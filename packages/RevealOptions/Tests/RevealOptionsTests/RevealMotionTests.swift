import XCTest
import AppKit
@testable import RevealOptions

final class RevealMotionTests: XCTestCase {
    private func parameters(count: Int = 3, width: Double = 320, isDestructive: Bool = false) -> RevealMotionParameters {
        return RevealMotionParameters(width: width, buttonWidth: 50, spacing: 10, edgeInset: 10, sideInset: 0, count: count, isDestructive: isDestructive, displayScale: 2)
    }

    private func settle(_ motion: inout RevealMotion) {
        for _ in 0 ..< 600 {
            motion.advance(by: 1.0 / 60.0)
        }
    }

    func testOpenDistanceCoversEveryButton() {
        XCTAssertEqual(parameters(count: 3).openDistance, 190)
        XCTAssertEqual(parameters(count: 1).openDistance, 70)
        XCTAssertEqual(parameters(count: 0).openDistance, 0)
    }

    func testConfirmationDistanceDependsOnTheDestructivePrimary() {
        XCTAssertEqual(parameters(width: 320).confirmationDistance, 210)
        XCTAssertEqual(parameters(width: 320, isDestructive: true).confirmationDistance, 291)
        XCTAssertEqual(parameters(width: 320).armedDistance, 240)
    }

    func testButtonsAreFullyRevealedAtTheOpenDistance() {
        let p = parameters()
        let geometry = RevealButtonGeometry.calculate(reveal: p.openDistance, expansion: 0, parameters: p)
        XCTAssertEqual(geometry.map(\.scale), [1, 1, 1])
        XCTAssertEqual(geometry.map(\.center), [35, 95, 155])
    }

    func testOuterButtonsRevealLaterThanThePrimary() {
        let p = parameters()
        let geometry = RevealButtonGeometry.calculate(reveal: 110, expansion: 0, parameters: p)
        XCTAssertEqual(geometry[0].scale, 1)
        XCTAssertGreaterThan(geometry[1].scale, 0)
        XCTAssertLessThan(geometry[1].scale, 1)
        XCTAssertEqual(geometry[2].scale, 0)
    }

    func testOverswipeStretchesThePrimaryAndConsolidationHidesTheOthers() {
        let p = parameters()
        let stretched = RevealButtonGeometry.calculate(reveal: 230, expansion: 0, parameters: p)
        XCTAssertEqual(stretched[0].width, 90)
        XCTAssertEqual(stretched[1].center, 135)
        let consolidated = RevealButtonGeometry.calculate(reveal: 230, expansion: 1, parameters: p)
        XCTAssertEqual(consolidated[0].width, 210)
        XCTAssertEqual(consolidated[1].scale, 0)
        XCTAssertEqual(consolidated[2].opacity, 0)
    }

    func testDestructivePrimaryNeverConsolidates() {
        let p = parameters(isDestructive: true)
        let geometry = RevealButtonGeometry.calculate(reveal: 230, expansion: 1, parameters: p)
        XCTAssertEqual(geometry[0].width, 90)
        XCTAssertGreaterThan(geometry[1].scale, 0)
    }

    func testShortDragSettlesClosed() {
        var motion = RevealMotion()
        motion.configure(parameters())
        motion.begin()
        motion.change(translation: 40, velocity: 0, distanceFromCommitEdge: .greatestFiniteMagnitude)
        XCTAssertEqual(motion.body.value, 40)
        let commit = motion.end(translation: 40, velocity: 0, cancelled: false)
        XCTAssertFalse(commit)
        settle(&motion)
        XCTAssertEqual(motion.state, .closed)
        XCTAssertEqual(motion.body.value, 0)
    }

    func testDragPastHalfTheOpenDistanceSettlesOpen() {
        var motion = RevealMotion()
        motion.configure(parameters())
        motion.begin()
        motion.change(translation: 120, velocity: 0, distanceFromCommitEdge: .greatestFiniteMagnitude)
        XCTAssertFalse(motion.end(translation: 120, velocity: 0, cancelled: false))
        settle(&motion)
        XCTAssertEqual(motion.state, .open)
        XCTAssertEqual(motion.body.value, 190)
    }

    func testFlickDecidesTheDirection() {
        var motion = RevealMotion()
        motion.configure(parameters())
        motion.begin()
        motion.change(translation: 60, velocity: 400, distanceFromCommitEdge: .greatestFiniteMagnitude)
        _ = motion.end(translation: 60, velocity: 400, cancelled: false)
        settle(&motion)
        XCTAssertEqual(motion.state, .open)
    }

    func testCrossingTheConfirmationDistanceArmsAndCommits() {
        var motion = RevealMotion()
        motion.configure(parameters())
        motion.begin()
        motion.change(translation: 230, velocity: 0, distanceFromCommitEdge: .greatestFiniteMagnitude)
        XCTAssertTrue(motion.isArmed)
        XCTAssertTrue(motion.isExpanded)
        XCTAssertGreaterThan(motion.body.target, 240)
        XCTAssertTrue(motion.end(translation: 230, velocity: 0, cancelled: false))
        settle(&motion)
        XCTAssertEqual(motion.state, .open)
    }

