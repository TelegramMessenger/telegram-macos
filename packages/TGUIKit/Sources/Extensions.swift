import Foundation
import CoreText
import AppKit
import ObjcUtils
import ColorPalette

public typealias UIImage = NSImage

public func safeFrame(_ frame: NSRect) -> NSRect {
    let x = frame.origin.x.isFinite ? frame.origin.x : 0
    let y = frame.origin.y.isFinite ? frame.origin.y : 0
    let w = frame.size.width.isFinite ? max(0, frame.size.width) : 0
    let h = frame.size.height.isFinite ? max(0, frame.size.height) : 0
    return NSMakeRect(x, y, w, h)
}

public extension NSAttributedString {
    
    var firstForegroundColor: NSColor? {
        guard length > 0 else { return nil }
        var found: NSColor?
        enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: length), options: []) { value, _, stop in
            if let c = value as? NSColor {
                found = c
                stop.pointee = true
            }
        }
        return found
    }
    
    func sizeFittingWidth(_ w: CGFloat) -> CGSize {
        let textStorage = NSTextStorage(attributedString: self)
        let size = CGSize(width: w, height: CGFloat.greatestFiniteMagnitude)
        let boundingRect = CGRect(origin: .zero, size: size)

        let textContainer = NSTextContainer(size: size)
//        textContainer.lineFragmentPadding = 0

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        textStorage.addLayoutManager(layoutManager)

        layoutManager.glyphRange(forBoundingRect: boundingRect, in: textContainer)

        let rect = layoutManager.usedRect(for: textContainer)

        return rect.size
    }
    
    
    func containsAttribute(attributeName: NSAttributedString.Key) -> Any? {
        let range = NSRange(location: 0, length: self.length)
        
        var containsAttribute: Any? = nil
        
        self.enumerateAttribute(attributeName, in: range, options: []) { (value, _, _) in
            if value != nil {
                containsAttribute = value
            }
        }
        
        return containsAttribute
    }
    
    var trimmed: NSAttributedString {
        
        let string:NSMutableAttributedString = self.mutableCopy() as! NSMutableAttributedString
        
        let originalText = string.string.nsstring
        let lineSeparatorRange = originalText.range(of: "\u{2028}")
        let objectReplacementRange = originalText.range(of: "\u{fffc}", options: .literal)
        if lineSeparatorRange.location != NSNotFound || objectReplacementRange.location != NSNotFound {
            let mutableString = string.mutableString
            func replaceSeparator(_ separator: String, options: NSString.CompareOptions, firstRange: NSRange) {
                var range = firstRange
                while range.location != NSNotFound {
                    string.replaceCharacters(in: range, with: "\n")
                    let nextLocation = NSMaxRange(range)
                    guard nextLocation < string.length else {
                        break
                    }
                    range = mutableString.range(of: separator, options: options, range: NSRange(location: nextLocation, length: string.length - nextLocation))
                }
            }
            replaceSeparator("\u{2028}", options: [], firstRange: lineSeparatorRange)
            replaceSeparator("\u{fffc}", options: .literal, firstRange: objectReplacementRange)
        }
        var range = string.string.nsstring.rangeOfCharacter(from: NSCharacterSet.whitespacesAndNewlines)
        while !string.string.isEmpty, range.location == 0 {
            string.replaceCharacters(in: NSMakeRange(0, 1), with: "")
            range = string.string.nsstring.rangeOfCharacter(from: NSCharacterSet.whitespacesAndNewlines)
        }
        while !string.string.isEmpty, string.string.rangeOfCharacter(from: NSCharacterSet.whitespacesAndNewlines, options: [], range: string.string.index(string.string.endIndex, offsetBy: -1) ..< string.string.endIndex) != nil {
            string.replaceCharacters(in: NSMakeRange(string.string.length - 1, 1), with: "")
        }
        
        return string
    }
    
    var trimNewLines: NSAttributedString {
        
        let string:NSMutableAttributedString = self.mutableCopy() as! NSMutableAttributedString
        
       
        var range = string.string.nsstring.rangeOfCharacter(from: NSCharacterSet.newlines)
        while !string.string.isEmpty, range.location == 0 {
            string.replaceCharacters(in: NSMakeRange(0, 1), with: "")
            range = string.string.nsstring.rangeOfCharacter(from: NSCharacterSet.newlines)
        }
        while !string.string.isEmpty, string.string.rangeOfCharacter(from: NSCharacterSet.newlines, options: [], range: string.string.index(string.string.endIndex, offsetBy: -1) ..< string.string.endIndex) != nil {
            string.replaceCharacters(in: NSMakeRange(string.string.length - 1, 1), with: "")
        }
        
        return string
    }
    var trimNewLinesToSpace: NSAttributedString {
        return replaceNewlinesWithSpaces(in: self)
    }
    
    func replaceNewlinesWithSpaces(in attributedString: NSAttributedString) -> NSAttributedString {
        let mutableAttributedString = NSMutableAttributedString(attributedString: attributedString)
        let range = NSRange(location: 0, length: mutableAttributedString.length)
        mutableAttributedString.mutableString.replaceOccurrences(of: "\n", with: " ", options: .literal, range: range)
        return mutableAttributedString
    }
    
    var range:NSRange {
        return NSMakeRange(0, self.length)
    }
    
    func trimRange(_ range:NSRange) -> NSRange {
        let loc:Int = min(range.location,self.length)
        let length:Int = min(range.length, self.length - loc)
        return NSMakeRange(loc, length)
    }
    
    static func initialize(string:String?, color:NSColor? = nil, font:NSFont? = .normal(.text)) -> NSAttributedString {
        guard let string, !string.isEmpty else {
            return NSAttributedString(string: "")
        }
        if color == nil, font == nil {
            return NSAttributedString(string: string)
        }
        let attr = NSMutableAttributedString(string: string)
        let range = NSRange(location: 0, length: attr.length)
        if let color {
            attr.addAttribute(.foregroundColor, value: color, range: range)
        }
        if let font {
            attr.addAttribute(.font, value: font, range: range)
        }
        return attr.copy() as! NSAttributedString
    }
    convenience init(string: String, font: NSFont? = nil, textColor: NSColor = NSColor.black, paragraphAlignment: NSTextAlignment? = nil) {
        var attributes: [NSAttributedString.Key: AnyObject] = [:]
        if let font = font {
            attributes[.font] = font
        }
        attributes[.foregroundColor] = textColor
        if let paragraphAlignment = paragraphAlignment {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = paragraphAlignment
            attributes[.paragraphStyle] = paragraphStyle
        }
        self.init(string: string, attributes: attributes)
    }

    
}

public extension String {
    
    static func prettySized(with size:Int64, afterDot: Int8 = 1, removeToken: Bool = false, round: Bool = false, forceDecimal: Bool = false) -> String {
        return prettySized(with: Int(size), afterDot: afterDot, removeToken: removeToken, round: round, forceDecimal: forceDecimal)
    }
    
    static func prettySized(with size:Int, afterDot: Int8 = 1, removeToken: Bool = false, round: Bool = false, forceDecimal: Bool = false) -> String {
        var converted:Double = Double(size)
        var factor:Int = 0
        
        let tokens:[String] = ["B", "KB", "MB", "GB", "TB"]
        
        if round {
            while converted >= 1000 {
                converted /= 1000
                factor += 1
            }
        } else {
            while converted >= 1024.0 {
                converted /= 1024.0
                factor += 1
            }
        }
        
        
        if factor == 0 {
            //converted = 0
        }
        //factor = Swift.max(1,factor)
        
        if ceil(converted) - converted != 0.0 || removeToken || (forceDecimal && factor > 0) {
            if removeToken {
                return String(format: "%.\(afterDot)f", converted)
            } else {
                return String(format: "%.\(afterDot)f %@", converted, tokens[factor])
            }
        } else {
            if removeToken {
                return String(format: "%.0f", converted)
            } else {
                return String(format: "%.0f %@", converted, tokens[factor])
            }
        }
        
    }
    
    var trimmed:String {
        
        var string:String = self
        string = string.replacingOccurrences(of: "\u{2028}", with: "\n")
        while !string.isEmpty, let index = string.rangeOfCharacter(from: NSCharacterSet.whitespacesAndNewlines), index.lowerBound == string.startIndex {
            string = String(string[index.upperBound..<string.endIndex])
        }
        while !string.isEmpty, let index = string.rangeOfCharacter(from: NSCharacterSet.whitespacesAndNewlines, options: .literal, range: string.index(string.endIndex, offsetBy: -1) ..< string.endIndex) {
            string = String(string[..<index.lowerBound])
        }

        return string
    }
    
    var fullTrimmed: String {
        var copy: String = self
        
        if copy.isEmpty {
            return copy
        }
        
        
        
        
        while let _ = copy.range(of: "\n\n\n") {
            copy = copy.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return copy
    }

}

public extension NSAttributedString.Key {
    static var preformattedCode: NSAttributedString.Key {
        return NSAttributedString.Key(rawValue: "TGPreformattedCodeAttributeName")
    }
    static var preformattedPre: NSAttributedString.Key {
        return NSAttributedString.Key(rawValue: "TGPreformattedPreAttributeName")
    }
    static var selectedColor: NSAttributedString.Key {
        return NSAttributedString.Key(rawValue: "KSelectedColorAttributeName")
    }
}

public extension NSPasteboard.PasteboardType {
    static var kUrl:NSPasteboard.PasteboardType {
        return NSPasteboard.PasteboardType(kUTTypeURL as String)
    }
    static var kInApp:NSPasteboard.PasteboardType {
        return NSPasteboard.PasteboardType("TelegramTextPboardType" as String)
    }
    /// Marks a copy that originated from a rendered rich-text message, so a paste into the composer can
    /// open it in the rich editor instead of the plain input.
    static var kRichTextMessage:NSPasteboard.PasteboardType {
        return NSPasteboard.PasteboardType("TelegramRichTextMessagePboardType" as String)
    }
    /// A reference (`peerId:namespace:id`) to a rich-text message that carries media, so a paste can refetch
    /// the message and seed the editor with its FULL content (media included), not just the flat selection.
    static var kRichTextMessageRef:NSPasteboard.PasteboardType {
        return NSPasteboard.PasteboardType("TelegramRichTextMessageRefPboardType" as String)
    }
    static var kFilenames:NSPasteboard.PasteboardType {
        return NSPasteboard.PasteboardType("NSFilenamesPboardType")
    }
    static var kFileUrl: NSPasteboard.PasteboardType {
        return NSPasteboard.PasteboardType(kUTTypeFileURL as String)
    }
}

public struct ParsingType: OptionSet {
    public var rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    public init() {
        self.rawValue = 0
    }
    
    public init(_ flags: ParsingType) {
        var rawValue: UInt32 = 0
        
        if flags.contains(ParsingType.Links) {
            rawValue |= ParsingType.Links.rawValue
        }
        
        if flags.contains(ParsingType.Mentions) {
            rawValue |= ParsingType.Mentions.rawValue
        }
        
        if flags.contains(ParsingType.Commands) {
            rawValue |= ParsingType.Commands.rawValue
        }
        
        if flags.contains(ParsingType.Hashtags) {
            rawValue |= ParsingType.Hashtags.rawValue
        }
        
        self.rawValue = rawValue
    }
    
    public static let Links = ParsingType(rawValue: 1)
    public static let Mentions = ParsingType(rawValue: 2)
    public static let Commands = ParsingType(rawValue: 4)
    public static let Hashtags = ParsingType(rawValue: 8)
    public static let Ton = ParsingType(rawValue: 16)
}

public extension NSAttributedString {
    func detectBold(with font: NSFont) -> NSAttributedString {
        let copy = self.mutableCopy() as! NSMutableAttributedString
        copy.detectBoldColorInString(with: font, string: copy.string)
        return copy
    }
}

public extension NSMutableAttributedString {
    
    func detectBoldColorInString(with font: NSFont, color: NSColor? = nil) {
        detectBoldColorInString(with: font, string: self.string, color: color)
    }

    func detectBoldColorInString(with font: NSFont, string: String, color: NSColor? = nil) {
        var offset: Int = 0
        
        let nsString = string.nsstring
        
        while (offset < nsString.length) {
            let startRange = nsString.range(of: "**", options: [], range: NSRange(location: offset, length: nsString.length - offset))
            if startRange.location != NSNotFound {
                offset = startRange.upperBound
                
                let endOffset = min(offset, nsString.length)
                
                let endRange = nsString.range(of: "**", options: [], range: NSRange(location: endOffset, length: nsString.length - endOffset))
                if endRange.location != NSNotFound {
                    let startIndex = offset
                    let endIndex = endRange.lowerBound
                    let attributeRange = NSRange(location: startIndex, length: endIndex - startIndex)
                    
                    addAttribute(NSAttributedString.Key.font, value: font, range: attributeRange)
                    if let color = color {
                        addAttribute(.foregroundColor, value: color, range: attributeRange)
                    }
                    offset = endRange.upperBound
                }
            } else {
                break
            }
        }
        
        while let startRange = self.string.range(of: "**") {
            self.replaceCharacters(in: NSRange(startRange, in: self.string), with: "")
        }
    }
    
    
    func removeWhitespaceFromQuoteAttribute() {
        let mutableAttributedString = self
        var fullRange = NSRange(location: 0, length: mutableAttributedString.length)

        mutableAttributedString.enumerateAttribute(TextInputAttributes.quote, in: fullRange, options: []) { value, range, _ in
            if let _ = value as? TextViewBlockQuoteData {
                var rangeToModify = range

                // Remove leading whitespace
                while rangeToModify.length > 0 {
                    let rangeString = mutableAttributedString.attributedSubstring(from: rangeToModify).string
                    if let firstChar = rangeString.first, firstChar.isNewline {
                        rangeToModify.location += 1
                        rangeToModify.length -= 1
                    } else {
                        break
                    }
                }

                // Remove trailing whitespace
                while rangeToModify.length > 0 {
                    let rangeString = mutableAttributedString.attributedSubstring(from: rangeToModify).string
                    if let lastChar = rangeString.last, lastChar.isNewline {
                        rangeToModify.length -= 1
                    } else {
                        break
                    }
                }
                if range != rangeToModify {
                    mutableAttributedString.replaceCharacters(in: range, with: mutableAttributedString.attributedSubstring(from: rangeToModify))
                }
            }
        }
        
        fullRange = NSRange(location: 0, length: mutableAttributedString.length)

        mutableAttributedString.enumerateAttribute(TextInputAttributes.quote, in: fullRange, options: []) { value, range, _ in
            if let _ = value as? TextViewBlockQuoteData {
                var rangeToModify = range
                if rangeToModify.min > 0 {
                    if let char = mutableAttributedString.attributedSubstring(from: NSMakeRange(rangeToModify.min - 1, 1)).string.first {
                        if !char.isNewline {
                            mutableAttributedString.insert(.initialize(string: "\n"), at: rangeToModify.min)
                            rangeToModify.location += 1
                        }
                    }
                }
                if rangeToModify.max < mutableAttributedString.length {
                    if let char = mutableAttributedString.attributedSubstring(from: NSMakeRange(rangeToModify.max, 1)).string.first {
                        if !char.isNewline {
                            mutableAttributedString.insert(.initialize(string: "\n"), at: rangeToModify.max)
                            rangeToModify.location -= 1
                        }
                    }
                }
            }
        }
    }

    
    @discardableResult func append(string:String?, color:NSColor? = nil, font:NSFont? = .normal(.text)) -> NSRange {
        
        if(string == nil) {
            return NSMakeRange(0, 0)
        }
        
        let slength:Int = self.length


        var range:NSRange
        
        
        self.append(NSAttributedString(string: string!))
        let nlength:Int = self.length - slength
        range = NSMakeRange(self.length - nlength, nlength)
        
        if let c = color {
            self.addAttribute(NSAttributedString.Key.foregroundColor, value: c, range:range )
        }
        
        if let f = font {
            self.setFont(font: f, range: range)
        }
        
        
        return range
        
    }
    
    func add(link:Any, for range:NSRange, color: NSColor = presentation.colors.link)  {
        self.addAttribute(NSAttributedString.Key.link, value: link, range: range)
        self.addAttribute(NSAttributedString.Key.foregroundColor, value: color, range: range)
    }
    
    
    func setSelected(color:NSColor,range:NSRange) -> Void {
        self.addAttribute(.selectedColor, value: color, range: range)
    }

    
    func setFont(font:NSFont, range:NSRange) -> Void {
        self.addAttribute(NSAttributedString.Key.font, value: font, range: range)
    }
    
}


public extension CALayer {
    
