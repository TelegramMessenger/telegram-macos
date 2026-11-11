import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import LocalAnimations
import ChatHistoryModel
import TelegramContext
import TelegramTheme
import AlertsUI
import HTMLBubbles
import WidgetSandbox
import InputTextView
import InlineStickerLayer
import TelegramUtils

public final class ChatHTMLRowItem: ChatRowItem, HTMLTwidgetRow {
    public let state: HTMLBubbleState
    public let appearance: HTMLBubbleAppearance
    public private(set) var renderWidth: CGFloat = 0
    fileprivate private(set) var eagerRendering: HTMLBubbleRendering?
    private var isSingleLine: Bool = false
    private let fontSize: CGFloat
    let isDocument: Bool
    fileprivate let widget: TelegramMediaWidget?
    private let previewHeightDidChange: (() -> Void)?
    private let documentStyle: HTMLDocumentBubbles.Style?
    private let documentWidth: CGFloat

    public convenience override init(_ initialSize: NSSize, _ chatInteraction: ChatInteraction, _ context: any AccountContextProtocol, _ object: ChatHistoryEntry, theme: TelegramPresentationTheme) {
        self.init(initialSize, chatInteraction, context, object, theme: theme, document: nil)
    }

    public convenience init(_ initialSize: NSSize, _ chatInteraction: ChatInteraction, _ context: any AccountContextProtocol, _ entry: ChatHistoryEntry, theme: TelegramPresentationTheme, previewWidget: TelegramMediaWidget, heightDidChange: @escaping () -> Void) {
        let state = HTMLWidgetStore.preview(widget: previewWidget, locale: appCurrentLanguage.languageCode)
        self.init(initialSize, chatInteraction, context, entry, theme: theme, document: nil, widget: previewWidget, widgetState: state, previewHeightDidChange: heightDidChange)
    }

    init(_ initialSize: NSSize, _ chatInteraction: ChatInteraction, _ context: any AccountContextProtocol, _ object: ChatHistoryEntry, theme: TelegramPresentationTheme, document: HTMLBubbleState?, widget: TelegramMediaWidget? = nil, widgetState: HTMLBubbleState? = nil, previewHeightDidChange: (() -> Void)? = nil) {
        let message = object.message!
        let state = widgetState ?? document ?? message.htmlBubbleState!
        self.state = state
        self.widget = widget
        self.previewHeightDidChange = previewHeightDidChange
        self.isDocument = document != nil
        self.documentStyle = document != nil ? HTMLDocumentBubbles.style : nil
        self.documentWidth = document != nil ? HTMLDocumentBubbles.bubbleWidth(state.source) : 0
        let incoming = message.isIncoming(context.account, object.renderType == .bubble)
        self.appearance = HTMLBubbleStyle.appearance(theme: theme, incoming: incoming)
        self.fontSize = theme.fontSize
        super.init(initialSize, chatInteraction, context, object, theme: theme)
        if let widget, !isWidgetPreview {
            state.widgetRequestHandler = { [weak context] request, complete in
                guard let context else { complete(.failure(.failed)); return }
                guard !request.wallet || ChatNavigationHooks.shared.widgetWalletAvailable(context) else { complete(.failure(.notAllowed)); return }
                _ = context.engine.messages.requestBotWidgetQueryAnswer(messageId: message.id, queryType: .data(withWallet: request.wallet), data: Data(request.data.utf8)).start(next: { data in
                    complete(.success(WidgetRequestAnswer(result: data.flatMap { String(data: $0, encoding: .utf8) })))
                }, error: { error in
                    switch error {
                    case .timeout: complete(.failure(.timeout))
                    case .rateLimited: complete(.failure(.rateLimited))
                    case .failed: complete(.failure(.failed))
                    }
                })
            }
            state.widgetWalletHandler = { [weak context] call, complete in
                guard let context else { complete(.failure(.failed)); return }
                ChatNavigationHooks.shared.openWidgetWallet(context, message, call, complete)
            }
            state.widgetCopyHandler = { [weak context] text in
                copyToClipboard(text)
                if let context { showModalText(for: context.window, text: text) }
            }
            HTMLWidgetPublicData.shared.attach(state: state, widget: widget, account: context.account, messages: context.engine.messages, messageId: message.id)
        }
        if widget != nil, !message.text.isEmpty {
            makeCaption(message: message, entry: object, context: context, theme: theme, incoming: incoming)
        }
    }

