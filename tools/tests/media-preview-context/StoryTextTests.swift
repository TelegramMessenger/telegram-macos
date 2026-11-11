enum StoryViewController {
    enum TooptipView {
        enum Source { case text, reaction(Int) }
    }
}
final class StoryCall {
    let internalId = UUID()
    var texts: [(String, Int64?)] = []
    var stars: [Int64] = []
    var onDispatch: (() -> Void)?
    func sendMessage(text: String, entities: [Int], paidStars: Int64?) { onDispatch?(); texts.append((text, paidStars)) }
    func sendStars(amount: Int64) { onDispatch?(); stars.append(amount) }
}
struct StoryCallMessages: Equatable { var topStars: [Int] = [] }
struct StoryStreamCall: Equatable {
    var call: StoryCall?
    var messages: StoryCallMessages?
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.call?.internalId == rhs.call?.internalId && lhs.messages == rhs.messages }
}
enum StoryTexts {
    static var inputs: [ChatTextInputState] = []
    static var onPicker: (() -> Void)?
    static var picker: Star_ReactionsController?
    static var premiumCallback: ((String) -> Void)?
    static var premiumContexts: [AnalyticsContext] = []
    static func reset() { inputs = []; onPicker = nil; picker = nil; premiumCallback = nil; premiumContexts = [] }
}
extension Sender {
    static func enqueue(input: ChatTextInputState, context: Account, peerId: PeerId, replyId: Int?, threadId: Int64?, replyStoryId: StoryReplyId?, sendAsPeerId: PeerId?, sendPaidMessageStars: StoryStars?) -> Signal<[Int?], NoError> {
        onBuild?()
        StoryTexts.inputs.append(input)
        StoryPayments.sends.append((peerId, replyStoryId, sendPaidMessageStars?.value))
        return StoryPayments.result
    }
}
struct StarCallback { let value: (Int, Int, Int) -> Void }
enum StarSource { case liveStream(Peer, [Int], callback: StarCallback) }
final class Star_ReactionsController {
    var analyticsContext: AnalyticsContext?
    let callback: StarCallback
    init(context: Account, source: StarSource, presentation: Int) {
        switch source { case let .liveStream(_, _, callback): self.callback = callback }
        StoryTexts.onPicker?()
    }
}
func showModal(with controller: Star_ReactionsController, for window: Window) { StoryTexts.picker = controller }
extension StoryHost {
    func installText() {
        let chatInteraction = self.chatInteraction
        let interactions = self.interactions
        let context = chatInteraction.interactionContext
        let beforeCompletion: () -> Void = { [weak self] in self?.before += 1 }
        let afterCompletion: () -> Void = { [weak self] in self?.after += 1 }
        let canAvoidGroupRestrictions = { false }
__STORY_TEXT__
        self.textSend = sendText
        self.captureReplyContext = captureStoryReplyContext
        let darkAppearance = 0
__STORY_STARS__
    }
}
final class StoryTextTests: XCTestCase {
    override func setUp() { StoryPayments.reset(); StoryTexts.reset(); Analytics.shared.enabled = true; Sender.onBuild = nil }
    override func tearDown() {
        StoryPayments.destroyed?(); drain(); StoryPayments.reset(); StoryTexts.reset(); Sender.onBuild = nil
        XCTAssertTrue(Analytics.activeContexts.isEmpty)
    }
    func drain() {
        let done = expectation(description: "dialog release")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 2)
    }
    func send(_ host: StoryHost, text: String = "draft", reaction: Bool = false, stars: Int64? = nil, origin: AnalyticsContext? = nil) {
        host.installText()
        host.textSend?(ChatTextInputState(inputText: text), host.interactions.presentation.entryId!, host.interactions.presentation.storyId!, reaction ? .reaction(1) : .text, stars, origin ?? host.captureReplyContext!(host.interactions.presentation.entryId!))
    }
    func testPaidTextConfirmationSendsOriginalInputOnceAndClearsOnlyItsDraft() {
        let host = StoryHost()
        host.interactions.presentation.input = ChatTextInputState(inputText: "draft")
        let origin = host.chatInteraction.captureAnalyticsContext()
        Sender.onBuild = { XCTAssertTrue(Analytics.activeContexts.contains { $0.scope === origin.scope }) }
        send(host, origin: origin)
        StoryPayments.success?(.thrid); StoryPayments.success?(.basic)
        XCTAssertEqual(StoryTexts.inputs.map(\.inputText), ["draft"])
        XCTAssertEqual(StoryPayments.sends[0].1, StoryReplyId(peerId: PeerId(), id: 7))
        XCTAssertEqual(host.interactions.inputClears, 1)
        XCTAssertEqual(StoryPayments.paidPreferences.count, 1)
        XCTAssertEqual(host.after, 1)
    }
    func testReactionReplyAndStarsNeverClearUnsentText() {
        let host = StoryHost(paid: false)
        host.interactions.presentation.input = ChatTextInputState(inputText: "draft")
        send(host, text: "reaction", reaction: true)
        XCTAssertEqual(host.interactions.inputClears, 0)
        XCTAssertEqual(host.interactions.presentation.input.inputText, "draft")
        let call = StoryCall()
        host.interactions.update { state in var state = state; state.mediaCall = StoryStreamCall(call: call); state.myStars = StoryStars(value: 10); return state }
        send(host, text: "", stars: 1)
        XCTAssertEqual(call.stars, [1])
        XCTAssertEqual(host.interactions.inputClears, 0)
        XCTAssertEqual(host.genericView.resets, 0)
    }
    func testTextEnteredWhileEnqueuePendingIsPreserved() {
        let host = StoryHost(paid: false)
        host.interactions.presentation.input = ChatTextInputState(inputText: "draft")
        var finish: (() -> Void)?
        StoryPayments.result = Signal { subscriber in finish = { subscriber.putCompletion() }; return EmptyDisposable }
        send(host)
        host.interactions.presentation.input = ChatTextInputState(inputText: "new draft")
        host.chatInteraction.sendIsCurrent = false
        finish?(); finish = nil
        XCTAssertEqual(host.interactions.inputClears, 0)
        XCTAssertEqual(host.interactions.presentation.input.inputText, "new draft")
    }
    func testNavigationAndReturnDuringPaymentCannotSendOrBuy() {
        for balance: Int64 in [0, 10] {
            StoryPayments.reset()
            let host = StoryHost(balance: balance)
            send(host)
            let original = host.interactions.presentation
            host.interactions.update { state in var state = state; state.storyId = 9; return state }
            host.interactions.update { _ in original }
            StoryPayments.success?(.thrid)
            XCTAssertTrue(StoryPayments.sends.isEmpty); XCTAssertTrue(StoryPayments.purchases.isEmpty)
            XCTAssertTrue(StoryPayments.paidPreferences.isEmpty)
            StoryPayments.destroyed?(); drain()
        }
    }
    func testStreamReplacementDuringConfirmationCannotRetarget() {
        let host = StoryHost()
        let first = StoryCall(), second = StoryCall()
        host.interactions.update { state in var state = state; state.mediaCall = StoryStreamCall(call: first); return state }
        send(host)
        host.interactions.update { state in var state = state; state.mediaCall = StoryStreamCall(call: second); return state }
        StoryPayments.success?(.basic)
        XCTAssertTrue(first.texts.isEmpty); XCTAssertTrue(second.texts.isEmpty); XCTAssertTrue(StoryPayments.sends.isEmpty)
    }
    func testLiveTextDispatchPreservesOriginAndClearsUnchangedDraft() {
        let host = StoryHost(paid: false)
        let call = StoryCall()
        host.interactions.update { state in var state = state; state.mediaCall = StoryStreamCall(call: call); state.input = ChatTextInputState(inputText: "draft"); return state }
        let origin = host.chatInteraction.captureAnalyticsContext()
        call.onDispatch = { XCTAssertTrue(Analytics.activeContexts.contains { $0.scope === origin.scope }) }
        send(host, origin: origin)
        XCTAssertEqual(call.texts.map { $0.0 }, ["draft"])
        XCTAssertEqual(host.interactions.inputClears, 1)
        XCTAssertEqual(host.genericView.resets, 1)
        XCTAssertTrue(StoryPayments.sends.isEmpty)
    }
    func testInsufficientLiveBalancePreservesDraftAndPurchaseContext() {
        let host = StoryHost(paid: false)
        let call = StoryCall()
        host.interactions.update { state in var state = state; state.mediaCall = StoryStreamCall(call: call); state.input = ChatTextInputState(inputText: "draft"); return state }
        let origin = host.chatInteraction.captureAnalyticsContext()
        StoryPayments.onPurchase = { context in XCTAssertTrue(context.scope === origin.scope); XCTAssertTrue(Analytics.activeContexts.contains { $0.scope === origin.scope }) }
        send(host, stars: 2, origin: origin)
        XCTAssertEqual(StoryPayments.purchases.count, 1)
        XCTAssertTrue(call.texts.isEmpty); XCTAssertEqual(host.before, 0)
        XCTAssertEqual(host.interactions.inputClears, 0)
    }
    func testPrivateAndMissingOriginsStayExcludedThroughConfirmationAndSend() {
        for missing in [false, true] {
            StoryPayments.reset()
            let host = StoryHost()
            let origin = missing ? Analytics.shared.unresolvedContext() : host.chatInteraction.captureAnalyticsContext()
            if !missing { host.chatInteraction.peer = Peer(id: PeerId(secret: true)) }
            StoryPayments.onAlert = { XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded }) }
            Sender.onBuild = { XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded }) }
            send(host, origin: origin)
            StoryPayments.success?(.basic)
            XCTAssertEqual(StoryPayments.sends.count, 1)
            StoryPayments.destroyed?(); drain()
        }
    }
    func testCancelUnknownDismissalAndClosedOwnerCannotSend() {
        for scenario in 0..<3 {
            StoryPayments.reset()
            let host = StoryHost()
            send(host)
            if scenario == 0 { StoryPayments.cancel?() }
            if scenario == 1 { StoryPayments.destroyed?(); drain() }
            if scenario == 2 { host.closed = true }
            StoryPayments.success?(.thrid)
            XCTAssertTrue(StoryPayments.sends.isEmpty); XCTAssertTrue(StoryPayments.paidPreferences.isEmpty)
            StoryPayments.destroyed?(); drain()
        }
    }
    func testIncompleteLiveCallAndMismatchedTargetDoNotFallBackToStoryReply() {
        let host = StoryHost(paid: false)
        host.interactions.update { state in var state = state; state.mediaCall = StoryStreamCall(); return state }
        send(host)
        XCTAssertTrue(StoryPayments.sends.isEmpty)
        host.interactions.update { state in var state = state; state.mediaCall = nil; return state }
        host.textSend?(ChatTextInputState(inputText: "draft"), PeerId(value: 9), 7, .text, nil, host.chatInteraction.captureAnalyticsContext())
        XCTAssertTrue(StoryPayments.sends.isEmpty)
    }
    func testLateCompletionDoesNotMutateNewStoryOrRetainOwner() {
        var host: StoryHost? = StoryHost(paid: false)
        var finish: (() -> Void)?
        StoryPayments.result = Signal { subscriber in finish = { subscriber.putCompletion() }; return EmptyDisposable }
        send(host!)
        host?.interactions.update { state in var state = state; state.storyId = 9; return state }
        finish?()
        XCTAssertEqual(host?.after, 0)
        XCTAssertEqual(host?.interactions.inputClears, 0)
        weak var released = host; host = nil
        XCTAssertNil(released)
        finish = nil
    }
    func testStarPickerCapturesOriginalScopeAndRejectsNavigation() {
        let host = StoryHost(paid: false)
        let call = StoryCall()
        host.interactions.update { state in var state = state; state.mediaCall = StoryStreamCall(call: call); state.myStars = StoryStars(value: 10); return state }
        host.installText()
        StoryTexts.onPicker = { XCTAssertFalse(Analytics.activeContexts.isEmpty) }
        host.starsAction?(false)
        XCTAssertNotNil(StoryTexts.picker?.analyticsContext?.scope)
        let original = host.interactions.presentation
        host.interactions.update { state in var state = state; state.storyId = 9; return state }
        host.interactions.update { _ in original }
        StoryTexts.picker?.callback.value(2, 0, 0)
        XCTAssertTrue(call.stars.isEmpty)
    }
    func testStarPickerCallbackIsOnceOnlyAndRetainsPrivateOrigin() {
        let host = StoryHost(paid: false)
        let call = StoryCall()
        host.interactions.update { state in var state = state; state.mediaCall = StoryStreamCall(call: call); state.myStars = StoryStars(value: 10); return state }
        host.chatInteraction.peer = Peer(id: PeerId(secret: true))
        host.installText()
        StoryTexts.onPicker = { XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded }) }
        host.starsAction?(false)
        XCTAssertEqual(StoryTexts.picker?.analyticsContext?.isExcluded, true)
        host.chatInteraction.peer = Peer()
        call.onDispatch = { XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded }) }
        StoryTexts.picker?.callback.value(2, 0, 0)
        StoryTexts.picker?.callback.value(2, 0, 0)
        XCTAssertEqual(call.stars, [2])
    }
}

