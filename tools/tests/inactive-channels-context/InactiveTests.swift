import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int64
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
    let peerId: PeerId
    let window = Window()
    init(_ owner: Int = 1, peerId: PeerId = 1) { engine = Engine(owner); self.peerId = peerId }
}
final class Window {}
final class Engine { let owner: Int; let peers = Peers(); init(_ owner: Int) { self.owner = owner } }
struct Peer { let id: PeerId }
struct EnginePeer { let peer: Peer; init(_ peer: Peer) { self.peer = peer } }
struct InactiveChannel: Equatable { let id: Int }
final class Peers {
    var list: Signal<[InactiveChannel], NoError> = .complete()
    var ensure: Signal<Never, NoError> = .complete()
    var removal: Signal<Void, NoError> = .complete()
    var removed: [PeerId] = []
    var ensured: [PeerId] = []
    func inactiveChannelList() -> Signal<[InactiveChannel], NoError> { UI.onList?(); return list }
    func ensurePeersAreLocallyAvailable(peers: [EnginePeer]) -> Signal<Never, NoError> { ensured = peers.map { $0.peer.id }; UI.onEnsure?(); return ensure }
    func removePeerChat(peerId: PeerId, reportChatSpam: Bool) -> Signal<Void, NoError> { removed.append(peerId); UI.onRemove?(); return removal }
}
struct SelectPresentation { var selected: Set<PeerId> = []; var peers: [PeerId: Peer] = [:] }
final class SelectPeerInteraction {
    var presentation = SelectPresentation()
    var singleUpdater: ((SelectPresentation) -> Void)?
}
__ARGUMENTS__
func inactiveEntries(state: InactiveChannelsState, arguments: InactiveChannelsArguments, source: InactiveSource) -> [Int] {
    UI.arguments = arguments; UI.source = source
    return state.channels?.map { $0.id } ?? []
}
struct InputDataSignalValue { let entries: [Int] }
enum Screen { case appTooManyChats }
enum DataResult { case none }
final class InputDataController {
    var analyticsScreen: Screen?
    var analyticsContext: AnalyticsContext?
    var entries: [Int] = []
    var onDeinit: (() -> Void)?
    var afterTransaction: ((InputDataController) -> Void)?
    var leftModalHeader: ModalHeaderData?
    var updateDatas: ((Int) -> DataResult)?
    var subscription: Disposable?
    init(dataSignal: Signal<InputDataSignalValue, NoError>, title: String) {
        subscription = dataSignal.start(next: { [weak self] value in self?.entries = value.entries })
    }
    deinit { onDeinit?(); subscription?.dispose() }
}
struct ModalHeaderData { let image: Int; let handler: () -> Void }
enum ButtonState { case Normal }
final class Button { var isEnabled = false; func set(text: String, for state: ButtonState) {} }
final class ModalInteractions {
    let accept: () -> Void
    init(acceptTitle: String, accept: @escaping () -> Void, singleButton: Bool) { self.accept = accept }
    func updateDone(_ f: (Button) -> Void) { f(Button()) }
}
final class InputDataModalController {
    let current: InputDataController
    let interactions: ModalInteractions
    let closeHandler: (@escaping () -> Void) -> Void
    var analyticsContext: AnalyticsContext?
    var closes = 0
    init(_ current: InputDataController, modalInteractions: ModalInteractions, closeHandler: @escaping (@escaping () -> Void) -> Void, size: NSSize) {
        self.current = current; interactions = modalInteractions; self.closeHandler = closeHandler
    }
    func close() { closeHandler { self.closes += 1; UI.onClose?() } }
}
enum InactiveSource: Equatable { case join, create, upgrade, invite }
enum InactiveChannelsReason { case join, create, upgrade }
struct Theme { struct Icons { let modalClose = 0 }; let icons = Icons() }
let theme = Theme()
struct Strings { let inactiveChannelsTitle = "inactive", inactiveChannelsOK = "remove", modalOK = "ok" }
func strings() -> Strings { Strings() }
enum Limit { case channels }
enum PremiumSource { case double_limits(Limit) }
final class PremiumBoardingController {
    let analyticsContext: AnalyticsContext?
    init(context: any AccountContextProtocol, source: PremiumSource, analyticsContext: AnalyticsContext? = nil) { self.analyticsContext = analyticsContext; UI.onPremiumInit?() }
}
func prem(with controller: PremiumBoardingController, for window: Window) { UI.premium.append(controller); UI.onPremium?() }
func showModal(with controller: InputDataModalController, for window: Window) { UI.modal = controller; UI.onShow?() }
func showModalProgress<T, E>(signal: Signal<T, E>, for window: Window) -> Signal<T, E> { UI.onProgress?(); return signal }
__FACTORY__
__PRESENT__
struct ChatHooks {
__CHAT_HOOK__
}
struct FeatureHooks {
__FEATURE_HOOK__
}
func chatHooks() -> ChatHooks {
    var hooks = ChatHooks()
__CHAT_INSTALL__
    return hooks
}
func featureHooks() -> FeatureHooks {
    var hooks = FeatureHooks()
__FEATURE_INSTALL__
    return hooks
}
enum UI {
    static var exclusions = 0
    static var arguments: InactiveChannelsArguments?
    static var source: InactiveSource?
    static var modal: InputDataModalController?
    static var premium: [PremiumBoardingController] = []
    static var onList: (() -> Void)?
    static var onEnsure: (() -> Void)?
    static var onRemove: (() -> Void)?
    static var onClose: (() -> Void)?
    static var onProgress: (() -> Void)?
    static var onShow: (() -> Void)?
    static var onPremiumInit: (() -> Void)?
    static var onPremium: (() -> Void)?
    static func reset() {
        modal = nil; arguments = nil; source = nil; premium = []
        onList = nil; onEnsure = nil; onRemove = nil; onClose = nil; onProgress = nil; onShow = nil; onPremiumInit = nil; onPremium = nil
    }
}
final class InactiveTests: XCTestCase {
    override func setUp() { UI.reset(); XCTAssertEqual(UI.exclusions, 0) }
    override func tearDown() { UI.reset(); XCTAssertEqual(UI.exclusions, 0) }
    func testLegacyPresentationIsDeniedBeforeListConstructionAndBindsBothControllers() {
        let context = Context()
        UI.onList = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onShow = { XCTAssertGreaterThan(UI.exclusions, 0) }
        showInactiveChannels(context: context, source: .join)
        XCTAssertTrue(UI.modal?.analyticsContext?.isExcluded == true)
        XCTAssertTrue(UI.modal?.current.analyticsContext?.isExcluded == true)
        UI.modal?.close()
        XCTAssertEqual(UI.exclusions, 0)
    }
    func testInstalledChatAndFeatureBridgesPreserveOrdinaryGrantAndReason() {
        let context = Context(); let origin = AnalyticsContext()
        chatHooks().showInactiveChannelsOnJoinObserved(context, analyticsContext: origin)
        XCTAssertTrue(UI.modal?.analyticsContext?.scope === origin.scope); XCTAssertEqual(UI.source, .join)
        UI.modal?.close(); UI.reset()
        for (reason, source) in [(InactiveChannelsReason.join, InactiveSource.join), (.create, .create), (.upgrade, .upgrade)] {
            featureHooks().showInactiveChannelsObserved(context, reason, analyticsContext: origin)
            XCTAssertTrue(UI.modal?.current.analyticsContext?.scope === origin.scope); XCTAssertEqual(UI.source, source)
            UI.modal?.close(); UI.reset()
        }
    }
    func testSecretForeignAndRevokedContextsCannotGainOrdinaryAdmission() {
        let revoked = AnalyticsContext(); revoked.scope?.valid = false
        for (context, origin) in [(Context(), AnalyticsContext(excluded: true)), (Context(2), AnalyticsContext()), (Context(), revoked), (Context(peerId: -1), AnalyticsContext())] {
            UI.onList = { XCTAssertGreaterThan(UI.exclusions, 0) }
            UI.onShow = { XCTAssertGreaterThan(UI.exclusions, 0) }
            featureHooks().showInactiveChannelsObserved(context, .join, analyticsContext: origin)
            UI.modal?.close(); UI.reset()
        }
    }
    func testListDeliveryAndDisposalUseOriginAndCloseRejectsLateOutput() {
        let context = Context(); var result: Subscriber<[InactiveChannel], NoError>?
        var disposed = 0
        let ready = expectation(description: "list subscription")
        context.engine.peers.list = Signal { result = $0; ready.fulfill(); return ActionDisposable { disposed += 1; XCTAssertGreaterThan(UI.exclusions, 0) } }
        let modal = InactiveChannelsController(context: context, source: .join, analyticsContext: AnalyticsContext(excluded: true))
        wait(for: [ready], timeout: 2)
        result?.putNext([InactiveChannel(id: 42)])
        XCTAssertEqual(modal.current.entries, [42])
        modal.close(); result?.putNext([InactiveChannel(id: 99)])
        XCTAssertEqual(disposed, 1); XCTAssertEqual(modal.current.entries, [42]); XCTAssertEqual(UI.exclusions, 0)
    }
    func testRemovalSnapshotsSelectionBeforeCloseAndConsumesRepeatedAcceptance() {
        let context = Context(); let origin = AnalyticsContext()
        let modal = InactiveChannelsController(context: context, source: .join, analyticsContext: origin)
        UI.arguments?.select.presentation = SelectPresentation(selected: [3], peers: [3: Peer(id: 3)])
        UI.onClose = { UI.arguments?.select.presentation = SelectPresentation(selected: [4], peers: [4: Peer(id: 4)]) }
        modal.interactions.accept(); modal.interactions.accept()
        XCTAssertEqual(context.engine.peers.removed, [3]); XCTAssertEqual(context.engine.peers.ensured, [3]); XCTAssertEqual(modal.closes, 1)
    }
    func testSecretSelectionScopesRemovalSetupAndPendingWorkAfterParentCloses() {
        for peerOnly in [false, true] {
            let context = Context(); var ensured: Subscriber<Never, NoError>?
            var removed: Subscriber<Void, NoError>?
            context.engine.peers.ensure = Signal { ensured = $0; return EmptyDisposable }
            context.engine.peers.removal = Signal { removed = $0; return ActionDisposable { XCTAssertGreaterThan(UI.exclusions, 0) } }
            let modal = InactiveChannelsController(context: context, source: .join, analyticsContext: AnalyticsContext())
            UI.arguments?.select.presentation = SelectPresentation(selected: [peerOnly ? 3 : -3], peers: [3: Peer(id: -3)])
            UI.onEnsure = { XCTAssertGreaterThan(UI.exclusions, 0) }
            UI.onRemove = { XCTAssertGreaterThan(UI.exclusions, 0) }
            UI.onProgress = { XCTAssertGreaterThan(UI.exclusions, 0) }
            modal.interactions.accept()
            XCTAssertEqual(modal.closes, 1); XCTAssertGreaterThan(UI.exclusions, 0)
            ensured?.putCompletion(); removed?.putCompletion()
            XCTAssertEqual(UI.exclusions, 0)
            UI.reset()
        }
    }
    func testEmptySelectionAndDismissalDoNotRemoveOrOpenLatePremium() {
        let context = Context()
        let modal = InactiveChannelsController(context: context, source: .join, analyticsContext: AnalyticsContext())
        let premium = UI.arguments!.premium
        modal.current.leftModalHeader?.handler()
        modal.interactions.accept(); premium()
        XCTAssertTrue(context.engine.peers.removed.isEmpty); XCTAssertTrue(UI.premium.isEmpty)
        XCTAssertEqual(modal.closes, 1)
    }
    func testPremiumRetainsOriginalContextAndRechecksRevocationBeforeConstruction() {
        let context = Context(); let origin = AnalyticsContext()
        let modal = InactiveChannelsController(context: context, source: .join, analyticsContext: origin)
        origin.scope?.valid = false
        UI.onPremiumInit = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.onPremium = { XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.arguments?.premium()
        XCTAssertEqual(UI.premium.count, 1); XCTAssertTrue(UI.premium[0].analyticsContext?.scope === origin.scope)
        modal.close(); UI.arguments?.premium()
        XCTAssertEqual(UI.premium.count, 1)
    }
    func testOwnerReleaseDisposesListAndRejectsRetainedActions() {
        let context = Context(); var disposed = 0
        let ready = expectation(description: "list subscription before owner release")
        context.engine.peers.list = Signal { _ in ready.fulfill(); return ActionDisposable { disposed += 1; XCTAssertGreaterThan(UI.exclusions, 0) } }
        var modal: InputDataModalController? = InactiveChannelsController(context: context, source: .join, analyticsContext: AnalyticsContext(excluded: true))
        wait(for: [ready], timeout: 2)
        let accept = modal!.interactions.accept; let premium = UI.arguments!.premium
        UI.arguments?.select.presentation.selected = [3]
        modal = nil; accept(); premium()
        XCTAssertEqual(disposed, 1); XCTAssertTrue(context.engine.peers.removed.isEmpty); XCTAssertTrue(UI.premium.isEmpty); XCTAssertEqual(UI.exclusions, 0)
    }
    func testLegacyHookFallbacksRunUnderPrivateOrigin() {
        let context = Context(); let origin = AnalyticsContext(excluded: true)
        var chat = ChatHooks(); var feature = FeatureHooks(); var calls = 0
        chat.showInactiveChannelsOnJoin = { _ in calls += 1; XCTAssertGreaterThan(UI.exclusions, 0) }
        feature.showInactiveChannels = { _, _ in calls += 1; XCTAssertGreaterThan(UI.exclusions, 0) }
        chat.showInactiveChannelsOnJoinObserved(context, analyticsContext: origin)
        feature.showInactiveChannelsObserved(context, .join, analyticsContext: origin)
        XCTAssertEqual(calls, 2); XCTAssertEqual(UI.exclusions, 0)
    }
    func testEmptyAcceptanceClosesOnceWithoutEnsuringOrRemovingPeers() {
        let context = Context()
        let modal = InactiveChannelsController(context: context, source: .join, analyticsContext: AnalyticsContext())
        modal.interactions.accept(); modal.interactions.accept()
        XCTAssertEqual(modal.closes, 1); XCTAssertTrue(context.engine.peers.removed.isEmpty); XCTAssertTrue(context.engine.peers.ensured.isEmpty)
    }
    func testClosingBeforeDelayedListSubscriptionPreventsItsStart() {
        let context = Context()
        let started = expectation(description: "closed list must not subscribe"); started.isInverted = true
        context.engine.peers.list = Signal { _ in started.fulfill(); return EmptyDisposable }
        let modal = InactiveChannelsController(context: context, source: .join)
        modal.close()
        wait(for: [started], timeout: 0.7)
        XCTAssertEqual(UI.exclusions, 0)
    }
    func testPrivatePremiumContextOutlivesSynchronousParentDismissal() {
        let context = Context()
        let modal = InactiveChannelsController(context: context, source: .join, analyticsContext: AnalyticsContext(excluded: true))
        UI.onPremium = { modal.close(); XCTAssertGreaterThan(UI.exclusions, 0) }
        UI.arguments?.premium()
        XCTAssertEqual(modal.closes, 1); XCTAssertEqual(UI.premium.count, 1)
        XCTAssertTrue(UI.premium[0].analyticsContext?.isExcluded == true)
        UI.onPremium = nil
    }

}
