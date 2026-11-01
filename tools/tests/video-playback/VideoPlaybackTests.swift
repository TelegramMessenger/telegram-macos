import AppKit
import AVFoundation
import XCTest
import Postbox
import TelegramCore
import TelegramMediaPlayer
import SwiftSignalKit
@testable import TelegramMedia

final class VideoPlaybackTests: XCTestCase {
    private static let initializeTempBox: Void = {
        TempBox.initializeShared(basePath: NSTemporaryDirectory() + "VideoPlaybackTests-" + UUID().uuidString, processType: "tests", launchSpecificId: Int64.random(in: 0 ... Int64.max))
    }()

    private func fixture(_ name: String) -> String {
        return URL(fileURLWithPath: ProcessInfo.processInfo.environment["VIDEO_PLAYBACK_FIXTURES"]!).appendingPathComponent(name + ".mp4").path
    }

    private func file(codec: String?, alternatives: [TelegramMediaFile] = [], mimeType: String = "video/mp4", video: Bool = true) -> TelegramMediaFile {
        return TelegramMediaFile(
            fileId: MediaId(namespace: 0, id: 1), partialReference: nil,
            resource: LocalFileMediaResource(fileId: 1), previewRepresentations: [], videoThumbnails: [],
            immediateThumbnailData: nil, mimeType: mimeType, size: 100,
            attributes: video ? [.Video(duration: 3.0, size: PixelDimensions(width: 128, height: 96), flags: [.supportsStreaming], preloadSize: nil, coverTime: nil, videoCodec: codec)] : [],
            alternativeRepresentations: alternatives
        )
    }

