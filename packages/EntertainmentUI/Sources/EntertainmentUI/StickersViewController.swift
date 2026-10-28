import Cocoa
import TGUIKit
import ColorPalette
import ComponentsUI
import SwiftSignalKit
import TelegramCore
import InAppSettings
import Postbox
import FoundationUtils
import ObjcUtils
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import MessageTextUtils
import GeneralRows
import AlertsUI
import ChatModeTypes

private struct State : Equatable {
    var searchCategories: EmojiSearchCategories?
    var selectedEmojiCategory: EmojiSearchCategories.Group?
}


public final class StickerPanelArguments {
    public let context: any AccountContextProtocol
    public let sendMedia:(Media, NSView, Bool, Bool, ItemCollectionId?)->Void
    public let showPack:(StickerPackReference)->Void
    public let navigate:(ItemCollectionViewEntryIndex)->Void
    public let addPack: (StickerPackReference)->Void
    public let clearRecent:()->Void
    public let removePack:(StickerPackCollectionId)->Void
    public let closeInlineFeatured:(Int64)->Void
    public let openFeatured:(FeaturedStickerPackItem)->Void
    public let selectEmojiCategory:(EmojiSearchCategories.Group?)->Void
    public let mode: EntertainmentViewController.Mode
    public let canSchedule:()->Bool
    public var createSticker: ((Control)->Void)?
    public var dragSticker: ((TelegramMediaFile, CGImage?, EntertainmentStickerDrag) -> Bool)?
    public init(context: any AccountContextProtocol, sendMedia: @escaping(Media, NSView, Bool, Bool, ItemCollectionId?)->Void, showPack: @escaping(StickerPackReference)->Void, addPack: @escaping(StickerPackReference)->Void, navigate: @escaping(ItemCollectionViewEntryIndex)->Void, clearRecent:@escaping()->Void, removePack:@escaping(StickerPackCollectionId)->Void, closeInlineFeatured:@escaping(Int64)->Void, openFeatured:@escaping(FeaturedStickerPackItem)->Void, selectEmojiCategory:@escaping(EmojiSearchCategories.Group?)->Void, mode: EntertainmentViewController.Mode, canSchedule:@escaping()->Bool) {
        self.context = context
        self.sendMedia = sendMedia
        self.showPack = showPack
        self.addPack = addPack
        self.navigate = navigate
        self.clearRecent = clearRecent
        self.removePack = removePack
        self.closeInlineFeatured = closeInlineFeatured
        self.openFeatured = openFeatured
        self.mode = mode
        self.selectEmojiCategory = selectEmojiCategory
        self.canSchedule = canSchedule
    }
}

public struct SpecificPackData : Equatable {
    public let info: StickerPackCollectionInfo
    public let peer: Peer
    
    public static func ==(lhs: SpecificPackData, rhs: SpecificPackData) -> Bool {
        if lhs.info != rhs.info {
            return false
        } else if !lhs.peer.isEqual(rhs.peer) {
            return false
        } else {
            return true
        }
    }
}

public enum PackEntry: Comparable, Identifiable {
    case stickerPack(index:Int, stableId: StickerPackCollectionId, info: StickerPackCollectionInfo, topItem: StickerPackItem?, allItems: [StickerPackItem])
    case recent
    case premium
    case saved
    case featured(hasUnread: Bool)
    case specificPack(data: SpecificPackData)
    
    public var stableId: StickerPackCollectionId {
        switch self {
        case let .stickerPack(_, stableId, _, _, _):
            return stableId
        case .recent:
            return .recent
        case .premium:
            return .premium
        case .saved:
            return .saved
        case let .featured(hasUnread):
            return .featured(hasUnred: hasUnread)
        case let .specificPack(data):
            return .specificPack(data.info.id)
        }
    }
    
    public var index: Int {
        switch self {
        case .featured:
            return -1
        case .saved:
            return 0
        case .recent:
            return 2
        case .premium:
            return 3
        case .specificPack:
            return 4
        case let .stickerPack(index, _, _, _, _):
            return 5 + index
        }
    }
    
    public static func <(lhs: PackEntry, rhs: PackEntry) -> Bool {
        return lhs.index < rhs.index
    }
    
    
}


private enum StickerPacksUpdate {
    case generic(animated: Bool, scrollToTop: Bool?)
    case scroll(animated: Bool)
    case navigate(StickerPacksIndex, animated: Bool)
}


private enum StickerPacksIndex : Hashable, Comparable {
    case sticker(ItemCollectionViewEntryIndex)
    case speficicPack(ItemCollectionId)
    case recent(Int)
    case premium(Int)
    case saved(Int)
    case featured(Int, Bool)
    case emojiRelated(Int)
    case whitespace(Int)
    var packIndex:ItemCollectionViewEntryIndex {
        switch self {
        case let .sticker(index):
            return index
        case let .saved(index), let .recent(index), let .premium(index), let .featured(index, _), let .emojiRelated(index):
            return ItemCollectionViewEntryIndex.lowerBound(collectionIndex: Int32(index), collectionId: ItemCollectionId(namespace: 0, id: 0))
        case let .speficicPack(id):
            return ItemCollectionViewEntryIndex.lowerBound(collectionIndex: 2, collectionId: id)
        case .whitespace:
            return ItemCollectionViewEntryIndex.lowerBound(collectionIndex: 0, collectionId: ItemCollectionId(namespace: 0, id: 0))
        }
    }
    
    var collectionId: StickerPackCollectionId {
        switch self {
        case let .sticker(index):
            return .pack(index.collectionId)
        case .recent:
            return .recent
        case .premium:
            return .premium
        case .saved:
            return .saved
        case let .speficicPack(id):
            return .specificPack(id)
        case let .featured(_, hasUnread):
            return .featured(hasUnred: hasUnread)
        case .emojiRelated:
            return .emojiRelated
        case let .whitespace(index):
            return .whitespace(Int32(index))
        }
    }
    
    func hash(into hasher: inout Hasher) {
        
    }
    
    var index: Int {
        switch self {
        case .emojiRelated:
            return -2
        case .featured:
            return -1
        case .saved:
            return 0
        case .recent:
            return 1
        case .premium:
            return 2
        case .speficicPack:
            return 3
        case .sticker:
            return 4
        case .whitespace(_):
            return -2
        }
    }
    
    static func <(lhs: StickerPacksIndex, rhs: StickerPacksIndex) -> Bool {
        switch lhs {
        case let .sticker(lhsIndex):
            if case let .sticker(rhsIndex) = rhs {
                return lhsIndex < rhsIndex
            } else {
                return lhs.index < rhs.index
            }
        default:
            return lhs.index < rhs.index
        }
    }
}

private enum StickerPacksScrollState: Equatable {
    static func == (lhs: StickerPacksScrollState, rhs: StickerPacksScrollState) -> Bool {
        switch lhs {
        case .initial:
            if case .initial = rhs {
                return true
            } else {
                return false
            }
        case let .loadFeaturedMore(lhsFound):
            if case .loadFeaturedMore(let rhsFound) = rhs {
                return lhsFound.sets.infos.map { $0.0 } == rhsFound.sets.infos.map { $0.0 }
            } else {
                return false
            }
        case let .scroll(aroundIndex):
            if case .scroll(aroundIndex) = rhs {
                return true
            } else {
                return false
            }
        case let .navigate(aroundIndex):
            if case .navigate(aroundIndex) = rhs {
                return true
            } else {
                return false
            }
        }
    }
    
    case initial
    case loadFeaturedMore(StickerPacksSearchData)
    case scroll(aroundIndex: StickerPacksIndex)
    case navigate(index: StickerPacksIndex)
}

private struct StickerPacksSearchData {
    let sets: FoundStickerSets
    let loading: Bool
    let basicFeaturedCount: Int
    let emojiRelated: [FoundStickerItem]
    let premiumStickers: [TelegramMediaFile]
}

private struct StickerPacksUpdateData {
    let view: ItemCollectionsView?
    let update: StickerPacksUpdate
    let specificPack:Tuple2<PeerSpecificStickerPackData, Peer>?
    let searchData: StickerPacksSearchData?
    let hasUnread: Bool
    let featured: [FeaturedStickerPackItem]
    let settings: StickerSettings
    let mode: EntertainmentViewController.Mode
    let state: State
    
    
    init(view: ItemCollectionsView?, update: StickerPacksUpdate, specificPack: Tuple2<PeerSpecificStickerPackData, Peer>?, searchData: StickerPacksSearchData? = nil, hasUnread: Bool, featured: [FeaturedStickerPackItem], settings: StickerSettings = .defaultSettings, mode: EntertainmentViewController.Mode, state: State) {
        self.view = view
        self.update = update
        self.specificPack = specificPack
        self.searchData = searchData
        self.hasUnread = hasUnread
        self.featured = featured
        self.settings = settings
        self.mode = mode
        self.state = state
    }

