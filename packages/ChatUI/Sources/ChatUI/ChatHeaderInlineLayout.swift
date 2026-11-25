import Foundation
import CoreGraphics

struct ChatHeaderInlineLayout {
    static let minimumAccessoryWidth: CGFloat = 320
    static let minimumSearchAccessoryWidth: CGFloat = 480

    static func accessoryFrame(in available: CGRect, preferredTitleWidth: CGFloat, spacing: CGFloat) -> CGRect? {
        let titleWidth = min(260, max(220, preferredTitleWidth))
        let accessoryWidth = available.width - titleWidth - spacing
        guard accessoryWidth >= minimumAccessoryWidth else {
            return nil
        }
        return CGRect(x: available.minX + titleWidth + spacing, y: available.minY, width: accessoryWidth, height: available.height)
    }
}
