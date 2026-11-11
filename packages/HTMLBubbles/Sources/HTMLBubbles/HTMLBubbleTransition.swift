import Cocoa
import TGUIKit

enum HTMLBubbleDiff {
    static func firstChange(old: [HTMLBubbleTile], new: [HTMLBubbleTile]) -> CGFloat? {
        for index in 0 ..< max(old.count, new.count) {
            guard index < old.count, index < new.count else {
                return (index < old.count ? old[index] : new[index]).rect.minY
            }
            if let y = firstChange(old[index], new[index]) {
                return y
            }
        }
        return nil
    }

    static func unchangedBottom(old: [HTMLBubbleTile], oldHeight: CGFloat, new: [HTMLBubbleTile], newHeight: CGFloat, above top: CGFloat) -> CGFloat {
        guard let first = old.first, let reference = new.first else {
            return 0
        }
        let width = first.image.width
        let scale = CGFloat(width) / max(first.rect.width, 1)
        guard width > 0, reference.image.width == width, abs(CGFloat(reference.image.width) / max(reference.rect.width, 1) - scale) < 0.01 else {
            return 0
        }
        struct Strip {
            let start: Int
            let rows: Int
            let stride: Int
            let data: CFData
        }
        func strips(_ tiles: [HTMLBubbleTile]) -> [Strip]? {
            var result: [Strip] = []
            for tile in tiles {
                let image = tile.image
                guard image.width == width, image.bitsPerPixel == 32, image.bytesPerRow >= width * 4,
                      let data = image.dataProvider?.data, CFDataGetLength(data) >= image.bytesPerRow * image.height else {
                    return nil
                }
                result.append(Strip(start: Int((tile.rect.minY * scale).rounded()), rows: image.height, stride: image.bytesPerRow, data: data))
            }
            return result
        }
        guard let oldStrips = strips(old), let newStrips = strips(new) else {
            return 0
        }
        func row(_ strips: [Strip], _ y: Int) -> UnsafePointer<UInt8>? {
            for strip in strips where y >= strip.start && y < strip.start + strip.rows {
                guard let bytes = CFDataGetBytePtr(strip.data) else {
                    return nil
                }
                return bytes + (y - strip.start) * strip.stride
            }
            return nil
        }
        let oldRows = Int((oldHeight * scale).rounded())
        let newRows = Int((newHeight * scale).rounded())
        let limit = max(0, min(oldRows, newRows) - Int((top * scale).rounded(.up)))
        var matched = 0
        var misses = 0
        var index = 0
        while index < limit {
            guard let a = row(oldStrips, oldRows - 1 - index), let b = row(newStrips, newRows - 1 - index) else {
                break
            }
            if rowsMatch(a, b, width * 4) {
                misses = 0
                matched = index + 1
            } else {
                misses += 1
                if CGFloat(misses) > 12 * scale {
                    break
                }
            }
            index += 1
        }
        return floor(CGFloat(matched) / scale)
    }

    private static func rowsMatch(_ a: UnsafePointer<UInt8>, _ b: UnsafePointer<UInt8>, _ count: Int) -> Bool {
        if memcmp(a, b, count) == 0 {
            return true
        }
        for index in 0 ..< count where abs(Int(a[index]) - Int(b[index])) > 3 {
            return false
        }
        return true
    }

