import Cocoa
import XCTest

struct ChatTextInputState: Equatable {
    private let attributed: NSAttributedString
    var selectionRange: Range<Int>
    var inputText: String { attributed.string }
    var attributes: [String] { [] }
    init(attributedText: NSAttributedString, selectionRange: Range<Int>) {
        self.attributed = attributedText
        self.selectionRange = selectionRange
    }
    func attributedString() -> NSAttributedString { attributed }
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.attributed == rhs.attributed && lhs.selectionRange == rhs.selectionRange
    }
}

enum TextInputAttributes {
    static let customEmoji = NSAttributedString.Key("customEmoji")
    static let textMention = NSAttributedString.Key("textMention")
    static let textUrl = NSAttributedString.Key("textUrl")
}

struct ComposerPresentation {
    let effectiveInput: ChatTextInputState
    func withUpdatedEffectiveInputState(_ input: ChatTextInputState) -> Self { Self(effectiveInput: input) }
}

final class ComposerInteraction {
    var presentation: ComposerPresentation
    var onUpdate: ((ChatTextInputState) -> Void)?
    init(_ input: ChatTextInputState) { presentation = ComposerPresentation(effectiveInput: input) }
    func update(_ transform: (ComposerPresentation) -> ComposerPresentation) {
        presentation = transform(presentation)
        onUpdate?(presentation.effectiveInput)
    }
}

final class ChatDictationEnhancer {
    var inputs: [String] = []
    func inputDidChange(_ input: ChatTextInputState) {
        inputs.append(input.inputText)
    }
}

final class CursorComposerHarness {
    enum Phase { case listening, finished }
    var isActive = true
    var updatingComposer = false
    var text = ""
    var token = 0
    var phase = Phase.listening
    var editedInput: ChatTextInputState?
    var insertion: ChatInputDictationInsertion?
    var sessionStart: Int?
    var enhancer: ChatDictationEnhancer?
    var composerBase: ChatTextInputState?
    var textEffect: ChatDictationTextEffect?
    var engine: ListeningEngine? = ListeningEngine()
    let permissionDisposable = ListeningPermission()
    let chatInteraction: ComposerInteraction?

    init() {
        let input = ChatTextInputState(attributedText: NSAttributedString(string: ""), selectionRange: 0 ..< 0)
        chatInteraction = ComposerInteraction(input)
        insertion = makeInsertion(input)
        chatInteraction?.onUpdate = { [weak self] state in self?.composerDidUpdate(state) }
    }
    func perform(_ action: ChatVoiceTranscriptionView.Action) { isActive = false }
    func recognize(_ transcript: String) {
        text = transcript
        updateComposer()
    }
    func select(_ range: Range<Int>) {
        var input = chatInteraction!.presentation.effectiveInput
        input.selectionRange = range
        composerDidUpdate(input)
        chatInteraction!.presentation = ComposerPresentation(effectiveInput: input)
    }
    func edit(_ text: String, selection: Range<Int>) {
        let input = ChatTextInputState(attributedText: NSAttributedString(string: text), selectionRange: selection)
        composerDidUpdate(input)
        chatInteraction!.presentation = ComposerPresentation(effectiveInput: input)
    }
    var current: ChatTextInputState { chatInteraction!.presentation.effectiveInput }

    __COMPOSER_DID_UPDATE__
    __MAKE_INSERTION__
    __PREPARE_COMPOSER__
    __UPDATE_COMPOSER__
}

final class DictationCursorTests: XCTestCase {
    func testTheEnhanceOfferHearsEveryEditEvenAfterDictationEnds() {
        let composer = CursorComposerHarness()
        let enhancer = ChatDictationEnhancer()
        composer.enhancer = enhancer
        composer.isActive = false
        composer.edit("Hello there", selection: 11 ..< 11)
        XCTAssertEqual(enhancer.inputs, ["Hello there"])
    }

    func testTheSessionStartFollowsTheCaretUntilTheUserEdits() {
        let composer = CursorComposerHarness()
        composer.edit("Hello world", selection: 6 ..< 6)
        composer.prepareComposer()
        XCTAssertEqual(composer.sessionStart, 6)
        composer.recognize("dear")
        XCTAssertEqual(composer.sessionStart, 6)
        composer.edit("Hello dear old world", selection: 14 ..< 14)
        XCTAssertNil(composer.sessionStart)
    }

    func testNewDictationStartsAtTheExistingCaret() {
        let composer = CursorComposerHarness()
        composer.edit("Hello world", selection: 6 ..< 6)
        composer.prepareComposer()
        composer.recognize("dear")
        XCTAssertEqual(composer.current.inputText, "Hello dear world")
        XCTAssertEqual(composer.current.selectionRange, 11 ..< 11)
    }

    func testNewDictationReplacesTheExistingSelection() {
        let composer = CursorComposerHarness()
        composer.edit("Hello old friend", selection: 6 ..< 9)
        composer.prepareComposer()
        composer.recognize("new")
        XCTAssertEqual(composer.current.inputText, "Hello new friend")
        XCTAssertEqual(composer.current.selectionRange, 9 ..< 9)
    }

