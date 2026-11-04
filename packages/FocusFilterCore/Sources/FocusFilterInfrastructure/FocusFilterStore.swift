import Foundation
import FocusFilterCore

public final class FocusFilterStore: FocusFilterRepository {
    private enum ConfigurationState {
        case missing
        case unreadable
        case saved(FocusFilterConfiguration)

        func policy(catalog: FocusFilterCatalog) -> FocusFilterPolicy {
            switch self {
            case .missing: return FocusFilterPolicy(catalog: catalog)
            case .unreadable: return FocusFilterPolicy(suppressingNotificationsWith: catalog)
            case let .saved(configuration): return FocusFilterPolicy(configuration: configuration, catalog: catalog)
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
    private var configurationState = ConfigurationState.missing
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
        reloadConfiguration(failures: &failures)
        let catalog = loadCatalog(failures: &failures)
        publish(configurationState.policy(catalog: catalog))
        lock.unlock()
        completeUpdate(failures: failures, notify: false)
    }

    public func updateConfiguration(_ configuration: FocusFilterConfiguration) throws {
        lock.lock()
        var failures: [Error] = []
        do {
            try persistence.saveConfiguration(configuration)
            configurationState = .saved(configuration)
            let catalog = loadCatalog(failures: &failures)
            publish(configurationState.policy(catalog: catalog))
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
            reloadConfiguration(failures: &failures)
            publish(configurationState.policy(catalog: catalog))
            lock.unlock()
        } catch {
            lock.unlock()
            throw error
        }
        completeUpdate(failures: failures, notify: true)
    }

    private func reloadConfiguration(failures: inout [Error]) {
        do {
            configurationState = .saved(try persistence.loadConfiguration())
        } catch {
            if case .missing = configurationState {
                if (error as? CocoaError)?.code == .fileReadNoSuchFile { return }
                configurationState = .unreadable
            }
            failures.append(error)
        }
    }

    private func loadCatalog(failures: inout [Error]) -> FocusFilterCatalog {
        do {
            return try persistence.loadCatalog()
        } catch {
            if (error as? CocoaError)?.code != .fileReadNoSuchFile || currentPolicy.catalog != FocusFilterCatalog() {
                failures.append(error)
            }
            return currentPolicy.catalog
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
