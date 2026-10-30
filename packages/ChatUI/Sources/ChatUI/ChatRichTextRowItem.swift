import Cocoa
import TelegramCore
import Postbox
import TGUIKit
import SwiftSignalKit
import QuartzCore
import CoreMedia
import InAppSettings
import RichTextEditorCore
import RichTextEditorUI
import TelegramMediaResources
import ChatHistoryModel
import InputTextView
import InstantPageUI
import Localization
import MessageUtils
import Strings
import TelegramContext
import TelegramTheme
import TelegramUtils
import InlineStickerLayer
import InputView

/// Resolves the gallery's open/close zoom source for a rich message's media. The rich message's media
/// views are scattered across the canvas (not a single ordered container like grouped media), so the
/// gallery's `firstStableId + subviews[index]` path doesn't fit — instead this maps the gallery item's
/// `InstantPageMedia.index` straight to the hosted media view. Held strongly by the row view; the
/// gallery keeps only a weak reference.
private final class InstantPageGalleryDelegate: InteractionContentViewProtocol {
    private weak var richView: InstantPageV2View?
    init(richView: InstantPageV2View) { self.richView = richView }
    func contentInteractionView(for stableId: AnyHashable, animateIn: Bool) -> NSView? {
        if let index = stableId.base as? Int {
            return self.richView?.mediaContentView(forMediaIndex: index)
        }
        return nil
    }
    func interactionControllerDidFinishAnimation(interactive: Bool, for stableId: AnyHashable) {}
    func addAccesoryOnCopiedView(for stableId: AnyHashable, view: NSView) {}
    func videoTimebase(for stableId: AnyHashable) -> CMTimebase? { return nil }
    func applyTimebase(for stableId: AnyHashable, timebase: CMTimebase?) {}
}

private var instantPageStreamRevealCursors: [AnyHashable: Int] = [:]
private var instantPageShowMoreExpandedMessageIds: Set<MessageId> = []
private let instantPageShowMoreTopInset: CGFloat = 2.0

public final class ChatRichTextRowItem: ChatMessageItem {

    public private(set) var richLayout: InstantPageV2Layout = InstantPageV2Layout(contentSize: .zero, items: [], detailsIndices: [])
    public private(set) var richAttribute: RichTextMessageAttribute?
    public private(set) var instantPageTheme: InstantPageTheme = ChatRichTextRowItem.buildInstantPageTheme(for: theme, isIncoming: true, isBubbled: false)
    public private(set) var showMoreLayout: TextViewLayout?
    public var spoilersRevealed: Bool = false

    public let isStreaming: Bool
    private let hasTranslationState: Bool
    public private(set) var richCostMap: InstantPageV2RevealCostMap?
    private var isShowMoreExpanded: Bool = false

    public var revealCursor: Int?

    private var richLayoutWidth: CGFloat?

    private var usesSeparateDateLine: Bool {
        guard !self.isStreaming, self.richAttribute != nil, self.isBubbled, self.hasBubble, self.rightSize.height > 0 else {
            return false
        }
        if self.showMoreLayout != nil {
            return false
        }
        return lastTextLineFrameV2IfLastItemIsText(in: self.richLayout) == nil
    }

    private var effectiveInstantPage: InstantPage? {
        guard let attribute = self.richAttribute else {
            return nil
        }
        if self.isShowMoreExpanded, let fullInstantPage = attribute.fullInstantPage {
            return fullInstantPage
        }
        return attribute.instantPage
    }

    private var shouldShowMore: Bool {
        guard !self.isShowMoreExpanded,
              !self.isStreaming,
              !self.hasTranslationState,
              self.chatInteraction.mode != .preview,
              let message = self.message,
              message.id.namespace == Namespaces.Message.Cloud,
              let attribute = self.richAttribute else {
            return false
        }
        return !attribute.instantPage.isComplete
    }

    /// `details` blocks the user toggled away from their `defaultExpanded` state (by layout index),
    /// sourced from the chat UI state via the history entry so it survives item rebuilds.
    private var toggledDetails: Set<Int> {
        return self.entry.additionalData.detailsExpanded
    }

    /// Toggle a `details` block's expansion through the chat UI state; the resulting history-view
    /// update rebuilds this item with the new expansion baked into the layout.
    public func toggleDetails(at index: Int) {
        guard let messageId = self.message?.id else { return }
        self.chatInteraction.toggleDetails(DetailsMessageIndex(messageId: messageId, index: index))
    }

    public override init(_ initialSize: NSSize, _ chatInteraction: ChatInteraction, _ context: any AccountContextProtocol, _ entry: ChatHistoryEntry, theme: TelegramPresentationTheme) {
        var richAttribute = entry.message?.attributes.compactMap({ $0 as? RichTextMessageAttribute }).first
        self.hasTranslationState = entry.additionalData.translate != nil
        // Live translation: a rich message's translated content arrives as an InstantPage on the
        // TranslationMessageAttribute (via messages.translateRichMessage) — render that page instead.
        if let message = entry.message, let translate = entry.additionalData.translate,
           case let .complete(toLang) = translate,
           let translated = message.translationAttribute(toLang: toLang)?.instantPage {
            richAttribute = RichTextMessageAttribute(instantPage: translated, fullInstantPage: nil)
        }
        self.richAttribute = richAttribute
        self.isStreaming = entry.message?.attributes.contains(where: { $0 is TypingDraftMessageAttribute }) ?? false
        super.init(initialSize, chatInteraction, context, entry, theme: theme)
        self.isShowMoreExpanded = richAttribute?.fullInstantPage != nil && self.message.map { instantPageShowMoreExpandedMessageIds.contains($0.id) } == true
    }

    @discardableResult
    public func setShowMoreExpanded(_ expanded: Bool, attribute: RichTextMessageAttribute? = nil) -> Bool {
        if let attribute, let fullInstantPage = attribute.fullInstantPage, let current = self.richAttribute {
            self.richAttribute = RichTextMessageAttribute(instantPage: current.instantPage, fullInstantPage: fullInstantPage)
        }
        let value = expanded && self.richAttribute?.fullInstantPage != nil
        guard self.isShowMoreExpanded != value else {
            return false
        }
        self.isShowMoreExpanded = value
        self.richLayoutWidth = nil
        self.previousBlockWidth = 0
        return true
    }

    public override var contentOffset: NSPoint {
        var offset = super.contentOffset
        if self.isBubbled,
           self.hasBubble,
           self.textLayout.size.height == 0,
           offset.y == self.defaultContentTopOffset {
            offset.y = self.topInset
        }
        return offset
    }

    public var resolvedRevealCursor: Int? {
        if let cursor = self.revealCursor {
            return cursor
        }
        if let cursor = instantPageStreamRevealCursors[self.stableId] {
            return cursor
        }
        return self.isStreaming ? 0 : nil
    }

    public var isRevealAnimationActive: Bool {
        return self.isStreaming || instantPageStreamRevealCursors[self.stableId] != nil
    }

    fileprivate var revealedRichContentSize: CGSize {
        guard self.isRevealAnimationActive, let cursor = self.resolvedRevealCursor, let costMap = self.richCostMap else {
            return self.richLayout.contentSize
        }
        let revealed = costMap.revealedContentSize(revealedCount: cursor, layout: self.richLayout)
        return CGSize(
            width: min(self.richLayout.contentSize.width, revealed.width),
            height: min(self.richLayout.contentSize.height, revealed.height)
        )
    }

    public var effectiveRichHeight: CGFloat {
        return self.isStreaming ? self.revealedRichContentSize.height : self.richLayout.contentSize.height
    }

    public var mediaBubbleCornerInset: CGFloat {
        return 1
    }

    public var effectiveMediaBleed: CGFloat {
        guard self.isBubbled else {
            return 0
        }
        return self.bubbleContentInset - (self.hasBubble ? self.mediaBubbleCornerInset : 0)
    }

    public private(set) var hasFullBleedMedia: Bool = false

    fileprivate var revealedUnsupportedItems: [InstantPageV2UnsupportedItem] {
        let limit = self.revealedRichContentSize.height
        var result: [InstantPageV2UnsupportedItem] = []
        for item in self.richLayout.items {
            if case let .unsupported(unsupported) = item, unsupported.frame.maxY <= limit {
                result.append(unsupported)
            }
        }
        return result
    }

    /// Frames of the `.unsupported` bands, in rich-view coordinates. Each one is a tear that runs
    /// clean through the bubble, so the paragraphs above and below become two pieces of torn paper.
    public var unsupportedBands: [CGRect] {
        return self.revealedUnsupportedItems.map { $0.layout.cleanTearRect(in: $0.frame) }
    }