    static func dominantColor(in tiles: [HTMLBubbleTile], at y: CGFloat) -> CGColor? {
        guard let tile = tiles.first(where: { y >= $0.rect.minY && y < $0.rect.maxY }) else {
            return nil
        }
        let image = tile.image
        let scale = CGFloat(image.width) / max(tile.rect.width, 1)
        let row = Int(((y - tile.rect.minY) * scale).rounded(.down))
        guard image.bitsPerPixel == 32, row >= 0, row < image.height, let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data), CFDataGetLength(data) >= image.bytesPerRow * image.height else {
            return nil
        }
        var counts: [UInt32: Int] = [:]
        let pixels = UnsafeRawPointer(bytes + row * image.bytesPerRow).assumingMemoryBound(to: UInt32.self)
        for x in 0 ..< image.width {
            counts[pixels[x], default: 0] += 1
        }
        guard let pixel = counts.max(by: { $0.value < $1.value })?.key else {
            return nil
        }
        let channels = (0 ..< 4).map { CGFloat((pixel >> (8 * UInt32($0))) & 0xff) / 255 }
        let first = image.alphaInfo == .premultipliedFirst || image.alphaInfo == .first || image.alphaInfo == .noneSkipFirst
        let little = image.bitmapInfo.contains(.byteOrder32Little)
        let order: [Int] = first ? (little ? [2, 1, 0, 3] : [1, 2, 3, 0]) : (little ? [3, 2, 1, 0] : [0, 1, 2, 3])
        let alpha = image.alphaInfo == .noneSkipFirst || image.alphaInfo == .noneSkipLast ? 1 : channels[order[3]]
        guard alpha > 0 else {
            return nil
        }
        let red = channels[order[0]] / alpha
        let green = channels[order[1]] / alpha
        let blue = channels[order[2]] / alpha
        return CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: [min(red, 1), min(green, 1), min(blue, 1), alpha])
    }

    static func bottomCornerRadius(in tiles: [HTMLBubbleTile], height: CGFloat) -> CGFloat {
        guard let tile = tiles.first(where: { height - 0.25 >= $0.rect.minY && height - 0.25 < $0.rect.maxY }) else {
            return 0
        }
        let image = tile.image
        let scale = CGFloat(image.width) / max(tile.rect.width, 1)
        var row = min(image.height, Int(((height - tile.rect.minY) * scale).rounded(.down))) - 1
        guard image.bitsPerPixel == 32, row >= 0, let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data), CFDataGetLength(data) >= image.bytesPerRow * image.height else {
            return 0
        }
        let first = image.alphaInfo == .premultipliedFirst || image.alphaInfo == .first
        let alpha = first == image.bitmapInfo.contains(.byteOrder32Little) ? 3 : 0
        let center = image.width / 2 * 4 + alpha
        let lowest = max(0, row - Int((4 * scale).rounded(.up)))
        while row > lowest, bytes[row * image.bytesPerRow + center] < 128 {
            row -= 1
        }
        let pixels = bytes + row * image.bytesPerRow
        var run = 0
        while run < image.width / 3, pixels[run * 4 + alpha] < 128 {
            run += 1
        }
        guard run > 0, run < image.width / 3 else {
            return 0
        }
        let root = 0.5 + CGFloat(run).squareRoot()
        return min((root * root + 0.25) / scale, 40)
    }

    private static func firstChange(_ a: HTMLBubbleTile, _ b: HTMLBubbleTile) -> CGFloat? {
        let imageA = a.image
        let imageB = b.image
        if imageA === imageB, a.rect == b.rect {
            return nil
        }
        guard a.rect.origin == b.rect.origin, imageA.width == imageB.width, imageA.width > 0,
              imageA.bitsPerPixel == 32, imageB.bitsPerPixel == 32,
              let dataA = imageA.dataProvider?.data, let dataB = imageB.dataProvider?.data,
              let bytesA = CFDataGetBytePtr(dataA), let bytesB = CFDataGetBytePtr(dataB) else {
            return min(a.rect.minY, b.rect.minY)
        }
        let width = imageA.width
        let strideA = imageA.bytesPerRow
        let strideB = imageB.bytesPerRow
        guard strideA >= width * 4, strideB >= width * 4, CFDataGetLength(dataA) >= strideA * imageA.height, CFDataGetLength(dataB) >= strideB * imageB.height else {
            return min(a.rect.minY, b.rect.minY)
        }
        let scale = CGFloat(width) / max(a.rect.width, 1)
        let rows = min(imageA.height, imageB.height)
        for y in 0 ..< rows where !rowsMatch(bytesA + y * strideA, bytesB + y * strideB, width * 4) {
            return a.rect.minY + CGFloat(y) / scale
        }
        return imageA.height == imageB.height ? nil : a.rect.minY + CGFloat(rows) / scale
    }
}

