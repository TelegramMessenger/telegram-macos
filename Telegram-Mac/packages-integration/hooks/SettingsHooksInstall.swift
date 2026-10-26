import Cocoa
import ChatHistoryModel
import ColorPalette
import Postbox
import QrStudioUI
import SettingsUI
import SelectColorUI
import StarsUI
import SwiftSignalKit
import TGUIKit
import TelegramCore
import TelegramLinks
import ThemeSettings
import WalletContext

extension ChatInteraction: @retroactive AppearanceChatPreviewContext {

}
extension inAppLink: AboutInAppLink {}
extension GlobalBadgeNode: @retroactive ShortPeerBadgeNode {}
extension inAppLink: SettingsSearchInAppLinkValue {
    var settingsSearchInAppLink: SettingsSearchInAppLink {
        return mapSettingsSearchInAppLink(self)
    }
}
extension MediaAnimatedStickerView: @retroactive SettingsStickerView {
    public func updateSettingsSticker(with media: Media, size: NSSize, context: any AccountContextProtocol, table: TableView?, animated: Bool) {
        self.update(with: media, size: size, context: context, table: table, animated: animated)
    }
}
extension PeerInfoController: @retroactive SettingsPeerInfoController {

}
extension ChatController: @retroactive SettingsChatController {

}
extension PremiumConfiguration: SelectColorPremiumConfiguration {

}
extension SmartThemePreviewRowItem: @retroactive AppearanceSmartThemePreviewRow {

}
extension EntertainmentInteractions: @retroactive SelectColorEntertainmentInteractions {
    public var selectColorSendAnimatedEmoji: (StickerPackItem, StarGift.UniqueGift?, StickerPackCollectionInfo?, Int32?, NSRect?) -> Void {
        get {
            return self.sendAnimatedEmoji
        }
        set {
            self.sendAnimatedEmoji = newValue
        }
    }
}
extension EmojiesController: @retroactive SelectColorEmojisController {
    public func updateSelectColorEmojis(with interactions: SelectColorEntertainmentInteractions?, chatLocation: ChatLocation, context: any AccountContextProtocol) {
        self.update(with: interactions as? EntertainmentInteractions, chatInteraction: ChatInteraction(chatLocation: chatLocation, context: context as! AccountContext))
    }
}
private func mapSelectColorEmojisMode(_ mode: SelectColorEmojisMode) -> EmojiesController.Mode {
    switch mode {
    case .emoji:
        return .emoji
    case .status:
        return .status
    case .reactions:
        return .reactions
    case .quickReaction:
        return .quickReaction
    case .selectAvatar:
        return .selectAvatar
    case .forumTopic:
        return .forumTopic
    case .backgroundIcon:
        return .backgroundIcon
    case .stories:
        return .stories
    case .channelReactions:
        return .channelReactions
    case .channelStatus:
        return .channelStatus
    case .defaultTags:
        return .defaultTags
    case .messageEffects:
        return .messageEffects
    }
}
private func mapSelectColorEmojiSelectedItem(_ item: SelectColorEmojiSelectedItem) -> EmojiesSectionRowItem.SelectedItem {
    let source: EmojiesSectionRowItem.SelectedItem.Source
    switch item.source {
    case let .builtin(emoji):
        source = .builtin(emoji)
    case let .custom(fileId):
        source = .custom(fileId)
    }
    let type: EmojiesSectionRowItem.SelectedItem.Selection
    switch item.type {
    case .normal:
        type = .normal
    case .transparent:
        type = .transparent
    }
    return .init(source: source, type: type)
}
extension ChatRowView: @retroactive AppearanceChatPreviewRowView {
    public func updateChatPreviewBackground(animated: Bool, item: TableRowItem?, rotated: Bool) {
        self.updateBackground(animated: animated, item: item, rotated: rotated, clean: false)
    }
}
private func mapAppearanceInAppLink(_ link: inAppLink) -> AppearanceInAppLink {
    switch link {
    case let .wallpaper(link, context, preview):
        return .wallpaper(link: link, context: context, preview: preview)
    default:
        return .other
    }
}
private func mapSettingsSearchInAppLink(_ link: inAppLink) -> SettingsSearchInAppLink {
    switch link {
    case let .instantView(link, webpage, anchor):
        return .instantView(link: link, webpage: webpage, anchor: anchor)
    default:
        return .other
    }
}
private func makeSettingsWalletHooks() -> Any? {
    if #available(macOS 10.15, *) {
        return SettingsWalletHooks(hasWallet: { context in
            return (context as! AccountContext).walletContext != nil
        }, showWallet: { context, window, morphSource in
            showWallet(context: context as! AccountContext, for: window, morphSource: morphSource)
        }, balance: { context in
            guard let walletContext = (context as! AccountContext).walletContext else {
                return .single(nil)
            }
            return walletContext.state
            |> map { state -> Int64? in
                guard case .wallet = state.phase else {
                    return nil
                }
                return state.balance.currentValue
            }
            |> distinctUntilChanged
        })
    } else {
        return nil
    }
}

