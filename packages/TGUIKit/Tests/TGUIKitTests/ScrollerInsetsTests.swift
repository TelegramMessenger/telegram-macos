import XCTest
import AppKit
@testable import TGUIKit

final class ScrollerInsetsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    func testVerticalScrollerRetainsTheNativeAppKitImplementation() throws {
        let frame = NSRect(x: 0, y: 0, width: 320, height: 400)
        let native = NSScrollView(frame: frame)
        native.scrollerStyle = .overlay
        native.hasVerticalScroller = true
        let expected = try XCTUnwrap(native.verticalScroller)
        let view = ScrollView(frame: frame)
        view.hasVerticalScroller = true
        let scroller = try XCTUnwrap(view.verticalScroller)
        XCTAssertEqual(ObjectIdentifier(type(of: scroller)), ObjectIdentifier(type(of: expected)))
        XCTAssertEqual(scroller.controlSize, expected.controlSize)
        XCTAssertEqual(scroller.knobStyle, expected.knobStyle)
        XCTAssertEqual(scroller.scrollerStyle, .overlay)
        view.hasVerticalScroller = false
        view.hasVerticalScroller = true
        XCTAssertTrue(view.verticalScroller === scroller)
    }

    func testHorizontalOnlyViewDoesNotGainVerticalScroller() {
        let view = HorizontalScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 400))
        XCTAssertFalse(view.hasVerticalScroller)
    }

    func testRepeatedPickerUpdatesKeepOnlyTheUnreservedBottomClearance() throws {
        let scroll = ScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 400))
        scroll.hasVerticalScroller = true
        scroll.documentView = View(frame: NSRect(x: 0, y: 0, width: 320, height: 1200))
        for reserved: CGFloat in [0, 56, 56, 56, 20, 56, 0] {
            scroll.contentInsets.bottom = reserved
            scroll.scrollerInsets = .init(left: 0, right: 0, top: 46, bottom: scroll.additionalBottomScrollerInset(for: 50))
            scroll.layoutSubtreeIfNeeded()
            XCTAssertEqual(scroll.scrollerInsets.bottom, max(0, 50 - reserved))
            XCTAssertEqual(scroll.scrollerInsets.top, 46)
            let scroller = try XCTUnwrap(scroll.verticalScroller)
            if scroll.isFlipped {
                XCTAssertEqual(scroller.frame.maxY, scroll.bounds.maxY - max(50, reserved), accuracy: 0.5)
            } else {
                XCTAssertEqual(scroller.frame.minY, scroll.bounds.minY + max(50, reserved), accuracy: 0.5)
            }
            XCTAssertEqual(reserved + scroll.scrollerInsets.bottom, max(50, reserved))
        }
    }

}
