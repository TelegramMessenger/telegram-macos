import Cocoa
import XCTest
import TGUIKit
@testable import ChatUI

private final class RecordingPointerWindow: Window {
    var pointer = NSPoint.zero

    override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
}

final class RecordingTrimScrubberInteractionTests: XCTestCase {
    private var window: RecordingPointerWindow!
    private var scrubber: RecordingTrimScrubberView!

    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
        window = RecordingPointerWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        scrubber = RecordingTrimScrubberView(frame: NSRect(x: 30, y: 30, width: 400, height: 34))
        window.contentView?.addSubview(scrubber)
        scrubber.update(duration: 10, waveform: nil, trimRange: 0 ..< 10, position: 0, isPlaying: false, isVideo: true)
        scrubber.layoutSubtreeIfNeeded()
    }

    override func tearDown() {
        window.contentView = nil
        window.close()
        scrubber = nil
        window = nil
        super.tearDown()
    }

    private var handles: [Control] {
        scrubber.subviews.compactMap { $0 as? Control }.filter { $0.frame.width == 34 }.sorted { $0.frame.minX < $1.frame.minX }
    }

    func testBothVideoGripsReceivePointerEvents() throws {
        XCTAssertEqual(handles.count, 2)
        for handle in handles {
            let point = NSPoint(x: handle.frame.midX, y: handle.frame.midY)
            let hit = scrubber.hitTest(scrubber.convert(point, to: scrubber.superview))
            XCTAssertTrue(hit === handle, "Unexpected target: \(String(describing: hit))")
        }
    }

    func testVideoTimelineHasVisiblePlaybackControl() throws {
        let play = try XCTUnwrap(scrubber.subviews.compactMap { $0 as? Control }.first { $0.frame.height == 22 })
        XCTAssertFalse(play.isHidden)
        var toggles = 0
        scrubber.togglePlay = { toggles += 1 }
        play.send(event: .Click)
        XCTAssertEqual(toggles, 1)
    }

    func testRightBoundaryIsAboveFloatingRecorder() throws {
        let right = try XCTUnwrap(handles.last)
        let screenPoint = window.convertPoint(toScreen: right.convert(NSPoint(x: right.bounds.midX, y: right.bounds.midY), to: nil))
        let overlay = ChatRecorderOverlayWindow(parent: window)
        let host = try XCTUnwrap(overlay.contentView)
        let point = host.convert(overlay.convertPoint(fromScreen: screenPoint), from: nil)
        let send = Control(frame: NSRect(x: point.x - 4, y: point.y - 50, width: 100, height: 100))
        overlay.installControls([send], editorControls: [scrubber])
        XCTAssertTrue(scrubber.window === overlay)
        let hit = host.hitTest(host.convert(point, to: host.superview))
        XCTAssertTrue(hit === right, "Recorder intercepts the right trim handle: \(String(describing: hit))")
        window.contentView?.addSubview(scrubber)
        overlay.contentView = nil
        overlay.close()
    }

    func testPauseControlReceivesClicksInOverlayWindow() throws {
        let overlay = ChatRecorderOverlayWindow(parent: window)
        let pause = ChatRecorderPauseControl(frame: NSRect(x: 250, y: 180, width: 40, height: 40))
        let body = Control(frame: NSRect(x: 220, y: 150, width: 100, height: 100))
        var pauses = 0
        pause.set(handler: { _ in pauses += 1 }, for: .Click)
        overlay.installControls([body, pause], editorControls: [])
        let host = try XCTUnwrap(overlay.contentView)
        var target = host.hitTest(host.convert(NSPoint(x: pause.frame.midX, y: pause.frame.midY), to: host.superview))
        while let view = target, view !== pause {
            target = view.superview
        }
        XCTAssertTrue(target === pause)
        (target as? Control)?.send(event: .Click)
        XCTAssertEqual(pauses, 1)
        overlay.contentView = nil
        overlay.close()
    }

    func testRightBoundaryCanShrinkAndExpand() throws {
        let handle = try XCTUnwrap(handles.last)
        var ranges: [Range<Double>] = []
        scrubber.trimUpdated = { range, _, _ in ranges.append(range) }
        window.pointer = handle.convert(NSPoint(x: handle.bounds.midX, y: handle.bounds.midY), to: nil)
        let origin = window.pointer
        handle.send(event: .Down)
        window.pointer.x -= 80
        handle.send(event: .MouseDragging)
        let reduced = try XCTUnwrap(ranges.last)
        XCTAssertLessThan(reduced.upperBound, 10)
        window.pointer = origin
        handle.send(event: .MouseDragging)
        XCTAssertEqual(ranges.last?.upperBound, 10)
        handle.send(event: .Up)
    }

    func testLeftBoundaryCanShrinkAndExpand() throws {
        let handle = try XCTUnwrap(handles.first)
        var ranges: [Range<Double>] = []
        scrubber.trimUpdated = { range, _, _ in ranges.append(range) }
        window.pointer = handle.convert(NSPoint(x: handle.bounds.midX, y: handle.bounds.midY), to: nil)
        let origin = window.pointer
        handle.send(event: .Down)
        window.pointer.x += 80
        handle.send(event: .MouseDragging)
        XCTAssertGreaterThan(try XCTUnwrap(ranges.last).lowerBound, 0)
        window.pointer = origin
        handle.send(event: .MouseDragging)
        XCTAssertEqual(ranges.last?.lowerBound, 0)
        handle.send(event: .Up)
    }
}
