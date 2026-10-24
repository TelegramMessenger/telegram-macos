import Cocoa
import XCTest
@testable import ChatUI

private final class PointerPassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class ChatLayerPointerVisibilityTests: XCTestCase {
    private var window: NSWindow!
    private var host: NSView!
    private var scene: NSView!
    private let point = NSPoint(x: 20, y: 25)

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        window = NSWindow(contentRect: NSRect(x: 40, y: 30, width: 400, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView = content
        host = NSView(frame: NSRect(x: 31, y: 47, width: 330, height: 230))
        content.addSubview(host)
        scene = NSView(frame: NSRect(x: 13, y: 17, width: 260, height: 180))
        host.addSubview(scene)
    }

    override func tearDown() {
        window.contentView = nil
        window.close()
        window = nil
        host = nil
        scene = nil
        super.tearDown()
    }

    private func cover() -> NSView {
        let overlay = NSView(frame: scene.frame)
        host.addSubview(overlay, positioned: .above, relativeTo: scene)
        return overlay
    }

    func testUncoveredMessageCanReceiveHover() {
        XCTAssertTrue(chatLayerPointerIsExposed(scene, at: point))
    }

    func testSuggestionsCoverMessageEvenWhenItsOwnHitTestSucceeds() {
        _ = cover()
        XCTAssertTrue(scene.hitTest(scene.convert(point, to: host)) === scene)
        XCTAssertFalse(chatLayerPointerIsExposed(scene, at: point))
    }

    func testCoverAppearingAtStationaryPointerInvalidatesHover() {
        XCTAssertTrue(chatLayerPointerIsExposed(scene, at: point))
        let overlay = cover()
        XCTAssertFalse(chatLayerPointerIsExposed(scene, at: point))
        overlay.removeFromSuperview()
        XCTAssertTrue(chatLayerPointerIsExposed(scene, at: point))
    }

    func testHiddenSuggestionsDoNotBlockMessage() {
        let overlay = cover()
        overlay.isHidden = true
        XCTAssertTrue(chatLayerPointerIsExposed(scene, at: point))
    }

    func testPassthroughOverlayDoesNotBlockMessage() {
        host.addSubview(PointerPassthroughView(frame: scene.frame))
        XCTAssertTrue(chatLayerPointerIsExposed(scene, at: point))
    }

    func testNativeChildOfSceneRemainsExposed() {
        scene.addSubview(NSView(frame: NSRect(x: 10, y: 10, width: 50, height: 50)))
        XCTAssertTrue(chatLayerPointerIsExposed(scene, at: point))
    }

    func testHiddenAndDetachedMessageCannotReceiveHover() {
        scene.isHidden = true
        XCTAssertFalse(chatLayerPointerIsExposed(scene, at: point))
        scene.isHidden = false
        scene.removeFromSuperview()
        XCTAssertFalse(chatLayerPointerIsExposed(scene, at: point))
    }

    func testPointerOutsideClippedHostCannotReceiveHover() {
        scene.setFrameSize(NSSize(width: 400, height: 180))
        XCTAssertFalse(chatLayerPointerIsExposed(scene, at: NSPoint(x: 350, y: 25)))
    }
}
