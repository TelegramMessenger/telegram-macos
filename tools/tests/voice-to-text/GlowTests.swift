import Cocoa
import QuartzCore
import XCTest

enum LiteFeature { case blur, animations }
protocol AccountContextProtocol {
    func isLite(_ feature: LiteFeature) -> Bool
}
struct GlowContext: AccountContextProtocol {
    var animationsDisabled = true
    var blurDisabled = true
    func isLite(_ feature: LiteFeature) -> Bool { feature == .animations ? animationsDisabled : blurDisabled }
}
struct PresentationTheme {
    struct Colors {
        var accent = NSColor.systemBlue
        var isDark = false
    }
    var colors = Colors()
}
let theme = PresentationTheme()

class View: NSView {
    var isEventLess = false
    required override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }
    func updateLocalizationAndTheme(theme: PresentationTheme) {}
}

final class ConstantDisplayLinkAnimator {
    enum FrameRate { case fps(Int) }
    static var activeCount = 0
    static weak var last: ConstantDisplayLinkAnimator?
    private var update: ((CGFloat) -> Void)?
    var isPaused = true {
        didSet {
            if oldValue != isPaused { Self.activeCount += isPaused ? -1 : 1 }
        }
    }
    init(framesPerSecond: FrameRate, update: @escaping (CGFloat) -> Void) {
        self.update = update
        Self.last = self
    }
    func tick(_ duration: CGFloat) { if !isPaused { update?(duration) } }
    func invalidate() { isPaused = true; update = nil }
    deinit { if !isPaused { Self.activeCount -= 1 } }
}

extension CGSize {
    var bounds: CGRect { CGRect(origin: .zero, size: self) }
}
extension CALayer {
    func animateAlpha(from: CGFloat, to: CGFloat, duration: Double, completion: @escaping (Bool) -> Void = { _ in }) { completion(true) }
}

__GLOW__

final class NativeComposerAuraTests: XCTestCase {
    func testGlowSurroundsTheFieldAndMasksOutTheEditorAndControls() {
        let view = TestedGlowView(context: GlowContext())
        let frame = CGRect(x: 72, y: 12, width: 400, height: 40)
        view.frame = frame
        view.updateLayout(size: frame.size, transition: .immediate)
        view.setListening(true, animated: false)
        view.updateLevel(1)
        XCTAssertTrue(view.isEventLess)
        XCTAssertTrue(view.subviews.isEmpty)
        XCTAssertEqual(view.frame, frame)
        XCTAssertTrue(CATransform3DIsIdentity(view.layer!.transform))
        let aura = view.layer!.sublayers!.first!
        XCTAssertLessThan(aura.frame.minX, 0)
        XCTAssertGreaterThan(aura.frame.maxX, frame.width)
        let mask = aura.mask as! CAShapeLayer
        let center = CGPoint(x: aura.bounds.midX, y: aura.bounds.midY)
        XCTAssertEqual(mask.fillRule, .evenOdd)
        XCTAssertFalse(mask.path!.contains(center, using: .evenOdd))
        XCTAssertTrue(mask.path!.contains(CGPoint(x: aura.bounds.midX, y: 12), using: .evenOdd))
        let gradients = aura.sublayers!.compactMap { $0 as? CAGradientLayer }
        XCTAssertEqual(gradients.count, 10)
        for gradient in gradients {
            let stroke = gradient.mask as! CAShapeLayer
            XCTAssertNil(stroke.fillColor)
            XCTAssertEqual(stroke.frame, aura.bounds)
            XCTAssertGreaterThan(stroke.lineWidth, 0)
        }
    }

