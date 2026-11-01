import Cocoa
import TelegramCore
import Postbox
import TGUIKit
import TelegramMedia
import InputTextView
import InstantPageUI
import MessageUtils
import Strings
import TelegramContext
import TelegramMediaUtils
import TelegramUtils
import TelegramTheme
import InlineStickerLayer
import InputView

private final class InstantPageV2DetailsChevronLayer: CALayer {
    static let size = CGSize(width: 18.0, height: 18.0)

    private static let animationKeyPath = "flipScale"

    @NSManaged private var flipScale: CGFloat

    var color: NSColor {
        didSet {
            if oldValue != self.color {
                self.setNeedsDisplay()
            }
        }
    }

    override class func needsDisplay(forKey key: String) -> Bool {
        if key == InstantPageV2DetailsChevronLayer.animationKeyPath {
            return true
        }
        return super.needsDisplay(forKey: key)
    }

    init(color: NSColor, expanded: Bool) {
        self.color = color
        super.init()

        let size = InstantPageV2DetailsChevronLayer.size
        self.bounds = CGRect(origin: .zero, size: size)
        self.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        self.isGeometryFlipped = true
        self.contentsScale = System.backingScale
        self.disableActions()
        self.setModelScale(expanded ? -1.0 : 1.0)
        self.setNeedsDisplay()
    }

    override init(layer: Any) {
        self.color = (layer as? InstantPageV2DetailsChevronLayer)?.color ?? .clear
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(in ctx: CGContext) {
        super.draw(in: ctx)
        let center = CGPoint(x: self.bounds.midX, y: self.bounds.midY)
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.scaleBy(x: self.flipScale, y: self.flipScale)
        ctx.translateBy(x: -center.x, y: -center.y)
        ctx.setStrokeColor(self.color.cgColor)
        ctx.setLineWidth(2.0)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.move(to: CGPoint(x: center.x - 5.0, y: center.y + 2.5))
        ctx.addLine(to: CGPoint(x: center.x, y: center.y - 2.5))
        ctx.addLine(to: CGPoint(x: center.x + 5.0, y: center.y + 2.5))
        ctx.strokePath()
        ctx.restoreGState()
    }

    func setExpanded(_ expanded: Bool, animated: Bool, duration: Double) {
        let target: CGFloat = expanded ? -1.0 : 1.0
        if animated {
            let source = self.presentation()?.flipScale
                ?? self.flipScale
            self.setModelScale(target)
            self.animate(
                from: NSNumber(value: Double(source)),
                to: NSNumber(value: Double(target)),
                keyPath: InstantPageV2DetailsChevronLayer.animationKeyPath,
                timingFunction: .spring,
                duration: duration
            )
        } else {
            self.removeAnimation(forKey: InstantPageV2DetailsChevronLayer.animationKeyPath)
            self.setModelScale(target)
            self.setNeedsDisplay()
        }
    }

    private func setModelScale(_ scale: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.flipScale = scale
        CATransaction.commit()
    }
}

private final class InstantPageV2DetailsHeaderView: View {
    private static let animationDuration: Double = 0.4

    private let chevronLayer: InstantPageV2DetailsChevronLayer
    private(set) var isExpanded: Bool

    init(item: InstantPageV2DetailsItem, color: NSColor) {
        self.chevronLayer = InstantPageV2DetailsChevronLayer(color: color, expanded: item.isExpanded)
        self.isExpanded = item.isExpanded
        super.init(frame: item.titleFrame)
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.clear.cgColor
        self.layer?.addSublayer(self.chevronLayer)
        self.update(item: item, color: color)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    func update(item: InstantPageV2DetailsItem, color: NSColor) {
        self.chevronLayer.color = color
        let halfWidth = InstantPageV2DetailsChevronLayer.size.width * 0.5
        let centerX = item.rtl
            ? (item.titleFrame.width - item.sideInset - halfWidth)
            : (item.sideInset + halfWidth)
        let centerY = floorToScreenPixels(
            System.backingScale,
            item.titleFrame.midY
        )
        self.chevronLayer.position = CGPoint(x: centerX, y: centerY)
        self.setExpanded(item.isExpanded, animated: false)
    }

    func setExpanded(_ expanded: Bool, animated: Bool) {
        guard self.isExpanded != expanded else { return }
        self.isExpanded = expanded
        self.chevronLayer.setExpanded(
            expanded,
            animated: animated,
            duration: InstantPageV2DetailsHeaderView.animationDuration
        )
    }
}

private final class InstantPageV2RevealSnippetLayer: CALayer {
    let characterIndex: Int
    private var textItem: InstantPageTextItem?
    private var sourceRect: CGRect = .zero

    init(characterIndex: Int, textItem: InstantPageTextItem, sourceRect: CGRect, contentsScale: CGFloat) {
        self.characterIndex = characterIndex
        self.textItem = textItem
        self.sourceRect = sourceRect
        super.init()
        self.contentsScale = contentsScale
        self.bounds = CGRect(origin: .zero, size: sourceRect.size)
        self.setNeedsDisplay()
    }

    override init(layer: Any) {
        if let layer = layer as? InstantPageV2RevealSnippetLayer {
            self.characterIndex = layer.characterIndex
            self.textItem = layer.textItem
            self.sourceRect = layer.sourceRect
        } else {
            self.characterIndex = 0
        }
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func action(forKey event: String) -> CAAction? {
        return NSNull()
    }

    override func draw(in ctx: CGContext) {
        guard let textItem = self.textItem else { return }
        ctx.saveGState()
        ctx.translateBy(
            x: -textItem.frame.minX - self.sourceRect.minX,
            y: -textItem.frame.minY - self.sourceRect.minY
        )
        textItem.drawInTile(context: ctx)
        ctx.restoreGState()
    }

    func updateFrame(contentOrigin: CGPoint) {
        self.frame = CGRect(
            x: contentOrigin.x + self.sourceRect.minX,
            y: contentOrigin.y + self.sourceRect.minY,
            width: self.sourceRect.width,
            height: self.sourceRect.height
        )
    }
}

public final class InstantPageV2View: View, NSViewToolTipOwner, HorizontalScrollConsuming {

    private enum InteractiveTarget {
        case button(InstantPageInlineButtonAttachment)
        case link(InstantPageUrlItem)
    }

    public func consumesHorizontalScroll(atWindowPoint windowPoint: NSPoint) -> Bool {
        let local = self.convert(windowPoint, from: nil)
        guard let i = self.tableIndex(at: local), i < self.tableScrollOffsets.count else { return false }
        return self.tableMaxOffset(i) > 0
    }


    public func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        // A button pill first: hovering it reveals the URL it would open (external links especially) —
        // a pill's label hides its destination the way a text link's label does.
        if case let .button(attachment)? = self.interactiveTarget(at: point),
           let url = InstantPageV2View.buttonTooltipURL(attachment.button.action) {
            return url.removingPercentEncoding?.prefixWithDots(70) ?? url
        }
        if let link = self.linkItem(at: point) {
            if link.tonAddress != nil {
                return ""
            }
            // Peer mentions carry an internal `tg://user?id=` URL; show the visible name instead.
            if link.url.hasPrefix("tg://user?id="), let text = self.linkDisplayText(at: point) {
                return text
            }
            return link.url.removingPercentEncoding?.prefixWithDots(70) ?? link.url
        }
        return ""
    }

    /// The destination a button tooltip should disclose: `.url` / `.urlAuth` open a link and
    /// `.openWebView` loads one — other actions (callback, copy, disabled…) have no URL to preview.
    private static func buttonTooltipURL(_ action: ReplyMarkupButtonAction) -> String? {
        switch action {
        case let .url(url): return url
        case let .urlAuth(url, _): return url
        case let .openWebView(url, _): return url
        default: return nil
        }
    }

    private var currentLayout: InstantPageV2Layout?
    private var currentTheme: InstantPageTheme?
    private var quoteHighlightLayer: SimpleLayer?

    private var detailsBodies: [Int: InstantPageV2View] = [:]
    private var mediaViews: [Int: ChatMediaContentView] = [:]
    private var slideshowViews: [Int: InstantPageV2SlideshowView] = [:]

    // Thinking views use their own occurrence namespace so answer-block churn does not recreate the
    // shared text-and-emoji shimmer host during streaming updates.
    private var thinkingViews: [Int: InstantPageV2ThinkingView] = [:]
    private var thinkingViewsByItemIndex: [Int: InstantPageV2ThinkingView] = [:]

    /// Supplies the chat-message context a `ChatMediaContentView` needs to render and to open
    /// media (gallery / music player / map). Given an instant-page `Media`, returns a parent
    /// `Message` carrying that media and the layout parameters (with `showMedia` wired to the
    /// chat gallery). `isFile` distinguishes a document block from a video/audio block that uses the
    /// same V2 layout carrier. Set by `ChatRichTextRowView`; when nil, media falls back to placeholders.
    public var mediaContentConfig: ((Media, CGSize, Int, Bool) -> (parent: Message, parameters: ChatMediaLayoutParameters)?)?
    private var detailsHeaders: [Int: InstantPageV2DetailsHeaderView] = [:]

    private var inkViews: [InvisibleInkDustView] = []
    private var spoilersRevealed: Bool = false
    /// Media indices whose spoiler dust the user has tapped to reveal (drives `forceSpoiler` per item).
    private var revealedMediaIndices: Set<Int> = []

    private var revealCostMap: InstantPageV2RevealCostMap?
    private var revealCursor: Int?
    private var itemReveals: [InstantPageV2ItemReveal]?

    private struct RevealTextKey: Hashable {
        let topLevelIndex: Int
        let tableCellIndex: Int?
        let subitemIndex: Int?
    }

    private struct RevealBlockKey: Hashable {
        let topLevelIndex: Int
        let tableCellIndex: Int?
        let subitemIndex: Int?
    }

    private final class RevealScalarState {
        var fromValue: CGFloat
        var targetValue: CGFloat
        var startTime: CFTimeInterval?

        init(value: CGFloat) {
            self.fromValue = value
            self.targetValue = value
        }
    }

    private struct RevealTextTarget {
        let textItem: InstantPageTextItem
        let contentOrigin: CGPoint
        let revealedCharacterCount: Int
    }

    private final class RevealTextState {
        var targetCharacterCount: Int
        var textItem: InstantPageTextItem
        var contentOrigin: CGPoint
        var activeSnippetLayers: [Int: InstantPageV2RevealSnippetLayer] = [:]

        init(targetCharacterCount: Int, textItem: InstantPageTextItem, contentOrigin: CGPoint) {
            self.targetCharacterCount = targetCharacterCount
            self.textItem = textItem
            self.contentOrigin = contentOrigin
        }
    }

    private var revealTextStates: [RevealTextKey: RevealTextState] = [:]
    private var revealOpacityStates: [RevealBlockKey: RevealScalarState] = [:]
    private var revealTableMaskStates: [RevealBlockKey: RevealScalarState] = [:]

    public var context: (any AccountContextProtocol)? {
        didSet {
            if context !== oldValue, let layout = self.currentLayout, let theme = self.currentTheme {
                self.reconcileSubviews(layout: layout, theme: theme)
            }
        }
    }
    private final class InlineEmojiLayerData {
        let layer: InlineStickerItemLayer
        var revealKey: RevealTextKey?
        var characterIndex: Int
        var revealWithThinkingHost: Bool
        var isRevealed: Bool = false
        /// Opacity once revealed. Below 1 only for a disabled button label, whose emoji has to fade
        /// with the lettering — the label tint reaches monochrome emoji only, so a full-colour one
        /// would otherwise stay at full strength inside a dimmed pill.
        var revealedAlpha: CGFloat = 1.0

        init(layer: InlineStickerItemLayer, revealKey: RevealTextKey?, characterIndex: Int, revealWithThinkingHost: Bool) {
            self.layer = layer
            self.revealKey = revealKey
            self.characterIndex = characterIndex
            self.revealWithThinkingHost = revealWithThinkingHost
        }
    }

    private var inlineStickerItemViews: [InlineStickerItemLayer.Key: InlineEmojiLayerData] = [:]
    private let emojiContainer: View = View()
    private var tableEmojiContainers: [Int: View] = [:]
    private var isLite: Bool = false

    private var tableScrollOffsets: [CGFloat] = []
    private var tableScrollerDrag: (index: Int, startMouseX: CGFloat, startOffset: CGFloat)?

    public var isDraggingTableScroller: Bool { return self.tableScrollerDrag != nil }

    public func isPointOverTableScroller(_ point: NSPoint) -> Bool {
        for i in 0..<self.tableScrollOffsets.count {
            if let rects = self.tableScrollerRects(i), rects.track.contains(point) {
                return true
            }
        }
        return false
    }

    private struct SelectedText {
        let range: NSRange
    }
    private var selectedRanges: [SelectedText] = []
    private var selectedFormulaIds: Set<ObjectIdentifier> = []
    private var hasLocalSelection: Bool = false
    public var canCopy: Bool = true

    /// Snapshot of the chat theme's text-selection color, captured once per layout pass so
    /// the formula-selection highlight matches the per-line `selectRect` color that
    /// `InstantPageTextItem.drawInTile` paints (it reads the global `theme.colors.selectText`).
    public var selectionColor: NSColor = NSColor.selectedTextBackgroundColor

    public var openMedia: ((InstantPageMedia) -> Void)?
    public var openUrl: ((InstantPageUrlItem, _ confirm: Bool) -> Void)?
    public var detailsTapped: ((_ index: Int) -> Void)?
    public var buttonTapped: ((InstantPageButton) -> Void)?
    /// Clicked the papercut card standing in for an `.unsupported` block. Same plumbing as a button
    /// pill: the card is a click target, not a link.
    public var unsupportedTapped: (() -> Void)?
    public var onSpoilerReveal: (() -> Void)?

    /// Whether a papercut card's "Update" pill is currently held down.
    fileprivate var pressedUnsupported: Bool = false

    fileprivate var pressedButtonAttachment: InstantPageInlineButtonAttachment? {
        didSet {
            if oldValue !== self.pressedButtonAttachment {
                oldValue?.isPressed = false
                self.pressedButtonAttachment?.isPressed = true
                self.needsDisplay = true
                self.setThinkingContentNeedsDisplay()
            }
        }
    }
    /// Tapped an in-message anchor (`#name`) whose target was located. The rect is the target's frame
    /// in this view's coordinates — the row scrolls the chat so it's visible.
    public var anchorReveal: ((CGRect) -> Void)?

    /// Horizontal bleed to the bubble's content edges (matches the media bleed). When > 0 (bubble
    /// mode) the anchor highlight spans the full bubble width with square corners.
    public var contentBleed: CGFloat = 0

    public weak var bubbleSelectionSource: ChatBubbleCustomTextSelection?
    public var bubbleSelectionStableId: AnyHashable?

    private var bubbleClipLayer: CAShapeLayer?
    private var appliedBubbleClip: (rect: CGRect, corners: ImageCorners)?

    public func setBubbleClip(_ rect: CGRect?, corners: ImageCorners = ImageCorners()) {
        guard let rect else {
            if self.bubbleClipLayer != nil {
                self.layer?.mask = nil
                self.bubbleClipLayer = nil
            }
            self.appliedBubbleClip = nil
            return
        }
        if let applied = self.appliedBubbleClip, applied.rect == rect, applied.corners == corners, self.bubbleClipLayer != nil {
            return
        }
        let clipLayer: CAShapeLayer
        if let existing = self.bubbleClipLayer {
            clipLayer = existing
        } else {
            clipLayer = CAShapeLayer()
            clipLayer.disableActions()
            self.bubbleClipLayer = clipLayer
            self.layer?.mask = clipLayer
        }
        clipLayer.frame = rect
        clipLayer.path = CGPath.bubbleCorners(size: rect.size, corners: corners)
        self.appliedBubbleClip = (rect, corners)
    }

    private var cursorTrackingArea: NSTrackingArea?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.layer?.masksToBounds = false
        self.emojiContainer.userInteractionEnabled = false
        self.emojiContainer.frame = self.bounds
        self.emojiContainer.layer?.masksToBounds = false
        self.emojiContainer.layerContentsRedrawPolicy = .never
        self.emojiContainer.isEventLess = true
        self.addSubview(self.emojiContainer)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.updateInlineEmojiObservers()
        self.updateInlineEmojiPlayback()
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        self.updateInlineEmojiObservers()
        self.updateInlineEmojiPlayback()
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        self.emojiContainer.frame = self.bounds
    }

    private weak var _observedWindow: NSWindow?
    private weak var _observedContentView: NSView?
    private weak var _observedDocumentView: NSView?
    private var _observersRegistered: Bool = false

