struct MediaSenderContainer { let index: Int }
final class VoiceFlight { var cancelled = false; func cancel() { cancelled = true } }
final class MediaSubmission {
    let journey: AnalyticsMediaJourney
    var context: AnalyticsContext { journey.discarded ? Analytics.shared.unresolvedContext() : journey.context }
    init(journey: AnalyticsMediaJourney) { self.journey = journey }
    func restrict(to context: AnalyticsContext) { journey.restrict(to: context) }
    func discard() { journey.discard() }
    func group(part: Int, count: Int) -> MediaSubmission { self }
    func complete(index: Int, buildResult: () -> Bool?) {
        if !journey.discarded, let result = buildResult() { journey.results.append(result) }
    }
    var skippedParts: [Int] = []
    var batchResults: [StoryBatchResult?] = []
    var ended = false
    func skip(part: Int) { if !journey.discarded { skippedParts.append(part) } }
    func complete(index: Int, buildResult: () -> StoryBatchResult?) {
        if !journey.discarded { batchResults.append(buildResult()) }
    }
    func end() { ended = true }
}
final class AnalyticsRecordingRequest {
    enum Blocker { case preparation, slowMode, chatPermission }
    let scope: Scope?
    var discarded = false
    var cancellations = 0
    var endings = 0
    var failures: [Blocker] = []
    var steps: [AnalyticsMediaJourney.Spec.Step] = []
    var commits: [Bool] = []
    var results: [Bool] = []
    init(context: AnalyticsContext) { scope = context.scope }
    func restrict(to context: AnalyticsContext) {
        if context.isExcluded || context.scope !== scope { discarded = true }
    }
    func step(_ step: AnalyticsMediaJourney.Spec.Step) { if !discarded { steps.append(step) } }
    func fail(_ reason: Blocker) { if !discarded { failures.append(reason); discarded = true } }
    func cancel() { cancellations += 1; discarded = true }
    func end() { endings += 1; discarded = true }
    func commit(scheduled: Bool) -> RecordingSubmission? {
        guard !discarded else { return nil }
        commits.append(scheduled)
        return RecordingSubmission(request: self)
    }
}
final class RecordingSubmission {
    let request: AnalyticsRecordingRequest
    init(request: AnalyticsRecordingRequest) { self.request = request }
    func complete(buildResult: () -> Bool?) {
        if !request.discarded, let result = buildResult() { request.results.append(result) }
    }
    func end() {}
}
enum DateMode { case schedule(PeerId) }
struct DateRequest {
    let origin: AnalyticsContext
    let selected: (Date?, Int32?) -> Void
    let cancelled: () -> Void
    let dismissed: () -> Void
}
final class FeatureNavigationHooks {
    static let shared = FeatureNavigationHooks()
    var dates: [DateRequest] = []
    var onShow: ((AnalyticsContext) -> Void)?
    func selectDateObserved(_ context: Account, _ window: Window, _ date: Int?, _ value: Int?, _ mode: DateMode, analyticsContext: AnalyticsContext, selectedAt: @escaping (Date?, Int32?) -> Void, cancelled: @escaping () -> Void, dismissed: @escaping () -> Void) {
        onShow?(analyticsContext)
        dates.append(DateRequest(origin: analyticsContext, selected: selectedAt, cancelled: cancelled, dismissed: dismissed))
    }
}
enum Sender {
    static var destinations: [PeerId] = []
    static var onBuild: (() -> Void)?
    static var onStart: (() -> Void)?
    static var holdBatch = false
    static var batchDelivery: (() -> Void)?
    static var batchDisposedUnderContext = false
    static func enqueue(media: [MediaSenderContainer], context: Account, peerId: PeerId, replyId: Int?, threadId: Int64?, atDate: Date? = nil, repeatPeriod: Int32? = nil, sendAsPeerId: Int?, customChatContents: Int?, sendPaidMessageStars: Int?) -> Signal<[Int?], NoError> {
        destinations.append(peerId)
        onBuild?()
        return Signal { subscriber in
            onStart?()
            subscriber.putNext(media.map { Optional($0.index) })
            subscriber.putCompletion()
            return EmptyDisposable
        }
    }
}
func chatAnalyticsEnqueueResult(_ ids: [Int?]) -> Bool? { ids.isEmpty ? nil : ids.allSatisfy { $0 != nil } }
final class NextTransaction { func set(handler: @escaping () -> Void) {} }
final class DirectHost {
    let chatInteraction: ChatInteraction
    var context: Account { chatInteraction.interactionContext }
    var mode: ChatMode { chatInteraction.mode }
    let nextTransaction = NextTransaction()
    var destination = PeerId()
    var destinationReads = 0
    init(_ chat: ChatInteraction) { chatInteraction = chat }
    func install(custom: Int? = nil, target: PeerId? = nil) {
        let context = self.context
        let peerId = target ?? chatInteraction.peerId
        let customChatContents = custom
        let makePeerId: () -> PeerId = { [weak self] in
            self?.destinationReads += 1
            return self?.destination ?? peerId
        }
        let takeReplyId: () -> Int? = { nil }
        let threadId64: () -> Int64? = { nil }
        let takePaidMessageStars: () -> Int? = { nil }
        let scrollAfterSend = {}
        let afterSentTransition = {}
__DIRECT_CONTROLLER__
    }
}
func storySendPrefix(chatInteraction: ChatInteraction, container: [MediaSenderContainer], journey: AnalyticsMediaJourney?, inheritedContext: AnalyticsContext?, recordingRequest: AnalyticsRecordingRequest?, callback: (AnalyticsContext) -> Void) {
    let interactions = StoryInteraction()
__STORY_PREFIX__
    callback(analyticsContext)
}

