import Cocoa
import TGUIKit
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
#endif


open class GeneralContainableRowView : TableRowView {
    public let containerView = GeneralRowContainerView(frame: NSZeroRect)
    public let borderView = SimpleLayer()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        super.addSubview(self.containerView)
        borderView.anchorPoint = .zero
        containerView.layer?.insertSublayer(borderView, at: 0)
    }
    
    open override var firstResponder: NSResponder? {
        return nil
    }
    
    deinit {
        self.containerView.removeAllSubviews()
    }
    
    open override func addSubview(_ view: NSView) {
        self.containerView.addSubview(view)
    }
    
    open override func addSubview(_ view: NSView, positioned place: NSWindow.OrderingMode, relativeTo otherView: NSView?) {
        self.containerView.addSubview(view, positioned: place, relativeTo: otherView)
    }
    
    open func addBasicSubview(_ view: NSView, positioned place: NSWindow.OrderingMode) {
        subviews.insert(view, at: place == .below ? 0 : 1)
    }
    
    open override var backdorColor: NSColor {
        return theme.colors.background
    }
    
    open override var mouseDownCanMoveWindow: Bool {
        return false
    }
    
    open override var borderColor: NSColor {
        return theme.colors.border
    }
    
    open override func updateColors() {
        guard let item = item as? GeneralRowItem else {
            return
        }
        self.backgroundColor = item.viewType.rowBackground
        self.containerView.backgroundColor = backdorColor
        self.borderView.backgroundColor = borderColor.cgColor
    }
    
    open var maxBlockWidth: CGFloat {
        guard let item = item as? GeneralRowItem else {
            return 600
        }
        return item.fullSize ? frame.width : 600
    }
    open var maxWidth: CGFloat {
        return frame.width
    }
    open var maxHeight: CGFloat {
        return frame.height
    }
    
    open override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    open override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)

        guard let item = item as? GeneralRowItem else {
            return
        }
        let blockWidth = min(item.viewType == .legacy ? size.width : maxBlockWidth, size.width - item.inset.left - item.inset.right)

        let rect = NSMakeRect(floorToScreenPixels(backingScaleFactor, (size.width - blockWidth) / 2), item.inset.top, blockWidth, size.height - item.inset.bottom - item.inset.top)
        transition.updateFrame(view: self.containerView, frame: rect)

        self.containerView.setCorners(item.viewType.corners, animated: transition.isAnimated, frame: rect)

        transition.updateFrame(layer: borderView, frame: NSMakeRect(item.viewType.innerInset.left + additionBorderInset, containerView.frame.height - .borderSize, containerView.frame.width - item.viewType.innerInset.left - item.viewType.innerInset.right - additionBorderInset, .borderSize))
    }

    open var additionBorderInset: CGFloat {
        return 0
    }
    
    open override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? GeneralRowItem else {
            return
        }
        
        borderView.isHidden = !item.hasBorder
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

open class GeneralRowContainerView : Control, MorphCornerProviding {

    open override func isAccessibilityElement() -> Bool {
        var current = superview
        while let view = current {
            if let row = view as? TableRowView {
                return row.isAccessibilityElement() ? false : super.isAccessibilityElement()
            }
            current = view.superview
        }
        return super.isAccessibilityElement()
    }


