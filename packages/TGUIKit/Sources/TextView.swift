import Cocoa
import SwiftSignalKit
import ColorPalette

private func combineIntersectingRectangles(_ rectangles: [TextViewBlockQuote]) -> [TextViewBlockQuote] {
    
    if rectangles.isEmpty {
        return []
    } else if rectangles.count == 1 {
        return rectangles
    }
    var result: [TextViewBlockQuote] = []
    var big: TextViewBlockQuote = rectangles[0]
    
    var max_w: CGFloat = big.frame.width
    
    for i in 1 ..< rectangles.count {
        let current: TextViewBlockQuote = rectangles[i]
        if current.frame.intersects(big.frame) {
            big.frame = big.frame.union(current.frame)
            if i == rectangles.count - 1 {
                result.append(big)
            }
        } else {
            result.append(big)
            if i == rectangles.count - 1 {
                result.append(rectangles[i])
            } else {
                big = rectangles[i]
            }
        }
        max_w = max(max_w, current.frame.width)
    }

    for value in result {
        value.frame = CGRect(origin: value.frame.origin, size: NSMakeSize(max_w, value.frame.height))
    }
    
    return result
}






public struct TextInputAttributes {
    public static let bold = NSAttributedString.Key(rawValue: "Attribute__Bold")
    public static let italic = NSAttributedString.Key(rawValue: "Attribute__Italic")
    public static let monospace = NSAttributedString.Key(rawValue: "Attribute__Monospace")
    public static let strikethrough = NSAttributedString.Key(rawValue: "Attribute__Strikethrough")
    public static let underline = NSAttributedString.Key(rawValue: "Attribute__Underline")
    public static let textMention = NSAttributedString.Key(rawValue: "Attribute__TextMention")
    public static let textUrl = NSAttributedString.Key(rawValue: "Attribute__TextUrl")
    public static let spoiler = NSAttributedString.Key(rawValue: "Attribute__Spoiler")
    public static let customEmoji = NSAttributedString.Key(rawValue: "Attribute__CustomEmoji")
    public static let code = NSAttributedString.Key(rawValue: "Attribute__Code")
    public static let quote = NSAttributedString.Key(rawValue: "Attribute__Blockquote")
    public static let formattedDate = NSAttributedString.Key(rawValue: "Attribute__FormattedDate")

    public static let embedded = NSAttributedString.Key(rawValue: "Attribute__EmbeddedItem")

    public static let allAttributes = [TextInputAttributes.bold, TextInputAttributes.italic, TextInputAttributes.monospace, TextInputAttributes.strikethrough, TextInputAttributes.underline, TextInputAttributes.textMention, TextInputAttributes.textUrl, TextInputAttributes.spoiler, TextInputAttributes.customEmoji, TextInputAttributes.code, TextInputAttributes.quote, TextInputAttributes.formattedDate]
}

public final class TextViewFormattedDateData {
    public let text: String
    public let date: Int32
    public let isRelative: Bool
    public let contextMenuItems: () -> [ContextMenuItem]

    public init(text: String, date: Int32, isRelative: Bool = false, contextMenuItems: @escaping () -> [ContextMenuItem] = { [] }) {
        self.text = text
        self.date = date
        self.isRelative = isRelative
        self.contextMenuItems = contextMenuItems
    }
}



private var codeCopyIconCache: [NSColor: CGImage] = [:]
private var codeCopyIconCacheScale: CGFloat = 0
private let codeCopyIconCacheLock = NSLock()

private func codeCopyIcon(_ color: NSColor) -> CGImage? {
    guard color.type == .componentBased else {
        return NSImage(named: "Icon_CopyCode")?.precomposed(color, flipVertical: true)
    }
    let scale = System.backingScale
    codeCopyIconCacheLock.lock()
    defer {
        codeCopyIconCacheLock.unlock()
    }
    if codeCopyIconCacheScale != scale {
        codeCopyIconCache.removeAll()
        codeCopyIconCacheScale = scale
    }
    if let image = codeCopyIconCache[color] {
        return image
    }
    guard let image = NSImage(named: "Icon_CopyCode")?.precomposed(color, flipVertical: true) else {
        return nil
    }
    if codeCopyIconCache.count >= 16 {
        codeCopyIconCache.removeAll()
    }
    codeCopyIconCache[color] = image
    return image
}

private func fillBlockBackgroundOnClearedArea(_ ctx: CGContext, frame: CGRect, radius: CGFloat, color: CGColor) {
    let ctm = ctx.ctm
    let deviceFrame = frame.applying(ctm)
    let scale = max(abs(ctm.a), abs(ctm.d))
    let inset = radius * scale + 1
    let innerMinX = ceil(deviceFrame.minX + inset)
    let innerMinY = ceil(deviceFrame.minY + inset)
    let innerMaxX = floor(deviceFrame.maxX - inset)
    let innerMaxY = floor(deviceFrame.maxY - inset)
    let path = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.setFillColor(color)
    guard ctm.b == 0, ctm.c == 0, ctm.a == ctm.a.rounded(), ctm.d == ctm.d.rounded(), innerMaxX > innerMinX, innerMaxY > innerMinY else {
        ctx.addPath(path)
        ctx.fillPath()
        return
    }
    let inner = CGRect(x: innerMinX, y: innerMinY, width: innerMaxX - innerMinX, height: innerMaxY - innerMinY)
    let outer = CGRect(x: floor(deviceFrame.minX), y: floor(deviceFrame.minY), width: ceil(deviceFrame.maxX) - floor(deviceFrame.minX), height: ceil(deviceFrame.maxY) - floor(deviceFrame.minY))
    let inverse = ctm.inverted()
    let strips = [
        CGRect(x: outer.minX, y: outer.minY, width: outer.width, height: inner.minY - outer.minY),
        CGRect(x: outer.minX, y: inner.maxY, width: outer.width, height: outer.maxY - inner.maxY),
        CGRect(x: outer.minX, y: inner.minY, width: inner.minX - outer.minX, height: inner.height),
        CGRect(x: inner.maxX, y: inner.minY, width: outer.maxX - inner.maxX, height: inner.height)
    ]
    ctx.saveGState()
    ctx.setBlendMode(.copy)
    ctx.fill(inner.applying(inverse))
    ctx.restoreGState()
    for strip in strips where strip.width > 0 && strip.height > 0 {
        ctx.saveGState()
        ctx.clip(to: strip.applying(inverse))
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()
    }
}

private let quoteIcon: CGImage = {
    return NSImage(named: "Icon_Quote")!.precomposed(flipVertical: false)
}()


public enum LinkType {
    case plain
    case email
    case username
    case hashtag
    case command
    case stickerPack
    case emojiPack
    case inviteLink
    case code
}

public func isValidEmail(_ email: String) -> Bool {
    // Create a regular expression pattern to match an email address
    let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
    
    // Create a regular expression object from the pattern
    guard let regex = try? NSRegularExpression(pattern: emailRegex) else {
        return false
    }
    if let url = URL(string: email) {
        if url.host != nil || url.scheme != nil {
            return false
        }
    }
    
    // Check if the email string matches the pattern
    let range = NSRange(location: 0, length: email.utf16.count)
    return regex.firstMatch(in: email, options: [], range: range) != nil
}

private enum CornerType {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
}

public extension NSAttributedString.Key {
    static let hexColorMark = NSAttributedString.Key("TextViewHexColorMarkAttribute")
    static let hexColorMarkDimensions = NSAttributedString.Key("TextViewHexColorMarkAttributeDimensions")
}


public final class TextViewBlockQuote {
    public var range: NSRange
    public var frame: CGRect
    public var colors: PeerNameColors.Colors
    public var isCode: Bool
    public var header: (TextNodeLayout, TextNode)?
    init(frame: CGRect, range: NSRange, colors: PeerNameColors.Colors, isCode: Bool, header: (TextNodeLayout, TextNode)?) {
        self.frame = frame
        self.range = range
        self.colors = colors
        self.isCode = isCode
        self.header = header
    }
    
    public var headerInset: CGFloat {
        if header != nil {
            return 20
        } else {
            return 0
        }
    }
}


public final class TextViewBlockQuoteData: NSObject {
    public let id: Int
    public let colors: PeerNameColors.Colors
    public let space: CGFloat
    public let isCode: Bool
    public let header: (TextNodeLayout, TextNode)?
    public let collapsable: Bool
    public init(id: Int, colors: PeerNameColors.Colors, isCode: Bool = false, space: CGFloat = 4, header: (TextNodeLayout, TextNode)? = nil, collapsable: Bool = false) {
        self.id = id
        self.colors = colors
        self.isCode = isCode
        self.space = space
        self.header = header
        self.collapsable = collapsable
        super.init()
    }
    
    var headerInset: CGFloat {
        if header != nil {
            return 20
        } else {
            return 0
        }
    }
    
    var minimumHeaderSize: CGFloat {
        if let header = header {
            return header.0.size.width
        } else {
            return 0
        }
    }

    
    override public func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? TextViewBlockQuoteData else {
            return false
        }
        if self.id != other.id {
            return false
        }
        if self.colors != other.colors {
            return false
        }
        if self.isCode != other.isCode {
            return false
        }
        if self.space != other.space {
            return false
        }
        if self.collapsable != other.collapsable {
            return false
        }
        switch (self.header, other.header) {
        case (nil, nil):
            break
        case let (lhs?, rhs?):
            if lhs.0 !== rhs.0 || lhs.1 !== rhs.1 { return false }
        default:
            return false
        }
        return true
    }

    public override var hash: Int {
        var hasher = Hasher()
        hasher.combine(id)
        hasher.combine(colors.main)
        hasher.combine(colors.secondary)
        hasher.combine(colors.tertiary)
        hasher.combine(space)
        hasher.combine(isCode)
        hasher.combine(collapsable)
        if let header {
            hasher.combine(ObjectIdentifier(header.0))
            hasher.combine(ObjectIdentifier(header.1))
        }
        return hasher.finalize()
    }
}


private final class TextViewEmbeddedItem {
    let range: NSRange
    let frame: CGRect
    let item: AnyHashable
    
    init(range: NSRange, frame: CGRect, item: AnyHashable) {
        self.range = range
        self.frame = frame
        self.item = item
    }
}



private func drawFullCorner(context: CGContext, color: NSColor, at point: CGPoint, type: CornerType, radius: CGFloat) {
    context.setFillColor(color.cgColor)
    switch type {
    case .topLeft:
        context.clear(CGRect(origin: point, size: CGSize(width: radius, height: radius)))
        context.fillEllipse(in: CGRect(origin: point, size: CGSize(width: radius * 2.0, height: radius * 2.0)))
    case .topRight:
        context.clear(CGRect(origin: CGPoint(x: point.x - radius, y: point.y), size: CGSize(width: radius, height: radius)))
        context.fillEllipse(in: CGRect(origin: CGPoint(x: point.x - radius * 2.0, y: point.y), size: CGSize(width: radius * 2.0, height: radius * 2.0)))
    case .bottomLeft:
        context.clear(CGRect(origin: CGPoint(x: point.x, y: point.y - radius), size: CGSize(width: radius, height: radius)))
        context.fillEllipse(in: CGRect(origin: CGPoint(x: point.x, y: point.y - radius * 2.0), size: CGSize(width: radius * 2.0, height: radius * 2.0)))
    case .bottomRight:
        context.clear(CGRect(origin: CGPoint(x: point.x - radius, y: point.y - radius), size: CGSize(width: radius, height: radius)))
        context.fillEllipse(in: CGRect(origin: CGPoint(x: point.x - radius * 2.0, y: point.y - radius * 2.0), size: CGSize(width: radius * 2.0, height: radius * 2.0)))
    }
}

private func drawConnectingCorner(context: CGContext, color: NSColor, at point: CGPoint, type: CornerType, radius: CGFloat) {
    context.setFillColor(color.cgColor)
    switch type {
    case .topLeft:
        context.fill(CGRect(origin: CGPoint(x: point.x - radius, y: point.y), size: CGSize(width: radius, height: radius)))
        context.setFillColor(NSColor.clear.cgColor)
        context.fillEllipse(in: CGRect(origin: CGPoint(x: point.x - radius * 2.0, y: point.y), size: CGSize(width: radius * 2.0, height: radius * 2.0)))
    case .topRight:
        context.fill(CGRect(origin: CGPoint(x: point.x, y: point.y), size: CGSize(width: radius, height: radius)))
        context.setFillColor(NSColor.clear.cgColor)
        context.fillEllipse(in: CGRect(origin: CGPoint(x: point.x, y: point.y), size: CGSize(width: radius * 2.0, height: radius * 2.0)))
    case .bottomLeft:
        context.fill(CGRect(origin: CGPoint(x: point.x - radius, y: point.y - radius), size: CGSize(width: radius, height: radius)))
        context.setFillColor(NSColor.clear.cgColor)
        context.fillEllipse(in: CGRect(origin: CGPoint(x: point.x - radius * 2.0, y: point.y - radius * 2.0), size: CGSize(width: radius * 2.0, height: radius * 2.0)))
    case .bottomRight:
        context.fill(CGRect(origin: CGPoint(x: point.x, y: point.y - radius), size: CGSize(width: radius, height: radius)))
        context.setFillColor(NSColor.clear.cgColor)
        context.fillEllipse(in: CGRect(origin: CGPoint(x: point.x, y: point.y - radius * 2.0), size: CGSize(width: radius * 2.0, height: radius * 2.0)))
    }
}



public func generateRectsImage(color: NSColor, rects: [CGRect], inset: CGFloat, outerRadius: CGFloat, innerRadius: CGFloat, stroke: Bool = false, strokeWidth: CGFloat = 2.0, useModernPathCalculation: Bool) -> (CGPoint, CGImage?) {
    if rects.isEmpty {
        return (CGPoint(), nil)
    }
    
    var topLeft = rects[0].origin
    var bottomRight = CGPoint(x: rects[0].maxX, y: rects[0].maxY)
    for i in 1 ..< rects.count {
        topLeft.x = min(topLeft.x, rects[i].origin.x)
        topLeft.y = min(topLeft.y, rects[i].origin.y)
        bottomRight.x = max(bottomRight.x, rects[i].maxX)
        bottomRight.y = max(bottomRight.y, rects[i].maxY)
    }
    
    var drawingInset = inset
    if stroke {
        drawingInset += 2.0
    }
    
    topLeft.x -= drawingInset
    topLeft.y -= drawingInset
    bottomRight.x += drawingInset * 2.0
    bottomRight.y += drawingInset * 2.0
    
    return (topLeft, generateImage(CGSize(width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y), rotatedContext: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        context.setFillColor(color.cgColor)
        
        context.setBlendMode(.copy)
        
        if useModernPathCalculation {
            if rects.count == 1 {
                let path = CGPath(roundedRect: rects[0].offsetBy(dx: -topLeft.x, dy: -topLeft.y), cornerWidth: outerRadius, cornerHeight: outerRadius, transform: nil)
                context.addPath(path)
                
                if stroke {
                    context.setStrokeColor(color.cgColor)
                    context.setLineWidth(strokeWidth)
                    context.strokePath()
                } else {
                    context.fillPath()
                }
                return
            }
            
            var combinedRects: [[CGRect]] = []
            var currentRects: [CGRect] = []
            for rect in rects {
                if rect.width.isZero {
                    if !currentRects.isEmpty {
                        combinedRects.append(currentRects)
                    }
                    currentRects.removeAll()
                } else {
                    currentRects.append(rect)
                }
            }
            if !currentRects.isEmpty {
                combinedRects.append(currentRects)
            }
            
            for rects in combinedRects {
                var rects = rects.map { $0.insetBy(dx: -inset, dy: -inset).offsetBy(dx: -topLeft.x, dy: -topLeft.y) }
                
                let minRadius: CGFloat = 2.0
                
                for _ in 0 ..< rects.count * rects.count {
                    var hadChanges = false
                    for i in 0 ..< rects.count - 1 {
                        if rects[i].maxY > rects[i + 1].minY {
                            let midY = floor((rects[i].maxY + rects[i + 1].minY) * 0.5)
                            rects[i].size.height = midY - rects[i].minY
                            rects[i + 1].origin.y = midY
                            rects[i + 1].size.height = rects[i + 1].maxY - midY
                            hadChanges = true
                        }
                        if rects[i].maxY >= rects[i + 1].minY && rects[i].insetBy(dx: 0.0, dy: 1.0).intersects(rects[i + 1]) {
                            if abs(rects[i].minX - rects[i + 1].minX) < minRadius {
                                let commonMinX = min(rects[i].origin.x, rects[i + 1].origin.x)
                                if rects[i].origin.x != commonMinX {
                                    rects[i].origin.x = commonMinX
                                    hadChanges = true
                                }
                                if rects[i + 1].origin.x != commonMinX {
                                    rects[i + 1].origin.x = commonMinX
                                    hadChanges = true
                                }
                            }
                            if abs(rects[i].maxX - rects[i + 1].maxX) < minRadius {
                                let commonMaxX = max(rects[i].maxX, rects[i + 1].maxX)
                                if rects[i].maxX != commonMaxX {
                                    rects[i].size.width = commonMaxX - rects[i].minX
                                    hadChanges = true
                                }
                                if rects[i + 1].maxX != commonMaxX {
                                    rects[i + 1].size.width = commonMaxX - rects[i + 1].minX
                                    hadChanges = true
                                }
                            }
                        }
                    }
                    if !hadChanges {
                        break
                    }
                }
                
                context.move(to: CGPoint(x: rects[0].midX, y: rects[0].minY))
                context.addLine(to: CGPoint(x: rects[0].maxX - outerRadius, y: rects[0].minY))
                context.addArc(tangent1End: rects[0].topRight, tangent2End: CGPoint(x: rects[0].maxX, y: rects[0].minY + outerRadius), radius: outerRadius)
                context.addLine(to: CGPoint(x: rects[0].maxX, y: rects[0].midY))
                
                for i in 0 ..< rects.count - 1 {
                    let rect = rects[i]
                    let next = rects[i + 1]
                    
                    if rect.maxX == next.maxX {
                        context.addLine(to: CGPoint(x: next.maxX, y: next.midY))
                    } else {
                        let nextRadius = min(outerRadius, floor(abs(rect.maxX - next.maxX) * 0.5))
                        context.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - nextRadius))
                        if next.maxX > rect.maxX {
                            context.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX + nextRadius, y: rect.maxY), radius: nextRadius)
                            context.addLine(to: CGPoint(x: next.maxX - nextRadius, y: next.minY))
                        } else {
                            context.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.maxX - nextRadius, y: rect.maxY), radius: nextRadius)
                            context.addLine(to: CGPoint(x: next.maxX + nextRadius, y: next.minY))
                        }
                        context.addArc(tangent1End: next.topRight, tangent2End: CGPoint(x: next.maxX, y: next.minY + nextRadius), radius: nextRadius)
                        context.addLine(to: CGPoint(x: next.maxX, y: next.midY))
                    }
                }
                
                let last = rects[rects.count - 1]
                context.addLine(to: CGPoint(x: last.maxX, y: last.maxY - outerRadius))
                context.addArc(tangent1End: last.bottomRight, tangent2End: CGPoint(x: last.maxX - outerRadius, y: last.maxY), radius: outerRadius)
                context.addLine(to: CGPoint(x: last.minX + outerRadius, y: last.maxY))
                context.addArc(tangent1End: last.bottomLeft, tangent2End: CGPoint(x: last.minX, y: last.maxY - outerRadius), radius: outerRadius)
                
                for i in (1 ..< rects.count).reversed() {
                    let rect = rects[i]
                    let prev = rects[i - 1]
                    
                    if rect.minX == prev.minX {
                        context.addLine(to: CGPoint(x: prev.minX, y: prev.midY))
                    } else {
                        let prevRadius = min(outerRadius, floor(abs(rect.minX - prev.minX) * 0.5))
                        context.addLine(to: CGPoint(x: rect.minX, y: rect.minY + prevRadius))
                        if rect.minX < prev.minX {
                            context.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + prevRadius, y: rect.minY), radius: prevRadius)
                            context.addLine(to: CGPoint(x: prev.minX - prevRadius, y: prev.maxY))
                        } else {
                            context.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX - prevRadius, y: rect.minY), radius: prevRadius)
                            context.addLine(to: CGPoint(x: prev.minX + prevRadius, y: prev.maxY))
                        }
                        context.addArc(tangent1End: prev.bottomLeft, tangent2End: CGPoint(x: prev.minX, y: prev.maxY - prevRadius), radius: prevRadius)
                        context.addLine(to: CGPoint(x: prev.minX, y: prev.midY))
                    }
                }
                
                context.addLine(to: CGPoint(x: rects[0].minX, y: rects[0].minY + outerRadius))
                context.addArc(tangent1End: rects[0].topLeft, tangent2End: CGPoint(x: rects[0].minX + outerRadius, y: rects[0].minY), radius: outerRadius)
                context.addLine(to: CGPoint(x: rects[0].midX, y: rects[0].minY))
                
                if stroke {
                    context.setStrokeColor(color.cgColor)
                    context.setLineWidth(strokeWidth)
                    context.strokePath()
                } else {
                    context.fillPath()
                }
            }
            return
        }
        
        for i in 0 ..< rects.count {
            let rect = rects[i].insetBy(dx: -inset, dy: -inset)
            context.fill(rect.offsetBy(dx: -topLeft.x, dy: -topLeft.y))
        }
        
        for i in 0 ..< rects.count {
            let rect = rects[i].insetBy(dx: -inset, dy: -inset).offsetBy(dx: -topLeft.x, dy: -topLeft.y)
            
            var previous: CGRect?
            if i != 0 {
                previous = rects[i - 1].insetBy(dx: -inset, dy: -inset).offsetBy(dx: -topLeft.x, dy: -topLeft.y)
            }
            
            var next: CGRect?
            if i != rects.count - 1 {
                next = rects[i + 1].insetBy(dx: -inset, dy: -inset).offsetBy(dx: -topLeft.x, dy: -topLeft.y)
            }
            
            if let previous = previous {
                if previous.contains(rect.topLeft) {
                    if abs(rect.topLeft.x - previous.minX) >= innerRadius {
                        var radius = innerRadius
                        if let next = next {
                            radius = min(radius, floor((next.minY - previous.maxY) / 2.0))
                        }
                        drawConnectingCorner(context: context, color: color, at: CGPoint(x: rect.topLeft.x, y: previous.maxY), type: .topLeft, radius: radius)
                    }
                } else {
                    drawFullCorner(context: context, color: color, at: rect.topLeft, type: .topLeft, radius: outerRadius)
                }
                if previous.contains(rect.topRight.offsetBy(dx: -1.0, dy: 0.0)) {
                    if abs(rect.topRight.x - previous.maxX) >= innerRadius {
                        var radius = innerRadius
                        if let next = next {
                            radius = min(radius, floor((next.minY - previous.maxY) / 2.0))
                        }
                        drawConnectingCorner(context: context, color: color, at: CGPoint(x: rect.topRight.x, y: previous.maxY), type: .topRight, radius: radius)
                    }
                } else {
                    drawFullCorner(context: context, color: color, at: rect.topRight, type: .topRight, radius: outerRadius)
                }
            } else {
                drawFullCorner(context: context, color: color, at: rect.topLeft, type: .topLeft, radius: outerRadius)
                drawFullCorner(context: context, color: color, at: rect.topRight, type: .topRight, radius: outerRadius)
            }
            
            if let next = next {
                if next.contains(rect.bottomLeft) {
                    if abs(rect.bottomRight.x - next.maxX) >= innerRadius {
                        var radius = innerRadius
                        if let previous = previous {
                            radius = min(radius, floor((next.minY - previous.maxY) / 2.0))
                        }
                        drawConnectingCorner(context: context, color: color, at: CGPoint(x: rect.bottomLeft.x, y: next.minY), type: .bottomLeft, radius: radius)
                    }
                } else {
                    drawFullCorner(context: context, color: color, at: rect.bottomLeft, type: .bottomLeft, radius: outerRadius)
                }
                if next.contains(rect.bottomRight.offsetBy(dx: -1.0, dy: 0.0)) {
                    if abs(rect.bottomRight.x - next.maxX) >= innerRadius {
                        var radius = innerRadius
                        if let previous = previous {
                            radius = min(radius, floor((next.minY - previous.maxY) / 2.0))
                        }
                        drawConnectingCorner(context: context, color: color, at: CGPoint(x: rect.bottomRight.x, y: next.minY), type: .bottomRight, radius: radius)
                    }
                } else {
                    drawFullCorner(context: context, color: color, at: rect.bottomRight, type: .bottomRight, radius: outerRadius)
                }
            } else {
                drawFullCorner(context: context, color: color, at: rect.bottomLeft, type: .bottomLeft, radius: outerRadius)
                drawFullCorner(context: context, color: color, at: rect.bottomRight, type: .bottomRight, radius: outerRadius)
            }
        }
    }))
}



