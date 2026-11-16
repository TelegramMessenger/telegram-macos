import Cocoa
import TGUIKit
@testable import ChatLayerEngineBaseline

typealias MessageId = Int
struct Message { let id: MessageId }

final class ChatRowItem {
    final class RowCaption {
        let message: Message
        let id: UInt32
        let layout: FoldingTextLayout
        let isLoading: Bool
        var offset: NSPoint
        init(messageId: MessageId, id: UInt32, layout: FoldingTextLayout, loading: Bool = false, offset: NSPoint = .zero) {
            message = Message(id: messageId)
            self.id = id
            self.layout = layout
            isLoading = loading
            self.offset = offset
        }
    }
    var captionLayouts: [RowCaption]
    var revealed: [(Int, MessageId)] = []
    init(_ captions: [RowCaption]) { captionLayouts = captions }
    func revealBlockAtIndex(_ index: Int, messageId: MessageId) { revealed.append((index, messageId)) }
}

final class CaptionFactCheck {
    final class Content { let textView = TextView() }
    let textView = Content()
}

class CaptionRowEnvironment: View {
    var item: AnyObject?
    let rowView = View()
    let contentView = View()
    var views: [FoldingTextView] { [] }
    var contentViews: [View] { views }
    var factCheckView: CaptionFactCheck?
    var selectableTextViews: [TextView] { [] }
    var textSelectionSources: ChatTextSelectionSources { .views(selectableTextViews) }
    var ids: [UInt32] { [] }
    var shimmers: [Bool] { [] }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(rowView)
        rowView.addSubview(contentView)
        rowView.frame = bounds
    }
    required init?(coder: NSCoder) { fatalError() }
    func bind(_ item: ChatRowItem, animated: Bool = false) {
        self.item = item
        fillCaption(item, animated: animated)
    }
    func fillCaption(_ item: ChatRowItem, animated: Bool) { fatalError() }
    func captionFrame(_ item: ChatRowItem, caption: ChatRowItem.RowCaption) -> NSRect {
        CGRect(origin: caption.offset, size: caption.layout.size)
    }
    func finishLayout() {
        guard let item = item as? ChatRowItem else { return }
        for (id, view) in zip(ids, contentViews) {
            if let caption = item.captionLayouts.first(where: { $0.id == id }) {
                view.frame = captionFrame(item, caption: caption)
            }
        }
    }
}
