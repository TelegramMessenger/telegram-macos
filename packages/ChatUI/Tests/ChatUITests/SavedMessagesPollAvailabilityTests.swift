import XCTest
import Foundation
import Postbox
import TelegramCore
@testable import ChatUI

final class SavedMessagesPollAvailabilityTests: XCTestCase {
    private let accountPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))

    private func user(_ id: Int64, premium: Bool = false, bot: Bool = false) -> TelegramUser {
        return TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(id)), accessHash: nil, firstName: "User", lastName: nil, username: nil, phone: nil, photo: [], botInfo: bot ? BotUserInfo(flags: [], inlinePlaceholder: nil) : nil, restrictionInfo: nil, flags: premium ? [.isPremium] : [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    private func group(banned: TelegramChatBannedRightsFlags = [], role: TelegramGroupRole = .member) -> TelegramGroup {
        return TelegramGroup(id: PeerId(namespace: Namespaces.Peer.CloudGroup, id: ._internalFromInt64Value(3)), title: "Group", photo: [], participantCount: 2, role: role, membership: .Member, flags: [], defaultBannedRights: TelegramChatBannedRights(flags: banned, untilDate: Int32.max), migrationReference: nil, creationDate: 0, version: 0)
    }

    private func channel(broadcast: Bool = false, rights: TelegramChatAdminRightsFlags = [], banned: TelegramChatBannedRightsFlags = []) -> TelegramChannel {
        return TelegramChannel(id: PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(4)), accessHash: nil, title: "Channel", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: broadcast ? .broadcast(.init(flags: [])) : .group(.init(flags: [])), flags: [], restrictionInfo: nil, adminRights: rights.isEmpty ? nil : TelegramChatAdminRights(rights: rights), bannedRights: nil, defaultBannedRights: TelegramChatBannedRights(flags: banned, untilDate: Int32.max), usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    func testSavedMessagesAllowPollsWithoutPremium() {
        let peer = user(1)
        XCTAssertTrue(ChatInputAttachButton.canAttachPoll(peer: peer, mainPeer: peer, accountPeerId: accountPeerId))
    }

    func testSavedMessagesAllowPollsWithPremium() {
        let peer = user(1, premium: true)
        XCTAssertTrue(ChatInputAttachButton.canAttachPoll(peer: peer, mainPeer: peer, accountPeerId: accountPeerId))
    }

    func testSavedMessagesDoNotRequireMainPeer() {
        XCTAssertTrue(ChatInputAttachButton.canAttachPoll(peer: user(1), mainPeer: nil, accountPeerId: accountPeerId))
    }

    func testSavedThreadWithDifferentMainPeerStillAllowsPolls() {
        XCTAssertTrue(ChatInputAttachButton.canAttachPoll(peer: user(1), mainPeer: user(2), accountPeerId: accountPeerId))
    }

    func testMainPeerAloneDoesNotEnablePollsForAnotherPrivateUser() {
        XCTAssertFalse(ChatInputAttachButton.canAttachPoll(peer: user(2), mainPeer: user(1), accountPeerId: accountPeerId))
    }

    func testOtherPrivateUsersDoNotGainPollCreation() {
        for premium in [false, true] {
            let peer = user(2, premium: premium)
            XCTAssertFalse(ChatInputAttachButton.canAttachPoll(peer: peer, mainPeer: peer, accountPeerId: accountPeerId))
        }
    }

    func testDifferentActiveAccountDoesNotTreatAnotherUserAsSavedMessages() {
        let peer = user(1)
        XCTAssertFalse(ChatInputAttachButton.canAttachPoll(peer: peer, mainPeer: peer, accountPeerId: user(2).id))
    }

    func testBotPollCreationRemainsAvailable() {
        let peer = user(2, bot: true)
        XCTAssertTrue(ChatInputAttachButton.canAttachPoll(peer: peer, mainPeer: peer, accountPeerId: accountPeerId))
    }

    func testGroupPollPermissionsArePreserved() {
        let unrestricted = group()
        XCTAssertTrue(ChatInputAttachButton.canAttachPoll(peer: unrestricted, mainPeer: unrestricted, accountPeerId: accountPeerId))
        for banned: TelegramChatBannedRightsFlags in [.banSendPolls, .banSendMedia] {
            let restricted = group(banned: banned)
            XCTAssertFalse(ChatInputAttachButton.canAttachPoll(peer: restricted, mainPeer: restricted, accountPeerId: accountPeerId))
            let creator = group(banned: banned, role: .creator(rank: nil))
            XCTAssertTrue(ChatInputAttachButton.canAttachPoll(peer: creator, mainPeer: creator, accountPeerId: accountPeerId))
        }
    }

    func testSupergroupPollPermissionsArePreserved() {
        let unrestricted = channel()
        XCTAssertTrue(ChatInputAttachButton.canAttachPoll(peer: unrestricted, mainPeer: unrestricted, accountPeerId: accountPeerId))
        for banned: TelegramChatBannedRightsFlags in [.banSendPolls, .banSendMedia] {
            let restricted = channel(banned: banned)
            XCTAssertFalse(ChatInputAttachButton.canAttachPoll(peer: restricted, mainPeer: restricted, accountPeerId: accountPeerId))
        }
    }

    func testBroadcastChannelStillRequiresPostingRights() {
        let reader = channel(broadcast: true)
        XCTAssertFalse(ChatInputAttachButton.canAttachPoll(peer: reader, mainPeer: reader, accountPeerId: accountPeerId))
        let writer = channel(broadcast: true, rights: [.canPostMessages])
        XCTAssertTrue(ChatInputAttachButton.canAttachPoll(peer: writer, mainPeer: writer, accountPeerId: accountPeerId))
    }
}