    private func updateInlineEmojiObservers() {
        guard let w = self.window else { return }
        let cv = self.enclosingScrollView?.contentView
        let dv = self.enclosingScrollView?.documentView
        if _observersRegistered && _observedWindow === w && _observedContentView === cv && _observedDocumentView === dv {
            return
        }
        let center = NotificationCenter.default
        if _observersRegistered {
            center.removeObserver(self)
        }
        center.addObserver(self, selector: #selector(updateInlineEmojiPlayback), name: NSWindow.didBecomeKeyNotification, object: w)
        center.addObserver(self, selector: #selector(updateInlineEmojiPlayback), name: NSWindow.didResignKeyNotification, object: w)
        if let cv = cv {
            center.addObserver(self, selector: #selector(updateInlineEmojiPlayback), name: NSView.boundsDidChangeNotification, object: cv)
        }
        if let dv = dv {
            center.addObserver(self, selector: #selector(updateInlineEmojiPlayback), name: NSView.frameDidChangeNotification, object: dv)
        }
        center.addObserver(self, selector: #selector(updateInlineEmojiPlayback), name: NSView.frameDidChangeNotification, object: self)
        _observedWindow = w
        _observedContentView = cv
        _observedDocumentView = dv
        _observersRegistered = true
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = self.cursorTrackingArea {
            self.removeTrackingArea(existing)
            self.cursorTrackingArea = nil
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .inVisibleRect, .cursorUpdate]
        let area = NSTrackingArea(rect: self.bounds, options: options, owner: self, userInfo: nil)
        self.addTrackingArea(area)
        self.cursorTrackingArea = area
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateCursor(with: event)
    }

    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateCursor(with: event)
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSCursor.arrow.set()
    }

    public override func cursorUpdate(with event: NSEvent) {
        updateCursor(with: event)
    }

    public override func mouseDown(with event: NSEvent) {
        let local = self.convert(event.locationInWindow, from: nil)
        let interactiveTarget = self.interactiveTarget(at: local)
        if event.clickCount >= 1, case let .button(attachment)? = interactiveTarget {
            if attachment.isEnabled {
                self.pressedButtonAttachment = attachment
                self.displayIfNeeded()
            }
            return
        }
        if event.clickCount >= 1, self.unsupportedItem(at: local) != nil {
            self.pressedUnsupported = true
            return
        }
        for i in 0..<self.tableScrollOffsets.count {
            guard let rects = self.tableScrollerRects(i) else { continue }
            if rects.track.contains(local) {
                var startOffset = self.tableScrollOffsets[i]
                let onThumb = rects.thumb.contains(local)
                if !onThumb {
                    let trackWidth = rects.track.width - rects.thumb.width
                    let normalized = trackWidth > 0 ? max(0, min(1, (local.x - rects.track.minX - rects.thumb.width / 2) / trackWidth)) : 0
                    startOffset = normalized * self.tableMaxOffset(i)
                    _ = self.setTableScrollOffset(startOffset, at: i)
                }
                self.tableScrollerDrag = (i, local.x, startOffset)
                self.trackScrollerDrag(index: i, startMouseX: local.x, startOffset: startOffset)
                return
            }
        }
        if !self.spoilersRevealed, let layout = self.currentLayout {
            let rects = self.collectSpoilerRects(layout: layout, originInView: .zero)
            if rects.contains(where: { $0.contains(local) }) {
                self.revealSpoilers()
                return
            }
        }
        if self.canCopy, let layout = self.currentLayout {
            if event.clickCount == 2, self.selectWord(at: local, in: layout) {
                return
            }
            if event.clickCount == 3, self.selectParagraph(at: local, in: layout) {
                return
            }
        }
        if self.canCopy, event.clickCount == 1, let layout = self.currentLayout {
            for (index, item) in layout.items.enumerated() {
                if let reveals = self.itemReveals, index < reveals.count, self.isHiddenReveal(reveals[index]) {
                    continue
                }
                if case let .codeBlock(block) = item, block.headerHeight > 0 {
                    let headerRect = CGRect(x: block.frame.minX, y: block.frame.minY,
                                            width: block.frame.width, height: block.headerHeight)
                    if headerRect.contains(local) {
                        copyToClipboard(block.textItem.attributedString.string)
                        if let window = self.window as? Window {
                            showModalText(for: window, text: localizedString("Share.Link.Copied"))
                        }
                        return
                    }
                }
            }
        }
        if event.clickCount == 1, case let .link(link)? = interactiveTarget {
            if self.hasLocalSelection {
                self.clearBubbleSelection()
            }
            // A `#` link is an in-page anchor only if the layout actually has that anchor; otherwise
            // (e.g. a `#hashtag`) fall through to normal link handling via openUrl → inApp.
            if link.url.hasPrefix("#"), self.handleAnchorTap(name: String(link.url.dropFirst()), at: local) {
                return
            }
            let confirm = self.isLinkHidden(at: local)
            self.openUrl?(link, confirm)
            return
        }
        if event.clickCount == 1, self.hasLocalSelection {
            self.clearBubbleSelection()
        }
        // Mirror TextView: a click drops any existing selection across all selectable targets.
        selectManager.removeAll()
        super.mouseDown(with: event)
    }

    public override func mouseUp(with event: NSEvent) {
        if self.pressedUnsupported {
            self.pressedUnsupported = false
            let local = self.convert(event.locationInWindow, from: nil)
            if self.unsupportedItem(at: local) != nil {
                self.unsupportedTapped?()
            }
            return
        }
        if let pressed = self.pressedButtonAttachment {
            self.pressedButtonAttachment = nil
            let local = self.convert(event.locationInWindow, from: nil)
            if case let .button(attachment)? = self.interactiveTarget(at: local), attachment === pressed {
                self.buttonTapped?(pressed.button)
            }
            return
        }
        super.mouseUp(with: event)
    }

    private func selectWord(at point: NSPoint, in layout: InstantPageV2Layout) -> Bool {
        guard let hit = self.hitTextItem(at: point) else { return false }
        let textItem = hit.textItem
        let line = hit.line
        let localX = (point.x - hit.textOriginInView.x) - hit.textItem.alignedLineFrame(line).minX
        let charIndex = CTLineGetStringIndexForPosition(line.line, NSMakePoint(localX, 0))
        guard charIndex >= 0, charIndex < textItem.attributedString.length else { return false }
        let range = self.wordRange(in: textItem.attributedString, around: charIndex)
        guard range.length > 0 else { return false }
        self.installLocalSelection(textItem: textItem, range: range)
        return true
    }

    private func selectParagraph(at point: NSPoint, in layout: InstantPageV2Layout) -> Bool {
        guard let hit = self.hitTextItem(at: point) else { return false }
        let textItem = hit.textItem
        let range = NSRange(location: 0, length: textItem.attributedString.length)
        guard range.length > 0 else { return false }
        self.installLocalSelection(textItem: textItem, range: range)
        return true
    }

    /// Order matters: drop any prior selection first (which also clears OUR selectRects via the
    /// source's clearBubbleSelection callback), then install fresh local rects, then publish a
    /// bubble fragment so Cmd+C / selection menu can find it.
    private func installLocalSelection(textItem: InstantPageTextItem, range: NSRange) {
        selectManager.removeAll()
        self.applySelectRects(to: textItem, range: range)
        self.hasLocalSelection = true
        self.needsDisplay = true
        self.setThinkingContentNeedsDisplay()
        if let source = self.bubbleSelectionSource, let stableId = self.bubbleSelectionStableId {
            let fragment = ChatBubbleSelectionFragment(
                attributedString: textItem.attributedString,
                range: range,
                index: 0,
                richText: [instantPageRichTextForSelection(textItem.attributedString.attributedSubstring(from: range))]
            )
            selectManager.addBubble(fragment: fragment, source: source, header: nil, stableId: stableId)
            if let window = self.window, window.firstResponder !== selectManager {
                _ = window.makeFirstResponder(selectManager)
            }
        }
    }

    private struct TextHit {
        let textItem: InstantPageTextItem
        let line: InstantPageTextLine
        let textOriginInView: CGPoint
    }

    private func hitTextItem(at point: NSPoint) -> TextHit? {
        guard let layout = self.currentLayout else { return nil }
        var entities: [LogicalEntity] = []
        collectEntities(layout: layout, originInView: .zero, into: &entities)
        for entity in entities {
            if case let .text(textItem, line) = entity.kind, entity.frameInView.contains(point) {
                return TextHit(textItem: textItem, line: line, textOriginInView: entity.textOriginInView)
            }
        }
        return nil
    }

    /// The visible text of the link run under `point` (e.g. a mention's display name), or nil if the
    /// point isn't over a `.URL`-attributed run.
    private func linkDisplayText(at point: NSPoint) -> String? {
        guard let hit = self.hitTextItem(at: point) else { return nil }
        let line = hit.line
        let localX = (point.x - hit.textOriginInView.x) - hit.textItem.alignedLineFrame(line).minX
        let charIndex = CTLineGetStringIndexForPosition(line.line, NSMakePoint(localX, 0))
        let attr = hit.textItem.attributedString
        guard charIndex >= 0, charIndex < attr.length else { return nil }
        var effectiveRange = NSRange(location: 0, length: 0)
        guard attr.attribute(.URL, at: charIndex, effectiveRange: &effectiveRange) != nil, effectiveRange.length > 0 else { return nil }
        return (attr.string as NSString).substring(with: effectiveRange)
    }

    /// Mirrors `TextView.selectWord`: starts at the clicked character and expands left and right
    /// across alphanumerics + underscore until a non-word boundary. A click on a non-word
    /// character returns an empty range so the caller can fall through.
    private func wordRange(in string: NSAttributedString, around index: Int) -> NSRange {
        let nsString = string.string as NSString
        guard index >= 0, index < nsString.length else { return NSRange(location: 0, length: 0) }
        let initial = nsString.substring(with: NSRange(location: index, length: 1))
        if !isWordCharacter(initial) {
            return NSRange(location: 0, length: 0)
        }
        var lo = index
        var hi = index
        while lo > 0 {
            let prev = nsString.substring(with: NSRange(location: lo - 1, length: 1))
            if isWordCharacter(prev) { lo -= 1 } else { break }
        }
        while hi + 1 < nsString.length {
            let next = nsString.substring(with: NSRange(location: hi + 1, length: 1))
            if isWordCharacter(next) { hi += 1 } else { break }
        }
        return NSRange(location: lo, length: hi - lo + 1)
    }

    private func isWordCharacter(_ ch: String) -> Bool {
        let tidy = ch.trimmingCharacters(in: .alphanumerics)
        return tidy.isEmpty || tidy == "_" || tidy == "\u{FFFD}"
    }

    private func trackScrollerDrag(index: Int, startMouseX: CGFloat, startOffset: CGFloat) {
        guard let window = self.window else {
            self.tableScrollerDrag = nil
            return
        }
        let maxOffset = self.tableMaxOffset(index)
        while let event = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if event.type == .leftMouseUp {
                break
            }
            guard let rects = self.tableScrollerRects(index) else { continue }
            let trackWidth = rects.track.width - rects.thumb.width
            guard trackWidth > 0 else { continue }
            let local = self.convert(event.locationInWindow, from: nil)
            let pixelDelta = local.x - startMouseX
            let normalizedDelta = pixelDelta / trackWidth
            let newOffset = max(0, min(maxOffset, startOffset + normalizedDelta * maxOffset))
            _ = self.setTableScrollOffset(newOffset, at: index)
        }
        self.tableScrollerDrag = nil
        self.needsDisplay = true
        self.refreshTableDependentOverlays()
    }

    private func revealSpoilers() {
        self.spoilersRevealed = true
        for ink in self.inkViews {
            ink.update(revealed: true)
        }
        let toRemove = self.inkViews
        self.inkViews.removeAll()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            for view in toRemove {
                view.removeFromSuperview()
            }
        }
        self.needsDisplay = true
        if let layout = self.currentLayout {
            self.propagateSpoilerReveal(layout: layout)
        }
        self.setThinkingContentNeedsDisplay()
        self.onSpoilerReveal?()
    }

    private func updateCursor(with event: NSEvent) {
        let local = self.convert(event.locationInWindow, from: nil)
        for i in 0..<self.tableScrollOffsets.count {
            if let rects = self.tableScrollerRects(i), rects.track.contains(local) {
                (self.tableScrollerDrag != nil ? NSCursor.closedHand : NSCursor.openHand).set()
                return
            }
        }
        if self.interactiveTarget(at: local) != nil || self.isPointOverUnrevealedSpoiler(local) {
            NSCursor.pointingHand.set()
        } else if self.isPointOverText(local) {
            NSCursor.iBeam.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    /// The torn band whose "Update" pill is under `point`, if any. Only that pill is the hit area, exactly
    /// like the row in a plain unsupported message — the rest of the band falls through to text handling.
    private func unsupportedItem(at point: NSPoint) -> InstantPageV2UnsupportedItem? {
        guard let layout = self.currentLayout else { return nil }
        for (index, item) in layout.items.enumerated() {
            if let reveals = self.itemReveals, index < reveals.count, self.isHiddenReveal(reveals[index]) {
                continue
            }
            if case let .unsupported(unsupported) = item, unsupported.layout.pillRect(in: unsupported.frame).contains(point) {
                return unsupported
            }
        }
        return nil
    }

    private func interactiveTarget(at point: NSPoint) -> InteractiveTarget? {
        guard let layout = self.currentLayout else { return nil }
        return self.findInteractiveTarget(
            in: layout,
            at: point,
            originInView: .zero,
            clipRect: nil,
            usesTopLevelReveal: true
        )
    }

    private func findInteractiveTarget(
        in layout: InstantPageV2Layout,
        at point: NSPoint,
        originInView: CGPoint,
        clipRect: NSRect?,
        usesTopLevelReveal: Bool
    ) -> InteractiveTarget? {
        for (index, item) in layout.items.enumerated() {
            let reveal = usesTopLevelReveal
                ? self.itemReveals.flatMap { index < $0.count ? $0[index] : nil }
                : nil
            if let reveal, self.isHiddenReveal(reveal) {
                continue
            }
            switch item {
            case let .buttonRow(row):
                for entry in row.buttons {
                    let frame = entry.frame.offsetBy(
                        dx: originInView.x + row.frame.minX,
                        dy: originInView.y + row.frame.minY
                    )
                    if (clipRect.map { $0.intersects(frame) } ?? true), frame.contains(point) {
                        return .button(entry.attachment)
                    }
                }
            case let .text(textItem):
                let textOrigin = CGPoint(
                    x: originInView.x + textItem.frame.minX,
                    y: originInView.y + textItem.frame.minY
                )
                if let target = self.findInteractiveTarget(
                    in: textItem.textItem,
                    at: point,
                    textOriginInView: textOrigin,
                    clipRect: clipRect,
                    reveal: reveal
                ) {
                    return target
                }
            case let .codeBlock(block):
                let textOrigin = CGPoint(
                    x: originInView.x + block.frame.minX + block.textItem.frame.minX,
                    y: originInView.y + block.frame.minY + block.textItem.frame.minY
                )
                if let target = self.findInteractiveTarget(
                    in: block.textItem,
                    at: point,
                    textOriginInView: textOrigin,
                    clipRect: clipRect,
                    reveal: reveal
                ) {
                    return target
                }
            case let .details(details):
                let textOrigin = CGPoint(
                    x: originInView.x + details.frame.minX + details.titleTextItem.frame.minX,
                    y: originInView.y + details.frame.minY + details.titleTextItem.frame.minY
                )
                if let target = self.findInteractiveTarget(
                    in: details.titleTextItem,
                    at: point,
                    textOriginInView: textOrigin,
                    clipRect: clipRect,
                    reveal: reveal
                ) {
                    return target
                }
            case let .table(table):
                let tableViewport = NSRect(
                    x: originInView.x + table.frame.minX,
                    y: originInView.y + table.frame.minY,
                    width: table.frame.width,
                    height: table.frame.height
                )
                let tableClip = clipRect.map { $0.intersection(tableViewport) } ?? tableViewport
                guard !tableClip.isNull, tableClip.contains(point) else { continue }

                let scrollX = clipRect == nil ? self.scrollOffset(forTopLevel: table) : 0.0
                let tableMinX = table.frame.minX - scrollX
                if let titleLayout = table.titleSubLayout, let titleFrame = table.titleFrame {
                    let titleOrigin = CGPoint(
                        x: originInView.x + table.frame.minX + titleFrame.minX,
                        y: originInView.y + table.frame.minY + titleFrame.minY
                    )
                    if let target = self.findInteractiveTarget(
                        in: titleLayout,
                        at: point,
                        originInView: titleOrigin,
                        clipRect: tableClip,
                        usesTopLevelReveal: false
                    ) {
                        return target
                    }
                }
                let gridOffsetY: CGFloat = table.titleFrame?.height ?? 0.0
                for cell in table.cells {
                    guard let subLayout = cell.subLayout else { continue }
                    let cellOrigin = CGPoint(
                        x: originInView.x + tableMinX + cell.frame.minX,
                        y: originInView.y + table.frame.minY + cell.frame.minY + gridOffsetY
                    )
                    if let target = self.findInteractiveTarget(
                        in: subLayout,
                        at: point,
                        originInView: cellOrigin,
                        clipRect: tableClip,
                        usesTopLevelReveal: false
                    ) {
                        return target
                    }
                }
            default:
                break
            }
        }
        return nil
    }

    private func findInteractiveTarget(
        in textItem: InstantPageTextItem,
        at point: NSPoint,
        textOriginInView: CGPoint,
        clipRect: NSRect?,
        reveal: InstantPageV2ItemReveal?
    ) -> InteractiveTarget? {
        guard clipRect.map({ $0.contains(point) }) ?? true else { return nil }
        if textItem.hasButtons {
            let revealedCount = reveal.map { self.revealedCharacterCount(for: $0, textItem: textItem) }
            for line in textItem.lines where !line.buttonItems.isEmpty {
                let lineFrame = textItem.alignedLineFrame(line)
                for buttonItem in line.buttonItems {
                    if let revealedCount, buttonItem.range.location >= revealedCount {
                        continue
                    }
                    let frame = buttonItem.frame
                        .offsetBy(dx: lineFrame.minX + textOriginInView.x, dy: textOriginInView.y)
                    if frame.contains(point) {
                        return .button(buttonItem.attachment)
                    }
                }
            }
        }
        let localPoint = NSPoint(
            x: point.x - textOriginInView.x,
            y: point.y - textOriginInView.y
        )
        if let link = textItem.linkAt(point: localPoint) {
            return .link(link)
        }
        return nil
    }

    private func isPointOverUnrevealedSpoiler(_ point: NSPoint) -> Bool {
        guard !self.spoilersRevealed, let layout = self.currentLayout else { return false }
        for rect in self.collectSpoilerRects(layout: layout, originInView: .zero) {
            if rect.contains(point) { return true }
        }
        return false
    }

    private func isPointOverText(_ point: NSPoint) -> Bool {
        guard let layout = self.currentLayout else { return false }
        var entities: [LogicalEntity] = []
        collectEntities(layout: layout, originInView: .zero, into: &entities)
        for entity in entities {
            if entity.frameInView.contains(point) { return true }
        }
        return false
    }

    public func clickInContent(point: NSPoint) -> Bool {
        return self.isPointOverText(point)
            || self.isPointOverUnrevealedSpoiler(point)
            || self.interactiveTarget(at: point) != nil
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(layout: InstantPageV2Layout, theme: InstantPageTheme) {
        self.currentLayout = layout
        self.currentTheme = theme
        self.synchronizeTableScrollOffsets(with: layout)
        self.reconcileSubviews(layout: layout, theme: theme)
        self.recomputeItemReveals(animated: false)
        self.needsDisplay = true
    }

    /// Set the streaming reveal cost map (nil to disable streaming reveal entirely).
    public func setRevealCostMap(_ map: InstantPageV2RevealCostMap?) {
        self.revealCostMap = map
        if map == nil {
            self.revealCursor = nil
        }
        self.recomputeItemReveals(animated: false)
        // The cost map is installed after update(layout:); reconcile once more so a newly inserted
        // thinking host receives the authoritative whole-block reveal state.
        if let layout = self.currentLayout, let theme = self.currentTheme {
            self.reconcileThinkingShimmers(layout: layout, theme: theme)
        }
    }

    /// Advance the streaming reveal to `cursor` (in cost/width units), or nil to show everything.
    public func applyReveal(cursor: Int?) {
        let animated: Bool
        if let cursor, let previousCursor = self.revealCursor {
            animated = cursor >= previousCursor
        } else {
            animated = false
        }
        self.revealCursor = cursor
        self.recomputeItemReveals(animated: animated)
        self.needsDisplay = true
    }

    private func recomputeItemReveals(animated: Bool) {
        guard let layout = self.currentLayout, let map = self.revealCostMap, let cursor = self.revealCursor else {
            self.itemReveals = nil
            self.resetRevealTextAnimations()
            self.revealOpacityStates.removeAll()
            self.revealTableMaskStates.removeAll()
            if let layout = self.currentLayout {
                self.updateTableEmojiRevealMasks(layout: layout)
            }
            for header in self.detailsHeaders.values { header.isHidden = false }
            for body in self.detailsBodies.values {
                body.applyNestedReveal(costMap: nil, cursor: nil, animated: animated)
                body.isHidden = false
            }
            for media in self.mediaViews.values { self.applyRevealVisibility(to: media, visible: true, animated: false) }
            for slideshow in self.slideshowViews.values { self.applyRevealVisibility(to: slideshow, visible: true, animated: false) }
            self.updateThinkingReveal(animated: animated)
            self.updateInlineEmojiReveal(animated: animated)
            return
        }
        self.itemReveals = map.resolvedReveal(revealedCount: cursor, layout: layout)
        self.updateBlockRevealAnimations(layout: layout, animated: animated)
        self.updateTableEmojiRevealMasks(layout: layout)
        self.updateRevealTextAnimations(layout: layout, animated: animated)
        self.updateRevealSubviewVisibility(layout: layout, animated: animated)
        self.updateDetailsBodyReveal(layout: layout, animated: animated)
        self.updateThinkingReveal(animated: animated)
        self.updateInlineEmojiReveal(animated: animated)
    }

    private func applyNestedReveal(costMap: InstantPageV2RevealCostMap?, cursor: Int?, animated: Bool) {
        self.revealCostMap = costMap
        self.revealCursor = costMap == nil ? nil : cursor
        self.recomputeItemReveals(animated: animated)
        self.needsDisplay = true
    }

    private func updateDetailsBodyReveal(layout: InstantPageV2Layout, animated: Bool) {
        guard let itemReveals = self.itemReveals else { return }
        for (itemIndex, item) in layout.items.enumerated() {
            guard case let .details(details) = item,
                  let body = self.detailsBodies[details.index],
                  itemIndex < itemReveals.count else {
                continue
            }
            if case let .details(_, bodyCostMap, _) = itemReveals[itemIndex] {
                body.applyNestedReveal(
                    costMap: bodyCostMap,
                    cursor: self.revealCursor,
                    animated: animated
                )
            } else {
                body.applyNestedReveal(costMap: nil, cursor: nil, animated: animated)
            }
        }
    }

    private func resetRevealTextAnimations() {
        for state in self.revealTextStates.values {
            for layer in state.activeSnippetLayers.values {
                layer.removeFromSuperlayer()
            }
        }
        self.revealTextStates.removeAll()
    }

    private func updateBlockRevealAnimations(layout: InstantPageV2Layout, animated: Bool) {
        guard let reveals = self.itemReveals else {
            self.revealOpacityStates.removeAll()
            self.revealTableMaskStates.removeAll()
            return
        }
        var opacityTargets: [RevealBlockKey: CGFloat] = [:]
        var tableMaskTargets: [RevealBlockKey: CGFloat] = [:]
        for (index, item) in layout.items.enumerated() {
            let reveal = index < reveals.count ? reveals[index] : .full
            let key = RevealBlockKey(topLevelIndex: index, tableCellIndex: nil, subitemIndex: nil)
            self.collectBlockRevealTargets(
                item: item,
                reveal: reveal,
                key: key,
                opacityTargets: &opacityTargets,
                tableMaskTargets: &tableMaskTargets
            )
        }
        self.updateRevealScalarStates(targets: opacityTargets, states: &self.revealOpacityStates, animated: animated)
        self.updateRevealScalarStates(targets: tableMaskTargets, states: &self.revealTableMaskStates, animated: animated)
    }

    private func collectBlockRevealTargets(
        item: InstantPageV2LaidOutItem,
        reveal: InstantPageV2ItemReveal,
        key: RevealBlockKey,
        opacityTargets: inout [RevealBlockKey: CGFloat],
        tableMaskTargets: inout [RevealBlockKey: CGFloat]
    ) {
        switch item {
        case .text, .details:
            break
        case let .table(table):
            let tableReveal: InstantPageV2TableReveal?
            switch reveal {
            case let .table(value):
                tableReveal = value
                tableMaskTargets[key] = value.visibleHeight
            case .hidden:
                tableReveal = nil
                tableMaskTargets[key] = 0.0
            default:
                tableReveal = nil
                tableMaskTargets[key] = table.frame.height
            }
            if let titleLayout = table.titleSubLayout {
                let titleReveals = tableReveal?.title
                for (subitemIndex, subitem) in titleLayout.items.enumerated() {
                    let subReveal = titleReveals.flatMap { subitemIndex < $0.count ? $0[subitemIndex] : nil } ?? (self.isHiddenReveal(reveal) ? .hidden : .full)
                    self.collectBlockRevealTargets(
                        item: subitem,
                        reveal: subReveal,
                        key: RevealBlockKey(topLevelIndex: key.topLevelIndex, tableCellIndex: -1, subitemIndex: subitemIndex),
                        opacityTargets: &opacityTargets,
                        tableMaskTargets: &tableMaskTargets
                    )
                }
            }
            for (cellIndex, cell) in table.cells.enumerated() {
                guard let subLayout = cell.subLayout else { continue }
                let cellReveals = tableReveal?.cells[InstantPageV2CellFrameKey(cell.frame)]
                for (subitemIndex, subitem) in subLayout.items.enumerated() {
                    let subReveal = cellReveals.flatMap { subitemIndex < $0.count ? $0[subitemIndex] : nil } ?? (self.isHiddenReveal(reveal) ? .hidden : .full)
                    self.collectBlockRevealTargets(
                        item: subitem,
                        reveal: subReveal,
                        key: RevealBlockKey(topLevelIndex: key.topLevelIndex, tableCellIndex: cellIndex, subitemIndex: subitemIndex),
                        opacityTargets: &opacityTargets,
                        tableMaskTargets: &tableMaskTargets
                    )
                }
            }
        default:
            opacityTargets[key] = self.isHiddenReveal(reveal) ? 0.0 : 1.0
        }
    }

    private func updateRevealScalarStates(
        targets: [RevealBlockKey: CGFloat],
        states: inout [RevealBlockKey: RevealScalarState],
        animated: Bool
    ) {
        let now = CACurrentMediaTime()
        let removedKeys = states.keys.filter { targets[$0] == nil }
        for key in removedKeys {
            states.removeValue(forKey: key)
        }
        for (key, target) in targets {
            if let state = states[key] {
                guard state.targetValue != target else { continue }
                let current = self.revealScalarValue(state, now: now)
                state.fromValue = current
                state.targetValue = target
                state.startTime = animated ? now : nil
                if !animated {
                    state.fromValue = target
                }
            } else {
                states[key] = RevealScalarState(value: target)
            }
        }
    }

    private func revealScalarValue(_ state: RevealScalarState, now: CFTimeInterval = CACurrentMediaTime()) -> CGFloat {
        guard let startTime = state.startTime else { return state.targetValue }
        let progress = min(1.0, max(0.0, (now - startTime) / 0.12))
        if progress >= 1.0 {
            state.startTime = nil
            state.fromValue = state.targetValue
            return state.targetValue
        }
        self.needsDisplay = true
        return state.fromValue + (state.targetValue - state.fromValue) * CGFloat(progress)
    }

    private func revealOpacity(for key: RevealBlockKey?) -> CGFloat {
        guard let key, let state = self.revealOpacityStates[key] else { return 1.0 }
        return self.revealScalarValue(state)
    }

    private func revealTableMaskHeight(for key: RevealBlockKey?, fallback: CGFloat) -> CGFloat {
        guard let key, let state = self.revealTableMaskStates[key] else { return fallback }
        return self.revealScalarValue(state)
    }

    private func updateTableEmojiRevealMasks(layout: InstantPageV2Layout) {
        var tableIndex = 0
        for (itemIndex, item) in layout.items.enumerated() {
            guard case let .table(table) = item else { continue }
            defer { tableIndex += 1 }
            guard let container = self.tableEmojiContainers[tableIndex] else { continue }
            let key = RevealBlockKey(topLevelIndex: itemIndex, tableCellIndex: nil, subitemIndex: nil)
            let height = self.revealTableMaskHeight(for: key, fallback: table.frame.height)
            container.frame = CGRect(
                x: table.frame.minX,
                y: table.frame.minY,
                width: table.frame.width,
                height: max(0.0, min(table.frame.height, height))
            )
        }
    }

    private func revealedCharacterCount(for reveal: InstantPageV2ItemReveal, textItem: InstantPageTextItem) -> Int {
        switch reveal {
        case .full, .table(_):
            return textItem.attributedString.length
        case .hidden:
            return 0
        case let .clipText(charCount):
            return max(0, min(textItem.attributedString.length, charCount))
        case let .details(titleCharacterCount, _, _):
            return max(0, min(textItem.attributedString.length, titleCharacterCount))
        }
    }

    private func revealTextTargets(layout: InstantPageV2Layout) -> [RevealTextKey: RevealTextTarget] {
        var result: [RevealTextKey: RevealTextTarget] = [:]
        let reveals = self.itemReveals

        func appendTarget(item: InstantPageV2LaidOutItem, reveal: InstantPageV2ItemReveal, key: RevealTextKey, origin: CGPoint) {
            let textItem: InstantPageTextItem
            let contentOrigin: CGPoint
            switch item {
            case let .text(text):
                guard !text.isThinking else { return }
                textItem = text.textItem
                contentOrigin = CGPoint(x: origin.x + text.frame.minX, y: origin.y + text.frame.minY)
            case let .codeBlock(block):
                textItem = block.textItem
                contentOrigin = CGPoint(
                    x: origin.x + block.frame.minX + block.textItem.frame.minX,
                    y: origin.y + block.frame.minY + block.textItem.frame.minY
                )
            case let .details(details):
                textItem = details.titleTextItem
                contentOrigin = CGPoint(
                    x: origin.x + details.frame.minX + details.titleTextItem.frame.minX,
                    y: origin.y + details.frame.minY + details.titleTextItem.frame.minY
                )
            default:
                return
            }
            result[key] = RevealTextTarget(
                textItem: textItem,
                contentOrigin: contentOrigin,
                revealedCharacterCount: self.revealedCharacterCount(for: reveal, textItem: textItem)
            )
        }

        for (topLevelIndex, item) in layout.items.enumerated() {
            let reveal: InstantPageV2ItemReveal = (reveals != nil && topLevelIndex < reveals!.count) ? reveals![topLevelIndex] : .full
            let topLevelKey = RevealTextKey(topLevelIndex: topLevelIndex, tableCellIndex: nil, subitemIndex: nil)

            switch item {
            case .text, .codeBlock, .details:
                appendTarget(item: item, reveal: reveal, key: topLevelKey, origin: .zero)
            case let .table(table):
                let tableReveal: InstantPageV2TableReveal?
                let tableIsHidden: Bool
                switch reveal {
                case let .table(value):
                    tableReveal = value
                    tableIsHidden = false
                case .hidden:
                    tableReveal = nil
                    tableIsHidden = true
                default:
                    tableReveal = nil
                    tableIsHidden = false
                }

                let scrollX = self.scrollOffset(forTopLevel: table)
                let gridOffsetY = table.titleFrame?.height ?? 0.0
                if let titleLayout = table.titleSubLayout, let titleFrame = table.titleFrame {
                    let titleReveals = tableReveal?.title
                    for (subitemIndex, subitem) in titleLayout.items.enumerated() {
                        let subReveal = titleReveals.flatMap { subitemIndex < $0.count ? $0[subitemIndex] : nil } ?? (tableIsHidden ? .hidden : .full)
                        let key = RevealTextKey(topLevelIndex: topLevelIndex, tableCellIndex: -1, subitemIndex: subitemIndex)
                        appendTarget(
                            item: subitem,
                            reveal: subReveal,
                            key: key,
                            origin: CGPoint(
                                x: table.frame.minX + titleFrame.minX,
                                y: table.frame.minY + titleFrame.minY
                            )
                        )
                    }
                }
                for (cellIndex, cell) in table.cells.enumerated() {
                    guard let subLayout = cell.subLayout else { continue }
                    let cellReveals = tableReveal?.cells[InstantPageV2CellFrameKey(cell.frame)]
                    for (subitemIndex, subitem) in subLayout.items.enumerated() {
                        let subReveal = cellReveals.flatMap { subitemIndex < $0.count ? $0[subitemIndex] : nil } ?? (tableIsHidden ? .hidden : .full)
                        let key = RevealTextKey(
                            topLevelIndex: topLevelIndex,
                            tableCellIndex: cellIndex,
                            subitemIndex: subitemIndex
                        )
                        appendTarget(
                            item: subitem,
                            reveal: subReveal,
                            key: key,
                            origin: CGPoint(
                                x: table.frame.minX - scrollX + cell.frame.minX,
                                y: table.frame.minY + gridOffsetY + cell.frame.minY
                            )
                        )
                    }
                }
            default:
                break
            }
        }
        return result
    }

    private func updateRevealTextAnimations(layout: InstantPageV2Layout, animated: Bool) {
        let targets = self.revealTextTargets(layout: layout)

        let removedKeys = self.revealTextStates.keys.filter { targets[$0] == nil }
        for key in removedKeys {
            guard let state = self.revealTextStates.removeValue(forKey: key) else { continue }
            for layer in state.activeSnippetLayers.values {
                layer.removeFromSuperlayer()
            }
        }

        for (key, target) in targets {
            let state: RevealTextState
            if let current = self.revealTextStates[key] {
                state = current
                state.textItem = target.textItem
                state.contentOrigin = target.contentOrigin
                for layer in state.activeSnippetLayers.values {
                    layer.updateFrame(contentOrigin: target.contentOrigin)
                }
            } else {
                let current = RevealTextState(
                    targetCharacterCount: target.revealedCharacterCount,
                    textItem: target.textItem,
                    contentOrigin: target.contentOrigin
                )
                self.revealTextStates[key] = current
                continue
            }

            if target.revealedCharacterCount < state.targetCharacterCount || (!animated && target.revealedCharacterCount != state.targetCharacterCount) {
                for layer in state.activeSnippetLayers.values {
                    layer.removeFromSuperlayer()
                }
                state.activeSnippetLayers.removeAll()
                state.targetCharacterCount = target.revealedCharacterCount
                continue
            }

            if animated && target.revealedCharacterCount > state.targetCharacterCount {
                self.animateNewRevealCharacters(
                    from: state.targetCharacterCount,
                    to: target.revealedCharacterCount,
                    key: key,
                    state: state
                )
            }
            state.targetCharacterCount = target.revealedCharacterCount
        }
    }

    private func animateNewRevealCharacters(from previousCount: Int, to currentCount: Int, key: RevealTextKey, state: RevealTextState) {
        guard let hostLayer = self.layer else { return }
        let textItem = state.textItem
        if textItem.hasButtons, let theme = self.currentTheme {
            textItem.instantPageTheme = theme
        }
        var previousRemaining = previousCount
        var currentRemaining = currentCount
        var globalCharacterIndex = 0

        for line in textItem.lines {
            let lineCharacterCount = line.characterRects?.count ?? line.range.length
            let previousLineCount = min(max(0, previousRemaining), lineCharacterCount)
            let currentLineCount = min(max(0, currentRemaining), lineCharacterCount)
            previousRemaining -= lineCharacterCount
            currentRemaining -= lineCharacterCount

            defer { globalCharacterIndex += lineCharacterCount }
            guard currentLineCount > previousLineCount, let characterRects = line.characterRects else {
                continue
            }

            let lineFrame = textItem.alignedLineFrame(line)
            for characterIndexInLine in previousLineCount ..< currentLineCount {
                let characterRect = characterRects[characterIndexInLine]
                if characterRect.isEmpty || characterRect.width < 0.5 {
                    continue
                }

                let characterIndex = globalCharacterIndex + characterIndexInLine
                if state.activeSnippetLayers[characterIndex] != nil {
                    continue
                }
                let sourceRect = CGRect(
                    x: lineFrame.minX + characterRect.origin.x,
                    y: lineFrame.minY,
                    width: characterRect.width,
                    height: lineFrame.height
                )
                let snippetLayer = InstantPageV2RevealSnippetLayer(
                    characterIndex: characterIndex,
                    textItem: textItem,
                    sourceRect: sourceRect,
                    contentsScale: self.window?.backingScaleFactor ?? System.backingScale
                )
                snippetLayer.updateFrame(contentOrigin: state.contentOrigin)
                hostLayer.addSublayer(snippetLayer)
                state.activeSnippetLayers[characterIndex] = snippetLayer

                if let blurFilter = ee2_makeBlurFilter() {
                    blurFilter.setValue(0.0 as NSNumber, forKey: "inputRadius")
                    snippetLayer.filters = [blurFilter]
                    let blurAnimation = CABasicAnimation(keyPath: "filters.gaussianBlur.inputRadius")
                    blurAnimation.fromValue = 2.0
                    blurAnimation.toValue = 0.0
                    blurAnimation.duration = 0.22
                    blurAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                    snippetLayer.add(blurAnimation, forKey: "richMessageRevealBlur")
                }
                snippetLayer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2, timingFunction: .easeInEaseOut)
                snippetLayer.animatePosition(
                    from: CGPoint(x: 0.0, y: 6.0),
                    to: .zero,
                    duration: 0.2,
                    timingFunction: .easeInEaseOut,
                    additive: true
                )
                snippetLayer.animateScale(from: 0.5, to: 1.0, duration: 0.2, timingFunction: .easeInEaseOut, completion: { [weak self, weak snippetLayer] _ in
                    guard let self, let snippetLayer,
                          let currentState = self.revealTextStates[key],
                          currentState.activeSnippetLayers[characterIndex] === snippetLayer else {
                        return
                    }
                    currentState.activeSnippetLayers.removeValue(forKey: characterIndex)
                    snippetLayer.removeFromSuperlayer()
                    self.needsDisplay = true
                })
            }
        }
    }

    private func canvasCharacterLimit(for key: RevealTextKey, requestedCount: Int) -> Int {
        guard let state = self.revealTextStates[key], let firstAnimating = state.activeSnippetLayers.keys.min() else {
            return requestedCount
        }
        return min(requestedCount, firstAnimating)
    }

    private func updateThinkingReveal(animated: Bool) {
        for view in self.thinkingViews.values {
            let isRevealed: Bool
            if let itemReveals = self.itemReveals, view.topLevelItemIndex < itemReveals.count {
                isRevealed = !self.isHiddenReveal(itemReveals[view.topLevelItemIndex])
            } else {
                isRevealed = true
            }
            view.setRevealed(isRevealed, animated: animated)
        }
    }

    private func setThinkingContentNeedsDisplay() {
        for view in self.thinkingViews.values {
            view.setContentNeedsDisplay()
        }
    }

    private func applyRevealVisibility(to view: NSView, visible: Bool, animated: Bool) {
        let targetOpacity: CGFloat = visible ? 1.0 : 0.0
        guard let layer = view.layer else {
            view.alphaValue = targetOpacity
            view.isHidden = !visible
            return
        }
        if !animated {
            layer.removeAnimation(forKey: "richMessageBlockReveal")
            view.alphaValue = targetOpacity
            view.isHidden = !visible
            return
        }
        if visible {
            if !view.isHidden && view.alphaValue == 1.0 { return }
            let source = view.alphaValue
            view.isHidden = false
            view.alphaValue = 1.0
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = source
            animation.toValue = 1.0
            animation.duration = 0.12
            layer.add(animation, forKey: "richMessageBlockReveal")
        } else {
            if view.isHidden || view.alphaValue == 0.0 { return }
            let source = view.alphaValue
            view.alphaValue = 0.0
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = source
            animation.toValue = 0.0
            animation.duration = 0.12
            layer.add(animation, forKey: "richMessageBlockReveal")
        }
    }

    private func updateRevealSubviewVisibility(layout: InstantPageV2Layout, animated: Bool) {
        guard let reveals = self.itemReveals else {
            for header in self.detailsHeaders.values { header.isHidden = false }
            for body in self.detailsBodies.values { body.isHidden = false }
            for media in self.mediaViews.values { self.applyRevealVisibility(to: media, visible: true, animated: animated) }
            for slideshow in self.slideshowViews.values { self.applyRevealVisibility(to: slideshow, visible: true, animated: animated) }
            return
        }
        for (i, item) in layout.items.enumerated() {
            let hidden = (i < reveals.count) ? isHiddenReveal(reveals[i]) : false
            switch item {
            case let .details(d):
                self.detailsHeaders[d.index]?.isHidden = hidden
                self.detailsBodies[d.index]?.isHidden = hidden
            case let .mediaImage(m):
                if let view = self.mediaViews[m.media.index] { self.applyRevealVisibility(to: view, visible: !hidden, animated: animated) }
            case let .mediaVideo(m):
                if let view = self.mediaViews[m.media.index] { self.applyRevealVisibility(to: view, visible: !hidden, animated: animated) }
            case let .mediaMap(m):
                if let view = self.mediaViews[m.media.index] { self.applyRevealVisibility(to: view, visible: !hidden, animated: animated) }
            case let .mediaCoverImage(m):
                if let view = self.mediaViews[m.media.index] { self.applyRevealVisibility(to: view, visible: !hidden, animated: animated) }
            case let .mediaPlaceholder(m):
                if let key = m.slideshowMedias.first?.index, let view = self.slideshowViews[key] {
                    self.applyRevealVisibility(to: view, visible: !hidden, animated: animated)
                }
            default:
                break
            }
        }
    }

    /// Hosts the chat's own `ChatMediaContentView` subclasses for top-level photo / video / map /
    /// cover-image items, so they render and open exactly like chat media: photo & video open the
    /// gallery, music/voice play in the player, maps open the map view. The chat-message context
    /// (parent message + gallery parameters) is supplied by `mediaContentConfig`. Audio and the
    /// various embeds that the layout turns into `.mediaPlaceholder` stay grey boxes, matching iOS.
    /// Media nested in tables/details bodies is handled by the respective child views.
    private func reconcileMediaViews(layout: InstantPageV2Layout) {
        guard let context = self.context, let config = self.mediaContentConfig else {
            for (_, view) in self.mediaViews { view.removeFromSuperview() }
            self.mediaViews.removeAll()
            return
        }
        var active: Set<Int> = []
        for item in layout.items {
            let media: Media
            let frame: CGRect
            let index: Int
            let cornerRadius: CGFloat
            let itemSpoiler: Bool
            let isFile: Bool
            switch item {
            case let .mediaImage(m):        media = m.media.media; frame = m.frame; index = m.media.index; cornerRadius = m.cornerRadius; itemSpoiler = m.spoiler; isFile = false
            case let .mediaCoverImage(m):   media = m.media.media; frame = m.frame; index = m.media.index; cornerRadius = m.cornerRadius; itemSpoiler = false; isFile = false
            case let .mediaVideo(m):        media = m.media.media; frame = m.frame; index = m.media.index; cornerRadius = m.cornerRadius; itemSpoiler = m.spoiler; isFile = m.isFile
            case let .mediaMap(m):          media = m.media.media; frame = m.frame; index = m.media.index; cornerRadius = m.cornerRadius; itemSpoiler = false; isFile = false
            default:                        continue
            }
            guard let (parent, parameters) = config(media, frame.size, index, isFile) else { continue }
            // Media spoiler: render the dust until the user taps it (per-item reveal, like the chat's).
            if itemSpoiler, !self.revealedMediaIndices.contains(index) {
                parameters.forceSpoiler = true
                parameters.revealMedia = { [weak self] _ in
                    guard let self = self, let layout = self.currentLayout else { return }
                    self.revealedMediaIndices.insert(index)
                    self.reconcileMediaViews(layout: layout)
                }
            }
            // Measure the parameters' text labels for the hosting width (audio title/duration, file
            // name, etc.) — the standard row item does this in makeContentSize; reconcile must too,
            // or e.g. ChatMusicContentView shows no title/artist. No-op for params without labels.
            _ = parameters.makeLabelsForWidth(frame.size.width)
            active.insert(index)
            let contentClass: ChatMediaContentView.Type
            if isFile, media is TelegramMediaFile {
                contentClass = ChatFileContentView.self
            } else {
                contentClass = ChatLayoutUtils.contentNode(for: media)
            }
            let view: ChatMediaContentView
            if let existing = self.mediaViews[index], existing.isKind(of: contentClass) {
                view = existing
            } else {
                self.mediaViews[index]?.removeFromSuperview()
                view = contentClass.init(frame: frame)
                self.addSubview(view)
                self.mediaViews[index] = view
            }
            // Square corners for full-bleed (bubble) photo/video/collage media — the layout sets the
            // item corner radius to 0 in that case. Must be set before update (it drives the rendered
            // image's corner radii). Maps square themselves via the map params.
            (view as? ChatInteractiveContentView)?.squareCorners = cornerRadius <= 0
            view.update(with: media, size: frame.size, context: context, parent: parent, table: nil, parameters: parameters, animated: false)
            view.frame = frame
            view.updateLayout(size: frame.size, transition: .immediate)
        }
        for (index, view) in self.mediaViews where !active.contains(index) {
            view.removeFromSuperview()
            self.mediaViews.removeValue(forKey: index)
        }
    }

    /// The hosted media view for a given `InstantPageMedia.index`, searched top-level → details bodies
    /// → slideshows. Used as the gallery's open/close zoom source.
    public func mediaContentView(forMediaIndex index: Int) -> NSView? {
        if let view = self.mediaViews[index] {
            return view
        }
        for body in self.detailsBodies.values {
            if let view = body.mediaContentView(forMediaIndex: index) {
                return view
            }
        }
        for slideshow in self.slideshowViews.values {
            if let view = slideshow.mediaContentView(forMediaIndex: index) {
                return view
            }
        }
        return nil
    }

    /// All hosted audio/music content views (top-level + nested details bodies). The global inline
    /// player registers these as listeners via `addGlobalAudioToVisible` so the bubble reflects
    /// play/pause state, since it can't reach them through the standard chat-row content path.
    public func audioContentViews() -> [ChatAudioContentView] {
        var result: [ChatAudioContentView] = []
        for (_, view) in self.mediaViews {
            if let audio = view as? ChatAudioContentView {
                result.append(audio)
            }
        }
        for body in self.detailsBodies.values {
            result.append(contentsOf: body.audioContentViews())
        }
        return result
    }

    /// Hosts a paging `SliderView` over each `.slideshow` placeholder, paging through its images/videos
    /// (the placeholder's grey box isn't painted when slideshow medias are present). Keyed by the first
    /// slide's media index, which is stable for the same content.
    private func reconcileSlideshows(layout: InstantPageV2Layout) {
        guard let context = self.context, let config = self.mediaContentConfig else {
            for view in self.slideshowViews.values { view.removeFromSuperview() }
            self.slideshowViews.removeAll()
            return
        }
        var active: Set<Int> = []
        for item in layout.items {
            guard case let .mediaPlaceholder(p) = item, !p.slideshowMedias.isEmpty,
                  let key = p.slideshowMedias.first?.index else { continue }
            active.insert(key)
            let view: InstantPageV2SlideshowView
            if let existing = self.slideshowViews[key] {
                view = existing
            } else {
                view = InstantPageV2SlideshowView(frame: p.frame)
                self.addSubview(view)
                self.slideshowViews[key] = view
            }
            view.frame = p.frame
            view.cornerRadius = p.cornerRadius
            view.configure(medias: p.slideshowMedias, context: context, config: config, size: p.frame.size)
        }
        for (key, view) in self.slideshowViews where !active.contains(key) {
            view.removeFromSuperview()
            self.slideshowViews.removeValue(forKey: key)
        }
    }

    /// Hosts every top-level thinking block in a single masked subtree so its Core Text content and
    /// inline emoji share the same continuously moving alpha gradient.
    private func reconcileThinkingShimmers(layout: InstantPageV2Layout, theme: InstantPageTheme) {
        var activeOccurrences: Set<Int> = []
        var viewsByItemIndex: [Int: InstantPageV2ThinkingView] = [:]
        var occurrence = 0

        for (itemIndex, item) in layout.items.enumerated() {
            guard case let .text(textItem) = item, textItem.isThinking else {
                continue
            }
            activeOccurrences.insert(occurrence)
            let view: InstantPageV2ThinkingView
            if let existing = self.thinkingViews[occurrence] {
                view = existing
            } else {
                view = InstantPageV2ThinkingView(item: textItem, theme: theme)
                self.thinkingViews[occurrence] = view
                self.addSubview(view)
            }
            view.topLevelItemIndex = itemIndex
            view.update(item: textItem, theme: theme)
            viewsByItemIndex[itemIndex] = view
            occurrence += 1
        }

        for (key, view) in self.thinkingViews where !activeOccurrences.contains(key) {
            view.removeFromSuperview()
            self.thinkingViews.removeValue(forKey: key)
        }
        self.thinkingViewsByItemIndex = viewsByItemIndex
        self.updateThinkingReveal(animated: false)
    }

    /// Returns the horizontal scroll offset for `table` if it's a top-level table in the current
    /// layout; 0 otherwise. Tables nested inside other tables don't scroll.
    private func scrollOffset(forTopLevel table: InstantPageV2TableItem) -> CGFloat {
        guard let layout = self.currentLayout else { return 0 }
        var idx = 0
        for item in layout.items {
            if case let .table(t) = item {
                if t.frame.origin == table.frame.origin && t.cells.count == table.cells.count {
                    return idx < self.tableScrollOffsets.count ? self.tableScrollOffsets[idx] : 0
                }
                idx += 1
            }
        }
        return 0
    }

    private static func countTopLevelTables(in layout: InstantPageV2Layout) -> Int {
        var n = 0
        for item in layout.items { if case .table = item { n += 1 } }
        return n
    }

    public func resetTableScrollState() {
        self.tableScrollerDrag = nil
        guard !self.tableScrollOffsets.isEmpty else { return }
        self.tableScrollOffsets = Array(repeating: 0, count: self.tableScrollOffsets.count)
        self.needsDisplay = true
        self.refreshTableDependentOverlays()
    }

    private func synchronizeTableScrollOffsets(with layout: InstantPageV2Layout) {
        let tableCount = Self.countTopLevelTables(in: layout)
        guard self.tableScrollOffsets.count == tableCount else {
            self.tableScrollOffsets = Array(repeating: 0, count: tableCount)
            return
        }
        for i in self.tableScrollOffsets.indices {
            self.tableScrollOffsets[i] = max(0, min(self.tableMaxOffset(i), self.tableScrollOffsets[i]))
        }
    }

    @discardableResult
    private func setTableScrollOffset(_ offset: CGFloat, at index: Int) -> Bool {
        guard self.tableScrollOffsets.indices.contains(index) else { return false }
        let clamped = max(0, min(self.tableMaxOffset(index), offset))
        guard clamped != self.tableScrollOffsets[index] else { return false }
        self.tableScrollOffsets[index] = clamped
        self.needsDisplay = true
        self.refreshTableDependentOverlays()
        return true
    }

    private func refreshTableDependentOverlays() {
        guard let layout = self.currentLayout, let theme = self.currentTheme else { return }
        if self.revealCostMap != nil, self.revealCursor != nil {
            self.updateRevealTextAnimations(layout: layout, animated: false)
        }
        self.reconcileSpoilerInks(layout: layout, theme: theme)
        self.reconcileInlineEmoji(layout: layout, theme: theme)
        self.reconcileLinkTooltips(layout: layout)
    }

    /// Index of the table at point inside `layout.items`, in walk order; nil otherwise.
    /// Walks only top-level items — nested tables in cells stay clipped.
    private func tableIndex(at point: NSPoint) -> Int? {
        guard let layout = self.currentLayout else { return nil }
        var idx = 0
        for item in layout.items {
            if case let .table(table) = item {
                if table.frame.contains(point) { return idx }
                idx += 1
            }
        }
        return nil
    }

    /// Max horizontal scroll for table `i` (>=0).
    private func tableMaxOffset(_ i: Int) -> CGFloat {
        guard let layout = self.currentLayout else { return 0 }
        var idx = 0
        for item in layout.items {
            if case let .table(table) = item {
                if idx == i {
                    return table.isHorizontallyScrollable ? table.contentSize.width - table.frame.width : 0
                }
                idx += 1
            }
        }
        return 0
    }

    /// Walk-order index of a top-level table whose frame equals the given frame.
    private func tableIndex(forFrame frame: CGRect) -> Int? {
        guard let layout = self.currentLayout else { return nil }
        var idx = 0
        for item in layout.items {
            if case let .table(t) = item {
                if t.frame == frame { return idx }
                idx += 1
            }
        }
        return nil
    }

    /// Returns (track rect, thumb rect) in V2View coords for the scroller at the bottom of
    /// the i-th top-level table, or nil if the table doesn't overflow horizontally.
    private func tableScrollerRects(_ i: Int) -> (track: NSRect, thumb: NSRect)? {
        guard let layout = self.currentLayout else { return nil }
        var idx = 0
        for item in layout.items {
            if case let .table(table) = item {
                if idx == i {
                    guard table.isHorizontallyScrollable else { return nil }
                    let trackInset: CGFloat = 4
                    let trackY = table.frame.maxY - v2TableScrollerHeight + trackInset
                    let trackHeight = v2TableScrollerHeight - trackInset * 2
                    let track = NSRect(
                        x: table.frame.minX + trackInset,
                        y: trackY,
                        width: table.frame.width - trackInset * 2,
                        height: trackHeight
                    )
                    let visibleRatio = max(0.12, min(1.0, table.frame.width / table.contentSize.width))
                    let thumbWidth = max(28, track.width * visibleRatio)
                    let maxOffset = self.tableMaxOffset(i)
                    let normalized = maxOffset > 0 ? self.tableScrollOffsets[i] / maxOffset : 0
                    let thumbX = track.minX + (track.width - thumbWidth) * normalized
                    let thumb = NSRect(x: thumbX, y: track.minY, width: thumbWidth, height: track.height)
                    return (track, thumb)
                }
                idx += 1
            }
        }
        return nil
    }

    public override func scrollWheel(with event: NSEvent) {
        let local = self.convert(event.locationInWindow, from: nil)
        let dx = event.scrollingDeltaX
        let dy = event.scrollingDeltaY
        if abs(dx) > abs(dy), let i = self.tableIndex(at: local), i < self.tableScrollOffsets.count {
            let maxOffset = self.tableMaxOffset(i)
            if maxOffset > 0 {
                let current = self.tableScrollOffsets[i]
                let next = max(0, min(maxOffset, current - dx))
                _ = self.setTableScrollOffset(next, at: i)
                return
            }
        }
        super.scrollWheel(with: event)
    }

    public func setSpoilerReveal(_ revealed: Bool) {
        guard self.spoilersRevealed != revealed else { return }
        self.spoilersRevealed = revealed
        if let layout = self.currentLayout, let theme = self.currentTheme {
            self.reconcileSubviews(layout: layout, theme: theme)
        }
        self.needsDisplay = true
    }

    public var contentSize: NSSize {
        return currentLayout?.contentSize ?? .zero
    }

    private func reconcileSubviews(layout: InstantPageV2Layout, theme: InstantPageTheme) {
        var activeDetails: Set<Int> = []
        for item in layout.items {
            if case let .details(d) = item {
                activeDetails.insert(d.index)
                let header: InstantPageV2DetailsHeaderView
                if let existing = self.detailsHeaders[d.index] {
                    header = existing
                    header.update(item: d, color: theme.textCategories.paragraph.color)
                } else {
                    header = InstantPageV2DetailsHeaderView(
                        item: d,
                        color: theme.textCategories.paragraph.color
                    )
                    self.addSubview(header)
                    self.detailsHeaders[d.index] = header

                    let tap = NSClickGestureRecognizer(target: self, action: #selector(self.detailsClicked(_:)))
                    header.addGestureRecognizer(tap)
                    header.identifier = NSUserInterfaceItemIdentifier(rawValue: "details-\(d.index)")
                }
                header.frame = d.titleFrame.offsetBy(dx: d.frame.minX, dy: d.frame.minY)

                if d.isExpanded, let inner = d.innerLayout {
                    let body: InstantPageV2View
                    if let existing = self.detailsBodies[d.index] {
                        body = existing
                    } else {
                        body = InstantPageV2View(frame: .zero)
                        body.openMedia = { [weak self] media in self?.openMedia?(media) }
                        body.openUrl = { [weak self] url, confirm in self?.openUrl?(url, confirm) }
                        body.onSpoilerReveal = { [weak self] in self?.onSpoilerReveal?() }
                        body.detailsTapped = { [weak self] index in self?.detailsTapped?(index) }
                        self.addSubview(body)
                        self.detailsBodies[d.index] = body
                    }
                    body.mediaContentConfig = self.mediaContentConfig
                    body.context = self.context
                    body.buttonTapped = { [weak self] button in self?.buttonTapped?(button) }
                    body.frame = CGRect(
                        x: d.frame.minX,
                        y: d.frame.minY + d.titleFrame.maxY,
                        width: d.frame.width,
                        height: inner.contentSize.height
                    )
                    body.update(layout: inner, theme: theme)
                } else if let existing = self.detailsBodies[d.index] {
                    existing.removeFromSuperview()
                    self.detailsBodies.removeValue(forKey: d.index)
                }
            }
        }
        for (index, view) in self.detailsHeaders where !activeDetails.contains(index) {
            view.removeFromSuperview()
            self.detailsHeaders.removeValue(forKey: index)
        }
        for (index, view) in self.detailsBodies where !activeDetails.contains(index) {
            view.removeFromSuperview()
            self.detailsBodies.removeValue(forKey: index)
        }

        self.reconcileMediaViews(layout: layout)
        self.reconcileSlideshows(layout: layout)
        self.reconcileThinkingShimmers(layout: layout, theme: theme)

        self.reconcileSpoilerInks(layout: layout, theme: theme)
        self.reconcileInlineEmoji(layout: layout, theme: theme)
        self.reconcileLinkTooltips(layout: layout)
    }

    private func reconcileLinkTooltips(layout: InstantPageV2Layout) {
        self.removeAllToolTips()
        let rects = self.collectHiddenLinkRects(layout: layout, originInView: .zero)
            + self.collectButtonTooltipRects(layout: layout, originInView: .zero)
        for rect in rects {
            self.addToolTip(rect, owner: self, userData: nil)
        }
    }

    /// Rects of every button pill whose action opens a URL — registered as tooltip zones so hovering a
    /// pill reveals its destination before a click. Mirrors `findInteractiveTarget`'s geometry (row
    /// pills, inline pills in text / code / details titles, and both recursively inside tables).
    private func collectButtonTooltipRects(layout: InstantPageV2Layout, originInView: CGPoint, clipRect: NSRect? = nil) -> [NSRect] {
        var result: [NSRect] = []
        func appendTextButtons(_ textItem: InstantPageTextItem, textOriginInView: CGPoint) {
            guard textItem.hasButtons else { return }
            for line in textItem.lines where !line.buttonItems.isEmpty {
                let lineFrame = textItem.alignedLineFrame(line)
                for buttonItem in line.buttonItems
                where InstantPageV2View.buttonTooltipURL(buttonItem.attachment.button.action) != nil {
                    let frame = buttonItem.frame
                        .offsetBy(dx: lineFrame.minX + textOriginInView.x, dy: textOriginInView.y)
                    if let clipRect {
                        let clipped = frame.intersection(clipRect)
                        if !clipped.isNull { result.append(clipped) }
                    } else {
                        result.append(frame)
                    }
                }
            }
        }
        for item in layout.items {
            switch item {
            case let .buttonRow(row):
                for entry in row.buttons
                where InstantPageV2View.buttonTooltipURL(entry.attachment.button.action) != nil {
                    result.append(entry.frame.offsetBy(dx: originInView.x + row.frame.minX,
                                                       dy: originInView.y + row.frame.minY))
                }
            case let .text(t):
                appendTextButtons(t.textItem, textOriginInView: CGPoint(x: originInView.x + t.frame.minX,
                                                                        y: originInView.y + t.frame.minY))
            case let .codeBlock(b):
                appendTextButtons(b.textItem, textOriginInView: CGPoint(
                    x: originInView.x + b.frame.minX + b.textItem.frame.minX,
                    y: originInView.y + b.frame.minY + b.textItem.frame.minY
                ))
            case let .details(d):
                appendTextButtons(d.titleTextItem, textOriginInView: CGPoint(x: originInView.x + d.frame.minX,
                                                                             y: originInView.y + d.frame.minY))
            case let .table(table):
                let scrollX = clipRect == nil ? self.scrollOffset(forTopLevel: table) : 0
                let tableMinX = table.frame.minX - scrollX
                let tableViewport = NSRect(
                    x: originInView.x + table.frame.minX,
                    y: originInView.y + table.frame.minY,
                    width: table.frame.width,
                    height: table.frame.height
                )
                let tableClip = clipRect.map { $0.intersection(tableViewport) } ?? tableViewport
                if let titleLayout = table.titleSubLayout, let titleFrame = table.titleFrame {
                    result.append(contentsOf: collectButtonTooltipRects(
                        layout: titleLayout,
                        originInView: CGPoint(x: originInView.x + table.frame.minX + titleFrame.minX,
                                              y: originInView.y + table.frame.minY + titleFrame.minY),
                        clipRect: tableClip
                    ))
                }
                let gridOffsetY: CGFloat = table.titleFrame?.height ?? 0
                for cell in table.cells {
                    guard let sub = cell.subLayout else { continue }
                    result.append(contentsOf: collectButtonTooltipRects(
                        layout: sub,
                        originInView: CGPoint(x: originInView.x + tableMinX + cell.frame.minX,
                                              y: originInView.y + table.frame.minY + cell.frame.minY + gridOffsetY),
                        clipRect: tableClip
                    ))
                }
            default:
                break
            }
        }
        return result
    }

    private func collectHiddenLinkRects(layout: InstantPageV2Layout, originInView: CGPoint, clipRect: NSRect? = nil) -> [NSRect] {
        var result: [NSRect] = []
        for item in layout.items {
            switch item {
            case let .text(textItem):
                let textOrigin = CGPoint(x: originInView.x + textItem.frame.minX,
                                         y: originInView.y + textItem.frame.minY)
                self.appendHiddenLinkRects(textItem: textItem.textItem, textOriginInView: textOrigin, clipRect: clipRect, into: &result)
            case let .codeBlock(block):
                let textOrigin = CGPoint(
                    x: originInView.x + block.frame.minX + block.textItem.frame.minX,
                    y: originInView.y + block.frame.minY + block.textItem.frame.minY
                )
                self.appendHiddenLinkRects(textItem: block.textItem, textOriginInView: textOrigin, clipRect: clipRect, into: &result)
            case let .details(d):
                let titleOrigin = CGPoint(x: originInView.x + d.frame.minX,
                                          y: originInView.y + d.frame.minY)
                self.appendHiddenLinkRects(textItem: d.titleTextItem, textOriginInView: titleOrigin, clipRect: clipRect, into: &result)
            case let .table(table):
                let scrollX = clipRect == nil ? self.scrollOffset(forTopLevel: table) : 0
                let tableMinX = table.frame.minX - scrollX
                let tableViewport = NSRect(
                    x: originInView.x + table.frame.minX,
                    y: originInView.y + table.frame.minY,
                    width: table.frame.width,
                    height: table.frame.height
                )
                let tableClip = clipRect.map { $0.intersection(tableViewport) } ?? tableViewport
                if let titleLayout = table.titleSubLayout, let titleFrame = table.titleFrame {
                    let titleOrigin = CGPoint(
                        x: originInView.x + table.frame.minX + titleFrame.minX,
                        y: originInView.y + table.frame.minY + titleFrame.minY
                    )
                    result.append(contentsOf: collectHiddenLinkRects(layout: titleLayout, originInView: titleOrigin, clipRect: tableClip))
                }
                let gridOffsetY: CGFloat = table.titleFrame?.height ?? 0
                for cell in table.cells {
                    guard let sub = cell.subLayout else { continue }
                    let cellOrigin = CGPoint(
                        x: originInView.x + tableMinX + cell.frame.minX,
                        y: originInView.y + table.frame.minY + cell.frame.minY + gridOffsetY
                    )
                    result.append(contentsOf: collectHiddenLinkRects(layout: sub, originInView: cellOrigin, clipRect: tableClip))
                }
            default:
                break
            }
        }
        return result
    }

    /// Handles a `#name` tap as an in-page anchor. Returns false when `name` isn't an anchor in this
    /// layout (e.g. it's a `#hashtag`), so the caller can fall through to normal link handling.
    @discardableResult
    private func handleAnchorTap(name: String, at point: NSPoint) -> Bool {
        guard let layout = self.currentLayout else { return false }
        // Prefer jumping to the target section: scroll it into view (via the row) and flash it.
        if let targetRect = self.anchorTargetRect(named: name, in: layout, origin: .zero) {
            self.flashAnchorHighlight(rect: targetRect)
            self.anchorReveal?(targetRect)
            return true
        }
        // Fallback (target not locatable, e.g. inside a collapsed details): show its text as a tooltip.
        guard let target = self.findAnchor(named: name, in: layout) else { return false }
        let snippet = target.attributedString.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !snippet.isEmpty else { return false }
        let anchorRect: NSRect
        if let hit = self.hitTextItem(at: point) {
            anchorRect = NSRect(x: point.x, y: hit.textOriginInView.y + hit.line.frame.minY,
                                width: 0, height: hit.line.frame.height)
        } else {
            anchorRect = NSRect(x: point.x, y: point.y, width: 0, height: 0)
        }
        tooltip(for: self, text: snippet, rect: anchorRect)
        return true
    }

    /// The frame (in this view's coordinates) of the text item carrying `name`, searched top-level →
    /// expanded details bodies → table cells. nil if absent or inside a collapsed details.
    private func anchorTargetRect(named name: String, in layout: InstantPageV2Layout, origin: CGPoint) -> CGRect? {
        for (i, item) in layout.items.enumerated() {
            switch item {
            case let .anchor(a):
                // A standalone anchor block is a zero-height marker before a section — scroll/flash the
                // block it precedes (the next item), or the marker's own position if it's last.
                if a.name == name {
                    if i + 1 < layout.items.count {
                        return layout.items[i + 1].frame.offsetBy(dx: origin.x, dy: origin.y)
                    }
                    return CGRect(x: origin.x, y: origin.y + a.frame.minY, width: layout.contentSize.width, height: max(a.frame.height, 24.0))
                }
            case let .text(t):
                if t.textItem.anchors[name] != nil { return t.frame.offsetBy(dx: origin.x, dy: origin.y) }
            case let .codeBlock(b):
                if b.textItem.anchors[name] != nil { return b.frame.offsetBy(dx: origin.x, dy: origin.y) }
            case let .details(d):
                if d.titleTextItem.anchors[name] != nil {
                    return d.titleFrame.offsetBy(dx: origin.x + d.frame.minX, dy: origin.y + d.frame.minY)
                }
                if d.isExpanded, let inner = d.innerLayout {
                    let bodyOrigin = CGPoint(x: origin.x + d.frame.minX, y: origin.y + d.frame.minY + d.titleFrame.maxY)
                    if let r = self.anchorTargetRect(named: name, in: inner, origin: bodyOrigin) { return r }
                }
            case let .table(table):
                let tableMinX = table.frame.minX - self.scrollOffset(forTopLevel: table)
                if let titleLayout = table.titleSubLayout, let titleFrame = table.titleFrame {
                    let titleOrigin = CGPoint(x: origin.x + table.frame.minX + titleFrame.minX, y: origin.y + table.frame.minY + titleFrame.minY)
                    if let r = self.anchorTargetRect(named: name, in: titleLayout, origin: titleOrigin) { return r }
                }
                let gridOffsetY: CGFloat = table.titleFrame?.height ?? 0
                for cell in table.cells {
                    guard let sub = cell.subLayout else { continue }
                    let cellOrigin = CGPoint(x: origin.x + tableMinX + cell.frame.minX, y: origin.y + table.frame.minY + cell.frame.minY + gridOffsetY)
                    if let r = self.anchorTargetRect(named: name, in: sub, origin: cellOrigin) { return r }
                }
            default:
                break
            }
        }
        return nil
    }

    public func clearQuoteHighlight() {
        self.quoteHighlightLayer?.removeFromSuperlayer()
        self.quoteHighlightLayer = nil
    }

    @discardableResult
    public func highlightQuote(text: String, color: NSColor, range: NSRange? = nil) -> Bool {
        var matches = self.quoteHighlightRects(text: text, range: range)
        guard !matches.isEmpty else { return false }
        if let layout = self.currentLayout {
            var tableIndex = 0
            for item in layout.items {
                guard case let .table(table) = item else { continue }
                let cellRects = matches.filter {
                    $0.cell?.tableOriginX == table.frame.minX && $0.cell?.tableOriginY == table.frame.minY
                }.map { $0.rect }
                if let first = cellRects.first {
                    let target = cellRects.dropFirst().reduce(first) { $0.union($1) }
                    if target.minX < table.frame.minX || target.maxX > table.frame.maxX {
                        let offset = self.scrollOffset(forTopLevel: table) + target.midX - table.frame.midX
                        _ = self.setTableScrollOffset(offset, at: tableIndex)
                    }
                }
                tableIndex += 1
            }
            matches = self.quoteHighlightRects(text: text, range: range)
        }
        self.clearQuoteHighlight()
        let highlight = SimpleLayer()
        highlight.frame = self.bounds
        highlight.opacity = 0.5
        for match in matches {
            let shape = SimpleLayer()
            shape.frame = match.rect
            shape.backgroundColor = color.cgColor
            shape.cornerRadius = 2
            highlight.addSublayer(shape)
        }
        self.layer?.addSublayer(highlight)
        self.quoteHighlightLayer = highlight
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self, weak highlight] in
            guard let self, let highlight, self.quoteHighlightLayer === highlight else { return }
            performSublayerRemoval(highlight, animated: true)
            self.quoteHighlightLayer = nil
        }
        if let first = matches.first {
            let target = matches.dropFirst().reduce(first.rect) { $0.union($1.rect) }
            self.anchorReveal?(target)
        }
        return true
    }

    private func quoteHighlightRects(text: String, range: NSRange?) -> [(rect: CGRect, cell: CellContext?)] {
        guard let layout = self.currentLayout else { return [] }
        var entities: [LogicalEntity] = []
        self.collectEntities(layout: layout, originInView: .zero, includeDetails: true, into: &entities)
        var blocks: [NSAttributedString] = []
        var indices: [ObjectIdentifier: Int] = [:]
        for entity in entities {
            let id: ObjectIdentifier
            let attributedString: NSAttributedString
            switch entity.kind {
            case let .text(item, _):
                id = ObjectIdentifier(item)
                attributedString = item.attributedString
            case let .formula(item):
                id = ObjectIdentifier(item.attachment)
                attributedString = NSAttributedString(string: item.attachment.latex)
            }
            if indices[id] == nil {
                indices[id] = blocks.count
                blocks.append(attributedString)
            }
        }
        let ranges = instantPageQuoteRanges(in: blocks, text: text, range: range)
        var rects: [(rect: CGRect, cell: CellContext?)] = []
        for entity in entities {
            switch entity.kind {
            case let .text(item, line):
                guard let index = indices[ObjectIdentifier(item)], let selected = ranges[index] else { continue }
                let intersection = NSIntersectionRange(line.range, selected)
                guard intersection.length > 0 else { continue }
                let start = CTLineGetOffsetForStringIndex(line.line, intersection.location, nil)
                let end = CTLineGetOffsetForStringIndex(line.line, NSMaxRange(intersection), nil)
                let rect = CGRect(x: entity.frameInView.minX + min(start, end), y: entity.frameInView.minY - 2, width: abs(end - start), height: entity.frameInView.height + 6)
                if rect.width > 0 {
                    rects.append((rect, entity.cellContext))
                }
            case let .formula(item):
                guard let index = indices[ObjectIdentifier(item.attachment)], ranges[index] != nil else { continue }
                rects.append((entity.frameInView, entity.cellContext))
            }
        }
        return rects
    }

    private func flashAnchorHighlight(rect: CGRect) {
        guard rect.height > 0 else { return }
        let color = self.currentTheme?.linkColor ?? NSColor.accent
        let frame: CGRect
        let cornerRadius: CGFloat
        if self.contentBleed > 0 {
            // Bubble mode: span the full bubble width (edge to edge, like bled media), square corners.
            frame = CGRect(x: -self.contentBleed, y: rect.minY - 2, width: self.bounds.width + self.contentBleed * 2, height: rect.height + 4)
            cornerRadius = 0
        } else {
            frame = rect.insetBy(dx: -4, dy: -2)
            cornerRadius = 6
        }
        let highlight = View(frame: frame)
        highlight.layer?.cornerRadius = cornerRadius
        highlight.backgroundColor = color.withAlphaComponent(0.25)
        highlight.userInteractionEnabled = false
        self.addSubview(highlight)
        highlight.layer?.animateAlpha(from: 1.0, to: 0.0, duration: 2.5, timingFunction: .easeOut, removeOnCompletion: false, completion: { [weak highlight] _ in
            highlight?.removeFromSuperview()
        })
    }

    private func findAnchor(named name: String, in layout: InstantPageV2Layout) -> InstantPageTextItem? {
        for item in layout.items {
            switch item {
            case let .text(textItem):
                if textItem.textItem.anchors[name] != nil { return textItem.textItem }
            case let .codeBlock(block):
                if block.textItem.anchors[name] != nil { return block.textItem }
            case let .details(d):
                if d.titleTextItem.anchors[name] != nil { return d.titleTextItem }
                if let inner = d.innerLayout, let hit = findAnchor(named: name, in: inner) { return hit }
            case let .table(table):
                if let title = table.titleSubLayout, let hit = findAnchor(named: name, in: title) { return hit }
                for cell in table.cells {
                    if let sub = cell.subLayout, let hit = findAnchor(named: name, in: sub) { return hit }
                }
            default:
                continue
            }
        }
        return nil
    }

    private func isLinkHidden(at point: NSPoint) -> Bool {
        guard let layout = self.currentLayout else { return false }
        let rects = self.collectHiddenLinkRects(layout: layout, originInView: .zero)
        return rects.contains(where: { $0.contains(point) })
    }

    private func appendHiddenLinkRects(textItem: InstantPageTextItem, textOriginInView: CGPoint, clipRect: NSRect?, into result: inout [NSRect]) {
        let attr = textItem.attributedString
        for line in textItem.lines {
            attr.enumerateAttribute(.URL, in: line.range, options: []) { value, range, _ in
                guard let urlItem = value as? InstantPageUrlItem else { return }
                // Anchors and peer mentions intentionally display text unrelated to their URL — they
                // aren't "hidden" links and shouldn't trigger the open-link confirmation.
                if urlItem.url.hasPrefix("#") || urlItem.url.hasPrefix("tg://user?id=") || urlItem.url.hasPrefix("tel:") {
                    return
                }
                let displayed = (attr.string as NSString).substring(with: range)
                if displayed == urlItem.url {
                    return
                }
                let lowerX = floor(CTLineGetOffsetForStringIndex(line.line, range.location, nil))
                let upperX = ceil(CTLineGetOffsetForStringIndex(line.line, range.location + range.length, nil))
                let minX = min(lowerX, upperX)
                let width = abs(upperX - lowerX)
                var rect = NSRect(
                    x: textOriginInView.x + textItem.alignedLineFrame(line).minX + minX,
                    y: textOriginInView.y + line.frame.minY,
                    width: width,
                    height: line.frame.height
                )
                if let clipRect {
                    rect = rect.intersection(clipRect)
                }
                guard !rect.isNull, !rect.isEmpty else { return }
                result.append(rect)
            }
        }
    }

    private func reconcileInlineEmoji(layout: InstantPageV2Layout, theme: InstantPageTheme) {
        guard let context = self.context else {
            for (_, data) in self.inlineStickerItemViews {
                data.layer.removeFromSuperlayer()
            }
            self.inlineStickerItemViews.removeAll()
            for (_, container) in self.tableEmojiContainers {
                container.removeFromSuperview()
            }
            self.tableEmojiContainers.removeAll()
            return
        }

        self.emojiContainer.frame = self.bounds
        self.isLite = context.isLite(.emoji)

        var validIds: Set<InlineStickerItemLayer.Key> = []
        var activeTableContainers: Set<Int> = []
        var topLevelTableIndex = 0
        var index: Int = 0
        let defaultColor = theme.textCategories.paragraph.color
        self.appendInlineEmojiLayers(
            layout: layout,
            originInView: .zero,
            tableOwner: nil,
            tableRevealTopLevelIndex: nil,
            tableRevealCellIndex: nil,
            defaultColor: defaultColor,
            context: context,
            validIds: &validIds,
            activeTableContainers: &activeTableContainers,
            topLevelTableIndex: &topLevelTableIndex,
            usesTopLevelReveal: true,
            index: &index,
            theme: theme
        )

        var removeKeys: [InlineStickerItemLayer.Key] = []
        for (key, data) in self.inlineStickerItemViews {
            if !validIds.contains(key) {
                removeKeys.append(key)
                data.layer.removeFromSuperlayer()
            }
        }
        for key in removeKeys {
            self.inlineStickerItemViews.removeValue(forKey: key)
        }
        for (tableIndex, container) in self.tableEmojiContainers where !activeTableContainers.contains(tableIndex) {
            container.removeFromSuperview()
            self.tableEmojiContainers.removeValue(forKey: tableIndex)
        }
        self.updateTableEmojiRevealMasks(layout: layout)
        self.updateInlineEmojiReveal(animated: false)
    }

    private func tableEmojiContainer(at index: Int, frame: CGRect) -> View {
        let container: View
        if let current = self.tableEmojiContainers[index] {
            container = current
        } else {
            container = View(frame: frame)
            container.userInteractionEnabled = false
            container.isEventLess = true
            container.layer?.masksToBounds = true
            container.layerContentsRedrawPolicy = .never
            self.emojiContainer.addSubview(container)
            self.tableEmojiContainers[index] = container
        }
        container.frame = frame
        return container
    }

    private func appendInlineEmojiLayers(
        layout: InstantPageV2Layout,
        originInView: CGPoint,
        tableOwner: View?,
        tableRevealTopLevelIndex: Int?,
        tableRevealCellIndex: Int?,
        defaultColor: NSColor,
        context: any AccountContextProtocol,
        validIds: inout Set<InlineStickerItemLayer.Key>,
        activeTableContainers: inout Set<Int>,
        topLevelTableIndex: inout Int,
        usesTopLevelReveal: Bool,
        index: inout Int,
        theme: InstantPageTheme
    ) {
        for (itemIndex, item) in layout.items.enumerated() {
            let revealKey: RevealTextKey?
            if usesTopLevelReveal {
                revealKey = RevealTextKey(topLevelIndex: itemIndex, tableCellIndex: nil, subitemIndex: nil)
            } else if let tableRevealTopLevelIndex {
                revealKey = RevealTextKey(topLevelIndex: tableRevealTopLevelIndex, tableCellIndex: tableRevealCellIndex, subitemIndex: itemIndex)
            } else {
                revealKey = nil
            }
            switch item {
            case let .text(textItem):
                let textOrigin = CGPoint(x: originInView.x + textItem.frame.minX,
                                         y: originInView.y + textItem.frame.minY)
                let thinkingHost = usesTopLevelReveal && textItem.isThinking
                    ? self.thinkingViewsByItemIndex[itemIndex]
                    : nil
                self.placeEmojiLayers(
                    textItem: textItem.textItem,
                    textOriginInView: textOrigin,
                    owner: thinkingHost?.emojiContainerView ?? tableOwner,
                    defaultColor: defaultColor,
                    context: context,
                    revealKey: revealKey,
                    revealWithThinkingHost: thinkingHost != nil,
                    validIds: &validIds,
                    index: &index,
                    theme: theme
                )
            case let .codeBlock(block):
                let textOrigin = CGPoint(
                    x: originInView.x + block.frame.minX + block.textItem.frame.minX,
                    y: originInView.y + block.frame.minY + block.textItem.frame.minY
                )
                self.placeEmojiLayers(textItem: block.textItem, textOriginInView: textOrigin, owner: tableOwner, defaultColor: defaultColor, context: context, revealKey: revealKey, revealWithThinkingHost: false, validIds: &validIds, index: &index, theme: theme)
            case let .details(d):
                let titleOrigin = CGPoint(x: originInView.x + d.frame.minX,
                                          y: originInView.y + d.frame.minY)
                self.placeEmojiLayers(textItem: d.titleTextItem, textOriginInView: titleOrigin, owner: tableOwner, defaultColor: defaultColor, context: context, revealKey: revealKey, revealWithThinkingHost: false, validIds: &validIds, index: &index, theme: theme)
            case let .buttonRow(row):
                // Block pills draw their labels through the same path as inline ones, so their emoji
                // need layers for the same reason — the row is not a text item and has no run scan.
                for entry in row.buttons {
                    let labelColor = instantPageButtonColors(entry.attachment, theme: theme, isInline: false, isDisabled: false).label
                    let emojiAlpha: CGFloat = entry.attachment.isEnabled ? 1.0 : instantPageButtonDisabledAlpha
                    // The block pill is stretched to the column, so the label origin has to come from
                    // the drawn frame, not from `attachment.size`.
                    let pillFrame = entry.frame.offsetBy(
                        dx: originInView.x + row.frame.minX,
                        dy: originInView.y + row.frame.minY
                    )
                    let labelOrigin = instantPageButtonLabelOrigin(attachment: entry.attachment, frame: pillFrame)
                    for emojiItem in entry.attachment.labelEmojiItems {
                        self.placeEmojiLayer(
                            baseRect: emojiItem.frame.offsetBy(dx: labelOrigin.x, dy: labelOrigin.y),
                            emoji: emojiItem.emoji,
                            itemTextColor: labelColor,
                            defaultColor: defaultColor,
                            revealedAlpha: emojiAlpha,
                            characterIndex: 0,
                            owner: tableOwner,
                            context: context,
                            revealKey: nil,
                            revealWithThinkingHost: false,
                            validIds: &validIds,
                            index: &index
                        )
                    }
                }
            case let .table(table):
                let owner: View
                let scrollX: CGFloat
                if let tableOwner {
                    owner = tableOwner
                    scrollX = 0
                } else {
                    let tableIndex = topLevelTableIndex
                    topLevelTableIndex += 1
                    activeTableContainers.insert(tableIndex)
                    owner = self.tableEmojiContainer(
                        at: tableIndex,
                        frame: table.frame.offsetBy(dx: originInView.x, dy: originInView.y)
                    )
                    scrollX = self.scrollOffset(forTopLevel: table)
                }
                let tableMinX = table.frame.minX - scrollX
                if let titleLayout = table.titleSubLayout, let titleFrame = table.titleFrame {
                    let titleOrigin = CGPoint(
                        x: originInView.x + table.frame.minX + titleFrame.minX,
                        y: originInView.y + table.frame.minY + titleFrame.minY
                    )
                    self.appendInlineEmojiLayers(
                        layout: titleLayout,
                        originInView: titleOrigin,
                        tableOwner: owner,
                        tableRevealTopLevelIndex: revealKey?.topLevelIndex,
                        tableRevealCellIndex: -1,
                        defaultColor: defaultColor,
                        context: context,
                        validIds: &validIds,
                        activeTableContainers: &activeTableContainers,
                        topLevelTableIndex: &topLevelTableIndex,
                        usesTopLevelReveal: false,
                        index: &index,
                        theme: theme
                    )
                }
                let gridOffsetY: CGFloat = table.titleFrame?.height ?? 0
                for (cellIndex, cell) in table.cells.enumerated() {
                    guard let sub = cell.subLayout else { continue }
                    let cellOrigin = CGPoint(
                        x: originInView.x + tableMinX + cell.frame.minX,
                        y: originInView.y + table.frame.minY + cell.frame.minY + gridOffsetY
                    )
                    self.appendInlineEmojiLayers(
                        layout: sub,
                        originInView: cellOrigin,
                        tableOwner: owner,
                        tableRevealTopLevelIndex: revealKey?.topLevelIndex,
                        tableRevealCellIndex: cellIndex,
                        defaultColor: defaultColor,
                        context: context,
                        validIds: &validIds,
                        activeTableContainers: &activeTableContainers,
                        topLevelTableIndex: &topLevelTableIndex,
                        usesTopLevelReveal: false,
                        index: &index,
                        theme: theme
                    )
                }
            default:
                break
            }
        }
    }

    private func placeEmojiLayers(textItem: InstantPageTextItem, textOriginInView: CGPoint, owner: View?, defaultColor: NSColor, context: any AccountContextProtocol, revealKey: RevealTextKey?, revealWithThinkingHost: Bool, validIds: inout Set<InlineStickerItemLayer.Key>, index: inout Int, theme: InstantPageTheme) {
        for line in textItem.lines {
            var entries: [(rect: NSRect, emoji: ChatTextCustomEmojiAttribute, itemTextColor: NSColor?, alpha: CGFloat, characterIndex: Int)] = line.emojiItems.map { emojiItem in
                let rect = NSRect(
                    x: textOriginInView.x + textItem.alignedLineFrame(line).minX + emojiItem.frame.minX,
                    y: textOriginInView.y + emojiItem.frame.minY,
                    width: emojiItem.frame.width,
                    height: emojiItem.frame.height
                )
                return (rect: rect, emoji: emojiItem.emoji, itemTextColor: emojiItem.textColor, alpha: 1.0, characterIndex: emojiItem.range.location)
            }

            // A pill draws its own label, so the paragraph's run scan never sees the label's emoji.
            // A monochrome emoji is tinted, so it takes the pill's label colour, not the paragraph's
            // — resolved undimmed, because a disabled pill fades its emoji by opacity instead (which
            // is the only thing a full-colour emoji responds to). Reveal follows the pill's own
            // character, so the emoji appears with it rather than ahead of it.
            for buttonItem in line.buttonItems {
                let labelColor = instantPageButtonColors(
                    buttonItem.attachment,
                    theme: theme,
                    isInline: true,
                    isDisabled: false
                ).label
                let alpha: CGFloat = buttonItem.attachment.isEnabled ? 1.0 : instantPageButtonDisabledAlpha
                let labelOrigin = instantPageButtonLabelOrigin(attachment: buttonItem.attachment, frame: buttonItem.frame)
                for emojiItem in buttonItem.attachment.labelEmojiItems {
                    let rect = emojiItem.frame.offsetBy(
                        dx: textOriginInView.x + labelOrigin.x,
                        dy: textOriginInView.y + labelOrigin.y
                    )
                    entries.append((rect: rect, emoji: emojiItem.emoji, itemTextColor: labelColor, alpha: alpha, characterIndex: buttonItem.range.location))
                }
            }

            for entry in entries {
                self.placeEmojiLayer(
                    baseRect: entry.rect,
                    emoji: entry.emoji,
                    itemTextColor: entry.itemTextColor,
                    defaultColor: defaultColor,
                    revealedAlpha: entry.alpha,
                    characterIndex: entry.characterIndex,
                    owner: owner,
                    context: context,
                    revealKey: revealKey,
                    revealWithThinkingHost: revealWithThinkingHost,
                    validIds: &validIds,
                    index: &index
                )
            }
        }
    }

    private func placeEmojiLayer(baseRect: NSRect, emoji: ChatTextCustomEmojiAttribute, itemTextColor: NSColor?, defaultColor: NSColor, revealedAlpha: CGFloat, characterIndex: Int, owner: View?, context: any AccountContextProtocol, revealKey: RevealTextKey?, revealWithThinkingHost: Bool, validIds: inout Set<InlineStickerItemLayer.Key>, index: inout Int) {
        let layerOwner = owner ?? self.emojiContainer
        let rect = self.convert(baseRect, to: layerOwner)
        let textColor = emoji.color ?? itemTextColor ?? defaultColor
        let key = InlineStickerItemLayer.Key(id: emoji.fileId, index: index, color: textColor)
        validIds.insert(key)
        index += 1

        let data: InlineEmojiLayerData
        if let existing = self.inlineStickerItemViews[key], existing.layer.frame.size == rect.size, existing.layer.textColor == textColor {
            data = existing
        } else {
            self.inlineStickerItemViews[key]?.layer.removeFromSuperlayer()
            let layer = InlineStickerItemLayer(
                account: context.account,
                inlinePacksContext: context.inlinePacksContext,
                emoji: emoji,
                size: rect.size,
                playPolicy: .loop,
                getColors: { file in
                    guard file.isCustomTemplateEmoji || emoji.color != nil else {
                        return []
                    }
                    return [LottieColor(keyPath: "", color: textColor)]
                },
                textColor: textColor
            )
            layer.opacity = 0.0
            data = InlineEmojiLayerData(
                layer: layer,
                revealKey: revealKey,
                characterIndex: characterIndex,
                revealWithThinkingHost: revealWithThinkingHost
            )
            self.inlineStickerItemViews[key] = data
        }
        data.revealKey = revealKey
        data.characterIndex = characterIndex
        data.revealWithThinkingHost = revealWithThinkingHost
        data.revealedAlpha = revealedAlpha
        let layer = data.layer
        if layer.superview !== layerOwner || layer.superlayer !== layerOwner.layer {
            layer.removeFromSuperlayer()
            layer.superview = layerOwner
            layerOwner.layer?.addSublayer(layer)
        }
        layer.frame = rect
        if data.isRevealed {
            layer.opacity = Float(revealedAlpha)
        }
    }

    private func updateInlineEmojiReveal(animated: Bool) {
        for (_, data) in self.inlineStickerItemViews {
            let isRevealed: Bool
            if data.revealWithThinkingHost {
                // The thinking host fades and shimmers its whole subtree as one unit.
                isRevealed = true
            } else if let revealKey = data.revealKey, let state = self.revealTextStates[revealKey] {
                isRevealed = data.characterIndex < state.targetCharacterCount
            } else {
                isRevealed = true
            }
            guard data.isRevealed != isRevealed else {
                continue
            }
            data.isRevealed = isRevealed
            if isRevealed {
                data.layer.opacity = Float(data.revealedAlpha)
                if animated && !data.revealWithThinkingHost {
                    data.layer.animateAlpha(from: 0.0, to: data.revealedAlpha, duration: 0.2)
                    data.layer.animateScale(from: 0.1, to: 1.0, duration: 0.2)
                }
            } else {
                data.layer.opacity = 0.0
            }
        }
        self.updateInlineEmojiPlayback()
    }

    @objc private func updateInlineEmojiPlayback() {
        let inWindow = (self.window?.isKeyWindow ?? false) && !self.isLite
        let visible = self.visibleRect
        for (_, data) in self.inlineStickerItemViews {
            let layer = data.layer
            guard let owner = layer.superview else {
                layer.isPlayable = false
                continue
            }
            let visibleInOwner = owner === self.emojiContainer || NSIntersectsRect(layer.frame, owner.bounds)
            let frameInView = owner.convert(layer.frame, to: self)
            let isPlayable = inWindow && data.isRevealed && visibleInOwner && NSIntersectsRect(frameInView, visible)
            layer.isPlayable = isPlayable
            if isPlayable {
                layer.resumeIfNeeded()
            }
        }
    }

    private func reconcileSpoilerInks(layout: InstantPageV2Layout, theme: InstantPageTheme) {
        let rects: [NSRect]
        if self.spoilersRevealed {
            rects = []
        } else {
            rects = self.collectSpoilerRects(layout: layout, originInView: .zero)
        }

        while self.inkViews.count > rects.count {
            self.inkViews.removeLast().removeFromSuperview()
        }
        while self.inkViews.count < rects.count {
            let ink = InvisibleInkDustView()
            self.addSubview(ink)
            self.inkViews.append(ink)
        }

        let color = self.currentTheme?.textCategories.paragraph.color ?? theme.textCategories.paragraph.color
        for (i, rect) in rects.enumerated() {
            let ink = self.inkViews[i]
            if rect.isEmpty || rect.isNull {
                ink.isHidden = true
                continue
            }
            ink.isHidden = false
            let sizeChanged = ink.frame.size != rect.size
            ink.frame = rect
            if sizeChanged {
                let local = CGRect(origin: .zero, size: rect.size)
                ink.update(size: rect.size, color: color, textColor: color, rects: [local], wordRects: [local.insetBy(dx: 2, dy: 2)])
            }
        }
    }

    private func collectSpoilerRects(layout: InstantPageV2Layout, originInView: CGPoint, clipRect: NSRect? = nil) -> [NSRect] {
        var result: [NSRect] = []
        for item in layout.items {
            switch item {
            case let .text(textItem):
                let textOrigin = CGPoint(x: originInView.x + textItem.frame.minX,
                                         y: originInView.y + textItem.frame.minY)
                appendSpoilerRects(textItem: textItem.textItem, textOriginInView: textOrigin, clipRect: clipRect, into: &result)
            case let .codeBlock(block):
                let textOrigin = CGPoint(
                    x: originInView.x + block.frame.minX + block.textItem.frame.minX,
                    y: originInView.y + block.frame.minY + block.textItem.frame.minY
                )
                appendSpoilerRects(textItem: block.textItem, textOriginInView: textOrigin, clipRect: clipRect, into: &result)
            case let .details(d):
                let titleOrigin = CGPoint(x: originInView.x + d.frame.minX,
                                          y: originInView.y + d.frame.minY)
                appendSpoilerRects(textItem: d.titleTextItem, textOriginInView: titleOrigin, clipRect: clipRect, into: &result)
            case let .table(table):
                let scrollX = clipRect == nil ? self.scrollOffset(forTopLevel: table) : 0
                let tableMinX = table.frame.minX - scrollX
                let tableViewport = NSRect(
                    x: originInView.x + table.frame.minX,
                    y: originInView.y + table.frame.minY - 2,
                    width: table.frame.width,
                    height: table.frame.height + 4
                )
                let tableClip = clipRect.map { $0.intersection(tableViewport) } ?? tableViewport
                if let titleLayout = table.titleSubLayout, let titleFrame = table.titleFrame {
                    let titleOrigin = CGPoint(
                        x: originInView.x + table.frame.minX + titleFrame.minX,
                        y: originInView.y + table.frame.minY + titleFrame.minY
                    )
                    result.append(contentsOf: collectSpoilerRects(layout: titleLayout, originInView: titleOrigin, clipRect: tableClip))
                }
                let gridOffsetY: CGFloat = table.titleFrame?.height ?? 0
                for cell in table.cells {
                    guard let sub = cell.subLayout else { continue }
                    let cellOrigin = CGPoint(
                        x: originInView.x + tableMinX + cell.frame.minX,
                        y: originInView.y + table.frame.minY + cell.frame.minY + gridOffsetY
                    )
                    result.append(contentsOf: collectSpoilerRects(layout: sub, originInView: cellOrigin, clipRect: tableClip))
                }
            default:
                break
            }
        }
        return result
    }

    private func appendSpoilerRects(textItem: InstantPageTextItem, textOriginInView: CGPoint, clipRect: NSRect?, into result: inout [NSRect]) {
        for line in textItem.lines {
            for spoiler in line.spoilerItems {
                let rect = NSRect(
                    x: textOriginInView.x + textItem.alignedLineFrame(line).minX + spoiler.frame.minX,
                    y: textOriginInView.y + spoiler.frame.minY,
                    width: spoiler.frame.width,
                    height: spoiler.frame.height
                )
                if let clipRect = clipRect {
                    result.append(rect.intersection(clipRect))
                } else {
                    result.append(rect)
                }
            }
        }
    }

    private func propagateSpoilerReveal(layout: InstantPageV2Layout) {
        for item in layout.items {
            switch item {
            case let .text(textItem):
                textItem.textItem.isSpoilerRevealed = self.spoilersRevealed
            case let .codeBlock(block):
                block.textItem.isSpoilerRevealed = self.spoilersRevealed
            case let .details(d):
                d.titleTextItem.isSpoilerRevealed = self.spoilersRevealed
                if d.isExpanded, let inner = d.innerLayout {
                    propagateSpoilerReveal(layout: inner)
                }
            case let .table(table):
                if let titleLayout = table.titleSubLayout {
                    propagateSpoilerReveal(layout: titleLayout)
                }
                for cell in table.cells {
                    if let sub = cell.subLayout {
                        propagateSpoilerReveal(layout: sub)
                    }
                }
            default:
                break
            }
        }
    }

    @objc private func detailsClicked(_ recognizer: NSClickGestureRecognizer) {
        guard let id = recognizer.view?.identifier?.rawValue, id.hasPrefix("details-"),
              let index = Int(id.dropFirst("details-".count)),
              let header = recognizer.view as? InstantPageV2DetailsHeaderView else { return }
        header.setExpanded(!header.isExpanded, animated: true)
        self.detailsTapped?(index)
    }

    public override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        guard let layout = self.currentLayout, let theme = self.currentTheme else { return }
        self.propagateSpoilerReveal(layout: layout)
        let reveals = self.itemReveals
        for (i, item) in layout.items.enumerated() {
            let reveal: InstantPageV2ItemReveal = (reveals != nil && i < reveals!.count) ? reveals![i] : .full
            if self.isHiddenReveal(reveal) { continue }
            if self.thinkingViewsByItemIndex[i] != nil {
                continue
            }
            self.drawItem(
                item,
                in: ctx,
                theme: theme,
                reveal: reveal,
                revealKey: RevealTextKey(topLevelIndex: i, tableCellIndex: nil, subitemIndex: nil),
                revealBlockKey: RevealBlockKey(topLevelIndex: i, tableCellIndex: nil, subitemIndex: nil)
            )
        }
    }

    private func isHiddenReveal(_ reveal: InstantPageV2ItemReveal) -> Bool {
        if case .hidden = reveal { return true }
        if case let .details(_, _, isVisible) = reveal { return !isVisible }
        return false
    }

    private func drawItem(
        _ item: InstantPageV2LaidOutItem,
        in ctx: CGContext,
        theme: InstantPageTheme,
        reveal: InstantPageV2ItemReveal = .full,
        revealKey: RevealTextKey? = nil,
        revealBlockKey: RevealBlockKey? = nil
    ) {
        let blockOpacity = self.revealOpacity(for: revealBlockKey)
        guard blockOpacity > 0.0 else { return }
        ctx.saveGState()
        ctx.setAlpha(blockOpacity)
        defer { ctx.restoreGState() }
        switch item {
        case let .text(textItem):
            // `drawInTile` owns the line geometry, so inline button pills are painted there; it needs
            // the InstantPage theme to resolve their colours. Stamped here rather than at layout time so
            // a theme change takes effect without relaying out.
            if textItem.textItem.hasButtons {
                textItem.textItem.instantPageTheme = theme
            }
            let requestedCharacterCount = self.revealedCharacterCount(for: reveal, textItem: textItem.textItem)
            let canvasCharacterCount = revealKey.map {
                self.canvasCharacterLimit(for: $0, requestedCount: requestedCharacterCount)
            } ?? requestedCharacterCount
            ctx.saveGState()
            if canvasCharacterCount < textItem.textItem.attributedString.length {
                let rects = instantPageV2RevealClipRects(textItem: textItem.textItem, charCount: canvasCharacterCount)
                    .map { $0.offsetBy(dx: textItem.frame.minX, dy: textItem.frame.minY) }
                if rects.isEmpty {
                    ctx.clip(to: .zero)
                } else {
                    ctx.clip(to: rects)
                }
            }
            ctx.translateBy(
                x: textItem.frame.minX - textItem.textItem.frame.minX,
                y: textItem.frame.minY - textItem.textItem.frame.minY
            )
            textItem.textItem.drawInTile(context: ctx)
            ctx.restoreGState()

        case let .unsupported(unsupported):
            // In a bubble this draws the row only — the band itself is a hole punched through
            // the bubble behind, so there is nothing here that needs to bleed past the layer bounds.
            unsupported.layout.draw(in: ctx, rect: unsupported.frame)

        case let .codeBlock(block):
            if block.textItem.hasButtons {
                block.textItem.instantPageTheme = theme
            }
            ctx.saveGState()
            let path = CGPath(roundedRect: block.frame,
                              cornerWidth: block.cornerRadius,
                              cornerHeight: block.cornerRadius, transform: nil)
            ctx.setFillColor(block.backgroundColor.cgColor)
            ctx.addPath(path)
            ctx.fillPath()

            // The standard code block's 3pt accent bar on the leading edge (clipped to the rounding).
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.setFillColor(block.headerColor.cgColor)
            ctx.fill(CGRect(x: block.frame.minX, y: block.frame.minY, width: 3, height: block.frame.height))
            ctx.restoreGState()

            if let header = block.headerText, block.headerHeight > 0 {
                let headerRect = CGRect(
                    x: block.frame.minX,
                    y: block.frame.minY,
                    width: block.frame.width,
                    height: block.headerHeight
                )
                ctx.saveGState()
                ctx.addPath(path)
                ctx.clip()
                ctx.setFillColor(block.headerColor.withAlphaComponent(0.2).cgColor)
                ctx.fill(headerRect)
                ctx.restoreGState()

                let headerFont = NSFont.medium(.text)
                let headerAttr = NSAttributedString(string: header, attributes: [
                    .font: headerFont,
                    .foregroundColor: block.headerColor
                ])
                let line = CTLineCreateWithAttributedString(headerAttr)
                let lineBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
                ctx.saveGState()
                ctx.textMatrix = CGAffineTransform(scaleX: 1.0, y: -1.0)
                let textY = headerRect.midY + lineBounds.height / 2 - 1
                ctx.textPosition = CGPoint(x: headerRect.minX + 8, y: textY)
                CTLineDraw(line, ctx)
                ctx.restoreGState()

                if let image = NSImage(named: "Icon_CopyCode")?.precomposed(block.headerColor, flipVertical: true) {
                    let iconSize = image.backingSize
                    let iconRect = CGRect(
                        x: headerRect.maxX - iconSize.width - 6,
                        y: headerRect.minY + (headerRect.height - iconSize.height) / 2,
                        width: iconSize.width,
                        height: iconSize.height
                    )
                    ctx.draw(image, in: iconRect)
                }
            }

            ctx.translateBy(x: block.frame.minX, y: block.frame.minY)
            // Stream the code text while the block chrome (background/bar/header) stays put.
            let requestedCharacterCount = self.revealedCharacterCount(for: reveal, textItem: block.textItem)
            let canvasCharacterCount = revealKey.map {
                self.canvasCharacterLimit(for: $0, requestedCount: requestedCharacterCount)
            } ?? requestedCharacterCount
            if canvasCharacterCount < block.textItem.attributedString.length {
                let rects = instantPageV2RevealClipRects(textItem: block.textItem, charCount: canvasCharacterCount)
                    .map { $0.offsetBy(dx: block.textItem.frame.minX, dy: block.textItem.frame.minY) }
                if rects.isEmpty {
                    ctx.clip(to: .zero)
                } else {
                    ctx.clip(to: rects)
                }
            }
            block.textItem.drawInTile(context: ctx)
            ctx.restoreGState()

        case let .divider(div):
            ctx.saveGState()
            ctx.setFillColor(div.color.cgColor)
            ctx.fill(div.frame)
            ctx.restoreGState()

        case let .listMarker(marker):
            ctx.saveGState()
            switch marker.kind {
            case .bullet:
                ctx.setFillColor(marker.color.cgColor)
                ctx.fillEllipse(in: CGRect(origin: marker.frame.origin.toScreenPixel, size: marker.frame.size))
            case let .number(text):
                let fontSize = theme.textCategories.paragraph.font.size
                let font = NSFont.normal(fontSize)
                let attr = NSAttributedString(string: text, attributes: [
                    .font: font,
                    .foregroundColor: marker.color
                ])
                let line = CTLineCreateWithAttributedString(attr)
                ctx.saveGState()
                ctx.textMatrix = CGAffineTransform(scaleX: 1.0, y: -1.0)
                // Baseline-align the number with the item text (same font). The marker frame is centered on
                // the text line's mid-Y, so their shared baseline sits at midY + (ascender+descender)/2 —
                // rather than a fixed offset from the frame bottom (which floated the number off the text).
                let baselineY = marker.frame.midY + (font.ascender + font.descender) / 2.0
                ctx.textPosition = CGPoint(x: marker.frame.minX, y: baselineY)
                CTLineDraw(line, ctx)
                ctx.restoreGState()
            case let .checklist(checked, colors):
                if checked {
                    drawPollSquareSelected(
                        ctx,
                        rect: marker.frame,
                        image: TelegramThemeHooks.shared.image(.iconPollSelected),
                        backgroundColor: colors.background,
                        foregroundColor: colors.foreground,
                        flipVertical: true
                    )
                } else {
                    drawPollSquareUnselected(ctx, rect: marker.frame, borderColor: colors.border)
                }
            }
            ctx.restoreGState()

        case let .blockQuoteBar(bar):
            ctx.saveGState()
            let path = CGPath(roundedRect: bar.frame,
                              cornerWidth: bar.cornerRadius,
                              cornerHeight: bar.cornerRadius, transform: nil)
            ctx.setFillColor(bar.color.cgColor)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.restoreGState()

        case let .blockQuoteDecoration(quote):
            ctx.saveGState()
            let bgPath = CGPath(
                roundedRect: quote.frame,
                cornerWidth: quote.backgroundCornerRadius,
                cornerHeight: quote.backgroundCornerRadius,
                transform: nil
            )
            ctx.setFillColor(quote.color.withAlphaComponent(0.1).cgColor)
            ctx.addPath(bgPath)
            ctx.fillPath()

            let barFrame = CGRect(
                x: quote.rtl ? (quote.frame.maxX - quote.barWidth) : quote.frame.minX,
                y: quote.frame.minY,
                width: quote.barWidth,
                height: quote.frame.height
            )
            ctx.saveGState()
            ctx.addPath(bgPath)
            ctx.clip()
            ctx.setFillColor(quote.color.cgColor)
            ctx.fill(barFrame)
            ctx.restoreGState()

            if quote.drawsIcon, let icon = NSImage(named: "Icon_Quote")?.precomposed(flipVertical: false) {
                let iconSize = icon.backingSize
                let iconRect = CGRect(
                    x: quote.rtl ? (quote.frame.minX + 4) : (quote.frame.maxX - 4 - iconSize.width),
                    y: quote.frame.minY + 4,
                    width: iconSize.width,
                    height: iconSize.height
                )
                ctx.saveGState()
                ctx.setFillColor(quote.color.cgColor)
                ctx.translateBy(x: iconRect.midX, y: iconRect.midY)
                ctx.scaleBy(x: 1.0, y: -1.0)
                ctx.translateBy(x: -iconRect.midX, y: -iconRect.midY)
                ctx.clip(to: iconRect, mask: icon)
                ctx.fill(iconRect)
                ctx.restoreGState()
                ctx.resetClip()
            }
            ctx.restoreGState()

        case let .shape(shape):
            ctx.saveGState()
            ctx.setFillColor(shape.color.cgColor)
            switch shape.kind {
            case let .roundedRect(radius):
                let path = CGPath(roundedRect: shape.frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
                ctx.addPath(path)
                ctx.fillPath()
            case let .line(thickness):
                let _ = thickness
                ctx.fill(shape.frame)
            }
            ctx.restoreGState()

        case let .pullQuoteMark(mark):
            let imageName: NSImage.Name
            switch mark.kind {
            case .open:
                imageName = "Icon_RichText_QuoteOpen"
            case .close:
                imageName = "Icon_RichText_QuoteClose"
            }
            if let icon = NSImage(named: imageName)?.precomposed(flipVertical: false) {
                ctx.saveGState()
                ctx.setFillColor(mark.color.cgColor)
                ctx.translateBy(x: mark.frame.midX, y: mark.frame.midY)
                ctx.scaleBy(x: 1.0, y: -1.0)
                ctx.translateBy(x: -mark.frame.midX, y: -mark.frame.midY)
                ctx.clip(to: mark.frame, mask: icon)
                ctx.fill(mark.frame)
                ctx.restoreGState()
                ctx.resetClip()
            }

        case let .mediaPlaceholder(item):
            // Slideshow placeholders are covered by a hosted SliderView — don't paint the grey box.
            if !item.slideshowMedias.isEmpty { break }
            ctx.saveGState()
            let path = CGPath(roundedRect: item.frame,
                              cornerWidth: item.cornerRadius,
                              cornerHeight: item.cornerRadius, transform: nil)
            ctx.setFillColor(theme.codeBlockBackgroundColor.cgColor)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.restoreGState()

        case let .details(d):
            if d.titleTextItem.hasButtons {
                d.titleTextItem.instantPageTheme = theme
            }
            let requestedCharacterCount = self.revealedCharacterCount(for: reveal, textItem: d.titleTextItem)
            let canvasCharacterCount = revealKey.map {
                self.canvasCharacterLimit(for: $0, requestedCount: requestedCharacterCount)
            } ?? requestedCharacterCount
            ctx.saveGState()
            ctx.translateBy(x: d.frame.minX, y: d.frame.minY)
            if canvasCharacterCount < d.titleTextItem.attributedString.length {
                let rects = instantPageV2RevealClipRects(
                    textItem: d.titleTextItem,
                    charCount: canvasCharacterCount
                ).map {
                    $0.offsetBy(dx: d.titleTextItem.frame.minX, dy: d.titleTextItem.frame.minY)
                }
                if rects.isEmpty {
                    ctx.clip(to: .zero)
                } else {
                    ctx.clip(to: rects)
                }
            }
            d.titleTextItem.drawInTile(context: ctx)
            ctx.restoreGState()

        case let .table(table):
            let scrollX = self.scrollOffset(forTopLevel: table)
            let needsClip = table.isHorizontallyScrollable
            ctx.saveGState()
            let maskHeight = self.revealTableMaskHeight(for: revealBlockKey, fallback: table.frame.height)
            ctx.clip(to: CGRect(x: table.frame.minX, y: table.frame.minY, width: table.frame.width, height: maskHeight))
            if needsClip {
                // Only clip horizontally — vertical clipping at table.frame edges
                // would chop the centered 1-pt outer border stroke top/bottom.
                let clipRect = NSRect(
                    x: table.frame.minX,
                    y: table.frame.minY - 2,
                    width: table.frame.width,
                    height: table.frame.height + 4
                )
                ctx.clip(to: clipRect)
            }
            let gridOffsetY: CGFloat = table.titleFrame?.height ?? 0.0
            let tableReveal: InstantPageV2TableReveal?
            if case let .table(value) = reveal {
                tableReveal = value
            } else {
                tableReveal = nil
            }

            if let titleFrame = table.titleFrame, let titleLayout = table.titleSubLayout {
                ctx.saveGState()
                ctx.translateBy(x: table.frame.minX + titleFrame.minX, y: table.frame.minY + titleFrame.minY)
                let titleReveals = tableReveal?.title
                for (subitemIndex, sub) in titleLayout.items.enumerated() {
                    let subReveal = titleReveals.flatMap { subitemIndex < $0.count ? $0[subitemIndex] : nil } ?? .full
                    if self.isHiddenReveal(subReveal) { continue }
                    self.drawItem(
                        sub,
                        in: ctx,
                        theme: theme,
                        reveal: subReveal,
                        revealKey: RevealTextKey(topLevelIndex: revealKey?.topLevelIndex ?? 0, tableCellIndex: -1, subitemIndex: subitemIndex),
                        revealBlockKey: RevealBlockKey(topLevelIndex: revealBlockKey?.topLevelIndex ?? 0, tableCellIndex: -1, subitemIndex: subitemIndex)
                    )
                }
                ctx.restoreGState()
            }

            ctx.translateBy(x: table.frame.minX - scrollX, y: table.frame.minY)

            ctx.saveGState()
            ctx.translateBy(x: 0, y: gridOffsetY)

            let lineWidth: CGFloat = 1.0
            let drawOuterFrame: CGRect
            if needsClip {
                // Anchor the outer rounded rect to the visible viewport so its corners
                // stay on-screen; cells/internal lines scroll behind it.
                drawOuterFrame = CGRect(
                    x: scrollX + lineWidth / 2,
                    y: table.outerFrame.minY,
                    width: table.frame.width - lineWidth,
                    height: table.outerFrame.height
                )
            } else {
                drawOuterFrame = table.outerFrame
            }
            let outerPath = CGPath(
                roundedRect: drawOuterFrame,
                cornerWidth: table.outerCornerRadius,
                cornerHeight: table.outerCornerRadius,
                transform: nil
            )

            ctx.saveGState()
            ctx.addPath(outerPath)
            ctx.clip()

            for cell in table.cells {
                if let bg = cell.backgroundColor {
                    ctx.setFillColor(bg.cgColor)
                    ctx.fill(cell.frame)
                }
            }

            ctx.setFillColor(table.borderColor.cgColor)
            for line in table.horizontalLines { ctx.fill(line) }
            for line in table.verticalLines   { ctx.fill(line) }

            ctx.restoreGState()

            // The rounded path is still used above as the clip, so cell fills keep their rounded
            // corners on an unbordered striped table; only the stroke itself is gated.
            if table.bordered {
                ctx.setStrokeColor(table.borderColor.cgColor)
                ctx.setLineWidth(lineWidth)
                ctx.addPath(outerPath)
                ctx.strokePath()
            }

            for (cellIndex, cell) in table.cells.enumerated() {
                guard let sub = cell.subLayout else { continue }
                ctx.saveGState()
                ctx.translateBy(x: cell.frame.minX, y: cell.frame.minY)
                let cellReveals = tableReveal?.cells[InstantPageV2CellFrameKey(cell.frame)]
                for (subitemIndex, subItem) in sub.items.enumerated() {
                    let subReveal = cellReveals.flatMap { subitemIndex < $0.count ? $0[subitemIndex] : nil } ?? .full
                    if self.isHiddenReveal(subReveal) { continue }
                    let subitemRevealKey = revealKey.map {
                        RevealTextKey(
                            topLevelIndex: $0.topLevelIndex,
                            tableCellIndex: cellIndex,
                            subitemIndex: subitemIndex
                        )
                    }
                    let subitemBlockKey = revealBlockKey.map {
                        RevealBlockKey(
                            topLevelIndex: $0.topLevelIndex,
                            tableCellIndex: cellIndex,
                            subitemIndex: subitemIndex
                        )
                    }
                    self.drawItem(
                        subItem,
                        in: ctx,
                        theme: theme,
                        reveal: subReveal,
                        revealKey: subitemRevealKey,
                        revealBlockKey: subitemBlockKey
                    )
                }
                ctx.restoreGState()
            }

            ctx.restoreGState()
            ctx.restoreGState()

            if needsClip, let idx = self.tableIndex(forFrame: table.frame), let rects = self.tableScrollerRects(idx) {
                ctx.saveGState()
                let trackColor = table.borderColor.withAlphaComponent(0.25)
                let trackPath = CGPath(roundedRect: rects.track, cornerWidth: rects.track.height / 2, cornerHeight: rects.track.height / 2, transform: nil)
                ctx.setFillColor(trackColor.cgColor)
                ctx.addPath(trackPath)
                ctx.fillPath()
                let isDragging = self.tableScrollerDrag?.index == idx
                let thumbAlpha: CGFloat = isDragging ? 0.85 : 0.55
                let thumbColor = (theme.textCategories.paragraph.color).withAlphaComponent(thumbAlpha)
                let thumbPath = CGPath(roundedRect: rects.thumb, cornerWidth: rects.thumb.height / 2, cornerHeight: rects.thumb.height / 2, transform: nil)
                ctx.setFillColor(thumbColor.cgColor)
                ctx.addPath(thumbPath)
                ctx.fillPath()
                ctx.restoreGState()
            }

        case let .formula(formula):
            ctx.saveGState()
            if selectedFormulaIds.contains(ObjectIdentifier(formula.attachment)) {
                ctx.setFillColor(self.selectionColor.cgColor)
                ctx.fill(formula.frame)
            }
            ctx.translateBy(x: formula.frame.minX, y: formula.frame.minY)

            if formula.isScrollable {
                ctx.saveGState()
                ctx.clip(to: CGRect(origin: .zero, size: formula.frame.size))
                if let cg = formula.attachment.rendered.image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    ctx.saveGState()
                    ctx.translateBy(x: formula.imageFrame.minX, y: formula.imageFrame.maxY)
                    ctx.scaleBy(x: 1.0, y: -1.0)
                    ctx.draw(cg, in: CGRect(origin: .zero, size: formula.imageFrame.size))
                    ctx.restoreGState()
                }
                ctx.restoreGState()
            } else {
                if let cg = formula.attachment.rendered.image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    ctx.saveGState()
                    ctx.translateBy(x: formula.imageFrame.minX, y: formula.imageFrame.maxY)
                    ctx.scaleBy(x: 1.0, y: -1.0)
                    ctx.draw(cg, in: CGRect(origin: .zero, size: formula.imageFrame.size))
                    ctx.restoreGState()
                }
            }
            ctx.restoreGState()

        case let .buttonRow(row):
            for entry in row.buttons {
                instantPageDrawButton(
                    entry.attachment,
                    in: entry.frame.offsetBy(dx: row.frame.minX, dy: row.frame.minY),
                    context: ctx,
                    theme: theme,
                    isInline: false
                )
            }

        case .anchor:
            break
        case .mediaImage, .mediaVideo, .mediaMap, .mediaCoverImage:
            // Grey box doubles as a loading background. For top-level media a real
            // InstantPageMediaView (see reconcileMediaViews) is hosted as a subview on top of it;
            // for media drawn in-context (e.g. table cells, or when no context is available) the
            // box is what shows.
            if case let .mediaVideo(m) = item {
                if m.isFile {
                    break
                }
                if let file = m.media.media as? TelegramMediaFile, file.isMusicFile || file.isVoice {
                    break
                }
            }
            ctx.saveGState()
            let path = CGPath(roundedRect: item.frame, cornerWidth: 8.0, cornerHeight: 8.0, transform: nil)
            ctx.setFillColor(theme.codeBlockBackgroundColor.cgColor)
            ctx.addPath(path)
            ctx.fillPath()
            ctx.restoreGState()
        }
    }

    // MARK: - Selection

    @discardableResult
    /// Total selectable (non-whitespace) character count across the whole message — used by the copy path to
    /// tell a whole-message selection (→ carry a media ref so paste rebuilds the full content) from a partial
    /// one (→ paste only the selected Document).
    public func totalSelectableTextLength() -> Int {
        guard let layout = self.currentLayout else { return 0 }
        var entities: [LogicalEntity] = []
        collectEntities(layout: layout, originInView: .zero, into: &entities)
        var seen = Set<ObjectIdentifier>()
        var total = 0
        func countNonWhitespace(_ s: NSAttributedString) -> Int {
            s.string.reduce(0) { $1.isWhitespace ? $0 : $0 + 1 }
        }
        for entity in entities {
            switch entity.kind {
            case let .text(textItem, _):
                if seen.insert(ObjectIdentifier(textItem)).inserted {
                    total += countNonWhitespace(textItem.attributedString)
                }
            case .formula:
                total += 1
            }
        }
        return total
    }

    public func applySelection(begin: NSPoint, end: NSPoint, isStartRow: Bool, isEndRow: Bool, reversed: Bool) -> [ChatBubbleSelectionFragment] {
        guard let layout = self.currentLayout else { return [] }
        self.clearBubbleSelection()

        var entities: [LogicalEntity] = []
        collectEntities(layout: layout, originInView: .zero, into: &entities)
        if entities.isEmpty {
            self.needsDisplay = true
            return []
        }

        let startIdx = nearestEntity(forY: begin.y, in: entities)
        let endIdx   = nearestEntity(forY: end.y,   in: entities)
        let isReversed = endIdx < startIdx
        let lo = min(startIdx, endIdx)
        let hi = max(startIdx, endIdx)

        var perItemRanges: [ObjectIdentifier: NSRange] = [:]
        var perItemAttr: [ObjectIdentifier: NSAttributedString] = [:]
        var perItemCell: [ObjectIdentifier: CellContext?] = [:]
        var selectedFormulas: Set<ObjectIdentifier> = []

        enum Emission {
            case text(ObjectIdentifier)
            case formula(NSAttributedString, CellContext?)
        }
        var emissions: [Emission] = []

        for i in lo ... hi {
            let entity = entities[i]
            switch entity.kind {
            case let .text(textItem, textLine):
                let lineRange = CTLineGetStringRange(textLine.line)
                var startIdxInLine: Int
                var endIdxInLine: Int

                if startIdx == endIdx {
                    let lineLocalX1 = (begin.x - entity.textOriginInView.x) - textItem.alignedLineFrame(textLine).minX
                    let lineLocalX2 = (end.x   - entity.textOriginInView.x) - textItem.alignedLineFrame(textLine).minX
                    let a = CTLineGetStringIndexForPosition(textLine.line, NSMakePoint(lineLocalX1, 0))
                    let b = CTLineGetStringIndexForPosition(textLine.line, NSMakePoint(lineLocalX2, 0))
                    startIdxInLine = min(a, b)
                    endIdxInLine = max(a, b)
                } else if i == lo {
                    let probe = isReversed ? end : begin
                    let probeX = (probe.x - entity.textOriginInView.x) - textItem.alignedLineFrame(textLine).minX
                    startIdxInLine = CTLineGetStringIndexForPosition(textLine.line, NSMakePoint(probeX, 0))
                    endIdxInLine = lineRange.location + lineRange.length
                } else if i == hi {
                    let probe = isReversed ? begin : end
                    let probeX = (probe.x - entity.textOriginInView.x) - textItem.alignedLineFrame(textLine).minX
                    startIdxInLine = lineRange.location
                    endIdxInLine = CTLineGetStringIndexForPosition(textLine.line, NSMakePoint(probeX, 0))
                } else {
                    startIdxInLine = lineRange.location
                    endIdxInLine = lineRange.location + lineRange.length
                }

                if startIdxInLine > endIdxInLine { swap(&startIdxInLine, &endIdxInLine) }
                guard endIdxInLine > startIdxInLine else { continue }

                let id = ObjectIdentifier(textItem)
                if perItemAttr[id] == nil {
                    perItemAttr[id] = textItem.attributedString
                    perItemCell[id] = entity.cellContext
                    emissions.append(.text(id))
                }
                if let existing = perItemRanges[id] {
                    let newLo = min(existing.location, startIdxInLine)
                    let newHi = max(existing.location + existing.length, endIdxInLine)
                    perItemRanges[id] = NSMakeRange(newLo, newHi - newLo)
                } else {
                    perItemRanges[id] = NSMakeRange(startIdxInLine, endIdxInLine - startIdxInLine)
                }

            case let .formula(formulaItem):
                let id = ObjectIdentifier(formulaItem.attachment)
                guard !selectedFormulas.contains(id) else { continue }
                selectedFormulas.insert(id)
                // Keep the LaTeX as the copied text (plain paste is unchanged) but mark it so a paste into the
                // composer can rebuild it as a real formula in the editor.
                let attr = NSAttributedString(string: formulaItem.attachment.latex, attributes: [.richFormulaLatex: formulaItem.attachment.latex])
                emissions.append(.formula(attr, entity.cellContext))
            }
        }

        var seen: Set<ObjectIdentifier> = []
        applySelectRectsRecursive(in: layout, perItemRanges: perItemRanges, seen: &seen)
        self.selectedFormulaIds = selectedFormulas

        // Build a single consolidated fragment in visual order with markdown-aware joins:
        // - cells in the same table row: " | "
        // - new row in same table: "\n"
        // - between distinct paragraphs / other items: "\n\n"
        let output = NSMutableAttributedString()
        var lastCell: CellContext? = nil
        var emittedAny = false
        var quoteParts: [RichText] = []

        for emission in emissions {
            let piece: NSAttributedString?
            let cell: CellContext?
            let quotePart: RichText
            switch emission {
            case let .text(id):
                guard let range = perItemRanges[id], let attr = perItemAttr[id], range.length > 0 else { continue }
                let location = max(0, range.location)
                let length = max(0, min(range.location + range.length, attr.length) - location)
                guard length > 0 else { continue }
                let selected = attr.attributedSubstring(from: NSMakeRange(location, length))
                piece = selected
                quotePart = instantPageRichTextForSelection(selected)
                cell = perItemCell[id] ?? nil
            case let .formula(attr, ctx):
                piece = attr
                quotePart = .formula(latex: attr.string)
                cell = ctx
            }
            guard let piece else { continue }

            if emittedAny {
                let sep: String
                switch (lastCell, cell) {
                case let (prev?, cur?) where prev.tableOriginX == cur.tableOriginX && prev.tableOriginY == cur.tableOriginY:
                    sep = (prev.cellRowY == cur.cellRowY) ? " | " : "\n"
                case (.some, .some), (.some, .none), (.none, .some):
                    sep = "\n\n"
                case (.none, .none):
                    sep = "\n\n"
                }
                output.append(NSAttributedString(string: sep))
            }
            output.append(piece)
            quoteParts.append(quotePart)
            emittedAny = true
            lastCell = cell
        }

        self.needsDisplay = true
        self.setThinkingContentNeedsDisplay()
        if output.length == 0 {
            return []
        }
        return [ChatBubbleSelectionFragment(attributedString: output, range: NSMakeRange(0, output.length), index: 0, richText: quoteParts)]
    }

    public func clearBubbleSelection() {
        self.selectedRanges = []
        self.selectedFormulaIds = []
        self.hasLocalSelection = false
        if let layout = self.currentLayout {
            clearSelectRectsRecursive(in: layout)
        }
        for body in self.detailsBodies.values { body.clearBubbleSelection() }
        self.needsDisplay = true
        self.setThinkingContentNeedsDisplay()
    }

    private struct CellContext: Hashable {
        let tableOriginX: CGFloat
        let tableOriginY: CGFloat
        let cellRowY: CGFloat
    }

    private struct LogicalEntity {
        enum Kind {
            case text(InstantPageTextItem, InstantPageTextLine)
            case formula(InstantPageV2FormulaItem)
        }
        let kind: Kind
        let cellContext: CellContext?
        let textOriginInView: CGPoint
        let midYInView: CGFloat
        let frameInView: NSRect
    }

    /// Walks the V2 layout (recursing into table titles + cell sub-layouts) producing a flat
    /// list of selectable entities — every text line and every block-level formula — in visual
    /// order. Each carries its V2-view-local geometry so the selection algorithm can treat them
    /// as one continuous stream.
    private func collectEntities(layout: InstantPageV2Layout, originInView: CGPoint, cellContext: CellContext? = nil, includeDetails: Bool = false, into result: inout [LogicalEntity]) {
        for item in layout.items {
            switch item {
            case let .text(text):
                let textOrigin = CGPoint(x: originInView.x + text.frame.minX,
                                         y: originInView.y + text.frame.minY)
                for line in text.textItem.lines {
                    // Alignment-applied frame so hit-testing lines up with the DRAWN (centered/right) text.
                    let lf = text.textItem.alignedLineFrame(line)
                    let frameInView = NSRect(
                        x: textOrigin.x + lf.minX,
                        y: textOrigin.y + lf.minY,
                        width: lf.width,
                        height: lf.height
                    )
                    result.append(LogicalEntity(
                        kind: .text(text.textItem, line),
                        cellContext: cellContext,
                        textOriginInView: textOrigin,
                        midYInView: textOrigin.y + lf.midY,
                        frameInView: frameInView
                    ))
                }
            case let .codeBlock(block):
                let textOrigin = CGPoint(
                    x: originInView.x + block.frame.minX + block.textItem.frame.minX,
                    y: originInView.y + block.frame.minY + block.textItem.frame.minY
                )
                for line in block.textItem.lines {
                    let frameInView = NSRect(
                        x: textOrigin.x + line.frame.minX,
                        y: textOrigin.y + line.frame.minY,
                        width: line.frame.width,
                        height: line.frame.height
                    )
                    result.append(LogicalEntity(
                        kind: .text(block.textItem, line),
                        cellContext: cellContext,
                        textOriginInView: textOrigin,
                        midYInView: textOrigin.y + line.frame.midY,
                        frameInView: frameInView
                    ))
                }
            case let .formula(formula):
                let frameInView = NSRect(
                    x: originInView.x + formula.frame.minX,
                    y: originInView.y + formula.frame.minY,
                    width: formula.frame.width,
                    height: formula.frame.height
                )
                result.append(LogicalEntity(
                    kind: .formula(formula),
                    cellContext: cellContext,
                    textOriginInView: CGPoint(x: frameInView.minX, y: frameInView.minY),
                    midYInView: frameInView.midY,
                    frameInView: frameInView
                ))
            case let .details(details) where includeDetails:
                let titleOrigin = CGPoint(x: originInView.x + details.frame.minX + details.titleFrame.minX + details.titleTextItem.frame.minX,
                                          y: originInView.y + details.frame.minY + details.titleFrame.minY + details.titleTextItem.frame.minY)
                for line in details.titleTextItem.lines {
                    let frame = details.titleTextItem.alignedLineFrame(line).offsetBy(dx: titleOrigin.x, dy: titleOrigin.y)
                    result.append(LogicalEntity(kind: .text(details.titleTextItem, line), cellContext: cellContext, textOriginInView: titleOrigin, midYInView: frame.midY, frameInView: frame))
                }
                if details.isExpanded, let inner = details.innerLayout {
                    let bodyOrigin = CGPoint(x: originInView.x + details.frame.minX, y: originInView.y + details.frame.minY + details.titleFrame.maxY)
                    collectEntities(layout: inner, originInView: bodyOrigin, cellContext: cellContext, includeDetails: true, into: &result)
                }
            case let .table(table):
                let tableMinX = table.frame.minX - self.scrollOffset(forTopLevel: table)
                if let titleLayout = table.titleSubLayout, let titleFrame = table.titleFrame {
                    let titleOriginInView = CGPoint(
                        x: originInView.x + table.frame.minX + titleFrame.minX,
                        y: originInView.y + table.frame.minY + titleFrame.minY
                    )
                    collectEntities(layout: titleLayout, originInView: titleOriginInView, cellContext: nil, includeDetails: includeDetails, into: &result)
                }
                let gridOffsetY: CGFloat = table.titleFrame?.height ?? 0
                for cell in table.cells {
                    guard let sub = cell.subLayout else { continue }
                    let cellOriginInView = CGPoint(
                        x: originInView.x + tableMinX + cell.frame.minX,
                        y: originInView.y + table.frame.minY + cell.frame.minY + gridOffsetY
                    )
                    let nestedContext = CellContext(
                        tableOriginX: table.frame.origin.x,
                        tableOriginY: table.frame.origin.y,
                        cellRowY: cell.frame.minY
                    )
                    collectEntities(layout: sub, originInView: cellOriginInView, cellContext: nestedContext, includeDetails: includeDetails, into: &result)
                }
            default:
                break
            }
        }
    }

    private func nearestEntity(forY y: CGFloat, in entities: [LogicalEntity]) -> Int {
        var bestIndex = 0
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for (i, entity) in entities.enumerated() {
            let d = abs(entity.midYInView - y)
            if d < bestDistance {
                bestDistance = d
                bestIndex = i
            }
        }
        return bestIndex
    }

    private func clearSelectRectsRecursive(in layout: InstantPageV2Layout) {
        for item in layout.items {
            switch item {
            case let .text(text):
                for line in text.textItem.lines { line.selectRect = .zero }
            case let .codeBlock(block):
                for line in block.textItem.lines { line.selectRect = .zero }
            case let .table(table):
                if let title = table.titleSubLayout { clearSelectRectsRecursive(in: title) }
                for cell in table.cells {
                    if let sub = cell.subLayout { clearSelectRectsRecursive(in: sub) }
                }
            default:
                break
            }
        }
    }

    private func applySelectRectsRecursive(in layout: InstantPageV2Layout, perItemRanges: [ObjectIdentifier: NSRange], seen: inout Set<ObjectIdentifier>) {
        for item in layout.items {
            switch item {
            case let .text(text):
                let id = ObjectIdentifier(text.textItem)
                if !seen.contains(id) {
                    seen.insert(id)
                    if let range = perItemRanges[id] {
                        applySelectRects(to: text.textItem, range: range)
                    } else {
                        for line in text.textItem.lines { line.selectRect = .zero }
                    }
                }
            case let .codeBlock(block):
                let id = ObjectIdentifier(block.textItem)
                if !seen.contains(id) {
                    seen.insert(id)
                    if let range = perItemRanges[id] {
                        applySelectRects(to: block.textItem, range: range)
                    } else {
                        for line in block.textItem.lines { line.selectRect = .zero }
                    }
                }
            case let .table(table):
                if let title = table.titleSubLayout {
                    applySelectRectsRecursive(in: title, perItemRanges: perItemRanges, seen: &seen)
                }
                for cell in table.cells {
                    if let sub = cell.subLayout {
                        applySelectRectsRecursive(in: sub, perItemRanges: perItemRanges, seen: &seen)
                    }
                }
            default:
                break
            }
        }
    }

    private func applySelectRects(to textItem: InstantPageTextItem, range: NSRange) {
        for line in textItem.lines {
            let inter = NSIntersectionRange(line.range, range)
            if inter.length == 0 {
                line.selectRect = .zero
                continue
            }
            let startOffset = CTLineGetOffsetForStringIndex(line.line, inter.location, nil)
            let endOffset = CTLineGetOffsetForStringIndex(line.line, inter.location + inter.length, nil)
            // Use the alignment-applied line frame so a centered (pull-quote) or right-aligned line's
            // selection highlight lines up with the DRAWN text, not the raw left-based `line.frame`.
            let lf = textItem.alignedLineFrame(line)
            line.selectRect = NSMakeRect(
                lf.minX + startOffset,
                lf.minY - 2,
                endOffset - startOffset,
                lf.height + 6
            )
        }
    }

    public func linkItem(at point: NSPoint) -> InstantPageUrlItem? {
        if case let .link(link)? = self.interactiveTarget(at: point) {
            return link
        }
        return nil
    }

}

// MARK: - Slideshow hosting

private final class InstantPageV2SlideMediaView: View {
    private var content: ChatMediaContentView?
    var mediaView: NSView? { return self.content }
    private(set) var media: InstantPageMedia?
    var onScrollWheel: ((NSEvent) -> Void)?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func scrollWheel(with event: NSEvent) {
        self.onScrollWheel?(event)
    }

