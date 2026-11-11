import Foundation

struct ChatRichTextDraftKey: Hashable {
    let accountId: Int64
    let peerId: Int64
    let threadId: Int64?
    let isWelcome: Bool
    var isCustomEditor: Bool = false
}

final class ChatRichTextDraftRevision {
    private let lock = NSLock()
    private var valid = true

    var isValid: Bool {
        lock.lock()
        defer { lock.unlock() }
        return valid
    }

    fileprivate func invalidate() {
        lock.lock()
        valid = false
        lock.unlock()
    }
}

private final class WeakChatRichTextDraftRevision {
    weak var value: ChatRichTextDraftRevision?

    init(_ value: ChatRichTextDraftRevision) {
        self.value = value
    }
}

final class ChatRichTextDraftStore<Value: Equatable, Origin: AnyObject> {
    private let lock = NSLock()
    private var values: [ChatRichTextDraftKey: Value] = [:]
    private var origins: [ChatRichTextDraftKey: Origin] = [:]
    private var revisions: [ChatRichTextDraftKey: [WeakChatRichTextDraftRevision]] = [:]

    func value(for key: ChatRichTextDraftKey) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }

    func entry(for key: ChatRichTextDraftKey) -> (value: Value, origin: Origin?)? {
        lock.lock()
        defer { lock.unlock() }
        guard let value = values[key] else { return nil }
        return (value, origins[key])
    }

    @discardableResult
    func set(_ value: Value?, for key: ChatRichTextDraftKey, origin: Origin? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let origin = value == nil ? nil : origin
        guard values[key] != value || origins[key] !== origin else { return false }
        values[key] = value
        origins[key] = origin
        for revision in revisions.removeValue(forKey: key) ?? [] {
            revision.value?.invalidate()
        }
        return true
    }

    func captureRevision(for key: ChatRichTextDraftKey) -> ChatRichTextDraftRevision {
        lock.lock()
        defer { lock.unlock() }
        revisions = revisions.compactMapValues { values in
            let live = values.filter { $0.value != nil }
            return live.isEmpty ? nil : live
        }
        let revision = ChatRichTextDraftRevision()
        revisions[key, default: []].append(WeakChatRichTextDraftRevision(revision))
        return revision
    }
}
