import Foundation
import QuartzCore

/// How long chat preparation may block waiting for widgets to reach their exact height: a few
/// widgets per batch are worth waiting for, a long history is not (its rows take remembered
/// heights and update when their background boot finishes).
enum TwidgetPrepareBudget {
    static var window: CFTimeInterval = 0.25
    static var perWindow: CFTimeInterval = 0.06
    private static let lock = NSLock()
    private static var windowStart: CFTimeInterval = 0
    private static var used: CFTimeInterval = 0

    static func take(_ wanted: TimeInterval) -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        let now = CACurrentMediaTime()
        if now - windowStart > window {
            windowStart = now
            used = 0
        }
        return max(0, min(wanted, perWindow - used))
    }

    static func spent(_ elapsed: TimeInterval) {
        lock.lock()
        used += elapsed
        lock.unlock()
    }
}

enum TwidgetDeferredPrepare {
    static var limit = 12
    private struct Entry {
        weak var state: HTMLBubbleState?
        let appearance: HTMLBubbleAppearance
        let width: CGFloat
    }
    private static let lock = NSLock()
    private static var pending: [Entry] = []
    private static var draining = false
    private static let queue = DispatchQueue(label: "HTMLBubbles.deferredPrepare", qos: .utility)

    static func enqueue(_ state: HTMLBubbleState, appearance: HTMLBubbleAppearance, width: CGFloat) {
        lock.lock()
        pending.removeAll(where: { $0.state == nil })
        guard pending.count < limit, !pending.contains(where: { $0.state === state }) else {
            lock.unlock()
            return
        }
        pending.append(Entry(state: state, appearance: appearance, width: width))
        let start = !draining
        draining = true
        lock.unlock()
        if start {
            queue.async(execute: drain)
        }
    }

    private static func drain() {
        while true {
            lock.lock()
            guard !pending.isEmpty else {
                draining = false
                lock.unlock()
                return
            }
            let entry = pending.removeFirst()
            lock.unlock()
            var attempts = 0
            while let state = entry.state, state.startTwidgetPrepare(appearance: entry.appearance, width: entry.width) == nil, state.needsTwidgetPrepare(width: entry.width), attempts < 10 {
                attempts += 1
                Thread.sleep(forTimeInterval: 0.02)
            }
        }
    }
}
