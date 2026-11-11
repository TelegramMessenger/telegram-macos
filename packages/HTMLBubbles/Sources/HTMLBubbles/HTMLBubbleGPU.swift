import Cocoa
import Metal
import IOSurface
import LiteHTML

final class HTMLBubbleGPU {
    static let shared = HTMLBubbleGPU()

    static let colorSpace = CGColorSpace(name: CGColorSpace.displayP3)!

    let renderer: LHGPURenderer?
    private let lock = NSLock()

    private init() {
        renderer = LHGPURenderer(device: nil)
    }

    func perform<T>(_ body: (LHGPURenderer) -> T) -> T? {
        guard let renderer = renderer else {
            return nil
        }
        lock.lock()
        defer { lock.unlock() }
        return body(renderer)
    }
}

public final class HTMLBubbleGPUBuffer {
    let surface: IOSurface
    let texture: MTLTexture
    private var snapshot: CGImage?

    init?(device: MTLDevice, width: Int, height: Int) {
        guard let surface = IOSurface(properties: [.width: width, .height: height, .bytesPerElement: 4, .pixelFormat: 0x42475241]) else {
            return nil
        }
        if let plist = HTMLBubbleGPU.colorSpace.copyPropertyList() {
            IOSurfaceSetValue(unsafeBitCast(surface, to: IOSurfaceRef.self), kIOSurfaceColorSpace, plist)
        }
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        desc.usage = [.renderTarget, .shaderRead]
        if #available(macOS 10.15, *), device.hasUnifiedMemory {
            desc.storageMode = .shared
        } else {
            desc.storageMode = .managed
        }
        guard let texture = device.makeTexture(descriptor: desc, iosurface: unsafeBitCast(surface, to: IOSurfaceRef.self), plane: 0) else {
            return nil
        }
        self.surface = surface
        self.texture = texture
    }

    var width: Int {
        return surface.width
    }

    var height: Int {
        return surface.height
    }

    func invalidate() {
        snapshot = nil
    }

    var image: CGImage? {
        if let snapshot = snapshot {
            return snapshot
        }
        surface.lock(options: .readOnly, seed: nil)
        defer { surface.unlock(options: .readOnly, seed: nil) }
        let data = Data(bytes: surface.baseAddress, count: surface.bytesPerRow * surface.height)
        guard let provider = CGDataProvider(data: data as CFData) else {
            return nil
        }
        let image = CGImage(width: surface.width, height: surface.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: surface.bytesPerRow, space: HTMLBubbleGPU.colorSpace,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        snapshot = image
        return image
    }
}

final class HTMLBubbleGPUPool {
    private var slots: [Int: [HTMLBubbleGPUBuffer]] = [:]

    func take(index: Int, width: Int, height: Int, device: MTLDevice) -> HTMLBubbleGPUBuffer? {
        var list = slots.removeValue(forKey: index) ?? []
        list.removeAll { $0.width != width || $0.height != height }
        var found: HTMLBubbleGPUBuffer?
        for i in list.indices where isKnownUniquelyReferenced(&list[i]) && !list[i].surface.isInUse {
            found = list[i]
            break
        }
        if found == nil, let created = HTMLBubbleGPUBuffer(device: device, width: width, height: height) {
            list.append(created)
            if list.count > 3 {
                list.removeFirst()
            }
            found = created
        }
        slots[index] = list
        found?.invalidate()
        return found
    }

    func trim(to count: Int) {
        slots = slots.filter { $0.key < count }
    }
}
