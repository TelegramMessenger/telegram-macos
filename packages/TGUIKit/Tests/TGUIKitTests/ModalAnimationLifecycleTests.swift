import XCTest
import AppKit
import QuartzCore
@testable import TGUIKit

final class ModalAnimationLifecycleTests: XCTestCase {
    private final class ContentController: ModalViewController {
        var automaticallyReady = true
        var appearances = 0

        override func viewDidLoad() {
            super.viewDidLoad()
            if automaticallyReady {
                readyOnce()
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            appearances += 1
        }
    }

    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
        ModalMorphContextSource.clear()
    }

    private func animatedMorphLayers(_ layer: CALayer) -> [CALayer] {
        let children = (layer.sublayers ?? []).flatMap(animatedMorphLayers)
        return layer.animation(forKey: "modalMorph.position") == nil ? children : [layer] + children
    }

    func testIncomingViewStaysTransparentUntilItsAnimationIsInstalled() throws {
        let window = Window(contentRect: NSMakeRect(0, 0, 800, 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = View(frame: NSMakeRect(0, 0, 800, 600))
        window.contentView = root
        window.orderBack(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        let incoming = View(frame: NSMakeRect(100, 100, 320, 300))
        let reveal = prepareLayerAnimation([incoming]) {
            root.addSubview(incoming)
        }
        let layer = try XCTUnwrap(incoming.layer)
        XCTAssertNotNil(layer.superlayer)
        XCTAssertEqual(layer.opacity, 0)
        XCTAssertEqual(try XCTUnwrap(layer.presentation()).opacity, 0)
        layer.animatePosition(from: NSMakePoint(800, 100), to: incoming.frame.origin, duration: 0.3)
        reveal()
        XCTAssertEqual(layer.opacity, 1)
        XCTAssertNotNil(layer.animation(forKey: "position"))
    }

    func testCapturedLinkSnapshotSurvivesLookupAndControllerReadiness() throws {
        let reduceMotion = ModalMorphTransition.reduceMotion
        ModalMorphTransition.reduceMotion = { false }
        defer { ModalMorphTransition.reduceMotion = reduceMotion }
        let window = Window(contentRect: NSMakeRect(0, 0, 800, 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = View(frame: NSMakeRect(0, 0, 800, 600))
        window.contentView = root
        window.orderBack(nil)
        let rect = window.convertToScreen(NSMakeRect(30, 40, 200, 20))
        ModalMorphContextSource.register(image: testImage(NSMakeSize(2, 2)), screenRect: rect)
        let snapshot = try XCTUnwrap(ModalMorphContextSource.captureSnapshot())
        XCTAssertNil(ModalMorphContextSource.captureSnapshot())
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.45))
        let controller = ContentController(frame: NSMakeRect(0, 0, 320, 300))
        controller.automaticallyReady = false
        let modal = Modal(controller: controller, for: window, isOverlay: false, animationType: .bottomToCenter, morphSnapshot: snapshot)
        modal.show()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.45))
        controller.readyOnce()
        XCTAssertFalse(try XCTUnwrap(root.layer).sublayers?.isEmpty ?? true)
        let layers = animatedMorphLayers(try XCTUnwrap(root.layer))
        XCTAssertFalse(layers.isEmpty)
        let layer = try XCTUnwrap(layers.first)
        let animation = try XCTUnwrap(layer.animation(forKey: "modalMorph.position") as? CAKeyframeAnimation)
        let start = try XCTUnwrap((animation.values?.first as? NSValue)?.pointValue)
        let startRect = root.convert(window.convertFromScreen(rect), from: nil)
        XCTAssertEqual(start.x - layer.anchorPoint.x * startRect.width, startRect.minX, accuracy: 1)
        XCTAssertEqual(start.y - layer.anchorPoint.y * startRect.height, startRect.minY, accuracy: 1)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1))
        XCTAssertEqual(controller.appearances, 1)
        modal.close(animationType: .noMorph)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
    }

    func testNormalAndMorphModalsSurviveBackgroundLayerCommits() throws {
        let reduceMotion = ModalMorphTransition.reduceMotion
        ModalMorphTransition.reduceMotion = { false }
        defer { ModalMorphTransition.reduceMotion = reduceMotion }
        let window = Window(contentRect: NSMakeRect(0, 0, 800, 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = View(frame: NSMakeRect(0, 0, 800, 600))
        window.contentView = root
        let source = View(frame: NSMakeRect(30, 40, 120, 40))
        source.layer?.contents = testImage(NSMakeSize(2, 2))
        root.addSubview(source)
        window.orderBack(nil)
        let background = CALayer()
        root.layer?.addSublayer(background)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        let stop = DispatchSemaphore(value: 0)
        let worker = DispatchGroup()
        worker.enter()
        DispatchQueue.global().async {
            var index = 0
            while stop.wait(timeout: .now()) == .timedOut {
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                background.opacity = index % 2 == 0 ? 0.5 : 1
                let layer = CALayer()
                background.addSublayer(layer)
                layer.removeFromSuperlayer()
                CATransaction.commit()
                index += 1
                usleep(500)
            }
            worker.leave()
        }
        defer {
            stop.signal()
            worker.wait()
        }
        for index in 0..<10 {
            let morph = index % 2 == 0
            let controller = ContentController(frame: NSMakeRect(0, 0, 320, 300))
            let modal = Modal(controller: controller, for: window, isOverlay: false, animationType: .bottomToCenter, morphSource: morph ? { [weak source] in source } : nil)
            modal.show()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
            if morph {
                XCTAssertFalse(animatedMorphLayers(try XCTUnwrap(root.layer)).isEmpty)
                XCTAssertTrue(modal.containerView.isHidden)
            } else {
                XCTAssertNotNil(modal.containerView.layer?.animation(forKey: "position"))
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.9))
            XCTAssertFalse(modal.containerView.isHidden)
            XCTAssertEqual(controller.appearances, 1)
            modal.close(animationType: .noMorph)
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        }
    }
}
