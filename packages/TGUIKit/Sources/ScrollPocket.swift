import Cocoa

public enum ScrollPocketEdge: Int {
    case top = 0
    case bottom = 1

    fileprivate var mask: Int {
        return 1 << rawValue
    }
}

public extension NSScrollView {
    func registerScrollPocketContainer(_ view: NSView, edge: ScrollPocketEdge) {
        allowScrollPocketEdge(edge)
        performPocketSelector("registerPocketContainer:onEdge:", view: view, edge: edge)
    }

    func unregisterScrollPocketContainer(_ view: NSView, edge: ScrollPocketEdge) {
        performPocketSelector("unregisterPocketContainer:onEdge:", view: view, edge: edge)
    }

    private func allowScrollPocketEdge(_ edge: ScrollPocketEdge) {
        let getter = NSSelectorFromString("allowedPocketEdges")
        let setter = NSSelectorFromString("setAllowedPocketEdges:")
        guard responds(to: getter), responds(to: setter) else {
            return
        }
        typealias Getter = @convention(c) (NSObject, Selector) -> Int
        typealias Setter = @convention(c) (NSObject, Selector, Int) -> Void
        let allowed = unsafeBitCast(method(for: getter), to: Getter.self)(self, getter)
        if allowed & edge.mask == 0 {
            unsafeBitCast(method(for: setter), to: Setter.self)(self, setter, allowed | edge.mask)
        }
    }

    private func performPocketSelector(_ name: String, view: NSView, edge: ScrollPocketEdge) {
        let selector = NSSelectorFromString(name)
        guard responds(to: selector) else {
            return
        }
        typealias Function = @convention(c) (NSObject, Selector, NSView, Int) -> Void
        unsafeBitCast(method(for: selector), to: Function.self)(self, selector, view, edge.rawValue)
    }
}

public final class ScrollPocketArea: View {
    public enum Style {
        case hard
        case soft
    }

    private final class HardElement: NSImageView {
        override func hitTest(_ point: NSPoint) -> NSView? {
            return nil
        }
    }

    private final class SoftElement: NSButton {
        override func hitTest(_ point: NSPoint) -> NSView? {
            return nil
        }
    }

    public let style: Style
    private let element: NSView

    public init(frame frameRect: NSRect, style: Style) {
        self.style = style
        switch style {
        case .hard:
            element = HardElement()
        case .soft:
            let button = SoftElement(title: "", target: nil, action: nil)
            button.isTransparent = true
            button.isEnabled = false
            button.refusesFirstResponder = true
            element = button
        }
        super.init(frame: frameRect)
        isEventLess = true
        element.setAccessibilityElement(false)
        element.frame = bounds
        addSubview(element)
        updateTint(presentation)
    }

    public required convenience init(frame frameRect: NSRect) {
        self.init(frame: frameRect, style: .hard)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public static let tintAlpha: CGFloat = 0.35

    private func updateTint(_ theme: PresentationTheme) {
        switch style {
        case .hard:
            backgroundColor = theme.colors.background.withAlphaComponent(ScrollPocketArea.tintAlpha)
        case .soft:
            backgroundColor = .clear
        }
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        updateTint(theme)
    }

    public override func layout() {
        super.layout()
        element.frame = bounds
    }
}

public final class ScrollPocketExcludedView: View {
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEventLess = true
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc func _shouldDescendantsContributeToScrollPocket() -> Bool {
        return false
    }
}
