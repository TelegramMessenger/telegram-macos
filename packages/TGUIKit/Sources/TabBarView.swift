import Cocoa

public protocol TabViewDelegate: AnyObject {
    func didChange(selected item: TabItem, index: Int)
    func scrollup()
}

struct FloatingTabBarLayout {
    static let height: CGFloat = 48
    static let bottomGap: CGFloat = 16
    static let sideInset: CGFloat = 20
    static let innerInset: CGFloat = 4

    let itemFrames: [NSRect]

    static func frame(in size: NSSize) -> NSRect {
        let width = min(500, max(0, size.width - sideInset * 2))
        return NSMakeRect(floorToScreenPixels((size.width - width) / 2), max(0, size.height - height - bottomGap), width, height)
    }

    init(size: NSSize, count: Int) {
        let width = max(0, size.width - Self.innerInset * 2)
        itemFrames = (0 ..< max(0, count)).map { index in
            let left = floorToScreenPixels(Self.innerInset + width * CGFloat(index) / CGFloat(count))
            let right = floorToScreenPixels(Self.innerInset + width * CGFloat(index + 1) / CGFloat(count))
            return NSMakeRect(left, Self.innerInset, right - left, max(0, size.height - Self.innerInset * 2))
        }
    }

    func index(at point: NSPoint) -> Int? {
        return itemFrames.indices.min(by: { abs(itemFrames[$0].midX - point.x) < abs(itemFrames[$1].midX - point.x) })
    }

    func position(at x: CGFloat) -> CGFloat {
        for index in 0 ..< max(0, itemFrames.count - 1) where x < itemFrames[index + 1].midX {
            let distance = itemFrames[index + 1].midX - itemFrames[index].midX
            return CGFloat(index) + min(1, max(0, (x - itemFrames[index].midX) / max(1, distance)))
        }
        return CGFloat(max(0, itemFrames.count - 1))
    }

    func selectionFrame(at position: CGFloat, lifted: Bool, nativeLens: Bool = false) -> NSRect {
        guard !itemFrames.isEmpty else {
            return .zero
        }
        let position = min(CGFloat(itemFrames.count - 1), max(0, position))
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, itemFrames.count - 1)
        let progress = position - CGFloat(lower)
        let first = itemFrames[lower]
        let second = itemFrames[upper]
        let frame = NSMakeRect(first.minX + (second.minX - first.minX) * progress, first.minY, first.width + (second.width - first.width) * progress, first.height)
        return lifted ? frame.insetBy(dx: nativeLens ? -10 : -8, dy: -8) : frame
    }
}

final class TabBarItemControl: Control {
    weak var tabBar: TabBarView?
    var tabIsSelected = false
    private var contextClick = false

    override var mouseDownCanMoveWindow: Bool {
        return false
    }

    override func mouseDown(with event: NSEvent) {
        contextClick = event.modifierFlags.contains(.control)
        if contextClick {
            tabBar?.cancelSelection()
            super.mouseDown(with: event)
        } else if isEnabled && userInteractionEnabled, let tabBar {
            tabBar.beginSelection(at: tabBar.convert(event.locationInWindow, from: nil))
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if !contextClick, let tabBar {
            tabBar.updateSelection(at: tabBar.convert(event.locationInWindow, from: nil))
        }
    }

    override func mouseUp(with event: NSEvent) {
        if contextClick {
            contextClick = false
            send(event: .RightUp)
        } else if let tabBar {
            tabBar.endSelection(at: tabBar.convert(event.locationInWindow, from: nil))
        }
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        return isAccessibilityElement() ? .radioButton : super.accessibilityRole()
    }

    override func isAccessibilitySelected() -> Bool {
        return tabIsSelected
    }
}

public class TabBarView: View {
    private struct SelectionGesture {
        let start: NSPoint
        let center: CGFloat
        var position: CGFloat
        var isDragging = false
    }

    private var tabs: [TabItem] = []
    private(set) var itemControls: [TabBarItemControl] = []
    public private(set) var selectedIndex: Int = 0
    public weak var delegate: TabViewDelegate?

