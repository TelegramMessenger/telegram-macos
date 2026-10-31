import Foundation
protocol AccountContextProtocol: AnyObject { var engine: Engine { get }; var account: Account { get } }
enum NoError: Error {}
struct Signal<T, E> { let value: T; static func single(_ value: T) -> Self { Self(value: value) }; func start() {} }
precedencegroup PipePrecedence { associativity: left }
infix operator |> : PipePrecedence
func |> <A, B>(value: A, transform: (A) -> B) -> B { transform(value) }
func map<A, B, E>(_ f: @escaping (A) -> B) -> (Signal<A, E>) -> Signal<B, E> { { .single(f($0.value)) } }
func mapToSignal<A, B, E>(_ f: @escaping (A) -> Signal<B, E>) -> (Signal<A, E>) -> Signal<B, E> { { f($0.value) } }
func deliverOnMainQueue<A, E>(_ signal: Signal<A, E>) -> Signal<A, E> { signal }
struct PeerId: Equatable { let namespace: Int; let id: Int }
enum Namespaces { enum Peer { static let SecretChat = 3 } }
class Peer { let id: PeerId; var isForumOrMonoForum: Bool; init(_ id: PeerId, forum: Bool = false) { self.id=id; isForumOrMonoForum=forum } }
struct ChannelFlags: OptionSet { let rawValue: Int; static let displayForumAsTabs = ChannelFlags(rawValue: 1) }
class TelegramChannel: Peer { var flags: ChannelFlags = [] }
struct KnownBool { var knownValue: Bool? }
struct CachedChannelData { var viewForumAsMessages = KnownBool() }
struct CachedItem { let id: PeerId }
struct EnginePeer { let peer: Peer; func _asPeer() -> Peer { peer } }
struct ReadState { var count=0; var marked=false; var isUnread: Bool { count>0 || marked } }
enum Group { case root, archive }
enum SearchControllerTarget { case common(Group), forum(PeerId), savedMessages(PeerId), community(PeerId) }
struct ReadItem { let id: PeerId }
struct GroupItem { let id: PeerId }
struct PeerItem { let id: PeerId }
enum TelegramEngine { enum EngineData { enum Item { enum Messages { typealias PeerReadCounters = ReadItem; typealias ChatListGroup = GroupItem }; enum Peer { typealias Peer = PeerItem; typealias CachedData = CachedItem } } } }
final class DataEngine {
    var cached: Any?; var state=ReadState(); var group: Group? = .root; var peer: EnginePeer?; var requests: [PeerId]=[]
    func get(_ read: ReadItem, _ group: GroupItem, _ peer: PeerItem, _ cached: CachedItem) -> Signal<(ReadState, Group?, EnginePeer?, Any?), NoError> { requests += [read.id,group.id,peer.id,cached.id]; return .single((state,self.group,self.peer,self.cached)) }
    func get(_ read: ReadItem, _ group: GroupItem, _ peer: PeerItem) -> Signal<(ReadState, Group?, EnginePeer?), NoError> { requests += [read.id,group.id,peer.id]; return .single((state,self.group,self.peer)) }
}
final class Peers { var removed: [PeerId]=[]; func removeRecentPeer(peerId: PeerId) -> Signal<Int, NoError> { removed.append(peerId); return .single(0) } }
final class Engine { let data=DataEngine(); let peers=Peers() }
final class Transaction {
 var rawState = ReadState()
 func getCombinedPeerReadState(_ id: PeerId) -> ReadState? { rawState }
}
final class Postbox {
 let data = Transaction()
 func transaction<T>(_ body: (Transaction) -> T) -> Signal<T, NoError> { .single(body(data)) }
}
final class Account { let postbox = Postbox() }
final class Context: AccountContextProtocol { let account = Account(); let engine=Engine(); var calls: [(PeerId,Bool)]=[] }
struct Labels { let chatListContextMaskAsRead="Read"; let chatListContextMaskAsUnread="Unread"; let searchPopularDelete="Remove" }
func strings() -> Labels { Labels() }
enum MenuAnimation { case menu_read, menu_unread, menu_delete; var value: Int { switch self { case .menu_read:0;case .menu_unread:1;case .menu_delete:2 } } }
enum ItemMode { case destruct }
class ContextMenuItem { let title: String; let handler:(()->Void)?; let image: Int?; init(_ title:String,handler:(()->Void)?=nil,itemMode: ItemMode?=nil,itemImage:Int?=nil) { self.title=title;self.handler=handler;image=itemImage } }
final class ContextSeparatorItem: ContextMenuItem { init() { super.init("separator") } }
enum ChatListRowItem {
 static func markAsRead(context:any AccountContextProtocol,peerId:PeerId) { (context as! Context).calls.append((peerId,false)); context.account.postbox.data.rawState.marked = false }
 static func markAsUnread(context:any AccountContextProtocol,peerId:PeerId) { (context as! Context).calls.append((peerId,true)); context.account.postbox.data.rawState.marked = true }
}
enum PopularItemType { case peer(Peer,Int?,Bool), savedMessages(Peer), articles(Int32) }
final class Popular {
 let context: Context; let type: PopularItemType
 init(_ context:Context,_ type:PopularItemType) { self.context=context;self.type=type }
 func menuItems() -> Signal<[ContextMenuItem],NoError> { __POPULAR_BODY__ }
}
__HELPER__
__LEASE__
var count=0, failures=0
func check(_ name:String,_ pass:Bool) {count+=1;if !pass {failures+=1;print("FAIL: "+name)} }
let context=Context(); let id=PeerId(namespace:0,id:42);let peer=Peer(id);context.engine.data.peer=EnginePeer(peer:peer)
for group in [Group.root,.archive] {
 context.engine.data.group=group
 for state in [ReadState(count:0,marked:false),ReadState(count:3,marked:false),ReadState(count:0,marked:true)] {
  context.engine.data.state=state;context.calls=[]
  let item=searchPeerReadMenuItem(context:context,peerId:id).value
  check("current read state determines title",item?.title == (state.isUnread ? "Read":"Unread"))
  check("standard read/unread icon",item?.image == (state.isUnread ? 0:1))
  item?.handler?()
  check("explicit action targets original chat",context.calls.count == 1 && context.calls[0].0 == id && context.calls[0].1 == !state.isUnread)
 }
}
context.engine.data.group=nil
check("global peer outside chat list has no read action",searchPeerReadMenuItem(context:context,peerId:id).value == nil)
context.engine.data.group = .root;context.engine.data.peer=nil
check("missing peer has no read action",searchPeerReadMenuItem(context:context,peerId:id).value == nil)
context.engine.data.peer=EnginePeer(peer:peer);context.engine.data.requests=[]
check("secret chat has no unsupported unread action",searchPeerReadMenuItem(context:context,peerId:PeerId(namespace:3,id:99)).value == nil)
check("secret chat does not look up the visible user's read state",context.engine.data.requests.isEmpty)
peer.isForumOrMonoForum=true;context.engine.data.state=ReadState()
check("read forum does not offer an action that would clear topics",searchPeerReadMenuItem(context:context,peerId:id).value == nil)
context.engine.data.state=ReadState(count:2)
check("unread forum can be marked read",searchPeerReadMenuItem(context:context,peerId:id).value?.title == "Read")
peer.isForumOrMonoForum=false;context.engine.data.state=ReadState()
let top=Popular(context,.peer(peer,nil,false)).menuItems().value
check("top peer has unread action",top.first?.title == "Unread")
check("top peer retains remove action",top.last?.title == "Remove")
check("top peer does not remove on menu construction",context.engine.peers.removed.isEmpty)
check("Saved Messages has read action",Popular(context,.savedMessages(peer)).menuItems().value.first?.title == "Unread")
check("articles do not acquire chat read action",Popular(context,.articles(2)).menuItems().value.isEmpty)
context.engine.data.state=ReadState(marked:true)
check("reopened top peer uses live manual unread mark",Popular(context,.peer(peer,nil,false)).menuItems().value.first?.title == "Read")
peer.isForumOrMonoForum = true
context.engine.data.state = ReadState()
context.engine.data.cached = CachedChannelData(viewForumAsMessages: KnownBool(knownValue: true))
check("forum displayed as messages retains Mark as Unread", searchPeerReadMenuItem(context: context, peerId: id).value?.title == "Unread")
context.engine.data.cached = nil
let tabsForum = TelegramChannel(id, forum: true)
tabsForum.flags = [.displayForumAsTabs]
context.engine.data.peer = EnginePeer(peer: tabsForum)
check("forum displayed as tabs retains Mark as Unread", searchPeerReadMenuItem(context: context, peerId: id).value?.title == "Unread")
context.engine.data.state = ReadState()
context.account.postbox.data.rawState = ReadState(marked: true)
let markedForum = searchPeerReadMenuItem(context: context, peerId: id).value
check("regular-chat forum reads its peer-level manual unread mark", markedForum?.title == "Read")
markedForum?.handler?()
check("Read action clears the forum peer-level mark", !context.account.postbox.data.rawState.marked)
check("reopened forum menu reflects cleared mark", searchPeerReadMenuItem(context: context, peerId: id).value?.title == "Unread")
searchPeerReadMenuItem(context: context, peerId: id).value?.handler?()
check("Unread action can set the peer-level mark again", context.account.postbox.data.rawState.marked)
check("forum round trip returns Mark as Read", searchPeerReadMenuItem(context: context, peerId: id).value?.title == "Read")
context.engine.data.requests=[]; context.calls=[]
check("Saved Messages sub-chat search omits the real peer read action",searchPeerReadMenuItem(context:context,peerId:id,target:.savedMessages(id)).value == nil)
check("Saved Messages sub-chat search never reads private-chat counters",context.engine.data.requests.isEmpty)
check("Saved Messages sub-chat menu cannot send read receipts",context.calls.isEmpty)
var firstWindow: NSObject?=NSObject()
weak var retainedRun=firstWindow
check("first diagnostic window acquires the run",SearchReadRunLease.begin(firstWindow!))
firstWindow=nil
check("closing the owner window preserves the active restore operation",retainedRun != nil)
let reopenedWindow=NSObject()
check("reopened window cannot overlap the restore run",!SearchReadRunLease.begin(reopenedWindow))
SearchReadRunLease.end(reopenedWindow)
check("another window cannot release the active lease",!SearchReadRunLease.begin(reopenedWindow))
SearchReadRunLease.end(retainedRun!)
check("finishing releases the old run owner",retainedRun == nil)
check("a later window can start after restoration",SearchReadRunLease.begin(reopenedWindow))
SearchReadRunLease.end(reopenedWindow)
print("\(count-failures)/\(count) search unread checks passed")
exit(failures==0 ? 0:1)
