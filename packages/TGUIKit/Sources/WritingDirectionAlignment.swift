import AppKit

public extension NSTextStorage {
    func alignParagraphsByWritingDirection(around editedRange: NSRange) {
        let string = self.string as NSString
        guard string.length > 0 else {
            return
        }
        let clampedLocation = min(editedRange.location, string.length)
        let clampedLength = min(editedRange.length, string.length - clampedLocation)
        let paragraphsRange = string.paragraphRange(for: NSMakeRange(clampedLocation, clampedLength))

        string.enumerateSubstrings(in: paragraphsRange, options: [.byParagraphs, .substringNotRequired]) { _, substringRange, enclosingRange, _ in
            guard enclosingRange.length > 0 else {
                return
            }
            let currentStyle = self.attribute(.paragraphStyle, at: enclosingRange.location, effectiveRange: nil) as? NSParagraphStyle ?? NSParagraphStyle.default
            let isRightToLeft: Bool
            switch currentStyle.baseWritingDirection {
            case .rightToLeft:
                isRightToLeft = true
            case .leftToRight:
                isRightToLeft = false
            default:
                isRightToLeft = WritingDirectionDetection.resolvedBaseDirectionIsRightToLeft(string.substring(with: substringRange))
            }
            let targetAlignment: NSTextAlignment = isRightToLeft ? .right : .natural

            self.enumerateAttribute(.paragraphStyle, in: enclosingRange, options: []) { value, range, _ in
                let style = value as? NSParagraphStyle ?? NSParagraphStyle.default
                if style.alignment == targetAlignment {
                    return
                }
                let updated = (style.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                updated.alignment = targetAlignment
                self.addAttribute(.paragraphStyle, value: updated, range: range)
            }
        }
    }
}

public final class WritingDirectionAlignmentDelegate: NSObject, NSTextStorageDelegate {
    public func textStorage(_ textStorage: NSTextStorage, didProcessEditing editedMask: NSTextStorageEditActions, range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) || editedMask.contains(.editedAttributes) else {
            return
        }
        textStorage.alignParagraphsByWritingDirection(around: editedRange)
    }
}

enum WritingDirectionDetection {
    private static let isolateInitiators = CharacterSet(charactersIn: "\u{2066}\u{2067}\u{2068}")
    private static let strongRightToLeftCharacter = "\u{05D0}"
    private static let initialPrefixLength = 64

    static func resolvedBaseDirectionIsRightToLeft(_ paragraph: String) -> Bool {
        let text = paragraph as NSString
        guard text.length > 0 else {
            return false
        }
        if text.rangeOfCharacter(from: isolateInitiators).location == NSNotFound {
            var prefixLength = initialPrefixLength
            while prefixLength < text.length {
                let prefix = text.substring(with: text.rangeOfComposedCharacterSequences(for: NSMakeRange(0, prefixLength)))
                if trailingSpaceIsRightToLeft(prefix) {
                    return true
                }
                if !trailingSpaceIsRightToLeft(prefix + strongRightToLeftCharacter) {
                    return false
                }
                prefixLength *= 2
            }
        }
        return trailingSpaceIsRightToLeft(paragraph)
    }

    private static func trailingSpaceIsRightToLeft(_ text: String) -> Bool {
        let probe = text + " "
        let trailingSpaceIndex = (probe as NSString).length - 1
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: probe))
        guard let runs = CTLineGetGlyphRuns(line) as? [CTRun] else {
            return false
        }
        for run in runs {
            let range = CTRunGetStringRange(run)
            if trailingSpaceIndex >= range.location && trailingSpaceIndex < range.location + range.length {
                return CTRunGetStatus(run).contains(.rightToLeft)
            }
        }
        return false
    }
}
