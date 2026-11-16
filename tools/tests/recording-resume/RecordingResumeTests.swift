import Cocoa
import SwiftSignalKit
import XCTest

final class Probe<T> {
    var subscribers: [Subscriber<T, NoError>] = []
    var starts = 0, disposals = 0
    var immediate: T?
    var empty = false
    var signal: Signal<T, NoError> { Signal { [weak self] subscriber in
        guard let self else { return EmptyDisposable }
        self.starts += 1; self.subscribers.append(subscriber)
        if let immediate = self.immediate { subscriber.putNext(immediate) }
        if self.empty { subscriber.putCompletion() }
        return ActionDisposable { [weak self] in self?.disposals += 1 }
    } }
    func send(_ value: T) { for subscriber in subscribers { subscriber.putNext(value) } }
    func complete() { for subscriber in subscribers { subscriber.putCompletion() } }
}
final class Presentation { func end() {} }
final class AnalyticsContext { func beginPresentation() -> Presentation { Presentation() } }
final class Analytics { static let shared = Analytics(); func unresolvedContext() -> AnalyticsContext { AnalyticsContext() } }
enum Step { case openConfirmation, cancelConfirmation }
final class Journey {
    func previewReady() {}
    func trimChanged(changed: Bool, committed: Bool) {}
    func step(_ value: Step) {}
    func cancel() {}
    func setOneTime(_ value: Bool) {}
}
struct ChatRecordingPreviewData { var path: String = "/tmp/source.m4a"; var duration: Double; var waveform: Int? = nil; var thumb: CGImage? = nil }
enum Via { case release }
final class Recorder {
    var trimRange: Range<Double>? = 2..<8
    var trimSourceDuration: Double? = 10
    var isCancelled = false, isOneTime = false, isPreparingSubmission = false, hasSubmitted = false
    var trimOperationId: UUID?
    var resumes = 0, sends = 0, trimCalls: [Range<Double>] = []
    var analyticsContext: AnalyticsContext? = AnalyticsContext()
    var analyticsRecordingJourney: Journey? = Journey()
    let operation = Probe<Bool>(), previews = Probe<ChatRecordingPreviewData?>()
    var previewData: Signal<ChatRecordingPreviewData?, NoError> { previews.signal }
    func performTrim(_ range: Range<Double>) -> Signal<Bool, NoError> { trimCalls.append(range); return operation.signal }
    func resume() { resumes += 1 }
    func updatePreviewTrim(_ range: Range<Double>, updatedEnd: Bool, applied: Bool) {}
    func send(from: Interaction, via: Via, closingOtherModals: Bool) { sends += 1 }
    func discard(from: Interaction, closingOtherModals: Bool) { isCancelled = true }
    __CORE__
    var result: Signal<Bool, NoError> { __RESULT__ }
}
class Window { func removeAllHandlers(for owner: AnyObject) {} }
typealias NSWindow = Window
final class Layer { func removeAllAnimations() {} }
class View {
    var window: Window? = Window()
    var layer: Layer? = Layer()
    var userInteractionEnabled = true, isEnabled = true, isSelected = false
    func viewWillMove(toWindow: NSWindow?) {}
    func viewDidMoveToWindow() {}
}
final class Timer { func update(duration: Double, running: Bool) {} }
final class Scrubber: View { var path: String?; func setVideo(path: String?, placeholder: CGImage?) { self.path = path } }
final class RecordingPreviewPlayer {
    var onUpdate: (() -> Void)?
    init(postbox: Int, preview: ChatRecordingPreviewData, trimRange: Range<Double>) {}
    func updateTrim(_ range: Range<Double>, updatedEnd: Bool, applied: Bool) {}
}
struct Interaction {
    struct Context { struct Account { let postbox = 0 }; let account = Account() }
    final class Transcription { func recordingStopped() {} }
    let interactionContext = Context(), voiceTranscription: Transcription? = nil
}
struct LocalStrings { let unknownError = "error", chatInputRecordingViewResumeDiscardTrimmed = "confirm", chatInputRecordingViewResume = "resume", modalCancel = "cancel" }
func strings() -> LocalStrings { LocalStrings() }
var alerts = 0
var confirmations: [(Int) -> Void] = []
func alert(for window: Window, info: String) { alerts += 1 }
func verifyAlert_button(for window: Window, information: String, ok: String, cancel: String, successHandler: @escaping (Int) -> Void, cancelHandler: @escaping () -> Void, onDeinit: @escaping () -> Void) { confirmations.append(successHandler) }
final class Input: View {
    let recorder: Recorder
    let scrubber = Scrubber(), pauseControl = View(), singleTimeControl = View(), recView = View(), timerView = Timer()
    let chatInteraction = Interaction()
    var parent: Window? = Window()
    var preview: ChatRecordingPreviewData? = ChatRecordingPreviewData(duration: 10)
    var previewPlayer: RecordingPreviewPlayer?
    var previewGeneration = UUID()
    var isPaused = true, isResuming = false, isDismissing = false, isVideoRecorder = false, isTranscribing = false, needsLayout = false
    var trimRange: Range<Double> = 2..<8
    let previewDisposable = MetaDisposable(), resumeDisposable = MetaDisposable()
    init(_ recorder: Recorder = Recorder()) { self.recorder = recorder; super.init() }
    func refreshScrubber() {}
    func updateDescription(_ value: Bool) {}
    func showOverlay(window: Window) {}
    func startBlinking() {}
    func hideOverlay() {}
    __UI__
    deinit { previewDisposable.dispose(); resumeDisposable.dispose() }
}
final class ManualQueue {
    var tasks: [() -> Void] = []
    func async(_ f: @escaping () -> Void) { tasks.append(f) }
    func run() { let tasks = self.tasks; self.tasks = []; for task in tasks { task() } }
}
var removed: [String] = []
var exports: [Probe<String?>] = []
func removeFile(at path: String) { removed.append(path) }
func exportTrimmedVideo(path: String, range: Range<Double>) -> Signal<String?, NoError> { let request = Probe<String?>(); exports.append(request); return request.signal }
enum VideoCameraRecordingStatus { case paused(info: ChatRecordingPreviewData) }
final class VideoRecorderPipeline {
    var status = VideoCameraRecordingStatus.paused(info: ChatRecordingPreviewData(duration: 10))
    var thumbnail: CGImage?
    static let queue = ManualQueue()
    var isPaused = true, isDiscarded = false
    var composed: [((String, Double)?) -> Void] = []
    var derivedFiles: [String] = [], segments: [URL] = []
    var completedDuration: Double = 10, lastSegmentDuration: Double = 0
    var liveUploading: Int? = 1
    var removals = 0
    func composedRecording(_ callback: @escaping ((String, Double)?) -> Void) { composed.append(callback) }
    func removeSegmentFiles() { removals += 1 }
    __PIPELINE__
    func finishComposition() { for callback in composed { callback(("/tmp/original.mp4", 10)) }; composed = [] }
}
class Case: XCTestCase {
    override func setUp() { alerts = 0; confirmations = []; removed = []; exports = []; VideoRecorderPipeline.queue.tasks = [] }
    func drain(_ assertions: @escaping () -> Void) { let done = expectation(description: "main queue"); DispatchQueue.main.async { assertions(); done.fulfill() }; wait(for: [done], timeout: 2) }
}
final class CoreTests: Case {
    func testConstructingTrimOperationDoesNotClearSelection() { let r = Recorder(); _ = r.result; XCTAssertEqual(r.trimRange, 2..<8); XCTAssertTrue(r.trimCalls.isEmpty) }
    func testConstructingUntrimmedOperationDoesNotResume() { let r = Recorder(); r.trimRange = nil; _ = r.result; XCTAssertEqual(r.resumes, 0) }
    func testPendingTrimPreservesSelection() { let r = Recorder(); let d = r.result.start(); XCTAssertEqual(r.trimRange, 2..<8); XCTAssertEqual(r.resumes, 0); d.dispose() }
    func testAcceptedTrimClearsAndResumesOnce() { let r = Recorder(); var results: [Bool] = []; let d = r.result.start(next: { results.append($0) }); r.operation.send(true); r.operation.send(true); XCTAssertEqual(r.resumes, 1); XCTAssertNil(r.trimRange); XCTAssertEqual(results, [true]); d.dispose() }
    func testRejectedTrimPreservesSelectionAndPause() { let r = Recorder(); var results: [Bool] = []; let d = r.result.start(next: { results.append($0) }); r.operation.send(false); XCTAssertEqual(r.resumes, 0); XCTAssertEqual(r.trimRange, 2..<8); XCTAssertEqual(results, [false]); d.dispose() }
    func testEmptyCompletionIsFailure() { let r = Recorder(); var results: [Bool] = []; let d = r.result.start(next: { results.append($0) }); r.operation.complete(); XCTAssertEqual(results, [false]); XCTAssertEqual(r.trimRange, 2..<8); XCTAssertEqual(r.resumes, 0); d.dispose() }
    func testCancelledRecorderCannotStartTrim() { let r = Recorder(); r.isCancelled = true; var results: [Bool] = []; let d = r.result.start(next: { results.append($0) }); XCTAssertEqual(results, [false]); XCTAssertTrue(r.trimCalls.isEmpty); XCTAssertEqual(r.resumes, 0); d.dispose() }
    func testDiscardBeforeAcceptanceCannotResume() { let r = Recorder(); let d = r.result.start(); r.isCancelled = true; r.operation.send(true); XCTAssertEqual(r.resumes, 0); d.dispose() }
    func testChangedSelectionCannotBeClearedByOldTrim() { let r = Recorder(); let d = r.result.start(); r.updateTrimRange(3..<7); r.operation.send(true); XCTAssertEqual(r.trimRange, 3..<7); XCTAssertEqual(r.resumes, 0); d.dispose() }
    func testChangedDurationCannotResumeOldSource() { let r = Recorder(); let d = r.result.start(); r.updateTrimRange(2..<8, duration: 12); r.operation.send(true); XCTAssertEqual(r.trimRange, 2..<8); XCTAssertEqual(r.resumes, 0); d.dispose() }
    func testNoTrimResumesWithSuccess() { let r = Recorder(); r.trimRange = nil; var results: [Bool] = []; let d = r.result.start(next: { results.append($0) }); XCTAssertEqual(results, [true]); XCTAssertEqual(r.resumes, 1); d.dispose() }
    func testDisposedOperationCannotResume() { let r = Recorder(); let d = r.result.start(); d.dispose(); r.operation.send(true); XCTAssertEqual(r.resumes, 0); XCTAssertEqual(r.trimRange, 2..<8); XCTAssertEqual(r.operation.disposals, 1) }
    func testBackgroundAcceptedThenDisposedBeforeMainCannotResume() { let r = Recorder(); let d = r.result.start(); let sent = DispatchSemaphore(value: 0); DispatchQueue.global().async { r.operation.send(true); sent.signal() }; XCTAssertEqual(sent.wait(timeout: .now()+2), .success); d.dispose(); drain { XCTAssertEqual(r.resumes, 0); XCTAssertNil(r.trimRange) } }
    func testOperationDoesNotRetainRecorderWaitingForResult() { var r: Recorder? = Recorder(); let probe = r!.operation; weak var weakRecorder = r; let d = r!.result.start(); r = nil; XCTAssertNil(weakRecorder); probe.send(true); d.dispose() }
}
final class InputTests: Case {
    func testPendingResumeKeepsPreviewForFailureRecovery() { let s = Input(); s.resumeAfterConfirm(); XCTAssertNotNil(s.preview); XCTAssertTrue(s.isResuming); XCTAssertFalse(s.pauseControl.isEnabled); XCTAssertFalse(s.scrubber.userInteractionEnabled) }
    func testRepeatedResumeStartsOneOperation() { let s = Input(); s.resumeAfterConfirm(); s.resumeAfterConfirm(); XCTAssertEqual(s.recorder.trimCalls.count, 1); XCTAssertEqual(s.recorder.operation.starts, 1) }
    func testFailureRestoresPreviewAndShowsError() { let s = Input(); s.resumeAfterConfirm(); s.recorder.operation.send(false); XCTAssertNotNil(s.preview); XCTAssertNotNil(s.previewPlayer); XCTAssertEqual(s.recorder.trimRange, 2..<8); XCTAssertEqual(s.recorder.resumes, 0); XCTAssertFalse(s.isResuming); XCTAssertTrue(s.pauseControl.isEnabled); XCTAssertTrue(s.scrubber.userInteractionEnabled); XCTAssertEqual(alerts, 1) }
    func testFailureCanRetry() { let s = Input(); s.resumeAfterConfirm(); s.recorder.operation.send(false); s.resumeAfterConfirm(); XCTAssertEqual(s.recorder.trimCalls.count, 2); s.recorder.operation.send(true); XCTAssertEqual(s.recorder.resumes, 1); XCTAssertNil(s.preview) }
    func testSynchronousFailureDoesNotLoseRestoredPreview() { let s = Input(); s.recorder.operation.immediate = false; s.resumeAfterConfirm(); XCTAssertNotNil(s.preview); XCTAssertFalse(s.isResuming); XCTAssertEqual(alerts, 1); XCTAssertEqual(s.recorder.operation.disposals, 1) }
    func testSynchronousSuccessClearsPreviewAndReleasesRequest() { let s = Input(); s.recorder.operation.immediate = true; s.resumeAfterConfirm(); XCTAssertNil(s.preview); XCTAssertFalse(s.isResuming); XCTAssertEqual(s.recorder.resumes, 1); XCTAssertEqual(s.recorder.operation.disposals, 1) }
    func testSendWhileTrimmingDoesNotSendUntrimmedData() { let s = Input(); s.resumeAfterConfirm(); s.stopAndSend(); XCTAssertEqual(s.recorder.sends, 0); XCTAssertTrue(s.isResuming) }
    func testSelectionCannotChangeWhileTrimPending() { let s = Input(); s.resumeAfterConfirm(); s.updateTrim(3..<7, updatedEnd: true, applied: false); XCTAssertEqual(s.recorder.trimRange, 2..<8); XCTAssertEqual(s.trimRange, 2..<8) }
    func testDiscardCancelsPendingResume() { let s = Input(); s.resumeAfterConfirm(); s.discardRecording(); s.recorder.operation.send(true); XCTAssertEqual(s.recorder.resumes, 0); XCTAssertNil(s.preview); XCTAssertEqual(alerts, 0); XCTAssertEqual(s.recorder.operation.disposals, 1) }
    func testDetachCancelsPendingResumeAndPlayback() { let s = Input(); s.resumeAfterConfirm(); s.viewWillMove(toWindow: nil); s.window = nil; s.recorder.operation.send(true); XCTAssertNil(s.preview); XCTAssertEqual(s.recorder.resumes, 0); XCTAssertFalse(s.isResuming) }
    func testReattachReloadsPausedPreview() { let s = Input(); s.viewWillMove(toWindow: nil); s.window = Window(); s.viewDidMoveToWindow(); XCTAssertEqual(s.recorder.previews.starts, 1); s.recorder.previews.send(ChatRecordingPreviewData(duration: 10)); XCTAssertNotNil(s.preview) }
    func testStaleConfirmationAfterResetCannotResumeNewPreview() { let s = Input(); s.resumeRecording(); XCTAssertEqual(confirmations.count, 1); s.resetPreviewState(); s.applyPreview(ChatRecordingPreviewData(duration: 10)); confirmations[0](0); XCTAssertTrue(s.recorder.trimCalls.isEmpty) }
    func testChangedTrimRejectsPriorConfirmation() { let s = Input(); s.resumeRecording(); s.recorder.updateTrimRange(3..<7); confirmations[0](0); XCTAssertTrue(s.recorder.trimCalls.isEmpty) }
    func testCurrentConfirmationCanResume() { let s = Input(); s.resumeRecording(); confirmations[0](0); XCTAssertEqual(s.recorder.trimCalls, [2..<8]) }
    func testResumedRecordingCannotApplyLatePreview() { let s = Input(); s.preview = nil; s.isPaused = false; s.applyPreview(ChatRecordingPreviewData(duration: 10)); XCTAssertNil(s.preview) }
    func testDismissingRecordingCannotApplyPreview() { let s = Input(); s.preview = nil; s.isDismissing = true; s.applyPreview(ChatRecordingPreviewData(duration: 10)); XCTAssertNil(s.preview) }
    func testPendingResumeCannotApplyAnotherPreview() { let s = Input(); s.resumeAfterConfirm(); s.applyPreview(ChatRecordingPreviewData(duration: 20)); XCTAssertEqual(s.preview?.duration, 10) }
    func testDetachedViewDoesNotStartPreviewLoad() { let s = Input(); s.window = nil; s.loadPreview(); XCTAssertEqual(s.recorder.previews.starts, 0) }
    func testPendingPreviewLoadCancelledOnReset() { let s = Input(); s.preview = nil; s.loadPreview(); s.resetPreviewState(); s.recorder.previews.send(ChatRecordingPreviewData(duration: 20)); XCTAssertNil(s.preview); XCTAssertEqual(s.recorder.previews.disposals, 1) }
    func testResumeRequestDoesNotRetainView() { var s: Input? = Input(); let recorder = s!.recorder; weak var weakView = s; s!.resumeAfterConfirm(); s = nil; XCTAssertNil(weakView); XCTAssertEqual(recorder.operation.disposals, 1); recorder.operation.send(true); XCTAssertEqual(recorder.resumes, 0) }
}
final class PipelineTests: Case {
    func testCompositionFailureRejectsTrimWithoutExport() { let p=VideoRecorderPipeline(); var results:[Bool]=[]; let d=p.applyTrim(2..<8).start(next:{results.append($0)}); VideoRecorderPipeline.queue.run(); let callbacks=p.composed; p.composed=[]; for callback in callbacks {callback(nil)}; XCTAssertEqual(results,[false]); XCTAssertTrue(exports.isEmpty); XCTAssertEqual(p.removals,0); d.dispose() }
    func testPendingCompositionDoesNotRetainPipelineAfterCallerRelease() { var p:VideoRecorderPipeline?=VideoRecorderPipeline(); weak var weakPipeline=p; let d=p!.applyTrim(2..<8).start(); VideoRecorderPipeline.queue.run(); p=nil; XCTAssertNil(weakPipeline); d.dispose() }

