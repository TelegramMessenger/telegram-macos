import Foundation

public enum AnalyticsPrivacy {
    case ordinary
    case excluded
    case unresolved
}

protocol AnalyticsRevocable: AnyObject {
    func revokeAnalytics()
}

private final class WeakAnalyticsObserver {
    weak var value: AnalyticsRevocable?

    init(_ value: AnalyticsRevocable) {
        self.value = value
    }
}

private final class WeakAnalyticsScope {
    weak var value: AnalyticsScope?

    init(_ value: AnalyticsScope) {
        self.value = value
    }
}

public final class AnalyticsScope {
    let policy: AnalyticsCollectionPolicy
    fileprivate let generation: UUID
    private var observers: [ObjectIdentifier: WeakAnalyticsObserver] = [:]
    private var privacyObservers: [ObjectIdentifier: WeakAnalyticsObserver] = [:]
    fileprivate var excluded = false

    fileprivate init(policy: AnalyticsCollectionPolicy, generation: UUID) {
        self.policy = policy
        self.generation = generation
    }

    var isExcluded: Bool { policy.sync { excluded } }

    public func exclude() {
        policy.exclude(self)
    }

    func observePrivacy(_ observer: AnalyticsRevocable) {
        policy.sync {
            privacyObservers = privacyObservers.filter { $0.value.value != nil }
            privacyObservers[ObjectIdentifier(observer)] = WeakAnalyticsObserver(observer)
            if excluded { observer.revokeAnalytics() }
        }
    }

    func removePrivacyObserver(_ observer: AnalyticsRevocable) {
        policy.sync { privacyObservers.removeValue(forKey: ObjectIdentifier(observer)) }
    }

    fileprivate func notifyPrivacyObservers() {
        let values = privacyObservers.values.compactMap { $0.value }
        for value in values { value.revokeAnalytics() }
    }

    public var isValid: Bool {
        return policy.sync { policy.accepts(self) }
    }

    @discardableResult
    func perform<T>(_ action: () -> T) -> T? {
        return policy.sync {
            guard policy.accepts(self) else {
                return nil
            }
            return action()
        }
    }

    func observe(_ observer: AnalyticsRevocable) {
        policy.sync {
            guard policy.accepts(self) else {
                observer.revokeAnalytics()
                return
            }
            observers = observers.filter { $0.value.value != nil }
            observers[ObjectIdentifier(observer)] = WeakAnalyticsObserver(observer)
        }
    }

    func removeObserver(_ observer: AnalyticsRevocable) {
        policy.sync {
            observers.removeValue(forKey: ObjectIdentifier(observer))
        }
    }

    fileprivate func revoke() {
        let values = observers.values.compactMap { $0.value }
        observers.removeAll()
        for value in values {
            value.revokeAnalytics()
        }
    }
}

final class AnalyticsCollectionPolicy {
    private let queue = DispatchQueue(label: "org.telegram.analytics.collection")
    private let queueKey = DispatchSpecificKey<Bool>()
    private var enabled = false
    private var owner: AnyObject?
    private var generation = UUID()
    private var exclusions = Set<ObjectIdentifier>()
    private var scopes: [WeakAnalyticsScope] = []
    var didRevoke: (() -> Void)?

    init() {
        queue.setSpecific(key: queueKey, value: true)
    }

    @discardableResult
    func sync<T>(_ action: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueKey) == true {
            return action()
        }
        return queue.sync(execute: action)
    }

    var isEnabled: Bool {
        get { sync { enabled } }
        set {
            sync {
                guard enabled != newValue else { return }
                enabled = newValue
                revoke()
            }
        }
    }

    var hasExclusions: Bool {
        return sync { !exclusions.isEmpty }
    }

    func setOwner(_ owner: AnyObject?) {
        sync {
            guard self.owner !== owner else { return }
            self.owner = owner
            revoke()
        }
    }

    func makeScope(owner: AnyObject, privacy: AnalyticsPrivacy) -> AnalyticsScope? {
        return sync {
            guard enabled, self.owner === owner, exclusions.isEmpty, privacy == .ordinary else {
                return nil
            }
            let scope = AnalyticsScope(policy: self, generation: generation)
            scopes.removeAll { $0.value == nil }
            scopes.append(WeakAnalyticsScope(scope))
            return scope
        }
    }

    func setExcluded(_ excluded: Bool, owner: ObjectIdentifier) {
        sync {
            if excluded {
                if exclusions.insert(owner).inserted {
                    revoke()
                }
            } else {
                exclusions.remove(owner)
            }
        }
    }

    func exclude(_ scope: AnalyticsScope) {
        sync {
            guard scope.policy === self, !scope.excluded else { return }
            scope.excluded = true
            revoke()
            scope.notifyPrivacyObservers()
        }
    }

    func accepts(_ scope: AnalyticsScope?) -> Bool {
        guard let scope = scope else { return false }
        return scope.policy === self && !scope.excluded && scope.generation == generation && enabled && owner != nil && exclusions.isEmpty
    }

    func accepts(_ scope: AnalyticsScope?, owner: AnyObject) -> Bool {
        return self.owner === owner && accepts(scope)
    }

    private func revoke() {
        generation = UUID()
        let values = scopes.compactMap { $0.value }
        scopes.removeAll()
        for scope in values {
            scope.revoke()
        }
        didRevoke?()
    }
}
