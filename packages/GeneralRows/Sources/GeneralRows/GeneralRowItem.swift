import Cocoa
import TGUIKit
#if SHARE
import TelegramThemeShare
import ColorPalette
import TelegramIconsTheme
#else
import TelegramTheme
import ColorPalette
import TelegramIconsTheme
#endif

public enum InputDataValueErrorTarget : Equatable {
    case data
    case files
}

public struct InputDataValueError : Equatable {
    public let description: String
    public let target: InputDataValueErrorTarget
    public init(description: String, target: InputDataValueErrorTarget) {
        self.description = description
        self.target = target
    }
}

public func bestGeneralViewType<T>(_ array:[T], for item: T) -> GeneralViewType where T: AnyObject {
    for _ in array {
        if item === array.first && item === array.last {
            return .singleItem
        } else if item === array.first {
            return .firstItem
        } else if item === array.last {
            return .lastItem
        } else {
            return .innerItem
        }
    }
    return .singleItem
}

public func bestGeneralViewType<T>(_ array:[T], for item: T) -> GeneralViewType where T: Equatable {
    for _ in array {
        if item == array.first && item == array.last {
            return .singleItem
        } else if item == array.first {
            return .firstItem
        } else if item == array.last {
            return .lastItem
        } else {
            return .innerItem
        }
    }
    return .singleItem
}

public func bestGeneralViewType<T>(_ array:[T], for i: Int) -> GeneralViewType  {
    if array.count <= 1 {
        return .singleItem
    } else if i == 0 {
        return .firstItem
    } else if i == array.count - 1 {
        return .lastItem
    } else {
        return .innerItem
    }
}

public func bestGeneralViewTypeAfterFirst<T>(_ array:[T], for i: Int) -> GeneralViewType  {
    if i == 0 {
        if array.count == 1 {
            return .lastItem
        } else {
            return .innerItem
        }
    } else {
        return bestGeneralViewType(array, for: i)
    }
}

public enum GeneralInteractedType : Equatable {
    case none
    case next
    case nextContext(String)
    case imageContext(CGImage, String)
    case nextImage(CGImage)
    case selectable(Bool)
    case selectableLeft(Bool)
    case switchable(Bool)
    case context(String)
    case contextColored(String, NSColor)
    case twoLinesContext(String, String)
    case loading
    case image(CGImage)
    case button(String)
    case search(Bool)
    case colorSelector(NSColor)
    case badge(String, NSColor)
    #if !SHARE
    case contextSelector(String, [ContextMenuItem])
    #endif
}


public final class GeneralViewItemCorners : OptionSet {
    public var rawValue: Int32
    
    public init() {
        self.rawValue = 0
    }
    
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }
    
    public static let topLeft = GeneralViewItemCorners(rawValue: (1 << 0))
    public static let topRight = GeneralViewItemCorners(rawValue: (1 << 1))
    public static let bottomLeft = GeneralViewItemCorners(rawValue: (1 << 2))
    public static let bottomRight = GeneralViewItemCorners(rawValue: (1 << 3))
    
    public static var all: GeneralViewItemCorners {
        return [.topLeft, .topRight, .bottomLeft, .bottomRight]
    }
}

public enum GeneralViewItemPosition : Equatable {
    case first
    case last
    case inner
    case single
    public var corners: GeneralViewItemCorners {
        switch self {
        case .first:
            return [.topLeft, .topRight]
        case .inner:
            return []
        case .last:
            return [.bottomLeft, .bottomRight]
        case .single:
            return [.topLeft, .topRight, .bottomRight, .bottomLeft]
        }
    }
    
    
    
    public var border: Bool {
        guard theme.colors.listBackground != theme.colors.background else {
            return true
        }
        switch self {
        case .first, .inner:
            return true
        default:
            return false
        }
    }
    
}


public enum GeneralViewType : Equatable {
    case legacy
    case modern(position: GeneralViewItemPosition, insets: NSEdgeInsets)

    public var isPlainMode: Bool {
        return theme.colors.listBackground == theme.colors.background || self == .legacy
    }
    public var innerInset: NSEdgeInsets {
        switch self {
        case .legacy:
            return NSEdgeInsetsMake(0, 0, 0, 0)
        case let .modern(_, insets):
            return insets
        }
    }
    
    public var rowBackground: NSColor {
        switch self {
        case .legacy:
            return theme.colors.background
        case .modern:
            return .clear
        }
    }
    
    public var corners:GeneralViewItemCorners {
        switch self {
        case .legacy:
            return []
        case let .modern(position, _):
            return isPlainMode ? [] : position.corners
        }
    }
    public var hasBorder: Bool {
        switch self {
        case .legacy:
            return false
        case let .modern(position, _):
            return position.border
        }
    }
    public var position: GeneralViewItemPosition {
        switch self {
        case .legacy:
            return .single
        case let .modern(position, _):
            return position
        }
    }
    