private func generateRectsImage(color: NSColor, rects: [CGRect], inset: CGFloat, outerRadius: CGFloat, innerRadius: CGFloat) -> (CGPoint, CGImage?) {
    if rects.isEmpty {
        return (CGPoint(), nil)
    }
    
    var topLeft = rects[0].origin
    var bottomRight = CGPoint(x: rects[0].maxX, y: rects[0].maxY)
    for i in 1 ..< rects.count {
        topLeft.x = min(topLeft.x, rects[i].origin.x)
        topLeft.y = min(topLeft.y, rects[i].origin.y)
        bottomRight.x = max(bottomRight.x, rects[i].maxX)
        bottomRight.y = max(bottomRight.y, rects[i].maxY)
    }
    
    topLeft.x -= inset
    topLeft.y -= inset
    bottomRight.x += inset * 2
    bottomRight.y += inset * 2
    
    return (topLeft, generateImage(CGSize(width: bottomRight.x - topLeft.x, height: bottomRight.y - topLeft.y), contextGenerator: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        context.setFillColor(color.cgColor)
        
        context.setBlendMode(.copy)
        
        for i in 0 ..< rects.count {
            let rect = rects[i].insetBy(dx: -inset, dy: -inset)
            context.fill(rect.offsetBy(dx: -topLeft.x, dy: -topLeft.y))
        }
        
        for i in 0 ..< rects.count {
            let rect = rects[i].insetBy(dx: -inset, dy: -inset).offsetBy(dx: -topLeft.x, dy: -topLeft.y)
            
            var previous: CGRect?
            if i != 0 {
                previous = rects[i - 1].insetBy(dx: -inset, dy: -inset).offsetBy(dx: -topLeft.x, dy: -topLeft.y)
            }
            
            var next: CGRect?
            if i != rects.count - 1 {
                next = rects[i + 1].insetBy(dx: -inset, dy: -inset).offsetBy(dx: -topLeft.x, dy: -topLeft.y)
            }
            
            if let previous = previous {
                if previous.contains(rect.topLeft) {
                    if abs(rect.topLeft.x - previous.minX) >= innerRadius {
                        var radius = innerRadius
                        if let next = next {
                            radius = min(radius, floor((next.minY - previous.maxY) / 2.0))
                        }
                        drawConnectingCorner(context: context, color: color, at: CGPoint(x: rect.topLeft.x, y: previous.maxY), type: .topLeft, radius: radius)
                    }
                } else {
                    drawFullCorner(context: context, color: color, at: rect.topLeft, type: .topLeft, radius: outerRadius)
                }
                if previous.contains(rect.topRight.offsetBy(dx: -1.0, dy: 0.0)) {
                    if abs(rect.topRight.x - previous.maxX) >= innerRadius {
                        var radius = innerRadius
                        if let next = next {
                            radius = min(radius, floor((next.minY - previous.maxY) / 2.0))
                        }
                        drawConnectingCorner(context: context, color: color, at: CGPoint(x: rect.topRight.x, y: previous.maxY), type: .topRight, radius: radius)
                    }
                } else {
                    drawFullCorner(context: context, color: color, at: rect.topRight, type: .topRight, radius: outerRadius)
                }
            } else {
                drawFullCorner(context: context, color: color, at: rect.topLeft, type: .topLeft, radius: outerRadius)
                drawFullCorner(context: context, color: color, at: rect.topRight, type: .topRight, radius: outerRadius)
            }
            
            if let next = next {
                if next.contains(rect.bottomLeft) {
                    if abs(rect.bottomRight.x - next.maxX) >= innerRadius {
                        var radius = innerRadius
                        if let previous = previous {
                            radius = min(radius, floor((next.minY - previous.maxY) / 2.0))
                        }
                        drawConnectingCorner(context: context, color: color, at: CGPoint(x: rect.bottomLeft.x, y: next.minY), type: .bottomLeft, radius: radius)
                    }
                } else {
                    drawFullCorner(context: context, color: color, at: rect.bottomLeft, type: .bottomLeft, radius: outerRadius)
                }
                if next.contains(rect.bottomRight.offsetBy(dx: -1.0, dy: 0.0)) {
                    if abs(rect.bottomRight.x - next.maxX) >= innerRadius {
                        var radius = innerRadius
                        if let previous = previous {
                            radius = min(radius, floor((next.minY - previous.maxY) / 2.0))
                        }
                        drawConnectingCorner(context: context, color: color, at: CGPoint(x: rect.bottomRight.x, y: next.minY), type: .bottomRight, radius: radius)
                    }
                } else {
                    drawFullCorner(context: context, color: color, at: rect.bottomRight, type: .bottomRight, radius: outerRadius)
                }
            } else {
                drawFullCorner(context: context, color: color, at: rect.bottomLeft, type: .bottomLeft, radius: outerRadius)
                drawFullCorner(context: context, color: color, at: rect.bottomRight, type: .bottomRight, radius: outerRadius)
            }
        }
    }))
    
}

public enum LinkHoverValue {
    case entered(Any)
    case exited
}

public final class TextViewInteractions {
    public var processURL:(Any)->Void // link, isPresent
    public var copy:(()->Bool)?
    public var menuItems:((LinkType?)->Signal<[ContextMenuItem], NoError>)?
    public var isDomainLink:(Any, String?)->Bool
    public var makeLinkType:((Any, String))->LinkType
    public var localizeLinkCopy:(LinkType)-> String
    public var resolveLink:(Any)->String?
    public var copyAttributedString:(NSAttributedString)->Bool
    public var copyToClipboard:((String)->Void)?
    public var hoverOnLink: (LinkHoverValue)->Void
    public var topWindow:(()->Signal<Window?, NoError>)? = nil
    public var translate:((String, Window)->ContextMenuItem?)? = nil
    public var longHoverOnLink: ((Any, NSView)->Disposable?)?
    public init(processURL:@escaping (Any)->Void = {_ in}, copy:(()-> Bool)? = nil, menuItems:((LinkType?)->Signal<[ContextMenuItem], NoError>)? = nil, isDomainLink:@escaping(Any, String?)->Bool = {_, _ in return true}, makeLinkType:@escaping((Any, String)) -> LinkType = {_ in return .plain}, localizeLinkCopy:@escaping(LinkType)-> String = {_ in return localizedString("Text.Copy")}, resolveLink: @escaping(Any)->String? = { _ in return nil }, copyAttributedString: @escaping(NSAttributedString)->Bool = { _ in return false}, copyToClipboard: ((String)->Void)? = nil, hoverOnLink: @escaping(LinkHoverValue)->Void = { _ in }, topWindow:(()->Signal<Window?, NoError>)? = nil, translate:((String, Window)->ContextMenuItem?)? = nil, longHoverOnLink: ((Any, NSView)->Disposable?)? = nil) {
        self.processURL = processURL
        self.copy = copy
        self.menuItems = menuItems
        self.isDomainLink = isDomainLink
        self.makeLinkType = makeLinkType
        self.localizeLinkCopy = localizeLinkCopy
        self.resolveLink = resolveLink
        self.copyAttributedString = copyAttributedString
        self.copyToClipboard = copyToClipboard
        self.hoverOnLink = hoverOnLink
        self.longHoverOnLink = longHoverOnLink
        self.topWindow = topWindow
        self.translate = translate
    }
}

struct TextViewStrikethrough {
    let color: NSColor
    let frame: NSRect
    init(color: NSColor, frame: NSRect) {
        self.color = color
        self.frame = frame
    }
}

struct TextViewUnderline {
    let color: NSColor
    let frame: NSRect
    init(color: NSColor, frame: NSRect) {
        self.color = color
        self.frame = frame
    }
}

public final class TextViewLine {
    public let line: CTLine
    public var frame: NSRect
    public let range: NSRange
    fileprivate let lineRange: NSRange
    public var penFlush: CGFloat
    public let isRTL: Bool
    let isBlocked: Bool
    let strikethrough:[TextViewStrikethrough]
    let underlines:[TextViewUnderline]
    fileprivate let embeddedItems:[TextViewEmbeddedItem]
    fileprivate init(line: CTLine, frame: CGRect, range: NSRange, lineRange: NSRange, penFlush: CGFloat, isBlocked: Bool = false, isRTL: Bool = false, strikethrough: [TextViewStrikethrough] = [], underlines: [TextViewUnderline] = [], embeddedItems:[TextViewEmbeddedItem] = []) {
        self.line = line
        self.frame = frame
        self.range = range
        self.penFlush = penFlush
        self.isBlocked = isBlocked
        self.strikethrough = strikethrough
        self.underlines = underlines
        self.isRTL = isRTL
        self.embeddedItems = embeddedItems
        self.lineRange = lineRange
    }
}


public struct TextViewCutout: Equatable {
    public var topLeft: CGSize?
    public var topRight: CGSize?
    public var bottomRight: CGSize?
    
    public init(topLeft: CGSize? = nil, topRight: CGSize? = nil, bottomRight: CGSize? = nil) {
        self.topLeft = topLeft
        self.topRight = topRight
        self.bottomRight = bottomRight
    }
}

private let defaultFont:NSFont = .normal(.text)

public final class TextViewLayout : Equatable {
    
    public final class EmbeddedItem: Equatable {
            public let range: NSRange
            public let rect: CGRect
            public let value: AnyHashable
            
            public init(range: NSRange, rect: CGRect, value: AnyHashable) {
                self.range = range
                self.rect = rect.toScreenPixel
                self.value = value
            }
            
            public static func ==(lhs: EmbeddedItem, rhs: EmbeddedItem) -> Bool {
                if lhs.range != rhs.range {
                    return false
                }
                if lhs.rect != rhs.rect {
                    return false
                }
                if lhs.value != rhs.value {
                    return false
                }
                return true
            }
        }

    
    public class Spoiler {
        public let range: NSRange
        public let color: NSColor
        public fileprivate(set) var isRevealed: Bool = false
        public init(range: NSRange, color: NSColor, isRevealed: Bool = false) {
            self.range = range
            self.color = color.withAlphaComponent(1.0)
            self.isRevealed = isRevealed
        }
    }
    
    public var mayItems: Bool = true
    public var selectWholeText: Bool = false
    public fileprivate(set) var attributedString:NSAttributedString
    public fileprivate(set) var constrainedWidth:CGFloat = 0
    public var interactions:TextViewInteractions = TextViewInteractions()
    public var selectedRange:TextSelectedRange
    public var additionalSelections:[TextSelectedRange] = []
    public var penFlush:CGFloat
    fileprivate var insets:NSSize = NSZeroSize
    public var lines:[TextViewLine] = []
    public private(set) var blockQuotes: [TextViewBlockQuote] = []

    public func blockQuoteText(startingWith range: NSRange) -> String? {
        let length = attributedString.length
        guard range.location >= 0, range.location <= length, range.length >= 0, range.length <= length - range.location else { return nil }
        var end = range.location + range.length
        while end < length {
            var run = NSRange()
            guard attributedString.attribute(TextInputAttributes.quote, at: end, longestEffectiveRange: &run, in: NSRange(location: end, length: length - end)) != nil else { break }
            end = NSMaxRange(run)
        }
        return (attributedString.string as NSString).substring(with: NSRange(location: range.location, length: end - range.location))
    }

    public fileprivate(set) var isPerfectSized:Bool = true
    public var maximumNumberOfLines:Int32
    public let truncationType:CTLineTruncationType
    public var cutout:TextViewCutout?
    public var maxGlyphDrawCount: Int?
    public var mayBlocked: Bool = false
    fileprivate var blockImage:(CGPoint, CGImage?) = (CGPoint(), nil)
    
    public var maskBlockImage:(CGPoint, CGImage?) = (CGPoint(), nil)
        
    public fileprivate(set) var lineSpacing:CGFloat?
    
    public var hasBlock: Bool {
        return blockImage.1 != nil
    }
    
    private static let quoteAttributeKey = TextInputAttributes.quote.rawValue as CFString

    private func lastBlockQuote(in range: NSRange) -> TextViewBlockQuoteData? {
        return Self.lastBlockQuote(in: range, attributedString: attributedString)
    }

    private static func lastBlockQuote(in range: NSRange, attributedString: NSAttributedString) -> TextViewBlockQuoteData? {
        let length = attributedString.length
        guard range.location >= 0, range.length > 0, range.location <= length, range.length <= length - range.location else { return nil }
        let string = attributedString as CFAttributedString
        let index = NSMaxRange(range) - 1
        if let value = CFAttributedStringGetAttribute(string, index, Self.quoteAttributeKey, nil) {
            return value as? TextViewBlockQuoteData
        }
        var missing = CFRange()
        _ = CFAttributedStringGetAttributeAndLongestEffectiveRange(string, index, Self.quoteAttributeKey, CFRange(location: range.location, length: range.length), &missing)
        guard missing.location > range.location else { return nil }
        return CFAttributedStringGetAttribute(string, missing.location - 1, Self.quoteAttributeKey, nil) as? TextViewBlockQuoteData
    }

    public var hasBlockQuotes: Bool {
        return lastBlockQuote(in: NSRange(location: 0, length: attributedString.length)) != nil
    }
    
    public var lastLineIsQuote: Bool {
        if let lineRange = self.lines.last?.lineRange {
            return lastBlockQuote(in: lineRange) != nil
        } else {
            return false
        }
    }
    
    public var blockCollapsable: Bool {
        return lastBlockQuote(in: NSRange(location: 0, length: attributedString.length))?.collapsable ?? false
    }
    
    public var string: String {
        return self.attributedString.string
    }
    
    public private(set) var layoutSize:NSSize = NSZeroSize
    public private(set) var perfectSize:NSSize = NSZeroSize

