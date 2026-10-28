import Cocoa
import TGUIKit
import CoreImage

private let markerBrushImage: CGImage? = {
    return NSImage(resource: .iconEditImageMarkerBrush).cgImage(forProposedRect: nil, context: nil, hints: nil)
}()

func editImageCanvasBlurredImage(_ image: CGImage) -> CGImage? {
    let fitted = image.size.fitted(NSMakeSize(256, 256))
    let width = max(1, Int(fitted.width))
    let height = max(1, Int(fitted.height))
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    context.interpolationQuality = .medium
    context.setFillColor(NSColor.black.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let small = context.makeImage() else {
        return nil
    }
    let input = CIImage(cgImage: small)
    guard let filter = CIFilter(name: "CIGaussianBlur") else {
        return small
    }
    filter.setValue(input.clampedToExtent(), forKey: kCIInputImageKey)
    filter.setValue(8.0, forKey: kCIInputRadiusKey)
    guard let output = filter.outputImage?.cropped(to: input.extent) else {
        return small
    }
    let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    return ciContext.createCGImage(output, from: input.extent)
}

func editImageCanvasDrawUpright(_ image: CGImage, in rect: CGRect, context: CGContext) {
    context.saveGState()
    context.translateBy(x: 0, y: rect.minY + rect.maxY)
    context.scaleBy(x: 1, y: -1)
    context.draw(image, in: rect)
    context.restoreGState()
}

private func baseOffset(_ offset: CGSize, context: CGContext) -> CGSize {
    let t = context.ctm
    return CGSize(width: t.a * offset.width + t.c * offset.height, height: t.b * offset.width + t.d * offset.height)
}

private func baseScale(_ context: CGContext) -> CGFloat {
    let t = context.ctm
    return sqrt(t.a * t.a + t.b * t.b)
}

func editImageCanvasDensePoints(_ points: [CGPoint]) -> [CGPoint] {
    guard points.count > 2 else {
        return points
    }
    var result: [CGPoint] = [points[0]]
    var current = points[0]
    for i in 1 ..< points.count - 1 {
        let control = points[i]
        let end = CGPoint(x: (points[i].x + points[i + 1].x) / 2.0, y: (points[i].y + points[i + 1].y) / 2.0)
        let length = hypot(control.x - current.x, control.y - current.y) + hypot(end.x - control.x, end.y - control.y)
        let steps = max(2, min(48, Int(length / 2.0)))
        for step in 1 ... steps {
            let t = CGFloat(step) / CGFloat(steps)
            let x = (1 - t) * (1 - t) * current.x + 2 * (1 - t) * t * control.x + t * t * end.x
            let y = (1 - t) * (1 - t) * current.y + 2 * (1 - t) * t * control.y + t * t * end.y
            result.append(CGPoint(x: x, y: y))
        }
        current = end
    }
    result.append(points[points.count - 1])
    return result
}

func editImageCanvasSmoothPath(_ points: [CGPoint]) -> CGPath {
    let path = CGMutablePath()
    guard let first = points.first else {
        return path
    }
    path.move(to: first)
    if points.count == 1 {
        return path
    }
    if points.count == 2 {
        path.addLine(to: points[1])
        return path
    }
    for i in 1 ..< points.count - 1 {
        let mid = CGPoint(x: (points[i].x + points[i + 1].x) / 2.0, y: (points[i].y + points[i + 1].y) / 2.0)
        path.addQuadCurve(to: mid, control: points[i])
    }
    path.addLine(to: points[points.count - 1])
    return path
}

private func strokeShape(_ points: [CGPoint], lineWidth: CGFloat) -> CGPath {
    if points.count == 1, let point = points.first {
        return CGPath(ellipseIn: CGRect(x: point.x - lineWidth / 2.0, y: point.y - lineWidth / 2.0, width: lineWidth, height: lineWidth), transform: nil)
    }
    return editImageCanvasSmoothPath(points).copy(strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 0)
}

func editImageCanvasArrowHead(points: [CGPoint], lineWidth: CGFloat, canvasSize: CGSize) -> CGPath? {
    let dense = editImageCanvasDensePoints(points)
    guard dense.count > 4, let last = dense.last else {
        return nil
    }
    let longSide = max(canvasSize.width, canvasSize.height)
    let arrowLength = max(max(10.0, longSide * 0.02), lineWidth * 3.0)
    var origin: CGPoint?
    for point in dense.reversed().prefix(200) {
        if hypot(point.x - last.x, point.y - last.y) > arrowLength * 0.5 {
            origin = point
            break
        }
    }
    guard let origin = origin else {
        return nil
    }
    let angle = atan2(last.y - origin.y, last.x - origin.x) + .pi
    let path = CGMutablePath()
    path.move(to: CGPoint(x: last.x + arrowLength * cos(angle - 0.45), y: last.y + arrowLength * sin(angle - 0.45)))
    path.addLine(to: last)
    path.addLine(to: CGPoint(x: last.x + arrowLength * cos(angle + 0.45), y: last.y + arrowLength * sin(angle + 0.45)))
    return path
}

private func tintedBrush(_ brush: CGImage, color: EditImageCanvasColor) -> CGImage? {
    let width = brush.width
    let height = brush.height
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    let rect = CGRect(x: 0, y: 0, width: width, height: height)
    context.clip(to: rect, mask: brush)
    context.setFillColor(color.withAlpha(1.0).cgColor)
    context.fill(rect)
    return context.makeImage()
}

private func stampMarker(_ points: [CGPoint], lineWidth: CGFloat, color: EditImageCanvasColor, context: CGContext) {
    guard let brush = markerBrushImage, let tinted = tintedBrush(brush, color: color) else {
        context.addPath(strokeShape(points, lineWidth: lineWidth))
        context.setFillColor(color.withAlpha(color.alpha * 0.7).cgColor)
        context.fillPath()
        return
    }
    let step = max(1.0, lineWidth / 16.0)
    let alpha = min(1.0, color.alpha / max(1.0, lineWidth / step) * 5.5)
    var samples: [CGPoint] = []
    for point in editImageCanvasDensePoints(points) {
        if let last = samples.last, hypot(point.x - last.x, point.y - last.y) < step {
            continue
        }
        samples.append(point)
    }
    let rect = CGRect(x: -lineWidth / 2.0, y: -lineWidth / 2.0, width: lineWidth, height: lineWidth)
    context.setAlpha(alpha)
    for sample in samples {
        context.saveGState()
        context.translateBy(x: sample.x, y: sample.y)
        context.rotate(by: -0.55)
        context.draw(tinted, in: rect)
        context.restoreGState()
    }
    context.setAlpha(1.0)
}

private func drawNeon(_ points: [CGPoint], lineWidth: CGFloat, color: EditImageCanvasColor, imageSize: CGSize, context: CGContext) {
    let minDimension = min(imageSize.width, imageSize.height)
    let strokeWidth = minDimension * 0.008
    let shadowRadius = minDimension * 0.02
    let corePath = strokeShape(points, lineWidth: lineWidth)
    let glowPath = strokeShape(points, lineWidth: lineWidth * 2.0)
    var glowColor = color.withAlpha(1.0)
    var fillColor = EditImageCanvasColor.white
    if glowColor.lightness < 0.01 {
        fillColor = glowColor
        glowColor = EditImageCanvasColor(rgb: 0x440881)
    }
    let shift = max(imageSize.width, imageSize.height) * 2.0 + 1000.0
    context.saveGState()
    context.translateBy(x: -shift, y: -shift)
    context.addPath(glowPath)
    context.setFillColor(fillColor.cgColor)
    context.setStrokeColor(fillColor.cgColor)
    context.setLineWidth(strokeWidth * 0.5)
    context.setShadow(offset: baseOffset(CGSize(width: shift, height: shift), context: context), blur: shadowRadius * 1.9 * baseScale(context), color: glowColor.withAlpha(0.87).cgColor)
    context.drawPath(using: .fillStroke)
    context.restoreGState()

    context.addPath(corePath)
    context.setLineWidth(strokeWidth)
    context.setStrokeColor(fillColor.mixed(with: glowColor, fraction: 0.25).cgColor)
    context.strokePath()

    context.addPath(corePath)
    context.setFillColor(fillColor.cgColor)
    context.fillPath()
}

func applyPaints(_ touches: [EditImageDrawTouch], for context: CGContext, imageSize: NSSize, blurImage: CGImage? = nil) {
    for touch in touches {
        applyPaint(touch, for: context, imageSize: imageSize, blurImage: blurImage)
    }
    context.setBlendMode(.normal)
}

func applyPaint(_ touch: EditImageDrawTouch, for context: CGContext, imageSize: NSSize, blurImage: CGImage?) {
    let multiplier = NSMakePoint(imageSize.width / max(1, touch.canvasSize.width), imageSize.height / max(1, touch.canvasSize.height))
    let lineWidth = touch.width * ((multiplier.x + multiplier.y) / 2.0)
    let points = touch.lines.map { NSMakePoint($0.x * multiplier.x, $0.y * multiplier.y) }
    let rect = NSMakeRect(0, 0, imageSize.width, imageSize.height)
    let color = EditImageCanvasColor(touch.color)

    context.saveGState()
    defer {
        context.restoreGState()
    }
    context.setLineCap(.round)
    context.setLineJoin(.round)

    switch touch.action {
    case .draw:
        guard !points.isEmpty else {
            return
        }
        context.setBlendMode(color.alpha < 1.0 ? .copy : .normal)
        context.addPath(strokeShape(points, lineWidth: lineWidth))
        context.setFillColor(color.cgColor)
        context.fillPath()
    case .drawArrow:
        guard !points.isEmpty else {
            return
        }
        context.setBlendMode(color.alpha < 1.0 ? .copy : .normal)
        let path = CGMutablePath()
        path.addPath(strokeShape(points, lineWidth: lineWidth))
        if let head = editImageCanvasArrowHead(points: points, lineWidth: lineWidth, canvasSize: imageSize) {
            path.addPath(head.copy(strokingWithWidth: lineWidth, lineCap: .round, lineJoin: .round, miterLimit: 0))
        }
        context.addPath(path)
        context.setFillColor(color.cgColor)
        context.fillPath()
    case .clear:
        guard !points.isEmpty else {
            return
        }
        context.setBlendMode(.clear)
        context.addPath(strokeShape(points, lineWidth: lineWidth))
        context.setFillColor(NSColor.black.cgColor)
        context.fillPath()
    case .marker:
        guard !points.isEmpty else {
            return
        }
        context.setBlendMode(.normal)
        stampMarker(points, lineWidth: lineWidth, color: color, context: context)
    case .neon:
        guard !points.isEmpty else {
            return
        }
        context.setBlendMode(.normal)
        drawNeon(points, lineWidth: lineWidth, color: color, imageSize: imageSize, context: context)
    case .blur:
        guard !points.isEmpty, let blurImage = blurImage else {
            return
        }
        context.setBlendMode(.normal)
        context.addPath(strokeShape(points, lineWidth: lineWidth))
        context.clip()
        editImageCanvasDrawUpright(blurImage, in: rect, context: context)
    case .fill:
        context.setBlendMode(.normal)
        context.setFillColor(color.cgColor)
        context.fill(rect)
    case .eraseAll:
        context.clear(rect)
    case .blurAll:
        guard let blurImage = blurImage else {
            return
        }
        context.setBlendMode(.normal)
        editImageCanvasDrawUpright(blurImage, in: rect, context: context)
    }
}

private func configureControlPoints(data: [CGPoint]) -> [(ctrl1: CGPoint, ctrl2: CGPoint)] {
    let segments = data.count - 1
    if segments == 1 {
        return [(data[0], data[1])]
    } else if segments > 1 {
        var ad: [CGFloat] = []
        var d: [CGFloat] = []
        var bd: [CGFloat] = []
        var rhsArray: [CGPoint] = []
        for i in 0 ..< segments {
            var rhsXValue: CGFloat = 0.0
            var rhsYValue: CGFloat = 0.0
            let p0 = data[i]
            let p3 = data[i + 1]
            if i == 0 {
                bd.append(0.0)
                d.append(2.0)
                ad.append(1.0)
                rhsXValue = p0.x + 2.0 * p3.x
                rhsYValue = p0.y + 2.0 * p3.y
            } else if i == segments - 1 {
                bd.append(2.0)
                d.append(7.0)
                ad.append(0.0)
                rhsXValue = 8.0 * p0.x + p3.x
                rhsYValue = 8.0 * p0.y + p3.y
            } else {
                bd.append(1.0)
                d.append(4.0)
                ad.append(1.0)
                rhsXValue = 4.0 * p0.x + 2.0 * p3.x
                rhsYValue = 4.0 * p0.y + 2.0 * p3.y
            }
            rhsArray.append(CGPoint(x: rhsXValue, y: rhsYValue))
        }
        var firstControlPoints: [CGPoint?] = []
        var secondControlPoints: [CGPoint?] = []
        var controlPoints: [(CGPoint, CGPoint)] = []
        var solutionSet1 = [CGPoint?](repeating: nil, count: segments)
        ad[0] = ad[0] / d[0]
        rhsArray[0].x = rhsArray[0].x / d[0]
        rhsArray[0].y = rhsArray[0].y / d[0]
        if segments > 2 {
            for i in 1 ... segments - 2 {
                let rhsValueX = rhsArray[i].x
                let prevRhsValueX = rhsArray[i - 1].x
                let rhsValueY = rhsArray[i].y
                let prevRhsValueY = rhsArray[i - 1].y
                ad[i] = ad[i] / (d[i] - bd[i] * ad[i - 1])
                let exp1x = (rhsValueX - (bd[i] * prevRhsValueX))
                let exp1y = (rhsValueY - (bd[i] * prevRhsValueY))
                let exp2 = (d[i] - bd[i] * ad[i - 1])
                rhsArray[i].x = exp1x / exp2
                rhsArray[i].y = exp1y / exp2
            }
        }
        let lastElementIndex = segments - 1
        let exp1 = (rhsArray[lastElementIndex].x - bd[lastElementIndex] * rhsArray[lastElementIndex - 1].x)
        let exp1y = (rhsArray[lastElementIndex].y - bd[lastElementIndex] * rhsArray[lastElementIndex - 1].y)
        let exp2 = (d[lastElementIndex] - bd[lastElementIndex] * ad[lastElementIndex - 1])
        rhsArray[lastElementIndex].x = exp1 / exp2
        rhsArray[lastElementIndex].y = exp1y / exp2
        solutionSet1[lastElementIndex] = rhsArray[lastElementIndex]
        for i in (0 ..< lastElementIndex).reversed() {
            let controlPointX = rhsArray[i].x - (ad[i] * solutionSet1[i + 1]!.x)
            let controlPointY = rhsArray[i].y - (ad[i] * solutionSet1[i + 1]!.y)
            solutionSet1[i] = CGPoint(x: controlPointX, y: controlPointY)
        }
        firstControlPoints = solutionSet1
        for i in 0 ..< segments {
            if i == (segments - 1) {
                let lastDataPoint = data[i + 1]
                guard let controlPoint1 = firstControlPoints[i] else {
                    continue
                }
                secondControlPoints.append(CGPoint(x: 0.5 * (lastDataPoint.x + controlPoint1.x), y: 0.5 * (lastDataPoint.y + controlPoint1.y)))
            } else {
                let dataPoint = data[i + 1]
                guard let controlPoint1 = firstControlPoints[i + 1] else {
                    continue
                }
                secondControlPoints.append(CGPoint(x: 2 * dataPoint.x - controlPoint1.x, y: 2 * dataPoint.y - controlPoint1.y))
            }
        }
        for i in 0 ..< segments {
            guard let firstControlPoint = firstControlPoints[i], i < secondControlPoints.count, let secondControlPoint = secondControlPoints[i] else {
                continue
            }
            controlPoints.append((firstControlPoint, secondControlPoint))
        }
        return controlPoints
    }
    return []
}

private func pointAt(_ point: CGPoint, distance: CGFloat, angle: CGFloat) -> CGPoint {
    return CGPoint(x: distance * cos(angle) + point.x, y: distance * sin(angle) + point.y)
}

private func angleBetween(_ from: CGPoint, _ to: CGPoint) -> CGFloat {
    return atan2(to.y - from.y, to.x - from.x)
}

private func arrowPath(from point: CGPoint, controlPoint: CGPoint, width: CGFloat, height: CGFloat) -> CGPath {
    let angle = atan2(point.y - controlPoint.y, point.x - controlPoint.x)
    let angleAdjustment = atan2(width, -height)
    let distance = hypot(width, height)
    let path = CGMutablePath()
    path.move(to: point)
    path.addLine(to: pointAt(point, distance: distance, angle: angle - angleAdjustment))
    path.addLine(to: pointAt(point, distance: distance, angle: angle + angleAdjustment))
    path.closeSubpath()
    return path
}

func editImageCanvasVectorPath(_ vector: EditImageCanvasEntity.Vector, referenceSize: CGSize) -> CGPath {
    let lineWidth = EditImageCanvasMetrics.entityLineWidth(vector.lineWidth, referenceSize: referenceSize)
    let arrowSize: CGSize? = vector.type == .line ? nil : CGSize(width: lineWidth * 1.5, height: lineWidth * 3.0)
    let twoSided = vector.type == .twoSidedArrow
    let start = vector.start
    let end = vector.end
    let mid = editImageCanvasVectorMidPoint(start: start, end: end, mid: vector.mid)

    let controlPoints = configureControlPoints(data: [start, mid, end])
    guard controlPoints.count == 2 else {
        let path = CGMutablePath()
        path.move(to: start)
        path.addLine(to: end)
        return path.copy(strokingWithWidth: lineWidth, lineCap: .square, lineJoin: .round, miterLimit: 0)
    }
    let linePath = CGMutablePath()
    var lineStart = start
    if let arrowSize = arrowSize, twoSided {
        lineStart = pointAt(start, distance: -arrowSize.height * 0.5, angle: angleBetween(controlPoints[0].ctrl1, start))
    }
    linePath.move(to: lineStart)
    linePath.addCurve(to: mid, control1: controlPoints[0].ctrl1, control2: controlPoints[0].ctrl2)
    var lineEnd = end
    if let arrowSize = arrowSize {
        lineEnd = pointAt(end, distance: -arrowSize.height * 0.5, angle: angleBetween(controlPoints[1].ctrl1, end))
    }
    linePath.addCurve(to: lineEnd, control1: controlPoints[1].ctrl1, control2: controlPoints[1].ctrl2)

    let path = CGMutablePath()
    path.addPath(linePath.copy(strokingWithWidth: lineWidth, lineCap: .square, lineJoin: .round, miterLimit: 0))
    if let arrowSize = arrowSize {
        path.addPath(arrowPath(from: end, controlPoint: controlPoints[1].ctrl1, width: arrowSize.width, height: arrowSize.height))
        if twoSided {
            path.addPath(arrowPath(from: start, controlPoint: controlPoints[0].ctrl1, width: arrowSize.width, height: arrowSize.height))
        }
    }
    return path
}

func editImageCanvasStarPath(in rect: CGRect, extrusion: CGFloat, points: Int = 5) -> CGPath {
    let path = CGMutablePath()
    let center = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.05)
    var angle: CGFloat = -CGFloat.pi / 2.0
    let angleIncrement = CGFloat.pi * 2.0 / CGFloat(points)
    let radius = rect.width / 2.0
    var firstPoint = true
    for _ in 1 ... points {
        let point = pointAt(center, distance: radius, angle: angle)
        let nextPoint = pointAt(center, distance: radius, angle: angle + angleIncrement)
        let midPoint = pointAt(center, distance: extrusion, angle: angle + angleIncrement * 0.5)
        if firstPoint {
            firstPoint = false
            path.move(to: point)
        }
        path.addLine(to: midPoint)
        path.addLine(to: nextPoint)
        angle += angleIncrement
    }
    path.closeSubpath()
    return path
}

