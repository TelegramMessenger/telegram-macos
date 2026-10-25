import Cocoa
import SidebarUI
import TelegramCore
import Postbox
import SwiftSignalKit
import TGUIKit
import InputView
import InAppSettings

func navigateToChatListFilter(_ filter: Int32, context: AccountContext) {

    context.bindings.mainViewController.chatList.updateFilter { state in
        return state.withUpdatedFilterId(filter)
    }

    let rootNavigation = context.bindings.rootNavigation()

    let leftController = context.bindings.mainViewController
    leftController.showChatList()

    leftController.navigation.close(animated: true)

    if context.layout == .single {
        rootNavigation.close(animated: true)
    }
}

func ChatListFiltersListController(context: AccountContext) -> InputDataController {
    return SidebarUI.ChatListFiltersListController(context: context, environment: AppSidebarUIEnvironment(context))
}

func ChatListFilterController(context: AccountContext, filter: ChatListFilter, isNew: Bool = false) -> InputDataController {
    return SidebarUI.ChatListFilterController(context: context, environment: AppSidebarUIEnvironment(context), filter: filter, isNew: isNew)
}

func filterContextMenuItems(_ filter: ChatListFilter, unreadCount: Int?, includeAllMuted: Bool? = nil, context: AccountContext) -> [ContextMenuItem] {
    return SidebarUI.filterContextMenuItems(filter, unreadCount: unreadCount, includeAllMuted: includeAllMuted, context: context, environment: AppSidebarUIEnvironment(context))
}

func shareFolderPremiumLimits(context: AccountContext, current: ChatListFilter, links: [ExportedChatFolderLink]?) -> Signal<(limitFilters: Bool, limitInvites: Bool), NoError> {
    return SidebarUI.shareFolderPremiumLimits(context: context, environment: AppSidebarUIEnvironment(context), current: current, links: links)
}

extension LeftSidebarController {
    convenience init(_ context: AccountContext, filterData: Signal<FilterData, NoError>, updateFilter: @escaping (_ f: (FilterData) -> FilterData) -> Void) {
        self.init(context, environment: AppSidebarUIEnvironment(context), filterData: filterData |> distinctUntilChanged(isEqual: { lhs, rhs in lhs.tabs == rhs.tabs && lhs.filter.id == rhs.filter.id }) |> map { SidebarState(tabs: $0.tabs, selectedFilterId: $0.filter.id) }, badges: chatListFilterItems(engine: context.engine, accountManager: context.sharedContext.accountManager))
    }
}

private func sidebarAlert(_ context: AccountContext, text: String) {
    alert(for: context.window, info: text)
}

private func sidebarDeleteSharedFolder(_ context: AccountContext, filter: ChatListFilter) {
    deleteSharedFolder(context: context, filter: filter)
}

private func sidebarPeerCanBeShared(_ peer: Peer) -> Bool {
    return peerCanBeSharedInFolder(peer)
}

private func sidebarPremiumLimit(_ context: AccountContext, limit: SidebarPremiumLimit) {
    switch limit {
    case .folders: showModal(with: PremiumLimitController(context: context, type: .folders), for: context.window)
    case .sharedFolders: showPremiumLimit(context: context, type: .sharedFolders)
    case .sharedInvites: showPremiumLimit(context: context, type: .sharedInvites)
    case .channels: showPremiumLimit(context: context, type: .channels)
    }
}

private func sidebarInactiveChannels(_ context: AccountContext) {
    showInactiveChannels(context: context, source: .join)
}

final class AppSidebarUIEnvironment: SidebarUIEnvironment {
    private let accountContext: AccountContext
    var context: any AccountContextProtocol { accountContext }

    init(_ context: AccountContext) {
        self.accountContext = context
    }

