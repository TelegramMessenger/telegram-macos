import XCTest
import AppKit
import QuartzCore
@testable import TGUIKit

final class NavigationAnimationTests: XCTestCase {
    private final class LayoutView: View {
        var onLayout: (() -> Void)?

        override func layout() {
            super.layout()
            onLayout?()
        }
    }

    private final class ContentController: ViewController {
        var appearances = 0
        var fullSlide = false

        override var fullSlideAnimation: Bool { fullSlide }

        override func viewDidLoad() {
            super.viewDidLoad()
            readyOnce()
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            appearances += 1
        }
    }

    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    func testPushWithPendingWindowLayout() throws {
        for width: CGFloat in [360, 820] {
            try verifyPendingLayoutTransition(width: width, pop: false, fullSlide: false)
        }
    }

    func testPopWithPendingWindowLayout() throws {
        for fullSlide in [false, true] {
            try verifyPendingLayoutTransition(width: 820, pop: true, fullSlide: fullSlide)
        }
    }

    private func verifyPendingLayoutTransition(width: CGFloat, pop: Bool, fullSlide: Bool) throws {
        let window = Window(contentRect: NSMakeRect(0, 0, width, 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = LayoutView(frame: NSMakeRect(0, 0, width, 600))
        let chat = ContentController()
        chat.insets = NSEdgeInsets(top: 7, left: 11, bottom: 13, right: 17)
        let navigation = NavigationViewController(chat, window)
        navigation.loadViewIfNeeded(root.bounds)
        root.addSubview(navigation.view)
        window.contentView = root
        window.orderBack(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        let profile = ContentController()
        profile.fullSlide = fullSlide
        profile.insets = NSEdgeInsets(top: 5, left: 9, bottom: 15, right: 19)
        if pop {
            navigation.push(profile, false)
        }
        root.onLayout = { [weak navigation, weak root] in
            guard let navigation, let root else { return }
            navigation.viewDidResized(root.bounds.size)
        }
        navigation.controllerDidChange = { [weak root] in
            root?.needsLayout = true
        }
        if pop {
            navigation.back()
        } else {
            navigation.push(profile)
        }
        let incoming = pop ? chat : profile
        let outgoing = pop ? profile : chat
        let expectedStart = pop ? (fullSlide ? -width : -round(width / 3)) : width
        let incomingContainer = navigation.containerOf(incoming)
        let animation = try XCTUnwrap(incomingContainer.layer?.animation(forKey: "position") as? CABasicAnimation)
        XCTAssertEqual((animation.fromValue as? NSValue)?.pointValue.x, expectedStart)
        XCTAssertEqual((animation.toValue as? NSValue)?.pointValue.x, incoming.insets.left)
        XCTAssertTrue(navigation.isLocked)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        let presentedX = try XCTUnwrap(incomingContainer.layer?.presentation()).frame.minX
        XCTAssertGreaterThan(presentedX, min(expectedStart, incoming.insets.left))
        XCTAssertLessThan(presentedX, max(expectedStart, incoming.insets.left))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        XCTAssertEqual(incoming.appearances, pop ? 2 : 1)
        XCTAssertFalse(navigation.isLocked)
        XCTAssertEqual(incomingContainer.frame.minX, incoming.insets.left)
        XCTAssertEqual(incomingContainer.frame.minY, incoming.insets.top)
        XCTAssertNil(navigation.existingContainerOf(outgoing)?.superview)
    }

    func testIncomingSlideSurvivesBackgroundCommit() throws {
        let window = Window(contentRect: NSMakeRect(0, 0, 800, 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let chat = ContentController()
        let navigation = NavigationViewController(chat, window)
        navigation.loadViewIfNeeded(NSMakeRect(0, 0, 800, 600))
        window.contentView = navigation.view
        window.orderBack(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        let profile = ContentController()
        navigation.push(profile)
        let incoming = navigation.containerOf(profile)
        let outgoing = navigation.containerOf(chat)
        XCTAssertNotNil(incoming.layer?.animation(forKey: "position"))
        DispatchQueue.global().sync {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            let layer = CALayer()
            layer.opacity = 0.5
            CATransaction.commit()
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        XCTAssertNotNil(incoming.layer?.animation(forKey: "position"))
        XCTAssertNotNil(outgoing.layer?.animation(forKey: "position"))
        XCTAssertTrue(navigation.isLocked)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        XCTAssertEqual(profile.appearances, 1)
        XCTAssertFalse(navigation.isLocked)
    }

    func testRepeatedSlidesDuringBackgroundLayerUpdates() throws {
        let window = Window(contentRect: NSMakeRect(0, 0, 800, 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let chat = ContentController()
        chat.animationStyle = .init(duration: 0.08, function: .spring)
        let navigation = NavigationViewController(chat, window)
        navigation.loadViewIfNeeded(NSMakeRect(0, 0, 800, 600))
        window.contentView = navigation.view
        window.orderBack(nil)
        let background = CALayer()
        chat.view.layer?.addSublayer(background)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        let worker = DispatchGroup()
        worker.enter()
        let stop = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            var index = 0
            while stop.wait(timeout: .now()) == .timedOut {
                index += 1
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                background.opacity = index % 2 == 0 ? 0.5 : 1
                let layer = CALayer()
                background.addSublayer(layer)
                layer.removeFromSuperlayer()
                CATransaction.commit()
                usleep(500)
            }
            worker.leave()
        }
        for _ in 0..<20 {
            let profile = ContentController()
            profile.animationStyle = chat.animationStyle
            navigation.push(profile)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            XCTAssertNotNil(navigation.containerOf(profile).layer?.animation(forKey: "position"))
            XCTAssertTrue(navigation.isLocked)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12))
            XCTAssertEqual(profile.appearances, 1)
            navigation.back()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            XCTAssertNotNil(navigation.containerOf(chat).layer?.animation(forKey: "position"))
            XCTAssertTrue(navigation.isLocked)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.12))
        }
        stop.signal()
        worker.wait()
    }
}
