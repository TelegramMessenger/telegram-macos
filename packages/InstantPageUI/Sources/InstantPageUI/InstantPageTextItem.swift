import Cocoa
import Localization
import TelegramUtils
import TelegramMediaUtils
import TelegramTheme
import TGUIKit
import TelegramContext
import AudioPlayerCore
import TelegramCore
import SwiftSignalKit
import RangeSet

import Postbox
import InlineStickerLayer
import InputView



extension NSAttributedString.Key {
    public static let URL: NSAttributedString.Key = NSAttributedString.Key("TelegramURL")
}

public struct InstantPageUrlItem: Hashable {
    public let url: String
    public let webpageId: MediaId?
    public let tonAddress: String?
    
    public init(url: String, webpageId: MediaId?, tonAddress: String? = nil) {
        self.url = url
        self.webpageId = webpageId
        self.tonAddress = tonAddress
    }
    
    public static func ==(lhs: InstantPageUrlItem, rhs: InstantPageUrlItem) -> Bool {
        return lhs.url == rhs.url && lhs.webpageId == rhs.webpageId && lhs.tonAddress == rhs.tonAddress
    }
}

public struct InstantPageTextMarkedItem {
    public let frame: CGRect
    public let color: NSColor
    public init(frame: CGRect, color: NSColor) {
        self.frame = frame
        self.color = color
    }
}

public struct InstantPageTextStrikethroughItem {
    public let frame: CGRect
    public let color: NSColor
    public init(frame: CGRect, color: NSColor) {
        self.frame = frame
        self.color = color
    }
}

public struct InstantPageTextSpoilerItem {
    public let frame: CGRect
    public init(frame: CGRect) {
        self.frame = frame
    }
}

public struct InstantPageTextEmojiItem {
    public let frame: CGRect
    public let range: NSRange
    public let emoji: ChatTextCustomEmojiAttribute
    public let textColor: NSColor?
    public init(frame: CGRect, range: NSRange, emoji: ChatTextCustomEmojiAttribute, textColor: NSColor?) {
        self.frame = frame
        self.range = range
        self.emoji = emoji
        self.textColor = textColor
    }
}

private struct PendingInstantPageTextEmojiItem {
    public let xOffset: CGFloat
    public let range: NSRange
    public let emoji: ChatTextCustomEmojiAttribute
    public let size: CGFloat
    public let textColor: NSColor?
}

public struct InstantPageTextImageItem {
    public let frame: CGRect
    public let range: NSRange
    public let id: MediaId
    public init(frame: CGRect, range: NSRange, id: MediaId) {
        self.frame = frame
        self.range = range
        self.id = id
    }
}

public struct InstantPageTextFormulaItem {
    public let frame: CGRect
    public let range: NSRange
    public let attachment: InstantPageMathAttachment
    public init(frame: CGRect, range: NSRange, attachment: InstantPageMathAttachment) {
        self.frame = frame
        self.range = range
        self.attachment = attachment
    }
}

/// One inline `RichText.textButton` pill positioned on a line. Same shape as the formula item: the
/// pill's whole width lives in a `CTRunDelegate` on a single placeholder character, so its frame has
/// to be recovered from the run offset at line-break time.
public struct InstantPageTextButtonItem {
    public let frame: CGRect
    public let range: NSRange
    public let attachment: InstantPageInlineButtonAttachment
    public init(frame: CGRect, range: NSRange, attachment: InstantPageInlineButtonAttachment) {
        self.frame = frame
        self.range = range
        self.attachment = attachment
    }
}

public struct InstantPageTextAnchorItem {
    public let name: String
    public let empty: Bool
    public init(name: String, empty: Bool) {
        self.name = name
        self.empty = empty
    }
}

public final class InstantPageTextLine {
    public let line: CTLine
    public let range: NSRange
    public let frame: CGRect
    public let strikethroughItems: [InstantPageTextStrikethroughItem]
    public let markedItems: [InstantPageTextMarkedItem]
    public let imageItems: [InstantPageTextImageItem]
    public let formulaItems: [InstantPageTextFormulaItem]
    public let buttonItems: [InstantPageTextButtonItem]
    public let anchorItems: [InstantPageTextAnchorItem]
    public let spoilerItems: [InstantPageTextSpoilerItem]
    public let emojiItems: [InstantPageTextEmojiItem]
    public let isRTL: Bool
    public let attributedString: NSAttributedString

    public let separatesTiles: Bool = false

    public let characterRects: [CGRect]?

    public var selectRect: NSRect = NSZeroRect

    public init(line: CTLine, attributedString: NSAttributedString, range: NSRange, frame: CGRect, strikethroughItems: [InstantPageTextStrikethroughItem], markedItems: [InstantPageTextMarkedItem], imageItems: [InstantPageTextImageItem], formulaItems: [InstantPageTextFormulaItem] = [], buttonItems: [InstantPageTextButtonItem] = [], anchorItems: [InstantPageTextAnchorItem], spoilerItems: [InstantPageTextSpoilerItem] = [], emojiItems: [InstantPageTextEmojiItem] = [], isRTL: Bool, characterRects: [CGRect]? = nil) {
        self.line = line
        self.attributedString = attributedString
        self.range = range
        self.frame = frame
        self.strikethroughItems = strikethroughItems
        self.markedItems = markedItems
        self.imageItems = imageItems
        self.formulaItems = formulaItems
        self.buttonItems = buttonItems
        self.anchorItems = anchorItems
        self.spoilerItems = spoilerItems
        self.emojiItems = emojiItems
        self.isRTL = isRTL
        self.characterRects = characterRects

    }
    
    public func linkAt(point: NSPoint) -> InstantPageUrlItem? {
        if point.x >= 0 && point.x <= frame.width {
            let index: CFIndex = CTLineGetStringIndexForPosition(line, point)
            if index >= 0 && index < attributedString.length {
                return attributedString.attribute(.URL, at: index, effectiveRange: nil) as? InstantPageUrlItem
            }
        }
        
        return nil
    }

    /// True when every character in `range` belongs to an inline button pill. A pill is a control, not
    /// prose: selecting one would paint the highlight over the button and copy the placeholder
    /// character that stands in for it. Most visible on an emoji-only pill, which is a single
    /// character, so any drag across it selects the whole button.
    private func rangeIsOnlyButtons(_ range: NSRange) -> Bool {
        guard range.length > 0, NSMaxRange(range) <= attributedString.length else {
            return false
        }
        var onlyButtons = true
        attributedString.enumerateAttribute(.instantPageInlineButtonAttribute, in: range, options: []) { value, _, stop in
            if value == nil {
                onlyButtons = false
                stop.pointee = true
            }
        }
        return onlyButtons
    }

    public func selectText(in rect: NSRect, boundingWidth: CGFloat, alignment: NSTextAlignment) -> NSAttributedString {

        var rect = rect
        if isRTL {
            rect.origin.x -= (boundingWidth - frame.width)
        }
        
        let startIndex: CFIndex = CTLineGetStringIndexForPosition(line, NSMakePoint(rect.minX, 0))
        let endIndex: CFIndex = CTLineGetStringIndexForPosition(line, NSMakePoint(rect.maxX, 0))
        
        
    
        var startOffset = CTLineGetOffsetForStringIndex(line, startIndex, nil)
        var endOffset = CTLineGetOffsetForStringIndex(line, endIndex, nil)
        
        switch alignment {
        case .center:
            let additional = floorToScreenPixels(System.backingScale, (boundingWidth - frame.width) / 2)
            startOffset += additional
            endOffset += additional
        case .right:
            startOffset = boundingWidth - startOffset
            endOffset =  boundingWidth - endOffset
        default:
            break
        }
        
        let selectedRange = NSMakeRange(min(startIndex, endIndex), abs(endIndex - startIndex))
        if rangeIsOnlyButtons(selectedRange) {
            self.selectRect = NSZeroRect
            return NSAttributedString()
        }

        var selectRect = NSMakeRect(startOffset, frame.minY - 2, endOffset - startOffset, frame.height + 6)

        if isRTL {
            selectRect.origin.x += (boundingWidth - frame.width)
        }

        self.selectRect = selectRect
        return attributedString.attributedSubstring(from: selectedRange)
    }
    
