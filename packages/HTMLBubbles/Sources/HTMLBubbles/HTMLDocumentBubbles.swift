import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit

public enum HTMLDocumentBubbles {
    public static let maxSize: Int64 = 256 * 1024
    public static let botIds: Set<Int64> = [8736535756]

    static let debugBotIdsKey = "HTMLBubbles.documentBotIds"

    public static var allowedBotIds: Set<Int64> {
        return botIds.union(debugBotIds(UserDefaults.standard))
    }

    static func debugBotIds(_ defaults: UserDefaults) -> Set<Int64> {
        guard let values = defaults.array(forKey: debugBotIdsKey) else {
            return []
        }
        return Set(values.compactMap { value -> Int64? in
            if let number = value as? NSNumber {
                return number.int64Value
            }
            if let string = value as? String {
                return Int64(string)
            }
            return nil
        })
    }

    public static func isHTMLDocument(mimeType: String, fileName: String?, size: Int64?) -> Bool {
        guard let size = size, size > 0, size <= maxSize else {
            return false
        }
        if mimeType.lowercased().trimmingCharacters(in: .whitespaces) == "text/html" {
            return true
        }
        if let fileName = fileName, fileName.lowercased().hasSuffix(".html") {
            return true
        }
        return false
    }

    public static func isAllowedAuthor(_ authorId: PeerId?, allowlist: Set<Int64> = allowedBotIds) -> Bool {
        guard let authorId = authorId, authorId.namespace == Namespaces.Peer.CloudUser else {
            return false
        }
        return allowlist.contains(authorId.id._internalGetInt64Value())
    }

    public static func document(in message: Message, allowlist: Set<Int64> = allowedBotIds) -> TelegramMediaFile? {
        guard message.flags.contains(.Incoming), message.id.namespace == Namespaces.Message.Cloud, isAllowedAuthor(message.author?.id, allowlist: allowlist) else {
            return nil
        }
        guard message.media.count == 1, let file = message.media.first as? TelegramMediaFile else {
            return nil
        }
        guard isHTMLDocument(mimeType: file.mimeType, fileName: file.fileName, size: file.size) else {
            return nil
        }
        return file
    }

    public static func decode(_ data: Data) -> String? {
        guard !data.isEmpty, Int64(data.count) <= maxSize, let html = String(data: data, encoding: .utf8) else {
            return nil
        }
        return html
    }

    public enum Style: String {
        case bare
        case card
        case bubble
        case full
    }

    static let styleKey = "HTMLBubbles.documentStyle"
    static let statsKey = "HTMLBubbles.documentStats"

    public static var style: Style {
        return style(UserDefaults.standard)
    }

    static func style(_ defaults: UserDefaults) -> Style {
        return defaults.string(forKey: styleKey).flatMap { Style(rawValue: $0.lowercased()) } ?? .bare
    }

    public static let bubbleWidth: CGFloat = 440
    public static let bubbleWidthRange: ClosedRange<CGFloat> = 200 ... 480

    private static let widthHintRegex = try? NSRegularExpression(pattern: "\\bdata-width\\s*=\\s*[\"']?\\s*(\\d{1,5})", options: [.caseInsensitive])

    public static func widthHint(_ html: String) -> CGFloat? {
        return firstNumber(widthHintRegex, html).map { min(max($0, bubbleWidthRange.lowerBound), bubbleWidthRange.upperBound) }
    }

    public static func bubbleWidth(_ html: String) -> CGFloat {
        return widthHint(html) ?? bubbleWidth
    }

    private static func firstNumber(_ regex: NSRegularExpression?, _ html: String) -> CGFloat? {
        let range = NSRange(html.startIndex..., in: html)
        guard let regex = regex, let match = regex.firstMatch(in: html, options: [], range: range), let group = Range(match.range(at: 1), in: html), let value = Double(html[group]) else {
            return nil
        }
        return CGFloat(value)
    }

    private static let morphRegex = try? NSRegularExpression(pattern: "^\\s*(?:<!--[\\s\\S]*?-->\\s*|<(style|script)\\b[^>]*>[\\s\\S]*?</\\1\\s*>\\s*|<meta\\b[^>]*>\\s*)*<[a-zA-Z][^>]*\\sdata-morph\\b", options: [.caseInsensitive])

