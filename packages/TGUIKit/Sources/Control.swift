import Cocoa
import SwiftSignalKit
import AppKit

public enum ControlState {
    case Normal
    case Hover
    case Highlight
    case Other
}

public enum ControlEvent {
    case Down
    case Up
    case Click
    case DoubleClick
    case SingleClick
    case RightDown
    case RightUp
    case MouseDragging
    case LongMouseDown
    case LongMouseUp
    case LongOver
}

private let longHandleDisposable = MetaDisposable()


internal struct ControlEventHandler : Hashable {
    static func == (lhs: ControlEventHandler, rhs: ControlEventHandler) -> Bool {
        return lhs.identifier == rhs.identifier
    }
    
    let identifier: UInt32
    let handler:(Control)->Void
    let event:ControlEvent
    let `internal`: Bool
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}
internal struct ControlStateHandler : Hashable {
    static func == (lhs: ControlStateHandler, rhs: ControlStateHandler) -> Bool {
        return lhs.identifier == rhs.identifier
    }
    let identifier: UInt32
    let handler:(Control)->Void
    let state:ControlState
    let `internal`: Bool
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
}

open class Control: View {

    public static var lastHandledClickTimestamp: CFTimeInterval?

    public var contextObject: Any?
    
    
    public internal(set) weak var popover: Popover?
    
    open var isEnabled:Bool = true {
        didSet {
            if isEnabled != oldValue {
                if !isEnabled, let effect = glassTouchEffect {
                    effect.setIsTracking(false)
                    effect.reset(animated: false)
                    glassTouchInitialLocation = nil
                }
                apply(state: controlState)
            }
        }
    }
    open var hideAnimated:Bool = false
    public var tooltipOnclick = false
    
    public var appTooltip: String? {
        didSet {
            if let tp = appTooltip, (!tooltipOnclick && controlState == .Hover) || (tooltipOnclick && controlState == .Highlight), userInteractionEnabled {
                tooltip(for: self, text: tp, alignment: .left)
            }
        }
    }

    open var isSelected:Bool {
        didSet {
            updateState()
            if isSelected != oldValue {
                apply(state: isSelected ? .Highlight : self.controlState)
            }
            
            updateSelected(isSelected)
        }
    }
    
    open func updateSelected(_ isSelected: Bool) {
        
    }
    
    open var animationStyle:AnimationStyle = AnimationStyle(duration:0.3, function:CAMediaTimingFunctionName.spring)
    
    var trackingArea:NSTrackingArea?

    public var hasHandlers: Bool {
        return !handlers.isEmpty
    }
    
    private var handlers:[ControlEventHandler] = []
    private var stateHandlers:[ControlStateHandler] = []
    
    private(set) internal var backgroundState:[ControlState:NSColor] = [:]
    
    private(set) internal var cursorState:[ControlState:NSCursor] = [:]
    
    private var mouseMovedInside: Bool = true
    private var longInvoked: Bool = false
    private var longOverHandleDisposable: MetaDisposable?
    private var longOverScheduled = false
    private var mouseDownWindowOrigin: NSPoint?
    public var handleLongEvent: Bool = true
    public var isMoving: Bool = false
    /// Springs the view slightly larger (1.03) while highlighted.
    public var scaleOnClick: Bool = false
    /// Springs the view slightly smaller (0.97) while highlighted — an inverse press effect.
    public var scaleDownOnClick: Bool = false

    public weak var stretchReferenceView: NSView? {
        didSet {
            if oldValue !== stretchReferenceView {
                rebuildGlassTouchEffect()
            }
        }
    }
    public weak var stretchTransformView: NSView? {
        didSet {
            if oldValue !== stretchTransformView {
                rebuildGlassTouchEffect()
            }
        }
    }

    public var interactiveGlassView: NSView? {
        get { return stretchReferenceView }
        set { stretchReferenceView = newValue }
    }
    public var interactiveGlassTransformView: NSView? {
        get { return stretchTransformView }
        set { stretchTransformView = newValue }
    }

    private var glassTouchEffect: GlassTouchEffect?
    private var glassTouchInitialLocation: NSPoint?
    private weak var pendingAdditionalGlassEffectView: NSView?

