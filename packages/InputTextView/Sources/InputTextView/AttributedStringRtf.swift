import Cocoa
import TGUIKit
import InputView
import TelegramTheme
import RichTextEditorCore

public extension NSAttributedString {

    func applyRtf() -> (NSAttributedString, [NSTextAttachment]) {
        let string = self.mutableCopy() as! NSMutableAttributedString
        
        let modified: NSMutableAttributedString = string.trimNewLines.mutableCopy() as! NSMutableAttributedString
        
        var attachments:[NSTextAttachment] = []
        
        modified.enumerateAttributes(in: modified.range, options: [], using: { attr, range, _ in
            if let url = attr[.link] {
                var string: String?
                if let url = url as? NSURL, let link = url.absoluteString {
                    string = link
                } else if let link = url as? String {
                    string = link
                }
                if let string = string {
                    modified.addAttribute(TextInputAttributes.textUrl, value: TextInputTextUrlAttribute.init(url: string), range: range)
                }
            } else if let font = attr[.font] as? NSFont {
                let newFont: NSFont
                if font.fontDescriptor.symbolicTraits.contains(.bold) && font.fontDescriptor.symbolicTraits.contains(.italic) {
                    newFont = .boldItalic(theme.fontSize)
                } else if font.fontDescriptor.symbolicTraits.contains(.bold) {
                    newFont = .bold(theme.fontSize)
                } else if font.fontDescriptor.symbolicTraits.contains(.italic) {
                    newFont = .italic(theme.fontSize)
                } else if font.fontDescriptor.symbolicTraits.contains(NSFontDescriptor.SymbolicTraits.monoSpace) {
                    newFont = .menlo(theme.fontSize)
                } else {
                    newFont = .normal(theme.fontSize)
                }
                modified.addAttribute(.font, value: newFont, range: range)
            }
            for key in attr.keys {
                switch key {
                case .font, .link:
                    break
                case .attachment:
                    modified.removeAttribute(key, range: range)
                    attachments.append(attr[key] as! NSTextAttachment)
                default:
                    modified.removeAttribute(key, range: range)
                }
            }
        })

        // Strip pasted self-referential links (a copied web link whose label IS its own URL): they must
        // land as plain text so they send as a server-auto-detected `url` entity, not a pinned `textUrl`.
        // Enumerated as a post-pass over `textUrl` (maximal effective ranges), because the loop above
        // walks whole-dictionary runs and would hand the predicate a partial label.
        modified.enumerateAttribute(TextInputAttributes.textUrl, in: modified.range, using: { value, range, _ in
            guard let attribute = value as? TextInputTextUrlAttribute else { return }
            if linkIsSelfReferential(text: modified.string.nsstring.substring(with: range), url: attribute.url) {
                modified.removeAttribute(TextInputAttributes.textUrl, range: range)
                modified.removeAttribute(.link, range: range)
            }
        })

        return (modified, attachments) //.trimmed
    }
    
    func appendAttributedString(_ string: NSAttributedString, selectedRange: NSRange = NSMakeRange(0, 0)) -> (NSAttributedString, NSRange) {
        let inputText = self.mutableCopy() as! NSMutableAttributedString
        
        
        let range: NSRange = NSMakeRange(selectedRange.location + string.string.length, 0);
        if selectedRange.upperBound - selectedRange.lowerBound > 0 {
            inputText.replaceCharacters(in: NSMakeRange(selectedRange.lowerBound, selectedRange.upperBound - selectedRange.lowerBound), with: string)
        } else {
            inputText.insert(string, at: selectedRange.lowerBound)
        }
        return (inputText, range)
    }
}
