#if canImport(AppKit)
import AppKit
import RichTextEditorCore

@available(macOS 12, *)
extension DocumentCanvasView {
    /// Wraps a mutation: snapshots the document + selection, brackets the change, runs `body`,
    /// registers a self-re-registering undo, and refreshes layout/display. This is the single entry
    /// point for every editing operation (typing, structural, list).
    func editing(coalescing: UndoCoalescing = .none, _ body: () -> Void) {
        if !isUpdatingTextInput {
            unmarkText()
        }
        let continuesComposition = isUpdatingTextInput && hasMarkedText()
        let before = currentModelBlocks()
        let beforeAnchor = anchor, beforeHead = head
        // Does this edit CONTINUE the open coalescing run? Same kind, a collapsed caret (not a
        // selection-replace), landing exactly where the last keystroke left off. If so we skip
        // registerUndo entirely — the snapshot taken at the run's START already captures the pre-run
        // document, so one undo reverts the whole run. A caret move / kind switch / selection-replace
        // fails this test and starts a fresh step.
        let continuesRun = coalescing != .none && beforeAnchor == beforeHead
            && (openUndoRun.map { $0.kind == coalescing && $0.caret == beforeHead } ?? false)
        body()
        if !continuesRun && !continuesComposition {
            registerUndo(snapshot: before, anchor: beforeAnchor, head: beforeHead)
        }
        // Open / extend / close the coalescing run for the NEXT edit: a coalescable edit that left a
        // collapsed caret opens (or extends) a run at the new caret; anything else closes it.
        openUndoRun = (coalescing != .none && anchor == head) ? (coalescing, head) : nil
        recomputeDocumentHasSpoilers()                   // model may have changed: refresh the fast-path gate
        scheduleSyntaxHighlightPass()                    // debounced; a burst of keystrokes fires one pass
        invalidateIntrinsicContentSize(); needsLayout = true; needsDisplay = true
        // Scroll-follow the caret only when this edit actually MOVED the selection (typing, structural
        // edits). A format-only edit on an untouched selection must not yank the viewport back to an
        // off-screen caret.
        if !isUpdatingTextInput {
            notifySelectionChanged(caretMoved: anchor != beforeAnchor || head != beforeHead)
        }
    }

    /// Restores a whole-document snapshot, then re-registers the inverse for redo (Phase 1 trick).
    /// Snapshots in `CanvasModelBlock` (not `[Block]`) so macOS-only media blocks survive undo/redo.
    func registerUndo(snapshot blocks: [CanvasModelBlock], anchor: Int, head: Int) {
        effectiveUndoManager?.registerUndo(withTarget: self) { target in
            let redo = target.currentModelBlocks()
            let redoAnchor = target.anchor, redoHead = target.head
            target.setModelBlocks(blocks, width: target.effectiveWidth)
            target.anchor = min(anchor, target.documentSize)
            target.head = min(head, target.documentSize)
            target.registerUndo(snapshot: redo, anchor: redoAnchor, head: redoHead)
            target.invalidateIntrinsicContentSize(); target.needsLayout = true
            target.needsDisplay = true; target.notifySelectionChanged()
        }
    }

    /// The structural-edit engine, now operating on the `BlockStack` that owns the selection (the
    /// root stack, or a table cell's stack — resolved via `activeStack`). Replaces the global range
    /// `[from, to)` with `text` WITHIN that one stack. Same-block: in-place. Cross-block: split/merge
    /// (paragraph↔paragraph) or truncate (image endpoint), dropping covered middle boxes. The endpoints
    /// MUST live in the same stack — callers guarantee this (top-level OR same-cell); a cross-stack
    /// range goes to `applyMultiRegionClear` instead. NOT wrapped in undo — call inside `editing { … }`.
    /// Precondition: `text` must not contain a newline — callers split paragraphs first (see
    /// `insertParagraphBreak`); multi-line paste is deferred (Phase 2c).
    func applyReplace(globalFrom: Int, globalTo: Int, text: String) {
        guard !boxes.isEmpty else { return }
        let lo = clampGlobal(min(globalFrom, globalTo))
        let hi = clampGlobal(max(globalFrom, globalTo))
        guard let start = activeStack(at: lo), let end = activeStack(at: hi), start.stack === end.stack else { return }
        let stack = start.stack

        if start.index == end.index {
            let b = start.box
            let attrs = typingAttributesAtGlobal(b.textStart + start.local)
            // A replace whose range covers a CODE block's whole node — its LEADING language line as well as
            // its code — must not strand the old language on the block. `activeStack`/`resolveBox` collapse
            // both endpoints onto the code region (the language is a second leaf region, off their radar),
            // so the replace below only touches the code layout and the language survives a selection the
            // user made over it.
            clearCodeLanguageIfCovered(b, lo: lo, hi: hi)
            b.textLayout.replace(start: start.local, end: end.local,
                                 with: NSAttributedString(string: text, attributes: attrs))
            recomputeSpans()
            let caret = b.textStart + start.local + (text as NSString).length
            anchor = caret; head = caret
            return
        }

        // Cross-block. Paragraph↔paragraph: the existing split/merge (keeps 2b behavior).
        if let sB = start.box as? BlockBox, let eB = end.box as? BlockBox {
            let headPart = sB.currentParagraph().split(at: start.local, newID: BlockID.generate()).0
            let tailPart = eB.currentParagraph().split(at: end.local, newID: BlockID.generate()).1
            var headRuns = headPart.runs
            if !text.isEmpty {
                let ca = mapper.characterAttributes(from: typingAttributesAtGlobal(start.box.textStart + start.local))
                headRuns.append(TextRun(text: text, attributes: ca))
            }
            var merged = headPart
            merged.runs = headRuns
            merged = merged.merging(tailPart)
            let mergedBox = BlockBox(paragraph: merged, mapper: sB.mapper, width: effectiveWidth)
            var newBoxes = stack.boxes
            newBoxes.replaceSubrange(start.index...end.index, with: [mergedBox])
            stack.boxes = newBoxes
            recomputeSpans()
            let caret = mergedBox.textStart + headPart.utf16Count + (text as NSString).length
            anchor = caret; head = caret
            return
        }
        // An image is at an endpoint. v1 bound (Phase 2c spec): TRUNCATE each endpoint's text region
        // (start keeps [0, start.local) + inserted text; end keeps [end.local, …)) and drop ONLY the
        // strictly-covered middle boxes. Do NOT merge across the block-type boundary and do NOT remove
        // the endpoint boxes — a selection ending inside an image caption keeps that image with its
        // surviving caption suffix. (Removing end.box here would lose that kept suffix.) A selection
        // that fully covers an image makes it a middle box, which IS dropped below.
        // A code block at EITHER endpoint gets the same whole-node language clear as the same-box branch
        // above (Select-All in a multi-block document always makes the code block an ENDPOINT, never a
        // dropped middle box, so without this the emptied block keeps drawing — and sending — its old
        // language). Attrs are captured FIRST: clearing the language shrinks `code.textStart`, so reading
        // the global position afterwards would sample a stale axis.
        let startAttrs = typingAttributesAtGlobal(start.box.textStart + start.local)
        clearCodeLanguageIfCovered(start.box, lo: lo, hi: hi)
        clearCodeLanguageIfCovered(end.box, lo: lo, hi: hi)
        start.box.textLayout.replace(start: start.local, end: start.box.textLength,
                                     with: NSAttributedString(string: text, attributes: startAttrs))
        end.box.textLayout.replace(start: 0, end: end.local, with: NSAttributedString(string: ""))
        if end.index > start.index + 1 {
            var newBoxes = stack.boxes
            newBoxes.removeSubrange((start.index + 1)..<end.index)
            stack.boxes = newBoxes
        }
        recomputeSpans()
        let caret = start.box.textStart + start.local + (text as NSString).length
        anchor = caret; head = caret
    }