    func testTypingKeepsListeningAndNewSpeechFollowsTheTypedCaret() {
        let composer = CursorComposerHarness()
        let engine = composer.engine!
        composer.recognize("Hello")
        composer.edit("Hello friend", selection: 12 ..< 12)
        composer.recognize("Hello how are you")
        XCTAssertEqual(composer.current.inputText, "Hello friend how are you")
        XCTAssertEqual(composer.current.selectionRange, 24 ..< 24)
        XCTAssertTrue(composer.isActive)
        XCTAssertEqual(engine.cancelCount, 0)
    }

    func testDeletingTextWhileListeningDoesNotBringItBackWithTheNextResult() {
        let composer = CursorComposerHarness()
        composer.recognize("Hello world")
        composer.edit("Hello", selection: 5 ..< 5)
        composer.recognize("Hello world again")
        XCTAssertEqual(composer.current.inputText, "Hello again")
        XCTAssertTrue(composer.isActive)
    }

    func testDefaultCaretFollowsTheEndOfEachPartialResult() {
        let composer = CursorComposerHarness()
        composer.recognize("Hello")
        XCTAssertEqual(composer.current.selectionRange, 5 ..< 5)
        composer.recognize("Hello world")
        XCTAssertEqual(composer.current.selectionRange, 11 ..< 11)
        XCTAssertTrue(composer.isActive)
    }

    func testMovingTheCaretRedirectsOnlyNewSpeechWithoutStoppingRecognition() {
        let composer = CursorComposerHarness()
        let engine = composer.engine!
        composer.recognize("Hello world")
        composer.select(5 ..< 5)
        composer.recognize("Hello world again")
        XCTAssertEqual(composer.current.inputText, "Hello again world")
        XCTAssertEqual(composer.current.selectionRange, 11 ..< 11)
        composer.recognize("Hello world again today")
        XCTAssertEqual(composer.current.inputText, "Hello again today world")
        XCTAssertEqual(composer.current.selectionRange, 17 ..< 17)
        XCTAssertTrue(composer.isActive)
        XCTAssertEqual(engine.cancelCount, 0)
    }

    func testMovingTheCaretTwiceKeepsPreviouslyInsertedSpeech() {
        let composer = CursorComposerHarness()
        composer.recognize("Hello world")
        composer.select(5 ..< 5)
        composer.recognize("Hello world again")
        composer.select(17 ..< 17)
        composer.recognize("Hello world again today")
        XCTAssertEqual(composer.current.inputText, "Hello again world today")
        XCTAssertEqual(composer.current.selectionRange, 23 ..< 23)
    }

    func testNewSpeechReplacesTheSelectionAndPartialRevisionsStayInThatSpan() {
        let composer = CursorComposerHarness()
        composer.recognize("Hello world")
        composer.select(6 ..< 11)
        composer.recognize("Hello world friend")
        XCTAssertEqual(composer.current.inputText, "Hello friend")
        composer.recognize("Hello world friends")
        XCTAssertEqual(composer.current.inputText, "Hello friends")
    }

    func testSelectingTextDoesNotDeleteItBeforeNewSpeechArrives() {
        let composer = CursorComposerHarness()
        composer.recognize("Hello world")
        composer.select(6 ..< 11)
        composer.recognize("Hello world")
        XCTAssertEqual(composer.current.inputText, "Hello world")
        XCTAssertEqual(composer.current.selectionRange, 6 ..< 11)
    }

    func testRecognizerCorrectionsBeforeTheCursorDoNotRepeatOldSpeech() {
        let composer = CursorComposerHarness()
        composer.recognize("hello world")
        composer.select(0 ..< 0)
        composer.recognize("Hello, world again")
        XCTAssertEqual(composer.current.inputText, "again hello world")
    }

    func testEmojiBeforeTheCaretKeepsUTF16Offsets() {
        let composer = CursorComposerHarness()
        composer.recognize("Hi🙂 world")
        composer.select(4 ..< 4)
        composer.recognize("Hi🙂 world again")
        XCTAssertEqual(composer.current.inputText, "Hi🙂 again world")
        XCTAssertEqual(composer.current.selectionRange, 10 ..< 10)
    }
}

final class CaretTextView {
    let inputView = NSTextView(frame: .zero)
    init() { inputView.string = "Hi🙂" }
}

final class CaretSelectionHarness {
    var isTranscribing = true
    let textView = CaretTextView()
    func apply(_ selection: Range<Int>) { updateTranscriptionSelection(selection) }
    __UPDATE_SELECTION__
}

final class NativeCaretSelectionTests: XCTestCase {
    func testNativeCaretMovesToTheRequestedUTF16OffsetEvenWithoutATextChange() {
        let composer = CaretSelectionHarness()
        composer.textView.inputView.setSelectedRange(NSRange(location: 0, length: 0))
        composer.apply(4 ..< 4)
        XCTAssertEqual(composer.textView.inputView.selectedRange(), NSRange(location: 4, length: 0))
    }

    func testNativeSelectionIsClampedToTheTextAndNormalEditingIsUntouched() {
        let composer = CaretSelectionHarness()
        composer.apply(20 ..< 30)
        XCTAssertEqual(composer.textView.inputView.selectedRange(), NSRange(location: 4, length: 0))
        composer.isTranscribing = false
        composer.apply(0 ..< 0)
        XCTAssertEqual(composer.textView.inputView.selectedRange(), NSRange(location: 4, length: 0))
    }
}
