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

    func testUncappedPortraitDoesNotForceWideChatBubble() {
        // Before the fix, centering a 120pt image in a 320pt column
        // moved its right edge to 220pt, inflating fitToWidth's maxX.
        let mediaWidth: CGFloat = 120
        let x = instantPageV2MediaOriginX(
            horizontalInset: 0,
            availableWidth: 320,
            mediaWidth: mediaWidth,
            bleedAmount: 0,
            shrinkToContent: true
        )
        XCTAssertEqual(x, 0)
        XCTAssertEqual(x + mediaWidth, 120)
    }

    func testHeightCappedPortraitAlsoStartsAtContentOrigin() {
        let size = instantPageV2FittedMediaSize(
            CGSize(width: 1080, height: 2400),
            availableWidth: 320,
            maxHeight: 320
        )
        let x = instantPageV2MediaOriginX(
            horizontalInset: 5,
            availableWidth: 320,
            mediaWidth: size.width,
            bleedAmount: 0,
            shrinkToContent: true
        )
        XCTAssertEqual(size, CGSize(width: 144, height: 320))
        XCTAssertEqual(x, 5)
    }

    func testHeightCappedNonChatPortraitRemainsCentered() {
        // A height cap changes the displayed dimensions, but not the
        // alignment policy for a regular Instant View page.
        let size = instantPageV2FittedMediaSize(
            CGSize(width: 1080, height: 2400),
            availableWidth: 320,
            maxHeight: 320
        )
        let x = instantPageV2MediaOriginX(
            horizontalInset: 5,
            availableWidth: 320,
            mediaWidth: size.width,
            bleedAmount: 0,
            shrinkToContent: false
        )
        XCTAssertEqual(size, CGSize(width: 144, height: 320))
        XCTAssertEqual(x, 93)
    }

    func testOrdinaryInstantViewStillCentersNarrowMedia() {
        let x = instantPageV2MediaOriginX(
            horizontalInset: 0,
            availableWidth: 320,
            mediaWidth: 120,
            bleedAmount: 0,
            shrinkToContent: false
        )
        XCTAssertEqual(x, 100)
    }

    func testFullBleedMediaKeepsBleedOrigin() {
        let x = instantPageV2MediaOriginX(
            horizontalInset: 0,
            availableWidth: 340,
            mediaWidth: 340,
            bleedAmount: 10,
            shrinkToContent: true
        )
        XCTAssertEqual(x, -10)
    }
}
