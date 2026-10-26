import AppKit
import XCTest
import SwiftUI
@testable import TGUIKit

final class SwitchViewTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
        TGUIKitAccessibility.isEnabled = true
    }

    override func tearDown() {
        for window in windows {
            window.contentView = nil
            window.close()
        }
        windows.removeAll()
        super.tearDown()
    }

    private func makeSwitch(on: Bool = false, motion: Bool = false) -> SwitchView {
        let view = SwitchView()
        view.reduceMotion = { !motion }
        view.setIsOn(on, animated: false)
        let window = SnapshotWindow(contentRect: CGRect(x: 0, y: 0, width: 120, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        view.frame.origin = CGPoint(x: 20, y: 20)
        window.contentView?.addSubview(view)
        windows.append(window)
        return view
    }

    private func waitUntilRest(_ view: SwitchView, file: StaticString = #filePath, line: UInt = #line) {
        CATransaction.flush()
        let deadline = Date().addingTimeInterval(2)
        while view.isSettling && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertFalse(view.isSettling, file: file, line: line)
    }

    func testClickCommitsOnlyAfterSettling() {
        let view = makeSwitch(motion: true)
        var calls = 0
        view.stateChanged = {
            calls += 1
            XCTAssertTrue(view.isOn)
            XCTAssertFalse(view.isSettling)
            XCTAssertEqual(view.currentThumbFrame.size, CGSize(width: 20, height: 13))
        }
        view.beginInteraction(at: CGPoint(x: 6, y: 10))
        XCTAssertFalse(view.isOn)
        view.endInteraction(at: CGPoint(x: 6, y: 10))
        XCTAssertTrue(view.isSettling)
        XCTAssertFalse(view.isOn)
        XCTAssertEqual(calls, 0)
        waitUntilRest(view)
        XCTAssertTrue(view.isOn)
        XCTAssertEqual(calls, 1)
    }

    func testPointerJitterIsAClick() {
        let view = makeSwitch()
        var calls = 0
        view.stateChanged = { calls += 1 }
        view.beginInteraction(at: CGPoint(x: 10, y: 10))
        view.dragInteraction(to: CGPoint(x: 11, y: 11))
        view.endInteraction(at: CGPoint(x: 11, y: 11))
        XCTAssertTrue(view.isOn)
        XCTAssertEqual(calls, 1)
    }

    func testDraggingBothDirectionsDefersValueUntilRelease() {
        for initial in [false, true] {
            let view = makeSwitch(on: initial)
            var calls = 0
            view.stateChanged = { calls += 1 }
            let start = CGPoint(x: 18, y: 10)
            let end = CGPoint(x: initial ? 2 : 34, y: 10)
            view.beginInteraction(at: start)
            view.dragInteraction(to: end)
            XCTAssertEqual(view.isOn, initial)
            XCTAssertEqual(calls, 0)
            view.endInteraction(at: end)
            XCTAssertEqual(view.isOn, !initial)
            XCTAssertEqual(calls, 1)
        }
    }

    func testDraggingBackToTheOriginalSideDoesNotToggle() {
        let view = makeSwitch()
        var calls = 0
        view.stateChanged = { calls += 1 }
        view.beginInteraction(at: CGPoint(x: 10, y: 10))
        view.dragInteraction(to: CGPoint(x: 30, y: 10))
        view.endInteraction(at: CGPoint(x: 10, y: 10))
        XCTAssertFalse(view.isOn)
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(view.visualPosition, 0)
    }

    func testMidpointRetainsOriginalState() {
        for initial in [false, true] {
            let view = makeSwitch(on: initial)
            var calls = 0
            view.stateChanged = { calls += 1 }
            view.beginInteraction(at: CGPoint(x: 18, y: 10))
            view.endInteraction(at: CGPoint(x: initial ? 11.5 : 24.5, y: 10))
            XCTAssertEqual(view.isOn, initial)
            XCTAssertEqual(calls, 0)
        }
    }

    func testDraggingOutsideTheControlAllowsOnlyBoundedHorizontalGive() {
        let view = makeSwitch()
        view.beginInteraction(at: CGPoint(x: 18, y: 10))
        view.dragInteraction(to: CGPoint(x: 500, y: 500))
        XCTAssertEqual(view.visualPosition, 1)
        XCTAssertGreaterThan(view.currentThumbFrame.midX, 27)
        XCTAssertLessThan(view.currentThumbFrame.midX, 27.5)
        XCTAssertEqual(view.currentThumbFrame.midY, 10)
        view.endInteraction(at: CGPoint(x: 500, y: 500))
        XCTAssertTrue(view.isOn)
        XCTAssertEqual(view.currentThumbFrame, CGRect(x: 14.5, y: 3.5, width: 20, height: 13))
    }

    func testDraggingSnapsBetweenEndpointsBeforeReleaseWithoutCommitting() {
        for initial in [false, true] {
            let view = makeSwitch(on: initial)
            var calls = 0
            view.stateChanged = { calls += 1 }
            view.beginInteraction(at: CGPoint(x: 18, y: 10))
            for x in stride(from: CGFloat(-20), through: 56, by: 0.5) {
                view.dragInteraction(to: CGPoint(x: x, y: 18))
                let position = (initial ? 1.0 : 0.0) + (x - 18) / 13
                let expected: CGFloat = position == 0.5 ? (initial ? 1 : 0) : (position > 0.5 ? 1 : 0)
                XCTAssertEqual(view.visualPosition, expected)
                XCTAssertLessThan(abs(view.currentThumbFrame.midX - (11.5 + 13 * expected)), 3)
                XCTAssertEqual(view.currentThumbFrame.midY, 10)
                XCTAssertEqual(view.isOn, initial)
                XCTAssertEqual(calls, 0)
            }
            view.endInteraction(at: CGPoint(x: 56, y: 18))
            XCTAssertTrue(view.isOn)
            XCTAssertEqual(calls, initial ? 0 : 1)
        }
    }

    func testClickReleasedOutsideDoesNotToggle() {
        let view = makeSwitch()
        var calls = 0
        view.stateChanged = { calls += 1 }
        view.beginInteraction(at: CGPoint(x: 35, y: 10))
        view.endInteraction(at: CGPoint(x: 37, y: 10))
        XCTAssertFalse(view.isOn)
        XCTAssertEqual(calls, 0)
    }

    func testOwnerControlledSwitchRequestsWithoutCommitting() {
        let view = makeSwitch(motion: true)
        view.autoswitch = false
        var calls = 0
        view.stateChanged = {
            calls += 1
            XCTAssertFalse(view.isOn)
            XCTAssertEqual(view.visualPosition, 0)
        }
        view.beginInteraction(at: CGPoint(x: 10, y: 10))
        view.endInteraction(at: CGPoint(x: 30, y: 10))
        XCTAssertEqual(calls, 0)
        waitUntilRest(view)
        XCTAssertEqual(calls, 1)
        XCTAssertFalse(view.isOn)
        view.setIsOn(true, animated: false)
        XCTAssertTrue(view.isOn)
        XCTAssertEqual(calls, 1)
    }

    func testProgrammaticUpdateCancelsPendingCallbackEvenForTheSameValue() {
        let view = makeSwitch(motion: true)
        var calls = 0
        view.stateChanged = { calls += 1 }
        view.performToggle()
        view.setIsOn(false, animated: false)
        RunLoop.current.run(until: Date().addingTimeInterval(SwitchMotion.settlingDuration + 0.1))
        XCTAssertFalse(view.isOn)
        XCTAssertFalse(view.isSettling)
        XCTAssertEqual(calls, 0)
    }

    func testNewPressFinishesThePreviousChangeExactlyOnce() {
        let view = makeSwitch(motion: true)
        var values: [Bool] = []
        view.stateChanged = { values.append(view.isOn) }
        view.performToggle()
        XCTAssertEqual(values, [])
        view.beginInteraction(at: CGPoint(x: 18, y: 10))
        XCTAssertEqual(values, [true])
        view.endInteraction(at: CGPoint(x: 18, y: 10))
        waitUntilRest(view)
        XCTAssertEqual(values, [true, false])
    }

    func testDisabledAndNoninteractiveSwitchesIgnoreActivation() {
        let view = makeSwitch()
        var calls = 0
        view.stateChanged = { calls += 1 }
        view.isEnabled = false
        view.performToggle()
        view.beginInteraction(at: CGPoint(x: 18, y: 10))
        XCTAssertFalse(view.accessibilityPerformPress())
        view.isEnabled = true
        view.userInteractionEnabled = false
        view.performToggle()
        XCTAssertFalse(view.accessibilityPerformPress())
        XCTAssertFalse(view.isTracking)
        XCTAssertFalse(view.isOn)
        XCTAssertEqual(calls, 0)
    }

    func testCancellationInvalidatesTrackingAndSettling() {
        for cancel in [
            { (view: SwitchView) in view.cancelInteraction() },
            { view in view.isEnabled = false },
            { view in view.userInteractionEnabled = false },
            { view in view.isHidden = true },
            { view in view.removeFromSuperview() },
            { view in NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: view.window) }
        ] {
            for settling in [false, true] {
                let view = makeSwitch(motion: true)
                var calls = 0
                view.stateChanged = { calls += 1 }
                view.beginInteraction(at: CGPoint(x: 18, y: 10))
                view.dragInteraction(to: CGPoint(x: 34, y: 10))
                if settling { view.endInteraction(at: CGPoint(x: 34, y: 10)) }
                cancel(view)
                XCTAssertFalse(view.isTracking)
                XCTAssertFalse(view.isSettling)
                XCTAssertFalse(view.isOn)
                XCTAssertEqual(calls, 0)
            }
        }
    }

    func testMouseEventsDoNotToggleTwice() {
        let view = makeSwitch()
        var calls = 0
        view.stateChanged = { calls += 1 }
        let location = view.convert(CGPoint(x: 18, y: 10), to: nil)
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [], timestamp: 0.1, windowNumber: view.window!.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0)!
        view.mouseDown(with: down)
        view.mouseUp(with: up)
        XCTAssertTrue(view.isOn)
        XCTAssertEqual(calls, 1)
    }

    func testThemePaletteAndDisabledColorArePreserved() {
        let view = makeSwitch()
        view.presentation = SwitchViewAppearance(backgroundColor: .black, stateOnColor: .purple, stateOffColor: .red, disabledColor: .gray, borderColor: .clear)
        XCTAssertEqual(view.trackLayer.backgroundColor, NSColor.red.cgColor)
        view.setIsOn(true, animated: false)
        XCTAssertEqual(view.trackLayer.backgroundColor, NSColor.purple.cgColor)
        view.updateLocalizationAndTheme(theme: PresentationTheme.current)
        XCTAssertEqual(view.trackLayer.backgroundColor, NSColor.purple.cgColor)
        view.isEnabled = false
        XCTAssertEqual(view.trackLayer.backgroundColor, NSColor.gray.cgColor)
    }

    func testGeometryScalesWithBoundsAndKeepsCapsuleThumb() {
        let view = makeSwitch(on: true)
        view.setFrameSize(CGSize(width: 72, height: 40))
        XCTAssertEqual(view.trackLayer.frame.size, CGSize(width: 72, height: 32))
        XCTAssertEqual(view.currentThumbFrame.size, CGSize(width: 40, height: 26))
        XCTAssertEqual(view.currentThumbFrame.minX, 29)
    }

    func testLensFailureKeepsTheOpaqueThumbAndControlHitTarget() {
        let previous = System.liquidGlass
        defer { System.liquidGlass = previous }
        System.liquidGlass = true
        let view = makeSwitch()
        view.lensFactory = { nil }
        view.reduceTransparency = { true }
        view.cancelInteraction()
        view.reduceTransparency = { false }
        view.beginInteraction(at: CGPoint(x: 18, y: 10))
        XCTAssertNil(view.nativeLens)
        XCTAssertTrue(view.hitTest(CGPoint(x: 38, y: 30)) === view)
        XCTAssertNil(view.hitTest(CGPoint(x: 19, y: 30)))
        XCTAssertEqual(view.accessibilityChildren()?.count, 0)
    }

    func testLensTracksTheThumbAndReleasesItsSurfaceAtRest() throws {
        guard System.liquidGlassAvailable else { throw XCTSkip("Liquid Glass requires a supported system") }
        let previous = System.liquidGlass
        defer { System.liquidGlass = previous }
        System.liquidGlass = true
        let view = makeSwitch(motion: true)
        view.reduceTransparency = { false }
        let restingFrame = view.currentThumbFrame
        let trackParent = view.trackLayer.superlayer
        XCTAssertNil(view.nativeLens)
        view.beginInteraction(at: CGPoint(x: 18, y: 10))
        guard let lens = view.nativeLens, lens.hasActiveSurface else { throw XCTSkip("Liquid Glass runtime unavailable") }
        let surface = try XCTUnwrap(lens.subviews.last?.layer?.sublayers?.first)
        XCTAssertGreaterThanOrEqual(surface.frame.width, restingFrame.width * 1.5)
        XCTAssertGreaterThanOrEqual(surface.frame.width / surface.frame.height, restingFrame.width / restingFrame.height)
        view.dragInteraction(to: CGPoint(x: 34, y: 10))
        XCTAssertTrue(view.nativeLens === lens)
        XCTAssertTrue(lens.hasActiveSurface)
        XCTAssertEqual(lens.activePortalCount, 0)
        XCTAssertTrue(lens.contentView.subviews.isEmpty)
        XCTAssertTrue(view.trackLayer.superlayer === trackParent)
        view.endInteraction(at: CGPoint(x: 34, y: 10))
        waitUntilRest(view)
        XCTAssertTrue(view.isOn)
        XCTAssertNil(view.nativeLens)
        XCTAssertFalse(lens.hasActiveSurface)
        XCTAssertEqual(lens.activePortalCount, 0)
    }

    func testSpaceAndEscapeFollowTheSameCommitAndCancellationRules() {
        let view = makeSwitch(motion: true)
        var calls = 0
        view.stateChanged = { calls += 1 }
        let space = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
        view.keyDown(with: space)
        XCTAssertFalse(view.isOn)
        waitUntilRest(view)
        XCTAssertTrue(view.isOn)
        XCTAssertEqual(calls, 1)
        view.beginInteraction(at: CGPoint(x: 18, y: 10))
        view.dragInteraction(to: CGPoint(x: 2, y: 10))
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: view.window!.windowNumber, context: nil, characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        view.keyDown(with: escape)
        view.endInteraction(at: CGPoint(x: 2, y: 10))
        XCTAssertTrue(view.isOn)
        XCTAssertFalse(view.isTracking)
        XCTAssertFalse(view.isSettling)
        XCTAssertEqual(calls, 1)
    }

    func testPositionSpringMatchesTheNativeMacProfile() throws {
        let view = makeSwitch(motion: true)
        view.performToggle()
        let animation = try XCTUnwrap(view.positionAnimation)
        XCTAssertEqual(animation.speed, 1)
        XCTAssertEqual(animation.mass, 1)
        if #available(macOS 14.0, *) {
            let reference = Spring(response: 0.47, dampingRatio: 0.7)
            XCTAssertEqual(animation.stiffness, reference.stiffness, accuracy: 0.0000001)
            XCTAssertEqual(animation.damping, reference.damping, accuracy: 0.0000001)
            XCTAssertEqual(animation.duration, reference.settlingDuration, accuracy: 0.0000001)
            for time in stride(from: 0.0, through: 0.9, by: 0.05) {
                let sample = try XCTUnwrap(SwitchMotion.sample(animation, elapsed: time))
                XCTAssertEqual(sample.position.x, reference.value(target: 13.0, time: time), accuracy: 0.000001)
                XCTAssertEqual(sample.velocity.x, reference.velocity(target: 13.0, time: time), accuracy: 0.000001)
            }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertFalse(view.isOn)
        XCTAssertTrue(view.isSettling)
        waitUntilRest(view)
        XCTAssertTrue(view.isOn)
    }

    func testDraggingWithinAnEndpointPreservesTheRunningSnapSpring() throws {
        let view = makeSwitch(motion: true)
        view.beginInteraction(at: CGPoint(x: 18, y: 10))
        view.dragInteraction(to: CGPoint(x: 34, y: 10))
        let spring = try XCTUnwrap(view.positionAnimation)
        view.dragInteraction(to: CGPoint(x: 35, y: 10))
        XCTAssertTrue(try XCTUnwrap(view.positionAnimation).isEqual(spring))
        XCTAssertGreaterThan(view.currentThumbFrame.midX, 24.5)
        XCTAssertLessThan(view.currentThumbFrame.midX, 27.5)
        XCTAssertFalse(view.isOn)
    }

    func testReversingTheSnapPreservesVelocity() throws {
        let view = makeSwitch(motion: true)
        view.beginInteraction(at: CGPoint(x: 18, y: 10))
        view.dragInteraction(to: CGPoint(x: 34, y: 10))
        CATransaction.flush()
        RunLoop.current.run(until: Date().addingTimeInterval(0.06))
        view.dragInteraction(to: CGPoint(x: 18, y: 10))
        XCTAssertLessThan(try XCTUnwrap(view.positionAnimation).initialVelocity, 0)
        XCTAssertFalse(view.isOn)
    }

    func testOffStateLiftStartsAtRestAndUsesComplementaryOpacityCurves() throws {
        guard System.liquidGlassAvailable else { throw XCTSkip("Liquid Glass requires a supported system") }
        let previous = System.liquidGlass
        defer { System.liquidGlass = previous }
        System.liquidGlass = true
        let view = makeSwitch(motion: true)
        view.reduceTransparency = { false }
        let restingFrame = view.currentThumbFrame
        let trackParent = view.trackLayer.superlayer
        view.beginInteraction(at: CGPoint(x: 18, y: 10))
        let lens = try XCTUnwrap(view.nativeLens)
        let surface = try XCTUnwrap(lens.subviews.last?.layer?.sublayers?.first)
        let bounds = try XCTUnwrap(surface.animation(forKey: "bounds") as? CABasicAnimation)
        XCTAssertEqual((bounds.fromValue as? NSValue)?.rectValue.size, restingFrame.size)
        let glass = try XCTUnwrap(surface.sublayers?.first?.animation(forKey: "opacity") as? CABasicAnimation)
        let white = try XCTUnwrap(view.appearanceAnimation?.animations?.first(where: { ($0 as? CABasicAnimation)?.keyPath == "opacity" }) as? CABasicAnimation)
        XCTAssertEqual(glass.duration, 0.2)
        XCTAssertEqual(white.duration, glass.duration)
        XCTAssertEqual((glass.fromValue as? NSNumber)?.doubleValue, 0)
        XCTAssertEqual((glass.toValue as? NSNumber)?.doubleValue, 1)
        XCTAssertEqual((white.fromValue as? NSNumber)?.doubleValue, 1)
        XCTAssertEqual((white.toValue as? NSNumber)?.doubleValue, 0)
        for index in 0..<4 {
            var first: [Float] = [0, 0]
            var second: [Float] = [0, 0]
            glass.timingFunction?.getControlPoint(at: index, values: &first)
            white.timingFunction?.getControlPoint(at: index, values: &second)
            XCTAssertEqual(first, second)
        }
        XCTAssertTrue(view.trackLayer.superlayer === trackParent)
        XCTAssertTrue(lens.contentView.subviews.isEmpty)
    }

    func testReferenceAppearanceSnapshots() {
        guard let path = ProcessInfo.processInfo.environment["SWITCH_SNAPSHOT_PATH"] else { return }
        let canvas = View(frame: CGRect(x: 0, y: 0, width: 220, height: 120))
        canvas.backgroundColor = NSColor(white: 0.14, alpha: 1)
        for (index, color) in [NSColor.systemGreen, .systemBlue, .systemPurple, .systemRed].enumerated() {
            for on in [false, true] {
                let view = SwitchView()
                view.presentation = SwitchViewAppearance(backgroundColor: .black, stateOnColor: color, stateOffColor: NSColor(white: 0.28, alpha: 1), disabledColor: .gray, borderColor: .clear)
                view.setIsOn(on, animated: false)
                view.frame.origin = CGPoint(x: on ? 140 : 40, y: 10 + 28 * index)
                canvas.addSubview(view)
            }
        }
        ViewSnapshot.render(canvas).write(to: path)
    }
}
