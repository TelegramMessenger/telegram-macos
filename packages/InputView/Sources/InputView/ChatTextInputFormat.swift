import Cocoa
import Foundation
import TelegramCore
import TGUIKit

private extension EnginePeer {
    var compactDisplayTitle: String {
        switch self {
        case let .user(user):
            if let firstName = user.firstName, !firstName.isEmpty {
                return firstName
            } else if let lastName = user.lastName, !lastName.isEmpty {
                return lastName
            } else if let _ = user.phone {
                return ""
            } else {
                return "Deleted Account"
            }
        case let .legacyGroup(group):
            return group.title
        case let .channel(channel):
            return channel.title
        case let .community(community):
            return community.title
        case .secretChat:
            return ""
        }
    }

}


public func chatTextInputAddFormattingAttribute(_ state: Updated_ChatTextInputState, attribute: NSAttributedString.Key) -> Updated_ChatTextInputState {
    var selectionRange = state.selectionRange
    if !selectionRange.isEmpty {
        let nsRange = NSRange(location: selectionRange.lowerBound, length: selectionRange.count)
        var hasText = false
        var allTextHasAttribute = true
        var hasCustomEmoji = false
        var allCustomEmojiHaveAttribute = true
        
        state.inputText.enumerateAttributes(in: nsRange, options: []) { attributes, range, _ in
            if attributes[TextInputAttributes.customEmoji] != nil {
                hasCustomEmoji = true
                if attributes[attribute] == nil {
                    allCustomEmojiHaveAttribute = false
                }
                return
            }
            if attribute == TextInputAttributes.quote && (state.inputText.string as NSString).substring(with: range).allSatisfy({ $0 == "\n" }) {
                return
            }
            hasText = true
            if attributes[attribute] == nil {
                allTextHasAttribute = false
            }
        }

        guard hasText || hasCustomEmoji else {
            return state
        }
        
        let result = NSMutableAttributedString(attributedString: state.inputText)
        let shouldRemoveAttribute = hasText ? allTextHasAttribute : allCustomEmojiHaveAttribute
        if shouldRemoveAttribute {
            result.removeAttribute(attribute, range: nsRange)
        } else {
            if attribute == TextInputAttributes.quote {
                result.addAttribute(attribute, value: TextInputTextQuoteAttribute(collapsed: false), range: nsRange)
                if nsRange.upperBound != result.length && (result.string as NSString).character(at: nsRange.upperBound) != 0x0a && (result.string as NSString).character(at: nsRange.upperBound - 1) != 0x0a {
                    result.insert(NSAttributedString(string: "\n"), at: nsRange.upperBound)
                }
                if nsRange.lowerBound != 0 && (result.string as NSString).character(at: nsRange.lowerBound - 1) != 0x0a && (result.string as NSString).character(at: nsRange.lowerBound) != 0x0a {
                    result.insert(NSAttributedString(string: "\n"), at: nsRange.lowerBound)
                    selectionRange = nsRange.lowerBound + 1 ..< nsRange.upperBound + 1

                }
            } else {
                result.addAttribute(attribute, value: true as Bool, range: nsRange)
            }
        }
        return Updated_ChatTextInputState(inputText: result, selectionRange: selectionRange)
    } else {
        return state
    }
}

public func chatTextInputClearFormattingAttributes(_ state: Updated_ChatTextInputState, targetKey: NSAttributedString.Key? = nil) -> Updated_ChatTextInputState {
    if !state.selectionRange.isEmpty {
        let nsRange = NSRange(location: state.selectionRange.lowerBound, length: state.selectionRange.count)
        var attributesToRemove: [(NSAttributedString.Key, NSRange)] = []
        
        state.inputText.enumerateAttributes(in: NSMakeRange(0, state.inputText.length), options: []) { attributes, range, stop in
            for (key, _) in attributes {
                guard key != chatInputAnalyticsExcludedAttribute else { continue }
                if range.intersection(nsRange) != nil {
                    if let targetKey = targetKey {
                        if targetKey == key {
                            attributesToRemove.append((key, range))
                        }
                    } else {
                        if key != TextInputAttributes.customEmoji {
                            attributesToRemove.append((key, range))
                        }
                    }
                }
            }
        }
        
        let result = NSMutableAttributedString(attributedString: state.inputText)
        for (attribute, range) in attributesToRemove {
            result.removeAttribute(attribute, range: range)
        }
        return Updated_ChatTextInputState(inputText: result, selectionRange: state.selectionRange)
    } else {
        return state
    }
}

public func chatTextInputAddLinkAttribute(_ state: Updated_ChatTextInputState, selectionRange: Range<Int>, url: String, text: String, inheritedAnalyticsExclusion: Bool = false) -> Updated_ChatTextInputState {
    guard selectionRange.lowerBound >= 0, selectionRange.upperBound <= state.inputText.length else { return state }
    if !selectionRange.isEmpty {
        let nsRange = NSRange(location: selectionRange.lowerBound, length: selectionRange.count)
        var linkRange = nsRange
        var attributesToRemove: [(NSAttributedString.Key, NSRange)] = []
        var hasExcludedAnalytics = inheritedAnalyticsExclusion
        state.inputText.enumerateAttributes(in: nsRange, options: .longestEffectiveRangeNotRequired) { attributes, range, stop in
            for (key, _) in attributes {
                if key == chatInputAnalyticsExcludedAttribute {
                    hasExcludedAnalytics = true
                } else if key == TextInputAttributes.textUrl {
                    attributesToRemove.append((key, range))
                    linkRange = linkRange.union(range)
                } else {
                    attributesToRemove.append((key, nsRange))
                }
            }
        }
        
        let result = NSMutableAttributedString(attributedString: state.inputText)
        for (attribute, range) in attributesToRemove {
            result.removeAttribute(attribute, range: range)
        }
        result.replaceCharacters(in:nsRange, with: text)
        let length: Int
        if nsRange.length > text.length {
            length = min(nsRange.length, text.length)
        } else {
            length = max(nsRange.length, text.length)
        }
        let updatedRange = NSMakeRange(nsRange.location, length)
        if hasExcludedAnalytics && updatedRange.length > 0 {
            result.addAttribute(chatInputAnalyticsExcludedAttribute, value: true as NSNumber, range: updatedRange)
        }
        result.addAttribute(TextInputAttributes.textUrl, value: TextInputTextUrlAttribute(url: url), range: updatedRange)
        return Updated_ChatTextInputState(inputText: result, selectionRange: updatedRange.lowerBound ..< updatedRange.upperBound)
    } else {
        return state
    }
}

