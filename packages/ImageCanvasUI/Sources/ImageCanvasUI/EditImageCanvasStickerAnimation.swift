import Cocoa
import AVFoundation
import TGUIKit
import SwiftSignalKit
import TelegramMedia
import TelegramMediaPlayer

public struct EditImageCanvasStickerAnimation: Equatable {
    public enum Kind: Equatable {
        case lottie
        case webm
        case video
    }
    public let kind: Kind
    public let path: String

    public init(kind: Kind, path: String) {
        self.kind = kind
        self.path = path
    }
}

let editImageCanvasAnimationFps: Int = 30

final class EditImageCanvasStickerFrameSource {
    let frameCount: Int
    private let render: (Int) -> CGImage?

    init?(animation: EditImageCanvasStickerAnimation, size: CGSize) {
        switch animation.kind {
        case .lottie:
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: animation.path)) else {
                return nil
            }
            let lottie = LottieAnimation(compressed: data, key: .init(key: .bundle("edit_canvas_\(animation.path)"), size: size, backingScale: 1), type: .lottie, cachePurpose: .none)
            guard let container = lottie.initialize(), container.endFrame > container.startFrame, container.mainFps > 0 else {
                return nil
            }
            let startFrame = container.startFrame
            let endFrame = container.endFrame
            let fps = Double(container.mainFps)
            self.frameCount = max(1, Int(Double(endFrame - startFrame) / fps * Double(editImageCanvasAnimationFps)))
            self.render = { index in
                let frame = min(endFrame - 1, startFrame + Int32(Double(index) * fps / Double(editImageCanvasAnimationFps)))
                return container.render(at: frame, frames: [], previousFrame: nil)?.image
            }
        case .webm:
            guard let reader = EditImageCanvasWebmReader(path: animation.path) else {
                return nil
            }
            self.frameCount = reader.frameCount
            self.render = { index in
                return reader.image(at: index)
            }
        case .video:
            guard let reader = EditImageCanvasVideoReader(path: animation.path) else {
                return nil
            }
            self.frameCount = reader.frameCount
            self.render = { index in
                return reader.image(at: index)
            }
        }
    }

    func image(at index: Int) -> CGImage? {
        return render(index % frameCount)
    }
}

private final class EditImageCanvasWebmReader {
    private let path: String
    private var source: SoftwareVideoSource
    private var position: Int = -1
    private var reachedEnd = false
    private var current: CGImage?
    private let fps: Double
    let frameCount: Int

    init?(path: String) {
        self.path = path
        let counter = SoftwareVideoSource(path: path, hintVP9: true, unpremultiplyAlpha: false)
        var count = 0
        var lastPosition: Double = 0
        while count < 1800 {
            let (frame, _, _, loop) = counter.readFrame(maxPts: nil)
            guard let frame = frame else {
                break
            }
            count += 1
            let position = frame.position.seconds
            if position.isFinite {
                lastPosition = max(lastPosition, position)
            }
            if loop {
                break
            }
        }
        guard count > 0 else {
            return nil
        }
        let reportedFps = Double(counter.getFramerate())
        let fps: Double
        if reportedFps > 0 {
            fps = reportedFps
        } else if count > 1, lastPosition > 0 {
            fps = Double(count - 1) / lastPosition
        } else {
            fps = Double(editImageCanvasAnimationFps)
        }
        self.fps = fps
        self.source = SoftwareVideoSource(path: path, hintVP9: true, unpremultiplyAlpha: false)
        self.frameCount = max(1, Int((Double(count) / fps * Double(editImageCanvasAnimationFps)).rounded()))
    }

    func image(at index: Int) -> CGImage? {
        let target = Int(Double(index) * fps / Double(editImageCanvasAnimationFps))
        if target < position {
            source = SoftwareVideoSource(path: path, hintVP9: true, unpremultiplyAlpha: false)
            position = -1
            reachedEnd = false
        }
        while position < target, !reachedEnd {
            let (frame, _, _, loop) = source.readFrame(maxPts: nil)
            guard let frame = frame else {
                reachedEnd = true
                break
            }
            position += 1
            reachedEnd = loop
            if position == target || loop {
                current = makeImage(frame)
            }
        }
        return current
    }

