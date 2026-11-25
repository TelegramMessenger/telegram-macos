import XCTest
import Postbox
import TelegramCore
@testable import InAppSettings

final class NativeChatListFilterBadgeTests: XCTestCase {
    private func userId(_ id: Int64) -> EnginePeer.Id {
        return EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: EnginePeer.Id.Id._internalFromInt64Value(id))
    }

    private func secretChatId(_ id: Int64) -> EnginePeer.Id {
        return EnginePeer.Id(namespace: Namespaces.Peer.SecretChat, id: EnginePeer.Id.Id._internalFromInt64Value(id))
    }

    private func folder(categories: ChatListFilterPeerCategories = [], excludeMuted: Bool = false, excludeArchived: Bool = false, include: [EnginePeer.Id] = [], pinned: [EnginePeer.Id] = [], exclude: [EnginePeer.Id] = []) -> ChatListFilterData {
        var includePeers = ChatListFilterIncludePeers()
        for peerId in include {
            let _ = includePeers.addPeer(peerId)
        }
        for peerId in pinned.reversed() {
            let _ = includePeers.addPinnedPeer(peerId)
        }
        return ChatListFilterData(isShared: false, hasSharedLinks: false, categories: categories, excludeMuted: excludeMuted, excludeRead: false, excludeArchived: excludeArchived, includePeers: includePeers, excludePeers: exclude, color: nil)
    }

    private func unread(_ tag: EnginePeerSummaryCounterTags, groupId: EnginePeerGroupId = .root, isMuted: Bool = false) -> ChatListFilterBadgeChat {
        return ChatListFilterBadgeChat(tag: tag, groupId: groupId, isMuted: isMuted)
    }

    private var secretChatsByUserId: [EnginePeer.Id: [EnginePeer.Id]] {
        return [self.userId(1): [self.secretChatId(10)]]
    }

    private var userIdBySecretChatId: [EnginePeer.Id: EnginePeer.Id] {
        return [self.secretChatId(10): self.userId(1)]
    }

    private func correction(_ data: ChatListFilterData, _ unreadChats: [EnginePeer.Id: ChatListFilterBadgeChat]) -> [Int] {
        let value = chatListFilterBadgeCorrection(data: data, unreadChats: unreadChats, secretChatsByUserId: self.secretChatsByUserId, userIdBySecretChatId: self.userIdBySecretChatId)
        return [value.count, value.unmuted]
    }


    func testAPinnedChatIsCountedOnce() {
        let data = self.folder(include: [self.userId(2)], pinned: [self.userId(1)])
        XCTAssertEqual(data.includePeers.peers, [self.userId(1), self.userId(2)])
        XCTAssertEqual(self.correction(data, [self.userId(1): self.unread(.nonContact)]), [1, 1])
    }

    func testAPinnedArchivedChatCountsInAFolderThatExcludesArchived() {
        let data = self.folder(excludeArchived: true, pinned: [self.userId(1)])
        XCTAssertEqual(self.correction(data, [self.userId(1): self.unread(.nonContact, groupId: Namespaces.PeerGroup.archive)]), [1, 1])
    }

    func testAPinnedSecretChatOfAnExcludedUserIsNotSubtracted() {
        let data = self.folder(categories: [.nonContacts], pinned: [self.secretChatId(10)], exclude: [self.userId(1)])
        XCTAssertEqual(data.includePeers.peers, [])
        XCTAssertEqual(self.correction(data, [self.secretChatId(10): self.unread(.nonContact)]), [0, 0])
    }

    func testAPinnedSecretChatOfAnExcludedUserOutsideTheCategoriesIsAdded() {
        let data = self.folder(pinned: [self.secretChatId(10)], exclude: [self.userId(1)])
        XCTAssertEqual(self.correction(data, [self.secretChatId(10): self.unread(.nonContact)]), [1, 1])
    }

    func testAPinnedChatThatIsAlsoExcludedIsShown() {
        let data = self.folder(categories: [.nonContacts], pinned: [self.userId(1)], exclude: [self.userId(1)])
        XCTAssertEqual(self.correction(data, [self.userId(1): self.unread(.nonContact)]), [0, 0])
    }

    func testAPinnedMutedChatCountsInAFolderThatExcludesMuted() {
        let data = self.folder(categories: [.nonContacts], excludeMuted: true, pinned: [self.userId(1)])
        XCTAssertEqual(self.correction(data, [self.userId(1): self.unread(.nonContact, isMuted: true)]), [1, 0])
    }


    func testASecretChatOfAPinnedUserFollowsTheCategories() {
        let data = self.folder(pinned: [self.userId(1)])
        XCTAssertEqual(self.correction(data, [self.secretChatId(10): self.unread(.nonContact)]), [0, 0])
        let withCategory = self.folder(categories: [.nonContacts], pinned: [self.userId(1)])
        XCTAssertEqual(self.correction(withCategory, [self.secretChatId(10): self.unread(.nonContact)]), [0, 0])
    }

    func testASecretChatOfAnIncludedUserIsAdded() {
        let data = self.folder(include: [self.userId(1)])
        XCTAssertEqual(self.correction(data, [self.secretChatId(10): self.unread(.nonContact)]), [1, 1])
    }

    func testASecretChatOfAnExcludedUserIsSubtracted() {
        let data = self.folder(categories: [.nonContacts], exclude: [self.userId(1)])
        XCTAssertEqual(self.correction(data, [self.secretChatId(10): self.unread(.nonContact)]), [-1, -1])
    }


    func testAnIncludedArchivedChatIsNotCountedInAFolderThatExcludesArchived() {
        let data = self.folder(excludeArchived: true, include: [self.userId(1)])
        XCTAssertEqual(self.correction(data, [self.userId(1): self.unread(.nonContact, groupId: Namespaces.PeerGroup.archive)]), [0, 0])
    }

    func testAnIncludedChatOutsideTheCategoriesIsAdded() {
        let data = self.folder(categories: [.groups], include: [self.userId(1)])
        XCTAssertEqual(self.correction(data, [self.userId(1): self.unread(.nonContact)]), [1, 1])
    }

    func testAnIncludedChatInTheCategoriesIsAlreadyCounted() {
        let data = self.folder(categories: [.nonContacts], include: [self.userId(1)])
        XCTAssertEqual(self.correction(data, [self.userId(1): self.unread(.nonContact)]), [0, 0])
    }

    func testAnIncludedMutedChatIsAddedInAFolderThatExcludesMuted() {
        let data = self.folder(categories: [.nonContacts], excludeMuted: true, include: [self.userId(1)])
        XCTAssertEqual(self.correction(data, [self.userId(1): self.unread(.nonContact, isMuted: true)]), [1, 0])
    }

    func testAnExcludedMutedChatIsSubtractedOnlyWhereTheTotalsCountIt() {
        let data = self.folder(categories: [.nonContacts], exclude: [self.userId(1)])
        XCTAssertEqual(self.correction(data, [self.userId(1): self.unread(.nonContact, isMuted: true)]), [-1, 0])
        let excludingMuted = self.folder(categories: [.nonContacts], excludeMuted: true, exclude: [self.userId(1)])
        XCTAssertEqual(self.correction(excludingMuted, [self.userId(1): self.unread(.nonContact, isMuted: true)]), [0, 0])
    }

    func testAnExcludedArchivedChatIsNotSubtractedInAFolderThatExcludesArchived() {
        let data = self.folder(categories: [.nonContacts], excludeArchived: true, exclude: [self.userId(1)])
        XCTAssertEqual(self.correction(data, [self.userId(1): self.unread(.nonContact, groupId: Namespaces.PeerGroup.archive)]), [0, 0])
    }

    func testAReadChatIsNotCorrected() {
        let data = self.folder(include: [self.userId(1)], pinned: [self.userId(2)], exclude: [self.userId(3)])
        XCTAssertEqual(self.correction(data, [:]), [0, 0])
    }
}
