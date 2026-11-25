import Cocoa
import SwiftSignalKit
import AVFoundation
import Foundation

private let tableRowPressureConfiguration = NSPressureConfiguration(pressureBehavior: .primaryDeepClick)

open class TableRowView: NSTableRowView, CALayerDelegate {
    
    private var animatedView: RowAnimateView?

    private var longDisposable: MetaDisposable?
    private let animatableContentObserver = AnimatableContentObserver()
    
    public internal(set) var isResorting: Bool = false {
        didSet {
            updateIsResorting()
        }
    }
    
    var dynamicContentStateForRestore:Bool? = nil
    var interactionStateForRestore:Bool? = nil
    
    public var isDynamicContentLocked:Bool = false {
        didSet {
            if isDynamicContentLocked != oldValue {
                viewDidUpdatedDynamicContent()
            }
        }
    }
    public var userInteractionEnabled:Bool = true {
        didSet {
            if userInteractionEnabled != oldValue {
                viewDidUpdatedInteractivity()
            }
        }
    }
    
    open func viewDidUpdatedInteractivity() {
        
    }
    open func viewDidUpdatedDynamicContent() {
        self._updateAnimatableContent()
    }
    
    
    open private(set) var item:TableRowItem?
    private var menuDisposable: MetaDisposable?
    private var menuVersion: UInt64 = 0
    private var menuRequestActive = false
    // var selected:Bool?
    
    open var border:BorderType?
    public var animates:Bool = true
    
    public private(set) var contextMenu:AppMenu?
    
    
    required public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        // self.layer = (self.layerClass() as! CALayer.Type).init()
        self.wantsLayer = true
        backgroundColor = .clear
        self.layerContentsRedrawPolicy = .never
        layer?.masksToBounds = true
        autoresizingMask = []
      //  self.layer?.delegate = self
        autoresizesSubviews = false
        pressureConfiguration = tableRowPressureConfiguration
        appearance = presentation.appearance
    }
    

