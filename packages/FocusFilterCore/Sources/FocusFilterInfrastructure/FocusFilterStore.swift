import Foundation
import FocusFilterCore

public final class FocusFilterStore: FocusFilterRepository {
    private struct StoredValue<Value> {
        private(set) var lastValid: Value?
        private(set) var readFailed = false

        mutating func accept(_ value: Value) {
            lastValid = value
            readFailed = false
        }

        mutating func reload(using load: () throws -> Value, required: Bool = false, failures: inout [Error]) {
            do {
                accept(try load())
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile && lastValid == nil && !readFailed {
                if required {
                    failures.append(error)
                }
            } catch {
                readFailed = true
                failures.append(error)
            }
        }
    }

    private struct Delivery {
        let policy: FocusFilterPolicy
        let observerIds: [UUID]
    }

    private let persistence: any FocusFilterPersistence
    private let changes: any FocusFilterChangeChannel
    private let onReadFailure: (Error) -> Void
    private let lock = NSLock()
    private var changeObservation: (any FocusFilterObservation)?
    private var storedConfiguration = StoredValue<FocusFilterConfiguration>()
    private var storedCatalog = StoredValue<FocusFilterCatalog>()
    private var needsFolderMembership: Bool {
        guard let configuration = storedConfiguration.lastValid else { return false }
        return configuration.effect.contains(.notifications)
            && configuration.folderIds.contains { configuration.accountIds.contains($0.accountId) }
    }
    private var currentPolicy = FocusFilterPolicy()
    private var observers: [UUID: (FocusFilterPolicy) -> Void] = [:]
    private var pendingDeliveries: [Delivery] = []
    private var delivering = false

    public init(persistence: any FocusFilterPersistence, changes: any FocusFilterChangeChannel, onReadFailure: @escaping (Error) -> Void) {
        self.persistence = persistence
        self.changes = changes
        self.onReadFailure = onReadFailure
        changeObservation = changes.observe { [weak self] in self?.reload() }
        reload()
    }

    public convenience init(location: FocusFilterStorageLocation, onReadFailure: @escaping (Error) -> Void) {
        self.init(
            persistence: FocusFilterFilePersistence(directory: location.directory),
            changes: DistributedFocusFilterChanges(name: location.notificationName),
            onReadFailure: onReadFailure
        )
    }

    public var policy: FocusFilterPolicy {
        lock.lock()
        defer { lock.unlock() }
        return currentPolicy
    }

    public func observe(_ observer: @escaping (FocusFilterPolicy) -> Void) -> any FocusFilterObservation {
        let id = UUID()
        lock.lock()
        observers[id] = observer
        pendingDeliveries.append(Delivery(policy: currentPolicy, observerIds: [id]))
        lock.unlock()
        deliverPendingPolicies()
        return FocusFilterObservationToken { [weak self] in self?.removeObserver(id) }
    }

    public func reload() {
        lock.lock()
        var failures: [Error] = []
        storedConfiguration.reload(using: persistence.loadConfiguration, failures: &failures)
        storedCatalog.reload(using: persistence.loadCatalog, required: needsFolderMembership, failures: &failures)
        publishPolicy()
        lock.unlock()
        completeUpdate(failures: failures, notify: false)
    }

    public func updateConfiguration(_ configuration: FocusFilterConfiguration) throws {
        lock.lock()
        var failures: [Error] = []
        do {
            try persistence.saveConfiguration(configuration)
            storedConfiguration.accept(configuration)
            storedCatalog.reload(using: persistence.loadCatalog, required: needsFolderMembership, failures: &failures)
            publishPolicy()
            lock.unlock()
        } catch {
            lock.unlock()
            throw error
        }
        completeUpdate(failures: failures, notify: true)
    }

    public func updateCatalog(_ catalog: FocusFilterCatalog) throws {
        lock.lock()
        guard storedCatalog.lastValid != catalog || storedCatalog.readFailed else { lock.unlock(); return }
        var failures: [Error] = []
        do {
            try persistence.saveCatalog(catalog)
            storedCatalog.accept(catalog)
            storedConfiguration.reload(using: persistence.loadConfiguration, failures: &failures)
            publishPolicy()
            lock.unlock()
        } catch {
            lock.unlock()
            throw error
        }
        completeUpdate(failures: failures, notify: true)
    }

    private func completeUpdate(failures: [Error], notify: Bool) {
        failures.forEach(onReadFailure)
        deliverPendingPolicies()
        if notify { changes.postChange() }
    }

    private func publishPolicy() {
        let configuration = storedConfiguration.lastValid ?? FocusFilterConfiguration()
        let folderMembershipUnavailable = needsFolderMembership && (storedCatalog.lastValid == nil || storedCatalog.readFailed)
        let policy = FocusFilterPolicy(
            configuration: configuration,
            catalog: storedCatalog.lastValid ?? FocusFilterCatalog(),
            isNotificationFilteringUnavailable: storedConfiguration.readFailed || folderMembershipUnavailable
        )
        guard currentPolicy != policy else { return }
        currentPolicy = policy
        pendingDeliveries.append(Delivery(policy: policy, observerIds: Array(observers.keys)))
    }

    private func deliverPendingPolicies() {
        lock.lock()
        guard !delivering else { lock.unlock(); return }
        delivering = true
        while !pendingDeliveries.isEmpty {
            let delivery = pendingDeliveries.removeFirst()
            lock.unlock()
            for id in delivery.observerIds {
                lock.lock()
                let observer = observers[id]
                lock.unlock()
                observer?(delivery.policy)
            }
            lock.lock()
        }
        delivering = false
        lock.unlock()
    }

    private func removeObserver(_ id: UUID) {
        lock.lock()
        observers.removeValue(forKey: id)
        lock.unlock()
    }

    deinit {
        changeObservation?.invalidate()
    }
}
