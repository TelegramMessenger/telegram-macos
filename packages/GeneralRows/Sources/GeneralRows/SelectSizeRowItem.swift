import Cocoa
import TGUIKit
import TelegramTheme
import ColorPalette
import Localization



public class SelectSizeRowItem: GeneralRowItem {

    fileprivate let titles:[String]?
    fileprivate let titlesImages:[CGImage]?
    fileprivate let sizes: [Int32]
    fileprivate var current: Int32
    fileprivate let initialCurrent: Int32
    fileprivate let selectAction:(Int)->Void
    fileprivate let hasMarkers: Bool
    fileprivate let dottedIndexes: [Int]
    public init(_ initialSize: NSSize, stableId: AnyHashable, current: Int32, sizes: [Int32], hasMarkers: Bool, titles:[String]? = nil, titlesImages: [CGImage]? = nil, dottedIndexes:[Int] = [], viewType: GeneralViewType = .legacy, selectAction: @escaping(Int)->Void) {
        self.sizes = sizes
        self.titles = titles
        self.titlesImages = titlesImages
        self.dottedIndexes = dottedIndexes
        self.initialCurrent = current
        self.hasMarkers = hasMarkers
        self.current = current
        self.selectAction = selectAction
        super.init(initialSize, height: titles != nil ? 70 : 40, stableId: stableId, viewType: viewType, inset: NSEdgeInsets(left: 20, right: 20))
    }
    
    public override func viewClass() -> AnyClass {
        return SelectSizeRowView.self
    }

    private func accessibilityTitle(at index: Int) -> String? {
        if let titles = titles, index >= 0, index < titles.count, !titles[index].isEmpty {
            return titles[index]
        }
        if index >= 0, index < sizes.count {
            return "\(sizes[index])"
        }
        return nil
    }

    public override var accessibilityLabel: String? {
        guard let first = accessibilityTitle(at: 0), let last = accessibilityTitle(at: sizes.count - 1) else {
            return nil
        }
        return "\(first) – \(last)"
    }

    public override var accessibilityValue: String? {
        return accessibilityTitle(at: sizes.firstIndex(of: current) ?? 0)
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .slider
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        return [
            NSAccessibilityCustomAction(name: strings().voiceOverCommonUp, handler: { [weak self] in
                return self?.accessibilityStep(1) ?? false
            }),
            NSAccessibilityCustomAction(name: strings().voiceOverCommonDown, handler: { [weak self] in
                return self?.accessibilityStep(-1) ?? false
            })
        ]
    }

    public override func accessibilityPerformPress() -> Bool {
        return false
    }

    private func accessibilityStep(_ delta: Int) -> Bool {
        guard let index = sizes.firstIndex(of: current) else {
            return false
        }
        let next = min(sizes.count - 1, max(0, index + delta))
        guard next != index else {
            return false
        }
        current = sizes[next]
        selectAction(next)
        redraw()
        return true
    }
    
    
}

private class SelectSizeRowView : TableRowView, ViewDisplayDelegate {
    private struct Metrics {
        let centers: [CGFloat]
        let centerY: CGFloat
    }

    private static let thumbSize = NSMakeSize(32, 20)
    private static let liftedThumbSize = NSMakeSize(46, 28)
    private static let settleDuration: Double = 0.35
    private static let commitHold: CFTimeInterval = 1
    private static let applyDelay: Double = 0.42

