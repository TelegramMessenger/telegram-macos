#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// Character-format toggles pending at a bare caret (no selection). Applied to the next typed text
/// (`applyPendingFormat`) and cleared on any caret/selection move — the "click B, type bold" behavior.
@available(macOS 12, *)
enum PendingFormatToggle { case bold, italic, strikethrough, underline, inlineCode, spoiler }

/// Shared factory: turns one Core `Block` into its `CanvasBlock` box. Used by the document root
/// (`setModelBlocks`), table cells (`TableBlockBox`), and `BlockQuoteBox`, so all three build children
/// through one recursive function. Core media blocks return nil (compose-only on macOS — images enter
/// via the local `.media` path).
@available(macOS 12, *)
func makeBox(for block: Block, mapper: AttributedStringMapper, width: CGFloat) -> CanvasBlock? {
    switch block {
    case .paragraph(let p):  return BlockBox(paragraph: p, mapper: mapper, width: width)
    case .media:             return nil
    case .table(let t):      return TableBlockBox(table: t, mapper: mapper, width: width)
    case .code(let c):       return CodeBlockBox(code: c, mapper: mapper, width: width)
    case .pullQuote(let pq): return PullQuoteBox(pullQuote: pq, mapper: mapper, width: width)
    case .blockQuote(let bq): return BlockQuoteBox(blockQuote: bq, mapper: mapper, width: width)
    case .details:           return nil
    case .buttonRow(let r):  return ButtonRowBox(row: r, mapper: mapper, width: width)
    }
}

/// The multi-block document surface. ONE view owns every block and the unified global selection.
/// (Internal — only `RichTextEditorView` is public; keeps `NSTextInputClient` witnesses internal.)
///
/// A FLIPPED `NSView` (`isFlipped = true`) so all existing y-down geometry math from the iOS port is
/// unchanged. Input is mouse + keyboard via `NSResponder` key selectors + `NSTextInputClient`; the caret
/// is self-drawn + blinking (AppKit has no `UITextSelectionDisplayInteraction`).
@available(macOS 12, *)
final class DocumentCanvasView: NSView {
    let root = BlockStack()
    var boxes: [CanvasBlock] { get { root.boxes } set { root.boxes = newValue } }
    var mapper: AttributedStringMapper
    var imageProvider: (String) -> NSImage? = { _ in nil }

    /// AppKit on macOS 27 attempts to synthesize an `NSTableViewCellMockElement` while resolving the
    /// parent of a focused custom text-input view hosted in a table row, and can throw an uncaught
    /// range exception while that table is transitioning. The app already uses this containment rule
    /// for native text fields; keep it local to the editor's focused canvas.
    override func accessibilityParent() -> Any? {
        return nil
    }

    /// Injectable theming. Rebuilds the mapper (preserving the current `styleSheet`) and redraws so the
    /// canvas's draw-site colors and run attributes track the host's theme. Defaults reproduce the
    /// built-in look exactly. (Named `editorAppearance`, not `appearance`, because `NSView.appearance`
    /// already exists as `NSAppearance?` and cannot be shadowed with a different type.)
    var editorAppearance: EditorAppearance = .default {
        didSet {
            mapper = AttributedStringMapper(styleSheet: mapper.styleSheet, appearance: editorAppearance, emojiScale: mapper.emojiScale)
            // The macOS host bakes the LIVE theme's palette into the token colours it answers with (the
            // UIKit hosts bake a fixed light one), so every cached answer belongs to the palette it was
            // produced under. Re-stamp BEFORE the rebuild: the pass `setModelBlocks` schedules then sees
            // the new palette and re-requests, while the stale answers stay in the cache so the rebuild
            // frame is painted rather than plain. An unchanged palette produces the same token, so a
            // colour-identical re-assign (the inline composer does one per update) asks for nothing.
            syntaxHighlightPaletteToken = richTextSyntaxPaletteToken(editorAppearance)
            // Each box captured the OLD mapper at creation, so a bare `mapper` swap doesn't re-color existing
            // content — re-seed the boxes from the current model with the new mapper (theme text color etc.).
            if !boxes.isEmpty {
                setModelBlocks(currentModelBlocks(), width: lastLayoutWidth)
            }
            layer?.backgroundColor = .clear
            needsDisplay = true
        }
    }

    /// Called whenever the canvas's content height may have changed (after an edit/undo). The host
    /// (`RichTextEditorView`) sizes the canvas frame-based, not via Auto Layout, so without this hook a
    /// height change is only reflected on the next host layout pass.
    var onContentSizeChange: (() -> Void)?

    /// Intercepts the Return key. Return `true` to consume it (no paragraph break) — e.g. an inline host that
    /// uses Return to send and forbids new paragraphs.
    var onReturnKey: (() -> Bool)?

    // Selection as global UTF-16 positions; `anchor` fixed, `head` moving.
    var anchor = 0
    var head = 0
    var markedTextState: (range: NSRange, attributes: [NSAttributedString.Key: Any])?
    var isUpdatingTextInput = false

    // MARK: - Inline custom emoji (host NSViews pooled by instanceID, positioned + culled)
    /// Live host emoji views keyed by `EmojiRef.instanceID` so a view + its animation survive edits/undo.
    var emojiViews: [String: HostedEmoji] = [:]
    /// Host hook: maps an emoji `id` + requested square size to a view (nil = no view this pass).
    var emojiViewProvider: (_ id: String, _ size: CGSize) -> NSView? = { _, _ in nil }
    /// Viewport inset (points) within which off-screen emoji views stay live (not hidden).
    var emojiCullMargin: CGFloat = 50
    /// Non-interactive overlay above block content; hosts all emoji views (clicks pass through).
    lazy var emojiOverlay: NSView = {
        let v = NonInteractiveOverlayView(); v.wantsLayer = true; addSubview(v); return v
    }()

