import Cocoa
import XCTest
import TGUIKit
@testable import ChatUI

final class RecordingOverlayLifecycleTests: XCTestCase {
    private var parent: Window!
    private var overlay: ChatRecorderOverlayWindow!

    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
        parent = Window(contentRect: NSRect(x: 0, y: 0, width: 500, height: 300), styleMask: .borderless, backing: .buffered, defer: false)
        parent.isReleasedWhenClosed = false
        overlay = ChatRecorderOverlayWindow(parent: parent)
        overlay.attach()
    }

    override func tearDown() {
        overlay.detach()
        overlay.close()
        parent.close()
        overlay = nil
        parent = nil
        super.tearDown()
    }

    func testConfirmationSuspendsRecorderAndCannotOpenTwice() {
        XCTAssertTrue(overlay.parent === parent)
        XCTAssertTrue(overlay.suspendForModal())
        XCTAssertNil(overlay.parent)
        XCTAssertFalse(overlay.acceptsRecordingEvents)
        XCTAssertFalse(overlay.suspendForModal())
        overlay.resumeAfterModal()
        XCTAssertTrue(overlay.parent === parent)
        XCTAssertTrue(overlay.acceptsRecordingEvents)
    }

    func testRepeatedDiscardCannotResurrectRecordingWindow() {
        for _ in 0 ..< 10 {
            overlay.attach()
            XCTAssertTrue(overlay.suspendForModal())
            overlay.detach()
            overlay.resumeAfterModal()
            XCTAssertNil(overlay.parent)
            XCTAssertFalse(overlay.acceptsRecordingEvents)
        }
    }

    func testDismissalFinishesWithoutAnimationCallback() {
        XCTAssertTrue(overlay.suspendForModal())
        var animationCompletion: (() -> Void)?
        var count = 0
        let finished = expectation(description: "Hidden recording window is cleaned up")
        performRecordingDismissal(timeout: 0.02, animations: { animationCompletion = $0 }, completion: {
            count += 1
            self.overlay.detach()
            finished.fulfill()
        })
        wait(for: [finished], timeout: 1)
        animationCompletion?()
        animationCompletion?()
        overlay.resumeAfterModal()
        XCTAssertEqual(count, 1)
        XCTAssertNil(overlay.parent)
    }

    func testAnimationAndFallbackCannotCompleteDismissalTwice() {
        var count = 0
        performRecordingDismissal(timeout: 0.02, animations: { finish in
            finish()
            finish()
        }, completion: { count += 1 })
        let fallback = expectation(description: "Fallback deadline elapsed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { fallback.fulfill() }
        wait(for: [fallback], timeout: 1)
        XCTAssertEqual(count, 1)
    }
}
