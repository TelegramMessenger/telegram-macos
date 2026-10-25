import XCTest
@testable import ChatListUI

final class StoryRevealModelTests: XCTestCase {
    private var time: Double = 100

    private func event(_ phase: StoryRevealInput.Phase, dy: CGFloat, dx: CGFloat = 0, momentum: StoryRevealInput.Momentum = .none, precise: Bool = true, dt: Double = 1.0 / 120.0) -> StoryRevealInput {
        self.time += dt
        return StoryRevealInput(phase: phase, momentum: momentum, deltaX: dx, deltaY: dy, precise: precise, time: self.time)
    }

    @discardableResult
    private func drag(_ model: StoryRevealModel, _ deltas: [CGFloat], offset: CGFloat = 0, dt: Double = 1.0 / 120.0, end: Bool = true) -> [StoryRevealModel.Decision] {
        var decisions: [StoryRevealModel.Decision] = []
        for (i, delta) in deltas.enumerated() {
            decisions.append(model.handle(self.event(i == 0 ? .began : .changed, dy: delta, dt: dt), tableOffset: offset))
        }
        if end {
            decisions.append(model.handle(self.event(.ended, dy: 0, dt: dt), tableOffset: offset))
        }
        return decisions
    }

    private func settle(_ model: StoryRevealModel, seconds: Double = 1.0) -> [CGFloat] {
        var values: [CGFloat] = []
        let end = self.time + seconds
        while self.time < end {
            self.time += 1.0 / 120.0
            model.advance(to: self.time)
            values.append(model.fraction)
        }
        return values
    }

    func testPullingAtTheTopTracksTheFingersOneToOne() {
        let model = StoryRevealModel()
        let decisions = self.drag(model, [3, 12, 12, 12, 12, 12], end: false)
        XCTAssertEqual(decisions, Array(repeating: .consumed, count: 6))
        XCTAssertEqual(model.fraction, 63 / StoryRevealModel.span, accuracy: 1e-9)
        XCTAssertTrue(model.isTracking)
        XCTAssertNil(model.spring)
    }

    func testAPartialPullHoldsWhileTheFingersRest() {
        let model = StoryRevealModel()
        self.drag(model, [10, 10, 10, 15], end: false)
        let held = model.fraction
        for _ in 0 ..< 30 {
            XCTAssertEqual(model.handle(self.event(.stationary, dy: 0), tableOffset: 0), .consumed)
        }
        XCTAssertEqual(model.fraction, held, "no auto-finish while the user is still holding")
        XCTAssertNil(model.spring)
    }

    func testSlowReleaseSnapsToTheNearestEnd() {
        let open = StoryRevealModel()
        self.drag(open, [5, 5, 5, 5, 5, 5, 5, 5], dt: 0.05)
        XCTAssertEqual(open.spring?.target, 1)
        XCTAssertEqual(self.settle(open).last, 1)

        let closed = StoryRevealModel()
        self.drag(closed, [5, 5, 5, 5, 5], dt: 0.05)
        XCTAssertEqual(closed.spring?.target, 0)
        XCTAssertEqual(self.settle(closed).last, 0)
    }

    func testAFlickDecidesByVelocityNotByDistance() {
        let model = StoryRevealModel()
        self.drag(model, [2, 6, 7], dt: 1.0 / 120.0)
        XCTAssertLessThan(model.fraction, 0.5)
        XCTAssertEqual(model.spring?.target, 1, "a quick short pull opens the stories")

        let revealed = StoryRevealModel(revealed: true)
        self.drag(revealed, [-4, -5, -5], dt: 1.0 / 120.0)
        XCTAssertGreaterThan(revealed.fraction, 0.5)
        XCTAssertNotNil(revealed.glide, "a quick short push closes them")
        XCTAssertNil(revealed.spring)
    }

