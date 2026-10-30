import Foundation

struct PeerId: Equatable { let raw: Int; init(_ raw: Int) { self.raw = raw }; init(_ raw: Int64) { self.raw = Int(raw) } }
struct MessageId: Equatable { let peerId: PeerId; let id: Int }
struct Thread { let peerId: PeerId; let channelMessageId: MessageId?; var isMonoforumPost = false; var threadId: Int64 = 0 }
enum ChatLocation { case peer(PeerId); case thread(Thread); var threadId: Int64? { if case let .thread(thread) = self { return thread.threadId }; return nil } }
enum ReplyThreadMode { case comments(origin: MessageId); case replies(origin: MessageId); case topic(origin: MessageId); case savedMessages(origin: MessageId) }
enum ChatMode: Equatable {
    case history, other, preview, thread(ReplyThreadMode)
    static func == (lhs: ChatMode, rhs: ChatMode) -> Bool { if case .history = lhs, case .history = rhs { return true }; return false }
    var isSavedMessagesThread: Bool { if case .thread(.savedMessages) = self { return true }; return false }
}
let repliesPeerId = PeerId(99)
final class Navigation {
    var isLocked = false
    var pushes = 0
    var controllers: [Controller] = []
    var controller: Controller { controllers.last! }
    func push(_ value: Int) { pushes += 1 }
    func enumerateControllers(_ body: (Controller, Int) -> Bool) {
        for index in controllers.indices.reversed() { if body(controllers[index], index) { break } }
    }
    func to(index: Int) { controllers = Array(controllers.prefix(index + 1)) }
}
final class Bindings { let navigation = Navigation(); func rootNavigation() -> Navigation { navigation } }
final class Context { let peerId = PeerId(1); let bindings = Bindings() }
struct Presentation { var reportMode: Int?; var isTopicMode = false }
struct Hook {
    func makePeerMediaController(_ context: Context, _ id: PeerId, _ value: Bool) -> Int { 0 }
    func makePeerMediaControllerObserved(_ context: Context, _ id: PeerId, isBot: Bool) -> Int { 0 }
    func pushPeerInfoObserved(_ navigation: Navigation, _ context: Context, _ peer: PeerId, _ info: ThreadInfo?, _ stories: Int?, _ media: Int?, _ album: Int?) {}
}
struct ThreadInfo { init(message: Thread, isChannelPost: Bool, isMonoforumPost: Bool, isEmpty: Bool, contextHolder: Int) {} }
enum Message { static let newTopicThreadId: Int64 = -1 }
final class Modal { func close() {} }
class Controller {
 var modal: Modal?
 var recording = false
 var pending: ((Controller, Bool) -> Void)?
 var target: Controller?
 func ableToNextController(_ controller: Controller, _ completion: @escaping (Controller, Bool)->Void) {
  if recording { target=controller; pending=completion } else { completion(controller,true) }
 }
 func answer(_ approved: Bool) {
  let callback=pending; pending=nil
  if let target { callback?(target,approved) }
 }
}
typealias ViewController = Controller
protocol ChatControllerKind: AnyObject { var chatInteraction: ChatInteraction { get } }
final class ChatController: Controller, ChatControllerKind {
    let chatInteraction: ChatInteraction
    init(_ interaction: ChatInteraction) { chatInteraction = interaction }
}
struct FocusTarget { let messageId: MessageId; let string: String? }
enum ScrollState { case CenterEmpty }
let navigationController: Controller? = nil
let chatLocationContextHolder = 0
let context = Context()
struct ChatUIHooks { static let shared = Hook() }
final class ChatInteraction {
    let interactionContext = Context()
    var mode: ChatMode
    var chatLocation: ChatLocation
    var peerId: PeerId
    var presentation = Presentation()
    var calls: [(PeerId, Bool, MessageId?)] = []
    var focused: [MessageId] = []
    func focusMessageId(_ from: MessageId?, _ target: FocusTarget, _ state: ScrollState) { focused.append(target.messageId) }
    init(_ mode: ChatMode, _ location: ChatLocation, _ peerId: PeerId) { self.mode = mode; self.chatLocation = location; self.peerId = peerId }
    func openInfo(_ peer: PeerId, _ toChat: Bool, _ post: MessageId?, _ action: Int?) { calls.append((peer, toChat, post)) }
    func openInfoObserved(_ peer: PeerId, _ toChat: Bool, _ post: MessageId?, _ action: Int?) { openInfo(peer, toChat, post, action) }
}

__SOURCE__

