import Cocoa

public struct DetachedWindowHeaderLayout: Equatable {
    public static let standardLayoutWidth: CGFloat = 650

    public static func usesCompactLayout(width: CGFloat) -> Bool {
        return width < standardLayoutWidth
    }

    public static let sideInset: CGFloat = 12
    public static let topInset: CGFloat = 12
    public static let height: CGFloat = 40
    public static let spacing: CGFloat = 10

    public let buttonsOffset: NSPoint
    public let capsuleFrame: NSRect

    public init(buttonsFrame: NSRect, titlebarFrame: NSRect) {
        let padding = floor((Self.height - buttonsFrame.height) / 2)
        let maxShiftY = titlebarFrame.maxY - buttonsFrame.maxY
        let dy = min(Self.topInset + padding - buttonsFrame.minY, maxShiftY)
        let dx = Self.sideInset + padding - buttonsFrame.minX
        buttonsOffset = NSPoint(x: dx, y: dy)
        let placed = buttonsFrame.offsetBy(dx: dx, dy: dy)
        capsuleFrame = NSRect(x: Self.sideInset, y: placed.midY - Self.height / 2, width: placed.width + padding * 2, height: Self.height)
    }

    public var reservedWidth: CGFloat {
        return capsuleFrame.maxX + Self.spacing
    }
}