    func testCollapsingHandsTheRestOfTheGestureToTheList() {
        let model = StoryRevealModel(revealed: true)
        let decisions = self.drag(model, [-20, -20, -20, -20, -20, -20], end: false)
        XCTAssertEqual(Array(decisions.prefix(4)), [.consumed, .consumed, .consumed, .consumed])
        XCTAssertEqual(model.fraction, 0)
        XCTAssertEqual(Array(decisions.suffix(2)), [.passThrough, .passThrough], "once collapsed, the same gesture scrolls the list")
        XCTAssertFalse(model.isTracking)
    }

    func testOneGestureCanOpenCloseAndReopen() {
        let model = StoryRevealModel()
        self.drag(model, [15, 15, 15], end: false)
        XCTAssertEqual(model.fraction, 45 / StoryRevealModel.span, accuracy: 1e-9)
        XCTAssertEqual(model.handle(self.event(.changed, dy: -30), tableOffset: 0), .consumed)
        XCTAssertEqual(model.fraction, 15 / StoryRevealModel.span, accuracy: 1e-9)
        XCTAssertEqual(model.handle(self.event(.changed, dy: -30), tableOffset: 0), .consumed)
        XCTAssertEqual(model.fraction, 0)
        XCTAssertEqual(model.handle(self.event(.changed, dy: -5), tableOffset: 0), .passThrough)
        XCTAssertEqual(model.handle(self.event(.changed, dy: 10), tableOffset: 0), .consumed)
        XCTAssertEqual(model.fraction, 10 / StoryRevealModel.span, accuracy: 1e-9)
    }

    func testPullingDownWhileFullyRevealedHandsTheGestureToTheList() {
        let model = StoryRevealModel(revealed: true)
        let decisions = self.drag(model, [10, 10, 10, 10], end: false)
        XCTAssertEqual(decisions, Array(repeating: .passThrough, count: 4))
        XCTAssertEqual(model.fraction, 1)
        XCTAssertFalse(model.isTracking)
        XCTAssertEqual(model.handle(self.event(.ended, dy: 0), tableOffset: -20), .passThrough)
        XCTAssertNil(model.spring)
    }

    func testAnEmptyFirstEventWhileFullyRevealedGoesToTheList() {
        let model = StoryRevealModel(revealed: true)
        XCTAssertEqual(model.handle(self.event(.began, dy: 0), tableOffset: 0), .passThrough)
        XCTAssertEqual(model.handle(self.event(.changed, dy: 10), tableOffset: 0), .passThrough)
        XCTAssertEqual(model.fraction, 1)
    }

    func testPullingUpAfterPullingDownStillClosesTheStories() {
        let model = StoryRevealModel(revealed: true)
        XCTAssertEqual(model.handle(self.event(.began, dy: 10), tableOffset: 0), .passThrough)
        XCTAssertEqual(model.handle(self.event(.changed, dy: -30), tableOffset: 0), .consumed)
        XCTAssertEqual(model.fraction, 1 - 30 / StoryRevealModel.span, accuracy: 1e-9)
        XCTAssertEqual(model.handle(self.event(.changed, dy: 30), tableOffset: 0), .consumed)
        XCTAssertEqual(model.fraction, 1, accuracy: 1e-9)
    }

    func testOpeningStoriesInOneGestureKeepsDrivingTheHeader() {
        let model = StoryRevealModel()
        let decisions = self.drag(model, [40, 40, 40, 40], end: false)
        XCTAssertEqual(decisions, Array(repeating: .consumed, count: 4))
        XCTAssertEqual(model.fraction, 1)
    }

    func testAGestureThatStartsBelowTheTopNeverReveals() {
        let model = StoryRevealModel()
        var offset: CGFloat = 60
        XCTAssertEqual(model.handle(self.event(.began, dy: 10), tableOffset: offset), .passThrough)
        for _ in 0 ..< 12 {
            offset = max(0, offset - 10)
            XCTAssertEqual(model.handle(self.event(.changed, dy: 10), tableOffset: offset), .passThrough)
        }
        XCTAssertEqual(model.fraction, 0)
        XCTAssertEqual(model.handle(self.event(.ended, dy: 0), tableOffset: 0), .passThrough)
        XCTAssertNil(model.spring)
    }