    public func selectWord(in point: NSPoint, boundingWidth: CGFloat, alignment: NSTextAlignment, rect: NSRect) -> NSAttributedString {
        
        var point = point
        if isRTL {
             point.x -= (boundingWidth - frame.width)
        }
        
        let lastIndex = self.range.location + self.range.length - 1
        if lastIndex < self.range.location {
            self.selectRect = NSZeroRect
            return NSAttributedString()
        }
        let startIndex: CFIndex = max(self.range.location, min(CTLineGetStringIndexForPosition(line, point), lastIndex))

        if rangeIsOnlyButtons(NSMakeRange(startIndex, 1)) {
            self.selectRect = NSZeroRect
            return NSAttributedString()
        }

        var prev = startIndex
        var next = startIndex
        var range = NSMakeRange(startIndex, 1)
        let char:NSString = attributedString.string.nsstring.substring(with: range) as NSString
        var effectiveRange:NSRange = NSMakeRange(NSNotFound, 0)
        let check = attributedString.attribute(NSAttributedString.Key.link, at: range.location, effectiveRange: &effectiveRange)
        if check != nil && effectiveRange.location != NSNotFound {
            return attributedString.attributedSubstring(from: effectiveRange)
        }
        if char == "" {
            return NSAttributedString()
        }
        let valid:Bool = char.trimmingCharacters(in: NSCharacterSet.alphanumerics) == "" || char == "_"
        let string:NSString = attributedString.string.nsstring
        while valid {
            let prevChar = string.substring(with: NSMakeRange(prev, 1))
            let nextChar = string.substring(with: NSMakeRange(next, 1))
            var prevValid:Bool = prevChar.trimmingCharacters(in: NSCharacterSet.alphanumerics) == "" || prevChar == "_"
            var nextValid:Bool = nextChar.trimmingCharacters(in: NSCharacterSet.alphanumerics) == "" || nextChar == "_"
            if (prevValid && prev > 0) {
                prev -= 1
            }
            if(nextValid && next < string.length - 1) {
                next += 1
            }
            range.location = prevValid ? prev : prev + 1;
            range.length =  next - range.location;
            if prev == 0 {
                prevValid = false
            }
            if(next == string.length - 1) {
                nextValid = false
                range.length += 1
            }
            if !prevValid && !nextValid {
                break
            }
            if prev == 0 && !nextValid {
                break
            }
        }

        
        var startOffset = CTLineGetOffsetForStringIndex(line, range.location, nil)
        var endOffset = CTLineGetOffsetForStringIndex(line, range.location + range.length, nil)

        switch alignment {
        case .center:
            let additional = floorToScreenPixels(System.backingScale, (boundingWidth - frame.width) / 2)
            startOffset += additional
            endOffset += additional
        case .right:
            startOffset = boundingWidth - startOffset
            endOffset =  boundingWidth - endOffset
        default:
            break
        }
     
        
        selectRect = NSMakeRect(startOffset, frame.minY - 2, endOffset - startOffset, frame.height + 6)
        
        
        
        if isRTL {
            selectRect.origin.x += (boundingWidth - frame.width)
        }
        
        return attributedString.attributedSubstring(from: range)
    }
    
    public func removeSelection() {
        selectRect = NSZeroRect
    }
}


private func frameForLine(_ line: InstantPageTextLine, boundingWidth: CGFloat, alignment: NSTextAlignment) -> CGRect {
    var lineFrame = line.frame
    if alignment == .center {
        lineFrame.origin.x = floor((boundingWidth - lineFrame.size.width) / 2.0)
    } else if alignment == .right || (alignment == .natural && line.isRTL) {
        lineFrame.origin.x = boundingWidth - lineFrame.size.width
    }
    return lineFrame
}

public final class InstantPageTextItem: InstantPageItem {
    public var hasLinks: Bool = false
    
    public let isInteractive: Bool = false
    
    public let attributedString: NSAttributedString
    public let lines: [InstantPageTextLine]
    public let rtlLineIndices: Set<Int>
    public var frame: CGRect
    public let alignment: NSTextAlignment
    public let medias: [InstantPageMedia] = []
    public let anchors: [String: (Int, Bool)]
    public let wantsView: Bool = false
    public let separatesTiles: Bool = false
    public var selectable: Bool = true

    public var isSpoilerRevealed: Bool = false

    public var instantPageTheme: InstantPageTheme?

    public var hasButtons: Bool {
        for line in self.lines where !line.buttonItems.isEmpty { return true }
        return false
    }

    public var hasSpoilers: Bool {
        for line in self.lines {
            if !line.spoilerItems.isEmpty { return true }
        }
        return false
    }

    public var containsRTL: Bool {
        return !self.rtlLineIndices.isEmpty
    }
    
    public init(frame: CGRect, attributedString: NSAttributedString, alignment: NSTextAlignment, lines: [InstantPageTextLine]) {
        self.attributedString = attributedString
        self.alignment = alignment
        self.frame = frame
        self.lines = lines
        var index = 0
        var rtlLineIndices = Set<Int>()
        var anchors: [String: (Int, Bool)] = [:]
        for line in lines {
            if line.isRTL {
                rtlLineIndices.insert(index)
            }
            for anchor in line.anchorItems {
                anchors[anchor.name] = (index, anchor.empty)
            }
            index += 1
        }
        self.rtlLineIndices = rtlLineIndices
        self.anchors = anchors
    }
    
    public func linkAt(point: NSPoint) -> InstantPageUrlItem? {
        for line in lines {
            var point = NSMakePoint(point.x, point.y)
            switch alignment {
            case .center:
                point.x -= floorToScreenPixels(System.backingScale, (frame.width - line.frame.width) / 2)
            case .right:
                point.x = frame.width - point.x
            default:
                break
            }
            
            if NSPointInRect(point, line.frame) {
                return line.linkAt(point: NSMakePoint(point.x, 0))
            }
        }
        return nil
    }

    /// The line's frame with this item's paragraph alignment applied (centered / right-aligned), exactly
    /// as `drawInTile` positions it. The raw `line.frame` is left-based, so any geometry that must line up
    /// with the DRAWN text (selection rects, hit-testing) must use this, not `line.frame`.
    public func alignedLineFrame(_ line: InstantPageTextLine) -> CGRect {
        return frameForLine(line, boundingWidth: self.frame.size.width, alignment: self.alignment)
    }

    /// The complete horizontal extent painted for a line. CoreText owns the text frame, while inline
    /// button pills are drawn separately from attachment frames and can extend beyond the typographic
    /// bounds CoreText reports. Consumers that size or clip the containing bubble must use this frame.
    public func visualLineFrame(_ line: InstantPageTextLine) -> CGRect {
        let lineFrame = self.alignedLineFrame(line)
        var result = lineFrame
        for button in line.buttonItems {
            result = result.union(button.frame.offsetBy(dx: lineFrame.minX, dy: 0.0))
        }
        return result
    }

    public func drawInTile(context: CGContext) {
        self.drawInTile(context: context, backingScaleFactor: nil)
    }

    public func drawInTile(context: CGContext, backingScaleFactor: CGFloat?) {
        context.saveGState()
        context.textMatrix = CGAffineTransform(scaleX: 1.0, y: -1.0)
        context.translateBy(x: self.frame.minX, y: self.frame.minY)
        let transform = context.ctm
        let smoothFonts = backingScaleFactor.map { $0 == 1.0 } ?? (hypot(transform.a, transform.b) <= 1.0)
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setAllowsFontSmoothing(smoothFonts)
        context.setShouldSmoothFonts(smoothFonts)
        context.setAllowsFontSubpixelPositioning(true)
        context.setShouldSubpixelPositionFonts(true)

        let clipRect = context.boundingBoxOfClipPath
        
        let upperOriginBound = clipRect.minY - 10.0
        let lowerOriginBound = clipRect.maxY + 10.0
        let boundsWidth = self.frame.size.width
        
        for i in 0 ..< self.lines.count {
            let line = self.lines[i]
            let lineFrame = frameForLine(line, boundingWidth: boundsWidth, alignment: self.alignment)
            if lineFrame.maxY < upperOriginBound || lineFrame.minY > lowerOriginBound {
                continue
            }
            
            let lineOrigin = lineFrame.origin
            
            
           
            
            context.textPosition = CGPoint(x: lineOrigin.x, y: lineOrigin.y + lineFrame.size.height)
            
            
            if !line.markedItems.isEmpty {
                context.saveGState()
                for item in line.markedItems {
                    // A fully transparent marker is a deliberate "no highlight" (button labels push a
                    // clear linkMarkerColor); skip the path rather than filling with nothing.
                    guard item.color.alphaComponent > 0 else {
                        continue
                    }
                    let itemFrame = item.frame.offsetBy(dx: lineFrame.minX, dy: 0.0)
                    context.setFillColor(item.color.cgColor)

                    let height = floor(itemFrame.height * 1.2)
                    let rect = CGRect(
                        x: itemFrame.minX - 2.0,
                        y: floor(itemFrame.minY + (itemFrame.height - height) / 2.0),
                        width: itemFrame.width + 4.0,
                        height: height
                    )
                    let path = CGPath(roundedRect: rect, cornerWidth: 3, cornerHeight: 3, transform: nil)
                    context.addPath(path)
                    context.fillPath()
                }
                context.restoreGState()
            }
            context.setFillColor(theme.colors.selectText.cgColor)
            context.fill(line.selectRect)

            let clipsSpoilers = !line.spoilerItems.isEmpty && !self.isSpoilerRevealed
            if clipsSpoilers {
                context.saveGState()
                context.beginPath()
                for item in line.spoilerItems {
                    context.addRect(item.frame.offsetBy(dx: lineFrame.minX, dy: 0.0))
                }
                context.addRect(CGRect(x: -1_000_000, y: -1_000_000, width: 2_000_000, height: 2_000_000))
                context.clip(using: .evenOdd)
            }
            CTLineDraw(line.line, context)

            if !line.strikethroughItems.isEmpty {
                for item in line.strikethroughItems {
                    let itemFrame = item.frame.offsetBy(dx: lineFrame.minX, dy: 0.0)
                    context.setFillColor(item.color.cgColor)
                    context.fill(CGRect(x: itemFrame.minX, y: itemFrame.minY + floor((lineFrame.size.height / 2.0) + 1.0), width: itemFrame.size.width, height: 1.0))
                }
            }
            if clipsSpoilers {
                context.restoreGState()
            }

            if !line.buttonItems.isEmpty, let instantPageTheme = self.instantPageTheme {
                for button in line.buttonItems {
                    instantPageDrawButton(
                        button.attachment,
                        in: button.frame.offsetBy(dx: lineFrame.minX, dy: 0.0),
                        context: context,
                        theme: instantPageTheme,
                        isInline: true
                    )
                }
                context.textMatrix = CGAffineTransform(scaleX: 1.0, y: -1.0)
                context.textPosition = CGPoint(x: lineOrigin.x, y: lineOrigin.y + lineFrame.size.height)
            }

            if !line.formulaItems.isEmpty {
                for formula in line.formulaItems {
                    let itemFrame = formula.frame.offsetBy(dx: lineFrame.minX, dy: 0.0)
                    if let cg = formula.attachment.rendered.image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        context.saveGState()
                        context.translateBy(x: itemFrame.minX, y: itemFrame.maxY)
                        context.scaleBy(x: 1.0, y: -1.0)
                        context.draw(cg, in: CGRect(origin: .zero, size: itemFrame.size))
                        context.restoreGState()
                    }
                }
            }

        }
        