    private func makeImage(_ frame: MediaTrackFrame) -> CGImage? {
        guard let buffer = CMSampleBufferGetImageBuffer(frame.sampleBuffer) else {
            return nil
        }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        }
        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return context?.makeImage()
    }
}

private func editImageCanvasVideoAsset(path: String) -> AVURLAsset {
    let link = NSTemporaryDirectory() + "edit_canvas_\(UInt(bitPattern: path.hashValue)).mp4"
    if !FileManager.default.fileExists(atPath: link) {
        try? FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: path)
    }
    return AVURLAsset(url: URL(fileURLWithPath: link))
}

public func editImageCanvasVideoPreview(path: String) -> CGImage? {
    let generator = AVAssetImageGenerator(asset: editImageCanvasVideoAsset(path: path))
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = NSMakeSize(1024, 1024)
    return try? generator.copyCGImage(at: .zero, actualTime: nil)
}

private final class EditImageCanvasVideoReader {
    private let asset: AVURLAsset
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var position: Int = -1
    private var current: CGImage?
    private let fps: Double
    let frameCount: Int

    init?(path: String) {
        self.asset = editImageCanvasVideoAsset(path: path)
        guard let track = asset.tracks(withMediaType: .video).first, asset.duration.seconds > 0 else {
            return nil
        }
        let fps = Double(track.nominalFrameRate)
        self.fps = fps > 0 ? fps : Double(editImageCanvasAnimationFps)
        self.frameCount = max(1, Int(asset.duration.seconds * Double(editImageCanvasAnimationFps)))
    }

    private func restart() {
        reader?.cancelReading()
        reader = nil
        output = nil
        position = -1
        guard let track = asset.tracks(withMediaType: .video).first, let reader = try? AVAssetReader(asset: asset) else {
            return
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            return
        }
        reader.add(output)
        guard reader.startReading() else {
            return
        }
        self.reader = reader
        self.output = output
    }

    func image(at index: Int) -> CGImage? {
        let target = Int(Double(index) * fps / Double(editImageCanvasAnimationFps))
        if target < position || output == nil {
            restart()
        }
        while position < target, let output = output {
            guard let sample = output.copyNextSampleBuffer() else {
                break
            }
            position += 1
            if position == target, let buffer = CMSampleBufferGetImageBuffer(sample) {
                current = makeImage(buffer)
            }
        }
        return current
    }

    private func makeImage(_ buffer: CVImageBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(buffer, .readOnly)
        }
        let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer), bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        return context?.makeImage()
    }

    deinit {
        reader?.cancelReading()
    }
}

func editImageCanvasStickerRenderSize(_ sticker: EditImageCanvasEntity.Sticker, side: CGFloat) -> CGSize {
    let side = max(64, min(1024, side))
    let size = sticker.baseSize.aspectFitted(NSMakeSize(side, side))
    return NSMakeSize(max(1, round(size.width)), max(1, round(size.height)))
}

final class EditImageCanvasStickerAnimator {
    private struct Item: Equatable {
        let animation: EditImageCanvasStickerAnimation
        let size: CGSize
    }

    private final class Sources {
        var values: [Int64: (Item, EditImageCanvasStickerFrameSource?)] = [:]
    }

    private let queue = Queue(name: "EditImageCanvasStickerAnimator")
    private let sources = Sources()
    private var items: [Int64: Item] = [:]
    private var timer: SwiftSignalKit.Timer?
    private var startTime: Double = CACurrentMediaTime()
    private var rendering = false
    var isActive: Bool = false {
        didSet {
            if oldValue != isActive {
                updateTimer()
            }
        }
    }
    var updated: (([Int64: CGImage]) -> Void)?

    func update(entities: [EditImageCanvasEntity]) {
        var items: [Int64: Item] = [:]
        for entity in entities {
            if case let .sticker(sticker) = entity.content, let animation = sticker.animation {
                items[entity.id] = Item(animation: animation, size: editImageCanvasStickerRenderSize(sticker, side: 512))
            }
        }
        guard items != self.items else {
            return
        }
        self.items = items
        updateTimer()
        if items.isEmpty {
            updated?([:])
        }
    }

