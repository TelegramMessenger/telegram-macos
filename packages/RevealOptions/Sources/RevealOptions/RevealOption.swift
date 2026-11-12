import AppKit
import TGUIKit

public protocol RevealOptionAnimationView: NSView {
    func play()
    func reset()
}

public struct RevealOptionAnimation: Equatable {
    public let name: String
    public let scale: CGFloat
    public let offset: CGFloat
    public let keysToColor: [String]
    public let flip: Bool

    public init(name: String, scale: CGFloat = 1, offset: CGFloat = 0, keysToColor: [String] = [], flip: Bool = false) {
        self.name = name
        self.scale = scale
        self.offset = offset
        self.keysToColor = keysToColor
        self.flip = flip
    }
}

public typealias RevealOptionAnimationFactory = (_ animation: RevealOptionAnimation, _ color: NSColor, _ size: NSSize) -> RevealOptionAnimationView?

public struct RevealOptionsConfiguration {
    public enum Sizing {
        case circles
        case pills
    }

    public var scale: CGFloat
    public var iconScale: CGFloat
    public var sizing: Sizing
    public var titleFont: NSFont
    public var pillTitleFont: NSFont
    public var enableAnimations: Bool

    public init(scale: CGFloat = 0.8, iconScale: CGFloat = 1.5, sizing: Sizing = .circles, titleFont: NSFont = .medium(11), pillTitleFont: NSFont = .medium(13), enableAnimations: Bool = true) {
        self.scale = scale
        self.iconScale = iconScale
        self.sizing = sizing
        self.titleFont = titleFont
        self.pillTitleFont = pillTitleFont
        self.enableAnimations = enableAnimations
    }

    public static let chatList = RevealOptionsConfiguration()
    public static let news = RevealOptionsConfiguration(sizing: .pills)
}

public struct RevealOptionsSurface {
    public var color: NSColor
    public var cornerRadius: CGFloat
    public var frame: NSRect

    public init(color: NSColor, cornerRadius: CGFloat, frame: NSRect) {
        self.color = color
        self.cornerRadius = cornerRadius
        self.frame = frame
    }
}

public enum RevealOptionIcon: Equatable {
    case none
    case image(CGImage)
    case animation(RevealOptionAnimation)

    public static func ==(lhs: RevealOptionIcon, rhs: RevealOptionIcon) -> Bool {
        switch lhs {
        case .none:
            if case .none = rhs {
                return true
            }
            return false
        case let .image(lhsImage):
            if case let .image(rhsImage) = rhs, lhsImage === rhsImage {
                return true
            }
            return false
        case let .animation(lhsAnimation):
            if case let .animation(rhsAnimation) = rhs, lhsAnimation == rhsAnimation {
                return true
            }
            return false
        }
    }

    var hasVisualIcon: Bool {
        switch self {
        case .none:
            return false
        case .image, .animation:
            return true
        }
    }
}

public struct RevealOption: Equatable {
    public let key: Int32
    public let animationKey: Int32
    public let title: String
    public let icon: RevealOptionIcon
    public let color: NSColor
    public let iconColor: NSColor
    public let textColor: NSColor
    public let isDestructive: Bool

    public init(key: Int32, animationKey: Int32? = nil, title: String, icon: RevealOptionIcon, color: NSColor, iconColor: NSColor, textColor: NSColor, isDestructive: Bool = false) {
        self.key = key
        self.animationKey = animationKey ?? key
        self.title = title
        self.icon = icon
        self.color = color
        self.iconColor = iconColor
        self.textColor = textColor
        self.isDestructive = isDestructive
    }

    public static func ==(lhs: RevealOption, rhs: RevealOption) -> Bool {
        return lhs.key == rhs.key && lhs.animationKey == rhs.animationKey && lhs.title == rhs.title && lhs.icon == rhs.icon && lhs.color.isEqual(rhs.color) && lhs.iconColor.isEqual(rhs.iconColor) && lhs.textColor.isEqual(rhs.textColor) && lhs.isDestructive == rhs.isDestructive
    }
}