extension StoryStrings { var emojiPackPremiumAlert: String { "premium" } }
enum StoryPremiumSource { case premiumStickers }
func showModalText(for window: Window, text: String, callback: @escaping (String) -> Void) { StoryTexts.premiumCallback = callback }
extension FeatureNavigationHooks {
    func showPremiumBoardingObserved(_ context: Account, _ window: Window, _ source: StoryPremiumSource, _ open: Bool, _ appearance: Int, analyticsContext: AnalyticsContext) {
        XCTAssertTrue(Analytics.activeContexts.contains { $0.scope === analyticsContext.scope && $0.isExcluded == analyticsContext.isExcluded })
        StoryTexts.premiumContexts.append(analyticsContext)
    }
}
extension StoryHost {
    func premiumReply(origin: AnalyticsContext) {
        let interactions: StoryInteraction? = self.interactions
        let context = chatInteraction.interactionContext
        let analyticsContext = origin
        let darkAppearance = 0
__PREMIUM_REPLY__
    }
}
extension StoryTextTests {
    func testPremiumReactionPromptKeepsOriginalExclusionUntilReleased() {
        let host = StoryHost(paid: false)
        let origin = Analytics.shared.unresolvedContext()
        host.premiumReply(origin: origin)
        XCTAssertTrue(Analytics.activeContexts.contains { $0.isExcluded })
        StoryTexts.premiumCallback?("")
        StoryTexts.premiumCallback?("")
        XCTAssertEqual(StoryTexts.premiumContexts.count, 1)
        XCTAssertTrue(StoryTexts.premiumContexts[0].isExcluded)
        StoryTexts.premiumCallback = nil
        XCTAssertTrue(Analytics.activeContexts.isEmpty)
    }
    func testPremiumReactionPromptCannotOpenBoardingAfterSourceChange() {
        let host = StoryHost(paid: false)
        host.premiumReply(origin: host.chatInteraction.captureAnalyticsContext())
        let original = host.interactions.presentation
        host.interactions.update { state in var state = state; state.storyId = 9; return state }
        host.interactions.update { _ in original }
        StoryTexts.premiumCallback?("")
        XCTAssertTrue(StoryTexts.premiumContexts.isEmpty)
    }
    func testLockedSlowModeAndPermissionBlockBeforePayment() {
        for scenario in 0..<3 {
            StoryPayments.reset()
            let host = StoryHost()
            if scenario == 0 { host.interactions.presentation.lock = true }
            if scenario == 1 { host.chatInteraction.presentation.slowMode = StorySlowMode(timeout: 1) }
            if scenario == 2 { StoryPayments.restricted = true }
            send(host)
            XCTAssertNil(StoryPayments.success)
            XCTAssertTrue(StoryPayments.sends.isEmpty)
        }
    }
}