func editImageCanvasBubblePath(in rect: CGRect, cornerRadius: CGFloat, smallCornerRadius: CGFloat, tailPosition: CGPoint, tailWidth: CGFloat) -> CGPath {
    let r1 = min(cornerRadius, min(rect.width, rect.height) / 3.0)
    let r2 = min(smallCornerRadius, min(rect.width, rect.height) / 10.0)
    let ax = tailPosition.x * rect.width
    let ay = max(1.0, tailPosition.y)
    let width = min(max(tailWidth, ay / 2.0), rect.width / 4.0)
    let angle = atan2(ay, width)
    let h = r2 / tan(angle / 2.0)
    let r1a = max(0, min(r1, min(rect.maxX - (rect.minX + ax), ax) * 0.5))
    let r2a = max(0, min(r2, min(rect.maxX - (rect.minX + ax), ax) * 0.2))

    let path = CGMutablePath()
    path.addArc(center: CGPoint(x: rect.minX + r1, y: rect.minY + r1), radius: r1, startAngle: .pi, endAngle: .pi * 3.0 / 2.0, clockwise: false)
    path.addArc(center: CGPoint(x: rect.maxX - r1, y: rect.minY + r1), radius: r1, startAngle: -.pi / 2.0, endAngle: 0.0, clockwise: false)
    if ax > rect.width / 2.0 {
        if ax < rect.width - 1 {
            path.addArc(center: CGPoint(x: rect.maxX - r1a, y: rect.maxY - r1a), radius: r1a, startAngle: 0.0, endAngle: .pi / 2.0, clockwise: false)
            path.addArc(center: CGPoint(x: rect.minX + ax + r2a, y: rect.maxY + r2a), radius: r2a, startAngle: .pi * 3.0 / 2.0, endAngle: .pi, clockwise: true)
        }
        path.addLine(to: CGPoint(x: rect.minX + ax, y: rect.maxY + ay))
        path.addArc(center: CGPoint(x: rect.minX + ax - width - r2, y: rect.maxY + h), radius: h, startAngle: -(CGFloat.pi / 2 - angle), endAngle: CGFloat.pi * 3 / 2, clockwise: true)
        path.addArc(center: CGPoint(x: rect.minX + r1, y: rect.maxY - r1), radius: r1, startAngle: CGFloat.pi / 2, endAngle: CGFloat.pi, clockwise: false)
    } else {
        path.addArc(center: CGPoint(x: rect.maxX - r1, y: rect.maxY - r1), radius: r1, startAngle: 0, endAngle: CGFloat.pi / 2, clockwise: false)
        path.addArc(center: CGPoint(x: rect.minX + ax + width + r2, y: rect.maxY + h), radius: h, startAngle: CGFloat.pi * 3 / 2, endAngle: CGFloat.pi * 3 / 2 - angle, clockwise: true)
        path.addLine(to: CGPoint(x: rect.minX + ax, y: rect.maxY + ay))
        if ax > 1 {
            path.addArc(center: CGPoint(x: rect.minX + ax - r2a, y: rect.maxY + r2a), radius: r2a, startAngle: 0, endAngle: CGFloat.pi * 3 / 2, clockwise: true)
            path.addArc(center: CGPoint(x: rect.minX + r1a, y: rect.maxY - r1a), radius: r1a, startAngle: CGFloat.pi / 2, endAngle: CGFloat.pi, clockwise: false)
        }
    }
    path.closeSubpath()
    return path
}

