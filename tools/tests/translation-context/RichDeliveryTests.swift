protocol MessageAttribute {}
extension TextEntitiesMessageAttribute: MessageAttribute {}
struct RichTextMessageAttribute: MessageAttribute { let instantPage: [Int]; let fullInstantPage: [Int]? }
struct NotificationInfoMessageAttribute: MessageAttribute { enum Flag { case muted }; let flags: [Flag] }
struct OutgoingScheduleInfoMessageAttribute: MessageAttribute { let scheduleTime: Int32; let repeatPeriod: Int32? }
let scheduleWhenOnlineTimestamp: Int32 = 2_147_483_647
extension ChatInteraction { struct Schedule { let date: Date; var repeatPeriod: Int32? = nil } }
enum RichSendComposed { case rich([Int]), plain(String, [Int]), empty }
final class RichSendEditor { var outgoing = [1]; func outgoingBlocks() -> [Int] { Probe.check?(); return outgoing } }
final class RichSendCoordinator { let editor = RichSendEditor(); let pickedMedia: [Int: Int] = [:] }
func richTextOutgoingHasContent(_ outgoing: [Int]) -> Bool { Probe.check?(); return !outgoing.isEmpty }
func composeRichMessage(from outgoing: [Int], media: [Int: Int]) -> RichSendComposed { Probe.check?(); return RichSendProbe.composed }
func richTextPlainPreview(from page: [Int]) -> (String, [Int]) { Probe.check?(); return RichSendProbe.preview }
final class RichSendNativeModal {
    enum Animation { case common, noMorph }
    func close(animationType: Animation) { Probe.check?(); RichSendProbe.closes += 1 }
}
final class RichSendModal { let modal: RichSendNativeModal? = RichSendNativeModal() }
struct RichSendHarness {
    let modal: RichSendModal
    let deliver: (String, [MessageAttribute], Bool, ChatInteraction.Schedule?) -> Void
    let perform: (Bool, ChatInteraction.Schedule?) -> Void
    let discard: () -> Bool
    let close: () -> Void
    let state: () -> [Bool]
}
func makeRichSendHarness(context: Context, analyticsContext: AnalyticsContext, coordinator: RichSendCoordinator, isEditing: Bool = false, onDeleteMessage: (() -> Void)? = nil, requestScheduleDate: ((@escaping (Date, Int32?) -> Void) -> Void)? = nil) -> RichSendHarness {
    var didSend = false, isClosed = false, discardPremiumFormatting = false
    var close: (() -> Void)?
    let modalController = RichSendModal()
    let contentNeedsPremium = { Probe.check?(); return RichSendProbe.needsPremium }
    let showPremiumFormatting = { Probe.check?(); RichSendProbe.premiums += 1 }
    let send: (String, [MessageAttribute]) -> Void = { text, attributes in Probe.check?(); RichSendProbe.sends.append((text, attributes)) }
__RICH_CLOSE__
__RICH_DISCARD__
__RICH_DELIVER__
__RICH_PERFORM__
    return RichSendHarness(modal: modalController, deliver: deliver, perform: performSend, discard: confirmDiscardIfNeeded, close: close!, state: { [didSend, isClosed, discardPremiumFormatting] })
}
extension Strings {
    var mediaSenderDiscardChangesHeader: String { "discard" }
    var mediaSenderDiscardChangesText: String { "changes" }
    var mediaSenderDiscardChangesOK: String { "ok" }
    var richTextEditorWindowEmptyMessage: String { "empty" }
    var richTextEditorWindowEditWithoutFormatting: String { "edit" }
    var richTextEditorWindowSendWithoutFormatting: String { "send" }
    var richTextEditorWindowRichFormattingRequiresPremium: String { "premium" }
    var richTextEditorWindowEdit: String { "edit" }
    var richTextEditorWindowSend: String { "send" }
    var richTextEditorWindowRemoveFormatting: String { "remove" }
}
func richSendAlert(for window: Int, header: String, information: String, ok: String, option: String, optionIsSelected: Bool, successHandler: @escaping (ConfirmResult) -> Void, onDeinit: @escaping () -> Void) {
    Probe.check?(); XCTAssertTrue(optionIsSelected); RichSendProbe.confirmations.append(successHandler); RichSendProbe.releases.append(onDeinit)
}
func richDiscardAlert(for window: Int, header: String, information: String, ok: String, successHandler: @escaping (ConfirmResult) -> Void, onDeinit: @escaping () -> Void) {
    Probe.check?(); RichSendProbe.confirmations.append(successHandler); RichSendProbe.releases.append(onDeinit)
}
func richSendToast(for window: Int, text: String) { Probe.check?(); RichSendProbe.toasts += 1 }
enum RichSendProbe {
    static var composed = RichSendComposed.rich([1])
    static var preview: (String, [Int]) = ("plain", [2])
    static var needsPremium = true
    static var closes = 0, premiums = 0, toasts = 0
    static var sends: [(String, [MessageAttribute])] = []
    static var confirmations: [(ConfirmResult) -> Void] = []
    static var releases: [() -> Void] = []
    static func reset() {
        confirmations = []; releases.forEach { $0() }; releases = []; closes = 0; premiums = 0; toasts = 0; sends = []
        composed = .rich([1]); preview = ("plain", [2]); needsPremium = true
    }
}
final class RichDeliveryTests: XCTestCase {
    var context: Context!
    var hub: Analytics { Analytics.shared }
    override func setUp() { Probe.check = nil; RichSendProbe.reset(); Analytics.shared = Analytics(); context = Context(); hub.policy.setOwner(context.engine.account); hub.policy.isEnabled = true; EditorProbe.premium = false }
    override func tearDown() { Probe.check = nil; RichSendProbe.reset(); EditorProbe.premium = false }
    func origin(_ peer: PeerId = 1) -> AnalyticsContext { hub.captureContext(engine: context.engine, peerId: peer) }

