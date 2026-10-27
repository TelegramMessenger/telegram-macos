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

public class VideoRecorderModalController: ModalViewController {

    private let pipeline: VideoRecorderPipeline
    private let state: ChatRecordingState

    private let disposable = MetaDisposable()
    private let countdownDisposable = MetaDisposable()
    private let previewDisposable = MetaDisposable()
    private var isPaused: Bool = false
    private var didRequestAutomaticSubmission = false

    public override func viewClass() -> AnyClass {
        return VideoRecorderModalView.self
    }

    private var genericView: VideoRecorderModalView {
        return view as! VideoRecorderModalView
    }

    public var previewView: NSView? {
        return isLoaded() ? genericView.previewView : nil
    }

    public let sendMedia:([MediaSenderContainer])->Void
    public let resetState:()->Void
    public init(state: ChatRecordingState, pipeline: VideoRecorderPipeline, sendMedia:@escaping([MediaSenderContainer])->Void, resetState:@escaping()->Void) {
        self.sendMedia = sendMedia
        self.state = state
        self.pipeline = pipeline
        self.resetState = resetState
        super.init(frame: NSMakeRect(0, 0, 300, 300))
        bar = .init(height: 0)
    }

    public var pathForThumbnail: String {
        return NSTemporaryDirectory() + "video_last_thumbnail.jpg"
    }


    private func saveThumbnail(_ thumb: CGImage) {
        let blurred: CGImage = thumb.blurred
        _ = blurred.saveToFile(pathForThumbnail)
    }

    public override func initializer() -> NSView {
        return VideoRecorderModalView(frame: NSMakeRect(_frameRect.minX, _frameRect.minY, _frameRect.width, _frameRect.height - bar.height), thumbnail: .loadFromFile(""))
    }


    public override func viewDidLoad() {
        super.viewDidLoad()
        readyOnce()
        genericView.updateWithSession(pipeline.session)
        pipeline.start()

        if let state = self.state as? ChatRecordingVideoState {
            genericView.previewUpdated = { [weak state] value in
                state?.previewState.set(value)
            }
            previewDisposable.set((state.previewCommands.get() |> deliverOnMainQueue).start(next: { [weak self] command in
                switch command {
                case let .update(trimRange, seekTo, play):
                    self?.genericView.updatePreview(trimRange: trimRange, seekTo: seekTo, play: play)
                case .togglePlayback:
                    self?.genericView.togglePreviewPlayback()
                }
            }))
        }

        disposable.set((pipeline.statePromise.get() |> deliverOnMainQueue).start(next: { [weak self] status in
            if let strongSelf = self {
                switch status {
                case let .finishRecording(path, _, _, thumb):
                    strongSelf.countdownDisposable.set(nil)
                    strongSelf.genericView.updateForPreview(path, preview: thumb)
                    strongSelf.pipeline.stopCapture()
                case .recording:
                    strongSelf.isPaused = false
                    strongSelf.genericView.updateResumed()
                    strongSelf.genericView.didStartedRecording()
                    strongSelf.runTimer()
                case let .paused(info):
                    strongSelf.isPaused = true
                    strongSelf.countdownDisposable.set(nil)
                    strongSelf.genericView.updatePaused(info.path)
                case .madeThumbnail(let thumb):
                    strongSelf.saveThumbnail(thumb)
                case .stopped:
                    strongSelf.countdownDisposable.set(nil)
                    strongSelf.pipeline.stopCapture()
                    strongSelf.close()
                case .failed:
                    strongSelf.countdownDisposable.set(nil)
                    strongSelf.pipeline.stopCapture()
                    strongSelf.resetState()
                    strongSelf.close()
                default:
                    break
                }
            }
        }))


    }

    public override var canBecomeResponder: Bool {
        return false
    }

    public override func becomeFirstResponder() -> Bool? {
        return nil
    }

    private func runTimer() {
        countdownDisposable.set((pipeline.powerAndDuration.get() |> deliverOnMainQueue).start(next: { [weak self] _, duration in
            guard let `self` = self else {return}
            self.genericView.updateProgress(Float(duration / VideoRecorderPipeline.videoMessageMaxDuration))
            if duration >= VideoRecorderPipeline.videoMessageMaxDuration, !self.isPaused, !self.didRequestAutomaticSubmission {
                self.didRequestAutomaticSubmission = true
                let sendMedia = self.sendMedia
                self.stopAndMakeRecordedVideo()
                let data = self.state.contextBoundData
                _ = data.start(next: { medias in
                    sendMedia(medias)
                })
                self.resetState()
                self.close()
            }

        }))
    }

    deinit {
        disposable.dispose()
        countdownDisposable.dispose()
        previewDisposable.dispose()
    }

    public override var handleAllEvents: Bool {
        return false
    }

    private func stopAndMakeRecordedVideo() {
        countdownDisposable.set(nil)
        pipeline.stop()
    }

    public override var handleEvents: Bool {
        return true
    }

    public override var closable: Bool {
        return false
    }


    public override func escapeKeyAction() -> KeyHandlerResult {
        self.close()
        self.state.cancel()
        self.resetState()
        return .invoked
    }



    public override var containerBackground: NSColor {
        return .clear
    }

    public override var background: NSColor {
        return .clear
    }


    public override func viewWillDisappear(_ animated: Bool) {
        previewDisposable.set(nil)
        countdownDisposable.set(nil)
        genericView.stopPreview()
        super.viewWillDisappear(animated)
    }

    public override var isFullScreen: Bool {
        return false
    }
}
