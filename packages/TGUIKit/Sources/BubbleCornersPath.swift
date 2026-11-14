import Cocoa

public extension CGPath {
    static func bubbleCorners(size: CGSize, flags: LayoutPositionFlags) -> CGPath {
        let path = CGMutablePath()
        
        let minx:CGFloat = 0, midx = size.width/2.0, maxx = size.width
        let miny:CGFloat = 0, midy = size.height/2.0, maxy = size.height
        
        path.move(to: NSMakePoint(minx, midy))
        
        var topLeftRadius: CGFloat = .cornerRadius
        var bottomLeftRadius: CGFloat = .cornerRadius
        var topRightRadius: CGFloat = .cornerRadius
        var bottomRightRadius: CGFloat = .cornerRadius
        
        
        if flags.contains(.top) && flags.contains(.left) {
            bottomLeftRadius = .cornerRadius * 3 + 2
        }
        if flags.contains(.top) && flags.contains(.right) {
            bottomRightRadius = .cornerRadius * 3 + 2
        }
        if flags.contains(.bottom) && flags.contains(.left) {
            topLeftRadius = .cornerRadius * 3 + 2
        }
        if flags.contains(.bottom) && flags.contains(.right) {
            topRightRadius = .cornerRadius * 3 + 2
        }
        
        path.addArc(tangent1End: NSMakePoint(minx, miny), tangent2End: NSMakePoint(midx, miny), radius: bottomLeftRadius)
        path.addArc(tangent1End: NSMakePoint(maxx, miny), tangent2End: NSMakePoint(maxx, midy), radius: bottomRightRadius)
        path.addArc(tangent1End: NSMakePoint(maxx, maxy), tangent2End: NSMakePoint(midx, maxy), radius: topRightRadius)
        path.addArc(tangent1End: NSMakePoint(minx, maxy), tangent2End: NSMakePoint(minx, midy), radius: topLeftRadius)

        return path
    }

    static func bubbleCorners(size: CGSize, corners: ImageCorners) -> CGPath {
        if corners.smoothing > 0 {
            let topLeft = corners.topLeft.corner, topRight = corners.topRight.corner
            let bottomLeft = corners.bottomLeft.corner, bottomRight = corners.bottomRight.corner
            let smoothing = continuousCornerSmoothing(size: size, topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight, limit: corners.smoothing)
            return CGPath.continuousRoundedRect(CGRect(origin: .zero, size: size), topLeft: topLeft, topRight: topRight, bottomLeft: bottomLeft, bottomRight: bottomRight, smoothing: smoothing)
        }
        let path = CGMutablePath()

        let minx: CGFloat = 0, midx = size.width / 2.0, maxx = size.width
        let miny: CGFloat = 0, midy = size.height / 2.0, maxy = size.height

        path.move(to: NSMakePoint(minx, midy))
        path.addArc(tangent1End: NSMakePoint(minx, miny), tangent2End: NSMakePoint(midx, miny), radius: corners.topLeft.corner)
        path.addArc(tangent1End: NSMakePoint(maxx, miny), tangent2End: NSMakePoint(maxx, midy), radius: corners.topRight.corner)
        path.addArc(tangent1End: NSMakePoint(maxx, maxy), tangent2End: NSMakePoint(midx, maxy), radius: corners.bottomRight.corner)
        path.addArc(tangent1End: NSMakePoint(minx, maxy), tangent2End: NSMakePoint(minx, midy), radius: corners.bottomLeft.corner)
        path.closeSubpath()
        return path
    }
}