    func testScrollingAwayInsideAGestureForgetsThatItStartedAtTheTop() {
        let model = StoryRevealModel()
        XCTAssertEqual(model.handle(self.event(.began, dy: -10), tableOffset: 0), .passThrough)
        XCTAssertEqual(model.handle(self.event(.changed, dy: -10), tableOffset: 20), .passThrough)
        XCTAssertEqual(model.handle(self.event(.changed, dy: 10), tableOffset: 10), .passThrough)
        XCTAssertEqual(model.handle(self.event(.changed, dy: 10), tableOffset: 0), .passThrough)
        XCTAssertEqual(model.handle(self.event(.changed, dy: 10), tableOffset: 0), .passThrough)
        XCTAssertEqual(model.fraction, 0)
    }

    func testMomentumNeverReveals() {
        let model = StoryRevealModel()
        self.drag(model, [-10, 10], offset: 300)
        XCTAssertEqual(model.handle(self.event(.none, dy: 30, momentum: .began), tableOffset: 0), .passThrough)
        for _ in 0 ..< 20 {
            XCTAssertEqual(model.handle(self.event(.none, dy: 20, momentum: .changed), tableOffset: 0), .passThrough)
        }
        XCTAssertEqual(model.fraction, 0)
        XCTAssertNil(model.spring)
    }

    func testMomentumAfterOpeningIsSwallowedSoTheListDoesNotBounce() {
        let model = StoryRevealModel()
        self.drag(model, [20, 20, 20, 20])
        XCTAssertEqual(model.fraction, 1)
        XCTAssertEqual(model.handle(self.event(.none, dy: 15, momentum: .began), tableOffset: 0), .consumed)
        XCTAssertEqual(model.handle(self.event(.none, dy: 10, momentum: .changed), tableOffset: 0), .consumed)
        XCTAssertEqual(model.fraction, 1)
    }

    private func glide(_ model: StoryRevealModel, seconds: Double = 3.0) -> [(fraction: CGFloat, offset: CGFloat)] {
        var values: [(CGFloat, CGFloat)] = []
        var offset: CGFloat = 0
        let end = self.time + seconds
        while self.time < end {
            self.time += 1.0 / 120.0
            model.advance(to: self.time)
            offset += model.takeTableDelta() ?? 0
            values.append((model.fraction, offset))
        }
        return values
    }

    func testAFlickUpClosesTheStoriesAndGlidesTheList() {
        let model = StoryRevealModel(revealed: true)
        let decisions = self.drag(model, [-6, -8, -10])
        XCTAssertEqual(decisions.last, .consumed)
        XCTAssertNil(model.spring)
        guard let glide = model.glide else {
            return XCTFail("a flick up glides")
        }
        XCTAssertEqual(glide.fromFraction, 1 - 24 / StoryRevealModel.span, accuracy: 1e-9)
        XCTAssertEqual(model.handle(self.event(.none, dy: -12, momentum: .began), tableOffset: 0), .consumed, "the glide owns the motion, so system momentum cannot scroll the list a second time")
        let values = self.glide(model)
        XCTAssertEqual(values.last?.fraction, 0)
        XCTAssertEqual(values.last?.offset ?? 0, glide.totalDistance - glide.fromFraction * StoryRevealModel.span, accuracy: 0.01)
        XCTAssertGreaterThan(values.last?.offset ?? 0, 200)
        XCTAssertNil(model.glide)
        XCTAssertTrue(model.isSettledConcealed)
    }

    func testTheGlideIsOneContinuousDeceleration() {
        let model = StoryRevealModel(revealed: true)
        self.drag(model, [-6, -8, -10])
        let values = self.glide(model)
        var travel: [CGFloat] = [24]
        for value in values {
            travel.append((1 - value.fraction) * StoryRevealModel.span + value.offset)
        }
        var lastStep = CGFloat.greatestFiniteMagnitude
        for i in 1 ..< travel.count {
            let step = travel[i] - travel[i - 1]
            XCTAssertGreaterThanOrEqual(step, -1e-9, "never moves back")
            XCTAssertLessThanOrEqual(step, lastStep + 1e-6, "only slows down, also where the stories hand over to the list")
            lastStep = step
        }
        XCTAssertLessThan(travel[1] - travel[0], 1440.0 / 120.0 + 0.5, "starts at the speed of the fingers")
    }

