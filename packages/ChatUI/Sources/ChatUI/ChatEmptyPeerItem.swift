import Cocoa
import TGUIKit
import TelegramCore
import TelegramMedia
import Postbox
import SwiftSignalKit
import ChatModeTypes
import GeneralRows
import Localization
import PremiumUI
import TelegramTheme
import TelegramUtils
import InlineStickerLayer

// MARK: - Item

public class ChatEmptyPeerItem: TableRowItem {

    fileprivate struct Metrics {
        static let textMeasureWidthDefault: CGFloat = 250
        static let textMeasureWidthWithStandImage: CGFloat = 280
        static let textMeasureWidthMargin: CGFloat = 80
        static let containerMinWidth: CGFloat = 300
        static let containerPadding: CGFloat = 20
        static let stickerSide: CGFloat = 150
        static let mediaContentWidth: CGFloat = 300
        static let standImageSmall: CGFloat = 50
        static let standImagePremium: CGFloat = 100
        static let managedBotPreview = NSSize(width: 300, height: 200)
        static let introInfoWidth: CGFloat = 240
        static let monoforumXOffset: CGFloat = 40
    }

    public private(set) var textViewLayout: TextViewLayout
    public private(set) var image: Media?
    public private(set) var sticker: TelegramMediaFile?
    public private(set) var premiumRequired: Bool = false
    public private(set) var standImage: (CGImage, CGFloat)? = nil
    public private(set) var linkText: TextViewLayout?
    public private(set) var introInfo: TextViewLayout?

    public let chatInteraction: ChatInteraction
    public let presentation: TelegramPresentationTheme

    private let peerViewDisposable = MetaDisposable()

    public override var stableId: AnyHashable { 0 }
    public override var animatable: Bool { false }
    public override var index: Int { -1000 }
    public override var height: CGFloat { table?.frame.height ?? initialSize.height }

    public init(_ initialSize: NSSize, chatInteraction: ChatInteraction, theme: TelegramPresentationTheme) {
        self.chatInteraction = chatInteraction
        self.presentation = theme

        let initial = ChatEmptyPeerItem.makeInitialContent(chatInteraction: chatInteraction, theme: theme)
        self.standImage = initial.standImage
        self.linkText = initial.linkText

        self.textViewLayout = TextViewLayout(initial.attr, alignment: .center, lineSpacing: initial.lineSpacing, alwaysStaticItems: true)
        self.textViewLayout.interactions = LinkHooks.shared.globalLinkExecutor()

        super.init(initialSize)

        // Cloud-user refinement: bot info / managed bot / premium-required /
        // business intro. The signal layers cached data + peer + greeting
        // sticker so the view can be patched in place once the data lands.
        if shouldFetchCloudUserData(chatInteraction) {
            subscribeToCloudUserData(theme: theme)
        }
    }

    public func sendSticker() {
        if let sticker = self.sticker {
            self.chatInteraction.sendAppFile(sticker, false, nil, false, nil, nil, nil)
        }
    }

    deinit {
        peerViewDisposable.dispose()
    }

    public override func viewClass() -> AnyClass {
        return ChatEmptyPeerView.self
    }

    public override var accessibilityLabel: String? {
        let text = textViewLayout.attributedString.string
        return text.isEmpty ? nil : text
    }

    // MARK: - Initial content

    fileprivate struct Content {
        var attr: NSMutableAttributedString
        var lineSpacing: CGFloat?
        var standImage: (CGImage, CGFloat)? = nil
        var linkText: TextViewLayout? = nil
    }

    private static func makeInitialContent(chatInteraction: ChatInteraction, theme: TelegramPresentationTheme) -> Content {
        let textColor = theme.colors.text
        let attr = NSMutableAttributedString()
        var content = Content(attr: attr, lineSpacing: 5)

        if chatInteraction.presentation.isNotAccessible, let peer = chatInteraction.peer {
            attr.append(string: peer.isChannel ? strings().chatChannelUnaccessible : strings().chatGroupUnaccessible, color: textColor, font: .medium(.text))
            return content
        }

        switch chatInteraction.mode {
        case .history, .preview:
            fillHistoryContent(into: &content, chatInteraction: chatInteraction, theme: theme, textColor: textColor)
        case .scheduled:
            content.lineSpacing = nil
            attr.append(string: strings().chatEmptyChat, color: textColor, font: .medium(.text))
        case let .thread(mode):
            content.lineSpacing = nil
            attr.append(string: threadEmptyText(for: mode), color: textColor, font: .medium(.text))
        case .pinned:
            content.lineSpacing = nil
            attr.append(string: strings().chatEmptyChat, color: textColor, font: .medium(.text))
        case let .customChatContents(contents):
            fillCustomChatContentsContent(into: &content, kind: contents.kind, theme: theme)
        case let .customLink(contents):
            fillCustomLinkContent(into: &content, link: contents.link, theme: theme)
        }
        return content
    }