    public override func makeContentSize(_ width: CGFloat) -> NSSize {
        let baseSize = super.makeContentSize(width)

        guard let page = self.effectiveInstantPage else {
            return baseSize
        }

        if self.richLayoutWidth != width {
            let quoteAccentColor = self.wpPresentation.activity.main
            self.instantPageTheme = ChatRichTextRowItem.buildInstantPageTheme(
                for: self.presentation,
                isIncoming: self.isIncoming,
                isBubbled: self.isBubbled,
                quoteAccentColor: quoteAccentColor
            )

            let webpage = TelegramMediaWebpage(
                webpageId: MediaId(namespace: 0, id: 0),
                content: .Loaded(TelegramMediaWebpageLoadedContent(
                    url: "", displayUrl: "", hash: 0, type: nil,
                    websiteName: nil, title: nil, text: nil,
                    embedUrl: nil, embedType: nil, embedSize: nil, duration: nil,
                    author: nil, isMediaLargeByDefault: nil, imageIsVideoCover: false,
                    image: nil, file: nil, story: nil, attributes: [],
                    instantPage: page
                ))
            )

            // Match the chat text bubble's code syntax-highlight palette. Code-block chrome uses the
            // Instant Page theme's link color, matching block quotes.
            let codeSyntaxThemeKeys = ChatHistoryUIHooks.shared.generateSyntaxThemeParams(self.presentation, self.isBubbled, self.isIncoming)

            // Lay collage media out with the chat grouped-media mosaic. Synthetic per-media messages
            // (distinct ids, like WPArticleLayout) feed `GroupedLayout`, which returns the tile frames.
            let collageMosaic: (([Media], CGFloat) -> [CGRect])?
            if let parent = self.message {
                let peerId = parent.id.peerId
                collageMosaic = { medias, maxWidth in
                    var messages: [Message] = []
                    for (i, media) in medias.enumerated() {
                        let message = parent.withUpdatedMedia([media])
                            .withUpdatedStableId(UInt32(truncatingIfNeeded: i &+ 1))
                            .withUpdatedId(MessageId(peerId: peerId, namespace: Namespaces.Message.Local, id: MessageId.Id(i)))
                        messages.append(message)
                    }
                    let grouped = GroupedLayout(messages, type: .photoOrVideo)
                    grouped.measure(NSMakeSize(maxWidth, min(maxWidth, 320.0)), spacing: 2.0)
                    return (0 ..< grouped.count).map { grouped.frame(at: $0) }
                }
            } else {
                collageMosaic = nil
            }

            let layout = layoutInstantPageV2(
                webpage: webpage,
                instantPage: page,
                boundingWidth: width,
                horizontalInset: 0,
                theme: self.instantPageTheme,
                toggledDetails: self.toggledDetails,
                fitToWidth: true,
                computeRevealCharacterRects: self.isRevealAnimationActive,
                codeSyntaxThemeKeys: codeSyntaxThemeKeys,
                codeTextColor: self.presentation.chat.monospacedPreColor(self.isIncoming, self.isBubbled),
                collageMosaic: collageMosaic,
                mediaBleed: self.effectiveMediaBleed,
                unsupportedStyle: ChatUnsupportedPapercutStyle.make(presentation: self.presentation, isBubbled: self.isBubbled && self.hasBubble, tornEdges: true)
            )
            self.richLayout = layout
            self.hasFullBleedMedia = layout.items.contains { $0.frame.minX < -0.5 }
            self.richCostMap = self.isRevealAnimationActive ? layout.computeRevealCostMap() : nil
            self.richLayoutWidth = width

            if self.shouldShowMore {
                let text = strings().chatRichTextShowMore
                let layout = TextViewLayout(.initialize(string: text, color: self.presentation.chat.linkColor(self.isIncoming, self.isBubbled), font: .normal(self.instantPageTheme.textCategories.paragraph.font.size)), maximumNumberOfLines: 1)
                layout.measure(width: width)
                layout.maskBlockImage = layout.generateBlock(backgroundColor: NSColor.black.withAlphaComponent(0.4))
                self.showMoreLayout = layout
            } else {
                self.showMoreLayout = nil
            }
        }

        let combinedWidth = max(max(baseSize.width, self.richLayout.contentSize.width), self.showMoreLayout?.layoutSize.width ?? 0)
        let spacing: CGFloat = baseSize.height > 0 ? defaultContentInnerInset : 0
        let showMoreHeight = self.showMoreLayout.map { instantPageShowMoreTopInset + $0.layoutSize.height } ?? 0
        // _contentSize is sized to the FULL rich height (stable across the stream); the per-frame
        // shrink during streaming is applied in `height` below, so the bubble grows gradually
        // without re-running makeContentSize/makeSize every frame.
        let combinedHeight = baseSize.height + spacing + self.richLayout.contentSize.height + showMoreHeight
        // The V2 page already supplies its own leading block spacing (5pt for a top-level
        // paragraph in chat), so there is no matching outer inset above the page. While streaming
        // the trailing one goes too: with nothing revealed below it, `spacing` is already acting as
        // the bottom padding and keeping both double-insets the bubble against a plain text one.
        let trailingInset: CGFloat = self.isStreaming || self.usesSeparateDateLine ? 0 : self.defaultContentInnerInset
        return NSSize(width: combinedWidth, height: combinedHeight + trailingInset)
    }

    public override var height: CGFloat {
        let full = super.height
        guard self.isStreaming else {
            return full
        }
        let hidden = self.richLayout.contentSize.height - self.effectiveRichHeight
        let bottomInset: CGFloat
        if let cursor = self.resolvedRevealCursor,
           let costMap = self.richCostMap,
           let firstItem = self.richLayout.items.first,
           costMap.revealedItemsMaxY(revealedCount: cursor, layout: self.richLayout) > firstItem.frame.maxY {
            bottomInset = 6.0
        } else {
            bottomInset = 0.0
        }
        return max(0, full - hidden - self.topInset * 2.0 + bottomInset)
    }

    public override var lastLineContentWidth: LastLineData? {
        if self.isStreaming {
            return super.lastLineContentWidth
        }
        if let showMoreLayout = self.showMoreLayout {
            return LastLineData(width: showMoreLayout.layoutSize.width, single: true)
        }
        // Committed rich message: trail the date after the last line only when the page ends in
        // text. The base additionalLineForDateInBubbleState then decides trail vs. wrap from this.
        if self.richAttribute != nil {
            if let lineFrame = lastTextLineFrameV2IfLastItemIsText(in: self.richLayout) {
                var totalTextLines = 0
                for item in self.richLayout.items {
                    if case let .text(t) = item { totalTextLines += t.textItem.lines.count }
                }
                return LastLineData(width: lineFrame.maxX, single: totalTextLines <= 1)
            }
            return nil
        }
        return super.lastLineContentWidth
    }

    public override var additionalLineForDateInBubbleState: CGFloat? {
        if self.isStreaming {
            return nil
        }
        guard self.richAttribute != nil else {
            return super.additionalLineForDateInBubbleState
        }
        if self.showMoreLayout != nil {
            return super.additionalLineForDateInBubbleState
        }
        if lastTextLineFrameV2IfLastItemIsText(in: self.richLayout) == nil {
            return self.rightSize.height + (self.usesSeparateDateLine ? 0 : self.defaultContentInnerInset)
        }
        // Ends in text: defer to the base trail/wrap decision (no extra inset) so the text→date gap
        // matches a normal text message — the content's own bottom inset already provides the spacing.
        return super.additionalLineForDateInBubbleState
    }

    public override var contentSize: NSSize {
        var size = super.contentSize
        if self.isStreaming {
            size.width = min(size.width, self.revealedRichContentSize.width)
        }
        return size
    }

    public override func viewClass() -> AnyClass {
        return ChatRichTextRowView.self
    }

    private static func chatBodyLineSpacingFactor(font: NSFont) -> CGFloat {
        let coreTextFont = font as CTFont
        let chatLineHeight = floor(CTFontGetAscent(coreTextFont) + CTFontGetDescent(coreTextFont))
        let chatLineSpacing = floor(chatLineHeight * 0.12)
        let richLineHeight = floor(font.ascender + font.descender)
        guard richLineHeight > 0.0 else {
            return 1.12
        }
        let requiredRichSpacing = max(0.0, chatLineHeight + chatLineSpacing - richLineHeight)
        return (requiredRichSpacing + 0.5) / richLineHeight
    }