final class EditImageCanvasTextLayout {
    let text: EditImageCanvasEntity.Text
    let referenceSize: CGSize
    let fontSize: CGFloat
    let boxSize: CGSize
    private let storage: NSTextStorage
    private let layoutManager: NSLayoutManager
    private let container: NSTextContainer
    private let backgroundRects: [CGRect]

    init(text: EditImageCanvasEntity.Text, referenceSize: CGSize) {
        self.text = text
        self.referenceSize = referenceSize
        let fontSize = EditImageCanvasMetrics.fontSize(text.fontSize, referenceSize: referenceSize)
        self.fontSize = fontSize
        let unit = EditImageCanvasMetrics.unit(referenceSize)
        let font = text.font.font(size: fontSize)

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = text.alignment.nsAlignment

        let textColor = EditImageCanvasTextLayout.textColor(for: text)
        let string = text.string.isEmpty ? " " : text.string
        self.storage = NSTextStorage(string: string, attributes: [.font: font, .foregroundColor: textColor.nsColor, .paragraphStyle: paragraph])
        self.layoutManager = NSLayoutManager()
        self.container = NSTextContainer(size: NSMakeSize(max(1, text.width), CGFloat.greatestFiniteMagnitude))
        self.container.lineFragmentPadding = floor(fontSize * 0.24)
        self.layoutManager.addTextContainer(self.container)
        self.storage.addLayoutManager(self.layoutManager)
        self.layoutManager.ensureLayout(for: self.container)
        let measured = self.layoutManager.usedRect(for: self.container)
        let boxWidth = max(224.0 * unit, ceil(measured.width) + 20.0 * unit)
        self.container.size = NSMakeSize(boxWidth, CGFloat.greatestFiniteMagnitude)
        self.layoutManager.ensureLayout(for: self.container)
        let used = self.layoutManager.usedRect(for: self.container)
        self.boxSize = NSMakeSize(boxWidth, ceil(max(used.height, font.ascender - font.descender)))
        if text.string.isEmpty {
            self.backgroundRects = []
        } else {
            self.backgroundRects = EditImageCanvasTextLayout.makeBackgroundRects(layoutManager: self.layoutManager, storage: self.storage, container: self.container, alignment: text.alignment)
        }
    }

