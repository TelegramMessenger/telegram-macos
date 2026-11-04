import Cocoa

public struct DetachedWindowHeaderLayout {
    public static let standardLayoutWidth: CGFloat = 650

    public static func usesCompactLayout(width: CGFloat) -> Bool {
        return width < standardLayoutWidth
    }

    public static let height: CGFloat = 40
    public static let capsuleHeight: CGFloat = 36
    public static let spacing: CGFloat = 6
    public static let sideInset: CGFloat = 12
    public static let buttonSize: CGFloat = 14
    public static let buttonSpacing: CGFloat = 9
    public static let controlsLeadingInset: CGFloat = 11
    public static let controlsTrailingInset: CGFloat = 12
    public static let controlsWidth: CGFloat = controlsLeadingInset + buttonSize * 3 + buttonSpacing * 2 + controlsTrailingInset
    public static let dividerWidth: CGFloat = 1
    public static let dividerHeight: CGFloat = 20
    public static let backButtonSize: CGFloat = 30
    public static let backButtonInset: CGFloat = 3
    public static let backSegmentWidth: CGFloat = dividerWidth + backButtonInset * 2 + backButtonSize

    public let controlsFrame: NSRect
    public let backButtonFrame: NSRect
    public let leadingPillFrame: NSRect
    public let dividerFrame: NSRect?
    public let contentMinX: CGFloat

    public init(origin: NSPoint, showsControls: Bool, hasBackButton: Bool) {
        if showsControls {
            let capsuleY = origin.y + floor((Self.height - Self.capsuleHeight) / 2)
            controlsFrame = NSRect(x: origin.x, y: capsuleY, width: Self.controlsWidth, height: Self.capsuleHeight)
            if hasBackButton {
                let divider = NSRect(x: controlsFrame.maxX, y: capsuleY + floor((Self.capsuleHeight - Self.dividerHeight) / 2), width: Self.dividerWidth, height: Self.dividerHeight)
                dividerFrame = divider
                backButtonFrame = NSRect(x: divider.maxX + Self.backButtonInset, y: capsuleY + Self.backButtonInset, width: Self.backButtonSize, height: Self.backButtonSize)
                leadingPillFrame = NSRect(x: origin.x, y: capsuleY, width: Self.controlsWidth + Self.backSegmentWidth, height: Self.capsuleHeight)
            } else {
                dividerFrame = nil
                backButtonFrame = NSRect(x: controlsFrame.maxX, y: origin.y, width: 0, height: 0)
                leadingPillFrame = NSRect(x: origin.x, y: capsuleY, width: Self.controlsWidth - Self.controlsTrailingInset + Self.controlsLeadingInset, height: Self.capsuleHeight)
            }
        } else {
            controlsFrame = NSRect(x: origin.x, y: origin.y, width: 0, height: Self.height)
            dividerFrame = nil
            backButtonFrame = NSRect(x: origin.x, y: origin.y, width: hasBackButton ? Self.height : 0, height: Self.height)
            leadingPillFrame = backButtonFrame
        }
        contentMinX = leadingPillFrame.maxX + (leadingPillFrame.width > 0 ? Self.spacing : 0)
    }
}
