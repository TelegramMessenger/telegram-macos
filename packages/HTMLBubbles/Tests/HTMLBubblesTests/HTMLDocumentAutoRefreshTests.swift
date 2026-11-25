import XCTest
import Postbox
import TelegramCore
@testable import HTMLBubbles

final class HTMLDocumentAutoRefreshTests: XCTestCase {
    private let id = MessageId(peerId: PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(8736535756)), namespace: Namespaces.Message.Cloud, id: 7)
    private let on = HTMLDocumentAutoRefresh.Conditions(visible: true, windowActive: true, appActive: true)

    func testIntervalComesFromTheRootAndIsClamped() {
        XCTAssertEqual(HTMLDocumentAutoRefresh.interval("<div class=\"widget\" data-refresh=\"60\">x</div>"), 60)
        XCTAssertEqual(HTMLDocumentAutoRefresh.interval("<style>a{}</style><div data-refresh='5'>x</div>"), 30)
        XCTAssertNil(HTMLDocumentAutoRefresh.interval("<div class=\"widget\"><p data-refresh=\"60\">x</p></div>"))
        XCTAssertNil(HTMLDocumentAutoRefresh.interval("<div class=\"widget\">x</div>"))
        XCTAssertNil(HTMLDocumentAutoRefresh.interval("<div data-refresh=\"0\">x</div>"))
    }

    func testRefreshButtonDetection() {
        XCTAssertTrue(HTMLDocumentAutoRefresh.isRefreshButton(text: "↻ Refresh", data: Data("x".utf8)))
        XCTAssertTrue(HTMLDocumentAutoRefresh.isRefreshButton(text: "Update", data: Data("refresh:1".utf8)))
        XCTAssertTrue(HTMLDocumentAutoRefresh.isRefreshButton(text: "Again", data: Data("ar:42".utf8)))
        XCTAssertFalse(HTMLDocumentAutoRefresh.isRefreshButton(text: "Vote", data: Data("g:1".utf8)))
    }

    func testFiresOnlyAfterBeingVisibleForTheInterval() {
        let refresh = HTMLDocumentAutoRefresh(limit: 60)
        XCTAssertEqual(refresh.check(id, interval: 30, conditions: on, now: 0), .wait)
        XCTAssertEqual(refresh.check(id, interval: 30, conditions: on, now: 29), .wait)
        XCTAssertEqual(refresh.check(id, interval: 30, conditions: on, now: 30), .fire)
        XCTAssertEqual(refresh.check(id, interval: 30, conditions: on, now: 70), .wait, "a refresh in flight is not repeated")
        refresh.finished(id, now: 71)
        XCTAssertEqual(refresh.check(id, interval: 30, conditions: on, now: 100), .wait)
        XCTAssertEqual(refresh.check(id, interval: 30, conditions: on, now: 101), .fire)
    }

    func testHiddenInactiveOrBackgroundResetsTheClock() {
        let refresh = HTMLDocumentAutoRefresh(limit: 60)
        _ = refresh.check(id, interval: 30, conditions: on, now: 0)
        for off in [HTMLDocumentAutoRefresh.Conditions(visible: false, windowActive: true, appActive: true), HTMLDocumentAutoRefresh.Conditions(visible: true, windowActive: false, appActive: true), HTMLDocumentAutoRefresh.Conditions(visible: true, windowActive: true, appActive: false)] {
            XCTAssertEqual(refresh.check(id, interval: 30, conditions: off, now: 40), .reset)
            XCTAssertEqual(refresh.check(id, interval: 30, conditions: on, now: 41), .wait)
            XCTAssertEqual(refresh.check(id, interval: 30, conditions: on, now: 60), .wait)
        }
        XCTAssertEqual(refresh.check(id, interval: 30, conditions: on, now: 71), .fire)
    }

    func testSessionLimit() {
        let refresh = HTMLDocumentAutoRefresh(limit: 2)
        var now: TimeInterval = 0
        var fires = 0
        _ = refresh.check(id, interval: 30, conditions: on, now: now)
        for _ in 0 ..< 10 {
            now += 31
            if refresh.check(id, interval: 30, conditions: on, now: now) == .fire {
                fires += 1
                refresh.finished(id, now: now)
            }
        }
        XCTAssertEqual(fires, 2)
        XCTAssertEqual(refresh.fired, 2)
    }

    func testFlagDefaultsOn() {
        let defaults = UserDefaults(suiteName: "HTMLDocumentAutoRefreshTests")!
        defaults.removePersistentDomain(forName: "HTMLDocumentAutoRefreshTests")
        XCTAssertTrue(HTMLDocumentAutoRefresh.isEnabled(defaults))
        defaults.set(false, forKey: HTMLDocumentAutoRefresh.flagKey)
        XCTAssertFalse(HTMLDocumentAutoRefresh.isEnabled(defaults))
        defaults.removePersistentDomain(forName: "HTMLDocumentAutoRefreshTests")
    }
}
