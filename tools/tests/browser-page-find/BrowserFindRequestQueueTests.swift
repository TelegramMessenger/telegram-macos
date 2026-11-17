import Foundation
import XCTest

final class BrowserFindRequestQueueTests: XCTestCase {
    func testNewQueryWaitsForOldRequestAndSuppressesStaleFeedback() {
        var calls: [(String, Bool)] = []
        var completions: [(Bool) -> Void] = []
        var results: [String] = []
        let queue = BrowserFindRequestQueue { query, backwards, completion in
            calls.append((query, backwards))
            completions.append(completion)
        }
        queue.result = { query, _ in results.append(query) }
        queue.enqueue("a", backwards: false)
        queue.enqueue("ab", backwards: false)
        queue.enqueue("abc", backwards: false)
        XCTAssertEqual(calls.map { $0.0 }, ["a"])
        completions.removeFirst()(true)
        XCTAssertTrue(results.isEmpty)
        XCTAssertEqual(calls.map { $0.0 }, ["a", "abc"])
        completions.removeFirst()(true)
        XCTAssertEqual(results, ["abc"])
    }

    func testClosingWhileRequestRunsClearsOldPageEvenAfterOwnerReleasesQueue() {
        var queries: [String] = []
        var completions: [(Bool) -> Void] = []
        var queue: BrowserFindRequestQueue? = BrowserFindRequestQueue { query, _, completion in
            queries.append(query)
            completions.append(completion)
        }
        weak var retained = queue
        queue?.enqueue("old", backwards: false)
        queue?.enqueue("", backwards: false)
        queue = nil
        XCTAssertNotNil(retained)
        completions.removeFirst()(true)
        XCTAssertEqual(queries, ["old", ""])
        completions.removeFirst()(false)
        XCTAssertNil(retained)
    }

    func testReopeningSupersedesPendingClearAndPreservesDirection() {
        var calls: [(String, Bool)] = []
        var completions: [(Bool) -> Void] = []
        let queue = BrowserFindRequestQueue { query, backwards, completion in
            calls.append((query, backwards))
            completions.append(completion)
        }
        queue.enqueue("old", backwards: false)
        queue.enqueue("", backwards: false)
        queue.enqueue("new", backwards: true)
        completions.removeFirst()(true)
        XCTAssertEqual(calls.map { $0.0 }, ["old", "new"])
        XCTAssertEqual(calls.map { $0.1 }, [false, true])
        completions.removeFirst()(false)
    }

    func testSynchronousCompletionAndNoResult() {
        var results: [Bool] = []
        let queue = BrowserFindRequestQueue { _, _, completion in completion(false) }
        queue.result = { _, found in results.append(found) }
        queue.enqueue("missing", backwards: false)
        queue.enqueue("missing", backwards: true)
        queue.enqueue("", backwards: false)
        XCTAssertEqual(results, [false, false, false])
    }
}