        context.restoreGState()
    }
    
    public func linkSelectionViews() -> [InstantPageLinkSelectionView] {
        return []
    }
    
    public func matchesAnchor(_ anchor: String) -> Bool {
        return false
    }
    
    public func view(arguments: InstantPageItemArguments, currentExpandedDetails: [Int : Bool]?) -> (InstantPageView & NSView)? {
        return nil
    }
    
    public func matchesView(_ node: InstantPageView) -> Bool {
        return false
    }
    
    public func distanceThresholdGroup() -> Int? {
        return nil
    }
    
    public func distanceThresholdWithGroupCount(_ count: Int) -> CGFloat {
        return 0.0
    }
    
    public func lineRects() -> [CGRect] {
        let boundsWidth = self.frame.width
        var rects: [CGRect] = []
        var topLeft = CGPoint(x: CGFloat.greatestFiniteMagnitude, y: 0.0)
        var bottomRight = CGPoint()
        
        var lastLineFrame: CGRect?
        for i in 0 ..< self.lines.count {
            let line = self.lines[i]
            
            var lineFrame = line.frame
            for imageItem in line.imageItems {
                if imageItem.frame.minY < lineFrame.minY {
                    let delta = lineFrame.minY - imageItem.frame.minY - 2.0
                    lineFrame = CGRect(x: lineFrame.minX, y: lineFrame.minY - delta, width: lineFrame.width, height: lineFrame.height + delta)
                }
                if imageItem.frame.maxY > lineFrame.maxY {
                    let delta = imageItem.frame.maxY - lineFrame.maxY - 2.0
                    lineFrame = CGRect(x: lineFrame.minX, y: lineFrame.minY, width: lineFrame.width, height: lineFrame.height + delta)
                }
            }
            lineFrame = lineFrame.insetBy(dx: 0.0, dy: -4.0)
            if self.alignment == .center {
                lineFrame.origin.x = floor((boundsWidth - lineFrame.size.width) / 2.0)
            } else if self.alignment == .right {
                lineFrame.origin.x = boundsWidth - lineFrame.size.width
            } else if self.alignment == .natural && self.rtlLineIndices.contains(i) {
                lineFrame.origin.x = boundsWidth - lineFrame.size.width
            }
            
            if lineFrame.minX < topLeft.x {
                topLeft = CGPoint(x: lineFrame.minX, y: topLeft.y)
            }
            if lineFrame.maxX > bottomRight.x {
                bottomRight = CGPoint(x: lineFrame.maxX, y: bottomRight.y)
            }
            
            if self.lines.count > 1 && i == self.lines.count - 1 {
                lastLineFrame = lineFrame
            } else {
                if lineFrame.minY < topLeft.y {
                    topLeft = CGPoint(x: topLeft.x, y: lineFrame.minY)
                }
                if lineFrame.maxY > bottomRight.y {
                    bottomRight = CGPoint(x: bottomRight.x, y: lineFrame.maxY)
                }
            }
        }
        rects.append(CGRect(x: topLeft.x, y: topLeft.y, width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y))
        if self.lines.count > 1, var lastLineFrame = lastLineFrame {
            let delta = lastLineFrame.minY - bottomRight.y
            lastLineFrame = CGRect(x: lastLineFrame.minX, y: bottomRight.y, width: lastLineFrame.width, height: lastLineFrame.height + delta)
            rects.append(lastLineFrame)
        }
        
        return rects
    }
    
    public func effectiveWidth() -> CGFloat {
        var width: CGFloat = 0.0
        for line in self.lines {
            width = max(width, line.frame.width)
        }
        return ceil(width)
    }
    
    public func plainText() -> String {
        if let first = self.lines.first, let last = self.lines.last {
            return self.attributedString.attributedSubstring(from: NSMakeRange(first.range.location, last.range.location + last.range.length - first.range.location)).string
        }
        return ""
    }
    
}





private final class InstantPageSelectionText: NSObject {
    let makeText: (String) -> RichText

    init(_ makeText: @escaping (String) -> RichText) {
        self.makeText = makeText
    }
}

private let instantPageSelectionTextKey = NSAttributedString.Key("InstantPageSelectionText")

public func instantPageRichTextForSelection(_ selection: NSAttributedString) -> RichText {
    var parts: [RichText] = []
    selection.enumerateAttribute(instantPageSelectionTextKey, in: NSRange(location: 0, length: selection.length)) { value, range, _ in
        let text = (selection.string as NSString).substring(with: range)
        parts.append((value as? InstantPageSelectionText)?.makeText(text) ?? .plain(text))
    }
    if parts.count == 1 {
        return parts[0]
    }
    return .concat(parts)
}

public func instantPageQuoteRanges(in blocks: [NSAttributedString], text: String, range: NSRange? = nil) -> [NSRange?] {
    struct Run {
        let block: Int
        let sourceRange: NSRange
        let renderedRange: NSRange
        let isLiteral: Bool
    }
    let source = NSMutableString()
    var runs: [Run] = []
    for (index, block) in blocks.enumerated() {
        if index != 0 {
            source.append("\n")
        }
        block.enumerateAttribute(instantPageSelectionTextKey, in: NSRange(location: 0, length: block.length)) { value, renderedRange, _ in
            let rendered = (block.string as NSString).substring(with: renderedRange)
            let original = (value as? InstantPageSelectionText)?.makeText(rendered).plainText ?? rendered
            runs.append(Run(block: index, sourceRange: NSRange(location: source.length, length: (original as NSString).length), renderedRange: renderedRange, isLiteral: original == rendered))
            source.append(original)
        }
    }
    var result: [NSRange?] = Array(repeating: nil, count: blocks.count)
    guard !text.isEmpty else { return result }
    let match: NSRange
    if let range, range.location != NSNotFound, range.location >= 0, range.length >= 0,
       range.location <= source.length, range.length <= source.length - range.location,
       source.substring(with: range) == text {
        match = range
    } else {
        match = source.range(of: text)
    }
    guard match.location != NSNotFound else { return result }
    for run in runs {
        let intersection = NSIntersectionRange(run.sourceRange, match)
        guard intersection.length > 0 else { continue }
        let renderedRange = run.isLiteral
            ? NSRange(location: run.renderedRange.location + intersection.location - run.sourceRange.location, length: intersection.length)
            : run.renderedRange
        result[run.block] = result[run.block].map { NSUnionRange($0, renderedRange) } ?? renderedRange
    }
    return result
}

