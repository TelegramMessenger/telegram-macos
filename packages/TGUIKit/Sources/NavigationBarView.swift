import Cocoa

public var navigationButtonStyle: ControlStyle {
    return ControlStyle(font: .medium(.title), foregroundColor: presentation.colors.text, backgroundColor: .clear, highlightColor: presentation.colors.text.withAlphaComponent(0.9))
}

public enum NavigationBarSwapAnimation {
    case none
    case crossfade
}

public struct NavigationBarStyle {
    /// Standard navigation bar height used across the app. Anywhere code
    /// needs to inset content beneath the nav bar (sticky-scrolling rows,
    /// scroll insets, anchored subviews), it should reference this
    /// constant instead of hard-coding `64`.
    public static let defaultHeight: CGFloat = 64

    public let height:CGFloat
    public let enableBorder:Bool
    public init(height:CGFloat, enableBorder:Bool = true, custom: Bool = false) {
        self.height = height
        self.enableBorder = enableBorder
    }

    public var has: Bool {
        return height > 0
    }
}

public class NavigationBarView: View {


    private var leftView:BarView = BarView(frame: NSZeroRect)
    private var centerView:BarView = BarView(frame: NSZeroRect)
    private var rightView:BarView = BarView(frame: NSZeroRect)

    /// Progressive blur for the navbar lives outside this view — in the
    /// `ControllerContainer.clippingView`, as a sibling of `contentView` and
    /// below the navbar in z-order. `CALayer.backgroundFilters` only blurs
    /// content drawn into the same superlayer, so the blur view has to sit
    /// next to the controller's content (not inside the navbar) to see it.
    public weak var navigationEdgeBlur: EdgeEffectView?

