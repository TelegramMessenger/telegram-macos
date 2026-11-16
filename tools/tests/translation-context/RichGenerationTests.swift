__COMPOSE_ERROR__
__COMPOSE_STATE__
struct ComposeArguments {
    let context: Context
    let updatePrompt: (Updated_ChatTextInputState) -> Void
}
extension Updated_ChatTextInputState {
    func textInputState() -> ChatTextInputState {
        var state = ChatTextInputState(inputText: inputText.string, selectionRange: 0..<0, attributes: [])
        inputText.enumerateAttribute(chatInputAnalyticsExcludedAttribute, in: NSRange(location: 0, length: inputText.length)) { value, _, _ in
            if value != nil { state.hasExcludedAnalytics = true }
        }
        return state
    }
}
extension Strings {
    var richTextAiComposeTitle: String { "Generate" }
    var richTextAiComposeGenerate: String { "Generate" }
    var richTextAiComposeAddToPage: String { "Add to Page" }
    var loginFloodWait: String { "limit" }
    var richTextAiComposeErrorEmpty: String { "empty" }
    var richTextAiComposeErrorTooLong: String { "long" }
}
extension Theme.Colors { var underSelectedColor: Int { 1 } }
extension ModalHeaderData { init(title: String) { image = 0; handler = {} } }
func entries(_ state: ComposeState, arguments: ComposeArguments) -> [State] {
    Probe.check?(); ComposeProbe.state = state; ComposeProbe.arguments = arguments; return []
}
func alert(for window: Int, info: String) { Probe.check?(); ComposeProbe.errors.append(info) }
class ComposeSubview {
    weak var parent: ComposeButton?
    func removeFromSuperview() { Probe.check?(); parent?.subviews.removeAll { $0 === self } }
}
final class ProgressIndicator: ComposeSubview {
    var progressColor = 0
    init(frame: NSRect) { Probe.check?() }
    func center() { Probe.check?() }
}
final class ComposeButton {
    enum Kind { case Normal }
    var subviews: [ComposeSubview] = []
    var text = ""
    var userInteractionEnabled = true
    func addSubview(_ view: ComposeSubview) { Probe.check?(); view.parent = self; subviews.append(view) }
    func set(text: String, for kind: Kind) { Probe.check?(); self.text = text }
}
final class ComposeInteractions {
    let accept: () -> Void
    let button = ComposeButton()
    init(acceptTitle: String, accept: @escaping () -> Void, singleButton: Bool) { self.accept = accept }
    func updateDone(_ action: (ComposeButton) -> Void) { Probe.check?(); action(button) }
}
final class ComposeController: Controller {
    enum Screen { case chatRichEditorAiCompose }
    var analyticsScreen: Screen?
    var validateData: ((Int) -> EditorValidation)?
    var leftModalHeader: ModalHeaderData?
    var centerModalHeader: ModalHeaderData?
    init(dataSignal: Signal<InputDataSignalValue, NoError>, title: String, removeAfterDisappear: Bool, hasDone: Bool) {
        Probe.check?(); super.init(dataSignal)
    }
}
final class ComposeModal {
    let controller: ComposeController
    let interactions: ComposeInteractions
    var analyticsContext: AnalyticsContext?
    init(_ controller: ComposeController, modalInteractions: ComposeInteractions, size: NSSize) {
        Probe.check?(); self.controller = controller; interactions = modalInteractions
    }
    func close() { Probe.check?(); ComposeProbe.closes += 1 }
}
enum ComposeProbe {
    static var requests: [(InstantPage?, String?)] = []
    static var sinks: [Subscriber<InstantPage, TranslationError>] = []
    static var state = ComposeState()
    static var arguments: ComposeArguments?
    static var disposals = 0
    static var closes = 0
    static var errors: [String] = []
    static func reset() { requests = []; sinks = []; state = ComposeState(); arguments = nil; disposals = 0; closes = 0; errors = [] }
}
extension Messages {
    func composeRichMessageWithAI(instantPage: InstantPage?, customPrompt: String?) -> Signal<InstantPage, TranslationError> {
        Probe.check?(); ComposeProbe.requests.append((instantPage, customPrompt))
        return Signal { sink in
            Probe.check?(); ComposeProbe.sinks.append(sink)
            return ActionDisposable { Probe.check?(); ComposeProbe.disposals += 1 }
        }
    }
}
func extractingAIFormulas(_ blocks: [Block]) -> [Block] { Probe.check?(); return blocks }
func generationReceiver(context: Context, analyticsContext: AnalyticsContext, coordinator: RichEntryCoordinator) -> (InstantPage) -> Void {
    return __COMPOSE_RECEIVER__
}
__COMPOSE_FACTORY__

