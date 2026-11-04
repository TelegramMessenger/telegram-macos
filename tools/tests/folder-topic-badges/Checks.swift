import Foundation

struct Signal<Value, Failure> {
    let value: Value
    static func single(_ value: Value) -> Self { Self(value: value) }
}
enum NoError: Error {}
struct Queue {}
precedencegroup PipePrecedence { associativity: left }
infix operator |> : PipePrecedence
func |> <A, B>(value: A, transform: (A) -> B) -> B { transform(value) }
func map<A, B, E>(_ transform: @escaping (A) -> B) -> (Signal<A, E>) -> Signal<B, E> { { .single(transform($0.value)) } }
func mapToSignal<A, B, E>(_ transform: @escaping (A) -> Signal<B, E>) -> (Signal<A, E>) -> Signal<B, E> { { transform($0.value) } }
func distinctUntilChanged<A>(isEqual: @escaping (A, A) -> Bool) -> (Signal<A, NoError>) -> Signal<A, NoError> { { $0 } }
func combineLatest<A, B>(_ a: Signal<A, NoError>, _ b: Signal<B, NoError>) -> Signal<(A, B), NoError> { .single((a.value, b.value)) }
func combineLatest<A, B>(queue: Queue, _ a: Signal<A, NoError>, _ b: Signal<B, NoError>) -> Signal<(A, B), NoError> { combineLatest(a, b) }

typealias PeerId = Int
typealias ValueBoxKey = Int
struct PeerGroupId: Hashable {
    let value: Int
    static let root = Self(value: 0)
}
enum Namespaces { enum PeerGroup { static let archive = PeerGroupId(value: 1) } }
struct PeerSummaryCounterTags: OptionSet, Hashable {
    let rawValue: Int
    static let contact = Self(rawValue: 1)
    static let nonContact = Self(rawValue: 2)
    static let group = Self(rawValue: 4)
    static let bot = Self(rawValue: 8)
    static let channel = Self(rawValue: 16)
}
struct Counter: Equatable { var chatCount: Int32 }
struct ChatListTotalUnreadState: Equatable {
    var absoluteCounters: [PeerSummaryCounterTags: Counter] = [:]
    var filteredCounters: [PeerSummaryCounterTags: Counter] = [:]
}
struct PreferencesEntry: Equatable { let value: Int }
enum PreferenceOperation { case update(ValueBoxKey, PreferencesEntry?) }
protocol PostboxView {}
protocol MutablePostboxView {}
protocol Peer: AnyObject {
    var associatedPeerId: PeerId? { get }
    var isForum: Bool { get set }
}
class TestPeer: Peer {
    var associatedPeerId: PeerId?
    var isForum: Bool
    init(forum: Bool = false) { self.isForum = forum }
}
final class TelegramChannel: TestPeer {
    enum Participation { case member, left }
    var participationStatus: Participation = .member
}
final class TelegramGroup: TestPeer {
    enum Membership { case Member, Left }
    var membership: Membership = .Member
}
enum PeerMuteState { case unmuted, muted(until: Int32), `default` }
struct TelegramPeerNotificationSettings { var muteState: PeerMuteState }
struct BasicPeerView: PostboxView {
    let peer: Peer?
    let isContact: Bool
    let notificationSettings: Any?
}
enum PeerReadState {
    case idBased(maxIncomingReadId: Int32, maxOutgoingReadId: Int32, maxKnownId: Int32, count: Int32, markedUnread: Bool)
}
struct CombinedPeerReadState: Equatable {
    let count: Int32
    let markedUnread: Bool
    var isUnread: Bool { count > 0 || markedUnread }
    init(states: [(Int, PeerReadState)]) {
        var count: Int32 = 0
        var markedUnread = false
        for (_, state) in states {
            if case let .idBased(_, _, _, value, marked) = state {
                count += value
                markedUnread = markedUnread || marked
            }
        }
        self.count = count
        self.markedUnread = markedUnread
    }
}
struct ThreadSummary { var totalUnreadCount: Int32; var hasUnmutedUnread: Bool }
final class PeerTable {
    var values: [PeerId: Peer] = [:]
    func get(_ id: PeerId) -> Peer? { values[id] }
}
final class ThreadSummaryTable {
    var values: [PeerId: ThreadSummary] = [:]
    func get(peerId: PeerId) -> ThreadSummary? { values[peerId] }
}
final class ReadStateTable {
    var values: [PeerId: CombinedPeerReadState] = [:]
    func getCombinedState(_ id: PeerId) -> CombinedPeerReadState? { values[id] }
}
final class PreferencesTable { func get(key: ValueBoxKey) -> PreferencesEntry? { nil } }
final class MetadataTable {
    var states: [PeerGroupId: ChatListTotalUnreadState] = [:]
    func getTotalUnreadState(groupId: PeerGroupId) -> ChatListTotalUnreadState { states[groupId] ?? .init() }
}
struct SeedConfiguration {
    let peerSummaryIsThreadBased: (Peer, Peer?) -> (value: Bool, threadsArePeers: Bool) = { peer, _ in (peer.isForum, false) }
    let peerSummaryCounterTags: (Peer, Bool) -> PeerSummaryCounterTags = { peer, _ in peer is TelegramChannel || peer is TelegramGroup ? .group : .nonContact }
}
final class PostboxImpl {
    let peerTable = PeerTable()
    let peerThreadsSummaryTable = ThreadSummaryTable()
    let readStateTable = ReadStateTable()
    let preferencesTable = PreferencesTable()
    let messageHistoryMetadataTable = MetadataTable()
    let seedConfiguration = SeedConfiguration()
}
struct PostboxTransaction {
    var alteredInitialPeerCombinedReadStates: [PeerId: CombinedPeerReadState] = [:]
    var updatedPeerThreadsSummaries: Set<PeerId> = []
    var currentUpdatedPeers: [PeerId: Peer] = [:]
    var currentPreferencesOperations: [PreferenceOperation] = []
    var currentUpdatedTotalUnreadStates: [PeerGroupId: ChatListTotalUnreadState] = [:]
}

