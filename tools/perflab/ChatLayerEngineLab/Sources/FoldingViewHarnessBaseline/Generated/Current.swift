import InputTextView
import Cocoa
import TGUIKit


private let quoteIcon: CGImage = InputTextView.sharedFoldingQuoteIconForLab()

final class FoldingTextQuoteLayer: SimpleLayer {
    final class CopyIconCache {
        static let shared = CopyIconCache()

        struct Key: Hashable {
            let source: ObjectIdentifier
            let color: CGColor
            let width: CGFloat
            let height: CGFloat
            let scale: CGFloat

            static func ==(lhs: Key, rhs: Key) -> Bool {
                return lhs.source == rhs.source && lhs.width == rhs.width && lhs.height == rhs.height && lhs.scale == rhs.scale && CFEqual(lhs.color, rhs.color)
            }

            func hash(into hasher: inout Hasher) {
                hasher.combine(source)
                hasher.combine(width)
                hasher.combine(height)
                hasher.combine(scale)
                hasher.combine(CFHash(color))
            }
        }

        struct Entry {
            let source: CGImage
            let image: CGImage
        }

        let lock = NSLock()
        var settings: DeviceGraphicsContextSettings?
        var images: [Key: Entry] = [:]
        var order: [Key] = []

        func image(_ source: NSImage, color: NSColor, scale: CGFloat) -> CGImage {
            guard color.type == .componentBased else {
                return source.precomposed(color, flipVertical: true, scale: scale)
            }
            var rect = CGRect(origin: .zero, size: source.size)
            guard let bitmap = source.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
                return source.precomposed(color, flipVertical: true, scale: scale)
            }
            let key = Key(source: ObjectIdentifier(bitmap), color: color.cgColor, width: source.size.width, height: source.size.height, scale: scale)
            let settings = DeviceGraphicsContextSettings.shared
            lock.lock()
            if self.settings != settings {
                images.removeAll(keepingCapacity: true)
                order.removeAll(keepingCapacity: true)
                self.settings = settings
            }
            if let entry = images[key] {
                lock.unlock()
                return entry.image
            }
            lock.unlock()

            let drawingContext = DrawingContext(size: NSSize(width: key.width, height: key.height), scale: scale, clear: true)
            drawingContext.withFlippedContext(vertical: true) { context in
                let rect = CGRect(origin: .zero, size: drawingContext.size)
                context.interpolationQuality = .high
                context.clear(rect)
                context.clip(to: rect, mask: bitmap)
                context.setFillColor(key.color)
                context.fill(rect)
            }
            let image = drawingContext.generateImage()!
            guard bitmap.bytesPerRow * bitmap.height + image.bytesPerRow * image.height <= 16 * 1024 else { return image }
            lock.lock()
            defer { lock.unlock() }
            guard self.settings == settings, DeviceGraphicsContextSettings.shared == settings else { return image }
            if let entry = images[key] { return entry.image }
            if order.count == 16 {
                images.removeValue(forKey: order.removeFirst())
            }
            images[key] = Entry(source: bitmap, image: image)
            order.append(key)
            return image
        }
    }

    var blockQuotes: [TextViewBlockQuote] = [] {
        didSet {
            setNeedsDisplay()
        }
    }
    override func draw(in ctx: CGContext) {
        for blockQuote in blockQuotes {
            let radius: CGFloat = 3.0
            let lineWidth: CGFloat = 3.0


            let blockFrame = blockQuote.frame
            let blockColor = blockQuote.isCode ? blockQuote.colors.tertiary ?? blockQuote.colors.main : blockQuote.colors.main
            let tintColor = blockQuote.colors.main
            let secondaryTintColor = blockQuote.colors.secondary
            let tertiaryTintColor = blockQuote.colors.tertiary


            var bg = blockColor
            if blockQuote.isCode {
                bg = bg.darker(amount: 0.5).withAlphaComponent(0.5)
            } else {
                bg = bg.withAlphaComponent(0.1)
            }
            ctx.setFillColor(bg.cgColor)
            ctx.addPath(CGPath(roundedRect: blockFrame, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.fillPath()

            ctx.setFillColor(tintColor.cgColor)

            if !blockQuote.isCode {
                let iconSize = quoteIcon.backingSize
                let quoteRect = CGRect(origin: CGPoint(x: blockFrame.maxX - 4.0 - iconSize.width, y: blockFrame.minY + 4.0), size: iconSize)
                ctx.saveGState()
                ctx.translateBy(x: quoteRect.midX, y: quoteRect.midY)
                ctx.scaleBy(x: 1.0, y: -1.0)
                ctx.translateBy(x: -quoteRect.midX, y: -quoteRect.midY)
                ctx.clip(to: quoteRect, mask: quoteIcon)
                ctx.fill(quoteRect)
                ctx.restoreGState()
                ctx.resetClip()
            }


            drawBlockQuoteLine(ctx: ctx, blockFrame: blockFrame, radius: radius, lineWidth: lineWidth, tintColor: tintColor, secondaryTintColor: secondaryTintColor, tertiaryTintColor: tertiaryTintColor)

            if let header = blockQuote.header {
                let headerHeight = blockQuote.headerInset + 2
                ctx.setFillColor(blockQuote.colors.main.withAlphaComponent(0.2).cgColor)
                let rect = NSMakeRect(blockFrame.minX, blockFrame.minY, blockFrame.width, headerHeight)
                ctx.drawRoundedRect(rect: rect, topLeftRadius: radius, topRightRadius: radius)
                header.1.draw(CGRect(x: blockFrame.minX + 8, y: blockFrame.minY + (headerHeight - header.0.size.height) / 2 - 1, width: header.0.size.width, height: header.0.size.height), in: ctx, backingScaleFactor: System.backingScale, backgroundColor: .clear)
                let image = CopyIconCache.shared.image(TelegramThemeHooks.shared.image(.iconCopyCode), color: blockQuote.colors.main, scale: System.backingScale)
                ctx.draw(image, in: CGRect(origin: NSMakePoint(blockFrame.width - image.backingSize.width - 3, blockFrame.minY + (headerHeight - image.backingSize.height) / 2), size: image.backingSize))
            }
        }
    }
}

final class FoldingQuoteMaskCache {
    static let shared = FoldingQuoteMaskCache()

    struct Key: Hashable {
        let width: CGFloat
        let height: CGFloat
        let y: CGFloat
        let scale: CGFloat
    }

    let lock = NSLock()
    let maximumCount: Int
    let maximumBytes: Int
    var settings: DeviceGraphicsContextSettings?
    var images: [Key: CGImage] = [:]
    var order: [Key] = []
    var retainedBytes = 0

    init(maximumCount: Int = 32, maximumBytes: Int = 2 * 1024 * 1024) {
        self.maximumCount = maximumCount
        self.maximumBytes = maximumBytes
    }

    func image(size: NSSize, y: CGFloat, scale: CGFloat) -> CGImage? {
        let key = Key(width: size.width, height: size.height, y: y, scale: scale)
        let settings = DeviceGraphicsContextSettings.shared
        lock.lock()
        if self.settings != settings {
            images.removeAll(keepingCapacity: true)
            order.removeAll(keepingCapacity: true)
            retainedBytes = 0
            self.settings = settings
        }
        if let image = images[key] {
            lock.unlock()
            return image
        }
        lock.unlock()

        guard let image = renderFoldingQuoteMask(size: size, y: y, scale: scale) else { return nil }
        let cost = image.bytesPerRow * image.height
        guard maximumCount > 0, cost <= maximumBytes else { return image }

        lock.lock()
        defer { lock.unlock() }
        guard self.settings == settings, DeviceGraphicsContextSettings.shared == settings else { return image }
        if let existing = images[key] { return existing }
        while !order.isEmpty && (order.count >= maximumCount || retainedBytes > maximumBytes - cost) {
            let removed = order.removeFirst()
            if let previous = images.removeValue(forKey: removed) {
                retainedBytes -= previous.bytesPerRow * previous.height
            }
        }
        images[key] = image
        order.append(key)
        retainedBytes += cost
        return image
    }
}

private func generateMaskImage(size: NSSize, y: CGFloat) -> CGImage? {
    return FoldingQuoteMaskCache.shared.image(size: size, y: y, scale: System.backingScale)
}

private func renderFoldingQuoteMask(size: NSSize, y: CGFloat, scale: CGFloat) -> CGImage? {
    return generateImage(size, scale: scale, rotatedContext: { size, context in
        context.clear(CGRect(origin: .zero, size: size))
        
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        
        var locations: [CGFloat] = [0.0, 0.7, 1.0]
        let colors: [CGColor] = [NSColor.white.cgColor, NSColor.white.withAlphaComponent(0.0).cgColor, NSColor.white.withAlphaComponent(0.0).cgColor]
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: &locations)!
        
        context.setBlendMode(.copy)
        context.clip(to: CGRect(origin: CGPoint(x: 0, y: y), size: CGSize(width: size.width, height: size.height)))
        context.drawLinearGradient(gradient, start: CGPoint(x: size.width - size.width / 4, y: 0.0), end: CGPoint(x: size.width, y: 0.0), options: CGGradientDrawingOptions())
    })
}


