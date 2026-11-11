import Cocoa
import XCTest

private final class DictationButtonInteraction {
    struct Presentation { let messageEffect: Bool? = nil }
    final class Transcription {
        var finishCount = 0
        func perform(_ action: ChatVoiceTranscriptionView.Action) { finishCount += 1 }
    }
    let presentation = Presentation()
    let voiceTranscription: Transcription? = Transcription()
    var sendCount = 0
    func sendMessage(_ silent: Bool, _ schedule: Int?, _ effect: Bool?) { sendCount += 1 }
}

private final class DictationButtonHarness {
    let chatInteraction = DictationButtonInteraction()
    var isDictating = false
    __ACTIVATE_SEND__
}

final class DictationWaveformTests: XCTestCase {
    func testWaveformGrowsWithTheMicrophoneAndSettlesInSilence() {
        var waveform = ChatDictationWaveform()
        let size = CGSize(width: 26, height: 22)
        let quiet = waveform.iconPath(size: size).boundingBoxOfPath.height
        for _ in 0 ..< 28 { waveform.update(1) }
        XCTAssertGreaterThan(waveform.iconPath(size: size).boundingBoxOfPath.height, quiet + 10)
        for _ in 0 ..< 50 { waveform.update(0) }
        XCTAssertLessThan(waveform.level, 0.001)
        XCTAssertEqual(waveform.iconPath(size: size).boundingBoxOfPath.height, quiet, accuracy: 0.01)
    }

    func testInvalidAndOutOfRangeMicrophoneLevelsStayFinite() {
        var waveform = ChatDictationWaveform()
        for value: CGFloat in [.nan, .infinity, -.infinity, -10, 10, 0] {
            waveform.update(value)
            XCTAssertTrue(waveform.samples.allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1 })
        }
    }


    func testWaveButtonFinishesDictationWithoutSendingTheMessage() {
        let button = DictationButtonHarness()
        button.isDictating = true
        button.activateSend()
        XCTAssertEqual(button.chatInteraction.voiceTranscription?.finishCount, 1)
        XCTAssertEqual(button.chatInteraction.sendCount, 0)
        button.isDictating = false
        button.activateSend()
        XCTAssertEqual(button.chatInteraction.sendCount, 1)
    }

    func testNativeWaveIconUsesMicrophoneHistoryAndKeepsItsSize() {
        let view = ChatDictationWaveformView(frame: CGRect(x: 7, y: 5, width: 26, height: 22))
        let original = view.frame
        let bars = view.layer!.sublayers!.first as! CAShapeLayer
        let quiet = bars.path!.boundingBoxOfPath.height
        for _ in 0 ..< 20 { view.updateLevel(1) }
        XCTAssertGreaterThan(bars.path!.boundingBoxOfPath.height, quiet + 10)
        XCTAssertEqual(view.frame, original)
        XCTAssertTrue(view.isEventLess)
        view.reset()
        XCTAssertEqual(bars.path!.boundingBoxOfPath.height, quiet)
    }
}
