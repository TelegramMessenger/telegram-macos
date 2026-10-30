import Cocoa
import Foundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import TelegramMedia
import TelegramMediaUtils
import ObjcUtils
import TGVideoCameraMovie
import AVFoundation

public class VideoRecorderModalView: View {
    private let captureLayer: AVCaptureVideoPreviewLayer = AVCaptureVideoPreviewLayer()
    private let captureContainer: Control = Control()
    private let placeholderView: ImageView = ImageView()
    private let progressView:  RadialProgressView
    private let previewPlayer: GIFPlayerView = GIFPlayerView()
    private let shadowView: ImageView = ImageView()

    private var pausedPlayer: AVPlayer?
    private var pausedPlayerLayer: AVPlayerLayer?
    private var pausedPath: String?
    private var pausedTrimRange: Range<Double>?
    private var pausedVideoRange: Range<Double>?
    private var pausedEndObserver: Any?
    private var pausedStatusObserver: NSKeyValueObservation?
    private var pausedTimeObserver: Any?
    private var pendingPreviewCommand: (trimRange: Range<Double>?, seekTo: Double, play: Bool)?
    private var requestedPlayback = false
    private var requestedPosition: Double = 0
    private var seekGeneration = UUID()
    private var isSeeking = false

    public var previewUpdated: ((VideoRecorderPreviewState) -> Void)?
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        // Drawing code here.
    }
    
    public init(frame frameRect: NSRect, thumbnail: CGImage?) {
        progressView = RadialProgressView(theme: RadialProgressTheme(backgroundColor: .clear, foregroundColor: theme.colors.accent, icon: nil, iconInset: NSEdgeInsets(), lineWidth: 4), twist: false)
        super.init(frame: frameRect)
        addSubview(shadowView)
        addSubview(captureContainer)

        captureContainer.set(handler: { [weak self] _ in
            self?.togglePreviewPlayback()
        }, for: .Click)

        
        
        captureContainer.addSubview(previewPlayer)
        
        backgroundColor = .clear
        captureContainer.setFrameSize(frameRect.width - 36, frameRect.height - 36)
        placeholderView.animates = false
        placeholderView.isAccessibilityDecorative = true
        shadowView.isAccessibilityDecorative = true
        placeholderView.image = thumbnail ?? TelegramThemeHooks.shared.image(.videoMessagePlaceholder).precomposed()
        placeholderView.frame = bounds
        captureContainer.addSubview(placeholderView)
        placeholderView.center()
        
        captureContainer.layer?.addSublayer(captureLayer)
        captureLayer.videoGravity = .resizeAspectFill
        captureLayer.frame = captureContainer.bounds
        captureContainer.layer?.cornerRadius = captureContainer.frame.width/2
        captureLayer.actions = ["opacity": NSNull()]
        captureLayer.opacity = 0
        
        progressView.frame = NSMakeRect(0, 0, captureContainer.frame.width + 17, captureContainer.frame.height + 17)
        addSubview(progressView)
        
        previewPlayer.frame = captureContainer.bounds
        
        shadowView.image = TelegramThemeHooks.shared.image(.iconVideoMessageShadow).precomposed()
        shadowView.setFrameSize(NSMakeSize(frameRect.width, frameRect.height))
    }
    
    public var previewView: NSView {
        return captureContainer
    }

    public func updateWithSession(_ session: AVCaptureSession) {
        captureLayer.session = session
        captureLayer.connection?.automaticallyAdjustsVideoMirroring = false
        captureLayer.connection?.isVideoMirrored = true
    }
    
    public func updatePaused(_ path: String) {
        hideGIFPreview()
        setupPausedPlayer(path)
        placeholderView.layer?.opacity = 0
        captureLayer.opacity = 0
    }
    
    public func updateResumed() {
        hideGIFPreview()
        captureLayer.opacity = 1
        if pausedPlayer != nil {
            fadeOutPausedPlayer()
        } else {
            placeholderView.layer?.opacity = 1
        }
    }

    private func fadeOutPausedPlayer() {
        guard let layer = pausedPlayerLayer else {
            tearDownPausedPlayer()
            return
        }
        tearDownPausedPlayer(removeLayer: false)
        layer.opacity = 0
        layer.animateAlpha(from: 1, to: 0, duration: 0.3)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak layer] in
            layer?.removeFromSuperlayer()
        }
    }
    
    private func hideGIFPreview() {
        previewPlayer.set(data: nil)
        previewPlayer.isHidden = true
    }
    
    public func updatePreview(trimRange: Range<Double>?, seekTo: Double, play: Bool) {
        guard seekTo.isFinite, let player = pausedPlayer else {
            return
        }
        seekGeneration = UUID()
        requestedPlayback = play
        pausedTrimRange = trimRange
        requestedPosition = clampedPreviewTime(seekTo, duration: CMTimeGetSeconds(player.currentItem?.duration ?? .zero))
        isSeeking = true
        player.pause()
        publishPreview(position: requestedPosition)
        guard player.currentItem?.status == .readyToPlay else {
            pendingPreviewCommand = (trimRange, seekTo, play)
            return
        }
        pendingPreviewCommand = nil
        if let trimRange {
            let duration = CMTimeGetSeconds(player.currentItem?.duration ?? .zero)
            let end = duration.isFinite && duration > 0 ? min(duration, trimRange.upperBound) : trimRange.upperBound
            player.currentItem?.forwardPlaybackEndTime = CMTimeMakeWithSeconds(end, preferredTimescale: 1000)
        } else {
            player.currentItem?.forwardPlaybackEndTime = .invalid
        }
        seekPreview(to: seekTo, play: play)
    }

    public func togglePreviewPlayback() {
        guard let player = pausedPlayer else { return }
        let time = isSeeking ? requestedPosition : CMTimeGetSeconds(player.currentTime())
        let lower = pausedTrimRange?.lowerBound ?? pausedVideoRange?.lowerBound ?? 0
        let upper = pausedTrimRange?.upperBound ?? pausedVideoRange?.upperBound ?? .greatestFiniteMagnitude
        let position = time.isFinite && time >= lower && time < upper - 0.05 ? time : lower
        updatePreview(trimRange: pausedTrimRange, seekTo: position, play: !requestedPlayback)
    }

    private func publishPreview(position: Double? = nil) {
        let time = position ?? (isSeeking ? requestedPosition : pausedPlayer.map { CMTimeGetSeconds($0.currentTime()) } ?? 0)
        previewUpdated?(VideoRecorderPreviewState(position: time.isFinite ? time : 0, isPlaying: requestedPlayback))
    }
    
    private func seekPreview(to seconds: Double, play: Bool) {
        guard let player = pausedPlayer, let item = player.currentItem else {
            return
        }
        let duration = CMTimeGetSeconds(item.duration)
        if item.status != .readyToPlay, !play {
            return
        }
        let clamped = clampedPreviewTime(seconds, duration: duration)
        let generation = UUID()
        seekGeneration = generation
        player.seek(to: CMTimeMakeWithSeconds(max(0, clamped), preferredTimescale: 1000), toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: { [weak self, weak player] finished in
            DispatchQueue.main.async {
                guard let self, self.pausedPlayer === player, self.seekGeneration == generation else { return }
                self.isSeeking = false
                if finished, play, self.requestedPlayback {
                    player?.play()
                } else {
                    self.requestedPlayback = false
                    player?.pause()
                }
                self.publishPreview()
            }
        })
    }

    private func clampedPreviewTime(_ seconds: Double, duration: Double) -> Double {
        var end = seconds
        if duration.isFinite, duration > 0 {
            end = min(end, duration - 0.05)
        }
        if let video = pausedVideoRange {
            end = min(end, video.upperBound - 0.05)
            end = max(video.lowerBound, end)
        }
        if let trim = pausedTrimRange {
            end = max(trim.lowerBound, min(end, trim.upperBound - 0.05))
        }
        return end
    }

    private func videoRange(of path: String) -> Range<Double>? {
        guard let track = AVURLAsset(url: URL(fileURLWithPath: path)).tracks(withMediaType: .video).first else {
            return nil
        }
        let start = CMTimeGetSeconds(track.timeRange.start)
        let end = CMTimeGetSeconds(track.timeRange.end)
        guard start.isFinite, end.isFinite, end > start else {
            return nil
        }
        return start ..< end
    }
    
    private func setupPausedPlayer(_ path: String) {
        if pausedPath == path {
            return
        }
        tearDownPausedPlayer()
        pausedPath = path
        pausedVideoRange = videoRange(of: path)
        
        let player = AVPlayer(url: URL(fileURLWithPath: path))
        player.actionAtItemEnd = .pause
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        layer.backgroundColor = NSColor.black.cgColor
        layer.frame = captureContainer.bounds
        captureContainer.layer?.addSublayer(layer)
        
        pausedPlayer = player
        pausedPlayerLayer = layer
        requestedPosition = pausedVideoRange?.lowerBound ?? 0
        requestedPlayback = false
        pausedTimeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 10), queue: .main, using: { [weak self, weak player] time in
            guard let self, self.pausedPlayer === player, !self.isSeeking else { return }
            self.publishPreview(position: CMTimeGetSeconds(time))
        })
        pausedStatusObserver = player.currentItem?.observe(\.status, options: [.initial, .new], changeHandler: { [weak self, weak player] _, _ in
            DispatchQueue.main.async {
                guard let self, self.pausedPlayer === player, player?.currentItem?.status == .readyToPlay,
                      let command = self.pendingPreviewCommand else { return }
                self.updatePreview(trimRange: command.trimRange, seekTo: command.seekTo, play: command.play)
            }
        })
        pausedEndObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main, using: { [weak self, weak player] _ in
            guard let self, self.pausedPlayer === player, self.requestedPlayback else { return }
            self.updatePreview(trimRange: self.pausedTrimRange, seekTo: self.pausedTrimRange?.lowerBound ?? self.pausedVideoRange?.lowerBound ?? 0, play: false)
        })
        publishPreview(position: requestedPosition)
    }

    public func stopPreview() {
        tearDownPausedPlayer()
        hideGIFPreview()
    }
    
    private func tearDownPausedPlayer(removeLayer: Bool = true) {
        seekGeneration = UUID()
        isSeeking = false
        requestedPlayback = false
        requestedPosition = 0
        if let pausedEndObserver {
            NotificationCenter.default.removeObserver(pausedEndObserver)
        }
        pausedEndObserver = nil
        pausedStatusObserver = nil
        pendingPreviewCommand = nil
        if let pausedTimeObserver {
            pausedPlayer?.removeTimeObserver(pausedTimeObserver)
        }
        pausedTimeObserver = nil
        pausedPlayer?.pause()
        pausedPlayer = nil
        if removeLayer {
            pausedPlayerLayer?.removeFromSuperlayer()
        }
        pausedPlayerLayer = nil
        pausedTrimRange = nil
        pausedVideoRange = nil
        pausedPath = nil
        publishPreview(position: 0)
    }
    
    deinit {
        tearDownPausedPlayer()
    }
    
    public func updateForPreview(_ path:String? = nil, preview: CGImage?) -> Void {
        tearDownPausedPlayer()
        previewPlayer.set(data: AVGifData.dataFrom(path))
        placeholderView.image = preview
        
        previewPlayer.isHidden = path == nil
        
        if let _ = path {
            placeholderView.layer?.animateAlpha(from: 1, to: 0, duration: 0.2)
        } else {
            placeholderView.layer?.opacity = 1
        }
        
        progressView.change(opacity: 0, removeOnCompletion: false) { [weak self] completed in
            if completed {
                self?.progressView.removeFromSuperview()
            }
        }
        captureLayer.removeFromSuperlayer()

    }
    
    public func updateProgress(_ progress: Float) {
        progressView.state = .ImpossibleFetching(progress: progress, force: true)
    }
    
    public func didStartedRecording() {
        captureLayer.opacity = 1
        placeholderView.change(opacity: 0.0, duration: 0.3)
       
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        captureContainer.center()
        progressView.center()
        shadowView.center()
        pausedPlayerLayer?.frame = captureContainer.bounds
    }
    
}
