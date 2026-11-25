import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int64
struct MessageId: Equatable { let peerId: PeerId }
final class Scope { var valid = true }
final class AnalyticsContext {
    let owner: Int
    let isExcluded: Bool
    let scope: Scope?
    init(_ owner: Int = 1, excluded: Bool = false, scope: Scope? = Scope()) { self.owner = owner; self.isExcluded = excluded; self.scope = excluded ? nil : scope }
    func restricting(peerId: PeerId) -> AnalyticsContext { AnalyticsContext(owner, excluded: isExcluded || peerId < 0, scope: scope) }
    func beginPresentation() -> AnalyticsPresentation { AnalyticsPresentation(self) }
__SIGNAL__
}
final class AnalyticsPresentation {
    let excluded: Bool
    var active = true
    init(_ context: AnalyticsContext) { excluded = context.isExcluded || context.scope?.valid != true; if excluded { UI.exclusions += 1 } }
    func end() { guard active else { return }; active = false; if excluded { UI.exclusions -= 1 } }
    deinit { end() }
}
final class Analytics {
    static let shared = Analytics()
    func send(_ event: Int) { if UI.exclusions == 0 { UI.successEvents += 1 } }
    func unresolvedContext() -> AnalyticsContext { AnalyticsContext(excluded: true) }
    func captureContext(engine: Engine, peerId: PeerId, inherited: AnalyticsContext) -> AnalyticsContext {
        AnalyticsContext(engine.owner, excluded: inherited.isExcluded || peerId < 0, scope: inherited.owner == engine.owner ? inherited.scope : nil)
    }
}
protocol AccountContextProtocol: AnyObject {
    var engine: Engine { get }; var peerId: PeerId { get }; var window: Window { get }
    var inAppPurchaseManager: StoreManager { get }; var starsContext: StarsContext { get }; var starsSubscriptionsContext: StarsContext { get }
}
final class Context: AccountContextProtocol {
    let engine: Engine
    let inAppPurchaseManager = StoreManager()
    let peerId: PeerId = 1
    let window = Window()
    let starsContext = StarsContext(), starsSubscriptionsContext = StarsContext()
    init(_ owner: Int = 1) { engine = Engine(owner) }
}
final class Window {}
final class Engine { let owner: Int; let payments = Payments(); let data = DataEngine(); init(_ owner: Int) { self.owner = owner } }
struct Peer: Equatable { let id: PeerId; var displayTitle: String { "synthetic" } }
struct EnginePeer: Equatable {
    let id: PeerId
    init(_ user: TelegramUser) { id = user.id }
    init(id: PeerId) { self.id = id }
    func _asPeer() -> Peer { Peer(id: id) }
}
enum NameColor { case preset(Int) }
struct TelegramUser {
    let id: PeerId
    init(id: PeerId, accessHash: Int?, firstName: String, lastName: String?, username: String?, phone: String?, photo: [Int], botInfo: Int?, restrictionInfo: Int?, flags: [Int], emojiStatus: Int?, usernames: [String], storiesHidden: Bool?, nameColor: NameColor?, backgroundEmojiId: Int?, profileColor: Int?, profileBackgroundEmojiId: Int?, subscriberCount: Int?, verificationIconFileId: Int?) { self.id = id }
}
struct StarsAmount: Equatable { let value: Int64; var nanos: Int = 0 }
final class StarsContext {
    struct State: Equatable { let balance: StarsAmount }
    var state: Signal<State?, NoError> = .single(State(balance: StarsAmount(value: 20)))
    var loads = 0
    func load(force: Bool) { loads += 1; UI.onLoad?() }
}
struct TelegramMediaInvoice: Equatable { var totalAmount: Int64 = 10; var title = "synthetic" }
struct Invite: Equatable {
    struct Pricing: Equatable { let amount: StarsAmount }
    var subscriptionPricing: Pricing? = Pricing(amount: StarsAmount(value: 10))
    var photoRepresentation: Int?
    var title = "synthetic", nameColor: Int?
    var subscriptionFormId: Int64? = 3
}
enum StarPurchaseType: Equatable { case bot, paidMedia, subscription(Invite), botSubscription(TelegramMediaInvoice) }
enum StarPurchaseCompletionStatus: Equatable { case paid(messageId: MessageId?, peerId: PeerId?), failed, cancelled }
enum BotPaymentInvoiceSource { case stars(option: TopUpOption, peerId: PeerId?), starsGift(peerId: PeerId, count: Int64, currency: String, amount: Int64); case message(MessageId), slug(String), starsChatSubscription(hash: String) }
struct PaymentForm { let id: Int64; let paymentBotId: PeerId? }
enum PaymentError: Error { case alreadyPaid, generic, paymentFailed, precheckoutFailed, starGiftOutOfStock, disallowedStarGift, starGiftUserLimit, serverProvided(String) }
enum PaymentResult { case done(MessageId?, PeerId?, Int?), externalVerificationRequired(url: String) }
final class Payments {
    var eligibility: Signal<Bool, NoError> = .single(true)
    var eligibilityCalls = 0
    var invoice: Signal<TelegramMediaInvoice, PaymentError> = .single(TelegramMediaInvoice())
    func canPurchasePremium(purpose: AppStoreTransactionPurpose) -> Signal<Bool, NoError> { eligibilityCalls += 1; UI.onEligibility?(); return eligibility }
    func fetchBotPaymentInvoice(source: BotPaymentInvoiceSource) -> Signal<TelegramMediaInvoice, PaymentError> { UI.onInvoice?(); return invoice }

