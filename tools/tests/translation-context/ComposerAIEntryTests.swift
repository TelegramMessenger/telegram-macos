struct ChatInputUIHooks {
    static var shared = ChatInputUIHooks()
    var makeTranslateModal: (Context, String?, String, String, @escaping (NSAttributedString) -> Void, @escaping (NSAttributedString) -> Void) -> Modal = { context, _, _, _, use, send in
        makeTranslation(context, onUse: use, onSend: send)
    }
__COMPOSER_HOOK__
__RICH_TRANSLATE_HOOK__
}
extension Translate { static func detectLanguage(for text: String) -> String? { Probe.check?(); return "en" } }
struct AttachPresentation {
    struct Input { let inputText: String }
    struct Peer { let isSecretChat: Bool }
    let effectiveInput: Input
    let peer: Peer?
}
extension ChatInteraction {
    var presentation: AttachPresentation { .init(effectiveInput: .init(inputText: inputText.string), peer: .init(isSecretChat: peerIsSecret)) }
    func updateInput(with text: NSAttributedString) {
        mutationCheck?(); Probe.check?(); inputText = text
        composerExcluded = text.length > 0 && text.attribute(chatInputAnalyticsExcludedAttribute, at: 0, effectiveRange: nil) != nil
    }
    func sendMessage(_ fromInput: Bool, _ a: Int?, _ b: Int?) {
        mutationCheck?(); Probe.check?(); XCTAssertTrue(fromInput); XCTAssertNil(a); XCTAssertNil(b); sentInputs.append(inputText)
    }
}
func TranslateModalController(context: Context, from: String?, toLang: String, text: String, onUse: @escaping (NSAttributedString) -> Void, onSend: @escaping (NSAttributedString) -> Void, analyticsContext: AnalyticsContext) -> Modal {
    Probe.check?(); EntryProbe.arguments = [from, toLang, text]
    var state = State(); state.translated = "result"
    return makeTranslation(context, analyticsContext: analyticsContext, initialState: state, onUse: onUse, onSend: onSend)
}
func showModal(with modal: Modal, for window: Int, morphSource: @escaping () -> Int?) { Probe.check?(); XCTAssertEqual(morphSource(), 1); EntryProbe.presented = modal }
final class AttachHost {
    let chatInteraction: ChatInteraction
    var aiButton: Int? = 1
    init(_ interaction: ChatInteraction) { chatInteraction = interaction }
__COMPOSER_ACTION__
}
func installComposerBridge() {
    var hooks = ChatInputUIHooks()
__COMPOSER_BRIDGE__
    ChatInputUIHooks.shared = hooks
}
enum Namespaces { enum Peer { static let SecretChat = 1 } }
extension Int64 { var namespace: Int { self < 0 ? 1 : 0 } }
final class CaptionTextView {
    var context: Context?
    var isSecretChat = false
    var analyticsContextProvider: (() -> AnalyticsContext)?
}
final class CaptionView { let textView = CaptionTextView() }
final class CaptionHost {
    let genericView = CaptionView()
    let context: Context
    let chatInteraction: ChatInteraction
    var analyticsContext: AnalyticsContext?
    init(_ context: Context, _ interaction: ChatInteraction, _ origin: AnalyticsContext?) { self.context = context; chatInteraction = interaction; analyticsContext = origin }
    func bind() {
__CAPTION_BINDING__
    }
}
final class ComposerAIEntryTests: XCTestCase {
    var context: Context!
    var interaction: ChatInteraction!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Probe.check = nil; EntryProbe.presented = nil; EntryProbe.arguments = []
        Analytics.shared = Analytics(); context = Context(); interaction = ChatInteraction(context)
        interaction.inputText = NSAttributedString(string: "input")
        hub.policy.setOwner(context.engine.account); hub.policy.isEnabled = true; installComposerBridge()
    }
    override func tearDown() { Probe.check = nil; EntryProbe.presented = nil; ChatInputUIHooks.shared = ChatInputUIHooks(); super.tearDown() }
    func origin() -> AnalyticsContext { hub.captureContext(engine: context.engine, peerId: 1) }
    func excluded() { Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) } }
    func marked(_ text: NSAttributedString) -> Bool { text.length > 0 && text.attribute(chatInputAnalyticsExcludedAttribute, at: 0, effectiveRange: nil) != nil }
    func testOrdinaryApplyAndSendPreserveArgumentsAndScope() {
        let source = origin(); interaction.inheritedAnalyticsContext = source
        let host = AttachHost(interaction)
        Probe.check = { XCTAssertFalse(self.hub.policy.hasExclusions) }
        host.runAITranslate()
        XCTAssertEqual(EntryProbe.arguments, ["en", "fr", "input"])
        XCTAssertTrue(EntryProbe.presented!.analyticsContext!.scope === source.scope)
        EntryProbe.presented!.interactions!.accept()
        XCTAssertEqual(interaction.inputText.string, "result"); XCTAssertFalse(marked(interaction.inputText)); XCTAssertTrue(interaction.sentInputs.isEmpty)
        EntryProbe.presented!.interactions!.extraAction?()
        XCTAssertEqual(interaction.sentInputs.map(\.string), ["result"])
        XCTAssertNotNil(interaction.inputText.attribute(NSAttributedString.Key("testFormatting"), at: 0, effectiveRange: nil))
    }
    func testSecretOrMarkedSourceStaysMarkedAfterParentAndModalRelease() {
        for useMarker in [false, true] {
            interaction.peerId = useMarker ? 1 : -1
            interaction.composerExcluded = useMarker
            if useMarker { interaction.inputText = chatInputTextExcludingAnalytics(NSAttributedString(string: "input")) }
            excluded()
            var host: AttachHost? = AttachHost(interaction)
            host!.runAITranslate()
            let apply = EntryProbe.presented!.interactions!.accept
            let send = EntryProbe.presented!.interactions!.extraAction!
            host = nil; EntryProbe.presented = nil
            interaction.peerId = 1; interaction.composerExcluded = false
            interaction.inputText = NSAttributedString(string: "replacement")
            XCTAssertFalse(hub.policy.hasExclusions)
            apply(); XCTAssertTrue(marked(interaction.inputText))
            send(); XCTAssertTrue(marked(interaction.sentInputs.last!))
            XCTAssertFalse(hub.policy.hasExclusions)
        }
    }
    func testReceivingComposerAndAccountChangesMarkSendResult() {
        for changeAccount in [false, true] {
            interaction.composerExcluded = false
            interaction.inputText = NSAttributedString(string: "input")
            AttachHost(interaction).runAITranslate()
            let send = EntryProbe.presented!.interactions!.extraAction!
            EntryProbe.presented = nil
            if changeAccount { hub.policy.setOwner(Account()) } else { interaction.composerExcluded = true }
            let policy = hub.policy
            interaction.mutationCheck = { XCTAssertTrue(policy.hasExclusions) }
            send()
            XCTAssertTrue(marked(interaction.sentInputs.last!)); XCTAssertFalse(hub.policy.hasExclusions)
            interaction.mutationCheck = nil
        }
    }
    func testRevocationCannotBeReplacedByFreshComposerGrant() {
        let source = origin(); interaction.inheritedAnalyticsContext = source
        AttachHost(interaction).runAITranslate()
        let apply = EntryProbe.presented!.interactions!.accept; EntryProbe.presented = nil
        source.scope?.exclude(); interaction.inheritedAnalyticsContext = origin()
        excluded(); apply(); XCTAssertTrue(marked(interaction.inputText))
    }
    func testEmptyInputAndReleasedInteractionDoNotSend() {
        interaction.inputText = NSAttributedString(string: "")
        AttachHost(interaction).runAITranslate(); XCTAssertNil(EntryProbe.presented)
        interaction.inputText = NSAttributedString(string: "input")
        AttachHost(interaction).runAITranslate()
        let send = EntryProbe.presented!.interactions!.extraAction!
        weak var weakInteraction = interaction
        interaction = nil; EntryProbe.presented = nil
        XCTAssertNil(weakInteraction); send()
    }
    func testLegacyHookStillMarksPrivateReturnedText() {
        var returned: ((NSAttributedString) -> Void)?
        var hooks = ChatInputUIHooks()
        hooks.makeTranslateModal = { context, _, _, _, use, send in Probe.check?(); returned = send; return makeTranslation(context, onUse: use, onSend: send) }
        ChatInputUIHooks.shared = hooks
        interaction.peerId = -1; excluded(); AttachHost(interaction).runAITranslate(); EntryProbe.presented = nil
        returned?(NSAttributedString(string: "legacy"))
        XCTAssertEqual(interaction.sentInputs.last?.string, "legacy"); XCTAssertTrue(marked(interaction.sentInputs.last!))
    }
    func testDisabledAIStillAppliesAndSends() {
        hub.policy.isEnabled = false; excluded(); AttachHost(interaction).runAITranslate()
        EntryProbe.presented!.interactions!.extraAction?()
        XCTAssertEqual(interaction.sentInputs.last?.string, "result"); XCTAssertTrue(marked(interaction.sentInputs.last!))
    }
    func testCaptionBindingUsesCurrentParentScopeAndFailsClosedAfterRelease() {
        let source = origin()
        var host: CaptionHost? = CaptionHost(context, interaction, source); host!.bind()
        let view = host!.genericView.textView
        XCTAssertFalse(view.isSecretChat); XCTAssertTrue(view.context === context)
        XCTAssertTrue(view.analyticsContextProvider?().scope === source.scope)
        interaction.composerExcluded = true; XCTAssertTrue(view.analyticsContextProvider!().isExcluded)
        interaction.composerExcluded = false; source.scope?.exclude(); XCTAssertTrue(view.analyticsContextProvider!().isExcluded)
        host = nil; XCTAssertTrue(view.analyticsContextProvider!().isExcluded)
    }
    func testCaptionBindingChecksSecretNamespaceAndMissingOrigin() {
        interaction.peerId = -1; interaction.peerIsSecret = false
        let host = CaptionHost(context, interaction, nil); host.bind()
        XCTAssertTrue(host.genericView.textView.isSecretChat); XCTAssertTrue(host.genericView.textView.analyticsContextProvider!().isExcluded)
        interaction.peerId = 1; interaction.peerIsSecret = true; host.bind()
        XCTAssertTrue(host.genericView.textView.isSecretChat)
    }
}
