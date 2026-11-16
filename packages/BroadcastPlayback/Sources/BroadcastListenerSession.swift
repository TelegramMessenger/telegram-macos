import Foundation
import HLSPlayback

// One ssrc's level since the last poll, as the audio core reports it (the maximum × 2, voice if any update had voice).
public struct BroadcastAudioLevelSample: Equatable {
    public var ssrc: UInt32
    public var level: Float
    public var voice: Bool

    public init(ssrc: UInt32, level: Float, voice: Bool) {
        self.ssrc = ssrc
        self.level = level
        self.voice = voice
    }
}

// What a listener session needs from its host (the app's call context, the testbench runner): the network, the decoders
// and the audio core. Every call and callback happens on the session's one thread, which is also the audio core's
// control thread.
public protocol BroadcastListenerPlatform: AnyObject {
    // Seconds on the audio core's clock (CACurrentMediaTime's base).
    var now: Double { get }
    func schedule(after delay: Double, _ action: @escaping () -> Void) -> BroadcastCancellable
    func requestLiveEdge(completion: @escaping (BroadcastEdgeOutcome) -> Void) -> BroadcastCancellable
    // `data` is the part's bytes with `.data`, nil otherwise; the platform reads `.data`'s info.
    func loadPart(_ request: BroadcastPartRequest, completion: @escaping (BroadcastPartOutcome, Data?) -> Void) -> BroadcastCancellable
    // Decodes off the session's thread; enqueues on it unless `gate` closed meanwhile.
    func handOverAudio(segmentTimestampMs: Int64, data: Data, gate: BroadcastAudioHandover.Gate)
    func playAudio(segmentTimestampMs: Int64, at hostTime: Double, offsetMs: Int)
    func setAudioActive(_ isActive: Bool)
    func setAudioVolume(ssrc: UInt32, volume: Float)
    func resetAudio()
    func takeAudioLevels() -> [BroadcastAudioLevelSample]
    func deliverVideo(_ segment: BroadcastSegment, data: [BroadcastPartRequest: Data])
    func playVideo(segmentTimestampMs: Int64, at hostTime: Double, offsetMs: Int)
    func stopVideo()
    func requestRejoin()
}

// A listener's broadcast player: the controller (a fresh one for every play, since a stopped controller stays stopped)
// and the handoff coordinator, the audio handover, the levels poll, volumes and requested channels, and the rejoin rule.
// The testbench runner and the app's call context host it, so the testbench holds the app's composition to the
// engine's baseline. It is told the mode the call sets and the engine's RTC connectivity, as the engine was.
//
// Rejoin: a part answered `GROUPCALL_JOIN_MISSING` makes the controller ask for a rejoin, which the call performs
// through its own `none`. The session holds broadcast through that `none`, and the next broadcast join tells the
// controller it rejoined, so the buffer plays on. Every other `none` without keep (the call's own reconnects) stops the
// player, and the next broadcast starts a fresh one, as the engine restarted.
public final class BroadcastListenerSession {
    // One controller's view of the platform. Callbacks of a controller that has stopped are dropped.
    private final class Environment: BroadcastPlaybackEnvironment {
        private let platform: BroadcastListenerPlatform
        private weak var session: BroadcastListenerSession?
        private let generation: Int

        init(platform: BroadcastListenerPlatform, session: BroadcastListenerSession, generation: Int) {
            self.platform = platform
            self.session = session
            self.generation = generation
        }

        private var isCurrent: Bool {
            return self.session?.generation == self.generation
        }

        var now: Double {
            return self.platform.now
        }

        func schedule(after delay: Double, _ action: @escaping () -> Void) -> BroadcastCancellable {
            return self.platform.schedule(after: delay, { [weak self] in
                guard let self, self.isCurrent else {
                    return
                }
                action()
            })
        }

        func requestLiveEdge(completion: @escaping (BroadcastEdgeOutcome) -> Void) -> BroadcastCancellable {
            return self.platform.requestLiveEdge(completion: { [weak self] outcome in
                guard let self, self.isCurrent else {
                    return
                }
                completion(outcome)
            })
        }