__POSTBOX__

struct FilterCategories: OptionSet {
    let rawValue: Int
    static let contacts = Self(rawValue: 1)
    static let nonContacts = Self(rawValue: 2)
    static let groups = Self(rawValue: 4)
    static let bots = Self(rawValue: 8)
    static let channels = Self(rawValue: 16)
}
struct IncludePeers: Equatable { var peers: [PeerId] }
struct ChatListFilterData: Equatable {
    var categories: FilterCategories = []
    var includePeers = IncludePeers(peers: [])
    var excludePeers: [PeerId] = []
    var excludeMuted = false
    var excludeArchived = true
}
enum ChatListFilter: Equatable {
    case allChats
    case filter(id: Int, title: String, emoticon: String?, data: ChatListFilterData)
    var id: Int {
        switch self {
        case .allChats: return 0
        case let .filter(id, _, _, _): return id
        }
    }
}
struct CombinedView { var views: [PostboxViewKey: PostboxView] }
enum PostboxViewKey: Hashable {
    case unreadCounts(items: [UnreadMessageCountsItem])
    case basicPeer(PeerId)
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.unreadCounts(lhs), .unreadCounts(rhs)): return lhs == rhs
        case let (.basicPeer(lhs), .basicPeer(rhs)): return lhs == rhs
        default: return false
        }
    }
    func hash(into hasher: inout Hasher) {
        switch self {
        case .unreadCounts: hasher.combine(0)
        case let .basicPeer(id): hasher.combine(1); hasher.combine(id)
        }
    }
}
final class Postbox {
    let impl = PostboxImpl()
    var settings: [PeerId: TelegramPeerNotificationSettings] = [:]
    var seedConfiguration: SeedConfiguration { impl.seedConfiguration }
    func combinedView(keys: [PostboxViewKey]) -> Signal<CombinedView, NoError> {
        var views: [PostboxViewKey: PostboxView] = [:]
        for key in keys {
            switch key {
            case let .unreadCounts(items): views[key] = MutableUnreadMessageCountsView(postbox: impl, items: items).immutableView()
            case let .basicPeer(id): views[key] = BasicPeerView(peer: impl.peerTable.get(id), isContact: false, notificationSettings: settings[id])
            }
        }
        return .single(CombinedView(views: views))
    }
}
final class Account { let postbox = Postbox() }
final class EnginePeers {
    var filters: [ChatListFilter] = []
    func updatedChatListFilters() -> Signal<[ChatListFilter], NoError> { .single(filters) }
}
final class TelegramEngine { let account = Account(); let peers = EnginePeers() }
struct TelegramAccountManagerTypes {}
struct AccountManager<T> { var badgeEnabled = true }
struct NotificationSettings { let badgeEnabled: Bool }
func appNotificationSettings(accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<NotificationSettings, NoError> { .single(.init(badgeEnabled: accountManager.badgeEnabled)) }
func renderedTotalUnreadCount(accountManager: AccountManager<TelegramAccountManagerTypes>, postbox: Postbox) -> Signal<(Int32, Bool), NoError> { .single((0, false)) }

__BADGE_MODELS__
__CALCULATION__

var passed = 0
var failed = 0
func check(_ condition: @autoclosure () -> Bool, _ description: String) {
    if condition() { passed += 1; print("PASS \(description)") }
    else { failed += 1; print("FAIL \(description)") }
}
func state(_ count: Int32) -> CombinedPeerReadState {
    .init(states: [(0, .idBased(maxIncomingReadId: 1, maxOutgoingReadId: 1, maxKnownId: 1, count: count, markedUnread: false))])
}
let engine = TelegramEngine()
let postbox = engine.account.postbox
let forum = TelegramChannel(forum: true)
let forumId = 100
postbox.impl.peerTable.values[forumId] = forum
postbox.settings[forumId] = .init(muteState: .unmuted)
postbox.impl.peerThreadsSummaryTable.values[forumId] = .init(totalUnreadCount: 1, hasUnmutedUnread: false)
engine.peers.filters = [.filter(id: 1, title: "Work", emoticon: nil, data: .init(includePeers: .init(peers: [forumId])))]
func badge() -> ChatListFilterBadge {
    makeChatListFilterItems(engine: engine, accountManager: .init()).value.filters[0]
}
check(badge().count == 1, "muted topic remains one unread chat")
check(!badge().hasUnmutedUnread, "muted-only topic does not activate folder badge")
postbox.impl.peerThreadsSummaryTable.values[forumId] = .init(totalUnreadCount: 2, hasUnmutedUnread: true)
check(badge().count == 1 && badge().hasUnmutedUnread, "an unmuted unread topic activates the badge once")
postbox.settings[forumId] = .init(muteState: .muted(until: Int32.max))
check(!badge().hasUnmutedUnread, "whole-group mute keeps existing behavior")
postbox.settings[forumId] = .init(muteState: .unmuted)
postbox.impl.peerThreadsSummaryTable.values[forumId] = .init(totalUnreadCount: 0, hasUnmutedUnread: false)
check(badge().count == 0 && !badge().hasUnmutedUnread, "all topics read clears the folder count")
forum.participationStatus = .left
postbox.impl.peerThreadsSummaryTable.values[forumId] = .init(totalUnreadCount: 1, hasUnmutedUnread: true)
check(badge().count == 0, "a left group is not counted")
forum.participationStatus = .member
let chatId = 200
postbox.impl.peerTable.values[chatId] = TestPeer()
postbox.impl.readStateTable.values[chatId] = state(3)
engine.peers.filters = [.filter(id: 2, title: "People", emoticon: nil, data: .init(includePeers: .init(peers: [chatId])))]
check(badge().count == 1 && badge().hasUnmutedUnread, "regular unmuted chat is unchanged")
postbox.settings[chatId] = .init(muteState: .muted(until: Int32.max))
check(badge().count == 1 && !badge().hasUnmutedUnread, "regular muted chat is unchanged")
postbox.settings[chatId] = .init(muteState: .unmuted)
engine.peers.filters = [.filter(id: 3, title: "Mixed", emoticon: nil, data: .init(includePeers: .init(peers: [forumId, chatId])))]
postbox.impl.peerThreadsSummaryTable.values[forumId] = .init(totalUnreadCount: 1, hasUnmutedUnread: false)
check(badge().count == 2 && badge().hasUnmutedUnread, "another unmuted chat keeps a mixed folder active")
postbox.impl.readStateTable.values[chatId] = state(0)
check(badge().count == 1 && !badge().hasUnmutedUnread, "reading other chats leaves the muted-only folder inactive")

let item = UnreadMessageCountsItem.peer(id: forumId, handleThreads: true)
let mutable = MutableUnreadMessageCountsView(postbox: postbox.impl, items: [item])
func snapshot(_ view: MutableUnreadMessageCountsView) -> UnreadMessageCountsView { view.immutableView() as! UnreadMessageCountsView }
check(snapshot(mutable).hasUnmutedUnreadThreads(for: forumId) == false, "initial snapshot exposes muted-only threads")
postbox.impl.peerThreadsSummaryTable.values[forumId] = .init(totalUnreadCount: 1, hasUnmutedUnread: true)
check(mutable.replay(postbox: postbox.impl, transaction: .init(updatedPeerThreadsSummaries: [forumId])), "unmute emits even when unread count stays one")
check(snapshot(mutable).count(for: item) == 1 && snapshot(mutable).hasUnmutedUnreadThreads(for: forumId) == true, "updated snapshot retains count and unmuted state")
postbox.impl.peerThreadsSummaryTable.values[forumId] = .init(totalUnreadCount: 1, hasUnmutedUnread: false)
check(mutable.replay(postbox: postbox.impl, transaction: .init(updatedPeerThreadsSummaries: [forumId])), "mute emits even when unread count stays one")
check(snapshot(mutable).hasUnmutedUnreadThreads(for: forumId) == false, "muted snapshot resets the highlight")
check(!mutable.replay(postbox: postbox.impl, transaction: .init(updatedPeerThreadsSummaries: [forumId])), "unchanged summaries produce no extra update")
postbox.impl.peerThreadsSummaryTable.values[forumId] = .init(totalUnreadCount: 1, hasUnmutedUnread: true)
check(mutable.refreshDueToExternalTransaction(postbox: postbox.impl), "external refresh notices mute-only changes")
check(snapshot(mutable).hasUnmutedUnreadThreads(for: forumId) == true, "external snapshot has current thread state")
let regular = MutableUnreadMessageCountsView(postbox: postbox.impl, items: [.peer(id: chatId, handleThreads: true)])
check(snapshot(regular).hasUnmutedUnreadThreads(for: chatId) == nil, "regular peers have no thread override")
let noThreads = MutableUnreadMessageCountsView(postbox: postbox.impl, items: [.peer(id: forumId, handleThreads: false)])
check(snapshot(noThreads).hasUnmutedUnreadThreads(for: forumId) == nil, "peer-only requests have no thread override")
let mixedModes = MutableUnreadMessageCountsView(postbox: postbox.impl, items: [item, .peer(id: forumId, handleThreads: false)])
check(snapshot(mixedModes).hasUnmutedUnreadThreads(for: forumId) == true, "a peer-only item cannot erase a thread-aware item")
forum.isForum = false
postbox.impl.readStateTable.values[forumId] = state(7)
check(mutable.replay(postbox: postbox.impl, transaction: .init(currentUpdatedPeers: [forumId: forum])), "peer kind change refreshes the view")
check(snapshot(mutable).hasUnmutedUnreadThreads(for: forumId) == nil && snapshot(mutable).count(for: item) == 7, "leaving thread mode clears thread metadata")
print("\(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