    private func spin(timeout: Double, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private func pixelHash(_ buffer: CVPixelBuffer) -> UInt64 {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        let planar = CVPixelBufferIsPlanar(buffer)
        let base = planar ? CVPixelBufferGetBaseAddressOfPlane(buffer, 0) : CVPixelBufferGetBaseAddress(buffer)
        let stride = planar ? CVPixelBufferGetBytesPerRowOfPlane(buffer, 0) : CVPixelBufferGetBytesPerRow(buffer)
        let width = planar ? CVPixelBufferGetWidthOfPlane(buffer, 0) : CVPixelBufferGetWidth(buffer) * 4
        let height = planar ? CVPixelBufferGetHeightOfPlane(buffer, 0) : CVPixelBufferGetHeight(buffer)
        guard let bytes = base?.assumingMemoryBound(to: UInt8.self) else {
            return 0
        }
        var hash: UInt64 = 14695981039346656037
        for y in 0 ..< height {
            for x in 0 ..< width {
                hash = (hash ^ UInt64(bytes[y * stride + x])) &* 1099511628211
            }
        }
        return hash
    }

    private func tempFile(_ name: String) throws -> ChunkMediaPlayerPart.TempFile {
        let _ = Self.initializeTempBox
        let file = TempBox.shared.tempFile(fileName: name + ".mp4")
        try Data(contentsOf: URL(fileURLWithPath: fixture(name))).write(to: URL(fileURLWithPath: file.path))
        return ChunkMediaPlayerPart.TempFile(file: file)
    }

    @objc func testPlayerSelection() {
        XCTAssertTrue(shouldUseChunkedVideoPlayer(file: file(codec: nil)))
        XCTAssertTrue(shouldUseChunkedVideoPlayer(file: file(codec: "av1")))
        XCTAssertTrue(shouldUseChunkedVideoPlayer(file: file(codec: "av01")))
        for codec in ["h264", "hevc", "vp9", "other"] {
            XCTAssertFalse(shouldUseChunkedVideoPlayer(file: file(codec: codec)))
        }
        let playlist = file(codec: nil, mimeType: "application/x-mpegurl", video: false)
        XCTAssertFalse(shouldUseChunkedVideoPlayer(file: file(codec: nil, alternatives: [playlist])))
        XCTAssertFalse(shouldUseChunkedVideoPlayer(file: file(codec: "av1", alternatives: [playlist])))
        XCTAssertFalse(shouldUseChunkedVideoPlayer(file: file(codec: nil, video: false)))
    }

    @objc func testActualDecodedPixelsAndAudio() throws {
        for codec in ["av1", "h264", "hevc"] {
            let reader = FFMpegMediaDataReaderV2(content: .tempFile(try tempFile(codec)), isVideo: true, codecName: codec)
            XCTAssertTrue(reader.hasVideo, codec)
            var hashes = Set<UInt64>()
            var frames = 0
            for _ in 0 ..< 60 {
                switch reader.readSampleBuffer() {
                case let .frame(sample):
                    let image = try XCTUnwrap(CMSampleBufferGetImageBuffer(sample), codec)
                    hashes.insert(pixelHash(image))
                    frames += 1
                case .endOfStream:
                    break
                case .waitingForMoreData, .error:
                    XCTFail("Unexpected decoder result for \(codec)")
                }
            }
            XCTAssertEqual(frames, 30, codec)
            XCTAssertGreaterThan(hashes.count, 10, codec)
            let audio = FFMpegMediaDataReaderV2(content: .tempFile(try tempFile(codec)), isVideo: false, codecName: codec)
            XCTAssertTrue(audio.hasAudio, codec)
            guard case let .frame(sample) = audio.readSampleBuffer() else {
                XCTFail("Missing audio for \(codec)")
                continue
            }
            XCTAssertGreaterThan(CMSampleBufferGetNumSamples(sample), 0, codec)
        }
    }

    @objc func testLookaheadDetectsCodecAndRotation() throws {
        for (name, codec, expectedRotation) in [("av1", "av1", 0.0), ("h264", "h264", 0.0), ("hevc", "hevc", 0.0), ("h264-rotated", "h264", Double.pi * 1.5)] {
            let data = try Data(contentsOf: URL(fileURLWithPath: fixture(name)))
            let state = Atomic<FFMpegLookahead.State?>(value: nil)
            let lookahead = FFMpegLookahead(
                seekToTimestamp: 0.0, lookaheadDuration: 10.0,
                updateState: { value in let _ = state.swap(value) },
                fetchInRange: { _ in return EmptyDisposable },
                getDataInRange: { range, completion in
                    let start = min(data.count, max(0, Int(range.lowerBound)))
                    let end = min(data.count, max(start, Int(range.upperBound)))
                    completion(data.subdata(in: start ..< end))
                    return EmptyDisposable
                },
                isDataCachedInRange: { _ in return true }, size: Int64(data.count)
            )
            lookahead.updateCurrentTimestamp(timestamp: 0.0)
            spin(timeout: 5.0, until: { state.with { $0?.isEnded == true } })
            let video = try XCTUnwrap(state.with { $0?.video }, name)
            XCTAssertEqual(resolveFFMpegCodecName(id: video.info.codecId), codec, name)
            let geometry = try XCTUnwrap(video.videoGeometry, name)
            XCTAssertEqual(geometry.rotationAngle, expectedRotation, accuracy: 0.001, name)
            XCTAssertEqual(geometry.displayDimensions, expectedRotation == 0 ? CGSize(width: 128, height: 96) : CGSize(width: 96, height: 128), name)
            let view = MediaPlayerView()
            view.frame = CGRect(origin: .zero, size: geometry.displayDimensions)
            view.setVideoGeometry(rotationAngle: geometry.rotationAngle, aspect: geometry.aspect)
            let layer = try XCTUnwrap(view.videoLayer)
            let transformed = layer.bounds.applying(layer.affineTransform())
            XCTAssertEqual(transformed.width, geometry.displayDimensions.width, accuracy: 0.01, name)
            XCTAssertEqual(transformed.height, geometry.displayDimensions.height, accuracy: 0.01, name)
            view.preventsCapture = true
            XCTAssertTrue(layer.preventsCapture)
            withExtendedLifetime(lookahead) {}
        }
    }

    @objc func testChunkedPlayerDisplaysMovingPixelsAndLoops() throws {
        guard #available(macOS 14.4, *) else { return }
        let _ = NSApplication.shared
        for codec in ["av1", "h264", "hevc"] {
            let state = Promise<ChunkMediaPlayerPartsState>()
            let part = ChunkMediaPlayerPart(startTime: 0.0, endTime: 3.0, content: try tempFile(codec), codecName: codec, offsetTime: 0.0)
            state.set(.single(ChunkMediaPlayerPartsState(duration: 3.0, content: .parts([part]))))
            let view = MediaPlayerView()
            view.frame = CGRect(x: 0, y: 0, width: 128, height: 96)
            let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = view
            window.orderFront(nil)
            defer { window.close() }
            let player = ChunkMediaPlayerV2(params: .init(useV2Reader: true), source: .externalParts(state.get()), video: true, enableSound: false, playerNode: view)
            var loops = 0
            player.actionAtEnd = .loop({ loops += 1 })
            player.play()
            let layer = try XCTUnwrap(view.videoLayer)
            var hashes = Set<UInt64>()
            spin(timeout: 6.0, until: {
                if let buffer = layer.sampleBufferRenderer.displayedPixelBuffer() {
                    hashes.insert(self.pixelHash(buffer))
                }
                return loops > 0 && hashes.count > 5
            })
            player.pause()
            XCTAssertGreaterThan(hashes.count, 5, codec)
            XCTAssertGreaterThan(loops, 0, codec)
            withExtendedLifetime(player) {}
        }
    }

    @objc func testLookaheadWaitsForMissingData() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: fixture("av1")))
        let available = Atomic<Bool>(value: false)
        let pending = Atomic<(() -> Void)?>(value: nil)
        let state = Atomic<FFMpegLookahead.State?>(value: nil)
        let lookahead = FFMpegLookahead(
            seekToTimestamp: 0.0, lookaheadDuration: 10.0,
            updateState: { value in let _ = state.swap(value) },
            fetchInRange: { _ in return EmptyDisposable },
            getDataInRange: { range, completion in
                let deliver = {
                    let start = min(data.count, max(0, Int(range.lowerBound)))
                    let end = min(data.count, max(start, Int(range.upperBound)))
                    completion(data.subdata(in: start ..< end))
                }
                if available.with({ $0 }) {
                    deliver()
                } else {
                    let _ = pending.swap(deliver)
                }
                return EmptyDisposable
            },
            isDataCachedInRange: { _ in return available.with { $0 } }, size: Int64(data.count)
        )
        lookahead.updateCurrentTimestamp(timestamp: 0.0)
        spin(timeout: 2.0, until: { pending.with { $0 != nil } })
        XCTAssertNil(state.with { $0 })
        let _ = available.swap(true)
        let deliver = try XCTUnwrap(pending.swap(nil))
        deliver()
        spin(timeout: 5.0, until: { state.with { $0?.isEnded == true } })
        XCTAssertNotNil(state.with { $0?.video })
        XCTAssertTrue(state.with { $0?.isEnded == true })
        withExtendedLifetime(lookahead) {}
    }

    private func expectedFrameHash(codec: String, timestamp: Double) throws -> UInt64 {
        let content = try tempFile(codec)
        let reader: MediaDataReader
        if codec == "av1", TelegramMediaPlayer.internal_isHardwareAv1Supported {
            reader = AVAssetVideoDataReader(filePath: content.file.path, isVideo: true)
        } else {
            reader = FFMpegMediaDataReaderV2(content: .tempFile(content), isVideo: true, codecName: codec)
        }
        var last: UInt64?
        for _ in 0 ..< 60 {
            guard case let .frame(sample) = reader.readSampleBuffer() else {
                break
            }
            last = pixelHash(try XCTUnwrap(CMSampleBufferGetImageBuffer(sample)))
            if CMSampleBufferGetPresentationTimeStamp(sample).seconds >= timestamp {
                return last!
            }
        }
        return try XCTUnwrap(last)
    }

    private func checkPausedSeeks(codec: String, direct: Bool) throws {
        let _ = NSApplication.shared
        let content = try tempFile(codec)
        let state = Promise<ChunkMediaPlayerPartsState>()
        let part = ChunkMediaPlayerPart(startTime: 0.0, endTime: 3.0, content: content, codecName: codec, offsetTime: 0.0)
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("VideoPlaybackMedia-" + UUID().uuidString)
        let mediaBox = MediaBox(basePath: directory.path, isMainProcess: true)
        let data = try Data(contentsOf: URL(fileURLWithPath: content.file.path))
        let resource = LocalFileMediaResource(fileId: Int64.random(in: 0 ... Int64.max), size: Int64(data.count))
        mediaBox.storeResourceData(resource.id, data: data, synchronous: true)
        let info = try XCTUnwrap(extractFFMpegMediaInfo(path: content.file.path))
        let videoInfo = try XCTUnwrap(info.video)
        func publish(id: Int, timestamp: Double) {
            if direct {
                let seek = (streamIndex: videoInfo.index, pts: CMTime(seconds: timestamp, preferredTimescale: videoInfo.timescale).value)
                let video = ChunkMediaPlayerPartsState.DirectReader.Stream(mediaBox: mediaBox, resource: resource, size: Int64(data.count), index: videoInfo.index, seek: seek, maxReadablePts: nil, codecName: codec)
                let audio = info.audio.map { audio in
                    ChunkMediaPlayerPartsState.DirectReader.Stream(mediaBox: mediaBox, resource: resource, size: Int64(data.count), index: audio.index, seek: seek, maxReadablePts: nil, codecName: codec)
                }
                state.set(.single(ChunkMediaPlayerPartsState(duration: 3.0, content: .directReader(.init(id: id, seekPosition: timestamp, availableUntilPosition: 3.0, bufferedUntilEnd: true, impl: .init(video: video, audio: audio))))))
            } else {
                state.set(.single(ChunkMediaPlayerPartsState(duration: 3.0, content: .parts([part]))))
            }
        }
        publish(id: 0, timestamp: 0.0)
        let view = MediaPlayerView()
        view.frame = CGRect(x: 0, y: 0, width: 128, height: 96)
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        defer { window.close() }
        let player = ChunkMediaPlayerV2(params: .init(useV2Reader: true), source: .externalParts(state.get()), video: true, enableSound: true, volume: 0.0, playerNode: view)
        var endActions = 0
        player.actionAtEnd = .loop({ endActions += 1 })
        var status: MediaPlayerStatus?
        let disposable = player.status.start(next: { status = $0 })
        defer { disposable.dispose() }
        let layer = try XCTUnwrap(view.videoLayer)
        func displayedHash() -> UInt64? {
            return layer.sampleBufferRenderer.displayedPixelBuffer().map(pixelHash)
        }
        player.play()
        spin(timeout: 4.0, until: { displayedHash() != nil })
        XCTAssertNotNil(displayedHash())
        player.pause()
        var id = 0
        func seek(_ timestamp: Double) {
            id += 1
            player.seek(timestamp: timestamp, play: false)
            publish(id: id, timestamp: timestamp)
        }
        for target in [2.0, 0.4, 2.95] {
            let expected = try expectedFrameHash(codec: codec, timestamp: target)
            var didReportReady = false
            var frameWhenReady: UInt64?
            let readiness = player.status.start(next: { value in
                if value.seekId == id, abs(value.timestamp - target) < 0.02, case .paused = value.status, !didReportReady {
                    didReportReady = true
                    frameWhenReady = displayedHash()
                }
            })
            seek(target)
            spin(timeout: 5.0, until: { didReportReady && displayedHash() == expected && status?.seekId == id && abs((status?.timestamp ?? -1.0) - target) < 0.02 })
            readiness.dispose()
            XCTAssertEqual(displayedHash(), expected, "\(codec) direct=\(direct) target=\(target)")
            XCTAssertTrue(didReportReady)
            XCTAssertEqual(frameWhenReady, expected, "Seek was reported ready before the target frame was displayed")
            XCTAssertEqual(try XCTUnwrap(status).timestamp, target, accuracy: 0.02)
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
            XCTAssertEqual(try XCTUnwrap(status).timestamp, target, accuracy: 0.02)
            XCTAssertEqual(displayedHash(), expected)
            XCTAssertEqual(endActions, 0, "Paused seeking triggered the end action")
            guard case .paused = status?.status else {
                XCTFail("Paused seek started playback")
                continue
            }
        }
        for target in [0.2, 2.4, 0.8] {
            seek(target)
        }
        let expected = try expectedFrameHash(codec: codec, timestamp: 0.8)
        spin(timeout: 5.0, until: { displayedHash() == expected && status?.seekId == id && abs((status?.timestamp ?? -1.0) - 0.8) < 0.02 })
        XCTAssertEqual(displayedHash(), expected, "Superseded seek displayed a stale frame")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(displayedHash(), expected)
        XCTAssertEqual(try XCTUnwrap(status).timestamp, 0.8, accuracy: 0.02)
        player.play()
        spin(timeout: 3.0, until: { (status?.timestamp ?? 0.0) > 1.0 && displayedHash() != expected })
        XCTAssertGreaterThan(status?.timestamp ?? 0.0, 1.0)
        XCTAssertNotEqual(displayedHash(), expected)
        for target in [2.0, 0.4, 2.4] {
            player.pause()
            seek(target)
            player.play()
            var displayed = Set<UInt64>()
            spin(timeout: 3.0, until: {
                if let hash = displayedHash() {
                    displayed.insert(hash)
                }
                return (status?.timestamp ?? 0.0) > target + 0.2 && displayed.count > 1
            })
            XCTAssertGreaterThan(status?.timestamp ?? 0.0, target + 0.2, "Scrubbing did not resume playback")
            XCTAssertGreaterThan(displayed.count, 1, "Scrubbing left the picture stuck")
        }
        player.pause()
        view.preventsCapture = true
        seek(1.0)
        spin(timeout: 2.0, until: {
            if status?.seekId == id, case .paused = status?.status {
                return true
            }
            return false
        })
        XCTAssertEqual(status?.seekId, id)
        XCTAssertEqual(status?.timestamp ?? -1.0, 1.0, accuracy: 0.02)
        XCTAssertEqual(status?.status, .paused, "Capture protection prevented the seek from completing")
        player.play()
        spin(timeout: 2.0, until: { (status?.timestamp ?? 0.0) > 1.2 })
        XCTAssertGreaterThan(status?.timestamp ?? 0.0, 1.2)
        player.pause()
        view.preventsCapture = false
        window.orderOut(nil)
        seek(0.2)
        spin(timeout: 2.0, until: {
            if status?.seekId == id, case .paused = status?.status {
                return true
            }
            return false
        })
        XCTAssertEqual(status?.status, .paused, "An unavailable displayed frame prevented the seek from completing")
        XCTAssertEqual(status?.timestamp ?? -1.0, 0.2, accuracy: 0.02)
        withExtendedLifetime((player, mediaBox)) {}
    }

    @objc func testPausedSeeksForChunkedParts() throws {
        for codec in ["av1", "h264", "hevc"] {
            try checkPausedSeeks(codec: codec, direct: false)
        }
    }

    @objc func testPausedSeeksForDirectReaders() throws {
        for codec in ["av1", "h264", "hevc"] {
            try checkPausedSeeks(codec: codec, direct: true)
        }
    }
}

let suite = XCTestSuite(forTestCaseClass: VideoPlaybackTests.self)
suite.run()
exit(suite.testRun?.hasSucceeded == true ? 0 : 1)