    // MARK: - Telegram spoilers (render-only hide + injectable "dust" overlay; reveal is selection-driven)
    /// Fast-path gate: true iff some leaf region carries a `.rtSpoiler` run. Recomputed only on
    /// model-mutating paths; `syncSpoilers` reads it to skip all work in spoiler-free documents.
    var documentHasSpoilers = false
    /// Last scanned spoiler runs (global ranges + per-line canvas rects + hidden state).
    var spoilerRuns: [SpoilerRun] = []
    /// Live dust views keyed by run, so a view + its dissolve survive a re-scan while the run persists.
    var spoilerDustViews: [SpoilerKey: HostedSpoilerDust] = [:]
    /// Host hook: maps a requested dust size to an injected `SpoilerEffect` (nil = use the default fill).
    var spoilerEffectProvider: ((CGSize) -> SpoilerEffect)?
    /// Non-interactive overlay ABOVE the emoji overlay; hosts every dust view (clicks pass through).
    lazy var spoilerOverlay: NSView = {
        let v = NonInteractiveOverlayView(); v.wantsLayer = true
        addSubview(v, positioned: .above, relativeTo: emojiOverlay)
        return v
    }()

    // MARK: - Embedded media blocks (file/audio/map — host-injected INTERACTIVE views, block-level)
    /// Live host media views keyed by block id, so a view survives edits/undo while the block persists.
    var mediaBlockViews: [String: HostedMediaBlock] = [:]
    /// Host hook: maps a media block's `(kind, mediaID, contentWidth)` to an interactive view (nil = none).
    var mediaBlockViewProvider: (_ kind: String, _ mediaID: String, _ spoiler: Bool, _ width: CGFloat) -> NSView? = { _, _, _, _ in nil }
    /// Host hook: invoked just before a hosted media view is removed (block deleted / document replaced /
    /// canvas torn down). The host releases the view's resources here (e.g. an injected content node's
    /// `clean()`); the package can't see app types, so teardown is the host's responsibility.
    var mediaBlockViewWillRemove: ((NSView) -> Void)?
    /// Host hook: collage mosaic. Maps a group's `mediaIDs` + full-bleed width to per-tile frames (origin
    /// relative to the media area's top-left), via the chat's `GroupedLayout`. nil = a placeholder height.
    var mediaGroupMosaic: ((_ mediaIDs: [String], _ width: CGFloat) -> [CGRect])?
    /// Host hook: builds a collage TILE view for `mediaID` rendered to fill `size` (cropping). nil = none.
    var mediaGroupTileProvider: (_ mediaID: String, _ spoiler: Bool, _ size: CGSize) -> NSView? = { _, _, _ in nil }
    /// Host hook: builds the SLIDER (slideshow) view for a group's `mediaIDs` at the full-bleed `width`,
    /// sized (frame height) to its content; the editor learns that height back. nil = none.
    var mediaGroupSliderProvider: (_ mediaIDs: [String], _ width: CGFloat) -> NSView? = { _, _ in nil }
    /// Host-provided overlay controls for a media block (collage/slider/single image·video). Given the
    /// block id, kind, media-area size, and per-tile frames (controls-local coords), returns a view the
    /// canvas positions over the media area (above tiles + select overlays). nil → no controls.
    var mediaControlsProvider: ((MediaControlsContext) -> NSView?)? { didSet { needsLayout = true } }
    /// Host hook: present a custom (TGUIKit) context menu. Called from `menu(for:)` with the click location
    /// (canvas coords), the media under it, and the selection state; returning true suppresses the native menu.
    var contextMenuRequested: ((_ location: NSPoint, _ media: EditorMediaContext?, _ hasSelection: Bool, _ event: NSEvent) -> Bool)?
    /// Live collage tile views keyed by "groupID#index" so they survive edits/undo while the group persists.
    var mediaGroupTileViews: [String: HostedMediaBlock] = [:]
    /// Click-to-select overlay per collage TILE (above the tile), keyed by "groupID#index".
    var mediaGroupOverlays: [String: MediaInteractionOverlayView] = [:]
    /// Realized media-controls overlays, pooled by block id, with the layout signature each was built for
    /// (a position-only change just repositions; a structural change rebuilds).
    var mediaControlsViews: [String: NSView] = [:]
    var mediaControlsSignatures: [String: String] = [:]
    /// The single collage tile the user clicked (highlighted; Backspace removes just it). Separate from the
    /// text selection. Cleared on a click elsewhere / typing.
    var selectedCollageTile: (group: BlockID, index: Int)?
    /// Viewport inset (points) within which off-screen media views stay live (not hidden).
    var mediaBlockCullMargin: CGFloat = 50
    /// INTERACTIVE overlay (unlike emoji/spoiler) ABOVE the spoiler overlay; hosts every media view.
    /// Hits inside a media view reach it; empty areas pass THROUGH to the canvas (text editing).
    lazy var mediaBlockHost: NSView = {
        let v = InteractiveMediaOverlayView(); v.wantsLayer = true
        addSubview(v, positioned: .above, relativeTo: spoilerOverlay)
        return v
    }()