    private func makeCaption(message: Message, entry: ChatHistoryEntry, context: any AccountContextProtocol, theme: TelegramPresentationTheme, incoming: Bool) {
        let bubbled = entry.renderType == .bubble
        var text = message.text
        var entities = message.textEntities?.entities ?? []
        var isLoading = false
        if let translate = entry.additionalData.translate {
            switch translate {
            case .loading:
                isLoading = true
            case let .complete(toLang):
                if let attribute = message.translationAttribute(toLang: toLang) {
                    text = attribute.text
                    entities = attribute.entities
                }
            }
        }
        let caption = ChatMessageItem.applyMessageEntities(with: [TextEntitiesMessageAttribute(entities: entities)], for: text, message: message, context: context, fontSize: theme.fontSize, openInfo: chatInteraction.openInfo, botCommand: chatInteraction.sendPlainText, hashtag: chatInteraction.hashtag, applyProxy: chatInteraction.applyProxy, textColor: theme.chat.textColor(incoming, bubbled), linkColor: theme.chat.linkColor(incoming, bubbled), monospacedPre: theme.chat.monospacedPreColor(incoming, bubbled), monospacedCode: theme.chat.monospacedCodeColor(incoming, bubbled), mediaDuration: nil, timecode: { _ in
        }, openBank: chatInteraction.openBank, blockColor: theme.chat.blockColor(context.peerNameColors, message: message, isIncoming: incoming, bubbled: bubbled), isDark: theme.colors.isDark, bubbled: bubbled, codeSyntaxData: entry.additionalData.codeSyntaxData, loadCodeSyntax: chatInteraction.interactionEnqueueCodeSyntax, openPhoneNumber: chatInteraction.openPhoneNumberContextMenu, openTonAddress: chatInteraction.openTonAddressContextMenu, ignoreLinks: !entry.additionalData.canHighlightLinks && incoming).mutableCopy() as! NSMutableAttributedString
        caption.removeWhitespaceFromQuoteAttribute()
        InlineStickerItem.apply(to: caption, associatedMedia: message.associatedMedia, entities: entities, isPremium: context.isPremium)
        let spoilerColor = bubbled ? theme.chat.grayText(incoming, bubbled) : theme.chat.textColor(incoming, bubbled)
        let isSpoilerRevealed = chatInteraction.presentation.interfaceState.revealedSpoilers.contains(message.id)
        let textLayout = FoldingTextLayout.make(caption, context: context, revealed: entry.additionalData.quoteRevealed, takeLayout: { [weak self] string in
            let textLayout = TextViewLayout(string, alignment: .left, selectText: theme.chat.selectText(incoming, bubbled), strokeLinks: bubbled, alwaysStaticItems: true, disableTooltips: false, mayItems: !message.isCopyProtected(cachedData: self?.chatInteraction.presentation.cachedData), spoilerColor: spoilerColor, isSpoilerRevealed: isSpoilerRevealed, onSpoilerReveal: { [weak self] in
                self?.chatInteraction.update({
                    $0.updatedInterfaceState({
                        $0.withRevealedSpoiler(message.id)
                    })
                })
            })
            if let highlightFoundText = entry.additionalData.highlightFoundText, let range = rangeOfSearch(highlightFoundText.query, in: caption.string) {
                textLayout.additionalSelections = [TextSelectedRange(range: range, color: theme.colors.accentIcon.withAlphaComponent(0.5), def: false)]
            }
            return textLayout
        })
        captionLayouts.append(.init(message: message, id: message.stableId, offset: CGPoint(x: 0, y: 0), layout: textLayout, isLoading: isLoading, contentInset: ChatRowItem.defaultContentInnerInset))
        captionLayouts[0].layout.applyRanges(selectManager.findAll(entry.stableId))
        let interactions = LinkHooks.shared.globalLinkExecutor()
        interactions.copyToClipboard = { text in
            copyToClipboard(text)
            showModalText(for: context.window, text: strings().shareLinkCopied)
        }
        interactions.menuItems = { [weak self, weak textLayout] type in
            if let self = self, let textLayout = textLayout {
                return chatMenuItems(for: message, entry: entry, textLayout: (textLayout.merged, type), chatInteraction: self.chatInteraction)
            }
            return .complete()
        }
        textLayout.set(interactions)
    }

