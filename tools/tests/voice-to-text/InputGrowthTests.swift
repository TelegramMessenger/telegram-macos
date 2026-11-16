import Cocoa
import XCTest

struct GrowthTextState {
    func textInputState() -> GrowthTextState { self }
}

final class GrowthTranscription {
    var isActive = true
    var updates = 0
    func composerDidUpdate(_ state: GrowthTextState) { updates += 1 }
}

final class GrowthInteraction {
    var voiceTranscription: GrowthTranscription? = GrowthTranscription()
}

final class GrowthTextInteractions {
    var inputDidUpdate: (GrowthTextState) -> Void = { _ in }
}

final class GrowthInputView {
    let chatInteraction = GrowthInteraction()
    let textInteractions = GrowthTextInteractions()
    var heightRequests: [Bool] = []
    func set(_ state: GrowthTextState) {}
    func inputDidUpdateLayout(animated: Bool) { heightRequests.append(animated) }
    func install() {
        __INPUT_DID_UPDATE__
    }
}

final class InputGrowthTests: XCTestCase {
    func testTheFieldGrowsWithAnimationWhileDictatingAsWhileTyping() {
        let view = GrowthInputView()
        view.install()
        view.textInteractions.inputDidUpdate(GrowthTextState())
        view.chatInteraction.voiceTranscription?.isActive = false
        view.textInteractions.inputDidUpdate(GrowthTextState())
        view.chatInteraction.voiceTranscription = nil
        view.textInteractions.inputDidUpdate(GrowthTextState())
        XCTAssertEqual(view.heightRequests, [true, true, true])
    }
}
