import Cocoa
import TGUIKit
import InputTextView

extension ChatLayerMessageTextPresentation {
    private enum ReferenceQuoteScanKeys {
        static let quote = TextInputAttributes.quote.rawValue as NSString
        static let spoiler = TextInputAttributes.spoiler.rawValue as NSString
        static let customEmoji = TextInputAttributes.customEmoji.rawValue as NSString
        static let formattedDate = TextInputAttributes.formattedDate.rawValue as NSString
        static let link = NSAttributedString.Key.link.rawValue as NSString
    }
    @inline(__always)
    private static func referenceQuoteScanAttribute(_ attributes: CFDictionary, _ key: NSString) -> UnsafeRawPointer? {
        return CFDictionaryGetValue(attributes, Unmanaged.passUnretained(key).toOpaque())
    }
    static func referenceSimpleText(_ layout: FoldingTextLayout) -> Self? {
        guard !layout.appendingAnimation, !layout.blocks.isEmpty else { return nil }
        var blocks: [Block] = []
        var y: CGFloat = 0
        for block in layout.blocks {
            let text = block.text
            guard block.isRevealed, !block.canReveal, text.embeddedItems.isEmpty,
                  !text.hasBlock, text.maskBlockImage.1 == nil else { return nil }
            let string = text.attributedString as CFAttributedString
            let length = CFAttributedStringGetLength(string)
            var hasLinks = false
            var index = 0
            while index < length {
                var range = CFRange()
                let attributes = CFAttributedStringGetAttributes(string, index, &range)!
                guard Self.referenceQuoteScanAttribute(attributes, ReferenceQuoteScanKeys.spoiler) == nil,
                      Self.referenceQuoteScanAttribute(attributes, ReferenceQuoteScanKeys.customEmoji) == nil,
                      Self.referenceQuoteScanAttribute(attributes, ReferenceQuoteScanKeys.formattedDate) == nil else { return nil }
                if let quote = Self.referenceQuoteScanAttribute(attributes, ReferenceQuoteScanKeys.quote), !(Unmanaged<AnyObject>.fromOpaque(quote).takeUnretainedValue() is TextViewBlockQuoteData) { return nil }
                if Self.referenceQuoteScanAttribute(attributes, ReferenceQuoteScanKeys.link) != nil { hasLinks = true }
                index = range.location + range.length
            }
            if blocks.isEmpty { blocks.reserveCapacity(layout.blocks.count) }
            let size = block.layoutSize
            blocks.append(Block(layout: text, frame: NSRect(x: 0, y: y, width: size.width, height: size.height), hasLinks: hasLinks, clipsTextToBounds: (text.attributedString.containsAttribute(attributeName: TextInputAttributes.quote) is TextViewBlockQuoteData), folding: nil))
            y += size.height
        }
        return Self(blocks: blocks, size: layout.size, nativeFeatures: [], requiresRevealAction: false)
    }
    static func referencePresentation(_ layout: FoldingTextLayout) -> Self {
        var blocks: [Block] = []
        blocks.reserveCapacity(layout.blocks.count)
        var features = Set<NativeFeature>()
        if layout.appendingAnimation { features.insert(.streaming) }
        var y: CGFloat = 0
        var requiresRevealAction = false
        for block in layout.blocks {
            let text = block.text
            let canReveal = block.canReveal
            requiresRevealAction = requiresRevealAction || canReveal
            let height = block.isRevealed ? block.layoutSize.height : block.size.height
            if !block.isRevealed && !canReveal { features.insert(.collapsed) }
            if !text.embeddedItems.isEmpty { features.insert(.embeddedItem) }
            if text.hasBlock || text.maskBlockImage.1 != nil { features.insert(.blockBackground) }
            var hasLinks = false
            var hasQuote = false
            let string = text.attributedString as CFAttributedString
            let length = CFAttributedStringGetLength(string)
            var index = 0
            while index < length {
                var range = CFRange()
                let attributes = CFAttributedStringGetAttributes(string, index, &range)!
                if let quote = Self.referenceQuoteScanAttribute(attributes, ReferenceQuoteScanKeys.quote), Unmanaged<AnyObject>.fromOpaque(quote).takeUnretainedValue() is TextViewBlockQuoteData {
                    hasQuote = true
                }
                if Self.referenceQuoteScanAttribute(attributes, ReferenceQuoteScanKeys.spoiler) != nil { features.insert(.spoiler) }
                if Self.referenceQuoteScanAttribute(attributes, ReferenceQuoteScanKeys.customEmoji) != nil { features.insert(.embeddedItem) }
                if Self.referenceQuoteScanAttribute(attributes, ReferenceQuoteScanKeys.formattedDate) != nil { features.insert(.formattedDate) }
                if Self.referenceQuoteScanAttribute(attributes, ReferenceQuoteScanKeys.link) != nil { hasLinks = true }
                index = range.location + range.length
            }
            blocks.append(Block(layout: text, frame: NSRect(x: 0, y: y, width: block.layoutSize.width, height: height), hasLinks: hasLinks, clipsTextToBounds: hasQuote && (text.attributedString.containsAttribute(attributeName: TextInputAttributes.quote) is TextViewBlockQuoteData), folding: canReveal ? Folding(block) : nil))
            y += height
        }
        return Self(blocks: blocks, size: layout.size, nativeFeatures: features, requiresRevealAction: requiresRevealAction)
    }
}
