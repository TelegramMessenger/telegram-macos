// Live position and quality ported from hls.js v1.7.3 (src/controller/latency-controller.ts, src/controller/stream-controller.ts, src/controller/abr-controller.ts), Copyright (c) Dailymotion and hls.js contributors, Apache License 2.0.

import Foundation
import HLSPlayback

// Decides what a broadcast listener or stream viewer fetches and when it plays, replacing tgcalls'
// `StreamingMediaContext`. In listener format it owns the playback clock (the host's) and tells the environment when
// each segment starts; in unified format the player is the clock and reports its position (`updatePlayback`).
//
// Every call happens on the environment's thread.
public final class BroadcastPlaybackController {
    public struct Configuration: Equatable {
        // hls.js `liveSyncDurationCount` (× the 1 s target duration) and `liveSyncOnStallIncrease`.
        public var liveSyncDurationCount: Double = 3.0
        public var liveSyncOnStallIncrease: Double = 1.0
        // What the server keeps: the earliest a re-anchor may start.
        public var windowMs: Int64 = 30_000
        // Listener format: buffered ahead before the first play, and after an underrun. Today's engine waits 3000 ms; the
        // lab's sweep lowered it to 2000, where no cell stalls more and every stall is shorter (1000 adds a stall on
        // step-down).
        public var startBufferMs: Int = 1000
        public var resumeBufferMs: Int = 2000
        // Unified: loaded before the player gets its first parts (today's `ChunkMediaPlayerV2` stops whenever less than 1 s
        // is ahead), and loaded ahead of it before parts flow again after it stalled. With the real ladder (medium and
        // full; the server refuses thumbnail) no value wins every cell: on step-down 1000 stalls 6-7 times (3.4 s), 2000
        // 2-3 times (3.9 s), 3000 1-2 times (3.8 s; the engine stalls 4-5 times, 13.8 s); with events 2000 costs at most
        // 0.16 s against 1000 and 3000 up to 0.5 s more. 2000 (the sweep, 2026-11-03).
        public var unifiedStartBufferMs: Int = 2000
        public var unifiedResumeBufferMs: Int = 2000
        public var maxSegmentLoadsInFlight: Int = 2
        // hls.js `maxBufferLength`.
        public var maxBufferAheadMs: Int = 30_000
        public var notReadyRetryDelay: Double = 0.1
        public var edgeRetryDelay: Double = 1.0
        public var abandonPollInterval: Double = 0.1

        public init() {
        }
    }

    public enum State: Equatable {
        case idle
        case starting
        case playing
        case stalled
        case stopped
    }

    // hls.js `abrEwmaDefaultEstimate`: only seeds the estimator object a first sample creates.
    private static let defaultEstimate = 500_000.0
    private static let partDurationMs = BroadcastLivePosition.partDurationMs

    final class PartLoad {
        let request: BroadcastPartRequest
        let endpointId: String?
        var info: BroadcastPartInfo?
        var bytes: Int64 = 0
        var progressBytes: Int64 = 0
        var task: BroadcastCancellable?
        var retry: BroadcastCancellable?
        var issueTime: Double = 0.0
        // Issued with no other load of this controller in flight: its answer's time holds a round trip.
        var issuedWhileIdle = false
        var token: HLSLinkLoadToken?
        var tokenClass: HLSNetworkClass?
        // Seconds of link busy time the store charged its data response.
        var charged: Double = 0.0

        init(request: BroadcastPartRequest, endpointId: String?) {
            self.request = request
            self.endpointId = endpointId
        }

        var isDone: Bool {
            return self.info != nil
        }

        var isInFlight: Bool {
            return self.task != nil
        }

        var quality: BroadcastQuality? {
            switch self.request.kind {
            case .audio:
                return nil
            case let .video(_, quality), let .unified(quality):
                return quality
            }
        }
    }

    final class Segment {
        let timestampMs: Int64
        var primary: PartLoad
        // Endpoint → video part.
        var video: [String: PartLoad] = [:]
        // The channels the segment was requested for.
        var channels: [BroadcastVideoChannelRequest]
        // Requested once a mapping was known: its own audio part's mapping then corrects its video.
        let isRequestedWithMapping: Bool
        var isDropped = false
        var isSampled = false

        init(timestampMs: Int64, primary: PartLoad, channels: [BroadcastVideoChannelRequest], isRequestedWithMapping: Bool) {
            self.timestampMs = timestampMs
            self.primary = primary
            self.channels = channels
            self.isRequestedWithMapping = isRequestedWithMapping
        }

        var isComplete: Bool {
            return self.primary.isDone && self.video.values.allSatisfy(\.isDone)
        }

        var allLoads: [PartLoad] {
            return [self.primary] + self.video.keys.sorted().compactMap { self.video[$0] }
        }

        var value: BroadcastSegment {
            var video: [String: BroadcastPartRequest] = [:]
            for (endpointId, load) in self.video {
                video[endpointId] = load.request
            }
            return BroadcastSegment(timestampMs: self.timestampMs, primary: self.primary.request, video: video, info: self.primary.info ?? BroadcastPartInfo())
        }
    }

    // A delivered, not yet playing segment's video part fetched again at a raised ceiling.
    final class Refetch {
        let timestampMs: Int64
        let endpointId: String
        let load: PartLoad
        var isDropped = false

        init(timestampMs: Int64, endpointId: String, load: PartLoad) {
            self.timestampMs = timestampMs
            self.endpointId = endpointId
            self.load = load
        }
    }

    private let format: BroadcastFormat
    private let environment: BroadcastPlaybackEnvironment
    let bandwidthStore: HLSBandwidthStore
    let configuration: Configuration
    private let log: ((String) -> Void)?

    public private(set) var state: State = .idle {
        didSet {
            if self.state != oldValue {
                self.onStateChanged?(self.state)
            }
        }
    }
    public var onStateChanged: ((State) -> Void)?
    public private(set) var stallCount = 0

