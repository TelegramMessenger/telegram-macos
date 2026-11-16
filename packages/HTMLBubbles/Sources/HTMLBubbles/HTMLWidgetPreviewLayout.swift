import Foundation

public struct HTMLWidgetPreviewLayout {
    public let contentSize: CGSize
    public let displaySize: CGSize

    public init(width: Int32, height: Int32, availableWidth: CGFloat, reportedHeight: CGFloat?) {
        let availableWidth = min(450, max(1, availableWidth))
        let contentWidth = width > 0 ? min(availableWidth, max(HTMLWidgetPayload.minimumWidth, CGFloat(width))) : availableWidth
        let contentHeight = HTMLWidgetPayload.clampedHeight(height > 0 ? CGFloat(height) : reportedHeight ?? 160)
        self.contentSize = CGSize(width: contentWidth, height: contentHeight)
        let scale = min(1, 240 / contentHeight)
        self.displaySize = CGSize(width: contentWidth * scale, height: contentHeight * scale)
    }
}
