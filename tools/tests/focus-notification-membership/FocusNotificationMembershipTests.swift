import Foundation

public struct PeerId: Hashable {
    let value: Int64
    init(_ value: Int64) { self.value = value }
    func toInt64() -> Int64 { value }
}

__PEER_GROUP__

enum Namespaces {
    enum PeerGroup {
        static let archive = PeerGroupId.group(1)
    }
    enum Message {
        static let Cloud: Int32 = 0
    }
}

public enum MessageId {
    public typealias Namespace = Int32
}

public struct MessageTags: OptionSet {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }
    static let unseenPersonalMessage = MessageTags(rawValue: 1)
}

public struct PendingMessageActionType: Hashable {
    let rawValue: Int32
    static let consumeUnseenPersonalMessage = PendingMessageActionType(rawValue: 1)
}

__SUMMARY_TYPES__

public protocol Peer {
    var id: PeerId { get }
    var associatedPeerId: PeerId? { get }
    var associatedPeerOverridesIdentity: Bool { get }
}

class TestPeer: Peer {
    let id: PeerId
    let associatedPeerId: PeerId?
    var associatedPeerOverridesIdentity: Bool { associatedPeerId != nil }

    init(_ id: Int64, associatedId: Int64? = nil) {
        self.id = PeerId(id)
        self.associatedPeerId = associatedId.map(PeerId.init)
    }
}

final class TelegramUser: TestPeer {
    var botInfo: Bool?
}

final class TelegramSecretChat: TestPeer {}
final class TelegramGroup: TestPeer {}
final class TelegramCommunity: TestPeer {}

final class TelegramChannel: TestPeer {
    enum Info {
        case group
        case broadcast
    }
    let info: Info

    init(_ id: Int64, info: Info) {
        self.info = info
        super.init(id)
    }
}

public struct ChatListFilterPeerCategories: OptionSet {
    public let rawValue: Int32
    public init(rawValue: Int32) { self.rawValue = rawValue }
    static let contacts = Self(rawValue: 1)
    static let nonContacts = Self(rawValue: 2)
    static let bots = Self(rawValue: 4)
    static let groups = Self(rawValue: 8)
    static let channels = Self(rawValue: 16)
    static let all: Self = [.contacts, .nonContacts, .bots, .groups, .channels]
}

struct IncludedPeers {
    var peers: [PeerId] = []
    var pinnedPeers: [PeerId] = []
}

struct ChatListFilterData {
    var categories: ChatListFilterPeerCategories = .all
    var includePeers = IncludedPeers()
    var excludePeers: [PeerId] = []
    var excludeArchived = false
    var excludeRead = false
    var excludeMuted = false
}

public struct ChatListFilter {
    let id: Int32
    let title: String
    let data: ChatListFilterData?
}

__POSTBOX_PREDICATE__
__CANONICAL_FOLDER_MAPPER__

public protocol PeerNotificationSettings {
    func isRemovedFromTotalUnreadCount(default: Bool) -> Bool
}

private struct TestNotificationSettings: PeerNotificationSettings {
    let muted: Bool
    func isRemovedFromTotalUnreadCount(default: Bool) -> Bool { muted }
}

__NOTIFICATION_SETTINGS__

struct CombinedPeerReadState {
    let isUnread: Bool
}

struct MessageHistoryTagNamespaceSummary {
    let count: Int32
}

final class Transaction {
    var peer: Peer?
    var groupId: PeerGroupId? = .root
    var isUnread = false
    var isContact = false
    var muted: Bool?
    var globallyMuted = false
    var mentionCount: Int32 = 0
    var pendingMentionCount: Int32 = 0
    private(set) var requestedPeers: [PeerId] = []

    init(peer: Peer) { self.peer = peer }

    func getPeer(_ peerId: PeerId) -> Peer? {
        requestedPeers.append(peerId)
        return peer?.id == peerId ? peer : nil
    }

    func getPeerChatListIndex(_ peerId: PeerId) -> (PeerGroupId, Int)? {
        guard let groupId, peer?.id == peerId else { return nil }
        return (groupId, 0)
    }

    func getCombinedPeerReadState(_ peerId: PeerId) -> CombinedPeerReadState? {
        precondition(peer?.id == peerId)
        return CombinedPeerReadState(isUnread: isUnread)
    }

    func isPeerContact(peerId: PeerId) -> Bool {
        precondition(peer?.id == peerId)
        return isContact
    }

    func getGlobalNotificationSettings() -> PostboxGlobalNotificationSettings {
        PostboxGlobalNotificationSettings(defaultIncludePeer: { _ in !self.globallyMuted })
    }

    func getPeerNotificationSettings(id: PeerId) -> PeerNotificationSettings? {
        precondition(peer?.id == id)
        return muted.map(TestNotificationSettings.init)
    }