    func update(media: InstantPageMedia, context: any AccountContextProtocol, parent: Message, parameters: ChatMediaLayoutParameters, size: NSSize, squareCorners: Bool) {
        self.media = media
        let cls = ChatLayoutUtils.contentNode(for: media.media)
        let view: ChatMediaContentView
        if let existing = self.content, existing.isKind(of: cls) {
            view = existing
        } else {
            self.content?.removeFromSuperview()
            view = cls.init(frame: CGRect(origin: .zero, size: size))
            self.addSubview(view)
            self.content = view
        }
        (view as? ChatInteractiveContentView)?.squareCorners = squareCorners
        view.update(with: media.media, size: size, context: context, parent: parent, table: nil, parameters: parameters, animated: false)
        view.frame = CGRect(origin: .zero, size: size)
        view.updateLayout(size: size, transition: .immediate)
    }

    override func layout() {
        super.layout()
        self.content?.frame = bounds
        self.content?.updateLayout(size: bounds.size, transition: .immediate)
    }
}

public final class InstantPageV2SlideshowView: View, HorizontalScrollConsuming {
    private enum ScrollAxis {
        case horizontal
        case vertical
    }

    private let pagesView = View(frame: .zero)
    private let dotsView = InstantPageV2SlideshowDotsView(frame: .zero)
    private var slideViews: [InstantPageV2SlideMediaView] = []
    private var currentKey: [Int] = []
    private var currentPage: Int = 0
    private var scrollAxis: ScrollAxis?
    private var isDragging: Bool = false
    private var dragOffset: CGFloat = 0
    private var lastScrollDeltaX: CGFloat = 0
    private var mouseMonitor: Any?

