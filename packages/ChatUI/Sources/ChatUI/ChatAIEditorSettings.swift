import Foundation
import Postbox
import SwiftSignalKit
import TelegramCore

public struct ChatAIEditorSettings: Codable, Equatable {
    public enum Kind: Int32 {
        case translate = 0
        case style = 1
        case fix = 2
    }

    private let kindValue: Int32
    public let language: String?
    public let emojify: Bool
    private let standardStyle: String?
    private let customStyleId: Int64?
    private let customStyleAccessHash: Int64?

    public init(kind: Kind, language: String? = nil, emojify: Bool = false, style: TelegramComposeAIMessageMode.CloudStyle.Reference? = nil) {
        self.kindValue = kind.rawValue
        self.language = language
        self.emojify = emojify
        switch style {
        case let .standard(name):
            standardStyle = name
            customStyleId = nil
            customStyleAccessHash = nil
        case let .custom(id, accessHash):
            standardStyle = nil
            customStyleId = id
            customStyleAccessHash = accessHash
        case nil:
            standardStyle = nil
            customStyleId = nil
            customStyleAccessHash = nil
        }
    }

    public var kind: Kind {
        Kind(rawValue: kindValue) ?? .style
    }

    public var style: TelegramComposeAIMessageMode.CloudStyle.Reference? {
        if let standardStyle {
            return .standard(standardStyle)
        }
        if let customStyleId, let customStyleAccessHash {
            return .custom(id: customStyleId, accessHash: customStyleAccessHash)
        }
        return nil
    }

    var mode: TelegramComposeAIMessageMode? {
        let style = style.map(TelegramComposeAIMessageMode.StyleReference.style) ?? .neutral
        switch kind {
        case .translate:
            guard let language, !language.isEmpty else { return nil }
            return .translate(toLanguage: language, emojify: emojify, style: style)
        case .style:
            guard style != .neutral || emojify else { return nil }
            return .stylize(emojify: emojify, style: style)
        case .fix:
            return .proofread
        }
    }

    private static let preferenceKeyPrefix = applicationSpecificPreferencesKey(56).getInt32(0)

    private static func key(_ peerId: PeerId) -> ValueBoxKey {
        let key = ValueBoxKey(length: 12)
        key.setInt32(0, value: preferenceKeyPrefix)
        key.setInt64(4, value: peerId.toInt64())
        return key
    }

    public static func observe(postbox: Postbox, peerId: PeerId) -> Signal<ChatAIEditorSettings?, NoError> {
        let key = key(peerId)
        return postbox.preferencesView(keys: [key])
        |> map { view in
            guard let settings = view.values[key]?.get(ChatAIEditorSettings.self), settings.mode != nil else {
                return nil
            }
            return settings
        }
        |> distinctUntilChanged
    }

    public static func save(_ settings: ChatAIEditorSettings?, postbox: Postbox, peerId: PeerId) {
        let key = key(peerId)
        _ = postbox.transaction { transaction in
            transaction.updatePreferencesEntry(key: key, { _ in settings.flatMap { PreferencesEntry($0) } })
        }.startStandalone()
    }
}
