import Foundation
import SwiftSignalKit

public struct PeerId: Hashable {
    let rawValue: Int64
    init(_ value: Int64) { rawValue = value }
    func toInt64() -> Int64 { rawValue }
}

__PEER_GROUP__

public protocol Peer {
    var id: PeerId { get }
    var associatedPeerId: PeerId? { get }
    var associatedPeerOverridesIdentity: Bool { get }
}

struct TestPeer: Peer, Equatable {
    let id: PeerId
    var associatedPeerId: PeerId? { nil }
    var associatedPeerOverridesIdentity: Bool { false }
    func _asPeer() -> TestPeer { self }
}

public struct ChatListMessageTagSummaryResultCalculation {}

__POSTBOX_PREDICATE__

struct EngineChatList: Equatable {
    struct RenderedPeer: Equatable {
        let peerId: PeerId
        var peer: TestPeer? { TestPeer(id: peerId) }
    }
    struct Item: Equatable {
        let renderedPeer: RenderedPeer
        init(_ id: Int64) { renderedPeer = .init(peerId: PeerId(id)) }
    }
    struct GroupItem: Equatable {
        let id: PeerGroupId
        let topMessage: Int?
        let items: [Item]
        let unreadCount: Int
    }
    struct AdditionalItem: Equatable { let item: Item }
    let items: [Item]
    let groupItems: [GroupItem]
    let additionalItems: [AdditionalItem]
    let hasEarlier: Bool
    let hasLater: Bool
    let isLoading: Bool
}

enum ViewUpdateType { case Initial, Generic }

struct ChatListViewUpdate {
    let list: EngineChatList
    let type: ViewUpdateType
    func withUpdatedList(_ list: EngineChatList, type: ViewUpdateType? = nil) -> ChatListViewUpdate {
        .init(list: list, type: type ?? self.type)
    }
}

enum Namespaces {
    enum PeerGroup { static let archive = PeerGroupId.group(1) }
}

struct TestIncludedPeers: Equatable { let peers: [PeerId] }
struct TestFolderData: Equatable {
    let excludeArchived = false
    let includePeers = TestIncludedPeers(peers: [])
}

enum ChatListFilter: Equatable {
    case allChats
    case filter(Int32, Set<Int64>)
    var isAllChats: Bool { self == .allChats }
    var data: TestFolderData? {
        if case .filter = self { return TestFolderData() }
        return nil
    }
}

enum ChatListControllerLocation { case chatList(groupId: PeerGroupId), forum(PeerId) }
enum ChatListIndexRequest { case Initial(Int, Int?), Index(Int, Int?) }
enum PinnedItemId { case peer(PeerId) }
enum PinLocation { case group(PeerGroupId) }

struct TestAccountId { let int64: Int64 }

struct TestSnapshot: Equatable {
    var peers: [Int64] = [1, 2]
    var isLoading = false
    var hasEarlier = false
    var hasLater = false
    var page: Set<Int64>?
}

final class TestTransaction {
    func getChatListPeers(groupId: PeerGroupId, filterPredicate: ChatListFilterPredicate?, additionalFilter: Int?) -> [TestPeer] { [] }
}

final class TestPostbox {
    func transaction<T>(_ body: (TestTransaction) -> T) -> Signal<T, NoError> {
        .single(body(TestTransaction()))
    }
}

final class Account {
    let id = TestAccountId(int64: 1)
    let postbox = TestPostbox()
    let baseline: ValuePromise<TestSnapshot>
    let filtered: ValuePromise<TestSnapshot>
    var calls: [(ChatListFilter?, ChatListIndexRequest, Bool)] = []
    init(baseline: TestSnapshot = .init(), filtered: TestSnapshot = .init()) {
        self.baseline = ValuePromise(baseline)
        self.filtered = ValuePromise(filtered)
    }
}

struct TelegramEngine {
    struct Peers {
        func getPinnedItemIds(location: PinLocation) -> Signal<[PinnedItemId], NoError> { .single([]) }
    }
    let peers = Peers()
    init(account: Account) {}
}

