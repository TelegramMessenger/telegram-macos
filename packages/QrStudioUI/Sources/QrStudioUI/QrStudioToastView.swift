import Foundation
import Cocoa
import QuartzCore
import CoreImage
import TGUIKit

struct QrStudioToast {
    struct Action {
        let title: String
        let perform: () -> Void
    }

    let icon: String
    let text: String
    var action: Action? = nil
}

final class QrStudioToastView: View {
    private enum Phase {
        case opening(Double)
        case holding(Double)
        case closing(Double)
    }

    private enum IconMode: Equatable {
        case image
        case progress
    }

    private static let iconFrame = CGRect(x: 14.0, y: 0.0, width: 30.0, height: 30.0)
    private static let maxTextWidth: CGFloat = 270.0

    private let glass = LiquidGlassView(frame: .zero, cornerRadius: 24.0, hasShadow: false, hasBorder: true, tintAlpha: 0.0, forceAppearance: .forceDark)
    private let contentView = View()
    private let contentMask = SimpleShapeLayer()
    private let iconView = ImageView(frame: .zero)
    private let label = TextView()
    private let actionLabel = TextView()
    private var action: QrStudioToast.Action?
    private let progressView = View()
    private let progressLayer = SimpleShapeLayer()
    private let cancelIconView = ImageView(frame: .zero)
    private var phase: Phase?
    private var text = ""
    private var contentSize = CGSize()
    private var contentOrigin = CGPoint()
    private var availableWidth: CGFloat = .greatestFiniteMagnitude
    private var glassWidth: CGFloat = 0.0
    private var currentP: CGFloat = 0.0
    private var lastTick: Double?
    private var displayLink: SharedDisplayLinkDriver.Link?
    private var cancel: (() -> Void)?
    private var isMouseDown = false

    private(set) var isShowingProgress = false

    static func glassColor(ink: QrStudioColor, isLight: Bool) -> NSColor {
        return (isLight ? QrStudioColor(0.0, 0.0, 0.0) : ink).nsColor.withAlphaComponent(0.55)
    }

    override init() {
        super.init(frame: .zero)
        self.setup()
    }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.setup()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setup() {
        self.isHidden = true
        self.layer?.masksToBounds = false

        self.addSubview(self.glass)

        self.contentView.isEventLess = true
        self.contentView.layerUsesCoreImageFilters = true
        self.contentView.layer?.masksToBounds = false

        self.iconView.isEventLess = true
        self.iconView.contentGravity = .center
        self.contentView.addSubview(self.iconView)

        let lineWidth: CGFloat = 2.5
        let ringSide = QrStudioToastView.iconFrame.width
        self.progressLayer.path = CGPath(ellipseIn: CGRect(x: 0.0, y: 0.0, width: ringSide, height: ringSide).insetBy(dx: lineWidth * 0.5, dy: lineWidth * 0.5), transform: nil)
        self.progressLayer.frame = CGRect(x: 0.0, y: 0.0, width: ringSide, height: ringSide)
        self.progressLayer.lineWidth = lineWidth
        self.progressLayer.strokeColor = NSColor.white.cgColor
        self.progressLayer.fillColor = NSColor.clear.cgColor
        self.progressLayer.lineCap = .round
        self.progressLayer.strokeEnd = 0.027
        self.progressView.isEventLess = true
        self.progressView.layer?.masksToBounds = false
        self.progressView.layer?.addSublayer(self.progressLayer)
        self.progressView.isHidden = true
        self.contentView.addSubview(self.progressView)

        self.cancelIconView.isEventLess = true
        self.cancelIconView.image = NSImage(named: "Icon_StoryClose")?.precomposed(NSColor.white)
        self.cancelIconView.contentGravity = .resizeAspect
        self.cancelIconView.isHidden = true
        self.contentView.addSubview(self.cancelIconView)

        self.label.isSelectable = false
        self.label.userInteractionEnabled = false
        self.label.isEventLess = true
        self.contentView.addSubview(self.label)

        self.actionLabel.isSelectable = false
        self.actionLabel.userInteractionEnabled = false
        self.actionLabel.isEventLess = true
        self.actionLabel.isHidden = true
        self.contentView.addSubview(self.actionLabel)

        self.contentView.layer?.mask = self.contentMask
        self.addSubview(self.contentView)
    }