    private static func threadEmptyText(for mode: ReplyThreadMode) -> String {
        switch mode {
        case .comments: return strings().chatEmptyComments
        case .replies: return strings().chatEmptyReplies
        case .topic: return strings().chatEmptyTopic
        case .savedMessages, .saved: return strings().chatEmptySavedMessages
        }
    }

    private static func fillHistoryContent(into content: inout Content, chatInteraction: ChatInteraction, theme: TelegramPresentationTheme, textColor: NSColor) {
        let attr = content.attr
        if chatInteraction.peerId.namespace == Namespaces.Peer.SecretChat {
            let lines = [
                strings().chatSecretChatEmptyHeader,
                strings().chatSecretChat1Feature,
                strings().chatSecretChat2Feature,
                strings().chatSecretChat3Feature,
                strings().chatSecretChat4Feature
            ]
            attr.append(linesString: lines, color: textColor, font: .medium(.text))
            return
        }

        if let peer = chatInteraction.peer, peer.isGroup || peer.isSupergroup, peer.groupAccess.isCreator {
            if chatInteraction.presentation.chatLocation.threadId == nil {
                let memberCount = chatInteraction.presentation.limitConfiguration.maxSupergroupMemberCount.formattedWithSeparator
                let lines = [
                    strings().emptyGroupInfoTitle,
                    strings().emptyGroupInfoSubtitle,
                    strings().emptyGroupInfoLine1(memberCount),
                    strings().emptyGroupInfoLine2,
                    strings().emptyGroupInfoLine3,
                    strings().emptyGroupInfoLine4
                ]
                attr.append(linesString: lines, color: textColor, font: .medium(.text))
            } else {
                content.lineSpacing = nil
                attr.append(string: strings().chatEmptyChat, color: textColor, font: .medium(.text))
            }
            return
        }

        if let paidMessageStars = chatInteraction.presentation.sendPaidMessageStars, let peer = chatInteraction.peer {
            attr.append(string: strings().chatEmptyPaidMessage(peer.displayTitle, strings().starListItemCountOther(Int(paidMessageStars.value))), color: textColor, font: .medium(.text))
            content.lineSpacing = nil
            return
        }

        if let restriction = chatInteraction.presentation.peer?.restrictionText(chatInteraction.interactionContext.contentSettings) {
            attr.append(string: restriction, color: theme.chatServiceItemTextColor, font: .medium(.text))
        } else {
            content.lineSpacing = nil
            attr.append(string: strings().chatEmptyChat, color: textColor, font: .medium(.text))
        }
    }