    /// Clears a CODE block's language when the range `[lo, hi]` covers the block's WHOLE node — its
    /// LEADING language line as well as its code. `activeStack`/`resolveBox` collapse both endpoints onto
    /// the code region (the language is a second leaf region, off their radar), so the replace engine only
    /// touches the code layout and the language would survive a selection the user made over it — visibly,
    /// since `selectionRects` highlights the language line, and in the model, since `currentCode()` reads
    /// it back. Called for the same-box branch AND for both endpoints of the cross-block truncate branch.
    func clearCodeLanguageIfCovered(_ box: any CanvasBlock, lo: Int, hi: Int) {
        guard let code = box as? CodeBlockBox, lo <= code.nodeStart,
              hi >= code.textStart + code.textLength else { return }
        code.languageLayout.replace(start: 0, end: code.languageLength,
                                    with: NSAttributedString(string: ""))
    }

    /// Removes the image box at `index`, placing the caret at the end of the previous block's text
    /// (or the start of the new first block's text region). Caller wraps this in `editing { … }`.
    func deleteImageBox(at index: Int) {
        guard boxes.indices.contains(index) else { return }
        var newBoxes = boxes
        newBoxes.remove(at: index)
        boxes = newBoxes
        recomputeSpans()
        let caret = index > 0 ? boxes[index - 1].textStart + boxes[index - 1].textLength
                              : (boxes.first?.textStart ?? 0)
        anchor = caret; head = caret
    }

    /// Removes the media block at `index` (file/audio/map atom). Caret lands at the end of the previous
    /// block, or the start of the first remaining block. Call inside `editing { }` so it's undoable (the
    /// snapshot preserves the media block, and the hosted view is rebuilt by the provider on undo).
    func deleteMediaBox(at index: Int) {
        guard boxes.indices.contains(index) else { return }
        var newBoxes = boxes
        newBoxes.remove(at: index)
        boxes = newBoxes
        recomputeSpans()
        let caret = index > 0 ? boxes[index - 1].textStart + boxes[index - 1].textLength
                              : (boxes.first?.textStart ?? 0)
        anchor = caret; head = caret
    }

    /// Resolves a global position to the innermost owning `BlockStack` — recursing through
    /// `BlockQuoteBox` children by token span, routing table cells through `cellStack`, and matching
    /// leaf boxes by their single leaf region. Handles top-level, in-cell, in-quote (incl. nested
    /// quotes), and quote-inside-table scenarios in one uniform recursive descent.
    ///
    /// For positions that fall outside all leaf regions (document start/end boundary, structural gap),
    /// falls back to `resolveBox`'s snapping behaviour. Container-structural boundary positions (at a
    /// `TableBlockBox` or `BlockQuoteBox` boundary) are filtered out of the fallback and return nil, so
    /// callers that handle them separately (`caretSnappedIntoContainer`,
    /// `selectionEndpointsEditableTopLevel`) still own that routing.
    func activeStack(at pos: Int) -> (stack: BlockStack, box: CanvasBlock, local: Int, index: Int)? {
        func descend(_ stack: BlockStack) -> (stack: BlockStack, box: CanvasBlock, local: Int, index: Int)? {
            for (i, b) in stack.boxes.enumerated() {
                // A block-quote child stack: descend by TOKEN SPAN (pos strictly inside the container).
                if let bq = b as? BlockQuoteBox, pos > b.nodeStart, pos < b.nodeStart + b.nodeSize {
                    return descend(bq.children)
                }
                // A table: keep the existing per-cell resolver.
                if let t = b as? TableBlockBox, pos > b.nodeStart, pos < b.nodeStart + b.nodeSize {
                    return t.cellStack(containing: pos)
                }
                // A leaf text box (paragraph/code/pullQuote): match by its PRIMARY text region — the one
                // starting at `textStart` — NOT by `leafRegions().first`. A code box's FIRST region is its
                // LANGUAGE line, and resolving a language position here would hand every caller a
                // language-relative `local` to apply to the box's CODE layout (a newline spliced into the
                // code at the wrong offset). Selecting by `textStart` makes a language position return nil
                // instead, exactly as a quote-author position already does, which leaves every existing
                // `box is CodeBlockBox` branch inert in the language line by construction rather than by
                // each site remembering to ask.
                //
                // NB the naive `pos >= b.textStart, pos <= b.textStart + b.textLength` is NOT equivalent:
                // container boxes (block quote / table) report a degenerate `textStart == nodeStart,
                // textLength == 0`, so that form would newly match them at exactly `nodeStart` and return
                // a container with `local == 0`, where today that position correctly falls through to the
                // fallback (which refuses containers).
                if let primary = b.leafRegions().first(where: { $0.globalStart == b.textStart }),
                   pos >= primary.globalStart, pos <= primary.globalStart + primary.length {
                    return (stack, b, pos - primary.globalStart, i)
                }
            }
            return nil
        }
        if let hit = descend(root) { return hit }
        // The fallback's `resolveBox` walks TOP-LEVEL boxes only, so a position INSIDE a container that
        // `descend` could not place — a nested code block's language line, a nested quote's author — would
        // snap to some unrelated top-level box and hand callers an offset into the WRONG block. Refuse
        // container-internal positions up front (mirrors the iOS pre-guard; macOS has no `DetailsBox`).
        guard !isInsideBlockQuote(pos), !isInsideTable(pos),
              let r = resolveBox(at: pos), !(r.box is TableBlockBox), !(r.box is BlockQuoteBox), !(r.box is ButtonRowBox) else { return nil }
        // The fallback snaps STRUCTURAL boundaries (before the first leaf, past the last, inter-block
        // gaps). A position inside one of the box's own NON-PRIMARY regions — a code block's language
        // line, a quote's author line — is not a boundary, and `resolveBox` maps it to the box with a
        // clamped `local` that callers would apply to `box.textLayout`, the PRIMARY layout. Refuse it, so
        // such a position resolves to no active stack at all.
        if let (region, _) = leafRegion(containingGlobal: pos),
           region.globalStart != r.box.textStart,
           r.box.leafRegions().contains(where: { $0.globalStart == region.globalStart }) {
            return nil
        }
        return (root, r.box, r.local, r.index)
    }

    /// The stack, box and index of the `CodeBlockBox` with `id`, searched recursively (a code block can
    /// sit inside a block quote or a table cell). Needed because a caret in a code block's LANGUAGE line
    /// resolves to no `activeStack` — by design — so a language-line branch cannot get at its own box the
    /// usual way.
    func stackContainingCodeBox(id: BlockID) -> (stack: BlockStack, box: CodeBlockBox, index: Int)? {
        func search(_ stack: BlockStack) -> (stack: BlockStack, box: CodeBlockBox, index: Int)? {
            for (i, b) in stack.boxes.enumerated() {
                if let c = b as? CodeBlockBox, c.id == id { return (stack, c, i) }
                if let bq = b as? BlockQuoteBox, let hit = search(bq.children) { return hit }
                if let t = b as? TableBlockBox {
                    for cell in t.cells.flatMap({ $0 }) { if let hit = search(cell) { return hit } }
                }
            }
            return nil
        }
        return search(root)
    }

