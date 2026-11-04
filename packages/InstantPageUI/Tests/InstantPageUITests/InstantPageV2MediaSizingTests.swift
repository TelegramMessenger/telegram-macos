import Cocoa
import XCTest
@testable import InstantPageUI

final class InstantPageV2MediaSizingTests: XCTestCase {
    func testPortraitIsScaledProportionallyToHeightCap() {
        let size = instantPageV2FittedMediaSize(
            CGSize(width: 1080, height: 2400),
            availableWidth: 320,
            maxHeight: 320
        )
        XCTAssertEqual(size, CGSize(width: 144, height: 320))
    }

    func testLandscapeMediaKeepsWidthConstraint() {
        let size = instantPageV2FittedMediaSize(
            CGSize(width: 1920, height: 1080),
            availableWidth: 320,
            maxHeight: 320
        )
        XCTAssertEqual(size, CGSize(width: 320, height: 180))
    }

    func testSquareMediaKeepsOriginalAspectRatio() {
        let size = instantPageV2FittedMediaSize(
            CGSize(width: 800, height: 800),
            availableWidth: 320,
            maxHeight: 320
        )
        XCTAssertEqual(size, CGSize(width: 320, height: 320))
    }

    func testSmallMediaIsNotUpscaled() {
        let size = instantPageV2FittedMediaSize(
            CGSize(width: 90, height: 120),
            availableWidth: 320,
            maxHeight: 320
        )
        XCTAssertEqual(size, CGSize(width: 90, height: 120))
    }

    func testVeryTallMediaAlsoHonorsAbsoluteHeightCap() {
        let size = instantPageV2FittedMediaSize(
            CGSize(width: 2000, height: 8000),
            availableWidth: 1500,
            maxHeight: 1000
        )
        XCTAssertEqual(size, CGSize(width: 250, height: 1000))
    }

    func testUnknownDimensionsRetainExistingPlaceholderBehavior() {
        let size = instantPageV2FittedMediaSize(
            CGSize(width: 0, height: 0),
            availableWidth: 320,
            maxHeight: 320
        )
        XCTAssertEqual(size, CGSize(width: 320, height: 0))
    }
}