    var layerTintColor: CGColor? {
        get {
            if let value = self.value(forKey: "contentsMultiplyColor"), CFGetTypeID(value as CFTypeRef) == CGColor.typeID {
                let result = value as! CGColor
                return result
            } else {
                return nil
            }
        } set(value) {
            self.setValue(value, forKey: "contentsMultiplyColor")
        }
    }

    
    func disableActions() -> Void {
        TGDisableLayerActions(self)
    }
    
    
    func animateBackground(duration: Double = 0.2, function: CAMediaTimingFunctionName = .easeOut) ->Void {
        let animation: CABasicAnimation
        if function == .spring {
            animation = makeSpringAnimation("backgroundColor")
        } else {
            animation = CABasicAnimation(keyPath: "backgroundColor")
            animation.timingFunction = .init(name: function)
        }
        self.add(animation, forKey: "backgroundColor")
    }
    func animateTransform() ->Void {
        let animation = CABasicAnimation(keyPath: "transform")
        animation.duration = 0.2
        self.add(animation, forKey: "transform")
    }
    
    func animatePath(duration: Double = 0.2, function: CAMediaTimingFunctionName = .easeOut) {
        let animation: CABasicAnimation
        if function == .spring {
            animation = makeSpringAnimation("path")
        } else {
            animation = CABasicAnimation(keyPath: "path")
            animation.timingFunction = .init(name: function)
        }
        animation.duration = duration
        self.add(animation, forKey: "path")
    }
    func animateShadow() {
        let animation = CABasicAnimation(keyPath: "shadowPath")
        animation.duration = 0.2
        self.add(animation, forKey: "shadowPath")
    }
    func animateFrameFast() {
        let animation = CABasicAnimation(keyPath: "frame")
        animation.duration = 0.2
        self.add(animation, forKey: "frame")
    }
    
    func animateBorder() ->Void {
        let animation = CABasicAnimation(keyPath: "borderWidth")
        animation.duration = 0.2
        self.add(animation, forKey: "borderWidth")
    }
    func animateOpacity() ->Void {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.duration = 0.2
        self.add(animation, forKey: "opacity")
    }
    
    func animateBorderColor() ->Void {
        let animation = CABasicAnimation(keyPath: "borderColor")
        animation.duration = 0.2
        self.add(animation, forKey: "borderColor")
    }
    func animateGradientColors() ->Void {
        let animation = CABasicAnimation(keyPath: "colors")
        animation.duration = 0.2
        self.add(animation, forKey: "colors")
    }
    func animateCornerRadius(duration: Double = 0.2, timingFunction: CAMediaTimingFunctionName = .easeOut) ->Void {
        let animation: CABasicAnimation
        if timingFunction == .spring {
            animation = makeSpringAnimation("cornerRadius")
        } else {
            animation = CABasicAnimation(keyPath: "cornerRadius")
            animation.timingFunction = .init(name: timingFunction)
        }
        animation.duration = duration
        self.add(animation, forKey: "cornerRadius")
    }
    
    func animateContents() ->Void {
        let animation = CABasicAnimation(keyPath: "contents")
        animation.duration = 0.2
        self.add(animation, forKey: "contents")
    }
    
}




public extension NSView {
    
    var snapshot: NSImage {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return NSImage() }
        self.cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }
    
    var subviewsSize: NSSize {
        var size: NSSize = NSZeroSize
        for subview in subviews {
            size.width += subview.frame.width
            size.height += subview.frame.height
        }
        return size
    }
    var subviewsWidthSize: NSSize {
        var size: NSSize = NSZeroSize
        for subview in subviews {
            size.width += subview.frame.width
            size.height = max(subview.frame.height, size.height)
        }
        return size
    }
    private func isInSuperclassView(_ superclass: AnyClass, view: NSView) -> Bool {
        if view.isKind(of: superclass) {
            return true
        } else if let view = view.superview {
            return isInSuperclassView(superclass, view: view)
        } else {
            return false
        }
    }
    func isInSuperclassView(_ superclass: AnyClass) -> Bool {
        return isInSuperclassView(superclass, view: self)
    }
    
    
    func _mouseInside() -> Bool {
        if let window = self.window {
       
            var location:NSPoint = window.mouseLocationOutsideOfEventStream

            location = self.convert(location, from: nil)
            
            
            if let view = window.contentView!.hitTest(window.mouseLocationOutsideOfEventStream) {
                if let view = view as? View {
                    if view.isEventLess {
                        return NSPointInRect(location, self.bounds)
                    }
                } else if let view = view as? ImageView, view.isEventLess {
                    return NSPointInRect(location, self.bounds)
                } else if let view = view as? LayerBackedView, view.isEventLess {
                    return NSPointInRect(location, self.bounds)
                } else if let view = view as? EventLessView, view.isEventLess {
                    return NSPointInRect(location, self.bounds)
                } else if let _ = view as? VisualEffect {
                    return NSPointInRect(location, self.bounds)
                }
                if view == self {
                    return NSPointInRect(location, self.bounds)
                } else {
                    var s = view.superview
                    if let view = view as? NSTableView {
                        let somePoint = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                        let row = view.row(at: somePoint)
                        if row >= 0 {
                            let someView = view.rowView(atRow: row, makeIfNecessary: false)
                            if let someView = someView {
                                let hit = someView.hitTest(someView.convert(window.mouseLocationOutsideOfEventStream, from: nil))
                                return hit == self
                            }
                        }
                    }
                    while let sv = s {
                        if sv == self {
                            return NSPointInRect(location, self.bounds)
                        }
                        s = sv.superview
                    }
                }
            } else {
                var bp:Int = 0
                bp += 1
            }
            
        }
        return false
    }
    
    var backingScaleFactor: CGFloat {
        if let window = window {
            return window.backingScaleFactor
        } else {
            return System.backingScale
        }
    }
    var bsc: CGFloat {
        return backingScaleFactor
    }
    
    func removeAllSubviews() -> Void {
        var filtered = self.subviews.filter { view -> Bool in
            if let view = view as? View {
                return !view.noWayToRemoveFromSuperview
            } else {
                return true
            }
        }
        while (filtered.count > 0) {
            filtered.removeFirst().removeFromSuperview()
        }
    }
    
    func isInnerView(_ view:NSView?) -> Bool {
        var inner = false
        for i in 0 ..< subviews.count {
            inner = subviews[i] == view
            if !inner && !subviews[i].subviews.isEmpty {
                inner = subviews[i].isInnerView(view)
            }
            if inner {
                break
            }
        }
        return inner
    }
    
    func setFrameSize(_ width:CGFloat, _ height:CGFloat) {
        self.setFrameSize(NSMakeSize(width, height))
    }
    
    func setFrameOrigin(_ x:CGFloat, _ y:CGFloat) {
        self.setFrameOrigin(NSMakePoint(x, y))
    }
    
    var background:NSColor {
        get {
            if let view = self as? View {
                return view.backgroundColor
            }
            if let backgroundColor = layer?.backgroundColor {
                return NSColor(cgColor: backgroundColor) ?? .white
            }
            return .white
        }
        set {
            if let view = self as? View {
                view.backgroundColor = newValue
            } else {
                self.layer?.backgroundColor = newValue.cgColor
            }
        }
    }
    
    func centerX(_ superView:NSView? = nil, y:CGFloat? = nil, addition: CGFloat = 0) -> Void {
        
        var x:CGFloat = 0
        
        if let sv = superView {
            x = CGFloat(roundf(Float((sv.frame.width - frame.width)/2.0)))
        } else if let sv = self.superview {
            x = CGFloat(roundf(Float((sv.frame.width - frame.width)/2.0)))
        }
        
        
        self.setFrameOrigin(NSMakePoint(x + addition, y == nil ? NSMinY(self.frame) : y!))
    }
    
    func centerFrameX(y:CGFloat? = nil, addition: CGFloat = 0) -> CGRect {
        var x:CGFloat = 0
        if let sv = self.superview {
            x = CGFloat(roundf(Float((sv.frame.width - frame.width)/2.0)))
        }
        return CGRect(origin: NSMakePoint(x + addition, y == nil ? NSMinY(self.frame) : y!), size: frame.size)
    }
    
    func focus(_ size:NSSize) -> NSRect {
        var x:CGFloat = 0
        var y:CGFloat = 0
        
        x = CGFloat(round((frame.width - size.width)/2.0))
        y = CGFloat(round((frame.height - size.height)/2.0))
        
        
        return NSMakeRect(x, y, size.width, size.height)
    }
    
    func focus(_ size:NSSize, inset:NSEdgeInsets) -> NSRect {
        let x:CGFloat = CGFloat(round((frame.width - size.width + (inset.left + inset.right))/2.0))
        let y:CGFloat = CGFloat(round((frame.height - size.height + (inset.top + inset.bottom))/2.0))
        return NSMakeRect(x, y, size.width, size.height).offsetBy(dx: 0, dy: -inset.top)
    }
    
    func centerY(_ superView:NSView? = nil, x:CGFloat? = nil, addition: CGFloat = 0) -> Void {
        
        var y:CGFloat = 0
        
        if let sv = superView {
            y = CGFloat(round((sv.frame.height - frame.height)/2.0))
        } else if let sv = self.superview {
            y = CGFloat(round((sv.frame.height - frame.height)/2.0))
        }
        
        self.setFrameOrigin(NSMakePoint(x ?? frame.minX, y + addition))
    }
    
    func centerFrameY(x:CGFloat? = nil, addition: CGFloat = 0) -> CGRect {
        
        var y:CGFloat = 0
        
        if let sv = self.superview {
            y = CGFloat(round((sv.frame.height - frame.height)/2.0))
        }
        
        return CGRect(origin: NSMakePoint(x ?? frame.minX, y + addition), size: frame.size)
    }
    
    
    func center(_ superView:NSView? = nil) -> Void {
        
        var x:CGFloat = 0
        var y:CGFloat = 0
        
        if let sv = superView {
            x = CGFloat(round((sv.frame.width - frame.width)/2.0))
            y = CGFloat(round((sv.frame.height - frame.height)/2.0))
        } else if let sv = self.superview {
            x = CGFloat(round((sv.frame.width - frame.width)/2.0))
            y = CGFloat(round((sv.frame.height - frame.height)/2.0))
        }
        
        self.setFrameOrigin(NSMakePoint(x, y))
        
    }
    
    func centerPoint() -> CGPoint {
        var x:CGFloat = 0
        var y:CGFloat = 0
        
        if let sv = self.superview {
            x = CGFloat(round((sv.frame.width - frame.width)/2.0))
            y = CGFloat(round((sv.frame.height - frame.height)/2.0))
        }
        return NSMakePoint(x, y)
    }
    
    func centerFrame() -> CGRect {
        var x:CGFloat = 0
        var y:CGFloat = 0
        
        if let sv = self.superview {
            x = CGFloat(round((sv.frame.width - frame.width)/2.0))
            y = CGFloat(round((sv.frame.height - frame.height)/2.0))
        }
        return CGRect(origin: NSMakePoint(x, y), size: frame.size)
    }


    func rect(_ point:NSPoint) -> NSRect {
        return NSMakeRect(point.x, point.y, frame.width, frame.height)
    }
    
    func _change(pos position: NSPoint, animated: Bool, _ save:Bool = true, removeOnCompletion: Bool = true, duration:Double = 0.2, timingFunction: CAMediaTimingFunctionName = CAMediaTimingFunctionName.easeOut, additive: Bool = false, forceAnimateIfHasAnimation: Bool = false, completion:((Bool)->Void)? = nil) -> Void {
        
        
        if position == frame.origin && !additive {
            completion?(true)
            return
        }
        
        if self is NSVisualEffectView {
            let sub = self.layer?.sublayers ?? []
            for layer in sub {
                if animated || (forceAnimateIfHasAnimation && layer.animation(forKey:"position") != nil) {
                    
                    var presentX = NSMinX(self.frame)
                    var presentY = NSMinY(self.frame)
                    let presentation:CALayer? = layer.presentation()
                    if let presentation = presentation, let _ = layer.animation(forKey:"position") {
                        presentY =  presentation.frame.minY
                        presentX = presentation.frame.minX
                    }
                    layer.animatePosition(from: NSMakePoint(presentX, presentY), to: position, duration: duration, timingFunction: timingFunction, removeOnCompletion: removeOnCompletion, additive: additive, completion: completion)

                } else {
                    layer.removeAnimation(forKey: "position")
                }
            }
        }
        
        if animated || (forceAnimateIfHasAnimation && self.layer?.animation(forKey:"position") != nil) {
            
            var presentX = NSMinX(self.frame)
            var presentY = NSMinY(self.frame)
            let presentation:CALayer? = self.layer?.presentation()
            if let presentation = presentation, let _ = self.layer?.animation(forKey:"position") {
                presentY =  presentation.frame.minY
                presentX = presentation.frame.minX
            }
            self.layer?.animatePosition(from: NSMakePoint(presentX, presentY), to: position, duration: duration, timingFunction: timingFunction, removeOnCompletion: removeOnCompletion, additive: additive, completion: completion)

        } else {
            self.layer?.removeAnimation(forKey: "position")
        }
        
        
        if save {
            self.setFrameOrigin(position)
            if let completion = completion, !animated {
                completion(true)
            }
        }
      
    }
    
    func shake(beep: Bool = true) {
        let a:CGFloat = 3
        if let layer = layer {
            self.layer?.shake(0.04, from:NSMakePoint(-a + layer.position.x,layer.position.y), to:NSMakePoint(a + layer.position.x, layer.position.y))
        }
        if beep {
            NSSound.beep()
        }
    }
    
    func _change(size: NSSize, animated: Bool, _ save:Bool = true, removeOnCompletion: Bool = true, duration:Double = 0.2, timingFunction: CAMediaTimingFunctionName = CAMediaTimingFunctionName.easeOut, completion:((Bool)->Void)? = nil) {
        
        if size == frame.size {
            completion?(true)
            return
        }
        
        func animate(_ layer: CALayer, main: Bool) -> Void {
            if animated {
                var presentBounds:NSRect = layer.bounds
                let presentation = layer.presentation()
                if let presentation = presentation, layer.animation(forKey:"bounds") != nil {
                    presentBounds.size.width = NSWidth(presentation.bounds)
                    presentBounds.size.height = NSHeight(presentation.bounds)
                }
                layer.animateBounds(from: presentBounds, to: NSMakeRect(0, 0, size.width, size.height), duration: duration, timingFunction: timingFunction, removeOnCompletion: removeOnCompletion, completion: main ? completion : nil)
            } else {
                layer.removeAnimation(forKey: "bounds")
            }
        }
        
        if let layer = self.layer {
            animate(layer, main: true)
        }

        
        if save {
            self.frame = NSMakeRect(NSMinX(self.frame), NSMinY(self.frame), size.width, size.height)
        }
    }
    
    func _changeBounds(from: NSRect, to: NSRect, animated: Bool, _ save:Bool = true, removeOnCompletion: Bool = true, duration:Double = 0.2, timingFunction: CAMediaTimingFunctionName = CAMediaTimingFunctionName.easeOut, completion:((Bool)->Void)? = nil) {
        
       
        if save {
            self.bounds = to
        }
        
        if from == to {
            completion?(true)
            return
        }
        
        if self is NSVisualEffectView {
            let sub = self.layer?.sublayers ?? []
            for layer in sub {
                if animated {
                    layer.animateBounds(from: from, to: to, duration: duration, timingFunction: timingFunction, removeOnCompletion: removeOnCompletion, completion: completion)
                    
                } else {
                    layer.removeAnimation(forKey: "bounds")
                }
            }
        }
        
        if animated {
            self.layer?.animateBounds(from: from, to: to, duration: duration, timingFunction: timingFunction, removeOnCompletion: removeOnCompletion, completion: completion)
            
        } else {
            self.layer?.removeAnimation(forKey: "bounds")
        }
        
        if !animated {
            completion?(true)
        }
    }
    
