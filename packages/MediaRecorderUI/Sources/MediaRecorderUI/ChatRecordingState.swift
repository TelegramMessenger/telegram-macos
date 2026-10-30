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
public enum ChatRecordingStatus : Equatable {
    case paused(duration: Double)
    case recording(duration: Double)
}

private func trimmedVideoFile(_ path: String, trimRange: Range<Double>) -> Signal<(String, Double)?, NoError> {
    return exportTrimmedVideo(path: path, range: trimRange) |> deliverOnMainQueue |> map { output in
        guard let output, output.path != path else { return nil }
        let duration = output.duration
        guard duration.isFinite, duration > 0, Int(exactly: ceil(duration)) != nil,
            let outputPath = output.takePath() else {
            output.discard()
            return nil
        }
        removeFile(at: path)
        return (outputPath, duration)
    }
}

public enum ChatRecordingSubmissionState {
    case idle
    case preparing
    case failed
}

public struct ChatRecordingPreviewData : Equatable {
    public let path: String
    public let duration: Double
    public let waveform: AudioWaveform?
    public let thumb: CGImage?
    
    public static func ==(lhs: ChatRecordingPreviewData, rhs: ChatRecordingPreviewData) -> Bool {
        return lhs.path == rhs.path && lhs.duration == rhs.duration && lhs.waveform == rhs.waveform && lhs.thumb === rhs.thumb
    }
    public init(path: String, duration: Double, waveform: AudioWaveform?, thumb: CGImage?) {
        self.path = path
        self.duration = duration
        self.waveform = waveform
        self.thumb = thumb
    }
}


open class ChatRecordingState : Equatable {
    public final var contextBoundData: Signal<[MediaSenderContainer], NoError> {
        return data |> deliverOnMainQueue
    }
  
    public let autohold: Bool
    public let holdpromise: ValuePromise<Bool> = ValuePromise()
    
    public var isOneTime: Bool = false
    public private(set) var isCancelled: Bool = false
    public private(set) var isPreparingSubmission = false
    public let submissionState = ValuePromise<ChatRecordingSubmissionState>(.idle)
    private var hasSubmitted = false
    private var trimOperationId: UUID?
    private let submissionDisposable = MetaDisposable()
    
    public private(set) var trimRange: Range<Double>?
    public private(set) var trimSourceDuration: Double?
    
    public init(autohold: Bool) {
        self.autohold = autohold
        holdpromise.set(autohold)
    }
    
    public var micLevel: Signal<Float, NoError> {
        return .complete()
    }
    public var status: Signal<ChatRecordingStatus, NoError> {
        return .complete()
    }
    public var data:Signal<[MediaSenderContainer], NoError>  {
        return .complete()
    }
    
    public var canPause: Bool {
        return false
    }
    
    public var previewData: Signal<ChatRecordingPreviewData?, NoError> {
        return .single(nil)
    }
    
    public func updateTrimRange(_ range: Range<Double>?, duration: Double? = nil) {
        self.trimRange = range
        if let duration {
            self.trimSourceDuration = duration
        }
    }
    
    public var isTrimmed: Bool {
        guard let trimRange, let duration = trimSourceDuration else {
            return false
        }
        return trimRange.lowerBound > 0.01 || trimRange.upperBound < duration - 0.01
    }
    
    public var pendingTrimRange: Range<Double>? {
        return isTrimmed ? trimRange : nil
    }
    