    public var alwaysStaticItems: Bool
    fileprivate var selectText: NSColor
    public var strokeLinks: Bool
    fileprivate var strokeRects: [(NSRect, NSColor)] = []
    fileprivate var hexColorsRect: [(NSRect, NSColor, String)] = []
    public fileprivate(set) var toolTipRects:[NSRect] = []
    private let disableTooltips: Bool
    private var preparedText: TextViewPreparedText?
    public fileprivate(set) var isBigEmoji: Bool = false
    fileprivate let spoilers:[Spoiler]
    private let onSpoilerReveal: ()->Void
    public private(set) var embeddedItems: [EmbeddedItem] = []
    public var truncatingColor: NSColor? = nil
    
    public init(_ attributedString:NSAttributedString, constrainedWidth:CGFloat = 0, maximumNumberOfLines:Int32 = INT32_MAX, truncationType: CTLineTruncationType = .end, cutout:TextViewCutout? = nil, alignment:NSTextAlignment = .left, lineSpacing:CGFloat? = nil, selectText: NSColor = presentation.colors.selectText, strokeLinks: Bool = false, alwaysStaticItems: Bool = false, disableTooltips: Bool = true, mayItems: Bool = true, spoilerColor:NSColor = presentation.colors.text, isSpoilerRevealed: Bool = false, onSpoilerReveal: @escaping()->Void = {}, truncatingColor: NSColor? = nil) {
        self.truncationType = truncationType
        self.maximumNumberOfLines = maximumNumberOfLines
        self.cutout = cutout
        self.disableTooltips = disableTooltips
        self.attributedString = attributedString
        self.constrainedWidth = constrainedWidth
        self.selectText = selectText
        self.alwaysStaticItems = alwaysStaticItems
        self.selectedRange = TextSelectedRange(color: selectText)
        self.strokeLinks = strokeLinks
        self.mayItems = mayItems
        self.onSpoilerReveal = onSpoilerReveal
        self.truncatingColor = truncatingColor
        switch alignment {
        case .center:
            penFlush = 0.5
        case .right:
            penFlush = 1.0
        default:
            penFlush = 0.0
        }
        self.lineSpacing = lineSpacing
        var spoilers: [Spoiler] = []
        attributedString.enumerateAttribute(TextInputAttributes.spoiler, in: attributedString.range, options: .init(), using: { value, range, stop in
            if let _ = value {
                spoilers.append(.init(range: range, color: spoilerColor, isRevealed: isSpoilerRevealed))
            }
        })
        self.spoilers = spoilers
        
    }
    
    func revealSpoiler() -> Void {
        for spoiler in spoilers {
            spoiler.isRevealed = true
        }
        onSpoilerReveal()
    }
    public var selectedString: NSAttributedString {
        if selectedRange.range.isEmpty {
            return self.attributedString
        } else {
            return self.attributedString.attributedSubstring(from: selectedRange.range)
        }
    }
    
    public func setAttributedString(_ string: NSAttributedString) {
        self.attributedString = string
        self.preparedText = nil
    }

    public func dropLayoutSize() {
        self.layoutSize = .zero
    }
    
    public var numberOfLines: Int {
        return lines.count
    }
    public var lastLineIsRtl: Bool {
        return lines.last?.isRTL ?? false
    }
    
    public var lastLineIsBlock: Bool {
        return blockQuotes.contains(where: { blockQuote in
            if let line = lines.last {
                if blockQuote.frame.intersects(line.frame) {
                    return true
                }
            }
            return false
        })
    }
    
