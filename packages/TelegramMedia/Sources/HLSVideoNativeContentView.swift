import Foundation
import AppKit
import AVFoundation
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramMediaPlayer
import RangeSet
import TGUIKit
import HLSPlayback

public final class HLSVideoNativeContentView: NSView, UniversalVideoContentView {
    static func qualityFiles(file: FileMediaReference) -> (levels: [HLSLevel], files: [HLSNativeQualityFile])? {
        guard let qualitySet = HLSQualitySet(baseFile: file) else {
            return nil
        }
        var candidates: [(level: HLSLevel, file: FileMediaReference, playlist: FileMediaReference, size: Int64)] = []
        for (key, qualityFile) in qualitySet.qualityFiles {
            guard let playlistFile = qualitySet.playlistFiles[key], let size = qualityFile.media.size, size > 0 else {
                continue
            }
            let dimensions = qualityFile.media.dimensions?.size ?? CGSize(width: 1280.0, height: 720.0)
            let bandwidth: Int
            if let duration = qualityFile.media.duration ?? file.media.duration, duration > 0.0 {
                bandwidth = Int(Double(size) / duration) * 8
            } else {
                bandwidth = 1_000_000
            }
            let level = HLSLevel(key: key, width: Int(dimensions.width), height: Int(dimensions.height), bandwidth: bandwidth)
            candidates.append((level, qualityFile, playlistFile, size))
        }
        if candidates.isEmpty {
            return nil
        }
        let levels = HLSLevels.sorted(candidates.map(\.level))
        var files: [HLSNativeQualityFile] = []
        for (index, level) in levels.enumerated() {
            guard let candidate = candidates.first(where: { $0.level == level }) else {
                return nil
            }
            files.append(HLSNativeQualityFile(level: index, file: candidate.file, playlistFile: candidate.playlist, size: candidate.size))
        }
        return (levels, files)
    }

    private let engine: TelegramEngine
    private let qualityResourceIds: [String]
    private let fileReference: FileMediaReference
    private let approximateDuration: Double

    private var requestedBaseRate: Double
    private var volume: Float

    private let playbackCompletedListeners = Bag<() -> Void>()

    private var initializedStatus = false
    private var statusValue: MediaPlayerStatus?
    private var seekId: Int = 0
    private let _status = ValuePromise<MediaPlayerStatus>()
    public var status: Signal<MediaPlayerStatus, NoError> {
        return self._status.get()
    }

    private let _bufferingStatus = Promise<(RangeSet<Int64>, Int64)?>()
    public var bufferingStatus: Signal<(RangeSet<Int64>, Int64)?, NoError> {
        return self._bufferingStatus.get()
    }

    private let _ready = Promise<Void>()
    public var ready: Signal<Void, NoError> {
        return self._ready.get()
    }

    public var fileRef: FileMediaReference {
        return self.fileReference
    }

    private let player: ChunkMediaPlayerV2
    private let playerView: MediaPlayerView

    private let levels: [HLSLevel]
    private let preloadLevel: Int
    private let partStore: HLSNativePartStore
    private let environment: HLSNativeEnvironment
    private let playlistLoader: HLSNativePlaylistLoader
    private let controller: HLSPlaybackController
    private let playerSource: HLSNativePlayerSource

    private var preferredVideoQuality: UniversalVideoContentVideoQuality = .auto
    private var lastPosition: Double = 0.0

    private var playerStatusDisposable: Disposable?
    private var connectionStatusDisposable: Disposable?
    private var networkTypeDisposable: Disposable?

    private let startInitTime = CFAbsoluteTimeGetCurrent()
    private let controllerInitTime = CACurrentMediaTime()
    private var startPlayTime: Double?
    private var didNoteFirstFrame = false
    private let stats = HLSPlaybackStats()
    private var isEffectivelyPlaying = false
    private var isPlayRequested = false
    private var enableSound = true
    private var downloadPriorityDisposables: [Disposable]?
    private var networkClass = "unknown"