    func testAFlickThatClosesOnItsLastEventStillGlides() {
        let model = StoryRevealModel(revealed: true)
        let decisions = self.drag(model, [-30, -30, -30])
        XCTAssertEqual(model.fraction, 0)
        XCTAssertEqual(decisions.last, .consumed)
        XCTAssertEqual(model.glide?.fromFraction, 0)
        XCTAssertGreaterThan(self.glide(model).last?.offset ?? 0, 300)
    }

    func testASlowCloseSnapsWithoutGliding() {
        let model = StoryRevealModel(revealed: true)
        self.drag(model, [-5, -5, -5, -5, -5, -5, -5, -5, -5], dt: 0.05)
        XCTAssertNil(model.glide)
        XCTAssertEqual(model.spring?.target, 0)
        XCTAssertNil(self.glide(model).first { $0.offset != 0 }, "a snap never scrolls the list")
    }

    func testTouchingTheTrackpadStopsAGlide() {
        let model = StoryRevealModel(revealed: true)
        self.drag(model, [-6, -8, -10])
        _ = self.glide(model, seconds: 0.2)
        let fraction = model.fraction
        XCTAssertEqual(model.handle(self.event(.mayBegin, dy: 0), tableOffset: 50), .passThrough)
        XCTAssertNil(model.glide)
        XCTAssertFalse(model.isAnimating)
        XCTAssertEqual(model.fraction, 0)
        XCTAssertEqual(fraction, 0)
        XCTAssertNotNil(model.takeTableDelta(), "the motion up to the touch is applied")
        XCTAssertNil(model.takeTableDelta())
    }

    func testTheMouseWheelStopsAGlide() {
        let model = StoryRevealModel(revealed: true)
        self.drag(model, [-6, -8, -10])
        _ = self.glide(model, seconds: 0.01)
        XCTAssertGreaterThan(model.fraction, 0)
        _ = model.handle(self.event(.none, dy: -1, precise: false), tableOffset: 0)
        XCTAssertNil(model.glide)
        XCTAssertEqual(model.spring?.target, 0, "the wheel finishes closing")
    }

    func testSettingTheStateStopsAGlide() {
        let model = StoryRevealModel(revealed: true)
        self.drag(model, [-6, -8, -10])
        model.setRevealed(true, animated: true, time: self.time)
        XCTAssertNil(model.glide)
        XCTAssertEqual(model.spring?.target, 1)
        XCTAssertNil(model.takeTableDelta())
    }

    func testGlideConstantsMatchNativeMomentum() {
        XCTAssertEqual(StoryRevealGlide.timeConstant, 0.4995, accuracy: 0.001)
        let glide = StoryRevealGlide(start: 0, fromFraction: 1, fromOffset: 0, speed: 1000)
        XCTAssertEqual(glide.totalDistance, 1000 * StoryRevealGlide.timeConstant * (1 - 15.0 / 1000.0), accuracy: 0.01)
        XCTAssertEqual(glide.fraction(at: 0), 1)
        XCTAssertEqual(glide.tableOffset(at: 0), 0)
        XCTAssertEqual(glide.tableOffset(at: glide.duration), glide.totalDistance - StoryRevealModel.span, accuracy: 0.01)
        XCTAssertTrue(glide.isFinished(at: glide.duration))
    }

    func testMomentumWhileSnappingOpenIsSwallowed() {
        let model = StoryRevealModel()
        self.drag(model, [5, 5, 5, 5, 5, 5, 5, 5], dt: 0.05)
        XCTAssertEqual(model.spring?.target, 1)
        XCTAssertEqual(model.handle(self.event(.none, dy: 4, momentum: .changed), tableOffset: 0), .consumed)
        XCTAssertEqual(model.handle(self.event(.none, dy: -4, momentum: .changed), tableOffset: 0), .consumed)
    }

