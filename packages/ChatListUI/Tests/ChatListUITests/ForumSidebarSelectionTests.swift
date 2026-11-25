import XCTest
@testable import ChatListUI

final class ForumSidebarSelectionTests: XCTestCase {
    func testSelectionRequiresExplicitActivationAndTogglesIndependently() {
        var selection = ForumSidebarSelection()
        selection.toggle(10)
        XCTAssertTrue(selection.selectedIds.isEmpty)
        selection.setActive(true)
        selection.toggle(10)
        selection.toggle(20)
        XCTAssertEqual(selection.selectedIds, [10, 20])
        selection.toggle(10)
        XCTAssertEqual(selection.selectedIds, [20])
    }

    func testCancelAndReentryNeverReuseAnOldSelection() {
        var selection = ForumSidebarSelection()
        selection.setActive(true)
        selection.toggle(42)
        selection.setActive(false)
        XCTAssertFalse(selection.isActive)
        XCTAssertTrue(selection.selectedIds.isEmpty)
        selection.setActive(true)
        XCTAssertTrue(selection.selectedIds.isEmpty)
    }

    func testLiveTopicRemovalDropsOnlyStaleSelectionIds() {
        var selection = ForumSidebarSelection()
        selection.setActive(true)
        [10, 20, 30].forEach { selection.toggle($0) }
        selection.retain([20, 30, 40])
        XCTAssertEqual(selection.selectedIds, [20, 30])
        selection.retain([])
        XCTAssertTrue(selection.selectedIds.isEmpty)
    }

    func testGeneralTopicHasNoCloseOrDeleteEvenForAnAdministrator() {
        let permissions = ForumTopicActionPermissions(threadId: 1, ownedByMe: true, managesTopics: true, deletesMessages: true)
        XCTAssertFalse(permissions.canClose)
        XCTAssertFalse(permissions.canDelete)
    }

    func testTopicOwnerCanCloseWithoutDeleteMessagesPermission() {
        let permissions = ForumTopicActionPermissions(threadId: 42, ownedByMe: true, managesTopics: false, deletesMessages: false)
        XCTAssertTrue(permissions.canClose)
        XCTAssertFalse(permissions.canDelete)
    }

    func testManageTopicsAndDeleteMessagesAreSeparatePermissions() {
        let manager = ForumTopicActionPermissions(threadId: 42, ownedByMe: false, managesTopics: true, deletesMessages: false)
        XCTAssertTrue(manager.canClose)
        XCTAssertFalse(manager.canDelete)
        let moderator = ForumTopicActionPermissions(threadId: 42, ownedByMe: false, managesTopics: false, deletesMessages: true)
        XCTAssertFalse(moderator.canClose)
        XCTAssertTrue(moderator.canDelete)
        let member = ForumTopicActionPermissions(threadId: 42, ownedByMe: false, managesTopics: false, deletesMessages: false)
        XCTAssertFalse(member.canClose)
        XCTAssertFalse(member.canDelete)
    }
    func testTopicSwipeOrderAndReverseStates() {
        XCTAssertEqual(ForumTopicSwipePolicy.actions(isMuted: false, isClosed: false, canClose: true, canDelete: true), [.mute, .delete, .close])
        XCTAssertEqual(ForumTopicSwipePolicy.actions(isMuted: true, isClosed: true, canClose: true, canDelete: true), [.unmute, .delete, .reopen])
    }

    func testTopicSwipeHidesUnavailableManagementActions() {
        XCTAssertEqual(ForumTopicSwipePolicy.actions(isMuted: false, isClosed: false, canClose: false, canDelete: false), [.mute])
        XCTAssertEqual(ForumTopicSwipePolicy.actions(isMuted: false, isClosed: false, canClose: true, canDelete: false), [.mute, .close])
        XCTAssertEqual(ForumTopicSwipePolicy.actions(isMuted: true, isClosed: true, canClose: false, canDelete: true), [.unmute, .delete])
    }

}