final class HTMLBubbleTransition {
    private static let edgeHeight: CGFloat = 16
    private static let bodyFadeDuration: CFTimeInterval = 0.12

    private struct Clipped {
        let container: CALayer
        let content: CALayer
    }

    private let fixed: [Clipped]
    private let outgoing: Clipped
    private var leftover: Clipped?
    private let incoming: Clipped?
    private weak var tilesLayer: CALayer?
    private let scale: CGFloat
    private let extent: CGSize
    private let target: CGSize
    private var finished = false
    private var sliding: Clipped?
    private var middle: CALayer?
    private var middleTarget: CGRect = .zero
    private var staleEdge: CALayer?
    private var slideDistance: CGFloat = 0
    private var slideStarted = false
    private var slideDone = true
    private var fadeDone = false
    private var onSettled: ((HTMLBubbleTransition) -> Void)?

    init?(resizing old: [HTMLBubbleTile], oldSize: CGSize, to new: [HTMLBubbleTile], newSize: CGSize, unchangedTop: CGFloat, unchangedBottom: CGFloat, pinned: Bool, contentLayer: CALayer, tilesLayer: CALayer, scale: CGFloat, duration: CFTimeInterval, completion: @escaping (HTMLBubbleTransition) -> Void) {
        let width = max(oldSize.width, newSize.width, 1)
        let shortest = min(oldSize.height, newSize.height)
        let top = max(0, min(unchangedTop, shortest)).rounded(.down)
        let unchanged = max(0, min((unchangedBottom * scale).rounded(.up) / scale, shortest - top))
        let bottom = pinned || unchanged >= HTMLBubbleTransition.edgeHeight ? unchanged : 0
        let delta = newSize.height - oldSize.height
        guard abs(delta) >= 0.5 else {
            return nil
        }
        let extent = CGSize(width: width, height: max(oldSize.height, newSize.height, 1))
        self.scale = scale
        self.extent = extent
        self.target = newSize
        self.tilesLayer = tilesLayer

        var bands: [Clipped] = []
        if top >= 0.5 {
            bands.append(HTMLBubbleTransition.clipped(new, region: CGRect(x: 0, y: 0, width: width, height: top), extent: extent, scale: scale))
        }
        var sliding: Clipped?
        if bottom >= 0.5 {
            let band = HTMLBubbleTransition.clipped(new, region: CGRect(x: 0, y: newSize.height - bottom, width: width, height: bottom), extent: extent, scale: scale)
            if pinned {
                let stale = CALayer()
                stale.frame = CGRect(x: 0, y: bottom - oldSize.height, width: extent.width, height: extent.height)
                HTMLBubbleTransition.fill(stale, with: old, scale: scale)
                band.container.addSublayer(stale)
                self.staleEdge = stale
            }
            bands.append(band)
            sliding = band
        }
        self.fixed = bands
        let oldMiddle = max(oldSize.height - bottom - top, 0)
        let newMiddle = max(newSize.height - bottom - top, 0)
        let faded = min(oldMiddle, newMiddle)
        self.outgoing = HTMLBubbleTransition.clipped(old, region: CGRect(x: 0, y: top, width: width, height: faded), extent: extent, scale: scale)
        if faded < oldMiddle {
            self.leftover = HTMLBubbleTransition.clipped(old, region: CGRect(x: 0, y: top + faded, width: width, height: oldMiddle - faded), extent: extent, scale: scale)
        }
        self.incoming = HTMLBubbleTransition.clipped(new, region: CGRect(x: 0, y: top, width: width, height: newMiddle), extent: extent, scale: scale)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let middle = CALayer()
        middle.anchorPoint = .zero
        middle.masksToBounds = true
        middle.zPosition = 1
        middle.backgroundColor = HTMLBubbleDiff.dominantColor(in: new, at: top + min(8, max(newMiddle, 1) / 2))
        if sliding == nil {
            let radius = HTMLBubbleDiff.bottomCornerRadius(in: new, height: newSize.height)
            if radius > 0 {
                middle.cornerRadius = radius
                middle.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            }
        }
        middle.bounds = CGRect(x: 0, y: top, width: width, height: oldMiddle)
        middle.position = CGPoint(x: 0, y: top)
        contentLayer.addSublayer(middle)
        self.middle = middle
        self.middleTarget = CGRect(x: 0, y: top, width: width, height: newMiddle)
        let host = middle
        incoming?.container.zPosition = 1
        outgoing.container.zPosition = 1.5
        leftover?.container.zPosition = 1.5
        if let incoming = incoming {
            host.addSublayer(incoming.container)
        }
        host.addSublayer(outgoing.container)
        if let leftover = leftover {
            host.addSublayer(leftover.container)
        }
        for band in bands {
            band.container.zPosition = 2
            contentLayer.addSublayer(band.container)
        }
        if let sliding = sliding {
            sliding.container.transform = CATransform3DMakeTranslation(0, -delta, 0)
        }
        tilesLayer.isHidden = true
        CATransaction.commit()

        self.sliding = sliding
        self.slideDistance = delta
        self.slideDone = false
        self.onSettled = completion

        let easeOut = CAMediaTimingFunction(name: .easeOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self = self else {
                return
            }
            self.fadeDone = true
            if !self.slideStarted {
                self.startSlide(.immediate)
            }
            self.settleIfDone()
        }
        let quick = min(duration, HTMLBubbleTransition.bodyFadeDuration)
        outgoing.container.add(HTMLBubbleTransition.animation("opacity", from: 1, to: 0, duration: quick, timing: easeOut, hold: true), forKey: "transition.opacity")
        leftover?.container.add(HTMLBubbleTransition.animation("opacity", from: 1, to: 0, duration: quick, timing: easeOut, hold: true), forKey: "transition.opacity")
        staleEdge?.add(HTMLBubbleTransition.animation("opacity", from: 1, to: 0, duration: duration, timing: easeOut, hold: true), forKey: "transition.opacity")
        CATransaction.commit()
    }