    static func textColor(for text: EditImageCanvasEntity.Text) -> EditImageCanvasColor {
        switch text.style {
        case .regular, .semi:
            return text.color
        case .filled:
            return text.color.lightness > 0.99 ? .black : .white
        }
    }

    static func frameColor(for text: EditImageCanvasEntity.Text) -> EditImageCanvasColor? {
        switch text.style {
        case .regular:
            return nil
        case .filled:
            return text.color
        case .semi:
            return text.color.lightness > 0.7 ? EditImageCanvasColor.black.withAlpha(0.75) : EditImageCanvasColor.white.withAlpha(0.75)
        }
    }

    static func makeBackgroundRects(layoutManager: NSLayoutManager, storage: NSTextStorage, container: NSTextContainer, alignment: EditImageCanvasEntity.TextAlignment) -> [CGRect] {
        var rects: [CGRect] = []
        let string = storage.string as NSString
        let glyphRange = layoutManager.glyphRange(for: container)
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, lineGlyphRange, _ in
            let characterRange = layoutManager.characterRange(forGlyphRange: lineGlyphRange, actualGlyphRange: nil)
            let substring = string.substring(with: characterRange)
            if substring.trimmingCharacters(in: .newlines).isEmpty {
                return
            }
            var used = usedRect
            if substring.hasSuffix(" ") && alignment != .right {
                used.size.width -= floor(used.height * 0.145)
            }
            rects.append(used)
        }
        guard rects.count >= 2 else {
            return rects
        }
        func process(_ index: Int, maxIndex: Int) {
            guard rects.count >= 2 && index > 0 && index <= maxIndex else {
                return
            }
            var last = rects[index - 1]
            var cur = rects[index]
            let radius = cur.height * 0.2
            let doubleRadius = radius * 2.5
            let t2 = ((last.minX - cur.minX < doubleRadius) && (last.minX > cur.minX)) || ((last.maxX - cur.maxX > -doubleRadius) && (last.maxX < cur.maxX))
            if t2 {
                rects[index - 1] = CGRect(x: cur.minX, y: last.minY, width: cur.width, height: last.height)
                process(index - 1, maxIndex: maxIndex)
            }
            last = rects[index - 1]
            cur = rects[index]
            let t1 = ((cur.minX - last.minX < doubleRadius) && (cur.minX > last.minX)) || ((cur.maxX - last.maxX > -doubleRadius) && (cur.maxX < last.maxX))
            if t1 {
                rects[index] = CGRect(x: last.minX, y: cur.minY, width: last.width, height: cur.height)
                process(index + 1, maxIndex: maxIndex)
            }
        }
        for i in 1 ..< rects.count {
            process(i, maxIndex: i)
        }
        return rects
    }

    static func backgroundPaths(_ backgroundRects: [CGRect], unit: CGFloat) -> [CGPath] {
        var paths: [CGPath] = []
        var last: CGRect = .null
        for i in 0 ..< backgroundRects.count {
            let cur = backgroundRects[i]
            let radius = cur.height * 0.2
            paths.append(CGPath(roundedRect: cur, cornerWidth: min(radius, cur.width / 2.0), cornerHeight: min(radius, cur.height / 2.0), transform: nil))
            if i == 0 {
                last = cur
                continue
            }
            guard abs(last.maxY - cur.minY) < 15.0 * unit else {
                last = cur
                continue
            }
            let a = cur.origin
            let b = CGPoint(x: cur.maxX, y: cur.minY)
            let c = CGPoint(x: last.minX, y: last.maxY)
            let d = CGPoint(x: last.maxX, y: last.maxY)
            if a.x - c.x >= 2.0 * radius {
                let path = CGMutablePath()
                path.addArc(center: CGPoint(x: a.x - radius, y: a.y + radius), radius: radius, startAngle: .pi * 0.5 * 3.0, endAngle: 0.0, clockwise: false)
                path.addArc(center: CGPoint(x: a.x + radius, y: a.y + radius), radius: radius, startAngle: .pi, endAngle: 3.0 * .pi * 0.5, clockwise: false)
                path.addLine(to: CGPoint(x: a.x - radius, y: a.y))
                paths.append(path)
            }
            if abs(a.x - c.x) < 0.5 {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: a.x, y: a.y - radius))
                path.addLine(to: CGPoint(x: a.x, y: a.y + radius))
                path.addArc(center: CGPoint(x: a.x + radius, y: a.y + radius), radius: radius, startAngle: .pi, endAngle: .pi * 0.5 * 3.0, clockwise: false)
                path.addArc(center: CGPoint(x: a.x + radius, y: a.y - radius), radius: radius, startAngle: .pi * 0.5, endAngle: .pi, clockwise: false)
                paths.append(path)
            }
            if d.x - b.x >= 2.0 * radius {
                let path = CGMutablePath()
                path.addArc(center: CGPoint(x: b.x + radius, y: b.y + radius), radius: radius, startAngle: .pi * 0.5 * 3.0, endAngle: .pi, clockwise: true)
                path.addArc(center: CGPoint(x: b.x - radius, y: b.y + radius), radius: radius, startAngle: 0.0, endAngle: 3.0 * .pi * 0.5, clockwise: true)
                path.addLine(to: CGPoint(x: b.x + radius, y: b.y))
                paths.append(path)
            }
            if abs(d.x - b.x) < 0.5 {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: b.x, y: b.y - radius))
                path.addLine(to: CGPoint(x: b.x, y: b.y + radius))
                path.addArc(center: CGPoint(x: b.x - radius, y: b.y + radius), radius: radius, startAngle: 0.0, endAngle: 3.0 * .pi * 0.5, clockwise: true)
                path.addArc(center: CGPoint(x: b.x - radius, y: b.y - radius), radius: radius, startAngle: .pi * 0.5, endAngle: 0.0, clockwise: true)
                paths.append(path)
            }
            if c.x - a.x >= 2.0 * radius {
                let path = CGMutablePath()
                path.addArc(center: CGPoint(x: c.x - radius, y: c.y - radius), radius: radius, startAngle: .pi * 0.5, endAngle: 0.0, clockwise: true)
                path.addArc(center: CGPoint(x: c.x + radius, y: c.y - radius), radius: radius, startAngle: .pi, endAngle: .pi * 0.5, clockwise: true)
                path.addLine(to: CGPoint(x: c.x - radius, y: c.y))
                paths.append(path)
            }
            if b.x - d.x >= 2.0 * radius {
                let path = CGMutablePath()
                path.addArc(center: CGPoint(x: d.x + radius, y: d.y - radius), radius: radius, startAngle: .pi * 0.5, endAngle: .pi, clockwise: false)
                path.addArc(center: CGPoint(x: d.x - radius, y: d.y - radius), radius: radius, startAngle: 0.0, endAngle: .pi * 0.5, clockwise: false)
                path.addLine(to: CGPoint(x: d.x + radius, y: d.y))
                paths.append(path)
            }
            last = cur
        }
        return paths
    }

    func draw(in context: CGContext, origin: CGPoint) {
        let unit = EditImageCanvasMetrics.unit(referenceSize)
        if let frameColor = EditImageCanvasTextLayout.frameColor(for: text), !backgroundRects.isEmpty {
            context.saveGState()
            context.translateBy(x: origin.x, y: origin.y)
            context.setAlpha(frameColor.alpha)
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            context.setFillColor(frameColor.withAlpha(1.0).cgColor)
            context.setStrokeColor(frameColor.withAlpha(1.0).cgColor)
            context.setLineWidth(unit)
            for path in EditImageCanvasTextLayout.backgroundPaths(backgroundRects, unit: unit) {
                context.addPath(path)
                context.drawPath(using: .fillStroke)
            }
            context.endTransparencyLayer()
            context.restoreGState()
        }
        guard !text.string.isEmpty else {
            return
        }
        context.saveGState()
        if text.style == .regular {
            context.setShadow(offset: baseOffset(CGSize(width: 0, height: 4.0 * unit), context: context), blur: 8.0 * unit * baseScale(context), color: NSColor.black.withAlphaComponent(0.4).cgColor)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        let glyphRange = layoutManager.glyphRange(for: container)
        layoutManager.drawGlyphs(forGlyphRange: glyphRange, at: origin)
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }
}

