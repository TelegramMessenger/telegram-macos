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
        super.init(initialSize, height: 42, stableId: stableId, viewType: viewType, action: action, enabled: enabled)
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
    private static let buttonHeight: CGFloat = 24
    private static let buttonPadding: CGFloat = 12
    private static let buttonRadius: CGFloat = 7

    private let button = Control()
    private let titleView = TextView()
    private let sizeView = TextView()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        button.scaleOnClick = true
        button.layer?.cornerRadius = StorageUsageClearButtonView.buttonRadius
        button.layer?.cornerCurve = .continuous
        containerView.addSubview(button)
        containerView.addSubview(sizeView)
        for view in [titleView, sizeView] {
            view.userInteractionEnabled = false
            view.isSelectable = false
            view.isAccessibilityDecorative = true
        }
        button.addSubview(titleView)

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
        guard let item = item as? StorageUsageClearButtonItem else {
            return
        }
        button.centerY(x: containerView.frame.width - button.frame.width - item.viewType.innerInset.right)
        titleView.center()
        sizeView.centerY(x: item.viewType.innerInset.left)
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? StorageUsageClearButtonItem else {
            return
        }

        button.isEnabled = item.enabled
        button.backgroundColor = theme.colors.text.withAlphaComponent(0.12)
        let titleLayout = TextViewLayout(.initialize(string: item.text, color: theme.colors.text, font: .normal(SettingsRowMetrics.titleSize)), maximumNumberOfLines: 1)
        titleLayout.measure(width: max(0, item.blockWidth / 2))
        titleView.update(titleLayout)
        button.setFrameSize(NSMakeSize(titleLayout.layoutSize.width + StorageUsageClearButtonView.buttonPadding * 2, StorageUsageClearButtonView.buttonHeight))

        let sizeLayout = TextViewLayout(.initialize(string: item.sizeText.map { strings().storageUsageClearButtonItemSelected($0) } ?? "", color: theme.colors.grayText, font: .normal(SettingsRowMetrics.titleSize)), maximumNumberOfLines: 1)
        sizeLayout.measure(width: max(0, item.blockWidth - button.frame.width - item.viewType.innerInset.left - item.viewType.innerInset.right - 16))
        sizeView.update(sizeLayout)
        sizeView.isHidden = item.sizeText == nil

        titleView.alphaValue = item.enabled ? 1 : 0.5
        needsLayout = true
    }
}
