import Cocoa
import SwiftSignalKit
import AppKit

public enum ViewControllerStyle {
    case push
    case pop
    case none
}



open class NavigationHeaderView : View {
    public private(set) weak var header:NavigationHeader?
    public let ready:Promise<Bool> = Promise()

    public private(set) var height: CGFloat
    public init(_ header:NavigationHeader) {
        self.header = header
        self.height = header.height
        super.init(frame: NSMakeRect(0, 0, 0, header.height))
        self.autoresizingMask = [.width]
        self.layer?.masksToBounds = false
    }

    open func update(with contextObject: Any) {
        self.header?.contextObject = contextObject
    }

    open func destroy() {
        self.header?.contextObject = nil
    }

    open func hide(_ animated: Bool) {
        destroy()
        self.header?.hide(animated)
    }
    
    required public init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

open class NavigationHeader {

    public var contextObject: Any? = nil

    fileprivate weak var supplyHeader:NavigationHeader?
    fileprivate weak var simpleHeader:NavigationHeader?


    public let height:CGFloat
    fileprivate var realHeight: CGFloat = 0
    let initializer:(NavigationHeader, Any, NavigationHeaderView?)->(NavigationHeaderView, CGFloat)
    weak var navigation:NavigationViewController?
    fileprivate let disposable:MetaDisposable = MetaDisposable()
    fileprivate(set) var isShown:Bool = false
    public var needShown:Bool = false
    public init(_ height:CGFloat, initializer:@escaping(NavigationHeader, Any, NavigationHeaderView?)->(NavigationHeaderView, CGFloat)) {
        self.height = height
        self.initializer = initializer
    }
    fileprivate var _view:NavigationHeaderView? 
    public var view:NavigationHeaderView {
        return _view!
    }
    
    deinit {
        disposable.dispose()
    }

    public func updateRealHeight(_ realHeight: CGFloat, animated: Bool) {
        let realHeight = max(0, realHeight)
        guard self.realHeight != realHeight else {
            return
        }
        self.realHeight = realHeight
        navigation?.updateHeaderOverflow(animated: animated)
    }
    
    open func show(_ animated:Bool, contextObject: Any) {
        assert(navigation != nil)
        self.contextObject = contextObject
        let initialized = initializer(self, contextObject, self._view)
        if isShown {
            if initialized.0 === _view {
                return
            } else if _view != nil {
                hide(animated)
            }
        }
        
        isShown = true
        if let navigation = navigation {
            readyShow(navigation, animated: animated, initialized: initialized)
        }
    }
    
    func readyShow(_ navigation: NavigationViewController, animated: Bool, initialized: (NavigationHeaderView, CGFloat)) {
        self._view = initialized.0
        self.realHeight = initialized.1
        let view = self.view
        let realHeight = self.realHeight
        let slotInset = navigation.slotLeadingInset
        let hWidth = max(0, navigation.containerView.frame.width - slotInset - navigation.slotTrailingInset)
        view.frame = NSMakeRect(slotInset, -realHeight, hWidth, realHeight)
        disposable.set((view.ready.get() |> filter {$0} |> take(1)).start(next: { [weak navigation, weak self, weak view] (ready) in
            if let navigation = navigation, let view = view {
                self?.needShown = true

                let activeContainer = navigation.containerOf(navigation.controller)

                if let header = self?.supplyHeader, header.needShown {
                    navigation.containerView.addSubview(view, positioned: .below, relativeTo: header.view)
                } else {
                    navigation.containerView.addSubview(view, positioned: .above, relativeTo: activeContainer)
                }

                var inset: CGFloat = 0
                if let supplyHeader = self?.supplyHeader, supplyHeader.needShown {
                    inset += supplyHeader.height
                }
                let transition: ContainedViewLayoutTransition
                if animated {
                    transition = .animated(duration: 0.2, curve: .easeOut)
                } else {
                    transition = .immediate
                }

                let slot = navigation.slotLeadingInset
                transition.updateFrame(view: view, frame: NSMakeRect(slot, inset, max(0, view.frame.width), view.frame.height))

                // Move the active container down to make room for the header.
                navigation.updateActiveControllerLayout(barHeight: navigation.controller.barHeight, transition: transition)

                _ = activeContainer
            }
        }))
    }

    open func hide(_ animated:Bool) {
        assert(navigation != nil)
        self.contextObject = nil
        if !isShown {
            return
        }
        needShown = false
        isShown = false

        if let navigation = navigation, let view = _view {
            _view = nil
            let slot = navigation.slotLeadingInset
            performSubviewPosRemoval(view, pos: NSMakePoint(slot, -realHeight), animated: animated, duration: 0.2, timingFunction: .easeOut)

            let transition: ContainedViewLayoutTransition
            if animated {
                transition = .animated(duration: 0.2, curve: .easeOut)
            } else {
                transition = .immediate
            }
            // Recompute the active container's frame (which now reflects the
            // updated `barInset`) and animate to it.
            navigation.updateActiveControllerLayout(barHeight: navigation.controller.barHeight, transition: transition)
        }

    }
}

public class CallNavigationHeader : NavigationHeader {

    override func readyShow(_ navigation: NavigationViewController, animated: Bool, initialized: (NavigationHeaderView, CGFloat)) {
        self._view = initialized.0
        self.realHeight = initialized.1
        let view = self.view
        let realHeight = self.realHeight
        let height = self.height
        let slotInset = navigation.slotLeadingInset
        let hWidth = max(0, navigation.containerView.frame.width - slotInset - navigation.slotTrailingInset)
        view.frame = NSMakeRect(slotInset, -realHeight, hWidth, realHeight)


        disposable.set((view.ready.get() |> take(1)).start(next: { [weak navigation, weak view, weak self] (ready) in
            if let navigation = navigation, let view = view {
                self?.needShown = true

                let activeContainer = navigation.containerOf(navigation.controller)

                if let simpleHeader = self?.simpleHeader, simpleHeader.needShown {
                    navigation.containerView.addSubview(view, positioned: .above, relativeTo: simpleHeader.view)
                } else {
                    navigation.containerView.addSubview(view, positioned: .above, relativeTo: activeContainer)
                }

                let transition: ContainedViewLayoutTransition
                if animated {
                    transition = .animated(duration: 0.2, curve: .easeOut)
                } else {
                    transition = .immediate
                }

                let slot = navigation.slotLeadingInset
                if let simpleHeader = self?.simpleHeader, simpleHeader.needShown {
                    let simpleView = simpleHeader.view
                    let size = simpleView.frame.size
                    transition.updateFrame(view: simpleView, frame: CGRect(origin: NSMakePoint(slot, height), size: size))
                }

                transition.updateFrame(view: view, frame: CGRect(origin: NSMakePoint(slot, 0), size: view.frame.size))

                navigation.updateActiveControllerLayout(barHeight: navigation.controller.barHeight, transition: transition)
                _ = activeContainer
            }
        }))
    }

    public override func hide(_ animated:Bool) {
        assert(navigation != nil)
        if !isShown {
            return
        }
        needShown = false
        isShown = false


        if let navigation = navigation, let view = _view {
            
            let slot = navigation.slotLeadingInset
            
            _view = nil
            performSubviewPosRemoval(view, pos: NSMakePoint(slot, -realHeight), animated: animated, duration: 0.2, timingFunction: .easeOut)

            let transition: ContainedViewLayoutTransition
            if animated {
                transition = .animated(duration: 0.2, curve: .easeOut)
            } else {
                transition = .immediate
            }
            if let header = simpleHeader, header.needShown {
                transition.updateFrame(view: header.view, frame: CGRect(origin: NSMakePoint(slot, 0), size: header.view.frame.size))
            }

            navigation.updateActiveControllerLayout(barHeight: navigation.controller.barHeight, transition: transition)
        }

    }
}

public class AdditionalNavigationHeader : NavigationHeader {