    /// True when a range can be safely edited by the top-level cross-block engine: neither endpoint
    /// is inside a cell or block-quote child, and neither endpoint resolves to a table or block-quote
    /// box. (Spanning one as a covered middle box is fine — the merge drops it.)
    func selectionEndpointsEditableTopLevel(_ a: Int, _ b: Int) -> Bool {
        if isInsideTable(a) || isInsideBlockQuote(a) || isInsideTable(b) || isInsideBlockQuote(b) { return false }
        if let ra = resolveBox(at: a), ra.box is TableBlockBox || ra.box is BlockQuoteBox || ra.box is ButtonRowBox { return false }
        if let rb = resolveBox(at: b), rb.box is TableBlockBox || rb.box is BlockQuoteBox || rb.box is ButtonRowBox { return false }
        return true
    }

    /// True when both positions resolve to the **same** owning `BlockStack` — the same table cell's
    /// stack, or the same block-quote child stack — so the full (stack-scoped) `applyReplace` engine
    /// can edit within that container, exactly like top-level.
    func sameOwningStack(_ a: Int, _ b: Int) -> Bool {
        guard let sa = owningStack(at: a), let sb = owningStack(at: b) else { return false }
        return sa === sb
    }

    /// The `BlockStack` that owns `pos`, tolerating a NON-PRIMARY leaf region — a quote author, a code
    /// block's language line. `activeStack` deliberately refuses those (its `local` would be meaningless
    /// against the box's PRIMARY layout), but stack ownership is well-defined for every region, and a
    /// caller that only needs "which stack is this position in" must not inherit that refusal — Select-All
    /// over a box whose end endpoint lands on such a region would otherwise stop resolving.
    func owningStack(at pos: Int) -> BlockStack? {
        if let active = activeStack(at: pos) { return active.stack }
        func search(_ stack: BlockStack) -> BlockStack? {
            for b in stack.boxes {
                // Containers first, so a NESTED box's region reports its own stack rather than the outer
                // one (a container's `leafRegions()` includes its children's).
                if let bq = b as? BlockQuoteBox, let hit = search(bq.children) { return hit }
                if let t = b as? TableBlockBox {
                    for cell in t.cells.flatMap({ $0 }) { if let hit = search(cell) { return hit } }
                }
                if b.leafRegions().contains(where: { pos >= $0.globalStart && pos <= $0.globalStart + $0.length }) {
                    return stack
                }
            }
            return nil
        }
        return search(root)
    }

    /// True if `pos` is inside a block-quote container. Mirrors `isInsideTable` over `BlockQuoteBox`
    /// leaf regions; `BlockQuoteBox.leafRegions()` recurses into nested quotes, so checking the
    /// top-level `BlockQuoteBox`es is sufficient.
    func isInsideBlockQuote(_ pos: Int) -> Bool {
        for box in boxes where box is BlockQuoteBox {
            for r in box.leafRegions() where pos >= r.globalStart && pos <= r.globalStart + r.length { return true }
        }
        return false
    }

    /// THE single routing point for replacing a (non-empty) selection `[from, to)` with `text`. A
    /// selection whose endpoints share a stack (both top-level, or both in one cell) goes to the
    /// stack-scoped `applyReplace`; a selection that crosses stack boundaries (cross-cell, cell↔body,
    /// cross-table, or an endpoint resting on a table box) goes to the structure-preserving
    /// `applyMultiRegionClear`. Every selection-replacing edit (typing, delete, paste, replace-witness,
    /// insert-image's pre-clear) MUST route through here so none drives a cross-stack range into
    /// `applyReplace`'s same-stack guard (which would silently no-op). Caller wraps in `editing { … }`.
    func applySelectionReplace(globalFrom: Int, globalTo: Int, text: String) {
        // A replace whose (expanded) range lies entirely within ONE region the top-level engine cannot
        // resolve — a quote AUTHOR line, or a code block's LANGUAGE line. Both are a SECOND leaf region on
        // their box, off `activeStack`'s radar, so `applyReplace` below either mis-resolves the endpoints
        // or refuses them outright and silently no-ops. Route it region-aware, like a cell.
        if let (rf, _) = leafRegion(containingGlobal: clampGlobal(min(globalFrom, globalTo))),
           regionIsOffTheTopLevelEngine(rf),
           let (rt, _) = leafRegion(containingGlobal: clampGlobal(max(globalFrom, globalTo))),
           rt.globalStart == rf.globalStart {
            applyLeafReplace(globalFrom: globalFrom, globalTo: globalTo, text: text)
            return
        }
        // A range that STRADDLES such a region and anything else — the language line into the code text,
        // the paragraph above into the language line, the language line into the following block. One
        // endpoint resolves to no `activeStack` (by design), so `applyReplace` below refuses the whole
        // edit: the keystroke is dropped, nothing is deleted, and the selection never collapses — the user
        // sees a live highlight no key can touch. Clear it region-aware instead, exactly like a cross-stack
        // range: every touched region loses its covered text and the replacement lands in the region owning
        // `globalFrom`. Keyed on `regionIsOffTheTopLevelEngine`, so the quote AUTHOR line — the same class
        // of off-engine leaf, with the same hole — is covered by the one arm.
        // (Placement is load-bearing: `selectionEndpointsEditableTopLevel` is true for a top-level code
        // block and is the left operand of the `||` below, so it short-circuits and fires first.)
        if let (a, _) = leafRegion(containingGlobal: clampGlobal(min(globalFrom, globalTo))),
           let (b, _) = leafRegion(containingGlobal: clampGlobal(max(globalFrom, globalTo))),
           a.globalStart != b.globalStart,
           regionIsOffTheTopLevelEngine(a) || regionIsOffTheTopLevelEngine(b) {
            // Replacement text landing in a LANGUAGE anchor is flattened, like the wholly-inside-language
            // paths in `commitText`: a `.Pre` language is a single-line string, and an interior "\n" would
            // reach the model where `currentCode()`'s edge-trim cannot see it.
            var replacement = text
            if case .codeLanguage = a.ref { replacement = text.replacingOccurrences(of: "\n", with: " ") }
            applyMultiRegionClear(globalFrom: globalFrom, globalTo: globalTo, text: replacement)
            return
        }
        if selectionEndpointsEditableTopLevel(globalFrom, globalTo) || sameOwningStack(globalFrom, globalTo) {
            applyReplace(globalFrom: globalFrom, globalTo: globalTo, text: text)
        } else {
            applyMultiRegionClear(globalFrom: globalFrom, globalTo: globalTo, text: text)
        }
    }

    /// True for a leaf region the TOP-LEVEL replace engine cannot resolve: a second region on its box,
    /// outside the box's primary `textStart`/`textLength` extent and off `activeStack`'s radar. A range
    /// inside one must be edited through `applyLeafReplace` or it silently no-ops.
    ///
    /// Exhaustive on purpose — no `default`. A new `TextNodeRef` case must state which side it is on here,
    /// because getting it wrong produces an edit that quietly does nothing rather than a build error.
    func regionIsOffTheTopLevelEngine(_ region: LeafTextRegion) -> Bool {
        switch region.ref {
        case .quoteAuthor, .codeLanguage:
            return true
        case .paragraph, .caption, .code, .pullQuote, .detailsTitle:
            return false
        }
    }

