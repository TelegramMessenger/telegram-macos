import Cocoa
import TGUIKit

public enum MessageBubbleImageNeighbors: Hashable {
    case none
    case top(side: Bool)
    case bottom
    case both
    case side
    case extracted
}

let messageBubbleMainRadius: CGFloat = 16.0
let messageBubbleAuxiliaryRadius: CGFloat = 8.0
let messageBubbleTailWidth: CGFloat = 6.0
let messageBubbleDiameter: CGFloat = 32.0
let messageBubbleContinuousDiameter: CGFloat = 52.0
private let messageBubbleContinuousSmoothing: CGFloat = 0.6

private let minRadiusForFullTailCorner: CGFloat = 14.0

func messageBubbleArguments(maxCornerRadius: CGFloat, minCornerRadius: CGFloat, incoming: Bool, neighbors: MessageBubbleImageNeighbors) -> (topLeftRadius: CGFloat, topRightRadius: CGFloat, bottomLeftRadius: CGFloat, bottomRightRadius: CGFloat, drawTail: Bool) {
    var topLeftRadius: CGFloat
    var topRightRadius: CGFloat
    var bottomLeftRadius: CGFloat
    var bottomRightRadius: CGFloat
    var drawTail: Bool

    switch neighbors {
    case .none:
        topLeftRadius = maxCornerRadius
        topRightRadius = maxCornerRadius
        bottomLeftRadius = maxCornerRadius
        bottomRightRadius = maxCornerRadius
        drawTail = true
    case .both:
        topLeftRadius = maxCornerRadius
        topRightRadius = minCornerRadius
        bottomLeftRadius = maxCornerRadius
        bottomRightRadius = minCornerRadius
        drawTail = false
    case .bottom:
        topLeftRadius = maxCornerRadius
        topRightRadius = minCornerRadius
        bottomLeftRadius = maxCornerRadius
        bottomRightRadius = maxCornerRadius
        drawTail = true
    case .side:
        topLeftRadius = maxCornerRadius
        topRightRadius = maxCornerRadius
        bottomLeftRadius = minCornerRadius
        bottomRightRadius = minCornerRadius
        drawTail = false
    case let .top(side):
        topLeftRadius = maxCornerRadius
        topRightRadius = maxCornerRadius
        bottomLeftRadius = side ? minCornerRadius : maxCornerRadius
        bottomRightRadius = minCornerRadius
        drawTail = false
    case .extracted:
        topLeftRadius = maxCornerRadius
        topRightRadius = maxCornerRadius
        bottomLeftRadius = maxCornerRadius
        bottomRightRadius = maxCornerRadius
        drawTail = false
    }

    if incoming {
        var tmp = topRightRadius
        topRightRadius = topLeftRadius
        topLeftRadius = tmp

        tmp = bottomRightRadius
        bottomRightRadius = bottomLeftRadius
        bottomLeftRadius = tmp
    }

    return (topLeftRadius, topRightRadius, bottomLeftRadius, bottomRightRadius, drawTail)
}

public func messageBubbleCorners(incoming: Bool, neighbors: MessageBubbleImageNeighbors, inset: CGFloat) -> ImageCorners {
    let radii = messageBubbleArguments(maxCornerRadius: messageBubbleMainRadius, minCornerRadius: messageBubbleAuxiliaryRadius, incoming: incoming, neighbors: neighbors)
    return ImageCorners(
        topLeft: .Corner(max(0, radii.topLeftRadius - inset)),
        topRight: .Corner(max(0, radii.topRightRadius - inset)),
        bottomLeft: .Corner(max(0, radii.bottomLeftRadius - inset)),
        bottomRight: .Corner(max(0, radii.bottomRightRadius - inset))
    )
}