    public var firstLineWidth: CGFloat {
        return lines[0].frame.width
    }
    public var lastLineWidth: CGFloat {
        return lines[lines.count - 1].frame.width
    }
    public var firstLineHeight: CGFloat {
        return lines[0].frame.height
    }
    public var lastLineHeight: CGFloat {
        return lines[lines.count - 1].frame.height
    }
    
    
    func calculateLayout(isBigEmoji: Bool = false, lineSpacing: CGFloat? = nil, saveRTL: Bool = false) -> Void {
        self.isBigEmoji = isBigEmoji
        isPerfectSized = true
        
        self.insets = .zero
        
        
        let font: CTFont
        if attributedString.length != 0 {
            if let stringFont = attributedString.attribute(NSAttributedString.Key(kCTFontAttributeName as String), at: 0, effectiveRange: nil) {
                font = stringFont as! CTFont
            } else {
                font = defaultFont
            }
        } else {
            font = defaultFont
        }
        
        self.lines.removeAll()
        self.blockQuotes.removeAll()
        
        let fontAscent = CTFontGetAscent(font)
        let fontDescent = CTFontGetDescent(font)
       
        let fontLineHeight = floor(fontAscent + fontDescent)
        let fontCapHeight = CTFontGetCapHeight(font)

        func strikethroughCapHeight(_ attributes: [NSAttributedString.Key : Any]) -> CGFloat {
            if let runFont = attributes[NSAttributedString.Key(kCTFontAttributeName as String)] {
                let f = runFont as! CTFont
                return CTFontGetCapHeight(f)
            }
            return fontCapHeight
        }

        var fontLineSpacing:CGFloat = lineSpacing ?? floor(fontLineHeight * 0.12)

        
        let attributedString: NSAttributedString
        let typesetter: CTTypesetter
        let needsRunDecorations: Bool
        if let prepared = self.preparedText, prepared.matches(self.attributedString) {
            attributedString = prepared.attributedString
            typesetter = prepared.typesetter
            needsRunDecorations = prepared.needsRunDecorations
        } else {
            let source = self.attributedString.copy() as! NSAttributedString
            let fullRange = NSMakeRange(0, source.length)
            var embeddedRanges: [NSRange] = []
            source.enumerateAttribute(TextInputAttributes.embedded, in: fullRange, options: [.longestEffectiveRangeNotRequired]) { value, range, _ in
                if let value = value, let _ = value as? AnyHashable {
                    embeddedRanges.append(range)
                }
            }
            var hasStrikethrough = false
            source.enumerateAttribute(.strikethroughStyle, in: fullRange, options: [.longestEffectiveRangeNotRequired]) { value, _, stop in
                if value != nil {
                    hasStrikethrough = true
                    stop.pointee = true
                }
            }
            if embeddedRanges.isEmpty {
                attributedString = source
            } else {
                let mutable = source.mutableCopy() as! NSMutableAttributedString
                for range in embeddedRanges {
                    mutable.addAttribute(.foregroundColor, value: NSColor.clear, range: range)
                }
                attributedString = mutable
            }
            let typesetterString: NSAttributedString
            if hasStrikethrough {
                let copy = attributedString.mutableCopy() as! NSMutableAttributedString
                copy.removeAttribute(.strikethroughStyle, range: copy.range)
                typesetterString = copy
            } else {
                typesetterString = attributedString
            }
            typesetter = CTTypesetterCreateWithAttributedString(typesetterString as CFAttributedString)
            var hasUnderline = false
            for key in [NSAttributedString.Key.underlineStyle, TextInputAttributes.underline] where !hasUnderline {
                source.enumerateAttribute(key, in: fullRange, options: [.longestEffectiveRangeNotRequired]) { value, _, stop in
                    if value != nil {
                        hasUnderline = true
                        stop.pointee = true
                    }
                }
            }
            needsRunDecorations = !embeddedRanges.isEmpty || hasStrikethrough || hasUnderline
            if source.length >= 64 && source.length <= 4096 {
                self.preparedText = TextViewPreparedText(source: source, attributedString: attributedString, typesetter: typesetter, needsRunDecorations: needsRunDecorations)
            } else {
                self.preparedText = nil
            }
        }
        
        var lastLineCharacterIndex: CFIndex = 0
        var layoutSize = NSSize()
        
        var cutoutEnabled = false
        var cutoutMinY: CGFloat = 0.0
        var cutoutMaxY: CGFloat = 0.0
        var cutoutWidth: CGFloat = 0.0
        var cutoutOffset: CGFloat = 0.0
        
        
        var bottomCutoutEnabled = false
        var bottomCutoutSize = CGSize()
        

        
        
        if let topLeft = cutout?.topLeft {
            cutoutMinY = -fontLineSpacing
            cutoutMaxY = topLeft.height + fontLineSpacing
            cutoutWidth = topLeft.width
            cutoutOffset = cutoutWidth
            cutoutEnabled = true
        } else if let topRight = cutout?.topRight {
            cutoutMinY = -fontLineSpacing
            cutoutMaxY = topRight.height + fontLineSpacing
            cutoutWidth = topRight.width
            cutoutEnabled = true
        }
        if let bottomRight = cutout?.bottomRight {
            bottomCutoutSize = bottomRight
            bottomCutoutEnabled = true
        }

        let quoteString = attributedString as CFAttributedString
        var quoteRange = CFRange(location: 0, length: 0)
        var quoteValue: TextViewBlockQuoteData?
        let blockQuote: (Int) -> TextViewBlockQuoteData? = { index in
            let position = min(index, attributedString.length - 1)
            if position < quoteRange.location || position - quoteRange.location >= quoteRange.length {
                quoteValue = CFAttributedStringGetAttributeAndLongestEffectiveRange(quoteString, position, Self.quoteAttributeKey, CFRange(location: 0, length: attributedString.length), &quoteRange) as? TextViewBlockQuoteData
            }
            return quoteValue
        }
        
        var first = true
        var breakInset: CGFloat = 0
        var isWasPreformatted: Bool = false
        while true {
            var strikethroughs: [TextViewStrikethrough] = []
            var underlines: [TextViewUnderline] = []
            var embeddedItems: [TextViewEmbeddedItem] = []

            
            
            func addEmbeddedItem(item: AnyHashable, line: CTLine, ascent: CGFloat, descent: CGFloat, startIndex: Int, endIndex: Int, rightInset: CGFloat = 0.0) {
                var secondaryLeftOffset: CGFloat = 0.0
                let rawLeftOffset = CTLineGetOffsetForStringIndex(line, startIndex, &secondaryLeftOffset)
                var leftOffset = floor(rawLeftOffset)
                if !rawLeftOffset.isEqual(to: secondaryLeftOffset) {
                    leftOffset = floor(secondaryLeftOffset)
                }
                
                var secondaryRightOffset: CGFloat = 0.0
                let rawRightOffset = CTLineGetOffsetForStringIndex(line, endIndex, &secondaryRightOffset)
                var rightOffset = ceil(rawRightOffset)
                if !rawRightOffset.isEqual(to: secondaryRightOffset) {
                    rightOffset = ceil(secondaryRightOffset)
                }
                
                let lineRange = NSMakeRange(CTLineGetStringRange(line).location, CTLineGetStringRange(line).length)
                let range = NSMakeRange(startIndex, endIndex - startIndex)
                                
                if lineRange.intersection(range) != range {
                    return
                }
                if lineRange.location != startIndex, rawLeftOffset == 0 {
                    return
                }
               // return;
                                        
                if abs(rightOffset - leftOffset) < 200 {
                    let x = floor(min(leftOffset, rightOffset)) + 1
                    var width = floor(abs(rightOffset - leftOffset) + rightInset)
                    if Int(width) % 2 != 0 {
                        width += 1
                    }
                    let height = ceil(ascent + descent)
                    let size = NSMakeSize(width, height)
                    let rect = CGRect(x: x, y: floor(descent - (ascent + descent)), width: size.width, height: size.height)
                    embeddedItems.append(TextViewEmbeddedItem(range: NSMakeRange(startIndex, endIndex - startIndex), frame: rect.insetBy(dx: -2, dy: -2), item: item))
                }
            }
            



            var lineConstrainedWidth = constrainedWidth
            var lineOriginY: CGFloat = 0
            
            var lineCutoutOffset: CGFloat = 0.0
            var lineAdditionalWidth: CGFloat = 0.0

            var isPreformattedLine: CGFloat? = nil
            
            fontLineSpacing = lineSpacing ?? floor(fontLineHeight * 0.12)
            
            if isBigEmoji {
                lineOriginY += 2
            }
            
            var isFirstFormattedLine: Bool = false
            
            if attributedString.length > 0, let blockQuote = blockQuote(lastLineCharacterIndex) {
                
                
                breakInset = CGFloat(blockQuote.space * 2 + 20)
                lineCutoutOffset += CGFloat(blockQuote.space * 2)
                lineAdditionalWidth += max(breakInset, blockQuote.minimumHeaderSize)
                
                if !isWasPreformatted {
                    layoutSize.height += CGFloat(blockQuote.space) + fontLineSpacing
                    
                    layoutSize.height += blockQuote.headerInset
                    
                    isFirstFormattedLine = true
                } else {
                    
                    if isWasPreformatted {
                        
                    } else if first {
                        layoutSize.height += CGFloat(blockQuote.space)
                    }
                    
                }

                isPreformattedLine = CGFloat(blockQuote.space)
                isWasPreformatted = true
            } else {
                
//                if isWasPreformatted && !first {
//                    lineOriginY -= (2 - fontLineSpacing)
//                }
//                if let isPreformattedLine = isPreformattedLine {
//                    fontLineSpacing += isPreformattedLine
//                }
                
                isWasPreformatted = false
            }
            
            lineOriginY += floor(layoutSize.height + fontLineHeight - fontLineSpacing * 2.0)
            
            if !first {
                lineOriginY += fontLineSpacing
            }
            
            if cutoutEnabled {
                if lineOriginY < cutoutMaxY && lineOriginY + fontLineHeight > cutoutMinY {
                    lineConstrainedWidth = max(1.0, lineConstrainedWidth - cutoutWidth)
                    lineCutoutOffset = cutoutOffset
                    lineAdditionalWidth = cutoutWidth
                }
            }
            
            
            
            let isLastAllowedLine = maximumNumberOfLines > 0 && lines.count == Int(maximumNumberOfLines) - 1
            let lineBreakWidth = lineConstrainedWidth - breakInset
            let lineCharacterCount: CFIndex
            if isLastAllowedLine && lastLineCharacterIndex < attributedString.length && lineBreakWidth > 0 && lineBreakWidth.isFinite {
                lineCharacterCount = 1
            } else {
                lineCharacterCount = CTTypesetterSuggestLineBreak(typesetter, lastLineCharacterIndex, Double(lineBreakWidth))
            }
            var lineRange = CFRange(location: lastLineCharacterIndex, length: lineCharacterCount)

            
            let lineHeight = fontLineHeight
            
            
            
            
//            if lineString.string.containsEmoji, !isBigEmoji {
//                if first {
//                    lineHeight += floor(fontDescent)
//                    lineOriginY += floor(fontDescent)
//                }
//            }
            
            
            if isLastAllowedLine && lineCharacterCount > 0 {
                
                
                if first {
                    first = false
                } else {
                    layoutSize.height += fontLineSpacing
                }
                
                var brokenLineRange = CFRange(location: lastLineCharacterIndex, length: lineCharacterCount)
                if brokenLineRange.location + brokenLineRange.length > attributedString.length {
                    brokenLineRange.length = attributedString.length - brokenLineRange.location
                }

                
                let coreTextLine: CTLine
                
                let originalLine = CTTypesetterCreateLineWithOffset(typesetter, CFRange(location: lastLineCharacterIndex, length: attributedString.length - lastLineCharacterIndex), 0.0)
                
               
                
                let originalLineWidth = CTLineGetTypographicBounds(originalLine, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(originalLine)
                var measuredLineWidth = originalLineWidth
                if originalLineWidth < Double(constrainedWidth) {
                    coreTextLine = originalLine
                } else {
                    
                    let lastIndex = attributedString.length - lastLineCharacterIndex
                    
                    var truncationTokenAttributes: [NSAttributedString.Key : Any] = [:]
                    truncationTokenAttributes[NSAttributedString.Key(kCTFontAttributeName as String)] = font
                    truncationTokenAttributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = truncatingColor ?? attributedString.attribute(.foregroundColor, at: min(lastIndex, attributedString.length - 1), effectiveRange: nil) as? NSColor ?? NSColor.black
                    
                    let tokenString = "\u{2026}"
                    let truncatedTokenString = NSAttributedString(string: tokenString, attributes: truncationTokenAttributes)
                    let truncationToken = CTLineCreateWithAttributedString(truncatedTokenString)
                    
                    
                    var lineConstrainedWidth = constrainedWidth
                    if bottomCutoutEnabled {
                        lineConstrainedWidth -= bottomCutoutSize.width
                    }

                    
                    coreTextLine = CTLineCreateTruncatedLine(originalLine, Double(lineConstrainedWidth), truncationType, truncationToken) ?? truncationToken
                    measuredLineWidth = CTLineGetTypographicBounds(coreTextLine, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(coreTextLine)
                    
                    let runs = CTLineGetGlyphRuns(coreTextLine)
                    let contextColorKey = Unmanaged.passUnretained(kCTForegroundColorFromContextAttributeName).toOpaque()
                    for index in 0..<CFArrayGetCount(runs) {
                        let run = unsafeBitCast(CFArrayGetValueAtIndex(runs, index), to: CTRun.self)
                        if CFDictionaryContainsKey(CTRunGetAttributes(run), contextColorKey) {
                            brokenLineRange.length = CTRunGetStringRange(run).location - brokenLineRange.location
                            break
                        }
                    }
                    if brokenLineRange.location + brokenLineRange.length > attributedString.length {
                        brokenLineRange.length = attributedString.length - brokenLineRange.location
                    }

                    
                    isPerfectSized = false
                }
                lineRange = CTLineGetStringRange(coreTextLine)
                
                var isRTL = false
                let glyphRuns = CTLineGetGlyphRuns(coreTextLine)
                for index in 0..<CFArrayGetCount(glyphRuns) {
                    let run = unsafeBitCast(CFArrayGetValueAtIndex(glyphRuns, index), to: CTRun.self)
                    if CTRunGetStatus(run).contains(CTRunStatus.rightToLeft) {
                        isRTL = true
                        break
                    }
                }
                
                if isRTL {
                    lineAdditionalWidth = 0
                }
                
                let lineWidth = ceil(CGFloat(measuredLineWidth))
                let lineFrame = CGRect(x: lineCutoutOffset, y: lineOriginY, width: lineWidth, height: lineHeight)
                layoutSize.height += lineHeight + fontLineSpacing
                layoutSize.width = max(layoutSize.width, lineWidth + lineAdditionalWidth)
                
                if needsRunDecorations, brokenLineRange.location >= 0 && brokenLineRange.length > 0 && brokenLineRange.location + brokenLineRange.length <= attributedString.length {
                    attributedString.enumerateAttributes(in: NSMakeRange(lineRange.location, lineRange.length), options: []) { attributes, range, _ in
                        if let embeddedItem = attributes[TextInputAttributes.embedded] as? AnyHashable {
                            var ascent: CGFloat = 0.0
                            var descent: CGFloat = 0.0
                            CTLineGetTypographicBounds(coreTextLine, &ascent, &descent, nil)
                            
                            addEmbeddedItem(item: embeddedItem, line: coreTextLine, ascent: ascent, descent: descent, startIndex: range.min, endIndex: range.max)
                        } else if let _ = attributes[.strikethroughStyle] {
                            let color = attributes[.foregroundColor] as? NSColor ?? presentation.colors.text



                            let lowerX = floor(CTLineGetOffsetForStringIndex(coreTextLine, range.location, nil))
                            var upperX = ceil(CTLineGetOffsetForStringIndex(coreTextLine, min(range.location + range.length, lineRange.location + lineRange.length), nil))

                            let lineStartIndex = CTLineGetStringIndexForPosition(coreTextLine, NSMakePoint(lowerX, lineFrame.minY))


                            if lowerX > 0 && upperX == 0 {
                                upperX = lineWidth
                            }

                            if lowerX == 0, !range.contains(lineStartIndex) {

                            } else {
                                let x = lowerX < upperX ? lowerX : upperX
                                strikethroughs.append(TextViewStrikethrough(color: color, frame: CGRect(x: x, y: 0.0, width: abs(upperX - lowerX), height: strikethroughCapHeight(attributes))))
                            }

                        }
                        if attributes[.underlineStyle] != nil || attributes[TextInputAttributes.underline] != nil {
                            let color = attributes[.foregroundColor] as? NSColor ?? presentation.colors.text
                            let lowerX = floor(CTLineGetOffsetForStringIndex(coreTextLine, range.location, nil))
                            var upperX = ceil(CTLineGetOffsetForStringIndex(coreTextLine, min(range.location + range.length, lineRange.location + lineRange.length), nil))
                            let lineStartIndex = CTLineGetStringIndexForPosition(coreTextLine, NSMakePoint(lowerX, lineFrame.minY))
                            if lowerX > 0 && upperX == 0 {
                                upperX = lineWidth
                            }
                            if !(lowerX == 0 && !range.contains(lineStartIndex)) {
                                let x = lowerX < upperX ? lowerX : upperX
                                underlines.append(TextViewUnderline(color: color, frame: CGRect(x: x, y: 0.0, width: abs(upperX - lowerX), height: fontLineHeight)))
                            }
                        }

                    }
                    
                }
                

                
                var penFlush = self.penFlush
                if penFlush == 0 {
                    if isRTL {
                        penFlush = 1
                    }
                } else if isRTL, penFlush == 1 {
                    penFlush = 0
                }
                let range = NSMakeRange(lineRange.location, lineRange.length)
                lines.append(TextViewLine(line: coreTextLine, frame: lineFrame, range: range, lineRange: range, penFlush: penFlush, isBlocked: isWasPreformatted, isRTL: isRTL, strikethrough: strikethroughs, underlines: underlines, embeddedItems: embeddedItems))
                
                break
            } else {
                if lineCharacterCount > 0 {
                    
                    
                    if first {
                        first = false
                    } else {
                        layoutSize.height += fontLineSpacing
                    }
                    
                    let coreTextLine = CTTypesetterCreateLineWithOffset(typesetter, CFRangeMake(lastLineCharacterIndex, lineCharacterCount), 100.0)
                    
                  
                    let lineWidth = ceil(CGFloat(CTLineGetTypographicBounds(coreTextLine, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(coreTextLine)))
                    let lineFrame = CGRect(x: lineCutoutOffset, y: lineOriginY, width: lineWidth, height: lineHeight)
                    layoutSize.height += lineHeight
                    layoutSize.width = max(layoutSize.width, lineWidth + lineAdditionalWidth)
                    
                    let lineQuote: TextViewBlockQuoteData?
                    if lineRange.location >= quoteRange.location && lineRange.location + lineRange.length <= quoteRange.location + quoteRange.length {
                        lineQuote = quoteValue
                    } else {
                        lineQuote = Self.lastBlockQuote(in: NSMakeRange(lineRange.location, lineRange.length), attributedString: attributedString)
                    }
                    if let blockQuote = lineQuote {
                        
                        let preformattedSpace = CGFloat(blockQuote.space) * 2
                        
                        var frame = NSMakeRect(0, lineFrame.minY - lineFrame.height, lineWidth + max(preformattedSpace + 20, lineAdditionalWidth), lineFrame.height + preformattedSpace)
                        
                        if isFirstFormattedLine {
                            frame.origin.y -= blockQuote.headerInset
                            frame.size.height += blockQuote.headerInset
                        }
                        blockQuotes.append(.init(frame: frame, range: NSMakeRange(lineRange.location, lineRange.length), colors: blockQuote.colors, isCode: blockQuote.isCode, header: blockQuote.header))
                    }

                    if needsRunDecorations {
                    attributedString.enumerateAttributes(in: NSMakeRange(lineRange.location, lineRange.length), options: []) { attributes, range, _ in
                        if let embeddedItem = attributes[TextInputAttributes.embedded] as? AnyHashable {
                            var ascent: CGFloat = 0.0
                            var descent: CGFloat = 0.0
                            CTLineGetTypographicBounds(coreTextLine, &ascent, &descent, nil)
                                                        
                            addEmbeddedItem(item: embeddedItem, line: coreTextLine, ascent: ascent, descent: descent, startIndex: range.location, endIndex: range.location + range.length)
                        } else if let _ = attributes[.strikethroughStyle] {
                            let color = attributes[.foregroundColor] as? NSColor ?? presentation.colors.text
                            let lowerX = floor(CTLineGetOffsetForStringIndex(coreTextLine, range.location, nil))
                            let upperX = ceil(CTLineGetOffsetForStringIndex(coreTextLine, range.location + range.length, nil))
                            let x = lowerX < upperX ? lowerX : upperX
                            let value = attributes.contains(where: { $0.key == TextInputAttributes.customEmoji })
                            if !value {
                                strikethroughs.append(TextViewStrikethrough(color: color, frame: CGRect(x: x, y: 0.0, width: abs(upperX - lowerX), height: strikethroughCapHeight(attributes))))
                            }
                        }
                        if attributes[.underlineStyle] != nil || attributes[TextInputAttributes.underline] != nil {
                            let color = attributes[.foregroundColor] as? NSColor ?? presentation.colors.text
                            let lowerX = floor(CTLineGetOffsetForStringIndex(coreTextLine, range.location, nil))
                            let upperX = ceil(CTLineGetOffsetForStringIndex(coreTextLine, range.location + range.length, nil))
                            let x = lowerX < upperX ? lowerX : upperX
                            let isCustomEmoji = attributes.contains(where: { $0.key == TextInputAttributes.customEmoji })
                            if !isCustomEmoji {
                                underlines.append(TextViewUnderline(color: color, frame: CGRect(x: x, y: 0.0, width: abs(upperX - lowerX), height: fontLineHeight)))
                            }
                        }

                    }
                    }
                    
                    var isRTL = false
                    let glyphRuns = CTLineGetGlyphRuns(coreTextLine)
                    if CFArrayGetCount(glyphRuns) != 0 {
                        let run = unsafeBitCast(CFArrayGetValueAtIndex(glyphRuns, 0), to: CTRun.self)
                        if CTRunGetStatus(run).contains(CTRunStatus.rightToLeft) {
                            isRTL = true
                        }
                    }
                    var penFlush = self.penFlush
                    if penFlush == 0 {
                        if isRTL {
                            penFlush = 1
                        }
                    } else if isRTL, penFlush == 1 {
                        penFlush = 0
                    }
                    let range = NSMakeRange(lineRange.location, lineRange.length)
                    lines.append(TextViewLine(line: coreTextLine, frame: lineFrame, range: range, lineRange: range, penFlush: penFlush, isBlocked: isWasPreformatted, isRTL: isRTL, strikethrough: strikethroughs, underlines: underlines, embeddedItems: embeddedItems))
                    lastLineCharacterIndex += lineCharacterCount
                } else {
                    if !lines.isEmpty {
                        layoutSize.height += fontLineSpacing
                    }
                    break
                }
            }
            
            if let isPreformattedLine = isPreformattedLine {
                if lastLineCharacterIndex == attributedString.length || blockQuote(lastLineCharacterIndex) == nil {
                    layoutSize.height += isPreformattedLine + isPreformattedLine / 2
                }
            }
            
        }
        
        self.blockQuotes = combineIntersectingRectangles(self.blockQuotes)
       
        
//        if mayBlocked {
            
        
//
//            self.blockImage = generateRectsImage(color: presentation.colors.grayBackground, rects: monospacedRects, inset: 0, outerRadius: .cornerRadius, innerRadius: .cornerRadius)
//        }
        
        var embeddedItems: [EmbeddedItem] = []
        for line in lines {
            for embeddedItem in line.embeddedItems {
                let penOffset = floor(CGFloat(CTLineGetPenOffsetForFlush(line.line, line.penFlush, Double(layoutSize.width))))
                embeddedItems.append(EmbeddedItem(range: embeddedItem.range, rect: embeddedItem.frame.offsetBy(dx: line.frame.minX, dy: line.frame.minY).offsetBy(dx: penOffset, dy: 0), value: embeddedItem.item))
            }
        }


        self.embeddedItems = embeddedItems
        
        if saveRTL {
            layoutSize.width = max(layoutSize.width, constrainedWidth)
        }
        
        self.layoutSize = layoutSize
    }
    
    
    public func rects(_ fromRange: NSRange) -> [(CGRect, TextViewLine)] {
        var rects:[(CGRect, TextViewLine)] = []
        for i in 0 ..< lines.count {
            let line = lines[i]
            if let intersection = fromRange.intersection(line.range) {
                let range = intersection.intersection(selectedRange.range)
                
                var ranges:[(NSRange, TextViewLine)] = []
                if let range = range {
                    ranges.append((NSMakeRange(fromRange.lowerBound, range.lowerBound - fromRange.lowerBound), line))
                    ranges.append((NSMakeRange(fromRange.lowerBound, range.lowerBound - fromRange.lowerBound), line))
                } else {
                    ranges.append((intersection, line))
                }
                for range in ranges {
                    var startSecondaryOffset: CGFloat = 0
                    var endSecondaryOffset: CGFloat = 0
                    let startOffset = CTLineGetOffsetForStringIndex(line.line, range.0.lowerBound, &startSecondaryOffset)
                    let endOffset = CTLineGetOffsetForStringIndex(line.line, range.0.upperBound, &endSecondaryOffset)

                    var ascent:CGFloat = 0
                    var descent:CGFloat = 0
                    var leading:CGFloat = 0
                    
                    _ = CGFloat(CTLineGetTypographicBounds(line.line, &ascent, &descent, &leading));
                    
                    var rect:NSRect = line.frame
                    
                    if startOffset == endOffset, range.0.length > 0 {
                        let minOffset = min(startOffset, startSecondaryOffset, endSecondaryOffset)
                        rect.size.width = max(startOffset, startSecondaryOffset, endSecondaryOffset) - minOffset
                        rect.origin.x = minOffset + line.frame.origin.x
                    } else {
                        rect.size.width = abs(endOffset - startOffset)
                        rect.origin.x = min(startOffset, endOffset) + line.frame.origin.x
                    }
                    rect.origin.y = rect.minY - rect.height + 2
                    rect.size.height += ceil(descent - leading)
                    
                    rects.append((rect, line))
  
                }
            }
        }
        return rects
    }
    
    public func generateBlock(for range: NSRange, backgroundColor: NSColor) -> (CGPoint, CGImage?) {
        
        let rectsAndLines = rects(range)
        var rects = rectsAndLines.map { $0.0 }
        
        if !rects.isEmpty {
            let sortedIndices = (0 ..< rects.count).sorted(by: { rects[$0].width > rects[$1].width })
            for i in 0 ..< sortedIndices.count {
                let index = sortedIndices[i]
                for j in -1 ... 1 {
                    if j != 0 && index + j >= 0 && index + j < sortedIndices.count {
                        if abs(rects[index + j].width - rects[index].width) < 10 {
                            rects[index + j].size.width = max(rects[index + j].width, rects[index].width)
                        }
                    }
                }
            }
            
            for i in 0 ..< rects.count {
                let height = rects[i].size.height
                rects[i] = rects[i].insetBy(dx: 0, dy: floor((rects[i].height - height) / 2.0))
                rects[i].size.height = height
                
                if rectsAndLines[i].1.penFlush == 1.0 {
                    rects[i].origin.x = layoutSize.width - rects[i].width
                } else if rectsAndLines[i].1.penFlush == 0.5 {
                    rects[i].origin.x = floor((layoutSize.width - rects[i].width) / 2.0)
                }
                
            }
            
            return generateRectsImage(color: backgroundColor, rects: rects, inset: 0, outerRadius: 4, innerRadius: 4, useModernPathCalculation: false)
            
//            var image = generateRectsImage(color: backgroundColor, rects: rects, inset: 0, outerRadius: rects[0].height / 2 , innerRadius: 10)
//            image.0 = rects[0].origin
//            
//            return image
        } else {
            return (.zero, nil)
        }
        
    }
    
    public func generateBlock(backgroundColor: NSColor) -> (CGPoint, CGImage?) {
        guard !self.lines.isEmpty else {
            return (.zero, nil)
        }
        let text = attributedString.string as NSString
        let lines = self.lines.filter { $0.range.length != 1 || text.character(at: $0.range.location) != 0x0A }
        var rects = lines.map({ $0.frame })
        
        
        if !rects.isEmpty {
            let sortedIndices = (0 ..< rects.count).sorted(by: { rects[$0].width > rects[$1].width })
            for i in 0 ..< sortedIndices.count {
                let index = sortedIndices[i]
                for j in -1 ... 1 {
                    if j != 0 && index + j >= 0 && index + j < sortedIndices.count {
                        if abs(rects[index + j].width - rects[index].width) < 10 {
                            rects[index + j].size.width = max(rects[index + j].width, rects[index].width)
                        }
                    }
                }
            }
            
            for i in 0 ..< rects.count {
                let height = rects[i].size.height + 5
                rects[i] = rects[i].insetBy(dx: 0, dy: floor((rects[i].height - height) / 2.0))
                rects[i].size.height = height
                
                if lines[i].penFlush == 1.0 {
                    rects[i].origin.x = layoutSize.width - rects[i].width - 5
                    rects[i].size.width += 10
                } else if lines[i].penFlush == 0.5 {
                    rects[i].origin.x = floor((layoutSize.width - rects[i].width) / 2.0)
                    rects[i].size.width += 20
                } else {
                    rects[i].size.width += 10
                    rects[i].origin.x -= 5
                }
                
            }
            
            var image = generateRectsImage(color: backgroundColor, rects: rects, inset: 0, outerRadius: lines.count == 1 ? rects[0].height / 2 : 10, innerRadius: .cornerRadius)
            image.0 = NSMakePoint(0, 0)
            
            return image
        } else {
            return (.zero, nil)
        }
    }
    
    public func generateAutoBlock(backgroundColor: NSColor, minusHeight: CGFloat = 0, yInset: CGFloat = 0) {
        
        var rects = self.lines.map({ $0.frame })
        
        if !rects.isEmpty {
            let sortedIndices = (0 ..< rects.count).sorted(by: { rects[$0].width > rects[$1].width })
            for i in 0 ..< sortedIndices.count {
                let index = sortedIndices[i]
                for j in -1 ... 1 {
                    if j != 0 && index + j >= 0 && index + j < sortedIndices.count {
                        let dif = minusHeight != 0 ? 10 : 40.0
                        if abs(rects[index + j].width - rects[index].width) < dif {
                            rects[index + j].size.width = max(rects[index + j].width, rects[index].width)
                        }
                    }
                }
            }
            
            for i in 0 ..< rects.count {
                let height = rects[i].size.height + 5
                rects[i] = rects[i].insetBy(dx: 0, dy: floor((rects[i].height - height) / 2.0))
                rects[i].size.height = height
                if self.penFlush == 0.5 {
                    rects[i].origin.x = floor((layoutSize.width - rects[i].width) / 2.0)
                    rects[i].size.width += 20
                } else {
                    rects[i].size.width += 10
                    rects[i].origin.x -= 5
                }
            }
            
            self.blockImage = generateRectsImage(color: backgroundColor, rects: rects, inset: 0, outerRadius: lines.count == 1 ? rects[0].height / 2 : 10, innerRadius: .cornerRadius)
            self.blockImage.0 = NSMakePoint(0, 0)
            
            var offset: NSPoint = NSPoint(x: 0, y: 0)
            if self.penFlush == 0.5 {
                offset.y = 2
                layoutSize.width += 20
            } else {
                layoutSize.width += 10
                offset.x = 5
            }
            for i in 0 ..< lines.count {
                let line = lines[i]
                lines[i] = TextViewLine(line: line.line, frame: line.frame.offsetBy(dx: offset.x, dy: offset.y + yInset), range: line.range, lineRange: line.range, penFlush: self.penFlush, strikethrough: line.strikethrough, embeddedItems: line.embeddedItems)
            }
            layoutSize.height = rects.last!.maxY - minusHeight
        } else {
            self.blockImage = (.zero, nil)
        }
        
    }
    
    public func selectNextChar() {
        var range = selectedRange.range
        
        switch selectedRange.cursorAlignment {
        case let .min(cursorAlignment), let .max(cursorAlignment):
            if range.min >= cursorAlignment {
                range.length += 1
            } else {
                range.location += 1
                if range.length > 1 {
                    range.length -= 1
                }
            }
        }
        let location = min(max(0, range.location), attributedString.length)
        let length = max(min(range.length, attributedString.length - location), 0)
        selectedRange.range = NSMakeRange(location, length)
    }
    
    public func selectPrevChar() {
        var range = selectedRange.range
        
        switch selectedRange.cursorAlignment {
            case let .min(cursorAlignment), let .max(cursorAlignment):
            if range.location >= cursorAlignment {
                if range.length > 1 {
                    range.length -= 1
                } else {
                    range.location -= 1
                }
            } else {
                if range.location > 0 {
                    range.location -= 1
                    range.length += 1
                }
            }
        }
        let location = min(max(0, range.location), attributedString.length)
        let length = max(min(range.length, attributedString.length - location), 0)
        selectedRange.range = NSMakeRange(location, length)
    }
    public func fitToLines(_ count: Int) {
        if lines.count > count {
            let lines = Array(lines.prefix(count))
            self.layoutSize = NSMakeSize(self.layoutSize.width, lines[lines.count - 1].frame.minY + 2)
        }
    }
    public func measure(width: CGFloat = 0, isBigEmoji: Bool = false, lineSpacing: CGFloat? = nil, saveRTL: Bool = false) -> Void {
        
        if width != 0 {
            constrainedWidth = width
        }

        toolTipRects.removeAll()
        
        calculateLayout(isBigEmoji: isBigEmoji, lineSpacing: lineSpacing, saveRTL: saveRTL)

        strokeRects.removeAll()
        
        if strokeLinks || !disableTooltips {
            let plainString = CFAttributedStringGetString(attributedString as CFAttributedString) as NSString
            attributedString.enumerateAttribute(NSAttributedString.Key.link, in: attributedString.range, options: NSAttributedString.EnumerationOptions(rawValue: 0), using: { value, range, stop in
                if let value = value {
                    let linkText = plainString.substring(with: range)
                    let needsTooltip = !disableTooltips && interactions.resolveLink(value) != linkText
                    if strokeLinks && interactions.isDomainLink(value, linkText) {
                        for line in lines {
                            let lineRange = NSIntersectionRange(range, line.range)
                            if lineRange.length != 0 {
                                var leftOffset: CGFloat = 0.0
                                if lineRange.location != line.range.location {
                                    leftOffset = floor(CTLineGetOffsetForStringIndex(line.line, lineRange.location, nil))
                                }
                                let rightOffset: CGFloat = ceil(CTLineGetOffsetForStringIndex(line.line, lineRange.location + lineRange.length, nil))
                                
                                let color: NSColor = attributedString.attribute(NSAttributedString.Key.foregroundColor, at: range.location, effectiveRange: nil) as? NSColor ?? presentation.colors.link
                                let rect = NSMakeRect(line.frame.minX + leftOffset + (line.isRTL ? layoutSize.width - line.frame.width : 0), line.frame.minY + 1, rightOffset - leftOffset, 1.0)
                                strokeRects.append((rect, color))
                                if needsTooltip {
                                    toolTipRects.append(NSMakeRect(rect.minX, line.frame.minY - line.frame.height, rightOffset - leftOffset, line.frame.height))
                                }
                            }
                        }
                    }
                    if needsTooltip {
                        for line in lines {
                            let lineRange = NSIntersectionRange(range, line.range)
                            if lineRange.length != 0 {
                                var leftOffset: CGFloat = 0.0
                                if lineRange.location != line.range.location {
                                    leftOffset = floor(CTLineGetOffsetForStringIndex(line.line, lineRange.location, nil))
                                }
                                let rightOffset: CGFloat = ceil(CTLineGetOffsetForStringIndex(line.line, lineRange.location + lineRange.length, nil))
                                
                                toolTipRects.append(NSMakeRect(line.frame.minX + leftOffset, line.frame.minY - line.frame.height, rightOffset - leftOffset, line.frame.height))
                            }
                        }
                    }
                }
            })
        }
        hexColorsRect.removeAll()
        attributedString.enumerateAttribute(NSAttributedString.Key.hexColorMark, in: attributedString.range, options: NSAttributedString.EnumerationOptions(rawValue: 0), using: { value, range, stop in
            if let color = value as? NSColor, let size = attributedString.attribute(.hexColorMarkDimensions, at: range.location, effectiveRange: nil) as? NSSize {
                for line in lines {
                    let lineRange = NSIntersectionRange(range, line.range)
                    if lineRange.length != 0 {
                        var leftOffset: CGFloat = 0
                        if lineRange.location != line.range.location {
                            leftOffset += floor(CTLineGetOffsetForStringIndex(line.line, lineRange.location, nil))
                        }
                        let rect = NSMakeRect(line.frame.minX + leftOffset + 10, line.frame.minY - (size.height - 7) + 2, size.width - 8, size.height - 8)
                        hexColorsRect.append((rect, color, attributedString.attributedSubstring(from: range).string))
                    }
                }
            }
            
        })
        
    }
    
    public func clearSelect() {
        self.selectedRange.range = NSMakeRange(NSNotFound, 0)
    }
    
    private func map(_ index: Int, byWord: Bool, forward: Bool) -> Int {
        if byWord {
            let range = self.attributedString.doubleClick(at: min(max(0, index), self.attributedString.string.length - 1))
            if forward {
                return range.max
            } else {
                return range.min
            }
        } else {
            return index
        }
    }
    

    public func selectedRange(startPoint:NSPoint, currentPoint:NSPoint, byWord: Bool = false) -> NSRange {

        
        var selectedRange:NSRange = NSMakeRange(NSNotFound, 0)
        
        if (currentPoint.x != -1 && currentPoint.y != -1 && !lines.isEmpty && startPoint.x != -1 && startPoint.y != -1) {
            
            
            let startSelectLineIndex = findIndex(location: startPoint)
            let currentSelectLineIndex = findIndex(location: currentPoint)
            
            
            let dif = abs(startSelectLineIndex - currentSelectLineIndex)
            let isReversed = currentSelectLineIndex < startSelectLineIndex
            var i = startSelectLineIndex
            while isReversed ? i >= currentSelectLineIndex : i <= currentSelectLineIndex {
                let line = lines[i].line
                
                let penOffset = CGFloat( CTLineGetPenOffsetForFlush(lines[i].line, lines[i].penFlush, Double(layoutSize.width)))
                
                let lineRange = CTLineGetStringRange(line)
                
                let sp = startPoint.offsetBy(dx: -penOffset - lines[i].frame.minX, dy: 0)
                let cp = currentPoint.offsetBy(dx: -penOffset - lines[i].frame.minX, dy: 0)
                
                var startIndex: CFIndex = CTLineGetStringIndexForPosition(line, sp)
                var endIndex: CFIndex = CTLineGetStringIndexForPosition(line, cp)
                
                if dif > 0 {
                    if i != currentSelectLineIndex {
                        endIndex = (lineRange.length + lineRange.location)
                    }
                    if i != startSelectLineIndex {
                        startIndex = lineRange.location
                    }
                    if isReversed {
                        if i == startSelectLineIndex {
                            endIndex = startIndex
                            startIndex = lineRange.location
                        }
                        if i == currentSelectLineIndex {
                            startIndex = endIndex
                            endIndex = (lineRange.length + lineRange.location)
                        }
                    }
                }
                if startIndex > endIndex {
                    startIndex = endIndex + startIndex
                    endIndex = startIndex - endIndex
                    startIndex = startIndex - endIndex
                }
                if abs(Int(startIndex) - Int(endIndex)) > 0 && (selectedRange.location == NSNotFound || selectedRange.location > startIndex) {
                    selectedRange.location = startIndex
                }
                selectedRange.length += (endIndex - startIndex)
                i +=  isReversed ? -1 : 1
            }
        }
        if selectedRange.location != NSNotFound, selectedRange.length > 0 {
            let start = selectedRange.min
            let end = selectedRange.max
            selectedRange.location = map(start, byWord: byWord, forward: false)
            selectedRange.length = map(end, byWord: byWord, forward: true) - selectedRange.location
        }
        
        return selectedRange
    }

    
    public func findIndex(location: NSPoint) -> Int {
        guard !lines.isEmpty else {
            return -1
        }
        if location.y == .greatestFiniteMagnitude {
            return lines.count - 1
        } else if location.y == 0 {
            return 0
        }
        var closestIndex = 0
        var closestYDistance = CGFloat.greatestFiniteMagnitude
        let point = location.offsetBy(dx: 0, dy: 5.0)
        for (index, line) in lines.enumerated() {
            let rect = line.frame
            let point = NSMakePoint(point.x, point.y + rect.height / 2)
            if rect.contains(point) {
                return index
            }
            let yDistance = abs(point.y - rect.midY)
            if yDistance < closestYDistance {
                closestYDistance = yDistance
                closestIndex = index
            }
        }
        let closestRect = lines[closestIndex].frame
        return closestRect == closestRect ? closestIndex : 0
    }

    public func isCurrentLine(pos:NSPoint, index:Int) -> Bool {
        
        let line = lines[index]
        var rect = line.frame
        
        var ascent:CGFloat = 0
        var descent:CGFloat = 0
        var leading:CGFloat = 0
        
        CTLineGetTypographicBounds(line.line, &ascent, &descent, &leading)
        
        rect.origin.y = rect.minY - rect.height + ceil(descent - leading)
        rect.size.height += ceil(descent - leading)
        
        if line.isBlocked {
            rect.size.height += 2
        }
        
        return (pos.y > rect.minY) && pos.y < rect.maxY
        
    }
    
    fileprivate func color(at point: NSPoint) -> (NSColor, String)? {
        
        for value in self.hexColorsRect {
            if NSPointInRect(point, value.0) {
                return (value.1, value.2)
            }
        }
        return nil
    }
    
    func spoiler(at point: NSPoint) -> Spoiler? {
        var result: Spoiler?
        enumerateSpoilerRects(true) { rect, spoiler in
            if rect.contains(point) {
                result = spoiler
                return false
            }
            return true
        }
        return result
    }

    func spoilerRects(_ checkRevealed: Bool = true) -> [(CGRect, Spoiler)] {
        var result: [(CGRect, Spoiler)] = []
        enumerateSpoilerRects(checkRevealed) { rect, spoiler in
            result.append((rect, spoiler))
            return true
        }
        return result
    }

    func spoilerRectFrames(_ checkRevealed: Bool = true) -> [CGRect] {
        var result: [CGRect] = []
        enumerateSpoilerRects(checkRevealed) { rect, _ in
            result.append(rect)
            return true
        }
        return result
    }

    @inline(__always)
    private func enumerateSpoilerRects(_ checkRevealed: Bool, _ body: (CGRect, Spoiler) -> Bool) {
        if spoilers.isEmpty || lines.isEmpty || (checkRevealed && !spoilers.contains(where: { !$0.isRevealed })) {
            return
        }
        for line in lines {
            var firstSpoiler = 0
            if spoilers.count > 8 {
                var end = spoilers.count
                while firstSpoiler < end {
                    let middle = firstSpoiler + (end - firstSpoiler) / 2
                    if spoilers[middle].range.upperBound < line.range.lowerBound {
                        firstSpoiler = middle + 1
                    } else {
                        end = middle
                    }
                }
            }
            var lineRect: CGRect?
            for index in firstSpoiler..<spoilers.count {
                let spoiler = spoilers[index]
                if spoiler.range.lowerBound > line.range.upperBound {
                    break
                }
                if checkRevealed && spoiler.isRevealed {
                    continue
                }
                guard let spoilerRange = spoiler.range.intersection(line.range) else {
                    continue
                }
                let baseRect: CGRect
                if let lineRect {
                    baseRect = lineRect
                } else {
                    var descent: CGFloat = 0
                    var leading: CGFloat = 0
                    _ = CTLineGetTypographicBounds(line.line, nil, &descent, &leading)
                    var rect = line.frame
                    rect.origin.y = rect.minY - rect.height + 2
                    rect.size.height += ceil(descent - leading)
                    lineRect = rect
                    baseRect = rect
                }
                func rect(for range: NSRange) -> CGRect {
                    let startOffset = CTLineGetOffsetForStringIndex(line.line, range.lowerBound, nil)
                    let endOffset = CTLineGetOffsetForStringIndex(line.line, range.upperBound, nil)
                    var rect = baseRect
                    rect.size.width = abs(endOffset - startOffset)
                    rect.origin.x = min(startOffset, endOffset) + line.frame.origin.x
                    if line.isRTL {
                        rect.origin.x += layoutSize.width - line.frame.width
                    }
                    return rect
                }
                if let range = spoilerRange.intersection(selectedRange.range) {
                    if !body(rect(for: NSMakeRange(spoiler.range.lowerBound, range.lowerBound - spoiler.range.lowerBound)), spoiler) { return }
                    if !body(rect(for: NSMakeRange(spoiler.range.upperBound, range.upperBound - spoiler.range.upperBound)), spoiler) { return }
                } else {
                    if !body(rect(for: spoilerRange), spoiler) { return }
                }
            }
        }
    }

    public func link(at point:NSPoint) -> (Any, LinkType, NSRange, NSRect)? {

        let index = findIndex(location: point)

        guard index != -1, !lines.isEmpty else {
            return nil
        }

        let line = lines[index]
        var ascent:CGFloat = 0
        var descent:CGFloat = 0
        var leading:CGFloat = 0

        let width:CGFloat = CGFloat(CTLineGetTypographicBounds(line.line, &ascent, &descent, &leading));

        var penOffset = CGFloat(CTLineGetPenOffsetForFlush(line.line, line.penFlush, Double(layoutSize.width)))
        if penFlush == 0.5, line.penFlush != 0.5 { penOffset = 0 }
        if line.penFlush == 1, let size = cutout?.topRight, line.frame.maxY <= size.height {
            penOffset -= size.width
        }
        if line.isRTL && blockQuotes.contains(where: { $0.frame.contains(line.frame.origin) }) {
            penOffset -= 20 + 4 * 2
        }
        penOffset += line.frame.minX
        var point = point
        point.x -= penOffset

        if  width > point.x, point.x >= 0 {
            var pos = CTLineGetStringIndexForPosition(line.line, point);
            pos = min(max(0,pos),attributedString.length - 1)
            var range:NSRange = NSMakeRange(NSNotFound, 0)
            let attrs = attributedString.attributes(at: pos, effectiveRange: &range)

            let link:Any? = attrs[NSAttributedString.Key.link]
            if let link = link {
                let startOffset = CTLineGetOffsetForStringIndex(line.line, range.location, nil);
                let endOffset = CTLineGetOffsetForStringIndex(line.line, range.location + range.length, nil);
                return (link, interactions.makeLinkType((link, attributedString.attributedSubstring(from: range).string)), range, NSMakeRect(startOffset + penOffset, line.frame.minY, endOffset - startOffset, ceil(ascent + ceil(descent) + leading)))
            }
        }
        return nil
    }

    public func formattedDate(at point: NSPoint) -> (TextViewFormattedDateData, NSRect)? {
        let index = findIndex(location: point)

        guard index != -1, !lines.isEmpty else {
            return nil
        }

        let line = lines[index]
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0

        let width: CGFloat = CGFloat(CTLineGetTypographicBounds(line.line, &ascent, &descent, &leading))

        var point = point
        point.x -= ((layoutSize.width - line.frame.width) * line.penFlush)

        if width > point.x, point.x >= 0 {
            var pos = CTLineGetStringIndexForPosition(line.line, point)
            pos = min(max(0, pos), attributedString.length - 1)
            var range: NSRange = NSMakeRange(NSNotFound, 0)
            let attrs = attributedString.attributes(at: pos, effectiveRange: &range)

            if let data = attrs[TextInputAttributes.formattedDate] as? TextViewFormattedDateData {
                let startOffset = CTLineGetOffsetForStringIndex(line.line, range.location, nil)
                let endOffset = CTLineGetOffsetForStringIndex(line.line, range.location + range.length, nil)
                return (data, NSMakeRect(startOffset, line.frame.minY, endOffset - startOffset, ceil(ascent + ceil(descent) + leading)))
            }
        }
        return nil
    }
    
    public func block(at point:NSPoint) -> NSRange? {
        
        let index = findIndex(location: point)
        
        guard index != -1, !lines.isEmpty else {
            return nil
        }
        
        let line = lines[index]
        var ascent:CGFloat = 0
        var descent:CGFloat = 0
        var leading:CGFloat = 0
        
        let width:CGFloat = CGFloat(CTLineGetTypographicBounds(line.line, &ascent, &descent, &leading));
        
        var point = point
        
         //point.x -= floorToScreenPixels(System.backingScale, (frame.width - line.frame.width) / 2)
        
        
//        var penOffset = CGFloat( CTLineGetPenOffsetForFlush(line.line, line.penFlush, Double(frame.width))) + line.frame.minX
//        if layout.penFlush == 0.5, line.penFlush != 0.5 {
//            penOffset = startPosition.x
//        } else if layout.penFlush == 0.0 {
//            penOffset = startPosition.x
//        }
        
        point.x -= ((layoutSize.width - line.frame.width) * line.penFlush)

        
        if  width > point.x, point.x >= 0 {
            var pos = CTLineGetStringIndexForPosition(line.line, point);
            pos = min(max(0,pos),attributedString.length - 1)
            var range:NSRange = NSMakeRange(NSNotFound, 0)
            let attrs = attributedString.attributes(at: pos, effectiveRange: &range)
            
            if let _ =  attrs[TextInputAttributes.code] {
                return range
            }
        }
        return nil
    }
    
    public func findCharacterIndex(at point:NSPoint) -> Int {
        let index = findIndex(location: point)
        
        guard index != -1 else {
            return index
        }
        
        let line = lines[index]
        let width:CGFloat = CGFloat(CTLineGetTypographicBounds(line.line, nil, nil, nil));
        if width > point.x {
            var charIndex = Int(CTLineGetStringIndexForPosition(line.line, point))
            
            let ctRange = CTLineGetStringRange(line.line)
            charIndex = (charIndex - ctRange.location) + line.range.location
            
            return charIndex == attributedString.length ? charIndex - 1 : charIndex
        }
        return -1
    }
    
    public func offset(for index: Int) -> CGFloat? {
        let line = self.lines.first(where: {
            $0.range.indexIn(index)
        })
        if let line = line {
            return CTLineGetOffsetForStringIndex(line.line, index, nil)
        }
        return nil
    }
    
    public func selectAll(at point:NSPoint) -> Void {
        
        let startIndex = findCharacterIndex(at: point)
        if startIndex == -1 {
            return
        }
       
        var blockRange: NSRange = NSMakeRange(NSNotFound, 0)
        var firstIndex: Int = startIndex
        var lastIndex: Int = startIndex
        
        var firstFound: Bool = false
        var lastFound: Bool = false
        
        let block = attributedString.attribute(TextInputAttributes.quote, at: firstIndex, effectiveRange: &blockRange) as? TextViewBlockQuoteData
        
        attributedString.enumerateAttribute(TextInputAttributes.quote, in: attributedString.range, using: { value, range, _ in
            if value as? TextViewBlockQuoteData === block {
                blockRange.location = min(range.location, blockRange.location)
                blockRange.length += range.length
            }
        })

        if blockRange.location != NSNotFound, block != nil {
            firstIndex = blockRange.min - 1
            lastIndex = blockRange.max + 1
            firstFound = true
            lastFound = true
        }
        
        while (firstIndex > 0 && !firstFound) || (lastIndex < self.attributedString.length - 1 && !lastFound) {
            
            let firstSymbol = self.attributedString.string.nsstring.substring(with: NSMakeRange(firstIndex, 1))
            let lastSymbol = self.attributedString.string.nsstring.substring(with: NSMakeRange(lastIndex, 1))
                        
            
            firstFound = firstSymbol == "\n"
            lastFound = lastSymbol == "\n"
                            
            if firstIndex > 0, !firstFound {
                firstIndex -= 1
            }
            if lastIndex < self.attributedString.length - 1, !lastFound {
                lastIndex += 1
            }
        }
        if lastFound {
           lastIndex = max(min(lastIndex, self.attributedString.length - 1) - 1, 0)
        }
        if firstFound {
           firstIndex = min(firstIndex + 1, self.attributedString.length - 1)
       }
        let location = max(0, min(firstIndex, self.attributedString.length))
        let length = max(0, min((lastIndex + 1) - firstIndex, self.attributedString.length - location))
        self.selectedRange = TextSelectedRange(range: NSMakeRange(location, length), color: selectText, def: true)

    }

    public func selectWord(at point:NSPoint) -> Void {
        
        if selectWholeText {
            self.selectedRange = TextSelectedRange(range: attributedString.range, color: selectText, def: true)
            return
        }
        
        let startIndex = findCharacterIndex(at: point)
        if startIndex == -1 {
            return
        }
        var prev = startIndex
        var next = startIndex
        var range = NSMakeRange(startIndex, 1)
        let char:NSString = attributedString.string.nsstring.substring(with: range) as NSString
        var effectiveRange:NSRange = NSMakeRange(NSNotFound, 0)
        let check = attributedString.attribute(NSAttributedString.Key.link, at: range.location, effectiveRange: &effectiveRange)
        if check != nil && effectiveRange.location != NSNotFound {
            self.selectedRange = TextSelectedRange(range: effectiveRange, color: selectText, def: true)
            return
        }
        if char == "" {
            self.selectedRange = TextSelectedRange(color: selectText)
            return
        }
        let string:NSString = attributedString.string.nsstring
        let tidyChar = char.trimmingCharacters(in: NSCharacterSet.alphanumerics)
        let valid:Bool = tidyChar == "" || tidyChar == "_" || tidyChar == "\u{FFFD}"
        
        var inBlockRange: NSRange = NSMakeRange(0, 0)
        let inBlock = attributedString.attribute(TextInputAttributes.quote, at: startIndex, effectiveRange: &inBlockRange) as? TextViewBlockQuoteData
        
        attributedString.enumerateAttribute(TextInputAttributes.quote, in: attributedString.range, using: { value, range, _ in
            if value as? TextViewBlockQuoteData === inBlock {
                inBlockRange.location = min(range.location, inBlockRange.location)
                inBlockRange.length += range.length
            }
        })
        
        
        if let _ = inBlock {
            range = inBlockRange
        } else {
            while valid {
                let prevChar = string.substring(with: NSMakeRange(prev, 1))
                let nextChar = string.substring(with: NSMakeRange(next, 1))
                
                
                let prevBlock = attributedString.attribute(.init("Attribute__Blockquote"), at: prev, effectiveRange: nil)
                let nextBlock = attributedString.attribute(.init("Attribute__Blockquote"), at: next, effectiveRange: nil)
                
               
                
                let tidyPrev = prevChar.trimmingCharacters(in: NSCharacterSet.alphanumerics)
                let tidyNext = nextChar.trimmingCharacters(in: NSCharacterSet.alphanumerics)
                var prevValid:Bool = (tidyPrev == "" || tidyPrev == "_" || tidyPrev == "\u{FFFD}") && prevBlock == nil
                var nextValid:Bool = (tidyNext == "" || tidyNext == "_" || tidyNext == "\u{FFFD}") && nextBlock == nil
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
                    let nextChar = string.substring(with: NSMakeRange(next, 1))
                    let nextTidy = nextChar.trimmingCharacters(in: NSCharacterSet.alphanumerics)
                    if nextTidy == "" || nextTidy == "_" || nextTidy == "\u{FFFD}" {
                        range.length += 1
                    }
                }
                if !prevValid && !nextValid {
                    break
                }
                if prev == 0 && !nextValid {
                    break
                }
            }
        }
        self.selectedRange = TextSelectedRange(range: NSMakeRange(max(range.location, 0), min(max(range.length, 0), string.length)), color: selectText, def: true)
    }
    

}

public func ==(lhs:TextViewLayout, rhs:TextViewLayout) -> Bool {
    return lhs.constrainedWidth == rhs.constrainedWidth && lhs.attributedString.isEqual(to: rhs.attributedString) && lhs.selectedRange == rhs.selectedRange && lhs.maximumNumberOfLines == rhs.maximumNumberOfLines && lhs.cutout == rhs.cutout && lhs.truncationType == rhs.truncationType && lhs.constrainedWidth == rhs.constrainedWidth
}

public enum CursorSelectAlignment {
    case min(Int)
    case max(Int)
}

public struct TextSelectedRange: Equatable {
    
    
    public var range:NSRange = NSMakeRange(NSNotFound, 0)
        
    public var color:NSColor = presentation.colors.selectText
    public var def:Bool = true
    
    public init(range: NSRange = NSMakeRange(NSNotFound, 0), color: NSColor = presentation.colors.selectText, def: Bool = true, cursorAlignment: CursorSelectAlignment = .min(0)) {
        self.range = range
        self.color = color
        self.def = def
        self.cursorAlignment = cursorAlignment
    }
    
    public var cursorAlignment: CursorSelectAlignment = .min(0)
    
    public var hasSelectText:Bool {
        return range.location != NSNotFound
    }
}

public func ==(lhs:TextSelectedRange, rhs:TextSelectedRange) -> Bool {
    return lhs.def == rhs.def && lhs.range.location == rhs.range.location && lhs.range.length == rhs.range.length && lhs.color.hexString == rhs.color.hexString
}

//private extension TextView : NSMenuDelegate {
//    
//}

private func drawTextViewContent(_ layout: TextViewLayout?, in ctx: CGContext, size: NSSize, drawingSize: NSSize, backingScaleFactor: CGFloat, backgroundColor: NSColor = .clear, disableBackgroundDrawing: Bool = true, hasBackground: Bool = false, isSelectable: Bool = false, isKeyWindow: Bool = false, clearExceptRevealed: Bool = false, inAnimation: Bool = false, canDrawBlocks: Bool = true) -> [(NSRect, NSRange)] {
    var blockHeaderRects: [(NSRect, NSRange)] = []
    if let layout {

        ctx.setAllowsFontSubpixelPositioning(true)
        ctx.setShouldSubpixelPositionFonts(true)
        if !System.supportsTransparentFontDrawing {
            ctx.setAllowsAntialiasing(true)

            ctx.setAllowsFontSmoothing(backingScaleFactor == 1.0)
            ctx.setShouldSmoothFonts(backingScaleFactor == 1.0)

            if backingScaleFactor == 1.0 && !disableBackgroundDrawing {
                ctx.setFillColor(backgroundColor.cgColor)
                for line in layout.lines {
                    ctx.fill(NSMakeRect(0, line.frame.minY - line.frame.height - 2, line.frame.width, line.frame.height + 6))
                }
            }
        } else {
            ctx.setAllowsAntialiasing(true)
            ctx.setShouldAntialias(true)
            ctx.setAllowsFontSmoothing(backingScaleFactor == 1.0)
            ctx.setShouldSmoothFonts(backingScaleFactor == 1.0)
        }

        if clearExceptRevealed {
            let path = CGMutablePath()

            for rect in layout.spoilerRectFrames(false) {
                path.addRect(rect)
            }
            ctx.addPath(path)
            ctx.clip()
        }

        if let image = layout.blockImage.1, !hasBackground {
            ctx.draw(image, in: NSMakeRect(layout.blockImage.0.x, layout.blockImage.0.y, image.backingSize.width, image.backingSize.height))
        }

        let firstSelection = isSelectable && layout.selectedRange.range.location != NSNotFound ? -1 : 0
        for selectionIndex in firstSelection ..< layout.additionalSelections.count {
            let range = selectionIndex == -1 ? (layout.selectedRange, true) : (layout.additionalSelections[selectionIndex], false)
            if range.0.range.location != NSNotFound && !layout.lines.isEmpty && (range.1 && isSelectable || !range.1) {

                var lessRange = range.0.range

                let lines:[TextViewLine] = layout.lines

                let beginIndex:Int = 0
                let endIndex:Int = layout.lines.count - 1

                let isReversed = endIndex < beginIndex

                var i:Int = beginIndex

                while isReversed ? i >= endIndex : i <= endIndex {

                    let line = lines[i].line

                    var rect:NSRect = lines[i].frame
                    let lineRange = lines[i].lineRange

                    var beginLineIndex:CFIndex = 0
                    var endLineIndex:CFIndex = 0

                    if let _ = lineRange.intersection(lessRange){
                        let penOffset = CGFloat(CTLineGetPenOffsetForFlush(line, lines[i].penFlush, Double(size.width)))

                        beginLineIndex = lessRange.location
                        let max = lineRange.length + lineRange.location
                        let maxSelect = max - beginLineIndex

                        let selectLength = min(maxSelect,lessRange.length)

                        lessRange.length-=selectLength
                        lessRange.location+=selectLength

                        endLineIndex = min(beginLineIndex + selectLength, lineRange.max)

                        var ascent:CGFloat = 0
                        var descent:CGFloat = 0
                        var leading:CGFloat = 0

                        var width:CGFloat = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading));

                        let startOffset = CTLineGetOffsetForStringIndex(line, beginLineIndex, nil);
                        var endOffset = CTLineGetOffsetForStringIndex(line, endLineIndex, nil);

                        if beginLineIndex < endLineIndex {
                            var index = endLineIndex - 1
                            while endOffset == 0 && index > 0 {
                                endOffset = CTLineGetOffsetForStringIndex(line, index, nil);
                                index -= 1
                            }
                        }

                        width = endOffset - startOffset;

                        if beginLineIndex == -1 {
                            beginLineIndex = 0
                        } else if beginLineIndex >= layout.attributedString.length {
                            beginLineIndex = layout.attributedString.length - 1
                        }

                        rect.size.width = width

                        rect.origin.x = penOffset + startOffset

                        rect.origin.y = rect.minY - rect.height + rect.height * 0.12
                        let insideBlock = layout.blockQuotes.first(where: { block in
                            if block.frame.contains(rect.origin) {
                                return true
                            } else {
                                return false
                            }
                        })
                        if let _ = insideBlock {
                            rect.origin.x += 4 * 2
                        }
                        if let _ = insideBlock, lines[i].isRTL {
                            rect.origin.x -= 20 + 4 * 2
                        }

                        rect.size.height += ceil(descent - leading)
                        let color:NSColor = isKeyWindow || !range.1 ? range.0.color : NSColor.lightGray

                        ctx.setFillColor(color.cgColor)
                        ctx.fill(rect)

                    }

                    i += isReversed ? -1 : 1

                }

            }
        }

        let startPosition = CGRect(origin: .zero, size: size).focus(layout.layoutSize).origin

        ctx.textMatrix = CGAffineTransform(scaleX: 1.0, y: -1.0)

        if canDrawBlocks {
            let blockAreaIsCleared = System.supportsTransparentFontDrawing && !clearExceptRevealed && (layout.blockImage.1 == nil || hasBackground) && !(isSelectable && layout.selectedRange.range.location != NSNotFound) && !layout.additionalSelections.contains(where: { $0.range.location != NSNotFound })
            for blockQuote in layout.blockQuotes {
                let radius: CGFloat = 3.0
                let lineWidth: CGFloat = 3.0

                let blockFrame = blockQuote.frame
                let blockColor = blockQuote.isCode ? blockQuote.colors.tertiary ?? blockQuote.colors.main : blockQuote.colors.main
                let tintColor = blockQuote.colors.main
                let secondaryTintColor = blockQuote.colors.secondary
                let tertiaryTintColor = blockQuote.colors.tertiary

                if blockAreaIsCleared {
                    fillBlockBackgroundOnClearedArea(ctx, frame: blockFrame, radius: radius, color: blockColor.withAlphaComponent(blockQuote.isCode ? 0.25 : 0.1).cgColor)
                } else {
                    ctx.setFillColor(blockColor.withAlphaComponent(blockQuote.isCode ? 0.25 : 0.1).cgColor)
                    ctx.addPath(CGPath(roundedRect: blockFrame, cornerWidth: radius, cornerHeight: radius, transform: nil))
                    ctx.fillPath()
                }

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
                    blockHeaderRects.append((rect, blockQuote.range))
                    ctx.drawRoundedRect(rect: rect, topLeftRadius: radius, topRightRadius: radius)

                    header.1.draw(CGRect(x: blockFrame.minX + 8, y: blockFrame.minY + (headerHeight - header.0.size.height) / 2 - 1, width: header.0.size.width, height: header.0.size.height), in: ctx, backingScaleFactor: backingScaleFactor, backgroundColor: .clear)
                    if let image = codeCopyIcon(blockQuote.colors.main) {
                        ctx.draw(image, in: CGRect(origin: NSMakePoint(blockFrame.width - image.backingSize.width - 3, blockFrame.minY + (headerHeight - image.backingSize.height) / 2), size: image.backingSize))
                    }
                }
            }
        }