    override func readyShow(_ navigation: NavigationViewController, animated: Bool, initialized: (NavigationHeaderView, CGFloat)) {
        self._view = initialized.0
        self.realHeight = initialized.1
        let view = self.view
        let realHeight = self.realHeight
        let slotInset = navigation.slotLeadingInset
        let hWidth = max(0, navigation.containerView.frame.width - slotInset - navigation.slotTrailingInset)
        view.frame = NSMakeRect(slotInset, -realHeight, hWidth, realHeight)

        disposable.set((view.ready.get() |> filter { $0 } |> take(1)).start(next: { [weak navigation, weak view, weak self] (ready) in
            if let navigation = navigation, let view = view {
                self?.needShown = true

                let activeContainer = navigation.containerOf(navigation.controller)
                navigation.containerView.addSubview(view, positioned: .above, relativeTo: activeContainer)

                let transition: ContainedViewLayoutTransition
                if animated {
                    transition = .animated(duration: 0.2, curve: .easeOut)
                } else {
                    transition = .immediate
                }

                let slot = navigation.slotLeadingInset
                transition.updateFrame(view: view, frame: CGRect(origin: NSMakePoint(slot, navigation.additionalHeaderInset), size: view.frame.size))

                navigation.updateActiveControllerLayout(barHeight: navigation.controller.barHeight, transition: transition)
                _ = activeContainer
            }
        }))
    }
}

open class NavigationViewController: ViewController, CALayerDelegate,CAAnimationDelegate {

    public var applyAppearOnLoad: Bool = true
    public var canAddControllers: Bool = true
    public private(set) var modalAction:NavigationModalAction?
    var stack:[ViewController] = [ViewController]()

    public var controllerDidChange:(()->Void)? = nil

    public var cleanupAfterDeinit: Bool = true

    var lock:Bool = false {
        didSet {
            var bp:Int = 0
            bp += 1
        }
    }

    /// No-op flags kept for backwards compatibility — the navigation no longer
    /// renders left/right borders or a vertical shadow during transitions.
    public var hasBarRightBorder: Bool = false
    public var hasBarLeftBorder: Bool = false
        
    open override var window: Window? {
        return _window ?? view.window as? Window
    }
    
    public var empty:ViewController {
        didSet {
            empty.navigationController = self

            let prev = self.stack.last
            self.stack.remove(at: 0)
            self.stack.insert(empty, at: 0)

            empty.loadViewIfNeeded(self.bounds)

            if prev == oldValue {
                show(empty, .none)
            } else if !self.stack.contains(where: { $0 === oldValue }) {
                discardContainer(for: oldValue)
            }
        }
    }
    
    open var isLocked:Bool {
        return lock
    }
    
    public private(set) var controller:ViewController {
        didSet {
            currentControllerDidChange()
        }
    }
    
    open override var backdorColor: NSColor {
        return .clear
    }
    
    /// The navigation bar of the **currently active** controller. Each controller
    /// owns its own `NavigationBarView` inside its `ControllerContainer`, so this
    /// computed accessor just returns the active container's bar.
    public var navigationBar: NavigationBarView {
        return containerOf(controller).navigationBar
    }

    let pushDisposable:MetaDisposable = MetaDisposable()
    let popDisposable:MetaDisposable = MetaDisposable()
    
    private(set) public var header:NavigationHeader?
    private(set) public var callHeader:CallNavigationHeader?
    private(set) public var additionalHeader:NavigationHeader?

    var containerView:View = View(frame: NSZeroRect)

    /// Per-controller wrapper view added inside `containerView`. Each pushed
    /// controller owns its own `ControllerContainer`, with its own
    /// `NavigationBarView` at the top and `contentView` below — so the bar is
    /// clipped by the container's rounded corners and layout/transitions/clipping
    /// (`masksToBounds = true`) are all scoped to a single controller.
    final class ControllerContainer: View {
        weak var controller: ViewController? {
            didSet {
                if oldValue != nil, controller == nil {
                    var bp = 0
                    bp += 1
                }
            }
        }
        public let navigationBar: NavigationBarView
        public let contentView: View
        public let backdropView: BackgroundView
        public let navigationEdgeBlur: EdgeEffectView
        private let clippingView: View
        private var glassView: LiquidGlassView?
        private var edgeBlurLayout: (rect: NSRect, hasBar: Bool, barIsReal: Bool) = (rect: .zero, hasBar: false, barIsReal: false)

        public required init(frame frameRect: NSRect) {
            self.navigationBar = NavigationBarView(frame: .zero)
            self.contentView = View(frame: .zero)
            self.clippingView = View(frame: .zero)
            self.backdropView = BackgroundView(frame: .zero)
            self.navigationEdgeBlur = EdgeEffectView(frame: .zero)
            super.init(frame: frameRect)

            self.layer?.masksToBounds = false
            self.backgroundColor = .clear

            clippingView.layer?.masksToBounds = false
            clippingView.layer?.cornerRadius = 20
            if #available(macOS 10.15, *) {
                clippingView.layer?.cornerCurve = .continuous
            }
            clippingView.backgroundColor = .clear

            backdropView.useSharedAnimationPhase = false

            self.addSubview(backdropView)
            addSubview(clippingView)
            clippingView.addSubview(contentView)
            navigationEdgeBlur.isEventLess = true
            clippingView.addSubview(navigationEdgeBlur)
            clippingView.addSubview(navigationBar)

            self.navigationBar.navigationEdgeBlur = navigationEdgeBlur

            //better make true if possible.
            contentView.layer?.masksToBounds = false
        }

        func updateBackgroundMode(_ mode: TableBackgroundMode) {
            backdropView.backgroundMode = mode
        }

        func applyContainerCornerRadius(_ radius: CGFloat) {
            clippingView.layer?.cornerRadius = radius
            clippingView.layer?.masksToBounds = radius > 0
        }

        func applyBackdrop(_ color: NSColor) {
            backdropView.backgroundColor = color
        }