    public func start() {
        
    }
    public func stop() {
        
    }
    public func pause() {}
    public func resume() {}
    public func performTrim(_ range: Range<Double>) -> Signal<Bool, NoError> {
        return .single(false)
    }
    public final func applyTrimAndResume() -> Signal<Bool, NoError> {
        return deferred { [weak self] in
            guard let self, !self.isCancelled, !self.isPreparingSubmission, !self.hasSubmitted, self.trimOperationId == nil else { return .single(false) }
            guard let range = self.pendingTrimRange else {
                self.updateTrimRange(nil)
                self.resume()
                return .single(true)
            }
            let sourceDuration = self.trimSourceDuration
            let operationId = UUID()
            self.trimOperationId = operationId
            let result = self.performTrim(range)
                |> then(.single(false))
                |> take(1)
            return Signal { [weak self] subscriber in
                let cancelled = Atomic(value: false)
                let disposable = result.start(next: { [weak self] success in
                    let apply = { [weak self] in
                        guard let self else {
                            subscriber.putNext(false)
                            subscriber.putCompletion()
                            return
                        }
                        if self.trimOperationId == operationId {
                            self.trimOperationId = nil
                        }
                        let accepted = success && self.pendingTrimRange == range && self.trimSourceDuration == sourceDuration
                        if accepted {
                            self.updateTrimRange(nil)
                        }
                        guard !cancelled.with({ $0 }) else { return }
                        if accepted && !self.isCancelled {
                            self.resume()
                            subscriber.putNext(true)
                        } else {
                            subscriber.putNext(false)
                        }
                        subscriber.putCompletion()
                    }
                    if Queue.mainQueue().isCurrent() {
                        apply()
                    } else {
                        Queue.mainQueue().async(apply)
                    }
                })
                return ActionDisposable { [weak self] in
                    _ = cancelled.swap(true)
                    disposable.dispose()
                    let clear = { [weak self] in
                        if self?.trimOperationId == operationId {
                            self?.trimOperationId = nil
                        }
                    }
                    if Queue.mainQueue().isCurrent() {
                        clear()
                    } else {
                        Queue.mainQueue().async(clear)
                    }
                }
            }
        }
    }
    public func updatePreviewTrim(_ range: Range<Double>, updatedEnd: Bool, applied: Bool) {}
    public func dispose() {
        
    }
    public func closeRecorderModal() {}
    public final func cancel() {
        isCancelled = true
        submissionDisposable.set(nil)
        isPreparingSubmission = false
        stop()
        dispose()
        closeRecorderModal()
    }
    public final func send(from chatInteraction: Any, closingOtherModals: Bool = false) {
        guard !isCancelled, !hasSubmitted, !isPreparingSubmission, trimOperationId == nil else { return }
        isPreparingSubmission = true
        guard !isCancelled else { return }
        guard let range = pendingTrimRange else {
            completeSubmission(from: chatInteraction, closingOtherModals: closingOtherModals)
            return
        }
        let sourceDuration = trimSourceDuration
        let operation = MetaDisposable()
        submissionDisposable.set(operation)
        submissionState.set(.preparing)
        guard !isCancelled else { return }
        weak var destination = chatInteraction as AnyObject
        operation.set((performTrim(range) |> then(.single(false)) |> take(1) |> deliverOnMainQueue).start(next: { [weak self] success in
            guard let self, !self.isCancelled else { return }
            let accepted = success && self.pendingTrimRange == range && self.trimSourceDuration == sourceDuration
            if accepted {
                self.updateTrimRange(nil)
            }
            guard let destination else {
                self.isPreparingSubmission = false
                self.submissionState.set(.failed)
                return
            }
            guard accepted else {
                self.isPreparingSubmission = false
                self.submissionState.set(.failed)
                return
            }
            self.completeSubmission(from: destination, closingOtherModals: closingOtherModals)
        }))
    }

    private func completeSubmission(from chatInteraction: Any, closingOtherModals: Bool) {
        guard !isCancelled, !hasSubmitted else { return }
        hasSubmitted = true
        isPreparingSubmission = false
        stop()
        MediaRecorderHooks.shared.setPendingMedia(chatInteraction, contextBoundData)
        closeRecorderModal()
        if closingOtherModals {
            closeAllModals()
        }
        MediaRecorderHooks.shared.clearRecordingState(chatInteraction)
    }

    public final func discard(from chatInteraction: Any, sendingMedia: Bool = false, closingOtherModals: Bool = false) {
        if sendingMedia {
            send(from: chatInteraction, closingOtherModals: closingOtherModals)
            return
        }
        cancel()
        if closingOtherModals {
            closeAllModals()
        }
        MediaRecorderHooks.shared.clearRecordingState(chatInteraction)
    }
    
    deinit {
        submissionDisposable.dispose()
    }
}

public func ==(lhs:ChatRecordingState, rhs:ChatRecordingState) -> Bool {
    return lhs === rhs
}

public final class ChatRecordingVideoState : ChatRecordingState {
    public let pipeline: VideoRecorderPipeline
    public let previewCommands: Promise<VideoRecorderPreviewCommand> = Promise()
    public let previewState = ValuePromise(VideoRecorderPreviewState(position: 0, isPlaying: false), ignoreRepeated: true)
    public init(context: (any AccountContextProtocol), liveUpload:Bool, autohold: Bool) {
        let id:Int64 = arc4random64()
        let path = temporaryMediaPath("video_message", "mp4")
        self.pipeline = VideoRecorderPipeline(path: path, config: VideoMessageConfig.with(appConfiguration: context.appConfiguration), liveUploading: liveUpload ? PreUploadManager(path, engine: context.engine, id: id) : nil)
        super.init(autohold: autohold)
    }
    
    public override var micLevel: Signal<Float, NoError> {
        return pipeline.powerAndDuration.get() |> map {$0.0}
    }
    
    public override var status: Signal<ChatRecordingStatus, NoError> {
        let pipeline = self.pipeline
        return pipeline.pausedInfo |> mapToSignal { paused -> Signal<ChatRecordingStatus, NoError> in
            if let paused {
                return .single(.paused(duration: paused.duration))
            }
            return pipeline.powerAndDuration.get() |> map { .recording(duration: $0.1) }
        }
    }
    
    public override var canPause: Bool {
        return true
    }
    
    public override var previewData: Signal<ChatRecordingPreviewData?, NoError> {
        return pipeline.pausedInfo
    }
    
