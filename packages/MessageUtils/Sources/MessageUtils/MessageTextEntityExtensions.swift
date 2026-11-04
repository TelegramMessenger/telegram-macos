import Foundation
import TelegramCore
import Postbox

public extension MessageTextEntity {
    func intersectsOrAdjacent(with attribute: MessageTextEntity) -> Bool {
        return self.range.upperBound >= attribute.range.lowerBound && self.range.lowerBound <= attribute.range.upperBound
    }
    
    func isSameAttribute(_ rhs: MessageTextEntity) -> Bool {
        switch self.type {
        case .Unknown:
            return self.weight == rhs.weight
        case .Mention:
            return self.weight == rhs.weight
        case .Hashtag:
            return self.weight == rhs.weight
        case .BotCommand:
            return self.weight == rhs.weight
        case .Url:
            return self.weight == rhs.weight
        case .Email:
            return self.weight == rhs.weight
        case .Bold:
            return self.weight == rhs.weight
        case .Italic:
            return self.weight == rhs.weight
        case .Code:
            return self.weight == rhs.weight
        case let .Pre(language):
            if case let .Pre(otherLanguage) = rhs.type {
                return language == otherLanguage
            }
            return false
        case .PhoneNumber:
            return self.weight == rhs.weight
        case .Strikethrough:
            return self.weight == rhs.weight
        case .BlockQuote:
            return false
        case .Underline:
            return self.weight == rhs.weight
        case .BankCard:
            return self.weight == rhs.weight
        case .Spoiler:
            return self.weight == rhs.weight
        case .TonAddress:
            return self.weight == rhs.weight
        case .CustomEmoji(stickerPack: _, fileId: _):
            return false
        case .Custom(type: let type):
            switch rhs.type {
            case .Custom(type):
                return true
            default:
                return false
            }
        case .TextUrl(url: let url):
            switch rhs.type {
            case .TextUrl(url):
                return true
            default:
                return false
            }
        case .TextMention(peerId: let peerId):
            switch rhs.type {
            case .TextMention(peerId):
                return true
            default:
                return false
            }
        case let .FormattedDate(format, date):
            switch rhs.type {
            case .FormattedDate(format, date):
                return true
            default:
                return false
            }
        }
    }

    mutating func merge(with attribute: MessageTextEntity) {
        let newStart = min(self.range.lowerBound, attribute.range.lowerBound)
        let newEnd = max(self.range.upperBound, attribute.range.upperBound)
        self.range = newStart..<newEnd
    }
    
    var weight: Int {
        switch self.type {
        case .Unknown:
            return 0
        case .Mention:
            return 1
        case .Hashtag:
            return 2
        case .BotCommand:
            return 3
        case .Url:
            return 4
        case .Email:
            return 5
        case .Bold:
            return 6
        case .Italic:
            return 7
        case .TextUrl:
            return 10
        case .TextMention:
            return 11
        case .PhoneNumber:
            return 12
        case .Strikethrough:
            return 13
        case .Underline:
            return 15
        case .BankCard:
            return 16
        case .Spoiler:
            return 17
        case .CustomEmoji:
            return 18
        case .Custom:
            return 19
        case .Code:
            return 20
        case .Pre:
            return 21
        case .BlockQuote:
            return 22
        case .FormattedDate:
            return 23
        case .TonAddress:
            return 24
        }
    }
}

public func concatMessageAttributes(_ attributes: [MessageTextEntity]) -> [MessageTextEntity] {
    guard !attributes.isEmpty else { return [] }

    let sortedAttributes = attributes.sorted { $0.weight < $1.weight }
    var mergedAttributes = [MessageTextEntity]()

    var currentAttribute = sortedAttributes.first!

    for attribute in sortedAttributes.dropFirst() {
        if currentAttribute.isSameAttribute(attribute) && currentAttribute.intersectsOrAdjacent(with: attribute) {
            currentAttribute.merge(with: attribute)
        } else {
            mergedAttributes.append(currentAttribute)
            currentAttribute = attribute
        }
    }
    // Append the last merged or unmerged attribute
    mergedAttributes.append(currentAttribute)

    return mergedAttributes
}
