import XCTest
import AppKit
import CoreVideo
@testable import TGUIKit

final class DisplayLinkRateTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    private var refreshRate: Double {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithCGDisplay(CGMainDisplayID(), &link)
        let period = CVDisplayLinkGetNominalOutputVideoRefreshPeriod(link!)
        return Double(period.timeScale) / Double(period.timeValue)
    }

    func testValueAnimatorTicksAtTheDisplayRate() {
        let finished = expectation(description: "finished")
        var ticks = 0
        var values: [CGFloat] = []
        let animator = DisplayLinkAnimator(duration: 1.0, from: 0, to: 1, update: { value in
            ticks += 1
            values.append(value)
        }, completion: {
            finished.fulfill()
        })
        wait(for: [finished], timeout: 4)
        withExtendedLifetime(animator) {}
        XCTAssertGreaterThan(Double(ticks), self.refreshRate * 0.8, "refresh \(self.refreshRate)")
        XCTAssertEqual(values.last, 1)
        XCTAssertEqual(values, values.sorted())
    }

    func testDisplayRateConstantAnimatorReportsTheFrameDuration() {
        var durations: [CGFloat] = []
        let animator = ConstantDisplayLinkAnimator(framesPerSecond: .max, update: { duration in
            durations.append(duration)
        })
        animator.isPaused = false
        let done = expectation(description: "done")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
        animator.isPaused = true
        XCTAssertGreaterThan(Double(durations.count), self.refreshRate * 0.8, "refresh \(self.refreshRate)")
        let median = durations.sorted()[durations.count / 2]
        XCTAssertEqual(Double(median), 1.0 / self.refreshRate, accuracy: 0.002)
    }

    func testDefaultConstantAnimatorKeepsSixtyFramesPerSecond() {
        var ticks = 0
        let animator = ConstantDisplayLinkAnimator(update: {
            ticks += 1
        })
        animator.isPaused = false
        let done = expectation(description: "done")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            done.fulfill()
        }
        wait(for: [done], timeout: 3)
        animator.isPaused = true
        XCTAssertEqual(Double(ticks), min(60, self.refreshRate), accuracy: 8)
    }
}

extension DisplayLinkRateTests {
    private func measure(_ fps: [SharedDisplayLinkDriver.FramesPerSecond], seconds: Double = 2.0) -> (ticks: [Int], deliveries: Int) {
        var ticks = Array(repeating: 0, count: fps.count)
        let animators = fps.enumerated().map { index, rate in
            ConstantDisplayLinkAnimator(framesPerSecond: rate, update: { _ in
                ticks[index] += 1
            })
        }
        for animator in animators {
            animator.isPaused = false
        }
        let warm = expectation(description: "warm")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            warm.fulfill()
        }
        wait(for: [warm], timeout: 3)
        ticks = Array(repeating: 0, count: fps.count)
        let before = SharedDisplayLinkDriver.shared.deliveredEvents
        let done = expectation(description: "done")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            done.fulfill()
        }
        wait(for: [done], timeout: seconds + 3)
        let deliveries = SharedDisplayLinkDriver.shared.deliveredEvents - before
        for animator in animators {
            animator.isPaused = true
        }
        let result = (ticks.map { Int((Double($0) / seconds).rounded()) }, Int((Double(deliveries) / seconds).rounded()))
        print("DisplayLinkRate refresh \(Int(self.refreshRate)) Hz, links \(fps): ticks/s \(result.0), main deliveries/s \(result.1)")
        return result
    }

    func testLowRateLinkOnlyWakesTheMainThreadWhenDue() throws {
        try XCTSkipIf(self.refreshRate < 50, "needs a display faster than the link")
        let result = self.measure([.fps(25)])
        let expected = self.refreshRate / Double(Int(ceil(self.refreshRate / 25.0 * 0.95 - 1e-3)))
        XCTAssertEqual(Double(result.ticks[0]), expected, accuracy: 3, "refresh \(self.refreshRate)")
        XCTAssertLessThanOrEqual(Double(result.deliveries), Double(result.ticks[0]) + 3, "refresh \(self.refreshRate)")
    }

    func testMixedRatesKeepTheirOwnCadence() throws {
        try XCTSkipIf(self.refreshRate < 50, "needs a display faster than the links")
        let rates = [25, 30, 60]
        let result = self.measure(rates.map { .fps($0) })
        let frameIntervals = rates.map { max(1, Int(ceil(self.refreshRate / Double($0) * 0.95 - 1e-3))) }
        for index in rates.indices {
            XCTAssertEqual(Double(result.ticks[index]), self.refreshRate / Double(frameIntervals[index]), accuracy: index == 2 ? 6 : 3)
        }
        let cycle = frameIntervals.reduce(1) { cycle, interval in
            var a = cycle
            var b = interval
            while b != 0 {
                (a, b) = (b, a % b)
            }
            return cycle / a * interval
        }
        let dueFrames = (1 ... cycle).filter { frame in
            frameIntervals.contains { frame.isMultiple(of: $0) }
        }.count
        let expectedDeliveries = self.refreshRate * Double(dueFrames) / Double(cycle)
        XCTAssertEqual(Double(result.deliveries), expectedDeliveries, accuracy: 6)
    }

    func testMaxLinkStillGetsEveryFrame() {
        let result = self.measure([.fps(25), .max])
        XCTAssertGreaterThan(Double(result.ticks[1]), self.refreshRate * 0.8)
        XCTAssertGreaterThan(Double(result.deliveries), self.refreshRate * 0.8)
    }
}

final class FrameStepTests: XCTestCase {
    func testSixtyHertzStepsAreUnchanged() {
        XCTAssertEqual(FrameStep.scale(1.0 / 60.0), 1, accuracy: 1e-9)
        XCTAssertEqual(FrameStep.decay(0.9, 1.0 / 60.0), 0.9, accuracy: 1e-9)
        XCTAssertEqual(FrameStep.blend(0.1, 1.0 / 60.0), 0.1, accuracy: 1e-9)
    }

    func testTwoHalfFramesMatchOneFrame() {
        let half: CGFloat = 1.0 / 120.0
        var smoothed: CGFloat = 0
        var target: CGFloat = 1
        for _ in 0 ..< 2 {
            smoothed = smoothed * FrameStep.decay(0.9, half) + target * (1 - FrameStep.decay(0.9, half))
        }
        XCTAssertEqual(smoothed, 0.1, accuracy: 1e-9)
        var chased: CGFloat = 0
        for _ in 0 ..< 2 {
            chased += (target - chased) * FrameStep.blend(0.2, half)
        }
        XCTAssertEqual(chased, 0.2, accuracy: 1e-9)
        target = 0
        XCTAssertEqual(FrameStep.scale(half) * 2, FrameStep.scale(1.0 / 60.0), accuracy: 1e-9)
    }
}