public func chatTextInputAddMentionAttribute(_ state: Updated_ChatTextInputState, peer: EnginePeer) -> Updated_ChatTextInputState {
    let inputText = NSMutableAttributedString(attributedString: state.inputText)
    
    let range = NSMakeRange(state.selectionRange.startIndex, state.selectionRange.endIndex - state.selectionRange.startIndex)
    
    if let addressName = peer.addressName, !addressName.isEmpty {
        let replacementText = "@\(addressName) "
        
        inputText.replaceCharacters(in: range, with: replacementText)
        
        let selectionPosition = range.lowerBound + (replacementText as NSString).length
        
        return Updated_ChatTextInputState(inputText: inputText, selectionRange: selectionPosition ..< selectionPosition)
    } else if !peer.compactDisplayTitle.isEmpty {
        let replacementText = NSMutableAttributedString()
        replacementText.append(NSAttributedString(string: peer.compactDisplayTitle, attributes: [TextInputAttributes.textMention: ChatTextInputTextMentionAttribute(peerId: peer.id)]))
        replacementText.append(NSAttributedString(string: " "))
        
        let updatedRange = NSRange(location: range.location , length: range.length)
        
        inputText.replaceCharacters(in: updatedRange, with: replacementText)
        
        let selectionPosition = updatedRange.lowerBound + replacementText.length
        
        return Updated_ChatTextInputState(inputText: inputText, selectionRange: selectionPosition ..< selectionPosition)
    } else {
        return state
    }
}

public func chatTextInputAddQuoteAttribute(_ state: Updated_ChatTextInputState, selectionRange: Range<Int>, collapsed: Bool = false, doNotUpdateSelection: Bool = false) -> Updated_ChatTextInputState {
    if selectionRange.isEmpty {
        return state
    }
    let nsRange = NSRange(location: selectionRange.lowerBound, length: selectionRange.count)
    var quoteRange = nsRange
    var attributesToRemove: [(NSAttributedString.Key, NSRange)] = []
    state.inputText.enumerateAttributes(in: nsRange, options: .longestEffectiveRangeNotRequired) { attributes, range, stop in
        for (key, _) in attributes {
            if key == TextInputAttributes.quote {
                attributesToRemove.append((key, range))
                quoteRange = quoteRange.union(range)
            }
        }
    }
    
    let result = NSMutableAttributedString(attributedString: state.inputText)
    for (attribute, range) in attributesToRemove {
        result.removeAttribute(attribute, range: range)
    }
    result.addAttribute(TextInputAttributes.quote, value: TextInputTextQuoteAttribute(collapsed: collapsed), range: nsRange)
    return Updated_ChatTextInputState(inputText: result, selectionRange: doNotUpdateSelection ? state.selectionRange : selectionRange)
}

public func chatTextInputReplaceSelectedText(_ state: Updated_ChatTextInputState, selectionRange: Range<Int>, text: NSAttributedString, inheritedAnalyticsExclusion: Bool = false) -> Updated_ChatTextInputState {
    guard selectionRange.lowerBound >= 0, selectionRange.upperBound <= state.inputText.length else { return state }
    let range = NSRange(location: selectionRange.lowerBound, length: selectionRange.count)
    let selected = state.inputText.attributedSubstring(from: range)
    let hasExcludedAnalytics = inheritedAnalyticsExclusion || ChatTextInputState(attributedText: selected, selectionRange: 0..<0).hasExcludedAnalytics
    let replacement = hasExcludedAnalytics ? chatInputTextExcludingAnalytics(text) : text
    let result = NSMutableAttributedString(attributedString: state.inputText)
    result.replaceCharacters(in: range, with: replacement)
    let cursor = range.location + replacement.length
    return Updated_ChatTextInputState(inputText: result, selectionRange: cursor..<cursor)
}

public func chatTextInputAddDateAttribute(_ state: Updated_ChatTextInputState, selectionRange: Range<Int>, date: Int32) -> Updated_ChatTextInputState {
    guard selectionRange.lowerBound >= 0, selectionRange.upperBound <= state.inputText.length else { return state }
    if !selectionRange.isEmpty {
        let nsRange = NSRange(location: selectionRange.lowerBound, length: selectionRange.count)
        let result = NSMutableAttributedString(attributedString: state.inputText)
        result.removeAttribute(TextInputAttributes.formattedDate, range: nsRange)
        result.addAttribute(TextInputAttributes.formattedDate, value: TextInputTextDateAttribute(date: date), range: nsRange)
        return Updated_ChatTextInputState(inputText: result, selectionRange: selectionRange)
    }
    return state
}