final class QrStudioShareObject: ShareObject {
    private let path: String
    private let link: String
    private let image = TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: 0), representations: [], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])

    init(_ context: AccountContext, path: String, link: String) {
        self.path = path
        self.link = link
        super.init(context)
    }

    override var messagesCount: Int {
        return 1
    }

    override var hasLink: Bool {
        return !self.link.isEmpty
    }

    override func shareLink() {
        copyToClipboard(self.link)
    }

    override func possibilityPerformTo(_ peer: Peer) -> Bool {
        return !self.excludePeerIds.contains(peer.id) && peer.id.namespace != Namespaces.Peer.SecretChat && peer.canSendMessage(false, media: self.image)
    }

    override func perform(to peerIds: [PeerId], threadId: Int64?, comment: ChatTextInputState? = nil, sendPaidMessageStars: [PeerId: StarsAmount] = [:]) -> Signal<Never, String> {
        let context = self.context
        let threadIds = self.threadIds
        let silent = self.withoutSound
        let atDate = self.scheduleDate
        return Sender.generateMedia(for: MediaSenderContainer(path: self.path, isFile: false), account: context.account, isSecretRelated: false)
        |> take(1)
        |> mapToSignal { media, _ -> Signal<Never, NoError> in
            let signals = peerIds.map { peerId -> Signal<[MessageId?], NoError> in
                let threadId = threadIds[peerId] ?? threadId
                let stars = sendPaidMessageStars[peerId]
                let send = Sender.enqueue(media: media, context: context, peerId: peerId, replyId: nil, threadId: threadId, silent: silent, atDate: atDate, sendPaidMessageStars: stars)
                if let comment, !comment.inputText.isEmpty {
                    return Sender.enqueue(input: comment, context: context, peerId: peerId, replyId: nil, threadId: threadId, silent: silent, atDate: atDate, sendPaidMessageStars: stars) |> then(send)
                }
                return send
            }
            return combineLatest(signals) |> take(1) |> ignoreValues
        }
        |> castError(String.self)
    }
}

