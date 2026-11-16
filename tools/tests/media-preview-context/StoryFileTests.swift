struct TelegramMediaFile { let index: Int }
enum StickerBlocker: Equatable { case slowMode, chatPermission, paymentRequired, enqueueRejected }
enum StickerResult: Equatable { case accepted, terminalFailure(StickerBlocker) }
final class AnalyticsStickerSendRequest {
    let scope: Scope?
    var discarded = false
    var endings = 0, cancellations = 0
    var failures: [StickerBlocker] = []
    var steps: [AnalyticsMediaJourney.Spec.Step] = []
    var commits: [(Bool, Bool)] = []
    var results: [StickerResult?] = []
    init(context: AnalyticsContext) { scope = context.scope }
    func restrict(to context: AnalyticsContext) { if context.isExcluded || context.scope !== scope { discarded = true } }
    func step(_ step: AnalyticsMediaJourney.Spec.Step) { if !discarded { steps.append(step) } }
    func fail(_ blocker: StickerBlocker) { if !discarded { failures.append(blocker); discarded = true } }
    func end() { endings += 1; discarded = true }
    func cancel() { if !discarded { cancellations += 1; discarded = true } }
    func commit(scheduled: Bool, silent: Bool) -> StickerSubmission? {
        guard !discarded else { return nil }
        commits.append((scheduled, silent))
        return StickerSubmission(request: self)
    }
}
final class StickerSubmission {
    let request: AnalyticsStickerSendRequest
    init(request: AnalyticsStickerSendRequest) { self.request = request }
    func complete(_ result: () -> StickerResult?) { if !request.discarded { request.results.append(result()) } }
    func end() {}
}
enum StoryFiles { static var expectedCount = 1 }
extension Sender {
    static func enqueue(media: TelegramMediaFile, context: Account, peerId: PeerId, replyId: Int?, threadId: Int64?, replyStoryId: StoryReplyId?, sendPaidMessageStars: StoryStars?, observedResult: @escaping (Int, [Int?]) -> Void) -> Signal<[Int?], NoError> {
        onBuild?()
        StoryPayments.sends.append((peerId, replyStoryId, sendPaidMessageStars?.value))
        return StoryPayments.result |> map { ids in observedResult(StoryFiles.expectedCount, ids); return ids }
    }
}
extension StoryHost {
    func installFileSend() {
        let chatInteraction = self.chatInteraction
        let context = chatInteraction.interactionContext
        let beforeCompletion: () -> Void = { [weak self] in self?.before += 1 }
        let afterCompletion: () -> Void = { [weak self] in self?.after += 1 }
        let canAvoidGroupRestrictions = { false }
__STORY_FILE_SEND__
    }
}
final class StoryFileTests: XCTestCase {
    override func setUp() {
        StoryPayments.reset(); StoryFiles.expectedCount = 1; Analytics.shared.enabled = true; Sender.onBuild = nil
    }
    override func tearDown() {
        StoryPayments.destroyed?(); drain(); StoryPayments.reset(); Sender.onBuild = nil
        XCTAssertTrue(Analytics.activeContexts.isEmpty)
    }
    func drain() {
        let done = expectation(description: "dialog cleanup")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 2)
    }
    func start(_ host: StoryHost, origin: AnalyticsContext? = nil) -> AnalyticsStickerSendRequest {
        host.installFileSend()
        let origin = origin ?? host.chatInteraction.captureAnalyticsContext()
        let request = AnalyticsStickerSendRequest(context: origin)
        host.chatInteraction.sendCreatedStickerWithAnalytics?(TelegramMediaFile(index: 1), origin, request)
        return request
    }
    func testPackFileCompanionPreservesPrivateOriginThroughPayment() {
        let host = StoryHost()
        host.installFileSend()
        let origin = Analytics.shared.unresolvedContext()
        StoryPayments.onAlert = { XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded }) }
        Sender.onBuild = { XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded }) }
        host.chatInteraction.sendAppFileWithContext?(TelegramMediaFile(index: 1), true, nil, true, nil, nil, nil, origin)
        StoryPayments.success?(.basic)
        XCTAssertEqual(StoryPayments.sends.count, 1)
        XCTAssertEqual(StoryPayments.sends[0].1, StoryReplyId(peerId: PeerId(), id: 7))
    }
    func testPackFileCompanionRejectsStaleStoryConfirmation() {
        let host = StoryHost()
        host.installFileSend()
        let origin = host.chatInteraction.captureAnalyticsContext()
        host.chatInteraction.sendAppFileWithContext?(TelegramMediaFile(index: 1), false, nil, false, nil, nil, nil, origin)
        host.interactions.update { state in var state = state; state.storyId = 8; return state }
        StoryPayments.success?(.basic)
        XCTAssertTrue(StoryPayments.sends.isEmpty)
        XCTAssertTrue(StoryPayments.purchases.isEmpty)
    }
    func testCreatedStickerPreservesOriginAndConfirmsOnce() {
        let host = StoryHost()
        let origin = host.chatInteraction.captureAnalyticsContext()
        Sender.onBuild = { XCTAssertTrue(Analytics.activeContexts.contains { $0.scope === origin.scope }) }
        let request = start(host, origin: origin)
        XCTAssertEqual(request.steps, [.openConfirmation])
        StoryPayments.success?(.thrid); StoryPayments.success?(.basic); StoryPayments.cancel?()
        XCTAssertEqual(StoryPayments.sends.count, 1)
        XCTAssertEqual(StoryPayments.sends[0].1, StoryReplyId(peerId: PeerId(), id: 7))
        XCTAssertEqual(StoryPayments.sends[0].2, 2)
        XCTAssertEqual(request.commits.count, 1)
        XCTAssertFalse(request.commits[0].0); XCTAssertFalse(request.commits[0].1)
        XCTAssertEqual(request.results, [.accepted])
        XCTAssertEqual(StoryPayments.paidPreferences.count, 1)
    }
    func testStoryNavigationAndRestoreCannotSendOrPurchase() {
        for balance: Int64 in [0, 10] {
            StoryPayments.reset()
            let host = StoryHost(balance: balance)
            let request = start(host)
            let original = host.interactions.presentation
            host.interactions.update { state in var state = state; state.storyId = 8; return state }
            host.interactions.update { _ in original }
            StoryPayments.success?(.thrid)
            XCTAssertEqual(request.endings, 1)
            XCTAssertTrue(StoryPayments.sends.isEmpty); XCTAssertTrue(StoryPayments.purchases.isEmpty)
            XCTAssertTrue(StoryPayments.paidPreferences.isEmpty)
            StoryPayments.destroyed?(); drain()
        }
    }
    func testCancellationIsExplicitAndUnknownDismissalCannotSendLater() {
        for cancel in [false, true] {
            StoryPayments.reset()
            let host = StoryHost()
            let request = start(host)
            if cancel { StoryPayments.cancel?(); StoryPayments.cancel?() }
            StoryPayments.destroyed?(); drain()
            StoryPayments.success?(.basic)
            XCTAssertEqual(request.cancellations, cancel ? 1 : 0)
            XCTAssertEqual(request.endings, cancel ? 0 : 1)
            XCTAssertTrue(StoryPayments.sends.isEmpty)
        }
    }
    func testPrivateActualTargetAndLatePrivateReceivingContextSuppressRequest() {
        for scenario in 0..<4 {
            let before = scenario == 0
            StoryPayments.reset()
            let host = StoryHost()
            let origin = host.chatInteraction.captureAnalyticsContext()
            if before {
                let peer = PeerId(secret: true)
                host.interactions.update { state in var state = state; state.entryId = peer; return state }
                host.genericView.storyContext?.stateValue?.slice?.peer.id = peer
                StoryPayments.onAlert = { XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded }) }
            }
            let request = start(host, origin: origin)
            if scenario == 1 { host.chatInteraction.peer = Peer(id: PeerId(secret: true)) }
            if scenario == 2 { host.chatInteraction.interactionContext.engine = Engine() }
            if scenario == 3 { origin.scope?.isValid = false }
            Sender.onBuild = { XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded }) }
            StoryPayments.success?(.basic)
            XCTAssertTrue(request.discarded)
            XCTAssertTrue(request.results.isEmpty); XCTAssertTrue(request.commits.isEmpty)
            XCTAssertEqual(StoryPayments.sends.count, 1)
            StoryPayments.destroyed?(); drain()
        }
    }
    func testPurchaseCarriesOriginalContextAndReportsOnlyObservedPaymentBlocker() {
        let host = StoryHost(balance: 0)
        let origin = host.chatInteraction.captureAnalyticsContext()
        StoryPayments.onPurchase = { context in
            XCTAssertTrue(context.scope === origin.scope)
            XCTAssertTrue(Analytics.activeContexts.contains { $0.scope === origin.scope })
        }
        let request = start(host, origin: origin)
        StoryPayments.success?(.thrid)
        XCTAssertEqual(request.failures, [.paymentRequired])
        XCTAssertEqual(StoryPayments.purchases.count, 1)
        XCTAssertTrue(request.commits.isEmpty); XCTAssertTrue(StoryPayments.sends.isEmpty)
    }
    func testPreflightBlockersAndMismatchedMetadataNeverSend() {
        for scenario in 0..<3 {
            StoryPayments.reset()
            let host = StoryHost(paid: false)
            if scenario == 0 { host.chatInteraction.presentation.slowMode = StorySlowMode(timeout: 1) }
            if scenario == 1 { StoryPayments.restricted = true }
            if scenario == 2 { host.genericView.storyContext?.stateValue?.slice?.peer.id = PeerId(value: 9) }
            let request = start(host)
            if scenario == 2 { XCTAssertEqual(request.endings, 1) }
            else { XCTAssertEqual(request.failures, [scenario == 0 ? .slowMode : .chatPermission]) }
            XCTAssertTrue(StoryPayments.sends.isEmpty); XCTAssertNil(StoryPayments.success)
        }
    }
    func testOwnerLossClosedStateAndChangedComposerRejectPendingConfirmation() {
        for scenario in 0..<3 {
            StoryPayments.reset()
            var host: StoryHost? = StoryHost()
            let request = start(host!)
            weak var released = host
            if scenario == 0 { host = nil; XCTAssertNil(released) }
            if scenario == 1 { host?.closed = true }
            if scenario == 2 { host?.chatInteraction.sendIsCurrent = false }
            StoryPayments.success?(.thrid)
            XCTAssertTrue(StoryPayments.sends.isEmpty); XCTAssertTrue(StoryPayments.paidPreferences.isEmpty)
            XCTAssertEqual(request.endings, 1)
            StoryPayments.destroyed?(); drain()
        }
    }
    func testLocalRejectionUnknownCardinalityAndNoResultAreDistinct() {
        for (expected, ids) in [(1, [nil] as [Int?]), (1, []), (2, [1, 2])] {
            StoryPayments.reset()
            let host = StoryHost(paid: false)
            StoryFiles.expectedCount = expected; StoryPayments.result = .single(ids)
            let request = start(host)
            XCTAssertEqual(request.results.count, 1)
            XCTAssertEqual(request.results[0], ids.count == 1 && expected == 1 ? .terminalFailure(.enqueueRejected) : nil)
        }
        StoryPayments.reset()
        let host = StoryHost(paid: false)
        StoryPayments.result = .complete()
        let request = start(host)
        XCTAssertTrue(request.results.isEmpty)
    }
    func testDelayedEnqueueOutlivesOwnerAndRetainsContextThroughCleanup() {
        var host: StoryHost? = StoryHost(paid: false)
        let origin = host!.chatInteraction.captureAnalyticsContext()
        var finish: (() -> Void)?
        var disposed = false
        StoryPayments.result = Signal { subscriber in
            finish = {
                XCTAssertTrue(Analytics.activeContexts.contains { $0.scope === origin.scope })
                subscriber.putNext([1]); subscriber.putCompletion()
            }
            return ActionDisposable {
                XCTAssertTrue(Analytics.activeContexts.contains { $0.scope === origin.scope })
                disposed = true
            }
        }
        let request = start(host!, origin: origin)
        weak var released = host; host = nil
        XCTAssertNil(released)
        finish?(); finish = nil
        XCTAssertEqual(request.results, [.accepted]); XCTAssertTrue(disposed)
    }
    func testLegacyAndRememberedPaymentSendsRemainFunctionalWithoutNewCounters() {
        for paid in [false, true] {
            StoryPayments.reset()
            let host = StoryHost(paid: paid)
            host.chatInteraction.presentation.alwaysPaidMessage = true
            host.installFileSend()
            Sender.onBuild = { XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded }) }
            host.chatInteraction.sendAppFile(TelegramMediaFile(index: 1), false, nil, false, nil, nil, nil)
            XCTAssertEqual(StoryPayments.sends.count, 1)
            XCTAssertNil(StoryPayments.success)
        }
    }
}