//    open override var translatesAutoresizingMaskIntoConstraints: Bool {
//        get {
//            return false
//        }
//        set {
//
//        }
//    }
    
    open func updateColors() {
        self.layer?.backgroundColor = backdorColor.cgColor
    }
    
    open override func smartMagnify(with event: NSEvent) {
        super.smartMagnify(with: event)
    }
    
    
    open var backdorColor: NSColor {
        if let item = self.item {
            return item.backdorColor
        }
        return presentation.colors.background
    }
    
    open var borderColor: NSColor {
        if let item = self.item {
            return item.borderColor
        }
        return presentation.colors.border
    }
    
    open var isSelect: Bool {
        return item?.isSelected ?? false
    }
    
    open var isHighlighted: Bool {
         return item?.isHighlighted ?? false
    }
    
    open override func draw(_ dirtyRect: NSRect) {
        var bp:Int = 0
        bp += 1
    }
    
    open func updateIsResorting() {
        
    }

    open override func isAccessibilityElement() -> Bool {
        return TGUIKitAccessibility.isEnabled && item?.accessibilityHasContent == true && item?.accessibilityIsSpacer != true
    }

    open override func accessibilityRole() -> NSAccessibility.Role? {
        guard TGUIKitAccessibility.isEnabled else {
            return super.accessibilityRole()
        }
        return item?.accessibilityRole ?? .group
    }

    open override func accessibilityChildren() -> [Any]? {
        guard TGUIKitAccessibility.isEnabled else {
            return nil
        }
        if item?.accessibilityIsSpacer == true {
            return []
        }
        if let item = item, !item.accessibilityIncludesChildren, isAccessibilityElement() {
            return []
        }
        return NSAccessibility.unignoredChildren(from: subviews)
    }

    open override func accessibilityLabel() -> String? {
        return item?.accessibilityLabel
    }

    open override func accessibilityValue() -> Any? {
        guard let item = item else {
            return nil
        }
        if let value = item.accessibilityValue {
            return value
        }
        if item.accessibilityRole == .staticText {
            return item.accessibilityLabel
        }
        if let toggle = item.accessibilityToggleState {
            return NSNumber(value: toggle ? 1 : 0)
        }
        return nil
    }

    open override func accessibilityHelp() -> String? {
        return item?.accessibilityHelp
    }

    open override func isAccessibilityEnabled() -> Bool {
        return item?.accessibilityIsEnabled ?? true
    }

    open override func accessibilityPerformPress() -> Bool {
        return item?.accessibilityPerformPress() ?? false
    }

    open override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        guard let item = item else {
            return nil
        }
        let own = item.accessibilityCustomActions ?? []
        guard TGUIKitAccessibility.isEnabled, !item.accessibilityIncludesChildren, isAccessibilityElement() else {
            return item.accessibilityCustomActions
        }
        let names = Set(own.map { $0.name })
        let hidden = hiddenControlActions().filter { !names.contains($0.name) }
        let result = own + hidden
        return result.isEmpty ? nil : result
    }

    public func accessibilityPressPrimaryControl() -> Bool {
        let rowArea = bounds.width * bounds.height
        guard rowArea > 0 else {
            return false
        }
        var stack: [NSView] = subviews.reversed()
        while let view = stack.popLast() {
            if view.isHidden {
                continue
            }
            if let control = view as? Control, !(control is TextView), control.hasHandlers, control.userInteractionEnabled, control.isEnabled, control.frame.width * control.frame.height >= rowArea * 0.5 {
                return control.accessibilityPerformPress()
            }
            stack.append(contentsOf: view.subviews.reversed())
        }
        return false
    }

    private func hiddenControlActions() -> [NSAccessibilityCustomAction] {
        var result: [NSAccessibilityCustomAction] = []
        var seen: Set<String> = []
        let rowArea = bounds.width * bounds.height
        var stack: [NSView] = subviews.reversed()
        while let view = stack.popLast() {
            if view.isHidden {
                continue
            }
            if let control = view as? Control, !(control is TextView), control.isAccessibilityElement(), control.userInteractionEnabled, control.isEnabled {
                let area = control.frame.width * control.frame.height
                if rowArea > 0, area >= rowArea * 0.8 {
                    stack.append(contentsOf: view.subviews.reversed())
                    continue
                }
                var name = control.accessibilityLabel() ?? ""
                if name.isEmpty, control.accessibilityRole() == .checkBox {
                    name = localizedString("VoiceOver.Common.Toggle")
                }
                if !name.isEmpty, !seen.contains(name) {
                    seen.insert(name)
                    result.append(NSAccessibilityCustomAction(name: name, handler: { [weak control] in
                        return control?.accessibilityPerformPress() ?? false
                    }))
                }
                continue
            }
            stack.append(contentsOf: view.subviews.reversed())
        }
        return result
    }

    open override func accessibilityPerformShowMenu() -> Bool {
        guard let window = window, item != nil else {
            return false
        }
        let point = convert(NSMakePoint(bounds.midX, bounds.midY), to: nil)
        guard let event = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else {
            return false
        }
        showContextMenu(event)
        return true
    }
    
    open func draw(_ layer: CALayer, in ctx: CGContext) {
//        ctx.setFillColor(backdorColor.cgColor)
//        ctx.fill(layer.bounds)
       // layer.draw(in: ctx)
        
        if let border = border {
            
            ctx.setFillColor(borderColor.cgColor)
            
            if border.contains(.Top) {
                ctx.fill(NSMakeRect(0, frame.height - .borderSize, frame.width, .borderSize))
            }
            if border.contains(.Bottom) {
                ctx.fill(NSMakeRect(0, 0, frame.width, .borderSize))
            }
            if border.contains(.Left) {
                ctx.fill(NSMakeRect(0, 0, .borderSize, frame.height))
            }
            if border.contains(.Right) {
                ctx.fill(NSMakeRect(frame.width - .borderSize, 0, .borderSize, frame.height))
            }
            
        }
        
    }
    
    open func interactionContentView(for innerId: AnyHashable, animateIn: Bool ) -> NSView {
        return self
    }
    open func interactionControllerDidFinishAnimation(interactive: Bool, innerId: AnyHashable) {
        
    }
    open func addAccesoryOnCopiedView(innerId: AnyHashable, view: NSView) {
        
    }
    open func videoTimebase(for innerId: AnyHashable) -> CMTimebase? {
        return nil
    }
    open func applyTimebase(for innerId: AnyHashable, timebase: CMTimebase?) {
        
    }
    
    open func hasFirstResponder() -> Bool {
        return false
    }
    
    open func nextResponder() -> NSResponder? {
        return nil
    }
    
    open var firstResponder:NSResponder? {
        return self
    }
    
    open override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateMouse(animated: true)
    }
    open override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateMouse(animated: true)
    }
    open override func mouseExited(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateMouse(animated: true)
    }
    
    open override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) && event.clickCount == 1 {
            showContextMenu(event)
        } else {
            if event.clickCount == 2 {
                doubleClick(in: convert(event.locationInWindow, from: nil))
                return
            }
            super.mouseDown(with: event)
        }
    }
    
    private var lastPressureEventStage = 0
    
    open override func pressureChange(with event: NSEvent) {
        super.pressureChange(with: event)
        
        if event.stage >= 1 && event.stage != lastPressureEventStage {
            if longDisposable == nil {
                longDisposable = MetaDisposable()
            }
            longDisposable?.set(delaySignal(0.5).start(completed: { [weak self] in
                if let strongSelf = self {
                    if NSEvent.pressedMouseButtons & (1 << 0) != 0 {
                        if strongSelf.window?.mouseLocationOutsideOfEventStream == event.locationInWindow {
                            strongSelf.forceClick(in: strongSelf.convert(event.locationInWindow, from: nil))
                        }
                    }
                }
            }))
        }
        
        if event.stage < 1 {
            longDisposable?.set(nil)
        }
        
        if event.stage == 2 && lastPressureEventStage < 2 {
            longDisposable?.set(nil)
            forceClick(in: convert(event.locationInWindow, from: nil))
        }
        lastPressureEventStage = event.stage
    }
    
    open override func rightMouseDown(with event: NSEvent) {
        if mouseInside() {
            showContextMenu(event)
        }
    }
    
    open func doubleClick(in location:NSPoint) -> Void {
        
    }
    
    open func forceClick(in location: NSPoint) {
        
    }
    
    open func canMultiselectTextIn(_ location: NSPoint) -> Bool {
        return true
    }
    
    open func convertWindowPointToContent(_ point: NSPoint) -> NSPoint {
        return convert(point, from: nil)
    }
    

    open func canAnimateUpdate(_ item: TableRowItem) -> Bool {
        return true
    }

    open func applyResizeAnchor(_ anchor: TableRowResizeAnchor, transition: ContainedViewLayoutTransition) {
    }
    
    private func cancelMenuRequest() {
        guard menuRequestActive else { return }
        menuVersion &+= 1
        menuRequestActive = false
        menuDisposable?.set(nil)
    }

    open func showContextMenu(_ event: NSEvent) {
        menuVersion &+= 1
        let version = menuVersion
        menuRequestActive = true
        contextMenu = nil
        menuDisposable?.set(nil)
        guard menuVersion == version else { return }
        guard let item = item else {
            menuRequestActive = false
            return
        }
        if menuDisposable == nil {
            menuDisposable = MetaDisposable()
        }
        let location = convertWindowPointToContent(event.locationInWindow)
        guard menuVersion == version else { return }
        let items = item.menuItems(in: location) |> deliverOnMainQueue |> take(1)
        guard menuVersion == version else { return }
        let addition = item.menuAdditionView
        guard menuVersion == version else { return }
        let disposable = combineLatest(queue: .mainQueue(), items, addition).start(next: { [weak self, weak item] items, topWindow in
            guard let self = self, let item = item, self.menuVersion == version else { return }
            let menu = ContextMenu(presentation: item.menuPresentation, isLegacy: item.isLegacyMenu)
            guard self.menuVersion == version else { return }
            menu.topWindow = topWindow
            for item in items {
                menu.addItem(item)
            }
            let appMenu = AppMenu(menu: menu)
            menu.onShow = { [weak self, weak appMenu] _ in
                guard let self = self, let appMenu = appMenu, self.contextMenu === appMenu else { return }
                self.onShowContextMenu()
            }
            menu.onClose = { [weak self, weak appMenu] in
                guard let self = self, let appMenu = appMenu, self.contextMenu === appMenu else { return }
                self.contextMenu = nil
                self.cancelMenuRequest()
                if self.contextMenu == nil {
                    self.onCloseContextMenu()
                }
            }
            self.contextMenu = appMenu
            appMenu.show(event: event, view: self)
        }, completed: { [weak self] in
            guard let self = self, self.menuVersion == version else { return }
            self.menuRequestActive = false
        })
        if menuVersion == version {
            menuDisposable?.set(disposable)
        } else {
            disposable.dispose()
        }
    }

    open override func menu(for event: NSEvent) -> NSMenu? {
        return nil
    }
    
    
    
    
    open func onShowContextMenu() ->Void {
        self.layer?.setNeedsDisplay()
        updateColors()
    }
    
    open func onCloseContextMenu() ->Void {
        self.layer?.setNeedsDisplay()
        updateColors()
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open func updateMouse(animated: Bool) {
        
    }
    
    public var isInsertionAnimated:Bool {
        if let layer = layer?.presentation(), layer.animation(forKey: "position") != nil {
            return true
        }
        return false
    }
    
    public var rect:NSRect {
        if let layer = layer?.presentation(), layer.animation(forKey: "position") != nil {
            let rect = NSMakeRect(layer.position.x, layer.position.y, frame.width, frame.height)
            return rect
        }
        return frame
    }
    
    open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
    }
    
    override public static var isCompatibleWithResponsiveScrolling: Bool {
        return true
    }
    
    
    open override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        _updateListeners()
        _updateAnimatableContent()
    }
    
    open override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    public func notifySubviewsToLayout(_ subview:NSView) -> Void {
        for sub in subview.subviews {
            sub.needsLayout = true
        }
    }
    
    
    open override var needsLayout: Bool {
        set {
            super.needsLayout = newValue
            if newValue {
                guard #available(OSX 10.12, *) else {
                    layout()
                    notifySubviewsToLayout(self)
                    return
                }
            }
        }
        get {
            return super.needsLayout
        }
    }
    
    deinit {
        longDisposable?.dispose()
        menuDisposable?.dispose()
        removeNotificationListeners()
    }
    
    open var mouseInsideField: Bool {
        return false
    }
    
    open override func copy() -> Any {
        let view:View = View(frame:bounds)
        view.backgroundColor = self.backdorColor
        return view
    }
    
    open func onRemove(_ animation: NSTableView.AnimationOptions) {
        
    }
    
    open func onInsert(_ animation: NSTableView.AnimationOptions, appearAnimated: Bool) {
        
    }
    
    open func set(item:TableRowItem, animated:Bool = false) -> Void {
        let cancelRequest = menuRequestActive && self.item?.stableId != item.stableId
        self.item = item
        if cancelRequest {
            cancelMenuRequest()
        }
        guard self.item === item else { return }
        updateColors()
        self._updateAnimatableContent()
    }
    
    open func focusAnimation(_ innerId: AnyHashable?, text: String?) {
        
        if animatedView == nil {
            self.animatedView = RowAnimateView(frame: bounds)
            self.animatedView?.isEventLess = true
            self.addSubview(animatedView!)
            animatedView?.backgroundColor = presentation.colors.focusAnimationColor
            animatedView?.layer?.opacity = 0
            
        }
        animatedView?.stableId = item?.stableId
        
        
        let animation: CABasicAnimation = makeSpringAnimation("opacity")
        
        animation.fromValue = animatedView?.layer?.presentation()?.opacity ?? 0
        animation.toValue = 0.5
        animation.autoreverses = true
        animation.isRemovedOnCompletion = true
        animation.fillMode = CAMediaTimingFillMode.forwards
        
        animation.delegate = CALayerAnimationDelegate(completion: { [weak self] completed in
            if completed {
                self?.animatedView?.removeFromSuperview()
                self?.animatedView = nil
            }
        })
        animation.isAdditive = false
        
        animatedView?.layer?.add(animation, forKey: "opacity")
    }

    open func focusAnimation(_ innerId: AnyHashable?, text: String?, range: NSRange?) {
        focusAnimation(innerId, text: text)
    }
    
    open var interactableView: NSView {
        return self
    }
    
    open func shakeView() {
        
    }
    
    open func shakeViewWithData(_ data: Any) {
        
    }
        
    open func mouseInside() -> Bool {
        return super._mouseInside()
    }
    
    open var rowAppearance: NSAppearance? {
        return self.appearance
    }
    
    open func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        
    }
    
    
    @objc private func _updateAnimatableContent() {
        self.updateAnimatableContent()
    }
    
    open func updateAnimatableContent() {
        
    }
    
    open var isEmojiLite: Bool {
        return false
    }
    
    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            cancelMenuRequest()
        }
        _updateListeners()
        _updateAnimatableContent()
    }
    

    private func _updateListeners() {
        animatableContentObserver.update(for: self, target: self, selector: #selector(_updateAnimatableContent), options: [.contentBounds, .documentFrame, .ownFrame])
    }

    open override func cursorUpdate(with event: NSEvent) {
        super.cursorUpdate(with: event)
        NSCursor.arrow.set()
    }
    
    private func removeNotificationListeners() {
        NotificationCenter.default.removeObserver(self)
    }
    
    
}
