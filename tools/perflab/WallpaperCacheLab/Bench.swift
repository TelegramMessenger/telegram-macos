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

func wallpaperID(_ wallpaper: ProbeWallpaper) -> Int {
    switch wallpaper {
    case let .image(id): return id
    case .emoticon: preconditionFailure("No emoticon fixture")
    }
}

func cachedBackground(_ wallpaper: ProbeWallpaper, palette: Int, size: NSSize) -> TableBackgroundMode? {
    let start = DispatchTime.now().uptimeNanoseconds
    let result = cache.cachedImage(for: PhotoCacheKeyEntry(id: wallpaperID(wallpaper)))
    cacheNanoseconds += DispatchTime.now().uptimeNanoseconds - start
    if result != nil { hits += 1 }
    return result
}

func cacheBackground(_ wallpaper: ProbeWallpaper, palette: Int, size: NSSize, background: TableBackgroundMode) {
    let start = DispatchTime.now().uptimeNanoseconds
    cache.cacheImage(background, for: PhotoCacheKeyEntry(id: wallpaperID(wallpaper)))
    cacheNanoseconds += DispatchTime.now().uptimeNanoseconds - start
}

func loadImage(_ id: Int, maxPixelSize: CGFloat) -> NSImage {
    let begin = DispatchTime.now().uptimeNanoseconds
    let image = downsampledImage(contentsOfFile: directory.appendingPathComponent("\(id).jpg").path, maxPixelSize: maxPixelSize)!
    decodeNanoseconds += DispatchTime.now().uptimeNanoseconds - begin
    decodes += 1
    let bitmap = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    weakImages.append(WeakImage(image, bytes: bitmap.bytesPerRow * bitmap.height))
    return image
}

func generateBackgroundMode(_ wallpaper: ProbeWallpaper, palette: Int, maxSize: NSSize, emoticonThemes: [Int]) -> TableBackgroundMode {
    return .background(image: loadImage(wallpaperID(wallpaper), maxPixelSize: 3160), intensity: nil, colors: nil, rotation: nil, metadata: nil)
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
var retainedThemes: [Int: WallpaperThemeProbe] = [:]
var requestNanoseconds: UInt64 = 0
var warmRequests: [Double] = []
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
case "live-themes": ids = Array(0..<12) + (0..<120).map { $0 % 12 }
case "released-themes", "close-themes": ids = Array(0..<12) + Array(0..<12)
case "same-themes": ids = (0..<100).map { $0 % 2 }
case "return-to-open": ids = Array(0..<13) + [0]
default: ids = Array(0..<12)
}
let initial = footprint()
for (step, id) in ids.enumerated() {
    autoreleasepool {
        if scenario == "close-themes", step == 12 { retainedThemes.removeAll() }
        let requestStart = DispatchTime.now().uptimeNanoseconds
        let image: NSImage
        if ["live-themes", "released-themes", "same-themes", "close-themes", "return-to-open"].contains(scenario) {
            let probe: WallpaperThemeProbe
            if scenario == "same-themes", let existing = retainedThemes[id] {
                probe = existing
            } else {
                probe = WallpaperThemeProbe(id)
            }
            guard case let .background(value, _, _, _, _) = probe.backgroundMode else { fatalError("Background missing") }
            image = value
            if scenario == "live-themes" || scenario == "same-themes" || (scenario == "close-themes" && step < 12) || (scenario == "return-to-open" && step == 0) {
                if retainedThemes[id] == nil { retainedThemes[id] = probe }
            }
        } else {
            let key = PhotoCacheKeyEntry(id: id)
            let start = DispatchTime.now().uptimeNanoseconds
            let cached = cache.cachedImage(for: key)
            cacheNanoseconds += DispatchTime.now().uptimeNanoseconds - start
            if case let .background(value, _, _, _, _) = cached {
                hits += 1
                image = value
            } else {
                image = loadImage(id, maxPixelSize: scenario == "thumbnails" ? 132 : 3160)
                let insertion = DispatchTime.now().uptimeNanoseconds
                cache.cacheImage(.background(image: image, intensity: nil, colors: nil, rotation: nil, metadata: nil), for: key)
                cacheNanoseconds += DispatchTime.now().uptimeNanoseconds - insertion
            }
        }
        let elapsed = DispatchTime.now().uptimeNanoseconds - requestStart
        requestNanoseconds += elapsed
        let initialRequests = scenario == "return-to-open" ? 13 : (scenario == "thumbnails" ? 20 : (scenario == "same-themes" || scenario == "recent" ? 2 : 12))
        if step >= initialRequests {
            warmRequests.append(Double(elapsed) / 1_000_000)
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
retainedThemes.removeAll()
usleep(100000)
let afterThemesClose = weakImages.filter { $0.image != nil }
let bitmapBytesAfterThemesClose = afterThemesClose.reduce(0) { $0 + $1.bytes }
let footprintAfterThemesClose = footprint()
cache.clearAll()
usleep(100000)
let liveAfterClear = weakImages.filter { $0.image != nil }.count
let cleared = footprint()
owner = nil
let liveAfterOwnersClose = weakImages.filter { $0.image != nil }.count
warmRequests.sort()
func percentile(_ fraction: Double) -> Double {
    guard !warmRequests.isEmpty else { return 0 }
    return warmRequests[min(warmRequests.count - 1, Int(ceil(Double(warmRequests.count) * fraction)) - 1)]
}
let output: [String: Any] = ["scenario": scenario, "requests": ids.count, "hits": hits, "decodes": decodes,
    "decode_ms": Double(decodeNanoseconds) / 1_000_000, "cache_ms": Double(cacheNanoseconds) / 1_000_000,
    "request_ms": Double(requestNanoseconds) / 1_000_000,
    "warm_request_p50_ms": percentile(0.5), "warm_request_p95_ms": percentile(0.95),
    "live_after_owners_close": liveAfterOwnersClose, "theme_local_hits": ids.count - hits - decodes,
    "live_after_themes_close": afterThemesClose.count, "bitmap_bytes_after_themes_close": bitmapBytesAfterThemesClose,
    "footprint_after_themes_close_delta": footprintAfterThemesClose - initial,
    "live_images": liveCount, "retained_bitmap_bytes": bitmapBytes, "footprint_delta": held - initial,
    "footprint_after_clear_delta": cleared - initial, "live_after_clear": liveAfterClear, "render_hashes": hashes]
print(String(data: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys, .prettyPrinted]), encoding: .utf8)!)
