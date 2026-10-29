import Foundation
import FocusFilterCore

public protocol FocusFilterChangeChannel {
    func observe(_ changed: @escaping () -> Void) -> any FocusFilterObservation
    func postChange()
}

public final class DistributedFocusFilterChanges: FocusFilterChangeChannel {
    private let name: Notification.Name
    private let center: DistributedNotificationCenter

    public init(name: String, center: DistributedNotificationCenter = .default()) {
        self.name = Notification.Name(name)
        self.center = center
    }

    public func observe(_ changed: @escaping () -> Void) -> any FocusFilterObservation {
        let token = center.addObserver(forName: name, object: nil, queue: nil) { _ in changed() }
        return FocusFilterObservationToken { [center] in center.removeObserver(token) }
    }

    public func postChange() {
        center.postNotificationName(name, object: nil, userInfo: nil, deliverImmediately: true)
    }
}

public final class FocusFilterObservationToken: FocusFilterObservation {
    private let lock = NSLock()
    private var cancellation: (() -> Void)?

    public init(_ cancellation: @escaping () -> Void) {
        self.cancellation = cancellation
    }

    public func invalidate() {
        lock.lock()
        let cancellation = self.cancellation
        self.cancellation = nil
        lock.unlock()
        cancellation?()
    }

    deinit {
        invalidate()
    }
}
