import Foundation
import XCTest
import FocusFilterCore
@testable import FocusFilterInfrastructure

final class FocusFilterDependencyTests: XCTestCase {
    func testInjectedPersistenceAndChangeChannelReloadWithoutFileAccess() throws {
        let persistence = MemoryFocusPersistence()
        let changes = TestFocusChanges()
        let store = FocusFilterStore(persistence: persistence, changes: changes, onReadFailure: { _ in XCTFail("Unexpected read failure") })
        var received: [FocusFilterConfiguration] = []
        let observation = store.observe { received.append($0.configuration) }
        let configuration = FocusFilterConfiguration(accountIds: [17], effect: .both)

        persistence.configuration = configuration
        changes.receiveChange()
        XCTAssertEqual(store.policy.configuration, configuration)
        XCTAssertEqual(received, [.init(), configuration])

        try store.updateConfiguration(.init())
        XCTAssertEqual(persistence.configuration, .init())
        XCTAssertEqual(changes.postCount, 1)
        observation.invalidate()
    }

    func testReadFailuresAreReportedAndDoNotDiscardValidCatalog() {
        let persistence = MemoryFocusPersistence()
        persistence.catalog = .init(accounts: [.init(id: 17, title: "Work")])
        persistence.failConfigurationRead = true
        var failures: [Error] = []
        let store = FocusFilterStore(persistence: persistence, changes: TestFocusChanges(), onReadFailure: { failures.append($0) })

        XCTAssertEqual(store.policy.configuration, .init())
        XCTAssertEqual(store.policy.catalog, persistence.catalog)
        XCTAssertEqual(failures.count, 1)
    }

    func testFailedWriteDoesNotPublishOrNotify() {
        let persistence = MemoryFocusPersistence()
        let changes = TestFocusChanges()
        let store = FocusFilterStore(persistence: persistence, changes: changes, onReadFailure: { _ in XCTFail("Unexpected read failure") })
        var received = 0
        let observation = store.observe { _ in received += 1 }
        persistence.failWrite = true

        XCTAssertThrowsError(try store.updateConfiguration(.init(accountIds: [17])))
        XCTAssertEqual(store.policy, .init())
        XCTAssertEqual(received, 1)
        XCTAssertEqual(changes.postCount, 0)
        observation.invalidate()
    }

    func testObserverCanReadPolicyFromAnotherThreadDuringDelivery() throws {
        let store = FocusFilterStore(persistence: MemoryFocusPersistence(), changes: TestFocusChanges(), onReadFailure: { _ in })
        let completed = expectation(description: "Observer does not hold the repository lock")
        let observation = store.observe { policy in
            guard policy.configuration.accountIds.contains(17) else { return }
            DispatchQueue.global().async {
                XCTAssertEqual(store.policy.configuration, policy.configuration)
                completed.fulfill()
            }
            self.wait(for: [completed], timeout: 1)
        }

        try store.updateConfiguration(.init(accountIds: [17]))
        observation.invalidate()
    }

    func testBuildChannelsHaveIsolatedStorageAndNotificationNames() {
        let container = URL(fileURLWithPath: "/temporary-fixture")
        let cases: [(String?, String)] = [("DEBUG", "debug"), ("STABLE", "stable"), ("APP_STORE", "appstore"), ("ALPHA", "beta"), (nil, "beta")]
        for (source, expectedChannel) in cases {
            let channel = FocusFilterStorageLocation.channel(for: source)
            let location = FocusFilterStorageLocation(container: container, appGroupIdentifier: "test.group", buildChannel: channel)
            XCTAssertEqual(channel, expectedChannel)
            XCTAssertEqual(location.directory.path, "/temporary-fixture/\(expectedChannel)/FocusFilters")
            XCTAssertEqual(location.notificationName, "test.group.FocusFilters.\(expectedChannel)")
        }
    }

    func testUnreadableDirectoryReportsFailureInsteadOfTreatingStateAsMissing() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let persistence = FocusFilterFilePersistence(directory: directory)
        try persistence.saveConfiguration(.init(accountIds: [17]))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: directory.path)

        XCTAssertThrowsError(try persistence.loadConfiguration())
        var failures: [Error] = []
        _ = FocusFilterStore(persistence: persistence, changes: TestFocusChanges(), onReadFailure: { failures.append($0) })
        XCTAssertFalse(failures.isEmpty)
    }
}

private final class MemoryFocusPersistence: FocusFilterPersistence {
    enum Failure: Error { case read, write }
    var configuration = FocusFilterConfiguration()
    var catalog = FocusFilterCatalog()
    var failConfigurationRead = false
    var failWrite = false

    func loadConfiguration() throws -> FocusFilterConfiguration {
        if failConfigurationRead { throw Failure.read }
        return configuration
    }

    func loadCatalog() throws -> FocusFilterCatalog { catalog }

    func saveConfiguration(_ configuration: FocusFilterConfiguration) throws {
        if failWrite { throw Failure.write }
        self.configuration = configuration
    }

    func saveCatalog(_ catalog: FocusFilterCatalog) throws {
        if failWrite { throw Failure.write }
        self.catalog = catalog
    }
}

private final class TestFocusChanges: FocusFilterChangeChannel {
    private var changed: (() -> Void)?
    private(set) var postCount = 0

    func observe(_ changed: @escaping () -> Void) -> any FocusFilterObservation {
        self.changed = changed
        return FocusFilterObservationToken { [weak self] in self?.changed = nil }
    }

    func postChange() { postCount += 1 }
    func receiveChange() { changed?() }
}
