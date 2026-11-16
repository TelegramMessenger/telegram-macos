import Foundation
import SwiftSignalKit
import XCTest

typealias PeerId = Int
typealias InputDataIdentifier = Int
typealias InputDataValue = Int
enum InputDataValidation { case none }
class Peer { let id: Int; var isPremium = true; var isChannel: Bool { self is TelegramChannel }; init(_ id: Int) { self.id = id } }
final class TelegramUser: Peer {}
final class TelegramChannel: Peer { var approximateBoostLevel: Int32? = 10 }
struct EnginePeer { let peer: Peer; init(_ peer: Peer) { self.peer = peer }; var id: Int { peer.id }; func _asPeer() -> Peer { peer } }
enum StarGift {
    case unique(UniqueGift)
    var unique: UniqueGift? { if case let .unique(gift) = self { return gift }; return nil }
    struct UniqueGift {
        enum Owner { case peerId(Int), address(String), name(String); var peerId: Int? { if case let .peerId(id) = self { return id }; return nil } }
        let id: Int64; var owner: Owner?; var hostPeerId: Int?
        init(_ id: Int64 = 100, owner: Owner? = .peerId(1), host: Int? = nil) { self.id = id; self.owner = owner; self.hostPeerId = host }
    }
}
struct ChannelBoostStatus { let level: Int }
struct MyBoostStatus { let count: Int }
enum Failure { case generic }
final class Request<T,E> {
    let subscriber: Subscriber<T,E>; var disposed = false; var onDispose: (() -> Void)?
    init(_ subscriber: Subscriber<T,E>) { self.subscriber = subscriber }
    func send(_ value: T) { subscriber.putNext(value) }
    func complete() { subscriber.putCompletion() }
    func reject(_ error: E) { subscriber.putError(error) }
    func dispose() { if !disposed { disposed = true; onDispose?() } }
}
final class AccountData {
    var requests: [Request<Never,Failure>] = []; var gifts: [Int64] = []; var onSubscribe: ((Request<Never,Failure>) -> Void)?
    func setStarGiftStatusWithResult(starGift: StarGift.UniqueGift, expirationDate: Int32?) -> Signal<Never,Failure> {
        Signal { subscriber in
            let request = Request(subscriber); self.requests.append(request); self.gifts.append(starGift.id); self.onSubscribe?(request)
            return ActionDisposable { request.dispose() }
        }
    }
    func setStarGiftStatus(starGift: StarGift.UniqueGift, expirationDate: Int32?) -> Signal<Never,NoError> { setStarGiftStatusWithResult(starGift: starGift, expirationDate: expirationDate) |> `catch` { _ in .complete() } }
}
final class Peers {
    var requests: [Request<Never,Failure>] = []; var targets: [Int] = []; var gifts: [Int64] = []
    var boosts: [Request<ChannelBoostStatus?,NoError>] = []; var mine: [Request<MyBoostStatus?,NoError>] = []
    func updatePeerStarGiftStatus(peerId: Int, starGift: StarGift.UniqueGift, expirationDate: Int32?) -> Signal<Never,Failure> { Signal { subscriber in let request = Request(subscriber); self.requests.append(request); self.targets.append(peerId); self.gifts.append(starGift.id); return ActionDisposable { request.dispose() } } }
    func getChannelBoostStatus(peerId: Int) -> Signal<ChannelBoostStatus?,NoError> { Signal { subscriber in let request = Request(subscriber); self.boosts.append(request); return ActionDisposable { request.dispose() } } }
    func getMyBoostStatus() -> Signal<MyBoostStatus?,NoError> { Signal { subscriber in let request = Request(subscriber); self.mine.append(request); return ActionDisposable { request.dispose() } } }
}
final class Engine { let accountData = AccountData(); let peers = Peers() }
final class Window { var messages: [String] = []; var confetti = 0; var premium = 0; var boost = 0; var boostMorph: Int?; var callbacks: [(String)->Void] = [] }
protocol AccountContextProtocol: AnyObject { var peerId: Int { get }; var isPremium: Bool { get }; var engine: Engine { get }; var window: Window { get } }
final class Context: AccountContextProtocol { let peerId = 1; var isPremium = true; let engine = Engine(); let window = Window() }
struct StarsHooks {
    static var shared = StarsHooks()
    func wearGiftBoostLevel(_ context: any AccountContextProtocol) -> Int32 { 5 }
    func openBoostForWear(_ context: any AccountContextProtocol, _ peer: Peer, _ stats: ChannelBoostStatus?, _ myStatus: MyBoostStatus?, _ window: Window) { window.boost += 1; window.boostMorph = ModalMorphContextSource.current }
}
enum ModalMorphContextSource { static var current: Int? = 42; static func withSource(_ source: Int?, perform: () -> Void) { let old = current; current = source; defer { current = old }; perform() } }
struct Strings { let unknownError = "Error"; let giftUniqueNeedsPremium = "Premium" }
func strings() -> Strings { Strings() }
func showModalText(for window: Window, text: String, callback: ((String) -> Void)? = nil) { window.messages.append(text); if let callback { window.callbacks.append(callback) } }
func PlayConfetti(for window: Window) { window.confetti += 1 }
enum PremiumSource { case emoji_status }
func PremiumBoardingController(context: any AccountContextProtocol, source: PremiumSource, openFeatures: Bool) -> Int { 0 }
func prem(with: Int, for window: Window) { window.premium += 1 }
final class Queue { static let main = Queue(); var jobs: [() -> Void] = []; static func mainQueue() -> Queue { main }; func justDispatch(_ f: @escaping () -> Void) { jobs.append(f) }; func drain() { while !jobs.isEmpty { jobs.removeFirst()() } } }
func deliverOnMainQueue<T,E>(_ signal: Signal<T,E>) -> Signal<T,E> { signal }
final class Progress { static var pending: [MetaDisposable] = []; static func reset() { pending.forEach { $0.dispose() }; pending.removeAll() } }
func showModalProgress<T,E>(signal: Signal<T,E>, for window: Window, shouldPresent: @escaping () -> Bool = { true }) -> Signal<T,E> { Signal { subscriber in let pending = MetaDisposable(); Progress.pending.append(pending); pending.set(signal.start(next: { subscriber.putNext($0) }, error: { subscriber.putError($0) }, completed: { subscriber.putCompletion() })); return pending } }
__HELPER__
enum Source { case previewWear(EnginePeer, StarGift.UniqueGift), quickLook(EnginePeer?, StarGift.UniqueGift), other }
struct State { var owner: EnginePeer?; var gift: StarGift; var source: Source; var converted = false; var starsState: Int? = 0; var closeOnOk = false }
final class View { weak var window: Window?; init(_ window: Window) { self.window = window } }
final class Controller {
    let view: View; var loaded = true
    var validateData: (([Int:Int]) -> InputDataValidation)?; var willDisappear: ((Controller) -> Void)?; var willAppear: ((Controller) -> Void)?; var onDeinit: (() -> Void)?
    init(_ window: Window) { view = View(window) }
    func isLoaded() -> Bool { loaded }
    func close() { willDisappear?(self); view.window = nil }
    deinit { onDeinit?() }
}
final class WeakController { weak var controller: Controller?; init(_ controller: Controller) { self.controller = controller } }
final class Observer { var onUpdate: (() -> Void)? }
final class GiftsContext {}
final class Screen {
    let context: Context; let stateValue: Atomic<State>; let wearAction: GiftWearAction; var controller: Controller?; let observer: Observer; var dismissPreview: (() -> Void)?
    init(context: Context = Context(), peer: Peer = TelegramUser(1), gift: StarGift.UniqueGift? = nil) {
        let gift = gift ?? StarGift.UniqueGift(owner: .peerId(peer.id))
        let owner = EnginePeer(peer)
        let stateValue = Atomic(value: State(owner: owner, gift: .unique(gift), source: .previewWear(owner,gift)))
        let wearAction = GiftWearAction()
        let controller = Controller(context.window)
        let box = WeakController(controller)
        var window: Window { box.controller?.view.window ?? context.window }
        let observer = Observer()
        let updateState: ((State) -> State) -> Void = { f in _ = stateValue.modify(f); observer.onUpdate?() }
        let giftsContext = GiftsContext()
        let actionsDisposable = DisposableSet(), craftContextDisposables = DisposableSet()
        __HOOKS__
        __VALIDATOR__
        controller.validateData = { validateGift($0) }
        self.context = context; self.stateValue = stateValue; self.wearAction = wearAction; self.controller = controller; self.observer = observer
        self.dismissPreview = {
            let state = stateValue.with { $0 }
            switch state.source {
            __DISMISS__
            default: break
            }
        }
        withExtendedLifetime(giftsContext) {}
    }
    func apply() { _ = controller?.validateData?([:]) }
    var pending: Request<Never,Failure>? { context.engine.accountData.requests.last ?? context.engine.peers.requests.last }
    var converted: Bool { stateValue.with { $0.converted } }
    var preview: Bool { stateValue.with { if case .previewWear = $0.source { return true }; return false } }
    func mutate(_ f: (inout State) -> Void) { _ = stateValue.modify { state in var state = state; f(&state); return state } }
}
final class GiftWearTests: XCTestCase {
    override func tearDown() { Progress.reset(); Queue.main.drain(); ModalMorphContextSource.current = 42 }
    func testAccountWaitsForAcceptance() { let s = Screen(); s.apply(); XCTAssertTrue(s.preview); XCTAssertFalse(s.converted); XCTAssertEqual(s.context.window.confetti,0); s.pending!.complete(); XCTAssertFalse(s.preview); XCTAssertTrue(s.converted); XCTAssertEqual(s.context.window.confetti,1) }
    func testAccountFailureKeepsPreviewAndReportsError() { let s = Screen(); s.apply(); s.pending!.reject(.generic); XCTAssertTrue(s.preview); XCTAssertFalse(s.converted); XCTAssertEqual(s.context.window.confetti,0); XCTAssertEqual(s.context.window.messages,["Error"]) }
    func testChannelWaitsAndUsesChannelApi() { let s = Screen(peer:TelegramChannel(20)); s.apply(); XCTAssertEqual(s.context.engine.peers.targets,[20]); XCTAssertTrue(s.context.engine.accountData.requests.isEmpty); XCTAssertTrue(s.preview); s.pending!.complete(); XCTAssertFalse(s.preview); XCTAssertEqual(s.context.window.confetti,1) }
    func testChannelFailureDoesNotCelebrate() { let s = Screen(peer:TelegramChannel(20)); s.apply(); s.pending!.reject(.generic); XCTAssertTrue(s.preview); XCTAssertEqual(s.context.window.confetti,0); XCTAssertEqual(s.context.window.messages,["Error"]) }
    func testMissingOwnerCannotFallBackToAccount() { let s = Screen(); s.mutate { $0.owner = nil }; s.apply(); XCTAssertNil(s.pending); XCTAssertTrue(s.preview); XCTAssertEqual(s.context.window.confetti,0) }
    func testForeignUserCannotChangePersonalStatus() { let s = Screen(peer:TelegramUser(2)); s.apply(); XCTAssertNil(s.pending); XCTAssertEqual(s.context.window.messages,["Error"]); XCTAssertTrue(s.preview) }
    func testUnsupportedPeerCannotChangePersonalStatus() { let s = Screen(peer:Peer(1)); s.apply(); XCTAssertNil(s.pending); XCTAssertTrue(s.preview) }
    func testChangedOwnerRejectsOldPreview() { let s = Screen(); s.mutate { $0.owner = EnginePeer(TelegramChannel(20)) }; s.apply(); XCTAssertNil(s.pending); XCTAssertTrue(s.preview) }
    func testChangedGiftRejectsOldPreview() { let s = Screen(); s.mutate { $0.gift = .unique(.init(200)) }; s.apply(); XCTAssertNil(s.pending); XCTAssertTrue(s.preview) }
    func testGiftOwnershipMustMatchTarget() { let s = Screen(gift:.init(owner:.peerId(2))); s.apply(); XCTAssertNil(s.pending); XCTAssertTrue(s.preview) }
    func testHostedGiftUsesHostAccount() { let s = Screen(gift:.init(owner:.address("wallet"),host:1)); s.apply(); XCTAssertEqual(s.context.engine.accountData.gifts,[100]); s.pending!.complete(); XCTAssertEqual(s.context.window.confetti,1) }
    func testHostedGiftUsesHostChannel() { let s = Screen(peer:TelegramChannel(20),gift:.init(owner:.name("owner"),host:20)); s.apply(); XCTAssertEqual(s.context.engine.peers.targets,[20]); XCTAssertTrue(s.context.engine.accountData.requests.isEmpty) }
    func testUnhostedExternalGiftCannotBeWorn() { let s = Screen(gift:.init(owner:.address("wallet"))); s.apply(); XCTAssertNil(s.pending); XCTAssertEqual(s.context.window.messages,["Error"]) }
    func testWearDoesNotRequireLoadedStarsBalance() { let s = Screen(); s.mutate { $0.starsState = nil }; s.apply(); XCTAssertNotNil(s.pending) }
    func testDuplicateClicksCoalesce() { let s = Screen(); s.apply(); s.apply(); XCTAssertEqual(s.context.engine.accountData.requests.count,1) }
    func testFailureAllowsRetry() { let s = Screen(); s.apply(); s.pending!.reject(.generic); s.apply(); XCTAssertEqual(s.context.engine.accountData.requests.count,2); s.pending!.complete(); XCTAssertEqual(s.context.window.confetti,1) }
    func testProgressCancelIsSilentAndRetryable() { let s = Screen(); s.apply(); Progress.pending.first?.dispose(); Queue.main.drain(); XCTAssertTrue(s.preview); XCTAssertEqual(s.context.window.confetti,0); XCTAssertTrue(s.context.window.messages.isEmpty); s.apply(); XCTAssertEqual(s.context.engine.accountData.requests.count,2) }
    func testCloseCancelsAndSuppressesFeedback() { let s = Screen(); s.apply(); let q = s.pending!; s.controller!.close(); XCTAssertTrue(q.disposed); q.complete(); XCTAssertTrue(s.preview); XCTAssertEqual(s.context.window.confetti,0) }
    func testClosedScreenCannotStartNewRequest() { let s = Screen(); s.controller!.close(); s.apply(); XCTAssertNil(s.pending) }
    func testReappearanceAllowsNewAttempt() { let s = Screen(); s.apply(); let first = s.pending!; s.controller!.close(); s.controller!.view.window = s.context.window; s.controller!.willAppear?(s.controller!); s.apply(); XCTAssertEqual(s.context.engine.accountData.requests.count,2); XCTAssertTrue(first.disposed) }
    func testDismissPreviewCancelsPendingWear() { let s = Screen(); s.apply(); let q = s.pending!; s.dismissPreview?(); XCTAssertTrue(q.disposed); q.complete(); XCTAssertEqual(s.context.window.confetti,0) }
    func testChangedSourceSuppressesAcceptedCallback() { let s = Screen(); s.apply(); s.mutate { $0.source = .other }; s.pending!.complete(); XCTAssertFalse(s.converted); XCTAssertEqual(s.context.window.confetti,0) }
    func testChangedOwnerSuppressesAcceptedCallback() { let s = Screen(); s.apply(); s.mutate { $0.owner = EnginePeer(TelegramUser(2)) }; s.pending!.complete(); XCTAssertTrue(s.preview); XCTAssertEqual(s.context.window.confetti,0) }
    func testChangedGiftSuppressesAcceptedCallback() { let s = Screen(); s.apply(); s.mutate { $0.gift = .unique(.init(200)) }; s.pending!.complete(); XCTAssertTrue(s.preview); XCTAssertEqual(s.context.window.confetti,0) }
    func testWindowChangeSuppressesFeedback() { let s = Screen(); s.apply(); let new = Window(); s.controller!.view.window = new; s.pending!.complete(); XCTAssertTrue(s.preview); XCTAssertEqual(s.context.window.confetti,0); XCTAssertEqual(new.confetti,0) }
    func testControllerReleaseCancelsAndDoesNotLeak() { let s = Screen(); weak var weakController = s.controller; s.apply(); let q = s.pending!; s.controller = nil; XCTAssertNil(weakController); XCTAssertTrue(q.disposed); q.complete(); XCTAssertEqual(s.context.window.confetti,0) }
    func testScreenReleaseReleasesContext() { var s: Screen? = Screen(); let engine = s!.context.engine; weak var context = s!.context; weak var controller = s!.controller; s!.apply(); s = nil; XCTAssertNil(controller); XCTAssertNil(context); XCTAssertTrue(engine.accountData.requests[0].disposed) }
    func testOldCleanupDoesNotCancelNewRetry() { let s = Screen(); s.apply(); s.pending!.reject(.generic); s.apply(); Queue.main.drain(); s.apply(); XCTAssertEqual(s.context.engine.accountData.requests.count,2); XCTAssertFalse(s.pending!.disposed) }
    func testSynchronousAcceptanceStillDisposes() { let s = Screen(); s.context.engine.accountData.onSubscribe = { $0.complete() }; s.apply(); XCTAssertTrue(s.converted); XCTAssertEqual(s.context.window.confetti,1); XCTAssertTrue(s.pending!.disposed) }
    func testSynchronousRejectionKeepsPreview() { let s = Screen(); s.context.engine.accountData.onSubscribe = { $0.reject(.generic) }; s.apply(); XCTAssertTrue(s.preview); XCTAssertEqual(s.context.window.messages,["Error"]) }
    func testDuplicateTerminalDoesNotRepeatConfetti() { let s = Screen(); s.apply(); let q = s.pending!; q.complete(); q.complete(); q.reject(.generic); XCTAssertEqual(s.context.window.confetti,1); XCTAssertTrue(s.context.window.messages.isEmpty) }
    func testCloseDuringDisposalSuppressesSuccess() { let s = Screen(); s.apply(); s.pending!.onDispose = { [weak s] in s?.controller?.close() }; s.pending!.complete(); XCTAssertTrue(s.preview); XCTAssertEqual(s.context.window.confetti,0) }
    func testCloseDuringStateUpdateSuppressesConfetti() { let s = Screen(); s.apply(); s.observer.onUpdate = { [weak s] in s?.controller?.close() }; s.pending!.complete(); XCTAssertTrue(s.converted); XCTAssertEqual(s.context.window.confetti,0) }
    func testNonPremiumShowsOfferWithoutMutation() { let c = Context(); c.isPremium = false; let peer = TelegramUser(1); peer.isPremium = false; let s = Screen(context:c,peer:peer); s.apply(); XCTAssertNil(s.pending); XCTAssertTrue(s.preview); XCTAssertEqual(c.window.messages,["Premium"]); c.window.callbacks.first?(""); XCTAssertEqual(c.window.premium,1) }
    func testPremiumEligibilityUsesCurrentContext() { let c = Context(); c.isPremium = false; let s = Screen(context:c); s.apply(); XCTAssertNil(s.pending); XCTAssertEqual(c.window.messages,["Premium"]) }
    func testPremiumCallbackAfterCloseIsIgnored() { let c = Context(); c.isPremium = false; let peer = TelegramUser(1); peer.isPremium = false; let s = Screen(context:c,peer:peer); s.apply(); s.controller!.close(); c.window.callbacks.first?(""); XCTAssertEqual(c.window.premium,0) }
    func testBoostLookupOwnedAndCoalesced() { let peer = TelegramChannel(20); peer.approximateBoostLevel = 0; let s = Screen(peer:peer); s.apply(); s.apply(); XCTAssertEqual(s.context.engine.peers.boosts.count,1); XCTAssertNil(s.pending); s.controller!.close(); XCTAssertTrue(s.context.engine.peers.boosts[0].disposed); XCTAssertTrue(s.context.engine.peers.mine[0].disposed) }
    func testBoostFailureKeepsPreviewAndReportsError() { let peer = TelegramChannel(20); peer.approximateBoostLevel = 0; let s = Screen(peer:peer); s.apply(); s.context.engine.peers.boosts[0].send(nil); s.context.engine.peers.mine[0].send(nil); XCTAssertEqual(s.context.window.messages,["Error"]); XCTAssertTrue(s.preview); XCTAssertEqual(s.context.window.confetti,0) }
    func testEmptyBoostLookupReportsFailure() { let peer = TelegramChannel(20); peer.approximateBoostLevel = 0; let s = Screen(peer:peer); s.apply(); s.context.engine.peers.boosts[0].complete(); s.context.engine.peers.mine[0].complete(); XCTAssertEqual(s.context.window.messages,["Error"]); XCTAssertTrue(s.preview) }
    func testBoostPromptPreservesMorphAndDoesNotApply() { let peer = TelegramChannel(20); peer.approximateBoostLevel = 0; let s = Screen(peer:peer); s.apply(); ModalMorphContextSource.current = 99; s.context.engine.peers.boosts[0].send(.init(level:0)); s.context.engine.peers.mine[0].send(.init(count:1)); XCTAssertEqual(s.context.window.boost,1); XCTAssertEqual(s.context.window.boostMorph,42); XCTAssertTrue(s.preview); XCTAssertNil(s.pending) }
    func testLateBoostReplyAfterCloseIsIgnored() { let peer = TelegramChannel(20); peer.approximateBoostLevel = 0; let s = Screen(peer:peer); s.apply(); s.controller!.close(); s.context.engine.peers.boosts[0].send(.init(level:0)); s.context.engine.peers.mine[0].send(nil); XCTAssertEqual(s.context.window.boost,0) }
    func testPremiumCallbackAfterLeavingPreviewIsIgnored() { let c = Context(); c.isPremium = false; let peer = TelegramUser(1); peer.isPremium = false; let s = Screen(context:c,peer:peer); s.apply(); s.dismissPreview?(); c.window.callbacks.first?(""); XCTAssertEqual(c.window.premium,0) }
    func testPremiumToastDoesNotKeepContextAlive() { var s: Screen? = Screen(); s!.context.isPremium = false; s!.stateValue.with { $0.owner!._asPeer().isPremium = false }; let window = s!.context.window; weak var context = s!.context; weak var controller = s!.controller; s!.apply(); s = nil; XCTAssertNil(controller); XCTAssertNil(context); window.callbacks.first?(""); XCTAssertEqual(window.premium,0) }

    func testClosedMissingOwnerDoesNotShowErrorInFallbackWindow() { let s = Screen(); s.mutate { $0.owner = nil }; s.controller!.close(); s.apply(); XCTAssertTrue(s.context.window.messages.isEmpty); XCTAssertNil(s.pending) }
    func testDetachedMissingOwnerDoesNotShowErrorInFallbackWindow() { let s = Screen(); s.mutate { $0.owner = nil }; s.controller!.view.window = nil; s.apply(); XCTAssertTrue(s.context.window.messages.isEmpty); XCTAssertNil(s.pending) }

}