    open var cornerRadius: CGFloat = 26
    // The visible rounding is drawn by `maskLayer`, not `layer.cornerRadius`, so report it for the morph.
    public var morphCornerRadius: CGFloat { return cornerRadius }
    // The row's layer is geometry-flipped (min-Y is the visual top, as createMask's arc order assumes), so a
    // visual top corner maps to a min-Y corner mask and a visual bottom corner to a max-Y one.
    public var morphCorners: CACornerMask {
        guard let corners = self.corners else {
            return [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
        var mask: CACornerMask = []
        if corners.contains(.topLeft) { mask.insert(.layerMinXMinYCorner) }
        if corners.contains(.topRight) { mask.insert(.layerMaxXMinYCorner) }
        if corners.contains(.bottomLeft) { mask.insert(.layerMinXMaxYCorner) }
        if corners.contains(.bottomRight) { mask.insert(.layerMaxXMaxYCorner) }
        return mask
    }

    private let maskLayer = CAShapeLayer()
    private var newPath: CGPath?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.mask = maskLayer
        self.maskLayer.disableActions()
    }
    
    private var corners: GeneralViewItemCorners? = nil
    open func setCorners(_ corners: GeneralViewItemCorners, animated: Bool = false, frame: NSRect? = nil) {
        if animated && self.corners != nil {
            let newPath = self.createMask(for: corners, frame: frame ?? self.frame)
            
            var oldPath: CGPath = self.maskLayer.path ?? CGMutablePath()
            
            if let presentation = self.maskLayer.presentation(), let _ = self.maskLayer.animation(forKey:"path") {
                oldPath = presentation.path ?? oldPath
                if newPath == self.newPath {
                    self.corners = corners
                    return
                }
            }
            self.newPath = newPath
            
            self.maskLayer.animate(from: oldPath, to: newPath, keyPath: "path", timingFunction: .easeOut, duration: 0.18, removeOnCompletion: false, additive: false, completion: { [weak self] _ in
                guard let self, self.newPath == newPath else {
                    return
                }
                self.maskLayer.removeAllAnimations()
                self.maskLayer.path = newPath
            })
            
        } else {
            self.newPath = nil
            self.maskLayer.removeAllAnimations()
            self.maskLayer.path = createMask(for: corners, frame: frame ?? self.bounds)
        }
        self.corners = corners
    }
    private func createMask(for corners: GeneralViewItemCorners, frame: NSRect) -> CGPath {

        if corners.contains(.topLeft) && corners.contains(.topRight) && corners.contains(.bottomLeft) && corners.contains(.bottomRight) {
            let radius = min(frame.height / 2, cornerRadius)
            return CGPath(roundedRect: CGRect(origin: .zero, size: frame.size), cornerWidth: radius, cornerHeight: radius, transform: nil)
        }

        let path = CGMutablePath()

        let minx:CGFloat = 0, midx = frame.width/2.0, maxx = frame.width
        let miny:CGFloat = 0, midy = frame.height/2.0, maxy = frame.height

        path.move(to: NSMakePoint(minx, midy))

        var topLeftRadius: CGFloat = 0
        var bottomLeftRadius: CGFloat = 0
        var topRightRadius: CGFloat = 0
        var bottomRightRadius: CGFloat = 0


        if corners.contains(.topLeft)  {
            bottomLeftRadius = cornerRadius
        }
        if corners.contains(.topRight) {
            bottomRightRadius = cornerRadius
        }
        if corners.contains(.bottomLeft) {
            topLeftRadius = cornerRadius
        }
        if corners.contains(.bottomRight) {
            topRightRadius = cornerRadius
        }

        path.addArc(tangent1End: NSMakePoint(minx, miny), tangent2End: NSMakePoint(midx, miny), radius: bottomLeftRadius)
        path.addArc(tangent1End: NSMakePoint(maxx, miny), tangent2End: NSMakePoint(maxx, midy), radius: bottomRightRadius)
        path.addArc(tangent1End: NSMakePoint(maxx, maxy), tangent2End: NSMakePoint(midx, maxy), radius: topRightRadius)
        path.addArc(tangent1End: NSMakePoint(minx, maxy), tangent2End: NSMakePoint(minx, midy), radius: topLeftRadius)


        return path
    }
    
    open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
    }
    
    open func change(size: NSSize, animated: Bool, corners: GeneralViewItemCorners) {
        super._change(size: size, animated: animated, animated, duration: 0.18)
        setCorners(corners, animated: animated, frame: NSMakeRect(0, 0, size.width, size.height))
    }
    
    open override func scrollWheel(with event: NSEvent) {
        superview?.scrollWheel(with: event)
    }
    
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


open class GeneralRowView: TableRowView,ViewDisplayDelegate {
    

     private var errorTextView: TextView? = nil
    
    open var general:GeneralRowItem? {
        return self.item as? GeneralRowItem
    }
    
    
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }
    
    open override var firstResponder: NSResponder? {
        return nil
    }
    
    
    
    open override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        if let item = item as? GeneralRowItem {
            self.border = item.border
            
            let minX = (frame.width - item.blockWidth) / 2

            
            if let errorLayout = item.errorLayout {
                let alphaAnimated = animated && errorTextView == nil
                let posAnimated = animated && errorTextView != nil
                if errorTextView == nil {
                    errorTextView = TextView()
                    errorTextView?.isSelectable = false
                    addSubview(errorTextView!)
                }
                errorTextView!.update(errorLayout)
                switch item.viewType {
                case .legacy:
                    errorTextView!.change(pos: NSMakePoint(item.inset.left, frame.height - 6 - errorLayout.layoutSize.height), animated: posAnimated)
                case let .modern(_, insets):
                    errorTextView!.change(pos: NSMakePoint(minX + insets.left, frame.height - 2 - errorLayout.layoutSize.height), animated: posAnimated)
                }
                if alphaAnimated {
                    errorTextView!.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            } else {
                if let errorTextView = self.errorTextView {
                    if animated {
                        self.errorTextView = nil
                        errorTextView.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, completion: { [weak errorTextView] _ in
                            errorTextView?.removeFromSuperview()
                        })
                    } else {
                        errorTextView.removeFromSuperview()
                        self.errorTextView = nil
                    }
                }
                
            }
        }
        self.needsDisplay = true
        self.needsLayout = true
    }


    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        
     //   let inset = general?.inset ?? NSEdgeInsets()
      //  overlay.frame = NSMakeRect(inset.left, 0, newSize.width - (inset.left + inset.right), newSize.height)
    }
    
    open override func layout() {
        
        guard let item = item as? GeneralRowItem else {return}

        let minX = (frame.width - item.blockWidth) / 2
        
        if let errorTextView = errorTextView {
            switch item.viewType {
            case .legacy:
                errorTextView.setFrameOrigin(item.inset.left, frame.height - 6 - errorTextView.frame.height)
            case let .modern(_, insets):
                errorTextView.setFrameOrigin(minX + insets.left, frame.height - 2
                    - errorTextView.frame.height)
            }
        }
    }
    
    open override var backdorColor: NSColor {
        
        guard let item = self.item as? GeneralRowItem else {
            return .clear
        }
        return item.backgroundColor
    }
    
    open override var mouseDownCanMoveWindow: Bool {
        if self.className == GeneralRowView.className() {
            return item?.table?._mouseDownCanMoveWindow ?? super.mouseDownCanMoveWindow
        } else {
            return false
        }
    }
    
}