func chatListViewForLocation(chatListLocation: ChatListControllerLocation, location: ChatListIndexRequest, filter: ChatListFilter?, account: Account, predicateTransform: ((ChatListFilterPredicate?) -> ChatListFilterPredicate?)? = nil) -> Signal<ChatListViewUpdate, NoError> {
    account.calls.append((filter, location, predicateTransform != nil))
    let base: ChatListFilterPredicate?
    if case let .filter(_, members)? = filter {
        base = ChatListFilterPredicate(includePeerIds: [], excludePeerIds: [], pinnedPeerIds: [], messageTagSummary: nil, includeAdditionalPeerGroupIds: [], include: { peer, _, _, _, _ in members.contains(peer.id.toInt64()) })
    } else {
        base = nil
    }
    let predicate = predicateTransform?(base) ?? base
    let source = predicateTransform == nil ? account.baseline : account.filtered
    return source.get() |> map { snapshot in
        let peers = snapshot.peers.filter { id in
            (predicate?.includes(peer: TestPeer(id: PeerId(id)), groupId: .root, isRemovedFromTotalUnreadCount: false, isUnread: true, isContact: true, messageTagSummaryResult: nil) ?? true)
                && (snapshot.page?.contains(id) ?? true)
        }
        return ChatListViewUpdate(list: EngineChatList(items: peers.map(EngineChatList.Item.init), groupItems: [], additionalItems: [], hasEarlier: snapshot.hasEarlier, hasLater: snapshot.hasLater, isLoading: snapshot.isLoading), type: .Initial)
    }
}

__FOCUS_PREDICATE__
__FOCUS_SUPPORT__
__FOCUS_FILTERING__

struct Language {
    let languageCode: String
    let strings: [String: String]
}

struct TelegramLocalization {
    let primaryLanguage: Language
    let secondaryLanguage: Language?
    var baseLanguageCode: String { secondaryLanguage?.languageCode ?? primaryLanguage.languageCode }
}

let appCurrentLanguage = TelegramLocalization(primaryLanguage: Language(languageCode: "en", strings: [:]), secondaryLanguage: nil)

__FOCUS_TEXT__

@main
private enum Tests {
    static let folder = ChatListFilter.filter(7, [1])
    static let hiddenSelection = FocusFilterSelection(mode: .allowSelected, peerIds: [])

    static func result(account: Account = Account(), filter: ChatListFilter? = folder, selection: FocusFilterSelection? = hiddenSelection, location: ChatListIndexRequest = .Initial(50, nil), chatListLocation: ChatListControllerLocation = .chatList(groupId: .root)) -> ChatListFocusViewUpdate {
        var value: ChatListFocusViewUpdate?
        let disposable = focusFilteredChatListView(chatListLocation: chatListLocation, location: location, filter: filter, account: account, selection: selection, policies: .single(.init())).start(next: { value = $0 })
        defer { disposable.dispose() }
        precondition(value != nil)
        return value!
    }

    static func testReasons() {
        precondition(result().hiddenByFocus)
        precondition(result(selection: .init(mode: .excludeSelected, peerIds: [1])).hiddenByFocus)
        precondition(result(selection: .init(mode: .allowSelected, peerIds: [2])).hiddenByFocus)
        precondition(!result(filter: .filter(8, [99])).hiddenByFocus)
        precondition(!result(account: Account(baseline: .init(peers: []), filtered: .init(peers: []))).hiddenByFocus)
        precondition(!result(filter: .filter(9, [1, 2]), selection: .init(mode: .allowSelected, peerIds: [1])).hiddenByFocus)
        precondition(!result(selection: .init(mode: .excludeSelected, peerIds: [])).hiddenByFocus)
        precondition(!result(selection: nil).hiddenByFocus)
        precondition(!result(filter: .allChats).hiddenByFocus)
        precondition(!result(filter: nil).hiddenByFocus)
        precondition(!result(chatListLocation: .forum(PeerId(1))).hiddenByFocus)
        precondition(!result(account: Account(baseline: .init(isLoading: true))).hiddenByFocus)
        precondition(!result(account: Account(filtered: .init(isLoading: true))).hiddenByFocus)
        for snapshot in [TestSnapshot(hasEarlier: true, page: []), TestSnapshot(hasLater: true, page: [])] {
            precondition(!result(account: Account(filtered: snapshot), selection: .init(mode: .allowSelected, peerIds: [1]), location: .Index(100, nil)).hiddenByFocus)
        }
        let paginated = Account()
        precondition(result(account: paginated, location: .Index(100, nil)).hiddenByFocus)
        precondition(paginated.calls.count == 2)
        precondition(paginated.calls.allSatisfy { $0.0 == folder })
        precondition(paginated.calls.contains { call in
            if case .Initial(50, nil) = call.1 { return !call.2 }
            return false
        })
        print("PASS: only loaded, genuinely hidden custom folders show the Focus reason; pagination, loading, normal emptiness and forums do not")
    }

