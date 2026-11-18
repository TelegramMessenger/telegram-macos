import Cocoa

final class CalendarSearchDayAccessibilityElement: NSAccessibilityElement {
    let date: Date
    weak var view: NSView?
    var frameInView: NSRect = .zero
    var press: (() -> Bool)?
    var focus: (() -> Void)?
    var isFocused: (() -> Bool)?

    init(date: Date, label: String, view: NSView) {
        self.date = date
        self.view = view
        super.init()
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(label)
    }

    override func accessibilityParent() -> Any? {
        return view
    }

    override func accessibilityFrame() -> NSRect {
        guard let view, view.window != nil else {
            return .zero
        }
        return NSAccessibility.screenRect(fromView: view, rect: frameInView)
    }

    override func accessibilityValue() -> Any? {
        return NSNumber(value: isAccessibilitySelected())
    }

    override func accessibilityPerformPress() -> Bool {
        guard view != nil, isAccessibilityEnabled() else {
            return false
        }
        return press?() ?? false
    }

    override func isAccessibilityFocused() -> Bool {
        return isFocused?() ?? false
    }

    override func setAccessibilityFocused(_ accessibilityFocused: Bool) {
        if accessibilityFocused {
            focus?()
        }
        super.setAccessibilityFocused(accessibilityFocused)
    }
}
