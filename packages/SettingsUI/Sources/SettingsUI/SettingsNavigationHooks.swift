import Cocoa
import AppAnalytics
import Postbox
import SwiftSignalKit
import TGUIKit
import TelegramContext
import TelegramCore
import TelegramTheme

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

public enum SettingsDataAndStorageTag {
    case automaticDownloadReset
    case autoplayGifs
    case autoplayVideos
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
    public var openQrStudioWithContext: ((any AccountContextProtocol, (() -> NSView?)?, AnalyticsContext) -> Void)?

    public func openQrStudioObserved(_ context: any AccountContextProtocol, _ morphSource: (() -> NSView?)?, analyticsContext: AnalyticsContext) {
        if let openQrStudioWithContext {
            openQrStudioWithContext(context, morphSource, analyticsContext)
        } else {
            let presentation = analyticsContext.beginPresentation()
            withExtendedLifetime(presentation) {
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
    public var openWebBotWithContext: ((any AccountContextProtocol, AttachMenuBot, AnalyticsContext) -> Void)?

    public func openWebBotObserved(_ context: any AccountContextProtocol, _ bot: AttachMenuBot, analyticsContext: AnalyticsContext) {
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: bot.peer.id, inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        if let openWebBotWithContext {
            openWebBotWithContext(context, bot, origin)
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