    func withUpdatedHasUnread(_ hasUnread: Bool) -> StickerPacksUpdateData {
        return .init(view: self.view, update: self.update, specificPack: self.specificPack, searchData: self.searchData, hasUnread: hasUnread, featured: self.featured, settings: self.settings, mode: self.mode, state: self.state)
    }
}
public enum StickerPackInfo : Equatable {
    case pack(StickerPackCollectionInfo?, installed: Bool, featured: Bool)
    case speficicPack(StickerPackCollectionInfo?)
    case recent
    case premium
    case saved
    case emojiRelated
    
    public var installed: Bool {
        switch self {
        case let .pack(_, installed, _):
            return installed
        default:
            return false
        }
    }
    public var featured: Bool {
        switch self {
        case let .pack(_, _, featured):
            return featured
        default:
            return false
        }
    }
}

public enum StickerPackCollectionId : Hashable {
    case pack(ItemCollectionId)
    case recent
    case premium
    case featured(hasUnred: Bool)
    case specificPack(ItemCollectionId)
    case saved
    case inlineFeatured(hasUnred: Bool)
    case emojiRelated
    case whitespace(Int32)
    public var itemCollectionId:ItemCollectionId? {
        switch self {
        case let .pack(collectionId):
            return collectionId
        case let .specificPack(collectionId):
            return collectionId
        default:
            return nil
        }
    }
    
}


private enum StickerPackEntry : TableItemListNodeEntry {
    case whitespace(Int32, CGFloat)
    case pack(index: StickerPacksIndex, files:[TelegramMediaFile], packInfo: StickerPackInfo, collectionId: StickerPackCollectionId, hasCreate: Bool = false)
    case trending(index: StickerPacksIndex, featured: [FeaturedStickerPackItem], collectionId: StickerPackCollectionId)
    
    static func < (lhs: StickerPackEntry, rhs: StickerPackEntry) -> Bool {
        return lhs.index < rhs.index
    }
    
    static func == (lhs: StickerPackEntry, rhs: StickerPackEntry) -> Bool {
        switch lhs {
        case let .whitespace(index, value):
            if case .whitespace(index, value) = rhs {
                return true
            } else {
                return false
            }
         case let .pack(index, lhsFiles, packInfo, collectionId, hasCreate):
            if case .pack(index, let rhsFiles, packInfo, collectionId, hasCreate) = rhs {
                if lhsFiles.count != rhsFiles.count {
                    return false
                } else {
                    for (i, lhsFile) in lhsFiles.enumerated() {
                        if !lhsFile.isEqual(to: rhsFiles[i]) {
                            return false
                        }
                    }
                }
                return true
            } else {
                return false
            }
        case let .trending(index, lhsFeatured, collectionId):
            if case .trending(index, let rhsFeatured, collectionId) = rhs {
                if lhsFeatured.count != rhsFeatured.count {
                    return false
                } else {
                    for (i, lhsItem) in lhsFeatured.enumerated() {
                        if lhsItem.info.id != rhsFeatured[i].info.id {
                            return false
                        }
                    }
                }
                return true
            } else {
                return false
            }
        }
    }
    
    var index: StickerPacksIndex {
        switch self {
        case let .pack(index, _, _, _, _):
            return index
        case let .trending(index, _, _):
            return index
        case let .whitespace(index, _):
            return .whitespace(Int(index))
        }
    }
    
    var stableId: StickerPackCollectionId {
        switch self {
        case let .pack(_, _, _, collectionId, _):
            return collectionId
        case let .trending(_, _, collectionId):
            return collectionId
        case let .whitespace(index, _):
            return .whitespace(index)
        }
    }
    
    func item(_ arguments: StickerPanelArguments, initialSize: NSSize) -> TableRowItem {
        switch self {
        case let .whitespace(_, value):
            return GeneralRowItem.init(initialSize, height: value, stableId: stableId)
        case let .pack(_, files, packInfo, collectionId, hasCreate):
            let addTile = hasCreate ? arguments.createSticker.map { action in
                return StickerPackPanelAddTile(position: .leading, accessibilityLabel: strings().stickersViewControllerCreateSticker, action: action)
            } : nil
            return StickerPackPanelRowItem(initialSize, context: arguments.context, arguments: arguments, files: files, packInfo: packInfo, collectionId: collectionId, canSend: true, addTile: addTile)
        case let .trending(_, items, collectionId):
            return StickerPackTrendingItem(initialSize, context: arguments.context, featured: items, collectionId: collectionId, close: arguments.closeInlineFeatured, click: arguments.openFeatured)
        }
    }
}

private func stickersEntries(view: ItemCollectionsView?, context: any AccountContextProtocol, featured:[FeaturedStickerPackItem], settings: StickerSettings, searchData: StickerPacksSearchData?, specificPack:Tuple2<PeerSpecificStickerPackData, Peer>?, mode: EntertainmentViewController.Mode) -> [StickerPackEntry] {
    var entries:[StickerPackEntry] = []
    var index: Int32 = 0

    
    entries.append(.whitespace(index, 46))
    index += 1
    
    if let view = view {
        var available: [ItemCollectionViewEntry] = view.entries
        
       
        
        var ids:[MediaId : MediaId] = [:]
        
        if view.lower == nil {
            
          
            
            if !view.orderedItemListsViews[1].items.isEmpty {
                var files:[TelegramMediaFile] = []
                for item in view.orderedItemListsViews[1].items {
                    if let entry = item.contents.get(SavedStickerItem.self) {
                        if let id = entry.file._parse().id, ids[id] == nil {
                            if !entry.file.isPremiumSticker || !context.premiumIsBlocked {
                                ids[id] = id
                                files.append(entry.file._parse())
                            }
                        }
                    }
                }
                if !files.isEmpty {
                    entries.append(.pack(index: .saved(0), files: files, packInfo: .saved, collectionId: .saved))
                }
            }
            
            if !featured.isEmpty, mode == .common {
                if settings.trendingClosedOn != featured.first?.info.id.id {
                  //  entries.append(.trending(index: .saved(1), featured: featured, collectionId: .inlineFeatured(hasUnred: featured.contains(where: { $0.unread }))))
                }
            }
            

            
            if !view.orderedItemListsViews[0].items.isEmpty {
                var files:[TelegramMediaFile] = []
                for item in view.orderedItemListsViews[0].items {
                    if let entry = item.contents.get(RecentMediaItem.self) {
                        let file = entry.media._parse()
                        if let id = file.id, ids[id] == nil, file.isStaticSticker || file.isAnimatedSticker {
                            if !file.isPremiumSticker || !context.premiumIsBlocked {
                                ids[id] = id
                                files.append(file)
                            }
                        }
                    }
                    if files.count == 20 {
                        break
                    }
                }
                if !files.isEmpty {
                    entries.append(.pack(index: .recent(1), files: files, packInfo: .recent, collectionId: .recent))
                }
            }
            
//            if !view.orderedItemListsViews[2].items.isEmpty, context.isPremium {
//                var files:[TelegramMediaFile] = []
//                for item in view.orderedItemListsViews[2].items {
//                    if let entry = item.contents.get(RecentMediaItem.self) {
//                        let file = entry.media
//                        if let id = file.id, ids[id] == nil, file.isStaticSticker || file.isAnimatedSticker {
//                            if !file.isPremiumSticker || !context.premiumIsBlocked {
//                                ids[id] = id
//                                files.append(file)
//                            }
//                        }
//                    }
//                }
//                if !files.isEmpty {
//                    entries.append(.pack(index: .premium(2), files: files, packInfo: .premium, collectionId: .premium))
//                }
//            }
            
            if let specificPack = specificPack, let info = specificPack._0.packInfo {
                var files:[TelegramMediaFile] = []
                for item in info.1 {
                    if let item = item as? StickerPackItem {
                        let file = item.file._parse()
                        if let id = file.id, ids[id] == nil, file.isStaticSticker || file.isAnimatedSticker {
                            if !file.isPremiumSticker || !context.premiumIsBlocked {
                                ids[id] = id
                                files.append(file)
                            }
                        }
                    }
                }
                if !files.isEmpty {
                    entries.append(.pack(index: .speficicPack(info.0.id), files: files, packInfo: .speficicPack(info.0._parse()), collectionId: .specificPack(info.0.id)))
                }
            }
            
        }
        
        for (id, info, item) in view.collectionInfos {
            if !available.isEmpty, let item = item {
                var files: [TelegramMediaFile] = []
                if let info = info as? StickerPackCollectionInfo {
                    let items = available.enumerated().reversed()
                    for (i, entry) in items {
                        if entry.index.collectionId == info.id {
                            if let item = available.remove(at: i).item as? StickerPackItem {
                                let file = item.file._parse()
                                if !file.isPremiumSticker || !context.premiumIsBlocked {
                                    files.insert(file, at: 0)
                                }
                            }
                        }
                    }
                    if !files.isEmpty {
                        entries.append(.pack(index: .sticker(ItemCollectionViewEntryIndex(collectionIndex: index, collectionId: id, itemIndex: item.index)), files: files, packInfo: .pack(info, installed: true, featured: false), collectionId: .pack(id)))
                    }
                }
            } else {
                break
            }
            index += 1
        }
        
        if mode == .common, view.lower == nil, let createIndex = entries.firstIndex(where: { entry in
            if case let .pack(_, _, packInfo, _, _) = entry {
                switch packInfo {
                case .recent, .speficicPack, .pack:
                    return true
                default:
                    return false
                }
            }
            return false
        }), case let .pack(packIndex, files, packInfo, collectionId, _) = entries[createIndex] {
            entries[createIndex] = .pack(index: packIndex, files: files, packInfo: packInfo, collectionId: collectionId, hasCreate: true)
        }
    } else if let searchData = searchData {
        if !searchData.loading {
            var available = searchData.sets.entries
            var index: Int32 = 0
            
            if !searchData.emojiRelated.isEmpty {
                
                var validIds:Set<MediaId> = Set()
                
                let files:[TelegramMediaFile] = searchData.emojiRelated.map { $0.file }.reduce([], { current, value in
                    var current = current
                    guard let id = value.id else {
                        return current
                    }
                    if !validIds.contains(id) {
                        validIds.insert(id)
                        current.append(value)
                    }
                    return current
                }).sorted(by: { lhs, rhs in
                    if lhs.isAnimatedSticker && !rhs.isAnimatedSticker {
                        return true
                    } else {
                        return false
                    }
                })
                entries.append(.pack(index: .emojiRelated(0), files: files, packInfo: .emojiRelated, collectionId: .emojiRelated))
                
                index += 1
            }
            if mode == .common {
                for set in searchData.sets.infos {
                    if !available.isEmpty {
                        var files: [TelegramMediaFile] = []
                        if let info = set.1 as? StickerPackCollectionInfo {
                            let items = available.enumerated().reversed()
                            for (i, entry) in items {
                                if entry.index.collectionId == info.id {
                                    if let item = available.remove(at: i).item as? StickerPackItem {
                                        files.insert(item.file._parse(), at: 0)
                                    }
                                }
                            }
                            if !files.isEmpty {
                                entries.append(.pack(index: .sticker(ItemCollectionViewEntryIndex(collectionIndex: index, collectionId: info.id, itemIndex: .init(index: 0, id: 0))), files: Array(files.prefix(5)), packInfo: .pack(info, installed: set.3, featured: true), collectionId: .pack(info.id)))
                            }
                        }
                    } else {
                        break
                    }
                    index += 1
                }
                if !searchData.premiumStickers.isEmpty {
                    _ = ItemCollectionId(namespace: 0, id: 0)
                    entries.append(.pack(index: .premium(0), files: searchData.premiumStickers, packInfo: .premium, collectionId: .premium))
                }
            }
        }
       
    }
    
    return entries
}

