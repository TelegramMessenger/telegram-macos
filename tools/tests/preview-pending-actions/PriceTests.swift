struct PricePreviewState {
    var payAmount: Int64?
    var isSpoiler = true
    func withUpdatedPayAmount(_ amount: Int64?) -> Self { var copy = self; copy.payAmount = amount; return copy }
    func withUpdatedIsSpoiler(_ value: Bool) -> Self { var copy = self; copy.isSpoiler = value; return copy }
}
final class PriceSendButton { var shakes = 0; func shake(beep: Bool) { shakes += 1 } }
final class PricePreviewView {
    let sendButton = PriceSendButton()
    var state = PricePreviewState()
    var writes = 0
    var stateValueInteractiveUpdate: ((PricePreviewState) -> Void)?
    init() {
        stateValueInteractiveUpdate = { [weak self] state in self?.state = state; self?.writes += 1 }
    }
}
enum PriceValidation {
    enum Failure { case none, fields([String: Action]) }
    enum Action { case shake }
    enum Success { case custom(() -> Void) }
    case fail(Failure), success(Success)
    func finish() { if case let .success(.custom(action)) = self { action() } }
    var succeeded: Bool { if case .success = self { return true }; return false }
}
struct PriceFormState { struct Input { var string = "" }; var inputState = Input() }
final class PriceFormValue {
    var value = PriceFormState()
    func with<T>(_ f: (PriceFormState) -> T) -> T { f(value) }
}
struct ModalHeaderData { let image: Int; let handler: () -> Void }
struct PriceTheme { struct Icons { let modalClose = 0 }; let icons = Icons() }
let theme = PriceTheme()
let _id_input = "input"
final class PriceInput {
    var analyticsContext: Context?
    var validateData: (Int) -> PriceValidation = { _ in .fail(.none) }
    var afterDisappear: () -> Void = {}
    var leftModalHeader: ModalHeaderData?
}
final class PriceModal {
    let current = PriceInput()
    let form = PriceFormValue()
    var analyticsContext: Context?
    var onDeinit: (() -> Void)?
    var priorDeinitCalls = 0
    var closes = 0
    let deliver: (Int64) -> Void
    let cancelled: (() -> Void)?
    init(deliver: @escaping (Int64) -> Void, cancelled: (() -> Void)?) { self.deliver = deliver; self.cancelled = cancelled }
    func close() { closes += 1; current.afterDisappear() }
    func enter(_ text: String) -> PriceValidation { form.value.inputState.string = text; return current.validateData(0) }
    deinit { onDeinit?() }
}
final class PriceUI { static var modals: [PriceModal] = [] }
func showModal(with controller: PriceModal, for window: Window) { PriceUI.modals.append(controller) }
func MediaPaidSetterController(context: Context, callback: @escaping (Int64) -> Void, cancelled: (() -> Void)? = nil, dismissed: (() -> Void)? = nil) -> PriceModal {
    context.onPriceConstruction?()
    let modalController = PriceModal(deliver: callback, cancelled: cancelled)
    let controller = modalController.current
    let stateValue = modalController.form
    let limit: Int64 = 10000
    var resolved = false
    let close: (() -> Void)? = { [weak modalController] in modalController?.close() }
__PRICE_VALIDATION__
__PRICE_CANCEL__
    modalController.onDeinit = { [weak modalController] in modalController?.priorDeinitCalls += 1 }
    return modalController
}