    func testBrightBorderStaysOnTheFieldEdgeDuringSpeechAndResize() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 700, height: 220), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = TestedGlowView(context: GlowContext(animationsDisabled: false, blurDisabled: false))
        window.contentView!.addSubview(view)
        view.setListening(true, animated: false)
        for size in [CGSize(width: 400, height: 40), CGSize(width: 600, height: 120)] {
            view.frame = CGRect(origin: CGPoint(x: 30, y: 30), size: size)
            view.updateLayout(size: size, transition: .immediate)
            let aura = view.layer!.sublayers!.first!
            let ribbon = aura.sublayers![8].mask as! CAShapeLayer
            let field = CGRect(x: ChatDictationAura.padding, y: ChatDictationAura.padding, width: size.width, height: size.height)
            let expected = CGPath(roundedRect: field, cornerWidth: 20, cornerHeight: 20, transform: nil)
            for level: CGFloat in [0, 1, 0] {
                view.updateLevel(level)
                for _ in 0 ..< 15 { ConstantDisplayLinkAnimator.last?.tick(1 / 30) }
                XCTAssertEqual(ribbon.path, expected)
                for glow in aura.sublayers![0 ..< 4] {
                    XCTAssertEqual((glow.mask as! CAShapeLayer).path, expected)
                }
                let visibleBorder = view.convert(ribbon.path!.boundingBoxOfPath.offsetBy(dx: aura.frame.minX, dy: aura.frame.minY), to: window.contentView!)
                XCTAssertEqual(visibleBorder, view.frame)
            }
        }
    }

    func testThemeChangesRecolorTheWholeAura() {
        let view = TestedGlowView(context: GlowContext())
        for dark in [false, true] {
            var customTheme = PresentationTheme()
            customTheme.colors.accent = NSColor(calibratedRed: 0.8, green: 0.2, blue: 0.4, alpha: 1)
            customTheme.colors.isDark = dark
            view.updateLocalizationAndTheme(theme: customTheme)
            let gradients = view.layer!.sublayers!.first!.sublayers!.compactMap { $0 as? CAGradientLayer }
            for gradient in gradients {
                let colors = gradient.colors as! [CGColor]
                XCTAssertEqual(colors[2], customTheme.colors.accent.usingColorSpace(.deviceRGB)!.cgColor)
                XCTAssertEqual(colors.first, colors.last)
                XCTAssertNotEqual(colors[0], colors[3])
            }
        }
    }

    func testVoiceEmitsOutwardRipplesThatFadeAfterSilence() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 100), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = TestedGlowView(context: GlowContext(animationsDisabled: false, blurDisabled: false))
        view.frame = CGRect(x: 0, y: 24, width: 400, height: 40)
        window.contentView!.addSubview(view)
        view.updateLayout(size: view.frame.size, transition: .immediate)
        view.setListening(true, animated: false)
        let ripples = Array(view.layer!.sublayers!.first!.sublayers![4 ..< 8])
        for _ in 0 ..< 20 { ConstantDisplayLinkAnimator.last?.tick(1 / 30) }
        XCTAssertTrue(ripples.allSatisfy { $0.opacity == 0 })
        view.updateLevel(1)
        for _ in 0 ..< 8 { ConstantDisplayLinkAnimator.last?.tick(1 / 30) }
        XCTAssertGreaterThan(ripples[0].opacity, 0)
        let firstBounds = (ripples[0].mask as! CAShapeLayer).path!.boundingBoxOfPath
        for _ in 0 ..< 6 { ConstantDisplayLinkAnimator.last?.tick(1 / 30) }
        let laterBounds = (ripples[0].mask as! CAShapeLayer).path!.boundingBoxOfPath
        XCTAssertLessThan(laterBounds.minY, firstBounds.minY)
        view.updateLevel(0)
        for _ in 0 ..< 50 { ConstantDisplayLinkAnimator.last?.tick(1 / 30) }
        XCTAssertTrue(ripples.allSatisfy { $0.opacity == 0 })
        view.setListening(false, animated: false)
        XCTAssertTrue(ripples.allSatisfy { $0.opacity == 0 })
    }

    func testLiteModeUsesAStaticRimWithoutBlurOrAFrameLoop() {
        let baseline = ConstantDisplayLinkAnimator.activeCount
        let view = TestedGlowView(context: GlowContext())
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 40)
        view.updateLayout(size: view.frame.size, transition: .immediate)
        view.setListening(true, animated: true)
        view.updateLevel(1)
        let gradients = view.layer!.sublayers!.first!.sublayers!
        XCTAssertTrue(gradients.first!.isHidden)
        XCTAssertNil(gradients.first!.filters)
        XCTAssertTrue(gradients.allSatisfy { $0.animationKeys() == nil })
        XCTAssertEqual(ConstantDisplayLinkAnimator.activeCount, baseline)
        view.animateOut(completion: {})
        XCTAssertEqual(view.layer?.opacity, 0)
    }

    func testVoiceExpandsTheRibbonAndDetachStopsItsFrameLoopAndColorFlow() throws {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { throw XCTSkip("Reduced motion is enabled") }
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 400, height: 100), styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let baseline = ConstantDisplayLinkAnimator.activeCount
        let view = TestedGlowView(context: GlowContext(animationsDisabled: false, blurDisabled: false))
        view.frame = CGRect(x: 0, y: 24, width: 400, height: 40)
        window.contentView!.addSubview(view)
        view.updateLayout(size: view.frame.size, transition: .immediate)
        view.setListening(true, animated: false)
        let gradients = view.layer!.sublayers!.first!.sublayers!
        let glow = gradients.first!
        let mask = glow.mask as! CAShapeLayer
        let width = mask.lineWidth
        let quiet = mask.path!.boundingBoxOfPath
        XCTAssertEqual(ConstantDisplayLinkAnimator.activeCount, baseline + 1)
        XCTAssertTrue(gradients.allSatisfy { $0.animation(forKey: "auroraFlow") != nil })
        view.updateLevel(1)
        for _ in 0 ..< 12 { ConstantDisplayLinkAnimator.last?.tick(1 / 30) }
        XCTAssertGreaterThan(mask.lineWidth, width)
        XCTAssertEqual(mask.path!.boundingBoxOfPath, quiet)
        view.removeFromSuperview()
        XCTAssertEqual(ConstantDisplayLinkAnimator.activeCount, baseline)
        XCTAssertTrue(gradients.allSatisfy { $0.animationKeys() == nil })
    }
}