    private static func fillCustomChatContentsContent(into content: inout Content, kind: ChatCustomContentsKind, theme: TelegramPresentationTheme) {
        let attr = content.attr
        let textColor = theme.colors.text
        let accentTint: NSColor = theme.colors.isDark ? theme.colors.text : theme.colors.accent

        switch kind {
        case .greetingMessageInput:
            attr.append(string: strings().chatEmptyBusinessGreetingMessage, color: textColor, font: .medium(.text))
            attr.append(string: "\n\n")
            attr.append(string: strings().chatEmptyBusinessGreetingMessageInfo, color: textColor, font: .normal(.text))
            content.standImage = (TelegramThemeHooks.shared.image(.iconBusinessChatGreetings).precomposed(accentTint), Metrics.standImageSmall)
        case .awayMessageInput:
            attr.append(string: strings().chatEmptyBusinessAwayMessage, color: textColor, font: .medium(.text))
            attr.append(string: "\n\n")
            attr.append(string: strings().chatEmptyBusinessAwayMessageInfo, color: textColor, font: .normal(.text))
            content.standImage = (TelegramThemeHooks.shared.image(.iconBusinessChatAway).precomposed(accentTint), Metrics.standImageSmall)
        case let .quickReplyMessageInput(shortcut):
            attr.append(string: strings().chatEmptyBusinessQuickReply, color: textColor, font: .medium(.text))
            attr.append(string: "\n\n")
            attr.append(string: strings().chatEmptyBusinessQuickReplyInfo1(shortcut), color: textColor, font: .normal(.text))
            attr.append(string: "\n")
            attr.append(string: strings().chatEmptyBusinessQuickReplyInfo2, color: textColor, font: .normal(.text))
            content.standImage = (TelegramThemeHooks.shared.image(.iconBusinessChatQuickReply).precomposed(accentTint), Metrics.standImageSmall)
            attr.detectBoldColorInString(with: .medium(.text))
        case .welcomeMessages:
            attr.append(string: strings().welcomeMessageEmptyTitle, color: textColor, font: .medium(.text))
            attr.append(string: "\n\n")
            attr.append(string: strings().welcomeMessageEmptyText, color: textColor, font: .normal(.text))
            content.standImage = (TelegramThemeHooks.shared.image(.iconBusinessChatGreetings).precomposed(accentTint), Metrics.standImageSmall)
        case .searchHashtag:
            attr.append(string: strings().chatEmptySearchHashtag, color: textColor, font: .medium(.text))
        case .htmlDemo:
            attr.append(string: strings().chatEmptyChat, color: textColor, font: .medium(.text))
        }
    }

    private static func fillCustomLinkContent(into content: inout Content, link: String, theme: TelegramPresentationTheme) {
        let attr = content.attr
        let textColor = theme.colors.text
        let accentTint: NSColor = theme.colors.isDark ? theme.colors.text : theme.colors.accent

        attr.append(string: strings().chatEmptyBusinessLinkTitle, color: textColor, font: .medium(.text))
        attr.append(string: "\n\n")
        attr.append(string: strings().chatEmptyBusinessLinkText, color: textColor, font: .normal(.text))
        content.standImage = (TelegramThemeHooks.shared.image(.iconChatLinksToChat).precomposed(accentTint), Metrics.standImageSmall)

        let linkLayout = TextViewLayout(.initialize(string: link, color: textColor, font: .medium(.text)))
        linkLayout.measure(width: .greatestFiniteMagnitude)
        content.linkText = linkLayout
    }

    // MARK: - Cloud-user refinement

    private func shouldFetchCloudUserData(_ chatInteraction: ChatInteraction) -> Bool {
        return chatInteraction.peerId.namespace == Namespaces.Peer.CloudUser
            && chatInteraction.mode.customChatContents == nil
            && chatInteraction.mode.customChatLink == nil
    }

    private func subscribeToCloudUserData(theme: TelegramPresentationTheme) {
        let context = chatInteraction.interactionContext

        let cachedData: Signal<CachedPeerData?, NoError> = .single(chatInteraction.presentation.cachedData)
            |> then(getCachedDataView(peerId: chatInteraction.peerId, postbox: context.account.postbox))
            |> deliverOnMainQueue

        let peer: Signal<Peer?, NoError> = .single(chatInteraction.presentation.mainPeer)
            |> then(getPeerView(peerId: chatInteraction.peerId, postbox: context.account.postbox))
            |> deliverOnMainQueue

        let sticker: Signal<FoundStickerItem?, NoError> = .single(nil)
            |> then(context.engine.stickers.randomGreetingSticker() |> deliverOnMainQueue)

        let managerPeer: Signal<Peer?, NoError> = cachedData |> mapToSignal { cached in
            if let cached = cached as? CachedUserData, let botManagerId = cached.botManagerId {
                return context.account.postbox.transaction { $0.getPeer(botManagerId) } |> deliverOnMainQueue
            }
            return .single(nil)
        }

        peerViewDisposable.set(combineLatest(queue: .mainQueue(), cachedData, peer, sticker, managerPeer).start(next: { [weak self] cached, peer, sticker, managerPeer in
            guard let self else { return }
            guard let cachedData = cached as? CachedUserData,
                  let user = peer,
                  self.chatInteraction.mode == .history,
                  peer?.restrictionInfo == nil else {
                return
            }
            if let botInfo = cachedData.botInfo, !botInfo.description.isEmpty {
                self.applyBotInfo(botInfo: botInfo, cachedData: cachedData, user: user, theme: theme)
            } else if let _ = cachedData.botManagerId {
                self.applyManagedBot(user: user, managerPeer: managerPeer, theme: theme)
            } else if let botInfo = cachedData.botInfo {
                self.applyBotInfo(botInfo: botInfo, cachedData: cachedData, user: user, theme: theme)
            } else if cachedData.flags.contains(.premiumRequired), !self.chatInteraction.interactionContext.isPremium {
                self.applyPremiumRequired(user: user, theme: theme)
            } else if case let .known(intro) = cachedData.businessIntro, let intro = intro {
                self.applyBusinessIntro(intro: intro, user: user, greetingSticker: sticker, theme: theme)
            }
            self.view?.set(item: self)
        }))
    }

