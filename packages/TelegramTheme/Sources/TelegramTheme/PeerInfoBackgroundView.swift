import Cocoa
import TGUIKit

public final class PeerInfoBackgroundView: View {
    private let backgroundGradientLayer: SimpleGradientLayer = SimpleGradientLayer()
    public let avatarBackgroundGradientLayer: SimpleGradientLayer = SimpleGradientLayer()

    public var offset: CGFloat = 0
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.backgroundGradientLayer.anchorPoint = .zero
        self.avatarBackgroundGradientLayer.anchorPoint = .zero
        self.layer?.addSublayer(backgroundGradientLayer)
        self.layer?.addSublayer(avatarBackgroundGradientLayer)

        let baseAvatarGradientAlpha: CGFloat = 0.2
        let numSteps = 6
        self.avatarBackgroundGradientLayer.colors = (0 ..< numSteps).map { i in
            let step: CGFloat = 1.0 - CGFloat(i) / CGFloat(numSteps - 1)
            return NSColor.white.withAlphaComponent(baseAvatarGradientAlpha * pow(step, 2.0)).cgColor
        }
        self.avatarBackgroundGradientLayer.startPoint = CGPoint(x: 0.5, y: 0.5)
        self.avatarBackgroundGradientLayer.endPoint = CGPoint(x: 1.0, y: 1.0)
        self.avatarBackgroundGradientLayer.type = .radial

        self.backgroundGradientLayer.startPoint = CGPoint(x: 0.5, y: 1.0)
        self.backgroundGradientLayer.endPoint = CGPoint(x: 0.5, y: 0.0)
        self.backgroundGradientLayer.type = .radial

    }

    public override var isFlipped: Bool {
        return false
    }

    public var gradient: [NSColor] = [] {
        didSet {
            backgroundGradientLayer.colors = gradient.map { $0.cgColor }
            avatarBackgroundGradientLayer.isHidden = gradient[0].alpha == 0
          //  backgroundGradientLayer.animateGradientColors()
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layout() {
        super.layout()
        self.updateLayout(size: frame.size, transition: .immediate)
    }
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(layer: avatarBackgroundGradientLayer, frame: size.bounds.focus(NSMakeSize(300, 300)).offsetBy(dx: 0, dy: offset))
        transition.updateFrame(layer: backgroundGradientLayer, frame: size.bounds)
    }
}
