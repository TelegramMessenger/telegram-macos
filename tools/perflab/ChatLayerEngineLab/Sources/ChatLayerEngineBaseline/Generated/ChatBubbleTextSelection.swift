import Cocoa
import TelegramCore

public struct ChatBubbleSelectionFragment {
    public let attributedString: NSAttributedString
    public let range: NSRange
    public let index: Int
    public var richText: [RichText]? = nil
}

public protocol ChatBubbleCustomTextSelection: AnyObject {
    func applyBubbleSelection(begin: NSPoint, end: NSPoint, isStartRow: Bool, isEndRow: Bool, reversed: Bool) -> [ChatBubbleSelectionFragment]
    func clearBubbleSelection()
}
