#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// A minimal pasteboard seam so copy/cut/paste are unit-testable with a fake — the real
/// `NSPasteboard.general` is a process-global side effect. Production uses `NSPasteboardAdapter`.
@available(macOS 12, *)
protocol TextPasteboard {
    var string: String? { get set }
    var hasStrings: Bool { get }
    /// The editor's own rich fragment (a `DocumentCodec` JSON `Document`) under a private pasteboard type,
    /// for attribute-preserving copy/paste WITHIN the editor. Setting it ADDS to the pasteboard (no clear),
    /// so copy must set `string` first (which clears) then `richFragment`.
    var richFragment: Data? { get set }
}

@available(macOS 12, *)
extension TextPasteboard {
    // Default so plain-only pasteboards (e.g. test fakes) need not implement the rich type.
    var richFragment: Data? { get { nil } set { } }
}

public extension NSPasteboard.PasteboardType {
    /// The editor's rich-fragment pasteboard type: a `DocumentCodec` JSON `Document`. Written on copy so
    /// hosts (e.g. the chat composer) can detect editor content on paste and reopen it fully formatted.
    static let richTextEditorFragment = NSPasteboard.PasteboardType("org.telegram.macos.richtexteditor.fragment")
}

/// Production `TextPasteboard` backed by the system pasteboard (the §3.6 adapter).
@available(macOS 12, *)
struct NSPasteboardAdapter: TextPasteboard {
    static let richFragmentType = NSPasteboard.PasteboardType.richTextEditorFragment
    var string: String? {
        get { NSPasteboard.general.string(forType: .string) }
        nonmutating set {
            NSPasteboard.general.clearContents()
            if let newValue { NSPasteboard.general.setString(newValue, forType: .string) }
        }
    }
    var richFragment: Data? {
        get { NSPasteboard.general.data(forType: Self.richFragmentType) }
        nonmutating set {
            if let newValue { NSPasteboard.general.setData(newValue, forType: Self.richFragmentType) }
        }
    }
    var hasStrings: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSString.self], options: nil)
    }
}

/// A closure-backed `NSMenuItem` so a built menu can carry its own action without a per-item selector.
/// Reused by the table structural menu (+TableControls) as well as the text edit menu below.
@available(macOS 12, *)
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void
    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }
    required init(coder: NSCoder) { fatalError() }
    @objc private func fire() { handler() }
}

