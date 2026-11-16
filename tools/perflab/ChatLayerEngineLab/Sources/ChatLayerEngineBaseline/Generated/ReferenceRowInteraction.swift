import Cocoa
import TGUIKit

enum ReferenceChatLayerTreeError: Error, Equatable {
    case duplicateIdentifier
    case alreadyParented
    case cycle
}

struct ReferenceChatLayerPointerEvent {
    enum Kind {
        case entered, exited, moved, down, dragged, up, cancelled
    }
    let kind: Kind
    let location: NSPoint
    let sceneLocation: NSPoint
    let button: Int
    let clickCount: Int
    let modifiers: NSEvent.ModifierFlags
    let nativeEvent: NSEvent?
}

class ReferenceChatLayerNode {
    let id: AnyHashable
    let layer: SimpleLayer
    private(set) weak var parent: ReferenceChatLayerNode?
    fileprivate(set) weak var scene: ReferenceChatLayerSceneView?
    private(set) var children: [ReferenceChatLayerNode] = []
    fileprivate var orderedChildren: [ReferenceChatLayerNode] = []
    fileprivate var accessibilityElement: ReferenceChatLayerAccessibilityElement?

    var acceptsPointerEvents = false {
        didSet {
            if acceptsPointerEvents != oldValue { scene?.invalidateHitIndex(); scene?.validateInput() }
        }
    }
    var isEnabled = true { didSet { scene?.validateInput() } }
    var acceptsKeyboardFocus = false { didSet { scene?.validateInput() } }
    var cursor: NSCursor?
    var hitRegion: ((NSPoint) -> Bool)? { didSet { scene?.invalidateHitIndex() } }
    var onPointer: ((ReferenceChatLayerPointerEvent) -> Bool)?
    var onCommand: ((Selector) -> Bool)?
    var onKeyDown: ((NSEvent) -> Bool)?
    var onFocusChanged: ((Bool) -> Void)?
    var onWindowKeyChanged: ((Bool) -> Void)?
    var menu: ((ReferenceChatLayerPointerEvent) -> NSMenu?)?
    var onAccessibilityPress: (() -> Bool)?
    var accessibilityRole: NSAccessibility.Role?
    var accessibilityLabel: String?
    var accessibilityValue: String?

    var frame: NSRect {
        get { layer.frame }
        set {
            let frame = NSRect(origin: newValue.origin, size: NSSize(width: max(0, newValue.width), height: max(0, newValue.height)))
            guard layer.frame != frame else { return }
            layer.frame = frame
            scene?.invalidateHitIndex()
            scene?.needsLayout = true
        }
    }
    func updateFrame(_ frame: NSRect, transition: ContainedViewLayoutTransition) {
        let frame = NSRect(origin: frame.origin, size: NSSize(width: max(0, frame.width), height: max(0, frame.height)))
        guard self.frame != frame else { return }
        transition.updateFrame(layer: layer, frame: frame)
        scene?.invalidateHitIndex()
        scene?.needsLayout = true
    }

    var transform: CATransform3D {
        get { layer.transform }
        set { layer.transform = newValue; scene?.invalidateHitIndex(); scene?.needsLayout = true }
    }
    var sublayerTransform: CATransform3D {
        get { layer.sublayerTransform }
        set { layer.sublayerTransform = newValue; scene?.invalidateHitIndex(); scene?.needsLayout = true }
    }
    var isHidden: Bool {
        get { layer.isHidden }
        set { layer.isHidden = newValue; scene?.validateInput() }
    }
    var opacity: Float {
        get { layer.opacity }
        set { layer.opacity = newValue; scene?.validateInput() }
    }
    var clipsChildren: Bool {
        get { layer.masksToBounds }
        set {
            guard layer.masksToBounds != newValue else { return }
            layer.masksToBounds = newValue
            scene?.needsLayout = true
        }
    }
    var zIndex: Int = 0 {
        didSet {
            layer.zPosition = CGFloat(zIndex)
            parent?.sortChildren()
            scene?.needsLayout = true
        }
    }

    init(id: AnyHashable, layer: SimpleLayer = SimpleLayer()) {
        self.id = id
        self.layer = layer
        layer.anchorPoint = .zero
        layer.edgeAntialiasingMask = []
    }