    var form: Signal<PaymentForm, PaymentError> = .single(PaymentForm(id: 3, paymentBotId: 2))
    var payment: Signal<PaymentResult, PaymentError> = .complete()
    var requests: [Int64] = []
    var formRequests = 0
    func fetchBotPaymentForm(source: BotPaymentInvoiceSource, themeParams: Int?) -> Signal<PaymentForm, PaymentError> { formRequests += 1; UI.onForm?(); return form }
    func sendStarsPaymentForm(formId: Int64, source: BotPaymentInvoiceSource) -> Signal<PaymentResult, PaymentError> { requests.append(formId); UI.onPayment?(); return payment }
}
enum TelegramEngine { enum EngineData { enum Item { enum Peer { struct Peer { let id: PeerId } } } } }
final class DataEngine {
    var peer: Signal<EnginePeer?, NoError> = .single(EnginePeer(id: 2))
    var requests: [PeerId] = []
    func subscribe(_ item: TelegramEngine.EngineData.Item.Peer.Peer) -> Signal<EnginePeer?, NoError> { requests.append(item.id); UI.onPeer?(); return peer }
}
__TYPES__
func entries(_ state: State, arguments: Arguments) -> [Int] { UI.state = state; UI.arguments = arguments; UI.onEntries?(); return [] }
struct InputDataSignalValue { let entries: [Int] }
func deliverOnPrepareQueue<T, E>(_ signal: Signal<T, E>) -> Signal<T, E> { signal }
enum Screen { case starsPayment }
class ViewController {
    var analyticsContext: AnalyticsContext?
    var onDeinit: (() -> Void)?
    var window: Window? = Window()
    deinit { onDeinit?() }
}
final class InputDataController: ViewController {
    var analyticsScreen: Screen?
    var contextObject: AnyObject?
    let subscription: Disposable
    init(dataSignal: Signal<InputDataSignalValue, NoError>, title: String) {
        subscription = dataSignal.start(next: { _ in }); super.init()
    }
    deinit { subscription.dispose() }
}
final class NativeModal { func close() { UI.closed += 1 } }
final class InputDataModalController: ViewController {
    let current: InputDataController
    let closeHandler: (@escaping () -> Void) -> Void
    let modal: NativeModal? = NativeModal()
    init(_ current: InputDataController, modalInteractions: Int?, closeHandler: @escaping (@escaping () -> Void) -> Void = { $0() }) {
        self.current = current; self.closeHandler = closeHandler; super.init()
    }
    func close() { closeHandler { self.modal?.close() } }
}
enum Star_ListScreenSource { case account, buy(suffix: String?, amount: Int64?), gift(EnginePeer), prolongSubscription(EnginePeer, Int64), reactions(EnginePeer, Int64); case purchase(EnginePeer, Int64), purchaseSubscribe(EnginePeer, Int64) }
func Star_ListScreen(context: any AccountContextProtocol, source: Star_ListScreenSource, analyticsContext: AnalyticsContext?) -> InputDataModalController {
    UI.topUpSources.append(source); UI.topUpContext = analyticsContext; UI.onTopUp?()
    let modal = InputDataModalController(InputDataController(dataSignal: .complete(), title: ""), modalInteractions: nil)
    modal.onDeinit = { UI.onTopUpDeinit?() }
    return modal
}
func showModal(with controller: InputDataModalController, for window: Window) { UI.topups.append(controller); UI.onShow?() }
func showModalProgress<T, E>(signal: Signal<T, E>, for window: Window) -> Signal<T, E> { UI.onProgress?(); return signal }
func showModalText(for window: Window, text: String) { UI.texts.append(text); UI.onText?() }
func PlayConfetti(for window: Window, stars: Bool) { UI.confetti += 1 }
struct Strings {
    let starListSpendTopupUnavailable = "disabled", paymentsInvoiceNotExists = "missing"
    let premiumPurchaseErrorUnknown = "unknown", premiumPurchaseErrorNetwork = "network", premiumPurchaseErrorNotAllowed = "not allowed", premiumPurchaseErrorCantMakePayments = "cannot", premiumBoardingAppStoreCancelled = "cancelled"
    func starListBuySuccessOther(_ count: Int) -> String { "paid" }
    let checkoutErrorInvoiceAlreadyPaid = "already", unknownError = "unknown", checkoutErrorPaymentFailed = "failed", checkoutErrorPrecheckoutFailed = "precheckout", giftSoldOutError = "sold", giftSendDisallowError = "disallowed", giftOptionsGiftBuyLimitReached = "limit"
    func starPurchaseTextInOther(_ count: Int) -> String { "count" }
    func starPurchaseSuccess(_ info: String, _ peer: String, _ amount: String) -> String { "paid" }
    func starPurchasePaidMediaSuccess(_ amount: String) -> String { "media" }
    func starsPurchaseSubscribeSuccess(_ title: String) -> String { "subscription" }
    func starsPurchaseBotSubscribeSuccess(_ title: String, _ peer: String) -> String { "bot subscription" }
}
func strings() -> Strings { Strings() }
__SESSION__
__SCREEN__
__FACTORY__
enum UI {
    static var onEligibility: (() -> Void)?, onInvoice: (() -> Void)?, onStore: (() -> Void)?, onCheckout: (() -> Void)?
    static var storeWindows: [ViewController] = []
    static var delayed: [() -> Void] = []
    static var successEvents = 0
    static var checkoutCompletion: ((CheckoutResult) -> Void)?
    static var checkout: ModalViewController?
    static var checkoutAvailable = true

