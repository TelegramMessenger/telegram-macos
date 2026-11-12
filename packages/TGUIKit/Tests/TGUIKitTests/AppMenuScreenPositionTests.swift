import AppKit
import XCTest
@testable import TGUIKit

final class AppMenuScreenPositionTests: XCTestCase {
    private var previousLegacyMenu = true

    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
        previousLegacyMenu = System.legacyMenu
        System.legacyMenu = false
    }

    override func tearDown() {
        System.legacyMenu = previousLegacyMenu
        super.tearDown()
    }

    private func checkMenu(screen: NSScreen, ownerFrame: NSRect? = nil, point: NSPoint, betterInside: Bool = false, bottomAnchor: Bool = false, mode: AppMenu.AppearMode = .click, rows: Int = 1, verify: (NSRect, NSRect, NSPoint) throws -> Void) throws {
        let owner = Window(contentRect: .zero, styleMask: [.titled, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        owner.isReleasedWhenClosed = false
        owner.setFrame(ownerFrame ?? screen.visibleFrame, display: false)
        defer { owner.close() }
        XCTAssertFalse(owner.isFullScreen)
        let actualScreen = try XCTUnwrap(owner.screen)
        XCTAssertEqual(actualScreen.frame, screen.frame)
        let content = try XCTUnwrap(owner.contentView)
        let anchor = NSView(frame: NSMakeRect(12, max(0, content.bounds.height - 36), 36, 36))
        content.addSubview(anchor)
        let menu = ContextMenu(betterInside: betterInside, bottomAnchor: bottomAnchor)
        for index in 0..<rows {
            menu.addItem(ContextMenuItem("Item \(index)", handler: { XCTFail("Geometry tests must not invoke menu actions") }))
        }
        let holder = AppMenu(menu: menu, appearMode: mode)
        let controller = AppMenuController(menu, presentation: menu.presentation, holder: holder, betterInside: betterInside, appearMode: mode, parentView: anchor)
        defer {
            let panels = NSApp.windows.filter { window in
                (window.contentView?.subviews.first as? MenuView)?.controller === controller
            }
            controller.close()
            panels.forEach { $0.orderOut(nil) }
        }
        let local = owner.convertFromScreen(NSRect(origin: point, size: .zero)).origin
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: local, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: owner.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
        controller.present(event: event, view: anchor)
        let panel = try XCTUnwrap(NSApp.windows.first { window in
            (window.contentView?.subviews.first as? MenuView)?.controller === controller
        })
        let menuView = try XCTUnwrap(panel.contentView?.subviews.first as? MenuView)
        XCTAssertTrue(menu.isShown)
        XCTAssertTrue(panel.isVisible)
        XCTAssertGreaterThan(panel.frame.height, 40)
        XCTAssertEqual(menuView.tableView.count, rows + 2)
        let reference = betterInside ? owner.frame : actualScreen.visibleFrame
        try verify(panel.frame, reference, owner.convertToScreen(NSRect(origin: local, size: .zero)).origin)
    }

    func testDesktopSizedWindowTopClickKeepsMenuBelowVisibleTop() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let visible = screen.visibleFrame
        for inset: CGFloat in [0, 1, 6, 19] {
            try checkMenu(screen: screen, point: NSMakePoint(visible.midX, visible.maxY - inset)) { frame, bounds, point in
                XCTAssertEqual(frame.maxY, bounds.maxY, accuracy: 0.01)
                XCTAssertGreaterThanOrEqual(frame.minY, bounds.minY)
                XCTAssertEqual(frame.minX, point.x - 18, accuracy: 0.01)
                XCTAssertLessThan(frame.minY, point.y)
            }
        }
    }

    func testTopClampingUsesTheActualMenuHeight() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let visible = screen.visibleFrame
        for rows in [1, 3, 12] {
            try checkMenu(screen: screen, point: NSMakePoint(visible.midX, visible.maxY - 5), rows: rows) { frame, bounds, _ in
                XCTAssertEqual(frame.minY, bounds.maxY - frame.height, accuracy: 0.01)
                XCTAssertEqual(frame.maxY, bounds.maxY, accuracy: 0.01)
                XCTAssertGreaterThanOrEqual(frame.minY, bounds.minY)
            }
        }
    }

    func testInteriorClickRetainsCursorRelativePlacement() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let visible = screen.visibleFrame
        for inset: CGFloat in [20, 40, 120] {
            try checkMenu(screen: screen, point: NSMakePoint(visible.midX, visible.maxY - inset)) { frame, _, point in
                XCTAssertEqual(frame.maxY, point.y + 20, accuracy: 0.01)
                XCTAssertEqual(frame.minX, point.x - 18, accuracy: 0.01)
            }
        }
    }

    func testSmallWindowCanPlaceMenuOutsideOwnerButInsideScreen() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let visible = screen.visibleFrame
        let frame = NSMakeRect(visible.midX - 220, visible.midY - 150, 440, 300)
        try checkMenu(screen: screen, ownerFrame: frame, point: NSMakePoint(frame.midX, frame.maxY - 5)) { menu, bounds, point in
            XCTAssertEqual(menu.maxY, point.y + 20, accuracy: 0.01)
            XCTAssertGreaterThan(menu.maxY, frame.maxY)
            XCTAssertLessThanOrEqual(menu.maxY, bounds.maxY)
        }
    }

    func testBetterInsideMenuClampsToOwnerTop() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let visible = screen.visibleFrame
        let frame = NSMakeRect(visible.midX - 220, visible.midY - 150, 440, 300)
        try checkMenu(screen: screen, ownerFrame: frame, point: NSMakePoint(frame.midX, frame.maxY - 5), betterInside: true) { menu, bounds, _ in
            XCTAssertEqual(menu.maxY, bounds.maxY, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(menu.minY, bounds.minY)
        }
    }

    func testBottomClampKeepsItsExistingPosition() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let visible = screen.visibleFrame
        try checkMenu(screen: screen, point: NSMakePoint(visible.midX, visible.minY + 5), rows: 3) { frame, bounds, _ in
            XCTAssertEqual(frame.minY, bounds.minY, accuracy: 0.01)
            XCTAssertLessThanOrEqual(frame.maxY, bounds.maxY)
        }
    }

    func testBottomAnchoredMenuAlsoStaysBelowTopEdge() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let visible = screen.visibleFrame
        try checkMenu(screen: screen, point: NSMakePoint(visible.midX, visible.maxY - 5), bottomAnchor: true, rows: 3) { frame, bounds, _ in
            XCTAssertEqual(frame.maxY, bounds.maxY, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(frame.minY, bounds.minY)
        }
    }

    func testHorizontalAdjustmentIsUnchangedAtTheTopEdge() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        let visible = screen.visibleFrame
        for x in [visible.minX + 1, visible.maxX - 1] {
            try checkMenu(screen: screen, point: NSMakePoint(x, visible.maxY - 5)) { frame, bounds, point in
                let expectedX = x < bounds.midX ? bounds.minX + 40 : point.x - 18 - frame.width + 40
                XCTAssertEqual(frame.minX, expectedX, accuracy: 0.01)
                XCTAssertEqual(frame.maxY, bounds.maxY, accuracy: 0.01)
            }
        }
    }

    func testHoverPlacementStaysWithinVisibleScreen() throws {
        let screen = try XCTUnwrap(NSScreen.main)
        try checkMenu(screen: screen, point: NSMakePoint(screen.visibleFrame.midX, screen.visibleFrame.maxY - 4), mode: .hover) { frame, bounds, _ in
            XCTAssertLessThanOrEqual(frame.maxY, bounds.maxY)
            XCTAssertGreaterThanOrEqual(frame.minY, bounds.minY)
        }
    }

    func testEachConnectedScreenUsesItsOwnVisibleTop() throws {
        XCTAssertFalse(NSScreen.screens.isEmpty)
        for screen in NSScreen.screens {
            let visible = screen.visibleFrame
            try checkMenu(screen: screen, point: NSMakePoint(visible.midX, visible.maxY - 5)) { frame, bounds, _ in
                XCTAssertEqual(frame.maxY, bounds.maxY, accuracy: 0.01)
                XCTAssertGreaterThanOrEqual(frame.minY, bounds.minY)
            }
        }
    }
}
