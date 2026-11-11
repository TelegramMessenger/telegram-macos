import XCTest
import InAppSettings
@testable import ChatUI

final class ChatSidebarKindTests: XCTestCase {
    private func resolve(standard: Bool = true, saved: Bool = false, mono: Bool = false, admin: Bool = false, forum: Bool = false, chats: Bool = false, thread: Bool = false) -> ChatSidebarKind? {
        ChatSidebarKind.resolve(isStandardMode: standard, isSavedMessages: saved, isMonoforum: mono, canManageDirect: admin, isGroupSidebar: forum, hasChats: chats, isThread: thread)
    }

    func testSavedMessagesRequiresSourceChatsInRoot() {
        XCTAssertNil(resolve(saved: true))
        XCTAssertEqual(resolve(saved: true, chats: true), .savedMessages)
    }

    func testSavedSubchatKeepsSidebarWhileIndexLoads() {
        XCTAssertEqual(resolve(saved: true, thread: true), .savedMessages)
    }

    func testChannelMessagesRequiresManageDirectPermission() {
        XCTAssertNil(resolve(mono: true))
        XCTAssertNil(resolve(mono: true, forum: true))
        XCTAssertEqual(resolve(mono: true, admin: true), .channelMessages)
        XCTAssertEqual(resolve(mono: true, admin: true, thread: true), .channelMessages)
    }

    func testSpecialChatModesHaveNoSidebar() {
        XCTAssertNil(resolve(standard: false, saved: true, chats: true))
        XCTAssertNil(resolve(standard: false, mono: true, admin: true))
        XCTAssertNil(resolve(standard: false, forum: true))
    }

    func testGroupSidebarStillRequiresServerDisplayFlag() {
        XCTAssertNil(resolve(chats: true, thread: true))
        XCTAssertEqual(resolve(forum: true), .forum)
    }

    func testOnlyForumsOfferTopicCreation() {
        XCTAssertTrue(ChatSidebarKind.forum.showsNewTopic)
        XCTAssertFalse(ChatSidebarKind.forum.usesSourceChats)
        for kind in [ChatSidebarKind.savedMessages, .channelMessages] {
            XCTAssertFalse(kind.showsNewTopic)
            XCTAssertTrue(kind.usesSourceChats)
        }
    }

    func testTrailingSidebarDoesNotReserveLegacyInlineSpace() throws {
        for savedState in [MonoforumUIState.vertical, .horizontal] {
            let state = try XCTUnwrap(ChatSidebarKind.resolvedMonoforumState(topicListAvailable: true, currentState: savedState, savedState: savedState, sidebarMode: true))
            XCTAssertEqual(state, .sidebar)
            XCTAssertNotEqual(state, .vertical)
            XCTAssertNotEqual(state, .horizontal)
        }
    }

    func testSwitchingBackToInlineTopicsRestoresSavedLayout() {
        for savedState in [MonoforumUIState.vertical, .horizontal] {
            XCTAssertEqual(ChatSidebarKind.resolvedMonoforumState(topicListAvailable: true, currentState: .sidebar, savedState: savedState, sidebarMode: false), savedState)
            XCTAssertEqual(ChatSidebarKind.resolvedMonoforumState(topicListAvailable: true, currentState: nil, savedState: savedState, sidebarMode: false), savedState)
        }
    }

    func testInlineTopicSelectionAndUnavailableListsKeepTheirBehavior() {
        XCTAssertEqual(ChatSidebarKind.resolvedMonoforumState(topicListAvailable: true, currentState: .horizontal, savedState: .vertical, sidebarMode: false), .horizontal)
        XCTAssertNil(ChatSidebarKind.resolvedMonoforumState(topicListAvailable: false, currentState: .sidebar, savedState: .vertical, sidebarMode: true))
    }

}