    func _change(opacity to: CGFloat, animated: Bool = true, _ save:Bool = true, removeOnCompletion: Bool = true, duration:Double = 0.2, timingFunction: CAMediaTimingFunctionName = CAMediaTimingFunctionName.easeOut, completion:((Bool)->Void)? = nil) {
        
        if Float(to) == self.layer?.opacity {
            completion?(true)
            return
        }
        if animated {
            if let layer = self.layer {
                var opacity:CGFloat = CGFloat(layer.opacity)
                if let presentation = self.layer?.presentation(), self.layer?.animation(forKey:"opacity") != nil {
                    opacity = CGFloat(presentation.opacity)
                }
                
                layer.animateAlpha(from: opacity, to: to, duration:duration, timingFunction: timingFunction, removeOnCompletion: removeOnCompletion, completion: completion)
            }
           
            
        } else {
            layer?.removeAnimation(forKey: "opacity")
        }
        if save {
            self.layer?.opacity = Float(to)
            if let completion = completion, !animated {
                completion(true)
            }
        }
    }
    
    func disableHierarchyInteraction() -> Void {
        for sub in self.subviews {
            if let sub = sub as? View, sub.interactionStateForRestore == nil {
                sub.interactionStateForRestore = sub.userInteractionEnabled
                sub.userInteractionEnabled = false
            }
            sub.disableHierarchyInteraction()
        }
    }
    func restoreHierarchyInteraction() -> Void {
        for sub in self.subviews {
            if let sub = sub as? View, let resporeState = sub.interactionStateForRestore {
                sub.userInteractionEnabled = resporeState
                sub.interactionStateForRestore = nil
            } else if let sub = sub as? TableRowView, let resporeState = sub.interactionStateForRestore {
                sub.userInteractionEnabled = resporeState
                sub.interactionStateForRestore = nil
            }
            sub.restoreHierarchyInteraction()
        }
    }
    
    func restoreHierarchyDynamicContent() -> Void {
        for sub in self.subviews {
            if let sub = sub as? View, let resporeState = sub.dynamicContentStateForRestore {
                sub.isDynamicContentLocked = resporeState
                sub.dynamicContentStateForRestore = nil
            } else if let sub = sub as? TableRowView, let resporeState = sub.dynamicContentStateForRestore {
                sub.isDynamicContentLocked = resporeState
                sub.dynamicContentStateForRestore = nil
            }
            sub.restoreHierarchyDynamicContent()
        }
    }
    
    func disableHierarchyDynamicContent() -> Void {
        for sub in self.subviews {
            if let sub = sub as? View, sub.interactionStateForRestore == nil {
                sub.dynamicContentStateForRestore = sub.isDynamicContentLocked
                sub.isDynamicContentLocked = true
            } else if let sub = sub as? TableRowView, sub.interactionStateForRestore == nil {
                sub.dynamicContentStateForRestore = sub.isDynamicContentLocked
                sub.isDynamicContentLocked = true
            }
            sub.disableHierarchyDynamicContent()
        }
    }
    
    

}




public extension NSTableView.AnimationOptions {
    static var none: NSTableView.AnimationOptions { get {
            return NSTableView.AnimationOptions(rawValue: 0)
        }
    }

}

public extension CGSize {
    func fitted(_ size: CGSize) -> CGSize {
        var fittedSize = self
        if fittedSize.width > size.width {
            fittedSize = CGSize(width: size.width, height: ceil((fittedSize.height * size.width / max(fittedSize.width, 1.0))))
        }
        if fittedSize.height > size.height {
            fittedSize = CGSize(width: ceil((fittedSize.width * size.height / max(fittedSize.height, 1.0))), height: size.height)
        }
        return fittedSize
    }
    
    func fit(_ maxSize: CGSize) -> CGSize {
        var size = self
        if self.width < 1.0 {
            return CGSize()
        }
        if self.height < 1.0 {
            return CGSize()
        }
    
        if size.width > maxSize.width {
            size.height = floor((size.height * maxSize.width / size.width));
            size.width = maxSize.width;
        }
        if size.height > maxSize.height {
            size.width = floor((size.width * maxSize.height / size.height));
            size.height = maxSize.height;
        }
        return size;
    }
    
    func cropped(_ size: CGSize) -> CGSize {
        return CGSize(width: min(size.width, self.width), height: min(size.height, self.height))
    }
    
    func fittedToArea(_ area: CGFloat) -> CGSize {
        if self.height < 1.0 || self.width < 1.0 {
            return CGSize()
        }
        let aspect = self.width / self.height
        let height = sqrt(area / aspect)
        let width = aspect * height
        return CGSize(width: ceil(width), height: ceil(height))
    }
    
    func aspectFilled(_ size: CGSize) -> CGSize {
        let scale = max(size.width / max(1.0, self.width), size.height / max(1.0, self.height))
        return CGSize(width: ceil(self.width * scale), height: ceil(self.height * scale))
    }
    func fittedToWidthOrSmaller(_ width: CGFloat) -> CGSize {
        let scale = min(1.0, width / max(1.0, self.width))
        return CGSize(width: floor(self.width * scale), height: floor(self.height * scale))
    }
    
    func aspectFitted(_ size: CGSize) -> CGSize {
        let scale = min(size.width / max(1.0, self.width), size.height / max(1.0, self.height))
        return CGSize(width: floor(self.width * scale), height: floor(self.height * scale))
    }
    
    func multipliedByScreenScale() -> CGSize {
        let scale:CGFloat = System.backingScale
        return CGSize(width: self.width * scale, height: self.height * scale)
    }
    
    var integralFloor: CGSize {
        return CGSize(width: floor(self.width), height: floor(self.height))
    }

    
    func dividedByScreenScale() -> CGSize {
        let scale:CGFloat = System.backingScale
        return CGSize(width: self.width / scale, height: self.height / scale)
    }
    var bounds: CGRect {
        return NSMakeRect(0, 0, width, height)
    }
}

private final class PrecomposedImageTintCache {
    static let shared = PrecomposedImageTintCache()

    private struct Key: Hashable {
        let source: ObjectIdentifier
        let color: CGColor
        let colorHash: CFHashCode
        let width: CGFloat
        let height: CGFloat
        let scale: CGFloat
        let flipVertical: Bool
        let flipHorizontal: Bool

        static func ==(lhs: Key, rhs: Key) -> Bool {
            lhs.source == rhs.source && lhs.width == rhs.width && lhs.height == rhs.height && lhs.scale == rhs.scale && lhs.flipVertical == rhs.flipVertical && lhs.flipHorizontal == rhs.flipHorizontal && CFEqual(lhs.color, rhs.color)
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(source)
            hasher.combine(width)
            hasher.combine(height)
            hasher.combine(scale)
            hasher.combine(flipVertical)
            hasher.combine(flipHorizontal)
            hasher.combine(colorHash)
        }
    }

    private struct Entry {
        weak var source: CGImage?
        let output: CGImage
        let cost: Int

        init(source: CGImage, output: CGImage) {
            self.source = source
            self.output = output
            self.cost = output.bytesPerRow * output.height
        }
    }

    private let lock = NSLock()
    private var settings: DeviceGraphicsContextSettings?
    private var entries: [Key: Entry] = [:]
    private var order: [Key?] = Array(repeating: nil, count: 64)
    private var first = 0
    private var count = 0
    private var retainedBytes = 0

    func image(_ source: NSImage, color: NSColor? = nil, bottomColor: NSColor? = nil, flipVertical: Bool = false, flipHorizontal: Bool = false, scale: CGFloat = System.backingScale, zoom: CGFloat = 1) -> CGImage {
        let size = source.size
        guard let color = color, bottomColor == nil, zoom == 1, color.type == .componentBased, size.width <= 64, size.height <= 64 else {
            return source.precomposedWithoutTintCache(color, bottomColor: bottomColor, flipVertical: flipVertical, flipHorizontal: flipHorizontal, scale: scale, zoom: zoom)
        }
        let resolvedScale = scale.isZero ? System.backingScale : scale
        var imageRect = CGRect(origin: .zero, size: size)
        let bitmap = source.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)!
        let resolvedColor = color.cgColor
        let key = Key(source: ObjectIdentifier(bitmap), color: resolvedColor, colorHash: CFHash(resolvedColor), width: size.width, height: size.height, scale: resolvedScale, flipVertical: flipVertical, flipHorizontal: flipHorizontal)
        let settings = DeviceGraphicsContextSettings.shared
        lock.lock()
        if self.settings != settings {
            entries.removeAll(keepingCapacity: true)
            order = Array(repeating: nil, count: 64)
            first = 0
            count = 0
            retainedBytes = 0
            self.settings = settings
        }
        if let entry = entries[key], entry.source === bitmap {
            lock.unlock()
            return entry.output
        }
        lock.unlock()

        let drawingContext = DrawingContext(size: size, scale: resolvedScale, clear: true)
        drawingContext.withFlippedContext(horizontal: flipHorizontal, vertical: flipVertical) { context in
            let rect = CGRect(origin: .zero, size: drawingContext.size)
            context.interpolationQuality = .high
            context.clip(to: rect, mask: bitmap)
            context.setFillColor(key.color)
            context.fill(rect)
        }
        let image = drawingContext.generateImage()!
        let cost = image.bytesPerRow * image.height
        guard cost <= 64 * 1024 else { return image }
        lock.lock()
        defer { lock.unlock() }
        guard self.settings == settings, DeviceGraphicsContextSettings.shared == settings else { return image }
        if let entry = entries[key] {
            if entry.source === bitmap { return entry.output }
            retainedBytes -= entry.cost
            entries[key] = Entry(source: bitmap, output: image)
            retainedBytes += cost
            while retainedBytes > 1024 * 1024 { evictFirst() }
            return image
        }
        while count >= 64 || retainedBytes + cost > 1024 * 1024 { evictFirst() }
        entries[key] = Entry(source: bitmap, output: image)
        order[(first + count) % order.count] = key
        count += 1
        retainedBytes += cost
        return image
    }

    private func evictFirst() {
        if let key = order[first], let entry = entries.removeValue(forKey: key) { retainedBytes -= entry.cost }
        order[first] = nil
        first = (first + 1) % order.count
        count -= 1
    }
}

public extension NSImage {
    
    func precomposed(_ colors:[NSColor], flipVertical:Bool = false, flipHorizontal:Bool = false, scale: CGFloat = System.backingScale) -> CGImage {
        
        let drawContext:DrawingContext = DrawingContext(size: NSMakeSize(self.size.width, self.size.height), scale: scale, clear: true)
        
        
        let make:(CGContext) -> Void = { [weak self] ctx in
            
            guard let image = self else { return }
            
            let rect = NSMakeRect(0, 0, drawContext.size.width, drawContext.size.height)
            ctx.interpolationQuality = .high
            ctx.clear(rect)
            
            var imageRect:CGRect = NSMakeRect(0, 0, image.size.width, image.size.height)

            let cimage = image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
            
            if !colors.isEmpty {
                ctx.clip(to: rect, mask: cimage!)
                if colors.count > 2 {
                    let preview = AnimatedGradientBackgroundView.generatePreview(size: NSMakeSize(32, 32), colors: colors)
                    ctx.draw(preview, in: rect.focus(preview.size.aspectFilled(rect.size)))
                } else if colors.count > 1 {
                    let rect = NSMakeRect(0, 0, rect.width, rect.height)
                    let gradient = CGGradient.evenlySpaced(Array(colors.reversed()))!
                    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 0.0, y: rect.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                } else if let color = colors.first {
                    ctx.setFillColor(color.cgColor)
                    ctx.fill(rect)
                }
            } else {
                ctx.draw(cimage!, in: imageRect)
            }
            

        }
        
        drawContext.withFlippedContext(horizontal: flipHorizontal, vertical: flipVertical, make)

        return drawContext.generateImage()!
    }
    
    
    func precomposed(_ color:NSColor? = nil, bottomColor: NSColor? = nil, flipVertical:Bool = false, flipHorizontal:Bool = false, scale: CGFloat = System.backingScale, zoom: CGFloat = 1) -> CGImage {
        return PrecomposedImageTintCache.shared.image(self, color: color, bottomColor: bottomColor, flipVertical: flipVertical, flipHorizontal: flipHorizontal, scale: scale, zoom: zoom)
    }

    fileprivate func precomposedWithoutTintCache(_ color:NSColor? = nil, bottomColor: NSColor? = nil, flipVertical:Bool = false, flipHorizontal:Bool = false, scale: CGFloat = System.backingScale, zoom: CGFloat = 1) -> CGImage {
        
        let drawContext:DrawingContext = DrawingContext(size: NSMakeSize(size.width * zoom, size.height * zoom), scale: scale, clear: true)
        
        if zoom != 1 {
            var bp = 0
            bp += 1
        }
        
        
        let make:(CGContext) -> Void = { [weak self] ctx in
            
            guard let image = self else { return }
            
            let rect = NSMakeRect(0, 0, drawContext.size.width * zoom, drawContext.size.height * zoom)
            ctx.interpolationQuality = .high
            ctx.clear(rect)
            
            var imageRect:CGRect = NSMakeRect(0, 0, image.size.width * zoom, image.size.height * zoom)

            let cimage = image.cgImage(forProposedRect: &imageRect, context: nil, hints: nil)
            
            if let color = color {
                ctx.clip(to: rect, mask: cimage!)
                if let bottomColor = bottomColor {
                    let colors = [color, bottomColor]
                    let rect = NSMakeRect(0, 0, rect.width, rect.height)
                    let gradient = CGGradient.evenlySpaced(Array(colors.reversed()))!
                    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0.0, y: 0.0), end: CGPoint(x: 0.0, y: rect.height), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
                } else {
                    ctx.setFillColor(color.cgColor)
                    ctx.fill(rect)
                }
             
            } else {
                ctx.draw(cimage!, in: imageRect)
            }

        }
        
        drawContext.withFlippedContext(horizontal: flipHorizontal, vertical: flipVertical, make)

        return drawContext.generateImage()!
    }
    
}

public extension CGRect {
    var topLeft: CGPoint {
        return self.origin
    }
    
    var topRight: CGPoint {
        return CGPoint(x: self.maxX, y: self.minY)
    }
    
    var bottomLeft: CGPoint {
        return CGPoint(x: self.minX, y: self.maxY)
    }
    
    var bottomRight: CGPoint {
        return CGPoint(x: self.maxX, y: self.maxY)
    }
    
    func makeSize(_ size: NSSize) -> CGRect {
        var rect = self
        rect.size = size
        return rect
    }
    
    var center: CGPoint {
        return CGPoint(x: self.midX, y: self.midY)
    }
    func focus(_ size:NSSize) -> NSRect {
        var x:CGFloat = 0
        var y:CGFloat = 0
        
        x = CGFloat(round((self.width - size.width)/2.0))
        y = CGFloat(round((self.height - size.height)/2.0))
        
        
        return NSMakeRect(x, y, size.width, size.height)
    }
    
    func focusX(_ size:NSSize, y: CGFloat) -> NSRect {
        var x:CGFloat = 0
        
        x = CGFloat(round((self.width - size.width)/2.0))
        
        return NSMakeRect(x, y, size.width, size.height)
    }
    
    func focusY(_ size:NSSize, x: CGFloat) -> NSRect {
        var y:CGFloat = 0
        
        y = CGFloat(round((self.height - size.height)/2.0))
        
        
        return NSMakeRect(x, y, size.width, size.height)
    }
}

public extension CGPoint {
    func offsetBy(dx: CGFloat, dy: CGFloat) -> CGPoint {
        return CGPoint(x: self.x + dx, y: self.y + dy)
    }
    func distance(p2: CGPoint) -> CGFloat {
        let xdst = self.x - p2.x
        let ydst = self.y - p2.y
        return sqrt((xdst * xdst) + (ydst * ydst))
    }
    
    var toScreenPixel: CGPoint {
        return CGPoint(x: floorToScreenPixels(x),
                      y: floorToScreenPixels(y))
    }
}


public enum ImageOrientation {
    case up
    case down
    case left
    case right
    case upMirrored
    case downMirrored
    case leftMirrored
    case rightMirrored
}


public extension CGImage {
    
    var backingSize:NSSize {
        return systemSize// NSMakeSize(CGFloat(width) * 0.5, CGFloat(height) * 0.5)
    }
    
    var halfSize:NSSize {
        return  NSMakeSize(CGFloat(width) * 0.5, CGFloat(height) * 0.5)
    }
    