    // The live edge (ms) as last reported, and when.
    private var edgeMs: Int64?
    private var edgeHostTime: Double = 0.0
    private var edgeRequest: BroadcastCancellable?
    private var edgeRetry: BroadcastCancellable?

    private var nextSegmentTimestamp: Int64?
    // Requested segments not yet delivered, in timestamp order.
    private(set) var loading: [Segment] = []
    // Delivered segments the timeline still holds, by timestamp.
    private var delivered: [Int64: BroadcastSegment] = [:]
    private var newestDeliveredTimestamp: Int64?
    // When each recent segment's last part landed (the abandon rule watches a load from its predecessor's).
    private var completionTimes: [Int64: Double] = [:]
    private var timeline: BroadcastListenerTimeline
    // The newest audio part's mapping, and its segment.
    private var newestMapping: [String: Int32]?
    private var newestMappingTimestamp: Int64 = Int64.min
    private(set) var requestedChannels: [BroadcastVideoChannelRequest] = []
    private var refetches: [Refetch] = []

    private var networkClass: HLSNetworkClass = .unknown
    private var levelBitrates = BroadcastLevelBitrates()
    private var ttfb = BroadcastTTFBEstimator()
    private var lastChosen: [String: BroadcastQuality] = [:]
    // Every estimator sample taken, for tests and logs.
    private(set) var samples: [(durationMs: Double, bytes: Int64)] = []

    private var requestWake: BroadcastCancellable?
    private var requestWakeTime: Double?
    private var timelineWake: BroadcastCancellable?
    private var abandonTimer: BroadcastCancellable?
    private var isRejoining = false
    // The first play has happened (listener: the clock's; unified: the player's).
    private var hasStartedPlaying = false

    // Unified: the player's position as it last reported it, the position (start or jump) waiting for its start
    // buffer, segments complete but not yet handed to the player, and those it holds.
    private var playerPositionMs: Int64?
    private var playerIsPlaying = false
    private var pendingUnifiedPosition: Int64?
    private var isHoldingAfterStall = false
    private var isAwaitingResyncEdge = false
    private var held: [BroadcastSegment] = []
    private var unifiedDelivered: [BroadcastSegment] = []
    private static let unifiedEndpointId = "unified"

    public init(format: BroadcastFormat, environment: BroadcastPlaybackEnvironment, bandwidthStore: HLSBandwidthStore = .shared, configuration: Configuration = Configuration(), log: ((String) -> Void)? = nil) {
        self.format = format
        self.environment = environment
        self.bandwidthStore = bandwidthStore
        self.configuration = configuration
        self.log = log
        self.timeline = BroadcastListenerTimeline(startBufferMs: configuration.startBufferMs, resumeBufferMs: configuration.resumeBufferMs)
    }

    // MARK: Public

    // Media time at the playhead: the clock's (listener) or the player's (unified).
    public var positionMs: Int64? {
        switch self.format {
        case .listener:
            return self.timeline.positionMs(now: self.environment.now)
        case .unified:
            return self.playerPositionMs
        }
    }

    // Unified: the player's position in part time, and whether it is moving while asked to play (false: buffering).
    public func updatePlayback(positionMs: Int64, isPlaying: Bool) {
        guard self.format == .unified, self.state != .idle, self.state != .stopped else {
            return
        }
        self.playerPositionMs = positionMs
        self.unifiedDelivered.removeAll(where: { $0.timestampMs + BroadcastPlaybackController.partDurationMs <= positionMs })
        if isPlaying {
            if !self.hasStartedPlaying {
                self.hasStartedPlaying = true
                self.log?("broadcast: playing at \(positionMs)")
            }
            self.isHoldingAfterStall = false
            self.state = .playing
            self.startAbandonTimerIfNeeded()
        } else if self.hasStartedPlaying && self.playerIsPlaying {
            self.stallCount += 1
            self.isHoldingAfterStall = true
            self.state = .stalled
            self.log?("broadcast: player stalled at \(positionMs), \(self.stallCount) so far")
        }
        self.playerIsPlaying = isPlaying
        self.releaseUnified()
        self.requestSegmentsIfNeeded()
    }

    // The live edge now: the last report plus the time since.
    public var liveEdgeMs: Int64? {
        guard let edgeMs = self.edgeMs else {
            return nil
        }
        // The microsecond keeps a wake scheduled for an exact millisecond from reading the one before it.
        return edgeMs + Int64(((self.environment.now - self.edgeHostTime) * 1000.0 + 1e-3).rounded(.down))
    }

    // The level last chosen for an endpoint's video (`"unified"` for a stream).
    public func quality(endpointId: String) -> BroadcastQuality? {
        return self.lastChosen[endpointId]
    }

    var ttfbEstimateMs: Double {
        return self.ttfb.estimateMs
    }

    public func setNetworkClass(_ networkClass: HLSNetworkClass) {
        if networkClass == self.networkClass {
            return
        }
        self.networkClass = networkClass
        self.log?("broadcast: network class \(networkClass.rawValue)")
    }

    public func start() {
        guard self.state == .idle else {
            return
        }
        self.state = .starting
        self.requestEdge()
    }

    public func stop() {
        if self.state == .stopped {
            return
        }
        self.state = .stopped
        self.edgeRequest?.cancel()
        self.edgeRequest = nil
        self.edgeRetry?.cancel()
        self.edgeRetry = nil
        self.requestWake?.cancel()
        self.requestWake = nil
        self.timelineWake?.cancel()
        self.timelineWake = nil
        self.abandonTimer?.cancel()
        self.abandonTimer = nil
        self.dropLoading()
        self.dropRefetches(where: { _ in true })
        var discarded: [BroadcastPartRequest] = (self.unifiedDelivered + self.held).map(\.primary)
        self.unifiedDelivered.removeAll()
        self.held.removeAll()
        for timestamp in self.timeline.removeAll() {
            if let segment = self.delivered.removeValue(forKey: timestamp) {
                discarded.append(segment.primary)
                discarded.append(contentsOf: segment.video.keys.sorted().compactMap { segment.video[$0] })
            }
        }
        if !discarded.isEmpty {
            self.environment.discard(discarded)
        }
        self.log?("broadcast: stopped")
    }

