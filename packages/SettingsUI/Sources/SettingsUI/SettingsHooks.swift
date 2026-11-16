import Cocoa
import AppAnalytics
import ChatHistoryModel
import ColorPalette
import GeneralRows
import Postbox
import SwiftSignalKit
import TGUIKit
import TelegramContext
import TelegramCore
import TelegramLinks
import TelegramTheme
import ThemeSettings
import InAppSettings
import LocalAnimations
import TelegramUtils
import ShortPeerRow
import ChatModeTypes
import InlineStickerLayer

public protocol AppearanceChatPreviewContext: AnyObject {
    var getGradientOffsetRect: () -> NSRect { get set }
}
public protocol AppearanceChatPreviewRowView: TableRowView {
    func updateChatPreviewBackground(animated: Bool, item: TableRowItem?, rotated: Bool)
}
public extension AppearanceChatPreviewRowView {
    func updateBackground(animated: Bool, item: TableRowItem?, rotated: Bool = false) -> Void {
        self.updateChatPreviewBackground(animated: animated, item: item, rotated: rotated)
    }
}

public protocol AboutInAppLink {
}

public protocol AppearanceSmartThemePreviewRow: TableRowItem {
}

public struct AppearanceThemeTuple {
    public var chatTheme: ChatTheme?
    public var image: CGImage?
    public var theme: TelegramPresentationTheme
    public var index: Int
    public var selected: Bool = false
    public init(chatTheme: ChatTheme?, image: CGImage?, theme: TelegramPresentationTheme, index: Int, selected: Bool = false) {
        self.chatTheme = chatTheme
        self.image = image
        self.theme = theme
        self.index = index
        self.selected = selected
    }
}

public protocol SelectColorPremiumConfiguration {
    var minChannelEmojiStatusLevel: Int32 { get }
    var minChannelNameIconLevel: Int32 { get }
    var minChannelProfileIconLevel: Int32 { get }
    var minChannelWallpaperLevel: Int32 { get }
    var minChannelCustomWallpaperLevel: Int32 { get }
    var minGroupEmojiStatusLevel: Int32 { get }
    var minGroupProfileIconLevel: Int32 { get }
    var minGroupWallpaperLevel: Int32 { get }
    var minGroupCustomWallpaperLevel: Int32 { get }
    var minGroupEmojiPackLevel: Int32 { get }
}

public struct SelectColorEmojiSelectedItem : Equatable {
    public enum Selection : Equatable {
        case normal
        case transparent
    }
    public enum Source : Equatable {
        case builtin(String)
        case custom(Int64)
    }
    public let source : Source
    public let type: Selection
    public init(source: Source, type: Selection) {
        self.source = source
        self.type = type
    }
}

public enum SelectColorEmojisMode {
    case emoji
    case status
    case reactions
    case quickReaction
    case selectAvatar
    case forumTopic
    case backgroundIcon
    case stories
    case channelReactions
    case channelStatus
    case defaultTags
    case messageEffects
}

public protocol SelectColorEntertainmentInteractions: AnyObject {
    var selectColorSendAnimatedEmoji: (StickerPackItem, StarGift.UniqueGift?, StickerPackCollectionInfo?, Int32?, NSRect?) -> Void { get set }
}

public protocol SelectColorEmojisController: ViewController {
    func updateSelectColorEmojis(with interactions: SelectColorEntertainmentInteractions?, chatLocation: ChatLocation, context: any AccountContextProtocol)
}

public enum AppearanceInAppLink {
    case wallpaper(link: String, context: any AccountContextProtocol, preview: WallpaperPreview)
    case other
}

public enum SettingsSearchInAppLink {
    case instantView(link: String, webpage: TelegramMediaWebpage, anchor: String?)
    case other
}

public protocol SettingsSearchInAppLinkValue: AboutInAppLink {
    var settingsSearchInAppLink: SettingsSearchInAppLink { get }
}

public protocol SettingsStickerView: View {
    func updateSettingsSticker(with media: Media, size: NSSize, context: any AccountContextProtocol, table: TableView?, animated: Bool)
}

public protocol SettingsPeerInfoController: ViewController {
    var peerId: PeerId { get }
}

public protocol SettingsChatController: ViewController {
    var mode: ChatMode { get }
}

