import Cocoa
import KeyboardKey

extension NSMenuItem {
    var returnKeyEquivalentText: String? {
        guard keyEquivalent == "\r" || keyEquivalent == "\u{3}" else {
            return nil
        }
        var text = ""
        for (flag, symbol): (NSEvent.ModifierFlags, String) in [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")] {
            if keyEquivalentModifierMask.contains(flag) {
                text += symbol
            }
        }
        return text + (keyEquivalent == "\r" ? "↩" : "⌤")
    }

    func matchesReturnKeyEquivalent(_ event: NSEvent) -> Bool {
        let modifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        return returnKeyEquivalentText != nil
            && event.type == .keyDown
            && (event.keyCode == KeyboardKey.Return.rawValue || event.keyCode == KeyboardKey.KeypadEnter.rawValue)
            && event.modifierFlags.intersection(modifiers) == keyEquivalentModifierMask.intersection(modifiers)
    }
}
