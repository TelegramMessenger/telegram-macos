import XCTest
import Foundation
import CoreMedia
import AVFoundation
import HLSPlayback
import TelegramMediaPlayer
@testable import TelegramMedia

final class ChatHLSFragmentTimingTests: XCTestCase {
    private func fixture(_ name: String) -> URL {
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../submodules/telegram-ios/submodules/MediaPlayer/Tests/Fixtures/\(name).mp4").standardizedFileURL
    }

    private func assertTrack(_ actual: (start: Double, duration: Double)?, _ expected: FFMpegMediaInfo.Info?, _ label: String) {
        XCTAssertEqual(actual == nil, expected == nil, label)
        if let actual, let expected {
            XCTAssertEqual(actual.start, expected.startTime.seconds, accuracy: 0.000001, label)
            XCTAssertEqual(actual.duration, expected.duration.seconds, accuracy: 0.000001, label)
        }
    }

    func testNativePartTimingMatchesRealFFmpegProbeIncludingAACPriming() throws {
        for name in ["fragment", "fragment720", "fragment-videoedit", "fragment-edit"] {
            let url = fixture(name)
            let data = try Data(contentsOf: url)
            XCTAssertNotNil(HLSFragmentTiming.parse(data), name)
            let expected = try XCTUnwrap(extractFFMpegMediaInfo(path: url.path), name)
            let actual = try XCTUnwrap(HLSNativePartStore.trackTiming(data: data, path: url.path), name)
            assertTrack(actual.audio, expected.audio, name + " audio")
            assertTrack(actual.video, expected.video, name + " video")
            XCTAssertEqual(actual.videoCodecName, expected.video?.codecName, name)
        }
    }

    func testNativePartTimingFallsBackForAnOrdinaryMP4() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let output = directory.appendingPathComponent("ordinary.mp4")
        let asset = AVURLAsset(url: fixture("fragment-edit"))
        let export = try XCTUnwrap(AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough))
        export.outputURL = output
        export.outputFileType = .mp4
        let finished = expectation(description: "remux ordinary MP4")
        export.exportAsynchronously { finished.fulfill() }
        wait(for: [finished], timeout: 20)
        XCTAssertEqual(export.status, .completed, String(describing: export.error))
        let data = try Data(contentsOf: output)
        XCTAssertNil(HLSFragmentTiming.parse(data))
        let expected = try XCTUnwrap(extractFFMpegMediaInfo(path: output.path))
        let actual = try XCTUnwrap(HLSNativePartStore.trackTiming(data: data, path: output.path))
        assertTrack(actual.audio, expected.audio, "fallback audio")
        assertTrack(actual.video, expected.video, "fallback video")
        XCTAssertEqual(actual.videoCodecName, expected.video?.codecName)
    }
}
