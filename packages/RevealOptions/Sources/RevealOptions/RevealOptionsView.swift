import AppKit
import TGUIKit

final class RevealOptionsView: View {
    private(set) var options: [RevealOption] = []
    let isLeft: Bool
    private let configuration: RevealOptionsConfiguration
    private let animationFactory: RevealOptionAnimationFactory?
    private var optionViews: [RevealOptionView] = []
    private var currentMetrics: (height: CGFloat, metrics: RevealOptionLayoutMetrics)?
    private var pressedIndex: Int?

    var optionSelected: ((RevealOption) -> Void)?

    init(isLeft: Bool, configuration: RevealOptionsConfiguration, animationFactory: RevealOptionAnimationFactory?) {
        self.isLeft = isLeft
        self.configuration = configuration
        self.animationFactory = animationFactory
        super.init(frame: .zero)
        self.layer?.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    func setOptions(_ options: [RevealOption]) {
        guard self.options != options else {
            return
        }
        self.options = options
        for view in self.optionViews {
            view.removeFromSuperview()
        }
        self.pressedIndex = nil
        self.optionViews = options.map { option in
            return RevealOptionView(option: option, configuration: self.configuration, animationFactory: self.animationFactory)
        }
        if self.isLeft {
            for view in self.optionViews.reversed() {
                self.addSubview(view)
            }
        } else {
            for view in self.optionViews {
                self.addSubview(view)
            }
        }
        self.currentMetrics = nil
    }

    func metrics(height: CGFloat) -> RevealOptionLayoutMetrics {
        if let currentMetrics = self.currentMetrics, currentMetrics.height == height {
            return currentMetrics.metrics
        }
        let hasVisualIcons = self.options.contains(where: { $0.icon.hasVisualIcon })
        var metrics = RevealOptionLayoutMetrics.metrics(for: height, hasVisualIcons: hasVisualIcons, scale: self.configuration.scale, titleFont: self.configuration.titleFont)
        metrics.iconScale = self.configuration.iconScale
        let updatedMetrics: RevealOptionLayoutMetrics
        if hasVisualIcons, self.configuration.sizing == .circles {
            updatedMetrics = metrics.withTitleWidths(self.optionViews.map(\.titleWidth))
        } else {
            let maxTitleWidth = self.optionViews.reduce(0) { result, view in
                return max(result, view.titleWidthForGroupPillSizing)
            }
            updatedMetrics = metrics.withGroupTitleWidth(maxTitleWidth)
        }
        self.currentMetrics = (height, updatedMetrics)
        return updatedMetrics
    }

    func motionParameters(width: CGFloat, height: CGFloat, displayScale: CGFloat) -> RevealMotionParameters {
        let metrics = self.metrics(height: height)
        let primary = self.isLeft ? self.options.first : self.options.last
        return RevealMotionParameters(width: Double(width), buttonWidth: Double(metrics.shapeSize.width), spacing: Double(metrics.spacing), edgeInset: Double(metrics.edgeInset), sideInset: 0, count: self.options.count, isDestructive: primary?.isDestructive ?? false, displayScale: Double(displayScale))
    }

    func render(motion: RevealMotion) {
        let distance = self.frame.width
        let height = self.frame.height
        let metrics = self.metrics(height: height)
        let geometry = motion.buttonGeometry
        for (index, view) in self.optionViews.enumerated() {
            let order = self.isLeft ? index : self.optionViews.count - 1 - index
            guard order < geometry.count, order < motion.scales.count else {
                continue
            }
            let g = geometry[order]
            let primary = order == 0
            let stretched = primary && g.width > Double(metrics.shapeSize.width) + 0.001
            let center = self.isLeft ? CGFloat(g.center) : distance - CGFloat(g.center)
            let scale = max(1, self.backingScaleFactor)
            let viewWidth = ((stretched ? CGFloat(g.width) : metrics.slotWidth) * scale).rounded() / scale
            view.frame = NSMakeRect(((center - viewWidth / 2) * scale).rounded() / scale, 0, viewWidth, height)
            view.updateLayout(isLeft: self.isLeft, isPrimary: primary, metrics: metrics, revealProgress: CGFloat(motion.scales[order].value), expandedProgress: primary ? CGFloat(min(1, max(0, motion.expansion.value))) : 0, isStretched: stretched, isExpanded: motion.isExpanded && primary, motionScale: CGFloat(motion.scales[order].value), motionOpacity: CGFloat(motion.opacities[order].value))
        }
    }

    private func optionIndex(at point: NSPoint) -> Int? {
        guard NSPointInRect(point, self.bounds) else {
            return nil
        }
        var i = self.isLeft ? 0 : self.optionViews.count - 1
        while i >= 0 && i < self.optionViews.count {
            let view = self.optionViews[i]
            if view.canBeHit, NSPointInRect(point, view.frame) {
                return i
            }
            if self.isLeft {
                i += 1
            } else {
                i -= 1
            }
        }
        return nil
    }

    func containsAction(atWindowPoint point: NSPoint) -> Bool {
        guard self.superview != nil, !self.isHidden else {
            return false
        }
        return self.optionIndex(at: self.convert(point, from: nil)) != nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !self.isHidden, self.alphaValue > 0.01, let superview = self.superview else {
            return nil
        }
        return self.optionIndex(at: self.convert(point, from: superview)) != nil ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        let index = self.optionIndex(at: self.convert(event.locationInWindow, from: nil))
        self.pressedIndex = index
        for (i, view) in self.optionViews.enumerated() {
            view.setHighlighted(i == index)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let pressedIndex = self.pressedIndex, pressedIndex < self.optionViews.count else {
            return
        }
        let index = self.optionIndex(at: self.convert(event.locationInWindow, from: nil))
        self.optionViews[pressedIndex].setHighlighted(index == pressedIndex)
    }

    override func mouseUp(with event: NSEvent) {
        let index = self.optionIndex(at: self.convert(event.locationInWindow, from: nil))
        let pressedIndex = self.pressedIndex
        self.pressedIndex = nil
        for view in self.optionViews {
            view.setHighlighted(false)
        }
        if let index = index, index == pressedIndex, index < self.options.count {
            self.optionSelected?(self.options[index])
        }
    }
}