final class EditImageCanvasTextLayoutCache {
    private var layouts: [Int64: EditImageCanvasTextLayout] = [:]

    func layout(for id: Int64, text: EditImageCanvasEntity.Text, referenceSize: CGSize) -> EditImageCanvasTextLayout {
        if let current = layouts[id], current.text == text, current.referenceSize == referenceSize {
            return current
        }
        let layout = EditImageCanvasTextLayout(text: text, referenceSize: referenceSize)
        layouts[id] = layout
        return layout
    }

    func boxSize(for text: EditImageCanvasEntity.Text, referenceSize: CGSize) -> CGSize {
        for layout in layouts.values where layout.text == text && layout.referenceSize == referenceSize {
            return layout.boxSize
        }
        return EditImageCanvasTextLayout(text: text, referenceSize: referenceSize).boxSize
    }

    func prune(_ ids: Set<Int64>) {
        for key in layouts.keys where !ids.contains(key) {
            layouts.removeValue(forKey: key)
        }
    }
}

func applyEntities(_ entities: [EditImageCanvasEntity], for context: CGContext, size: NSSize, excluding: Int64? = nil, cache: EditImageCanvasTextLayoutCache? = nil, stickerFrames: [Int64: CGImage] = [:]) {
    for entity in entities where entity.id != excluding {
        let scale = size.width / max(1, entity.referenceSize.width)
        context.saveGState()
        context.scaleBy(x: scale, y: scale)
        drawEntity(entity, in: context, cache: cache, stickerFrame: stickerFrames[entity.id])
        context.restoreGState()
    }
    context.setBlendMode(.normal)
}

