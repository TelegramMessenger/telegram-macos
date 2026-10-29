import Foundation
import XCTest
import TGUIKit

final class DateExtractionTests: XCTestCase {
    private let referenceDate = Date(timeIntervalSince1970: 0)

    func testRussianYearIsNotDetectedAsHour() {
        XCTAssertTrue(extractDates(from: "через 1 год", referenceDate: referenceDate).isEmpty)
        XCTAssertEqual(
            extractDates(from: "через 1 год = через 60 минут", referenceDate: referenceDate).map(\.text),
            ["через 60 минут"]
        )
    }

    func testRussianAndBelarusianHoursAreDetected() {
        XCTAssertEqual(
            extractDates(from: "через 1 час", referenceDate: referenceDate).map(\.text),
            ["через 1 час"]
        )
        XCTAssertEqual(
            extractDates(from: "праз 1 гадзіну", referenceDate: referenceDate).map(\.text),
            ["праз 1 гадзіну"]
        )
    }
}
