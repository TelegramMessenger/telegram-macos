import Cocoa
import QuartzCore
import XCTest

__ANIMATION_COMPLETION__

private final class FlightInteraction {
    var context = GlowContext(animationsDisabled: false, blurDisabled: false)
}

private struct FlightLabels { let voiceOverCommonDone = "Done" }
private func strings() -> FlightLabels { FlightLabels() }

private final class FlightSendView: View {
    let imageView = View(frame: CGRect(x: 5, y: 1, width: 30, height: 30))
    var appTooltip: String?
    required init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(imageView)
    }
    required init?(coder: NSCoder) { fatalError() }
}

private final class FlightButton: View {
    static let fieldSpringStiffness: CGFloat = 555.027
    static let fieldSpringDamping: CGFloat = 47.118
    let chatInteraction = FlightInteraction()
    static let planeFlightOffset = CGPoint(x: -22, y: 18)
    let send = FlightSendView(frame: CGRect(x: 0, y: 4, width: 40, height: 32))
    let dictationWaveform = ChatDictationWaveformView(frame: CGRect(x: 7, y: 5, width: 26, height: 22))
    var isDictating = true
    var dictationTransitionIcon: CALayer?
    var outgoingDictationWaveform: CALayer?
    var shouldFinishDictationTransition = false
    struct State {
        enum Kind { case send }
        var kind: Kind = .send
        var isEditing = false
        var isSendEnabled = true
        var isInlineLoading = false
    }
    var state = State()
    lazy var activeView: View = send
    func update(state: State, animated: Bool) { self.state = state }
    func finish() { finishDictationTransition() }

    required init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(send)
        send.layer!.cornerRadius = 16
        send.addSubview(dictationWaveform)
        updateDictationAppearance()
    }
    required init?(coder: NSCoder) { fatalError() }
    func stop() { setDictating(false) }
    __SET_DICTATING__
    __DICTATION_APPEARANCE__
    __FINISH_DICTATION__
    __PLANE_FLIGHT__
    __BUTTON_FLIGHT__
    __CANCEL_FLIGHT__
    __DETACH_FLIGHT__
}

private final class OriginOverlay: View {
    struct Blob { let centreDiameter: CGFloat = 60 }
    let blobView = Blob()
    var dictationTransitionIcon: CGImage?
}

private final class OriginHarness {
    let overlayView = OriginOverlay(frame: CGRect(x: 80, y: 20, width: 100, height: 100))
    __CAPTURE_ORIGIN__
}

