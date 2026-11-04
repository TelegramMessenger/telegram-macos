#if canImport(AppKit)
import AppKit
import RichTextEditorCore

// MARK: - Plain text/geometry helpers (were UITextInput witnesses; now Int-based)

@available(macOS 12, *)
extension DocumentCanvasView {
    private func clamp(_ n: Int) -> Int { clampGlobal(n) }

    /// Concatenated text over a global range (leaf-region-aware). Was `text(in: UITextRange)`.
    func text(inGlobalRange lo0: Int, _ hi0: Int) -> String {
        let lo = clamp(min(lo0, hi0)), hi = clamp(max(lo0, hi0))
        var result = ""
        for region in allLeafRegions() {
            let a = max(lo, region.globalStart), b = min(hi, region.globalStart + region.length)
            guard a < b else { continue }
            let s = region.layout.attributedString.string as NSString
            result += s.substring(with: NSRange(location: a - region.globalStart, length: b - a))
        }
        return result
    }

    /// System-initiated replacement over a global range (autocorrect/dictation/IME). Routes through the
    /// 3-way selection logic, not applyReplace directly, since a system edit can span a table boundary.
    func replace(globalRange r: (Int, Int), withText text: String) {
        let lo = min(r.0, r.1), hi = max(r.0, r.1)
        editing { applySelectionReplace(globalFrom: lo, globalTo: hi, text: text) }
    }

    func typingAttributeDict(region: LeafTextRegion, atLocal location: Int) -> [NSAttributedString.Key: Any] {
        // A code block types in the monospace code attributes regardless of caret context — the block
        // carries no inline formatting, so pending toggles and inherited attrs don't apply.
        if case .code = region.ref {
            return CodeBlockBox.codeAttributes(appearance: mapper.appearance)
        }
        // A code block's LANGUAGE line types in the language attributes (bold, accent) the same way —
        // without this the first character typed into an empty language line lands body-styled and
        // read-back writes that string into the model. Inline formats are inert here, so pending
        // toggles don't apply either.
        if case .codeLanguage = region.ref {
            return CodeBlockBox.languageAttributes(appearance: mapper.appearance)
        }
        if isUpdatingTextInput, let state = markedTextState {
            return state.attributes
        }
        let storage = region.layout.attributedString
        if storage.length == 0 {
            // A caption region types in the caption style (12pt secondary), so the first typed character
            // matches the rest of the caption rather than dropping to body.
            if case .caption = region.ref {
                var attrs = mapper.attributes(for: CharacterAttributes(), style: .caption)
                attrs[.paragraphStyle] = mapper.styleSheet.paragraphStyle(for: .caption, attributes: .default)
                return applyPendingFormat(to: attrs)
            }
            // An empty pull quote types in its own style (italic + centered), not body-upright-left.
            if case .pullQuote = region.ref {
                let m = (activeStack(at: region.globalStart)?.box as? PullQuoteBox)?.mapper ?? mapper
                return applyPendingFormat(to: PullQuoteBox.pullQuoteTypingAttributes(m))
            }
            // An empty pull-quote author line types in the author style (bold+italic caption, centered).
            // `activeStack` matches a box by its FIRST leaf region only, so it misroutes an author
            // position — resolve the owning pull quote by its id instead.
            if case let .quoteAuthor(id) = region.ref,
               let pq = boxes.compactMap({ $0 as? PullQuoteBox }).first(where: { $0.id == id }) {
                return applyPendingFormat(to: pq.authorTypingAttributes())
            }
            // Recover the owning paragraph (if any) so an empty styled/listed paragraph keeps its
            // paragraph style on the next typed character. Resolved through the recursive activeStack so
            // a paragraph nested in a container (block quote, table cell) is found too, and its own
            // mapper (a container-scoped variant) styles the first typed character.
            let p = activeStack(at: region.globalStart)?.box as? BlockBox
            let m = p?.mapper ?? mapper
            let style = p?.style ?? .body
            let para = p?.paragraphAttributes ?? .default
            let list = p?.listMembership
            var attrs = m.attributes(for: CharacterAttributes(), style: style)
            attrs[.paragraphStyle] = m.styleSheet.paragraphStyle(for: style, attributes: para, list: list)
            return applyPendingFormat(to: attrs)
        }
        var attrs = storage.attributes(at: min(max(0, location - 1), storage.length - 1), effectiveRange: nil)
        // An atom's render attributes must never propagate to text typed after it. TextKit already drops
        // `.attachment` from non-atom chars (so emoji is safe), but the formula marker is a plain attribute,
        // so text typed right after a formula would otherwise inherit it and read back as a formula.
        attrs.removeValue(forKey: .attachment)
        attrs.removeValue(forKey: .rtFormula)
        // A link extends to typed text only when typing STRICTLY INSIDE it — the characters on both sides
        // of the caret carry the same link. At a link's leading/trailing edge typing breaks out of it
        // (matching NSTextView/UITextView), so drop the inherited `.link` and its render-only blue color.
        if attrs[.link] != nil {
            let leftLink  = location >= 1 ? storage.attribute(.link, at: location - 1, effectiveRange: nil) : nil
            let rightLink = location < storage.length ? storage.attribute(.link, at: location, effectiveRange: nil) : nil
            if !linkValuesEqual(leftLink, rightLink) {
                attrs.removeValue(forKey: .link)
                attrs[.foregroundColor] = editorAppearance.defaultForeground
            }
        }
        return applyPendingFormat(to: attrs)
    }