class FoldingTextLayout {
    
    struct ViewLayout {
        let text: TextViewLayout
        let arrowDown: CGImage?
        let arrowUp: CGImage?
        let mask: CGImage?
        let isRevealed: Bool
        let collapsable: Bool
        let size: NSSize
        func updated(width: CGFloat, revealed: Bool, collapsable: Bool, isBigEmoji: Bool) -> ViewLayout {
            text.measure(width: width, isBigEmoji: isBigEmoji)
            
            let isRevealed = revealed || text.blockQuotes.isEmpty || text.lines.count <= 3 || !collapsable
            
            let size: NSSize
            if isRevealed {
                size = text.layoutSize
            } else {
                size = NSMakeSize(text.layoutSize.width, text.lines[1].frame.maxY + 8)
            }
            
            let arrowDown: CGImage?
            let arrowUp: CGImage?
            
            if text.hasBlockQuotes && canReveal {
                let mainColor = text.blockQuotes[0].colors.main
                
                let generateArrow:(NSSize, CGContext)->Void = { size, context in
                    context.clear(CGRect(origin: CGPoint(), size: size))
                    context.setStrokeColor(mainColor.cgColor)
                    context.setLineWidth(1.5)
                    context.setLineCap(.round)
                    context.setLineJoin(.round)
                    context.beginPath()
                    context.move(to: CGPoint(x: 1.0, y: 1.0))
                    context.addLine(to: CGPoint(x: size.width / 2.0, y: size.height - 2.0))
                    context.addLine(to: CGPoint(x: size.width - 1.0, y: 1.0))
                    context.strokePath()
                }
                
                arrowDown = self.arrowDown ?? generateImage(CGSize(width: 10, height: 7), rotatedContext: generateArrow)
                arrowUp = self.arrowUp ?? generateImage(CGSize(width: 10, height: 7), contextGenerator: generateArrow)
            } else {
                arrowDown = nil
                arrowUp = nil
            }
            
            
            if text.hasBlockQuotes && !isRevealed {
                return .init(text: text, arrowDown: arrowDown, arrowUp: arrowUp, mask: generateMaskImage(size: NSMakeSize(size.width, size.height - 5), y: text.lines[0].frame.maxY + 2), isRevealed: isRevealed, collapsable: collapsable, size: size)
            } else {
                return .init(text: text, arrowDown: arrowDown, arrowUp: arrowUp, mask: nil, isRevealed: isRevealed, collapsable: collapsable, size: size)
            }
        }
        
        var layoutSize: NSSize {
            return self.text.layoutSize
        }
        
