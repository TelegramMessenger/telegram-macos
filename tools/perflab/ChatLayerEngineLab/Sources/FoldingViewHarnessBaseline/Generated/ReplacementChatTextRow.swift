import Cocoa
import TGUIKit

final class ReplacementChatTextRow: ChatTextRow {
    override func bind(_ next: ChatMessageItem, animated: Bool = false) {
        let previous = item as? ChatMessageItem
        item = next
        updateText(for: next, previous: previous, animated: animated)
    }
    func updateText(for item: ChatMessageItem, previous: ChatMessageItem?, animated: Bool) {
            let isEqual = previous?.textLayout.string == item.textLayout.string
            if item.papercutLayout != nil {
                // The card replaces the text entirely; dropping the view also stops drag-selection and
                // content clicks from starting inside it.
                if let view = self.text {
                    performSubviewRemoval(view, animated: animated)
                    self.text = nil
                }
            } else if isEqual, let view = self.text {
                view.update(layout: item.textLayout, animated: animated)
                view.streamingVisibleHeightChanged = { [weak self] in
                    guard let self, let item = self.item as? ChatMessageItem, let table = item.table else {
                        return
                    }
                    let oldHeight = item.height
                    item.previousBlockWidth = 0
                    _ = item.makeSize(item.width, oldWidth: 0)
                    let newHeight = item.height
                    if oldHeight != newHeight {
                        table.noteHeightOfRow(item.index, true)
                    }
                }
            } else {

                let appendingAnimationView = self.text?.appendingAnimationView

                if let view = self.text {
                    performSubviewRemoval(view, animated: animated)
                }
                let current: FoldingTextView = FoldingTextView(frame: textFrame(item))
                current.update(layout: item.textLayout, animated: false, appendingAnimationView: appendingAnimationView)

                current.revealBlockAtIndex = { [weak self] index in
                    if let item = self?.item as? ChatMessageItem {
                        item.revealBlockAtIndex(index)
                    }
                }
                current.streamingVisibleHeightChanged = { [weak self] in
                    guard let self, let item = self.item as? ChatMessageItem, let table = item.table else {
                        return
                    }
                    let oldHeight = item.height
                    item.previousBlockWidth = 0
                    _ = item.makeSize(item.width, oldWidth: 0)
                    let newHeight = item.height
                    if oldHeight != newHeight {
                        table.noteHeightOfRow(item.index, true)
                    }
                }

                self.text = current
                addSubview(current)

                if animated, !item.textLayout.appendingAnimation {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }

    }

    public override var selectableTextViews: [TextView] {
        var views:[TextView] = super.selectableTextViews + (text?.textViews ?? [])
        if let webpage = webpageContent {
            views += webpage.selectableTextViews
        }
        return views
    }
}
