import ColorPalette
import GeneralRows
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import Cocoa
import TGUIKit
import TelegramCore

import SwiftSignalKit
import SecureIdUtils

public enum InputDataEntryId : Hashable {
    case desc(Int32)
    case input(InputDataIdentifier)
    case general(InputDataIdentifier)
    case selector(InputDataIdentifier)
    case dataSelector(InputDataIdentifier)
    case dateSelector(InputDataIdentifier)
    case custom(InputDataIdentifier)
    case search(InputDataIdentifier)
    case loading
    case sectionId(Int32)
    
    public var identifier: InputDataIdentifier? {
        switch self {
        case let .input(identifier), let .selector(identifier), let .dataSelector(identifier), let .dateSelector(identifier), let .general(identifier), let .custom(identifier), let .search(identifier):
            return identifier
        default:
            return nil
        }
    }
}


public enum InputDataInputMode : Equatable {
    case plain
    case secure
}



public typealias InputDataEquatable = UIEquatable

public struct InputDataComparableIndex : Comparable {
    public let data: Any
    public let compare:(Any, Any)->Bool
    public let equatable:(Any, Any)->Bool

    public init(data: Any, compare: @escaping (Any, Any) -> Bool, equatable: @escaping (Any, Any) -> Bool) {
        self.data = data
        self.compare = compare
        self.equatable = equatable
    }

    public static func <(lhs: InputDataComparableIndex, rhs: InputDataComparableIndex) -> Bool {
        return lhs.compare(lhs.data, rhs.data)
    }
    public static func ==(lhs: InputDataComparableIndex, rhs: InputDataComparableIndex) -> Bool {
        return lhs.equatable(lhs.data, rhs.data)
    }
}

public struct InputDataInputPlaceholder : Equatable {
    public let placeholder: String?
    public let drawBorderAfterPlaceholder: Bool
    public let icon: CGImage?
    public let action: (()-> Void)?
    public let hasLimitationText: Bool
    public let insets: NSEdgeInsets
    public init(_ placeholder: String? = nil, icon: CGImage? = nil, drawBorderAfterPlaceholder: Bool = false, hasLimitationText: Bool = false, insets: NSEdgeInsets = NSEdgeInsets(), action: (()-> Void)? = nil) {
        self.drawBorderAfterPlaceholder = drawBorderAfterPlaceholder
        self.hasLimitationText = hasLimitationText
        self.placeholder = placeholder
        self.icon = icon
        self.action = action
        self.insets = insets
    }
    
    public static func ==(lhs: InputDataInputPlaceholder, rhs: InputDataInputPlaceholder) -> Bool {
        return lhs.placeholder == rhs.placeholder && lhs.icon === rhs.icon && lhs.drawBorderAfterPlaceholder == rhs.drawBorderAfterPlaceholder && lhs.insets == rhs.insets
    }
}


public final class InputDataGeneralData : Equatable {
    
    

    
    public let name: String
    public let nameAttributed: NSAttributedString?
    public let color: NSColor
    public let icon: CGImage?
    public let type: GeneralInteractedType
    public let viewType: GeneralViewType
    public let description: String?
    public let action: (()->Void)?
    public let disabledAction:(()->Void)?
    public let switchAction: (()->Void)?
    public let descClick:(()->Void)?
    public let enabled: Bool
    public let justUpdate: Int64?
    public let menuItems:(()->[ContextMenuItem])?
    public let theme: GeneralRowItem.Theme?
    public let disableBorder: Bool
    public let descTextColor: NSColor?
    public let afterNameImage: CGImage?
    public let autoswitch: Bool
    public let iconTextInset:CGFloat?
    public let iconInset: CGFloat?
    public let leftInset: CGFloat?
    public init(name: String, color: NSColor, icon: CGImage? = nil, type: GeneralInteractedType = .none, viewType: GeneralViewType = .legacy, enabled: Bool = true, description: String? = nil, descTextColor: NSColor? = nil, justUpdate: Int64? = nil, action: (()->Void)? = nil, switchAction: (()->Void)? = nil, disabledAction: (()->Void)? = nil, menuItems:(()->[ContextMenuItem])? = nil, descClick: (()->Void)? = nil, theme: GeneralRowItem.Theme? = nil, disableBorder: Bool = false, nameAttributed: NSAttributedString? = nil, afterNameImage: CGImage? = nil, autoswitch: Bool = true, iconTextInset: CGFloat? = nil, iconInset: CGFloat? = nil, leftInset: CGFloat? = nil) {
        self.name = name
        self.color = color
        self.icon = icon
        self.type = type
        self.viewType = viewType
        self.description = description
        self.action = action
        self.descClick = descClick
        self.switchAction = switchAction
        self.enabled = enabled
        self.justUpdate = justUpdate
        self.disabledAction = disabledAction
        self.menuItems = menuItems
        self.theme = theme
        self.disableBorder = disableBorder
        self.nameAttributed = nameAttributed
        self.descTextColor = descTextColor
        self.afterNameImage = afterNameImage
        self.autoswitch = autoswitch
        self.iconTextInset = iconTextInset
        self.iconInset = iconInset
        self.leftInset = leftInset
    }
    
