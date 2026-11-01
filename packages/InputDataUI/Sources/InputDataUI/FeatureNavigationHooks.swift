import Foundation
import Cocoa
import CoreLocation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramTheme

public enum PremiumBoardingSource: Equatable {
    case settings
    case noAds
    case gracePeriod
    case storyViewers
    case storiesStealthMode
    case storiesSaveToGallery
    case premiumStickers
    case premiumEmoji
    case storiesQuality
    case savedTags
    case messageEffects
    case aiCompose
    case translations
    case noforwards
    case channelBoost(PeerId)
}

public enum PremiumLimitKind: Equatable {
    case pin
    case pinInArchive
    case savedGifs
    case folders
    case chatInFolders
    case pinInFolders(PeerGroupId)
    case faveStickers
    case publicLink
    case channels
    case uploadFile(Int?)
    case caption(Int)
    case about(Int)
    case accounts(Int)
    case sharedFolders
    case sharedInvites
}

public enum InactiveChannelsReason {
    case join
    case create
    case upgrade
}

public enum DateSelectorRequest {
    case schedule(PeerId)
    case date(title: String, doneTitle: String)
}

public enum BoostInfoSource {
    case story
    case reactions
}

public enum PaymentCheckoutResult {
    case paid
    case cancelled
    case failed
}

public enum UserLocationRequestResult {
    case success(CLLocation)
    case restricted
    case notDetermined
    case denied
    case wifiRequired
    case disabled
}

public struct SponsoredReportOption: Equatable {
    public let text: String
    public let id: Data
    public init(text: String, id: Data) {
        self.text = text
        self.id = id
    }
}

public struct SponsoredReportPage: Equatable {
    public let title: String
    public let options: [SponsoredReportOption]
    public init(title: String, options: [SponsoredReportOption]) {
        self.title = title
        self.options = options
    }
}

public enum FeatureModalKind {
    case premiumBoarding
    case previewSender
}

public struct FeatureNavigationHooks {
    public var showPremiumBoarding: (any AccountContextProtocol, Window, PremiumBoardingSource?, Bool, TelegramPresentationTheme?) -> Void = { _, _, _, _, _ in }
    public var showPremiumBoardingWithContext: ((any AccountContextProtocol, Window, PremiumBoardingSource?, Bool, TelegramPresentationTheme?) -> Void)?

    public func showPremiumBoardingObserved(_ context: any AccountContextProtocol, _ window: Window, _ source: PremiumBoardingSource?, _ openFeatures: Bool, _ theme: TelegramPresentationTheme?) {
        if let showPremiumBoardingWithContext {
            showPremiumBoardingWithContext(context, window, source, openFeatures, theme)
        } else {
            showPremiumBoarding(context, window, source, openFeatures, theme)
        }
    }
    public var showPremiumLimit: (any AccountContextProtocol, PremiumLimitKind) -> Void = { _, _ in }
    public var showPremiumLimitWithContext: ((any AccountContextProtocol, PremiumLimitKind) -> Void)?

    public func showPremiumLimitObserved(_ context: any AccountContextProtocol, _ kind: PremiumLimitKind) {
        if let showPremiumLimitWithContext {
            showPremiumLimitWithContext(context, kind)
        } else {
            showPremiumLimit(context, kind)
        }
    }
    public var makePremiumLockModal: () -> ModalViewController? = { nil }
    public var showStarsPurchase: (any AccountContextProtocol, Window, CurrencyAmount.Currency, String?, Int64?) -> Void = { _, _, _, _, _ in }
    public var showStarsPurchaseWithContext: (any AccountContextProtocol, Window, CurrencyAmount.Currency, String?, Int64?) -> Void = { _, _, _, _, _ in }
    public var selectDate: (any AccountContextProtocol, Window, Date?, Int32?, DateSelectorRequest, @escaping (Date, Int32?) -> Void) -> Void = { _, _, _, _, _, _ in }
    public var selectDateWithContext: ((any AccountContextProtocol, Window, Date?, Int32?, DateSelectorRequest, @escaping (Date, Int32?) -> Void, @escaping () -> Void) -> Void)?
    public var selectDateWithDismissal: ((any AccountContextProtocol, Window, Date?, Int32?, DateSelectorRequest, @escaping (Date, Int32?) -> Void, @escaping () -> Void, @escaping () -> Void) -> Void)?

    public func selectDateObserved(_ context: any AccountContextProtocol, _ window: Window, _ defaultDate: Date?, _ repeatPeriod: Int32?, _ request: DateSelectorRequest, selectedAt: @escaping (Date, Int32?) -> Void, cancelled: @escaping () -> Void, dismissed: @escaping () -> Void) {
        if let selectDateWithDismissal {
            selectDateWithDismissal(context, window, defaultDate, repeatPeriod, request, selectedAt, cancelled, dismissed)
        } else {
            dismissed()
            selectDateObserved(context, window, defaultDate, repeatPeriod, request, selectedAt: selectedAt, cancelled: cancelled)
        }
    }