final class PriceTests: XCTestCase {
    private func drain() {
        let done = expectation(description: "dismissed")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 2)
    }
    override func setUp() { PriceUI.modals = [] }
    override func tearDown() { PriceUI.modals = []; drain() }
    func testConstructionBindingApplyAndRemovalStayInOriginalContext() {
        let owner = Controller()
        let origin = owner.analyticsContext!
        owner.context.onPriceConstruction = { XCTAssertEqual(origin.depth, 1) }
        owner.togglePaidContent()
        let modal = PriceUI.modals[0]
        XCTAssertTrue(modal.analyticsContext === origin)
        XCTAssertTrue(modal.current.analyticsContext === origin)
        XCTAssertEqual(owner.analyticsMediaJourney?.steps, [.openPrice])
        let update = owner.genericView.stateValueInteractiveUpdate
        owner.genericView.stateValueInteractiveUpdate = { state in
            XCTAssertEqual(origin.depth, 2)
            update?(state)
            modal.deliver(999)
        }
        modal.enter("25").finish()
        modal.deliver(100)
        XCTAssertEqual(owner.genericView.state.payAmount, 25)
        XCTAssertFalse(owner.genericView.state.isSpoiler)
        XCTAssertEqual(owner.genericView.writes, 1)
        XCTAssertEqual(owner.analyticsMediaJourney?.steps, [.openPrice, .applyPrice])
        drain()
        XCTAssertEqual(origin.depth, 0)
        owner.genericView.stateValueInteractiveUpdate = update
        owner.togglePaidContent()
        XCTAssertNil(owner.genericView.state.payAmount)
        XCTAssertEqual(owner.analyticsMediaJourney?.steps, [.openPrice, .applyPrice, .removePrice])
    }
    func testExplicitCancelWinsOnceAndKeepsParentJourney() {
        let owner = Controller()
        owner.togglePaidContent()
        let modal = PriceUI.modals[0]
        modal.current.leftModalHeader?.handler()
        modal.current.leftModalHeader?.handler()
        modal.deliver(20)
        modal.cancelled?()
        XCTAssertEqual(modal.closes, 1)
        XCTAssertNil(owner.genericView.state.payAmount)
        XCTAssertEqual(owner.analyticsMediaJourney?.steps, [.openPrice, .cancelPrice])
        XCTAssertEqual(owner.analyticsMediaJourney?.cancelled, 0)
        drain()
        XCTAssertEqual(owner.analyticsContext?.depth, 0)
    }
    func testUnknownDisappearanceDoesNotInventCancelAndBlocksValidation() {
        let owner = Controller()
        owner.togglePaidContent()
        let modal = PriceUI.modals[0]
        modal.close()
        XCTAssertFalse(modal.enter("20").succeeded)
        drain()
        modal.deliver(30)
        modal.cancelled?()
        XCTAssertEqual(owner.analyticsMediaJourney?.steps, [.openPrice])
        XCTAssertNil(owner.genericView.state.payAmount)
    }
    func testChangedChatPreviewClosedAndCommittedOwnersRejectLateApply() {
        for change in 0..<4 {
            let owner = Controller()
            owner.togglePaidContent()
            let modal = PriceUI.modals.last!
            switch change {
            case 0: owner.chatInteraction.revision += 1
            case 1: owner.pendingActions.invalidate()
            case 2: owner.pendingActions.close()
            default: owner.sent = true
            }
            modal.deliver(25)
            modal.cancelled?()
            XCTAssertNil(owner.genericView.state.payAmount)
            XCTAssertEqual(owner.analyticsMediaJourney?.steps, [.openPrice])
        }
    }
    func testNewDialogAndPriceRemovalSupersedeOldResult() {
        let owner = Controller()
        owner.togglePaidContent()
        let old = PriceUI.modals[0]
        owner.togglePaidContent()
        let current = PriceUI.modals[1]
        old.deliver(10)
        XCTAssertNil(owner.genericView.state.payAmount)
        owner.genericView.state.payAmount = 40
        owner.togglePaidContent()
        current.deliver(50)
        XCTAssertNil(owner.genericView.state.payAmount)
        XCTAssertEqual(owner.analyticsMediaJourney?.steps, [.openPrice, .openPrice, .removePrice])
    }
    func testMissingStateUpdateDoesNotInventAppliedOrRemovedPrice() {
        let owner = Controller()
        owner.genericView.stateValueInteractiveUpdate = nil
        owner.togglePaidContent()
        PriceUI.modals[0].deliver(20)
        XCTAssertNil(owner.genericView.state.payAmount)
        owner.genericView.state.payAmount = 30
        owner.togglePaidContent()
        XCTAssertEqual(owner.genericView.state.payAmount, 30)
        XCTAssertEqual(owner.analyticsMediaJourney?.steps, [.openPrice])
    }
    func testInvalidAmountsCanBeCorrectedAndSuccessfulValidationIsConsumed() {
        let owner = Controller()
        owner.togglePaidContent()
        let modal = PriceUI.modals[0]
        for value in ["", "abc", "0", "-1", "10001", "9223372036854775808"] {
            XCTAssertFalse(modal.enter(value).succeeded)
        }
        XCTAssertEqual(owner.genericView.writes, 0)
        XCTAssertTrue(modal.enter("10000").succeeded)
        XCTAssertFalse(modal.enter("5").succeeded)
        modal.current.leftModalHeader?.handler()
        XCTAssertEqual(owner.genericView.state.payAmount, 10000)
        XCTAssertEqual(owner.analyticsMediaJourney?.steps, [.openPrice, .applyPrice])
    }
    func testDestroyedOwnerIsNotRetainedAndDeniedObservationDoesNotDisablePricing() {
        var owner: Controller? = Controller()
        weak var weakOwner = owner
        owner!.togglePaidContent()
        let modal = PriceUI.modals[0]
        owner = nil
        XCTAssertNil(weakOwner)
        modal.deliver(20)
        modal.cancelled?()
        let other = Controller()
        other.analyticsMediaJourney = nil
        other.togglePaidContent()
        PriceUI.modals[1].enter("20").finish()
        XCTAssertEqual(other.genericView.state.payAmount, 20)
    }
    func testClosedOrCommittedPreviewDoesNotOpenOrRemovePrice() {
        for sent in [false, true] {
            let owner = Controller()
            if sent { owner.sent = true } else { owner.pendingActions.close() }
            owner.togglePaidContent()
            owner.genericView.state.payAmount = 20
            owner.togglePaidContent()
            XCTAssertEqual(owner.genericView.state.payAmount, 20)
            XCTAssertTrue(owner.analyticsMediaJourney!.steps.isEmpty)
        }
        XCTAssertTrue(PriceUI.modals.isEmpty)
    }
}
