import AVFoundation
import BroadcastPlayback
import QuartzCore
import SwiftSignalKit
import TelegramCore
import TelegramMedia
import func TelegramMediaPlayer.extractFFMpegMediaInfo
import TelegramVoip

final class GroupCallStreamPlayer {
    private final class Token: BroadcastCancellable {
        var cancelled = false
        private let disposable = MetaDisposable()

        func set(_ disposable: Disposable) {
            self.disposable.set(disposable)
        }

        func cancel() {
            self.cancelled = true
            self.disposable.dispose()
        }
    }

    private final class Environment: BroadcastPlaybackEnvironment {
        weak var owner: GroupCallStreamPlayer?

        var now: Double { CACurrentMediaTime() }

        func schedule(after delay: Double, _ action: @escaping () -> Void) -> BroadcastCancellable {
            let token = Token()
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, delay)) { [weak self] in
                if let owner = self?.owner, !owner.stopped, !token.cancelled {
                    action()
                }
            }
            return token
        }

        func requestLiveEdge(completion: @escaping (BroadcastEdgeOutcome) -> Void) -> BroadcastCancellable {
            let token = Token()
            if let fetcher = self.owner?.fetcher {
                token.set(fetcher.edge { outcome in
                    if !token.cancelled { completion(outcome) }
                })
            } else {
                completion(.failed)
            }
            return token
        }

        func loadPart(_ request: BroadcastPartRequest, progress: @escaping (Int64) -> Void, completion: @escaping (BroadcastPartOutcome) -> Void) -> BroadcastCancellable {
            let token = Token()
            if let owner = self.owner, let fetcher = owner.fetcher {
                token.set(fetcher.load(request) { [weak owner] outcome, data in
                    guard let owner, !owner.stopped, !token.cancelled else { return }
                    owner.loaded[request] = data
                    completion(outcome)
                })
            } else {
                completion(.notReady)
            }
            return token
        }

        func deliver(_ segment: BroadcastSegment) {
            self.owner?.deliver(segment)
        }

        func play(segmentTimestampMs: Int64, at hostTime: Double, offsetMs: Int) {
        }

        func setUnifiedPosition(_ positionMs: Int64) {
            self.owner?.seek(to: positionMs)
        }

        func discard(_ requests: [BroadcastPartRequest]) {
            self.owner?.discard(requests)
        }

        func requestRejoin() {
            self.owner?.rejoin()
        }
    }

    private let view = MediaPlayerView()
    private let source = BroadcastStreamPlayerSource()
    private let environment = Environment()
    private let controller: BroadcastPlaybackController
    private let partQueue = DispatchQueue(label: "GroupCallStreamPlayer.parts")
    private let networkStateValue = ValuePromise(OngoingGroupCallContext.NetworkState(isConnected: false, isTransitioningFromBroadcastToRtc: false, isBroadcast: true), ignoreRepeated: true)
    private let rejoin: () -> Void
    private var player: ChunkMediaPlayerV2?
    private var statusDisposable: Disposable?
    private var networkDisposable: Disposable?
    private var fetcher: GroupCallBroadcastFetcher?
    private var loaded: [BroadcastPartRequest: Data] = [:]
    private var pendingParts: [Int64: UUID] = [:]
    private var holes = Set<Int64>()
    private var hasPosition = false
    private var stopped = false

    var networkState: Signal<OngoingGroupCallContext.NetworkState, NoError> {
        self.networkStateValue.get()
    }

    init(account: Account, rejoin: @escaping () -> Void) {
        self.rejoin = rejoin
        self.controller = BroadcastPlaybackController(format: .unified, environment: self.environment)
        self.environment.owner = self
        let player = ChunkMediaPlayerV2(
            params: .init(useV2Reader: true),
            source: .custom(self.source),
            video: true,
            enableSound: true,
            minimumPlayableDuration: 0.2,
            playerNode: self.view
        )
        self.player = player
        self.statusDisposable = player.status.start(next: { [weak self] status in
            DispatchQueue.main.async { [weak self] in
                self?.updatePlayback(status)
            }
        })
        self.networkDisposable = (account.networkType |> deliverOnMainQueue).start(next: { [weak self] type in
            self?.controller.setNetworkClass(broadcastNetworkClass(type))
        })
    }

    deinit {
        self.statusDisposable?.dispose()
        self.networkDisposable?.dispose()
    }

    func joined(_ data: OngoingGroupCallContext.AudioStreamData) {
        guard !self.stopped else { return }
        let rejoined = self.fetcher != nil
        self.fetcher = GroupCallBroadcastFetcher(queue: .mainQueue(), audioStreamData: data)
        self.networkStateValue.set(.init(isConnected: true, isTransitioningFromBroadcastToRtc: false, isBroadcast: true))
        if rejoined {
            self.controller.rejoined()
        } else {
            self.controller.start()
        }
    }

    func stop() {
        guard !self.stopped else { return }
        self.stopped = true
        self.controller.stop()
        self.statusDisposable?.dispose()
        self.networkDisposable?.dispose()
        self.player?.pause()
        self.player = nil
        self.view.reset()
        self.source.removeAll()
        self.fetcher = nil
        self.loaded.removeAll()
        self.pendingParts.removeAll()
    }

    func makeVideoView() -> PresentationCallVideoView {
        let view = self.view
        return PresentationCallVideoView(holder: view, view: view, setOnFirstFrameReceived: { [weak view] callback in
            view?.hasSentFramesToDisplay = { callback?(0) }
        }, getOrientation: { .rotation0 }, getAspect: { 0 }, setVideoContentMode: { [weak view] mode in
            view?.setVideoLayerGravity(mode == .resizeAspectFill ? .resizeAspectFill : .resizeAspect)
        }, setOnOrientationUpdated: { _ in }, setOnIsMirroredUpdated: { _ in }, setIsPaused: { _ in }, renderToSize: { [weak view] _, _ in
            view?.updateLayout()
        })
    }

    private func seek(to positionMs: Int64) {
        self.hasPosition = true
        self.player?.seek(timestamp: Double(positionMs) / 1000, play: true)
    }

    private func updatePlayback(_ status: MediaPlayerStatus) {
        guard self.hasPosition, !self.stopped, status.timestamp.isFinite else { return }
        let positionMs = Int64((status.timestamp * 1000).rounded())
        let isPlaying: Bool
        if case .playing = status.status {
            isPlaying = true
        } else {
            isPlaying = false
        }
        self.controller.updatePlayback(positionMs: positionMs, isPlaying: isPlaying)
        self.source.removePlayed(before: positionMs)
        self.holes = self.holes.filter { $0 + BroadcastLivePosition.partDurationMs > positionMs - 2000 }

        if !isPlaying, let hole = self.holes.sorted().first(where: { positionMs >= $0 - 1000 && positionMs < $0 + BroadcastLivePosition.partDurationMs }),
           let next = self.source.partTimestampsMs.first(where: { $0 >= hole + BroadcastLivePosition.partDurationMs }) {
            self.holes = self.holes.filter { $0 >= next }
            self.seek(to: next)
        }
    }

    private func deliver(_ segment: BroadcastSegment) {
        guard let data = self.loaded.removeValue(forKey: segment.primary) else { return }
        let timestamp = segment.timestampMs
        let generation = UUID()
        self.pendingParts[timestamp] = generation
        self.partQueue.async { [weak self] in
            let part = Self.readPart(data)
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.stopped, self.pendingParts[timestamp] == generation else {
                    if let part { EngineTempBox.shared.dispose(part.file) }
                    return
                }
                self.pendingParts.removeValue(forKey: timestamp)
                if let part {
                    self.holes.remove(timestamp)
                    self.source.add(segmentTimestampMs: timestamp, sliceFile: part.file, audioDurationSeconds: part.duration, codecName: part.codecName)
                } else {
                    self.holes.insert(timestamp)
                }
            }
        }
    }

    private func discard(_ requests: [BroadcastPartRequest]) {
        for request in requests {
            self.loaded.removeValue(forKey: request)
            self.pendingParts.removeValue(forKey: request.timestampMs)
            self.holes.remove(request.timestampMs)
        }
        self.source.remove(timestampsMs: requests.map(\.timestampMs))
    }

    private static func readPart(_ data: Data) -> (file: EngineTempBoxFile, duration: Double?, codecName: String?)? {
        guard let slice = broadcastPartSlice(data) else { return nil }
        let file = EngineTempBox.shared.tempFile(fileName: "part.mp4")
        guard (try? slice.write(to: URL(fileURLWithPath: file.path), options: .atomic)) != nil,
              let info = extractFFMpegMediaInfo(path: file.path),
              info.audio != nil || info.video != nil else {
            EngineTempBox.shared.dispose(file)
            return nil
        }
        return (file, info.audio?.duration.seconds, info.video?.codecName)
    }
}
