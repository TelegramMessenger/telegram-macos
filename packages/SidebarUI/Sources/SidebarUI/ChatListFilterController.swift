import Cocoa
import LocalAnimations
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import GeneralRows
import InputDataUI

import SwiftSignalKit
import Postbox
import TelegramCore
import InAppSettings
import TGUIKit
import InputView


private enum FolderColorEntryId: Hashable {
    case color(String)
}

private enum  FolderColorEntry: Comparable, Identifiable {
    case color(Int, NSColor, Bool)

    var stableId:  FolderColorEntryId {
        switch self {
            case let .color(_, color, _):
            return .color(color.hexString)
        }
    }

    static func ==(lhs:  FolderColorEntry, rhs: FolderColorEntry) -> Bool {
        switch lhs {
            case let .color(index, color, selected):
                if case .color(index, color, selected) = rhs {
                    return true
                } else {
                    return false
                }
        }
    }

    static func <(lhs: FolderColorEntry, rhs: FolderColorEntry) -> Bool {
        switch lhs {
            case let .color(lhsIndex, _, _):
                switch rhs {
                    case let .color(rhsIndex, _, _):
                        return lhsIndex < rhsIndex
            }
        }
    }

    func item(initialSize: NSSize, context: any AccountContextProtocol, environment: SidebarUIEnvironment, action: @escaping (NSColor) -> Void) -> FolderColorIconItem {
        switch self {
            case let .color(_, color, selected):
            return FolderColorIconItem(initialSize: initialSize, stableId: self.stableId, context: context, environment: environment, color: color, selected: selected, action: action)
        }
    }
}



private class FolderColorIconItem: TableRowItem {
    let color: NSColor
    let selected: Bool
    let action: (NSColor) -> Void
    let context: any AccountContextProtocol
    let environment: SidebarUIEnvironment
    public init(initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, environment: SidebarUIEnvironment, color: NSColor, selected: Bool, action: @escaping (NSColor) -> Void) {
        self.color = color
        self.environment = environment
        self.selected = selected
        self.action = action
        self.context = context
        super.init(initialSize, stableId: stableId)
    }

    override var height: CGFloat {
        return 55
    }
    override var width: CGFloat {
        return 55
    }

    override func viewClass() -> AnyClass {
        return FolderColorIconView.self
    }

    override var accessibilityLabel: String? {
        return strings().voiceOverCommonColor
    }

    override var accessibilityValue: String? {
        return selected ? strings().voiceOverCommonSelected : nil
    }
}

private final class FolderColorIconView : ColorSwatchView {

    private var item: TableRowItem?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        control.set(handler: { [weak self] _ in
            guard let item = self?.item as? FolderColorIconItem else {
                return
            }
            item.action(item.color)
        }, for: .Click)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func set(item: TableRowItem, animated: Bool) {

        self.item = item

        guard let item = item as? FolderColorIconItem else {
            return
        }

        update(fill: item.environment.colorImage(item.color, ring: false), ring: item.environment.colorImage(item.color, ring: true), selected: item.selected, animated: animated)
        control.setAccessibilityLabel(item.accessibilityLabel)
        control.setAccessibilityValue(item.accessibilityValue)
    }
}



private final class FolderColorRowItem : GeneralRowItem {
    fileprivate let colors: [NSColor]
    fileprivate let selected: NSColor?
    fileprivate let selectAction:(NSColor)->Void
    fileprivate let context: any AccountContextProtocol
    fileprivate let environment: SidebarUIEnvironment

    let itemSize: NSSize = NSMakeSize(45, 45)
    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, environment: SidebarUIEnvironment, colors: [NSColor], selected: NSColor?, viewType: GeneralViewType, action: @escaping(NSColor)->Void) {
        self.environment = environment
        self.colors = colors
        self.context = context
        self.selected = selected
        self.selectAction = action
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    var frames:[CGRect] = []

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)

        frames.removeAll()

        let perRow = Int(floor((blockWidth - 10) / itemSize.width))

        var point: CGPoint = NSMakePoint(5, 5)
        for i in 1 ... colors.count {
            frames.append(CGRect(origin: point, size: itemSize))
            if i % perRow == 0 {
                point.x = 5
                point.y += itemSize.height
            } else {
                point.x += itemSize.width
            }
        }

        return true
    }

    override var instantlyResize: Bool {
        return true
    }

    override var height: CGFloat {
        _ = floor((blockWidth - 10) / itemSize.width)

        return frames[frames.count - 1].maxY + 5
    }

    override func viewClass() -> AnyClass {
        return PeerNamesRowView.self
    }

    override var accessibilityLabel: String? {
        return strings().voiceOverCommonColor
    }
}

private final class PeerNamesRowView : GeneralContainableRowView {
    let tableView: View
    required init(frame frameRect: NSRect) {
        tableView = View(frame: frameRect)
        super.init(frame: frameRect)
        addSubview(tableView)
    }

    override func layout() {
        super.layout()
        tableView.frame = containerView.bounds
        guard let item = item as? FolderColorRowItem else {
            return
        }

        for (i, subview) in tableView.subviews.enumerated() {
            subview.frame = item.frames[i]
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var previous: [FolderColorEntry] = []

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? FolderColorRowItem else {
            return
        }

        var entries: [FolderColorEntry] = []

        var index: Int = 0
        for color in item.colors {
            entries.append(.color(index, color, color == item.selected))
            index += 1
        }

        let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: previous, rightList: entries)


        for rdx in deleteIndices.reversed() {
            tableView.subviews[rdx].removeFromSuperview()
        }


        for (idx, entry, _) in indicesAndItems {
            let view = FolderColorIconView(frame: item.itemSize.bounds)
            let item = entry.item(initialSize: bounds.size, context: item.context, environment: item.environment, action: item.selectAction)
            view.set(item: item, animated: animated)
            tableView.subviews.insert(view, at: idx)
        }
        for (idx, entry, _) in updateIndices {
            let item = item
            let updatedItem = entry.item(initialSize: bounds.size, context: item.context, environment: item.environment, action: item.selectAction)
            (tableView.subviews[idx] as? FolderColorIconView)?.set(item: updatedItem, animated: animated)
        }

        self.previous = entries

        needsLayout = true

    }

}



public func shareFolderPremiumLimits(context: any AccountContextProtocol, environment: SidebarUIEnvironment, current: ChatListFilter, links: [ExportedChatFolderLink]?) -> Signal<(limitFilters: Bool, limitInvites: Bool), NoError> {
    return chatListFilterPreferences(engine: context.engine) |> take(1) |> map { data in
        return sidebarSharingLimits(filters: data.list, current: current, links: links, isPremium: context.isPremium, limits: environment.limits)
    }
}