    func testMouseWheelSnapsOpenAndClosed() {
        let model = StoryRevealModel()
        XCTAssertEqual(model.handle(self.event(.none, dy: 4, precise: false), tableOffset: 0), .consumed)
        XCTAssertEqual(model.spring?.target, 1)
        XCTAssertEqual(model.handle(self.event(.none, dy: 4, precise: false), tableOffset: 0), .consumed)
        XCTAssertEqual(self.settle(model).last, 1)
        XCTAssertEqual(model.handle(self.event(.none, dy: -4, precise: false), tableOffset: 0), .consumed)
        XCTAssertEqual(model.spring?.target, 0)
        XCTAssertEqual(model.handle(self.event(.none, dy: -4, precise: false), tableOffset: 0), .passThrough, "further notches scroll the list while the stories close")
        XCTAssertEqual(self.settle(model).last, 0)
        XCTAssertEqual(model.handle(self.event(.none, dy: -4, precise: false), tableOffset: 0), .passThrough)
    }

    func testMouseWheelBelowTheTopScrollsTheList() {
        let model = StoryRevealModel()
        XCTAssertEqual(model.handle(self.event(.none, dy: 4, precise: false), tableOffset: 40), .passThrough)
        XCTAssertNil(model.spring)
    }

    func testHorizontalGesturesAreLeftAlone() {
        let model = StoryRevealModel()
        XCTAssertEqual(model.handle(self.event(.began, dy: 1, dx: 8), tableOffset: 0), .passThrough)
        XCTAssertEqual(model.axis, .horizontal)
        for _ in 0 ..< 10 {
            XCTAssertEqual(model.handle(self.event(.changed, dy: 6, dx: 2), tableOffset: 0), .passThrough, "the axis is locked for the whole gesture")
        }
        XCTAssertEqual(model.fraction, 0)
    }

    func testDiagonalGesturesLockToTheDominantAxis() {
        let model = StoryRevealModel()
        XCTAssertEqual(model.handle(self.event(.began, dy: 6, dx: 4), tableOffset: 0), .consumed)
        XCTAssertEqual(model.axis, .vertical)
        XCTAssertEqual(model.handle(self.event(.changed, dy: 1, dx: 9), tableOffset: 0), .consumed)
        XCTAssertEqual(model.fraction, 7 / StoryRevealModel.span, accuracy: 1e-9, "only the vertical component drives the stories")
    }

    func testAnEmptyFirstEventDoesNotDecideTheAxis() {
        let model = StoryRevealModel()
        XCTAssertEqual(model.handle(self.event(.began, dy: 0), tableOffset: 0), .consumed, "at the top the gesture is held back from the list until its direction is known")
        XCTAssertEqual(model.axis, .undecided)
        XCTAssertEqual(model.handle(self.event(.changed, dy: 5), tableOffset: 0), .consumed)
        XCTAssertEqual(model.axis, .vertical)
    }

    func testAnEmptyFirstEventBelowTheTopGoesStraightToTheList() {
        let model = StoryRevealModel()
        XCTAssertEqual(model.handle(self.event(.began, dy: 0), tableOffset: 40), .passThrough)
        XCTAssertEqual(model.handle(self.event(.changed, dy: 5), tableOffset: 40), .passThrough)
        XCTAssertEqual(model.fraction, 0)
    }

    func testTouchingTheTrackpadCatchesASnapMidway() {
        let model = StoryRevealModel()
        self.drag(model, [5, 5, 5, 5, 5, 5, 5, 5], dt: 0.05)
        let from = model.fraction
        self.time += 0.06
        XCTAssertEqual(model.handle(self.event(.mayBegin, dy: 0, dt: 0), tableOffset: 0), .passThrough)
        XCTAssertNil(model.spring)
        XCTAssertGreaterThan(model.fraction, from)
        XCTAssertLessThan(model.fraction, 1)
        let caught = model.fraction
        XCTAssertEqual(model.handle(self.event(.began, dy: -6), tableOffset: 0), .consumed)
        XCTAssertEqual(model.fraction, caught - 6 / StoryRevealModel.span, accuracy: 1e-9, "the new gesture continues from where the snap was caught")
    }

