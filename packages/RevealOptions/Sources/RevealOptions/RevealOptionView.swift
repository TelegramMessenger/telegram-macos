import AppKit
import TGUIKit

private let animationTriggerProgress: CGFloat = 0.1
private let interactiveAnimationResetProgress: CGFloat = 0.01

private func clampToUnitInterval(_ value: CGFloat) -> CGFloat {
    return max(0, min(1, value))
}

final class RevealOptionView: View {
    let option: RevealOption
    private let backgroundView = View()
    private let highlightView = View()
    private let titleView = ImageView()
    private let titleString: NSAttributedString
    private var titleScale: CGFloat = 0
    private var titleSize: NSSize = .zero
    private let iconClipView = View()
    private let iconContainer = View()
    private var imageView: ImageView?
    private var animationView: RevealOptionAnimationView?
    private var animationSize: NSSize = .zero
    private let animationFactory: RevealOptionAnimationFactory?
    private let enableAnimations: Bool
    private let displaysTitleInsidePill: Bool
    private let scale: CGFloat

    private var isAnimationTriggered = false
    private var actionIsHighlighted = false
    private var contentScale: CGFloat = 1
    private(set) var isExpanded = false

    init(option: RevealOption, configuration: RevealOptionsConfiguration, animationFactory: RevealOptionAnimationFactory?) {
        self.option = option
        self.scale = configuration.scale
        self.enableAnimations = configuration.enableAnimations
        self.animationFactory = animationFactory
        let displaysTitleInsidePill: Bool
        if case .none = option.icon {
            displaysTitleInsidePill = true
        } else {
            displaysTitleInsidePill = false
        }
        self.displaysTitleInsidePill = displaysTitleInsidePill
        let font: NSFont = displaysTitleInsidePill ? configuration.pillTitleFont : configuration.titleFont
        self.titleString = .initialize(string: option.title, color: displaysTitleInsidePill ? option.iconColor : option.textColor, font: font)
        super.init(frame: .zero)

        self.titleView.isEventLess = true
        self.titleView.contentGravity = .resize

        self.layer?.allowsGroupOpacity = true
        self.layer?.masksToBounds = false
        self.backgroundView.backgroundColor = option.color
        self.highlightView.backgroundColor = (option.color.usingColorSpace(.deviceRGB) ?? option.color).withMultipliedBrightnessBy(0.9)
        self.highlightView.layer?.opacity = 0
        self.iconContainer.layer?.masksToBounds = false
        self.iconClipView.layer?.masksToBounds = true

        if #available(macOS 10.15, *) {
            self.backgroundView.layer?.cornerCurve = .continuous
            self.highlightView.layer?.cornerCurve = .continuous
            self.iconClipView.layer?.cornerCurve = .continuous
        }

        if case let .image(image) = option.icon {
            let imageView = ImageView()
            imageView.contentGravity = .resizeAspect
            imageView.image = image
            self.imageView = imageView
            self.iconContainer.addSubview(imageView)
        }

        self.addSubview(self.backgroundView)
        self.addSubview(self.highlightView)
        self.iconClipView.addSubview(self.iconContainer)
        self.addSubview(self.iconClipView)
        self.addSubview(self.titleView)

        for view in [self.backgroundView, self.highlightView, self.iconClipView, self.iconContainer] {
            view.isEventLess = true
        }
        self.setAccessibilityLabel(option.title)
        self.updateTitleImage(scale: System.backingScale)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    var titleWidth: CGFloat {
        return self.titleSize.width
    }

    var titleWidthForGroupPillSizing: CGFloat {
        var titleWidth = self.titleSize.width
        if self.displaysTitleInsidePill {
            titleWidth += 8 * self.scale
        }
        return titleWidth
    }

    var canBeHit: Bool {
        return self.alphaValue > 0.1 && abs(self.contentScale) > 0.3
    }

