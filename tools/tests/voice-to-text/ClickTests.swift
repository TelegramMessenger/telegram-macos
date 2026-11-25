import Cocoa
import XCTest

private enum RecordingClickResult { case rejected, invokeNext, invoked }
private class InputDataModalController {}
private func findModal(_ type: InputDataModalController.Type) -> InputDataModalController? { nil }
private final class ClickControl {
    var inside = false
    var isMouseOverButton: Bool { inside }
    func mouseInside() -> Bool { inside }
}
private final class RecordingClickHarness {
    var isTranscribing = true
    var isMouseOverChatNavigation = false
    var isMouseOverTranscription = false
    var isPaused = false
    var draggingPreview = false
    var sendCount = 0
    let overlayView = ClickControl()
    let singleTimeControl = ClickControl()
    let pauseControl = ClickControl()
    let transcribeControl = ClickControl()
    let deleteButton = ClickControl()
    let scrubber = ClickControl()
    private func proccessMouseUp() -> RecordingClickResult {
        if overlayView.isMouseOverButton { sendCount += 1 }
        return .invoked
    }
    func click() -> RecordingClickResult {
        __MOUSE_HANDLER__
        return proccessMouseUp(NSEvent())
    }
}
final class RecordingClickTests: XCTestCase {
    func testHiddenFloatingRecorderDoesNotInterceptTheComposerButton() {
        let view = RecordingClickHarness()
        view.overlayView.inside = true
        view.isMouseOverTranscription = true
        XCTAssertEqual(view.click(), .invokeNext)
        XCTAssertEqual(view.sendCount, 0)
    }
    func testComposerStillReceivesEditingClicks() {
        let view = RecordingClickHarness()
        view.isMouseOverTranscription = true
        XCTAssertEqual(view.click(), .invokeNext)
        XCTAssertEqual(view.sendCount, 0)
    }
    func testCancelStillReceivesClicks() {
        let view = RecordingClickHarness()
        view.deleteButton.inside = true
        XCTAssertEqual(view.click(), .invokeNext)
        XCTAssertEqual(view.sendCount, 0)
    }
}
