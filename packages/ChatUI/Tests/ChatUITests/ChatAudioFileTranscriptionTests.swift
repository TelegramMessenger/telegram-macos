import XCTest
import SwiftSignalKit
import TelegramCore
import TelegramMedia
import OpusBinding
@testable import ChatUI

final class ChatAudioFileTranscriptionTests: XCTestCase {
    private func recording(seconds: Double) throws -> Data {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString + ".ogg")
        defer { try? FileManager.default.removeItem(at: url) }
        let item = DataItem(path: url.path)
        let writer = TGOggOpusWriter()
        XCTAssertTrue(writer.begin(with: item))
        var samples = [Int16](repeating: 0, count: 960)
        for _ in 0 ..< Int(seconds * 50) {
            let written = samples.withUnsafeMutableBytes { bytes in
                writer.writeFrame(bytes.baseAddress!.assumingMemoryBound(to: UInt8.self), frameByteCount: UInt(bytes.count))
            }
            XCTAssertTrue(written)
        }
        XCTAssertTrue(writer.writeFrame(nil, frameByteCount: 0))
        return try Data(contentsOf: url)
    }

    func testPreparedClipKeepsAudioAndMeasuresDuration() throws {
        let data = try recording(seconds: 3)
        let done = expectation(description: "prepared")
        var duration: Double?
        let disposable = prepareAudioFileTranscription(data, trimRange: nil).start(next: { audio, value in
            XCTAssertEqual(audio, data)
            duration = value
        }, error: { error in
            XCTFail("Unexpected error: \(error)")
            done.fulfill()
        }, completed: { done.fulfill() })
        wait(for: [done], timeout: 5)
        XCTAssertEqual(try XCTUnwrap(duration), 3, accuracy: 0.03)
        disposable.dispose()
    }

    func testTrimmedClipUploadsOnlySelectedRange() throws {
        let data = try recording(seconds: 4)
        let done = expectation(description: "trimmed")
        var duration: Double?
        let disposable = prepareAudioFileTranscription(data, trimRange: 1 ..< 3).start(next: { audio, value in
            XCTAssertNotEqual(audio, data)
            duration = value
        }, error: { error in
            XCTFail("Unexpected error: \(error)")
            done.fulfill()
        }, completed: { done.fulfill() })
        wait(for: [done], timeout: 5)
        XCTAssertEqual(try XCTUnwrap(duration), 2, accuracy: 0.03)
        disposable.dispose()
    }

    func testInvalidAndTooShortClipsFailBeforeUpload() throws {
        for data in [Data("invalid".utf8), try recording(seconds: 0.5)] {
            let done = expectation(description: "rejected")
            let disposable = prepareAudioFileTranscription(data, trimRange: nil).start(next: { _ in
                XCTFail("Invalid audio was accepted")
            }, error: { error in
                XCTAssertEqual(error, .invalidAudio)
                done.fulfill()
            })
            wait(for: [done], timeout: 5)
            disposable.dispose()
        }
    }

    func testNativeClipSourceFeedsOnlySelectedSamples() throws {
        let data = try recording(seconds: 4)
        let source = ChatDictationRecordingSource(audio: .clip(data, trimRange: 1 ..< 3))
        let done = expectation(description: "native clip decoded")
        let frames = Atomic(value: 0)
        source.onEnded = { done.fulfill() }
        source.start { buffer in
            _ = frames.modify { $0 + Int(buffer.frameLength) }
        }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(frames.with { $0 }, 2 * 48000)
        source.stop()
    }

    @available(macOS 10.15, *)
    func testServerLanguageSuggestionsKeepTheirProbabilityOrder() {
        let preferences = ChatDictationEngineFactory.automaticPreferences(chatLanguage: "fr", suggestedLanguages: ["ru-RU", "en-US", "uz-UZ"])
        XCTAssertEqual(Array(preferences.prefix(3)), ["ru-RU", "en-US", "uz-UZ"])
        XCTAssertTrue(preferences.contains("fr"))
    }
}