    public func withUpdatedInsets(_ insets: NSEdgeInsets) -> GeneralViewType {
        switch self {
        case .legacy:
            return self
        case let .modern(position, _):
            return .modern(position: position, insets: insets)
        }
    }
    
    public static var firstItem: GeneralViewType {
        return .modern(position: .first, insets: NSEdgeInsetsMake(12, 14, 12, 14))
    }
    public static var innerItem: GeneralViewType {
        return .modern(position: .inner, insets: NSEdgeInsetsMake(12, 14, 12, 14))
    }
    public static var lastItem: GeneralViewType {
        return .modern(position: .last, insets: NSEdgeInsetsMake(12, 14, 12, 14))
    }
    public static var singleItem: GeneralViewType {
        return .modern(position: .single, insets: NSEdgeInsetsMake(12, 14, 12, 14))
    }
    public static var textTopItem: GeneralViewType {
        return .modern(position: .single, insets: NSEdgeInsetsMake(0, 14, 5, 0))
    }
    public static var textBottomItem: GeneralViewType {
        return .modern(position: .single, insets: NSEdgeInsetsMake(5, 14, 0, 0))
    }
    public static var separator: GeneralViewType {
        return .modern(position: .single, insets: NSEdgeInsetsMake(0, 0, 0, 0))
    }
    public static func plain(_ position: GeneralViewItemPosition) -> GeneralViewType {
        return .modern(position: position, insets: NSEdgeInsetsMake(0, 0, 0, 0))
    }
}

open class GeneralRowItem: TableRowItem {

    
    public struct Theme : Equatable {
        public let backgroundColor: NSColor
        public let grayBackground: NSColor
        public let grayForeground: NSColor
        public let highlightColor: NSColor
        public let borderColor: NSColor
        public let accentColor: NSColor
        public let secondaryColor: NSColor
        public let textColor: NSColor
        public let grayTextColor: NSColor
        public let underSelectedColor: NSColor
        public let accentSelectColor: NSColor
        public let redColor: NSColor
        public let indicatorColor: NSColor
        public let appearance: NSAppearance
        
        public let switchAppearance: SwitchViewAppearance?
        
        public let unselectedImage: CGImage
        public let selectedImage: CGImage
        
        public static func initialize(_ theme: TelegramPresentationTheme, background: NSColor? = nil) -> GeneralRowItem.Theme {
            return .init(backgroundColor: background ?? theme.colors.background,
                         grayBackground: theme.colors.grayBackground,
                         grayForeground: theme.colors.grayForeground,
                         highlightColor: theme.colors.grayHighlight,
                         borderColor: theme.colors.border,
                         accentColor: theme.colors.accent,
                         secondaryColor: theme.colors.grayUI,
                         textColor: theme.colors.text,
                         grayTextColor: theme.colors.grayText,
                         underSelectedColor: theme.colors.underSelectedColor,
                         accentSelectColor: theme.colors.accentSelect,
                         redColor: theme.colors.redUI,
                         indicatorColor: theme.colors.indicatorColor,
                         appearance: theme.colors.appearance,
                         switchAppearance: .init(theme: theme),
                         unselectedImage: theme.icons.chatToggleUnselected,
                         selectedImage: theme.icons.chatToggleSelected)
        }

        public init(backgroundColor: NSColor = theme.colors.background,
             grayBackground: NSColor = theme.colors.grayBackground,
             grayForeground: NSColor = theme.colors.grayForeground,
             highlightColor: NSColor = theme.colors.grayHighlight,
             borderColor: NSColor = theme.colors.border,
             accentColor: NSColor = theme.colors.accent,
             secondaryColor: NSColor = theme.colors.grayText,
             textColor: NSColor = theme.colors.text,
             grayTextColor: NSColor = theme.colors.grayText,
             underSelectedColor: NSColor = theme.colors.underSelectedColor,
             accentSelectColor: NSColor = theme.colors.accentSelect,
             redColor: NSColor = theme.colors.redUI,
             indicatorColor: NSColor = theme.colors.indicatorColor,
             appearance: NSAppearance = theme.colors.appearance,
             switchAppearance: SwitchViewAppearance? = nil,
             unselectedImage: CGImage = theme.icons.chatToggleUnselected,
             selectedImage: CGImage = theme.icons.chatToggleSelected) {
            
            
            self.backgroundColor = backgroundColor
            self.grayBackground = grayBackground
            self.grayForeground = grayForeground
            self.highlightColor = highlightColor
            self.borderColor = borderColor
            self.accentColor = accentColor
            self.secondaryColor = secondaryColor
            self.textColor = textColor
            self.grayTextColor = grayTextColor
            self.underSelectedColor = underSelectedColor
            self.redColor = redColor
            self.accentSelectColor = accentSelectColor
            self.indicatorColor = indicatorColor
            self.appearance = appearance
            self.switchAppearance = switchAppearance
            self.unselectedImage = unselectedImage
            self.selectedImage = selectedImage
        }
    }
    
    public let border:BorderType
    public let enabled: Bool
    open var _height:CGFloat
    open override var height: CGFloat {
        var height = _height
        if let errorLayout = errorLayout {
            height += errorLayout.layoutSize.height
        }
        return height
    }
    