    public init?(engine: TelegramEngine, userLocation: MediaResourceUserLocation, fileReference: FileMediaReference, baseRate: Double, volume: Float, initialQuality: UniversalVideoContentVideoQuality) {
        guard let qualities = HLSVideoNativeContentView.qualityFiles(file: fileReference) else {
            return nil
        }
        let levels = qualities.levels
        self.engine = engine
        self.qualityResourceIds = qualities.files.map { EngineMediaResource($0.file.media.resource).id.stringRepresentation }
        self.fileReference = fileReference
        self.approximateDuration = fileReference.media.duration ?? 0.0
        self.requestedBaseRate = baseRate
        self.volume = volume
        self.levels = levels

        var manualLevel: Int?
        if case let .quality(quality) = initialQuality, let key = HLSVideoContent.qualityKey(keys: levels.map(\.key), initialQuality: .quality(quality)) {
            manualLevel = levels.firstIndex(where: { $0.key == key })
        }
        if let manualLevel {
            self.preloadLevel = manualLevel
            self.preferredVideoQuality = .quality(levels[manualLevel].key)
        } else {
            self.preloadLevel = HLSLevels.preloadQualityKey(keys: levels.map(\.key)).flatMap({ key in levels.firstIndex(where: { $0.key == key }) }) ?? 0
        }

        self.playerView = MediaPlayerView()

        self.partStore = HLSNativePartStore(engine: engine, files: qualities.files)
        self.environment = HLSNativeEnvironment(engine: engine, userLocation: userLocation, files: qualities.files, partStore: self.partStore)
        self.playlistLoader = HLSNativePlaylistLoader(engine: engine, userLocation: userLocation, files: qualities.files, startLevel: self.preloadLevel)
        self.controller = HLSPlaybackController(levels: levels, preloadLevel: self.preloadLevel, environment: self.environment)
        self.playerSource = HLSNativePlayerSource()

        self.player = ChunkMediaPlayerV2(
            params: ChunkMediaPlayerV2.MediaDataReaderParams(useV2Reader: true),
            source: .custom(self.playerSource),
            video: true,
            enableSound: true,
            baseRate: baseRate,
            volume: volume,
            playerNode: self.playerView
        )

        super.init(frame: .zero)

        self.player.actionAtEnd = .action({ [weak self] in
            self?.performActionAtEnd()
        })

        self.playerView.frame = CGRect(origin: .zero, size: self.frame.size)
        self.addSubview(self.playerView)

        self.playerView.hasSentFramesToDisplay = { [weak self] in
            self?.noteFirstFrameIfNeeded()
        }

        self._ready.set(.single(Void()))
        self._bufferingStatus.set(.single(nil))

        self.playerStatusDisposable = (self.player.status
        |> deliverOnMainQueue).startStrict(next: { [weak self] status in
            guard let self else {
                return
            }
            self.initializedStatus = true
            self.statusValue = status
            self._status.set(status)
            self.noteStatus(status.status)
        })

        let fileId = fileReference.media.fileId.id
        self.controller.onLog = { line in
            Logger.shared.log("HLSNative", "\(fileId): \(line)")
        }
        self.controller.onBufferChanged = { [weak self] parts, duration in
            self?.bufferChanged(parts: parts, duration: duration)
        }
        self.playlistLoader.onLog = { line in
            Logger.shared.log("HLSNative", "\(fileId): \(line)")
        }
        self.playlistLoader.onPlaylist = { [weak self] level, playlist in
            self?.controller.setPlaylist(playlist, level: level)
        }
        self.playlistLoader.onPlaylistUnavailable = { [weak self] level in
            self?.controller.setPlaylistUnavailable(level: level)
        }
        self.playlistLoader.onPlaylistRejected = { [weak self] level in
            self?.controller.setPlaylistRejected(level: level)
        }
        self.playerSource.onSeek = { [weak self] position in
            guard let self else {
                return
            }
            self.lastPosition = position
            self.controller.seek(to: position)
        }
        self.playerSource.onPlaybackState = { [weak self] position, isPlaying in
            guard let self else {
                return
            }
            self.lastPosition = position
            self.controller.updatePlayback(position: position, isPlaying: isPlaying, rate: self.requestedBaseRate)
            self.stats.notePlayhead(level: self.controller.level(at: position), isPlaying: self.isEffectivelyPlaying, now: CACurrentMediaTime())
            self.updateDownloadPriority()
        }
        self.environment.onDiskStateKnown = { [weak self] in
            guard let self else {
                return
            }
            Logger.shared.log("HLSNative", "\(fileId): disk state known ms=\(Int((CFAbsoluteTimeGetCurrent() - self.startInitTime) * 1000.0))")
            self.controller.start()
        }
        self.networkTypeDisposable = (engine.account.networkType
        |> deliverOnMainQueue).startStrict(next: { [weak self] networkType in
            guard let self else {
                return
            }
            let networkClass = HLSVideoNativeContentView.networkClass(networkType)
            self.networkClass = networkClass.rawValue
            if networkType != .none, let estimate = self.engine.resources.downloadThroughputEstimate(isWifi: networkType == .wifi) {
                _ = HLSBandwidthStore.shared.seedPrior(bitsPerSecond: estimate, networkClass: networkClass)
            }
            self.controller.setNetworkClass(networkClass)
        })
        self.connectionStatusDisposable = (engine.account.network.connectionStatus
        |> deliverOnMainQueue).startStrict(next: { [weak self] status in
            switch status {
            case .online, .updating:
                self?.controller.setNetworkAvailable(true)
            case .waitingForNetwork, .connecting:
                self?.controller.setNetworkAvailable(false)
            }
        })

        if let manualLevel {
            self.controller.setManualLevel(manualLevel)
        }
        self.playlistLoader.start()
        if self.environment.isDiskStateKnown {
            self.controller.start()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.logSession()
        self.controller.stop()
        self.playlistLoader.cancel()
        self.partStore.removeAll()
        self.playerStatusDisposable?.dispose()
        self.connectionStatusDisposable?.dispose()
        self.networkTypeDisposable?.dispose()
        self.downloadPriorityDisposables?.forEach { $0.dispose() }
    }

    private func bufferChanged(parts: [HLSBufferedPart], duration: Double?) {
        let playerParts = self.partStore.parts(for: parts)
        self.playerSource.partsPromise.set(.single(ChunkMediaPlayerPartsState(duration: duration, content: .parts(playerParts), startNotBefore: self.controller.startNotBefore)))
        self._bufferingStatus.set(.single(hlsBufferingStatus(parts: parts, duration: duration)))
        self.updateDownloadPriority()
    }

    private func updateDownloadPriority() {
        let isOn: Bool
        if !self.enableSound || !self.isPlayRequested {
            isOn = false
        } else if self.downloadPriorityDisposables != nil {
            isOn = self.controller.forwardBufferLength < 20.0
        } else {
            isOn = self.controller.forwardBufferLength < 10.0
        }
        if isOn == (self.downloadPriorityDisposables != nil) {
            return
        }
        if isOn {
            self.downloadPriorityDisposables = self.qualityResourceIds.map { resourceId in
                self.engine.resources.pushPriorityDownload(resourceId: resourceId, priority: 2)
            }
        } else {
            self.downloadPriorityDisposables?.forEach { $0.dispose() }
            self.downloadPriorityDisposables = nil
        }
    }

    private static func networkClass(_ networkType: NetworkType) -> HLSNetworkClass {
        switch networkType {
        case .none:
            return HLSNetworkClass("none")
        case .wifi:
            return HLSNetworkClass("wifi")
        }
    }

    private func noteStatus(_ status: MediaPlayerPlaybackStatus) {
        let now = CACurrentMediaTime()
        switch status {
        case let .buffering(_, whilePlaying):
            self.isEffectivelyPlaying = false
            self.isPlayRequested = whilePlaying
            self.stats.noteStatus(isBuffering: true, isPlayRequested: whilePlaying, now: now)
        case .playing:
            self.isEffectivelyPlaying = true
            self.isPlayRequested = true
            self.noteFirstFrameIfNeeded()
            self.stats.noteStatus(isBuffering: false, isPlayRequested: true, now: now)
        case .paused:
            self.isEffectivelyPlaying = false
            self.isPlayRequested = false
            self.stats.noteStatus(isBuffering: false, isPlayRequested: false, now: now)
        }
        self.stats.notePlayhead(level: self.controller.level(at: self.lastPosition), isPlaying: self.isEffectivelyPlaying, now: now)
        self.updateDownloadPriority()
    }

    private func sinceInitMs(_ time: Double?) -> Int {
        return time.map { Int(($0 - self.controllerInitTime) * 1000.0) } ?? -1
    }

    private func logSession() {
        let summary = self.stats.summary
        let levels = summary.secondsPerLevel.sorted(by: { $0.key < $1.key }).compactMap { level, seconds -> String? in
            guard level >= 0 && level < self.levels.count else {
                return nil
            }
            return "\(self.levels[level].key):\(String(format: "%.1f", seconds))"
        }.joined(separator: ",")
        let estimate = self.controller.estimate.map { "\(Int($0))" } ?? "none"
        let line = "HLSSession file=\(self.fileReference.media.fileId.id) network=\(self.networkClass) stalls=\(summary.stallCount) stallMs=\(Int(summary.stallTime * 1000.0)) seekWaits=\(summary.seekWaitCount) seekWaitMs=\(Int(summary.seekWaitTime * 1000.0)) playedMs=\(Int(summary.playedTime * 1000.0)) levels=\(levels.isEmpty ? "none" : levels) switches=\(summary.levelSwitches) networkBytes=\(self.controller.networkBytesLoaded) diskBytes=\(self.controller.diskBytesAppended) abandons=\(self.controller.abandonCount) estimate=\(estimate)"
        Logger.shared.log("HLSSession", line)
        #if DEBUG
        NSLog("%@", line)
        #endif
    }

    private func notePlayRequested() {
        self.isPlayRequested = true
        self.updateDownloadPriority()
        if self.startPlayTime == nil {
            self.startPlayTime = CFAbsoluteTimeGetCurrent()
        }
    }

    private func noteFirstFrameIfNeeded() {
        if self.didNoteFirstFrame {
            return
        }
        self.didNoteFirstFrame = true
        self.stats.noteFirstFrame(now: CACurrentMediaTime())

        let firstFrameTime = CFAbsoluteTimeGetCurrent()
        let initToPlayMs = self.startPlayTime.map { Int(($0 - self.startInitTime) * 1000.0) } ?? -1
        let playToFirstFrameMs = self.startPlayTime.map { Int((firstFrameTime - $0) * 1000.0) } ?? -1
        let initToFirstFrameMs = Int((firstFrameTime - self.startInitTime) * 1000.0)
        let startQuality = self.controller.firstSegmentLevel.map { "\(self.levels[$0].key)" } ?? "unknown"
        let firstSegment: String
        switch self.controller.firstSegmentSource {
        case .disk:
            firstSegment = "disk"
        case .network:
            firstSegment = "network"
        case .none:
            firstSegment = "unknown"
        }
        let timeline = self.controller.timeline
        let line = "HLSStart file=\(self.fileReference.media.fileId.id) engine=native initToPlayMs=\(initToPlayMs) playToFirstFrameMs=\(playToFirstFrameMs) initToFirstFrameMs=\(initToFirstFrameMs) startQuality=\(startQuality) firstSegment=\(firstSegment) startedMs=\(self.sinceInitMs(timeline.started)) firstLoadMs=\(self.sinceInitMs(timeline.firstLoadIssued)) firstLoadDoneMs=\(self.sinceInitMs(timeline.firstLoadCompleted)) firstAppendMs=\(self.sinceInitMs(timeline.firstAppendRequested)) firstAppendDoneMs=\(self.sinceInitMs(timeline.firstAppendCompleted))"
        Logger.shared.log("HLSStart", line)
        #if DEBUG
        NSLog("%@", line)
        #endif
    }

    private func performActionAtEnd() {
        for listener in self.playbackCompletedListeners.copyItems() {
            listener()
        }
    }

    public var duration: Double {
        if let statusValue = self.statusValue, statusValue.duration > 0.0 {
            return statusValue.duration
        }
        return self.approximateDuration
    }

    public func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: self.playerView, frame: CGRect(origin: .zero, size: size))
    }

    public func play() {
        self.notePlayRequested()
        if !self.initializedStatus {
            self._status.set(MediaPlayerStatus(generationTimestamp: 0.0, duration: self.approximateDuration, dimensions: CGSize(), timestamp: 0.0, baseRate: self.requestedBaseRate, volume: self.volume, seekId: self.seekId, status: .buffering(initial: true, whilePlaying: true)))
        }
        self.player.play()
    }

    public func pause() {
        self.isPlayRequested = false
        self.updateDownloadPriority()
        self.player.pause()
    }

    public func togglePlayPause() {
        self.player.togglePlayPause(faded: false)
    }

    public func setSoundEnabled(_ value: Bool) {
        if self.enableSound != value {
            self.enableSound = value
            if value {
                self.player.playOnceWithSound(playAndRecord: false, seek: .none)
            } else {
                self.player.continuePlayingWithoutSound(seek: .none)
            }
            self.controller.setCap(value ? nil : self.preloadLevel)
            self.updateDownloadPriority()
        }
    }

    public func setVolume(_ value: Float) {
        self.volume = value
        self.player.setVolume(volume: value)
    }

    public func seek(_ timestamp: Double) {
        self.stats.noteSeek(now: CACurrentMediaTime())
        self.seekId += 1
        self.player.seek(timestamp: timestamp, play: nil)
    }

    public func seek(_ timestamp: Double, play: Bool) {
        if play {
            self.notePlayRequested()
        }
        self.stats.noteSeek(now: CACurrentMediaTime())
        self.seekId += 1
        self.player.seek(timestamp: timestamp, play: play)
    }

    public func seekFrame(_ timestamp: Double) {
        self.seek(timestamp)
    }

    public func playOnceWithSound(playAndRecord: Bool, actionAtEnd: MediaPlayerActionAtEnd) {
        self.notePlayRequested()
        self.player.playOnceWithSound(playAndRecord: playAndRecord, seek: .none)
    }

    public func setActionAtEnd(_ value: MediaPlayerActionAtEnd) {
        switch value {
        case let .loop(f):
            self.player.actionAtEnd = .loop(f)
        case let .action(f):
            self.player.actionAtEnd = .action(f)
        case let .loopDisablingSound(f):
            self.player.actionAtEnd = .loopDisablingSound(f)
        case .stop:
            self.player.actionAtEnd = .stop
        }
    }

    public func setSoundMuted(soundMuted: Bool) {
        self.player.setSoundMuted(soundMuted: soundMuted)
    }

    public func setBaseRate(_ baseRate: Double) {
        self.requestedBaseRate = baseRate
        self.player.setBaseRate(baseRate)
    }

    public func setVideoQuality(_ videoQuality: UniversalVideoContentVideoQuality) {
        switch videoQuality {
        case .auto:
            self.preferredVideoQuality = .auto
            self.controller.setManualLevel(nil)
        case let .quality(quality):
            if let index = self.levels.firstIndex(where: { $0.key == quality }) {
                self.preferredVideoQuality = .quality(quality)
                self.controller.setManualLevel(index)
            }
        }
    }

    public func videoQualityState() -> (current: Int, preferred: UniversalVideoContentVideoQuality, available: [Int])? {
        if self.levels.isEmpty {
            return nil
        }
        let currentLevel = self.controller.level(at: self.lastPosition) ?? self.controller.startLevel ?? self.preloadLevel
        var keys = self.levels.indices.filter({ !self.controller.isPlaylistRejected(level: $0) }).map({ self.levels[$0].key })
        if keys.isEmpty {
            keys = self.levels.map(\.key)
        }
        let available = Array(Set(keys)).sorted(by: { $0 > $1 })
        return (self.levels[currentLevel].key, self.preferredVideoQuality, available)
    }

    public func addPlaybackCompleted(_ f: @escaping () -> Void) -> Int {
        return self.playbackCompletedListeners.add(f)
    }

    public func removePlaybackCompleted(_ index: Int) {
        self.playbackCompletedListeners.remove(index)
    }

    public func fetchControl(_ control: UniversalVideoNodeFetchControl) {
    }

    public func setVideoLayerGravity(_ gravity: AVLayerVideoGravity) {
        self.playerView.setVideoLayerGravity(gravity)
    }
}