    /// If a collapsed caret resolves to a table or block-quote box — a structural boundary such as the
    /// position just before/after one of these containers — returns the nearest in-container text start
    /// so the edit routes through that container's stack. Returns `pos` unchanged when it is not at
    /// such a boundary. Prevents writing through a container's degenerate `textLayout` (which would
    /// silently drop the keystroke).
    func caretSnappedIntoContainer(_ pos: Int) -> Int {
        guard let r = resolveBox(at: pos) else { return pos }
        if !isInsideTable(pos), let table = r.box as? TableBlockBox {
            let snap = pos <= table.nodeStart
                ? table.cellTextStart(row: 0, column: 0)
                : table.cellTextStart(row: table.rowCount - 1, column: table.columnCount - 1)
            return snap ?? pos
        }
        if !isInsideBlockQuote(pos), let bq = r.box as? BlockQuoteBox,
           let first = bq.children.boxes.first?.leafRegions().first {
            return first.globalStart
        }
        return pos
    }

    /// Splits the caret's paragraph at the caret, within whatever `BlockStack` owns the caret (root
    /// or a cell). Deletes any selection first (bounded if it touches a table). Caret → new block start.
    /// When `newParagraphAsBody` is set, the new (lower) paragraph is forced to a plain body paragraph
    /// (no list, body style) — Shift+Enter starts a fresh paragraph that breaks out of a list/heading/
    /// quote, regardless of the current block's type.
    func insertParagraphBreak(newParagraphAsBody: Bool = false) {
        guard !boxes.isEmpty else { return }
        // A caret parked on a button-row atom: Enter opens an empty body paragraph AFTER the row —
        // the split machinery below needs a paragraph box and would silently no-op on the text-free row.
        if selFrom == selTo, let row = buttonRowBox(atAtom: head) ?? buttonRowBox(atBoundary: head),
           let i = boxIndex(of: row) {
            editing { insertParagraphAfterButtonRow(at: i, text: "") }
            return
        }
        editing {
            if selFrom != selTo {
                applySelectionReplace(globalFrom: selFrom, globalTo: selTo, text: "")
            }
            guard let active = activeStack(at: head), let p = active.box as? BlockBox else { return }
            let (upper, lower) = p.currentParagraph().split(at: active.local, newID: BlockID.generate())
            let lowerParagraph = newParagraphAsBody
                ? ParagraphBlock(id: lower.id, style: .body, paragraph: .default, list: nil, runs: lower.runs)
                : lower
            let upperBox = BlockBox(paragraph: upper, mapper: p.mapper, width: effectiveWidth)
            let lowerBox = BlockBox(paragraph: lowerParagraph, mapper: p.mapper, width: effectiveWidth)
            var newBoxes = active.stack.boxes
            newBoxes.replaceSubrange(active.index...active.index, with: [upperBox, lowerBox])
            active.stack.boxes = newBoxes
            recomputeSpans()
            anchor = lowerBox.textStart; head = lowerBox.textStart
        }
    }

    /// Merges `stack.boxes[upperIndex+1]` into `stack.boxes[upperIndex]` (both paragraphs), within the
    /// given stack. Caret lands at the join. Caller wraps in `editing { }`.
    func mergeParagraphs(in stack: BlockStack, upperIndex: Int) {
        guard stack.boxes.indices.contains(upperIndex), stack.boxes.indices.contains(upperIndex + 1),
              let upper = stack.boxes[upperIndex] as? BlockBox,
              let lower = stack.boxes[upperIndex + 1] as? BlockBox else { return }
        let joinLocal = upper.currentParagraph().utf16Count
        let merged = upper.currentParagraph().merging(lower.currentParagraph())
        let mergedBox = BlockBox(paragraph: merged, mapper: upper.mapper, width: effectiveWidth)
        var newBoxes = stack.boxes
        newBoxes.replaceSubrange(upperIndex...(upperIndex + 1), with: [mergedBox])
        stack.boxes = newBoxes
        recomputeSpans()
        let caret = mergedBox.textStart + joinLocal
        anchor = caret; head = caret
    }

    /// Inserts an image block (with an empty caption) at the caret, splitting the caret's paragraph
    /// if mid-text. The caller has already registered the image with the canvas's `imageProvider`
    /// under `assetID`. Caret lands in the new image's caption.
    func insertImage(_ image: NSImage, naturalSize: CGSize, assetID: String) {
        guard !boxes.isEmpty else { return }
        editing {
            if selFrom != selTo { applySelectionReplace(globalFrom: selFrom, globalTo: selTo, text: "") }
            guard let pos = resolveBox(at: head) else { return }
            let imageBlock = MediaBlock(id: BlockID.generate(), kind: .image, mediaID: assetID,
                                        naturalSize: Size2D(width: Double(naturalSize.width),
                                                            height: Double(naturalSize.height)))
            // Images are hosted views now (like video), resolved from `mediaID` via the media provider.
            let imageBox = MediaBlockBox(media: imageBlock, mapper: mapper, width: effectiveWidth)
            var newBoxes = boxes
            if let p = pos.box as? BlockBox, pos.local > 0, pos.local < p.textLength {
                // split the paragraph and insert the image between the halves
                let (upper, lower) = p.currentParagraph().split(at: pos.local, newID: BlockID.generate())
                let upperBox = BlockBox(paragraph: upper, mapper: mapper, width: effectiveWidth)
                let lowerBox = BlockBox(paragraph: lower, mapper: mapper, width: effectiveWidth)
                let replacement: [any CanvasBlock] = [upperBox, imageBox, lowerBox]
                newBoxes.replaceSubrange(pos.index...pos.index, with: replacement)
            } else if pos.local == 0 {
                newBoxes.insert(imageBox, at: pos.index)        // before the caret's block
            } else {
                newBoxes.insert(imageBox, at: pos.index + 1)    // after the caret's block
            }
            boxes = newBoxes
            recomputeSpans()
            anchor = imageBox.textStart; head = imageBox.textStart
        }
    }

