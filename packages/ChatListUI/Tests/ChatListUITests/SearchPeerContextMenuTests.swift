import XCTest
import TGUIKit
import Localization
import Postbox
import TelegramCore
@testable import ChatListUI

final class SearchPeerContextMenuTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
        applyMacEnglishStrings()
    }

    private func actions(_ record: @escaping (String) -> Void = { _ in }) -> SearchPeerMenuActions {
        return SearchPeerMenuActions(openProfile: { record("profile") }, markRead: { record($0 ? "read" : "unread") }, toggleMute: { record("toggleMute") }, mute: { record("mute:\($0)") }, muteUntil: { record("until") }, togglePin: { record("pin") })
    }

    private func state(canPin: Bool = false, unread: Bool = false, muted: Bool = false, pinned: Bool = false, profile: Bool = true, manage: Bool = true, canMarkRead: Bool = true, canMarkUnread: Bool = true) -> SearchPeerMenuState {
        return SearchPeerMenuState(canOpenProfile: profile, canManageChat: manage, canMarkRead: canMarkRead, canMarkUnread: canMarkUnread, canPin: canPin, isUnread: unread, isMuted: muted, isPinned: pinned)
    }

    private func labels(_ items: [ContextMenuItem]) -> [String] {
        return items.map { $0 is ContextSeparatorItem ? "separator" : $0.title }
    }

    func testPopularKeepsOriginalRemovalAndDoesNotOfferPin() throws {
        var removed = 0
        let remove = ContextMenuItem(strings().searchPopularDelete, handler: { removed += 1 }, itemMode: .destruct)
        let folder = ContextMenuItem("Work")
        let items = searchPeerMenuItems(state: state(), profileTitle: strings().exportedInvitationContextOpenProfile, actions: actions(), folders: [folder], remove: remove)
        XCTAssertEqual(labels(items), [strings().exportedInvitationContextOpenProfile, strings().chatListContextMaskAsUnread, strings().chatListContextMute, "separator", strings().chatListFilterAddToFolder, "separator", strings().searchPopularDelete])
        XCTAssertTrue(items.last === remove)
        items.last?.handler?()
        XCTAssertEqual(removed, 1)
        XCTAssertTrue(items[4].submenu?.items.first === folder)
    }

    func testRecentReadMutedPinnedStatesAndCallbacks() {
        var called: [String] = []
        let remove = ContextMenuItem(strings().searchRemoveFromRecent)
        let items = searchPeerMenuItems(state: state(canPin: true, unread: true, muted: true, pinned: true), profileTitle: "Profile", actions: actions { called.append($0) }, folders: [ContextMenuItem("Work")], remove: remove)
        XCTAssertEqual(labels(items), ["Profile", strings().chatListContextMaskAsRead, strings().chatListContextUnmute, "separator", strings().chatListContextUnpin, strings().chatListFilterAddToFolder, "separator", strings().searchRemoveFromRecent])
        items[0].handler?()
        items[1].handler?()
        items[2].handler?()
        items[4].handler?()
        XCTAssertEqual(called, ["profile", "read", "toggleMute", "pin"])
        XCTAssertNil(items[2].submenu)
    }

    func testSearchResultsRetainPinWithoutRemovalOrTrailingSeparator() {
        let items = searchPeerMenuItems(state: state(canPin: true), profileTitle: "Profile", actions: actions(), folders: [ContextMenuItem("Work")], remove: nil)
        XCTAssertEqual(labels(items), ["Profile", strings().chatListContextMaskAsUnread, strings().chatListContextMute, "separator", strings().chatListContextPin, strings().chatListFilterAddToFolder])
        XCTAssertFalse(items.last is ContextSeparatorItem)
    }

    func testMuteParentUsesChooserWithoutSelectingADuration() {
        var called: [String] = []
        let items = searchPeerMenuItems(state: state(), profileTitle: "Profile", actions: actions { called.append($0) }, folders: [], remove: nil)
        items[2].handler?()
        XCTAssertEqual(called, ["toggleMute"])
        XCTAssertNotNil(items[2].submenu)
    }

    func testSecretChatsKeepNotificationsButOmitBothReadActions() {
        for unread in [false, true] {
            let items = searchPeerMenuItems(state: state(canPin: true, unread: unread, canMarkRead: false, canMarkUnread: false), profileTitle: "Profile", actions: actions(), folders: [], remove: nil)
            XCTAssertEqual(labels(items), ["Profile", strings().chatListContextMute, "separator", strings().chatListContextPin])
        }
    }

    func testNotificationSubmenuDurationsAndUnreadAction() throws {
        var called: [String] = []
        let items = searchPeerMenuItems(state: state(), profileTitle: "Profile", actions: actions { called.append($0) }, folders: [], remove: nil)
        items[1].handler?()
        let submenu = try XCTUnwrap(items[2].submenu)
        XCTAssertEqual(submenu.items.count, 6)
        for item in submenu.items where !(item is ContextSeparatorItem) {
            (item as? ContextMenuItem)?.handler?()
        }
        XCTAssertEqual(called, ["unread", "mute:3600", "mute:28800", "mute:259200", "until", "mute:2147483647"])
    }

    func testReadOnlyUnreadPolicyDoesNotHideMuteForForums() {
        let read = searchPeerMenuItems(state: state(canMarkUnread: false), profileTitle: "Profile", actions: actions(), folders: [], remove: nil)
        XCTAssertEqual(labels(read), ["Profile", strings().chatListContextMute])
        XCTAssertNotNil(read[1].submenu)
        var called: [String] = []
        let unread = searchPeerMenuItems(state: state(unread: true, canMarkUnread: false), profileTitle: "Profile", actions: actions { called.append($0) }, folders: [], remove: nil)
        XCTAssertEqual(labels(unread), ["Profile", strings().chatListContextMaskAsRead, strings().chatListContextMute])
        unread[1].handler?()
        XCTAssertEqual(called, ["read"])
    }

    func testChannelDirectMessagesKeepTheirOwnNotificationIdentity() {
        let channelId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(10))
        let messagesId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(11))
        let messages = TelegramChannel(id: messagesId, accessHash: nil, title: "Messages", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: .group(TelegramChannelGroupInfo(flags: [])), flags: [.isMonoforum], restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: channelId)
        XCTAssertEqual(messages.associatedPeerId, channelId)
        XCTAssertNil(messages.notificationSettingsPeerId)
        XCTAssertEqual(searchPeerNotificationPeerId(messages), messagesId)
        XCTAssertNotEqual(searchPeerNotificationPeerId(messages), channelId)
    }

    func testSecretChatsKeepTheirExplicitNotificationPeer() {
        let secretId = PeerId(namespace: Namespaces.Peer.SecretChat, id: ._internalFromInt64Value(20))
        let userId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(21))
        let secret = TelegramSecretChat(id: secretId, creationDate: 0, regularPeerId: userId, accessHash: 0, role: .creator, embeddedState: .active, messageAutoremoveTimeout: nil)
        XCTAssertEqual(searchPeerNotificationPeerId(secret), userId)
        XCTAssertNotEqual(searchPeerNotificationPeerId(secret), secretId)
    }

    func testSavedSubchatMenuCannotMutateRegularChatState() {
        for pinned in [false, true] {
            var calls: [String] = []
            let items = searchSavedPeerMenuItems(profileTitle: "Profile", isPinned: pinned, openProfile: { calls.append("profile") }, togglePin: { calls.append("savedPin") })
            XCTAssertEqual(labels(items), ["Profile", "separator", pinned ? strings().chatListContextUnpin : strings().chatListContextPin])
            items[0].handler?()
            items[2].handler?()
            XCTAssertEqual(calls, ["profile", "savedPin"])
            XCTAssertTrue(items.allSatisfy { $0.submenu == nil })
        }
        let own = searchSavedPeerMenuItems(profileTitle: nil, isPinned: false, openProfile: {}, togglePin: {})
        XCTAssertEqual(labels(own), [strings().chatListContextPin])
    }

    func testMissingChatAndSavedMessagesOmitInapplicableActions() {
        let missing = searchPeerMenuItems(state: state(manage: false), profileTitle: "Profile", actions: actions(), folders: [], remove: nil)
        XCTAssertEqual(labels(missing), ["Profile"])
        let saved = searchPeerMenuItems(state: state(canPin: true, profile: false, manage: false), profileTitle: "Profile", actions: actions(), folders: [ContextMenuItem("Work")], remove: nil)
        XCTAssertEqual(labels(saved), [strings().chatListContextPin, strings().chatListFilterAddToFolder])
        let remove = ContextMenuItem(strings().searchPopularDelete)
        let removalOnly = searchPeerMenuItems(state: state(profile: false, manage: false), profileTitle: "Profile", actions: actions(), folders: [], remove: remove)
        XCTAssertEqual(removalOnly.count, 1)
        XCTAssertTrue(removalOnly[0] === remove)
    }
}
