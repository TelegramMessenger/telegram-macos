import XCTest
import Postbox
@testable import ChatUI

final class ChatInputAccessoryPanelStackTests: XCTestCase {
    private let linkPreview: AnyHashable = "linkPreview"
    private let forward: AnyHashable = "forward"
    private let reply: AnyHashable = "reply"

    func testReplySetAfterLinkPreviewIsShown() {
        var stack = ChatInputAccessoryPanelStack<AnyHashable>()
        XCTAssertEqual(stack.update(availableKeys: [self.linkPreview]), self.linkPreview)
        XCTAssertEqual(stack.update(availableKeys: [self.linkPreview, self.reply]), self.reply)
        XCTAssertEqual(stack.update(availableKeys: [self.linkPreview, self.reply]), self.reply)
    }

    func testCancellingTheReplyBringsBackTheLinkPreview() {
        var stack = ChatInputAccessoryPanelStack<AnyHashable>()
        _ = stack.update(availableKeys: [self.linkPreview])
        _ = stack.update(availableKeys: [self.linkPreview, self.reply])
        XCTAssertEqual(stack.update(availableKeys: [self.linkPreview]), self.linkPreview)
    }

    func testLinkPreviewAppearingAfterReplyIsShown() {
        var stack = ChatInputAccessoryPanelStack<AnyHashable>()
        XCTAssertEqual(stack.update(availableKeys: [self.reply]), self.reply)
        XCTAssertEqual(stack.update(availableKeys: [self.linkPreview, self.reply]), self.linkPreview)
        XCTAssertEqual(stack.update(availableKeys: [self.reply]), self.reply)
    }

    func testPanelsAppearingTogetherKeepThePriority() {
        var stack = ChatInputAccessoryPanelStack<AnyHashable>()
        XCTAssertEqual(stack.update(availableKeys: [self.linkPreview, self.forward, self.reply]), self.linkPreview)
        XCTAssertEqual(stack.update(availableKeys: [self.forward, self.reply]), self.forward)
        XCTAssertEqual(stack.update(availableKeys: [self.reply]), self.reply)
    }

    func testReplyingToAnotherMessageComesBackOnTop() {
        let replyToA: AnyHashable = "reply-a"
        let replyToB: AnyHashable = "reply-b"
        var stack = ChatInputAccessoryPanelStack<AnyHashable>()
        _ = stack.update(availableKeys: [replyToA])
        XCTAssertEqual(stack.update(availableKeys: [self.linkPreview, replyToA]), self.linkPreview)
        XCTAssertEqual(stack.update(availableKeys: [self.linkPreview, replyToB]), replyToB)
    }

    func testANewPanelGoesOverTheWholeStack() {
        var stack = ChatInputAccessoryPanelStack<AnyHashable>()
        _ = stack.update(availableKeys: [self.reply])
        _ = stack.update(availableKeys: [self.linkPreview, self.reply])
        XCTAssertEqual(stack.update(availableKeys: [self.linkPreview, self.forward, self.reply]), self.forward)
        XCTAssertEqual(stack.update(availableKeys: [self.linkPreview, self.reply]), self.linkPreview)
    }

    func testHidingTheSlotKeepsTheOrder() {
        var stack = ChatInputAccessoryPanelStack<AnyHashable>()
        _ = stack.update(availableKeys: [self.linkPreview])
        _ = stack.update(availableKeys: [self.linkPreview, self.reply])
        XCTAssertNil(stack.update(availableKeys: nil))
        XCTAssertEqual(stack.update(availableKeys: [self.linkPreview, self.reply]), self.reply)
    }

    func testNothingAvailableShowsNothing() {
        var stack = ChatInputAccessoryPanelStack<AnyHashable>()
        _ = stack.update(availableKeys: [self.reply])
        XCTAssertNil(stack.update(availableKeys: []))
        _ = stack.update(availableKeys: [self.linkPreview])
        XCTAssertEqual(stack.update(availableKeys: [self.linkPreview, self.reply]), self.reply)
    }
    func testEditingURLHasADifferentIdentityFromComposeURL() {
        let id = MessageId(peerId: PeerId(1), namespace: 0, id: 7)
        let compose = ChatInputAccessoryPanelKey.urlPreview("https://example.com", nil)
        let edit = ChatInputAccessoryPanelKey.urlPreview("https://example.com", id)
        let reply = ChatInputAccessoryPanelKey.reply(id)
        var stack = ChatInputAccessoryPanelStack<ChatInputAccessoryPanelKey>()
        XCTAssertEqual(stack.update(availableKeys: [compose]), compose)
        XCTAssertEqual(stack.update(availableKeys: [compose, reply]), reply)
        XCTAssertEqual(stack.update(availableKeys: [edit, reply]), edit)
        XCTAssertEqual(stack.update(availableKeys: [reply]), reply)
    }

    func testForwardSubjectsKeepTheirSelectionOrder() {
        let first = MessageId(peerId: PeerId(1), namespace: 0, id: 7)
        let second = MessageId(peerId: PeerId(1), namespace: 0, id: 8)
        let forward = ChatInputAccessoryPanelKey.forward([first, second])
        let reordered = ChatInputAccessoryPanelKey.forward([second, first])
        let url = ChatInputAccessoryPanelKey.urlPreview("https://example.com", nil)
        var stack = ChatInputAccessoryPanelStack<ChatInputAccessoryPanelKey>()
        _ = stack.update(availableKeys: [forward])
        XCTAssertEqual(stack.update(availableKeys: [url, forward]), url)
        XCTAssertEqual(stack.update(availableKeys: [url, reordered]), reordered)
    }
}