    public static func isMorphable(_ html: String) -> Bool {
        guard let regex = morphRegex else {
            return false
        }
        return regex.firstMatch(in: html, options: [], range: NSRange(html.startIndex..., in: html)) != nil
    }

    public static let skeletonHeight: CGFloat = 180
    public static let heightHintRange: ClosedRange<CGFloat> = 40 ... 1200

    private static let heightHintRegex = try? NSRegularExpression(pattern: "\\bdata-height\\s*=\\s*[\"']?\\s*(\\d{1,5})", options: [.caseInsensitive])

    public static func heightHint(_ html: String) -> CGFloat? {
        return firstNumber(heightHintRegex, html).map { min(max($0, heightHintRange.lowerBound), heightHintRange.upperBound) }
    }

    public static func makeState(html: String) -> HTMLBubbleState {
        let state = HTMLBubbleState(html: html, outgoing: false, engine: .twidget, selfContained: true)
        state.heightHint = heightHint(html) ?? 0
        state.showsStats = UserDefaults.standard.bool(forKey: statsKey)
        return state
    }
}

public final class HTMLDocumentStore {
    public struct Key: Hashable {
        let box: ObjectIdentifier
        let messageId: MessageId
        let resourceId: String
    }

    private struct MessageKey: Hashable {
        let box: ObjectIdentifier
        let messageId: MessageId
    }

    public enum Status {
        case loading(Key)
        case ready(HTMLBubbleState)
        case failed
    }

    private enum Entry {
        case loading([() -> Void])
        case ready(HTMLBubbleState)
        case failed
    }

    public static let shared = HTMLDocumentStore()

    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    private var order: [Key] = []
    private var latest: [MessageKey: HTMLBubbleState] = [:]
    private var disposables: [Key: Disposable] = [:]
    private let queue = Queue(name: "HTMLDocumentStore", qos: .userInitiated)
    private let capacity = 48

    public func status(mediaBox: MediaBox, message: Message, file: TelegramMediaFile) -> Status {
        let key = Key(box: ObjectIdentifier(mediaBox), messageId: message.id, resourceId: file.resource.id.stringRepresentation)
        lock.lock()
        let existing = entries[key]
        lock.unlock()
        switch existing {
        case .loading:
            return .loading(key)
        case let .ready(state):
            return .ready(state)
        case .failed:
            guard mediaBox.completedResourcePath(file.resource) != nil else {
                return .failed
            }
        case .none:
            break
        }
        if !Thread.isMainThread, previousState(mediaBox: mediaBox, messageId: message.id) == nil, let path = mediaBox.completedResourcePath(file.resource) {
            let state = HTMLDocumentStore.load(path: path)
            lock.lock()
            if case .loading = entries[key] {
                lock.unlock()
                return .loading(key)
            }
            if existing == nil {
                order.append(key)
            }
            lock.unlock()
            finish(key: key, state: state, force: true)
            lock.lock()
            defer { lock.unlock() }
            if case let .ready(cached) = entries[key] {
                return .ready(cached)
            }
            return .failed
        }
        lock.lock()
        if case .loading = entries[key] {
            lock.unlock()
            return .loading(key)
        }
        if entries[key] == nil {
            order.append(key)
        }
        entries[key] = .loading([])
        lock.unlock()
        start(key: key, mediaBox: mediaBox, message: message, file: file)
        return .loading(key)
    }