    func testOrdinarySilentExplicitScheduleKeepsAttributesAndClampsDate() {
        let editor = RichSendCoordinator(), source = origin()
        let host = makeRichSendHarness(context: context, analyticsContext: source, coordinator: editor)
        Probe.check = { XCTAssertFalse(self.hub.policy.hasExclusions) }
        host.deliver("text", [TextEntitiesMessageAttribute(entities: [4])], true, .init(date: Date(timeIntervalSince1970: 3_000_000_000), repeatPeriod: 60))
        XCTAssertEqual(RichSendProbe.sends.count, 1); XCTAssertEqual(RichSendProbe.sends[0].0, "text")
        let attributes = RichSendProbe.sends[0].1
        XCTAssertEqual((attributes[0] as? TextEntitiesMessageAttribute)?.entities, [4])
        XCTAssertEqual((attributes[1] as? OutgoingScheduleInfoMessageAttribute)?.scheduleTime, scheduleWhenOnlineTimestamp)
        XCTAssertEqual((attributes[1] as? OutgoingScheduleInfoMessageAttribute)?.repeatPeriod, 60)
        XCTAssertNotNil(attributes[2] as? NotificationInfoMessageAttribute); XCTAssertEqual(host.state(), [true, true, false])
    }

    func testDelayedScheduleRevalidatesPrivateRevokedAndChangedAccountOrigins() {
        for mode in 0..<3 {
            setUp()
            let source = origin(mode == 0 ? -1 : 1), editor = RichSendCoordinator()
            var selected: ((Date, Int32?) -> Void)?
            let host = makeRichSendHarness(context: context, analyticsContext: source, coordinator: editor, requestScheduleDate: { callback in Probe.check?(); selected = callback })
            host.deliver("text", [], false, nil)
            if mode == 1 { source.scope?.exclude() }
            if mode == 2 { hub.policy.setOwner(Account()) }
            Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
            selected?(Date(timeIntervalSince1970: 100), 30)
            XCTAssertEqual(RichSendProbe.sends.count, 1)
            XCTAssertEqual((RichSendProbe.sends[0].1.first as? OutgoingScheduleInfoMessageAttribute)?.repeatPeriod, 30)
            tearDown()
        }
    }

    func testDuplicateOrPostCloseScheduleDoesNotSendAgain() {
        for closeFirst in [false, true] {
            setUp()
            let editor = RichSendCoordinator(); var selected: ((Date, Int32?) -> Void)?
            let host = makeRichSendHarness(context: context, analyticsContext: origin(), coordinator: editor, requestScheduleDate: { selected = $0 })
            host.deliver("text", [], false, nil)
            if closeFirst { host.close() }
            selected?(Date(), nil); selected?(Date(), nil); host.perform(false, nil)
            XCTAssertEqual(RichSendProbe.sends.count, closeFirst ? 0 : 1)
            tearDown()
        }
    }

