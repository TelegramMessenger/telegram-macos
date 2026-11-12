import XCTest
import Cocoa
import TGUIKit
@testable import ChatUI

final class GiftPreviewTitleLayoutTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private func title(_ text: String, fontSize: CGFloat = 14, width: CGFloat = 200) -> TextView {
        let attributed = NSMutableAttributedString(string: "Telegram\n", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .medium)])
        attributed.append(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: fontSize, weight: .medium)]))
        let layout = TextViewLayout(attributed, maximumNumberOfLines: 10, truncationType: .end, alwaysStaticItems: true)
        layout.measure(width: width)
        let view = TextView()
        view.update(layout)
        view.setFrameOrigin(.zero)
        return view
    }

    private func contentRect(textHeight: CGFloat, width: CGFloat = 200, mediaHeight: CGFloat = 200) -> NSRect {
        return NSMakeRect(8, 3, width, mediaHeight + textHeight + 6 + 39 + 50)
    }

    private func background(_ text: TextView, width: CGFloat = 200) -> NSRect {
        return WPMediaContentView.giftBackgroundFrame(contentRect: contentRect(textHeight: text.frame.height, width: width), textFrame: text.frame)
    }

    func testWrappedGiftNameAndNumberAreAboveBackground() throws {
        let view = title("Homemade Cake #1400370", fontSize: 18)
        let layout = try XCTUnwrap(view.textLayout)
        XCTAssertGreaterThanOrEqual(layout.lines.count, 3)
        XCTAssertEqual(layout.attributedString.string, "Telegram\nHomemade Cake #1400370")
        XCTAssertGreaterThanOrEqual(background(view).minY, view.frame.maxY + 6)
    }

    func testExplicitNumberLineIsNotCovered() {
        let view = title("Homemade Cake\n#1400370")
        XCTAssertGreaterThanOrEqual(background(view).minY, view.frame.maxY + 6)
    }

    func testMultilineNamesRemainAboveBackgroundAtEveryFontSize() {
        for fontSize: CGFloat in [11, 13, 16, 18, 24, 30] {
            let view = title("Very Long Collectible Gift Name #123456789", fontSize: fontSize)
            XCTAssertGreaterThanOrEqual(background(view).minY, view.frame.maxY + 6, "Font size: \(fontSize)")
            XCTAssertGreaterThan(background(view).height, 0)
        }
    }

    func testNarrowAndWideTextMeasurementsKeepSeparation() {
        for width: CGFloat in [120, 160, 200, 260, 320] {
            let view = title("Homemade Cake #1400370", fontSize: 18, width: width)
            XCTAssertGreaterThanOrEqual(background(view, width: width).minY, view.frame.maxY + 6, "Width: \(width)")
        }
    }

    func testRemeasuredTextDoesNotRetainOldBackgroundOrigin() {
        let view = title("A Very Long Gift Name #123456789", fontSize: 18, width: 300)
        let wide = background(view, width: 300)
        view.textLayout?.measure(width: 120)
        view.update(view.textLayout)
        let narrow = background(view, width: 120)
        XCTAssertGreaterThan(narrow.minY, wide.minY)
        XCTAssertGreaterThanOrEqual(narrow.minY, view.frame.maxY + 6)
        view.textLayout?.measure(width: 300)
        view.update(view.textLayout)
        XCTAssertEqual(background(view, width: 300), wide)
    }

    func testBackgroundBottomAndHorizontalInsetsStayUnchanged() {
        let view = title("Homemade Cake\n#1400370", fontSize: 24)
        let rect = contentRect(textHeight: view.frame.height)
        let previous = rect.insetBy(dx: 0, dy: 35).offsetBy(dx: -8, dy: -2)
        let updated = WPMediaContentView.giftBackgroundFrame(contentRect: rect, textFrame: view.frame)
        XCTAssertEqual(updated.maxY, previous.maxY)
        XCTAssertEqual(updated.minX, previous.minX)
        XCTAssertEqual(updated.width, previous.width)
        XCTAssertGreaterThan(updated.minY, previous.minY)
    }

    func testShortTextKeepsExistingMinimumTopInset() {
        let rect = NSMakeRect(8, 3, 200, 280)
        let text = NSMakeRect(0, 0, 100, 20)
        XCTAssertEqual(WPMediaContentView.giftBackgroundFrame(contentRect: rect, textFrame: text), rect.insetBy(dx: 0, dy: 35).offsetBy(dx: -8, dy: -2))
    }

    func testNoTextKeepsExistingBackgroundGeometry() {
        let rect = NSMakeRect(8, 3, 200, 280)
        XCTAssertEqual(WPMediaContentView.giftBackgroundFrame(contentRect: rect, textFrame: .zero), rect.insetBy(dx: 0, dy: 35).offsetBy(dx: -8, dy: -2))
    }

    func testTextOriginIsRespectedInContainerCoordinates() {
        let rect = NSMakeRect(8, 3, 200, 350)
        let text = NSMakeRect(0, 12, 200, 60)
        XCTAssertEqual(WPMediaContentView.giftBackgroundFrame(contentRect: rect, textFrame: text).minY, 78)
    }

    func testTextGapDoesNotDependOnBackingScale() {
        let view = title("Homemade Cake\n#1400370", fontSize: 18)
        let frame = background(view)
        for scale: CGFloat in [1, 2] {
            XCTAssertGreaterThanOrEqual((frame.minY - view.frame.maxY) * scale, 6 * scale)
        }
    }

    func testGrowingTitleDoesNotChangeAvailableGiftHeight() {
        let short = NSMakeRect(0, 0, 200, 40)
        let long = NSMakeRect(0, 0, 200, 90)
        let first = WPMediaContentView.giftBackgroundFrame(contentRect: contentRect(textHeight: short.height), textFrame: short)
        let second = WPMediaContentView.giftBackgroundFrame(contentRect: contentRect(textHeight: long.height), textFrame: long)
        XCTAssertEqual(second.minY - first.minY, 50)
        XCTAssertEqual(second.height, first.height)
    }

    func testDegenerateContentNeverProducesNegativeHeight() {
        let frame = WPMediaContentView.giftBackgroundFrame(contentRect: NSMakeRect(8, 3, 200, 80), textFrame: NSMakeRect(0, 0, 200, 120))
        XCTAssertEqual(frame.height, 0)
        XCTAssertGreaterThanOrEqual(frame.minY, 126)
    }
}