    public static func buildInstantPageTheme(for theme: TelegramPresentationTheme, isIncoming: Bool, isBubbled: Bool, quoteAccentColor: NSColor? = nil) -> InstantPageTheme {
        let isDark = theme.colors.isDark
        let palette = theme.colors

        let bodyFont = NSFont.normal(theme.fontSize)
        let bodyLineSpacingFactor = self.chatBodyLineSpacingFactor(font: bodyFont)

        let primary = theme.chat.textColor(isIncoming, isBubbled)
        let secondary = theme.chat.grayText(isIncoming, isBubbled)
        let link = theme.chat.linkColor(isIncoming, isBubbled)
        let quoteAccent = quoteAccentColor ?? link

        let codeBg: NSColor
        let borderColor: NSColor
        if isBubbled {
            let bubbleBg = isIncoming ? palette.bubbleBackground_incoming : palette.blendedOutgoingColors
            codeBg = bubbleBg.darker(amount: isDark ? -0.06 : 0.04)
            borderColor = primary.withAlphaComponent(0.15)
        } else {
            codeBg = palette.grayBackground
            borderColor = palette.border
        }

        let buttonAccent = isIncoming ? palette.accent : theme.chat.activityColor(isIncoming, isBubbled)
        let buttonPrimaryFill = isIncoming ? palette.accent : theme.chat.activityBackground(isIncoming, isBubbled)
        let buttonPrimaryForeground: NSColor
        if isIncoming {
            // Hex, not `.white`: this reaches RLottie as the tint for a monochrome custom emoji in a
            // button label, and its component readers raise on a Generic Gray colour.
            buttonPrimaryForeground = NSColor(rgb: 0xffffff)
        } else if isDark && isBubbled {
            buttonPrimaryForeground = palette.blendedOutgoingColors
        } else {
            buttonPrimaryForeground = theme.chat.activityForeground(isIncoming, isBubbled)
        }
        let buttonPanelFill = buttonPrimaryFill.withAlphaComponent(0.1)
        let buttonRegularFill = isIncoming && !isDark ? NSColor(rgb: 0x000000, alpha: 0.05) : buttonPanelFill
        let checklistBorderColor = isDark || !isIncoming ? buttonPrimaryFill.withMultipliedAlpha(0.25) : NSColor(rgb: 0x000000, alpha: 0.1)
        let usesMonochromeButtonPalette = isDark && !isIncoming && isBubbled
        let buttonDangerColor = usesMonochromeButtonPalette ? buttonAccent : palette.redUI
        let buttonSuccessColor = usesMonochromeButtonPalette ? buttonAccent : (isDark ? NSColor(rgb: 0x30cf30) : NSColor(rgb: 0x26972c))

        let separatorBaseAlpha: CGFloat = isDark ? 0.5 : (isIncoming ? 0.6 : 0.65)

        return InstantPageTheme(
            type: isDark ? .dark : .light,
            pageBackgroundColor: .clear,
            textCategories: InstantPageTextCategories(
                kicker: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 13.0, lineSpacingFactor: 0.85), color: secondary),
                header: InstantPageTextAttributes(font: InstantPageFont(style: .serif, size: 24.0, lineSpacingFactor: 1.0, weight: .medium), color: primary),
                subheader: InstantPageTextAttributes(font: InstantPageFont(style: .serif, size: 22.0, lineSpacingFactor: 1.0, weight: .medium), color: primary),
                paragraph: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: bodyFont.pointSize, lineSpacingFactor: bodyLineSpacingFactor), color: primary),
                caption: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 12.0, lineSpacingFactor: 1.0), color: secondary),
                credit: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 11.0, lineSpacingFactor: 1.0), color: secondary),
                table: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 13.0, lineSpacingFactor: 1.0), color: primary),
                article: InstantPageTextAttributes(font: InstantPageFont(style: .sans, size: 14.0, lineSpacingFactor: 1.0), color: primary)
            ),
            serif: false,
            codeBlockBackgroundColor: codeBg,
            linkColor: link,
            textHighlightColor: link.withAlphaComponent(0.1),
            linkHighlightColor: link.withAlphaComponent(0.1),
            markerColor: isDark ? NSColor(rgb: 0xffd54f).withAlphaComponent(0.35) : NSColor(rgb: 0xfef3bc),
            panelBackgroundColor: buttonPanelFill,
            panelHighlightedBackgroundColor: buttonPrimaryFill.withAlphaComponent(0.25),
            panelPrimaryColor: isIncoming ? primary : buttonAccent,
            panelSecondaryColor: secondary,
            panelAccentColor: buttonAccent,
            tableBorderColor: borderColor,
            tableHeaderColor: buttonRegularFill,
            controlColor: buttonPrimaryFill,
            imageTintColor: nil,
            overlayPanelColor: isDark ? NSColor(rgb: 0x000000, alpha: 0.2) : NSColor(rgb: 0xffffff, alpha: 0.7),
            separatorColor: secondary.withMultipliedAlpha(separatorBaseAlpha).mixedWith(buttonAccent.withMultipliedAlpha(0.2), alpha: 0.3),
            quoteAccentColor: quoteAccent,
            buttonDangerColor: buttonDangerColor,
            buttonSuccessColor: buttonSuccessColor,
            checklistBorderColor: checklistBorderColor,
            checkboxFill: buttonPrimaryFill,
            checkboxForeground: buttonPrimaryForeground
        )
    }
}

private final class ChatRichTextShowMoreControl: Control {
    private let textView = TextView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.addSubview(self.textView)
        self.textView.isSelectable = false
        self.textView.userInteractionEnabled = false
        self.scaleOnClick = true
        self.set(cursor: .pointingHand, for: .Hover)
        self.set(cursor: .pointingHand, for: .Highlight)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(layout: TextViewLayout, loading: Bool, animated: Bool) {
        self.textView.update(layout)
        self.setFrameSize(layout.layoutSize)
        self.textView.frame = self.bounds
        self.setLoading(loading, animated: animated)
    }

    func setLoading(_ loading: Bool, animated: Bool) {
        self.isEnabled = !loading
        self.textView.setIsShimmering(loading, animated: animated)
    }

    override func layout() {
        super.layout()
        self.textView.frame = self.bounds
    }
}

public final class ChatRichTextRowView: ChatMessageView, ChatBubbleCustomTextSelection {

    private var richView: InstantPageV2View
    private let showMoreControl = ChatRichTextShowMoreControl(frame: .zero)

    private var revealController: TextRevealController?
    private var revealLink: SharedDisplayLinkDriver.Link?
    private var lastRevealStableId: AnyHashable?
    private var lastBoundRichStableId: AnyHashable?
    private var lastShowMoreMessageId: MessageId?
    private var pendingQuoteFocus: (messageId: MessageId, text: String, range: NSRange?)?
    private var quoteDetailsExpansion: (messageId: MessageId, previousState: Set<Int>)?
    private var requestFullRichTextDisposable: Disposable?
    private var requestFullRichTextMessageId: MessageId?
    // Held strongly so the gallery (which keeps only a weak delegate) can resolve the zoom source view
    // for the duration of the open/close animation.
    private var galleryDelegate: InstantPageGalleryDelegate?

    deinit {
        self.revealLink?.invalidate()
        self.requestFullRichTextDisposable?.dispose()
        if let messageId = self.lastShowMoreMessageId {
            instantPageShowMoreExpandedMessageIds.remove(messageId)
        }
    }

    /// Creates (and retains) the gallery zoom-source delegate for this row's rich media.
    fileprivate func makeGalleryDelegate() -> InteractionContentViewProtocol {
        let delegate = InstantPageGalleryDelegate(richView: self.richView)
        self.galleryDelegate = delegate
        return delegate
    }

    /// Hosted audio/music content views, for the global inline player to bind as listeners (so the
    /// bubble reflects play/pause state).
    public func audioContentViews() -> [ChatAudioContentView] {
        guard self.item is ChatRichTextRowItem else {
            return []
        }
        return self.richView.audioContentViews()
    }

    /// Lets the gallery (via the table path) find a media subview by its `InstantPageMedia.index`.
    public override func interactionContentView(for innerId: AnyHashable, animateIn: Bool) -> NSView {
        if self.item is ChatRichTextRowItem,
           let index = innerId.base as? Int,
           let view = self.richView.mediaContentView(forMediaIndex: index) {
            return view
        }
        return super.interactionContentView(for: innerId, animateIn: animateIn)
    }

    public func applyBubbleSelection(begin: NSPoint, end: NSPoint, isStartRow: Bool, isEndRow: Bool, reversed: Bool) -> [ChatBubbleSelectionFragment] {
        guard self.item is ChatRichTextRowItem else {
            return []
        }
        if self.richView.isDraggingTableScroller {
            return []
        }
        let localBegin = self.richView.convert(begin, from: self)
        let localEnd   = self.richView.convert(end,   from: self)
        return self.richView.applySelection(begin: localBegin, end: localEnd, isStartRow: isStartRow, isEndRow: isEndRow, reversed: reversed)
    }

    public func clearBubbleSelection() {
        self.richView.clearBubbleSelection()
    }

    /// Total selectable (non-whitespace) length of the whole message — the copy path compares the selection
    /// against this to distinguish a whole-message copy from a partial one.
    public func totalSelectableTextLength() -> Int {
        guard self.item is ChatRichTextRowItem else {
            return 0
        }
        return self.richView.totalSelectableTextLength()
    }

    public override func canStartTextSelecting(_ event: NSEvent) -> Bool {
        guard self.item is ChatRichTextRowItem else {
            return super.canStartTextSelecting(event)
        }
        let local = self.richView.convert(event.locationInWindow, from: nil)
        if self.richView.isPointOverTableScroller(local) {
            return false
        }
        return super.canStartTextSelecting(event)
    }

    public override func clickInContent(point: NSPoint) -> Bool {
        guard self.item is ChatRichTextRowItem else {
            return super.clickInContent(point: point)
        }
        let local = self.richView.convert(point, from: self)
        if self.richView.clickInContent(point: local) {
            return true
        }
       
        return super.clickInContent(point: point)
    }

    public override func focusAnimation(_ innerId: AnyHashable?, text: String?) {
        self.focusAnimation(innerId, text: text, range: nil)
    }

    public override func focusAnimation(_ innerId: AnyHashable?, text: String?, range: NSRange?) {
        self.pendingQuoteFocus = nil
        if let item = self.item as? ChatRichTextRowItem, let messageId = item.message?.id, let text, !text.isEmpty {
            self.pendingQuoteFocus = (messageId, text, range)
            if self.retryPendingQuoteFocus() {
                return
            }
        }
        super.focusAnimation(innerId, text: text, range: range)
    }