private struct FolderSelection {
    let filter: ChatListFilter
    let environment: SidebarUIEnvironment
    var data: ChatListFilterData? { filter.data }

    var additionIncludeItems: [Peer] {
        var items:[Peer] = []
        if data?.isShared == false {
            items.append(environment.categoryPeer(.contacts))
            items.append(environment.categoryPeer(.nonContacts))
            items.append(environment.categoryPeer(.groups))
            items.append(environment.categoryPeer(.channels))
            items.append(environment.categoryPeer(.bots))
        }
        return items
    }
    var includeCustom: [PeerId] {
        var items: [PeerId] = []
        if let data = data {
            if data.categories.contains(.contacts) {
                items.append(environment.categoryPeer(.contacts).id)
            }
            if data.categories.contains(.nonContacts) {
                items.append(environment.categoryPeer(.nonContacts).id)
            }
            if data.categories.contains(.groups) {
                items.append(environment.categoryPeer(.groups).id)
            }
            if data.categories.contains(.channels) {
                items.append(environment.categoryPeer(.channels).id)
            }
            if data.categories.contains(.bots) {
                items.append(environment.categoryPeer(.bots).id)
            }
        }
        return items
    }

    var excludeAllPeers: [PeerId] {
        var items:[PeerId] = []
        if let data = data {
            if data.excludeMuted {
                items.append(environment.categoryPeer(.excludeMuted).id)
            }
            if data.excludeRead {
                items.append(environment.categoryPeer(.excludeRead).id)
            }
            if data.excludeArchived {
                items.append(environment.categoryPeer(.excludeArchived).id)
            }
            items.append(contentsOf: data.excludePeers)
        }
        return items
    }

    var selectedIncludeItems: [Peer] {
        var items:[Peer] = []

        switch filter {
        case .allChats:
            break
        case let .filter(_, _, _, data):
            if data.categories.contains(.contacts) {
                items.append(environment.categoryPeer(.contacts))
            }
            if data.categories.contains(.nonContacts) {
                items.append(environment.categoryPeer(.nonContacts))
            }
            if data.categories.contains(.groups) {
                items.append(environment.categoryPeer(.groups))
            }
            if data.categories.contains(.channels) {
                items.append(environment.categoryPeer(.channels))
            }
            if data.categories.contains(.bots) {
                items.append(environment.categoryPeer(.bots))
            }
        }

        return items
    }
    var additionExcludeItems: [Peer] {
        var items:[Peer] = []
        items.append(environment.categoryPeer(.excludeMuted))
        items.append(environment.categoryPeer(.excludeRead))
        items.append(environment.categoryPeer(.excludeArchived))
        return items
    }


    var selectedExcludeItems: [Peer] {
        var items:[Peer] = []

        switch filter {
        case .allChats:
            break
        case let .filter(_, _, _, data):
            if data.excludeMuted {
                items.append(environment.categoryPeer(.excludeMuted))
            }
            if data.excludeRead {
                items.append(environment.categoryPeer(.excludeRead))
            }
            if data.excludeArchived {
                items.append(environment.categoryPeer(.excludeArchived))
            }
        }

        return items
    }
}

//extension ChatListFiltersState {
//    mutating func withAddedFilter(_ filter: ChatListFilter, onlyReplace: Bool = false) {
//        if let index = filters.firstIndex(where: {$0.sidebarId == filter.sidebarId}) {
//            filters[index] = filter
//        } else if !onlyReplace {
//            filters.append(filter)
//        }
//    }
//
//    mutating func withRemovedFilter(_ filter: ChatListFilter) {
//        filters.removeAll(where: {$0.sidebarId == filter.sidebarId })
//    }
//
//    mutating func withMoveFilter(_ from: Int, _ to: Int)  {
//        filters.insert(filters.remove(at: from), at: to)
//    }
//}

private struct State: Equatable {
    var filter: ChatListFilter
    var initialFilter: ChatListFilter
    var showAllInclude: Bool
    var showAllExclude: Bool
    var isNew: Bool
    var changedName: Bool
    var inviteLinks: [ExportedChatFolderLink]?
    var creatingLink: Bool
    var linkSaving: String?
    var inputState: Updated_ChatTextInputState
    var nameAnimation: Bool
    let inputStateEquals: (Updated_ChatTextInputState, Updated_ChatTextInputState) -> Bool
    init(filter: ChatListFilter, isNew: Bool, showAllInclude: Bool, showAllExclude: Bool, changedName: Bool, inviteLinks: [ExportedChatFolderLink]?, creatingLink: Bool, linkSaving: String?, inputState: Updated_ChatTextInputState, nameAnimation: Bool, inputStateEquals: @escaping (Updated_ChatTextInputState, Updated_ChatTextInputState) -> Bool) {
        self.filter = filter
        self.initialFilter = filter
        self.isNew = isNew
        self.showAllInclude = showAllInclude
        self.showAllExclude = showAllExclude
        self.changedName = changedName
        self.inviteLinks = inviteLinks
        self.creatingLink = creatingLink
        self.linkSaving = linkSaving
        self.inputState = inputState
        self.nameAnimation = nameAnimation
        self.inputStateEquals = inputStateEquals
    }

    static func == (lhs: State, rhs: State) -> Bool {
        return lhs.filter == rhs.filter && lhs.initialFilter == rhs.initialFilter && lhs.showAllInclude == rhs.showAllInclude && lhs.showAllExclude == rhs.showAllExclude && lhs.isNew == rhs.isNew && lhs.changedName == rhs.changedName && lhs.inviteLinks == rhs.inviteLinks && lhs.creatingLink == rhs.creatingLink && lhs.linkSaving == rhs.linkSaving && lhs.nameAnimation == rhs.nameAnimation && lhs.inputStateEquals(lhs.inputState, rhs.inputState)
    }

    mutating func withUpdatedFilter(_ f:(ChatListFilter)->ChatListFilter) {
        self.filter = f(self.filter)
    }
}

