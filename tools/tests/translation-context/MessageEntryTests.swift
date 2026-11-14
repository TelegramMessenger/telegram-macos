typealias MessageTextEntity = Int
typealias InstantPage = [Int]
typealias InputDataModalController = Modal
extension Context { var concrete: Context { self } }
__MESSAGE_SOURCE__
struct ChatHistoryUIHooks {
    static var shared = makeMessageHooks()
    var executeLink: (Any) -> Void = { _ in }
    var executeLinkWithContext: ((Any, AnalyticsContext) -> Void)?
__MESSAGE_HOOKS__
}
struct Message { var id: MessageId; var containsSecretMedia = false }
final class ChatInteraction {
    let interactionContext: Context
    var peerId: PeerId = 1
    var inheritedAnalyticsContext: AnalyticsContext?
    var composerExcluded = false
    var inputText = NSAttributedString(string: "")
    var sentInputs: [NSAttributedString] = []
    var peerIsSecret = false
    var mutationCheck: (() -> Void)?
    var tones: [TranslationTone] = []
    var languages: [String] = []
    var paywalls = 0
    init(_ context: Context) { interactionContext = context }
    func captureAnalyticsContext(sourcePeerId: PeerId? = nil) -> AnalyticsContext {
        guard !composerExcluded else { return Analytics.shared.unresolvedContext() }
        let origin = Analytics.shared.captureContext(engine: interactionContext.engine, peerId: peerId, inherited: inheritedAnalyticsContext)
        return sourcePeerId.map { origin.restricting(peerId: $0) } ?? origin
    }
    func captureAnalyticsContext(inherited: AnalyticsContext) -> AnalyticsContext {
        let current = captureAnalyticsContext()
        guard !current.isExcluded, current.scope?.isValid == true else { return current }
        return Analytics.shared.captureContext(engine: interactionContext.engine, peerId: peerId, inherited: inherited)
    }
    func setTranslateTone(_ tone: TranslationTone) { Probe.check?(); tones.append(tone) }
    func translateTo(_ language: String) { Probe.check?(); languages.append(language) }
    func enableTranslatePaywall() { Probe.check?(); paywalls += 1 }
}
__MESSAGE_PRIVACY__
final class MenuData {
    var message: Message
    let chatInteraction: ChatInteraction
    init(_ message: Message, _ interaction: ChatInteraction) { self.message = message; chatInteraction = interaction }
}
struct RichAttribute { let instantPage: InstantPage = [7, 8] }
enum MessageEntryProbe {
    static var arguments: (String?, String, String, [Int], Bool, PeerId?, Bool, InstantPage?, Bool)?
    static var tone: ((TranslationTone) -> Void)?
    static var entire: (() -> Void)?
    static var origin: AnalyticsContext?
    static var fallback = ""
    static func reset() { arguments = nil; tone = nil; entire = nil; origin = nil; fallback = "" }
}
func TranslateModalController(context: Context, from: String?, toLang: String, text: String, entities: [Int] = [], canBreak: Bool = true, messageId: MessageId? = nil, isRichMessage: Bool = false, richMessagePage: InstantPage? = nil, dismissOnly: Bool = false, onToneChanged: ((TranslationTone) -> Void)? = nil, translateEntireChat: (() -> Void)? = nil, analyticsContext: AnalyticsContext) -> Modal {
    Probe.check?()
    MessageEntryProbe.arguments = (from, toLang, text, entities, canBreak, messageId?.peerId, isRichMessage, richMessagePage, dismissOnly)
    MessageEntryProbe.tone = onToneChanged; MessageEntryProbe.entire = translateEntireChat; MessageEntryProbe.origin = analyticsContext
    return makeTranslation(context, messageId: messageId, analyticsContext: analyticsContext, dismissOnly: dismissOnly, onToneChanged: onToneChanged, translateEntireChat: translateEntireChat)
}
func legacyTranslation(_ route: String, _ context: Context, _ tone: ((TranslationTone) -> Void)?, _ entire: (() -> Void)?) -> Modal {
    Probe.check?(); MessageEntryProbe.fallback = route
    MessageEntryProbe.tone = tone; MessageEntryProbe.entire = entire
    return makeTranslation(context, analyticsContext: Analytics.shared.unresolvedContext(), dismissOnly: true, onToneChanged: tone, translateEntireChat: entire)
}
func makeMessageHooks() -> ChatHistoryUIHooks {
    ChatHistoryUIHooks(
        makeRichMessageTranslateModal: { c, _, _, _, _, _, _, t, e in legacyTranslation("rich", c, t, e) },
        makePollTranslateModal: { c, _, _, _, _, _, t, e in legacyTranslation("poll", c, t, e) },
        makeMessageTranslateModal: { c, _, _, _, _, _, t, e in legacyTranslation("plain", c, t, e) },
        makeSelectedTextTranslateModal: { c, _, _, _, _, t, e in legacyTranslation("selection", c, t, e) },
        makeTranscriptionTranslateModal: { c, _, _, _, _, t, e in legacyTranslation("transcription", c, t, e) }
    )
}
func installMessageBridge() {
    var hooks = makeMessageHooks()
__MESSAGE_BRIDGE__
    ChatHistoryUIHooks.shared = hooks
}
func menuAction(_ route: Int, data: MenuData) -> () -> Void {
    let message = data.message
    let chatInteraction = data.chatInteraction
    let context = chatInteraction.interactionContext
    let messageId = message.id
    let richAttribute = RichAttribute()
    let text = "message"
    let entities = [3, 4]
    let language: String? = "en"
__MESSAGE_CAPTURE__
    switch route {
__MESSAGE_ACTIONS__
    default: fatalError("unknown route")
    }
}
final class MessageEntryTests: XCTestCase {
    var context: Context!
    var interaction: ChatInteraction!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Analytics.shared = Analytics(); context = Context(); interaction = ChatInteraction(context)
        hub.policy.setOwner(context.engine.account); hub.policy.isEnabled = true
        Probe.check = nil; EntryProbe.presented = nil; MessageEntryProbe.reset(); installMessageBridge()
    }
    override func tearDown() {
        Probe.check = nil; EntryProbe.presented = nil; MessageEntryProbe.reset()
        ChatHistoryUIHooks.shared = makeMessageHooks()
        super.tearDown()
    }
    func origin() -> AnalyticsContext { hub.captureContext(engine: context.engine, peerId: 1) }
    func data(_ id: PeerId = 2, secret: Bool = false) -> MenuData { MenuData(Message(id: MessageId(peerId: id), containsSecretMedia: secret), interaction) }
    func excluded() { Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) } }
    func releaseModal() { EntryProbe.presented = nil; XCTAssertFalse(hub.policy.hasExclusions) }
    func testAllFiveRoutesPreserveOptionsAndOrdinaryScope() {
        let source = origin(); interaction.inheritedAnalyticsContext = source
        for route in 0..<5 {
            Probe.check = { XCTAssertFalse(self.hub.policy.hasExclusions) }
            menuAction(route, data: data())()
            let args = MessageEntryProbe.arguments!
            XCTAssertEqual(args.0, "en"); XCTAssertEqual(args.1, "fr"); XCTAssertEqual(args.2, "message")
            XCTAssertEqual(args.3, route == 4 ? [] : [3, 4]); XCTAssertEqual(args.4, route != 1)
            XCTAssertEqual(args.5, route == 3 ? nil : 2); XCTAssertEqual(args.6, route == 0)
            XCTAssertEqual(args.7, route == 0 ? [7, 8] : nil); XCTAssertTrue(args.8)
            XCTAssertTrue(MessageEntryProbe.origin?.scope === source.scope)
            XCTAssertTrue(EntryProbe.presented?.analyticsContext?.scope === source.scope)
            let tone = MessageEntryProbe.tone; let entire = MessageEntryProbe.entire
            releaseModal(); tone?(.formal); entire?()
        }
        XCTAssertEqual(interaction.paywalls, 5)
        XCTAssertEqual(interaction.tones, Array(repeating: .formal, count: 5))
        XCTAssertEqual(interaction.languages, Array(repeating: "fr", count: 5))
    }
    func testAllRoutesRejectSecretMediaAndNamespaceIncludingSelectionWithoutMessageId() {
        for secret in [false, true] {
            for route in 0..<5 {
                let item = data(secret ? 2 : -2, secret: secret)
                let action = menuAction(route, data: item)
                item.message = Message(id: MessageId(peerId: 2))
                excluded(); action()
                XCTAssertTrue(MessageEntryProbe.origin!.isExcluded)
                let tone = MessageEntryProbe.tone; let entire = MessageEntryProbe.entire
                releaseModal(); tone?(.formal); entire?()
                XCTAssertFalse(hub.policy.hasExclusions)
            }
        }
        XCTAssertEqual(interaction.paywalls, 10); XCTAssertEqual(interaction.tones.count, 10)
    }
    func testSecretMediaDiscoveredAfterMenuCaptureRevokesExistingScope() {
        let source = origin(); interaction.inheritedAnalyticsContext = source
        let item = data(); let action = menuAction(3, data: item)
        item.message.containsSecretMedia = true
        excluded(); action()
        XCTAssertTrue(source.scope!.isExcluded); XCTAssertTrue(MessageEntryProbe.origin!.isExcluded)
        releaseModal()
        item.message.containsSecretMedia = false
        interaction.inheritedAnalyticsContext = origin()
        action()
        XCTAssertTrue(MessageEntryProbe.origin!.isExcluded)
    }
    func testComposerBecomesExcludedBeforeMenuAction() {
        let action = menuAction(2, data: data())
        interaction.composerExcluded = true; excluded(); action()
        XCTAssertTrue(MessageEntryProbe.origin!.isExcluded)
    }
    func testRevocationBeforeActionCannotBeReplacedWithFreshScope() {
        let source = origin(); interaction.inheritedAnalyticsContext = source
        let action = menuAction(0, data: data())
        source.scope?.exclude(); interaction.inheritedAnalyticsContext = origin()
        excluded(); action()
        XCTAssertTrue(MessageEntryProbe.origin!.isExcluded)
    }
    func testAccountChangeBeforeActionRejectsCapturedOrigin() {
        let action = menuAction(1, data: data())
        hub.policy.setOwner(Account()); excluded(); action()
        XCTAssertTrue(MessageEntryProbe.origin?.scope?.isValid != true)
    }
    func testRetainedCallbacksRevalidateAccountAfterModalRelease() {
        menuAction(4, data: data())()
        let tone = MessageEntryProbe.tone; let entire = MessageEntryProbe.entire
        releaseModal(); hub.policy.setOwner(Account()); excluded()
        tone?(.formal); entire?()
        XCTAssertEqual(interaction.tones, [.formal]); XCTAssertEqual(interaction.languages, ["fr"])
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testLegacyFallbackRoutesKeepDelayedCallbacksExcluded() {
        ChatHistoryUIHooks.shared = makeMessageHooks()
        for (route, name) in ["rich", "poll", "plain", "selection", "transcription"].enumerated() {
            excluded(); menuAction(route, data: data(2, secret: true))()
            XCTAssertEqual(MessageEntryProbe.fallback, name)
            let tone = MessageEntryProbe.tone; let entire = MessageEntryProbe.entire
            releaseModal(); tone?(.formal); entire?()
            XCTAssertFalse(hub.policy.hasExclusions)
        }
        XCTAssertEqual(interaction.paywalls, 5); XCTAssertEqual(interaction.tones.count, 5)
    }
    func testDisabledCollectionStillOpensAllRoutesAndRunsActions() {
        hub.policy.isEnabled = false
        for route in 0..<5 {
            excluded(); menuAction(route, data: data())()
            XCTAssertTrue(MessageEntryProbe.origin?.scope?.isValid != true)
            MessageEntryProbe.tone?(.formal); MessageEntryProbe.entire?(); releaseModal()
        }
        XCTAssertEqual(interaction.paywalls, 5); XCTAssertEqual(interaction.tones.count, 5)
    }
}
