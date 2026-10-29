import Foundation
import FocusFilterCore

public final class FocusFilterStore: FocusFilterRepository {
    private struct Delivery {
        let policy: FocusFilterPolicy
        let observerIds: [UUID]
    }

    private let persistence: any FocusFilterPersistence
    private let changes: any FocusFilterChangeChannel
    private let onReadFailure: (Error) -> Void
    private let lock = NSLock()
    private var changeObservation: (any FocusFilterObservation)?
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
        publish(loadPolicy(failures: &failures))
        lock.unlock()
        completeUpdate(failures: failures, notify: false)
    }

    public func updateConfiguration(_ configuration: FocusFilterConfiguration) throws {
        lock.lock()
        var failures: [Error] = []
        do {
            try persistence.saveConfiguration(configuration)
            let catalog = recover(defaultValue: FocusFilterCatalog(), failures: &failures, load: persistence.loadCatalog)
            publish(FocusFilterPolicy(configuration: configuration, catalog: catalog))
            lock.unlock()
        } catch {
            lock.unlock()
            throw error
        }
        completeUpdate(failures: failures, notify: true)
    }

    public func updateCatalog(_ catalog: FocusFilterCatalog) throws {
        lock.lock()
        guard currentPolicy.catalog != catalog else { lock.unlock(); return }
        var failures: [Error] = []
        do {
            try persistence.saveCatalog(catalog)
            let configuration = recover(defaultValue: FocusFilterConfiguration(), failures: &failures, load: persistence.loadConfiguration)
            publish(FocusFilterPolicy(configuration: configuration, catalog: catalog))
            lock.unlock()
        } catch {
            lock.unlock()
            throw error
        }
        completeUpdate(failures: failures, notify: true)
    }

    private func loadPolicy(failures: inout [Error]) -> FocusFilterPolicy {
        let configuration = recover(defaultValue: FocusFilterConfiguration(), failures: &failures, load: persistence.loadConfiguration)
        let catalog = recover(defaultValue: FocusFilterCatalog(), failures: &failures, load: persistence.loadCatalog)
        return FocusFilterPolicy(configuration: configuration, catalog: catalog)
    }

    private func recover<Value>(defaultValue: Value, failures: inout [Error], load: () throws -> Value) -> Value {
        do {
            return try load()
        } catch {
            failures.append(error)
            return defaultValue
        }
    }

    private func completeUpdate(failures: [Error], notify: Bool) {
        failures.forEach(onReadFailure)
        deliverPendingPolicies()
        if notify { changes.postChange() }
    }

    private func publish(_ policy: FocusFilterPolicy) {
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