private final class ChatListPresetArguments {
    let environment: SidebarUIEnvironment
    let context: any AccountContextProtocol
    let toggleOption:(ChatListFilterPeerCategories)->Void
    let toggleExcludeMuted:(Bool)->Void
    let toggleExcludeRead:(Bool)->Void
    let addInclude:()->Void
    let addExclude:()->Void
    let removeIncluded:(PeerId)->Void
    let removeExcluded:(PeerId)->Void
    let openInfo:(PeerId)->Void
    let showAllInclude: ()->Void
    let showAllExclude: ()->Void
    let updateIcon:(FolderIcon)->Void
    let shareFolder:(ExportedChatFolderLink?)->Void
    let copy:(String)->Void
    let deleteLink:(ExportedChatFolderLink)->Void
    let toggleColor:(Int32?)->Void
    let updateState:(Updated_ChatTextInputState)->Void
    let toggleNameAnimation:()->Void
    init(context: any AccountContextProtocol, environment: SidebarUIEnvironment, toggleOption:@escaping(ChatListFilterPeerCategories)->Void, addInclude: @escaping()->Void, addExclude: @escaping()->Void, removeIncluded: @escaping(PeerId)->Void, removeExcluded: @escaping(PeerId)->Void, openInfo: @escaping(PeerId)->Void, toggleExcludeMuted:@escaping(Bool)->Void, toggleExcludeRead: @escaping(Bool)->Void, showAllInclude:@escaping()->Void, showAllExclude:@escaping()->Void, updateIcon: @escaping(FolderIcon)->Void, shareFolder:@escaping(ExportedChatFolderLink?)->Void, copy: @escaping(String)->Void, deleteLink:@escaping(ExportedChatFolderLink)->Void, toggleColor:@escaping(Int32?)->Void, updateState:@escaping(Updated_ChatTextInputState)->Void, toggleNameAnimation:@escaping()->Void) {
        self.environment = environment
        self.context = context
        self.toggleOption = toggleOption
        self.toggleExcludeMuted = toggleExcludeMuted
        self.toggleExcludeRead = toggleExcludeRead
        self.addInclude = addInclude
        self.addExclude = addExclude
        self.removeIncluded = removeIncluded
        self.removeExcluded = removeExcluded
        self.openInfo = openInfo
        self.showAllInclude = showAllInclude
        self.showAllExclude = showAllExclude
        self.updateIcon = updateIcon
        self.shareFolder = shareFolder
        self.copy = copy
        self.deleteLink = deleteLink
        self.toggleColor = toggleColor
        self.updateState = updateState
        self.toggleNameAnimation = toggleNameAnimation
    }
}

private let _id_name_input = InputDataIdentifier("_id_name_input")
private let _id_private_chats = InputDataIdentifier("_id_private_chats")

private let _id_public_groups = InputDataIdentifier("_id_public_groups")
private let _id_private_groups = InputDataIdentifier("_id_private_groups")
private let _id_secret_chats = InputDataIdentifier("_id_secret_chats")


private let _id_channels = InputDataIdentifier("_id_channels")
private let _id_bots = InputDataIdentifier("_id_bots")
private let _id_exclude_muted = InputDataIdentifier("_id_exclude_muted")
private let _id_exclude_read = InputDataIdentifier("_id_exclude_read")

private let _id_add_include = InputDataIdentifier("_id_add_include")
private let _id_add_exclude = InputDataIdentifier("_id_add_exclude")

private let _id_show_all_include = InputDataIdentifier("_id_show_all_include")
private let _id_show_all_exclude = InputDataIdentifier("_id_show_all_exclude")
private let _id_header = InputDataIdentifier("_id_header")
private let _id_loading_links = InputDataIdentifier("_id_loading_links")
private let _id_share_invite = InputDataIdentifier("_id_share_invite")

private let _id_color = InputDataIdentifier("_id_color")
private let _id_reset_color = InputDataIdentifier("_id_color")
private func _id_invite_link(_ string: String) -> InputDataIdentifier {
    return InputDataIdentifier("_id_invite_link\(string)")
}

private func _id_include(_ peerId: PeerId) -> InputDataIdentifier {
    return InputDataIdentifier("_id_include_\(peerId)")
}
private func _id_exclude(_ peerId: PeerId) -> InputDataIdentifier {
    return InputDataIdentifier("_id_exclude_\(peerId)")
}
private func chatListFilterEntries(state: State, includePeers: [Peer], excludePeers: [Peer], arguments: ChatListPresetArguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []


    let maximumPeers = arguments.context.isPremium ? arguments.environment.limits.dialog_filters_chats_limit_premium : arguments.environment.limits.dialog_filters_chats_limit_default

    var includePeers:[Peer] = includePeers
    var excludePeers:[Peer] = excludePeers

    switch state.filter {
    case .allChats:
        break
    case let .filter(_, _, _, data):
        if data.categories.contains(.groups) {
            includePeers.insert(arguments.environment.categoryPeer(.groups), at: 0)
        }
        if data.categories.contains(.channels) {
            includePeers.insert(arguments.environment.categoryPeer(.channels), at: 0)
        }
        if data.categories.contains(.contacts) {
            includePeers.insert(arguments.environment.categoryPeer(.contacts), at: 0)
        }
        if data.categories.contains(.nonContacts) {
            includePeers.insert(arguments.environment.categoryPeer(.nonContacts), at: 0)
        }
        if data.categories.contains(.bots) {
            includePeers.insert(arguments.environment.categoryPeer(.bots), at: 0)
        }


        if data.excludeMuted {
            excludePeers.insert(arguments.environment.categoryPeer(.excludeMuted), at: 0)
        }
        if data.excludeRead {
            excludePeers.insert(arguments.environment.categoryPeer(.excludeRead), at: 0)
        }
        if data.excludeArchived {
            excludePeers.insert(arguments.environment.categoryPeer(.excludeArchived), at: 0)
        }

        var sectionId:Int32 = 0
        var index: Int32 = 0


        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1


        if state.isNew {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: nil, comparable: nil, item: { initialSize, stableId in
                let attributedString = NSMutableAttributedString()
                return ChatListFiltersHeaderItem(initialSize, context: arguments.context, environment: arguments.environment, stableId: stableId, sticker: .newFolder, text: attributedString)
            }))

            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
        }

        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().chatListFilterNameHeader), data: .init(color: theme.colors.listGrayText, detectBold: true, viewType: .textTopItem, rightItem: .init(isLoading: false, text: .initialize(string: state.nameAnimation ? strings().chatListFolderDisableAnimations : strings().chatListFolderEnableAnimations, color: theme.colors.accent, font: .normal(.text)), action: arguments.toggleNameAnimation))))
        index += 1

        //InputTextDataRowItem

        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_name_input, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return arguments.environment.makeNameRow(initialSize, stableId: stableId, state: state.inputState, rightItem: InputDataRightItem.action(FolderIcon(state.filter).icon(for: .settings, image: arguments.environment.folderImage), .custom{ item, control in
                showPopover(for: control, with: ChatListFilterFolderIconController(arguments.context, environment: arguments.environment, select: arguments.updateIcon), edge: .minX, inset: NSMakePoint(0,-45))
            }), updateState: arguments.updateState, playAnimation: state.nameAnimation)
        }))

        index += 1

