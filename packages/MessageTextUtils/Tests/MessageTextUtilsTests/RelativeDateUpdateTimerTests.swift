import AppKit
import XCTest
@testable import MessageTextUtils

final class RelativeDateUpdateTimerTests: XCTestCase {
    private let date: Int32 = 1_780_000_000

    func testEmptyDatesDoNotCreateATimer() {
        XCTAssertNil(RelativeDateUpdateTimer(timestamps: [], clock: { 0 }, notificationCenter: NotificationCenter(), wakeNotificationCenter: NotificationCenter(), update: { XCTFail() }))
    }

    func testNativeTimerRearmsAtSuccessiveBoundariesOnMainQueue() {
        let started = Date().timeIntervalSince1970
        let base = Double(date) + 10.95
        let fired = expectation(description: "two one-shot deadlines")
        fired.expectedFulfillmentCount = 2
        var times: [Double] = []
        let timer = RelativeDateUpdateTimer(timestamps: [date, date - 7200], clock: { base + Date().timeIntervalSince1970 - started }, notificationCenter: NotificationCenter(), wakeNotificationCenter: NotificationCenter(), update: {
            XCTAssertTrue(Thread.isMainThread)
            times.append(Date().timeIntervalSince1970 - started)
            fired.fulfill()
        })!
        defer { timer.invalidate() }
        wait(for: [fired], timeout: 3)
        XCTAssertEqual(times.count, 2)
        if times.count == 2 {
            XCTAssertGreaterThanOrEqual(times[0], 0.049)
            XCTAssertGreaterThanOrEqual(times[1] - times[0], 0.9)
        }
    }

    func testInvalidationCancelsPendingTimerAndObservers() {
        let center = NotificationCenter()
        let wakeCenter = NotificationCenter()
        let fired = expectation(description: "cancelled callbacks")
        fired.isInverted = true
        let started = Date().timeIntervalSince1970
        let timer = RelativeDateUpdateTimer(timestamps: [date], clock: { Double(self.date) + 10.95 + Date().timeIntervalSince1970 - started }, notificationCenter: center, wakeNotificationCenter: wakeCenter, update: { fired.fulfill() })!
        timer.invalidate()
        timer.invalidate()
        center.post(name: .NSSystemClockDidChange, object: nil)
        wakeCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        wait(for: [fired], timeout: 0.15)
    }

    func testDeinitReleasesTimerWithoutARetainCycle() {
        weak var weakTimer: RelativeDateUpdateTimer?
        autoreleasepool {
            let timer = RelativeDateUpdateTimer(timestamps: [date], clock: { Double(self.date) + 1000 }, notificationCenter: NotificationCenter(), wakeNotificationCenter: NotificationCenter(), update: {})!
            weakTimer = timer
        }
        XCTAssertNil(weakTimer)
    }

    func testClockChangesAndWakeRefreshImmediately() {
        let center = NotificationCenter()
        let wakeCenter = NotificationCenter()
        var now = Double(date) + 1000
        var displayed: [Double] = []
        let timer = RelativeDateUpdateTimer(timestamps: [date], clock: { now }, notificationCenter: center, wakeNotificationCenter: wakeCenter, update: { displayed.append(now) })!
        defer { timer.invalidate() }
        now += 86400
        center.post(name: .NSSystemClockDidChange, object: nil)
        now -= 172800
        center.post(name: .NSSystemClockDidChange, object: nil)
        now += 3600
        wakeCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        XCTAssertEqual(displayed, [Double(date) + 87400, Double(date) - 85400, Double(date) - 81800])
    }