    public static func ==(lhs: InputDataGeneralData, rhs: InputDataGeneralData) -> Bool {
        return lhs.name == rhs.name && lhs.icon === rhs.icon && lhs.color.hexString == rhs.color.hexString && lhs.type == rhs.type && lhs.description == rhs.description && lhs.viewType == rhs.viewType && lhs.enabled == rhs.enabled && lhs.justUpdate == rhs.justUpdate && lhs.theme == rhs.theme && lhs.disableBorder == rhs.disableBorder && lhs.nameAttributed == rhs.nameAttributed && lhs.descTextColor == rhs.descTextColor && lhs.afterNameImage == rhs.afterNameImage && lhs.autoswitch == rhs.autoswitch && lhs.iconTextInset == rhs.iconTextInset && lhs.iconInset == rhs.iconInset && lhs.leftInset == rhs.leftInset
    }
}

public final class InputDataGeneralTextData : Equatable {
    public let color: NSColor
    public let detectBold: Bool
    public let viewType: GeneralViewType
    public let rightItem: InputDataGeneralTextRightData
    public let fontSize: CGFloat?
    public let contextMenu:(()->[ContextMenuItem])?
    public let clickable: Bool
    public let clickableCornerRadius: CGFloat
    public let inset: NSEdgeInsets
    public let centerViewAlignment: Bool
    public let alignment: NSTextAlignment
    public let linkColor: NSColor
    public let context: (any AccountContextProtocol)?
    public let linkExecutor: TextViewInteractions
    public let isTextSelectable: Bool
    public init(color: NSColor = theme.colors.listGrayText, detectBold: Bool = true, isTextSelectable: Bool = false, viewType: GeneralViewType = .legacy, rightItem: InputDataGeneralTextRightData = InputDataGeneralTextRightData(isLoading: false, text: nil), fontSize: CGFloat? = nil, contextMenu:(()->[ContextMenuItem])? = nil, clickable: Bool = false, clickableCornerRadius: CGFloat = .cornerRadius, inset: NSEdgeInsets = .init(left: 20, right: 20, top:4, bottom:2), centerViewAlignment: Bool = false, alignment: NSTextAlignment = .left, linkColor: NSColor = theme.colors.link, context: (any AccountContextProtocol)? = nil, linkExecutor: TextViewInteractions = GeneralRowsHooks.shared.linkExecutor()) {
        self.color = color
        self.detectBold = detectBold
        self.viewType = viewType
        self.rightItem = rightItem
        self.inset = inset
        self.fontSize = fontSize
        self.contextMenu = contextMenu
        self.clickable = clickable
        self.clickableCornerRadius = clickableCornerRadius
        self.alignment = alignment
        self.centerViewAlignment = centerViewAlignment
        self.linkColor = linkColor
        self.context = context
        self.linkExecutor = linkExecutor
        self.isTextSelectable = isTextSelectable
    }
    public static func ==(lhs: InputDataGeneralTextData, rhs: InputDataGeneralTextData) -> Bool {
        return lhs.color == rhs.color && lhs.detectBold == rhs.detectBold && lhs.viewType == rhs.viewType && lhs.rightItem == rhs.rightItem && lhs.fontSize == rhs.fontSize && lhs.clickable == rhs.clickable && lhs.clickableCornerRadius == rhs.clickableCornerRadius && lhs.inset == rhs.inset && lhs.centerViewAlignment == rhs.centerViewAlignment && lhs.alignment == rhs.alignment && lhs.linkColor == rhs.linkColor && lhs.isTextSelectable == rhs.isTextSelectable
    }
}

