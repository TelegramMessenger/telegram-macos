import Cocoa
import TGUIKit
import InputTextView

struct LegacyChatLayerMessageTextPresentation {
    enum NativeFeature: Hashable {
        case streaming, quote, collapsed, embeddedItem, spoiler, formattedDate, blockBackground
    }

    struct Block {
        let layout: TextViewLayout
        let frame: NSRect
        let hasLinks: Bool
    }

    let blocks: [Block]
    let size: NSSize
    let nativeFeatures: Set<NativeFeature>
}

import Cocoa
import TGUIKit
import InputTextView

extension LegacyChatLayerMessageTextPresentation {
    init(_ item: ChatMessageItem) {
        self.init(item.textLayout)
    }

    init(_ layout: FoldingTextLayout) {
        var blocks: [Block] = []
        blocks.reserveCapacity(layout.blocks.count)
        var features = Set<NativeFeature>()
        if layout.appendingAnimation { features.insert(.streaming) }
        var y: CGFloat = 0
        for block in layout.blocks {
            let text = block.text
            let height = block.isRevealed ? block.layoutSize.height : block.size.height
            if !block.isRevealed { features.insert(.collapsed) }
            if !text.embeddedItems.isEmpty { features.insert(.embeddedItem) }
            if text.hasBlock || text.maskBlockImage.1 != nil { features.insert(.blockBackground) }
            var hasLinks = false
            text.attributedString.enumerateAttributes(in: NSRange(location: 0, length: text.attributedString.length)) { attributes, _, _ in
                if attributes[TextInputAttributes.quote] is TextViewBlockQuoteData { features.insert(.quote) }
                if attributes[TextInputAttributes.spoiler] != nil { features.insert(.spoiler) }
                if attributes[TextInputAttributes.customEmoji] != nil { features.insert(.embeddedItem) }
                if attributes[TextInputAttributes.formattedDate] != nil { features.insert(.formattedDate) }
                if attributes[.link] != nil { hasLinks = true }
            }
            blocks.append(Block(layout: text, frame: NSRect(x: 0, y: y, width: block.layoutSize.width, height: height), hasLinks: hasLinks))
            y += height
        }
        self.init(blocks: blocks, size: layout.size, nativeFeatures: features)
    }
}