    public var htmlTwidgetState: HTMLBubbleState {
        return state
    }

    public var htmlTwidgetAppearance: HTMLBubbleAppearance {
        return appearance
    }

    public var htmlTwidgetWidth: CGFloat {
        return renderWidth
    }

    fileprivate var isWidgetPreview: Bool {
        return previewHeightDidChange != nil
    }

    var hasFullScreen: Bool {
        return !isWidgetPreview && state.scene3D != nil
    }

    fileprivate func openFullScreen() {
        guard let url = HTMLBubblePage.write(source: state.source, appearance: appearance) else {
            return
        }
        ChatNavigationHooks.shared.openHTMLPage(context, url)
    }

    fileprivate var autoRefresh: (interval: TimeInterval, data: MemoryBuffer)? {
        guard isDocument, HTMLDocumentAutoRefresh.isEnabled, let message = message, let interval = HTMLDocumentAutoRefresh.interval(state.source), let data = HTMLDocumentAutoRefresh.refreshCallback(in: message) else {
            return nil
        }
        return (interval, data)
    }

    fileprivate func handleDocumentLink(_ url: String) {
        guard url.lowercased().hasPrefix("https:") else {
            return
        }
        let link = ChatHistoryLink.inApp(for: url as NSString, context: context, peerId: message?.id.peerId, messageId: message?.id, openInfo: chatInteraction.openInfo, confirm: true)
        ChatHistoryLink.execute(inapp: link)
    }

    fileprivate func handleWidgetAction(_ action: HTMLWidgetAction) {
        guard !HTMLWidgetLinkPrompt.isShown else {
            return
        }
        switch action {
        case let .openLink(url):
            confirmWidgetLink(url) {
                NSWorkspace.shared.open(url)
            }
        case let .openTelegramLink(url):
            let link = ChatHistoryLink.inApp(for: url.absoluteString as NSString, context: context, peerId: message?.id.peerId, messageId: message?.id, openInfo: chatInteraction.openInfo)
            ChatHistoryLink.execute(inapp: link)
        }
    }

    private func confirmWidgetLink(_ url: URL, open: @escaping () -> Void) {
        HTMLWidgetLinkPrompt.isShown = true
        let done = { HTMLWidgetLinkPrompt.isShown = false }
        verifyAlert_button(for: context.window, header: strings().inAppLinksConfirmOpenExternalHeader, information: strings().inAppLinksConfirmOpenExternalNew(url.absoluteString), ok: strings().inAppLinksConfirmOpenExternalOK, cancel: strings().modalCancel, successHandler: { _ in
            done()
            open()
        }, cancelHandler: done, onDeinit: done)
    }

    public override func viewClass() -> AnyClass {
        return ChatHTMLRowView.self
    }

    public var isFullsize: Bool {
        if widget != nil {
            return false
        }
        switch documentStyle {
        case .bubble:
            return false
        case .card, .bare:
            return true
        default:
            return !state.isWidget
        }
    }

    var isCard: Bool {
        return documentStyle == .card
    }

    var isWidgetFill: Bool {
        return widget != nil && state.isWidgetMessage && renderType == .bubble
    }

    var mediaBubbleCornerInset: CGFloat {
        return 1
    }

    private var hasUpsideSomething: Bool {
        return authorText != nil || replyModel != nil || topicLinkLayout != nil || forwardNameLayout != nil
    }

    public override var contentOffset: NSPoint {
        if isWidgetFill {
            return upsideContentOffset(super.contentOffset, hasUpsideSomething: hasUpsideSomething)
        }
        return super.contentOffset
    }

    public override var elementsContentInset: CGFloat {
        if isWidgetFill, hasBubble {
            return bubbleContentInset - mediaBubbleCornerInset
        }
        return super.elementsContentInset
    }

    public override var _defaultHeight: CGFloat {
        if isWidgetFill, hasBubble, isStateOverlayLayout {
            return contentOffset.y + 2 + mediaBubbleCornerInset + (invertMedia && !captionLayouts.isEmpty ? defaultContentInnerInset : 0)
        }
        return super._defaultHeight
    }

    public override var realContentSize: NSSize {
        var size = super.realContentSize
        if isWidgetFill {
            size.width -= bubbleContentInset * 2
        }
        return size
    }