final class RichGenerationTests: XCTestCase {
    var context: Context!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Analytics.shared = Analytics(); context = Context()
        hub.policy.setOwner(context.engine.account); hub.policy.isEnabled = true
        Probe.check = nil; ComposeProbe.reset()
    }
    override func tearDown() { Probe.check = nil; ComposeProbe.reset() }
    func origin(_ peer: PeerId = 1) -> AnalyticsContext { hub.captureContext(engine: context.engine, peerId: peer) }
    func prompt(_ text: String, excluded: Bool = false) {
        let attributed = NSAttributedString(string: text)
        ComposeProbe.arguments?.updatePrompt(.init(inputText: excluded ? chatInputTextExcludingAnalytics(attributed) : attributed))
    }
    func testOrdinaryGenerationPreviewsThenAddsWithOriginalScope() {
        let source = origin(), coordinator = RichEntryCoordinator()
        let value = RichTextAiComposeController(context: context, analyticsContext: source, completion: generationReceiver(context: context, analyticsContext: source, coordinator: coordinator))
        XCTAssertTrue(value.analyticsContext?.scope === source.scope)
        XCTAssertTrue(value.controller.analyticsContext?.scope === source.scope)
        prompt("  make a table \n")
        value.interactions.accept()
        XCTAssertEqual(ComposeProbe.requests.count, 1)
        XCTAssertNil(ComposeProbe.requests.first?.0)
        XCTAssertEqual(ComposeProbe.requests.first?.1, "make a table")
        XCTAssertFalse(value.interactions.button.userInteractionEnabled)
        XCTAssertEqual(value.interactions.button.subviews.count, 1)
        ComposeProbe.sinks[0].putNext([1, 2]); ComposeProbe.sinks[0].putCompletion()
        XCTAssertEqual(value.interactions.button.text, "Add to Page")
        XCTAssertTrue(value.interactions.button.userInteractionEnabled)
        XCTAssertTrue(value.interactions.button.subviews.isEmpty)
        XCTAssertTrue(coordinator.editor.blocks.isEmpty)
        value.interactions.accept()
        XCTAssertEqual(coordinator.editor.blocks, [1, 2]); XCTAssertEqual(coordinator.editor.focuses, 1)
        XCTAssertEqual(ComposeProbe.closes, 1); XCTAssertEqual(ComposeProbe.requests.count, 1)
    }
    func testEmptyAndDuplicateGenerateDoNotCreateExtraRequests() {
        let value = RichTextAiComposeController(context: context, analyticsContext: origin(), completion: { _ in XCTFail() })
        prompt(" \n "); value.interactions.accept(); XCTAssertTrue(ComposeProbe.requests.isEmpty)
        prompt("hello"); value.interactions.accept(); value.interactions.accept()
        _ = value.controller.validateData?(0)
        prompt("ignored during request")
        XCTAssertEqual(ComposeProbe.requests.count, 1)
        XCTAssertEqual(ComposeProbe.state.prompt.inputText.string, "hello")
    }
    func testPromptTextChangeInvalidatesPreviewButFormattingChangeDoesNot() {
        let value = RichTextAiComposeController(context: context, analyticsContext: origin(), completion: { _ in })
        prompt("hello"); value.interactions.accept(); ComposeProbe.sinks[0].putNext([1]); ComposeProbe.sinks[0].putCompletion()
        ComposeProbe.arguments?.updatePrompt(.init(inputText: NSAttributedString(string: "hello", attributes: [.font: 1])))
        XCTAssertEqual(ComposeProbe.state.result, [1]); XCTAssertEqual(ComposeProbe.state.resultToken, 1)
        prompt("changed"); XCTAssertNil(ComposeProbe.state.result)
        XCTAssertEqual(value.interactions.button.text, "Generate")
        value.interactions.accept(); XCTAssertEqual(ComposeProbe.requests.count, 2)
    }
    func testMarkedPromptPermanentlyExcludesSharedEditorOrigin() {
        let source = origin(), coordinator = RichEntryCoordinator()
        var value: ComposeModal? = RichTextAiComposeController(context: context, analyticsContext: source, completion: generationReceiver(context: context, analyticsContext: source, coordinator: coordinator))
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        prompt("private", excluded: true)
        XCTAssertTrue(source.isExcluded)
        value?.interactions.accept(); ComposeProbe.sinks[0].putNext([4]); ComposeProbe.sinks[0].putCompletion()
        let apply = value!.interactions.accept
        value = nil; apply()
        XCTAssertEqual(coordinator.editor.blocks, [4]); XCTAssertTrue(source.isExcluded)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testSameTextMarkedAfterGenerationExcludesTheExistingPreview() {
        let source = origin(), coordinator = RichEntryCoordinator()
        let value = RichTextAiComposeController(context: context, analyticsContext: source, completion: generationReceiver(context: context, analyticsContext: source, coordinator: coordinator))
        prompt("hello"); value.interactions.accept()
        ComposeProbe.sinks[0].putNext([5]); ComposeProbe.sinks[0].putCompletion()
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        prompt("hello", excluded: true)
        XCTAssertTrue(source.isExcluded)
        XCTAssertEqual(ComposeProbe.state.result, [5])
        value.interactions.accept()
        XCTAssertEqual(coordinator.editor.blocks, [5])
        XCTAssertEqual(ComposeProbe.requests.count, 1)
    }
    func testPrivateAndMissingOriginsGuardWorkAndRetainedCompletion() {
        for source in [origin(-1), nil] {
            var output: InstantPage?
            Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
            var value: ComposeModal? = RichTextAiComposeController(context: context, analyticsContext: source, completion: { result in Probe.check?(); output = result })
            prompt("hello"); value?.interactions.accept(); ComposeProbe.sinks.last?.putNext([3]); ComposeProbe.sinks.last?.putCompletion()
            let apply = value!.interactions.accept
            value = nil; apply()
            XCTAssertEqual(output, [3]); XCTAssertFalse(hub.policy.hasExclusions)
            Probe.check = nil; ComposeProbe.reset()
        }
    }
    func testAccountChangeBeforeProviderDeliveryCannotRestoreOrdinaryContext() {
        let source = origin(), coordinator = RichEntryCoordinator()
        var value: ComposeModal? = RichTextAiComposeController(context: context, analyticsContext: source, completion: generationReceiver(context: context, analyticsContext: source, coordinator: coordinator))
        prompt("hello"); value?.interactions.accept()
        hub.policy.setOwner(Account())
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        ComposeProbe.sinks[0].putNext([8]); ComposeProbe.sinks[0].putCompletion()
        let apply = value!.interactions.accept
        value = nil; apply()
        XCTAssertEqual(coordinator.editor.blocks, [8]); XCTAssertFalse(source.scope?.isValid == true)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testEachProviderErrorRestoresGenerateAndShowsCategoricalFeedback() {
        for (error, expected): (TranslationError, String) in [(.limitExceeded, "limit"), (.textIsEmpty, "empty"), (.textTooLong, "long"), (.generic, "error"), (.invalidMessageId, "error"), (.invalidLanguage, "error"), (.tryAlternative, "error")] {
            Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
            let value = RichTextAiComposeController(context: context, analyticsContext: origin(-1), completion: { _ in XCTFail() })
            prompt("hello"); value.interactions.accept(); ComposeProbe.sinks.last?.putError(error)
            XCTAssertEqual(ComposeProbe.errors.last, expected)
            XCTAssertFalse(ComposeProbe.state.isProcessing); XCTAssertNil(ComposeProbe.state.result)
            XCTAssertTrue(value.interactions.button.userInteractionEnabled)
            XCTAssertEqual(value.interactions.button.text, "Generate")
        }
    }
    func testDisposalCancelsProviderAndDisabledCollectionKeepsFunctionality() {
        hub.policy.isEnabled = false
        var output: InstantPage?
        var value: ComposeModal? = RichTextAiComposeController(context: context, analyticsContext: origin(), completion: { output = $0 })
        prompt("hello"); value?.interactions.accept()
        let sink = ComposeProbe.sinks[0]
        value = nil
        XCTAssertEqual(ComposeProbe.disposals, 1)
        sink.putNext([9]); sink.putCompletion()
        XCTAssertNil(output); XCTAssertNil(ComposeProbe.state.result)
        XCTAssertFalse(hub.policy.hasExclusions)
        let next = RichTextAiComposeController(context: context, completion: { output = $0 })
        prompt("new"); next.interactions.accept(); ComposeProbe.sinks.last?.putNext([6]); ComposeProbe.sinks.last?.putCompletion()
        next.interactions.accept(); XCTAssertEqual(output, [6])
    }
}