    private func applyManagedBot(user: Peer, managerPeer: Peer?, theme: TelegramPresentationTheme) {
        let managerName = managerPeer?.displayTitle ?? "bot manager"
        let attr = NSMutableAttributedString()
        attr.append(string: "\(user.displayTitle) ", color: theme.colors.text, font: .bold(.text))
        attr.append(string: strings().chatEmptyManagedBotIsReady, color: theme.colors.text, font: .normal(.text))
        attr.append(string: "\n\n", color: theme.colors.text, font: .normal(.text))
        attr.append(string: strings().chatEmptyManagedBotTap, color: theme.colors.text, font: .normal(.text))
        attr.append(string: strings().chatEmptyManagedBotStart, color: theme.colors.text, font: .bold(.text))
        attr.append(string: strings().chatEmptyManagedBotTestInfo, color: theme.colors.text, font: .normal(.text))
        attr.append(string: managerName, color: theme.colors.text, font: .bold(.text))
        attr.append(string: ".", color: theme.colors.text, font: .normal(.text))
        attr.append(string: "\n\n", color: theme.colors.text, font: .normal(.text))
        attr.append(string: strings().chatEmptyManagedBotEditInfo, color: theme.colors.text, font: .normal(.text))
        let hereRange = attr.append(string: strings().chatEmptyManagedBotHere, color: theme.colors.link, font: .normal(.text))

        let peerId = chatInteraction.peerId
        let ctx = chatInteraction.interactionContext
        attr.add(link: LinkHooks.shared.callbackLink("", { _ in
            ChatHistoryUIHooks.shared.pushEditPeerInfo(ctx.bindings.rootNavigation(), ctx, peerId)
        }), for: hereRange, color: theme.colors.link)
        attr.replaceChevron(color: theme.colors.link)

        self.textViewLayout = TextViewLayout(attr, alignment: .left)
        self.textViewLayout.interactions = LinkHooks.shared.globalLinkExecutor()
        self.standImage = (Self.managedBotPreviewImage(peerId: peerId, theme: theme), Metrics.managedBotPreview.width)
    }

    private struct ManagedBotPreviewCacheEntry {
        let top: NSColor
        let bottom: NSColor
        let scale: CGFloat
        let image: CGImage
    }
    
    private static var managedBotPreviewCache: [ManagedBotPreviewCacheEntry] = []
    private static let managedBotPreviewLock = NSLock()
    
    private static func managedBotPreviewImage(peerId: PeerId, theme: TelegramPresentationTheme) -> CGImage {
        let colorIndex = Int(peerId.id._internalGetInt64Value() % 7)
        let colors = theme.colors.peerColors(colorIndex)
        let scale = System.backingScale
        managedBotPreviewLock.lock()
        let cached = managedBotPreviewCache.first(where: { $0.scale == scale && $0.top.isEqual(colors.top) && $0.bottom.isEqual(colors.bottom) })
        managedBotPreviewLock.unlock()
        if let cached {
            return cached.image
        }
        let image = makeManagedBotPreviewImage(colors: colors)
        managedBotPreviewLock.lock()
        managedBotPreviewCache.append(ManagedBotPreviewCacheEntry(top: colors.top, bottom: colors.bottom, scale: scale, image: image))
        if managedBotPreviewCache.count > 2 {
            managedBotPreviewCache.removeFirst()
        }
        managedBotPreviewLock.unlock()
        return image
    }
    