    private func rebuildGlassTouchEffect() {
        if let reference = stretchReferenceView {
            let transformHost = stretchTransformView ?? self
            self.wantsLayer = true
            reference.wantsLayer = true
            transformHost.wantsLayer = true
            glassTouchEffect = GlassTouchEffect(transformView: transformHost, referenceView: reference)
            glassTouchEffect?.additionalGlassEffectView = pendingAdditionalGlassEffectView
        } else {
            glassTouchEffect?.reset(animated: false)
            glassTouchEffect = nil
        }
    }

    public weak var additionalGlassEffectView: NSView? {
        didSet {
            pendingAdditionalGlassEffectView = additionalGlassEffectView
            glassTouchEffect?.additionalGlassEffectView = additionalGlassEffectView
        }
    }


    public func resetGlassTouchTracking(animated: Bool = false) {
        glassTouchEffect?.reset(animated: animated)
    }

    open override var backgroundColor: NSColor {
        get{
            return self.style.backgroundColor
        }
        set {
            if self.style.backgroundColor != newValue {
                self.style.backgroundColor = newValue
                self.setNeedsDisplayLayer()
            }
        }
    }
    
    public var style:ControlStyle = ControlStyle() {
        didSet {
            if style != oldValue {
                apply(style:style)
            }
        }
    }
    
    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            cancelLongOver()
            self.controlState = .Normal
        }
        updateTrackingAreas()
    }
    
    public var controlState:ControlState = .Normal {
        didSet {
            stateDidUpdate(controlState)
            for value in stateHandlers {
                if value.state == .Other {
                    value.handler(self)
                }
            }
            if oldValue != controlState {
                
                for value in stateHandlers {
                    if value.state == controlState {
                        value.handler(self)
                    }
                }

                if let tp = appTooltip, controlState == .Hover, userInteractionEnabled {
                    tooltip(for: self, text: tp, alignment: .left)
                }
            }
            apply(state: isSelected ? .Highlight : controlState)
        }
    }
    
    public func apply(state:ControlState) -> Void {
        let state:ControlState = self.isSelected ? .Highlight : state
        let color: CGColor
        if isEnabled, let stateColor = backgroundState[state] {
            color = stateColor.cgColor
        } else {
            color = backgroundState[.Normal]?.cgColor ?? self.backgroundColor.cgColor
        }
        if let layer = self.layer, layer.backgroundColor != color {
            layer.backgroundColor = color
            if animates {
                layer.animateBackground()
            }
        }
        
        let cursor: NSCursor? = cursorState[state]
        if let cursor = cursor {
            cursor.set()
        } else if !cursorState.isEmpty {
            NSCursor.arrow.set()
        }
    }
    private var previousState: ControlState?
    open func stateDidUpdate(_ state: ControlState) {
        if (self.scaleOnClick || self.scaleDownOnClick) && glassTouchEffect == nil {
            if state != previousState, isEnabled {
                let pressed: CGFloat = self.scaleDownOnClick ? 0.97 : 1.03
                if state == .Highlight {
                    self.layer?.animateScaleSpring(from: 1, to: pressed, duration: 0.3, removeOnCompletion: false)
                } else if self.layer?.animation(forKey: "transform") != nil, previousState == ControlState.Highlight {
                    self.layer?.animateScaleSpring(from: pressed, to: 1.0, duration: 0.3)
                }
            }
        }
        previousState = state
    }
    
    private var mouseIsDown:Bool {
        return (NSEvent.pressedMouseButtons & (1 << 0)) != 0
    }
    
    open override func updateTrackingAreas() {
        super.updateTrackingAreas()

        guard window != nil else {
            return
        }
        let needsTracking = visibleRect != .zero
        let hasTracking = trackingArea != nil

        if needsTracking == hasTracking {
            return
        }

        if let trackingArea = trackingArea {
            self.removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }

        if needsTracking {
            let options: NSTrackingArea.Options = [.cursorUpdate, .mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .assumeInside, .inVisibleRect]
            let area = NSTrackingArea(rect: self.bounds, options: options, owner: self, userInfo: nil)
            self.trackingArea = area
            self.addTrackingArea(area)
        }
    }
    
    open override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    open override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateTrackingAreas()
    }
    
    deinit {
        if let trackingArea = self.trackingArea {
            self.removeTrackingArea(trackingArea)
        }
        self.popover?.hide()
        longOverHandleDisposable?.dispose()
        
    //    longHandleDisposable.dispose()
    }
    
    public var controlIsHidden: Bool {
        return super.isHidden || (layer!.opacity < Float(0.5) && !controlOpacityEventIgnored)
    }
    
    public var controlOpacityEventIgnored: Bool = false
    
    open override var isHidden: Bool {
        get {
            return super.isHidden
        }
        set {
            if newValue != super.isHidden {
                if hideAnimated {
                    if !newValue {
                        super.isHidden = newValue
                    }
                    self.layer?.opacity = newValue ? 0.0 : 1.0
                    self.layer?.animateAlpha(from: newValue ? 1.0 : 0.0, to: newValue ? 0.0 : 1.0, duration: 0.2, completion:{ [weak self] completed in
                        if completed {
                            self?.updateHiddenState(newValue)
                        }
                    })
                    
                } else {
                    updateHiddenState(newValue)
                }
            }
        }
    }
    
    public func forceHide() -> Void {
        super.isHidden = true
        self.layer?.removeAllAnimations()
    }
    
    private func updateHiddenState(_ value:Bool) -> Void {
        super.isHidden = value
    }
    
    
    public var canHighlight: Bool = true
    
    @discardableResult public func set(handler:@escaping (Control) -> Void, for event:ControlEvent) -> UInt32 {
        return set(handler: handler, for: event, internal: false)
    }
    
    @discardableResult public func set(handler:@escaping (Control) -> Void, for state:ControlState) -> UInt32 {
        return set(handler: handler, for: state, internal: false)
    }
    
    @discardableResult internal func set(handler:@escaping (Control) -> Void, for event:ControlEvent, internal: Bool) -> UInt32 {
        let new = ControlEventHandler(identifier: arc4random(), handler: handler, event: event, internal: `internal`)
        handlers.append(new)
        return new.identifier
    }
    
    @discardableResult internal func set(handler:@escaping (Control) -> Void, for state:ControlState, internal: Bool) -> UInt32 {
        let new = ControlStateHandler(identifier: arc4random(), handler: handler, state: state, internal: `internal`)
        stateHandlers.append(new)
        return new.identifier
    }
    
    @discardableResult public func setSingle(handler:@escaping (Control) -> Void, for event:ControlEvent) -> UInt32 {
        self.removeAllHandlers()
        return self.set(handler: handler, for: event)
    }
    
    open override func cursorUpdate(with event: NSEvent) {
      //  super.cursorUpdate(with: event)
        apply(state: self.controlState)
    }
    
    public func set(background:NSColor, for state:ControlState) -> Void {
        backgroundState[state] = background
        apply(state: self.controlState)
        self.setNeedsDisplayLayer()
    }
    
    public func set(cursor:NSCursor, for state:ControlState) -> Void {
        cursorState[state] = cursor
        apply(state: self.controlState)
        self.setNeedsDisplayLayer()
    }
    
    public func removeLastHandler() -> ((Control)->Void)? {
        var last: ControlEventHandler?
        for handler in handlers.reversed() {
            if !handler.internal {
                last = handler
                break
            }
        }
        if let last = last {
            self.handlers.removeAll(where: { last.identifier == $0.identifier })
            return last.handler
        }
        return nil
    }
    
    public func removeLastStateHandler() -> Void {
        
        var last: ControlStateHandler?
        for handler in stateHandlers.reversed() {
            if !handler.internal {
                last = handler
                break
            }
        }
        if let last = last {
            self.stateHandlers.removeAll(where: { last.identifier == $0.identifier })
        }
    }
    
    public func removeStateHandler(_ identifier: UInt32) -> Void {
        self.stateHandlers.removeAll(where: { identifier == $0.identifier })
    }
    
    public func removeHandler(_ identifier: UInt32) -> Void {
        self.handlers.removeAll(where: { identifier == $0.identifier })
    }
    
    open func removeAllStateHandlers() -> Void {
        self.stateHandlers.removeAll(where: { !$0.internal })

    }

    open func removeAllHandlers() ->Void {
        self.handlers.removeAll(where: { !$0.internal })
    }
    
    
    override open func mouseDown(with event: NSEvent) {
        longInvoked = false
        mouseDownWindowOrigin = self.window?.frame.origin
        cancelLongOver()

        if userInteractionEnabled, isEnabled, let effect = glassTouchEffect, interactiveGlassView != nil {
            glassTouchInitialLocation = self.convert(event.locationInWindow, from: nil)
            effect.setStretchVector(.zero, animated: false)
            effect.setIsTracking(true)
        }
                
        if event.modifierFlags.contains(.control) {
            
            if let menu = self.contextMenu?(), event.clickCount == 1 {
                AppMenu.show(menu: menu, event: event, for: self)
            }
            
            for handler in handlers {
                if handler.event == .RightDown {
                    handler.handler(self)
                }
            }
            if sendRightMouseAnyway {
                super.mouseDown(with: event)
            }
            return
        }
        
        if userInteractionEnabled {
            updateState()
            
        }
        
        
        if userInteractionEnabled {
            updateState()
            send(event: .Down)
            if handleLongEvent {
                let point = event.locationInWindow
                let disposable = (Signal<Void,Void>.single(Void()) |> delay(0.35, queue: Queue.mainQueue())).start(next: { [weak self] in
                    self?.invokeLongDown(event, point: point)
                })
                
                longHandleDisposable.set(disposable)
            } else {
                longHandleDisposable.set(nil)
            }
           
            
        } else {
            super.mouseDown(with: event)
        }
    }
    
    private func invokeLongDown(_ event: NSEvent, point: NSPoint) {
        if self.mouseInside(), let wPoint = self.window?.mouseLocationOutsideOfEventStream, NSPointInRect(point, NSMakeRect(wPoint.x - 2, wPoint.y - 2, 4, 4)) {
            self.longInvoked = true
            if let menu = self.contextMenu?(), handlers.filter({ $0.event == .LongMouseDown }).isEmpty {
                AppMenu.show(menu: menu, event: event, for: self)
            }
            self.send(event: .LongMouseDown)
        }
    }
    
    public var moveNextEventDeep: Bool = false
    
    override open func mouseUp(with event: NSEvent) {
        longHandleDisposable.set(nil)
        cancelLongOver()

        if let effect = glassTouchEffect {
            effect.setIsTracking(false)
            glassTouchInitialLocation = nil
        }

        let windowMoved: Bool
        if let start = mouseDownWindowOrigin, let current = self.window?.frame.origin {
            windowMoved = start != current
        } else {
            windowMoved = false
        }
        mouseDownWindowOrigin = nil

        if moveNextEventDeep {
            super.mouseUp(with: event)
            moveNextEventDeep = false
            return
        }

        if userInteractionEnabled && !event.modifierFlags.contains(.control) {
            if isEnabled && !controlIsHidden && !windowMoved {
                
                if !longInvoked, self.handlers.isEmpty, let menu = self.contextMenu?(), event.clickCount == 1 {
                    AppMenu.show(menu: menu, event: event, for: self)
                }
                
                send(event: .Up)

                if longInvoked {
                    send(event: .LongMouseUp)
                }
                if mouseInside() && !longInvoked {
                    if event.clickCount == 1  {
                        send(event: .SingleClick)
                    }
                    if event.clickCount == 2 {
                        send(event: .DoubleClick)
                    }
                    send(event: .Click)
                    Control.lastHandledClickTimestamp = CACurrentMediaTime()
                }
            } else {
                if mouseInside() && !longInvoked {
                    //NSSound.beep()
                }
            }
            updateState()
            
        } else {
            if userInteractionEnabled && event.modifierFlags.contains(.control) {
                send(event: .RightUp)
                return
            }
            super.mouseUp(with: event)
        }
    }
    
    func performSuperMouseUp(_ event: NSEvent) {
         super.mouseUp(with: event)
    }
    func performSuperMouseDown(_ event: NSEvent) {
        super.mouseDown(with: event)
    }
    public var contextMenu:(()->ContextMenu?)? = nil

    public var isAccessibilityDecorative: Bool = false

    open var accessibilityDefaultLabel: String? {
        return nil
    }

    open override func isAccessibilityElement() -> Bool {
        guard TGUIKitAccessibility.isEnabled, !isAccessibilityDecorative, !isHidden else {
            return false
        }
        if let label = super.accessibilityLabel(), !label.isEmpty {
            return true
        }
        return hasHandlers || contextMenu != nil
    }

    open override func accessibilityRole() -> NSAccessibility.Role? {
        guard isAccessibilityElement() else {
            return super.accessibilityRole()
        }
        return containsAccessibleControls ? .group : .button
    }

    public var containsAccessibleControls: Bool {
        var stack: [NSView] = subviews
        while let view = stack.popLast() {
            if view.isHidden {
                continue
            }
            if let control = view as? Control, control.isAccessibilityElement(), control.accessibilityRole() != .staticText {
                return true
            }
            stack.append(contentsOf: view.subviews)
        }
        return false
    }

    open override func accessibilityLabel() -> String? {
        if let label = super.accessibilityLabel(), !label.isEmpty {
            return label
        }
        if let tooltip = appTooltip, !tooltip.isEmpty {
            return tooltip
        }
        if let tooltip = toolTip, !tooltip.isEmpty {
            return tooltip
        }
        return accessibilityDefaultLabel
    }

    open override func isAccessibilityEnabled() -> Bool {
        return isEnabled
    }

    open override func isAccessibilitySelected() -> Bool {
        return isSelected
    }

    open override func accessibilityPerformPress() -> Bool {
        guard isEnabled, userInteractionEnabled else {
            return false
        }
        if !hasHandlers, contextMenu != nil {
            return accessibilityPerformShowMenu()
        }
        send(event: .Down)
        send(event: .Up)
        send(event: .SingleClick)
        send(event: .Click)
        return true
    }

    open override func accessibilityPerformShowMenu() -> Bool {
        guard let menu = contextMenu?(), let window = window else {
            return false
        }
        let point = convert(NSMakePoint(bounds.midX, bounds.midY), to: nil)
        guard let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else {
            return false
        }
        AppMenu.show(menu: menu, event: event, for: self)
        return true
    }
   
    open func showContextMenu() {
        if let menu = self.contextMenu?(), let event = NSApp.currentEvent {
            AppMenu.show(menu: menu, event: event, for: self)
        }
    }
    
    public private(set) static weak var currentEventSource: Control?

    public func send(event:ControlEvent) -> Void {
        let previousSource = Control.currentEventSource
        Control.currentEventSource = self
        defer { Control.currentEventSource = previousSource }
        for value in handlers {
            if value.event == event {
                value.handler(self)
            }
        }
       
    }
    
    override open func mouseMoved(with event: NSEvent) {
        updateState()
        if userInteractionEnabled {
            scheduleLongOver()
        } else {
            super.mouseMoved(with: event)
        }
    }
    
    public var handleScrollEventOnInteractionEnabled: Bool = false
    
    open override func scrollWheel(with event: NSEvent) {
        if userInteractionEnabled, handleScrollEventOnInteractionEnabled {
            
        } else {
            super.scrollWheel(with: event)
        }
    }
    
    open var sendRightMouseAnyway: Bool {
        return true
    }
    
    open override func rightMouseDown(with event: NSEvent) {
        if let menu = self.contextMenu?(), event.clickCount == 1, userInteractionEnabled {
            AppMenu.show(menu: menu, event: event, for: self)
            return
        }
        if userInteractionEnabled {
            updateState()
            send(event: .RightDown)
            if sendRightMouseAnyway {
                super.rightMouseDown(with: event)
            }
        } else {
            super.rightMouseDown(with: event)
        }
    }
    
    open override func rightMouseUp(with event: NSEvent) {
        if userInteractionEnabled {
            updateState()
            send(event: .RightUp)
        } else {
            super.rightMouseUp(with: event)
        }
    }
    
    
    public func updateState() -> Void {
        if mouseInside(), !inLiveResize {
            if mouseIsDown && canHighlight {
                self.controlState = .Highlight
            } else if mouseMovedInside {
                self.controlState = .Hover
            } else {
                self.controlState = .Normal
            }
        } else {
            self.controlState = .Normal
        }
        
    }
    
    public var continuesAction: Bool = false

    private func cancelLongOver() {
        longOverScheduled = false
        longOverHandleDisposable?.set(nil)
    }

    private func scheduleLongOver() {
        guard controlState == .Hover, userInteractionEnabled, isEnabled else {
            cancelLongOver()
            return
        }
        guard !longOverScheduled, handlers.contains(where: { $0.event == .LongOver }) else {
            return
        }
        longOverScheduled = true
        if longOverHandleDisposable == nil {
            longOverHandleDisposable = MetaDisposable()
        }
        longOverHandleDisposable?.set((Signal<Void, Void>.single(()) |> delay(0.3, queue: Queue.mainQueue())).start(next: { [weak self] in
            guard let self, self.mouseInside(), self.controlState == .Hover, self.userInteractionEnabled, self.isEnabled else {
                self?.cancelLongOver()
                return
            }
            self.send(event: .LongOver)
        }))
    }
    
    override open func mouseEntered(with event: NSEvent) {
        updateState()
        if userInteractionEnabled {
            scheduleLongOver()
        } else {
            super.mouseEntered(with: event)
        }
    }
    
    
    override open func mouseExited(with event: NSEvent) {
        updateState()
        cancelLongOver()
        if userInteractionEnabled {
        } else {
            super.mouseExited(with: event)
        }
    }
    
    
    open override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return NSDragOperation.generic
    }
    
    
    
    override open func mouseDragged(with event: NSEvent) {
        if let start = mouseDownWindowOrigin, let current = self.window?.frame.origin, start != current {
            longHandleDisposable.set(nil)
        }
        if userInteractionEnabled {
            if isEnabled, let effect = glassTouchEffect, let initial = glassTouchInitialLocation {
                let current = self.convert(event.locationInWindow, from: nil)
                effect.setStretchVector(CGPoint(x: current.x - initial.x, y: current.y - initial.y), animated: false)
            }
            send(event: .MouseDragging)
            updateState()
        } else {
            super.mouseDragged(with: event)
        }
    }
    
    func apply(style:ControlStyle) -> Void {
        set(background: style.backgroundColor, for: .Normal)
        self.backgroundColor = style.backgroundColor
        if self.animates {
            self.layer?.animateBackground()
        }
        self.setNeedsDisplayLayer()
    }
    
    
    
    required public init(frame frameRect: NSRect) {
        self.isSelected = false
        super.init(frame: safeFrame(frameRect))
        animates = false
//        layer?.disableActions()
      
        
        //self.wantsLayer = true
        //self.layer?.isOpaque = true
    }
    
    public override init() {
        self.isSelected = false
        super.init(frame: NSZeroRect)
        animates = false
        layer?.disableActions()

       
        
        //self.wantsLayer = true
        //self.layer?.isOpaque = true
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open override func becomeFirstResponder() -> Bool {
        if let window = _window {
            return window.makeFirstResponder(self)
        }
        return false
    }
    
    public weak var redirectView: NSView?
    
    open override func smartMagnify(with event: NSEvent) {
        if let redirectView = self.redirectView {
            redirectView.smartMagnify(with: event)
        } else {
            super.smartMagnify(with: event)
        }
    }
    
    open override func magnify(with event: NSEvent) {
        if let redirectView = self.redirectView {
            redirectView.magnify(with: event)
        } else {
            super.magnify(with: event)
        }
    }
 
    public var forceMouseDownCanMoveWindow: Bool = false
    open override var mouseDownCanMoveWindow: Bool {
        return !self.userInteractionEnabled || forceMouseDownCanMoveWindow
    }
}

public extension Control {
    func setStateChangeHandler(_ handler: @escaping () -> Void) {
        set(handler: { _ in handler() }, for: .Highlight)
        set(handler: { _ in handler() }, for: .Normal)
        set(handler: { _ in handler() }, for: .Hover)
    }
}
