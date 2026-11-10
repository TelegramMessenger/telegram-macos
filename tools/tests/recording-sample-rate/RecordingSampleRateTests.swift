import Foundation
import AVFoundation
import AudioToolbox
import QuartzCore
import XCTest
private let opusDecodedSampleRate = 48000
__CONVERTER__
__FORMAT__
func trace1(_ name: String, what: String) {}
final class RecorderQueue { func isCurrent() -> Bool { true } }
final class AudioUnitSlot { func swap(_ value: AudioUnit?) -> AudioUnit? { nil } }
enum RecordingState { case recording(duration: Double, durationMediaTimestamp: Double), paused(duration: Double) }
final class RecordingStateSink { func set(_ value: RecordingState) {} }
final class UploadSink { func fileDidChangedSize(_ completed: Bool) {} }
struct RecordedAudioData { let pcm: Data; let duration: Double }
final class PCMWriter {
    var pcm = Data()
    private var finished = false
    @discardableResult func writeFrame(_ bytes: UnsafeMutablePointer<UInt8>?, frameByteCount: UInt) -> Bool {
        guard !finished, frameByteCount <= 1920, frameByteCount.isMultiple(of: 2) else { return false }
        if frameByteCount == 0 { finished = true }
        else if let bytes { pcm.append(bytes, count: Int(frameByteCount)) }
        else { return false }
        return true
    }
    func encodedDuration() -> Double { Double(pcm.count / 2) / Double(opusDecodedSampleRate) }
    func pause() -> [AnyHashable: Any] { [:] }
    func resume(with item: Int, encoderState: [AnyHashable: Any]) -> Bool { !finished }
}
final class Recorder {
    let queue = RecorderQueue(), audioUnit = AudioUnitSlot(), recordingState = RecordingStateSink()
    let oggWriter = PCMWriter(), dataItem = 0
    var liveUploading: UploadSink?
    var recordingStateUpdateTimestamp: Double?
    var encoderState: [AnyHashable: Any]?
    var audioBuffer = Data(), paused = true
    var pcmTap: ((Data) -> Void)?
    var sampleRate: Int32
    var convertor: CustomAudioConverter!
    init(rate: Int32) { sampleRate = rate; start() }
    func start() { paused = false; convertor = CustomAudioConverter(asbd: audioRecorderNativeStreamDescription(Double(sampleRate))); precondition(convertor != nil) }
    func processWaveformPreview(samples: UnsafePointer<Int16>, count: Int) {}
    func makeWaveformBitstream() -> Data? { nil }
    func snapshot(waveform: Data?, displayWaveform: Data?) -> RecordedAudioData { RecordedAudioData(pcm: oggWriter.pcm, duration: oggWriter.encodedDuration()) }
    __METHODS__
    func feed(_ samples: [Int16], chunks: [Int]) {
        var offset = 0, index = 0
        samples.withUnsafeBytes { bytes in
            while offset < samples.count {
                let count = min(chunks[index % chunks.count], samples.count - offset), memory = malloc(count * 2)!
                memcpy(memory, bytes.baseAddress!.advanced(by: offset * 2), count * 2)
                processAndDisposeAudioBuffer(AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(count * 2), mData: memory))
                offset += count; index += 1
            }
        }
    }
}
final class RecordingSampleRateTests: XCTestCase {
    let frequency = 440.0
    func signal(rate: Int32, duration: Double = 2) -> [Int16] { (0 ..< Int(Double(rate) * duration)).map { Int16((sin(2 * .pi * frequency * Double($0) / Double(rate)) * 10000).rounded()) } }
    func samples(_ data: Data) -> [Int16] { data.withUnsafeBytes { bytes in (0 ..< data.count / 2).map { bytes.loadUnaligned(fromByteOffset: $0 * 2, as: Int16.self) } } }
    func pitch(_ values: [Int16]) -> Double {
        let start = min(2400, values.count / 4), end = values.count - start
        guard end > start + 1 else { return 0 }
        var crossings: [Double] = []
        for index in start ..< end - 1 where values[index] <= 0 && values[index + 1] > 0 {
            let fraction = -Double(values[index]) / Double(Int(values[index + 1]) - Int(values[index]))
            crossings.append(Double(index) + fraction)
        }
        guard let first = crossings.first, let last = crossings.last, last > first else { return 0 }
        return Double(opusDecodedSampleRate) * Double(crossings.count - 1) / (last - first)
    }
    func record(rate: Int32, chunks: [Int] = [1024], duration: Double = 2) -> RecordedAudioData {
        let recorder = Recorder(rate: rate); recorder.feed(signal(rate: rate, duration: duration), chunks: chunks); recorder.stop(); return recorder.takeData()!
    }
    func test44100PreservesPitchAndDuration() { let r = record(rate: 44100); XCTAssertEqual(pitch(samples(r.pcm)), frequency, accuracy: 0.05); XCTAssertEqual(r.duration, 2, accuracy: 1.0 / 48000) }
    func testSupportedRatesPreservePitchAndDuration() {
        for rate: Int32 in [8000, 12000, 16000, 24000, 48000, 96000] {
            let r = record(rate: rate); XCTAssertEqual(pitch(samples(r.pcm)), frequency, accuracy: 0.05, "rate \(rate)"); XCTAssertEqual(r.duration, 2, accuracy: 1.0 / 48000, "rate \(rate)")
        }
    }
    func test48000PreservesEverySample() { let input = (0 ..< 12480).map { Int16(($0 * 7919) % 60001 - 30000) }, r = Recorder(rate: 48000); r.feed(input, chunks: [1, 511, 1024, 7]); r.stop(); XCTAssertEqual(samples(r.takeData()!.pcm), input) }
    func testChunkBoundariesDoNotChangeConversion() {
        let whole = samples(record(rate: 44100, chunks: [88200]).pcm), fragmented = samples(record(rate: 44100, chunks: [1, 13, 511, 7, 1024, 4096]).pcm)
        XCTAssertEqual(whole.count, fragmented.count); XCTAssertLessThanOrEqual(zip(whole, fragmented).map { abs(Int($0) - Int($1)) }.max() ?? 0, 1)
    }
    func testLargeInputBufferIsFullyDrained() { let r = record(rate: 16000, chunks: [80000], duration: 5); XCTAssertEqual(r.duration, 5, accuracy: 1.0 / 48000); XCTAssertEqual(pitch(samples(r.pcm)), frequency, accuracy: 0.05) }
    func testPauseResumeCanChangeInputRate() {
        let r = Recorder(rate: 44100); r.feed(signal(rate: 44100, duration: 1), chunks: [1024]); r.pause(); r.sampleRate = 24000; r.resume(); r.feed(signal(rate: 24000, duration: 1), chunks: [311, 1024]); r.stop()
        let recording = r.takeData()!, values = samples(recording.pcm)
        XCTAssertEqual(recording.duration, 2, accuracy: 1.0 / 48000); XCTAssertEqual(pitch(Array(values.prefix(48000))), frequency, accuracy: 0.05); XCTAssertEqual(pitch(Array(values.suffix(48000))), frequency, accuracy: 0.05)
    }
    func testCallbacksAfterPauseAreDiscarded() { let r = Recorder(rate: 44100); r.feed(signal(rate: 44100, duration: 1), chunks: [1024]); r.pause(); r.feed(signal(rate: 44100, duration: 1), chunks: [1024]); XCTAssertEqual(r.takeData()!.duration, 1, accuracy: 1.0 / 48000) }
    func testRepeatedStopDoesNotDuplicateTail() {
        let r = Recorder(rate: 44100); r.feed(signal(rate: 44100), chunks: [137]); r.stop()
        let count = r.oggWriter.pcm.count + r.audioBuffer.count; r.stop()
        XCTAssertEqual(r.oggWriter.pcm.count + r.audioBuffer.count, count); XCTAssertEqual(r.takeData()!.duration, 2, accuracy: 1.0 / 48000)
    }
    func testEmptyRecordingStaysEmpty() { let r = Recorder(rate: 44100); r.stop(); XCTAssertEqual(r.takeData()!.duration, 0) }
    func testTakingDataFlushesAnActiveConverter() { let r = Recorder(rate: 44100); r.feed(signal(rate: 44100), chunks: [137]); let recording = r.takeData()!; XCTAssertEqual(recording.duration, 2, accuracy: 1.0 / 48000); XCTAssertEqual(pitch(samples(recording.pcm)), frequency, accuracy: 0.05) }
    func testShortRecordingLengthStaysWithinOneEncoderFrame() {
        for rate: Int32 in [16000, 24000, 44100, 48000] { let r = record(rate: rate, chunks: [17, 331], duration: 0.123); XCTAssertLessThanOrEqual(r.duration, 0.123 + 1.0 / 48000); XCTAssertGreaterThan(r.duration, 0.123 - 0.02) }
    }
    func testPCMTapReceivesResampledAudioAcrossPauseAndResume() {
        let r = Recorder(rate: 44100); var tapped = Data(); r.pcmTap = { tapped.append($0) }
        r.feed(signal(rate: 44100, duration: 1), chunks: [137, 1024]); XCTAssertFalse(tapped.isEmpty); r.pause()
        let count = tapped.count; r.feed(signal(rate: 44100, duration: 0.1), chunks: [311]); XCTAssertEqual(tapped.count, count)
        r.sampleRate = 24000; r.resume(); r.feed(signal(rate: 24000, duration: 1), chunks: [311, 1024]); let recording = r.takeData()!
        XCTAssertEqual(tapped, recording.pcm); XCTAssertEqual(Double(tapped.count / 2) / Double(opusDecodedSampleRate), 2, accuracy: 1.0 / 48000); XCTAssertEqual(pitch(samples(tapped)), frequency, accuracy: 0.05)
    }

}