    public override var bubbleFrame: NSRect {
        if isWidgetFill {
            return fullFilledBubbleFrame(super.bubbleFrame, mediaBubbleCornerInset: mediaBubbleCornerInset)
        }
        return super.bubbleFrame
    }

    var cardInsets: NSEdgeInsets {
        return isCard ? NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14) : NSEdgeInsets()
    }

    public override var additionalLineForDateInBubbleState: CGFloat? {
        if isCard {
            return nil
        }
        if isWidgetFill, isStateOverlayLayout {
            return nil
        }
        if isWidgetFill, captionLayouts.isEmpty {
            return rightSize.height
        }
        return super.additionalLineForDateInBubbleState
    }

    public override var hasBubble: Bool {
        get {
            return !isFullsize && super.hasBubble
        }
        set {
            super.hasBubble = newValue
        }
    }

    public override var isBubbleFullFilled: Bool {
        return isFullsize || isWidgetFill || super.isBubbleFullFilled
    }

    public override var isStateOverlayLayout: Bool {
        if isWidgetFill {
            return super.isStateOverlayLayout
        }
        if isCard {
            return false
        }
        if documentStyle == .bubble, renderType == .bubble {
            return true
        }
        return isFullsize && renderType == .bubble || super.isStateOverlayLayout
    }

    public override var bubbleContentInset: CGFloat {
        return isFullsize && renderType == .bubble ? 0 : super.bubbleContentInset
    }

    public override var min_block_width: CGFloat {
        if let widget = widget {
            return widget.width > 0 ? min(max(CGFloat(widget.width), HTMLWidgetPayload.minimumWidth), super.min_block_width) : super.min_block_width
        }
        if documentStyle == .bubble || documentStyle == .bare || isCard {
            return documentWidth
        }
        return isFullsize ? .greatestFiniteMagnitude : 560
    }

    public override var rightSize: NSSize {
        if isFullsize, renderType == .bubble, !isCard {
            return .zero
        }
        return super.rightSize
    }

    public override func makeContentSize(_ width: CGFloat) -> NSSize {
        let insets = cardInsets
        renderWidth = floor(max(width - insets.left - insets.right, 40))
        if let widget = widget, widget.width > 0 {
            renderWidth = min(renderWidth, max(CGFloat(widget.width), HTMLWidgetPayload.minimumWidth))
        }
        if state.engine.usesWidgetSandbox {
            state.prepareTwidget(appearance: appearance, width: renderWidth, wait: 0.025)
            observeTwidgetHeight()
        }
        let size = state.layout(width: renderWidth, appearance: appearance)
        let scrollable = size.width > renderWidth + 0.5
        isSingleLine = !scrollable && size.height < fontSize * 2.4
        if Thread.isMainThread || state.isScripted || state.engine.usesWidgetSandbox {
            eagerRendering = nil
        } else {
            eagerRendering = HTMLBubbleRenderer.renderEagerly(state: state, appearance: appearance, width: renderWidth, scale: System.backingScale)
        }
        let height = size.height + (scrollable ? HTMLBubbleView.scrollIndicatorInset : 0) + state.statsReservedHeight
        if isCard {
            return NSMakeSize(renderWidth + insets.left + insets.right, max(height, 1) + insets.top + insets.bottom)
        }
        if isWidgetFill, hasBubble {
            return NSMakeSize(renderWidth, max(height, 1))
        }
        if widget != nil, !captionLayouts.isEmpty {
            return NSMakeSize(renderWidth, max(height, 1))
        }
        return NSMakeSize(max(min(size.width, renderWidth), 1), max(height, 1))
    }

    private var twidgetObserver: Int?

    private func observeTwidgetHeight() {
        let observe = { [weak self] in
            guard let self = self, self.twidgetObserver == nil else {
                return
            }
            self.twidgetObserver = self.state.addObserver { [weak self] in
                self?.twidgetHeightChanged()
            }
        }
        if Thread.isMainThread {
            observe()
        } else {
            DispatchQueue.main.async(execute: observe)
        }
    }

    private func twidgetHeightChanged() {
        guard table != nil, index != -1, view == nil else {
            return
        }
        let size = state.layout(width: renderWidth, appearance: appearance)
        let insets = cardInsets
        if abs(size.height + state.statsReservedHeight + insets.top + insets.bottom - contentSize.height) > 0.5 {
            copyAndUpdate(animated: false)
        }
    }

    deinit {
        if let token = twidgetObserver {
            let state = self.state
            DispatchQueue.main.async {
                state.removeObserver(token)
            }
        }
    }

    fileprivate func consumeEagerRendering() -> HTMLBubbleRendering? {
        let rendering = eagerRendering
        eagerRendering = nil
        return rendering
    }

    public override var lastLineContentWidth: ChatRowItem.LastLineData? {
        if !captionLayouts.isEmpty {
            return super.lastLineContentWidth
        }
        return .init(width: contentSize.width, single: isSingleLine)
    }

    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        var items = super.menuItems(in: location)
        #if DEBUG
        let source = state.source
        let window = context.window
        items = items |> map { items in
            return items + [ContextSeparatorItem(), ContextMenuItem("Copy HTML (dev)", handler: {
                copyToClipboard(source)
                showModalText(for: window, text: "Copied")
            }, itemMode: .normal, itemImage: MenuAnimation.menu_copy.value)]
        }
        #endif
        guard let text = (view as? ChatHTMLRowView)?.selectedText else {
            return items
        }
        let copy = ContextMenuItem(strings().chatCopySelectedText, handler: {
            copyToClipboard(text)
        }, itemImage: MenuAnimation.menu_copy.value)
        return items |> map { [copy, ContextSeparatorItem()] + $0 }
    }

    fileprivate var htmlFrame: NSRect {
        let insets = cardInsets
        let width = isWidgetFill && hasBubble ? renderWidth : contentSize.width - insets.left - insets.right
        return NSMakeRect(insets.left, insets.top, max(width, 1), max(contentSize.height - insets.top - insets.bottom, 1))
    }

    public override func resizeAnchor(previous: TableRowItem) -> TableRowResizeAnchor? {
        guard state.engine.usesWidgetSandbox, let previous = previous as? ChatHTMLRowItem, let view = previous.view as? ChatHTMLRowView, view.window != nil, let table = previous.table else {
            return super.resizeAnchor(previous: previous)
        }
        let oldHeight = previous.htmlFrame.height
        let newHeight = htmlFrame.height
        guard abs(oldHeight - newHeight) > 0.5 else {
            return super.resizeAnchor(previous: previous)
        }
        let sticksToBottom = table.isAtBottom
        let reserved = state.statsReservedHeight
        let click = HTMLRowClick.point(in: view.htmlContent)
        state.twidgetPrefersBottom(sticksToBottom)
        let resize = state.twidgetResize(oldHeight: oldHeight - reserved, newHeight: newHeight - reserved)
        let anchor: TableRowResizeAnchor
        if let widgetAnchor = state.twidgetMessageResizeAnchor(width: renderWidth, oldHeight: oldHeight, newHeight: newHeight) {
            anchor = widgetAnchor
        } else if click == nil, sticksToBottom {
            anchor = .bottom(oldHeight: oldHeight, newHeight: newHeight)
        } else if click != nil, let from = resize?.pointerFrom, let to = resize?.pointerTo {
            anchor = .pointer(from: from, to: to, oldHeight: oldHeight, newHeight: newHeight)
        } else if let resize = resize {
            let point = click ?? (resize.keepsBottom ? oldHeight : 0)
            anchor = TableRowResizeAnchor(from: point, to: resize.keepsBottom ? point + newHeight - oldHeight : point)
        } else {
            anchor = TableRowResizeAnchor.resolve(oldHeight: oldHeight, newHeight: newHeight, click: click, sticksToBottom: sticksToBottom)
        }
        let top = view.htmlContentTop
        return TableRowResizeAnchor(from: anchor.from + top, to: anchor.to + top)
    }

    public override func copyAndUpdate(animated: Bool) {
        guard let previewHeightDidChange else {
            super.copyAndUpdate(animated: animated)
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, let table = self.table, table.item(stableId: self.stableId) === self else { return }
            let oldHeight = self.height
            let oldContentSize = self.contentSize
            self.previousBlockWidth = 0
            _ = self.makeSize(table.frame.width, oldWidth: table.frame.width)
            let heightChanged = self.height != oldHeight
            if heightChanged || self.contentSize != oldContentSize {
                self.noteHeightOfRow()
            }
            if heightChanged {
                previewHeightDidChange()
            }
        }
    }

    fileprivate func contentDidChange(size: NSSize) {
        let scrollable = size.width > renderWidth + 0.5
        let insets = cardInsets
        let height = size.height + (scrollable ? HTMLBubbleView.scrollIndicatorInset : 0) + state.statsReservedHeight + insets.top + insets.bottom
        let width: CGFloat
        if isWidgetFill, hasBubble {
            width = renderWidth
        } else {
            width = isCard ? renderWidth + insets.left + insets.right : min(size.width, renderWidth)
        }
        if width != contentSize.width || height != contentSize.height {
            let settled = (view as? ChatHTMLRowView)?.hasSettledOnScreen ?? false
            let allowed = settled && table?.liveScrolling != true && !ScrollActivity.isRecent
            copyAndUpdate(animated: state.resizePacing.animates(delta: height - contentSize.height, allowed: allowed, now: CACurrentMediaTime()))
        }
    }
}

