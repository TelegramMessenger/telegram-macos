import Cocoa
import AVFoundation
import XCTest
import MediaRecorderUI

final class RecordingVideoPreviewTests: XCTestCase {
    private var directory: URL!
    private var view: VideoRecorderModalView!
    private var player: AVPlayer!
    private var lastState = VideoRecorderPreviewState(position: 0, isPlaying: false)

    override func setUpWithError() throws {
        try super.setUpWithError()
        UITestBootstrap.install()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("preview.mp4")
        try makeVideo(at: url)
        view = VideoRecorderModalView(frame: NSRect(x: 0, y: 0, width: 300, height: 300), thumbnail: nil)
        view.previewUpdated = { [weak self] in self?.lastState = $0 }
        view.updatePaused(url.path)
        player = try XCTUnwrap(view.previewView.layer?.sublayers?.compactMap { ($0 as? AVPlayerLayer)?.player }.first)
    }

    override func tearDownWithError() throws {
        view?.stopPreview()
        view = nil
        player = nil
        if let directory { try? FileManager.default.removeItem(at: directory) }
        directory = nil
        try super.tearDownWithError()
    }

    func testSeekBeforePlayerIsReadySelectsRequestedFrame() {
        view.updatePreview(trimRange: 2 ..< 7, seekTo: 3, play: false)
        view.updatePreview(trimRange: 2 ..< 7, seekTo: 5, play: false)
        waitUntil("Latest requested video frame is selected") {
            abs(CMTimeGetSeconds(self.player.currentTime()) - 5) < 0.1 && self.player.rate == 0
        }
        XCTAssertEqual(CMTimeGetSeconds(player.currentItem!.forwardPlaybackEndTime), 7, accuracy: 0.05)
    }

    func testFullVideoCanPlayAndPause() {
        view.togglePreviewPlayback()
        waitUntil("Video is playing") { self.lastState.isPlaying && self.player.rate > 0 }
        view.togglePreviewPlayback()
        waitUntil("Video is paused") { !self.lastState.isPlaying && self.player.rate == 0 }
    }

    func testTrimmedFragmentStopsAndCanReplay() {
        view.updatePreview(trimRange: 2 ..< 2.8, seekTo: 2, play: false)
        waitUntil("Trim start is selected") { abs(CMTimeGetSeconds(self.player.currentTime()) - 2) < 0.1 }
        view.togglePreviewPlayback()
        waitUntil("Trimmed fragment is playing") { self.lastState.isPlaying && self.player.rate > 0 }
        waitUntil("Trimmed fragment stops at its boundary") {
            !self.lastState.isPlaying && self.player.rate == 0 && abs(CMTimeGetSeconds(self.player.currentTime()) - 2) < 0.1
        }
        XCTAssertEqual(CMTimeGetSeconds(player.currentItem!.forwardPlaybackEndTime), 2.8, accuracy: 0.05)
        view.togglePreviewPlayback()
        waitUntil("Trimmed fragment can play again") { self.lastState.isPlaying && self.player.rate > 0 }
    }

    func testPauseCancelsPendingPlaybackSeek() {
        view.updatePreview(trimRange: 2 ..< 7, seekTo: 4, play: true)
        view.togglePreviewPlayback()
        let settled = expectation(description: "Pending seeks settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        XCTAssertFalse(lastState.isPlaying)
        XCTAssertEqual(player.rate, 0)
    }

    func testRepeatedResumeDoesNotLeavePreviewLayers() {
        for _ in 0 ..< 5 {
            view.updatePreview(trimRange: 2 ..< 7, seekTo: 4, play: false)
            view.updateResumed()
            view.updatePaused(directory.appendingPathComponent("preview.mp4").path)
        }
        let settled = expectation(description: "Outgoing preview layers cleaned up")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        let layers = view.previewView.layer?.sublayers?.compactMap { $0 as? AVPlayerLayer } ?? []
        XCTAssertEqual(layers.count, 1)
        view.stopPreview()
        XCTAssertFalse(lastState.isPlaying)
        XCTAssertTrue(view.previewView.layer?.sublayers?.compactMap { $0 as? AVPlayerLayer }.isEmpty ?? true)
    }

    private func waitUntil(_ description: String, condition: @escaping () -> Bool) {
        if condition() { return }
        let result = expectation(description: description)
        let timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { timer in
            if condition() {
                timer.invalidate()
                result.fulfill()
            }
        }
        defer { timer.invalidate() }
        wait(for: [result], timeout: 8)
    }

    private func makeVideo(at url: URL) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0 ..< 10 {
            let deadline = Date().addingTimeInterval(5)
            while !input.isReadyForMoreMediaData, Date() < deadline {
                Thread.sleep(forTimeInterval: 0.005)
            }
            XCTAssertTrue(input.isReadyForMoreMediaData)
            var buffer: CVPixelBuffer?
            let pool = try XCTUnwrap(adaptor.pixelBufferPool)
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer), kCVReturnSuccess)
            let pixels = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixels, [])
            memset(CVPixelBufferGetBaseAddress(pixels), 255, CVPixelBufferGetDataSize(pixels))
            CVPixelBufferUnlockBaseAddress(pixels, [])
            XCTAssertTrue(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(index), timescale: 1)))
        }
        writer.endSession(atSourceTime: CMTime(value: 10, timescale: 1))
        input.markAsFinished()
        let completed = expectation(description: "Synthetic video written")
        writer.finishWriting { completed.fulfill() }
        wait(for: [completed], timeout: 8)
        XCTAssertEqual(writer.status, .completed)
    }
}
