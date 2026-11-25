import Foundation
import Postbox

struct ChatInputAccessoryPanelStack<Key: Hashable> {
    private var keys: [Key] = []

    mutating func update(availableKeys: [Key]?) -> Key? {
        guard let availableKeys else { return nil }
        let available = Set(availableKeys)
        var updatedKeys = keys.filter { available.contains($0) }
        let known = Set(updatedKeys)
        for key in availableKeys.reversed() where !known.contains(key) {
            updatedKeys.append(key)
        }
        keys = updatedKeys
        return updatedKeys.last
    }
}

enum ChatInputAccessoryPanelKey: Hashable {
    enum Kind { case suggestPost, urlPreview, edit, forward, reply }
    case suggestPost
    case urlPreview(String, MessageId?)
    case edit(MessageId)
    case forward([MessageId])
    case reply(MessageId)

    var kind: Kind {
        switch self {
        case .suggestPost: return .suggestPost
        case .urlPreview: return .urlPreview
        case .edit: return .edit
        case .forward: return .forward
        case .reply: return .reply
        }
    }
}
