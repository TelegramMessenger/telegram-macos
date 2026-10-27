import Cocoa
import TGUIKit

public struct EditImageCanvasColor: Hashable {
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1.0) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public init(rgb: UInt32, alpha: CGFloat = 1.0) {
        self.init(red: CGFloat((rgb >> 16) & 0xff) / 255.0, green: CGFloat((rgb >> 8) & 0xff) / 255.0, blue: CGFloat(rgb & 0xff) / 255.0, alpha: alpha)
    }

    public init(_ color: NSColor) {
        let converted = color.usingColorSpace(.sRGB) ?? color.usingColorSpace(.deviceRGB) ?? NSColor.white
        self.init(red: converted.redComponent, green: converted.greenComponent, blue: converted.blueComponent, alpha: converted.alphaComponent)
    }

    public var nsColor: NSColor {
        return NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public var cgColor: CGColor {
        return nsColor.cgColor
    }

    public var lightness: CGFloat {
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    public var rgb: UInt32 {
        let r = UInt32(max(0, min(255, (red * 255.0).rounded())))
        let g = UInt32(max(0, min(255, (green * 255.0).rounded())))
        let b = UInt32(max(0, min(255, (blue * 255.0).rounded())))
        return (r << 16) | (g << 8) | b
    }

    public var hexString: String {
        return String(format: "%06X", rgb)
    }

    public func withAlpha(_ alpha: CGFloat) -> EditImageCanvasColor {
        return EditImageCanvasColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    public func mixed(with other: EditImageCanvasColor, fraction: CGFloat) -> EditImageCanvasColor {
        let f = max(0, min(1, fraction))
        return EditImageCanvasColor(red: red + (other.red - red) * f, green: green + (other.green - green) * f, blue: blue + (other.blue - blue) * f, alpha: alpha + (other.alpha - alpha) * f)
    }

    public func multipliedBrightness(_ factor: CGFloat) -> EditImageCanvasColor {
        var hue: CGFloat = 0
        var saturation: CGFloat = 0
        var brightness: CGFloat = 0
        var a: CGFloat = 0
        nsColor.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &a)
        return EditImageCanvasColor(NSColor(hue: hue, saturation: saturation, brightness: max(0, min(1, brightness * factor)), alpha: alpha))
    }

    public func isSameRGB(_ other: EditImageCanvasColor) -> Bool {
        return rgb == other.rgb
    }

    public static let white = EditImageCanvasColor(rgb: 0xffffff)
    public static let black = EditImageCanvasColor(rgb: 0x000000)
}

public enum EditImageCanvasTool: Int, CaseIterable {
    case pen
    case arrow
    case marker
    case neon
    case blur
    case eraser

    var action: EditImageDrawTouch.Action {
        switch self {
        case .pen:
            return .draw
        case .arrow:
            return .drawArrow
        case .marker:
            return .marker
        case .neon:
            return .neon
        case .blur:
            return .blur
        case .eraser:
            return .clear
        }
    }

    var hasColor: Bool {
        switch self {
        case .blur, .eraser:
            return false
        default:
            return true
        }
    }

    var filterDistance: CGFloat {
        switch self {
        case .marker, .neon:
            return 3.0
        default:
            return 2.0
        }
    }
}

struct EditImageCanvasToolState: Equatable {
    var color: EditImageCanvasColor
    var size: CGFloat
}

enum EditImageCanvasToolSettings {
    private static let toolsKey = "editImageCanvasTools"
    private static let selectedKey = "editImageCanvasSelectedTool"

    private static let presetValues: [UInt32] = [0xFF453A, 0xFF8A00, 0xFFD60A, 0x34C759, 0x63E6E2, 0x0A84FF, 0xBF5AF2, 0xFFFFFF]

    static let presets: [EditImageCanvasColor] = presetValues.map {
        EditImageCanvasColor(rgb: $0)
    }

    static func defaults() -> [EditImageCanvasTool: EditImageCanvasToolState] {
        return [
            .pen: EditImageCanvasToolState(color: EditImageCanvasColor(rgb: 0xFF453A), size: 0.23),
            .arrow: EditImageCanvasToolState(color: EditImageCanvasColor(rgb: 0xFF8A00), size: 0.23),
            .marker: EditImageCanvasToolState(color: EditImageCanvasColor(rgb: 0xFFD60A), size: 0.75),
            .neon: EditImageCanvasToolState(color: EditImageCanvasColor(rgb: 0x34C759), size: 0.4),
            .blur: EditImageCanvasToolState(color: .white, size: 0.5),
            .eraser: EditImageCanvasToolState(color: .white, size: 0.5)
        ]
    }

    static func load() -> (tools: [EditImageCanvasTool: EditImageCanvasToolState], selected: EditImageCanvasTool) {
        var result = defaults()
        if let stored = UserDefaults.standard.dictionary(forKey: toolsKey) {
            for tool in EditImageCanvasTool.allCases {
                if let values = stored["\(tool.rawValue)"] as? [Double], values.count == 5 {
                    let color = EditImageCanvasColor(red: CGFloat(values[0]), green: CGFloat(values[1]), blue: CGFloat(values[2]), alpha: CGFloat(values[3]))
                    result[tool] = EditImageCanvasToolState(color: color, size: max(0, min(1, CGFloat(values[4]))))
                }
            }
        }
        let selected = EditImageCanvasTool(rawValue: UserDefaults.standard.integer(forKey: selectedKey)) ?? .pen
        return (result, selected)
    }

    static func save(_ tools: [EditImageCanvasTool: EditImageCanvasToolState], selected: EditImageCanvasTool) {
        var stored: [String: [Double]] = [:]
        for (tool, state) in tools {
            stored["\(tool.rawValue)"] = [Double(state.color.red), Double(state.color.green), Double(state.color.blue), Double(state.color.alpha), Double(state.size)]
        }
        UserDefaults.standard.set(stored, forKey: toolsKey)
        UserDefaults.standard.set(selected.rawValue, forKey: selectedKey)
    }
}

enum EditImageCanvasMetrics {
    static func strokeWidth(tool: EditImageCanvasTool, size: CGFloat, canvasSize: CGSize) -> CGFloat {
        let longSide = max(canvasSize.width, canvasSize.height)
        switch tool {
        case .marker:
            let minWidth = max(10.0, longSide * 0.01)
            let maxWidth = max(20.0, longSide * 0.09)
            return minWidth + (maxWidth - minWidth) * size
        default:
            let minWidth = max(1.0, longSide * 0.002)
            let maxWidth = max(10.0, longSide * 0.07)
            return minWidth + (maxWidth - minWidth) * size
        }
    }

    static func entityLineWidth(_ value: CGFloat, referenceSize: CGSize) -> CGFloat {
        let longSide = max(referenceSize.width, referenceSize.height)
        let minWidth = max(10.0, longSide * 0.01)
        let maxWidth = max(10.0, longSide * 0.05)
        return minWidth + (maxWidth - minWidth) * value
    }

    static func shapeMaxLineWidth(referenceSize: CGSize) -> CGFloat {
        return max(10.0, max(referenceSize.width, referenceSize.height) * 0.05)
    }

    static func fontSize(_ value: CGFloat, referenceSize: CGSize) -> CGFloat {
        let longSide = max(referenceSize.width, referenceSize.height)
        let minSize = max(10.0, longSide * 0.025)
        let maxSize = max(10.0, longSide * 0.25)
        return minSize + (maxSize - minSize) * value
    }

    static func unit(_ referenceSize: CGSize) -> CGFloat {
        return max(referenceSize.width, referenceSize.height) / 1920.0
    }
}

public struct EditImageCanvasEntity: Equatable {
    public enum TextStyle: Int, CaseIterable {
        case regular
        case filled
        case semi

        var next: TextStyle {
            switch self {
            case .regular:
                return .filled
            case .filled:
                return .semi
            case .semi:
                return .regular
            }
        }
    }

    public enum TextAlignment: Int, CaseIterable {
        case left
        case center
        case right

        var next: TextAlignment {
            switch self {
            case .left:
                return .center
            case .center:
                return .right
            case .right:
                return .left
            }
        }

        var nsAlignment: NSTextAlignment {
            switch self {
            case .left:
                return .left
            case .center:
                return .center
            case .right:
                return .right
            }
        }
    }

    public enum TextFont: Int, CaseIterable {
        case sanFrancisco
        case typewriter
        case avenirNext
        case courierNew
        case noteworthy
        case georgia
        case papyrus
        case snellRoundhand

        public var title: String {
            switch self {
            case .sanFrancisco:
                return "San Francisco"
            case .typewriter:
                return "Typewriter"
            case .avenirNext:
                return "Avenir Next"
            case .courierNew:
                return "Courier New"
            case .noteworthy:
                return "Noteworthy"
            case .georgia:
                return "Georgia"
            case .papyrus:
                return "Papyrus"
            case .snellRoundhand:
                return "Snell Roundhand"
            }
        }

        private var postScriptName: String? {
            switch self {
            case .sanFrancisco:
                return nil
            case .typewriter:
                return "AmericanTypewriter"
            case .avenirNext:
                return "AvenirNext-DemiBoldItalic"
            case .courierNew:
                return "CourierNewPS-BoldMT"
            case .noteworthy:
                return "Noteworthy-Bold"
            case .georgia:
                return "Georgia-Bold"
            case .papyrus:
                return "Papyrus"
            case .snellRoundhand:
                return "SnellRoundhand-Bold"
            }
        }

        public func font(size: CGFloat) -> NSFont {
            if let name = postScriptName, let font = NSFont(name: name, size: size) {
                return font
            }
            return NSFont.systemFont(ofSize: size, weight: .semibold)
        }
    }

    public enum DrawType: Int {
        case fill
        case stroke
    }

    public enum ShapeType: Int {
        case rectangle
        case ellipse
        case star
    }

    public enum VectorType: Int {
        case oneSidedArrow
        case twoSidedArrow
        case line

        var next: VectorType {
            switch self {
            case .oneSidedArrow:
                return .twoSidedArrow
            case .twoSidedArrow:
                return .line
            case .line:
                return .oneSidedArrow
            }
        }
    }

    public struct Text: Hashable {
        public var string: String
        public var style: TextStyle
        public var font: TextFont
        public var alignment: TextAlignment
        public var color: EditImageCanvasColor
        public var fontSize: CGFloat
        public var width: CGFloat
    }

    public struct Sticker: Equatable {
        public var image: CGImage
        public var baseSize: CGSize
        public var fileId: Int64?
        public var animation: EditImageCanvasStickerAnimation? = nil

        public static func == (lhs: Sticker, rhs: Sticker) -> Bool {
            return lhs.image === rhs.image && lhs.baseSize == rhs.baseSize && lhs.fileId == rhs.fileId && lhs.animation == rhs.animation
        }
    }

    public struct Shape: Equatable {
        public var type: ShapeType
        public var drawType: DrawType
        public var color: EditImageCanvasColor
        public var lineWidth: CGFloat
        public var size: CGSize
    }

    public struct Bubble: Equatable {
        public var drawType: DrawType
        public var color: EditImageCanvasColor
        public var lineWidth: CGFloat
        public var size: CGSize
        public var tailPosition: CGPoint
    }

    public struct Vector: Equatable {
        public var type: VectorType
        public var color: EditImageCanvasColor
        public var lineWidth: CGFloat
        public var start: CGPoint
        public var end: CGPoint
        public var mid: CGPoint
    }

    public enum Content: Equatable {
        case text(Text)
        case sticker(Sticker)
        case shape(Shape)
        case bubble(Bubble)
        case vector(Vector)
    }

    public let id: Int64
    public var content: Content
    public var position: CGPoint
    public var scale: CGFloat
    public var rotation: CGFloat
    public var mirrored: Bool
    public var referenceSize: CGSize

    public init(id: Int64 = Int64.random(in: Int64.min ... Int64.max), content: Content, position: CGPoint, scale: CGFloat = 1.0, rotation: CGFloat = 0.0, mirrored: Bool = false, referenceSize: CGSize) {
        self.id = id
        self.content = content
        self.position = position
        self.scale = scale
        self.rotation = rotation
        self.mirrored = mirrored
        self.referenceSize = referenceSize
    }

    public func duplicate() -> EditImageCanvasEntity {
        var copy = EditImageCanvasEntity(content: content, position: position, scale: scale, rotation: rotation, mirrored: mirrored, referenceSize: referenceSize)
        let offset = referenceSize.width * 0.1
        if case var .vector(vector) = copy.content {
            vector.start = vector.start.offsetBy(dx: offset, dy: offset)
            vector.end = vector.end.offsetBy(dx: offset, dy: offset)
            copy.content = .vector(vector)
        } else {
            copy.position = position.offsetBy(dx: offset, dy: offset)
        }
        return copy
    }

    public func transformed(angle: CGFloat, flipped: Bool) -> EditImageCanvasEntity {
        let theta = angle * .pi / 180.0
        let original = referenceSize
        let rotated = NSMakeSize(abs(original.width * cos(theta)) + abs(original.height * sin(theta)), abs(original.width * sin(theta)) + abs(original.height * cos(theta)))
        let transformPoint: (CGPoint) -> CGPoint = { point in
            var x = point.x
            let y = point.y
            if flipped {
                x = original.width - x
            }
            let tempX = x - original.width / 2.0
            let tempY = y - original.height / 2.0
            let rotatedX = tempX * cos(theta) - tempY * sin(theta)
            let rotatedY = tempX * sin(theta) + tempY * cos(theta)
            return NSMakePoint(rotatedX + rotated.width / 2.0, rotatedY + rotated.height / 2.0)
        }
        var result = self
        result.referenceSize = NSMakeSize(round(rotated.width), round(rotated.height))
        result.position = transformPoint(position)
        result.rotation = (flipped ? -rotation : rotation) + theta
        result.mirrored = flipped ? !mirrored : mirrored
        if case var .vector(vector) = content {
            vector.start = transformPoint(vector.start)
            vector.end = transformPoint(vector.end)
            if flipped {
                vector.mid.y = -vector.mid.y
            }
            result.content = .vector(vector)
            result.rotation = 0
            result.mirrored = false
        }
        return result
    }

    var isVector: Bool {
        if case .vector = content {
            return true
        }
        return false
    }

    var isText: Bool {
        if case .text = content {
            return true
        }
        return false
    }

    var text: Text? {
        if case let .text(text) = content {
            return text
        }
        return nil
    }

    var sticker: Sticker? {
        if case let .sticker(sticker) = content {
            return sticker
        }
        return nil
    }

    var color: EditImageCanvasColor? {
        switch content {
        case let .text(text):
            return text.color
        case .sticker:
            return nil
        case let .shape(shape):
            return shape.color
        case let .bubble(bubble):
            return bubble.color
        case let .vector(vector):
            return vector.color
        }
    }

    mutating func setColor(_ color: EditImageCanvasColor) {
        switch content {
        case var .text(text):
            text.color = color
            content = .text(text)
        case .sticker:
            break
        case var .shape(shape):
            shape.color = color
            content = .shape(shape)
        case var .bubble(bubble):
            bubble.color = color
            content = .bubble(bubble)
        case var .vector(vector):
            vector.color = color
            content = .vector(vector)
        }
    }

    var sizeValue: CGFloat? {
        switch content {
        case let .text(text):
            return text.fontSize
        case .sticker:
            return nil
        case let .shape(shape):
            return shape.drawType == .stroke ? shape.lineWidth : nil
        case let .bubble(bubble):
            return bubble.drawType == .stroke ? bubble.lineWidth : nil
        case let .vector(vector):
            return vector.lineWidth
        }
    }

    mutating func setSizeValue(_ value: CGFloat) {
        let value = max(0, min(1, value))
        switch content {
        case var .text(text):
            text.fontSize = value
            content = .text(text)
        case .sticker:
            break
        case var .shape(shape):
            shape.lineWidth = value
            content = .shape(shape)
        case var .bubble(bubble):
            bubble.lineWidth = value
            content = .bubble(bubble)
        case var .vector(vector):
            vector.lineWidth = value
            content = .vector(vector)
        }
    }

    var localTransform: CGAffineTransform {
        var transform = CGAffineTransform(translationX: position.x, y: position.y)
        transform = transform.rotated(by: rotation)
        transform = transform.scaledBy(x: scale * (mirrored ? -1.0 : 1.0), y: scale)
        return transform
    }

    func localSize(textSize: (Text, CGSize) -> CGSize) -> CGSize {
        switch content {
        case let .text(text):
            return textSize(text, referenceSize)
        case let .sticker(sticker):
            return sticker.baseSize
        case let .shape(shape):
            return shape.size
        case let .bubble(bubble):
            return bubble.size
        case .vector:
            return .zero
        }
    }

    func selectionLocalRect(textSize: (Text, CGSize) -> CGSize) -> CGRect {
        let size = localSize(textSize: textSize)
        switch content {
        case .sticker:
            let side = max(size.width, size.height)
            return NSMakeRect(-side / 2.0, -side / 2.0, side, side)
        default:
            return NSMakeRect(-size.width / 2.0, -size.height / 2.0, size.width, size.height)
        }
    }

    func vectorMidPoint() -> CGPoint? {
        guard case let .vector(vector) = content else {
            return nil
        }
        return editImageCanvasVectorMidPoint(start: vector.start, end: vector.end, mid: vector.mid)
    }

    func contains(_ point: CGPoint, tolerance: CGFloat, textSize: (Text, CGSize) -> CGSize) -> Bool {
        switch content {
        case let .vector(vector):
            let path = editImageCanvasVectorPath(vector, referenceSize: referenceSize)
            if path.contains(point) {
                return true
            }
            let hitPath = path.copy(strokingWithWidth: tolerance * 2.0, lineCap: .round, lineJoin: .round, miterLimit: 0)
            return hitPath.contains(point)
        default:
            let local = point.applying(localTransform.inverted())
            let localTolerance = tolerance / max(0.01, scale)
            var rect = selectionLocalRect(textSize: textSize)
            if case let .bubble(bubble) = content {
                rect.size.height += max(0, bubble.tailPosition.y)
            }
            return rect.insetBy(dx: -localTolerance, dy: -localTolerance).contains(local)
        }
    }
}

func editImageCanvasVectorMidPoint(start: CGPoint, end: CGPoint, mid: CGPoint) -> CGPoint {
    let distance = hypot(end.x - start.x, end.y - start.y)
    let angle = atan2(end.y - start.y, end.x - start.x)
    let p1 = CGPoint(x: start.x + distance * mid.x * cos(angle), y: start.y + distance * mid.x * sin(angle))
    let perpendicular = angle + .pi * 0.5
    return CGPoint(x: p1.x + distance * mid.y * cos(perpendicular), y: p1.y + distance * mid.y * sin(perpendicular))
}

func editImageCanvasVectorMid(start: CGPoint, end: CGPoint, midPoint: CGPoint) -> CGPoint {
    let distance = max(0.001, hypot(end.x - start.x, end.y - start.y))
    let dx = end.x - start.x
    let dy = end.y - start.y
    let t = ((midPoint.x - start.x) * dx + (midPoint.y - start.y) * dy) / (distance * distance)
    let pointOnLine = CGPoint(x: start.x + dx * t, y: start.y + dy * t)
    var height = hypot(midPoint.x - pointOnLine.x, midPoint.y - pointOnLine.y) / distance
    let cross = dx * (midPoint.y - start.y) - dy * (midPoint.x - start.x)
    if cross < 0 {
        height = -height
    }
    return CGPoint(x: t, y: height)
}
