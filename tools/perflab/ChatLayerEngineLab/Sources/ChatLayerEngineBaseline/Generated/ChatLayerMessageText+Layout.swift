import Cocoa
import TGUIKit
import InputTextView

extension ChatLayerMessageTextPresentation {
    private enum AttributeKeys {
        static let quote = TextInputAttributes.quote.rawValue as NSString
        static let spoiler = TextInputAttributes.spoiler.rawValue as NSString
        static let customEmoji = TextInputAttributes.customEmoji.rawValue as NSString
        static let formattedDate = TextInputAttributes.formattedDate.rawValue as NSString
        static let link = NSAttributedString.Key.link.rawValue as NSString
    }

    @inline(__always)
    private static func attribute(_ attributes: CFDictionary, _ key: NSString) -> UnsafeRawPointer? {
        return CFDictionaryGetValue(attributes, Unmanaged.passUnretained(key).toOpaque())
    }

    static func simpleText(_ layout: FoldingTextLayout) -> Self? {
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
            var hasQuote = false
            var index = 0
            while index < length {
                var range = CFRange()
                let attributes = CFAttributedStringGetAttributes(string, index, &range)!
                guard Self.attribute(attributes, AttributeKeys.spoiler) == nil,
                      Self.attribute(attributes, AttributeKeys.customEmoji) == nil,
                      Self.attribute(attributes, AttributeKeys.formattedDate) == nil else { return nil }
                if let quote = Self.attribute(attributes, AttributeKeys.quote) {
                    guard Unmanaged<AnyObject>.fromOpaque(quote).takeUnretainedValue() is TextViewBlockQuoteData else { return nil }
                    hasQuote = true
                }
                if Self.attribute(attributes, AttributeKeys.link) != nil { hasLinks = true }
                index = range.location + range.length
            }
            if blocks.isEmpty { blocks.reserveCapacity(layout.blocks.count) }
            let size = block.layoutSize
            blocks.append(Block(layout: text, frame: NSRect(x: 0, y: y, width: size.width, height: size.height), hasLinks: hasLinks, clipsTextToBounds: hasQuote, folding: nil))
            y += size.height
        }
        return Self(blocks: blocks, size: layout.size, nativeFeatures: [], requiresRevealAction: false)
    }

    init(_ item: ChatMessageItem) {
        self.init(item.textLayout)
    }

    init(_ layout: FoldingTextLayout) {
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
                if let quote = Self.attribute(attributes, AttributeKeys.quote) {
                    hasQuote = Unmanaged<AnyObject>.fromOpaque(quote).takeUnretainedValue() is TextViewBlockQuoteData
                }
                if Self.attribute(attributes, AttributeKeys.spoiler) != nil { features.insert(.spoiler) }
                if Self.attribute(attributes, AttributeKeys.customEmoji) != nil { features.insert(.embeddedItem) }
                if Self.attribute(attributes, AttributeKeys.formattedDate) != nil { features.insert(.formattedDate) }
                if Self.attribute(attributes, AttributeKeys.link) != nil { hasLinks = true }
                index = range.location + range.length
            }
            blocks.append(Block(layout: text, frame: NSRect(x: 0, y: y, width: block.layoutSize.width, height: height), hasLinks: hasLinks, clipsTextToBounds: hasQuote, folding: canReveal ? Folding(block) : nil))
            y += height
        }
        self.init(blocks: blocks, size: layout.size, nativeFeatures: features, requiresRevealAction: requiresRevealAction)
    }
}
