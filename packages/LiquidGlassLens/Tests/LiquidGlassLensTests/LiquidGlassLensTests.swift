import AppKit
import XCTest
@testable import LiquidGlassLens

final class LiquidGlassLensTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func tearDown() {
        for window in windows {
            window.close()
        }
        windows.removeAll()
        super.tearDown()
    }

    private func makeLens() throws -> LiquidGlassLensView {
        _ = NSApplication.shared
        guard #available(macOS 26.0, *) else {
            throw XCTSkip("Native glass requires macOS 26")
        }
        let lens = try XCTUnwrap(LiquidGlassLensView.make())
        lens.frame = CGRect(x: 0, y: 0, width: 333, height: 48)
        let window = NSWindow(contentRect: lens.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = lens
        windows.append(window)
        lens.layoutSubtreeIfNeeded()
        return lens
    }

    private func addContent(to lens: LiquidGlassLensView) -> NSView {
        let source = NSView(frame: CGRect(x: 4, y: 4, width: 80, height: 40))
        source.wantsLayer = true
        source.layer?.backgroundColor = NSColor.systemBlue.cgColor
        lens.contentView.addSubview(source)
        return source
    }

    private func update(_ lens: LiquidGlassLensView, progress: CGFloat, frame: CGRect = CGRect(x: -6, y: -4, width: 100, height: 56), animation: LiquidGlassLensAnimation = .immediate, restingBlurRadius: CGFloat = 0, restingTintColor: NSColor? = nil) {
        lens.update(lensFrame: frame, interactionProgress: progress, appearance: NSAppearance(named: .aqua)!, backingScale: 2, animation: animation, restingBlurRadius: restingBlurRadius, restingTintColor: restingTintColor)
        lens.layoutSubtreeIfNeeded()
        lens.window?.displayIfNeeded()
    }

    private func portalSources(_ layer: CALayer) -> [CALayer] {
        var result: [CALayer] = []
        if layer.responds(to: NSSelectorFromString("sourceLayer")), let source = layer.value(forKey: "sourceLayer") as? CALayer {
            result.append(source)
        }
        for child in layer.sublayers ?? [] {
            result += portalSources(child)
        }
        return result
    }

    func testRestingRendererKeepsNoTemporarySurfaces() throws {
        let lens = try makeLens()
        let source = addContent(to: lens)
        update(lens, progress: 0)
        XCTAssertFalse(lens.hasActiveSurface)
        XCTAssertEqual(lens.activePortalCount, 0)
        XCTAssertTrue(source.superview === lens.contentView)
        XCTAssertNil(lens.subviews.first?.layer?.mask)
    }

    func testRestingBackdropBlursBelowContentWithoutCreatingPortals() throws {
        let lens = try makeLens()
        let source = addContent(to: lens)
        let frame = CGRect(x: 4, y: 4, width: 80, height: 40)
        let tint = NSColor.black.withAlphaComponent(0.08)
        update(lens, progress: 0, frame: frame, restingBlurRadius: 16, restingTintColor: tint)
        let background = try XCTUnwrap(lens.subviews.first?.layer?.sublayers?.first)
        let backdrop = try XCTUnwrap(background.sublayers?.first)
        XCTAssertEqual(background.name, "lensRestingBackground")
        XCTAssertEqual(background.frame, frame)
        XCTAssertEqual(background.cornerRadius, 20)
        XCTAssertTrue(background.masksToBounds)
        XCTAssertEqual(background.opacity, 1)
        XCTAssertEqual(backdrop.value(forKeyPath: "filters.lensRestingBlur.inputRadius") as? CGFloat, 16)
        XCTAssertEqual(background.sublayers?.last?.backgroundColor, tint.cgColor)
        XCTAssertFalse(lens.hasActiveSurface)
        XCTAssertEqual(lens.activePortalCount, 0)
        XCTAssertNil(source.layer?.filters)
    }

    func testRestingBackdropFadesOnLiftAndReturnsAfterRelease() throws {
        let lens = try makeLens()
        _ = addContent(to: lens)
        let restingFrame = CGRect(x: 4, y: 4, width: 80, height: 40)
        update(lens, progress: 0, frame: restingFrame, restingBlurRadius: 16)
        let background = try XCTUnwrap(lens.subviews.first?.layer?.sublayers?.first)
        update(lens, progress: 1, animation: .spring(duration: 0.05), restingBlurRadius: 16)
        XCTAssertEqual(background.opacity, 0)
        XCTAssertEqual((background.animation(forKey: "opacity") as? CABasicAnimation)?.fromValue as? Float, 1)
        update(lens, progress: 1, frame: CGRect(x: 130, y: -4, width: 100, height: 56), restingBlurRadius: 16)
        XCTAssertEqual(background.opacity, 0)
        XCTAssertNil(background.animation(forKey: "opacity"))
        update(lens, progress: 0, frame: restingFrame, animation: .spring(duration: 0.01), restingBlurRadius: 16)
        XCTAssertEqual(background.opacity, 1)
        XCTAssertEqual((background.animation(forKey: "opacity") as? CABasicAnimation)?.toValue as? Float, 1)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertFalse(lens.hasActiveSurface)
        XCTAssertTrue(background.superlayer === lens.subviews.first?.layer)
        XCTAssertEqual(background.frame, restingFrame)
    }

    func testRestingBackdropUpdatesItsTintAndResetsWithoutLosingContent() throws {
        let lens = try makeLens()
        let source = addContent(to: lens)
        update(lens, progress: 0, restingBlurRadius: 16, restingTintColor: .red)
        let background = try XCTUnwrap(lens.subviews.first?.layer?.sublayers?.first)
        update(lens, progress: 0, restingBlurRadius: 16, restingTintColor: .blue)
        XCTAssertEqual(background.sublayers?.last?.backgroundColor, NSColor.blue.cgColor)
        lens.reset()
        XCTAssertNil(background.superlayer)
        XCTAssertTrue(source.superview === lens.contentView)
        update(lens, progress: 0, restingBlurRadius: 16)
        XCTAssertEqual(lens.subviews.first?.layer?.sublayers?.first?.name, "lensRestingBackground")
        update(lens, progress: 0, restingBlurRadius: .nan)
        XCTAssertTrue(lens.subviews.first?.layer?.sublayers?.isEmpty ?? true)
    }

    func testInteractionUsesLiveSourcesAndResetPreservesTheOriginalViews() throws {
        let lens = try makeLens()
        let source = addContent(to: lens)
        update(lens, progress: 1)
        XCTAssertTrue(lens.hasActiveSurface)
        XCTAssertEqual(lens.activePortalCount, 1)
        XCTAssertTrue(portalSources(try XCTUnwrap(lens.layer)).contains { $0 === source.layer })
        source.layer?.backgroundColor = NSColor.systemRed.cgColor
        XCTAssertTrue(portalSources(try XCTUnwrap(lens.layer)).contains { $0 === source.layer })
        lens.reset()
        XCTAssertFalse(lens.hasActiveSurface)
        XCTAssertTrue(portalSources(try XCTUnwrap(lens.layer)).isEmpty)
        XCTAssertTrue(source.superview === lens.contentView)
        XCTAssertNil(lens.subviews.first?.layer?.mask)
    }

    func testSourceMaskRemovesOnlyTheAreaDrawnThroughTheLens() throws {
        let lens = try makeLens()
        _ = addContent(to: lens)
        update(lens, progress: 1)
        let mask = try XCTUnwrap(lens.subviews[2].layer?.sublayers?.first?.mask as? CAShapeLayer)
        let path = try XCTUnwrap(mask.path)
        XCTAssertFalse(path.contains(CGPoint(x: 40, y: 24), using: .evenOdd))
        XCTAssertTrue(path.contains(CGPoint(x: 180, y: 24), using: .evenOdd))
    }

    func testRemovedContentReleasesItsPortalAndReplacementStaysLive() throws {
        let lens = try makeLens()
        let original = addContent(to: lens)
        update(lens, progress: 1)
        original.removeFromSuperview()
        let replacement = addContent(to: lens)
        update(lens, progress: 1)
        let sources = portalSources(try XCTUnwrap(lens.layer))
        XCTAssertEqual(lens.activePortalCount, 1)
        XCTAssertFalse(sources.contains { $0 === original.layer })
        XCTAssertTrue(sources.contains { $0 === replacement.layer })
    }

    func testRedundantLayoutPreservesTheRunningTransitionAndReleaseCleansUp() throws {
        let lens = try makeLens()
        _ = addContent(to: lens)
        update(lens, progress: 0, frame: CGRect(x: 4, y: 4, width: 80, height: 40))
        update(lens, progress: 1, animation: .spring(duration: 0.05))
        let surface = try XCTUnwrap(lens.subviews.last?.layer?.sublayers?.first)
        let animation = try XCTUnwrap(surface.animation(forKey: "position"))
        update(lens, progress: 1)
        XCTAssertTrue(try XCTUnwrap(surface.animation(forKey: "position")).isEqual(animation))
        update(lens, progress: 0, frame: CGRect(x: 4, y: 4, width: 80, height: 40), animation: .spring(duration: 0.01))
        let deadline = Date(timeIntervalSinceNow: 1)
        while lens.hasActiveSurface && Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        }
        XCTAssertFalse(lens.hasActiveSurface)
        XCTAssertEqual(lens.activePortalCount, 0)
    }

    func testInvalidGeometryClearsEffectsWithoutLosingContent() throws {
        let lens = try makeLens()
        let source = addContent(to: lens)
        update(lens, progress: 1)
        update(lens, progress: .nan)
        XCTAssertFalse(lens.hasActiveSurface)
        XCTAssertTrue(source.superview === lens.contentView)
    }

    func testPortalCopiesUseTheSameCenterAsTheirSource() throws {
        let lens = try makeLens()
        let source = addContent(to: lens)
        update(lens, progress: 1)
        let portal = try XCTUnwrap(lens.subviews[2].layer?.sublayers?.first?.sublayers?.first)
        XCTAssertEqual(portal.anchorPoint, CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(portal.position, CGPoint(x: source.frame.midX, y: source.frame.midY))
        XCTAssertEqual(portal.bounds, source.bounds)
    }

    func testNewPressSurvivesThePreviousReleaseCleanup() throws {
        let lens = try makeLens()
        _ = addContent(to: lens)
        update(lens, progress: 1)
        update(lens, progress: 0, animation: .spring(duration: 0.01))
        update(lens, progress: 1, animation: .spring(duration: 0.05))
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
        XCTAssertTrue(lens.hasActiveSurface)
        XCTAssertEqual(lens.activePortalCount, 1)
        update(lens, progress: 0)
        XCTAssertFalse(lens.hasActiveSurface)
    }

    func testDraggingDuringLiftKeepsTheSurfaceAndContentMaskInSync() throws {
        let lens = try makeLens()
        _ = addContent(to: lens)
        update(lens, progress: 0, frame: CGRect(x: 4, y: 4, width: 80, height: 40))
        update(lens, progress: 1, animation: .spring(duration: 0.4))
        let surface = try XCTUnwrap(lens.subviews.last?.layer?.sublayers?.first)
        XCTAssertNotNil(surface.animation(forKey: "bounds"))
        update(lens, progress: 1, frame: CGRect(x: 130, y: -4, width: 100, height: 56))
        XCTAssertNil(surface.animation(forKey: "bounds"))
        XCTAssertNil(surface.animation(forKey: "position"))
        let mask = try XCTUnwrap(lens.subviews[2].layer?.sublayers?.first?.mask as? CAShapeLayer)
        XCTAssertNil(mask.animation(forKey: "path"))
        XCTAssertEqual(surface.frame, CGRect(x: 130, y: -4, width: 100, height: 56))
    }
}
