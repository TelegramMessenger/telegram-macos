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
            tabBar.beginSelection(at: tabBar.convert(event.locationInWindow, from: nil), control: self, timestamp: event.timestamp)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if !contextClick, let tabBar {
            tabBar.updateSelection(at: tabBar.convert(event.locationInWindow, from: nil), timestamp: event.timestamp)
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
        let sourceIndex: Int
        let pressedAt: TimeInterval
        let heldPosition: CGFloat?
        var reordersTabs = false
        var position: CGFloat
        var destination: Int
        var isDragging = false
    }

    private var tabs: [TabItem] = []
    private(set) var itemControls: [TabBarItemControl] = []
    public private(set) var selectedIndex: Int = 0
    public weak var delegate: TabViewDelegate?
    var allowsReordering = false {
        didSet {
            cancelSelection(animated: false)
            updateLayout()
        }
    }
    var didReorderTabs: () -> Void = {}

    private let glass = LiquidGlassView(frame: .zero, cornerRadius: FloatingTabBarLayout.height / 2, tintAlpha: 0.15)
    private let selectionView = View()
    private let liftedGlass = LiquidGlassView(frame: .zero, cornerRadius: 28, hasShadow: true, hasBorder: true, tintAlpha: 0.1)
    private var gesture: SelectionGesture?
    private var reorderGesture: SelectionGesture? {
        guard let gesture, gesture.reordersTabs, gesture.isDragging else {
            return nil
        }
        return gesture
    }

    private var pickup: NSView?
    private weak var pickupControl: TabBarItemControl?
    private var pickupCleanup: DispatchWorkItem?
    private static let settleDuration: TimeInterval = 0.22
    private static let reorderHoldDuration: TimeInterval = 0.25

    private var reorderTransition: ContainedViewLayoutTransition {
        return reduceMotion() ? .immediate : .animated(duration: Self.settleDuration, curve: .easeOut)
    }

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
        pickupCleanup?.cancel()
        if reorderGesture != nil {
            NSCursor.pop()
        }
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
        updateItemFrames(transition: .immediate)
        if modeChanged {
            updateSelection(animated: false)
        } else {
            let isReordering = reorderGesture != nil || pickup != nil
            updateLens(transition: isReordering ? reorderTransition : .immediate)
        }
    }

    private func displayedCenter(of control: TabBarItemControl) -> CGFloat {
        return control.frame.midX + displayedOffset(of: control)
    }

    private func displayedOffset(of control: TabBarItemControl) -> CGFloat {
        guard let layer = control.layer, let animation = layer.animation(forKey: "position") as? CABasicAnimation else {
            return 0
        }
        let shown = layer.presentation()?.position ?? (animation.fromValue as? NSValue)?.pointValue ?? layer.position
        return shown.x - layer.position.x
    }

    private func updateItemFrames(transition: ContainedViewLayoutTransition) {
        let layout = itemLayout
        let drag = reorderGesture
        let commonWidth = allowsReordering ? layout.itemFrames.map(\.width).min() : nil

        for (index, control) in itemControls.enumerated() {
            let isDragged = index == drag?.sourceIndex
            var slot = index
            if let drag, !isDragged {
                if drag.sourceIndex < index && index <= drag.destination {
                    slot -= 1
                } else if drag.destination <= index && index < drag.sourceIndex {
                    slot += 1
                }
            }
            var frame = layout.itemFrames[slot]
            let heldPosition = index == gesture?.sourceIndex ? gesture?.heldPosition : nil
            if let position = isDragged ? drag?.position : heldPosition {
                frame = layout.selectionFrame(at: position, lifted: false)
            }
            if let commonWidth {
                frame = NSRect(x: frame.midX - commonWidth / 2, y: frame.minY, width: commonWidth, height: frame.height)
            }
            move(control, tab: tabs[index], to: frame, transition: isDragged ? .immediate : transition)
        }
    }

    private func move(_ control: TabBarItemControl, tab: TabItem, to frame: NSRect, transition: ContainedViewLayoutTransition) {
        guard control.frame != frame else {
            return
        }
        let layer = control.layer
        let previousX = (layer?.position.x ?? 0) + displayedOffset(of: control)
        layer?.removeAnimation(forKey: "position")
        let resized = control.frame.size != frame.size
        control.frame = frame
        if resized {
            control.subviews.first?.center()
            tab.subNode?.update()
        }
        if case let .animated(duration, curve) = transition, let layer {
            let from = NSPoint(x: previousX, y: layer.position.y)
            layer.animatePosition(from: from, to: layer.position, duration: duration, timingFunction: curve.timingFunction)
        }
    }

    private func startPickup(for control: TabBarItemControl) {
        guard !reduceMotion() else {
            return
        }
        clearPickup()
        pickupControl = control
        control.layer?.zPosition = 1
        if #available(macOS 14.0, *) {
            control.clipsToBounds = false
        }
        if nativeLens != nil, let glass = lensFactory() {
            pickup = glass
            glass.frame = control.bounds.insetBy(dx: -10, dy: -8)
            control.addSubview(glass)
            glass.layer?.zPosition = -1
            updatePickup(progress: 1, animation: .immediate)
        } else {
            let glass = LiquidGlassView(frame: control.bounds.insetBy(dx: -8, dy: -8), cornerRadius: 28, hasShadow: true, hasBorder: true, tintAlpha: 0.1)
            pickup = glass
            glass.isEventLess = true
            control.addSubview(glass)
            glass.layer?.zPosition = -1
            glass.updateLayout(size: glass.bounds.size, transition: .immediate)
        }
    }

    private func updatePickup(progress: CGFloat, animation: LiquidGlassLensAnimation) {
        guard let glass = pickup as? LiquidGlassLensView else {
            return
        }
        let frame = progress == 0 ? glass.bounds.insetBy(dx: 10, dy: 8) : glass.bounds
        glass.update(lensFrame: frame, interactionProgress: progress, appearance: presentation.appearance, backingScale: window?.backingScaleFactor ?? System.backingScale, animation: animation, contentSources: [])
    }

    private func settlePickup(transition: ContainedViewLayoutTransition) {
        guard let pickup, case let .animated(duration, curve) = transition else {
            clearPickup()
            return
        }
        updatePickup(progress: 0, animation: .animated(duration: duration, timingFunction: curve.timingFunction))
        if !(pickup is LiquidGlassLensView) {
            transition.updateAlpha(view: pickup, alpha: 0)
        }
        let cleanup = DispatchWorkItem { [weak self] in
            self?.clearPickup()
        }
        pickupCleanup = cleanup
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: cleanup)
    }

    private func clearPickup() {
        pickupCleanup?.cancel()
        pickupCleanup = nil
        (pickup as? LiquidGlassLensView)?.reset()
        pickup?.removeFromSuperview()
        pickup = nil
        pickupControl?.layer?.zPosition = 0
        pickupControl = nil
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

    func beginSelection(at point: NSPoint, control: TabBarItemControl? = nil, timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        _ = updateLensMode()
        let hitIndex = control.flatMap { itemControls.firstIndex(of: $0) }
        guard !isHidden, let index = hitIndex ?? itemIndex(at: point) else {
            return
        }
        finishGesture()
        clearPickup()
        let layout = itemLayout
        let pressed = itemControls[index]
        let center = allowsReordering ? displayedCenter(of: pressed) : layout.itemFrames[index].midX
        let heldPosition = center == pressed.frame.midX ? nil : layout.position(at: center)
        gesture = SelectionGesture(start: point, center: center, sourceIndex: index, pressedAt: timestamp, heldPosition: heldPosition, position: CGFloat(index), destination: index)
        if heldPosition != nil {
            let frame = pressed.frame.offsetBy(dx: center - pressed.frame.midX, dy: 0)
            move(pressed, tab: tabs[index], to: frame, transition: .immediate)
        }
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

    func updateSelection(at point: NSPoint, timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard var gesture else {
            return
        }
        let delta = point.x - gesture.start.x
        guard gesture.isDragging || abs(delta) >= 3 else {
            return
        }
        let startedDragging = !gesture.isDragging
        if startedDragging {
            gesture.reordersTabs = allowsReordering && tabs.count > 1 && timestamp > gesture.pressedAt + Self.reorderHoldDuration
        }
        let layout = itemLayout
        let x = gesture.center + delta
        let position = layout.position(at: x)
        if gesture.reordersTabs {
            let direction: CGFloat = position >= CGFloat(gesture.destination) ? 1 : -1
            let thresholdPosition = layout.position(at: x - direction * 4)
            let destination = Int(thresholdPosition.rounded())
            if (CGFloat(destination - gesture.destination) * direction) > 0 {
                gesture.destination = destination
            }
        }
        let changed = gesture.position != position
        gesture.position = position
        gesture.isDragging = true
        self.gesture = gesture

        if gesture.reordersTabs {
            if startedDragging {
                NSCursor.closedHand.push()
                updateSelection(animated: false)
                startPickup(for: itemControls[gesture.sourceIndex])
            }
            updateItemFrames(transition: reorderTransition)
            updateLens(transition: gesture.sourceIndex == selectedIndex ? .immediate : reorderTransition)
        } else if changed {
            updateSelection(animated: false)
        }
    }

    func endSelection(at point: NSPoint) {
        guard let gesture else {
            return
        }
        if gesture.reordersTabs {
            endReorder(at: point)
            return
        }
        if gesture.isDragging {
            updateSelection(at: point)
        }
        let index = Int((self.gesture ?? gesture).position.rounded())
        finishGesture(reorderTransition: reorderTransition)
        if index == selectedIndex {
            updateSelection(animated: true)
            delegate?.scrollup()
        } else {
            selectedIndex = index
            updateSelection(animated: true, playSelectedItem: gesture.isDragging)
            delegate?.didChange(selected: tabs[index], index: index)
        }
    }

    private func endReorder(at point: NSPoint) {
        guard bounds.insetBy(dx: -16, dy: -20).contains(point) else {
            cancelSelection()
            return
        }
        updateSelection(at: point)
        guard let drag = reorderGesture else {
            return
        }
        let source = drag.sourceIndex
        let destination = drag.destination
        if source != destination {
            let selectedControl = itemControls[selectedIndex]
            tabs.insert(tabs.remove(at: source), at: destination)
            itemControls.insert(itemControls.remove(at: source), at: destination)
            contentScales.insert(contentScales.remove(at: source), at: destination)
            selectedIndex = itemControls.firstIndex(of: selectedControl) ?? selectedIndex
        }
        finishGesture(reorderTransition: reorderTransition)
        updateLens(transition: reorderTransition)
        if source != destination {
            didReorderTabs()
        }
    }

    func cancelSelection(animated: Bool = true) {
        guard let gesture else {
            if !animated, pickup != nil {
                clearPickup()
                updateLens(transition: .immediate)
            }
            return
        }
        let transition = animated ? reorderTransition : .immediate
        finishGesture(reorderTransition: transition)
        if gesture.reordersTabs {
            updateLens(transition: transition)
        } else {
            updateSelection(animated: animated)
        }
    }

    private func finishGesture(reorderTransition: ContainedViewLayoutTransition = .immediate) {
        let previous = gesture
        gesture = nil
        if let previous {
            if previous.reordersTabs || previous.heldPosition != nil {
                updateItemFrames(transition: reorderTransition)
            }
            if previous.reordersTabs {
                NSCursor.pop()
                settlePickup(transition: reorderTransition)
            }
        }
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
        let selectionGesture = gesture.flatMap { $0.reordersTabs ? nil : $0 }
        let previewIndex = selectionGesture.map { Int($0.position.rounded()) } ?? selectedIndex
        for (index, control) in itemControls.enumerated() {
            let selected = index == previewIndex
            if control.tabIsSelected != selected || (selected && playSelectedItem), let icon = control.subviews.first {
                control.tabIsSelected = selected
                control.isSelected = selected
                tabs[index].setSelected(selected, for: icon, animated: animated)
            }
            let scale: CGFloat = nativeLens == nil && selectionGesture != nil && selected && !reduceMotion ? 1.15 : 1
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
        let hidesRestingSelection = reorderGesture != nil && !reduceMotion()
        selectionView.isHidden = tabs.isEmpty
        let selectionGesture = gesture.flatMap { $0.reordersTabs ? nil : $0 }
        let position = selectionGesture?.position ?? CGFloat(selectedIndex)
        let lifted = selectionGesture != nil && !reduceMotion()
        let frame = reorderGesture != nil && itemControls.indices.contains(selectedIndex)
            ? itemControls[selectedIndex].frame
            : itemLayout.selectionFrame(at: position, lifted: lifted, nativeLens: nativeLens != nil)
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
            let unlensedIconColor = presentation.colors.text
            let sources: [LiquidGlassLensContentSource] = reorderGesture != nil || pickup != nil ? [] : itemControls.enumerated().flatMap { index, control -> [LiquidGlassLensContentSource] in
                guard control.layer?.animation(forKey: "position") == nil else {
                    return []
                }
                return control.subviews.enumerated().flatMap { childIndex, view -> [LiquidGlassLensContentSource] in
                    guard view !== pickup else {
                        return []
                    }
                    if childIndex == 0 {
                        return tabs[index].lensContentSources(for: view, lensedTintColor: presentation.colors.accentIcon, unlensedTintColor: unlensedIconColor)
                    }
                    return [LiquidGlassLensContentSource(view: view)]
                }
            }
            nativeLens.update(lensFrame: frame, interactionProgress: lifted ? 1 : 0, appearance: presentation.appearance, backingScale: window?.backingScaleFactor ?? System.backingScale, animation: animation, restingBlurRadius: 16, restingTintColor: selectionView.backgroundColor, restingVisibility: hidesRestingSelection ? 0 : 1, contentSources: sources)
            selectionView.layer?.removeAnimation(forKey: "opacity")
            selectionView.alphaValue = 0
            liftedGlass.alphaValue = 0
            return
        }
        transition.updateAlpha(view: selectionView, alpha: hidesRestingSelection ? 0 : 1)
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
        clearPickup()
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

    private func itemIndex(at point: NSPoint) -> Int? {
        if allowsReordering {
            return itemControls.indices.min {
                abs(displayedCenter(of: itemControls[$0]) - point.x) < abs(displayedCenter(of: itemControls[$1]) - point.x)
            }
        }
        return itemLayout.index(at: point)
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard !isHidden, NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).contains(local), let index = itemIndex(at: local) else {
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
