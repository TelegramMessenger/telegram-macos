import Foundation
import Cocoa
import TGUIKit
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
import TelegramCore
import Postbox
import AvatarUI

public final class StorageUsageClearButtonItem : GeneralRowItem {
    fileprivate let text: String
    fileprivate let sizeText: String?
    public init(_ initialSize: NSSize, stableId: AnyHashable, text: String, sizeText: String? = nil, enabled: Bool, viewType: GeneralViewType, action:@escaping()->Void) {
        self.text = text
        self.sizeText = sizeText
        super.init(initialSize, height: 40 + viewType.innerInset.top + viewType.innerInset.bottom, stableId: stableId, viewType: viewType, action: action, enabled: enabled)
    }
    
    public override var accessibilityLabel: String? {
        return [text, sizeText].compactMap { $0 }.joined(separator: " ")
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }

    public override var accessibilityIsEnabled: Bool {
        return enabled
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func accessibilityPerformPress() -> Bool {
        guard enabled else {
            return false
        }
        action()
        return true
    }

    public override func viewClass() -> AnyClass {
        return StorageUsageClearButtonView.self
    }
}


private final class StorageUsageClearButtonView: GeneralContainableRowView {
    private let button = ImageButton()
    private let titleView = TextView()
    private let sizeView = TextView()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        button.scaleOnClick = true
        button.autohighlight = false
        button.disableActions()
        button.setGlassEffect(tintColor: theme.colors.accent)
        button.set(background: .clear, for: .Normal)
        button.set(background: .clear, for: .Highlight)
        addSubview(button)
        for view in [titleView, sizeView] {
            view.userInteractionEnabled = false
            view.isSelectable = false
            view.isAccessibilityDecorative = true
            button.addSubview(view)
        }
        
        button.set(handler: { [weak self] _ in
            if let item = self?.item as? GeneralRowItem, item.enabled {
                item.action()
            }
        }, for: .Click)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        button.center()
        let spacing: CGFloat = sizeView.isHidden ? 0 : 4
        let width = titleView.frame.width + (sizeView.isHidden ? 0 : sizeView.frame.width) + spacing
        titleView.setFrameOrigin(NSMakePoint(floorToScreenPixels((button.frame.width - width) / 2), floorToScreenPixels((button.frame.height - titleView.frame.height) / 2)))
        sizeView.setFrameOrigin(NSMakePoint(titleView.frame.maxX + spacing, floorToScreenPixels((button.frame.height - sizeView.frame.height) / 2)))
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? StorageUsageClearButtonItem else {
            return
        }
        
        button.glassTintColor = theme.colors.accent
        button.isEnabled = item.enabled
        button.setFrameSize(NSMakeSize(item.blockWidth - item.viewType.innerInset.left - item.viewType.innerInset.right, 40))
        let foreground = theme.colors.accent.lightness > 0.8 ? NSColor.black : NSColor.white
        let titleLayout = TextViewLayout(.initialize(string: item.text, color: foreground, font: .medium(.title)), maximumNumberOfLines: 1)
        let sizeLayout = TextViewLayout(.initialize(string: item.sizeText ?? "", color: foreground.withAlphaComponent(0.6), font: .medium(.title)), maximumNumberOfLines: 1)
        sizeLayout.measure(width: max(0, button.frame.width - 32))
        titleLayout.measure(width: max(0, button.frame.width - 32 - (item.sizeText == nil ? 0 : sizeLayout.layoutSize.width + 4)))
        titleView.update(titleLayout)
        sizeView.update(sizeLayout)
        sizeView.isHidden = item.sizeText == nil
        titleView.alphaValue = item.enabled ? 1 : 0.5
        sizeView.alphaValue = item.enabled ? 1 : 0.5
        needsLayout = true
    }
}