final class DictationButtonFlightTests: XCTestCase {
    private func makeWindow() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 600, height: 300), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }

    func testWavesShrinkAndFadeAsThePlaneFliesInWithoutMovingThePill() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        let window = makeWindow()
        defer { window.close() }
        let button = FlightButton(frame: CGRect(x: 450, y: 20, width: 40, height: 40))
        window.contentView!.addSubview(button)
        let frame = button.send.frame
        for _ in 0 ..< 20 { button.dictationWaveform.updateLevel(1) }
        button.setDictating(false, animated: true)
        let outgoing = try XCTUnwrap(button.outgoingDictationWaveform)
        let frozenBars = outgoing.sublayers!.first as! CAShapeLayer
        XCTAssertGreaterThan(frozenBars.path!.boundingBoxOfPath.height, 10)
        XCTAssertEqual(outgoing.frame, button.dictationWaveform.frame)
        XCTAssertTrue(button.dictationWaveform.isHidden)
        XCTAssertFalse(button.send.imageView.isHidden)
        XCTAssertNil(button.send.imageView.layer!.animation(forKey: "planeFlight"))
        button.finish()
        XCTAssertFalse(button.shouldFinishDictationTransition)
        let fade = try XCTUnwrap(outgoing.animation(forKey: "dictationWavesFade") as? CABasicAnimation)
        XCTAssertEqual(fade.fromValue as? Int, 1)
        XCTAssertEqual(fade.toValue as? Int, 0)
        XCTAssertNotNil(outgoing.animation(forKey: "dictationWavesShrink"))
        let plane = try XCTUnwrap(button.send.imageView.layer!.animation(forKey: "planeFlight") as? CASpringAnimation)
        XCTAssertTrue(plane.isAdditive)
        XCTAssertEqual((plane.fromValue as! NSValue).pointValue, CGPoint(x: -22, y: 18))
        XCTAssertEqual((plane.toValue as! NSValue).pointValue, .zero)
        XCTAssertNotNil(button.send.imageView.layer!.animation(forKey: "dictationPlaneReveal"))
        XCTAssertEqual(button.send.frame, frame)
        button.finish()
        XCTAssertFalse(button.shouldFinishDictationTransition)
        button.setDictating(true)
        XCTAssertNil(button.outgoingDictationWaveform)
        XCTAssertNil(outgoing.superlayer)
        XCTAssertNil(button.send.imageView.layer!.animation(forKey: "planeFlight"))
        XCTAssertTrue(button.send.imageView.isHidden)
        XCTAssertFalse(button.dictationWaveform.isHidden)
    }

    func testEndingWithoutASendTargetDoesNotFlyAnAirplane() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        let window = makeWindow()
        defer { window.close() }
        let button = FlightButton(frame: CGRect(x: 450, y: 20, width: 40, height: 40))
        window.contentView!.addSubview(button)
        button.activeView = View(frame: .zero)
        button.setDictating(false, animated: true)
        button.finish()
        XCTAssertNil(button.outgoingDictationWaveform)
        XCTAssertNil(button.send.imageView.layer!.animation(forKey: "planeFlight"))
    }

    func testNavigationAndLiteModeSkipTheWaveToPlaneAnimation() {
        let window = makeWindow()
        defer { window.close() }
        let button = FlightButton(frame: CGRect(x: 450, y: 20, width: 40, height: 40))
        window.contentView!.addSubview(button)
        button.setDictating(false, animated: false)
        button.finish()
        XCTAssertNil(button.outgoingDictationWaveform)
        XCTAssertNil(button.send.imageView.layer!.animation(forKey: "planeFlight"))
        button.setDictating(true)
        button.chatInteraction.context.animationsDisabled = true
        button.setDictating(false, animated: true)
        button.finish()
        XCTAssertNil(button.outgoingDictationWaveform)
        XCTAssertNil(button.send.imageView.layer!.animation(forKey: "planeFlight"))
    }

    func testRecorderOriginPreservesCoordinatesAcrossWindows() {
        let window = makeWindow()
        defer { window.close() }
        let host = View(frame: CGRect(x: 32, y: 45, width: 400, height: 200))
        window.contentView!.addSubview(host)
        let recorder = OriginHarness()
        host.addSubview(recorder.overlayView)
        let origin = recorder.dictationButtonOrigin()!
        let expected = window.convertToScreen(host.convert(CGRect(x: 100, y: 40, width: 60, height: 60), to: nil))
        XCTAssertEqual(origin.screenFrame, expected)
        let otherWindow = makeWindow()
        defer { otherWindow.close() }
        otherWindow.setFrameOrigin(CGPoint(x: 250, y: 300))
        let received = otherWindow.convertFromScreen(origin.screenFrame)
        XCTAssertEqual(otherWindow.convertToScreen(received), expected)
    }

    func testLiveButtonFliesFromTheRecorderAndMorphsFromCircleToCapsule() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        let window = makeWindow()
        defer { window.close() }
        let button = FlightButton(frame: CGRect(x: 450, y: 20, width: 40, height: 40))
        window.contentView!.addSubview(button)
        let targetFrame = button.send.frame
        let layer = button.send.layer!
        let targetPosition = layer.position
        let source = CGRect(x: -70, y: 15, width: 60, height: 60)
        let screenFrame = window.convertToScreen(button.convert(source, to: nil))
        let bitmap = CGContext(data: nil, width: 30, height: 30, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        button.animateDictationTransition(from: ChatDictationButtonOrigin(screenFrame: screenFrame, icon: bitmap.makeImage()))
        let group = try XCTUnwrap(layer.animation(forKey: "dictationFlight") as? CAAnimationGroup)
        let animations = group.animations as! [CASpringAnimation]
        XCTAssertEqual(animations.map(\.keyPath), ["position", "bounds", "cornerRadius"])
        let position = animations[0]
        let startPosition = (position.fromValue as! NSValue).pointValue
        XCTAssertEqual(startPosition.x + targetPosition.x, source.minX + source.width * layer.anchorPoint.x, accuracy: 0.001)
        XCTAssertEqual(startPosition.y + targetPosition.y, source.minY + source.height * layer.anchorPoint.y, accuracy: 0.001)
        XCTAssertTrue(position.isAdditive)
        XCTAssertEqual((position.toValue as! NSValue).pointValue, .zero)
        XCTAssertEqual((animations[1].fromValue as! NSValue).rectValue.size, source.size)
        XCTAssertEqual((animations[1].toValue as! NSValue).rectValue.size, CGSize(width: 40, height: 32))
        XCTAssertEqual(animations[2].fromValue as? CGFloat, 30)
        XCTAssertEqual(animations[2].toValue as? CGFloat, 16)
        XCTAssertTrue(animations.allSatisfy { $0.duration == group.duration })
        XCTAssertNotNil(button.dictationTransitionIcon)
        XCTAssertNotNil(button.dictationWaveform.layer?.animation(forKey: "dictationReveal"))
        let bars = button.dictationWaveform.layer!.sublayers!.first as! CAShapeLayer
        let quiet = bars.path!.boundingBoxOfPath.height
        for _ in 0 ..< 12 { button.dictationWaveform.updateLevel(1) }
        XCTAssertGreaterThan(bars.path!.boundingBoxOfPath.height, quiet)
        XCTAssertEqual(button.send.frame, targetFrame)
        XCTAssertEqual(layer.position, targetPosition)
        button.frame.origin.y += 30
        XCTAssertNotNil(layer.animation(forKey: "dictationFlight"))
        button.stop()
        XCTAssertNil(layer.animation(forKey: "dictationFlight"))
        XCTAssertNil(button.dictationWaveform.layer!.animation(forKey: "dictationReveal"))
        XCTAssertNil(button.dictationTransitionIcon)
        XCTAssertEqual(button.send.frame, targetFrame)
    }

    func testLiteModeAndInactiveDictationSkipTheFlight() {
        let window = makeWindow()
        defer { window.close() }
        let button = FlightButton(frame: CGRect(x: 450, y: 20, width: 40, height: 40))
        window.contentView!.addSubview(button)
        let origin = ChatDictationButtonOrigin(screenFrame: CGRect(x: 100, y: 200, width: 60, height: 60), icon: nil)
        button.chatInteraction.context.animationsDisabled = true
        button.animateDictationTransition(from: origin)
        XCTAssertNil(button.send.layer!.animation(forKey: "dictationFlight"))
        button.chatInteraction.context.animationsDisabled = false
        button.isDictating = false
        button.animateDictationTransition(from: origin)
        XCTAssertNil(button.send.layer!.animation(forKey: "dictationFlight"))
    }

    func testDetachingDuringFlightRemovesItsAnimations() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        let window = makeWindow()
        defer { window.close() }
        let button = FlightButton(frame: CGRect(x: 450, y: 20, width: 40, height: 40))
        window.contentView!.addSubview(button)
        button.animateDictationTransition(from: ChatDictationButtonOrigin(screenFrame: CGRect(x: 100, y: 200, width: 60, height: 60), icon: nil))
        XCTAssertNotNil(button.send.layer!.animation(forKey: "dictationFlight"))
        button.removeFromSuperview()
        XCTAssertNil(button.send.layer!.animation(forKey: "dictationFlight"))
        XCTAssertNil(button.dictationWaveform.layer!.animation(forKey: "dictationReveal"))
    }
}
