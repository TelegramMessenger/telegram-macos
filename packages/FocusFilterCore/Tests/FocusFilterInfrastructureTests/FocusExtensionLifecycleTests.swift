import FocusFilterCore
import XCTest
@testable import FocusFilterInfrastructure

final class FocusExtensionLifecycleTests: XCTestCase {
    func testUnchangedInstallationNeverRetires() {
        let probe = RetirementProbe()

        for time in [0.0, 2.0, 30.0, 3_600.0] {
            probe.time = time
            XCTAssertFalse(probe.check("original", isCurrent: true))
        }

        XCTAssertEqual(probe.retirements, 0)
    }

    func testPollingFindsReplacementWithoutAnyNotification() {
        let probe = RetirementProbe()
        XCTAssertFalse(probe.check("original", isCurrent: true))

        probe.time = 30
        XCTAssertTrue(probe.check("replacement"))
        probe.time = 31.99
        XCTAssertTrue(probe.check("replacement"))
        XCTAssertEqual(probe.retirements, 0)
        probe.time = 32
        XCTAssertFalse(probe.check("replacement"))
        XCTAssertEqual(probe.retirements, 1)
    }

    func testAllActiveRequestsFinishBeforeRetirementGraceStarts() {
        let probe = RetirementProbe()
        let first = probe.retirement.beginRequest()
        let second = probe.retirement.beginRequest()
        XCTAssertTrue(probe.check("replacement"))

        probe.time = 20
        XCTAssertTrue(probe.check("replacement"))
        first.invalidate()
        probe.time = 100
        XCTAssertTrue(probe.check("replacement"))
        XCTAssertEqual(probe.retirements, 0)
        second.invalidate()

        probe.time = 101.99
        XCTAssertTrue(probe.check("replacement"))
        XCTAssertEqual(probe.retirements, 0)
        probe.time = 102
        XCTAssertFalse(probe.check("replacement"))
        XCTAssertEqual(probe.retirements, 1)
    }

    func testRequestStartingDuringConfirmationDelaysRetirement() {
        let probe = RetirementProbe()
        XCTAssertTrue(probe.check("replacement"))
        probe.time = 1
        let request = probe.retirement.beginRequest()

        probe.time = 2
        XCTAssertTrue(probe.check("replacement"))
        request.invalidate()
        probe.time = 3.99
        XCTAssertTrue(probe.check("replacement"))
        XCTAssertEqual(probe.retirements, 0)
        probe.time = 4
        XCTAssertFalse(probe.check("replacement"))
        XCTAssertEqual(probe.retirements, 1)
    }

    func testChangingReplacementRestartsConfirmation() {
        let probe = RetirementProbe()
        XCTAssertTrue(probe.check("replacement-one"))
        probe.time = 2
        XCTAssertTrue(probe.check("replacement-two"))
        probe.time = 3.99
        XCTAssertTrue(probe.check("replacement-two"))
        XCTAssertEqual(probe.retirements, 0)
        probe.time = 4
        XCTAssertFalse(probe.check("replacement-two"))
        XCTAssertEqual(probe.retirements, 1)
    }

    func testIncompleteInstallationClearsPendingConfirmation() {
        let probe = RetirementProbe()
        XCTAssertTrue(probe.check("replacement"))
        probe.time = 2
        XCTAssertFalse(probe.check(nil))
        probe.time = 30
        XCTAssertFalse(probe.check(nil))
        XCTAssertEqual(probe.retirements, 0)

        probe.time = 60
        XCTAssertTrue(probe.check("replacement"))
        probe.time = 61.99
        XCTAssertTrue(probe.check("replacement"))
        XCTAssertEqual(probe.retirements, 0)
        probe.time = 62
        XCTAssertFalse(probe.check("replacement"))
        XCTAssertEqual(probe.retirements, 1)
    }

    func testRevertedInstallationCancelsPendingRetirement() {
        let probe = RetirementProbe()
        XCTAssertTrue(probe.check("replacement"))
        probe.time = 2
        XCTAssertFalse(probe.check("original", isCurrent: true))
        probe.time = 30
        XCTAssertFalse(probe.check("original", isCurrent: true))
        XCTAssertEqual(probe.retirements, 0)

        probe.time = 60
        XCTAssertTrue(probe.check("replacement"))
        probe.time = 61.99
        XCTAssertTrue(probe.check("replacement"))
        XCTAssertEqual(probe.retirements, 0)
        probe.time = 62
        XCTAssertFalse(probe.check("replacement"))
        XCTAssertEqual(probe.retirements, 1)
    }

    func testRepeatedInvalidationAndTokenDeinitializationReleaseEachRequestOnce() {
        let probe = RetirementProbe()
        var first: (any FocusFilterObservation)? = probe.retirement.beginRequest()
        var second: (any FocusFilterObservation)? = probe.retirement.beginRequest()
        XCTAssertNotNil(second)
        XCTAssertTrue(probe.check("replacement"))

        probe.time = 10
        first?.invalidate()
        first?.invalidate()
        first = nil
        probe.time = 20
        XCTAssertTrue(probe.check("replacement"))
        XCTAssertEqual(probe.retirements, 0)

        second = nil
        probe.time = 21.99
        XCTAssertTrue(probe.check("replacement"))
        probe.time = 22
        XCTAssertFalse(probe.check("replacement"))
        XCTAssertEqual(probe.retirements, 1)
    }

    func testRetirementRunsOnlyOnceDespiteFurtherChecks() {
        let probe = RetirementProbe()
        XCTAssertTrue(probe.check("replacement"))
        probe.time = 2
        XCTAssertFalse(probe.check("replacement"))
        probe.time = 30
        XCTAssertFalse(probe.check("replacement"))
        XCTAssertFalse(probe.check("another-replacement"))
        XCTAssertFalse(probe.check(nil))
        XCTAssertFalse(probe.check("original", isCurrent: true))
        XCTAssertEqual(probe.retirements, 1)
    }

    func testInstallationNotificationsAreScopedByAppGroupAndBuildChannel() {
        let sources: [(String?, String)] = [
            ("DEBUG", "debug"),
            ("STABLE", "stable"),
            ("APP_STORE", "appstore"),
            ("BETA", "beta"),
            (nil, "beta")
        ]

        for (source, channel) in sources {
            XCTAssertEqual(
                FocusExtensionLifecycle.notificationName(appGroupIdentifier: "group.first", buildSource: source),
                "group.first.FocusFilters.\(channel).Installation"
            )
            XCTAssertNotEqual(
                FocusExtensionLifecycle.notificationName(appGroupIdentifier: "group.first", buildSource: source),
                FocusExtensionLifecycle.notificationName(appGroupIdentifier: "group.second", buildSource: source)
            )
        }

        let names = sources.prefix(4).map {
            FocusExtensionLifecycle.notificationName(appGroupIdentifier: "group.first", buildSource: $0.0)
        }
        XCTAssertEqual(Set(names).count, 4)
    }
}

private final class RetirementProbe {
    var time: TimeInterval = 0
    var retirements = 0
    lazy var retirement = FocusExtensionRetirement<String>(now: { [unowned self] in self.time })

    func check(_ snapshot: String?, isCurrent: Bool = false) -> Bool {
        retirement.check(snapshot: snapshot, isCurrent: isCurrent) {
            retirements += 1
        }
    }
}