    /// True when two `.link` attribute values denote the same (non-nil) URL, in String or URL form.
    private func linkValuesEqual(_ a: Any?, _ b: Any?) -> Bool {
        let sa = (a as? String) ?? (a as? URL)?.absoluteString
        let sb = (b as? String) ?? (b as? URL)?.absoluteString
        return sa != nil && sa == sb
    }

    /// Typing attributes for the caret at a global position: the leaf region's attributes, or body
    /// defaults at a structural boundary (no region). Used by the structural-edit engine.
    func typingAttributesAtGlobal(_ pos: Int) -> [NSAttributedString.Key: Any] {
        if let (region, local) = leafRegion(containingGlobal: clamp(pos)) {
            return typingAttributeDict(region: region, atLocal: local)   // already pending-applied
        }
        return applyPendingFormat(to: mapper.attributes(for: CharacterAttributes(), style: .body))
    }

    /// Programmatic selection setter for the façade (was the `selectedTextRange` UITextInput witness).
    var selectedGlobalRange: (Int, Int) {
        get { (anchor, head) }
        set {
            clearTableSelection()
            pendingFormatToggles.removeAll()
            anchor = clamp(newValue.0); head = clamp(newValue.1)
            needsDisplay = true; notifySelectionChanged()
        }
    }

    // The first/last positions the caret can occupy must be RENDERABLE (a leaf region start/end or an
    // image gap), not the document's structural open/close token slots (0 / documentSize) — otherwise
    // "move to start/end of document" would hide the caret.
    func firstRenderableGlobal() -> Int { snapToRenderable(0, forward: true) }
    func lastRenderableGlobal() -> Int { snapToRenderable(documentSize, forward: false) }

    /// Caret rect for a global position (leaf region or image gap). Was `caretRect(for: UITextPosition)`.
    func caretRect(forGlobal pos0: Int) -> CGRect {
        // A structural row/column selection hides the blinking caret (the outline is the indicator).
        if tableSelection != nil { return .zero }
        let pos = clamp(pos0)
        if let (r, local) = leafRegion(containingGlobal: pos) {
            var rect = r.layout.caretRect(atOffset: local).offsetBy(dx: r.canvasOrigin.x, dy: r.canvasOrigin.y)
            // TextKit 2 lays out no line fragment for an empty paragraph, so caretRect returns x = 0 (the
            // container's left edge), ignoring firstLineHeadIndent. For an indented empty line — a list
            // item or quote — that drops the caret into the marker gutter; place it at the text indent.
            if r.layout.length == 0 {
                if let p = activeStack(at: r.globalStart)?.box as? BlockBox {
                    let ps = p.mapper.styleSheet.paragraphStyle(for: p.style, attributes: p.paragraphAttributes, list: p.listMembership)
                    rect.origin.x = r.canvasOrigin.x + ps.firstLineHeadIndent
                } else if let pq = activeStack(at: r.globalStart)?.box as? PullQuoteBox {
                    // An empty pull quote's text is centered inside the centered pill — the caret sits at
                    // the pill's mid-x, not the layout's left edge.
                    rect.origin.x = pq.frame.midX
                }
            }
            return rect
        }
        // A button-row pill atom is a real caret slot but not a text leaf. Report a vertical bar at
        // the pill's TRAILING edge — standard atom semantics: the caret sits after the thing Backspace
        // would delete, exactly like a character or an emoji. (An empty row keeps the bar at the row's
        // own leading edge — there is no pill to trail.)
        if let (row, index) = buttonRowPill(at: pos) {
            if let pill = row.pillCanvasRect(min(index, max(0, row.buttons.count - 1))) {
                return CGRect(x: pill.maxX + 1, y: pill.minY, width: 2, height: pill.height)
            }
            return CGRect(x: row.frame.minX, y: row.frame.minY, width: 2, height: row.height)
        }
        // A media gap is a real caret slot but not a text leaf. Report a vertical bar at the media's
        // leading edge so the self-drawn caret renders there.
        if let box = imageBox(atGap: pos) {
            let y: CGFloat, h: CGFloat
            if let img = box as? ImageBlockBox { let rr = img.imageRect(); y = rr.minY; h = rr.height }
            else if let m = box as? MediaBlockBox { y = m.mediaOrigin.y; h = m.mediaAreaHeight }
            else { y = box.frame.minY; h = box.frame.height }
            return CGRect(x: box.frame.minX, y: y, width: 2, height: h)
        }
        return .zero
    }
}