    var size:NSSize {
        return NSMakeSize(CGFloat(width), CGFloat(height))
    }
    
    var systemSize:NSSize {
        return NSMakeSize(CGFloat(width) / scale, CGFloat(height) / scale)
    }
    
    var backingBounds: NSRect {
        return NSMakeRect(0, 0, backingSize.width, backingSize.height)
    }
    
    var scale:CGFloat {
        return System.backingScale
    }
    
    var _NSImage: NSImage {
        return NSImage(cgImage: self, size: backingSize)
    }

    func highlight(color: NSColor) -> CGImage {
        let image = self
        let context = DrawingContext(size:image.backingSize, scale: System.backingScale, clear:true)
        context.withContext { ctx in
            ctx.clear(NSMakeRect(0, 0, image.backingSize.width, image.backingSize.height))
            let imageRect = NSMakeRect(0, 0, image.backingSize.width, image.backingSize.height)
            
            ctx.clip(to: imageRect, mask: image)
            ctx.setFillColor(color.cgColor)
            ctx.fill(imageRect)
        }
        return context.generateImage() ?? image
    }
    
    func createMatchingBackingDataWithImage(orienation: ImageOrientation, keepColorSpace: Bool = false) -> CGImage?
    {
        var orientedImage: CGImage?
        let imageRef = self
        let originalWidth = imageRef.width
        let originalHeight = imageRef.height
        
        
        
        
        var degreesToRotate: Double
        var swapWidthHeight: Bool
        var mirrored: Bool
        switch orienation {
        case .up:
            degreesToRotate = 0.0
            swapWidthHeight = false
            mirrored = false
            break
        case .upMirrored:
            degreesToRotate = 0.0
            swapWidthHeight = false
            mirrored = true
            break
        case .right:
            degreesToRotate = 90.0
            swapWidthHeight = true
            mirrored = false
            break
        case .rightMirrored:
            degreesToRotate = 90.0
            swapWidthHeight = true
            mirrored = true
            break
        case .down:
            degreesToRotate = 180.0
            swapWidthHeight = false
            mirrored = false
            break
        case .downMirrored:
            degreesToRotate = 180.0
            swapWidthHeight = false
            mirrored = true
            break
        case .left:
            degreesToRotate = -90.0
            swapWidthHeight = true
            mirrored = false
            break
        case .leftMirrored:
            degreesToRotate = -90.0
            swapWidthHeight = true
            mirrored = true
            break
        }
        let radians = degreesToRotate * Double.pi / 180.0
        
        var width: Int
        var height: Int
        if swapWidthHeight {
            width = originalHeight
            height = originalWidth
        } else {
            width = originalWidth
            height = originalHeight
        }
        
        let bytesPerRow = (4 * Int(swapWidthHeight ? imageRef.height : imageRef.width) + 15) & (~15)
        let bitsPerComponent = 8
        let bitmapInfo = CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)

        
        let colorSpace: CGColorSpace
        if keepColorSpace, let imageColorSpace = imageRef.colorSpace, imageColorSpace.model == .rgb {
            colorSpace = imageColorSpace
        } else {
            colorSpace = deviceColorSpace
        }
        let contextRef = CGContext(data: nil, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo.rawValue)
        contextRef?.translateBy(x: CGFloat(width) / 2.0, y: CGFloat(height) / 2.0)
        if mirrored {
            contextRef?.scaleBy(x: -1.0, y: 1.0)
        }
        contextRef?.rotate(by: CGFloat(radians))
        if swapWidthHeight {
            contextRef?.translateBy(x: -CGFloat(height) / 2.0, y: -CGFloat(width) / 2.0)
        } else {
            contextRef?.translateBy(x: -CGFloat(width) / 2.0, y: -CGFloat(height) / 2.0)
        }
        contextRef?.draw(imageRef, in: CGRect(x: 0.0, y: 0.0, width: CGFloat(originalWidth), height: CGFloat(originalHeight)))
        orientedImage = contextRef?.makeImage()
        
        return orientedImage
    }
}

public extension Array {
    func randomElements(_ count: Int) -> [Element] {
        var indexes:[Int] = []
        if self.count <= count {
            return self.shuffled()
        }
        for _ in 0 ..< count {
            var finding = true
            while finding {
                let index = Int.random(in: 0 ..< self.count)
                if !indexes.contains(index) {
                    indexes.append(index)
                    finding = false
                }
            }
        }
        
        return indexes.reduce([], { current, index in
            var current = current
            current.append(self[index])
            return current
        })
    }
}

public extension NSScrollView {
    var contentOffset: NSPoint {
        return contentView.bounds.origin
    }
}

public struct LayoutPositionFlags : OptionSet {
    
    public var rawValue: UInt32
    
    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }
    
    public init() {
        self.rawValue = 0
    }
    
    public init(_ flags: LayoutPositionFlags) {
        var rawValue: UInt32 = 0
        
        if flags.contains(LayoutPositionFlags.none) {
            rawValue |= LayoutPositionFlags.none.rawValue
        }
        
        if flags.contains(LayoutPositionFlags.top) {
            rawValue |= LayoutPositionFlags.top.rawValue
        }
        
        if flags.contains(LayoutPositionFlags.bottom) {
            rawValue |= LayoutPositionFlags.bottom.rawValue
        }
        
        if flags.contains(LayoutPositionFlags.left) {
            rawValue |= LayoutPositionFlags.left.rawValue
        }
        if flags.contains(LayoutPositionFlags.right) {
            rawValue |= LayoutPositionFlags.right.rawValue
        }
        if flags.contains(LayoutPositionFlags.inside) {
            rawValue |= LayoutPositionFlags.inside.rawValue
        }
        
        self.rawValue = rawValue
    }
    
    public static let none: LayoutPositionFlags = []
    public static let top = LayoutPositionFlags(rawValue: 1 << 0)
    public static let bottom = LayoutPositionFlags(rawValue: 1 << 1)
    public static let left = LayoutPositionFlags(rawValue: 1 << 2)
    public static let right = LayoutPositionFlags(rawValue: 1 << 3)
    public static let inside = LayoutPositionFlags(rawValue: 1 << 4)
}

public struct NSRectCorner: OptionSet {
    public let rawValue: UInt
    
    public static let none: NSRectCorner = []
    public static let topLeft = NSRectCorner(rawValue: 1 << 0)
    public static let topRight = NSRectCorner(rawValue: 1 << 1)
    public static let bottomLeft = NSRectCorner(rawValue: 1 << 2)
    public static let bottomRight = NSRectCorner(rawValue: 1 << 3)
    public static var all: NSRectCorner {
        return [.topLeft, .topRight, .bottomLeft, .bottomRight]
    }
    
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
    
}

public extension CGContext {
    func round(_ size:NSSize,_ corners:CGFloat = .cornerRadius) {
        let minx:CGFloat = 0, midx = size.width/2.0, maxx = size.width
        let miny:CGFloat = 0, midy = size.height/2.0, maxy = size.height
        
        self.move(to: NSMakePoint(minx, midy))
        self.addArc(tangent1End: NSMakePoint(minx, miny), tangent2End: NSMakePoint(midx, miny), radius: corners)
        self.addArc(tangent1End: NSMakePoint(maxx, miny), tangent2End: NSMakePoint(maxx, midy), radius: corners)
        self.addArc(tangent1End: NSMakePoint(maxx, maxy), tangent2End: NSMakePoint(midx, maxy), radius: corners)
        self.addArc(tangent1End: NSMakePoint(minx, maxy), tangent2End: NSMakePoint(minx, midy), radius: corners)
        
        self.closePath()
        self.clip()

    }
    
    
    func drawRoundedRect(rect: CGRect, topLeftRadius: CGFloat = 0, topRightRadius: CGFloat = 0, bottomLeftRadius: CGFloat = 0, bottomRightRadius: CGFloat = 0) {
        let context = self
        context.beginPath()
        
        let topLeft = rect.origin
        let topRight = CGPoint(x: rect.origin.x + rect.size.width, y: rect.origin.y)
        let bottomRight = CGPoint(x: rect.origin.x + rect.size.width, y: rect.origin.y + rect.size.height)
        let bottomLeft = CGPoint(x: rect.origin.x, y: rect.origin.y + rect.size.height)
        
        context.move(to: CGPoint(x: topLeft.x + topLeftRadius, y: topLeft.y))
        context.addLine(to: CGPoint(x: topRight.x - topRightRadius, y: topRight.y))
        context.addArc(tangent1End: topRight, tangent2End: bottomRight, radius: topRightRadius)
        context.addLine(to: CGPoint(x: bottomRight.x, y: bottomRight.y - bottomRightRadius))
        context.addArc(tangent1End: bottomRight, tangent2End: bottomLeft, radius: bottomRightRadius)
        context.addLine(to: CGPoint(x: bottomLeft.x + bottomLeftRadius, y: bottomLeft.y))
        context.addArc(tangent1End: bottomLeft, tangent2End: topLeft, radius: bottomLeftRadius)
        context.addLine(to: CGPoint(x: topLeft.x, y: topLeft.y + topLeftRadius))
        context.addArc(tangent1End: topLeft, tangent2End: topRight, radius: topLeftRadius)
        
        context.closePath()
        
        context.fillPath()
    }
    
    func round(_ frame: NSRect, flags: LayoutPositionFlags) {
        var topLeftRadius: CGFloat = 0
        var bottomLeftRadius: CGFloat = 0
        var topRightRadius: CGFloat = 0
        var bottomRightRadius: CGFloat = 0
        
        let minx:CGFloat = frame.minX, midx = frame.midX, maxx = frame.width
        let miny:CGFloat = frame.minY, midy = frame.midY, maxy = frame.height
        
        self.move(to: NSMakePoint(minx, midy))
        
        
        if flags.contains(.top) && flags.contains(.left) {
            topLeftRadius = .cornerRadius
        }
        if flags.contains(.top) && flags.contains(.right) {
            topRightRadius = .cornerRadius
        }
        if flags.contains(.bottom) && flags.contains(.left) {
            bottomLeftRadius = .cornerRadius
        }
        if flags.contains(.bottom) && flags.contains(.right) {
            bottomRightRadius = .cornerRadius
        }
        
        self.addArc(tangent1End: NSMakePoint(minx, miny), tangent2End: NSMakePoint(midx, miny), radius: bottomLeftRadius)
        self.addArc(tangent1End: NSMakePoint(maxx, miny), tangent2End: NSMakePoint(maxx, midy), radius: bottomRightRadius)
        self.addArc(tangent1End: NSMakePoint(maxx, maxy), tangent2End: NSMakePoint(midx, maxy), radius: topRightRadius)
        self.addArc(tangent1End: NSMakePoint(minx, maxy), tangent2End: NSMakePoint(minx, midy), radius: topLeftRadius)
        
        self.closePath()
        self.clip()
    }
    
    
    static func round(frame: NSRect, cornerRadius: CGFloat, rectCorner: NSRectCorner) -> CGPath {
        
        let path = CGMutablePath()
        
        let minx:CGFloat = 0, midx = frame.width/2.0, maxx = frame.width
        let miny:CGFloat = frame.height, midy = frame.height/2.0, maxy: CGFloat = 0
        
        path.move(to: NSMakePoint(minx, midy))
        
        var topLeftRadius: CGFloat = 0
        var bottomLeftRadius: CGFloat = 0
        var topRightRadius: CGFloat = 0
        var bottomRightRadius: CGFloat = 0
        
        
        if rectCorner.contains(.topLeft) {
            topLeftRadius = cornerRadius
        }
        if rectCorner.contains(.topRight) {
            topRightRadius = cornerRadius
        }
        if rectCorner.contains(.bottomLeft) {
            bottomLeftRadius = cornerRadius
        }
        if rectCorner.contains(.bottomRight) {
            bottomRightRadius = cornerRadius
        }
        
        
        
        path.addArc(tangent1End: NSMakePoint(minx, miny), tangent2End: NSMakePoint(midx, miny), radius: bottomLeftRadius)
        path.addArc(tangent1End: NSMakePoint(maxx, miny), tangent2End: NSMakePoint(maxx, midy), radius: bottomRightRadius)
        path.addArc(tangent1End: NSMakePoint(maxx, maxy), tangent2End: NSMakePoint(midx, maxy), radius: topRightRadius)
        path.addArc(tangent1End: NSMakePoint(minx, maxy), tangent2End: NSMakePoint(minx, midy), radius: topLeftRadius)
        
        if rectCorner.contains(.topLeft) {
             path.move(to: NSMakePoint(minx, cornerRadius))
        } else {
             path.move(to: NSMakePoint(minx, maxy))
        }
       
        
        path.addLine(to: NSMakePoint(minx, midy))
        
        //cgPath.closePath()
        return path
        //cgPath.clip()
    }
}



public extension NSRange {
    var min:Int {
        return self.location
    }
    var max:Int {
        return self.location + self.length
    }
    var isEmpty: Bool {
        return self.length == 0
    }
    
    var isNone: Bool {
        return self.length == 0 && self.location == 0
    }
    
    func indexIn(_ index: Int) -> Bool {
        return NSLocationInRange(index, self)
    }
    init(string: String, range: Range<String.Index>) {
        let utf8 = string.utf16

        let location = utf8.distance(from: utf8.startIndex, to: range.lowerBound)
        let length = utf8.distance(from: range.lowerBound, to: range.upperBound)

        self.init(location: location, length: length)
    }
}

public extension NSBezierPath {
    var _cgPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)

        for i in 0..<self.elementCount {
            switch self.element(at: i, associatedPoints: &points) {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }
        return path
    }

}


public extension NSRect {
    
    func apply(multiplier: NSSize) -> NSRect {
        return NSMakeRect(round(minX * multiplier.width), round(minY * multiplier.height), round(width * multiplier.width), round(height * multiplier.height))
    }
    
    func scaleLinear(amount: Double) -> CGRect {
        guard amount != 1.0, amount > 0.0 else { return self }
        let ratio = ((1.0 - amount) / 2.0)
        return insetBy(dx: width * ratio, dy: height * ratio)
    }

    func scaleArea(amount: Double) -> CGRect {
        return scaleLinear(percent: sqrt(amount))
    }

    func scaleLinear(percent: Double) -> CGRect {
        return scaleLinear(amount: percent / 100)
    }

    func scaleArea(percent: Double) -> CGRect {
        return scaleArea(amount: percent / 100)
    }
    
    func rotate90Degress(parentSize: NSSize) -> NSRect {

       
        
        let width: CGFloat = parentSize.width
        let height: CGFloat = parentSize.height
        
        
        let transform = NSAffineTransform()
        
     //   transform.translateX(by: 0, yBy: height)
        
        transform.rotate(byDegrees: 90)
        transform.translateX(by: 0, yBy: -height)

        
        //transform.scaleX(by: 1, yBy: -1)

        let path = NSBezierPath()
        path.appendRect(NSMakeRect(0, 0, width, height))
        path.appendRect(self)
        
        let newPath = transform.transform(path)
        
        var rect = NSMakeRect(0, 0, self.height, self.width)
        for i in 5 ..< newPath.elementCount - 2 {
            var points = [NSPoint](repeating: NSZeroPoint, count: 1)
            
            switch newPath.element(at: i, associatedPoints: &points) {
            case .moveTo:
                let point = points[0]
                rect.origin.x = (height - point.x)
                rect.origin.y = (width - point.y - self.width)
            default:
                break
            }
        }
        
        
        
        return rect
    }
}

public extension NSEdgeInsets {

    init(left:CGFloat = 0, right:CGFloat = 0, top:CGFloat = 0, bottom:CGFloat = 0) {
        self.init(top: top, left: left, bottom: bottom, right: right)
    }
}


public extension Int32 {
    var isFuture: Bool {
        return self > Int32(Date().timeIntervalSince1970)
    }
    var decemial: Double {
        return Double(self) / 10
    }
}

public extension Double {
    var string: String {
        return self.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", self) : String(self)
    }
}

public extension Int64 {
    
