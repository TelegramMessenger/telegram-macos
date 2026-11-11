import Cocoa
import XCTest

private enum ChatVoiceTranscription {
    static var isSupported = true
}

private enum ShortcutResult { case invoked, rejected }

private enum ChatDictationShortcut {
    case automatic, record, dictate
    static var current = ChatDictationShortcut.automatic
}

private final class ShortcutInteraction {
    struct Input {
        var inputText = ""
        var selection = 0 ..< 0
    }
    struct Presentation {
        enum State { case normal, editing }
        var state = State.normal
        var recordingState: Bool?
        var effectiveInput = Input()
    }
    final class Transcription {
        var isActive = false
        var finishCount = 0
        func perform(_ action: ChatVoiceTranscriptionView.Action) {
            if case .edit = action { finishCount += 1 }
        }
    }
    enum Via { case shortcut }
    var presentation = Presentation()
    var voiceTranscription: Transcription? = Transcription()
    var richTextDraft: Bool?
    var onStart: (() -> Void)?
    var lastVia: Via?
    var held = false
    func startRecordingObserved(_ hold: Bool, _ view: NSView?, via: Via) {
        held = hold
        lastVia = via
        onStart?()
    }
}

private final class ShortcutController {
    let chatInteraction = ShortcutInteraction()
    var pendingDictation = false
    var dictated: [Bool] = []
    init() {
        chatInteraction.onStart = { [weak self] in
            guard let self else { return }
            self.dictated.append(self.pendingDictation)
            self.pendingDictation = false
        }
    }
    __RECORDING_SHORTCUT__
}

final class DictationShortcutTests: XCTestCase {
    override func tearDown() {
        ChatVoiceTranscription.isSupported = true
        ChatDictationShortcut.current = .automatic
        super.tearDown()
    }

    func testDictateSettingDictatesIntoAnEmptyComposerToo() {
        ChatDictationShortcut.current = .dictate
        for text in ["", "Draft"] {
            let controller = ShortcutController()
            controller.chatInteraction.presentation.effectiveInput.inputText = text
            _ = controller.startRecordingShortcut()
            XCTAssertEqual(controller.dictated, [true], text)
        }
    }

    func testRecordSettingRecordsEvenWithADraft() {
        ChatDictationShortcut.current = .record
        let controller = ShortcutController()
        controller.chatInteraction.presentation.effectiveInput.inputText = "Draft"
        _ = controller.startRecordingShortcut()
        XCTAssertEqual(controller.dictated, [false])
    }

    func testDictateSettingRecordsWhereDictationIsUnavailable() {
        ChatDictationShortcut.current = .dictate
        ChatVoiceTranscription.isSupported = false
        let controller = ShortcutController()
        _ = controller.startRecordingShortcut()
        XCTAssertEqual(controller.dictated, [false])
    }

    func testCommandRStillFinishesActiveDictationWithEverySetting() {
        for setting in [ChatDictationShortcut.automatic, .record, .dictate] {
            ChatDictationShortcut.current = setting
            let controller = ShortcutController()
            controller.chatInteraction.presentation.recordingState = true
            controller.chatInteraction.voiceTranscription?.isActive = true
            _ = controller.startRecordingShortcut()
            XCTAssertEqual(controller.chatInteraction.voiceTranscription?.finishCount, 1)
            XCTAssertTrue(controller.dictated.isEmpty)
        }
    }

    func testCommandRDictatesIntoAnExistingDraftWithoutChangingItsSelection() {
        let controller = ShortcutController()
        controller.chatInteraction.presentation.effectiveInput = .init(inputText: "Hello friend", selection: 6 ..< 6)
        XCTAssertEqual(controller.startRecordingShortcut(), .invoked)
        XCTAssertEqual(controller.dictated, [true])
        XCTAssertEqual(controller.chatInteraction.presentation.effectiveInput.inputText, "Hello friend")
        XCTAssertEqual(controller.chatInteraction.presentation.effectiveInput.selection, 6 ..< 6)
        XCTAssertEqual(controller.chatInteraction.lastVia, .shortcut)
        XCTAssertTrue(controller.chatInteraction.held)
    }

    func testEmptyAndWhitespaceDraftsKeepNormalRecording() {
        for text in ["", " \n\t"] {
            let controller = ShortcutController()
            controller.chatInteraction.presentation.effectiveInput.inputText = text
            _ = controller.startRecordingShortcut()
            XCTAssertEqual(controller.dictated, [false])
        }
    }

    func testClearingTheDraftRestoresNormalRecordingOnTheNextShortcut() {
        let controller = ShortcutController()
        controller.chatInteraction.presentation.effectiveInput.inputText = "Draft"
        _ = controller.startRecordingShortcut()
        controller.chatInteraction.presentation.effectiveInput.inputText = ""
        _ = controller.startRecordingShortcut()
        XCTAssertEqual(controller.dictated, [true, false])
    }

    func testUnsupportedDictationKeepsTheExistingRecordingRoute() {
        let controller = ShortcutController()
        controller.chatInteraction.presentation.effectiveInput.inputText = "Draft"
        ChatVoiceTranscription.isSupported = false
        _ = controller.startRecordingShortcut()
        XCTAssertEqual(controller.dictated, [false])
    }

    func testUnavailableOrBusyComposerDoesNotStartAnotherDictation() {
        for scenario in 0 ..< 4 {
            let controller = ShortcutController()
            controller.chatInteraction.presentation.effectiveInput.inputText = "Draft"
            switch scenario {
            case 0: controller.chatInteraction.voiceTranscription = nil
            case 1: controller.chatInteraction.presentation.recordingState = true
            case 2: controller.chatInteraction.presentation.state = .editing
            default: controller.chatInteraction.richTextDraft = true
            }
            _ = controller.startRecordingShortcut()
            XCTAssertEqual(controller.dictated, [false])
        }
    }

    func testCommandRStopsActiveDictationEvenBeforeTextArrives() {
        for text in ["", "Recognized text"] {
            let controller = ShortcutController()
            controller.chatInteraction.presentation.effectiveInput = .init(inputText: text, selection: 0 ..< 0)
            controller.chatInteraction.presentation.recordingState = true
            controller.chatInteraction.voiceTranscription?.isActive = true
            controller.pendingDictation = true
            XCTAssertEqual(controller.startRecordingShortcut(), .invoked)
            XCTAssertEqual(controller.chatInteraction.voiceTranscription?.finishCount, 1)
            XCTAssertTrue(controller.dictated.isEmpty)
            XCTAssertFalse(controller.pendingDictation)
            XCTAssertEqual(controller.chatInteraction.presentation.effectiveInput.inputText, text)
            XCTAssertEqual(controller.chatInteraction.presentation.effectiveInput.selection, 0 ..< 0)
        }
    }

    func testCommandRCanStartDictationAgainAfterItFinishes() {
        let controller = ShortcutController()
        controller.chatInteraction.presentation.effectiveInput.inputText = "Keep this draft"
        _ = controller.startRecordingShortcut()
        controller.chatInteraction.voiceTranscription?.isActive = true
        _ = controller.startRecordingShortcut()
        XCTAssertEqual(controller.dictated, [true])
        XCTAssertEqual(controller.chatInteraction.voiceTranscription?.finishCount, 1)
        controller.chatInteraction.voiceTranscription?.isActive = false
        _ = controller.startRecordingShortcut()
        XCTAssertEqual(controller.dictated, [true, true])
        XCTAssertEqual(controller.chatInteraction.presentation.effectiveInput.inputText, "Keep this draft")
    }
}