    static var exclusions = 0, closed = 0, confetti = 0
    static var onLoad: (() -> Void)?, onForm: (() -> Void)?, onPeer: (() -> Void)?, onPayment: (() -> Void)?, onProgress: (() -> Void)?, onEntries: (() -> Void)?, onTopUp: (() -> Void)?, onShow: (() -> Void)?, onText: (() -> Void)?, onTopUpDeinit: (() -> Void)?
    static var arguments: Arguments?
    static var state: State?
    static var topups: [InputDataModalController] = []
    static var topUpContext: AnalyticsContext?
    static var topUpSources: [Star_ListScreenSource] = []
    static var texts: [String] = []
    static func reset() {
        onEligibility = nil; onInvoice = nil; onStore = nil; onCheckout = nil
        storeWindows = []; delayed = []; successEvents = 0; checkoutCompletion = nil; checkout = nil; checkoutAvailable = true
        arguments = nil; state = nil; topups = []; topUpSources = []; topUpContext = nil; texts = []; closed = 0; confetti = 0
        onLoad = nil; onForm = nil; onPeer = nil; onPayment = nil; onProgress = nil; onEntries = nil; onTopUp = nil; onShow = nil; onText = nil; onTopUpDeinit = nil
    }
}
final class PurchaseTests: XCTestCase {
    override func setUp() { UI.reset(); XCTAssertEqual(UI.exclusions, 0) }
    override func tearDown() { UI.reset(); XCTAssertEqual(UI.exclusions, 0) }
    func make(_ context: Context, origin: AnalyticsContext? = nil, source: BotPaymentInvoiceSource = .slug("synthetic"), completion: @escaping (StarPurchaseCompletionStatus) -> Void = { _ in }) -> InputDataModalController {
        Star_PurschaseInApp(context: context, invoice: TelegramMediaInvoice(), source: source, analyticsContext: origin, completion: completion)
    }
    func testLegacyAndPrivatePreparationBindBothControllersAndDisposeUnderOrigin() {
        let context = Context()
        var balance: Subscriber<StarsContext.State?, NoError>?
        var disposed = false
        context.starsContext.state = Signal { balance = $0; XCTAssertGreaterThan(UI.exclusions, 0); return ActionDisposable { disposed = true; XCTAssertGreaterThan(UI.exclusions, 0) } }
        UI.onLoad = { XCTAssertGreaterThan(UI.exclusions, 0) }; UI.onForm = UI.onLoad; UI.onPeer = UI.onLoad; UI.onEntries = UI.onLoad
        var statuses: [StarPurchaseCompletionStatus] = []
        var modal: InputDataModalController? = Star_PurschaseInApp(context: context, invoice: TelegramMediaInvoice(), source: .slug("synthetic"), completion: { statuses.append($0) })
        XCTAssertTrue(modal?.analyticsContext?.isExcluded == true); XCTAssertTrue(modal?.current.analyticsContext === modal?.analyticsContext)
        balance?.putNext(.init(balance: .init(value: 30)))
        XCTAssertEqual(UI.state?.myBalance?.value, 30)
        modal?.close(); XCTAssertTrue(disposed); XCTAssertEqual(statuses, [.cancelled])
        let buy = UI.arguments?.buy; modal = nil; buy?(); balance = nil
        XCTAssertEqual(statuses, [.cancelled]); XCTAssertTrue(context.engine.payments.requests.isEmpty)
    }
    func testOrdinaryGrantIsPreservedAndMessageSecretOrForeignCannotPromoteIt() {
        let origin = AnalyticsContext()
        var modal: InputDataModalController? = make(Context(), origin: origin)
        XCTAssertTrue(modal?.analyticsContext?.scope === origin.scope); XCTAssertEqual(UI.exclusions, 0)
        modal = nil; UI.reset()
        modal = make(Context(), origin: origin, source: .message(MessageId(peerId: -5)))
        XCTAssertTrue(modal?.analyticsContext?.isExcluded == true); modal = nil; UI.reset()
        modal = make(Context(2), origin: origin)
        XCTAssertNil(modal?.analyticsContext?.scope); XCTAssertGreaterThan(UI.exclusions, 0); modal = nil
    }
    func testDuplicateBuyAndReentrantPaidClosureProduceOnePaymentAndNoCancellation() {
        let context = Context(); var response: Subscriber<PaymentResult, PaymentError>?
        context.engine.payments.payment = Signal { response = $0; return EmptyDisposable }
        var statuses: [StarPurchaseCompletionStatus] = []
        var modal: InputDataModalController?
        modal = make(context) { status in statuses.append(status); modal?.close(); UI.arguments?.buy() }
        UI.arguments?.buy(); UI.arguments?.buy()
        XCTAssertEqual(context.engine.payments.requests, [3])
        response?.putNext(.done(nil, 8, nil)); response?.putNext(.done(nil, 9, nil)); response = nil
        XCTAssertEqual(statuses, [.paid(messageId: nil, peerId: 8)])
        XCTAssertEqual(context.engine.payments.requests, [3]); XCTAssertEqual(UI.texts, ["paid"])
        modal = nil
        XCTAssertEqual(statuses.count, 1)
    }
    func testErrorAllowsReentrantRetryWithoutOldCompletionClearingNewAttempt() {
        let context = Context(); var responses: [Subscriber<PaymentResult, PaymentError>] = []
        context.engine.payments.payment = Signal { responses.append($0); return EmptyDisposable }
        var statuses: [StarPurchaseCompletionStatus] = []
        var modal: InputDataModalController? = make(context) { status in
            statuses.append(status)
            if status == .failed { UI.arguments?.buy() }
        }
        UI.arguments?.buy(); responses[0].putError(.generic)
        XCTAssertEqual(context.engine.payments.requests, [3, 3])
        UI.arguments?.buy(); XCTAssertEqual(context.engine.payments.requests.count, 2)
        responses[1].putNext(.done(nil, nil, nil)); responses = []
        XCTAssertEqual(statuses, [.failed, .paid(messageId: nil, peerId: nil)])
        modal?.close(); modal = nil
    }
    func testClosingDuringProgressSetupPreventsPaymentSubscription() {
        let context = Context(); var subscribed = false
        context.engine.payments.payment = Signal { _ in subscribed = true; return EmptyDisposable }
        let modal = make(context)
        UI.onProgress = { [weak modal] in modal?.close() }
        UI.arguments?.buy()
        XCTAssertEqual(context.engine.payments.requests.count, 1); XCTAssertFalse(subscribed)
    }
    func testClosingPendingPaymentDisposesAndRejectsLateSuccess() {
        let context = Context(); var response: Subscriber<PaymentResult, PaymentError>?; var disposed = false
        context.engine.payments.payment = Signal { response = $0; return ActionDisposable { disposed = true; XCTAssertGreaterThan(UI.exclusions, 0) } }
        var statuses: [StarPurchaseCompletionStatus] = []
        let modal = make(context) { statuses.append($0) }
        UI.arguments?.buy(); modal.close()
        XCTAssertTrue(disposed)
        response?.putNext(.done(nil, 9, nil)); response = nil; UI.arguments?.buy()
        XCTAssertEqual(statuses, [.cancelled]); XCTAssertTrue(UI.texts.isEmpty)
    }
    func testRevokedContextAndSecretResultAreRestrictedAtDelivery() {
        for secret in [false, true] {
            let context = Context(); let origin = AnalyticsContext(); var response: Subscriber<PaymentResult, PaymentError>?
            context.engine.payments.payment = Signal { response = $0; return EmptyDisposable }
            let modal = make(context, origin: origin) { _ in XCTAssertGreaterThan(UI.exclusions, 0) }
            UI.arguments?.buy()
            if !secret { origin.scope?.valid = false }
            UI.onText = { XCTAssertGreaterThan(UI.exclusions, 0) }
            response?.putNext(.done(secret ? MessageId(peerId: -8) : nil, nil, nil)); response = nil
            withExtendedLifetime(modal) {}; UI.reset()
        }
    }
    func testEmptyAndExternalVerificationNeverClaimPaidOrResubmit() {
        for signal: Signal<PaymentResult, PaymentError> in [.complete(), .single(.externalVerificationRequired(url: "synthetic"))] {
            let context = Context(); context.engine.payments.payment = signal
            var statuses: [StarPurchaseCompletionStatus] = []
            let modal = make(context) { statuses.append($0) }
            UI.arguments?.buy(); UI.arguments?.buy()
            XCTAssertEqual(context.engine.payments.requests.count, 1); XCTAssertTrue(statuses.isEmpty); XCTAssertTrue(UI.texts.isEmpty)
            modal.close(); XCTAssertEqual(statuses, [.cancelled]); UI.reset()
        }
    }
    func testTopUpOwnsPrivateLifetimeAfterParentClosesAndCannotReviveParent() {
        let context = Context(); context.starsContext.state = .single(.init(balance: .init(value: 0)))
        UI.onTopUp = { XCTAssertGreaterThan(UI.exclusions, 0); XCTAssertTrue(UI.topUpContext?.isExcluded == true) }
        UI.onTopUpDeinit = { XCTAssertGreaterThan(UI.exclusions, 0) }
        var modal: InputDataModalController? = make(context)
        UI.arguments?.buy(); UI.arguments?.buy()
        XCTAssertEqual(UI.topups.count, 1)
        XCTAssertTrue(UI.topups[0].analyticsContext?.isExcluded == true)
        XCTAssertTrue(UI.topups[0].current.analyticsContext === UI.topups[0].analyticsContext)
        let buy = UI.arguments?.buy
        modal?.close(); modal = nil; UI.arguments = nil
        XCTAssertGreaterThan(UI.exclusions, 0)
        UI.topups = []; buy?()
        XCTAssertEqual(UI.topUpSources.count, 1); XCTAssertTrue(context.engine.payments.requests.isEmpty)
    }
    func testTopUpDismissalAllowsBuyingWithUpdatedBalance() {
        let context = Context(); let balance = ValuePromise<StarsContext.State?>(.init(balance: .init(value: 0)))
        context.starsContext.state = balance.get()
        let modal = make(context)
        UI.arguments?.buy(); XCTAssertEqual(UI.topups.count, 1)
        balance.set(.init(balance: .init(value: 20)))
        UI.arguments?.buy(); XCTAssertTrue(context.engine.payments.requests.isEmpty)
        UI.topups = []; UI.arguments?.buy()
        XCTAssertEqual(context.engine.payments.requests, [3]); withExtendedLifetime(modal) {}
    }
    func testSubscriptionUsesInviteFormAndDoesNotTreatSyntheticDisplayPeerAsDestination() {
        let context = Context(); let origin = AnalyticsContext()
        context.engine.payments.payment = .single(.done(nil, 8, nil))
        var statuses: [StarPurchaseCompletionStatus] = []
        let modal = Star_PurschaseInApp(context: context, invoice: nil, source: .starsChatSubscription(hash: "synthetic"), type: .subscription(Invite()), analyticsContext: origin) { status in
            XCTAssertEqual(UI.exclusions, 0); statuses.append(status)
        }
        UI.arguments?.buy()
        XCTAssertEqual(context.engine.payments.formRequests, 0); XCTAssertEqual(context.engine.payments.requests, [3])
        XCTAssertEqual(statuses, [.paid(messageId: nil, peerId: 8)]); XCTAssertEqual(UI.confetti, 1); withExtendedLifetime(modal) {}
    }
    func testMissingBalancePeerOrFormDoesNotStartPayment() {
        for missing in 0..<3 {
            let context = Context()
            if missing == 0 { context.starsContext.state = .single(nil) }
            if missing == 1 { context.engine.data.peer = .single(nil) }
            var modal: InputDataModalController?
            if missing == 2 {
                modal = Star_PurschaseInApp(context: context, invoice: nil, source: .starsChatSubscription(hash: "synthetic"), type: .subscription(Invite(subscriptionFormId: nil)))
            } else { modal = make(context) }
            UI.arguments?.buy(); UI.arguments?.buy()
            XCTAssertTrue(context.engine.payments.requests.isEmpty); XCTAssertTrue(UI.topups.isEmpty)
            modal = nil; UI.reset()
        }
    }
    func testDelayedFormAfterCloseCannotLoadPeerOrMutateState() {
        let context = Context(); var form: Subscriber<PaymentForm, PaymentError>?
        context.engine.payments.form = Signal { form = $0; return EmptyDisposable }
        let modal = make(context)
        modal.close(); form?.putNext(.init(id: 9, paymentBotId: 9)); form = nil
        XCTAssertTrue(context.engine.data.requests.isEmpty); XCTAssertNil(UI.state?.formId)
    }
}

