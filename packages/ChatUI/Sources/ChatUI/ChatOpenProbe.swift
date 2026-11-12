import Foundation
import QuartzCore

#if DEBUG
enum ChatOpenProbe {
    private static let lock = NSLock()
    private static var startedAt: CFTimeInterval?
    private static var events: [(String, CFTimeInterval)] = []

    static func begin() {
        lock.lock()
        startedAt = CACurrentMediaTime()
        events.removeAll()
        lock.unlock()
    }

    static func mark(_ name: @autoclosure () -> String) {
        lock.lock()
        if let startedAt {
            events.append((name(), CACurrentMediaTime() - startedAt))
        }
        lock.unlock()
    }

    static func end() -> [(String, CFTimeInterval)] {
        lock.lock()
        let result = events
        startedAt = nil
        events.removeAll()
        lock.unlock()
        return result
    }
}
#endif
