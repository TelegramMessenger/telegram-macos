typealias AnalyticsMediaSubmission = MediaSubmission
struct Media { let index: Int }
struct ChatTextInputState: Equatable {
    var text = ""
    var hasExcludedAnalytics = false
    var inputText: String { text }
    init(text: String = "") { self.text = text }
    init(inputText: String) { text = inputText }
    func messageTextEntities() -> [Int] { [] }
}
enum AvailableMessageEffects { struct MessageEffect {} }
__DEFERRED_ACTION__
enum MessageKind { case album, image }
func chatAnalyticsMessageKind(_ media: Media?) -> MessageKind { .image }
final class SendObservation {
    func complete(expectedCount: Int, resultCount: Int, acceptedCount: Int) {}
}
extension Sender {
    static func enqueue(media: [Media], caption: ChatTextInputState, context: Account, peerId: PeerId, replyId: Int?, threadId: Int64?, isCollage: Bool, additionText: ChatTextInputState?, silent: Bool, atDate: Date?, repeatPeriod: Int32?, isSpoiler: Bool, customChatContents: Int?, messageEffect: AvailableMessageEffects.MessageEffect?, leadingText: Bool, sendPaidMessageStars: Int?, suggestPost: Int?, observedResult: @escaping (Int, [Int?]) -> Void) -> Signal<[Int?], NoError> {
        destinations.append(peerId)
        onBuild?()
        return Signal { subscriber in
            onStart?()
            let deliver = {
                let ids = media.map { Optional($0.index) }
                observedResult(ids.count, ids)
                subscriber.putNext(ids)
                subscriber.putCompletion()
            }
            if holdBatch { batchDelivery = deliver } else { deliver() }
            return ActionDisposable {
                batchDisposedUnderContext = !Analytics.activeContexts.isEmpty
                batchDelivery = nil
            }
        }
    }
}
final class BatchHost {
    let chatInteraction: ChatInteraction
    var onEntry: (AnalyticsContext, AnalyticsMediaSubmission?, Int) -> Void = { _, _, _ in }
    let nextTransaction = NextTransaction()
    var observedContexts: [AnalyticsContext] = []
    init(_ chat: ChatInteraction) { chatInteraction = chat }
    func installEntries() {
        let customChatContents: Int? = nil
__TEXT_ENTRY__
__MEDIA_ENTRY__
    }
    func makeMessageSendObservation(_ kind: MessageKind, analyticsContext: AnalyticsContext, scheduled: Bool, silent: Bool) -> SendObservation? {
        observedContexts.append(analyticsContext)
        return analyticsContext.isExcluded ? nil : SendObservation()
    }
    func applyBatch(origin: AnalyticsContext, destination: PeerId, submission: AnalyticsMediaSubmission, part: Int) {
        let schedulingAnalyticsContext = origin
        let context = chatInteraction.interactionContext
        let makePeerId = { destination }
        let medias = [Media(index: part)]
        let caption = ChatTextInputState()
        let isCollage = false, silent = false, isSpoiler = false, leadingText = false
        let additionText: ChatTextInputState? = nil
        let customChatContents: Int? = nil
        let messageEffect: AvailableMessageEffects.MessageEffect? = nil
        let presentation = chatInteraction.presentation
        let takeReplyId: () -> Int? = { nil }
        let threadId64: () -> Int64? = { nil }
        let takePaidMessageStars: () -> Int? = { nil }
        let scrollAfterSend = {}, afterSentTransition = {}
        let submission: AnalyticsMediaSubmission? = submission
__APPLY_BATCH__
        apply(self, atDate: nil, repeatPeriod: nil)
    }
}