    private static func makeManagedBotPreviewImage(colors: (top: NSColor, bottom: NSColor)) -> CGImage {
        let size = Metrics.managedBotPreview
        return generateImage(size, rotatedContext: { size, ctx in
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let gradient = CGGradient(colorsSpace: colorSpace, colors: [colors.top.darker().cgColor, colors.bottom.darker().cgColor] as CFArray, locations: [0.0, 1.0])!
            ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])

            let patternImage = TelegramThemeHooks.shared.image(.iconManageBotPattern).precomposed(.white, flipVertical: true)
            let patternSize = patternImage.backingSize * 0.5
            let patternRect = CGRect(origin: CGPoint(x: (size.width - patternSize.width) / 2, y: (size.height - patternSize.height) / 2), size: patternSize)
            ctx.setBlendMode(.overlay)
            ctx.draw(patternImage, in: patternRect)
            ctx.setBlendMode(.normal)

            let codeIcon = TelegramThemeHooks.shared.image(.iconManageBotCode).precomposed(.white, flipVertical: true)
            let iconSize = NSMakeSize(codeIcon.backingSize.width / 2, codeIcon.backingSize.height / 2)
            let iconRect = CGRect(origin: CGPoint(x: (size.width - iconSize.width) / 2, y: (size.height - iconSize.height) / 2), size: iconSize)
            ctx.draw(codeIcon, in: iconRect)
        })!
    }

    private func applyBotInfo(botInfo: BotInfo, cachedData: CachedUserData, user: Peer, theme: TelegramPresentationTheme) {
        var about = botInfo.description
        if about.isEmpty {
            about = cachedData.about ?? strings().chatEmptyChat
        }
        if about.isEmpty {
            about = strings().chatEmptyChat
        }
        if user.isScam {
            about = strings().peerInfoScamWarning
        }
        if user.isFake {
            about = strings().peerInfoFakeWarning
        }
        let chatInteraction = self.chatInteraction
        let attr = NSMutableAttributedString()
        attr.append(string: about, color: theme.colors.text, font: .medium(.text))
        ChatHistoryLink.detectLinks(attr, type: [.Links, .Mentions, .Hashtags, .Commands], context: chatInteraction.interactionContext, color: theme.colors.link, openInfo: chatInteraction.openInfo, hashtag: { hashtag in
            chatInteraction.interactionContext.bindings.globalSearch(hashtag, nil, nil)
        }, command: chatInteraction.sendPlainText, applyProxy: chatInteraction.applyProxy, dotInMention: false)

        self.textViewLayout = TextViewLayout(attr, alignment: .left)
        self.textViewLayout.interactions = LinkHooks.shared.globalLinkExecutor()
        self.image = botInfo.video ?? botInfo.photo
        self.standImage = nil
    }

    private func applyPremiumRequired(user: Peer, theme: TelegramPresentationTheme) {
        let chatInteraction = self.chatInteraction
        let attr = NSMutableAttributedString()
        attr.append(string: strings().chatEmptyPremiumRequiredState(user.compactDisplayTitle), color: theme.colors.text, font: .medium(.text))
        attr.detectBoldColorInString(with: .medium(.text))
        ChatHistoryLink.detectLinks(attr, type: [.Links, .Mentions, .Hashtags, .Commands], context: chatInteraction.interactionContext, color: theme.colors.link, openInfo: chatInteraction.openInfo, hashtag: { hashtag in
            chatInteraction.interactionContext.bindings.globalSearch(hashtag, nil, nil)
        }, command: chatInteraction.sendPlainText, applyProxy: chatInteraction.applyProxy, dotInMention: false)

        let accentTint: NSColor = theme.colors.isDark ? theme.colors.text : theme.colors.accent
        self.textViewLayout = TextViewLayout(attr, alignment: .center)
        self.textViewLayout.interactions = LinkHooks.shared.globalLinkExecutor()
        self.premiumRequired = true
        self.standImage = (TelegramThemeHooks.shared.image(.iconChatPremiumRequired).precomposed(accentTint), Metrics.standImagePremium)
    }

    private func applyBusinessIntro(intro: TelegramBusinessIntro, user: Peer, greetingSticker: FoundStickerItem?, theme: TelegramPresentationTheme) {
        let attr = NSMutableAttributedString()
        attr.append(string: intro.title.isEmpty ? strings().chatEmptyChat : intro.title, color: theme.colors.text, font: .medium(.text))
        attr.append(string: "\n", color: theme.colors.text, font: .medium(.text))
        attr.append(string: intro.text.isEmpty ? strings().chatEmptyChatInfo : intro.text, color: theme.colors.text, font: .normal(.text))

        self.textViewLayout = TextViewLayout(attr, alignment: .center)
        self.textViewLayout.interactions = LinkHooks.shared.globalLinkExecutor()
        self.sticker = intro.stickerFile ?? greetingSticker?.file

        let info = parseMarkdownIntoAttributedString(strings().chatEmptyBusinessIntroHow(user.compactDisplayTitle), attributes: .init(
            body: .init(font: .normal(.text), textColor: theme.colors.text),
            bold: .init(font: .medium(.text), textColor: theme.colors.text),
            link: .init(font: .normal(.text), textColor: theme.colors.accent),
            linkAttribute: { _ in (NSAttributedString.Key.foregroundColor.rawValue, theme.colors.accent) }
        )).detectBold(with: .medium(.text))

        let introInfo = TextViewLayout(info, alignment: .center)
        introInfo.interactions = LinkHooks.shared.globalLinkExecutor()
        self.introInfo = introInfo
    }
}

