import Foundation
import SwiftSignalKit
import AppKit
import ColorPalette

public final class BackgroundGradientView : View {
    public var values:(top: NSColor?, bottom: NSColor?, rotation: Int32?)? {
        didSet {
            needsDisplay = true
        }
    }
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        noWayToRemoveFromSuperview = true
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    override public var isFlipped: Bool {
        return false
    }
    
    override public func layout() {
        super.layout()
        let values = self.values
        self.values = values
    }
    
    override public func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        if let values = self.values {
            
            let colors = Array([values.top, values.bottom].compactMap { $0?.cgColor }.reversed())
            
            guard !colors.isEmpty else {
                return
            }
            
            let gradient = CGGradient.evenlySpaced(colors)!
            
            ctx.saveGState()
            ctx.translateBy(x: frame.width / 2.0, y: frame.height / 2.0)
            ctx.rotate(by: CGFloat(values.rotation ?? 0) * CGFloat.pi / -180.0)
            ctx.translateBy(x: -frame.width / 2.0, y: -frame.height / 2.0)
            ctx.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 0.0, y: frame.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        }
        
    }
}


open class BackgroundView: View {
    
    private var slotsMetadata: SVG_SlotsMetadata? = nil
    private var slotOverlays: [NSView] = []
    
    public var getBackgroundSlot:((NSRect)->NSView)? = nil
    
    private var isTiled: Bool = false
    private var tileImageSize: CGSize = .zero
    
    private func setSlotsMetadata(_ metadata: SVG_SlotsMetadata?) {
        // Remove old overlays
        for v in slotOverlays { v.removeFromSuperview() }
        slotOverlays.removeAll()
        
        slotsMetadata = metadata
        guard metadata != nil else { return }
        
        // We don't know tile count yet; update will allocate exactly what it needs.
        updateSlotOverlaysLayout(size: bounds.size)
    }
    
    private func updateSlotOverlaysLayout(size: NSSize) {
        guard let md = slotsMetadata else { return }

        // ---- compute tile rects (same as your logic) ----
        let host = CGRect(origin: .zero, size: CGSize(width: size.width, height: max(500, size.height)))
        var tileRects: [CGRect] = []

        if isTiled, tileImageSize.width > 0, tileImageSize.height > 0 {
            let sf = min(host.width / tileImageSize.width, host.height / tileImageSize.height)
            let tileW = tileImageSize.width * sf
            let tileH = tileImageSize.height * sf

            if tileW < host.width {
                var x: CGFloat = 0
                let y = host.minY + (host.height - tileH) * 0.5
                while x < host.width {
                    tileRects.append(CGRect(x: x, y: y, width: tileW, height: tileH))
                    x += tileW
                }
            } else {
                let sfFill = max(host.width / tileImageSize.width, host.height / tileImageSize.height)
                let w = tileImageSize.width * sfFill
                let h = tileImageSize.height * sfFill
                tileRects = [CGRect(x: host.minX + (host.width - w) * 0.5,
                                    y: host.minY + (host.height - h) * 0.5,
                                    width: w, height: h)]
            }
        } else {
            tileRects = [imageView.frame]
        }

        // ---- only draw the neatSpot slot, one overlay per tile ----
        guard md.slots.count > 0 else {
            slotOverlays.forEach { $0.isHidden = true }
            return
        }
        let neat = max(0, min(md.neatSpot, md.slots.count - 1))
        let slot = md.slots[neat]

        // Ensure exactly tileRects.count overlays exist
        let needed = tileRects.count
        
        
        let src = md.imageSize.cgSize
        var spotRects: [NSRect] = []
        for tile in tileRects {

            let s = tile.width / src.width // tiles are uniform-scaled
            let r = slot.pixel.cgRect

            let x = floor(tile.minX + r.minX * s)
            let y = floor(tile.minY + (tile.height - (r.minY + r.height) * s) + 6)
            let w = floor(r.width  * s)
            let h = floor(r.height * s)

            spotRects.append(CGRect(x: x, y: y, width: w, height: h).insetBy(dx: -4, dy: -4))
        }
        
        if slotOverlays.count > needed {
            for _ in needed..<slotOverlays.count { slotOverlays.removeLast().removeFromSuperview() }
        } else if slotOverlays.count < needed {
            for _ in slotOverlays.count..<needed {
                let rect = spotRects[slotOverlays.count]
                let v = getBackgroundSlot?(rect) ?? NSView(frame: rect)
                addSubview(v)
                slotOverlays.append(v)
            }
        }
        for (i, slot) in slotOverlays.enumerated() {
            slot.frame = spotRects[i]
        }
    }


    private final class TileControl {
        private var superlayer: CALayer?
        private let main: CALayer
        private var tile: NSImage? = nil
        private var shouldTile: Bool = false
        private var tileLayers:[CALayer] = []
        
        init(main: CALayer) {
            self.main = main
            tileLayers.append(main)
        }
        
        func set(superlayer: CALayer?, tile: NSImage?, shouldTile: Bool) {
            self.superlayer = superlayer
            self.shouldTile = shouldTile
            self.tile = tile
        }
        
        var validLayout: CGRect? = nil
        
