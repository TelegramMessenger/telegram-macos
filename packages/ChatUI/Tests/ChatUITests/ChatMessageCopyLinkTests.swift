import XCTest
import Postbox
import TelegramCore
@testable import ChatUI

final class ChatMessageCopyLinkTests: XCTestCase {
    private func channel(_ id: Int64, flags: TelegramChannelFlags = [], rights: TelegramChatAdminRightsFlags? = nil, linked: PeerId? = nil) -> TelegramChannel {
        return TelegramChannel(id: PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(id)), accessHash: nil, title: "Channel", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: .group(.init(flags: [])), flags: flags, restrictionInfo: nil, adminRights: rights.map { TelegramChatAdminRights(rights: $0) }, bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: linked)
    }

    private func kind(rights: TelegramChatAdminRightsFlags? = nil, creator: Bool = false, known: Bool = true, namespace: MessageId.Namespace = Namespaces.Message.Cloud, service: Bool = false) -> ChatMessageCopyLinkKind? {
        let main = channel(100, flags: creator ? [.isCreator] : [], rights: rights)
        let direct = channel(101, flags: [.isMonoforum], linked: main.id)
        return chatMessageCopyLinkKind(messageId: MessageId(peerId: direct.id, namespace: namespace, id: 42), peer: direct, getPeer: { id in known && id == main.id ? main : nil }, isService: service)
    }

    func testDirectMessagesRequiresManageDirectOrCreator() {
        XCTAssertEqual(kind(rights: [.canManageDirect]), .directMessages)
        XCTAssertEqual(kind(creator: true), .directMessages)
        XCTAssertNil(kind())
        XCTAssertNil(kind(rights: [.canPostMessages, .canEditMessages]))
        XCTAssertNil(kind(rights: [.canManageDirect], known: false))
    }

    func testLocalAndServiceMessagesHaveNoLink() {
        XCTAssertNil(kind(rights: [.canManageDirect], namespace: Namespaces.Message.Local))
        XCTAssertNil(kind(rights: [.canManageDirect], service: true))
    }

    func testOrdinaryChannelsStillUseExportedLinks() {
        let peer = channel(102)
        let id = MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: 42)
        XCTAssertEqual(chatMessageCopyLinkKind(messageId: id, peer: peer, getPeer: { _ in nil }, isService: false), .channelMessage)
        XCTAssertNil(chatMessageCopyLinkKind(messageId: id, peer: nil, getPeer: { _ in nil }, isService: false))
        XCTAssertNil(chatMessageCopyLink(exportedLink: nil, messageId: id, kind: .channelMessage))
        XCTAssertEqual(chatMessageCopyLink(exportedLink: "https://t.me/example/42", messageId: id, kind: .channelMessage), "https://t.me/example/42")
    }

    func testDirectMessagesUsesServerLinkOrPrivateFallback() {
        let id = MessageId(peerId: channel(101).id, namespace: Namespaces.Message.Cloud, id: 42)
        XCTAssertEqual(chatMessageCopyLink(exportedLink: nil, messageId: id, kind: .directMessages), "https://t.me/c/101/42")
        XCTAssertEqual(chatMessageCopyLink(exportedLink: "https://t.me/c/101/42?single", messageId: id, kind: .directMessages), "https://t.me/c/101/42?single")
    }
}