    public override var data: Signal<[MediaSenderContainer], NoError> {
        let isOneTime = self.isOneTime
        let trimRange = self.pendingTrimRange
        func container(path: String, duration: Int, id: Int64?) -> MediaSenderContainer {
            return VideoMessageSenderContainer(path: path, duration: duration, size: CGSize(width: 200, height: 200), id: id, isOneTime: isOneTime)
        }
        return pipeline.statePromise.get() |> filter { state in
            switch state {
            case .finishRecording, .failed, .stopped:
                return true
            default:
                return false
            }
        } |> take(1) |> mapToSignal { state -> Signal<[MediaSenderContainer], NoError> in
            guard case let .finishRecording(path, duration, id, _) = state else {
                return .complete()
            }
            guard let trimRange else {
                return .single([container(path: path, duration: duration, id: id)])
            }
            return trimmedVideoFile(path, trimRange: trimRange) |> map { output in
                guard let (trimmedPath, trimmedDuration) = output, let duration = Int(exactly: ceil(trimmedDuration)) else { return [] }
                return [container(path: trimmedPath, duration: duration, id: nil)]
            }
        }
    }
    
    public override func start() {
        pipeline.start()
    }
    public override func stop() {
        pipeline.stop()
    }
    public override func pause() {
        pipeline.pause()
    }
    public override func resume() {
        pipeline.resume()
    }
    public override func performTrim(_ range: Range<Double>) -> Signal<Bool, NoError> {
        return pipeline.applyTrim(range)
    }
    public override func updatePreviewTrim(_ range: Range<Double>, updatedEnd: Bool, applied: Bool) {
        let seekTo = updatedEnd && !applied ? range.upperBound : range.lowerBound
        previewCommands.set(.single(VideoRecorderPreviewCommand(trimRange: applied ? range : nil, seekTo: seekTo, play: applied)))
    }
    public override func dispose() {
        pipeline.dispose()
    }
    public override func closeRecorderModal() {
        closeModal(VideoRecorderModalController.self)
    }
}

public final class ChatRecordingAudioState : ChatRecordingState {
    private let recorder:ManagedAudioRecorder
    private let path: String

    
    public override var micLevel: Signal<Float, NoError> {
        return recorder.micLevel
    }
    
    public override var status: Signal<ChatRecordingStatus, NoError> {
        return recorder.recordingState |> map { state in
            switch state {
            case let .paused(duration):
                return .paused(duration: duration)
            case let .recording(duration, _):
                return .recording(duration: duration)
            }
        }
    }
    
    public override var canPause: Bool {
        return true
    }
    
    public override var previewData: Signal<ChatRecordingPreviewData?, NoError> {
        return recorder.previewData() |> map { value in
            guard let value, value.duration > 0 else {
                return nil
            }
            let waveform = value.displayWaveform ?? value.waveform.map { AudioWaveform(bitstream: $0, bitsPerSample: 5) }
            return ChatRecordingPreviewData(path: value.path, duration: value.duration, waveform: waveform, thumb: nil)
        }
    }
    
    public override var data: Signal<[MediaSenderContainer], NoError> {
        let isOneTime = self.isOneTime
        let recorder = self.recorder
        let path = self.path
        let takeMedia: () -> Signal<[MediaSenderContainer], NoError> = {
            return recorder.takenRecordedData() |> map { value in
                guard let value, value.duration > 0.5 else {
                    removeFile(at: path)
                    return []
                }
                return [VoiceSenderContainer(data: value, id: value.id, isOneTime: isOneTime)]
            }
        }
        guard let trimRange = pendingTrimRange else {
            return takeMedia()
        }
        return performTrim(trimRange) |> then(.single(false)) |> take(1) |> mapToSignal { success in
            guard success else { return .single([]) }
            return takeMedia()
        }
    }
    
    public var recordingState: Signal<AudioRecordingState, NoError> {
        return recorder.recordingState
    }
    
    
    
    public init(context: (any AccountContextProtocol), liveUpload: Bool, autohold: Bool) {
        let id = arc4random64()
        let path = temporaryMediaPath("voice_message", "ogg")
        self.path = path
        let uploadManager:PreUploadManager? = liveUpload ? PreUploadManager(path, engine: context.engine, id: id) : nil
        let dataItem = DataItem(path: path)
        recorder = ManagedAudioRecorder(liveUploading: uploadManager, dataItem: dataItem)
        super.init(autohold: autohold)
    }
    
    
    
    public override func start() {
        recorder.start()
    }
    
    public override func stop() {
        recorder.stop()
    }
    
    public override func pause() {
        recorder.pause()
    }
    
    public override func resume() {
        recorder.resume()
    }
    
    public override func performTrim(_ range: Range<Double>) -> Signal<Bool, NoError> {
        return recorder.applyTrim(range)
    }
    
    public override func dispose() {
        recorder.discard()
    }
    
    
    deinit {
        recorder.stop()
    }
}
