import Cocoa
import AVFoundation
import XCTest
import TGUIKit
import SwiftSignalKit
import TelegramMediaUtils
@testable import MediaRecorderUI

private final class RecordingLimitState: ChatRecordingState {
    override var data: Signal<[MediaSenderContainer], NoError> { .single([]) }
}

final class RecordingCapturePipelineProbe {
    static let videoMessageMaxDuration: Double = 60
    let session = AVCaptureSession()
    let statePromise = ValuePromise<VideoCameraRecordingStatus>(.idle, ignoreRepeated: true)
    let powerAndDuration = Promise<(Float, Double)>()
    private(set) var isCapturing = false
    var captureStopped: (() -> Void)?
    private(set) var pauseCount = 0

    func start() {
        isCapturing = true
    }

    func stop() {
        statePromise.set(.stoppingRecording)
    }

    func pause() {
        pauseCount += 1
        statePromise.set(.paused(info: ChatRecordingPreviewData(path: "/unused-preview.mp4", duration: Self.videoMessageMaxDuration, waveform: nil, thumb: nil)))
    }

    func stopCapture() {
        isCapturing = false
        captureStopped?()
    }
}

final class RecordingCaptureViewProbe: View {
    var previewUpdated: ((VideoRecorderPreviewState) -> Void)?
    var previewView: NSView { self }
    var paused: (() -> Void)?

    init(frame: NSRect, thumbnail: CGImage?) {
        super.init(frame: frame)
    }

    required init(frame: NSRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError()
    }

    func updateWithSession(_ session: AVCaptureSession) {}
    func updatePreview(trimRange: Range<Double>?, seekTo: Double, play: Bool) {}
    func togglePreviewPlayback() {}
    func updateForPreview(_ path: String, preview: CGImage?) {}
    func updateResumed() {}
    func didStartedRecording() {}
    func updatePaused(_ path: String) { paused?() }
    func updateProgress(_ progress: Float) {}
    func stopPreview() {}
}

final class RecordingCameraLifecycleTests: XCTestCase {
    func testDurationLimitOpensEditorWithoutSubmittingOrClearingRecording() {
        UITestBootstrap.install()
        let state = RecordingLimitState(autohold: false)
        var handsFree = false
        let hold = state.holdpromise.get().start(next: { handsFree = $0 })
        defer { hold.dispose() }
        var submissions = 0
        var resets = 0
        let (controller, pipeline) = makeController(state: state, onSubmit: { submissions += 1 }, onReset: { resets += 1 })
        let editor = expectation(description: "Duration limit opens the paused editor")
        (controller.view as? RecordingCaptureViewProbe)?.paused = { editor.fulfill() }
        pipeline.statePromise.set(.recording)
        pipeline.powerAndDuration.set(.single((0, 60)))
        wait(for: [editor], timeout: 1)
        XCTAssertEqual(pipeline.pauseCount, 1)
        XCTAssertEqual(submissions, 0)
        XCTAssertEqual(resets, 0)
        XCTAssertTrue(handsFree)
        withExtendedLifetime(controller) {}
    }

    func testDurationBelowLimitKeepsRecording() {
        let (controller, pipeline) = makeController()
        pipeline.powerAndDuration.set(.single((0, 59.99)))
        pipeline.statePromise.set(.recording)
        settle()
        XCTAssertEqual(pipeline.pauseCount, 0)
        withExtendedLifetime(controller) {}
    }

    func testRepeatedLimitUpdatesPauseOnlyOnce() {
        let (controller, pipeline) = makeController()
        let editor = expectation(description: "Repeated limit updates leave one paused editor")
        (controller.view as? RecordingCaptureViewProbe)?.paused = { editor.fulfill() }
        pipeline.statePromise.set(.recording)
        pipeline.powerAndDuration.set(Signal { subscriber in
            for duration in [60.0, 60.01, 61.0] {
                subscriber.putNext((0, duration))
            }
            subscriber.putCompletion()
            return EmptyDisposable
        })
        wait(for: [editor], timeout: 1)
        XCTAssertEqual(pipeline.pauseCount, 1)
        withExtendedLifetime(controller) {}
    }

    func testDiscardStopsCaptureBeforeRetainedControllerIsReleased() {
        assertCaptureStops(after: .stopped(thumb: nil))
    }

    func testFailureStopsCaptureBeforeRetainedControllerIsReleased() {
        assertCaptureStops(after: .failed)
    }

    func testCompletedRecordingStopsCaptureBeforeRetainedControllerIsReleased() {
        assertCaptureStops(after: .finishRecording(path: "/unused-preview.mp4", duration: 1, id: nil, thumb: nil))
    }

    private func assertCaptureStops(after status: VideoCameraRecordingStatus) {
        let (controller, pipeline) = makeController()
        weak var retainedController = controller
        let stopped = expectation(description: "Capture stops after dismissal while controller is retained")
        pipeline.captureStopped = { stopped.fulfill() }
        controller.viewWillDisappear(false)
        DispatchQueue.main.async { pipeline.statePromise.set(status) }
        wait(for: [stopped], timeout: 1)
        withExtendedLifetime(controller) {
            XCTAssertNotNil(retainedController)
            XCTAssertFalse(pipeline.isCapturing)
        }
    }

    private func settle() {
        let settled = expectation(description: "Queued recording updates settle")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { settled.fulfill() }
        wait(for: [settled], timeout: 1)
    }

    private func makeController(state: ChatRecordingState = RecordingLimitState(autohold: false), onSubmit: @escaping () -> Void = { XCTFail("Unexpected submission") }, onReset: @escaping () -> Void = {}) -> (RecordingCameraLifecycleController, RecordingCapturePipelineProbe) {
        UITestBootstrap.install()
        let pipeline = RecordingCapturePipelineProbe()
        let controller = RecordingCameraLifecycleController(state: state, pipeline: pipeline, sendMedia: { _ in onSubmit() }, resetState: onReset)
        controller.loadViewIfNeeded(NSRect(x: 0, y: 0, width: 300, height: 300))
        XCTAssertTrue(pipeline.isCapturing)
        return (controller, pipeline)
    }
}
