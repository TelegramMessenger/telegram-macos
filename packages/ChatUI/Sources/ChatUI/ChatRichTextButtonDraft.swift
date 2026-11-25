import Foundation
import Postbox
import TelegramCore
import RichTextEditorCore

struct ChatRichTextButtonDraft: Equatable {
    enum Choice: CaseIterable {
        case url, copyText, userProfile
    }

    var action: ButtonAction
    var profileName: String?

    var choice: Choice? {
        switch action {
        case .url: return .url
        case .copyText: return .copyText
        case .userProfile: return .userProfile
        case .disabled, .unsupported: return nil
        }
    }

    var text: String {
        switch action {
        case let .url(value), let .copyText(value): return value
        default: return ""
        }
    }

    var profileId: PeerId? {
        guard case let .userProfile(raw) = action, raw > 0 else { return nil }
        let bits = UInt64(raw)
        guard (bits >> 32) & 7 == 0 else { return nil }
        let userId = Int64(((bits >> 35) << 32) | (bits & 0xffffffff))
        guard userId > 0, userId < (1 << 52) else { return nil }
        let id = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(userId))
        return id.toInt64() == raw ? id : nil
    }

    mutating func select(_ choice: Choice) {
        guard self.choice != choice else { return }
        profileName = nil
        switch choice {
        case .url: action = .url("")
        case .copyText: action = .copyText("")
        case .userProfile: action = .userProfile(peerId: 0)
        }
    }

    mutating func updateText(_ value: String) {
        switch action {
        case .url: action = .url(value)
        case .copyText: action = .copyText(value)
        default: break
        }
    }

    mutating func selectUser(id: PeerId, name: String) {
        guard choice == .userProfile, id.namespace == Namespaces.Peer.CloudUser,
              id.id._internalGetInt64Value() > 0, id.id._internalGetInt64Value() < (1 << 52) else { return }
        action = .userProfile(peerId: id.toInt64())
        profileName = name
    }

    func validatedAction(validateURL: (String) -> String?) -> ButtonAction? {
        switch action {
        case let .url(value):
            return validateURL(value.trimmingCharacters(in: .whitespacesAndNewlines)).map(ButtonAction.url)
        case .userProfile:
            return profileId == nil ? nil : action
        default:
            return action
        }
    }
}
