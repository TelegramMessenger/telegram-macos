import Cocoa
import TGUIKit
@testable import ChatLayerEngineBaseline

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
}