    func setChildren(_ children: [ReferenceChatLayerNode]) throws {
        if self.children.count == children.count && zip(self.children, children).allSatisfy({ $0 === $1 }) { return }
        for child in children {
            if let parent = child.parent, parent !== self { throw ReferenceChatLayerTreeError.alreadyParented }
            var ancestor: ReferenceChatLayerNode? = self
            while let node = ancestor {
                if node === child { throw ReferenceChatLayerTreeError.cycle }
                ancestor = node.parent
            }
        }
        var root = self
        while let parent = root.parent { root = parent }
        var identifiers = Set<AnyHashable>()
        var objects = Set<ObjectIdentifier>()
        func validate(_ node: ReferenceChatLayerNode) throws {
            guard objects.insert(ObjectIdentifier(node)).inserted else { throw ReferenceChatLayerTreeError.cycle }
            guard identifiers.insert(node.id).inserted else { throw ReferenceChatLayerTreeError.duplicateIdentifier }
            for child in node === self ? children : node.children { try validate(child) }
        }
        try validate(root)
        let retained = Set(children.map(ObjectIdentifier.init))
        for child in self.children where !retained.contains(ObjectIdentifier(child)) {
            child.parent = nil
            child.attach(to: nil)
            child.layer.removeFromSuperlayer()
        }
        let previousLayers = Set(self.children.map { ObjectIdentifier($0.layer) })
        let contentCount = (layer.sublayers ?? []).filter { !previousLayers.contains(ObjectIdentifier($0)) }.count
        self.children = children
        for (offset, child) in children.enumerated() {
            let index = contentCount + offset
            child.parent = self
            child.attach(to: scene)
            if (layer.sublayers?.count ?? 0) <= index || layer.sublayers?[index] !== child.layer {
                layer.insertSublayer(child.layer, at: UInt32(index))
            }
        }
        sortChildren()
        scene?.treeDidChange()
    }

    fileprivate func sortChildren() {
        scene?.invalidateHitIndex()
        orderedChildren = children.enumerated().sorted {
            $0.element.zIndex == $1.element.zIndex ? $0.offset < $1.offset : $0.element.zIndex < $1.element.zIndex
        }.map(\.element)
    }

    func attach(to scene: ReferenceChatLayerSceneView?) {
        guard self.scene !== scene else { return }
        self.scene = scene
        if let scene {
            updateOwnScale(scene.backingScaleFactor)
            onWindowKeyChanged?(scene.window?.isKeyWindow ?? false)
        }
        for child in children { child.attach(to: scene) }
    }

    func updateOwnScale(_ scale: CGFloat) {
        if layer.contentsScale != scale {
            layer.contentsScale = scale
            layer.setNeedsDisplay()
        }
    }

    fileprivate func updateScale(_ scale: CGFloat) {
        updateOwnScale(scale)
        for child in children { child.updateScale(scale) }
    }

    var isVisible: Bool {
        return !isHidden && opacity > 0 && (parent?.isVisible ?? true)
    }

    var isEffectivelyEnabled: Bool { isEnabled && (parent?.isEffectivelyEnabled ?? true) }

    fileprivate func contains(_ point: NSPoint) -> Bool {
        return hitRegion?(point) ?? layer.bounds.contains(point)
    }

    fileprivate func allowsHit(at point: NSPoint, from root: CALayer) -> Bool {
        guard isVisible, contains(layer.convert(point, from: root)) else { return false }
        var current: ReferenceChatLayerNode? = self
        while let ancestor = current {
            if ancestor.clipsChildren {
                let local = ancestor.layer.convert(point, from: root)
                guard ancestor.layer.bounds.contains(local) else { return false }
                let radius = ancestor.layer.cornerRadius
                if radius > 0 && !CGPath(roundedRect: ancestor.layer.bounds, cornerWidth: radius, cornerHeight: radius, transform: nil).contains(local) { return false }
            }
            current = ancestor.parent
        }
        return true
    }

    fileprivate func accessibilityHit(at point: NSPoint, from root: CALayer) -> ReferenceChatLayerAccessibilityElement? {
        guard isVisible else { return nil }
        let local = layer.convert(point, from: root)
        if clipsChildren && !layer.bounds.contains(local) { return nil }
        for child in orderedChildren.reversed() {
            if let result = child.accessibilityHit(at: point, from: root) { return result }
        }
        guard accessibilityRole != nil, layer.bounds.contains(local) else { return nil }
        if accessibilityElement == nil { accessibilityElement = ReferenceChatLayerAccessibilityElement(node: self) }
        return accessibilityElement
    }