    // The channels the views ask for. A raised ceiling re-fetches the endpoint's part, at the new choice, in every segment
    // after the playing one where it is lower; a lowered one keeps what is buffered; a removed endpoint's loads stop.
    public func setRequestedVideoChannels(_ channels: [BroadcastVideoChannelRequest]) {
        let previous = self.requestedChannels
        self.requestedChannels = channels
        if self.state == .idle || self.state == .stopped {
            return
        }
        let current = Set(channels.map(\.endpointId))
        for removed in previous.map(\.endpointId) where !current.contains(removed) {
            for segment in self.loading {
                segment.video[removed].map { self.cancel($0) }
                segment.video[removed] = nil
                segment.channels.removeAll(where: { $0.endpointId == removed })
            }
            self.dropRefetches(where: { $0.endpointId == removed })
            self.lastChosen[removed] = nil
        }
        for channel in channels {
            guard let old = previous.first(where: { $0.endpointId == channel.endpointId }), channel.maxQuality > old.maxQuality else {
                continue
            }
            for segment in self.loading {
                if let index = segment.channels.firstIndex(where: { $0.endpointId == channel.endpointId }) {
                    segment.channels[index] = channel
                }
            }
            self.raise(channel)
        }
        self.deliverCompletedSegments()
    }

    // The call joined again after `requestRejoin`.
    public func rejoined() {
        guard self.isRejoining, self.state != .stopped else {
            return
        }
        self.isRejoining = false
        self.log?("broadcast: rejoined")
        if let next = self.nextSegmentTimestamp, let edge = self.liveEdgeMs, next < edge - self.configuration.windowMs {
            switch self.format {
            case .listener:
                self.reanchor(edgeMs: edge)
            case .unified:
                // A stream moves its player to the new anchor (a jump), or it would wait at the old position forever.
                self.reanchorUnified(edgeMs: edge)
            }
        }
        self.requestSegmentsIfNeeded()
    }

    // MARK: Live edge

    private func requestEdge() {
        // An answer inside the call (it may come synchronously) has already cleared `edgeRequest`.
        var isAnswered = false
        let request = self.environment.requestLiveEdge(completion: { [weak self] outcome in
            isAnswered = true
            self?.handleEdge(outcome)
        })
        if !isAnswered {
            self.edgeRequest = request
        }
    }

    private func handleEdge(_ outcome: BroadcastEdgeOutcome) {
        if self.state == .stopped {
            return
        }
        self.edgeRequest = nil
        guard case let .edge(reportedMs) = outcome else {
            self.scheduleEdgeRetry()
            return
        }
        let edge = BroadcastLivePosition.edgeMs(format: self.format, reportedMs: reportedMs)
        let position = self.liveSyncPosition(edgeMs: edge)
        if position <= 0 {
            self.scheduleEdgeRetry()
            return
        }
        if self.isAwaitingResyncEdge {
            self.isAwaitingResyncEdge = false
            self.reanchorUnified(edgeMs: edge)
            self.requestSegmentsIfNeeded()
            return
        }
        self.edgeMs = edge
        self.edgeHostTime = self.environment.now
        let first = BroadcastLivePosition.partTimestamp(containing: position)
        self.nextSegmentTimestamp = first
        switch self.format {
        case .listener:
            self.timeline.firstOffsetMs = Int(position - first)
        case .unified:
            self.pendingUnifiedPosition = position
        }
        self.log?("broadcast: edge \(edge), start at \(position)")
        self.requestSegmentsIfNeeded()
    }

    // A stream's resync: the edge asked again. An anchor at or before what is loaded continues after it; one past it is
    // a jump, taken once the start buffer is loaded there (the old buffer plays until then).
    private func reanchorUnified(edgeMs: Int64) {
        self.edgeMs = edgeMs
        self.edgeHostTime = self.environment.now
        let position = self.liveSyncPosition(edgeMs: edgeMs)
        let anchor = BroadcastLivePosition.partTimestamp(containing: position)
        // What was handed to the player counts even once it has played it out (a jump back would replay it).
        let deliveredEnd = self.newestDeliveredTimestamp.map { $0 + BroadcastPlaybackController.partDurationMs }
        if let loadedEnd = self.unifiedLoadedEndMs ?? deliveredEnd, anchor <= loadedEnd {
            self.nextSegmentTimestamp = loadedEnd
            self.log?("broadcast: stream edge \(edgeMs) behind the buffer, continuing at \(loadedEnd)")
        } else {
            self.nextSegmentTimestamp = anchor
            self.pendingUnifiedPosition = position
            self.log?("broadcast: stream edge \(edgeMs), jumping to \(position)")
        }
    }

    // The end of what a stream has loaded (handed to the player or held).
    private var unifiedLoadedEndMs: Int64? {
        let newest = (self.unifiedDelivered + self.held).map(\.timestampMs).max()
        return newest.map { $0 + BroadcastPlaybackController.partDurationMs }
    }

    private func scheduleEdgeRetry() {
        self.edgeRetry = self.environment.schedule(after: self.configuration.edgeRetryDelay, { [weak self] in
            guard let self, self.state != .stopped else {
                return
            }
            self.edgeRetry = nil
            self.requestEdge()
        })
    }

