import Cocoa
import XCTest

final class ChatInputSendButton {
    struct State {
        let isInField: Bool
        static let initial = State(isInField: false)
    }
    static let fieldInset: CGFloat = 4
    static let fieldSize = NSMakeSize(40, 32)
    static let fieldTextGap: CGFloat = 6
    static let fieldMotionDuration: Double = 0.22
    var isInField = false
    var desiredSize = NSMakeSize(40, 40)
    var hasAppliedState = true
    var lastAnimated = false
    var appearanceCount = 0
    var dictationOrigin: ChatDictationButtonOrigin?
    func animateDictationTransition(from origin: ChatDictationButtonOrigin) { dictationOrigin = origin }
    var lastDictationLevel: CGFloat = 0
    func updateDictationLevel(_ level: CGFloat) { lastDictationLevel = level }
    var lastDictationAnimated = false
    func setDictating(_ value: Bool, animated: Bool = false) {
        lastDictationAnimated = animated
        if value { _ = update(state: State(isInField: true), animated: false) }
    }
    func update(state: State, animated: Bool) -> Bool {
        if state.isInField, !isInField, animated { appearanceCount += 1 }
        isInField = state.isInField
        lastAnimated = animated
        return false
    }
}

final class ListeningWidthHarness {
    let sendButton = ChatInputSendButton()
    var isTranscribing = false
    var springsFieldMerge = false
    var layoutCount = 0
    var lastLayoutAnimated = false
    var lastLayoutSpringsField = false
    __IS_SEND_IN_FIELD__
    __SEND_SLOT__

    func fieldWidth(windowWidth: CGFloat) -> CGFloat {
        return windowWidth - 12 - 62 - sendSlot(gap: 10).outside
    }
    func updateLayout(transition: ContainedViewLayoutTransition) {
        layoutCount += 1
        if case .animated = transition { lastLayoutAnimated = true } else { lastLayoutAnimated = false }
        lastLayoutSpringsField = springsFieldMerge
    }
}

final class ListeningGhost {
    let layer: CALayer? = CALayer()
    let appearanceContainer = NSView()
    let effectView = NSView()
}

typealias ChatInputView = ListeningWidthViewHarness

final class ListeningWidthViewHarness {
    enum ChatState { case normal }
    struct Presentation {
        let state = ChatState.normal
        var sendState = ChatInputSendButton.State.initial
    }
    final class Interaction {
        var presentation = Presentation()
        let richTextDraft: Bool? = nil
    }
    let chatInteraction = Interaction()
    let container = ListeningWidthHarness()
    var sendButton: ChatInputSendButton { container.sendButton }
    var isTranscribing = false
    var window: Bool? = true
    var dictationHeight = ChatDictationHeightHold()
    let canStopIncomingStreamingMessage = false
    let attachGhost: ListeningGhost? = nil
    let textGhost: ListeningGhost? = nil
    let voiceGhost: ListeningGhost? = nil
    let botMenuGhost: ListeningGhost? = nil
    let keyboardGhost: ListeningGhost? = nil
    var chatState: ChatState { chatInteraction.presentation.state }
    func finishGlassMorph() {}
    func needUpdateChatState(with state: ChatState, _ animated: Bool) {}
    func updateInput(_ state: Presentation, prevState: Presentation, animated: Bool) {}
    var heightRequests: [(animated: Bool, held: CGFloat)] = []
    func inputDidUpdateLayout(animated: Bool) {
        heightRequests.append((animated, dictationHeight.floor))
        container.updateLayout(transition: .immediate)
    }
    static func sendButtonState(from state: Presentation, hasRichDraft: Bool, canStopIncomingStreamingMessage: Bool) -> ChatInputSendButton.State { state.sendState }
    func applyTextPresence(_ hasText: Bool) {
        chatInteraction.presentation.sendState = ChatInputSendButton.State(isInField: hasText)
        updateSendButton(chatInteraction.presentation.sendState, animated: true)
    }
    __UPDATE_SEND_BUTTON__
    __SET_TRANSCRIBING__
}

final class ListeningWidthTests: XCTestCase {
    func testTextUpdatesDuringListeningDoNotStartSendOrFieldAnimations() {
        let view = ListeningWidthViewHarness()
        view.setTranscribing(true)
        let layoutCount = view.container.layoutCount
        view.applyTextPresence(true)
        XCTAssertFalse(view.sendButton.lastAnimated)
        XCTAssertTrue(view.sendButton.isInField)
        XCTAssertEqual(view.container.layoutCount, layoutCount)
        view.applyTextPresence(false)
        XCTAssertFalse(view.sendButton.lastAnimated)
        XCTAssertEqual(view.container.layoutCount, layoutCount)
    }

