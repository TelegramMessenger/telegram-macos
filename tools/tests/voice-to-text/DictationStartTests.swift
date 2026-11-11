import XCTest

private class ChatRecordingState {
    var autohold = true
    var isCancelled = false
    var discarded = false
    func discard(from interaction: Bool) {
        discarded = true
        isCancelled = true
    }
}

private final class ChatRecordingAudioState: ChatRecordingState {
    var startsDictation = true
}

private final class DictationAttachmentHarness {
    enum ChatState {
        case normal
        case recording(ChatRecordingState)
    }
    let recorder: ChatRecordingState = ChatRecordingAudioState()
    let chatInteraction = true
    var canTranscribe = true
    var window: Bool? = nil
    var isDismissing = false
    var isTranscribing = false
    var composerVisible = true
    var timerVisible = false
    var morphPending = false
    var draft = "Hello?"
    var starts = 0
    var held = false

    func hold() { held = true }
    func startTranscribing() {
        guard !isTranscribing else { return }
        starts += 1
        isTranscribing = true
        morphPending = false
        composerVisible = true
        timerVisible = false
    }
    __START_DICTATION__
    func showOverlay() {
        __AUTO_START__
    }
    func attachRecordingPanel() {
        showOverlay()
        window = true
    }
    func completeStateUpdate() {
        let state = ChatState.recording(recorder)
        let animated = true
        let canMorphGlass = true
        __MORPH_POLICY__
        morphPending = morphsGlass
        let dictationPanelToActivate: DictationAttachmentHarness? = self
        __ACTIVATE__
    }
    func finishMorph() {
        if morphPending { composerVisible = false }
    }
    func endTranscribing() {
        __END_DICTATION__
        timerVisible = true
    }
}

final class DictationStartTests: XCTestCase {
    func testDictationStartsAfterPanelAttachmentWithoutARecordingMorphOrTimer() {
        let view = DictationAttachmentHarness()
        view.attachRecordingPanel()
        XCTAssertTrue(view.held)
        XCTAssertEqual(view.starts, 0)
        view.completeStateUpdate()
        XCTAssertEqual(view.starts, 1)
        XCTAssertTrue(view.isTranscribing)
        XCTAssertFalse(view.morphPending)
        XCTAssertFalse(view.timerVisible)
        view.finishMorph()
        XCTAssertTrue(view.composerVisible)
        XCTAssertEqual(view.draft, "Hello?")
    }

    func testDetachingBeforeStartupDoesNotStartDictation() {
        let view = DictationAttachmentHarness()
        view.attachRecordingPanel()
        view.window = nil
        view.completeStateUpdate()
        XCTAssertEqual(view.starts, 0)
    }

    func testCancelledRecordingDoesNotStartDictation() {
        let view = DictationAttachmentHarness()
        view.attachRecordingPanel()
        view.recorder.isCancelled = true
        view.completeStateUpdate()
        XCTAssertEqual(view.starts, 0)
    }

    func testDismissingPanelDoesNotStartDictation() {
        let view = DictationAttachmentHarness()
        view.attachRecordingPanel()
        view.isDismissing = true
        view.completeStateUpdate()
        XCTAssertEqual(view.starts, 0)
    }

    func testNormalVoiceRecordingKeepsItsRecordingPresentation() {
        let view = DictationAttachmentHarness()
        (view.recorder as? ChatRecordingAudioState)?.startsDictation = false
        view.attachRecordingPanel()
        view.completeStateUpdate()
        XCTAssertEqual(view.starts, 0)
        XCTAssertTrue(view.held)
        XCTAssertTrue(view.morphPending)
    }

    func testUnsupportedTranscriptionDoesNotStartDictation() {
        let view = DictationAttachmentHarness()
        view.canTranscribe = false
        view.attachRecordingPanel()
        view.completeStateUpdate()
        XCTAssertEqual(view.starts, 0)
    }

    func testEndingDictationDiscardsAudioWithoutReturningToTheRecordingTimer() {
        let view = DictationAttachmentHarness()
        view.attachRecordingPanel()
        view.completeStateUpdate()
        view.endTranscribing()
        XCTAssertTrue(view.recorder.discarded)
        XCTAssertFalse(view.timerVisible)
        XCTAssertEqual(view.draft, "Hello?")
    }

    func testEndingTranscriptionOfAnExistingVoiceRecordingKeepsTheRecording() {
        let view = DictationAttachmentHarness()
        (view.recorder as? ChatRecordingAudioState)?.startsDictation = false
        view.attachRecordingPanel()
        view.startTranscribing()
        view.endTranscribing()
        XCTAssertFalse(view.recorder.discarded)
        XCTAssertTrue(view.timerVisible)
    }
}