        var canReveal: Bool {
            return collapsable && !self.text.blockQuotes.isEmpty && self.text.lines.count > 3
        }
        
        func makeImageBlock(backgroundColor: NSColor) {
            self.text.maskBlockImage = self.text.generateBlock(backgroundColor: backgroundColor)
        }
    }
    
    final class StreamingState {
        var previousString: String = ""
        var fromGlyphCount: Int = 0
        var toGlyphCount: Int = 0
        var currentGlyphCount: Int = 0
        var startTime: CFTimeInterval = 0
        var maxVisibleHeight: CGFloat = 0
    }

    var blocks:[ViewLayout]
    let blockRanges: [NSRange]
    var revealed: Set<Int>
    let context: any AccountContextProtocol
    let attributedString: NSAttributedString

    let appendingAnimation: Bool
    let streamingState: StreamingState

    private var width: CGFloat = 0

    var string: String {
        return attributedString.string
    }

    init(attributedString: NSAttributedString, blocks: [TextViewLayout], blockRanges: [NSRange], context: any AccountContextProtocol, revealed: Set<Int>, appendingAnimation: Bool = false, streamingState: StreamingState? = nil) {
        self.context = context
        self.attributedString = attributedString
        self.blocks = blocks.enumerated().map {
            ViewLayout(text: $0.element, arrowDown: nil, arrowUp: nil, mask: nil, isRevealed: revealed.contains($0.offset), collapsable: $0.element.blockCollapsable, size: .zero)
        }
        self.blockRanges = blockRanges
        self.revealed = revealed
        self.appendingAnimation = appendingAnimation
        self.streamingState = streamingState ?? StreamingState()
    }
    
    func toggle(_ index: Int) {
        if revealed.contains(index) {
            revealed.remove(index)
        } else {
            revealed.insert(index)
        }
        self.measure(width: self.width)
    }
    
    func applyRanges(_ ranges: [(NSRange, Int)]) {
        for range in ranges {
            if blocks.count > range.1, let clamped = blocks[range.1].text.attributedString.range.intersection(range.0) {
                self.blocks[range.1].text.selectedRange.range = clamped
            }
        }
    }
    
    func set(_ interactions: TextViewInteractions) {
        for block in blocks {
            block.text.interactions = interactions
        }
    }
    
    var lastLineIsRtl: Bool {
        return blocks.last?.text.lastLineIsRtl ?? false
    }
    
    var lastLineIsBlock: Bool {
        return blocks.last?.text.lastLineIsBlock ?? false
    }
    
    var linesCount: Int {
        return blocks.reduce(0, { $0 + $1.text.lines.count })
    }
    
    var lastLine: TextViewLine? {
        return blocks.last?.text.lines.last
    }
    
    var hasBlockQuotes: Bool {
        return blocks.contains(where: { $0.text.hasBlockQuotes })
    }
    
    var lastLineIsQuote: Bool {
        return blocks.last?.text.lastLineIsQuote ?? false
    }
    
    func makeImageBlock(backgroundColor: NSColor) {
        for i in 0 ..< blocks.count {
            blocks[i].makeImageBlock(backgroundColor: backgroundColor)
        }
    }
    
    var hasSelectedText: Bool {
        return blocks.contains(where: { $0.text.selectedRange.hasSelectText })
    }
    
    func rect(for text: String, range: NSRange? = nil) -> NSRect? {
        if let range, range.location >= 0, range.location != NSNotFound, range.length >= 0, range.location <= attributedString.length, range.length <= attributedString.length - range.location, attributedString.string.nsstring.substring(with: range) == text {
            var y: CGFloat = 0
            for (block, blockRange) in zip(blocks, blockRanges) {
                if let intersection = blockRange.intersection(range) {
                    let localRange = NSRange(location: intersection.location - blockRange.location, length: intersection.length)
                    if let rect = block.text.rects(localRange).first?.0 {
                        return rect.offsetBy(dx: 0, dy: y)
                    }
                }
                y += block.isRevealed ? block.layoutSize.height : block.size.height
            }
        }

        for block in blocks {
            let range = block.text.attributedString.string.nsstring.range(of: text)
            if range.location != NSNotFound {
                return block.text.rects(range).first?.0
            }
        }
        return nil
    }
    
    var merged: TextViewLayout {
        let lines = self.blocks.reduce([], {
            $0 + $1.text.lines
        })
        var range: NSRange = NSMakeRange(NSNotFound, 0)
        
        let attributedString = NSMutableAttributedString()
        
        var offset: Int = 0
        for block in blocks {
            let current = block.text.selectedRange.range
            if current.location != NSNotFound {
                if range.location == NSNotFound {
                    range.location = offset + current.location
                }
                range.length += current.length
            }
            offset += block.text.string.length
            attributedString.append(block.text.attributedString)
        }
        let merged = TextViewLayout(attributedString)
        merged.lines = lines
        merged.selectedRange.range = range

        return merged
    }

    var size: NSSize {
        var size: NSSize = .zero
        for block in blocks {
            if block.isRevealed {
                size.height += block.layoutSize.height
            } else {
                size.height += block.size.height
            }
            size.width = max(block.layoutSize.width, size.width)
        }
        
        if appendingAnimation, let last = blocks.last?.text.lines.last {
            let animSize = NSMakeSize(18, 18)
            if last.frame.maxX + animSize.width > size.width {
                if blocks.count == 1, blocks[0].text.lines.count == 1 {
                    size.width += animSize.width
                } else {
                    size.height += animSize.height
                }
            }
        }
        return size
    }