public final class InputDataRowData : Equatable {
    public let viewType: GeneralViewType
    public let rightItem: InputDataRightItem?
    public let defaultText: String?
    public let pasteFilter:((String)->(Bool, String))?
    public let maxBlockWidth: CGFloat?
    public let canMakeTransformations: Bool
    public let customTheme: GeneralRowItem.Theme?
    public init(viewType: GeneralViewType = .legacy, rightItem: InputDataRightItem? = nil, defaultText: String? = nil, maxBlockWidth: CGFloat? = nil, canMakeTransformations: Bool = false, pasteFilter:((String)->(Bool, String))? = nil, customTheme: GeneralRowItem.Theme? = nil) {
        self.viewType = viewType
        self.rightItem = rightItem
        self.defaultText = defaultText
        self.pasteFilter = pasteFilter
        self.maxBlockWidth = maxBlockWidth
        self.canMakeTransformations = canMakeTransformations
        self.customTheme = customTheme
    }
    public static func ==(lhs: InputDataRowData, rhs: InputDataRowData) -> Bool {
        return lhs.viewType == rhs.viewType && lhs.rightItem == rhs.rightItem && lhs.defaultText == rhs.defaultText && lhs.maxBlockWidth == rhs.maxBlockWidth && lhs.canMakeTransformations == rhs.canMakeTransformations && lhs.customTheme == rhs.customTheme
    }
}

public enum InputDataSectionType : Equatable {
    case normal
    case legacy
    case custom(CGFloat)
    case customModern(CGFloat)
    public var height: CGFloat {
        switch self {
        case .normal:
            return 20
        case .legacy:
            return 20
        case let .custom(height):
            return height
        case let .customModern(height):
            return height
        }
    }
}

public enum InputDataEntry : Identifiable, Comparable {
    case desc(sectionId: Int32, index: Int32, text: GeneralRowTextType, data: InputDataGeneralTextData)
    case input(sectionId: Int32, index: Int32, value: InputDataValue, error: InputDataValueError?, identifier: InputDataIdentifier, mode: InputDataInputMode, data: InputDataRowData, placeholder: InputDataInputPlaceholder?, inputPlaceholder: String, filter:(String)->String, limit: Int32)
    case general(sectionId: Int32, index: Int32, value: InputDataValue, error: InputDataValueError?, identifier: InputDataIdentifier, data: InputDataGeneralData)
    case dateSelector(sectionId: Int32, index: Int32, value: InputDataValue, error: InputDataValueError?, identifier: InputDataIdentifier, placeholder: String)
    case selector(sectionId: Int32, index: Int32, value: InputDataValue, error: InputDataValueError?, identifier: InputDataIdentifier, placeholder: String, viewType: GeneralViewType, values:[ValuesSelectorValue<InputDataValue>])
    case dataSelector(sectionId: Int32, index: Int32, value: InputDataValue, error: InputDataValueError?, identifier: InputDataIdentifier, placeholder: String, description: String?, icon: CGImage?, action:()->Void)
    case custom(sectionId: Int32, index: Int32, value: InputDataValue, identifier: InputDataIdentifier, equatable: InputDataEquatable?, comparable: InputDataComparableIndex?, item:(NSSize, InputDataEntryId)->TableRowItem)
    case search(sectionId: Int32, index: Int32, value: InputDataValue, identifier: InputDataIdentifier, update:(SearchState)->Void)
    case loading
    case sectionId(Int32, type: InputDataSectionType)
    
    public var comparable: InputDataComparableIndex? {
        switch self {
        case let .custom(_, _, _, _, _, comparable, _):
            return comparable
        default:
            return nil
        }
    }
    