    public func selectDateObserved(_ context: any AccountContextProtocol, _ window: Window, _ defaultDate: Date?, _ repeatPeriod: Int32?, _ request: DateSelectorRequest, selectedAt: @escaping (Date, Int32?) -> Void, cancelled: @escaping () -> Void) {
        if let selectDateWithContext = selectDateWithContext {
            selectDateWithContext(context, window, defaultDate, repeatPeriod, request, selectedAt, cancelled)
        } else {
            selectDate(context, window, defaultDate, repeatPeriod, request, { date, period in
                do {
                    selectedAt(date, period)
                }
            })
        }
    }
    public var selectTimeRange: (any AccountContextProtocol, Window, TimePickerOption, TimePickerOption, String, String, String, String, @escaping (TimePickerOption, TimePickerOption) -> Void) -> Void = { _, _, _, _, _, _, _, _, _ in }
    public var showInactiveChannels: (any AccountContextProtocol, InactiveChannelsReason) -> Void = { _, _ in }
    public var showInactiveChannelsWithContext: ((any AccountContextProtocol, InactiveChannelsReason) -> Void)?

    public func showInactiveChannelsObserved(_ context: any AccountContextProtocol, _ reason: InactiveChannelsReason) {
        if let showInactiveChannelsWithContext {
            showInactiveChannelsWithContext(context, reason)
        } else {
            showInactiveChannels(context, reason)
        }
    }

    public var reportContent: (any AccountContextProtocol, ReportContentSubject, String) -> Void = { _, _, _ in }
    public var showSponsoredReport: (any AccountContextProtocol, Window, String, String?, String, SponsoredReportPage, @escaping (SponsoredReportOption) -> Signal<SponsoredReportPage?, NoError>) -> Void = { _, _, _, _, _, _, _ in }
    public var makeRecentSessionsController: (any AccountContextProtocol) -> ViewController? = { _ in nil }
    public var makeProxyListController: (any AccountContextProtocol, @escaping ([ProxyServerSettings]) -> Void, @escaping (ViewController) -> Void) -> ViewController? = { _, _, _ in nil }
    public var makeInviteLinksController: (any AccountContextProtocol, PeerId, Bool) -> ViewController? = { _, _, _ in nil }
    public var makeRequestJoinMembersController: (any AccountContextProtocol, PeerId, PeerInvitationImportersContext, @escaping () -> Void) -> ViewController? = { _, _, _, _ in nil }
    public var showInvitePrivacyLimited: (any AccountContextProtocol, PeerId, [PeerId], [TelegramForbiddenInvitePeer]) -> Void = { _, _, _, _ in }
    public var openStoryStats: (any AccountContextProtocol, EngineStoryItem, EnginePeer) -> Void = { _, _, _ in }
    public var openStoryStatsWithContext: ((any AccountContextProtocol, EngineStoryItem, EnginePeer) -> Void)?
    public func openStoryStatsObserved(_ context: any AccountContextProtocol, _ item: EngineStoryItem, _ peer: EnginePeer) {
        if let openStoryStatsWithContext {
            openStoryStatsWithContext(context, item, peer)
        } else {
            openStoryStats(context, item, peer)
        }
    }
    public var showBoostInfo: (any AccountContextProtocol, Window, Peer, ChannelBoostStatus, MyBoostStatus?, BoostInfoSource, TelegramPresentationTheme?) -> Void = { _, _, _, _, _, _, _ in }
    public var hasFeatureModal: (FeatureModalKind, ModalViewController?) -> Bool = { _, _ in false }
    public var makeVerifyAgeController: (any AccountContextProtocol) -> ModalViewController? = { _ in nil }
    public var makeCalendarController: (Window, Date, Int, Bool, @escaping (Date) -> Void) -> ViewController? = { _, _, _, _, _ in nil }
    public var makeSelectCountriesController: (any AccountContextProtocol, [Country], @escaping ([Country]) -> Void) -> ModalViewController? = { _, _, _ in nil }
    public var makePaymentsCheckoutController: (any AccountContextProtocol, BotPaymentInvoiceSource, TelegramMediaInvoice, ((PaymentCheckoutResult) -> Void)?) -> ModalViewController? = { _, _, _, _ in nil }
    public var makePaymentsCheckoutControllerWithContext: ((any AccountContextProtocol, BotPaymentInvoiceSource, TelegramMediaInvoice, ((PaymentCheckoutResult) -> Void)?) -> ModalViewController?)?

    public func makePaymentsCheckoutObserved(_ context: any AccountContextProtocol, _ source: BotPaymentInvoiceSource, _ invoice: TelegramMediaInvoice, completion: ((PaymentCheckoutResult) -> Void)?) -> ModalViewController? {
        let observedCompletion: ((PaymentCheckoutResult) -> Void)? = completion.map { completion in
            return { result in
                completion(result)
            }
        }
        let controller: ModalViewController?
        if let makePaymentsCheckoutControllerWithContext {
            controller = makePaymentsCheckoutControllerWithContext(context, source, invoice, observedCompletion)
        } else {
            controller = makePaymentsCheckoutController(context, source, invoice, observedCompletion)
        }
        guard let controller else {
            return nil
        }
        let onDeinit = controller.onDeinit
        controller.onDeinit = {
            onDeinit?()
        }
        return controller
    }

