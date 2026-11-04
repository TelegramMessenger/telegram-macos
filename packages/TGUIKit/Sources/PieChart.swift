import Foundation
import AppKit
import ColorPalette


struct PieChartParticle {
    var trackIndex: Int
    var position: CGPoint
    var scale: CGFloat
    var alpha: CGFloat
    var direction: CGPoint
    var velocity: CGFloat
    
    init(
        trackIndex: Int,
        position: CGPoint,
        scale: CGFloat,
        alpha: CGFloat,
        direction: CGPoint,
        velocity: CGFloat
    ) {
        self.trackIndex = trackIndex
        self.position = position
        self.scale = scale
        self.alpha = alpha
        self.direction = direction
        self.velocity = velocity
    }
    
    mutating func update(deltaTime: CGFloat) {
        var position = self.position
        position.x += self.direction.x * self.velocity * deltaTime
        position.y += self.direction.y * self.velocity * deltaTime
        self.position = position
    }
}

final class PieChartParticleSet {
    private(set) var particles: [PieChartParticle] = []
    
    init() {
        self.generateParticles(preAdvance: true)
    }
    
    private func generateParticles(preAdvance: Bool) {
        let maxDirections = 24
        
        if self.particles.count < maxDirections {
            var allTrackIndices: [Int] = Array(repeating: 0, count: maxDirections)
            for i in 0 ..< maxDirections {
                allTrackIndices[i] = i
            }
            var takenIndexCount = 0
            for particle in self.particles {
                allTrackIndices[particle.trackIndex] = -1
                takenIndexCount += 1
            }
            var availableTrackIndices: [Int] = []
            availableTrackIndices.reserveCapacity(maxDirections - takenIndexCount)
            for index in allTrackIndices {
                if index != -1 {
                    availableTrackIndices.append(index)
                }
            }
            
            if !availableTrackIndices.isEmpty {
                availableTrackIndices.shuffle()
                
                for takeIndex in availableTrackIndices {
                    let directionIndex = takeIndex
                    let angle = (CGFloat(directionIndex % maxDirections) / CGFloat(maxDirections)) * CGFloat.pi * 2.0
                    
                    let direction = CGPoint(x: cos(angle), y: sin(angle))
                    let velocity = CGFloat.random(in: 20.0 ..< 40.0)
                    let alpha = CGFloat.random(in: 0.1 ..< 0.4)
                    let scale = CGFloat.random(in: 0.5 ... 1.0) * 0.22
                    
                    var position = CGPoint(x: 100.0, y: 100.0)
                    var initialOffset: CGFloat = 0.4
                    if preAdvance {
                        initialOffset = CGFloat.random(in: initialOffset ... 1.0)
                    }
                    position.x += direction.x * initialOffset * 105.0
                    position.y += direction.y * initialOffset * 105.0
                    
                    let particle = PieChartParticle(
                        trackIndex: directionIndex,
                        position: position,
                        scale: scale,
                        alpha: alpha,
                        direction: direction,
                        velocity: velocity
                    )
                    self.particles.append(particle)
                }
            }
        }
    }
    
    func update(deltaTime: CGFloat) {
        let size = CGSize(width: 200.0, height: 200.0)
        let radius2 = pow(size.width * 0.5 + 10.0, 2.0)
        for i in (0 ..< self.particles.count).reversed() {
            self.particles[i].update(deltaTime: deltaTime)
            let position = self.particles[i].position
            
            if pow(position.x - size.width * 0.5, 2.0) + pow(position.y - size.height * 0.5, 2.0) > radius2 {
                self.particles.remove(at: i)
            }
        }
        
        self.generateParticles(preAdvance: false)
    }
}


public func optimizeArray(array: [Int], minPercent: Double) -> [Int] {
    let total = array.reduce(0, +)

    let minValue = Int(Double(total) * minPercent)

    var array = array
    var totalDiff = 0
    
    for i in 0 ..< array.count {
        if array[i] < minValue && array[i] > 0 {
            let diff = minValue - array[i]
            array[i] += diff
            totalDiff += diff
        }
    }

    let minus = totalDiff / array.count
    for i in 0 ..< array.count {
        if array[i] > 0 {
            array[i] -= minus
        }
    }
    
    return array
}





