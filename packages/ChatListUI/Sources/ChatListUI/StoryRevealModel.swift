import Foundation
import CoreGraphics

public struct StoryRevealInput: Equatable {
    public enum Phase: Equatable {
        case none
        case mayBegin
        case began
        case changed
        case stationary
        case ended
        case cancelled
    }

    public enum Momentum: Equatable {
        case none
        case began
        case changed
        case ended
    }

    public var phase: Phase
    public var momentum: Momentum
    public var deltaX: CGFloat
    public var deltaY: CGFloat
    public var precise: Bool
    public var time: Double

    public init(phase: Phase, momentum: Momentum, deltaX: CGFloat, deltaY: CGFloat, precise: Bool, time: Double) {
        self.phase = phase
        self.momentum = momentum
        self.deltaX = deltaX
        self.deltaY = deltaY
        self.precise = precise
        self.time = time
    }

    var isWheel: Bool {
        return self.phase == .none && self.momentum == .none
    }
}

public struct StoryRevealSpring: Equatable {
    public var omega: Double
    public var target: CGFloat
    public var from: CGFloat
    public var velocity: Double
    public var start: Double

    public static let omegaReveal: Double = 19.0
    public static let omegaCollapse: Double = 22.0
    public static let tolerance: CGFloat = 0.002

    public func value(at time: Double) -> CGFloat {
        let t = max(0, time - self.start)
        let x0 = Double(self.from - self.target)
        let b = self.velocity + self.omega * x0
        let x = (x0 + b * t) * exp(-self.omega * t)
        return self.target + CGFloat(x)
    }

    public func velocity(at time: Double) -> Double {
        let t = max(0, time - self.start)
        let x0 = Double(self.from - self.target)
        let b = self.velocity + self.omega * x0
        return (b - self.omega * (x0 + b * t)) * exp(-self.omega * t)
    }

    public func isSettled(at time: Double) -> Bool {
        return abs(self.value(at: time) - self.target) <= StoryRevealSpring.tolerance && abs(self.velocity(at: time)) < 0.05
    }
}

public struct StoryRevealGlide: Equatable {
    public var start: Double
    public var fromFraction: CGFloat
    public var fromOffset: CGFloat
    public var speed: Double

    public static let timeConstant: Double = -0.001 / log(0.998)
    public static let stopSpeed: Double = 15

    public init(start: Double, fromFraction: CGFloat, fromOffset: CGFloat, speed: Double) {
        self.start = start
        self.fromFraction = fromFraction
        self.fromOffset = fromOffset
        self.speed = speed
    }

    public var duration: Double {
        return StoryRevealGlide.timeConstant * log(max(1, self.speed / StoryRevealGlide.stopSpeed))
    }

    public var totalDistance: CGFloat {
        return self.distance(at: self.start + self.duration)
    }

    public func distance(at time: Double) -> CGFloat {
        let t = min(max(0, time - self.start), self.duration)
        return CGFloat(self.speed * StoryRevealGlide.timeConstant * (1 - exp(-t / StoryRevealGlide.timeConstant)))
    }

    public func fraction(at time: Double) -> CGFloat {
        return max(0, self.fromFraction - self.distance(at: time) / StoryRevealModel.span)
    }

    public func tableOffset(at time: Double) -> CGFloat {
        return self.fromOffset + max(0, self.distance(at: time) - self.fromFraction * StoryRevealModel.span)
    }

    public func isFinished(at time: Double) -> Bool {
        return time - self.start >= self.duration
    }
}

public final class StoryRevealModel {
    public enum Axis: Equatable {
        case undecided
        case vertical
        case horizontal
    }

    public enum Decision: Equatable {
        case passThrough
        case consumed
    }

    public static let span: CGFloat = 75
    public static let topTolerance: CGFloat = 0.5
    public static let flickVelocity: Double = 350
    public static let velocityWindow: Double = 0.08
    public static let scrolledAwayOffset: CGFloat = 4

    public var enabled: Bool = true {
        didSet {
            if !self.enabled, oldValue {
                self.endGesture()
                if !self.isAnimating, self.fraction > 0, self.fraction < 1 {
                    self.resumeCaught(at: self.lastTime)
                }
            }
        }
    }

