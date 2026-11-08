import XCTest
import AppKit
import Postbox
import TelegramCore
@testable import TGUIKit
import Localization
@testable import ChatUI

final class ReactionPeerModerationMenuTests: XCTestCase {
    private static let menuImages: [NSImage] = ["Icon_Menu_More", "Icon_Menu_Selected"].map { name in
        let image = TestImages.named(name)
        _ = image.setName(name)
        return image
    }

    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
        applyMacEnglishStrings()
        _ = Self.menuImages
    }

    private let accountId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))
    private let participantId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(2))

    private func channel(rights: TelegramChatAdminRightsFlags = [], flags: TelegramChannelFlags = [], status: TelegramChannelParticipationStatus = .member, broadcast: Bool = false) -> TelegramChannel {
        return TelegramChannel(id: PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(3)), accessHash: nil, title: "Group", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: status, info: broadcast ? .broadcast(.init(flags: [])) : .group(.init(flags: [])), flags: flags, restrictionInfo: nil, adminRights: rights.isEmpty ? nil : TelegramChatAdminRights(rights: rights), bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    private func message(peer: Peer?, canViewList: Bool = true, hasReactions: Bool = true, namespace: Int32 = Namespaces.Message.Cloud) -> Message {
        let chatId = peer?.id ?? PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(3))
        var peers = SimpleDictionary<PeerId, Peer>()
        if let peer {
            peers[peer.id] = peer
        }
        let attributes: [MessageAttribute] = hasReactions ? [ReactionsMessageAttribute(canViewList: canViewList, isTags: false, reactions: [], recentPeers: [], topPeers: [])] : []
        return Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: chatId, namespace: namespace, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0, flags: [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: nil, text: "Message", attributes: attributes, media: [], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
    }

    private func canModerate(_ message: Message?, participantId: PeerId? = nil, reaction: MessageReaction.Reaction? = .builtin("👍")) -> Bool {
        return ReactionPeerMenu.canModerate(message: message, accountPeerId: accountId, reactionPeerId: participantId ?? self.participantId, reaction: reaction)
    }

    func testCreatorCanModerateAnotherParticipantsReaction() {
        XCTAssertTrue(canModerate(message(peer: channel(flags: [.isCreator]))))
    }

    func testDeleteMessagesRightIsSufficientWithoutBanRight() {
        XCTAssertTrue(canModerate(message(peer: channel(rights: [.canDeleteMessages]))))
    }

    func testBanAndOtherAdminRightsDoNotAuthorizeReactionDeletion() {
        for rights: TelegramChatAdminRightsFlags in [[], [.canBanUsers], [.canAddAdmins], [.canManageRanks]] {
            XCTAssertFalse(canModerate(message(peer: channel(rights: rights))))
        }
    }

    func testOwnReactionDoesNotOfferParticipantModeration() {
        XCTAssertFalse(canModerate(message(peer: channel(flags: [.isCreator])), participantId: accountId))
    }

    func testReadReceiptWithoutReactionDoesNotOfferModeration() {
        XCTAssertFalse(canModerate(message(peer: channel(flags: [.isCreator])), reaction: nil))
    }

    func testPrivateReactionListDoesNotOfferModeration() {
        XCTAssertFalse(canModerate(message(peer: channel(flags: [.isCreator]), canViewList: false)))
    }

    func testMissingMessagePeerOrReactionAttributeDoesNotAuthorize() {
        XCTAssertFalse(canModerate(nil))
        XCTAssertFalse(canModerate(message(peer: nil)))
        XCTAssertFalse(canModerate(message(peer: channel(flags: [.isCreator]), hasReactions: false)))
    }

    func testBroadcastChannelDoesNotExposeReactorModeration() {
        XCTAssertFalse(canModerate(message(peer: channel(flags: [.isCreator], broadcast: true))))
    }

    private func group(role: TelegramGroupRole = .creator(rank: nil), membership: TelegramGroupMembership = .Member) -> TelegramGroup {
        return TelegramGroup(id: PeerId(namespace: Namespaces.Peer.CloudGroup, id: ._internalFromInt64Value(4)), title: "Group", photo: [], participantCount: 2, role: role, membership: membership, flags: [], defaultBannedRights: nil, migrationReference: nil, creationDate: 0, version: 0)
    }

    func testBasicGroupCreatorCanModerateReactions() {
        XCTAssertTrue(canModerate(message(peer: group())))
    }

    func testBasicGroupDeleteAdminCanModerateWithoutBanRights() {
        XCTAssertTrue(canModerate(message(peer: group(role: .admin(.init(rights: [.canDeleteMessages]), rank: nil)))))
    }

    func testBasicGroupOrdinaryMemberCannotModerate() {
        XCTAssertFalse(canModerate(message(peer: group(role: .member))))
    }

    func testBasicGroupUnrelatedAdminRightsDoNotAuthorize() {
        XCTAssertFalse(canModerate(message(peer: group(role: .admin(.init(rights: [.canBanUsers]), rank: nil)))))
    }

    func testDepartedBasicGroupCreatorCannotModerate() {
        XCTAssertFalse(canModerate(message(peer: group(membership: .Left))))
    }

    func testReactionValueDoesNotDependOnAnAnimationFile() {
        let message = message(peer: group())
        XCTAssertTrue(canModerate(message, reaction: .builtin("👍")))
        XCTAssertTrue(canModerate(message, reaction: .custom(42)))
        XCTAssertFalse(canModerate(message, reaction: .stars))
    }

    func testLeftAndKickedAccountsDoNotOfferModeration() {
        for status: TelegramChannelParticipationStatus in [.left, .kicked] {
            XCTAssertFalse(canModerate(message(peer: channel(rights: [.canDeleteMessages], status: status))))
        }
    }

    func testUnsentMessageDoesNotOfferModeration() {
        XCTAssertFalse(canModerate(message(peer: channel(flags: [.isCreator]), namespace: Namespaces.Message.Local)))
    }

    func testCurrentPeerRightsDetermineAuthorization() {
        let original = message(peer: channel(rights: [.canDeleteMessages]))
        XCTAssertTrue(canModerate(original))
        var peers = original.peers
        let updated = channel(rights: [.canBanUsers])
        peers[updated.id] = updated
        XCTAssertFalse(canModerate(original.withUpdatedPeers(peers)))
    }

    func testModerationMenuKeepsProfileAndExplicitReactionDeletionSeparate() throws {
        var actions: [String] = []
        let menu = reactionPeerModerationMenu(openProfile: { actions.append("profile") }, deleteReaction: { actions.append("reaction") })
        XCTAssertEqual(menu.items.count, 2)
        let profile = try XCTUnwrap(menu.items.first as? ContextMenuItem)
        let deletion = try XCTUnwrap(menu.items.last as? ContextMenuItem)
        XCTAssertEqual(profile.title, strings().chatContextPeerOpenInfo)
        XCTAssertEqual(deletion.title, strings().deleteGroupMessagesDeleteReaction)
        XCTAssertTrue(actions.isEmpty)
        profile.handler?()
        XCTAssertEqual(actions, ["profile"])
        deletion.handler?()
        XCTAssertEqual(actions, ["profile", "reaction"])
    }

    func testTimestampIsTheDisabledBottomRowAfterASeparator() throws {
        var actions: [String] = []
        let menu = reactionPeerModerationMenu(openProfile: { actions.append("profile") }, deleteReaction: { actions.append("reaction") }, timestamp: "today at 03:11")
        XCTAssertEqual(menu.items.count, 4)
        XCTAssertTrue(menu.items[2].isSeparatorItem)
        let footer = try XCTUnwrap(menu.items.last as? ContextMenuItem)
        XCTAssertEqual(footer.title, "today at 03:11")
        XCTAssertFalse(footer.isEnabled)
        XCTAssertNil(footer.handler)
        XCTAssertNotNil(footer.itemImage)
        footer.handler?()
        XCTAssertTrue(actions.isEmpty)
        (menu.items[0] as? ContextMenuItem)?.handler?()
        (menu.items[1] as? ContextMenuItem)?.handler?()
        XCTAssertEqual(actions, ["profile", "reaction"])
    }

    func testLongTimestampIsNotTruncatedInTheFooter() {
        let timestamp = "Wednesday, November 18, 2026 at 03:11"
        let menu = reactionPeerModerationMenu(openProfile: {}, deleteReaction: {}, timestamp: timestamp)
        XCTAssertEqual(menu.items.last?.title, timestamp)
    }

    func testLiveRightsRefreshPreservesTimestampFooter() throws {
        let item = ContextMenuItem("Participant")
        let binding = ReactionPeerModerationBinding(item: item, message: message(peer: channel()), accountPeerId: accountId, reactionPeerId: participantId, reaction: .builtin("👍"), timestamp: "today at 03:11", openProfile: {}, deleteReaction: { _ in })
        XCTAssertNil(item.submenu)
        binding.update(peer: channel(rights: [.canDeleteMessages]))
        let submenu = try XCTUnwrap(item.submenu)
        XCTAssertEqual(submenu.items.last?.title, "today at 03:11")
        XCTAssertFalse(try XCTUnwrap(submenu.items.last).isEnabled)
        binding.update(peer: channel(rights: [.canDeleteMessages, .canBanUsers]))
        XCTAssertTrue(item.submenu === submenu)
        XCTAssertEqual(item.submenu?.items.last?.title, "today at 03:11")
    }

    func testRestoredPermissionsRestoreTheTimestampFooter() {
        let item = ContextMenuItem("Participant")
        let binding = ReactionPeerModerationBinding(item: item, message: message(peer: group()), accountPeerId: accountId, reactionPeerId: participantId, reaction: .builtin("👍"), timestamp: "today at 03:11", openProfile: {}, deleteReaction: { _ in })
        XCTAssertEqual(item.submenu?.items.last?.title, "today at 03:11")
        binding.update(peer: group(role: .member))
        XCTAssertNil(item.submenu)
        binding.update(peer: group())
        XCTAssertEqual(item.submenu?.items.last?.title, "today at 03:11")
        XCTAssertEqual(item.submenu?.items.count, 4)
    }

    private func row(item: ContextMenuItem, invoked: @escaping () -> Void, submenu: @escaping () -> Void) -> (AppMenuRowItem, ReactionPeerMenuRowView) {
        let interaction = AppMenuBasicItem.Interaction(action: { _ in invoked() }, presentSubmenu: { _ in submenu() }, cancelSubmenu: { _ in }, hover: { _ in }, close: {})
        let row = AppMenuRowItem(.zero, item: item, interaction: interaction, presentation: .current(PresentationTheme.current.colors))
        let view = ReactionPeerMenuRowView(frame: NSMakeRect(0, 0, 220, 28))
        view.set(item: row)
        return (row, view)
    }

    func testClickOpensModerationSubmenuWithoutInvokingProfileOrDeletion() {
        let item = ContextMenuItem("Participant")
        var deletions = 0
        item.submenu = reactionPeerModerationMenu(openProfile: {}, deleteReaction: { deletions += 1 })
        var actions = 0
        var submenus = 0
        let (row, view) = row(item: item, invoked: { actions += 1 }, submenu: { submenus += 1 })
        XCTAssertTrue(row.showMoreIfNeeded)
        view.invokeClick()
        XCTAssertEqual(submenus, 1)
        XCTAssertEqual(actions, 0)
        XCTAssertEqual(deletions, 0)
    }

    func testBoundParticipantClickOpensSubmenuInsteadOfProfile() {
        for peer: Peer in [group(), group(role: .admin(.init(rights: [.canDeleteMessages]), rank: nil)), channel(rights: [.canDeleteMessages])] {
            var profiles = 0
            var deletedMessages: [MessageId] = []
            let item = ContextMenuItem("Participant", handler: { profiles += 1 })
            let message = message(peer: peer)
            let binding = ReactionPeerModerationBinding(item: item, message: message, accountPeerId: accountId, reactionPeerId: participantId, reaction: .builtin("👍"), openProfile: { profiles += 1 }, deleteReaction: { deletedMessages.append($0.id) })
            withExtendedLifetime(binding) {
                XCTAssertNil(item.handler)
                XCTAssertEqual(item.submenu?.items.count, 2)
                var actions = 0
                var submenus = 0
                let (_, view) = row(item: item, invoked: { actions += 1; item.handler?() }, submenu: { submenus += 1 })
                view.invokeClick()
                view.invokeClick()
                XCTAssertEqual(submenus, 2)
                XCTAssertEqual(actions, 0)
                XCTAssertEqual(profiles, 0)
                XCTAssertTrue(deletedMessages.isEmpty)
                (item.submenu?.items.last as? ContextMenuItem)?.handler?()
                XCTAssertEqual(deletedMessages, [message.id])
            }
        }
    }

    func testCurrentChatUpdateEnablesMenuAfterStaleMessageSnapshot() {
        let item = ContextMenuItem("Participant")
        let binding = ReactionPeerModerationBinding(item: item, message: message(peer: channel()), accountPeerId: accountId, reactionPeerId: participantId, reaction: .custom(42), openProfile: {}, deleteReaction: { _ in })
        XCTAssertNil(item.submenu)
        binding.update(peer: channel(rights: [.canDeleteMessages]))
        XCTAssertNotNil(item.submenu)
        XCTAssertNil(item.handler)
    }

    func testRevokedRightsInvalidatePreviouslyOpenedDeleteAction() throws {
        let item = ContextMenuItem("Participant")
        var deletions = 0
        var profiles = 0
        let binding = ReactionPeerModerationBinding(item: item, message: message(peer: channel(rights: [.canDeleteMessages])), accountPeerId: accountId, reactionPeerId: participantId, reaction: .builtin("👍"), openProfile: { profiles += 1 }, deleteReaction: { _ in deletions += 1 })
        let deletion = try XCTUnwrap(item.submenu?.items.last as? ContextMenuItem)
        binding.update(peer: channel())
        XCTAssertNil(item.submenu)
        deletion.handler?()
        XCTAssertEqual(deletions, 0)
        item.handler?()
        XCTAssertEqual(profiles, 1)
    }

    func testMissingCurrentChatFailsClosedForRetainedSubmenu() throws {
        let item = ContextMenuItem("Participant")
        var deletions = 0
        let binding = ReactionPeerModerationBinding(item: item, message: message(peer: group()), accountPeerId: accountId, reactionPeerId: participantId, reaction: .builtin("👍"), openProfile: {}, deleteReaction: { _ in deletions += 1 })
        let deletion = try XCTUnwrap(item.submenu?.items.last as? ContextMenuItem)
        binding.update(peer: nil)
        deletion.handler?()
        XCTAssertNil(item.submenu)
        XCTAssertEqual(deletions, 0)
    }

    func testDifferentCurrentChatCannotAuthorizeOriginalMessage() {
        let item = ContextMenuItem("Participant")
        let binding = ReactionPeerModerationBinding(item: item, message: message(peer: channel()), accountPeerId: accountId, reactionPeerId: participantId, reaction: .builtin("👍"), openProfile: {}, deleteReaction: { _ in })
        binding.update(peer: group())
        XCTAssertNil(item.submenu)
    }

    func testDisabledModerationItemCannotOpenSubmenu() {
        let item = ContextMenuItem("Participant")
        item.submenu = reactionPeerModerationMenu(openProfile: {}, deleteReaction: {})
        item.isEnabled = false
        var actions = 0
        var submenus = 0
        let (_, view) = row(item: item, invoked: { actions += 1 }, submenu: { submenus += 1 })
        view.invokeClick()
        XCTAssertEqual(actions, 0)
        XCTAssertEqual(submenus, 0)
    }

    func testOrdinaryParticipantRetainsProfileAction() {
        let item = ContextMenuItem("Participant", handler: {})
        var actions = 0
        var submenus = 0
        let (_, view) = row(item: item, invoked: { actions += 1 }, submenu: { submenus += 1 })
        view.invokeClick()
        XCTAssertEqual(actions, 1)
        XCTAssertEqual(submenus, 0)
    }

    func testReactionAndSubmenuChevronHaveEightPointGap() {
        let item = ContextMenuItem("Participant")
        item.submenu = ContextMenu()
        let (row, view) = row(item: item, invoked: {}, submenu: {})
        view.layoutSubtreeIfNeeded()
        let chevronMinX = view.containerView.frame.width - row.leftInset - row.moreSize.width
        let reactionMaxX = view.rightX - reactionPeerMenuSubmenuInset(row)
        XCTAssertEqual(chevronMinX - reactionMaxX, 8)
    }

    func testReactionWithoutSubmenuKeepsItsExistingInset() {
        let item = ContextMenuItem("Participant", handler: {})
        let (row, _) = row(item: item, invoked: {}, submenu: {})
        XCTAssertEqual(reactionPeerMenuSubmenuInset(row), 0)
    }

    func testHiddenChevronDoesNotReserveReactionSpacing() {
        let item = ContextMenuItem("Participant")
        item.submenu = ContextMenu()
        let (row, _) = row(item: item, invoked: {}, submenu: {})
        row.showMoreIfNeeded = false
        XCTAssertEqual(reactionPeerMenuSubmenuInset(row), 0)
    }

    func testReactionSpacingTracksSubmenuAvailability() {
        let item = ContextMenuItem("Participant")
        let (row, _) = row(item: item, invoked: {}, submenu: {})
        XCTAssertEqual(reactionPeerMenuSubmenuInset(row), 0)
        item.submenu = ContextMenu()
        XCTAssertEqual(reactionPeerMenuSubmenuInset(row), 6)
        item.submenu = nil
        XCTAssertEqual(reactionPeerMenuSubmenuInset(row), 0)
    }

    func testForwardingItemRetainsItsDirectAction() {
        let item = ContextMenuItem("Destination", handler: {})
        item.submenu = ContextMenu()
        var actions = 0
        var submenus = 0
        let (_, view) = row(item: item, invoked: { actions += 1 }, submenu: { submenus += 1 })
        view.invokeClick()
        XCTAssertEqual(actions, 1)
        XCTAssertEqual(submenus, 0)
    }
}
