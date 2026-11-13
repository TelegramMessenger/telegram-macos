import Cocoa
import ColorPalette

open class SidebarMaterialView: View {

    public static let defaultTintAlpha: CGFloat = 0.45

    private let effectView: NSVisualEffectView?
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

    public var cornerRadius: CGFloat = 0 {
        didSet {
            let views: [NSView?] = [effectView, tintView]
            for view in views.compactMap({ $0 }) {
                view.layer?.cornerRadius = cornerRadius
                view.layer?.masksToBounds = cornerRadius > 0
            }
        }
    }

    public init(frame frameRect: NSRect, material: NSVisualEffectView.Material?, blendingMode: NSVisualEffectView.BlendingMode = .withinWindow) {
        if let material {
            let effectView = NSVisualEffectView(frame: frameRect.size.bounds)
            effectView.material = material
            effectView.blendingMode = blendingMode
            effectView.state = .followsWindowActiveState
            effectView.wantsLayer = true
            self.effectView = effectView
        } else {
            self.effectView = nil
        }
        super.init(frame: frameRect)
        backgroundColor = .clear

        tintView.isEventLess = true
        tintView.userInteractionEnabled = false
        tintView.frame = bounds

        if let effectView {
            addSubview(effectView)
        }
        addSubview(tintView)

        applyAppearance(presentation)
    }

    public required convenience init(frame frameRect: NSRect) {
        self.init(frame: frameRect, material: nil)
    }

    public convenience init(frame frameRect: NSRect, tintColor: NSColor) {
        self.init(frame: frameRect)
        self.tintColor = tintColor
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        applyAppearance(theme)
    }

    private func applyAppearance(_ theme: PresentationTheme) {
        effectView?.appearance = theme.appearance
        let usesThemeTint = tintAlpha > 0 && SidebarMaterialView.hasTintedBackground(theme.colors)
        tintView.backgroundColor = usesThemeTint ? tintColor.withAlphaComponent(tintColor.alphaComponent * tintAlpha) : .clear
    }

    private static func hasTintedBackground(_ colors: ColorPalette) -> Bool {
        if colors.tinted {
            return true
        }
        return !colors.background.isEqual(colors.parent.palette.background)
    }

    open override func layout() {
        super.layout()
        effectView?.frame = bounds
        tintView.frame = bounds
    }
}
