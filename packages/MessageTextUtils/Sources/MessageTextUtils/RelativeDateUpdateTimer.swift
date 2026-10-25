import AppKit
import TelegramUtils

public final class RelativeDateUpdateTimer {
    private let timestamps: [Int32]
    private let clock: () -> TimeInterval
    private let update: () -> Void
    private let timer: DispatchSourceTimer
    private let lock = NSLock()
    private var invalidated = false
    private var nextUpdateTimestamp: TimeInterval?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    public convenience init?(timestamps: [Int32], relativeTo timestamp: TimeInterval, update: @escaping () -> Void) {
        self.init(timestamps: timestamps, referenceTimestamp: timestamp, clock: { Date().timeIntervalSince1970 }, notificationCenter: .default, wakeNotificationCenter: NSWorkspace.shared.notificationCenter, update: update)
    }

    init?(timestamps: [Int32], referenceTimestamp: TimeInterval? = nil, clock: @escaping () -> TimeInterval, notificationCenter: NotificationCenter, wakeNotificationCenter: NotificationCenter, update: @escaping () -> Void) {
        guard !timestamps.isEmpty else {
            return nil
        }
        self.timestamps = Array(Set(timestamps))
        self.clock = clock
        self.update = update
        self.timer = DispatchSource.makeTimerSource(queue: .main)
        timer.setEventHandler { [weak self] in
            self?.timerFired()
        }
        timer.resume()
        for (center, name) in [(notificationCenter, Notification.Name.NSSystemClockDidChange), (wakeNotificationCenter, NSWorkspace.didWakeNotification)] {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refresh()
            }
            observers.append((center, observer))
        }
        schedule(relativeTo: referenceTimestamp)
    }

    private func schedule(relativeTo referenceTimestamp: TimeInterval? = nil) {
        lock.lock()
        defer { lock.unlock() }
        guard !invalidated else {
            return
        }
        let now = clock()
        if let referenceTimestamp, referenceTimestamp > now {
            nextUpdateTimestamp = now
        } else {
            nextUpdateTimestamp = nextRelativeDateTimeEntityUpdate(timestamps: timestamps, now: referenceTimestamp ?? now)
        }
        if let nextUpdateTimestamp {
            timer.schedule(wallDeadline: .now() + max(0.001, nextUpdateTimestamp - now), leeway: .milliseconds(1))
        }
    }

    private func timerFired() {
        lock.lock()
        guard !invalidated, let nextUpdateTimestamp else {
            lock.unlock()
            return
        }
        let remaining = nextUpdateTimestamp - clock()
        if remaining > 0 {
            timer.schedule(wallDeadline: .now() + max(0.001, remaining), leeway: .milliseconds(1))
            lock.unlock()
            return
        }
        lock.unlock()
        refresh()
    }

    private func refresh() {
        lock.lock()
        let shouldUpdate = !invalidated
        lock.unlock()
        guard shouldUpdate else {
            return
        }
        let referenceTimestamp = clock()
        update()
        schedule(relativeTo: referenceTimestamp)
    }

    public func invalidate() {
        lock.lock()
        invalidated = true
        timer.cancel()
        let observers = self.observers
        self.observers.removeAll()
        lock.unlock()
        for (center, observer) in observers {
            center.removeObserver(observer)
        }
    }

    deinit {
        invalidate()
    }
}