private func installQrStudioHooks() {
    QrStudioNavigationHooks.openPremium = { context in
        guard let context = context as? AccountContext else {
            return
        }
        prem(with: PremiumBoardingController(context: context, source: .premium_emoji), for: context.window)
    }
    QrStudioNavigationHooks.openGiftShop = { context in
        guard let context = context as? AccountContext else {
            return
        }
        showModal(with: GiftingController(context: context, peerId: context.peerId, isBirthday: false), for: context.window)
    }
    QrStudioNavigationHooks.shareImage = { context, path, link, window in
        guard let context = context as? AccountContext, let window = window as? Window else {
            return
        }
        showModal(with: ShareModalController(QrStudioShareObject(context, path: path, link: link)), for: window)
    }
    QrStudioEmojiPickerHooks.make = { context, presentation, staticEmojiFilter, select in
        guard let context = context as? AccountContext else {
            return nil
        }
        let emojis = EmojiesController(context, mode: .emoji, presentation: presentation)
        emojis.isGlass = true
        emojis.staticEmojiFilter = staticEmojiFilter
        let interactions = EntertainmentInteractions(.emoji, peerId: context.peerId)
        let chatInteraction = ChatInteraction(chatLocation: .peer(context.peerId), context: context)
        emojis.update(with: interactions, chatInteraction: chatInteraction)
        interactions.sendEmoji = { emoji, _ in
            select(nil, emoji)
        }
        interactions.sendAnimatedEmoji = { sticker, _, _, _, _ in
            select(sticker.file._parse(), nil)
        }
        return QrStudioEmojiPickerHooks.Picker(controller: emojis, setSelected: { [weak emojis] fileIds, unicode in
            let _ = chatInteraction
            let custom = fileIds.sorted(by: { ($0.value, $0.key) < ($1.value, $1.key) }).map { EmojiesSectionRowItem.SelectedItem(source: .custom($0.key), type: .normal, index: $0.value) }
            let builtin = unicode.sorted(by: { ($0.value, $0.key) < ($1.value, $1.key) }).map { EmojiesSectionRowItem.SelectedItem(source: .builtin($0.key), type: .normal, index: $0.value) }
            emojis?.updateSelectedItems(custom + builtin)
        })
    }
}