//        entries.append(.sectionId(sectionId, type: .normal))
//        sectionId += 1
//
//        entries.append(.input(sectionId: sectionId, index: index, value: .string(title), error: nil, identifier: _id_name_input, mode: .plain, data: .init(viewType: .singleItem, rightItem: InputDataRightItem.action(FolderIcon(state.filter).icon(for: .settings, image: arguments.environment.folderImage), .custom{ item, control in
//            showPopover(for: control, with: ChatListFilterFolderIconController(arguments.context, environment: arguments.environment, select: arguments.updateIcon), edge: .minX, inset: NSMakePoint(0,-45))
//        })), placeholder: nil, inputPlaceholder: strings().chatListFilterNamePlaceholder, filter: { $0 }, limit: 12))
//        index += 0

        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1

        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().chatListFilterIncludeHeader), data: .init(color: theme.colors.listGrayText, detectBold: true, viewType: .textTopItem)))
        index += 1

        let hasAddInclude = data.includePeers.peers.count < maximumPeers || data.categories != .all

        if hasAddInclude  {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_add_include, equatable: InputDataEquatable(state), comparable: nil, item: { initialSize, stableId in
                return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().chatListFilterIncludeAddChat, nameStyle: ControlStyle(font: .normal(.title), foregroundColor: theme.colors.accent), type: .none, viewType: includePeers.isEmpty ? .singleItem : .firstItem, action: arguments.addInclude, thumb: GeneralThumbAdditional(thumb: theme.icons.chat_filter_add, textInset: 46, thumbInset: 4), context: arguments.context)
            }))
            index += 0
        }



        var fake:[Int] = []
        fake.append(0)
        for (i, _) in includePeers.enumerated() {
            if hasAddInclude {
                fake.append(i + 1)
            } else {
                fake.append(i)
            }
        }

        for (i, peer) in includePeers.enumerated() {

            struct E : Equatable {
                let viewType: GeneralViewType
                let peer: SidebarPeerEquatable
            }

            if i > 10, !state.showAllInclude {
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_show_all_include, equatable: InputDataEquatable(includePeers.count), comparable: nil, item: { initialSize, stableId in
                    return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().chatListFilterShowMoreOther(includePeers.count - i), nameStyle: ControlStyle(font: .normal(.title), foregroundColor: theme.colors.accent), type: .none, viewType: .lastItem, action: arguments.showAllInclude, thumb: GeneralThumbAdditional(thumb: theme.icons.chatSearchUp, textInset: 52, thumbInset: 4))
                }))
                index += 0
                break
            } else {
                var viewType = bestGeneralViewType(fake, for: hasAddInclude ? i + 1 : i)

                if excludePeers.count > 10, i == includePeers.count - 1, state.showAllInclude {
                    viewType = .innerItem
                }


                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_include(peer.id), equatable: InputDataEquatable(E(viewType: viewType, peer: SidebarPeerEquatable(peer))), comparable: nil, item: { initialSize, stableId in
                    return arguments.environment.makePeerRow(initialSize, peer: peer, stableId: stableId, viewType: viewType, action: {
                        arguments.openInfo(peer.id)
                    }, remove: {
                        arguments.removeIncluded(peer.id)
                    }, contextMenuItems: {
                        return .single([ContextMenuItem(strings().chatListFilterIncludeRemoveChat, handler: {
                            arguments.removeIncluded(peer.id)
                        }, itemMode: .destruct, itemImage: arguments.environment.menuImage(.menu_delete))])
                    })
                }))
                index += 0
            }
        }

        if includePeers.count > 10, state.showAllInclude {
            struct T: Equatable {
                let a: Bool
                let b: Int
            }

            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_show_all_include, equatable: InputDataEquatable(T(a: state.showAllInclude, b: includePeers.count)), comparable: nil, item: { initialSize, stableId in
                return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().chatListFilterHideOther(includePeers.count - 11), nameStyle: ControlStyle(font: .normal(.title), foregroundColor: theme.colors.accent), type: .none, viewType: .lastItem, action: arguments.showAllInclude, thumb: GeneralThumbAdditional(thumb: theme.icons.chatSearchDown, textInset: 52, thumbInset: 4))
            }))
            index += 0
        }


        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().chatListFilterIncludeDesc), data: .init(color: theme.colors.listGrayText, detectBold: true, viewType: .textBottomItem)))
        index += 1

        if !data.isShared {
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1


            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().chatListFilterExcludeHeader), data: .init(color: theme.colors.listGrayText, detectBold: true, viewType: .textTopItem)))
            index += 1

            let hasAddExclude = (data.excludePeers.count < maximumPeers || !data.excludeRead || !data.excludeMuted || !data.excludeArchived)


            if hasAddExclude {
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_add_exclude, equatable: InputDataEquatable(state), comparable: nil, item: { initialSize, stableId in
                    return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().chatListFilterExcludeAddChat, nameStyle: ControlStyle(font: .normal(.title), foregroundColor: theme.colors.accent), type: .none, viewType: excludePeers.isEmpty ? .singleItem : .firstItem, action: arguments.addExclude, thumb: GeneralThumbAdditional(thumb: theme.icons.chat_filter_add, textInset: 46, thumbInset: 2))
                }))
                index += 0
            }
            fake = []
            fake.append(0)
            for (i, _) in excludePeers.enumerated() {
                if hasAddExclude {
                    fake.append(i + 1)
                } else {
                    fake.append(i)
                }
            }

            for (i, peer) in excludePeers.enumerated() {
                struct E : Equatable {
                    let viewType: GeneralViewType
                    let peer: SidebarPeerEquatable
                }
                if i > 10, !state.showAllExclude {
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_show_all_exclude, equatable: InputDataEquatable(excludePeers.count), comparable: nil, item: { initialSize, stableId in
                        return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().chatListFilterShowMoreOther(excludePeers.count - i), nameStyle: ControlStyle(font: .normal(.title), foregroundColor: theme.colors.accent), type: .none, viewType: .lastItem, action: arguments.showAllExclude, thumb: GeneralThumbAdditional(thumb: theme.icons.chatSearchUp, textInset: 52, thumbInset: 4))
                    }))
                    index += 0
                    break
                } else {
                    var viewType = bestGeneralViewType(fake, for: hasAddExclude ? i + 1 : i)

                    if excludePeers.count > 10, i == excludePeers.count - 1, state.showAllExclude {
                        viewType = .innerItem
                    }

                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_exclude(peer.id), equatable: InputDataEquatable(E(viewType: viewType, peer: SidebarPeerEquatable(peer))), comparable: nil, item: { initialSize, stableId in
                        return arguments.environment.makePeerRow(initialSize, peer: peer, stableId: stableId, viewType: viewType, action: {
                            arguments.openInfo(peer.id)
                        }, remove: {
                            arguments.removeExcluded(peer.id)
                        }, contextMenuItems: {
                            return .single([ContextMenuItem.init(strings().chatListFilterExcludeRemoveChat, handler: {
                                arguments.removeExcluded(peer.id)
                            })])
                        })
                    }))
                    index += 0
                }

            }

            if excludePeers.count > 10, state.showAllExclude {

                struct T: Equatable {
                    let a: Bool
                    let b: Int
                }

                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_show_all_exclude, equatable: InputDataEquatable(T(a: state.showAllExclude, b: excludePeers.count)), comparable: nil, item: { initialSize, stableId in
                    return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().chatListFilterHideOther(excludePeers.count - 11), nameStyle: ControlStyle(font: .normal(.title), foregroundColor: theme.colors.accent), type: .none, viewType: .lastItem, action: arguments.showAllExclude, thumb: GeneralThumbAdditional(thumb: theme.icons.chatSearchDown, textInset: 52, thumbInset: 4))
                }))
                index += 0
            }


            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().chatListFilterExcludeDesc), data: .init(color: theme.colors.listGrayText, detectBold: true, viewType: .textBottomItem)))
            index += 1
        }


        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1

        let colors = [theme.colors.peerColors(0).bottom,
                      theme.colors.peerColors(1).bottom,
                      theme.colors.peerColors(2).bottom,
                      theme.colors.peerColors(3).bottom,
                      theme.colors.peerColors(4).bottom,
                      theme.colors.peerColors(5).bottom,
                      theme.colors.peerColors(6).bottom]

        let currentColor = state.filter.data?.color
        let selected: NSColor? = currentColor.map { colors[abs(Int($0.rawValue)) % colors.count] }

        let rightText: NSAttributedString?
        if state.filter.data?.color != nil {
            let attr = NSMutableAttributedString()
            attr.append(string: state.filter.title, color: selected, font: .bold(11))
            arguments.environment.applyInlineStickers(to: attr, entities: state.filter.entities, isPremium: true, animated: true)
            rightText = attr
        } else {
            rightText = nil
        }


        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().chatListFolderColorTitle), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem, rightItem: .init(isLoading: false, text: rightText, action: nil, update: nil, alignToText: true, wrap: selected?.withAlphaComponent(0.1)), context: arguments.context)))
        index += 1


        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_color, equatable: InputDataEquatable(state.filter.data), comparable: nil, item: { initialSize, stableId in
            return FolderColorRowItem(initialSize, stableId: stableId, context: arguments.context, environment: arguments.environment, colors: colors, selected: selected, viewType: state.filter.data?.color == nil ? .singleItem : .firstItem, action: { color in
                arguments.toggleColor(colors.firstIndex(of: color).flatMap { Int32($0) })
            })
        }))

        if state.filter.data?.color != nil {
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_reset_color, data: .init(name: strings().chatListFolderColorReset, color: theme.colors.redUI, viewType: .lastItem, action: {
                arguments.toggleColor(nil)
            })))
        }

        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().chatListFolderColorInfo), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1


        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1

        if true {
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().chatListFilterInviteLinkHeader), data: .init(color: theme.colors.listGrayText, detectBold: true, viewType: .textTopItem)))
            index += 1

            let viewType: GeneralViewType

            if let invite = state.inviteLinks, !invite.isEmpty {
                viewType = .firstItem
            } else if state.inviteLinks == nil {
                viewType = .singleItem
            } else {
                viewType = .singleItem
            }

            let text: String
            if let invite = state.inviteLinks, !invite.isEmpty {
                text = strings().chatListFilterInviteLink
            } else {
                text = strings().chatListFilterInviteLinkShare
            }

            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_share_invite, equatable: InputDataEquatable(state), comparable: nil, item: { initialSize, stableId in
                return GeneralInteractedRowItem(initialSize, stableId: stableId, name: text, nameStyle: ControlStyle(font: .normal(.title), foregroundColor: theme.colors.accent), type: state.creatingLink || state.inviteLinks == nil ? .loading : .none, viewType: viewType, action: {
                    arguments.shareFolder(nil)
                }, thumb: GeneralThumbAdditional(thumb: theme.icons.group_invite_via_link, textInset: 52, thumbInset: 4))
            }))
            index += 0



            if let links = state.inviteLinks {
                struct Tuple : Equatable {
                    let link:ExportedChatFolderLink
                    let viewType: GeneralViewType
                    let saving: Bool
                }
                var items: [Tuple] = []
                for (i, link) in links.enumerated() {
                    items.append(.init(link: link, viewType: bestGeneralViewTypeAfterFirst(links, for: i), saving: state.linkSaving == link.link))
                }

                for item in items {

                    let info: String
                    info = strings().chatListFilterInviteLinkDescOther(item.link.peerIds.count)

                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_invite_link(item.link.slug), equatable: .init(item), comparable: nil, item: { initialSize, stableId in
                        return GeneralInteractedRowItem(initialSize, name: item.link.title.isEmpty ? item.link.link : item.link.title, description: info, type: item.saving ? .loading : .none, viewType: item.viewType, action: {
                            arguments.shareFolder(item.link)
                        }, thumb: GeneralThumbAdditional(thumb: item.link.isRevoked ? theme.icons.folder_invite_link_revoked : theme.icons.folder_invite_link, textInset: 52, thumbInset: 4), menuItems: {
                            var items: [ContextMenuItem] = []

                            items.append(ContextMenuItem(strings().contextCopy, handler: {
                                arguments.copy(item.link.link)
                            }, itemImage: arguments.environment.menuImage(.menu_copy)))

                            items.append(ContextSeparatorItem())

                            items.append(ContextMenuItem(strings().chatListFilterInviteLinkDelete, handler: {
                                arguments.deleteLink(item.link)
                            }, itemMode: .destruct, itemImage: arguments.environment.menuImage(.menu_delete)))


                            return items
                        })
                    }))
                    index += 0
                }
            }

            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().chatListFilterInviteLinkInfo), data: .init(color: theme.colors.listGrayText, detectBold: true, viewType: .textBottomItem)))
            index += 1

            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
        }

    }

    return entries
}