    func testCancelledBeforeQueueDoesNotStartComposition() { let p = VideoRecorderPipeline(); let d = p.applyTrim(2..<8).start(); d.dispose(); VideoRecorderPipeline.queue.run(); XCTAssertTrue(p.composed.isEmpty); XCTAssertTrue(exports.isEmpty) }
    func testDiscardedPipelineCannotStartComposition() { let p = VideoRecorderPipeline(); p.isDiscarded = true; let d = p.applyTrim(2..<8).start(); VideoRecorderPipeline.queue.run(); XCTAssertTrue(p.composed.isEmpty); d.dispose() }
    func testCancelledDuringCompositionDoesNotExport() { let p = VideoRecorderPipeline(); let d = p.applyTrim(2..<8).start(); VideoRecorderPipeline.queue.run(); d.dispose(); p.finishComposition(); XCTAssertTrue(exports.isEmpty) }
    func testDiscardDuringCompositionDoesNotExport() { let p = VideoRecorderPipeline(); let d = p.applyTrim(2..<8).start(); VideoRecorderPipeline.queue.run(); p.isDiscarded = true; p.finishComposition(); XCTAssertTrue(exports.isEmpty); d.dispose() }
    func testCancelledQueuedExportDoesNotReplaceSegments() { let p = VideoRecorderPipeline(); let d = p.applyTrim(2..<8).start(); VideoRecorderPipeline.queue.run(); p.finishComposition(); exports[0].send("/tmp/trimmed.mp4"); d.dispose(); VideoRecorderPipeline.queue.run(); XCTAssertEqual(p.removals, 0); XCTAssertTrue(p.derivedFiles.isEmpty); XCTAssertEqual(removed, ["/tmp/trimmed.mp4"]) }
    func testDiscardQueuedExportDoesNotReplaceSegments() { let p = VideoRecorderPipeline(); let d = p.applyTrim(2..<8).start(); VideoRecorderPipeline.queue.run(); p.finishComposition(); exports[0].send("/tmp/trimmed.mp4"); p.isDiscarded = true; VideoRecorderPipeline.queue.run(); XCTAssertEqual(p.removals, 0); XCTAssertEqual(removed, ["/tmp/trimmed.mp4"]); d.dispose() }
    func testResumedPipelineRejectsOldTrimResult() { let p = VideoRecorderPipeline(); let d = p.applyTrim(2..<8).start(); VideoRecorderPipeline.queue.run(); p.finishComposition(); exports[0].send("/tmp/trimmed.mp4"); p.isPaused = false; VideoRecorderPipeline.queue.run(); XCTAssertEqual(p.removals, 0); XCTAssertEqual(removed, ["/tmp/trimmed.mp4"]); d.dispose() }
    func testAcceptedTrimReplacesSegmentsAndReportsSuccess() { let p = VideoRecorderPipeline(); var results: [Bool] = []; let d = p.applyTrim(2..<8).start(next: { results.append($0) }); VideoRecorderPipeline.queue.run(); p.finishComposition(); exports[0].send("/tmp/trimmed.mp4"); VideoRecorderPipeline.queue.run(); XCTAssertEqual(results, [true]); XCTAssertEqual(p.completedDuration, 6); XCTAssertEqual(p.derivedFiles, ["/tmp/trimmed.mp4"]); XCTAssertEqual(p.removals, 1); XCTAssertNil(p.liveUploading); d.dispose() }
    func testAcceptedTrimPublishesNewPausedPreview() { let p = VideoRecorderPipeline(); let d = p.applyTrim(2..<8).start(); VideoRecorderPipeline.queue.run(); p.finishComposition(); exports[0].send("/tmp/trimmed.mp4"); VideoRecorderPipeline.queue.run(); if case let .paused(info) = p.status { XCTAssertEqual(info.path, "/tmp/trimmed.mp4"); XCTAssertEqual(info.duration, 6) }; d.dispose() }
    func testRejectedExportPreservesSegmentsAndDuration() { let p = VideoRecorderPipeline(); var results: [Bool] = []; let d = p.applyTrim(2..<8).start(next: { results.append($0) }); VideoRecorderPipeline.queue.run(); p.finishComposition(); exports[0].send(nil); VideoRecorderPipeline.queue.run(); XCTAssertEqual(results, [false]); XCTAssertEqual(p.completedDuration, 10); XCTAssertEqual(p.removals, 0); d.dispose() }
}

extension String {
    var duration: Double { 6 }
    func takePath() -> String? { self }
    func discard() { removeFile(at: self) }
}
