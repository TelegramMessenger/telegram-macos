import Foundation
import QuartzCore
import XCTest

infix operator |> : AdditionPrecedence

private struct LanguageSignal<Value> {
    let value: Value
    func start(next: @escaping (Value) -> Void) -> Bool {
        if LanguageCallbacks.deferred {
            LanguageCallbacks.pending.append { next(value) }
        } else {
            next(value)
        }
        return true
    }
}

private enum LanguageCallbacks {
    static var deferred = false
    static var pending: [() -> Void] = []
    static func drain() {
        let callbacks = pending
        pending.removeAll()
        callbacks.forEach { $0() }
    }
}

private func |> <Value, Result>(value: Value, transform: (Value) -> Result) -> Result { transform(value) }
private func take<Value>(_ count: Int) -> (LanguageSignal<Value>) -> LanguageSignal<Value> { { $0 } }
private func deliverOnMainQueue<Value>(_ signal: LanguageSignal<Value>) -> LanguageSignal<Value> { signal }
private func combineLatest<A, B>(_ a: LanguageSignal<A>, _ b: LanguageSignal<B>) -> LanguageSignal<(A, B)> { LanguageSignal(value: (a.value, b.value)) }
private func requestSpeechRecognitionPermission() -> LanguageSignal<Bool> { LanguageSignal(value: true) }

private enum LanguageRecordingState {
    case recording(duration: Double, durationMediaTimestamp: Double)
    case paused(duration: Double)
}

private final class LanguageRecorder {
    var state = LanguageRecordingState.recording(duration: 5, durationMediaTimestamp: CACurrentMediaTime())
    var recordingState: LanguageSignal<LanguageRecordingState> { LanguageSignal(value: state) }
}

private enum LanguageAudio {
    case recording(LanguageRecorder)
    case clip(Data, trimRange: Range<Double>?)
}

private enum ChatVoiceTranscription {
    typealias Audio = LanguageAudio
}

private final class LanguageSwitchHarness {
    enum Phase { case listening, preparing, finished }
    enum Failure { case speechDenied }
    var phase = Phase.listening
    var audio: LanguageAudio?
    var text = ""
    var language: String?
    var token = 0
    var recordingStartTime: Double = 0
    var createdStartTimes: [Double] = []
    var createdTokens: [Int] = []
    var engine: ListeningEngine? = ListeningEngine()
    let permissionDisposable = ListeningPermission()
    let chatInteraction: ComposerInteraction?
    var insertion: ChatInputDictationInsertion?
    var textEffect: ChatDictationTextEffect?
    var updatingComposer = false
    let recorder = LanguageRecorder()

    init(draft: String = "") {
        let input = ChatTextInputState(attributedText: NSAttributedString(string: draft), selectionRange: draft.utf16.count ..< draft.utf16.count)
        chatInteraction = ComposerInteraction(input)
        insertion = makeInsertion(input)
        audio = .recording(recorder)
    }
    var current: ChatTextInputState { chatInteraction!.presentation.effectiveInput }
    func recognize(_ value: String) { text = value; updateComposer() }
    func createEngine(token: Int) {
        createdStartTimes.append(recordingStartTime)
        createdTokens.append(token)
    }
    func fail(_ error: Failure) { XCTFail("Unexpected permission failure") }
    func switchLanguage() { restartForLanguageChange() }
    __MAKE_INSERTION__
    __UPDATE_COMPOSER__
    __RESTART__
}

private func temporaryMediaPath(_ prefix: String, _ suffix: String) -> String {
    NSTemporaryDirectory() + UUID().uuidString + "." + suffix
}

private final class OggOpusReader {
    let samples: [Int16]
    var position = 0
    init?(path: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        samples = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
    }
    func read(_ buffer: UnsafeMutableRawPointer, bufSize: Int32) -> Int32 {
        let count = min(Int(bufSize), samples.count - position)
        let output = buffer.assumingMemoryBound(to: Int16.self)
        for index in 0 ..< count { output[index] = samples[position + index] }
        position += count
        return Int32(count)
    }
}

private typealias ChatDictationRecordingSource = RecordingCutoffHarness

