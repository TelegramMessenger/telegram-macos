import Foundation
import Cocoa
import TGUIKit
import ColorPalette
import Localization

func qrStudioSheetPalette(isDark: Bool) -> ColorPalette {
    return isDark ? darkPalette : dayClassicPalette
}

private final class QrStudioSheetClipView: View {
    let contentView = View()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.layer?.masksToBounds = true
        self.contentView.layer?.masksToBounds = true
        self.addSubview(self.contentView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(size: CGSize, top: CGFloat, bottom: CGFloat) {
        self.layer?.cornerRadius = bottom
        self.layer?.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        let bounds = CGRect(origin: CGPoint(), size: size)
        if self.contentView.frame != bounds {
            self.contentView.frame = bounds
        }
        self.contentView.layer?.cornerRadius = top
        self.contentView.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
    }
}

private final class QrStudioSheetIconButton: Control {
    let kind: QrStudioLook.Kind
    let iconView = ImageView(frame: .zero)

    init(kind: QrStudioLook.Kind) {
        self.kind = kind
        super.init(frame: .zero)
        self.scaleOnClick = true
        self.iconView.isEventLess = true
        self.iconView.isAccessibilityDecorative = true
        self.iconView.contentGravity = .center
        self.addSubview(self.iconView)
        switch kind {
        case .color:
            self.setAccessibilityLabel(strings().voiceOverCommonColor)
        case .emoji:
            self.setAccessibilityLabel(strings().voiceOverCommonEmoji)
        case .gift:
            self.setAccessibilityLabel(strings().voiceOverCommonGift)
        }
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class QrStudioSheetView: View {
    let motion = QrStudioSheetMotion()
    private(set) var geometry: QrStudioSheetGeometry?

    var requestOpenTab: ((QrStudioLook.Kind) -> Void)?
    var progressUpdated: (() -> Void)?

    private let capsuleGlass: LiquidGlassView
    private let iconsContainer = View()
    private var capsuleButtons: [QrStudioLook.Kind: QrStudioSheetIconButton] = [:]
    private var kinds: [QrStudioLook.Kind] = []

    private let clipView = QrStudioSheetClipView(frame: .zero)
    private let panelGlass: LiquidGlassView
    private let contentContainer = View()
    private let headerView = View()
    private let headerPill = View()
    private var headerButtons: [QrStudioLook.Kind: QrStudioSheetIconButton] = [:]

    private var contents: [QrStudioLook.Kind: NSView] = [:]
    private var fadingKinds: [QrStudioLook.Kind: Int] = [:]
    private var fadeToken = 0
    private(set) var currentTab: QrStudioLook.Kind?

    private struct Layout {
        var frame: CGRect
        var top: CGFloat
        var bottom: CGFloat
        var glassAlpha: CGFloat
        var iconsAlpha: CGFloat
        var backgroundAlpha: CGFloat
        var contentAlpha: CGFloat
        var zoom: CGFloat
    }

    private var link: SharedDisplayLinkDriver.Link?
    private var lastTick: Double = 0.0
    private var controlAppearance: QrStudioGlassAppearance?
    private var panelIsDark = false
    private var appliedPanelIsDark: Bool?
    private var isContentInteractive = false

    private var dragStartY: CGFloat?
    private var dragAnchor: CGFloat = 0.0
    private var isDragging = false
    private var lastDragY: CGFloat = 0.0
    private var lastDragTime: Double = 0.0
    private var dragVelocity: CGFloat = 0.0

    static let iconSide: CGFloat = 30.0
    static let iconSpacing: CGFloat = 24.0
    static let iconInset: CGFloat = 7.0
    static let headerHeight: CGFloat = 44.0
    private static let pillInset: CGFloat = 7.0
    private static let pillHeight: CGFloat = 32.0

    static func capsuleWidth(count: Int) -> CGFloat {
        let count = CGFloat(max(1, count))
        return self.iconInset * 2.0 + self.iconSide * count + self.iconSpacing * (count - 1.0)
    }

    required init(frame frameRect: NSRect) {
        self.capsuleGlass = LiquidGlassView(frame: .zero, cornerRadius: 22.0, hasShadow: true, hasBorder: true, forceAppearance: .forceLight)
        self.panelGlass = LiquidGlassView(frame: .zero, cornerRadius: 0.0, hasShadow: false, hasBorder: false, tintAlpha: 0.0, forceAppearance: .forceDark, customTint: nil, forceBlur: true)
        super.init(frame: frameRect)

        self.addSubview(self.capsuleGlass)
        self.addSubview(self.iconsContainer)

        self.addSubview(self.clipView)
        self.clipView.contentView.addSubview(self.panelGlass)
        self.clipView.contentView.addSubview(self.contentContainer)
        self.contentContainer.addSubview(self.headerView)
        self.headerPill.isEventLess = true
        self.headerPill.layer?.cornerRadius = QrStudioSheetView.pillHeight * 0.5
        self.headerView.addSubview(self.headerPill)
        self.clipView.isHidden = true
        self.capsuleGlass.isHidden = true
        self.iconsContainer.isHidden = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        self.link?.invalidate()
    }

    var isOpen: Bool {
        return self.motion.isOpen
    }

    var openness: CGFloat {
        guard let geometry = self.geometry else {
            return 0.0
        }
        return self.motion.openness(travel: geometry.sheet.height)
    }

    var sheetSize: CGSize {
        guard let geometry = self.geometry else {
            return CGSize()
        }
        return CGSize(width: geometry.sheet.width, height: max(0.0, geometry.sheet.height - QrStudioSheetView.headerHeight))
    }

    private var contentFrame: CGRect {
        return CGRect(origin: CGPoint(x: 0.0, y: QrStudioSheetView.headerHeight), size: self.sheetSize)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let geometry = self.geometry, !self.isHidden else {
            return nil
        }
        let local = self.convert(point, from: self.superview)
        let sample = self.motion.sample
        let frame = self.frame(geometry: geometry, sample: sample)
        guard frame.contains(local) else {
            return nil
        }
        if !self.motion.isOpen {
            if sample.rise < 0.001, let result = super.hitTest(point), result !== self, result.isDescendant(of: self.iconsContainer) {
                return result
            }
            return self
        }
        if self.isContentInteractive, let result = super.hitTest(point), result !== self {
            return result
        }
        return self
    }

    func update(size: CGSize, safeBottom: CGFloat, bottomCornerRadius: CGFloat, kinds: [QrStudioLook.Kind], appearance: QrStudioGlassAppearance, panelIsDark: Bool, transition: ContainedViewLayoutTransition) {
        let geometry = QrStudioSheetGeometry(screen: size, safeBottom: safeBottom, capsuleWidth: QrStudioSheetView.capsuleWidth(count: kinds.count), bottomCornerRadius: bottomCornerRadius)
        let geometryChanged = self.geometry != geometry
        self.geometry = geometry

        let kindsChanged = self.kinds != kinds
        if kindsChanged {
            self.kinds = kinds
            self.rebuildButtons()
        }

        let appearanceChanged = self.controlAppearance != appearance || self.appliedPanelIsDark != panelIsDark
        let animateAppearance = transition.isAnimated && self.controlAppearance != nil
        self.controlAppearance = appearance
        self.panelIsDark = panelIsDark
        self.appliedPanelIsDark = panelIsDark
        if appearanceChanged || kindsChanged {
            self.applyAppearance(animated: appearanceChanged && animateAppearance)
        }

        if geometryChanged || kindsChanged {
            self.layoutStatic(geometry: geometry)
            self.updateHeader(transition: .immediate)
        }

        if self.link == nil {
            self.applyCurrent()
        }
    }

    private static func iconName(_ kind: QrStudioLook.Kind) -> String {
        switch kind {
        case .color:
            return "qr_studio_tab_color"
        case .emoji:
            return "qr_studio_tab_emoji"
        case .gift:
            return "qr_studio_tab_gift"
        }
    }

    private static func iconImage(_ kind: QrStudioLook.Kind, color: NSColor) -> CGImage? {
        guard let image = NSImage(named: QrStudioSheetView.iconName(kind)) else {
            return nil
        }
        return image.precomposed(color)
    }

    private func rebuildButtons() {
        for (_, button) in self.capsuleButtons {
            button.removeFromSuperview()
        }
        for (_, button) in self.headerButtons {
            button.removeFromSuperview()
        }
        self.capsuleButtons.removeAll()
        self.headerButtons.removeAll()
        for kind in self.kinds {
            let capsuleButton = QrStudioSheetIconButton(kind: kind)
            capsuleButton.set(handler: { [weak self] _ in
                self?.capsuleTapped(kind)
            }, for: .Click)
            self.iconsContainer.addSubview(capsuleButton)
            self.capsuleButtons[kind] = capsuleButton

            let headerButton = QrStudioSheetIconButton(kind: kind)
            headerButton.set(handler: { [weak self] _ in
                self?.headerTapped(kind)
            }, for: .Click)
            self.headerView.addSubview(headerButton)
            self.headerButtons[kind] = headerButton
        }
    }

    private func capsuleTapped(_ kind: QrStudioLook.Kind) {
        guard !self.motion.isOpen else {
            return
        }
        self.requestOpenTab?(kind)
    }

    private func headerTapped(_ kind: QrStudioLook.Kind) {
        guard self.motion.isOpen, kind != self.currentTab else {
            return
        }
        self.requestOpenTab?(kind)
    }

    static func addAppearanceFade(_ layer: CALayer?) {
        guard let layer else {
            return
        }
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.4
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(fade, forKey: "qrStudioAppearance")
    }

    private func applyAppearance(animated: Bool) {
        let palette = qrStudioSheetPalette(isDark: self.panelIsDark)
        if let controlAppearance = self.controlAppearance, self.capsuleGlass.customTint != controlAppearance.tintColor {
            if animated {
                QrStudioSheetView.addAppearanceFade(self.capsuleGlass.layer)
            }
            self.capsuleGlass.setCustomTint(controlAppearance.tintColor, animated: false)
        }
        let panelAppearance: LiquidGlassAppearance = self.panelIsDark ? .forceDark : .forceLight
        if self.panelGlass.forceAppearance != panelAppearance {
            if animated {
                QrStudioSheetView.addAppearanceFade(self.panelGlass.layer)
                QrStudioSheetView.addAppearanceFade(self.headerView.layer)
            }
            self.panelGlass.forceAppearance = panelAppearance
            self.panelGlass.updateLocalizationAndTheme(theme: presentation)
        }
        self.panelGlass.setCustomTint(palette.background.withAlphaComponent(0.72), animated: false)
        self.headerPill.backgroundColor = palette.text.withAlphaComponent(self.panelIsDark ? 0.12 : 0.08)

        let capsuleGlyph = self.controlAppearance?.iconColor ?? .white
        let headerGlyph = QrStudioGlass.iconColor(isDark: self.panelIsDark)
        let buttons = Array(self.capsuleButtons.values).map { ($0, capsuleGlyph) } + Array(self.headerButtons.values).map { ($0, headerGlyph) }
        for (button, glyphColor) in buttons {
            if animated, let layer = button.iconView.layer {
                let fade = CATransition()
                fade.type = .fade
                fade.duration = 0.35
                layer.add(fade, forKey: "contents")
            }
            button.iconView.image = QrStudioSheetView.iconImage(button.kind, color: glyphColor)
        }
    }

    private func layoutStatic(geometry: QrStudioSheetGeometry) {
        let sheetSize = geometry.sheet.size
        let backgroundSize = CGSize(width: sheetSize.width, height: sheetSize.height + 80.0)
        if self.panelGlass.frame.size != backgroundSize {
            self.panelGlass.setFrameSize(backgroundSize)
            self.panelGlass.updateLayout(size: backgroundSize, transition: .immediate)
        }

        self.contentContainer.layer?.transform = CATransform3DIdentity
        self.contentContainer.frame = CGRect(origin: CGPoint(), size: sheetSize)
        self.headerView.frame = CGRect(x: 0.0, y: 0.0, width: sheetSize.width, height: QrStudioSheetView.headerHeight)
        let contentFrame = self.contentFrame
        for (_, view) in self.contents {
            view.frame = contentFrame
        }

        let capsuleSize = geometry.capsule.size
        self.iconsContainer.setFrameSize(capsuleSize)
        let headerOrigin = floor((sheetSize.width - capsuleSize.width) * 0.5)
        let iconY = floor((capsuleSize.height - QrStudioSheetView.iconSide) * 0.5)
        let count = self.kinds.count
        for (index, kind) in self.kinds.enumerated() {
            let iconX = QrStudioSheetView.iconInset + CGFloat(index) * (QrStudioSheetView.iconSide + QrStudioSheetView.iconSpacing)
            if let button = self.capsuleButtons[kind] {
                let left = index == 0 ? 0.0 : iconX - QrStudioSheetView.iconSpacing * 0.5
                let right = index == count - 1 ? capsuleSize.width : iconX + QrStudioSheetView.iconSide + QrStudioSheetView.iconSpacing * 0.5
                button.frame = CGRect(x: left, y: 0.0, width: right - left, height: capsuleSize.height)
                button.iconView.frame = CGRect(x: iconX - left, y: iconY, width: QrStudioSheetView.iconSide, height: QrStudioSheetView.iconSide)
            }
            if let button = self.headerButtons[kind] {
                let pillY = floor((QrStudioSheetView.headerHeight - QrStudioSheetView.pillHeight) * 0.5)
                let frame = CGRect(x: headerOrigin + iconX - QrStudioSheetView.pillInset, y: pillY, width: QrStudioSheetView.iconSide + QrStudioSheetView.pillInset * 2.0, height: QrStudioSheetView.pillHeight)
                button.frame = frame
                button.iconView.frame = CGRect(x: QrStudioSheetView.pillInset, y: floor((frame.height - QrStudioSheetView.iconSide) * 0.5), width: QrStudioSheetView.iconSide, height: QrStudioSheetView.iconSide)
            }
        }
    }

    private func updateHeader(transition: ContainedViewLayoutTransition) {
        guard let currentTab = self.currentTab, let selectedButton = self.headerButtons[currentTab] else {
            self.headerPill.isHidden = true
            for (_, button) in self.headerButtons {
                button.iconView.layer?.opacity = 1.0
            }
            return
        }
        let wasHidden = self.headerPill.isHidden
        self.headerPill.isHidden = false
        if wasHidden {
            self.headerPill.frame = selectedButton.frame
        } else {
            transition.updateFrame(view: self.headerPill, frame: selectedButton.frame)
        }
        for (kind, button) in self.headerButtons {
            if let layer = button.iconView.layer {
                transition.updateAlpha(layer: layer, alpha: kind == currentTab ? 1.0 : 0.45)
            }
        }
    }

    func setContent(_ view: NSView, for kind: QrStudioLook.Kind) {
        if let current = self.contents[kind], current !== view {
            current.removeFromSuperview()
        }
        self.contents[kind] = view
        view.frame = self.contentFrame
        self.updateAttachedContent()
    }

    private func updateAttachedContent() {
        let isShown = self.motion.isOpen || self.motion.rise > 0.001
        for (kind, view) in self.contents {
            let attached = isShown && (kind == self.currentTab || self.fadingKinds[kind] != nil)
            if attached {
                if view.superview !== self.contentContainer {
                    view.layer?.removeAllAnimations()
                    view.layer?.opacity = 1.0
                    self.contentContainer.addSubview(view, positioned: .below, relativeTo: self.headerView)
                }
            } else if view.superview != nil {
                view.removeFromSuperview()
                view.layer?.removeAllAnimations()
                view.layer?.opacity = 1.0
            }
        }
    }

    func open(tab: QrStudioLook.Kind) {
        let previous = self.currentTab
        let crossfade = self.isContentInteractive && previous != nil && previous != tab
        self.currentTab = tab
        if crossfade, let previous {
            self.fadeToken += 1
            self.fadingKinds[previous] = self.fadeToken
        }
        self.fadingKinds.removeValue(forKey: tab)
        self.motion.open(animated: true)
        self.updateAttachedContent()
        if crossfade, let previous {
            let transition = ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeInOut)
            if let view = self.contents[tab] {
                view.layer?.opacity = 0.0
                transition.updateAlpha(view: view, alpha: 1.0)
            }
            if let view = self.contents[previous] {
                let token = self.fadeToken
                transition.updateAlpha(view: view, alpha: 0.0, completion: { [weak self] _ in
                    guard let self, self.fadingKinds[previous] == token else {
                        return
                    }
                    self.fadingKinds.removeValue(forKey: previous)
                    self.updateAttachedContent()
                })
            }
            self.updateHeader(transition: transition)
        } else {
            self.updateHeader(transition: .immediate)
        }
        self.runMotion()
    }

    func close() {
        guard self.motion.isOpen else {
            return
        }
        if let window = self.window, let responder = window.firstResponder as? NSView, responder.isDescendant(of: self) {
            _ = window.makeFirstResponder(nil)
        }
        self.isDragging = false
        self.dragStartY = nil
        self.motion.close(velocity: 0.0, travel: 1.0)
        self.runMotion()
    }

    private func releaseTravel(geometry: QrStudioSheetGeometry) -> CGFloat {
        return geometry.capsule.minY - (geometry.sheet.minY + self.motion.pull)
    }

    override func mouseDown(with event: NSEvent) {
        guard self.motion.isOpen else {
            return
        }
        let point = self.convert(event.locationInWindow, from: nil)
        self.dragStartY = point.y
        self.dragAnchor = self.motion.pull
        self.isDragging = false
        self.lastDragY = point.y
        self.lastDragTime = event.timestamp
        self.dragVelocity = 0.0
    }

    override func mouseDragged(with event: NSEvent) {
        guard let dragStartY = self.dragStartY, self.motion.isOpen else {
            return
        }
        let point = self.convert(event.locationInWindow, from: nil)
        let translation = point.y - dragStartY
        if !self.isDragging && abs(translation) < 4.0 {
            return
        }
        self.isDragging = true
        let dt = event.timestamp - self.lastDragTime
        if dt > 0.0 {
            self.dragVelocity = (point.y - self.lastDragY) / CGFloat(dt)
        }
        self.lastDragY = point.y
        self.lastDragTime = event.timestamp
        self.motion.drag(self.dragAnchor + translation)
        self.runMotion()
    }

    override func mouseUp(with event: NSEvent) {
        let wasDragging = self.isDragging
        self.dragStartY = nil
        self.isDragging = false
        guard wasDragging, let geometry = self.geometry, self.motion.isOpen else {
            return
        }
        if event.timestamp - self.lastDragTime > 0.1 {
            self.dragVelocity = 0.0
        }
        self.motion.release(velocity: self.dragVelocity, travel: self.releaseTravel(geometry: geometry))
        self.runMotion()
    }

    private func frame(geometry: QrStudioSheetGeometry, sample: QrStudioSheetMotion.Sample) -> CGRect {
        return geometry.frame(rise: sample.rise, spread: sample.spread, pull: sample.pull, lift: 0.0)
    }

    private func layout(geometry: QrStudioSheetGeometry, sample: QrStudioSheetMotion.Sample) -> Layout {
        let frame = self.frame(geometry: geometry, sample: sample)
        let corners = geometry.corners(rise: sample.rise, frame: frame)
        let phases = QrStudioSheetGeometry.phases(grown: min(sample.rise, sample.spread))
        let sheetSize = geometry.sheet.size
        let zoom = min(1.08, max(frame.width / max(sheetSize.width, 1.0), frame.height / max(sheetSize.height, 1.0)))
        return Layout(frame: frame, top: corners.top, bottom: corners.bottom, glassAlpha: phases.glass, iconsAlpha: phases.icons, backgroundAlpha: phases.background, contentAlpha: phases.content, zoom: zoom)
    }

    private func runMotion() {
        guard self.geometry != nil else {
            return
        }
        if self.motion.isSettled {
            self.stopLink()
            self.applyCurrent()
            return
        }
        if self.link == nil {
            self.lastTick = CACurrentMediaTime()
            self.link = SharedDisplayLinkDriver.shared.add(framesPerSecond: .fps(60), { [weak self] _ in
                self?.tick()
            })
        }
        self.applyCurrent()
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = now - self.lastTick
        self.lastTick = now
        self.motion.step(dt)
        if self.motion.isSettled {
            self.stopLink()
        }
        self.applyCurrent()
    }

    private func stopLink() {
        self.link?.invalidate()
        self.link = nil
    }

    private func applyCurrent() {
        guard let geometry = self.geometry else {
            return
        }
        let layout = self.layout(geometry: geometry, sample: self.motion.sample)
        self.updateAttachedContent()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.applyGlass(layout, geometry: geometry)
        self.applyWindow(layout, geometry: geometry)
        CATransaction.commit()
        self.isContentInteractive = self.motion.isOpen && layout.contentAlpha > 0.9
        self.progressUpdated?()
    }

    private func applyGlass(_ layout: Layout, geometry: QrStudioSheetGeometry) {
        let frame = layout.frame
        let isVisible = layout.glassAlpha > 0.001
        if self.capsuleGlass.isHidden == isVisible {
            self.capsuleGlass.isHidden = !isVisible
        }
        if self.iconsContainer.isHidden == isVisible {
            self.iconsContainer.isHidden = !isVisible
        }
        guard isVisible else {
            return
        }
        if self.capsuleGlass.frame != frame {
            self.capsuleGlass.frame = frame
        }
        self.capsuleGlass.cornerRadius = min(layout.top, min(frame.width, frame.height) * 0.5)
        self.capsuleGlass.updateLayout(size: frame.size, transition: .immediate)
        ContainedViewLayoutTransition.immediate.updateAlpha(view: self.capsuleGlass, alpha: layout.glassAlpha)
        let capsuleSize = geometry.capsule.size
        self.iconsContainer.setFrameOrigin(NSPoint(x: floor(frame.midX - capsuleSize.width * 0.5), y: floor(frame.midY - capsuleSize.height * 0.5)))
        self.iconsContainer.layer?.opacity = Float(layout.glassAlpha * layout.iconsAlpha)
    }

    private func applyWindow(_ layout: Layout, geometry: QrStudioSheetGeometry) {
        let isVisible = layout.backgroundAlpha > 0.001 || layout.contentAlpha > 0.001
        if self.clipView.isHidden == isVisible {
            self.clipView.isHidden = !isVisible
        }
        guard isVisible else {
            return
        }
        let frame = layout.frame
        if self.clipView.frame != frame {
            self.clipView.frame = frame
        }
        self.clipView.update(size: frame.size, top: layout.top, bottom: layout.bottom)

        let sheetSize = geometry.sheet.size
        let backgroundWidth = self.panelGlass.frame.width
        self.panelGlass.setFrameOrigin(NSPoint(x: floor((frame.width - backgroundWidth) * 0.5), y: 0.0))
        ContainedViewLayoutTransition.immediate.updateAlpha(view: self.panelGlass, alpha: layout.backgroundAlpha)

        if let layer = self.contentContainer.layer {
            let zoom = layout.zoom
            let offset = (frame.width - sheetSize.width) * 0.5
            let pivot = CGPoint(x: sheetSize.width * 0.5, y: 0.0)
            let anchor = CGPoint(x: layer.anchorPoint.x * sheetSize.width, y: layer.anchorPoint.y * sheetSize.height)
            layer.transform = CATransform3DConcat(CATransform3DMakeScale(zoom, zoom, 1.0), CATransform3DMakeTranslation((1.0 - zoom) * (pivot.x - anchor.x) + offset, (1.0 - zoom) * (pivot.y - anchor.y), 0.0))
            layer.opacity = Float(layout.contentAlpha)
        }
    }
}