        let spoilerRects = layout.spoilerRectFrames(!inAnimation)
        if !spoilerRects.isEmpty {
            ctx.beginPath()
            ctx.addRects(spoilerRects)
            ctx.closePath()
            ctx.addRect(CGRect(x: 0, y: 0, width: drawingSize.width, height: drawingSize.height))
            ctx.clip(using: .evenOdd)
        }

        for stroke in layout.strokeRects {
            ctx.setFillColor(stroke.1.cgColor)
            ctx.fill(stroke.0)
        }

        for hexColor in layout.hexColorsRect {
            ctx.setFillColor(hexColor.1.cgColor)
            ctx.fill(hexColor.0)
        }

        var drawnGlyphCount: Int = 0
        for i in 0 ..< layout.lines.count {
            let line = layout.lines[i]

            if let maxGlyphDraw = layout.maxGlyphDrawCount, drawnGlyphCount >= maxGlyphDraw {
                break
            }

            var penOffset = CGFloat( CTLineGetPenOffsetForFlush(line.line, line.penFlush, Double(size.width)))
            if layout.penFlush == 0.5, line.penFlush != 0.5 {
                penOffset = startPosition.x
            }
            if line.penFlush == 1.0 {
                if let size = layout.cutout?.topRight {
                    if line.frame.maxY <= size.height {
                        penOffset -= size.width
                    }
                }
            }

            var additionY: CGFloat = 0
            if layout.isBigEmoji {
                additionY -= 4
            }

            if line.isRTL && layout.blockQuotes.contains(where: { $0.frame.contains(line.frame.origin) }) {
                penOffset -= 20 + 4 * 2
            }

            let textPosition = CGPoint(x: penOffset + line.frame.minX, y: startPosition.y + line.frame.minY + additionY)

            drawTextLineRuns(line.line, in: ctx, at: textPosition, maximumGlyphCount: layout.maxGlyphDrawCount, drawnGlyphCount: &drawnGlyphCount)
            let decorationOffsetX = penOffset + line.frame.minX
            for strikethrough in line.strikethrough {
                ctx.setFillColor(strikethrough.color.cgColor)
                ctx.fill(NSMakeRect(decorationOffsetX + strikethrough.frame.minX, line.frame.minY - strikethrough.frame.height / 2, strikethrough.frame.width, .borderSize))
            }
            for underline in line.underlines {
                ctx.setFillColor(underline.color.cgColor)
                ctx.fill(NSMakeRect(decorationOffsetX + underline.frame.minX, line.frame.minY + 1, underline.frame.width, .borderSize))
            }

        }

    }
    return blockHeaderRects
}


