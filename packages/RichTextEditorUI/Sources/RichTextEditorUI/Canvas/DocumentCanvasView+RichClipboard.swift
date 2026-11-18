#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// Rich (attribute-preserving) copy/paste WITHIN the editor. Copy extracts the selection as a `[Block]`
/// fragment (paragraph runs sliced to the selection, whole tables when covered; media/host content is
/// dropped — it isn't part of the Core model). Paste splices a fragment at the caret, merging the boundary
/// paragraphs and inserting any interior blocks — which also gives proper multi-line/multi-paragraph paste.
@available(macOS 12, *)
extension DocumentCanvasView {

    // MARK: Extract (selection → fragment)

    /// The current selection as a `[Block]` fragment: each overlapped paragraph contributes its runs sliced
    /// to the selection (keeping style/list + per-run attributes); a table is taken whole when the selection
    /// touches it. A structural row/column selection yields a sub-table of those rows/columns. Empty when
    /// nothing is selected.
    func selectedFragment() -> [Block] {
        if let subTable = structuralTableFragment() { return [subTable] }
        let lo = selFrom, hi = selTo
        guard lo < hi else { return [] }
        return slicedBlocks(from: boxes, lo: lo, hi: hi)
    }

    /// The `[lo, hi)`-covered portion of `boxes` as fresh Core blocks — paragraphs/code sliced at the
    /// selection edges, tables included whole on any overlap, and block quotes recursed (a partially
    /// covered quote copies as a quote of its covered children).
    private func slicedBlocks(from boxes: [CanvasBlock], lo: Int, hi: Int) -> [Block] {
        var result: [Block] = []
        for box in boxes {
            if let p = box as? BlockBox {
                let bStart = box.textStart, bEnd = box.textStart + box.textLength
                let a = max(lo, bStart), b = min(hi, bEnd)
                if a < b {
                    let para = p.currentParagraph()
                    var copy = para
                    copy.id = BlockID.generate()
                    copy.runs = Self.sliceRuns(para.runs, from: a - bStart, to: b - bStart)
                    result.append(.paragraph(copy))
                } else if box.textLength == 0, lo <= bStart, bStart < hi {
                    // A wholly-covered empty paragraph (e.g. a blank line in the selection) is kept.
                    var copy = p.currentParagraph(); copy.id = BlockID.generate(); copy.runs = []
                    result.append(.paragraph(copy))
                }
            } else if let t = box as? TableBlockBox {
                // Include the whole table when the selection overlaps any of its cells.
                let overlaps = t.leafRegions().contains { region in
                    max(lo, region.globalStart) < min(hi, region.globalStart + region.length)
                }
                if overlaps { result.append(t.currentBlock()) }
            } else if let c = box as? CodeBlockBox {
                let bStart = box.textStart, bEnd = box.textStart + box.textLength
                let a = max(lo, bStart), b = min(hi, bEnd)
                if a < b {
                    let s = c.textLayout.attributedString.string as NSString
                    let sub = s.substring(with: NSRange(location: a - bStart, length: b - a))
                    // A partial copy carries the language — block metadata rather than flat text, the
                    // same rule the pull quote applies to its author.
                    result.append(.code(CodeBlock(id: BlockID.generate(), language: c.currentCode().language,
                                                  runs: [TextRun(text: sub)])))
                }
            } else if let pq = box as? PullQuoteBox {
                let bStart = box.textStart, bEnd = box.textStart + box.textLength
                let a = max(lo, bStart), b = min(hi, bEnd)
                if a < b, case let .pullQuote(model) = pq.currentBlock() {
                    result.append(.pullQuote(PullQuote(id: BlockID.generate(),
                                                       runs: Self.sliceRuns(model.runs, from: a - bStart, to: b - bStart))))
                }
            } else if let bq = box as? BlockQuoteBox, !bq.collapsed {
                // Recurse into the quote's children; the covered portion copies as a quote container.
                let sliced = slicedBlocks(from: bq.children.boxes, lo: lo, hi: hi)
                if !sliced.isEmpty {
                    result.append(.blockQuote(BlockQuote(id: BlockID.generate(), children: sliced, collapsed: false)))
                }
            } else if let bq = box as? BlockQuoteBox, bq.collapsed,
                      lo <= bq.nodeStart, hi >= bq.nodeStart + bq.nodeSize {
                // A collapsed quote atom copies whole when the selection covers its span.
                result.append(Self.reid(bq.currentBlock()))
            } else if let row = box as? ButtonRowBox,
                      lo <= row.nodeStart, hi >= row.nodeStart + row.nodeSize - 2 {
                // A button row is text-free; it copies whole when the selection covers its atom span.
                result.append(Self.reid(row.currentBlock()))
            }
            // Media / image / group boxes are host-managed, not Core blocks → dropped from the fragment.
        }
        return result
    }