    func testLiftingTheFingersAfterCatchingASnapFinishesIt() {
        let model = StoryRevealModel()
        self.drag(model, [5, 5, 5, 5, 5, 5, 5, 5], dt: 0.05)
        XCTAssertEqual(model.spring?.target, 1)
        self.time += 0.06
        _ = model.handle(self.event(.mayBegin, dy: 0, dt: 0), tableOffset: 0)
        XCTAssertNil(model.spring, "resting fingers hold the stories where they are")
        let held = model.fraction
        XCTAssertEqual(model.handle(self.event(.cancelled, dy: 0), tableOffset: 0), .passThrough)
        XCTAssertEqual(model.spring?.target, 1, "lifting them finishes the snap that was caught")
        XCTAssertEqual(model.spring?.from ?? 0, held, accuracy: 1e-9)
        XCTAssertEqual(self.settle(model).last, 1)
    }

    func testLiftingTheFingersAfterCatchingAGlideFinishesClosing() {
        let model = StoryRevealModel(revealed: true)
        self.drag(model, [-6, -8, -10])
        _ = self.glide(model, seconds: 0.01)
        XCTAssertGreaterThan(model.fraction, 0)
        _ = model.handle(self.event(.mayBegin, dy: 0, dt: 0), tableOffset: 0)
        XCTAssertFalse(model.isAnimating)
        _ = model.handle(self.event(.cancelled, dy: 0), tableOffset: 0)
        XCTAssertEqual(model.spring?.target, 0)
        XCTAssertEqual(self.settle(model).last, 0)
    }

    func testASidewaysSwipeAfterCatchingASnapLetsItFinish() {
        let model = StoryRevealModel()
        self.drag(model, [5, 5, 5, 5, 5, 5, 5, 5], dt: 0.05)
        self.time += 0.06
        _ = model.handle(self.event(.mayBegin, dy: 0, dt: 0), tableOffset: 0)
        XCTAssertEqual(model.handle(self.event(.began, dy: 1, dx: 9), tableOffset: 0), .passThrough)
        XCTAssertEqual(model.spring?.target, 1, "the scroll view takes that gesture, so the model never sees it end")
    }

    func testDisablingKeepsARunningAnimationGoing() {
        let model = StoryRevealModel(revealed: true)
        model.setRevealed(false, animated: true, time: self.time)
        _ = self.settle(model, seconds: 0.05)
        model.enabled = false
        XCTAssertEqual(model.spring?.target, 0)
        XCTAssertEqual(model.handle(self.event(.began, dy: 10), tableOffset: 0), .passThrough)
        XCTAssertEqual(self.settle(model).last, 0)
        XCTAssertTrue(model.isSettledConcealed)
    }

    func testDisablingMidGestureSettlesTheStories() {
        let model = StoryRevealModel()
        self.drag(model, [10, 10, 10], end: false)
        XCTAssertTrue(model.isTracking)
        model.enabled = false
        XCTAssertFalse(model.isTracking)
        XCTAssertEqual(model.spring?.target, 0)
        XCTAssertEqual(self.settle(model).last, 0)
    }

    func testPresentationFollowsWhatIsOnScreen() {
        let model = StoryRevealModel()
        XCTAssertEqual(model.presentation, .concealed)
        self.drag(model, [15, 15], end: false)
        XCTAssertEqual(model.presentation, .moving(fraction: 30 / StoryRevealModel.span, opening: false, tracking: true))
        _ = model.handle(self.event(.changed, dy: 60), tableOffset: 0)
        XCTAssertEqual(model.presentation, .moving(fraction: 1, opening: true, tracking: true), "fully pulled but still held")
        _ = model.handle(self.event(.ended, dy: 0), tableOffset: 0)
        XCTAssertEqual(model.presentation, .revealed)
        self.drag(model, [-6, -8, -10])
        guard case let .moving(_, opening, tracking) = model.presentation else {
            return XCTFail("closing")
        }
        XCTAssertFalse(opening)
        XCTAssertFalse(tracking)
        let values = self.glide(model, seconds: 0.3)
        XCTAssertEqual(values.last?.fraction, 0)
        XCTAssertNotNil(model.glide, "still scrolling the list")
        XCTAssertEqual(model.presentation, .concealed, "the header is closed while the list glides, so the folder bar scrolls again")
    }