private func addContinuousCorner(_ context: CGContext, corner: CGPoint, incoming u: CGPoint, outgoing v: CGPoint, radius: CGFloat, smoothing: CGFloat) {
    let p = (1.0 + smoothing) * radius
    let arcMeasure = 90.0 * (1.0 - smoothing)
    let arcLength = sin(arcMeasure / 2.0 * .pi / 180.0) * radius * 2.0.squareRoot()
    let alpha = (90.0 - arcMeasure) / 2.0
    let beta = 45.0 * smoothing * .pi / 180.0
    let c = radius * tan(alpha / 2.0 * .pi / 180.0) * cos(beta)
    let d = c * tan(beta)
    let b = (p - arcLength - c - d) / 3.0
    let a = 2.0 * b

    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        return CGPoint(x: corner.x + u.x * x + v.x * y, y: corner.y + u.y * x + v.y * y)
    }

    let arcStart = CGPoint(x: p - a - b - c, y: d)
    let arcEnd = CGPoint(x: arcStart.x - arcLength, y: d + arcLength)
    let tangentLength = radius * tan(arcMeasure / 2.0 * .pi / 180.0)
    let tangentCross = CGPoint(x: arcStart.x - tangentLength * cos(beta), y: arcStart.y + tangentLength * sin(beta))

    context.addLine(to: point(p, 0.0))
    context.addCurve(to: point(arcStart.x, arcStart.y), control1: point(p - a, 0.0), control2: point(p - a - b, 0.0))
    context.addArc(tangent1End: point(tangentCross.x, tangentCross.y), tangent2End: point(arcEnd.x, arcEnd.y), radius: radius)
    context.addCurve(to: point(0.0, p), control1: point(arcEnd.x - d, arcEnd.y + c), control2: point(arcEnd.x - d, arcEnd.y + b + c))
}

private func addContinuousBubblePath(_ context: CGContext, size: CGSize, topLeftRadius: CGFloat, topRightRadius: CGFloat, bottomLeftRadius: CGFloat, bottomRightRadius: CGFloat, drawTail: Bool, smoothing: CGFloat) {
    let width = size.width
    let height = size.height
    context.move(to: CGPoint(x: width - (1.0 + smoothing) * topRightRadius, y: 0.0))
    addContinuousCorner(context, corner: CGPoint(x: width, y: 0.0), incoming: CGPoint(x: -1.0, y: 0.0), outgoing: CGPoint(x: 0.0, y: 1.0), radius: topRightRadius, smoothing: smoothing)
    if drawTail {
        context.addLine(to: CGPoint(x: width, y: height - bottomRightRadius))
        context.addArc(tangent1End: CGPoint(x: width, y: height), tangent2End: CGPoint(x: width - bottomRightRadius, y: height), radius: bottomRightRadius)
    } else {
        addContinuousCorner(context, corner: CGPoint(x: width, y: height), incoming: CGPoint(x: 0.0, y: -1.0), outgoing: CGPoint(x: -1.0, y: 0.0), radius: bottomRightRadius, smoothing: smoothing)
    }
    addContinuousCorner(context, corner: CGPoint(x: 0.0, y: height), incoming: CGPoint(x: 1.0, y: 0.0), outgoing: CGPoint(x: 0.0, y: -1.0), radius: bottomLeftRadius, smoothing: smoothing)
    addContinuousCorner(context, corner: CGPoint(x: 0.0, y: 0.0), incoming: CGPoint(x: 0.0, y: 1.0), outgoing: CGPoint(x: 1.0, y: 0.0), radius: topLeftRadius, smoothing: smoothing)
    context.closePath()
}

private struct MessageBubbleFormGeometry: Hashable {
    let width: Int
    let height: Int
    let smoothing: CGFloat

    static let legacy = MessageBubbleFormGeometry(width: Int(messageBubbleDiameter), height: Int(messageBubbleDiameter), smoothing: 0.0)

    static func fitting(_ bubbleSize: CGSize, neighbors: MessageBubbleImageNeighbors) -> MessageBubbleFormGeometry {
        let limit = messageBubbleContinuousDiameter
        let width = min(limit, max(messageBubbleDiameter, (bubbleSize.width - messageBubbleTailWidth).rounded()))
        let height = min(limit, max(messageBubbleDiameter, bubbleSize.height.rounded()))
        let corners = messageBubbleArguments(maxCornerRadius: messageBubbleMainRadius, minCornerRadius: messageBubbleAuxiliaryRadius, incoming: false, neighbors: neighbors)
        let tailRadius = corners.drawTail ? corners.bottomRightRadius : 0.0
        let smoothRight = corners.drawTail ? 0.0 : corners.bottomRightRadius
        func allowed(_ length: CGFloat, smooth: CGFloat, fixed: CGFloat) -> CGFloat {
            guard smooth > 0 else {
                return messageBubbleContinuousSmoothing
            }
            return (length - fixed) / smooth - 1.0
        }
        let smoothing = min(
            allowed(height, smooth: corners.topLeftRadius + corners.bottomLeftRadius, fixed: 0.0),
            allowed(height, smooth: corners.topRightRadius + smoothRight, fixed: tailRadius),
            allowed(width, smooth: corners.topLeftRadius + corners.topRightRadius, fixed: 0.0),
            allowed(width, smooth: corners.bottomLeftRadius + smoothRight, fixed: tailRadius)
        )
        return MessageBubbleFormGeometry(width: Int(width), height: Int(height), smoothing: (max(0.0, min(messageBubbleContinuousSmoothing, smoothing)) * 100.0).rounded(.down) / 100.0)
    }
}

