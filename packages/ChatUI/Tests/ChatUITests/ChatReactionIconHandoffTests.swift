import XCTest
@testable import ChatUI

final class ChatReactionIconHandoffTests: XCTestCase {
    func testNoFrameKeepsOriginalVisible() {
        var hidden = false
        let handoff = ChatReactionIconHandoff(hide: { hidden = true }, show: { hidden = false })
        XCTAssertFalse(hidden)
        handoff.finish()
        XCTAssertFalse(hidden)
    }

    func testFirstDrawHidesOriginalUntilCompletion() {
        var hidden = false
        let handoff = ChatReactionIconHandoff(hide: { hidden = true }, show: { hidden = false })
        handoff.contentDidDraw(); XCTAssertTrue(hidden)
        handoff.finish(); XCTAssertFalse(hidden)
    }

    func testLateFrameAfterCancellationCannotHideOriginal() {
        var hidden = false
        let handoff = ChatReactionIconHandoff(hide: { hidden = true }, show: { hidden = false })
        handoff.finish(); handoff.contentDidDraw()
        XCTAssertFalse(hidden)
    }

    func testRepeatedFramesAndCompletionAreIdempotent() {
        var hides = 0, shows = 0
        let handoff = ChatReactionIconHandoff(hide: { hides += 1 }, show: { shows += 1 })
        handoff.contentDidDraw(); handoff.contentDidDraw(); handoff.finish(); handoff.finish(); handoff.contentDidDraw()
        XCTAssertEqual(hides, 1); XCTAssertEqual(shows, 1)
    }
}