// MARK: - NSTextInputClient

@available(macOS 12, *)
extension DocumentCanvasView: NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        guard let text = (string as? String) ?? (string as? NSAttributedString)?.string else { return }
        let range = textInputReplacementRange(replacementRange)
        guard !text.isEmpty || range.length > 0 else {
            unmarkText()
            return
        }
        isUpdatingTextInput = true
        defer { isUpdatingTextInput = false }
        if replacementRange.location != NSNotFound || hasMarkedText() {
            anchor = range.location
            head = NSMaxRange(range)
        }
        commitText(text)
        markedTextState = nil
        needsDisplay = true
        notifySelectionChanged()
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard let text = (string as? String) ?? (string as? NSAttributedString)?.string else { return }
        let range = textInputReplacementRange(replacementRange)
        let attributes = markedTextState?.attributes ?? typingAttributesAtGlobal(range.location)
        isUpdatingTextInput = true
        defer { isUpdatingTextInput = false }
        anchor = range.location
        head = NSMaxRange(range)
        if !text.isEmpty || range.length > 0 {
            commitText(text)
        }
        let length = min((text as NSString).length, head)
        if length > 0 {
            let marked = NSRange(location: head - length, length: length)
            markedTextState = (marked, attributes)
            let location = selectedRange.location == NSNotFound ? length : min(max(0, selectedRange.location), length)
            anchor = marked.location + location
            head = anchor + min(max(0, selectedRange.length), length - location)
        } else {
            markedTextState = nil
        }
        needsDisplay = true
        notifySelectionChanged()
    }

    func unmarkText() {
        guard markedTextState != nil else { return }
        markedTextState = nil
        inputContext?.discardMarkedText()
        needsDisplay = true
    }

    func hasMarkedText() -> Bool { markedTextState != nil }
    func markedRange() -> NSRange { markedTextState?.range ?? NSRange(location: NSNotFound, length: 0) }
    func selectedRange() -> NSRange { NSRange(location: selFrom, length: selTo - selFrom) }

    private func textInputReplacementRange(_ range: NSRange) -> NSRange {
        let range = range.location == NSNotFound ? markedTextState?.range ?? selectedRange() : range
        let location = clampGlobal(range.location)
        return NSRange(location: location, length: min(max(0, range.length), documentSize - location))
    }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        let lo = clampGlobal(range.location), hi = clampGlobal(range.location + range.length)
        actualRange?.pointee = NSRange(location: lo, length: hi - lo)
        return NSAttributedString(string: text(inGlobalRange: lo, hi))
    }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    // --- Geometry: flat-char space ≈ global offset (LTR, single axis); screen coords out/in ---
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        let lo = clampGlobal(range.location), hi = clampGlobal(range.location + range.length)
        let rect = selectionRects(globalFrom: lo, globalTo: hi).first ?? caretRect(forGlobal: lo)
        guard let window else { return rect }
        return window.convertToScreen(convert(rect, to: nil))
    }
    func characterIndex(for screenPoint: NSPoint) -> Int {
        guard let window else { return selFrom }
        let viewPoint = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        return closestGlobalPosition(to: viewPoint)
    }
}
#endif
