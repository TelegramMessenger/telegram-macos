import XCTest
import AppKit
@testable import TGUIKit

final class ModalOverlayPresentationTests: XCTestCase {
    private final class Dialog: ModalViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            readyOnce()
        }
    }

    private var windows: [Window] = []

    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    override func tearDown() {
        for window in windows {
            closeAllModals(window: window)
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        super.tearDown()
    }

    private func makeWindow(_ size: NSSize) -> Window {
        let window = Window(contentRect: NSRect(origin: NSPoint(x: -2400, y: 100), size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderBack(nil)
        windows.append(window)
        return window
    }

    private func dialog(in window: Window) -> Dialog {
        let controller = Dialog(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        showModal(with: controller, for: window, animated: false)
        return controller
    }

    private func waitForClose(_ controller: Dialog, file: StaticString = #filePath, line: UInt = #line) {
        let deadline = Date().addingTimeInterval(2)
        while controller.modal != nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertNil(controller.modal, file: file, line: line)
    }

    func testSourceRetainsItsViewAndFullWindowOverlayClosesIndependently() throws {
        let main = makeWindow(NSSize(width: 900, height: 800))
        let source = makeWindow(NSSize(width: 420, height: 600))
        source.modalPresentationParent = main
        let content = source.contentView
        let frame = source.frame
        let controller = dialog(in: source)
        let retainedModal = try XCTUnwrap(controller.modal)
        let overlay = retainedModal.window
        XCTAssertFalse(overlay === main)
        XCTAssertFalse(overlay === source)
        XCTAssertTrue(overlay.parent === source)
        XCTAssertFalse(overlay.isOpaque)
        XCTAssertEqual(overlay.frame.size, main.contentView!.bounds.size)
        XCTAssertTrue(hasModals(main) && hasModals(source))
        controller.close()
        waitForClose(controller)
        XCTAssertNil(overlay.parent)
        XCTAssertFalse(overlay.isVisible)
        XCTAssertTrue(source.isVisible)
        XCTAssertTrue(source.contentView === content)
        XCTAssertEqual(source.frame, frame)
        XCTAssertFalse(hasModals(source))
    }

    func testSameTypeNestedDialogsKeepRemainingDialogInEitherCloseOrder() throws {
        for closeLowerFirst in [false, true] {
            let main = makeWindow(NSSize(width: 900, height: 800))
            let source = makeWindow(NSSize(width: 420, height: 600))
            source.modalPresentationParent = main
            let lower = dialog(in: source)
            let overlay = try XCTUnwrap(lower.modal).window
            let upper = dialog(in: main)
            XCTAssertTrue(upper.modal?.window === overlay)
            XCTAssertNotNil(lower.modal)
            let first = closeLowerFirst ? lower : upper
            let remaining = closeLowerFirst ? upper : lower
            first.close()
            waitForClose(first)
            XCTAssertNotNil(remaining.modal)
            XCTAssertTrue(overlay.isVisible)
            XCTAssertTrue(overlay.parent === source)
            remaining.close()
            waitForClose(remaining)
            XCTAssertFalse(overlay.isVisible)
            XCTAssertNil(overlay.parent)
        }
    }

    func testSourceCleanupAndUnrelatedSameTypeDialogsAreIsolated() throws {
        let main = makeWindow(NSSize(width: 900, height: 800))
        let source = makeWindow(NSSize(width: 420, height: 600))
        source.modalPresentationParent = main
        let lower = dialog(in: source)
        let upper = dialog(in: main)
        let overlay = try XCTUnwrap(lower.modal).window
        let unrelated = makeWindow(NSSize(width: 600, height: 600))
        let other = dialog(in: unrelated)
        XCTAssertTrue(other.modal?.window === unrelated)
        XCTAssertNotNil(lower.modal)
        XCTAssertNotNil(upper.modal)
        closeAllModals(window: source)
        waitForClose(lower)
        waitForClose(upper)
        XCTAssertFalse(overlay.isVisible)
        XCTAssertNotNil(other.modal)
        other.close()
        waitForClose(other)
    }

    func testOrdinaryWindowKeepsItsExistingReplacementBehavior() throws {
        let window = makeWindow(NSSize(width: 900, height: 800))
        let first = dialog(in: window)
        XCTAssertTrue(first.modal?.window === window)
        let second = dialog(in: window)
        waitForClose(first)
        XCTAssertTrue(second.modal?.window === window)
        second.close()
        waitForClose(second)
    }

}
