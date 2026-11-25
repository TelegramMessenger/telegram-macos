import Cocoa
import TGUIKit
@testable import ChatLayerEngineBaseline

final class ChatTextTable {
    var notedRows: [Int] = []
    func noteHeightOfRow(_ index: Int, _ animated: Bool) { notedRows.append(index) }
}

final class ChatMessageItem {
    let stableId: Int
    let textLayout: FoldingTextLayout
    var papercutLayout: Bool?
    var height: CGFloat = 40
    var width: CGFloat = 240
    var index = 0
    var previousBlockWidth: CGFloat = 100
    var table: ChatTextTable?
    var textOrigin = NSPoint.zero
    var revealedIndices: [Int] = []
    init(id: Int, layout: FoldingTextLayout) { stableId = id; textLayout = layout }
    func revealBlockAtIndex(_ index: Int) { revealedIndices.append(index) }
    func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool { height = textLayout.size.height; return true }
}

final class ChatTextWebpage {
    var selectableTextViews: [TextView] = []
}

class ChatTextRow: View, MultipleSelectable, ChatTextSelectionProvider {
    var nativeCaptions: [TextView] = []
    var captionViews: [LayerCaptionRow.CaptionView] = []
    var webpageContent: ChatTextWebpage?
    var header: String?
    var selectableTextViews: [TextView] { captionViews.flatMap { $0.nativeView?.textViews ?? [] } + nativeCaptions }
    var textSelectionSources: ChatTextSelectionSources {
        guard captionViews.contains(where: { $0.layerView != nil }) else { return .views(selectableTextViews) }
        var sources: [ChatTextSelectionSource] = []
        for caption in captionViews {
            if let layer = caption.layerView {
                sources.append(contentsOf: layer.body.textNodes.map { .layer($0, layer) })
            } else if let native = caption.nativeView {
                sources.append(contentsOf: native.textViews.map(ChatTextSelectionSource.view))
            }
        }
        sources.append(contentsOf: nativeCaptions.map(ChatTextSelectionSource.view))
        return .mixed(sources)
    }
    var item: AnyObject?
    var text: FoldingTextView?
    var layerText: ChatLayerMessageTextView?
    var textBindingVersion: UInt64 = 0
    func textFrame(_ item: ChatMessageItem) -> NSRect { NSRect(origin: item.textOrigin, size: item.textLayout.size) }
    func bind(_ next: ChatMessageItem, animated: Bool = false) { fatalError() }
}