func installSettingsUIHooks() {
    installQrStudioHooks()
    SettingsNavigationHooks.install(makeSettingsNavigationHooks())
    var hooks = SettingsHooks(shareLink: { context, link in
        guard let context = context as? AccountContext else {
            return
        }
        showModal(with: ShareModalController(ShareLinkObject(context, link: link)), for: context.window)
    }, updateBirthday: { date, context in
        guard let context = context as? AccountContext else {
            return
        }
        editAccountUpdateBirthday(date, context: context)
    }, makeResetPhotoItem: { initialSize, stableId, context, string, style, user, image, viewType, action in
        return UserInfoResetPhotoItem(initialSize, stableId: stableId, context: context as! AccountContext, string: string, style: style, user: user, image: image, viewType: viewType, action: action)
    }, openPeerInfo: { navigation, context, peerId in
        guard let context = context as? AccountContext else {
            return
        }
        PeerInfoController.push(navigation: navigation, context: context, peerId: peerId)
    }, selectPrivacyPeers: { window, context, title, premiumBlock, miniappsBlock, selectedPeerIds in
        guard let context = context as? AccountContext else {
            return .single([])
        }
        return selectModalPeers(window: window, context: context, title: title, limit: 0, behavior: SelectChatsBehavior(settings: [.groups, .contacts, .remote, .bots], premiumBlock: premiumBlock, miniappsBlock: miniappsBlock), confirmation: { _ in return .single(true) }, selectedPeerIds: selectedPeerIds)
    }, makeChatPreviewContext: { context, peerId, isLogInteraction in
        return ChatInteraction(chatLocation: .peer(peerId), context: context as! AccountContext, isLogInteraction: isLogInteraction, disableSelectAbility: true)
    }, makeChatPreviewItem: { initialSize, previewContext, entry, theme in
        return ChatRowItem.item(initialSize, from: entry, interaction: previewContext as! ChatInteraction, theme: theme)
    }, makeSelectColorController: { context, peer in
        return SelectColorController(context: context as! AccountContext, peer: peer)
    }, downloadAndApplyCloudTheme: { context, cloudTheme, palette, install in
        return downloadAndApplyCloudTheme(context: context as! AccountContext, theme: cloudTheme, palette: palette, install: install)
    }, generateThemePreview: { palette, wallpaper, backgroundMode in
        return generateThemePreview(for: palette, wallpaper: wallpaper, backgroundMode: backgroundMode)
    }, inAppLink: { url, context in
        return mapAppearanceInAppLink(inApp(for: url, context: context as? AccountContext))
    }, cloudThemes: { context in
        guard let context = context as? AccountContext else {
            return .single(CloudThemesCachedData(themes: [], list: [:], default: nil, custom: nil))
        }
        return context.cloudThemes
    }, applyMessageEntities: { attributes, text, context, fontSize, isDark, bubbled in
        return ChatMessageItem.applyMessageEntities(with: attributes, for: text, message: nil, context: context as! AccountContext, fontSize: fontSize, openInfo: { _, _, _, _ in return }, isDark: isDark, bubbled: bubbled)
    }, formatPhoneNumber: { context, number in
        return formatPhoneNumber(context: context as! AccountContext, number: number)
    }, makePersonalChannelController: { context in
        return PersonalChannelController(context: context as! AccountContext)
    }, makeSelectColorParentController: { context, peer in
        return SelectColorParentController(context as! AccountContext, peer: peer)
    }, updatePrivacy: { context, updated, kind in
        guard let context = context as? AccountContext else {
            return
        }
        context.updatePrivacy(updated, kind: kind)
    }, executeInAppLink: { url in
        guard let url = url as? inAppLink else {
            return
        }
        execute(inapp: url)
    }, makeSelectColorPreviewContext: { context, chatLocation, isLogInteraction, disableSelectAbility, isGlobalSearchMessage in
        return ChatInteraction(chatLocation: chatLocation, context: context as! AccountContext, isLogInteraction: isLogInteraction, disableSelectAbility: disableSelectAbility, isGlobalSearchMessage: isGlobalSearchMessage)
    }, selectColorPremiumConfiguration: { context in
        return PremiumConfiguration.with(appConfiguration: context.appConfiguration)
    }, boostLevelBadgeImage: { text in
        return generateDisclosureActionBoostLevelBadgeImage(text: text)
    }, makeStickerHeaderItem: { initialSize, stableId, context, sticker, text, viewType, hasBorder in
        return AnimatedStickerHeaderItem(initialSize, stableId: stableId, context: context as! AccountContext, sticker: sticker, text: text, viewType: viewType, hasBorder: hasBorder)
    }, makeInteractiveStickerHeaderItem: { initialSize, stableId, context, sticker, text, viewType, hasBorder, interactions in
        return AnimatedStickerHeaderItem(initialSize, stableId: stableId, context: context as! AccountContext, sticker: sticker, text: text, viewType: viewType, hasBorder: hasBorder, interactions: interactions)
    }, makeEmojisController: { context, mode, selectedItems, color in
        return EmojiesController(context as! AccountContext, mode: mapSelectColorEmojisMode(mode), selectedItems: selectedItems.map(mapSelectColorEmojiSelectedItem), color: color)
    }, makeEntertainmentInteractions: { defaultState, peerId in
        return EntertainmentInteractions(defaultState, peerId: peerId)
    }, makeGroupEmojiPackController: { context, peerId, selected, updated in
        return GroupEmojiPackController(context: context as! AccountContext, peerId: peerId, selected: selected, updated: updated)
    }, makePremiumStatusController: { context, callback, peer in
        return PremiumStatusController(context as! AccountContext, callback: callback, peer: peer)
    }, setPeerInfoSpawnEmoji: { view, fileId, color, context, animated in
        view.set(fileId: fileId, color: color, context: context as! AccountContext, animated: animated)
    }, makeSmartThemePreviewRow: { initialSize, context, stableId, bubbled, emojies, theme, selected, select in
        return SmartThemePreviewRowItem(initialSize, context: context as! AccountContext, stableId: stableId, bubbled: bubbled, emojies: emojies, theme: ThemeTuple(chatTheme: theme.chatTheme, image: theme.image, theme: theme.theme, index: theme.index, selected: theme.selected), selected: selected, select: select)
    }, makeChatController: { context, chatLocation in
        return ChatController(context: context as! AccountContext, chatLocation: chatLocation)
    }, resolveInstantViewUrl: { account, url in
        return resolveInstantViewUrl(account: account, url: url) |> map { link -> SettingsSearchInAppLinkValue in
            return link
        }
    }, instantViewInAppLink: { link, webpage, anchor in
        return inAppLink.instantView(link: link, webpage: webpage, anchor: anchor)
    }, makeStickerView: { frame in
        return MediaAnimatedStickerView(frame: frame)
    }, composeCreateChannel: { context in
        guard let context = context as? AccountContext else {
            return
        }
        context.composeCreateChannel()
    }, pushPeerInfo: { navigation, context, peerId, animated in
        guard let context = context as? AccountContext else {
            return
        }
        PeerInfoController.push(navigation: navigation, context: context, peerId: peerId, animated: animated)
    }, openAccount: { context, id in
        guard let context = context as? AccountContext else {
            return
        }
        context.sharedContext.openAccount(id: id)
    }, makeAccountBadgeNode: { account, context in
        return GlobalBadgeNode(account, sharedContext: (context as! AccountContext).sharedContext, getColor: { _ in theme.colors.accent }, sync: true)
    }, makeChatListFiltersListController: { context in
        return ChatListFiltersListController(context: context as! AccountContext)
    }, appUpdateStateText: { state in
        var text: String = ""
        #if !APP_STORE
        if let state = state as? AppUpdateState {
            switch state.loadingState {
            case let .loading(_, current, total):
                text = "\(Int(Float(current) / Float(total) * 100))%"
            case let .readyToInstall(item), let .unarchiving(item):
                text = "\(item.displayVersionString!).\(item.versionString!)"
            case .uptodate:
                text = "" //strings().accountViewControllerDescUpdated
            case .failed:
                text = strings().accountViewControllerDescFailed
            default:
                text = ""
            }
        }
        #endif
        return text
    }, appUpdateState: {
        let appUpdateState: Signal<Any?, NoError>
        #if APP_STORE
            appUpdateState = .single(nil)
        #else
        appUpdateState = appUpdateStateSignal |> map(Optional.init)
        #endif
        return appUpdateState
    }, pushAppUpdate: { navigation in
        #if !APP_STORE
        navigation.push(AppUpdateViewController(), false)
        #endif
    }, openFaq: { context in
        guard let context = context as? AccountContext else {
            return
        }
        openFaq(context: context)
    }, showStories: { context, isHidden, initialId, singlePeer in
        guard let context = context as? AccountContext else {
            return
        }
        StoryModalController.ShowStories(context: context, isHidden: isHidden, initialId: initialId, singlePeer: singlePeer)
    }, authorizationStatus: { context in
        return UNUserNotifications.recurrentAuthorizationStatus(context as! AccountContext) |> map { NotificationAuthorizationStatus(rawValue: $0.rawValue) ?? .notDetermined }
    }, wallet: makeSettingsWalletHooks())
    hooks.showStoriesWithContext = { context, isHidden, initialId, singlePeer in
        guard let context = context as? AccountContext else { return }
        StoryModalController.ShowStories(context: context, isHidden: isHidden, initialId: initialId, singlePeer: singlePeer)
    }
    SettingsHooks.install(hooks)
}

