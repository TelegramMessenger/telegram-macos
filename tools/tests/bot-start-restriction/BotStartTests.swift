import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int64
struct ContentSettings { var ignoreContentRestrictionReasons: Set<String> = [] }

final class Peer {
    let id: PeerId
    let isBot = true
    var restriction: (reason: String, text: String)?
    init(id: PeerId) { self.id = id }
    func restrictionText(_ contentSettings: ContentSettings?) -> String? {
        guard let restriction else { return nil }
        if let contentSettings, contentSettings.ignoreContentRestrictionReasons.contains(restriction.reason) { return nil }
        return restriction.text
    }
}

enum ChatInitialActionBehavior: Equatable { case none, automatic }
enum ChatInitialAction: Equatable {
    case start(parameter: String, behavior: ChatInitialActionBehavior)
    case inputText(text: String, behavior: ChatInitialActionBehavior)
}

struct Message { let id: Int; var requestsSetupReply = false }
struct ReplySubject { let messageId: Int; let quote: String?; let innerSubject: Int? }
struct InterfaceState {
    var dismissedForceReplyId: Int?
    var replyMessageId: ReplySubject?
    func withUpdatedReplyMessageId(_ value: ReplySubject?) -> InterfaceState { var result = self; result.replyMessageId = value; return result }
}

struct ChatPresentationInterfaceState {
    var initialAction: ChatInitialAction?
    var historyCount: Int?
    var monoforumState: Int?
    var interfaceState = InterfaceState()
    var keyboardButtonsMessage: Message?
    func updatedInitialAction(_ value: ChatInitialAction?) -> Self { var result = self; result.initialAction = value; return result }
    func withoutInitialAction() -> Self { updatedInitialAction(nil) }
    func updatedHistoryCount(_ value: Int?) -> Self { var result = self; result.historyCount = value; return result }
    func updatedKeyboardButtonsMessage(_ value: Message?) -> Self { var result = self; result.keyboardButtonsMessage = value; return result }
    func updatedInterfaceState(_ f: (InterfaceState) -> InterfaceState) -> Self { var result = self; result.interfaceState = f(interfaceState); return result }
}

final class Server {
    var messages: [Int] = []
    var sentStarts: [String] = []
    func receive() { messages.append(messages.count + 1) }
    func requestStartBot(botPeerId: PeerId, payload: String?) -> Signal<Void, NoError> {
        return Signal { subscriber in
            self.sentStarts.append(payload ?? "")
            self.receive()
            self.receive()
            subscriber.putCompletion()
            return EmptyDisposable
        }
    }
}
final class EngineMessages {
    let server: Server
    init(server: Server) { self.server = server }
    func requestStartBot(botPeerId: PeerId, payload: String?) -> Signal<Void, NoError> { server.requestStartBot(botPeerId: botPeerId, payload: payload) }
}
final class Engine { let messages: EngineMessages; init(server: Server) { messages = EngineMessages(server: server) } }
final class Context { let engine: Engine; var contentSettings = ContentSettings(); init(server: Server) { engine = Engine(server: server) } }

final class ChatInteraction {
    let context: Context
    let peerId: PeerId
    var peer: Peer?
    private(set) var presentation = ChatPresentationInterfaceState()
    let startBotDisposable = MetaDisposable()
    init(context: Context, peerId: PeerId) { self.context = context; self.peerId = peerId }
    func update(animated: Bool = true, _ f: (ChatPresentationInterfaceState) -> ChatPresentationInterfaceState) { presentation = f(presentation) }

__START_BOT__
    func invokeInitialAction(includeAuto: Bool = false, animated: Bool = true, action: ChatInitialAction? = nil) {
        if let action = action ?? presentation.initialAction {
            switch action {
__START_CASE__
            default:
                break
            }
        }
    }
}

enum ViewState { case visible, progress }
final class TableView { var isEmpty = true }
final class GenericView { let tableView = TableView(); var state = ViewState.progress }
final class CenterBarView { var animates = false }
struct OriginalView { let entries: [Int] }
struct ProcessedView { let originalView: OriginalView? }
struct InitialData { var buttonKeyboardMessage: Message? = nil }

final class ChatController {
    let context: Context
    let chatInteraction: ChatInteraction
    let genericView = GenericView()
    let centerBarView = CenterBarView()
    init(context: Context, chatInteraction: ChatInteraction) { self.context = context; self.chatInteraction = chatInteraction }
    func readyHistory() {}
    func updateInteractiveReading() {}
    func peerDidLoad() { updateEmptyBotStartAction() }

__EMPTY_BOT_START__
    func applyTransitionTail(processedView: ProcessedView, initialData: InitialData, wasEmpty: Bool) {
__APPLY_TRANSITION_TAIL__
    }
}

final class Harness {
    let server = Server()
    let peer = Peer(id: 1)
    let controller: ChatController
    var hidesHistory = false
    var transitions = 0

    init(restricted: Bool, history: Int, initialAction: ChatInitialAction? = nil, peerLoaded: Bool = true) {
        let context = Context(server: server)
        let chatInteraction = ChatInteraction(context: context, peerId: peer.id)
        if peerLoaded {
            chatInteraction.peer = peer
        }
        controller = ChatController(context: context, chatInteraction: chatInteraction)
        if restricted {
            peer.restriction = (reason: "porn", text: "This bot violated App Store rules")
        }
        for _ in 0 ..< history { server.receive() }
        chatInteraction.update(animated: false, { $0.updatedInitialAction(initialAction) })
    }

    var presentation: ChatPresentationInterfaceState { controller.chatInteraction.presentation }

