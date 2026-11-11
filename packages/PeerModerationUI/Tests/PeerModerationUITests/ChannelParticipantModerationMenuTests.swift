import XCTest
import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
@testable import ChatUI
@testable import PeerModerationUI

final class ChannelParticipantModerationMenuTests: XCTestCase {
    private static let themeImages: [NSImage] = {
        let assets = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Telegram-Mac/Assets.xcassets")
        return [("Icon_SearchField", "search-icon@2x.png"), ("Icon_SearchClear", "ic_delete@2x.png"), ("Icon_Quote", "ic_quote_10@2x.png"), ("Icon_Quote_Collapse", "collapse_16@2x.png"), ("Icon_Quote_Expand", "expand_16@2x.png")].compactMap { name, file in
            guard let image = NSImage(contentsOf: assets.appendingPathComponent(name + ".imageset").appendingPathComponent(file)) else {
                XCTFail("Missing theme image: \(name)")
                return nil
            }
            image.size = NSSize(width: image.size.width / 2, height: image.size.height / 2)
            image.setName(name)
            return image
        }
    }()

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        XCTAssertEqual(Self.themeImages.count, 5)
    }

    private let accountPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(1))

    private func peer(_ id: Int64 = 2) -> Peer {
        return TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(id)), accessHash: nil, firstName: "Author", lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    private func channel(rights: TelegramChatAdminRightsFlags = [.canBanUsers], flags: TelegramChannelFlags = [], broadcast: Bool = false) -> TelegramChannel {
        return TelegramChannel(id: PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(3)), accessHash: nil, title: "Group", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: broadcast ? .broadcast(.init(flags: [])) : .group(.init(flags: [])), flags: flags, restrictionInfo: nil, adminRights: rights.isEmpty ? nil : TelegramChatAdminRights(rights: rights), bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    private func participant(_ id: Int64 = 2, admin: Bool = false, editable: Bool = false, promotedByAccount: Bool = false) -> ChannelParticipant {
        let adminInfo = admin ? ChannelParticipantAdminInfo(rights: TelegramChatAdminRights(rights: [.canBanUsers]), promotedBy: promotedByAccount ? accountPeerId : peer(4).id, canBeEditedByAccountPeer: editable) : nil
        return .member(id: peer(id).id, invitedAt: 0, adminInfo: adminInfo, banInfo: nil, rank: nil, subscriptionUntilDate: nil)
    }

    private func flushMainQueue() {
        let delivered = expectation(description: "Main queue delivered")
        DispatchQueue.main.async { delivered.fulfill() }
        wait(for: [delivered], timeout: 1)
    }

    func testMissingSnapshotNeverOffersOwnerOrUneditableAdminActions() {
        let denied: [ChannelParticipant] = [.creator(id: peer().id, adminInfo: nil, rank: nil), participant(admin: true)]
        for target in denied {
            let pipe = ValuePipe<(TelegramChannel?, ChannelParticipant?)>()
            let authorization = ChannelParticipantModerationMenu(accountPeerId: accountPeerId, member: peer(), participant: pipe.signal())
            var calls: [String] = []
            let actions = authorization.items(channel: channel(), participant: nil, restrict: { calls.append("restrict") }, ban: { calls.append("ban") })
            let copy = ContextMenuItem("Copy", handler: { calls.append("copy") })
            let menu = ContextMenu()
            menu.items = [copy, ContextSeparatorItem()] + actions
            menu.update()
            for item in actions {
                XCTAssertFalse(item.isEnabled)
                XCTAssertFalse((item as? NSMenuItemValidation)?.validateMenuItem(item) ?? true)
                item.handler?()
            }
            copy.handler?()
            XCTAssertEqual(calls, ["copy"])
            pipe.putNext((channel(), target))
            XCTAssertEqual(menu.items.count, 1)
            XCTAssertTrue(menu.items.first === copy)
            for item in actions {
                XCTAssertFalse(item.isEnabled)
                item.handler?()
            }
            XCTAssertEqual(calls, ["copy"])
        }
    }

    func testOrdinaryAndEditableMembersEnableSameGuardedItemsOnlyAfterLookup() {
        let targets = [(channel(), participant()), (channel(), participant(admin: true, editable: true)), (channel(), participant(admin: true, promotedByAccount: true)), (channel(flags: [.isCreator]), participant(admin: true))]
        for (channel, target) in targets {
            let pipe = ValuePipe<(TelegramChannel?, ChannelParticipant?)>()
            let authorization = ChannelParticipantModerationMenu(accountPeerId: accountPeerId, member: peer(), participant: pipe.signal())
            var calls = 0
            let actions = authorization.items(channel: channel, participant: nil, restrict: { calls += 1 }, ban: { calls += 1 })
            let menu = ContextMenu()
            menu.items = actions
            for item in actions {
                XCTAssertFalse(item.isEnabled)
                item.handler?()
            }
            XCTAssertEqual(calls, 0)
            pipe.putNext((channel, target))
            for (index, item) in actions.enumerated() {
                XCTAssertTrue(item.isEnabled)
                XCTAssertTrue(menu.items[index] === item)
                XCTAssertTrue((item as? NSMenuItemValidation)?.validateMenuItem(item) ?? false)
                item.handler?()
            }
            XCTAssertEqual(calls, 2)
        }
    }

    func testAllowedHistoricalSnapshotStillRequiresFreshAuthorization() {
        for current in [participant(admin: true), .creator(id: peer().id, adminInfo: nil, rank: nil)] {
            let pipe = ValuePipe<(TelegramChannel?, ChannelParticipant?)>()
            let authorization = ChannelParticipantModerationMenu(accountPeerId: accountPeerId, member: peer(), participant: pipe.signal())
            var calls = 0
            let actions = authorization.items(channel: channel(), participant: participant(), restrict: { calls += 1 }, ban: { calls += 1 })
            let menu = ContextMenu()
            menu.items = actions
            actions.forEach { $0.handler?() }
            XCTAssertEqual(calls, 0)
            pipe.putNext((channel(), current))
            XCTAssertTrue(menu.items.isEmpty)
            actions.forEach { $0.handler?() }
            XCTAssertEqual(calls, 0)
        }
    }

    func testFailedMissingMismatchedAndRevokedLookupsRemoveOnlyModeration() {
        let results: [(TelegramChannel?, ChannelParticipant?)] = [(channel(), nil), (nil, participant()), (channel(), participant(7)), (channel(rights: []), participant()), (channel(broadcast: true), participant())]
        for result in results {
            let pipe = ValuePipe<(TelegramChannel?, ChannelParticipant?)>()
            let authorization = ChannelParticipantModerationMenu(accountPeerId: accountPeerId, member: peer(), participant: pipe.signal())
            let actions = authorization.items(channel: channel(), participant: nil, restrict: { XCTFail("restrict") }, ban: { XCTFail("ban") })
            let menu = ContextMenu()
            let copy = ContextMenuItem("Copy")
            let translate = ContextMenuItem("Translate")
            menu.items = [copy, ContextSeparatorItem()] + actions + [ContextSeparatorItem(), translate]
            pipe.putNext(result)
            XCTAssertEqual(menu.items.count, 3)
            XCTAssertTrue(menu.items.first === copy)
            XCTAssertTrue(menu.items[1].isSeparatorItem)
            XCTAssertTrue(menu.items.last === translate)
            actions.forEach { $0.handler?() }
        }
    }

    func testDeniedDeletedAuthorSubmenuIsPrunedWithoutRemovingOtherTargets() {
        let pipe = ValuePipe<(TelegramChannel?, ChannelParticipant?)>()
        let authorization = ChannelParticipantModerationMenu(accountPeerId: accountPeerId, member: peer(), participant: pipe.signal())
        let actions = authorization.items(channel: channel(), participant: nil, restrict: { XCTFail("restrict") }, ban: { XCTFail("ban") })
        let submenu = ContextMenu()
        submenu.items = actions
        let denied = ContextMenuItem("Owner")
        denied.submenu = submenu
        let other = ContextMenuItem("Other author")
        let showMore = ContextMenuItem("Show more")
        let menu = ContextMenu()
        menu.items = [denied, ContextSeparatorItem(), other, showMore]
        pipe.putNext((channel(), .creator(id: peer().id, adminInfo: nil, rank: nil)))
        XCTAssertTrue(submenu.items.isEmpty)
        XCTAssertEqual(menu.items.count, 2)
        XCTAssertTrue(menu.items[0] === other)
        XCTAssertTrue(menu.items[1] === showMore)
    }

    func testSynchronousDenialBeforeAttachmentAndEmptyCompletionArePruned() {
        for signal: Signal<(TelegramChannel?, ChannelParticipant?), NoError> in [.single((channel(), nil)), .complete()] {
            let authorization = ChannelParticipantModerationMenu(accountPeerId: accountPeerId, member: peer(), participant: signal)
            let actions = authorization.items(channel: channel(), participant: nil, restrict: { XCTFail("restrict") }, ban: { XCTFail("ban") })
            let submenu = ContextMenu()
            submenu.items = actions
            let parent = ContextMenuItem("Author")
            parent.submenu = submenu
            let menu = ContextMenu()
            let copy = ContextMenuItem("Copy")
            menu.items = [copy, ContextSeparatorItem(), parent]
            flushMainQueue()
            XCTAssertTrue(submenu.items.isEmpty)
            XCTAssertEqual(menu.items.count, 1)
            XCTAssertTrue(menu.items.first === copy)
        }
    }

    func testKnownForbiddenTargetsDoNotStartLookup() {
        var subscriptions = 0
        let signal = Signal<(TelegramChannel?, ChannelParticipant?), NoError> { _ in
            subscriptions += 1
            return EmptyDisposable
        }
        let cases: [(TelegramChannel, Peer, ChannelParticipant?)] = [(channel(), peer(), .creator(id: peer().id, adminInfo: nil, rank: nil)), (channel(), peer(), participant(admin: true)), (channel(), peer(), participant(7)), (channel(), peer(1), nil), (channel(rights: []), peer(), nil), (channel(broadcast: true), peer(), nil)]
        for (channel, member, participant) in cases {
            let authorization = ChannelParticipantModerationMenu(accountPeerId: accountPeerId, member: member, participant: signal)
            XCTAssertTrue(authorization.items(channel: channel, participant: participant, restrict: {}, ban: {}).isEmpty)
        }
        XCTAssertEqual(subscriptions, 0)
    }

    func testMenuReleaseDisposesLookupAndIgnoresLateResult() {
        var disposed = false
        var subscriber: Subscriber<(TelegramChannel?, ChannelParticipant?), NoError>?
        weak var released: ChannelParticipantModerationMenu?
        autoreleasepool {
            let signal = Signal<(TelegramChannel?, ChannelParticipant?), NoError> { value in
                subscriber = value
                return ActionDisposable { disposed = true }
            }
            let authorization = ChannelParticipantModerationMenu(accountPeerId: accountPeerId, member: peer(), participant: signal)
            released = authorization
            let menu = ContextMenu()
            menu.items = authorization.items(channel: channel(), participant: nil, restrict: { XCTFail("restrict") }, ban: { XCTFail("ban") })
        }
        XCTAssertNil(released)
        XCTAssertTrue(disposed)
        subscriber?.putNext((channel(), participant()))
        XCTAssertNil(released)
    }

    func testFreshInvocationCheckDoesNotReuseMenuAuthorization() {
        let pipe = ValuePipe<(TelegramChannel?, ChannelParticipant?)>()
        let authorization = ChannelParticipantModerationMenu(accountPeerId: accountPeerId, member: peer(), participant: pipe.signal())
        let actions = authorization.items(channel: channel(), participant: nil, restrict: {}, ban: {})
        pipe.putNext((channel(), participant()))
        XCTAssertTrue(actions.allSatisfy { $0.isEnabled })
        var results: [ChannelParticipant?] = []
        let disposable = authorization.authorizedParticipant.start(next: { results.append($0) })
        XCTAssertTrue(results.isEmpty)
        pipe.putNext((channel(), participant(admin: true)))
        XCTAssertEqual(results.count, 1)
        XCTAssertNil(results.first!)
        disposable.dispose()
    }

    func testTimeoutRemovesPendingActionsWithoutBlockingCopy() {
        let authorization = ChannelParticipantModerationMenu(accountPeerId: accountPeerId, member: peer(), participant: .never())
        let menu = ContextMenu()
        var copied = false
        let copy = ContextMenuItem("Copy", handler: { copied = true })
        let actions = authorization.items(channel: channel(), participant: nil, restrict: { XCTFail("restrict") }, ban: { XCTFail("ban") })
        menu.items = [copy, ContextSeparatorItem()] + actions
        copy.handler?()
        XCTAssertTrue(copied)
        XCTAssertTrue(actions.allSatisfy { !$0.isEnabled })
        let timedOut = expectation(description: "Authorization timeout")
        DispatchQueue.main.asyncAfter(deadline: .now() + 10.2) {
            XCTAssertEqual(menu.items.count, 1)
            XCTAssertTrue(menu.items.first === copy)
            timedOut.fulfill()
        }
        wait(for: [timedOut], timeout: 12)
    }

    func testLateAuthorizationPreservesAvatarSemanticBindingGuards() throws {
        for sameContext in [true, false] {
            let avatar = ChatAvatarView(frame: .zero)
            let account = NSObject()
            let interaction = NSObject()
            func context(_ row: Int) -> ChatAvatarView.MenuContext {
                return .init(account: ObjectIdentifier(account), interaction: ObjectIdentifier(interaction), chatPeerId: channel().id, threadId: nil, mode: .history, rowId: AnyHashable(row), messageId: nil, peer: peer(), chatPeer: .init(channel()), hasStories: false)
            }
            let pipe = ValuePipe<(TelegramChannel?, ChannelParticipant?)>()
            let authorization = ChannelParticipantModerationMenu(accountPeerId: accountPeerId, member: peer(), participant: pipe.signal())
            var calls = 0
            let actions = authorization.items(channel: channel(), participant: nil, restrict: { calls += 1 }, ban: { calls += 1 })
            let menu = ContextMenu()
            menu.items = actions
            avatar.updateContextMenu({ menu }, context: context(1))
            let open = try XCTUnwrap(avatar.contextMenu?())
            avatar.updateContextMenu({ ContextMenu() }, context: context(sameContext ? 1 : 2))
            pipe.putNext((channel(), participant()))
            for case let item as ContextMenuItem in open.items {
                item.handler?()
            }
            XCTAssertEqual(calls, sameContext ? 2 : 0)
            avatar.updateContextMenu(nil)
            actions.forEach { $0.handler?() }
            XCTAssertEqual(calls, sameContext ? 2 : 0)
        }
    }
}
