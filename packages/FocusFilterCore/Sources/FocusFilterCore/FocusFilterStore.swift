import Foundation

public final class FocusFilterObservation {
    private let lock = NSLock()
    private var cancel: (() -> Void)?

    init(cancel: @escaping () -> Void) {
        self.cancel = cancel
    }

    public func invalidate() {
        lock.lock()
        let cancel = self.cancel
        self.cancel = nil
        lock.unlock()
        cancel?()
    }

    deinit {
        invalidate()
    }
}

public final class FocusFilterStore {
    public static let shared = FocusFilterStore()

    private let lock = NSRecursiveLock()
    private var directory: URL?
    private var notificationName: Notification.Name?
    private var distributedObservation: NSObjectProtocol?
    private var currentPolicy = FocusFilterPolicy()
    private var observers: [UUID: (FocusFilterPolicy) -> Void] = [:]
    private var pendingDeliveries: [(FocusFilterPolicy, [UUID])] = []
    private var delivering = false

    public init() {
    }

    public var policy: FocusFilterPolicy {
        lock.lock()
        defer { lock.unlock() }
        return currentPolicy
    }

    public func configure(directory: URL, notificationName: String) {
        lock.lock()
        if self.directory == directory && self.notificationName?.rawValue == notificationName {
            lock.unlock()
            return
        }
        if let observation = distributedObservation {
            DistributedNotificationCenter.default().removeObserver(observation)
        }
        self.directory = directory
        self.notificationName = Notification.Name(notificationName)
        self.distributedObservation = DistributedNotificationCenter.default().addObserver(forName: self.notificationName, object: nil, queue: nil) { [weak self] _ in
            self?.reload()
        }
        lock.unlock()
        reload()
    }

    public func observe(_ observer: @escaping (FocusFilterPolicy) -> Void) -> FocusFilterObservation {
        let id = UUID()
        lock.lock()
        observers[id] = observer
        pendingDeliveries.append((currentPolicy, [id]))
        deliverPendingPolicies()
        lock.unlock()
        return FocusFilterObservation { [weak self] in
            guard let self = self else { return }
            self.lock.lock()
            self.observers.removeValue(forKey: id)
            self.lock.unlock()
        }
    }

    public func reload() {
        lock.lock()
        let configuration: FocusFilterConfiguration = read("configuration.json") ?? .init()
        let catalog: FocusFilterCatalog = read("catalog.json") ?? .init()
        publish(FocusFilterPolicy(configuration: configuration, catalog: catalog))
        lock.unlock()
    }

    public func updateConfiguration(_ configuration: FocusFilterConfiguration) throws {
        lock.lock()
        defer { lock.unlock() }
        try write(configuration, name: "configuration.json")
        let catalog: FocusFilterCatalog = read("catalog.json") ?? .init()
        publish(FocusFilterPolicy(configuration: configuration, catalog: catalog))
        notifyOtherProcesses()
    }

    public func updateCatalog(_ catalog: FocusFilterCatalog) throws {
        lock.lock()
        defer { lock.unlock() }
        guard currentPolicy.catalog != catalog else { return }
        try write(catalog, name: "catalog.json")
        let configuration: FocusFilterConfiguration = read("configuration.json") ?? .init()
        publish(FocusFilterPolicy(configuration: configuration, catalog: catalog))
        notifyOtherProcesses()
    }

    private func publish(_ policy: FocusFilterPolicy) {
        guard currentPolicy != policy else { return }
        currentPolicy = policy
        pendingDeliveries.append((policy, Array(observers.keys)))
        deliverPendingPolicies()
    }

    private func deliverPendingPolicies() {
        guard !delivering else { return }
        delivering = true
        while !pendingDeliveries.isEmpty {
            let (policy, ids) = pendingDeliveries.removeFirst()
            for id in ids {
                observers[id]?(policy)
            }
        }
        delivering = false
    }

    private func read<T: Decodable>(_ name: String) -> T? {
        guard let directory = directory,
              let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else {
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, name: String) throws {
        guard let directory = directory else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent(name)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private func notifyOtherProcesses() {
        if let notificationName = notificationName {
            DistributedNotificationCenter.default().postNotificationName(notificationName, object: nil, userInfo: nil, deliverImmediately: true)
        }
    }

    deinit {
        if let observation = distributedObservation {
            DistributedNotificationCenter.default().removeObserver(observation)
        }
    }
}