    func setHighlighted(_ highlighted: Bool) {
        guard self.actionIsHighlighted != highlighted, let layer = self.highlightView.layer else {
            return
        }
        self.actionIsHighlighted = highlighted
        let previousAlpha = CGFloat(layer.presentation()?.opacity ?? layer.opacity)
        layer.removeAnimation(forKey: "opacity")
        layer.opacity = highlighted ? 1 : 0
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            layer.animateAlpha(from: previousAlpha, to: highlighted ? 1 : 0, duration: highlighted ? 0.08 : 0.18)
        }
    }

    private func setAnimationTriggered(_ isTriggered: Bool) {
        guard self.enableAnimations, self.isAnimationTriggered != isTriggered else {
            return
        }
        self.isAnimationTriggered = isTriggered
        if isTriggered {
            self.animationView?.play()
        } else {
            self.animationView?.reset()
        }
    }

    private func updateAnimationView(size: NSSize, animation: RevealOptionAnimation) {
        guard self.animationSize != size else {
            return
        }
        self.animationSize = size
        self.animationView?.removeFromSuperview()
        self.animationView = self.animationFactory?(animation, self.option.color, size)
        self.isAnimationTriggered = false
        if let animationView = self.animationView {
            animationView.frame = NSMakeRect(0, 0, size.width, size.height)
            self.iconContainer.addSubview(animationView)
        }
        self.iconContainer.layer?.sublayerTransform = RevealOptionView.centeredTransform(self.iconContainer.layer, size: size, transform: animation.flip ? CATransform3DMakeScale(1, -1, 1) : CATransform3DIdentity)
    }

    private static func centeredTransform(_ layer: CALayer?, size: NSSize, transform: CATransform3D) -> CATransform3D {
        let anchor = layer?.anchorPoint ?? .zero
        let dx = size.width / 2 - anchor.x * size.width
        let dy = size.height / 2 - anchor.y * size.height
        var result = CATransform3DMakeTranslation(-dx, -dy, 0)
        result = CATransform3DConcat(result, transform)
        result = CATransform3DConcat(result, CATransform3DMakeTranslation(dx, dy, 0))
        return result
    }

    private func applyContentTransform(scale: CGFloat) {
        if scale >= 0.999 {
            self.layer?.sublayerTransform = CATransform3DIdentity
        } else {
            self.layer?.sublayerTransform = RevealOptionView.centeredTransform(self.layer, size: self.bounds.size, transform: CATransform3DMakeScale(scale, scale, 1))
        }
    }

    private func updateTitleImage(scale: CGFloat) {
        let scale = max(1, scale)
        self.titleScale = scale
        let line = CTLineCreateWithAttributedString(self.titleString)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let pixelWidth = max(1, Int(ceil(width * scale)))
        let pixelHeight = max(1, Int(ceil((ascent + descent) * scale)))
        self.titleSize = NSMakeSize(CGFloat(pixelWidth) / scale, CGFloat(pixelHeight) / scale)
        guard let context = CGContext(data: nil, width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            self.titleView.image = nil
            return
        }
        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setAllowsFontSmoothing(false)
        context.setShouldSmoothFonts(false)
        context.scaleBy(x: scale, y: scale)
        context.textPosition = CGPoint(x: 0, y: descent)
        CTLineDraw(line, context)
        self.titleView.image = context.makeImage()
    }

    func updateLayout(isLeft: Bool, isPrimary: Bool, metrics: RevealOptionLayoutMetrics, revealProgress: CGFloat, expandedProgress: CGFloat, isStretched: Bool, isExpanded: Bool, motionScale: CGFloat, motionOpacity: CGFloat) {
        let bounds = self.bounds
        let backingScaleFactor = self.backingScaleFactor
        if self.backingScaleFactor != self.titleScale {
            self.updateTitleImage(scale: self.backingScaleFactor)
        }
        let titleSize = self.titleSize

        let pillSize = metrics.shapeSize
        let shapeY: CGFloat
        if self.displaysTitleInsidePill {
            shapeY = floorToScreenPixels(backingScaleFactor, (bounds.height - pillSize.height) / 2)
        } else {
            let contentHeight = pillSize.height + metrics.titleSpacing + titleSize.height
            shapeY = floorToScreenPixels(backingScaleFactor, (bounds.height - contentHeight) / 2)
        }

        let shapeFrameX: CGFloat
        if isStretched {
            shapeFrameX = isLeft ? 0 : bounds.width - pillSize.width
        } else {
            shapeFrameX = floorToScreenPixels(backingScaleFactor, (metrics.slotWidth - pillSize.width) / 2)
        }
        let shapeFrame = NSMakeRect(shapeFrameX, shapeY, pillSize.width, pillSize.height)
        let backgroundFrame: NSRect
        if isStretched {
            backgroundFrame = NSMakeRect(0, shapeY, bounds.width, pillSize.height)
        } else {
            backgroundFrame = shapeFrame
        }

        self.backgroundView.frame = backgroundFrame
        self.highlightView.frame = backgroundFrame
        self.backgroundView.layer?.cornerRadius = metrics.cornerRadius
        self.highlightView.layer?.cornerRadius = metrics.cornerRadius
        self.iconClipView.frame = backgroundFrame
        self.iconClipView.layer?.cornerRadius = metrics.cornerRadius

        self.isExpanded = isExpanded
        let contentScale = max(0.0001, motionScale)
        let contentOpacity = clampToUnitInterval(motionOpacity)
        self.contentScale = contentScale
        self.alphaValue = contentOpacity
        self.applyContentTransform(scale: contentScale)

        let centeredIconCenterX = isPrimary ? backgroundFrame.midX : shapeFrame.midX
        let iconCenterX: CGFloat
        if isPrimary && expandedProgress > 0 {
            let expandedIconCenterX: CGFloat
            if isLeft {
                expandedIconCenterX = backgroundFrame.maxX - metrics.cornerRadius
            } else {
                expandedIconCenterX = backgroundFrame.minX + metrics.cornerRadius
            }
            iconCenterX = centeredIconCenterX + (expandedIconCenterX - centeredIconCenterX) * expandedProgress
        } else {
            iconCenterX = centeredIconCenterX
        }
        let iconCenterY = backgroundFrame.midY

        switch self.option.icon {
        case let .animation(animation):
            var imageSize = NSMakeSize(metrics.animationSide * animation.scale, metrics.animationSide * animation.scale)
            let imageMaxSide = max(imageSize.width, imageSize.height)
            if imageMaxSide > metrics.iconMaxSide {
                let imageScale = metrics.iconMaxSide / imageMaxSide * metrics.iconScale
                imageSize = NSMakeSize(floorToScreenPixels(backingScaleFactor, imageSize.width * imageScale), floorToScreenPixels(backingScaleFactor, imageSize.height * imageScale))
            }
            let scaleFraction = imageSize.height / 56
            let iconFrame = NSMakeRect(floorToScreenPixels(backingScaleFactor, iconCenterX - imageSize.width / 2), floorToScreenPixels(backingScaleFactor, iconCenterY - imageSize.height / 2) + (6 + animation.offset) * scaleFraction, imageSize.width, imageSize.height)
            self.updateAnimationView(size: imageSize, animation: animation)
            self.iconContainer.frame = iconFrame.offsetBy(dx: -backgroundFrame.minX, dy: -backgroundFrame.minY)
            if self.enableAnimations {
                if min(contentScale, contentOpacity) >= animationTriggerProgress {
                    self.setAnimationTriggered(true)
                } else if revealProgress <= interactiveAnimationResetProgress {
                    self.setAnimationTriggered(false)
                }
            }
        case let .image(image):
            var fittedSize = image.backingSize
            let imageMaxSide = max(fittedSize.width, fittedSize.height)
            if imageMaxSide > metrics.iconMaxSide {
                let imageScale = metrics.iconMaxSide / imageMaxSide
                fittedSize = NSMakeSize(floorToScreenPixels(backingScaleFactor, fittedSize.width * imageScale), floorToScreenPixels(backingScaleFactor, fittedSize.height * imageScale))
            }
            let iconFrame = NSMakeRect(floorToScreenPixels(backingScaleFactor, iconCenterX - fittedSize.width / 2), floorToScreenPixels(backingScaleFactor, iconCenterY - fittedSize.height / 2), fittedSize.width, fittedSize.height)
            self.iconContainer.frame = iconFrame.offsetBy(dx: -backgroundFrame.minX, dy: -backgroundFrame.minY)
            self.imageView?.frame = NSMakeRect(0, 0, fittedSize.width, fittedSize.height)
        case .none:
            break
        }

        let titleAlpha: CGFloat = isPrimary && !self.displaysTitleInsidePill ? 1 - expandedProgress : 1
        self.titleView.alphaValue = titleAlpha

        if self.displaysTitleInsidePill {
            let titleCenterX: CGFloat
            if isPrimary && expandedProgress > 0 {
                let titleEdgeInset = max(metrics.expandedIconInset, titleSize.width / 2 + metrics.iconlessTitleExpandedHorizontalPadding)
                let expandedTitleCenterX: CGFloat
                if isLeft {
                    expandedTitleCenterX = backgroundFrame.maxX - titleEdgeInset
                } else {
                    expandedTitleCenterX = backgroundFrame.minX + titleEdgeInset
                }
                titleCenterX = backgroundFrame.midX + (expandedTitleCenterX - backgroundFrame.midX) * expandedProgress
            } else {
                titleCenterX = backgroundFrame.midX
            }
            self.titleView.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, titleCenterX - titleSize.width / 2), floorToScreenPixels(backingScaleFactor, backgroundFrame.midY - titleSize.height / 2), titleSize.width, titleSize.height)
        } else {
            self.titleView.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, iconCenterX - titleSize.width / 2), floorToScreenPixels(backingScaleFactor, shapeFrame.maxY + metrics.titleSpacing), titleSize.width, titleSize.height)
        }
    }
}