    var visibleSize: NSSize {
        guard appendingAnimation, streamingState.currentGlyphCount < streamingState.toGlyphCount else {
            return size
        }
        var remaining = streamingState.currentGlyphCount
        var visibleHeight: CGFloat = 0

        for block in blocks {
            var blockLastVisibleMaxY: CGFloat = 0
            var blockFullyVisible = true

            for line in block.text.lines {
                let lineGlyphs = (CTLineGetGlyphRuns(line.line) as NSArray).reduce(0) { sum, run in
                    sum + CTRunGetGlyphCount(run as! CTRun)
                }
                if remaining > 0 {
                    blockLastVisibleMaxY = line.frame.minY + line.frame.height
                }
                remaining -= lineGlyphs
                if remaining <= 0 {
                    blockFullyVisible = false
                    break
                }
            }

            if blockFullyVisible {
                let blockHeight = block.isRevealed ? block.layoutSize.height : block.size.height
                visibleHeight += blockHeight
            } else {
                visibleHeight += blockLastVisibleMaxY
                break
            }
        }


        let clampedHeight = min(size.height, max(visibleHeight, blocks.first?.text.lines.first?.frame.height ?? 0))
        streamingState.maxVisibleHeight = max(streamingState.maxVisibleHeight, clampedHeight)
        let result = NSMakeSize(size.width, min(size.height, streamingState.maxVisibleHeight))
        return result
    }

    func measure(width: CGFloat, isBigEmoji: Bool = false) {
        self.width = width
        for i in 0 ..< blocks.count {
            blocks[i] = blocks[i].updated(width: width, revealed: self.revealed.contains(i), collapsable: blocks[i].collapsable, isBigEmoji: isBigEmoji)
        }
    }

    func updateStreamingStateIfNeeded() {
        guard appendingAnimation else { return }
        let currentString = string

        let totalGlyphs = blocks.reduce(0) { sum, block in
            sum + block.text.lines.reduce(0) { lineSum, line in
                lineSum + (CTLineGetGlyphRuns(line.line) as NSArray).reduce(0) { runSum, run in
                    runSum + CTRunGetGlyphCount(run as! CTRun)
                }
            }
        }
        let stringChanged = currentString != streamingState.previousString
        guard totalGlyphs > streamingState.toGlyphCount || (stringChanged && totalGlyphs > 0) else { return }
        streamingState.fromGlyphCount = streamingState.currentGlyphCount
        streamingState.toGlyphCount = max(totalGlyphs, streamingState.currentGlyphCount + 1)
        streamingState.startTime = CACurrentMediaTime()
        streamingState.previousString = currentString
    }
    
    
    static func breakString(_ string: NSAttributedString) -> [NSRange] {

        var results = [NSRange]()
        let length = string.length
        let text = string.string as NSString

        var rangeStart = 0
        var insideBlockquote = false

        string.enumerateAttribute(TextInputAttributes.quote, in: NSRange(location: 0, length: length), options: []) { (quote, range, _) in
            if quote != nil {
                if !insideBlockquote {
                    if rangeStart < range.location {
                        var textRange = NSRange(location: rangeStart, length: range.location - rangeStart)
                        if text.character(at: textRange.location) == 0x0A {
                            textRange = NSRange(location: textRange.location + 1, length: textRange.length - 1)
                        }
                        if textRange.length > 0 {
                            results.append(textRange)
                        }
                    }
                    rangeStart = range.location
                    insideBlockquote = true
                }
            } else {
                if insideBlockquote {
                    let blockquoteRange = NSRange(location: rangeStart, length: range.location - rangeStart)
                    if blockquoteRange.length > 0 {
                        results.append(blockquoteRange)
                    }
                    rangeStart = range.location
                    insideBlockquote = false
                }
            }
        }

        if rangeStart < length {
            var finalRange = NSRange(location: rangeStart, length: length - rangeStart)
            if text.character(at: finalRange.location) == 0x0A {
                finalRange = NSRange(location: finalRange.location + 1, length: finalRange.length - 1)
            }
            if finalRange.length > 0 {
                results.append(finalRange)
            }
        }

        return results
    }

    static func make(_ string: NSAttributedString, context: any AccountContextProtocol, revealed: Set<Int>, takeLayout:@escaping(NSAttributedString)->TextViewLayout, appendingAnimation: Bool = false, streamingState: StreamingState? = nil) -> FoldingTextLayout {
        let blockRanges = FoldingTextLayout.breakString(string)
        return FoldingTextLayout(attributedString: string, blocks: blockRanges.map { takeLayout(string.attributedSubstring(from: $0)) }, blockRanges: blockRanges, context: context, revealed: revealed, appendingAnimation: appendingAnimation, streamingState: streamingState)
    }
}

private final class FoldingInlineStickers {
    private var inlineStickerItemViews: [InlineStickerItemLayer.Key: SimpleLayer] = [:]
    var isEmpty: Bool { inlineStickerItemViews.isEmpty }

    func resetForContentChange(previous: TextViewLayout?, next: TextViewLayout?) {
        guard !inlineStickerItemViews.isEmpty else { return }
        func requiresRestart(_ layout: TextViewLayout?) -> Bool {
            return layout?.embeddedItems.contains { item in
                guard let sticker = item.value as? InlineStickerItem else { return false }
                if case .avatar = sticker.source { return true }
                return (sticker.playPolicy ?? .loop) != .loop
            } ?? false
        }
        if requiresRestart(previous) || requiresRestart(next) {
            for layer in inlineStickerItemViews.values { layer.removeFromSuperlayer() }
            inlineStickerItemViews.removeAll(keepingCapacity: true)
        }
    }