    public var cornerRadius: CGFloat = 8.0 {
        didSet {
            guard cornerRadius != oldValue else { return }
            self.layer?.cornerRadius = cornerRadius
        }
    }

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.layer?.cornerRadius = 8.0
        self.layer?.masksToBounds = true
        self.addSubview(self.pagesView)
        self.dotsView.isEventLess = true
        self.addSubview(self.dotsView)
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        self.removeMouseMonitor()
    }

    public func consumesHorizontalScroll(atWindowPoint windowPoint: NSPoint) -> Bool {
        return self.slideViews.count > 1
    }

    public func mediaContentView(forMediaIndex index: Int) -> NSView? {
        guard self.currentKey.firstIndex(of: index) == self.currentPage, self.currentPage < self.slideViews.count else {
            return nil
        }
        return self.slideViews[self.currentPage].mediaView
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            self.endDrag()
        }
    }

    public func configure(medias: [InstantPageMedia], context: any AccountContextProtocol, config: (Media, CGSize, Int, Bool) -> (parent: Message, parameters: ChatMediaLayoutParameters)?, size: NSSize) {
        let key = medias.map { $0.index }
        if key != self.currentKey {
            self.currentKey = key
            self.endDrag()
            self.pagesView.layer?.removeAllAnimations()
            self.currentPage = 0
            self.slideViews.forEach { $0.removeFromSuperview() }
            self.slideViews.removeAll()
            for media in medias {
                guard let (parent, parameters) = config(media.media, size, media.index, false) else { continue }
                let slide = InstantPageV2SlideMediaView(frame: CGRect(origin: .zero, size: size))
                slide.onScrollWheel = { [weak self] event in
                    self?.handleSlideScroll(event)
                }
                slide.update(media: media, context: context, parent: parent, parameters: parameters, size: size, squareCorners: self.cornerRadius <= 0)
                self.slideViews.append(slide)
                self.pagesView.addSubview(slide)
            }
        } else {
            for slide in self.slideViews {
                guard let media = medias.first(where: { $0.index == slide.media?.index }),
                      let (parent, parameters) = config(media.media, size, media.index, false) else { continue }
                slide.update(media: media, context: context, parent: parent, parameters: parameters, size: size, squareCorners: self.cornerRadius <= 0)
            }
        }
        self.dotsView.update(count: self.slideViews.count, page: self.currentPage)
        self.updatePagesLayout()
        self.updateSlidesPlayback()
    }

