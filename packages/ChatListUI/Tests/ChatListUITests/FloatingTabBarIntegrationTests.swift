import AppKit
import XCTest
import TGUIKit
import TelegramMedia
import TLottie
@testable import ChatListUI

private final class FloatingTabBarTestRow: TableRowItem {
    override var height: CGFloat {
        return 60
    }
}

private final class TabAnimationTestRenderer: TLottieBridge, R_LottieBridge {
}

final class FloatingTabBarIntegrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    func testPeerListsComposeBottomPaddingWithTheirHeaderInsets() {
        let view = PeerListContainerView(frame: NSMakeRect(0, 0, 380, 700))
        view.tableView.contentInsets.top = 30
        view.contentBottomInset = 64
        XCTAssertEqual(view.tableView.contentInsets.top, 30)
        XCTAssertEqual(view.tableView.contentInsets.bottom, 64)
        XCTAssertEqual(view.tableView.scrollerInsets.bottom, 64)
        view.contentBottomInset = 64
        XCTAssertEqual(view.tableView.contentInsets.bottom, 64)
        view.contentBottomInset = 0
        XCTAssertEqual(view.tableView.contentInsets.top, 30)
        XCTAssertEqual(view.tableView.contentInsets.bottom, 0)
        XCTAssertEqual(view.tableView.scrollerInsets.bottom, 0)
    }

    func testBottomControlsUseTheAreaAboveTheFloatingBar() {
        let view = PeerListContainerView(frame: NSMakeRect(0, 0, 380, 700))
        var bottomY: CGFloat?
        view.layoutBottomOverlay = { y, _ in
            bottomY = y
            return nil
        }
        view.contentBottomInset = 64
        XCTAssertEqual(bottomY, 636)
        view.contentBottomInset = 0
        XCTAssertEqual(bottomY, 700)
    }

    func testAnimatedTabReplacementKeepsItsBadgeControllerAndTitle() throws {
        let controller = ViewController()
        let badge = Node(View(frame: NSMakeRect(0, 0, 18, 18)))
        let first = TestImages.named("Icon_SearchField").precomposed()
        let second = TestImages.named("Icon_SearchClear").precomposed()
        let item = TabAnimatedItem(.tab_chats, image: first, selectedImage: first, controller: controller, subNode: badge)
        item.accessibilityTitle = "Chats"
        let replacement = try XCTUnwrap(item.withUpdatedImages(second, second) as? TabAnimatedItem)
        XCTAssertEqual(replacement.sticker, .tab_chats)
        XCTAssertTrue(replacement.controller === controller)
        XCTAssertTrue(replacement.subNode === badge)
        XCTAssertEqual(replacement.accessibilityTitle, "Chats")
    }

    private func waitUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.004))
        }
        return condition()
    }

    func testSelectedTabPreviewStartsPlayingWithoutChangingColors() throws {
        let resource = TestImages.catalog.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/tgs/tab_chats.tgs")
        let data = try Data(contentsOf: resource)
        let previousRenderer = makeRLottie
        makeRLottie = { json, _ in TabAnimationTestRenderer(json: json) }
        let icon = TabAnimatedIconView(sticker: .tab_chats, animationData: data)
        let player: LottiePlayerView = icon
        defer {
            player.set(nil)
            makeRLottie = previousRenderer
        }
        icon.setSelected(true, animated: false)
        XCTAssertTrue(waitUntil { player.currentState == .finished })
        let finalFrame = try XCTUnwrap(player.currentFrame)
        XCTAssertGreaterThan(finalFrame, 0)
        let colors = try XCTUnwrap(player.animation).colors
        icon.setSelected(true, animated: true)
        XCTAssertEqual(player.animation?.colors, colors)
        guard waitUntil({ player.currentFrame.map { $0 < finalFrame } ?? false }) else {
            XCTFail("The selected icon must restart playback after its static preview")
            return
        }
        let firstFrame = try XCTUnwrap(player.currentFrame)
        XCTAssertTrue(waitUntil { player.currentFrame.map { $0 > firstFrame } ?? false })
    }

    func testLastRowCanScrollAboveTheFloatingBar() {
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 380, 700), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = PeerListContainerView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(view)
        view.tableView.frame = view.bounds
        view.contentBottomInset = 64
        for index in 0 ..< 20 {
            _ = view.tableView.addItem(item: FloatingTabBarTestRow(view.bounds.size, stableId: index))
        }
        view.layoutSubtreeIfNeeded()
        view.tableView.scroll(to: .bottom(id: 19, innerId: nil, animated: false, focus: .init(focus: false), inset: 0))
        view.layoutSubtreeIfNeeded()
        let row = view.tableView.rectOf(item: view.tableView.item(at: 19))
        let visibleRow = view.convert(row, from: view.tableView.view)
        XCTAssertLessThanOrEqual(visibleRow.maxY, view.bounds.height - 64)
    }
}
