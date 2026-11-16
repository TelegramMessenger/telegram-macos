import XCTest
import Postbox
import TelegramCore
@testable import PeerInfoUI

final class PeerInfoUserReportTests: XCTestCase {
    private let accountId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))

    private func user(_ id: Int64, deleted: Bool = false, bot: Bool = false, flags: UserInfoFlags = []) -> TelegramUser {
        return TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(id)), accessHash: nil, firstName: deleted ? nil : "User", lastName: nil, username: nil, phone: nil, photo: [], botInfo: bot ? BotUserInfo(flags: [], inlinePlaceholder: nil) : nil, restrictionInfo: nil, flags: flags, emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    func testUserProfilesReportTheCloudUser() {
        XCTAssertEqual(peerInfoUserReportTarget(user(2), accountPeerId: accountId), user(2).id)
    }

    func testSecretChatProfileReportsItsUser() {
        let secretChatId = PeerId(namespace: Namespaces.Peer.SecretChat, id: ._internalFromInt64Value(42))
        let target = peerInfoUserReportTarget(user(2), accountPeerId: accountId)
        XCTAssertEqual(target?.namespace, Namespaces.Peer.CloudUser)
        XCTAssertNotEqual(target, secretChatId)
    }

    func testSelfDeletedSupportAndBotProfilesAreExcluded() {
        for peer in [user(1), user(2, deleted: true), user(3, bot: true), user(4, flags: [.isSupport])] {
            XCTAssertNil(peerInfoUserReportTarget(peer, accountPeerId: accountId))
        }
    }

    func testServiceAccountsAreExcluded() {
        for id: Int64 in [777000, 333000, 489000, 708513] {
            XCTAssertNil(peerInfoUserReportTarget(user(id), accountPeerId: accountId))
        }
    }
}
