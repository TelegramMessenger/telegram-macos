import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit

private func concatAttributes(_ attributes: [ChatTextInputAttribute]) -> [ChatTextInputAttribute] {
    guard !attributes.isEmpty else { return [] }

    let sortedAttributes = attributes.sorted { $0.weight < $1.weight }
    var mergedAttributes = [ChatTextInputAttribute]()

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

private let markdownRegexFormat = "(^|\\s|\\n)(````?)([\\s\\S]+?)(````?)([\\s\\n\\.,:?!;]|$)|(^|\\s)(`|\\*\\*|__|~~|\\|\\|)([^\\n]+?)\\7([\\s\\.,:?!;]|$)|@(\\d+)\\s*\\((.+?)\\)"
private let markdownRegex = try? NSRegularExpression(pattern: markdownRegexFormat, options: [.caseInsensitive, .anchorsMatchLines])



public enum ChatTextInputAttribute : Equatable, Comparable, Codable {
    case bold(Range<Int>)
    case strikethrough(Range<Int>)
    case spoiler(Range<Int>)
    case underline(Range<Int>)
    case italic(Range<Int>)
    case pre(Range<Int>, String?)
    case code(Range<Int>)
    case uid(Range<Int>, Int64)
    case url(Range<Int>, String)
    case animated(Range<Int>, String, Int64, TelegramMediaFile?, ItemCollectionId?)
    case quote(Range<Int>, Bool)
    case date(Range<Int>, Int32)
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: StringCodingKey.self)

        let lowerBound = Int(try container.decode(Int32.self, forKey: "start"))
        let upperBound = Int(try container.decode(Int32.self, forKey: "end"))
        let range = lowerBound ..< upperBound

        let type: Int32 = try container.decode(Int32.self, forKey: "_rawValue")
        switch type {
        case 0:
            self = .bold(range)
        case 1:
            self = .italic(range)
        case 2:
            self = .pre(range, try container.decodeIfPresent(String.self, forKey: "language"))
        case 3:
            self = .uid(range, try container.decode(Int64.self, forKey: "uid"))
        case 4:
            self = .code(range)
        case 5:
            self = .url(range, try container.decode(String.self, forKey: "url"))
        case 6:
            self = .strikethrough(range)
        case 7:
            self = .spoiler(range)
        case 8:
            self = .underline(range)
        case 9:
            self = .animated(range, try container.decode(String.self, forKey: "id"), try container.decode(Int64.self, forKey: "fileId"), try container.decodeIfPresent(TelegramMediaFile.self, forKey: "file"), try container.decodeIfPresent(ItemCollectionId.self, forKey: "info"))
        case 10:
            self = .quote(range, try container.decodeIfPresent(Bool.self, forKey: "collapsed") ?? false)
        case 11:
            self = .date(range, try container.decode(Int32.self, forKey: "date"))
        case 12:
            self = .bold(0..<0)
        default:
            self = .bold(range)
            //fatalError("input attribute not supported")
        }
    }
    public var weight: Int {
        switch self {
        case .bold:
            return 0
        case .italic:
            return 1
        case .pre:
            return 2
        case .code:
            return 3
        case .strikethrough:
            return 4
        case .uid:
            return 5
        case .url:
            return 6
        case .spoiler:
            return 7
        case .underline:
            return 8
        case .animated:
            return 9
        case .quote:
            return 11
        case .date:
            return 10
        }
    }

    public static func <(lhs: ChatTextInputAttribute, rhs: ChatTextInputAttribute) -> Bool {
        if lhs.weight != rhs.weight {
            return lhs.weight < rhs.weight
        }
        return lhs.range.lowerBound < rhs.range.lowerBound
    }

    public func encode(to encoder: Encoder) throws {

        var container = encoder.container(keyedBy: StringCodingKey.self)

        try container.encode(Int32(self.range.lowerBound), forKey: "start")
        try container.encode(Int32(self.range.upperBound), forKey: "end")
        switch self {
        case .bold:
            try container.encode(Int32(0), forKey: "_rawValue")
        case .italic:
            try container.encode(Int32(1), forKey: "_rawValue")
        case let .pre(_, language):
            try container.encode(Int32(2), forKey: "_rawValue")
            try container.encodeIfPresent(language, forKey: "language")
        case .code:
            try container.encode(Int32(4), forKey: "_rawValue")
        case .strikethrough:
            try container.encode(Int32(6), forKey: "_rawValue")
        case .spoiler:
            try container.encode(Int32(7), forKey: "_rawValue")
        case .underline:
            try container.encode(Int32(8), forKey: "_rawValue")
        case let .uid(_, uid):
            try container.encode(Int32(3), forKey: "_rawValue")
            try container.encode(uid, forKey: "uid")
        case let .url(_, url):
            try container.encode(Int32(5), forKey: "_rawValue")
            try container.encode(url, forKey: "url")
        case let .animated(_, id, fileId, file, info):
            try container.encode(Int32(9), forKey: "_rawValue")
            try container.encode(id, forKey: "id")
            try container.encode(fileId, forKey: "fileId")
            if let file = file {
                try container.encode(file, forKey: "file")
            }
            if let info = info {
                try container.encode(info, forKey: "info")
            }
        case let .quote(_, collapsed):
            try container.encode(Int32(10), forKey: "_rawValue")
            try container.encode(collapsed, forKey: "collapsed")
        case let .date(_, date):
            try container.encode(Int32(11), forKey: "_rawValue")
            try container.encode(date, forKey: "date")
        }
    }

}