private func drawMessageBubbleForm(_ context: CGContext, neighbors: MessageBubbleImageNeighbors, geometry: MessageBubbleFormGeometry) {
    let width = CGFloat(geometry.width)
    let height = CGFloat(geometry.height)
    let maxCornerRadius = messageBubbleMainRadius
    let corners = messageBubbleArguments(maxCornerRadius: maxCornerRadius, minCornerRadius: messageBubbleAuxiliaryRadius, incoming: false, neighbors: neighbors)
    let topLeftRadius = corners.topLeftRadius
    let topRightRadius = corners.topRightRadius
    let bottomLeftRadius = corners.bottomLeftRadius
    let bottomRightRadius = corners.bottomRightRadius

    let bottomEllipse = CGRect(origin: CGPoint(x: width - 9.0, y: height - 17.0), size: CGSize(width: 27.0, height: 17.0))
    let topEllipse = CGRect(origin: CGPoint(x: width, y: height - 19.0), size: CGSize(width: 23.0, height: 21.0))

    context.setFillColor(NSColor.black.cgColor)

    if geometry.smoothing > 0 {
        addContinuousBubblePath(context, size: CGSize(width: width, height: height), topLeftRadius: topLeftRadius, topRightRadius: topRightRadius, bottomLeftRadius: bottomLeftRadius, bottomRightRadius: bottomRightRadius, drawTail: corners.drawTail, smoothing: geometry.smoothing)
    } else {
        context.move(to: CGPoint(x: 0.0, y: topLeftRadius))
        context.addArc(tangent1End: CGPoint(x: 0.0, y: 0.0), tangent2End: CGPoint(x: topLeftRadius, y: 0.0), radius: topLeftRadius)
        context.addLine(to: CGPoint(x: width - topRightRadius, y: 0.0))
        context.addArc(tangent1End: CGPoint(x: width, y: 0.0), tangent2End: CGPoint(x: width, y: topRightRadius), radius: topRightRadius)
        context.addLine(to: CGPoint(x: width, y: height - bottomRightRadius))
        context.addArc(tangent1End: CGPoint(x: width, y: height), tangent2End: CGPoint(x: width - bottomRightRadius, y: height), radius: bottomRightRadius)
        context.addLine(to: CGPoint(x: bottomLeftRadius, y: height))
        context.addArc(tangent1End: CGPoint(x: 0.0, y: height), tangent2End: CGPoint(x: 0.0, y: height - bottomLeftRadius), radius: bottomLeftRadius)
        context.addLine(to: CGPoint(x: 0.0, y: topLeftRadius))
    }
    context.fillPath()

    if corners.drawTail {
        if maxCornerRadius >= minRadiusForFullTailCorner {
            context.move(to: CGPoint(x: bottomEllipse.minX, y: bottomEllipse.midY))
            context.addQuadCurve(to: CGPoint(x: bottomEllipse.midX, y: bottomEllipse.maxY), control: CGPoint(x: bottomEllipse.minX, y: bottomEllipse.maxY))
            context.addQuadCurve(to: CGPoint(x: bottomEllipse.maxX, y: bottomEllipse.midY), control: CGPoint(x: bottomEllipse.maxX, y: bottomEllipse.maxY))
            context.fillPath()
        } else {
            context.fill(CGRect(origin: CGPoint(x: bottomEllipse.minX - 2.0, y: bottomEllipse.midY), size: CGSize(width: bottomEllipse.width + 2.0, height: bottomEllipse.height / 2.0)))
        }
        context.fill(CGRect(origin: CGPoint(x: width - bottomRightRadius, y: floor(height - bottomRightRadius)), size: CGSize(width: bottomRightRadius, height: ceil(bottomEllipse.midY) - floor(height - bottomRightRadius))))
        context.setFillColor(NSColor.clear.cgColor)
        context.setBlendMode(.copy)
        context.fillEllipse(in: topEllipse)
        context.setBlendMode(.normal)
    }
}

private func messageBubbleFormImage(incoming: Bool, neighbors: MessageBubbleImageNeighbors, geometry: MessageBubbleFormGeometry, scale: CGFloat) -> CGImage {
    let size = CGSize(width: CGFloat(geometry.width) + messageBubbleTailWidth, height: CGFloat(geometry.height))
    return generateImage(size, scale: scale, rotatedContext: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        if incoming {
            context.translateBy(x: size.width, y: 0.0)
            context.scaleBy(x: -1.0, y: 1.0)
        }
        drawMessageBubbleForm(context, neighbors: neighbors, geometry: geometry)
    })!
}