struct RevealOptionLayoutMetrics {
    let scale: CGFloat
    var iconScale: CGFloat = 1.5
    let shapeSize: NSSize
    let slotWidth: CGFloat
    let titleWidth: CGFloat
    let iconMaxSide: CGFloat
    let cornerRadius: CGFloat
    let expandedIconInset: CGFloat
    var spacing: CGFloat
    var edgeInset: CGFloat

    var titleSpacing: CGFloat { return 4 * self.scale }
    var titleGap: CGFloat { return 6 * self.scale }
    var iconlessTitleExpandedHorizontalPadding: CGFloat { return 8 * self.scale }
    var iconlessTitleHorizontalPadding: CGFloat { return 8 * self.scale }
    var animationSide: CGFloat { return 66 * self.scale }

    static func metrics(for height: CGFloat, hasVisualIcons: Bool, scale: CGFloat, titleFont: NSFont) -> RevealOptionLayoutMetrics {
        let regularShapeSide = 50 * scale
        let titleLineHeight = ceil(titleFont.ascender - titleFont.descender + titleFont.leading)
        let regularContentHeight = regularShapeSide + 4 * scale + titleLineHeight
        if height < regularContentHeight || !hasVisualIcons {
            return RevealOptionLayoutMetrics(scale: scale, shapeSize: NSMakeSize(60 * scale, 32 * scale), slotWidth: 70 * scale, titleWidth: 70 * scale, iconMaxSide: 24 * scale, cornerRadius: 16 * scale, expandedIconInset: 16 * scale, spacing: 10 * scale, edgeInset: 10 * scale)
        } else {
            return RevealOptionLayoutMetrics(scale: scale, shapeSize: NSMakeSize(regularShapeSide, regularShapeSide), slotWidth: 60 * scale, titleWidth: 60 * scale, iconMaxSide: 40 * scale, cornerRadius: 25 * scale, expandedIconInset: 20 * scale, spacing: 10 * scale, edgeInset: 10 * scale)
        }
    }

    func withTitleWidths(_ widths: [CGFloat]) -> RevealOptionLayoutMetrics {
        guard let first = widths.first, let last = widths.last else {
            return self
        }
        var stride = self.shapeSize.width + self.spacing
        for index in 0 ..< widths.count - 1 {
            stride = max(stride, ceil((widths[index] + widths[index + 1]) / 2 + self.titleGap))
        }
        var result = self
        result.spacing = stride - self.shapeSize.width
        result.edgeInset = max(self.edgeInset, ceil((max(first, last) - self.shapeSize.width) / 2 + self.titleGap / 2))
        return result
    }

    func withGroupTitleWidth(_ maxTitleWidth: CGFloat) -> RevealOptionLayoutMetrics {
        if maxTitleWidth <= self.shapeSize.width - self.iconlessTitleExpandedHorizontalPadding {
            return self
        }
        let updatedShapeWidth = ceil(maxTitleWidth + self.iconlessTitleExpandedHorizontalPadding)
        let slotWidthDelta = self.slotWidth - self.shapeSize.width
        return RevealOptionLayoutMetrics(
            scale: self.scale,
            iconScale: self.iconScale,
            shapeSize: NSMakeSize(updatedShapeWidth, self.shapeSize.height),
            slotWidth: updatedShapeWidth + slotWidthDelta,
            titleWidth: max(self.titleWidth, updatedShapeWidth - self.iconlessTitleExpandedHorizontalPadding),
            iconMaxSide: self.iconMaxSide,
            cornerRadius: self.cornerRadius,
            expandedIconInset: self.expandedIconInset,
            spacing: self.spacing,
            edgeInset: self.edgeInset
        )
    }

    func revealWidth(count: Int) -> CGFloat {
        if count == 0 {
            return 0
        }
        return self.edgeInset * 2 + self.shapeSize.width * CGFloat(count) + self.spacing * CGFloat(count - 1)
    }
}
