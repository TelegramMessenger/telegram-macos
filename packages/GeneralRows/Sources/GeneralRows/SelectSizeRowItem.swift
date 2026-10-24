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
    
    private var availableRects:[NSRect] = []
    private let containerView = GeneralRowContainerView(frame: NSZeroRect)
    private var knobPosition: CGFloat?
    private var knobAnimator: DisplayLinkAnimator?
    private var trackMinX: CGFloat = 0
    private var trackStep: CGFloat = 0
    private var isTracking: Bool = false
    private var isDragging: Bool = false
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.addSubview(containerView)
        containerView.displayDelegate = self
        containerView.userInteractionEnabled = false
        containerView.isEventLess = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }
    
    
    
    
    private var currentIndex: Int {
        guard let item = item as? SelectSizeRowItem else {
            return 0
        }
        return item.sizes.firstIndex(of: item.current) ?? 0
    }
    
    private var effectivePosition: CGFloat {
        return knobPosition ?? CGFloat(currentIndex)
    }
    
    private func position(for event: NSEvent) -> CGFloat? {
        guard let item = item as? SelectSizeRowItem, item.sizes.count > 1, trackStep > 0 else {
            return nil
        }
        let point = containerView.convert(event.locationInWindow, from: nil)
        let value = (point.x - trackMinX) / trackStep
        return min(max(0, value), CGFloat(item.sizes.count - 1))
    }
    
    private func isInsideTrack(_ event: NSEvent) -> Bool {
        guard let item = item as? SelectSizeRowItem, item.sizes.count > 1, trackStep > 0 else {
            return false
        }
        let point = containerView.convert(event.locationInWindow, from: nil)
        let maxX = trackMinX + trackStep * CGFloat(item.sizes.count - 1)
        return point.x >= trackMinX - 15 && point.x <= maxX + 15 && point.y >= 0 && point.y <= containerView.frame.height
    }
    
    private func moveKnob(to position: CGFloat) {
        knobAnimator?.invalidate()
        knobAnimator = nil
        knobPosition = position
        containerView.needsDisplay = true
    }
    
    private func animateKnob(to index: Int) {
        guard let item = item as? SelectSizeRowItem, !item.sizes.isEmpty else {
            return
        }
        let index = min(max(0, index), item.sizes.count - 1)
        let from = effectivePosition
        let changed = index != currentIndex
        knobPosition = from
        item.current = item.sizes[index]
        
        let completion: () -> Void = { [weak self, weak item] in
            guard let self else {
                return
            }
            self.knobAnimator = nil
            self.knobPosition = nil
            self.containerView.needsDisplay = true
            if changed {
                item?.selectAction(index)
            }
        }
        
        knobAnimator?.invalidate()
        knobAnimator = nil
        if abs(from - CGFloat(index)) < 0.001 {
            completion()
        } else {
            knobAnimator = DisplayLinkAnimator(duration: 0.2, from: from, to: CGFloat(index), update: { [weak self] value in
                self?.knobPosition = value
                self?.containerView.needsDisplay = true
            }, completion: completion)
        }
    }
    
    public override func mouseDown(with event: NSEvent) {
        guard isInsideTrack(event) else {
            super.mouseDown(with: event)
            return
        }
        isTracking = true
        isDragging = false
    }
    
    public override func mouseDragged(with event: NSEvent) {
        guard isTracking, let position = position(for: event) else {
            super.mouseDragged(with: event)
            return
        }
        isDragging = true
        moveKnob(to: position)
    }
    
    public override func mouseUp(with event: NSEvent) {
        guard isTracking, let position = position(for: event) else {
            super.mouseUp(with: event)
            return
        }
        if isDragging {
            animateKnob(to: Int(effectivePosition.rounded()))
        } else {
            animateKnob(to: Int(position.rounded()))
        }
        isTracking = false
        isDragging = false
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
            
            let current: CGFloat = effectivePosition
            
            let selectSize = NSMakeSize(20, 20)
            
            trackMinX = minX
            trackStep = floorToScreenPixels(backingScaleFactor, interactionRect.width / CGFloat(count))
            
            let selectPoint = NSMakePoint(minX + trackStep * current - selectSize.width / 2, _focus(selectSize).minY)
            
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
            
            
            ctx.setFillColor(theme.colors.border.cgColor)
            ctx.fillEllipse(in: NSMakeRect(selectPoint.x, selectPoint.y, selectSize.width, selectSize.height))
            
            ctx.setFillColor(.white)
            ctx.fillEllipse(in: NSMakeRect(selectPoint.x + 1, selectPoint.y + 1, selectSize.width - 2, selectSize.height - 2))
            
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
            
            let current: CGFloat = effectivePosition
            
            let selectSize = NSMakeSize(20, 20)
            
            trackMinX = minX
            trackStep = floorToScreenPixels(backingScaleFactor, interactionRect.width / CGFloat(count))
            
            let selectPoint = NSMakePoint(minX + trackStep * current - selectSize.width / 2, _focus(selectSize).minY)
            
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


            ctx.setFillColor(theme.colors.border.cgColor)
            ctx.fillEllipse(in: NSMakeRect(selectPoint.x, selectPoint.y, selectSize.width, selectSize.height))

            ctx.setFillColor(theme.colors.background.cgColor)
            ctx.fillEllipse(in: NSMakeRect(selectPoint.x + 1, selectPoint.y + 1, selectSize.width - 2, selectSize.height - 2))

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
        
        needsLayout = true
        containerView.needsDisplay = true
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}