    var limits: SidebarLimits {
        let limits = accountContext.premiumLimits
        return SidebarLimits(dialog_filters_limit_default: limits.dialog_filters_limit_default, dialog_filters_limit_premium: limits.dialog_filters_limit_premium, dialog_filters_chats_limit_default: limits.dialog_filters_chats_limit_default, dialog_filters_chats_limit_premium: limits.dialog_filters_chats_limit_premium, community_invites_limit_default: limits.community_invites_limit_default, community_invites_limit_premium: limits.community_invites_limit_premium, communities_joined_limit_default: limits.communities_joined_limit_default, communities_joined_limit_premium: limits.communities_joined_limit_premium)
    }

    var filterPredicates: Signal<(ChatListFilter?) -> ChatListFilterPredicate?, NoError> {
        return communityFilterCategories(account: accountContext.account) |> map { categories in
            return { filter in chatListFilterPredicate(for: filter, communityCategories: categories) }
        }
    }

    func navigateToFilter(_ id: Int32) {
        navigateToChatListFilter(id, context: accountContext)
    }

    func openPeerInfo(_ id: PeerId) {
        PeerInfoController.push(navigation: accountContext.bindings.rootNavigation(), context: accountContext, peerId: id)
    }

    func shareFolder(_ filter: ChatListFilter) {
        shareSharedFolder(context: accountContext, filter: filter)
    }

    func deleteSharedFolder(_ filter: ChatListFilter) {
        sidebarDeleteSharedFolder(accountContext, filter: filter)
    }

    func openSharedFolderLink(filter: ChatListFilter, link: ExportedChatFolderLink?, updated: @escaping (ExportedChatFolderLink, ExportedChatFolderLink?) -> Void) {
        showModal(with: ShareCloudFolderController(context: accountContext, filter: filter, link: link, updated: updated), for: accountContext.window)
    }

    func peerCanBeSharedInFolder(_ peer: Peer) -> Bool {
        return sidebarPeerCanBeShared(peer)
    }

    func showPremiumLimit(_ limit: SidebarPremiumLimit) {
        sidebarPremiumLimit(accountContext, limit: limit)
    }

    func showFolderTagsPremium() {
        prem(with: PremiumBoardingController(context: accountContext, source: .folder_tags, openFeatures: true), for: accountContext.window)
    }

    func showInactiveChannels() {
        sidebarInactiveChannels(accountContext)
    }

    func copyToClipboard(_ text: String) {
        sidebarCopyToClipboard(text)
    }

    func alert(_ text: String) {
        sidebarAlert(accountContext, text: text)
    }

    func confirm(header: String?, information: String?, ok: String, cancel: String?, successHandler: @escaping () -> Void) {
        verifyAlert_button(for: accountContext.window, header: header ?? appName, information: information, ok: ok, cancel: cancel ?? strings().alertCancel, successHandler: { _ in successHandler() })
    }

    func category(for peerId: PeerId) -> ChatListFilterPeerCategories? {
        guard peerId.namespace._internalGetInt32Value() == ChatListFilterPeerCategories.Namespace else { return nil }
        return ChatListFilterPeerCategories(rawValue: Int32(peerId.id._internalGetInt64Value()))
    }

    func categoryPeer(_ category: ChatListFilterPeerCategories) -> Peer {
        return TelegramFilterCategory(category: category)
    }

    func selectPeers(defaultSelectedIds: Set<PeerId>, categories: [Peer], limit: Int, limitReachedText: String, callback: @escaping ([PeerId]) -> Signal<Never, NoError>) {
        let items = categories.map { ShareAdditionItem(peer: $0, status: "") }
        let additional = items.isEmpty ? nil : ShareAdditionItems(items: items, topSeparator: strings().chatListAddTopSeparator, bottomSeparator: strings().chatListAddBottomSeparator)
        showModal(with: ShareModalController(SelectCallbackObject(accountContext, defaultSelectedIds: defaultSelectedIds, additionTopItems: additional, limit: limit, limitReachedText: limitReachedText, callback: callback)), for: accountContext.window)
    }

    func titleInputState(_ filter: ChatListFilter) -> Updated_ChatTextInputState {
        return ChatTextInputState(inputText: filter.title, selectionRange: filter.title.length..<filter.title.length, attributes: chatTextAttributes(from: TextEntitiesMessageAttribute(entities: filter.entities), associatedMedia: [:])).textInputState()
    }

