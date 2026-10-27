import AppKit
import ColorPalette
import XCTest
@testable import TGUIKit

final class TabBarControllerShadowTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    private func makeController(size: NSSize = NSSize(width: 380, height: 700)) -> TabBarController {
        let controller = TabBarController()
        controller.bar = .init(height: 0)
        controller._frameRect = NSRect(origin: .zero, size: size)
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        return controller
    }

    private func makeTab(controller: ViewController = ViewController()) -> TabItem {
        controller.bar = .init(height: 0)
        let image = testImage(NSSize(width: 24, height: 24))
        return TabItem(image: image, selectedImage: image, controller: controller)
    }

    private func shadow(in controller: TabBarController) throws -> EdgeEffectView {
        return try XCTUnwrap(controller.view.subviews.compactMap { $0 as? EdgeEffectView }.first)
    }

    private func bar(in controller: TabBarController) throws -> TabBarView {
        return try XCTUnwrap(controller.view.subviews.compactMap { $0 as? TabBarView }.first)
    }

    func testShadowStaysAboveOpaqueContentWhenSwitchingTabs() throws {
        let controller = makeController()
        let first = ViewController()
        let second = ViewController()
        controller.add(tab: makeTab(controller: first))
        controller.add(tab: makeTab(controller: second))
        let shadow = try shadow(in: controller)
        let bar = try bar(in: controller)
        for (index, child) in [first, second].enumerated() {
            child.loadViewIfNeeded()
            child.view.layer?.backgroundColor = NSColor.white.cgColor
            controller.select(index: index)
            let views = controller.view.subviews
            XCTAssertLessThan(try XCTUnwrap(views.firstIndex(of: child.view)), try XCTUnwrap(views.firstIndex(of: shadow)))
            XCTAssertLessThan(try XCTUnwrap(views.firstIndex(of: shadow)), try XCTUnwrap(views.firstIndex(of: bar)))
            XCTAssertEqual(child.view.frame, controller.bounds)
            XCTAssertFalse(shadow.isHidden)
            XCTAssertEqual(controller.contentBottomInset, 64)
        }
    }

    func testShadowFillsThePaneWidthAndTracksItsBottomEdge() throws {
        let controller = makeController()
        controller.add(tab: makeTab())
        let shadow = try shadow(in: controller)
        let bar = try bar(in: controller)
        for size in [NSSize(width: 380, height: 700), NSSize(width: 800, height: 700), NSSize(width: 280, height: 110), NSSize(width: 10, height: 20), .zero] {
            controller.updateFrame(NSRect(origin: .zero, size: size), transition: .immediate)
            XCTAssertEqual(shadow.frame.minX, 0)
            XCTAssertEqual(shadow.frame.width, size.width)
            XCTAssertEqual(shadow.frame.minY, max(0, bar.frame.minY - 24))
            XCTAssertEqual(shadow.frame.maxY, size.height)
            XCTAssertGreaterThanOrEqual(shadow.frame.height, 0)
            XCTAssertLessThanOrEqual(bar.frame.width, 500)
        }
    }

    func testShadowVisibilityFollowsTabInsertionRemovalAndHiding() throws {
        let controller = makeController()
        let shadow = try shadow(in: controller)
        XCTAssertTrue(shadow.isHidden)
        controller.add(tab: makeTab())
        XCTAssertFalse(shadow.isHidden)
        controller.hideTabView(true)
        XCTAssertTrue(shadow.isHidden)
        controller.hideTabView(false)
        XCTAssertFalse(shadow.isHidden)
        controller.remove(at: 0)
        XCTAssertTrue(shadow.isHidden)
        controller.insert(tab: makeTab(), at: 0)
        XCTAssertFalse(shadow.isHidden)
        controller.hideTabView(true)
        controller.add(tab: makeTab())
        XCTAssertTrue(shadow.isHidden)
    }

    func testShadowPassesClicksToContentAndTheTabBar() throws {
        let controller = makeController(size: NSSize(width: 800, height: 700))
        let child = ViewController()
        controller.add(tab: makeTab(controller: child))
        controller.select(index: 0)
        let parent = View(frame: controller.bounds)
        parent.addSubview(controller.view)
        let shadow = try shadow(in: controller)
        let bar = try bar(in: controller)
        let outside = NSPoint(x: 10, y: bar.frame.midY)
        XCTAssertTrue(shadow.isEventLess)
        XCTAssertNil(shadow.hitTest(outside))
        XCTAssertTrue(controller.view.hitTest(outside) === child.view)
        let inside = NSPoint(x: bar.frame.midX, y: bar.frame.midY)
        XCTAssertTrue(controller.view.hitTest(inside) === controller.control(for: 0))
    }

    func testShadowUsesTheHeaderGradientAndUpdatesWithTheTheme() throws {
        let controller = makeController()
        controller.add(tab: makeTab())
        let shadow = try shadow(in: controller)
        let gradient = try XCTUnwrap(shadow.layer?.sublayers?.first as? CAGradientLayer)
        for palette in [whitePalette, darkPalette] {
            let theme = PresentationTheme(colors: palette, search: presentation.search, inputTheme: presentation.inputTheme)
            controller.updateLocalizationAndTheme(theme: theme)
            let colors = try XCTUnwrap(gradient.colors as? [CGColor])
            XCTAssertEqual(colors.first, palette.listBackground.withAlphaComponent(0.6).cgColor)
            XCTAssertEqual(colors.last?.alpha, 0)
            XCTAssertEqual(gradient.startPoint, NSPoint(x: 0.5, y: 1))
            XCTAssertEqual(gradient.endPoint, NSPoint(x: 0.5, y: 0))
            XCTAssertEqual(gradient.frame, shadow.bounds)
        }
    }
}
