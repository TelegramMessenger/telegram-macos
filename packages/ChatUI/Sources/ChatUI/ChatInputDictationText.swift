import Foundation

struct ChatInputDictationDraft {
    let prefix: NSAttributedString
    let suffix: NSAttributedString
    let attributes: [NSAttributedString.Key: Any]

    init(text: NSAttributedString, selection: Range<Int>, excludingAttribute: (NSAttributedString.Key, Any) -> Bool = { _, _ in false }) {
        let length = text.length
        let lower = max(0, min(selection.lowerBound, length))
        let upper = max(lower, min(selection.upperBound, length))
        self.prefix = text.attributedSubstring(from: NSMakeRange(0, lower))
        self.suffix = text.attributedSubstring(from: NSMakeRange(upper, length - upper))
        if lower > 0 {
            self.attributes = text.attributes(at: lower - 1, effectiveRange: nil).filter { !excludingAttribute($0.key, $0.value) }
        } else {
            self.attributes = [:]
        }
    }

    func compose(_ transcript: String) -> (text: NSAttributedString, cursor: Int) {
        let insertion = ChatInputDictationText.insertion(prefix: prefix.string, transcript: transcript, suffix: suffix.string)
        let result = NSMutableAttributedString(attributedString: prefix)
        result.append(NSAttributedString(string: insertion, attributes: attributes))
        let cursor = result.length
        result.append(suffix)
        return (result, cursor)
    }
}

struct ChatInputDictationInsertion {
    private let text: NSAttributedString
    private let selection: Range<Int>
    private let draft: ChatInputDictationDraft
    private let consumedTranscript: String

    init(text: NSAttributedString, selection: Range<Int>, consumedTranscript: String = "", excludingAttribute: (NSAttributedString.Key, Any) -> Bool = { _, _ in false }) {
        self.text = text
        let lower = max(0, min(selection.lowerBound, text.length))
        let upper = max(lower, min(selection.upperBound, text.length))
        self.selection = lower ..< upper
        self.draft = ChatInputDictationDraft(text: text, selection: self.selection, excludingAttribute: excludingAttribute)
        self.consumedTranscript = consumedTranscript
    }

    func compose(_ transcript: String) -> (text: NSAttributedString, selection: Range<Int>) {
        let remainder = ChatInputDictationText.remainder(transcript, after: consumedTranscript)
        guard !remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (text, selection)
        }
        let result = draft.compose(remainder)
        return (result.text, result.cursor ..< result.cursor)
    }

    var start: Int {
        return draft.prefix.length
    }

    func insertedRange(_ transcript: String) -> NSRange {
        let remainder = ChatInputDictationText.remainder(transcript, after: consumedTranscript)
        guard !remainder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return NSRange(location: start, length: 0)
        }
        let result = draft.compose(remainder)
        return NSRange(location: start, length: max(0, result.text.length - start - draft.suffix.length))
    }
}

struct ChatDictationHeightHold {
    private(set) var floor: CGFloat = 0

    mutating func fit(_ height: CGFloat, transcribing: Bool) -> CGFloat {
        guard transcribing else {
            return height
        }
        floor = max(floor, height)
        return floor
    }

    mutating func release() {
        floor = 0
    }
}

enum ChatInputDictationText {
    static func changedCharacters(from old: String, to new: String, limit: Int = 640_000) -> [NSRange] {
        let before = Array(old)
        let after = Array(new)
        var prefix = 0
        while prefix < before.count, prefix < after.count, before[prefix] == after[prefix] {
            prefix += 1
        }
        var suffix = 0
        while suffix < before.count - prefix, suffix < after.count - prefix, before[before.count - 1 - suffix] == after[after.count - 1 - suffix] {
            suffix += 1
        }
        let removed = Array(before[prefix ..< before.count - suffix])
        let added = Array(after[prefix ..< after.count - suffix])
        var changed = [Bool](repeating: true, count: added.count)
        if !removed.isEmpty, !added.isEmpty, removed.count * added.count <= limit {
            let width = added.count + 1
            var table = [UInt16](repeating: 0, count: (removed.count + 1) * width)
            for i in stride(from: removed.count - 1, through: 0, by: -1) {
                for j in stride(from: added.count - 1, through: 0, by: -1) {
                    table[i * width + j] = removed[i] == added[j] ? table[(i + 1) * width + j + 1] &+ 1 : max(table[(i + 1) * width + j], table[i * width + j + 1])
                }
            }
            var i = 0
            var j = 0
            while i < removed.count, j < added.count {
                if removed[i] == added[j] {
                    changed[j] = false
                    i += 1
                    j += 1
                } else if table[(i + 1) * width + j] >= table[i * width + j + 1] {
                    i += 1
                } else {
                    j += 1
                }
            }
        }
        var ranges: [NSRange] = []
        var offset = String(after[0 ..< prefix]).utf16.count
        for (index, character) in added.enumerated() {
            let length = String(character).utf16.count
            if changed[index] {
                if let last = ranges.last, NSMaxRange(last) == offset {
                    ranges[ranges.count - 1].length += length
                } else {
                    ranges.append(NSRange(location: offset, length: length))
                }
            }
            offset += length
        }
        return ranges
    }