    /// Last non-zero width laid out; used to rebuild boxes during undo (extensions can't add
    /// stored properties, so it lives here).
    var lastLayoutWidth: CGFloat = 0
    var effectiveWidth: CGFloat { lastLayoutWidth > 0 ? lastLayoutWidth : (bounds.width > 0 ? bounds.width : 320) }
    /// Last content height reported to the host. `onContentSizeChange` fires from `invalidateIntrinsicContentSize`
    /// BEFORE `layout()` recomputes the per-box facing insets, so a freshly-created box is summed with stale
    /// (default) insets; re-reporting post-layout (when insets are correct) settles the host to the right height.
    private var lastReportedContentHeight: CGFloat = -1

    func clampGlobal(_ n: Int) -> Int { min(max(n, 0), documentSize) }

    /// Resolves a global position to the box that owns it, snapping structural-boundary and
    /// end-of-document positions to the nearest in-text position. Returns the box, the local
    /// UTF-16 offset, and the box's index.
    func resolveBox(at pos: Int) -> (box: CanvasBlock, local: Int, index: Int)? {
        if let (b, l) = box(containingGlobal: pos), let i = boxIndex(of: b) { return (b, l, i) }
        for (i, b) in boxes.enumerated() {
            if pos < b.textStart { return (b, 0, i) }
            if pos <= b.textStart + b.textLength { return (b, pos - b.textStart, i) }
        }
        if let last = boxes.last { return (last, last.textLength, boxes.count - 1) }
        return nil
    }
    private(set) var documentSize = 0
    var selFrom: Int { min(anchor, head) }
    var selTo: Int { max(anchor, head) }

    /// Transient table row/column structural selection (separate from the text selection). The `table` id
    /// guards against a stale selection after the active table is rebuilt. nil = none.
    var tableSelection: (table: BlockID, kind: TableStructuralSelection)?
    var draggingEndpoint: SelectionEndpoint?
    var draggingTableKnob: TableRangeEnd?
    /// The mouse-down point for a text drag; the selection only starts extending once the pointer moves
    /// past a small threshold, so a click with a tiny tremor places a caret instead of selecting text.
    var textDragOrigin: CGPoint?
    /// Injectable pasteboard (defaults to the system pasteboard; tests inject a fake — see TextPasteboard).
    var pasteboard: TextPasteboard = NSPasteboardAdapter()   // NSPasteboardAdapter defined in +EditMenu.swift (same target)
    /// Word/paragraph/line boundary helper (AppKit replacement for UITextInputTokenizer).
    lazy var tokenizer = DocumentTokenizer(canvas: self)
    var undoManagerOverride: UndoManager?
    /// The editor owns a DEDICATED undo manager rather than borrowing the responder chain's (the window /
    /// modal one). Sharing it mixed the canvas's `DocumentCanvasView`-typed `registerUndo` handlers with the
    /// modal's own registrations, so a menu ⌘Z (Edit▸Undo) could invoke a canvas handler with the modal's
    /// `ModalBackground` target → `Could not cast ModalBackground to DocumentCanvasView`. Isolating it fixes
    /// that and keeps editor undo from undoing unrelated app actions.
    private let ownUndoManager = UndoManager()
    var effectiveUndoManager: UndoManager? { undoManagerOverride ?? ownUndoManager }
    /// Route the responder-chain undo manager (which the system Edit▸Undo / ⌘Z targets) to ours, so menu
    /// undo/redo drives the editor when it's first responder.
    override var undoManager: UndoManager? { effectiveUndoManager }

    /// Coalescing kind for an edit: consecutive `.typing` (or consecutive `.deleting`) edits that are
    /// contiguous collapse into ONE undo step; `.none` always starts/breaks a step (structural, format,
    /// paste, media, list, table edits).
    enum UndoCoalescing { case typing, deleting, none }
    /// The currently-open coalescing run. `caret` is where the NEXT contiguous keystroke must land for it
    /// to join this run. `nil` = no open run (the next edit registers a fresh undo step).
    var openUndoRun: (kind: UndoCoalescing, caret: Int)?
    /// Closes any open coalescing run so the next edit registers a fresh undo step. Called on every
    /// run-breaking boundary the contiguity check can't see (document swap / undo-redo restore, resign-FR).
    func breakUndoCoalescing() { openUndoRun = nil }

    /// Horizontal page/content margin. Defaults to the document look (`CanvasMetrics.pageMargin`); a compact
    /// host (the inline chat composer) sets a small value so text aligns with the plain input. It drives the
    /// block layout origin/width AND every media block's edge-bleed (kept in sync in `layout()`).
    var contentMargin: CGFloat = CanvasMetrics.pageMargin {
        didSet { guard oldValue != contentMargin else { return }; needsLayout = true }
    }

    /// Host toggle for the table structural controls (the ⋮ row / ••• column handles and, via them, the
    /// resize knobs). The inline chat composer hides them; the modal editor keeps them.
    var showsTableControls: Bool = true {
        didSet { guard oldValue != showsTableControls else { return }; needsDisplay = true }
    }

    /// Host hook consulted on paste, AFTER the editor's own rich fragment but BEFORE the plain-string
    /// fallback: lets the app convert its private pasteboard formats (e.g. the chat input's entity
    /// payload, carrying custom emoji/formatting) into a `[Block]` fragment. Return nil/empty to decline.
    var hostPasteFragmentProvider: (() -> [Block]?)?
    var withPasteContext: ((() -> Void) -> Void)?

    /// The overflowing (horizontally scrollable) table under `point` (canvas coords), if any. Also the
    /// predicate hosts use to make global horizontal-swipe handlers (navigation back) yield to the pan.
    func horizontallyScrollableTable(at point: CGPoint) -> TableBlockBox? {
        return boxes.compactMap { $0 as? TableBlockBox }.first { $0.frame.contains(point) && $0.maxScrollX > 0 }
    }

