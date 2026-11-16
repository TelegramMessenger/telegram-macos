import Cocoa
import TGUIKit
func referenceMaskImage(size: NSSize, y: CGFloat, scale: CGFloat) -> CGImage? {
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

class ReferenceMaskFoldingTextLayout {
    
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
                return .init(text: text, arrowDown: arrowDown, arrowUp: arrowUp, mask: referenceMaskImage(size: NSMakeSize(size.width, size.height - 5), y: text.lines[0].frame.maxY + 2, scale: System.backingScale), isRevealed: isRevealed, collapsable: collapsable, size: size)
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

    static func make(_ string: NSAttributedString, context: any AccountContextProtocol, revealed: Set<Int>, takeLayout:@escaping(NSAttributedString)->TextViewLayout, appendingAnimation: Bool = false, streamingState: StreamingState? = nil) -> ReferenceMaskFoldingTextLayout {
        let blockRanges = ReferenceMaskFoldingTextLayout.breakString(string)
        return ReferenceMaskFoldingTextLayout(attributedString: string, blocks: blockRanges.map { takeLayout(string.attributedSubstring(from: $0)) }, blockRanges: blockRanges, context: context, revealed: revealed, appendingAnimation: appendingAnimation, streamingState: streamingState)
    }
}
