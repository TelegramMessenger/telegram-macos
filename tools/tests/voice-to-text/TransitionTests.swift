import Cocoa
import QuartzCore
import XCTest

enum ContainedViewLayoutTransition {
    enum Curve { case easeOut }
    case immediate
    case animated(duration: Double, curve: Curve)
    func updateAlpha(view: NSView, alpha: CGFloat) { view.layer?.opacity = Float(alpha) }
}

protocol ChatVoiceTranscriptionHost: AnyObject {}

final class NativeEditor {
    var text = "Hello, what's going on?"
    var selection = 7 ..< 7
}

final class InputView {
    let sendButton = ChatInputSendButton()
    let textView = NativeTextView()
    let editor = NativeEditor()
    var isTranscribing = false
    var exitAnimated = false
    var fieldFrame = NSRect(x: 60, y: 100, width: 480, height: 40)
    func setTranscribing(_ value: Bool, animated: Bool = false) {
        isTranscribing = value
        if !value { exitAnimated = animated }
    }
    func transcriptionFrame(in view: ChatControllerView) -> NSRect { fieldFrame }
}

final class NativeTextView {
    let inputView = NSTextView(frame: .zero)
}

final class ChatVoiceTranscriptionView {
    enum Action {
        case edit
        case cancel
    }
    var frame = NSRect.zero
    var appliedTheme: PresentationTheme?
    func updateLocalizationAndTheme(theme: PresentationTheme) { appliedTheme = theme }
    var removed = false
    var outgoingCompletion: (() -> Void)?
    func animateOut(completion: @escaping () -> Void) { outgoingCompletion = completion }
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {}
    func removeFromSuperview() { removed = true }
}

final class ChatControllerView {
    var chatTheme: PresentationTheme?
    var transcriptionView: ChatVoiceTranscriptionView?
    let inputView = InputView()
    var window: Bool? = true
    func addSubview(_ view: ChatVoiceTranscriptionView, positioned: NSWindow.OrderingMode, relativeTo: InputView) {}
}

__HOST__

final class TranscriptionTransitionTests: XCTestCase {
    func testSwipeOriginReachesTheLiveComposerButton() {
        let host = ChatControllerView()
        let origin = ChatDictationButtonOrigin(screenFrame: CGRect(x: 100, y: 200, width: 60, height: 60), icon: nil)
        host.animateTranscriptionButton(from: origin)
        XCTAssertEqual(host.inputView.sendButton.dictationOrigin?.screenFrame, origin.screenFrame)
    }

    func testListeningUsesTheSelectedChatTheme() {
        let host = ChatControllerView()
        var customTheme = PresentationTheme()
        customTheme.colors.accent = .systemOrange
        customTheme.colors.isDark = true
        host.chatTheme = customTheme
        let glow = ChatVoiceTranscriptionView()
        host.showTranscriptionView(glow)
        XCTAssertEqual(glow.appliedTheme?.colors.accent, customTheme.colors.accent)
        XCTAssertEqual(glow.appliedTheme?.colors.isDark, true)
    }

    func testMicrophoneLevelsReachTheComposerButton() {
        let host = ChatControllerView()
        host.updateTranscriptionLevel(0.75)
        XCTAssertEqual(host.inputView.sendButton.lastDictationLevel, 0.75)
    }

    func testListeningUsesTheSameEditorAndItsExistingFrame() {
        let host = ChatControllerView()
        let editor = host.inputView.editor
        let frame = host.inputView.fieldFrame
        let glow = ChatVoiceTranscriptionView()
        host.showTranscriptionView(glow)
        XCTAssertTrue(host.inputView.editor === editor)
        XCTAssertEqual(glow.frame, frame)
        XCTAssertEqual(host.inputView.fieldFrame, frame)
        XCTAssertTrue(host.inputView.isTranscribing)
    }

    func testStoppingOnlyRemovesTheGlowAndLeavesTheTextAndSelectionInPlace() {
        let host = ChatControllerView()
        let editor = host.inputView.editor
        let frame = host.inputView.fieldFrame
        let glow = ChatVoiceTranscriptionView()
        host.showTranscriptionView(glow)
        host.hideTranscriptionView(animated: true)
        XCTAssertTrue(host.inputView.editor === editor)
        XCTAssertEqual(editor.text, "Hello, what's going on?")
        XCTAssertEqual(editor.selection, 7 ..< 7)
        XCTAssertEqual(host.inputView.fieldFrame, frame)
        XCTAssertEqual(glow.frame, frame)
        XCTAssertFalse(host.inputView.isTranscribing)
        XCTAssertTrue(host.inputView.exitAnimated)
        XCTAssertNotNil(glow.outgoingCompletion)
        glow.outgoingCompletion?()
        XCTAssertTrue(glow.removed)
    }

    func testOldGlowFadeCannotRemoveANewerListeningSession() {
        let host = ChatControllerView()
        let old = ChatVoiceTranscriptionView()
        host.showTranscriptionView(old)
        host.hideTranscriptionView(animated: true)
        let current = ChatVoiceTranscriptionView()
        host.showTranscriptionView(current)
        old.outgoingCompletion?()
        XCTAssertTrue(host.transcriptionView === current)
        XCTAssertTrue(host.inputView.isTranscribing)
        XCTAssertFalse(current.removed)
    }

    func testDismissalWithoutAWindowRemovesTheGlowImmediately() {
        let host = ChatControllerView()
        let glow = ChatVoiceTranscriptionView()
        host.showTranscriptionView(glow)
        host.window = nil
        host.hideTranscriptionView(animated: true)
        XCTAssertTrue(glow.removed)
        XCTAssertNil(glow.outgoingCompletion)
        XCTAssertFalse(host.inputView.exitAnimated)
    }
}
