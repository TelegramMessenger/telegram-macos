import Cocoa
import Postbox
import SwiftSignalKit
import TGUIKit
import TelegramContext
import TelegramCore
import TelegramTheme
import InAppSettings
import Localization
import InputDataUI

public enum SettingsSection {
    case dataAndStorage
    case stickers
    case sessions
    case passport
    case premium
}

public protocol SettingsSectionController: AnyObject {
    var settingsSection: SettingsSection { get }
}

public enum SettingsDataAndStorageTag: Int32 {
    case storageUsage = 1
    case keepMedia = 2
    case clearCache = 3
    case networkUsage = 4
    case automaticDownloadReset = 7
    case autoplayGifs = 8
    case autoplayVideos = 9
    case automaticDownload = 10
    case photos = 11
    case videos = 12
    case files = 13
    case voice = 14
    case instantVideo = 15
    case gifs = 16
    case downloadFolder = 17
    case soundOnHover = 18
    case sensitiveContent = 19
    case proxy = 20
    case exportData = 21
}

extension SettingsDataAndStorageTag: SettingsSearchTag {
    static var icon: SettingsSearchableItemIcon {
        return .data
    }
    
    static var rootTitle: String {
        return strings().accountSettingsDataAndStorage
    }
    
    static var rootAlternates: [String] {
        return synonyms(strings().settingsSearchSynonymsDataTitle)
    }
    
    static func itemId(_ index: Int32) -> SettingsSearchableItemId {
        return .data(index)
    }
    
    static func open<Context: AccountContextProtocol>(_ tag: SettingsDataAndStorageTag?, context: Context, present: @escaping (SettingsSearchableItemPresentation, ViewController?) -> Void) {
        switch tag {
        case .storageUsage, .keepMedia, .clearCache:
            present(.push, SettingsNavigationHooks.shared.makeStorageUsageController(context))
        case .networkUsage:
            present(.push, SettingsNavigationHooks.shared.makeNetworkUsageController(context))
        default:
            present(.push, SettingsNavigationHooks.shared.makeDataAndStorageController(context, tag))
        }
    }
    
    var searchTitle: String {
        switch self {
        case .storageUsage:
            return strings().dataAndStorageStorageUsage
        case .keepMedia:
            return strings().storageUsageKeepMedia
        case .clearCache:
            return strings().logoutOptionsClearCacheTitle
        case .networkUsage:
            return strings().dataAndStorageNetworkUsage
        case .automaticDownloadReset:
            return strings().dataAndStorageAutomaticDownloadReset
        case .autoplayGifs:
            return strings().dataAndStorageAutoplayGIFs
        case .autoplayVideos:
            return strings().dataAndStorageAutoplayVideos
        case .automaticDownload:
            return strings().dataAndStorageAutomaticDownload
        case .photos:
            return strings().dataAndStorageAutomaticDownloadPhoto
        case .videos:
            return strings().dataAndStorageAutomaticDownloadVideo
        case .files:
            return strings().dataAndStorageAutomaticDownloadFiles
        case .voice:
            return strings().dataAndStorageAutomaticDownloadVoice
        case .instantVideo:
            return strings().dataAndStorageAutomaticDownloadInstantVideo
        case .gifs:
            return strings().dataAndStorageAutomaticDownloadGIFs
        case .downloadFolder:
            return strings().dataAndStorageDownloadFolder
        case .soundOnHover:
            return strings().dataAndStorageAutoplaySoundOnHover
        case .sensitiveContent:
            return strings().dataAndStorageSensitiveContent
        case .proxy:
            return strings().privacySettingsUseProxy
        case .exportData:
            return FeatureNavigationHooks.shared.fullExportRowTitle()
        }
    }
    
