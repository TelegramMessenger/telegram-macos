import AppKit
import TGUIKit

typealias ChatHeaderState = HeaderState
typealias TelegramPresentationTheme = PresentationTheme
var theme: PresentationTheme { .current }
protocol ChatHeaderProtocol {
    func update(with state: ChatHeaderState, animated: Bool)
    func remove(animated: Bool)
    func measure(_ width: CGFloat)
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition)
}

__RESTART_TOPIC__

func runUtilityHeaderChecks() {
    let before = checks
    let interaction = ChatInteraction()
    let state = HeaderState(main: .restartTopic)
    let action = ChatRestartTopic(interaction, state: state, frame: NSMakeRect(0, 0, 320, 40))
    let text = action.subviews.compactMap { $0 as? TextView }.first!
    for title in ["Reopen Topic", "Повторно открыть тему", String(repeating: "Ein sehr langer Themenname ", count: 5)] {
        utilityHeaderTitle = title
        action.update(with: state, animated: false)
        check(action.accessibilityLabel() == title, "reopen topic lost its full accessibility label")
        for width: CGFloat in [320, 480, 800] {
            for height: CGFloat in [36, 40] {
                action.frame = NSMakeRect(0, 0, width, height)
                action.updateLayout(size: action.frame.size, transition: .immediate)
                check(abs(text.frame.midY - height / 2) <= 1, "reopen topic text is vertically off center")
                check(text.frame.minX >= 19 && text.frame.maxX <= width - 19 && text.frame.height < height, "localized reopen topic text overflows its control")
            }
        }
    }
    utilityHeaderTitle = "Reopen Topic"
    action.update(with: state, animated: false)
    check(action.accessibilityPerformPress(), "reopen topic has no accessible action")
    check(interaction.events == ["restart"], "reopen topic bypassed or duplicated the existing callback")
    print("PASS: \(checks - before) production reopen-topic control, localization and callback checks")
}