    /// When a structural row/column selection is active, the selected rows (all columns) or columns (all
    /// rows) as a fresh sub-table — so ⌘C copies "that part of the table". Fresh ids avoid collisions on paste.
    func structuralTableFragment() -> Block? {
        guard let sel = tableSelection, let a = activeTable(), a.box.id == sel.table,
              case .table(let table) = a.box.currentBlock(), table.rowCount > 0, table.columnCount > 0 else { return nil }
        switch sel.kind {
        case .rows(let r):
            let range = r.clamped(to: 0 ... (table.rowCount - 1))
            return Self.reid(.table(TableBlock(id: BlockID.generate(), columns: table.columns,
                                               rows: range.map { table.rows[$0] },
                                               compact: table.compact, bordered: table.bordered)))
        case .columns(let c):
            let cols = Array(c).filter { table.columns.indices.contains($0) }
            guard !cols.isEmpty else { return nil }
            let rows = table.rows.map { row in
                Row(id: row.id, height: row.height, isHeader: row.isHeader,
                    cells: cols.compactMap { row.cells.indices.contains($0) ? row.cells[$0] : nil })
            }
            return Self.reid(.table(TableBlock(id: BlockID.generate(), columns: cols.map { table.columns[$0] }, rows: rows,
                                               compact: table.compact, bordered: table.bordered)))
        }
    }

    /// Regenerate every id in a block (paragraph / table → rows / cells / nested paragraphs) so an inserted
    /// fragment can never collide with existing block ids (incl. repeated pastes of the same fragment).
    static func reid(_ block: Block) -> Block {
        switch block {
        case .paragraph(var p): p.id = BlockID.generate(); return .paragraph(p)
        case .table(let t):     return .table(reidTable(t))
        case .code(var c):      c.id = BlockID.generate(); return .code(c)
        case .pullQuote(var pq): pq.id = BlockID.generate(); return .pullQuote(pq)
        case .blockQuote(var bq):
            bq.id = BlockID.generate()
            bq.children = bq.children.map { reid($0) }
            return .blockQuote(bq)
        case .buttonRow(var r):
            r.id = BlockID.generate()   // pills carry no ids of their own
            return .buttonRow(r)
        default:                return block   // media doesn't appear in editor fragments
        }
    }

    private static func reidTable(_ t: TableBlock) -> TableBlock {
        let rows = t.rows.map { row -> Row in
            let cells = row.cells.map { cell in
                var cell = cell
                cell.id = BlockID.generate()
                cell.blocks = cell.blocks.map { reid($0) }
                return cell
            }
            return Row(id: BlockID.generate(), height: row.height, isHeader: row.isHeader, cells: cells)
        }
        return TableBlock(id: BlockID.generate(), columns: t.columns, rows: rows,
                          compact: t.compact, bordered: t.bordered)
    }

    /// Slice a run array to the UTF-16 range `[from, to)`, preserving each run's attributes.
    static func sliceRuns(_ runs: [TextRun], from: Int, to: Int) -> [TextRun] {
        var out: [TextRun] = []
        var offset = 0
        for run in runs {
            let length = (run.text as NSString).length
            let runStart = offset, runEnd = offset + length
            let a = max(from, runStart), b = min(to, runEnd)
            if a < b {
                let sub = (run.text as NSString).substring(with: NSRange(location: a - runStart, length: b - a))
                out.append(TextRun(text: sub, attributes: run.attributes))
            }
            offset = runEnd
        }
        return out
    }

    // MARK: Insert (fragment → at caret, replacing selection)