    @discardableResult
    private func retryPendingQuoteFocus() -> Bool {
        guard let pending = self.pendingQuoteFocus,
              let item = self.item as? ChatRichTextRowItem,
              item.message?.id == pending.messageId else {
            self.pendingQuoteFocus = nil
            return false
        }
        if let expansion = self.quoteDetailsExpansion, expansion.messageId == pending.messageId {
            if item.entry.additionalData.detailsExpanded == expansion.previousState {
                return true
            }
        }
        self.quoteDetailsExpansion = nil
        if let index = item.richLayout.collapsedDetailsIndex(forQuote: pending.text, range: pending.range) {
            self.quoteDetailsExpansion = (pending.messageId, item.entry.additionalData.detailsExpanded)
            item.toggleDetails(at: index)
            return true
        }
        if self.richView.highlightQuote(text: pending.text, color: item.presentation.colors.focusAnimationColor, range: pending.range) {
            self.pendingQuoteFocus = nil
            return true
        }
        if item.showMoreLayout != nil {
            self.activateShowMore()
            return true
        }
        self.pendingQuoteFocus = nil
        return false
    }

    public required init(frame frameRect: NSRect) {
        self.richView = ChatRichTextRowView.makeRichView()
        super.init(frame: frameRect)
        contentView.addSubview(self.richView)
        contentView.addSubview(self.showMoreControl)
        self.showMoreControl.isHidden = true
        self.showMoreControl.set(handler: { [weak self] _ in
            self?.activateShowMore()
        }, for: .Click)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func makeRichView() -> InstantPageV2View {
        let view = InstantPageV2View(frame: .zero)
        view.layer?.masksToBounds = false
        return view
    }

    private func attachRichContent() {
        if self.richView.superview == nil {
            self.contentView.addSubview(self.richView)
        }
        if self.showMoreControl.superview == nil {
            self.contentView.addSubview(self.showMoreControl)
        }
    }

    private func deactivateRichContent() {
        self.pendingQuoteFocus = nil
        self.quoteDetailsExpansion = nil
        self.stopRevealLink()
        self.revealController = nil
        if let stableId = self.lastRevealStableId {
            instantPageStreamRevealCursors.removeValue(forKey: stableId)
        }
        self.lastRevealStableId = nil
        self.lastBoundRichStableId = nil
        self.resetShowMore()
        self.galleryDelegate = nil
        self.richView.removeFromSuperview()
        self.richView = ChatRichTextRowView.makeRichView()
        self.showMoreControl.removeFromSuperview()
        self.rightView.change(opacity: 1.0, animated: false)
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        var showMoreStateChanged = false
        if let item = item as? ChatRichTextRowItem {
            self.attachRichContent()
            let messageId = item.message?.id
            if self.lastShowMoreMessageId != messageId {
                self.pendingQuoteFocus = nil
                self.quoteDetailsExpansion = nil
                if let messageId = self.lastShowMoreMessageId {
                    instantPageShowMoreExpandedMessageIds.remove(messageId)
                }
                self.finishShowMore(keepExpanded: false)
                self.lastShowMoreMessageId = messageId
            }
            let expanded = messageId.map { instantPageShowMoreExpandedMessageIds.contains($0) } == true
            showMoreStateChanged = item.setShowMoreExpanded(expanded)
            if showMoreStateChanged {
                _ = item.makeSize(item.width, oldWidth: 0)
            }
        } else {
            self.deactivateRichContent()
        }
        super.set(item: item, animated: animated)
        guard let item = item as? ChatRichTextRowItem else {
            return
        }

        self.rightView.change(opacity: item.isRevealAnimationActive ? 0.0 : 1.0, animated: false)
        self.richView.isHidden = false

        if self.lastBoundRichStableId != item.stableId {
            self.richView.clearQuoteHighlight()
            self.richView.resetTableScrollState()
            self.lastBoundRichStableId = item.stableId
        }

        let interaction = item.chatInteraction
        self.richView.openUrl = { [weak item] urlItem, confirm in
            if let address = urlItem.tonAddress {
                guard let item, address.utf8.count == 48, item.entry.additionalData.canHighlightLinks || !item.isIncoming else {
                    return
                }
                interaction.openTonAddressContextMenu(address)
                return
            }
            // Mention by peer id (see InstantPageTextItem .textMentionName): open the profile directly,
            // since `inApp` doesn't resolve a `tg://user?id=` URL.
            if urlItem.url.hasPrefix("tg://user?id="),
               let idString = urlItem.url.components(separatedBy: "id=").last,
               let rawId = Int64(idString) {
                interaction.openInfo(PeerId(rawId), false, nil, nil)
                return
            }
            // Phone: mirror the standard chat (a context menu) — `inApp` has no scheme for it, so route
            // to the chat-interaction handler directly.
            if urlItem.url.hasPrefix("tel:") {
                interaction.openPhoneNumberContextMenu(String(urlItem.url.dropFirst("tel:".count)))
                return
            }
            let link = ChatHistoryLink.inApp(
                for: urlItem.url as NSString,
                context: interaction.interactionContext,
                openInfo: interaction.openInfo,
                hashtag: interaction.hashtag,
                command: interaction.sendPlainText,
                applyProxy: interaction.applyProxy,
                confirm: confirm
            )
            ChatHistoryLink.execute(inapp: link)
        }
        // InstantPage button pills. `ReplyMarkupButtonAction` is deliberately reused as the page-button
        // action type so a tap can go through the same handlers bot buttons use; only 10 of its cases
        // are reachable from `Api.InlineButtonType`, which is what this covers. The rest (`.text`,
        // `.requestPhone`, `.requestMap`, `.setupPoll`, `.requestPeer`) come only from `Api.ButtonType`
        // and cannot appear on a page button.
        self.richView.buttonTapped = { [weak item] button in
            guard let message = item?.message else { return }
            let context = interaction.interactionContext
            let callbackTargetMessageId = message.callbackTargetMessageId
            switch button.action {
            case .disabled:
                break
            case let .url(url):
                ChatHistoryLink.execute(inapp: ChatHistoryLink.inApp(for: url.nsstring, context: context, openInfo: interaction.openInfo, hashtag: interaction.hashtag, command: interaction.sendPlainText, applyProxy: interaction.applyProxy, confirm: true))
            case let .copyText(payload):
                copyToClipboard(payload)
                showModalText(for: context.window, text: strings().shareLinkCopied)
            case let .openUserProfile(peerId):
                interaction.openInfo(peerId, false, nil, nil)
            case let .callback(requiresPassword, data):
                interaction.requestMessageActionCallback(callbackTargetMessageId, false, (requiresPassword: requiresPassword, data: data))
            case .openWebApp:
                interaction.requestMessageActionCallback(callbackTargetMessageId, true, nil)
            case let .openWebView(url, simple):
                if let bot = message.inlinePeer ?? message.author {
                    interaction.openWebview(bot: bot, title: bot.displayTitle, buttonText: button.text.plainText, url: url, simple: simple, inline: false)
                }
            case let .switchInline(samePeer, query, peerTypes):
                guard let bot = message.inlinePeer ?? message.author,
                      bot.isBot,
                      let username = bot.username,
                      !username.isEmpty else {
                    return
                }
                let text = "@\(username) \(query)"
                if samePeer {
                    interaction.updateInput(with: text)
                } else {
                    ChatInterfaceHooks.shared.shareSwitchInlineQuery(context, peerTypes, text)
                }
            case let .urlAuth(url, buttonId):
                _ = showModalProgress(signal: context.engine.messages.requestMessageActionUrlAuth(subject: .message(id: callbackTargetMessageId, buttonId: buttonId)), for: context.window).start(next: { result in
                    switch result {
                    case let .accepted(accepted):
                        if let accepted {
                            ChatHistoryLink.execute(inapp: ChatHistoryLink.inApp(for: accepted.nsstring, context: context, openInfo: interaction.openInfo, hashtag: interaction.hashtag, command: interaction.sendPlainText, applyProxy: interaction.applyProxy))
                        }
                    default:
                        // `.default` and the login-widget `.request` flow both fall back to opening the
                        // button's own URL with a confirmation, as the bot-keyboard path does.
                        ChatHistoryLink.execute(inapp: ChatHistoryLink.inApp(for: url.nsstring, context: context, openInfo: interaction.openInfo, hashtag: interaction.hashtag, command: interaction.sendPlainText, applyProxy: interaction.applyProxy, confirm: true))
                    }
                })
            default:
                break
            }
        }

        // A rich message is never `unsupported` (its content lives in the attribute), so route straight
        // to the update path rather than through `invokeAction`.
        self.richView.unsupportedTapped = { [weak item] in
            item?.invokeUpdateApp()
        }

        self.richView.detailsTapped = { [weak item] index in
            // Toggle through the chat UI state; the history-view update rebuilds this row with the
            // new expansion baked into the layout (same path as quote reveal).
            item?.toggleDetails(at: index)
        }

        self.richView.onSpoilerReveal = { [weak item] in
            item?.spoilersRevealed = true
        }

        // Tapping an in-message anchor centers the target section in the viewport. Centering is
        // symmetric, so it works regardless of the table's flip: convert the target to the document
        // view, then scroll the clip so the target's mid-Y lands at the viewport center (clamped to
        // the scrollable range). No full-bubble focus flash; the rich view flashes the target itself.
        self.richView.anchorReveal = { [weak self, weak item] rect in
            guard let self = self, let table = item?.table, let docView = table.documentView else { return }
            let clip = table.clipView
            let rectInDoc = self.richView.convert(rect, to: docView)
            let viewportHeight = clip.bounds.height
            let maxOriginY = max(0, docView.frame.height - viewportHeight)
            let originY = max(0, min(rectInDoc.midY - viewportHeight / 2.0, maxOriginY))
            clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: originY), animated: true)
        }

