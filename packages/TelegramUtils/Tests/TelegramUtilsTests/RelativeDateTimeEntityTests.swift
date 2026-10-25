import Foundation
import XCTest
@testable import TelegramUtils

final class RelativeDateTimeEntityTests: XCTestCase {
    private let date: Int32 = 1_780_000_000

    private func reference(_ timestamp: Int64, date: Int32) -> String {
        let delta = timestamp - Int64(date)
        let value = abs(delta)
        let direction = delta > 0 ? "past" : "future"
        if value < 60 {
            return "\(direction):s:\(value)"
        } else if value <= 3600 {
            return "\(direction):m:\(Int(round(Float(value) / 60)))"
        } else if value <= 86400 {
            return "\(direction):h:\(Int(round(Float(value) / 3600)))"
        } else {
            return "\(direction):d:\(Int(round(Float(value) / 86400)))"
        }
    }

    func testNoRelativeDatesHaveNoDeadline() {
        XCTAssertNil(nextRelativeDateTimeEntityUpdate(timestamps: [], now: TimeInterval(date)))
        XCTAssertNil(nextRelativeDateTimeEntityUpdate(timestamps: [date], now: .nan))
        XCTAssertNil(nextRelativeDateTimeEntityUpdate(timestamps: [date], now: .infinity))
    }

    func testSecondMinuteHourAndDayBoundaries() {
        let cases: [(Int64, Int64)] = [
            (-60, -59), (-59, -58), (-1, 0), (0, 1), (1, 2),
            (59, 60), (60, 90), (89, 90), (90, 150),
            (3599, 3601), (3600, 3601), (3601, 5400),
            (86400, 86401), (86401, 129600),
            (-3601, -3600), (-3600, -3569), (-90, -89),
            (-86401, -86400), (-129600, -129599)
        ]
        for (age, nextAge) in cases {
            XCTAssertEqual(nextRelativeDateTimeEntityUpdate(timestamps: [date], now: Double(Int64(date) + age)), Double(Int64(date) + nextAge), "age=\(age)")
        }
    }

    func testFractionalSecondsWaitForTheNextIntegerBoundary() {
        let now = Double(date) + 10.75
        XCTAssertEqual(nextRelativeDateTimeEntityUpdate(timestamps: [date], now: now), Double(date) + 11)
        XCTAssertEqual(nextRelativeDateTimeEntityUpdate(timestamps: [date], now: now)! - now, 0.25)
    }

    func testEarliestDeadlineDoesNotDependOnEntityOrderOrDuplicates() {
        let now = Double(date)
        let recent = date - 10
        let old = date - 7200
        let future = date + 7200
        let expected = now + 1
        for dates in [[recent, old, future], [old, future, recent], [future, recent, old], [old, recent, recent]] {
            XCTAssertEqual(nextRelativeDateTimeEntityUpdate(timestamps: dates, now: now), expected)
        }
    }

    func testFullFourDaySweepMatchesTheOriginalRounding() {
        let firstAge: Int64 = -172800
        let lastAge: Int64 = 259201
        var nextChange = lastAge
        var following = reference(Int64(date) + lastAge, date: date)
        for age in stride(from: lastAge - 1, through: firstAge, by: -1) {
            let current = reference(Int64(date) + age, date: date)
            if current != following {
                nextChange = age + 1
                following = current
            }
            if age <= 172800 {
                XCTAssertEqual(nextRelativeDateTimeEntityUpdate(timestamps: [date], now: Double(Int64(date) + age)), Double(Int64(date) + nextChange), "age=\(age)")
            }
        }
    }

    func testWideTimestampRangeAndFloatRounding() {
        var seed: UInt64 = 0x1A2B3C4D
        for index in 0..<20000 {
            seed = seed &* 6364136223846793005 &+ 1
            let date = Int32(truncatingIfNeeded: seed >> 16)
            seed = seed &* 6364136223846793005 &+ 1
            let now = Int64(Int32(truncatingIfNeeded: seed >> 16))
            let next = Int64(nextRelativeDateTimeEntityUpdate(timestamps: [date], now: Double(now))!)
            XCTAssertGreaterThan(next, now)
            XCTAssertEqual(reference(now, date: date), reference(next - 1, date: date), "case \(index)")
            XCTAssertNotEqual(reference(now, date: date), reference(next, date: date), "case \(index)")
        }
        for date in [Int32.min, Int32.max] {
            for now in [Int64(Int32.min), 0, Int64(Int32.max)] {
                let next = Int64(nextRelativeDateTimeEntityUpdate(timestamps: [date], now: Double(now))!)
                XCTAssertEqual(reference(now, date: date), reference(next - 1, date: date))
                XCTAssertNotEqual(reference(now, date: date), reference(next, date: date))
            }
        }
    }

    func testFreshPastDateNeeds119CallbacksOverAnHour() {
        let end = Double(date) + 3601
        var now = Double(date) + 1
        var count = 0
        while let next = nextRelativeDateTimeEntityUpdate(timestamps: [date], now: now), next <= end {
            XCTAssertNotEqual(reference(Int64(now), date: date), reference(Int64(next), date: date))
            now = next
            count += 1
        }
        XCTAssertEqual(count, 119)
    }

    func testFutureDateSpeedsUpAndRemainsCurrentAcrossTheEvent() {
        let start = Double(date) - 7200
        var now = start
        var shown = reference(Int64(now), date: date)
        var next = nextRelativeDateTimeEntityUpdate(timestamps: [date], now: now)!
        var callbacks = 0
        for offset in 1...7202 {
            now = start + Double(offset)
            if now >= next {
                shown = reference(Int64(now), date: date)
                callbacks += 1
                next = nextRelativeDateTimeEntityUpdate(timestamps: [date], now: now)!
            }
            XCTAssertEqual(shown, reference(Int64(now), date: date), "offset \(offset)")
        }
        XCTAssertEqual(callbacks, 123)
    }

    func testWeekOldDateNeedsOneCallbackOverADay() {
        var now = Double(date) + 7 * 86400
        let end = now + 86400
        var count = 0
        while let next = nextRelativeDateTimeEntityUpdate(timestamps: [date], now: now), next <= end {
            now = next
            count += 1
        }
        XCTAssertEqual(count, 1)
    }
}
