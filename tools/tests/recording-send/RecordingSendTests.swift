import Cocoa
import SwiftSignalKit
import XCTest

let baseline = __BASELINE__
final class Probe<T> {
    var subscribers: [Subscriber<T, NoError>] = []
    var starts = 0, disposals = 0
    var immediate: T?
    var empty = false
    var signal: Signal<T, NoError> { Signal { [weak self] s in
        guard let self else { return EmptyDisposable }
        starts += 1; subscribers.append(s)
        if let immediate { s.putNext(immediate) }
        if empty { s.putCompletion() }
        return ActionDisposable { [weak self] in self?.disposals += 1 }
    } }
    func send(_ value: T) { for s in subscribers { s.putNext(value) } }
    func complete() { for s in subscribers { s.putCompletion() } }
}
final class AnalyticsContext {}
final class Analytics { static let shared = Analytics(); func unresolvedContext() -> AnalyticsContext { AnalyticsContext() } }
final class AnalyticsRecordingRequest {
    enum Failure { case preparation }
    var failures = 0, ends = 0
    func fail(_ value: Failure) { failures += 1 }
    func end() { ends += 1 }
    func observingPreparation<T>(_ signal: Signal<T, NoError>) -> Signal<T, NoError> { signal }
}
final class AnalyticsRecordingJourney {
    enum Spec { enum SubmitVia { case release, keyboard } }
    var requests: [AnalyticsRecordingRequest] = []
    func prepareSubmission(via: Spec.SubmitVia) -> AnalyticsRecordingRequest? { let r = AnalyticsRecordingRequest(); requests.append(r); return r }
    func setOneTime(_ value: Bool) {}
}
struct MediaSenderContainer { var path: String; var duration: Double }
struct AudioData { let duration: Double; var id: Int64 = 1 }
func VoiceSenderContainer(data: AudioData, id: Int64, isOneTime: Bool) -> MediaSenderContainer { MediaSenderContainer(path: "audio", duration: data.duration) }
final class Interaction { var recorder: Recorder? }
final class Hooks {
    var sent = 0, cleared = 0, media: [MediaSenderContainer] = []
    var setPendingRecording: ((Any, Signal<[MediaSenderContainer], NoError>, AnalyticsContext, AnalyticsRecordingRequest?) -> Void)?
    var setPendingMediaWithContext: ((Any, Signal<[MediaSenderContainer], NoError>, AnalyticsContext) -> Void)?
    func setPendingMedia(_ interaction: Any, _ signal: Signal<[MediaSenderContainer], NoError>) { sent += 1; _ = signal.start(next: { self.media += $0 }) }
    func clearRecordingState(_ interaction: Any) { cleared += 1 }
}
enum MediaRecorderHooks { static var shared = Hooks() }
var closedAll = 0
func closeAllModals() { closedAll += 1 }
enum ChatRecordingSubmissionState { case idle, preparing, failed }
final class Recorder {
    var analyticsRecordingJourney: AnalyticsRecordingJourney? = AnalyticsRecordingJourney()
    var analyticsContext: AnalyticsContext? = AnalyticsContext()
    var trimRange: Range<Double>? = 2..<8
    var trimSourceDuration: Double? = 10
    var isCancelled = false, isPreparingSubmission = false, hasSubmitted = false, isOneTime = false
    var trimOperationId: UUID?
    let submissionDisposable = MetaDisposable()
    let submissionState = ValuePromise<ChatRecordingSubmissionState>(.idle)
    let operation = Probe<Bool>()
    var stops = 0, resumes = 0, closes = 0, disposes = 0, trimCalls = 0, reads = 0
    var contextBoundData: Signal<[MediaSenderContainer], NoError> { reads += 1; return .single([MediaSenderContainer(path: "prepared", duration: 6)]) }
    func stop() { stops += 1 }
    func resume() { resumes += 1 }
    func dispose() { disposes += 1 }
    func closeRecorderModal() { closes += 1 }
    func performTrim(_ range: Range<Double>) -> Signal<Bool, NoError> { trimCalls += 1; return operation.signal }
    __CORE__
    deinit { submissionDisposable.dispose() }
}
final class AudioBackend {
    let result = Probe<AudioData?>()
    var takes = 0
    func takenRecordedData() -> Signal<AudioData?, NoError> { takes += 1; return result.signal }
}
final class AudioState {
    let recorder = AudioBackend(), trim = Probe<Bool>()
    var isOneTime = false, path = "original.ogg"
    var pendingTrimRange: Range<Double>? = 2..<8
    func performTrim(_ range: Range<Double>) -> Signal<Bool, NoError> { trim.signal }
    __AUDIO__
}
var removed: [String] = []
func removeFile(at path: String) { removed.append(path) }
let export = Probe<String?>()
func exportTrimmedVideo(path: String, range: Range<Double>) -> Signal<String?, NoError> { export.signal }
struct AssetDuration { let seconds: Double }
final class AVURLAsset {
    static var duration: Double = 5.95
    var duration: AssetDuration { AssetDuration(seconds: Self.duration) }
    init(url: URL) {}
}
__VIDEO__
class Control { var isEnabled = true, userInteractionEnabled = true, isSelected = true }
struct LocalStrings { let unknownError = "error" }
func strings() -> LocalStrings { LocalStrings() }
var alerts = 0
func alert(for parent: Int, info: String) { alerts += 1 }
final class Input {
    let recorder = Recorder(), chatInteraction = Interaction()
    let pauseControl = Control(), scrubber = Control(), singleTimeControl = Control()
    var isResuming = false, isDismissing = false
    var previewGeneration = UUID(), parent: Int? = 1
    let previewDisposable = MetaDisposable()
    var resets = 0, loads = 0, teardowns = 0
    func resetPreviewState() { resets += 1 }
    func loadPreview() { loads += 1 }
    func tearDownPlayback() { teardowns += 1 }
    __UI__
}
final class EmptySender {
    final class Request { enum Reason { case preparation }; var failed = 0; func fail(_ reason: Reason) { failed += 1 } }
    final class Journey { enum Reason { case emptySelection }; var failed = 0; func fail(_ reason: Reason) { failed += 1 } }
    final class Flight { var cancelled = 0; func cancel() { cancelled += 1 } }
    final class Interaction { var voiceSendFlight: Flight? = Flight() }
    let chatInteraction = Interaction()
    var continued = 0
    func send(_ media: [Int], recordingRequest: Request?, journey: Journey?) {
        let callback = { [weak self] in
            __EMPTY__
            self?.continued += 1
        }
        callback()
    }
}
class Case: XCTestCase {
    override func setUp() {
        MediaRecorderHooks.shared = Hooks(); closedAll = 0; removed = []; alerts = 0
        export.subscribers = []; export.starts = 0; export.immediate = nil; export.empty = false
        AVURLAsset.duration = 5.95
    }
    func drain() { let e = expectation(description: "main"); DispatchQueue.main.async { e.fulfill() }; wait(for: [e], timeout: 2) }
    func send(_ r: Recorder, _ i: Interaction) { r.send(from: i, via: .keyboard, closingOtherModals: true) }
}
final class SendTests: Case {
    func testPendingTrimKeepsRecorderAndDoesNotReadOrStop() { let r = Recorder(), i = Interaction(); send(r,i); XCTAssertTrue(r.isPreparingSubmission); XCTAssertEqual(r.stops,0); XCTAssertEqual(r.reads,0); XCTAssertEqual(MediaRecorderHooks.shared.cleared,0); XCTAssertEqual(r.closes,0) }
    func testFailurePreservesSelectionAndAllowsRetry() { let r = Recorder(), i = Interaction(); send(r,i); r.operation.send(false); drain(); XCTAssertEqual(r.trimRange,2..<8); XCTAssertEqual(r.stops,0); XCTAssertFalse(r.isPreparingSubmission); XCTAssertEqual(r.analyticsRecordingJourney?.requests.first?.failures,1); send(r,i); XCTAssertEqual(r.trimCalls,2) }
    func testEmptyCompletionIsFailure() { let r = Recorder(), i = Interaction(); send(r,i); r.operation.complete(); drain(); XCTAssertFalse(r.isPreparingSubmission); XCTAssertEqual(MediaRecorderHooks.shared.sent,0); XCTAssertEqual(r.analyticsRecordingJourney?.requests.first?.failures,1) }
    func testSuccessClearsSelectionThenStopsAndHandsOff() { let r = Recorder(), i = Interaction(); send(r,i); r.operation.send(true); drain(); XCTAssertNil(r.trimRange); XCTAssertEqual(r.stops,1); XCTAssertEqual(MediaRecorderHooks.shared.sent,1); XCTAssertEqual(MediaRecorderHooks.shared.cleared,1); XCTAssertEqual(closedAll,1) }
    func testOnlyFirstTrimResultIsAccepted() { let r = Recorder(), i = Interaction(); send(r,i); r.operation.send(false); r.operation.send(true); drain(); XCTAssertEqual(MediaRecorderHooks.shared.sent,0); XCTAssertEqual(r.trimRange,2..<8) }
    func testDuplicatePendingSendStartsOneTrim() { let r = Recorder(), i = Interaction(); send(r,i); send(r,i); XCTAssertEqual(r.trimCalls,1); XCTAssertEqual(r.analyticsRecordingJourney?.requests.count,1) }
    func testDuplicateFinishedSendDoesNotResubmit() { let r = Recorder(), i = Interaction(); r.trimRange = nil; send(r,i); send(r,i); XCTAssertEqual(MediaRecorderHooks.shared.sent,1) }
    func testUntrimmedSendKeepsImmediateBehavior() { let r = Recorder(), i = Interaction(); r.trimRange = nil; send(r,i); XCTAssertEqual(r.trimCalls,0); XCTAssertEqual(MediaRecorderHooks.shared.sent,1); XCTAssertEqual(r.stops,1) }
    func testCancelledRecorderDoesNotSend() { let r = Recorder(), i = Interaction(); r.cancel(); send(r,i); XCTAssertEqual(MediaRecorderHooks.shared.sent,0); XCTAssertEqual(r.trimCalls,0) }
    func testDiscardCancelsPendingTrim() { let r = Recorder(), i = Interaction(); send(r,i); r.cancel(); r.operation.send(true); drain(); XCTAssertEqual(MediaRecorderHooks.shared.sent,0); XCTAssertEqual(r.operation.disposals,1) }
    func testBackgroundResultDiscardedBeforeMainDoesNotSend() { let r = Recorder(), i = Interaction(); send(r,i); let done = DispatchSemaphore(value:0); DispatchQueue.global().async { r.operation.send(true); done.signal() }; XCTAssertEqual(done.wait(timeout:.now()+2),.success); r.cancel(); drain(); XCTAssertEqual(MediaRecorderHooks.shared.sent,0) }
    func testChangedSelectionRejectsOldSend() { let r = Recorder(), i = Interaction(); send(r,i); r.updateTrimRange(3..<7); r.operation.send(true); drain(); XCTAssertEqual(MediaRecorderHooks.shared.sent,0); XCTAssertEqual(r.trimRange,3..<7) }
    func testChangedSourceRejectsOldSend() { let r = Recorder(), i = Interaction(); send(r,i); r.updateTrimRange(2..<8,duration:12); r.operation.send(true); drain(); XCTAssertEqual(MediaRecorderHooks.shared.sent,0) }
    func testSynchronousFailureCanRetry() { let r = Recorder(), i = Interaction(); r.operation.immediate = false; send(r,i); drain(); send(r,i); drain(); XCTAssertEqual(r.trimCalls,2); XCTAssertEqual(r.operation.disposals,2); XCTAssertEqual(MediaRecorderHooks.shared.sent,0) }
    func testSynchronousSuccessSendsOnce() { let r = Recorder(), i = Interaction(); r.operation.immediate = true; send(r,i); drain(); XCTAssertEqual(r.trimCalls,1); XCTAssertEqual(r.operation.disposals,1); XCTAssertEqual(MediaRecorderHooks.shared.sent,1) }
    func testResumeCannotRacePendingSend() { let r = Recorder(), i = Interaction(); send(r,i); var result:[Bool] = []; let d = r.applyTrimAndResume().start(next:{result.append($0)}); XCTAssertEqual(result,[false]); XCTAssertEqual(r.trimCalls,1); d.dispose() }
    func testKeyboardSendCannotRaceResume() { let r = Recorder(), i = Interaction(); let d = r.applyTrimAndResume().start(); send(r,i); XCTAssertEqual(r.trimCalls,1); XCTAssertEqual(r.stops,0); XCTAssertEqual(MediaRecorderHooks.shared.sent,0); d.dispose() }
    func testDisposedResumeUnlocksSend() { let r = Recorder(), i = Interaction(); let d = r.applyTrimAndResume().start(); d.dispose(); send(r,i); XCTAssertEqual(r.trimCalls,2) }
    func testPendingSendDoesNotRetainInteractionAndRecorderCycle() { var i: Interaction? = Interaction(); var r: Recorder? = Recorder(); i!.recorder = r; weak var weakInteraction = i; weak var weakRecorder = r; send(r!,i!); i = nil; r = nil; XCTAssertNil(weakInteraction); XCTAssertNil(weakRecorder) }
    func testFailureObserverCanRetrySynchronously() { let r=Recorder(), i=Interaction(); var failures=0; let d=r.submissionState.get().start(next:{ if case .failed = $0 { failures += 1; if failures == 1 { self.send(r,i) } } }); send(r,i); r.operation.send(false); drain(); XCTAssertEqual(r.trimCalls,2); XCTAssertTrue(r.isPreparingSubmission); r.operation.send(true); drain(); XCTAssertEqual(MediaRecorderHooks.shared.sent,1); d.dispose() }
    func testReleasedDestinationCannotReceivePreparedMedia() { let r=Recorder(); var i:Interaction?=Interaction(); send(r,i!); i=nil; r.operation.send(true); drain(); XCTAssertEqual(MediaRecorderHooks.shared.sent,0); XCTAssertFalse(r.isPreparingSubmission); XCTAssertNil(r.trimRange) }
    func testRecordingHookReceivesOnlyPreparedMedia() { let r=Recorder(), i=Interaction(); var received=0; MediaRecorderHooks.shared.setPendingRecording={ _, data, _, _ in received += 1; _=data.start() }; send(r,i); XCTAssertEqual(received,0); r.operation.send(true); drain(); XCTAssertEqual(received,1); XCTAssertEqual(MediaRecorderHooks.shared.sent,0) }
    func testContextFallbackReceivesOnlyPreparedMedia() { let r=Recorder(), i=Interaction(); var received=0; MediaRecorderHooks.shared.setPendingMediaWithContext={ _, data, _ in received += 1; _=data.start() }; send(r,i); XCTAssertEqual(received,0); r.operation.send(true); drain(); XCTAssertEqual(received,1); XCTAssertEqual(MediaRecorderHooks.shared.sent,0) }
    func testPreparingObserverCannotSubmitAgain() { let r=Recorder(), i=Interaction(); let d=r.submissionState.get().start(next:{ if case .preparing = $0 { self.send(r,i) } }); send(r,i); XCTAssertEqual(r.trimCalls,1); XCTAssertEqual(r.analyticsRecordingJourney?.requests.count,1); d.dispose() }
    func testPreparingObserverCanCancelBeforeBackendStarts() { let r = Recorder(), i = Interaction(); let d = r.submissionState.get().start(next:{ if case .preparing = $0 { r.cancel() } }); send(r,i); XCTAssertEqual(r.trimCalls,0); XCTAssertEqual(MediaRecorderHooks.shared.sent,0); d.dispose() }
}
final class DataTests: Case {
    func testAudioRejectedTrimDoesNotTakeOriginal() { let a = AudioState(); var values:[[MediaSenderContainer]]=[]; let d=a.data.start(next:{values.append($0)}); a.trim.send(false); XCTAssertEqual(a.recorder.takes,0); XCTAssertEqual(values.count,1); XCTAssertEqual(values.first?.count,0); d.dispose() }
    func testAudioEmptyTrimDoesNotTakeOriginal() { let a = AudioState(); var values:[[MediaSenderContainer]]=[]; let d=a.data.start(next:{values.append($0)}); a.trim.complete(); XCTAssertEqual(a.recorder.takes,0); XCTAssertEqual(values.count,1); d.dispose() }
    func testAudioAcceptedTrimTakesOnce() { let a=AudioState(); let d=a.data.start(); a.trim.send(true); a.trim.send(true); XCTAssertEqual(a.recorder.takes,1); d.dispose() }
    func testAudioUntrimmedTakesNormally() { let a=AudioState(); a.pendingTrimRange=nil; let d=a.data.start(); XCTAssertEqual(a.recorder.takes,1); XCTAssertEqual(a.trim.starts,0); d.dispose() }
    func testVideoFailedExportNeverSubstitutesSource() { var path:String?; let d=trimmedVideoFile("source.mp4",trimRange:2..<8).start(next:{path=$0?.0}); export.send(nil); drain(); XCTAssertNil(path); XCTAssertFalse(removed.contains("source.mp4")); d.dispose() }
    func testVideoSamePathIsNotAcceptedAsTrim() { var path:String?; let d=trimmedVideoFile("source.mp4",trimRange:2..<8).start(next:{path=$0?.0}); export.send("source.mp4"); drain(); XCTAssertNil(path); XCTAssertTrue(removed.isEmpty); d.dispose() }
    func testVideoUsesActualOutputDuration() { var duration:Double?; let d=trimmedVideoFile("source.mp4",trimRange:2..<8).start(next:{duration=$0?.1}); export.send("trimmed.mp4"); drain(); XCTAssertEqual(duration,5.95); XCTAssertEqual(removed,["source.mp4"]); d.dispose() }
    func testInvalidVideoOutputPreservesOriginal() { AVURLAsset.duration = .nan; var path:String?; let d=trimmedVideoFile("source.mp4",trimRange:2..<8).start(next:{path=$0?.0}); export.send("trimmed.mp4"); drain(); XCTAssertNil(path); XCTAssertEqual(removed,["trimmed.mp4"]); d.dispose() }
}
final class InputTests: Case {
    func testSendKeepsPreviewUntilPreparationCompletes() { let i=Input(); i.stopAndSend(); XCTAssertEqual(i.resets,0) }
    func testSendWhilePreparingDoesNotResetPreview() { let i=Input(); i.recorder.isPreparingSubmission=true; i.stopAndSend(); XCTAssertEqual(i.resets,0); XCTAssertEqual(i.recorder.analyticsRecordingJourney?.requests.count,0) }
    func testPreparingStopsPreviewAndLocksControls() { let i=Input(); i.updateSubmissionState(.preparing); XCTAssertEqual(i.teardowns,1); XCTAssertFalse(i.singleTimeControl.isEnabled); XCTAssertFalse(i.pauseControl.isEnabled); XCTAssertFalse(i.scrubber.userInteractionEnabled) }
    func testFailureReloadsPreviewAndShowsError() { let i=Input(); i.updateSubmissionState(.preparing); i.updateSubmissionState(.failed); XCTAssertEqual(i.loads,1); XCTAssertTrue(i.singleTimeControl.isEnabled); XCTAssertEqual(alerts,1); XCTAssertTrue(i.pauseControl.isEnabled); XCTAssertTrue(i.scrubber.userInteractionEnabled) }
    func testDiscardedInputDoesNotShowStaleFailure() { let i=Input(); i.recorder.isCancelled=true; i.updateSubmissionState(.failed); XCTAssertEqual(alerts,0); XCTAssertEqual(i.loads,0) }
    func testResumeCleanupDoesNotUnlockPendingSend() { let i=Input(); i.recorder.isPreparingSubmission=true; i.setResuming(false); XCTAssertFalse(i.pauseControl.isEnabled); XCTAssertFalse(i.scrubber.userInteractionEnabled) }
    func testEmptyMediaDoesNotProceedToSchedulingOrEnqueue() { let s=EmptySender(), r=EmptySender.Request(), j=EmptySender.Journey(); s.send([],recordingRequest:r,journey:j); XCTAssertEqual(s.continued,0); XCTAssertEqual(r.failed,1); XCTAssertEqual(j.failed,1); XCTAssertEqual(s.chatInteraction.voiceSendFlight?.cancelled,1) }
    func testNonEmptyMediaContinues() { let s=EmptySender(); s.send([1],recordingRequest:nil,journey:nil); XCTAssertEqual(s.continued,1) }
}

extension String {
    var path: String { self }
    var duration: Double { AVURLAsset.duration }
    func takePath() -> String? { self }
    func discard() { removeFile(at: self) }
}