        self.richView.context = interaction.interactionContext
        self.richView.selectionColor = item.presentation.colors.selectText
        self.richView.bubbleSelectionSource = self
        self.richView.bubbleSelectionStableId = item.stableId
        // Match the media bleed so the anchor highlight can span the full bubble width.
        self.richView.contentBleed = item.effectiveMediaBleed

        self.richView.mediaContentConfig = { [weak self, weak item] media, size, mediaIndex, isFile in
            guard let item = item, let message = item.message else { return nil }
            let context = item.context
            let interaction = item.chatInteraction
            let parent = message.withUpdatedMedia([media])
            let presentation = ChatMediaPresentation.make(for: parent, account: context.account, renderType: .bubble, theme: item.presentation)

            if let map = media as? TelegramMediaMap {
                let scale: CGFloat = 2.0
                var pw = max(1, Int((size.width > 0 ? size.width : 320) * scale))
                var ph = max(1, Int((size.height > 0 ? size.height : 120) * scale))
                let maxW = 1280
                if pw > maxW {
                    ph = Int(CGFloat(ph) * CGFloat(maxW) / CGFloat(pw))
                    pw = maxW
                }
                let resource = MapSnapshotMediaResource(latitude: map.latitude, longitude: map.longitude, width: Int32(pw), height: Int32(ph), zoom: 15)
                let parameters = ChatMediaMapLayoutParameters(map: map, resource: resource, presentation: presentation, automaticDownload: true, execute: {
                    ChatNavigationHooks.shared.showLocationPreview(context, map, parent.effectiveAuthor, parent.id, context.window)
                }, imageSize: size.width > 0 && size.height > 0 ? size : nil, cornerRadius: item.isBubbled ? 0 : 8)
                return (parent, parameters)
            }
            if isFile, let file = media as? TelegramMediaFile {
                let parameters = ChatMediaLayoutParameters.layout(
                    for: file,
                    isWebpage: true,
                    chatInteraction: interaction,
                    presentation: presentation,
                    automaticDownload: true,
                    isIncoming: parent.isIncoming(context.account, true),
                    isFile: true,
                    autoplayMedia: AutoplayMediaPreferences.defaultSettings,
                    isChatRelated: true,
                    isCopyProtected: message.isCopyProtected(cachedData: interaction.presentation.cachedData)
                )
                return (parent, parameters)
            }
            if let file = media as? TelegramMediaFile, file.isMusic || file.isVoice {
                var audioParent = parent
                var isWebpage = true
                if file.isMusic {
                    let medias = item.richLayout.allMedias().filter { ($0.media as? TelegramMediaFile)?.isMusic == true }
                    let messages = expandSharedMediaMessages([message], where: sharedMediaPredicate(for: .music))
                    if let index = medias.firstIndex(where: { $0.index == mediaIndex }), index < messages.count {
                        audioParent = messages[index]
                        isWebpage = false
                    }
                }
                let parameters = ChatMediaLayoutParameters.layout(for: file, isWebpage: isWebpage, chatInteraction: interaction, presentation: presentation, automaticDownload: true, isIncoming: audioParent.isIncoming(context.account, true), autoplayMedia: AutoplayMediaPreferences.defaultSettings, isChatRelated: true)
                parameters.chatLocationInput = interaction.chatLocationInput
                parameters.chatMode = interaction.mode
                return (audioParent, parameters)
            }

            weak var weakParameters: ChatMediaGalleryParameters?
            let parameters = ChatMediaGalleryParameters(
                showMedia: { [weak self] _ in
                    guard let self, let item = self.item as? ChatRichTextRowItem, let realParent = item.message else { return }
                    let medias = item.richLayout.allMedias().filter {
                        $0.media is TelegramMediaImage || (($0.media as? TelegramMediaFile)?.isVideo ?? false)
                    }
                    let firstIndex = medias.firstIndex(where: { $0.index == mediaIndex })
                        ?? medias.firstIndex(where: { $0.media.isEqual(to: media) }) ?? 0
                    let galleryDelegate = self.makeGalleryDelegate()
                    showInstantViewGallery(context: context, medias: medias, firstIndex: firstIndex, firstStableId: nil, parent: realParent, galleryDelegate, weakParameters)
                },
                showMessage: { _ in },
                isWebpage: true,
                media: media,
                automaticDownload: true
            )
            weakParameters = parameters
            return (parent, parameters)
        }

