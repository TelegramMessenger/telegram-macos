import AppKit
import XCTest
@testable import TGUIKit

private final class HeaderSidebarChat: ViewController {
    override func viewDidLoad() { super.viewDidLoad(); readyOnce() }
}

final class SidebarPlayerHeaderTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    private func fixture(width: CGFloat) -> (Window, SplitView, NavigationViewController, HeaderSidebarChat, HeaderSidebarChat, NavigationHeader) {
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: width, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let split = SplitView(frame: window.contentView!.bounds)
        split.canChangeState = false
        window.contentView = split
        let chat = HeaderSidebarChat()
        chat.bar = .init(height: 0)
        let navigation = NavigationViewController(chat, window)
        split.addController(controller: navigation, proportion: SplitProportion(min: width, max: .greatestFiniteMagnitude))
        let sidebar = HeaderSidebarChat()
        sidebar.insets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 8)
        split.setTrailing(controller: sidebar, width: 358, minimumLeadingWidth: 380, overlayWhenNarrow: true, navigationOwner: chat)
        split.layoutSubtreeIfNeeded()
        let header = NavigationHeader(52) { header, _, _ in
            let view = NavigationHeaderView(header)
            view.ready.set(.single(true))
            return (view, 52)
        }
        navigation.set(header: header)
        window.orderBack(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        return (window, split, navigation, chat, sidebar, header)
    }

    func testPlayerShowHideKeepsSidebarFrameAndTopHitTarget() throws {
        for width: CGFloat in [1100, 500] {
            let (window, split, navigation, chat, sidebar, header) = fixture(width: width)
            let original = sidebar.view.convert(sidebar.view.bounds, to: split)
            XCTAssertEqual(original.minY, 8, accuracy: 0.01)
            for visible in [true, false, true, false] {
                if visible { header.show(false, contextObject: ()) } else { header.hide(false) }
                split.layoutSubtreeIfNeeded()
                let rect = sidebar.view.convert(sidebar.view.bounds, to: split)
                XCTAssertEqual(rect.minY, original.minY, accuracy: 0.01)
                XCTAssertEqual(rect.height, original.height, accuracy: 0.01)
                XCTAssertEqual(chat.view.frame.width, width == 1100 ? 742 : 500, accuracy: 0.01)
                let hit = try XCTUnwrap(split.hitTest(NSPoint(x: rect.midX, y: rect.minY + 12)))
                XCTAssertTrue(hit === sidebar.view || hit.isDescendant(of: sidebar.view), "Sidebar's top must remain clickable above the player inset")
            }
            split.setTrailing(controller: nil, width: 0, minimumLeadingWidth: 0)
            split.layoutSubtreeIfNeeded()
            XCTAssertNil(sidebar.view.superview)
            window.close()
            withExtendedLifetime(navigation) {}
        }
    }

    func testAnimatedPlayerShowHideDoesNotMoveSidebarAtIntermediateFrames() throws {
        let (window, split, navigation, _, sidebar, header) = fixture(width: 1100)
        defer { window.close() }
        func presentedRect() throws -> CGRect {
            let layer = try XCTUnwrap(sidebar.view.layer?.presentation())
            let root = try XCTUnwrap(split.layer?.presentation())
            return layer.convert(layer.bounds, to: root)
        }
        let original = try presentedRect()
        for visible in [true, false, true, false] {
            if visible { header.show(true, contextObject: ()) } else { header.hide(true) }
            for _ in 0..<12 {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                let rect = try presentedRect()
                XCTAssertEqual(rect.minY, original.minY, accuracy: 0.75)
                XCTAssertEqual(rect.height, original.height, accuracy: 0.75)
            }
        }
        withExtendedLifetime(navigation) {}
    }

    func testHeaderAlreadyPlayingWhenSidebarOpens() {
        let (window, split, navigation, chat, sidebar, header) = fixture(width: 1100)
        defer { window.close() }
        split.setTrailing(controller: nil, width: 0, minimumLeadingWidth: 0)
        split.layoutSubtreeIfNeeded()
        header.show(false, contextObject: ())
        split.setTrailing(controller: sidebar, width: 358, minimumLeadingWidth: 380, overlayWhenNarrow: true, navigationOwner: chat)
        split.layoutSubtreeIfNeeded()
        let rect = sidebar.view.convert(sidebar.view.bounds, to: split)
        XCTAssertEqual(rect.minY, 8, accuracy: 0.01)
        XCTAssertEqual(rect.maxY, 692, accuracy: 0.01)
        withExtendedLifetime(navigation) {}
    }
}
