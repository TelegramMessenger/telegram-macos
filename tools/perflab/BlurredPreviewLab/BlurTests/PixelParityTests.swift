import XCTest
import Cocoa
import ImageIO
import CoreServices
import TGUIKit
import NativeBlur

final class PixelParityTests: XCTestCase {
    private func assertParity(_ image: CGImage, file: StaticString = #filePath, line: UInt = #line) {
        autoreleasepool {
            let firstReference = NativeBlur.renderReference(image)
            let secondReference = NativeBlur.renderReference(image)
            let current = NativeBlur.renderBlur(image)
            assertMatching(firstReference, secondReference, file: file, line: line)
            assertMatching(firstReference, current, file: file, line: line)
        }
    }

    private func assertMatching(_ expected: CGImage, _ actual: CGImage, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.width, expected.width, file: file, line: line)
        XCTAssertEqual(actual.height, expected.height, file: file, line: line)
        XCTAssertEqual(actual.bytesPerRow, expected.bytesPerRow, file: file, line: line)
        XCTAssertEqual(actual.bitsPerPixel, expected.bitsPerPixel, file: file, line: line)
        XCTAssertEqual(actual.bitsPerComponent, expected.bitsPerComponent, file: file, line: line)
        XCTAssertEqual(actual.alphaInfo, expected.alphaInfo, file: file, line: line)
        XCTAssertEqual(actual.bitmapInfo, expected.bitmapInfo, file: file, line: line)
        XCTAssertEqual(actual.shouldInterpolate, expected.shouldInterpolate, file: file, line: line)
        if let actualSpace = actual.colorSpace, let expectedSpace = expected.colorSpace {
            XCTAssertTrue(CFEqual(actualSpace, expectedSpace), file: file, line: line)
        } else {
            XCTAssertNil(actual.colorSpace, file: file, line: line)
            XCTAssertNil(expected.colorSpace, file: file, line: line)
        }
        XCTAssertEqual(pixelBytes(actual), pixelBytes(expected), file: file, line: line)
    }

    func testOpaqueDimensionsColorsAndBackingScalesMatchReference() throws {
        let previousScale = System.backingScale
        defer { System.updateScaleFactor(previousScale) }
        let spaces = [CGColorSpaceCreateDeviceRGB(), try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3))]
        let sizes = [(64, 64), (500, 500), (720, 720), (500, 720), (720, 500), (511, 733), (733, 511)]
        for scale in [CGFloat(1), CGFloat(2)] {
            System.updateScaleFactor(scale)
            for space in spaces {
                for (index, size) in sizes.enumerated() {
                    assertParity(fixtureImage(width: size.0, height: size.1, seed: UInt32(index + 1), colorSpace: space))
                }
            }
        }
    }

    func testLazyJpegDecodedSourceMatchesReference() throws {
        let previousScale = System.backingScale
        defer { System.updateScaleFactor(previousScale) }
        for scale in [CGFloat(1), CGFloat(2)] {
            System.updateScaleFactor(scale)
            let encoded = NSMutableData()
            let destination = try XCTUnwrap(CGImageDestinationCreateWithData(encoded, kUTTypeJPEG, 1, nil))
            CGImageDestinationAddImage(destination, fixtureImage(width: 733, height: 511, seed: 191), [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            let source = try XCTUnwrap(CGImageSourceCreateWithData(encoded, [kCGImageSourceShouldCache: false] as CFDictionary))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false, kCGImageSourceShouldCacheImmediately: false] as CFDictionary))
            assertParity(image)
        }
    }

    func testReturnedPixelsRemainValidAfterSourceAndAutoreleasePoolAreReleased() {
        let previousScale = System.backingScale
        defer { System.updateScaleFactor(previousScale) }
        System.updateScaleFactor(2)
        weak var releasedSource: CGImage?
        let result: (CGImage, Data) = autoreleasepool {
            let source = fixtureImage(width: 500, height: 720, seed: 81)
            releasedSource = source
            let image = NativeBlur.renderBlur(source)
            return (image, pixelBytes(image))
        }
        XCTAssertNil(releasedSource)
        XCTAssertFalse(result.1.isEmpty)
        XCTAssertEqual(pixelBytes(result.0), result.1)
    }

    func testRenderingPreservesCurrentAppKitGraphicsContext() throws {
        let previousScale = System.backingScale
        let previousContext = NSGraphicsContext.current
        defer {
            System.updateScaleFactor(previousScale)
            NSGraphicsContext.current = previousContext
        }
        System.updateScaleFactor(2)
        let image = fixtureImage(width: 500, height: 500, seed: 43)
        let bitmap = NSBitmapImageRep(cgImage: fixtureImage(width: 64, height: 64))
        let sentinel = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.current = sentinel
        _ = NativeBlur.renderReference(image)
        XCTAssertTrue(NSGraphicsContext.current === sentinel)
        _ = NativeBlur.renderBlur(image)
        XCTAssertTrue(NSGraphicsContext.current === sentinel)
    }
}