extension PurchaseTests {
    func testSynchronousErrorRetryOwnsNewPendingRequest() {
        let context = Context(); context.engine.payments.payment = .fail(.generic)
        var second: Subscriber<PaymentResult, PaymentError>?, disposed = false
        var statuses: [StarPurchaseCompletionStatus] = []
        let modal = make(context) { status in
            statuses.append(status)
            if status == .failed {
                context.engine.payments.payment = Signal { second = $0; return ActionDisposable { disposed = true } }
                UI.arguments?.buy()
            }
        }
        UI.arguments?.buy()
        XCTAssertEqual(context.engine.payments.requests.count, 2); XCTAssertFalse(disposed)
        second?.putNext(.done(nil, 8, nil)); second = nil
        XCTAssertEqual(statuses, [.failed, .paid(messageId: nil, peerId: 8)]); XCTAssertTrue(disposed)
        withExtendedLifetime(modal) {}
    }
    func testAllPaymentErrorsKeepPrivateFeedbackAndPermitExplicitRetry() {
        let context = Context()
        let errors: [PaymentError] = [.alreadyPaid, .generic, .paymentFailed, .precheckoutFailed, .starGiftOutOfStock, .disallowedStarGift, .starGiftUserLimit, .serverProvided("synthetic server error")]
        var statuses: [StarPurchaseCompletionStatus] = []
        let modal = make(context) { status in XCTAssertGreaterThan(UI.exclusions, 0); statuses.append(status) }
        UI.onText = { XCTAssertGreaterThan(UI.exclusions, 0) }
        for error in errors { context.engine.payments.payment = .fail(error); UI.arguments?.buy() }
        XCTAssertEqual(statuses, Array(repeating: .failed, count: errors.count))
        XCTAssertEqual(UI.texts, ["already", "unknown", "failed", "precheckout", "sold", "disallowed", "limit", "synthetic server error"])
        XCTAssertEqual(context.engine.payments.requests.count, errors.count)
        modal.close()
    }
    func testOwnerReleaseCancelsOnceEvenWhenBuyClosureSurvives() {
        let context = Context(); var disposed = false
        context.engine.payments.payment = Signal { _ in ActionDisposable { disposed = true; XCTAssertGreaterThan(UI.exclusions, 0) } }
        var statuses: [StarPurchaseCompletionStatus] = []
        var modal: InputDataModalController? = make(context) { statuses.append($0) }
        weak var weakModal = modal
        let buy = UI.arguments?.buy
        buy?(); modal = nil
        XCTAssertNil(weakModal); XCTAssertTrue(disposed); XCTAssertEqual(statuses, [.cancelled])
        buy?(); XCTAssertEqual(context.engine.payments.requests.count, 1)
    }
}