public extension ChatTextInputAttribute {


    func isSameAttribute(_ rhs: ChatTextInputAttribute) -> Bool {
        switch self {
        case .bold:
            return self.weight == rhs.weight
        case .strikethrough:
            return self.weight == rhs.weight
        case .spoiler:
            return self.weight == rhs.weight
        case .underline:
            return self.weight == rhs.weight
        case .italic:
            return self.weight == rhs.weight
        case .pre:
            return self.weight == rhs.weight
        case .code:
            return self.weight == rhs.weight
        case .quote:
            return self.weight == rhs.weight
        case let .uid(_, id):
            switch rhs {
            case .uid(_, id):
                return true
            default:
                return false
            }
        case let .url(_, string):
            switch rhs {
            case .url(_, string):
                return true
            default:
                return false
            }
        case .animated:
            return false
        case .date:
            return self.weight == rhs.weight
        }
    }

    func intersectsOrAdjacent(with attribute: ChatTextInputAttribute) -> Bool {
        return self.range.upperBound >= attribute.range.lowerBound && self.range.lowerBound <= attribute.range.upperBound
    }

    // Merge two attributes into one with a combined range
    mutating func merge(with attribute: ChatTextInputAttribute) {
        let newStart = min(self.range.lowerBound, attribute.range.lowerBound)
        let newEnd = max(self.range.upperBound, attribute.range.upperBound)
        self = self.updateRange(newStart..<newEnd)
    }

    var range:Range<Int> {
        switch self {
        case let .bold(range), let .italic(range), let .pre(range, _), let .code(range), let .strikethrough(range), let .spoiler(range), let .underline(range):
            return range
        case let .uid(range, _):
            return range
        case let .url(range, _):
            return range
        case let .animated(range, _, _, _, _):
            return range
        case let .quote(range, _):
            return range
        case let .date(range, _):
            return range
        }
    }

    func updateRange(_ range: Range<Int>) -> ChatTextInputAttribute {
        switch self {
        case .bold:
            return .bold(range)
        case .italic:
            return .italic(range)
        case let .pre(_, language):
            return .pre(range, language)
        case .code:
            return .code(range)
        case .strikethrough:
            return .strikethrough(range)
        case .spoiler:
            return .spoiler(range)
        case .underline:
            return .underline(range)
        case let .uid(_, uid):
            return .uid(range, uid)
        case let .url(_, url):
            return .url(range, url)
        case let .animated(_, id, fileId, file, info):
            return .animated(range, id, fileId, file, info)
        case let .quote(_, collapsed):
            return .quote(range, collapsed)
        case let .date(_, date):
            return .date(range, date)
        }
    }
}


