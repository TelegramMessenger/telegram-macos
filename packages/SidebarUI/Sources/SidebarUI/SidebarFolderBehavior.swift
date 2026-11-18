import Foundation
import TelegramCore
import Postbox
import TGUIKit
import InAppSettings

func sidebarFilterIncluding(_ filter: ChatListFilter, peerIds: [PeerId], maximumPeers: Int, categoryForPeer: (PeerId) -> ChatListFilterPeerCategories?) -> ChatListFilter {
    let categories = peerIds.filter {
        categoryForPeer($0) != nil
    }
    let peerIds = Set(peerIds).subtracting(categories)

    var filter = filter
    switch filter {
    case .allChats:
        break
    case let .filter(id, title, emoticon, data):
        var data = data
        data.includePeers.setPeers(Array(peerIds.uniqueElements.prefix(Int(maximumPeers))))
        data.excludePeers = data.excludePeers.filter { !data.includePeers.peers.contains($0) }
        var updatedCats: ChatListFilterPeerCategories = []
        let cats = categories.compactMap(categoryForPeer)
        for cat in cats {
            updatedCats.insert(cat)
        }
        data.categories = updatedCats
        filter = .filter(id: id, title: title, emoticon: emoticon, data: data)
    }

    return filter
}

func sidebarFilterExcluding(_ filter: ChatListFilter, peerIds: [PeerId], maximumPeers: Int, categoryForPeer: (PeerId) -> ChatListFilterPeerCategories?) -> ChatListFilter {
    var filter = filter
    switch filter {
    case .allChats:
        break
    case let .filter(id, title, emoticon, data):
        var data = data
        let categories = peerIds.filter {
            categoryForPeer($0) != nil
        }
        let peerIds = Set(peerIds).subtracting(categories)
        data.excludePeers = Array(peerIds.uniqueElements.prefix(Int(maximumPeers)))
        data.includePeers.setPeers(data.includePeers.peers.filter { !data.excludePeers.contains($0) })
        let cats = categories.compactMap(categoryForPeer)
        data.excludeMuted = cats.contains(.excludeMuted)
        data.excludeRead = cats.contains(.excludeRead)
        data.excludeArchived = cats.contains(.excludeArchived)
        filter = .filter(id: id, title: title, emoticon: emoticon, data: data)
    }


    return filter
}

func sidebarSharingLimits(filters: [ChatListFilter], current: ChatListFilter, links: [ExportedChatFolderLink]?, isPremium: Bool, limits: SidebarLimits) -> (limitFilters: Bool, limitInvites: Bool) {
    var shared = filters.filter { $0.data?.isShared == true }
    if current.data?.isShared == true, current.data?.hasSharedLinks == true {
        shared.removeAll()
    }
    let links = links ?? []
    var limitFilters: Bool = false
    var limitInvites: Bool = false
    if isPremium {
        if shared.count >= limits.communities_joined_limit_premium {
            limitFilters = true
        } else if links.count >= limits.community_invites_limit_premium {
            limitInvites = true
        }
    } else {
        if shared.count >= limits.communities_joined_limit_default {
            limitFilters = true
        }
        if links.count >= limits.community_invites_limit_default {
            limitInvites = true
        }
    }
    return (limitFilters: limitFilters, limitInvites: limitInvites)
}

func sidebarMenuAddingPeers(_ data: ChatListFilterData, peerIds: [PeerId]) -> ChatListFilterData {
    var data = data
    data.includePeers.setPeers(Array(peerIds.uniqueElements.prefix(100)))
    data.excludePeers = data.excludePeers.filter { !data.includePeers.peers.contains($0) }
    return data
}

func sidebarResortRange(rowCount: Int, isPremium: Bool) -> NSRange {
    return isPremium ? NSMakeRange(1, rowCount - 1) : NSMakeRange(2, rowCount - 2)
}

func sidebarReorderedFilters(_ filters: [ChatListFilter], from: Int, to: Int, rangeLocation: Int, offset: Int) -> [ChatListFilter] {
    var filters = filters
    filters.move(at: from - rangeLocation + offset, to: to - rangeLocation + offset)
    return filters
}