public func ChatListFilterController(context: any AccountContextProtocol, environment: SidebarUIEnvironment, filter: ChatListFilter, isNew: Bool = false) -> InputDataController {


    let title = environment.titleInputState(filter)

    let initialState = State(filter: filter, isNew: isNew, showAllInclude: false, showAllExclude: false, changedName: !isNew, inviteLinks: nil, creatingLink: false, linkSaving: nil, inputState: title, nameAnimation: true, inputStateEquals: environment.inputStatesEqual)

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }

    let maximumPeers = context.isPremium ? environment.limits.dialog_filters_chats_limit_premium : environment.limits.dialog_filters_chats_limit_default


    let updateDisposable = MetaDisposable()

    var getController:(()->InputDataController?)? = nil

    let save:(Bool)->Void = { savedOnServer in
        _ = context.engine.peers.updateChatListFiltersInteractively({ filters in
            let filter = stateValue.with { $0.filter }
            var filters = filters
            if let index = filters.firstIndex(where: {$0.sidebarId == filter.sidebarId}) {
                filters[index] = filter
            } else {
                filters.append(filter)
            }
            return filters
        }).start()

        if savedOnServer {
            updateState { current in
                var current = current
                current.isNew = false
                return current
            }
        }
    }

    let actionsDisposable = DisposableSet()


    let arguments = ChatListPresetArguments(context: context, environment: environment, toggleOption: { option in
        updateState { state in
            var state = state
            state.withUpdatedFilter { filter in
                var filter = filter
                switch filter {
                case .allChats:
                    break
                case let .filter(id, title, emoticon, data):
                    var data = data
                    if data.categories.contains(option) {
                        data.categories.remove(option)
                    } else {
                        data.categories.insert(option)
                    }
                    filter = .filter(id: id, title: title, emoticon: emoticon, data: data)
                }

                return filter
            }
            return state
        }
       // save(true)

    }, addInclude: {

        let items = stateValue.with { FolderSelection(filter: $0.filter, environment: environment).additionIncludeItems }
        let additionTopItems = items

        environment.selectPeers(defaultSelectedIds: Set(stateValue.with { $0.filter.data!.includePeers.peers + FolderSelection(filter: $0.filter, environment: environment).selectedIncludeItems.map { $0.id } }), categories: additionTopItems, limit: Int(maximumPeers), limitReachedText: strings().chatListFilterIncludeLimitReachedNew(Int(maximumPeers)), callback: { peerIds in
            updateState { state in
                var state = state

                state.withUpdatedFilter { sidebarFilterIncluding($0, peerIds: peerIds, maximumPeers: maximumPeers, categoryForPeer: environment.category) }
                return state
            }
         //   save(true)
            return .complete()
        })
    }, addExclude: {

        let items = stateValue.with { FolderSelection(filter: $0.filter, environment: environment).additionExcludeItems }
        let additionTopItems = items

        environment.selectPeers(defaultSelectedIds: Set(stateValue.with { $0.filter.data!.excludePeers + FolderSelection(filter: $0.filter, environment: environment).selectedExcludeItems.map { $0.id } }), categories: additionTopItems, limit: Int(maximumPeers), limitReachedText: strings().chatListFilterExcludeLimitReachedNew(Int(maximumPeers)), callback: { peerIds in
            updateState { state in
                var state = state
                state.withUpdatedFilter { sidebarFilterExcluding($0, peerIds: peerIds, maximumPeers: maximumPeers, categoryForPeer: environment.category) }
                return state
            }
            //   save(true)
            return .complete()
        })
    }, removeIncluded: { peerId in
        updateState { state in
            var state = state
            state.withUpdatedFilter { filter in
                let filter = filter
                switch filter {
                case .allChats:
                    break
                case let .filter(id, title, emoticon, data):
                    var data = data
                    var peers = data.includePeers.peers
                    peers.removeAll(where: { $0 == peerId })
                    data.includePeers.setPeers(peers)
                    if let category = environment.category(for: peerId) {
                        data.categories.remove(category)
                    }
                    return .filter(id: id, title: title, emoticon: emoticon, data: data)
                }

                return filter
            }
            return state
        }
        //save(true)
    }, removeExcluded: { peerId in
        updateState { state in
            var state = state
            state.withUpdatedFilter { filter in
                var filter = filter
                switch filter {
                case .allChats:
                    break
                case let .filter(id, title, emoticon, data):
                    var data = data
                    var peers = data.excludePeers
                    peers.removeAll(where: { $0 == peerId })
                    data.excludePeers = peers
                    if let category = environment.category(for: peerId) {
                        if category == .excludeMuted {
                            data.excludeMuted = false
                        }
                        if category == .excludeRead {
                            data.excludeRead = false
                        }
                        if category == .excludeArchived {
                            data.excludeArchived = false
                        }
                    }
                    filter = .filter(id: id, title: title, emoticon: emoticon, data: data)
                }

                return filter
            }
            return state
        }
        //save(true)
    }, openInfo: { peerId in
        environment.openPeerInfo(peerId)
    }, toggleExcludeMuted: { updated in
        updateState { state in
            var state = state
            state.withUpdatedFilter { filter in
                var filter = filter
                switch filter {
                case .allChats:
                    break
                case let .filter(id, title, emoticon, data):
                    var data = data
                    data.excludeMuted = updated
                    filter = .filter(id: id, title: title, emoticon: emoticon, data: data)
                }
                return filter
            }
            return state
        }
       // save(true)
    }, toggleExcludeRead: { updated in
        updateState { state in
            var state = state
            state.withUpdatedFilter { filter in
                var filter = filter
                switch filter {
                case .allChats:
                    break
                case let .filter(id, title, emoticon, data):
                    var data = data
                    data.excludeRead = updated
                    filter = .filter(id: id, title: title, emoticon: emoticon, data: data)
                }
                return filter
            }
            return state
        }
        //save(true)
    }, showAllInclude: {
        updateState { state in
            var state = state
            state.showAllInclude = !state.showAllInclude
            return state
        }
    }, showAllExclude: {
        updateState { state in
            var state = state
            state.showAllExclude = !state.showAllExclude
            return state
        }
    }, updateIcon: { icon in
        updateState { state in
            var state = state
            state.withUpdatedFilter { filter in
                var filter = filter
                switch filter {
                case .allChats:
                    break
                case let .filter(id, title, _, data):
                    filter = .filter(id: id, title: title, emoticon: icon.emoticon.emoji, data: data)
                }
                return filter
            }
            return state
        }
    }, shareFolder: { link in
        let filter = stateValue.with { $0.filter }
        let initialFilter = stateValue.with { $0.initialFilter }
        let isLoading = stateValue.with { $0.creatingLink }

        let updateLink:(ExportedChatFolderLink, ExportedChatFolderLink?)->Void = { link, updated in
            updateState { current in
                var current = current
                current.creatingLink = false
                if let index = current.inviteLinks?.firstIndex(where: { $0.link == link.link }) {
                    current.inviteLinks?.remove(at: index)
                    if let updated = updated {
                        current.inviteLinks?.insert(updated, at: index)
                    }
                }
                return current
            }
        }

        if let data = filter.data, !isLoading {
            if link == nil {
                updateState { current in
                    var current = current
                    current.creatingLink = true
                    return current
                }
                let emptyTitle = stateValue.with { value -> Bool in
                    switch value.filter {
                    case .allChats:
                        return true
                    case let .filter(_, title, _, _):
                        return title.text.isEmpty
                    }
                }
                let emptyPeers = stateValue.with { value -> Bool in
                    switch value.filter {
                    case .allChats:
                        return true
                    case let .filter(_, _, _, data):
                        return data.includePeers.peers.isEmpty
                    }
                }
                let exclude = stateValue.with {
                    FolderSelection(filter: $0.filter, environment: environment).excludeAllPeers
                }
                let wrongInclude = stateValue.with {
                    return FolderSelection(filter: $0.filter, environment: environment).includeCustom
                }
                if emptyTitle || emptyPeers || !exclude.isEmpty || !wrongInclude.isEmpty {
                    updateState { current in
                        var current = current
                        current.creatingLink = false
                        return current
                    }
                    var fail: [InputDataIdentifier : InputDataValidationFailAction] = [:]
                    if emptyTitle {
                        fail[_id_name_input] = .shake
                    } else if !wrongInclude.isEmpty {
                        for id in wrongInclude {
                            fail[_id_include(id)] = .shake
                        }
                        showModalText(for: context.window, text: strings().chatListFilterInviteLinkIncludeExcludeError)
                    } else if emptyPeers {
                        showModalText(for: context.window, text: strings().chatListFilterErrorEmpty)
                        fail[_id_add_include] = .shake
                    } else if !exclude.isEmpty {
                        for id in exclude {
                            fail[_id_exclude(id)] = .shake
                        }
                        showModalText(for: context.window, text: strings().chatListFilterInviteLinkIncludeExcludeError)
                    }

                    getController?()?.proccessValidation(.fail(.fields(fail)))
                    return
                }

                let signal: Signal<Never, RequestUpdateChatListFilterError>
                if initialFilter == filter {
                    signal = .complete()
                } else {
                    signal = context.engine.peers.requestUpdateChatListFilter(id: filter.sidebarId, filter: filter) |> deliverOnMainQueue
                }

                actionsDisposable.add(signal.start(error: { error in
                    environment.alert(strings().unknownError)

                    updateState { current in
                        var current = current
                        current.creatingLink = false
                        return current
                    }
                }, completed: {

                    updateState { current in
                        var current = current
                        current.initialFilter = filter
                        return current
                    }

                    save(true)

                    let folderLimits = shareFolderPremiumLimits(context: context, environment: environment, current: filter, links: stateValue.with { $0.inviteLinks })

                    let canCreateLink: Signal<Bool, NoError> = context.account.postbox.transaction { transaction -> Bool in
                        var peers:[Peer] = []

                        for peerId in data.includePeers.peers {
                            if let peer = transaction.getPeer(peerId) {
                                peers.append(peer)
                            }
                        }
                        return !peers.filter( { environment.peerCanBeSharedInFolder($0) }).isEmpty
                    } |> deliverOnMainQueue

                    _ = combineLatest(folderLimits, canCreateLink).start(next: { limits, canCreateLink in
                        if canCreateLink {

                            if limits.limitInvites || limits.limitFilters {
                                if limits.limitFilters {
                                    environment.showPremiumLimit(.sharedFolders)
                                } else if limits.limitInvites {
                                    environment.showPremiumLimit(.sharedInvites)
                                }
                                updateState { current in
                                    var current = current
                                    current.creatingLink = false
                                    return current
                                }
                                return
                            }

                            let makeUrl = context.engine.peers.exportChatFolder(filterId: filter.sidebarId, title: "", peerIds: data.includePeers.peers) |> deliverOnMainQueue
                            actionsDisposable.add(makeUrl.start(next: { link in
                                updateState { current in
                                    var current = current
                                    current.creatingLink = false
                                    current.inviteLinks?.append(link)
                                    var filter = current.filter
                                    var data = data
                                    data.isShared = true
                                    for peerId in link.peerIds.reversed() {
                                        _ = data.includePeers.addPeer(peerId)
                                    }
                                    filter = filter.withUpdatedData(data)
                                    current.filter = filter
                                    current.initialFilter = filter
                                    return current
                                }
                                save(false)
                                environment.openSharedFolderLink(filter: stateValue.with { $0.filter }, link: link, updated: updateLink)
                            }, error: { error in

                                switch error {
                                case .limitExceeded:
                                    environment.showPremiumLimit(.sharedInvites)
                                case .sharedFolderLimitExceeded:
                                    environment.showPremiumLimit(.sharedFolders)
                                case .tooManyChannels:
                                    environment.showInactiveChannels()
                                case .tooManyChannelsInAccount:
                                    environment.showPremiumLimit(.channels)
                                case .someUserTooManyChannels:
                                    environment.alert(strings().sharedFolderErrorSomeUserTooMany)
                                case .generic:
                                    environment.alert(strings().unknownError)
                                }

                                updateState { current in
                                    var current = current
                                    current.creatingLink = false
                                    return current
                                }
                            }))
                        } else {
                            updateState { current in
                                var current = current
                                current.creatingLink = false
                                return current
                            }
                            environment.openSharedFolderLink(filter: filter, link: nil, updated: updateLink)
                        }
                    })
                }))


            } else {

                let signal: Signal<Never, RequestUpdateChatListFilterError>
                if initialFilter == filter {
                    signal = .complete()
                } else {
                    updateState { current in
                        var current = current
                        current.linkSaving = link?.link
                        return current
                    }
                    signal = context.engine.peers.requestUpdateChatListFilter(id: filter.sidebarId, filter: filter) |> deliverOnMainQueue
                }

                actionsDisposable.add(signal.start(error: { error in
                    environment.alert(strings().unknownError)
                    updateState { current in
                        var current = current
                        current.linkSaving = nil
                        return current
                    }
                }, completed: {
                    updateState { current in
                        var current = current
                        current.linkSaving = nil
                        current.initialFilter = filter
                        return current
                    }

                    save(true)

                    environment.openSharedFolderLink(filter: filter, link: link, updated: updateLink)
                }))

            }
        }
    }, copy: { link in
        showModalText(for: context.window, text: strings().shareLinkCopied)
        environment.copyToClipboard(link)
    }, deleteLink: { link in
        environment.confirmFolderAction(information: strings().chatListFilterInviteLinkDeleteConfirm, ok: strings().chatListFilterInviteLinkDelete, successHandler: {

            var index: Int? = nil
            updateState { current in
                var current = current
                index = current.inviteLinks?.firstIndex(of: link)
                if let index = index {
                    current.inviteLinks?.remove(at: index)
                }
                return current
            }
            let signal = context.engine.peers.deleteChatFolderLink(filterId: filter.sidebarId, link: link) |> deliverOnMainQueue

            actionsDisposable.add(signal.start(error: { error in
                environment.alert(strings().unknownError)
                updateState { current in
                    var current = current
                    if let index = index {
                        current.inviteLinks?.insert(link, at: index)
                    }
                    return current
                }
            }))

        })
    }, toggleColor: { color in
        if let _ = color, !context.isPremium {
            showModalText(for: context.window, text: strings().chatListFolderPremiumAlert, button: strings().alertLearnMore, callback: { _ in
                environment.showFolderTagsPremium()
            })
        } else {
            updateState { current in
                var current = current
                switch current.filter {
                case .allChats:
                    current.filter = .allChats
                case .filter(let id, let title, let emoticon, var data):
                    data.color = color.flatMap { .init(rawValue: $0) }
                    current.filter = .filter(id: id, title: title, emoticon: emoticon, data: data)
                }
                return current
            }
        }
    }, updateState: { state in
        updateState { current in
            var current = current
            current.inputState = state
            current.changedName = true
            current.filter = sidebarUpdatingTitle(current.filter, state: current.inputState, animated: current.nameAnimation, entities: environment.titleEntities)
            return current
        }
    }, toggleNameAnimation: {
        updateState { current in
            var current = current
            current.nameAnimation = !current.nameAnimation
            current.filter = sidebarUpdatingTitle(current.filter, state: current.inputState, animated: current.nameAnimation, entities: environment.titleEntities)
            return current
        }
    })


    let inviteLinks: Signal<[ExportedChatFolderLink]?, NoError>

    if isNew {
        inviteLinks = .single([])
    } else {
        inviteLinks = .single(nil) |> then(context.engine.peers.getExportedChatFolderLinks(id: filter.sidebarId) |> map {
            $0 ?? []
        })
    }


    actionsDisposable.add(inviteLinks.start(next: { links in
        updateState { current in
            var current = current
            current.inviteLinks = links
            return current
        }
    }))

    let dataSignal = combineLatest(queue: prepareQueue, appearanceSignal, statePromise.get()) |> mapToSignal { _, state -> Signal<(State, ([Peer], [Peer])), NoError> in
        return context.account.postbox.transaction { transaction -> ([Peer], [Peer]) in
            switch state.filter {
            case .allChats:
                return ([], [])
            case let .filter(_, _, _, data):
                return (data.includePeers.peers.compactMap { transaction.getPeer($0) }, data.excludePeers.compactMap { transaction.getPeer($0) })
            }
        } |> map {
            (state, $0)
        }
    } |> map {
        return chatListFilterEntries(state: $0, includePeers: $1.0, excludePeers: $1.1, arguments: arguments)
    } |> map {
          return InputDataSignalValue(entries: $0)
    }


    let controller = InputDataController(dataSignal: dataSignal, title: isNew ? strings().chatListFilterNewTitle : strings().chatListFilterTitle, removeAfterDisappear: false)


    controller.backInvocation = { data, f in
        sidebarConfirmDiscard(changed: stateValue.with { $0.filter != $0.initialFilter }, confirm: { accepted in
            environment.confirmFolderAction(header: strings().chatListFilterDiscardHeader, information: strings().chatListFilterDiscardText, ok: strings().chatListFilterDiscardOK, cancel: strings().chatListFilterDiscardCancel, successHandler: accepted)
        }, continuation: f)

    }

    controller.updateDoneValue = { data in
        return { f in
            if stateValue.with({ $0.isNew }) {
                f(.enabled(strings().chatListFilterDone))
            } else {
                f(.enabled(strings().navigationDone))
            }
        }
    }

    controller.onDeinit = {
        updateDisposable.dispose()
        actionsDisposable.dispose()
    }

    getController = { [weak controller] in
        return controller
    }

    controller.afterTransaction = { controller in
        let type = stateValue.with { chatListFilterType($0.filter) }
        let nameIsUpdated = stateValue.with { $0.changedName }


        if !nameIsUpdated {
            switch type {
            case .generic:
                break
            case .unmuted:
                //state.name = presentationData.strings.ChatListFolder_NameNonMuted
                updateState { state in
                    var state = state
                    state.filter = state.filter.withUpdatedTitle(string: strings().chatListFilterTilteDefaultUnmuted, entities: [], enableAnimations: false)
                  //  emoticon =
                    return state
                }
            case .unread:
                updateState { state in
                    var state = state
                    state.filter = state.filter.withUpdatedTitle(string: strings().chatListFilterTilteDefaultUnread, entities: [], enableAnimations: false)
                    return state
                }
            case .channels:
                updateState { state in
                    var state = state
                    state.filter = state.filter.withUpdatedTitle(string: strings().chatListFilterTilteDefaultChannels, entities: [], enableAnimations: false)
                    return state
                }
            case .groups:
                updateState { state in
                    var state = state
                    state.filter = state.filter.withUpdatedTitle(string: strings().chatListFilterTilteDefaultGroups, entities: [], enableAnimations: false)
                    return state
                }
            case .bots:
                updateState { state in
                    var state = state
                    state.filter = state.filter.withUpdatedTitle(string: strings().chatListFilterTilteDefaultBots, entities: [], enableAnimations: false)
                    return state
                }
            case .contacts:
                updateState { state in
                    var state = state
                    state.filter = state.filter.withUpdatedTitle(string: strings().chatListFilterTilteDefaultContacts, entities: [], enableAnimations: false)
                    return state
                }
            case .nonContacts:
                updateState { state in
                    var state = state
                    state.filter = state.filter.withUpdatedTitle(string: strings().chatListFilterTilteDefaultNonContacts, entities: [], enableAnimations: false)
                    return state
                }
            }

        }
    }

    controller.validateData = { data in

        return .fail(.doSomething(next: { f in
            let titleLength = stateValue.with { value -> Int in
                switch value.filter {
                case .allChats:
                    return 1
                case .filter:
                    return value.inputState.inputText.string.length
                }
            }
            let filter = stateValue.with { $0.filter }
            sidebarValidateFolder(filter: filter, initialFilter: stateValue.with { $0.initialFilter }, titleLength: titleLength, nameId: _id_name_input, includeId: _id_add_include, notify: { text in
                showModalText(for: context.window, text: text)
            }, requestSave: { completed in
                _ = showModalProgress(signal: context.engine.peers.requestUpdateChatListFilter(id: filter.sidebarId, filter: filter), for: context.window).start(error: { error in
                    switch error {
                    case .generic:
                        environment.alert(strings().unknownError)
                    }
                }, completed: completed)
            }, save: save, completion: f)

        }))
    }

    return controller

}