    private func liveSyncPosition(edgeMs: Int64) -> Int64 {
        let targetLatency = BroadcastLivePosition.targetLatencyMs(liveSyncDurationCount: self.configuration.liveSyncDurationCount, stallCount: self.stallCount, liveSyncOnStallIncrease: self.configuration.liveSyncOnStallIncrease)
        return BroadcastLivePosition.liveSyncPositionMs(edgeMs: edgeMs, targetLatencyMs: targetLatency, windowMs: self.configuration.windowMs)
    }

    // A resync (or a rejoin after the window): continue at the new anchor, or after what is already delivered.
    private func reanchor(edgeMs: Int64) {
        self.edgeMs = edgeMs
        self.edgeHostTime = self.environment.now
        let position = self.liveSyncPosition(edgeMs: edgeMs)
        let anchor = BroadcastLivePosition.partTimestamp(containing: position)
        if let newest = self.newestDeliveredTimestamp {
            self.nextSegmentTimestamp = max(anchor, newest + BroadcastPlaybackController.partDurationMs)
        } else {
            self.nextSegmentTimestamp = anchor
            if !self.timeline.hasStarted {
                self.timeline.firstOffsetMs = Int(position - anchor)
            }
        }
        self.log?("broadcast: re-anchored at edge \(edgeMs), next \(self.nextSegmentTimestamp ?? -1)")
    }

    // MARK: Requests

    private var segmentsInFlight: Int {
        return self.loading.filter({ !$0.isComplete }).count
    }

    // Loaded ahead of the playhead, ms: the clock's buffer (listener), or what the stream has loaded past the player's
    // position (before the player reports, the position it was sent to).
    private var bufferedAheadMs: Int {
        switch self.format {
        case .listener:
            return self.timeline.bufferedAheadMs(now: self.environment.now)
        case .unified:
            guard let position = self.playerPositionMs ?? self.pendingUnifiedPosition, let loadedEnd = self.unifiedLoadedEndMs else {
                return 0
            }
            return max(0, Int(loadedEnd - position))
        }
    }

    private var bufferedAheadSeconds: Double {
        return Double(self.bufferedAheadMs) / 1000.0
    }

    private func requestSegmentsIfNeeded() {
        // A stream waiting for its edge after a resync requests nothing, as the old engine does while it has no anchor.
        guard self.state == .starting || self.state == .playing || self.state == .stalled, !self.isRejoining, !self.isAwaitingResyncEdge else {
            return
        }
        // Read afresh every round and advanced before a segment's loads are issued: an answer that comes inside
        // `loadPart` runs this again from within.
        while let next = self.nextSegmentTimestamp, let edge = self.liveEdgeMs, !self.isAwaitingResyncEdge, !self.isRejoining {
            if self.segmentsInFlight >= self.configuration.maxSegmentLoadsInFlight {
                break
            }
            let ahead = self.bufferedAheadMs + self.loading.count * Int(BroadcastPlaybackController.partDurationMs)
            if ahead >= self.configuration.maxBufferAheadMs {
                break
            }
            if next + BroadcastPlaybackController.partDurationMs > edge {
                self.scheduleRequestWake(afterMs: next + BroadcastPlaybackController.partDurationMs - edge)
                break
            }
            self.nextSegmentTimestamp = next + BroadcastPlaybackController.partDurationMs
            self.requestSegment(at: next)
            if self.state == .stopped {
                break
            }
        }
    }

    private func scheduleRequestWake(afterMs: Int64) {
        let time = self.environment.now + Double(afterMs) / 1000.0
        if let current = self.requestWakeTime, self.requestWake != nil, abs(current - time) < 1e-9 {
            return
        }
        self.requestWake?.cancel()
        self.requestWakeTime = time
        self.requestWake = self.environment.schedule(after: Double(afterMs) / 1000.0, { [weak self] in
            guard let self else {
                return
            }
            self.requestWake = nil
            self.requestWakeTime = nil
            self.requestSegmentsIfNeeded()
        })
    }

    private func requestSegment(at timestampMs: Int64) {
        if self.format == .unified {
            // Medium and full only: a stream's server refuses thumbnail (FLOOD_WAIT, read as NotReady, so a stream that
            // abandoned down to it stalled until it re-anchored; @bbcpersian on the simulator, 2026-11-03). The engine
            // fetched full only.
            let stream = BroadcastVideoChannelRequest(endpointId: BroadcastPlaybackController.unifiedEndpointId, minQuality: .medium, maxQuality: .full)
            let quality = self.chooseQualities([stream])[stream.endpointId] ?? .full
            let segment = Segment(timestampMs: timestampMs, primary: PartLoad(request: BroadcastPartRequest(timestampMs: timestampMs, kind: .unified(quality: quality)), endpointId: stream.endpointId), channels: [stream], isRequestedWithMapping: false)
            self.loading.append(segment)
            self.issue(segment.primary, in: segment)
            return
        }
        let primary = PartLoad(request: BroadcastPartRequest(timestampMs: timestampMs, kind: .audio), endpointId: nil)
        let segment = Segment(timestampMs: timestampMs, primary: primary, channels: self.requestedChannels, isRequestedWithMapping: self.newestMapping != nil)
        if let mapping = self.newestMapping {
            let present = self.requestedChannels.filter({ mapping[$0.endpointId] != nil })
            let qualities = self.chooseQualities(present)
            for channel in present {
                if let channelId = mapping[channel.endpointId], let quality = qualities[channel.endpointId] {
                    segment.video[channel.endpointId] = PartLoad(request: BroadcastPartRequest(timestampMs: timestampMs, kind: .video(channelId: channelId, quality: quality)), endpointId: channel.endpointId)
                }
            }
        }
        self.loading.append(segment)
        self.issue(segment.primary, in: segment)
        for channel in self.requestedChannels {
            if let load = segment.video[channel.endpointId] {
                self.issue(load, in: segment)
            }
        }
    }