        func installGlass(cornerRadius: CGFloat) {
            guard glassView == nil else { return }
            let glass = LiquidGlassView(frame: bounds, cornerRadius: cornerRadius, hasShadow: true, hasBorder: true, tintAlpha: 0)
            addSubview(glass, positioned: .below, relativeTo: clippingView)
            self.glassView = glass
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func updateLocalizationAndTheme(theme: PresentationTheme) {
            super.updateLocalizationAndTheme(theme: theme)
            backdropView.updateLocalizationAndTheme(theme: theme)
            glassView?.updateLocalizationAndTheme(theme: theme)
            navigationBar.updateLocalizationAndTheme(theme: theme)
            updateEdgeBlur(transition: .immediate)
            if let controller {
                applyBackdrop(controller.backdorColor)
            }
        }

        func updateInternalLayout(barHeight: CGFloat, slotLeadingInset: CGFloat = 0, slotTrailingInset: CGFloat = 0, inset: CGFloat = 0, barOffset: CGFloat = 0, transition: ContainedViewLayoutTransition = .immediate) {

            let barIsReal = controller?.barIsReal ?? false

            let contentTop = barIsReal ? barHeight + barOffset : 0

            let rect = bounds
            transition.updateFrame(view: clippingView, frame: rect)
            let backdropFrame = CGRect(origin: .zero, size: rect.size).insetBy(dx: 0, dy: -inset/2).offsetBy(dx: 0, dy: -inset/2)
            transition.updateFrame(view: backdropView, frame: backdropFrame)
            transition.updateFrame(view: navigationBar, frame: NSMakeRect(slotLeadingInset, barOffset, max(0, rect.width - slotLeadingInset - slotTrailingInset), barHeight))
            navigationBar.isHidden = barHeight == 0
            transition.updateFrame(view: contentView, frame: NSMakeRect(0, contentTop, rect.width, max(0, rect.height - contentTop)))

            edgeBlurLayout = (rect: NSMakeRect(0, 0, rect.width, max(0, barHeight + barOffset)), hasBar: barHeight > 0, barIsReal: barIsReal)
            transition.updateFrame(view: navigationEdgeBlur, frame: edgeBlurLayout.rect)
            navigationEdgeBlur.isHidden = !edgeBlurLayout.hasBar
            updateEdgeBlur(transition: transition)

            if let glassView {
                transition.updateFrame(view: glassView, frame: rect)
                glassView.updateLayout(size: rect.size, transition: transition)
            }
        }

        private func updateEdgeBlur(transition: ContainedViewLayoutTransition) {
            let blurRect = edgeBlurLayout.rect
            let blursContentUnderBar = edgeBlurLayout.hasBar && !edgeBlurLayout.barIsReal && System.blurEnabled
            let fadeSize = max(1, blurRect.height * 0.6)
            let blur = blursContentUnderBar ? EdgeEffectView.Blur(rect: blurRect, edgeSize: fadeSize) : nil
            navigationEdgeBlur.update(color: presentation.colors.listBackground, blur: blur, alpha: 0.6, edge: .bottom, edgeSize: fadeSize, rect: blurRect, transition: transition)
        }
    }

    // Keyed by `controller.internalId` (random Int per instance) rather than
    // `ObjectIdentifier`: ObjectIdentifier is just the heap address, so a
    // freshly-allocated controller can collide with a recently-deallocated one
    // whose address got reused. That collision was producing two
    // ChatControllerView siblings inside one ControllerContainer.contentView
    // when chats were closed/opened rapidly.
    private var controllerContainers: [Int: ControllerContainer] = [:]

    internal func existingContainerOf(_ controller: ViewController) -> ControllerContainer? {
        return controllerContainers[controller.internalId]
    }

    private var swipeBackgroundViews: [WeakReference<NSView>] = []

    private func removeSwipeBackgroundViews() {
        let views = swipeBackgroundViews
        swipeBackgroundViews.removeAll()
        for view in views {
            view.value?.removeFromSuperview()
        }
    }

    /// Lazy accessor for a controller's container. Creates the container, adds
    /// `controller.view` to the container's `contentView`, installs the
    /// controller's bar items into the container's `navigationBar`, and
    /// remembers the mapping. Subsequent calls return the same container.
    internal func containerOf(_ controller: ViewController) -> ControllerContainer {
        let key = controller.internalId
        if let existing = controllerContainers[key] {
            if controller.view.superview !== existing.contentView {
                controller.view.removeFromSuperview()
                existing.contentView.addSubview(controller.view)
                controller.view.frame = existing.contentView.bounds
            }
            return existing
        }
        let inset = bounds.insetBy(dx: controller.insets.left, dy: controller.insets.top)
        let containerFrame = NSMakeRect(inset.minX, inset.minY, max(0, inset.width), max(0, inset.height))
        let container = ControllerContainer(frame: containerFrame)
        container.controller = controller
        let radius = controller.containerCornerRadius
        container.applyContainerCornerRadius(radius)
        container.applyBackdrop(controller.backdorColor)
        if let bgMode = controller.bgMode {
            container.updateBackgroundMode(bgMode)
        }

        if controller.wantsContainerGlass && radius > 0 {
            container.installGlass(cornerRadius: radius)
        }

        container.navigationBar.navigation = self
        controller.navigationController = self
        container.contentView.addSubview(controller.view)
        container.navigationBar.switchViews(left: controller.leftBarView, center: controller.centerBarView, right: controller.rightBarView, controller: controller, style: .none, animationStyle: controller.animationStyle, liveSwiping: false)
        controllerContainers[key] = container
        return container
    }

    /// Sets the controller's container frame and lays out the bar + content
    /// view inside it. The container's frame is the full area the controller
    /// owns (bar + body); inside, the bar sits at `(0, 0, w, barHeight)` and
    /// `contentView` (which holds `controller.view`) sits below at
    /// `(0, barHeight, w, h - barHeight)`.
    internal func setControllerFrame(_ controller: ViewController, frame: NSRect) {
        let container = containerOf(controller)
        container.frame = frame
        let chromeOffset = barOffset(for: controller)
        container.updateInternalLayout(barHeight: controller.barHeight, slotLeadingInset: self.slotLeadingInset, slotTrailingInset: self.slotTrailingInset, inset: frame.minY, barOffset: chromeOffset)
        let contentBounds = container.contentView.bounds
        let inset = self.slotLeadingInset
        controller.view.frame = NSMakeRect(inset, 0, max(0, contentBounds.width - inset - self.slotTrailingInset), contentBounds.height)
        controller.updateNavigationHeaderOverflow(chromeOffset, transition: .immediate)
    }

    /// Scales an `animationStyle.duration` up by the share of total width that
    /// `slotLeadingInset` occupies. With a 240px-wide slot inside an 800px
    /// container, a 0.4s base duration becomes `0.4 * (1 + 240/800) = 0.52s` —
    /// keeping the perceived velocity consistent for the wider on-screen sweep.
    internal func scaledAnimationDuration(_ base: TimeInterval) -> TimeInterval {
        let width = max(1, self.containerView.frame.width)
        let factor = 1 + max(0, self.slotLeadingInset) / width
        return base * factor
    }

    internal func updateActiveControllerLayout(barHeight: CGFloat, transition: ContainedViewLayoutTransition) {
        updateHeaderFrames(transition: transition)

        let activeContainer = containerOf(controller)
        let newFrame = controllerFrame(for: controller)
        transition.updateFrame(view: activeContainer, frame: newFrame)
        let chromeOffset = barOffset(for: controller)
        activeContainer.updateInternalLayout(barHeight: barHeight, slotLeadingInset: slotLeadingInset, slotTrailingInset: slotTrailingInset, inset: newFrame.minY, barOffset: chromeOffset, transition: transition)
        let contentBounds = activeContainer.contentView.bounds
        let inset = slotLeadingInset
        controller.updateFrame(NSMakeRect(inset, 0, max(0, contentBounds.width - inset - slotTrailingInset), contentBounds.height), inset: newFrame.minY, transition: transition)
        controller.updateNavigationHeaderOverflow(chromeOffset, transition: transition)
    }

    private(set) var headerOverflow: CGFloat = 0

    private func contentOverflow(for controller: ViewController) -> CGFloat {
        return controller.absorbsNavigationHeaderOverflow ? headerOverflow : 0
    }

    private func barOffset(for controller: ViewController) -> CGFloat {
        return controller.absorbsNavigationHeaderOverflow ? 0 : headerOverflow
    }

    func updateHeaderFrames(transition: ContainedViewLayoutTransition) {
        let headerX = slotLeadingInset
        let headerWidth = max(0, containerView.frame.width - slotLeadingInset - slotTrailingInset)
        var reserved: CGFloat = 0
        var visualBottom: CGFloat = 0

        let headers: [NavigationHeader?] = [callHeader, header, additionalHeader]
        for header in headers.compactMap({ $0 }) where header.needShown && header._view != nil {
            let top = max(reserved, visualBottom)
            transition.updateFrame(view: header.view, frame: NSMakeRect(headerX, top, headerWidth, header.realHeight))
            visualBottom = top + header.realHeight
            reserved += header.height
        }
        headerOverflow = max(0, visualBottom - reserved)
    }