final class DictationAuraGeometryTests: XCTestCase {
    func testPulseExpandsFromTheEdgeAndDissolvesToTransparency() {
        let pulse = ChatDictationAuraPulse(born: 3, energy: 1)
        XCTAssertEqual(pulse.expansion(at: 3), 0)
        XCTAssertEqual(pulse.opacity(at: 3), 0)
        XCTAssertGreaterThan(pulse.opacity(at: 3.2), 0.5)
        XCTAssertGreaterThan(pulse.expansion(at: 3.8), pulse.expansion(at: 3.2))
        XCTAssertEqual(pulse.opacity(at: 3 + ChatDictationAuraPulse.lifetime), 0, accuracy: 0.00001)
        XCTAssertEqual(pulse.expansion(at: 6), 20)
        let field = CGRect(x: 30, y: 30, width: 600, height: 44)
        for frame in 0 ... 40 {
            let time = 3 + Double(frame) / 30
            let progress = pulse.progress(at: time)
            let path = ChatDictationAura.path(around: field, level: pulse.energy * (1 - progress) * 0.35, time: time, band: pulse.energy * 0.8, motion: true, expansion: pulse.expansion(at: time))
            XCTAssertTrue(field.insetBy(dx: -ChatDictationAura.padding, dy: -ChatDictationAura.padding).contains(path.boundingBoxOfPath))
        }
    }

    func testSpeechExpandsTheWaveOnAllFourSides() {
        let field = CGRect(x: 24, y: 24, width: 600, height: 44)
        let quiet = ChatDictationAura.path(around: field, level: 0, time: 1, band: 0, motion: true).boundingBoxOfPath
        let loud = ChatDictationAura.path(around: field, level: 1, time: 1, band: 0, motion: true).boundingBoxOfPath
        XCTAssertLessThan(loud.minX, quiet.minX)
        XCTAssertLessThan(loud.minY, quiet.minY)
        XCTAssertGreaterThan(loud.maxX, quiet.maxX)
        XCTAssertGreaterThan(loud.maxY, quiet.maxY)
    }

    func testWavesAreClosedAndTheirContourChangesWithTime() {
        let field = CGRect(x: 24, y: 24, width: 400, height: 40)
        func firstPoint(_ time: Double) -> CGPoint {
            var point = CGPoint.zero
            var closed = false
            ChatDictationAura.path(around: field, level: 1, time: time, band: 0, motion: true).applyWithBlock { element in
                if element.pointee.type == .moveToPoint { point = element.pointee.points[0] }
                closed = element.pointee.type == .closeSubpath
            }
            XCTAssertTrue(closed)
            return point
        }
        XCTAssertNotEqual(firstPoint(0), firstPoint(1))
    }

    func testWaveGeometryStaysFiniteAndInsideItsReservedPadding() {
        for size in [CGSize(width: 1, height: 1), CGSize(width: 100, height: 40), CGSize(width: 1700, height: 140)] {
            let field = CGRect(origin: CGPoint(x: 24, y: 24), size: size)
            for level: CGFloat in [0, 1, .nan] {
                let path = ChatDictationAura.path(around: field, level: level, time: 2, band: 1, motion: true)
                let rect = path.boundingBoxOfPath
                XCTAssertTrue(rect.minX.isFinite && rect.minY.isFinite && rect.width.isFinite && rect.height.isFinite)
                XCTAssertTrue(field.insetBy(dx: -ChatDictationAura.padding, dy: -ChatDictationAura.padding).contains(rect))
            }
        }
    }

    func testReducedMotionKeepsTheContourStillAsVoiceAndTimeChange() {
        let field = CGRect(x: 24, y: 24, width: 400, height: 40)
        let quiet = ChatDictationAura.path(around: field, level: 0, time: 0, band: 0, motion: false)
        let loud = ChatDictationAura.path(around: field, level: 1, time: 8, band: 1, motion: false)
        XCTAssertEqual(quiet.boundingBoxOfPath, loud.boundingBoxOfPath)
    }
}