public final class TextViewLayer: SimpleLayer {
    public private(set) var textLayout: TextViewLayout?
    public var textSize: NSSize = .zero {
        didSet {
            if textSize != oldValue {
                setNeedsDisplay()
            }
        }
    }
    public var canDrawBlocks: Bool = true {
        didSet {
            if canDrawBlocks != oldValue {
                setNeedsDisplay()
            }
        }
    }
    public var isTextSelectable: Bool = false {
        didSet {
            if isTextSelectable != oldValue { setNeedsDisplay() }
        }
    }
    public var isKeyWindow: Bool = false {
        didSet {
            if isKeyWindow != oldValue && isTextSelectable && textLayout?.selectedRange.hasSelectText == true { setNeedsDisplay() }
        }
    }
    fileprivate var drawer: ((CGContext) -> Void)?

    public override init() {
        super.init()
    }

    public override init(layer: Any) {
        super.init(layer: layer)
        if let layer = layer as? TextViewLayer {
            contentsScale = layer.contentsScale
            textLayout = layer.textLayout
            textSize = layer.textSize
            canDrawBlocks = layer.canDrawBlocks
            isTextSelectable = layer.isTextSelectable
            isKeyWindow = layer.isKeyWindow
        }
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(_ layout: TextViewLayout?, size: NSSize? = nil) {
        textLayout = layout
        if let size {
            textSize = size
        } else if let layout {
            textSize = NSSize(width: layout.layoutSize.width + layout.insets.width, height: layout.layoutSize.height + layout.insets.height)
        } else {
            textSize = .zero
        }
        setNeedsDisplay()
    }

    public override func draw(in ctx: CGContext) {
        if let drawer {
            drawer(ctx)
        } else {
            _ = drawTextViewContent(textLayout, in: ctx, size: textSize, drawingSize: frame.size, backingScaleFactor: contentsScale, isSelectable: isTextSelectable, isKeyWindow: isKeyWindow, canDrawBlocks: canDrawBlocks)
        }
    }
}

private final class TextViewMenuState: Disposable {
    private(set) var version: UInt64 = 0
    private(set) var text: NSAttributedString?
    private weak var layout: TextViewLayout?
    weak var presentedMenu: ContextMenu?
    private var disposable: Disposable?
    private var active = false
    private var disposed = false

    func isCurrent(_ version: UInt64) -> Bool {
        return !disposed && self.version == version
    }

    func matches(_ layout: TextViewLayout?) -> Bool {
        guard active, let layout = layout, self.layout === layout, let text = text else { return false }
        return text === layout.attributedString || text.isEqual(to: layout.attributedString)
    }

    func begin(_ layout: TextViewLayout) -> UInt64 {
        let version = cancel()
        guard isCurrent(version) else { return version }
        self.layout = layout
        text = layout.attributedString.copy() as? NSAttributedString
        active = true
        return version
    }

    @discardableResult func cancel() -> UInt64 {
        version &+= 1
        let version = version
        presentedMenu = nil
        clearPending()
        return version
    }

    func cancelIfInvalid(_ layout: TextViewLayout?) {
        if active && !matches(layout) {
            cancel()
        }
    }

    func install(_ disposable: Disposable, version: UInt64) {
        guard isCurrent(version), active else {
            disposable.dispose()
            return
        }
        let previous = self.disposable
        self.disposable = disposable
        previous?.dispose()
    }

    func finish(_ version: UInt64) {
        if isCurrent(version) { clearPending() }
    }

    private func clearPending() {
        let previous = disposable
        let previousText = text
        disposable = nil
        text = nil
        layout = nil
        active = false
        previous?.dispose()
        withExtendedLifetime(previousText) {}
    }

    func dispose() {
        disposed = true
        cancel()
    }
}

open class TextView: Control, NSViewToolTipOwner, ViewDisplayDelegate {
    
    
    public func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
        
        guard let layout = self.textLayout else { return "" }
        
        if let link = layout.link(at: point), let resolved = layout.interactions.resolveLink(link.0)?.removingPercentEncoding {
            return resolved.prefixWithDots(70)
        }
        
        return ""

    }
    
    private var installedToolTipRects: [NSRect]?

    open override func addToolTip(_ rect: NSRect, owner: Any, userData data: UnsafeMutableRawPointer?) -> NSView.ToolTipTag {
        installedToolTipRects = nil
        return super.addToolTip(rect, owner: owner, userData: data)
    }

    open override func removeToolTip(_ tag: NSView.ToolTipTag) {
        installedToolTipRects = nil
        super.removeToolTip(tag)
    }

    open override func removeAllToolTips() {
        installedToolTipRects = nil
        super.removeAllToolTips()
    }

    private var inkViews: [InvisibleInkDustView] = []
    private final class EmbeddedMaskSnapshot {
        let contentsGravity: CALayerContentsGravity
        let contentsScale: CGFloat
        let frame: CGRect
        let contents: Any?

        init(_ mask: CALayer) {
            contentsGravity = mask.contentsGravity
            contentsScale = System.backingScale
            frame = mask.frame
            contents = mask.contents
        }

        func makeLayer() -> SimpleLayer {
            let layer = SimpleLayer()
            layer.contentsGravity = contentsGravity
            layer.contentsScale = contentsScale
            layer.frame = frame
            layer.contents = contents
            return layer
        }
    }

    private var currentEmbeddedContainer: SimpleLayer?
    private var pendingEmbeddedMask: EmbeddedMaskSnapshot?
    private var embeddedContainerBelowText = false

    public var embeddedContainer: SimpleLayer {
        if let currentEmbeddedContainer { return currentEmbeddedContainer }
        let container = SimpleLayer()
        container.masksToBounds = false
        container.frame = bounds
        container.contentsScale = backingScaleFactor
        container.mask = pendingEmbeddedMask?.makeLayer()
        pendingEmbeddedMask = nil
        currentEmbeddedContainer = container
        if let parent = drawLayer.superlayer ?? layer {
            if drawLayer.superlayer === parent {
                if embeddedContainerBelowText {
                    parent.insertSublayer(container, below: drawLayer)
                } else {
                    parent.insertSublayer(container, above: drawLayer)
                }
            } else {
                parent.addSublayer(container)
            }
        }
        return container
    }
    