    func updateHeaderOverflow(animated: Bool) {
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate
        updateHeaderFrames(transition: transition)

        if controller.absorbsNavigationHeaderOverflow {
            updateActiveControllerLayout(barHeight: controller.barHeight, transition: transition)
        } else {
            let activeContainer = containerOf(controller)
            activeContainer.updateInternalLayout(barHeight: controller.barHeight, slotLeadingInset: slotLeadingInset, slotTrailingInset: slotTrailingInset, inset: activeContainer.frame.minY, barOffset: headerOverflow, transition: transition)
            controller.updateNavigationHeaderOverflow(headerOverflow, transition: transition)
        }
    }

    /// Forgets a controller's container (called when the controller is removed
    /// from the navigation stack permanently). Also detaches the controller's
    /// view from the container's `contentView` so the controller's strong
    /// reference to its own view is the only one left holding it.
    func discardContainer(for controller: ViewController) {
        let key = controller.internalId
        if let container = controllerContainers.removeValue(forKey: key) {
            container.removeFromSuperview()
            if controller.isLoaded(), controller.view.superview === container.contentView {
                controller.view.removeFromSuperview()
            }
        } else {
            var bp = 0
            bp += 1
        }
    }

    /// Removes the controller from the navigation's bookkeeping: discards its
    /// container, then notifies the controller. Use this in any path that drops
    /// a controller from the stack so its retained subviews can be released.
    fileprivate func removeFromStack(_ controller: ViewController) {
        discardContainer(for: controller)
        controller.didRemovedFromStack()
    }
    
    public func set(header:NavigationHeader?) {
        self.header?.hide(false)
        header?.navigation = self
        header?.supplyHeader = callHeader
        callHeader?.simpleHeader = header
        self.header = header
    }
    
    public func set(callHeader:CallNavigationHeader?) {
        self.callHeader?.hide(false)
        callHeader?.navigation = self
        header?.supplyHeader = callHeader
        callHeader?.simpleHeader = header
        self.callHeader = callHeader
    }

    public func set(additionalHeader:NavigationHeader?) {
        self.additionalHeader?.hide(false)
        additionalHeader?.navigation = self
        self.additionalHeader = additionalHeader
    }

    
    open override func loadView() {
        super.loadView();
        navigationBar.navigation = self
        view.layer?.masksToBounds = false
        bar = .init(height: 0)

    }
    
    public var navigationBarLeftPosition: CGFloat = 0 {
        didSet {
            navigationBar.needsLayout = true
        }
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()


        containerView.frame = bounds
        //self.view.autoresizesSubviews = true
        //containerView.autoresizesSubviews = true
        //containerView.autoresizingMask = [.width, .height]
        self.view.addSubview(containerView, positioned: .below, relativeTo: self.view.subviews.first)
        controller._frameRect = controllerFrame(for: controller)
        if self.applyAppearOnLoad {
            controller.viewWillAppear(false)
        }
        controller.navigationController = self

        // Each controller's container owns its own navigation bar; just create
        // and lay out the active controller's container.
        setControllerFrame(controller, frame: controllerFrame(for: controller))
        containerView.addSubview(containerOf(controller))

        if self.applyAppearOnLoad {
            Queue.mainQueue().justDispatch {
                self.controller.viewDidAppear(false)
            }
        }
        

    }
    
    var barInset: CGFloat {
        var barInset: CGFloat = 0
        if let header = header, header.needShown {
            barInset += header.height
        }
        if let header = callHeader, header.needShown {
            barInset += header.height
        }
        if let header = additionalHeader, header.needShown {
            barInset += header.height
        }
        return barInset
    }

    /// Vertical offset at which the `additionalHeader` (e.g. the chat-export
    /// banner) sits — directly below the audio/call headers when those are shown.
    var additionalHeaderInset: CGFloat {
        var inset: CGFloat = 0
        if let header = callHeader, header.needShown {
            inset += header.height
        }
        if let header = header, header.needShown {
            inset += header.height
        }
        return inset
    }

    /// Frame for the `ControllerContainer` inside `containerView`. The container
    /// owns the full vertical area for the controller — bar + body — so the
    /// navigation bar can live inside it and inherit the container's rounded
    /// clipping. Per-controller `insets` are applied as well.
    internal func controllerFrame(for controller: ViewController, baseX: CGFloat = 0, width: CGFloat? = nil) -> NSRect {
        let insets = controller.insets
        let baseWidth = width ?? containerView.frame.width
        let overflow = contentOverflow(for: controller)
        let x = baseX + insets.left
        let y = barInset + overflow + insets.top
        let w = max(0, baseWidth - insets.left - insets.right)
        let h = max(0, containerView.frame.height - barInset - overflow - insets.top - insets.bottom)
        return NSMakeRect(x, y, w, h)
    }
    
    override open func swapNavigationBar(leftView: BarView?, centerView: BarView?, rightView: BarView?, animation: NavigationBarSwapAnimation) {

        if let leftView = leftView {
            navigationBar.switchLeftView(leftView, animation: animation)
        }
        if let centerView = centerView {
            navigationBar.switchCenterView(centerView, animation: animation)
        }
        if let rightView = rightView {
            navigationBar.switchRightView(rightView, animation: animation)
        }
    }
    
    var containerSize: NSSize {
        return frame.size
    }
    
    open override func viewDidResized(_ size: NSSize) {
        super.viewDidResized(size)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        containerView.frame = NSMakeRect(0, 0, size.width, size.height)
        CATransaction.commit()

        let settings = self.controller.stake
        let containerSize = containerView.frame.size

        let keepLeft: CGFloat = containerSize.width == settings.keepLeft ? 0 : settings.keepLeft
        let keepTop = containerSize.width == settings.keepLeft ? 0 : settings.keepTop()

        let width = containerSize.width - keepLeft
        let point = NSMakePoint(keepLeft, 0)

        let headerWidth = max(0, width - slotLeadingInset - slotTrailingInset)
        let headerX = point.x + slotLeadingInset
        if let header = callHeader, header.needShown {
            header.view.frame = NSMakeRect(headerX, header.view.frame.minY, headerWidth, header.realHeight)
        }
        if let header = header, header.needShown {
            header.view.frame = NSMakeRect(headerX, header.view.frame.minY, headerWidth, header.realHeight)
        }
        if let header = additionalHeader, header.needShown {
            header.view.frame = NSMakeRect(headerX, additionalHeaderInset, headerWidth, header.realHeight)
        }

        if controller.isLoaded() {
            var frame = controllerFrame(for: controller, baseX: point.x, width: width)
            frame.origin.y += keepTop
            setControllerFrame(controller, frame: frame)

            if let tied = controller.tied {
                containerView.addSubview(containerOf(tied), positioned: .below, relativeTo: containerOf(controller))
                setControllerFrame(tied, frame: NSMakeRect(0, barInset + tied.bar.height, containerSize.width, containerSize.height - barInset - tied.bar.height))
                if tied.widthOnDisappear != nil {
                    tied.widthOnDisappear = containerSize.width
                }
            }

        }

    }
    
    open override var canBecomeResponder: Bool {
        return false
    }
    open func currentControllerDidChange() {
        controller.updateContainerContentInsets(containerContentInsets, transition: .immediate)
        controllerDidChange?()
    }