public func chatTextAttributes(from entities:TextEntitiesMessageAttribute, associatedMedia:[MediaId : Media] = [:]) -> [ChatTextInputAttribute] {
    var inputAttributes:[ChatTextInputAttribute] = []
    for entity in entities.entities {
        switch entity.type {
        case .Bold:
            inputAttributes.append(.bold(entity.range))
        case .Italic:
            inputAttributes.append(.italic(entity.range))
        case .Code:
            inputAttributes.append(.code(entity.range))
        case let .Pre(language):
            inputAttributes.append(.pre(entity.range, language))
        case let .TextMention(peerId: peerId):
            inputAttributes.append(.uid(entity.range, peerId.id._internalGetInt64Value()))
        case let .TextUrl(url):
            inputAttributes.append(.url(entity.range, url))
        case .Strikethrough:
            inputAttributes.append(.strikethrough(entity.range))
        case .Spoiler:
            inputAttributes.append(.spoiler(entity.range))
        case .Underline:
            inputAttributes.append(.underline(entity.range))
        case let .CustomEmoji(_, fileId):
            inputAttributes.append(.animated(entity.range, "\(arc4random())", fileId, nil, nil))
        case let .BlockQuote(collapsed):
            inputAttributes.append(.quote(entity.range, collapsed))
        case let .FormattedDate(_, date):
            inputAttributes.append(.date(entity.range, date))
        default:
            break
        }
    }
    return inputAttributes
}

public func chatTextAttributes(from attributedText: NSAttributedString) -> [ChatTextInputAttribute] {

    var parsedAttributes: [ChatTextInputAttribute] = []
    attributedText.enumerateAttributes(in: NSRange(location: 0, length: attributedText.length), options: [], using: { attributes, range, _ in
        for (key, value) in attributes {
            let range = range.location ..< (range.location + range.length)
            if key == TextInputAttributes.bold {
                parsedAttributes.append(.bold(range))
            } else if key == TextInputAttributes.italic {
                parsedAttributes.append(.italic(range))
            } else if key == TextInputAttributes.code {
                parsedAttributes.append(.pre(range, value as? String))
            } else if key == TextInputAttributes.monospace {
                parsedAttributes.append(.code(range))
            } else if key == TextInputAttributes.textMention, let value = value as? ChatTextInputTextMentionAttribute {
                parsedAttributes.append(.uid(range, value.peerId.id._internalGetInt64Value()))

            } else if key == TextInputAttributes.textUrl, let value = value as? TextInputTextUrlAttribute {
                parsedAttributes.append(.url(range, value.url))
            } else if key == TextInputAttributes.customEmoji, let value = value as? TextInputTextCustomEmojiAttribute {
                parsedAttributes.append(.animated(range, value.emoji, value.fileId, value.file, value.collectionId))
            } else if key == TextInputAttributes.embedded, let value = value as? EmbeddedCustomEmojiAttributeValue, let emoji = value.customEmojiAttribute {
                parsedAttributes.append(.animated(range, emoji.emoji, emoji.fileId, emoji.file, nil))
            } else if key == TextInputAttributes.strikethrough {
                parsedAttributes.append(.strikethrough(range))
            } else if key == TextInputAttributes.underline {
                parsedAttributes.append(.underline(range))
            } else if key == TextInputAttributes.spoiler {
                parsedAttributes.append(.spoiler(range))
            } else if key == TextInputAttributes.formattedDate, let value = value as? TextInputTextDateAttribute {
                parsedAttributes.append(.date(range, value.date))
            }
        }
    })
    attributedText.enumerateAttribute(TextInputAttributes.quote, in: NSRange(location: 0, length: attributedText.length), options: [], using: { value, range, _ in
        if let value = value as? TextInputTextQuoteAttribute {
            parsedAttributes.append(.quote(range.location ..< (range.location + range.length), value.collapsed))
        }
    })
    return parsedAttributes
}