        func update(frame: NSRect, transition: ContainedViewLayoutTransition) {
            
            
            var rects:[CGRect] = []
            var frame = frame
            frame.size.height = max(500, frame.height)
            
            if let superlayer = superlayer {
                if let tile = tile {
                    let size = tile.size
                    let tileSize = size.aspectFitted(frame.size)
                    if shouldTile {
                        if tileSize.width < frame.width {
                            while rects.reduce(CGFloat(0), { $0 + $1.width }) < frame.width {
                                let width = rects.reduce(CGFloat(0), { $0 + $1.width })
                                rects.append(CGRect(origin: .init(x: width, y: (frame.height - tileSize.height) / 2), size: tileSize))
                            }
                        } else {
                            rects.append(frame.focus(size.aspectFilled(frame.size)))
                        }
                    } else {
                        rects.append(frame.focus(size.aspectFilled(frame.size)))
                    }
                    
                    while self.tileLayers.count > rects.count {
                        self.tileLayers.removeLast().removeFromSuperlayer()
                    }
                    while self.tileLayers.count < rects.count {
                        let layer = SimpleLayer()
//                        layer.disableActions()
                        self.tileLayers.append(layer)
                    }
                    
                    for (i, layer) in tileLayers.enumerated() {
                        layer.compositingFilter = main.compositingFilter
                        layer.backgroundColor = main.backgroundColor
                        layer.contents = main.contents
                        layer.opacity = main.opacity
//                        layer.contentsGravity = .resize

                        transition.updateFrame(layer: layer, frame: rects[i])
                        superlayer.addSublayer(layer)
                    }
                } else {
                    while tileLayers.count > 1 {
                        tileLayers.removeLast().removeFromSuperlayer()
                    }
                    superlayer.addSublayer(main)
                    transition.updateFrame(layer: main, frame: frame)
                }
            } else {
                while tileLayers.count > 1 {
                    tileLayers.removeLast().removeFromSuperlayer()
                }
                main.removeFromSuperlayer()
            }
        }
    }
    

    
    deinit {
    }
    
    private let imageView: SimpleLayer = SimpleLayer()
    private var backgroundView: NSView?
    
    public var useSharedAnimationPhase: Bool = true
    public var checkDarkPattern: Bool = true

    private let container: View = View()
    
    private var tileControl: TileControl

    public required init(frame frameRect: NSRect) {
        tileControl = TileControl(main: imageView)
        super.init(frame: frameRect)
//        imageView.disableActions()
        imageView.frame = frameRect.size.bounds
//        container.addSubview(imageView)
        autoresizesSubviews = false
        imageView.contentsGravity = .resize
        self.addSubview(container)
    }
    

    var contentViews: [NSView] {
        return self.subviews
    }

    
    open override func change(size: NSSize, animated: Bool, _ save: Bool = true, removeOnCompletion: Bool = true, duration: Double = 0.2, timingFunction: CAMediaTimingFunctionName = CAMediaTimingFunctionName.easeOut, completion: ((Bool) -> Void)? = nil) {
        super.change(size: size, animated: animated, save, removeOnCompletion: removeOnCompletion, duration: duration, timingFunction: timingFunction, completion: completion)
        
    }
    
    override init() {
        fatalError("not supported")
    }
    
    open override func layout() {
        super.layout()
        _customHandler?.layout?(self)
        self.updateLayout(size: frame.size, transition: .immediate)
    }
    
    public func doAction() {
        if let backgroundView = backgroundView as? AnimatedGradientBackgroundView {
            backgroundView.animateEvent(transition: .animated(duration: 0.5, curve: .spring))
        }
    }
    
