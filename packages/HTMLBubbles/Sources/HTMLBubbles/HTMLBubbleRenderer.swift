import Cocoa
import LiteHTML

public struct HTMLBubbleTile {
    public let rect: CGRect
    private let cgImage: CGImage?
    let buffer: HTMLBubbleGPUBuffer?

    init(rect: CGRect, image: CGImage) {
        self.rect = rect
        self.cgImage = image
        self.buffer = nil
    }

    init(rect: CGRect, buffer: HTMLBubbleGPUBuffer) {
        self.rect = rect
        self.cgImage = nil
        self.buffer = buffer
    }

    public var image: CGImage {
        if let cgImage = cgImage {
            return cgImage
        }
        return buffer?.image ?? HTMLBubbleTile.empty
    }

    public var contents: AnyObject {
        if let cgImage = cgImage {
            return cgImage
        }
        if let buffer = buffer {
            return buffer.surface
        }
        return HTMLBubbleTile.empty
    }

    var byteCount: Int {
        if let cgImage = cgImage {
            return cgImage.bytesPerRow * cgImage.height
        }
        return (buffer?.surface.bytesPerRow ?? 0) * (buffer?.height ?? 0)
    }

    private static let empty: CGImage = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!.makeImage()!
}

public final class HTMLBubbleRendering {
    public let key: String
    public let version: Int
    public let size: NSSize
    public let tiles: [HTMLBubbleTile]
    let layoutKey: String
    let displayList: LHDisplayList?
    let document: LHDocument?
    let pinTop: CGRect
    let pinBottom: CGRect

    init(key: String, version: Int, size: NSSize, tiles: [HTMLBubbleTile], layoutKey: String, displayList: LHDisplayList?, document: LHDocument? = nil, pinTop: CGRect = .null, pinBottom: CGRect = .null) {
        self.key = key
        self.version = version
        self.size = size
        self.tiles = tiles
        self.layoutKey = layoutKey
        self.displayList = displayList
        self.document = document
        self.pinTop = pinTop
        self.pinBottom = pinBottom
    }
}

public enum HTMLBubbleRenderer {
    public static let queue = DispatchQueue(label: "org.telegram.HTMLBubbleRenderer", qos: .userInitiated, attributes: .concurrent)

    private static let tileHeight: CGFloat = 64
    private static let eagerPixelLimit: CGFloat = 3_000_000

    public static func render(state: HTMLBubbleState, appearance: HTMLBubbleAppearance, width: CGFloat, scale: CGFloat, colorSpace: CGColorSpace? = nil, previous: HTMLBubbleRendering? = nil) -> HTMLBubbleRendering {
        let spaceKey = colorSpace.map { ($0.name as String?) ?? "\(ObjectIdentifier($0))" } ?? "srgb"
        let layoutKey = "\(appearance.key)|\(Int(width))|\(scale)|\(spaceKey)"
        if state.engine.usesWidgetSandbox {
            let key = state.renderKey(width: width, appearance: appearance, scale: scale)
            return HTMLBubbleRendering(key: key, version: state.contentVersion, size: state.twidgetSize(width: width), tiles: [], layoutKey: layoutKey, displayList: nil)
        }
        let start = HTMLProcessUsage.threadCPUNanoseconds()
        defer {
            state.renderStats.record(cpuNanoseconds: HTMLProcessUsage.threadCPUNanoseconds() - start)
        }
        if state.engine == .litehtmlGPU, let rendering = renderGPU(state: state, appearance: appearance, width: width, scale: scale, previous: previous) {
            return rendering
        }
        let (version, document) = state.versionedDocument(for: appearance)
        document.colorSpace = colorSpace
        let key = state.renderKey(version: version, width: width, appearance: appearance, scale: scale)
        let size = state.resolveLayout(document, width: width)
        let incremental = state.engine != .litehtmlBefore
        let tileHeight = state.engine == .litehtmlBefore ? 1024 : self.tileHeight
        let displayList = incremental ? document.displayList(maxWidth: width, scale: scale) : nil
        var reusable: (tiles: [HTMLBubbleTile], changed: [CGRect])?
        if let displayList = displayList, let previous = previous, let previousList = previous.displayList, previous.layoutKey == layoutKey, previous.size == size {
            reusable = (previous.tiles, displayList.changedRects(since: previousList).map { $0.rectValue })
        }
        var tiles: [HTMLBubbleTile] = []
        var y: CGFloat = 0
        while y < size.height {
            let height = min(tileHeight, size.height - y)
            let rect = CGRect(x: 0, y: y, width: size.width, height: height)
            let index = tiles.count
            if let reusable = reusable, index < reusable.tiles.count, reusable.tiles[index].rect == rect {
                let old = reusable.tiles[index]
                let dirty = reusable.changed.reduce(CGRect.null) { $1.intersects(rect) ? $0.union($1.intersection(rect)) : $0 }
                if dirty.isNull {
                    tiles.append(old)
                } else if let image = document.copyImage(maxWidth: width, rect: rect, scale: scale) {
                    tiles.append(HTMLBubbleTile(rect: rect, image: image))
                }
            } else if let image = document.copyImage(maxWidth: width, rect: rect, scale: scale) {
                tiles.append(HTMLBubbleTile(rect: rect, image: image))
            }
            y += height
        }
        let pinTop = state.mayHavePins ? document.bounds(matching: "[data-pin=top]") : .null
        let pinBottom = state.mayHavePins ? document.bounds(matching: "[data-pin=bottom]") : .null
        return HTMLBubbleRendering(key: key, version: version, size: size, tiles: tiles, layoutKey: layoutKey, displayList: displayList, document: document, pinTop: pinTop, pinBottom: pinBottom)
    }

