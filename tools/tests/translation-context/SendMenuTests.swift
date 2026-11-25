__SEND_MENU_ACTION__
extension Account { var peerId: PeerId { 1 } }
struct SendMenuPeer { var id: PeerId = 2; var isSecretChat = false }
struct SendMenuPresentation {
    enum State { case normal, editing }
    struct SlowMode { var hasLocked: Bool }
    var peer: SendMenuPeer? = SendMenuPeer()
    var slowMode: SlowMode?
    var state = State.normal
    var canScheduleWhenOnline = true
    var sendPaidMessageStars: Int?
}
final class SendMenuInteraction {
    enum Mode { case history, thread, scheduled }
    typealias Schedule = ChatInteraction.Schedule
    var presentation = SendMenuPresentation()
    var mode = Mode.history
    let context: Context
    var revision = 0
    init(_ context: Context) { self.context = context }
    func captureAnalyticsContext(inherited: AnalyticsContext? = nil) -> AnalyticsContext { Analytics.shared.captureContext(engine: context.engine, peerId: presentation.peer?.id ?? 0, inherited: inherited) }
    func captureDeferredSendAction() -> ChatDeferredSendAction {
        let revision = self.revision
        return ChatDeferredSendAction { [weak self] in self?.revision == revision }
    }
}
struct SendMenuItem {
    let title: String
    let handler: () -> Void
    init(_ title: String, handler: @escaping () -> Void, itemImage: Int) { Probe.check?(); self.title = title; self.handler = handler }
}
enum SendMenuAnimation {
    case menu_mute, menu_online, menu_schedule_message
    var value: Int { 0 }
}
extension Strings {
    var chatSendWithoutSound: String { "silent" }
    var chatSendSendWhenOnline: String { "online" }
    var chatSendSetReminder: String { "reminder" }
    var chatSendScheduledMessage: String { "schedule" }
}
let scheduleWhenOnlineDate = Date(timeIntervalSince1970: Double(scheduleWhenOnlineTimestamp))
struct SendMenuDatePicker { let origin: AnalyticsContext; let selected: (Date, Int32?) -> Void }
func sendMenuDateSelector(context: Context, mode: RichScheduleMode, analyticsContext: AnalyticsContext, selectedAt: @escaping (Date, Int32?) -> Void) -> SendMenuDatePicker {
    Probe.check?(); return SendMenuDatePicker(origin: analyticsContext, selected: selectedAt)
}
func showModal(with controller: SendMenuDatePicker, for window: Int) { Probe.check?(); SendMenuProbe.picker = controller }
enum SendMenuProbe { static var picker: SendMenuDatePicker? }
__SEND_MENU_METHODS__

final class SendMenuTests: XCTestCase {
    var context: Context!
    var hub: Analytics { Analytics.shared }
    override func setUp() { Probe.check = nil; SendMenuProbe.picker = nil; Analytics.shared = Analytics(); context = Context(); hub.policy.setOwner(context.engine.account); hub.policy.isEnabled = true }
    override func tearDown() { Probe.check = nil; SendMenuProbe.picker = nil }
    func origin(_ peer: PeerId = 2) -> AnalyticsContext { hub.captureContext(engine: context.engine, peerId: peer) }
    func items(_ interaction: SendMenuInteraction, _ source: AnalyticsContext, _ send: @escaping (Bool, ChatInteraction.Schedule?) -> Void = { _, _ in }) -> [SendMenuItem] {
        sendMessageMenuItems(chatInteraction: interaction, analyticsContext: source, send: send) ?? []
    }

    func testOrdinaryMenuOptionsSilentOnlineAndScheduledArguments() {
        for kind in ["silent", "online", "schedule"] {
            let interaction = SendMenuInteraction(context), source = origin(); var calls = 0
            Probe.check = { XCTAssertFalse(self.hub.policy.hasExclusions) }
            let menu = items(interaction, source) { silent, schedule in
                Probe.check?(); calls += 1; XCTAssertEqual(silent, kind == "silent")
                if kind == "online" { XCTAssertEqual(schedule?.date, scheduleWhenOnlineDate) }
                if kind == "schedule" { XCTAssertEqual(schedule?.repeatPeriod, 30); XCTAssertEqual(schedule?.date.timeIntervalSince1970, 100) }
            }
            XCTAssertEqual(menu.map(\.title), ["silent", "online", "schedule"])
            menu.first { $0.title == kind }!.handler()
            if kind == "schedule" {
                XCTAssertTrue(SendMenuProbe.picker?.origin.scope === source.scope)
                SendMenuProbe.picker?.selected(Date(timeIntervalSince1970: 100), 30)
            }
            XCTAssertEqual(calls, 1); SendMenuProbe.picker = nil
        }
    }

    func testEveryActionRejectsInvalidatedDraftAndDuplicateCallback() {
        for kind in ["silent", "online", "schedule"] {
            for invalidate in [false, true] {
                let interaction = SendMenuInteraction(context); var calls = 0
                let menu = items(interaction, origin()) { _, _ in calls += 1 }
                let action = menu.first { $0.title == kind }!.handler
                if kind == "schedule" { action() }
                if invalidate { interaction.revision += 1 }
                if kind == "schedule" { SendMenuProbe.picker?.selected(Date(), nil); SendMenuProbe.picker?.selected(Date(), nil) }
                else { action(); action() }
                XCTAssertEqual(calls, invalidate ? 0 : 1); SendMenuProbe.picker = nil
            }
        }
    }

    func testStaleScheduleMenuCannotOpenPicker() {
        let interaction = SendMenuInteraction(context)
        let actual = items(interaction, origin()); interaction.revision += 1
        actual.last!.handler(); XCTAssertNil(SendMenuProbe.picker)
    }

