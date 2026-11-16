import Cocoa
import TGUIKit

final class BadgeBindingItem {
    let adminBadge: TextViewLayout
    let adminBadgeAuthorId: Int?
    var actions = 0
    init(_ layout: TextViewLayout, authorId: Int?) { adminBadge = layout; adminBadgeAuthorId = authorId }
    func adminBadgeInteraction(_ view: NSView) { actions += 1 }
}

final class NativeBadgeBindingRow: View {
    var adminBadge: TextView?
    var rowView: View { self }
    func adminBadgePoint(_ item: BadgeBindingItem) -> NSPoint { .zero }
    func bind(_ item: BadgeBindingItem) {
        let adminBadge = item.adminBadge
                    if self.adminBadge == nil {
                        self.adminBadge = TextView(frame: CGRect(origin: adminBadgePoint(item), size: adminBadge.layoutSize))
                        self.adminBadge?.isSelectable = false
                        rowView.addSubview(self.adminBadge!)
                    }
                    self.adminBadge?.update(adminBadge)
                    if item.adminBadgeAuthorId != nil {
                        self.adminBadge?.scaleOnClick = true
                        self.adminBadge?.userInteractionEnabled = true
                        self.adminBadge?.setSingle(handler: { [weak item] control in
                            item?.adminBadgeInteraction(control)
                        }, for: .Click)
                    }

    }
}

final class LayerBadgeBindingRow: View {
    var adminBadge: TextView?
    var rowView: View { self }
    func adminBadgePoint(_ item: BadgeBindingItem) -> NSPoint { .zero }
    func bind(_ item: BadgeBindingItem) {
        let adminBadge = item.adminBadge
                    if self.adminBadge == nil {
                        self.adminBadge = TextView(frame: CGRect(origin: adminBadgePoint(item), size: adminBadge.layoutSize))
                        self.adminBadge?.isSelectable = false
                        rowView.addSubview(self.adminBadge!)
                    }
                    self.adminBadge?.update(adminBadge)
                    self.adminBadge?.removeAllHandlers()
                    if item.adminBadgeAuthorId == nil { self.adminBadge?.controlState = .Normal }
                    self.adminBadge?.scaleOnClick = item.adminBadgeAuthorId != nil
                    self.adminBadge?.userInteractionEnabled = item.adminBadgeAuthorId != nil
                    if item.adminBadgeAuthorId != nil {
                        self.adminBadge?.set(handler: { [weak item] control in
                            item?.adminBadgeInteraction(control)
                        }, for: .Click)
                    }

    }
}
