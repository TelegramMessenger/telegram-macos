import Cocoa
import TGUIKit
import TelegramTheme
import LiteHTML
import HTMLScript
import HTML3D
import SwiftSignalKit
import KeyboardKey
import TwidgetRenderer

private struct HTMLTextPosition: Comparable {
    let fragment: Int
    let offset: Int

    static func < (lhs: HTMLTextPosition, rhs: HTMLTextPosition) -> Bool {
        return lhs.fragment != rhs.fragment ? lhs.fragment < rhs.fragment : lhs.offset < rhs.offset
    }
}

public final class HTMLBubbleView: View, HTMLBubbleVisibility, HorizontalScrollConsuming {
    public static let scrollIndicatorInset: CGFloat = 8

    public private(set) var state: HTMLBubbleState?
    private var bubbleAppearance: HTMLBubbleAppearance?
    private var maxWidth: CGFloat = 0
    private var observer: Int?
    private var tileLayers: [CALayer] = []
    private var currentKey: String?
    private let renderQueue = DispatchQueue(label: "org.telegram.HTMLBubbleView", qos: .userInitiated, target: HTMLBubbleRenderer.queue)
    private var rendering = false
    private var renderAgain = false
    private var trackingArea: NSTrackingArea?
    private var hoverPoint: CGPoint?
    private var pointer = false
    private var lastVisible = false
    private var fragments: [LHTextFragment] = []
    private var fragmentsKey: String?
    private var selection: (anchor: HTMLTextPosition, focus: HTMLTextPosition)?
    private let selectionLayer = CAShapeLayer()
    private let contentLayer = CALayer()
    private let tilesLayer = CALayer()
    private var currentTiles: [HTMLBubbleTile] = []
    private var currentRendering: HTMLBubbleRendering?
    private var twidgetView: NSView?
    private let twidgetSnapshotLayer = CALayer()
    private var shownTwidgetSnapshot: HTMLTwidgetSnapshot?
    private lazy var twidgetContainer: HTMLTwidgetContainer = {
        let view = HTMLTwidgetContainer(frame: .zero)
        view.wantsLayer = true
        return view
    }()
    private var currentSize: CGSize = .zero
    private var activeTransition: HTMLBubbleTransition?
    private lazy var magicStage: MagicMoveStage = {
        let stage = MagicMoveStage(host: tilesLayer)
        stage.onFinish = { [weak self] in
            self?.finishMagicMove()
        }
        return stage
    }()
    private let indicatorLayer = CALayer()
    private var contentExtent: CGFloat = 0
    private var scrollX: CGFloat = 0
    private var appliedVersion: Int = -1
    private let statsOverlay = HTMLBubbleStatsOverlay()
    private var statsTimer: SwiftSignalKit.Timer?
    private var sceneLayer: CAMetalLayer?
    private weak var sceneSession: HTML3DSession?
    private var sceneRect: CGRect = .null
    private weak var sceneWindow: Window?

    public var onContentChanged: ((_ size: NSSize, _ animated: Bool) -> Void)?

    struct PendingTransition {
        let kind: String
        let top: CGFloat
        let unchangedBottom: CGFloat
        let pinned: Bool
    }