    static func load(path: String) -> HTMLBubbleState? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe), let html = HTMLDocumentBubbles.decode(data) else {
            return nil
        }
        return HTMLDocumentBubbles.makeState(html: html)
    }

    public func previousState(mediaBox: MediaBox, messageId: MessageId) -> HTMLBubbleState? {
        lock.lock()
        defer { lock.unlock() }
        return latest[MessageKey(box: ObjectIdentifier(mediaBox), messageId: messageId)]
    }

    public func whenResolved(_ key: Key, _ callback: @escaping () -> Void) {
        lock.lock()
        if case let .loading(callbacks) = entries[key] {
            entries[key] = .loading(callbacks + [callback])
            lock.unlock()
            return
        }
        lock.unlock()
        DispatchQueue.main.async(execute: callback)
    }

    private func start(key: Key, mediaBox: MediaBox, message: Message, file: TelegramMediaFile) {
        let reference = FileMediaReference.message(message: MessageReference(message), media: file).resourceReference(file.resource)
        let fetch = fetchedMediaResource(mediaBox: mediaBox, userLocation: .peer(message.id.peerId), userContentType: .file, reference: reference)
        let data = mediaBox.resourceData(file.resource) |> filter { $0.complete } |> take(1) |> map { Optional($0.path) }
        let signal = Signal<String?, NoError> { subscriber in
            let fetchDisposable = fetch.start()
            let dataDisposable = data.start(next: { path in
                subscriber.putNext(path)
                subscriber.putCompletion()
            })
            return ActionDisposable {
                fetchDisposable.dispose()
                dataDisposable.dispose()
            }
        } |> timeout(30, queue: queue, alternate: .single(nil)) |> deliverOn(queue)

        let disposable = signal.start(next: { [weak self] path in
            guard let self = self else {
                return
            }
            let html = path.flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0), options: .mappedIfSafe) }.flatMap(HTMLDocumentBubbles.decode)
            guard let html = html else {
                self.finish(key: key, state: nil)
                return
            }
            guard HTMLDocumentBubbles.isMorphable(html), let previous = self.previousState(mediaBox: mediaBox, messageId: key.messageId) else {
                self.finish(key: key, state: HTMLDocumentBubbles.makeState(html: html))
                return
            }
            DispatchQueue.main.async {
                previous.morph(html: html) { [weak self] applied in
                    guard let self = self else {
                        return
                    }
                    if applied {
                        previous.heightHint = HTMLDocumentBubbles.heightHint(html) ?? previous.heightHint
                        self.finish(key: key, state: previous)
                    } else {
                        self.queue.async {
                            self.finish(key: key, state: HTMLDocumentBubbles.makeState(html: html))
                        }
                    }
                }
            }
        })
        lock.lock()
        if case .loading = entries[key] {
            disposables[key] = disposable
            lock.unlock()
        } else {
            lock.unlock()
            disposable.dispose()
        }
    }

    private func finish(key: Key, state: HTMLBubbleState?, force: Bool = false) {
        lock.lock()
        var callbacks: [() -> Void] = []
        switch entries[key] {
        case let .loading(pending):
            callbacks = pending
        case .ready:
            lock.unlock()
            return
        case .failed, .none:
            guard force else {
                lock.unlock()
                return
            }
        }
        if let state = state {
            entries[key] = .ready(state)
            latest[MessageKey(box: key.box, messageId: key.messageId)] = state
            let replaced = entries.keys.filter { other in
                guard other != key, other.box == key.box, other.messageId == key.messageId, case .ready = entries[other] else {
                    return false
                }
                return true
            }
            for other in replaced {
                entries.removeValue(forKey: other)
            }
            order.removeAll(where: { replaced.contains($0) })
        } else {
            entries[key] = .failed
        }
        disposables.removeValue(forKey: key)
        let evicted = evict()
        lock.unlock()
        evicted.forEach { $0.dispose() }
        if !callbacks.isEmpty {
            DispatchQueue.main.async {
                callbacks.forEach { $0() }
            }
        }
    }

    private func evict() -> [Disposable] {
        var removed: [Disposable] = []
        while order.count > capacity, let index = order.firstIndex(where: { if case .loading = entries[$0] { return false } else { return true } }) {
            let key = order.remove(at: index)
            entries.removeValue(forKey: key)
            let messageKey = MessageKey(box: key.box, messageId: key.messageId)
            if !entries.keys.contains(where: { $0.box == key.box && $0.messageId == key.messageId }) {
                latest.removeValue(forKey: messageKey)
            }
            if let disposable = disposables.removeValue(forKey: key) {
                removed.append(disposable)
            }
        }
        return removed
    }
}