    func prettyFormatter(_ n: Int64, iteration: Int, rounded: Bool = false) -> String {
        let keys = ["K", "M", "B", "T"]
        var d = Double((n / 100)) / 10.0
        if rounded {
            d = floor(d)
        }
        let isRound:Bool = (Int(d) * 10) % 10 == 0
        if d < 1000 {
            if d == 1 {
                return "\(Int(d))\(keys[iteration])"
            } else {
                var result = "\((d > 99.9 || isRound || (!isRound && d > 9.99)) ? d * 10 / 10 : d)"
                if result.hasSuffix(".0") {
                    result = result.prefix(result.count - 2)
                }
                return result + "\(keys[iteration])"
            }
        }
        else {
            return self.prettyFormatter(Int64(d), iteration: iteration + 1, rounded: rounded)
        }
    }
    
    var prettyRounded: String {
        if self < 1000 {
            return "\(self)"
        }
        return self.prettyFormatter(self, iteration: 0, rounded: true).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }
    
    var prettyNumber:String {
        if self < 1000 {
            return "\(self)"
        }
        
        return self.prettyFormatter(self, iteration: 0).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }
    var separatedNumber: String {
        if self < 1000 {
            return "\(self)"
        }
        let string = "\(self)"
        
        let length: Int = string.length
        var result:String = ""
        var index:Int = 0
        while index < length {
            let modulo = length % 3
            if index == 0 && modulo != 0 {
                result = string.nsstring.substring(with: NSMakeRange(index, modulo))
                index += modulo
            } else {
                let count:Int = 3
                let value = string.nsstring.substring(with: NSMakeRange(index, count))
                if index == 0 {
                    result = value
                } else {
                    result += " " + value
                }
                index += count
            }
        }
        return result
    }
}




public extension Int {
    
    func prettyFormatter(_ n: Int, iteration: Int, rounded: Bool = false) -> String {
        let keys = ["K", "M", "B", "T"]
        var d = Double((n / 100)) / 10.0
        if rounded {
            d = floor(d)
        }
        let isRound:Bool = (Int(d) * 10) % 10 == 0
        if d < 1000 {
            if d == 1 {
                return "\(Int(d))\(keys[iteration])"
            } else {
                var result = "\((d > 99.9 || isRound || (!isRound && d > 9.99)) ? d * 10 / 10 : d)"
                if result.hasSuffix(".0") {
                    result = result.prefix(result.count - 2)
                }
                return result + "\(keys[iteration])"
            }
        }
        else {
            return self.prettyFormatter(Int(d), iteration: iteration + 1, rounded: rounded)
        }
    }
    
    var prettyRounded: String {
        if self < 1000 {
            return "\(self)"
        }
        return self.prettyFormatter(self, iteration: 0, rounded: true).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }
    
    var prettyNumber:String {
        if self < 1000 {
            return "\(self)"
        }
        
        return self.prettyFormatter(self, iteration: 0).replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".")
    }
    var separatedNumber: String {
        if self < 1000 {
            return "\(self)"
        }
        let string = "\(self)"
        
        let length: Int = string.length
        var result:String = ""
        var index:Int = 0
        while index < length {
            let modulo = length % 3
            if index == 0 && modulo != 0 {
                result = string.nsstring.substring(with: NSMakeRange(index, modulo))
                index += modulo
            } else {
                let count:Int = 3
                let value = string.nsstring.substring(with: NSMakeRange(index, count))
                if index == 0 {
                    result = value
                } else {
                    result += " " + value
                }
                index += count
            }
        }
        return result
    }
}


public extension NSProgressIndicator {
    func set(color:NSColor) {
        let color = color.usingColorSpace(NSColorSpace.sRGB)

        let colorPoly = CIFilter(name: "CIColorPolynomial")
        if let colorPoly = colorPoly, let color = color {
            colorPoly.setDefaults()
            let redVector = CIVector(x: color.redComponent, y: 0, z: 0, w: 0)
            let greenVector = CIVector(x: color.greenComponent, y: 0, z: 0, w: 0)
            let blueVector = CIVector(x: color.blueComponent, y: 0, z: 0, w: 0)
            
            colorPoly.setValue(redVector, forKey: "inputRedCoefficients")
            colorPoly.setValue(greenVector, forKey: "inputGreenCoefficients")
            colorPoly.setValue(blueVector, forKey: "inputBlueCoefficients")
            self.contentFilters = [colorPoly]
        }
    }
}


public extension NSTextField {
    func setSelectionRange(_ range: NSRange) {
        textView?.setSelectedRange(range)
    }
    
    var selectedRange: NSRange {
        if let textView = textView {
            return textView.selectedRange
        }
        return NSMakeRange(0, 0)
    }
    
    func setCursorToEnd() {
        self.setSelectionRange(NSRange(location: self.stringValue.length, length: 0))
    }
    
    var textView:NSTextView? {
        let textView = (self.window?.fieldEditor(true, for: self) as? NSTextView)
        textView?.backgroundColor = .clear
        textView?.drawsBackground = true
        return textView
    }
}

public extension NSTextView {
    func selectAllText() {
        setSelectedRange(NSMakeRange(0, self.string.length))
    }
    
    func appendText(_ text: String) -> Void {
        let inputText = self.attributedString().mutableCopy() as! NSMutableAttributedString
        
        if selectedRange.upperBound - selectedRange.lowerBound > 0 {
            inputText.replaceCharacters(in: NSMakeRange(selectedRange.lowerBound, selectedRange.upperBound - selectedRange.lowerBound), with: NSAttributedString(string: text))
        } else {
            inputText.insert(NSAttributedString(string: text), at: selectedRange.lowerBound)
        }
        self.string = inputText.string
    }
}





public extension Sequence where Iterator.Element: Hashable {
    var uniqueElements: [Iterator.Element] {
        return self.reduce([], { current, value in
            if current.contains(value) {
                return current
            } else {
                return current + [value]
            }
        })
    }
}
public extension Sequence where Iterator.Element: Equatable {
    var uniqueElements: [Iterator.Element] {
        return self.reduce([], { current, value in
            if current.contains(value) {
                return current
            } else {
                return current + [value]
            }
        })
//        return self.reduce([]){
//            uniqueElements, element in
//
//            uniqueElements.contains(element)
//                ? uniqueElements
//                : uniqueElements + [element]
//        }
    }
}
public extension String {
    func capitalizingFirstLetter() -> String {
        return prefix(1).uppercased() + dropFirst()
    }
    
    mutating func capitalizeFirstLetter() {
        self = self.capitalizingFirstLetter()
    }
}



class GestureUtils{
    /**
     * To avoid duplicate code we could extract the content of this method into an GestureUtils method. Return nil if there isn't 2 touches and set the array only if != nil
     */
    static func twoFingersTouches(_ view:NSView, _ event:NSEvent)->[String:NSTouch]?{
        var twoFingersTouches:[String:NSTouch]? = nil//NSMutualDictionary was used before and didn't require casting id to string, revert if side-effects manifest
        let touches:Set<NSTouch> = event.touches(matching:NSTouch.Phase.any, in: view)//touchesMatchingPhase:NSTouchPhaseAny inView:self
        if(touches.count == 2){
            twoFingersTouches = [String:NSTouch]()
            for touch in touches {
                twoFingersTouches!["\((touch).identity)"] = touch/*assigns each touch to the identity of the same touch*///was [ setObject: forKey:];
            }
        }
        return twoFingersTouches
    }
    /**
     * Detects 2 finger (left/right) swipe gesture
     * NOTE: either of 3 enums is returned: .leftSwipe, .rightSwipe .none
     * TODO: also make up and down swipe detectors, and do more research into how this could be done easier. Maybe you even have some clues in the notes about gestures etc.
     * Conceptually:
     * 1. Record 2 .began touchEvents
     * 2. Record 2 .ended touchEvents
     * 3. Measure the distance between .began and .ended and assert if it is within threshold
     */
    static func swipe(_ view:NSView, _ event:NSEvent, _ beginningTouches:[String:NSTouch]) -> SwipeType{
        let endingTouches:Set<NSTouch> = event.touches(matching: NSTouch.Phase.ended, in: view)
        if endingTouches.count == 2 {
            var magnitudesX:[CGFloat] = []/*magnitude definition: the great size or extent of something.*/
            let magnitudesY:[CGFloat] = []/*magnitude definition: the great size or extent of something.*/
            for endingTouch in endingTouches {
                guard let beginningTouch:NSTouch = beginningTouches["\(endingTouch.identity)"] else {continue}
                
                let magnitudeX:CGFloat = endingTouch.normalizedPosition.x - beginningTouch.normalizedPosition.x
                magnitudesX.append(magnitudeX)
                
                let magnitudeY:CGFloat = endingTouch.normalizedPosition.y - beginningTouch.normalizedPosition.y
                magnitudesX.append(magnitudeY)
            }
            
            let kSwipeMinimumLength:CGFloat = 0.1

            
            var sumX:CGFloat = 0
            for magnitudeX in magnitudesX {
                sumX += magnitudeX
            }
            
            var sumY:CGFloat = 0
            for magnitudeY in magnitudesY {
                sumY += magnitudeY
            }
            
            let absoluteSumY:CGFloat = abs(sumY)
            if (absoluteSumY > kSwipeMinimumLength) {return .none}
            
            let absoluteSumX:CGFloat = abs(sumX)/*force value to be positive*/
            if (absoluteSumX < kSwipeMinimumLength) {return .none}/*Assert if the absolute sum is long enough to be considered a complete gesture*/
            if (sumX > 0){
                return .right
            }else /*if(sum < 0)*/{
                return .left
            }
        }
        return .none/*no swipe direction detected*/
    }
}
public extension NSView {
    
    var effectiveVisibleRect: NSRect {
        var visibleRect = self.visibleRect
        if let tableView = self.enclosingScrollView as? TableView {
            if tableView.contentInsets.top > 0 {
                let rect = self.convert(self.bounds, to: tableView.documentView)
                let visible = NSMakeRect(0, tableView.documentOffset.y, tableView.frame.width, tableView.frame.height)
                if rect.minY < visible.minY {
                    visibleRect = CGRect(origin: CGPoint(x: 0, y: 0), size: NSMakeSize(rect.width, rect.minY - visible.minY + rect.height))
                } else {
                    let height = visible.maxY - rect.minY - tableView.contentInsets.top
                    visibleRect = CGRect(origin: CGPoint(x: 0, y: rect.height - height), size: NSMakeSize(rect.width, height))
                }
            }
        }
        return visibleRect
    }
    
    func setAnchorPoint(anchorPoint: CGPoint) {
        guard let layer = self.layer else {
            return
        }
        
        var newPoint = CGPoint(x: bounds.size.width * anchorPoint.x, y: bounds.size.height * anchorPoint.y)
        var oldPoint = CGPoint(x: bounds.size.width * layer.anchorPoint.x, y: bounds.size.height * layer.anchorPoint.y)

        newPoint = newPoint.applying(layer.affineTransform())
        oldPoint = oldPoint.applying(layer.affineTransform())

        var position = layer.position

        position.x -= oldPoint.x
        position.x += newPoint.x

        position.y -= oldPoint.y
        position.y += newPoint.y
        
        layer.position = position
        layer.anchorPoint = anchorPoint
    }
    
}

public extension NSWindow {
    var bounds: NSRect {
        return NSMakeRect(0, 0, frame.width, frame.height)
    }
}



public extension String {
    var isDirectory: Bool {
        var isDir: ObjCBool = false
        _ = FileManager.default.fileExists(atPath: self, isDirectory: &isDir)
        return isDir.boolValue
    }
}



public extension Formatter {
    static let withSeparator: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = NSLocale.current
        formatter.numberStyle = .decimal
        return formatter
    }()
}

public extension BinaryInteger {
    var formattedWithSeparator: String {
        return Formatter.withSeparator.string(for: self) ?? ""
    }
}


public extension String {
    var persistentHashValue: UInt64 {
        var result = UInt64 (5381)
        let buf = [UInt8](self.utf8)
        for b in buf {
            result = 127 * (result & 0x00ffffffffffffff) + UInt64(b)
        }
        return result
    }
}
extension NSEdgeInsets : @retroactive Equatable {
    public static func ==(lhs: NSEdgeInsets, rhs: NSEdgeInsets) -> Bool {
        return lhs.left == rhs.left && lhs.right == rhs.right && lhs.bottom == rhs.bottom && lhs.top == rhs.top
    }
    public var isEmpty: Bool {
        return self.left == 0 && self.right == 0 && self.top == 0 && self.bottom == 0
    }
}


public func arc4random64() -> Int64 {
    return Int64.random(in: Int64.min ... Int64.max)
}


public func performSubviewRemoval(_ view: NSView, animated: Bool, duration: Double = 0.2, timingFunction: CAMediaTimingFunctionName = .easeOut, checkCompletion: Bool = false, scale: Bool = false, scaleHorizontal: Bool = false, scaleVertical: Bool = false, scaleTo: CGFloat? = nil, completed:((Bool)->Void)? = nil) {
    
    if let liquidGlass = view as? LiquidGlassView {
        if liquidGlass.appearanceContainer !== liquidGlass {
            liquidGlass.appearanceContainer.removeFromSuperview()
            liquidGlass.effectView.removeFromSuperview()
        }
    }
    
    if animated {
        
        let from = view.layer?.presentation()?.opacity ?? view.layer?.opacity ?? 1
        view.layer?.animateAlpha(from: CGFloat(from), to: 0, duration: duration, timingFunction: timingFunction, removeOnCompletion: false, completion: { [weak view] finish in
            completed?(finish)
            if checkCompletion {
                if finish {
                    view?.removeFromSuperview()
                }
            } else {
                view?.removeFromSuperview()
            }
        })
        if scale {
            view.layer?.animateScaleCenter(from: 1, to: 0.01, duration: duration, removeOnCompletion: false, timingFunction: timingFunction)
        } else if scaleHorizontal {
            view.layer?.animateScaleXCenter(from: 1, to: 0.01, duration: duration, removeOnCompletion: false, timingFunction: timingFunction)
        } else if scaleVertical {
            view.layer?.animateScaleYCenter(from: 1, to: 0.01, duration: duration, removeOnCompletion: false, timingFunction: timingFunction)
        } else if let scaleTo = scaleTo {
            view.layer?.animateScaleCenter(from: 1, to: scaleTo, duration: duration, removeOnCompletion: false, timingFunction: timingFunction)
        }
    } else {
        view.removeFromSuperview()
    }
}

public func performSublayerRemoval(_ view: CALayer, animated: Bool, duration: Double = 0.2, timingFunction: CAMediaTimingFunctionName = .easeOut, checkCompletion: Bool = false, scale: Bool = false, scaleTo: CGFloat? = nil, completed:((Bool)->Void)? = nil) {
    if animated {
        view.animateAlpha(from: CGFloat(view.opacity), to: 0, duration: duration, timingFunction: timingFunction, removeOnCompletion: false, completion: { [weak view] finish in
            completed?(finish)
            if checkCompletion {
                if finish {
                    view?.removeFromSuperlayer()
                }
            } else {
                view?.removeFromSuperlayer()
            }
        })
        if scale {
            view.animateScale(from: 1, to: 0.01, duration: duration, timingFunction: timingFunction, removeOnCompletion: false)
        } else if let scaleTo = scaleTo {
            view.animateScale(from: 1, to: scaleTo, duration: duration, timingFunction: timingFunction, removeOnCompletion: false)
        }
    } else {
        view.removeFromSuperlayer()
    }
}

public func performSubviewPosRemoval(_ view: NSView, pos: NSPoint, animated: Bool, duration: Double = 0.2, timingFunction: CAMediaTimingFunctionName = .easeInEaseOut) {
    if animated {
        view.layer?.animatePosition(from: view.frame.origin, to: pos, duration: duration, timingFunction: timingFunction, removeOnCompletion: false, completion: { [weak view] _ in
            view?.removeFromSuperview()
        })
    } else {
        view.removeFromSuperview()
    }
}

public extension NSView {
    override class func accessibilityFocusedUIElement() -> Any? {
        return nil
    }
}



extension CGPoint {
    public init(vector: CGVector) {
        self.init(x: vector.dx, y: vector.dy)
    }
    
    
    public init(angle: CGFloat) {
        self.init(x: cos(angle), y: sin(angle))
    }
    
    
    public mutating func offset(dx: CGFloat, dy: CGFloat) -> CGPoint {
        x += dx
        y += dy
        return self
    }
    
    public func length() -> CGFloat {
        return sqrt(x*x + y*y)
    }
    