    static func enhanceableText(_ segment: String) -> String? {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).count
        guard words >= 2, trimmed.utf16.count <= 4096 else {
            return nil
        }
        return trimmed
    }

    static func replacingSegment(_ text: NSAttributedString, range: NSRange, with improved: String) -> (text: NSAttributedString, range: NSRange)? {
        guard range.location >= 0, range.length > 0, NSMaxRange(range) <= text.length else {
            return nil
        }
        let segment = (text.string as NSString).substring(with: range)
        let core = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        let replacement = improved.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !core.isEmpty, !replacement.isEmpty, replacement != core else {
            return nil
        }
        let leading = String(segment.prefix(while: { $0.isWhitespace })).utf16.count
        let trailing = String(segment.reversed().prefix(while: { $0.isWhitespace })).utf16.count
        let coreRange = NSRange(location: range.location + leading, length: range.length - leading - trailing)
        let attributes = text.attributes(at: coreRange.location, effectiveRange: nil)
        let result = NSMutableAttributedString(attributedString: text)
        result.replaceCharacters(in: coreRange, with: NSAttributedString(string: replacement, attributes: attributes))
        return (result, NSRange(location: range.location, length: leading + replacement.utf16.count + trailing))
    }

    static func selection(_ selection: Range<Int>, afterReplacing range: NSRange, length: Int) -> Range<Int> {
        let delta = length - range.length
        if selection.lowerBound >= NSMaxRange(range) {
            return (selection.lowerBound + delta) ..< (selection.upperBound + delta)
        }
        if selection.upperBound <= range.location {
            return selection
        }
        let caret = range.location + length
        return caret ..< caret
    }

    static func sessionRange(_ inserted: NSRange, from sessionStart: Int?) -> NSRange {
        guard let sessionStart, sessionStart <= inserted.location else {
            return inserted
        }
        return NSRange(location: sessionStart, length: NSMaxRange(inserted) - sessionStart)
    }

    private static let opening: Set<Character> = ["(", "[", "{", "«", "“", "‘", "\"", "'", "@", "#", "/"]
    private static let closing: Set<Character> = [".", ",", "!", "?", ";", ":", ")", "]", "}", "»", "”", "’", "…"]
    private static let primaryRegion: [String: String] = [
        "en": "us", "es": "es", "pt": "br", "zh": "cn", "ar": "sa", "uk": "ua", "ja": "jp", "ko": "kr",
        "sv": "se", "da": "dk", "he": "il", "el": "gr", "cs": "cz", "hi": "in", "vi": "vn", "ms": "my",
        "ca": "es", "nb": "no", "yue": "cn", "wuu": "cn", "fa": "ir", "kk": "kz", "et": "ee"
    ]
    private static let languageAliases: [String: String] = ["no": "nb", "tl": "fil", "iw": "he"]

    static func insertion(prefix: String, transcript: String, suffix: String) -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }
        var result = trimmed
        if let last = prefix.last, !last.isWhitespace, !opening.contains(last), let first = trimmed.first, !closing.contains(first) {
            result = " " + result
        }
        if let first = suffix.first, !first.isWhitespace, !closing.contains(first) {
            result += " "
        }
        return result
    }

    static func remainder(_ transcript: String, after consumed: String) -> String {
        if transcript.hasPrefix(consumed) {
            return String(transcript.dropFirst(consumed.count))
        }
        let previous = consumed.split(whereSeparator: { $0.isWhitespace })
        let current = transcript.split(whereSeparator: { $0.isWhitespace })
        guard !previous.isEmpty, current.count >= previous.count else { return "" }
        let last = current[previous.count - 1]
        let boundary: String.Index
        if last.hasPrefix(previous[previous.count - 1]) {
            boundary = transcript.index(last.startIndex, offsetBy: previous[previous.count - 1].count)
        } else {
            boundary = last.endIndex
        }
        return String(transcript[boundary...])
    }

    static func join(_ head: String, _ tail: String) -> String {
        guard let last = head.last, let first = tail.first else {
            return head + tail
        }
        if last.isWhitespace || first.isWhitespace || closing.contains(first) || opening.contains(last) {
            return head + tail
        }
        return head + " " + tail
    }

    static func appending(_ transcript: NSAttributedString, selection: Range<Int>, to draft: NSAttributedString) -> (text: NSAttributedString, selection: Range<Int>) {
        let merged = join(draft.string, transcript.string)
        let offset = (merged as NSString).length - transcript.length
        let result = NSMutableAttributedString(attributedString: draft)
        if offset > result.length {
            result.append(NSAttributedString(string: " "))
        }
        result.append(transcript)
        let lower = max(0, min(selection.lowerBound, transcript.length))
        let upper = max(lower, min(selection.upperBound, transcript.length))
        return (result, (offset + lower) ..< (offset + upper))
    }

    static func resolveLocale(preferred: [String], supported: [String]) -> String? {
        let normalized = supported.map { (original: $0, key: normalize($0)) }
        for identifier in preferred {
            let key = normalize(identifier)
            if let match = normalized.first(where: { $0.key == key }) {
                return match.original
            }
            let parts = key.split(separator: "-").map(String.init)
            guard let language = parts.first, !language.isEmpty else {
                continue
            }
            let candidates = normalized.filter { $0.key == language || $0.key.hasPrefix(language + "-") }
            if candidates.isEmpty {
                continue
            }
            if parts.count > 1, let region = parts.last, let match = candidates.first(where: { $0.key.hasSuffix("-" + region) }) {
                return match.original
            }
            let primary = primaryRegion[language] ?? language
            if let match = candidates.first(where: { $0.key == language + "-" + primary }) {
                return match.original
            }
            return candidates.map(\.original).sorted().first
        }
        return nil
    }

    static func stablePrefix(previous: String, current: String) -> String {
        let old = Array(previous)
        let new = Array(current)
        var position = 0
        while position < min(old.count, new.count), old[position] == new[position] {
            position += 1
        }
        let splitsWord = position > 0 && !new[position - 1].isWhitespace && (position == new.count || !new[position].isWhitespace)
        if splitsWord {
            while position > 0, !new[position - 1].isWhitespace {
                position -= 1
            }
        }
        return String(new[0 ..< position])
    }

    static func resolveLanguage(_ codes: [String], preferred: [String], supported: [String]) -> String? {
        var candidates: [String] = []
        for code in codes {
            let key = normalize(code)
            for variant in [key] + (languageAliases[key].map { [$0] } ?? []) {
                if !variant.contains("-") {
                    let language = languageCode(of: variant)
                    candidates += preferred.filter { languageCode(of: $0) == language }
                }
                candidates.append(variant)
            }
        }
        return resolveLocale(preferred: candidates, supported: supported)
    }

    static func flag(for identifier: String) -> String? {
        let parts = normalize(identifier).split(separator: "-")
        guard parts.count > 1, let region = parts.dropFirst().last(where: { $0.count == 2 && $0.allSatisfy({ $0 >= "a" && $0 <= "z" }) }) else {
            return nil
        }
        var flag = ""
        for scalar in region.uppercased().unicodeScalars {
            guard let indicator = Unicode.Scalar(127397 + scalar.value) else {
                return nil
            }
            flag.unicodeScalars.append(indicator)
        }
        return flag
    }

    static func automaticLocales(preferred: [String], supported: [String], limit: Int) -> [String] {
        var result: [String] = []
        var languages: Set<String> = []
        for identifier in preferred {
            guard result.count < limit, let resolved = resolveLocale(preferred: [identifier], supported: supported) else {
                continue
            }
            if languages.insert(languageCode(of: resolved)).inserted {
                result.append(resolved)
            }
        }
        return result
    }

    static func preferences(chatLanguage: String?, system: [String]) -> [String] {
        guard let chatLanguage, !chatLanguage.isEmpty else {
            return system
        }
        let language = languageCode(of: chatLanguage)
        let regional = system.first(where: { languageCode(of: $0) == language }) ?? chatLanguage
        return [regional] + system
    }

    static func languageCode(of identifier: String) -> String {
        let key = normalize(identifier)
        let language = key.split(separator: "-").first.map(String.init) ?? key
        return language.uppercased()
    }

    static func languageGroup(of identifier: String) -> String {
        let parts = normalize(identifier).split(separator: "-").map(String.init)
        guard let language = parts.first else {
            return ""
        }
        guard language == "zh", parts.count > 1 else {
            return language
        }
        switch parts[1] {
        case "hk":
            return "yue"
        case "tw", "mo", "hant":
            return "zh-hant"
        default:
            return "zh-hans"
        }
    }

    static func score(stability: Double, confidence: Double?, priority: Int) -> Double {
        let bonus = priority == 0 ? 0.04 : 0
        if let confidence {
            return stability * 0.5 + confidence * 0.5 + bonus
        }
        return stability + bonus
    }

    private static func normalize(_ identifier: String) -> String {
        let base = identifier.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? identifier
        return base.replacingOccurrences(of: "_", with: "-").lowercased()
    }
}

struct ChatInputDictationStability {
    private var total: Double = 0
    private var samples: Int = 0

    var value: Double {
        return samples == 0 ? 0.5 : total / Double(samples)
    }

    mutating func update(previous: String, current: String) {
        let old = ChatInputDictationStability.words(previous)
        let new = ChatInputDictationStability.words(current)
        let compared = min(old.count - 1, new.count)
        guard compared > 0 else {
            return
        }
        var kept = 0
        while kept < compared, old[kept] == new[kept] {
            kept += 1
        }
        total += Double(kept) / Double(compared)
        samples += 1
    }

    private static func words(_ text: String) -> [String] {
        return text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
}