    func testGlideDeltasAddUpToTheListPartOfTheGlide() {
        let model = StoryRevealModel(revealed: true)
        self.drag(model, [-6, -8, -10])
        guard let glide = model.glide else {
            return XCTFail("glides")
        }
        let values = self.glide(model)
        XCTAssertEqual(values.last?.offset ?? 0, glide.totalDistance - glide.fromFraction * StoryRevealModel.span, accuracy: 1e-6)
    }

    func testATouchWithAnOlderTimestampNeverMovesAGlideBackwards() {
        let model = StoryRevealModel(revealed: true)
        self.drag(model, [-6, -8, -10])
        _ = self.glide(model, seconds: 0.3)
        let fraction = model.fraction
        XCTAssertEqual(model.handle(StoryRevealInput(phase: .mayBegin, momentum: .none, deltaX: 0, deltaY: 0, precise: true, time: self.time - 0.02), tableOffset: 80), .passThrough)
        XCTAssertNil(model.glide)
        XCTAssertGreaterThanOrEqual(model.takeTableDelta() ?? 0, 0)
        XCTAssertLessThanOrEqual(model.fraction, fraction)
    }

    func testATouchBelowTheTopDoesNotPauseTheScrollAwayCollapse() {
        let model = StoryRevealModel(revealed: true)
        model.tableDidScroll(offset: 40, time: self.time)
        XCTAssertEqual(model.spring?.target, 0)
        _ = model.handle(self.event(.mayBegin, dy: 0), tableOffset: 40)
        XCTAssertEqual(model.spring?.target, 0, "the list is being scrolled away, the collapse keeps going")
        _ = model.handle(self.event(.began, dy: -10), tableOffset: 50)
        XCTAssertEqual(model.spring?.target, 0)
        XCTAssertEqual(self.settle(model).last, 0)
    }

    func testDisablingLongAfterTheLastEventStillAnimates() {
        let model = StoryRevealModel()
        self.drag(model, [10, 10, 10], end: false)
        self.time += 5
        model.advance(to: self.time)
        model.enabled = false
        XCTAssertEqual(model.spring?.start ?? 0, self.time, accuracy: 1e-9, "the settle starts now instead of in the past")
        XCTAssertFalse(model.spring?.isSettled(at: self.time + 1.0 / 120.0) ?? true)
    }

    func testFinishingAStrandedHeaderContinuesTheCaughtCollapse() {
        let model = StoryRevealModel(revealed: true)
        model.setRevealed(false, animated: true, time: self.time)
        _ = self.settle(model, seconds: 0.03)
        XCTAssertGreaterThan(model.fraction, 0.5)
        _ = model.handle(self.event(.mayBegin, dy: 0, dt: 0), tableOffset: 0)
        XCTAssertNil(model.spring)
        model.finishIfPartial(time: self.time)
        XCTAssertEqual(model.spring?.target, 0, "the caught collapse continues even though the stories are more than half open")
    }

    func testANewSpringForgetsAnOlderCatch() {
        let model = StoryRevealModel(revealed: true)
        model.setRevealed(false, animated: true, time: self.time)
        _ = self.settle(model, seconds: 0.03)
        _ = model.handle(self.event(.mayBegin, dy: 0, dt: 0), tableOffset: 0)
        _ = model.handle(self.event(.none, dy: 1, precise: false), tableOffset: 0)
        XCTAssertEqual(model.spring?.target, 1, "the wheel reopens")
        _ = self.settle(model, seconds: 0.03)
        _ = model.handle(self.event(.mayBegin, dy: 0, dt: 0), tableOffset: 0)
        _ = model.handle(self.event(.cancelled, dy: 0), tableOffset: 0)
        XCTAssertEqual(model.spring?.target, 1, "resumes the wheel's reopen, not the collapse caught before it")
    }

