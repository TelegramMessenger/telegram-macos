import XCTest
@testable import HTMLBubbles

final class WidgetPreviewLayoutTests: XCTestCase {
    func testAutoHeightUsesPlaceholderThenReportedHeight() {
        let placeholder = HTMLWidgetPreviewLayout(width: 0, height: 0, availableWidth: 350, reportedHeight: nil)
        XCTAssertEqual(placeholder.contentSize, CGSize(width: 350, height: 160))
        let measured = HTMLWidgetPreviewLayout(width: 0, height: 0, availableWidth: 350, reportedHeight: 210)
        XCTAssertEqual(measured.displaySize, CGSize(width: 350, height: 210))
    }

    func testTallWidgetsScaleWithoutCroppingOrRelayoutAtANarrowerWidth() {
        let layout = HTMLWidgetPreviewLayout(width: 0, height: 400, availableWidth: 350, reportedHeight: 100)
        XCTAssertEqual(layout.contentSize, CGSize(width: 350, height: 400))
        XCTAssertEqual(layout.displaySize, CGSize(width: 210, height: 240))
    }

    func testAnchorsAreClampedLikeSentWidgets() {
        XCTAssertEqual(HTMLWidgetPreviewLayout(width: 100, height: 10, availableWidth: 350, reportedHeight: nil).contentSize, CGSize(width: 200, height: 50))
        XCTAssertEqual(HTMLWidgetPreviewLayout(width: 800, height: 800, availableWidth: 350, reportedHeight: nil).contentSize, CGSize(width: 350, height: 600))
        XCTAssertEqual(HTMLWidgetPreviewLayout(width: 100, height: 100, availableWidth: 150, reportedHeight: nil).contentSize, CGSize(width: 150, height: 100))
    }

    func testAutoHeightIsClampedAndFixedHeightIgnoresReports() {
        XCTAssertEqual(HTMLWidgetPreviewLayout(width: 0, height: 0, availableWidth: 350, reportedHeight: 900).contentSize.height, 600)
        XCTAssertEqual(HTMLWidgetPreviewLayout(width: 0, height: 0, availableWidth: 350, reportedHeight: 5).contentSize.height, 50)
        XCTAssertEqual(HTMLWidgetPreviewLayout(width: 0, height: 100, availableWidth: 350, reportedHeight: 200).contentSize.height, 100)
    }

    func testWideSuggestionsUseTheSentBubbleMaximumWidth() {
        XCTAssertEqual(HTMLWidgetPreviewLayout(width: 0, height: 0, availableWidth: 1000, reportedHeight: 180).contentSize, CGSize(width: 450, height: 180))
        XCTAssertEqual(HTMLWidgetPreviewLayout(width: 900, height: 400, availableWidth: 1000, reportedHeight: nil).displaySize, CGSize(width: 270, height: 240))
    }
}
