import XCTest
import Postbox
import TelegramCore
@testable import ChatUI

final class ChatWalletTransferRecipientTests: XCTestCase {
    private let accountId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))
    private let normalizedAddress = "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c"

    private func user(_ id: Int64, firstName: String? = "User", bot: Bool = false, flags: UserInfoFlags = [], namespace: PeerId.Namespace = Namespaces.Peer.CloudUser) -> TelegramUser {
        return TelegramUser(id: PeerId(namespace: namespace, id: ._internalFromInt64Value(id)), accessHash: nil, firstName: firstName, lastName: nil, username: nil, phone: nil, photo: [], botInfo: bot ? BotUserInfo(flags: [], inlinePlaceholder: nil) : nil, restrictionInfo: nil, flags: flags, emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    private func recipient(_ peer: Peer?, address: String = "valid") -> ChatWalletSendRecipient? {
        return chatWalletTransferRecipient(chatPeer: peer, accountPeerId: accountId, peerAddress: address, normalizeAddress: { value in
            value.trimmingCharacters(in: .whitespacesAndNewlines) == "valid" ? self.normalizedAddress : nil
        })
    }

    func testPrivateChatTargetsUserEvenWhenTransferAddressIsDifferent() {
        let peer = user(2)
        guard case let .peer(actual)? = recipient(peer) else { return XCTFail("missing private-chat recipient") }
        XCTAssertEqual(actual.id, peer.id)
    }

    func testPrivateChatDoesNotDependOnAddressLookup() {
        let result = chatWalletTransferRecipient(chatPeer: user(2), accountPeerId: accountId, peerAddress: "invalid", normalizeAddress: { _ in
            XCTFail("ordinary user should use peer resolution")
            return nil
        })
        guard case .peer? = result else { return XCTFail("missing private-chat recipient") }
    }

    func testNotificationsUseOnlyNormalizedCounterpartyAddress() {
        guard case let .address(address)? = recipient(user(777000), address: " valid\n") else { return XCTFail("missing address recipient") }
        XCTAssertEqual(address, normalizedAddress)
    }

    func testNotificationsWithInvalidOrEmptyAddressHaveNoRecipient() {
        for address in ["", " \n", "invalid"] {
            XCTAssertNil(recipient(user(777000), address: address))
        }
    }

    func testServiceBotsSupportDeletedAndSelfHaveNoRecipient() {
        let candidates = [user(333000), user(489000), user(708513), user(2, bot: true), user(3, flags: [.isSupport]), user(4, firstName: nil), user(1)]
        for peer in candidates {
            XCTAssertNil(recipient(peer), "invalid recipient \(peer.id)")
        }
    }

    func testMissingGroupAndNonCloudUsersHaveNoRecipient() {
        XCTAssertNil(recipient(nil))
        let group = TelegramGroup(id: PeerId(namespace: Namespaces.Peer.CloudGroup, id: ._internalFromInt64Value(3)), title: "Group", photo: [], participantCount: 2, role: .member, membership: .Member, flags: [], defaultBannedRights: nil, migrationReference: nil, creationDate: 0, version: 0)
        XCTAssertNil(recipient(group))
        XCTAssertNil(recipient(user(2, namespace: Namespaces.Peer.SecretChat)))
    }
}