public final class ChatTextInputState: Codable, Equatable {
    public static func == (lhs: ChatTextInputState, rhs: ChatTextInputState) -> Bool {
        return lhs.selectionRange == rhs.selectionRange && lhs.attributes == rhs.attributes && lhs.inputText == rhs.inputText
    }

    public let inputText: String


    public let attributes:[ChatTextInputAttribute]
    public let selectionRange: Range<Int>


    public init() {
        self.inputText = ""
        self.selectionRange = 0 ..< 0
        self.attributes = []
    }

    public init(inputText: String, selectionRange: Range<Int>, attributes:[ChatTextInputAttribute]) {
        self.inputText = inputText
        self.selectionRange = selectionRange
        self.attributes = attributes.sorted(by: <)
    }

    public init(attributedText: NSAttributedString, selectionRange: Range<Int>) {
        self.inputText = attributedText.string
        self.selectionRange = selectionRange
        self.attributes = chatTextAttributes(from: attributedText)
    }



    public var inlineMedia: [MediaId : Media] {
        var media:[MediaId : Media] = [:]
        for attribute in attributes {
            switch attribute {
            case .animated(_, _, let fileId, let file, _):
                if let file = file {
                    media[MediaId(namespace: Namespaces.Media.CloudFile, id: fileId)] = file
                }
            default:
                break
            }
        }
        return media
    }

    public var upstairCollections: [ItemCollectionId] {
        var media:[ItemCollectionId] = []
        for attribute in attributes {
            switch attribute {
            case let .animated(_, _, _, _, info):
                if let info = info {
                    if !media.contains(info) {
                        media.append(info)
                    }
                }
            default:
                break
            }
        }
        return media
    }

    public var withoutAnimatedEmoji: ChatTextInputState {
        let attrs = self.attributes.filter { attr in
            switch attr {
            case .animated:
                return false
            default:
                return true
            }
        }
        return .init(inputText: self.inputText, selectionRange: self.selectionRange, attributes: attrs)
    }


    public func removeAttribute(_ attribute: ChatTextInputAttribute) -> ChatTextInputState {
        var attrs = self.attributes
        attrs.removeAll(where: {
            $0 == attribute
        })
        return .init(inputText: self.inputText, selectionRange: self.selectionRange, attributes: attrs)
    }

    public func withUpdatedRange(_ range: Range<Int>) -> ChatTextInputState {
        return .init(inputText: self.inputText, selectionRange: range, attributes: attributes)
    }

    public func isFirstAnimatedEmoji(_ string: String) -> Bool {
        for attribute in attributes {
            switch attribute {
            case let .animated(range, _, _, _, _):
                if range == 0 ..< string.length {
                    return true
                }
            default:
                break
            }
        }
        return false
    }
    public func isAnimatedEmoji(at r: NSRange) -> Bool {
        for attribute in attributes {
            switch attribute {
            case let .animated(range, _, _, _, _):
                if range.lowerBound == r.lowerBound && range.upperBound == range.upperBound {
                    return true
                }
            default:
                break
            }
        }
        return false
    }

    public init(inputText: String) {
        self.inputText = inputText
        self.selectionRange = inputText.length ..< inputText.length
        self.attributes = []
    }