@available(macOS 10.15, *)
public struct SettingsWalletHooks {
    public let hasWallet: (any AccountContextProtocol) -> Bool
    public let showWallet: (any AccountContextProtocol, Window, (() -> NSView?)?) -> Void
    public let balance: (any AccountContextProtocol) -> Signal<Int64?, NoError>

    public init(hasWallet: @escaping (any AccountContextProtocol) -> Bool,
                showWallet: @escaping (any AccountContextProtocol, Window, (() -> NSView?)?) -> Void,
                balance: @escaping (any AccountContextProtocol) -> Signal<Int64?, NoError>) {
        self.hasWallet = hasWallet
        self.showWallet = showWallet
        self.balance = balance
    }
}
private final class PlaceholderChatPreviewContext: AppearanceChatPreviewContext {
    var getGradientOffsetRect: () -> NSRect = { return .zero }
}

public struct SettingsHooks {
    public let shareLink: (any AccountContextProtocol, String) -> Void
    public let updateBirthday: (Date, any AccountContextProtocol) -> Void
    public let makeResetPhotoItem: (NSSize, AnyHashable, any AccountContextProtocol, String, ControlStyle, TelegramUser, TelegramMediaImage?, GeneralViewType, @escaping () -> Void) -> TableRowItem
    public let openPeerInfo: (NavigationViewController, any AccountContextProtocol, PeerId) -> Void
    public let selectPrivacyPeers: (Window, any AccountContextProtocol, String, Bool, Bool, Set<PeerId>) -> Signal<[PeerId], NoError>
    public let makeChatPreviewContext: (any AccountContextProtocol, PeerId, Bool) -> AppearanceChatPreviewContext
    public let makeChatPreviewItem: (NSSize, AppearanceChatPreviewContext, ChatHistoryEntry, TelegramPresentationTheme) -> TableRowItem
    public let makeSelectColorController: (any AccountContextProtocol, Peer) -> ViewController
    public let downloadAndApplyCloudTheme: (any AccountContextProtocol, TelegramTheme, ColorPalette?, Bool) -> Signal<Never, Void>
    public let generateThemePreview: (ColorPalette, Wallpaper, TableBackgroundMode) -> CGImage
    public let inAppLink: (NSString, any AccountContextProtocol) -> AppearanceInAppLink
    public let cloudThemes: (any AccountContextProtocol) -> Signal<CloudThemesCachedData, NoError>
    public let applyMessageEntities: ([MessageAttribute], String, any AccountContextProtocol, CGFloat, Bool, Bool) -> NSAttributedString
    public let formatPhoneNumber: (any AccountContextProtocol, String) -> String
    public let makePersonalChannelController: (any AccountContextProtocol) -> ModalViewController
    public let makeSelectColorParentController: (any AccountContextProtocol, Peer) -> ViewController
    public let updatePrivacy: (any AccountContextProtocol, SelectivePrivacySettings, SelectivePrivacySettingsKind) -> Void
    public let executeInAppLink: (AboutInAppLink) -> Void
    public let makeSelectColorPreviewContext: (any AccountContextProtocol, ChatLocation, Bool, Bool, Bool) -> AppearanceChatPreviewContext
    public let selectColorPremiumConfiguration: (any AccountContextProtocol) -> any SelectColorPremiumConfiguration
    public let boostLevelBadgeImage: (String) -> CGImage
    public let makeStickerHeaderItem: (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString, GeneralViewType, Bool?) -> TableRowItem
    public let makeInteractiveStickerHeaderItem: (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString, GeneralViewType, Bool?, TextViewInteractions) -> TableRowItem
    public let makeEmojisController: (any AccountContextProtocol, SelectColorEmojisMode, [SelectColorEmojiSelectedItem], NSColor?) -> SelectColorEmojisController
    public let makeEntertainmentInteractions: (EntertainmentState, PeerId) -> SelectColorEntertainmentInteractions
    public let makeGroupEmojiPackController: (any AccountContextProtocol, PeerId, StickerPackCollectionInfo?, @escaping (StickerPackCollectionInfo?) -> Void) -> ViewController
    public let makePremiumStatusController: (any AccountContextProtocol, @escaping (TelegramMediaFile, StarGift.UniqueGift?, Int32?, CGRect?) -> Void, TelegramUser) -> ViewController
    public let setPeerInfoSpawnEmoji: (PeerInfoSpawnEmojiView, Int64, NSColor, any AccountContextProtocol, Bool) -> Void
    public let makeSmartThemePreviewRow: (NSSize, any AccountContextProtocol, AnyHashable, Bool, [String: StickerPackItem], AppearanceThemeTuple, Bool, @escaping ((ChatTheme, TelegramPresentationTheme)?) -> Void) -> AppearanceSmartThemePreviewRow
    public let makeChatController: (any AccountContextProtocol, ChatLocation) -> ViewController
    public let resolveInstantViewUrl: (Account, String) -> Signal<SettingsSearchInAppLinkValue, NoError>
    public let instantViewInAppLink: (String, TelegramMediaWebpage, String?) -> SettingsSearchInAppLinkValue
    public let makeStickerView: (NSRect) -> SettingsStickerView
    public let composeCreateChannel: (any AccountContextProtocol) -> Void
    public let pushPeerInfo: (NavigationViewController, any AccountContextProtocol, PeerId, Bool) -> Void
    public let openAccount: (any AccountContextProtocol, AccountRecordId) -> Void
    public let makeAccountBadgeNode: (Account, any AccountContextProtocol) -> ShortPeerBadgeNode
    public let makeChatListFiltersListController: (any AccountContextProtocol) -> ViewController
    public let appUpdateStateText: (Any) -> String
    public let appUpdateState: () -> Signal<Any?, NoError>
    public let pushAppUpdate: (MajorNavigationController) -> Void
    public let openFaq: (any AccountContextProtocol) -> Void
    public let showStories: (any AccountContextProtocol, Bool, StoryInitialIndex?, Bool) -> Void
    public var showStoriesWithContext: ((any AccountContextProtocol, Bool, StoryInitialIndex?, Bool, AnalyticsContext) -> Void)?
    public func showStoriesObserved(_ context: any AccountContextProtocol, _ isHidden: Bool, _ initialId: StoryInitialIndex?, _ singlePeer: Bool, analyticsContext: AnalyticsContext) {
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: initialId?.peerId ?? context.peerId, inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        if let showStoriesWithContext {
            showStoriesWithContext(context, isHidden, initialId, singlePeer, origin)
        } else {
            showStories(context, isHidden, initialId, singlePeer)
        }
    }
    public let authorizationStatus: (any AccountContextProtocol) -> Signal<NotificationAuthorizationStatus, NoError>
    public let wallet: Any?