    public func lengthSquared() -> CGFloat {
        return x*x + y*y
    }
    
    func normalized() -> CGPoint {
        let len = length()
        return len>0 ? self / len : CGPoint.zero
    }
    
    public mutating func normalize() -> CGPoint {
        self = normalized()
        return self
    }
    
    public func distanceTo(_ point: CGPoint) -> CGFloat {
        return (self - point).length()
    }
    
    public var angle: CGFloat {
        return atan2(y, x)
    }
    
    public var cgSize: CGSize {
        return CGSize(width: x, height: y)
    }
    
    func rotate(origin: CGPoint, angle: CGFloat) -> CGPoint {
        let point = self - origin
        let s = sin(angle)
        let c = cos(angle)
        return CGPoint(x: c * point.x - s * point.y,
                       y: s * point.x + c * point.y) + origin
    }
}

public extension CGSize {
    var cgPoint: CGPoint {
        return CGPoint(x: width, y: height)
    }
    
    init(point: CGPoint) {
        self.init(width: point.x, height: point.y)
    }
    
    func centered(around position: CGPoint) -> CGRect {
        return CGRect(origin: CGPoint(x: position.x - self.width / 2.0, y: position.y - self.height / 2.0), size: self)
    }
    
    func centered(in rect: CGRect) -> CGRect {
        let origin = CGPoint(
            x: rect.origin.x + (rect.width - self.width) / 2,
            y: rect.origin.y + (rect.height - self.height) / 2
        )
        return CGRect(origin: origin, size: self)
    }

}

public func + (left: CGPoint, right: CGPoint) -> CGPoint {
    return CGPoint(x: left.x + right.x, y: left.y + right.y)
}

public func += (left: inout CGPoint, right: CGPoint) {
    left = left + right
}

public func + (left: CGPoint, right: CGVector) -> CGPoint {
    return CGPoint(x: left.x + right.dx, y: left.y + right.dy)
}

public func += (left: inout CGPoint, right: CGVector) {
    left = left + right
}

public func + (left: CGSize, right: CGSize) -> CGSize { return CGSize(width: left.width + right.width, height: left.height + right.height) }

public func - (left: CGPoint, right: CGPoint) -> CGPoint { return CGPoint(x: left.x - right.x, y: left.y - right.y) }
public func - (left: CGSize, right: CGSize) -> CGSize { return CGSize(width: left.width - right.width, height: left.height - right.height) }
public func - (left: CGSize, right: CGPoint) -> CGSize { return CGSize(width: left.width - right.x, height: left.height - right.x) }
public func - (left: CGPoint, right: CGSize) -> CGPoint { return CGPoint(x: left.x - right.width, y: left.y - right.height) }

public func -= (left: inout CGPoint, right: CGPoint) {
    left = left - right
}

public func - (left: CGPoint, right: CGVector) -> CGPoint {
    return CGPoint(x: left.x - right.dx, y: left.y - right.dy)
}

public func -= (left: inout CGPoint, right: CGVector) {
    left = left - right
}

public func *= (left: inout CGPoint, right: CGPoint) {
    left = left * right
}

public func * (point: CGPoint, scalar: CGFloat) -> CGPoint { return CGPoint(x: point.x * scalar, y: point.y * scalar) }
public func * (point: CGSize, scalar: CGFloat) -> CGSize { return CGSize(width: point.width * scalar, height: point.height * scalar) }

public func *= (point: inout CGPoint, scalar: CGFloat) { point = point * scalar }

public func * (left: CGPoint, right: CGVector) -> CGPoint {
    return CGPoint(x: left.x * right.dx, y: left.y * right.dy)
}

public func *= (left: inout CGPoint, right: CGVector) {
    left = left * right
}

public func / (left: CGPoint, right: CGPoint) -> CGPoint { return CGPoint(x: left.x / right.x, y: left.y / right.y) }
public func / (left: CGSize, right: CGSize) -> CGSize { return CGSize(width: left.width / right.width, height: left.height / right.height) }
public func / (left: CGPoint, right: CGSize) -> CGPoint { return CGPoint(x: left.x / right.width, y: left.y / right.height) }
public func / (left: CGSize, right: CGPoint) -> CGSize { return CGSize(width: left.width / right.x, height: left.height / right.y) }
public func /= (left: inout CGPoint, right: CGPoint) { left = left / right }
public func /= (left: inout CGSize, right: CGSize) { left = left / right }
public func /= (left: inout CGSize, right: CGPoint) { left = left / right }
public func /= (left: inout CGPoint, right: CGSize) { left = left / right }


public func / (point: CGPoint, scalar: CGFloat) -> CGPoint { return CGPoint(x: point.x / scalar, y: point.y / scalar) }
public func / (point: CGSize, scalar: CGFloat) -> CGSize { return CGSize(width: point.width / scalar, height: point.height / scalar) }

public func /= (point: inout CGPoint, scalar: CGFloat) {
    point = point / scalar
}

public func / (left: CGPoint, right: CGVector) -> CGPoint {
    return CGPoint(x: left.x / right.dx, y: left.y / right.dy)
}

public func / (left: CGSize, right: CGVector) -> CGSize {
    return CGSize(width: left.width / right.dx, height: left.height / right.dy)
}

public func /= (left: inout CGPoint, right: CGVector) {
    left = left / right
}

public func * (left: CGPoint, right: CGPoint) -> CGPoint { return CGPoint(x: left.x * right.x, y: left.y * right.y) }
public func * (left: CGPoint, right: CGSize) -> CGPoint { return CGPoint(x: left.x * right.width, y: left.y * right.height) }
public func *= (left: inout CGPoint, right: CGSize) { left = left * right }
public func * (left: CGSize, right: CGSize) -> CGSize { return CGSize(width: left.width * right.width, height: left.height * right.height) }
public func *= (left: inout CGSize, right: CGSize) { left = left * right }
public func * (left: CGSize, right: CGPoint) -> CGSize { return CGSize(width: left.width * right.x, height: left.height * right.y) }
public func *= (left: inout CGSize, right: CGPoint) { left = left * right }


public func lerp(start: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
    return start + (end - start) * t
}

public func abs(_ point: CGPoint) -> CGPoint {
    return CGPoint(x: abs(point.x), y: abs(point.y))
}

extension CGSize {
    var isValid: Bool {
        return width > 0 && height > 0 && width != .infinity && height != .infinity && width != .nan && height != .nan
    }
    
    var ratio: CGFloat {
        return width / height
    }
}


public extension CGRect {
    static var identity: CGRect {
        return CGRect(x: 0, y: 0, width: 1, height: 1)
    }
    
    var rounded: CGRect {
        return CGRect(x: origin.x.rounded(),
                      y: origin.y.rounded(),
                      width: width.rounded(.up),
                      height: height.rounded(.up))
    }
    
    var toScreenPixel: CGRect {
        return CGRect(x: floorToScreenPixels(origin.x),
                      y: floorToScreenPixels(origin.y),
                      width: floorToScreenPixels(width),
                      height: floorToScreenPixels(height))
    }
    
    var mirroredVertically: CGRect {
        return CGRect(x: origin.x,
                      y: 1.0 - (origin.y + height),
                      width: width,
                      height: height)
    }
}

extension CGAffineTransform {
    func inverted(with size: CGSize) -> CGAffineTransform {
        var transform = self
        let transformedSize = CGRect(origin: .zero, size: size).applying(transform).size
        transform.tx /= transformedSize.width;
        transform.ty /= transformedSize.height;
        transform = transform.inverted()
        transform.tx *= transformedSize.width;
        transform.ty *= transformedSize.height;
        return transform
    }
}


public extension CGFloat {
    func rounded(toPlaces places:Int) -> CGFloat {
        let divisor = pow(10.0, CGFloat(places))
        return (self * divisor).rounded() / divisor
    }
}



public func generateRoundedRectWithTailPath(rectSize: CGSize, cornerRadius: CGFloat? = nil, tailSize: CGSize = CGSize(width: 20.0, height: 9.0), tailRadius: CGFloat = 4.0, tailPosition: CGFloat? = 0.5, transformTail: Bool = true) -> CGPath {
    let cornerRadius: CGFloat = cornerRadius ?? rectSize.height / 2.0
    let tailWidth: CGFloat = tailSize.width
    let tailHeight: CGFloat = tailSize.height

    let rect = CGRect(origin: CGPoint(x: 0.0, y: tailHeight), size: rectSize)
    
    guard let tailPosition = tailPosition else {
        return CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    }

    let cutoff: CGFloat = 0.27
    
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))

    var leftArcEndAngle: CGFloat = .pi / 2.0
    var leftConnectionArcRadius = tailRadius
    var tailLeftHalfWidth: CGFloat = tailWidth / 2.0
    var tailLeftArcStartAngle: CGFloat = -.pi / 4.0
    var tailLeftHalfRadius = tailRadius
    
    var rightArcStartAngle: CGFloat = -.pi / 2.0
    var rightConnectionArcRadius = tailRadius
    var tailRightHalfWidth: CGFloat = tailWidth / 2.0
    var tailRightArcStartAngle: CGFloat = .pi / 4.0
    var tailRightHalfRadius = tailRadius
    
    if transformTail {
        if tailPosition < 0.5 {
            let fraction = max(0.0, tailPosition - 0.15) / 0.35
            leftArcEndAngle *= fraction
            
            let connectionFraction = max(0.0, tailPosition - 0.35) / 0.15
            leftConnectionArcRadius *= connectionFraction
            
            if tailPosition < cutoff {
                let fraction = tailPosition / cutoff
                tailLeftHalfWidth *= fraction
                tailLeftArcStartAngle *= fraction
                tailLeftHalfRadius *= fraction
            }
        } else if tailPosition > 0.5 {
            let tailPosition = 1.0 - tailPosition
            let fraction = max(0.0, tailPosition - 0.15) / 0.35
            rightArcStartAngle *= fraction
            
            let connectionFraction = max(0.0, tailPosition - 0.35) / 0.15
            rightConnectionArcRadius *= connectionFraction
            
            if tailPosition < cutoff {
                let fraction = tailPosition / cutoff
                tailRightHalfWidth *= fraction
                tailRightArcStartAngle *= fraction
                tailRightHalfRadius *= fraction
            }
        }
    }
    
    path.addArc(
        center: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
        radius: cornerRadius,
        startAngle: .pi,
        endAngle: .pi + max(0.0001, leftArcEndAngle),
        clockwise: false
    )

    let leftArrowStart = max(rect.minX, rect.minX + rectSize.width * tailPosition - tailLeftHalfWidth - leftConnectionArcRadius)
    path.addArc(
        center: CGPoint(x: leftArrowStart, y: rect.minY - leftConnectionArcRadius),
        radius: leftConnectionArcRadius,
        startAngle: .pi / 2.0,
        endAngle: .pi / 4.0,
        clockwise: true
    )

    path.addLine(to: CGPoint(x: max(rect.minX, rect.minX + rectSize.width * tailPosition - tailLeftHalfRadius), y: rect.minY - tailHeight))

    path.addArc(
        center: CGPoint(x: rect.minX + rectSize.width * tailPosition, y: rect.minY - tailHeight + tailRadius / 2.0),
        radius: tailRadius,
        startAngle: -.pi / 2.0 + tailLeftArcStartAngle,
        endAngle: -.pi / 2.0 + tailRightArcStartAngle,
        clockwise: false
    )
    
    path.addLine(to: CGPoint(x: min(rect.maxX, rect.minX + rectSize.width * tailPosition + tailRightHalfRadius), y: rect.minY - tailHeight))

    let rightArrowStart = min(rect.maxX, rect.minX + rectSize.width * tailPosition + tailRightHalfWidth + rightConnectionArcRadius)
    path.addArc(
        center: CGPoint(x: rightArrowStart, y: rect.minY - rightConnectionArcRadius),
        radius: rightConnectionArcRadius,
        startAngle: .pi - .pi / 4.0,
        endAngle: .pi / 2.0,
        clockwise: true
    )

    path.addArc(
        center: CGPoint(x: rect.minX + rectSize.width - cornerRadius, y: rect.minY + cornerRadius),
        radius: cornerRadius,
        startAngle: min(-0.0001, rightArcStartAngle),
        endAngle: 0.0,
        clockwise: false
    )

    path.addLine(to: CGPoint(x: rect.minX + rectSize.width, y: rect.minY + rectSize.height - cornerRadius))

    path.addArc(
        center: CGPoint(x: rect.minX + rectSize.width - cornerRadius, y: rect.minY + rectSize.height - cornerRadius),
        radius: cornerRadius,
        startAngle: 0.0,
        endAngle: .pi / 2.0,
        clockwise: false
    )

    path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + rectSize.height))

    path.addArc(
        center: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + rectSize.height - cornerRadius),
        radius: cornerRadius,
        startAngle: .pi / 2.0,
        endAngle: .pi,
        clockwise: false
    )
    
    return path
}


public extension FileManager {
    
    func modificationDateForFileAtPath(path:String) -> NSDate? {
        guard let attributes = try? self.attributesOfItem(atPath: path) else { return nil }
        return attributes[.modificationDate] as? NSDate
    }
    
    func creationDateForFileAtPath(path:String) -> NSDate? {
        guard let attributes = try? self.attributesOfItem(atPath: path) else { return nil }
        return attributes[.creationDate] as? NSDate
    }
    
    
}




public extension NSCursor  {
    static var set_windowResizeNorthWestSouthEastCursor: NSCursor? {
        return ObjcUtils.windowResizeNorthWestSouthEastCursor()
    }
    static var set_windowResizeNorthEastSouthWestCursor: NSCursor? {
        return ObjcUtils.windowResizeNorthEastSouthWestCursor()
    }
}

public extension NSImage {
    var _cgImage: CGImage? {
        return self.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
    
    var jpegCGImage: CGImage? {
        guard let tiffData = self.tiffRepresentation,
              let bitmapImageRep = NSBitmapImageRep(data: tiffData) else {
            return nil
        }

        let compressionFactor: CGFloat = 1.0
        
        guard let jpegData = bitmapImageRep.representation(using: .jpeg, properties: [.compressionFactor: compressionFactor]),
              let dataProvider = CGDataProvider(data: jpegData as CFData),
              let cgImage = CGImage(jpegDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else {
            return nil
        }
        
        return cgImage
    }
}


public func truncate(double: Double, places : Int)-> Double
{
    return Double(floor(pow(10.0, Double(places)) * double)/pow(10.0, Double(places)))
}


public extension NSImage {
    
    enum Orientation {
        case up
        case down
    }
    
    convenience init(cgImage: CGImage, scale: CGFloat, orientation: UIImage.Orientation) {
        self.init(cgImage: cgImage, size: cgImage.systemSize)
    }
}



public extension CGImage {
    var cvPixelBuffer: CVPixelBuffer? {
        let cgImage = self

        var maybePixelBuffer: CVPixelBuffer? = nil
        let ioSurfaceProperties = NSMutableDictionary()
        let options = NSMutableDictionary()
        options.setObject(ioSurfaceProperties, forKey: kCVPixelBufferIOSurfacePropertiesKey as NSString)

        let _ = CVPixelBufferCreate(kCFAllocatorDefault, cgImage.width, cgImage.height, kCVPixelFormatType_32ARGB, options as CFDictionary, &maybePixelBuffer)
        guard let pixelBuffer = maybePixelBuffer else {
            return nil
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        defer {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        }

        let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer)

        let context = CGContext(
            data: baseAddress,
            width: cgImage.width,
            height: cgImage.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue,
            releaseCallback: nil,
            releaseInfo: nil
        )!
        let bounds = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        context.clear(bounds)
        context.draw(cgImage, in: bounds)

        return pixelBuffer
    }

    
    var cmSampleBuffer: CMSampleBuffer? {
           guard let pixelBuffer = self.cvPixelBuffer else {
               return nil
           }
           var newSampleBuffer: CMSampleBuffer? = nil

           var timingInfo = CMSampleTimingInfo(
               duration: CMTimeMake(value: 1, timescale: 30),
               presentationTimeStamp: CMTimeMake(value: 0, timescale: 30),
               decodeTimeStamp: CMTimeMake(value: 0, timescale: 30)
           )

           var videoInfo: CMVideoFormatDescription? = nil
           CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &videoInfo)
           guard let videoInfo = videoInfo else {
               return nil
           }
           CMSampleBufferCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: videoInfo, sampleTiming: &timingInfo, sampleBufferOut: &newSampleBuffer)

           if let newSampleBuffer = newSampleBuffer {
               let attachments = CMSampleBufferGetSampleAttachmentsArray(newSampleBuffer, createIfNecessary: true)! as NSArray
               let dict = attachments[0] as! NSMutableDictionary

               dict.setValue(kCFBooleanTrue as AnyObject, forKey: kCMSampleAttachmentKey_DisplayImmediately as NSString as String)
           }

           return newSampleBuffer
       }

}


