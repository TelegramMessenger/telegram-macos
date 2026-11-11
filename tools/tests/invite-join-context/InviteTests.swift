import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int64
extension Int64 {
    enum Id { static func _internalFromInt64Value(_ value: Int64) -> Int64 { value } }
    init(namespace: Int, id: Int64) { self = id }
}
enum Namespaces { enum Peer { static let CloudGroup = 1 } }
final class Scope { var valid = true }
final class AnalyticsContext {
    let owner: Int
    let isExcluded: Bool
    let scope: Scope?
    init(_ owner: Int = 1, excluded: Bool = false, scope: Scope? = Scope()) { self.owner = owner; self.isExcluded = excluded; self.scope = excluded ? nil : scope }
    func restricting(peerId: PeerId) -> AnalyticsContext { AnalyticsContext(owner, excluded: isExcluded || peerId < 0, scope: scope) }
    func beginPresentation() -> AnalyticsPresentation { AnalyticsPresentation(self) }
__SIGNAL__
}
final class AnalyticsPresentation {
    let excluded: Bool
    var ended = false
    init(_ context: AnalyticsContext) { excluded = context.isExcluded || context.scope?.valid != true; if excluded { UI.exclusions += 1 } }
    func end() { guard !ended else { return }; ended = true; if excluded { UI.exclusions -= 1 } }
    deinit { end() }
}
final class Analytics {
    static let shared = Analytics()
    func unresolvedContext() -> AnalyticsContext { AnalyticsContext(excluded: true) }
    func captureContext(engine: Engine, peerId: PeerId, inherited: AnalyticsContext) -> AnalyticsContext {
        AnalyticsContext(engine.owner, excluded: inherited.isExcluded || peerId < 0, scope: inherited.owner == engine.owner ? inherited.scope : nil)
    }
}
protocol AccountContextProtocol: AnyObject { var engine: Engine { get }; var peerId: PeerId { get }; var window: Window { get } }
final class Context: AccountContextProtocol {
    let engine: Engine
    let peerId: PeerId = 1
    let window = Window()
    init(_ owner: Int = 1) { engine = Engine(owner) }
}
final class Window {}
final class Engine { let owner: Int; let peers = Peers(); init(_ owner: Int) { self.owner = owner } }
class Peer { let id: PeerId; init(_ id: PeerId) { self.id = id } }
struct EnginePeer { let peer: Peer; var id: PeerId { peer.id }; init(_ peer: Peer) { self.peer = peer }; func _asPeer() -> Peer { peer } }
enum Role { case member }
enum Membership { case Left }
final class TelegramGroup: Peer {
    init(id: PeerId, title: String, photo: [Int], participantCount: Int, role: Role, membership: Membership, flags: [Int], defaultBannedRights: Int?, migrationReference: Int?, creationDate: Int, version: Int) { super.init(id) }
}
typealias TelegramMediaImageRepresentation = Int
enum ExternalJoiningChatState {
    struct Invite {
        struct Flags: Equatable { var isChannel = true; var isBroadcast = false }
        var flags = Flags()
        var title = "synthetic"
        var about: String? = nil
        var photoRepresentation: Int? = nil
        var participantsCount: Int32 = 0
        var participants: [EnginePeer]? = nil
    }
    case invite(Invite)
    case invalid
}
enum JoinLinkError: Error { case generic, tooMuchJoined, tooMuchUsers, requestSent, flood }
struct JoinWebView { let botPeer: EnginePeer; let url: String?; let queryId: Int64; let peerId: PeerId? }
enum JoinLinkResult { case joined(EnginePeer?), webView(JoinWebView) }
final class Peers {
    var signal: Signal<JoinLinkResult, JoinLinkError> = .complete()
    var requests = 0
    func joinChatInteractively(with hash: String) -> Signal<JoinLinkResult, JoinLinkError> { requests += 1; UI.events.append("request"); UI.onRequest?(); return signal }
}
__REQUEST_TYPES__
func entries(_ state: State, arguments: Arguments) -> [Int] { [] }
func joinLinkPreviewEntries(context: any AccountContextProtocol, peer: TelegramGroup, participants: [Peer]?, groupUserCount: Int32) -> [Int] { [] }
func deliverOnPrepareQueue<T, E>(_ signal: Signal<T, E>) -> Signal<T, E> { signal }
struct InputDataSignalValue { let entries: [Int] }
enum Screen { case linkInvitePreview, linkJoinRequest }
enum KeyResult { case `default` }
final class InputDataController {
    var analyticsScreen: Screen?
    var analyticsContext: AnalyticsContext?
    var window: Window? = Window()
    var onDeinit: (() -> Void)?
    var leftModalHeader: ModalHeaderData?
    var afterTransaction: ((InputDataController) -> Void)?
    var returnKeyInvocation: ((Int, Int) -> KeyResult)?
    init(dataSignal: Signal<InputDataSignalValue, NoError>, title: String) { UI.onControllerInit?() }
    func returnKeyAction() -> KeyResult { returnKeyInvocation?(0, 0) ?? .default }
    deinit { onDeinit?() }
}
struct ModalHeaderData { let image: Int; let handler: () -> Void }
final class ModalInteractions {
    let accept: () -> Void
    init(acceptTitle: String, accept: @escaping () -> Void, singleButton: Bool) { self.accept = accept }
}
final class InputDataModalController {
    let current: InputDataController
    let interactions: ModalInteractions
    let closeHandler: (@escaping () -> Void) -> Void
    var analyticsContext: AnalyticsContext?
    var closes = 0
    var modal: InputDataModalController? { self }
    init(_ current: InputDataController, modalInteractions: ModalInteractions, closeHandler: @escaping (@escaping () -> Void) -> Void = { $0() }, size: NSSize = .zero) {
        self.current = current; interactions = modalInteractions; self.closeHandler = closeHandler
    }
    func close() { closeHandler { self.closes += 1; self.current.window = nil; UI.events.append("close"); UI.onClose?() } }
}
struct Theme { struct Icons { let modalClose = 0 }; let icons = Icons() }
let theme = Theme()
struct Strings {
    let joinLinkJoin = "join", requestJoinButton = "request", unknownError = "unknown", groupUsersTooMuchError = "too many", requestJoinSent = "sent", joinLinkFloodError = "flood"
}
func strings() -> Strings { Strings() }
enum InactiveChannelsReason { case join, create, upgrade }
enum InactiveSource { case join, create, upgrade }
func showInactiveChannels(context: any AccountContextProtocol, source: InactiveSource) { UI.recovery.append(nil); UI.onRecovery?() }
func showInactiveChannels(context: any AccountContextProtocol, source: InactiveSource, analyticsContext: AnalyticsContext?) { UI.recovery.append(analyticsContext); UI.onRecovery?() }
func openJoinChatBotWebView(context: any AccountContextProtocol, botId: PeerId, url: String?, queryId: Int64, joinedPeerId: PeerId?) { UI.browser.append(nil); UI.browserPeers.append(joinedPeerId); UI.onBrowser?() }
func openJoinChatBotWebView(context: any AccountContextProtocol, botId: PeerId, url: String?, queryId: Int64, joinedPeerId: PeerId?, analyticsContext: AnalyticsContext?) { UI.browser.append(analyticsContext); UI.browserPeers.append(joinedPeerId); UI.events.append("browser"); UI.onBrowser?() }
func showModalProgress<T, E>(signal: Signal<T, E>, for window: Window) -> Signal<T, E> { UI.onProgress?(); return signal }
func showModalText(for window: Window, text: String) { UI.texts.append(text); UI.onFeedback?() }
func alert(for window: Window, info: String) { UI.alerts.append(info); UI.onFeedback?() }
struct FeatureNavigationHooks {
    static var shared = FeatureNavigationHooks()
__JOIN_HOOK__
__RECOVERY_HOOK__
}
func installHooks() {
    var hooks = FeatureNavigationHooks()
__JOIN_INSTALL__
__RECOVERY_INSTALL__
    FeatureNavigationHooks.shared = hooks
}
__ACTION__
__PREVIEW__
__REQUEST__
enum UI {
    static var exclusions = 0
    static var browser: [AnalyticsContext?] = []
    static var browserPeers: [PeerId?] = []
    static var recovery: [AnalyticsContext?] = []
    static var alerts: [String] = []
    static var texts: [String] = []
    static var events: [String] = []
    static var onRequest: (() -> Void)?
    static var onProgress: (() -> Void)?
    static var onControllerInit: (() -> Void)?
    static var onClose: (() -> Void)?
    static var onFeedback: (() -> Void)?
    static var onRecovery: (() -> Void)?
    static var onBrowser: (() -> Void)?
    static func reset() {
        browser = []; browserPeers = []; recovery = []; alerts = []; texts = []; events = []
        onRequest = nil; onProgress = nil; onControllerInit = nil; onClose = nil; onFeedback = nil; onRecovery = nil; onBrowser = nil
        installHooks()
    }
}
final class InviteTests: XCTestCase {
    override func setUp() { UI.reset(); XCTAssertEqual(UI.exclusions, 0) }
    override func tearDown() { UI.reset(); XCTAssertEqual(UI.exclusions, 0) }
    func preview(_ context: Context, origin: AnalyticsContext? = nil, interaction: @escaping (Peer) -> Void = { _ in }) -> InputDataModalController {
        JoinLinkPreviewModalController(context, hash: "synthetic", join: .invite(.init()), analyticsContext: origin, interaction: interaction)
    }
    func request(_ context: Context, origin: AnalyticsContext? = nil, interaction: @escaping (Peer) -> Void = { _ in }) -> InputDataModalController {
        RequestJoinChatModalController(context: context, joinhash: "synthetic", invite: .invite(.init()), analyticsContext: origin, interaction: interaction)
    }
    func webview(_ peerId: PeerId? = 3) -> JoinLinkResult { .webView(JoinWebView(botPeer: EnginePeer(Peer(2)), url: "synthetic", queryId: 901, peerId: peerId)) }
    func testLegacyFactoriesDenyConstructionAndBindInputAndModal() {
        let context = Context()
        UI.onControllerInit = { XCTAssertGreaterThan(UI.exclusions, 0) }
        let a = JoinLinkPreviewModalController(context, hash: "synthetic", join: .invite(.init()), interaction: { _ in })
        let b = RequestJoinChatModalController(context: context, joinhash: "synthetic", invite: .invite(.init()), interaction: { _ in })
        for modal in [a, b] { XCTAssertTrue(modal.analyticsContext?.isExcluded == true); XCTAssertTrue(modal.current.analyticsContext?.isExcluded == true) }
    }
    func testPreviewOwnsPendingRequestAndClosingSuppressesLateResult() {
        let context = Context(); var result: Subscriber<JoinLinkResult, JoinLinkError>?
        var disposed = 0
        context.engine.peers.signal = Signal { result = $0; return ActionDisposable { disposed += 1; XCTAssertGreaterThan(UI.exclusions, 0) } }
        UI.onRequest = { XCTAssertGreaterThan(UI.exclusions, 0) }; UI.onProgress = { XCTAssertGreaterThan(UI.exclusions, 0) }
        var joined = 0
        let modal = preview(context, origin: AnalyticsContext(excluded: true), interaction: { _ in joined += 1 })
        modal.interactions.accept(); modal.interactions.accept()
        XCTAssertEqual(context.engine.peers.requests, 1); XCTAssertGreaterThan(UI.exclusions, 0)
        modal.close(); result?.putNext(.joined(EnginePeer(Peer(3))))
        XCTAssertEqual(disposed, 1); XCTAssertEqual(joined, 0); XCTAssertEqual(UI.exclusions, 0)
    }
    func testPreviewBrowserHandoffClosesBeforeOpeningAndKeepsOriginAfterDisposal() {
        let context = Context(); let origin = AnalyticsContext(excluded: true)
        context.engine.peers.signal = .single(webview())
        UI.onBrowser = { XCTAssertGreaterThan(UI.exclusions, 0) }
        let modal = preview(context, origin: origin)
        modal.interactions.accept(); modal.interactions.accept()
        XCTAssertEqual(UI.events, ["request", "close", "browser"])
        XCTAssertTrue(UI.browser.last??.isExcluded == true); XCTAssertEqual(UI.browserPeers, [3])
    }
    func testRequestSubmissionSurvivesParentReleaseButCannotBeSubmittedTwice() {
        let context = Context(); var result: Subscriber<JoinLinkResult, JoinLinkError>?
        var disposed = 0; var joined = 0
        context.engine.peers.signal = Signal { result = $0; return ActionDisposable { disposed += 1; XCTAssertGreaterThan(UI.exclusions, 0) } }
        var modal: InputDataModalController? = request(context, origin: AnalyticsContext(excluded: true), interaction: { _ in joined += 1; XCTAssertGreaterThan(UI.exclusions, 0) })
        let invoke = modal!.current.returnKeyInvocation!
        _ = invoke(0, 0); _ = invoke(0, 0)
        XCTAssertEqual(UI.events, ["close", "request"])
        modal = nil
        XCTAssertEqual(disposed, 0); XCTAssertGreaterThan(UI.exclusions, 0)
        result?.putNext(.joined(EnginePeer(Peer(3)))); result?.putNext(.joined(EnginePeer(Peer(3))))
        XCTAssertEqual(joined, 1); XCTAssertEqual(disposed, 1); XCTAssertEqual(UI.exclusions, 0)
    }
    func testCancelledRequestDialogRejectsRetainedReturnKeyHandler() {
        let context = Context(); let modal = request(context)
        let invoke = modal.current.returnKeyInvocation!
        modal.close(); _ = invoke(0, 0); modal.interactions.accept()
        XCTAssertEqual(context.engine.peers.requests, 0)
    }
    func testPreviewCanRetryAfterErrorOrEmptyCompletionWithoutStaleAttemptWinning() {
        let context = Context(); let modal = preview(context)
        context.engine.peers.signal = .fail(.generic)
        modal.interactions.accept()
        context.engine.peers.signal = .complete()
        modal.interactions.accept()
        context.engine.peers.signal = .single(.joined(nil))
        modal.interactions.accept(); modal.interactions.accept()
        XCTAssertEqual(context.engine.peers.requests, 3); XCTAssertEqual(UI.alerts, ["unknown"]); XCTAssertEqual(modal.closes, 1)
        let gate = InviteJoinAction(); let first = gate.begin()!
        XCTAssertTrue(gate.take(first, terminal: false))
        let second = gate.begin()!
        XCTAssertFalse(gate.take(first, terminal: false)); XCTAssertNil(gate.begin()); XCTAssertTrue(gate.take(second, terminal: true))
    }
    func testRequestSentFeedbackPreservesEachDialogsExistingBehavior() {
        let context = Context(); context.engine.peers.signal = .fail(.requestSent)
        UI.onFeedback = { XCTAssertGreaterThan(UI.exclusions, 0) }
        let a = preview(context); a.interactions.accept()
        let b = request(context); b.interactions.accept()
        XCTAssertEqual(UI.alerts, ["unknown"]); XCTAssertEqual(UI.texts, ["sent"])
    }
    func testRecoveryAndOtherErrorsKeepOriginAfterRequestDialogCloses() {
        for error in [JoinLinkError.tooMuchJoined, .tooMuchUsers, .flood, .generic] {
            let context = Context(); context.engine.peers.signal = .fail(error)
            UI.onRecovery = { XCTAssertGreaterThan(UI.exclusions, 0) }; UI.onFeedback = { XCTAssertGreaterThan(UI.exclusions, 0) }
            let modal = request(context, origin: AnalyticsContext(excluded: true)); modal.interactions.accept()
            XCTAssertEqual(UI.recovery.count + UI.alerts.count, 1)
            if !UI.recovery.isEmpty { XCTAssertTrue(UI.recovery[0]?.isExcluded == true) }
            UI.reset()
        }
    }
    func testKnownOrdinaryDestinationKeepsGrantAndUnknownOrSecretDestinationDenies() {
        for peerId: PeerId? in [3, nil, -3] {
            let context = Context(); let origin = AnalyticsContext()
            context.engine.peers.signal = .single(webview(peerId))
            let modal = preview(context, origin: origin); modal.interactions.accept()
            if peerId == 3 { XCTAssertTrue(UI.browser.last??.scope === origin.scope) }
            else { XCTAssertTrue(UI.browser.last??.isExcluded == true) }
            XCTAssertEqual(UI.browserPeers, [peerId]); UI.reset()
        }
    }
    func testRevocationAndForeignAccountDoNotRefreshGrantBeforeDelayedBrowserDelivery() {
        for foreign in [false, true] {
            let context = Context(foreign ? 2 : 1); let origin = AnalyticsContext()
            var result: Subscriber<JoinLinkResult, JoinLinkError>?
            context.engine.peers.signal = Signal { result = $0; return EmptyDisposable }
            let modal = request(context, origin: origin); modal.interactions.accept()
            origin.scope?.valid = false
            UI.onBrowser = { XCTAssertGreaterThan(UI.exclusions, 0) }
            result?.putNext(webview())
            if foreign { XCTAssertNil(UI.browser.last??.scope) } else { XCTAssertTrue(UI.browser.last??.scope === origin.scope) }
            UI.reset()
        }
    }
    func testJoinedDestinationIsRestrictedBeforeNavigationAndNilPeerDoesNotNavigate() {
        let context = Context(); var peers: [PeerId] = []
        context.engine.peers.signal = .single(.joined(EnginePeer(Peer(-3))))
        let first = preview(context, origin: AnalyticsContext(), interaction: { peer in peers.append(peer.id); XCTAssertGreaterThan(UI.exclusions, 0) })
        first.interactions.accept()
        context.engine.peers.signal = .single(.joined(nil))
        let second = request(context, origin: AnalyticsContext(), interaction: { peer in peers.append(peer.id) })
        second.interactions.accept()
        XCTAssertEqual(peers, [-3]); XCTAssertEqual(first.closes, 1)
    }
    func testReentrantSuccessCannotStartAnotherPreviewSubmission() {
        let context = Context(); context.engine.peers.signal = .single(.joined(EnginePeer(Peer(3))))
        var accept: (() -> Void)?
        let modal = preview(context, interaction: { _ in accept?() })
        accept = modal.interactions.accept
        accept?()
        XCTAssertEqual(context.engine.peers.requests, 1); XCTAssertEqual(modal.closes, 1)
        accept = nil
    }
    func testPreviewReleaseDisposesRequestAndRetainedAcceptCannotRestart() {
        let context = Context(); var disposed = 0
        context.engine.peers.signal = Signal { _ in ActionDisposable { disposed += 1; XCTAssertGreaterThan(UI.exclusions, 0) } }
        var modal: InputDataModalController? = preview(context, origin: AnalyticsContext(excluded: true))
        let accept = modal!.interactions.accept
        accept(); modal = nil; accept()
        XCTAssertEqual(context.engine.peers.requests, 1); XCTAssertEqual(disposed, 1); XCTAssertEqual(UI.exclusions, 0)
    }
    func testReentrantErrorRetryKeepsNewAttemptAndCompletesOnlyOnce() {
        let context = Context(); context.engine.peers.signal = .fail(.generic)
        let modal = preview(context)
        var result: Subscriber<JoinLinkResult, JoinLinkError>?
        UI.onFeedback = {
            context.engine.peers.signal = Signal { result = $0; return EmptyDisposable }
            modal.interactions.accept()
        }
        modal.interactions.accept()
        XCTAssertEqual(context.engine.peers.requests, 2)
        result?.putNext(.joined(nil))
        XCTAssertEqual(modal.closes, 1)
        UI.onFeedback = nil
    }

}
