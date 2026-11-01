import Cocoa
import Postbox
import SwiftSignalKit
import TelegramCore
import Strings

public let diceSymbol: String = "🎲"
public let dartSymbol: String = "🎯"


public struct EmojiSkinModifier : Codable, Equatable {
    public let emoji: String
    public let modifier: String
    public init(emoji: String, modifier: String) {
        self.emoji = emoji.emojiUnmodified
        self.modifier = modifier
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode(emoji, forKey: "e")
        try container.encode(modifier, forKey: "m")
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        self.emoji = try container.decode(String.self, forKey: "e")
        self.modifier = try container.decode(String.self, forKey: "m")
    }
}

private func recentEmojiLineWidth(_ string: String) -> CGFloat {
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: 26)]))
    return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
}

private let recentSingleEmojiWidth = recentEmojiLineWidth("😀")

public extension String {
    var recentEmojiCandidates: [String] {
        return self.map { String($0) }.filter { $0.hasEmojiPresentation }.map { $0.recentEmojiCanonical }.filter { $0.isRecentEmojiCandidate }
    }
}

private func recentEmojiUsing(_ emoji: String, in emojies: [String]) -> [String] {
    guard emoji.isRecentEmojiCandidate else {
        return emojies
    }
    return Array(([emoji] + emojies.filter { $0 != emoji }).prefix(35))
}

private extension String {
    var hasEmojiPresentation: Bool {
        if unicodeScalars.contains("\u{fe0e}") {
            return false
        }
        return unicodeScalars.contains {
            $0 == "\u{fe0f}" || $0 == "\u{20e3}" || $0.properties.isEmojiPresentation || $0.properties.isEmojiModifier
        }
    }
    
    var recentEmojiCanonical: String {
        var scalars = String.UnicodeScalarView(unicodeScalars.filter { $0 != "\u{fe0e}" && $0 != "\u{fe0f}" })
        while scalars.last == "\u{200d}" {
            scalars.removeLast()
        }
        let normalized = String(scalars).normalizedEmoji
        if scalars.count == 1, !normalized.unicodeScalars.contains("\u{fe0f}") {
            return normalized + "\u{fe0f}"
        }
        return normalized
    }
    
    var rendersAsSingleEmoji: Bool {
        guard count == 1, containsEmoji else {
            return false
        }
        if glyphCount == 1 {
            return true
        }
        return recentEmojiLineWidth(self) <= recentSingleEmojiWidth * 1.5
    }
    
    var isRecentEmojiCandidate: Bool {
        let scalars = Array(unicodeScalars)
        guard let first = scalars.first, let last = scalars.last else {
            return false
        }
        let isKeycap = scalars.count > 1 && last == "\u{20e3}" && "0123456789#*".unicodeScalars.contains(first) && scalars.dropFirst().dropLast().allSatisfy { $0 == "\u{fe0f}" }
        let hasEmojiBase = scalars.contains {
            $0.value > 0x7f && $0.properties.isEmoji && !$0.properties.isEmojiModifier
        }
        let hasStrayMark = scalars.contains {
            let category = $0.properties.generalCategory
            let isMark = category == .nonspacingMark || category == .enclosingMark
            return isMark && !$0.properties.isVariationSelector && !(isKeycap && $0 == "\u{20e3}")
        }
        return (hasEmojiBase || isKeycap) && !hasStrayMark && rendersAsSingleEmoji
    }
}

public class RecentUsedEmoji: Codable, Equatable {
    public let emojies:[String]
    public let skinModifiers:[EmojiSkinModifier]
    public let animated:[MediaId]
    public init(emojies:[String], animated: [MediaId], skinModifiers: [EmojiSkinModifier]) {
        self.emojies = emojies
        self.animated = animated
        self.skinModifiers = skinModifiers
    }
    
    public static var defaultSettings: RecentUsedEmoji {
        return RecentUsedEmoji(emojies: ["😂", "😘", "❤️", "😍", "😊", "🤔", "😁", "👍", "☺️", "😔", "😄", "😭", "💋", "😒", "😳", "😜", "🙈", "😉", "😃", "😢", "😝", "😱", "😡", "😏", "😞", "😅", "😚", "🙊", "😌", "😀", "😋", "😆", "🌚", "😐", "😕", "👎", diceSymbol, dartSymbol], animated: [], skinModifiers: [])
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        
        self.animated = try container.decode([MediaId].self, forKey: "ae")
        self.skinModifiers = try container.decode([EmojiSkinModifier].self, forKey: "sm_new")
        let emojies = try container.decode([String].self, forKey: "e")

        var isset = Set<String>()
        var list:[String] = []
        for emoji in emojies {
            let emoji = emoji.recentEmojiCanonical
            if emoji.isRecentEmojiCandidate, isset.insert(emoji).inserted {
                list.append(emoji)
            }
        }
        self.emojies = list
        
        
    }
    
    
    public func removingEmoji(_ emoji: String) -> RecentUsedEmoji {
        let emoji = emoji.recentEmojiCanonical
        return RecentUsedEmoji(emojies: emojies.filter { $0.recentEmojiCanonical != emoji }, animated: animated, skinModifiers: skinModifiers)
    }

