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

private func drawMessageBubbleForm(_ context: CGContext, neighbors: MessageBubbleImageNeighbors, diameter: CGFloat) {
    let fixedMainDiameter = diameter
    let maxCornerRadius = messageBubbleMainRadius
    let corners = messageBubbleArguments(maxCornerRadius: maxCornerRadius, minCornerRadius: messageBubbleAuxiliaryRadius, incoming: false, neighbors: neighbors)
    let topLeftRadius = corners.topLeftRadius
    let topRightRadius = corners.topRightRadius
    let bottomLeftRadius = corners.bottomLeftRadius
    let bottomRightRadius = corners.bottomRightRadius

    let bottomEllipse = CGRect(origin: CGPoint(x: fixedMainDiameter - 9.0, y: fixedMainDiameter - 17.0), size: CGSize(width: 27.0, height: 17.0))
    let topEllipse = CGRect(origin: CGPoint(x: fixedMainDiameter, y: fixedMainDiameter - 19.0), size: CGSize(width: 23.0, height: 21.0))

    context.setFillColor(NSColor.black.cgColor)

    context.move(to: CGPoint(x: 0.0, y: topLeftRadius))
    context.addArc(tangent1End: CGPoint(x: 0.0, y: 0.0), tangent2End: CGPoint(x: topLeftRadius, y: 0.0), radius: topLeftRadius)
    context.addLine(to: CGPoint(x: fixedMainDiameter - topRightRadius, y: 0.0))
    context.addArc(tangent1End: CGPoint(x: fixedMainDiameter, y: 0.0), tangent2End: CGPoint(x: fixedMainDiameter, y: topRightRadius), radius: topRightRadius)
    context.addLine(to: CGPoint(x: fixedMainDiameter, y: fixedMainDiameter - bottomRightRadius))
    context.addArc(tangent1End: CGPoint(x: fixedMainDiameter, y: fixedMainDiameter), tangent2End: CGPoint(x: fixedMainDiameter - bottomRightRadius, y: fixedMainDiameter), radius: bottomRightRadius)
    context.addLine(to: CGPoint(x: bottomLeftRadius, y: fixedMainDiameter))
    context.addArc(tangent1End: CGPoint(x: 0.0, y: fixedMainDiameter), tangent2End: CGPoint(x: 0.0, y: fixedMainDiameter - bottomLeftRadius), radius: bottomLeftRadius)
    context.addLine(to: CGPoint(x: 0.0, y: topLeftRadius))
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
        context.fill(CGRect(origin: CGPoint(x: fixedMainDiameter / 2.0, y: floor(fixedMainDiameter / 2.0)), size: CGSize(width: fixedMainDiameter / 2.0, height: ceil(bottomEllipse.midY) - floor(fixedMainDiameter / 2.0))))
        context.setFillColor(NSColor.clear.cgColor)
        context.setBlendMode(.copy)
        context.fillEllipse(in: topEllipse)
        context.setBlendMode(.normal)
    }
}

func messageBubbleFormImage(incoming: Bool, neighbors: MessageBubbleImageNeighbors, diameter: CGFloat = messageBubbleDiameter, scale: CGFloat = System.backingScale) -> CGImage {
    let size = CGSize(width: diameter + messageBubbleTailWidth, height: diameter)
    return generateImage(size, scale: scale, rotatedContext: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        if incoming {
            context.translateBy(x: size.width, y: 0.0)
            context.scaleBy(x: -1.0, y: 1.0)
        }
        drawMessageBubbleForm(context, neighbors: neighbors, diameter: diameter)
    })!
}

private struct MessageBubbleImageKey: Hashable {
    let incoming: Bool
    let neighbors: MessageBubbleImageNeighbors
    let fillColor: UInt32
    let strokeColor: UInt32
    let scale: CGFloat
}

private let messageBubbleImageLock = NSLock()
private var messageBubbleImageCache: [MessageBubbleImageKey: (CGImage, NSEdgeInsets)] = [:]
// Each theme's bubble colors add a handful of entries; without a bound the cache grew for the whole
// process lifetime across theme switches. A switch keeps the active theme's working set well under this.
private let messageBubbleImageCacheLimit = 128

public func clearMessageBubbleImageCache() {
    messageBubbleImageLock.lock()
    messageBubbleImageCache.removeAll(keepingCapacity: true)
    messageBubbleImageLock.unlock()
}

private let messageBubbleMaskFillArgb = NSColor.black.argb
private let messageBubbleMaskStrokeArgb = NSColor.clear.argb

public func messageBubbleMaskImage(incoming: Bool, neighbors: MessageBubbleImageNeighbors) -> (CGImage, NSEdgeInsets) {
    return messageBubbleImageModern(incoming: incoming, fillColor: .black, fillArgb: messageBubbleMaskFillArgb, strokeColor: .clear, strokeArgb: messageBubbleMaskStrokeArgb, neighbors: neighbors)
}

public func messageBubbleImageModern(incoming: Bool, fillColor: NSColor, strokeColor: NSColor, neighbors: MessageBubbleImageNeighbors) -> (CGImage, NSEdgeInsets) {
    return messageBubbleImageModern(incoming: incoming, fillColor: fillColor, fillArgb: fillColor.argb, strokeColor: strokeColor, strokeArgb: strokeColor.argb, neighbors: neighbors)
}

private func messageBubbleImageModern(incoming: Bool, fillColor: NSColor, fillArgb: UInt32, strokeColor: NSColor, strokeArgb: UInt32, neighbors: MessageBubbleImageNeighbors) -> (CGImage, NSEdgeInsets) {
    let scale = System.backingScale
    let key = MessageBubbleImageKey(incoming: incoming, neighbors: neighbors, fillColor: fillArgb, strokeColor: strokeArgb, scale: scale)
    messageBubbleImageLock.lock()
    if let cached = messageBubbleImageCache[key] {
        messageBubbleImageLock.unlock()
        return cached
    }
    messageBubbleImageLock.unlock()

    let form = messageBubbleFormImage(incoming: incoming, neighbors: neighbors, scale: scale)
    let size = CGSize(width: messageBubbleDiameter + messageBubbleTailWidth, height: messageBubbleDiameter)
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

    let stretchPoint = Int(messageBubbleDiameter / 2.0)
    let leftCapWidth = CGFloat(incoming ? Int(size.width) - stretchPoint - 1 : stretchPoint)
    let topCapHeight = CGFloat(stretchPoint)
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
