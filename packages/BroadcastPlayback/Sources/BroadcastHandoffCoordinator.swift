import Foundation

// The listener-to-speaker handoff rule that GroupInstanceCustomImpl applied inside tgcalls (GroupInstanceCustomImpl.cpp
// 2266-2290, 2464-2520, 2837-2953), for PresentationGroupCall and the testbench runner to drive now that the engine
// knows only `none` and `rtc`. The call tells it the mode it sets and the engine's RTC connectivity; it says whether
// the broadcast player plays and what network state the call shows.
//
// The rule, ported with its quirks:
// - leaving broadcast with `keepBroadcastIfWasEnabled` marks broadcast as kept: it plays on through the rejoin, and the
//   call shows connected and transitioning while it does; leaving it without keep stops it at once;
// - entering broadcast clears "broadcast connected" and starts playing if it is not playing; a kept broadcast continues
//   and stays marked as kept;
// - a status tick at creation and every 500 ms sets "broadcast connected" while in broadcast or while kept, so a
//   listener shows connected at the same moment as before;
// - any change of RTC connectivity, either way, stops a kept broadcast at once and unmarks it.
// Every call and callback happens on one thread.
public final class BroadcastHandoffCoordinator {
    public enum Mode: Equatable {
        case none
        case rtc
        case broadcast
    }

    public struct NetworkState: Equatable {
        public var isConnected: Bool
        public var isTransitioningFromBroadcastToRtc: Bool
        public var mode: Mode

        public init(isConnected: Bool, isTransitioningFromBroadcastToRtc: Bool, mode: Mode) {
            self.isConnected = isConnected
            self.isTransitioningFromBroadcastToRtc = isTransitioningFromBroadcastToRtc
            self.mode = mode
        }
    }

    private static let statusTickInterval: Double = 0.5

    private let schedule: (Double, @escaping () -> Void) -> BroadcastCancellable
    private var tick: BroadcastCancellable?
    private var mode: Mode = .none
    private var isKept = false
    private var isBroadcastConnected = false
    private var isRtcConnected = false
    private var isStopped = false

    public var networkStateUpdated: ((NetworkState) -> Void)?
    public var broadcastPlayingUpdated: ((Bool) -> Void)?
    public private(set) var networkState = NetworkState(isConnected: false, isTransitioningFromBroadcastToRtc: false, mode: .none)
    public private(set) var isBroadcastPlaying = false

    public init(schedule: @escaping (Double, @escaping () -> Void) -> BroadcastCancellable) {
        self.schedule = schedule
        self.scheduleTick(after: 0.0)
    }

    public func setMode(_ mode: Mode, keepBroadcastIfWasEnabled: Bool) {
        if self.isStopped || (self.mode == mode && mode != .none) {
            return
        }
        let previous = self.mode
        self.mode = mode
        if previous == .broadcast {
            if keepBroadcastIfWasEnabled {
                self.isKept = true
            } else {
                self.setPlaying(false)
            }
        }
        if mode == .broadcast {
            self.isBroadcastConnected = false
            self.setPlaying(true)
        }
        self.update()
    }

    // The engine's network state (it connects only in `rtc`).
    public func setRtcConnected(_ isConnected: Bool) {
        if self.isStopped || self.isRtcConnected == isConnected {
            return
        }
        self.isRtcConnected = isConnected
        if self.isKept {
            self.isKept = false
            self.setPlaying(false)
        }
        self.update()
    }

    public func stop() {
        if self.isStopped {
            return
        }
        self.isStopped = true
        self.tick?.cancel()
        self.tick = nil
        self.isKept = false
        self.setPlaying(false)
    }

    private func scheduleTick(after delay: Double) {
        self.tick = self.schedule(delay, { [weak self] in
            guard let self, !self.isStopped else {
                return
            }
            if self.mode == .broadcast || self.isKept {
                if !self.isBroadcastConnected {
                    self.isBroadcastConnected = true
                    self.update()
                }
            }
            self.scheduleTick(after: BroadcastHandoffCoordinator.statusTickInterval)
        })
    }

    private func setPlaying(_ isPlaying: Bool) {
        if self.isBroadcastPlaying == isPlaying {
            return
        }
        self.isBroadcastPlaying = isPlaying
        self.broadcastPlayingUpdated?(isPlaying)
    }

    private func update() {
        let transitioning = self.isKept && self.isBroadcastConnected
        var state = NetworkState(isConnected: false, isTransitioningFromBroadcastToRtc: false, mode: self.mode)
        switch self.mode {
        case .none:
            state.isConnected = transitioning
            state.isTransitioningFromBroadcastToRtc = transitioning
        case .rtc:
            state.isConnected = self.isRtcConnected || transitioning
            state.isTransitioningFromBroadcastToRtc = transitioning
        case .broadcast:
            state.isConnected = self.isBroadcastConnected
        }
        if state != self.networkState {
            self.networkState = state
            self.networkStateUpdated?(state)
        }
    }
}