    fileprivate func accessibleChildren() -> [ReferenceChatLayerAccessibilityElement] {
        guard isVisible else { return [] }
        return orderedChildren.flatMap { node -> [ReferenceChatLayerAccessibilityElement] in
            guard node.isVisible else { return [] }
            if node.accessibilityRole != nil {
                if node.accessibilityElement == nil { node.accessibilityElement = ReferenceChatLayerAccessibilityElement(node: node) }
                return [node.accessibilityElement!]
            }
            return node.accessibleChildren()
        }
    }
}

class ReferenceChatLayerSceneView: View {
    private final class State {
        let root: ReferenceChatLayerNode
        let canRelease: Bool
        var selectableTextNodeIds: [AnyHashable] = []
        var geometryVersion: UInt64 = 0
        weak var focusedNode: ReferenceChatLayerNode?
        var nodes: [AnyHashable: ReferenceChatLayerNode] = [:]
        var hitIndex: [(node: ReferenceChatLayerNode, frame: NSRect)] = []
        var hitIndexIsValid: Bool = false
        var captures: [Int: ReferenceChatLayerNode] = [:]
        var blockedButtons: Set<Int> = []
        var hovered: [ReferenceChatLayerNode] = []
        var hoverGeneration: Int = 0
        var inputGeneration: Int = 0
        var lastPointer: NSPoint? = nil
        var pointerArea: NSTrackingArea? = nil
        var toolTipNodes: [ReferenceChatLayerTextNode]? = nil
        init(root: ReferenceChatLayerNode, canRelease: Bool = false) { self.root = root; self.canRelease = canRelease }
    }

    private var storedState: State?
    private var state: State { storedState! }
    var hasLayerContent: Bool { storedState != nil }
    var root: ReferenceChatLayerNode {
        if storedState == nil {
            let root = ReferenceChatLayerNode(id: UUID())
            storedState = State(root: root, canRelease: true)
            installRoot()
            observeWindow(window)
            updateTrackingAreas()
            needsLayout = true
        }
        return state.root
    }
    var selectableTextNodeIds: [AnyHashable] {
        get { storedState?.selectableTextNodeIds ?? [] }
        set {
            if storedState == nil && newValue.isEmpty { return }
            _ = root
            let current = state
            if current.selectableTextNodeIds != newValue { clearBubbleSelection() }
            guard storedState === current else { return }
            current.selectableTextNodeIds = newValue
        }
    }
    private(set) var geometryVersion: UInt64 {
        get { storedState?.geometryVersion ?? 0 }
        set { state.geometryVersion = newValue }
    }
    private(set) var focusedNode: ReferenceChatLayerNode? {
        get { storedState?.focusedNode }
        set { state.focusedNode = newValue }
    }
    private var nodes: [AnyHashable: ReferenceChatLayerNode] {
        _read { yield state.nodes }
        _modify { yield &state.nodes }
    }
    private var hitIndex: [(node: ReferenceChatLayerNode, frame: NSRect)] {
        _read { yield state.hitIndex }
        _modify { yield &state.hitIndex }
    }
    private var hitIndexIsValid: Bool {
        _read { yield state.hitIndexIsValid }
        _modify { yield &state.hitIndexIsValid }
    }
    private var captures: [Int: ReferenceChatLayerNode] {
        _read { yield state.captures }
        _modify { yield &state.captures }
    }
    private var blockedButtons: Set<Int> {
        _read { yield state.blockedButtons }
        _modify { yield &state.blockedButtons }
    }
    private var hovered: [ReferenceChatLayerNode] {
        _read { yield state.hovered }
        _modify { yield &state.hovered }
    }
    private var hoverGeneration: Int {
        _read { yield state.hoverGeneration }
        _modify { yield &state.hoverGeneration }
    }
    private var inputGeneration: Int {
        _read { yield state.inputGeneration }
        _modify { yield &state.inputGeneration }
    }
    private var lastPointer: NSPoint? {
        _read { yield state.lastPointer }
        _modify { yield &state.lastPointer }
    }
    private var pointerArea: NSTrackingArea? {
        _read { yield state.pointerArea }
        _modify { yield &state.pointerArea }
    }
    private var toolTipNodes: [ReferenceChatLayerTextNode]? {
        _read { yield state.toolTipNodes }
        _modify { yield &state.toolTipNodes }
    }

    override var isHidden: Bool {
        didSet { if isHidden { cancelInput() } }
    }

