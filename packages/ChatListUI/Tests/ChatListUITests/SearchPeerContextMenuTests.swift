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
        return SearchPeerMenuActions(openProfile: { record("profile") }, toggleMute: { record("toggleMute") }, mute: { record("mute:\($0)") }, muteUntil: { record("until") }, togglePin: { record("pin") })
    }

    private func state(canPin: Bool = false, muted: Bool = false, pinned: Bool = false, profile: Bool = true, manage: Bool = true) -> SearchPeerMenuState {
        return SearchPeerMenuState(canOpenProfile: profile, canManageChat: manage, canPin: canPin, isMuted: muted, isPinned: pinned)
    }

    private func readItem(unread: Bool = false, handler: @escaping () -> Void = {}) -> ContextMenuItem {
        return ContextMenuItem(unread ? strings().chatListContextMaskAsRead : strings().chatListContextMaskAsUnread, handler: handler)
    }

    private func labels(_ items: [ContextMenuItem]) -> [String] {
        return items.map { $0 is ContextSeparatorItem ? "separator" : $0.title }
    }

    func testPopularKeepsOriginalRemovalAndDoesNotOfferPin() throws {
        var removed = 0
        let remove = ContextMenuItem(strings().searchPopularDelete, handler: { removed += 1 }, itemMode: .destruct)
        let folder = ContextMenuItem("Work")
        let items = searchPeerMenuItems(state: state(), profileTitle: strings().exportedInvitationContextOpenProfile, actions: actions(), readItem: readItem(), folders: [folder], remove: remove)
        XCTAssertEqual(labels(items), [strings().exportedInvitationContextOpenProfile, strings().chatListContextMaskAsUnread, strings().chatListContextMute, "separator", strings().chatListFilterAddToFolder, "separator", strings().searchPopularDelete])
        XCTAssertTrue(items.last === remove)
        items.last?.handler?()
        XCTAssertEqual(removed, 1)
        XCTAssertTrue(items[4].submenu?.items.first === folder)
    }

    func testRecentReadMutedPinnedStatesAndCallbacks() {
        var called: [String] = []
        let remove = ContextMenuItem(strings().searchRemoveFromRecent)
        let read = readItem(unread: true) { called.append("read") }
        let items = searchPeerMenuItems(state: state(canPin: true, muted: true, pinned: true), profileTitle: "Profile", actions: actions { called.append($0) }, readItem: read, folders: [ContextMenuItem("Work")], remove: remove)
        XCTAssertEqual(labels(items), ["Profile", strings().chatListContextMaskAsRead, strings().chatListContextUnmute, "separator", strings().chatListContextUnpin, strings().chatListFilterAddToFolder, "separator", strings().searchRemoveFromRecent])
        items[0].handler?()
        items[1].handler?()
        items[2].handler?()
        items[4].handler?()
        XCTAssertEqual(called, ["profile", "read", "toggleMute", "pin"])
        XCTAssertNil(items[2].submenu)
    }

    func testSearchResultsRetainPinWithoutRemovalOrTrailingSeparator() {
        let items = searchPeerMenuItems(state: state(canPin: true), profileTitle: "Profile", actions: actions(), readItem: readItem(), folders: [ContextMenuItem("Work")], remove: nil)
        XCTAssertEqual(labels(items), ["Profile", strings().chatListContextMaskAsUnread, strings().chatListContextMute, "separator", strings().chatListContextPin, strings().chatListFilterAddToFolder])
        XCTAssertFalse(items.last is ContextSeparatorItem)
    }

    func testMuteParentUsesChooserWithoutSelectingADuration() {
        var called: [String] = []
        let items = searchPeerMenuItems(state: state(), profileTitle: "Profile", actions: actions { called.append($0) }, readItem: readItem(), folders: [], remove: nil)
        items[2].handler?()
        XCTAssertEqual(called, ["toggleMute"])
        XCTAssertNotNil(items[2].submenu)
    }

    func testAbsentReadActionKeepsNotificationsAndPinning() {
        let items = searchPeerMenuItems(state: state(canPin: true), profileTitle: "Profile", actions: actions(), readItem: nil, folders: [], remove: nil)
        XCTAssertEqual(labels(items), ["Profile", strings().chatListContextMute, "separator", strings().chatListContextPin])
    }

    func testNotificationSubmenuDurationsAndUnreadAction() throws {
        var called: [String] = []
        let read = readItem { called.append("unread") }
        let items = searchPeerMenuItems(state: state(), profileTitle: "Profile", actions: actions { called.append($0) }, readItem: read, folders: [], remove: nil)
        items[1].handler?()
        let submenu = try XCTUnwrap(items[2].submenu)
        XCTAssertEqual(submenu.items.count, 6)
        for item in submenu.items where !(item is ContextSeparatorItem) {
            (item as? ContextMenuItem)?.handler?()
        }
        XCTAssertEqual(called, ["unread", "mute:3600", "mute:28800", "mute:259200", "until", "mute:2147483647"])
    }

    func testSuppliedReadActionRetainsIdentityAndHandlerWithoutDuplication() {
        for unread in [false, true] {
            var called = 0
            let read = readItem(unread: unread) { called += 1 }
            let items = searchPeerMenuItems(state: state(), profileTitle: "Profile", actions: actions(), readItem: read, folders: [], remove: nil)
            XCTAssertEqual(labels(items), ["Profile", read.title, strings().chatListContextMute])
            XCTAssertTrue(items[1] === read)
            XCTAssertEqual(items.filter { $0.title == read.title }.count, 1)
            items[1].handler?()
            XCTAssertEqual(called, 1)
        }
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

    func testMissingChatOmitsInapplicableActions() {
        let missing = searchPeerMenuItems(state: state(manage: false), profileTitle: "Profile", actions: actions(), readItem: nil, folders: [], remove: nil)
        XCTAssertEqual(labels(missing), ["Profile"])
        let remove = ContextMenuItem(strings().searchPopularDelete)
        let removalOnly = searchPeerMenuItems(state: state(profile: false, manage: false), profileTitle: "Profile", actions: actions(), readItem: nil, folders: [], remove: remove)
        XCTAssertEqual(removalOnly.count, 1)
        XCTAssertTrue(removalOnly[0] === remove)
    }

    private func sponsoredPeer(opaqueId: Data) -> AdPeer {
        let peer = TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(42)), accessHash: nil, firstName: "Sponsored", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
        return AdPeer(opaqueId: opaqueId, peer: .user(peer), subscribers: nil, sponsorInfo: nil, additionalInfo: nil)
    }

    func testSponsoredProfileSelectionCountsClickBeforeOpening() throws {
        let ad = sponsoredPeer(opaqueId: Data([1, 2, 3]))
        var calls: [String] = []
        let open = searchPeerOpenProfileAction(adPeer: ad, markAdAction: { opaqueId, media, fullscreen in
            XCTAssertEqual(opaqueId, ad.opaqueId)
            XCTAssertFalse(media)
            XCTAssertFalse(fullscreen)
            calls.append("ad")
        }, openProfile: { calls.append("profile") })
        let callbacks = SearchPeerMenuActions(openProfile: open, toggleMute: { calls.append("mute") }, mute: { _ in }, muteUntil: {}, togglePin: { calls.append("pin") })
        let items = searchPeerMenuItems(state: state(canPin: true), profileTitle: "Profile", actions: callbacks, readItem: nil, folders: [], remove: nil)
        XCTAssertTrue(calls.isEmpty)
        try XCTUnwrap(items.first { $0.title == strings().chatListContextMute }).handler?()
        try XCTUnwrap(items.first { $0.title == strings().chatListContextPin }).handler?()
        XCTAssertEqual(calls, ["mute", "pin"])
        try XCTUnwrap(items.first { $0.title == "Profile" }).handler?()
        XCTAssertEqual(calls, ["mute", "pin", "ad", "profile"])
    }

    func testOrdinaryProfileSelectionDoesNotCountAnAdClick() throws {
        var opened = 0
        let open = searchPeerOpenProfileAction(adPeer: nil, markAdAction: { _, _, _ in XCTFail("Ordinary peer must not report an ad click") }, openProfile: { opened += 1 })
        let callbacks = SearchPeerMenuActions(openProfile: open, toggleMute: {}, mute: { _ in }, muteUntil: {}, togglePin: {})
        let items = searchPeerMenuItems(state: state(), profileTitle: "Profile", actions: callbacks, readItem: nil, folders: [], remove: nil)
        XCTAssertEqual(opened, 0)
        try XCTUnwrap(items.first).handler?()
        XCTAssertEqual(opened, 1)
    }

    func testSponsoredResultsForSamePeerKeepTheirOwnOpaqueIds() {
        let first = sponsoredPeer(opaqueId: Data([4, 5]))
        let second = sponsoredPeer(opaqueId: Data([6, 7]))
        XCTAssertEqual(first.peer.id, second.peer.id)
        var recorded: [Data] = []
        var opened = 0
        let actions = [first, second].map { ad in
            searchPeerOpenProfileAction(adPeer: ad, markAdAction: { opaqueId, _, _ in recorded.append(opaqueId) }, openProfile: { opened += 1 })
        }
        XCTAssertTrue(recorded.isEmpty)
        actions[1]()
        actions[0]()
        XCTAssertEqual(recorded, [second.opaqueId, first.opaqueId])
        XCTAssertEqual(opened, 2)
    }

    func testReopeningSponsoredMenusOnlyCountsChosenProfileActions() throws {
        let ad = sponsoredPeer(opaqueId: Data([8, 9]))
        var clicks = 0
        var opened = 0
        func menu() -> [ContextMenuItem] {
            let open = searchPeerOpenProfileAction(adPeer: ad, markAdAction: { _, _, _ in clicks += 1 }, openProfile: { opened += 1 })
            return searchPeerMenuItems(state: state(), profileTitle: "Profile", actions: SearchPeerMenuActions(openProfile: open, toggleMute: {}, mute: { _ in }, muteUntil: {}, togglePin: {}), readItem: nil, folders: [], remove: nil)
        }
        _ = menu()
        let selected = menu()
        _ = menu()
        XCTAssertEqual(clicks, 0)
        XCTAssertEqual(opened, 0)
        try XCTUnwrap(selected.first).handler?()
        XCTAssertEqual(clicks, 1)
        XCTAssertEqual(opened, 1)
        try XCTUnwrap(menu().first).handler?()
        XCTAssertEqual(clicks, 2)
        XCTAssertEqual(opened, 2)
    }

    func testSavedMessagesAccountRetainsReadActionWithoutProfileOrMute() {
        for unread in [false, true] {
            var calls = 0
            let read = readItem(unread: unread) { calls += 1 }
            let saved = searchPeerMenuItems(state: state(canPin: true, profile: false, manage: false), profileTitle: "Profile", actions: actions(), readItem: read, folders: [ContextMenuItem("Work")], remove: nil)
            XCTAssertEqual(labels(saved), [read.title, "separator", strings().chatListContextPin, strings().chatListFilterAddToFolder])
            XCTAssertTrue(saved.first === read)
            saved.first?.handler?()
            XCTAssertEqual(calls, 1)
        }
    }
}
