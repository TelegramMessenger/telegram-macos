import Foundation
import AVFoundation
import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramMediaPlayer
import TelegramMedia
import RangeSet
import TelegramCore
import InAppSettings

public final class ChunkedNativeMediaPlayer : View, UniversalVideoContentView {

    public var duration: Double {
        return reference.media.duration ?? 0
    }

    private let mediaPlayerView: MediaPlayerView
    private let mediaPlayer: ChunkMediaPlayerV2
    private let postbox: Postbox
    private let reference: FileMediaReference
    private let playbackCompletedListeners = Bag<() -> Void>()
    private let fetchDisposable = MetaDisposable()

    public var fileRef: FileMediaReference {
        return self.reference
    }

    public init(postbox: Postbox, reference: FileMediaReference, fetchAutomatically: Bool = false) {
        self.postbox = postbox
        self.reference = reference
        let mediaPlayerView = MediaPlayerView()
        self.mediaPlayerView = mediaPlayerView
        self.mediaPlayer = ChunkMediaPlayerV2(
            params: ChunkMediaPlayerV2.MediaDataReaderParams(useV2Reader: true),
            source: .directFetch(ChunkMediaPlayerV2.SourceDescription.ResourceDescription(
                postbox: postbox,
                size: reference.media.size ?? 0,
                reference: reference.resourceReference(reference.media.resource),
                userLocation: reference.userLocation,
                userContentType: reference.userContentType,
                statsCategory: statsCategoryForFileWithAttributes(reference.media.attributes),
                fetchAutomatically: fetchAutomatically
            )),
            video: true,
            enableSound: true,
            baseRate: FastSettings.playingVideoRate,
            volume: FastSettings.volumeRate,
            playerNode: mediaPlayerView
        )
        super.init()

        addSubview(mediaPlayerView)

        mediaPlayer.actionAtEnd = .action({ [weak self] in
            self?.performActionAtEnd()
        })
    }

    private func performActionAtEnd() {
        for listener in self.playbackCompletedListeners.copyItems() {
            listener()
        }
    }

    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public var ready: Signal<Void, NoError> {
        return .single(Void())
    }

    public var status: Signal<MediaPlayerStatus, NoError> {
        return mediaPlayer.status
    }

    public var bufferingStatus: Signal<(RangeSet<Int64>, Int64)?, NoError> {
        let size = reference.media.resource.size ?? 0
        return postbox.mediaBox.resourceRangesStatus(reference.media.resource)
            |> map { ranges -> (RangeSet<Int64>, Int64)? in
                return (ranges, size)
        } |> deliverOnMainQueue
    }

    public func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: mediaPlayerView, frame: size.bounds)
    }

    public override func layout() {
        super.layout()
        self.updateLayout(size: self.bounds.size, transition: .immediate)
    }

    public func play() {
        mediaPlayer.play()
    }

    public func pause() {
        mediaPlayer.pause()
    }

    public func togglePlayPause() {
        mediaPlayer.togglePlayPause(faded: false)
    }

    public func setSoundEnabled(_ value: Bool) {
    }

    public func seek(_ timestamp: Double) {
        mediaPlayer.seek(timestamp: timestamp, play: nil)
    }

    public func seek(_ timestamp: Double, play: Bool) {
        mediaPlayer.seek(timestamp: timestamp, play: play)
    }

    public func playOnceWithSound(playAndRecord: Bool, actionAtEnd: MediaPlayerActionAtEnd) {
    }

    public func setActionAtEnd(_ value: MediaPlayerActionAtEnd) {
        switch value {
        case let .loop(f):
            mediaPlayer.actionAtEnd = .loop(f)
        case let .action(f):
            mediaPlayer.actionAtEnd = .action(f)
        case let .loopDisablingSound(f):
            mediaPlayer.actionAtEnd = .loopDisablingSound(f)
        case .stop:
            mediaPlayer.actionAtEnd = .stop
        }
    }

    public func setSoundMuted(soundMuted: Bool) {
    }

    public func setBaseRate(_ baseRate: Double) {
        self.mediaPlayer.setBaseRate(baseRate)
    }

    public func setVideoQuality(_ videoQuality: UniversalVideoContentVideoQuality) {
    }

    public func videoQualityState() -> (current: Int, preferred: UniversalVideoContentVideoQuality, available: [Int])? {
        return nil
    }

    public func addPlaybackCompleted(_ f: @escaping () -> Void) -> Int {
        return self.playbackCompletedListeners.add(f)
    }

    public func removePlaybackCompleted(_ index: Int) {
        self.playbackCompletedListeners.remove(index)
    }

    public func fetchControl(_ control: UniversalVideoNodeFetchControl) {
        switch control {
        case .fetch:
            self.fetchDisposable.set(fetchedMediaResource(mediaBox: self.postbox.mediaBox, userLocation: self.reference.userLocation, userContentType: .video, reference: self.reference.resourceReference(self.reference.media.resource), statsCategory: statsCategoryForFileWithAttributes(self.reference.media.attributes)).start())
        case .cancel:
            self.postbox.mediaBox.cancelInteractiveResourceFetch(self.reference.media.resource)
        }
    }

    public func setVolume(_ value: Float) {
        self.mediaPlayer.setVolume(volume: value)
    }

    public func setVideoLayerGravity(_ gravity: AVLayerVideoGravity) {
        self.mediaPlayerView.setVideoLayerGravity(gravity)
    }

    deinit {
        fetchDisposable.dispose()
    }
}