    static let resizeDuration: CFTimeInterval = 0.2

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        backgroundColor = .clear
        layer?.isOpaque = false
        layer?.masksToBounds = true
        selectionLayer.zPosition = 2
        contentLayer.addSublayer(tilesLayer)
        contentLayer.addSublayer(selectionLayer)
        layer?.addSublayer(contentLayer)
        indicatorLayer.cornerRadius = 1.5
        indicatorLayer.isHidden = true
        layer?.addSublayer(indicatorLayer)
        layer?.addSublayer(statsOverlay.layer)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        statsTimer?.invalidate()
        detach()
    }

    public var crossfadesNextState = false
    private let crossfadeLayer = CALayer()
    private var crossfadeToken = 0

    private func beginCrossfade(from snapshot: HTMLTwidgetSnapshot) {
        crossfadeToken += 1
        let token = crossfadeToken
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        crossfadeLayer.removeAllAnimations()
        crossfadeLayer.anchorPoint = .zero
        crossfadeLayer.frame = contentBounds
        crossfadeLayer.zPosition = 5
        crossfadeLayer.opacity = 1
        snapshot.install(in: crossfadeLayer)
        if crossfadeLayer.superlayer == nil {
            layer?.addSublayer(crossfadeLayer)
        }
        CATransaction.commit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.crossfadeToken == token {
                self?.endCrossfade()
            }
        }
    }

    private func endCrossfadeIfReady() {
        if crossfadeLayer.superlayer != nil, state?.twidgetReady == true {
            endCrossfade()
        }
    }

    private func endCrossfade() {
        guard crossfadeLayer.superlayer != nil else {
            return
        }
        crossfadeToken += 1
        let token = crossfadeToken
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = crossfadeLayer.presentation()?.opacity ?? 1
        fade.toValue = 0
        fade.duration = 0.2
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        CATransaction.setCompletionBlock { [weak self] in
            guard let self = self, self.crossfadeToken == token else {
                return
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.crossfadeLayer.removeAllAnimations()
            self.crossfadeLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            self.crossfadeLayer.removeFromSuperlayer()
            CATransaction.commit()
        }
        crossfadeLayer.removeAllAnimations()
        crossfadeLayer.opacity = 0
        crossfadeLayer.add(fade, forKey: "crossfade")
        CATransaction.commit()
    }

    public func update(state: HTMLBubbleState, appearance: HTMLBubbleAppearance, maxWidth: CGFloat, rendering: HTMLBubbleRendering?) {
        let crossfade = crossfadesNextState
        crossfadesNextState = false
        if self.state !== state {
            if crossfade, window != nil, let snapshot = self.state?.captureTwidgetSnapshot() {
                beginCrossfade(from: snapshot)
            }
            detach()
            self.state = state
            state.visibility = self
            observer = state.addObserver { [weak self] in
                self?.contentDidChange()
            }
            currentKey = nil
            appliedVersion = -1
            removeTiles()
            clearSelection()
            fragments = []
            fragmentsKey = nil
            scrollX = 0
            contentExtent = 0
            statsOverlay.reset()
        }
        if self.maxWidth != maxWidth || self.bubbleAppearance != appearance {
            clearSelection()
        }
        if state.engine.usesWidgetSandbox {
            bubbleAppearance = appearance
            self.maxWidth = maxWidth
            attachTwidget()
            updateVisibility(force: true)
            return
        }
        detachTwidget()
        self.bubbleAppearance = appearance
        self.maxWidth = maxWidth
        let key = state.renderKey(width: maxWidth, appearance: appearance, scale: backingScale)
        if let rendering = rendering, rendering.key == key {
            apply(rendering, transition: nil)
            if state.scene3D != nil {
                updateScene(rendering.document?.bounds(matching: "[data-3d]") ?? .null)
            }
        } else if currentKey != key {
            scheduleRender()
        }
        updateVisibility(force: true)
    }

    private func detach() {
        removeScene()
        if let state = state {
            if state.twidgetHostChangedOwner === self {
                state.twidgetHostChanged = nil
                state.twidgetHostChangedOwner = nil
            }
            if let observer = observer {
                state.removeObserver(observer)
            }
            if state.visibility === self {
                state.visibility = nil
            }
        }
        observer = nil
        state = nil
        detachTwidget()
    }

    private var backingScale: CGFloat {
        return window?.backingScaleFactor ?? System.backingScale
    }

    private func contentDidChange() {
        if state?.engine.usesWidgetSandbox == true {
            reportTwidgetSize()
            return
        }
        scheduleRender()
    }

    private func attachTwidget() {
        guard let state = state, let appearance = bubbleAppearance else {
            return
        }
        let bubble = state.twidgetBubble(appearance: appearance, width: maxWidth)
        if let color = appearance.textSelectionColor {
            state.twidgetSelectionColor = color
        }
        state.twidgetSelectionChanged = { [weak self] selected in
            if selected, let self = self {
                self.window?.makeFirstResponder(self)
            }
        }
        state.twidgetHostChangedOwner = self
        state.visibility = self
        state.twidgetHostChanged = { [weak self] in
            self?.attachTwidgetHost()
        }
        attachTwidgetSpace()
        bubble.slot.setNeedsUpdate()
        attachTwidgetHost()
    }

    private func attachTwidgetSpace() {
        if let state = state, let table = enclosingScrollView as? TableView {
            _ = HTMLTwidgetTableSpace.space(for: table, engine: state.engine)
        }
    }

    private func updateTwidgetSnapshot() {
        guard let state = state, state.engine.usesWidgetSandbox else {
            return
        }
        if !state.twidgetReady, let snapshot = state.twidgetSnapshot {
            if twidgetContainer.superview !== self {
                addSubview(twidgetContainer)
            }
            twidgetContainer.frame = contentBounds
            twidgetView = twidgetContainer
            if twidgetSnapshotLayer.superlayer == nil {
                twidgetSnapshotLayer.anchorPoint = .zero
                twidgetContainer.layer?.addSublayer(twidgetSnapshotLayer)
            }
            twidgetSnapshotLayer.frame = twidgetContainer.bounds
            if shownTwidgetSnapshot !== snapshot {
                snapshot.install(in: twidgetSnapshotLayer)
                shownTwidgetSnapshot = snapshot
            }
            state.twidgetSnapshotShown()
        } else if shownTwidgetSnapshot != nil {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            twidgetSnapshotLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            twidgetSnapshotLayer.removeFromSuperlayer()
            CATransaction.commit()
            shownTwidgetSnapshot = nil
        }
    }

    private func attachTwidgetHost() {
        guard state?.twidgetHostChangedOwner === self else {
            return
        }
        updateTwidgetSnapshot()
        defer { endCrossfadeIfReady() }
        guard let state = state, let host = state.twidgetHost else {
            if let view = twidgetView, view.superview === self {
                twidgetContainer.subviews.forEach { $0.removeFromSuperview() }
            }
            return
        }
        if twidgetContainer.superview !== self {
            addSubview(twidgetContainer)
        }
        twidgetContainer.frame = contentBounds
        if host.view.superview !== twidgetContainer {
            twidgetContainer.subviews.forEach { $0.removeFromSuperview() }
            twidgetContainer.addSubview(host.view)
        }
        host.view.frame = twidgetContainer.bounds
        host.view.autoresizingMask = [.width, .height]
        twidgetView = twidgetContainer
        reportTwidgetSize()
    }

    private func detachTwidget() {
        if let state = state, state.twidgetHostChangedOwner === self {
            state.twidgetHostChanged = nil
            state.twidgetHostChangedOwner = nil
        }
        if let view = twidgetView, view.superview === self {
            view.removeFromSuperview()
            twidgetContainer.subviews.forEach { $0.removeFromSuperview() }
        }
        twidgetView = nil
        if shownTwidgetSnapshot != nil {
            twidgetSnapshotLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            twidgetSnapshotLayer.removeFromSuperlayer()
            shownTwidgetSnapshot = nil
        }
    }

    private func reportTwidgetSize() {
        guard let state = state, state.twidgetHostChangedOwner === self else {
            return
        }
        endCrossfadeIfReady()
        let size = state.twidgetSize(width: maxWidth)
        if size != contentBounds.size {
            onContentChanged?(size, false)
        }
    }

    private var contentBounds: CGRect {
        let reserved = state?.statsReservedHeight ?? 0
        return CGRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - reserved))
    }

    public var isHTMLBubbleVisible: Bool {
        guard let window = window, window.occlusionState.contains(.visible) else {
            return false
        }
        if let clip = enclosingScrollView?.contentView {
            return bounds.intersects(convert(clip.bounds, from: clip))
        }
        return !visibleRect.isEmpty
    }

    private var visibilityRecheckScheduled = false

    private func updateVisibility(force: Bool) {
        if state?.engine.usesWidgetSandbox == true {
            state?.twidgetNeedsUpdate()
            return
        }
        let visible = isHTMLBubbleVisible
        if !visible, window != nil, !visibilityRecheckScheduled {
            visibilityRecheckScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self = self else {
                    return
                }
                self.visibilityRecheckScheduled = false
                if self.isHTMLBubbleVisible {
                    self.updateVisibility(force: false)
                }
            }
        }
        if !visible {
            endScenePlay()
        }
        if force || visible != lastVisible {
            lastVisible = visible
            state?.visibilityChanged()
        }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            finishTransition()
            endScenePlay()
        }
        NotificationCenter.default.removeObserver(self)
        updateStatsTimer()
        if let window = window {
            NotificationCenter.default.addObserver(self, selector: #selector(statsOverlayNotification(_:)), name: HTMLBubbleStatsOverlay.didChangeNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(visibilityNotification(_:)), name: NSWindow.didChangeOcclusionStateNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(screenNotification(_:)), name: NSWindow.didChangeScreenNotification, object: window)
            updateScriptDisplay()
            if state?.engine.usesWidgetSandbox == true {
                attachTwidgetSpace()
            }
            if let clip = enclosingScrollView?.contentView {
                NotificationCenter.default.addObserver(self, selector: #selector(visibilityNotification(_:)), name: NSView.boundsDidChangeNotification, object: clip)
                if let document = clip.documentView {
                    NotificationCenter.default.addObserver(self, selector: #selector(visibilityNotification(_:)), name: NSView.frameDidChangeNotification, object: document)
                }
            }
        }
        updateVisibility(force: true)
    }

    private func updateStatsTimer() {
        statsTimer?.invalidate()
        statsTimer = nil
        guard window != nil, HTMLBubbleStatsOverlay.isEnabled(for: state) else {
            statsOverlay.reset()
            return
        }
        let timer = SwiftSignalKit.Timer(timeout: 1.0, repeat: true, completion: { [weak self] in
            self?.updateStats()
        }, queue: Queue.mainQueue())
        statsTimer = timer
        timer.start()
    }
    
    @objc private func statsOverlayNotification(_ notification: Notification) {
        updateStatsTimer()
        if let state = state {
            let size = state.engine.usesWidgetSandbox ? state.twidgetSize(width: maxWidth) : currentSize
            if size.height > 0 {
                onContentChanged?(size, false)
            }
        }
        needsLayout = true
    }
    
    private func updateStats() {
        guard HTMLBubbleStatsOverlay.isEnabled(for: state) else {
            statsOverlay.reset()
            return
        }
        guard let state = state, isHTMLBubbleVisible else {
            return
        }
        let bitmapBytes = currentTiles.reduce(0) { $0 + $1.byteCount }
        statsOverlay.update(state: state, bitmapBytes: bitmapBytes, bounds: bounds, scale: backingScale)
    }

    @objc private func screenNotification(_ notification: Notification) {
        updateScriptDisplay()
    }

    private func updateScriptDisplay() {
        guard state?.isScripted == true, let number = window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return
        }
        HTMLScript.setDisplay(CGDirectDisplayID(number.uint32Value))
    }

    @objc private func visibilityNotification(_ notification: Notification) {
        if state?.engine.usesWidgetSandbox == true {
            state?.twidgetNeedsUpdate()
            return
        }
        updateVisibility(force: false)
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if currentKey != nil {
            scheduleRender()
        }
    }

    private func scheduleRender() {
        guard let state = state, let appearance = bubbleAppearance, maxWidth > 0 else {
            return
        }
        if rendering {
            renderAgain = true
            return
        }
        rendering = true
        let width = maxWidth
        let scale = backingScale
        let colorSpace = window?.colorSpace?.cgColorSpace
        let hoverPoint = self.hoverPoint
        let applied = appliedVersion
        let previousTiles = currentTiles
        let previousSize = currentSize
        let previous = currentRendering
        let presented = magicStage.isActive ? magicStage.presentedFrames() : [:]
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        renderQueue.async { [weak self] in
            var magicCapture: HTMLBubbleMagicMove.Capture?
            if applied >= 0, !reduceMotion, state.engine == .litehtml || state.engine == .litehtmlBefore, state.transition(after: applied, upTo: Int.max) == "move", let old = previous?.document {
                magicCapture = HTMLBubbleMagicMove.capture(old, presented: presented, scale: scale)
            }
            if let hoverPoint = hoverPoint {
                let document = state.document(for: appearance)
                _ = document.layout(withMaxWidth: width)
                _ = document.mouseMoved(hoverPoint)
            }
            let result = HTMLBubbleRenderer.render(state: state, appearance: appearance, width: width, scale: scale, colorSpace: colorSpace, previous: previous)
            let sceneRect = state.scene3D?.isSupported == true ? (result.document?.bounds(matching: "[data-3d]") ?? .null) : .null
            var pending: HTMLBubbleView.PendingTransition?
            if applied >= 0, !previousTiles.isEmpty, let kind = state.transition(after: applied, upTo: result.version), var top = HTMLBubbleDiff.firstChange(old: previousTiles, new: result.tiles) {
                var bottom: CGFloat = 0
                var pinned = false
                if abs(previousSize.height - result.size.height) >= 0.5, HTMLBubbleTransition.opensOrCloses(kind) {
                    let pins = HTMLBubbleView.pinnedEdges(new: result, old: previous, newHeight: result.size.height, oldHeight: previousSize.height, scale: scale)
                    if let pinnedTop = pins.top {
                        top = pinnedTop
                    }
                    if let pinnedBottom = pins.bottom {
                        bottom = pinnedBottom
                        pinned = true
                    } else if let list = result.displayList ?? result.document?.displayList(maxWidth: width, scale: scale), let previousList = previous?.displayList ?? previous?.document?.displayList(maxWidth: width, scale: scale) {
                        bottom = list.unchangedBottom(since: previousList, previousHeight: previousSize.height, height: result.size.height, below: top)
                    } else {
                        bottom = HTMLBubbleDiff.unchangedBottom(old: previousTiles, oldHeight: previousSize.height, new: result.tiles, newHeight: result.size.height, above: top)
                    }
                }
                pending = HTMLBubbleView.PendingTransition(kind: kind, top: top, unchangedBottom: bottom, pinned: pinned)
            }
            var magicPlan: HTMLBubbleMagicMove.Plan?
            if let capture = magicCapture, pending?.kind == "move", let document = result.document {
                magicPlan = HTMLBubbleMagicMove.plan(capture, document: document, width: width, scale: scale, tiles: result.tiles)
            }
            DispatchQueue.main.async {
                guard let self = self else {
                    return
                }
                self.rendering = false
                if self.state === state, self.bubbleAppearance == appearance, self.maxWidth == width {
                    var transition: HTMLBubbleView.PendingTransition?
                    if let pending = pending, self.appliedVersion == applied, self.isHTMLBubbleVisible {
                        transition = pending
                    }
                    self.apply(result, transition: transition, magic: transition != nil ? magicPlan : nil)
                    self.updateScene(sceneRect)
                    let scrollable = result.size.width > width + 0.5
                    let expected = NSMakeSize(min(result.size.width, width), result.size.height + (scrollable ? HTMLBubbleView.scrollIndicatorInset : 0))
                    if expected != self.frame.size {
                        self.onContentChanged?(result.size, transition != nil)
                    }
                }
                if self.renderAgain {
                    self.renderAgain = false
                    self.scheduleRender()
                }
            }
        }
    }

    private static func pinnedEdges(new: HTMLBubbleRendering, old: HTMLBubbleRendering?, newHeight: CGFloat, oldHeight: CGFloat, scale: CGFloat) -> (top: CGFloat?, bottom: CGFloat?) {
        guard let old = old else {
            return (nil, nil)
        }
        func align(_ value: CGFloat) -> CGFloat {
            return (value * scale).rounded() / scale
        }
        var top: CGFloat?
        let headerNew = new.pinTop
        let headerOld = old.pinTop
        if !headerNew.isNull, !headerOld.isNull, abs(headerNew.maxY - headerOld.maxY) < 1 {
            top = align(headerNew.maxY)
        }
        var bottom: CGFloat?
        let footerNew = new.pinBottom
        let footerOld = old.pinBottom
        if !footerNew.isNull, !footerOld.isNull, abs((oldHeight - footerOld.minY) - (newHeight - footerNew.minY)) < 1 {
            bottom = align(newHeight - footerNew.minY)
        }
        return (top, bottom)
    }

    private func apply(_ rendering: HTMLBubbleRendering, transition: HTMLBubbleView.PendingTransition?, magic: HTMLBubbleMagicMove.Plan? = nil) {
        currentKey = rendering.key
        appliedVersion = rendering.version
        contentExtent = rendering.size.width
        let scale = backingScale
        let previousTiles = currentTiles
        let previousSize = currentSize
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if transition != nil || activeTransition.map({ !$0.covers(rendering.size) }) == true {
            finishTransition()
        }
        if magicStage.isActive {
            magicStage.cancel()
            magicTiles = nil
        }
        while tileLayers.count < rendering.tiles.count {
            let tile = CALayer()
            tile.contentsGravity = .resize
            tilesLayer.addSublayer(tile)
            tileLayers.append(tile)
        }
        while tileLayers.count > rendering.tiles.count {
            tileLayers.removeLast().removeFromSuperlayer()
        }
        tilesLayer.frame = CGRect(x: 0, y: 0, width: max(rendering.size.width, 1), height: max(rendering.size.height, 1))
        for (tileLayer, tile) in zip(tileLayers, rendering.tiles) {
            tileLayer.frame = tile.rect
            tileLayer.contentsScale = scale
            if (tileLayer.contents as AnyObject?) !== tile.contents {
                tileLayer.contents = tile.contents
            }
        }
        currentTiles = rendering.tiles
        currentRendering = rendering
        currentSize = rendering.size
        activeTransition?.mirror(rendering.tiles)
        if let transition = transition, !previousTiles.isEmpty {
            if let magic = magic, magic.baseTiles.count == tileLayers.count {
                stopReveal()
                for (tileLayer, tile) in zip(tileLayers, magic.baseTiles) {
                    tileLayer.contents = tile.contents
                }
                magicTiles = rendering.tiles
                magicStage.play(magic.items, scale: scale)
            } else if abs(previousSize.height - rendering.size.height) >= 0.5, HTMLBubbleTransition.opensOrCloses(transition.kind) {
                let completion: (HTMLBubbleTransition) -> Void = { [weak self] finished in
                    guard let self = self, self.activeTransition === finished else {
                        return
                    }
                    self.finishTransition()
                }
                stopReveal()
                activeTransition = HTMLBubbleTransition(resizing: previousTiles, oldSize: previousSize, to: rendering.tiles, newSize: rendering.size, unchangedTop: transition.top, unchangedBottom: transition.unchangedBottom, pinned: transition.pinned, contentLayer: contentLayer, tilesLayer: tilesLayer, scale: scale, duration: HTMLBubbleView.resizeDuration, completion: completion)
            } else {
                reveal(kind: transition.kind)
            }
        }
        CATransaction.commit()
        updateScroll()
    }

    private func updateScene(_ rect: CGRect) {
        guard let session = state?.scene3D, session.isSupported, !rect.isNull, rect.width >= 1, rect.height >= 1 else {
            removeScene()
            return
        }
        if sceneSession !== session {
            removeScene()
        }
        guard let layer = sceneLayer ?? session.makeLayer() else {
            return
        }
        if sceneLayer == nil {
            layer.zPosition = 1
            contentLayer.insertSublayer(layer, above: tilesLayer)
            sceneLayer = layer
            sceneSession = session
        }
        let scale = backingScale
        let radius = session.cornerRadius
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.frame = rect
        layer.contentsScale = scale
        let drawableSize = CGSize(width: (rect.width * scale).rounded(), height: (rect.height * scale).rounded())
        if layer.drawableSize != drawableSize {
            layer.drawableSize = drawableSize
        }
        layer.cornerRadius = radius
        layer.masksToBounds = radius > 0
        CATransaction.commit()
        sceneRect = rect
        session.attach(layer, size: rect.size, scale: scale)
    }

    private func removeScene() {
        endScenePlay()
        if let layer = sceneLayer {
            sceneSession?.detach(layer)
            layer.removeFromSuperlayer()
        }
        sceneLayer = nil
        sceneSession = nil
        sceneRect = .null
    }

    private func beginScenePlay() {
        guard sceneWindow == nil, let window = window as? Window else {
            return
        }
        sceneWindow = window
        let keys: [(KeyboardKey, String)] = [(.UpArrow, "ArrowUp"), (.DownArrow, "ArrowDown"), (.LeftArrow, "ArrowLeft"), (.RightArrow, "ArrowRight"), (.W, "w"), (.A, "a"), (.S, "s"), (.D, "d"), (.Space, " "), (.Return, "Enter")]
        for (key, name) in keys {
            window.set(handler: { [weak self] event in
                guard let self = self, self.sceneWindow != nil, event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
                    return .rejected
                }
                if !event.isARepeat {
                    self.state?.performInput("key", name, 0)
                }
                return .invoked
            }, with: self, for: key, priority: .supreme)
        }
        window.set(handler: { [weak self] _ in
            self?.endScenePlay()
            return .invoked
        }, with: self, for: .Escape, priority: .supreme)
        window.set(mouseHandler: { [weak self] event in
            guard let self = self, self.sceneWindow != nil else {
                return .rejected
            }
            let point = self.convert(event.locationInWindow, from: nil)
            if event.window !== self.window || !self.sceneRect.contains(CGPoint(x: point.x + self.scrollX, y: point.y)) {
                self.endScenePlay()
            }
            return .rejected
        }, with: self, for: .leftMouseDown, priority: .supreme)
        state?.performInput("focus", 1, 0)
    }

    private func endScenePlay() {
        guard let window = sceneWindow else {
            return
        }
        sceneWindow = nil
        window.removeAllHandlers(for: self)
        state?.performInput("focus", 0, 0)
    }

    private func reveal(kind: String) {
        guard let layer = layer else {
            return
        }
        HTMLBubbleTransition.reveal(layer, kind: kind, size: bounds.size)
    }

    private func stopReveal() {
        layer?.removeAnimation(forKey: "transition.opacity")
        layer?.removeAnimation(forKey: "transition.motion")
    }

    public func layoutTransitionStarted(_ transition: ContainedViewLayoutTransition) {
        activeTransition?.startSlide(transition)
    }

    public func pinContent(_ anchor: TableRowResizeAnchor, transition: ContainedViewLayoutTransition) {
        guard let view = twidgetView, view.superview === self else {
            return
        }
        anchor.pin(view, transition: transition)
    }

    private var magicTiles: [HTMLBubbleTile]?

    private func finishMagicMove() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let tiles = magicTiles, tiles.count == tileLayers.count {
            for (tileLayer, tile) in zip(tileLayers, tiles) {
                tileLayer.contents = tile.contents
            }
        }
        magicTiles = nil
        magicStage.clear()
        CATransaction.commit()
    }

    private func finishTransition() {
        activeTransition?.finish()
        activeTransition = nil
    }

    private func removeTiles() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        finishTransition()
        magicStage.cancel()
        magicTiles = nil
        for tile in tileLayers {
            tile.removeFromSuperlayer()
        }
        tileLayers.removeAll()
        currentTiles = []
        currentRendering = nil
        currentSize = .zero
        CATransaction.commit()
    }

    private var maxScrollX: CGFloat {
        return max(0, contentExtent - bounds.width)
    }

    private var isScrollable: Bool {
        return maxScrollX > 0.5
    }

    private func updateScroll() {
        scrollX = min(max(scrollX, 0), maxScrollX)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        contentLayer.frame = bounds
        contentLayer.bounds = CGRect(x: scrollX, y: 0, width: bounds.width, height: bounds.height)
        if isScrollable {
            let track = bounds.width - 4
            let width = max(24, track * bounds.width / contentExtent)
            let x = 2 + (track - width) * (scrollX / maxScrollX)
            indicatorLayer.frame = CGRect(x: x, y: bounds.height - 4, width: width, height: 3)
            indicatorLayer.backgroundColor = theme.chat.grayText(bubbleAppearance?.incoming ?? true, true).withAlphaComponent(0.45).cgColor
            indicatorLayer.isHidden = false
        } else {
            indicatorLayer.isHidden = true
        }
        CATransaction.commit()
    }

    public override func layout() {
        super.layout()
        twidgetView?.frame = contentBounds
        if shownTwidgetSnapshot != nil {
            twidgetSnapshotLayer.frame = contentBounds
        }
        updateScroll()
        updateVisibility(force: false)
    }

    public func consumesHorizontalScroll(atWindowPoint windowPoint: NSPoint) -> Bool {
        if state?.engine == .twidget, let renderer = state?.twidgetHost?.rendererObject as? LiteHTMLWidgetRenderer {
            return renderer.containsHorizontalScrollRegion(at: renderer.view.convert(windowPoint, from: nil))
        }
        return isScrollable && bounds.contains(convert(windowPoint, from: nil))
    }

    public override func scrollWheel(with event: NSEvent) {
        let deltaX = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.scrollingDeltaX * 8
        guard isScrollable, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else {
            super.scrollWheel(with: event)
            return
        }
        scrollX -= deltaX
        updateScroll()
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .cursorUpdate], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    private func documentPoint(_ event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x + scrollX, y: point.y)
    }

    private func perform(_ body: @escaping (LHDocument) -> Bool) {
        guard let state = state, let appearance = bubbleAppearance else {
            return
        }
        let width = maxWidth
        renderQueue.async { [weak self] in
            let document = state.document(for: appearance)
            _ = document.layout(withMaxWidth: width)
            let changed = body(document)
            let pointer = document.cursor == "pointer"
            DispatchQueue.main.async {
                guard let self = self, self.state === state else {
                    return
                }
                self.setPointer(pointer)
                if changed {
                    self.scheduleRender()
                }
            }
        }
    }

    private func setPointer(_ pointer: Bool) {
        self.pointer = pointer
        if hoverPoint != nil {
            (pointer ? NSCursor.pointingHand : NSCursor.arrow).set()
        }
    }

    public override func cursorUpdate(with event: NSEvent) {
        (pointer ? NSCursor.pointingHand : NSCursor.arrow).set()
    }

    public override func mouseMoved(with event: NSEvent) {
        let point = documentPoint(event)
        hoverPoint = point
        perform { $0.mouseMoved(point) }
    }

    public override func mouseExited(with event: NSEvent) {
        hoverPoint = nil
        pointer = false
        NSCursor.arrow.set()
        perform { $0.mouseExited() }
    }

    public override func mouseDown(with event: NSEvent) {
        let start = documentPoint(event)
        if sceneLayer != nil, sceneRect.contains(start) {
            beginScenePlay()
            state?.performInput("pointer", Double(start.x - sceneRect.minX), Double(start.y - sceneRect.minY))
            return
        }
        if event.clickCount >= 2, !pointer {
            selectByClick(at: start, clickCount: event.clickCount)
            return
        }
        clearSelection()
        perform { $0.mouseDown(start) }
        guard let window = window else {
            return
        }
        var anchor: HTMLTextPosition?
        var dragging = false
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let point = documentPoint(next)
            if next.type == .leftMouseUp {
                if dragging {
                    perform { $0.mouseExited() }
                    if hasSelection {
                        window.makeFirstResponder(self)
                    }
                } else {
                    perform { document in
                        _ = document.mouseDown(point)
                        return document.mouseUp(point)
                    }
                }
                break
            }
            if !dragging, hypot(point.x - start.x, point.y - start.y) > 4 {
                dragging = true
                anchor = position(at: start, in: ensureFragments())
            }
            if dragging, let anchor = anchor, let focus = position(at: point, in: fragments) {
                selection = (anchor, focus)
                updateSelectionLayer()
            }
        }
    }

    public var selectedText: String? {
        guard let (start, end) = orderedSelection, start != end else {
            return state?.engine.usesWidgetSandbox == true ? state?.twidgetSelectedText : nil
        }
        var result = ""
        var previous: LHTextFragment?
        for index in start.fragment ... end.fragment {
            let fragment = fragments[index]
            let text = fragment.text as NSString
            let from = index == start.fragment ? start.offset : 0
            let to = index == end.fragment ? end.offset : text.length
            if to <= from {
                continue
            }
            if let previous = previous {
                if fragment.frame.minY >= previous.frame.maxY - 1 {
                    result += "\n"
                } else if fragment.frame.minX - previous.frame.maxX > 0.5 {
                    result += " "
                }
            }
            result += text.substring(with: NSRange(location: from, length: to - from))
            previous = fragment
        }
        return result.isEmpty ? nil : result
    }

    private var hasSelection: Bool {
        return selectedText != nil
    }

    private var orderedSelection: (HTMLTextPosition, HTMLTextPosition)? {
        guard let selection = selection, !fragments.isEmpty else {
            return nil
        }
        return selection.anchor < selection.focus ? (selection.anchor, selection.focus) : (selection.focus, selection.anchor)
    }

    private func selectByClick(at point: CGPoint, clickCount: Int) {
        let fragments = ensureFragments()
        guard !fragments.isEmpty else {
            return
        }
        if clickCount == 2, let position = position(at: point, in: fragments) {
            let length = (fragments[position.fragment].text as NSString).length
            selection = (HTMLTextPosition(fragment: position.fragment, offset: 0), HTMLTextPosition(fragment: position.fragment, offset: length))
        } else {
            let last = fragments.count - 1
            selection = (HTMLTextPosition(fragment: 0, offset: 0), HTMLTextPosition(fragment: last, offset: (fragments[last].text as NSString).length))
        }
        updateSelectionLayer()
        window?.makeFirstResponder(self)
    }

    private func ensureFragments() -> [LHTextFragment] {
        guard let state = state, let appearance = bubbleAppearance else {
            return []
        }
        let key = state.renderKey(width: maxWidth, appearance: appearance, scale: 1)
        if fragmentsKey == key {
            return fragments
        }
        let width = maxWidth
        fragments = renderQueue.sync {
            return state.document(for: appearance).textFragments(maxWidth: width)
        }
        fragmentsKey = key
        return fragments
    }

    private func position(at point: CGPoint, in fragments: [LHTextFragment]) -> HTMLTextPosition? {
        guard let last = fragments.last else {
            return nil
        }
        var line: [Int] = []
        for (index, fragment) in fragments.enumerated() {
            let frame = fragment.frame
            if point.y >= frame.minY && point.y <= frame.maxY {
                if point.x >= frame.minX && point.x <= frame.maxX {
                    return HTMLTextPosition(fragment: index, offset: Int(fragment.characterIndex(atX: point.x)))
                }
                line.append(index)
            }
        }
        if !line.isEmpty {
            let before = line.filter { fragments[$0].frame.maxX <= point.x }
            if let index = before.max(by: { fragments[$0].frame.maxX < fragments[$1].frame.maxX }) {
                return HTMLTextPosition(fragment: index, offset: (fragments[index].text as NSString).length)
            }
            if let index = line.min(by: { fragments[$0].frame.minX < fragments[$1].frame.minX }) {
                return HTMLTextPosition(fragment: index, offset: 0)
            }
        }
        if let index = fragments.firstIndex(where: { $0.frame.minY > point.y }) {
            return HTMLTextPosition(fragment: index, offset: 0)
        }
        return HTMLTextPosition(fragment: fragments.count - 1, offset: (last.text as NSString).length)
    }

    private func updateSelectionLayer() {
        var rects: [CGRect] = []
        if let (start, end) = orderedSelection {
            for index in start.fragment ... end.fragment {
                let fragment = fragments[index]
                let from = index == start.fragment ? start.offset : 0
                let to = index == end.fragment ? end.offset : (fragment.text as NSString).length
                if to <= from {
                    continue
                }
                let minX = fragment.x(forCharacterIndex: UInt(from))
                let maxX = fragment.x(forCharacterIndex: UInt(to))
                let rect = CGRect(x: minX, y: fragment.frame.minY, width: maxX - minX, height: fragment.frame.height)
                if let previous = rects.last, abs(previous.midY - rect.midY) < 2, rect.minX > previous.maxX {
                    rects[rects.count - 1].size.width = rect.minX - previous.minX
                }
                rects.append(rect)
            }
        }
        let path = CGMutablePath()
        for rect in rects {
            path.addRect(rect)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        selectionLayer.frame = CGRect(x: 0, y: 0, width: max(contentExtent, bounds.width), height: bounds.height)
        selectionLayer.fillColor = theme.chat.selectText(bubbleAppearance?.incoming ?? true, true).withAlphaComponent(0.35).cgColor
        selectionLayer.path = rects.isEmpty ? nil : path
        CATransaction.commit()
    }

    private func clearSelection() {
        guard selection != nil else {
            return
        }
        selection = nil
        updateSelectionLayer()
    }

    public override var acceptsFirstResponder: Bool {
        return true
    }

    public override func resignFirstResponder() -> Bool {
        clearSelection()
        state?.clearTwidgetSelection()
        return super.resignFirstResponder()
    }

    @objc public func copy(_ sender: Any?) {
        if let text = selectedText {
            copyToClipboard(text)
        }
    }
}