    public init(from decoder: Decoder) throws {

        let container = try decoder.container(keyedBy: StringCodingKey.self)

        self.inputText = try container.decode(String.self, forKey: "t")
        let lowerBound = try container.decode(Int32.self, forKey: "s0")
        let upperBound = try container.decode(Int32.self, forKey: "s1")

        self.selectionRange = Int(lowerBound) ..< Int(upperBound)
        self.attributes = try container.decode([ChatTextInputAttribute].self, forKey: "t.a").filter { !$0.range.isEmpty }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: StringCodingKey.self)
        try container.encode(self.inputText, forKey: "t")
        try container.encode(Int32(self.selectionRange.lowerBound), forKey: "s0")
        try container.encode(Int32(self.selectionRange.upperBound), forKey: "s1")
        try container.encode(self.attributes, forKey: "t.a")
    }

    public func unique(isPremium: Bool) -> ChatTextInputState {
        let attributes:[ChatTextInputAttribute] = self.attributes.compactMap { attr in
            switch attr {
            case let .animated(range, _, fileId, file, info):
                if !isPremium && file?.isPremiumEmoji == true {
                    return nil
                }
                return .animated(range, "\(arc4random64())", fileId, file, info)
            default:
                return attr
            }
        }
        return .init(inputText: self.inputText, selectionRange: self.selectionRange, attributes: attributes)
    }

    public func textInputState() -> Updated_ChatTextInputState {
        let result = NSMutableAttributedString(string: self.inputText)
        for attribute in self.attributes {
            let range = NSRange(location: attribute.range.lowerBound, length: attribute.range.count)
            switch attribute {
            case .bold:
                result.addAttribute(TextInputAttributes.bold, value: true as NSNumber, range: range)
            case .italic:
                result.addAttribute(TextInputAttributes.italic, value: true as NSNumber, range: range)
            case .code:
                result.addAttribute(TextInputAttributes.monospace, value: true as NSNumber, range: range)
            case .pre(_, _):
                break
            case let .uid(_, id):
                result.addAttribute(TextInputAttributes.textMention, value: ChatTextInputTextMentionAttribute(peerId: PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(id))), range: range)
            case let .url(_, url):
                result.addAttribute(TextInputAttributes.textUrl, value: TextInputTextUrlAttribute(url: url), range: range)
            case let .animated(_, emoji, fileId, file, collectionId):
                result.addAttribute(TextInputAttributes.customEmoji, value: TextInputTextCustomEmojiAttribute(collectionId: collectionId, fileId: fileId, file: file, emoji: emoji), range: range)
            case .strikethrough:
                result.addAttribute(TextInputAttributes.strikethrough, value: true as NSNumber, range: range)
            case .underline:
                result.addAttribute(TextInputAttributes.underline, value: true as NSNumber, range: range)
            case .spoiler:
                result.addAttribute(TextInputAttributes.spoiler, value: true as NSNumber, range: range)
            case let .quote(_, collapsed):
                result.addAttribute(TextInputAttributes.quote, value: TextInputTextQuoteAttribute(collapsed: collapsed), range: range)
            case let .date(_, date):
                result.addAttribute(TextInputAttributes.formattedDate, value: TextInputTextDateAttribute(date: date), range: range)
            }
        }
        return .init(inputText: result, selectionRange: self.selectionRange)

    }

    public func attributedString() -> NSAttributedString {
        return self.textInputState().inputText
    }

    public func makeAttributeString(addPreAsBlock: Bool = false) -> NSAttributedString {
        let string = self.textInputState().inputText.mutableCopy() as! NSMutableAttributedString
        var pres:[(Range<Int>, String)] = []

        for attribute in attributes {
            switch attribute {
            case let .pre(range, language):
                if addPreAsBlock {
                    pres.append((range, language ?? ""))
                }
            default:
                break
            }
        }
        if addPreAsBlock {
            var offset: Int = 0
            for (pre, language) in pres.sorted(by: { $0.0.lowerBound < $1.0.lowerBound }) {
                let symbols = "```"

                string.insert(.initialize(string: symbols), at: pre.lowerBound + offset)
                offset += symbols.count

                if !language.isEmpty {
                    if string.string.nsstring.substring(with: NSMakeRange(pre.lowerBound + offset, 1)) == "\n" {
                        string.insert(.initialize(string: language), at: pre.lowerBound + offset)
                        offset += language.length
                    } else {
                        string.insert(.initialize(string: language + "\n"), at: pre.lowerBound + offset)
                        offset += language.length + 1
                    }
                }
                string.insert(.initialize(string: symbols), at: pre.upperBound + offset)
                offset += symbols.count
            }
        }

        return string.copy() as! NSAttributedString
    }


    public func subInputState(from range: NSRange) -> ChatTextInputState {
//        let subText = convertMarkdownToAttributes(attributedString().attributedSubstring(from: range)).trimmed
//        let attributes = chatTextAttributes(from: subText)



        let subText = attributedString().attributedSubstring(from: range).trimmed

        let localAttributes = chatTextAttributes(from: subText)


        var raw:String = subText.string
        var appliedText = subText.string
        var attributes:[ChatTextInputAttribute] = []

        var offsetRanges:[NSRange] = []
        if let regex = markdownRegex {

            var skipIndexes:Set<Int> = Set()
            if !localAttributes.isEmpty {
                var index: Int = 0
                let matches = regex.matches(in: subText.string, range: NSMakeRange(0, subText.string.length))
                for match in matches {
                    for attr in localAttributes {
                        let range = match.range
                        let attrRange = NSMakeRange(attr.range.lowerBound, attr.range.upperBound - attr.range.lowerBound)
                        if attrRange.intersection(range) != nil {
                            skipIndexes.insert(index)
                        }
                    }
                    index += 1
                }
            }


            var rawOffset:Int = 0
            var newText:[String] = []
            var index: Int = 0
            while let match = regex.firstMatch(in: raw, range: NSMakeRange(0, raw.length)) {



                let matchIndex = rawOffset + match.range.location



                newText.append(raw.nsstring.substring(with: NSMakeRange(0, match.range.location)))

                var pre = match.range(at: 3)


                if pre.location != NSNotFound {
                    if !skipIndexes.contains(index) {
                        var text = raw.nsstring.substring(with: pre)

                        var language: String = ""
                        let newLineRange = text.nsstring.range(of: "\n")
                        if newLineRange.location != 0 && newLineRange.location != NSNotFound {
                            let lang = text.nsstring.substring(with: NSMakeRange(0, newLineRange.location))
                            let test = lang.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                            if test.length == lang.length {
                                language = lang
                                offsetRanges.append(NSMakeRange(matchIndex + newLineRange.location, lang.length))
                                text = String(text.nsstring.substring(with: NSMakeRange(newLineRange.location, text.length - newLineRange.location)))
                                rawOffset -= newLineRange.location
                            }
                        }

                        rawOffset -= match.range(at: 2).length + match.range(at: 4).length
                        newText.append(raw.nsstring.substring(with: match.range(at: 1)) + text + raw.nsstring.substring(with: match.range(at: 5)))
                        attributes.append(.pre(matchIndex + match.range(at: 1).length ..< matchIndex + match.range(at: 1).length + text.length, language))
                        offsetRanges.append(NSMakeRange(matchIndex + match.range(at: 1).length, 3))
                        offsetRanges.append(NSMakeRange(matchIndex + match.range(at: 1).length + text.length + 3, 3))
                    } else {
                        let text = raw.nsstring.substring(with: pre)
                        let entity = raw.nsstring.substring(with: match.range(at: 2))
                        newText.append(raw.nsstring.substring(with: match.range(at: 1)) + entity + text + entity + raw.nsstring.substring(with: match.range(at: 5)))
                    }
                }

                pre = match.range(at: 8)
                if pre.location != NSNotFound {
                    let text = raw.nsstring.substring(with: pre)
                    if !skipIndexes.contains(index) {

                        let left = match.range(at: 6)

                        let entity = raw.nsstring.substring(with: match.range(at: 7))
                        newText.append(raw.nsstring.substring(with: left) + text + raw.nsstring.substring(with: match.range(at: 9)))


                        switch entity {
                        case "`":
                            attributes.append(.code(matchIndex + left.length ..< matchIndex + left.length + text.length))
                        case "**":
                            attributes.append(.bold(matchIndex + left.length ..< matchIndex + left.length + text.length))
                        case "~~":
                            attributes.append(.strikethrough(matchIndex + left.length ..< matchIndex + left.length + text.length))
                        case "__":
                            attributes.append(.italic(matchIndex + left.length ..< matchIndex + left.length + text.length))
                        case "||":
                            attributes.append(.spoiler(matchIndex + left.length ..< matchIndex + left.length + text.length))
                        default:
                            break
                        }

                        offsetRanges.append(NSMakeRange(matchIndex + left.length, entity.length))
                        offsetRanges.append(NSMakeRange(matchIndex + left.length + text.length, entity.length))

                        rawOffset -= match.range(at: 7).length * 2
                    } else {
                        let entity = raw.nsstring.substring(with: match.range(at: 7))
                        newText.append(raw.nsstring.substring(with: match.range(at: 6)) + entity + text + entity + raw.nsstring.substring(with: match.range(at: 9)))
                    }
                }
                raw = raw.nsstring.substring(from: match.range.location + match.range(at: 0).length)
                rawOffset += match.range.location + match.range(at: 0).length

                index += 1
            }

            newText.append(raw)
            appliedText = newText.joined()
        }

        for attr in localAttributes {
            var newRange = NSMakeRange(attr.range.lowerBound, (attr.range.upperBound - attr.range.lowerBound))
            for offsetRange in offsetRanges {
                if offsetRange.location < newRange.location {
                    newRange.location -= offsetRange.length
                }
//                if newRange.intersection(offsetRange) != nil {
//                    newRange.length -= offsetRange.length
//                }
            }


            //if newRange.lowerBound >= range.location && newRange.upperBound <= range.location + range.length {
                switch attr {
                case .bold:
                    attributes.append(.bold(newRange.min ..< newRange.max))
                case .italic:
                    attributes.append(.italic(newRange.min ..< newRange.max))
                case let .pre(_, language):
                    attributes.append(.pre(newRange.min ..< newRange.max, language))
                case .code:
                    attributes.append(.code(newRange.min ..< newRange.max))
                case .strikethrough:
                    attributes.append(.strikethrough(newRange.min ..< newRange.max))
                case .underline:
                    attributes.append(.underline(newRange.min ..< newRange.max))
                case .spoiler:
                    attributes.append(.spoiler(newRange.min ..< newRange.max))
                case let .uid(_, uid):
                    attributes.append(.uid(newRange.min ..< newRange.max, uid))
                case let .url(_, url):
                    attributes.append(.url(newRange.min ..< newRange.max, url))
                case let .quote(_, collapsed):
                    attributes.append(.quote(newRange.min ..< newRange.max, collapsed))
                case let .animated(_, id, fileId, file, itemId):
                    attributes.append(.animated(newRange.min ..< newRange.max, id, fileId, file, itemId))
                case let .date(_, date):
                    attributes.append(.date(newRange.min ..< newRange.max, date))
                }
          //  }
        }

        let charset = CharacterSet.whitespacesAndNewlines

        while !appliedText.isEmpty, let range = appliedText.rangeOfCharacter(from: charset), range.lowerBound == appliedText.startIndex {

            let oldLength = appliedText.length
            appliedText.removeSubrange(range)
            let newLength = appliedText.length

            let symbolLength = oldLength - newLength

            for (i, attr) in attributes.enumerated() {
                let updated: ChatTextInputAttribute
                if attr.range.lowerBound == 0 {
                    updated = attr.updateRange(0 ..< max(attr.range.upperBound - symbolLength, 0))
                } else {
                    updated = attr.updateRange(attr.range.lowerBound - symbolLength ..< max(attr.range.upperBound - symbolLength, attr.range.lowerBound - symbolLength))
                }
                attributes[i] = updated
            }
        }



        while !appliedText.isEmpty, let range = appliedText.rangeOfCharacter(from: charset, options: [], range: appliedText.index(before: appliedText.endIndex) ..< appliedText.endIndex), range.upperBound == appliedText.endIndex {

            let oldLength = appliedText.length
            appliedText.removeSubrange(range)
            let newLength = appliedText.length

            let symbolLength = oldLength - newLength

            for (i, attr) in attributes.enumerated() {
                if attr.range.upperBound == oldLength {
                    let updated: ChatTextInputAttribute
                    updated = attr.updateRange(attr.range.lowerBound ..< max(attr.range.upperBound - symbolLength, attr.range.lowerBound))
                    attributes[i] = updated
                }
            }
        }

        attributes = concatAttributes(attributes).sorted(by: { $0.range.lowerBound < $1.range.lowerBound })

        return ChatTextInputState(inputText: appliedText, selectionRange: 0 ..< 0, attributes: attributes)

    }


    public func messageTextEntities(_ detectLinks: ParsingType = [.Hashtags], extractDates extractDate: Bool = false) -> [MessageTextEntity] {
        var entities:[MessageTextEntity] = []
        for attribute in attributes {
            sw: switch attribute {
            case let .bold(range):
                entities.append(.init(range: range, type: .Bold))
            case let .strikethrough(range):
                entities.append(.init(range: range, type: .Strikethrough))
            case let .spoiler(range):
                entities.append(.init(range: range, type: .Spoiler))
            case let .underline(range):
                entities.append(.init(range: range, type: .Underline))
            case let .italic(range):
                entities.append(.init(range: range, type: .Italic))
            case let .pre(range, language):
                entities.append(.init(range: range, type: .Pre(language: language)))
            case let .code(range):
                entities.append(.init(range: range, type: .Code))
            case let .uid(range, uid):
                entities.append(.init(range: range, type: .TextMention(peerId: PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(uid)))))
            case let .url(range, url):
                entities.append(.init(range: range, type: .TextUrl(url: url)))
            case let .animated(range, _, fileId, _, _):
                entities.append(.init(range: range, type: .CustomEmoji(stickerPack: nil, fileId: fileId)))
            case let .quote(range, collapsed):
                entities.append(.init(range: range, type: .BlockQuote(isCollapsed: collapsed)))
            case let .date(range, date):
                entities.append(.init(range: range, type: .FormattedDate(format: .full(timeFormat: .short, dateFormat: .short, dayOfWeek: false), date: date)))
            }
        }

        for link in detectedTextLinks(in: inputText, type: detectLinks).sorted(by: { $0.range.location < $1.range.location }) {
            if link.text.hasPrefix("#") {
                entities.append(MessageTextEntity(range: link.range.lowerBound ..< link.range.upperBound, type: .Hashtag))
            } else if detectLinks.contains(.Links) {
                entities.append(MessageTextEntity(range: link.range.lowerBound ..< link.range.upperBound, type: .Url))
            }
        }

        let dateDetectionKey = "AutomaticDateDetectionEnabled1TGGrowingTextView"
        let dateDetectionEnabled = UserDefaults.standard.bool(forKey: dateDetectionKey)
        if extractDate && dateDetectionEnabled {
            let extractedDates = extractDates(from: inputText)
            for extracted in extractedDates {
                let overlaps = entities.contains { entity in
                    switch entity.type {
                    case .Bold, .Italic, .Strikethrough, .Underline, .Spoiler, .FormattedDate:
                        return false
                    default:
                        return entity.range.overlaps(extracted.range)
                    }
                }
                if !overlaps, let timestamp = Int32(exactly: extracted.date.timeIntervalSince1970.rounded(.towardZero)) {
                    let dateFormat: MessageTextEntityType.DateTimeFormat
                    switch extracted.format {
                    case .relative:
                        dateFormat = .relative
                    case let .full(hasTime, hasDate):
                        let timeFormat: MessageTextEntityType.DateTimeFormat.TimeFormat? = hasTime ? .short : nil
                        let dateFmt: MessageTextEntityType.DateTimeFormat.DateFormat? = hasDate ? .short : nil
                        dateFormat = .full(timeFormat: timeFormat, dateFormat: dateFmt, dayOfWeek: false)
                    }
                    entities.append(MessageTextEntity(range: extracted.range, type: .FormattedDate(format: dateFormat, date: timestamp)))
                }
            }
        }

        return entities
    }


}



extension Updated_ChatTextInputState : Equatable {
    public func textInputState() -> ChatTextInputState {
        return .init(attributedText: self.inputText, selectionRange: self.selectionRange)
    }
    public static func ==(lhs: Updated_ChatTextInputState, rhs: Updated_ChatTextInputState) -> Bool {
        if lhs.inputText.string != rhs.inputText.string {
            return false
        }
        if lhs.textInputState().attributes != rhs.textInputState().attributes {
            return false
        }
        return lhs.selectionRange == rhs.selectionRange
    }
}
