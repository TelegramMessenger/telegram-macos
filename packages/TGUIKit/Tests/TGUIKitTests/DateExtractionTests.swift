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

    func testRussianUkrainianAndBelarusianHoursAreDetected() {
        XCTAssertEqual(
            extractDates(from: "через 1 час", referenceDate: referenceDate).map(\.text),
            ["через 1 час"]
        )
        XCTAssertEqual(
            extractDates(from: "через 2 години", referenceDate: referenceDate).map(\.text),
            ["через 2 години"]
        )
        XCTAssertEqual(
            extractDates(from: "за годину", referenceDate: referenceDate).map(\.text),
            ["за годину"]
        )
        XCTAssertEqual(
            extractDates(from: "через 5 годин", referenceDate: referenceDate).map(\.text),
            ["через 5 годин"]
        )
        XCTAssertEqual(
            extractDates(from: "праз 1 гадзіну", referenceDate: referenceDate).map(\.text),
            ["праз 1 гадзіну"]
        )
    }
}
