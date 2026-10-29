import XCTest
import AppKit
@testable import TGUIKit

final class PieChartTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
        PieChartView.reduceMotion = { false }
    }

    override func tearDown() {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
            window.close()
        }
        windows.removeAll()
        PieChartView.reduceMotion = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        System.updateScaleFactor(2)
        super.tearDown()
    }

    func testParticlesMatchIOSDistributionAndAdvanceByFrameDuration() {
        let set = PieChartParticleSet()
        XCTAssertEqual(set.particles.count, 24)
        XCTAssertEqual(Set(set.particles.map { $0.trackIndex }), Set(0 ..< 24))
        let initial = set.particles
        let duration: CGFloat = 1.0 / 120.0
        set.update(deltaTime: duration)
        for (before, after) in zip(initial, set.particles) {
            XCTAssertTrue((20 ..< 40).contains(before.velocity))
            XCTAssertTrue((0.1 ..< 0.4).contains(before.alpha))
            XCTAssertTrue((0.11 ... 0.22).contains(before.scale))
            XCTAssertTrue((42 ... 105).contains(hypot(before.position.x - 100, before.position.y - 100)))
            XCTAssertEqual(after.position.x, before.position.x + before.direction.x * before.velocity * duration, accuracy: 0.00001)
            XCTAssertEqual(after.position.y, before.position.y + before.direction.y * before.velocity * duration, accuracy: 0.00001)
        }
    }

    func testParticlesRecycleOntoEveryTrackAtTheIOSStartingRadius() {
        let set = PieChartParticleSet()
        set.update(deltaTime: 100)
        XCTAssertEqual(Set(set.particles.map { $0.trackIndex }), Set(0 ..< 24))
        for particle in set.particles {
            XCTAssertEqual(hypot(particle.position.x - 100, particle.position.y - 100), 42, accuracy: 0.00001)
        }
    }

    func testSlicesMaskParticlesOutOfTheCenterAndKeepLabelsAboveThem() throws {
        let chart = makeChart()
        let sections = try sections(in: chart)
        XCTAssertEqual(sections.count, 2)
        for section in sections {
            let mask = try XCTUnwrap(section.mask as? CAShapeLayer)
            let path = try XCTUnwrap(mask.path)
            XCTAssertFalse(path.contains(CGPoint(x: 100, y: 100)))
            XCTAssertFalse(path.contains(CGPoint(x: 0, y: 0)))
            let layers = try XCTUnwrap(section.sublayers)
            let gradient = try XCTUnwrap(layers.first as? CAGradientLayer)
            XCTAssertEqual(gradient.type, .radial)
            XCTAssertEqual(gradient.locations, [0.5, 0.65, 0.75, 0.85, 1.0])
            XCTAssertEqual(layers.count, 27)
            for particle in layers.dropFirst().prefix(24) {
                XCTAssertEqual(particle.bounds.size, NSMakeSize(72, 72))
                XCTAssertTrue((0.1 ..< 0.4).contains(particle.opacity))
            }
            XCTAssertNotNil(layers.last?.contents)
        }
        XCTAssertNil(chart.selectedItemIndex(at: NSMakePoint(200, 100)))
        XCTAssertNil(chart.selectedItemIndex(at: .zero))
    }

    func testEmptyChartRemovesSlicesWithoutInvalidGeometry() throws {
        let chart = makeChart()
        chart.update(items: [], dynamicText: "", animated: false)
        XCTAssertEqual(try sections(in: chart).count, 0)
    }

    func testParticlesKeepMovingAtRestAndStopWhenHiddenOrMotionIsReduced() throws {
        let chart = makeChart()
        let window = NSWindow(contentRect: chart.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = chart
        windows.append(window)
        window.orderFront(nil)
        chart.layoutSubtreeIfNeeded()
        XCTAssertTrue(chart.isAnimatingParticles)
        let particle = try XCTUnwrap(try sections(in: chart).first?.sublayers?.dropFirst().first)
        let initial = particle.position
        advanceRunLoop()
        XCTAssertNotEqual(particle.position, initial)
        chart.isHidden = true
        XCTAssertFalse(chart.isAnimatingParticles)
        let hidden = particle.position
        advanceRunLoop()
        XCTAssertEqual(particle.position, hidden)
        chart.isHidden = false
        PieChartView.reduceMotion = { true }
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        XCTAssertFalse(chart.isAnimatingParticles)
        let reduced = particle.position
        advanceRunLoop()
        XCTAssertEqual(particle.position, reduced)
    }

    func testScrollingChartOffscreenStopsItsParticles() throws {
        let chart = makeChart()
        let scrollView = NSScrollView(frame: NSMakeRect(0, 0, 400, 200))
        scrollView.contentView.postsBoundsChangedNotifications = true
        let document = View(frame: NSMakeRect(0, 0, 400, 800))
        document.addSubview(chart)
        scrollView.documentView = document
        let window = NSWindow(contentRect: scrollView.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scrollView
        windows.append(window)
        window.orderFront(nil)
        chart.layoutSubtreeIfNeeded()
        XCTAssertTrue(chart.isAnimatingParticles)
        scrollView.contentView.scroll(to: NSMakePoint(0, 400))
        XCTAssertFalse(chart.isAnimatingParticles)
        let particle = try XCTUnwrap(try sections(in: chart).first?.sublayers?.dropFirst().first)
        let position = particle.position
        advanceRunLoop()
        XCTAssertEqual(particle.position, position)
    }

    func testFirstNonanimatedUpdateStillMorphsFromEqualSlices() throws {
        let chart = makeChart()
        let section = try XCTUnwrap(try sections(in: chart).first)
        let mask = try XCTUnwrap(section.mask as? CAShapeLayer)
        let initial = try XCTUnwrap(mask.path)
        let window = NSWindow(contentRect: chart.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = chart
        windows.append(window)
        window.orderFront(nil)
        advanceRunLoop()
        XCTAssertNotEqual(mask.path, initial)
    }

    func testReduceMotionSkipsTheIntroMorph() throws {
        PieChartView.reduceMotion = { true }
        let chart = makeChart()
        let section = try XCTUnwrap(try sections(in: chart).first)
        let mask = try XCTUnwrap(section.mask as? CAShapeLayer)
        let initial = try XCTUnwrap(mask.path)
        let window = NSWindow(contentRect: chart.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = chart
        windows.append(window)
        window.orderFront(nil)
        advanceRunLoop()
        XCTAssertEqual(mask.path, initial)
    }

    private func makeChart() -> PieChartView {
        let chart = PieChartView(frame: NSMakeRect(0, 0, 400, 200), presentation: .init(strokeColor: .clear, strokeSize: 1, bgColor: .clear, totalTextColor: .black, itemTextColor: .white))
        let particle = testImage(NSMakeSize(144, 144))
        chart.update(items: [
            .init(id: 0, index: 0, count: 60, color: .systemBlue, badge: nil, particle: particle),
            .init(id: 1, index: 1, count: 40, color: .systemGreen, badge: nil, particle: particle)
        ], dynamicText: "100 MB", animated: false)
        return chart
    }

    private func sections(in chart: PieChartView) throws -> [CALayer] {
        let root = try XCTUnwrap(chart.layer?.sublayers?.first)
        return root.sublayers ?? []
    }

    private func advanceRunLoop() {
        let finished = expectation(description: "Display link advanced")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            finished.fulfill()
        }
        wait(for: [finished], timeout: 1)
    }
}