// MARK: - Attribute helper

private extension NSMutableAttributedString {
    /// Append each entry as a separate medium-text line, mirroring the
    /// pre-refactor pattern of `append(string:); append("\n")` repeated by
    /// hand. The final line is appended without a trailing newline to match
    /// the original behaviour.
    func append(linesString lines: [String], color: NSColor, font: NSFont) {
        for (i, line) in lines.enumerated() {
            _ = append(string: line, color: color, font: font)
            if i != lines.count - 1 {
                _ = append(string: "\n")
            }
        }
    }
}

// MARK: - View

public class ChatEmptyPeerView: TableRowView {

    private let textView = InteractiveTextView()
    private let bgView: LiquidGlassView
    private var imageView: ChatMediaContentView?
    private var stickerView: StickerMediaContentView?
    private var premRequiredImageView: ImageView?
    private var premRequiredButton: TextButton?
    private var linkView: TextView?
    private var introInfoView: TextView?

    public required init(frame frameRect: NSRect) {
        self.bgView = LiquidGlassView(frame: .zero, cornerRadius: 20, hasShadow: false, hasBorder: false, customTint: theme.colors.background)
        super.init(frame: frameRect)
        addSubview(bgView, positioned: .below, relativeTo: nil)
        addSubview(textView)
        textView.textView.isSelectable = false
        textView.textView.userInteractionEnabled = true
        textView.textView.disableBackgroundDrawing = true
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var backdorColor: NSColor {
        return .clear
    }

    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item)
        guard let item = item as? ChatEmptyPeerItem else { return }

        bgView.customTint = item.presentation.colors.background
        reparent(into: bgView)

        configureImageView(item: item, bgView: bgView)
        configureStickerView(item: item, bgView: bgView)
        configureStandImage(item: item, bgView: bgView)
        configureLinkView(item: item, bgView: bgView)
        configureIntroInfo(item: item)
        configurePremiumButton(item: item, bgView: bgView)