    /// Splice a `[Block]` fragment at the caret (after clearing any selection). The first fragment paragraph
    /// joins the caret's paragraph head; the last joins its tail; interior blocks (paragraphs/tables) are
    /// inserted whole. Falls back to plain text when the caret isn't in a top-level paragraph (e.g. a table
    /// cell). Caller need not wrap in `editing { }` — this does.
    ///
    /// `downgradeUnsupportedActions` is the PASTE-only rule: `.unsupported` button actions become
    /// `.disabled` in the pasted fragment (a copy severed from its source message can't keep an action
    /// the editor cannot express). Only the pasteboard callers pass true — the edit round-trip AND the
    /// host's AI-splice path (`replaceSelection(with:)`) preserve actions verbatim.
    func insertFragment(_ fragment: [Block], downgradeUnsupportedActions: Bool = false) {
        guard !boxes.isEmpty else { return }
        let fragment = downgradeUnsupportedActions
            ? Document(blocks: fragment).convertingUnsupportedButtonActions().blocks
            : fragment
        // Re-id everything (collision-free, incl. repeated pastes); paragraphs/tables/code stay as
        // first-class blocks; media isn't a Core block.
        let blocks: [Block] = fragment.compactMap { block -> Block? in
            switch block {
            case .paragraph, .table, .code, .pullQuote, .blockQuote, .buttonRow: return Self.reid(block)
            case .media: return nil
            case .details: return nil   // `makeBox` builds no box for a details block, so it cannot be hosted
            }
        }
        guard !blocks.isEmpty else { return }

        editing {
            if selFrom != selTo { applySelectionReplace(globalFrom: selFrom, globalTo: selTo, text: "") }

            // A single-table fragment pasted INSIDE a table merges as new rows/columns when the dimensions
            // line up (column count → rows after the caret's row; row count → columns after the caret's col).
            if blocks.count == 1, case let .table(fragTable) = blocks[0],
               let a = activeTable(), case let .table(existing) = a.box.currentBlock(),
               mergeTableFragment(fragTable, into: existing, at: a) {
                return
            }

            guard let pos = resolveBox(at: head), let blockBox = pos.box as? BlockBox else {
                // Not a top-level paragraph (e.g. inside a table cell, fragment not mergeable) → plain text,
                // flattened (applyReplace can't take newlines).
                let flat = Self.plainText(of: blocks).replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\t", with: " ")
                applySelectionReplace(globalFrom: head, globalTo: head, text: flat)
                return
            }
            let index = pos.index
            let (headPara, tailPara) = blockBox.currentParagraph().split(at: pos.local, newID: BlockID.generate())

            var spliced: [Block] = []
            var caretBoxOffset = 0          // index into `spliced` where the caret lands
            var caretLocal = 0              // UTF-16 offset within that box

            func utf16(_ runs: [TextRun]) -> Int { runs.reduce(0) { $0 + $1.utf16Count } }

            if blocks.count == 1, case let .paragraph(f0) = blocks[0] {
                // Single paragraph → fully inline: head + f0 + tail in one paragraph (head's style).
                var merged = headPara
                merged.runs = headPara.runs + f0.runs + tailPara.runs
                spliced = [.paragraph(merged)]
                caretBoxOffset = 0
                caretLocal = utf16(headPara.runs) + utf16(f0.runs)
            } else if blocks.count == 1 {
                // Single non-paragraph block (a table): [head?, block, tail]; caret lands in the tail.
                if !headPara.runs.isEmpty { spliced.append(.paragraph(headPara)) }
                spliced.append(blocks[0])
                spliced.append(.paragraph(tailPara))
                caretBoxOffset = spliced.count - 1
                caretLocal = 0
            } else {
                // First fragment block: if the caret's head text is non-empty, the block's runs join it
                // (head keeps its style); if the head is empty (caret at paragraph start), the fragment
                // block is kept whole so its style survives. A non-paragraph (table) keeps the head before it.
                if case let .paragraph(f0) = blocks.first! {
                    if headPara.runs.isEmpty {
                        spliced.append(.paragraph(f0))
                    } else {
                        var first = headPara; first.runs = headPara.runs + f0.runs
                        spliced.append(.paragraph(first))
                    }
                } else {
                    if !headPara.runs.isEmpty { spliced.append(.paragraph(headPara)) }
                    spliced.append(blocks.first!)
                }
                // Interior blocks inserted whole.
                for block in blocks.dropFirst().dropLast() { spliced.append(block) }
                // Last fragment block: mirror of the first — join a non-empty tail (tail keeps its style),
                // else keep the fragment block whole. The caret lands at the end of the pasted content.
                if case let .paragraph(fn) = blocks.last! {
                    if tailPara.runs.isEmpty {
                        spliced.append(.paragraph(fn)); caretLocal = utf16(fn.runs)
                    } else {
                        var last = tailPara; last.runs = fn.runs + tailPara.runs
                        spliced.append(.paragraph(last)); caretLocal = utf16(fn.runs)
                    }
                    caretBoxOffset = spliced.count - 1
                } else {
                    spliced.append(blocks.last!)
                    if !tailPara.runs.isEmpty { spliced.append(.paragraph(tailPara)) }
                    caretBoxOffset = spliced.count - 1
                    caretLocal = 0
                }
            }

            let newBoxes = spliced.map { Self.makeBox(for: $0, mapper: mapper, width: effectiveWidth) }
            var arr = boxes
            arr.replaceSubrange(index ... index, with: newBoxes)
            boxes = arr
            recomputeSpans()
            let caretBox = newBoxes[min(caretBoxOffset, newBoxes.count - 1)]
            let caret = caretBox.textStart + caretLocal
            anchor = caret; head = caret
        }
        needsLayout = true
    }