    func startSlide(_ transition: ContainedViewLayoutTransition) {
        guard !slideStarted, !finished else {
            return
        }
        slideStarted = true
        let middleBounds = middle?.bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        sliding?.container.transform = CATransform3DIdentity
        middle?.bounds = middleTarget
        CATransaction.commit()
        switch transition {
        case .immediate:
            slideDone = true
        case let .animated(duration, curve):
            let timing = CAMediaTimingFunction(name: curve.timingFunction)
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                self?.slideDone = true
                self?.settleIfDone()
            }
            sliding?.container.add(HTMLBubbleTransition.animation("transform.translation.y", from: -slideDistance, to: 0, duration: duration, timing: timing, hold: false), forKey: "transition.slide")
            if let middle = middle, let middleBounds = middleBounds {
                middle.add(HTMLBubbleTransition.animation("bounds", from: NSValue(rect: middleBounds), to: NSValue(rect: middleTarget), duration: duration, timing: timing, hold: false), forKey: "transition.middle")
            }
            CATransaction.commit()
        }
    }

    private func settleIfDone() {
        guard fadeDone, slideDone, let onSettled = onSettled else {
            return
        }
        self.onSettled = nil
        onSettled(self)
    }

    func covers(_ size: CGSize) -> Bool {
        return abs(size.width - target.width) < 0.5 && abs(size.height - target.height) < 0.5
    }

    func mirror(_ tiles: [HTMLBubbleTile]) {
        guard !finished else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for part in fixed {
            HTMLBubbleTransition.fill(part.content, with: tiles, scale: scale)
        }
        if let incoming = incoming {
            HTMLBubbleTransition.fill(incoming.content, with: tiles, scale: scale)
        }
        CATransaction.commit()
    }

    func finish() {
        guard !finished else {
            return
        }
        finished = true
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for part in fixed {
            part.container.removeFromSuperlayer()
        }
        incoming?.container.removeFromSuperlayer()
        outgoing.container.removeAllAnimations()
        outgoing.container.removeFromSuperlayer()
        leftover?.container.removeFromSuperlayer()
        middle?.removeFromSuperlayer()
        tilesLayer?.isHidden = false
        CATransaction.commit()
    }

    static func opensOrCloses(_ kind: String) -> Bool {
        return kind == "slide-up" || kind == "slide-down"
    }

    static func reveal(_ layer: CALayer, kind: String, size: CGSize) {
        let opacity: CABasicAnimation
        var motion: CABasicAnimation?
        switch kind {
        case "none":
            return
        case "slide-left", "slide-right", "slide-up", "slide-down":
            let timing = CAMediaTimingFunction(controlPoints: 0.33, 1, 0.68, 1)
            let path = kind == "slide-left" || kind == "slide-right" ? "transform.translation.x" : "transform.translation.y"
            let from: CGFloat = kind == "slide-left" || kind == "slide-up" ? 24 : -24
            opacity = animation("opacity", from: 0, to: 1, duration: 0.26, timing: timing, hold: false)
            motion = animation(path, from: from, to: 0, duration: 0.26, timing: timing, hold: false)
        case "pop":
            let timing = CAMediaTimingFunction(controlPoints: 0.34, 1.56, 0.64, 1)
            opacity = animation("opacity", from: 0, to: 1, duration: 0.32, timing: timing, hold: false)
            let center = CGPoint(x: size.width * (0.5 - layer.anchorPoint.x), y: size.height * (0.5 - layer.anchorPoint.y))
            var scaled = CATransform3DMakeTranslation(-center.x, -center.y, 0)
            scaled = CATransform3DConcat(scaled, CATransform3DMakeScale(0.96, 0.96, 1))
            scaled = CATransform3DConcat(scaled, CATransform3DMakeTranslation(center.x, center.y, 0))
            motion = animation("transform", from: NSValue(caTransform3D: scaled), to: NSValue(caTransform3D: CATransform3DIdentity), duration: 0.32, timing: timing, hold: false)
        default:
            opacity = animation("opacity", from: 0, to: 1, duration: 0.22, timing: CAMediaTimingFunction(name: .easeOut), hold: false)
        }
        layer.removeAnimation(forKey: "transition.motion")
        layer.add(opacity, forKey: "transition.opacity")
        if let motion = motion {
            layer.add(motion, forKey: "transition.motion")
        }
    }

    private static func animation(_ keyPath: String, from: Any, to: Any, duration: CFTimeInterval, timing: CAMediaTimingFunction, hold: Bool) -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: keyPath)
        animation.fromValue = from
        animation.toValue = to
        animation.duration = duration
        animation.timingFunction = timing
        if hold {
            animation.fillMode = .forwards
            animation.isRemovedOnCompletion = false
        }
        return animation
    }

    private static func clipped(_ tiles: [HTMLBubbleTile], region: CGRect, extent: CGSize, scale: CGFloat) -> Clipped {
        let container = CALayer()
        container.frame = region
        container.masksToBounds = true
        let content = CALayer()
        content.anchorPoint = CGPoint(x: region.midX / extent.width, y: region.midY / extent.height)
        content.frame = CGRect(x: -region.minX, y: -region.minY, width: extent.width, height: extent.height)
        fill(content, with: tiles, scale: scale)
        container.addSublayer(content)
        return Clipped(container: container, content: content)
    }

    private static func fill(_ layer: CALayer, with tiles: [HTMLBubbleTile], scale: CGFloat) {
        var sublayers = layer.sublayers ?? []
        while sublayers.count > tiles.count {
            sublayers.removeLast().removeFromSuperlayer()
        }
        while sublayers.count < tiles.count {
            let sublayer = CALayer()
            sublayer.contentsGravity = .resize
            layer.addSublayer(sublayer)
            sublayers.append(sublayer)
        }
        for (sublayer, tile) in zip(sublayers, tiles) {
            sublayer.frame = tile.rect
            sublayer.contentsScale = scale
            sublayer.contents = tile.contents
        }
    }
}
