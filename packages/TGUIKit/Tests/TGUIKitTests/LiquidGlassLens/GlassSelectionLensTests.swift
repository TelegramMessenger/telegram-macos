import AppKit
import XCTest
@testable import TGUIKit

final class GlassSelectionLensTests: XCTestCase {
    private var windows: [NSWindow] = []
    private let first = CGRect(x: 3, y: 3, width: 114, height: 34)
    private let second = CGRect(x: 123, y: 3, width: 114, height: 34)
    private let appearance = NSAppearance(named: .darkAqua)!

    override func tearDown() {
        for window in windows {
            window.close()
        }
        windows.removeAll()
        super.tearDown()
    }

    private func makeHost() -> (host: View, selection: View, labels: [View]) {
        _ = NSApplication.shared
        let host = View(frame: CGRect(x: 0, y: 0, width: 240, height: 40))
        let window = NSWindow(contentRect: host.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        windows.append(window)
        let selection = View(frame: first)
        selection.backgroundColor = NSColor.white.withAlphaComponent(0.1)
        host.addSubview(selection)
        let labels = [View(frame: CGRect(x: 30, y: 10, width: 60, height: 20)), View(frame: CGRect(x: 150, y: 10, width: 60, height: 20))]
        for label in labels {
            host.addSubview(label)
        }
        return (host, selection, labels)
    }

    private func makeLens(reduceMotion: Bool = false) throws -> (lens: GlassSelectionLens, host: View, selection: View, labels: [View]) {
        guard System.liquidGlassAvailable, LiquidGlassLensView.make() != nil else {
            throw XCTSkip("Liquid Glass lens requires a supported system")
        }
        let previous = System.liquidGlass
        addTeardownBlock { System.liquidGlass = previous }
        System.liquidGlass = true
        let (host, selection, labels) = makeHost()
        let lens = GlassSelectionLens(host: host, selectionView: selection)
        lens.reduceTransparency = { false }
        lens.reduceMotion = { reduceMotion }
        lens.updateMode(content: labels)
        return (lens, host, selection, labels)
    }

    private func wait(_ seconds: TimeInterval) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    func testModeMovesContentIntoTheLensAndBack() throws {
        let (lens, host, selection, labels) = try makeLens()
        let lensView = try XCTUnwrap(lens.lensView)
        XCTAssertTrue(labels.allSatisfy { $0.superview === lensView.contentView })
        XCTAssertTrue(selection.superview === host)
        XCTAssertEqual(selection.layer?.opacity, 0)
        XCTAssertFalse(lens.updateMode(content: labels))
        lens.reduceTransparency = { true }
        XCTAssertTrue(lens.updateMode(content: labels))
        XCTAssertNil(lens.lensView)
        XCTAssertNil(lensView.superview)
        XCTAssertEqual(selection.layer?.opacity, 1)
        XCTAssertTrue(labels.allSatisfy { $0.superview === host })
        XCTAssertEqual(labels.map { $0.frame }, [CGRect(x: 30, y: 10, width: 60, height: 20), CGRect(x: 150, y: 10, width: 60, height: 20)])
    }

    func testTheLensDrawsTheRestingSelection() throws {
        let (lens, _, selection, labels) = try makeLens()
        lens.update(selection: first, lifted: false, sources: labels, appearance: appearance, transition: .immediate)
        XCTAssertEqual(lens.lensView?.currentLensFrame, first)
        XCTAssertEqual(lens.lensView?.currentInteractionProgress, 0)
        XCTAssertEqual(selection.layer?.opacity, 0)
    }

    func testAClickOnAnotherTabGrowsInPlaceTravelsAndSettles() throws {
        let (lens, _, _, labels) = try makeLens()
        lens.update(selection: first, lifted: false, sources: labels, appearance: appearance, transition: .immediate)
        lens.update(selection: second, lifted: true, sources: labels, appearance: appearance, transition: .animated(duration: 0.4, curve: .spring))
        XCTAssertEqual(lens.lensView?.currentLensFrame, first.insetBy(dx: -10, dy: -8))
        XCTAssertEqual(lens.lensView?.currentInteractionProgress, 1)
        lens.update(selection: second, lifted: false, sources: labels, appearance: appearance, transition: .animated(duration: 0.4, curve: .spring))
        XCTAssertEqual(lens.lensView?.currentLensFrame, first.insetBy(dx: -10, dy: -8))
        wait(GlassSelectionLens.travelDelay + 0.05)
        XCTAssertEqual(lens.lensView?.currentLensFrame, second.insetBy(dx: -10, dy: -8))
        XCTAssertEqual(lens.lensView?.currentInteractionProgress, 1)
        XCTAssertTrue(lens.isLifted)
        wait(GlassSelectionLens.minimumLift - GlassSelectionLens.travelDelay + 0.05)
        XCTAssertFalse(lens.isLifted)
        XCTAssertEqual(lens.lensView?.currentLensFrame, second)
        XCTAssertEqual(lens.lensView?.currentInteractionProgress, 0)
    }

    func testAQuickClickOnTheSelectedTabStillLiftsBeforeSettling() throws {
        let (lens, _, _, labels) = try makeLens()
        lens.update(selection: first, lifted: false, sources: labels, appearance: appearance, transition: .immediate)
        lens.update(selection: first, lifted: true, sources: labels, appearance: appearance, transition: .animated(duration: 0.4, curve: .spring))
        lens.update(selection: first, lifted: false, sources: labels, appearance: appearance, transition: .animated(duration: 0.4, curve: .spring))
        XCTAssertEqual(lens.lensView?.currentInteractionProgress, 1)
        wait(GlassSelectionLens.minimumLift + 0.05)
        XCTAssertEqual(lens.lensView?.currentLensFrame, first)
        XCTAssertEqual(lens.lensView?.currentInteractionProgress, 0)
    }

    func testAReleaseAfterALongPressSettlesImmediately() throws {
        let (lens, _, _, labels) = try makeLens()
        var time: CFTimeInterval = 100
        lens.now = { time }
        lens.update(selection: first, lifted: false, sources: labels, appearance: appearance, transition: .immediate)
        lens.update(selection: first, lifted: true, sources: labels, appearance: appearance, transition: .immediate)
        lens.update(selection: second, lifted: true, sources: labels, appearance: appearance, transition: .immediate)
        XCTAssertEqual(lens.lensView?.currentLensFrame, second.insetBy(dx: -10, dy: -8))
        time += 1
        lens.update(selection: second, lifted: false, sources: labels, appearance: appearance, transition: .animated(duration: 0.4, curve: .spring))
        XCTAssertFalse(lens.isLifted)
        XCTAssertEqual(lens.lensView?.currentLensFrame, second)
        XCTAssertEqual(lens.lensView?.currentInteractionProgress, 0)
    }

    func testTheRestingSelectionComesBackWhenTheHostReturnsToAWindow() throws {
        let (lens, host, _, labels) = try makeLens()
        let parent = try XCTUnwrap(host.window?.contentView)
        let child = View(frame: host.bounds)
        host.window?.contentView = child
        child.addSubview(host)
        lens.update(selection: first, lifted: false, sources: labels, appearance: appearance, transition: .immediate)
        XCTAssertEqual(lens.lensView?.currentLensFrame, first)
        host.removeFromSuperview()
        XCTAssertNil(lens.lensView?.currentLensFrame)
        child.addSubview(host)
        XCTAssertEqual(lens.lensView?.currentLensFrame, first)
        XCTAssertEqual(lens.lensView?.currentInteractionProgress, 0)
        _ = parent
    }

    func testAHiddenHostKeepsItsRestingSelection() throws {
        let (lens, host, _, labels) = try makeLens()
        host.isHidden = true
        lens.update(selection: first, lifted: false, sources: labels, appearance: appearance, transition: .immediate)
        host.isHidden = false
        XCTAssertEqual(lens.lensView?.currentLensFrame, first)
    }

    func testTheRestingSelectionIsClippedButTheLiftedLensIsNot() throws {
        let (lens, _, _, labels) = try makeLens()
        let clip = CGRect(x: 3, y: 3, width: 180, height: 34)
        lens.update(selection: second, clip: clip, lifted: false, sources: labels, appearance: appearance, transition: .immediate)
        XCTAssertEqual(lens.lensView?.currentLensFrame, CGRect(x: 123, y: 3, width: 60, height: 34))
        lens.update(selection: second, clip: clip, lifted: true, sources: labels, appearance: appearance, transition: .immediate)
        XCTAssertEqual(lens.lensView?.currentLensFrame, second.insetBy(dx: -10, dy: -8))
    }

    func testReduceMotionKeepsTheSelectionAtRest() throws {
        let (lens, _, _, labels) = try makeLens(reduceMotion: true)
        XCTAssertFalse(lens.liftsOnPress)
        lens.update(selection: first, lifted: false, sources: labels, appearance: appearance, transition: .immediate)
        lens.update(selection: second, lifted: true, sources: labels, appearance: appearance, transition: .immediate)
        XCTAssertFalse(lens.isLifted)
        XCTAssertEqual(lens.lensView?.currentLensFrame, second)
        XCTAssertEqual(lens.lensView?.currentInteractionProgress, 0)
    }

    func testWithoutGlassTheContentAndSelectionStayInTheHost() {
        let previous = System.liquidGlass
        defer { System.liquidGlass = previous }
        System.liquidGlass = false
        let (host, selection, labels) = makeHost()
        let lens = GlassSelectionLens(host: host, selectionView: selection)
        lens.updateMode(content: labels)
        XCTAssertNil(lens.lensView)
        XCTAssertNil(lens.contentView)
        XCTAssertFalse(lens.liftsOnPress)
        XCTAssertTrue(labels.allSatisfy { $0.superview === host })
        lens.update(selection: first, lifted: true, sources: labels, appearance: appearance, transition: .immediate)
        XCTAssertEqual(selection.layer?.opacity, 1)
    }
}
