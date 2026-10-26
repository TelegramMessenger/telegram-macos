public protocol FocusFilterObservation: AnyObject {
    func invalidate()
}

public protocol FocusFilterPolicySource: AnyObject {
    var policy: FocusFilterPolicy { get }
    func observe(_ observer: @escaping (FocusFilterPolicy) -> Void) -> any FocusFilterObservation
}

public protocol FocusFilterRepository: FocusFilterPolicySource {
    func reload()
    func updateConfiguration(_ configuration: FocusFilterConfiguration) throws
    func updateCatalog(_ catalog: FocusFilterCatalog) throws
}

public final class InactiveFocusFilterPolicySource: FocusFilterPolicySource {
    public init() {
    }

    public var policy: FocusFilterPolicy { .init() }

    public func observe(_ observer: @escaping (FocusFilterPolicy) -> Void) -> any FocusFilterObservation {
        observer(policy)
        return InactiveFocusFilterObservation()
    }
}

private final class InactiveFocusFilterObservation: FocusFilterObservation {
    func invalidate() {
    }
}