    private static func iconName(_ key: String) -> String {
        switch (key as NSString).lastPathComponent.lowercased() {
        case "timer":
            return "menu_schedule_message"
        case "stars":
            return "menu_folder_star"
        case "reload":
            return "menu_reload"
        case "link":
            return "menu_copy_link"
        case "download":
            return "menu_save_as"
        case "image":
            return "menu_copy_media"
        case "check":
            return "menu_check_selected"
        default:
            return "menu_show_info"
        }
    }

    private static func icon(_ key: String) -> CGImage? {
        return NSImage(named: self.iconName(key))?.precomposed(NSColor.white)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !self.isHidden else {
            return nil
        }
        let local = self.convert(point, from: self.superview)
        if self.action != nil {
            if case .closing = self.phase {
                return nil
            }
            return self.actionArea.contains(local) ? self : nil
        }
        guard self.isShowingProgress else {
            return nil
        }
        return self.cancelArea.contains(local) ? self : nil
    }

    private var actionArea: CGRect {
        return CGRect(x: self.bounds.width - 120.0, y: 0.0, width: 120.0, height: self.bounds.height)
    }

    private var cancelArea: CGRect {
        let icon = self.iconView.frame.offsetBy(dx: self.contentOrigin.x, dy: self.contentOrigin.y)
        return CGRect(x: icon.minX - 12.0, y: 0.0, width: icon.width + 24.0, height: self.bounds.height)
    }

    override func mouseDown(with event: NSEvent) {
        guard self.isShowingProgress || self.action != nil else {
            super.mouseDown(with: event)
            return
        }
        self.isMouseDown = true
    }

    override func mouseUp(with event: NSEvent) {
        guard self.isMouseDown else {
            super.mouseUp(with: event)
            return
        }
        self.isMouseDown = false
        let point = self.convert(event.locationInWindow, from: nil)
        if let action = self.action {
            guard self.actionArea.contains(point) else {
                return
            }
            self.action = nil
            self.phase = .closing(QrStudioClock.now)
            self.startDisplayLink()
            action.perform()
            return
        }
        guard self.isShowingProgress, self.cancelArea.contains(point) else {
            return
        }
        let cancel = self.cancel
        self.cancel = nil
        self.isShowingProgress = false
        self.dismiss()
        cancel?()
    }

    func show(_ toast: QrStudioToast, ink: QrStudioColor, isLight: Bool) {
        self.isShowingProgress = false
        self.cancel = nil
        self.action = toast.action
        self.iconView.image = QrStudioToastView.icon(toast.icon)
        self.setIcon(.image)
        self.present(text: toast.text, ink: ink, isLight: isLight)
    }

    func showProgress(text: String, ink: QrStudioColor, isLight: Bool, cancel: @escaping () -> Void) {
        self.isShowingProgress = true
        self.cancel = cancel
        self.action = nil
        self.progressLayer.removeAnimation(forKey: "strokeEnd")
        self.progressLayer.strokeEnd = 0.027
        self.setIcon(.progress)
        self.present(text: text, ink: ink, isLight: isLight)
        if self.progressLayer.animation(forKey: "rotation") == nil {
            let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
            rotation.duration = 2.0
            rotation.fromValue = 0.0 as NSNumber
            rotation.toValue = (Double.pi * 2.0) as NSNumber
            rotation.repeatCount = Float.infinity
            rotation.timingFunction = CAMediaTimingFunction(name: .linear)
            self.progressLayer.add(rotation, forKey: "rotation")
        }
    }

    func updateProgress(_ value: Double) {
        guard self.isShowingProgress else {
            return
        }
        let target = CGFloat(max(0.027, min(1.0, value)))
        let from = self.progressLayer.presentation()?.strokeEnd ?? self.progressLayer.strokeEnd
        self.progressLayer.strokeEnd = target
        self.progressLayer.animate(from: NSNumber(value: Double(from)), to: NSNumber(value: Double(target)), keyPath: "strokeEnd", timingFunction: .easeOut, duration: 0.2)
    }

    func completeProgress(text: String) {
        guard self.isShowingProgress else {
            return
        }
        self.isShowingProgress = false
        self.cancel = nil
        self.iconView.image = QrStudioToastView.icon("download")
        self.setIcon(.image)
        self.iconView.layer?.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
        self.text = text
        self.layoutContent()
        let fade = CATransition()
        fade.type = .fade
        fade.duration = 0.2
        self.label.layer?.add(fade, forKey: "text")
        self.phase = .holding(QrStudioClock.now)
        self.startDisplayLink()
    }

