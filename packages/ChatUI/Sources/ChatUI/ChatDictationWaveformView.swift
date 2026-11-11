import Cocoa
import TGUIKit

final class ChatDictationWaveformView: View {
    private let bars = CAShapeLayer()
    private var waveform = ChatDictationWaveform()
    var animationsEnabled = true

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEventLess = true
        bars.fillColor = nil
        bars.strokeColor = NSColor.white.cgColor
        bars.lineWidth = 2
        bars.contentsScale = 2
        bars.lineCap = .round
        layer?.addSublayer(bars)
        updatePath(animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func reset() {
        waveform = ChatDictationWaveform()
        bars.removeAllAnimations()
        updatePath(animated: false)
    }

    func transitionLayer() -> CALayer {
        let container = CALayer()
        container.frame = frame
        let copy = CAShapeLayer()
        copy.frame = bounds
        copy.path = bars.presentation()?.path ?? bars.path
        copy.fillColor = bars.fillColor
        copy.strokeColor = bars.strokeColor
        copy.lineWidth = bars.lineWidth
        copy.lineCap = bars.lineCap
        copy.contentsScale = bars.contentsScale
        container.addSublayer(copy)
        return container
    }

    func updateLevel(_ level: CGFloat) {
        waveform.update(level)
        updatePath(animated: animationsEnabled && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    override func layout() {
        super.layout()
        updatePath(animated: false)
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        bars.contentsScale = window?.backingScaleFactor ?? 2
    }

    private func updatePath(animated: Bool) {
        let previous = bars.presentation()?.path ?? bars.path
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        bars.frame = bounds
        bars.path = waveform.iconPath(size: bounds.size)
        CATransaction.commit()
        if animated, let previous, window != nil {
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = previous
            animation.toValue = bars.path
            animation.duration = 0.1
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            bars.add(animation, forKey: "microphoneLevel")
        }
    }
}
