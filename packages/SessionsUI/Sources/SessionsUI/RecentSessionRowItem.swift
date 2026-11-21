import Cocoa
import TGUIKit
import TelegramCore
import DateUtils
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import GeneralRows
import InputDataUI
import AlertsUI
import AvatarUI
import LocalAnimations
import ColorPalette
import TelegramIconsTheme
import SwiftSignalKit
import Postbox

public class RecentSessionRowItem: GeneralRowItem {
    
    public let session:RecentAccountSession
    
    public let headerLayout:TextViewLayout
    public let descLayout:TextViewLayout
    public let dateLayout:TextViewLayout
    public let handler:()->Void
    public let icon: (CGImage?, LocalAnimatedSticker?, NSColor?, [String]?)
    
    public init(_ initialSize: NSSize, session:RecentAccountSession, deviceModel: String? = nil, stableId:AnyHashable, viewType: GeneralViewType, icon: (CGImage?, LocalAnimatedSticker?, NSColor?, [String]?), handler: @escaping()->Void) {
        self.session = session
        self.handler = handler
        self.icon = icon
        headerLayout = TextViewLayout(.initialize(string: deviceModel ?? session.deviceModel, color: theme.colors.text, font: .normal(SettingsRowMetrics.titleSize)), maximumNumberOfLines: 1)
        
        let attr = NSMutableAttributedString()
        
                
        _ = attr.append(string: (session.appName + " " + session.appVersion.prefixWithDots(30) + ", " + session.platform + " " + session.systemVersion).trimmed, color: theme.colors.grayText, font: .normal(SettingsRowMetrics.subtitleSize))
        
        _ = attr.append(string: "\n")
        
        _ = attr.append(string: (session.ip + " " + session.country).trimmed, color: theme.colors.grayText, font: .normal(SettingsRowMetrics.subtitleSize))
        
        descLayout = TextViewLayout(attr, maximumNumberOfLines: 0, lineSpacing: SettingsRowMetrics.subtitleGap)
    
        dateLayout = TextViewLayout(.initialize(string: session.isCurrent ? strings().peerStatusOnline : DateUtils.string(forMessageListDate: session.activityDate), color: session.isCurrent ? theme.colors.accent : theme.colors.grayText, font: .normal(SettingsRowMetrics.titleSize)))
        
        super.init(initialSize, stableId: stableId, viewType: viewType.withUpdatedInsets(NSEdgeInsets(top: SettingsRowMetrics.verticalInset, left: SettingsRowMetrics.contentInset, bottom: SettingsRowMetrics.verticalInset, right: SettingsRowMetrics.contentInset)))
        
        _ = makeSize(initialSize.width, oldWidth: initialSize.width)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        dateLayout.measure(width: .greatestFiniteMagnitude)
        let textInset = icon.0 != nil ? SettingsRowMetrics.deviceIconSize + SettingsRowMetrics.iconGap : 0
        let textWidth = blockWidth - viewType.innerInset.left - viewType.innerInset.right - textInset
        headerLayout.measure(width: max(1, textWidth - dateLayout.layoutSize.width - SettingsRowMetrics.iconGap))
        descLayout.measure(width: max(1, textWidth))
        return success
    }
    
    public override var height: CGFloat {
        return max(54, headerLayout.layoutSize.height + SettingsRowMetrics.subtitleGap + descLayout.layoutSize.height + viewType.innerInset.top + viewType.innerInset.bottom)
    }
    
    public override func viewClass() -> AnyClass {
        return RecentSessionRowView.self
    }

    public override var accessibilityLabel: String? {
        return headerLayout.attributedString.string
    }

    public override var accessibilityValue: String? {
        return "\(descLayout.attributedString.string.replacingOccurrences(of: "\n", with: ", ")), \(dateLayout.attributedString.string)"
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func accessibilityPerformPress() -> Bool {
        handler()
        return true
    }
}

public class RecentSessionRowView : GeneralContainableRowView {
    private let headerTextView = TextView()
    private let descTextView = TextView()
    private let dateTextView = TextView()
    private let iconView: ImageView = ImageView()
    private let scrambleAnimation = ScrambleTextAnimation()
    private var scrambleLayout: TextViewLayout?

    var titleView: NSView {
        return headerTextView
    }
    public required init(frame frameRect: NSRect) {
          
        super.init(frame: frameRect)
        self.addSubview(headerTextView)
        self.addSubview(descTextView)
        self.addSubview(dateTextView)
        addSubview(iconView)
        iconView.isAccessibilityDecorative = true
        
        headerTextView.userInteractionEnabled = false
        headerTextView.isSelectable = false
            
        dateTextView.userInteractionEnabled = false
        dateTextView.isSelectable = false
        
        descTextView.userInteractionEnabled = false
        descTextView.isSelectable = false


        containerView.set(handler: { [weak self] _ in
            if let item = self?.item as? RecentSessionRowItem {
                item.handler()
            }
        }, for: .Click)
    }
    
    public override func updateColors() {
        super.updateColors()
        headerTextView.backgroundColor = backdorColor
        descTextView.backgroundColor = backdorColor
        dateTextView.backgroundColor = backdorColor
        containerView.backgroundColor = backdorColor
        if let item = item as? RecentSessionRowItem {
            self.background = item.viewType.rowBackground
        }
    }
    
    public override var backdorColor: NSColor {
        return theme.colors.background
    }
    
    
    public override func set(item: TableRowItem, animated: Bool) {
        let previousTitle = (self.item as? RecentSessionRowItem)?.headerLayout.attributedString.string
        super.set(item: item)
 
        
        
        if let item = item as? RecentSessionRowItem {
            let title = item.headerLayout.attributedString.string
            if animated, let previousTitle = previousTitle, previousTitle != title, !title.isEmpty {
                let width = item.headerLayout.constrainedWidth
                let attributes = item.headerLayout.attributedString.attributes(at: 0, effectiveRange: nil)
                scrambleAnimation.start(from: scrambleLayout?.attributedString.string ?? previousTitle, to: title, update: { [weak self] text in
                    let layout = TextViewLayout(NSAttributedString(string: text, attributes: attributes), maximumNumberOfLines: 1)
                    layout.measure(width: width)
                    self?.scrambleLayout = text == title ? nil : layout
                    self?.needsLayout = true
                })
            } else if previousTitle != title {
                scrambleAnimation.cancel()
                scrambleLayout = nil
            }
            self.iconView.image = item.icon.0
            self.iconView.setFrameSize(SettingsRowMetrics.deviceIconSize, SettingsRowMetrics.deviceIconSize)
        }
        
        self.needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        guard let item = item as? RecentSessionRowItem  else {
            return
        }
        let insets = item.viewType.innerInset
        self.iconView.setFrameOrigin(NSMakePoint(insets.left, insets.top))
        let left: CGFloat = (item.icon.0 != nil ? SettingsRowMetrics.deviceIconSize + SettingsRowMetrics.iconGap : 0)
        self.headerTextView.update(scrambleLayout ?? item.headerLayout, origin: NSMakePoint(left + insets.left, insets.top))
        self.descTextView.update(item.descLayout, origin: NSMakePoint(left + insets.left, headerTextView.frame.maxY + SettingsRowMetrics.subtitleGap))
        self.dateTextView.update(item.dateLayout, origin: NSMakePoint(self.containerView.frame.width - insets.right - item.dateLayout.layoutSize.width, insets.top))

    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
