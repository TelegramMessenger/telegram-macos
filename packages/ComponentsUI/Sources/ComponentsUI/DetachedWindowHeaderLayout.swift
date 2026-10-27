import Cocoa

public struct DetachedWindowHeaderLayout {
    public static let controlsWidth: CGFloat = 80
    public static let height: CGFloat = 40
    public static let spacing: CGFloat = 8
    public static let sideInset: CGFloat = 12

    public let controlsFrame: NSRect
    public let backButtonFrame: NSRect
    public let leadingPillFrame: NSRect
    public let contentMinX: CGFloat

    public init(origin: NSPoint, showsControls: Bool, hasBackButton: Bool) {
        let controlsWidth = showsControls ? Self.controlsWidth : 0
        let backWidth = hasBackButton ? Self.height : 0
        controlsFrame = NSRect(origin: origin, size: NSSize(width: controlsWidth, height: Self.height))
        backButtonFrame = NSRect(x: controlsFrame.maxX, y: origin.y, width: backWidth, height: Self.height)
        leadingPillFrame = NSRect(origin: origin, size: NSSize(width: controlsWidth + backWidth, height: Self.height))
        contentMinX = leadingPillFrame.maxX + (leadingPillFrame.width > 0 ? Self.spacing : 0)
    }
}
