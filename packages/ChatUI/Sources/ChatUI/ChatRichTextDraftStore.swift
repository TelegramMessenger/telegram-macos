import Foundation

struct ChatRichTextDraftKey: Hashable {
    let accountId: Int64
    let peerId: Int64
    let threadId: Int64?
    let isWelcome: Bool
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

final class ChatRichTextDraftStore<Value: Equatable> {
    private let lock = NSLock()
    private var values: [ChatRichTextDraftKey: Value] = [:]
    private var revisions: [ChatRichTextDraftKey: [WeakChatRichTextDraftRevision]] = [:]

    func value(for key: ChatRichTextDraftKey) -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }


    @discardableResult
    func set(_ value: Value?, for key: ChatRichTextDraftKey) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard values[key] != value else { return false }
        values[key] = value
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
