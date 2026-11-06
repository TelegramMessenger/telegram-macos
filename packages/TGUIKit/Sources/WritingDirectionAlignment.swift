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

        string.enumerateSubstrings(in: paragraphsRange, options: [.byParagraphs, .substringNotRequired]) { _, _, enclosingRange, _ in
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
                isRightToLeft = WritingDirectionDetection.firstStrongDirectionIsRightToLeft(string.substring(with: enclosingRange))
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
    static func firstStrongDirectionIsRightToLeft(_ text: String) -> Bool {
        for scalar in text.unicodeScalars {
            if isRightToLeftScalar(scalar) {
                return true
            }
            if CharacterSet.letters.contains(scalar) {
                return false
            }
        }
        return false
    }

    private static func isRightToLeftScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x0660...0x0669, 0x06F0...0x06F9:
            return false
        case 0x0590...0x08FF, 0xFB1D...0xFDFF, 0xFE70...0xFEFF, 0x10800...0x10FFF, 0x1E800...0x1EFFF:
            return true
        default:
            return false
        }
    }
}