        func loadPart(_ request: BroadcastPartRequest, progress: @escaping (Int64) -> Void, completion: @escaping (BroadcastPartOutcome) -> Void) -> BroadcastCancellable {
            return self.platform.loadPart(request, completion: { [weak self] outcome, data in
                guard let self, self.isCurrent, let session = self.session else {
                    return
                }
                if case .data = outcome, let data {
                    session.held[request] = data
                }
                completion(outcome)
            })
        }

        func deliver(_ segment: BroadcastSegment) {
            self.session?.deliver(segment)
        }

        func play(segmentTimestampMs: Int64, at hostTime: Double, offsetMs: Int) {
            self.platform.playAudio(segmentTimestampMs: segmentTimestampMs, at: hostTime, offsetMs: offsetMs)
            self.platform.playVideo(segmentTimestampMs: segmentTimestampMs, at: hostTime, offsetMs: offsetMs)
        }

        func setUnifiedPosition(_ positionMs: Int64) {
        }

        func discard(_ requests: [BroadcastPartRequest]) {
            self.session?.discard(requests)
        }

        func requestRejoin() {
            self.session?.rejoinRequested()
        }
    }

    private static let levelsInterval = 0.1

    private let platform: BroadcastListenerPlatform
    private let bandwidthStore: HLSBandwidthStore
    private let configuration: BroadcastPlaybackController.Configuration
    private let log: ((String) -> Void)?
    private let coordinator: BroadcastHandoffCoordinator

    private var generation = 0
    private var controller: BroadcastPlaybackController?
    private var handover: BroadcastAudioHandover?
    private var levelsPoll: BroadcastCancellable?
    private var held: [BroadcastPartRequest: Data] = [:]
    private var requestedChannels: [BroadcastVideoChannelRequest] = []
    private var networkClass: HLSNetworkClass?
    private var rejoinPending = false
    private var isStopped = false

    public var networkStateUpdated: ((BroadcastHandoffCoordinator.NetworkState) -> Void)?
    public var levelsUpdated: (([BroadcastAudioLevelSample]) -> Void)?

    public var networkState: BroadcastHandoffCoordinator.NetworkState {
        return self.coordinator.networkState
    }

    public var isBroadcastPlaying: Bool {
        return self.coordinator.isBroadcastPlaying
    }

    // Bytes held between a part's load and its segment's delivery (tests, diagnostics).
    public var heldPartCount: Int {
        return self.held.count
    }

    public init(platform: BroadcastListenerPlatform, bandwidthStore: HLSBandwidthStore = .shared, configuration: BroadcastPlaybackController.Configuration = BroadcastPlaybackController.Configuration(), log: ((String) -> Void)? = nil) {
        self.platform = platform
        self.bandwidthStore = bandwidthStore
        self.configuration = configuration
        self.log = log
        self.coordinator = BroadcastHandoffCoordinator(schedule: { delay, action in
            return platform.schedule(after: delay, action)
        })
        self.coordinator.networkStateUpdated = { [weak self] state in
            self?.networkStateUpdated?(state)
        }
        self.coordinator.broadcastPlayingUpdated = { [weak self] isPlaying in
            self?.broadcastPlayingChanged(isPlaying)
        }
    }

    // The mode the call sets on its engine, with its keep flag (the engine's old `setConnectionMode` arguments).
    public func setMode(_ mode: BroadcastHandoffCoordinator.Mode, keepBroadcastIfWasEnabled: Bool) {
        if self.isStopped {
            return
        }
        if self.rejoinPending {
            if mode == .none && !keepBroadcastIfWasEnabled {
                self.log?("broadcast session: holding broadcast through the rejoin")
                return
            }
            self.rejoinPending = false
            if mode == .broadcast, let controller = self.controller {
                controller.rejoined()
                return
            }
        }
        self.coordinator.setMode(mode, keepBroadcastIfWasEnabled: keepBroadcastIfWasEnabled)
    }

