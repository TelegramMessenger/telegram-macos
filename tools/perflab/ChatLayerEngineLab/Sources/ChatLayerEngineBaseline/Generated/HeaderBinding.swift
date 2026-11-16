import Cocoa
import TGUIKit

final class HeaderBindingItem {
    let forwardHeader: TextViewLayout?
    let frame: NSRect
    init(_ layout: TextViewLayout?, frame: NSRect) { forwardHeader = layout; self.frame = frame }
}

final class NativeHeaderBindingRow: View {
    let rowView: View
    var forwardHeader: TextView?
    required init(frame: NSRect) {
        rowView = View(frame: frame.size.bounds)
        super.init(frame: frame)
        addSubview(rowView)
    }
    required init?(coder: NSCoder) { fatalError() }
    func forwardHeaderRect(_ item: HeaderBindingItem) -> NSRect { item.frame }
    func fillForwardHeader(_ item:HeaderBindingItem, animated: Bool) -> Void {
        if let forwardHeader = item.forwardHeader {
            let current: TextView
            if let view = self.forwardHeader {
                current = view
            } else {
                current = TextView(frame: forwardHeaderRect(item))
                current.userInteractionEnabled = false
                current.isSelectable = false
                self.forwardHeader = current
                rowView.addSubview(current)
            }
            current.update(forwardHeader)
        } else if let forwardHeader {
           performSubviewRemoval(forwardHeader, animated: animated)
            self.forwardHeader = nil
        }
    }
}

extension NativeHeaderBindingRow {
    func layoutHeader(_ item: HeaderBindingItem, transition: ContainedViewLayoutTransition) {
        if let view = forwardHeader {
            transition.updateFrame(view: view, frame: forwardHeaderRect(item))
        }
    }
}

final class LayerHeaderBindingRow: View {
    let rowView: View
    
    required init(frame: NSRect) {
        rowView = ChatLayerRowView(frame: frame.size.bounds)
        super.init(frame: frame)
        addSubview(rowView)
    }
    required init?(coder: NSCoder) { fatalError() }
    func forwardHeaderRect(_ item: HeaderBindingItem) -> NSRect { item.frame }
    func fillForwardHeader(_ item: HeaderBindingItem, animated: Bool) {
        (rowView as? ChatLayerRowView)?.updateForwardHeader(item.forwardHeader, frame: forwardHeaderRect(item), animated: animated)
    }
}

extension LayerHeaderBindingRow {
    func layoutHeader(_ item: HeaderBindingItem, transition: ContainedViewLayoutTransition) {
        (rowView as? ChatLayerRowView)?.layoutForwardHeader(frame: forwardHeaderRect(item), transition: transition)
    }
}