    private var blockHeaderRects: [(NSRect, NSRange)] = []
    
    private var shimmerEffect: ShimmerView?
    private var shimmerMask: SimpleLayer?
    
    public var selectionWasCleared: Bool = false

    private var clearExceptRevealed: Bool = false
    private var inAnimation: Bool = false {
        didSet {
            setNeedsDisplayLayer()
        }
    }
    
    private var visualEffect: VisualEffect? = nil

    private var textView: View? = nil
    private let drawLayer: TextViewLayer = TextViewLayer()
    private var blockMask: SimpleLayer?
    
    public var lockDrawingLayer: Bool = false
    
    
    var hasBackground: Bool {
        return blurBackground != nil
    }
    
    public var blurBackground: NSColor? = nil {
        didSet {
            updateBackgroundBlur()
            if hasBackground {
                self.backgroundColor = .clear
            }
        }
    }
    
    public var canDrawBlocks: Bool = true {
        didSet {
            drawLayer.needsDisplay()
        }
    }
    
    private var menuDisposable: TextViewMenuState?

    private var longHoverTimer: SwiftSignalKit.Timer?
    private var longHoverRange = NSRange(location: NSNotFound, length: 0)
    private var longHoverDisposable: Disposable?
    private var longHoverText: NSAttributedString?

    private(set) public var textLayout:TextViewLayout? {
        didSet {
            if oldValue !== textLayout || (longHoverText != nil && !matchesLongHoverText(textLayout)) {
                cancelLongHoverTimer()
            }
            menuDisposable?.cancelIfInvalid(textLayout)
        }
    }
    
    private var beginSelect:NSPoint = NSZeroPoint
    private var endSelect:NSPoint = NSZeroPoint
    
    public var canBeResponder:Bool = true
    
    
    public var isSelectable:Bool = true {
        didSet {
            if oldValue != isSelectable {
                self.setNeedsDisplayLayer()
            }
        }
    }
    public var onlyTextIsInteractive: Bool = false

    
    
    public override init() {
        super.init();
        
        initialize()
//        wantsLayer = false
//        self.layer?.delegate = nil
    }

    public override var isFlipped: Bool {
        return true
    }
    
    private func initialize() {
        layer?.disableActions()
        self.style = ControlStyle(backgroundColor: .clear)
        
        self.layer?.addSublayer(drawLayer)
        self.drawLayer.drawer = { [weak self] ctx in
            guard let `self` = self else {
                return
            }
            self.draw(self.drawLayer, in: ctx)
        }
        
        if let currentEmbeddedContainer { self.layer?.addSublayer(currentEmbeddedContainer) }
        self.layer?.masksToBounds = false

    }

    public required init(frame frameRect: NSRect) {
        super.init(frame:frameRect)
        initialize()
    }
    private var _disableBackgroundDrawing: Bool = false
    public var disableBackgroundDrawing: Bool {
        set {
            _disableBackgroundDrawing = newValue
        }
        get {
            return _disableBackgroundDrawing || hasBackground
        }
    }


    public override var wantsUpdateLayer: Bool {
        return true
    }
    
    public var drawingLayer: CALayer {
        return drawLayer
    }
    
    public func set(mask: CALayer?) {
        self.drawLayer.mask = mask
        if let container = currentEmbeddedContainer {
            if let mask {
                let copy = SimpleLayer()
                copy.contentsGravity = mask.contentsGravity
                copy.frame = mask.frame
                copy.contents = mask.contents
                container.mask = copy
            } else {
                container.mask = nil
            }
        } else {
            pendingEmbeddedMask = mask.map(EmbeddedMaskSnapshot.init)
        }
    }

    public override func draw(_ layer: CALayer, in ctx: CGContext) {
        guard drawingLayer == layer else {
            blockHeaderRects = []
            return
        }
        lastDrawnSelectionState = currentSelectionState
        blockHeaderRects = drawTextViewContent(textLayout, in: ctx, size: frame.size, drawingSize: layer.frame.size, backingScaleFactor: backingScaleFactor, backgroundColor: backgroundColor, disableBackgroundDrawing: disableBackgroundDrawing, hasBackground: hasBackground, isSelectable: isSelectable, isKeyWindow: window?.isKeyWindow == true, clearExceptRevealed: clearExceptRevealed, inAnimation: inAnimation, canDrawBlocks: canDrawBlocks)
    }

    private func acceptsMenuRequest(_ state: TextViewMenuState, version: UInt64) -> Bool {
        guard menuDisposable === state, state.isCurrent(version) else { return false }
        guard state.matches(textLayout) else {
            state.cancel()
            return false
        }
        return true
    }

    private func presentTextMenu(_ menu: ContextMenu, event: NSEvent, state: TextViewMenuState, version: UInt64) {
        guard acceptsMenuRequest(state, version: version) else { return }
        state.presentedMenu = menu
        menu.onClose = { [weak state, weak menu] in
            guard let state = state, let menu = menu, state.isCurrent(version), state.presentedMenu === menu else { return }
            state.cancel()
        }
        AppMenu.show(menu: menu, event: event, for: self)
    }

    open override func rightMouseDown(with event: NSEvent) {
        let previousState = menuDisposable
        let cancelledVersion = previousState?.cancel()
        guard menuDisposable === previousState, previousState?.version == cancelledVersion else { return }
        if let layout = textLayout, userInteractionEnabled, layout.mayItems, mouseInside() {
            let location = convert(event.locationInWindow, from: nil)
            if !layout.selectedRange.hasSelectText && (!layout.alwaysStaticItems || layout.link(at: location) != nil) {
                layout.selectWord(at: location)
            }
            self.setNeedsDisplayLayer()
            if (layout.selectedRange.hasSelectText && isSelectable) || !layout.alwaysStaticItems {
                guard textLayout === layout, menuDisposable === previousState, previousState?.version == cancelledVersion else { return }
                let state: TextViewMenuState
                if let current = menuDisposable {
                    state = current
                } else {
                    state = TextViewMenuState()
                    menuDisposable = state
                }
                let version = state.begin(layout)
                guard acceptsMenuRequest(state, version: version) else { return }
                let link = layout.link(at: convert(event.locationInWindow, from: nil))
                guard acceptsMenuRequest(state, version: version) else { return }
                let items = layout.interactions.menuItems?(link?.1)
                guard acceptsMenuRequest(state, version: version) else { return }
                let window = layout.interactions.topWindow?() ?? .single(nil)
                guard acceptsMenuRequest(state, version: version) else { return }
                let disposable: Disposable
                if let items = items {
                    disposable = combineLatest(queue: .mainQueue(), items, window).start(next: { [weak self, weak state] items, topWindow in
                        guard let self = self, let state = state, self.acceptsMenuRequest(state, version: version) else { return }
                        let menu = ContextMenu()
                        for item in items { menu.addItem(item) }
                        menu.topWindow = topWindow
                        self.presentTextMenu(menu, event: event, state: state, version: version)
                    }, completed: { [weak state] in state?.finish(version) })
                } else {
                    disposable = (window |> deliverOnMainQueue).start(next: { [weak self, weak state, weak layout] topWindow in
                        guard let self = self, let state = state, let layout = layout, self.acceptsMenuRequest(state, version: version), let text = state.text else { return }
                        let link = layout.link(at: location)
                        let resolved = link.flatMap { layout.interactions.resolveLink($0.0) }
                        guard self.acceptsMenuRequest(state, version: version) else { return }
                        let title = link.map { layout.interactions.localizeLinkCopy($0.1) } ?? localizedString("Text.Copy")
                        guard self.acceptsMenuRequest(state, version: version) else { return }
                        let copyAction: () -> Void
                        if let resolved = resolved {
                            copyAction = { [weak self] in
                                guard let self = self else { return }
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.declareTypes([.string], owner: self)
                                pb.setString(resolved, forType: .string)
                            }
                        } else {
                            let selection = layout.selectedRange.range
                            let selectedText: NSAttributedString?
                            if selection.location != NSNotFound, selection.location >= 0, selection.length >= 0,
                               selection.location <= text.length, selection.length <= text.length - selection.location {
                                selectedText = text.attributedSubstring(from: selection)
                            } else {
                                selectedText = nil
                            }
                            let copySelection = layout.interactions.copy
                            let copyAttributedString = layout.interactions.copyAttributedString
                            copyAction = { [weak self] in
                                guard let self = self else { return }
                                if copySelection?() != true, let selectedText = selectedText, !copyAttributedString(selectedText) {
                                    let pb = NSPasteboard.general
                                    pb.clearContents()
                                    pb.declareTypes([.string], owner: self)
                                    pb.setString(selectedText.string, forType: .string)
                                }
                            }
                        }
                        let menu = ContextMenu()
                        let copy = ContextMenuItem(title, handler: copyAction, itemImage: TextView.context_copy_animation)
                        menu.addItem(copy)
                        if resolved == nil, let window = self._window {
                            if let text = self.effectiveText, let translate = layout.interactions.translate?(text, window) {
                                menu.addItem(translate)
                            }
                        }
                        menu.topWindow = topWindow
                        self.presentTextMenu(menu, event: event, state: state, version: version)
                    }, completed: { [weak state] in state?.finish(version) })
                }
                state.install(disposable, version: version)
            } else {
                layout.selectedRange.range = NSMakeRange(NSNotFound, 0)
                setNeedsDisplayLayer()
                super.rightMouseDown(with: event)
            }
        } else {
            super.rightMouseDown(with: event)
        }
    }

    public static var context_copy_animation: ((NSColor, ContextMenuItem)->AppMenuItemImageDrawable)?
    
    
    public func menuDidClose(_ menu: NSMenu) {
        
    }
    
    /*
     var view: NSTextView? = (self.window?.fieldEditor(true, forObject: self) as? NSTextView)
     view?.isEditable = false
     view?.isSelectable = true
     view?.string = layout.attributedString.string
     view?.selectedRange = NSRange(location: 0, length: view?.string?.length)
     NSMenu.popUpContextMenu(view?.menu(for: event), with: event, for: view)
 */
    
    public override func menu(for event: NSEvent) -> NSMenu? {
        
        return nil
    }
    
    deinit {
        menuDisposable?.dispose()
        cancelLongHoverTimer()
    }
    
