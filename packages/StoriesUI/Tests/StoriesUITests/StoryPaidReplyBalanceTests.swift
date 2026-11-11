import XCTest
import SwiftSignalKit
@testable import StoriesUI

final class StoryPaidReplyBalanceTests: XCTestCase {
    func testExactBalanceIsEnough() {
        var count = 0
        let disposable = storyPaidReplyBalanceReady(.single(10), required: 10).start(next: { count += 1 })
        XCTAssertEqual(count, 1); disposable.dispose()
    }

    func testConfirmedTopUpWaitsForAuthoritativeBalanceAndResumesOnlyOnce() {
        let balance = ValuePipe<Int64?>()
        var count = 0
        let disposable = storyPaidReplyBalanceReady(balance.signal(), required: 10).start(next: { count += 1 })
        balance.putNext(nil); balance.putNext(5); balance.putNext(9)
        XCTAssertEqual(count, 0)
        balance.putNext(10); balance.putNext(20)
        XCTAssertEqual(count, 1); disposable.dispose()
    }

    func testClosedStoryCancelsPendingBalanceObservation() {
        let balance = ValuePipe<Int64?>()
        var count = 0
        let disposable = storyPaidReplyBalanceReady(balance.signal(), required: 10).start(next: { count += 1 })
        balance.putNext(0); disposable.dispose(); balance.putNext(10)
        XCTAssertEqual(count, 0)
    }

    func testChangedReplyCannotResumeAfterBalanceArrives() {
        let balance = ValuePipe<Int64?>()
        var current = true, count = 0
        let disposable = storyPaidReplyBalanceReady(balance.signal(), required: 10, isCurrent: { current }).start(next: { count += 1 })
        balance.putNext(5); current = false; balance.putNext(10); current = true; balance.putNext(20)
        XCTAssertEqual(count, 0); disposable.dispose()
    }

    func testInvalidPriceCannotResumeSend() {
        var count = 0, completed = false
        let disposable = storyPaidReplyBalanceReady(.single(100), required: -1).start(next: { count += 1 }, completed: { completed = true })
        XCTAssertEqual(count, 0); XCTAssertTrue(completed); disposable.dispose()
    }
}
