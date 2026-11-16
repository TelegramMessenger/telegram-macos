struct StoryStars: Equatable { let value: Int64 }
struct StoryBalance { let balance: StoryStars }
struct StorySlowMode { let timeout: Int }
struct StoryReplyId: Equatable { let peerId: PeerId; let id: Int32 }
struct StoryData { var paidMessage: StoryStars? }
struct StorySlice { var peer: Peer; var additionalPeerData = StoryData() }
struct StoryContextState { var slice: StorySlice? }
final class StoryContext { var stateValue: StoryContextState? }
enum StoryTooltip { case tooltip(String, Int); case media([Any]) }
enum MenuAnimation { static let menu_clear_history = 0 }
func slowModeTooltipText(_ timeout: Int) -> String { "slow" }
enum StoryRight { case banSendMedia, banSendFiles, banSendText }
func permissionText(from peer: Peer?, for right: StoryRight) -> String? { StoryPayments.restricted ? "restricted" : nil }
final class StoryView {
    let storyContext: StoryContext? = StoryContext()
    var resets = 0
    func resetInputView() { resets += 1 }
    func showTooltip(_ source: StoryViewController.TooptipView.Source) { tooltips += 1 }
    var tooltips = 0
    func showTooltip(_ value: StoryTooltip) { tooltips += 1 }
}
struct StoryArguments { let interaction: ChatInteraction }
final class StoryInteraction {
    struct State: Equatable {
        var entryId: PeerId?
        var storyId: Int32?
        var closed = false
        var mediaCall: StoryStreamCall?
        var lock = false
        var input = ChatTextInputState()
        var myStars: StoryStars?
        var messageStarPrice: Int64?
    }
    var inputClears = 0
    func updateInput(with text: String, resetFocus: Bool) { presentation.input = ChatTextInputState(inputText: text); inputClears += 1 }
    var presentation = State(entryId: PeerId(), storyId: 7)
    private var replyActionRevision = UUID()
__STORY_ACTION__
    func update(_ f: (State) -> State) {
__STORY_UPDATE__
    }
}
enum ConfirmResult { case basic, thrid }
enum StoryCurrency { case stars }
enum StoryPayments {
    static var restricted = false
    static var onAlert: (() -> Void)?
    static var success: ((ConfirmResult) -> Void)?
    static var cancel: (() -> Void)?
    static var destroyed: (() -> Void)?
    static var purchases: [(Int64?, AnalyticsContext)] = []
    static var onPurchase: ((AnalyticsContext) -> Void)?
    static var sends: [(PeerId, StoryReplyId?, Int64?)] = []
    static var result: Signal<[Int?], NoError> = .single([1])
    static var paidPreferences: [PeerId] = []
    static func reset() {
        restricted = false
        onAlert = nil; success = nil; cancel = nil; destroyed = nil
        purchases = []; onPurchase = nil; sends = []; result = .single([1]); paidPreferences = []
    }
}
func verifyAlert(for window: Window, header: String, information: String, ok: String, option: String, optionIsSelected: Bool, successHandler: @escaping (ConfirmResult) -> Void, cancelHandler: @escaping () -> Void, onDeinit: @escaping () -> Void) {
    StoryPayments.onAlert?()
    StoryPayments.success = successHandler
    StoryPayments.cancel = cancelHandler
    StoryPayments.destroyed = onDeinit
}
__PAYMENT__
struct StoryStrings {
    var chatPayStarsConfirmTitle: String { "Pay" }
    var chatPayStarsConfirmCheckbox: String { "Remember" }
    func starListItemCountOther(_ count: Int) -> String { "amount" }
    func chatPayStarsConfirmMessagesOther(_ count: Int) -> String { "messages" }
    func chatPayStarsConfirmText(_ peer: String, _ amount: String, _ total: String, _ count: String) -> String { "confirmation" }
    func chatPayStarsConfirmPayOther(_ count: Int) -> String { "send" }
}
func strings() -> StoryStrings { StoryStrings() }
enum FastSettings {
    static func toggleCofirmPaid(_ peer: PeerId, price: Int) { StoryPayments.paidPreferences.append(peer) }
}
extension FeatureNavigationHooks {
    func showStarsPurchaseWithContext(_ context: Account, _ window: Window, _ currency: StoryCurrency, _ source: Int?, _ amount: Int64?, _ origin: AnalyticsContext) {
        StoryPayments.onPurchase?(origin)
        StoryPayments.purchases.append((amount, origin))
    }
}
extension Sender {
    static func enqueue(media: [MediaSenderContainer], context: Account, peerId: PeerId, replyId: Int?, threadId: Int64?, replyStoryId: StoryReplyId?, sendPaidMessageStars: StoryStars?) -> Signal<[Int?], NoError> {
        onBuild?()
        StoryPayments.sends.append((peerId, replyStoryId, sendPaidMessageStars?.value))
        return StoryPayments.result
    }
}
final class StoryHost {
    var textSend: ((ChatTextInputState, PeerId, Int32, StoryViewController.TooptipView.Source, Int64?, AnalyticsContext) -> Void)?
    var captureReplyContext: ((PeerId) -> AnalyticsContext)?
    var starsAction: ((Bool) -> Void)?
    var window: Window? { chatInteraction.interactionContext.window }
    let chatInteraction = ChatInteraction()
    let interactions = StoryInteraction()
    let genericView = StoryView()
    var arguments: StoryArguments?
    var closed = false
    var before = 0, after = 0
    var send: (([MediaSenderContainer], AnalyticsMediaJourney?, AnalyticsContext?, AnalyticsRecordingRequest?) -> Void)?
    init(paid: Bool = true, balance: Int64 = 10) {
        chatInteraction.peer = Peer()
        chatInteraction.presentation.peer = Peer()
        chatInteraction.presentation.sendPaidMessageStars = paid ? StoryStars(value: 2) : nil
        chatInteraction.presentation.starsState = StoryBalance(balance: StoryStars(value: balance))
        arguments = StoryArguments(interaction: chatInteraction)
        genericView.storyContext?.stateValue = StoryContextState(slice: StorySlice(peer: Peer(), additionalPeerData: StoryData(paidMessage: paid ? StoryStars(value: 2) : nil)))
    }
    func install() {
        let context = chatInteraction.interactionContext
        let chatInteraction = self.chatInteraction
        let interactions = self.interactions
        let beforeCompletion: () -> Void = { [weak self] in self?.before += 1 }
        let afterCompletion: () -> Void = { [weak self] in self?.after += 1 }
        let canAvoidGroupRestrictions = { false }
__STORY_SEND__
        send = sendStoryMedia
    }
}