    func testPrivateDiscardHoldsDialogLifetimeAndClosesOnce() {
        let editor = RichSendCoordinator()
        let host = makeRichSendHarness(context: context, analyticsContext: origin(-1), coordinator: editor)
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        XCTAssertFalse(host.discard()); XCTAssertTrue(hub.policy.hasExclusions)
        RichSendProbe.confirmations[0](.basic); RichSendProbe.confirmations[0](.basic)
        XCTAssertEqual(host.state(), [false, true, true]); XCTAssertEqual(RichSendProbe.closes, 1)
        RichSendProbe.reset(); XCTAssertFalse(hub.policy.hasExclusions)
    }

    func testDiscardWithoutPremiumContentDoesNotOpenDialog() {
        RichSendProbe.needsPremium = false
        let editor = RichSendCoordinator()
        let host = makeRichSendHarness(context: context, analyticsContext: origin(), coordinator: editor)
        XCTAssertTrue(host.discard()); XCTAssertTrue(RichSendProbe.confirmations.isEmpty); XCTAssertEqual(host.state(), [false, false, false])
    }

    func testPrivateRemoveFormattingConfirmationPreservesTextAndEntities() {
        let editor = RichSendCoordinator(), source = origin(-1)
        let host = makeRichSendHarness(context: context, analyticsContext: source, coordinator: editor)
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        host.perform(false, nil); XCTAssertTrue(hub.policy.hasExclusions)
        RichSendProbe.confirmations[0](.thrid); RichSendProbe.confirmations[0](.thrid)
        XCTAssertEqual(RichSendProbe.sends.count, 1); XCTAssertEqual(RichSendProbe.sends[0].0, "plain")
        XCTAssertEqual((RichSendProbe.sends[0].1[0] as? TextEntitiesMessageAttribute)?.entities, [2])
        RichSendProbe.reset(); XCTAssertFalse(hub.policy.hasExclusions)
    }

    func testPremiumChoiceAndEmptyFormattingRemovalDoNotSend() {
        let editor = RichSendCoordinator()
        let retained = makeRichSendHarness(context: context, analyticsContext: origin(), coordinator: editor)
        retained.perform(false, nil); RichSendProbe.confirmations[0](.basic)
        XCTAssertEqual(RichSendProbe.premiums, 1); XCTAssertTrue(RichSendProbe.sends.isEmpty)
        RichSendProbe.preview = (" \n", [])
        RichSendProbe.confirmations[0](.thrid); XCTAssertTrue(RichSendProbe.sends.isEmpty)
    }

    func testClosedEditorIgnoresFormattingConfirmation() {
        let editor = RichSendCoordinator()
        let host = makeRichSendHarness(context: context, analyticsContext: origin(), coordinator: editor)
        host.perform(false, nil); host.close(); RichSendProbe.confirmations[0](.thrid)
        XCTAssertTrue(RichSendProbe.sends.isEmpty)
    }

    func testPremiumRichAndPlainAndEmptyBehaviorsWithCollectionDisabled() {
        for mode in 0..<3 {
            setUp(); hub.policy.isEnabled = false; EditorProbe.premium = true
            RichSendProbe.composed = mode == 0 ? .rich([1]) : mode == 1 ? .plain("plain", [3]) : .empty
            let editor = RichSendCoordinator()
            let retained = makeRichSendHarness(context: context, analyticsContext: origin(), coordinator: editor)
            retained.perform(false, nil)
            XCTAssertEqual(RichSendProbe.sends.count, mode == 2 ? 0 : 1); XCTAssertEqual(RichSendProbe.closes, 1)
            if mode == 0 { XCTAssertNotNil(RichSendProbe.sends[0].1.first as? RichTextMessageAttribute) }
            tearDown()
        }
    }

    func testEmptyEditingDeletesAndEmptyNewMessageShowsFeedback() {
        for editing in [false, true] {
            setUp()
            let editor = RichSendCoordinator(); editor.editor.outgoing = []; var deletes = 0
            let host = makeRichSendHarness(context: context, analyticsContext: origin(-1), coordinator: editor, isEditing: editing, onDeleteMessage: { Probe.check?(); deletes += 1 })
            Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
            host.perform(false, nil); host.perform(false, nil)
            XCTAssertEqual(deletes, editing ? 1 : 0); XCTAssertEqual(RichSendProbe.toasts, editing ? 0 : 2)
            XCTAssertTrue(RichSendProbe.sends.isEmpty); tearDown()
        }
    }
}