private enum HTMLWidgetLinkPrompt {
    static var isShown = false
}

private enum HTMLRowClick {
    private static var location: NSPoint = .zero
    private static weak var window: NSWindow?
    private static var time: CFTimeInterval = 0
    private static let maxAge: CFTimeInterval = 1.5
    private static let monitor: Any? = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
        location = event.locationInWindow
        window = event.window
        time = CACurrentMediaTime()
        return event
    }

    static func start() {
        _ = monitor
    }

    static func point(in view: NSView) -> CGFloat? {
        guard let window = window, window === view.window, CACurrentMediaTime() - time < maxAge else {
            return nil
        }
        let point = view.convert(location, from: nil)
        guard view.bounds.contains(point) else {
            return nil
        }
        return view.isFlipped ? point.y : view.bounds.height - point.y
    }
}

private enum ScrollActivity {
    private static var lastScroll: CFTimeInterval = 0
    private static let monitor: Any? = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
        lastScroll = CACurrentMediaTime()
        return event
    }

    static func start() {
        _ = monitor
    }

    static var isRecent: Bool {
        return CACurrentMediaTime() - lastScroll < 0.4
    }
}

private final class ChatHTMLRowView: ChatRowView {
    private let htmlView = HTMLBubbleView(frame: .zero)
    private let widgetMask = ChatBubbleSliceLayer()
    private var fullScreenButton: ImageButton?
    private var networkMarker: TextButton?
    private var card: View?