    func testRowFollowsTheFingerAfterArmingAndDisarming() {
        var motion = RevealMotion()
        motion.configure(parameters())
        motion.begin()
        motion.change(translation: 100, velocity: 0, distanceFromCommitEdge: .greatestFiniteMagnitude)
        XCTAssertEqual(motion.body.value, 100, accuracy: 0.001)
        motion.change(translation: 230, velocity: 0, distanceFromCommitEdge: .greatestFiniteMagnitude)
        XCTAssertTrue(motion.isArmed)
        settle(&motion)
        XCTAssertEqual(motion.body.value, motion.body.target, accuracy: 0.001)
        motion.change(translation: 150, velocity: 0, distanceFromCommitEdge: .greatestFiniteMagnitude)
        XCTAssertFalse(motion.isArmed)
        settle(&motion)
        XCTAssertEqual(motion.body.value, 150, accuracy: 0.001)
        motion.change(translation: 120, velocity: 0, distanceFromCommitEdge: .greatestFiniteMagnitude)
        XCTAssertEqual(motion.body.value, 120, accuracy: 0.001)
        motion.change(translation: 170, velocity: 0, distanceFromCommitEdge: .greatestFiniteMagnitude)
        XCTAssertEqual(motion.body.value, 170, accuracy: 0.001)
    }

    func testArmingStillAnimatesTheJumpForward() {
        var motion = RevealMotion()
        motion.configure(parameters())
        motion.begin()
        motion.change(translation: 200, velocity: 0, distanceFromCommitEdge: .greatestFiniteMagnitude)
        motion.change(translation: 230, velocity: 0, distanceFromCommitEdge: .greatestFiniteMagnitude)
        XCTAssertTrue(motion.isArmed)
        XCTAssertEqual(motion.body.target - motion.body.value, 30, accuracy: 0.001)
    }

    func testShortTitlesKeepTheStandardSpacing() {
        let metrics = RevealOptionLayoutMetrics.metrics(for: 70, hasVisualIcons: true, scale: 0.8, titleFont: .systemFont(ofSize: 11, weight: .medium))
        XCTAssertEqual(metrics.shapeSize.width, 40, accuracy: 0.001)
        let spaced = metrics.withTitleWidths([17, 35, 41])
        XCTAssertEqual(spaced.spacing, 8, accuracy: 0.001)
        XCTAssertEqual(spaced.edgeInset, 8, accuracy: 0.001)
    }

    func testLongTitlesSpreadTheButtonsInsteadOfOverlapping() {
        let metrics = RevealOptionLayoutMetrics.metrics(for: 70, hasVisualIcons: true, scale: 0.8, titleFont: .systemFont(ofSize: 11, weight: .medium))
        let spaced = metrics.withTitleWidths([59, 78])
        XCTAssertEqual(spaced.spacing, 34, accuracy: 0.001)
        XCTAssertEqual(spaced.edgeInset, 22, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(spaced.shapeSize.width + spaced.spacing, (59 + 78) / 2)
    }

    func testPillSizingWidensEveryShapeToTheWidestTitle() {
        let metrics = RevealOptionLayoutMetrics.metrics(for: 70, hasVisualIcons: true, scale: 0.8, titleFont: .systemFont(ofSize: 11 * 0.8))
        let pills = metrics.withGroupTitleWidth(60.8)
        XCTAssertEqual(pills.shapeSize.width, 68, accuracy: 0.001)
        XCTAssertEqual(pills.shapeSize.height, 40, accuracy: 0.001)
        XCTAssertEqual(pills.spacing, 8, accuracy: 0.001)
        XCTAssertEqual(metrics.withGroupTitleWidth(30).shapeSize.width, 40, accuracy: 0.001)
    }

    func testCancelledGestureNeverCommits() {
        var motion = RevealMotion()
        motion.configure(parameters())
        motion.begin()
        motion.change(translation: 260, velocity: 0, distanceFromCommitEdge: .greatestFiniteMagnitude)
        XCTAssertFalse(motion.end(translation: 260, velocity: 0, cancelled: true))
    }

    func testRegrabbingAnOpenRowAndDraggingBackCloses() {
        var motion = RevealMotion()
        motion.configure(parameters())
        motion.settle(to: motion.parameters.openDistance, velocity: 0, animated: false)
        XCTAssertEqual(motion.state, .open)
        motion.begin()
        motion.change(translation: -150, velocity: 0, distanceFromCommitEdge: .greatestFiniteMagnitude)
        XCTAssertEqual(motion.body.value, 40, accuracy: 0.001)
        _ = motion.end(translation: -150, velocity: 0, cancelled: false)
        settle(&motion)
        XCTAssertEqual(motion.state, .closed)
    }

    func testDraggingTheWrongWayIsResisted() {
        var motion = RevealMotion()
        motion.configure(parameters())
        motion.begin()
        motion.change(translation: -100, velocity: 0, distanceFromCommitEdge: .greatestFiniteMagnitude)
        XCTAssertEqual(motion.body.value, -pow(100, 0.7), accuracy: 0.001)
    }

    func testFillSettlesPastTheRowAndStaysFilling() {
        var motion = RevealMotion()
        motion.configure(parameters())
        motion.settle(to: 394, velocity: 0, animated: true, filling: true)
        settle(&motion)
        XCTAssertEqual(motion.state, .filling)
        XCTAssertEqual(motion.body.value, 394)
    }

    func testSurfaceFollowsTheGesture() {
        var motion = RevealMotion()
        motion.configure(parameters())
        motion.begin()
        settle(&motion)
        XCTAssertEqual(motion.surface.value, 1, accuracy: 0.001)
        XCTAssertEqual(motion.surfaceOpacity.value, 1, accuracy: 0.001)
        _ = motion.end(translation: 0, velocity: 0, cancelled: false)
        settle(&motion)
        XCTAssertEqual(motion.surface.value, 0, accuracy: 0.001)
    }
}
