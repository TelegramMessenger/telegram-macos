import XCTest
import SwiftSignalKit
@testable import TelegramCore
@testable import ChatUI

final class ChatRecordedAudioTranscriptionTests: XCTestCase {
    func testNativeSuccessNeverStartsServerUpload() {
        var nativeCalls = 0
        var serverCalls = 0
        var text: String?
        let signal = transcribeRecordedAudio(native: {
            nativeCalls += 1
            return .single("Native text")
        }, server: {
            serverCalls += 1
            return .single("Server text")
        }, isSecretChat: false)
        XCTAssertEqual(nativeCalls, 0)
        let disposable = signal.start(next: { text = $0 })
        XCTAssertEqual(nativeCalls, 1)
        XCTAssertEqual(serverCalls, 0)
        XCTAssertEqual(text, "Native text")
        disposable.dispose()
    }

    func testOlderSystemUsesServerWithoutNativePermissionRequest() {
        var calls = 0
        var text: String?
        let disposable = transcribeRecordedAudio(native: nil, server: {
            calls += 1
            return .single("Older system text")
        }, isSecretChat: false).start(next: { text = $0 })
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(text, "Older system text")
        disposable.dispose()
    }

    func testUnavailableUnsupportedAndFailedNativeFallBackToServer() {
        for error: ChatDictationError in [.unavailable, .unsupportedLanguage, .failed] {
            var calls = 0
            var text: String?
            let disposable = transcribeRecordedAudio(native: { .fail(error) }, server: {
                calls += 1
                return .single("Fallback")
            }, isSecretChat: false).start(next: { text = $0 })
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(text, "Fallback")
            disposable.dispose()
        }
    }

    func testAsynchronousServerFallbackSurvivesImmediateNativeFailure() {
        let pipe = ValuePipe<String>()
        var values: [String] = []
        let disposable = transcribeRecordedAudio(native: { .fail(.unavailable) }, server: {
            pipe.signal() |> castError(AudioFileTranscriptionError.self)
        }, isSecretChat: false).start(next: { values.append($0) })
        pipe.putNext("Asynchronous fallback")
        XCTAssertEqual(values, ["Asynchronous fallback"])
        disposable.dispose()
    }

    func testEmptyNativeResultFallsBackInsteadOfLeavingEmptyComposer() {
        for native: Signal<String, ChatDictationError> in [.single(" \n"), .complete()] {
            var calls = 0
            var text: String?
            let disposable = transcribeRecordedAudio(native: { native }, server: {
                calls += 1
                return .single("Recovered")
            }, isSecretChat: false).start(next: { text = $0 })
            XCTAssertEqual(calls, 1)
            XCTAssertEqual(text, "Recovered")
            disposable.dispose()
        }
    }

    func testPermissionDenialDoesNotSilentlyUploadRecording() {
        for error: ChatDictationError in [.speechDenied, .microphoneDenied] {
            var calls = 0
            var received: ChatRecordedAudioTranscriptionError?
            let disposable = transcribeRecordedAudio(native: { .fail(error) }, server: {
                calls += 1
                return .single("Unexpected upload")
            }, isSecretChat: false).start(error: { received = $0 })
            XCTAssertEqual(calls, 0)
            XCTAssertEqual(received, .native(error))
            disposable.dispose()
        }
    }

    func testSecretChatsNeverFallBackToServer() {
        let failures: [(() -> Signal<String, ChatDictationError>)?] = [nil, { .fail(.unavailable) }, { .fail(.failed) }, { .fail(.unsupportedLanguage) }]
        for native in failures {
            var calls = 0
            var received: ChatRecordedAudioTranscriptionError?
            let disposable = transcribeRecordedAudio(native: native, server: {
                calls += 1
                return .single("Unexpected upload")
            }, isSecretChat: true).start(error: { received = $0 })
            XCTAssertEqual(calls, 0)
            XCTAssertNotNil(received)
            disposable.dispose()
        }
    }

    func testServerLimitsAndErrorsArePreservedAfterNativeFallback() {
        for error: AudioFileTranscriptionError in [.premiumRequired, .limitExceeded(60), .tooBig, .invalidAudio, .tooLong, .timedOut, .failed] {
            var received: ChatRecordedAudioTranscriptionError?
            let disposable = transcribeRecordedAudio(native: { .fail(.unavailable) }, server: { .fail(error) }, isSecretChat: false).start(error: { received = $0 })
            XCTAssertEqual(received, .server(error))
            disposable.dispose()
        }
    }

    func testEmptyServerResultIsAnError() {
        for server: Signal<String, AudioFileTranscriptionError> in [.single(" "), .complete()] {
            var received: ChatRecordedAudioTranscriptionError?
            let disposable = transcribeRecordedAudio(native: nil, server: { server }, isSecretChat: false).start(error: { received = $0 })
            XCTAssertEqual(received, .server(.failed))
            disposable.dispose()
        }
    }

    func testNativeAdapterOnlyPublishesFinalTranscript() {
        let engine = RecordedAudioTestEngine()
        var values: [String] = []
        let disposable = nativeRecordedAudioTranscription { $0(.success(engine)) }.start(next: { values.append($0) })
        XCTAssertEqual(engine.startCount, 1)
        engine.onTranscript?("Partial")
        XCTAssertTrue(values.isEmpty)
        engine.onTranscript?("Final native transcript")
        engine.onFinish?(nil)
        XCTAssertEqual(values, ["Final native transcript"])
        XCTAssertEqual(engine.cancelCount, 1)
        disposable.dispose()
    }

