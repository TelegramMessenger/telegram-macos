#if canImport(AppKit)
import AppKit
import RichTextEditorCore

/// The media under a right-click, handed to the host context-menu handler so it can offer media actions
/// (add to collage, collage/slider toggle, …). `kind` is one of `image`/`video`/`file`/`audio`/`map`
/// (single media) or `collage`/`slideshow` (a group); `blockID` identifies the block for the edit ops.
@available(macOS 12, *)
public struct EditorMediaContext {
    public let blockID: String
    public let kind: String
}

/// Public façade. Renders all block types (paragraphs, images, tables) in a vertical canvas
/// with continuous cross-block selection.
@available(macOS 12, *)
public final class RichTextEditorView: NSView {
    private let scrollView = HostScrollForwardingScrollView()
    let canvas = DocumentCanvasView()
    private var assets: [String: NSImage] = [:]

    public override init(frame: NSRect) {
        super.init(frame: frame)
        scrollView.hasVerticalScroller = true
        // Always-transparent editor surface: a non-drawing scroll view AND clip view, so the host
        // background shows through (the clip view otherwise fills its default control-white background).
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.documentView = canvas
        addSubview(scrollView)
        canvas.imageProvider = { [weak self] id in self?.assets[id] }
        // The canvas is sized frame-based in layout(), so a content-height change (typing wraps a
        // line, a cell grows, undo, …) must re-trigger our layout — otherwise it only updates on
        // the next layout pass (e.g. a window resize).
        canvas.onContentSizeChange = { [weak self] in
            self?.needsLayout = true
            self?.onContentHeightChange?()
        }
        // Keep the caret visible while typing / adding paragraphs. When the editor doesn't scroll itself
        // (isScrollEnabled == false), it lives inside the host's scroller, so scrolling `self` into view
        // drives the host scroll.
        canvas.onCaretMoved = { [weak self] in self?.scrollCaretToVisible() }
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    public override var isFlipped: Bool { true }

    /// Injectable editor theming. Named `editorAppearance` rather than `appearance` because
    /// `NSView.appearance` already exists as `NSAppearance?` and can't be shadowed with a different type.
    public var editorAppearance: EditorAppearance {
        get { canvas.editorAppearance }
        set { canvas.editorAppearance = newValue }   // editor surface stays transparent; `background` is not applied to the view
    }

    /// Horizontal content margin (document look by default). A compact host (the inline chat composer) sets a
    /// small value so the editor text aligns with the plain input rather than a wide document margin.
    public var contentMargin: CGFloat {
        get { canvas.contentMargin }
        set { canvas.contentMargin = newValue; needsLayout = true }
    }

    /// When `false`, the editor does not scroll internally: wheel events fall through to the enclosing
    /// scroller, and the host is expected to size the editor to its full `contentHeight` (e.g. a growing
    /// row inside a scrolling InputData table). In this mode the canvas is detached from the internal
    /// scroll view and hosted directly, so no NSScrollView remains in an NSTableView row's accessibility
    /// hierarchy.
    public var isScrollEnabled: Bool = true {
        didSet {
            guard oldValue != isScrollEnabled else { return }
            updateCanvasHost()
        }
    }

    /// When `false`, the editor still scrolls (wheel/trackpad) but shows no scroller — for a compact host
    /// (the inline chat composer) that doesn't want a scrollbar over the content.
    public var showsScroller: Bool = true {
        didSet {
            guard oldValue != showsScroller else { return }
            scrollView.hasVerticalScroller = isScrollEnabled && showsScroller
        }
    }

    /// The editor's current intrinsic content height (the canvas's laid-out content height). Use to
    /// drive a host row's dynamic height; observe changes via `onContentHeightChange`.
    public var contentHeight: CGFloat { max(canvas.intrinsicContentSize.height, 0) }

    /// Fired when the editor's content height may have changed (typing wraps a line, a block is added,
    /// undo, …) so a host can re-measure its row.
    public var onContentHeightChange: (() -> Void)?

    /// The text-input responder used by hosts which manage focus themselves. Returning the canvas avoids
    /// routing focus through this façade's `becomeFirstResponder`, which would re-enter NSWindow.
    public var inputResponder: NSResponder { canvas }

    /// Intercepts the Return key. Return `true` to consume it (no paragraph break inserted) — e.g. an inline
    /// composer host that sends on Return and forbids new paragraphs (text-only inline editing).
    public var onReturnKey: (() -> Bool)? {
        get { canvas.onReturnKey }
        set { canvas.onReturnKey = newValue }
    }

    /// A media-preserving, send-oriented view of the document (unlike `document`, which drops media).
    /// Resolve each `.media`/`.mediaGroup` `mediaID` against your media cache to serialize the whole
    /// document — e.g. into an InstantPage rich message.
    public func outgoingBlocks() -> [RichTextOutgoingBlock] { canvas.outgoingBlocks() }

    public var document: Document {
        get { Document(blocks: canvas.currentBlocks()) }
        set {
            var blocks = newValue.blocks
            if blocks.isEmpty { blocks = [.paragraph(ParagraphBlock(id: BlockID.generate()))] }
            canvas.setBlocks(blocks, width: bounds.width)
            needsLayout = true
        }
    }

    /// Registers an image bitmap under `id` so the canvas's image provider can draw `.image` blocks that
    /// reference it — WITHOUT inserting a block. Call before `setOutgoingBlocks(_:)` when seeding
    /// media-bearing content for editing (e.g. reopening a rich draft).
    public func registerImageAsset(_ image: NSImage, id: String) {
        assets[id] = image
    }

    /// Media-preserving seed — the inverse of `outgoingBlocks()`. Replaces the document with `blocks`,
    /// keeping `.media`/`.mediaGroup` (unlike `document =`, which drops media). Resolve each `mediaID`
    /// beforehand via `registerImageAsset` (images) and the media-view provider (file/audio/map/video).
    public func setOutgoingBlocks(_ blocks: [RichTextOutgoingBlock]) {
        let seeded = blocks.isEmpty ? [.paragraph(ParagraphBlock(id: BlockID.generate()))] : blocks
        canvas.setOutgoingBlocks(seeded, width: bounds.width)
        needsLayout = true
    }

    /// Serializes the document to Markdown (GFM): headings, body, blockquote, fenced code, bullet/ordered/
    /// checklist lists, pipe tables, and inline bold/italic/strike/code/links/formulas/spoilers. Media has no
    /// markdown form (the text/structure is captured; attachments are not).
    public func markdown() -> String { RichTextMarkdown.markdown(from: canvas.currentBlocks()) }

    public override func layout() {
        super.layout()
        let width = bounds.width
        canvas.setParagraphsWidthIfNeeded(width)
        // In scroll mode the document takes its intrinsic height; a direct canvas fills a short host but
        // may grow beyond it until the enclosing dynamic row consumes `onContentHeightChange`.
        let minimumHeight = isScrollEnabled ? 44 : bounds.height
        let height = max(canvas.intrinsicContentSize.height, minimumHeight)
        if isScrollEnabled {
            scrollView.frame = bounds
        }
        canvas.frame = NSRect(x: 0, y: 0, width: width, height: height)
        canvas.layoutSubtreeIfNeeded()
    }

    /// Moves the canvas between its internal scroller and a direct host. The latter is mandatory for
    /// table-backed hosts: hiding a nested NSScrollView is insufficient because AppKit still discovers it
    /// while resolving accessibility parents during a focus change.
    private func updateCanvasHost() {
        scrollView.forwardsScroll = !isScrollEnabled
        scrollView.hasVerticalScroller = isScrollEnabled && showsScroller
        scrollView.verticalScrollElasticity = isScrollEnabled ? .automatic : .none

        if isScrollEnabled {
            if canvas.superview !== scrollView.contentView {
                canvas.removeFromSuperview()
                scrollView.documentView = canvas
            }
            if scrollView.superview !== self {
                addSubview(scrollView)
            }
        } else {
            if scrollView.documentView === canvas {
                scrollView.documentView = nil
            }
            canvas.removeFromSuperview()
            if canvas.superview !== self {
                addSubview(canvas)
            }
            scrollView.removeFromSuperview()
        }
        needsLayout = true
    }

    public func toggleBold() { canvas.toggleBold() }
    public func toggleItalic() { canvas.toggleItalic() }
    public func toggleStrikethrough() { canvas.toggleStrikethrough() }
    public func toggleUnderline() { canvas.toggleUnderline() }
    public func toggleInlineCode() { canvas.toggleInlineCode() }
    /// Toggles a Telegram spoiler over the current selection. The run's text is hidden behind a "dust"
    /// overlay (a private-API-free fill by default; inject a richer effect via `spoilerEffectProvider`)
    /// and revealed when the caret/selection lands in it.
    public func toggleSpoiler() { canvas.toggleSpoiler() }
    /// Host hook for the spoiler "dust" overlay: maps a requested size to a `SpoilerEffect`. nil (the
    /// default) uses the package's private-API-free translucent-fill cross-fade.
    public var spoilerEffectProvider: ((CGSize) -> SpoilerEffect)? {
        get { canvas.spoilerEffectProvider }
        set { canvas.spoilerEffectProvider = newValue }
    }
    public func setParagraphStyle(_ name: ParagraphStyleName) { canvas.setParagraphStyle(name) }
    /// Toggles the selection into a single code block, or a single selected code block back to body paragraphs.
    public func makeCodeBlock() { canvas.makeCodeBlock() }
    /// True when the caret's top-level block is a code block — lets a host show the toggle's checked state.
    public var isCaretInCodeBlock: Bool { canvas.isCaretInCodeBlock() }
    /// The caret's code-block language (nil when not in a code block / no language set).
    public var caretCodeBlockLanguage: String? { canvas.caretCodeBlockLanguage() }
    /// Sets (or clears, on empty/nil) the caret's code-block language — a programmatic write into the
    /// block's always-visible, editable language line.
    public func setCodeBlockLanguage(_ language: String?) { canvas.setCodeBlockLanguage(language) }
    /// LEGACY: the code block's header band (copy zone + language-editor click) was replaced by the
    /// editable language line, so this never fires anymore. Kept so existing host wiring compiles.
    public var onCodeCopied: (() -> Void)? {
        get { canvas.onCodeCopied }
        set { canvas.onCodeCopied = newValue }
    }
    /// LEGACY: see `onCodeCopied` — the language is authored in the block's own language line now, so
    /// this never fires anymore. Kept so existing host wiring compiles.
    public var onCodeHeaderClicked: (() -> Void)? {
        get { canvas.onCodeHeaderClicked }
        set { canvas.onCodeHeaderClicked = newValue }
    }
    /// Register the host's syntax highlighter. The editor detects which code blocks need highlighting,
    /// debounces (~300ms from edits, never from selection), caches answers per (language, text) and
    /// applies them; the host only turns (language, text) into colours and calls `completion` on the main
    /// queue whenever it is ready. Answering late is expected; never answering leaves the block plain.
    /// The editor cannot do this itself — it cannot see the app's libprisma wrapper (`CodeSyntax`).
    public func registerSyntaxHighlighter(
        _ provider: ((_ language: String, _ text: String,
                      _ completion: @escaping ([RichTextSyntaxToken]) -> Void) -> Void)?
    ) {
        canvas.syntaxHighlighter = provider
        canvas.scheduleSyntaxHighlightPass()
    }
    /// Wraps the touched blocks into one recursive block quote (re-applying inside a quote nests deeper).
    public func wrapInBlockQuote() { canvas.wrapInBlockQuote() }
    /// Removes exactly one block-quote level around the caret (children spliced back into the parent).
    public func unwrapBlockQuoteLevel() { canvas.unwrapBlockQuoteLevel() }
    /// Number of block quotes enclosing the caret (0 = not in a quote).
    public var blockQuoteDepth: Int { canvas.blockQuoteDepth(at: canvas.head) }
    /// Toggles the selection into a pull quote, or a selected pull quote back to body paragraphs.
    public func makePullQuote() { canvas.makePullQuote() }
    public func setAlignment(_ alignment: TextAlignment) { canvas.setAlignment(alignment) }
    public func setList(_ marker: ListMarker?) { canvas.setList(marker) }
    /// Toggles the checked state of the caret's `.checklist` item (a checkbox is also toggled by clicking it).
    public func toggleChecklistItem() { canvas.toggleChecklistAtCaret() }

    public func undo() { canvas.effectiveUndoManager?.undo() }
    public func redo() { canvas.effectiveUndoManager?.redo() }
    public func removeAllUndoActions() { canvas.effectiveUndoManager?.removeAllActions() }

    /// True when a non-collapsed text selection exists.
    public var hasSelection: Bool { canvas.selFrom != canvas.selTo }
    /// The current selection as a Core `[Block]` fragment (paragraph runs sliced to the selection, whole
    /// tables when touched, code blocks sliced). Empty when nothing is selected.
    public func selectedBlocks() -> [Block] { canvas.selectedFragment() }
    /// Replaces the current selection (or splices at the caret) with a Core `[Block]` fragment — the
    /// write-back half of `selectedBlocks()` for host transforms (e.g. AI compose on a selection).
    public func replaceSelection(with blocks: [Block]) { canvas.insertFragment(blocks) }

    // MARK: Table structural commands (operate on the caret's table; no-op otherwise)
    public func insertTableRowAbove() { canvas.insertTableRowAbove() }
    public func insertTableRowBelow() { canvas.insertTableRowBelow() }
    public func deleteTableRow() { canvas.deleteTableRow() }
    public func insertTableColumnLeft() { canvas.insertTableColumnLeft() }
    public func insertTableColumnRight() { canvas.insertTableColumnRight() }
    public func deleteTableColumn() { canvas.deleteTableColumn() }
    public func setTableColumnAlignment(_ alignment: TextAlignment) { canvas.setTableColumnAlignment(alignment) }
    public func setTableColumnVerticalAlignment(_ alignment: VerticalAlignment) { canvas.setTableColumnVerticalAlignment(alignment) }
    /// Highlights the caret's cell (or every cell of a structural row/column selection, or the bounding
    /// cells of a multi-cell text selection) with `color`; `removeTableCellHighlight()` clears it.
    public func setTableCellHighlight(_ color: NSColor) { canvas.setTableCellBackground(color.rgba) }
    public func removeTableCellHighlight() { canvas.setTableCellBackground(nil) }
    /// Shows / hides the caret table's grid. Not merely a paint toggle: an unbordered table lays out
    /// with zero-width borders (cells butt together), matching how the sent message renders it. One
    /// undo step; no-op outside a table.
    public func toggleTableBordered() { canvas.toggleTableBordered() }
    /// Flips the caret's table between compact (halved cell padding) and normal, as one undo step.
    public func toggleTableCompact() { canvas.toggleTableCompact() }
    /// The caret table's `bordered` flag (true outside a table) — switches the menu item's title.
    public var isCaretTableBordered: Bool { canvas.activeTable()?.box.bordered ?? true }
    /// The caret table's `compact` flag (false outside a table) — switches the menu item's title.
    public var isCaretTableCompact: Bool { canvas.activeTable()?.box.compact ?? false }
    /// True when the caret is inside a table cell (the predicate the table commands guard on) — lets a
    /// host present a context-aware table menu: only "Insert Table" outside, the editing actions inside.
    public var isCaretInTable: Bool { canvas.activeTable() != nil }

    /// Host toggle for the table structural controls (row/column handles + resize knobs). The inline
    /// chat composer hides them (table structure is edited in the modal editor); defaults to shown.
    public var showsTableControls: Bool {
        get { canvas.showsTableControls }
        set { canvas.showsTableControls = newValue }
    }

    /// Host hook consulted on paste, after the editor's own rich fragment but before the plain-string
    /// fallback: convert app-private pasteboard formats (e.g. the chat input's entity payload with custom
    /// emoji/formatting) into a `[Block]` fragment. Return nil/empty to decline.
    public var pasteFragmentProvider: (() -> [Block]?)? {
        get { canvas.hostPasteFragmentProvider }
        set { canvas.hostPasteFragmentProvider = newValue }
    }

    public var withPasteContext: ((() -> Void) -> Void)? {
        get { canvas.withPasteContext }
        set { canvas.withPasteContext = newValue }
    }

    /// True when `windowPoint` (window coordinates) sits over a table that pans horizontally — a host's
    /// global horizontal-swipe handlers (e.g. navigation-back) should yield so the pan reaches the table.
    public func consumesHorizontalPan(atWindowPoint windowPoint: NSPoint) -> Bool {
        guard window != nil else { return false }
        let point = canvas.convert(windowPoint, from: nil)
        return canvas.horizontallyScrollableTable(at: point) != nil
    }

    /// Inserts an empty `rows`×`cols` table (row 0 a header) at the caret. No-op unless the caret is in
    /// a top-level paragraph.
    public func insertTable(rows: Int, cols: Int) { canvas.insertTable(rows: rows, columns: cols) }

    // MARK: Buttons

    /// Inserts a button row (one default pill) at the caret. Top-level only: a row inside a table or a
    /// block quote is preservation-only. The fresh pill is blank — pair with `onEditButtonRequested`
    /// so a click on it opens the property editor.
    public func insertButtonRow() { canvas.insertButtonRow() }
    /// SHEET-FIRST insert: drops a row carrying an already-configured pill (the host collected its
    /// properties in the editor sheet before inserting, so no blank placeholder enters the document).
    public func insertButtonRow(with button: ButtonRef) { canvas.insertButtonRow(with: button) }
    /// True when `insertButtonRow()` would act at the current caret — the command's exact guard, for a
    /// menu item's enablement (rows are creatable only in a top-level paragraph).
    public var canInsertButtonRow: Bool { canvas.canInsertButtonRow }
    /// Converts the current selection into ONE inline button pill labelled with the selected text (the
    /// Link flow's analogue). No-op without a selection inside one text run (code blocks refuse it).
    public func makeSelectionInlineButton() { canvas.makeSelectionInlineButton() }
    /// SHEET-FIRST inline variant: replaces the current selection with a pill carrying an
    /// already-configured button.
    public func makeSelectionInlineButton(with button: ButtonRef) { canvas.makeSelectionInlineButton(with: button) }
    /// True when `makeSelectionInlineButton()` would act on the current selection — for enablement.
    public var canMakeSelectionInlineButton: Bool { canvas.canMakeSelectionInlineButton }
    /// SHEET-FIRST inline insert at a collapsed caret (converts the selection when one exists): the
    /// pill lands at the caret like an emoji atom.
    public func insertInlineButton(with button: ButtonRef) { canvas.insertInlineButton(with: button) }
    /// True when `insertInlineButton(with:)` would act — selection or bare caret in a text run.
    public var canInsertInlineButton: Bool { canvas.canInsertInlineButton }
    /// Asked to present the button property editor (label / URL / style / delete) for a clicked pill.
    /// `isBlockPill` says which kind was clicked (`true` = a row pill, `false` = an inline
    /// `textButton`); the completion applies the edited button, or removes the pill on nil. Wiring
    /// this also enables the authoring chrome (the row's "…" menu affordance); a host that leaves it
    /// nil keeps pills preservation-only — a click just places the caret.
    public var onEditButtonRequested: ((_ button: ButtonRef, _ isBlockPill: Bool, _ completion: @escaping (ButtonRef?) -> Void) -> Void)? {
        get { canvas.buttonEditRequested }
        set { canvas.buttonEditRequested = newValue }
    }

    /// Sets `url` as a link over the current selection (no-op if the selection is empty).
    public func setLink(_ url: String) { canvas.setLink(url) }
    /// Removes any link over the current selection.
    public func removeLink() { canvas.removeLink() }
    /// The link the entire selection carries (for prefilling a link editor), or nil.
    public func currentLink() -> String? { canvas.currentLink() }
    /// The plain text of the current selection (to prefill a link editor's text field).
    public func selectedText() -> String { canvas.selectedText() }
    /// Applies a link from a two-field URL editor (link text + url). When `text` matches the current
    /// selection the link is toggled in place; otherwise the selection is replaced with `text` (or
    /// `text` is inserted at a collapsed caret) and the link applied to it. `url == nil` removes the
    /// link while keeping the text.
    public func applyLink(text: String, url: String?) { canvas.applyLink(text: text, url: url) }
    /// True when a table row/column is structurally selected (via its handle) rather than a text range.
    /// Such a selection is cleared when the editor yields first responder to a modal, so a modal-mediated
    /// link prompt can't act on it — callers should skip the prompt in that state.
    public var hasStructuralTableSelection: Bool { canvas.tableSelection != nil }

    /// Increases the list nesting level of the touched list items (no-op on non-list paragraphs).
    public func indent() { canvas.indent() }
    /// Decreases the list nesting level of the touched list items (clamps at 0; no-op on non-list).
    public func outdent() { canvas.outdent() }

    public func insertImage(_ image: NSImage, naturalSize: CGSize) {
        insertImage(image, naturalSize: naturalSize, assetID: BlockID.generate().rawValue)
    }
    /// Inserts an image under a host-chosen `assetID`. Use this when the host also caches a `Media` under
    /// the SAME id (so "Make Collage" can resolve the image into a collage tile) — the editor draws the
    /// `NSImage` via the image provider while the host can resolve the id for a collage.
    public func insertImage(_ image: NSImage, naturalSize: CGSize, assetID: String) {
        assets[assetID] = image
        canvas.insertImage(image, naturalSize: naturalSize, assetID: assetID)
    }

    /// Inserts plain text at the caret (replacing any selection) — e.g. a unicode emoji from a picker.
    public func insertText(_ text: String) { canvas.commitText(text) }
    /// Inserts one inline custom emoji (a single `U+FFFC` atom) at the caret, replacing any selection.
    public func insertEmoji(id: String, altText: String? = nil) { canvas.insertEmoji(id: id, altText: altText) }
    /// Inserts a LaTeX formula atom at the caret, or replaces the formula the caret is on/adjacent to (a
    /// blank latex removes it). Formulas are created only through this (no inline `$…$` auto-parsing).
    public func insertFormula(latex: String) { canvas.insertFormula(latex: latex) }
    /// The LaTeX of the formula the caret is on/adjacent to, for pre-filling a host editor (like `currentLink()`).
    public func currentFormula() -> String? { canvas.currentFormula() }
    /// Registers the host's emoji-view factory (`id`, requested square size → a view, or nil). The
    /// editor pools, positions, and culls returned views; the attachment itself draws nothing.
    public func registerEmojiViewProvider(_ provider: @escaping (_ id: String, _ size: CGSize) -> NSView?) { canvas.emojiViewProvider = provider }
    /// Viewport inset (points) within which off-screen emoji views stay live (not hidden) during culling.
    public var emojiCullMargin: CGFloat { get { canvas.emojiCullMargin } set { canvas.emojiCullMargin = newValue } }

    /// Inserts a macOS-only embedded-media block (file / audio / map) at the caret, replacing any
    /// selection. `kind` is `"file"`, `"audio"`, or `"map"`; `mediaID` is an opaque key the host's
    /// media-view provider maps back to a real media view. No-op on an unknown `kind`.
    public func insertMediaBlock(kind: String, mediaID: String) {
        guard let k = MediaKind(rawValue: kind) else { return }
        canvas.insertMediaBlock(kind: k, mediaID: mediaID)
    }
    /// Registers the host's media-block view factory (`kind`, `mediaID`, content width → an interactive
    /// view, or nil). The editor pools, positions, and culls returned views and reads their height back;
    /// the block itself draws nothing. Mirrors `registerEmojiViewProvider` but for block-level media.
    public func registerMediaBlockViewProvider(_ provider: @escaping (_ kind: String, _ mediaID: String, _ spoiler: Bool, _ width: CGFloat) -> NSView?) {
        canvas.mediaBlockViewProvider = provider
    }
    /// Registers a teardown for a hosted media view, called just before it's removed (block deleted /
    /// document replaced / editor torn down) so the host can release the view's resources.
    public func registerMediaBlockViewTeardown(_ teardown: @escaping (NSView) -> Void) {
        canvas.mediaBlockViewWillRemove = teardown
    }
    /// Viewport inset (points) within which off-screen media views stay live (not hidden) during culling.
    public var mediaBlockCullMargin: CGFloat { get { canvas.mediaBlockCullMargin } set { canvas.mediaBlockCullMargin = newValue } }

    /// Inserts a media GROUP (collage of ≤10 photos/videos) at the caret, replacing any selection. `kind`
    /// is `"collage"` (or `"slideshow"`, reserved); `mediaIDs` are opaque keys the host's tile provider
    /// resolves. The editor lays the tiles out via the registered mosaic. No-op on an unknown `kind`.
    public func insertMediaGroup(kind: String, mediaIDs: [String]) {
        guard let k = MediaGroupKind(rawValue: kind) else { return }
        canvas.insertMediaGroup(kind: k, mediaIDs: mediaIDs)
    }
    /// Registers the collage mosaic: `mediaIDs` + full-bleed width → per-tile frames (origin relative to
    /// the media area's top-left). Wrap the chat's `GroupedLayout` here.
    public func registerMediaGroupMosaic(_ mosaic: @escaping (_ mediaIDs: [String], _ width: CGFloat) -> [CGRect]) {
        canvas.mediaGroupMosaic = mosaic
    }
    /// Registers the collage tile factory: `mediaID` + tile size → a view rendered to FILL that size
    /// (cropping). The editor positions/pools/culls tiles and runs the media teardown on removal.
    public func registerMediaGroupTileProvider(_ provider: @escaping (_ mediaID: String, _ spoiler: Bool, _ size: CGSize) -> NSView?) {
        canvas.mediaGroupTileProvider = provider
    }
    /// Registers the slider (slideshow) factory: a group's `mediaIDs` + full-bleed width → a paging view
    /// SIZED (frame height) to its content; the editor hosts it full-bleed and learns the height back.
    public func registerMediaGroupSliderProvider(_ provider: @escaping (_ mediaIDs: [String], _ width: CGFloat) -> NSView?) {
        canvas.mediaGroupSliderProvider = provider
    }
    /// Provide the on-media overlay controls (pills) for collage/slider/single image·video blocks.
    public func registerMediaControlsProvider(_ provider: @escaping (MediaControlsContext) -> NSView?) {
        canvas.mediaControlsProvider = provider
    }
    /// Appends media to an existing group (collage/slider), capped at 10.
    public func addMediaToGroup(groupID: String, mediaIDs: [String]) {
        canvas.addMediaToGroup(groupID: BlockID(groupID), mediaIDs: mediaIDs)
    }
    public func replaceGroupMedia(groupID: String, index: Int, newMediaID: String) {
        canvas.replaceGroupMedia(groupID: groupID, index: index, newMediaID: newMediaID)
    }
    public func replaceMedia(blockID: String, newMediaID: String) {
        canvas.replaceMedia(blockID: blockID, newMediaID: newMediaID)
    }
    /// Toggles a group between `"collage"` and `"slideshow"`.
    public func setMediaGroupKind(groupID: String, kind: String) {
        guard let k = MediaGroupKind(rawValue: kind) else { return }
        canvas.setMediaGroupKind(groupID: BlockID(groupID), kind: k)
    }
    /// Converts a single image/video block into a group (`"collage"`/`"slideshow"`) of its media + the added.
    public func convertMediaToGroup(blockID: String, kind: String = "collage", addingMediaIDs: [String]) {
        guard let k = MediaGroupKind(rawValue: kind) else { return }
        canvas.convertMediaToGroup(blockID: BlockID(blockID), kind: k, addingMediaIDs: addingMediaIDs)
    }
    /// Removes a media block (image / file·audio·map·video / collage·slider) by id.
    public func removeMediaBlock(blockID: String) { canvas.removeMediaBlock(id: BlockID(blockID)) }

    /// Removes one tile from a collage group by index. Removing the last tile drops the whole group.
    public func removeCollageTile(groupID: String, index: Int) {
        canvas.removeCollageTile(group: BlockID(groupID), index: index)
    }
    /// Returns the media id for a block, or nil if not found.
    /// For a collage/slider group pass `tileIndex`; for a single image or video block pass nil.
    public func mediaID(forBlock blockID: String, tileIndex: Int?) -> String? {
        canvas.mediaID(forBlock: BlockID(blockID), tileIndex: tileIndex)
    }

    /// Whether the media (single block → `tileIndex == nil`, or a group tile) is a Telegram-style spoiler.
    public func isMediaSpoiler(blockID: String, tileIndex: Int?) -> Bool {
        canvas.isMediaSpoiler(blockID: BlockID(blockID), tileIndex: tileIndex)
    }
    /// Sets the Telegram-style spoiler on the media (single block → `tileIndex == nil`, or a group tile).
    public func setMediaSpoiler(blockID: String, tileIndex: Int?, spoiler: Bool) {
        canvas.setMediaSpoiler(blockID: BlockID(blockID), tileIndex: tileIndex, spoiler: spoiler)
    }

    /// Demo helper: place a gap cursor just before the first image block.
    public func placeGapCursorBeforeFirstImage() {
        canvas.placeGapCursorBeforeFirstImage()
    }

    /// Demo helper: select from mid-way through the 2nd block to mid-way through the 3rd.
    public func selectRangeAcrossFirstTwoBodyParagraphs() {
        canvas.selectAcrossBlocks(firstIndex: 1, secondIndex: 2)
    }

    /// Demo helper: set a cross-cell selection spanning from mid-way through leaf region at
    /// `firstLeaf` to mid-way through the region at `secondLeaf` (document order). Use this to
    /// demonstrate Phase 4 continuous cross-cell selection.
    public func selectAcrossLeafRegions(firstLeaf: Int, secondLeaf: Int) {
        canvas.selectAcrossLeafRegions(firstLeaf: firstLeaf, secondLeaf: secondLeaf)
    }

    /// Demo helper: select the first table's first column (showcases the table handles + selection outline).
    public func selectFirstTableColumn() { canvas.selectFirstTableColumn() }

    public func selectAll() {
        canvas.selectedGlobalRange = (0, canvas.documentSizeValue)
    }
    public func cut() { canvas.cut(nil) }
    /// Named `copySelection` (not `copy`) to avoid clashing with `NSObject.copy()`.
    public func copySelection() { canvas.copy(nil) }
    public func paste() { canvas.paste(nil) }

    /// Installs a host context-menu handler. On right-click the editor calls it with the click `location`
    /// (canvas coords), the media under the click (if any), and whether there's a selection; if the handler
    /// returns `true` (the host showed its own menu, e.g. a TGUIKit `ContextMenu`), the editor suppresses
    /// its native `NSMenu`. Return `false` to fall back to the built-in menu.
    public func registerContextMenuHandler(_ handler: @escaping (_ location: NSPoint, _ media: EditorMediaContext?, _ hasSelection: Bool, _ event: NSEvent) -> Bool) {
        canvas.contextMenuRequested = handler
    }

    @discardableResult
    public override func becomeFirstResponder() -> Bool {
        window?.makeFirstResponder(canvas) ?? false
    }

    /// Focuses the editor for typing: makes the internal `canvas` (the `NSTextInputClient` that handles
    /// `keyDown`) the window's first responder. Hosts should call THIS rather than
    /// `window.makeFirstResponder(self)` — the façade is not itself a key-input target, and routing
    /// through it re-entrantly (its `becomeFirstResponder` re-calls `makeFirstResponder(canvas)`) can
    /// leave the façade as first responder, so no typed key reaches the editor.
    public func makeEditorFirstResponder() {
        _ = window?.makeFirstResponder(canvas)
    }

    /// Scrolls the editor's enclosing scroller so the caret is visible. When the editor doesn't scroll
    /// internally it sits inside the host's scroll view, so scrolling `self`'s caret rect into view drives
    /// the host. Deferred to the next runloop so a content-height change (new line/paragraph) has re-laid
    /// out the host row first. A no-op when the caret is already visible.
    public func scrollCaretToVisible() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.window != nil else { return }
            let rect = self.canvas.convert(self.canvas.currentCaretRect(), to: self)
            guard rect.height > 0 else { return }
            self.scrollToVisible(rect.insetBy(dx: 0, dy: -10))
        }
    }

    /// Places the caret at the end of the document (used when opening to edit an existing message).
    public func moveCaretToEnd() { canvas.moveCaretToEnd() }

    /// The current selection as a global `(anchor, head)` range — capture it before a toolbar action that
    /// may move focus, and restore it after `makeEditorFirstResponder()`, so a format toggle still acts on
    /// the user's selection (and not a caret it collapsed to).
    public var selectedRange: (Int, Int) {
        get { canvas.selectedGlobalRange }
        set { canvas.selectedGlobalRange = newValue }
    }

    /// The active character formats at the caret/selection — drive a toolbar's active-state highlight.
    public func currentFormatState() -> CharacterFormatState { canvas.currentCharacterFormatState() }
    /// The active paragraph style / list / alignment across the selection (for a toolbar's selected-item
    /// marks). Each field is the uniform value, or nil / `.mixed` when the touched paragraphs disagree.
    public func currentParagraphFormatState() -> ParagraphFormatState { canvas.currentParagraphFormatState() }

    /// Fired when the selection, caret, or active formatting may have changed. Refresh toolbar state here.
    public var onFormatStateChange: (() -> Void)? {
        get { canvas.onSelectionOrFormatChange }
        set { canvas.onSelectionOrFormatChange = newValue }
    }
}

/// An NSScrollView that, when `forwardsScroll` is set, passes wheel events to the next responder instead
/// of scrolling itself — lets an enclosing scroller (e.g. an InputData table) handle scrolling so a
/// scrolling NSScrollView is never nested live in an NSTableView row.
@available(macOS 12, *)
final class HostScrollForwardingScrollView: NSScrollView {
    var forwardsScroll = false
    override func scrollWheel(with event: NSEvent) {
        if forwardsScroll {
            nextResponder?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}
#endif