    func testSpringsAreCriticallyDampedAndQuick() {
        for (from, target, velocity) in [(CGFloat(0.3), CGFloat(1), 0.0), (1, 0, 0), (0.6, 1, 8.0), (0.4, 0, -10.0), (0.45, 1, -3.0)] {
            let model = StoryRevealModel()
            model.setRevealed(from >= 0.5, animated: false, time: self.time)
            let spring = StoryRevealSpring(omega: target > from ? StoryRevealSpring.omegaReveal : StoryRevealSpring.omegaCollapse, target: target, from: from, velocity: velocity, start: self.time)
            var previous = from
            var settledAt: Double?
            var t = self.time
            while t < self.time + 1.5 {
                t += 1.0 / 240.0
                let value = spring.value(at: t)
                let overshoot = target >= from ? value - target : target - value
                XCTAssertLessThan(overshoot * StoryRevealModel.span, 0.5, "never visibly passes the target")
                if velocity * Double(target - from) >= 0, abs(value - target) > 0.01 {
                    if target >= from {
                        XCTAssertGreaterThanOrEqual(value, previous - 1e-9, "monotonic toward the target")
                    } else {
                        XCTAssertLessThanOrEqual(value, previous + 1e-9, "monotonic toward the target")
                    }
                }
                previous = value
                if settledAt == nil, spring.isSettled(at: t) {
                    settledAt = t - self.time
                }
            }
            XCTAssertNotNil(settledAt)
            XCTAssertLessThan(settledAt ?? 9, 0.55, "settles fast from \(from) to \(target)")
        }
    }

    func testAdvanceKeepsTheFractionInRangeAndFinishes() {
        let model = StoryRevealModel()
        self.drag(model, [4, 12, 16], dt: 1.0 / 120.0)
        XCTAssertEqual(model.spring?.target, 1)
        for value in self.settle(model, seconds: 1.0) {
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 1)
        }
        XCTAssertNil(model.spring)
        XCTAssertTrue(model.isSettledRevealed)
        XCTAssertFalse(model.advance(to: self.time + 1))
    }

    func testScrollingTheListAwayClosesTheStories() {
        let model = StoryRevealModel(revealed: true)
        model.tableDidScroll(offset: 2, time: self.time)
        XCTAssertNil(model.spring)
        model.tableDidScroll(offset: 12, time: self.time)
        XCTAssertEqual(model.spring?.target, 0)
        XCTAssertEqual(self.settle(model).last, 0)
    }

    func testProgrammaticRevealAndConceal() {
        let model = StoryRevealModel()
        model.setRevealed(true, animated: true, time: self.time)
        XCTAssertEqual(model.spring?.target, 1)
        XCTAssertEqual(self.settle(model).last, 1)
        model.setRevealed(false, animated: false, time: self.time)
        XCTAssertNil(model.spring)
        XCTAssertEqual(model.fraction, 0)
        model.setRevealed(false, animated: true, time: self.time)
        XCTAssertNil(model.spring, "already concealed: nothing to animate")
    }

    func testDisabledModelPassesEverything() {
        let model = StoryRevealModel()
        model.enabled = false
        XCTAssertEqual(model.handle(self.event(.began, dy: 20), tableOffset: 0), .passThrough)
        XCTAssertEqual(model.handle(self.event(.none, dy: 4, precise: false), tableOffset: 0), .passThrough)
        XCTAssertEqual(model.fraction, 0)
    }

    func testPreciseEventsWithoutPhasesBehaveLikeTheWheel() {
        let model = StoryRevealModel()
        XCTAssertEqual(model.handle(self.event(.none, dy: -3, precise: true), tableOffset: 0), .passThrough)
        XCTAssertEqual(model.handle(self.event(.none, dy: 1, dx: 6, precise: true), tableOffset: 0), .passThrough)
        XCTAssertEqual(model.handle(self.event(.none, dy: 3, precise: true), tableOffset: 0), .consumed)
        XCTAssertEqual(model.spring?.target, 1)
    }
}
