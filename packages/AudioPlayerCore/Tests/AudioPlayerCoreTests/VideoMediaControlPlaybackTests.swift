import AppKit
import AVFoundation
import MediaPlayer
import Postbox
import SwiftSignalKit
@testable import TelegramMedia
import TelegramMediaPlayer
import XCTest
@testable import AudioPlayerCore

final class VideoMediaControlPlaybackTests: XCTestCase {
    private static let initializeTempBox: Void = {
        TempBox.initializeShared(basePath: NSTemporaryDirectory() + "VideoMediaControlTests-" + UUID().uuidString, processType: "tests", launchSpecificId: Int64.random(in: 0 ... Int64.max))
    }()

    private func waitUntil(timeout: Double = 5, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    private func makeVideo() throws -> TempBoxFile {
        _ = Self.initializeTempBox
        let file = TempBox.shared.tempFile(fileName: UUID().uuidString + ".mp4")
        let writer = try AVAssetWriter(outputURL: URL(fileURLWithPath: file.path), fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: 96,
            AVVideoHeightKey: 64
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 96,
            kCVPixelBufferHeightKey as String: 64
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let pool = try XCTUnwrap(adaptor.pixelBufferPool)
        for index in 0 ..< 120 {
            guard waitUntil({ input.isReadyForMoreMediaData || writer.status == .failed }) else {
                throw NSError(domain: "VideoMediaControlTests", code: 1)
            }
            if let error = writer.error { throw error }
            var buffer: CVPixelBuffer?
            XCTAssertEqual(CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer), kCVReturnSuccess)
            let pixelBuffer = try XCTUnwrap(buffer)
            CVPixelBufferLockBaseAddress(pixelBuffer, [])
            let bytes = CVPixelBufferGetBaseAddress(pixelBuffer)!.assumingMemoryBound(to: UInt8.self)
            let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
            for y in 0 ..< 64 {
                for x in 0 ..< 96 {
                    let offset = y * stride + x * 4
                    bytes[offset] = UInt8((x + index * 3) % 256)
                    bytes[offset + 1] = UInt8((y + index * 5) % 256)
                    bytes[offset + 2] = UInt8(index * 2 % 256)
                    bytes[offset + 3] = 255
                }
            }
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            XCTAssertTrue(adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(index), timescale: 15)))
        }
        input.markAsFinished()
        let finished = expectation(description: "write video")
        writer.finishWriting { finished.fulfill() }
        wait(for: [finished], timeout: 10)
        if let error = writer.error { throw error }
        XCTAssertEqual(writer.status, .completed)
        return file
    }

    func testMediaCommandsPauseAndResumeRealVideoPlayback() throws {
        XCTAssertTrue(Thread.isMainThread)
        _ = NSApplication.shared
        let file = try makeVideo()
        defer { TempBox.shared.dispose(file) }
        let part = ChunkMediaPlayerPart(startTime: 0, endTime: 8, content: .init(file: file), codecName: "h264", offsetTime: 0)
        let view = MediaPlayerView()
        view.frame = CGRect(x: 0, y: 0, width: 96, height: 64)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        defer { window.close() }
        let player = ChunkMediaPlayerV2(params: .init(useV2Reader: true), source: .externalParts(.single(.init(duration: 8, content: .parts([part])))), video: true, enableSound: false, playerNode: view)
        let owner = MediaPlaybackControlCenter()
        owner.play = { player.play(); return true }
        owner.pause = { player.pause(); return true }
        owner.togglePlayPause = { player.togglePlayPause(faded: false); return true }
        owner.activate()
        owner.updateControlsAvaiability(nextEnabled: false, prevEnabled: false, seekEnabled: false)
        var latest: MediaPlayerStatus?
        let disposable = (player.status |> deliverOnMainQueue).start(next: { status in
            latest = status
            owner.setupNowPlaying(videoTitle: "Generated video", status: status)
        })
        defer {
            disposable.dispose()
            player.pause()
            owner.clearNowPlaying()
        }
        player.play()
        XCTAssertTrue(waitUntil { latest?.status == .playing && (latest?.timestamp ?? 0) > 0.2 })
        if #available(macOS 14.4, *) {
            XCTAssertTrue(waitUntil { view.videoLayer?.sampleBufferRenderer.displayedPixelBuffer() != nil })
        }
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .playing)
        let generation = owner.commandGeneration
        XCTAssertEqual(owner.performCommand(generation: generation) { $0.togglePlayPause() }, .success)
        XCTAssertTrue(waitUntil { latest?.status == .paused })
        let paused = try XCTUnwrap(latest?.timestamp)
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))
        XCTAssertEqual(try XCTUnwrap(latest?.timestamp), paused, accuracy: 0.03)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .paused)
        XCTAssertEqual(owner.performCommand(generation: generation) { $0.togglePlayPause() }, .success)
        XCTAssertTrue(waitUntil { latest?.status == .playing && (latest?.timestamp ?? 0) > paused + 0.2 })
        XCTAssertEqual(owner.performCommand(generation: generation) { $0.pause() }, .success)
        XCTAssertTrue(waitUntil { latest?.status == .paused })
        XCTAssertEqual(owner.performCommand(generation: generation) { $0.play() }, .success)
        XCTAssertTrue(waitUntil { latest?.status == .playing })
        player.pause()
        XCTAssertTrue(waitUntil { latest?.status == .paused })
        owner.clearNowPlaying()
        XCTAssertEqual(owner.performCommand(generation: generation) { $0.play() }, .commandFailed)
        XCTAssertEqual(latest?.status, .paused)
        XCTAssertNil(MPNowPlayingInfoCenter.default().nowPlayingInfo)
    }
}