    private static func renderGPU(state: HTMLBubbleState, appearance: HTMLBubbleAppearance, width: CGFloat, scale: CGFloat, previous: HTMLBubbleRendering?) -> HTMLBubbleRendering? {
        let space = HTMLBubbleGPU.colorSpace
        let layoutKey = "\(appearance.key)|\(Int(width))|\(scale)|gpu"
        let (version, document) = state.versionedDocument(for: appearance)
        document.colorSpace = space
        let key = state.renderKey(version: version, width: width, appearance: appearance, scale: scale)
        let size = state.resolveLayout(document, width: width)
        return HTMLBubbleGPU.shared.perform { renderer -> HTMLBubbleRendering in
            let list = document.displayList(maxWidth: width, gpu: renderer, scale: scale)
            var rects: [CGRect] = []
            var y: CGFloat = 0
            while y < size.height {
                rects.append(CGRect(x: 0, y: y, width: size.width, height: min(tileHeight, size.height - y)))
                y += tileHeight
            }
            var changed: [CGRect]?
            if let previous = previous, let previousList = previous.displayList, previous.layoutKey == layoutKey, previous.size == size {
                changed = list.changedRects(since: previousList).map { $0.rectValue }
            }
            var tiles: [HTMLBubbleTile?] = []
            var dirty: [Int] = []
            for (index, rect) in rects.enumerated() {
                if let previous = previous, let changed = changed, index < previous.tiles.count, previous.tiles[index].rect == rect, !changed.contains(where: { $0.intersects(rect) }) {
                    tiles.append(previous.tiles[index])
                } else {
                    tiles.append(nil)
                    dirty.append(index)
                }
            }
            state.gpuPool.trim(to: rects.count)
            if !dirty.isEmpty {
                var buffers: [HTMLBubbleGPUBuffer] = []
                if list.gpuSupported {
                    for index in dirty {
                        let rect = rects[index]
                        guard let buffer = state.gpuPool.take(index: index, width: Int((rect.width * scale).rounded(.up)), height: Int((rect.height * scale).rounded(.up)), device: renderer.device) else {
                            break
                        }
                        buffers.append(buffer)
                    }
                }
                if buffers.count == dirty.count, let commandBuffer = renderer.queue.makeCommandBuffer(),
                   renderer.encode(list, tiles: dirty.map { NSValue(rect: rects[$0]) }, scale: scale, targets: buffers.map { $0.texture }, commandBuffer: commandBuffer) {
                    commandBuffer.commit()
                    commandBuffer.waitUntilCompleted()
                    for (index, buffer) in zip(dirty, buffers) {
                        tiles[index] = HTMLBubbleTile(rect: rects[index], buffer: buffer)
                    }
                } else {
                    for index in dirty {
                        if let image = document.copyImage(maxWidth: width, rect: rects[index], scale: scale) {
                            tiles[index] = HTMLBubbleTile(rect: rects[index], image: image)
                        }
                    }
                }
                renderer.endFrame()
            }
            let pinTop = state.mayHavePins ? document.bounds(matching: "[data-pin=top]") : .null
            let pinBottom = state.mayHavePins ? document.bounds(matching: "[data-pin=bottom]") : .null
            return HTMLBubbleRendering(key: key, version: version, size: size, tiles: tiles.compactMap { $0 }, layoutKey: layoutKey, displayList: list, document: document, pinTop: pinTop, pinBottom: pinBottom)
        }
    }

    public static func renderEagerly(state: HTMLBubbleState, appearance: HTMLBubbleAppearance, width: CGFloat, scale: CGFloat) -> HTMLBubbleRendering? {
        let size = state.layout(width: width, appearance: appearance)
        if size.width * size.height * scale * scale > eagerPixelLimit {
            return nil
        }
        return render(state: state, appearance: appearance, width: width, scale: scale)
    }
}
