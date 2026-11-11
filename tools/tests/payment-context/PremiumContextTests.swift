import Foundation
import XCTest
import SwiftSignalKit

public final class Window {}
public final class PremiumEngine { let payments = PremiumPayments() }
public enum PremiumInvoiceError: Error { case failed }
public final class PremiumPayments {
    var eligibility: Signal<Bool, NoError> = .single(true)
    var eligibilityChecks = 0
    func canPurchasePremium(purpose: AppStoreTransactionPurpose) -> Signal<Bool, NoError> { eligibilityChecks += 1; return eligibility }
    var source: Signal<TelegramMediaInvoice, PremiumInvoiceError> = .complete()
    var fetch: (() -> Void)?
    func fetchBotPaymentInvoice(source: BotPaymentInvoiceSource) -> Signal<TelegramMediaInvoice, PremiumInvoiceError> { fetch?(); return self.source }
}
public struct PeerId: Equatable {
    public struct Id: Equatable { func _internalGetInt64Value() -> Int64 { 1 } }
    let id = Id()
}
public enum StarGift { public struct Gift: Equatable {} }
public enum PremiumValue {
    case business_location, business_hours, quick_replies, greeting_message, away_message, business_bots, business_links
    case double_limits, more_upload, infinite_reactions, premium_stickers, animated_emoji, translations, stories, no_ads, saved_tags, last_seen, message_privacy, pm_noforwards, business_intro, folder_tags, emoji_status, todo, ai_compose, rich_formatting
}
__PREMIUM_SOURCE_ENUM__
__NAVIGATION_SOURCE_ENUM__
__SOURCE_MAPPING__
public struct TelegramPresentationTheme { public init() {} }
public let theme = TelegramPresentationTheme()
public enum PremiumBoardingEntryTag {}
public enum AnalyticsScreen { case settingsBusiness, premiumBusiness, premiumPromo }
typealias FeatureNavigationHooks = Hooks
__BOARDING__
__PRESENT__
__INVOICE__
func installedPremiumHooks() -> Hooks {
    var hooks = Hooks()
__INSTALL__
    return hooks
}
struct PremiumStrings {
    let premiumBoardingAppStoreSuccess = "store success"
    let premiumPurchaseErrorUnknown = "unknown store error"
    let premiumPurchaseErrorNetwork = "network error"
    let premiumPurchaseErrorNotAllowed = "not allowed"
    let premiumPurchaseErrorCantMakePayments = "cannot pay"
    let premiumBoardingAppStoreCancelled = "cancelled"
    let premiumRestoreSuccess = "restore success"
    let premiumRestoreErrorUnknown = "restore failed"
    let paymentsInvoiceNotExists = "unavailable invoice"
    let premiumBoardingPaymentNotAvailalbe = "unavailable premium"
}
func strings() -> PremiumStrings { PremiumStrings() }
enum PremiumUI {
    static var modals: [ModalViewController] = []
    static var confetti = 0
    static var feedback: [String] = []
    static var onFeedback: (() -> Void)?
    static var onProgress: (() -> Void)?
}
func showModal(with controller: ModalViewController, for window: Window, morphSource: (() -> NSView?)? = nil) { PremiumUI.modals.append(controller) }
public class NSView {}
func showModalText(for window: Window, text: String) { PremiumUI.onFeedback?(); PremiumUI.feedback.append(text) }
func PlayConfetti(for window: Window) { PremiumUI.confetti += 1 }
func showModalProgress<T, E>(signal: Signal<T, E>, for window: Window) -> Signal<T, E> {
    PremiumUI.onProgress?()
    return signal
}

