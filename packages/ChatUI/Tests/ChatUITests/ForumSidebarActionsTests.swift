import AppKit
import XCTest
import Postbox
import TelegramCore
import TGUIKit
import ChatHistoryModel
import TelegramTheme
@testable import ChatUI

private final class SidebarActionRows: ForumSidebarRowsContent {
    let view = NSView(frame: .zero)
    var isSelecting = false
    var selectionChanged: ((Bool) -> Void)?
    var updates = 0
    func update(items: [EngineChatList.Item], selectedThreadId: Int64?, kind: ChatSidebarKind, parentPeer: EngineRenderedPeer) { updates += 1 }
    func search(query: String?, peerId: PeerId, loadingUpdated: @escaping (Bool) -> Void) { loadingUpdated(false) }
    func selectSearchResult() { }
    func setSelecting(_ selecting: Bool) { isSelecting = selecting; selectionChanged?(selecting) }
}

final class ForumSidebarActionsTests: XCTestCase {
    override func setUp() { super.setUp(); UITestBootstrap.install(); applyMacEnglishStrings() }

    func testForumOwnerMenuContainsEveryRequestedActionInOrder() {
        XCTAssertEqual(ForumSidebarMenuPolicy.actions(kind: .forum, canCreateTopics: true, canInviteMembers: true), [.mute, .newTopic, .addMembers, .select])
    }

    func testRestrictedForumMenuKeepsMuteAndSelect() {
        XCTAssertEqual(ForumSidebarMenuPolicy.actions(kind: .forum, canCreateTopics: false, canInviteMembers: false), [.mute, .select])
        XCTAssertEqual(ForumSidebarMenuPolicy.actions(kind: .forum, canCreateTopics: true, canInviteMembers: false), [.mute, .newTopic, .select])
        XCTAssertEqual(ForumSidebarMenuPolicy.actions(kind: .forum, canCreateTopics: false, canInviteMembers: true), [.mute, .addMembers, .select])
    }

    func testSavedAndChannelMessagesUseTheirOwnMenus() {
        XCTAssertEqual(ForumSidebarMenuPolicy.actions(kind: .savedMessages, canCreateTopics: true, canInviteMembers: true), [])
        XCTAssertEqual(ForumSidebarMenuPolicy.actions(kind: .channelMessages, canCreateTopics: true, canInviteMembers: true), [.mute, .markAllRead])
    }

    private func parent(creator: Bool) -> EngineRenderedPeer {
        let peer = TelegramChannel(id: PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(100)), accessHash: nil, title: "Group Forum", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: .group(.init(flags: [])), flags: creator ? [.isForum, .isCreator] : [.isForum], restrictionInfo: nil, adminRights: nil, bannedRights: creator ? nil : .init(flags: [.banManageTopics], untilDate: Int32.max), defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
        return EngineRenderedPeer(peerId: peer.id, peers: [peer.id: .channel(peer)], associatedMedia: [:])
    }

    private func sidebar(width: CGFloat = 358, creator: Bool = true, kind: ChatSidebarKind = .forum) -> (ForumSidebarView, SidebarActionRows) {
        let rows = SidebarActionRows()
        let view = ForumSidebarView(frame: NSRect(x: 0, y: 0, width: width, height: 600), rowsContent: rows)
        let peer = parent(creator: creator)
        view.set(items: [], selectedThreadId: 42, title: "Group Forum", peerId: peer.peerId, kind: kind, parentPeer: peer)
        view.layoutSubtreeIfNeeded()
        return (view, rows)
    }

    func testSidebarHasNoMoreButtonAndNewTopicRoutesOneClick() throws {
        let (view, _) = sidebar()
        let content = try XCTUnwrap(view.subviews.first)
        XCTAssertTrue(content.subviews.filter { $0 is ImageButton && !($0 is TextButton) }.isEmpty)
        let create = try XCTUnwrap(content.subviews.compactMap { $0 as? TextButton }.first { $0.frame.height == 44 })
        var createClicks = 0
        view.onNewTopic = { createClicks += 1 }
        XCTAssertFalse(create.isHidden)
        create.send(event: .Click)
        XCTAssertEqual(createClicks, 1)
    }

    func testSelectionReplacesCreateWithDoneAndEscapeCancels() throws {
        let (view, rows) = sidebar()
        let content = try XCTUnwrap(view.subviews.first)
        let done = try XCTUnwrap(content.subviews.compactMap { $0 as? TextButton }.first { $0.frame.minY == 9 })
        let create = try XCTUnwrap(content.subviews.compactMap { $0 as? TextButton }.first { $0.frame.height == 44 })
        view.beginSelection()
        view.layoutSubtreeIfNeeded()
        XCTAssertTrue(rows.isSelecting)
        XCTAssertTrue(create.isHidden)
        XCTAssertFalse(done.isHidden)
        done.send(event: .Click)
        XCTAssertFalse(rows.isSelecting)
        view.beginSelection()
        XCTAssertTrue(view.cancelSelection())
        XCTAssertFalse(rows.isSelecting)
        XCTAssertFalse(view.cancelSelection())
    }

    func testRestrictedAndSavedSidebarsHideUnavailableControls() throws {
        let (restricted, _) = sidebar(creator: false)
        let create = try XCTUnwrap(restricted.subviews.first?.subviews.compactMap { $0 as? TextButton }.first { $0.frame.height == 44 })
        XCTAssertTrue(create.isHidden)
        let (saved, _) = sidebar(kind: .savedMessages)
        XCTAssertTrue(saved.subviews.first!.subviews.filter { $0 is ImageButton && !($0 is TextButton) }.isEmpty)
    }

    func testNativeHeaderControlsFitNarrowAndDockedWidths() throws {
        for width: CGFloat in [300, 358, 480] {
            let (view, _) = sidebar(width: width)
            let content = try XCTUnwrap(view.subviews.first)
            let title = try XCTUnwrap(content.subviews.compactMap { $0 as? NSTextField }.first)
            XCTAssertEqual(title.frame.minX, 10)
            XCTAssertEqual(title.frame.maxX, width - 10)
            view.beginSelection()
            view.layoutSubtreeIfNeeded()
            XCTAssertLessThanOrEqual(title.frame.maxX, width - 50)
            for child in content.subviews { XCTAssertGreaterThanOrEqual(child.frame.width, 0) }
        }
    }
    func testNativeHeaderRendersBrowsingAndSelectionStates() throws {
        let (view, _) = sidebar()
        var previous: PixelBuffer?
        for selecting in [false, true] {
            if selecting { view.beginSelection() }
            let pixels = ViewSnapshot.render(view)
            XCTAssertGreaterThan(pixels.pixels(darkerThan: 180), 100)
            if let previous { XCTAssertGreaterThan(pixels.differingPixels(from: previous), 100) }
            previous = pixels
            var bytes = pixels.bytes
            let context = try XCTUnwrap(CGContext(data: &bytes, width: pixels.width, height: pixels.height, bitsPerComponent: 8, bytesPerRow: pixels.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: try XCTUnwrap(context.makeImage())).representation(using: .png, properties: [:]))
            let name = selecting ? "forum-sidebar-selection-header" : "forum-sidebar-browsing-header"
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = name
            attachment.lifetime = .keepAlways
            add(attachment)
            if let output = ProcessInfo.processInfo.environment["FORUM_ACTIONS_HARNESS_OUTPUT"] {
                try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
                try png.write(to: URL(fileURLWithPath: output).appendingPathComponent(name + ".png"))
            }
        }
    }

}