    public init(shareLink: @escaping (any AccountContextProtocol, String) -> Void,
                updateBirthday: @escaping (Date, any AccountContextProtocol) -> Void,
                makeResetPhotoItem: @escaping (NSSize, AnyHashable, any AccountContextProtocol, String, ControlStyle, TelegramUser, TelegramMediaImage?, GeneralViewType, @escaping () -> Void) -> TableRowItem,
                openPeerInfo: @escaping (NavigationViewController, any AccountContextProtocol, PeerId) -> Void,
                selectPrivacyPeers: @escaping (Window, any AccountContextProtocol, String, Bool, Bool, Set<PeerId>) -> Signal<[PeerId], NoError>,
                makeChatPreviewContext: @escaping (any AccountContextProtocol, PeerId, Bool) -> AppearanceChatPreviewContext,
                makeChatPreviewItem: @escaping (NSSize, AppearanceChatPreviewContext, ChatHistoryEntry, TelegramPresentationTheme) -> TableRowItem,
                makeSelectColorController: @escaping (any AccountContextProtocol, Peer) -> ViewController,
                downloadAndApplyCloudTheme: @escaping (any AccountContextProtocol, TelegramTheme, ColorPalette?, Bool) -> Signal<Never, Void>,
                generateThemePreview: @escaping (ColorPalette, Wallpaper, TableBackgroundMode) -> CGImage,
                inAppLink: @escaping (NSString, any AccountContextProtocol) -> AppearanceInAppLink,
                cloudThemes: @escaping (any AccountContextProtocol) -> Signal<CloudThemesCachedData, NoError>,
                applyMessageEntities: @escaping ([MessageAttribute], String, any AccountContextProtocol, CGFloat, Bool, Bool) -> NSAttributedString,
                formatPhoneNumber: @escaping (any AccountContextProtocol, String) -> String,
                makePersonalChannelController: @escaping (any AccountContextProtocol) -> ModalViewController,
                makeSelectColorParentController: @escaping (any AccountContextProtocol, Peer) -> ViewController,
                updatePrivacy: @escaping (any AccountContextProtocol, SelectivePrivacySettings, SelectivePrivacySettingsKind) -> Void,
                executeInAppLink: @escaping (AboutInAppLink) -> Void,
                makeSelectColorPreviewContext: @escaping (any AccountContextProtocol, ChatLocation, Bool, Bool, Bool) -> AppearanceChatPreviewContext,
                selectColorPremiumConfiguration: @escaping (any AccountContextProtocol) -> any SelectColorPremiumConfiguration,
                boostLevelBadgeImage: @escaping (String) -> CGImage,
                makeStickerHeaderItem: @escaping (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString, GeneralViewType, Bool?) -> TableRowItem,
                makeInteractiveStickerHeaderItem: @escaping (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString, GeneralViewType, Bool?, TextViewInteractions) -> TableRowItem,
                makeEmojisController: @escaping (any AccountContextProtocol, SelectColorEmojisMode, [SelectColorEmojiSelectedItem], NSColor?) -> SelectColorEmojisController,
                makeEntertainmentInteractions: @escaping (EntertainmentState, PeerId) -> SelectColorEntertainmentInteractions,
                makeGroupEmojiPackController: @escaping (any AccountContextProtocol, PeerId, StickerPackCollectionInfo?, @escaping (StickerPackCollectionInfo?) -> Void) -> ViewController,
                makePremiumStatusController: @escaping (any AccountContextProtocol, @escaping (TelegramMediaFile, StarGift.UniqueGift?, Int32?, CGRect?) -> Void, TelegramUser) -> ViewController,
                setPeerInfoSpawnEmoji: @escaping (PeerInfoSpawnEmojiView, Int64, NSColor, any AccountContextProtocol, Bool) -> Void,
                makeSmartThemePreviewRow: @escaping (NSSize, any AccountContextProtocol, AnyHashable, Bool, [String: StickerPackItem], AppearanceThemeTuple, Bool, @escaping ((ChatTheme, TelegramPresentationTheme)?) -> Void) -> AppearanceSmartThemePreviewRow,
                makeChatController: @escaping (any AccountContextProtocol, ChatLocation) -> ViewController,
                resolveInstantViewUrl: @escaping (Account, String) -> Signal<SettingsSearchInAppLinkValue, NoError>,
                instantViewInAppLink: @escaping (String, TelegramMediaWebpage, String?) -> SettingsSearchInAppLinkValue,
                makeStickerView: @escaping (NSRect) -> SettingsStickerView,
                composeCreateChannel: @escaping (any AccountContextProtocol) -> Void,
                pushPeerInfo: @escaping (NavigationViewController, any AccountContextProtocol, PeerId, Bool) -> Void,
                openAccount: @escaping (any AccountContextProtocol, AccountRecordId) -> Void,
                makeAccountBadgeNode: @escaping (Account, any AccountContextProtocol) -> ShortPeerBadgeNode,
                makeChatListFiltersListController: @escaping (any AccountContextProtocol) -> ViewController,
                appUpdateStateText: @escaping (Any) -> String,
                appUpdateState: @escaping () -> Signal<Any?, NoError>,
                pushAppUpdate: @escaping (MajorNavigationController) -> Void,
                openFaq: @escaping (any AccountContextProtocol) -> Void,
                showStories: @escaping (any AccountContextProtocol, Bool, StoryInitialIndex?, Bool) -> Void,
                authorizationStatus: @escaping (any AccountContextProtocol) -> Signal<NotificationAuthorizationStatus, NoError>,
                wallet: Any?) {
        self.shareLink = shareLink
        self.updateBirthday = updateBirthday
        self.makeResetPhotoItem = makeResetPhotoItem
        self.openPeerInfo = openPeerInfo
        self.selectPrivacyPeers = selectPrivacyPeers
        self.makeChatPreviewContext = makeChatPreviewContext
        self.makeChatPreviewItem = makeChatPreviewItem
        self.makeSelectColorController = makeSelectColorController
        self.downloadAndApplyCloudTheme = downloadAndApplyCloudTheme
        self.generateThemePreview = generateThemePreview
        self.inAppLink = inAppLink
        self.cloudThemes = cloudThemes
        self.applyMessageEntities = applyMessageEntities
        self.formatPhoneNumber = formatPhoneNumber
        self.makePersonalChannelController = makePersonalChannelController
        self.makeSelectColorParentController = makeSelectColorParentController
        self.updatePrivacy = updatePrivacy
        self.executeInAppLink = executeInAppLink
        self.makeSelectColorPreviewContext = makeSelectColorPreviewContext
        self.selectColorPremiumConfiguration = selectColorPremiumConfiguration
        self.boostLevelBadgeImage = boostLevelBadgeImage
        self.makeStickerHeaderItem = makeStickerHeaderItem
        self.makeInteractiveStickerHeaderItem = makeInteractiveStickerHeaderItem
        self.makeEmojisController = makeEmojisController
        self.makeEntertainmentInteractions = makeEntertainmentInteractions
        self.makeGroupEmojiPackController = makeGroupEmojiPackController
        self.makePremiumStatusController = makePremiumStatusController
        self.setPeerInfoSpawnEmoji = setPeerInfoSpawnEmoji
        self.makeSmartThemePreviewRow = makeSmartThemePreviewRow
        self.makeChatController = makeChatController
        self.resolveInstantViewUrl = resolveInstantViewUrl
        self.instantViewInAppLink = instantViewInAppLink
        self.makeStickerView = makeStickerView
        self.composeCreateChannel = composeCreateChannel
        self.pushPeerInfo = pushPeerInfo
        self.openAccount = openAccount
        self.makeAccountBadgeNode = makeAccountBadgeNode
        self.makeChatListFiltersListController = makeChatListFiltersListController
        self.appUpdateStateText = appUpdateStateText
        self.appUpdateState = appUpdateState
        self.pushAppUpdate = pushAppUpdate
        self.openFaq = openFaq
        self.showStories = showStories
        self.authorizationStatus = authorizationStatus
        self.wallet = wallet
    }