public func mapRange(_ x: Double, inMin: Double, inMax: Double, outMin: Double, outMax: Double) -> Double {
    let slope = (outMax - outMin) / (inMax - inMin)
    return outMin + slope * (x - inMin)
}



public final class TransformImageResult {
    public let image: CGImage?
    public let highQuality: Bool
    public let sampleBuffer: CMSampleBuffer?
    public init(_ image: CGImage?, _ highQuality: Bool, _ sampleBuffer: CMSampleBuffer? = nil) {
        self.image = image
        self.sampleBuffer = sampleBuffer
        self.highQuality = highQuality
    }
    deinit {
        
    }
}

public func deg2rad(_ number: Float) -> Float {
    return number * .pi / 180
}

public func rad2deg(_ number: Float) -> Float {
    return number * 180.0 / .pi
}


public extension NSAttributedString {
    var smallDecemial: NSAttributedString {
        let range = self.string.nsstring.range(of: ".")
        if range.location != NSNotFound {
            let attr = self.mutableCopy() as! NSMutableAttributedString
            
            let font = attr.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
            if let font = font, let updated = NSFont(name: font.fontName, size: font.pointSize / 1.5) {
                attr.addAttribute(.font, value: updated, range: NSMakeRange(range.location, attr.range.length - range.lowerBound))
            }
            return attr

        } else {
            return self
        }
    }
}


public extension CGPath {
    
    static func rounded(frame: NSRect, cornerRadius: CGFloat, rectCorner: NSRectCorner) -> CGPath {
        
        let path = CGMutablePath()
        
        let minx:CGFloat = frame.minX, midx = frame.maxX/2.0, maxx = frame.maxX
        let miny:CGFloat = frame.maxY, midy = frame.maxY/2.0, maxy: CGFloat = 0
        
        path.move(to: NSMakePoint(minx, midy))
        
        var topLeftRadius: CGFloat = 0
        var bottomLeftRadius: CGFloat = 0
        var topRightRadius: CGFloat = 0
        var bottomRightRadius: CGFloat = 0
        
        
        if rectCorner.contains(.topLeft) {
            topLeftRadius = cornerRadius
        }
        if rectCorner.contains(.topRight) {
            topRightRadius = cornerRadius
        }
        if rectCorner.contains(.bottomLeft) {
            bottomLeftRadius = cornerRadius
        }
        if rectCorner.contains(.bottomRight) {
            bottomRightRadius = cornerRadius
        }
        
        
        path.addArc(tangent1End: NSMakePoint(minx, miny), tangent2End: NSMakePoint(midx, miny), radius: bottomLeftRadius)
        path.addArc(tangent1End: NSMakePoint(maxx, miny), tangent2End: NSMakePoint(maxx, midy), radius: bottomRightRadius)
        path.addArc(tangent1End: NSMakePoint(maxx, maxy), tangent2End: NSMakePoint(midx, maxy), radius: topRightRadius)
        path.addArc(tangent1End: NSMakePoint(minx, maxy), tangent2End: NSMakePoint(minx, midy), radius: topLeftRadius)
        
        if rectCorner.contains(.topLeft) {
             path.move(to: NSMakePoint(minx, cornerRadius))
        } else {
             path.move(to: NSMakePoint(minx, maxy))
        }
       
        path.addLine(to: NSMakePoint(minx, midy))
        
        return path
    }
    
}


public func fontSizeThatFits(text: String, in rect: CGRect, initialFont: NSFont, minFontSize: CGFloat = 5.0) -> NSFont {
    var fontSize = initialFont.pointSize
    var currentFont = initialFont

    // Create an attributed string to measure
    let attributedText = NSMutableAttributedString(string: text, attributes: [.font: currentFont])

    // Measure the text size with the current font
    var textSize = attributedText.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: rect.height), options: .usesLineFragmentOrigin, context: nil)

    // Reduce the font size until it fits within the rect's width or reaches the minimum size
    while textSize.width > rect.width && fontSize > minFontSize {
        fontSize -= 1
        currentFont = NSFont(name: initialFont.fontName, size: fontSize) ?? initialFont
        attributedText.addAttribute(.font, value: currentFont, range: NSRange(location: 0, length: attributedText.length))
        textSize = attributedText.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: rect.height), options: .usesLineFragmentOrigin, context: nil)
    }

    return currentFont
}


public func extractHashtagAndUsername(from query: String) -> (hashtag: String, username: String)? {
    // Regular expression to match hashtag followed by username
    let pattern = "^([#$])([a-zA-Z0-9_]+)@([a-zA-Z0-9_]+)$"
       
       // Create regular expression object
       guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
       
       // Search for matches
       let matches = regex.matches(in: query, range: NSRange(query.startIndex..., in: query))
       
       // Ensure we have a match
       guard let match = matches.first, match.numberOfRanges == 4 else { return nil }
       
       // Extract symbol (# or $), tag, and username from the match
       if let symbolRange = Range(match.range(at: 1), in: query),
          let tagRange = Range(match.range(at: 2), in: query),
          let usernameRange = Range(match.range(at: 3), in: query) {
           
           let symbol = String(query[symbolRange])
           let tag = String(query[tagRange])
           let fullTag = symbol + tag
           let username = String(query[usernameRange])
           
           return (fullTag, username)
       }
       
       return nil
}
public func extractAnchor(from text: String, matching url: String) -> String? {
    // Escape the URL to safely use it in a regex
    let escapedURL = NSRegularExpression.escapedPattern(for: url)
    
    // Regular expression pattern to match the given URL with optional anchor (#)
    let pattern = "\(escapedURL)(#[a-zA-Z0-9_-]+)?"
    
    // Create regular expression object
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    
    // Search for matches in the text
    let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    
    // Ensure there is at least one match
    guard let match = matches.first else { return nil }
    
    // Extract the anchor if it exists (the part after #)
    if match.numberOfRanges > 1, let anchorRange = Range(match.range(at: 1), in: text) {
        return String(text[anchorRange].dropFirst()) // Drop the # symbol
    }
    
    // If no anchor is found, return nil
    return nil
}


public func formatMonthYear(_ dateString: String, locale: Locale = .current) -> String? {
    // Create date formatter for parsing input
    let inputFormatter = DateFormatter()
    inputFormatter.dateFormat = "MM.yyyy"
    
    // Try to parse the input string to date
    guard let date = inputFormatter.date(from: dateString) else {
        return nil
    }
    
    // Create formatter for output
    let outputFormatter = DateFormatter()
    outputFormatter.locale = locale
    outputFormatter.setLocalizedDateFormatFromTemplate("MMM yyyy")
    
    return outputFormatter.string(from: date)
}


public func escapeMarkdownSpecialCharacters(in text: String) -> String {
    return text
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "[", with: "\\[")
        .replacingOccurrences(of: "]", with: "\\]")
        .replacingOccurrences(of: "(", with: "\\(")
        .replacingOccurrences(of: ")", with: "\\)")
}


public extension CGMutablePath {
    func addRoundedRect(in rect: CGRect, topLeft: Bool, topRight: Bool, bottomLeft: Bool, bottomRight: Bool, radius: CGFloat) {
        let maxRadius = min(radius, min(rect.width, rect.height) / 2)

        let tl = topLeft ? maxRadius : 0
        let tr = topRight ? maxRadius : 0
        let bl = bottomLeft ? maxRadius : 0
        _ = bottomRight ? maxRadius : 0

        self.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))

        // Bottom line
        self.addLine(to: CGPoint(x: rect.maxX - bl, y: rect.minY))
        if bl > 0 {
            self.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + bl),
                              control: CGPoint(x: rect.maxX, y: rect.minY))
        }

        // Right line
        self.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - tr))
        if tr > 0 {
            self.addQuadCurve(to: CGPoint(x: rect.maxX - tr, y: rect.maxY),
                              control: CGPoint(x: rect.maxX, y: rect.maxY))
        }

        // Top line
        self.addLine(to: CGPoint(x: rect.minX + tl, y: rect.maxY))
        if tl > 0 {
            self.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - tl),
                              control: CGPoint(x: rect.minX, y: rect.maxY))
        }

        // Left line
        self.addLine(to: CGPoint(x: rect.minX, y: rect.minY + bl))
        if bl > 0 {
            self.addQuadCurve(to: CGPoint(x: rect.minX + bl, y: rect.minY),
                              control: CGPoint(x: rect.minX, y: rect.minY))
        }

        self.closeSubpath()
    }
}



public func + <K,V>(left: Dictionary<K,V>, right: Dictionary<K,V>)
    -> Dictionary<K,V>
{
    var map = Dictionary<K,V>()
    for (k, v) in left {
        map[k] = v
    }
    for (k, v) in right {
        map[k] = v
    }
    return map
}

public extension Array {
    func subarray(with range: NSRange) -> Array {
        return Array(self[range.min ..< range.max])
    }
    mutating func move(at oldIndex: Int, to newIndex: Int) {
        self.insert(self.remove(at: oldIndex), at: newIndex)
    }
}
public extension Array {
    func chunks(_ chunkSize: Int) -> [[Element]] {
        if self.count == 0 || chunkSize == 0 {
            return []
        }
        if chunkSize >= self.count {
            return [self]
        }
        return stride(from: 0, to: self.count, by: chunkSize).map {
            Array(self[$0..<Swift.min($0 + chunkSize, self.count)])
        }
    }
    func toDictionary<Key: Hashable>(with selectKey: (Element) -> Key) -> [Key:Element] {
        var dict = [Key:Element]()
        for element in self {
            dict[selectKey(element)] = element
        }
        return dict
    }
}


public func mapInt64ToInt32(_ value: Int64) -> Int32 {
    let mixed = value ^ (value >> 32)
    return Int32(truncatingIfNeeded: mixed)
}


public struct SVG_SlotsMetadata: Codable, Equatable {
    
    public struct SizeWH: Codable, Equatable {
        public let w: Double
        public let h: Double

        public var cgSize: CGSize { CGSize(width: w, height: h) }
    }

    public struct PointXY: Codable, Equatable {
        public let x: Double
        public let y: Double

        public var cgPoint: CGPoint { CGPoint(x: x, y: y) }
    }

    public struct RectRR: Codable, Equatable {
        public let x: Double
        public let y: Double
        public let w: Double
        public let h: Double

        public var cgRect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    }

    public struct Slot: Codable, Equatable {
        public let i: Int
        public let pixel: RectRR
    }
    
    public let version: Int
    public let imageSize: SizeWH
    public let scale: Double
    public let offset: PointXY
    public let slots: [Slot]
    public let neatSpot: Int

}

public func loadSlotsMetadata(from url: URL) throws -> SVG_SlotsMetadata {
    let data = try Data(contentsOf: url)
    return try parseSlotsMetadata(from: data)
}

private func parseSlotsMetadata(from jsonData: Data) throws -> SVG_SlotsMetadata {
    let dec = JSONDecoder()
    return try dec.decode(SVG_SlotsMetadata.self, from: jsonData)
}

private func parseSlotsMetadata(from dict: [String: Any]) throws -> SVG_SlotsMetadata {
    let data = try JSONSerialization.data(withJSONObject: dict, options: [])
    return try parseSlotsMetadata(from: data)
}


public struct ExtractedDate {
    public enum Format {
        case relative
        case full(hasTime: Bool, hasDate: Bool)
    }

    public let range: Range<Int>   // UTF-16 offsets
    public let date: Date
    public let text: String
    public let format: Format
}

public func extractDates(from text: String, referenceDate: Date = Date()) -> [ExtractedDate] {
    var results: [ExtractedDate] = []

    // 1) Relative durations ("in 20 minutes", "через 2 часа", "dans 10 min", "en 3 días", "za 5 хвилин", "20m")
    results.append(contentsOf: extractRelativeDates(from: text, referenceDate: referenceDate))
    // 2) Absolute dates (tomorrow at 15:00, Feb 25 12:00, etc.) via NSDataDetector
    // Only include if the matched text contains a time component
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) {
        let nsRange = NSRange(location: 0, length: text.utf16.count)
        for match in detector.matches(in: text, options: [], range: nsRange) {
            guard let date = match.date,
                  let swiftRange = Range(match.range, in: text) else { continue }

            let matchedText = String(text[swiftRange])

            // Skip dates without time component (e.g., just "завтра" or "tomorrow")
            if !textContainsTime(matchedText) {
                continue
            }

            let start = text.utf16.distance(from: text.startIndex, to: swiftRange.lowerBound)
            let end   = text.utf16.distance(from: text.startIndex, to: swiftRange.upperBound)
            let r = start..<end

            // avoid overlaps with relative matches
            if !results.contains(where: { $0.range.overlaps(r) }) {
                let format = detectDateFormat(from: matchedText)
                results.append(ExtractedDate(range: r, date: date, text: matchedText, format: format))
            }
        }
    }

    return results.sorted { $0.range.lowerBound < $1.range.lowerBound }
}