    open override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
    }
    
    open override var isFlipped: Bool {
        return true
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open var backgroundMode:TableBackgroundMode = .plain {
        didSet {
            if oldValue != backgroundMode {
//                CATransaction.begin()
//                CATransaction.setDisableActions(true)
                tileControl.validLayout = nil
                var backgroundView: NSView? = nil
                switch backgroundMode {
                case let .background(image, intensity, colors, rotation, metadata):
                    imageView.backgroundColor = .clear
                    imageView.contents = image
                    let colors = colors?.map { $0.withAlphaComponent(1) }

                    var shouldTile = false
                    if let colors = colors, !colors.isEmpty {
                        
                        shouldTile = colors.count > 1
                        let intense = Float((abs(intensity ?? 50))) / 100.0
                        
                        let invertPattern = presentation.colors.isDark && checkDarkPattern || colors.count == 1
                        if invertPattern {
                            self.imageView.compositingFilter = nil
                            imageView.opacity = 1.0
                        } else {
                            self.imageView.compositingFilter = "softLightBlendMode"
                            imageView.opacity = intense
                        }

                        if colors.count > 2 {
                            if let bg = self.backgroundView as? AnimatedGradientBackgroundView {
                                backgroundView = bg
                                bg.updateColors(colors: colors)
                            } else {
                                backgroundView = AnimatedGradientBackgroundView(colors: colors, useSharedAnimationPhase: useSharedAnimationPhase)
                                backgroundView?.frame = bounds
                            }
                        } else {
                            if let bg = self.backgroundView as? BackgroundGradientView {
                                backgroundView = bg
                            } else {
                                let bg = BackgroundGradientView(frame: bounds)
                                backgroundView = bg
                            }
                            (backgroundView as? BackgroundGradientView)?.values = (top: colors.first, bottom: colors.last, rotation: rotation)
                        }
                    } else {
                        imageView.opacity = 1
                        imageView.compositingFilter = nil
                    }
                    if let bg = backgroundView as? AnimatedGradientBackgroundView {
                        tileControl.set(superlayer: bg.contentView.layer, tile: image, shouldTile: shouldTile)
                    } else if let bg = backgroundView as? BackgroundGradientView {
                        tileControl.set(superlayer: bg.layer, tile: image, shouldTile: shouldTile)
                    } else {
                        tileControl.set(superlayer: container.layer, tile: image, shouldTile: shouldTile)
                    }
                    self.isTiled = shouldTile
                    self.tileImageSize = image.size
                    
                    setSlotsMetadata(metadata)
                case let .color(color):
                    imageView.backgroundColor = color.withAlphaComponent(1.0).cgColor
                    imageView.compositingFilter = nil
                    imageView.contents = nil
                    imageView.opacity = 1
                    tileControl.set(superlayer: container.layer!, tile: nil, shouldTile: false)
                    setSlotsMetadata(nil)
                case let .gradient(colors, rotation):
                    let colors = colors.map { $0.withAlphaComponent(1) }
                    imageView.contents = nil
                    imageView.backgroundColor = .clear
                    imageView.opacity = 1
                    imageView.compositingFilter = nil
                    imageView.removeFromSuperlayer()
                    tileControl.set(superlayer: nil, tile: nil, shouldTile: false)
                    if colors.count > 2 {
                        if let bg = self.backgroundView as? AnimatedGradientBackgroundView {
                            backgroundView = bg
                            bg.updateColors(colors: colors)
                        } else {
                            backgroundView = AnimatedGradientBackgroundView(colors: colors, useSharedAnimationPhase: useSharedAnimationPhase)
                            backgroundView?.frame = bounds
                        }
                    } else {
                        if let bg = self.backgroundView as? BackgroundGradientView {
                            backgroundView = bg
                        } else {
                            let bg = BackgroundGradientView(frame: bounds)
                            backgroundView = bg
                        }
                        (backgroundView as? BackgroundGradientView)?.values = (top: colors.first, bottom: colors.last, rotation: rotation)
                    }
                    setSlotsMetadata(nil)
                default:
                    imageView.backgroundColor = presentation.colors.background.cgColor
                    imageView.contents = nil
                    imageView.compositingFilter = nil
                    imageView.opacity = 1
                    imageView.removeFromSuperlayer()
                    tileControl.set(superlayer: nil, tile: nil, shouldTile: false)
                    setSlotsMetadata(nil)
                }
                
                tileControl.update(frame: bounds, transition: .immediate)
                
                if let backgroundView = backgroundView {
                    self.backgroundView?.removeFromSuperview()
                    self.backgroundView = backgroundView
                    container.addSubview(backgroundView)
                } else {
                    self.backgroundView?.removeFromSuperview()
                    self.backgroundView = nil
                }
            }
//            CATransaction.commit()
        }
    }
    
    open func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(layer: imageView, frame: size.bounds)
        transition.updateFrame(view: container, frame: size.bounds)
        tileControl.update(frame: size.bounds, transition: transition)
        if let backgroundView = backgroundView {
            transition.updateFrame(view: backgroundView, frame: size.bounds)
            if let backgroundView = backgroundView as? AnimatedGradientBackgroundView {
                backgroundView.updateLayout(size: size, transition: transition)
            }
        }
        updateSlotOverlaysLayout(size: size)
    }

    open override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        // .plain bakes presentation.colors.background into imageView at the
        // moment `backgroundMode` was set; re-resolve so a dark/light flip
        // doesn't leave a stale color behind. Other modes carry their own
        // pre-resolved image/gradient and don't need a refresh here.
        switch backgroundMode {
        case .plain:
            imageView.backgroundColor = presentation.colors.background.cgColor
        default:
            break
        }
    }
    private(set) var isCopy: Bool = false
    override open func copy() -> Any {
        let view = BackgroundView(frame: self.frame)
        view.isCopy = true
        view.backgroundMode = self.backgroundMode
        view.useSharedAnimationPhase = true
        view.updateLayout(size: view.frame.size, transition: .immediate)
        return view
    }
    
    open func copy(_ backgroundMode: TableBackgroundMode?) -> BackgroundView {
        let view = BackgroundView(frame: self.frame)
        view.isCopy = true
        view.backgroundMode = backgroundMode ?? self.backgroundMode
        view.useSharedAnimationPhase = true
        view.updateLayout(size: view.frame.size, transition: .immediate)
        return view
    }
}




public enum ViewControllerLifecycleHooks {
    public static var willAppear: ((ViewController) -> Void)?
    public static var didAppear: ((ViewController) -> Void)?
    public static var didDisappear: ((ViewController) -> Void)?
    public static var didDeinit: ((ObjectIdentifier) -> Void)?
}

open class ViewController : NSObject {
    
    
    public struct StakeSettings {
        
        
        public let keepLeft: CGFloat
        public let straightMove: Bool
        public let keepIn: Bool
        public let keepTop: ()->CGFloat
        public var isCustom: Bool {
            if keepLeft > 0 {
                return true
            }
            if straightMove {
                return true
            }
            if keepIn {
                return true
            }
            if keepTop() > 0 {
                return true
            }
            return false
        }
        
        public init(keepLeft: CGFloat, keepTop: @escaping()->CGFloat, straightMove: Bool, keepIn: Bool) {
            self.keepLeft = keepLeft
            self.straightMove = straightMove
            self.keepIn = keepIn
            self.keepTop = keepTop
        }
        