    func testNativeAdapterCancelsEngineAndPreventsLateResults() {
        let engine = RecordedAudioTestEngine()
        var values: [String] = []
        let disposable = nativeRecordedAudioTranscription { $0(.success(engine)) }.start(next: { values.append($0) })
        let lateTranscript = engine.onTranscript
        let lateFinish = engine.onFinish
        disposable.dispose()
        lateTranscript?("Stale")
        lateFinish?(nil)
        XCTAssertEqual(engine.cancelCount, 1)
        XCTAssertTrue(values.isEmpty)
    }

    func testNativeAdapterCancelsEnginePreparedAfterCancellation() {
        var prepared: ((Result<ChatDictationEngine, ChatDictationError>) -> Void)?
        let engine = RecordedAudioTestEngine()
        let disposable = nativeRecordedAudioTranscription { prepared = $0 }.start()
        disposable.dispose()
        prepared?(.success(engine))
        XCTAssertEqual(engine.startCount, 0)
        XCTAssertEqual(engine.cancelCount, 1)
    }

    func testNativeAdapterReportsEmptyFinalAsFailure() {
        let engine = RecordedAudioTestEngine()
        var error: ChatDictationError?
        let disposable = nativeRecordedAudioTranscription { $0(.success(engine)) }.start(error: { error = $0 })
        engine.onFinish?(nil)
        XCTAssertEqual(error, .failed)
        disposable.dispose()
    }

    func testSuccessfulDeliveryDisposalIsNotCancellation() {
        let pipe = ValuePipe<String>()
        let done = expectation(description: "final result delivered")
        var cancels = 0
        var disposable: Disposable?
        disposable = deliverRecordedAudioTranscription(pipe.signal() |> castError(ChatRecordedAudioTranscriptionError.self), cancelled: { cancels += 1 }).start(next: { value in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(value, "Ready")
            disposable?.dispose()
            done.fulfill()
        })
        DispatchQueue.global().async {
            pipe.putNext("Ready")
        }
        wait(for: [done], timeout: 3)
        XCTAssertEqual(cancels, 0)
    }

    func testCancellationDisposesNativeWithoutStartingFallback() {
        let engine = RecordedAudioTestEngine()
        var serverCalls = 0
        var cancels = 0
        let signal = transcribeRecordedAudio(native: { nativeRecordedAudioTranscription { $0(.success(engine)) } }, server: {
            serverCalls += 1
            return .single("Unexpected")
        }, isSecretChat: false)
        let disposable = deliverRecordedAudioTranscription(signal, cancelled: { cancels += 1 }).start()
        disposable.dispose()
        disposable.dispose()
        XCTAssertEqual(cancels, 1)
        XCTAssertEqual(engine.cancelCount, 1)
        XCTAssertEqual(serverCalls, 0)
    }

    func testPendingResultDoesNotConsumeFinalResultTimeout() {
        let pipe = ValuePipe<AudioFileTranscription>()
        let done = expectation(description: "pending timeout")
        var error: AudioFileTranscriptionError?
        let disposable = finalRecordedAudioTranscript(pipe.signal() |> castError(AudioFileTranscriptionError.self), timeout: 0.03).start(next: { _ in
            XCTFail("A pending result must not reach the composer")
        }, error: {
            error = $0
            done.fulfill()
        })
        pipe.putNext(.init(id: 1, text: "Partial", isPending: true))
        wait(for: [done], timeout: 3)
        XCTAssertEqual(error, .timedOut)
        disposable.dispose()
    }

    func testOnlyFinalServerTextIsDelivered() {
        let pipe = ValuePipe<AudioFileTranscription>()
        var values: [String] = []
        let disposable = finalRecordedAudioTranscript(pipe.signal() |> castError(AudioFileTranscriptionError.self)).start(next: { values.append($0) })
        pipe.putNext(.init(id: 1, text: "Partial", isPending: true))
        XCTAssertTrue(values.isEmpty)
        pipe.putNext(.init(id: 1, text: "Final", isPending: false))
        XCTAssertEqual(values, ["Final"])
        disposable.dispose()
    }

    func testRecorderAvailabilityDistinguishesOlderCloudAndSecretChats() {
        XCTAssertTrue(ChatRecordedAudioTranscriptionPolicy.canTranscribe(nativeAvailable: false, isSecretChat: false))
        XCTAssertFalse(ChatRecordedAudioTranscriptionPolicy.canTranscribe(nativeAvailable: false, isSecretChat: true))
        XCTAssertFalse(ChatRecordedAudioTranscriptionPolicy.showsRecorderButton(nativeAvailable: false, isPaused: false, isSecretChat: false))
        XCTAssertTrue(ChatRecordedAudioTranscriptionPolicy.showsRecorderButton(nativeAvailable: false, isPaused: true, isSecretChat: false))
        XCTAssertFalse(ChatRecordedAudioTranscriptionPolicy.showsRecorderButton(nativeAvailable: false, isPaused: true, isSecretChat: true))
        XCTAssertTrue(ChatRecordedAudioTranscriptionPolicy.showsRecorderButton(nativeAvailable: true, isPaused: false, isSecretChat: true))
    }
}

private final class RecordedAudioTestEngine: ChatDictationEngine {
    var onTranscript: ((String) -> Void)?
    var onLevel: ((CGFloat) -> Void)?
    var onLanguage: ((String) -> Void)?
    var onFinish: ((ChatDictationError?) -> Void)?
    var startCount = 0
    var cancelCount = 0

    func start() { startCount += 1 }
    func stop() {}
    func cancel() { cancelCount += 1 }
}
