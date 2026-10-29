import XCTest
import Cocoa
import LocalAnimations
import TelegramCore
import Postbox
import InAppSettings
import InputDataUI
import InputView
import TGUIKit
@testable import SidebarUI

final class SidebarUITests: XCTestCase {
    private let nameId = InputDataIdentifier("name")
    private let includeId = InputDataIdentifier("include")

    private func peer(_ value: Int64) -> PeerId {
        return PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(value))
    }

    private func filter(_ id: Int32 = 10, categories: ChatListFilterPeerCategories = [], include: [PeerId] = [], exclude: [PeerId] = [], shared: Bool = false, hasLinks: Bool = false, muted: Bool = false, read: Bool = false, archived: Bool = false) -> ChatListFilter {
        return .filter(id: id, title: .init(text: "Folder", entities: [], enableAnimations: true), emoticon: nil, data: ChatListFilterData(isShared: shared, hasSharedLinks: hasLinks, categories: categories, excludeMuted: muted, excludeRead: read, excludeArchived: archived, includePeers: includedPeers(include), excludePeers: exclude, color: nil))
    }

    private func includedPeers(_ ids: [PeerId]) -> ChatListFilterIncludePeers {
        var value = ChatListFilterIncludePeers()
        value.setPeers(ids)
        return value
    }

    private func category(_ value: ChatListFilterPeerCategories) -> PeerId {
        return PeerId(namespace: ._internalFromInt32Value(7), id: ._internalFromInt64Value(Int64(value.rawValue)))
    }

    private func categoryForPeer(_ id: PeerId) -> ChatListFilterPeerCategories? {
        guard id.namespace._internalGetInt32Value() == 7 else { return nil }
        return ChatListFilterPeerCategories(rawValue: Int32(id.id._internalGetInt64Value()))
    }

    func testAllChatsIdentityAndEntryOrderPreserveAppConvention() {
        let state = SidebarState(tabs: [.allChats, filter(20), filter(10)], selectedFilterId: -1)
        let entries = leftSidebarEntries(state, ChatListFilterBadges(total: 0, filters: []))
        XCTAssertEqual(entries.map { $0.stableId }, [-2, -1, 20, 10])
        XCTAssertEqual(entries.map { $0.index }, [-1, 1, 2, 3])
        XCTAssertEqual(entries.sorted(), entries)
        guard case let .folder(_, selected, _, count, _, unmuted) = entries[1] else { return XCTFail() }
        XCTAssertTrue(selected)
        XCTAssertEqual(count, 0)
        XCTAssertFalse(unmuted)
    }

    func testBadgesFollowIdentityAndSelectionWithoutReordering() {
        let entries = leftSidebarEntries(SidebarState(tabs: [filter(20), filter(10)], selectedFilterId: 10), badgeForFilter: { filter in
            return filter.sidebarId == 20 ? (7, 9, true) : nil
        })
        guard case let .folder(_, selected, filter, count, totalCount, unmuted) = entries[1] else { return XCTFail() }
        XCTAssertEqual(filter.sidebarId, 20)
        XCTAssertFalse(selected)
        XCTAssertEqual(count, 7)
        XCTAssertEqual(totalCount, 9)
        XCTAssertTrue(unmuted)
        guard case let .folder(_, secondSelected, _, secondCount, _, _) = entries[2] else { return XCTFail() }
        XCTAssertTrue(secondSelected)
        XCTAssertEqual(secondCount, 0)
    }

    func testResortingPreservesAllChatsRestrictionAndSettingsOffset() {
        XCTAssertEqual(sidebarResortRange(rowCount: 4, isPremium: true), NSRange(location: 1, length: 3))
        XCTAssertEqual(sidebarResortRange(rowCount: 4, isPremium: false), NSRange(location: 2, length: 2))
        let folders: [ChatListFilter] = [.allChats, filter(10), filter(20)]
        XCTAssertEqual(sidebarReorderedFilters(folders, from: 2, to: 3, rangeLocation: 1, offset: 0).map { $0.sidebarId }, [-1, 20, 10])
        XCTAssertEqual(sidebarReorderedFilters(folders, from: 5, to: 6, rangeLocation: 5, offset: 1).map { $0.sidebarId }, [-1, 20, 10])
        XCTAssertEqual(sidebarReorderedFilters(folders, from: 1, to: 3, rangeLocation: 1, offset: 0).map { $0.sidebarId }, [10, 20, -1])
    }

    func testClassificationPrefersUnreadAndExplicitPeersUseGenericIcon() {
        XCTAssertEqual(chatListFilterType(filter(categories: .all, muted: true, read: true)), .unread)
        XCTAssertEqual(chatListFilterType(filter(categories: .all, muted: true)), .unmuted)
        XCTAssertEqual(chatListFilterType(filter(categories: .bots)), .bots)
        XCTAssertEqual(chatListFilterType(filter(categories: .bots, include: [peer(1)])), .generic)
        XCTAssertEqual(FolderIcon(filter(categories: .channels)).emoticon.iconName, "Icon_Sidebar_Channel")
    }

    func testIncludeSelectionReplacesCategoriesDeduplicatesAndRemovesOverlap() {
        let original = filter(categories: .bots, exclude: [peer(1), peer(3)])
        let updated = sidebarFilterIncluding(original, peerIds: [peer(1), peer(1), peer(2), category(.contacts)], maximumPeers: 2, categoryForPeer: categoryForPeer)
        XCTAssertEqual(Set(updated.data!.includePeers.peers), Set([peer(1), peer(2)]))
        XCTAssertEqual(updated.data!.excludePeers, [peer(3)])
        XCTAssertEqual(updated.data!.categories, .contacts)
        XCTAssertEqual(sidebarFilterIncluding(original, peerIds: [peer(1), peer(2), peer(3)], maximumPeers: 1, categoryForPeer: categoryForPeer).data!.includePeers.peers.count, 1)
        XCTAssertEqual(sidebarFilterIncluding(.allChats, peerIds: [peer(1)], maximumPeers: 1, categoryForPeer: categoryForPeer), .allChats)
    }

    func testExcludingPreservesExistingFlagsWhenNotSelected() {
        let original = filter(include: [peer(1), peer(2)], read: true)
        let updated = sidebarFilterExcluding(original, peerIds: [peer(1), peer(1), category(.excludeMuted)], maximumPeers: 2, categoryForPeer: categoryForPeer)
        XCTAssertEqual(updated.data!.excludePeers, [peer(1)])
        XCTAssertEqual(updated.data!.includePeers.peers, [peer(2)])
        XCTAssertTrue(updated.data!.excludeRead)
        XCTAssertTrue(updated.data!.excludeMuted)
        XCTAssertFalse(updated.data!.excludeArchived)
    }

    func testMenuAddChatsRetainsOrderAndFixedHundredPeerLimit() {
        let ids = (1...105).map { peer(Int64($0)) }
        let updated = sidebarMenuAddingPeers(filter(exclude: [peer(1), peer(105)]).data!, peerIds: [ids[0]] + ids)
        XCTAssertEqual(updated.includePeers.peers, Array(ids.prefix(100)))
        XCTAssertEqual(updated.excludePeers, [peer(105)])
    }

    func testMenuCallbacksAreDeferredAndDispatchInDisplayedOrder() {
        var actions: [SidebarMenuAction] = []
        let items = sidebarMenuItems(filter: filter(include: [peer(1)], shared: true), unreadCount: 3, includeAllMuted: false, image: { _ in nil }, perform: { actions.append($0) })
        XCTAssertTrue(actions.isEmpty)
        items.forEach { $0.handler?() }
        XCTAssertEqual(actions, [.edit, .addChats, .markRead, .mute(true), .share, .delete])
        XCTAssertTrue(items[items.count - 2] is ContextSeparatorItem)
    }

    func testMenuHidesReadMuteAndShareForIneligibleFolders() {
        var actions: [SidebarMenuAction] = []
        sidebarMenuItems(filter: filter(categories: .bots, include: [peer(1)]), unreadCount: 0, includeAllMuted: true, image: { _ in nil }, perform: { actions.append($0) }).forEach { $0.handler?() }
        XCTAssertEqual(actions, [.edit, .addChats, .delete])
        actions.removeAll()
        sidebarMenuItems(filter: .allChats, unreadCount: 9, includeAllMuted: true, image: { _ in nil }, perform: { actions.append($0) }).forEach { $0.handler?() }
        XCTAssertEqual(actions, [.editFolders])
        actions.removeAll()
        sidebarMenuItems(filter: filter(include: [peer(1)]), unreadCount: nil, includeAllMuted: true, image: { _ in nil }, perform: { actions.append($0) }).forEach { $0.handler?() }
        XCTAssertTrue(actions.contains(.mute(false)))
    }

    func testSharingLimitBranchingAndExistingSharedLinkException() {
        let limits = SidebarLimits(dialog_filters_limit_default: 10, dialog_filters_limit_premium: 20, dialog_filters_chats_limit_default: 100, dialog_filters_chats_limit_premium: 200, community_invites_limit_default: 0, community_invites_limit_premium: 0, communities_joined_limit_default: 1, communities_joined_limit_premium: 1)
        let folders = [filter(shared: true)]
        let basic = sidebarSharingLimits(filters: folders, current: filter(), links: nil, isPremium: false, limits: limits)
        XCTAssertTrue(basic.limitFilters)
        XCTAssertTrue(basic.limitInvites)
        let premium = sidebarSharingLimits(filters: folders, current: filter(), links: nil, isPremium: true, limits: limits)
        XCTAssertTrue(premium.limitFilters)
        XCTAssertFalse(premium.limitInvites)
        let existing = sidebarSharingLimits(filters: folders, current: filter(shared: true, hasLinks: true), links: nil, isPremium: true, limits: limits)
        XCTAssertFalse(existing.limitFilters)
        XCTAssertTrue(existing.limitInvites)
    }

    func testTitleConversionReceivesAttributedStateAndRetainsAnimationChoice() {
        let attributed = NSAttributedString(string: "Hi", attributes: [NSAttributedString.Key("custom"): "value"])
        let state = Updated_ChatTextInputState(inputText: attributed, selectionRange: 0..<1)
        let entities = [MessageTextEntity(range: 0..<2, type: .Bold)]
        var calls = 0
        let updated = sidebarUpdatingTitle(filter(), state: state, animated: false, entities: { received in
            calls += 1
            XCTAssertEqual(received.inputText, attributed)
            XCTAssertEqual(received.selectionRange, 0..<1)
            return entities
        })
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(updated.title, "Hi")
        XCTAssertEqual(updated.entities, entities)
        XCTAssertFalse(updated.enableAnimations)
    }

    func testValidationWaitsForServerCompletionBeforeSavingAndNavigating() {
        var events: [String] = []
        var serverCompleted: (() -> Void)?
        sidebarValidateFolder(filter: filter(20, include: [peer(1)]), initialFilter: filter(), titleLength: 6, nameId: nameId, includeId: includeId, notify: { _ in XCTFail() }, requestSave: { serverCompleted = $0; events.append("request") }, save: { events.append("save:\($0)") }, completion: { value in
            guard case .success(.navigationBack) = value else { return XCTFail() }
            events.append("back")
        })
        XCTAssertEqual(events, ["request"])
        serverCompleted?()
        XCTAssertEqual(events, ["request", "save:true", "back"])
    }

    func testUnchangedFolderSavesLocallyBeforeNavigation() {
        var events: [String] = []
        let folder = filter(include: [peer(1)])
        sidebarValidateFolder(filter: folder, initialFilter: folder, titleLength: 12, nameId: nameId, includeId: includeId, notify: { _ in XCTFail() }, requestSave: { _ in XCTFail() }, save: { events.append("save:\($0)") }, completion: { value in
            guard case .success(.navigationBack) = value else { return XCTFail() }
            events.append("back")
        })
        XCTAssertEqual(events, ["save:false", "back"])
    }

    func testInvalidNamesShakeBeforeOtherValidation() {
        for length in [0, 13] {
            var called = false
            sidebarValidateFolder(filter: filter(), initialFilter: filter(), titleLength: length, nameId: nameId, includeId: includeId, notify: { _ in XCTFail() }, requestSave: { _ in XCTFail() }, save: { _ in XCTFail() }, completion: { value in
                guard case let .fail(.fields(fields)) = value else { return XCTFail() }
                XCTAssertNotNil(fields[self.nameId])
                called = true
            })
            XCTAssertTrue(called)
        }
    }

    func testEmptyAndFullFoldersKeepDifferentValidationCallbacks() {
        var notifications = 0
        var callbacks = 0
        let empty = filter()
        sidebarValidateFolder(filter: empty, initialFilter: empty, titleLength: 6, nameId: nameId, includeId: includeId, notify: { _ in notifications += 1 }, requestSave: { _ in XCTFail() }, save: { _ in XCTFail() }, completion: { value in
            guard case let .fail(.fields(fields)) = value else { return XCTFail() }
            XCTAssertNotNil(fields[self.includeId])
            callbacks += 1
        })
        XCTAssertEqual(notifications, 1)
        XCTAssertEqual(callbacks, 1)
        sidebarValidateFolder(filter: .allChats, initialFilter: .allChats, titleLength: 1, nameId: nameId, includeId: includeId, notify: { _ in notifications += 1 }, requestSave: { _ in XCTFail() }, save: { _ in XCTFail() }, completion: { _ in XCTFail("Full folders only show the existing notification") })
        XCTAssertEqual(notifications, 2)
    }

    func testDiscardWaitsForAcceptanceAndUnchangedBackIsImmediate() {
        var accepted: (() -> Void)?
        var callbacks: [Bool] = []
        sidebarConfirmDiscard(changed: true, confirm: { accepted = $0 }, continuation: { callbacks.append($0) })
        XCTAssertTrue(callbacks.isEmpty)
        accepted?()
        XCTAssertEqual(callbacks, [true])
        sidebarConfirmDiscard(changed: false, confirm: { _ in XCTFail() }, continuation: { callbacks.append($0) })
        XCTAssertEqual(callbacks, [true, true])
    }
}