    public var stableId: InputDataEntryId {
        switch self {
        case let .desc(_, index, _, _):
            return .desc(index)
        case let .input(_, _, _, _, identifier, _, _, _, _, _, _):
            return .input(identifier)
        case let .general(_, _, _, _, identifier, _):
            return .general(identifier)
        case let .selector(_, _, _, _, identifier, _, _, _):
            return .selector(identifier)
        case let .dataSelector(_, _, _, _, identifier, _, _, _, _):
            return .dataSelector(identifier)
        case let .dateSelector(_, _, _, _, identifier, _):
            return .dateSelector(identifier)
        case let .custom(_, _, _, identifier, _, _, _):
            return .custom(identifier)
        case let .search(_, _, _, identifier, _):
            return .custom(identifier)
        case let .sectionId(index, _):
            return .sectionId(index)
        case .loading:
            return .loading
        }
    }
    
    public var stableIndex: Int32 {
        switch self {
        case let .desc(_, index, _, _):
            return index
        case let .input(_, index, _, _, _, _, _, _, _, _, _):
            return index
        case let .general(_, index, _, _, _, _):
            return index
        case let .selector(_, index, _, _, _, _, _, _):
            return index
        case let .dateSelector(_, index, _, _, _, _):
            return index
        case let .dataSelector(_, index, _, _, _, _, _, _, _):
            return index
        case let .custom(_, index, _, _, _, _, _):
            return index
        case let .search(_, index, _, _, _):
            return index
        case .loading:
            return 0
        case .sectionId:
            fatalError()
        }
    }
    
    public var sectionIndex: Int32 {
        switch self {
        case let .desc(index, _, _, _):
            return index
        case let .input(index, _, _, _, _, _, _, _, _, _, _):
            return index
        case let .selector(index, _, _, _, _, _, _, _):
            return index
        case let .general(index, _, _, _, _, _):
            return index
        case let .dateSelector(index, _, _, _, _, _):
            return index
        case let .dataSelector(index, _, _, _, _, _, _, _, _):
            return index
        case let .custom(index, _, _, _, _, _, _):
            return index
        case let .search(index, _, _, _, _):
            return index
        case .loading:
            return 0
        case .sectionId:
            fatalError()
        }
    }
    
    public var index: Int32 {
        switch self {
        case let .sectionId(sectionId, _):
            return (sectionId + 1) * 100000 - sectionId
        default:
            return (sectionIndex * 100000) + stableIndex
        }
    }
    