    func getMessageTagSummary(peerId: PeerId, threadId: Int64?, tagMask: MessageTags, namespace: MessageId.Namespace, customTag: Data?) -> MessageHistoryTagNamespaceSummary? {
        precondition(peer?.id == peerId && threadId == nil && tagMask == .unseenPersonalMessage && namespace == Namespaces.Message.Cloud && customTag == nil)
        return MessageHistoryTagNamespaceSummary(count: mentionCount)
    }

    func getPendingMessageActionsSummary(peerId: PeerId, type: PendingMessageActionType, namespace: MessageId.Namespace) -> Int32? {
        precondition(peer?.id == peerId && type == .consumeUnseenPersonalMessage && namespace == Namespaces.Message.Cloud)
        return pendingMentionCount
    }
}

__LIVE_NOTIFICATION_ADAPTER__

@main
private enum Tests {
    static let account: Int64 = 71
    static let peer = TelegramUser(0x10000002a)
    static let folder = FocusFolderIdentifier(accountId: account, folderId: 4)

    static func policy(_ transaction: Transaction, _ data: ChatListFilterData?, mode: FocusFilterMode = .allowSelected, explicitPeers: Set<FocusChatIdentifier> = [], effect: FocusFilterEffect = .both, categories: [PeerId: ChatListFilterPeerCategories] = [:]) -> FocusFilterPolicy {
        focusNotificationPolicy(
            transaction: transaction,
            request: .init(chat: .init(accountId: account, peerId: (transaction.peer?.id ?? peer.id).toInt64()), configuration: .init(accountIds: [account], chatIds: explicitPeers, folderIds: [folder], mode: mode, effect: effect), filters: [.init(id: folder.folderId, title: "Projects", data: data)], communityCategories: categories)
        )
    }

    static func criteria(_ policy: FocusFilterPolicy, for identifier: FocusChatIdentifier) -> String {
        FocusNotificationFilter(configuration: policy.configuration).criteria(for: identifier, catalog: policy.catalog)
    }

    static func predicate(_ policy: FocusFilterPolicy) -> NSPredicate {
        FocusNotificationFilter(configuration: policy.configuration).predicate
    }

    static func assertMembership(_ expected: Bool, transaction: Transaction, data: ChatListFilterData?, categories: [PeerId: ChatListFilterPeerCategories] = [:]) {
        let peerId = transaction.peer?.id ?? peer.id
        for mode in [FocusFilterMode.allowSelected, .excludeSelected] {
            let live = policy(transaction, data, mode: mode, categories: categories)
            let allows = mode == .allowSelected ? expected : !expected
            precondition(live.includes(accountId: account, peerId: peerId.toInt64(), effect: .notifications) == allows)
            let criteria = criteria(live, for: .init(accountId: account, peerId: peerId.toInt64()))
            precondition(predicate(live).evaluate(with: criteria) == allows)
        }
    }