    func dismiss() {
        switch self.phase {
        case .opening, .holding:
            self.phase = .closing(QrStudioClock.now)
            self.startDisplayLink()
        default:
            break
        }
    }

    func sizeThatFits(width: CGFloat) -> CGSize {
        if self.availableWidth != width {
            self.availableWidth = width
            if self.phase != nil {
                self.layoutContent()
                self.startDisplayLink()
            }
        }
        return self.contentSize
    }

    private func setIcon(_ mode: IconMode) {
        self.iconView.isHidden = mode != .image
        self.progressView.isHidden = mode != .progress
        self.cancelIconView.isHidden = mode != .progress
        if mode != .progress {
            self.progressLayer.removeAnimation(forKey: "rotation")
        }
    }

    private func present(text: String, ink: QrStudioColor, isLight: Bool) {
        self.text = text
        self.layoutContent()
        self.glassWidth = self.contentSize.width
        let tint = QrStudioToastView.glassColor(ink: ink, isLight: isLight)
        if !(self.glass.customTint?.isEqual(tint) ?? false) {
            self.glass.setCustomTint(tint, animated: false)
        }
        self.isHidden = false
        self.phase = .opening(QrStudioClock.now)
        self.startDisplayLink()
        self.tick()
    }

    private func layoutContent() {
        var actionLayout: TextViewLayout?
        var actionWidth: CGFloat = 0.0
        if let action = self.action {
            let layout = TextViewLayout(NSAttributedString(string: action.title, attributes: [.font: NSFont.semibold(14.0), .foregroundColor: NSColor(red: 0.45, green: 0.73, blue: 1.0, alpha: 1.0)]), maximumNumberOfLines: 1)
            layout.measure(width: 200.0)
            actionLayout = layout
            actionWidth = 12.0 + ceil(layout.layoutSize.width)
        }
        let maxTextWidth = max(1.0, min(self.action != nil ? 200.0 : QrStudioToastView.maxTextWidth, self.availableWidth - 66.0 - actionWidth))
        let attributed = NSAttributedString(string: self.text, attributes: [.font: NSFont.normal(14.0), .foregroundColor: NSColor.white])
        let layout = TextViewLayout(attributed, maximumNumberOfLines: 2)
        layout.measure(width: maxTextWidth)
        let textWidth = min(maxTextWidth, ceil(layout.layoutSize.width))
        let textHeight = ceil(layout.layoutSize.height)
        let height = max(48.0, textHeight + 18.0)
        self.contentSize = CGSize(width: 14.0 + 30.0 + 12.0 + textWidth + actionWidth + 20.0, height: height)
        let iconFrame = CGRect(x: QrStudioToastView.iconFrame.minX, y: floor((height - 30.0) * 0.5), width: 30.0, height: 30.0)
        self.label.update(layout)
        self.label.frame = CGRect(x: 14.0 + 30.0 + 12.0, y: floor((height - textHeight) * 0.5), width: textWidth, height: textHeight)
        self.actionLabel.isHidden = actionLayout == nil
        if let actionLayout {
            self.actionLabel.update(actionLayout)
            self.actionLabel.frame = CGRect(x: self.label.frame.maxX + 12.0, y: floor((height - actionLayout.layoutSize.height) * 0.5), width: actionLayout.layoutSize.width, height: actionLayout.layoutSize.height)
        }
        self.iconView.frame = iconFrame
        self.progressView.frame = iconFrame
        self.cancelIconView.frame = iconFrame.insetBy(dx: 8.0, dy: 8.0)

        let frame = self.frame
        if frame.size != self.contentSize {
            if frame.size == CGSize() {
                self.setFrameSize(self.contentSize)
            } else {
                self.frame = CGRect(x: floor(frame.midX - self.contentSize.width * 0.5), y: floor(frame.midY - self.contentSize.height * 0.5), width: self.contentSize.width, height: self.contentSize.height)
            }
        }
        self.layoutContentView()
    }

    private func layoutContentView() {
        let bounds = self.bounds
        self.contentOrigin = CGPoint(x: floor((bounds.width - self.contentSize.width) * 0.5), y: floor((bounds.height - self.contentSize.height) * 0.5))
        let frame = CGRect(origin: self.contentOrigin, size: self.contentSize)
        if self.contentView.frame != frame, let layer = self.contentView.layer {
            let transform = layer.transform
            layer.transform = CATransform3DIdentity
            self.contentView.frame = frame
            layer.transform = transform
        }
    }

    override func layout() {
        super.layout()
        self.layoutContentView()
        if self.phase != nil {
            self.apply(self.currentP)
        }
    }