    public private(set) var fraction: CGFloat = 0
    public private(set) var spring: StoryRevealSpring?
    public private(set) var glide: StoryRevealGlide?
    private var glideOffset: CGFloat = 0
    private var pendingTableDelta: CGFloat = 0
    private var caughtTarget: CGFloat?
    private var lastTime: Double = 0
    public private(set) var axis: Axis = .undecided
    public private(set) var gestureDrivesHeader: Bool = false
    private var gestureStartedRevealed: Bool = false

    private var gestureActive: Bool = false
    private var gestureStartedAtTop: Bool = false
    private var collapsedInGesture: Bool = false
    private var momentumPassesThrough: Bool = true
    private var samples: [(time: Double, delta: CGFloat)] = []

    public init(revealed: Bool = false) {
        self.fraction = revealed ? 1 : 0
    }

    public var isAnimating: Bool {
        return self.spring != nil || self.glide != nil
    }

    public var isTracking: Bool {
        return self.gestureActive && self.gestureDrivesHeader
    }

    public var isSettledRevealed: Bool {
        return !self.isAnimating && !self.isTracking && self.fraction >= 1
    }

    public var isSettledConcealed: Bool {
        return !self.isAnimating && !self.isTracking && self.fraction <= 0
    }

    public enum Presentation: Equatable {
        case revealed
        case concealed
        case moving(fraction: CGFloat, opening: Bool, tracking: Bool)
    }

    public var presentation: Presentation {
        if self.isSettledRevealed {
            return .revealed
        }
        if !self.isTracking, self.spring == nil, self.fraction <= 0 {
            return .concealed
        }
        let target = self.spring?.target ?? (self.glide != nil ? 0 : (self.fraction >= 0.5 ? 1 : 0))
        return .moving(fraction: max(0, min(1, self.fraction)), opening: target >= 1, tracking: self.isTracking)
    }

    public func takeTableDelta() -> CGFloat? {
        let delta = self.pendingTableDelta
        self.pendingTableDelta = 0
        return delta == 0 ? nil : delta
    }

    public func stopGlide() {
        self.glide = nil
        self.pendingTableDelta = 0
    }

    public func handle(_ input: StoryRevealInput, tableOffset: CGFloat) -> Decision {
        guard self.enabled else {
            return .passThrough
        }
        self.lastTime = max(self.lastTime, input.time)
        let decision = self.route(input, tableOffset: tableOffset)
        if decision == .passThrough, input.phase != .mayBegin, !self.gestureDrivesHeader, !self.isAnimating, self.fraction > 0, self.fraction < 1 {
            self.resumeCaught(at: self.lastTime)
        }
        return decision
    }

    private func route(_ input: StoryRevealInput, tableOffset: CGFloat) -> Decision {
        let atTop = tableOffset <= StoryRevealModel.topTolerance

        if input.momentum != .none {
            return self.handleMomentum(input, atTop: atTop)
        }
        if input.isWheel {
            if input.precise {
                return self.handlePreciseWithoutPhase(input, atTop: atTop)
            }
            return self.handleWheel(input, atTop: atTop)
        }

        switch input.phase {
        case .mayBegin:
            self.catchMotion(atTop: atTop)
            return .passThrough
        case .began:
            self.beginGesture(atTop: atTop, time: input.time)
            return self.track(input, tableOffset: tableOffset)
        case .changed, .stationary:
            if !self.gestureActive {
                self.beginGesture(atTop: atTop, time: input.time)
            }
            return self.track(input, tableOffset: tableOffset)
        case .ended, .cancelled:
            return self.finishGesture(input, tableOffset: tableOffset)
        case .none:
            return .passThrough
        }
    }

    public func tableDidScroll(offset: CGFloat, time: Double) {
        guard self.enabled, !self.isTracking, self.glide == nil, self.fraction > 0 else {
            return
        }
        if offset > StoryRevealModel.scrolledAwayOffset, self.spring?.target != 0 {
            self.startSpring(target: 0, velocity: 0, time: time)
        }
    }

