import Cocoa
import TGUIKit
import SwiftSignalKit
import Localization
#if SHARE
import TelegramThemeShare
import TelegramContextShare
#else
import TelegramTheme
import TelegramContext
import ColorPalette
#endif


public struct GeneralThumbAdditional {
    public let thumb:CGImage
    public let textInset:CGFloat?
    public let thumbInset: CGFloat?
    public init(thumb: CGImage, textInset: CGFloat? = nil, thumbInset: CGFloat? = nil) {
        self.thumb = thumb
        self.textInset = textInset
        self.thumbInset = thumbInset
    }
}


open class GeneralInteractedRowItem: GeneralRowItem {
        
    public private(set) var nameLayout: TextViewLayout
    public private(set) var nameLayoutSelected: TextViewLayout
    public let name:String
    public let nameAttributed: NSAttributedString?
    public var descLayout:TextViewLayout?
    public var balancedDescriptionLayout: Bool = false
    public var showsPopUpIndicator: Bool = false
    public var nameStyle:ControlStyle
    public let thumb:GeneralThumbAdditional?
    public let activeThumb:GeneralThumbAdditional?
    public let switchAppearance: SwitchViewAppearance
    public let autoswitch: Bool
    
    public let badgeNode:BadgeNode?
    
    public let disabledAction:(()->Void)?
    
    public var settingsIconSize: NSSize? {
        guard let presentation = settingsPresentation, thumb != nil else { return nil }
        let size = SettingsRowMetrics.iconSize(presentation: presentation)
        return NSMakeSize(size, size)
    }

    public var settingsTextInset: CGFloat? {
        guard let presentation = settingsPresentation else { return nil }
        return SettingsRowMetrics.textInset(presentation: presentation, hasIcon: thumb != nil)
    }

    public var settingsTitleY: CGFloat {
        let descriptionHeight = descLayout?.layoutSize.height ?? 0
        let contentHeight = nameLayout.layoutSize.height + (descriptionHeight > 0 ? SettingsRowMetrics.subtitleGap + descriptionHeight : 0)
        return floor((height - contentHeight) / 2)
    }

    @discardableResult
    open override func withSettingsLayout(_ presentation: SettingsRowPresentation = .content) -> Self {
        super.withSettingsLayout(presentation)
        guard settingsPresentation != nil else { return self }
        let titleFont: NSFont = descLayout != nil ? .medium(SettingsRowMetrics.titleSize) : .normal(SettingsRowMetrics.titleSize)
        if nameAttributed == nil {
            nameLayout = TextViewLayout(.initialize(string: name, color: enabled ? nameStyle.foregroundColor : theme.colors.grayText, font: titleFont), maximumNumberOfLines: 1)
            nameLayoutSelected = TextViewLayout(.initialize(string: name, color: theme.colors.underSelectedColor, font: presentation == .sidebar ? .semibold(SettingsRowMetrics.titleSize) : titleFont), maximumNumberOfLines: 1)
        }
        if let description = descLayout {
            let text = NSMutableAttributedString(attributedString: description.attributedString)
            text.addAttribute(.font, value: NSFont.normal(SettingsRowMetrics.subtitleSize), range: text.range)
            text.addAttribute(.foregroundColor, value: customTheme?.grayTextColor ?? theme.colors.grayText, range: text.range)
            descLayout = TextViewLayout(text, maximumNumberOfLines: 0)
        }
        _ = makeSize(width, oldWidth: 0)
        return self
    }

