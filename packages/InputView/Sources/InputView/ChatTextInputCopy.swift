import Cocoa
import TGUIKit

public func chatTextInputCopyText(_ text: NSAttributedString) -> NSAttributedString {
    let result = NSMutableAttributedString(attributedString: text)
    var quotes: [Int: TextInputTextQuoteAttribute] = [:]
    text.enumerateAttribute(TextInputAttributes.quote, in: NSRange(location: 0, length: text.length), options: []) { value, range, _ in
        guard let quote = value as? TextViewBlockQuoteData else { return }
        if quote.isCode {
            result.removeAttribute(TextInputAttributes.quote, range: range)
        } else {
            let inputQuote = quotes[quote.id] ?? TextInputTextQuoteAttribute(collapsed: quote.collapsable)
            quotes[quote.id] = inputQuote
            result.addAttribute(TextInputAttributes.quote, value: inputQuote, range: range)
        }
    }
    text.enumerateAttribute(TextInputAttributes.code, in: NSRange(location: 0, length: text.length), options: []) { value, range, _ in
        if value != nil {
            result.removeAttribute(TextInputAttributes.monospace, range: range)
        }
    }
    return result
}