        self.richView.update(layout: item.richLayout, theme: item.instantPageTheme)
        self.richView.setSpoilerReveal(item.spoilersRevealed)
        if let layout = item.showMoreLayout {
            self.showMoreControl.isHidden = false
            let loading = self.requestFullRichTextMessageId == item.message?.id
            self.showMoreControl.update(layout: layout, loading: loading, animated: animated)
        } else {
            self.showMoreControl.isHidden = true
            self.showMoreControl.setLoading(false, animated: animated)
        }
        self.updateStreaming(item: item)
        if self.pendingQuoteFocus != nil {
            Queue.mainQueue().justDispatch { [weak self] in
                self?.retryPendingQuoteFocus()
            }
        }
        if showMoreStateChanged {
            Queue.mainQueue().justDispatch { [weak self, weak item] in
                guard let self, let item, self.item === item else {
                    return
                }
                item.noteHeightOfRow()
            }
        }
    }

    private func activateShowMore() {
        guard let item = self.item as? ChatRichTextRowItem,
              let messageId = item.message?.id,
              item.showMoreLayout != nil else {
            return
        }
        instantPageShowMoreExpandedMessageIds.insert(messageId)
        if let attribute = item.richAttribute, attribute.fullInstantPage != nil {
            self.applyShowMoreExpansion(item: item, attribute: attribute)
            return
        }
        guard self.requestFullRichTextDisposable == nil else {
            return
        }
        self.requestFullRichTextMessageId = messageId
        if let layout = item.showMoreLayout {
            self.showMoreControl.update(layout: layout, loading: true, animated: true)
        }
        self.requestFullRichTextDisposable = (item.context.engine.messages.requestFullRichText(id: messageId)
        |> deliverOnMainQueue).start(next: { [weak self] attribute in
            guard let self,
                  self.requestFullRichTextMessageId == messageId else {
                return
            }
            guard let item = self.item as? ChatRichTextRowItem,
                  item.message?.id == messageId,
                  let attribute,
                  attribute.fullInstantPage != nil else {
                self.finishShowMore(keepExpanded: false)
                return
            }
            self.finishShowMore(keepExpanded: true)
            self.applyShowMoreExpansion(item: item, attribute: attribute)
        })
    }

    private func applyShowMoreExpansion(item: ChatRichTextRowItem, attribute: RichTextMessageAttribute) {
        guard let messageId = item.message?.id else {
            return
        }
        instantPageShowMoreExpandedMessageIds.insert(messageId)
        guard item.setShowMoreExpanded(true, attribute: attribute) else {
            return
        }
        _ = item.makeSize(item.width, oldWidth: 0)
        self.invalidateFrameCache()
        item.noteHeightOfRow(animated: true)
    }

    private func finishShowMore(keepExpanded: Bool) {
        if !keepExpanded {
            self.pendingQuoteFocus = nil
        }
        if !keepExpanded, let messageId = self.requestFullRichTextMessageId ?? self.lastShowMoreMessageId {
            instantPageShowMoreExpandedMessageIds.remove(messageId)
        }
        self.requestFullRichTextDisposable?.dispose()
        self.requestFullRichTextDisposable = nil
        self.requestFullRichTextMessageId = nil
        if let item = self.item as? ChatRichTextRowItem, let layout = item.showMoreLayout {
            self.showMoreControl.update(layout: layout, loading: false, animated: true)
        }
    }

    private func resetShowMore() {
        self.finishShowMore(keepExpanded: false)
        if let messageId = self.lastShowMoreMessageId {
            instantPageShowMoreExpandedMessageIds.remove(messageId)
        }
        self.lastShowMoreMessageId = nil
    }

    private func updateStreaming(item: ChatRichTextRowItem) {
        // The live-typing draft message keeps a fixed stableId across chunks, so the reveal
        // controller persists (cursor survives) while new chunks arrive. A different message
        // resets it.
        if self.lastRevealStableId != item.stableId {
            self.stopRevealLink()
            self.revealController = nil
            if let old = self.lastRevealStableId {
                instantPageStreamRevealCursors.removeValue(forKey: old)
            }
            self.lastRevealStableId = item.stableId
        }

        guard item.isRevealAnimationActive else {
            self.finishReveal(item: item)
            return
        }

        let costMap = item.richCostMap ?? item.richLayout.computeRevealCostMap()
        let now = CACurrentMediaTime()

        if item.isStreaming {
            if let controller = self.revealController, controller.isFinalizing {
                let currentCount = controller.currentGlyphCount
                self.stopRevealLink()
                self.revealController = TextRevealController(
                    initialRevealedCount: currentCount,
                    initialLength: costMap.total,
                    durationMultiplier: 10.0
                )
            } else if self.revealController == nil {
                self.revealController = TextRevealController(
                    initialRevealedCount: item.resolvedRevealCursor ?? 0,
                    initialLength: costMap.total,
                    durationMultiplier: 10.0
                )
            }
            self.revealController?.observeUpdate(latestLength: costMap.total, at: now)
        } else {
            if self.revealController == nil {
                self.revealController = TextRevealController(
                    initialRevealedCount: item.resolvedRevealCursor ?? 0,
                    initialLength: costMap.total,
                    durationMultiplier: 10.0
                )
            }
            self.revealController?.finalize(finalLength: costMap.total)
        }

        self.richView.setRevealCostMap(costMap)
        let seed = self.revealController?.currentGlyphCount ?? 0
        item.revealCursor = seed
        instantPageStreamRevealCursors[item.stableId] = seed
        self.richView.applyReveal(cursor: seed)

        if let controller = self.revealController,
           controller.isFinalizing,
           controller.revealedCount >= Double(controller.latestLength) {
            self.finishReveal(item: item)
            return
        }
        self.maybeStartRevealLink()
    }

    private func finishReveal(item: ChatRichTextRowItem) {
        let animateStatus = item.isRevealAnimationActive && !item.isStreaming
        let previousUnsupportedCount = item.revealedUnsupportedItems.count
        self.revealController = nil
        self.stopRevealLink()
        item.revealCursor = nil
        instantPageStreamRevealCursors.removeValue(forKey: item.stableId)
        self.richView.setRevealCostMap(nil)
        self.richView.applyReveal(cursor: nil)
        self.rightView.change(opacity: 1.0, animated: animateStatus, duration: 0.2, timingFunction: .easeInEaseOut)
        self.refreshUnsupportedBandsIfNeeded(item: item, previousCount: previousUnsupportedCount)
    }

    private func refreshUnsupportedBandsIfNeeded(item: ChatRichTextRowItem, previousCount: Int) {
        guard item.revealedUnsupportedItems.count != previousCount else { return }
        self.invalidateFrameCache()
        item.noteHeightOfRow(animated: false)
    }

    /// Starts the reveal display link only once there is real content to reveal (cost > 0, i.e. past
    /// the "Thinking…" no-content phase) and only while the view is mounted. Called both from
    /// `updateStreaming` (content/chunk arrived) and `viewDidMoveToWindow` (mounted), since either can
    /// be the moment both conditions first hold.
    private func maybeStartRevealLink() {
        guard self.revealLink == nil, self.window != nil else { return }
        guard let item = self.item as? ChatRichTextRowItem, item.isRevealAnimationActive, self.revealController != nil else { return }
        guard (item.richCostMap?.total ?? 0) > 0 else { return }
        self.startRevealLink()
    }

    private func startRevealLink() {
        if self.revealLink != nil { return }
        self.revealLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .max) { [weak self] _ in
            self?.revealTick()
        }
    }

    private func stopRevealLink() {
        self.revealLink?.invalidate()
        self.revealLink = nil
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if self.window != nil {
            self.maybeStartRevealLink()
        } else {
            self.stopRevealLink()
        }
    }

    private func revealTick() {
        guard let controller = self.revealController,
              let item = self.item as? ChatRichTextRowItem,
              item.isRevealAnimationActive else {
            self.stopRevealLink()
            return
        }
        let previousRevealedSize = item.isStreaming ? item.revealedRichContentSize : nil
        let previousUnsupportedCount = item.revealedUnsupportedItems.count
        let (count, isComplete) = controller.tick(now: CACurrentMediaTime())
        if isComplete {
            self.finishReveal(item: item)
            return
        }
        item.revealCursor = count
        instantPageStreamRevealCursors[item.stableId] = count
        self.richView.applyReveal(cursor: count)

        if let previousRevealedSize, previousRevealedSize != item.revealedRichContentSize {
            self.invalidateFrameCache()
            item.noteHeightOfRow(animated: true)
        } else {
            self.refreshUnsupportedBandsIfNeeded(item: item, previousCount: previousUnsupportedCount)
        }
    }

    private func updateBubbleClip(item: ChatRichTextRowItem, richFrame: NSRect) {
        guard item.isBubbled, item.hasBubble, item.hasFullBleedMedia, let corners = item.mediaBubbleCorners(inset: item.mediaBubbleCornerInset) else {
            self.richView.setBubbleClip(nil)
            return
        }
        let inset = item.mediaBubbleCornerInset
        let bubble = self.bubbleFrame(item)
        let content = self.contentFrame(item)
        var body = NSRect(
            x: bubble.minX + (item.isIncoming ? item.additionBubbleInset : 0),
            y: bubble.minY,
            width: bubble.width - item.additionBubbleInset,
            height: bubble.height
        )
        body = body.insetBy(dx: inset, dy: 0)
        body.origin.y += inset
        body.size.height -= inset
        let local = body.offsetBy(dx: -(content.minX + richFrame.minX), dy: -(content.minY + richFrame.minY))
        self.richView.setBubbleClip(local, corners: corners)
    }

    private func richFrame(_ item: ChatRichTextRowItem) -> NSRect {
        let textFrame = self.textFrame(item)
        let contentTop = textFrame.maxY + (item.textLayout.size.height > 0 ? item.defaultContentInnerInset : 0)
        return NSRect(
            x: 0,
            y: contentTop + (item.isStreaming ? item.topInset : 0),
            width: item.richLayout.contentSize.width,
            height: item.effectiveRichHeight
        )
    }

    /// An `.unsupported` block cuts the bubble in two across its full width, so the band's content is
    /// drawn straight onto the chat wallpaper. Rich-view coordinates → bubble-local coordinates.
    public override func cutBands(_ item: ChatRowItem) -> [CGRect] {
        guard let item = item as? ChatRichTextRowItem else {
            return super.cutBands(item)
        }
        guard item.isBubbled, item.hasBubble else {
            return []
        }
        let bands = item.unsupportedBands
        guard !bands.isEmpty else {
            return []
        }
        let bubble = self.bubbleFrame(item)
        let origin = self.contentFrame(item).minY + self.richFrame(item).minY - bubble.minY
        return bands.map {
            CGRect(x: 0, y: origin + $0.minY, width: bubble.width, height: $0.height)
        }
    }

    /// The three frosted surfaces each band carries — the rounded panel the row sits on, the icon
    /// silhouette with the plane punched out of it, and the lighter pill under the action label. Unlike
    /// the hole, these keep the band's own horizontal extent (the rich content column), which is what
    /// leaves the wallpaper sharp in the margins beside the panel.
    public override func frostedPanels(_ item: ChatRowItem) -> [ChatRowView.FrostedPanel] {
        guard let item = item as? ChatRichTextRowItem else {
            return super.frostedPanels(item)
        }
        guard item.isBubbled, item.hasBubble else {
            return []
        }
        let bubble = self.bubbleFrame(item)
        let content = self.contentFrame(item)
        let rich = self.richFrame(item)
        let origin = CGPoint(x: content.minX - bubble.minX, y: content.minY + rich.minY - bubble.minY)

        var result: [ChatRowView.FrostedPanel] = []
        for unsupported in item.revealedUnsupportedItems {
            result.append(contentsOf: (unsupported.layout as! ChatUnsupportedPapercutLayout).frostedPanels(in: unsupported.frame, offsetBy: origin))
        }
        return result
    }

    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        guard let item = self.item as? ChatRichTextRowItem else {
            self.richView.isHidden = true
            self.showMoreControl.isHidden = true
            self.richView.setBubbleClip(nil)
            transition.updateFrame(view: self.richView, frame: .zero)
            transition.updateFrame(view: self.showMoreControl, frame: .zero)
            return
        }
        self.richView.isHidden = false
        let richFrame = self.richFrame(item)
        transition.updateFrame(view: self.richView, frame: richFrame)
        self.updateBubbleClip(item: item, richFrame: richFrame)
        if let layout = item.showMoreLayout {
            self.showMoreControl.isHidden = false
            transition.updateFrame(view: self.showMoreControl, frame: CGRect(origin: CGPoint(x: 0, y: richFrame.maxY + instantPageShowMoreTopInset), size: layout.layoutSize))
        } else {
            self.showMoreControl.isHidden = true
            transition.updateFrame(view: self.showMoreControl, frame: .zero)
        }
    }
}

// MARK: - Read-only rich draft preview (composer)

/// Renders a composer's structural rich-text draft (an `InstantPage`) read-only via the timeline's
/// `InstantPageV2View`, for display above the chat input (the macOS analog of iOS's in-place rich input).
/// The page is hosted inside a scroll view so a draft taller than `maxPreviewHeight` scrolls within the
/// composer (like the plain text field), and a click on the content reopens the draft in the editor.
/// The scroll document for the draft preview. Swallows every hit so embedded media / links don't
/// intercept — a click anywhere reopens the editor — while scroll-wheel events forward to the scroll view.
private final class RichDraftDocumentView: Control {
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        return bounds.contains(local) ? self : nil
    }
    override func scrollWheel(with event: NSEvent) {
        enclosingScrollView?.scrollWheel(with: event)
    }
}

public final class RichTextDraftPreviewView: View {
    public static let maxPreviewHeight: CGFloat = 180
    /// The height cap before the content scrolls — the host sets this to the plain text view's max height so
    /// a rich draft grows to the same extent as normal typed text. Defaults to the standalone `maxPreviewHeight`.
    public var maxContentHeight: CGFloat = RichTextDraftPreviewView.maxPreviewHeight
    /// Top/bottom inset between the content and the preview edges (applied via the scroll view).
    public static let vInset: CGFloat = 6

