import AppKit
import TGUIKit

public protocol AccountContextProtocol {}
final class ContextFixture: AccountContextProtocol {}
final class ChatInteraction {
    enum InputContext { case contextRequest(Int, String) }
    struct Presentation { var inputContext: InputContext? }
    let interactionContext = ContextFixture()
    var presentation = Presentation()
    func clearInput() {}
    func clearContextQuery() {}
}
struct ThemeFixture {
    struct Colors {
        let accent = NSColor(calibratedRed: 0.15, green: 0.62, blue: 0.98, alpha: 1)
        let underSelectedColor = NSColor.white
        let grayIcon = NSColor.gray
    }
    struct Icons {
        var chat_input_star: CGImage { NSImage(named: "star_small")!.precomposed(.white) }
        var chat_header_done: CGImage { chat_input_star }
        var send_message_large: CGImage { NSImage(named: "Icon_SendMessage_Large")!.precomposed(.white) }
    }
    let colors = Colors()
    let icons = Icons()
}
let theme = ThemeFixture()
let premiumGradient: [NSColor] = [.blue, .purple]
struct StringsFixture {
    let voiceOverMessageContextSend = "Send"
    let voiceOverCommonCancel = "Cancel"
    let voiceOverCommonLoading = "Loading"
}
func strings() -> StringsFixture { StringsFixture() }
final class InlineProgressView: Control {}
final class PointerWindowFixture: NSWindow {
    var pointer = NSPoint.zero
    override var mouseLocationOutsideOfEventStream: NSPoint { pointer }
}

__STARS_VIEW__

public final class ChatInputSendButton: View {
    __STATE__
    __CONSTANTS__
    let send = ImageButton()
    let voice = ImageButton()
    let stop = ImageButton()
    let slowModeTimeout = TextButton()
    let inlineCancel = ImageButton()
    var sendPaidMessages: StarsSendActionView?
    var inlineProgress: InlineProgressView?
    let chatInteraction = ChatInteraction()
    var state: State = .initial
    var activeView: View
    var first = true
    var fieldTransitions: [(NSView, Bool)] = []

    required public init(frame: NSRect) {
        activeView = voice
        super.init(frame: frame)
        for view in [send, voice, stop, slowModeTimeout, inlineCancel] {
            view.setFrameSize(NSMakeSize(40, 40))
            addSubview(view)
            view.isHidden = view !== voice
        }
        send.set(background: theme.colors.accent, for: .Normal)
        send.layer?.cornerRadius = Self.fieldSize.height / 2
    }
    required public init?(coder: NSCoder) { fatalError() }

    __FIELD_STATE__
    __FIELD_ACTION__
    __DESIRED_SIZE__
    __UPDATE__
    __LAYOUT__

    __FIELD_TRANSITION__
    __PLANE_FLIGHT__
    func animateSendIconChange(from previous: CGImage, frame: NSRect) {}
}

public final class ChatInputActionsView: View {
    static let extraButtonSize: CGFloat = 40
    let entertaiments = ImageButton()
    let extraButtons: [ImageButton] = []
    required public init(frame: NSRect) {
        super.init(frame: frame)
        entertaiments.set(image: NSImage(named: "Icon_Entertainments")!.precomposed(theme.colors.grayIcon), for: .Normal)
        entertaiments.setFrameSize(NSMakeSize(40, 40))
        addSubview(entertaiments)
    }
    required public init?(coder: NSCoder) { fatalError() }
    __ACTIONS_LAYOUT__
}

final class ComposerFixture {
    let sendButton: ChatInputSendButton
    init(_ sendButton: ChatInputSendButton) { self.sendButton = sendButton }

    __SEND_SLOT__

    func frames(width: CGFloat) -> (field: NSRect, send: NSRect, ghost: NSRect) {
        let size = NSMakeSize(width, 60)
        let edge: CGFloat = 12
        let gap: CGFloat = 10
        let containerX: CGFloat = 62
        let inputBarBottom: CGFloat = 10
        let sendSize = sendButton.desiredSize
        let sendWidth = sendSize.width
        let rightX = size.width - edge - sendWidth
        let slot = sendSlot(gap: gap)
        let textFieldFrame = NSMakeRect(containerX, inputBarBottom, size.width - edge - slot.outside - containerX, 40)
        __PLACEMENT__
        return (textFieldFrame, sendFrame, voiceGhostFrame)
    }
}
