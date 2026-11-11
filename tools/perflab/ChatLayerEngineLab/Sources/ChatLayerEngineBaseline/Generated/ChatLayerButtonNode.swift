import Cocoa
import TGUIKit

final class ChatLayerButtonNode: ChatLayerNode {
    private var pressed = false
    private var inside = false
    var action: (() -> Void)?
    var onStateChanged: ((_ highlighted: Bool, _ hovered: Bool, _ focused: Bool) -> Void)?

    init(id: AnyHashable, label: String, action: @escaping () -> Void) {
        super.init(id: id)
        self.action = action
        acceptsPointerEvents = true
        acceptsKeyboardFocus = true
        cursor = .pointingHand
        accessibilityRole = .button
        accessibilityLabel = label
        onPointer = { [weak self] event in self?.handle(event) ?? false }
        onKeyDown = { [weak self] event in
            guard let self, event.keyCode == 49 || event.keyCode == 36 else { return false }
            if !event.isARepeat { self.action?() }
            return true
        }
        onFocusChanged = { [weak self] _ in self?.updateState() }
        onAccessibilityPress = { [weak self] in
            guard let self else { return false }
            self.action?()
            return true
        }
    }

    private func updateState() {
        onStateChanged?(pressed && inside, inside, scene?.focusedNode === self)
    }

    func resetInteraction() {
        pressed = false
        updateState()
    }

    private func handle(_ event: ChatLayerPointerEvent) -> Bool {
        switch event.kind {
        case .entered: inside = true
        case .exited: inside = false
        case .moved: return false
        case .down:
            guard event.button == 0, !event.modifiers.contains(.control) else { return false }
            pressed = true
        case .dragged:
            guard pressed else { return false }
            inside = scene?.hitNode(at: event.sceneLocation) === self
        case .cancelled: pressed = false
        case .up:
            guard pressed, event.button == 0 else { return false }
            pressed = false
            let activate = inside && scene?.hitNode(at: event.sceneLocation) === self
            updateState()
            if activate { action?() }
            return true
        }
        updateState()
        return true
    }
}