    /// Inserts a new body paragraph immediately before the (top-level) image box at `index`, containing
    /// `text` (empty for a bare newline). Caret lands at the end of the inserted text in the new
    /// paragraph. Mirrors `insertImage`'s block-insert. Caller wraps this in `editing { … }`.
    func insertParagraphBeforeImage(at index: Int, text: String) {
        guard boxes.indices.contains(index) else { return }
        let runs = text.isEmpty ? [] : [TextRun(text: text)]
        let newBox = BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), runs: runs),
                              mapper: mapper, width: effectiveWidth)
        var newBoxes = boxes
        newBoxes.insert(newBox, at: index)
        boxes = newBoxes
        recomputeSpans()
        let caret = newBox.textStart + (text as NSString).length
        anchor = caret; head = caret
    }

    /// Typing (or Enter) with the caret parked on a button-row atom opens a body paragraph AFTER the
    /// row, caret in it — the row is TEXT-FREE, so the generic replace/split machinery below would
    /// silently drop the keystroke. Mirrors `insertParagraphBeforeImage` (the image-gap analogue).
    /// Call inside `editing { }`.
    func insertParagraphAfterButtonRow(at index: Int, text: String) {
        guard boxes.indices.contains(index) else { return }
        let runs = text.isEmpty ? [] : [TextRun(text: text)]
        let newBox = BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), runs: runs),
                              mapper: mapper, width: effectiveWidth)
        var newBoxes = boxes
        newBoxes.insert(newBox, at: index + 1)
        boxes = newBoxes
        recomputeSpans()
        let caret = newBox.textStart + (text as NSString).length
        anchor = caret; head = caret
    }

    /// True when Return should EXIT the code block at the caret instead of adding another line: a
    /// collapsed caret at the very end of a code block whose text is empty or already ends in "\n"
    /// (i.e. the caret sits on the block's trailing blank line — the second Return of a double-return).
    /// (Block quotes exit via `blockQuoteEmptyTrailingChildExit`; pull quotes via their own branch.)
    func caretAtQuoteTrailingBlankLine() -> Bool {
        guard selFrom == selTo, !isInsideTable(head), let pos = resolveBox(at: head),
              pos.local == pos.box.textLength else { return false }
        guard pos.box is CodeBlockBox || pos.box is PullQuoteBox else { return false }
        let s = pos.box.textLayout.attributedString.string as NSString
        return s.length == 0 || s.hasSuffix("\n")
    }

    /// Double-return's code exit: an EMPTY block un-codes in place; otherwise the trailing "\n" (the
    /// blank line the first Return added) is removed and an empty body paragraph opens AFTER the
    /// block, caret there.
    func exitQuoteBelow() {
        guard let pos = resolveBox(at: head) else { return }
        if pos.box.textLength == 0 {
            if pos.box is CodeBlockBox {
                makeCodeBlock()
            } else if pos.box is PullQuoteBox {
                makePullQuote()
            } else {
                setParagraphStyle(.body)
            }
            return
        }
        editing {
            let s = pos.box.textLayout.attributedString.string as NSString
            if s.hasSuffix("\n") {
                pos.box.textLayout.replace(start: s.length - 1, end: s.length, with: NSAttributedString(string: ""))
            }
            insertParagraphAfterBlock(at: pos.index)
        }
    }

    /// True when Return should EXIT the block quote: a collapsed caret at the very end of the LAST
    /// child of its enclosing quote, whose text is empty or already ends in "\n" (the blank line the
    /// first Return added — the second Return of a double-return).
    func caretAtBlockQuoteTrailingBlankLine() -> Bool {
        guard selFrom == selTo, isInsideBlockQuote(head),
              let active = activeStack(at: head), let child = active.box as? BlockBox,
              active.local == child.textLength,
              let (bq, _, _) = enclosingBlockQuote(at: head),
              bq.children.boxes.last === child else { return false }
        let s = child.textLayout.attributedString.string as NSString
        return s.length == 0 || s.hasSuffix("\n")
    }

    /// Double-return's block-quote exit: trims the trailing "\n" from the last child (an EMPTY lone
    /// child exits via `blockQuoteEmptyTrailingChildExit` instead) and opens an empty body paragraph
    /// AFTER the quote, caret there.
    func exitBlockQuoteBelow() {
        guard let (bqBox, parentStack, index) = enclosingBlockQuote(at: head),
              let child = bqBox.children.boxes.last as? BlockBox else { return }
        if child.textLength == 0 {
            _ = blockQuoteEmptyTrailingChildExit()
            return
        }
        editing {
            let s = child.textLayout.attributedString.string as NSString
            if s.hasSuffix("\n") {
                child.textLayout.replace(start: s.length - 1, end: s.length, with: NSAttributedString(string: ""))
            }
            let body = BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), style: .body, runs: []),
                                mapper: mapper, width: effectiveWidth)
            parentStack.boxes.insert(body, at: index + 1)
            recomputeSpans()
            anchor = body.textStart; head = body.textStart
        }
    }

    /// Inserts a fresh empty body paragraph immediately AFTER the (top-level) box at `index`, caret →
    /// its start. Used by Shift+Enter to step out of a media caption into a new paragraph. Caller wraps
    /// in `editing { … }`.
    func insertParagraphAfterBlock(at index: Int) {
        guard boxes.indices.contains(index) else { return }
        let newBox = BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), runs: []),
                              mapper: mapper, width: effectiveWidth)
        var newBoxes = boxes
        newBoxes.insert(newBox, at: index + 1)
        boxes = newBoxes
        recomputeSpans()
        anchor = newBox.textStart; head = newBox.textStart
    }

    /// Inserts a fresh empty body paragraph as the document's FIRST block and lands the caret in it. Backs
    /// Up-arrow's "escape above a trapped leading block" — the only way to start a normal paragraph above a
    /// non-body first block (quote / heading / list / code / table / media). Caller wraps in `editing { }`.
    func insertEmptyBodyParagraphAtTop() {
        let newBox = BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), runs: []),
                              mapper: mapper, width: effectiveWidth)
        var newBoxes = boxes
        newBoxes.insert(newBox, at: 0)
        boxes = newBoxes
        recomputeSpans()
        anchor = newBox.textStart; head = newBox.textStart
    }

    /// In-place text replace within the leaf region's layout (used for typing inside cells, and as
    /// the same-leaf fast path generally). Recomputes spans. Caller wraps in `editing { }`.
    func applyLeafReplace(globalFrom: Int, globalTo: Int, text: String) {
        guard let (region, _) = leafRegion(containingGlobal: clampGlobal(min(globalFrom, globalTo))) else { return }
        let lo = clampGlobal(min(globalFrom, globalTo)) - region.globalStart
        let hi = min(clampGlobal(max(globalFrom, globalTo)) - region.globalStart, region.length)
        guard lo >= 0, hi >= lo else { return }
        let attrs = typingAttributeDict(region: region, atLocal: lo)
        region.layout.replace(start: lo, end: hi, with: NSAttributedString(string: text, attributes: attrs))
        recomputeSpans()
        let caret = region.globalStart + lo + (text as NSString).length
        anchor = caret; head = caret
    }

    /// Structure-preserving clear of a selection that crosses `BlockStack` boundaries (cross-cell,
    /// cell↔body, cross-table). Clears the covered text in EVERY touched leaf region (paragraph or
    /// image caption), and lands any replacement `text` in the region owning **selFrom** (its kept
    /// prefix + text), exactly as a single-region replace would. Never removes a box, cell, row, or the
    /// grid — a fully-covered cell keeps an empty paragraph; a covered image keeps its atom (only its
    /// caption clears). One `recomputeSpans()`; caret always collapses to selFrom (+ text length), even
    /// when the selection covered only empty regions (so a keystroke is never lost / the selection never
    /// sticks). Mirrors `selectionRects` so what clears == what was highlighted. Caller wraps in `editing { … }`.
    func applyMultiRegionClear(globalFrom: Int, globalTo: Int, text: String) {
        let lo = clampGlobal(min(globalFrom, globalTo))
        let hi = clampGlobal(max(globalFrom, globalTo))
        guard lo < hi else { return }
        // The region owning selFrom is where replacement text lands (it may be empty, hence not in
        // `touched`). Capture its attrs before any clearing mutates it.
        let anchorRegion = leafRegion(containingGlobal: lo)
        let insertAttrs = anchorRegion.map { typingAttributeDict(region: $0.region, atLocal: $0.local) } ?? [:]
        let touched: [(region: LeafTextRegion, rLo: Int, rHi: Int)] = allLeafRegions().compactMap { r in
            let a = max(lo, r.globalStart), b = min(hi, r.globalStart + r.length)
            guard a < b else { return nil }
            return (r, a - r.globalStart, b - r.globalStart)
        }
        var insertedIntoAnchor = false
        for t in touched {
            let isAnchor = (anchorRegion?.region.layout) === t.region.layout
            let s = isAnchor ? text : ""
            let attrs: [NSAttributedString.Key: Any] = isAnchor ? insertAttrs : [:]
            t.region.layout.replace(start: t.rLo, end: t.rHi, with: NSAttributedString(string: s, attributes: attrs))
            if isAnchor { insertedIntoAnchor = true }
        }
        // The selFrom region had no covered text (e.g. an empty start cell), so it wasn't cleared
        // above — insert `text` there directly so the keystroke isn't lost.
        if !insertedIntoAnchor, !text.isEmpty, let a = anchorRegion {
            a.region.layout.replace(start: a.local, end: a.local,
                                    with: NSAttributedString(string: text, attributes: insertAttrs))
        }
        recomputeSpans()
        // selFrom's region start is unaffected by the edit (nothing before lo changed), so this is
        // valid post-recompute. With no owning region (range in a structural gap), just collapse to lo.
        let caret = anchorRegion.map { $0.region.globalStart + $0.local + (text as NSString).length } ?? clampGlobal(lo)
        anchor = caret; head = caret
    }

    /// True if `pos` is inside a table (its owning top-level box is a `TableBlockBox`).
    func isInsideTable(_ pos: Int) -> Bool {
        for box in boxes where box is TableBlockBox {
            for r in box.leafRegions() where pos >= r.globalStart && pos <= r.globalStart + r.length { return true }
        }
        return false
    }

    func placeGapCursorBeforeFirstImage() {
        guard let img = boxes.first(where: { $0 is ImageBlockBox }) else { return }
        window?.makeFirstResponder(self)
        anchor = img.nodeStart; head = img.nodeStart
        needsDisplay = true; notifySelectionChanged()
    }

    // MARK: - Text commit entry point (was UIKeyInput.insertText)

    /// The text-commit entry point called by `NSTextInputClient.insertText(_:replacementRange:)` and
    /// `setMarkedText`. Contains the full typing routing logic from the original UIKeyInput.insertText,
    /// but WITHOUT the `"\n"` branch — Enter now routes via `insertNewline(_:)`.
    func commitText(_ text: String) {
        clearTableSelection()
        selectedCollageTile = nil                        // typing clears a collage tile selection
        // Caret on an image's gap cursor → open a new body paragraph immediately before the image
        // (rather than letting the text fall into the caption). Symmetric to deleteBackward's gap branch.
        if selFrom == selTo, let img = imageBox(atGap: head), let i = boxIndex(of: img) {
            editing { insertParagraphBeforeImage(at: i, text: text) }
            return
        }
        // Caret parked on a button-row atom (a pill or the row's boundary slot): typing opens a body
        // paragraph AFTER the row — the row is text-free, so the generic replace below would drop the
        // keystroke and the caret would look stuck beside the pill.
        if selFrom == selTo, let row = buttonRowBox(atAtom: head) ?? buttonRowBox(atBoundary: head),
           let i = boxIndex(of: row) {
            editing { insertParagraphAfterButtonRow(at: i, text: text) }
            return
        }
        // NOTE: the standalone `if text == "\n"` branch from UIKeyInput.insertText is intentionally
        // REMOVED here — Enter arrives via insertNewline(_:) on macOS, not through commitText.
        // A soft line break ("\n" via Return) is its own undo step; plain characters coalesce.
        let kind: UndoCoalescing = text == "\n" ? .none : .typing
        if selFrom != selTo {
            // A selection wholly inside a pull-quote author line edits that region's own layout directly
            // (the top-level cross-block engine resolves by primary text region and is not author-aware).
            if isAuthorPosition(selFrom), isAuthorPosition(selTo) {
                editing(coalescing: kind) { applyLeafReplace(globalFrom: selFrom, globalTo: selTo, text: text); pendingFormatToggles.removeAll() }
                return
            }
            // A selection wholly inside a code block's LANGUAGE line: same second-region routing as the
            // author. Newlines are stripped — a `.Pre` language is a single-line string, and an interior
            // "\n" would land in the model where `currentCode()`'s edge-trim cannot reach it.
            if isCodeLanguagePosition(selFrom), isCodeLanguagePosition(selTo),
               leafRegion(containingGlobal: selFrom)?.region.globalStart == leafRegion(containingGlobal: selTo)?.region.globalStart {
                let flat = text.replacingOccurrences(of: "\n", with: " ")
                editing(coalescing: kind) { applyLeafReplace(globalFrom: selFrom, globalTo: selTo, text: flat); pendingFormatToggles.removeAll() }
                return
            }
            editing(coalescing: kind) { applySelectionReplace(globalFrom: selFrom, globalTo: selTo, text: text) }
            return
        }
        // A collapsed caret that resolves to a table or block-quote box (e.g. before a leading
        // container / after a trailing one) is a structural boundary — snap it into the nearest
        // in-container text start so the edit goes through that container's stack, never through the
        // container's degenerate textLayout (which would drop the keystroke).
        if !isInsideTable(head) && !isInsideBlockQuote(head),
           let r = resolveBox(at: head), r.box is TableBlockBox || r.box is BlockQuoteBox {
            let snapped = caretSnappedIntoContainer(head)
            anchor = snapped; head = snapped
        }
        // A collapsed caret in a pull-quote author line: type into that region's own layout (the author
        // has a distinct `authorLayout`; the top-level engine below edits only the primary quote text).
        if isAuthorPosition(head) {
            editing(coalescing: kind) { applyLeafReplace(globalFrom: selFrom, globalTo: selTo, text: text); pendingFormatToggles.removeAll() }
            return
        }
        // A collapsed caret in a code block's LANGUAGE line: like the quote author, it is a second leaf
        // region outside the box's primary `textStart`/`textLength` extent, so `activeStack` resolves nil
        // and `applyReplace` below would drop the keystroke. Route it through the region-aware path.
        // Newlines are stripped: a `.Pre` language is a single-line string, and a multi-line paste (which
        // reaches this path flattened — `insertFragment` refuses a language locus, so the clipboard falls
        // back to plain text) would otherwise put interior "\n"s in the model, where `currentCode()`'s
        // edge-trim cannot reach them.
        if isCodeLanguagePosition(head) {
            let flat = text.replacingOccurrences(of: "\n", with: " ")
            editing(coalescing: kind) { applyLeafReplace(globalFrom: selFrom, globalTo: selTo, text: flat); pendingFormatToggles.removeAll() }
            return
        }
        if isInsideTable(head) {
            // collapsed caret in a cell: text is in-place. Clear pending INSIDE editing (after the insert
            // consumes it) so the format-state change `editing` fires reflects the post-insert caret
            // WITHOUT the just-consumed pending — otherwise the toolbar flips state for one keystroke.
            editing(coalescing: kind) { applyLeafReplace(globalFrom: selFrom, globalTo: selTo, text: text); pendingFormatToggles.removeAll() }
            return
        }
        editing(coalescing: kind) { applyReplace(globalFrom: selFrom, globalTo: selTo, text: text); pendingFormatToggles.removeAll() }
    }

    // MARK: - Delete backward implementation (was UIKeyInput.deleteBackward)

    /// The actual delete-backward logic (was the UIKeyInput.deleteBackward body). All branches
    /// preserved: cell, gap-image, caption-start, table-boundary, cross-block.
    func performDeleteBackward() {
        guard !boxes.isEmpty else { return }
        // A click-selected collage tile → remove just that tile (not the whole group).
        if let sel = selectedCollageTile { removeCollageTile(group: sel.group, index: sel.index); return }
        // A structural row/column selection (the table handle) → Delete removes that row/column.
        if let sel = tableSelection {
            switch sel.kind {
            case .rows: deleteTableRow()
            case .columns: deleteTableColumn()
            }
            return
        }
        // A click-selected image (selection confined to its atom) → remove it.
        if let img = soleSelectedImageBlock(), let i = boxIndex(of: img) {
            editing { deleteImageBox(at: i) }
            return
        }
        // A click-selected media group (collage/slider) → remove the whole group.
        if let g = soleSelectedMediaGroupBlock(), let i = boxIndex(of: g) {
            editing { deleteMediaBox(at: i) }
            return
        }
        // A click-selected media block (selection confined to its atom) → remove the whole block.
        if let m = soleSelectedMediaBlock(), let i = boxIndex(of: m) {
            editing { deleteMediaBox(at: i) }
            return
        }
        // A caret on a button-row pill atom (or a structural range over rows) → delete one pill,
        // BEFORE the generic selection-replace, which would otherwise wipe whole rows at once.
        if deleteButtonPillIfNeeded() { return }
        // Backspace with a collapsed caret at the START of a code block's LANGUAGE line. The language is
        // the block's FIRST position, so there is nothing inside the block to merge into:
        //   • a WHOLLY empty block (no language, no code) is un-made to a body paragraph — the
        //     empty-code rule below, relocated to the block's new first position;
        //   • otherwise the caret steps OUT to the previous block's end, deleting nothing. When the code
        //     block is the document's first block there is nowhere to step, so it is a no-op.
        // Never merges the language into the previous block; never deletes a block that has content.
        // BEFORE the in-table / in-quote branches: a nested code block's language caret resolves to no
        // `activeStack`, so those branches would swallow it as a silent no-op.
        if selFrom == selTo, let (region, local) = leafRegion(containingGlobal: head),
           case let .codeLanguage(id) = region.ref, local == 0,
           let owner = stackContainingCodeBox(id: id) {
            if region.length == 0, owner.box.textLength == 0 {
                editing {
                    let body = BlockBox(paragraph: ParagraphBlock(id: owner.box.id, style: .body, runs: []),
                                        mapper: mapper, width: effectiveWidth)
                    var newBoxes = owner.stack.boxes
                    newBoxes.replaceSubrange(owner.index...owner.index, with: [body])
                    owner.stack.boxes = newBoxes
                    recomputeSpans()
                    anchor = body.textStart; head = body.textStart
                }
                return
            }
            let prev = prevTextPosition(before: region.globalStart)
            if prev != head { setCaret(global: prev) }
            return
        }
        // Backspace INSIDE a code block's language line (text before the caret): delete in the language
        // region. `activeStack` resolves nil there by design, so the generic paths below would mis-route
        // it. Mirrors the quote-author branch further down.
        if selFrom == selTo, let (region, local) = leafRegion(containingGlobal: head),
           case .codeLanguage = region.ref, local > 0 {
            editing(coalescing: .deleting) { applyLeafReplace(globalFrom: head - 1, globalTo: head, text: "") }
            return
        }
        if selFrom != selTo {
            let lo = selFrom
            let coveredMediaIDs = Set(mediaBoxesFullyCovered().map { $0.id })
            editing(coalescing: .deleting) {
                applySelectionReplace(globalFrom: selFrom, globalTo: selTo, text: "")
                // The cross-block text engine drops media that are MIDDLE boxes; remove any fully-covered
                // media (image / media / group) that survived as a selection endpoint (e.g. a leading/trailing
                // block on select-all).
                if !coveredMediaIDs.isEmpty {
                    var newBoxes = boxes.filter { box in
                        !((box is MediaBlockBox || box is ImageBlockBox || box is MediaGroupBlockBox || box is TableBlockBox || box is ButtonRowBox) && coveredMediaIDs.contains(box.id))
                    }
                    if newBoxes.isEmpty {
                        newBoxes = [BlockBox(paragraph: ParagraphBlock(id: BlockID.generate(), runs: []),
                                             mapper: mapper, width: effectiveWidth)]
                    }
                    boxes = newBoxes
                    recomputeSpans()
                    let caret = clampGlobal(lo)
                    anchor = caret; head = caret
                }
            }
            return
        }
        if isInsideTable(head) {
            guard let active = activeStack(at: head) else { return }
            if active.local > 0 {
                editing(coalescing: .deleting) { applyLeafReplace(globalFrom: head - 1, globalTo: head, text: "") }
            } else if active.index > 0 {
                editing { mergeParagraphs(in: active.stack, upperIndex: active.index - 1) }
            } else if let ti = boxes.firstIndex(where: { ($0 as? TableBlockBox)?.cellLocation(containing: head) != nil }),
                      let table = boxes[ti] as? TableBlockBox,
                      let loc = table.cellLocation(containing: head), loc.row == 0, loc.column == 0,
                      tableIsTextuallyEmpty(table) {
                // Backspace at the start of the FIRST cell of an otherwise-empty table removes the whole
                // table (mirrors Backspace in an empty quote/code block). A table holding content in any
                // cell is preserved — the caret just steps out (the branch below).
                editing { deleteTableBlock(at: ti) }
            } else {
                // Caret at the cell's first-paragraph start: move WITHOUT deleting to the previous text
                // position — the previous cell's end (row-major), or, at the table's FIRST cell, the end
                // of the block before the table. No-op only when the table is the document's first block
                // (nothing before — like Backspace at the very start of a document).
                let prev = prevTextPosition(before: head)
                if prev != head { setCaret(global: prev) }
            }
            return
        }
        if isInsideBlockQuote(head) {
            // Mirrors the in-cell shape above: in-place delete, sibling merge, or — at the start of the
            // quote's LONE child — unwrap one quote level (content preserved). A non-lone first child at
            // its start just steps the caret back out of the quote.
            guard let active = activeStack(at: head) else { return }
            if active.local > 0 {
                editing(coalescing: .deleting) { applyReplace(globalFrom: head - 1, globalTo: head, text: "") }
            } else if active.index > 0 {
                editing { mergeParagraphs(in: active.stack, upperIndex: active.index - 1) }
            } else if active.stack.boxes.count == 1, active.box is BlockBox {
                unwrapBlockQuoteLevel()
            } else {
                let prev = prevTextPosition(before: head)
                if prev != head { setCaret(global: prev) }
            }
            return
        }
        // Gap before a single-media atom → delete it.
        if let box = imageBox(atGap: head), let i = boxIndex(of: box) {
            editing { box is ImageBlockBox ? deleteImageBox(at: i) : deleteMediaBox(at: i) }
            return
        }
        // A pull-quote author line: handle Backspace here — the `resolveBox` ladder below matches a box
        // by its PRIMARY (quote) text region only and would misroute an author position to the following
        // block. Delete a character when past the author's start; at its start there is nothing to merge
        // into (the quote text lives in a separate region), so it's a no-op.
        if selFrom == selTo, let (region, local) = leafRegion(containingGlobal: head), case .quoteAuthor = region.ref {
            // Edit the author region's OWN layout via the region-aware replace (the top-level engine is
            // not author-aware). At the author's start there's nothing to merge into, so it's a no-op.
            if local > 0 { editing(coalescing: .deleting) { applyLeafReplace(globalFrom: head - 1, globalTo: head, text: "") } }
            return
        }
        guard let pos = resolveBox(at: head) else { return }
        if pos.box is MediaBlockBox || pos.box is MediaGroupBlockBox, pos.local == 0 {   // caption start → delete the (group) media block
            editing { deleteMediaBox(at: pos.index) }
        } else if pos.box is ImageBlockBox, pos.local == 0 {        // caption start → delete the image
            editing { deleteImageBox(at: pos.index) }
        } else if pos.local > 0 {
            editing(coalescing: .deleting) { applyReplace(globalFrom: head - 1, globalTo: head, text: "") }
        } else if pos.box is CodeBlockBox, pos.box.textLength == 0 {
            // Backspace in an EMPTY code block un-codes it back to an empty body paragraph — mirrors
            // Backspace in an empty quote just below (and the iOS editor's behavior).
            makeCodeBlock()
        } else if pos.box is PullQuoteBox, pos.box.textLength == 0 {
            // Backspace in an EMPTY pull quote removes it back to an empty body paragraph — the same
            // exit the empty quote/code blocks get. `makePullQuote` on an existing pull quote toggles
            // it off (wraps `editing { }` itself).
            makePullQuote()
        } else if let p = pos.box as? BlockBox, p.textLength == 0, p.listMembership != nil {
            // Backspace at the start of an EMPTY list item removes its list formatting (outdent, or
            // leave the list) instead of doing nothing — mirrors the iOS editor. These commands wrap
            // `editing { }` themselves, so they aren't wrapped again here.
            if let list = p.listMembership, list.level > 0 { outdent() } else { setList(nil) }
        } else if let p = pos.box as? BlockBox, p.textLength == 0, pos.index == 0, boxes.count > 1 {
            // Backspace in an EMPTY first paragraph removes it (nothing precedes it to merge into), landing
            // the caret at the start of the now-first block — the counterpart to Up-arrow inserting one above.
            editing {
                var nb = boxes; nb.remove(at: 0); boxes = nb
                recomputeSpans()
                let caret = firstRenderableGlobal()
                anchor = caret; head = caret
            }
        } else if pos.index > 0, boxes[pos.index - 1] is MediaBlockBox || boxes[pos.index - 1] is MediaGroupBlockBox || boxes[pos.index - 1] is ImageBlockBox {
            // Start of a paragraph after a media/image/group block. Backspace must NOT delete the media (you
            // delete media by selecting it, its leading gap, or its caption start). You can't merge text into
            // a caption, so move the caret to the caption's end; if this paragraph is empty, remove it first
            // so the empty line is actually deleted (mirrors the table-boundary behavior just below).
            let prev = prevTextPosition(before: head)
            if let p = pos.box as? BlockBox, p.textLength == 0, boxes.count > 1 {
                editing { var nb = boxes; nb.remove(at: pos.index); boxes = nb; recomputeSpans(); anchor = prev; head = prev }
            } else if prev != head {
                setCaret(global: prev)
            }
        } else if pos.index > 0, boxes[pos.index - 1] is TableBlockBox || boxes[pos.index - 1] is ButtonRowBox {
            // Start of a block after a table or a button row → move WITHOUT deleting (no merge across
            // the boundary). For a row the previous text position is its last pill atom, so the NEXT
            // Backspace deletes that pill. Mirrors Backspace at a cell's first-paragraph start.
            let prev = prevTextPosition(before: head)
            if prev != head { setCaret(global: prev) }
        } else if pos.index > 0 {
            let prev = boxes[pos.index - 1]
            let from = prev.textStart + prev.textLength
            editing { applyReplace(globalFrom: from, globalTo: head, text: "") }
        }
    }

    /// True when every cell of `table` holds no text (all cell paragraphs empty) — the condition under
    /// which Backspace at the first cell removes the whole table.
    func tableIsTextuallyEmpty(_ table: TableBlockBox) -> Bool {
        for row in table.cells {
            for stack in row {
                for box in stack.boxes where box.textLength > 0 { return false }
            }
        }
        return true
    }
}

