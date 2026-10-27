import Cocoa
import AVFoundation
import XCTest
import SwiftSignalKit
import TGVideoCameraMovie
@testable import MediaRecorderUI

private final class ControlledMovieRecorder: TGVideoCameraMovieRecorder {
    var recordedDuration: Double = 0
    private(set) var finishRequests = 0
    var complete: (() -> Void)?
    var fail: (() -> Void)?

    override func addAudioTrack(withSourceFormatDescription formatDescription: CMFormatDescription!, settings audioSettings: [AnyHashable: Any]!) {}
    override func addVideoTrack(withSourceFormatDescription formatDescription: CMFormatDescription!, transform: CGAffineTransform, settings videoSettings: [AnyHashable: Any]!) {}
    override func prepareToRecord() {}
    override func videoDuration() -> TimeInterval { recordedDuration }
    override func finishRecording() { finishRequests += 1 }
}

private final class RecordingWriterFactory {
    private(set) var writers: [ControlledMovieRecorder] = []
    private(set) var urls: [URL] = []
    private(set) var queue: DispatchQueue!

    func make(_ url: URL, delegate: TGVideoCameraMovieRecorderDelegate, queue: DispatchQueue) -> TGVideoCameraMovieRecorder {
        self.queue = queue
        let writer = ControlledMovieRecorder(url: url, delegate: delegate, callbackQueue: queue)!
        writer.complete = { [weak delegate, weak writer] in
            guard let delegate, let writer else { return }
            queue.async { delegate.movieRecorderDidFinishRecording(writer) }
        }
        writer.fail = { [weak delegate, weak writer] in
            guard let delegate, let writer else { return }
            queue.async { delegate.movieRecorder(writer, didFailWithError: NSError(domain: "RecordingPipelineTests", code: 1)) }
        }
        writers.append(writer)
        urls.append(url)
        return writer
    }

    func drain() {
        queue.sync {}
        queue.sync {}
    }
}

