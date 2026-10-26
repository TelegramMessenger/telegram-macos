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
        var emoji = emoji
        for skin in emoji.emojiSkinToneModifiers {
            emoji = emoji.replacingOccurrences(of: skin, with: "")
        }
        self.emoji = emoji
        self.modifier = modifier
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode(emoji, forKey: "e")
        try container.encode(modifier, forKey: "m")
    }
    
    public var modify: String {
        var e:String = emoji
        if emoji.length == 5 {
            let mutable = NSMutableString()
            mutable.insert(e, at: 0)
            mutable.insert(modifier, at: 2)
            e = mutable as String
        } else {
            e = emoji + modifier
        }
        return e
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
        return self.map { String($0) }.filter { $0.isRecentEmojiCandidate }
    }
}

private extension String {
    var rendersAsSingleEmoji: Bool {
        guard count == 1, containsEmoji else {
            return false
        }
        if glyphCount == 1 {
            return true
        }
        return recentEmojiLineWidth(self) <= recentSingleEmojiWidth * 1.5
    }
    
    var withoutTrailingVariationSelectors: String {
        var scalars = String.UnicodeScalarView(unicodeScalars)
        while scalars.last == "\u{fe0f}" {
            scalars.removeLast()
        }
        return String(scalars)
    }
    
    var isRecentEmojiCandidate: Bool {
        return rendersAsSingleEmoji && unicodeScalars.contains { $0.value > 0x7f && !$0.properties.isVariationSelector }
    }
}

public class RecentUsedEmoji: Codable, Equatable {
    private let _emojies:[String]
    public let skinModifiers:[EmojiSkinModifier]
    public let animated:[MediaId]
    public init(emojies:[String], animated: [MediaId], skinModifiers: [EmojiSkinModifier]) {
        self._emojies = emojies
        self.animated = animated
        self.skinModifiers = skinModifiers
    }
    
    public static var defaultSettings: RecentUsedEmoji {
        return RecentUsedEmoji(emojies: ["😂", "😘", "❤️", "😍", "😊", "🤔", "😁", "👍", "☺️", "😔", "😄", "😭", "💋", "😒", "😳", "😜", "🙈", "😉", "😃", "😢", "😝", "😱", "😡", "😏", "😞", "😅", "😚", "🙊", "😌", "😀", "😋", "😆", "🌚", "😐", "😕", "👎", diceSymbol, dartSymbol], animated: [], skinModifiers: [])
    }
    
    public var emojies: [String] {
        var isset = Set<String>()
        var list:[String] = []
        for emoji in _emojies {
            var value = emoji
            if value.emojiHasSkinTone, !value.rendersAsSingleEmoji {
                value = String(String.UnicodeScalarView(value.unicodeScalars.filter { !$0.properties.isEmojiModifier }))
            }
            guard let first = value.first else {
                continue
            }
            value = String(first)
            let key = value.strippedEmoji
            if !key.isEmpty, !value.emojiSkinToneModifiers.contains(value), isset.insert(key).inserted {
                list.append(value)
            }
        }
        return list
    }
    
    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)
        
        self.animated = try container.decode([MediaId].self, forKey: "ae")
        self.skinModifiers = try container.decode([EmojiSkinModifier].self, forKey: "sm_new")
        let emojies = try container.decode([String].self, forKey: "e")

        var isset = Set<String>()
        var list:[String] = []
        for emoji in emojies {
            let key = emoji.strippedEmoji
            if !key.isEmpty, emoji != "�", !emoji.emojiSkinToneModifiers.contains(emoji), isset.insert(key).inserted {
                let emoji = emoji.withoutTrailingVariationSelectors
                let updated = emoji + "\u{fe0f}"
                if updated.isRecentEmojiCandidate {
                    list.append(updated)
                } else if emoji.isRecentEmojiCandidate {
                    list.append(emoji)
                }
            }
        }
        self._emojies = list
        
        
    }
    
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode(_emojies, forKey: "e")
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
            var emojies: [String]
            let value: RecentUsedEmoji = entry?.get(RecentUsedEmoji.self) ?? RecentUsedEmoji.defaultSettings
            emojies = value.emojies.filter {
                $0.isRecentEmojiCandidate
            }
            
            for emoji in list.reversed() {
                if emoji.isRecentEmojiCandidate {
                    let key = emoji.strippedEmoji
                    if !key.isEmpty && emoji.count == 1 {
                        if let index = emojies.firstIndex(where: { $0.strippedEmoji == key }) {
                            emojies.remove(at: index)
                        }
                        emojies.insert(emoji, at: 0)
                    }
                }
            }
            emojies = Array(emojies.filter({$0.containsEmoji}).prefix(35))
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

public func modifySkinEmoji(_ emoji:String, modifier: String?, postbox: Postbox) -> Signal<Void, NoError> {
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
           
            return PreferencesEntry(RecentUsedEmoji(emojies: settings.emojies, animated: settings.animated, skinModifiers: skinModifiers))
            
        })
    }
}

public func recentUsedEmoji(postbox: Postbox) -> Signal<RecentUsedEmoji, NoError> {
    return postbox.preferencesView(keys: [ApplicationSpecificPreferencesKeys.recentEmoji]) |> map { preferences in
        return preferences.values[ApplicationSpecificPreferencesKeys.recentEmoji]?.get(RecentUsedEmoji.self) ?? RecentUsedEmoji.defaultSettings
    } |> deliverOn(.concurrentDefaultQueue())
}
