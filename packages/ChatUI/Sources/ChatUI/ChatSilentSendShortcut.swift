import Cocoa
import KeyboardKey
import TGUIKit

enum ChatSilentSendShortcut {
    static let keyEquivalent = "\r"
    static let modifierFlags: NSEvent.ModifierFlags = [.command, .shift]

    static func matches(_ event: NSEvent) -> Bool {
        return event.type == .keyDown
            && (event.keyCode == KeyboardKey.Return.rawValue || event.keyCode == KeyboardKey.KeypadEnter.rawValue)
            && event.modifierFlags.intersection([.command, .shift, .option, .control]) == modifierFlags
    }

    static func isAvailable(for interaction: ChatInteraction) -> Bool {
        let presentation = interaction.presentation
        guard let peer = presentation.peer else {
            return false
        }
        return peer.id != interaction.interactionContext.account.peerId
            && presentation.state == .normal
            && presentation.slowMode?.hasLocked != true
    }

    static func invoke(in items: [ContextMenuItem]?) {
        items?.first(where: {
            $0.keyEquivalent == keyEquivalent && $0.keyEquivalentModifierMask == modifierFlags && $0.isEnabled && !$0.isHidden
        })?.handler?()
    }
}