    func update(textView: TextView, context: any AccountContextProtocol, textLayout: TextViewLayout) {
        guard !textLayout.embeddedItems.isEmpty || !inlineStickerItemViews.isEmpty else { return }
        var validIds = InlineStickerKeyCollection()
        var index: Int = textView.hashValue
        
        let textColor: NSColor
        if textLayout.attributedString.length > 0 {
            var range:NSRange = NSMakeRange(NSNotFound, 0)
            let attrs = textLayout.attributedString.attributes(at: max(0, textLayout.attributedString.length - 1), effectiveRange: &range)
            textColor = attrs[.foregroundColor] as? NSColor ?? theme.colors.text
        } else {
            textColor = theme.colors.text
        }

        for item in textLayout.embeddedItems {
            if let stickerItem = item.value as? InlineStickerItem, item.rect.width > 10 {
                if case let .attribute(emoji) = stickerItem.source {
                    
                    let id = InlineStickerItemLayer.Key(id: emoji.fileId, index: index, color: emoji.color ?? textColor)
                    validIds.append(id)
                    
                    let rect = item.rect.insetBy(dx: 0, dy: 0)
                    
                    let view: InlineStickerItemLayer
                    if let current = self.inlineStickerItemViews[id] as? InlineStickerItemLayer, current.frame.size == rect.size && current.textColor == id.color {
                        view = current
                    } else {
                        self.inlineStickerItemViews[id]?.removeFromSuperlayer()
                        view = InlineStickerItemLayer(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: emoji, size: rect.size, playPolicy: stickerItem.playPolicy ?? .loop, textColor: textColor)
                        self.inlineStickerItemViews[id] = view
                        view.superview = textView
                        textView.addEmbeddedLayer(view)
                    }
                    index += 1
                    
                    view.frame = rect
                } else if case let .avatar(peer) = stickerItem.source {
                    let id = InlineStickerItemLayer.Key(id: peer.id.toInt64(), index: index)
                    validIds.append(id)
                    let rect = NSMakeRect(item.rect.minX, item.rect.minY + 3, item.rect.width - 3, item.rect.width - 3)
                   
                    let view: any InputInlineAvatarLayer
                    if let current = self.inlineStickerItemViews[id] as? any InputInlineAvatarLayer {
                        view = current
                    } else {
                        self.inlineStickerItemViews[id]?.removeFromSuperlayer()
                        view = InputTextViewHooks.shared.makeInlineAvatarLayer(context, rect, peer)
                        self.inlineStickerItemViews[id] = view
                        textView.addEmbeddedLayer(view)
                    }
                    index += 1
                    view.frame = rect
               }
                
            }
        }
        
        var removeKeys: [InlineStickerItemLayer.Key] = []
        for (key, itemLayer) in self.inlineStickerItemViews {
            if !validIds.contains(key) {
                removeKeys.append(key)
                itemLayer.removeFromSuperlayer()
            }
        }
        for key in removeKeys {
            self.inlineStickerItemViews.removeValue(forKey: key)
        }
    }

    func updateAnimatableContent(window: NSWindow?, isLite: Bool) {
        updateInlineStickerPlayback(inlineStickerItemViews.values, window: window, isLite: isLite)
    }
}

private protocol FoldingBlockInteractionState: AnyObject {
    var ignoreNextClick: Bool { get set }
}

private final class PlainTextBlock: NSObject, FoldingBlockInteractionState {
    var ignoreNextClick = false
    let textView = TextView()
    private(set) var currentLayout: FoldingTextLayout.ViewLayout?
    private var isLite: Bool = false
    fileprivate let inlineStickers = FoldingInlineStickers()
    private var animatableContentObserver: AnimatableContentObserver?

    func update(_ layout: FoldingTextLayout.ViewLayout, context: any AccountContextProtocol, transition: ContainedViewLayoutTransition) {
        self.currentLayout = layout
        self.isLite = context.isLite(.emoji)
        textView.canDrawBlocks = !layout.canReveal
        textView.update(layout.text)
        textView.set(mask: nil)
        textView.setIsShimmering(true, animated: transition.isAnimated)
        inlineStickers.update(textView: textView, context: context, textLayout: layout.text)
        updateAnimatableContent()
    }

    func updateListeners() {
        guard !inlineStickers.isEmpty else {
            animatableContentObserver = nil
            return
        }
        if animatableContentObserver == nil { animatableContentObserver = AnimatableContentObserver() }
        animatableContentObserver?.update(for: textView, target: self, selector: #selector(updateAnimatableContent), options: [.contentBounds, .documentFrame, .ownFrame])
    }

    @objc func updateAnimatableContent() {
        inlineStickers.updateAnimatableContent(window: textView.window, isLite: isLite)
    }
}

private enum FoldingBlock {
    case wrapper(WrapperView)
    case plain(PlainTextBlock)

    var view: NSView {
        switch self {
        case let .wrapper(view):
            return view
        case let .plain(block):
            return block.textView
        }
    }

    var inlineStickers: FoldingInlineStickers {
        switch self {
        case let .wrapper(view): return view.inlineStickers
        case let .plain(block): return block.inlineStickers
        }
    }

    var hasActiveContentAnimation: Bool {
        if case let .wrapper(view) = self { return view.hasActiveContentAnimation }
        return false
    }

    var interactionState: any FoldingBlockInteractionState {
        switch self {
        case let .wrapper(view): return view
        case let .plain(block): return block
        }
    }

    var textView: TextView {
        switch self {
        case let .wrapper(view):
            return view.textView
        case let .plain(block):
            return block.textView
        }
    }

    var currentLayout: FoldingTextLayout.ViewLayout? {
        switch self {
        case let .wrapper(view):
            return view.currentLayout
        case let .plain(block):
            return block.currentLayout
        }
    }

    var isPlain: Bool {
        if case .plain = self {
            return true
        }
        return false
    }

    static func isPlain(_ layout: FoldingTextLayout.ViewLayout) -> Bool {
        return !layout.text.hasBlockQuotes && !layout.canReveal
    }

    static func make(isPlain: Bool) -> FoldingBlock {
        return isPlain ? .plain(PlainTextBlock()) : .wrapper(WrapperView(frame: .zero))
    }
}

private final class WrapperView : View, FoldingBlockInteractionState {
    var ignoreNextClick = false
    
    
    let textView = TextView()
    private let mask: SimpleShapeLayer = SimpleShapeLayer()
    private var textMask: SimpleLayer?
    private var blockLayer: FoldingTextQuoteLayer?
    private var arrow: SimpleLayer?
    
    
    var currentLayout: FoldingTextLayout.ViewLayout?
    