    func testPrivateAndRevokedOriginsGuardDeferredActions() {
        for kind in ["silent", "online", "schedule"] {
            for mode in 0..<3 {
                setUp()
                let interaction = SendMenuInteraction(context), source = origin(mode == 0 ? -1 : 2); var calls = 0
                let menu = items(interaction, source) { _, _ in Probe.check?(); calls += 1 }
                if mode == 1 { source.scope?.exclude() }
                if mode == 2 { hub.policy.setOwner(Account()) }
                Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
                menu.first { $0.title == kind }!.handler()
                if kind == "schedule" { SendMenuProbe.picker?.selected(Date(), nil) }
                XCTAssertEqual(calls, 1); tearDown()
            }
        }
    }

    func testPeerAndComposerGatesKeepExistingMenuChoices() {
        let interaction = SendMenuInteraction(context)
        interaction.presentation.peer = nil; XCTAssertTrue(items(interaction, origin()).isEmpty)
        interaction.presentation.peer = SendMenuPeer(); interaction.presentation.state = .editing; XCTAssertTrue(items(interaction, origin()).isEmpty)
        interaction.presentation.state = .normal; interaction.presentation.slowMode = .init(hasLocked: true); XCTAssertTrue(items(interaction, origin()).isEmpty)
        interaction.presentation.slowMode = nil; interaction.presentation.sendPaidMessageStars = 10; XCTAssertEqual(items(interaction, origin()).map(\.title), ["silent"])
        interaction.presentation.sendPaidMessageStars = nil; interaction.presentation.peer?.isSecretChat = true; XCTAssertEqual(items(interaction, origin()).map(\.title), ["silent"])
        interaction.presentation.peer = .init(id: 1); XCTAssertEqual(items(interaction, origin()).map(\.title), ["reminder"])
        interaction.mode = .scheduled; XCTAssertTrue(items(interaction, origin()).isEmpty)
    }

    func testLegacySignatureDisabledCollectionAndReleasedInteraction() {
        hub.policy.isEnabled = false
        var interaction: SendMenuInteraction? = SendMenuInteraction(context); weak var weakInteraction = interaction
        var calls = 0
        let menu = sendMessageMenuItems(chatInteraction: interaction!, send: { _, _ in calls += 1 })!
        menu[0].handler(); XCTAssertEqual(calls, 1)
        let abandoned = items(interaction!, origin()) { _, _ in XCTFail("released owner") }
        interaction = nil; XCTAssertNil(weakInteraction)
        abandoned.forEach { $0.handler() }; XCTAssertNil(SendMenuProbe.picker)
    }
}

struct RichMenuMedia {
    let value: Int
    func isEqual(to other: RichMenuMedia) -> Bool { Probe.check?(); return value == other.value }
}
final class RichMenuCoordinator {
    let editor = RichSendEditor()
    var pickedMedia: [String: RichMenuMedia] = [:]
    var menu: (() -> [SendMenuItem]?)?
    func setSendContextMenu(_ items: @escaping () -> [SendMenuItem]?) { menu = items }
}
func installRichSendMenu(context: Context, analyticsContext: AnalyticsContext, coordinator: RichMenuCoordinator, sendMenuItems: @escaping (@escaping (Bool, ChatInteraction.Schedule?) -> Void) -> [SendMenuItem]?, isClosed: @escaping () -> Bool, didSend: @escaping () -> Bool, performSend: @escaping (Bool, ChatInteraction.Schedule?) -> Void) {
__RICH_MENU_BINDING__
}
extension SendMenuTests {
    func testRichMenuSnapshotRejectsTextAndMediaChangesButAllowsSameContent() {
        for mode in 0..<5 {
            let coordinator = RichMenuCoordinator(); coordinator.pickedMedia = ["media": .init(value: 1)]
            var selected: ((Bool, ChatInteraction.Schedule?) -> Void)?; var sent = 0
            installRichSendMenu(context: context, analyticsContext: origin(), coordinator: coordinator, sendMenuItems: { selected = $0; return [] }, isClosed: { false }, didSend: { false }, performSend: { _, _ in sent += 1 })
            _ = coordinator.menu?()
            switch mode {
            case 1: coordinator.editor.outgoing = [2]
            case 2: coordinator.pickedMedia["media"] = .init(value: 2)
            case 3: coordinator.pickedMedia["extra"] = .init(value: 1)
            case 4: coordinator.pickedMedia = [:]
            default: coordinator.pickedMedia["media"] = .init(value: 1)
            }
            selected?(false, nil); selected?(false, nil)
            XCTAssertEqual(sent, mode == 0 ? 1 : 0)
        }
    }

    func testRichMenuSnapshotGuardsPrivateCallbackAndClosedOrReleasedEditor() {
        for mode in 0..<3 {
            var coordinator: RichMenuCoordinator? = RichMenuCoordinator(); weak var weakCoordinator = coordinator
            var selected: ((Bool, ChatInteraction.Schedule?) -> Void)?; var sent = 0, closed = false
            Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) }
            installRichSendMenu(context: context, analyticsContext: origin(-1), coordinator: coordinator!, sendMenuItems: { selected = $0; return [] }, isClosed: { closed }, didSend: { false }, performSend: { _, _ in Probe.check?(); sent += 1 })
            _ = coordinator?.menu?()
            if mode == 1 { closed = true; XCTAssertNil(coordinator?.menu?()) }
            if mode == 2 { coordinator = nil; XCTAssertNil(weakCoordinator) }
            selected?(true, nil); XCTAssertEqual(sent, mode == 0 ? 1 : 0)
            Probe.check = nil
        }
    }
}
