import Foundation
import InputView
import TGUIKit

func chatQuoteTextRange(in layoutString: NSAttributedString, text: String, offset: Int?) -> NSRange? {
    guard !text.isEmpty else { return nil }
    var replacements: [(layout: NSRange, original: NSRange)] = []
    let originalString = NSMutableString()
    let layoutText = layoutString.string as NSString
    layoutString.enumerateAttribute(TextInputAttributes.embedded, in: NSRange(location: 0, length: layoutString.length)) { value, range, _ in
        if let emoji = (value as? EmbeddedCustomEmojiAttributeValue)?.customEmojiAttribute?.emoji, !emoji.isEmpty {
            replacements.append((range, NSRange(location: originalString.length, length: (emoji as NSString).length)))
            originalString.append(emoji)
        } else {
            originalString.append(layoutText.substring(with: range))
        }
    }
    var match: NSRange?
    if let offset, offset >= 0, offset <= originalString.length {
        let candidate = originalString.range(of: text, range: NSRange(location: offset, length: originalString.length - offset))
        if candidate.location == offset {
            match = candidate
        }
    }
    if match == nil {
        var searchLocation = 0
        while searchLocation < originalString.length {
            let range = originalString.range(of: text, range: NSRange(location: searchLocation, length: originalString.length - searchLocation))
            guard range.location != NSNotFound else { break }
            if let offset, let current = match {
                if abs(range.location - offset) > abs(current.location - offset) { break }
            }
            match = range
            guard offset != nil else { break }
            searchLocation = range.location + 1
        }
    }
    guard let match else { return nil }

    func layoutPosition(_ originalPosition: Int, upperBound: Bool) -> Int {
        var delta = 0
        for replacement in replacements {
            if originalPosition >= NSMaxRange(replacement.original) {
                delta += replacement.layout.length - replacement.original.length
            } else if originalPosition > replacement.original.location {
                return upperBound ? NSMaxRange(replacement.layout) : replacement.layout.location
            } else {
                break
            }
        }
        return originalPosition + delta
    }

    let lowerBound = layoutPosition(match.location, upperBound: false)
    let upperBound = layoutPosition(NSMaxRange(match), upperBound: true)
    return NSRange(location: lowerBound, length: max(0, upperBound - lowerBound))
}