public func attributedStringForRichText(_ text: RichText, styleStack: InstantPageTextStyleStack, url: InstantPageUrlItem? = nil, boundingWidth: CGFloat? = nil, inlineButtonMaxWidth: CGFloat? = nil, isInsideTableCell: Bool = false) -> NSAttributedString {
    let result = renderedAttributedStringForRichText(text, styleStack: styleStack, url: url, boundingWidth: boundingWidth, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
    guard result.length > 0 else {
        return result
    }
    let wrap: (RichText) -> RichText
    switch text {
    case .empty, .concat:
        return result
    case .plain:
        let mutable = NSMutableAttributedString(attributedString: result)
        mutable.addAttribute(instantPageSelectionTextKey, value: InstantPageSelectionText { .plain($0) }, range: NSRange(location: 0, length: mutable.length))
        return mutable
    case .image, .formula, .textCustomEmoji, .textButton:
        let mutable = NSMutableAttributedString(attributedString: result)
        mutable.addAttribute(instantPageSelectionTextKey, value: InstantPageSelectionText { _ in text }, range: NSRange(location: 0, length: mutable.length))
        return mutable
    case .bold: wrap = { .bold($0) }
    case .italic: wrap = { .italic($0) }
    case .underline: wrap = { .underline($0) }
    case .strikethrough: wrap = { .strikethrough($0) }
    case .fixed: wrap = { .fixed($0) }
    case let .url(_, url, webpageId): wrap = { .url(text: $0, url: url, webpageId: webpageId) }
    case let .email(_, email): wrap = { .email(text: $0, email: email) }
    case .subscript: wrap = { .subscript($0) }
    case .superscript: wrap = { .superscript($0) }
    case .marked: wrap = { .marked($0) }
    case let .phone(_, phone): wrap = { .phone(text: $0, phone: phone) }
    case let .anchor(_, name): wrap = { .anchor(text: $0, name: name) }
    case .textAutoEmail: wrap = { .textAutoEmail(text: $0) }
    case .textAutoPhone: wrap = { .textAutoPhone(text: $0) }
    case .textAutoUrl: wrap = { .textAutoUrl(text: $0) }
    case .textBankCard: wrap = { .textBankCard(text: $0) }
    case .textTonAddress: wrap = { .textTonAddress(text: $0) }
    case .textBotCommand: wrap = { .textBotCommand(text: $0) }
    case .textCashtag: wrap = { .textCashtag(text: $0) }
    case .textHashtag: wrap = { .textHashtag(text: $0) }
    case .textMention: wrap = { .textMention(text: $0) }
    case let .textMentionName(_, peerId): wrap = { .textMentionName(text: $0, peerId: peerId) }
    case .textSpoiler: wrap = { .textSpoiler(text: $0) }
    case let .textDate(_, date, format): wrap = { .textDate(text: $0, date: date, format: format) }
    }
    let mutable = NSMutableAttributedString(attributedString: result)
    result.enumerateAttribute(instantPageSelectionTextKey, in: NSRange(location: 0, length: result.length)) { value, range, _ in
        let inner = value as? InstantPageSelectionText
        mutable.addAttribute(instantPageSelectionTextKey, value: InstantPageSelectionText { wrap(inner?.makeText($0) ?? .plain($0)) }, range: range)
    }
    return mutable
}

private func renderedAttributedStringForRichText(_ text: RichText, styleStack: InstantPageTextStyleStack, url: InstantPageUrlItem? = nil, boundingWidth: CGFloat? = nil, inlineButtonMaxWidth: CGFloat? = nil, isInsideTableCell: Bool = false) -> NSAttributedString {
    switch text {
    case .empty:
        return NSAttributedString(string: "", attributes: styleStack.textAttributes())
    case let .plain(string):
        var attributes = styleStack.textAttributes()
        if let url = url {
            attributes[.URL] = url
        }
        return NSAttributedString(string: string, attributes: attributes)
    case let .bold(text):
        styleStack.push(.bold)
        let result = attributedStringForRichText(text, styleStack: styleStack, url: url, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        styleStack.pop()
        return result
    case let .italic(text):
        styleStack.push(.italic)
        let result = attributedStringForRichText(text, styleStack: styleStack, url: url, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        styleStack.pop()
        return result
    case let .underline(text):
        styleStack.push(.underline)
        let result = attributedStringForRichText(text, styleStack: styleStack, url: url, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        styleStack.pop()
        return result
    case let .strikethrough(text):
        styleStack.push(.strikethrough)
        let result = attributedStringForRichText(text, styleStack: styleStack, url: url, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        styleStack.pop()
        return result
    case let .fixed(text):
        styleStack.push(.fontFixed(true))
        let result = attributedStringForRichText(text, styleStack: styleStack, url: url, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        styleStack.pop()
        return result
    case let .url(text, url, webpageId):
        styleStack.push(.link(webpageId != nil))
        let result = attributedStringForRichText(text, styleStack: styleStack, url: InstantPageUrlItem(url: url, webpageId: webpageId), inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        styleStack.pop()
        return result
    case let .email(text, email):
        styleStack.push(.bold)
        styleStack.push(.underline)
        let result = attributedStringForRichText(text, styleStack: styleStack, url: InstantPageUrlItem(url: "mailto:\(email)", webpageId: nil), inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        styleStack.pop()
        styleStack.pop()
        return result
    case let .concat(texts):
        let string = NSMutableAttributedString()
        for text in texts {
            let substring = attributedStringForRichText(text, styleStack: styleStack, url: url, boundingWidth: boundingWidth, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
            string.append(substring)
        }
        return string
    case let .subscript(text):
        styleStack.push(.subscript)
        let result = attributedStringForRichText(text, styleStack: styleStack, url: url, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        styleStack.pop()
        return result
    case let .superscript(text):
        styleStack.push(.superscript)
        let result = attributedStringForRichText(text, styleStack: styleStack, url: url, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        styleStack.pop()
        return result
    case let .marked(text):
        styleStack.push(.marker)
        let result = attributedStringForRichText(text, styleStack: styleStack, url: url, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        styleStack.pop()
        return result
    case let .phone(text, phone):
        styleStack.push(.bold)
        styleStack.push(.underline)
        let result = attributedStringForRichText(text, styleStack: styleStack, url: InstantPageUrlItem(url: "tel:\(phone)", webpageId: nil), inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        styleStack.pop()
        styleStack.pop()
        return result
    case let .image(id, dimensions):
        struct RunStruct {
            let ascent: CGFloat
            let descent: CGFloat
            let width: CGFloat
        }
        
        var dimensions = dimensions.size
        if let boundingWidth = boundingWidth {
            dimensions = dimensions.fittedToWidthOrSmaller(boundingWidth)
        }
        let extentBuffer = UnsafeMutablePointer<RunStruct>.allocate(capacity: 1)
        extentBuffer.initialize(to: RunStruct(ascent: 0.0, descent: 0.0, width: dimensions.width))
        var callbacks = CTRunDelegateCallbacks(version: kCTRunDelegateVersion1, dealloc: { (pointer) in
            pointer.assumingMemoryBound(to: RunStruct.self).deallocate()
        }, getAscent: { (pointer) -> CGFloat in
            let d = pointer.assumingMemoryBound(to: RunStruct.self)
            return d.pointee.ascent
        }, getDescent: { (pointer) -> CGFloat in
            let d = pointer.assumingMemoryBound(to: RunStruct.self)
            return d.pointee.descent
        }, getWidth: { (pointer) -> CGFloat in
            let d = pointer.assumingMemoryBound(to: RunStruct.self)
            return d.pointee.width
        })
        let delegate = CTRunDelegateCreate(&callbacks, extentBuffer)
        let attrDictionaryDelegate = [(kCTRunDelegateAttributeName as NSAttributedString.Key): (delegate as Any), .instantPageMediaIdAttribute : id.id, .instantPageMediaDimensionsAttribute: dimensions]
        return NSAttributedString(string: " ", attributes: attrDictionaryDelegate)
    case let .anchor(text, name):
        var empty = false
        var text = text
        if case .empty = text {
            empty = true
            text = .plain("\u{200b}")
        }
        styleStack.push(.anchor(name, empty))
        let result = attributedStringForRichText(text, styleStack: styleStack, url: url, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        styleStack.pop()
        return result
    case .formula(latex: let latex):
        let attributes = styleStack.textAttributes()
        let textColor = (attributes[.foregroundColor] as? NSColor) ?? .black
        let fontSize = (attributes[.font] as? NSFont)?.pointSize ?? 16.0

        guard let attachment = instantPageMathAttachment(latex: latex, fontSize: fontSize, textColor: textColor, mode: .inline) else {
            var fallbackAttributes = attributes
            if let url = url {
                fallbackAttributes[.URL] = url
            }
            return NSAttributedString(string: latex, attributes: fallbackAttributes)
        }

        struct RunStruct {
            let ascent: CGFloat
            let descent: CGFloat
            let width: CGFloat
        }
        let extentBuffer = UnsafeMutablePointer<RunStruct>.allocate(capacity: 1)
        extentBuffer.initialize(to: RunStruct(ascent: attachment.rendered.ascent, descent: attachment.rendered.descent, width: attachment.rendered.size.width))
        var callbacks = CTRunDelegateCallbacks(version: kCTRunDelegateVersion1, dealloc: { pointer in
            pointer.assumingMemoryBound(to: RunStruct.self).deallocate()
        }, getAscent: { pointer -> CGFloat in
            let data = pointer.assumingMemoryBound(to: RunStruct.self)
            return data.pointee.ascent
        }, getDescent: { pointer -> CGFloat in
            let data = pointer.assumingMemoryBound(to: RunStruct.self)
            return data.pointee.descent
        }, getWidth: { pointer -> CGFloat in
            let data = pointer.assumingMemoryBound(to: RunStruct.self)
            return data.pointee.width
        })
        let delegate = CTRunDelegateCreate(&callbacks, extentBuffer)
        let mutableAttributedString = attributedStringForRichText(.plain(" "), styleStack: styleStack, url: url, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell).mutableCopy() as! NSMutableAttributedString
        mutableAttributedString.addAttributes([
            kCTRunDelegateAttributeName as NSAttributedString.Key: delegate as Any,
            .instantPageFormulaAttribute: attachment
        ], range: NSMakeRange(0, mutableAttributedString.length))
        return mutableAttributedString
    case let .textAutoUrl(text):
        styleStack.push(.link(false))
        let result = attributedStringForRichText(text, styleStack: styleStack, url: InstantPageUrlItem(url: text.plainText, webpageId: nil), inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        styleStack.pop()
        return result
    case let .textAutoEmail(text):
        styleStack.push(.link(false))
        let result = attributedStringForRichText(text, styleStack: styleStack, url: InstantPageUrlItem(url: "mailto:\(text.plainText)", webpageId: nil), inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        styleStack.pop()
        return result
    case let .textAutoPhone(text):
        styleStack.push(.link(false))
        let result = attributedStringForRichText(text, styleStack: styleStack, url: InstantPageUrlItem(url: "tel:\(text.plainText)", webpageId: nil), inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        styleStack.pop()
        return result
    case let .textTonAddress(text):
        var components = URLComponents(string: "https://t.me/sendgrams")!
        components.queryItems = [URLQueryItem(name: "to", value: text.plainText)]
        styleStack.push(.link(false))
        let result = attributedStringForRichText(text, styleStack: styleStack, url: InstantPageUrlItem(url: components.string!, webpageId: nil, tonAddress: text.plainText), inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        styleStack.pop()
        return result
    case let .textMention(text):
        styleStack.push(.link(false))
        let routed = InstantPageUrlItem(url: text.plainText, webpageId: nil)
        let result = attributedStringForRichText(text, styleStack: styleStack, url: routed, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        styleStack.pop()
        return result
    case let .textHashtag(text):
        styleStack.push(.link(false))
        let routed = InstantPageUrlItem(url: text.plainText, webpageId: nil)
        let result = attributedStringForRichText(text, styleStack: styleStack, url: routed, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        styleStack.pop()
        return result
    case let .textBotCommand(text):
        styleStack.push(.link(false))
        let routed = InstantPageUrlItem(url: text.plainText, webpageId: nil)
        let result = attributedStringForRichText(text, styleStack: styleStack, url: routed, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        styleStack.pop()
        return result
    case let .textMentionName(text, peerId):
        guard peerId > 0, peerId < (1 << 52) else {
            return attributedStringForRichText(text, styleStack: styleStack, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        }
        // Mention by peer id (no username): route to a peer URL so the run is a real link (clickable +
        // tooltip). The rich-text host intercepts `tg://user?id=` and opens the peer's profile.
        styleStack.push(.link(false))
        let routed = InstantPageUrlItem(url: "tg://user?id=\(peerId)", webpageId: nil)
        let result = attributedStringForRichText(text, styleStack: styleStack, url: routed, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        styleStack.pop()
        return result
    case let .textCashtag(text):
        // Cashtag ($GOOG): route the run to its own text as a link so the host's `inApp` resolves it
        // to a hashtag/cashtag search (same as #hashtags).
        styleStack.push(.link(false))
        let routed = InstantPageUrlItem(url: text.plainText, webpageId: nil)
        let result = attributedStringForRichText(text, styleStack: styleStack, url: routed, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        styleStack.pop()
        return result
    case let .textBankCard(text):
        styleStack.push(.link(false))
        let result = attributedStringForRichText(text, styleStack: styleStack, url: url, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        styleStack.pop()
        return result
    case let .textSpoiler(text):
        let inner = attributedStringForRichText(text, styleStack: styleStack, url: url, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
        let mutable = inner.mutableCopy() as! NSMutableAttributedString
        if mutable.length != 0 {
            mutable.addAttribute(TextInputAttributes.spoiler, value: true, range: NSRange(location: 0, length: mutable.length))
        }
        return mutable
    case let .textCustomEmoji(fileId, alt):
        var attributes = styleStack.textAttributes()
        if let url = url {
            attributes[.URL] = url
        }
        struct RunStruct {
            let ascent: CGFloat
            let descent: CGFloat
            let width: CGFloat
        }
        let font = (attributes[.font] as? NSFont) ?? NSFont.systemFont(ofSize: 17.0)
        // Match iOS: the player bleeds beyond the font's line box, while the run delegate keeps the
        // surrounding text on its normal baseline and reserves the player's exact square width.
        let itemSize = font.ascender - font.descender + 4.0 * font.pointSize / 17.0
        let extentBuffer = UnsafeMutablePointer<RunStruct>.allocate(capacity: 1)
        extentBuffer.initialize(to: RunStruct(ascent: font.ascender, descent: font.descender, width: itemSize))
        var callbacks = CTRunDelegateCallbacks(version: kCTRunDelegateVersion1, dealloc: { pointer in
            pointer.assumingMemoryBound(to: RunStruct.self).deallocate()
        }, getAscent: { pointer -> CGFloat in
            return pointer.assumingMemoryBound(to: RunStruct.self).pointee.ascent
        }, getDescent: { pointer -> CGFloat in
            return pointer.assumingMemoryBound(to: RunStruct.self).pointee.descent
        }, getWidth: { pointer -> CGFloat in
            return pointer.assumingMemoryBound(to: RunStruct.self).pointee.width
        })
        let delegate = CTRunDelegateCreate(&callbacks, extentBuffer)
        let emoji = ChatTextCustomEmojiAttribute(fileId: fileId, file: nil, emoji: alt)
        let result = NSMutableAttributedString(string: " ", attributes: attributes)
        let range = NSRange(location: 0, length: result.length)
        result.addAttributes([
            kCTRunDelegateAttributeName as NSAttributedString.Key: delegate as Any,
            TextInputAttributes.embedded: InlineStickerItem(source: .attribute(emoji))
        ], range: range)
        return result
    case .textDate(text: let text, date: _, format: _):
        // Mirrors telegram-ios's attributedStringForRichText: it reformats the timestamp only when a
        // `formatDate` closure is threaded through. macOS plumbs no such closure, so this is iOS's
        // fallback branch — render the server-supplied inner text, which already holds the date string.
        return attributedStringForRichText(text, styleStack: styleStack, url: url, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
    case let .textButton(button):
        // Inline attachment, built like an inline formula above: measure the label, reserve the pill's
        // full box via a CTRunDelegate reporting REAL ascent/descent so CoreText grows the line box, and
        // carry the measurement on the attribute for the V2 line-breaker. Deliberately not the
        // inline-image shape, which reports 0/0 and then owns manual centring plus symmetric bleed — a
        // pill is taller than its glyphs and would overlap the neighbouring lines.
        // A button label has its own typography rather than inheriting the paragraph's: pushed onto the
        // surrounding stack (and popped) so nested formatting inside the label still composes.
        let presentation: InstantPageInlineButtonPresentation = button.isLink ? .plain : .pill
        let labelString: NSAttributedString
        // Suppress the link marker inside a button label. Every link gets `linkMarkerColor` painted
        // behind it as a rounded highlight, which under a pill is redundant — the pill is already the
        // affordance — and on a link-styled button (no colour, so no fill) it is the ONLY thing drawn,
        // reading as a stray tinted chip behind the label. `.marked` text inside a label is unaffected:
        // it resolves through `markerColor`, which is left alone.
        styleStack.push(.linkMarkerColor(.clear))
        if presentation == .plain {
            let isEnabled = InstantPageButtonUIModel(button: button).isEnabled
            if isEnabled {
                styleStack.push(.link(false))
            }
            labelString = attributedStringForRichText(button.text, styleStack: styleStack, url: url, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
            if isEnabled {
                styleStack.pop()
            }
        } else {
            styleStack.push(.fontSize(instantPageInlineButtonFontSize))
            styleStack.push(.medium)
            labelString = instantPageInlineButtonLabelWithInsetEmoji(
                attributedStringForRichText(button.text, styleStack: styleStack, url: url, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell)
            )
            styleStack.pop()
            styleStack.pop()
        }
        styleStack.pop()
        // Cap at the line's bounding width: a pill wider than the line cannot be re-broken onto the next
        // one (that path needs the line to hold something besides the pill), so it would otherwise
        // overflow the bubble.
        let attachment = instantPageInlineButtonAttachment(
            button: button,
            presentation: presentation,
            labelString: labelString,
            maxWidth: inlineButtonMaxWidth,
            allowBareEmoji: isInsideTableCell,
            isEnabled: styleStack.buttonsEnabled
        )

        struct RunStruct {
            let ascent: CGFloat
            let descent: CGFloat
            let width: CGFloat
        }
        let extentBuffer = UnsafeMutablePointer<RunStruct>.allocate(capacity: 1)
        extentBuffer.initialize(to: RunStruct(ascent: attachment.ascent, descent: attachment.descent, width: attachment.size.width))
        var callbacks = CTRunDelegateCallbacks(version: kCTRunDelegateVersion1, dealloc: { pointer in
            pointer.assumingMemoryBound(to: RunStruct.self).deallocate()
        }, getAscent: { pointer -> CGFloat in
            return pointer.assumingMemoryBound(to: RunStruct.self).pointee.ascent
        }, getDescent: { pointer -> CGFloat in
            return pointer.assumingMemoryBound(to: RunStruct.self).pointee.descent
        }, getWidth: { pointer -> CGFloat in
            return pointer.assumingMemoryBound(to: RunStruct.self).pointee.width
        })
        let delegate = CTRunDelegateCreate(&callbacks, extentBuffer)
        let mutableAttributedString = attributedStringForRichText(.plain(" "), styleStack: styleStack, url: url, inlineButtonMaxWidth: inlineButtonMaxWidth, isInsideTableCell: isInsideTableCell).mutableCopy() as! NSMutableAttributedString
        mutableAttributedString.addAttributes([
            kCTRunDelegateAttributeName as NSAttributedString.Key: delegate as Any,
            .instantPageInlineButtonAttribute: attachment
        ], range: NSMakeRange(0, mutableAttributedString.length))
        return mutableAttributedString
    }
}

/// Vertical metrics captured from a V2 block's base style before nested RichText changes its runs.
/// Bold, italic, fixed-width, marked text and inline buttons keep their own drawing fonts, but the
/// containing block retains one stable line rhythm.
public struct InstantPageTextLineMetrics {
    public let font: NSFont
    public let lineSpacingFactor: CGFloat

    public init?(styleStack: InstantPageTextStyleStack) {
        let attributes = styleStack.textAttributes()
        guard let font = attributes[.font] as? NSFont else {
            return nil
        }
        self.font = font
        self.lineSpacingFactor = (attributes[.instantPageLineSpacingFactorAttribute] as? NSNumber)
            .map { CGFloat($0.floatValue) } ?? 1.12
    }
}

private func instantPageLineBreakBeforeHangingEmoji(_ string: NSAttributedString, typesetter: CTTypesetter, start: CFIndex, count: CFIndex, maxWidth: CGFloat) -> CFIndex {
    if count <= 1 {
        return count
    }
    let text = string.string as NSString
    let end = start + count
    var trailingStart = end
    while trailingStart > start + 1 {
        let isWhitespace = Unicode.Scalar(text.character(at: trailingStart - 1)).map {
            CharacterSet.whitespacesAndNewlines.contains($0)
        } ?? false
        if !isWhitespace {
            break
        }
        trailingStart -= 1
    }
    if trailingStart == end {
        return count
    }
    let tolerance = 1.0 / max(1.0, System.backingScale)
    var line: CTLine?
    for index in trailingStart ..< end {
        guard let embedded = string.attribute(TextInputAttributes.embedded, at: index, effectiveRange: nil) as? InlineStickerItem,
              case .attribute = embedded.source else {
            continue
        }
        let resolvedLine = line ?? CTTypesetterCreateLineWithOffset(typesetter, CFRangeMake(start, count), 100.0)
        line = resolvedLine
        let lowerX = CTLineGetOffsetForStringIndex(resolvedLine, index, nil)
        let upperX = CTLineGetOffsetForStringIndex(resolvedLine, index + 1, nil)
        if min(lowerX, upperX) < -tolerance || max(lowerX, upperX) > maxWidth + tolerance {
            return index - start
        }
    }
    return count
}

public func layoutTextItemWithString(_ string: NSAttributedString, boundingWidth: CGFloat, horizontalInset: CGFloat = 0.0, alignment: NSTextAlignment = .natural, offset: CGPoint, media: [MediaId: Media] = [:], webpage: TelegramMediaWebpage? = nil, minimizeWidth: Bool = false, fitToWidth: Bool = false, maxNumberOfLines: Int = 0, computeRevealCharacterRects: Bool = false, trueLineBox: Bool = false, lineMetrics: InstantPageTextLineMetrics? = nil) -> (InstantPageTextItem?, [InstantPageItem], CGSize) {
    if string.length == 0 {
        return (nil, [], CGSize())
    }
    
    var lines: [InstantPageTextLine] = []
    var imageItems: [InstantPageTextImageItem] = []
    var font = string.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
    if font == nil {
        let range = NSMakeRange(0, string.length)
        string.enumerateAttributes(in: range, options: []) { attributes, range, _ in
            if font == nil, let furtherFont = attributes[.font] as? NSFont {
                font = furtherFont
            }
        }
    }
    let image = string.attribute(.instantPageMediaIdAttribute, at: 0, effectiveRange: nil)
    guard font != nil || image != nil || lineMetrics != nil else {
        return (nil, [], CGSize())
    }
    
    var lineSpacingFactor = lineMetrics?.lineSpacingFactor ?? 1.12
    if lineMetrics == nil, let lineSpacingFactorAttribute = string.attribute(.instantPageLineSpacingFactorAttribute, at: 0, effectiveRange: nil) {
        lineSpacingFactor = CGFloat((lineSpacingFactorAttribute as! NSNumber).floatValue)
    }
    
    let typesetter = CTTypesetterCreateWithAttributedString(string)
    let metricFont = lineMetrics?.font ?? font
    let fontAscent = metricFont?.ascender ?? 0.0
    let fontDescent = metricFont?.descender ?? 0.0
    
    let fontLineHeight = floor(fontAscent + fontDescent)
    let fontLineSpacing = floor(fontLineHeight * lineSpacingFactor)
    let standardLineAdvance = fontLineHeight + fontLineSpacing

    // True font-height line box (V2 layouts): shift the whole line stack down by the ascender headroom
    // above the cap line (A − L) and pad the final height by the descender (D) below the last baseline,
    // so a single-line item measures exactly A + D. Without this, item heights under-measure by the
    // descender and consecutive paragraph blocks (2pt spacing in chat) visibly overlap. Mirrors the iOS
    // V2 `layoutTextItem`; V1 instant-page layouts keep the legacy metric (trueLineBox: false).
    let fontDescentBelowBaseline = trueLineBox ? max(0.0, -fontDescent) : 0.0
    let lineBoxTopInset = trueLineBox ? max(0.0, fontAscent - fontLineHeight) : 0.0
    let baselineToNextTopSlack = trueLineBox ? max(0.0, fontLineSpacing - 4.0) : 0.0

    var lastIndex: CFIndex = 0
    var currentLineOrigin = CGPoint(x: 0.0, y: lineBoxTopInset)
    
    var hasAnchors = false
    var maxLineWidth: CGFloat = 0.0
    var maxImageHeight: CGFloat = 0.0
    var extraDescent: CGFloat = 0.0
    let text = string.string
    var indexOffset: CFIndex?
    while true {
        var workingLineOrigin = currentLineOrigin
        
        let currentMaxWidth = boundingWidth - workingLineOrigin.x
        var lineCharacterCount: CFIndex
        var hadIndexOffset = false
        if minimizeWidth {
            var count = 0
            for ch in text.suffix(text.count - lastIndex) {
                count += 1
                if ch == " " || ch == "\n" || ch == "\t" {
                    break
                }
            }
            lineCharacterCount = count
        } else {
            let suggestedLineBreak = instantPageLineBreakBeforeHangingEmoji(
                string,
                typesetter: typesetter,
                start: lastIndex,
                count: CTTypesetterSuggestLineBreak(typesetter, lastIndex, Double(currentMaxWidth)),
                maxWidth: currentMaxWidth
            )
            if let offset = indexOffset {
                lineCharacterCount = suggestedLineBreak + offset
                if lineCharacterCount <= 0 {
                    lineCharacterCount = suggestedLineBreak
                }
                indexOffset = nil
                hadIndexOffset = true
            } else {
                lineCharacterCount = suggestedLineBreak
            }
        }
        if lineCharacterCount > 0 {
            var line = CTTypesetterCreateLineWithOffset(typesetter, CFRangeMake(lastIndex, lineCharacterCount), 100.0)
            var lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
            let lineRange = NSMakeRange(lastIndex, lineCharacterCount)
            let substring = string.attributedSubstring(from: lineRange).string
            
            var stop = false
            if maxNumberOfLines > 0 && lines.count == maxNumberOfLines - 1 && lastIndex + lineCharacterCount < string.length {
                let attributes = string.attributes(at: lastIndex + lineCharacterCount - 1, effectiveRange: nil)
                if let truncateString = CFAttributedStringCreate(nil, "\u{2026}" as CFString, attributes as CFDictionary) {
                    let truncateToken = CTLineCreateWithAttributedString(truncateString)
                    let tokenWidth = CGFloat(CTLineGetTypographicBounds(truncateToken, nil, nil, nil) + 3.0)
                    if let truncatedLine = CTLineCreateTruncatedLine(line, Double(lineWidth - tokenWidth), .end, truncateToken) {
                        lineWidth += tokenWidth
                        line = truncatedLine
                    }
                }
                stop = true
            }
            
            let hadExtraDescent = extraDescent > 0.0
            extraDescent = 0.0
            var lineAscent = fontLineHeight
            var lineDescent = fontDescentBelowBaseline
            var lineImageItems: [InstantPageTextImageItem] = []
            var lineFormulaItems: [InstantPageTextFormulaItem] = []
            var lineButtonItems: [InstantPageTextButtonItem] = []
            var pendingEmojiItems: [PendingInstantPageTextEmojiItem] = []
            var isRTL = false
            if let glyphRuns = CTLineGetGlyphRuns(line) as? [CTRun], !glyphRuns.isEmpty {
                if let run = glyphRuns.first, CTRunGetStatus(run).contains(CTRunStatus.rightToLeft) {
                    isRTL = true
                }

                var appliedLineOffset: CGFloat = 0.0
                for run in glyphRuns {
                    let cfRunRange = CTRunGetStringRange(run)
                    let runRange = NSMakeRange(cfRunRange.location == kCFNotFound ? NSNotFound : cfRunRange.location, cfRunRange.length)
                    string.enumerateAttributes(in: runRange, options: []) { attributes, range, _ in
                        if let id = attributes[.instantPageMediaIdAttribute] as? Int64, let dimensions = attributes[.instantPageMediaDimensionsAttribute] as? CGSize {
                            var imageFrame = CGRect(origin: CGPoint(), size: dimensions)

                            let xOffset = CTLineGetOffsetForStringIndex(line, CTRunGetStringRange(run).location, nil)
                            let yOffset = fontLineHeight.isZero ? 0.0 : floorToScreenPixels(System.backingScale, (fontLineHeight - imageFrame.size.height) / 2.0)
                            imageFrame.origin = imageFrame.origin.offsetBy(dx: workingLineOrigin.x + xOffset, dy: workingLineOrigin.y + yOffset)

                            if !trueLineBox {
                                let minSpacing = fontLineSpacing - 4.0
                                let delta = workingLineOrigin.y - minSpacing - imageFrame.minY - appliedLineOffset
                                if !fontAscent.isZero && delta > 0.0 {
                                    workingLineOrigin.y += delta
                                    appliedLineOffset += delta
                                    imageFrame.origin = imageFrame.origin.offsetBy(dx: 0.0, dy: delta)
                                }
                                if !fontLineHeight.isZero {
                                    extraDescent = max(extraDescent, imageFrame.maxY - (workingLineOrigin.y + fontLineHeight + minSpacing))
                                }
                            }
                            maxImageHeight = max(maxImageHeight, imageFrame.height)
                            lineImageItems.append(InstantPageTextImageItem(frame: imageFrame, range: range, id: MediaId(namespace: Namespaces.Media.CloudFile, id: id)))
                        } else if let attachment = attributes[.instantPageFormulaAttribute] as? InstantPageMathAttachment {
                            let xOffset = CTLineGetOffsetForStringIndex(line, range.location, nil)
                            let baselineOffset = (attributes[.baselineOffset] as? CGFloat) ?? 0.0
                            var formulaFrame = CGRect(
                                origin: CGPoint(
                                    x: workingLineOrigin.x + xOffset,
                                    y: workingLineOrigin.y + fontLineHeight + baselineOffset - attachment.rendered.ascent
                                ),
                                size: attachment.rendered.size
                            )

                            if trueLineBox {
                                let formulaAscent = attachment.rendered.size.height - attachment.rendered.descent
                                lineAscent = max(lineAscent, formulaAscent)
                                lineDescent = max(lineDescent, attachment.rendered.descent)
                            } else {
                                let minSpacing = fontLineSpacing - 4.0
                                let delta = workingLineOrigin.y - minSpacing - formulaFrame.minY - appliedLineOffset
                                if !fontAscent.isZero && delta > 0.0 {
                                    workingLineOrigin.y += delta
                                    appliedLineOffset += delta
                                    formulaFrame.origin = formulaFrame.origin.offsetBy(dx: 0.0, dy: delta)
                                }
                                if !fontLineHeight.isZero {
                                    extraDescent = max(extraDescent, formulaFrame.maxY - (workingLineOrigin.y + fontLineHeight + minSpacing))
                                }
                            }
                            maxImageHeight = max(maxImageHeight, formulaFrame.height)
                            lineFormulaItems.append(InstantPageTextFormulaItem(frame: formulaFrame, range: range, attachment: attachment))
                        } else if let attachment = attributes[.instantPageInlineButtonAttribute] as? InstantPageInlineButtonAttachment {
                            // Same shape as the formula arm above: `attachment.ascent` already includes
                            // the pill's vertical padding, so it is the baseline-to-pill-top distance.
                            // In V2 the fixed-size inline pill fits inside the paragraph's standard
                            // baseline rhythm and must not move or enlarge its line. V1 retains its
                            // legacy attachment-overflow adjustment.
                            let xOffset = CTLineGetOffsetForStringIndex(line, range.location, nil)
                            let baselineOffset = (attributes[.baselineOffset] as? CGFloat) ?? 0.0
                            var buttonFrame = CGRect(
                                origin: CGPoint(
                                    x: workingLineOrigin.x + xOffset,
                                    y: workingLineOrigin.y + fontLineHeight + baselineOffset - attachment.ascent
                                ),
                                size: attachment.size
                            )

                            if trueLineBox {
                                // Match iOS V2: first consume the headroom already present above the
                                // reduced CoreText line box and below the baseline. A pill only grows
                                // the physical line when it genuinely exceeds that existing leeway.
                                lineAscent = max(lineAscent, attachment.ascent - lineBoxTopInset)
                                lineDescent = max(lineDescent, attachment.descent - baselineToNextTopSlack)
                            } else {
                                let minSpacing = fontLineSpacing - 4.0
                                let delta = workingLineOrigin.y - minSpacing - buttonFrame.minY - appliedLineOffset
                                if !fontAscent.isZero && delta > 0.0 {
                                    workingLineOrigin.y += delta
                                    appliedLineOffset += delta
                                    buttonFrame.origin = buttonFrame.origin.offsetBy(dx: 0.0, dy: delta)
                                }
                                if !fontLineHeight.isZero {
                                    extraDescent = max(extraDescent, buttonFrame.maxY - (workingLineOrigin.y + fontLineHeight + minSpacing))
                                }
                            }
                            maxImageHeight = max(maxImageHeight, buttonFrame.height)
                            lineButtonItems.append(InstantPageTextButtonItem(frame: buttonFrame, range: range, attachment: attachment))
                        } else if let embedded = attributes[TextInputAttributes.embedded] as? InlineStickerItem,
                                  case let .attribute(emoji) = embedded.source {
                            let lowerX = CTLineGetOffsetForStringIndex(line, range.location, nil)
                            let upperX = CTLineGetOffsetForStringIndex(line, range.location + range.length, nil)
                            let runFont = (attributes[.font] as? NSFont) ?? metricFont ?? NSFont.systemFont(ofSize: 17.0)
                            let itemSize = runFont.ascender - runFont.descender + 4.0 * runFont.pointSize / 17.0
                            pendingEmojiItems.append(PendingInstantPageTextEmojiItem(
                                xOffset: min(lowerX, upperX),
                                range: range,
                                emoji: emoji,
                                size: itemSize,
                                textColor: attributes[.foregroundColor] as? NSColor
                            ))
                        }
                    }
                }
            }

            let lineBaselineOffset = trueLineBox ? max(0.0, lineAscent - fontLineHeight) : 0.0
            let baselineY = workingLineOrigin.y + fontLineHeight + lineBaselineOffset
            let lineEmojiItems = pendingEmojiItems.map { item in
                InstantPageTextEmojiItem(
                    frame: CGRect(
                        x: workingLineOrigin.x + item.xOffset,
                        y: floorToScreenPixels(System.backingScale, baselineY - fontLineHeight / 2.0 - item.size / 2.0),
                        width: item.size,
                        height: item.size
                    ),
                    range: item.range,
                    emoji: item.emoji,
                    textColor: item.textColor
                )
            }
            if trueLineBox {
                // Attachment frames above were recovered from their CoreText runs using the standard
                // body baseline. iOS resolves the final per-line ascent first, then positions every
                // attachment from that shared baseline. Translating them by the ascent delta is
                // equivalent and keeps text, pills, formulas and images on one baseline.
                if !lineBaselineOffset.isZero {
                    lineImageItems = lineImageItems.map {
                        InstantPageTextImageItem(frame: $0.frame.offsetBy(dx: 0.0, dy: lineBaselineOffset), range: $0.range, id: $0.id)
                    }
                    lineFormulaItems = lineFormulaItems.map {
                        InstantPageTextFormulaItem(frame: $0.frame.offsetBy(dx: 0.0, dy: lineBaselineOffset), range: $0.range, attachment: $0.attachment)
                    }
                    lineButtonItems = lineButtonItems.map {
                        InstantPageTextButtonItem(frame: $0.frame.offsetBy(dx: 0.0, dy: lineBaselineOffset), range: $0.range, attachment: $0.attachment)
                    }
                }

                extraDescent = max(0.0, lineDescent - baselineToNextTopSlack)
                let baselineY = workingLineOrigin.y + lineAscent
                for imageItem in lineImageItems {
                    extraDescent = max(extraDescent, imageItem.frame.maxY - (baselineY + baselineToNextTopSlack))
                }
            }

            let hasVariableHeightAttachment = !lineImageItems.isEmpty
                || !lineFormulaItems.isEmpty
                || !lineButtonItems.isEmpty
            if !trueLineBox && substring.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && hasVariableHeightAttachment {
                extraDescent += max(6.0, fontLineSpacing / 2.0)
            }

            if !minimizeWidth && lineCharacterCount > 1 {
                // CoreText can suggest a break after more than one single-character button
                // attachment. Moving only the last button still leaves an earlier pill outside the
                // line, and the adjusted line used to skip another recovery pass. Check the actual
                // pill frames on every pass and break before the first one outside the available
                // horizontal bounds. A pill already at the line start cannot move any further; its
                // label has already been truncated to the line width by the attachment builder.
                let overflowTolerance = 1.0 / max(1.0, System.backingScale)
                let availableMinX = workingLineOrigin.x - overflowTolerance
                let availableMaxX = workingLineOrigin.x + currentMaxWidth + overflowTolerance
                let overflowingButtonItem = lineButtonItems
                    .filter {
                        $0.range.lowerBound > lastIndex
                            && ($0.frame.minX < availableMinX || $0.frame.maxX > availableMaxX)
                    }
                    .min(by: { $0.range.lowerBound < $1.range.lowerBound })
                if let overflowingButtonItem {
                    indexOffset = -(lastIndex + lineCharacterCount - overflowingButtonItem.range.lowerBound)
                    continue
                }
            }
            
            if !minimizeWidth && !hadIndexOffset && lineCharacterCount > 1 && lineWidth > currentMaxWidth + 5.0 {
                if let imageItem = lineImageItems.last {
                    indexOffset = -(lastIndex + lineCharacterCount - imageItem.range.lowerBound)
                    continue
                } else if let formulaItem = lineFormulaItems.last, formulaItem.range.lowerBound > lastIndex {
                    // A wide inline formula that overflows the line: break before it so it starts a
                    // new line (matching iOS), keeping the preceding text on the current line. If the
                    // formula is already at the line start it can't break further and just overflows.
                    indexOffset = -(lastIndex + lineCharacterCount - formulaItem.range.lowerBound)
                    continue
                }
            }
            
            var strikethroughItems: [InstantPageTextStrikethroughItem] = []
            var markedItems: [InstantPageTextMarkedItem] = []
            var anchorItems: [InstantPageTextAnchorItem] = []
            var spoilerItems: [InstantPageTextSpoilerItem] = []
            let emojiItems = lineEmojiItems

            var spoilerFrameHeight = fontLineHeight
            if trueLineBox {
                var typographicDescent: CGFloat = 0.0
                var typographicLeading: CGFloat = 0.0
                _ = CTLineGetTypographicBounds(line, nil, &typographicDescent, &typographicLeading)
                spoilerFrameHeight += ceil(typographicDescent - typographicLeading) + 2.0
            }

            string.enumerateAttributes(in: lineRange, options: []) { attributes, range, _ in
                if attributes[.instantPageStrikethroughAttribute] != nil {
                    let lowerX = floor(CTLineGetOffsetForStringIndex(line, range.location, nil))
                    let upperX = ceil(CTLineGetOffsetForStringIndex(line, range.location + range.length, nil))
                    let x = lowerX < upperX ? lowerX : upperX
                    let color = (attributes[.foregroundColor] as? NSColor) ?? .black
                    strikethroughItems.append(InstantPageTextStrikethroughItem(frame: CGRect(x: workingLineOrigin.x + x, y: workingLineOrigin.y + lineBaselineOffset, width: abs(upperX - lowerX), height: fontLineHeight), color: color))
                }
                if let flag = attributes[TextInputAttributes.spoiler] as? Bool, flag {
                    let lowerX = floor(CTLineGetOffsetForStringIndex(line, range.location, nil))
                    let upperX = ceil(CTLineGetOffsetForStringIndex(line, range.location + range.length, nil))
                    let x = lowerX < upperX ? lowerX : upperX
                    spoilerItems.append(InstantPageTextSpoilerItem(frame: CGRect(x: workingLineOrigin.x + x, y: workingLineOrigin.y + lineBaselineOffset, width: abs(upperX - lowerX), height: spoilerFrameHeight)))
                }
                if let color = attributes[.instantPageMarkerColorAttribute] as? NSColor {
                    var lineHeight = fontLineHeight
                    var delta: CGFloat = 0.0
                    
                    if let offset = attributes[.baselineOffset] as? CGFloat {
                        lineHeight = floorToScreenPixels(System.backingScale, lineHeight * 0.85)
                        delta = offset * 0.6
                    }
                    let lowerX = floor(CTLineGetOffsetForStringIndex(line, range.location, nil))
                    let upperX = ceil(CTLineGetOffsetForStringIndex(line, range.location + range.length, nil))
                    let x = lowerX < upperX ? lowerX : upperX
                    markedItems.append(InstantPageTextMarkedItem(frame: CGRect(x: workingLineOrigin.x + x, y: workingLineOrigin.y + lineBaselineOffset + delta, width: abs(upperX - lowerX), height: lineHeight), color: color))
                }
                if let item = attributes[.instantPageAnchorAttribute] as? Dictionary<String, Any>, let name = item["name"] as? String, let empty = item["empty"] as? Bool {
                    anchorItems.append(InstantPageTextAnchorItem(name: name, empty: empty))
                }
            }
            
            if !anchorItems.isEmpty {
                hasAnchors = true
            }
            
            if hadExtraDescent && extraDescent > 0 {
                workingLineOrigin.y += fontLineSpacing
            }

            var lineCharacterRects: [CGRect]? = nil
            if computeRevealCharacterRects {
                var rects = [CGRect](repeating: CGRect.zero, count: lineCharacterCount)
                if let glyphRuns = CTLineGetGlyphRuns(line) as? [CTRun] {
                    for run in glyphRuns {
                        let glyphCount = CTRunGetGlyphCount(run)
                        if glyphCount == 0 {
                            continue
                        }
                        var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
                        CTRunGetGlyphs(run, CFRangeMake(0, glyphCount), &glyphs)
                        var positions = [CGPoint](repeating: .zero, count: glyphCount)
                        CTRunGetPositions(run, CFRangeMake(0, glyphCount), &positions)
                        var stringIndices = [CFIndex](repeating: 0, count: glyphCount)
                        CTRunGetStringIndices(run, CFRangeMake(0, glyphCount), &stringIndices)
                        let attributes = CTRunGetAttributes(run) as NSDictionary
                        guard let runFont = attributes[kCTFontAttributeName as String] else {
                            continue
                        }
                        let ctFont = runFont as! CTFont
                        var boundingRects = [CGRect](repeating: .zero, count: glyphCount)
                        CTFontGetBoundingRectsForGlyphs(ctFont, .default, &glyphs, &boundingRects, glyphCount)
                        for i in 0 ..< glyphCount {
                            let charIndex = stringIndices[i] - lineRange.location
                            if charIndex >= 0 && charIndex < lineCharacterCount {
                                let pos = positions[i]
                                let bbox = boundingRects[i]
                                rects[charIndex] = CGRect(
                                    x: pos.x + bbox.origin.x,
                                    y: pos.y + bbox.origin.y,
                                    width: bbox.width,
                                    height: bbox.height
                                )
                            }
                        }
                    }
                }
                for emoji in emojiItems {
                    let localIndex = emoji.range.location - lineRange.location
                    if localIndex >= 0 && localIndex < lineCharacterCount {
                        rects[localIndex] = CGRect(x: emoji.frame.minX - workingLineOrigin.x, y: 0.0, width: emoji.frame.width, height: emoji.frame.height)
                    }
                }
                for imageItem in lineImageItems {
                    let localIndex = imageItem.range.location - lineRange.location
                    if localIndex >= 0 && localIndex < lineCharacterCount {
                        rects[localIndex] = CGRect(x: imageItem.frame.minX - workingLineOrigin.x, y: 0.0, width: imageItem.frame.width, height: imageItem.frame.height)
                    }
                }
                lineCharacterRects = rects
            }

            let height = trueLineBox ? lineAscent : (!fontLineHeight.isZero ? fontLineHeight : maxImageHeight)
            let textLine = InstantPageTextLine(line: line, attributedString: string, range: lineRange, frame: CGRect(x: workingLineOrigin.x, y: workingLineOrigin.y, width: lineWidth, height: height), strikethroughItems: strikethroughItems, markedItems: markedItems, imageItems: lineImageItems, formulaItems: lineFormulaItems, buttonItems: lineButtonItems, anchorItems: anchorItems, spoilerItems: spoilerItems, emojiItems: emojiItems, isRTL: isRTL, characterRects: lineCharacterRects)
            
            lines.append(textLine)
            imageItems.append(contentsOf: lineImageItems)
            
            if lineWidth > maxLineWidth {
                maxLineWidth = lineWidth
            }
            
            workingLineOrigin.x = 0.0
            workingLineOrigin.y += (trueLineBox ? lineAscent + fontLineSpacing : standardLineAdvance) + extraDescent
            currentLineOrigin = workingLineOrigin
            
            lastIndex += lineCharacterCount
            
            if stop {
                break
            }
        } else {
            break
        }
    }
    
    var height: CGFloat = 0.0
    if !lines.isEmpty && !(string.string == "\u{200b}" && hasAnchors) {
        // + fontDescentBelowBaseline (trueLineBox only): contain the last line's descender below its
        // baseline, so the block after this item can't overlap the glyph tails.
        height = lines.last!.frame.maxY + extraDescent + fontDescentBelowBaseline
    }
    
    var textWidth = boundingWidth
    if fitToWidth && alignment == .natural {
        textWidth = maxLineWidth
    }
    var requiresScroll = false
    if !imageItems.isEmpty && maxLineWidth > boundingWidth + 10.0 {
        textWidth = maxLineWidth
        requiresScroll = true
    }
    
    let textItem = InstantPageTextItem(frame: CGRect(x: 0.0, y: 0.0, width: textWidth, height: height), attributedString: string, alignment: alignment, lines: lines)
    if !requiresScroll {
        textItem.frame = textItem.frame.offsetBy(dx: offset.x, dy: offset.y)
    }
    var items: [InstantPageItem] = []
    if !requiresScroll && (imageItems.isEmpty || string.length > 1) {
        items.append(textItem)
    }
    
    var topInset: CGFloat = 0.0
    var bottomInset: CGFloat = 0.0
    var additionalItems: [InstantPageItem] = []
    if let webpage = webpage {
        let offset = requiresScroll ? CGPoint() : offset
        for line in textItem.lines {
            let lineFrame = frameForLine(line, boundingWidth: textWidth, alignment: alignment)
            for imageItem in line.imageItems {
                if let image = media[imageItem.id] as? TelegramMediaFile {
                    let item = InstantPageImageItem(frame: imageItem.frame.offsetBy(dx: lineFrame.minX + offset.x, dy: offset.y), webPage: webpage, media: InstantPageMedia(index: -1, media: image, webpage: webpage, url: nil, caption: nil, credit: nil), interactive: false, roundCorners: false, fit: false)
                    additionalItems.append(item)
                    
                    if item.frame.minY < topInset {
                        topInset = item.frame.minY
                    }
                    if item.frame.maxY > height {
                        bottomInset = max(bottomInset, item.frame.maxY - height)
                    }
                }
            }
        }
    }
    
//    if requiresScroll {
//        textItem.frame = textItem.frame.offsetBy(dx: 0.0, dy: fabs(topInset))
//        for var item in additionalItems {
//            item.frame = item.frame.offsetBy(dx: 0.0, dy: fabs(topInset))
//        }
//
//        let scrollableItem = InstantPageScrollableTextItem(frame: CGRect(x: 0.0, y: 0.0, width: boundingWidth + horizontalInset * 2.0, height: height + fabs(topInset) + bottomInset), item: textItem, additionalItems: additionalItems, totalWidth: textWidth, horizontalInset: horizontalInset, rtl: textItem.containsRTL)
//        items.append(scrollableItem)
//    } else {
        items.append(contentsOf: additionalItems)
//    }
    
    return (requiresScroll ? nil : textItem, items, textItem.frame.size)
}