    public var emptyChatControllerType: () -> ViewController.Type? = { nil }
    public var openInstantView: (any AccountContextProtocol, String, TelegramMediaWebpage) -> Void = { _, _, _ in }
    public var requestUserLocation: () -> Signal<UserLocationRequestResult, NoError> = { .single(.disabled) }
    public var makeLocationPreviewController: (any AccountContextProtocol, String) -> Signal<ModalViewController?, NoError> = { _, _ in .single(nil) }
    public var fullExportRowTitle: () -> String = { "" }
    public var fullExportRowInfo: () -> String = { "" }
    public var showFullExportModal: (any AccountContextProtocol) -> Void = { _ in }
    public var makeGigagroupLandingController: (any AccountContextProtocol, PeerId) -> ModalViewController? = { _, _ in nil }
    public var openJoinChatBotWebView: (any AccountContextProtocol, PeerId, String?, Int64, PeerId?) -> Void = { _, _, _, _, _ in }
    public var openJoinChatBotWebViewWithContext: ((any AccountContextProtocol, PeerId, String?, Int64, PeerId?) -> Void)?

    public func openJoinChatBotWebViewObserved(_ context: any AccountContextProtocol, _ botId: PeerId, _ url: String?, _ queryId: Int64, _ joinedPeerId: PeerId?) {
        if let openJoinChatBotWebViewWithContext {
            openJoinChatBotWebViewWithContext(context, botId, url, queryId, joinedPeerId)
        } else {
            openJoinChatBotWebView(context, botId, url, queryId, joinedPeerId)
        }
    }

    public var makeGroupCallAvatarMenuItem: (Peer, any AccountContextProtocol) -> ContextMenuItem? = { _, _ in nil }
    public var selectGroupCallJoiner: (any AccountContextProtocol, PeerId, @escaping (PeerId, Date?, Bool) -> Void) -> Void = { _, _, _ in }
    public var makeLinkInvitationController: (any AccountContextProtocol, PeerId) -> ViewController? = { _, _ in nil }
    public var makeTwoStepAccessController: (any AccountContextProtocol, @escaping (ViewController, Bool, Bool) -> Void) -> ViewController? = { _, _ in nil }
    public var createSupergroup: (any AccountContextProtocol, String) -> Signal<PeerId?, NoError> = { _, _ in .single(nil) }
    public var shareLink: (any AccountContextProtocol, Window, String) -> Void = { _, _, _ in }
    public var makeChannelAdminController: (any AccountContextProtocol, PeerId, PeerId, ChannelParticipant?, @escaping (TelegramChatAdminRights?) -> Void, @escaping (PeerId, @escaping () -> Void) -> Void) -> ModalViewController? = { _, _, _, _, _, _ in nil }
    public var makeChannelAdminControllerWithContext: ((any AccountContextProtocol, PeerId, PeerId, ChannelParticipant?, @escaping (TelegramChatAdminRights?) -> Void, @escaping (PeerId, @escaping () -> Void) -> Void) -> ModalViewController?)?
    public func makeChannelAdminControllerObserved(_ context: any AccountContextProtocol, _ peerId: PeerId, _ adminId: PeerId, _ participant: ChannelParticipant?, _ updated: @escaping (TelegramChatAdminRights?) -> Void, _ upgraded: @escaping (PeerId, @escaping () -> Void) -> Void) -> ModalViewController? {
        if let makeChannelAdminControllerWithContext {
            return makeChannelAdminControllerWithContext(context, peerId, adminId, participant, updated, upgraded)
        } else {
            return makeChannelAdminController(context, peerId, adminId, participant, updated, upgraded)
        }
    }
    public var applyGroupCallResult: (any SharedAccountContextProtocol, AnyObject) -> Void = { _, _ in }
    public var fileSizeLimitExceed: (any AccountContextProtocol, Int64) -> Bool = { _, _ in true }
    public var showFileLimit: (any AccountContextProtocol, Int64?) -> Void = { _, _ in }
    public var makePreviewSender: ([URL], AnyObject, Bool, NSAttributedString?, TelegramPresentationTheme?) -> ModalViewController? = { _, _, _, _, _ in nil }
    public var makePreviewSenderWithContext: ([URL], AnyObject, Bool, NSAttributedString?, TelegramPresentationTheme?) -> ModalViewController? = { _, _, _, _, _ in nil }
    public var makeArchiveSettingsController: (any AccountContextProtocol, GlobalPrivacySettings?, @escaping (GlobalPrivacySettings) -> Void) -> ViewController? = { _, _, _ in nil }
    public var updateAccountBirthday: (Date, any AccountContextProtocol) -> Void = { _, _ in }

    public init() {}

    private static var installed: FeatureNavigationHooks?

    public static var shared: FeatureNavigationHooks {
        return installed ?? FeatureNavigationHooks()
    }

    public static var isInstalled: Bool {
        return installed != nil
    }

    public static func install(_ hooks: FeatureNavigationHooks) {
        installed = hooks
    }
}