        needsLayout = true
    }

    private func reparent(into bgView: NSView) {
        let managed: [NSView?] = [textView, imageView, stickerView, premRequiredImageView, premRequiredButton, linkView]
        for view in managed {
            guard let view, view.superview !== bgView else { continue }
            bgView.addSubview(view)
        }
    }

    private func configureImageView(item: ChatEmptyPeerItem, bgView: NSView) {
        guard let media = item.image else {
            if let view = imageView {
                performSubviewRemoval(view, animated: false)
                imageView = nil
            }
            return
        }
        let contentNode = ChatLayoutUtils.contentNode(for: media)
        let contentSize = ChatLayoutUtils.contentSize(for: media, with: ChatEmptyPeerItem.Metrics.mediaContentWidth)
        if imageView == nil || !imageView!.isKind(of: contentNode) {
            imageView?.removeFromSuperview()
            let view = contentNode.init(frame: .zero)
            bgView.addSubview(view)
            imageView = view
        }
        imageView?.update(with: media, size: contentSize, context: item.chatInteraction.interactionContext, parent: nil, table: item.table)
        imageView?.fetch(userInitiated: true)
        // The media sits flush against the top edge of the glass bg, so its
        // top corners need to match `bgView.cornerRadius` (set to 20 whenever
        // a media view is present — see `updateLayout`'s corner-radius math).
        imageView?.layer?.cornerRadius = 20
        imageView?.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        imageView?.layer?.masksToBounds = true
    }

    private func configureStickerView(item: ChatEmptyPeerItem, bgView: NSView) {
        guard let sticker = item.sticker else {
            if let view = stickerView {
                performSubviewRemoval(view, animated: false)
                stickerView = nil
            }
            return
        }
        let target = NSMakeSize(ChatEmptyPeerItem.Metrics.stickerSide, ChatEmptyPeerItem.Metrics.stickerSide)
        let size = sticker.dimensions?.size.aspectFitted(target) ?? target
        if stickerView == nil {
            let view = StickerMediaContentView(frame: size.bounds)
            view.scaleOnClick = true
            view.userInteractionEnabled = true
            view.set(handler: { [weak self] _ in
                (self?.item as? ChatEmptyPeerItem)?.sendSticker()
            }, for: .Click)
            bgView.addSubview(view)
            stickerView = view
        }
        stickerView?.update(with: sticker, size: size, context: item.chatInteraction.interactionContext, parent: nil, table: item.table)
    }

    private func configureStandImage(item: ChatEmptyPeerItem, bgView: NSView) {
        guard let standImage = item.standImage else {
            if let view = premRequiredImageView {
                performSubviewRemoval(view, animated: false)
                premRequiredImageView = nil
            }
            return
        }
        if premRequiredImageView == nil {
            let view = ImageView()
            view.isAccessibilityDecorative = true
            bgView.addSubview(view)
            premRequiredImageView = view
        }
        premRequiredImageView?.image = standImage.0
        let fitted = standImage.0.backingSize.aspectFitted(NSMakeSize(standImage.1, standImage.1))
        premRequiredImageView?.setFrameSize(NSMakeSize(standImage.1, fitted.height))
        premRequiredImageView?.contentGravity = .resizeAspect
    }

    private func configureLinkView(item: ChatEmptyPeerItem, bgView: NSView) {
        guard let linkText = item.linkText else {
            if let view = linkView {
                performSubviewRemoval(view, animated: false)
                linkView = nil
            }
            return
        }
        if linkView == nil {
            let view = TextView()
            view.userInteractionEnabled = false
            view.isSelectable = false
            bgView.addSubview(view)
            linkView = view
        }
        linkView?.update(linkText)
    }

    private func configureIntroInfo(item: ChatEmptyPeerItem) {
        guard let introInfo = item.introInfo else {
            if let view = introInfoView {
                performSubviewRemoval(view, animated: false)
                introInfoView = nil
            }
            return
        }
        if introInfoView == nil {
            let view = TextView()
            view.isSelectable = false
            view.scaleOnClick = true
            view.set(handler: { [weak item, weak view] _ in
                if let context = item?.chatInteraction.interactionContext {
                    prem(with: PremiumBoardingController(context: context, source: .business_intro), for: context.window, morphSource: { view })
                }
            }, for: .Click)
            self.addSubview(view)
            introInfoView = view
        }
        introInfo.measure(width: ChatEmptyPeerItem.Metrics.introInfoWidth)
        introInfo.generateAutoBlock(backgroundColor: item.presentation.colors.background)
        introInfoView?.update(introInfo)
    }

    private func configurePremiumButton(item: ChatEmptyPeerItem, bgView: NSView) {
        guard item.premiumRequired else {
            if let view = premRequiredButton {
                performSubviewRemoval(view, animated: false)
                premRequiredButton = nil
            }
            return
        }
        if premRequiredButton == nil {
            let button = TextButton()
            button.scaleOnClick = true
            button.set(handler: { [weak self, weak button] _ in
                if let context = (self?.item as? ChatEmptyPeerItem)?.chatInteraction.interactionContext {
                    prem(with: PremiumBoardingController(context: context), for: context.window, morphSource: { button })
                }
            }, for: .Click)
            bgView.addSubview(button)
            premRequiredButton = button
        }
        guard let button = premRequiredButton else { return }
        button.set(background: item.presentation.colors.accent, for: .Normal)
        button.set(font: .medium(.text), for: .Normal)
        button.set(color: item.presentation.colors.underSelectedColor, for: .Normal)
        button.set(text: strings().chatEmptyPremiumRequiredAction, for: .Normal)
        button.sizeToFit(NSMakeSize(20, 20))
        button.layer?.cornerRadius = button.frame.height / 2
    }

    // MARK: - Layout

    public override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }

    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        guard let item = item as? ChatEmptyPeerItem else { return }

        let textMeasureWidth: CGFloat = item.standImage != nil
            ? ChatEmptyPeerItem.Metrics.textMeasureWidthWithStandImage
            : min(size.width - ChatEmptyPeerItem.Metrics.textMeasureWidthMargin, ChatEmptyPeerItem.Metrics.textMeasureWidthDefault)

        item.textViewLayout.measure(width: textMeasureWidth)
        if item.textViewLayout.lineSpacing != nil {
            for (i, line) in item.textViewLayout.lines.enumerated() {
                line.penFlush = (i == 0) ? 0.5 : 0.0
            }
        }
        textView.set(text: item.textViewLayout, context: item.chatInteraction.interactionContext)

        var bgWidth = textView.frame.width + ChatEmptyPeerItem.Metrics.containerPadding
        if imageView != nil || linkView != nil || premRequiredImageView != nil {
            bgWidth = max(bgWidth, ChatEmptyPeerItem.Metrics.containerMinWidth)
        }

        var totalHeight: CGFloat = [imageView, premRequiredImageView, premRequiredButton, stickerView, linkView]
            .compactMap { $0?.frame.height }
            .reduce(0, +)

        if premRequiredImageView != nil { totalHeight += 10 + ChatEmptyPeerItem.Metrics.containerPadding }
        if premRequiredButton != nil { totalHeight += 20 }
        if stickerView != nil { totalHeight += 10 }
        if linkView != nil { totalHeight += 8 }

        totalHeight += textView.frame.height + ChatEmptyPeerItem.Metrics.containerPadding

        let xOffset: CGFloat = item.chatInteraction.presentation.monoforumState == .vertical
            ? ChatEmptyPeerItem.Metrics.monoforumXOffset
            : 0

        bgView.setFrameSize(NSMakeSize(bgWidth, totalHeight))
        transition.updateFrame(view: bgView, frame: bgView.centerFrame().offsetBy(dx: xOffset, dy: 0))

        layoutMainStack(transition: transition)

        if let view = premRequiredButton {
            transition.updateFrame(view: view, frame: view.centerFrameX(y: textView.frame.maxY + 10).offsetBy(dx: xOffset, dy: 0))
        }
        if let view = linkView {
            transition.updateFrame(view: view, frame: view.centerFrameX(y: textView.frame.maxY + 8).offsetBy(dx: xOffset, dy: 0))
        }
        if let view = introInfoView {
            transition.updateFrame(view: view, frame: view.centerFrameX(y: bgView.frame.maxY + 10).offsetBy(dx: xOffset, dy: 0))
        }

        let singleLine = item.textViewLayout.lines.count == 1
        bgView.cornerRadius = (imageView == nil && premRequiredImageView == nil)
            ? (singleLine ? textView.frame.height / 2 : 20)
            : 20
    }

    /// Position the leading image/sticker (if any) and the textView relative
    /// to it. Mirrors the original cascading if/else chain so unchanged code
    /// paths keep identical frames.
    private func layoutMainStack(transition: ContainedViewLayoutTransition) {
        if let view = premRequiredImageView {
            transition.updateFrame(view: view, frame: view.centerFrameX(y: ChatEmptyPeerItem.Metrics.containerPadding))
            transition.updateFrame(view: textView, frame: textView.centerFrameX(y: view.frame.maxY + 10))
        } else if let view = imageView {
            transition.updateFrame(view: view, frame: view.centerFrameX(y: 0))
            transition.updateFrame(view: textView, frame: textView.centerFrameX(y: view.frame.maxY + 10))
        } else if let view = stickerView {
            transition.updateFrame(view: textView, frame: textView.centerFrameX(y: 10))
            transition.updateFrame(view: view, frame: view.centerFrameX(y: textView.frame.maxY + 10))
        } else {
            transition.updateFrame(view: textView, frame: textView.centerFrame())
        }
    }
}
