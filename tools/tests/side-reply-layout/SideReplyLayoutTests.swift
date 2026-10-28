import Cocoa

final class Accessory {
    var isSideAccessory = true
    var size = NSSize.zero
    var width: CGFloat = 0
    var longQuote = false
    func measureSize(_ width: CGFloat, sizeToFit: Bool) {
        self.width = width
        let lines = longQuote ? min(8, ceil(700 / max(1, width - 14))) : 1
        size = NSSize(width: sizeToFit ? min(180, max(1, width)) + 12 : width, height: 22 + 16 * lines)
    }
}
struct Mode { var isThreadMode = false }
struct Location { var threadMsgId: Int? }
struct Interaction { let mode = Mode(); let chatLocation = Location() }
struct Message { let id: Int }
final class ChatRowItem {
    var width: CGFloat = 320
    var leftInset: CGFloat = 13
    var rightInset: CGFloat = 12
    var defLeftInset: CGFloat = 20
    var isIncoming = false
    var isBubbled = true
    var hasBubble = false
    var isBubbleFullFilled = true
    var isSharable = false
    var hasSource = false
    var commentsBubbleDataOverlay: Int?
    var elementsContentInset: CGFloat = 0
    var bubbleContentInset: CGFloat = 0
    var additionBubbleInset: CGFloat = 6
    var bubbleDefaultInnerInset: CGFloat { bubbleContentInset * 2 + additionBubbleInset }
    var _contentSize = NSSize(width: 160, height: 80)
    var contentSize: NSSize { _contentSize }
    var contentOffset: NSPoint { NSPoint(x: defLeftInset, y: 2) }
    var bubbleFrameWidth: CGFloat { _contentSize.width + additionBubbleInset }
    var max_reply_size_width: CGFloat { _contentSize.width }
    var additionalLineForDateInBubbleState: CGFloat?
    var defaultContentTopOffset: CGFloat = 2
    var replyOffset: CGFloat = 5
    var replyModel: Accessory? = Accessory()
    let chatInteraction = Interaction()
    var message: Message?
    func measureReply() {
        let cachedBlockWidth = width
        if let replyModel = replyModel { __MEASURE__ }
    }
    var height: CGFloat {
        var height = _contentSize.height + defaultContentTopOffset * 2
        __HEIGHT__
        return height
    }
    var replyFrame: NSRect {
        let bubble = ChatRowGeometry.bubbleFrame(.init(rowWidth: width, layoutFrame: NSRect(x: defLeftInset, y: 0, width: bubbleFrameWidth, height: 0), leftInset: leftInset, isIncoming: isIncoming, isCenteredThread: false))
        let content = ChatRowGeometry.contentFrame(.init(item: self, bubbleFrame: bubble))
        return ChatRowGeometry.sideAccessoryFrame(.init(item: self, size: replyModel!.size, offset: replyOffset, contentFrame: content))
    }
}
var checks = 0
var failures = 0
func expect(_ condition: @autoclosure () -> Bool, _ name: String) {
    checks += 1
    if !condition() { failures += 1; print("FAIL: \(name)") }
}
for width in [CGFloat(300), 320, 350, 400, 640, 1280] {
    for incoming in [false, true] {
        for sideAction in [false, true] {
            for contentWidth in [CGFloat(80), 160, 200] {
                for longQuote in [false, true] {
                    let row = ChatRowItem()
                    row.width = width
                    row.isIncoming = incoming
                    row.isSharable = sideAction
                    row._contentSize.width = contentWidth
                    row.replyModel!.longQuote = longQuote
                    row.measureReply()
                    let frame = row.replyFrame
                    let tag = "width=\(width) incoming=\(incoming) action=\(sideAction) content=\(contentWidth) quote=\(longQuote)"
                    expect(frame.minX >= row.leftInset, "reply keeps left margin: \(tag)")
                    expect(frame.maxX <= width - row.rightInset, "reply keeps right margin: \(tag)")
                    expect(frame.maxY <= row.height - row.defaultContentTopOffset, "entire quoted reply fits row height: \(tag)")
                }
            }
        }
    }
}
let row = ChatRowItem()
row.width = 1280
row.measureReply()
expect(row.replyModel!.size.width == 172, "wide layout keeps intrinsic side reply sizing")
row.width = 320
row.measureReply()
expect(row.replyFrame.minX >= row.leftInset, "resizing narrows existing reply")
row.width = 1280
row.measureReply()
expect(row.replyModel!.size.width == 172, "resizing restores intrinsic side reply width")
print("\(checks - failures)/\(checks) side reply layout checks passed")
exit(failures == 0 ? 0 : 1)
