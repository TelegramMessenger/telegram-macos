import Cocoa
import TGUIKit
import TelegramCore
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import FoundationUtils
import AlertsUI
import InAppSettings
import LocalAnimations
import SwiftSignalKit
import Postbox
import AvatarUI

public final class StorageUsageCategoryItem : GeneralRowItem {
    public enum Category : Equatable {
        case basic(hasSub: Bool, revealed: Bool)
        case sub
    }
    public enum Action : Equatable {
        case selection
        case toggle
    }
    fileprivate let nameLayout: TextViewLayout
    fileprivate let subLayout: TextViewLayout
    fileprivate let category: StorageUsageCategory
    fileprivate let selected: Bool
    fileprivate let itemCategory: Category
    fileprivate let color: NSColor
    fileprivate let _action: (Action)->Void
    public init(_ initialSize: NSSize, stableId: AnyHashable, category: StorageUsageCategory, name: NSAttributedString, subString: NSAttributedString, color: NSColor, selected: Bool, itemCategory: Category, viewType: GeneralViewType, action:@escaping(Action)->Void) {
        
        self._action = action
        self.nameLayout = .init(name)
        self.subLayout = .init(subString)
        self.category = category
        self.itemCategory = itemCategory
        self.color = color
        self.selected = selected

        super.init(initialSize, height: 42, stableId: stableId, viewType: viewType)
        
        subLayout.measure(width: .greatestFiniteMagnitude)
        _ = makeSize(initialSize.width)
    }
    
    
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        var nameLayoutWidth: CGFloat = blockWidth - viewType.innerInset.left - 18 - viewType.innerInset.left - viewType.innerInset.left - subLayout.layoutSize.width - viewType.innerInset.left
        
        switch itemCategory {
        case let .basic(hasSub, _):
            nameLayoutWidth -= (hasSub ? 10 : 0)
        case .sub:
            nameLayoutWidth -= (viewType.innerInset.left - 18 - viewType.innerInset.left)
        }
        
        nameLayout.measure(width: nameLayoutWidth)
        
        
        return true
    }
    
    public override var accessibilityLabel: String? {
        return nameLayout.attributedString.string
    }

    public override var accessibilityValue: String? {
        return subLayout.attributedString.string
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .checkBox
    }

    public override var accessibilityToggleState: Bool? {
        return selected
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func accessibilityPerformPress() -> Bool {
        _action(.selection)
        return true
    }

    public override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        guard case let .basic(true, revealed) = itemCategory else {
            return nil
        }
        return [NSAccessibilityCustomAction(name: revealed ? strings().voiceOverCommonCollapse : strings().voiceOverCommonExpand, handler: { [weak self] in
            self?._action(.toggle)
            return true
        })]
    }

    public override func viewClass() -> AnyClass {
        return StorageUsageCategoryView.self
    }
}

private final class StorageUsageCategoryView : GeneralContainableRowView {
    private let nameTextView = TextView()
    private let subTextView = TextView()
    private var subImageView: ImageView?
    private let selectionView: SelectingControl = SelectingControl(unselectedImage: SettingsCheckbox.unselected, selectedImage: SettingsCheckbox.selected())
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        addSubview(selectionView)
        addSubview(nameTextView)
        addSubview(subTextView)
        
        selectionView.userInteractionEnabled = true
        
        nameTextView.userInteractionEnabled = false
        nameTextView.isSelectable = false
        subTextView.isSelectable = false
        subTextView.userInteractionEnabled = false
        
        
        containerView.setStateChangeHandler { [weak self] in
            self?.updateColors()
        }
        
        containerView.set(handler: { [weak self] _ in
            self?.invokeAction()
        }, for: .Click)
        
        selectionView.set(handler: { [weak self] _ in
            self?.invokeAction(toggle: false)
        }, for: .Click)
    }
    
    private func invokeAction(toggle: Bool = true) {
        guard let item = item as? StorageUsageCategoryItem else {
            return
        }
        if case .basic(hasSub: true, _) = item.itemCategory, toggle {
            item._action(.toggle)
        } else {
            item._action(.selection)
        }
    }
    
    
    public override var additionBorderInset: CGFloat {
        
        guard let item = item as? StorageUsageCategoryItem else {
            return super.additionBorderInset
        }
        switch item.itemCategory {
        case .sub:
            return 18 + item.viewType.innerInset.left
        default:
            return super.additionBorderInset
        }
    }
    
    public override func updateColors() {
        super.updateColors()
        
        let highlighted = isSelect ? self.backdorColor : theme.colors.grayHighlight
        containerView.set(background: self.backdorColor, for: .Normal)
        containerView.set(background: highlighted, for: .Highlight)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        
        guard let item = item as? StorageUsageCategoryItem else {
            return
        }
        selectionView.centerY(x: item.viewType.innerInset.left + additionBorderInset)

        nameTextView.centerY(x: selectionView.frame.maxX + item.viewType.innerInset.left)

        var addition: CGFloat = 0
        switch item.itemCategory {
        case let .basic(hasSub, _):
            if hasSub {
                addition = 20
            }
        default:
            break
        }
        subTextView.centerY(x: containerView.frame.width - subTextView.frame.width - item.viewType.innerInset.right - addition)
        
        if let view = subImageView {
            view.centerY(x: containerView.frame.width - view.frame.width - item.viewType.innerInset.right)
        }
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? StorageUsageCategoryItem else {
            return
        }
        
        nameTextView.update(item.nameLayout)
        subTextView.update(item.subLayout)
        
        selectionView.update(unselectedImage: SettingsCheckbox.unselected, selectedImage: SettingsCheckbox.selected(item.color), selected: item.selected, animated: animated)
        
        let concealed_img: CGImage = theme.icons.general_chevron_down
        let revealed_img: CGImage = theme.icons.general_chevron_up

        
        switch item.itemCategory {
        case .basic(true, let revealed):
            let current: ImageView
            if let view = self.subImageView {
                current = view
            } else {
                current = ImageView()
                current.isAccessibilityDecorative = true
                self.subImageView = current
                addSubview(current)
            }
            current.animates = animated
            current.image = revealed ? revealed_img : concealed_img
            current.sizeToFit()
        default:
            if let view = self.subImageView {
                performSubviewRemoval(view, animated: animated)
                self.subImageView = nil
            }
        }
        
        needsLayout = true
    }
    
}