final class PremiumContextTests: XCTestCase {
    override func setUp() {
        Hooks.shared = Hooks()
        PremiumUI.modals = []
        PremiumUI.confetti = 0
        PremiumUI.feedback = []
        PremiumUI.onFeedback = nil
        PremiumUI.onProgress = nil
    }
    override func tearDown() { PremiumUI.modals = []; Hooks.shared = Hooks() }
    func testEffectsSourceUsesOverviewAndRemainsDistinctFromSavedTags() {
        let source = PremiumBoardingSource.messageEffects.logSource
        XCTAssertEqual(source, .message_effects)
        XCTAssertEqual(source.value, "message_effects")
        XCTAssertNil(source.features)
        XCTAssertEqual(PremiumBoardingSource.savedTags.logSource, .saved_tags)
        XCTAssertEqual(PremiumBoardingSource.savedTags.logSource.features, .saved_tags)
        let controller = PremiumBoardingController(context: AccountContext(), source: source, analyticsContext: AnalyticsContext(excluded: true))
        XCTAssertEqual(controller.analyticsScreen, .premiumPromo)
    }
    func testExplicitOriginSurvivesReplacingOnDeinitAndParentRelease() {
        let origin = AnalyticsContext(excluded: true)
        let parent = origin.beginPresentation()
        var child: PremiumBoardingController? = PremiumBoardingController(context: AccountContext(), analyticsContext: origin)
        XCTAssertTrue(child?.analyticsContext === origin)
        XCTAssertEqual(origin.depth, 2)
        var cleaned = 0
        child?.onDeinit = { cleaned += 1 }
        parent.end()
        XCTAssertEqual(origin.depth, 1)
        child = nil
        XCTAssertEqual(origin.depth, 0)
        XCTAssertEqual(cleaned, 1)
    }
    func testExistingInitializerStillConstructsAndDoesNotInventOrigin() {
        let child = PremiumBoardingController(context: AccountContext())
        XCTAssertNil(child.analyticsContext)
        XCTAssertEqual(child.analyticsScreen, .premiumPromo)
    }
    func testInstalledHookBindsAndRetainsOriginForShownRoot() {
        let origin = AnalyticsContext(excluded: true)
        let hooks = installedPremiumHooks()
        let context = AccountContext()
        hooks.showPremiumBoardingObserved(context, context.window, .savedTags, true, nil, analyticsContext: origin)
        XCTAssertEqual(PremiumUI.modals.count, 1)
        XCTAssertTrue(PremiumUI.modals[0].analyticsContext === origin)
        XCTAssertEqual(origin.depth, 1)
        PremiumUI.modals = []
        XCTAssertEqual(origin.depth, 0)
    }
    func testBlockedPresentationAndLegacyFallbackStayInsideOriginDelivery() {
        let origin = AnalyticsContext(excluded: true)
        var context = AccountContext()
        context.premiumIsBlocked = true
        PremiumUI.onFeedback = { XCTAssertGreaterThan(origin.depth, 0) }
        installedPremiumHooks().showPremiumBoardingObserved(context, context.window, nil, false, nil, analyticsContext: origin)
        XCTAssertEqual(PremiumUI.feedback, ["unavailable premium"])
        XCTAssertTrue(PremiumUI.modals.isEmpty)
        XCTAssertEqual(origin.depth, 0)
        var legacy = Hooks()
        var calls = 0
        legacy.showPremiumBoarding = { _, _, _, _, _ in calls += 1; XCTAssertEqual(origin.depth, 1) }
        legacy.showPremiumBoardingObserved(context, context.window, nil, false, nil, analyticsContext: origin)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(origin.depth, 0)
    }
    func testInvoiceAfterParentEndsConstructsBoundCheckoutAndCompletesOnce() {
        let origin = AnalyticsContext(excluded: true)
        let context = AccountContext()
        let parent = origin.beginPresentation()
        var next: ((TelegramMediaInvoice) -> Void)?
        var disposed = 0
        context.engine.payments.source = Signal { subscriber in
            XCTAssertGreaterThan(origin.depth, 0)
            next = { subscriber.putNext($0) }
            return ActionDisposable { disposed += 1 }
        }
        context.engine.payments.fetch = { XCTAssertGreaterThan(origin.depth, 0) }
        PremiumUI.onProgress = { XCTAssertGreaterThan(origin.depth, 0) }
        var completion: ((PaymentCheckoutResult) -> Void)?
        Hooks.shared.makePaymentsCheckoutControllerWithContext = { _, _, _, received, callback in
            XCTAssertTrue(received === origin)
            XCTAssertGreaterThan(origin.depth, 0)
            completion = callback
            return InputDataModalController()
        }
        var paid = 0
        premiumInvoiceCheckout(context: context, slug: "synthetic", analyticsContext: origin) {
            XCTAssertGreaterThan(origin.depth, 0)
            paid += 1
        }
        parent.end()
        XCTAssertGreaterThan(origin.depth, 0)
        next?(TelegramMediaInvoice())
        next?(TelegramMediaInvoice())
        XCTAssertEqual(disposed, 1)
        XCTAssertEqual(PremiumUI.modals.count, 1)
        XCTAssertTrue(PremiumUI.modals[0].analyticsContext === origin)
        XCTAssertTrue((PremiumUI.modals[0] as? InputDataModalController)?.current.analyticsContext === origin)
        PremiumUI.modals = []
        completion?(.paid); completion?(.paid); completion?(.failed)
        XCTAssertEqual(paid, 1)
        XCTAssertEqual(PremiumUI.confetti, 1)
        XCTAssertEqual(origin.depth, 0)
    }
    func testErrorAfterParentEndsKeepsFeedbackExcludedAndReleasesSubscription() {
        let origin = AnalyticsContext(excluded: true)
        let context = AccountContext()
        var fail: (() -> Void)?
        var disposed = 0
        context.engine.payments.source = Signal { subscriber in
            fail = { subscriber.putError(.failed) }
            return ActionDisposable { disposed += 1 }
        }
        let parent = origin.beginPresentation()
        PremiumUI.onFeedback = { XCTAssertGreaterThan(origin.depth, 0) }
        premiumInvoiceCheckout(context: context, slug: "synthetic", analyticsContext: origin, paid: { XCTFail("No checkout") })
        parent.end()
        fail?()
        XCTAssertEqual(PremiumUI.feedback, ["unavailable invoice"])
        XCTAssertTrue(PremiumUI.modals.isEmpty)
        XCTAssertEqual(origin.depth, 0)
        XCTAssertEqual(disposed, 1)
    }
    func testEmptyInvoiceCompletionOrMissingFactoryDoesNotInventPayment() {
        for empty in [false, true] {
            let origin = AnalyticsContext(excluded: true)
            let context = AccountContext()
            context.engine.payments.source = empty ? .complete() : .single(TelegramMediaInvoice())
            premiumInvoiceCheckout(context: context, slug: "synthetic", analyticsContext: origin, paid: { XCTFail("Unknown output") })
            XCTAssertTrue(PremiumUI.modals.isEmpty)
            XCTAssertTrue(PremiumUI.feedback.isEmpty)
            XCTAssertEqual(origin.depth, 0)
        }
    }
    func testCancelledAndFailedCheckoutDoNotInvokePaidFeedback() {
        for result in [PaymentCheckoutResult.cancelled, .failed] {
            let origin = AnalyticsContext(excluded: false)
            let context = AccountContext()
            context.engine.payments.source = .single(TelegramMediaInvoice())
            var completion: ((PaymentCheckoutResult) -> Void)?
            Hooks.shared.makePaymentsCheckoutControllerWithContext = { _, _, _, _, callback in
                completion = callback
                return ModalViewController()
            }
            premiumInvoiceCheckout(context: context, slug: "synthetic", analyticsContext: origin, paid: { XCTFail("Not paid") })
            completion?(result)
            completion?(.paid)
            XCTAssertEqual(PremiumUI.confetti, 0)
            PremiumUI.modals = []
            XCTAssertEqual(origin.depth, 0)
        }
    }
}