        public static var `default`: StakeSettings {
            return .init(keepLeft: 0, keepTop: { 0 }, straightMove: false, keepIn: false)
        }
    }
    
    public var _window: Window?

    
    fileprivate var _view:NSView?
    public var _frameRect:NSRect
    
    public var atomicSize:Atomic<NSSize> = Atomic(value:NSZeroSize)
    
    public var onDeinit: (()->Void)? = nil
    
    weak open var navigationController:NavigationViewController? {
        didSet {
            if navigationController != oldValue {
                updateNavigation(navigationController)
            }
        }
    }
    
    open func swapNavigationBar(leftView: BarView?, centerView: BarView?, rightView: BarView?, animation: NavigationBarSwapAnimation) {
        self.navigationController?.swapNavigationBar(leftView: leftView, centerView: centerView, rightView: rightView, animation: animation)
    }
    
    public var noticeResizeWhenLoaded: Bool = true

    public var animationStyle:AnimationStyle = AnimationStyle(duration: 0.4, function:CAMediaTimingFunctionName.spring)
    public var bar:NavigationBarStyle = NavigationBarStyle(height: NavigationBarStyle.defaultHeight)

    /// Insets applied by the navigation container (or `SplitView`) when laying out
    /// this controller's view. The view is positioned at `(insets.left, insets.top)`
    /// and sized so that `insets.right` / `insets.bottom` of empty space remain on
    /// the trailing sides. Default is 5px on every side; controllers that should
    /// fill their container edge-to-edge (e.g. `ChatController`) assign `.zero`
    /// to this property in their init.
    public var insets: NSEdgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)

    public private(set) var containerContentInsets: NSEdgeInsets = NSEdgeInsets()

    open func updateContainerContentInsets(_ insets: NSEdgeInsets, transition: ContainedViewLayoutTransition) {
        containerContentInsets = insets
    }

    /// When this controller is placed in a `SplitView` that grants it the full
    /// container width (rather than its logical pane width), `slotLeadingInset`
    /// is the x coordinate where the original logical pane began. Controllers
    /// that host other controllers (e.g. `NavigationViewController`) use this
    /// to keep their content aligned with the split pane slot while the outer
    /// view spans the full container.
    public var slotLeadingInset: CGFloat = 0 {
        didSet {
            if slotLeadingInset != oldValue, isLoaded() {
                viewDidResized(view.frame.size)
            }
        }
    }

    public var slotTrailingInset: CGFloat = 0 {
        didSet {
            if slotTrailingInset != oldValue, isLoaded() {
                viewDidResized(view.frame.size)
            }
        }
    }

    /// Corner radius applied to the per-controller `ControllerContainer` that
    /// wraps this controller in a `NavigationViewController`. Default is 20.
    /// Controllers nested inside an already-rounded outer container (e.g. the
    /// borderless GroupCall window) should override this to `0` so the inner
    /// container does not double-clip.
    open var containerCornerRadius: CGFloat { return 20 }

    open var wantsContainerGlass: Bool { return false }

    public var leftBarView:BarView!
    public var centerBarView:TitledBarView!
    public var rightBarView:BarView!
    
    public var popover:Popover?
    open var modal:Modal?
    
    open var barHeight: CGFloat {
        return bar.height
    }
    
    open var barIsReal: Bool {
        return false
    }
    
    open var barPresentation: ControlStyle {
        return navigationButtonStyle
    }
    
    var widthOnDisappear: CGFloat? = nil
    
    public var ableToNextController:(ViewController, @escaping(ViewController, Bool)->Void)->Void = { controller, f in
        f(controller, true)
    }
    
    private let _ready = Promise<Bool>()
    open var ready: Promise<Bool> {
        return self._ready
    }
    public var didSetReady:Bool = false
    
    public let isKeyWindow:Promise<Bool> = Promise(false)
    
    private let _viewOnState: ValuePromise<Bool> = .init(false, ignoreRepeated: true)
    public var viewOnStage: Signal<Bool, NoError> {
        return _viewOnState.get()
    }
    
    open var view:NSView {
        get {
            if(_view == nil) {
                loadView();
            }
            
            return _view!;
        }
       
    }
    
    open var redirectUserInterfaceCalls: Bool {
        return false
    }
    
    public var backgroundColor: NSColor {
        set {
            self.view.background = newValue
        }
        get {
            return self.view.background
        }
    }

    /// Background color applied to this controller's surrounding
    /// `ControllerContainer` (the rounded, navigation-bar-owning wrapper
    /// installed by `NavigationViewController`). Default is
    /// `presentation.colors.listBackground`. Controllers that want a
    /// transparent container (e.g. ChatController, which paints its own
    /// wallpaper) should override to `.clear`.
    open var backdorColor: NSColor {
        return presentation.colors.listBackground
    }
    
    open var enableBack:Bool {
        return false
    }
    
    open var isAutoclosePopover: Bool {
        return true
    }

    open var popoverBackgroundColor: NSColor {
        return presentation.colors.background
    }
    
    open func menuItems() -> [ContextMenuItem] {
        return []
    }
    open var isOnScreen: Bool {
        return self.navigationController?.controller == self && !hasModals()
    }
    
    open func executeReturn() -> Void {
        self.navigationController?.back()
    }
    
    open func measure(size:NSSize) {
        
    }
    
    open func updateNavigation(_ navigation:NavigationViewController?) {
        
    }
    
    open var rightSwipeController: ViewController? {
        return nil
    }
    
    open func navigationWillChangeController() {
        
    }
    
    open var sidebar:ViewController? {
        return nil
    }
    
    open var supportSwipes: Bool {
        return true
    }
    
    public let internalId:Int = Int(arc4random());
    
    public override init() {
        _frameRect = NSZeroRect
        super.init()
    }
    
    public init(frame frameRect:NSRect) {
        _frameRect = frameRect;
    }
    
    open func readyOnce() -> Void {
        if !didSetReady {
            didSetReady = true
            ready.set(.single(true))
        }
    }
    
    open func updateLocalizationAndTheme(theme: PresentationTheme) {
        (view as? AppearanceViewProtocol)?.updateLocalizationAndTheme(theme: theme)
      //  self.navigationController?.updateLocalizationAndTheme(theme: theme)
    }
    
    open func loadView() -> Void {
        if(_view == nil) {
            
            leftBarView = getLeftBarViewOnce()
            centerBarView = getCenterBarViewOnce()
            rightBarView = getRightBarViewOnce()
            
            _view = defaultInitializer();
            _view?.autoresizingMask = [.width,.height]
            
            NotificationCenter.default.addObserver(self, selector: #selector(viewFrameChanged(_:)), name: NSView.frameDidChangeNotification, object: _view!)
            
            _ = atomicSize.swap(_view!.frame.size)
            viewDidLoad()
        }
    }
    
    open func defaultInitializer() -> NSView {
        let vz = viewClass() as! NSView.Type
        return vz.init(frame: _frameRect)
    }
    
    open func navigationHeaderDidNoticeAnimation(_ current: CGFloat, _ previous: CGFloat, _ animated: Bool) -> ()->Void  {
        return {}
    }
    

    
    open func requestUpdateBackBar() {
        if isLoaded(), let leftBarView = leftBarView as? BackNavigationBar {
            leftBarView.requestUpdate()
        }
        self.leftBarView.style = barPresentation
    }
    
    open func requestUpdateCenterBar() {
        setCenterTitle(defaultBarTitle)
        setCenterStatus(defaultBarStatus)
        self.centerBarView.style = barPresentation
    }
    open func requestUpdateRightBar() {
        self.rightBarView.style = barPresentation
    }
    
    
    open func dismiss() {
        if navigationController?.controller === self {
            navigationController?.back()
        } 
    }
    

    
    @objc func viewFrameChanged(_ notification:Notification) {
        if atomicSize.with({ $0 != frame.size}) {
            viewDidResized(frame.size)
        }
    }
    public private(set) var bgMode: TableBackgroundMode?
    
    open func updateBackgroundColor(_ backgroundMode: TableBackgroundMode) {
        self.bgMode = backgroundMode
        switch backgroundMode {
        case .background, .gradient:
            backgroundColor = .clear
        case let .color(color):
            backgroundColor = color
        default:
            backgroundColor = presentation.colors.background
        }
        if let nav = navigationController {
            nav.existingContainerOf(self)?.updateBackgroundMode(backgroundMode)
        }
    }
    
    open func updateController() {
        
    }
    
    open func viewDidResized(_ size:NSSize) {
        _ = atomicSize.swap(size)
    }
    
    open func draggingExited() {
        
    }
    open func draggingEntered() {
        
    }
    
    open func focusSearch(animated: Bool, text: String? = nil) {
        
    }
    
    open func invokeNavigationBack() -> Bool {
        return true
    }
    
    
    
    open func updateFrame(_ frame: NSRect, transition: ContainedViewLayoutTransition) {
        if isLoaded() {
            transition.updateFrame(view: self.view, frame: frame)
        }
    }

    open func updateFrame(_ frame: NSRect, inset: CGFloat, transition: ContainedViewLayoutTransition) {
        updateFrame(frame, transition: transition)
    }

    public private(set) var navigationHeaderOverflow: CGFloat = 0

    open func updateNavigationHeaderOverflow(_ overflow: CGFloat, transition: ContainedViewLayoutTransition) {
        self.navigationHeaderOverflow = overflow
    }

    open var absorbsNavigationHeaderOverflow: Bool {
        return false
    }
    
    open func getLeftBarViewOnce() -> BarView {
        return enableBack ? BackNavigationBar(self) : BarView(controller: self)
    }
    
    open var defaultBarTitle:String {
        return localizedString(self.className)
    }
    open var defaultBarStatus:String? {
        return nil
    }

    
    open func getCenterBarViewOnce() -> TitledBarView {
        return TitledBarView(controller: self, .initialize(string: defaultBarTitle, color: barPresentation.textColor, font: .medium(.title)))
    }
    
    open func setCenterTitle(_ text:String) {
        self.centerBarView.text = .initialize(string: text, color: barPresentation.textColor, font: .medium(.title))
    }
    open func setCenterStatus(_ text: String?) {
        if let text = text {
            self.centerBarView.status = .initialize(string: text, color: barPresentation.grayTextColor, font: .normal(.text))
        } else {
            self.centerBarView.status = nil
        }
    }
    open func getRightBarViewOnce() -> BarView {
        return BarView(controller: self)
    }
    
    open var abolishWhenNavigationSame: Bool {
        return false
    }
    
    open func viewClass() ->AnyClass {
        return View.self
    }
    
    open func draggingItems(for pasteboard:NSPasteboard) -> [DragItem] {
        return []
    }
    
    public func loadViewIfNeeded(_ frame:NSRect = NSZeroRect) -> Void {
        
         guard _view != nil else {
            if !NSIsEmptyRect(frame) {
                _frameRect = frame
            }
            self.loadView()
            
            return
        }
    }
    
    open func viewDidLoad() -> Void {
        if noticeResizeWhenLoaded {
            viewDidResized(view.frame.size)
        }
    }
    
    
    
    open func viewWillAppear(_ animated:Bool) -> Void {
        ViewControllerLifecycleHooks.willAppear?(self)
        _viewOnState.set(true)
    }

    open func readyToDetach() {

    }
    
    open func setToNextController(_ controller: ViewController, style: ViewControllerStyle) {
        
    }
    open func setToPreviousController(_ controller: ViewController, style: ViewControllerStyle) {
        
    }
    open var stake: StakeSettings {
        return .default
    }

    /// When `true`, push/pop/swipe transitions fully slide the previous
    /// controller out by `frame.width` (instead of the default 1/3 parallax).
    /// Override in controllers that should animate as a real full slide.
    open var fullSlideAnimation: Bool {
        return false
    }

    open weak var tied: ViewController?
    
    open func updateSwipingState(_ state: SwipeState, controller: ViewController, isPrevious: Bool) -> Void {
        
    }
    
    deinit {
        self.window?.removeObserver(for: self)
        self.window?.removeAllHandlers(for: self)
        NotificationCenter.default.removeObserver(self)
        assertOnMainThread()
        self.onDeinit?()
        ViewControllerLifecycleHooks.didDeinit?(ObjectIdentifier(self))
    }
    
    
    open func viewWillDisappear(_ animated:Bool) -> Void {
        widthOnDisappear = frame.width
        //assert(self.window != nil)
        if canBecomeResponder {
            self.window?.removeObserver(for: self)
        }
        if hasNextResponder {
            self.window?.remove(object: self, for: .Tab)
        }
        NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
        isKeyWindow.set(.single(false))
        _viewOnState.set(false)
    }
    
    public func isLoaded() -> Bool {
        return _view != nil
    }
    
    open func viewDidAppear(_ animated:Bool) -> Void {
        ViewControllerLifecycleHooks.didAppear?(self)
        //assert(self.window != nil)
        if hasNextResponder {
            self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
                guard let `self` = self else {return .rejected}
                
                _ = self.window?.makeFirstResponder(self.nextResponder())
                
                return .invoked
            }, with: self, for: .Tab, priority: responderPriority)
        }
        
        if canBecomeResponder {
            self.window?.set(responder: {[weak self] () -> NSResponder? in
                return self?.firstResponder()
            }, with: self, priority: responderPriority)
            
            if let become = becomeFirstResponder(), become == true {
                self.window?.applyResponderIfNeeded()
            } else {
                _ = self.window?.makeFirstResponder(self.window?.firstResponder)
            }
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeKey), name: NSWindow.didBecomeKeyNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidResignKey), name: NSWindow.didResignKeyNotification, object: window)
        if let window = window {
            isKeyWindow.set(.single(window.isKeyWindow))
        }
        
        func findTableView(in view: NSView) -> Void {
            for subview in view.subviews {
                if subview is NSTableView {
                    if !subview.inLiveResize {
                        subview.viewDidEndLiveResize()
                    }
                } else if !subview.subviews.isEmpty {
                    findTableView(in: subview)
                }
            }
        }
        if let widthOnDisappear = widthOnDisappear, frame.width != widthOnDisappear {
            findTableView(in: view)
        }
    }
    
    
    
    @objc open func windowDidBecomeKey() {
        isKeyWindow.set(.single(true))
    }
    
    @objc open func windowDidResignKey() {
        isKeyWindow.set(.single(false))
    }
    
    open var canBecomeResponder: Bool {
        return true
    }
    
    open var removeAfterDisapper:Bool {
        return false
    }
    
    open func escapeKeyAction() -> KeyHandlerResult {
        return .rejected
    }
    
    open func backKeyAction() -> KeyHandlerResult {
        if let event = NSApp.currentEvent, event.modifierFlags.contains(.shift), let textView = window?.firstResponder as? TextView, let layout = textView.textLayout, layout.selectedRange.range.max != 0 {
            layout.selectPrevChar()
            textView.needsDisplay = true
            return .invoked
        }
        return .rejected
    }
    
    open func nextKeyAction() -> KeyHandlerResult {
        if let event = NSApp.currentEvent, event.modifierFlags.contains(.shift), let textView = window?.firstResponder as? TextView, let layout = textView.textLayout, layout.selectedRange.range.max != 0 {
            layout.selectNextChar()
            textView.needsDisplay = true
            return .invoked
        }
        return .invokeNext
    }
    
    open func returnKeyAction() -> KeyHandlerResult {
        return .rejected
    }
    
    open func didRemovedFromStack() -> Void {
        
    }
    
    open func viewDidDisappear(_ animated:Bool) -> Void {
        ViewControllerLifecycleHooks.didDisappear?(self)
    }
    
    open func scrollup(force: Bool = false) {
        
    }
    
    open func becomeFirstResponder() -> Bool? {

        return false
    }
    
    open var window:Window? {
        return _window ?? _view?.window as? Window
    }
    
    open func firstResponder() -> NSResponder? {
        return nil
    }
    
    open func nextResponder() -> NSResponder? {
        return nil
    }
    
    open var hasNextResponder: Bool {
        return false
    }
    
    open var responderPriority:HandlerPriority {
        return .low
    }
    
    
    
    public var frame:NSRect {
        get {
            return isLoaded() ? self.view.frame : _frameRect
        }
        set {
            self.view.frame = newValue
        }
    }
    public var bounds:NSRect {
        return isLoaded() ? self.view.bounds : NSMakeRect(0, 0, _frameRect.width, _frameRect.height - bar.height)
    }
    
    open var isOpaque: Bool {
        return true
    }
    
    func removeBackgroundCap() {
        for subview in view.subviews.reversed() {
            if let subview = subview as? BackgroundView, subview.isCopy {
                subview.removeFromSuperview()
            }
        }
    }
    
    public func addSubview(_ subview:NSView) -> Void {
        self.view.addSubview(subview)
    }
    
    
    
    public func removeFromSuperview() ->Void {
        if isLoaded() {
            self.view.removeFromSuperview()
        }
    }
    
    
    open func backSettings() -> (String,CGImage?) {
        return (localizedString("Navigation.back"),#imageLiteral(resourceName: "Icon_NavigationBack").precomposed(barPresentation.foregroundColor))
    }
    
    open var popoverClass:AnyClass {
        return Popover.self
    }
    
    open func show(for control:Control, edge:NSRectEdge? = nil, inset:NSPoint = NSZeroPoint, static: Bool = false) -> Void {
        if popover == nil {
            self.popover = (self.popoverClass as! Popover.Type).init(controller: self, static: `static`, animationMode: .classic)
        }
        
        if let popover = popover {
            popover.show(for: control, edge: edge, inset: inset)
        }
    }
    
    open func closePopover() -> Void {
        self.popover?.hide()
    }
    
    open func invokeNavigation(action:NavigationModalAction) {
        _ = (self.ready.get() |> take(1) |> deliverOnMainQueue).start(next: { (ready) in
            action.close()
        })
    }
    
}


