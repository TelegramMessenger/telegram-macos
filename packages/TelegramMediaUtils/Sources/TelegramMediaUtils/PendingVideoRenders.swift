import Foundation
import SwiftSignalKit
import TelegramMediaResources

public final class PendingVideoRenderInfo {
    public let duration: Double
    public let dimensions: CGSize
    public let hasAudio: Bool
    private let state: Atomic<(frame: Data?, make: (() -> Data?)?)>

    public init(duration: Double, dimensions: CGSize, hasAudio: Bool, frame: @escaping () -> Data?) {
        self.duration = duration
        self.dimensions = dimensions
        self.hasAudio = hasAudio
        self.state = Atomic(value: (frame: nil, make: frame))
    }

    public var frame: Data? {
        let current = state.with { $0 }
        guard let make = current.make else {
            return current.frame
        }
        let frame = make()
        _ = state.swap((frame: frame, make: nil))
        return frame
    }
}

public enum PendingVideoRenderEvent {
    public static let minimumStreamingSize: Int64 = 10 * 1024 * 1024
    case progress(path: String, size: Int64, headerSize: Int64)
    case completed(Bool)
}

public final class PendingVideoRenders {
    public static let shared = PendingVideoRenders()

    private final class Entry {
        let info: PendingVideoRenderInfo
        let result = Promise<Bool>()
        let events = Promise<PendingVideoRenderEvent>()
        let disposable = MetaDisposable()
        let finished = Atomic<Bool>(value: false)

        init(info: PendingVideoRenderInfo) {
            self.info = info
        }

        func finish(_ success: Bool) {
            guard !finished.swap(true) else { return }
            events.set(.single(.completed(success)))
            result.set(.single(success))
        }
    }

    private let lock = NSRecursiveLock()
    private var entries: [String: Entry] = [:]

    public func add(path: String, info: PendingVideoRenderInfo, render: Signal<Bool, NoError>) {
        add(path: path, info: info, rendering: render |> map { .completed($0) })
    }

    public func add(path: String, info: PendingVideoRenderInfo, rendering: Signal<PendingVideoRenderEvent, NoError>) {
        let entry = Entry(info: info)
        lock.lock()
        let previous = entries.updateValue(entry, forKey: path)
        updateStreamingVideoHeaderSize(nil, path: path)
        previous?.finish(false)
        guard entries[path] === entry, !entry.finished.with({ $0 }) else {
            lock.unlock()
            previous?.disposable.dispose()
            return
        }
        entry.disposable.set(rendering.start(next: { [weak self, weak entry] event in
            guard let self, let entry else { return }
            self.lock.lock()
            guard self.entries[path] === entry, !entry.finished.with({ $0 }) else {
                self.lock.unlock()
                return
            }
            switch event {
            case let .progress(_, size, headerSize):
                guard headerSize > 0, headerSize <= Int64(Int32.max), size >= headerSize else {
                    entry.finish(false)
                    self.lock.unlock()
                    Queue.concurrentDefaultQueue().async { entry.disposable.dispose() }
                    return
                }
                updateStreamingVideoHeaderSize(headerSize, path: path)
                entry.events.set(.single(event))
            case let .completed(success):
                entry.finish(success)
            }
            self.lock.unlock()
        }, completed: { [weak self, weak entry] in
            guard let self, let entry else { return }
            self.lock.lock()
            if self.entries[path] === entry { entry.finish(false) }
            self.lock.unlock()
            entry.disposable.dispose()
        }))
        lock.unlock()
        previous?.disposable.dispose()
    }

    public func info(for path: String) -> PendingVideoRenderInfo? {
        lock.lock()
        defer { lock.unlock() }
        return entries[path]?.info
    }

    public func result(for path: String) -> Signal<Bool, NoError>? {
        lock.lock()
        defer { lock.unlock() }
        return entries[path].map { $0.result.get() |> take(1) }
    }

    public func events(for path: String) -> Signal<PendingVideoRenderEvent, NoError>? {
        lock.lock()
        defer { lock.unlock() }
        return entries[path]?.events.get()
    }

    public func cancel(path: String) {
        lock.lock()
        let removed = entries.removeValue(forKey: path)
        updateStreamingVideoHeaderSize(nil, path: path)
        if removed != nil { try? FileManager.default.removeItem(atPath: path) }
        removed?.finish(false)
        lock.unlock()
        removed?.disposable.dispose()
    }
}