    public override func layout() {
        super.layout()
        self.updatePagesLayout()
    }

    private func updatePagesLayout() {
        let size = self.bounds.size
        for (i, slide) in self.slideViews.enumerated() {
            slide.frame = CGRect(x: CGFloat(i) * size.width, y: 0, width: size.width, height: size.height)
        }
        let maxOffset = CGFloat(max(0, self.slideViews.count - 1)) * size.width
        var offset = CGFloat(self.currentPage) * size.width
        if self.isDragging {
            let clamped = min(max(self.dragOffset, 0), maxOffset)
            offset = clamped + (self.dragOffset - clamped) / 3.0
        }
        let pagesFrame = CGRect(x: -offset, y: 0, width: maxOffset + size.width, height: size.height)
        if self.pagesView.frame != pagesFrame {
            self.pagesView.frame = pagesFrame
        }
        self.dotsView.frame = CGRect(x: 0, y: size.height - 24, width: size.width, height: 24)
    }

    private func handleSlideScroll(_ event: NSEvent) {
        if event.phase == .mayBegin || event.phase == .began {
            self.endDrag()
            self.scrollAxis = nil
        }
        if self.scrollAxis == nil, !event.phase.isEmpty, event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 {
            let isHorizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) && self.slideViews.count > 1
            self.scrollAxis = isHorizontal ? .horizontal : .vertical
            if isHorizontal {
                self.beginDrag()
            }
        }
        let isGesture = !event.phase.isEmpty || !event.momentumPhase.isEmpty
        guard isGesture, self.scrollAxis == .horizontal else {
            self.superview?.scrollWheel(with: event)
            return
        }
        switch event.phase {
        case .began, .changed:
            let width = self.bounds.width
            self.dragOffset = max(-width, min(CGFloat(self.slideViews.count) * width, self.dragOffset - event.scrollingDeltaX))
            self.lastScrollDeltaX = event.scrollingDeltaX
            self.updatePagesLayout()
        case .ended, .cancelled:
            self.endDrag()
            self.superview?.scrollWheel(with: event)
        default:
            break
        }
    }

    private func beginDrag() {
        self.dragOffset = -(self.pagesView.layer?.presentation()?.frame.minX ?? self.pagesView.frame.minX)
        self.pagesView.layer?.removeAllAnimations()
        self.lastScrollDeltaX = 0
        self.isDragging = true
        self.removeMouseMonitor()
        self.mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.endDrag()
            return event
        }
    }

    private func endDrag() {
        guard self.isDragging else {
            return
        }
        self.isDragging = false
        self.removeMouseMonitor()
        let width = self.bounds.width
        guard width > 0, !self.slideViews.isEmpty else {
            return
        }
        let position = self.dragOffset / width
        let page = self.lastScrollDeltaX < -2 ? ceil(position) : self.lastScrollDeltaX > 2 ? floor(position) : round(position)
        self.currentPage = max(0, min(self.slideViews.count - 1, Int(page)))
        self.dotsView.update(count: self.slideViews.count, page: self.currentPage)
        let frame = CGRect(origin: NSMakePoint(-CGFloat(self.currentPage) * width, 0), size: self.pagesView.frame.size)
        ContainedViewLayoutTransition.animated(duration: 0.35, curve: .spring).updateFrame(view: self.pagesView, frame: frame, completion: { [weak self] _ in
            self?.updateSlidesPlayback()
        })
    }

    private func removeMouseMonitor() {
        if let monitor = self.mouseMonitor {
            NSEvent.removeMonitor(monitor)
            self.mouseMonitor = nil
        }
    }

    private func updateSlidesPlayback() {
        for slide in self.slideViews {
            (slide.mediaView as? ChatInteractiveContentView)?.updatePlayerIfNeeded()
        }
    }
}

private final class InstantPageV2SlideshowDotsView: View {
    private var dots: [CALayer] = []

    func update(count: Int, page: Int) {
        let visibleCount = count > 1 ? count : 0
        while self.dots.count > visibleCount {
            self.dots.removeLast().removeFromSuperlayer()
        }
        while self.dots.count < visibleCount {
            let dot = CALayer()
            dot.cornerRadius = 3
            self.layer?.addSublayer(dot)
            self.dots.append(dot)
        }
        for (i, dot) in self.dots.enumerated() {
            dot.backgroundColor = (i == page ? NSColor.white : NSColor.white.withAlphaComponent(0.5)).cgColor
        }
        self.needsLayout = true
    }

    override func layout() {
        super.layout()
        let startX = floor((self.bounds.width - CGFloat(self.dots.count - 1) * 12 - 6) / 2)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, dot) in self.dots.enumerated() {
            dot.frame = CGRect(x: startX + CGFloat(i) * 12, y: floor((self.bounds.height - 6) / 2), width: 6, height: 6)
        }
        CATransaction.commit()
    }
}
