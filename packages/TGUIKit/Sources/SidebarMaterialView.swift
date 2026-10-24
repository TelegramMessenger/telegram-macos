import Cocoa
import ColorPalette

open class SidebarMaterialView: View {

    public static let defaultTintAlpha: CGFloat = 0.45

    private static let sidebarGlassVariant = 17
    private static let sidebarAdaptiveAppearance = 1

    private let effectView: NSView
    private let tintView = View()

    public var tintColor: NSColor = presentation.colors.background {
        didSet {
            applyAppearance(presentation)
        }
    }

    public var tintAlpha: CGFloat = SidebarMaterialView.defaultTintAlpha {
        didSet {
            applyAppearance(presentation)
        }
    }

    public required init(frame frameRect: NSRect) {
        self.effectView = SidebarMaterialView.makeEffectView(frame: frameRect.size.bounds)
        super.init(frame: frameRect)
        backgroundColor = .clear

        tintView.isEventLess = true
        tintView.userInteractionEnabled = false
        tintView.frame = bounds

        addSubview(effectView)
        addSubview(tintView)

        applyAppearance(presentation)
    }

    public convenience init(frame frameRect: NSRect, tintColor: NSColor) {
        self.init(frame: frameRect)
        self.tintColor = tintColor
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func makeEffectView(frame: NSRect) -> NSView {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.style = .regular
            glass.cornerRadius = 0
            setPrivateInteger(glass, "set_variant:", sidebarGlassVariant)
            setPrivateInteger(glass, "set_adaptiveAppearance:", sidebarAdaptiveAppearance)
            return glass
        }
        let visual = NSVisualEffectView(frame: frame)
        visual.material = .sidebar
        visual.blendingMode = .behindWindow
        visual.state = .followsWindowActiveState
        return visual
    }

    private static func setPrivateInteger(_ view: NSView, _ selectorName: String, _ value: Int) {
        let selector = NSSelectorFromString(selectorName)
        guard view.responds(to: selector) else {
            return
        }
        typealias Setter = @convention(c) (NSObject, Selector, Int) -> Void
        unsafeBitCast(view.method(for: selector), to: Setter.self)(view, selector, value)
    }

    open override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        applyAppearance(theme)
    }

    private func applyAppearance(_ theme: PresentationTheme) {
        effectView.appearance = theme.appearance
        effectView.isHidden = !System.blurEnabled
        let usesThemeTint = tintAlpha > 0 && SidebarMaterialView.hasTintedBackground(theme.colors)
        let tint = usesThemeTint ? tintColor.withAlphaComponent(tintColor.alphaComponent * tintAlpha) : nil
        if #available(macOS 26.0, *), let glass = effectView as? NSGlassEffectView {
            glass.tintColor = tint
            tintView.backgroundColor = System.blurEnabled ? .clear : tintColor
        } else {
            tintView.backgroundColor = System.blurEnabled ? (tint ?? .clear) : tintColor
        }
    }

    private static func hasTintedBackground(_ colors: ColorPalette) -> Bool {
        if colors.tinted {
            return true
        }
        return !colors.background.isEqual(colors.parent.palette.background)
    }

    open override func layout() {
        super.layout()
        effectView.frame = bounds
        tintView.frame = bounds
    }
}
