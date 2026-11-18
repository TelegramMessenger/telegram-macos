import Foundation
import XCTest
import Postbox
import TelegramCore
import TelegramUtils
@testable import ChatHistoryModel

final class RepliesBubbleMergeTests: XCTestCase {
    private let accountPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(100))
    private let discussionGroup = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(2000))
    private let repliesPeer = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1271266957))
    private let channelPeer = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(3000))

    override func setUp() {
        super.setUp()
        TelegramUtilsHooks.install(.init(animationsAreLite: { false }, isLite: { _ in true }, peerTitle: { _ in "" }, peerLetters: { _ in [] }, peerIsForum: { _ in false }, peerCompactTitle: { _ in "" }, repliesPeerId: { self.repliesPeer }))
    }

    private func user(_ id: Int64, _ name: String) -> TelegramUser {
        TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(id)), accessHash: nil, firstName: name, lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    private func group(_ id: PeerId, _ title: String) -> TelegramChannel {
        TelegramChannel(id: id, accessHash: nil, title: title, username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: .group(.init(flags: [])), flags: [], restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    private func message(peerId: PeerId, author: Peer?, forwardAuthor: Peer?, timestamp: Int32, sourcePeerId: PeerId?) -> Message {
        var peers: [PeerId: Peer] = [peerId: peerId == channelPeer ? group(peerId, "Channel") : user(peerId.id._internalGetInt64Value(), "Chat")]
        for peer in [author, forwardAuthor] {
            if let peer = peer {
                peers[peer.id] = peer
            }
        }
        peers[discussionGroup] = group(discussionGroup, "Discussion")
        var attributes: [MessageAttribute] = []
        if let sourcePeerId = sourcePeerId {
            attributes.append(SourceReferenceMessageAttribute(messageId: MessageId(peerId: sourcePeerId, namespace: Namespaces.Message.Cloud, id: 10)))
        }
        var forwardInfo: MessageForwardInfo?
        if let forwardAuthor = forwardAuthor {
            forwardInfo = .init(author: forwardAuthor, source: forwardAuthor, sourceMessageId: MessageId(peerId: sourcePeerId ?? discussionGroup, namespace: Namespaces.Message.Cloud, id: 10), date: timestamp - 5, authorSignature: nil, psaType: nil, flags: [])
        }
        return Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: 10), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: timestamp, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: forwardInfo, author: author, text: "comment", attributes: attributes, media: [], peers: SimpleDictionary(peers), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    func testRepliesCopiesOfDifferentAuthorsDoNotMerge() {
        let first = message(peerId: repliesPeer, author: user(501, "AeroXP"), forwardAuthor: user(501, "AeroXP"), timestamp: 1000, sourcePeerId: discussionGroup)
        let second = message(peerId: repliesPeer, author: user(502, "Katy"), forwardAuthor: user(502, "Katy"), timestamp: 1300, sourcePeerId: discussionGroup)
        XCTAssertFalse(shouldMergeBubbles(upper: first, lower: second, accountPeerId: accountPeerId))
    }

    func testRepliesCopiesOfTheSameAuthorMerge() {
        let first = message(peerId: repliesPeer, author: user(501, "AeroXP"), forwardAuthor: user(501, "AeroXP"), timestamp: 1000, sourcePeerId: discussionGroup)
        let second = message(peerId: repliesPeer, author: user(501, "AeroXP"), forwardAuthor: user(501, "AeroXP"), timestamp: 1200, sourcePeerId: discussionGroup)
        XCTAssertTrue(shouldMergeBubbles(upper: first, lower: second, accountPeerId: accountPeerId))
    }

    func testRepliesCopiesResolveAuthorFromForwardInfoWhenAuthorIsMissing() {
        let first = message(peerId: repliesPeer, author: nil, forwardAuthor: user(501, "AeroXP"), timestamp: 1000, sourcePeerId: discussionGroup)
        let second = message(peerId: repliesPeer, author: nil, forwardAuthor: user(502, "Katy"), timestamp: 1300, sourcePeerId: discussionGroup)
        XCTAssertFalse(shouldMergeBubbles(upper: first, lower: second, accountPeerId: accountPeerId))
    }

    func testChannelCopiesQuotingTheSameSourceChatStillMerge() {
        let first = message(peerId: channelPeer, author: nil, forwardAuthor: nil, timestamp: 1000, sourcePeerId: discussionGroup)
        let second = message(peerId: channelPeer, author: nil, forwardAuthor: nil, timestamp: 1200, sourcePeerId: discussionGroup)
        XCTAssertTrue(shouldMergeBubbles(upper: first, lower: second, accountPeerId: accountPeerId))
    }
}
