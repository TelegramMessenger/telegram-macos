import XCTest
import AppKit
@testable import TGUIKit

final class ModalNavigationLayoutTests: XCTestCase {
    private final class ContentController: ViewController {
        override func viewDidLoad() {
            super.viewDidLoad()
            readyOnce()
        }
    }

    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    func testNavigationWrapperPreservesBoundsBeforeAndAfterLoading() {
        let navigation = NavigationViewController(ContentController(), nil)
        navigation._frameRect = NSMakeRect(0, 0, 300, 310)
        let wrapper = ModalController(navigation)
        XCTAssertFalse(wrapper.isLoaded())
        XCTAssertEqual(wrapper.bounds.size, navigation._frameRect.size)
        wrapper.loadViewIfNeeded()
        XCTAssertEqual(wrapper.bounds.size, navigation.view.bounds.size)
        XCTAssertEqual(wrapper.bounds.size, NSMakeSize(300, 310))
    }

    func testNavigationModalContainsItsContentOnOpenAndResize() throws {
        let window = Window(contentRect: NSMakeRect(0, 0, 800, 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = View(frame: NSMakeRect(0, 0, 800, 600))
        let navigation = NavigationViewController(ContentController(), window)
        navigation._frameRect = NSMakeRect(0, 0, 300, 310)
        let wrapper = ModalController(navigation)
        let modal = Modal(controller: wrapper, for: window, animated: false, isOverlay: false, animationType: .bottomToCenter)
        defer { modal.close(animationType: .noMorph) }
        modal.show()
        let parent = try XCTUnwrap(navigation.view.superview)
        XCTAssertEqual(parent.bounds.size, navigation.view.bounds.size)
        XCTAssertTrue(parent.bounds.contains(navigation.view.frame))
        for size in [NSMakeSize(340, 380), NSMakeSize(300, 246)] {
            modal.resize(with: size, animated: false)
            XCTAssertEqual(parent.bounds.size, size)
            XCTAssertEqual(navigation.view.bounds.size, size)
            XCTAssertTrue(parent.bounds.contains(navigation.view.frame))
        }
    }
}