private func packEntries(view: ItemCollectionsView?, context: any AccountContextProtocol, specificPack:Tuple2<PeerSpecificStickerPackData, Peer>?, hasUnread: Bool, featured:[FeaturedStickerPackItem], settings: StickerSettings, mode: EntertainmentViewController.Mode) -> [PackEntry] {
    var entries:[PackEntry] = []
    var index: Int = 0
    
    if let view = view {
        if !featured.isEmpty, mode == .common {
            entries.append(.featured(hasUnread: hasUnread))
        }
        
        if !view.orderedItemListsViews[1].items.isEmpty {
            entries.append(.saved)
        }
        if !view.orderedItemListsViews[0].items.isEmpty {
            entries.append(.recent)
        }
//        if !view.orderedItemListsViews[2].items.isEmpty, context.isPremium {
//            if context.isPremium || !context.premiumIsBlocked {
//                entries.append(.premium)
//            }
//        }
        if let specificPack = specificPack, let info = specificPack._0.packInfo?.0 {
            entries.append(.specificPack(data: SpecificPackData(info: info._parse(), peer: specificPack._1)))
        }
        
        for (_, info, item) in view.collectionInfos {
            var files: [StickerPackItem] = []
            if let info = info as? StickerPackCollectionInfo {
                let items = view.entries.enumerated()
                for (_, entry) in items {
                    if entry.index.collectionId == info.id {
                        if let item = entry.item as? StickerPackItem {
                            files.append(item)
                        }
                    }
                }
            }
            if let info = info as? StickerPackCollectionInfo {
                entries.append(.stickerPack(index: index, stableId: .pack(info.id), info: info, topItem: item as? StickerPackItem, allItems: files))
                index += 1
            }
        }
    }

    return entries
}


private func prepareStickersTransition(from:[AppearanceWrapperEntry<StickerPackEntry>], to: [AppearanceWrapperEntry<StickerPackEntry>], initialSize: NSSize, arguments: StickerPanelArguments, update: StickerPacksUpdate) -> TableUpdateTransition {
    let (removed,inserted,updated) = proccessEntriesWithoutReverse(from, right: to, { entry -> TableRowItem in
        return entry.entry.item(arguments, initialSize: initialSize)
    })
    let state: TableScrollState
    var anim: Bool
    switch update {
    case let .generic(animated, scrollToTop):
        anim = animated
        if let scrollToTop = scrollToTop {
            if scrollToTop {
                state = .up(animated)
            } else {
                state = .saveVisible(.lower, false)
            }
        } else {
            state = .none(nil)
        }
        
    case let .scroll(animated):
        state = .saveVisible(.upper, false)
        anim = animated
    case let .navigate(index, animated):
        state = .top(id: index.collectionId, innerId: nil, animated: true, focus: .init(focus: false), inset: 0)
        anim = animated
    }
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: anim, state: state, grouping: !anim, animateVisibleOnly: false)
}

fileprivate func preparePackTransition(from:[AppearanceWrapperEntry<PackEntry>]?, to:[AppearanceWrapperEntry<PackEntry>], context: any AccountContextProtocol, initialSize:NSSize) -> TableUpdateTransition {
    
    let (deleted,inserted,updated) = proccessEntriesWithoutReverse(from, right: to, { (entry) -> TableRowItem in
        switch entry.entry {
        case let .stickerPack(index, stableId, info, topItem, allItems):
            return StickerPackRowItem(initialSize, stableId: stableId, packIndex: index, isPremium: false, context: context, info: info, topItem: topItem, allItems: allItems)
        case .recent:
            return RecentPackRowItem(initialSize, entry.entry.stableId)
        case .premium:
            return RecentPackRowItem(initialSize, entry.entry.stableId)
        case .featured:
            return RecentPackRowItem(initialSize, entry.entry.stableId)
        case .saved:
            return RecentPackRowItem(initialSize, entry.entry.stableId)
        case let .specificPack(data):
            return StickerSpecificPackItem(initialSize, stableId: entry.entry.stableId, specificPack: (data.info, data.peer), account: context.account)
        }
    })
    
    return TableUpdateTransition(deleted: deleted, inserted: inserted, updated:updated, animated: true, state: .none(nil))
    
}

private func stickerSearchHasResults(_ table: TableView) -> Bool {
    var hasResults = false
    table.enumerateItems(with: { item in
        if item is StickerPackPanelRowItem {
            hasResults = true
            return false
        }
        return true
    })
    return hasResults
}

public class NStickersView : View {
    let tableView:TableView = TableView(frame: NSZeroRect)
    fileprivate var restrictedView:RestrictionWrappedView?
    private let searchStatusView = PanelSearchStatusView(frame: .zero)
    private var searchStatus: PanelSearchPresentation = .hidden
    private var searchPresentationTheme: TelegramPresentationTheme?
    
    public let searchView = SearchView(frame: .zero)
    private let searchContainer = View()
    fileprivate let packsView:HorizontalTableView = HorizontalTableView(frame: NSZeroRect)
    private let separator:View = View()
    fileprivate let tabsContainer: View = View()
    private let selectionView: View = View(frame: NSMakeRect(0, 0, 36, 36))
    private let searchBorder = View()
    
    fileprivate var categories: AnimatedEmojiesCategories?
    fileprivate var closeCategories: BackCategoryControl?


    private let searchInside = View()
    private let searchBackdrop = View()

    public var isGlass: Bool = false {
        didSet {
            if oldValue != isGlass {
                updateLocalizationAndTheme(theme: presentation ?? theme)
                needsLayout = true
            }
        }
    }
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        addSubview(tableView)
                