    public func setRevealed(_ revealed: Bool, animated: Bool, time: Double) {
        self.endGesture()
        self.stopGlide()
        self.caughtTarget = nil
        self.lastTime = max(self.lastTime, time)
        let target: CGFloat = revealed ? 1 : 0
        if animated {
            if self.spring?.target != target && self.fraction != target {
                self.startSpring(target: target, velocity: 0, time: time)
            } else if self.fraction == target {
                self.spring = nil
            }
        } else {
            self.spring = nil
            self.fraction = target
        }
    }

    public func finishIfPartial(time: Double) {
        guard self.enabled, !self.isAnimating, !self.isTracking, self.fraction > 0, self.fraction < 1 else {
            return
        }
        self.resumeCaught(at: max(time, self.lastTime))
    }

    @discardableResult
    public func advance(to time: Double) -> Bool {
        self.lastTime = max(self.lastTime, time)
        if let glide = self.glide {
            self.fraction = glide.fraction(at: time)
            let offset = glide.tableOffset(at: time)
            self.pendingTableDelta += offset - self.glideOffset
            self.glideOffset = offset
            if glide.isFinished(at: time) {
                self.fraction = 0
                self.glide = nil
            }
            return true
        }
        guard let spring = self.spring else {
            return false
        }
        if spring.isSettled(at: time) {
            self.fraction = spring.target
            self.spring = nil
        } else {
            self.fraction = max(0, min(1, spring.value(at: time)))
        }
        return true
    }

    private func beginGesture(atTop: Bool, time: Double) {
        self.catchMotion(atTop: atTop)
        self.gestureActive = true
        self.gestureStartedAtTop = atTop
        self.gestureDrivesHeader = false
        self.axis = .undecided
        self.samples = []
        self.momentumPassesThrough = true
        self.gestureStartedRevealed = self.fraction >= 1
    }

    private func endGesture() {
        self.gestureActive = false
        self.gestureDrivesHeader = false
        self.collapsedInGesture = false
        self.axis = .undecided
        self.samples = []
    }

    private func catchMotion(atTop: Bool) {
        guard self.glide != nil || (self.spring != nil && atTop) else {
            return
        }
        let target = self.spring?.target ?? 0
        self.advance(to: self.lastTime)
        self.spring = nil
        self.glide = nil
        self.caughtTarget = self.fraction > 0 && self.fraction < 1 ? target : nil
    }

    private func resumeCaught(at time: Double) {
        let target = self.caughtTarget ?? (self.fraction >= 0.5 ? 1 : 0)
        self.caughtTarget = nil
        self.startSpring(target: target, velocity: 0, time: time)
    }

    private func track(_ input: StoryRevealInput, tableOffset: CGFloat) -> Decision {
        let atTop = tableOffset <= StoryRevealModel.topTolerance
        if tableOffset > StoryRevealModel.scrolledAwayOffset {
            self.gestureStartedAtTop = false
        }
        if self.axis == .undecided {
            if input.deltaX == 0 && input.deltaY == 0 {
                if self.gestureStartedRevealed && !self.gestureDrivesHeader {
                    return .passThrough
                }
                let mayDrive = atTop && (self.fraction > 0 || self.gestureStartedAtTop)
                return self.gestureDrivesHeader || mayDrive ? .consumed : .passThrough
            }
            self.axis = abs(input.deltaX) > abs(input.deltaY) ? .horizontal : .vertical
        }
        guard self.axis == .vertical else {
            return .passThrough
        }
        let delta = input.deltaY
        if self.gestureStartedRevealed && !self.gestureDrivesHeader && self.fraction >= 1 && delta > 0 {
            return .passThrough
        }
        let canDrive = atTop && (self.fraction > 0 || (self.gestureStartedAtTop && delta > 0))
        guard canDrive || self.gestureDrivesHeader else {
            self.collapsedInGesture = false
            return .passThrough
        }
        if !canDrive && self.fraction <= 0 {
            self.gestureDrivesHeader = false
            self.collapsedInGesture = false
            return .passThrough
        }
        self.gestureDrivesHeader = true
        self.caughtTarget = nil
        self.record(delta, time: input.time)
        let next = self.fraction + delta / StoryRevealModel.span
        if next <= 0 {
            self.fraction = 0
            self.gestureDrivesHeader = false
            self.collapsedInGesture = true
            return .consumed
        }
        self.collapsedInGesture = false
        self.fraction = min(1, next)
        return .consumed
    }

