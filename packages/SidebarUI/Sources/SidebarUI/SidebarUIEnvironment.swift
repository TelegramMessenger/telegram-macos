import Cocoa
import TGUIKit
import TelegramContext
import TelegramCore
import Postbox
import SwiftSignalKit
import InputView
import InputDataUI
import GeneralRows

public struct SidebarState {
    public let tabs: [ChatListFilter]
    public let selectedFilterId: Int32

    public init(tabs: [ChatListFilter], selectedFilterId: Int32) {
        self.tabs = tabs
        self.selectedFilterId = selectedFilterId
    }
}

public enum SidebarImage {
    case iconSharedFolder
    case tabsselectTopGray, tabsselectTopSystemcol, tabsselectLeftGray, tabsselectLeftSystemcol
    case iconForumTabs, iconForumList
}

public enum SidebarMenuImage {
    case menu_edit, menu_plus, menu_folder_read, menu_mute, menu_unmuted, menu_share, menu_delete, menu_copy
}

public enum SidebarPremiumLimit {
    case folders, sharedFolders, sharedInvites, channels
}

public enum SidebarHeaderAnimation {
    case folder, newFolder
}

public protocol SidebarAnimatedHeaderView: NSView {
    func update(animation: SidebarHeaderAnimation, table: TableView?, animated: Bool)
}

public protocol SidebarUIEnvironment: AnyObject {
    var context: any AccountContextProtocol { get }
    var limits: SidebarLimits { get }
    var filterPredicates: Signal<(ChatListFilter?) -> ChatListFilterPredicate?, NoError> { get }
    func navigateToFilter(_ id: Int32)
    func openPeerInfo(_ id: PeerId)
    func shareFolder(_ filter: ChatListFilter)
    func deleteSharedFolder(_ filter: ChatListFilter)
    func openSharedFolderLink(filter: ChatListFilter, link: ExportedChatFolderLink?, updated: @escaping (ExportedChatFolderLink, ExportedChatFolderLink?) -> Void)
    func peerCanBeSharedInFolder(_ peer: Peer) -> Bool
    func showPremiumLimit(_ limit: SidebarPremiumLimit)
    func showFolderTagsPremium()
    func showInactiveChannels()
    func copyToClipboard(_ text: String)
    func alert(_ text: String)
    func confirm(header: String?, information: String?, ok: String, cancel: String?, successHandler: @escaping () -> Void)
    func category(for peerId: PeerId) -> ChatListFilterPeerCategories?
    func categoryPeer(_ category: ChatListFilterPeerCategories) -> Peer
    func selectPeers(defaultSelectedIds: Set<PeerId>, categories: [Peer], limit: Int, limitReachedText: String, callback: @escaping ([PeerId]) -> Signal<Never, NoError>)
    func titleInputState(_ filter: ChatListFilter) -> Updated_ChatTextInputState
    func titleEntities(_ state: Updated_ChatTextInputState) -> [MessageTextEntity]
    func inputStatesEqual(_ lhs: Updated_ChatTextInputState, _ rhs: Updated_ChatTextInputState) -> Bool
    func makeNameRow(_ size: NSSize, stableId: AnyHashable, state: Updated_ChatTextInputState, rightItem: InputDataRightItem, updateState: @escaping (Updated_ChatTextInputState) -> Void, playAnimation: Bool) -> TableRowItem
    func makePeerRow(_ size: NSSize, peer: Peer, stableId: AnyHashable, viewType: GeneralViewType, action: @escaping () -> Void, remove: @escaping () -> Void, contextMenuItems: @escaping () -> Signal<[ContextMenuItem], NoError>) -> TableRowItem
    func makeAnimatedHeader() -> SidebarAnimatedHeaderView
    func applyInlineStickers(to text: NSMutableAttributedString, entities: [MessageTextEntity], isPremium: Bool, animated: Bool)
    func image(_ image: SidebarImage) -> NSImage
    func folderImage(_ name: String) -> NSImage
    func menuImage(_ image: SidebarMenuImage) -> ((NSColor, ContextMenuItem) -> AppMenuItemImageDrawable)?
    func colorImage(_ color: NSColor, ring: Bool) -> CGImage
}

extension SidebarUIEnvironment {
    func confirmFolderAction(header: String? = nil, information: String?, ok: String, cancel: String? = nil, successHandler: @escaping () -> Void) {
        confirm(header: header, information: information, ok: ok, cancel: cancel, successHandler: successHandler)
    }
}
