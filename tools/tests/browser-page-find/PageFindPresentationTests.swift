import Cocoa
import XCTest

final class PageFindPresentationTests: XCTestCase {
    func testSearchHeaderReservesSpaceWithoutCumulativeShrink() {
        let scroll = InstantPageFindScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 500))
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 1000))
        scroll.tile()
        let original = scroll.contentView.frame
        let bar = PageFindBarView(frame: .zero)
        scroll.pageFindBar = bar
        let displayed = scroll.contentView.frame
        XCTAssertEqual(displayed.height, original.height - 46)
        XCTAssertEqual(displayed.width, original.width)
        XCTAssertEqual(bar.frame.height, 46)
        XCTAssertFalse(bar.frame.intersects(displayed))
        for _ in 0 ..< 20 { scroll.tile() }
        XCTAssertEqual(scroll.contentView.frame, displayed)
        scroll.pageFindBar = nil
        XCTAssertEqual(scroll.contentView.frame, original)
        XCTAssertNil(bar.superview)
    }

    func testSmallHeaderAndResizeStayInsideScrollBounds() {
        let scroll = InstantPageFindScrollView(frame: NSRect(x: 0, y: 0, width: 220, height: 20))
        scroll.pageFindBar = PageFindBarView(frame: .zero)
        scroll.tile()
        XCTAssertEqual(scroll.contentView.frame.height, 0)
        XCTAssertEqual(scroll.pageFindBar?.frame.height, 20)
        scroll.setFrameSize(NSSize(width: 600, height: 400))
        scroll.tile()
        XCTAssertEqual(scroll.pageFindBar?.frame.width, 600)
        XCTAssertEqual(scroll.contentView.frame.height, 354)
    }
}
