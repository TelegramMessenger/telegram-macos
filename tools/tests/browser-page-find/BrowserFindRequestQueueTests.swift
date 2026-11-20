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

    private final class Harness {
        var query = ""
        var calls: [(String, Bool)] = []
        var completions: [(Bool) -> Void] = []
        var results: [(String, Bool)] = []
        lazy var queue: BrowserFindRequestQueue = {
            let queue = BrowserFindRequestQueue { [unowned self] query, backwards, completion in
                calls.append((query, backwards))
                completions.append(completion)
            }
            queue.result = { [unowned self] query, found in results.append((query, found)) }
            return queue
        }()

        func edit(_ query: String) {
            self.query = query
            queue.enqueue(query, backwards: false)
        }

        func navigate(_ backwards: Bool = false) {
            guard !query.isEmpty else { return }
#if BASELINE
            queue.enqueue(query, backwards: backwards)
#else
            queue.navigate(backwards: backwards)
#endif
        }

        func finish(_ found: Bool = true) {
            guard !completions.isEmpty else { return XCTFail("Expected a pending search") }
            completions.removeFirst()(found)
        }

        func drain() {
            while !completions.isEmpty { finish() }
        }
    }

    func testRepeatedNextCommandsAreNotDropped() {
        let harness = Harness()
        harness.edit("needle")
        harness.finish()
        harness.navigate()
        harness.navigate()
        harness.navigate()
        harness.drain()
        XCTAssertEqual(harness.calls.map { $0.0 }, Array(repeating: "needle", count: 4))
        XCTAssertEqual(harness.calls.map { $0.1 }, [false, false, false, false])
    }

    func testRepeatedPreviousCommandsAreNotDropped() {
        let harness = Harness()
        harness.edit("needle")
        harness.finish()
        for _ in 0 ..< 3 { harness.navigate(true) }
        harness.drain()
        XCTAssertEqual(harness.calls.map { $0.1 }, [false, true, true, true])
    }

    func testMixedNavigationMaintainsOrderWhileInitialQueryRuns() {
        let harness = Harness()
        harness.edit("needle")
        for backwards in [false, true, true, false, true] { harness.navigate(backwards) }
        XCTAssertEqual(harness.calls.count, 1)
        harness.drain()
        XCTAssertEqual(harness.calls.map { $0.1 }, [false, false, true, true, false, true])
        XCTAssertEqual(harness.results.count, 1)
    }

    func testTypingCoalescesButRetainsNavigationForTheLatestQuery() {
        let harness = Harness()
        harness.edit("n")
        harness.edit("ne")
        harness.navigate(true)
        harness.edit("needle")
        harness.navigate()
        harness.navigate(true)
        harness.drain()
        XCTAssertEqual(harness.calls.map { $0.0 }, ["n", "needle", "needle", "needle"])
        XCTAssertEqual(harness.calls.map { $0.1 }, [false, false, false, true])
        XCTAssertEqual(harness.results.map { $0.0 }, ["needle"])
    }

    func testNewQueryDiscardsPendingOldNavigation() {
        let harness = Harness()
        harness.edit("old")
        harness.finish()
        harness.navigate(true)
        harness.navigate()
        harness.navigate(true)
        harness.edit("new")
        harness.navigate()
        harness.navigate(true)
        harness.drain()
        XCTAssertEqual(harness.calls.map { $0.0 }, ["old", "old", "new", "new", "new"])
        XCTAssertEqual(harness.calls.map { $0.1 }, [false, true, false, false, true])
        XCTAssertEqual(harness.results.map { $0.0 }, ["old", "new"])
    }

    func testEditingTheSameQueryStartsANewGeneration() {
        let harness = Harness()
        harness.edit("same")
        harness.navigate(true)
        harness.navigate(true)
        harness.edit("same")
        harness.navigate()
        harness.drain()
        XCTAssertEqual(harness.calls.map { $0.1 }, [false, false, false])
        XCTAssertEqual(harness.results.count, 1)
    }

    func testClearingDiscardsNavigationAndSuppressesOldFeedback() {
        let harness = Harness()
        harness.edit("old")
        harness.navigate()
        harness.navigate(true)
        harness.edit("")
        harness.navigate()
        harness.drain()
        XCTAssertEqual(harness.calls.map { $0.0 }, ["old", ""])
        XCTAssertEqual(harness.results.map { $0.0 }, [""])
    }

    func testOnlyTheLastNavigationPublishesFeedback() {
        let harness = Harness()
        harness.edit("needle")
        harness.navigate()
        harness.navigate()
        harness.finish(false)
        XCTAssertTrue(harness.results.isEmpty)
        harness.finish(true)
        XCTAssertTrue(harness.results.isEmpty)
        harness.finish(false)
        XCTAssertEqual(harness.results.map { $0.1 }, [false])
    }

    func testReentrantResultCanChangeQueryAndQueueNavigation() {
        let harness = Harness()
        harness.queue.result = { query, found in
            harness.results.append((query, found))
            if query == "old" {
                harness.edit("new")
                harness.navigate(true)
                harness.navigate()
            }
        }
        harness.edit("old")
        harness.drain()
        XCTAssertEqual(harness.calls.map { $0.0 }, ["old", "new", "new", "new"])
        XCTAssertEqual(harness.calls.map { $0.1 }, [false, false, true, false])
        XCTAssertEqual(harness.results.map { $0.0 }, ["old", "new"])
        harness.queue.result = nil
    }

    func testQueuedNavigationSurvivesOwnerRelease() {
        var calls = 0
        var completions: [(Bool) -> Void] = []
        var queue: BrowserFindRequestQueue? = BrowserFindRequestQueue { _, _, completion in
            calls += 1
            completions.append(completion)
        }
        weak var retained = queue
        queue?.enqueue("needle", backwards: false)
#if BASELINE
        queue?.enqueue("needle", backwards: false)
        queue?.enqueue("needle", backwards: true)
#else
        queue?.navigate(backwards: false)
        queue?.navigate(backwards: true)
#endif
        queue = nil
        while !completions.isEmpty { completions.removeFirst()(true) }
        XCTAssertEqual(calls, 3)
        XCTAssertNil(retained)
    }

    func testLargeSynchronousDrainDoesNotRecurse() {
        var first: ((Bool) -> Void)?
        var calls = 0
        var depth = 0
        var maxDepth = 0
        let queue = BrowserFindRequestQueue { _, _, completion in
            calls += 1
            depth += 1
            maxDepth = max(maxDepth, depth)
            if calls == 1 { first = completion } else { completion(true) }
            depth -= 1
        }
        queue.enqueue("needle", backwards: false)
        for index in 0 ..< 10000 {
#if BASELINE
            queue.enqueue("needle", backwards: index % 2 == 0)
#else
            queue.navigate(backwards: index % 2 == 0)
#endif
        }
        first?(true)
        first = nil
        XCTAssertEqual(calls, 10001)
        XCTAssertEqual(maxDepth, 1)
    }

    func testNavigationWithNoActiveQueryDoesNothing() {
        var calls = 0
        let queue = BrowserFindRequestQueue { _, _, completion in calls += 1; completion(false) }
#if !BASELINE
        queue.navigate(backwards: false)
        queue.navigate(backwards: true)
#endif
        XCTAssertEqual(calls, 0)
        queue.enqueue("", backwards: false)
#if !BASELINE
        queue.navigate(backwards: false)
#endif
        XCTAssertEqual(calls, 1)
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
