import XCTest
import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import ChatModeTypes
@testable import ChatUI

final class ChatAvatarMenuBindingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private let account = NSObject()
    private let interaction = NSObject()

    private func photo(_ id: Int64 = 1, hasVideo: Bool = false) -> TelegramMediaImageRepresentation {
        return TelegramMediaImageRepresentation(dimensions: PixelDimensions(width: 36, height: 36), resource: LocalFileMediaResource(fileId: id), progressiveSizes: [], immediateThumbnailData: nil, hasVideo: hasVideo)
    }

    private func peer(_ id: Int64 = 2, premiumVideo: Bool = false) -> Peer {
        return TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(id)), accessHash: nil, firstName: "Author", lastName: nil, username: nil, phone: nil, photo: premiumVideo ? [photo(hasVideo: true)] : [], botInfo: nil, restrictionInfo: nil, flags: premiumVideo ? [.isPremium] : [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    private func channel(_ id: Int64 = 3, rights: TelegramChatAdminRightsFlags = [.canBanUsers], flags: TelegramChannelFlags = [], status: TelegramChannelParticipationStatus = .member, info: TelegramChannelInfo = .group(.init(flags: [])), title: String = "Group", photo: [TelegramMediaImageRepresentation] = [], boostLevel: Int32? = nil) -> TelegramChannel {
        return TelegramChannel(id: PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(id)), accessHash: nil, title: title, username: nil, photo: photo, creationDate: 0, version: 0, participationStatus: status, info: info, flags: flags, restrictionInfo: nil, adminRights: rights.isEmpty ? nil : TelegramChatAdminRights(rights: rights), bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: boostLevel, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    private func group(title: String = "Group", photo: [TelegramMediaImageRepresentation] = [], participantCount: Int = 10) -> TelegramGroup {
        return TelegramGroup(id: PeerId(namespace: Namespaces.Peer.CloudGroup, id: ._internalFromInt64Value(3)), title: title, photo: photo, participantCount: participantCount, role: .member, membership: .Member, flags: [], defaultBannedRights: nil, migrationReference: nil, creationDate: 0, version: 0)
    }

    private func context(author: Int64 = 2, row: Int = 1, message: Int32 = 1, account: NSObject? = nil, interaction: NSObject? = nil, chat: Peer? = nil, mode: ChatMode = .history, thread: Int64? = nil, stories: Bool = false, premiumVideo: Bool = false) -> ChatAvatarView.MenuContext {
        let peer = self.peer(author, premiumVideo: premiumVideo)
        let chat = chat ?? channel()
        return .init(account: ObjectIdentifier(account ?? self.account), interaction: ObjectIdentifier(interaction ?? self.interaction), chatPeerId: chat.id, threadId: thread, mode: mode, rowId: AnyHashable(row), messageId: MessageId(peerId: chat.id, namespace: Namespaces.Message.Cloud, id: message), peer: peer, chatPeer: .init(chat), hasStories: stories)
    }

    private func factory(_ action: @escaping (String) -> Void) -> () -> ContextMenu? {
        return {
            let menu = ContextMenu()
            menu.items = ["Open Profile", "Send Message", "Mention", "Restrict", "Ban"].map { name in
                ContextMenuItem(name, handler: { action(name) })
            }
            let submenu = ContextMenu()
            submenu.items = [ContextMenuItem("Nested Ban", handler: { action("Nested Ban") })]
            let parent = ContextMenuItem("Actions")
            parent.submenu = submenu
            menu.items += [parent]
            return menu
        }
    }

    private func invoke(_ menu: NSMenu) {
        for case let item as ContextMenuItem in menu.items {
            item.handler?()
            if let submenu = item.submenu { invoke(submenu) }
        }
    }

    func testSameContextRefreshPreservesOpenMenuAndNestedActions() throws {
        let avatar = ChatAvatarView(frame: .zero)
        var calls: [String] = []
        avatar.updateContextMenu(factory { calls.append($0) }, context: context())
        let previousFactory = try XCTUnwrap(avatar.contextMenu)
        let open = try XCTUnwrap(previousFactory())
        avatar.updateContextMenu(factory { calls.append("new " + $0) }, context: context())
        XCTAssertNotNil(previousFactory())
        invoke(open)
        XCTAssertEqual(calls, ["Open Profile", "Send Message", "Mention", "Restrict", "Ban", "Nested Ban"])
        let current = try XCTUnwrap(avatar.contextMenu?())
        invoke(current)
        XCTAssertEqual(calls.count, 12)
        XCTAssertEqual(calls.last, "new Nested Ban")
    }

    func testChatMetadataRefreshPreservesMenusBeforeAndAfterRebinding() throws {
        let chats: [(Peer, [Peer])] = [
            (channel(), [channel(title: "Renamed"), channel(photo: [photo()]), channel(boostLevel: 5), channel(rights: [.canBanUsers, .canChangeInfo]), channel(info: .group(.init(flags: [.slowModeEnabled])))]),
            (group(), [group(title: "Renamed"), group(photo: [photo()]), group(participantCount: 11)])
        ]
        for (chat, updates) in chats {
            for updated in updates {
                XCTAssertFalse(chat.isEqual(updated))
                for stories in [false, true] {
                    for premiumVideo in [false, true] {
                        let avatar = ChatAvatarView(frame: .zero)
                        let captured = context(chat: chat, stories: stories, premiumVideo: premiumVideo)
                        var current = captured
                        var calls: [String] = []
                        avatar.updateContextMenu(factory { calls.append($0) }, context: captured, isCurrent: { current == captured })
                        let previousFactory = try XCTUnwrap(avatar.contextMenu)
                        let open = try XCTUnwrap(previousFactory())
                        current = context(chat: updated, stories: stories, premiumVideo: premiumVideo)
                        XCTAssertEqual(captured, current)
                        invoke(try XCTUnwrap(previousFactory()))
                        invoke(open)
                        XCTAssertEqual(calls.count, 12)
                        avatar.updateContextMenu(factory { calls.append("new " + $0) }, context: current, isCurrent: { current == captured })
                        XCTAssertNotNil(previousFactory())
                        invoke(open)
                        XCTAssertEqual(calls.count, 18)
                        invoke(try XCTUnwrap(avatar.contextMenu?()))
                        XCTAssertEqual(calls.count, 24)
                        XCTAssertEqual(calls.last, "new Nested Ban")
                    }
                }
            }
        }
    }

    func testSemanticContextChangesInvalidateAllOpenActions() throws {
        let otherAccount = NSObject()
        let otherInteraction = NSObject()
        let replacements = [context(author: 4), context(row: 2), context(message: 2), context(account: otherAccount), context(interaction: otherInteraction), context(chat: channel(rights: [])), context(chat: channel(4)), context(chat: group()), context(mode: .pinned), context(thread: 7), context(stories: true)]
        for replacement in replacements {
            let avatar = ChatAvatarView(frame: .zero)
            var calls: [String] = []
            avatar.updateContextMenu(factory { calls.append($0) }, context: context())
            let previousFactory = try XCTUnwrap(avatar.contextMenu)
            let open = try XCTUnwrap(previousFactory())
            avatar.updateContextMenu(factory { calls.append($0) }, context: replacement)
            XCTAssertNil(previousFactory())
            invoke(open)
            XCTAssertTrue(calls.isEmpty)
            invoke(try XCTUnwrap(avatar.contextMenu?()))
            XCTAssertEqual(calls.count, 6)
        }
    }

    func testLiveChatActionChangesInvalidateMenusBeforeAndAfterRebinding() throws {
        let allRights: TelegramChatAdminRightsFlags = [.canBanUsers, .canAddAdmins, .canManageRanks]
        let replacements: [Peer] = [
            channel(rights: [.canAddAdmins, .canManageRanks]),
            channel(rights: [.canBanUsers, .canManageRanks]),
            channel(rights: [.canBanUsers, .canAddAdmins]),
            channel(rights: allRights, flags: [.isCreator]),
            channel(rights: allRights, flags: [.isMonoforum]),
            channel(rights: allRights, status: .left),
            channel(rights: allRights, status: .kicked),
            channel(rights: allRights, info: .broadcast(.init(flags: []))),
            channel(4, rights: allRights),
            group()
        ]
        for replacement in replacements {
            let avatar = ChatAvatarView(frame: .zero)
            let captured = context(chat: channel(rights: allRights))
            var current = captured
            var calls: [String] = []
            avatar.updateContextMenu(factory { calls.append($0) }, context: captured, isCurrent: { current == captured })
            let previousFactory = try XCTUnwrap(avatar.contextMenu)
            let open = try XCTUnwrap(previousFactory())
            current = context(chat: replacement)
            XCTAssertNotEqual(current, captured)
            XCTAssertNil(previousFactory())
            invoke(open)
            XCTAssertTrue(calls.isEmpty)
            avatar.updateContextMenu(factory { calls.append($0) }, context: current)
            XCTAssertNil(previousFactory())
            invoke(open)
            XCTAssertTrue(calls.isEmpty)
            invoke(try XCTUnwrap(avatar.contextMenu?()))
            XCTAssertEqual(calls.count, 6)
        }
    }

    func testCreatorLossInvalidatesModerationEvenWithSameEffectiveRights() throws {
        let avatar = ChatAvatarView(frame: .zero)
        let rights: TelegramChatAdminRightsFlags = [.canBanUsers, .canAddAdmins, .canManageRanks]
        let captured = context(chat: channel(rights: rights, flags: [.isCreator]))
        var current = captured
        var calls: [String] = []
        avatar.updateContextMenu(factory { calls.append($0) }, context: captured, isCurrent: { current == captured })
        let previousFactory = try XCTUnwrap(avatar.contextMenu)
        let open = try XCTUnwrap(previousFactory())
        current = context(chat: channel(rights: rights))
        XCTAssertNil(previousFactory())
        invoke(open)
        XCTAssertTrue(calls.isEmpty)
    }

    func testMissingLiveChatInvalidatesMenu() throws {
        let avatar = ChatAvatarView(frame: .zero)
        let captured = context()
        var current = captured
        var calls: [String] = []
        avatar.updateContextMenu(factory { calls.append($0) }, context: captured, isCurrent: { current == captured })
        let open = try XCTUnwrap(avatar.contextMenu?())
        current = .init(account: captured.account, interaction: captured.interaction, chatPeerId: captured.chatPeerId, threadId: captured.threadId, mode: captured.mode, rowId: captured.rowId, messageId: captured.messageId, peer: captured.peer, chatPeer: nil, hasStories: captured.hasStories)
        XCTAssertNil(avatar.contextMenu?())
        invoke(open)
        XCTAssertTrue(calls.isEmpty)
    }

    func testRefreshUsesLatestRowLivenessCheck() throws {
        let avatar = ChatAvatarView(frame: .zero)
        var previousAlive = true
        var currentAlive = true
        var calls: [String] = []
        avatar.updateContextMenu(factory { calls.append($0) }, context: context(), isCurrent: { previousAlive })
        let open = try XCTUnwrap(avatar.contextMenu?())
        previousAlive = false
        avatar.updateContextMenu(factory { calls.append($0) }, context: context(), isCurrent: { currentAlive })
        invoke(open)
        XCTAssertEqual(calls.count, 6)
        currentAlive = false
        invoke(open)
        XCTAssertEqual(calls.count, 6)
    }

    func testRemovalInvalidatesSameContextMenu() throws {
        let avatar = ChatAvatarView(frame: .zero)
        var calls: [String] = []
        avatar.updateContextMenu(factory { calls.append($0) }, context: context())
        let open = try XCTUnwrap(avatar.contextMenu?())
        avatar.updateContextMenu(nil)
        XCTAssertNil(avatar.contextMenu)
        invoke(open)
        XCTAssertTrue(calls.isEmpty)
    }

    func testReuseInvalidatesOldActionsAndUsesNewAuthor() throws {
        let avatar = ChatAvatarView(frame: .zero)
        var calls: [String] = []
        func factory(_ author: String) -> () -> ContextMenu? {
            return {
                let menu = ContextMenu()
                let submenu = ContextMenu()
                submenu.items = [ContextMenuItem("Ban", handler: { calls.append(author) })]
                let parent = ContextMenuItem("Actions")
                parent.submenu = submenu
                menu.items = [ContextMenuItem("Open", handler: { calls.append(author) }), parent]
                return menu
            }
        }
        avatar.updateContextMenu(factory("A"))
        let oldFactory = try XCTUnwrap(avatar.contextMenu)
        let old = try XCTUnwrap(oldFactory())
        avatar.updateContextMenu(factory("B"))
        XCTAssertNil(oldFactory())
        (old.items[0] as? ContextMenuItem)?.handler?()
        (old.items[1].submenu?.items[0] as? ContextMenuItem)?.handler?()
        XCTAssertTrue(calls.isEmpty)
        let current = try XCTUnwrap(avatar.contextMenu?())
        (current.items[0] as? ContextMenuItem)?.handler?()
        (current.items[1].submenu?.items[0] as? ContextMenuItem)?.handler?()
        XCTAssertEqual(calls, ["B", "B"])
        avatar.updateContextMenu(factory("B-new-item"))
        (current.items[0] as? ContextMenuItem)?.handler?()
        XCTAssertEqual(calls, ["B", "B"])
        let replacement = try XCTUnwrap(avatar.contextMenu?())
        (replacement.items[0] as? ContextMenuItem)?.handler?()
        XCTAssertEqual(calls.last, "B-new-item")
        avatar.updateContextMenu(nil)
        XCTAssertNil(avatar.contextMenu)
        (replacement.items[0] as? ContextMenuItem)?.handler?()
        XCTAssertEqual(calls.count, 3)
    }
}