typealias ModalViewController = ViewController
struct TopUpOption { var count: Int64 = 10; var currency = "USD"; var amount: Int64 = 1 }
struct StoreProduct { var priceCurrencyAndAmount: (currency: String, amount: Int64) { ("USD", 1) } }
extension State { struct Option { var amount: Int64 = 10; var native = TopUpOption(); var storeProduct: StoreProduct? = StoreProduct() } }
enum AppStoreTransactionPurpose { case starsGift(peerId: PeerId, count: Int64, currency: String, amount: Int64), stars(count: Int64, currency: String, amount: Int64, peerId: PeerId?) }
enum StoreError: Error { case generic, network, notAllowed, cantMakePayments, assignFailed, cancelled }
enum StoreResult { case purchased(transactionId: String) }
final class StoreManager {
    var purchase: Signal<StoreResult, StoreError> = .complete()
    var requests = 0, finishes = 0
    func buyProduct(_ product: StoreProduct, purpose: AppStoreTransactionPurpose) -> Signal<StoreResult, StoreError> { requests += 1; UI.onStore?(); return purchase }
    func finishAllTransactions() { finishes += 1 }
}
final class PremiumLockModalController: ViewController { var closes = 0; func close() { closes += 1 } }
func delay(_ seconds: Double, closure: @escaping () -> Void) { UI.delayed.append(closure) }
func showModal(with controller: ViewController, for window: Window) { UI.storeWindows.append(controller) }
extension Int64 { var formattedWithSeparator: String { String(self) } }
enum AnalyticsEvents {
    struct StarsPurchaseSuccessStars { init(bucketing: Int) {} }
    static func starsPurchaseSuccess(stars: StarsPurchaseSuccessStars) -> Int { 1 }
}
enum CheckoutResult { case paid, cancelled, failed }
struct FeatureNavigationHooks {
    static let shared = FeatureNavigationHooks()
    func makePaymentsCheckoutObserved(_ context: any AccountContextProtocol, _ source: BotPaymentInvoiceSource, _ invoice: TelegramMediaInvoice, analyticsContext: AnalyticsContext, completion: @escaping (CheckoutResult) -> Void) -> ModalViewController? {
        UI.onCheckout?(); UI.checkoutCompletion = completion
        guard UI.checkoutAvailable else { return nil }
        let result = InputDataModalController(InputDataController(dataSignal: .complete(), title: ""), modalInteractions: nil)
        UI.checkout = result
        return result
    }
}
func topUpActions(_ context: Context, screen: StarsScreenContext, disabled: Bool = false) -> (store: (State.Option) -> Void, invoice: (State.Option) -> Void) {
    let window = context.window
    let actionsDisposable = screen.disposables
    let paymentDisposable = MetaDisposable()
    actionsDisposable.add(paymentDisposable)
    let inAppPurchaseManager = context.inAppPurchaseManager
    let source = Star_ListScreenSource.account
    let commercialPeerId: PeerId? = nil
    let invoiceTopupDisabled = disabled
    let close: (() -> Void)? = { screen.close() }
__INVOICE_TOPUP__
__STORE_TOPUP__
    return (buyAppStore, buyNonStore)
}
extension PurchaseTests {
    func testScreenSourcesExcludeSecretAndRetainOrdinaryGrant() {
        let origin = AnalyticsContext()
        for source in [Star_ListScreenSource.gift(.init(id: -5)), .purchase(.init(id: -5), 1), .purchaseSubscribe(.init(id: -5), 1), .prolongSubscription(.init(id: -5), 1), .reactions(.init(id: -5), 1)] {
            let screen = StarsScreenContext(context: Context(), source: source, analyticsContext: origin)
            XCTAssertTrue(screen.analytics.isExcluded); screen.close()
        }
        let ordinary = StarsScreenContext(context: Context(), source: .account, analyticsContext: origin)
        XCTAssertTrue(ordinary.analytics.scope === origin.scope)
        let legacy = StarsScreenContext(context: Context(), source: .account, analyticsContext: nil)
        XCTAssertTrue(legacy.analytics.isExcluded)
        let foreign = StarsScreenContext(context: Context(2), source: .account, analyticsContext: origin)
        XCTAssertNil(foreign.analytics.scope)
        ordinary.close(); legacy.close(); foreign.close()
    }
    func testScreenActionsReenterRevokedContextAndIgnoreRetainedActionsAfterClose() {
        let origin = AnalyticsContext(); let screen = StarsScreenContext(context: Context(), source: .account, analyticsContext: origin)
        var calls = 0
        let action = screen.action { (value: Int) in calls += value; XCTAssertGreaterThan(UI.exclusions, 0) }
        origin.scope?.valid = false; action(1); screen.close(); action(2)
        XCTAssertEqual(calls, 1)
    }
    func testScreenSignalOwnsSubscriptionDeliveryDisposalAndBlocksPostCloseSubscription() {
        let screen = StarsScreenContext(context: Context(), source: .account, analyticsContext: nil)
        var subscriber: Subscriber<Int, NoError>?, calls = 0, starts = 0, disposals = 0
        let signal = Signal<Int, NoError> { subscriber = $0; starts += 1; XCTAssertGreaterThan(UI.exclusions, 0); return ActionDisposable { disposals += 1; XCTAssertGreaterThan(UI.exclusions, 0) } }
        screen.disposables.add(screen.preserving(signal).start(next: { calls += $0; XCTAssertGreaterThan(UI.exclusions, 0) }))
        subscriber?.putNext(1); screen.close(); subscriber?.putNext(2); subscriber = nil
        _ = screen.preserving(signal).start(next: { _ in XCTFail() })
        XCTAssertEqual(calls, 1); XCTAssertEqual(starts, 1); XCTAssertEqual(disposals, 1)
    }
    func testScreenChildRetainsPrivateLeaseAfterParentCloseAndChainsCleanup() {
        let screen = StarsScreenContext(context: Context(), source: .account, analyticsContext: nil)
        var child: ModalViewController?, cleaned = false
        screen.showChild({
            XCTAssertGreaterThan(UI.exclusions, 0)
            let child = InputDataModalController(InputDataController(dataSignal: .complete(), title: ""), modalInteractions: nil)
            child.onDeinit = { cleaned = true; XCTAssertGreaterThan(UI.exclusions, 0) }
            return child
        }, show: { child = $0 })
        XCTAssertTrue(child?.analyticsContext?.isExcluded == true)
        XCTAssertTrue((child as? InputDataModalController)?.current.analyticsContext === child?.analyticsContext)
        screen.close(); XCTAssertGreaterThan(UI.exclusions, 0); child = nil; XCTAssertTrue(cleaned)
        screen.showChild({ XCTFail(); return ViewController() }, show: { _ in XCTFail() })
    }
    func testScreenClosingDuringChildConstructionPreventsPresentation() {
        let screen = StarsScreenContext(context: Context(), source: .account, analyticsContext: nil)
        screen.showChild({ screen.close(); return ViewController() }, show: { _ in XCTFail() })
    }
    func testStoreTopUpDuplicateEligibilityAndBuyProduceOneTerminalResult() {
        let context = Context(); let screen = StarsScreenContext(context: context, source: .account, analyticsContext: AnalyticsContext())
        var eligibility: Subscriber<Bool, NoError>?, purchase: Subscriber<StoreResult, StoreError>?
        context.engine.payments.eligibility = Signal { eligibility = $0; return EmptyDisposable }
        context.inAppPurchaseManager.purchase = Signal { purchase = $0; return EmptyDisposable }
        let actions = topUpActions(context, screen: screen)
        actions.store(.init()); actions.store(.init()); actions.invoice(.init())
        XCTAssertEqual(context.engine.payments.eligibilityCalls, 1)
        eligibility?.putNext(true); eligibility?.putNext(true); eligibility = nil
        XCTAssertEqual(context.inAppPurchaseManager.requests, 1)
        purchase?.putNext(.purchased(transactionId: "synthetic")); purchase?.putNext(.purchased(transactionId: "duplicate")); purchase = nil
        XCTAssertEqual(UI.successEvents, 1); XCTAssertEqual(context.inAppPurchaseManager.finishes, 1)
        UI.delayed.forEach { $0() }; XCTAssertTrue(UI.storeWindows.isEmpty)
    }
    func testStoreErrorBeforeDelayedLockDoesNotReopenLockAndAllowsRetry() {
        let context = Context(); let screen = StarsScreenContext(context: context, source: .account, analyticsContext: nil)
        context.inAppPurchaseManager.purchase = .fail(.network)
        let actions = topUpActions(context, screen: screen)
        actions.store(.init()); UI.delayed.forEach { $0() }; UI.delayed = []
        XCTAssertTrue(UI.storeWindows.isEmpty); XCTAssertEqual(UI.texts, ["network"]); XCTAssertEqual(UI.successEvents, 0)
        context.inAppPurchaseManager.purchase = .complete(); actions.store(.init())
        XCTAssertEqual(context.inAppPurchaseManager.requests, 2)
        UI.delayed.forEach { $0() }; XCTAssertTrue(UI.storeWindows.isEmpty); screen.close()
    }
    func testStoreEmptyOrDeniedEligibilityReleasesAttemptWithoutSuccess() {
        for result: Signal<Bool, NoError> in [.complete(), .single(false)] {
            let context = Context(); let screen = StarsScreenContext(context: context, source: .account, analyticsContext: nil)
            context.engine.payments.eligibility = result
            let actions = topUpActions(context, screen: screen)
            actions.store(.init()); actions.store(.init()); UI.delayed.forEach { $0() }
            XCTAssertEqual(context.engine.payments.eligibilityCalls, 2); XCTAssertEqual(context.inAppPurchaseManager.requests, 0)
            XCTAssertTrue(UI.storeWindows.isEmpty); XCTAssertEqual(UI.successEvents, 0); screen.close(); UI.reset()
        }
    }
    func testStoreCloseDuringEligibilityOrPurchaseSetupPreventsChargeSubscription() {
        let context = Context(); let screen = StarsScreenContext(context: context, source: .account, analyticsContext: nil)
        var subscribed = false
        context.inAppPurchaseManager.purchase = Signal { _ in subscribed = true; return EmptyDisposable }
        UI.onStore = { screen.close() }
        topUpActions(context, screen: screen).store(.init())
        UI.delayed.forEach { $0() }
        XCTAssertFalse(subscribed); XCTAssertTrue(UI.storeWindows.isEmpty); XCTAssertEqual(UI.successEvents, 0)
    }
    func testInvoiceTopUpBindsChildAndRejectsDuplicateCompletionAfterClose() {
        let context = Context(); let screen = StarsScreenContext(context: context, source: .account, analyticsContext: AnalyticsContext())
        let actions = topUpActions(context, screen: screen)
        actions.invoice(.init()); let child = UI.checkout
        XCTAssertTrue(child?.analyticsContext?.scope === screen.analytics.scope)
        actions.invoice(.init()); XCTAssertTrue(UI.checkout === child)
        UI.checkoutCompletion?(.paid); UI.checkoutCompletion?(.paid)
        XCTAssertEqual(UI.successEvents, 1); XCTAssertFalse(screen.isOpen)
    }
    func testInvoiceChildKeepsPrivacyAfterParentCloseWithoutPublishingLateOutcome() {
        let context = Context(); let screen = StarsScreenContext(context: context, source: .account, analyticsContext: nil)
        topUpActions(context, screen: screen).invoice(.init())
        XCTAssertTrue(UI.checkout?.analyticsContext?.isExcluded == true)
        screen.close(); XCTAssertGreaterThan(UI.exclusions, 0)
        UI.checkoutCompletion?(.paid); XCTAssertEqual(UI.successEvents, 0); XCTAssertTrue(UI.texts.isEmpty)
    }
    func testInvoiceEmptyErrorOrMissingCheckoutPermitRetryAndNeverClaimSuccess() {
        for mode in 0..<3 {
            let context = Context(); let screen = StarsScreenContext(context: context, source: .account, analyticsContext: nil)
            if mode == 0 { context.engine.payments.invoice = .complete() }
            if mode == 1 { context.engine.payments.invoice = .fail(.generic) }
            if mode == 2 { UI.checkoutAvailable = false }
            var requests = 0; UI.onInvoice = { requests += 1 }
            let actions = topUpActions(context, screen: screen); actions.invoice(.init()); actions.invoice(.init())
            XCTAssertEqual(requests, 2); XCTAssertEqual(UI.successEvents, 0); screen.close(); UI.reset()
        }
    }
}
