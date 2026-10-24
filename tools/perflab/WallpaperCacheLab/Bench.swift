import AppKit
import ImageIO
import CryptoKit
import Darwin

final class WeakImage {
    weak var image: NSImage?
    let bytes: Int
    init(_ image: NSImage, bytes: Int) { self.image = image; self.bytes = bytes }
}

func footprint() -> Int {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    precondition(result == KERN_SUCCESS)
    return Int(info.phys_footprint)
}

func makeFixture(_ id: Int, directory: URL) {
    let width = 2080
    let height = 3160
    let count = width * height
    let pixels = UnsafeMutablePointer<UInt32>.allocate(capacity: count)
    var seed = UInt32(id + 1)
    for pixel in 0..<count {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        let x = pixel % width
        let y = pixel / width
        let r = UInt32((x / 16 + id * 19) % 256)
        let g = UInt32((y / 16 + id * 37) % 256)
        let b = UInt32((x / 32 + y / 32 + Int(seed % 32)) % 256)
        pixels[pixel] = r | (g << 8) | (b << 16) | 0xff000000
    }
    let provider = CGDataProvider(dataInfo: nil, data: pixels, size: count * 4, releaseData: { _, data, _ in
        data.assumingMemoryBound(to: UInt32.self).deallocate()
    })!
    let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
    let url = directory.appendingPathComponent("\(id).jpg")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.jpeg" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    precondition(CGImageDestinationFinalize(destination))
}

func fingerprint(_ image: NSImage, full: Bool = false) -> String {
    let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    if full {
        return SHA256.hash(data: bitmap.dataProvider!.data! as Data).map { String(format: "%02x", $0) }.joined()
    }
    let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(bitmap, in: CGRect(x: 0, y: 0, width: 64, height: 64))
    return SHA256.hash(data: Data(bytes: context.data!, count: 64 * 256)).map { String(format: "%02x", $0) }.joined()
}

let scenario = CommandLine.arguments[1]
let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
if scenario == "fixtures" {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for id in 0..<20 {
        autoreleasepool { makeFixture(id, directory: directory) }
    }
    print("20 deterministic 2080x3160 JPEG files")
    exit(0)
}

autoreleasepool {
    let warmup = downsampledImage(contentsOfFile: directory.appendingPathComponent("0.jpg").path, maxPixelSize: 132)!
    _ = fingerprint(warmup)
}
let cache = WallpaperCache(20)
var weakImages: [WeakImage] = []
var owner: NSImage?
var hashes: [String: String] = [:]
var hits = 0
var decodes = 0
var decodeNanoseconds: UInt64 = 0
var cacheNanoseconds: UInt64 = 0
let ids: [Int]
switch scenario {
case "recent": ids = (0..<100).map { $0 % 2 }
case "thumbnails": ids = (0..<100).map { $0 % 20 }
case "revisit": ids = Array(0..<12) + Array(0..<12)
case "verify": ids = Array(0..<20)
default: ids = Array(0..<12)
}
let initial = footprint()
for (step, id) in ids.enumerated() {
    autoreleasepool {
        let key = PhotoCacheKeyEntry(id: id)
        let start = DispatchTime.now().uptimeNanoseconds
        let cached = cache.cachedImage(for: key)
        cacheNanoseconds += DispatchTime.now().uptimeNanoseconds - start
        let image: NSImage
        if case let .background(value, _, _, _, _) = cached {
            hits += 1
            image = value
        } else {
            let begin = DispatchTime.now().uptimeNanoseconds
            image = downsampledImage(contentsOfFile: directory.appendingPathComponent("\(id).jpg").path, maxPixelSize: scenario == "thumbnails" ? 132 : 3160)!
            decodeNanoseconds += DispatchTime.now().uptimeNanoseconds - begin
            decodes += 1
            let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
            weakImages.append(WeakImage(image, bytes: bitmap.bytesPerRow * bitmap.height))
            let insertion = DispatchTime.now().uptimeNanoseconds
            cache.cacheImage(.background(image: image, intensity: nil, colors: nil, rotation: nil, metadata: nil), for: key)
            cacheNanoseconds += DispatchTime.now().uptimeNanoseconds - insertion
        }
        if scenario == "active-owner", step == 0 { owner = image }
        let hash = fingerprint(image, full: scenario == "verify")
        if let previous = hashes[String(id)] { precondition(hash == previous) }
        hashes[String(id)] = hash
    }
}
usleep(100000)
let held = footprint()
let alive = weakImages.filter { $0.image != nil }
let bitmapBytes = alive.reduce(0) { $0 + $1.bytes }
let liveCount = alive.count
cache.clearAll()
usleep(100000)
let liveAfterClear = weakImages.filter { $0.image != nil }.count
let cleared = footprint()
let output: [String: Any] = ["scenario": scenario, "requests": ids.count, "hits": hits, "decodes": decodes,
    "decode_ms": Double(decodeNanoseconds) / 1_000_000, "cache_ms": Double(cacheNanoseconds) / 1_000_000,
    "live_images": liveCount, "retained_bitmap_bytes": bitmapBytes, "footprint_delta": held - initial,
    "footprint_after_clear_delta": cleared - initial, "live_after_clear": liveAfterClear, "render_hashes": hashes]
withExtendedLifetime(owner) {}
print(String(data: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys, .prettyPrinted]), encoding: .utf8)!)
