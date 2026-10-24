import XCTest
import AppKit

final class WeakImage {
    weak var value: NSImage?
    init(_ value: NSImage) { self.value = value }
}

final class WallpaperCacheTests: XCTestCase {
    func image(width: Int = 32, height: Int = 32, rowBytes: Int? = nil, pointSize: NSSize? = nil) -> NSImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: rowBytes ?? width * 4, bitsPerPixel: 32)!
        return NSImage(cgImage: bitmap.cgImage!, size: pointSize ?? NSSize(width: width, height: height))
    }

    func mode(_ image: NSImage) -> TableBackgroundMode {
        return .background(image: image, intensity: -45, colors: [.red, .blue], rotation: 90, metadata: SVG_SlotsMetadata(fixture: 42))
    }

    func testPixelCostUsesPixelsRatherThanPoints() {
        let value = image(width: 80, height: 60, pointSize: NSSize(width: 40, height: 30))
        XCTAssertEqual(WallpaperCachedRecord(mode: mode(value)).cost, 80 * 60 * 4)
    }

    func testCostIncludesRowPadding() {
        let value = image(width: 17, height: 10, rowBytes: 128)
        XCTAssertEqual(WallpaperCachedRecord(mode: .tiled(image: value)).cost, 128 * 10)
    }

    func testTiledAndBackgroundUseSameBitmapCost() {
        let value = image()
        XCTAssertEqual(WallpaperCachedRecord(mode: .tiled(image: value)).cost, WallpaperCachedRecord(mode: mode(value)).cost)
    }

    func testNonImageModesHaveNoBitmapCost() {
        for value: TableBackgroundMode in [.plain, .color(color: .red), .gradient(colors: [.blue, .green], rotation: 30)] {
            XCTAssertEqual(WallpaperCachedRecord(mode: value).cost, 0)
        }
    }

    func testRoundTripPreservesImageAndSettings() {
        let cache = WallpaperCache(20)
        let value = image()
        let original = mode(value)
        cache.cacheImage(original, for: PhotoCacheKeyEntry(id: 1))
        XCTAssertEqual(cache.cachedImage(for: PhotoCacheKeyEntry(id: 1)), original)
        if case let .background(result, _, _, _, _) = cache.cachedImage(for: PhotoCacheKeyEntry(id: 1)) {
            XCTAssertTrue(result === value)
        } else { XCTFail("Background missing") }
    }

    func testOversizedInsertKeepsExistingSmallEntry() {
        let cache = WallpaperCache(20, byteLimit: 8192)
        let small = mode(image())
        cache.cacheImage(small, for: PhotoCacheKeyEntry(id: 1))
        cache.cacheImage(mode(image(width: 64, height: 64)), for: PhotoCacheKeyEntry(id: 2))
        XCTAssertEqual(cache.cachedImage(for: PhotoCacheKeyEntry(id: 1)), small)
        XCTAssertNil(cache.cachedImage(for: PhotoCacheKeyEntry(id: 2)))
    }

    func testOversizedReplacementCannotReturnStaleMode() {
        let cache = WallpaperCache(20, byteLimit: 8192)
        let key = PhotoCacheKeyEntry(id: 1)
        cache.cacheImage(mode(image()), for: key)
        cache.cacheImage(mode(image(width: 64, height: 64)), for: key)
        XCTAssertNil(cache.cachedImage(for: key))
    }

    func testExactBudgetEntryCanBeReused() {
        let value = image()
        let cache = WallpaperCache(20, byteLimit: WallpaperCachedRecord(mode: mode(value)).cost)
        cache.cacheImage(mode(value), for: PhotoCacheKeyEntry(id: 1))
        XCTAssertEqual(cache.cachedImage(for: PhotoCacheKeyEntry(id: 1)), mode(value))
    }

    func testReplacementReleasesPreviousImage() {
        let cache = WallpaperCache(20)
        let previous: WeakImage = autoreleasepool {
            let value = image()
            cache.cacheImage(mode(value), for: PhotoCacheKeyEntry(id: 1))
            return WeakImage(value)
        }
        XCTAssertNotNil(previous.value)
        cache.cacheImage(.plain, for: PhotoCacheKeyEntry(id: 1))
        XCTAssertNil(previous.value)
        XCTAssertEqual(cache.cachedImage(for: PhotoCacheKeyEntry(id: 1)), .plain)
    }

    func testPurgeReleasesCachedImageButPreservesExternalOwner() {
        let cache = WallpaperCache(20)
        var owner: NSImage? = image()
        let weak = WeakImage(owner!)
        cache.cacheImage(mode(owner!), for: PhotoCacheKeyEntry(id: 1))
        cache.clearAll()
        XCTAssertNil(cache.cachedImage(for: PhotoCacheKeyEntry(id: 1)))
        XCTAssertNotNil(weak.value)
        owner = nil
        XCTAssertNil(weak.value)
    }

    func testPurgeReleasesCacheOnlyImages() {
        let cache = WallpaperCache(20)
        let weak: WeakImage = autoreleasepool {
            let value = image()
            cache.cacheImage(mode(value), for: PhotoCacheKeyEntry(id: 1))
            return WeakImage(value)
        }
        XCTAssertNotNil(weak.value)
        cache.clearAll()
        XCTAssertNil(weak.value)
    }

    func testConcurrentLookupInsertionAndPurge() {
        let cache = WallpaperCache(20)
        let images = (0..<16).map { image(width: 32 + $0) }
        DispatchQueue.concurrentPerform(iterations: 8) { worker in
            for step in 0..<2000 {
                autoreleasepool {
                    let id = (worker * 19 + step) % images.count
                    let key = PhotoCacheKeyEntry(id: id)
                    switch step % 3 {
                    case 0: cache.cacheImage(.tiled(image: images[id]), for: key)
                    case 1:
                        if case let .tiled(value) = cache.cachedImage(for: key) {
                            XCTAssertTrue(value === images[id])
                        }
                    default: cache.clearAll()
                    }
                }
            }
        }
        cache.clearAll()
        for id in images.indices { XCTAssertNil(cache.cachedImage(for: PhotoCacheKeyEntry(id: id))) }
    }

}