    open override func updateContainerContentInsets(_ insets: NSEdgeInsets, transition: ContainedViewLayoutTransition) {
        super.updateContainerContentInsets(insets, transition: transition)
        enumerateControllers { controller, _ in
            controller.updateContainerContentInsets(insets, transition: transition)
            return false
        }
    }
    
    public override var backgroundColor: NSColor {
        set {
            self.view.background = newValue
            navigationBar.backgroundColor = newValue
        }
        get {
            return self.view.background
        }
    }
    
    public init(_ empty:ViewController, _ window: Window?) {
        self.empty = empty
        self.controller = empty
        self.stack.append(controller)

        super.init()
        self._window = window
        // A NavigationViewController fills its parent and applies inset handling
        // to its active child internally — never let an outer container double up.
        self.insets = NSEdgeInsets()
    }
    
    public var stackCount:Int {
        return stack.count
    }
    
    deinit {
        self.popDisposable.dispose()
        self.pushDisposable.dispose()
        if cleanupAfterDeinit {
            while !stack.isEmpty {
                let value = stack.removeFirst()
                
                value.removeFromSuperview()
            }
        }
    }
    
    public func stackInsert(_ controller:ViewController, at: Int) -> Void {
        controller.navigationController = self
        controller.loadViewIfNeeded(self.bounds)
        stack.insert(controller, at: at)
    }
    
    open func push(_ controller:ViewController, _ animated:Bool = true, style: ViewControllerStyle? = nil, clearStack: Bool = false) -> Void {
        
//        if isLocked {
//            return
//        }
        
        if !self.canAddControllers {
            return
        }
        
        if controller.abolishWhenNavigationSame, controller.className == self.controller.className {
            return
        }

        controller.navigationController = self
        controller.loadViewIfNeeded(self.bounds)
        self.controller.readyToDetach()
        self.pushDisposable.set((controller.ready.get() |> take(1)).start(next: {[weak self] _ in
            if let strongSelf = self {
                controller.navigationController = strongSelf
                
                if let index = strongSelf.stack.firstIndex(of: controller) {
                    strongSelf.stack.remove(at: index)
                }
                
                strongSelf.stack.append(controller)
                
                let newStyle:ViewControllerStyle
                if let style = style {
                    newStyle = style
                } else {
                    newStyle = animated && strongSelf.stack.count > 1 ? .push : .none
                }
                CATransaction.begin()
                strongSelf.show(controller, newStyle)
                CATransaction.commit()
            }
        }))
    }
    
    
    func show(_ controller:ViewController,_ style:ViewControllerStyle) -> Void {
        lock = true


        guard let window = self.window else {return}
        if style == .none {
            window.abortSwiping()
        }
        defer {
            CATransaction.commit()
        }

        CATransaction.begin()

        let keepLeft = frame.width == controller.stake.keepLeft ? 0 : controller.stake.keepLeft

        
        let previous:ViewController = self.controller;
        controller.navigationController = self



        previous.setToNextController(controller, style: style)
        controller.setToPreviousController(previous, style: style)

        // containerView stays full-size; the new controller's `insets` are applied
        // only to the new controller's view (and its navigation bar). The previous
        // controller keeps its own frame so it doesn't visually shift while sliding
        // out during the transition.
        let keepTop = frame.width == controller.stake.keepLeft ? 0 : controller.stake.keepTop()
        var contentInset = controller.barHeight + keepTop

        let size = CGSize(width: containerView.frame.width - keepLeft, height: containerView.frame.height)
        let point = NSMakePoint(keepLeft, contentInset)

        
        if(previous === controller && stackCount > 1) {
            previous.viewWillDisappear(false)
            previous.viewDidDisappear(false)
            
            controller.viewWillAppear(false)
            controller.viewDidAppear(false)
            _ = controller.becomeFirstResponder()
            lock = false

            return;
        }
        
        
        

        var barInset: CGFloat = 0
        var visualBottom: CGFloat = 0
        let headerX = point.x + slotLeadingInset
        let headerWidth = max(0, size.width - slotLeadingInset - slotTrailingInset)
        if let header = callHeader, header.needShown {
            header.view.frame = NSMakeRect(headerX, 0, headerWidth, header.realHeight)
            visualBottom = header.realHeight
            contentInset += header.height
            barInset += header.height
        }

        if let header = header, header.needShown {
            let top = max(barInset, visualBottom)
            header.view.frame = NSMakeRect(headerX, top, headerWidth, header.realHeight)
            containerView.addSubview(header.view, positioned: .above, relativeTo: containerOf(controller))
            visualBottom = top + header.realHeight
            contentInset += header.height
            barInset += header.height
        }

        if let header = additionalHeader, header.needShown {
            let top = max(barInset, visualBottom)
            header.view.frame = NSMakeRect(headerX, top, headerWidth, header.realHeight)
            containerView.addSubview(header.view, positioned: .above, relativeTo: containerOf(controller))
            visualBottom = top + header.realHeight
            contentInset += header.height
            barInset += header.height
        }

        headerOverflow = max(0, visualBottom - barInset)

        // Each container has its own bar; no shared-bar position animation needed.

        
     
        
        if keepLeft > 0 || previous.stake.keepIn {
            controller.tied = previous
        } else {
            controller.tied = nil
        }
        previous.tied = nil
        
       // controller.view.removeFromSuperview()
        
        let popInteractiveInset: CGFloat? = window.inLiveSwiping ? containerOf(controller).frame.minX : nil

        do {
            let insets = controller.insets
            let overflow = contentOverflow(for: controller)
            setControllerFrame(controller, frame: NSMakeRect(point.x + insets.left, barInset + overflow + keepTop + insets.top, max(0, size.width - insets.left - insets.right), max(0, containerView.frame.height - barInset - overflow - keepTop - insets.top - insets.bottom)))
        }
       
        
        let reloadHeaders = { [weak self] in
            guard let self else { return }
            let container = self.containerOf(controller)
            if let header = self.callHeader, header.needShown {
                self.containerView.addSubview(header.view, positioned: .above, relativeTo: container)
            }
            if let header = self.header, header.needShown {
                self.containerView.addSubview(header.view, positioned: .above, relativeTo: container)
            }
            if let header = self.additionalHeader, header.needShown {
                self.containerView.addSubview(header.view, positioned: .above, relativeTo: container)
            }
        }
        
        var pfrom:CGFloat = 0, pto:CGFloat = 0, nto:CGFloat = 0, nfrom:CGFloat = 0;

        let previousContainer = containerOf(previous)
        let controllerContainer = containerOf(controller)

        switch style {
        case .push:

            controller.view.disableHierarchyDynamicContent()

            previous.viewWillDisappear(true);
            controller.viewWillAppear(true);

            nfrom = popInteractiveInset != nil ? popInteractiveInset! : frame.width
            nto = keepLeft + controller.insets.left
            pfrom = previousContainer.frame.minX
            if previous.stake.keepLeft > 0 && previous.stake.keepLeft != frame.width {
                pto = frame.maxX
            } else if keepLeft > 0 {
                pto = 0
            } else if controller.fullSlideAnimation {
                pto = -(self.frame.width - slotLeadingInset - slotTrailingInset)
            } else {
                pto = -round((self.frame.width - slotLeadingInset - slotTrailingInset)/3.0)
            }

            previousContainer.setFrameOrigin(NSMakePoint(pfrom, previousContainer.frame.minY))
            controllerContainer.setFrameOrigin(NSMakePoint(nfrom, controllerContainer.frame.minY))


            if popInteractiveInset == nil {
                controllerContainer.backdropView.layer?.opacity = 0
                previousContainer.backdropView.layer?.opacity = 1
            }

            containerView.addSubview(controllerContainer, positioned: .above, relativeTo: previousContainer)


        case .pop:

            controller.view.disableHierarchyDynamicContent()

            previous.viewWillDisappear(true);
            controller.viewWillAppear(true);

            if let popInteractiveInset = popInteractiveInset {
                nfrom = popInteractiveInset
            } else if previous.stake.keepLeft > 0 && previous.stake.keepLeft != frame.width {
                nfrom = 0
            } else if previous.fullSlideAnimation {
                nfrom = -(frame.width - slotLeadingInset - slotTrailingInset)
            } else {
                nfrom = -round((frame.width - slotLeadingInset - slotTrailingInset)/3.0)
            }

            nto = controller.insets.left
            pfrom = previousContainer.frame.minX
            pto = frame.width

            previousContainer.setFrameOrigin(NSMakePoint(pfrom, previousContainer.frame.minY))
            controllerContainer.setFrameOrigin(NSMakePoint(nfrom, controllerContainer.frame.minY))

            if popInteractiveInset == nil {
                controllerContainer.backdropView.layer?.opacity = 1
                previousContainer.backdropView.layer?.opacity = 1
            }

            containerView.addSubview(controllerContainer, positioned: .below, relativeTo: previousContainer)


        case .none:


            CATransaction.begin()
            
            
            previous.viewWillDisappear(false);
            previousContainer.removeFromSuperview()
            containerView.addSubview(controllerContainer)
            
            if let index = stack.firstIndex(of: previous) {
                if previous.removeAfterDisapper {
                    self.stack.remove(at: index)
                } else if previous.stake.keepLeft > 0 {
                    self.stack.remove(at: index)
                }
            }
            
            if !self.stack.contains(where: { $0 === previous }) {
                self.discardContainer(for: previous)
            }

            self.controller = controller

            controller.viewWillAppear(false);
            previous.viewDidDisappear(false);
            controller.viewDidAppear(false);
            _ = controller.becomeFirstResponder();
            lock = false

            reloadHeaders()

            
            CATransaction.commit()
            

            return // without animations
        }

        self.controller = controller


        let prevBackgroundView: NSView = View(frame: containerView.frame)
        let nextBackgroundView: NSView = View(frame: containerView.frame)

        if !controller.isOpaque {
            controllerContainer.addSubview(nextBackgroundView, positioned: .below, relativeTo: controllerContainer.subviews.first)
            nextBackgroundView.setFrameOrigin(NSMakePoint(nextBackgroundView.frame.minX, -controllerContainer.frame.minY))
        }
        if !previous.isOpaque {
            previousContainer.addSubview(prevBackgroundView, positioned: .below, relativeTo: previousContainer.subviews.first)
            prevBackgroundView.setFrameOrigin(NSMakePoint(prevBackgroundView.frame.minX, -previousContainer.frame.minY))
        }


        if let index = stack.firstIndex(of: previous) {
            if previous.removeAfterDisapper {
                self.stack.remove(at: index)
            } else if previous.stake.keepLeft > 0 {
                self.stack.remove(at: index)
            }
        }


        reloadHeaders()




        
        // Each container has its own bar with its own items already installed at
        // creation; nothing to switch here.

        
        
        let scaledDuration = self.scaledAnimationDuration(controller.animationStyle.duration)
        if style == .push {
            controllerContainer.backdropView._change(opacity: 1, animated: true, duration: scaledDuration / 3, timingFunction: .spring)
        }

        previousContainer._change(pos: NSMakePoint(pto, previousContainer.frame.minY), animated: true, duration: scaledDuration, timingFunction: .spring, completion: { [weak prevBackgroundView, weak self, weak previousContainer] _ in
            // After the animation finishes (or is interrupted), tear down the
            // previous container's stage state so it doesn't waste render memory.
            // - In normal mode (`keepLeft == 0` or `previous.stake.keepLeft > 0`)
            //   the previous container is detached from `containerView`. Its
            //   controller is still alive in the stack — when the user navigates
            //   back, `push(.pop)` re-adds the cached container.
            // - If `previous` is no longer on the stack at all, the container is
            //   fully discarded (entry removed + controller.view detached) so the
            //   controller can be deinited.
            prevBackgroundView?.removeFromSuperview()
            guard let self = self else { return }

            let stillInStack = self.stack.contains(where: { $0 === previous })
            let removeFromStage = (keepLeft == 0) || (previous.stake.keepLeft > 0)

            if !stillInStack {
                self.discardContainer(for: previous)
                previous.viewDidDisappear(true)
            } else if removeFromStage {
                previousContainer?.removeFromSuperview()
                previous.viewDidDisappear(true)
            }
        });


        controllerContainer._change(pos: NSMakePoint(nto, controllerContainer.frame.minY), animated: true, duration: scaledDuration, timingFunction: .spring, completion: { [weak nextBackgroundView, weak self] completed in
            guard let `self` = self else { return }
            if completed {
                controller.viewDidAppear(true);
                _ = controller.becomeFirstResponder()
                nextBackgroundView?.removeFromSuperview()
            }
            self.lock = false
            controller.view.restoreHierarchyDynamicContent()

        })

        if style == .pop {
            previousContainer.backdropView._change(opacity: 0, animated: true, duration: scaledDuration / 3, timingFunction: .spring)
        }

    }
    
