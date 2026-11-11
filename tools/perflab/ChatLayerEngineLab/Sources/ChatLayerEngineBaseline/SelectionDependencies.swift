import Cocoa
import TGUIKit

final class ChatInteraction {
    enum State { case normal, selecting }
    struct Presentation { var state = State.normal }
    var presentation = Presentation()
}
struct SelectionTheme { let bubbled = false }
let theme = SelectionTheme()

class ChatRichTextRowView: NSObject, ChatBubbleCustomTextSelection {
    var clearCount = 0
    func clearBubbleSelection() { clearCount += 1 }
    func applyBubbleSelection(begin: NSPoint, end: NSPoint, isStartRow: Bool, isEndRow: Bool, reversed: Bool) -> [ChatBubbleSelectionFragment] { return [] }
}

final class ChatRowItem {
    let stableId: AnyHashable
    weak var view: NSView?
    init(id: AnyHashable, view: NSView) { stableId = id; self.view = view }
}

class ChatRowView: View, MultipleSelectable, ChatTextSelectionProvider {
    var textSelectionSources: ChatTextSelectionSources { .views(selectableTextViews) }
    var item: ChatRowItem?
    var selectableTextViews: [TextView] = []
    var header: String?
    func bubbleFrame(_ item: ChatRowItem) -> NSRect { bounds }
    func toggleSelected(_ deselect: Bool, in point: NSPoint) {}
}

final class SelectionTable {
    let documentView: NSView?
    let rows: [ChatRowItem]
    private let views: [NSView]
    private let reversed: Bool
    var offscreenRows = Set<Int>()
    var count: Int { rows.count }
    init(views: [NSView], reversed: Bool = true) {
        self.views = views
        self.reversed = reversed
        rows = views.enumerated().map { ChatRowItem(id: $0.offset, view: $0.element) }
        let document = View(frame: NSRect(x: 0, y: 0, width: 300, height: CGFloat(100 * views.count)))
        for (index, view) in views.enumerated() {
            view.frame = NSRect(x: 0, y: CGFloat((reversed ? views.count - 1 - index : index) * 100), width: 300, height: 100)
            document.addSubview(view)
            (view as? ChatRowView)?.item = rows[index]
        }
        documentView = document
    }
    func row(at point: NSPoint) -> Int {
        let index = min(rows.count - 1, max(0, Int(point.y / 100)))
        return reversed ? rows.count - 1 - index : index
    }
    func item(at index: Int) -> ChatRowItem { rows[index] }
    func viewNecessary(at index: Int) -> NSView? { offscreenRows.contains(index) ? nil : views[index] }
    func _mouseInside() -> Bool { false }
}