    // The levels for a segment's channels: their ceilings while the class has no estimator at all, else the chooser's,
    // which steps down the smallest tiles first (ordered by ceiling, then endpoint). An estimator without weight (an
    // abandon's reset, a seeded prior) is an estimate: its default is what hls.js chooses from.
    private func chooseQualities(_ channels: [BroadcastVideoChannelRequest]) -> [String: BroadcastQuality] {
        var result: [String: BroadcastQuality] = [:]
        guard let estimator = self.bandwidthStore.estimator(for: self.networkClass) else {
            for channel in channels {
                result[channel.endpointId] = channel.maxQuality
                self.lastChosen[channel.endpointId] = channel.maxQuality
            }
            return result
        }
        let ordered = channels.sorted(by: { lhs, rhs in
            if lhs.maxQuality != rhs.maxQuality {
                return lhs.maxQuality < rhs.maxQuality
            }
            return lhs.endpointId < rhs.endpointId
        })
        let video = self.format == .listener
        let inputs = ordered.map { channel in
            BroadcastChannelLevelInput(floor: min(channel.minQuality, channel.maxQuality), ceiling: channel.maxQuality, lastChosen: self.lastChosen[channel.endpointId], bitsPerSecond: self.levelBitrates.bitsPerSecond(video: video))
        }
        let fixed = self.format == .listener ? self.levelBitrates.bitsPerSecond(.audio) : 0.0
        let chosen = BroadcastQualityChooser.choose(inputs, fixedBitsPerSecond: fixed, estimate: estimator.estimate, bufferStarvationDelay: self.bufferedAheadSeconds, ttfbSeconds: self.ttfb.estimateMs / 1000.0)
        for (channel, quality) in zip(ordered, chosen) {
            result[channel.endpointId] = quality
            self.lastChosen[channel.endpointId] = quality
        }
        return result
    }

    private func currentQuality(for channel: BroadcastVideoChannelRequest) -> BroadcastQuality {
        let quality = self.lastChosen[channel.endpointId] ?? channel.maxQuality
        return min(max(quality, min(channel.minQuality, channel.maxQuality)), channel.maxQuality)
    }

    private var loadsInFlight: Int {
        var count = 0
        for segment in self.loading {
            for load in segment.allLoads where load.isInFlight {
                count += 1
            }
        }
        for refetch in self.refetches where refetch.load.isInFlight {
            count += 1
        }
        return count
    }

    private func issue(_ load: PartLoad, in segment: Segment) {
        self.start(load, completion: { [weak self, weak segment, weak load] outcome in
            guard let self, let segment, let load else {
                return
            }
            self.handle(outcome, load: load, segment: segment)
        })
    }

    private func start(_ load: PartLoad, completion: @escaping (BroadcastPartOutcome) -> Void) {
        let now = self.environment.now
        load.retry = nil
        load.issueTime = now
        load.progressBytes = 0
        load.issuedWhileIdle = self.loadsInFlight == 0
        load.token = self.bandwidthStore.beginLoad(networkClass: self.networkClass, now: now)
        load.tokenClass = self.networkClass
        // An answer inside the call (SwiftSignalKit failures often come synchronously) has already been handled: the
        // task returned after it must not mark the load in flight again.
        var isAnswered = false
        let task = self.environment.loadPart(load.request, progress: { [weak load] bytes in
            load?.progressBytes = bytes
        }, completion: { outcome in
            isAnswered = true
            completion(outcome)
        })
        if !isAnswered {
            load.task = task
        }
        self.startAbandonTimerIfNeeded()
    }

    private func cancel(_ load: PartLoad) {
        load.task?.cancel()
        load.task = nil
        load.retry?.cancel()
        load.retry = nil
        if let token = load.token {
            self.bandwidthStore.cancelLoad(token, now: self.environment.now)
            load.token = nil
        }
    }

    // The link-side bookkeeping of an answer: a data response is charged and observed; any other answer is not charged,
    // and, sent with nothing else in flight (100 bytes: a round trip), samples the TTFB.
    private func account(_ outcome: BroadcastPartOutcome, load: PartLoad) {
        let now = self.environment.now
        load.task = nil
        guard let token = load.token else {
            return
        }
        load.token = nil
        if case let .data(bytes, _, _) = outcome {
            load.charged = self.bandwidthStore.endLoad(token, now: now)
            self.levelBitrates.observe(BroadcastBitrateKey(load.request.kind), bytes: bytes)
        } else {
            self.bandwidthStore.cancelLoad(token, now: now)
            if load.issuedWhileIdle {
                self.ttfb.sample(ttfbMs: (now - load.issueTime) * 1000.0)
            }
        }
    }

    private func handle(_ outcome: BroadcastPartOutcome, load: PartLoad, segment: Segment) {
        if segment.isDropped || self.state == .stopped {
            return
        }
        self.account(outcome, load: load)
        switch outcome {
        case let .data(bytes, _, info):
            load.info = info
            load.bytes = bytes
            if load === segment.primary && self.format == .listener {
                self.applyMapping(info.videoChannels, of: segment)
            }
            if segment.isComplete && !segment.isSampled {
                self.sample(segment)
            }
            self.deliverCompletedSegments()
        case .notReady:
            load.retry = self.environment.schedule(after: self.configuration.notReadyRetryDelay, { [weak self, weak segment, weak load] in
                guard let self, let segment, let load, !segment.isDropped, self.state != .stopped else {
                    return
                }
                self.issue(load, in: segment)
            })
        case let .resyncNeeded(responseTimestamp):
            self.log?("broadcast: resync at \(segment.timestampMs)")
            let nextAfterDrop = self.dropLoading()
            self.nextSegmentTimestamp = nextAfterDrop ?? self.nextSegmentTimestamp
            switch self.format {
            case .listener:
                self.reanchor(edgeMs: Int64((responseTimestamp * 1000.0).rounded(.down)))
                self.requestSegmentsIfNeeded()
            case .unified:
                // A stream asks its edge again (`last_timestamp_ms`), as today.
                if !self.isAwaitingResyncEdge {
                    self.isAwaitingResyncEdge = true
                    self.edgeRequest?.cancel()
                    self.requestEdge()
                }
            }
        case .rejoinNeeded:
            self.log?("broadcast: join missing at \(segment.timestampMs)")
            if let next = self.dropLoading() {
                self.nextSegmentTimestamp = next
            }
            if !self.isRejoining {
                self.isRejoining = true
                self.environment.requestRejoin()
            }
        }
    }

