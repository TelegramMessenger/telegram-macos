import Cocoa
import TGUIKit
import TelegramMedia

private enum Corner: Hashable {
    case TopLeft(Int), TopRight(Int), BottomLeft(Int), BottomRight(Int)
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case let .TopLeft(radius):
            hasher.combine(radius | (1 << 24))
        case let .TopRight(radius):
            hasher.combine(radius | (2 << 24))
        case let .BottomLeft(radius):
            hasher.combine(radius | (3 << 24))
        case let .BottomRight(radius):
            hasher.combine(radius | (2 << 24))
        }
    }
    
    var radius: Int {
        switch self {
        case let .TopLeft(radius):
            return radius
        case let .TopRight(radius):
            return radius
        case let .BottomLeft(radius):
            return radius
        case let .BottomRight(radius):
            return radius
        }
    }
}



private enum Tail: Hashable {
    case BottomLeft(Int)
    case BottomRight(Int)
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case let .BottomLeft(radius):
            hasher.combine(radius | (1 << 24))
        case let .BottomRight(radius):
            hasher.combine(radius | (2 << 24))
        }
    }
    
    var radius: Int {
        switch self {
        case let .BottomLeft(radius):
            return radius
        case let .BottomRight(radius):
            return radius
        }
    }
}

private func ==(lhs: Tail, rhs: Tail) -> Bool {
    switch lhs {
    case let .BottomLeft(lhsRadius):
        switch rhs {
        case let .BottomLeft(rhsRadius) where rhsRadius == lhsRadius:
            return true
        default:
            return false
        }
    case let .BottomRight(lhsRadius):
        switch rhs {
        case let .BottomRight(rhsRadius) where rhsRadius == lhsRadius:
            return true
        default:
            return false
        }
    }
}


private func cornerContext(_ corner: Corner, scale:CGFloat) -> DrawingContext {
    
    let context = DrawingContext(size: CGSize(width: CGFloat(corner.radius), height: CGFloat(corner.radius)), scale: scale, clear: true)
    
    context.withContext { c in
        c.setBlendMode(.copy)
        c.setFillColor(NSColor.black.cgColor)
        let rect: CGRect
        switch corner {
        case let .TopLeft(radius):
            rect = CGRect(origin: CGPoint(x: 0.0, y: -CGFloat(radius)), size: CGSize(width: CGFloat(radius << 1), height: CGFloat(radius << 1)))
        case let .TopRight(radius):
            rect = CGRect(origin: CGPoint(x: -CGFloat(radius), y: -CGFloat(radius)), size: CGSize(width: CGFloat(radius << 1), height: CGFloat(radius << 1)))
        case let .BottomLeft(radius):
            rect = CGRect(origin: CGPoint(), size: CGSize(width: CGFloat(radius << 1), height: CGFloat(radius << 1)))
        case let .BottomRight(radius):
            rect = CGRect(origin: CGPoint(x: -CGFloat(radius), y: 0.0), size: CGSize(width: CGFloat(radius << 1), height: CGFloat(radius << 1)))
        }
        c.fillEllipse(in: rect)
    }
    return context
}

private func tailContext(_ tail: Tail, scale:CGFloat) -> DrawingContext {
    let cached: DrawingContext? = nil

    
    if let cached = cached {
        return cached
    } else {
        let context = DrawingContext(size: CGSize(width: CGFloat(tail.radius) + 3.0, height: CGFloat(tail.radius)), scale:scale, clear: true)
        
        context.withContext { c in
            c.setBlendMode(.copy)
            c.setFillColor(NSColor.black.cgColor)
            let rect: CGRect
            switch tail {
            case let .BottomLeft(radius):
                rect = CGRect(origin: CGPoint(x: 3.0, y: -CGFloat(radius)), size: CGSize(width: CGFloat(radius << 1), height: CGFloat(radius << 1)))
                
                c.move(to: CGPoint(x: 3.0, y: 0.0))
                c.addLine(to: CGPoint(x: 3.0, y: 8.7))
                c.addLine(to: CGPoint(x: 2.0, y: 11.7))
                c.addLine(to: CGPoint(x: 1.5, y: 12.7))
                c.addLine(to: CGPoint(x: 0.8, y: 13.7))
                c.addLine(to: CGPoint(x: 0.2, y: 14.4))
                c.addLine(to: CGPoint(x: 3.5, y: 13.8))
                c.addLine(to: CGPoint(x: 5.0, y: 13.2))
                c.addLine(to: CGPoint(x: 3.0 + CGFloat(radius) - 9.5, y: 11.5))
                c.closePath()
                c.fillPath()
            case let .BottomRight(radius):
                rect = CGRect(origin: CGPoint(x: -CGFloat(radius) + 3.0, y: -CGFloat(radius)), size: CGSize(width: CGFloat(radius << 1), height: CGFloat(radius << 1)))
                
                /*CGContextMoveToPoint(c, 3.0, 0.0)
                 CGContextAddLineToPoint(c, 3.0, 8.7)
                 CGContextAddLineToPoint(c, 2.0, 11.7)
                 CGContextAddLineToPoint(c, 1.5, 12.7)
                 CGContextAddLineToPoint(c, 0.8, 13.7)
                 CGContextAddLineToPoint(c, 0.2, 14.4)
                 CGContextAddLineToPoint(c, 3.5, 13.8)
                 CGContextAddLineToPoint(c, 5.0, 13.2)
                 CGContextAddLineToPoint(c, 3.0 + CGFloat(radius) - 9.5, 11.5)
                 CGContextClosePath(c)
                 CGContextFillPath(c)*/
            }
            c.fillEllipse(in: rect)
        }
        
        return context
    }
}



