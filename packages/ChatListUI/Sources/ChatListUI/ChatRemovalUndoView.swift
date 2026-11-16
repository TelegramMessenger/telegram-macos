import Cocoa
import TGUIKit
import SwiftSignalKit
import Localization
import TelegramTheme
import ChatUI

final class ChatRemovalUndoView: Control {
    static let height: CGFloat = 44

    private let visualEffect = NSVisualEffectView()
    private let ringView = View(frame: NSMakeRect(0, 0, 30, 30))
    private let ringLayer = CAShapeLayer()
    private let secondsView = View(frame: NSMakeRect(0, 0, 30, 30))
    private let textView = TextView()
    private let undoButton = TextButton()

    private var toast: PendingChatRemovalToast?
    private var seconds: Int = 0
    private var timer: SwiftSignalKit.Timer?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(visualEffect)
        addSubview(ringView)
        addSubview(secondsView)
        addSubview(textView)
        addSubview(undoButton)

        visualEffect.material = .ultraDark
        visualEffect.blendingMode = .withinWindow
        visualEffect.state = .active

        self.layer?.cornerRadius = 10

        let size = ringView.frame.size
        let lineWidth: CGFloat = 2
        let path = CGMutablePath()
        path.addArc(center: NSMakePoint(size.width / 2, size.height / 2), radius: (size.width - lineWidth) / 2 - 1, startAngle: -.pi / 2, endAngle: .pi * 1.5, clockwise: false)
        ringLayer.path = path
        ringLayer.frame = ringView.bounds
        ringLayer.fillColor = NSColor.clear.cgColor
        ringLayer.strokeColor = NSColor.white.cgColor
        ringLayer.lineWidth = lineWidth
        ringLayer.lineCap = .round
        ringLayer.strokeEnd = 0
        ringView.layer?.addSublayer(ringLayer)

        ringView.userInteractionEnabled = false
        secondsView.userInteractionEnabled = false
        textView.userInteractionEnabled = false
        textView.isSelectable = false

        undoButton.set(font: .medium(.title), for: .Normal)
        undoButton.set(color: TelegramThemeHooks.shared.darkAppearance().colors.accent, for: .Normal)
        undoButton.set(background: .clear, for: .Normal)
        undoButton.set(text: strings().chatUndoManagerUndo, for: .Normal)
        _ = undoButton.sizeToFit(NSMakeSize(24, 0), NSMakeSize(0, ChatRemovalUndoView.height), thatFit: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        timer?.invalidate()
    }

    func update(toast: PendingChatRemovalToast, undo: @escaping () -> Void) {
        undoButton.setSingle(handler: { _ in
            undo()
        }, for: .Click)

        guard self.toast != toast else {
            return
        }
        let animated = self.toast != nil
        self.toast = toast

        let layout = TextViewLayout(.initialize(string: toast.text, color: .white, font: .medium(.text)), maximumNumberOfLines: 1)
        layout.measure(width: .greatestFiniteMagnitude)
        textView.update(layout)

        startRing(toast)
        seconds = 0
        updateSeconds(animated: animated)
        scheduleTick()
        needsLayout = true
    }

    private func startRing(_ toast: PendingChatRemovalToast) {
        let remaining = max(0, toast.deadline - CACurrentMediaTime())
        let fraction = CGFloat(min(1, remaining / toast.duration))

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ringLayer.removeAnimation(forKey: "countdown")
        ringLayer.strokeEnd = 0
        CATransaction.commit()

        let animation = CABasicAnimation(keyPath: "strokeEnd")
        animation.fromValue = fraction
        animation.toValue = 0
        animation.duration = remaining
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        ringLayer.add(animation, forKey: "countdown")
    }

    private func scheduleTick() {
        timer?.invalidate()
        timer = nil
        guard let toast = self.toast else {
            return
        }
        let remaining = toast.deadline - CACurrentMediaTime()
        guard remaining > 1 else {
            return
        }
        let untilNext = remaining - floor(remaining)
        let timer = SwiftSignalKit.Timer(timeout: untilNext > 0.001 ? untilNext : 1, repeat: false, completion: { [weak self] in
            self?.updateSeconds(animated: true)
            self?.scheduleTick()
        }, queue: .mainQueue())
        self.timer = timer
        timer.start()
    }

    private func updateSeconds(animated: Bool) {
        guard let toast = self.toast else {
            return
        }
        let value = max(1, Int(ceil(toast.deadline - CACurrentMediaTime())))
        guard value != seconds else {
            return
        }
        seconds = value

        let view = ImageView(frame: secondsView.bounds)
        view.image = countdownDigitImage(value, size: secondsView.frame.size)
        view.isAccessibilityDecorative = true

        if animated {
            for previous in secondsView.subviews {
                previous.layer?.animateAlpha(from: 1, to: 0, duration: 0.12, removeOnCompletion: false)
                previous.layer?.animatePosition(from: previous.frame.origin, to: NSMakePoint(previous.frame.minX, previous.frame.minY + 10), duration: 0.12, removeOnCompletion: false, completion: { [weak previous] _ in
                    previous?.removeFromSuperview()
                })
            }
        } else {
            secondsView.removeAllSubviews()
        }

        secondsView.addSubview(view)

        if animated {
            view.layer?.animateAlpha(from: 0, to: 1, duration: 0.12)
            view.layer?.animatePosition(from: NSMakePoint(view.frame.minX, view.frame.minY - 10), to: view.frame.origin, duration: 0.12)
        }
    }

    override func layout() {
        super.layout()
        visualEffect.frame = bounds
        ringView.centerY(x: 8)
        secondsView.frame = ringView.frame
        undoButton.centerY(x: frame.width - undoButton.frame.width)

        let textX = ringView.frame.maxX + 10
        if let layout = textView.textLayout {
            layout.measure(width: max(0, undoButton.frame.minX - textX))
            textView.update(layout)
        }
        textView.centerY(x: textX)
    }
}

private func countdownDigitImage(_ value: Int, size: NSSize) -> CGImage? {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: "\(value)", attributes: [.font: NSFont.normal(.title), .foregroundColor: NSColor.white]))
    let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    return generateImage(size, rotatedContext: { size, ctx in
        ctx.clear(size.bounds)
        ctx.translateBy(x: size.width / 2, y: size.height / 2)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = NSMakePoint(-glyphBounds.midX, glyphBounds.midY)
        CTLineDraw(line, ctx)
    })
}
