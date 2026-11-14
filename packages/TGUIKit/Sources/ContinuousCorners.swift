import Cocoa

public func continuousCornerSmoothing(size: CGSize, topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat, limit: CGFloat) -> CGFloat {
    func allowed(_ length: CGFloat, _ first: CGFloat, _ second: CGFloat) -> CGFloat {
        let radii = first + second
        guard radii > 0 else {
            return limit
        }
        return length / radii - 1.0
    }
    let smoothing = min(
        allowed(size.height, topLeft, bottomLeft),
        allowed(size.height, topRight, bottomRight),
        allowed(size.width, topLeft, topRight),
        allowed(size.width, bottomLeft, bottomRight)
    )
    return max(0.0, min(limit, smoothing))
}

public extension CGMutablePath {
    func addContinuousCorner(corner: CGPoint, incoming u: CGPoint, outgoing v: CGPoint, radius: CGFloat, smoothing: CGFloat) {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            return CGPoint(x: corner.x + u.x * x + v.x * y, y: corner.y + u.y * x + v.y * y)
        }
        guard radius > 0 else {
            self.addLine(to: corner)
            return
        }
        let p = (1.0 + smoothing) * radius
        let arcMeasure = 90.0 * (1.0 - smoothing)
        let arcLength = sin(arcMeasure / 2.0 * .pi / 180.0) * radius * 2.0.squareRoot()
        let alpha = (90.0 - arcMeasure) / 2.0
        let beta = 45.0 * smoothing * .pi / 180.0
        let c = radius * tan(alpha / 2.0 * .pi / 180.0) * cos(beta)
        let d = c * tan(beta)
        let b = (p - arcLength - c - d) / 3.0
        let a = 2.0 * b

        let arcStart = CGPoint(x: p - a - b - c, y: d)
        let arcEnd = CGPoint(x: arcStart.x - arcLength, y: d + arcLength)
        let tangentLength = radius * tan(arcMeasure / 2.0 * .pi / 180.0)
        let tangentCross = CGPoint(x: arcStart.x - tangentLength * cos(beta), y: arcStart.y + tangentLength * sin(beta))

        self.addLine(to: point(p, 0.0))
        self.addCurve(to: point(arcStart.x, arcStart.y), control1: point(p - a, 0.0), control2: point(p - a - b, 0.0))
        self.addArc(tangent1End: point(tangentCross.x, tangentCross.y), tangent2End: point(arcEnd.x, arcEnd.y), radius: radius)
        self.addCurve(to: point(0.0, p), control1: point(arcEnd.x - d, arcEnd.y + c), control2: point(arcEnd.x - d, arcEnd.y + b + c))
    }
}

public extension CGPath {
    static func continuousRoundedRect(_ rect: CGRect, topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat, smoothing: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        path.move(to: CGPoint(x: maxX - (1.0 + smoothing) * topRight, y: minY))
        path.addContinuousCorner(corner: CGPoint(x: maxX, y: minY), incoming: CGPoint(x: -1.0, y: 0.0), outgoing: CGPoint(x: 0.0, y: 1.0), radius: topRight, smoothing: smoothing)
        path.addContinuousCorner(corner: CGPoint(x: maxX, y: maxY), incoming: CGPoint(x: 0.0, y: -1.0), outgoing: CGPoint(x: -1.0, y: 0.0), radius: bottomRight, smoothing: smoothing)
        path.addContinuousCorner(corner: CGPoint(x: minX, y: maxY), incoming: CGPoint(x: 1.0, y: 0.0), outgoing: CGPoint(x: 0.0, y: -1.0), radius: bottomLeft, smoothing: smoothing)
        path.addContinuousCorner(corner: CGPoint(x: minX, y: minY), incoming: CGPoint(x: 0.0, y: 1.0), outgoing: CGPoint(x: 1.0, y: 0.0), radius: topLeft, smoothing: smoothing)
        path.closeSubpath()
        return path
    }
}