        searchView.isLeftOrientated = true
        searchView.layer?.cornerRadius = 15

        searchInside.addSubview(searchView)

        addSubview(searchContainer)
        
        searchContainer.addSubview(searchBackdrop)
        searchContainer.addSubview(searchInside)
        searchContainer.addSubview(searchBorder)
        
        tabsContainer.addSubview(selectionView)
        tabsContainer.addSubview(packsView)
        tabsContainer.addSubview(separator)
        addSubview(tabsContainer)
        addSubview(searchStatusView)
        
        
        packsView.getBackgroundColor = {
            .clear
        }
        
        self.packsView.addScroll(listener: .init(dispatchWhenVisibleRangeUpdated: false, { [weak self] position in
            self?.updateSelectionState(animated: false)
        }))
        
        tableView.scrollerInsets = .init(left: 0, right: 0, top: 46, bottom: 50)
        
        self.tableView.addScroll(listener: .init(dispatchWhenVisibleRangeUpdated: false, { [weak self] position in
            self?.updateScrollerSearch()
        }))
        
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    private func updateScrollerSearch() {
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    
    public func updateRestricion(_ peer: Peer?, cachedData: CachedPeerData?, animated: Bool) {
        if let peer = peer, let text = permissionText(from: peer, for: .banSendStickers, cachedData: cachedData) {
            let current: RestrictionWrappedView
            if let view = self.restrictedView {
                current = view
            } else {
                current = RestrictionWrappedView(text)
                self.restrictedView = current
                addSubview(current)
            }
            current.update(text)
        } else if let view = self.restrictedView {
            performSubviewRemoval(view, animated: animated)
            self.restrictedView = nil
        }
        needsLayout = true
    }
    
    func updateSearchStatus(isSearching: Bool, isLoading: Bool) {
        searchStatus = .resolve(isSearching: isSearching, isLoading: isLoading, hasResults: !isSearching || stickerSearchHasResults(tableView))
        searchStatusView.updateSearchStatus(searchStatus, kind: .stickers, query: searchView.query, theme: searchPresentationTheme ?? theme)
        needsLayout = true
    }

    private var searchState: SearchState? = nil
    
    public func updateSearchState(_ searchState: SearchState, animated: Bool) {
        let previous = self.searchState
        self.searchState = searchState

        let transition: ContainedViewLayoutTransition
        if animated {
            transition = .animated(duration: 0.2, curve: .easeOut)
        } else {
            transition = .immediate
        }
        updateSelectionState(animated: animated)
        self.updateLayout(size: frame.size, transition: transition)

        if previous?.state != searchState.state {
            self.tableView.scroll(to: .up(animated))
            self.moveCategories(nil)
        }
        
    }
    
    public func updateSelectionState(animated: Bool) {
        
      
        
        let transition: ContainedViewLayoutTransition
        if animated {
            transition = .animated(duration: 0.2, curve: .easeOut)
        } else {
            transition = .immediate
        }
        
        let theme = presentation ?? theme
        
        let currentClose: BackCategoryControl
        if state?.selectedEmojiCategory != nil, let context = context {
            if let view = self.closeCategories {
                currentClose = view
            } else {
                currentClose = .init(frame: NSMakeRect(searchView.frame.minX, searchView.frame.minY, 30, 30), context: context, presentation: theme)
                self.closeCategories = currentClose
                searchInside.addSubview(currentClose)
                
                currentClose.set(handler: { [weak self] _ in
                    self?.arguments?.selectEmojiCategory(nil)
                }, for: .Click)
            }
            self.searchView.updateSearchHolderVisibility(visible: false, transition: .immediate)
        } else {
            if let view = self.closeCategories {
                view.close()
                delay(0.4, closure: { [weak self, weak view] in
                    view?.removeFromSuperview()
                    if self?.closeCategories == nil {
                        self?.searchView.updateSearchHolderVisibility(visible: true, transition: .immediate)
                    }
                })
                self.closeCategories = nil
            }
        }
        
        if searchState == nil || searchState?.state == .None, let groups = self.state?.searchCategories?.groups, let context = context {
            let current: AnimatedEmojiesCategories
            
            
            if let view = self.categories {
                current = view
            } else {
                current = AnimatedEmojiesCategories(frame: categoryRect, presentation: presentation)
                self.categories = current
                searchInside.addSubview(current)
                
                current.select = { [weak self] category in
                    self?.arguments?.selectEmojiCategory(category)
                }
            }
            
            current.userInteractionEnabled = current.selected != nil
           
            if current.selected != state?.selectedEmojiCategory, current.selected == nil || state?.selectedEmojiCategory == nil {
                self.moveCategories(nil)
            }
            
            current.update(categories: groups, context: context, selected: self.state?.selectedEmojiCategory, animated: animated)
            current.scrollView.applyExternalScroll = { [weak self] event in
                return self?.moveCategories(event) ?? false
            }
            
            
            current.updateScroll()
            
            
            self.searchView.externalScroll = { [weak current] event in
                if current?.mouseInside() == false {
                    current?.scrollView.scrollWheel(with: event)
                }
            }
            
        } else if let view = self.categories {
            performSubviewRemoval(view, animated: animated)
            if animated {
                view.layer?.animatePosition(from: view.frame.origin, to: categoryRect.origin, duration: 0.2, removeOnCompletion: false)
                view.layer?.animateBounds(from: view.frame.size.bounds, to: categoryRect.size.bounds, duration: 0.2, removeOnCompletion: false)
            }
            self.categories = nil
            self.searchView.externalScroll = nil
            
        }
        
        var animated = animated
        var item = packsView.selectedItem()
        if item == nil, let value = packsView.item(stableId: AnyHashable(StickerPackCollectionId.saved)) {
            item = value
            animated = false
        }
                
        guard let item = item, let view = item.view else {
            return
        }
        
        let point = packsView.clipView.destination ?? packsView.contentOffset
        let rect = NSMakeRect(view.frame.origin.y - point.y, 5, item.height, packsView.frame.height)
        
        selectionView.layer?.cornerRadius = item.height == item.width ? .cornerRadius : item.width / 2
        selectionView.background = isGlass ? theme.colors.vibrant.mixedWith(NSColor(0x000000), alpha: 0.1) : theme.colors.grayBackground
        if animated {
            selectionView.layer?.animateCornerRadius()
        }
        transition.updateFrame(view: selectionView, frame: rect)
        updateLocalizationAndTheme(theme: presentation ?? theme)
    }
    private var state: State?
    private var context: (any AccountContextProtocol)?
    private var arguments: StickerPanelArguments?
    
    public var presentation: TelegramPresentationTheme? {
        didSet {
            categories?.presentation = presentation
        }
    }
    
    fileprivate func update(data: StickerPacksUpdateData, context: any AccountContextProtocol, arguments: StickerPanelArguments?, animated: Bool) {
        self.state = data.state
        self.context = context
        self.arguments = arguments
        
        let transition: ContainedViewLayoutTransition
        if animated {
            transition = .animated(duration: 0.2, curve: .easeInOut)
        } else {
            transition = .immediate
        }
        self.updateLayout(size: self.frame.size, transition: transition)
    }
    
    
    @discardableResult public func moveCategories(_ event: NSEvent?) -> Bool {
        let transition: ContainedViewLayoutTransition = event == nil ? .animated(duration: 0.2, curve: .easeInOut) : .immediate
        if let view = self.categories {
            if let event = event, state?.selectedEmojiCategory == nil {
                let previous = view.scrollView.contentView.bounds.origin
                let point = view.scrollView.makeScrollPoint(event)
                let difference = previous.x - point.x
                var rect = view.frame.insetBy(dx: difference, dy: 0)
                
                var accept: Bool = previous.x == 0

                if accept {
                    
                    let minX = searchView.frame.minX + searchView.searchSize.width
                    
                    if rect.origin.x < minX {
                        accept = false
                    } else if rect.origin.x > searchContainer.frame.width - categoryRect.width - searchView.frame.minX {
                        accept = false
                    }
                    rect.size.width = min(searchView.frame.width - searchView.searchSize.width, max(categoryRect.width, rect.width))
                    rect.origin.x = max(minX, searchContainer.frame.width - rect.width - searchView.frame.minX)
                    transition.updateFrame(view: view, frame: rect)
                    
                    let maxX = (searchView.frame.minX + searchView.holderSize.width)
                    
                    let sInset = maxX - rect.origin.x
                    let sOpacity: CGFloat = 1 - sInset / minX
                    searchView.movePlaceholder(-sInset, opacity: sOpacity, transition: transition)
                }
                view.updateScroll()
                
                return accept
            } else {
                if let _ = state?.selectedEmojiCategory {
                    transition.updateFrame(view: view, frame: revealedCategoryRect)
                    searchView.movePlaceholder(-((searchView.frame.minX + searchView.holderSize.width) - revealedCategoryRect.minX), opacity: 0, transition: transition)
                } else {
                    transition.updateFrame(view: view, frame: categoryRect)
                    searchView.movePlaceholder(nil, opacity: 1, transition: transition)
                    view.scrollView.clipView.scroll(to: .zero, animated: transition.isAnimated)
                }
                view.updateLayout(size: view.frame.size, transition: transition)
            }
        } else {
            searchView.movePlaceholder(nil, opacity: 1, transition: transition)
        }
        return false
    }
    
    public var categoryRect: NSRect {
        let width = searchView.frame.width - searchView.holderSize.width
        let rect = NSMakeRect(searchContainer.frame.width - (width + searchView.frame.minX), searchView.frame.minY, width, 30)
        return rect
    }
    public var revealedCategoryRect: NSRect {
        let width = searchView.frame.width - searchView.searchSize.width
        return NSMakeRect(searchContainer.frame.width - (width + searchView.frame.minX), searchView.frame.minY, width, 30)
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        self.restrictedView?.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)
        let background: NSColor = isGlass ? .clear : theme.colors.background
        let border: NSColor = isGlass ? theme.colors.grayIcon.withAlphaComponent(0.1) : theme.colors.border
        self.separator.backgroundColor = border
        self.tableView.updateLocalizationAndTheme(theme: theme)
        self.tableView.backgroundColor = background
        self.tableView.documentView?.background = background
        searchPresentationTheme = theme
        self.searchStatusView.updateSearchStatus(searchStatus, kind: .stickers, query: searchView.query, theme: theme)
        self.searchContainer.backgroundColor = background
        self.tabsContainer.backgroundColor = background
        self.searchBorder.backgroundColor = border
        self.searchBackdrop.backgroundColor = theme.colors.background.withAlphaComponent(0.85)
        self.searchBackdrop.isHidden = !isGlass

        if isGlass {
            let searchBackground = theme.colors.vibrant.mixedWith(NSColor(0x000000), alpha: 0.1)
            let searchTheme = SearchTheme(searchBackground, theme.search.searchImage, theme.search.clearImage, theme.search.placeholder, theme.search.textColor, theme.search.placeholderColor)
            self.searchView.searchTheme = searchTheme
            self.categories?.searchTheme = searchTheme
        } else {
            self.searchView.searchTheme = theme.search
            self.categories?.searchTheme = theme.search
        }
        self.searchView.updateLocalizationAndTheme(theme: theme)
    }
    
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        
        let inSearch = searchState?.state == .Focus || state?.selectedEmojiCategory != nil
        