private func drawEntity(_ entity: EditImageCanvasEntity, in context: CGContext, cache: EditImageCanvasTextLayoutCache?, stickerFrame: CGImage?) {
    let referenceSize = entity.referenceSize
    switch entity.content {
    case let .vector(vector):
        context.addPath(editImageCanvasVectorPath(vector, referenceSize: referenceSize))
        context.setFillColor(vector.color.cgColor)
        context.fillPath()
        return
    default:
        break
    }
    context.concatenate(entity.localTransform)
    switch entity.content {
    case let .text(text):
        let layout = cache?.layout(for: entity.id, text: text, referenceSize: referenceSize) ?? EditImageCanvasTextLayout(text: text, referenceSize: referenceSize)
        layout.draw(in: context, origin: CGPoint(x: -layout.boxSize.width / 2.0, y: -layout.boxSize.height / 2.0))
    case let .sticker(sticker):
        let rect = CGRect(x: -sticker.baseSize.width / 2.0, y: -sticker.baseSize.height / 2.0, width: sticker.baseSize.width, height: sticker.baseSize.height)
        context.interpolationQuality = .high
        editImageCanvasDrawUpright(stickerFrame ?? sticker.image, in: rect, context: context)
    case let .shape(shape):
        let maxLineWidth = EditImageCanvasMetrics.shapeMaxLineWidth(referenceSize: referenceSize)
        let rect = CGRect(x: -shape.size.width / 2.0, y: -shape.size.height / 2.0, width: shape.size.width, height: shape.size.height).insetBy(dx: maxLineWidth * 0.5, dy: maxLineWidth * 0.5)
        let path: CGPath
        switch shape.type {
        case .rectangle:
            path = CGPath(rect: rect, transform: nil)
        case .ellipse:
            path = CGPath(ellipseIn: rect, transform: nil)
        case .star:
            path = editImageCanvasStarPath(in: rect, extrusion: shape.size.width * 0.2)
        }
        context.addPath(path)
        switch shape.drawType {
        case .fill:
            context.setFillColor(shape.color.cgColor)
            context.fillPath()
        case .stroke:
            context.setStrokeColor(shape.color.cgColor)
            context.setLineWidth(EditImageCanvasMetrics.entityLineWidth(shape.lineWidth, referenceSize: referenceSize))
            context.strokePath()
        }
    case let .bubble(bubble):
        let longSide = max(referenceSize.width, referenceSize.height)
        let rect = CGRect(x: -bubble.size.width / 2.0, y: -bubble.size.height / 2.0, width: bubble.size.width, height: bubble.size.height)
        let path = editImageCanvasBubblePath(in: rect, cornerRadius: max(10.0, longSide * 0.045), smallCornerRadius: max(5.0, longSide * 0.01), tailPosition: bubble.tailPosition, tailWidth: max(5.0, longSide * 0.1))
        context.addPath(path)
        switch bubble.drawType {
        case .fill:
            context.setFillColor(bubble.color.cgColor)
            context.fillPath()
        case .stroke:
            context.setLineJoin(.round)
            context.setStrokeColor(bubble.color.cgColor)
            context.setLineWidth(EditImageCanvasMetrics.entityLineWidth(bubble.lineWidth, referenceSize: referenceSize))
            context.strokePath()
        }
    case .vector:
        break
    }
}

func editImageCanvasEmojiImage(_ emoji: String) -> CGImage? {
    let size = NSMakeSize(256, 256)
    return generateImage(size, contextGenerator: { size, context in
        context.clear(size.bounds)
        let font = NSFont(name: "AppleColorEmoji", size: 200) ?? NSFont.systemFont(ofSize: 200)
        let attributed = NSAttributedString(string: emoji, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.textPosition = CGPoint(x: (size.width - bounds.width) / 2.0 - bounds.minX, y: (size.height - bounds.height) / 2.0 - bounds.minY)
        CTLineDraw(line, context)
    }, scale: 1.0)
}