    private func startDisplayLink() {
        if self.displayLink == nil {
            self.lastTick = nil
            self.displayLink = SharedDisplayLinkDriver.shared.add(framesPerSecond: .fps(60), { [weak self] _ in
                self?.tick()
            })
        }
    }

    private func stopDisplayLink() {
        self.displayLink?.invalidate()
        self.displayLink = nil
    }

    private func tick() {
        guard let phase = self.phase else {
            return
        }
        let now = QrStudioClock.now
        let dt = self.lastTick.map { now - $0 } ?? 0.0
        self.lastTick = now
        self.glassWidth = QrStudioLens.approach(self.glassWidth, to: self.contentSize.width, dt: dt)
        let p: CGFloat
        switch phase {
        case let .opening(start):
            p = QrStudioLens.opening(now - start)
            if now - start >= QrStudioLens.openDuration * 1.6 {
                self.phase = .holding(now)
            }
        case let .holding(start):
            p = 1.0
            if QrStudioLens.closesAfterHold(holding: now - start, isPersistent: self.isShowingProgress) {
                self.phase = .closing(now)
            } else if self.isShowingProgress && self.glassWidth == self.contentSize.width {
                self.stopDisplayLink()
            }
        case let .closing(start):
            if now - start >= QrStudioLens.closeDuration {
                self.phase = nil
                self.stopDisplayLink()
                self.isHidden = true
                self.action = nil
                self.isShowingProgress = false
                self.isMouseDown = false
                self.progressLayer.removeAnimation(forKey: "rotation")
                return
            }
            p = QrStudioLens.closing(now - start)
        }
        self.apply(p)
    }

    private static func scaleTransform(_ scale: CGFloat, layer: CALayer) -> CATransform3D {
        let dx = layer.bounds.width * (0.5 - layer.anchorPoint.x)
        let dy = layer.bounds.height * (0.5 - layer.anchorPoint.y)
        var transform = CATransform3DMakeTranslation(dx, dy, 0.0)
        transform = CATransform3DScale(transform, scale, scale, 1.0)
        transform = CATransform3DTranslate(transform, -dx, -dy, 0.0)
        return transform
    }

    private func apply(_ p: CGFloat) {
        self.currentP = p
        let contentSize = self.contentSize
        let size = QrStudioLens.size(p, width: self.glassWidth, height: contentSize.height)
        let c = QrStudioLens.ramp(p, 0.2, 0.95)
        let cornerRadius = min(size.height * 0.5, 24.0)
        let localGlass = CGRect(x: (contentSize.width - size.width) * 0.5, y: (contentSize.height - size.height) * 0.5, width: size.width, height: size.height)
        let glassFrame = localGlass.offsetBy(dx: self.contentOrigin.x, dy: self.contentOrigin.y)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let hasGlass = size.width > 0.0 && size.height > 0.0
        self.glass.isHidden = !hasGlass
        if hasGlass {
            self.glass.frame = glassFrame
            self.glass.cornerRadius = cornerRadius
            self.glass.updateLayout(size: glassFrame.size, transition: .immediate)
        }

        let scale = 1.0 + 0.85 * (1.0 - c)
        if let layer = self.contentView.layer {
            layer.transform = QrStudioToastView.scaleTransform(scale, layer: layer)
            layer.opacity = Float(QrStudioLens.ramp(p, 0.08, 0.5))
        }
        let radius = 5.0 * (1.0 - c)
        if radius > 0.05, let filter = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: NSNumber(value: Double(radius))]) {
            self.contentView.contentFilters = [filter]
        } else if !self.contentView.contentFilters.isEmpty {
            self.contentView.contentFilters = []
        }

        let center = CGPoint(x: contentSize.width * 0.5, y: contentSize.height * 0.5)
        let local = CGRect(x: center.x + (localGlass.minX - center.x) / scale, y: center.y + (localGlass.minY - center.y) / scale, width: localGlass.width / scale, height: localGlass.height / scale)
        self.contentMask.frame = CGRect(origin: CGPoint(), size: contentSize)
        if local.width > 0.0 && local.height > 0.0 {
            let radius = min(cornerRadius / scale, local.width * 0.5, local.height * 0.5)
            self.contentMask.path = CGPath(roundedRect: local, cornerWidth: radius, cornerHeight: radius, transform: nil)
        } else {
            self.contentMask.path = nil
        }

        CATransaction.commit()
    }
}