open class GenericViewController<T> : ViewController where T:NSView {
    public var genericView:T {
        return super.view as! T
    }
    
    open override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
    }
    
    deinit {
        var bp:Int = 0
        bp += 1
    }
    
    override open func loadView() -> Void {
        if(_view == nil) {
            
            leftBarView = getLeftBarViewOnce()
            centerBarView = getCenterBarViewOnce()
            rightBarView = getRightBarViewOnce()

            
            _view = initializer()
            _view?.wantsLayer = true
            _view?.autoresizingMask = [.width,.height]
            
            NotificationCenter.default.addObserver(self, selector: #selector(viewFrameChanged(_:)), name: NSView.frameDidChangeNotification, object: _view!)
            
            _ = atomicSize.swap(_view!.frame.size)
        }
        viewDidLoad()
    }
    
    public var initializationRect: NSRect {
        return NSMakeRect(_frameRect.minX, _frameRect.minY, _frameRect.width - self.stake.keepLeft, _frameRect.height - bar.height)
    }
    

    open func initializer() -> T {
        let vz = T.self as NSView.Type
        //controller.bar.height
        return vz.init(frame: initializationRect) as! T
    }
    
}

public struct ModalHeaderData {
    public let title: String?
    public let subtitle: String?
    public let image: CGImage?
    public let handler: (()-> Void)?
    public let contextMenu:(()->[ContextMenuItem])?
    public let isCloseButton: Bool
    public let attributedTitle: NSAttributedString?
    public let titleLinkHandler: ((Any) -> Void)?
    public init(title: String? = nil, subtitle: String? = nil, image: CGImage? = nil, handler: (()->Void)? = nil, contextMenu:(()->[ContextMenuItem])? = nil, isCloseButton: Bool = true, attributedTitle: NSAttributedString? = nil, titleLinkHandler: ((Any) -> Void)? = nil) {
        self.title = title
        self.image = image
        self.subtitle = subtitle
        self.handler = handler
        self.contextMenu = contextMenu
        self.isCloseButton = isCloseButton
        self.attributedTitle = attributedTitle
        self.titleLinkHandler = titleLinkHandler
    }
}