    var searchAlternates: [String] {
        switch self {
        case .storageUsage:
            return synonyms(strings().settingsSearchSynonymsDataStorageTitle)
        case .keepMedia:
            return synonyms(strings().settingsSearchSynonymsDataStorageKeepMedia)
        case .clearCache:
            return synonyms(strings().settingsSearchSynonymsDataStorageClearCache)
        case .networkUsage:
            return synonyms(strings().settingsSearchSynonymsDataNetworkUsage)
        case .automaticDownloadReset:
            return synonyms(strings().settingsSearchSynonymsDataAutoDownloadReset)
        case .autoplayGifs:
            return synonyms(strings().settingsSearchSynonymsDataAutoplayGifs)
        case .autoplayVideos:
            return synonyms(strings().settingsSearchSynonymsDataAutoplayVideos)
        default:
            return []
        }
    }
    
    var searchIndex: Int32 {
        return rawValue
    }
}

public enum SettingsStickersTag {
    case suggestOptions
}

public enum SettingsPremiumSource {
    case settings
    case business
    case businessStandalone
    case translations
    case messagePrivacy
    case lastSeen
}

public enum SettingsPremiumLimit {
    case accounts(Int)
    case caption(Int)
    case about(Int)
}

public enum SettingsBoostSource {
    case basic
    case nameColor(Int32)
    case nameIcon(Int32)
    case profileColor(Int32)
    case profileIcon(Int32)
    case emojiStatus(Int32)
    case emojiPack(Int32)
    case wallpaper(Int32)
}

public struct SettingsCachedInstantPage {
    public let webPage: TelegramMediaWebpage
    public let timestamp: Int32
    public init(webPage: TelegramMediaWebpage, timestamp: Int32) {
        self.webPage = webPage
        self.timestamp = timestamp
    }
}

public struct SettingsUserLocation {
    public let latitude: Double
    public let longitude: Double
    public let city: String?
    public init(latitude: Double, longitude: Double, city: String?) {
        self.latitude = latitude
        self.longitude = longitude
        self.city = city
    }
}

public struct SettingsUserLocationError: Error {
    public init() {
    }
}

public enum SettingsStarsCurrency {
    case stars
    case ton
}

public struct SettingsNavigationHooks {
    public var showMultigift: (any AccountContextProtocol, (() -> NSView?)?) -> Void = { _, _ in }
    public var openQrStudio: (any AccountContextProtocol, (() -> NSView?)?) -> Void = { _, _ in }
    public var openQrStudioWithContext: ((any AccountContextProtocol, (() -> NSView?)?) -> Void)?