// MARK: - NSResponder editing selectors

@available(macOS 12, *)
extension DocumentCanvasView {
    override func insertNewline(_ sender: Any?) {
        if let onReturnKey = onReturnKey, onReturnKey() { return }
        clearTableSelection()
        // Return in a code block's LANGUAGE line moves the caret to the start of the code text — the
        // same rule `keyDown` applies for the raw Return key (see the note there); repeated here for
        // every path that reaches this selector directly (`doCommand(by:)`, tests).
        if selFrom == selTo, let (region, _) = leafRegion(containingGlobal: head),
           case let .codeLanguage(id) = region.ref,
           let owner = stackContainingCodeBox(id: id) {
            setCaret(global: owner.box.textStart)
            return
        }
        if selFrom == selTo, let img = imageBox(atGap: head), let i = boxIndex(of: img) {
            editing { insertParagraphBeforeImage(at: i, text: "") }
            return
        }
        // Enter at the END of a heading starts a plain body paragraph — a heading is a one-line title, so
        // the next line is normal text rather than carrying the heading style forward. Splitting mid-heading
        // (or a heading that is also a list item) keeps the current behavior.
        if selFrom == selTo, let active = activeStack(at: head), let p = active.box as? BlockBox,
           isHeadingStyle(p.style), p.listMembership == nil,
           active.local >= p.currentParagraph().utf16Count {
            insertParagraphBreak(newParagraphAsBody: true)
            return
        }
        insertParagraphBreak()
    }

    private func isHeadingStyle(_ style: ParagraphStyleName) -> Bool {
        switch style {
        case .heading1, .heading2, .heading3, .heading4, .heading5, .heading6: return true
        default: return false
        }
    }

    override func deleteBackward(_ sender: Any?) { performDeleteBackward() }

    override func deleteForward(_ sender: Any?) {
        // A structural row/column selection (the table handle) → Forward-delete removes it too.
        if let sel = tableSelection {
            switch sel.kind {
            case .rows: deleteTableRow()
            case .columns: deleteTableColumn()
            }
            return
        }
        // A click-selected media block → Forward-delete removes it too.
        if let m = soleSelectedMediaBlock(), let i = boxIndex(of: m) {
            editing { deleteMediaBox(at: i) }
            return
        }
        // Forward-delete on text: swallow to avoid the system beep. Refine in a later pass if needed.
    }

    override func deleteWordBackward(_ sender: Any?) {
        // Minimal: single-char backward delete. Refine with word-boundary nav in a later pass.
        performDeleteBackward()
    }

    override func insertTab(_ sender: Any?) { moveToCell(forward: true) }
    override func insertBacktab(_ sender: Any?) { moveToCell(forward: false) }
}
#endif