    public func first(_ f:(ViewController)->Bool) -> ViewController? {
        return self.stack.first(where: f)
    }
    
    open override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        navigationBar.updateLocalizationAndTheme(theme: theme)
        if let callHeader = callHeader, callHeader.needShown {
            callHeader.view.updateLocalizationAndTheme(theme: theme)
        }
        if let header = header, header.needShown {
            header.view.updateLocalizationAndTheme(theme: theme)
        }
        if let additionalHeader = additionalHeader, additionalHeader.needShown {
            additionalHeader.view.updateLocalizationAndTheme(theme: theme)
        }

        for controller in self.stack {
            if controller != self.controller, controller.isLoaded() {
                controller.leftBarView.updateLocalizationAndTheme(theme: theme)
                controller.centerBarView.updateLocalizationAndTheme(theme: theme)
                controller.rightBarView.updateLocalizationAndTheme(theme: theme)
            }
        }

        // The per-controller backdrop / glass live on ControllerContainer, not
        // inside the controller view, so the controller's own theme pass
        // doesn't reach them. Refresh every cached container so the .plain
        // backdrop color and the LiquidGlassView's appearance get rebuilt.
        for (_, container) in controllerContainers {
            container.updateLocalizationAndTheme(theme: theme)
        }
    }
    

    open func invokeBack(animated:Bool = true, forceAnimated: Bool = false, animationStyle: ViewControllerStyle = .pop, checkLock: Bool = true) {
        if !isLocked, let last = stack.last, !checkLock || last.invokeNavigationBack() {
            if stackCount > 1 {
                let controller = stack[stackCount - 2]
                stack.removeLast()
                last.didRemovedFromStack()
                show(controller, animated || forceAnimated ? animationStyle : .none)
            } else {
                doSomethingOnEmptyBack?()
            }
        }
    }
    