    // One sample per segment: its data responses' bytes over the busy time they were charged, less one round trip when
    // the segment opened the link's busy period (hls.js subtracts min(first byte, estimated TTFB); a whole response shows
    // no first byte, so the estimate stands in).
    private func sample(_ segment: Segment) {
        segment.isSampled = true
        self.completionTimes[segment.timestampMs] = self.environment.now
        self.completionTimes = self.completionTimes.filter({ $0.key >= segment.timestampMs - 10 * BroadcastPlaybackController.partDurationMs })
        let loads = segment.allLoads
        guard loads.allSatisfy({ $0.tokenClass == self.networkClass }) else {
            return
        }
        self.takeSample(bytes: loads.reduce(Int64(0), { $0 + $1.bytes }), chargedSeconds: loads.reduce(0.0, { $0 + $1.charged }), openedBusyPeriod: segment.primary.issuedWhileIdle)
    }

    // hls.js floors every sample's duration at 50 ms (`minDelayMs`), so a small fragment still carries weight;
    // `HLSBandwidthEstimator` floors it lower for small parts, which would leave a 12 KB part answered within its round
    // trip (after the TTFB comes off) without weight, and the estimate at the default.
    private static let minimumSampleMs = 50.0

    private func takeSample(bytes: Int64, chargedSeconds: Double, openedBusyPeriod: Bool) {
        var durationMs = chargedSeconds * 1000.0
        if openedBusyPeriod {
            durationMs -= min(self.ttfb.estimateMs, durationMs)
        }
        durationMs = max(durationMs, BroadcastPlaybackController.minimumSampleMs)
        let _ = self.bandwidthStore.sample(durationMs: durationMs, bytes: bytes, networkClass: self.networkClass, defaultEstimate: BroadcastPlaybackController.defaultEstimate, now: self.environment.now)
        self.samples.append((durationMs, bytes))
    }

    // A segment's own audio part names its video channels: correct what was requested with an older mapping.
    private func applyMapping(_ mapping: [String: Int32], of segment: Segment) {
        if segment.timestampMs >= self.newestMappingTimestamp {
            self.newestMapping = mapping
            self.newestMappingTimestamp = segment.timestampMs
        }
        guard segment.isRequestedWithMapping else {
            return
        }
        for channel in segment.channels {
            let endpointId = channel.endpointId
            let wanted = mapping[endpointId]
            if let existing = segment.video[endpointId] {
                guard case let .video(channelId, quality) = existing.request.kind else {
                    continue
                }
                if wanted == channelId {
                    continue
                }
                self.cancel(existing)
                self.discardIfLoaded(existing)
                segment.video[endpointId] = nil
                if let wanted {
                    let replacement = PartLoad(request: BroadcastPartRequest(timestampMs: segment.timestampMs, kind: .video(channelId: wanted, quality: quality)), endpointId: endpointId)
                    segment.video[endpointId] = replacement
                    self.issue(replacement, in: segment)
                }
            } else if let wanted {
                let load = PartLoad(request: BroadcastPartRequest(timestampMs: segment.timestampMs, kind: .video(channelId: wanted, quality: self.currentQuality(for: channel))), endpointId: endpointId)
                segment.video[endpointId] = load
                self.issue(load, in: segment)
            }
        }
    }

    // Cancels every load and forgets the segments not yet delivered; returns the first of them.
    @discardableResult
    private func dropLoading() -> Int64? {
        let first = self.loading.first?.timestampMs
        var loaded: [BroadcastPartRequest] = []
        for segment in self.loading {
            segment.isDropped = true
            for load in segment.allLoads {
                self.cancel(load)
                if load.isDone {
                    loaded.append(load.request)
                }
            }
        }
        self.loading.removeAll()
        // The environment holds what it loaded until it is delivered or discarded.
        if !loaded.isEmpty {
            self.environment.discard(loaded)
        }
        return first
    }

    // A part that landed and is replaced before its segment is delivered.
    private func discardIfLoaded(_ load: PartLoad) {
        if load.isDone {
            self.environment.discard([load.request])
        }
    }

    // MARK: The in-place update

    private func raise(_ channel: BroadcastVideoChannelRequest) {
        let endpointId = channel.endpointId
        let choice: BroadcastQuality
        if self.bandwidthStore.estimator(for: self.networkClass) != nil {
            let present = self.requestedChannels.filter({ self.newestMapping?[$0.endpointId] != nil || $0.endpointId == endpointId })
            choice = self.chooseQualities(present)[endpointId] ?? channel.maxQuality
        } else {
            choice = channel.maxQuality
            self.lastChosen[endpointId] = choice
        }
        self.log?("broadcast: \(endpointId) raised to \(channel.maxQuality), refetching at \(choice)")
        // Segments still loading: replace the part in place.
        for segment in self.loading {
            guard let existing = segment.video[endpointId], case let .video(channelId, quality) = existing.request.kind, quality < choice else {
                continue
            }
            self.cancel(existing)
            self.discardIfLoaded(existing)
            let replacement = PartLoad(request: BroadcastPartRequest(timestampMs: segment.timestampMs, kind: .video(channelId: channelId, quality: choice)), endpointId: endpointId)
            segment.video[endpointId] = replacement
            segment.isSampled = false
            self.issue(replacement, in: segment)
        }
        // Delivered segments not yet playing: fetch again, and deliver again when it lands.
        for entry in self.timeline.queue {
            guard let segment = self.delivered[entry.timestampMs], let existing = segment.video[endpointId], case let .video(channelId, quality) = existing.kind, quality < choice else {
                continue
            }
            if self.refetches.contains(where: { $0.timestampMs == entry.timestampMs && $0.endpointId == endpointId && ($0.load.quality ?? .thumbnail) >= choice }) {
                continue
            }
            self.dropRefetches(where: { $0.timestampMs == entry.timestampMs && $0.endpointId == endpointId })
            let refetch = Refetch(timestampMs: entry.timestampMs, endpointId: endpointId, load: PartLoad(request: BroadcastPartRequest(timestampMs: entry.timestampMs, kind: .video(channelId: channelId, quality: choice)), endpointId: endpointId))
            self.refetches.append(refetch)
            self.issueRefetch(refetch)
        }
    }