    private let glass = LiquidGlassView(frame: .zero, cornerRadius: FloatingTabBarLayout.height / 2, tintAlpha: 0.15)
    private let selectionView = View()
    private let liftedGlass = LiquidGlassView(frame: .zero, cornerRadius: 28, hasShadow: true, hasBorder: true, tintAlpha: 0.1)
    private var gesture: SelectionGesture?
    private var escapeMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var contentScales: [CGFloat] = []
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    var reduceTransparency: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
    var lensFactory: () -> LiquidGlassLensView? = { LiquidGlassLensView.make() }
    private(set) var nativeLens: LiquidGlassLensView?
    private var requestedLensMode: Bool?
    private var glassSettingObserver: NSObjectProtocol?
    private var displayOptionsObserver: NSObjectProtocol?

    private var itemLayout: FloatingTabBarLayout {
        return FloatingTabBarLayout(size: bounds.size, count: tabs.count)
    }

    var selectionFrame: NSRect {
        return selectionView.frame
    }

    var isTrackingSelection: Bool {
        return gesture != nil
    }

    required public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizesSubviews = false
        autoresizingMask = []
        backgroundColor = .clear
        layer?.masksToBounds = false
        glass.isEventLess = true
        selectionView.isEventLess = true
        selectionView.layer?.masksToBounds = false
        liftedGlass.isEventLess = true
        addSubview(glass)
        addSubview(selectionView)
        selectionView.addSubview(liftedGlass)
        liftedGlass.alphaValue = 0
        updateLocalizationAndTheme(theme: presentation)
        glassSettingObserver = NotificationCenter.default.addObserver(forName: systemLiquidGlassDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.updateLocalizationAndTheme(theme: presentation)
        }
        displayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cancelSelection(animated: false)
            self?.updateLocalizationAndTheme(theme: presentation)
        }
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        if let glassSettingObserver {
            NotificationCenter.default.removeObserver(glassSettingObserver)
        }
        if let displayOptionsObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(displayOptionsObserver)
        }
    }

    public override var isHidden: Bool {
        didSet {
            if isHidden {
                cancelSelection(animated: false)
            }
        }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        cancelSelection(animated: false)
    }

    func control(for index: Int) -> Control {
        return itemControls[index]
    }

    func addTab(_ tab: TabItem) {
        insertTab(tab, at: tabs.count)
    }

    func replaceTab(_ tab: TabItem, at index: Int) {
        guard tabs.indices.contains(index) else {
            return
        }
        cancelSelection(animated: false)
        let previous = tabs[index]
        tabs[index] = tab
        let control = itemControls[index]
        if previous.subNode?.view !== tab.subNode?.view {
            previous.subNode?.view?.removeFromSuperview()
            if let badge = tab.subNode?.view {
                control.addSubview(badge)
            }
        }
        if let icon = control.subviews.first {
            tab.setSelected(index == selectedIndex, for: icon, animated: false)
            (icon as? AppearanceViewProtocol)?.updateLocalizationAndTheme(theme: presentation)
        }
        updateMetadata(for: control, tab: tab)
        tab.subNode?.update()
        updateLayout()
    }

    func insertTab(_ tab: TabItem, at index: Int) {
        guard (0 ... tabs.count).contains(index) else {
            return
        }
        cancelSelection(animated: false)
        if !tabs.isEmpty && selectedIndex >= index {
            selectedIndex += 1
        }
        tabs.insert(tab, at: index)
        let control = TabBarItemControl(frame: .zero)
        control.tabBar = self
        control.backgroundColor = .clear
        control.layer?.masksToBounds = false
        control.autoresizesSubviews = false
        let icon = tab.makeView()
        control.addSubview(icon)
        tab.setSelected(false, for: icon, animated: false)
        if let badge = tab.subNode?.view {
            control.addSubview(badge)
        }
        control.set(handler: { [weak self, weak control] _ in
            guard let self, let control, let index = self.itemControls.firstIndex(of: control) else {
                return
            }
            self.tabs[index].longHoverHandler?(control)
        }, for: .RightDown)
        control.set(handler: { [weak self, weak control] _ in
            guard let self, let control, let index = self.itemControls.firstIndex(of: control) else {
                return
            }
            self.activate(index: index)
        }, for: .Click)
        updateMetadata(for: control, tab: tab)
        itemControls.insert(control, at: index)
        contentScales.insert(1, at: index)
        (nativeLens?.contentView ?? self).addSubview(control)
        tab.subNode?.update()
        updateLayout()
        updateSelection(animated: false)
    }

    func removeTab(_ tab: TabItem) {
        if let index = tabs.firstIndex(of: tab) {
            removeTab(at: index)
        }
    }

    func removeTab(at index: Int) {
        guard tabs.indices.contains(index) else {
            return
        }
        cancelSelection(animated: false)
        let removedSelection = index == selectedIndex
        tabs.remove(at: index)
        itemControls.remove(at: index).removeFromSuperview()
        contentScales.remove(at: index)
        if selectedIndex > index {
            selectedIndex -= 1
        } else if removedSelection {
            selectedIndex = min(index, max(0, tabs.count - 1))
        }
        updateLayout()
        updateSelection(animated: false)
        if removedSelection, tabs.indices.contains(selectedIndex) {
            delegate?.didChange(selected: tabs[selectedIndex], index: selectedIndex)
        }
    }

    func enumerateItems(_ f: (TabItem) -> Bool) {
        for item in tabs {
            if f(item) {
                break
            }
        }
    }

    public var isEmpty: Bool {
        return tabs.isEmpty
    }

    public var count: Int {
        return tabs.count
    }

    public func tab(at index: Int) -> TabItem {
        return tabs[index]
    }

    public func showTooltip(text: String, for index: Int) {
        guard itemControls.indices.contains(index) else {
            return
        }
        tooltip(for: itemControls[index], text: text)
    }

    private func updateMetadata(for control: Control, tab: TabItem) {
        control.setAccessibilityLabel(tab.accessibilityTitle)
        control.toolTip = tab.accessibilityTitle
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        backgroundColor = .clear
        selectionView.backgroundColor = theme.colors.text.withAlphaComponent(theme.colors.isDark ? 0.12 : 0.08)
        for (tab, control) in zip(tabs, itemControls) {
            updateMetadata(for: control, tab: tab)
            if nativeLens != nil {
                control.updateLocalizationAndTheme(theme: theme)
            }
        }
        updateSelection(animated: false)
    }

    public override func setFrameSize(_ newSize: NSSize) {
        if frame.size != newSize {
            cancelSelection(animated: false)
        }
        super.setFrameSize(newSize)
        updateLayout()
    }

    public override func layout() {
        super.layout()
        updateLayout()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateLens(transition: .immediate)
    }

    private func updateLayout() {
        let modeChanged = updateLensMode()
        glass.frame = bounds
        glass.updateLayout(size: bounds.size, transition: .immediate)
        nativeLens?.frame = bounds
        for (index, frame) in itemLayout.itemFrames.enumerated() {
            let control = itemControls[index]
            if control.frame != frame {
                control.frame = frame
                control.subviews.first?.center()
                tabs[index].subNode?.update()
            }
        }
        if modeChanged {
            updateSelection(animated: false)
        } else {
            updateLens(transition: .immediate)
        }
    }

    public func setSelectedIndex(_ index: Int, respondToDelegate: Bool, animated: Bool) {
        guard tabs.indices.contains(index) else {
            return
        }
        finishGesture()
        selectedIndex = index
        updateSelection(animated: animated)
        if respondToDelegate {
            delegate?.didChange(selected: tabs[index], index: index)
        }
    }

    private func activate(index: Int) {
        if index == selectedIndex {
            delegate?.scrollup()
        } else {
            setSelectedIndex(index, respondToDelegate: true, animated: true)
        }
    }

    func beginSelection(at point: NSPoint) {
        _ = updateLensMode()
        guard !isHidden, let index = itemLayout.index(at: point) else {
            return
        }
        finishGesture()
        gesture = SelectionGesture(start: point, center: itemLayout.itemFrames[index].midX, position: CGFloat(index))
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.gesture != nil, event.window === self.window, event.keyCode == 53 else {
                return event
            }
            self.cancelSelection(animated: true)
            return nil
        }
        if let window {
            resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
                self?.cancelSelection(animated: true)
            }
        }
        updateSelection(animated: true)
    }

    func updateSelection(at point: NSPoint) {
        guard var gesture, gesture.isDragging || abs(point.x - gesture.start.x) >= 3 else {
            return
        }
        gesture.isDragging = true
        let position = itemLayout.position(at: gesture.center + point.x - gesture.start.x)
        let changed = gesture.position != position
        gesture.position = position
        self.gesture = gesture
        if changed {
            updateSelection(animated: false)
        }
    }

    func endSelection(at point: NSPoint) {
        guard gesture != nil else {
            return
        }
        let isDragging = gesture?.isDragging == true
        if isDragging {
            updateSelection(at: point)
        }
        let index = Int(gesture!.position.rounded())
        finishGesture()
        if index == selectedIndex {
            updateSelection(animated: true)
            delegate?.scrollup()
        } else {
            selectedIndex = index
            updateSelection(animated: true, playSelectedItem: isDragging)
            delegate?.didChange(selected: tabs[index], index: index)
        }
    }

    func cancelSelection(animated: Bool = true) {
        guard gesture != nil else {
            return
        }
        finishGesture()
        updateSelection(animated: animated)
    }

    private func finishGesture() {
        gesture = nil
        if let escapeMonitor {
            NSEvent.removeMonitor(escapeMonitor)
            self.escapeMonitor = nil
        }
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
            self.resignObserver = nil
        }
    }

    private func updateSelection(animated: Bool, playSelectedItem: Bool = false) {
        let modeChanged = updateLensMode()
        let reduceMotion = self.reduceMotion()
        let animated = animated && !reduceMotion && !modeChanged
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.4, curve: .spring) : .immediate
        let previewIndex = gesture.map { Int($0.position.rounded()) } ?? selectedIndex
        for (index, control) in itemControls.enumerated() {
            let selected = index == previewIndex
            if control.tabIsSelected != selected || (selected && playSelectedItem), let icon = control.subviews.first {
                control.tabIsSelected = selected
                control.isSelected = selected
                tabs[index].setSelected(selected, for: icon, animated: animated)
            }
            let scale: CGFloat = nativeLens == nil && gesture != nil && selected && !reduceMotion ? 1.15 : 1
            if contentScales[index] != scale, let layer = control.layer {
                let previous = layer.presentation()?.transform ?? layer.transform
                var transform = CATransform3DMakeTranslation(control.bounds.midX, control.bounds.midY, 0)
                transform = CATransform3DScale(transform, scale, scale, 1)
                transform = CATransform3DTranslate(transform, -control.bounds.midX, -control.bounds.midY, 0)
                layer.transform = transform
                if animated {
                    layer.animate(from: NSValue(caTransform3D: previous), to: NSValue(caTransform3D: transform), keyPath: "transform", timingFunction: .spring, duration: 0.4)
                } else {
                    layer.removeAnimation(forKey: "transform")
                }
                contentScales[index] = scale
            }
        }
        updateLens(transition: transition)
    }

    private func updateLens(transition: ContainedViewLayoutTransition) {
        selectionView.isHidden = tabs.isEmpty
        let position = gesture?.position ?? CGFloat(selectedIndex)
        let lifted = gesture != nil && !reduceMotion()
        let frame = itemLayout.selectionFrame(at: position, lifted: lifted, nativeLens: nativeLens != nil)
        selectionView.layer?.cornerRadius = frame.height / 2
        updateSelectionFrame(frame, transition: transition)
        if let nativeLens {
            let animation: LiquidGlassLensAnimation
            switch transition {
            case .immediate:
                animation = .immediate
            case let .animated(duration, curve):
                if case .spring = curve {
                    animation = .spring(duration: duration)
                } else {
                    animation = .animated(duration: duration, timingFunction: curve.timingFunction)
                }
            }
            nativeLens.frame = bounds
            let unlensedIconColor = presentation.colors.isDark ? NSColor.white : presentation.colors.grayIcon
            let sources = itemControls.enumerated().flatMap { index, control in
                control.subviews.enumerated().flatMap { childIndex, view in
                    if childIndex == 0 {
                        return tabs[index].lensContentSources(for: view, lensedTintColor: presentation.colors.accentIcon, unlensedTintColor: unlensedIconColor)
                    }
                    return [LiquidGlassLensContentSource(view: view)]
                }
            }
            nativeLens.update(lensFrame: frame, interactionProgress: lifted ? 1 : 0, appearance: presentation.appearance, backingScale: window?.backingScaleFactor ?? System.backingScale, animation: animation, restingBlurRadius: 16, restingTintColor: selectionView.backgroundColor, contentSources: sources)
            selectionView.layer?.removeAnimation(forKey: "opacity")
            selectionView.alphaValue = 0
            liftedGlass.alphaValue = 0
            return
        }
        selectionView.alphaValue = 1
        transition.updateFrame(view: liftedGlass, frame: frame.size.bounds)
        liftedGlass.cornerRadius = frame.height / 2
        liftedGlass.updateLayout(size: frame.size, transition: transition)
        transition.updateAlpha(view: liftedGlass, alpha: lifted ? 1 : 0)
    }

    private func updateLensMode() -> Bool {
        let enabled: Bool
        if #available(macOS 26.0, *) {
            enabled = System.liquidGlass && !reduceTransparency()
        } else {
            enabled = false
        }
        guard requestedLensMode != enabled else {
            return false
        }
        requestedLensMode = enabled
        finishGesture()
        if let nativeLens {
            nativeLens.reset()
            for control in itemControls {
                addSubview(control)
            }
            nativeLens.removeFromSuperview()
            self.nativeLens = nil
        }
        if enabled, let lens = lensFactory() {
            nativeLens = lens
            addSubview(lens)
            lens.frame = bounds
            for control in itemControls {
                lens.contentView.addSubview(control)
            }
        }
        return true
    }

    private func updateSelectionFrame(_ frame: NSRect, transition: ContainedViewLayoutTransition) {
        guard selectionView.frame != frame else {
            return
        }
        guard let layer = selectionView.layer else {
            selectionView.frame = frame
            return
        }
        switch transition {
        case .immediate:
            layer.removeAnimation(forKey: "position")
            layer.removeAnimation(forKey: "bounds")
            selectionView.frame = frame
        case let .animated(duration, curve):
            let displayed = layer.presentation()
            let positionAnimation = layer.animation(forKey: "position") as? CABasicAnimation
            let boundsAnimation = layer.animation(forKey: "bounds") as? CABasicAnimation
            let previousPosition = positionAnimation.map { displayed?.position ?? ($0.fromValue as? NSValue)?.pointValue ?? layer.position } ?? layer.position
            let previousBounds = boundsAnimation.map { displayed?.bounds ?? ($0.fromValue as? NSValue)?.rectValue ?? layer.bounds } ?? layer.bounds
            layer.removeAnimation(forKey: "position")
            layer.removeAnimation(forKey: "bounds")
            selectionView.frame = frame
            layer.animatePosition(from: previousPosition, to: layer.position, duration: duration, timingFunction: curve.timingFunction)
            layer.animateBounds(from: previousBounds, to: layer.bounds, duration: duration, timingFunction: curve.timingFunction)
        }
    }

    public override var mouseDownCanMoveWindow: Bool {
        return false
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard !isHidden, NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).contains(local), let index = itemLayout.index(at: local) else {
            return nil
        }
        return itemControls[index]
    }

    public override func isAccessibilityElement() -> Bool {
        return TGUIKitAccessibility.isEnabled && !isHidden && !tabs.isEmpty
    }

    public override func accessibilityRole() -> NSAccessibility.Role? {
        return .tabGroup
    }

    public override func accessibilityChildren() -> [Any]? {
        return isHidden ? [] : itemControls
    }
}