    /// Route a horizontal trackpad scroll over an overflowing table into that table's own `scrollX`
    /// (columns clamp at a minimum width, so a table wider than the host pans instead of squeezing).
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            let point = convert(event.locationInWindow, from: nil)
            if let table = horizontallyScrollableTable(at: point) {
                let clamped = max(0, min(table.maxScrollX, table.scrollX - event.scrollingDeltaX))
                if clamped != table.scrollX {
                    table.scrollX = clamped
                    table.recompute()
                    needsLayout = true
                    needsDisplay = true
                }
                return
            }
        }
        super.scrollWheel(with: event)
    }

    /// Auto-pans the caret's table so its active column stays visible while editing — the horizontal
    /// analog of the vertical caret-follow (`onCaretMoved`). No-op unless the caret is inside a table
    /// that overflows horizontally.
    private func autoScrollCaretTableIntoView() {
        for table in boxes.compactMap({ $0 as? TableBlockBox }) {
            guard let loc = table.cellLocation(containing: head) else { continue }
            if table.scrollToReveal(column: loc.column) {
                table.recompute()
                needsLayout = true
                needsDisplay = true
            }
            break
        }
    }

    // Self-drawn blinking caret (AppKit has no UITextSelectionDisplayInteraction).
    private var caretTimer: Timer?
    var caretVisible = false

    /// Format toggles pending at a bare caret — applied to the next typed text, cleared on caret move.
    var pendingFormatToggles: Set<PendingFormatToggle> = []
    /// True when a character-format command should target typing (no selection, not a table selection).
    var isCollapsedTextCaret: Bool { tableSelection == nil && selFrom == selTo }
    /// Fired when the selection, caret, or active formatting may have changed — a host toolbar refreshes
    /// its active-state highlight from `currentCharacterFormatState()`.
    var onSelectionOrFormatChange: (() -> Void)?
    /// Fired when the caret moves (separate from the host-facing hook above) so the editor can keep the
    /// caret visible by scrolling its enclosing scroller.
    var onCaretMoved: (() -> Void)?
    /// Fired after a click on a code block's language header copied the code (host shows feedback).
    /// LEGACY: the header band was replaced by the always-visible, editable language line, so nothing
    /// fires this anymore; kept so existing host wiring keeps compiling.
    var onCodeCopied: (() -> Void)?
    /// Fired when the language header (outside the copy zone) was clicked. LEGACY: the language is now
    /// authored directly in the block's editable language line; kept so existing host wiring compiles.
    var onCodeHeaderClicked: (() -> Void)?

    /// Host-supplied syntax highlighter: (language, text, completion). nil disables highlighting entirely.
    /// The editor cannot call libprisma itself — see `RichTextSyntaxToken`.
    var syntaxHighlighter: ((String, String, @escaping ([RichTextSyntaxToken]) -> Void) -> Void)?
    /// Answers, keyed by (normalized language, exact text), each stamped with the palette it was produced
    /// under. In-memory and per-canvas; nothing persists.
    var syntaxHighlightCache: [CodeHighlightSpec: CachedSyntaxHighlight] = [:]
    /// Specs already requested and not yet answered, mapped to the palette they were requested under, so a
    /// second pass does not re-ask — but a pass running under a NEW palette still does.
    var inFlightSyntaxHighlightSpecs: [CodeHighlightSpec: String] = [:]
    /// Identity of the palette the host currently bakes into its answers, derived from `editorAppearance`.
    /// An answer carrying a different token is stale: still worth painting as a placeholder, never worth
    /// keeping instead of re-asking.
    var syntaxHighlightPaletteToken: String = richTextSyntaxPaletteToken(.default)
    /// Debounce for the highlight pass. Tests set 0 to fire on the next runloop turn.
    var syntaxHighlightDebounceInterval: TimeInterval = 0.3
    /// The scheduled pass, cancelled and replaced by each new edit. Internal (not `private`) so the
    /// `+SyntaxHighlight` extension in another file can reach it.
    var pendingSyntaxHighlightWork: DispatchWorkItem?
    /// Counts repaints caused by a colour change; read by tests through `codeHighlightRepaintCountForTesting`.
    var codeHighlightRepaintCount: Int = 0
    /// Host hook: asked to present the button property editor (label / URL / style / delete) for a
    /// clicked pill. `isBlockPill` distinguishes a row pill from an inline `textButton`; the completion
    /// applies the edited button, or removes the pill on nil. Wiring this ALSO enables the button
    /// authoring chrome (the row's "…" affordance) — a host that leaves it nil (the inline chat
    /// composer) keeps pills preservation-only, rendering exactly like the sent message.
    var buttonEditRequested: ((_ button: ButtonRef, _ isBlockPill: Bool, _ completion: @escaping (ButtonRef?) -> Void) -> Void)? {
        didSet { stampButtonRowAffordances() }
    }

    /// The caret rect for the current selection head, in canvas coordinates.
    func currentCaretRect() -> CGRect { caretRect(forGlobal: head) }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    /// Bridge key events into the NSTextInputClient machinery: the input context routes committed text to
    /// `insertText(_:replacementRange:)` and command keys to `doCommand(by:)` (→ our `moveLeft:`/
    /// `insertNewline:`/`deleteBackward:`/… selectors). Without this override, `NSResponder`'s default
    /// `keyDown` ignores the event — no typed character or arrow key ever reaches the editor.
    override func keyDown(with event: NSEvent) {
        if hasMarkedText() {
            if inputContext?.handleEvent(event) != true { super.keyDown(with: event) }
            return
        }
        // Return semantics. Shift+Enter always starts a fresh plain body paragraph (breaking out of a
        // list / heading / quote — the new empty paragraph shows the "Type something…" placeholder), or
        // leaves the table from a cell. In a LIST item, Enter continues the list with a new item (and
        // outdents / leaves the list when the item is empty); elsewhere Enter is a soft line break that
        // stays in the paragraph/cell. Handled here so it's deterministic regardless of input-context
        // routing.
        if event.keyCode == 36 || event.keyCode == 76 {   // Return / keypad Enter
            // Return in a code block's LANGUAGE line moves the caret to the start of the code text. It
            // inserts nothing and splits nothing: a `.Pre` language has no second line. (The quote author
            // splits instead, because it is a TRAILING region — the tail becomes a paragraph after the
            // quote. A leading region has no such tail.) Handled FIRST: a language caret resolves to no
            // `activeStack`, so the branches below would misroute it (e.g. `caretAtQuoteTrailingBlankLine`
            // snaps it onto the code box and could un-make an empty block).
            if selFrom == selTo, !event.modifierFlags.contains(.shift),
               let (region, _) = leafRegion(containingGlobal: head),
               case let .codeLanguage(id) = region.ref,
               let owner = stackContainingCodeBox(id: id) {
                setCaret(global: owner.box.textStart)
                return
            }
            let listBox = activeListBox()
            if event.modifierFlags.contains(.shift) {
                clearTableSelection()
                if isInsideTable(head) {
                    exitTableBelow()                       // Shift+Enter in a cell leaves the table
                } else if selFrom == selTo, let img = imageBox(atGap: head), let i = boxIndex(of: img) {
                    editing { insertParagraphBeforeImage(at: i, text: "") }
                } else if selFrom == selTo, let pos = resolveBox(at: head),
                          pos.box is MediaBlockBox || pos.box is ImageBlockBox || pos.box is MediaGroupBlockBox || pos.box is CodeBlockBox || pos.box is PullQuoteBox || pos.box is ButtonRowBox {
                    editing { insertParagraphAfterBlock(at: pos.index) }   // exit a media/image/collage caption, a code block, a pull quote, or a button row into a new paragraph
                } else {
                    insertParagraphBreak(newParagraphAsBody: true)   // fresh body paragraph for ALL types
                }
            } else if let listBox {
                if listBox.textLength == 0 {               // Enter on an empty item: step out of the list
                    if (listBox.listMembership?.level ?? 0) > 0 { outdent() } else { setList(nil) }
                } else {
                    insertParagraphBreak()                 // Enter in a list: new list item
                }
            } else if caretAtQuoteTrailingBlankLine() {
                exitQuoteBelow()                           // double-return exits the code/pull-quote block
            } else if caretAtBlockQuoteTrailingBlankLine() {
                exitBlockQuoteBelow()                      // double-return exits the block quote to a body paragraph
            } else {
                commitText("\n")                           // non-list: soft line break
            }
            return
        }
        if inputContext?.handleEvent(event) != true { super.keyDown(with: event) }
    }

    init(mapper: AttributedStringMapper = AttributedStringMapper()) {
        self.mapper = mapper
        self.editorAppearance = mapper.appearance
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = .clear   // the editor surface is always transparent (shows the host through)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    deinit {
        // Tear down any still-hosted media views so their injected content nodes release subscriptions
        // (the host's `clean()`), rather than leaking with a live status signal.
        for (_, h) in mediaBlockViews { mediaBlockViewWillRemove?(h.view) }
        for (_, view) in mediaControlsViews { view.removeFromSuperview() }   // parity with the media-view teardown
        caretTimer?.invalidate()
    }

    /// Builds a box per block (paragraph, image, or table). Tables become `TableBlockBox`es whose
    /// cells the canvas reaches via `leafRegions()`.
    func setBlocks(_ blocks: [Block], width: CGFloat) {
        setModelBlocks(blocks.map { .core($0) }, width: width)
    }

    /// Builds the boxes from the canvas's internal currency (`.core` core blocks + macOS-only `.media`).
    /// `setBlocks([Block])` and undo restore both route through here.
    func setModelBlocks(_ blocks: [CanvasModelBlock], width: CGFloat) {
        unmarkText()
        if width > 0 { lastLayoutWidth = width }
        breakUndoCoalescing()   // a full document swap — programmatic set OR an undo/redo restore — ends any open typing/deleting run
        // `width` here is the raw canvas width; the per-box TextKit layout is re-done at the content width
        // (bounds − 2·pageMargin) on the next `layout()` pass, so this init width is a transient hint.
        boxes = blocks.compactMap { modelBlock -> CanvasBlock? in
            switch modelBlock {
            case .core(let block):
                return makeBox(for: block, mapper: mapper, width: width)
            case .media(let m):
                // All embedded media — image included — is a hosted view. An image renders via
                // `ChatInteractiveContentView` (native blur+dust spoiler + tap-to-reveal) exactly like video,
                // resolved from `mediaID` through the host's media-view provider.
                return MediaBlockBox(media: m, mapper: mapper, width: width)
            case .mediaGroup(let g):
                let box = MediaGroupBlockBox(group: g, mapper: mapper, width: width)
                box.mosaicProvider = mediaGroupMosaic
                return box
            }
        }
        recomputeSpans()
        anchor = min(anchor, documentSize); head = min(head, documentSize)
        recomputeDocumentHasSpoilers()                   // model changed: refresh the fast-path gate
        // Re-apply what we already know BEFORE the first draw of the new boxes: a rebuild (theme change /
        // undo restore) reconstructs them from the model, which carries no colours, and waiting for the
        // debounced pass would show a plain frame first.
        reapplyCachedSyntaxHighlights()
        scheduleSyntaxHighlightPass()                    // a document seed / undo restore changes every spec
        invalidateIntrinsicContentSize(); needsLayout = true; needsDisplay = true
    }

    /// Media-preserving seed: maps the public send model back to internal `CanvasModelBlock`s (the inverse
    /// of `outgoingBlocks()`), so media survives reopening a draft. Image `naturalSize` is recovered from the
    /// already-registered asset (via `imageProvider`); unknown media kinds are dropped.
    func setOutgoingBlocks(_ blocks: [RichTextOutgoingBlock], width: CGFloat) {
        let model: [CanvasModelBlock] = blocks.compactMap { block in
            switch block {
            case .paragraph(let p): return .core(.paragraph(p))
            case .table(let t): return .core(.table(t))
            case .code(let c): return .core(.code(c))
            case .pullQuote, .blockQuote: return block.coreBlock.map { .core($0) }
            case .buttonRow(let r): return .core(.buttonRow(r))
            case let .media(kind, mediaID, caption, spoiler):
                guard let k = MediaKind(rawValue: kind) else { return nil }
                var naturalSize = Size2D(width: 0, height: 0)
                if k == .image, let img = imageProvider(mediaID) {
                    naturalSize = Size2D(width: img.size.width, height: img.size.height)
                }
                return .media(MediaBlock(id: BlockID.generate(), kind: k, mediaID: mediaID, naturalSize: naturalSize, caption: caption, spoiler: spoiler))
            case let .mediaGroup(kind, mediaIDs, caption, spoilers):
                guard let k = MediaGroupKind(rawValue: kind) else { return nil }
                return .mediaGroup(MediaGroupBlock(id: BlockID.generate(), kind: k, mediaIDs: mediaIDs, caption: caption, spoilers: spoilers))
            }
        }
        setModelBlocks(model.isEmpty ? [.core(.paragraph(ParagraphBlock(id: BlockID.generate())))] : model, width: width)
    }

    /// Undo currency: preserves macOS-only media blocks.
    func currentModelBlocks() -> [CanvasModelBlock] { boxes.map { $0.currentModelBlock() } }

    /// Public/serialization currency: core blocks only (media blocks are dropped — persistence deferred).
    func currentBlocks() -> [Block] {
        currentModelBlocks().compactMap { if case .core(let b) = $0 { return b } else { return nil } }
    }

    /// Send-oriented currency: core blocks PLUS the macOS-local media / media-group blocks (as `kind` +
    /// `mediaID`s), so a host can resolve and serialize media. See `RichTextOutgoingBlock`.
    func outgoingBlocks() -> [RichTextOutgoingBlock] {
        currentModelBlocks().compactMap { block in
            switch block {
            case .core(let core):
                return RichTextOutgoingBlock(core: core)
            case .media(let m):
                return .media(kind: m.kind.rawValue, mediaID: m.mediaID, caption: m.caption, spoiler: m.spoiler)
            case .mediaGroup(let g):
                return .mediaGroup(kind: g.kind.rawValue, mediaIDs: g.mediaIDs, caption: g.caption, spoilers: g.spoilers)
            }
        }
    }

    func setParagraphs(_ paragraphs: [ParagraphBlock], width: CGFloat) {
        setBlocks(paragraphs.map { .paragraph($0) }, width: width)
    }

    func currentParagraphs() -> [ParagraphBlock] {
        boxes.compactMap { ($0 as? BlockBox)?.currentParagraph() }
    }

    /// Assigns each box its `nodeStart` (= prior tokens + 1) and accumulates `documentSize` from each
    /// box's `nodeSize` (paragraph: textLength+2; image: textLength+5). Matches `RichTextEditorCore`
    /// row-major token addressing.
    func recomputeSpans() {
        documentSize = root.recompute(baseOffset: 0)
        for case let t as TableBlockBox in boxes { t.recompute() }
        for case let bq as BlockQuoteBox in boxes { bq.recompute() }
        stampButtonRowAffordances()
    }

    /// Stamps each button row's "…" affordance from whether a host wired the button editor — a
    /// CAPABILITY, not a style choice (the `hostsChecklistCheckbox` shape). Runs on every span pass so
    /// freshly created / pasted rows are stamped too.
    func stampButtonRowAffordances() {
        let shows = buttonEditRequested != nil
        for case let row as ButtonRowBox in allBoxesForButtons() {
            row.showsMenuAffordance = shows
        }
    }

    /// The box whose text contains `pos` (inclusive of the trailing caret slot), or nil at a
    /// structural boundary between blocks.
    func box(containingGlobal pos: Int) -> (box: CanvasBlock, local: Int)? {
        for box in boxes where pos >= box.textStart && pos <= box.textStart + box.textLength {
            return (box, pos - box.textStart)
        }
        return nil
    }

    /// All editable leaf regions in document order (recurses into tables). v1: rebuilt per call; cache
    /// if profiling shows it matters.
    func allLeafRegions() -> [LeafTextRegion] { root.leafRegions() }

    /// The leaf region containing `pos` (inclusive of the trailing caret slot), with the local offset.
    func leafRegion(containingGlobal pos: Int) -> (region: LeafTextRegion, local: Int)? {
        for r in allLeafRegions() where pos >= r.globalStart && pos <= r.globalStart + r.length {
            return (r, pos - r.globalStart)
        }
        return nil
    }

    /// True when `pos` lands in a quote's author line (a `.quoteAuthor` leaf region). Author regions are
    /// a SECOND editable region with their own layout, so the `resolveBox`/`activeStack` resolvers (which
    /// key off a box's primary text region) misroute them — callers that must edit the author route
    /// through the region-aware `leafRegion` / `applyLeafReplace` instead.
    func isAuthorPosition(_ pos: Int) -> Bool {
        guard let ref = leafRegion(containingGlobal: pos)?.region.ref else { return false }
        if case .quoteAuthor = ref { return true }
        return false
    }

    /// True when `pos` lands in a code block's language line (a `.codeLanguage` leaf region). Like a
    /// quote's author line, it is a SECOND editable region with its own layout, off the
    /// `resolveBox`/`activeStack` resolvers' radar — callers that must edit it route through the
    /// region-aware `leafRegion` / `applyLeafReplace` instead.
    func isCodeLanguagePosition(_ pos: Int) -> Bool {
        guard let ref = leafRegion(containingGlobal: pos)?.region.ref else { return false }
        if case .codeLanguage = ref { return true }
        return false
    }

    func boxIndex(of box: CanvasBlock) -> Int? { boxes.firstIndex { $0 === box } }

    /// Public-within-module accessor for the façade.
    var documentSizeValue: Int { documentSize }

    /// Re-flows boxes to a new width if it changed (called from the façade's layout).
    func setParagraphsWidthIfNeeded(_ width: CGFloat) {
        let content = max(width - contentMargin * 2, 1)
        guard let first = boxes.first, abs(first.frame.width - content) > 0.5 || first.frame.width == 0 else { return }
        for box in boxes { box.setWidth(content) }
        recomputeSpans()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        if bounds.width > 0 { lastLayoutWidth = bounds.width }
        // Keep every media block's bleed margin in sync with the canvas margin before it draws.
        for case let media as MediaControlsProviding in boxes { media.contentMargin = contentMargin }
        let contentHeight = root.layout(origin: CGPoint(x: contentMargin, y: 0),
                                        width: max(bounds.width - contentMargin * 2, 1))
        for case let t as TableBlockBox in boxes { t.recompute() }   // cell frames depend on the table frame
        for case let bq as BlockQuoteBox in boxes { bq.recompute() }   // child frames depend on the quote frame
        emojiOverlay.frame = bounds                                  // sits above the canvas's drawn content; clicks pass through
        syncEmojiViews()                                            // reconcile host emoji views post-layout
        spoilerOverlay.frame = bounds                                // dust sits above emoji; clicks pass through
        syncSpoilers()                                              // reconcile clear-foreground hide + dust views post-layout
        mediaBlockHost.frame = bounds                                // interactive media views, above the rest
        syncMediaBlockViews()                                        // reconcile host media-block views post-layout
        syncMediaGroupViews()                                        // reconcile collage tile views post-layout
        updateMediaSelectionHighlight()                              // selection overlay tracks the new frames
        // Re-report the height now that facing insets are correct (the invalidate-time report used stale
        // insets). Guarded by change so the host's re-measure → frame change → layout() doesn't loop.
        if abs(contentHeight - lastReportedContentHeight) > 0.5 {
            lastReportedContentHeight = contentHeight
            onContentSizeChange?()
        }
    }

    override var intrinsicContentSize: NSSize {
        // From the layout root, not a sum of box heights — a bare inter-atom gap belongs to no box
        // frame and a plain sum under-reports it (see BlockStack.currentHeight).
        NSSize(width: NSView.noIntrinsicMetric, height: root.currentHeight)
    }

    /// The canvas is frame-managed by its host, so this is a no-op for layout on its own; forward the
    /// signal to the host (`onContentSizeChange`) so it re-flows the canvas frame + scroll content size.
    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onContentSizeChange?()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // 0) block background decorations (blockquote bar+fill), behind everything
        drawBlockquoteDecorations(in: ctx)
        // 1) selection highlight, behind text — the native macOS text-selection color (emphasized blue
        // while focused, the system's unemphasized gray otherwise), so it reads as a real text selection.
        if selFrom != selTo {
            let focused = window?.firstResponder === self
            (focused ? editorAppearance.selectionFocused : editorAppearance.selectionUnfocused).setFill()
            for r in selectionRects(globalFrom: selFrom, globalTo: selTo) { ctx.fill(r) }
        }
        // 2) each box draws itself (decoration/grid + text)
        root.draw(in: ctx, imageProvider: imageProvider)
        if let range = markedTextState?.range {
            editorAppearance.defaultForeground.setFill()
            for rect in selectionRects(globalFrom: range.location, globalTo: NSMaxRange(range)) {
                ctx.fill(CGRect(x: rect.minX, y: rect.maxY - 1, width: rect.width, height: 1))
            }
        }
        // 2.05) accent wash over a click-selected image (drawn ON TOP of the opaque bitmap)
        drawImageSelectionHighlight(in: ctx)
        // 2.5) list markers in the gutter (computed by Core ListNumbering; not in the text storage)
        drawListMarkers(in: ctx)
        // table structural-selection outline + row/column handles
        drawTableSelectionOutline(in: ctx)
        drawTableHandles(in: ctx)
        drawTableResizeKnobs(in: ctx)
        // 2.6) placeholders for empty regions (title, body)
        drawPlaceholders(in: ctx)
        // 3) self-drawn caret: only when collapsed, eligible, blink-on, and a real rect exists.
        if selFrom == selTo, isCaretEligible, caretVisible {
            let rect = caretRect(forGlobal: head)
            if rect != .zero { editorAppearance.caretColor.setFill(); ctx.fill(rect) }
        }
    }

    /// Hidden during a table-structural selection or when not focused (mirrors caretRect rules).
    private var isCaretEligible: Bool {
        tableSelection == nil && (window?.firstResponder === self)
    }

    /// Rect-union: clamp the global range to each box, enumerate that box's `.selection` segments,
    /// offset into canvas coordinates. The cross-block continuous highlight.
    func selectionRects(globalFrom: Int, globalTo: Int) -> [CGRect] {
        var rects: [CGRect] = []
        for r in allLeafRegions() {
            let lo = max(globalFrom, r.globalStart), hi = min(globalTo, r.globalStart + r.length)
            guard lo < hi else { continue }
            for seg in r.layout.selectionRects(start: lo - r.globalStart, end: hi - r.globalStart) {
                rects.append(seg.offsetBy(dx: r.canvasOrigin.x, dy: r.canvasOrigin.y))
            }
        }
        return rects
    }

    /// Maps a point in canvas coordinates to the closest global text position.
    func closestGlobalPosition(to point: CGPoint) -> Int { root.closestPosition(toCanvasPoint: point) }

    /// True if `pos` is the gap before a single-media atom (image / file·audio·map·video — an
    /// `ImageBlockBox` or `MediaBlockBox` `nodeStart`; a group has its own handling).
    func isGapPosition(_ pos: Int) -> Bool {
        boxes.contains { ($0 is ImageBlockBox || $0 is MediaBlockBox) && $0.nodeStart == pos }
    }

    /// The single-media box (image or file·audio·map·video) whose gap-before-atom is at `pos`, if any.
    /// Named `imageBox` for history; images are hosted `MediaBlockBox`es now, so this matches both.
    func imageBox(atGap pos: Int) -> (any CanvasBlock)? {
        boxes.first { ($0 is ImageBlockBox || $0 is MediaBlockBox) && $0.nodeStart == pos }
    }

    // MARK: - Selection mutation (all bracket notifySelectionChanged)

    /// Sets a collapsed caret (clears the drag anchor).
    func setCaret(global pos: Int) {
        clearTableSelection()
        pendingFormatToggles.removeAll()                 // explicit caret move discards pending typing format
        anchor = pos; head = pos
        needsDisplay = true; notifySelectionChanged()
    }

    /// Moves the selection head, keeping the anchor (drag-to-select).
    func setSelectionHead(global pos: Int) {
        clearTableSelection()
        pendingFormatToggles.removeAll()
        head = pos
        needsDisplay = true; notifySelectionChanged()
    }

    /// Moves the selection anchor (keeps the head).
    func setSelectionAnchor(global pos: Int) {
        clearTableSelection()
        pendingFormatToggles.removeAll()
        anchor = pos
        needsDisplay = true; notifySelectionChanged()
    }

    // MARK: - Caret blink lifecycle + selection-change notification

    /// Replaces the old UITextInputDelegate bracketing. NSTextInputClient wants character-coordinate
    /// invalidation on selection changes; also restarts the caret blink (show immediately).
    /// `caretMoved: false` suppresses the host caret-follow scroll (`onCaretMoved`) — pass it for edits
    /// that changed content/format WITHOUT moving the selection (e.g. a toolbar formatting action on a
    /// remote selection), so the viewport doesn't jump back to an off-screen caret.
    func notifySelectionChanged(caretMoved: Bool = true) {
        if !isUpdatingTextInput {
            unmarkText()
        }
        inputContext?.invalidateCharacterCoordinates()
        restartCaretBlink()
        syncSpoilers()                                   // a caret/selection landing in a hidden run reveals it
        updateMediaSelectionHighlight()                  // media inside the selection shows the select colour
        updateMediaGroupSelectionHighlight()             // …and collages/sliders inside the selection
        onSelectionOrFormatChange?()
        if caretMoved {
            autoScrollCaretTableIntoView()
            onCaretMoved?()
        }
    }

    func startCaretBlink() {
        caretVisible = true
        caretTimer?.invalidate()
        caretTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.caretVisible.toggle(); self.needsDisplay = true
        }
        needsDisplay = true
    }
    func stopCaretBlink() { caretTimer?.invalidate(); caretTimer = nil; caretVisible = false; needsDisplay = true }
    func restartCaretBlink() { if window?.firstResponder === self { startCaretBlink() } }

    override func becomeFirstResponder() -> Bool {
        startCaretBlink(); needsDisplay = true
        return super.becomeFirstResponder()
    }
    override func resignFirstResponder() -> Bool {
        unmarkText()
        stopCaretBlink(); clearTableSelection(); draggingEndpoint = nil; draggingTableKnob = nil
        breakUndoCoalescing()   // losing focus ends any open typing/deleting run (matches native)
        return super.resignFirstResponder()
    }

    /// Demo helper: set a selection spanning the middle of two blocks by index.
    func selectAcrossBlocks(firstIndex: Int, secondIndex: Int) {
        guard boxes.indices.contains(firstIndex), boxes.indices.contains(secondIndex) else { return }
        anchor = boxes[firstIndex].textStart + boxes[firstIndex].textLength / 2
        head = boxes[secondIndex].textStart + boxes[secondIndex].textLength / 2
        window?.makeFirstResponder(self)
        needsDisplay = true; notifySelectionChanged()
    }

    /// Demo helper: set a selection spanning mid-way through two leaf regions by document-order index.
    func selectAcrossLeafRegions(firstLeaf: Int, secondLeaf: Int) {
        let regions = allLeafRegions()
        guard regions.indices.contains(firstLeaf), regions.indices.contains(secondLeaf) else { return }
        let r1 = regions[firstLeaf], r2 = regions[secondLeaf]
        anchor = r1.globalStart + max(1, r1.length / 2)
        head   = r2.globalStart + max(1, r2.length / 2)
        window?.makeFirstResponder(self)
        needsDisplay = true; notifySelectionChanged()
    }
}
#endif