    private func issueRefetch(_ refetch: Refetch) {
        self.start(refetch.load, completion: { [weak self, weak refetch] outcome in
            guard let self, let refetch else {
                return
            }
            self.handleRefetch(outcome, refetch: refetch)
        })
    }

    private func handleRefetch(_ outcome: BroadcastPartOutcome, refetch: Refetch) {
        if refetch.isDropped || self.state == .stopped {
            return
        }
        self.account(outcome, load: refetch.load)
        switch outcome {
        case let .data(bytes, _, info):
            refetch.load.info = info
            refetch.load.bytes = bytes
            self.refetches.removeAll(where: { $0 === refetch })
            if refetch.load.tokenClass == self.networkClass {
                self.takeSample(bytes: bytes, chargedSeconds: refetch.load.charged, openedBusyPeriod: refetch.load.issuedWhileIdle)
            }
            if self.timeline.queue.contains(where: { $0.timestampMs == refetch.timestampMs }), var segment = self.delivered[refetch.timestampMs], let old = segment.video[refetch.endpointId] {
                segment.video[refetch.endpointId] = refetch.load.request
                self.delivered[refetch.timestampMs] = segment
                self.environment.deliver(segment)
                self.environment.discard([old])
            } else {
                // It started playing meanwhile: the part is not needed.
                self.environment.discard([refetch.load.request])
            }
        case .notReady:
            refetch.load.retry = self.environment.schedule(after: self.configuration.notReadyRetryDelay, { [weak self, weak refetch] in
                guard let self, let refetch, !refetch.isDropped, self.state != .stopped else {
                    return
                }
                self.issueRefetch(refetch)
            })
        case .resyncNeeded, .rejoinNeeded:
            self.refetches.removeAll(where: { $0 === refetch })
        }
    }

    private func dropRefetches(where predicate: (Refetch) -> Bool) {
        for refetch in self.refetches where predicate(refetch) {
            refetch.isDropped = true
            self.cancel(refetch.load)
        }
        self.refetches.removeAll(where: { $0.isDropped })
    }

    // MARK: Abandon

    private func startAbandonTimerIfNeeded() {
        if self.abandonTimer != nil || !self.hasStartedPlaying || self.state == .stopped {
            return
        }
        self.abandonTimer = self.environment.schedule(after: self.configuration.abandonPollInterval, { [weak self] in
            guard let self else {
                return
            }
            self.abandonTimer = nil
            self.checkAbandon()
            if self.loadsInFlight > 0 {
                self.startAbandonTimerIfNeeded()
            }
        })
    }

    // hls.js's `_abandonRulesCheck` for every in-flight video (or unified) part above its floor, once playback has started.
    // A load is watched from when the segment before it landed (until then it waits behind that segment's bytes). Audio
    // is never abandoned.
    private func checkAbandon() {
        guard self.hasStartedPlaying, self.state != .stopped, self.bandwidthStore.estimator(for: self.networkClass) != nil else {
            return
        }
        let now = self.environment.now
        for segment in self.loading {
            if let previous = self.loading.first(where: { $0.timestampMs == segment.timestampMs - BroadcastPlaybackController.partDurationMs }), !previous.isComplete {
                continue
            }
            let watchedSince = self.completionTimes[segment.timestampMs - BroadcastPlaybackController.partDurationMs]
            var candidates: [(endpointId: String, load: PartLoad)] = []
            if case .unified = segment.primary.request.kind {
                candidates.append((BroadcastPlaybackController.unifiedEndpointId, segment.primary))
            }
            for endpointId in segment.video.keys.sorted() {
                if let load = segment.video[endpointId] {
                    candidates.append((endpointId, load))
                }
            }
            for (endpointId, load) in candidates {
                guard load.isInFlight, let quality = load.quality, let channel = segment.channels.first(where: { $0.endpointId == endpointId }), let current = self.bandwidthStore.estimator(for: self.networkClass) else {
                    continue
                }
                let floor = min(channel.minQuality, channel.maxQuality)
                if quality <= floor {
                    continue
                }
                let isVideo = self.format == .listener
                let start = max(load.issueTime, watchedSince ?? load.issueTime)
                let context = HLSAbrContext(levels: self.levelBitrates.levels(video: isVideo), averageSegmentDuration: [1.0, 1.0, 1.0], levelErrors: [0, 0, 0], minAutoLevel: floor.rawValue, maxAutoLevel: channel.maxQuality.rawValue, lastLoadedLevel: self.lastChosen[endpointId]?.rawValue, currentSegmentDuration: 1.0, bufferStarvationDelay: self.bufferedAheadSeconds, ttfbSeconds: self.ttfb.estimateMs / 1000.0, lastLevelLoadSeconds: 0.0)
                let expectedBytes = Int64(self.levelBitrates.bitsPerSecond(BroadcastBitrateKey(load.request.kind)) / 8.0)
                let input = HLSAbandonInput(fragmentLevel: quality.rawValue, fragmentDuration: 1.0, expectedBytes: expectedBytes, loadedBytes: load.progressBytes, elapsedMs: (now - start) * 1000.0, estimator: current, playbackRate: 1.0, isPaused: false, context: context)
                guard let decision = HLSAbr.abandonDecision(input), let level = BroadcastQuality(rawValue: min(max(decision.level, floor.rawValue), channel.maxQuality.rawValue)), level < quality else {
                    continue
                }
                self.log?("broadcast: abandoning \(segment.timestampMs) \(endpointId) at \(quality) for \(level)")
                self.cancel(load)
                self.bandwidthStore.replace(decision.estimator, networkClass: self.networkClass, now: now)
                self.lastChosen[endpointId] = level
                let kind: BroadcastPartKind
                switch load.request.kind {
                case let .video(channelId, _):
                    kind = .video(channelId: channelId, quality: level)
                case .unified, .audio:
                    kind = .unified(quality: level)
                }
                let replacement = PartLoad(request: BroadcastPartRequest(timestampMs: segment.timestampMs, kind: kind), endpointId: endpointId)
                if load === segment.primary {
                    segment.primary = replacement
                } else {
                    segment.video[endpointId] = replacement
                }
                self.issue(replacement, in: segment)
            }
        }
    }