    private var availableRects:[NSRect] = []
    private let containerView = GeneralRowContainerView(frame: NSZeroRect)
    private let thumbView = View()
    private var nativeLens: LiquidGlassLensView?
    private var dragPosition: CGFloat?
    private var tracking = false
    private var lifted = false
    private var thumbPlaced = false
    private var committed: (value: Int32, until: CFTimeInterval)?
    private var pendingSelect: DispatchWorkItem?
    private var shownPosition: CGFloat?
    private var positionAnimator: DisplayLinkAnimator?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.addSubview(containerView)
        containerView.displayDelegate = self
        containerView.userInteractionEnabled = false
        containerView.isEventLess = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        thumbView.isEventLess = true
        thumbView.layer?.cornerRadius = SelectSizeRowView.thumbSize.height / 2
        thumbView.layer?.borderWidth = 0.5
        thumbView.layer?.masksToBounds = false
        thumbView.layer?.shadowColor = NSColor.black.cgColor
        thumbView.layer?.shadowOpacity = 0.3
        thumbView.layer?.shadowRadius = 3
        thumbView.layer?.shadowOffset = NSMakeSize(0, 1)
        thumbView.layer?.shadowPath = CGPath(roundedRect: SelectSizeRowView.thumbSize.bounds, cornerWidth: SelectSizeRowView.thumbSize.height / 2, cornerHeight: SelectSizeRowView.thumbSize.height / 2, transform: nil)
        containerView.addSubview(thumbView)
    }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        let view = super.hitTest(point)
        if let view, view !== self, view.isDescendant(of: containerView) {
            return self
        }
        return view
    }

    private var lensEnabled: Bool {
        if #available(macOS 26.0, *) {
            return System.liquidGlass && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        }
        return false
    }

    private var liftsOnPress: Bool {
        return lensEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func metrics(_ item: SelectSizeRowItem) -> Metrics? {
        guard !item.sizes.isEmpty else {
            return nil
        }
        let left: CGFloat
        let right: CGFloat
        let count: CGFloat
        switch item.viewType {
        case .legacy:
            left = item.inset.left
            right = item.inset.right
            count = CGFloat(item.sizes.count)
        case let .modern(_, insets):
            left = insets.left
            right = insets.right
            count = max(1, CGFloat(item.sizes.count) - 1)
        }
        var minWidth: CGFloat = 0
        var maxWidth: CGFloat = 0
        if item.hasMarkers {
            let minNode = TextNode.layoutText(.initialize(string: "A", color: theme.colors.text, font: .normal(min(CGFloat(item.sizes.first!), 11))), backdorColor, 1, .end, NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude), nil, false, .left)
            let maxNode = TextNode.layoutText(.initialize(string: "A", color: theme.colors.text, font: .normal(min(CGFloat(item.sizes.last!), 15))), backdorColor, 1, .end, NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude), nil, false, .left)
            minWidth = _focus(minNode.0.size).width
            maxWidth = _focus(maxNode.0.size).width
        }
        let insetBetweenFont: CGFloat = item.hasMarkers ? 20 : 0
        let width = containerView.frame.width - (left + minWidth) - (right + maxWidth) - insetBetweenFont * 2
        let minX = left + minWidth + insetBetweenFont
        let step = floorToScreenPixels(backingScaleFactor, width / count)
        return Metrics(centers: (0 ..< item.sizes.count).map { minX + step * CGFloat($0) }, centerY: _focus(SelectSizeRowView.thumbSize).midY)
    }

    private func centerX(at position: CGFloat, _ metrics: Metrics) -> CGFloat {
        let centers = metrics.centers
        let clamped = min(max(position, 0), CGFloat(centers.count - 1))
        let lower = Int(clamped.rounded(.down))
        let upper = min(lower + 1, centers.count - 1)
        return centers[lower] + (centers[upper] - centers[lower]) * (clamped - CGFloat(lower))
    }

    private func position(at x: CGFloat, _ metrics: Metrics) -> CGFloat {
        let centers = metrics.centers
        guard centers.count > 1 else {
            return 0
        }
        let step = max(1, centers[1] - centers[0])
        return min(max((x - centers[0]) / step, 0), CGFloat(centers.count - 1))
    }

    private var targetPosition: CGFloat {
        guard let item = item as? SelectSizeRowItem else {
            return 0
        }
        return dragPosition ?? CGFloat(item.sizes.firstIndex(of: item.current) ?? 0)
    }

    private var renderedPosition: CGFloat {
        return shownPosition ?? targetPosition
    }

    private func thumbRect(at position: CGFloat, _ metrics: Metrics) -> NSRect {
        let size = SelectSizeRowView.thumbSize
        let center = NSMakePoint(centerX(at: position, metrics), metrics.centerY)
        return NSMakeRect(center.x - size.width / 2, center.y - size.height / 2, size.width, size.height)
    }

    private func updateThumb(lens animation: LiquidGlassLensAnimation?) {
        guard let item = item as? SelectSizeRowItem, let metrics = metrics(item) else {
            thumbView.isHidden = true
            nativeLens?.reset()
            return
        }
        thumbView.isHidden = false
        thumbView.backgroundColor = .white
        thumbView.layer?.borderColor = theme.colors.border.cgColor
        let previous = thumbPlaced ? thumbView.frame : thumbRect(at: renderedPosition, metrics)
        let rect = thumbRect(at: renderedPosition, metrics)
        if thumbView.frame != rect {
            thumbView.layer?.removeAnimation(forKey: "position")
            thumbView.layer?.removeAnimation(forKey: "bounds")
            thumbView.frame = rect
        }
        thumbPlaced = true
        if let animation {
            updateLens(target: thumbRect(at: targetPosition, metrics), from: previous, animation: animation)
        }
    }

    private func animatePosition(from: CGFloat) {
        positionAnimator?.invalidate()
        positionAnimator = nil
        let target = targetPosition
        guard abs(from - target) > 0.001 else {
            shownPosition = nil
            return
        }
        shownPosition = from
        positionAnimator = DisplayLinkAnimator(duration: SelectSizeRowView.settleDuration, from: from, to: target, timingFunction: CAMediaTimingFunction(controlPoints: 0.5, 1.0 + 0.4 / 3.0, 1.0, 1.0), update: { [weak self] value in
            guard let self else { return }
            self.shownPosition = value
            self.containerView.needsDisplay = true
            self.updateThumb(lens: nil)
        }, completion: { [weak self] in
            guard let self else { return }
            self.positionAnimator = nil
            self.shownPosition = nil
            self.containerView.needsDisplay = true
            self.updateThumb(lens: nil)
        })
    }

    private func stopPositionAnimation() {
        positionAnimator?.invalidate()
        positionAnimator = nil
        shownPosition = nil
    }

    private func updateLens(target rest: NSRect, from: NSRect, animation: LiquidGlassLensAnimation) {
        guard lensEnabled else {
            if let nativeLens {
                nativeLens.reset()
                nativeLens.removeFromSuperview()
                self.nativeLens = nil
            }
            thumbView.layer?.opacity = 1
            return
        }
        if lifted, nativeLens == nil, let lens = LiquidGlassLensView.make() {
            lens.frame = containerView.bounds
            containerView.addSubview(lens)
            nativeLens = lens
            lens.update(lensFrame: from, interactionProgress: 0, appearance: theme.appearance, backingScale: backingScaleFactor, animation: .immediate, contentSources: [])
        }
        guard let nativeLens else {
            thumbView.layer?.opacity = 1
            return
        }
        nativeLens.frame = containerView.bounds
        let size = SelectSizeRowView.liftedThumbSize
        let frame = lifted ? NSMakeRect(rest.midX - size.width / 2, rest.midY - size.height / 2, size.width, size.height) : rest
        nativeLens.update(lensFrame: frame, interactionProgress: lifted ? 1 : 0, appearance: theme.appearance, backingScale: backingScaleFactor, animation: animation, contentSources: [])
        let opacity: Float = lifted && nativeLens.hasActiveSurface ? 0 : 1
        if thumbView.layer?.opacity != opacity {
            let previous = thumbView.layer?.presentation()?.opacity ?? thumbView.layer?.opacity ?? 1
            thumbView.layer?.opacity = opacity
            thumbView.layer?.animateAlpha(from: CGFloat(previous), to: CGFloat(opacity), duration: 0.2)
        }
    }

    private func setDragPosition(at x: CGFloat, item: SelectSizeRowItem, metrics: Metrics) {
        let position = self.position(at: x, metrics)
        dragPosition = position
        let nearest = item.sizes[Int(position.rounded())]
        if item.current != nearest {
            item.current = nearest
        }
    }

    public override func mouseDown(with event: NSEvent) {
        guard let item = item as? SelectSizeRowItem, let metrics = metrics(item), let first = metrics.centers.first, let last = metrics.centers.last else {
            super.mouseDown(with: event)
            return
        }
        let point = containerView.convert(event.locationInWindow, from: nil)
        let area = NSMakeRect(first - 20, metrics.centerY - 16, last - first + 40, 32)
        guard area.contains(point) else {
            super.mouseDown(with: event)
            return
        }
        let from = renderedPosition
        tracking = true
        committed = nil
        pendingSelect?.cancel()
        pendingSelect = nil
        lifted = liftsOnPress
        setDragPosition(at: point.x, item: item, metrics: metrics)
        animatePosition(from: from)
        containerView.needsDisplay = true
        updateThumb(lens: .spring(duration: 0.4))
    }

    public override func mouseDragged(with event: NSEvent) {
        guard tracking, let item = item as? SelectSizeRowItem, let metrics = metrics(item) else {
            super.mouseDragged(with: event)
            return
        }
        stopPositionAnimation()
        setDragPosition(at: containerView.convert(event.locationInWindow, from: nil).x, item: item, metrics: metrics)
        containerView.needsDisplay = true
        updateThumb(lens: .immediate)
    }

    public override func mouseUp(with event: NSEvent) {
        guard tracking, let item = item as? SelectSizeRowItem, !item.sizes.isEmpty else {
            super.mouseUp(with: event)
            return
        }
        let from = renderedPosition
        tracking = false
        lifted = false
        let index = min(max(Int(targetPosition.rounded()), 0), item.sizes.count - 1)
        dragPosition = nil
        item.current = item.sizes[index]
        animatePosition(from: from)
        containerView.needsDisplay = true
        updateThumb(lens: .spring(duration: 0.4))
        pendingSelect?.cancel()
        pendingSelect = nil
        if item.initialCurrent != item.current {
            committed = (item.current, CACurrentMediaTime() + SelectSizeRowView.applyDelay + SelectSizeRowView.commitHold)
            let action = item.selectAction
            let select = DispatchWorkItem { [weak self] in
                self?.pendingSelect = nil
                action(index)
            }
            pendingSelect = select
            DispatchQueue.main.asyncAfter(deadline: .now() + SelectSizeRowView.applyDelay, execute: select)
        }
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            tracking = false
            lifted = false
            dragPosition = nil
            stopPositionAnimation()
            nativeLens?.reset()
        }
    }
    
    public func _focus(_ size: NSSize) -> NSRect {
        var focus = self.containerView.focus(size)
        if let item = item as? SelectSizeRowItem {
            switch item.viewType {
            case .legacy:
                if item.titles != nil {
                    focus.origin.y += 20
                }
            case let .modern(_, insets):
                if item.titles != nil {
                    focus.origin.y += (24 - insets.bottom)
                }
            }
            
        }
        return focus
    }
    
    
    public override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        
        guard let item = item as? SelectSizeRowItem, !item.sizes.isEmpty, containerView.layer == layer else {return}
        
        switch item.viewType {
        case .legacy:
            let minFontSize = CGFloat(item.sizes.first!)
            let maxFontSize = CGFloat(item.sizes.last!)
            
            let minNode = TextNode.layoutText(.initialize(string: "A", color: theme.colors.text, font: .normal(min(minFontSize, 11))), backdorColor, 1, .end, NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude), nil, false, .left)
            
            let maxNode = TextNode.layoutText(.initialize(string: "A", color: theme.colors.text, font: .normal(min(maxFontSize, 15))), backdorColor, 1, .end, NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude), nil, false, .left)
            
            let minF = _focus(item.hasMarkers ? minNode.0.size : NSZeroSize)
            let maxF = _focus(item.hasMarkers ? maxNode.0.size : NSZeroSize)
            
            if item.hasMarkers {
                minNode.1.draw(NSMakeRect(item.inset.left, minF.minY, minF.width, minF.height), in: ctx, backingScaleFactor: backingScaleFactor, backgroundColor: backgroundColor)
                maxNode.1.draw(NSMakeRect(containerView.frame.width - item.inset.right - maxF.width, maxF.minY, maxF.width, maxF.height), in: ctx, backingScaleFactor: backingScaleFactor, backgroundColor: backgroundColor)
            }
            
            let count = CGFloat(item.sizes.count)
            
            let insetBetweenFont: CGFloat = item.hasMarkers ? 20 : 0
            
            let width: CGFloat = containerView.frame.width - (item.inset.left + minF.width) - (item.inset.right + maxF.width) - insetBetweenFont * 2
            
            let per = floorToScreenPixels(backingScaleFactor, width / (count))
            
            ctx.setFillColor(theme.colors.accent.cgColor)
            let lineSize = NSMakeSize(width, 2)
            let lc = _focus(lineSize)
            let minX = item.inset.left + minF.width + insetBetweenFont
            
            let interactionRect = NSMakeRect(minX, lc.minY, lc.width, lc.height)
            
            ctx.fill(interactionRect)
            
            let current: CGFloat = renderedPosition
            
            let selectSize = NSMakeSize(20, 20)
            
            let selectPoint = NSMakePoint(minX + floorToScreenPixels(backingScaleFactor, interactionRect.width / CGFloat(count)) * current - selectSize.width / 2, _focus(selectSize).minY)
            
            ctx.setFillColor(theme.colors.grayText.cgColor)
            let unMinX = selectPoint.x + selectSize.width / 2
            ctx.fill(NSMakeRect(unMinX, lc.minY, lc.maxX - unMinX, lc.height))
            
            
            for i in 0 ..< item.sizes.count {
                let perSize = NSMakeSize(10, 10)
                let perF = _focus(perSize)
                let point = NSMakePoint(minX + per * CGFloat(i) - (i > 0 ? perSize.width / 2 : 0), perF.minY)
                ctx.setFillColor(theme.colors.background.cgColor)
                ctx.fill(NSMakeRect(point.x, point.y, perSize.width, perSize.height))
                
                ctx.setFillColor(CGFloat(i) <= current + 0.001 ? theme.colors.accent.cgColor : theme.colors.grayText.cgColor)
                ctx.fillEllipse(in: NSMakeRect(point.x + perSize.width/2 - 2, point.y + 3, 4, 4))
                
                if let titles = item.titles, titles.count == item.sizes.count {
                    let title = titles[i]
                    let titleNode = TextNode.layoutText(.initialize(string: title, color: theme.colors.text, font: .normal(.short)), backdorColor, 1, .end, NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude), nil, false, .left)
                    let titleRect = NSMakeRect(min(max(point.x - titleNode.0.size.width / 2 + 3, minX), frame.width - titleNode.0.size.width - minX), point.y - 15 - titleNode.0.size.height, titleNode.0.size.width, titleNode.0.size.height)
                    
                    if let image = item.titlesImages?[i] {
                        ctx.draw(image, in: CGRect(origin: NSMakePoint(titleRect.minX - image.backingSize.width, titleRect.minY), size: image.backingSize))
                    }
                    
                    titleNode.1.draw(titleRect, in: ctx, backingScaleFactor: backingScaleFactor, backgroundColor: backgroundColor)
                }
            }
            
            if let titles = item.titles, titles.count == 1, let title = titles.first {
                let perSize = NSMakeSize(10, 10)
                let perF = _focus(perSize)
                let titleNode = TextNode.layoutText(.initialize(string: title, color: theme.colors.text, font: .normal(.short)), backdorColor, 1, .end, NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude), nil, false, .left)
                
                titleNode.1.draw(NSMakeRect(_focus(titleNode.0.size).minX, perF.minY - 15 - titleNode.0.size.height, titleNode.0.size.width, titleNode.0.size.height), in: ctx, backingScaleFactor: backingScaleFactor, backgroundColor: backgroundColor)
            }
            
            
            resetCursorRects()
            availableRects.removeAll()
            
            for i in 0 ..< item.sizes.count {
                let perF = _focus(selectSize)
                let point = NSMakePoint(interactionRect.minX + floorToScreenPixels(backingScaleFactor, interactionRect.width / (count)) * CGFloat(i) - selectSize.width / 2, perF.minY)
                let rect = NSMakeRect(point.x, point.y, selectSize.width, selectSize.height)
                addCursorRect(rect, cursor: NSCursor.pointingHand)
                availableRects.append(rect)
            }
        case let .modern(_, insets):
            let minFontSize = CGFloat(item.sizes.first!)
            let maxFontSize = CGFloat(item.sizes.last!)
            
            let minNode = TextNode.layoutText(.initialize(string: "A", color: theme.colors.text, font: .normal(min(minFontSize, 11))), backdorColor, 1, .end, NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude), nil, false, .left)
            
            let maxNode = TextNode.layoutText(.initialize(string: "A", color: theme.colors.text, font: .normal(min(maxFontSize, 15))), backdorColor, 1, .end, NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude), nil, false, .left)
            
            let minF = _focus(item.hasMarkers ? minNode.0.size : NSZeroSize)
            let maxF = _focus(item.hasMarkers ? maxNode.0.size : NSZeroSize)
            
            if item.hasMarkers {
                minNode.1.draw(NSMakeRect(insets.left, minF.minY, minF.width, minF.height), in: ctx, backingScaleFactor: backingScaleFactor, backgroundColor: backgroundColor)
                maxNode.1.draw(NSMakeRect(containerView.frame.width - insets.right - maxF.width, maxF.minY, maxF.width, maxF.height), in: ctx, backingScaleFactor: backingScaleFactor, backgroundColor: backgroundColor)
            }
            
            let count = max(1, CGFloat(item.sizes.count) - 1)
            
            let insetBetweenFont: CGFloat = item.hasMarkers ? 20 : 0
            
            let width: CGFloat = containerView.frame.width - (insets.left + minF.width) - (insets.right + maxF.width) - insetBetweenFont * 2
            
            let per = floorToScreenPixels(backingScaleFactor, width / (count))
            
            ctx.setFillColor(theme.colors.accent.cgColor)
            let lineSize = NSMakeSize(width, 2)
            let lc = _focus(lineSize)
            let minX = insets.left + minF.width + insetBetweenFont
            
            let interactionRect = NSMakeRect(minX, lc.minY, lc.width, lc.height)
            
            ctx.fill(interactionRect)
            
            let current: CGFloat = renderedPosition
            
            let selectSize = NSMakeSize(20, 20)
            
            let selectPoint = NSMakePoint(minX + floorToScreenPixels(backingScaleFactor, interactionRect.width / CGFloat(count)) * current - selectSize.width / 2, _focus(selectSize).minY)
            
            ctx.setFillColor(theme.colors.grayText.cgColor)
            let unMinX = selectPoint.x + selectSize.width / 2



            ctx.fill(NSMakeRect(unMinX, lc.minY, lc.maxX - unMinX, lc.height))

            
            for i in 0 ..< item.sizes.count {
                let perSize = NSMakeSize(10, 10)
                let perF = _focus(perSize)
                let point = NSMakePoint(minX + per * CGFloat(i) - (i > 0 ? perSize.width / 2 : 0), perF.minY)
                ctx.setFillColor(theme.colors.background.cgColor)
                ctx.fill(NSMakeRect(point.x, point.y, perSize.width, perSize.height))
                
                ctx.setFillColor(CGFloat(i) <= current + 0.001 ? theme.colors.accent.cgColor : theme.colors.grayText.cgColor)
                ctx.fillEllipse(in: NSMakeRect(point.x + perSize.width/2 - 2, point.y + 3, 4, 4))


                if item.dottedIndexes.contains(i), i > 0 {
                    let prevPoint = NSMakePoint(minX + per * CGFloat(i - 1) + (i == 1 ? perSize.width : perSize.width / 2), lc.minY)
                    let rect = NSMakeRect(prevPoint.x, lc.minY, point.x - prevPoint.x, lc.height)
                    ctx.clear(rect)
                    let w: CGFloat = 16


                    let count = Int(floor(rect.width / w))
                    let total = CGFloat(count) * w

                    let inset: CGFloat = ceil((rect.width - total) / 2)

                    for j in 0 ..< count {
                        let rect = NSMakeRect(rect.minX + CGFloat(j) * w, rect.minY, w, rect.height)
                        ctx.saveGState()
                        ctx.setFillColor(CGFloat(i) <= current + 0.001 ? theme.colors.accent.cgColor : theme.colors.grayText.cgColor)
                        ctx.fill(NSMakeRect(rect.minX + inset + 2, rect.minY, w - 4, rect.height))
                        ctx.restoreGState()
                    }
                }

                if let titles = item.titles, titles.count == item.sizes.count, titles.count > 1 {
                    let title = titles[i]
                    let titleNode = TextNode.layoutText(.initialize(string: title, color: theme.colors.grayText, font: .normal(.short)), backdorColor, 1, .end, NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude), nil, false, .left)

                    var rect = NSMakeRect(min(max(point.x - titleNode.0.size.width / 2 + 4, minX), frame.width - titleNode.0.size.width - minX), point.y - 15 - titleNode.0.size.height, titleNode.0.size.width, titleNode.0.size.height)

                    if i == titles.count - 1 {
                        rect.origin.x = min(rect.minX, (point.x + 5) - titleNode.0.size.width)
                    }
                    
                    if let image = item.titlesImages?[i] {
                        ctx.draw(image, in: CGRect(origin: NSMakePoint(rect.minX - image.backingSize.width + 4, rect.minY), size: image.backingSize))
                        rect.origin.x += 6
                    }
                    

                    titleNode.1.draw(rect, in: ctx, backingScaleFactor: backingScaleFactor, backgroundColor: backgroundColor)
                }
            }

            if let titles = item.titles, titles.count == 1, let title = titles.first {
                let titleNode = TextNode.layoutText(.initialize(string: title, color: theme.colors.grayText, font: .normal(.short)), backdorColor, 1, .end, NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude), nil, false, .left)
                titleNode.1.draw(NSMakeRect(_focus(titleNode.0.size).minX, insets.top , titleNode.0.size.width, titleNode.0.size.height), in: ctx, backingScaleFactor: backingScaleFactor, backgroundColor: backgroundColor)
            }


            resetCursorRects()
            availableRects.removeAll()
            
            for i in 0 ..< item.sizes.count {
                let perF = _focus(selectSize)
                let point = NSMakePoint(interactionRect.minX + floorToScreenPixels(backingScaleFactor, interactionRect.width / (count)) * CGFloat(i) - selectSize.width / 2, perF.minY)
                let rect = NSMakeRect(point.x, point.y, selectSize.width, selectSize.height)
                addCursorRect(rect, cursor: NSCursor.pointingHand)
                availableRects.append(rect)
            }
        }
        
        layout()
        
    }
    
    public override var backdorColor: NSColor {
        return theme.colors.background
    }
    
    public override func layout() {
        super.layout()
        guard let item = item as? SelectSizeRowItem else {
            return
        }
        switch item.viewType {
        case .legacy:
            self.containerView.frame = bounds
        case let .modern(position, _):
            self.containerView.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - item.blockWidth) / 2), item.inset.top, item.blockWidth, frame.height - item.inset.bottom - item.inset.top)
            self.containerView.setCorners(position.corners)
        }
        updateThumb(lens: .immediate)
    }
    
    
    public override var firstResponder: NSResponder? {
        return self
    }
    
    public override func updateColors() {
        guard let item = item as? SelectSizeRowItem else {
            return
        }
        containerView.backgroundColor = backdorColor
        self.backgroundColor = item.viewType.rowBackground
        
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? SelectSizeRowItem else {
            return
        }
        switch item.viewType {
        case .legacy:
            self.containerView.setCorners([])
        case let .modern(position, _):
            self.containerView.setCorners(position.corners)
        }
        
        if !tracking {
            dragPosition = nil
            lifted = false
        }
        if let committed {
            if item.current == committed.value || CACurrentMediaTime() > committed.until || !item.sizes.contains(committed.value) {
                self.committed = nil
            } else {
                item.current = committed.value
            }
        }
        needsLayout = true
        containerView.needsDisplay = true
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}