    private func finishGesture(_ input: StoryRevealInput, tableOffset: CGFloat) -> Decision {
        let drove = self.gestureDrivesHeader
        let collapsed = self.collapsedInGesture
        let velocity = self.velocity(at: input.time)
        self.endGesture()
        guard drove else {
            self.momentumPassesThrough = true
            if collapsed, velocity < -StoryRevealModel.flickVelocity {
                self.startGlide(speed: -velocity, tableOffset: tableOffset, time: input.time)
                return .consumed
            }
            return .passThrough
        }
        let target: CGFloat
        if self.fraction >= 1 {
            target = 1
        } else if self.fraction <= 0 {
            target = 0
        } else if velocity > StoryRevealModel.flickVelocity {
            target = 1
        } else if velocity < -StoryRevealModel.flickVelocity {
            target = 0
        } else {
            target = self.fraction >= 0.5 ? 1 : 0
        }
        self.momentumPassesThrough = false
        if target == 0, velocity < -StoryRevealModel.flickVelocity {
            self.startGlide(speed: -velocity, tableOffset: tableOffset, time: input.time)
            return .consumed
        }
        if self.fraction != target {
            self.startSpring(target: target, velocity: velocity / Double(StoryRevealModel.span), time: input.time)
        }
        return .consumed
    }

    private func handleMomentum(_ input: StoryRevealInput, atTop: Bool) -> Decision {
        if self.glide != nil {
            return .consumed
        }
        if self.spring != nil {
            if self.spring?.target == 0, self.momentumPassesThrough, input.deltaY < 0 {
                return .passThrough
            }
            return .consumed
        }
        if self.fraction > 0 {
            if input.deltaY < 0 && atTop {
                let next = self.fraction + input.deltaY / StoryRevealModel.span
                self.fraction = max(0, next)
                return .consumed
            }
            return .consumed
        }
        return .passThrough
    }

    private func handleWheel(_ input: StoryRevealInput, atTop: Bool) -> Decision {
        self.endGesture()
        if self.glide != nil {
            self.catchMotion(atTop: atTop)
        }
        guard atTop, input.deltaY != 0 else {
            return .passThrough
        }
        if input.deltaY > 0 {
            if self.fraction < 1 && self.spring?.target != 1 {
                self.startSpring(target: 1, velocity: 0, time: input.time)
            }
            return .consumed
        }
        if self.fraction > 0 && self.spring?.target != 0 {
            self.startSpring(target: 0, velocity: 0, time: input.time)
            return .consumed
        }
        return .passThrough
    }

    private func handlePreciseWithoutPhase(_ input: StoryRevealInput, atTop: Bool) -> Decision {
        guard atTop, abs(input.deltaY) >= abs(input.deltaX), input.deltaY != 0 else {
            return .passThrough
        }
        if input.deltaY < 0, self.fraction <= 0 {
            return .passThrough
        }
        return self.handleWheel(input, atTop: atTop)
    }

    private func startGlide(speed: Double, tableOffset: CGFloat, time: Double) {
        self.spring = nil
        self.caughtTarget = nil
        self.glide = StoryRevealGlide(start: time, fromFraction: self.fraction, fromOffset: tableOffset, speed: speed)
        self.glideOffset = tableOffset
        self.pendingTableDelta = 0
    }

    private func startSpring(target: CGFloat, velocity: Double, time: Double) {
        self.caughtTarget = nil
        let omega = target > self.fraction ? StoryRevealSpring.omegaReveal : StoryRevealSpring.omegaCollapse
        self.spring = StoryRevealSpring(omega: omega, target: target, from: self.fraction, velocity: velocity, start: time)
    }

    private func record(_ delta: CGFloat, time: Double) {
        self.samples.append((time, delta))
        let horizon = time - StoryRevealModel.velocityWindow * 2
        self.samples.removeAll { $0.time < horizon }
    }

    private func velocity(at time: Double) -> Double {
        let recent = self.samples.filter { $0.time >= time - StoryRevealModel.velocityWindow }
        guard let first = recent.first, recent.count >= 2 else {
            return 0
        }
        let span = max(time - first.time, 1.0 / 120.0)
        let total = recent.reduce(0) { $0 + Double($1.delta) }
        return total / span
    }
}