    var isLite: Bool = false
    
    fileprivate let inlineStickers = FoldingInlineStickers()

    
    var hasActiveContentAnimation: Bool {
        return mask.animationKeys()?.isEmpty == false || arrow?.animationKeys()?.isEmpty == false
    }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        self.layer?.mask = mask
    }
    
    func update(_ layout: FoldingTextLayout.ViewLayout, isRevealed: Bool, context: any AccountContextProtocol, transition: ContainedViewLayoutTransition) {
        
        let previousLayout = self.currentLayout
        
        self.currentLayout = layout
        
        let isRevealed = layout.isRevealed
        
        self.isLite = context.isLite(.emoji)
        
        textView.canDrawBlocks = !layout.canReveal

        self.textView.update(layout.text)
        
        let size = layout.size
 
        
        
        let path = CGMutablePath()
        
        if layout.canReveal {
            path.addRoundedRect(in: size.bounds, cornerWidth: min(size.width / 2, 4), cornerHeight: min(size.height / 2, 4))
        } else {
            path.addRoundedRect(in: size.bounds, cornerWidth: 0, cornerHeight: 0)
        }
        
        
        if transition.isAnimated {
            let animation = mask.makeAnimation(from: self.mask.path ?? CGMutablePath(), to: path, keyPath: "path", timingFunction: transition.timingFunction, duration: transition.duration)
            mask.add(animation, forKey: "path")
        }
        mask.path = path
        
        self.layer?.masksToBounds = layout.text.hasBlockQuotes
        self.layer?.mask = layout.text.hasBlockQuotes ? mask : nil


        if layout.canReveal {
            let current: FoldingTextQuoteLayer
            if let layer = self.blockLayer {
                current = layer
            } else {
                current = FoldingTextQuoteLayer(frame: size.bounds)
                self.layer?.addSublayer(current)
                self.blockLayer = current
            }
            current.blockQuotes = layout.text.blockQuotes
            transition.updateFrame(layer: current, frame: layout.layoutSize.bounds)
            current.mask = mask
        } else {
            if let layer = self.blockLayer {
                performSublayerRemoval(layer, animated: transition.isAnimated)
                self.blockLayer = nil
            }
        }
        
        if !isRevealed {
            let current: SimpleLayer
            if let layer = self.textMask {
                current = layer
            } else {
                current = .init(frame: size.bounds)
                self.textMask = current
            }
            current.contents = layout.mask
            current.contentsGravity = .bottom
            current.frame = size.bounds
            if transition.isAnimated {
                delay(transition.duration, closure: { [weak self] in
                    self?.textView.set(mask: self?.textMask)
                })
            } else {
                self.textView.set(mask: current)
            }
        } else {
            self.textMask = nil
            self.textView.set(mask: nil)
        }
        
        if layout.canReveal {
            let current: SimpleLayer
            if let layer = self.arrow {
                current = layer
            } else {
                let s = NSMakeSize(10, 7)
                current = SimpleLayer(frame: NSMakeRect(size.width - s.width - 5, size.height - s.height - 6, s.width, s.height))
                self.arrow = current
                self.layer?.addSublayer(current)
            }
            current.anchorPoint = NSMakePoint(0, 0)
            current.contents = layout.isRevealed ? layout.arrowUp : layout.arrowDown
            
            if previousLayout?.isRevealed != layout.isRevealed, transition.isAnimated {
                current.animateContents()
            }
        } else if let arrow = self.arrow {
            performSublayerRemoval(arrow, animated: transition.isAnimated)
            self.arrow = nil
        }
        
        self.textView.setIsShimmering(true, animated: transition.isAnimated)
        
        self.updateInlineStickers(context: context, textLayout: layout.text)
        self.updateListeners()
        self.updateAnimatableContent()
        
        transition.updateFrame(view: self, frame: CGRect(origin: self.frame.origin, size: size))
        self.updateLayout(size: size, transition: transition)
    }
    
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        if let arrow = arrow {
            transition.updateFrame(layer: arrow, frame: NSMakeRect(size.width - arrow.frame.width - 5, size.height - arrow.frame.height - 6, arrow.frame.width, arrow.frame.height))
        }
    }
    
    
    override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    
    func updateInlineStickers(context: any AccountContextProtocol, textLayout: TextViewLayout) {
        inlineStickers.update(textView: textView, context: context, textLayout: textLayout)
    }
    
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.updateListeners()
        self.updateAnimatableContent()
    }
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        self.updateListeners()
        self.updateAnimatableContent()
    }
    
    @objc func updateAnimatableContent() -> Void {
        inlineStickers.updateAnimatableContent(window: window, isLite: isLite)
    }
    private var animatableContentObserver: AnimatableContentObserver?

    private func updateListeners() {
        guard !inlineStickers.isEmpty else {
            animatableContentObserver = nil
            return
        }
        if animatableContentObserver == nil { animatableContentObserver = AnimatableContentObserver() }
        animatableContentObserver?.update(for: self, target: self, selector: #selector(updateAnimatableContent), options: [.contentBounds, .documentFrame, .ownFrame])
    }

}

class FoldingTextView : View {

    var revealBlockAtIndex:((Int)->Void)? = nil
    var streamingVisibleHeightChanged:(()->Void)?

    private var layouts: FoldingTextLayout?
    private var blocks: [FoldingBlock] = []

    private(set) var appendingAnimationView: LottiePlayerView?

    private var streamingTimer: ConstantDisplayLinkAnimator?
    private var lastStreamingVisibleLineCount: Int = 0

    var textSelectable: Bool = true {
        didSet {
            if textSelectable != oldValue { self.updateLayouts() }
        }
    }
    
    override var userInteractionEnabled: Bool {
        didSet {
            if userInteractionEnabled != oldValue { self.updateLayouts() }
        }
    }
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        layer?.masksToBounds = false
                