private class TooltipView : View {
    private let textView = TextView()
    private let visual = VisualEffect()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        addSubview(visual)
        addSubview(textView)
        
        
        textView.userInteractionEnabled = false
        textView.isSelectable = false
                
        layer?.cornerRadius = 10
        
    }
    
    func update(attr: NSAttributedString, animated: Bool) -> NSSize {
        let layout = TextViewLayout(attr)
        layout.measure(width: .greatestFiniteMagnitude)
        textView.update(layout)
        visual.bgColor = presentation.colors.background.withMultipliedAlpha(0.8)
        return NSMakeSize(layout.layoutSize.width + 16, layout.layoutSize.height + 10)
    }
    
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) -> Void {
        transition.updateFrame(view: textView, frame: textView.centerFrame())
        transition.updateFrame(view: visual, frame: size.bounds.insetBy(dx: -10, dy: -5))
    }
    
    override func layout() {
        super.layout()
        updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


private final class SectionLayer: SimpleLayer {
    private let maskLayer: SimpleShapeLayer
    private let gradientLayer: SimpleGradientLayer
    private let strokeLayer = SimpleShapeLayer()
    private let labelLayer = SimpleLayer()
    private var labelCache: (text: String, fontSize: CGFloat, color: NSColor, scale: CGFloat)?
    private var particleImage: CGImage?
    private var particleLayers: [SimpleLayer] = []

    override init() {
        self.maskLayer = SimpleShapeLayer()
        self.maskLayer.fillColor = NSColor.white.cgColor
        
        self.gradientLayer = SimpleGradientLayer()
        self.gradientLayer.type = .radial
        self.gradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.gradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
                
        super.init()
        
        self.mask = self.maskLayer
        self.addSublayer(self.gradientLayer)
        self.strokeLayer.fillColor = nil
        self.strokeLayer.lineCap = .round
        self.addSublayer(self.strokeLayer)
        self.addSublayer(self.labelLayer)
    }

    override init(layer: Any) {
        self.maskLayer = SimpleShapeLayer()
        self.gradientLayer = SimpleGradientLayer()
        super.init(layer: layer)
    }
    
    
    required init(coder: NSCoder) {
        preconditionFailure()
    }
    
    func isPointOnGraph(point: CGPoint) -> Bool {
        if let path = self.maskLayer.path {
            return path.contains(point)
        }
        return false
    }
    
    func update(item: PieChartView.Item, size: CGSize, path: CGPath, strokePath: CGPath, presentation: PieChartView.Presentation) {
        self.maskLayer.frame = CGRect(origin: CGPoint(), size: size)
        self.gradientLayer.frame = CGRect(origin: CGPoint(), size: size)
        self.strokeLayer.frame = CGRect(origin: .zero, size: size)
        self.strokeLayer.path = strokePath
        self.strokeLayer.strokeColor = presentation.strokeColor.cgColor
        self.strokeLayer.lineWidth = presentation.strokeSize
        if self.particleImage !== item.particle {
            self.particleImage = item.particle
            for layer in self.particleLayers {
                layer.contents = item.particle
                layer.bounds = CGRect(origin: .zero, size: item.particle?.backingSize ?? .zero)
            }
        }
        
        let color = item.color.usingColorSpace(.deviceRGB) ?? item.color
        let normalColor = color.cgColor
        let darkerColor = color.withMultipliedBrightnessBy(0.96).cgColor
        let colors: [CGColor] = [
            darkerColor,
            normalColor,
            normalColor,
            normalColor,
            darkerColor
        ]
        self.gradientLayer.colors = colors
        
        let locations: [CGFloat] = [
            0.0,
            0.3,
            0.5,
            0.7,
            1.0
        ]
        self.gradientLayer.locations = locations.map { location in
            let location = location * 0.5 + 0.5
            return location as NSNumber
        }
        
        self.maskLayer.path = path
    }

    func updateLabel(text: String?, fontSize: CGFloat, color: NSColor, center: CGPoint) {
        guard let text else {
            self.labelLayer.isHidden = true
            return
        }
        self.labelLayer.isHidden = false
        if labelCache?.text != text || labelCache?.fontSize != fontSize || labelCache?.color != color || labelCache?.scale != System.backingScale {
            let attributedString = NSAttributedString(string: text, attributes: [.foregroundColor: color, .font: NSFont.avatar(fontSize)])
            let node = TextLabelNode.layoutText(attributedString, CGSize(width: 200, height: 200))
            self.labelLayer.bounds = CGRect(origin: .zero, size: node.0.size)
            self.labelLayer.contents = generateImage(node.0.size, rotatedContext: { size, context in
                context.clear(CGRect(origin: .zero, size: size))
                node.1.draw(CGRect(origin: .zero, size: size), in: context, backingScaleFactor: System.backingScale)
            })
            self.labelCache = (text, fontSize, color, System.backingScale)
        }
        self.labelLayer.position = center
    }

    func updateParticles(particleSet: PieChartParticleSet) {
        guard let particleImage = self.particleImage else {
            for layer in self.particleLayers {
                layer.isHidden = true
            }
            return
        }
        for i in 0 ..< particleSet.particles.count {
            let particle = particleSet.particles[i]
            
            let particleLayer: SimpleLayer
            if i < self.particleLayers.count {
                particleLayer = self.particleLayers[i]
                particleLayer.isHidden = false
            } else {
                particleLayer = SimpleLayer()
                particleLayer.contents = particleImage
                particleLayer.bounds = CGRect(origin: CGPoint(), size: particleImage.backingSize)
                self.particleLayers.append(particleLayer)
                self.insertSublayer(particleLayer, above: self.gradientLayer)
            }
            
            particleLayer.position = particle.position
            particleLayer.transform = CATransform3DMakeScale(particle.scale, particle.scale, 1.0)
            particleLayer.opacity = Float(particle.alpha)
        }
        if particleSet.particles.count < self.particleLayers.count {
            for i in particleSet.particles.count ..< self.particleLayers.count {
                self.particleLayers[i].isHidden = true
            }
        }
    }
}


public class PieChartView : Control {
    
    
    
    public struct Item : Comparable, Identifiable {
        public var id: AnyHashable
        public var index: Int
        public var count: Int
        public var color: NSColor
        public var badge: NSAttributedString?
        public var particle: CGImage?
        public init(id: AnyHashable, index: Int, count: Int, color: NSColor, badge: NSAttributedString?, particle: CGImage?) {
            self.id = id
            self.index = index
            self.count = count
            self.color = color
            self.badge = badge
            self.particle = particle
        }
        public var stableId: AnyHashable {
            return id
        }
        public static func <(lhs: Item, rhs: Item) -> Bool {
            return lhs.index < rhs.index
        }
    }
    
    public struct Presentation {
        public var strokeColor: NSColor
        public var strokeSize: CGFloat
        public var bgColor: NSColor
        public var totalTextColor: NSColor
        public var itemTextColor: NSColor
        public init(strokeColor: NSColor, strokeSize: CGFloat, bgColor: NSColor, totalTextColor: NSColor, itemTextColor: NSColor) {
            self.strokeColor = strokeColor
            self.strokeSize = strokeSize
            self.bgColor = bgColor
            self.totalTextColor = totalTextColor
            self.itemTextColor = itemTextColor
        }
    }
    
    public private(set) var items: [Item] = []
    public var presentation: Presentation {
        didSet {
            updateChartLayers()
        }
    }
    private let totalTextView = DynamicCounterTextView()
    private var tooltipView: TooltipView?
    
    
    public var toggleSelected:((Item)->Void)? = nil
    
    
    private var displayAnimator: ConstantDisplayLinkAnimator?
    private let chartLayer = SimpleLayer()
    private var sectionLayers: [AnyHashable: SectionLayer] = [:]
    private let contentObserver = AnimatableContentObserver()
    private var motionObserver: NSObjectProtocol?
    static var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    
    private struct AnimationValues {
        struct Value {
            let value: Int
            let timestamp: CGFloat
        }
        var values:[AnyHashable : Value] = [:]
        var selection:[AnyHashable : CGFloat] = [:]
        var radius:[AnyHashable : CGFloat] = [:]
        var selected: AnyHashable? = nil
        
    }
    
    private var animationValues: AnimationValues = .init() {
        didSet {
            updateChartLayers()
            updateAnimator()
        }
    }
    private let particleSet = PieChartParticleSet()

    
    public init(frame frameRect: NSRect, presentation: Presentation) {
        self.presentation = presentation
        super.init(frame: frameRect)
        self.layer?.isOpaque = false
        self.layer?.backgroundColor = NSColor.clear.cgColor
        self.layer?.insertSublayer(chartLayer, at: 0)
        addSubview(totalTextView)
        postsFrameChangedNotifications = true
        postsBoundsChangedNotifications = true
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main, using: { [weak self] _ in
            self?.updateAnimator()
        })
        
        set(handler: { [weak self] control in
            self?.invokeToggle()
        }, for: .Click)
    }

    private var hasChartAnimation: Bool {
        if !animationValues.values.isEmpty {
            return true
        }
        for item in items {
            let selectionTarget: CGFloat = animationValues.selected == item.id ? 1 : 0
            if (animationValues.selection[item.id] ?? 0) != selectionTarget {
                return true
            }
            let radiusTarget: CGFloat = !animationValues.selection.isEmpty && animationValues.selection[item.id] == nil ? 1 : 0
            if (animationValues.radius[item.id] ?? 0) != radiusTarget {
                return true
            }
        }
        return false
    }

    private var isVisibleForAnimation: Bool {
        return window?.isVisible == true && WindowKeyObserver.isKey(window) && !isHiddenOrHasHiddenAncestor && !visibleRect.isEmpty
    }

    var isAnimatingParticles: Bool {
        return isVisibleForAnimation && !Self.reduceMotion() && items.contains(where: { $0.count > 0 && $0.particle != nil })
    }

    private func updateAnimator() {
        let isAnimating = isVisibleForAnimation && (hasChartAnimation || isAnimatingParticles)
        if isAnimating && displayAnimator == nil {
            displayAnimator = ConstantDisplayLinkAnimator(framesPerSecond: .max, update: { [weak self] duration in
                guard let self else {
                    return
                }
                if self.isAnimatingParticles {
                    self.particleSet.update(deltaTime: duration)
                    for layer in self.sectionLayers.values {
                        layer.updateParticles(particleSet: self.particleSet)
                    }
                }
                if self.hasChartAnimation {
                    self.runAnimatorUpdater(duration)
                }
            })
        }
        displayAnimator?.isPaused = !isAnimating
    }

    @objc private func updateAnimationVisibility() {
        contentObserver.update(for: self, target: self, selector: #selector(updateAnimationVisibility), options: [.contentBounds, .documentFrame, .ownFrame, .ownBounds])
        updateAnimator()
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAnimationVisibility()
    }

    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateAnimationVisibility()
    }

    public override func viewDidHide() {
        super.viewDidHide()
        updateAnimator()
    }

    public override func viewDidUnhide() {
        super.viewDidUnhide()
        updateAnimator()
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateChartLayers()
    }

    deinit {
        displayAnimator?.invalidate()
        if let motionObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(motionObserver)
        }
    }
    
    private func invokeToggle() {
        guard let window = self.window else {
            return
        }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        if let index = self.selectedItemIndex(at: point) {
            self.toggleSelected?(self.items[index])
        }
        if let view = tooltipView {
            performSubviewRemoval(view, animated: true)
            self.tooltipView = nil
        }
    }
        
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required public init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    
    public func update(items: [Item], dynamicText: String, animated: Bool) {
        
        
        let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: self.items, rightList: items)

        
        let prevItems = self.items
        
        for idx in deleteIndices.reversed() {
            self.items.remove(at: idx)
        }
        var updated = self.animationValues.values
        
        for indicesAndItem in indicesAndItems {
            let item = indicesAndItem.1
            self.items.insert(item, at: indicesAndItem.0)
            if animated {
                updated[item.stableId] = .init(value: 0, timestamp: 0)
            }
        }
        
    
        
        for updateIndex in updateIndices {
            let item = updateIndex.1
            let prev: Item = prevItems[updateIndex.2]
            self.items[updateIndex.0] = item
            if updated[item.stableId] == nil, animated {
                updated[item.stableId] = .init(value: prev.count, timestamp: 0)
            } else if let value = updated[item.stableId] {
                updated[item.stableId] = .init(value: value.value, timestamp: 0)
            }
        }
        
        if prevItems.isEmpty && !Self.reduceMotion() {
            for item in self.items {
                updated[item.stableId] = .init(value: items.reduce(0, { $0 + $1.count }) / items.count, timestamp: 0)
            }
        }
        
        let validIds = Set(self.items.map { $0.id })
        self.animationValues = .init(values: updated.filter { validIds.contains($0.key) }, selection: self.animationValues.selection.filter { validIds.contains($0.key) }, radius: self.animationValues.radius.filter { validIds.contains($0.key) }, selected: self.animationValues.selected.flatMap { validIds.contains($0) ? $0 : nil })

        
        var dynamicFontSize: CGFloat = 15
        var value: DynamicCounterTextView.Value = DynamicCounterTextView.make(for: dynamicText, count: dynamicText, font: .avatar(dynamicFontSize), textColor: presentation.totalTextColor, width: .greatestFiniteMagnitude)
        
        let innerDiameter = min(bounds.width, bounds.height) / 2.5

        while value.size.width > innerDiameter && dynamicFontSize > 1 {
            dynamicFontSize -= 1
            value = DynamicCounterTextView.make(for: dynamicText, count: dynamicText, font: .avatar(dynamicFontSize), textColor: presentation.totalTextColor, width: dynamicFontSize < 6 ? innerDiameter - 4 : .greatestFiniteMagnitude)
        }
        
        totalTextView.update(value, animated: animated)
        totalTextView.change(size: value.size, animated: animated)
        totalTextView.change(pos: focus(value.size).origin, animated: animated)
        
        self.runAnimatorUpdater(1.0 / 60.0)
        self.updateAnimator()
        
        needsLayout = true
        self.updateChartLayers()
    }
    
    private var countUpElapsed: CGFloat = 0
    
    private func runAnimatorUpdater(_ duration: CGFloat) {
        var updated = self.animationValues.values
        self.countUpElapsed += duration
        let countUpStep = self.countUpElapsed >= 1.0 / 60.0 * 0.95
        if countUpStep {
            self.countUpElapsed = 0
        }
        let step = 0.016 * 8 * FrameStep.scale(duration)
        for (key, value) in self.animationValues.values where countUpStep {
            let item = self.items.first(where: { $0.id == key })
            if let item = item {
                let d = CGFloat(item.count - value.value)
                let timestamp = value.timestamp + 0.016 / 3
                let curve = listViewAnimationCurveEaseInOut(timestamp)
                let result = d * curve
                let current: Int
                if result < 0 {
                    current = Int(floor(result))
                } else {
                    current = Int(ceil(result))
                }
                let updatedValue = value.value + current
                updated[key] = .init(value: updatedValue, timestamp: timestamp)
                
                if abs(current) == 0 {
                    updated.removeValue(forKey: key)
                }
            }
        }
        
        var selection = self.animationValues.selection
        if let selected = self.animationValues.selected {
            let current = selection[selected] ?? 0
            selection[selected] = min(current + step, 1)
        }
        for (key, value) in self.animationValues.selection {
            if key != self.animationValues.selected {
                let updatedValue = max(0, value - step)
                if updatedValue > 0 {
                    selection[key] = updatedValue
                } else {
                    selection.removeValue(forKey: key)
                }
            }
        }
        
        var radius = self.animationValues.radius
        for item in items {
            let current = radius[item.id] ?? 0
            let value: CGFloat
            if !selection.isEmpty && selection[item.id] == nil {
                value = min(current + step, 1)
            } else {
                value = max(current - step, 0)
            }
            radius[item.id] = value
            if value == 0 {
                radius.removeValue(forKey: item.id)
            }
        }
        
        
        self.animationValues = .init(values: updated, selection: selection, radius: radius, selected: self.animationValues.selected)
        
        
    }
    
    public override func layout() {
        super.layout()
        totalTextView.center()
        updateChartLayers()
        updateAnimator()
    }
    
    func selectedItemIndex(at point: CGPoint) -> Int? {
        
        
        
        let lastRenderedChartFrame = self.bounds
        let center = CGPoint(x: lastRenderedChartFrame.midX, y: lastRenderedChartFrame.midY)

        let radius = min(bounds.width, bounds.height) / 2 - presentation.strokeSize - 8

        let innerRadius = min(bounds.width, bounds.height) / 2.5 / 2
        
        if center.distance(p2: point) > radius || center.distance(p2: point) < innerRadius { return nil }
        let angle = (center - point).angle + .pi
        let total: CGFloat = items.map({ CGFloat($0.count) }).reduce(0, +)
        var startAngle: CGFloat = initialAngle
        for (index, piece) in items.enumerated() {
            let percent = CGFloat(piece.count) / total
            let segmentSize = 2 * .pi * percent
            let endAngle = startAngle + segmentSize
            if angle >= startAngle && angle <= endAngle ||
               angle + .pi * 2 >= startAngle && angle + .pi * 2 <= endAngle {
                return index
            }
            startAngle = endAngle
        }
        return nil
    }
    
    private let initialAngle: CGFloat = .pi / 3
    
    private func updateChartLayers() {
        chartLayer.frame = bounds
        let center = CGPoint(x: 100, y: 100)
        let chartFrame = CGRect(x: bounds.midX - 100, y: bounds.midY - 100, width: 200, height: 200)
        let innerRadius = min(bounds.width, bounds.height) / 5
        let visibleItems = items.filter { (animationValues.values[$0.id]?.value ?? $0.count) > 0 }
        let counts = visibleItems.map { CGFloat(animationValues.values[$0.id]?.value ?? $0.count) }
        let total = counts.reduce(0, +)
        var validIds = Set<AnyHashable>()
        var startAngle = initialAngle

        if total > 0 {
            for (index, item) in visibleItems.enumerated() {
                validIds.insert(item.id)
                let section: SectionLayer
                if let current = sectionLayers[item.id] {
                    section = current
                } else {
                    section = SectionLayer()
                    sectionLayers[item.id] = section
                    chartLayer.addSublayer(section)
                }
                section.frame = chartFrame
                var radius = min(bounds.width, bounds.height) / 2 - presentation.strokeSize - 8
                if visibleItems.count > 1 {
                    radius -= 5 * (animationValues.radius[item.id] ?? 0)
                }
                radius = max(innerRadius, radius)
                let fraction = counts[index] / total
                let endAngle = startAngle + 2 * .pi * fraction
                let middleAngle = (startAngle + endAngle) / 2

                let path = CGMutablePath()
                path.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
                path.addArc(center: center, radius: innerRadius, startAngle: endAngle, endAngle: startAngle, clockwise: true)
                path.closeSubpath()

                let strokePath = CGMutablePath()
                strokePath.move(to: center)
                strokePath.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
                strokePath.closeSubpath()
                section.update(item: item, size: chartFrame.size, path: path, strokePath: strokePath, presentation: presentation)
                section.updateParticles(particleSet: particleSet)

                let fontFraction = min(CGFloat.pi / 4, 1)
                let fontSize = (4 + (radius / 7 - 4) * fontFraction).rounded(.down)
                let diagramRadius = radius - 5
                let labelOffset = diagramRadius / 2 + diagramRadius / 2 * (1 - fontFraction) + 15
                let labelCenter = CGPoint(x: center.x + cos(middleAngle) * labelOffset, y: center.y + sin(middleAngle) * labelOffset)
                let text = fraction >= 0.04 && fraction != 1 ? "\(Int(fraction * 100))%" : nil
                section.updateLabel(text: text, fontSize: fontSize, color: presentation.itemTextColor, center: labelCenter)
                startAngle = endAngle
            }
        }

        for id in Set(sectionLayers.keys).subtracting(validIds) {
            sectionLayers.removeValue(forKey: id)?.removeFromSuperlayer()
        }
    }

    private func middleTextPoint(_ point: NSPoint, item: Item) -> NSPoint {
        
        let selectionAnimationFraction: CGFloat = 1.0

        let radius = min(bounds.width, bounds.height) / 2 - presentation.strokeSize - 8


        
        let centerOffsetStartAngle = CGFloat.pi / 4
        let fraction = max(0, min(centerOffsetStartAngle, 1))
        
        let animationSelectionOffset: CGFloat = 5

        let diagramRadius = radius - animationSelectionOffset

        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let labelPotisionOffset = diagramRadius / 2 + diagramRadius / 2 * (1 - fraction) + 15
        let angle = (center - point).angle + .pi
        let total: CGFloat = items.map({ CGFloat($0.count) }).reduce(0, +)

        var startAngle: CGFloat = initialAngle
        for piece in items {
            let percent = CGFloat(piece.count) / total
            let segmentSize = 2 * .pi * percent
            let endAngle = startAngle + segmentSize
            if angle >= startAngle && angle <= endAngle ||
               angle + .pi * 2 >= startAngle && angle + .pi * 2 <= endAngle {
                
                let centerAngle = (startAngle + endAngle) / 2
                let vector = CGPoint(x: cos(centerAngle),
                                          y: sin(centerAngle))
                
                let updatedCenter = CGPoint(x: center.x + vector.x * selectionAnimationFraction * animationSelectionOffset,
                                            y: center.y + vector.y * selectionAnimationFraction * animationSelectionOffset)


                return CGPoint(x: floor(vector.x * labelPotisionOffset + updatedCenter.x),
                                         y: floor(vector.y * labelPotisionOffset + updatedCenter.y))

            }
            startAngle = endAngle
        }
        return .zero
    }
    
    private func updateTooltip(_ point: NSPoint) {
        if let index = self.selectedItemIndex(at: point) {
            let item = self.items[index]
            if let badge = item.badge {
                let current: TooltipView
                if let view = self.tooltipView {
                    current = view
                } else {
                    current = TooltipView(frame: .zero)
                    addSubview(current)
                    self.tooltipView = current
                    
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
                let size = current.update(attr: badge, animated: true)
                let point = middleTextPoint(point, item: item)
                current.frame = CGRect(origin: point - NSMakePoint(size.width / 2, size.height / 2), size: size)
            }  else if let view = self.tooltipView {
                performSubviewRemoval(view, animated: true)
                self.tooltipView = nil
            }
        } else if let view = self.tooltipView {
            performSubviewRemoval(view, animated: true)
            self.tooltipView = nil
        }
    }
    
    private func updateGraph(_ point: NSPoint) {
        if let index = self.selectedItemIndex(at: point) {
            self.animationValues.selected = self.items[index].id
        } else {
            self.animationValues.selected = nil
        }
        self.updateTooltip(point)
    }
    
    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateGraph(self.convert(event.locationInWindow, from: nil))
    }
    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateGraph(self.convert(event.locationInWindow, from: nil))
    }
    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        updateGraph(self.convert(event.locationInWindow, from: nil))
    }
}