    public func removingAnimatedEmoji(_ id: MediaId) -> RecentUsedEmoji {
        return RecentUsedEmoji(emojies: emojies, animated: animated.filter { $0 != id }, skinModifiers: skinModifiers)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode(emojies, forKey: "e")
        try container.encode(skinModifiers, forKey: "sm_new")
        try container.encode(animated, forKey: "ae")

        
    }
}

public func ==(lhs: RecentUsedEmoji, rhs: RecentUsedEmoji) -> Bool {
    return lhs.emojies == rhs.emojies && lhs.skinModifiers == rhs.skinModifiers && lhs.animated == rhs.animated
}


public func saveUsedEmoji(_ list:[String], postbox:Postbox) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> Void in
        transaction.updatePreferencesEntry(key: ApplicationSpecificPreferencesKeys.recentEmoji, { entry in
            let value: RecentUsedEmoji = entry?.get(RecentUsedEmoji.self) ?? RecentUsedEmoji.defaultSettings
            var emojies = value.emojies
            for emoji in list.reversed() {
                emojies = recentEmojiUsing(emoji.recentEmojiCanonical, in: emojies)
            }
            return PreferencesEntry(RecentUsedEmoji(emojies: emojies, animated: value.animated, skinModifiers: value.skinModifiers))
        })
    }
}

public func saveAnimatedUsedEmoji(_ list:[MediaId], postbox:Postbox) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> Void in
        transaction.updatePreferencesEntry(key: ApplicationSpecificPreferencesKeys.recentEmoji, { entry in
            let value: RecentUsedEmoji = entry?.get(RecentUsedEmoji.self) ?? RecentUsedEmoji.defaultSettings

            var animated: [MediaId] = value.animated
            
            animated.insert(contentsOf: list, at: 0)
            var seen = Set<MediaId>()
            animated = animated.filter { seen.insert($0).inserted }
            animated = Array(animated.prefix(32))
            return PreferencesEntry(RecentUsedEmoji(emojies: value.emojies, animated: animated, skinModifiers: value.skinModifiers))
        })
    }
}

public func modifySkinEmoji(_ emoji:String, modifier: String?, recentEmoji: String?, postbox: Postbox) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> Void in
        transaction.updatePreferencesEntry(key: ApplicationSpecificPreferencesKeys.recentEmoji, { entry in
            let settings = entry?.get(RecentUsedEmoji.self) ?? RecentUsedEmoji.defaultSettings
            var skinModifiers = settings.skinModifiers
            let index:Int? = skinModifiers.firstIndex(where: {$0.emoji == emoji})
            
            if let modifier = modifier {
                if let index = index {
                    skinModifiers[index] = EmojiSkinModifier(emoji: emoji, modifier: modifier)
                } else {
                    skinModifiers.append(EmojiSkinModifier(emoji: emoji, modifier: modifier))
                }
            } else if let index = index {
                skinModifiers.remove(at: index)
            }
           
            var emojies = settings.emojies
            if let recentEmoji = recentEmoji, emojies.contains(recentEmoji.recentEmojiCanonical) {
                emojies = recentEmojiUsing((modifier.map { emoji.emojiWithSkinModifier($0) } ?? emoji).recentEmojiCanonical, in: emojies)
            }
            return PreferencesEntry(RecentUsedEmoji(emojies: emojies, animated: settings.animated, skinModifiers: skinModifiers))
            
        })
    }
}

public func removeUsedEmoji(_ emoji: String, postbox: Postbox) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> Void in
        transaction.updatePreferencesEntry(key: ApplicationSpecificPreferencesKeys.recentEmoji, { entry in
            let value = entry?.get(RecentUsedEmoji.self) ?? RecentUsedEmoji.defaultSettings
            return PreferencesEntry(value.removingEmoji(emoji))
        })
    }
}

public func removeAnimatedUsedEmoji(_ id: MediaId, postbox: Postbox) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> Void in
        transaction.updatePreferencesEntry(key: ApplicationSpecificPreferencesKeys.recentEmoji, { entry in
            let value = entry?.get(RecentUsedEmoji.self) ?? RecentUsedEmoji.defaultSettings
            return PreferencesEntry(value.removingAnimatedEmoji(id))
        })
    }
}

public func recentUsedEmoji(postbox: Postbox) -> Signal<RecentUsedEmoji, NoError> {
    return postbox.preferencesView(keys: [ApplicationSpecificPreferencesKeys.recentEmoji]) |> map { preferences in
        return preferences.values[ApplicationSpecificPreferencesKeys.recentEmoji]?.get(RecentUsedEmoji.self) ?? RecentUsedEmoji.defaultSettings
    } |> deliverOn(.concurrentDefaultQueue())
}
