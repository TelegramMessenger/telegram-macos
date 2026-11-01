import Cocoa

public final class GlassSegmentView: View {
    public static let height: CGFloat = 40
    private static let itemInset: CGFloat = 12
    private static let itemOverlap: CGFloat = 8
    private static let selectionInset: CGFloat = 3

    private let glass = LiquidGlassView(frame: NSZeroRect, cornerRadius: GlassSegmentView.height / 2, hasShadow: true, hasBorder: true)
    private let selectionView = View()
    private var menuBlur: NSVisualEffectView?
    private let menuVeil = View()
    private let menuShadow = MenuShadowLayer()
    private let menuRim = CALayer()
    private let menuHairline = CALayer()
    private var labels: [TextView] = []
    private var currentTheme: PresentationTheme = presentation
    private var selectionPosition: CGFloat?

    public private(set) var titles: [String] = []
    public private(set) var selectedIndex: Int?
    public var didSelect: ((Int) -> Void)?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.layer?.masksToBounds = false
        if #available(macOS 14.0, *) {
            self.clipsToBounds = false
        }
        self.addSubview(self.glass)
        self.selectionView.isHidden = true
        self.selectionView.layer?.cornerRadius = (GlassSegmentView.height - GlassSegmentView.selectionInset * 2) / 2
        self.addSubview(self.selectionView)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public var usesMenuMaterial: Bool = false {
        didSet {
            if oldValue != usesMenuMaterial {
                refreshMenuMaterial()
            }
        }
    }

    public func refreshMenuMaterial() {
        let fallback = usesMenuMaterial && !(System.liquidGlass && System.liquidGlassAvailable) && System.blurEnabled
        if fallback, menuBlur == nil {
            let blur = NSVisualEffectView(frame: bounds)
            blur.wantsLayer = true
            blur.material = .menu
            blur.blendingMode = .withinWindow
            blur.state = .active
            blur.layer?.cornerRadius = GlassSegmentView.height / 2
            blur.layer?.masksToBounds = true
            addSubview(blur, positioned: .above, relativeTo: glass)
            menuVeil.autoresizingMask = [.width, .height]
            menuVeil.frame = blur.bounds
            blur.addSubview(menuVeil)
            menuBlur = blur
            menuRim.borderWidth = 1
            menuHairline.borderWidth = 0.5
            for layer in [menuRim, menuHairline] {
                layer.cornerRadius = GlassSegmentView.height / 2
                layer.zPosition = 1
                self.layer?.addSublayer(layer)
            }
        } else if !fallback, let blur = menuBlur {
            blur.removeFromSuperview()
            menuBlur = nil
            for layer in [menuRim, menuHairline] {
                layer.removeFromSuperlayer()
            }
        }
        glass.isHidden = menuBlur != nil
        if usesMenuMaterial, menuShadow.superlayer == nil {
            layer?.insertSublayer(menuShadow, at: 0)
        } else if !usesMenuMaterial {
            menuShadow.removeFromSuperlayer()
        }
        applyTheme()
        needsLayout = true
    }

    public var contentSize: NSSize {
        return NSMakeSize(itemFrames.last?.maxX ?? 0, GlassSegmentView.height)
    }

    public func set(titles: [String], selected index: Int?, animated: Bool) {
        if self.titles != titles {
            self.titles = titles
            while labels.count > titles.count {
                labels.removeLast().removeFromSuperview()
            }
            while labels.count < titles.count {
                let label = TextView()
                label.userInteractionEnabled = false
                label.isSelectable = false
                addSubview(label)
                labels.append(label)
            }
            applyTheme()
        }
        self.selectedIndex = index
        self.selectionPosition = index.flatMap { CGFloat($0) }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let animated = animated && !reduceMotion
        if reduceMotion {
            selectionView.layer?.removeAllAnimations()
        }
        updateLayout(size: frame.size, transition: animated ? .animated(duration: 0.4, curve: .spring) : .immediate)
    }

    public func setSelection(position: CGFloat, animated: Bool) {
        let animated = animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !animated {
            selectionView.layer?.removeAllAnimations()
        }
        self.selectionPosition = position
        updateLayout(size: frame.size, transition: animated ? .animated(duration: 0.4, curve: .spring) : .immediate)
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        self.currentTheme = theme
        applyTheme()
        needsLayout = true
    }

    private func applyTheme() {
        let colors = currentTheme.colors
        selectionView.backgroundColor = colors.text.withAlphaComponent(colors.isDark ? 0.1 : 0.075)
        menuBlur?.appearance = NSAppearance(named: colors.isDark ? .darkAqua : .aqua)
        menuVeil.backgroundColor = .menuFallbackVeil(isDark: colors.isDark)
        menuRim.borderColor = NSColor.white.withAlphaComponent(colors.isDark ? 0.1 : 0.5).cgColor
        menuHairline.borderColor = NSColor.black.withAlphaComponent(colors.isDark ? 0.85 : 0.2).cgColor
        for (label, title) in zip(labels, titles) {
            let layout = TextViewLayout(.initialize(string: title, color: colors.text, font: .medium(.title)))
            layout.measure(width: .greatestFiniteMagnitude)
            label.update(layout)
        }
    }

    public var itemFrames: [NSRect] {
        var x: CGFloat = 0
        return labels.map { label in
            let frame = NSMakeRect(x, 0, label.frame.width + GlassSegmentView.itemInset * 2, GlassSegmentView.height)
            x = frame.maxX - GlassSegmentView.itemOverlap
            return frame
        }
    }

    private func selectionFrame(at position: CGFloat, frames: [NSRect]) -> NSRect {
        let clamped = min(max(position, 0), CGFloat(frames.count - 1))
        let lower = Int(clamped.rounded(.down))
        let upper = min(lower + 1, frames.count - 1)
        let progress = clamped - CGFloat(lower)
        let minX = frames[lower].minX + (frames[upper].minX - frames[lower].minX) * progress
        let width = frames[lower].width + (frames[upper].width - frames[lower].width) * progress
        let inset = GlassSegmentView.selectionInset
        return NSMakeRect(minX + inset, inset, max(0, width - inset * 2), GlassSegmentView.height - inset * 2)
    }

    private func position(forCenterX x: CGFloat, frames: [NSRect]) -> CGFloat {
        let centers = frames.map { $0.midX }
        for index in 0 ..< max(centers.count - 1, 0) where x < centers[index + 1] {
            return CGFloat(index) + max(0, x - centers[index]) / (centers[index + 1] - centers[index])
        }
        return CGFloat(max(centers.count - 1, 0))
    }

    private func index(at x: CGFloat, frames: [NSRect]) -> Int? {
        return frames.indices.min(by: { abs(frames[$0].midX - x) < abs(frames[$1].midX - x) })
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        return super.hitTest(point) == nil ? nil : self
    }

    public override var mouseDownCanMoveWindow: Bool {
        return false
    }

    public override func mouseDown(with event: NSEvent) {
        let frames = itemFrames
        let start = convert(event.locationInWindow, from: nil)
        guard let window = self.window, let pressedIndex = index(at: start.x, frames: frames) else {
            return
        }
        var position = CGFloat(pressedIndex)
        var moved = false
        if pressedIndex != selectedIndex {
            setSelection(position: position, animated: true)
        }
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp {
                let index = Int(position.rounded())
                setSelection(position: CGFloat(index), animated: true)
                if !moved || index != selectedIndex {
                    didSelect?(index)
                }
                break
            }
            let point = convert(next.locationInWindow, from: nil)
            moved = moved || abs(point.x - start.x) > 2
            if moved {
                position = self.position(forCenterX: frames[pressedIndex].midX + point.x - start.x, frames: frames)
                setSelection(position: position, animated: false)
            }
        }
    }

    public override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }

    private func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: glass, frame: size.bounds)
        glass.updateLayout(size: size, transition: transition)
        if menuShadow.superlayer != nil {
            menuShadow.update(shape: CGPath(roundedRect: size.bounds, cornerWidth: size.height / 2, cornerHeight: size.height / 2, transform: nil), in: size.bounds)
        }
        if let menuBlur {
            transition.updateFrame(view: menuBlur, frame: size.bounds)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            menuRim.frame = size.bounds
            menuHairline.frame = size.bounds.insetBy(dx: -0.5, dy: -0.5)
            menuHairline.cornerRadius = GlassSegmentView.height / 2 + 0.5
            CATransaction.commit()
        }

        let frames = itemFrames
        for (label, itemFrame) in zip(labels, frames) {
            let labelFrame = NSMakeRect(itemFrame.minX + floorToScreenPixels((itemFrame.width - label.frame.width) / 2), floorToScreenPixels((itemFrame.height - label.frame.height) / 2), label.frame.width, label.frame.height)
            transition.updateFrame(view: label, frame: labelFrame)
        }

        if let position = selectionPosition, !frames.isEmpty {
            let selectionTransition: ContainedViewLayoutTransition = selectionView.isHidden ? .immediate : transition
            selectionView.isHidden = false
            selectionTransition.updateFrame(view: selectionView, frame: selectionFrame(at: position, frames: frames))
        } else {
            selectionView.isHidden = true
        }
    }
}
