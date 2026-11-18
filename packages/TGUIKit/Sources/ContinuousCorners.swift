import Cocoa

public func continuousCornerSmoothing(size: CGSize, topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat, limit: CGFloat) -> CGFloat {
    let sides = continuousCornerSideSmoothing(size: size, topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight, limit: limit)
    return min(sides.horizontal, sides.vertical)
}

public func continuousCornerSideSmoothing(size: CGSize, topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat, limit: CGFloat) -> (horizontal: CGFloat, vertical: CGFloat) {
    func allowed(_ length: CGFloat, _ first: CGFloat, _ second: CGFloat) -> CGFloat {
        let radii = first + second
        guard radii > 0 else {
            return limit
        }
        return length / radii - 1.0
    }
    let horizontal = min(allowed(size.width, topLeft, topRight), allowed(size.width, bottomLeft, bottomRight))
    let vertical = min(allowed(size.height, topLeft, bottomLeft), allowed(size.height, topRight, bottomRight))
    return (max(0.0, min(limit, horizontal)), max(0.0, min(limit, vertical)))
}

public extension CGMutablePath {
    func addContinuousCorner(corner: CGPoint, incoming u: CGPoint, outgoing v: CGPoint, radius: CGFloat, smoothing: CGFloat) {
        addContinuousCorner(corner: corner, incoming: u, outgoing: v, radius: radius, incomingSmoothing: smoothing, outgoingSmoothing: smoothing)
    }

    func addContinuousCorner(corner: CGPoint, incoming u: CGPoint, outgoing v: CGPoint, radius: CGFloat, incomingSmoothing: CGFloat, outgoingSmoothing: CGFloat) {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            return CGPoint(x: corner.x + u.x * x + v.x * y, y: corner.y + u.y * x + v.y * y)
        }
        guard radius > 0 else {
            self.addLine(to: corner)
            return
        }
        let incomingAngle = 45.0 * incomingSmoothing * .pi / 180.0
        let outgoingAngle = 45.0 * outgoingSmoothing * .pi / 180.0
        let incomingLength = (1.0 + incomingSmoothing) * radius
        let outgoingLength = (1.0 + outgoingSmoothing) * radius
        let incomingHandle = radius * tan(incomingAngle / 2.0) * cos(incomingAngle)
        let outgoingHandle = radius * tan(outgoingAngle / 2.0) * cos(outgoingAngle)
        let arcStart = CGPoint(x: radius - radius * sin(incomingAngle), y: radius - radius * cos(incomingAngle))
        let arcEnd = CGPoint(x: radius - radius * cos(outgoingAngle), y: radius - radius * sin(outgoingAngle))
        let incomingStep = (incomingLength - arcStart.x - incomingHandle) / 3.0
        let outgoingStep = (outgoingLength - arcEnd.y - outgoingHandle) / 3.0
        let halfArc = (.pi / 2.0 - incomingAngle - outgoingAngle) / 2.0
        let middle = incomingAngle + halfArc
        let tangentCross = CGPoint(x: radius - radius / cos(halfArc) * sin(middle), y: radius - radius / cos(halfArc) * cos(middle))

        self.addLine(to: point(incomingLength, 0.0))
        self.addCurve(to: point(arcStart.x, arcStart.y), control1: point(incomingLength - 2.0 * incomingStep, 0.0), control2: point(arcStart.x + incomingHandle, 0.0))
        self.addArc(tangent1End: point(tangentCross.x, tangentCross.y), tangent2End: point(arcEnd.x, arcEnd.y), radius: radius)
        self.addCurve(to: point(0.0, outgoingLength), control1: point(0.0, arcEnd.y + outgoingHandle), control2: point(0.0, outgoingLength - 2.0 * outgoingStep))
    }
}

public extension CGPath {
    static func continuousRoundedRect(_ rect: CGRect, topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat, smoothing: CGFloat) -> CGPath {
        return continuousRoundedRect(rect, topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight, horizontalSmoothing: smoothing, verticalSmoothing: smoothing)
    }

    static func continuousRoundedRect(_ rect: CGRect, topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat, horizontalSmoothing h: CGFloat, verticalSmoothing v: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let minX = rect.minX, minY = rect.minY, maxX = rect.maxX, maxY = rect.maxY
        path.move(to: CGPoint(x: maxX - (1.0 + h) * topRight, y: minY))
        path.addContinuousCorner(corner: CGPoint(x: maxX, y: minY), incoming: CGPoint(x: -1.0, y: 0.0), outgoing: CGPoint(x: 0.0, y: 1.0), radius: topRight, incomingSmoothing: h, outgoingSmoothing: v)
        path.addContinuousCorner(corner: CGPoint(x: maxX, y: maxY), incoming: CGPoint(x: 0.0, y: -1.0), outgoing: CGPoint(x: -1.0, y: 0.0), radius: bottomRight, incomingSmoothing: v, outgoingSmoothing: h)
        path.addContinuousCorner(corner: CGPoint(x: minX, y: maxY), incoming: CGPoint(x: 1.0, y: 0.0), outgoing: CGPoint(x: 0.0, y: -1.0), radius: bottomLeft, incomingSmoothing: h, outgoingSmoothing: v)
        path.addContinuousCorner(corner: CGPoint(x: minX, y: minY), incoming: CGPoint(x: 0.0, y: 1.0), outgoing: CGPoint(x: 1.0, y: 0.0), radius: topLeft, incomingSmoothing: v, outgoingSmoothing: h)
        path.closeSubpath()
        return path
    }
}