    private var shownAt: CFTimeInterval = 0
    private var shownStableId: AnyHashable?

    var hasSettledOnScreen: Bool {
        return window != nil && CACurrentMediaTime() - shownAt > 0.6
    }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(htmlView)
        ScrollActivity.start()
        HTMLRowClick.start()
    }

    var htmlContent: NSView {
        return htmlView
    }

    var htmlContentTop: CGFloat {
        return convert(htmlView.bounds.origin, from: htmlView).y
    }

    override func applyResizeAnchor(_ anchor: TableRowResizeAnchor, transition: ContainedViewLayoutTransition) {
        htmlView.pinContent(anchor, transition: transition)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        shownAt = CACurrentMediaTime()
        updateAutoRefresh()
    }

    private var refreshTimer: Foundation.Timer?
    private let refreshDisposable = MetaDisposable()

    deinit {
        refreshTimer?.invalidate()
        refreshDisposable.dispose()
    }

    private func updateAutoRefresh() {
        let wanted = window != nil && (item as? ChatHTMLRowItem)?.autoRefresh != nil
        if wanted, refreshTimer == nil {
            let timer = Foundation.Timer(timeInterval: HTMLDocumentAutoRefresh.checkInterval, repeats: true) { [weak self] _ in
                self?.autoRefreshTick()
            }
            RunLoop.main.add(timer, forMode: .common)
            refreshTimer = timer
        } else if !wanted, let timer = refreshTimer {
            timer.invalidate()
            refreshTimer = nil
        }
    }

    private func autoRefreshTick() {
        guard let item = item as? ChatHTMLRowItem, let refresh = item.autoRefresh, let messageId = item.message?.id, let window = window else {
            return
        }
        let conditions = HTMLDocumentAutoRefresh.Conditions(visible: htmlView.isHTMLBubbleVisible, windowActive: window.isVisible && window.occlusionState.contains(.visible) && window.isKeyWindow, appActive: NSApp.isActive)
        let now = CACurrentMediaTime()
        guard HTMLDocumentAutoRefresh.shared.check(messageId, interval: refresh.interval, conditions: conditions, now: now) == .fire else {
            return
        }
        refreshDisposable.set((item.context.engine.messages.requestMessageActionCallback(messageId: messageId, isGame: false, password: nil, data: refresh.data) |> deliverOnMainQueue).start(error: { _ in
            HTMLDocumentAutoRefresh.shared.finished(messageId, now: CACurrentMediaTime())
        }, completed: {
            HTMLDocumentAutoRefresh.shared.finished(messageId, now: CACurrentMediaTime())
        }))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? ChatHTMLRowItem else {
            return
        }
        if shownStableId != item.stableId {
            shownStableId = item.stableId
            shownAt = CACurrentMediaTime()
        } else if item.isDocument {
            htmlView.crossfadesNextState = true
        }
        htmlView.onContentChanged = { [weak item] size, _ in
            item?.contentDidChange(size: size)
        }
        updateCard(item)
        if !animated || htmlView.frame.size == .zero {
            let frame = item.htmlFrame
            let resized = htmlView.frame.height != frame.height
            htmlView.frame = frame
            if resized {
                htmlView.layoutTransitionStarted(.immediate)
            }
            updateWidgetMask(item, transition: .immediate)
        }
        if item.isDocument {
            item.state.linkHandler = { [weak item] _, url in
                item?.handleDocumentLink(url)
            }
        }
        if item.widget != nil, !item.isWidgetPreview {
            item.state.widgetActionHandler = { [weak item] _, action in
                item?.handleWidgetAction(action)
            }
        }
        htmlView.update(state: item.state, appearance: item.appearance, maxWidth: item.renderWidth, rendering: item.consumeEagerRendering())
        updateNetworkMarker(item)
        updateFullScreenButton(item)
        updateAutoRefresh()
    }

    private func updateCard(_ item: ChatHTMLRowItem) {
        guard item.isCard else {
            card?.removeFromSuperview()
            card = nil
            return
        }
        let current: View
        if let card = card {
            current = card
        } else {
            current = View(frame: .zero)
            current.wantsLayer = true
            current.layer?.cornerRadius = 14
            current.layer?.borderWidth = 1
            contentView.addSubview(current, positioned: .below, relativeTo: htmlView)
            card = current
        }
        let dark = item.appearance.dark
        current.backgroundColor = item.presentation.chat.bubbleBackgroundColor(true, true)
        current.layer?.borderColor = (dark ? NSColor.white.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.10)).cgColor
        current.frame = NSMakeRect(0, 0, item.contentSize.width, item.contentSize.height)
    }

    override func rightFrame(_ item: ChatRowItem) -> NSRect {
        var rect = super.rightFrame(item)
        if let item = item as? ChatHTMLRowItem, item.isCard, item.isBubbled {
            rect.origin.x -= item.cardInsets.right - 4
            rect.origin.y -= 2
        }
        return rect
    }

    private func updateNetworkMarker(_ item: ChatHTMLRowItem) {
        guard !item.isWidgetPreview, item.widget?.canQuery == true else {
            networkMarker?.removeFromSuperview()
            networkMarker = nil
            return
        }
        let marker = networkMarker ?? TextButton()
        if networkMarker == nil {
            contentView.addSubview(marker)
            networkMarker = marker
        }
        marker.set(text: "↗", for: .Normal)
        marker.set(color: item.presentation.colors.accent, for: .Normal)
        marker.set(font: .medium(14), for: .Normal)
        marker.toolTip = strings().chatHTMLRowItemNetworkWarning
        marker.frame = networkMarkerFrame(item)
        marker.removeAllHandlers()
        marker.set(handler: { [weak item] _ in
            guard let item else { return }
            showModalText(for: item.context.window, text: strings().chatHTMLRowItemNetworkWarning)
        }, for: .Click)
    }

    private func networkMarkerFrame(_ item: ChatHTMLRowItem) -> NSRect {
        let widgetFrame = item.htmlFrame
        var right = widgetFrame.maxX - 4
        if item.isStateOverlayLayout {
            let dateFrame = contentView.convert(rightFrame(item), from: rowView)
            if dateFrame.intersects(widgetFrame) {
                right = min(right, dateFrame.minX - 4)
            }
        }
        return NSMakeRect(right - 20, widgetFrame.maxY - 24, 20, 20)
    }

    private func updateFullScreenButton(_ item: ChatHTMLRowItem) {
        guard item.hasFullScreen else {
            fullScreenButton?.removeFromSuperview()
            fullScreenButton = nil
            return
        }
        let button: ImageButton
        if let current = fullScreenButton {
            button = current
        } else {
            button = ImageButton()
            button.autohighlight = false
            button.scaleOnClick = true
            button.disableActions()
            rowView.addSubview(button)
            fullScreenButton = button
        }
        let icon = item.presentation.icons.videoPlayerEnterFullScreen
        let iconSize = NSMakeSize(floor(icon.backingSize.width * 0.62), floor(icon.backingSize.height * 0.62))
        if let small = generateImage(iconSize, contextGenerator: { size, context in
            context.clear(CGRect(origin: .zero, size: size))
            context.draw(icon, in: CGRect(origin: .zero, size: size))
        }) {
            button.set(image: small, for: .Normal)
        }
        if item.presentation.backgroundMode.hasWallpaper {
            button.blurBackground = item.presentation.blurServiceColor
            button.backgroundColor = .clear
        } else {
            button.blurBackground = nil
            button.backgroundColor = item.presentation.chatServiceItemColor
        }
        button.frame = NSMakeRect(0, 0, 30, 30)
        button.set(cornerRadius: .half, for: .Normal)
        button.removeAllHandlers()
        button.set(handler: { [weak item] _ in
            item?.openFullScreen()
        }, for: .Click)
        button.setFrameOrigin(fullScreenButtonPoint(item))
    }

    private func fullScreenButtonPoint(_ item: ChatHTMLRowItem) -> NSPoint {
        let bubble = bubbleFrame(item)
        let size: CGFloat = 30
        return NSMakePoint(item.isIncoming ? bubble.maxX + 10 : bubble.minX - size - 10, bubble.minY)
    }

    var selectedText: String? {
        return htmlView.selectedText
    }

    override func canMultiselectTextIn(_ location: NSPoint) -> Bool {
        return false
    }

    override func forceClick(in location: NSPoint) {
        if !htmlView.isHidden, htmlView.bounds.contains(htmlView.convert(location, from: self)) {
            return
        }
        super.forceClick(in: location)
    }

    override func contentFrame(_ item: ChatRowItem) -> NSRect {
        var rect = super.contentFrame(item)
        if let item = item as? ChatHTMLRowItem {
            if item.isWidgetFill {
                if item.hasBubble {
                    rect.origin.x = bubbleFrame(item).minX + item.mediaBubbleCornerInset + (item.isIncoming ? item.additionBubbleInset : 0)
                    rect.size.width = item.htmlFrame.width
                } else {
                    rect.origin.x -= item.bubbleContentInset
                }
            }
            if item.widget != nil, item.invertMedia, let caption = item.captionLayouts.last {
                rect.origin.y += caption.invertedSize
            }
        }
        return rect
    }

    private func updateWidgetMask(_ item: ChatHTMLRowItem, transition: ContainedViewLayoutTransition) {
        guard item.isWidgetFill, item.hasBubble, let image = item.bubbleImage, let layer = htmlView.layer else {
            if htmlView.layer?.mask === widgetMask {
                htmlView.layer?.mask = nil
            }
            return
        }
        if layer.mask !== widgetMask {
            layer.mask = widgetMask
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        widgetMask.data = image
        CATransaction.commit()
        let content = contentFrame(item)
        let bubble = bubbleFrame(item)
        transition.updateFrame(layer: widgetMask, frame: bubble.offsetBy(dx: -content.minX - item.htmlFrame.minX, dy: -content.minY - item.htmlFrame.minY))
    }

    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        if let item = item as? ChatHTMLRowItem {
            let frame = item.htmlFrame
            let resized = htmlView.frame.height != frame.height
            updateWidgetMask(item, transition: transition)
            transition.updateFrame(view: htmlView, frame: frame)
            if let card = card {
                transition.updateFrame(view: card, frame: NSMakeRect(0, 0, item.contentSize.width, item.contentSize.height))
            }
            if resized {
                htmlView.layoutTransitionStarted(transition)
            }
            if let marker = networkMarker {
                transition.updateFrame(view: marker, frame: networkMarkerFrame(item))
            }
            if let button = fullScreenButton {
                transition.updateFrame(view: button, frame: CGRect(origin: fullScreenButtonPoint(item), size: button.frame.size))
            }
        }
    }
}