private struct MessageBubbleImageKey: Hashable {
    let incoming: Bool
    let geometry: MessageBubbleFormGeometry
    let neighbors: MessageBubbleImageNeighbors
    let fillColor: UInt32
    let strokeColor: UInt32
    let scale: CGFloat
}

private let messageBubbleImageLock = NSLock()
private var messageBubbleImageCache: [MessageBubbleImageKey: (CGImage, NSEdgeInsets)] = [:]
// Each theme's bubble colors add a handful of entries; without a bound the cache grew for the whole
// process lifetime across theme switches. A switch keeps the active theme's working set well under this.
private let messageBubbleImageCacheLimit = 512

public func clearMessageBubbleImageCache() {
    messageBubbleImageLock.lock()
    messageBubbleImageCache.removeAll(keepingCapacity: true)
    messageBubbleImageLock.unlock()
}

public func messageBubbleImageModern(incoming: Bool, fillColor: NSColor, strokeColor: NSColor, neighbors: MessageBubbleImageNeighbors, fitting bubbleSize: CGSize? = nil) -> (CGImage, NSEdgeInsets) {
    let scale = System.backingScale
    let geometry = bubbleSize.map { MessageBubbleFormGeometry.fitting($0, neighbors: neighbors) } ?? .legacy
    let key = MessageBubbleImageKey(incoming: incoming, geometry: geometry, neighbors: neighbors, fillColor: fillColor.argb, strokeColor: strokeColor.argb, scale: scale)
    messageBubbleImageLock.lock()
    if let cached = messageBubbleImageCache[key] {
        messageBubbleImageLock.unlock()
        return cached
    }
    messageBubbleImageLock.unlock()

    let form = messageBubbleFormImage(incoming: incoming, neighbors: neighbors, geometry: geometry, scale: scale)
    let size = CGSize(width: CGFloat(geometry.width) + messageBubbleTailWidth, height: CGFloat(geometry.height))
    let borderWidth = 1.0 / scale + 0.25

    let image = generateImage(size, contextGenerator: { size, context in
        let bounds = CGRect(origin: CGPoint(), size: size)
        context.clear(bounds)

        context.saveGState()
        context.clip(to: bounds, mask: form)
        context.setFillColor(fillColor.cgColor)
        context.fill(bounds)
        context.restoreGState()

        if strokeColor.alphaComponent > 0 {
            let band = generateImage(size, contextGenerator: { size, bandContext in
                let bounds = CGRect(origin: CGPoint(), size: size)
                bandContext.clear(bounds)
                bandContext.saveGState()
                bandContext.clip(to: bounds, mask: form)
                bandContext.setFillColor(NSColor.black.cgColor)
                bandContext.fill(bounds)
                bandContext.restoreGState()

                bandContext.saveGState()
                for step in 0 ..< 16 {
                    let angle = CGFloat(step) * .pi / 8.0
                    bandContext.clip(to: bounds.offsetBy(dx: cos(angle) * borderWidth, dy: sin(angle) * borderWidth), mask: form)
                }
                bandContext.setBlendMode(.copy)
                bandContext.setFillColor(NSColor.clear.cgColor)
                bandContext.fill(bounds)
                bandContext.restoreGState()
            }, scale: scale)!

            context.saveGState()
            context.clip(to: bounds, mask: band)
            context.setFillColor(strokeColor.cgColor)
            context.fill(bounds)
            context.restoreGState()
        }
    }, scale: scale)!

    let stretchPoint = geometry.width / 2
    let leftCapWidth = CGFloat(incoming ? Int(size.width) - stretchPoint - 1 : stretchPoint)
    let topCapHeight = CGFloat(geometry.height / 2)
    let rightCapWidth = size.width - leftCapWidth - 1.0
    let bottomCapHeight = size.height - topCapHeight - 1.0

    let result = (image, NSEdgeInsetsMake(topCapHeight, leftCapWidth, bottomCapHeight, rightCapWidth))

    messageBubbleImageLock.lock()
    if messageBubbleImageCache.count >= messageBubbleImageCacheLimit {
        messageBubbleImageCache.removeAll(keepingCapacity: true)
    }
    messageBubbleImageCache[key] = result
    messageBubbleImageLock.unlock()

    return result
}