        let initial: CGFloat = inSearch ? -46 : 0
        
        transition.updateFrame(view: tabsContainer, frame: NSMakeRect(0, initial, size.width, 46))
        transition.updateFrame(view: separator, frame: NSMakeRect(0, tabsContainer.frame.height - .borderSize, tabsContainer.frame.width, .borderSize))
        transition.updateFrame(view: packsView, frame: tabsContainer.focus(NSMakeSize(size.width, 36)))

        
        let dest = max(0, min(tableView.rectOf(index: 0).minY + (tableView.clipView.destination?.y ?? tableView.documentOffset.y), 46))

        let searchDest = inSearch ? 0 : dest
                
        
        transition.updateFrame(view: searchContainer, frame: NSMakeRect(0, tabsContainer.frame.maxY, size.width, 46 - min(searchDest, 46)))

        
        let searchInsideRect: CGRect = CGRect(origin: CGPoint(x: 0, y: searchContainer.frame.height - 46), size: NSMakeSize(size.width, 46))
        transition.updateFrame(view: searchInside, frame: searchInsideRect)

        
        transition.updateFrame(view: searchView, frame: searchInside.focus(NSMakeSize(size.width - 16, 30)))
        transition.updateFrame(view: searchBorder, frame: NSMakeRect(0, searchContainer.frame.height - .borderSize, size.width, .borderSize))
        let alpha: CGFloat = inSearch && tableView.documentOffset.y > 0 ? 1 : 0
        transition.updateAlpha(view: searchBorder, alpha: alpha)
        if isGlass {
            transition.updateAlpha(view: searchBackdrop, alpha: alpha)
        }
        transition.updateFrame(view: searchBackdrop, frame: searchInsideRect)
        
        if let categories = categories {
            transition.updateFrame(view: categories, frame: categories.centerFrameY(x: searchInside.frame.width - categories.frame.width - searchView.frame.minX))
            categories.updateLayout(size: categories.frame.size, transition: transition)
        }

        
        
        if let restrictedView = restrictedView {
            transition.updateFrame(view: restrictedView, frame: size.bounds)
        }
        transition.updateFrame(view: tableView, frame: NSMakeRect(0, tabsContainer.frame.maxY, size.width, size.height))

                
        transition.updateFrame(view: searchStatusView, frame: NSMakeRect(0, searchContainer.frame.maxY, size.width, max(0, size.height - searchContainer.frame.maxY - 56)))
        
        
        self.updateSelectionState(animated: transition.isAnimated)

    }
    
    public override func layout() {
        super.layout()

        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}



public class NStickersViewController<Context: AccountContextProtocol>: TelegramGenericViewController<NStickersView, Context>, TableViewDelegate, Notifable {
    public override var defaultBarTitle: String {
        return localizedString("Telegram.NStickersViewController")
    }

    private let searchValue = ValuePromise<SearchState>(.init(state: .None, request: nil))
    private var searchState: SearchState = .init(state: .None, request: nil) {
        didSet {
            self.searchValue.set(searchState)
        }
    }
    private let position = ValuePromise<StickerPacksScrollState>(ignoreRepeated: true)
    private let disposable = MetaDisposable()
    private let searchStateDisposable = MetaDisposable()
    private let actionsDisposable = DisposableSet()
    private let specificPeerId = ValuePromise<PeerId>(PeerId(0), ignoreRepeated: true)
    private var listener: TableScrollListener!
    private var interactions: EntertainmentInteractions?
    private weak var chatInteraction: (any ChatInteractionProtocol)?
    
    private var updateState: (((State) -> State) -> Void)? = nil
    
    public var makeSearchCommand:((ESearchCommand)->Void)?
    
    
    public var mode: EntertainmentViewController.Mode = .common
    private var presentation: TelegramPresentationTheme?
    