    public func setEdgeEffectOpacity(_ opacity: CGFloat, animated: Bool = false) {
        let clamped = max(0, min(1, opacity))
        guard let edge = navigationEdgeBlur else { return }
        if animated {
            edge.change(opacity: clamped, animated: true)
        } else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            edge.layer?.opacity = Float(clamped)
            CATransaction.commit()
        }
    }

    weak var navigation: NavigationViewController?



    override init() {
        super.init()
        updateLocalizationAndTheme(theme: presentation)
        layer?.masksToBounds = false
    }

    required public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false
        updateLocalizationAndTheme(theme: presentation)
    }

    override public func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        self.leftView.updateLocalizationAndTheme(theme: theme)
        self.centerView.updateLocalizationAndTheme(theme: theme)
        self.rightView.updateLocalizationAndTheme(theme: theme)
        backgroundColor = .clear
    }

    private func ensureSubviewOrder() {
        if leftView.superview === self {
            addSubview(leftView, positioned: .above, relativeTo: centerView)
        }
        if rightView.superview === self {
            addSubview(rightView, positioned: .above, relativeTo: leftView)
        }
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    public override func draw(_ layer: CALayer, in ctx: CGContext) {
        
        super.draw(layer, in: ctx)
//        ctx.setFillColor(NSColor.white.cgColor)
//        ctx.fill(self.bounds)
//
//        ctx.setFillColor(theme.colors.border.cgColor)
//        ctx.fill(NSMakeRect(0, NSHeight(self.frame) - .borderSize, NSWidth(self.frame), .borderSize))
    }
    
    override public func layout() {
        super.layout()

        self.layout(left: leftView, center: centerView, right: rightView, animated: false)
    }

    override public func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        
       // guard let window = window as? Window, !window.inLiveSwiping else {return}

    }
    
    public override var mouseDownCanMoveWindow: Bool {
        return true
    }
    
    var startPosition: CGFloat {
//        if let navigation = self.navigation {
//            return navigation.navigationBarLeftPosition
//        }
        return 0
    }
    
    
    public var usesWindowEdgeInsets: Bool = false {
        didSet {
            if usesWindowEdgeInsets != oldValue {
                needsLayout = true
            }
        }
    }

    private var appliesWindowEdgeInsets: Bool {
        return usesWindowEdgeInsets
    }

    private var edgeInset: CGFloat {
        return appliesWindowEdgeInsets ? System.windowEdgeInset : 12
    }

    private var itemsTopShift: CGFloat {
        return appliesWindowEdgeInsets ? System.windowEdgeInset - 12 : 0
    }
    public static let contentTopInset: NSEdgeInsets = NSEdgeInsets(top: 50)

    func layout(left: BarView, center: BarView, right: BarView, force: Bool = false, animated: Bool = false) -> Void {

        if frame.height > 0 {

            let transition: ContainedViewLayoutTransition = animated && !inLiveResize ? .animated(duration: 0.2, curve: .easeOut) : .immediate

            let edge = edgeInset
            let width = max(0, frame.width - startPosition - edge * 2)

            let rightWidth = right.fit(to: width / 2, transition: transition)
            let leftWidth = left.fit(to: width / 2, transition: transition)
            

            transition.updateFrame(view: left, frame: NSMakeRect(startPosition + edge, itemsTopShift, leftWidth, frame.height))
            transition.updateFrame(view: center, frame: NSMakeRect(0, 0, frame.width, frame.height))
            transition.updateFrame(view: right, frame: NSMakeRect(frame.width - rightWidth - edge, itemsTopShift, rightWidth, frame.height))

            left.updateLayout(size: NSMakeSize(leftWidth, frame.height), transition: transition)
            center.updateLayout(size: NSMakeSize(frame.width, frame.height), transition: transition)
            right.updateLayout(size: NSMakeSize(rightWidth, frame.height), transition: transition)
        }
    }
    
    // ! PUSH !
    //  left from center
    //  right cross fade
    //  center from right
    
    // ! POP !
    // old left -> new center
    // old center -> right
    // old right -> fade
    
    @objc func viewFrameChanged(_ notification:Notification) {
        guard let window = window as? Window, !window.inLiveSwiping else {return}
        layout(left: leftView, center: centerView, right: rightView, animated: true)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
        
    public func switchViews(left:BarView, center:BarView, right:BarView, controller:ViewController, style:ViewControllerStyle, animationStyle:AnimationStyle, liveSwiping: Bool) {
        
      //  var animationStyle = AnimationStyle.init(duration: 3.0, function: animationStyle.function)
        
        
        
        if !liveSwiping {
            layout(left: left, center: center, right: right, animated: false)
        }
        
        
//        NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: leftView)
//        NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: centerView)
//        NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: rightView)
        
        if style != .none {
            
            
            CATransaction.begin()
            
            let pLeft = self.leftView
            let pCenter = self.centerView
            let pRight = self.rightView

            self.leftView = left
            self.centerView = center
            self.rightView = right

            if !liveSwiping {
                addSubview(left)
                addSubview(center)
                addSubview(right)
                ensureSubviewOrder()
                left.layer?.opacity = 0
                center.layer?.opacity = 0
                right.layer?.opacity = 0
            }

            left.setNeedsDisplay()
            center.setNeedsDisplay()
            right.setNeedsDisplay()

            pLeft.updateLocalizationAndTheme(theme: presentation)
            pCenter.updateLocalizationAndTheme(theme: presentation)
            pRight.updateLocalizationAndTheme(theme: presentation)
            
            var pLeft_from:CGFloat = 0,pRight_from:CGFloat = 0, pCenter_from:CGFloat = 0, pLeft_to:CGFloat = 0, pRight_to:CGFloat = 0, pCenter_to:CGFloat = 0
            var nLeft_from:CGFloat = 0, nRight_from:CGFloat = 0, nCenter_from:CGFloat = 0, nLeft_to:CGFloat = 0, nRight_to:CGFloat = 0, nCenter_to:CGFloat = 0
            
            switch style {
            case .push:
                
                //left
                pLeft_from = liveSwiping ? pLeft.frame.minX : 0
                pLeft_to = startPosition
                nLeft_from = liveSwiping ? left.frame.minX : round(frame.width - left.frame.width)/2.0
                nLeft_to = startPosition
                
                //center
                pCenter_from = liveSwiping ? pCenter.frame.minX : pLeft.frame.width
                pCenter_to = 0
                
                nCenter_from = liveSwiping ? center.frame.minX : left.frame.width + center.frame.width
                nCenter_to = left.frame.width
                
                //right
                pRight_from = right.frame.minX
                pRight_to = right.frame.minX
                nRight_from = right.frame.minX
                nRight_to = right.frame.minX
                
                break
            case .pop:
                
                //left
                pLeft_from = liveSwiping ? pLeft.frame.minX : 0
                pLeft_to = startPosition
                nLeft_from = liveSwiping ? left.frame.minX : 0
                nLeft_to = startPosition
                
                //center
                pCenter_from = liveSwiping ? pCenter.frame.minX : center.frame.minX
                pCenter_to = left.frame.width + center.frame.width
                nCenter_from = liveSwiping ? center.frame.minX : 0
                nCenter_to = left.frame.maxX
                
                //right
                pRight_from = liveSwiping ? pRight.frame.minX : right.frame.minX
                pRight_to = right.frame.minX
                nRight_from = right.frame.minX
                nRight_to = right.frame.minX

                
                break
            case .none:
                break
            }
            
            
            
            left.setFrameOrigin(nLeft_from, left.frame.minY)
            center.setFrameOrigin(nCenter_from, center.frame.minY)
            right.setFrameOrigin(nRight_from, right.frame.minY)
            
            pLeft.setFrameOrigin(pLeft_from, left.frame.minY)
          //  pCenter.setFrameOrigin(pCenter_from, pCenter.frame.minY)
            pRight.setFrameOrigin(pRight_from, pRight.frame.minY)
            
                        
//
            // old
            pLeft.change(opacity: 0.0, duration: animationStyle.duration, timingFunction: animationStyle.function, completion:{ [weak pLeft] completed in
                if completed {
                    pLeft?.removeFromSuperview()
                }
            })
            pLeft.change(pos: NSMakePoint(pLeft_to, pLeft.frame.minY), animated: true, duration: animationStyle.duration, timingFunction: animationStyle.function)

            pCenter.change(opacity: 0.0, duration: animationStyle.duration, timingFunction: animationStyle.function, completion:{ [weak pCenter] completed in
                if completed {
                    pCenter?.removeFromSuperview()
                }
            })
         //   pCenter.change(pos: NSMakePoint(pCenter_to, pCenter.frame.minY), animated: true, duration: animationStyle.duration, timingFunction: animationStyle.function)

            
            pRight.change(opacity: 0.0, duration: animationStyle.duration, timingFunction: animationStyle.function, completion:{ [weak pRight] completed in
                if completed {
                    pRight?.removeFromSuperview()
                }
            })
            pRight.change(pos: NSMakePoint(pRight_to, pRight.frame.minY), animated: true, duration: animationStyle.duration, timingFunction: animationStyle.function)

            // new
            if !left.isHidden {
                left.change(opacity: 1.0, duration: animationStyle.duration, timingFunction: animationStyle.function)
            }
            left.change(pos: NSMakePoint(nLeft_to, left.frame.minY), animated: true, duration: animationStyle.duration, timingFunction: animationStyle.function)
           
            
            if !center.isHidden {
                center.change(opacity: 1.0, duration: animationStyle.duration, timingFunction: animationStyle.function)
            }
            
            center.change(pos: NSMakePoint(nCenter_to, center.frame.minY), animated: true, duration: animationStyle.duration, timingFunction: animationStyle.function)

            
            if !right.isHidden {
                right.change(opacity: 1.0, duration: animationStyle.duration, timingFunction: animationStyle.function)
            }
            right.change(pos: NSMakePoint(nRight_to, right.frame.minY), animated: true, duration: animationStyle.duration, timingFunction: animationStyle.function)

            
            
            CATransaction.commit()

        } else {
            self.leftView.removeFromSuperview()
            self.centerView.removeFromSuperview()
            self.rightView.removeFromSuperview()

            self.leftView = left
            self.centerView = center
            self.rightView = right

            addSubview(left)
            addSubview(center)
            addSubview(right)
            ensureSubviewOrder()

            left.layer?.opacity = 1
            center.layer?.opacity = 1
            right.layer?.opacity = 1

            layout()
        }
        
//        NotificationCenter.default.addObserver(self, selector: #selector(viewFrameChanged(_:)), name: NSView.frameDidChangeNotification, object: left)
//        NotificationCenter.default.addObserver(self, selector: #selector(viewFrameChanged(_:)), name: NSView.frameDidChangeNotification, object: center)
//        NotificationCenter.default.addObserver(self, selector: #selector(viewFrameChanged(_:)), name: NSView.frameDidChangeNotification, object: right)
        
    }
    
    private func applyAnimation(_ animation: NavigationBarSwapAnimation, from fromView: BarView, to toView: BarView) {

        toView.frame = fromView.frame

        switch animation {
        case .none:
            toView.layer?.opacity = 1.0
            fromView.removeFromSuperview()
            self.addSubview(toView)
            ensureSubviewOrder()
            toView.layer?.removeAllAnimations()
            fromView.layer?.removeAllAnimations()
        case .crossfade:
            self.addSubview(toView)
            ensureSubviewOrder()
            toView.layer?.opacity = 1.0
            toView.layer?.removeAllAnimations()
            toView.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            fromView.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak fromView] completed in
                if completed {
                    fromView?.removeFromSuperview()
                }
            })
        }
    }
    
    public func switchLeftView(_ barView: BarView, animation: NavigationBarSwapAnimation) {
        if self.leftView != barView {
            applyAnimation(animation, from: self.leftView, to: barView)
            self.leftView = barView
        }
        layout(left: leftView, center: centerView, right: rightView, animated: false)
    }
    public func switchCenterView(_ barView: BarView, animation: NavigationBarSwapAnimation) {
        if self.centerView != barView {
            applyAnimation(animation, from: self.centerView, to: barView)
            self.centerView = barView
        }
        layout(left: leftView, center: centerView, right: rightView, animated: false)
    }
    public func switchRightView(_ barView: BarView, animation: NavigationBarSwapAnimation) {
        if self.rightView != barView {
            applyAnimation(animation, from: self.rightView, to: barView)
            self.rightView = barView
        }
        layout(left: leftView, center: centerView, right: rightView, animated: false)
    }
}