    static func testLiveBaseline() {
        let account = Account()
        var values: [ChatListFocusViewUpdate] = []
        let disposable = focusFilteredChatListView(chatListLocation: .chatList(groupId: .root), location: .Index(100, nil), filter: folder, account: account, selection: hiddenSelection, policies: .single(.init())).start(next: { values.append($0) })
        defer { disposable.dispose() }
        precondition(values.last?.hiddenByFocus == true)
        let queries = account.calls.count
        account.baseline.set(.init(peers: [2]))
        precondition(values.last?.hiddenByFocus == false)
        precondition(values.last?.view.type == .Generic)
        account.baseline.set(.init(peers: [1, 2]))
        precondition(values.last?.hiddenByFocus == true)
        account.baseline.set(.init(isLoading: true))
        precondition(values.last?.hiddenByFocus == false)
        account.baseline.set(.init())
        precondition(values.last?.hiddenByFocus == true)
        precondition(account.calls.count == queries)
        print("PASS: live folder membership/loading changes update the message without restarting the filtered query")
    }

    static func testPolicyChanges() {
        let policies = ValuePromise(FocusFilterPolicy(configuration: .init(accountIds: [1], mode: .allowSelected, effect: .chatList)))
        let account = Account()
        var values: [ChatListFocusViewUpdate] = []
        let signal = chatListFocusSelection(accountId: 1, policies: policies.get()) |> mapToSignal { selection in
            focusFilteredChatListView(chatListLocation: .chatList(groupId: .root), location: .Initial(50, nil), filter: folder, account: account, selection: selection, policies: policies.get())
        }
        let disposable = signal.start(next: { values.append($0) })
        defer { disposable.dispose() }
        precondition(values.last?.hiddenByFocus == true)
        for configuration in [FocusFilterConfiguration(), .init(accountIds: [1], effect: .notifications), .init(accountIds: [2], effect: .both)] {
            policies.set(FocusFilterPolicy(configuration: configuration))
            precondition(values.last?.hiddenByFocus == false)
            precondition(values.last?.view.list.items.map { $0.renderedPeer.peerId.toInt64() } == [1])
        }
        policies.set(FocusFilterPolicy(configuration: .init(accountIds: [1], mode: .excludeSelected, effect: .both), catalog: .init()))
        precondition(values.last?.hiddenByFocus == false)
        print("PASS: disabling Focus, notification-only effects and untargeted accounts restore the ordinary folder")
    }

    static func testLocalization() {
        let bundle = Bundle(path: CommandLine.arguments[1])!
        let key = "ChatList.Filter.EmptyFocus"
        let russian = "Все чаты в этой папке скрыты настройками фокусирования"
        let english = "All chats in this folder are hidden by Focus settings."
        func language(_ primary: String, secondary: String? = nil, primaryValues: [String: String] = [:], secondaryValues: [String: String] = [:]) -> TelegramLocalization {
            TelegramLocalization(primaryLanguage: .init(languageCode: primary, strings: primaryValues), secondaryLanguage: secondary.map { .init(languageCode: $0, strings: secondaryValues) })
        }
        for code in ["ru", "RU", "ru-RU", "ru_RU"] {
            precondition(chatListFocusEmptyText(language: language(code), bundle: bundle) == russian)
        }
        precondition(chatListFocusEmptyText(language: language("custom", secondary: "ru"), bundle: bundle) == russian)
        precondition(chatListFocusEmptyText(language: language("ru", secondary: "en"), bundle: bundle) == russian)
        precondition(chatListFocusEmptyText(language: language("en", secondary: "ru"), bundle: bundle) == english)
        for code in ["en", "en-US", "fr"] {
            precondition(chatListFocusEmptyText(language: language(code), bundle: bundle) == english)
        }
        precondition(chatListFocusEmptyText(language: language("custom", secondary: "ru", primaryValues: [key: "Primary"], secondaryValues: [key: "Secondary"]), bundle: bundle) == "Primary")
        precondition(chatListFocusEmptyText(language: language("custom", secondary: "ru", primaryValues: [key: ""], secondaryValues: [key: "Secondary"]), bundle: bundle) == "Secondary")
        precondition(chatListFocusEmptyText(language: language("ru", primaryValues: [key: ""]), bundle: bundle) == russian)
        precondition(chatListFocusEmptyText(language: language("ru"), bundle: .main) == english)
        print("PASS: bundled Russian/English text, app-language variants, custom language base, remote override priority and missing-resource fallback")
    }

    static func main() {
        testReasons()
        testLiveBaseline()
        testPolicyChanges()
        testLocalization()
    }
}