private func mapSettingsPremiumSource(_ source: SettingsPremiumSource) -> PremiumLogEventsSource {
    switch source {
    case .settings:
        return .settings
    case .business:
        return .business
    case .businessStandalone:
        return .business_standalone
    case .translations:
        return .translations
    case .messagePrivacy:
        return .message_privacy
    case .lastSeen:
        return .last_seen
    }
}

private func mapSettingsBoostSource(_ source: SettingsBoostSource) -> BoostChannelSource {
    switch source {
    case .basic:
        return .basic
    case let .nameColor(level):
        return .nameColor(level)
    case let .nameIcon(level):
        return .nameIcon(level)
    case let .profileColor(level):
        return .profileColor(level)
    case let .profileIcon(level):
        return .profileIcon(level)
    case let .emojiStatus(level):
        return .emojiStatus(level)
    case let .emojiPack(level):
        return .emojiPack(level)
    case let .wallpaper(level):
        return .wallpaper(level)
    }
}

private func makeSettingsNavigationHooks() -> SettingsNavigationHooks {
    var hooks = SettingsNavigationHooks()
    hooks.openQrStudio = { context, morphSource in
        showQrStudio(context: context, peerId: context.peerId, morphSource: morphSource)
    }
    hooks.openQrStudioWithContext = { context, morphSource in
        showQrStudio(context: context, peerId: context.peerId, morphSource: morphSource)
    }
    hooks.prefetchQrStudio = { context in
        prefetchQrStudio(context: context)
    }
    hooks.makeDataAndStorageController = { context, tag in
        let focus: DataAndStorageEntryTag?
        switch tag {
        case .automaticDownloadReset:
            focus = .automaticDownloadReset
        case .autoplayGifs:
            focus = .autoplayGifs
        case .autoplayVideos:
            focus = .autoplayVideos
        case nil:
            focus = nil
        }
        return DataAndStorageViewController(context as! AccountContext, focusOnItemTag: focus)
    }
    hooks.makeStorageUsageController = { context in
        return StorageUsageController(context as! AccountContext)
    }
    hooks.makeNetworkUsageController = { context in
        return networkUsageStatsController(context: context)
    }
    hooks.makePassportController = { context, peer in
        return PassportController(context, peer, request: nil, nil)
    }
    hooks.makePhoneNumberIntroController = { context in
        return PhoneNumberIntroController(context)
    }
    hooks.makeCallSettingsController = { context in
        return CallSettingsController(sharedContext: context.sharedContext)
    }
    hooks.makeRecentSessionsController = { context in
        return RecentSessionsController(context as! AccountContext)
    }
    hooks.makeWebSessionsController = { context in
        return WebSessionsController(context as! AccountContext)
    }
    hooks.makeBusinessHoursController = { context in
        return BusinessHoursController(context: context)
    }
    hooks.makeBusinessLocationController = { context in
        return BusinessLocationController(context: context)
    }
    hooks.makeBusinessChatbotController = { context in
        return BusinessChatbotController(context: context)
    }
    hooks.makePasscodeSettingsController = { context in
        return PasscodeSettingsViewController(context as! AccountContext)
    }
    hooks.makeInstalledStickerPacksController = { context, tag in
        let focus: InstalledStickerPacksEntryTag?
        switch tag {
        case .suggestOptions:
            focus = .suggestOptions
        case nil:
            focus = nil
        }
        return InstalledStickerPacksController(context as! AccountContext, focusOnItemTag: focus)
    }
    hooks.makeFeaturedStickerPacksController = { context in
        return FeaturedStickerPacksController(context as! AccountContext)
    }
    hooks.makeArchivedStickerPacksController = { context in
        return ArchivedStickerPacksController(context as! AccountContext, archived: nil, updatedPacks: { _ in })
    }
    hooks.makeProxyListController = { context, share, pushController in
        return proxyListController(accountManager: context.sharedContext.accountManager, network: context.account.network, share: share, pushController: pushController)
    }
    hooks.showMultigift = { context, morphSource in
        multigift(context: context as! AccountContext, morphSource: morphSource)
    }
    hooks.showStarsList = { context, currency, morphSource in
        let context = context as! AccountContext
        switch currency {
        case .stars:
            showModal(with: Star_ListScreen(context: context, source: .account), for: context.window, morphSource: morphSource)
        case .ton:
            showModal(with: Star_ListScreen(context: context, currency: .ton, source: .account), for: context.window, morphSource: morphSource)
        }
    }
    hooks.newBadgeFlippedIcon = { bgColor, textColor in
        generateTextIcon_NewBadge_Flipped(bgColor: bgColor, textColor: textColor)
    }
    hooks.makePremiumBoardingController = { context, source in
        return PremiumBoardingController(context: context, source: mapSettingsPremiumSource(source))
    }
    hooks.makeBirthdayCalendarController = { window, selectHandler in
        return CalendarController(NSMakeRect(0, 0, 300, 300), window, current: Date(), lowYear: 1900, canBeNoYear: true, selectHandler: selectHandler)
    }
    hooks.makeBoostInfoController = { context, peer, boosts, myStatus, source in
        return BoostChannelModalController(context: context, peer: peer, boosts: boosts, myStatus: myStatus, infoOnly: true, source: mapSettingsBoostSource(source))
    }
    hooks.makeAddTonBalanceController = { context, tonAmount in
        return AddTonBalanceController(context: context, tonAmount: tonAmount)
    }
    hooks.makePasskeysController = { context, passkeys in
        if #available(macOS 12.0, *) {
            return PasskeysController(context: context, passkeys: passkeys)
        }
        return ModalViewController()
    }
    hooks.makeSetupEmailController = { context, pattern in
        return SetupEmailController(context: context, pattern: pattern)
    }
    hooks.showPremiumBoarding = { context, source, openFeatures, window, morphSource in
        prem(with: PremiumBoardingController(context: context, source: mapSettingsPremiumSource(source), openFeatures: openFeatures), for: window, morphSource: morphSource)
    }
    hooks.showPremiumLimit = { context, limit in
        let type: PremiumLimitController.LimitType
        switch limit {
        case let .accounts(count):
            type = .accounts(count)
        case let .caption(length):
            type = .caption(length)
        case let .about(length):
            type = .about(length)
        }
        showPremiumLimit(context: context, type: type)
    }
    hooks.showPhotosGallery = { context, peerId, firstStableId, delegate in
        showPhotosGallery(context: context, peerId: peerId, firstStableId: firstStableId, delegate, nil)
    }
    hooks.openWebBot = { context, bot in
        openWebBot(bot, context: context)
    }
    hooks.openWebBotWithContext = { context, bot in
        openWebBot(bot, context: context)
    }
    hooks.openInstantView = { context, url, webPage, anchor in
        BrowserStateContext.get(context).open(tab: .instantView(url: url, webPage: webPage, anchor: anchor))
    }
    hooks.cachedInstantPage = { context, url in
        return cachedInstantPage(postbox: context.account.postbox, url: url) |> map { cached in
            return cached.map { SettingsCachedInstantPage(webPage: $0.webPage, timestamp: $0.timestamp) }
        }
    }
    hooks.updateCachedInstantPage = { context, url, webPage in
        return updateCachedInstantPage(postbox: context.account.postbox, url: url, webPage: webPage)
    }
    hooks.requestUserLocation = {
        return requestUserLocation() |> take(1) |> mapToSignal { value -> Signal<SettingsUserLocation, UserLocationError> in
            switch value {
            case let .success(location):
                return reverseGeocodeLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                    |> mapError { _ in return UserLocationError.denied } |> map { geocode in
                        return SettingsUserLocation(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, city: geocode?.city)
                }
            }
        } |> mapError { _ in return SettingsUserLocationError() }
    }
    return hooks
}

extension DataAndStorageViewController: @retroactive SettingsSectionController {
    public var settingsSection: SettingsSection {
        return .dataAndStorage
    }
}

extension InstalledStickerPacksController: @retroactive SettingsSectionController {
    public var settingsSection: SettingsSection {
        return .stickers
    }
}

extension RecentSessionsController: @retroactive SettingsSectionController {
    public var settingsSection: SettingsSection {
        return .sessions
    }
}

extension PassportController: @retroactive SettingsSectionController {
    public var settingsSection: SettingsSection {
        return .passport
    }
}

extension PremiumBoardingController: @retroactive SettingsSectionController {
    public var settingsSection: SettingsSection {
        return .premium
    }
}
