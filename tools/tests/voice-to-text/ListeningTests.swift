import Cocoa
import QuartzCore
import XCTest

enum KeyHandlerResult {
    case invoked
    case rejected
}

enum ChatDictationError: Error {
    case failed
}

final class ListeningEngine {
    var stopCount = 0
    var cancelCount = 0
    func stop() { stopCount += 1 }
    func cancel() { cancelCount += 1 }
}

final class ListeningPermission {
    func set(_ value: Any?) {}
}

final class ListeningJourney {
    var insertedCount = 0
    func cancel() {}
    func draftInserted() { insertedCount += 1 }
}

final class ListeningView {
    func setListening(_ value: Bool, animated: Bool) {}
}

final class ListeningHarness {
    enum Phase {
        case idle
        case preparing
        case listening
        case finishing
        case finished
    }

    var phase: Phase = .listening
    var isActive: Bool { phase != .idle }
    var text = "Hello"
    var pendingAction: ChatVoiceTranscriptionView.Action?
    var engine: ListeningEngine? = ListeningEngine()
    var recordingJourney: ListeningJourney? = ListeningJourney()
    var view: ListeningView? = ListeningView()
    var permissionDisposable = ListeningPermission()
    var token = 1
    var insertedText: String?
    var discarded = false
    var enhanceCancels = 0

    func cancelEnhance() {
        enhanceCancels += 1
    }

    func refresh(animated: Bool) {}
    func fail(_ error: ChatDictationError) { dismiss(animated: false) }
    func restoreComposer() {}
    func discardRecording() {
        discarded = true
        recordingStopped()
    }
    func dismiss(animated: Bool, keepsRecording: Bool = false) {
        engine?.cancel()
        phase = .idle
        text = ""
    }
    func complete(_ action: ChatVoiceTranscriptionView.Action) {
        switch action {
        case .edit:
            insertedText = text
        case .cancel:
            break
        }
        dismiss(animated: true)
    }
    func finish() { engineFinished(nil) }

    __RECORDING_STOPPED__
    __PERFORM__
    __ENGINE_FINISHED__
    __STOP_FOR_NAVIGATION__
}

final class ListeningChatInteraction {
    let voiceTranscription: ListeningHarness?
    init(_ transcription: ListeningHarness?) { voiceTranscription = transcription }
}

final class ListeningEscapeRouter {
    let chatInteraction: ListeningChatInteraction
    init(_ transcription: ListeningHarness?) { chatInteraction = ListeningChatInteraction(transcription) }
    func escape() -> KeyHandlerResult {
        __ESCAPE__
        return .rejected
    }
}

final class ListeningNavigationRouter {
    let chatInteraction: ListeningChatInteraction
    init(_ transcription: ListeningHarness?) { chatInteraction = ListeningChatInteraction(transcription) }
    func switchWindow() { __WINDOW_STOP__ }
    func switchChat() { __CHAT_STOP__ }
    func detach() { __DETACH_STOP__ }
}

final class ListeningLifecycleTests: XCTestCase {
    func testLeavingTheChatWithdrawsTheEnhanceOfferEvenAfterDictationEnded() {
        let harness = ListeningHarness()
        harness.phase = .idle
        harness.stopForNavigation()
        XCTAssertEqual(harness.enhanceCancels, 1)
    }

    func testSwitchingWindowsImmediatelyStopsBothRecordingAndRecognition() {
        let session = ListeningHarness()
        let engine = session.engine!
        let journey = session.recordingJourney!
        ListeningNavigationRouter(session).switchWindow()
        XCTAssertEqual(session.phase, .idle)
        XCTAssertTrue(session.discarded)
        XCTAssertEqual(engine.cancelCount, 1)
        XCTAssertEqual(engine.stopCount, 0)
        XCTAssertEqual(journey.insertedCount, 1)
        XCTAssertNil(session.insertedText)
    }

    func testSwitchingChatsDuringPreparationDoesNotStartOrFinishRecognition() {
        let session = ListeningHarness()
        let engine = session.engine!
        session.phase = .preparing
        let token = session.token
        ListeningNavigationRouter(session).switchChat()
        XCTAssertEqual(session.phase, .idle)
        XCTAssertGreaterThan(session.token, token)
        XCTAssertEqual(engine.cancelCount, 1)
        XCTAssertTrue(session.discarded)
        XCTAssertNil(session.insertedText)
    }

    func testDetachingAndDisappearingOnlyStopTheSessionOnce() {
        let session = ListeningHarness()
        let engine = session.engine!
        let router = ListeningNavigationRouter(session)
        router.detach()
        router.switchChat()
        router.switchWindow()
        XCTAssertEqual(engine.cancelCount, 1)
        XCTAssertEqual(session.phase, .idle)
    }

    func testEscapeStopsRecognitionAndInsertsFinalTranscript() {
        let session = ListeningHarness()
        let engine = session.engine!
        XCTAssertEqual(ListeningEscapeRouter(session).escape(), .invoked)
        XCTAssertEqual(session.phase, .finishing)
        XCTAssertEqual(session.text, "Hello")
        XCTAssertEqual(engine.stopCount, 1)
        XCTAssertEqual(engine.cancelCount, 0)
        session.text = "Hello, how are you?"
        session.finish()
        XCTAssertEqual(session.insertedText, "Hello, how are you?")
        XCTAssertEqual(session.phase, .idle)
    }

    func testEscapeDuringPreparationKeepsText() {
        let session = ListeningHarness()
        session.phase = .preparing
        XCTAssertEqual(ListeningEscapeRouter(session).escape(), .invoked)
        XCTAssertEqual(session.insertedText, "Hello")
        XCTAssertEqual(session.phase, .idle)
    }

    func testRepeatedEscapeWhileFinishingDoesNotStopTwice() {
        let session = ListeningHarness()
        let engine = session.engine!
        let router = ListeningEscapeRouter(session)
        XCTAssertEqual(router.escape(), .invoked)
        XCTAssertEqual(router.escape(), .invoked)
        XCTAssertEqual(engine.stopCount, 1)
        session.finish()
        XCTAssertEqual(session.insertedText, "Hello")
    }

    func testDiscardDoesNotWaitForAnotherRecognitionResult() {
        let session = ListeningHarness()
        let engine = session.engine!
        session.perform(.cancel)
        XCTAssertTrue(session.discarded)
        XCTAssertNil(session.insertedText)
        XCTAssertEqual(engine.stopCount, 0)
        XCTAssertEqual(engine.cancelCount, 1)
        XCTAssertEqual(session.phase, .idle)
    }

    func testStoppingAnIdleSessionDoesNotHideTheComposer() {
        let session = ListeningHarness()
        session.phase = .idle
        session.recordingStopped()
        XCTAssertEqual(session.phase, .idle)
        XCTAssertFalse(session.discarded)
    }
}