    required convenience init(frame frameRect: NSRect) {
        self.init(frame: frameRect, ownedRoot: ReferenceChatLayerNode(id: UUID()))
    }

    init(frame frameRect: NSRect, ownedRoot: ReferenceChatLayerNode) {
        precondition(ownedRoot.parent == nil && ownedRoot.scene == nil)
        storedState = State(root: ownedRoot)
        super.init(frame: frameRect)
        installRoot()
    }

    init(frame frameRect: NSRect, deferred: Bool) {
        super.init(frame: frameRect)
        if !deferred { _ = root }
    }

    private func installRoot() {
        let root = state.root
        layer?.addSublayer(root.layer)
        root.attach(to: self)
        treeDidChange()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @discardableResult
    func releaseEmptyLayerContent() -> Bool {
        guard let previous = storedState, previous.canRelease, previous.root.children.isEmpty,
              previous.root.layer.sublayers?.isEmpty != false, previous.selectableTextNodeIds.isEmpty else { return false }
        cancelInput()
        guard storedState === previous, previous.root.children.isEmpty,
              previous.root.layer.sublayers?.isEmpty != false, previous.selectableTextNodeIds.isEmpty else { return false }
        if let area = previous.pointerArea { removeTrackingArea(area) }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window)
        previous.root.attach(to: nil)
        previous.root.layer.removeFromSuperlayer()
        storedState = nil
        return true
    }

    func node(id: AnyHashable) -> ReferenceChatLayerNode? { storedState?.nodes[id] }

    override func layout() {
        super.layout()
        guard let current = storedState else { return }
        current.root.layer.frame = bounds
        invalidateHitIndex()
        toolTipNodes?.forEach { $0.synchronizeLinkToolTips(force: false) }
        if let point = lastPointer {
            updateHover(at: point)
            guard storedState === current else { return }
            if let node = hovered.last as? ReferenceChatLayerTextNode {
                node.refreshLinkHover(at: node.layer.convert(point, from: root.layer))
            }
        }
    }

    func registerToolTipNode(_ node: ReferenceChatLayerTextNode) {
        guard hasLayerContent, node.scene === self else { return }
        if toolTipNodes?.contains(where: { $0 === node }) != true {
            if toolTipNodes == nil { toolTipNodes = [] }
            toolTipNodes?.append(node)
        }
    }

    func unregisterToolTipNode(_ node: ReferenceChatLayerTextNode) {
        guard hasLayerContent else { return }
        toolTipNodes?.removeAll(where: { $0 === node })
        if toolTipNodes?.isEmpty == true { toolTipNodes = nil }
    }

    override func removeAllToolTips() {
        super.removeAllToolTips()
        storedState?.toolTipNodes?.forEach { $0.didRemoveLinkToolTips() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        storedState?.root.updateScale(backingScaleFactor)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if hasLayerContent && window !== newWindow {
            cancelInput()
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window)
            if hasLayerContent { observeWindow(newWindow) }
        }
    }