private final class RecordingCutoffHarness {
    static let sampleRate: Double = 48000
    static let readCapacity = 4
    let audio: LanguageAudio
    let recordingStartSample: Int
    var stopped = false
    var snapshotFed = false
    var pending: [Data] = []
    var finishing: (() -> Void)?
    var emitted: [Int16] = []
    var consume: (([Int16]) -> Void)?
    __SOURCE_INIT__
    func makeBuffer(_ samples: UnsafePointer<Int16>, count: Int) -> [Int16]? {
        Array(UnsafeBufferPointer(start: samples, count: count))
    }
    func emitLive(_ data: Data) {
        consume?(data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) })
    }
    func close() { stopped = true }
    func snapshot(_ data: Data?) {
        let callback: (Data?) -> Void = { [weak self] snapshot in
            __SNAPSHOT__
        }
        callback(data)
    }
    __RECEIVE__
    __FEED__
    __DECODE__
}

final class DictationLanguageSwitchTests: XCTestCase {
    override func tearDown() {
        LanguageCallbacks.deferred = false
        LanguageCallbacks.drain()
        super.tearDown()
    }

    func testSwitchPreservesTheExistingDraftAndTranscriptAndAppendsOnlyNewSpeech() {
        let view = LanguageSwitchHarness(draft: "Draft")
        view.recognize("Hello")
        view.switchLanguage()
        XCTAssertEqual(view.current.inputText, "Draft Hello")
        view.recognize("Привет")
        XCTAssertEqual(view.current.inputText, "Draft Hello Привет")
        view.switchLanguage()
        view.recognize("Bonjour")
        XCTAssertEqual(view.current.inputText, "Draft Hello Привет Bonjour")
        XCTAssertEqual(view.createdStartTimes.count, 2)
    }

    func testSwitchPreservesEditsAndTheCurrentCaret() {
        let view = LanguageSwitchHarness()
        view.recognize("Hello world")
        let input = ChatTextInputState(attributedText: NSAttributedString(string: "Hello my world"), selectionRange: 6 ..< 6)
        view.insertion = view.makeInsertion(input, consumedTranscript: view.text)
        view.chatInteraction!.presentation = ComposerPresentation(effectiveInput: input)
        view.switchLanguage()
        view.recognize("новый")
        XCTAssertEqual(view.current.inputText, "Hello новый my world")
    }

    func testSwitchUsesTheRecordingPositionAtSelectionTime() {
        let view = LanguageSwitchHarness()
        view.recorder.state = .recording(duration: 4, durationMediaTimestamp: CACurrentMediaTime() - 0.25)
        view.switchLanguage()
        XCTAssertEqual(view.createdStartTimes.first ?? 0, 4.25, accuracy: 0.1)
    }

    func testRapidSwitchesIgnoreThePreviousPreparationCallback() {
        let view = LanguageSwitchHarness()
        LanguageCallbacks.deferred = true
        view.switchLanguage()
        view.switchLanguage()
        LanguageCallbacks.drain()
        XCTAssertEqual(view.createdTokens, [2])
    }

    func testChangingLanguageDoesNotReplayACompletedClip() {
        let view = LanguageSwitchHarness()
        view.audio = .clip(Data([1]), trimRange: nil)
        view.switchLanguage()
        XCTAssertTrue(view.createdStartTimes.isEmpty)
    }

    func testSnapshotSkipsOldSpeechButKeepsAudioCapturedWhilePreparingAndLiveAudio() {
        let source = RecordingCutoffHarness(audio: .recording(LanguageRecorder()), recordingStartTime: 5 / 48000)
        var received: [Int16] = []
        source.consume = { received += $0 }
        func pcm(_ samples: [Int16]) -> Data { samples.withUnsafeBytes { Data($0) } }
        source.receive(pcm([10, 11]))
        source.snapshot(pcm(Array(0 ... 9)))
        source.receive(pcm([12, 13]))
        XCTAssertEqual(received, Array(5 ... 13))
    }

    func testInitialTranscriptionStillIncludesTheExistingRecording() {
        let source = RecordingCutoffHarness(audio: .recording(LanguageRecorder()))
        var received: [Int16] = []
        source.consume = { received += $0 }
        source.snapshot([Int16(1), 2, 3].withUnsafeBytes { Data($0) })
        XCTAssertEqual(received, [1, 2, 3])
    }
}