final class RecordingPipelineTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        try super.tearDownWithError()
    }

    func testSendWaitsForPausedSegmentToFinish() throws {
        let (pipeline, factory) = try makeRecording(duration: 60)
        let states = Atomic<[VideoCameraRecordingStatus]>(value: [])
        let finished = expectation(description: "Send finishes the complete paused segment")
        let status = pipeline.statePromise.get().start(next: { value in
            _ = states.modify { $0 + [value] }
            if case .finishRecording = value { finished.fulfill() }
        })
        defer { status.dispose() }

        pipeline.pause()
        factory.drain()
        XCTAssertEqual(factory.writers[0].finishRequests, 1)
        pipeline.stop()
        factory.drain()
        XCTAssertFalse(states.with { values in values.contains { if case .stopped = $0 { return true }; return false } })

        factory.writers[0].complete?()
        wait(for: [finished], timeout: 3)
        let durations = states.with { values in values.compactMap { value -> Int? in
            if case let .finishRecording(_, duration, _, _) = value { return duration }
            return nil
        } }
        XCTAssertEqual(durations, [60])
        withExtendedLifetime(pipeline) {}
    }

    func testResumeAfterTrimPublishesRetainedDurationBeforeRecording() throws {
        let (pipeline, factory) = try makeRecording(duration: 60)
        _ = try finishPause(pipeline, factory: factory)
        let trimmed = expectation(description: "The recorded file is trimmed")
        var trimSucceeded = false
        let trim = pipeline.applyTrim(0 ..< 10).start(next: { success in
            trimSucceeded = success
            trimmed.fulfill()
        })
        wait(for: [trimmed], timeout: 8)
        trim.dispose()
        XCTAssertTrue(trimSucceeded)

        let duration = Atomic<Double>(value: -1)
        let power = pipeline.powerAndDuration.get().start(next: { value in _ = duration.swap(value.1) })
        defer { power.dispose() }
        XCTAssertEqual(duration.with { $0 }, 60)
        let resumedDuration = Atomic<Double>(value: -1)
        let resumed = expectation(description: "The real pipeline resumes with retained duration")
        let status = pipeline.statePromise.get().start(next: { value in
            if case .recording = value {
                _ = resumedDuration.swap(duration.with { $0 })
                resumed.fulfill()
            }
        })
        defer { status.dispose() }
        pipeline.resume()
        wait(for: [resumed], timeout: 3)
        factory.drain()
        XCTAssertEqual(factory.writers.count, 2)
        XCTAssertEqual(resumedDuration.with { $0 }, 10, accuracy: 0.05)
        withExtendedLifetime(pipeline) {}
    }

    func testNormalSendStillFinishesRecording() throws {
        let (pipeline, factory) = try makeRecording(duration: 3)
        let result = try finishRecording(pipeline) {
            pipeline.stop()
            factory.drain()
            XCTAssertEqual(factory.writers[0].finishRequests, 1)
            factory.writers[0].complete?()
        }
        XCTAssertEqual(result.duration, 3)
    }

    func testRepeatedSendWaitsWithoutFinishingWriterAgain() throws {
        let (pipeline, factory) = try makeRecording(duration: 60)
        let result = try finishRecording(pipeline) {
            pipeline.pause()
            factory.drain()
            for _ in 0 ..< 5 { pipeline.stop() }
            factory.drain()
            XCTAssertEqual(factory.writers[0].finishRequests, 1)
            factory.writers[0].complete?()
        }
        XCTAssertEqual(result.duration, 60)
        pipeline.stop()
        factory.drain()
        XCTAssertEqual(factory.writers[0].finishRequests, 1)
    }

    func testSendWaitsForTheSecondSegmentAndIncludesBothSegments() throws {
        let (pipeline, factory) = try makeRecording(duration: 2)
        _ = try finishPause(pipeline, factory: factory)
        pipeline.resume()
        factory.drain()
        XCTAssertEqual(factory.writers.count, 2)
        try makeVideo(at: factory.urls[1], duration: 3)
        factory.queue.sync {
            factory.writers[1].recordedDuration = 3
            pipeline.updatePowerAndDuration(0)
        }
        let result = try finishRecording(pipeline) {
            pipeline.pause()
            factory.drain()
            pipeline.stop()
            factory.drain()
            factory.writers[1].complete?()
        }
        XCTAssertEqual(result.duration, 5)
        XCTAssertEqual(CMTimeGetSeconds(AVURLAsset(url: URL(fileURLWithPath: result.path)).duration), 5, accuracy: 0.05)
    }

    func testDiscardDuringFinalizationIgnoresTheLateWriterCompletion() throws {
        let (pipeline, factory) = try makeRecording(duration: 60)
        let states = Atomic<[VideoCameraRecordingStatus]>(value: [])
        let status = pipeline.statePromise.get().start(next: { value in _ = states.modify { $0 + [value] } })
        defer { status.dispose() }
        pipeline.pause()
        factory.drain()
        pipeline.dispose()
        factory.drain()
        factory.writers[0].complete?()
        factory.drain()
        XCTAssertTrue(states.with { values in if case .stopped = values.last { return true }; return false })
        XCTAssertFalse(states.with { values in values.contains { if case .finishRecording = $0 { return true }; return false } })
    }

    func testResumeCannotReplaceAWriterThatIsStillFinishing() throws {
        let (pipeline, factory) = try makeRecording(duration: 60)
        pipeline.pause()
        factory.drain()
        pipeline.resume()
        factory.drain()
        XCTAssertEqual(factory.writers.count, 1)
        XCTAssertEqual(factory.writers[0].finishRequests, 1)
    }

    func testWriterFailureRemainsTerminalWhenCompletionArrivesLate() throws {
        let (pipeline, factory) = try makeRecording(duration: 60)
        let states = Atomic<[VideoCameraRecordingStatus]>(value: [])
        let status = pipeline.statePromise.get().start(next: { value in _ = states.modify { $0 + [value] } })
        defer { status.dispose() }
        pipeline.pause()
        factory.drain()
        factory.writers[0].fail?()
        factory.drain()
        factory.writers[0].complete?()
        factory.drain()
        XCTAssertTrue(states.with { values in if case .failed = values.last { return true }; return false })
        XCTAssertFalse(states.with { values in values.contains { if case .finishRecording = $0 { return true }; return false } })
    }

    private func finishRecording(_ pipeline: VideoRecorderPipeline, perform: () throws -> Void) throws -> (path: String, duration: Int) {
        let finished = expectation(description: "The real pipeline completes one video")
        finished.assertForOverFulfill = true
        let result = Atomic<(String, Int)?>(value: nil)
        let status = pipeline.statePromise.get().start(next: { value in
            if case let .finishRecording(path, duration, _, _) = value {
                _ = result.swap((path, duration))
                finished.fulfill()
            }
        })
        defer { status.dispose() }
        try perform()
        wait(for: [finished], timeout: 8)
        let value = try XCTUnwrap(result.with { $0 })
        addTeardownBlock { try? FileManager.default.removeItem(atPath: value.0) }
        return (value.0, value.1)
    }

    private func finishPause(_ pipeline: VideoRecorderPipeline, factory: RecordingWriterFactory) throws -> ChatRecordingPreviewData {
        let paused = expectation(description: "The real pipeline finishes pausing")
        let preview = Atomic<ChatRecordingPreviewData?>(value: nil)
        let status = (pipeline.pausedInfo |> filter { $0 != nil } |> take(1)).start(next: { value in
            _ = preview.swap(value)
            paused.fulfill()
        })
        defer { status.dispose() }
        pipeline.pause()
        factory.drain()
        factory.writers.last?.complete?()
        wait(for: [paused], timeout: 3)
        return try XCTUnwrap(preview.with { $0 })
    }

    private func makeRecording(duration: Double) throws -> (VideoRecorderPipeline, RecordingWriterFactory) {
        let url = directory.appendingPathComponent(UUID().uuidString + ".mp4")
        try makeVideo(at: url, duration: duration)
        let factory = RecordingWriterFactory()
        let pipeline = VideoRecorderPipeline(path: url.path, config: .defaultValue, liveUploading: nil, initializeCapture: false, makeRecorder: factory.make)
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)).formatDescription
        factory.queue.sync {
            pipeline.startRecording(audioFormat: format)
            factory.writers[0].recordedDuration = duration
            pipeline.updatePowerAndDuration(0)
        }
        return (pipeline, factory)
    }

    private func makeVideo(at url: URL, duration: Double) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0 ..< 2 {
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData && Date() < deadline { Thread.sleep(forTimeInterval: 0.001) }
            XCTAssertTrue(input.isReadyForMoreMediaData)
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 64, 64, kCVPixelFormatType_32ARGB, nil, &buffer), kCVReturnSuccess)
            let pixel = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixel, [])
            memset(CVPixelBufferGetBaseAddress(pixel), 0, CVPixelBufferGetDataSize(pixel))
            CVPixelBufferUnlockBaseAddress(pixel, [])
            XCTAssertTrue(adaptor.append(pixel, withPresentationTime: CMTimeMakeWithSeconds(Double(index) * duration / 2, preferredTimescale: 1000)))
        }
        writer.endSession(atSourceTime: CMTimeMakeWithSeconds(duration, preferredTimescale: 1000))
        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        XCTAssertEqual(done.wait(timeout: .now() + 5), .success)
        XCTAssertEqual(writer.status, .completed)
    }
}