    private let scrollView = NSScrollView()
    /// The scroll document — clickable (reopens the editor) and sized to the FULL content height.
    private let documentControl = RichDraftDocumentView()
    private let pageView = InstantPageV2View(frame: .zero)
    private var page: InstantPage?
    private var presentationTheme: TelegramPresentationTheme = theme
    private weak var chatInteraction: ChatInteraction?
    /// Reopen the draft in the editor when its content is clicked.
    public var onReopen: (() -> Void)?

    /// Editable text-only mode: when the draft carries no media we host a live `RichTextEditorView`
    /// (no toolbar; Return sends; new paragraphs forbidden) so the text can be edited in place. Stored as
    /// `NSView?` so the property isn't macOS-12-gated; reached via `richEditor`.
    private var editorView: NSView?
    private var isEditable = false
    /// Media backing the inline editor's blocks (synthetic `mediaID` → `Media`), so the host can compose +
    /// send the edited content with its media intact.
    private var mediaCache: [String: Media] = [:]
    private let imageLoadDisposable = DisposableSet()
    /// Fired when Return is pressed inside the inline editor (the host sends the current content).
    public var onSend: (() -> Void)?
    /// Fired when the inline editor's content height changes (the host re-measures the row).
    public var onEditorHeightChange: (() -> Void)?

    @available(macOS 12, *)
    private var richEditor: RichTextEditorView? { editorView as? RichTextEditorView }

    /// The inline editor's current content (media-preserving), or nil when not in editable mode. The host
    /// composes + sends this.
    public func currentOutgoing() -> [RichTextOutgoingBlock]? {
        if #available(macOS 12, *) { return richEditor?.outgoingBlocks() }
        return nil
    }

    /// The focusable inline editor view (only in editable mode), so the composer can route first-responder to
    /// it instead of the hidden plain-text field — making the draft text editable in place.
    public var editorResponder: NSView? { isEditable ? editorView : nil }

    /// The media backing the inline editor's current content — so the host resolves `mediaID`s when it
    /// composes + sends.
    public func currentMedia() -> [String: Media] { mediaCache }

    /// True while the live inline editor is shown (vs the read-only preview).
    public var isInlineEditing: Bool { isEditable }

    /// Undo / redo on the inline editor (host wires ⌘Z / ⌘⇧Z to these).
    public func undoInline() { if #available(macOS 12, *) { richEditor?.undo() } }
    public func redoInline() { if #available(macOS 12, *) { richEditor?.redo() } }

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.applyThemedVerticalScroller()
        scrollView.verticalScrollElasticity = .allowed
        // Top/bottom breathing room that survives scrolling (the content never sits flush against the
        // preview's edges).
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: RichTextDraftPreviewView.vInset, left: 0, bottom: RichTextDraftPreviewView.vInset, right: 0)
        scrollView.documentView = documentControl
        documentControl.addSubview(pageView)
        pageView.userInteractionEnabled = false
        // Clicking the rich text never opens the modal editor — only the expand icon does. (A text-only draft
        // is the live inline editor and edits on click; a media draft's read-only preview is inert.)
        addSubview(scrollView)
        layer?.masksToBounds = true
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override func layout() {
        super.layout()
        scrollView.frame = bounds
    }

    /// Re-lays the stored draft at a new width (used by the host on resize). Returns the capped height.
    @discardableResult
    public func relayout(width: CGFloat) -> CGFloat {
        // In editable mode just re-measure the live editor (re-seeding would reset the caret); the read-only
        // preview re-lays its stored page.
        if #available(macOS 12, *), isEditable {
            return measureEditable(width: width)
        }
        guard let page = self.page else { return 0 }
        return update(instantPage: page, width: width, chatInteraction: chatInteraction, theme: presentationTheme)
    }

    // MARK: - Editable text-only mode

    /// Hosts (or refreshes) the live inline editor, seeded from the text-only draft. Re-seeds on each call
    /// (an external draft change); per-keystroke growth goes through `relayout` → `measureEditable` instead,
    /// so the caret isn't reset while typing.
    @available(macOS 12, *)
    private func updateEditable(instantPage: InstantPage, width: CGFloat) -> CGFloat {
        isEditable = true
        scrollView.isHidden = true
        let isNew = richEditor == nil
        let editor: RichTextEditorView
        if let existing = richEditor {
            editor = existing
        } else {
            editor = RichTextEditorView(frame: .zero)
            editor.isScrollEnabled = true
            editor.showsScroller = false
            editor.showsTableControls = false
            editor.pasteFragmentProvider = { ChatHistoryUIHooks.shared.richTextHooks.blocksFromInAppPasteboard() }
            editor.withPasteContext = { [weak self] paste in
                paste()
            }
            // Return follows the plain-input send preference: the configured send combo (Enter, or ⌘/⇧-Enter)
            // sends; any other Return combo falls through (returns false) so the editor inserts a newline.
            editor.onReturnKey = { [weak self] in
                guard let self = self, let event = NSApp.currentEvent, FastSettings.checkSendingAbility(for: event) else { return false }
                self.onSend?()
                return true
            }
            editor.onContentHeightChange = { [weak self] in self?.onEditorHeightChange?() }
            // Render custom-emoji atoms as the app's animated inline stickers (same provider as the modal
            // editor) — without this an inline draft's custom emoji draw as blanks.
            if let context = self.chatInteraction?.interactionContext {
                editor.registerEmojiViewProvider { id, size in
                    guard let fileId = Int64(id) else { return nil }
                    let emoji = ChatTextCustomEmojiAttribute(fileId: fileId, file: nil, emoji: "")
                    return InlineStickerView(account: context.account, inlinePacksContext: context.inlinePacksContext,
                                             emoji: emoji, size: size)
                }
            }
            // Same libprisma highlighter the modal editor registers — without it a code block in the
            // inline draft renders plain while the identical document highlights in the modal and in the
            // sent bubble.
            ChatHistoryUIHooks.shared.richTextHooks.installSyntaxHighlighter(editor, { [weak self] in
                self?.presentationTheme ?? theme
            })
            // Host media blocks (map / file / audio / video) and media groups (collage / slider) with the
            // same chat content nodes the modal editor uses, backed by the draft's media cache — so a
            // media-bearing draft edits in place (its caption is a normal editable region).
            if let interaction = self.chatInteraction {
                let context = interaction.interactionContext
                editor.registerMediaBlockViewProvider { [weak self] _, mediaID, spoiler, width in
                    guard let media = self?.mediaCache[mediaID] else { return nil }
                    return ChatHistoryUIHooks.shared.richTextHooks.makeMediaContentView(media, width, spoiler,
                                                                          context, interaction)
                }
                editor.registerMediaBlockViewTeardown { view in
                    guard let content = view as? ChatMediaContentView else { return }
                    content.willRemove()
                    content.clean()
                }
                editor.registerMediaGroupMosaic { [weak self] mediaIDs, maxWidth in
                    var messages: [Message] = []
                    for (i, mid) in mediaIDs.enumerated() {
                        guard let media = self?.mediaCache[mid] else { continue }
                        messages.append(Message(media, stableId: UInt32(truncatingIfNeeded: i + 1),
                                                messageId: MessageId(peerId: PeerId(0), namespace: Namespaces.Message.Local, id: Int32(i))))
                    }
                    guard messages.count == mediaIDs.count, !messages.isEmpty else { return [] }
                    let grouped = GroupedLayout(messages, type: .photoOrVideo)
                    grouped.measure(NSMakeSize(maxWidth, min(maxWidth, 320.0)), spacing: 2.0)
                    return (0 ..< grouped.count).map { grouped.frame(at: $0) }
                }
                editor.registerMediaGroupTileProvider { [weak self] mediaID, spoiler, size in
                    guard let media = self?.mediaCache[mediaID] else { return nil }
                    return ChatHistoryUIHooks.shared.richTextHooks.makeCollageTileView(media, size, spoiler,
                                                                         context, interaction)
                }
                editor.registerMediaGroupSliderProvider { [weak self] mediaIDs, width in
                    ChatHistoryUIHooks.shared.richTextHooks.makeSliderView(mediaIDs, width,
                                                             { self?.mediaCache[$0] }, context)
                }
            }
            addSubview(editor)
            editor.spoilerEffectProvider = { _ in ChatHistoryUIHooks.shared.richTextHooks.makeSpoilerEffect() }
            self.editorView = editor
        }
        // Inline in the composer we want the text to sit close to the left edge (like the plain input), not
        // behind a wide document margin — so drop the editor's horizontal content margin.
        editor.contentMargin = 0
        // Match the modal editor's appearance so selections (incl. the image-selection wash) are a translucent
        // accent tint over the content, not an opaque fill.
        let colors = presentationTheme.colors
        // Button pill slots mirror `buildInstantPageTheme`'s non-bubbled incoming derivation, so the
        // editor's pills match the rendered message: inline neutral = (panelBackground, panelAccent),
        // block neutral = (tableHeader, panelPrimary), primary = (checkboxFill, checkboxForeground).
        editor.editorAppearance = EditorAppearance(
            caretColor: colors.text,
            selectionFocused: colors.accent.withAlphaComponent(0.7),
            selectionUnfocused: colors.accent.withAlphaComponent(0.5),
            background: .clear,
            linkColor: colors.link,
            inlineCodeBackground: colors.grayBackground,
            defaultForeground: colors.text,
            secondaryForeground: colors.grayText,
            spoilerCoverColor: colors.grayText,
            codeAccent: colors.accent,
            isDark: colors.isDark,
            buttonNeutralFill: colors.accent.withAlphaComponent(0.1),
            buttonNeutralLabel: colors.accent,
            buttonNeutralBlockFill: colors.isDark ? colors.accent.withAlphaComponent(0.1) : NSColor(rgb: 0x000000, alpha: 0.05),
            buttonNeutralBlockLabel: colors.text,
            buttonPrimaryFill: colors.accent,
            buttonPrimaryLabel: NSColor(rgb: 0xffffff),
            buttonDanger: colors.redUI,
            buttonSuccess: colors.isDark ? NSColor(rgb: 0x30cf30) : NSColor(rgb: 0x26972c)
        )
        editor.isHidden = false
        let hInset: CGFloat = 4
        let avail = max(40, width - hInset * 2)
        editor.frame = NSMakeRect(hInset, RichTextDraftPreviewView.vInset, avail, max(1, editor.frame.height))
        // Seed only when creating the editor or when the change is EXTERNAL (editor not focused). While the
        // user is actively editing, the editor is the live source of truth — re-seeding (e.g. from our own
        // draft-sync round-trip) would reset the caret.
        let focused = (window?.firstResponder as? NSView).map { $0 === editor || $0.isDescendant(of: editor) } ?? false
        if isNew || !focused {
            let (blocks, media) = richTextOutgoing(from: instantPage)
            self.mediaCache = media
            editor.setOutgoingBlocks(blocks)
            editor.moveCaretToEnd()
        }
        return measureEditable(width: width)
    }