public protocol ModalControllerHelper {
    var modalInteractions:ModalInteractions? { get }
}

open class ModalViewController : ViewController, ModalControllerHelper {
    
    public struct Theme {
        let text: NSColor
        let grayText: NSColor
        let background: NSColor
        let border: NSColor
        let accent: NSColor
        let grayForeground: NSColor
        let activeBackground: NSColor
        let activeBorder: NSColor
        let listBackground: NSColor
        let hideUnactiveText: Bool
        public init(text: NSColor = presentation.colors.text, grayText: NSColor = presentation.colors.grayText, background: NSColor = .clear, border: NSColor = presentation.colors.border, accent: NSColor = presentation.colors.accent, grayForeground: NSColor = presentation.colors.grayForeground, activeBackground: NSColor = presentation.colors.background, activeBorder: NSColor = presentation.colors.border, listBackground: NSColor = presentation.colors.listBackground, hideUnactiveText: Bool = false) {
            self.text = text
            self.hideUnactiveText = hideUnactiveText
            self.grayText = grayText
            self.background = background
            self.border = border
            self.accent = accent
            self.grayForeground = grayForeground
            self.activeBackground = activeBackground
            self.activeBorder = activeBorder
            self.listBackground = listBackground
        }
        public init(presentation: PresentationTheme) {
            self.text = presentation.colors.text
            self.grayText = presentation.colors.grayText
            self.background = presentation.colors.background
            self.border = presentation.colors.border
            self.accent = presentation.colors.accent
            self.grayForeground = presentation.colors.grayForeground
            self.activeBackground = presentation.colors.background
            self.activeBorder = presentation.colors.border
            self.listBackground = presentation.colors.listBackground
            self.hideUnactiveText = false
        }
    }
    
    
    open var modalTheme:Theme {
        return Theme()
    }
    
