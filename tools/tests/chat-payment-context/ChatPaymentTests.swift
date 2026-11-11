import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int64
let XTR = "XTR"
struct MessageId: Equatable { let peerId: PeerId; var id = 1 }
final class Scope { var valid = true }
final class AnalyticsContext {
    let owner: Int, isExcluded: Bool, scope: Scope?
    init(_ owner: Int = 1, excluded: Bool = false, scope: Scope? = Scope()) { self.owner = owner; isExcluded = excluded; self.scope = excluded ? nil : scope }
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
    func unresolvedContext() -> AnalyticsContext { AnalyticsContext(excluded: true) }
    func captureContext(engine: Engine, peerId: PeerId, inherited: AnalyticsContext) -> AnalyticsContext {
        AnalyticsContext(engine.owner, excluded: inherited.isExcluded || peerId < 0, scope: inherited.owner == engine.owner ? inherited.scope : nil)
    }
}
protocol AccountContextProtocol: AnyObject { var engine: Engine { get }; var peerId: PeerId { get }; var window: Window { get }; var account: Account { get } }
final class Context: AccountContextProtocol {
    let engine: Engine
    let peerId: PeerId = 1
    let window = Window(), account = Account()
    init(_ owner: Int = 1) { engine = Engine(owner) }
}
final class Window {}
final class Account { let postbox = Postbox() }
final class Engine { let owner: Int; let payments = Payments(); init(_ owner: Int) { self.owner = owner } }
struct Peer: Equatable { let id: PeerId }
struct PeerEquatable: Equatable { let peer: Peer; init(_ peer: Peer) { self.peer = peer } }
struct BotPaymentReceipt: Equatable { let botPaymentId: PeerId }
enum PaymentError: Error { case generic }
struct TelegramMediaInvoice: Equatable { var currency = XTR; var receiptMessageId: MessageId? }
enum BotPaymentInvoiceSource { case message(MessageId) }
final class Payments {
    var invoice: Signal<TelegramMediaInvoice, PaymentError> = .single(TelegramMediaInvoice())
    var receipt: Signal<BotPaymentReceipt, PaymentError> = .complete()
    var invoices: [MessageId] = [], receipts: [MessageId] = []
    func fetchBotPaymentInvoice(source: BotPaymentInvoiceSource) -> Signal<TelegramMediaInvoice, PaymentError> { if case let .message(id) = source { invoices.append(id) }; UI.onInvoice?(); return invoice }
    func requestBotPaymentReceipt(messageId: MessageId) -> Signal<BotPaymentReceipt, PaymentError> { receipts.append(messageId); UI.onReceipt?(); return receipt }
}
final class Transaction {
    func getPeer(_ id: PeerId) -> Peer? { UI.peerIds.append(id); UI.onPeer?(); return Peer(id: id) }
}
final class Postbox {
    var result: Signal<Peer?, NoError>?
    func transaction(_ callback: (Transaction) -> Peer?) -> Signal<Peer?, NoError> { let value = callback(Transaction()); return result ?? .single(value) }
}
__STATE__
func entries(_ state: State, arguments: Arguments) -> [Int] { UI.receiptState = state; UI.onEntries?(); return [] }
struct InputDataSignalValue { let entries: [Int] }
func deliverOnPrepareQueue<T, E>(_ signal: Signal<T, E>) -> Signal<T, E> { signal }
enum Screen { case paymentsReceipt }
enum Validation { case none }
struct ModalHeaderData { let image: Int; let handler: () -> Void }
struct ModalInteractions { let acceptTitle: String; let accept: () -> Void; let singleButton: Bool }
let theme = Theme()
struct Theme { let icons = Icons() }
struct Icons { let modalClose = 0 }
class ViewController {
    var analyticsContext: AnalyticsContext?, onDeinit: (() -> Void)?
    deinit { onDeinit?() }
}
final class InputDataController: ViewController {
    var analyticsScreen: Screen?
    var validateData: ((Int) -> Validation)?
    var leftModalHeader: ModalHeaderData?
    let subscription: Disposable
    init(dataSignal: Signal<InputDataSignalValue, NoError>, title: String) { subscription = dataSignal.start(next: { _ in }); super.init() }
    func returnKeyAction() -> Validation { validateData?(0) ?? .none }
    deinit { subscription.dispose() }
}
final class NativeModal { func close() {} }
final class InputDataModalController: ViewController {
    let current: InputDataController
    let closeHandler: (@escaping () -> Void) -> Void
    let modal: NativeModal? = NativeModal()
    init(_ current: InputDataController, modalInteractions: ModalInteractions?, closeHandler: @escaping (@escaping () -> Void) -> Void = { $0() }) { self.current = current; self.closeHandler = closeHandler; super.init() }
    func close() { closeHandler { self.modal?.close() } }
}
final class TelegramMediaImage {}
final class TelegramMediaFile {}
enum StarPurchaseType {
    struct PaidMediaCount { let photoCount: Int; let videoCount: Int }
    case bot, paidMedia(TelegramMediaImage, PaidMediaCount)
}
func Star_PurschaseInApp(context: any AccountContextProtocol, invoice: TelegramMediaInvoice?, source: BotPaymentInvoiceSource, type: StarPurchaseType = .bot, analyticsContext: AnalyticsContext?) -> InputDataModalController {
    UI.starContexts.append(analyticsContext); UI.starSources.append(source); UI.starTypes.append(type); UI.onStar?()
    let controller = InputDataModalController(InputDataController(dataSignal: .complete(), title: ""), modalInteractions: nil)
    controller.analyticsContext = analyticsContext; controller.current.analyticsContext = analyticsContext
    controller.onDeinit = { UI.onStarDeinit?() }
    return controller
}
func PaymentsCheckoutController(context: any AccountContextProtocol, source: BotPaymentInvoiceSource, invoice: TelegramMediaInvoice, analyticsContext: AnalyticsContext? = nil) -> InputDataModalController {
    UI.checkoutContexts.append(analyticsContext); UI.onCheckout?()
    return InputDataModalController(InputDataController(dataSignal: .complete(), title: ""), modalInteractions: nil)
}
func showModal(with controller: InputDataModalController, for window: Window) { UI.shown.append(controller); UI.onShow?() }
func showModalProgress<T, E>(signal: Signal<T, E>, for window: Window) -> Signal<T, E> { UI.onProgress?(); return signal }
func showModalText(for window: Window, text: String) { UI.texts.append(text); UI.onText?() }
struct Strings { let paymentsInvoiceNotExists = "missing", checkoutReceiptTitle = "receipt", modalDone = "done" }
func strings() -> Strings { Strings() }
struct ChatNavigationHooks {
    static var shared = ChatNavigationHooks()
__HOOKS__
}
func installHooks() {
    var hooks = ChatNavigationHooks()
__INSTALL__
    ChatNavigationHooks.shared = hooks
}
__ACTION__
__RECEIPT__
final class Interaction {
    var origin: AnalyticsContext
    var captures: [PeerId?] = []
    init(_ origin: AnalyticsContext) { self.origin = origin }
    func captureAnalyticsContext(sourcePeerId: PeerId? = nil) -> AnalyticsContext { captures.append(sourcePeerId); return sourcePeerId.map { origin.restricting(peerId: $0) } ?? origin }
}
struct Message { let id: MessageId; var anyMedia: Any? }
final class PaidRow {
    let payment = ChatPaidMediaPurchase()
    var message: Message?
    let context: Context
    let chatInteraction: Interaction
    enum Extended { case full(Any), preview(Int?, Int?, Int?) }
    struct Media { var extendedMedia: [Extended] = [.full(TelegramMediaFile()), .preview(nil, nil, nil)] }
    struct Data { var items = [1, 2] }
    var media = Media(), data = Data()
    init(_ context: Context, origin: AnalyticsContext, peer: PeerId = 5) { self.context = context; chatInteraction = Interaction(origin); message = Message(id: MessageId(peerId: peer)) }
__ROW__
}
func pressPayment(_ strongSelf: Interaction, keyboardMessage: Message, context: Context) {
__KEYBOARD__
}
enum UI {
    static var exclusions = 0
    static var onInvoice: (() -> Void)?, onReceipt: (() -> Void)?, onPeer: (() -> Void)?, onEntries: (() -> Void)?, onStar: (() -> Void)?, onStarDeinit: (() -> Void)?, onCheckout: (() -> Void)?, onShow: (() -> Void)?, onProgress: (() -> Void)?, onText: (() -> Void)?
    static var shown: [InputDataModalController] = []
    static var starContexts: [AnalyticsContext?] = [], checkoutContexts: [AnalyticsContext?] = []
    static var starSources: [BotPaymentInvoiceSource] = [], starTypes: [StarPurchaseType] = []
    static var texts: [String] = [], peerIds: [PeerId] = []
    static var receiptState: State?
    static func reset() {
        shown = []; starContexts = []; checkoutContexts = []; starSources = []; starTypes = []; texts = []; peerIds = []; receiptState = nil
        onInvoice = nil; onReceipt = nil; onPeer = nil; onEntries = nil; onStar = nil; onStarDeinit = nil; onCheckout = nil; onShow = nil; onProgress = nil; onText = nil
        ChatNavigationHooks.shared = ChatNavigationHooks()
    }
}
final class ChatPaymentTests: XCTestCase {
    override func setUp() { UI.reset(); installHooks(); XCTAssertEqual(UI.exclusions, 0) }
    override func tearDown() { UI.reset(); XCTAssertEqual(UI.exclusions, 0) }
    func testPaidMediaCapturesOriginalOriginBeforeMetadataAndKeepsItAcrossChatChange() {
        let context = Context(); let origin = AnalyticsContext(excluded: true)
        let row = PaidRow(context, origin: origin)
        var invoice: Subscriber<TelegramMediaInvoice, PaymentError>?, disposed = false
        context.engine.payments.invoice = Signal { invoice = $0; XCTAssertGreaterThan(UI.exclusions, 0); return ActionDisposable { disposed = true; XCTAssertGreaterThan(UI.exclusions, 0) } }
        UI.onInvoice = { XCTAssertGreaterThan(UI.exclusions, 0) }; UI.onProgress = UI.onInvoice; UI.onStar = UI.onInvoice
        row.buyProduct(image: TelegramMediaImage()); row.buyProduct(image: TelegramMediaImage())
        XCTAssertEqual(context.engine.payments.invoices.count, 1)
        row.chatInteraction.origin = AnalyticsContext(2)
        invoice?.putNext(TelegramMediaInvoice()); invoice?.putNext(TelegramMediaInvoice()); invoice = nil
        XCTAssertTrue(disposed); XCTAssertEqual(UI.shown.count, 1); XCTAssertTrue(UI.starContexts[0]?.isExcluded == true)
        guard case let .paidMedia(_, count) = UI.starTypes[0] else { return XCTFail() }
        XCTAssertEqual(count.photoCount, 1); XCTAssertEqual(count.videoCount, 1)
        row.buyProduct(image: TelegramMediaImage()); XCTAssertEqual(context.engine.payments.invoices.count, 1)
        withExtendedLifetime(row) {}
    }
    func testPaidMediaRowReleaseDisposesPendingMetadataAndIgnoresLateInvoice() {
        let context = Context(); var row: PaidRow? = PaidRow(context, origin: AnalyticsContext(excluded: true))
        var invoice: Subscriber<TelegramMediaInvoice, PaymentError>?, disposed = false
        context.engine.payments.invoice = Signal { invoice = $0; return ActionDisposable { disposed = true; XCTAssertGreaterThan(UI.exclusions, 0) } }
        row?.buyProduct(image: TelegramMediaImage()); row = nil
        XCTAssertTrue(disposed); invoice?.putNext(TelegramMediaInvoice()); invoice = nil
        XCTAssertTrue(UI.shown.isEmpty)
    }
    func testPaidMediaChildRetainsPrivacyAfterRowReleaseAndChainsDeinit() {
        let context = Context(); var row: PaidRow? = PaidRow(context, origin: AnalyticsContext(excluded: true))
        var cleaned = false; UI.onStarDeinit = { cleaned = true; XCTAssertGreaterThan(UI.exclusions, 0) }
        row?.buyProduct(image: TelegramMediaImage()); row = nil
        XCTAssertGreaterThan(UI.exclusions, 0); UI.shown = []; XCTAssertTrue(cleaned)
    }
    func testPaidMediaErrorEmptyAndChildDismissalPermitRetry() {
        let context = Context(); let row = PaidRow(context, origin: AnalyticsContext(excluded: true))
        UI.onText = { XCTAssertGreaterThan(UI.exclusions, 0) }
        context.engine.payments.invoice = .fail(.generic); row.buyProduct(image: TelegramMediaImage())
        context.engine.payments.invoice = .complete(); row.buyProduct(image: TelegramMediaImage())
        context.engine.payments.invoice = .single(TelegramMediaInvoice()); row.buyProduct(image: TelegramMediaImage())
        XCTAssertEqual(UI.shown.count, 1); UI.shown = []; row.buyProduct(image: TelegramMediaImage())
        XCTAssertEqual(context.engine.payments.invoices.count, 4); XCTAssertEqual(UI.texts, ["missing"])
    }
    func testPaidMediaSecretSourceForeignAccountAndRevokedDeliveryAreExcluded() {
        for mode in 0..<3 {
            let context = Context(); let origin = AnalyticsContext(mode == 1 ? 2 : 1)
            let row = PaidRow(context, origin: origin, peer: mode == 0 ? -5 : 5)
            var invoice: Subscriber<TelegramMediaInvoice, PaymentError>?
            context.engine.payments.invoice = Signal { invoice = $0; return EmptyDisposable }
            row.buyProduct(image: TelegramMediaImage())
            if mode == 2 { origin.scope?.valid = false }
            UI.onStar = { XCTAssertGreaterThan(UI.exclusions, 0) }
            invoice?.putNext(TelegramMediaInvoice()); invoice = nil
            XCTAssertEqual(UI.shown.count, 1); UI.reset(); installHooks(); withExtendedLifetime(row) {}
        }
    }
    func testPaidMediaMissingMessageDoesNotFetch() {
        let context = Context(); let row = PaidRow(context, origin: AnalyticsContext())
        row.message = nil; row.buyProduct(image: TelegramMediaImage())
        XCTAssertTrue(context.engine.payments.invoices.isEmpty)
    }
    func testKeyboardSelectsStarsCheckoutAndReceiptWithOriginalPrivateContext() {
        let context = Context(); let interaction = Interaction(AnalyticsContext(excluded: true))
        UI.onStar = { XCTAssertGreaterThan(UI.exclusions, 0) }; UI.onCheckout = UI.onStar; UI.onReceipt = UI.onStar
        pressPayment(interaction, keyboardMessage: Message(id: .init(peerId: 5), anyMedia: TelegramMediaInvoice()), context: context)
        pressPayment(interaction, keyboardMessage: Message(id: .init(peerId: 5), anyMedia: TelegramMediaInvoice(currency: "USD")), context: context)
        pressPayment(interaction, keyboardMessage: Message(id: .init(peerId: 5), anyMedia: TelegramMediaInvoice(receiptMessageId: .init(peerId: 6))), context: context)
        XCTAssertEqual(UI.starContexts.count, 1); XCTAssertTrue(UI.starContexts[0]?.isExcluded == true)
        XCTAssertEqual(UI.checkoutContexts.count, 1); XCTAssertTrue(UI.checkoutContexts[0]?.isExcluded == true)
        XCTAssertEqual(context.engine.payments.receipts, [.init(peerId: 6)])
        XCTAssertTrue(UI.shown.last?.analyticsContext?.isExcluded == true)
        XCTAssertEqual(interaction.captures, [5, 5, 5])
    }
    func testKeyboardOrdinaryGrantAndReceiptPeerRestriction() {
        let context = Context(); let origin = AnalyticsContext(); let interaction = Interaction(origin)
        pressPayment(interaction, keyboardMessage: Message(id: .init(peerId: 5), anyMedia: TelegramMediaInvoice(currency: "USD")), context: context)
        XCTAssertTrue(UI.checkoutContexts[0]?.scope === origin.scope)
        pressPayment(interaction, keyboardMessage: Message(id: .init(peerId: 5), anyMedia: TelegramMediaInvoice(receiptMessageId: .init(peerId: -6))), context: context)
        XCTAssertTrue(UI.shown.last?.analyticsContext?.isExcluded == true)
    }
    func testLegacyHookFallbackScopesConstructionAndRevalidatesAccount() {
        let context = Context(2)
        ChatNavigationHooks.shared = ChatNavigationHooks()
        var calls = 0
        ChatNavigationHooks.shared.showPaymentsReceipt = { _, _, _, _ in calls += 1; XCTAssertGreaterThan(UI.exclusions, 0) }
        ChatNavigationHooks.shared.showPaymentsCheckout = { _, _, _, _ in calls += 1; XCTAssertGreaterThan(UI.exclusions, 0) }
        openChatMessagePayment(context: context, messageId: .init(peerId: 5), invoice: .init(currency: "USD"), analyticsContext: AnalyticsContext())
        openChatMessagePayment(context: context, messageId: .init(peerId: 5), invoice: .init(receiptMessageId: .init(peerId: 6)), analyticsContext: AnalyticsContext())
        XCTAssertEqual(calls, 2)
    }
    func testReceiptLegacyEntryScopesNetworkPeerAndEntryDelivery() {
        let context = Context(); var receipt: Subscriber<BotPaymentReceipt, PaymentError>?
        context.engine.payments.receipt = Signal { receipt = $0; XCTAssertGreaterThan(UI.exclusions, 0); return EmptyDisposable }
        UI.onReceipt = { XCTAssertGreaterThan(UI.exclusions, 0) }; UI.onPeer = UI.onReceipt; UI.onEntries = UI.onReceipt
        let modal = PaymentsReceiptController(context: context, messageId: .init(peerId: 5), invoice: .init())
        XCTAssertTrue(modal.analyticsContext?.isExcluded == true); XCTAssertTrue(modal.current.analyticsContext === modal.analyticsContext)
        receipt?.putNext(.init(botPaymentId: 8)); receipt?.putNext(.init(botPaymentId: 9)); receipt = nil
        XCTAssertEqual(UI.peerIds, [8]); XCTAssertEqual(UI.receiptState?.receipt?.botPaymentId, 8)
    }
    func testReceiptCloseDisposesRequestAndLateResultCannotLoadPeer() {
        let context = Context(); var receipt: Subscriber<BotPaymentReceipt, PaymentError>?, disposed = false
        context.engine.payments.receipt = Signal { receipt = $0; return ActionDisposable { disposed = true; XCTAssertGreaterThan(UI.exclusions, 0) } }
        let modal = PaymentsReceiptController(context: context, messageId: .init(peerId: 5), invoice: .init())
        modal.close(); XCTAssertTrue(disposed)
        receipt?.putNext(.init(botPaymentId: 8)); receipt = nil; XCTAssertTrue(UI.peerIds.isEmpty)
    }
    func testReceiptCloseDuringPeerLoadingDisposesAndSuppressesUpdate() {
        let context = Context(); context.engine.payments.receipt = .single(.init(botPaymentId: 8))
        var peer: Subscriber<Peer?, NoError>?, disposed = false
        context.account.postbox.result = Signal { peer = $0; return ActionDisposable { disposed = true; XCTAssertGreaterThan(UI.exclusions, 0) } }
        let modal = PaymentsReceiptController(context: context, messageId: .init(peerId: 5), invoice: .init())
        _ = modal.current.returnKeyAction(); XCTAssertTrue(disposed)
        peer?.putNext(Peer(id: 8)); peer = nil; XCTAssertNil(UI.receiptState?.receipt)
    }
    func testReceiptErrorAndMissingPeerDoNotInventContent() {
        let context = Context(); context.engine.payments.receipt = .fail(.generic)
        var modal: InputDataModalController? = PaymentsReceiptController(context: context, messageId: .init(peerId: 5), invoice: .init())
        XCTAssertNil(UI.receiptState?.receipt); modal = nil
        context.engine.payments.receipt = .single(.init(botPaymentId: 8)); context.account.postbox.result = .single(nil)
        modal = PaymentsReceiptController(context: context, messageId: .init(peerId: 5), invoice: .init())
        XCTAssertEqual(UI.receiptState?.receipt?.botPaymentId, 8); XCTAssertNil(UI.receiptState?.botPeer); modal = nil
    }
}