    open func back(animated:Bool = true, forceAnimated: Bool = false, animationStyle: ViewControllerStyle = .pop) -> Void {
        self.invokeBack(animated: animated, forceAnimated: forceAnimated, animationStyle: animationStyle, checkLock: true)
    }
    
    
    public var doSomethingOnEmptyBack: (()->Void)? = nil


    
    public func to( index:Int? = nil) -> Void {
        if stackCount > 1, let index = index {
            if index < 0 {
                gotoEmpty(false)
            } else {
                let controller = stack[index]
                let range = min(max(1, index + 1), stackCount) ..< stackCount
                let copy = stack[range]
                stack.removeSubrange(range)
                for controller in copy {
                    removeFromStack(controller)
                }
                show(controller, .none)
            }
        }
    }

    public func gotoEmpty(_ animated:Bool = true) -> Void {
        if controller != empty {
            for controller in stack {
                controller.viewWillDisappear(false)
                removeFromStack(controller)
                controller.viewDidDisappear(false)
            }
            while stack.count != 1 {
                stack.removeLast()
            }
            show(empty, animated ? .pop : .none)
        }
    }

    public func close(animated:Bool = true) ->Void {
        if stackCount > 1 && !isLocked {
            let controller = stack[0]
            while stack.last != self.empty {
                let last = stack.removeLast()
                removeFromStack(last)
            }
            show(controller, animated ? .pop : .none)
        }
    }
    
    public func set(modalAction:NavigationModalAction, _ showView:Bool = true) {
        self.modalAction?.view?.removeFromSuperview()
        self.modalAction = modalAction
        modalAction.navigation = self
        if showView {
            let actionView = NavigationModalView(action: modalAction, viewController: self)
            modalAction.view = actionView
            actionView.frame = bounds
            view.addSubview(actionView)
        }  
    }
    
    public func removeImmediately(_ controller: ViewController, upNext: Bool = true) {
        if let index = self.stack.firstIndex(where: { $0.internalId == controller.internalId }) {
            if index == self.stack.count - 1, upNext {
                if self.stack.count > index {
                    show(self.stack[index - 1], .none)
                } else {
                    show(self.empty, .none)
                }
            }
            self.stack.remove(at: index)
            removeFromStack(controller)
        }
    }
    
    public func index(of controller: ViewController) -> Int? {
        return self.stack.firstIndex(of: controller)
    }
    
    private let depencyReadyDisposable = MetaDisposable()
    
    public func removeImmediately(_ controller: ViewController, depencyReady: ViewController) {
        let ready = depencyReady.ready.get() |> take(1) |> deliverOnMainQueue
        depencyReadyDisposable.set(ready.start(completed: { [weak controller, weak self] in
            guard let controller = controller else {
                return
            }
            self?.removeImmediately(controller)
        }))
    }
    
    public func removeUntil(_ controllerType: ViewController.Type) {
        let index = stack.firstIndex(where: { current in
            return current.className == NSStringFromClass(controllerType)
        })
        if let index = index {
            while stack.count - 1 > index {
                let controller = stack.removeLast()
                removeFromStack(controller)
            }
        } else {
            while stack.count > 1 {
                let controller = stack.removeLast()
                removeFromStack(controller)
            }
        }
    }

    public func removeAll() {
        for controller in stack {
            discardContainer(for: controller)
        }
        stack.removeAll()
    }
    
    public func removeModalAction() {
        self.modalAction?.view?.removeFromSuperview()
        self.modalAction = nil
    }
    
    public func enumerateControllers(_ f:(ViewController, Int)->Bool) {
        for i in stride(from: stack.count - 1, to: -1, by: -1) {
            if f(stack[i], i) {
                break
            }
        }
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if controller.redirectUserInterfaceCalls {
            controller.viewWillAppear(animated)
        }
    }
    
    
    open var previousController: ViewController? {
        if stackCount > 1 {
            return stack[stackCount - 2]
        }
        return nil
    }
    
