import XCTest
import CoreGraphics
@testable import ChatUI

final class ChatHeaderInlineLayoutTests: XCTestCase {
    func testAccessoryUsesTheRemainingSpaceBesideTheTitle() throws {
        let available = CGRect(x: 62, y: 12, width: 900, height: 40)
        let frame = try XCTUnwrap(ChatHeaderInlineLayout.accessoryFrame(in: available, preferredTitleWidth: 220, spacing: 10))
        XCTAssertEqual(frame, CGRect(x: 292, y: 12, width: 670, height: 40))
        XCTAssertEqual(frame.maxX, available.maxX)
    }

    func testNarrowHeaderFallsBackBeforeTheSearchFieldIsCramped() {
        let available = CGRect(x: 12, y: 12, width: 549, height: 40)
        XCTAssertNil(ChatHeaderInlineLayout.accessoryFrame(in: available, preferredTitleWidth: 220, spacing: 10))
    }

    func testExactFitReservesTheMinimumAccessoryWidth() throws {
        let available = CGRect(x: 12, y: 12, width: 550, height: 40)
        let frame = try XCTUnwrap(ChatHeaderInlineLayout.accessoryFrame(in: available, preferredTitleWidth: 220, spacing: 10))
        XCTAssertEqual(frame.width, ChatHeaderInlineLayout.minimumAccessoryWidth)
    }

    func testLongTitlesLeaveSpaceForSearch() throws {
        let frame = try XCTUnwrap(ChatHeaderInlineLayout.accessoryFrame(in: CGRect(x: 0, y: 12, width: 590, height: 40), preferredTitleWidth: 1500, spacing: 10))
        XCTAssertEqual(frame.minX, 270)
        XCTAssertEqual(frame.width, ChatHeaderInlineLayout.minimumAccessoryWidth)
    }

    func testShortTitlesKeepRoomForTheAvatarStatusAndTypingActivity() throws {
        let frame = try XCTUnwrap(ChatHeaderInlineLayout.accessoryFrame(in: CGRect(x: 0, y: 12, width: 550, height: 40), preferredTitleWidth: 20, spacing: 10))
        XCTAssertEqual(frame.minX, 230)
        XCTAssertEqual(frame.width, ChatHeaderInlineLayout.minimumAccessoryWidth)
    }

    func testResizingKeepsInlineContentInsideTheAvailableHeader() {
        for width in stride(from: CGFloat(0), through: 1800, by: 1) {
            let available = CGRect(x: 62, y: 12, width: width, height: 40)
            guard let frame = ChatHeaderInlineLayout.accessoryFrame(in: available, preferredTitleWidth: 220, spacing: 10) else {
                continue
            }
            XCTAssertGreaterThanOrEqual(frame.minX, available.minX + 220 + 10)
            XCTAssertGreaterThanOrEqual(frame.width, ChatHeaderInlineLayout.minimumAccessoryWidth)
            XCTAssertEqual(frame.maxX, available.maxX)
            XCTAssertEqual(frame.minY, available.minY)
            XCTAssertEqual(frame.height, available.height)
        }
    }
}