    public func item(arguments: InputDataArguments, initialSize: NSSize) -> TableRowItem {
        switch self {
        case let .sectionId(_, type):
            let viewType: GeneralViewType
            switch type {
            case .legacy, .custom:
                viewType = .legacy
            default:
                viewType = .separator
            }
            return GeneralRowItem(initialSize, height: type.height, stableId: stableId, viewType: viewType)
        case let .desc(_, _, text, data):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, detectBold: data.detectBold, textColor: data.color, linkColor: data.linkColor, alignment: data.alignment, inset: data.inset, centerViewAlignment: data.centerViewAlignment, isTextSelectable: data.isTextSelectable, viewType: data.viewType, rightItem: data.rightItem, fontSize: data.fontSize, contextMenu: data.contextMenu, clickable: data.clickable, clickableCornerRadius: data.clickableCornerRadius, context: data.context, linkExecutor: data.linkExecutor)
        case let .custom(_, _, _, _, _, _, item):
            return item(initialSize, stableId)
        case let .selector(_, _, value, error, _, placeholder, viewType, values):
            return InputDataDataSelectorRowItem(initialSize, stableId: stableId, value: value, error: error, placeholder: placeholder, viewType: viewType, updated: arguments.dataUpdated, values: values)
        case let .dataSelector(_, _, _, error, _, placeholder, description, icon, action):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: placeholder, icon: icon, nameStyle: ControlStyle(font: .normal(.title), foregroundColor: theme.colors.accent), description: description, type: .none, action: action, error: error)
        case let .general(_, _, value, error, identifier, data):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: data.name, nameAttributed: data.nameAttributed, icon: data.icon, nameStyle: ControlStyle(font: .normal(.title), foregroundColor: data.color), description: data.description, descTextColor: data.descTextColor ?? data.theme?.grayTextColor ?? theme.colors.text, type: data.type, viewType: data.viewType, action: {
                data.action != nil ? data.action?() : arguments.select((identifier, value))
            }, inset: .init(left: data.leftInset ?? 20, right: 20), enabled: data.enabled, switchAppearance: data.theme?.switchAppearance ?? switchViewAppearance, error: error, autoswitch: data.autoswitch, disabledAction: data.disabledAction ?? {}, menuItems: data.menuItems, customTheme: data.theme, disableBorder: data.disableBorder, switchAction: data.switchAction, descClick: data.descClick, afterNameImage: data.afterNameImage, iconTextInset: data.iconTextInset, iconInset: data.iconInset)
        case let .dateSelector(_, _, value, error, _, placeholder):
            return InputDataDateRowItem(initialSize, stableId: stableId, value: value, error: error, updated: arguments.dataUpdated, placeholder: placeholder)
        case let .input(_, _, value, error, _, mode, data, placeholder, inputPlaceholder, filter, limit: limit):
            return InputDataRowItem(initialSize, stableId: stableId, mode: mode, error: error, viewType: data.viewType, currentText: value.stringValue ?? "", currentAttributedText: value.attributedString, placeholder: placeholder, inputPlaceholder: inputPlaceholder, defaultText: data.defaultText, rightItem: data.rightItem, canMakeTransformations: data.canMakeTransformations, maxBlockWidth: data.maxBlockWidth, filter: filter, updated: { _ in
                arguments.dataUpdated()
            }, pasteFilter: data.pasteFilter, limit: limit, customTheme: data.customTheme)
        case .loading:
            return InputDataUIHooks.shared.makeLoadingRow(initialSize, AnyHashable(stableId))
        case let .search(_, _, _, _, update):
            return SearchRowItem(initialSize, stableId: stableId, searchInteractions: SearchInteractions({ state, _ in
                update(state)
            }, { state in
                update(state)
            }), inset: NSEdgeInsets(left: 10,right: 10))
        }
    }
}

public func <(lhs: InputDataEntry, rhs: InputDataEntry) -> Bool {
    if let lhsComparable = lhs.comparable, let rhsComparable = rhs.comparable {
        return lhsComparable < rhsComparable
    }
    return lhs.index < rhs.index
}

public func ==(lhs: InputDataEntry, rhs: InputDataEntry) -> Bool {
    switch lhs {
    case let .desc(_, index, text, data):
        if case .desc(_, index, text, data) = rhs {
            return true
        } else {
            return false
        }
    case let .input(_, index, lhsValue, lhsError, identifier, mode, data, placeholder, inputPlaceholder, _, limit):
        if case .input(_, index, let rhsValue, let rhsError, identifier, mode, data, placeholder, inputPlaceholder, _, limit) = rhs {
            return lhsValue == rhsValue && lhsError == rhsError
        } else {
            return false
        }
    case let .general(_, index, lhsValue, lhsError, identifier, data):
        if case .general(_, index, let rhsValue, let rhsError, identifier, data) = rhs {
            return lhsValue == rhsValue && lhsError == rhsError
        } else {
            return false
        }
    case let .selector(_, index, lhsValue, lhsError, identifier, placeholder, viewType, lhsValues):
        if case .selector(_, index, let rhsValue, let rhsError, identifier, placeholder, viewType, let rhsValues) = rhs {
            return lhsValues == rhsValues && lhsValue == rhsValue && lhsError == rhsError
        } else {
            return false
        }
    case let .dateSelector(_, index, lhsValue, lhsError, identifier, placeholder):
        if case .dateSelector(_, index, let rhsValue, let rhsError, identifier, placeholder) = rhs {
            return lhsValue == rhsValue && lhsError == rhsError
        } else {
            return false
        }
    case let .dataSelector(_, index, lhsValue, lhsError, identifier, placeholder, description, lhsIcon, _):
        if case .dataSelector(_, index, let rhsValue, let rhsError, identifier, placeholder, description, let rhsIcon, _) = rhs {
            return lhsValue == rhsValue && lhsError == rhsError && lhsIcon == rhsIcon
        } else {
            return false
        }
    case let .custom(_, _, value, identifier, lhsEquatable, comparable, _):
        if case .custom(_, _, value, identifier, let rhsEquatable, comparable, _) = rhs {
            return lhsEquatable == rhsEquatable
        } else {
            return false
        }
    case let .search(_, index, value, identifier, _):
        if case .search(_, index, value, identifier, _) = rhs {
            return true
        } else {
            return false
        }
    case let .sectionId(_, type):
        if case .sectionId(_, type) = rhs {
            return true
        } else {
            return false
        }
    case .loading:
        if case .loading = rhs {
            return true
        } else {
            return false
        }
    }
}

