import Cocoa

public final class MenuShadowLayer: CALayer {
    private static let inset: CGFloat = 40

    private let ambient = CALayer()
    private let contact = CALayer()
    private let cutout = CAShapeLayer()

    public override init() {
        super.init()
        ambient.shadowColor = NSColor.black.cgColor
        ambient.shadowOpacity = 0.35
        ambient.shadowRadius = 10
        ambient.shadowOffset = CGSize(width: 0, height: -4)
        contact.shadowColor = NSColor.black.cgColor
        contact.shadowOpacity = 0.2
        contact.shadowRadius = 2
        contact.shadowOffset = .zero
        cutout.fillRule = .evenOdd
        mask = cutout
        addSublayer(ambient)
        addSublayer(contact)
    }

    public override init(layer: Any) {
        super.init(layer: layer)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(shape: CGPath, in bounds: CGRect) {
        let inset = MenuShadowLayer.inset
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frame = bounds.insetBy(dx: -inset, dy: -inset)
        cutout.frame = self.bounds
        let path = CGMutablePath()
        path.addRect(self.bounds)
        path.addPath(shape, transform: CGAffineTransform(translationX: inset - bounds.minX, y: inset - bounds.minY))
        cutout.path = path
        let inner = NSMakeRect(inset, inset, bounds.width, bounds.height)
        for layer in [ambient, contact] {
            layer.frame = inner
            layer.shadowPath = shape.copy(using: [CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY)])
        }
        CATransaction.commit()
    }
}