private final class HTMLTwidgetContainer: NSView {
    private var pendingScrollEvents: [NSEvent] = []
    private var scrollDecided = false
    private weak var scrollWidget: NSView?
    private var forwardingToWidget = false

    override var isFlipped: Bool {
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if let event = NSApp.currentEvent, event.type == .scrollWheel {
            return frame.contains(point) ? self : nil
        }
        return super.hitTest(point)
    }

    override func scrollWheel(with event: NSEvent) {
        if forwardingToWidget || HTMLWidgetTestMode.usesPreviousBehavior {
            superview?.scrollWheel(with: event)
            return
        }
        if event.phase.isEmpty && event.momentumPhase.isEmpty {
            route(event, to: horizontalScrollTarget(for: event))
            return
        }
        if scrollDecided && (event.phase.contains(.mayBegin) || event.phase.contains(.began)) {
            scrollDecided = false
            scrollWidget = nil
        }
        if scrollDecided {
            route(event, to: scrollWidget)
            return
        }
        let finishing = event.phase.contains(.ended) || event.phase.contains(.cancelled) || !event.momentumPhase.isEmpty
        if event.scrollingDeltaX == 0 && event.scrollingDeltaY == 0 && !finishing {
            pendingScrollEvents.append(event)
            return
        }
        scrollDecided = true
        scrollWidget = finishing ? nil : horizontalScrollTarget(for: event)
        let events = pendingScrollEvents + [event]
        pendingScrollEvents.removeAll()
        for queued in events {
            route(queued, to: scrollWidget)
        }
    }

    private func horizontalScrollTarget(for event: NSEvent) -> NSView? {
        guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY), let superview = superview, (superview as? HorizontalScrollConsuming)?.consumesHorizontalScroll(atWindowPoint: event.locationInWindow) == true else {
            return nil
        }
        let view = super.hitTest(superview.convert(event.locationInWindow, from: nil))
        return view === self ? nil : view
    }

    private func route(_ event: NSEvent, to widget: NSView?) {
        guard let widget = widget else {
            superview?.scrollWheel(with: event)
            return
        }
        forwardingToWidget = true
        widget.scrollWheel(with: event)
        forwardingToWidget = false
    }
}
