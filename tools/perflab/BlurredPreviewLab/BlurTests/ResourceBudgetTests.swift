import XCTest
import TGUIKit
import TrackedBlur

final class ResourceBudgetTests: XCTestCase {
    func testBlurredPreviewOnlyAllocatesThumbnailSizedCanvases() {
        let previousScale = System.backingScale
        defer { System.updateScaleFactor(previousScale) }
        System.updateScaleFactor(2)
        let image = fixtureImage(width: 500, height: 500)
        resetCanvasAllocations()
        let result = renderBlur(image)
        XCTAssertEqual(result.width, 50)
        XCTAssertEqual(result.height, 50)
        let allocations = canvasAllocations()
        XCTAssertFalse(allocations.isEmpty)
        XCTAssertLessThanOrEqual(allocations.max()!, 50 * 224)
    }

    func testNativeCanvasAllocationsDecreaseAcrossSizesAndScales() throws {
        let previousScale = System.backingScale
        defer { System.updateScaleFactor(previousScale) }
        for scale in [CGFloat(1), CGFloat(2)] {
            System.updateScaleFactor(scale)
            for (width, height) in [(50, 50), (64, 64), (500, 500), (720, 720), (1280, 720), (1920, 1080)] {
                try autoreleasepool {
                    let source = fixtureImage(width: width, height: height)
                    resetCanvasAllocations()
                    let reference = renderReference(source)
                    let before = canvasAllocations()
                    resetCanvasAllocations()
                    let current = renderBlur(source)
                    let after = canvasAllocations()
                    XCTAssertEqual(pixelBytes(reference), pixelBytes(current))
                    XCTAssertLessThan(after.reduce(0, +), before.reduce(0, +))
                    XCTAssertLessThanOrEqual(after.max()!, 50 * 224)
                    let record: [String: Any] = ["width": width, "height": height, "scale": scale, "baselineCanvasBytes": before.reduce(0, +), "currentCanvasBytes": after.reduce(0, +)]
                    let data = try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])
                    print("NATIVE_CANVAS " + String(decoding: data, as: UTF8.self))
                }
            }
        }
    }
}