final class DirectMediaTests: XCTestCase {
    let media = [MediaSenderContainer(index: 1)]
    override func setUp() {
        Analytics.shared.enabled = true
        Sender.destinations = []
        Sender.onBuild = nil
        Sender.onStart = nil
        FeatureNavigationHooks.shared.dates = []
        FeatureNavigationHooks.shared.onShow = nil
        XCTAssertTrue(Analytics.activeContexts.isEmpty)
    }
    override func tearDown() {
        FeatureNavigationHooks.shared.dates = []
        FeatureNavigationHooks.shared.onShow = nil
        Sender.onBuild = nil
        Sender.onStart = nil
        XCTAssertTrue(Analytics.activeContexts.isEmpty)
    }
    func chat() -> ChatInteraction {
        let chat = ChatInteraction()
        chat.peer = Peer()
        return chat
    }
    func assertPrivate() {
        XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded || $0.scope == nil })
    }
    func testMediaAndRecordingWrappersValidateBeforeProviderCallback() {
        let chat = chat()
        let origin = chat.captureAnalyticsContext()
        let journey = AnalyticsMediaJourney(context: origin)
        let recording = AnalyticsRecordingRequest(context: origin)
        chat.peerId.secret = true
        var calls = 0
        chat.sendMediaWithJourney = { media, task, context in
            calls += 1
            XCTAssertEqual(media.count, 1)
            XCTAssertTrue(context?.isExcluded == true)
            XCTAssertTrue(task?.discarded == true)
            self.assertPrivate()
        }
        chat.sendRecordingMediaWithAnalytics = { media, context, request in
            calls += 1
            XCTAssertEqual(media.count, 1)
            XCTAssertTrue(context.isExcluded)
            XCTAssertTrue(request?.discarded == true)
            self.assertPrivate()
        }
        chat.sendMediaObserved(media, journey: journey, analyticsContext: origin)
        chat.sendRecordingMediaObserved(media, analyticsContext: origin, request: recording)
        XCTAssertEqual(calls, 2)
    }
    func testLegacyFallbackAndMissingOriginRemainFunctionalAndUnobserved() {
        let chat = chat()
        let origin = chat.captureAnalyticsContext()
        let journey = AnalyticsMediaJourney(context: origin)
        var calls = 0
        chat.sendMedia = { media in calls += 1; XCTAssertEqual(media.count, 1); self.assertPrivate() }
        chat.sendMediaObserved(media, journey: journey)
        let recording = AnalyticsRecordingRequest(context: origin)
        chat.peerId.secret = true
        chat.sendRecordingMediaObserved(media, analyticsContext: origin, request: recording)
        XCTAssertTrue(journey.discarded)
        XCTAssertTrue(recording.discarded)
        XCTAssertEqual(calls, 2)
    }
    func testImmediateMediaProviderConstructionAndResultUseOriginalContext() {
        let chat = chat()
        let origin = chat.captureAnalyticsContext()
        let journey = AnalyticsMediaJourney(context: origin)
        let host = DirectHost(chat)
        host.install()
        Sender.onBuild = { XCTAssertGreaterThan(origin.depth, 0) }
        Sender.onStart = { XCTAssertGreaterThan(origin.depth, 0) }
        chat.sendMediaWithJourney?(media, journey, origin)
        XCTAssertEqual(journey.commits, [false])
        XCTAssertEqual(journey.results, [true])
        XCTAssertEqual(Sender.destinations.count, 1)
        XCTAssertFalse(journey.discarded)
    }
    func testInstalledDirectCallbackRejectsSecretDestinationAndForeignScope() {
        for scenario in 0..<3 {
            Sender.onBuild = nil
            let chat = chat()
            let origin = chat.captureAnalyticsContext()
            let journey = AnalyticsMediaJourney(context: origin)
            let host = DirectHost(chat)
            if scenario == 0 { chat.peerId.secret = true }
            host.install(target: scenario == 1 ? PeerId(secret: true) : nil)
            let supplied = scenario == 2 ? chat.captureAnalyticsContext() : origin
            if scenario != 2 { Sender.onBuild = { self.assertPrivate() } }
            chat.sendMediaWithJourney?(media, journey, supplied)
            XCTAssertTrue(journey.discarded)
            XCTAssertTrue(journey.commits.isEmpty)
            XCTAssertEqual(Sender.destinations.count, scenario + 1)
        }
    }
    func testRecordingRestrictionPrecedesEmptyPreparationFailure() {
        let chat = chat()
        let origin = chat.captureAnalyticsContext()
        let recording = AnalyticsRecordingRequest(context: origin)
        let host = DirectHost(chat)
        host.install()
        chat.peerId.secret = true
        chat.sendRecordingMediaWithAnalytics?([], origin, recording)
        XCTAssertTrue(recording.discarded)
        XCTAssertTrue(recording.failures.isEmpty)
        XCTAssertTrue(recording.commits.isEmpty)
    }
    func testScheduledSelectionRevalidatesActualDestinationOnce() {
        let chat = chat()
        chat.mode = .scheduled
        let origin = chat.captureAnalyticsContext()
        let journey = AnalyticsMediaJourney(context: origin)
        let host = DirectHost(chat)
        host.install()
        chat.sendMediaWithJourney?(media, journey, origin)
        XCTAssertEqual(journey.steps, [.openSchedule])
        host.destination.secret = true
        Sender.onBuild = { self.assertPrivate() }
        Sender.onStart = { self.assertPrivate() }
        FeatureNavigationHooks.shared.dates[0].selected(Date(), nil)
        XCTAssertEqual(host.destinationReads, 1)
        XCTAssertEqual(Sender.destinations.count, 1)
        XCTAssertTrue(Sender.destinations[0].secret)
        XCTAssertTrue(journey.discarded)
        XCTAssertTrue(journey.commits.isEmpty)
    }
    func testScheduledRecordingRejectsChangedChatBeforeCommit() {
        let chat = chat()
        chat.mode = .scheduled
        let origin = chat.captureAnalyticsContext()
        let recording = AnalyticsRecordingRequest(context: origin)
        let host = DirectHost(chat)
        host.install()
        chat.sendRecordingMediaWithAnalytics?(media, origin, recording)
        XCTAssertEqual(recording.steps, [.openSchedule])
        chat.peerId.secret = true
        Sender.onBuild = { self.assertPrivate() }
        FeatureNavigationHooks.shared.dates[0].selected(Date(), nil)
        XCTAssertTrue(recording.discarded)
        XCTAssertTrue(recording.commits.isEmpty)
        XCTAssertEqual(Sender.destinations.count, 1)
    }
    func testEligibleScheduledRecordingAndMediaCanStillCommit() {
        for recording in [false, true] {
            let chat = chat()
            chat.mode = .scheduled
            let origin = chat.captureAnalyticsContext()
            let host = DirectHost(chat)
            let task = AnalyticsMediaJourney(context: origin)
            let request = AnalyticsRecordingRequest(context: origin)
            host.install()
            if recording { chat.sendRecordingMediaObserved(media, analyticsContext: origin, request: request) }
            else { chat.sendMediaObserved(media, journey: task, analyticsContext: origin) }
            FeatureNavigationHooks.shared.dates.last?.selected(Date(), 2)
            XCTAssertEqual(recording ? request.commits : task.commits, [true])
            XCTAssertEqual(recording ? request.results : task.results, [true])
        }
        XCTAssertEqual(Sender.destinations.count, 2)
    }
    func testScheduledCancellationRevalidatesBeforeRecordingCancelSteps() {
        for recording in [false, true] {
            let chat = chat()
            chat.mode = .scheduled
            let origin = chat.captureAnalyticsContext()
            let host = DirectHost(chat)
            let task = AnalyticsMediaJourney(context: origin)
            let request = AnalyticsRecordingRequest(context: origin)
            host.install()
            if recording { chat.sendRecordingMediaObserved(media, analyticsContext: origin, request: request) }
            else { chat.sendMediaObserved(media, journey: task, analyticsContext: origin) }
            chat.peerId.secret = true
            FeatureNavigationHooks.shared.dates.last?.cancelled()
            XCTAssertEqual(recording ? request.steps : task.steps, [.openSchedule])
            XCTAssertTrue(recording ? request.discarded : task.discarded)
        }
        XCTAssertTrue(Sender.destinations.isEmpty)
    }
    func testReleasedScheduledOwnerDiscardsWithoutEnqueue() {
        let chat = chat()
        chat.mode = .scheduled
        let origin = chat.captureAnalyticsContext()
        let task = AnalyticsMediaJourney(context: origin)
        var host: DirectHost? = DirectHost(chat)
        host?.install()
        chat.sendMediaWithJourney?(media, task, origin)
        weak var released = host
        host = nil
        XCTAssertNil(released)
        FeatureNavigationHooks.shared.dates[0].selected(Date(), nil)
        XCTAssertTrue(task.discarded)
        XCTAssertTrue(Sender.destinations.isEmpty)
    }
    func testStoryPrefixValidatesRecordingBeforeFailureAndPaidPreflight() {
        for secret in [false, true] {
            let chat = chat()
            let origin = chat.captureAnalyticsContext()
            let request = AnalyticsRecordingRequest(context: origin)
            chat.peerId.secret = secret
            var reachedPreflight = false
            storySendPrefix(chatInteraction: chat, container: [], journey: nil, inheritedContext: origin, recordingRequest: request) { _ in
                reachedPreflight = true
            }
            XCTAssertFalse(reachedPreflight)
            XCTAssertEqual(request.failures.count, secret ? 0 : 1)
            let nonemptyRequest = AnalyticsRecordingRequest(context: origin)
            storySendPrefix(chatInteraction: chat, container: media, journey: nil, inheritedContext: origin, recordingRequest: nonemptyRequest) { context in
                reachedPreflight = true
                XCTAssertEqual(context.isExcluded, secret)
                XCTAssertGreaterThan(context.depth, 0)
            }
            XCTAssertTrue(reachedPreflight)
        }
    }
}