/// The right-click / Control-click context menu plus the responder actions that back it (and the main-menu
/// Edit menu / ⌘ key equivalents the system delivers via `performKeyEquivalent:`). Cut/Copy/Paste/Select All
/// route to plain helpers; a Format submenu routes Bold/Italic/Underline to the existing Core toggles;
/// Look Up / Share appear when there is a selection (see +EditMenuActions). Enable state lives in
/// `validateUserInterfaceItem` (replacing the UIKit `canPerformAction`).
@available(macOS 12, *)
extension DocumentCanvasView {
    override func menu(for event: NSEvent) -> NSMenu? {
        // A structurally-selected table row/column → its Add/Delete/Align menu (system Cut/Copy/Paste are
        // irrelevant to a structural pick).
        if tableSelection != nil { return structuralMenu() }

        let p = convert(event.locationInWindow, from: nil)
        placeCaretForContextClick(at: p)   // a right-click in a cell targets that cell (menu + commands)

        // Let the host present its own (e.g. TGUIKit) menu; if it does, suppress the native one.
        if let handler = contextMenuRequested {
            if handler(p, mediaContext(atCanvasPoint: p), selFrom != selTo, event) { return nil }
        }

        let menu = NSMenu()
        // Responder-routed standard actions: `target == nil` lets AppKit walk the responder chain and call
        // `validateUserInterfaceItem` for enable state.
        menu.addItem(withTitle: editorLocalized("RichTextEditor.Menu.Cut", "Cut"), action: #selector(cut(_:)), keyEquivalent: "")
        menu.addItem(withTitle: editorLocalized("RichTextEditor.Menu.Copy", "Copy"), action: #selector(copy(_:)), keyEquivalent: "")
        menu.addItem(withTitle: editorLocalized("RichTextEditor.Menu.Paste", "Paste"), action: #selector(paste(_:)), keyEquivalent: "")
        menu.addItem(withTitle: editorLocalized("RichTextEditor.Menu.SelectAll", "Select All"), action: #selector(selectAll(_:)), keyEquivalent: "")
        menu.addItem(.separator())

        let format = NSMenu()
        format.addItem(withTitle: editorLocalized("RichTextEditor.Menu.Bold", "Bold"), action: #selector(toggleBoldface(_:)), keyEquivalent: "")
        format.addItem(withTitle: editorLocalized("RichTextEditor.Menu.Italic", "Italic"), action: #selector(toggleItalics(_:)), keyEquivalent: "")
        format.addItem(withTitle: editorLocalized("RichTextEditor.Menu.Underline", "Underline"), action: #selector(toggleUnderline(_:)), keyEquivalent: "")
        let formatItem = NSMenuItem(title: editorLocalized("RichTextEditor.Menu.Format", "Format"), action: nil, keyEquivalent: "")
        formatItem.submenu = format
        menu.addItem(formatItem)

        if selFrom != selTo {
            menu.addItem(.separator())
            menu.addItem(ClosureMenuItem(title: editorLocalized("RichTextEditor.Menu.LookUp", "Look Up")) { [weak self] in self?.lookUpSelection() })
            menu.addItem(ClosureMenuItem(title: editorLocalized("RichTextEditor.Menu.Share", "Share…")) { [weak self] in self?.shareSelection(from: event) })
        }
        return menu
    }

    /// On a right-click with no active selection, move the caret into the clicked table cell so the
    /// context menu's table actions — and the commands they invoke, which operate on the caret — target
    /// where the user clicked. No-op outside a table, and when a selection is active (so right-clicking a
    /// selection keeps it for Cut/Copy).
    func placeCaretForContextClick(at point: NSPoint) {
        guard selFrom == selTo else { return }
        let pos = closestGlobalPosition(to: point)
        // Right-click on a formula atom → put the caret just after it so the menu can offer "Edit Formula"
        // (currentFormula / insertFormula resolve the atom adjacent to the caret).
        if formulaLatex(atGlobal: pos) != nil { setCaret(global: pos + 1); return }
        if pos > 0, formulaLatex(atGlobal: pos - 1) != nil { setCaret(global: pos); return }
        if isInsideTable(pos) { setCaret(global: pos); return }
        // Right-click on a code block → caret into it so the menu's code actions target it. A click that
        // already resolved into one of the block's own regions (the language line included) keeps its
        // position; only a structural-slot resolve is clamped into the code text.
        if let code = codeBlockBoxes().first(where: { $0.frame.contains(point) }) {
            if code.leafRegions().contains(where: { pos >= $0.globalStart && pos <= $0.globalStart + $0.length }) {
                setCaret(global: pos)
            } else {
                setCaret(global: min(max(pos, code.textStart), code.textStart + code.textLength))
            }
        }
    }

    // MARK: - Responder actions (also fire from the main Edit menu / ⌘ equivalents)

    @objc func copy(_ sender: Any?) { copySelectionToPasteboard() }

    @objc func cut(_ sender: Any?) {
        copySelectionToPasteboard()
        guard selFrom < selTo else { return }
        replace(globalRange: (selFrom, selTo), withText: "")   // routes through editing { } + applySelectionReplace
    }

    @objc func paste(_ sender: Any?) { pasteFromPasteboard() }

    @objc override func selectAll(_ sender: Any?) { selectAllText() }

    @objc func toggleBoldface(_ sender: Any?) { toggleBold() }
    @objc func toggleItalics(_ sender: Any?) { toggleItalic() }
    /// Overrides the standard `NSResponder.toggleUnderline(_:)` so the Format submenu item, the main Edit
    /// menu, and ⌘U all route to the existing Core `toggleUnderline()` command.
    @objc func toggleUnderline(_ sender: Any?) { toggleUnderline() }

    // MARK: - Clipboard (plaintext, CRLF-flattened — multi-line paragraph paste is a later phase)

    private func plainTextWithQuoteBoundaries(in regions: [LeafTextRegion], from lo: Int, to hi: Int) -> String {
        var result = ""
        var previous: TextNodeRef?
        for region in regions {
            let a = max(lo, region.globalStart), b = min(hi, region.globalStart + region.length)
            guard a < b else { continue }
            if case let .quoteAuthor(id) = region.ref, previous == .pullQuote(id) {
                result += "\n"
            }
            let text = region.layout.attributedString.string as NSString
            result += text.substring(with: NSRange(location: a - region.globalStart, length: b - a))
            previous = region.ref
        }
        return result
    }

    /// Copy the current selection to the pasteboard: a rich `DocumentCodec` fragment (for attribute-
    /// preserving paste back into the editor) AND plain text (for other apps). `string` is set first because
    /// its setter clears the pasteboard; `richFragment` then adds the private type without clearing.
    func copySelectionToPasteboard() {
        let fragment = selectedFragment()
        guard !fragment.isEmpty else {
            // A selection lying wholly in a NON-PRIMARY leaf region — a code block's language line, a pull
            // quote's author — yields no Core fragment (`slicedBlocks` slices boxes against their primary
            // region only), so without this the copy would write nothing and `cut(_:)` would be a silent
            // destructive delete. Write the selection's plain text instead, exactly as the UIKit editor's
            // `writeSelectionToPasteboard` does for a fragment-less selection. Paste-back is unaffected:
            // the plain branch of `pasteFromPasteboard` routes through the region-aware `replace`.
            if selFrom < selTo { pasteboard.string = plainTextWithQuoteBoundaries(in: allLeafRegions(), from: selFrom, to: selTo) }
            return
        }
        // Plain text: the selected text, or (for a structural/table fragment) the fragment flattened.
        pasteboard.string = (selFrom < selTo) ? plainTextWithQuoteBoundaries(in: allLeafRegions(), from: selFrom, to: selTo) : Self.plainText(of: fragment)
        if let data = try? DocumentCodec.encode(Document(blocks: fragment)) {
            pasteboard.richFragment = data
        }
    }

    /// Paste over the current selection. Prefers the editor's own rich fragment (full attribute + block
    /// fidelity, incl. multi-paragraph), then the host's converter (app-private pasteboard formats, e.g.
    /// the chat input's entity payload — custom emoji, formatting); falls back to plain text otherwise
    /// (newlines split into paragraphs via the fragment path, or flattened when only plain text is available).
    func pasteFromPasteboard() {
        if let withPasteContext {
            withPasteContext { insertContentFromPasteboard() }
        } else {
            insertContentFromPasteboard()
        }
    }

    private func insertContentFromPasteboard() {
        if let data = pasteboard.richFragment, let document = try? DocumentCodec.decode(data), !document.blocks.isEmpty {
            insertFragment(document.blocks, downgradeUnsupportedActions: true)
            return
        }
        if let blocks = hostPasteFragmentProvider?(), !blocks.isEmpty {
            insertFragment(blocks, downgradeUnsupportedActions: true)
            return
        }
        guard let raw = pasteboard.string else { return }
        // Plain text: split paragraphs on newlines and insert as a fragment so multi-line paste works.
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: .newlines)
        if lines.count > 1 {
            let blocks = lines.map { Block.paragraph(ParagraphBlock(id: BlockID.generate(), runs: [TextRun(text: $0)])) }
            insertFragment(blocks, downgradeUnsupportedActions: true)
        } else {
            replace(globalRange: (selFrom, selTo), withText: normalized)
        }
    }
}

/// Enable state for the menu / Edit-menu items (replaces the UIKit `canPerformAction`).
@available(macOS 12, *)
extension DocumentCanvasView: NSUserInterfaceValidations {
    func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)), #selector(cut(_:)):
            return selFrom != selTo
        case #selector(paste(_:)):
            return pasteboard.hasStrings
        case #selector(selectAll(_:)):
            return documentSize > 0
        default:
            return true
        }
    }
}
#endif