private func extractRelativeDates(from text: String, referenceDate: Date) -> [ExtractedDate] {
    var out: [ExtractedDate] = []
    let nsRange = NSRange(location: 0, length: text.utf16.count)

    // --- 1) Build token tables (units + “prefix words”) ---
    // Units are intentionally broad (cover plural/cases/accents/abbrev).
    // We match by "starts-with" or exact where appropriate.
    let unitMatchers: [(String) -> RelativeUnit?] = [
        // seconds
        { s in
            let u = s
            if u.hasPrefix("sec") || u == "s" || u == "сек" || u.hasPrefix("секунд")
                || u.hasPrefix("son") || u.hasPrefix("sek") || u.hasPrefix("sekund")
                || u.hasPrefix("сек") || u.hasPrefix("сэ") { // tolerate typos
                return .seconds
            }
            return nil
        },
        // minutes
        { s in
            let u = s
            if u.hasPrefix("min") || u == "m" || u == "мин" || u.hasPrefix("минут")
                || u.hasPrefix("хв") || u.hasPrefix("хвил") // uk
                || u.hasPrefix("хв") || u.hasPrefix("хвіл") // uk variants
                || u.hasPrefix("daq") || u.hasPrefix("daqi") || u.hasPrefix("daqiqa") // uz (daqiqа)
                || u.hasPrefix("daq") // uz shorthand
                || u.hasPrefix("minute") || u.hasPrefix("minutes") // fr/en
                || u.hasPrefix("minut") // de/plural-ish
                || u.hasPrefix("minuto") || u.hasPrefix("minutos") // es
                || u.hasPrefix("мiн") || u.hasPrefix("мін") { // be/uk “мін”
                return .minutes
            }
            return nil
        },
        // hours
        { s in
            let u = s
            if u.hasPrefix("hour") || u == "h" || u.hasPrefix("hr")
                || u.hasPrefix("час") || u.hasPrefix("годин") || u.hasPrefix("гадз") // ru/uk/be
                || u.hasPrefix("st") || u.hasPrefix("std") // de Stunde
                || u.hasPrefix("heure") || u.hasPrefix("heures") // fr
                || u.hasPrefix("hora") || u.hasPrefix("horas") // es
                || u.hasPrefix("soat") // uz
            {
                return .hours
            }
            return nil
        },
        // days
        { s in
            let u = s
            if u.hasPrefix("day") || u == "d"
                || u == "день" || u.hasPrefix("дн") || u.hasPrefix("дня") || u.hasPrefix("дней")
                || u.hasPrefix("днi") || u.hasPrefix("дні") || u.hasPrefix("днів") // uk
                || u.hasPrefix("дз") || u.hasPrefix("дзён") || u.hasPrefix("дзень") // be
                || u.hasPrefix("tag") || u.hasPrefix("tage") // de
                || u.hasPrefix("jour") || u.hasPrefix("jours") // fr
                || u.hasPrefix("día") || u.hasPrefix("dias") || u.hasPrefix("días") // es
                || u.hasPrefix("kun") // uz
            {
                return .days
            }
            return nil
        },
        // weeks
        { s in
            let u = s
            if u.hasPrefix("week") || u == "w"
                || u.hasPrefix("нед") || u.hasPrefix("тиж") // ru/uk
                || u.hasPrefix("тыд") // be
                || u.hasPrefix("woche") || u.hasPrefix("wochen") // de
                || u.hasPrefix("semaine") || u.hasPrefix("semaines") // fr
                || u.hasPrefix("semana") || u.hasPrefix("semanas") // es
                || u.hasPrefix("hafta") // uz
            {
                return .weeks
            }
            return nil
        },
        // months (optional but often useful)
        { s in
            let u = s
            if u.hasPrefix("month") || u.hasPrefix("mon") // en
                || u.hasPrefix("мес") // ru
                || u.hasPrefix("міс") || u.hasPrefix("місяц") // uk
                || u.hasPrefix("мес") || u.hasPrefix("месяц") // ru variants
                || u.hasPrefix("monat") || u.hasPrefix("monate") // de
                || u.hasPrefix("mois") // fr
                || u.hasPrefix("mes") // es
                || u.hasPrefix("oy") // uz
            {
                return .months
            }
            return nil
        }
    ]

    // Prefix words for "in/after/через/..." (multi-language)
    // We keep them short; you can expand anytime.
    let prefixWords = [
        // en
        "in", "after", "within",
        // ru/be/uk
        "через", "спустя", "через", "праз", "празь", "за", "через",
        // uk
        "за", "через",
        // fr
        "dans", "d'ici", "après",
        // es
        "en", "dentro de", "después de",
        // de
        "in", "nach",
        // uz (latin + cyrillic)
        "ichida", "keyin", "so‘ng", "song", "орқали", "кейин"
    ]

    // --- 2) Two patterns: (A) prefix + number + unit, (B) compact number+unit ---
    // Pattern A examples:
    // "in 20 minutes", "after 2 hrs", "через 10 минут", "dans 5 min", "en 3 días", "nach 2 Stunden", "za 5 хвилин"
    let escapedPrefixes = prefixWords
        .sorted { $0.count > $1.count } // longer first ("dentro de")
        .map { NSRegularExpression.escapedPattern(for: $0) }
        .joined(separator: "|")

    // Unit token: letters + dots (min., etc.) + Cyrillic + accents
    // We capture unit as group 2
    let patternA = #"(?:\b(?:\#(escapedPrefixes))\b)\s+(\d+(?:[.,]\d+)?)\s*([[:alpha:]\p{M}\.]+)"#

    // Pattern B examples:
    // "20m", "2h", "3d", "1w", "20 min", "10мин", "5хв", "2soat"
    let patternB = #"(?<!\S)(\d+(?:[.,]\d+)?)\s*([[:alpha:]\p{M}]{1,12}\.?)\b"#

    // Pattern C examples (implied "1"):
    // "через минуту", "через час", "in a minute", "in an hour", "nach einer Stunde"
    // Matches: prefix + optional article + unit (no number)
    let articles = ["a", "an", "one", "einer", "eine", "einem", "un", "une", "una", "uno"]
    let escapedArticles = articles.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
    let patternC = #"(?:\b(?:\#(escapedPrefixes))\b)\s+(?:(?:\#(escapedArticles))\s+)?([[:alpha:]\p{M}]{2,15})\b"#

    // Written numbers mapping
    let writtenNumbers: [String: Double] = [
        // English
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "fifteen": 15, "twenty": 20, "thirty": 30,
        "half": 0.5,
        // Russian
        "один": 1, "одну": 1, "одного": 1, "одной": 1,
        "два": 2, "две": 2, "двух": 2,
        "три": 3, "трёх": 3, "трех": 3,
        "четыре": 4, "четырёх": 4, "четырех": 4,
        "пять": 5, "пяти": 5,
        "шесть": 6, "шести": 6,
        "семь": 7, "семи": 7,
        "восемь": 8, "восьми": 8,
        "девять": 9, "девяти": 9,
        "десять": 10, "десяти": 10,
        "пол": 0.5, "полчаса": 0.5,
        // German
        "eins": 1, "zwei": 2, "drei": 3, "vier": 4, "fünf": 5,
        "sechs": 6, "sieben": 7, "acht": 8, "neun": 9, "zehn": 10,
        // French
        "un": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5,
        "sept": 7, "huit": 8, "neuf": 9, "dix": 10,
    ]
    let writtenNumberWords = writtenNumbers.keys.sorted { $0.count > $1.count }
    let escapedWrittenNumbers = writtenNumberWords.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")

    // Pattern E: prefix + written number + unit
    // "in two hours", "через два часа", "dans trois heures"
    let patternE = #"(?:\b(?:\#(escapedPrefixes))\b)\s+(\#(escapedWrittenNumbers))\s+([[:alpha:]\p{M}]{2,15})\b"#

    // Compile once
    let regexA = try? NSRegularExpression(pattern: patternA, options: [.caseInsensitive])
    let regexB = try? NSRegularExpression(pattern: patternB, options: [.caseInsensitive])
    let regexC = try? NSRegularExpression(pattern: patternC, options: [.caseInsensitive])
    let regexE = try? NSRegularExpression(pattern: patternE, options: [.caseInsensitive])

    // Helper: parse number
    func parseNumber(_ s: Substring) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "."))
    }

    func unitFromToken(_ token: String) -> RelativeUnit? {
        let t = token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()

        for matcher in unitMatchers {
            if let u = matcher(t) { return u }
        }
        return nil
    }

    // Convert units
    func add(_ value: Double, unit: RelativeUnit, to date: Date) -> Date {
        switch unit {
        case .seconds: return date.addingTimeInterval(value)
        case .minutes: return date.addingTimeInterval(value * 60)
        case .hours:   return date.addingTimeInterval(value * 3600)
        case .days:    return date.addingTimeInterval(value * 86400)
        case .weeks:   return date.addingTimeInterval(value * 604800)
        case .months:
            // Months are calendar-based; use Calendar
            let months = Int(value.rounded())
            return Calendar.current.date(byAdding: .month, value: months, to: date) ?? date
        }
    }

    // Collect matches from A (strong signal)
    if let regexA {
        for m in regexA.matches(in: text, options: [], range: nsRange) {
            guard m.numberOfRanges >= 4,
                  let fullRange = Range(m.range, in: text),
                  let numRange = Range(m.range(at: 2), in: text),
                  let unitRange = Range(m.range(at: 3), in: text),
                  let number = parseNumber(text[numRange]) else { continue }

            let unitToken = String(text[unitRange])
            guard let unit = unitFromToken(unitToken) else { continue }

            let date = add(number, unit: unit, to: referenceDate)

            let start = text.utf16.distance(from: text.startIndex, to: fullRange.lowerBound)
            let end   = text.utf16.distance(from: text.startIndex, to: fullRange.upperBound)

            out.append(ExtractedDate(range: start..<end, date: date, text: String(text[fullRange]), format: .relative))
        }
    }

    // Collect matches from B (compact), but avoid obvious false positives by:
    // - requiring the token to map to a known unit
    // - and not overlapping existing matches
    if let regexB {
        for m in regexB.matches(in: text, options: [], range: nsRange) {
            guard m.numberOfRanges >= 3,
                  let fullRange = Range(m.range, in: text),
                  let numRange = Range(m.range(at: 1), in: text),
                  let unitRange = Range(m.range(at: 2), in: text),
                  let number = parseNumber(text[numRange]) else { continue }

            let unitToken = String(text[unitRange])
            guard let unit = unitFromToken(unitToken) else { continue }

            let start = text.utf16.distance(from: text.startIndex, to: fullRange.lowerBound)
            let end   = text.utf16.distance(from: text.startIndex, to: fullRange.upperBound)
            let r = start..<end

            if out.contains(where: { $0.range.overlaps(r) }) { continue }

            // Heuristic: If it's just "in" (German/English), ignore (unitFromToken would be nil anyway)
            // Also ignore very large numbers for seconds/minutes if you want (optional).
            let date = add(number, unit: unit, to: referenceDate)
            out.append(ExtractedDate(range: r, date: date, text: String(text[fullRange]), format: .relative))
        }
    }

    // Collect matches from E (prefix + written number + unit)
    // Examples: "in two hours", "через два часа", "dans trois heures"
    if let regexE {
        for m in regexE.matches(in: text, options: [], range: nsRange) {
            guard m.numberOfRanges >= 3,
                  let fullRange = Range(m.range, in: text),
                  let numWordRange = Range(m.range(at: 1), in: text),
                  let unitRange = Range(m.range(at: 2), in: text) else { continue }

            let numWord = String(text[numWordRange]).lowercased()
            guard let number = writtenNumbers[numWord] else { continue }

            let unitToken = String(text[unitRange])
            guard let unit = unitFromToken(unitToken) else { continue }

            let start = text.utf16.distance(from: text.startIndex, to: fullRange.lowerBound)
            let end   = text.utf16.distance(from: text.startIndex, to: fullRange.upperBound)
            let r = start..<end

            if out.contains(where: { $0.range.overlaps(r) }) { continue }

            let date = add(number, unit: unit, to: referenceDate)
            out.append(ExtractedDate(range: r, date: date, text: String(text[fullRange]), format: .relative))
        }
    }

    // Collect matches from C (prefix + unit without number, implies 1)
    // Examples: "через минуту", "in a minute", "in an hour"
    if let regexC {
        for m in regexC.matches(in: text, options: [], range: nsRange) {
            guard m.numberOfRanges >= 2,
                  let fullRange = Range(m.range, in: text),
                  let unitRange = Range(m.range(at: 1), in: text) else { continue }

            let unitToken = String(text[unitRange])
            guard let unit = unitFromToken(unitToken) else { continue }

            let start = text.utf16.distance(from: text.startIndex, to: fullRange.lowerBound)
            let end   = text.utf16.distance(from: text.startIndex, to: fullRange.upperBound)
            let r = start..<end

            if out.contains(where: { $0.range.overlaps(r) }) { continue }

            let date = add(1, unit: unit, to: referenceDate)
            out.append(ExtractedDate(range: r, date: date, text: String(text[fullRange]), format: .relative))
        }
    }

    // Pattern D: "next month on the 30th", "в следующем месяце 30 числа"
    let nextMonthPatterns = [
        #"(в\s+)?следующ[а-я]*\s+месяц[а-я]*(\s+(\d{1,2})\s*(числа|го)?)?"#,  // в следующем месяце 30 числа
        #"next\s+month(\s+on\s+(the\s+)?(\d{1,2})(st|nd|rd|th)?)?"#,           // next month on the 30th
    ]

    for pattern in nextMonthPatterns {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
        for m in regex.matches(in: text, options: [], range: nsRange) {
            guard let fullRange = Range(m.range, in: text) else { continue }

            let start = text.utf16.distance(from: text.startIndex, to: fullRange.lowerBound)
            let end = text.utf16.distance(from: text.startIndex, to: fullRange.upperBound)
            let r = start..<end

            if out.contains(where: { $0.range.overlaps(r) }) { continue }

            // Extract day number if present (group 3 for Russian, group 3 for English)
            var dayOfMonth = 1
            if m.numberOfRanges >= 4, let dayRange = Range(m.range(at: 3), in: text) {
                if let day = Int(text[dayRange]) {
                    dayOfMonth = min(max(day, 1), 31)
                }
            }

            // Calculate next month date at noon
            var components = Calendar.current.dateComponents([.year, .month], from: referenceDate)
            components.month! += 1
            components.day = dayOfMonth
            components.hour = 12
            components.minute = 0

            if let date = Calendar.current.date(from: components) {
                out.append(ExtractedDate(range: r, date: date, text: String(text[fullRange]), format: .full(hasTime: true, hasDate: true)))
            }
        }
    }

    // Deduplicate overlaps (prefer longer spans)
    out.sort { $0.range.count > $1.range.count }
    var filtered: [ExtractedDate] = []
    for item in out {
        if !filtered.contains(where: { $0.range.overlaps(item.range) }) {
            filtered.append(item)
        }
    }
    filtered.sort { $0.range.lowerBound < $1.range.lowerBound }
    return filtered
}

private enum RelativeUnit {
    case seconds, minutes, hours, days, weeks, months
}

private func textContainsTime(_ text: String) -> Bool {
    let lowercased = text.lowercased()
    let timePatterns = [
        #"\d{1,2}:\d{2}"#,                    // 12:00, 3:30
        #"\d{1,2}\s*(am|pm)"#,                // 3pm, 11 am
        #"\d{1,2}\s*(ч|час)"#,                // 15 ч, 3 часа (Russian)
        #"\bв\s+\d{1,2}"#,                    // в 15, в 3 (Russian "at 15", "at 3")
        #"\bat\s+\d{1,2}"#,                   // at 15, at 3
    ]
    return timePatterns.contains { pattern in
        (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive))?.firstMatch(in: lowercased, range: NSRange(location: 0, length: lowercased.utf16.count)) != nil
    }
}

private func detectDateFormat(from text: String) -> ExtractedDate.Format {
    let lowercased = text.lowercased()

    // Check for time patterns (12:00, 3pm, 15:30, в 5 утра, etc.)
    let timePatterns = [
        #"\d{1,2}:\d{2}"#,                    // 12:00, 3:30
        #"\d{1,2}\s*(am|pm)"#,                // 3pm, 11 am
        #"\d{1,2}\s*(ч|час)"#,                // 15 ч, 3 часа (Russian)
        #"\bв\s+\d{1,2}\b"#,                  // в 5, в 15 (Russian "at 5")
        #"\bat\s+\d{1,2}\b"#,                 // at 5, at 15
        #"\d{1,2}\s*(утра|вечера|ночи|дня)"#, // 5 утра, 8 вечера (Russian time of day)
        #"\d{1,2}\s*(morning|evening|night)"#, // 5 morning (English time of day)
    ]
    let hasTime = timePatterns.contains { pattern in
        (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive))?.firstMatch(in: lowercased, range: NSRange(location: 0, length: lowercased.utf16.count)) != nil
    }

    let datePatterns = [
        #"\d{1,2}[./]\d{1,2}[./]\d{2,4}"#,
        #"\d{1,2}[./]\d{1,2}"#,                // 19.02, 02/25
        #"(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\s+\d{1,2}"#,  // February 25
        #"\d{1,2}\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)"#,         // 25 February
        #"(янв|фев|мар|апр|ма[йя]|июн|июл|авг|сен|окт|ноя|дек)[а-я]*\s+\d{1,2}"#, // февраля 25
        #"\d{1,2}\s+(янв|фев|мар|апр|ма[йя]|июн|июл|авг|сен|окт|ноя|дек)"#,       // 25 февраля
    ]
    let hasExplicitDate = datePatterns.contains { pattern in
        (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive))?.firstMatch(in: lowercased, range: NSRange(location: 0, length: lowercased.utf16.count)) != nil
    }

    // Check for relative day words (tomorrow, today, etc.) - these should use relative format
    let relativeDayPatterns = [
        #"\btoday\b|\btonight\b|\btomorrow\b|\byesterday\b"#,
        #"\bсегодня\b|\bзавтра\b|\bвчера\b"#,
        #"\bnext\s+(monday|tuesday|wednesday|thursday|friday|saturday|sunday|week|month)\b"#,
        #"\bследующ[а-я]+\s+(понедельник|вторник|сред|четверг|пятниц|суббот|воскресень|недел|месяц)"#,
    ]
    let isRelativeDay = relativeDayPatterns.contains { pattern in
        (try? NSRegularExpression(pattern: pattern, options: .caseInsensitive))?.firstMatch(in: lowercased, range: NSRange(location: 0, length: lowercased.utf16.count)) != nil
    }

    // If it's a relative day word without explicit date format, use relative
    if isRelativeDay && !hasExplicitDate && !hasTime {
        return .relative
    }

    // If we have explicit time or date patterns, use full format
    if hasTime || hasExplicitDate {
        return .full(hasTime: hasTime, hasDate: hasExplicitDate)
    }

    // Default to relative for NSDataDetector matches that don't have clear patterns
    return .relative
}

private extension Range where Bound == Int {
    var count: Int { upperBound - lowerBound }
}