    public var nameWidth:CGFloat {
        if settingsPresentation != nil {
            let insets = viewType.innerInset
            var available = blockWidth - insets.left - insets.right - (settingsTextInset ?? 0)
            let context: String?
            var accessoryWidth: CGFloat = 0
            switch type {
            case .switchable:
                accessoryWidth = 46
                context = nil
            case let .nextContext(value):
                accessoryWidth = settingsPresentation == .sidebar ? 0 : 20
                context = value
            case let .context(value), let .contextColored(value, _), let .contextSelector(value, _):
                context = value
            case let .imageContext(_, value):
                accessoryWidth = 30
                context = value
            case let .twoLinesContext(first, second):
                context = first.count > second.count ? first : second
            case .next:
                accessoryWidth = settingsPresentation == .sidebar ? 0 : 20
                context = nil
            case .none:
                context = nil
            case .selectableLeft:
                accessoryWidth = 38
                context = nil
            default:
                accessoryWidth = 30
                context = nil
            }
            if let context, !context.isEmpty {
                let contextWidth = NSAttributedString.initialize(string: context, font: .normal(SettingsRowMetrics.titleSize)).size().width
                accessoryWidth += min(available * 0.4, contextWidth) + SettingsRowMetrics.iconGap
            }
            available -= accessoryWidth
            return max(1, available)
        }
        switch self.viewType {
        case .legacy:
            var width = self.size.width - (inset.left + inset.right)
            switch type {
            case .switchable:
                width -= SwitchView.preferredSize.width + 8
            case .context, .contextColored:
                width -= 40
            case .selectable:
                width -= 40
            case .selectableLeft:
                width -= 40
            default:
                break
            }
            if let thumb = thumb {
                width -= settingsTextInset ?? (thumb.thumb.systemSize.width + 20)
            }
            return width
        case let .modern(_, insets):
            var width = self.blockWidth - (insets.left + insets.right)
            switch type {
            case .switchable:
                width -= SwitchView.preferredSize.width + 8
            case .context, .contextColored:
                width -= 40
            case .selectable:
                width -= 40
            case .selectableLeft:
                width -= 40
            default:
                break
            }
            if let thumb = thumb {
                width -= settingsTextInset ?? (thumb.thumb.systemSize.width + 20)
            }
            return width
        }
    }
    
    private let menuItems:(()->[ContextMenuItem])?
    public let disableBorder: Bool
    public let rightIcon: CGImage?
    public let switchAction:(()->Void)?
    public let descClick:(()->Void)?
    public let afterNameImage: CGImage?
    public let context: (any AccountContextProtocol)?
    public init(_ initialSize:NSSize, stableId:AnyHashable = arc4random(), name:String, nameAttributed: NSAttributedString? = nil, icon: CGImage? = nil, activeIcon: CGImage? = nil, nameStyle:ControlStyle = ControlStyle(font: .normal(.title), foregroundColor: theme.colors.text), description: String? = nil, descTextColor: NSColor = theme.colors.grayText, type:GeneralInteractedType = .none, viewType: GeneralViewType = .legacy, action:@escaping ()->Void = {}, drawCustomSeparator:Bool = true, thumb:GeneralThumbAdditional? = nil, border:BorderType = [], inset: NSEdgeInsets = NSEdgeInsets(left: 20, right: 20), enabled: Bool = true, switchAppearance: SwitchViewAppearance = switchViewAppearance, error: InputDataValueError? = nil, autoswitch: Bool = true, disabledAction: (()-> Void)? = nil, menuItems:(()->[ContextMenuItem])? = nil, customTheme: GeneralRowItem.Theme? = nil, disableBorder: Bool = false, rightIcon: CGImage? = nil, switchAction:(()->Void)? = nil, descClick:(()->Void)? = nil, afterNameImage: CGImage? = nil, iconTextInset: CGFloat? = nil, iconInset: CGFloat? = nil, context: (any AccountContextProtocol)? = nil) {
        
        self.afterNameImage = afterNameImage
        self.name = name
        self.context = context
        self.nameAttributed = nameAttributed
        self.switchAction = switchAction
        self.rightIcon = rightIcon
        self.menuItems = menuItems
        self.disableBorder = disableBorder
        if let description = description {
            descLayout = TextViewLayout(.initialize(string: description, color: descTextColor, font: .normal(.text)), maximumNumberOfLines: 4)
        } else {
            descLayout = nil
        }
        self.nameStyle = nameStyle
        if thumb == nil, let icon = icon {
            self.thumb = GeneralThumbAdditional(thumb: icon, textInset: iconTextInset, thumbInset: iconInset)
        } else {
            self.thumb = thumb
        }
        if case let .badge(text, color) = type {
            self.badgeNode = .init(.initialize(string: text, color: .white, font: .medium(.short)), color)
        } else {
            self.badgeNode = nil
        }
        self.disabledAction = disabledAction
        self.autoswitch = autoswitch
        self.activeThumb = activeIcon != nil ? GeneralThumbAdditional(thumb: activeIcon!, textInset: iconTextInset, thumbInset: iconInset) : self.thumb
        self.switchAppearance = customTheme?.switchAppearance ?? switchAppearance
        self.descClick = descClick
        
        
        let nameAttributed = self.nameAttributed ?? NSAttributedString.initialize(string: name, color: enabled ? nameStyle.foregroundColor : theme.colors.grayText, font: nameStyle.font)
        
        let nameAttributedSelected = self.nameAttributed ?? NSAttributedString.initialize(string: name, color: theme.colors.underSelectedColor, font: nameStyle.font)
        
        nameLayout = .init(nameAttributed, maximumNumberOfLines: 1)
        nameLayoutSelected = .init(nameAttributedSelected, maximumNumberOfLines: 1)

        
        super.init(initialSize, height: 0, stableId:stableId, type:type, viewType: viewType, action:action, drawCustomSeparator:drawCustomSeparator, border:border, inset:inset, enabled: enabled, error: error, customTheme: customTheme)
        _ = makeSize(initialSize.width, oldWidth: 0)
    }
    