    func transition() {
        transitions += 1
        let wasEmpty = controller.genericView.tableView.isEmpty
        let filtered = peer.restrictionText(controller.context.contentSettings) != nil || hidesHistory
        controller.genericView.tableView.isEmpty = filtered || server.messages.isEmpty
        controller.genericView.state = .visible
        controller.applyTransitionTail(processedView: ProcessedView(originalView: OriginalView(entries: server.messages)), initialData: InitialData(), wasEmpty: wasEmpty)
    }

    func settle(limit: Int = 60) {
        for _ in 0 ..< limit {
            let count = server.messages.count
            transition()
            if server.messages.count == count { return }
        }
    }

    func loadPeer() {
        controller.chatInteraction.peer = peer
        controller.peerDidLoad()
    }

    func pressStart() {
        controller.chatInteraction.invokeInitialAction()
        settle()
    }
}

final class BotStartTests: XCTestCase {
    func testRestrictedBotWithHistoryNeverSendsStartByItself() {
        let harness = Harness(restricted: true, history: 2)
        harness.settle()
        XCTAssertEqual(harness.server.sentStarts, [])
        XCTAssertNil(harness.presentation.initialAction)
        XCTAssertEqual(harness.presentation.historyCount, 2)
    }

    func testRestrictedBotStaysQuietWhileItKeepsWriting() {
        let harness = Harness(restricted: true, history: 2)
        harness.settle()
        for _ in 0 ..< 5 {
            harness.server.receive()
            harness.settle()
        }
        XCTAssertEqual(harness.server.sentStarts, [])
        XCTAssertEqual(harness.server.messages.count, 7)
    }

    func testRestrictedBotResolvedAfterHistoryNeverSendsStart() {
        let harness = Harness(restricted: true, history: 2, peerLoaded: false)
        harness.settle()
        harness.loadPeer()
        harness.settle()
        XCTAssertEqual(harness.server.sentStarts, [])
        XCTAssertNil(harness.presentation.initialAction)
    }

    func testEmptyBotResolvedAfterHistoryOffersStart() {
        let harness = Harness(restricted: false, history: 0, peerLoaded: false)
        harness.settle()
        harness.loadPeer()
        XCTAssertEqual(harness.presentation.initialAction, .start(parameter: "", behavior: .none))
        harness.settle()
        XCTAssertEqual(harness.server.sentStarts, [])
    }

    func testRestrictedBotWithoutHistoryOffersNoStart() {
        let harness = Harness(restricted: true, history: 0)
        harness.settle()
        XCTAssertEqual(harness.server.sentStarts, [])
        XCTAssertNil(harness.presentation.initialAction)
    }

    func testIgnoredRestrictionBehavesLikeNormalBot() {
        let harness = Harness(restricted: true, history: 0)
        harness.controller.context.contentSettings.ignoreContentRestrictionReasons = ["porn"]
        harness.settle()
        XCTAssertEqual(harness.presentation.initialAction, .start(parameter: "", behavior: .none))
        XCTAssertEqual(harness.server.sentStarts, [])
    }

    func testHiddenHistoryOfUnrestrictedBotNeverSendsStartByItself() {
        let harness = Harness(restricted: false, history: 2)
        harness.hidesHistory = true
        harness.settle()
        XCTAssertEqual(harness.server.sentStarts, [])
    }

    func testHiddenSingleMessageStillOffersStart() {
        let harness = Harness(restricted: false, history: 1)
        harness.hidesHistory = true
        harness.settle()
        XCTAssertEqual(harness.presentation.initialAction, .start(parameter: "", behavior: .none))
        XCTAssertEqual(harness.server.sentStarts, [])
    }

    func testEmptyBotChatOffersStartAndSendsOnlyWhenPressed() {
        let harness = Harness(restricted: false, history: 0)
        harness.settle()
        XCTAssertEqual(harness.presentation.initialAction, .start(parameter: "", behavior: .none))
        XCTAssertEqual(harness.server.sentStarts, [])
        harness.pressStart()
        XCTAssertEqual(harness.server.sentStarts, [""])
        XCTAssertNil(harness.presentation.initialAction)
        harness.server.receive()
        harness.settle()
        XCTAssertEqual(harness.server.sentStarts, [""])
    }

    func testStartLinkIntoExistingChatSendsOnce() {
        let harness = Harness(restricted: false, history: 2, initialAction: .start(parameter: "ref", behavior: .none))
        harness.settle()
        XCTAssertEqual(harness.server.sentStarts, ["ref"])
        XCTAssertNil(harness.presentation.initialAction)
    }

    func testStartLinkIntoNewChatWaitsForPress() {
        let harness = Harness(restricted: false, history: 0, initialAction: .start(parameter: "ref", behavior: .none))
        harness.settle()
        XCTAssertEqual(harness.server.sentStarts, [])
        harness.pressStart()
        XCTAssertEqual(harness.server.sentStarts, ["ref"])
    }

    func testAutomaticStartSendsOnce() {
        let harness = Harness(restricted: false, history: 0, initialAction: .start(parameter: "x", behavior: .automatic))
        harness.settle()
        XCTAssertEqual(harness.server.sentStarts, ["x"])
    }

    func testStartLinkIntoRestrictedBotWithHistorySendsOnce() {
        let harness = Harness(restricted: true, history: 2, initialAction: .start(parameter: "ref", behavior: .none))
        harness.settle()
        XCTAssertEqual(harness.server.sentStarts, ["ref"])
        harness.server.receive()
        harness.settle()
        XCTAssertEqual(harness.server.sentStarts, ["ref"])
    }
}