extension ChatPaymentTests {
    func testPaidMediaOrdinaryGrantAndMessageSnapshotSurviveRowMutation() {
        let context = Context(); let origin = AnalyticsContext(); let row = PaidRow(context, origin: origin)
        var invoice: Subscriber<TelegramMediaInvoice, PaymentError>?
        context.engine.payments.invoice = Signal { invoice = $0; return EmptyDisposable }
        row.buyProduct(image: TelegramMediaImage())
        row.chatInteraction.origin = AnalyticsContext(2)
        row.message = Message(id: .init(peerId: 6)); row.data.items = []; row.media.extendedMedia = []
        invoice?.putNext(TelegramMediaInvoice()); invoice = nil
        XCTAssertTrue(UI.starContexts[0]?.scope === origin.scope)
        guard case let .message(id) = UI.starSources[0], case let .paidMedia(_, count) = UI.starTypes[0] else { return XCTFail() }
        XCTAssertEqual(id.peerId, 5); XCTAssertEqual(count.photoCount, 1); XCTAssertEqual(count.videoCount, 1)
        XCTAssertEqual(UI.exclusions, 0)
    }
    func testReceiptRetainsOrdinaryGrantAndReentersRevokedContextForLateDelivery() {
        let context = Context(); let origin = AnalyticsContext()
        var receipt: Subscriber<BotPaymentReceipt, PaymentError>?
        context.engine.payments.receipt = Signal { receipt = $0; return EmptyDisposable }
        let modal = PaymentsReceiptController(context: context, messageId: .init(peerId: 5), invoice: .init(), analyticsContext: origin)
        XCTAssertTrue(modal.analyticsContext?.scope === origin.scope)
        origin.scope?.valid = false
        UI.onPeer = { XCTAssertGreaterThan(UI.exclusions, 0) }; UI.onEntries = UI.onPeer
        receipt?.putNext(.init(botPaymentId: 8)); receipt = nil
        XCTAssertEqual(UI.receiptState?.receipt?.botPaymentId, 8)
        modal.close()
    }
    func testReceiptOwnerReleaseDisposesBeforeLateResponse() {
        let context = Context(); var receipt: Subscriber<BotPaymentReceipt, PaymentError>?, disposed = false
        context.engine.payments.receipt = Signal { receipt = $0; return ActionDisposable { disposed = true } }
        var modal: InputDataModalController? = PaymentsReceiptController(context: context, messageId: .init(peerId: 5), invoice: .init())
        weak var weakModal = modal; modal = nil
        XCTAssertNil(weakModal); XCTAssertTrue(disposed)
        receipt?.putNext(.init(botPaymentId: 8)); receipt = nil; XCTAssertTrue(UI.peerIds.isEmpty)
    }
    func testKeyboardWithoutInvoiceDoesNotCaptureOrPresentPayment() {
        let context = Context(); let interaction = Interaction(AnalyticsContext())
        pressPayment(interaction, keyboardMessage: Message(id: .init(peerId: 5)), context: context)
        XCTAssertTrue(interaction.captures.isEmpty); XCTAssertTrue(UI.shown.isEmpty)
    }
}