    @available(macOS 10.15, *)
    public var walletHooks: SettingsWalletHooks {
        return wallet as! SettingsWalletHooks
    }

    private static var _shared: SettingsHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: SettingsHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("SettingsHooks.install must be called before settings screens are used")
        return .placeholder
    }

    public static func install(_ hooks: SettingsHooks) {
        assert(Thread.isMainThread, "SettingsHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = SettingsHooks(shareLink: { _, _ in
    }, updateBirthday: { _, _ in
    }, makeResetPhotoItem: { initialSize, stableId, _, _, _, _, _, _, _ in
        GeneralRowItem(initialSize, stableId: stableId)
    }, openPeerInfo: { _, _, _ in
    }, selectPrivacyPeers: { _, _, _, _, _, _ in
        .single([])
    }, makeChatPreviewContext: { _, _, _ in
        PlaceholderChatPreviewContext()
    }, makeChatPreviewItem: { initialSize, _, _, _ in
        GeneralRowItem(initialSize, stableId: arc4random())
    }, makeSelectColorController: { _, _ in
        ViewController()
    }, downloadAndApplyCloudTheme: { _, _, _, _ in
        .complete()
    }, generateThemePreview: { _, _, _ in
        generateImage(NSMakeSize(320, 320), rotatedContext: { size, ctx in
            ctx.clear(NSMakeRect(0, 0, size.width, size.height))
        })!
    }, inAppLink: { _, _ in
        .other
    }, cloudThemes: { _ in
        .single(CloudThemesCachedData(themes: [], list: [:], default: nil, custom: nil))
    }, applyMessageEntities: { _, text, _, _, _, _ in
        NSAttributedString(string: text)
    }, formatPhoneNumber: { _, number in
        number
    }, makePersonalChannelController: { _ in
        ModalViewController()
    }, makeSelectColorParentController: { _, _ in
        ViewController()
    }, updatePrivacy: { _, _, _ in
    }, executeInAppLink: { _ in
    }, makeSelectColorPreviewContext: { _, _, _, _, _ in
        PlaceholderChatPreviewContext()
    }, selectColorPremiumConfiguration: { _ in
        SelectColorPlaceholderPremiumConfiguration()
    }, boostLevelBadgeImage: { _ in
        generateImage(NSMakeSize(1, 1), contextGenerator: { size, ctx in
            ctx.clear(size.bounds)
        })!
    }, makeStickerHeaderItem: { initialSize, stableId, _, _, _, _, _ in
        GeneralRowItem(initialSize, stableId: stableId)
    }, makeInteractiveStickerHeaderItem: { initialSize, stableId, _, _, _, _, _, _ in
        GeneralRowItem(initialSize, stableId: stableId)
    }, makeEmojisController: { _, _, _, _ in
        SelectColorPlaceholderEmojisController()
    }, makeEntertainmentInteractions: { _, _ in
        SelectColorPlaceholderEntertainmentInteractions()
    }, makeGroupEmojiPackController: { _, _, _, _ in
        ViewController()
    }, makePremiumStatusController: { _, _, _ in
        ViewController()
    }, setPeerInfoSpawnEmoji: { _, _, _, _, _ in
    }, makeSmartThemePreviewRow: { initialSize, _, stableId, _, _, _, _, _ in
        AppearanceSmartThemePreviewPlaceholderRow(initialSize, stableId: stableId)
    }, makeChatController: { _, _ in
        ViewController()
    }, resolveInstantViewUrl: { _, _ in
        .complete()
    }, instantViewInAppLink: { _, _, _ in
        SettingsSearchPlaceholderInAppLink()
    }, makeStickerView: { frame in
        SettingsPlaceholderStickerView(frame: frame)
    }, composeCreateChannel: { _ in
    }, pushPeerInfo: { _, _, _, _ in
    }, openAccount: { _, _ in
    }, makeAccountBadgeNode: { _, _ in
        SettingsPlaceholderBadgeNode()
    }, makeChatListFiltersListController: { _ in
        ViewController()
    }, appUpdateStateText: { _ in
        ""
    }, appUpdateState: {
        .single(nil)
    }, pushAppUpdate: { _ in
    }, openFaq: { _ in
    }, showStories: { _, _, _, _ in
    }, authorizationStatus: { _ in
        .single(.authorized)
    }, wallet: nil)
}