    private func observeWindow(_ window: NSWindow?) {
        guard let window else { return }
        NotificationCenter.default.addObserver(self, selector: #selector(windowKeyChanged), name: NSWindow.didResignKeyNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(windowKeyChanged), name: NSWindow.didBecomeKeyNotification, object: window)
    }

    @objc private func windowKeyChanged() {
        guard let current = storedState else { return }
        let isKey = window?.isKeyWindow ?? false
        if !isKey { cancelInput(preservingFocus: true) }
        guard storedState === current else { return }
        for node in nodes.values {
            guard storedState === current else { return }
            if node.scene === self { node.onWindowKeyChanged?(isKey) }
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        storedState?.root.updateScale(backingScaleFactor)
        windowKeyChanged()
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard hasLayerContent else { return }
        let needsTracking = window != nil && !visibleRect.isEmpty
        guard needsTracking != (pointerArea != nil) else { return }
        if let pointerArea {
            removeTrackingArea(pointerArea)
            self.pointerArea = nil
        }
        guard needsTracking else { return }
        let area = NSTrackingArea(rect: .zero, options: [.activeInActiveApp, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved, .cursorUpdate], owner: self)
        addTrackingArea(area)
        pointerArea = area
    }

    fileprivate func invalidateHitIndex() {
        guard hasLayerContent else { return }
        geometryVersion &+= 1
        if hitIndexIsValid { hitIndex.removeAll(keepingCapacity: true) }
        hitIndexIsValid = false
    }

    fileprivate func treeDidChange() {
        guard let current = storedState else { return }
        invalidateHitIndex()
        var updated: [AnyHashable: ReferenceChatLayerNode] = [:]
        func visit(_ node: ReferenceChatLayerNode) {
            updated[node.id] = node
            for child in node.children { visit(child) }
        }
        visit(current.root)
        nodes = updated
        validateInput()
        needsLayout = true
    }

    fileprivate func validateInput() {
        guard let current = storedState else { return }
        for (button, node) in captures where node.scene !== self || !node.isVisible || !node.isEffectivelyEnabled || isHiddenOrHasHiddenAncestor {
            guard captures[button] === node else { continue }
            captures.removeValue(forKey: button)
            blockedButtons.insert(button)
            _ = node.onPointer?(event(.cancelled, node: nil, point: lastPointer ?? .zero, button: button))
            guard storedState === current else { return }
        }
        if let node = focusedNode, node.scene !== self || !node.isVisible || !node.isEffectivelyEnabled || !node.acceptsKeyboardFocus {
            focus(nil)
            guard storedState === current else { return }
        }
        if let point = lastPointer { updateHover(at: point) }
    }

    var hasActiveInput: Bool { hasLayerContent && (!captures.isEmpty || focusedNode != nil || lastPointer != nil || !hovered.isEmpty) }

    func cancelInput(preservingFocus: Bool = false) {
        guard let current = storedState else { return }
        let previous = captures
        captures.removeAll()
        blockedButtons.formUnion(previous.keys)
        lastPointer = nil
        if !preservingFocus { focus(nil) }
        guard storedState === current else { return }
        for (button, node) in previous {
            _ = node.onPointer?(event(.cancelled, node: nil, point: .zero, button: button))
            guard storedState === current else { return }
        }
        updateHover(at: nil)
    }

    func focus(_ node: ReferenceChatLayerNode?) {
        guard let current = storedState else { return }
        guard focusedNode !== node else { return }
        if let node {
            guard node.scene === self, node.isVisible, node.isEffectivelyEnabled, node.acceptsKeyboardFocus else { return }
        }
        let previous = focusedNode
        focusedNode = node
        previous?.onFocusChanged?(false)
        guard storedState === current else { return }
        if focusedNode === node { node?.onFocusChanged?(true) }
    }

    override func resignFirstResponder() -> Bool {
        focus(nil)
        return super.resignFirstResponder()
    }

    func hitNode(at point: NSPoint) -> ReferenceChatLayerNode? {
        guard let current = storedState else { return nil }
        guard !isHiddenOrHasHiddenAncestor, bounds.contains(point) else { return nil }
        if !hitIndexIsValid {
            hitIndex.removeAll(keepingCapacity: true)
            func visit(_ node: ReferenceChatLayerNode) {
                if node.acceptsPointerEvents {
                    hitIndex.append((node, node.layer.convert(node.layer.bounds, to: root.layer)))
                }
                for child in node.orderedChildren { visit(child) }
            }
            visit(root)
            hitIndexIsValid = true
        }
        for entry in hitIndex.reversed() where entry.node.hitRegion != nil || entry.frame.contains(point) {
            let matches = entry.node.allowsHit(at: point, from: current.root.layer)
            guard storedState === current else { return nil }
            if matches, entry.node.scene === self, entry.node.acceptsPointerEvents { return entry.node }
        }
        return nil
    }

    private func event(_ kind: ReferenceChatLayerPointerEvent.Kind, node: ReferenceChatLayerNode?, point: NSPoint, button: Int = 0, native: NSEvent? = nil) -> ReferenceChatLayerPointerEvent {
        var clickCount = 1
        if let native {
            switch native.type {
            case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged, .otherMouseDown, .otherMouseUp, .otherMouseDragged:
                clickCount = native.clickCount
            default:
                break
            }
        }
        let location: NSPoint
        if let node, let current = storedState, node.scene === self {
            location = node.layer.convert(point, from: current.root.layer)
        } else {
            location = .zero
        }
        return ReferenceChatLayerPointerEvent(kind: kind, location: location, sceneLocation: point, button: button, clickCount: clickCount, modifiers: native?.modifierFlags ?? [], nativeEvent: native)
    }

    private func path(to node: ReferenceChatLayerNode?) -> [ReferenceChatLayerNode] {
        var result: [ReferenceChatLayerNode] = []
        var current = node
        while let node = current {
            result.append(node)
            current = node.parent
        }
        return result.reversed()
    }

    func updateHover(at point: NSPoint?) {
        guard let current = storedState else { return }
        hoverGeneration += 1
        let generation = hoverGeneration
        let target = point.flatMap(hitNode)
        guard storedState === current else { return }
        let next = path(to: target?.isEffectivelyEnabled == true ? target : nil)
        let previous = hovered
        hovered = next
        let common = zip(previous, next).prefix { $0 === $1 }.count
        for node in previous.dropFirst(common).reversed() {
            guard storedState === current, hoverGeneration == generation else { return }
            _ = node.onPointer?(event(.exited, node: node.scene === self ? node : nil, point: point ?? .zero))
        }
        for node in next.dropFirst(common) {
            guard storedState === current, hoverGeneration == generation else { return }
            _ = node.onPointer?(event(.entered, node: node, point: point ?? .zero))
        }
        guard storedState === current, hoverGeneration == generation else { return }
        updatePointerCursor(next.reversed().compactMap(\.cursor).first ?? .arrow, at: point)
    }

    func updatePointerCursor(_ cursor: NSCursor, at point: NSPoint?) {
        cursor.set()
    }

    @discardableResult func handlePointer(_ kind: ReferenceChatLayerPointerEvent.Kind, at point: NSPoint, button: Int = 0, native: NSEvent? = nil) -> Bool {
        guard let current = storedState else { return false }
        inputGeneration += 1
        let generation = inputGeneration
        if isHiddenOrHasHiddenAncestor { cancelInput() }
        guard storedState === current else { return true }
        lastPointer = point
        updateHover(at: point)
        guard storedState === current, inputGeneration == generation else { return true }
        if kind == .up {
            if blockedButtons.remove(button) != nil { return true }
            guard let target = captures.removeValue(forKey: button) else { return false }
            _ = target.onPointer?(event(kind, node: target, point: point, button: button, native: native))
            return true
        }
        if kind == .dragged {
            if blockedButtons.contains(button) { return true }
            guard let target = captures[button] else { return false }
            _ = target.onPointer?(event(kind, node: target, point: point, button: button, native: native))
            return true
        }
        if kind == .down {
            blockedButtons.remove(button)
            if let previous = captures.removeValue(forKey: button) {
                _ = previous.onPointer?(event(.cancelled, node: previous, point: point, button: button, native: native))
                guard storedState === current, inputGeneration == generation else { return true }
            }
        }
        let target = hitNode(at: point)
        guard storedState === current, inputGeneration == generation else { return true }
        guard let target else { return false }
        if !target.isEffectivelyEnabled {
            if kind == .down { blockedButtons.insert(button) }
            return true
        }
        for node in path(to: target).reversed() where node.scene === self {
            let handled = node.onPointer?(event(kind, node: node, point: point, button: button, native: native)) == true
            guard storedState === current, inputGeneration == generation else { return true }
            if handled {
                if kind == .down {
                    if node.scene === self && node.isVisible && node.isEffectivelyEnabled {
                        captures[button] = node
                        if node.acceptsKeyboardFocus {
                            focus(node)
                            guard storedState === current, focusedNode === node else { return true }
                            window?.makeFirstResponder(self)
                        }
                    } else {
                        blockedButtons.insert(button)
                        _ = node.onPointer?(event(.cancelled, node: nil, point: point, button: button, native: native))
                    }
                }
                return true
            }
        }
        return false
    }

    private var focusCandidates: [ReferenceChatLayerNode] {
        guard hasLayerContent else { return [] }
        guard !isHiddenOrHasHiddenAncestor else { return [] }
        var candidates: [ReferenceChatLayerNode] = []
        func visit(_ node: ReferenceChatLayerNode) {
            guard node.isVisible, node.isEffectivelyEnabled else { return }
            if node.acceptsKeyboardFocus { candidates.append(node) }
            for child in node.orderedChildren { visit(child) }
        }
        visit(root)
        return candidates
    }

    @discardableResult func moveFocus(backward: Bool) -> Bool {
        let candidates = focusCandidates
        guard !candidates.isEmpty else { return false }
        let index = focusedNode.flatMap { current in candidates.firstIndex { $0 === current } }
        let next = index.map { $0 + (backward ? -1 : 1) } ?? (backward ? candidates.count - 1 : 0)
        guard candidates.indices.contains(next) else { return false }
        let target = candidates[next]
        focus(target)
        guard focusedNode === target, target.scene === self else { return true }
        window?.makeFirstResponder(self)
        return true
    }

    private var keyboardTarget: ReferenceChatLayerNode? {
        guard !isHiddenOrHasHiddenAncestor, let node = focusedNode, node.scene === self, node.isVisible, node.isEffectivelyEnabled else { return nil }
        return node
    }

    @objc func copy(_ sender: Any?) { _ = keyboardTarget?.onCommand?(#selector(copy(_:))) }
    @objc override func selectAll(_ sender: Any?) { _ = keyboardTarget?.onCommand?(#selector(selectAll(_:))) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.command, .option, .control]) == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "c": if keyboardTarget?.onCommand?(#selector(copy(_:))) == true { return true }
            case "a": if keyboardTarget?.onCommand?(#selector(selectAll(_:))) == true { return true }
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func menu(for native: NSEvent) -> NSMenu? {
        guard let current = storedState else { return super.menu(for: native) }
        let point = convert(native.locationInWindow, from: nil)
        guard let target = hitNode(at: point), target.isEffectivelyEnabled else { return super.menu(for: native) }
        for node in path(to: target).reversed() {
            guard storedState === current, node.scene === self else { return nil }
            let menu = node.menu?(event(.down, node: node, point: point, button: 1, native: native))
            guard storedState === current, node.scene === self else { return nil }
            if let menu { return menu }
        }
        return super.menu(for: native)
    }

    override var acceptsFirstResponder: Bool { !focusCandidates.isEmpty }
    override var canBecomeKeyView: Bool { acceptsFirstResponder }
    override func becomeFirstResponder() -> Bool {
        if focusedNode == nil { focus(focusCandidates.first) }
        return super.becomeFirstResponder()
    }
    override func keyDown(with event: NSEvent) {
        guard hasLayerContent else { super.keyDown(with: event); return }
        if event.keyCode == 48 {
            let backward = event.modifierFlags.contains(.shift)
            if moveFocus(backward: backward) { return }
            if backward { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
            return
        }
        if keyboardTarget?.onKeyDown?(event) != true { super.keyDown(with: event) }
    }
    override func mouseDown(with event: NSEvent) {
        if !handlePointer(.down, at: convert(event.locationInWindow, from: nil), native: event) { super.mouseDown(with: event) }
    }
    override func mouseDragged(with event: NSEvent) {
        if !handlePointer(.dragged, at: convert(event.locationInWindow, from: nil), native: event) { super.mouseDragged(with: event) }
    }
    override func mouseUp(with event: NSEvent) {
        if !handlePointer(.up, at: convert(event.locationInWindow, from: nil), native: event) { super.mouseUp(with: event) }
    }
    override func rightMouseDown(with event: NSEvent) {
        if !handlePointer(.down, at: convert(event.locationInWindow, from: nil), button: 1, native: event) { super.rightMouseDown(with: event) }
    }
    override func rightMouseDragged(with event: NSEvent) {
        if !handlePointer(.dragged, at: convert(event.locationInWindow, from: nil), button: 1, native: event) { super.rightMouseDragged(with: event) }
    }
    override func otherMouseDown(with event: NSEvent) {
        if !handlePointer(.down, at: convert(event.locationInWindow, from: nil), button: event.buttonNumber, native: event) { super.otherMouseDown(with: event) }
    }
    override func otherMouseDragged(with event: NSEvent) {
        if !handlePointer(.dragged, at: convert(event.locationInWindow, from: nil), button: event.buttonNumber, native: event) { super.otherMouseDragged(with: event) }
    }
    override func otherMouseUp(with event: NSEvent) {
        if !handlePointer(.up, at: convert(event.locationInWindow, from: nil), button: event.buttonNumber, native: event) { super.otherMouseUp(with: event) }
    }
    override func rightMouseUp(with event: NSEvent) {
        if !handlePointer(.up, at: convert(event.locationInWindow, from: nil), button: 1, native: event) { super.rightMouseUp(with: event) }
    }
    override func mouseMoved(with event: NSEvent) {
        guard hasLayerContent else { super.mouseMoved(with: event); return }
        _ = handlePointer(.moved, at: convert(event.locationInWindow, from: nil), native: event)
    }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) {
        guard hasLayerContent else { super.mouseExited(with: event); return }
        lastPointer = nil
        updateHover(at: nil)
    }
    override func cursorUpdate(with event: NSEvent) { mouseMoved(with: event) }

    override func isAccessibilityElement() -> Bool {
        guard hasLayerContent else { return super.isAccessibilityElement() }
        return TGUIKitAccessibility.isEnabled && !isHiddenOrHasHiddenAncestor && (!root.accessibleChildren().isEmpty || super.isAccessibilityElement())
    }
    override func accessibilityRole() -> NSAccessibility.Role? { hasLayerContent ? .group : super.accessibilityRole() }

    override func accessibilityChildren() -> [Any]? {
        guard hasLayerContent else { return super.accessibilityChildren() }
        guard TGUIKitAccessibility.isEnabled, !isHiddenOrHasHiddenAncestor else { return nil }
        return root.accessibleChildren() + (super.accessibilityChildren() ?? [])
    }
    override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        guard let window else { return super.accessibilityHitTest(point) }
        let local = convert(window.convertPoint(fromScreen: point), from: nil)
        if hasLayerContent, TGUIKitAccessibility.isEnabled, !isHiddenOrHasHiddenAncestor, bounds.contains(local), let result = root.accessibilityHit(at: local, from: root.layer) { return result }
        return super.accessibilityHitTest(point)
    }
}

fileprivate final class ReferenceChatLayerAccessibilityElement: NSAccessibilityElement {
    private weak var node: ReferenceChatLayerNode?
    init(node: ReferenceChatLayerNode) { self.node = node; super.init() }
    override func isAccessibilityElement() -> Bool {
        guard TGUIKitAccessibility.isEnabled, let node, let scene = node.scene, !scene.isHiddenOrHasHiddenAncestor else { return false }
        return node.isVisible && node.accessibilityRole != nil
    }
    override func accessibilityRole() -> NSAccessibility.Role? { node?.accessibilityRole }
    override func accessibilityLabel() -> String? { node?.accessibilityLabel }
    override func accessibilityValue() -> Any? { node?.accessibilityValue }
    override func isAccessibilityEnabled() -> Bool { node?.isEffectivelyEnabled ?? false }
    override func accessibilityChildren() -> [Any]? { node?.accessibleChildren() }
    override func accessibilityParent() -> Any? {
        guard let node, let scene = node.scene else { return nil }
        var parent = node.parent
        while let value = parent {
            if value.accessibilityRole != nil {
                if value.accessibilityElement == nil { value.accessibilityElement = ReferenceChatLayerAccessibilityElement(node: value) }
                return value.accessibilityElement
            }
            parent = value.parent
        }
        return NSAccessibility.unignoredAncestor(of: scene)
    }
    override func accessibilityFrame() -> NSRect {
        guard let node, let scene = node.scene, let window = scene.window else { return .zero }
        let local = node.layer.convert(node.layer.bounds, to: scene.root.layer)
        return window.convertToScreen(scene.convert(local, to: nil))
    }
    override func accessibilityPerformPress() -> Bool {
        guard isAccessibilityElement(), isAccessibilityEnabled() else { return false }
        return node?.onAccessibilityPress?() ?? false
    }
}

extension ReferenceChatLayerSceneView {
    func clearBubbleSelection() {}
}
final class ReferenceChatLayerTextNode: ReferenceChatLayerNode {
    func synchronizeLinkToolTips(force: Bool) {}
    func didRemoveLinkToolTips() {}
    func refreshLinkHover(at point: NSPoint) {}
}
final class ReferenceRowInteractionView: ReferenceChatLayerSceneView {
    weak var layerHitBackground: NSView?
    required init(frame: NSRect) { super.init(frame: frame, deferred: true) }
    required init?(coder: NSCoder) { fatalError() }
    override func hitNode(at point: NSPoint) -> ReferenceChatLayerNode? {
        guard hasLayerContent else { return nil }
        guard let native = super.hitTest(convert(point, to: superview)) else { return nil }
        guard native === self || native === layerHitBackground else { return nil }
        return super.hitNode(at: point)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let native = super.hitTest(point)
        guard let native, hasLayerContent, native === self || native === layerHitBackground,
              super.hitNode(at: convert(point, from: superview)) != nil else { return native }
        return self
    }
    override func updatePointerCursor(_ cursor: NSCursor, at point: NSPoint?) {
        if let point, let native = super.hitTest(convert(point, to: superview)), native !== self, native !== layerHitBackground { return }
        super.updatePointerCursor(cursor, at: point)
    }
}