private enum ContinuousCornerPosition {
    case topLeft, topRight, bottomLeft, bottomRight
}

private func continuousCornerContext(_ position: ContinuousCornerPosition, radius: CGFloat, smoothing: CGFloat, scale: CGFloat) -> DrawingContext {
    let extent = ((1.0 + smoothing) * radius).rounded(.up)
    let context = DrawingContext(size: CGSize(width: extent, height: extent), scale: scale, clear: true)
    context.withContext { c in
        c.setBlendMode(.copy)
        c.setFillColor(NSColor.black.cgColor)
        let origin: CGPoint
        switch position {
        case .topLeft:
            origin = CGPoint(x: 0.0, y: -extent)
        case .topRight:
            origin = CGPoint(x: -extent, y: -extent)
        case .bottomLeft:
            origin = CGPoint()
        case .bottomRight:
            origin = CGPoint(x: -extent, y: 0.0)
        }
        c.addPath(CGPath.continuousRoundedRect(CGRect(origin: origin, size: CGSize(width: extent * 2.0, height: extent * 2.0)), topLeft: radius, topRight: radius, bottomLeft: radius, bottomRight: radius, smoothing: smoothing))
        c.fillPath()
    }
    return context
}

private func addContinuousCorners(_ context: DrawingContext, corners: ImageCorners, drawingRect: CGRect, scale: CGFloat) {
    let topLeft = corners.topLeft.corner, topRight = corners.topRight.corner
    let bottomLeft = corners.bottomLeft.corner, bottomRight = corners.bottomRight.corner
    let smoothing = continuousCornerSmoothing(size: drawingRect.size, topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight, limit: corners.smoothing)
    func extent(_ radius: CGFloat) -> CGFloat {
        return ((1.0 + smoothing) * radius).rounded(.up)
    }
    if topLeft > CGFloat.ulpOfOne {
        context.blt(continuousCornerContext(.topLeft, radius: topLeft, smoothing: smoothing, scale: scale), at: CGPoint(x: drawingRect.minX, y: drawingRect.minY))
    }
    if topRight > CGFloat.ulpOfOne {
        context.blt(continuousCornerContext(.topRight, radius: topRight, smoothing: smoothing, scale: scale), at: CGPoint(x: drawingRect.maxX - extent(topRight), y: drawingRect.minY))
    }
    if bottomLeft > CGFloat.ulpOfOne {
        context.blt(continuousCornerContext(.bottomLeft, radius: bottomLeft, smoothing: smoothing, scale: scale), at: CGPoint(x: drawingRect.minX, y: drawingRect.maxY - extent(bottomLeft)))
    }
    if bottomRight > CGFloat.ulpOfOne {
        context.blt(continuousCornerContext(.bottomRight, radius: bottomRight, smoothing: smoothing, scale: scale), at: CGPoint(x: drawingRect.maxX - extent(bottomRight), y: drawingRect.maxY - extent(bottomRight)))
    }
}

public func addCorners(_ context: DrawingContext, arguments: TransformImageArguments, scale:CGFloat) {
    let corners = arguments.corners
    let drawingRect = arguments.drawingRect
    
    if corners.smoothing > 0 {
        addContinuousCorners(context, corners: corners, drawingRect: drawingRect, scale: scale)
        return
    }
    
    if case let .Corner(radius) = corners.topLeft, radius > CGFloat.ulpOfOne {
        let corner = cornerContext(.TopLeft(Int(radius)), scale:scale)
        context.blt(corner, at: CGPoint(x: drawingRect.minX, y: drawingRect.minY))
    }
    
    if case let .Corner(radius) = corners.topRight, radius > CGFloat.ulpOfOne {
        let corner = cornerContext(.TopRight(Int(radius)), scale:scale)
        context.blt(corner, at: CGPoint(x: drawingRect.maxX - radius, y: drawingRect.minY))
    }
    
    switch corners.bottomLeft {
    case let .Corner(radius):
        if radius > CGFloat.ulpOfOne {
            let corner = cornerContext(.BottomLeft(Int(radius)), scale:scale)
            context.blt(corner, at: CGPoint(x: drawingRect.minX, y: drawingRect.maxY - radius))
        }
    case let .Tail(radius):
        if radius > CGFloat.ulpOfOne {
            let tail = tailContext(.BottomLeft(Int(radius)), scale:scale)
            let color = context.colorAt(CGPoint(x: drawingRect.minX, y: drawingRect.maxY - 1.0))
            context.withContext { c in
                c.setFillColor(color.cgColor)
                c.fill(CGRect(x: 0.0, y: drawingRect.maxY - 6.0, width: 3.0, height: 6.0))
            }
            context.blt(tail, at: CGPoint(x: drawingRect.minX - 3.0, y: drawingRect.maxY - radius))
        }
        
    }
    
    switch corners.bottomRight {
    case let .Corner(radius):
        if radius > CGFloat.ulpOfOne {
            let corner = cornerContext(.BottomRight(Int(radius)), scale:scale)
            context.blt(corner, at: CGPoint(x: drawingRect.maxX - radius, y: drawingRect.maxY - radius))
        }
    case let .Tail(radius):
        if radius > CGFloat.ulpOfOne {
            let tail = tailContext(.BottomRight(Int(radius)), scale:scale)
            context.blt(tail, at: CGPoint(x: drawingRect.maxX - radius - 3.0, y: drawingRect.maxY - radius))
        }
    }
}
