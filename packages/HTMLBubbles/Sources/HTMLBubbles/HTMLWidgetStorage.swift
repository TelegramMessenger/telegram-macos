import Cocoa
import Postbox
import SwiftSignalKit
import WidgetSandbox

public final class HTMLWidgetStorage {
    public static let shared = HTMLWidgetStorage()

    private struct Key: Hashable {
        let basePath: String
        let accountPeerId: PeerId
        let messageId: MessageId

        init(_ context: HTMLWidgetContext) {
            self.basePath = context.basePath
            self.accountPeerId = context.accountPeerId
            self.messageId = context.messageId
        }

        var path: String {
            return HTMLWidgetStorage.path(basePath: basePath, messageId: messageId)
        }
    }

    private static let maximumFileSize = 256 * 1024
    private static let pruneInterval: CFAbsoluteTime = 60
    private let pruneLock = NSLock()
    private var local: [Key: [String: String]] = [:]
    private var session: [Key: [String: String]] = [:]
    private var pending: Set<Key> = []
    private var flushScheduled = false
    private var prunedAt: [String: CFAbsoluteTime] = [:]
    private let queue: DispatchQueue
    private var observers: [NSObjectProtocol] = []

    private convenience init() {
        self.init(queue: DispatchQueue(label: "HTMLBubbles.widgetStorage", qos: .utility))
    }

    init(queue: DispatchQueue) {
        self.queue = queue
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: nil) { [weak self] _ in
            self?.flushAll()
        })
        for name in [NSApplication.willResignActiveNotification, NSApplication.didHideNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.queue.async {
                    self?.writePending()
                }
            })
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private static func directory(basePath: String) -> String {
        return basePath + "/widget-storage"
    }

    private static func path(basePath: String, messageId: MessageId) -> String {
        return directory(basePath: basePath) + "/\(messageId.peerId.toInt64())_\(messageId.namespace)_\(messageId.id).json"
    }

    private static func messageId(fileName: String) -> MessageId? {
        guard fileName.hasSuffix(".json") else {
            return nil
        }
        let parts = fileName.dropLast(5).split(separator: "_")
        guard parts.count == 3, let peerId = Int64(parts[0]), let namespace = Int32(parts[1]), let id = Int32(parts[2]) else {
            return nil
        }
        return MessageId(peerId: PeerId(peerId), namespace: namespace, id: id)
    }

    func storage(for context: HTMLWidgetContext) -> WidgetStorage {
        return queue.sync {
            let key = Key(context)
            let values = local[key] ?? HTMLWidgetStorage.read(key.path)
            local[key] = values
            return WidgetStorage(local: values, session: session[key] ?? [:])
        }
    }

    func commit(_ area: WidgetStorageArea, values: [String: String], context: HTMLWidgetContext) {
        queue.sync {
            let key = Key(context)
            switch area {
            case .local:
                local[key] = values
                pending.insert(key)
                if !flushScheduled {
                    flushScheduled = true
                    queue.asyncAfter(deadline: .now() + 1) { [weak self] in
                        self?.writePending()
                    }
                }
            case .session:
                session[key] = values
            }
        }
    }

    func flush(_ context: HTMLWidgetContext) {
        queue.async {
            let key = Key(context)
            guard self.pending.remove(key) != nil else {
                return
            }
            HTMLWidgetStorage.write(self.local[key] ?? [:], key: key)
        }
    }

    public func removeAll(basePath: String, peerId: PeerId? = nil) {
        queue.async {
            self.forget { $0.basePath == basePath && (peerId == nil || $0.messageId.peerId == peerId) }
            let directory = HTMLWidgetStorage.directory(basePath: basePath)
            guard let peerId = peerId else {
                try? FileManager.default.removeItem(atPath: directory)
                return
            }
            let prefix = "\(peerId.toInt64())_"
            for name in (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? [] where name.hasPrefix(prefix) {
                try? FileManager.default.removeItem(atPath: directory + "/" + name)
            }
        }
    }

    public func pruneDeletedMessages(postbox: Postbox, basePath: String) -> Disposable {
        let disposables = DisposableSet()
        let prune = { [weak self, weak disposables] in
            guard let self = self, let disposables = disposables, self.startPrune(basePath: basePath) else {
                return
            }
            disposables.add(self.deletedMessageIds(postbox: postbox, basePath: basePath).start(next: { [weak self] ids in
                self?.remove(basePath: basePath, messageIds: ids)
            }))
        }
        prune()
        let observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            prune()
        }
        disposables.add(ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        })
        return disposables
    }

    private func startPrune(basePath: String) -> Bool {
        let now = CFAbsoluteTimeGetCurrent()
        pruneLock.lock()
        defer { pruneLock.unlock() }
        if let last = prunedAt[basePath], now - last < HTMLWidgetStorage.pruneInterval {
            return false
        }
        prunedAt[basePath] = now
        return true
    }

    private func deletedMessageIds(postbox: Postbox, basePath: String) -> Signal<[MessageId], NoError> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: HTMLWidgetStorage.directory(basePath: basePath))) ?? []
        let ids = names.compactMap(HTMLWidgetStorage.messageId(fileName:))
        guard !ids.isEmpty else {
            return .complete()
        }
        return postbox.transaction { transaction -> [MessageId] in
            return ids.filter { !transaction.messageExists(id: $0) }
        }
    }

    private func remove(basePath: String, messageIds: [MessageId]) {
        guard !messageIds.isEmpty else {
            return
        }
        let ids = Set(messageIds)
        queue.async {
            self.forget { $0.basePath == basePath && ids.contains($0.messageId) }
            for id in ids {
                try? FileManager.default.removeItem(atPath: HTMLWidgetStorage.path(basePath: basePath, messageId: id))
            }
        }
    }

    private func forget(_ matches: (Key) -> Bool) {
        local = local.filter { !matches($0.key) }
        session = session.filter { !matches($0.key) }
        pending = pending.filter { !matches($0) }
    }

    private func flushAll() {
        queue.sync {
            writePending()
        }
    }

    private func writePending() {
        let keys = pending
        pending.removeAll()
        flushScheduled = false
        let writes = keys.map { ($0, local[$0] ?? [:]) }
        for (key, values) in writes {
            HTMLWidgetStorage.write(values, key: key)
        }
    }

    private static func read(_ path: String) -> [String: String] {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path), let size = attributes[.size] as? NSNumber, size.intValue <= maximumFileSize else {
            return [:]
        }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let values = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] else {
            return [:]
        }
        return values
    }

    private static func write(_ values: [String: String], key: Key) {
        let url = URL(fileURLWithPath: key.path)
        if values.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return
        }
        guard FileManager.default.fileExists(atPath: key.basePath), let data = try? JSONSerialization.data(withJSONObject: values) else {
            return
        }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }
}
