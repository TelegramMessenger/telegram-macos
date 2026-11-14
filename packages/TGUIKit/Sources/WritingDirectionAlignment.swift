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
            let isRightToLeft = self.paragraphIsRightToLeft(contentsRange: substringRange, styleLocation: enclosingRange.location)
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

extension NSTextStorage {
    func paragraphIsRightToLeft(contentsRange: NSRange, styleLocation: Int) -> Bool {
        let style = attribute(.paragraphStyle, at: styleLocation, effectiveRange: nil) as? NSParagraphStyle ?? NSParagraphStyle.default
        switch style.baseWritingDirection {
        case .rightToLeft:
            return true
        case .leftToRight:
            return false
        default:
            return WritingDirectionDetection.resolvedBaseDirectionIsRightToLeft((string as NSString).substring(with: contentsRange))
        }
    }

    func paragraphIsRightToLeft(containing index: Int) -> Bool? {
        let string = self.string as NSString
        guard index >= 0, index <= string.length else {
            return nil
        }
        var start = 0
        var end = 0
        var contentsEnd = 0
        string.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSMakeRange(index, 0))
        guard end > start else {
            return nil
        }
        return paragraphIsRightToLeft(contentsRange: NSMakeRange(start, contentsEnd - start), styleLocation: start)
    }
}

public final class WritingDirectionSelection {
    private var dataSource: AnyObject?

    public init() {
    }

    public func attach(to textView: NSTextView) {
        #if compiler(>=6.4)
        if #available(macOS 27.0, *) {
            guard let manager = textView.textSelectionManager, let base = manager.textSelectionDataSource, !(base is WritingDirectionResolvingSelectionDataSource), let textStorage = textView.textStorage else {
                return
            }
            let resolving = WritingDirectionResolvingSelectionDataSource(base: base, textStorage: textStorage)
            dataSource = resolving
            manager.textSelectionDataSource = resolving
        }
        #endif
    }
}

@available(macOS 12.0, *)
final class WritingDirectionResolvingSelectionDataSource: NSObject, NSTextSelectionDataSource {
    private let base: NSTextSelectionDataSource
    private weak var textStorage: NSTextStorage?

    init(base: NSTextSelectionDataSource, textStorage: NSTextStorage) {
        self.base = base
        self.textStorage = textStorage
    }

    var documentRange: NSTextRange {
        return base.documentRange
    }

    func baseWritingDirection(at location: NSTextLocation) -> NSTextSelectionNavigation.WritingDirection {
        let index = base.offset(from: base.documentRange.location, to: location)
        guard let isRightToLeft = textStorage?.paragraphIsRightToLeft(containing: index) else {
            return base.baseWritingDirection(at: location)
        }
        return isRightToLeft ? .rightToLeft : .leftToRight
    }

    func enumerateSubstrings(from location: NSTextLocation, options: NSString.EnumerationOptions = [], using block: (String?, NSTextRange, NSTextRange?, UnsafeMutablePointer<ObjCBool>) -> Void) {
        base.enumerateSubstrings(from: location, options: options, using: block)
    }

    func textRange(for selectionGranularity: NSTextSelection.Granularity, enclosing location: NSTextLocation) -> NSTextRange? {
        return base.textRange(for: selectionGranularity, enclosing: location)
    }

    func location(_ location: NSTextLocation, offsetBy offset: Int) -> NSTextLocation? {
        return base.location(location, offsetBy: offset)
    }

    func offset(from: NSTextLocation, to: NSTextLocation) -> Int {
        return base.offset(from: from, to: to)
    }

    func enumerateCaretOffsetsInLineFragment(at location: NSTextLocation, using block: (CGFloat, NSTextLocation, Bool, UnsafeMutablePointer<ObjCBool>) -> Void) {
        base.enumerateCaretOffsetsInLineFragment(at: location, using: block)
    }

    func lineFragmentRange(for point: CGPoint, inContainerAt location: NSTextLocation) -> NSTextRange? {
        return base.lineFragmentRange(for: point, inContainerAt: location)
    }

    func enumerateContainerBoundaries(from location: NSTextLocation, reverse: Bool, using block: (NSTextLocation, UnsafeMutablePointer<ObjCBool>) -> Void) {
        base.enumerateContainerBoundaries?(from: location, reverse: reverse, using: block)
    }

    func textLayoutOrientation(at location: NSTextLocation) -> NSTextSelectionNavigation.LayoutOrientation {
        return base.textLayoutOrientation?(at: location) ?? .horizontal
    }

    override func responds(to selector: Selector!) -> Bool {
        if selector == #selector(NSTextSelectionDataSource.enumerateContainerBoundaries(from:reverse:using:)) || selector == #selector(NSTextSelectionDataSource.textLayoutOrientation(at:)) {
            return base.responds(to: selector)
        }
        return super.responds(to: selector)
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
