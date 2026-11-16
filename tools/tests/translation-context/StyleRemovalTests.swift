__REMOVAL_ERROR__
enum ConfirmResult { case basic, thrid }
struct RemovalStyle { let id: String; let isAuthor: Bool }
final class StyleConfirmation {
    let option: String?
    let success: (ConfirmResult) -> Void
    let onDeinit: () -> Void
    init(option: String?, success: @escaping (ConfirmResult) -> Void, onDeinit: @escaping () -> Void) {
        self.option = option; self.success = success; self.onDeinit = onDeinit
    }
    deinit { onDeinit() }
}
enum StyleRemovalProbe {
    static var confirmation: StyleConfirmation?
    static var calls: [(String, Int64, Int64)] = []
    static var sinks: [Subscriber<Never, DeleteAITextStyleError>] = []
    static var disposals = 0
    static var state = State()
    static var requests = 0
    static func reset() { confirmation = nil; calls = []; sinks = []; disposals = 0; state = State(); requests = 0 }
}
func verifyAlert(for window: Int, header: String, information: String, ok: String, option: String? = nil, successHandler: @escaping (ConfirmResult) -> Void, onDeinit: @escaping () -> Void) {
    Probe.check?()
    XCTAssertEqual(window, 1); XCTAssertEqual(header, "delete-style"); XCTAssertEqual(information, "confirm-delete"); XCTAssertEqual(ok, "Delete")
    StyleRemovalProbe.confirmation = StyleConfirmation(option: option, success: successHandler, onDeinit: onDeinit)
}
extension Messages {
    func deleteAITextStyle(id: Int64, accessHash: Int64) -> Signal<Never, DeleteAITextStyleError> { styleRemoval("delete", id, accessHash) }
    func unsaveAITextStyle(id: Int64, accessHash: Int64) -> Signal<Never, DeleteAITextStyleError> { styleRemoval("unsave", id, accessHash) }
    private func styleRemoval(_ name: String, _ id: Int64, _ hash: Int64) -> Signal<Never, DeleteAITextStyleError> {
        Probe.check?(); StyleRemovalProbe.calls.append((name, id, hash))
        return Signal { sink in
            Probe.check?(); StyleRemovalProbe.sinks.append(sink)
            return ActionDisposable { Probe.check?(); StyleRemovalProbe.disposals += 1 }
        }
    }
}
func makeStyleRemoval(_ context: Context, author: Bool, getAnalyticsContext: @escaping () -> AnalyticsContext) -> () -> Void {
    let style = RemovalStyle(id: "custom_42", isAuthor: author)
    let styleId: Int64 = 42
    let accessHash: Int64 = 91
    let updateState: ((State) -> State) -> Void = { transform in Probe.check?(); StyleRemovalProbe.state = transform(StyleRemovalProbe.state) }
    let request: () -> Void = { Probe.check?(); StyleRemovalProbe.requests += 1 }
    return {
__STYLE_REMOVAL__
    }
}
final class StyleRemovalTests: XCTestCase {
    var context: Context!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Probe.check = nil; StyleRemovalProbe.reset(); Analytics.shared = Analytics(); context = Context()
        hub.policy.setOwner(context.engine.account); hub.policy.isEnabled = true
        StyleRemovalProbe.state.styles = [.init(id: "custom_42", authorId: nil), .init(id: "other", authorId: nil)]
        StyleRemovalProbe.state.styleId = "custom_42"
    }
    override func tearDown() {
        Probe.check = nil
        StyleRemovalProbe.sinks.forEach { $0.putCompletion() }; StyleRemovalProbe.reset()
        super.tearDown()
    }
    func origin(_ id: PeerId = 1) -> AnalyticsContext { hub.captureContext(engine: context.engine, peerId: id) }
    func excluded() { Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) } }
    func testAuthorDeleteAndUnsavePreserveOptionsAndLocalRemoval() {
        for result in [ConfirmResult.thrid, .basic] {
            StyleRemovalProbe.state.styles = [.init(id: "custom_42", authorId: nil), .init(id: "other", authorId: nil)]
            StyleRemovalProbe.state.styleId = "custom_42"
            let source = origin()
            Probe.check = { XCTAssertFalse(self.hub.policy.hasExclusions) }
            makeStyleRemoval(context, author: true, getAnalyticsContext: { source })()
            XCTAssertEqual(StyleRemovalProbe.confirmation?.option, "for-all")
            StyleRemovalProbe.confirmation?.success(result)
            let call = StyleRemovalProbe.calls.last!
            XCTAssertEqual(call.0, result == .thrid ? "delete" : "unsave")
            XCTAssertEqual(call.1, 42); XCTAssertEqual(call.2, 91)
            XCTAssertEqual(StyleRemovalProbe.state.styles.map(\.id), ["other"])
            XCTAssertEqual(StyleRemovalProbe.state.styleId, "")
            StyleRemovalProbe.confirmation = nil; StyleRemovalProbe.sinks.last?.putCompletion()
        }
        XCTAssertEqual(StyleRemovalProbe.requests, 2); XCTAssertEqual(StyleRemovalProbe.disposals, 2)
    }
    func testNonAuthorOnlyUnsavesAndPreservesDifferentSelection() {
        let source = origin(); StyleRemovalProbe.state.styleId = "other"
        makeStyleRemoval(context, author: false, getAnalyticsContext: { source })()
        XCTAssertNil(StyleRemovalProbe.confirmation?.option)
        StyleRemovalProbe.confirmation?.success(.thrid)
        XCTAssertEqual(StyleRemovalProbe.calls.last?.0, "unsave")
        XCTAssertEqual(StyleRemovalProbe.state.styleId, "other")
    }
    func testExcludedConfirmationAndRequestOutliveParentModal() {
        for author in [true, false] {
            excluded()
            var modal: Modal? = makeTranslation(context, analyticsContext: origin(-1))
            let action = makeStyleRemoval(context, author: author, getAnalyticsContext: modal!.getOrigin)
            action(); modal = nil
            XCTAssertTrue(hub.policy.hasExclusions)
            StyleRemovalProbe.confirmation?.success(.thrid)
            StyleRemovalProbe.confirmation = nil
            XCTAssertTrue(hub.policy.hasExclusions)
            StyleRemovalProbe.sinks.last?.putCompletion()
            XCTAssertFalse(hub.policy.hasExclusions)
        }
        XCTAssertEqual(StyleRemovalProbe.calls.map { $0.0 }, ["delete", "unsave"])
        XCTAssertEqual(StyleRemovalProbe.requests, 2); XCTAssertEqual(StyleRemovalProbe.disposals, 2)
    }
    func testCancellationOrDismissalReleasesPrivacyWithoutMutation() {
        excluded()
        var modal: Modal? = makeTranslation(context, analyticsContext: origin(-1))
        makeStyleRemoval(context, author: true, getAnalyticsContext: modal!.getOrigin)()
        modal = nil; XCTAssertTrue(hub.policy.hasExclusions)
        StyleRemovalProbe.confirmation = nil
        XCTAssertFalse(hub.policy.hasExclusions)
        XCTAssertTrue(StyleRemovalProbe.calls.isEmpty); XCTAssertEqual(StyleRemovalProbe.requests, 0)
        XCTAssertEqual(StyleRemovalProbe.state.styleId, "custom_42")
    }
    func testRetainedConfirmationCallbackRevalidatesAfterAccountChange() {
        var modal: Modal? = makeTranslation(context, analyticsContext: origin())
        makeStyleRemoval(context, author: true, getAnalyticsContext: modal!.getOrigin)()
        let callback = StyleRemovalProbe.confirmation!.success
        modal = nil; StyleRemovalProbe.confirmation = nil
        XCTAssertFalse(hub.policy.hasExclusions)
        hub.policy.setOwner(Account()); excluded(); callback(.basic)
        XCTAssertEqual(StyleRemovalProbe.calls.last?.0, "unsave")
        StyleRemovalProbe.sinks.last?.putCompletion(); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testRevokedOriginRemainsExcludedAfterDialogRelease() {
        let source = origin()
        var modal: Modal? = makeTranslation(context, analyticsContext: source)
        makeStyleRemoval(context, author: false, getAnalyticsContext: modal!.getOrigin)()
        let callback = StyleRemovalProbe.confirmation!.success
        modal = nil; StyleRemovalProbe.confirmation = nil
        source.scope?.exclude(); excluded(); callback(.basic)
        XCTAssertEqual(StyleRemovalProbe.calls.last?.0, "unsave")
        StyleRemovalProbe.sinks.last?.putCompletion(); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testFailedRequestReleasesPrivacyAndKeepsExistingLocalRemovalBehavior() {
        excluded()
        var modal: Modal? = makeTranslation(context, analyticsContext: origin(-1))
        makeStyleRemoval(context, author: true, getAnalyticsContext: modal!.getOrigin)()
        modal = nil
        StyleRemovalProbe.confirmation?.success(.thrid); StyleRemovalProbe.confirmation = nil
        XCTAssertTrue(hub.policy.hasExclusions)
        StyleRemovalProbe.sinks.last?.putError(.generic)
        XCTAssertFalse(hub.policy.hasExclusions); XCTAssertEqual(StyleRemovalProbe.disposals, 1)
        XCTAssertEqual(StyleRemovalProbe.state.styles.map(\.id), ["other"])
        XCTAssertEqual(StyleRemovalProbe.requests, 1)
    }
    func testDisabledCollectionStillAllowsConfirmationAndDeletion() {
        hub.policy.isEnabled = false; excluded()
        var modal: Modal? = makeTranslation(context, analyticsContext: origin())
        makeStyleRemoval(context, author: true, getAnalyticsContext: modal!.getOrigin)()
        modal = nil
        StyleRemovalProbe.confirmation?.success(.thrid); StyleRemovalProbe.confirmation = nil
        XCTAssertEqual(StyleRemovalProbe.calls.last?.0, "delete")
        XCTAssertEqual(StyleRemovalProbe.requests, 1)
        StyleRemovalProbe.sinks.last?.putCompletion(); XCTAssertFalse(hub.policy.hasExclusions)
    }
}
