import Cocoa
import TGUIKit
import KeyboardKey

extension Window {
    func setGalleryKeyHandler(_ handler: @escaping (NSEvent) -> KeyHandlerResult, with object: NSObject, for key: KeyboardKey, priority: HandlerPriority = .low, modifierFlags: NSEvent.ModifierFlags? = nil) {
        self.set(handler: { [weak self] event in
            guard let self, !hasModals(self) else {
                return .rejected
            }
            return handler(event)
        }, with: object, for: key, priority: priority, modifierFlags: modifierFlags)
    }
}
