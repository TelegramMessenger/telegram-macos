import Foundation

struct PeerId: Hashable {
    let value: Int64
    func toInt64() -> Int64 { value }
}

enum PeerGroupId: Hashable {
    case root
    case archive
}

enum Namespaces {
    enum PeerGroup {
        static let archive = PeerGroupId.archive
    }
}

protocol Peer {
    var id: PeerId { get }
    var displayTitle: String { get }
}

struct GroupPeer: Peer {
    let id: PeerId
    let displayTitle: String
}

final class TelegramUser: Peer {
    let id: PeerId
    let firstName: String?
    let lastName: String?
    let displayTitle = "A private phone number must not be exported"

    init(id: Int64, firstName: String?, lastName: String?) {
        self.id = PeerId(value: id)
        self.firstName = firstName
        self.lastName = lastName
    }
}

struct TestStrings {
    let peerDeletedUser = "Deleted Account"
}

func strings() -> TestStrings { TestStrings() }

struct ChatListFilterPeerCategories {}

struct ChatListFilterPredicate {
    let includes: (Peer) -> Bool
}

struct ChatListFilter {
    let id: Int32
    let title: String
    let predicate: ChatListFilterPredicate?
}

func chatListFilterPredicate(for filter: ChatListFilter, communityCategories: [PeerId: ChatListFilterPeerCategories]) -> ChatListFilterPredicate? {
    filter.predicate
}

final class Transaction {
    var groups: [PeerGroupId: [Peer]]

    init(groups: [PeerGroupId: [Peer]]) {
        self.groups = groups
    }

    func getChatListPeers(groupId: PeerGroupId, filterPredicate: ChatListFilterPredicate?, additionalFilter: ((Peer) -> Bool)?) -> [Peer] {
        (groups[groupId] ?? []).filter { peer in
            (filterPredicate?.includes(peer) ?? true) && (additionalFilter?(peer) ?? true)
        }
    }
}

@main
struct FocusCatalogTests {
    static func main() {
        let work = GroupPeer(id: PeerId(value: 30), displayTitle: "Work")
        let archived = GroupPeer(id: PeerId(value: 20), displayTitle: "Archived")
        let oldCached = GroupPeer(id: PeerId(value: 10), displayTitle: "Older cached chat beyond a history hole")
        let transaction = Transaction(groups: [.root: [work, oldCached], .archive: [archived, work]])
        let workFolder = ChatListFilter(id: 4, title: "Work folder", predicate: .init(includes: { $0.id.value == 30 }))
        let snapshot = focusAccountCatalog(transaction: transaction, accountId: 71, filters: [workFolder], communityCategories: [:])
        precondition(snapshot.chats.map { $0.id.peerId } == [10, 20, 30])
        precondition(snapshot.chats.allSatisfy { $0.id.accountId == 71 })
        precondition(snapshot.chats.first(where: { $0.id.peerId == 10 })?.isArchived == false)
        precondition(snapshot.chats.first(where: { $0.id.peerId == 20 })?.isArchived == true)
        precondition(snapshot.folders == [FocusCatalogFolder(id: .init(accountId: 71, folderId: 4), title: "Work folder", peerIds: [30])])
        print("PASS all local chats, archive, duplicate identities and stable ordering")

        let updatedFolder = ChatListFilter(id: 4, title: "Work folder", predicate: .init(includes: { $0.id.value != 10 }))
        let updated = focusAccountCatalog(transaction: transaction, accountId: 71, filters: [updatedFolder], communityCategories: [:])
        precondition(updated.folders.first?.peerIds == [20, 30])
        precondition(updated != snapshot)
        print("PASS dynamic folder membership uses the supplied canonical predicate")

        let moveTransaction = Transaction(groups: [.root: [oldCached], .archive: []])
        let beforeMove = focusAccountCatalog(transaction: moveTransaction, accountId: 71, filters: [], communityCategories: [:])
        moveTransaction.groups = [.root: [], .archive: [oldCached]]
        let afterMove = focusAccountCatalog(transaction: moveTransaction, accountId: 71, filters: [], communityCategories: [:])
        precondition(beforeMove.chats.first?.id == afterMove.chats.first?.id)
        precondition(beforeMove.chats.first?.title == afterMove.chats.first?.title)
        precondition(beforeMove.folders == afterMove.folders)
        precondition(beforeMove.chats.first?.isArchived == false)
        precondition(afterMove.chats.first?.isArchived == true)
        precondition(beforeMove != afterMove)
        moveTransaction.groups = [.root: [oldCached], .archive: []]
        let restored = focusAccountCatalog(transaction: moveTransaction, accountId: 71, filters: [], communityCategories: [:])
        precondition(restored == beforeMove)
        print("PASS moving an unchanged chat into or out of archive invalidates the catalog")

        transaction.groups = [.root: [oldCached], .archive: []]
        let removed = focusAccountCatalog(transaction: transaction, accountId: 71, filters: [], communityCategories: [:])
        precondition(removed.chats.map { $0.id.peerId } == [10])
        precondition(removed.folders.isEmpty)
        print("PASS removed chats and folders disappear from the next snapshot")

        let otherAccount = focusAccountCatalog(transaction: transaction, accountId: 72, filters: [workFolder], communityCategories: [:])
        precondition(otherAccount.chats.first?.id != removed.chats.first?.id)
        precondition(otherAccount.folders.first?.id.accountId == 72)
        print("PASS same chat and folder identifiers remain account-qualified")

        precondition(focusCatalogTitle(TelegramUser(id: 1, firstName: "Ada", lastName: "Lovelace")) == "Ada Lovelace")
        precondition(focusCatalogTitle(TelegramUser(id: 2, firstName: nil, lastName: nil)) == "Deleted Account")
        precondition(focusCatalogTitle(TelegramUser(id: 3, firstName: "", lastName: "")) == "Deleted Account")
        print("PASS user titles never fall back to private phone numbers")
    }
}
