import Foundation
import Postbox
import TelegramCore

struct ChatRichTextDraftKey: Hashable {
    let accountId: Int64
    let peerId: Int64
    let threadId: Int64?
    let isWelcome: Bool
}

final class ChatRichTextDraftEntry: Codable {
    let page: InstantPage

    init(page: InstantPage) {
        self.page = page
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        let pageData = try container.decode(AdaptedPostboxDecoder.RawObjectData.self, forKey: "page")
        self.page = InstantPage(decoder: PostboxDecoder(buffer: MemoryBuffer(data: pageData.data)))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode(PostboxEncoder().encodeObjectToRawData(self.page), forKey: "page")
    }
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