    private func updateTimer() {
        if isActive, !items.isEmpty {
            if timer == nil {
                let timer = SwiftSignalKit.Timer(timeout: 1.0 / Double(editImageCanvasAnimationFps), repeat: true, completion: { [weak self] in
                    self?.tick()
                }, queue: .mainQueue())
                self.timer = timer
                timer.start()
            }
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private func tick() {
        guard !rendering else {
            return
        }
        rendering = true
        let items = self.items
        let index = Int((CACurrentMediaTime() - startTime) * Double(editImageCanvasAnimationFps))
        let sources = self.sources
        queue.async { [weak self] in
            var images: [Int64: CGImage] = [:]
            sources.values = sources.values.filter { items[$0.key] == $0.value.0 }
            for (id, item) in items {
                let source: EditImageCanvasStickerFrameSource?
                if let current = sources.values[id] {
                    source = current.1
                } else {
                    source = EditImageCanvasStickerFrameSource(animation: item.animation, size: item.size)
                    sources.values[id] = (item, source)
                }
                if let image = source?.image(at: index) {
                    images[id] = image
                }
            }
            Queue.mainQueue().async {
                guard let self else {
                    return
                }
                self.rendering = false
                if self.items == items {
                    self.updated?(images)
                }
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
}

func editImageCanvasWriteVideo<Frame>(size: CGSize, frameCount: Int, isCancelled: () -> Bool, prepare: (Range<Int>) -> [Frame], render: (Frame) -> CGImage?) -> URL? {
    let url = URL(fileURLWithPath: NSTemporaryDirectory() + "edited_\(UUID().uuidString).mp4")
    let width = Int(size.width)
    let height = Int(size.height)
    guard width > 0, height > 0, frameCount > 0, let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
        return nil
    }
    let settings: [String: Any] = [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: max(2000000, width * height * 4)]
    ]
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
    input.expectsMediaDataInRealTime = false
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height
    ])
    guard writer.canAdd(input) else {
        return nil
    }
    writer.add(input)
    guard writer.startWriting() else {
        return nil
    }
    writer.startSession(atSourceTime: .zero)

    let fail: () -> URL? = {
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: url)
        return nil
    }

    let batchSize = max(1, min(8, ProcessInfo.processInfo.activeProcessorCount))
    for batchStart in stride(from: 0, to: frameCount, by: batchSize) {
        if isCancelled() {
            return fail()
        }
        let range = batchStart ..< min(frameCount, batchStart + batchSize)
        let batch = Array(range)
        let frames = prepare(range)
        var images = [CGImage?](repeating: nil, count: batch.count)
        let lock = NSLock()
        DispatchQueue.concurrentPerform(iterations: batch.count) { offset in
            let image = autoreleasepool {
                render(frames[offset])
            }
            lock.lock()
            images[offset] = image
            lock.unlock()
        }
        for (offset, index) in batch.enumerated() {
            let appended: Bool = autoreleasepool {
                guard let image = images[offset], let pool = adaptor.pixelBufferPool else {
                    return false
                }
                var pixelBuffer: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
                guard let buffer = pixelBuffer else {
                    return false
                }
                CVPixelBufferLockBaseAddress(buffer, [])
                let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
                let rect = CGRect(x: 0, y: 0, width: width, height: height)
                context?.setFillColor(NSColor.black.cgColor)
                context?.fill(rect)
                context?.interpolationQuality = .high
                context?.draw(image, in: rect)
                CVPixelBufferUnlockBaseAddress(buffer, [])
                while !input.isReadyForMoreMediaData, writer.status == .writing {
                    Thread.sleep(forTimeInterval: 0.005)
                }
                return writer.status == .writing && adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: Int32(editImageCanvasAnimationFps)))
            }
            if !appended {
                return fail()
            }
        }
    }
    input.markAsFinished()
    writer.endSession(atSourceTime: CMTime(value: Int64(frameCount), timescale: Int32(editImageCanvasAnimationFps)))
    let semaphore = DispatchSemaphore(value: 0)
    writer.finishWriting {
        semaphore.signal()
    }
    semaphore.wait()
    guard writer.status == .completed else {
        try? FileManager.default.removeItem(at: url)
        return nil
    }
    return url
}