    open override var height: CGFloat {
        if let presentation = settingsPresentation {
            return super.height + SettingsRowMetrics.height(presentation: presentation, hasIcon: thumb != nil, titleHeight: nameLayout.layoutSize.height, subtitleHeight: descLayout?.layoutSize.height ?? 0)
        }
        switch viewType {
        case .legacy:
            let height: CGFloat = super.height + 40
            if let descLayout = descLayout {
                return height + descLayout.layoutSize.height
            }
            return height
        case let .modern(_, insets):
            var height: CGFloat = super.height + insets.top + insets.bottom + nameLayout.layoutSize.height
            if case .twoLinesContext = type {
                height += 10
            }
            if let descLayout = self.descLayout {
                if descLayout.lines.count > 1 {
                    return height + descLayout.layoutSize.height - 10
                } else {
                    return height + 8
                }
            }
            return height
        }
    }
    
    
    open override var instantlyResize: Bool {
        return true
    }
    
    open override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
                

        nameLayout.measure(width: max(1, nameWidth))
        nameLayoutSelected.measure(width: max(1, nameWidth))
        descLayout?.measure(width: max(1, nameWidth))
        
        return result
    }
    
    open override func prepare(_ selected: Bool) {
        super.prepare(selected)
    }
    
    open override func viewClass() -> AnyClass {
        return GeneralInteractedRowView.self
    }
    
    
    open override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        
        if let menuItems = self.menuItems {
            return .single(menuItems())
        } else if case let .contextSelector(_, items) = type {
            if !items.isEmpty {
                return .single(items)
            } else {
                return super.menuItems(in: location)
            }
        } else {
            return super.menuItems(in: location)
        }
    }

    open override var accessibilityLabel: String? {
        let title = nameAttributed?.string ?? name
        return title.isEmpty ? nil : title
    }

    open override var accessibilityValue: String? {
        switch type {
        case let .context(value), let .contextColored(value, _), let .nextContext(value), let .imageContext(_, value), let .badge(value, _):
            return value.isEmpty ? nil : value
        case let .twoLinesContext(first, second):
            return [first, second].filter { !$0.isEmpty }.joined(separator: ", ")
        #if !SHARE
        case let .contextSelector(value, _):
            return value.isEmpty ? nil : value
        #endif
        case let .switchable(value), let .selectableLeft(value):
            guard accessibilityHasSeparateSwitch else {
                return nil
            }
            return value ? strings().voiceOverCommonChecked : strings().voiceOverCommonUnchecked
        default:
            return nil
        }
    }

    private var accessibilityHasSeparateSwitch: Bool {
        guard switchAction != nil else {
            return false
        }
        switch type {
        case .switchable, .selectableLeft:
            return true
        default:
            return false
        }
    }

    open override var accessibilityRole: NSAccessibility.Role? {
        if accessibilityHasSeparateSwitch {
            return .button
        }
        switch type {
        case .switchable:
            return .checkBox
        case .selectable, .selectableLeft:
            return .radioButton
        case .loading:
            return .busyIndicator
        default:
            return .button
        }
    }

    open override var accessibilityHelp: String? {
        guard let text = descLayout?.attributedString.string, !text.isEmpty else {
            return nil
        }
        return text
    }

    open override var accessibilityIsEnabled: Bool {
        return enabled
    }

    open override var accessibilityIncludesChildren: Bool {
        return false
    }

    open override func accessibilityPerformPress() -> Bool {
        #if !SHARE
        if case let .contextSelector(_, items) = type, let view = view as? GeneralInteractedRowView {
            return enabled && view.showAccessibilityContextSelector(items)
        }
        #endif
        if let view = view as? GeneralInteractedRowView {
            view.invokeAction(self)
            return true
        }
        if enabled {
            if case let .switchable(value) = type, autoswitch, switchAction == nil {
                type = .switchable(!value)
            }
            action()
        } else {
            disabledAction?()
        }
        return true
    }

    open override var accessibilityToggleState: Bool? {
        if accessibilityHasSeparateSwitch {
            return nil
        }
        switch type {
        case let .switchable(value), let .selectable(value), let .selectableLeft(value):
            return value
        default:
            return nil
        }
    }
}