final class RichScheduleInteraction {
    enum Mode { case scheduled, history }
    struct Peer { let id: PeerId }
    typealias Schedule = ChatInteraction.Schedule
    let interactionContext: Context
    var mode = Mode.scheduled
    var peer: Peer? = Peer(id: 2)
    init(_ context: Context) { interactionContext = context }
    func captureAnalyticsContext(inherited: AnalyticsContext) -> AnalyticsContext { Analytics.shared.captureContext(engine: interactionContext.engine, peerId: peer?.id ?? 0, inherited: inherited) }
}
struct RichScheduleItem {}
enum RichScheduleMode { case schedule(PeerId) }
struct RichScheduleController { let origin: AnalyticsContext; let selected: (Date, Int32?) -> Void }
enum RichScheduleProbe {
    static var controller: RichScheduleController?
    static var menuOrigin: AnalyticsContext?
    static var send: ((Bool, ChatInteraction.Schedule?) -> Void)?
}
func chatDateSelector(context: Context, mode: RichScheduleMode, analyticsContext: AnalyticsContext, selectedAt: @escaping (Date, Int32?) -> Void) -> RichScheduleController {
    Probe.check?(); if case let .schedule(id) = mode { XCTAssertEqual(id, 2) }
    return RichScheduleController(origin: analyticsContext, selected: selectedAt)
}
func showModal(with controller: RichScheduleController, for window: Int) { Probe.check?(); RichScheduleProbe.controller = controller }
func sendMessageMenuItems(chatInteraction: RichScheduleInteraction, analyticsContext: AnalyticsContext, send: @escaping (Bool, RichScheduleInteraction.Schedule?) -> Void) -> [RichScheduleItem]? {
    Probe.check?(); RichScheduleProbe.menuOrigin = analyticsContext; RichScheduleProbe.send = send; return [RichScheduleItem()]
}
__RICH_SCHEDULE_REQUEST__
__RICH_SEND_MENU__
extension RichDeliveryTests {
    func testScheduledChatFactoryKeepsOriginalAndGuardsDeferredSelection() {
        let interaction = RichScheduleInteraction(context), source = origin()
        let factory = richTextScheduleRequest(chatInteraction: interaction, analyticsContext: source)!
        var selected = 0
        factory { date, period in Probe.check?(); XCTAssertEqual(date.timeIntervalSince1970, 100); XCTAssertEqual(period, 20); selected += 1 }
        XCTAssertTrue(RichScheduleProbe.controller?.origin.scope === source.scope)
        source.scope?.exclude(); Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        RichScheduleProbe.controller?.selected(Date(timeIntervalSince1970: 100), 20)
        XCTAssertEqual(selected, 1); RichScheduleProbe.controller = nil
    }

    func testPrivateScheduledConstructionAndUnavailableModes() {
        let interaction = RichScheduleInteraction(context), source = origin(-1)
        Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        let factory = richTextScheduleRequest(chatInteraction: interaction, analyticsContext: source)!
        factory { _, _ in Probe.check?() }
        XCTAssertTrue(RichScheduleProbe.controller!.origin.isExcluded)
        RichScheduleProbe.controller?.selected(Date(), nil); RichScheduleProbe.controller = nil
        interaction.mode = .history; XCTAssertNil(richTextScheduleRequest(chatInteraction: interaction, analyticsContext: source))
        interaction.mode = .scheduled; interaction.peer = nil; XCTAssertNil(richTextScheduleRequest(chatInteraction: interaction, analyticsContext: source))
    }

    func testSendMenuPassesOriginalAndRevalidatesAfterAccountChange() {
        let interaction = RichScheduleInteraction(context), source = origin()
        let menu = richTextSendMenuItems(chatInteraction: interaction, analyticsContext: source)
        var sent = 0
        XCTAssertEqual(menu { silent, schedule in Probe.check?(); XCTAssertTrue(silent); XCTAssertEqual(schedule?.repeatPeriod, 10); sent += 1 }?.count, 1)
        XCTAssertTrue(RichScheduleProbe.menuOrigin?.scope === source.scope)
        hub.policy.setOwner(Account()); Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        RichScheduleProbe.send?(true, .init(date: Date(), repeatPeriod: 10))
        XCTAssertEqual(sent, 1); RichScheduleProbe.send = nil; RichScheduleProbe.menuOrigin = nil
    }

    func testMenuFactoryDoesNotRetainReleasedInteraction() {
        var interaction: RichScheduleInteraction? = RichScheduleInteraction(context)
        let menu = richTextSendMenuItems(chatInteraction: interaction!, analyticsContext: origin())
        interaction = nil; XCTAssertNil(menu { _, _ in XCTFail("unexpected selection") })
    }
}