private final class SettingsPlaceholderBadgeNode: ShortPeerBadgeNode {
    var isSelected: Bool = false
    var customLayout: Bool = false
    var size: NSSize = .zero
    var view: View? = nil
    var onUpdate: (() -> Void)? = nil
}

private final class SettingsPlaceholderStickerView: View, SettingsStickerView {
    func updateSettingsSticker(with media: Media, size: NSSize, context: any AccountContextProtocol, table: TableView?, animated: Bool) {
    }
}

private struct SettingsSearchPlaceholderInAppLink: SettingsSearchInAppLinkValue {
    var settingsSearchInAppLink: SettingsSearchInAppLink {
        return .other
    }
}

private final class AppearanceSmartThemePreviewPlaceholderRow: GeneralRowItem, AppearanceSmartThemePreviewRow {
    override var accessibilityIsSpacer: Bool {
        return true
    }
}

private struct SelectColorPlaceholderPremiumConfiguration: SelectColorPremiumConfiguration {
    var minChannelEmojiStatusLevel: Int32 = 0
    var minChannelNameIconLevel: Int32 = 0
    var minChannelProfileIconLevel: Int32 = 0
    var minChannelWallpaperLevel: Int32 = 0
    var minChannelCustomWallpaperLevel: Int32 = 0
    var minGroupEmojiStatusLevel: Int32 = 0
    var minGroupProfileIconLevel: Int32 = 0
    var minGroupWallpaperLevel: Int32 = 0
    var minGroupCustomWallpaperLevel: Int32 = 0
    var minGroupEmojiPackLevel: Int32 = 0
}

private final class SelectColorPlaceholderEmojisController: ViewController, SelectColorEmojisController {
    func updateSelectColorEmojis(with interactions: SelectColorEntertainmentInteractions?, chatLocation: ChatLocation, context: any AccountContextProtocol) {
    }
}

private final class SelectColorPlaceholderEntertainmentInteractions: SelectColorEntertainmentInteractions {
    var selectColorSendAnimatedEmoji: (StickerPackItem, StarGift.UniqueGift?, StickerPackCollectionInfo?, Int32?, NSRect?) -> Void = { _, _, _, _, _ in }
}