    public func openQrStudioObserved(_ context: any AccountContextProtocol, _ morphSource: (() -> NSView?)?) {
        if let openQrStudioWithContext {
            openQrStudioWithContext(context, morphSource)
        } else {
            do {
                openQrStudio(context, morphSource)
            }
        }
    }
    public var prefetchQrStudio: (any AccountContextProtocol) -> Void = { _ in }
    public var showStarsList: (any AccountContextProtocol, SettingsStarsCurrency, (() -> NSView?)?) -> Void = { _, _, _ in }
    public var newBadgeFlippedIcon: (NSColor, NSColor) -> CGImage = { bgColor, textColor in generateTextIcon_NewBadge(bgColor: bgColor, textColor: textColor) }
    public var makeDataAndStorageController: (any AccountContextProtocol, SettingsDataAndStorageTag?) -> ViewController = { _, _ in ViewController() }
    public var makeStorageUsageController: (any AccountContextProtocol) -> ViewController = { _ in ViewController() }
    public var makeNetworkUsageController: (any AccountContextProtocol) -> ViewController = { _ in ViewController() }
    public var makePassportController: (any AccountContextProtocol, Peer) -> ViewController = { _, _ in ViewController() }
    public var makePhoneNumberIntroController: (any AccountContextProtocol) -> ViewController = { _ in ViewController() }
    public var makeCallSettingsController: (any AccountContextProtocol) -> ViewController = { _ in ViewController() }
    public var makeRecentSessionsController: (any AccountContextProtocol) -> ViewController = { _ in ViewController() }
    public var makeWebSessionsController: (any AccountContextProtocol) -> ViewController = { _ in ViewController() }
    public var makeBusinessHoursController: (any AccountContextProtocol) -> ViewController = { _ in ViewController() }
    public var makeBusinessLocationController: (any AccountContextProtocol) -> ViewController = { _ in ViewController() }
    public var makeBusinessChatbotController: (any AccountContextProtocol) -> ViewController = { _ in ViewController() }
    public var makePasscodeSettingsController: (any AccountContextProtocol) -> ViewController = { _ in ViewController() }
    public var makeInstalledStickerPacksController: (any AccountContextProtocol, SettingsStickersTag?) -> ViewController = { _, _ in ViewController() }
    public var makeFeaturedStickerPacksController: (any AccountContextProtocol) -> ViewController = { _ in ViewController() }
    public var makeArchivedStickerPacksController: (any AccountContextProtocol) -> ViewController = { _ in ViewController() }
    public var makeProxyListController: (any AccountContextProtocol, @escaping ([ProxyServerSettings]) -> Void, @escaping (ViewController) -> Void) -> ViewController = { _, _, _ in ViewController() }
    public var makePremiumBoardingController: (any AccountContextProtocol, SettingsPremiumSource) -> ViewController = { _, _ in ViewController() }
    public var makeBirthdayCalendarController: (Window, @escaping (Date) -> Void) -> ViewController = { _, _ in ViewController() }
    public var makeBoostInfoController: (any AccountContextProtocol, Peer, ChannelBoostStatus, MyBoostStatus?, SettingsBoostSource) -> ModalViewController = { _, _, _, _, _ in ModalViewController() }
    public var makeAddTonBalanceController: (any AccountContextProtocol, Int64) -> ModalViewController = { _, _ in ModalViewController() }
    public var makePasskeysController: (any AccountContextProtocol, [TelegramPasskey]) -> ModalViewController = { _, _ in ModalViewController() }
    public var makeSetupEmailController: (any AccountContextProtocol, String?) -> ModalViewController = { _, _ in ModalViewController() }
    public var showPremiumBoarding: (any AccountContextProtocol, SettingsPremiumSource, Bool, Window, (() -> NSView?)?) -> Void = { _, _, _, _, _ in }
    public var showPremiumLimit: (any AccountContextProtocol, SettingsPremiumLimit) -> Void = { _, _ in }
    public var showPhotosGallery: (any AccountContextProtocol, PeerId, AnyHashable, InteractionContentViewProtocol?) -> Void = { _, _, _, _ in }
    public var openWebBot: (any AccountContextProtocol, AttachMenuBot) -> Void = { _, _ in }
    public var openWebBotWithContext: ((any AccountContextProtocol, AttachMenuBot) -> Void)?

    public func openWebBotObserved(_ context: any AccountContextProtocol, _ bot: AttachMenuBot) {
        if let openWebBotWithContext {
            openWebBotWithContext(context, bot)
        } else {
            openWebBot(context, bot)
        }
    }

    public var openInstantView: (any AccountContextProtocol, String, TelegramMediaWebpage, String?) -> Void = { _, _, _, _ in }
    public var cachedInstantPage: (any AccountContextProtocol, String) -> Signal<SettingsCachedInstantPage?, NoError> = { _, _ in .single(nil) }
    public var updateCachedInstantPage: (any AccountContextProtocol, String, TelegramMediaWebpage?) -> Signal<Void, NoError> = { _, _, _ in .complete() }
    public var requestUserLocation: () -> Signal<SettingsUserLocation, SettingsUserLocationError> = { .fail(SettingsUserLocationError()) }

    public init() {
    }

    private static var _shared: SettingsNavigationHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: SettingsNavigationHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("SettingsNavigationHooks.install must be called before settings screens are used")
        return SettingsNavigationHooks()
    }

    public static func install(_ hooks: SettingsNavigationHooks) {
        assert(Thread.isMainThread, "SettingsNavigationHooks.install must be called on the main thread")
        _shared = hooks
    }
}