    deinit {
        imageLoadDisposable.dispose()
    }

    @available(macOS 12, *)
    private func measureEditable(width: CGFloat) -> CGFloat {
        guard let editor = richEditor else { return 0 }
        let hInset: CGFloat = 4
        let vInset = RichTextDraftPreviewView.vInset
        let avail = max(40, width - hInset * 2)
        let full = editor.contentHeight
        let visible = min(full, maxContentHeight - vInset * 2)
        editor.frame = NSMakeRect(hInset, vInset, avail, max(1, visible))
        return min(full + vInset * 2, maxContentHeight)
    }

    /// Supplies `InstantPageV2View` what it needs to render embedded media (photo/video/file/map/audio):
    /// a synthetic local parent `Message` carrying the media + the matching layout parameters. Without it,
    /// media falls back to grey placeholders.
    private func makeMediaConfig(_ chatInteraction: ChatInteraction, _ presentationTheme: TelegramPresentationTheme) -> (Media, CGSize, Int, Bool) -> (parent: Message, parameters: ChatMediaLayoutParameters)? {
        return { [weak chatInteraction] media, size, _, isFile in
            guard let interaction = chatInteraction else { return nil }
            let context = interaction.interactionContext
            let parent = Message(stableId: 0, stableVersion: 0,
                                 id: MessageId(peerId: interaction.peerId, namespace: Namespaces.Message.Local, id: 0),
                                 globallyUniqueId: 0, groupingKey: 0, groupInfo: nil, threadId: nil,
                                 timestamp: 0, flags: [], tags: [], globalTags: [], localTags: [], customTags: [],
                                 forwardInfo: nil, author: nil, text: "", attributes: [], media: [media],
                                 peers: SimpleDictionary(), associatedMessages: SimpleDictionary(),
                                 associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
            let presentation = ChatMediaPresentation.make(for: parent, account: context.account, renderType: .bubble, theme: presentationTheme)
            if let map = media as? TelegramMediaMap {
                let scale: CGFloat = 2.0
                var pw = max(1, Int((size.width > 0 ? size.width : 320) * scale))
                var ph = max(1, Int((size.height > 0 ? size.height : 120) * scale))
                let maxW = 1280
                if pw > maxW {
                    ph = Int(CGFloat(ph) * CGFloat(maxW) / CGFloat(pw))
                    pw = maxW
                }
                let resource = MapSnapshotMediaResource(latitude: map.latitude, longitude: map.longitude, width: Int32(pw), height: Int32(ph), zoom: 15)
                let parameters = ChatMediaMapLayoutParameters(map: map, resource: resource, presentation: presentation, automaticDownload: true, execute: {}, imageSize: size.width > 0 && size.height > 0 ? size : nil, cornerRadius: 8)
                return (parent, parameters)
            }
            if isFile, let file = media as? TelegramMediaFile {
                let parameters = ChatMediaLayoutParameters.layout(
                    for: file,
                    isWebpage: true,
                    chatInteraction: interaction,
                    presentation: presentation,
                    automaticDownload: true,
                    isIncoming: false,
                    isFile: true,
                    autoplayMedia: AutoplayMediaPreferences.defaultSettings,
                    isChatRelated: true
                )
                return (parent, parameters)
            }
            if let file = media as? TelegramMediaFile, file.isMusic || file.isVoice {
                let parameters = ChatMediaLayoutParameters.layout(for: file, isWebpage: true, chatInteraction: interaction, presentation: presentation, automaticDownload: true, isIncoming: false, autoplayMedia: AutoplayMediaPreferences.defaultSettings, isChatRelated: true)
                return (parent, parameters)
            }
            // Photo / video / generic file → the standard gallery parameters; tapping is a no-op here
            // (the whole preview reopens the editor on click).
            let parameters = ChatMediaGalleryParameters(showMedia: { _ in }, showMessage: { _ in }, isWebpage: true, media: media, automaticDownload: true)
            return (parent, parameters)
        }
    }

    /// Lays the draft out at `width` and returns the (capped) height the host should reserve.
    @discardableResult
    public func update(instantPage: InstantPage, width: CGFloat, chatInteraction: ChatInteraction?, theme presentationTheme: TelegramPresentationTheme) -> CGFloat {
        self.page = instantPage
        self.presentationTheme = presentationTheme
        self.chatInteraction = chatInteraction
        // Every draft edits in the live inline editor: media blocks (map / video / file-audio) and media
        // groups (collage / slider) are hosted with the same chat content nodes as the modal editor, so
        // their captions are ordinary editable regions.
        if #available(macOS 12, *) {
            return updateEditable(instantPage: instantPage, width: width)
        }
        isEditable = false
        editorView?.isHidden = true
        scrollView.isHidden = false
        pageView.context = chatInteraction?.interactionContext
        pageView.mediaContentConfig = chatInteraction.map { self.makeMediaConfig($0, presentationTheme) }
        let webpage = TelegramMediaWebpage(
            webpageId: MediaId(namespace: 0, id: 0),
            content: .Loaded(TelegramMediaWebpageLoadedContent(
                url: "", displayUrl: "", hash: 0, type: nil,
                websiteName: nil, title: nil, text: nil,
                embedUrl: nil, embedType: nil, embedSize: nil, duration: nil,
                author: nil, isMediaLargeByDefault: nil, imageIsVideoCover: false,
                image: nil, file: nil, story: nil, attributes: [],
                instantPage: instantPage
            ))
        )
        let ipTheme = ChatRichTextRowItem.buildInstantPageTheme(for: presentationTheme, isIncoming: true, isBubbled: false)
        // Inset the content so full-width blocks (code, tables, media) don't touch the pill's rounded edges
        // (`hInset` sides), and `pad` keeps the clip edge off the text baseline (descenders aren't shaved).
        let hInset: CGFloat = 8
        let pad: CGFloat = 3
        // Lay out at the content width; if the result overflows the cap (so it scrolls), re-lay reserving the
        // overlay scroller's width on the right so text doesn't run under it.
        func makeLayout(_ w: CGFloat) -> (InstantPageV2Layout, CGFloat) {
            let l = layoutInstantPageV2(webpage: webpage, instantPage: instantPage, boundingWidth: max(40, w), horizontalInset: 0, theme: ipTheme)
            let bottom = l.items.map { $0.frame.maxY }.max() ?? l.contentSize.height
            return (l, bottom + pad * 2)
        }
        let vInset = RichTextDraftPreviewView.vInset
        // Total preview height = document + top/bottom scroll insets; it scrolls once that exceeds the cap.
        func previewHeight(_ docHeight: CGFloat) -> CGFloat { docHeight + vInset * 2 }
        var layoutWidth = width - hInset * 2
        var (layout, docHeight) = makeLayout(layoutWidth)
        if previewHeight(docHeight) > maxContentHeight {
            let scrollerReserve: CGFloat = 14
            layoutWidth = width - hInset - (hInset + scrollerReserve)
            (layout, docHeight) = makeLayout(layoutWidth)
        }
        layoutWidth = max(40, layoutWidth)
        pageView.update(layout: layout, theme: ipTheme)
        // Document holds the FULL content; the scroll view (sized to the capped height by the host, with
        // vertical content insets) scrolls when the document overflows it.
        documentControl.frame = NSMakeRect(0, 0, width, docHeight)
        pageView.frame = NSMakeRect(hInset, pad, layoutWidth, layout.contentSize.height)
        scrollView.frame = bounds
        return min(previewHeight(docHeight), maxContentHeight)
    }
}

@available(macOS 12, *)
extension RichTextEditorView: @retroactive HorizontalScrollConsuming {
    public func consumesHorizontalScroll(atWindowPoint windowPoint: NSPoint) -> Bool {
        return consumesHorizontalPan(atWindowPoint: windowPoint)
    }
}