    open var hasBorder: Bool {
        return true
    }
    
    open var closable:Bool {
        return true
    }
    
    // use this only for modal progress. This is made specially for nsvisualeffect support.
    open var contentBelowBackground: Bool {
        return false
    }
    
    open var shouldCloseAllTheSameModals: Bool {
        return true
    }
    
    
    open var hasOwnTouchbar: Bool {
        return true
    }
    
    open var background:NSColor {
        return NSColor(0x000000, 0.6)
    }
    
    open func didResizeView(_ size: NSSize, animated: Bool) -> Void {
        
    }
    
    open var isVisualEffectBackground: Bool {
        return false
    }
    open var isVisualEffectContainer: Bool {
        return false
    }
    
    open var isFullScreen:Bool {
        return false
    }
    
    open var cornerRadius: CGFloat {
        return 20
    }
    
    open var redirectMouseAfterClosing: Bool {
        return false
    }
    
    open var containerBackground: NSColor {
        return presentation.colors.background
    }
    open var headerBackground: NSColor {
        return presentation.colors.background
    }
    open var headerBorderColor: NSColor {
        return presentation.colors.border
    }
    
    open var dynamicSize:Bool {
        return false
    }
    
    open override func becomeFirstResponder() -> Bool? {
        return true
    }
    
 
    
