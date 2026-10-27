import Cocoa

public struct DetachedWindowHeaderLayout {
    public static let standardLayoutWidth: CGFloat = 650

    public static func usesCompactLayout(width: CGFloat) -> Bool {
        return width < standardLayoutWidth
    }

    public static let controlsWidth: CGFloat = 72
    public static let height: CGFloat = 40
    public static let spacing: CGFloat = 6
    public static let sideInset: CGFloat = 12
    public static let dividerHeight: CGFloat = 18

    public let controlsFrame: NSRect
    public let backButtonFrame: NSRect
    public let leadingPillFrame: NSRect
    public let dividerFrame: NSRect?
    public let contentMinX: CGFloat

    public init(origin: NSPoint, showsControls: Bool, hasBackButton: Bool) {
        let controlsWidth = showsControls ? Self.controlsWidth : 0
        let backWidth = hasBackButton ? Self.height : 0
        controlsFrame = NSRect(origin: origin, size: NSSize(width: controlsWidth, height: Self.height))
        backButtonFrame = NSRect(x: controlsFrame.maxX, y: origin.y, width: backWidth, height: Self.height)
        leadingPillFrame = NSRect(origin: origin, size: NSSize(width: controlsWidth + backWidth, height: Self.height))
        contentMinX = leadingPillFrame.maxX + (leadingPillFrame.width > 0 ? Self.spacing : 0)
        if showsControls && hasBackButton {
            dividerFrame = NSRect(x: controlsFrame.maxX - 0.5, y: origin.y + floor((Self.height - Self.dividerHeight) / 2), width: 1, height: Self.dividerHeight)
        } else {
            dividerFrame = nil
        }
    }
}