final class MultipartTests: XCTestCase {
    override func setUp() {
        Analytics.shared.enabled = true
        Sender.destinations = []
        Sender.onBuild = nil
        Sender.onStart = nil
        Sender.holdBatch = false
        Sender.batchDelivery = nil
        Sender.batchDisposedUnderContext = false
    }
    override func tearDown() {
        Sender.onBuild = nil
        Sender.onStart = nil
        Sender.holdBatch = false
        Sender.batchDelivery = nil
        XCTAssertTrue(Analytics.activeContexts.isEmpty)
    }
    func testTextAndMediaDispatchRetainOriginalTokenAndScopeForEveryPart() {
        let chat = ChatInteraction()
        let origin = chat.captureAnalyticsContext()
        let task = AnalyticsMediaJourney(context: origin)
        let submission = MediaSubmission(journey: task)
        let host = BatchHost(chat)
        host.installEntries()
        var parts: [Int] = []
        host.onEntry = { context, received, part in
            parts.append(part)
            XCTAssertTrue(received === submission)
            XCTAssertTrue(context.scope === origin.scope)
            XCTAssertGreaterThan(origin.depth, 0)
        }
        chat.sendMessageObserved(false, nil, nil, submission: submission, part: 0)
        for part in 1...3 {
            chat.sendMediasObserved([Media(index: part)], ChatTextInputState(), true, nil, false, nil, false, nil, false, submission: submission, part: part)
        }
        XCTAssertEqual(parts, [0, 1, 2, 3])
        XCTAssertFalse(task.discarded)
    }
    func testChangedReceivingChatDiscardsWholeTokenBeforeAnyPartCallback() {
        for useText in [true, false] {
            let chat = ChatInteraction()
            let origin = chat.captureAnalyticsContext()
            let task = AnalyticsMediaJourney(context: origin)
            let submission = MediaSubmission(journey: task)
            chat.peerId.secret = true
            var calls = 0
            chat.sendMessageWithAnalytics = { _, _, _, received, _ in
                calls += 1
                XCTAssertTrue(received?.journey.discarded == true)
                XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded })
            }
            chat.sendMediasWithAnalytics = { _, _, _, _, _, _, _, _, _, received, _ in
                calls += 1
                XCTAssertTrue(received?.journey.discarded == true)
                XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded })
            }
            if useText { chat.sendMessageObserved(false, nil, nil, submission: submission, part: 0) }
            else { chat.sendMediasObserved([], ChatTextInputState(), false, nil, false, nil, false, nil, false, submission: submission, part: 1) }
            XCTAssertEqual(calls, 1)
        }
    }
    func testLegacyFallbackDiscardsObservationButStillInvokesFunctionalSend() {
        let chat = ChatInteraction()
        let origin = chat.captureAnalyticsContext()
        let task = AnalyticsMediaJourney(context: origin)
        let submission = MediaSubmission(journey: task)
        var calls = 0
        chat.sendMessage = { _, _, _ in calls += 1; XCTAssertGreaterThan(origin.depth, 0) }
        chat.sendMedias = { _, _, _, _, _, _, _, _, _ in calls += 1; XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded }) }
        chat.sendMessageObserved(false, nil, nil, submission: submission, part: 0)
        chat.sendMediasObserved([], ChatTextInputState(), false, nil, false, nil, false, nil, false, submission: submission, part: 1)
        XCTAssertEqual(calls, 2)
        XCTAssertTrue(task.discarded)
    }
    func testInstalledCallbackEntryCannotRefreshRevokedSubmissionContext() {
        let chat = ChatInteraction()
        let origin = chat.captureAnalyticsContext()
        let task = AnalyticsMediaJourney(context: origin)
        let submission = MediaSubmission(journey: task)
        let host = BatchHost(chat)
        host.installEntries()
        origin.scope?.isValid = false
        var calls = 0
        host.onEntry = { context, _, _ in calls += 1; XCTAssertTrue(context.isExcluded || context.scope == nil); XCTAssertTrue(task.discarded) }
        chat.sendMessageWithAnalytics?(false, nil, nil, submission, 0)
        chat.sendMediasWithAnalytics?([], ChatTextInputState(), false, nil, false, nil, false, nil, false, submission, 1)
        XCTAssertEqual(calls, 2)
    }
    func testMediaApplyPreservesOriginalContextThroughConstructionAndResult() {
        let chat = ChatInteraction()
        let origin = chat.captureAnalyticsContext()
        let task = AnalyticsMediaJourney(context: origin)
        let host = BatchHost(chat)
        Sender.onBuild = { XCTAssertGreaterThan(origin.depth, 0) }
        Sender.onStart = { XCTAssertGreaterThan(origin.depth, 0) }
        host.applyBatch(origin: origin, destination: PeerId(), submission: MediaSubmission(journey: task), part: 1)
        XCTAssertEqual(task.results, [true])
        XCTAssertTrue(host.observedContexts[0].scope === origin.scope)
        XCTAssertEqual(Sender.destinations.count, 1)
    }
    func testMediaApplyRestrictsActualDestinationBeforeGroupAndProvider() {
        let chat = ChatInteraction()
        let origin = chat.captureAnalyticsContext()
        let task = AnalyticsMediaJourney(context: origin)
        let host = BatchHost(chat)
        Sender.onBuild = { XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded }); XCTAssertTrue(task.discarded) }
        host.applyBatch(origin: origin, destination: PeerId(secret: true), submission: MediaSubmission(journey: task), part: 1)
        XCTAssertTrue(host.observedContexts[0].isExcluded)
        XCTAssertTrue(task.results.isEmpty)
        XCTAssertTrue(Sender.destinations[0].secret)
    }
    func testDelayedBatchRetainsOriginUntilResultAndDisposal() {
        let chat = ChatInteraction()
        let origin = chat.captureAnalyticsContext()
        let task = AnalyticsMediaJourney(context: origin)
        let host = BatchHost(chat)
        Sender.holdBatch = true
        host.applyBatch(origin: origin, destination: PeerId(), submission: MediaSubmission(journey: task), part: 1)
        XCTAssertTrue(task.results.isEmpty)
        XCTAssertGreaterThan(origin.depth, 0)
        Sender.batchDelivery?()
        XCTAssertEqual(task.results, [true])
        XCTAssertTrue(Sender.batchDisposedUnderContext)
        XCTAssertEqual(origin.depth, 0)
    }
}


