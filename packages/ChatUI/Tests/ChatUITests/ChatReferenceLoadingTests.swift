import AppKit
import XCTest
import ChatHistoryModel
import TGUIKit
@testable import ChatUI

final class ChatReferenceLoadingTests: XCTestCase {
    override func setUp() { super.setUp(); UITestBootstrap.install() }

    func testPendingMissingReferenceDoesNotPretendToBeDeleted() {
        XCTAssertEqual(ChatReferenceAvailability.resolve(hasContent: false, referencesPending: true), .loading)
        XCTAssertEqual(ChatReferenceAvailability.resolve(hasContent: false, referencesPending: false), .unavailable)
    }

    func testResolvedReferenceWinsWhileAnotherReferenceIsPending() {
        XCTAssertEqual(ChatReferenceAvailability.resolve(hasContent: true, referencesPending: true), .available)
        XCTAssertEqual(ChatReferenceAvailability.resolve(hasContent: true, referencesPending: false), .available)
    }

    func testFollowUpEitherReplacesSkeletonOrReleasesTheMissingState() {
        let success = [(false, true), (true, true), (true, false)].map { ChatReferenceAvailability.resolve(hasContent: $0.0, referencesPending: $0.1) }
        let absent = [(false, true), (false, false)].map { ChatReferenceAvailability.resolve(hasContent: $0.0, referencesPending: $0.1) }
        XCTAssertEqual(success, [.loading, .available, .available])
        XCTAssertEqual(absent, [.loading, .unavailable])
    }

    func testQuoteKeepsItsTextLineClearAndStoriesReserveTheirSquare() {
        let size = CGSize(width: 190, height: 38)
        let plain = ChatReferenceSkeleton.frames(size: size, story: false, hasQuote: false)
        let quote = ChatReferenceSkeleton.frames(size: size, story: false, hasQuote: true)
        let story = ChatReferenceSkeleton.frames(size: size, story: true, hasQuote: false)
        XCTAssertEqual(plain.count, 2)
        XCTAssertEqual(quote.count, 1)
        XCTAssertLessThan(quote[0].maxY, 20)
        XCTAssertEqual(story.count, 3)
        XCTAssertEqual(story[0].size, CGSize(width: 30, height: 30))
        XCTAssertGreaterThanOrEqual(story[1].minX, story[0].maxX + 6)
    }

    func testNativeMaskHasVisiblePixelsAndStaysWithinNarrowAndWideBounds() throws {
        for width: CGFloat in [8, 20, 40, 80, 160, 320] {
            for story in [false, true] {
                let size = CGSize(width: width, height: 38)
                let frames = ChatReferenceSkeleton.frames(size: size, story: story, hasQuote: false)
                for frame in frames { XCTAssertTrue(CGRect(origin: .zero, size: size).contains(frame)) }
                let image = try XCTUnwrap(ChatReferenceSkeleton.image(size: size, story: story, hasQuote: false))
                XCTAssertEqual(image.width, Int(width * 2)); XCTAssertEqual(image.height, 76)
                if width >= 40 {
                    let bytes = try XCTUnwrap(image.dataProvider?.data)
                    let buffer = try XCTUnwrap(CFDataGetBytePtr(bytes))
                    var visible = 0
                    for index in stride(from: 3, to: CFDataGetLength(bytes), by: 4) { if buffer[index] > 0 { visible += 1 } }
                    XCTAssertGreaterThan(visible, 20)
                }
            }
        }
        XCTAssertNil(ChatReferenceSkeleton.image(size: .zero, story: false, hasQuote: false))
        XCTAssertNil(ChatReferenceSkeleton.image(size: CGSize(width: CGFloat.infinity, height: 38), story: false, hasQuote: false))
    }
}
