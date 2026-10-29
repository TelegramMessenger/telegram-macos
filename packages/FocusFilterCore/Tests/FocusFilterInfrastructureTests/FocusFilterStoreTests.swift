import Foundation
import XCTest
import FocusFilterCore
@testable import FocusFilterInfrastructure

final class FocusFilterStoreTests: XCTestCase {
    private var directory: URL!
    private var notificationName: String!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("FocusFilterCoreTests-\(UUID().uuidString)", isDirectory: true)
        notificationName = "org.telegram.FocusFilterCoreTests.\(UUID().uuidString)"
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func makeStore() -> FocusFilterStore {
        FocusFilterStore(
            persistence: FocusFilterFilePersistence(directory: directory),
            changes: DistributedFocusFilterChanges(name: notificationName),
            onReadFailure: { _ in }
        )
    }

    func testTwoStoresPreserveEachOthersConfigurationAndCatalogWrites() throws {
        let app = makeStore()
        let system = makeStore()
        let chat = FocusChatIdentifier(accountId: Int64.min, peerId: Int64.max)
        let configuration = FocusFilterConfiguration(accountIds: [chat.accountId], chatIds: [chat], effect: .both)
        let catalog = FocusFilterCatalog(accounts: [.init(id: chat.accountId, title: "Работа")], chats: [.init(id: chat, title: "Чат")])

        try system.updateConfiguration(configuration)
        app.reload()
        XCTAssertEqual(app.policy.configuration, configuration)
        try app.updateCatalog(catalog)
        system.reload()
        XCTAssertEqual(system.policy.configuration, configuration)
        XCTAssertEqual(system.policy.catalog, catalog)

        let restored = makeStore()
        XCTAssertEqual(restored.policy, FocusFilterPolicy(configuration: configuration, catalog: catalog))
        try system.updateConfiguration(.init())
        app.reload()
        XCTAssertEqual(app.policy.catalog, catalog)
        XCTAssertNil(app.policy.selection(accountId: chat.accountId, effect: .chatList))
    }

    func testObservationsDeliverInitialAndChangedPoliciesOnceAndCancelIdempotently() throws {
        let store = makeStore()
        let recorder = PolicyRecorder()
        let observation = store.observe(recorder.append)
        XCTAssertEqual(recorder.values, [.init()])
        let configuration = FocusFilterConfiguration(accountIds: [10], effect: .both)

        try store.updateConfiguration(configuration)
        try store.updateConfiguration(configuration)
        store.reload()
        XCTAssertEqual(recorder.values.count, 2)
        XCTAssertEqual(recorder.values.last?.configuration, configuration)

        let catalog = FocusFilterCatalog(accounts: [.init(id: 10, title: "Work")])
        try store.updateCatalog(catalog)
        try store.updateCatalog(catalog)
        XCTAssertEqual(recorder.values.count, 3)
        observation.invalidate()
        observation.invalidate()
        try store.updateConfiguration(.init())
        XCTAssertEqual(recorder.values.count, 3)
    }

    func testReleasingObservationStopsDelivery() throws {
        let store = makeStore()
        let recorder = PolicyRecorder()
        var observation: FocusFilterObservation? = store.observe(recorder.append)
        XCTAssertNotNil(observation)
        XCTAssertEqual(recorder.values.count, 1)
        observation = nil

        try store.updateConfiguration(.init(accountIds: [10]))
        XCTAssertEqual(recorder.values.count, 1)
    }

    func testReentrantObserverUpdatesNeverDeliverAnOlderPolicyAfterANewerOne() throws {
        let store = makeStore()
        let first = FocusFilterConfiguration(accountIds: [10], effect: .notifications)
        let second = FocusFilterConfiguration(accountIds: [100], effect: .both)
        let recorders = [PolicyRecorder(), PolicyRecorder()]
        let observations = recorders.map { recorder in
            store.observe { policy in
                recorder.append(policy)
                if policy.configuration == first {
                    do {
                        try store.updateConfiguration(second)
                    } catch {
                        XCTFail("Unable to persist observer update: \(error)")
                    }
                }
            }
        }

        try store.updateConfiguration(first)

        XCTAssertEqual(store.policy.configuration, second)
        for recorder in recorders {
            XCTAssertEqual(recorder.values.last?.configuration, second)
        }
        observations.forEach { $0.invalidate() }
    }

    func testDistributedChangeReloadsOtherStoreWithoutPolling() throws {
        let app = makeStore()
        let system = makeStore()
        let configuration = FocusFilterConfiguration(accountIds: [10], mode: .excludeSelected, effect: .both)
        let received = expectation(description: "The other process receives the active configuration")
        received.assertForOverFulfill = true
        let observation = app.observe { policy in
            if policy.configuration == configuration {
                received.fulfill()
            }
        }

        try system.updateConfiguration(configuration)
        wait(for: [received], timeout: 3)
        observation.invalidate()
        XCTAssertEqual(app.policy.configuration, configuration)
    }

    func testPersistenceRestrictsCatalogAndConfigurationPermissions() throws {
        let store = makeStore()
        try store.updateConfiguration(.init(accountIds: [10]))
        try store.updateCatalog(.init(accounts: [.init(id: 10, title: "Work")]))

        let directoryPermissions = try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(directoryPermissions?.intValue, 0o700)
        for file in ["configuration.json", "catalog.json"] {
            let permissions = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent(file).path)[.posixPermissions] as? NSNumber
            XCTAssertEqual(permissions?.intValue, 0o600, file)
        }
    }

    func testCorruptConfigurationResetsFilteringWithoutDestroyingCatalog() throws {
        let store = makeStore()
        let catalog = FocusFilterCatalog(accounts: [.init(id: 10, title: "Work")])
        try store.updateCatalog(catalog)
        try store.updateConfiguration(.init(accountIds: [10], effect: .both))
        try Data("not json".utf8).write(to: directory.appendingPathComponent("configuration.json"), options: .atomic)
        store.reload()

        XCTAssertEqual(store.policy.configuration, .init())
        XCTAssertEqual(store.policy.catalog, catalog)
        XCTAssertTrue(store.policy.includes(accountId: 10, peerId: 42, effect: .notifications))
    }


}

private final class PolicyRecorder {
    private let lock = NSLock()
    private var policies: [FocusFilterPolicy] = []

    var values: [FocusFilterPolicy] {
        lock.lock()
        defer { lock.unlock() }
        return policies
    }

    func append(_ policy: FocusFilterPolicy) {
        lock.lock()
        policies.append(policy)
        lock.unlock()
    }
}