    static func main() {
        let transaction = Transaction(peer: peer)
        var unreadFolder = ChatListFilterData()
        unreadFolder.excludeRead = true
        for mode in [FocusFilterMode.allowSelected, .excludeSelected] {
            let configuration = FocusFilterConfiguration(accountIds: [account], folderIds: [folder], mode: mode, effect: .both)
            let staleReadCatalog = FocusFilterCatalog(folders: [.init(id: folder, title: "Projects", peerIds: [])])
            let staleRead = FocusFilterPolicy(configuration: configuration, catalog: staleReadCatalog)
            transaction.isUnread = true
            let firstUnread = policy(transaction, unreadFolder, mode: mode)
            let identifier = FocusChatIdentifier(accountId: account, peerId: peer.id.toInt64())
            precondition(staleRead.includes(accountId: account, peerId: peer.id.toInt64(), effect: .notifications) != firstUnread.includes(accountId: account, peerId: peer.id.toInt64(), effect: .notifications))
            precondition(firstUnread.includes(accountId: account, peerId: peer.id.toInt64(), effect: .notifications) == (mode == .allowSelected))
            precondition(predicate(staleRead).evaluate(with: criteria(firstUnread, for: identifier)) == (mode == .allowSelected))
            transaction.isUnread = false
            let readAgain = policy(transaction, unreadFolder, mode: mode)
            precondition(readAgain.includes(accountId: account, peerId: peer.id.toInt64(), effect: .notifications) == (mode == .excludeSelected))
            precondition(predicate(staleRead).evaluate(with: criteria(readAgain, for: identifier)) == (mode == .excludeSelected))
        }
        print("PASS first read-to-unread notification uses live membership before allow/deny gate and system criteria")

        var data = unreadFolder
        data.excludeMuted = true
        transaction.isUnread = true
        transaction.muted = true
        assertMembership(false, transaction: transaction, data: data)
        transaction.mentionCount = 2
        transaction.pendingMentionCount = 1
        transaction.isUnread = false
        assertMembership(true, transaction: transaction, data: data)
        transaction.pendingMentionCount = 2
        assertMembership(false, transaction: transaction, data: data)
        transaction.mentionCount = 0
        transaction.pendingMentionCount = 0
        transaction.isUnread = true
        transaction.muted = nil
        transaction.globallyMuted = true
        assertMembership(false, transaction: transaction, data: data)
        transaction.muted = false
        assertMembership(true, transaction: transaction, data: data)
        print("PASS current unread, peer/global mute and unconsumed mention summaries use canonical folder semantics")

        data = ChatListFilterData()
        data.categories = [.contacts]
        transaction.isContact = true
        assertMembership(true, transaction: transaction, data: data)
        transaction.isContact = false
        assertMembership(false, transaction: transaction, data: data)
        data.categories = [.nonContacts]
        assertMembership(true, transaction: transaction, data: data)
        transaction.isContact = true
        assertMembership(false, transaction: transaction, data: data)
        print("PASS contact and non-contact category changes are read for the incoming peer")

        data = unreadFolder
        data.excludeMuted = true
        data.excludeArchived = true
        transaction.isUnread = false
        transaction.muted = true
        transaction.groupId = Namespaces.PeerGroup.archive
        data.includePeers.peers = [peer.id]
        assertMembership(true, transaction: transaction, data: data)
        data.excludePeers = [peer.id]
        assertMembership(false, transaction: transaction, data: data)
        data.includePeers.pinnedPeers = [peer.id]
        assertMembership(true, transaction: transaction, data: data)
        data.includePeers.pinnedPeers = []
        data.includePeers.peers = []
        data.excludePeers = []
        data.excludeRead = false
        data.excludeMuted = false
        assertMembership(false, transaction: transaction, data: data)
        data.excludeArchived = false
        assertMembership(true, transaction: transaction, data: data)
        transaction.groupId = nil
        assertMembership(false, transaction: transaction, data: data)
        transaction.groupId = .root
        assertMembership(true, transaction: transaction, data: nil)
        print("PASS pinned/include/exclude precedence, archive and absent chat-list entries match canonical behavior")

        let secret = TelegramSecretChat(7, associatedId: peer.id.toInt64())
        let secretTransaction = Transaction(peer: secret)
        data = ChatListFilterData()
        data.categories = []
        data.includePeers.peers = [peer.id]
        assertMembership(true, transaction: secretTransaction, data: data)
        let secretPolicy = policy(secretTransaction, data)
        precondition(criteria(secretPolicy, for: .init(accountId: account, peerId: secret.id.toInt64())).hasPrefix("telegram-focus:\(account):\(secret.id.toInt64());"))
        precondition(!secretPolicy.includes(accountId: account, peerId: peer.id.toInt64(), effect: .notifications))
        print("PASS associated peer folder rules retain the actual namespaced notification chat identity")

        let explicit = FocusChatIdentifier(accountId: account, peerId: peer.id.toInt64())
        let explicitPolicy = policy(transaction, unreadFolder, explicitPeers: [explicit])
        precondition(explicitPolicy.includes(accountId: account, peerId: peer.id.toInt64(), effect: .notifications))
        precondition(explicitPolicy.includes(accountId: account + 1, peerId: peer.id.toInt64(), effect: .notifications))
        let deletedFolder = focusNotificationPolicy(transaction: transaction, request: .init(chat: explicit, configuration: explicitPolicy.configuration, filters: [], communityCategories: [:]))
        precondition(deletedFolder.includes(accountId: account, peerId: peer.id.toInt64(), effect: .notifications))
        let listOnly = policy(transaction, unreadFolder, effect: .chatList)
        precondition(listOnly.includes(accountId: account, peerId: peer.id.toInt64(), effect: .notifications))
        precondition(transaction.requestedPeers.allSatisfy { $0 == peer.id })
        print("PASS explicit chat union, deleted folders, non-target accounts and chat-list-only effects remain independent")

        let groupTransaction = Transaction(peer: TelegramGroup(111))
        data = ChatListFilterData()
        data.categories = [.groups]
        assertMembership(true, transaction: groupTransaction, data: data)
        data.categories = [.channels]
        assertMembership(false, transaction: groupTransaction, data: data)
        let broadcastTransaction = Transaction(peer: TelegramChannel(222, info: .broadcast))
        assertMembership(true, transaction: broadcastTransaction, data: data)
        let community = TelegramCommunity(333)
        let communityTransaction = Transaction(peer: community)
        assertMembership(true, transaction: communityTransaction, data: data, categories: [community.id: [.channels]])
        assertMembership(false, transaction: communityTransaction, data: data, categories: [community.id: [.groups]])
        print("PASS personal chats, groups, channels and community categories use the production folder mapper")

        FocusNotificationResolverTests.run()
    }
}