    // The engine's network state (it connects only in `rtc`).
    public func setRtcConnected(_ isConnected: Bool) {
        if self.isStopped {
            return
        }
        self.coordinator.setRtcConnected(isConnected)
    }

    public func setRequestedVideoChannels(_ channels: [BroadcastVideoChannelRequest]) {
        self.requestedChannels = channels
        self.controller?.setRequestedVideoChannels(channels)
    }

    // The core keeps every ssrc's volume, playing or not.
    public func setVolume(ssrc: UInt32, volume: Float) {
        self.platform.setAudioVolume(ssrc: ssrc, volume: volume)
    }

    public func setNetworkClass(_ networkClass: HLSNetworkClass) {
        self.networkClass = networkClass
        self.controller?.setNetworkClass(networkClass)
    }

    // Ends the session. `keepingAudio`: the testbench keeps the core active and unreset until its device stops (a
    // trailing silence would count as a stall); the app empties it.
    public func stop(keepingAudio: Bool = false) {
        if self.isStopped {
            return
        }
        self.isStopped = true
        if keepingAudio {
            self.coordinator.broadcastPlayingUpdated = nil
            self.handover?.close()
            self.tearDownPlayer()
        }
        self.coordinator.stop()
    }

    private func broadcastPlayingChanged(_ isPlaying: Bool) {
        if isPlaying {
            self.startPlayer()
        } else {
            self.platform.setAudioActive(false)
            self.handover?.stop()
            self.tearDownPlayer()
        }
    }

    private func startPlayer() {
        self.generation += 1
        let platform = self.platform
        let gate = BroadcastAudioHandover.Gate()
        self.handover = BroadcastAudioHandover(handOver: { timestampMs, data in
            platform.handOverAudio(segmentTimestampMs: timestampMs, data: data, gate: gate)
        }, resetCore: {
            platform.resetAudio()
        }, gate: gate)
        let environment = Environment(platform: platform, session: self, generation: self.generation)
        let controller = BroadcastPlaybackController(format: .listener, environment: environment, bandwidthStore: self.bandwidthStore, configuration: self.configuration, log: self.log)
        self.controller = controller
        if let networkClass = self.networkClass {
            controller.setNetworkClass(networkClass)
        }
        controller.setRequestedVideoChannels(self.requestedChannels)
        controller.start()
        platform.setAudioActive(true)
        self.scheduleLevelsPoll(generation: self.generation)
    }

    // The controller's own stop discards what it delivered and has not played; its callbacks are dropped afterwards.
    private func tearDownPlayer() {
        self.controller?.stop()
        self.controller = nil
        self.handover = nil
        self.generation += 1
        self.platform.stopVideo()
        self.levelsPoll?.cancel()
        self.levelsPoll = nil
        self.held.removeAll()
        self.rejoinPending = false
    }

    private func scheduleLevelsPoll(generation: Int) {
        self.levelsPoll = self.platform.schedule(after: BroadcastListenerSession.levelsInterval, { [weak self] in
            guard let self, self.generation == generation else {
                return
            }
            let levels = self.platform.takeAudioLevels()
            if !levels.isEmpty {
                self.levelsUpdated?(levels)
            }
            self.scheduleLevelsPoll(generation: generation)
        })
    }

    // The segment's held bytes go to the audio handover and the video, and are dropped: what a re-delivery needs is a
    // re-fetched part, held anew.
    private func deliver(_ segment: BroadcastSegment) {
        var data: [BroadcastPartRequest: Data] = [:]
        for request in [segment.primary] + segment.video.values.map({ $0 }) {
            if let bytes = self.held.removeValue(forKey: request) {
                data[request] = bytes
            }
        }
        self.handover?.deliver(segment, data: data)
        self.platform.deliverVideo(segment, data: data)
    }

    private func discard(_ requests: [BroadcastPartRequest]) {
        for request in requests {
            self.held.removeValue(forKey: request)
        }
        self.handover?.discard(requests)
    }

    private func rejoinRequested() {
        self.rejoinPending = true
        self.platform.requestRejoin()
    }
}