public let InputDataEmptyIdentifier = InputDataIdentifier("")

open class InputDataIdentifier : Hashable {
    public let identifier: String
    public init(_ identifier: String) {
        self.identifier = identifier
    }
    open func hash(into hasher: inout Hasher) {
        hasher.combine(identifier)
    }
    open func isEqual(to: InputDataIdentifier) -> Bool {
        if self.identifier == to.identifier {
            return true
        } else {
            return false
        }
    }
}

public func ==(lhs: InputDataIdentifier, rhs: InputDataIdentifier) -> Bool {
    return lhs.isEqual(to: rhs)
}

public enum InputDataValue : Equatable {
    case string(String?)
    case attributedString(NSAttributedString?)
    case date(Int32?, Int32?, Int32?)
    case gender(SecureIdGender?)
    case secureIdDocument(SecureIdVerificationDocument)
    case none
    public var stringValue: String? {
        switch self {
        case let .string(value):
            return value
        case let .attributedString(value):
            return value?.string
        default:
            return nil
        }
    }
    
    public var attributedString:NSAttributedString? {
        switch self {
        case let .attributedString(value):
            return value
        default:
            return nil
        }
    }
    
    public var secureIdDocument: SecureIdVerificationDocument? {
        switch self {
        case let .secureIdDocument(document):
            return document
        default:
            return nil
        }
    }
    
    public var gender: SecureIdGender? {
        switch self {
        case let .gender(gender):
            return gender
        default:
            return nil
        }
    }
}

public func ==(lhs: InputDataValue, rhs: InputDataValue) -> Bool {
    switch lhs {
    case let .string(lhsValue):
        if case let .string(rhsValue) = rhs {
            return lhsValue == rhsValue
        } else {
            return false
        }
    case let .attributedString(lhsValue):
        if case let .attributedString(rhsValue) = rhs {
            return lhsValue == rhsValue
        } else {
            return false
        }
    case let .gender(lhsValue):
        if case let .gender(rhsValue) = rhs {
            return lhsValue == rhsValue
        } else {
            return false
        }
    case let .secureIdDocument(lhsValue):
        if case let .secureIdDocument(rhsValue) = rhs {
            return lhsValue.isEqual(to: rhsValue)
        } else {
            return false
        }
    case let .date(lhsDay, lhsMonth, lhsYear):
        if case let .date(rhsDay, rhsMonth,rhsYear) = rhs {
            return lhsDay == rhsDay && lhsMonth == rhsMonth && lhsYear == rhsYear
        } else {
            return false
        }
    case .none:
        if case .none = rhs {
            return true
        } else {
            return false
        }
    }
}

public enum InputDataValidationFailAction {
    case shake
    case shakeWithData(Any)
}

public enum InputDataValidationBehaviour {
    case navigationBack
    case navigationBackWithPushAnimation
    case custom(()->Void)
}

public enum InputDataFailResult {
    case alert(String)
    case doSomething(next: (@escaping(InputDataValidation)->Void) -> Void)
    case textAfter(String, InputDataIdentifier)
    case fields([InputDataIdentifier: InputDataValidationFailAction])
    case none
}

public enum InputDataValidation {
    case success(InputDataValidationBehaviour)
    case fail(InputDataFailResult)
    case none
    public var isSuccess: Bool {
        switch self {
        case .success:
            return true
        case .fail, .none:
            return false
            
        }
    }
}




public enum InputDoneValue : Equatable {
    case enabled(String)
    case disabled(String)
    case invisible
    case loading
}