    func testInvalidatingInsideCallbackDoesNotRearm() {
        let started = Date().timeIntervalSince1970
        let base = Double(date) + 10.95
        let fired = expectation(description: "first callback")
        let extra = expectation(description: "no rearm after cancellation")
        extra.isInverted = true
        var count = 0
        weak var weakTimer: RelativeDateUpdateTimer?
        let timer = RelativeDateUpdateTimer(timestamps: [date], clock: { base + Date().timeIntervalSince1970 - started }, notificationCenter: NotificationCenter(), wakeNotificationCenter: NotificationCenter(), update: {
            count += 1
            weakTimer?.invalidate()
            if count == 1 { fired.fulfill() } else { extra.fulfill() }
        })!
        weakTimer = timer
        wait(for: [fired], timeout: 2)
        wait(for: [extra], timeout: 1.1)
        XCTAssertEqual(count, 1)
        withExtendedLifetime(timer) {}
    }

    func testBackwardClockChangeCancelsThePreviousDeadline() {
        let center = NotificationCenter()
        let started = Date().timeIntervalSince1970
        var offset: Double = 0
        var count = 0
        let unexpected = expectation(description: "superseded deadline")
        unexpected.isInverted = true
        let timer = RelativeDateUpdateTimer(timestamps: [date], clock: { Double(self.date) + 10.95 + Date().timeIntervalSince1970 - started + offset }, notificationCenter: center, wakeNotificationCenter: NotificationCenter(), update: {
            count += 1
            if count > 1 { unexpected.fulfill() }
        })!
        defer { timer.invalidate() }
        offset = -7200
        center.post(name: .NSSystemClockDidChange, object: nil)
        XCTAssertEqual(count, 1)
        wait(for: [unexpected], timeout: 0.15)
    }

    func testBoundaryDuringRowConstructionRefreshesBeforeTheFollowingMinute() {
        let fired = expectation(description: "missed construction boundary")
        let timer = RelativeDateUpdateTimer(timestamps: [date], referenceTimestamp: Double(date) + 59.9, clock: { Double(self.date) + 60.1 }, notificationCenter: NotificationCenter(), wakeNotificationCenter: NotificationCenter(), update: { fired.fulfill() })!
        defer { timer.invalidate() }
        wait(for: [fired], timeout: 0.5)
    }

    func testClockMovingBackDuringConstructionRefreshesImmediately() {
        let fired = expectation(description: "clock moved back during construction")
        let timer = RelativeDateUpdateTimer(timestamps: [date], referenceTimestamp: Double(date) + 7200, clock: { Double(self.date) + 1000 }, notificationCenter: NotificationCenter(), wakeNotificationCenter: NotificationCenter(), update: { fired.fulfill() })!
        defer { timer.invalidate() }
        wait(for: [fired], timeout: 0.5)
    }

    func testBoundaryInsideCallbackIsNotSkippedWhenRearming() {
        var now = Double(date) + 60.1
        var count = 0
        let fired = expectation(description: "catch the boundary crossed by the callback")
        fired.expectedFulfillmentCount = 2
        let timer = RelativeDateUpdateTimer(timestamps: [date], referenceTimestamp: Double(date) + 59.9, clock: { now }, notificationCenter: NotificationCenter(), wakeNotificationCenter: NotificationCenter(), update: {
            count += 1
            if count == 1 { now = Double(self.date) + 90.1 }
            fired.fulfill()
        })!
        defer { timer.invalidate() }
        wait(for: [fired], timeout: 0.5)
        XCTAssertEqual(count, 2)
    }

    func testDelayedMainQueueSkipsMissedDeadlines() {
        let started = Date().timeIntervalSince1970
        let base = Double(date) + 10.95
        let fired = expectation(description: "one overdue update")
        let extra = expectation(description: "no catch-up loop")
        extra.isInverted = true
        var count = 0
        let timer = RelativeDateUpdateTimer(timestamps: [date], clock: { base + Date().timeIntervalSince1970 - started }, notificationCenter: NotificationCenter(), wakeNotificationCenter: NotificationCenter(), update: {
            count += 1
            if count == 1 { fired.fulfill() } else { extra.fulfill() }
        })!
        defer { timer.invalidate() }
        Thread.sleep(forTimeInterval: 0.2)
        wait(for: [fired], timeout: 1)
        wait(for: [extra], timeout: 0.1)
        XCTAssertEqual(count, 1)
    }
}