    private let _stableId:AnyHashable
    open override var stableId: AnyHashable {
        return _stableId
    }
        
    open var drawCustomSeparator:Bool = true {
        didSet {
            if drawCustomSeparator != oldValue {
                self.noteHeightOfRow()
            }
        }
    }
    
    private let _inset: NSEdgeInsets
    open var inset:NSEdgeInsets {
        if settingsPresentation == .sidebar {
            return NSEdgeInsets(left: SettingsRowMetrics.sidebarInset, right: SettingsRowMetrics.sidebarInset)
        }
        return _inset
    }
    
    
    open private(set) var action:()->Void
    open var type:GeneralInteractedType
    
    public let backgroundColor: NSColor
    
    public let error: InputDataValueError?
    public let errorLayout: TextViewLayout?
    
    
    open private(set) var viewType: GeneralViewType
    public private(set) var settingsPresentation: SettingsRowPresentation?
    public var usesSettingsCorners: Bool = false

    @discardableResult
    open func withSettingsLayout(_ presentation: SettingsRowPresentation = .content) -> Self {
        if Swift.type(of: self) == GeneralRowItem.self, _height > 0, _height <= 20 {
            _height = SettingsRowMetrics.cardGap
        }
        guard case let .modern(position, insets) = viewType else { return self }
        settingsPresentation = presentation
        let horizontal = presentation == .sidebar ? SettingsRowMetrics.sidebarContentInset : SettingsRowMetrics.contentInset
        viewType = .modern(position: position, insets: NSEdgeInsets(top: insets.top, left: horizontal, bottom: insets.bottom, right: horizontal))
        _ = makeSize(width, oldWidth: 0)
        return self
    }

    
    public func setSettingsInsets(_ insets: NSEdgeInsets) {
        guard settingsPresentation != nil else { return }
        viewType = viewType.withUpdatedInsets(insets)
    }

    public let customTheme: Theme?

    open override var backdorColor: NSColor {
        return customTheme?.backgroundColor ?? super.backdorColor
    }

    private let _ignoreAtInitialization: Bool
    open override var ignoreAtInitialization: Bool {
        return _ignoreAtInitialization
    }
    
    public let containable: Bool
    public let fullSize: Bool
    
    public init(_ initialSize: NSSize, height:CGFloat = 40.0, stableId:AnyHashable = arc4random(),type:GeneralInteractedType = .none, viewType: GeneralViewType = .legacy, action:@escaping()->Void = {}, drawCustomSeparator:Bool = true, border:BorderType = [], inset:NSEdgeInsets = NSEdgeInsets(left: 20, right: 20), enabled: Bool = true, backgroundColor: NSColor? = nil, error: InputDataValueError? = nil, customTheme: Theme? = nil, ignoreAtInitialization: Bool = false, containable: Bool = false, fullSize: Bool = false) {
        self.type = type
        _height = height
        _stableId = stableId
        self.border = border
        self.fullSize = fullSize
        self._inset = inset
        self.containable = containable
        self.customTheme = customTheme
        self._ignoreAtInitialization = ignoreAtInitialization
        if let backgroundColor = backgroundColor {
            self.backgroundColor = backgroundColor
        } else {
            self.backgroundColor = viewType.rowBackground
        }
        
        self.drawCustomSeparator = drawCustomSeparator
        self.action = action
        self.enabled = enabled
        self.error = error
        self.viewType = viewType
        if let error = error {
            errorLayout = TextViewLayout(.initialize(string: error.description, color: theme.colors.redUI, font: .normal(.text)))
        } else {
            errorLayout = nil
        }
        
        super.init(initialSize)
        
        let _ = self.makeSize(initialSize.width)
    }
    
    open override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        errorLayout?.measure(width: width - inset.left - inset.right)
        return success
    }
    
    open var hasBorder: Bool {
        return viewType.hasBorder && (drawCustomSeparator || !containable)
    }
    
    open override var instantlyResize: Bool {
        return true
    }
    
    open override var canBeAnchor: Bool {
        return false
    }
    
    
    open var blockWidth: CGFloat {
        switch self.viewType {
        case .legacy:
            return self.width - self.inset.left - self.inset.right
        case .modern:
            if fullSize {
                return self.width - self.inset.left - self.inset.right
            } else {
                return min(600, self.width - self.inset.left - self.inset.right)
            }
        }
    }
    
    open override var accessibilityIsSpacer: Bool {
        return Swift.type(of: self) == GeneralRowItem.self
    }

    open override func viewClass() -> AnyClass {
        if containable {
            return GeneralContainableRowView.self
        } else {
            return GeneralRowView.self
        }
    }
    
}

extension TableRowItem {
    public func settingsRow(_ presentation: SettingsRowPresentation = .content) -> TableRowItem {
        if let item = self as? GeneralRowItem {
            return item.withSettingsLayout(presentation)
        }
        return self
    }
}