final class StoryPaymentTests: XCTestCase {
    override func setUp() { StoryPayments.reset(); Analytics.shared.enabled = true; Sender.onBuild = nil }
    override func tearDown() {
        StoryPayments.destroyed?()
        drain()
        StoryPayments.reset()
        Sender.onBuild = nil
        XCTAssertTrue(Analytics.activeContexts.isEmpty)
    }
    func drain() {
        let done = expectation(description: "main queue drained")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 2)
    }
    func start(_ host: StoryHost, origin: AnalyticsContext? = nil, media: [MediaSenderContainer] = [MediaSenderContainer(index: 1)]) -> AnalyticsRecordingRequest {
        host.install()
        let source = origin ?? host.chatInteraction.captureAnalyticsContext()
        let request = AnalyticsRecordingRequest(context: source)
        host.send?(media, nil, source, request)
        return request
    }
    func testOrdinaryPaidConfirmationSendsOriginalStoryOnce() {
        let host = StoryHost()
        let request = start(host)
        XCTAssertTrue(StoryPayments.sends.isEmpty)
        StoryPayments.success?(.thrid)
        StoryPayments.success?(.basic)
        StoryPayments.cancel?()
        XCTAssertEqual(StoryPayments.sends.count, 1)
        XCTAssertEqual(StoryPayments.sends.first?.1, StoryReplyId(peerId: PeerId(), id: 7))
        XCTAssertEqual(StoryPayments.sends.first?.2, 2)
        XCTAssertEqual(request.results, [true])
        XCTAssertEqual(host.before, 1)
        XCTAssertEqual(host.after, 1)
        XCTAssertEqual(StoryPayments.paidPreferences.count, 1)
    }
    func testStoryChangeAndRestoreCannotSendOrBuyAfterConfirmation() {
        for balance: Int64 in [0, 10] {
            StoryPayments.reset()
            let host = StoryHost(balance: balance)
            let request = start(host)
            let original = host.interactions.presentation
            host.interactions.update { state in var state = state; state.storyId = 8; return state }
            host.interactions.update { _ in original }
            StoryPayments.success?(.basic)
            XCTAssertTrue(StoryPayments.sends.isEmpty)
            XCTAssertTrue(StoryPayments.purchases.isEmpty)
            XCTAssertTrue(StoryPayments.paidPreferences.isEmpty)
            XCTAssertEqual(request.endings, 1)
            XCTAssertTrue(request.results.isEmpty)
            StoryPayments.destroyed?(); drain()
        }
    }
    func testCancelledConfirmationDiffersFromUnknownDismissal() {
        let cancelledHost = StoryHost()
        let cancelled = start(cancelledHost)
        StoryPayments.cancel?()
        StoryPayments.cancel?()
        XCTAssertEqual(cancelled.cancellations, 1)
        XCTAssertEqual(cancelled.endings, 0)
        StoryPayments.destroyed?(); drain()
        StoryPayments.reset()
        let host = StoryHost()
        let dismissed = start(host)
        StoryPayments.destroyed?(); drain()
        StoryPayments.success?(.basic)
        XCTAssertEqual(dismissed.endings, 1)
        XCTAssertEqual(dismissed.cancellations, 0)
        XCTAssertTrue(StoryPayments.sends.isEmpty)
    }
    func testPurchaseEndsRecordingUnknownAndPreservesContext() {
        let host = StoryHost(balance: 0)
        let origin = host.chatInteraction.captureAnalyticsContext()
        StoryPayments.onPurchase = { context in
            XCTAssertTrue(context.scope === origin.scope)
            XCTAssertTrue(Analytics.activeContexts.contains { $0.scope === origin.scope })
        }
        let request = start(host, origin: origin)
        StoryPayments.success?(.basic)
        XCTAssertEqual(StoryPayments.purchases.first?.0, 2)
        XCTAssertEqual(request.endings, 1)
        XCTAssertEqual(request.cancellations, 0)
        XCTAssertTrue(request.results.isEmpty)
        XCTAssertTrue(StoryPayments.sends.isEmpty)
    }
    func testPrivateReceivingContextExcludesConfirmationSendAndCancellation() {
        for cancel in [false, true] {
            StoryPayments.reset()
            let host = StoryHost()
            let origin = host.chatInteraction.captureAnalyticsContext()
            let request = start(host, origin: origin)
            host.chatInteraction.peer = Peer(id: PeerId(secret: true))
            Sender.onBuild = { XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded }) }
            if cancel { StoryPayments.cancel?() } else { StoryPayments.success?(.basic) }
            XCTAssertTrue(request.discarded)
            XCTAssertTrue(request.results.isEmpty)
            XCTAssertEqual(StoryPayments.sends.count, cancel ? 0 : 1)
            StoryPayments.destroyed?(); drain()
        }
    }
    func testClosedOwnerAndChangedComposerDoNotSend() {
        for close in [false, true] {
            StoryPayments.reset()
            let host = StoryHost()
            let request = start(host)
            if close { host.closed = true } else { host.chatInteraction.sendIsCurrent = false }
            StoryPayments.success?(.basic)
            XCTAssertEqual(request.endings, 1)
            XCTAssertTrue(StoryPayments.sends.isEmpty)
            StoryPayments.destroyed?(); drain()
        }
    }
    func testReleasedOwnerCannotBeRetainedByConfirmation() {
        var host: StoryHost? = StoryHost()
        let request = start(host!)
        weak var released = host
        host = nil
        XCTAssertNil(released)
        StoryPayments.success?(.basic)
        XCTAssertEqual(request.endings, 1)
        XCTAssertTrue(StoryPayments.sends.isEmpty)
    }
    func testImmediateAndRememberedPaidSendsRemainFunctional() {
        for paid in [false, true] {
            StoryPayments.reset()
            let host = StoryHost(paid: paid)
            host.chatInteraction.presentation.alwaysPaidMessage = true
            let request = start(host)
            XCTAssertNil(StoryPayments.success)
            XCTAssertEqual(StoryPayments.sends.count, 1)
            XCTAssertEqual(request.results, [true])
        }
    }
    func testEmptyMediaAndObservedBlockersDoNotOpenPaymentOrSend() {
        for reason in 0..<3 {
            StoryPayments.reset()
            let host = StoryHost()
            if reason == 1 { host.chatInteraction.presentation.slowMode = StorySlowMode(timeout: 5) }
            if reason == 2 { StoryPayments.restricted = true }
            let request = start(host, media: reason == 0 ? [] : [MediaSenderContainer(index: 1)])
            XCTAssertEqual(request.failures, [reason == 0 ? .preparation : reason == 1 ? .slowMode : .chatPermission])
            XCTAssertNil(StoryPayments.success)
            XCTAssertTrue(StoryPayments.sends.isEmpty)
            XCTAssertTrue(StoryPayments.purchases.isEmpty)
            XCTAssertEqual(host.before, 0)
        }
    }
    func testMissingOrMismatchedStoryTargetCannotOpenPayment() {
        for missing in [false, true] {
            StoryPayments.reset()
            let host = StoryHost()
            if missing { host.interactions.update { state in var state = state; state.storyId = nil; return state } }
            else { host.genericView.storyContext?.stateValue?.slice?.peer.id = PeerId(value: 2) }
            let request = start(host)
            XCTAssertEqual(request.endings, 1)
            XCTAssertNil(StoryPayments.success)
            XCTAssertTrue(StoryPayments.sends.isEmpty)
        }
    }
    func testActualPrivateTargetExcludesAlertAndPurchaseBeforeConstruction() {
        let host = StoryHost(balance: 0)
        let privatePeer = PeerId(secret: true)
        host.interactions.update { state in var state = state; state.entryId = privatePeer; return state }
        host.genericView.storyContext?.stateValue?.slice?.peer.id = privatePeer
        StoryPayments.onAlert = { XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded }) }
        StoryPayments.onPurchase = { origin in
            XCTAssertTrue(origin.isExcluded)
            XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded })
        }
        let request = start(host)
        XCTAssertTrue(request.discarded)
        StoryPayments.success?(.basic)
        XCTAssertEqual(StoryPayments.purchases.count, 1)
        XCTAssertTrue(request.steps.isEmpty)
        XCTAssertTrue(request.results.isEmpty)
    }
    func testLocalRejectionAndUnknownResultsRemainDistinct() {
        for ids: [Int?] in [[nil], [], [1, 2]] {
            StoryPayments.reset()
            let host = StoryHost(paid: false)
            StoryPayments.result = .single(ids)
            let request = start(host)
            XCTAssertEqual(request.results, ids.count == 1 ? [false] : [])
            XCTAssertEqual(host.before, 1)
            XCTAssertEqual(host.after, 1)
        }
        StoryPayments.reset()
        let host = StoryHost(paid: false)
        StoryPayments.result = .complete()
        let request = start(host)
        XCTAssertTrue(request.results.isEmpty)
        XCTAssertEqual(host.after, 1)
    }
    func testEnqueueResultAndCleanupRetainOriginalContextAfterOwnerRelease() {
        var host: StoryHost? = StoryHost(paid: false)
        let origin = host!.chatInteraction.captureAnalyticsContext()
        var complete: (() -> Void)?
        var disposed = false
        StoryPayments.result = Signal { subscriber in
            XCTAssertTrue(Analytics.activeContexts.contains { $0.scope === origin.scope })
            complete = {
                XCTAssertTrue(Analytics.activeContexts.contains { $0.scope === origin.scope })
                subscriber.putNext([1])
                subscriber.putCompletion()
            }
            return ActionDisposable {
                XCTAssertTrue(Analytics.activeContexts.contains { $0.scope === origin.scope })
                disposed = true
            }
        }
        let request = start(host!, origin: origin)
        weak var released = host
        host = nil
        XCTAssertNil(released)
        XCTAssertTrue(request.results.isEmpty)
        complete?()
        XCTAssertEqual(request.results, [true])
        XCTAssertTrue(disposed)
        complete = nil
    }

}