        self.revealBlockAtIndex = { [weak self] index in
            if let layout = self?.layouts {
                layout.toggle(index)
                self?.update(layout: layout, animated: true)
            }
        }
    }
    
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @discardableResult func updateForReusedContent(layout: FoldingTextLayout) -> Bool {
        guard let previous = layouts, previous.context === layout.context,
              !previous.appendingAnimation, !layout.appendingAnimation,
              !contextMenuOnScreen(), layer?.animationKeys()?.isEmpty != false,
              blocks.allSatisfy({
                  $0.textView.canReuseForContentChange && !$0.hasActiveContentAnimation
                      && $0.view.layer?.animationKeys()?.isEmpty != false
                      && $0.view.layer?.mask?.animationKeys()?.isEmpty != false
              }) else { return false }
        for (index, block) in blocks.enumerated() {
            guard block.textView.resetForContentChange() else { return false }
            block.inlineStickers.resetForContentChange(previous: block.currentLayout?.text, next: index < layout.blocks.count ? layout.blocks[index].text : nil)
        }
        update(layout: layout, animated: false)
        return true
    }

    func update(layout: FoldingTextLayout, animated: Bool, appendingAnimationView: LottiePlayerView? = nil) {
        self.layouts = layout

        if layout.appendingAnimation {
            computeStreamingState(layout: layout)
            applyStreamingGlyphCount()
        } else {
            stopStreamingTimer()
        }

        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate

        var blocks = self.blocks
        while blocks.count > layout.blocks.count {
            let block = blocks.removeLast()
            block.textView.removeAllHandlers()
            block.view.removeFromSuperview()
        }
        for (i, textLayout) in layout.blocks.enumerated() {
            let isPlain = FoldingBlock.isPlain(textLayout)
            if i < blocks.count {
                if blocks[i].isPlain != isPlain {
                    blocks[i].textView.removeAllHandlers()
                    blocks[i].view.removeFromSuperview()
                    blocks[i] = FoldingBlock.make(isPlain: isPlain)
                    configureActions(for: blocks[i], index: i)
                }
            } else {
                blocks.append(FoldingBlock.make(isPlain: isPlain))
                configureActions(for: blocks[i], index: i)
            }
        }
        self.blocks = blocks
        let currentSubviews = self.subviews
        if currentSubviews.count < blocks.count || zip(blocks, currentSubviews).contains(where: { $0.view !== $1 }) {
            let blockViews = blocks.map { $0.view }
            if currentSubviews.isEmpty {
                self.subviews = blockViews
            } else {
                let blockIds = Set(blockViews.map { ObjectIdentifier($0) })
                self.subviews = blockViews + currentSubviews.filter { !blockIds.contains(ObjectIdentifier($0)) }
            }
        }
        for (i, textLayout) in layout.blocks.enumerated() {
            let block = blocks[i]
            switch block {
            case let .wrapper(view):
                view.update(textLayout, isRevealed: layout.revealed.contains(i), context: layout.context, transition: transition)
            case let .plain(plain):
                plain.update(textLayout, context: layout.context, transition: transition)
                plain.updateListeners()
            }
            let textView = block.textView
            textView.userInteractionEnabled = userInteractionEnabled
            textView.isSelectable = textSelectable
            textView.sendDownAnyway = true
            block.interactionState.ignoreNextClick = false
        }
        
        if layout.appendingAnimation {
            
            let size = NSMakeSize(18, 18)
            
            let current: LottiePlayerView
            if let appendingAnimationView {
                if self.appendingAnimationView !== appendingAnimationView {
                    self.appendingAnimationView?.removeFromSuperview()
                }
                current = appendingAnimationView
                if let owner = current.superview as? FoldingTextView, owner !== self, owner.appendingAnimationView === current {
                    owner.appendingAnimationView = nil
                }
                self.appendingAnimationView = current
                if current.superview !== self { addSubview(current) }
            } else if let view = self.appendingAnimationView {
                current = view
            } else {
                current = LottiePlayerView()
                current.setFrameSize(size)
                self.appendingAnimationView = current
                addSubview(current)
                
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            let animation = LocalAnimatedSticker.voice_dots
            
            let color = layout.blocks.first?.text.attributedString.firstForegroundColor ?? theme.colors.text
            
            if let compressed = animation.data {
                let colors: [LottieColor] = [LottieColor(keyPath: "", color: color)]
                current.set(LottieAnimation(compressed: compressed, key: .init(key: .bundle("dots_\(animation.rawValue)"), size: size, colors: colors), playPolicy: .loop, colors: colors))
            }
            
        } else if let view = self.appendingAnimationView ?? appendingAnimationView {
            if let owner = view.superview as? FoldingTextView, owner.appendingAnimationView === view {
                owner.appendingAnimationView = nil
            }
            self.appendingAnimationView = nil
            performSubviewRemoval(view, animated: animated)
        }
        
        self.updateLayout(size: layout.size, transition: transition)
    }
    
    private func configureActions(for block: FoldingBlock, index: Int) {
        let textView = block.textView
        textView.removeAllHandlers()
        textView.set(handler: { [weak self] control in
            guard let self, self.blocks.indices.contains(index), self.blocks[index].textView === control else { return }
            self.blocks[index].interactionState.ignoreNextClick = self.blocks[index].textView.selectionWasCleared
        }, for: .Down)
        textView.set(handler: { [weak self] control in
            guard let self, self.blocks.indices.contains(index), self.blocks[index].textView === control else { return }
            if !self.hasSelectedText, !self.blocks[index].interactionState.ignoreNextClick {
                self.revealBlockAtIndex?(index)
            }
        }, for: .Click)
    }

    private func computeStreamingState(layout: FoldingTextLayout) {
        layout.updateStreamingStateIfNeeded()
        if layout.streamingState.currentGlyphCount < layout.streamingState.toGlyphCount {
            startStreamingTimer()
        }
    }

    private func startStreamingTimer() {
        if streamingTimer == nil {
            let animator = ConstantDisplayLinkAnimator(framesPerSecond: .max, update: { [weak self] _ in
                self?.tickStreaming()
            })
            animator.isPaused = false
            streamingTimer = animator
        }
    }

    private func stopStreamingTimer() {
        streamingTimer?.isPaused = true
        streamingTimer = nil
    }

    private func tickStreaming() {
        guard let layout = self.layouts, layout.appendingAnimation else {
            stopStreamingTimer()
            return
        }
        let state = layout.streamingState
        let elapsed = CACurrentMediaTime() - state.startTime
        let gap = Double(state.toGlyphCount - state.fromGlyphCount)
        let baseSpeed: Double = 120.0
        let speed = max(baseSpeed, gap / 1.5)
        let duration = max(0.05, gap / speed)
        let fraction = min(1.0, elapsed / duration)
        let prev = state.currentGlyphCount
        state.currentGlyphCount = Int(Double(state.fromGlyphCount) + fraction * Double(state.toGlyphCount - state.fromGlyphCount))

        if prev != state.currentGlyphCount {
            applyStreamingGlyphCount()
        }

        if fraction >= 1.0 {
            stopStreamingTimer()
        }
    }

    private func applyStreamingGlyphCount() {
        guard let layout = self.layouts else { return }
        let state = layout.streamingState

        var remaining = state.currentGlyphCount
        var lineGlyphCounts: [[Int]] = []
        var changedLayouts = Set<ObjectIdentifier>()
        for block in layout.blocks {
            let blockLineGlyphCounts = block.text.lines.map { line in
                (CTLineGetGlyphRuns(line.line) as NSArray).reduce(0) { runSum, run in
                    runSum + CTRunGetGlyphCount(run as! CTRun)
                }
            }
            lineGlyphCounts.append(blockLineGlyphCounts)
            let blockGlyphs = blockLineGlyphCounts.reduce(0, +)
            let maxGlyphDrawCount = max(0, min(blockGlyphs, remaining))
            if block.text.maxGlyphDrawCount != maxGlyphDrawCount {
                changedLayouts.insert(ObjectIdentifier(block.text))
            }
            block.text.maxGlyphDrawCount = maxGlyphDrawCount
            remaining -= blockGlyphs
        }

        var visibleLines = 0
        var counted = 0
        for blockLineGlyphCounts in lineGlyphCounts {
            for lineGlyphs in blockLineGlyphCounts {
                if counted < state.currentGlyphCount {
                    visibleLines += 1
                }
                counted += lineGlyphs
            }
        }
        if visibleLines != lastStreamingVisibleLineCount {
            lastStreamingVisibleLineCount = visibleLines
            streamingVisibleHeightChanged?()
        }

        for textView in textViews {
            if let textLayout = textView.textLayout, changedLayouts.contains(ObjectIdentifier(textLayout)) {
                textView.needsDisplay = true
            }
        }

        let isStreaming = state.currentGlyphCount < state.toGlyphCount
        appendingAnimationView?.isHidden = isStreaming
    }

    deinit {
        stopStreamingTimer()
    }

    var hasSelectedText: Bool {
        return self.layouts?.hasSelectedText ?? false
    }

    private func updateLayouts() {
        for subview in textViews {
            subview.userInteractionEnabled = userInteractionEnabled
            subview.isSelectable = textSelectable
        }
    }
    
    var textViews: [TextView] {
        return blocks.map { $0.textView }
    }
    
    var string: String? {
        return self.layouts?.string
    }
    
    var textLayouts: [TextViewLayout] {
        return self.layouts?.blocks.map { $0.text } ?? []
    }
    func highlight(text: String, color: NSColor, range: NSRange? = nil) {
        if let layouts, let range, range.location >= 0, range.location != NSNotFound, range.length >= 0, range.location <= layouts.attributedString.length, range.length <= layouts.attributedString.length - range.location, layouts.attributedString.string.nsstring.substring(with: range) == text {
            var highlighted = false
            for (textView, (block, blockRange)) in zip(textViews, zip(layouts.blocks, layouts.blockRanges)) {
                if let intersection = blockRange.intersection(range) {
                    let localRange = NSRange(location: intersection.location - blockRange.location, length: intersection.length)
                    let localText = block.text.attributedString.string.nsstring.substring(with: localRange)
                    textView.highlight(text: localText, color: color, range: localRange)
                    highlighted = true
                }
            }
            if highlighted {
                return
            }
        }
        for textView in textViews {
            textView.highlight(text: text, color: color)
        }
    }
    
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        var y: CGFloat = 0
        for view in subviews {
            transition.updateFrame(view: view, frame: CGRect(origin: NSPoint(x: 0, y: y), size: view.frame.size))
            y += view.frame.height
        }

        if let view = appendingAnimationView, let last = textViews.last?.textLayout?.lines.last {
            let x: CGFloat
            if last.frame.maxX + view.frame.width > size.width {
                x = -3
            } else {
                x = last.frame.maxX
            }
            transition.updateFrame(view: view, frame: CGRect(origin: CGPoint(x: x, y: size.height - view.frame.height + 1), size: view.frame.size))
        }
    }
    
    func clickInContent(point: NSPoint) -> Bool {
        for block in blocks {
            let view = block.view
            if view.frame.contains(point) {
                let point = view.convert(point, from: self)
                if let layout = block.currentLayout?.text {
                    let index = layout.findIndex(location: point)
                    return index >= 0 && point.x < layout.lines[index].frame.maxX
                }
            }
        }
        
        return false
    }
    
    
    override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updatePlainBlocksAnimatableContent()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updatePlainBlocksAnimatableContent()
    }

    private func updatePlainBlocksAnimatableContent() {
        for block in blocks {
            if case let .plain(plain) = block {
                plain.updateListeners()
                plain.updateAnimatableContent()
            }
        }
    }
    
}
func referenceSharedQuoteIcon() -> CGImage { quoteIcon }
