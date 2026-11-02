import Foundation
import SwiftSignalKit
import XCTest

final class Window { var messages: [String] = []; var onMessage: (() -> Void)? }
struct Strings { let emojiContextSetStatus = "Set status"; let emojiContextSetStatusSuccess = "Success"; let unknownError = "Error" }
func strings() -> Strings { Strings() }
func showModalText(for window: Window, text: String) { window.messages.append(text); window.onMessage?() }
final class Queue {
    static let main = Queue(); var jobs: [() -> Void] = []
    static func mainQueue() -> Queue { main }
    func justDispatch(_ f: @escaping () -> Void) { jobs.append(f) }
    func drain() { while !jobs.isEmpty { jobs.removeFirst()() } }
}
func deliverOnMainQueue<T, E>(_ signal: Signal<T, E>) -> Signal<T, E> { signal }
final class Progress {
    static var pending: [MetaDisposable] = []
    static func reset() { pending.forEach { $0.dispose() }; pending.removeAll() }
}
func showModalProgress<T, E>(signal: Signal<T, E>, for window: Window, shouldPresent: @escaping () -> Bool = { true }) -> Signal<T, E> {
    Signal { subscriber in
        let pending = MetaDisposable()
        Progress.pending.append(pending)
        pending.set(signal.start(next: { subscriber.putNext($0) }, error: { subscriber.putError($0) }, completed: { subscriber.putCompletion() }))
        return pending
    }
}
final class TelegramMediaFile { var isCustomEmoji: Bool; let id: Int; init(_ id: Int = 10, custom: Bool = true) { self.id = id; isCustomEmoji = custom } }
enum SetEmojiStatusError { case generic }
final class Request {
    let subscriber: Subscriber<Never, SetEmojiStatusError>; let file: TelegramMediaFile?; let expiry: Int32?
    var disposed = false; var onDispose: (() -> Void)?
    init(_ subscriber: Subscriber<Never, SetEmojiStatusError>, file: TelegramMediaFile?, expiry: Int32?) { self.subscriber = subscriber; self.file = file; self.expiry = expiry }
    func accept() { subscriber.putCompletion() }
    func reject() { subscriber.putError(.generic) }
    func dispose() { if !disposed { disposed = true; onDispose?() } }
}
final class AccountData {
    var requests: [Request] = []; var onSubscribe: ((Request) -> Void)?
    func requestEmojiStatus(file: TelegramMediaFile?, expirationDate: Int32?) -> Signal<Never, SetEmojiStatusError> {
        Signal { subscriber in
            let request = Request(subscriber, file: file, expiry: expirationDate)
            self.requests.append(request)
            self.onSubscribe?(request)
            return ActionDisposable { request.dispose() }
        }
    }
    func setEmojiStatus(file: TelegramMediaFile?, expirationDate: Int32?) -> Signal<Never, NoError> { requestEmojiStatus(file: file, expirationDate: expirationDate) |> `catch` { _ in .complete() } }
}
final class Engine { let accountData = AccountData() }
protocol AccountContextProtocol: AnyObject { var engine: Engine { get }; var window: Window { get }; var isPremium: Bool { get } }
final class Context: AccountContextProtocol { let engine = Engine(); var window = Window(); var isPremium = true }
__HELPER__
struct MenuAnimation { static let menu_smile = MenuAnimation(); let value = 0 }
final class ContextMenuItem { let handler: () -> Void; init(_ text: String, handler: @escaping () -> Void, itemImage: Int) { self.handler = handler } }
class RowView {}
final class EmojiesSectionRowView: RowView { struct Item { let file: TelegramMediaFile }; var itemUnderMouse: (Item, Int)? = (.init(file: TelegramMediaFile()), 0) }
final class Row {
    enum Mode: CaseIterable { case panel, preview, statuses }
    let context: Context; var view: RowView? = EmojiesSectionRowView(); var mode = Mode.panel
    private let emojiStatusAction = EmojiStatusMenuAction()
    init(_ context: Context) { self.context = context }
    func menu() -> ContextMenuItem? {
        let context = self.context
        var setStatus: ContextMenuItem?
        __MENU__
        return setStatus
    }
}
final class EmojiStatusMenuTests: XCTestCase {
    override func tearDown() { Progress.reset(); Queue.main.drain() }
    func testWaitsForCompletion() { let c = Context(); let r = Row(c); r.menu()!.handler(); XCTAssertTrue(c.window.messages.isEmpty); XCTAssertEqual(c.engine.accountData.requests.count, 1); c.engine.accountData.requests[0].accept(); XCTAssertEqual(c.window.messages, ["Success"]) }
    func testDuplicateClicksSharePendingRequest() { let c = Context(); let r = Row(c); let menu = r.menu()!; menu.handler(); menu.handler(); XCTAssertEqual(c.engine.accountData.requests.count, 1) }
    func testNewChoiceAfterCompletion() { let c = Context(); let r = Row(c); let menu = r.menu()!; menu.handler(); c.engine.accountData.requests[0].accept(); menu.handler(); XCTAssertEqual(c.engine.accountData.requests.count, 2); c.engine.accountData.requests[1].accept(); XCTAssertEqual(c.window.messages, ["Success", "Success"]) }
    func testOldDisposalCannotClearNewRequest() { let c = Context(); let r = Row(c); let menu = r.menu()!; menu.handler(); c.engine.accountData.requests[0].accept(); menu.handler(); Queue.main.drain(); menu.handler(); XCTAssertEqual(c.engine.accountData.requests.count, 2) }
    func testProgressCancellationIsSilentAndRetryable() { let c = Context(); let r = Row(c); let menu = r.menu()!; menu.handler(); XCTAssertEqual(Progress.pending.count, 1); Progress.pending.first?.dispose(); Queue.main.drain(); menu.handler(); XCTAssertEqual(c.engine.accountData.requests.count, 2); XCTAssertFalse(c.engine.accountData.requests[0].disposed); XCTAssertTrue(c.window.messages.isEmpty) }
    func testLateSuccessAfterCancellationIsIgnored() { let c = Context(); let r = Row(c); r.menu()!.handler(); Progress.pending.first?.dispose(); Queue.main.drain(); c.engine.accountData.requests[0].accept(); XCTAssertTrue(c.window.messages.isEmpty) }
    func testRowReleaseKeepsRequest() { let c = Context(); var r: Row? = Row(c); weak var weakRow = r; r!.menu()!.handler(); r = nil; XCTAssertNil(weakRow); XCTAssertFalse(c.engine.accountData.requests[0].disposed); c.engine.accountData.requests[0].accept(); XCTAssertTrue(c.window.messages.isEmpty) }
    func testRetainedMenuDoesNotKeepRowOrContextAlive() { var c: Context? = Context(); var r: Row? = Row(c!); weak var weakContext = c; weak var weakRow = r; let menu = r!.menu()!; r = nil; c = nil; XCTAssertNil(weakRow); XCTAssertNil(weakContext); menu.handler() }
    func testPendingRequestDoesNotKeepContextAlive() { var c: Context? = Context(); var r: Row? = Row(c!); let engine = c!.engine; weak var weakContext = c; r!.menu()!.handler(); r = nil; c = nil; XCTAssertNil(weakContext); XCTAssertFalse(engine.accountData.requests[0].disposed) }
    func testWindowReplacementSuppressesFeedback() { let c = Context(); let r = Row(c); let old = c.window; r.menu()!.handler(); c.window = Window(); c.engine.accountData.requests[0].accept(); XCTAssertTrue(old.messages.isEmpty); XCTAssertTrue(c.window.messages.isEmpty) }
    func testPremiumIsCheckedAtInvocation() { let c = Context(); let r = Row(c); let menu = r.menu()!; c.isPremium = false; menu.handler(); XCTAssertTrue(c.engine.accountData.requests.isEmpty) }
    func testNonPremiumHasNoMenuAction() { let c = Context(); c.isPremium = false; XCTAssertNil(Row(c).menu()) }
    func testPanelAndPreviewOfferAction() { let r = Row(Context()); for mode in [Row.Mode.panel, .preview] { r.mode = mode; XCTAssertNotNil(r.menu()) }; r.mode = .statuses; XCTAssertNil(r.menu()) }
    func testBuiltinEmojiHasNoStatusAction() { let r = Row(Context()); (r.view as! EmojiesSectionRowView).itemUnderMouse = (.init(file: TelegramMediaFile(custom: false)), 0); XCTAssertNil(r.menu()) }
    func testFileRevalidatedAtInvocation() { let c = Context(); let r = Row(c); let file = (r.view as! EmojiesSectionRowView).itemUnderMouse!.0.file; let menu = r.menu()!; file.isCustomEmoji = false; menu.handler(); XCTAssertTrue(c.engine.accountData.requests.isEmpty) }
    func testExactFileAndIndefiniteExpiration() { let c = Context(); let r = Row(c); r.menu()!.handler(); XCTAssertEqual(c.engine.accountData.requests[0].file?.id, 10); XCTAssertNil(c.engine.accountData.requests[0].expiry) }
    func testSynchronousSuccessAllowsNextChoice() { let c = Context(); let r = Row(c); c.engine.accountData.onSubscribe = { $0.accept() }; let menu = r.menu()!; menu.handler(); menu.handler(); XCTAssertEqual(c.window.messages, ["Success", "Success"]); XCTAssertTrue(c.engine.accountData.requests.allSatisfy { $0.disposed }) }
    func testDuplicateTerminalEventsDoNotRepeatToast() { let c = Context(); let r = Row(c); r.menu()!.handler(); let q = c.engine.accountData.requests[0]; q.accept(); q.accept(); q.reject(); XCTAssertEqual(c.window.messages, ["Success"]) }
    func testCompletedRequestIsReleased() { let c = Context(); let a = EmojiStatusMenuAction(); a.perform(context: c, file: TelegramMediaFile(), window: c.window, canPresent: { true }); c.engine.accountData.requests[0].accept(); XCTAssertTrue(c.engine.accountData.requests[0].disposed); XCTAssertEqual(c.window.messages, ["Success"]) }
    func testResetDuringPresentationCheckSuppressesFeedback() { let c = Context(); let a = EmojiStatusMenuAction(); var checks = 0; a.perform(context: c, file: TelegramMediaFile(), window: c.window, canPresent: { checks += 1; if checks > 1 { a.reset() }; return true }); c.engine.accountData.requests[0].accept(); XCTAssertTrue(c.window.messages.isEmpty) }
    func testReentrantNewRequestSurvivesOldCompletion() { let c = Context(); let a = EmojiStatusMenuAction(); var checks = 0; a.perform(context: c, file: TelegramMediaFile(), window: c.window, canPresent: { checks += 1; if checks == 2 { a.reset(); a.perform(context: c, file: TelegramMediaFile(20), window: c.window, canPresent: { true }) }; return true }); c.engine.accountData.requests[0].accept(); Queue.main.drain(); XCTAssertEqual(c.engine.accountData.requests.count, 2); XCTAssertFalse(c.engine.accountData.requests[1].disposed); XCTAssertTrue(c.window.messages.isEmpty); c.engine.accountData.requests[1].accept(); XCTAssertEqual(c.window.messages, ["Success"]) }
    func testUnavailablePresentationDoesNotStart() { let c = Context(); let a = EmojiStatusMenuAction(); a.perform(context: c, file: TelegramMediaFile(), window: c.window, canPresent: { false }); XCTAssertTrue(c.engine.accountData.requests.isEmpty) }
}