    func titleEntities(_ state: Updated_ChatTextInputState) -> [MessageTextEntity] {
        return state.textInputState().messageTextEntities()
    }

    func inputStatesEqual(_ lhs: Updated_ChatTextInputState, _ rhs: Updated_ChatTextInputState) -> Bool {
        return lhs == rhs
    }

    func makeNameRow(_ size: NSSize, stableId: AnyHashable, state: Updated_ChatTextInputState, rightItem: InputDataRightItem, updateState: @escaping (Updated_ChatTextInputState) -> Void, playAnimation: Bool) -> TableRowItem {
        return InputTextDataRowItem(size, stableId: stableId, context: accountContext, state: state, viewType: .singleItem, placeholder: nil, inputPlaceholder: strings().chatListFilterNamePlaceholder, rightItem: rightItem, filter: { $0 }, updateState: updateState, limit: 12, hasEmoji: true, playAnimation: playAnimation)
    }

    func makePeerRow(_ size: NSSize, peer: Peer, stableId: AnyHashable, viewType: GeneralViewType, action: @escaping () -> Void, remove: @escaping () -> Void, contextMenuItems: @escaping () -> Signal<[ContextMenuItem], NoError>) -> TableRowItem {
        let item = ShortPeerRowItem(size, peer: peer, account: accountContext.account, context: accountContext, stableId: stableId, height: 44, photoSize: NSMakeSize(30, 30), inset: NSEdgeInsets(left: 20, right: 20), viewType: viewType, action: action, contextMenuItems: contextMenuItems)
        item.avatarRemoveAction = remove
        return item
    }

    func makeAnimatedHeader() -> SidebarAnimatedHeaderView {
        return AppSidebarAnimatedHeader(accountContext)
    }

    func applyInlineStickers(to text: NSMutableAttributedString, entities: [MessageTextEntity], isPremium: Bool, animated: Bool) {
        InlineStickerItem.apply(to: text, associatedMedia: [:], entities: entities, isPremium: isPremium, playPolicy: animated ? nil : .framesCount(1))
    }

    func image(_ image: SidebarImage) -> NSImage {
        return sidebarImage(image)
    }

    func folderImage(_ name: String) -> NSImage {
        return NSImage(named: name)!
    }

    func menuImage(_ image: SidebarMenuImage) -> ((NSColor, ContextMenuItem) -> AppMenuItemImageDrawable)? {
        switch image {
        case .menu_edit: return MenuAnimation.menu_edit.value
        case .menu_plus: return MenuAnimation.menu_plus.value
        case .menu_folder_read: return MenuAnimation.menu_folder_read.value
        case .menu_mute: return MenuAnimation.menu_mute.value
        case .menu_unmuted: return MenuAnimation.menu_unmuted.value
        case .menu_share: return MenuAnimation.menu_share.value
        case .menu_delete: return MenuAnimation.menu_delete.value
        case .menu_copy: return MenuAnimation.menu_copy.value
        }
    }

    func colorImage(_ color: NSColor, ring: Bool) -> CGImage {
        return ring ? generateRingImage(nameColor: .init(main: color)) : generateFillImage(nameColor: .init(main: color))
    }
}

private final class AppSidebarAnimatedHeader: View, SidebarAnimatedHeaderView {
    private let context: AccountContext
    private let stickerView = MediaAnimatedStickerView(frame: .zero)

    init(_ context: AccountContext) {
        self.context = context
        super.init(frame: NSMakeRect(0, 0, 112, 112))
        addSubview(stickerView)
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(animation: SidebarHeaderAnimation, table: TableView?, animated: Bool) {
        let sticker: LocalAnimatedSticker = animation == .folder ? .folder : .new_folder
        stickerView.update(with: sticker.file, size: NSMakeSize(112, 112), context: context, parent: nil, table: table, parameters: sticker.parameters, animated: animated, positionFlags: nil, approximateSynchronousValue: false)
    }
}

private func sidebarCopyToClipboard(_ text: String) {
    copyToClipboard(text)
}