    /// Merge a copied sub-table into the caret's table when their dimensions line up: same column count →
    /// insert `frag`'s rows after the caret's row; same row count → insert `frag`'s columns after the caret's
    /// column. Returns false (caller inserts a new table instead) when neither matches. Call inside `editing`.
    private func mergeTableFragment(_ frag: TableBlock, into existing: TableBlock,
                                    at a: (box: TableBlockBox, index: Int, row: Int, col: Int)) -> Bool {
        if frag.columnCount == existing.columnCount, !frag.rows.isEmpty {
            var rows = existing.rows
            rows.insert(contentsOf: frag.rows, at: min(a.row + 1, rows.count))
            replaceTable(at: a.index, with: TableBlock(id: existing.id, columns: existing.columns, rows: rows,
                                                       compact: existing.compact, bordered: existing.bordered),
                         caretRow: a.row + 1, caretCol: a.col)
            return true
        }
        if frag.rowCount == existing.rowCount, !frag.columns.isEmpty {
            var columns = existing.columns
            columns.insert(contentsOf: frag.columns, at: min(a.col + 1, columns.count))
            let rows = zip(existing.rows, frag.rows).map { row, fragRow -> Row in
                var cells = row.cells
                cells.insert(contentsOf: fragRow.cells, at: min(a.col + 1, cells.count))
                return Row(id: row.id, height: row.height, isHeader: row.isHeader, cells: cells)
            }
            replaceTable(at: a.index, with: TableBlock(id: existing.id, columns: columns, rows: rows,
                                                       compact: existing.compact, bordered: existing.bordered),
                         caretRow: a.row, caretCol: a.col + 1)
            return true
        }
        return false
    }

    private static func makeBox(for block: Block, mapper: AttributedStringMapper, width: CGFloat) -> any CanvasBlock {
        RichTextEditorUI.makeBox(for: block, mapper: mapper, width: width)
            ?? BlockBox(paragraph: ParagraphBlock(id: BlockID.generate()), mapper: mapper, width: width)
    }

    /// Plain-text of a fragment: paragraphs/code by line, a table as tab-separated cells per row. Used for
    /// the cross-app pasteboard string and the table-cell paste fallback (the caller flattens newlines there).
    static func plainText(of blocks: [Block]) -> String {
        blocks.map { block -> String in
            switch block {
            case let .paragraph(p): return p.runs.map(\.text).joined()
            case let .code(c): return c.text
            case let .pullQuote(pq): return pq.text
            case let .blockQuote(bq): return plainText(of: bq.children)
            case let .table(t):
                return t.rows.map { row in
                    row.cells.map { cell in
                        cell.blocks.compactMap { if case let .paragraph(p) = $0 { return p.runs.map(\.text).joined() } else { return nil } }
                            .joined(separator: " ")
                    }.joined(separator: "\t")
                }.joined(separator: "\n")
            case .media: return ""
            case let .buttonRow(row): return row.buttons.map(\.labelText).joined(separator: " ")
            case let .details(d):
                let title = d.title.map(\.text).joined()
                let children = plainText(of: d.children)
                return title.isEmpty ? children : title + "\n" + children
            }
        }.joined(separator: "\n")
    }
}
#endif