    public init(_ context: Context, presentation: TelegramPresentationTheme? = nil) {
        self.presentation = presentation
        super.init(context)
        bar = .init(height: 0)
        _frameRect = NSMakeRect(0, 0, 350, 350)
    }
    
    
    private func updateSearchState(_ state: SearchState) {
        self.position.set(.initial)
        let changed = self.searchState.request.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased() != state.request.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased()
        self.searchState = state
        if changed && !state.request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.makeSearchCommand?(.loading)
        }
        if self.isLoaded() == true {
            self.genericView.updateSearchState(state, animated: true)
            self.genericView.tableView.scroll(to: .up(true))

        }
    }
    
    deinit {
        disposable.dispose()
        searchStateDisposable.dispose()
        actionsDisposable.dispose()
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: presentation ?? theme)
        self.genericView.packsView.updateLocalizationAndTheme(theme: presentation ?? theme)
    }
    
    public func update(with interactions:EntertainmentInteractions, chatInteraction: any ChatInteractionProtocol) {
        self.interactions = interactions
        self.chatInteraction?.remove(observer: self)
        self.chatInteraction = chatInteraction
        chatInteraction.add(observer: self)
        if isLoaded() {
            genericView.updateRestricion(chatInteraction.presentationPeer, cachedData: chatInteraction.presentationCachedData, animated: false)
        }
        self.specificPeerId.set(chatInteraction.peerId)
    }
    
    public func notify(with value: Any, oldValue: Any, animated: Bool) {
        if let value = value as? ChatPresentationSnapshot, let oldValue = oldValue as? ChatPresentationSnapshot {
            if let peer = value.snapshotPeer, let oldPeer = oldValue.snapshotPeer {
                if permissionText(from: peer, for: .banSendStickers, cachedData: value.snapshotCachedData) != permissionText(from: oldPeer, for: .banSendStickers, cachedData: oldValue.snapshotCachedData) {
                    genericView.updateRestricion(peer, cachedData: value.snapshotCachedData, animated: animated)
                }
            } else if (oldValue.snapshotPeer != nil) != (value.snapshotPeer != nil), let peer = value.snapshotPeer {
                genericView.updateRestricion(peer, cachedData: value.snapshotCachedData, animated: animated)
            }
        }
    }
    
    public func isEqual(to other: Notifable) -> Bool {
        return other === self
    }
    
    public func isSelectable(row: Int, item: TableRowItem) -> Bool {
        return true
    }
    public func selectionWillChange(row: Int, item: TableRowItem, byClick: Bool) -> Bool {
        return true
    }
    public func selectionDidChange(row:Int, item:TableRowItem, byClick:Bool, isNew:Bool) {
        if byClick, let collectionId = item.stableId.base as? StickerPackCollectionId {
            if let item = genericView.tableView.item(stableId: collectionId) {
                self.genericView.tableView.removeScroll(listener: self.listener)
                self.genericView.tableView.scroll(to: .top(id: item.stableId, innerId: nil, animated: true, focus: .init(focus: false), inset: 0), completion: { [weak self] _ in
                    if let `self` = self {
                        self.genericView.tableView.addScroll(listener: self.listener)
                    }
                })
            } else {
                var index: StickerPacksIndex? = nil
                switch collectionId {
                case let .pack(id):
                    if let item = item as? StickerPackRowItem {
                        index = .sticker(ItemCollectionViewEntryIndex.lowerBound(collectionIndex: Int32(item.packIndex), collectionId: id))
                    }
                case .featured, .inlineFeatured:
                    self.interactions?.toggleSearch()
                case .saved:
                    index = .saved(0)
                case .recent:
                    index = .recent(1)
                case .premium:
                    index = .premium(1)
                case let .specificPack(id):
                    index = .speficicPack(id)
                case .emojiRelated, .whitespace:
                    break
                }
                if let index = index {
                    self.genericView.tableView.removeScroll(listener: self.listener)
                    self.position.set(.navigate(index: index))
                }
            }
            genericView.updateSelectionState(animated: row != 0)
        }
    }
    public func findGroupStableId(for stableId: AnyHashable) -> AnyHashable? {
        return nil
    }
    
    private func shouldSendActivity(_ isPresent: Bool) {
        if let chatInteraction = chatInteraction {
            if chatInteraction.peerId.toInt64() != 0 {
                chatInteraction.interactionContext.account.updateLocalInputActivity(peerId: chatInteraction.activitySpace, activity: .choosingSticker, isPresent: isPresent)

            }
        }
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.shouldSendActivity(false)
    }
    
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let chatInteraction = chatInteraction {
            genericView.updateRestricion(chatInteraction.presentationPeer, cachedData: chatInteraction.presentationCachedData, animated: false)
        }
    }
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.genericView.updateSelectionState(animated: false)
        if let chatInteraction = chatInteraction {
            genericView.updateRestricion(chatInteraction.presentationPeer, cachedData: chatInteraction.presentationCachedData, animated: false)
        }
    }
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        
        genericView.presentation = presentation
        
        let context = self.context
        let initialSize = self.atomicSize
        
        let initialState = State()
        
        let statePromise = ValuePromise<State>(ignoreRepeated: true)
        let stateValue = Atomic(value: initialState)
        let updateState: ((State) -> State) -> Void = { f in
            statePromise.set(stateValue.modify (f))
        }
        
        self.updateState = { f in
            updateState(f)
        }
        
        genericView.tableView.addScroll(listener: TableScrollListener.init(dispatchWhenVisibleRangeUpdated: false, { [weak self] _ in
            self?.shouldSendActivity(true)
        }))
        
               
        let searchInteractions = SearchInteractions({ [weak self] state, _ in
            self?.updateState? { current in
                var current = current
                current.selectedEmojiCategory = nil
                return current
            }
            self?.updateSearchState(state)
        }, { [weak self] state in
            self?.updateState? { current in
                var current = current
                current.selectedEmojiCategory = nil
                return current
            }
            self?.updateSearchState(state)
        })
        
        genericView.searchView.searchInteractions = searchInteractions
        
        listener = TableScrollListener(dispatchWhenVisibleRangeUpdated: true, { [weak self] position in
            guard let `self` = self, position.visibleRows.length > 0 else {
                return
            }
            let item = self.genericView.tableView.item(at: position.visibleRows.location)
            self.genericView.packsView.changeSelection(stableId: item.stableId)
            self.genericView.packsView.scroll(to: .center(id: item.stableId, innerId: nil, animated: true, focus: .init(focus: false), inset: 0))
            self.genericView.updateSelectionState(animated: true)
        })

        self.genericView.packsView.delegate = self
        
        let previous:Atomic<[AppearanceWrapperEntry<StickerPackEntry>]> = Atomic(value: [])
        
        let foundPacks: Atomic<StickerPacksSearchData?> = Atomic(value: nil)
        
        let previousPacks:Atomic<[AppearanceWrapperEntry<PackEntry>]> = Atomic(value: [])

        let arguments = StickerPanelArguments(context: context, sendMedia: { [weak self] media, view, silent, schedule, collectionId in
            guard let `self` = self else { return }
            
            if let file = media as? TelegramMediaFile {
                if file.isPremiumSticker, !context.isPremium {
                    self.interactions?.showStickerPremium(file, view)
                    return
                }
            }
            
            if let chatInteraction = self.chatInteraction, let slowMode = chatInteraction.presentationSlowMode, slowMode.hasLocked {
                showSlowModeTimeoutTooltip(slowMode, for: view)
            } else if let file = media as? TelegramMediaFile {
                if !schedule, let chatInteraction = self.chatInteraction, let window = view.window {
                    let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                    if let layer = view.layer?.sublayers?.last(where: { !$0.isHidden && $0.frame.contains(point) }) {
                        EntertainmentUIHooks.shared.launchSendFlight(chatInteraction, view, layer.frame, layer)
                    }
                }
                self.interactions?.sendSticker(file, silent, schedule, collectionId)
            }
        }, showPack: { [weak self] reference in
            if let peerId = self?.chatInteraction?.peerId {
                showModal(with: EntertainmentUIHooks.shared.makeStickerPackPreview(context, peerId, [.stickers(reference)]), for: context.window)
            }
        }, addPack: { [weak self] reference in
            
            
            
            _ = showModalProgress(signal: context.engine.stickers.loadedStickerPack(reference: reference, forceActualized: false)
                |> filter { result in
                    switch result {
                    case .result:
                        return true
                    default:
                        return false
                    }
                }
                |> take(1)
                |> mapToSignal { result -> Signal<ItemCollectionId, NoError> in
                    switch result {
                    case let .result(info, items, _):
                        return context.engine.stickers.addStickerPackInteractively(info: info._parse(), items: items) |> map { _ in info.id }
                    default:
                        return .complete()
                    }
                }
                |> deliverOnMainQueue, for: context.window).start(next: { [weak self] result in
                    if let `self` = self {
                        if !self.searchState.request.isEmpty {
                            self.makeSearchCommand?(.close)
                            self.position.set(.navigate(index: StickerPacksIndex.sticker(ItemCollectionViewEntryIndex.lowerBound(collectionIndex: 0, collectionId: result))))
                        }
                    }
                })
        }, navigate: { [weak self] index in
            self?.position.set(.navigate(index: .sticker(index)))
        }, clearRecent: {
            verifyAlert_button(for: context.window, header: strings().stickersConfirmClearRecentHeader, information: strings().stickersConfirmClearRecentText, ok: strings().stickersConfirmClearRecentOK, successHandler: { _ in
                _ = context.engine.stickers.clearRecentlyUsedStickers().start()
            })
        }, removePack: { collectionId in
            if let id = collectionId.itemCollectionId {
                _ = showModalProgress(signal: context.engine.stickers.removeStickerPackInteractively(id: id, option: .delete), for: context.window).start()
            }
        }, closeInlineFeatured: { id in
            _ = updateStickerSettingsInteractively(postbox: context.account.postbox, {
                $0.withUpdatedTrendingClosedOn(id)
            }).start()
        }, openFeatured: { [weak self] featured in
            self?.genericView.searchView.change(state: .Focus, true)
        }, selectEmojiCategory: { [weak self] category in
            updateState { current in
                var current = current
                current.selectedEmojiCategory = category
                return current
            }
            let searchState: SearchState
            if let category = category {
                if category.kind == .premium {
                    searchState = .init(state: .None, request: "premium")
                } else {
                    searchState = .init(state: .None, request: category.identifiers.joined(separator: ""))
                }
            } else {
                searchState = .init(state: .None, request: nil)
            }
            self?.updateSearchState(searchState)
        }, mode: mode, canSchedule: { [weak self] in
            return self?.chatInteraction?.presentationSendPaidMessageStars == nil
        })
        
        arguments.dragSticker = { [weak self] file, image, drag in
            guard let dragItem = self?.interactions?.dragItem, !file.isPremiumSticker || context.isPremium else {
                return false
            }
            dragItem(.file(file), image, drag)
            return true
        }

        if #available(macOS 14.0, *), mode == .common {
            arguments.createSticker = { [weak self] _ in
                guard let self else { return }
                presentCreateSticker(context: context, chatInteraction: self.chatInteraction)
            }
        }
        
        let specificPackData: Signal<Tuple2<PeerSpecificStickerPackData, Peer>?, NoError> = self.specificPeerId.get() |> mapToSignal { peerId -> Signal<Peer?, NoError> in
            if peerId.toInt64() == 0 {
                return .single(nil)
            } else {
                return context.account.postbox.transaction {
                    $0.getPeer(peerId)
                }
            }
        } |> mapToSignal { peer -> Signal<Tuple2<PeerSpecificStickerPackData, Peer>?, NoError> in
            if let peer = peer, peer.isSupergroup {
                return context.engine.peers.peerSpecificStickerPack(peerId: peer.id) |> map { data in
                    return Tuple2(data, peer)
                }
            } else {
                return .single(nil)
            }
        }
        let mode = self.mode
        
        let searchCategories: Signal<EmojiSearchCategories?, NoError>
        if mode == .selectAvatar {
            searchCategories = .single(nil)
        } else {
            searchCategories = context.engine.stickers.emojiSearchCategories(kind: .combinedChatStickers) |> map { groups in
                var groups = groups?.groups ?? []
                if mode == .intro {
                    if let index = groups.firstIndex(where: { $0.kind == .greeting }) {
                        groups.move(at: index, to: 0)
                    }
                }
                return .init(hash: 0, groups: groups)
            }
        }

        
        let searchQueries = self.searchValue.get() |> map { $0.request.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").lowercased() } |> distinctUntilChanged
        let selectedCategories = Signal<EmojiSearchCategories.Group?, NoError>.single(initialState.selectedEmojiCategory) |> then(statePromise.get() |> map { $0.selectedEmojiCategory }) |> distinctUntilChanged
        let positionedSearchInputs = combineLatest(queue: prepareQueue, searchQueries, self.position.get(), selectedCategories) |> map { query, position, category -> (String, StickerPacksScrollState, EmojiSearchCategories.Group?) in
            return (query, query.isEmpty && category == nil ? position : .initial, category)
        }
        let searchInputs = positionedSearchInputs |> distinctUntilChanged(isEqual: { previous, next in
            return previous.0 == next.0 && previous.1 == next.1 && previous.2 == next.2
        })
        let featuredForUnread = Promise<[FeaturedStickerPackItem]>()
        featuredForUnread.set(context.account.viewTracker.featuredStickerPacks())
        let signal = searchInputs |> mapToSignal { values -> Signal<StickerPacksUpdateData, NoError> in
            
            let count = initialSize.with { size -> Int in
                return max(100, Int(round((size.height * (values.1 == .initial ? 2 : 20)) / 60 * 5)))
            }
            if values.0.isEmpty && values.2 == nil {
                var firstTime: Bool = true
                
                let settings = stickerSettings(postbox: context.account.postbox)
                switch values.1 {
                case .initial:
                    let packsView = context.account.postbox.itemCollectionsView(orderedItemListCollectionIds: [Namespaces.OrderedItemList.CloudRecentStickers, Namespaces.OrderedItemList.CloudSavedStickers], namespaces: [Namespaces.ItemCollection.CloudStickerPacks], aroundIndex: nil, count: count)
                    let featuredView = context.account.viewTracker.featuredStickerPacks()
                    
                    return combineLatest(packsView, featuredView, settings, statePromise.get()) |> mapToSignal { view, featured, settings, state in
                            return specificPackData |> map { specificPack in
                                let scrollToTop = firstTime
                                firstTime = false
                                return StickerPacksUpdateData(view: view, update: .generic(animated: scrollToTop, scrollToTop: scrollToTop), specificPack: specificPack, hasUnread: false, featured: featured, settings: settings, mode: mode, state: state)
                            }
                    }
                case let .scroll(aroundIndex):
                    let packsView = context.account.postbox.itemCollectionsView(orderedItemListCollectionIds: [Namespaces.OrderedItemList.CloudRecentStickers, Namespaces.OrderedItemList.CloudSavedStickers], namespaces: [Namespaces.ItemCollection.CloudStickerPacks], aroundIndex: aroundIndex.packIndex, count: count)
                    let featuredView = context.account.viewTracker.featuredStickerPacks()

                    
                    return combineLatest(packsView, featuredView, settings, statePromise.get())
                        |> mapToSignal { view, featured, settings, state in
                            return specificPackData |> map { specificPack in
                                let update: StickerPacksUpdate
                                if firstTime {
                                    firstTime = false
                                    update = .scroll(animated: false)
                                } else {
                                    update = .generic(animated: false, scrollToTop: false)
                                }
                                return StickerPacksUpdateData(view: view, update: update, specificPack: specificPack, hasUnread: false, featured: featured, settings: settings, mode: mode, state: state)
                            }
                    }
                case let .navigate(index):
                    let featuredView = context.account.viewTracker.featuredStickerPacks()
                    let packsView = context.account.postbox.itemCollectionsView(orderedItemListCollectionIds: [Namespaces.OrderedItemList.CloudRecentStickers, Namespaces.OrderedItemList.CloudSavedStickers], namespaces: [Namespaces.ItemCollection.CloudStickerPacks], aroundIndex: index.packIndex, count: count)
                    return combineLatest(packsView, featuredView, statePromise.get())
                        |> mapToSignal { view, featured, state in
                            return specificPackData |> map { specificPack in
                                let update: StickerPacksUpdate
                                if firstTime {
                                    firstTime = false
                                    update = .navigate(index, animated: true)
                                } else {
                                    update = .generic(animated: true, scrollToTop: false)
                                }
                                return StickerPacksUpdateData(view: view, update: update, specificPack: specificPack, hasUnread: false, featured: featured, mode: mode, state: state)
                            }
                    } 
                case .loadFeaturedMore:
                    fatalError("load featured for basic packs is not possible")
                }
            } else {
                let searchText = values.0
                                
                let premiumStickers: Signal<[TelegramMediaFile], NoError>
                if searchText == "premium" {
                    premiumStickers = context.account.postbox.itemCollectionsView(orderedItemListCollectionIds: [Namespaces.OrderedItemList.CloudPremiumStickers], namespaces: [Namespaces.ItemCollection.CloudStickerPacks], aroundIndex: nil, count: 1000) |> map { view in
                        var files:[TelegramMediaFile] = []
                        if !view.orderedItemListsViews[0].items.isEmpty {
                            for item in view.orderedItemListsViews[0].items {
                                if let entry = item.contents.get(RecentMediaItem.self) {
                                    files.append(entry.media._parse())
                                }
                            }
                        }
                        return files
                    }
                } else {
                    premiumStickers = .single([])
                }
                
                
                
                let searchLocal: Signal<FoundStickerSets?, NoError>
                let searchRemote: Signal<FoundStickerSets?, NoError>
                let emojiRelated: Signal<([FoundStickerItem], Bool), NoError>
                if let category = values.2, category.kind != .premium {
                    searchLocal = .single(nil)
                    searchRemote = .single(nil)
                    emojiRelated = context.engine.stickers.searchStickers(category: category) |> map { ($0.items, $0.isFinalResult) }
                } else {
                    searchLocal = context.engine.stickers.searchStickerSets(query: searchText) |> map(Optional.init)
                    searchRemote = .single(nil) |> then(context.engine.stickers.searchStickerSetsRemotely(query: searchText) |> delay(0.2, queue: prepareQueue) |> map(Optional.init))
                    let input: Signal<String, NoError> = Signal { subscriber in
                        subscriber.putNext(currentKeyboardLanguage())
                        subscriber.putCompletion()
                        return EmptyDisposable
                    } |> runOn(.mainQueue())
                    emojiRelated = combineLatest(EntertainmentUIHooks.shared.inputSource(context).searchEmoji(postbox: context.account.postbox, engine: context.engine, sharedContext: context.sharedContext, query: searchText, completeMatch: searchText.count < 3, checkPrediction: false), input) |> mapToSignal { emojis, input in
                        let emoticons = panelSearchAppendingUnique([], emojis.map { $0.basicEmoji.0 }, id: { $0 })
                        return context.engine.stickers.searchStickers(query: searchText.isSingleEmoji ? nil : searchText, emoticon: emoticons, inputLanguageCode: input) |> map { ($0.items, $0.isFinalResult) }
                    }
                }
                let relatedResults = Signal<([FoundStickerItem], Bool), NoError>.single(([], false)) |> then(emojiRelated |> delay(0.15, queue: prepareQueue))

                return combineLatest(searchLocal, searchRemote, relatedResults, statePromise.get(), premiumStickers) |> map { local, remote, emojiRelated, state, premiumStickers in
                    var value = FoundStickerSets()
                    if let local = local {
                        value = value.merge(with: local)
                    }
                    if let remote = remote {
                        value = value.merge(with: remote)
                    }
                    
                    let searchData = StickerPacksSearchData(sets: value, loading: (values.2 == nil ? remote == nil || !emojiRelated.1 : !emojiRelated.1) && value.entries.isEmpty && emojiRelated.0.isEmpty && premiumStickers.isEmpty, basicFeaturedCount: 0, emojiRelated: emojiRelated.0, premiumStickers: premiumStickers)
                    return StickerPacksUpdateData(view: nil, update: .generic(animated: true, scrollToTop: nil), specificPack: nil, searchData: searchData, hasUnread: false, featured: [], mode: mode, state: state)
                }
                
            }
            
        } |> deliverOnPrepareQueue
        |> mapToSignal { data -> Signal<StickerPacksUpdateData, NoError> in
            let hasUnread = featuredForUnread.get() |> map { featured in
                return featured.contains(where: { $0.unread })
            }
            return hasUnread |> map {
                return data.withUpdatedHasUnread($0)
            }
        }
        
        let transition = combineLatest(queue: prepareQueue, appearanceSignal, signal)
             |> map { appearance, data -> (TableUpdateTransition, TableUpdateTransition, [AppearanceWrapperEntry<PackEntry>], StickerPacksUpdateData) in
                
                _ = foundPacks.swap(data.searchData)
                
                 
                 
                 let entries = stickersEntries(view: data.view, context: context, featured: data.featured, settings: data.settings, searchData: data.searchData, specificPack: data.specificPack, mode: mode).map { AppearanceWrapperEntry(entry: $0, appearance: appearance) }
                let from = previous.swap(entries)
                
                 let entriesPack = packEntries(view: data.view, context: context, specificPack: data.specificPack, hasUnread: data.hasUnread, featured: data.featured, settings: data.settings, mode: mode).map { AppearanceWrapperEntry(entry: $0, appearance: appearance) }
                let fromPacks = previousPacks.swap(entriesPack)
                
                let transition = prepareStickersTransition(from: from, to: entries, initialSize: initialSize.with { $0 }, arguments: arguments, update: data.update)
                let packTransition = preparePackTransition(from: fromPacks, to: entriesPack, context: context, initialSize: initialSize.with { $0 })
                
                return (transition, packTransition, entriesPack, data)
        } |> deliverOnMainQueue
        
        var first: Bool = true
        
        disposable.set(transition.start(next: { [weak self] value in
            let (transition, packTransition, entriesPack, data) = value
            guard let `self` = self else { return }
            
            
            self.genericView.tableView.removeScroll(listener: self.listener)
            self.genericView.tableView.merge(with: transition)
            self.genericView.packsView.merge(with: packTransition)
            self.genericView.updateSearchStatus(isSearching: data.searchData != nil, isLoading: data.searchData?.loading ?? false)
            self.genericView.tableView.addScroll(listener: self.listener)
            
            
            first = false
            
            var visibleRows = self.genericView.tableView.visibleRows()
            if visibleRows.length == 0, !self.genericView.tableView.isEmpty {
                visibleRows.location = 0
                visibleRows.length = 1
            }
            if visibleRows.length > 0 {
                let item = self.genericView.tableView.item(at: visibleRows.location)
                self.genericView.packsView.changeSelection(stableId: item.stableId)
            }
            
            
            self.makeSearchCommand?(.normal)
            
            self.genericView.update(data: data, context: context, arguments: arguments, animated: !first)
            
            self.genericView.updateSelectionState(animated: transition.animated)

            if !packTransition.isEmpty {
                var resortRange: NSRange = NSMakeRange(0, 0)
                let entries = entriesPack.map( {$0.entry })
                
                for entry in entries {
                    switch entry {
                    case .saved, .recent, .specificPack, .featured:
                        resortRange.location += 1
                    default:
                        break
                    }
                }
                if entries.count > resortRange.location {
                    resortRange.length = entries.count - resortRange.location
                }
                self.genericView.packsView.resortController = TableResortController(resortRange: resortRange, start: { _ in }, resort: { _ in }, complete: { [weak self] fromIndex, toIndex in
                    
                    
                    if fromIndex == toIndex {
                        return
                    }
                    
                    let entries = entriesPack.map( {$0.entry })
                    
                    
                    let fromEntry = entries[fromIndex]
                    
                    guard case let .stickerPack(_, _, fromPackInfo, _, _) = fromEntry else {
                        return
                    }
                    
                    var referenceId: ItemCollectionId?
                    var beforeAll = false
                    var afterAll = false
                    if toIndex < entries.count {
                        switch entries[toIndex] {
                        case let .stickerPack(_, _, toPackInfo, _, _):
                            referenceId = toPackInfo.id
                        default:
                            if entries[toIndex] < fromEntry {
                                beforeAll = true
                            } else {
                                afterAll = true
                            }
                        }
                    } else {
                        afterAll = true
                    }
                    
                    
                    let _ = (context.account.postbox.transaction { transaction -> Void in
                        var infos = transaction.getItemCollectionsInfos(namespace: Namespaces.ItemCollection.CloudStickerPacks)
                        var reorderInfo: ItemCollectionInfo?
                        for i in 0 ..< infos.count {
                            if infos[i].0 == fromPackInfo.id {
                                reorderInfo = infos[i].1
                                infos.remove(at: i)
                                break
                            }
                        }
                        if let reorderInfo = reorderInfo {
                            if let referenceId = referenceId {
                                var inserted = false
                                for i in 0 ..< infos.count {
                                    if infos[i].0 == referenceId {
                                        if fromIndex < toIndex {
                                            infos.insert((fromPackInfo.id, reorderInfo), at: i + 1)
                                        } else {
                                            infos.insert((fromPackInfo.id, reorderInfo), at: i)
                                        }
                                        inserted = true
                                        break
                                    }
                                }
                                if !inserted {
                                    infos.append((fromPackInfo.id, reorderInfo))
                                }
                            } else if beforeAll {
                                infos.insert((fromPackInfo.id, reorderInfo), at: 0)
                            } else if afterAll {
                                infos.append((fromPackInfo.id, reorderInfo))
                            }
                            addSynchronizeInstalledStickerPacksOperation(transaction: transaction, namespace: Namespaces.ItemCollection.CloudStickerPacks, content: .sync, noDelay: false)
                            transaction.replaceItemCollectionInfos(namespace: Namespaces.ItemCollection.CloudStickerPacks, itemCollectionInfos: infos)
                        }
                    } |> deliverOnMainQueue).start(completed: { [weak self] in
                        if let `self` = self {
                            self.genericView.tableView.removeScroll(listener: self.listener)
                        }
                    })
                })
            }
            
            self.readyOnce()
        }))
        
        self.genericView.tableView.setScrollHandler { [weak self] position in
            if let `self` = self {
                let entries = previous.with ({ $0 })
                let index:StickerPacksIndex?
                
                if let foundPacks = foundPacks.with ({ $0 }), !self.searchState.request.isEmpty {
                    self.position.set(.loadFeaturedMore(foundPacks))
                } else {
                    switch position.direction {
                    case .bottom:
                        index = entries.last?.entry.index
                    case .top:
                        index = entries.first?.entry.index
                    case .none:
                        index = nil
                    }
                    if let index = index, self.searchState.request.isEmpty {
                        self.position.set(.scroll(aroundIndex: index))
                    }
                }
            }
        }
        
        actionsDisposable.add(searchCategories.start(next: { categories in
            updateState { current in
                var current = current
                current.searchCategories = categories
                return current
            }
        }))
        
        self.position.set(.initial)
        
    }
    public override func scrollup(force: Bool = false) {
        self.makeSearchCommand?(.close)
        self.position.set(.initial)
        self.genericView.packsView.scroll(to: .up(true))
        self.genericView.tableView.scroll(to: .up(true))
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
    
    public override var supportSwipes: Bool {
        if let categories = genericView.categories, categories._mouseInside() || genericView.searchView._mouseInside() {
            return false
        }
        return !self.genericView.packsView._mouseInside()
    }
    
    public override func escapeKeyAction() -> KeyHandlerResult {
        var cancelled: Bool = false
        self.updateState? { current in
            var current = current
            if current.selectedEmojiCategory != nil {
                cancelled = true
                current.selectedEmojiCategory = nil
            }
            return current
        }
        if searchState.state == .Focus {
            cancelled = true
        }
        if cancelled {
            self.updateSearchState(.init(state: .None, request: nil))
            return .invoked
        } else {
            return super.escapeKeyAction()
        }
    }
    
}
