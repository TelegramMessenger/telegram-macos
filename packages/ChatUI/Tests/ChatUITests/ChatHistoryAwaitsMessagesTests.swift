import XCTest
import Postbox
import TelegramCore
import TelegramContext
import ChatHistoryModel

final class ChatHistoryAwaitsMessagesTests: XCTestCase {
    private let peerId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(100))

    private func location(forum: Bool = true) -> ChatLocation {
        return .thread(ChatReplyThreadMessage(peerId: peerId, threadId: 1, channelMessageId: nil, isChannelPost: false, isForumPost: forum, isMonoforumPost: false, maxMessage: nil, maxReadIncomingMessageId: nil, maxReadOutgoingMessageId: nil, unreadCount: 0, initialFilledHoles: IndexSet(), initialAnchor: .automatic, isNotAvailable: false))
    }

    private func message(_ action: TelegramMediaActionType? = nil) -> Message {
        return Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: 1, timestamp: 0, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: nil, text: action == nil ? "Message" : "", attributes: [], media: action.map { [TelegramMediaAction(action: $0)] } ?? [], peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    private func view(_ messages: [Message], loading: Bool = false, earlier: Bool = false, later: Bool = false) -> MessageHistoryView {
        return MessageHistoryView(tag: nil, namespaces: .all, entries: messages.map { MessageHistoryEntry(message: $0, isRead: false, location: nil, monthLocation: nil, attributes: MutableMessageHistoryEntryAttributes(authorIsContact: false)) }, holeEarlier: earlier, holeLater: later, isLoading: loading)
    }

    private func channel(mono: Bool) -> TelegramChannel {
        return TelegramChannel(id: peerId, accessHash: nil, title: "Forum", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: .group(.init(flags: [])), flags: mono ? [.isMonoforum] : [.isForum], restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    private func bot(forum: Bool) -> TelegramUser {
        return TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(200)), accessHash: nil, firstName: "Bot", lastName: nil, username: nil, phone: nil, photo: [], botInfo: BotUserInfo(flags: forum ? [.hasForum] : [], inlinePlaceholder: nil), restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    func testColdForumRootWaitsOnlyWhileHoleRemains() {
        let root = message(.topicCreated(title: "Topic", iconColor: 0, iconFileId: nil))
        for holes in [(true, false), (false, true), (true, true)] {
            XCTAssertTrue(chatHistoryViewAwaitsMessages(view([root], earlier: holes.0, later: holes.1), location: location(), peer: channel(mono: false)))
        }
        XCTAssertFalse(chatHistoryViewAwaitsMessages(view([root]), location: location(), peer: channel(mono: false)))
        XCTAssertFalse(chatHistoryViewAwaitsMessages(view([root, message()], earlier: true), location: location(), peer: channel(mono: false)))
    }

    func testMonoforumAndForumBotGroupCreatedRootsUseSameFilter() {
        let root = message(.groupCreated(title: "Topic"))
        for peer in [channel(mono: true) as Peer, bot(forum: true) as Peer] {
            XCTAssertTrue(chatHistoryMessageIsUndisplayedForumRoot(root, location: location(), peer: peer))
            XCTAssertTrue(chatHistoryViewAwaitsMessages(view([root], later: true), location: location(), peer: peer))
        }
        for peer in [channel(mono: false) as Peer, bot(forum: false) as Peer] {
            XCTAssertFalse(chatHistoryMessageIsUndisplayedForumRoot(root, location: location(), peer: peer))
            XCTAssertFalse(chatHistoryViewAwaitsMessages(view([root], later: true), location: location(), peer: peer))
        }
    }

    func testOrdinaryEmptyChatsAndCommentThreadsNeverWaitOnPersistentHole() {
        let root = message(.topicCreated(title: "Topic", iconColor: 0, iconFileId: nil))
        for location in [ChatLocation.peer(peerId), location(forum: false)] {
            XCTAssertFalse(chatHistoryViewAwaitsMessages(view([root], earlier: true), location: location, peer: channel(mono: false)))
            XCTAssertFalse(chatHistoryViewAwaitsMessages(view([], earlier: true), location: location, peer: channel(mono: false)))
        }
        XCTAssertFalse(chatHistoryViewAwaitsMessages(view([], earlier: true), location: location(), peer: channel(mono: false)))
        XCTAssertFalse(chatHistoryViewAwaitsMessages(view([message()], earlier: true), location: location(), peer: channel(mono: false)))
    }

    func testExplicitLoadingAlwaysRemainsLoading() {
        XCTAssertTrue(chatHistoryViewAwaitsMessages(view([], loading: true), location: .peer(peerId), peer: nil))
        XCTAssertTrue(chatHistoryViewAwaitsMessages(view([message()], loading: true), location: location(forum: false), peer: nil))
    }
}