func clickLegacy(_ chatInteraction: ChatInteraction) {
__HEADER_ACTION__
    openInfo(chatInteraction)
}
func clickModern(_ chatInteraction: ChatInteraction) {
__MODERN_ACTION__
}
func click(_ chatInteraction: ChatInteraction) {
    chatInteraction.calls.removeAll()
    clickLegacy(chatInteraction)
    let legacy = chatInteraction.calls
    chatInteraction.calls.removeAll()
    clickModern(chatInteraction)
    let modern = chatInteraction.calls
    check("glass and legacy title actions agree", legacy.count == modern.count && zip(legacy, modern).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 && $0.2 == $1.2 })
}
var checked = 0
var failed = 0
func check(_ label: String, _ condition: Bool) {
    checked += 1
    if !condition { print("FAIL: " + label); failed += 1 }
}
let channel = PeerId(10)
let group = PeerId(20)
let other = PeerId(30)
let post = MessageId(peerId: channel, id: 123)
let comment = MessageId(peerId: group, id: 456)
let wrongOrigin = MessageId(peerId: other, id: 789)
let thread = ChatLocation.thread(Thread(peerId: group, channelMessageId: post))
let linked = ChatInteraction(.thread(.comments(origin: post)), thread, group)
click(linked)
check("comment link opens channel", linked.calls.first?.0 == channel)
check("opens chat rather than profile", linked.calls.first?.1 == true)
check("focuses source post", linked.calls.first?.2 == post)
let fromComment = ChatInteraction(.thread(.comments(origin: comment)), thread, group)
click(fromComment)
check("resolved source wins over comment origin", fromComment.calls.first?.2 == post)
let staleOrigin = ChatInteraction(.thread(.comments(origin: wrongOrigin)), thread, group)
click(staleOrigin)
check("thread source wins over navigation origin", staleOrigin.calls.first?.2 == post)
let fallback = ChatInteraction(.thread(.comments(origin: post)), .thread(Thread(peerId: group, channelMessageId: nil)), group)
click(fallback)
check("channel origin works before source cache", fallback.calls.first?.2 == post)
let unknown = ChatInteraction(.thread(.comments(origin: comment)), .thread(Thread(peerId: group, channelMessageId: nil)), group)
click(unknown)
check("does not jump into discussion group without source", unknown.calls.isEmpty)
for mode: ChatMode in [.thread(.replies(origin: comment)), .thread(.topic(origin: comment)), .thread(.savedMessages(origin: comment)), .other, .history] {
    check("source helper limited to comments", chatDiscussionSourceMessageId(mode: mode, location: thread) == nil)
}
check("not a thread", chatDiscussionSourceMessageId(mode: .thread(.comments(origin: post)), location: .peer(channel)) == nil)
let history = ChatInteraction(.history, .peer(channel), channel)
click(history)
check("ordinary channel opens profile", history.calls.first?.0 == channel && history.calls.first?.1 == false)
let topic = ChatInteraction(.thread(.topic(origin: comment)), thread, group)
topic.presentation.isTopicMode = true
click(topic)
check("forum topic retains profile action", topic.calls.first?.0 == group && topic.calls.first?.1 == false)
for legacy in [false, true] {
    let current = ChatInteraction(.thread(.comments(origin: post)), thread, group)
    let original = ChatInteraction(.history, .peer(channel), channel)
    let navigation = current.interactionContext.bindings.navigation
    let originalController = ChatController(original)
    navigation.controllers = [originalController, ChatController(current)]
    if legacy { clickLegacy(current) } else { clickModern(current) }
    check("same-source channel is reused", navigation.controllers.count == 1 && navigation.controllers.first === originalController)
    check("reuse focuses the original post", original.focused == [post])
    check("reuse never requests a duplicate channel push", current.calls.isEmpty)
}

for legacy in [false, true] {
 let current=ChatInteraction(.thread(.comments(origin:post)),thread,group)
 let original=ChatInteraction(.history,.peer(channel),channel)
 let navigation=current.interactionContext.bindings.navigation
 let target=ChatController(original), recording=ChatController(current)
 recording.recording=true
 navigation.controllers=[target,recording]
 if legacy { clickLegacy(current) } else { clickModern(current) }
 check("recording requests navigation confirmation", recording.pending != nil)
 check("recording remains open before confirmation", navigation.controllers.count == 2 && original.focused.isEmpty)
 recording.answer(false)
 check("cancel preserves recording and stack", navigation.controllers.last === recording && original.focused.isEmpty)
 if legacy { clickLegacy(current) } else { clickModern(current) }
 recording.answer(true)
 check("confirmed recording exit reuses channel", navigation.controllers.count == 1 && original.focused == [post])
 navigation.controllers=[target,recording]
 original.focused=[]
 if legacy { clickLegacy(current) } else { clickModern(current) }
 let replacement=Controller()
 navigation.controllers.append(replacement)
 recording.answer(true)
 check("stale confirmation cannot navigate another active page", navigation.controllers.last === replacement && original.focused.isEmpty)
}
for legacy in [false,true] {
 let current=ChatInteraction(.thread(.comments(origin:post)),thread,group)
 let original=ChatInteraction(.history,.peer(channel),channel)
 let navigation=current.interactionContext.bindings.navigation
 let target=ChatController(original), recording=ChatController(current)
 recording.recording=true
 navigation.controllers=[target,recording]; navigation.isLocked=true
 if legacy { clickLegacy(current) } else { clickModern(current) }
 check("locked transition ignores title activation",recording.pending == nil && navigation.controllers.count == 2 && original.focused.isEmpty)
 navigation.isLocked=false
 if legacy { clickLegacy(current) } else { clickModern(current) }
 navigation.isLocked=true; recording.answer(true)
 check("confirmation during a transition cannot truncate its stack",navigation.controllers.count == 2 && original.focused.isEmpty)
 navigation.isLocked=false
 if legacy { clickLegacy(current) } else { clickModern(current) }
 recording.answer(true)
 check("title reuse resumes once navigation unlocks",navigation.controllers.count == 1 && original.focused == [post])
}
print("\(checked - failed)/\(checked) discussion navigation checks passed")
exit(failed == 0 ? 0 : 1)