    public func isEqual(to layout:TextViewLayout) -> Bool {
        return self.textLayout == layout
    }
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        self.drawLayer.contentsScale = backingScaleFactor
        self.currentEmbeddedContainer?.contentsScale = backingScaleFactor
        setNeedsDisplayLayer()
    }

    //
    
    private func updateInks(_ layout: TextViewLayout?, animated: Bool = false) {
        let rects = layout?.spoilerRectFrames() ?? []
        if let layout = layout {
            let spoilers = layout.spoilers
            while rects.count > self.inkViews.count {
                let inkView = InvisibleInkDustView()
                self.inkViews.append(inkView)
                self.addSubview(inkView)
            }
            
            if rects.count < self.inkViews.count, animated {
                let fake = TextView(frame: self.bounds)
                
                fake.update(layout)
                fake.userInteractionEnabled = false
                fake.isSelectable = false
                addSubview(fake, positioned: .below, relativeTo: self.subviews.first)
                fake.layer?.animateAlpha(from: 0, to: 1, duration: 0.2, timingFunction: .easeInEaseOut, removeOnCompletion: false, completion: { [weak fake, weak self] _ in
                    fake?.removeFromSuperview()
                    self?.inAnimation = false
                })
                self.inAnimation = true
                fake.clearExceptRevealed = true
            }
            while rects.count < self.inkViews.count {
                performSubviewRemoval(self.inkViews.removeLast(), animated: animated)
            }
            
            for (i, inkView) in inkViews.enumerated() {
                let rect = rects[i]
                let color = spoilers[0].color
                inkView.update(size: rect.size, color: color, textColor: color, rects: [rect.size.bounds], wordRects: [rect.size.bounds.insetBy(dx: 2, dy: 2)])
                inkView.frame = rect
            }
        } else {
            while !inkViews.isEmpty {
                performSubviewRemoval(inkViews.removeLast(), animated: animated)
            }
        }
        if layout != nil {
            self.updateEmbeddedVisibility(spoilerRects: rects)
        }
        self.selectionWasCleared = false
    }
    
    public var canReuseForContentChange: Bool {
        return locationInWindow == nil && controlState != .Highlight && canBeResponder
            && !inAnimation && shimmerEffect == nil && contextMenu == nil
            && layer?.animationKeys()?.isEmpty != false
    }

    @discardableResult public func resetForContentChange() -> Bool {
        guard canReuseForContentChange else { return false }
        let previous = textLayout
        textLayout = nil
        guard textLayout == nil else { return false }
        animatedView?.removeFromSuperlayer()
        animatedView = nil
        blockHeaderRects.removeAll(keepingCapacity: true)
        lastDrawnSelectionState = nil
        beginSelect = NSPoint(x: -1, y: -1)
        endSelect = NSPoint(x: -1, y: -1)
        selectionWasCleared = false
        moveNextEventDeep = false
        clearExceptRevealed = false
        if window?.firstResponder === self { window?.makeFirstResponder(nil) }
        setNeedsDisplayLayer()
        previous?.interactions.hoverOnLink(.exited)
        return true
    }

    public func update(_ layout:TextViewLayout?, origin:NSPoint? = nil, transition: ContainedViewLayoutTransition = .immediate) -> Void {
        
        if let current = self.textLayout, current.attributedString.string == layout?.attributedString.string {
            if layout?.selectedRange.range == NSMakeRange(NSNotFound, 0) {
                layout?.selectedRange = current.selectedRange
            }
        } else {
            self.animatedView?.removeFromSuperlayer()
            self.animatedView = nil
        }
        
        self.textLayout = layout
        guard self.textLayout === layout else { return }

        self.updateInks(layout)
        
        
        if let layout = layout {
            self.set(selectedRange: layout.selectedRange.range, display: false)
            let point:NSPoint
            if let origin = origin {
                point = origin
            } else {
                point = frame.origin
            }
            let rect = NSMakeRect(point.x, point.y, layout.layoutSize.width + layout.insets.width, layout.layoutSize.height + layout.insets.height)
            transition.updateFrame(view: self, frame: rect)
            
            if installedToolTipRects != layout.toolTipRects {
                removeAllToolTips()
                for rect in layout.toolTipRects {
                    addToolTip(rect, owner: self, userData: nil)
                }
                installedToolTipRects = layout.toolTipRects
            }
            
        } else {
            self.set(selectedRange: NSMakeRange(NSNotFound, 0), display: false)
            transition.updateFrame(view: self, frame: NSZeroRect)

        }
        
       

        updateBackgroundBlur()

        self.setNeedsDisplayLayer()
    }
    
    public func set(layout:TextViewLayout?) {
        self.textLayout = layout
        self.setNeedsDisplayLayer()
    }
    
    public override func setNeedsDisplayLayer() {
        self.drawingLayer.setNeedsDisplay()
    }
    
    public override func setNeedsDisplay() {
        self.layer?.setNeedsDisplay()
        self.drawingLayer.setNeedsDisplay()
    }
    
    func set(selectedRange range:NSRange, display:Bool = true) -> Void {
        
        if let layout = textLayout {
            layout.selectedRange = TextSelectedRange(range:range, color: layout.selectText, def:true)
        }
        
        beginSelect = NSMakePoint(-1, -1)
        endSelect = NSMakePoint(-1, -1)
        
        
        if display {
            self.setNeedsDisplayLayer()
        }
        
    }
    
    public override func mouseDown(with event: NSEvent) {
        
        if event.modifierFlags.contains(.control) {
            rightMouseDown(with: event)
            return
        }
        
        if isSelectable && !event.modifierFlags.contains(.shift)  {
            self.window?.makeFirstResponder(nil)
        }
        if let layout = textLayout, userInteractionEnabled {
            let point = self.convert(event.locationInWindow, from: nil)
            let index = layout.findIndex(location: point)
            if index == -1 || (point.x > layout.lines[index].frame.maxX && isSelectable) {
                superview?.mouseDown(with: event)
                if sendDownAnyway {
                    super.mouseDown(with: event)
                }
            } else {
                _mouseDown(with: event)
            }
        } else if !userInteractionEnabled {
            _mouseDown(with: event)
        }
        
        selectionWasCleared = false
    }
    
    
    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let window = window, window !== newWindow {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: window)
        }
        if let newWindow = newWindow, newWindow !== window {
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeKey), name: NSWindow.didBecomeKeyNotification, object: newWindow)
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidResignKey), name: NSWindow.didResignKeyNotification, object: newWindow)
        }
    }
    
    private struct DrawnSelectionState: Equatable {
        let layout: ObjectIdentifier
        let layoutSize: NSSize
        let lineCount: Int
        let isSelectable: Bool
        let selectedRange: NSRange
        let additionalSelections: [NSRange]
    }
    
    private var lastDrawnSelectionState: DrawnSelectionState?
    
    private var currentSelectionState: DrawnSelectionState? {
        guard let layout = textLayout else {
            return nil
        }
        return DrawnSelectionState(layout: ObjectIdentifier(layout), layoutSize: layout.layoutSize, lineCount: layout.lines.count, isSelectable: isSelectable, selectedRange: layout.selectedRange.range, additionalSelections: layout.additionalSelections.map { $0.range })
    }
    
    private var needsDisplayOnKeyWindowChange: Bool {
        if isSelectable, let layout = textLayout, layout.selectedRange.range.location != NSNotFound {
            return true
        }
        return currentSelectionState != lastDrawnSelectionState
    }
    
    @objc open func windowDidBecomeKey() {
        if needsDisplayOnKeyWindowChange {
            setNeedsDisplayLayer()
        }
    }
    
    @objc open func windowDidResignKey() {
        if needsDisplayOnKeyWindowChange {
            setNeedsDisplayLayer()
        }
    }
    
    private var locationInWindow:NSPoint? = nil
    
    public var sendDownAnyway: Bool = false
    
    func _mouseDown(with event: NSEvent) -> Void {
        
        self.locationInWindow = event.locationInWindow
        
        if !isSelectable || !userInteractionEnabled || event.modifierFlags.contains(.shift) {
            super.mouseDown(with: event)
            return
        } else if sendDownAnyway {
            super.mouseDown(with: event)
        }
        
        _ = self.becomeFirstResponder()
        
        set(selectedRange: NSMakeRange(NSNotFound, 0), display: false)
        self.beginSelect = self.convert(event.locationInWindow, from: nil)
        
        self.setNeedsDisplayLayer()
        
    }
    
    public override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        checkCursor(event)
        _mouseDragged(with: event)
    }
    
    func _mouseDragged(with event: NSEvent) -> Void {
        if !isSelectable || !userInteractionEnabled {
            return
        }
        if let locationInWindow = self.locationInWindow {
            let old = (ceil(locationInWindow.x), ceil(locationInWindow.y))
            let new = (ceil(event.locationInWindow.x), round(event.locationInWindow.y))
            if abs(old.0 - new.0) <= 1 && abs(old.1 - new.1) <= 1 {
                return
            }
        }
        
        endSelect = self.convert(event.locationInWindow, from: nil)
        if let layout = textLayout {
            layout.selectedRange.range = layout.selectedRange(startPoint: beginSelect, currentPoint: endSelect, byWord: event.clickCount == 2)
            layout.selectedRange.cursorAlignment = beginSelect.x > endSelect.x ? .min(layout.selectedRange.range.max) : .max(layout.selectedRange.range.min)
        }
        self.setNeedsDisplayLayer()
    }
    
    
    public override func mouseEntered(with event: NSEvent) {
        if userInteractionEnabled {
            checkCursor(event)
        } else {
            super.mouseEntered(with: event)
        }
        
    }
    
    public override func mouseExited(with event: NSEvent) {
        if userInteractionEnabled {
            checkCursor(event)
        } else {
            super.mouseExited(with: event)
        }
    }
    
    public override func mouseMoved(with event: NSEvent) {
        if userInteractionEnabled {
            checkCursor(event)
        } else {
            super.mouseMoved(with: event)
        }
    }
    
    
    
    public override func mouseUp(with event: NSEvent) {
        
        self.locationInWindow = nil
        
        if let layout = textLayout, userInteractionEnabled, let window = _window {
            let point = self.convert(event.locationInWindow, from: nil)
            if let _ = layout.spoiler(at: point) {
                layout.revealSpoiler()
                guard textLayout === layout else { return }
                setNeedsDisplayLayer()
                self.updateInks(layout, animated: true)
                return
            }
            if let blockHeader = blockHeaderRects.first(where: { $0.0.contains(point) }) {
                if let string = layout.blockQuoteText(startingWith: blockHeader.1) {
                    _ = layout.interactions.copyToClipboard?(string)
                    showModalText(for: window, text: localizedString("Share.Link.Copied"))
                }
            } else if event.clickCount == 3, isSelectable {
                layout.selectAll(at: point)
                layout.selectedRange.cursorAlignment = .max(layout.selectedRange.range.min)
            } else if isSelectable, event.clickCount == 2 || (event.type == .rightMouseUp && !layout.selectedRange.hasSelectText) {
                layout.selectWord(at : point)
                layout.selectedRange.cursorAlignment = .max(layout.selectedRange.range.min)
            } else if !layout.selectedRange.hasSelectText || !isSelectable && (event.clickCount == 1 || !isSelectable) {
                if let color = layout.color(at: point), let copyToClipboard = layout.interactions.copyToClipboard {
                    copyToClipboard(color.0.hexString.lowercased())
                } else if let (data, _) = layout.formattedDate(at: point) {
                    if event.clickCount == 1 {
                        let items = data.contextMenuItems()
                        if !items.isEmpty {
                            let menu = ContextMenu()
                            for item in items {
                                menu.addItem(item)
                            }
                            AppMenu.show(menu: menu, event: event, for: self)
                        }
                    }
                } else if let (link, _, _, linkRect) = layout.link(at: point) {
                    if event.clickCount == 1 {
                        if linkRect.width >= 1, linkRect.height >= 1, let image = ModalMorphTransition.controlImage(self, rect: linkRect) {
                            let screenRect = window.convertToScreen(self.convert(linkRect, to: nil))
                            ModalMorphContextSource.register(image: image, screenRect: screenRect)
                        }
                        layout.interactions.processURL(link)
                    }
                } else {
                    if layout.findCharacterIndex(at: point) == -1, onlyTextIsInteractive {
                        moveNextEventDeep = true
                    }
                    super.mouseUp(with: event)
                }
            } else if layout.selectedRange.hasSelectText && event.clickCount == 1 && event.modifierFlags.contains(.shift) {
                var range = layout.selectedRange.range
                let index = layout.findCharacterIndex(at: point)
                if index < range.min {
                    range.length += (range.location - index)
                    range.location = index
                } else if index > range.max {
                    range.length = (index - range.location)
                }
                layout.selectedRange.range = range
            } else {
                super.mouseUp(with: event)
            }
            setNeedsDisplayLayer()
        } else {
            super.mouseUp(with: event)
        }
        
        self.beginSelect = NSMakePoint(-1, -1)
    }
    public override func cursorUpdate(with event: NSEvent) {
        if userInteractionEnabled {
            checkCursor(event)
        } else {
            super.cursorUpdate(with: event)
        }
    }
    
    func checkCursor(_ event:NSEvent) -> Void {
        
        let location = self.convert(event.locationInWindow, from: nil)
        
        if self.isMousePoint(location , in: self.visibleRect) && mouseInside() && userInteractionEnabled {
            let inBlockHeader = blockHeaderRects.contains(where: { $0.0.contains(location) })
            if inBlockHeader {
                cancelLongHoverTimer()
                NSCursor.pointingHand.set()
            } else if textLayout?.spoiler(at: location) != nil {
                cancelLongHoverTimer()
                NSCursor.pointingHand.set()
            }  else if textLayout?.color(at: location) != nil {
                cancelLongHoverTimer()
                NSCursor.pointingHand.set()
                textLayout?.interactions.hoverOnLink(.exited)
            } else if textLayout?.formattedDate(at: location) != nil {
                cancelLongHoverTimer()
                NSCursor.pointingHand.set()
            } else if let layout = textLayout, let (value, _, range, _) = layout.link(at: location) {
                NSCursor.pointingHand.set()
                layout.interactions.hoverOnLink(.entered(value))
                if layout.interactions.longHoverOnLink != nil {
                    startLongHoverTimer(for: value, range: range, layout: layout)
                } else {
                    cancelLongHoverTimer()
                }
            } else if isSelectable {
                NSCursor.iBeam.set()
                textLayout?.interactions.hoverOnLink(.exited)
                cancelLongHoverTimer()
            } else {
                NSCursor.arrow.set()
                textLayout?.interactions.hoverOnLink(.exited)
                cancelLongHoverTimer()
            }
        } else {
            NSCursor.arrow.set()
            textLayout?.interactions.hoverOnLink(.exited)
            cancelLongHoverTimer()
        }
    }

    private func startLongHoverTimer(for link: Any, range: NSRange, layout: TextViewLayout) {
        guard textLayout === layout else { return }
        if longHoverText === layout.attributedString, longHoverRange == range {
            return
        }
        if let text = longHoverText, longHoverRange.location != NSNotFound, longHoverRange.location < text.length,
           let existingLink = text.attribute(.link, at: longHoverRange.location, effectiveRange: nil) {
            if let existing = existingLink as? String, let next = link as? String, existing == next {
                return
            }
            if (existingLink as AnyObject) === (link as AnyObject) {
                return
            }
        }
        cancelLongHoverTimer()
        guard textLayout === layout, longHoverRange.location == NSNotFound else { return }
        longHoverRange = range
        longHoverText = layout.attributedString.copy() as? NSAttributedString
        let timer = SwiftSignalKit.Timer(timeout: 1.0, repeat: false, completion: { [weak self, weak layout] timer in
            guard let self = self, let layout = layout, self.textLayout === layout, self.longHoverTimer === timer else { return }
            guard self.matchesLongHoverText(layout) else {
                self.cancelLongHoverTimer()
                return
            }
            if !contextMenuOnScreen() {
                let disposable = layout.interactions.longHoverOnLink?(link, self)
                guard self.textLayout === layout, self.longHoverTimer === timer, self.matchesLongHoverText(layout) else {
                    if self.longHoverTimer === timer { self.cancelLongHoverTimer() }
                    disposable?.dispose()
                    return
                }
                self.longHoverDisposable = disposable
                self.longHoverTimer = nil
            } else {
                self.cancelLongHoverTimer()
            }
        }, queue: .mainQueue())
        longHoverTimer = timer
        timer.start()
    }

    private func matchesLongHoverText(_ layout: TextViewLayout?) -> Bool {
        guard let text = longHoverText, let layout = layout else { return false }
        return text === layout.attributedString || text.isEqual(to: layout.attributedString)
    }

    private func cancelLongHoverTimer() {
        guard longHoverRange.location != NSNotFound else { return }
        let timer = longHoverTimer
        let disposable = longHoverDisposable
        let text = longHoverText
        longHoverTimer = nil
        longHoverRange = NSRange(location: NSNotFound, length: 0)
        longHoverDisposable = nil
        longHoverText = nil
        timer?.invalidate()
        disposable?.dispose()
        withExtendedLifetime(text) {}
    }

    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            cancelLongHoverTimer()
        }
        if window == nil {
            menuDisposable?.cancel()
        }
    }

    private func updateBackgroundBlur() {
        
        if lockDrawingLayer {
            return
        }
        
        if self.layer?.masksToBounds != (blurBackground != nil) {
            self.layer?.masksToBounds = blurBackground != nil
        }
        if let blurBackground = blurBackground {

            if self.visualEffect == nil {
                self.visualEffect = VisualEffect(frame: self.bounds)
                addSubview(self.visualEffect!, positioned: .below, relativeTo: nil)
                if let textView = self.textView {
                    self.visualEffect?.addSubview(textView)
                } else {
                    self.visualEffect?.layer?.addSublayer(drawLayer)
                }
                if let currentEmbeddedContainer { self.visualEffect?.layer?.addSublayer(currentEmbeddedContainer) }
                embeddedContainerBelowText = false
            }
            self.visualEffect?.bgColor = blurBackground
            
            
            if let textlayout = self.textLayout, let blockImage = textlayout.blockImage.1 {
                if blockMask == nil {
                    blockMask = SimpleLayer()
                }
                var fr = CATransform3DIdentity
                fr = CATransform3DTranslate(fr, blockImage.backingSize.width / 2, 0, 0)
                fr = CATransform3DScale(fr, 1, -1, 1)
                fr = CATransform3DTranslate(fr, -(blockImage.backingSize.width / 2), 0, 0)
                
                blockMask?.transform = fr
                blockMask?.contentsScale = backingScaleFactor
                blockMask?.contents = blockImage
                blockMask?.frame = CGRect(origin: .zero, size: blockImage.backingSize)
                self.layer?.mask = blockMask
            } else {
                self.blockMask = nil
                self.layer?.mask = nil
            }
        }  else {
            if let textView = textView {
                self.addSubview(textView, positioned: .below, relativeTo: nil)
            } else if let layer = self.layer {
                let hasAnimatedLayer = animatedView?.superlayer != nil
                embeddedContainerBelowText = hasAnimatedLayer
                let container = currentEmbeddedContainer
                let drawIndex = hasAnimatedLayer ? (container == nil ? 1 : 2) : 0
                let sublayers = layer.sublayers ?? []
                let containerIsMisplaced = container.map { sublayers.count < 2 || sublayers[1] !== $0 } ?? false
                if sublayers.count <= drawIndex || sublayers[drawIndex] !== drawLayer || containerIsMisplaced {
                    layer.insertSublayer(drawLayer, at: hasAnimatedLayer ? 1 : 0)
                    if let container { layer.insertSublayer(container, at: 1) }
                }
            }
            if textView != nil, let currentEmbeddedContainer {
                self.layer?.insertSublayer(currentEmbeddedContainer, at: 1)
            }
            self.visualEffect?.removeFromSuperview()
            self.visualEffect = nil
            
            self.blockMask?.removeFromSuperlayer()
            self.blockMask = nil
            if self.layer?.mask != nil {
                self.layer?.mask = nil
            }
        }
        

        let drawingBounds = bounds.insetBy(dx: -2, dy: -3)
        if type(of: self) != TextView.self || _customHandler?.layout != nil || visualEffect != nil
            || drawLayer.frame != drawingBounds || drawLayer.bounds != drawingBounds
            || (currentEmbeddedContainer.map { $0.frame != bounds } ?? false) {
            needsLayout = true
        }
    }
    
    public override var needsDisplay: Bool {
        didSet {
            setNeedsDisplayLayer()
        }
    }
    

    public func addEmbeddedLayer(_ layer: CALayer) {
        embeddedContainer.addSublayer(layer)
    }
    
    public override func layout() {
        super.layout()
        self.visualEffect?.frame = bounds
        self.textView?.frame = bounds
        self.currentEmbeddedContainer?.frame = bounds
        self.drawLayer.frame = bounds
        self.drawLayer.bounds = bounds.insetBy(dx: -2, dy: -3)
        self.updateInks(self.textLayout)
    }
    
    public func resize(_ width: CGFloat, blockColor: NSColor? = nil) {
        self.textLayout?.measure(width: width)
        if let blockColor = blockColor {
            self.textLayout?.generateAutoBlock(backgroundColor: blockColor)
        }
        self.update(self.textLayout)
    }
    
    public override func becomeFirstResponder() -> Bool {
        if canBeResponder {
            if let window = self.window {
                return window.makeFirstResponder(self)
            }
        }
        
        
        return false        
    }
    
    public var isAccessibilitySensitive: Bool = false

    private var accessibilityText: String? {
        guard let text = textLayout?.attributedString.string, !text.isEmpty else {
            return nil
        }
        if isAccessibilitySensitive, !NSWorkspace.shared.isVoiceOverEnabled {
            return nil
        }
        return text
    }

    public override func isAccessibilityElement() -> Bool {
        guard TGUIKitAccessibility.isEnabled, !isAccessibilityDecorative, !isHidden else {
            return false
        }
        return accessibilityText != nil
    }

    public override func accessibilityRole() -> NSAccessibility.Role? {
        return TGUIKitAccessibility.isEnabled ? .staticText : super.accessibilityRole()
    }

    public override func accessibilityLabel() -> String? {
        return nil
    }

    public override func accessibilityValue() -> Any? {
        return accessibilityText
    }

//    public override var isOpaque: Bool {
//        return false
//    }
    
    public override func resignFirstResponder() -> Bool {
        _resignFirstResponder()
        return super.resignFirstResponder()
    }
    
    func _resignFirstResponder() -> Void {
        self.set(selectedRange: NSMakeRange(NSNotFound, 0))
    }
    
    public override func responds(to aSelector: Selector!) -> Bool {
        guard let aSelector = aSelector else {
            return false
        }
        if NSStringFromSelector(aSelector) == "copy:" {
            return self.textLayout?.selectedRange.range.location != NSNotFound
        }
        
        return super.responds(to: aSelector)
    }
    
    private var effectiveText: String? {
        if let layout = textLayout {
            if layout.selectedRange.range.location != NSNotFound {
                return layout.attributedString.string.nsstring.substring(with: layout.selectedRange.range)
            } else {
                return layout.attributedString.string
            }
        } else {
            return nil
        }
    }
    
    @objc public func copy(_ sender:Any) -> Void {
        if let layout = textLayout {
            if let copy = layout.interactions.copy {
                if !copy() && layout.selectedRange.range.location != NSNotFound {
                    if !layout.interactions.copyAttributedString(layout.attributedString.attributedSubstring(from: layout.selectedRange.range)) {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.declareTypes([.string], owner: self)
                        pb.setString(layout.attributedString.string.nsstring.substring(with: layout.selectedRange.range), forType: .string)
                    }
                }
            } else if layout.selectedRange.range.location != NSNotFound {
                if !layout.interactions.copyAttributedString(layout.attributedString.attributedSubstring(from: layout.selectedRange.range)) {
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    pb.declareTypes([.string], owner: self)
                    pb.setString(layout.attributedString.string.nsstring.substring(with: layout.selectedRange.range), forType: .string)
                }
            }
        }
    }
    
    public func checkEmbeddedUnderSpoiler() {
        if let layout = self.textLayout {
            updateEmbeddedVisibility(spoilerRects: layout.spoilerRectFrames())
        }
    }

    private func updateEmbeddedVisibility(spoilerRects: [CGRect]) {
        for sublayer in currentEmbeddedContainer?.sublayers ?? [] {
            let center = NSMakeRect(sublayer.frame.midX, sublayer.frame.midY, 1, 1)
            let opacity: Float = spoilerRects.contains(where: { NSIntersectsRect(center, $0) }) ? 0 : 1
            if sublayer.opacity != opacity {
                sublayer.opacity = opacity
            }
        }
    }

    @objc func paste(_ sender:Any) {
        
    }
    
    public override func removeFromSuperview() {
        super.removeFromSuperview()
    }
    
    
    public func updateWithNewWidth(_ width: CGFloat) {
        let layout = self.textLayout
        layout?.measure(width: width)
        self.update(layout)
    }
 
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var animatedView: SimpleLayer?
    
    public func highlight(text: String, color: NSColor, range: NSRange? = nil) {
        guard let textLayout = self.textLayout else {
            return
        }
        
        
        self.animatedView?.removeFromSuperlayer()
        
        let string = textLayout.attributedString.string.nsstring
        let effectiveRange: NSRange
        if let range, range.location >= 0, range.location != NSNotFound, range.length >= 0, range.location <= string.length, range.length <= string.length - range.location, string.substring(with: range) == text {
            effectiveRange = range
        } else {
            effectiveRange = string.range(of: text)
        }
        if effectiveRange.location != NSNotFound {
            let image = textLayout.generateBlock(for: effectiveRange, backgroundColor: color)
            guard let blockImage = image.1 else {
                return
            }
            let imageView = SimpleLayer(frame: CGRect(origin: image.0, size: blockImage.backingSize))
            imageView.contents = blockImage
            imageView.opacity = 0.5
            
            self.layer?.insertSublayer(imageView, at: 0)
            
            self.animatedView = imageView
            
            _ = delaySignal(3.0).start(completed: { [weak self, weak imageView] in
                guard let self, let imageView, self.animatedView === imageView else { return }
                performSublayerRemoval(imageView, animated: true)
                self.animatedView = nil
            })
            
        }
    }
}


public extension TextView {
    func setIsShimmering(_ value: Bool, animated: Bool) {
        if value, let blockImage = textLayout?.maskBlockImage.1 {
            let size = blockImage.size
            let current: ShimmerView
            if let view = self.shimmerEffect {
                current = view
            } else {
                current = ShimmerView()
                self.shimmerEffect = current
                self.addSubview(current)
                
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            current.update(backgroundColor: .blackTransparent, data: nil, size: size, imageSize: size)
            current.updateAbsoluteRect(size.bounds, within: size)
            
            let frame = self.bounds
            current.frame = blockImage.backingSize.bounds.offsetBy(dx: frame.minX - 5, dy: frame.minY - 1)
            
            if let blockImage = textLayout?.maskBlockImage.1 {
                if shimmerMask == nil {
                    shimmerMask = SimpleLayer()
                }
                var fr = CATransform3DIdentity
                fr = CATransform3DTranslate(fr, blockImage.backingSize.width / 2, 0, 0)
                fr = CATransform3DScale(fr, 1, -1, 1)
                fr = CATransform3DTranslate(fr, -(blockImage.backingSize.width / 2), 0, 0)
                
                shimmerMask?.transform = fr
                shimmerMask?.contentsScale = 2.0
                shimmerMask?.contents = blockImage
                shimmerMask?.frame = CGRect(origin: .zero, size: blockImage.backingSize)
                current.layer?.mask = shimmerMask
            } else {
                self.shimmerMask = nil
                current.layer?.mask = nil
            }
        } else {
            if let view = self.shimmerEffect {
                let shimmerMask = self.shimmerMask
                performSubviewRemoval(view, animated: animated, completed: { [weak shimmerMask] _ in
                    shimmerMask?.removeFromSuperlayer()
                })
                self.shimmerEffect = nil
                self.shimmerMask = nil
            }
        }
    }
    func reloadAnimation() {
        self.shimmerEffect?.reloadAnimation()
    }
}