    open var canSwipeBack: Bool {
        return self.stackCount > 1 // (self.genericView.state == .single || self.stackCount > 2)
    }
    
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.window?.add(swipe: { [weak self] direction, animated -> SwipeHandlerResult in

            guard let `self` = self, self.containerOf(self.controller).layer?.animationKeys() == nil, let window = self.window else {
                return .failed
            }

            let mouseInWindow = window.mouseLocationOutsideOfEventStream
            if let hit = window.contentView?.hitTest(window.contentView!.convert(mouseInWindow, from: nil)),
               hit.enclosingHorizontalScrollConsumer(atWindowPoint: mouseInWindow) != nil {
                return .failed
            }
            if let view = window.contentView!.hitTest(window.contentView!.convert(mouseInWindow, from: nil))?.superview {
                if view is HorizontalRowView || view.superview is HorizontalRowView {
                    return .failed
                } else if view.enclosingScrollView is HorizontalScrollView || view.enclosingScrollView is HorizontalTableView {
                    return .failed
                }
            }
            if hasPopover(window) {
                return .failed
            }


            switch direction {
            case let .left(state):

                self.controller.updateSwipingState(state, controller: self.controller, isPrevious: false)
                self.previousController?.updateSwipingState(state, controller: self.controller, isPrevious: true)

                switch state {
                case .start:

                    guard let previous = self.previousController, self.controller.supportSwipes, self.stackCount > 1 && !self.isLocked, self.canSwipeBack else {return .failed}

                    let previousContainer = self.containerOf(previous)
                    let activeContainer = self.containerOf(self.controller)

                    let fullSlide = self.controller.fullSlideAnimation

                    
                    self.setControllerFrame(previous, frame: self.controllerFrame(for: previous, baseX: fullSlide ? -self.frame.width : 0))

                    self.containerView.addSubview(previousContainer, positioned: .below, relativeTo: self.navigationBar)


                    let prevBackgroundView: NSView = View(frame: self.containerView.frame)
                    let nextBackgroundView: NSView = View(frame: self.containerView.frame)

                    self.removeSwipeBackgroundViews()
                    if !previous.isOpaque {
                        previousContainer.addSubview(prevBackgroundView, positioned: .below, relativeTo: previousContainer.subviews.first)
                        prevBackgroundView.setFrameOrigin(NSMakePoint(prevBackgroundView.frame.minX, -previousContainer.frame.minY))
                        self.swipeBackgroundViews.append(WeakReference(value: prevBackgroundView))
                    }
                    if !self.controller.isOpaque {
                        activeContainer.addSubview(nextBackgroundView, positioned: .below, relativeTo: activeContainer.subviews.first)
                        nextBackgroundView.setFrameOrigin(NSMakePoint(nextBackgroundView.frame.minX, -activeContainer.frame.minY))
                        self.swipeBackgroundViews.append(WeakReference(value: nextBackgroundView))
                    }

                    self.lock = true
                    return .success(previous)
                case let .swiping(delta, previous):
                    let settings = self.controller.stake

                    let keepLeft: CGFloat = self.frame.width == settings.keepLeft ? 0 : settings.keepLeft
                    let activeInsetLeft = self.controller.insets.left
                    let previousInsetLeft = previous.insets.left

                    let activeContainer = self.containerOf(self.controller)
                    let previousContainer = self.containerOf(previous)

                    let activeRestX = keepLeft + activeInsetLeft
                    let nPosition = min(max(activeRestX, delta + activeRestX), self.containerView.frame.width)
                    activeContainer._change(pos: NSMakePoint(nPosition, activeContainer.frame.minY), animated: false)
                    let fullSlide = self.controller.fullSlideAnimation
                    let previousStart: CGFloat
                    if keepLeft > 0 {
                        previousStart = 0
                    } else if fullSlide {
                        previousStart = -(self.containerView.frame.width - slotLeadingInset - slotTrailingInset)
                    } else {
                        previousStart = -round((self.containerView.frame.width - slotLeadingInset - slotTrailingInset)/3.0)
                    }
                    let parallaxDivisor: CGFloat = fullSlide ? 1.0 : 3.0

                    previousContainer._change(pos: NSMakePoint(min(previousStart + max(delta, 0) / parallaxDivisor + previousInsetLeft, previousInsetLeft), previousContainer.frame.minY), animated: false)

                    let progress = min(1, max(0, delta / self.containerView.frame.width))
                    let opacityProgress = min(1, progress * (fullSlide ? 1 : 2))
                    activeContainer.layer?.opacity = Float(1 - opacityProgress)

                    return .deltaUpdated(available: nPosition - activeRestX)

                case let .success(_, controller):
                    self.lock = false

                    controller.removeBackgroundCap()
                    self.controller.removeBackgroundCap()

                    self.back(forceAnimated: true)
                case let .failed(_, previous):
                    //   CATransaction.begin()
                    let animationStyle = previous.animationStyle
                    let settings = self.controller.stake

                    let keepLeft: CGFloat = self.frame.width == settings.keepLeft ? 0 : settings.keepLeft
                    let activeInsetLeft = self.controller.insets.left
                    let previousInsetLeft = previous.insets.left

                    let activeContainer = self.containerOf(self.controller)
                    let previousContainer = self.containerOf(previous)

                    let scaledDuration = self.scaledAnimationDuration(animationStyle.duration)
                    activeContainer._change(pos: NSMakePoint(keepLeft + activeInsetLeft, activeContainer.frame.minY), animated: animated, duration: scaledDuration, timingFunction: animationStyle.function)

                    let previousStart: CGFloat
                    if keepLeft > 0 {
                        previousStart = 0
                    } else if self.controller.fullSlideAnimation {
                        previousStart = -(self.containerView.frame.width - slotLeadingInset - slotTrailingInset)
                    } else {
                        previousStart = -round((self.containerView.frame.width - slotLeadingInset - slotTrailingInset)/3.0)
                    }

                    activeContainer._change(opacity: 1, animated: animated, duration: scaledDuration / 2, timingFunction: animationStyle.function)
                    previousContainer._change(pos: NSMakePoint(previousStart + previousInsetLeft, previousContainer.frame.minY), animated: animated, duration: scaledDuration, timingFunction: animationStyle.function, completion: { [weak self, weak previous] completed in
                        if completed {
                            self?.removeSwipeBackgroundViews()
                        }
                        if completed, keepLeft == 0 {
                            if let previous {
                                self?.discardContainer(for: previous)
                                previous.removeBackgroundCap()
                            }
                            self?.controller.removeBackgroundCap()
                        }
                    })
                    self.lock = false
                    //  CATransaction.commit()
                }
            case let .right(state):

                self.controller.updateSwipingState(state, controller: self.controller, isPrevious: false)
                self.previousController?.updateSwipingState(state, controller: self.controller, isPrevious: true)

                switch state {
                case .start:
                    guard let new = self.controller.rightSwipeController, !self.isLocked else {return .failed}
                    new._frameRect = self.containerView.bounds
                    let newContainer = self.containerOf(new)
                    let activeContainer = self.containerOf(self.controller)
                    self.setControllerFrame(new, frame: NSMakeRect(self.containerView.frame.width, activeContainer.frame.minY, self.containerView.frame.width, self.containerView.frame.height))


                    let prevBackgroundView: NSView = View(frame: self.containerView.frame)
                    let nextBackgroundView: NSView = View(frame: self.containerView.frame)

                    self.removeSwipeBackgroundViews()
                    if !new.isOpaque {
                        newContainer.addSubview(prevBackgroundView, positioned: .below, relativeTo: newContainer.subviews.first)
                        prevBackgroundView.setFrameOrigin(NSMakePoint(prevBackgroundView.frame.minX, -newContainer.frame.minY))
                        self.swipeBackgroundViews.append(WeakReference(value: prevBackgroundView))
                    }
                    if !self.controller.isOpaque {
                        activeContainer.addSubview(nextBackgroundView, positioned: .below, relativeTo: activeContainer.subviews.first)
                        nextBackgroundView.setFrameOrigin(NSMakePoint(nextBackgroundView.frame.minX, -activeContainer.frame.minY))
                        self.swipeBackgroundViews.append(WeakReference(value: nextBackgroundView))
                    }

                    newContainer.backdropView.layer?.opacity = 0

                    self.containerView.addSubview(newContainer, positioned: .above, relativeTo: activeContainer)
                    self.lock = true
                    return .success(new)
                case let .swiping(delta, new):
                    let delta = min(max(0, delta), self.containerView.frame.width)
                    let activeInsetLeft = self.controller.insets.left

                    let nPosition = self.containerView.frame.width - delta
                    let newContainer = self.containerOf(new)
                    let activeContainer = self.containerOf(self.controller)
                    newContainer._change(pos: NSMakePoint(nPosition, newContainer.frame.minY), animated: false)

                    activeContainer._change(pos: NSMakePoint(min(-delta / 3.0 + activeInsetLeft, activeInsetLeft), activeContainer.frame.minY), animated: false)

                    let progress = min(1, max(0, delta / self.containerView.frame.width))
                    let fullSlide = self.controller.fullSlideAnimation

                    let opacityProgress = min(1, progress * (fullSlide ? 1 : 2))
                    newContainer.backdropView.layer?.opacity = Float(opacityProgress)

                    return .deltaUpdated(available: delta)
                case let .success(_, controller):
                    self.lock = false

                    controller.removeBackgroundCap()
                    self.controller.removeBackgroundCap()

                    self.push(controller, true, style: .push)
                case let .failed(_, new):
                    // CATransaction.begin()
                    let animationStyle = new.animationStyle
                    let activeInsetLeft = self.controller.insets.left
                    var _new:ViewController? = new
                    let newContainer = self.containerOf(new)
                    let activeContainer = self.containerOf(self.controller)


                    let scaledDuration = self.scaledAnimationDuration(animationStyle.duration)
                    newContainer._change(pos: NSMakePoint(self.containerView.frame.width, newContainer.frame.minY), animated: animated, duration: scaledDuration, timingFunction: animationStyle.function)
                    newContainer.backdropView._change(opacity: 0, animated: animated, duration: scaledDuration / 3, timingFunction: animationStyle.function)
                    activeContainer._change(pos: NSMakePoint(activeInsetLeft, activeContainer.frame.minY), animated: animated, duration: scaledDuration, timingFunction: animationStyle.function, completion: { [weak self, weak new] completed in
                        self?.removeSwipeBackgroundViews()
                        self?.controller.removeBackgroundCap()
                        if let new {
                            self?.discardContainer(for: new)
                        }
                        _new = nil
                    })
                    self.lock = false
                    // CATransaction.commit()
                }
            default:
                break
            }

            return .nothing
        }, with: self.containerView, identifier: "\(self.description)")
        
        if controller.redirectUserInterfaceCalls {
            controller.viewDidAppear(animated)
        }
    }
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.window?.removeAllHandlers(for: self)
        if controller.redirectUserInterfaceCalls {
            controller.viewWillDisappear(animated)
        }
    }
    
    open override func scrollup(force: Bool = false) {
        super.scrollup()
        if controller.redirectUserInterfaceCalls {
            controller.scrollup()
        }
    }
    
    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if controller.redirectUserInterfaceCalls {
            controller.viewDidDisappear(animated)
        }
    }
    
    open override func focusSearch(animated: Bool, text: String? = nil) {
        super.focusSearch(animated: animated)
        if controller.redirectUserInterfaceCalls {
            controller.focusSearch(animated: animated, text: text)
        }
    }
}