    // MARK: Delivery and the clock

    private func deliverCompletedSegments() {
        let now = self.environment.now
        while let first = self.loading.first, first.isComplete {
            self.loading.removeFirst()
            if !first.isSampled {
                self.sample(first)
            }
            let value = first.value
            self.newestDeliveredTimestamp = max(self.newestDeliveredTimestamp ?? first.timestampMs, first.timestampMs)
            switch self.format {
            case .listener:
                self.delivered[first.timestampMs] = value
                self.environment.deliver(value)
                self.timeline.append(BroadcastListenerTimeline.Entry(timestampMs: first.timestampMs, audioDurationMs: value.info.audioDurationMs, hasVideo: !value.video.isEmpty, readyTime: now))
            case .unified:
                self.held.append(value)
            }
        }
        switch self.format {
        case .listener:
            self.updateTimeline()
        case .unified:
            self.releaseUnified()
        }
        self.requestSegmentsIfNeeded()
    }

    // Unified: hands held segments to the player. A start (or jump) waits until `unifiedStartBufferMs` is loaded from its
    // position, a player stall until `unifiedResumeBufferMs` is loaded ahead of the player; otherwise segments go as they
    // come.
    private func releaseUnified() {
        guard self.format == .unified, self.state != .stopped, !self.held.isEmpty else {
            return
        }
        self.held.sort(by: { $0.timestampMs < $1.timestampMs })
        if let target = self.pendingUnifiedPosition {
            let anchor = BroadcastLivePosition.partTimestamp(containing: target)
            var end = anchor
            for segment in self.held where segment.timestampMs == end {
                end += BroadcastPlaybackController.partDurationMs
            }
            if end - target < Int64(self.configuration.unifiedStartBufferMs) {
                return
            }
            let stale = self.unifiedDelivered + self.held.filter({ $0.timestampMs < anchor })
            if !stale.isEmpty {
                self.environment.discard(stale.map(\.primary))
            }
            self.unifiedDelivered.removeAll()
            self.held.removeAll(where: { $0.timestampMs < anchor })
            self.pendingUnifiedPosition = nil
            // Where the player is until it reports otherwise.
            self.playerPositionMs = target
            self.environment.setUnifiedPosition(target)
            self.log?("broadcast: stream position \(target)")
        } else if self.isHoldingAfterStall {
            guard let position = self.playerPositionMs, let loadedEnd = self.unifiedLoadedEndMs, loadedEnd - position >= Int64(self.configuration.unifiedResumeBufferMs) else {
                return
            }
            self.isHoldingAfterStall = false
        }
        for segment in self.held {
            self.environment.deliver(segment)
            self.unifiedDelivered.append(segment)
        }
        self.held.removeAll()
    }

    private func updateTimeline() {
        if self.state == .stopped {
            return
        }
        let now = self.environment.now
        for event in self.timeline.advance(now: now) {
            switch event {
            case let .announce(timestampMs, hostTime):
                self.environment.play(segmentTimestampMs: timestampMs, at: hostTime, offsetMs: 0)
            case let .play(timestampMs, hostTime, offsetMs, announced):
                if !announced {
                    self.environment.play(segmentTimestampMs: timestampMs, at: hostTime, offsetMs: offsetMs)
                }
                self.hasStartedPlaying = true
                self.forgetPlayedSegments(before: timestampMs)
                self.dropRefetches(where: { $0.timestampMs <= timestampMs })
                if self.state != .playing {
                    self.log?("broadcast: playing \(timestampMs) from \(offsetMs) ms")
                }
                self.state = .playing
                self.startAbandonTimerIfNeeded()
            case let .stall(hostTime):
                self.forgetPlayedSegments(before: Int64.max)
                self.stallCount += 1
                self.state = .stalled
                self.log?("broadcast: stalled at \(hostTime), \(self.stallCount) so far")
            }
        }
        self.timelineWake?.cancel()
        self.timelineWake = nil
        if let wake = self.timeline.nextWakeTime {
            self.timelineWake = self.environment.schedule(after: max(0.0, wake - now), { [weak self] in
                guard let self else {
                    return
                }
                self.timelineWake = nil
                self.updateTimeline()
                self.requestSegmentsIfNeeded()
            })
        }
    }

    private func forgetPlayedSegments(before timestampMs: Int64) {
        for key in self.delivered.keys where key < timestampMs {
            self.delivered[key] = nil
        }
    }
}