    func testFinishingKeepsTheButtonAndFieldInPlace() {
        let view = ListeningWidthViewHarness()
        view.setTranscribing(true)
        view.applyTextPresence(true)
        view.setTranscribing(false, animated: true)
        XCTAssertEqual(view.sendButton.appearanceCount, 0)
        XCTAssertTrue(view.sendButton.lastDictationAnimated)
        XCTAssertTrue(view.container.isSendButtonInField)
        XCTAssertFalse(view.container.lastLayoutAnimated)
        XCTAssertFalse(view.container.lastLayoutSpringsField)
    }

    func testExistingDraftKeepsItsSendButtonWhenListeningEnds() {
        let view = ListeningWidthViewHarness()
        view.applyTextPresence(true)
        let appearanceCount = view.sendButton.appearanceCount
        view.setTranscribing(true)
        XCTAssertTrue(view.sendButton.isInField)
        view.setTranscribing(false, animated: true)
        XCTAssertEqual(view.sendButton.appearanceCount, appearanceCount)
        XCTAssertFalse(view.container.lastLayoutAnimated)
    }

    func testNavigationExitRestoresSendWithoutPlayingAnEntrance() {
        let view = ListeningWidthViewHarness()
        view.setTranscribing(true)
        view.applyTextPresence(true)
        view.setTranscribing(false, animated: false)
        XCTAssertTrue(view.container.isSendButtonInField)
        XCTAssertFalse(view.sendButton.lastDictationAnimated)
        XCTAssertEqual(view.sendButton.appearanceCount, 0)
        XCTAssertFalse(view.container.lastLayoutAnimated)
    }

    func testCancellingWithoutADraftDoesNotShowASendButton() {
        let view = ListeningWidthViewHarness()
        view.setTranscribing(true)
        view.setTranscribing(false, animated: true)
        XCTAssertFalse(view.container.isSendButtonInField)
        XCTAssertEqual(view.sendButton.appearanceCount, 0)
    }

    func testNormalTextUpdatesStillRelayoutForTheSendButton() {
        let view = ListeningWidthViewHarness()
        view.applyTextPresence(true)
        XCTAssertTrue(view.sendButton.lastAnimated)
        XCTAssertEqual(view.container.layoutCount, 1)
    }

    func testListeningStartsWithAFreshHeightHoldAndDropsItAtOnceWhenItEnds() {
        let view = ListeningWidthViewHarness()
        _ = view.dictationHeight.fit(60, transcribing: true)
        view.setTranscribing(true)
        XCTAssertEqual(view.dictationHeight.floor, 0)
        _ = view.dictationHeight.fit(60, transcribing: true)
        view.setTranscribing(false)
        XCTAssertEqual(view.dictationHeight.floor, 0)
        let layouts = view.container.layoutCount
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        XCTAssertEqual(view.container.layoutCount, layouts)
    }

    func testEndingDictationKeepsTheHeldHeightThroughTheSwitchThenEasesToTheText() {
        let view = ListeningWidthViewHarness()
        view.setTranscribing(true, animated: true)
        XCTAssertEqual(view.heightRequests.map { $0.animated }, [false])
        _ = view.dictationHeight.fit(54, transcribing: true)
        view.heightRequests.removeAll()
        view.setTranscribing(false, animated: true)
        XCTAssertEqual(view.heightRequests.map { $0.animated }, [false, true])
        XCTAssertEqual(view.heightRequests.first?.held, 54)
        XCTAssertEqual(view.heightRequests.last?.held, 0)
    }

    func testListeningKeepsTheSameFieldWidthWhenTextAppearsOrIsCleared() {
        let layout = ListeningWidthHarness()
        layout.isTranscribing = true
        layout.sendButton.setDictating(true)
        let emptyWidth = layout.fieldWidth(windowWidth: 800)
        layout.sendButton.isInField = true
        XCTAssertEqual(layout.fieldWidth(windowWidth: 800), emptyWidth)
        XCTAssertTrue(layout.isSendButtonInField)
        XCTAssertEqual(layout.fieldWidth(windowWidth: 800), emptyWidth)
    }

    func testListeningStillFollowsWindowResizing() {
        let layout = ListeningWidthHarness()
        layout.isTranscribing = true
        let width = layout.fieldWidth(windowWidth: 800)
        XCTAssertEqual(layout.fieldWidth(windowWidth: 1000), width + 200)
    }

    func testNormalSendLayoutReturnsAfterListeningStops() {
        let layout = ListeningWidthHarness()
        layout.isTranscribing = true
        layout.sendButton.isInField = true
        let width = layout.fieldWidth(windowWidth: 800)
        layout.isTranscribing = false
        XCTAssertTrue(layout.isSendButtonInField)
        XCTAssertEqual(layout.fieldWidth(windowWidth: 800), width)
    }
}