    open var modalInteractions:ModalInteractions? {
        return nil
    }
    open var modalHeader: (left:ModalHeaderData?, center: ModalHeaderData?, right: ModalHeaderData?)? {
        return nil
    }
    
    open override var responderPriority: HandlerPriority {
        return .modal
    }
    
    open override func firstResponder() -> NSResponder? {
        return self.view
    }
    
    open func close(animationType: ModalAnimationCloseBehaviour = .common) {
        modal?.close(animationType: animationType)
    }
    
    open var handleEvents:Bool {
        return true
    }
    
    open var handleAllEvents: Bool {
        return true
    }
    
    override open func loadView() -> Void {
        if(_view == nil) {
            
            _view = initializer()
            _view?.autoresizingMask = [.width,.height]
            
            NotificationCenter.default.addObserver(self, selector: #selector(viewFrameChanged(_:)), name: NSView.frameDidChangeNotification, object: _view!)
            
            _ = atomicSize.swap(_view!.frame.size)
        }
        viewDidLoad()
    }
    
    open func initializer() -> NSView {
        let vz = viewClass() as! NSView.Type
        return vz.init(frame: NSMakeRect(_frameRect.minX, _frameRect.minY, _frameRect.width, _frameRect.height - bar.height));
    }

}

open class ModalController : ModalViewController {
    public let controller: NavigationViewController
    public init(_ controller: NavigationViewController) {
        self.controller = controller
        super.init(frame: controller._frameRect)
    }

    open override var handleEvents: Bool {
        return true
    }
    
    open override var modalInteractions: ModalInteractions? {
        return (self.controller.controller as? ModalControllerHelper)?.modalInteractions
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        ViewControllerLifecycleHooks.willAppear?(self)
        self.controller.viewWillAppear(animated)
    }
    open override func viewWillDisappear(_ animated: Bool) {
        self.controller.viewWillDisappear(animated)
    }
    open override func viewDidAppear(_ animated: Bool) {
        ViewControllerLifecycleHooks.didAppear?(self)
        self.controller.viewDidAppear(animated)
    }
    open override func viewDidDisappear(_ animated: Bool) {
        self.controller.viewDidDisappear(animated)
        ViewControllerLifecycleHooks.didDisappear?(self)
    }
    open override func firstResponder() -> NSResponder? {
        return controller.controller.firstResponder()
    }
    
    open override func returnKeyAction() -> KeyHandlerResult {
        return controller.controller.returnKeyAction()
    }
    
    open override func escapeKeyAction() -> KeyHandlerResult {
        return controller.controller.escapeKeyAction()
    }

    open override var hasBorder: Bool {
        return false
    }
    
    open override var hasNextResponder: Bool {
        return true
    }
    
    open override func nextResponder() -> NSResponder? {
        return controller.controller.nextResponder()
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        ready.set(controller.controller.ready.get())
    }
    
    open override func becomeFirstResponder() -> Bool? {
        return nil
    }
    
    
    open override func loadView() {
        self._view = controller.view
        NotificationCenter.default.addObserver(self, selector: #selector(viewFrameChanged(_:)), name: NSView.frameDidChangeNotification, object: _view!)
        
        _ = atomicSize.swap(_view!.frame.size)
        viewDidLoad()
    }
}