extension MultipartTests {
    func testInstalledSendEntriesExcludeCachedPrivateAndUnresolvedSourcesBeforeChildren() {
        for kind in 0..<5 {
            for text in [false, true] {
                let chat = ChatInteraction()
                let origin = chat.captureAnalyticsContext()
                let journey = AnalyticsMediaJourney(context: origin)
                let submission = MediaSubmission(journey: journey)
                var privateMessage = Message()
                privateMessage.containsSecretMedia = true
                if kind >= 3 {
                    chat.presentation.interfaceState.replyMessageId = ReplySubject(messageId: privateMessage.id)
                    chat.presentation.interfaceState.replyMessage = kind == 3 ? privateMessage : nil
                } else if kind == 2 {
                    chat.presentation.interfaceState.editState = EditState(message: privateMessage)
                } else {
                    chat.presentation.interfaceState.forwardMessageIds = [privateMessage.id]
                    chat.presentation.interfaceState.forwardMessages = kind == 0 ? [privateMessage] : []
                }
                let host = BatchHost(chat)
                host.installEntries()
                var calls = 0
                host.onEntry = { context, _, _ in
                    calls += 1
                    XCTAssertTrue(context.isExcluded)
                    XCTAssertTrue(journey.discarded)
                    XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded })
                }
                if text {
                    chat.sendMessageWithAnalytics?(false, nil, nil, submission, 0)
                } else {
                    chat.sendMediasWithAnalytics?([], ChatTextInputState(), false, nil, false, nil, false, nil, false, submission, 0)
                }
                XCTAssertEqual(calls, 1)
            }
        }
    }
}
