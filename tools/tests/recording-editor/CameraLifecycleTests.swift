import Cocoa
import AVFoundation
import XCTest
import TGUIKit
import SwiftSignalKit
import MediaRecorderUI

final class RecordingCapturePipelineProbe {
    static let videoMessageMaxDuration: Double = 60
    let session = AVCaptureSession()
    let statePromise = ValuePromise<VideoCameraRecordingStatus>(.idle, ignoreRepeated: true)
    let powerAndDuration = Promise<(Float, Double)>()
    private(set) var isCapturing = false
    var captureStopped: (() -> Void)?

    func start() {
        isCapturing = true
    }

    func stop() {
        statePromise.set(.stoppingRecording)
    }

    func stopCapture() {
        isCapturing = false
        captureStopped?()
    }
}

final class RecordingCaptureViewProbe: View {
    var previewUpdated: ((VideoRecorderPreviewState) -> Void)?
    var previewView: NSView { self }

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
    func updatePaused(_ path: String) {}
    func updateProgress(_ progress: Float) {}
    func stopPreview() {}
}

final class RecordingCameraLifecycleTests: XCTestCase {
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

    private func makeController() -> (RecordingCameraLifecycleController, RecordingCapturePipelineProbe) {
        UITestBootstrap.install()
        let pipeline = RecordingCapturePipelineProbe()
        let controller = RecordingCameraLifecycleController(state: ChatRecordingState(autohold: false), pipeline: pipeline, sendMedia: { _ in XCTFail("Unexpected submission") }, resetState: {})
        controller.loadViewIfNeeded(NSRect(x: 0, y: 0, width: 300, height: 300))
        XCTAssertTrue(pipeline.isCapturing)
        return (controller, pipeline)
    }
}
