import Cocoa
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramCore
import InAppSettings
import ColorPalette
import Localization
import TelegramTheme
import TelegramIconsTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import AlertsUI
import LocalAnimations
import PremiumUI
import Reactions
import DiceCache

public enum InstalledStickerPacksEntryTag: ItemListItemTag {
    case suggestOptions
    case loopAnimatedStickers
    
    public func isEqual(to other: ItemListItemTag) -> Bool {
        if let other = other as? InstalledStickerPacksEntryTag, self == other {
            return true
        } else {
            return false
        }
    }
}

private final class InstalledStickerPacksControllerArguments {
    let context: any AccountContextProtocol
    
    let openStickerPack: (StickerPackCollectionInfo) -> Void
    let removePack: (ItemCollectionId) -> Void
    let openStickersBot: () -> Void
    let openFeatured: () -> Void
    let openArchived: ([ArchivedStickerPackItem]?) -> Void
    let openSuggestionOptions: () -> Void
    let toggleLoopAnimated: (Bool)->Void
    let quickSetup:(Control)->Void
    let customEmoji: () -> Void
    let toggleDynamicPackOrder:()->Void
    init(context: any AccountContextProtocol, openStickerPack: @escaping (StickerPackCollectionInfo) -> Void, removePack: @escaping (ItemCollectionId) -> Void, openStickersBot: @escaping () -> Void, openFeatured: @escaping () -> Void, openArchived: @escaping ([ArchivedStickerPackItem]?) -> Void, openSuggestionOptions: @escaping() -> Void, toggleLoopAnimated: @escaping(Bool)->Void, quickSetup:@escaping(Control)->Void, customEmoji: @escaping() -> Void, toggleDynamicPackOrder:@escaping()->Void) {
        self.context = context
        self.openStickerPack = openStickerPack
        self.removePack = removePack
        self.openStickersBot = openStickersBot
        self.openFeatured = openFeatured
        self.openArchived = openArchived
        self.openSuggestionOptions = openSuggestionOptions
        self.toggleLoopAnimated = toggleLoopAnimated
        self.quickSetup = quickSetup
        self.customEmoji = customEmoji
        self.toggleDynamicPackOrder = toggleDynamicPackOrder
    }
}

public struct ItemListStickerPackItemEditing: Equatable {
    public let editable: Bool
    public let editing: Bool
    public init(editable: Bool, editing: Bool) {
        self.editable = editable
        self.editing = editing
    }
    
    public static func ==(lhs: ItemListStickerPackItemEditing, rhs: ItemListStickerPackItemEditing) -> Bool {
        if lhs.editable != rhs.editable {
            return false
        }
        if lhs.editing != rhs.editing {
            return false
        }
        return true
    }
}


private enum InstalledStickerPacksEntryId: Hashable {
    case index(Int32)
    case pack(ItemCollectionId)
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case let .index(index):
            hasher.combine(index)
        case let .pack(id):
            hasher.combine(id)
        }
    }
    
    static func ==(lhs: InstalledStickerPacksEntryId, rhs: InstalledStickerPacksEntryId) -> Bool {
        switch lhs {
        case let .index(index):
            if case .index(index) = rhs {
                return true
            } else {
                return false
            }
        case let .pack(id):
            if case .pack(id) = rhs {
                return true
            } else {
                return false
            }
        }
    }
}

private struct ArchivedListContainer : Equatable {
    let archived: [ArchivedStickerPackItem]?
    static func ==(lhs: ArchivedListContainer, rhs: ArchivedListContainer) -> Bool {
        if let lhsItem = lhs.archived, let rhsItem = rhs.archived {
            if lhsItem.count != rhsItem.count {
                return false
            } else {
                for i in 0 ..< lhsItem.count {
                    let lhs = lhsItem[i]
                    let rhs = rhsItem[i]
                    if lhs.info != rhs.info {
                        return false
                    }
                    if lhs.topItems != rhs.topItems {
                        return false
                    }
                }
            }
        } else if (lhs.archived != nil) != (rhs.archived != nil) {
            return false
        }
        return true
    }
}

private enum InstalledStickerPacksEntry: TableItemListNodeEntry {
    case section(sectionId:Int32)
    case suggestOptions(sectionId: Int32, String, GeneralViewType)
    case trending(sectionId:Int32, Int32?, GeneralViewType)
    case archived(sectionId:Int32, ArchivedListContainer, GeneralViewType)
    case quickReaction(sectionId:Int32, ContextReaction, GeneralViewType)
    case customEmoji(sectionId:Int32, GeneralViewType)
    case loopAnimated(sectionId: Int32, Bool, GeneralViewType)
    case dynamicPackOrder(sectionId: Int32, Bool, GeneralViewType)
    case dynamicPackOrderInfo(sectionId: Int32, GeneralViewType)

    case packsTitle(sectionId:Int32, String, GeneralViewType)
    case pack(sectionId:Int32, Int32, StickerPackCollectionInfo, StickerPackItem?, Int32, Bool, Bool, ItemListStickerPackItemEditing, GeneralViewType)
    case packsInfo(sectionId:Int32, String, GeneralViewType)
    
    
    var stableId: InstalledStickerPacksEntryId {
        switch self {
        case .suggestOptions:
            return .index(0)
        case .loopAnimated:
            return .index(1)
        case .trending:
            return .index(2)
        case .archived:
            return .index(3)
        case .customEmoji:
            return .index(4)
        case .quickReaction:
            return .index(5)
        case .dynamicPackOrder:
            return .index(6)
        case .dynamicPackOrderInfo:
            return .index(7)
        case .packsTitle:
            return .index(8)
        case let .pack(_, _, info, _, _, _, _, _, _):
            return .pack(info.id)
        case .packsInfo:
            return .index(9)
        case let .section(sectionId):
            return .index((sectionId + 1) * 1000 - sectionId)
        }
    }
    
    
    var stableIndex:Int32 {
        switch self {
        case .suggestOptions:
            return 0
        case .loopAnimated:
            return 1
        case .trending:
            return 2
        case .archived:
            return 3
        case .customEmoji:
            return 4
        case .quickReaction:
            return 5
        case .dynamicPackOrder:
            return 7
        case .dynamicPackOrderInfo:
            return 8
        case .packsTitle:
            return 9
        case .pack:
            fatalError("")
        case .packsInfo:
            return 10
        case let .section(sectionId):
            return (sectionId + 1) * 1000 - sectionId
        }
    }
    
    var index:Int32 {
        switch self {
        case let .suggestOptions(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .trending(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .archived(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .quickReaction(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .customEmoji(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .loopAnimated(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .dynamicPackOrder(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .dynamicPackOrderInfo(sectionId, _):
            return (sectionId * 1000) + stableIndex
        case let .packsTitle(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .pack( sectionId, index, _, _, _, _, _, _, _):
            return (sectionId * 1000) + 100 + index
        case let .packsInfo(sectionId, _, _):
            return (sectionId * 1000) + stableIndex
        case let .section(sectionId):
            return (sectionId + 1) * 1000 - sectionId
        }
    }
    
    static func <(lhs: InstalledStickerPacksEntry, rhs: InstalledStickerPacksEntry) -> Bool {
        return lhs.index < rhs.index
    }
    
    func item(_ arguments: InstalledStickerPacksControllerArguments, initialSize:NSSize) -> TableRowItem {
        switch self {
        case let .suggestOptions(_, value, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().stickersSuggestStickers, icon: theme.icons.installed_stickers_suggest, type: .context(value), viewType: viewType, action: {
                arguments.openSuggestionOptions()
            })
        case let .trending(_, count, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().installedStickersTranding, icon: theme.icons.installed_stickers_trending, type: count.map { GeneralInteractedType.nextContext($0 > 0 ? "\($0)" : "") } ?? .loading, viewType: viewType, action: {
                arguments.openFeatured()
            })
        case let .archived(_, archived, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().installedStickersArchived, icon: theme.icons.installed_stickers_archive, type: .next, viewType: viewType, action: {
                arguments.openArchived(archived.archived)
            })
        case let .quickReaction(_, reaction, viewType):
            return QuickReactionRowItem(initialSize, stableId: stableId, context: arguments.context, reaction: reaction, viewType: viewType, select: arguments.quickSetup)
        case let .loopAnimated(_, value, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().installedStickersLoopAnimated, icon: theme.icons.installed_stickers_loop, type: .switchable(value), viewType: viewType, action: {
                arguments.toggleLoopAnimated(!value)
            })
        case let .customEmoji(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().installedStickersCustomEmoji, icon: theme.icons.installed_stickers_custom_emoji, type: .next, viewType: viewType, action: arguments.customEmoji)
        case let .dynamicPackOrder(_, value, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().installedStickersDynamicPackOrder, icon: theme.icons.installed_stickers_dynamic_order, type: .switchable(value), viewType: viewType, action: arguments.toggleDynamicPackOrder)
        case let .dynamicPackOrderInfo(_, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().installedStickersDynamicPackOrderInfo, viewType: viewType)
        case let .packsTitle(_, text, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, viewType: viewType)
        case let .pack(_, _, info, topItem, count, enabled, _, editing, viewType):
            return StickerSetTableRowItem(initialSize, context: arguments.context, stableId: stableId, info: info, topItem: topItem, itemCount: count, unread: false, editing: editing, enabled: enabled, control: .none, viewType: viewType, action: {
                arguments.openStickerPack(info)
            }, addPack: {
                
            }, removePack: {
                arguments.removePack(info.id)
            })
        case let .packsInfo(_, text, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, viewType: viewType)
        case .section:
            return GeneralRowItem(initialSize, height: 20, stableId: stableId, viewType: .separator)
        }
    }
}

private struct InstalledStickerPacksControllerState: Equatable {
    var editing: Bool
    var quick: ContextReaction?
}


private func installedStickerPacksControllerEntries(state: InstalledStickerPacksControllerState, autoplayMedia: AutoplayMediaPreferences, stickerSettings: StickerSettings, view: CombinedView, featuredCount: Int, featuredUnreadCount: Int32?, archived: [ArchivedStickerPackItem]?, hasEmojies: Bool) -> [InstalledStickerPacksEntry] {
    var entries: [InstalledStickerPacksEntry] = []
    
    var sectionId:Int32 = 1
    
    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    
    let suggestString: String
    switch stickerSettings.emojiStickerSuggestionMode {
    case .none:
        suggestString = strings().stickersSuggestNone
    case .all:
        suggestString = strings().stickersSuggestAll
    case .installed:
        suggestString = strings().stickersSuggestAdded
    }
    entries.append(.suggestOptions(sectionId: sectionId, suggestString, .firstItem))
    
    
    entries.append(.loopAnimated(sectionId: sectionId, autoplayMedia.loopAnimatedStickers, .lastItem))
    
    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    
    
    if featuredCount != 0 {
        entries.append(.trending(sectionId: sectionId, featuredUnreadCount, .firstItem))
    }
    let archivedViewType: GeneralViewType
    switch (featuredCount == 0, !hasEmojies && state.quick == nil) {
    case (true, true):
        archivedViewType = .singleItem
    case (true, false):
        archivedViewType = .firstItem
    case (false, true):
        archivedViewType = .lastItem
    case (false, false):
        archivedViewType = .innerItem
    }
    entries.append(.archived(sectionId: sectionId, ArchivedListContainer(archived: archived), archivedViewType))
    
    if hasEmojies {
        entries.append(.customEmoji(sectionId: sectionId, state.quick == nil ? .lastItem : .innerItem))
    }
    if let quick = state.quick {
        entries.append(.quickReaction(sectionId: sectionId, quick, .lastItem))
    }
    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    
    
    entries.append(.dynamicPackOrder(sectionId: sectionId, stickerSettings.dynamicPackOrder, .singleItem))
    entries.append(.dynamicPackOrderInfo(sectionId: sectionId, .textBottomItem))

    
    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    
    entries.append(.packsTitle(sectionId: sectionId, strings().installedStickersPacksTitle, .textTopItem))
    
    if let stickerPacksView = view.views[.itemCollectionInfos(namespaces: [Namespaces.ItemCollection.CloudStickerPacks])] as? ItemCollectionInfosView {
        if let packsEntries = stickerPacksView.entriesByNamespace[Namespaces.ItemCollection.CloudStickerPacks] {
            var index: Int32 = 0
            for entry in packsEntries {
                if let info = entry.info as? StickerPackCollectionInfo {
                    let viewType: GeneralViewType = bestGeneralViewType(packsEntries, for: entry)
                   
                    entries.append(.pack(sectionId: sectionId, index, info, entry.firstItem as? StickerPackItem, info.count == 0 ? entry.count : info.count, true, autoplayMedia.loopAnimatedStickers, ItemListStickerPackItemEditing(editable: true, editing: state.editing), viewType))
                    index += 1
                }
            }
        }
    }
    entries.append(.packsInfo(sectionId: sectionId, strings().installedStickersDescrpiption, .textBottomItem))
    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    return entries
}

private func prepareTransition(left:[AppearanceWrapperEntry<InstalledStickerPacksEntry>], right: [AppearanceWrapperEntry<InstalledStickerPacksEntry>], initialSize: NSSize, arguments: InstalledStickerPacksControllerArguments) -> TableUpdateTransition {
    let (removed, inserted, updated) = proccessEntriesWithoutReverse(left, right: right) { entry -> TableRowItem in
        return entry.entry.item(arguments, initialSize: initialSize).settingsRow()
    }
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: true)
}

open class InstalledStickerPacksController<Context: AccountContextProtocol>: TableViewController<Context> {

    open override var defaultBarTitle: String {
        return localizedString("Telegram.InstalledStickerPacksController")
    }

    private let focusOnItemTag: InstalledStickerPacksEntryTag?
    public init(_ context: Context, focusOnItemTag: InstalledStickerPacksEntryTag? = nil) {
        self.focusOnItemTag = focusOnItemTag
        super.init(context)
    }
    
    private let disposbale = MetaDisposable()
    private func openSuggestionOptions() {
        let postbox: Postbox = context.account.postbox
        if let view = (genericView.item(stableId: InstalledStickerPacksEntryId.index(0))?.view as? GeneralInteractedRowView)?.textView {
            if let event = NSApp.currentEvent {
                
                let menu = ContextMenu()
                
                menu.addItem(ContextMenuItem(strings().stickersSuggestAll, handler: {
                    _ = updateStickerSettingsInteractively(postbox: postbox, {$0.withUpdatedEmojiStickerSuggestionMode(.all)}).start()
                }, itemImage: MenuAnimation.menu_view_sticker_set.value))
                
                menu.addItem(ContextMenuItem(strings().stickersSuggestAdded, handler: {
                    _ = updateStickerSettingsInteractively(postbox: postbox, {$0.withUpdatedEmojiStickerSuggestionMode(.installed)}).start()
                }, itemImage: MenuAnimation.menu_open_profile.value))
                
                menu.addItem(ContextMenuItem(strings().stickersSuggestNone, handler: {
                    _ = updateStickerSettingsInteractively(postbox: postbox, {$0.withUpdatedEmojiStickerSuggestionMode(.none)}).start()
               }, itemImage: MenuAnimation.menu_clear_history.value))
                
                let value = AppMenu(menu: menu)
                
                value.show(event: event, view: view)
                
            }
         
        }
    }
    
    deinit {
        disposbale.dispose()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        
        let context = self.context
        let initialValue = InstalledStickerPacksControllerState(editing: false, quick: nil)
        let statePromise = ValuePromise<InstalledStickerPacksControllerState>(ignoreRepeated: true)
        let stateValue = Atomic(value: initialValue)
        let updateState: ((InstalledStickerPacksControllerState) -> InstalledStickerPacksControllerState) -> Void = { f in
            statePromise.set(stateValue.modify { f($0) })
        }
        
        let archivedPromise = Promise<[ArchivedStickerPackItem]?>()
        archivedPromise.set(.single(nil) |> then(context.engine.stickers.archivedStickerPacks() |> map(Optional.init)))
        

        
        let actionsDisposable = DisposableSet()
        
        let resolveDisposable = MetaDisposable()
        actionsDisposable.add(resolveDisposable)
        
        let arguments = InstalledStickerPacksControllerArguments(context: context, openStickerPack: { info in
            showModal(with: StickerSettingsHooks.shared.makeStickerPackPreview(context, nil, [.stickers(.name(info.shortName))]), for: context.window)
        }, removePack: { id in
            
            verifyAlert_button(for: context.window, information: strings().installedStickersRemoveDescription, ok: strings().installedStickersRemoveDelete, successHandler: { result in
                switch result {
                case .basic:
                    _ = context.engine.stickers.removeStickerPackInteractively(id: id, option: .archive).start()
                case .thrid:
                    break
                }
            })
            
        }, openStickersBot: {
//            resolveDisposable.set((context.engine.peers.resolvePeerByName(name: "stickers") |> deliverOnMainQueue).start(next: { peerId in
//                if let peerId = peerId {
//                   // navigateToChatControllerImpl?(peerId)
//                }
//            }))
        }, openFeatured: { [weak self] in
            self?.navigationController?.push(FeaturedStickerPacksController(context))
        }, openArchived: { [weak self] archived in
            self?.navigationController?.push(ArchivedStickerPacksController(context, archived: archived, updatedPacks: { packs in
                archivedPromise.set(.single(packs))
            }))
        }, openSuggestionOptions: { [weak self] in
            self?.openSuggestionOptions()
        }, toggleLoopAnimated: { value in
            _ = updateAutoplayMediaSettingsInteractively(postbox: context.account.postbox, {
                $0.withUpdatedLoopAnimatedStickers(value)
            }).start()
        }, quickSetup: { control in
            
            let callback:(TelegramMediaFile)->Void = { file in
                if let bundle = file.stickerText {
                    context.reactions.updateQuick(.builtin(bundle))
                } else {
                    if context.isPremium {
                        context.reactions.updateQuick(.custom(file.fileId.id))
                    } else {
                        showModalText(for: context.window, text: strings().customReactionPremiumAlert, callback: { _ in
                            prem(with: PremiumBoardingController(context: context, source: .infinite_reactions), for: context.window)
                        })
                    }
                }
            }
            if control.popover == nil {
                showPopover(for: control, with: StickerSettingsHooks.shared.makeSetupQuickReaction(context, callback), edge: .maxY, inset: NSMakePoint(-80, -35), static: true, animationMode: .reveal)
            }
        }, customEmoji: {
            context.bindings.rootNavigation().push(CustomEmojiController(context: context))
        }, toggleDynamicPackOrder: {
            _ = updateStickerSettingsInteractively(postbox: context.account.postbox, {
                $0.withUpdatedDynamicPackOrder(!$0.dynamicPackOrder)
            }).start()
        })
        let emojiPacksKey: PostboxViewKey = .itemCollectionInfos(namespaces: [Namespaces.ItemCollection.CloudEmojiPacks])
        let featuredKey: PostboxViewKey = .orderedItemList(id: Namespaces.OrderedItemList.CloudFeaturedStickerPacks)
        let stickerPacks = context.account.postbox.combinedView(keys: [.itemCollectionInfos(namespaces: [Namespaces.ItemCollection.CloudStickerPacks]), emojiPacksKey, featuredKey])
        let featuredUnreadCount: Signal<Int32?, NoError> = .single(nil) |> then(context.account.viewTracker.featuredStickerPacks() |> map { featured in
            return Int32(featured.filter { $0.unread }.count)
        })
        
        
        let stickerSettingsKey = ApplicationSpecificPreferencesKeys.stickerSettings
        let autoplayKey = ApplicationSpecificPreferencesKeys.autoplayMedia
        let preferencesKey: PostboxViewKey = .preferences(keys: Set([stickerSettingsKey, autoplayKey]))
        let preferencesView: Signal<CombinedView?, NoError> = .single(nil) |> then(context.account.postbox.combinedView(keys: [preferencesKey]) |> map(Optional.init))
        
        let previousEntries:Atomic<[AppearanceWrapperEntry<InstalledStickerPacksEntry>]> = Atomic(value: [])
        let initialSize = self.atomicSize
        
        
        let settings = context.account.postbox.preferencesView(keys: [PreferencesKeys.reactionSettings])
           |> map { preferencesView -> ReactionSettings in
               let reactionSettings: ReactionSettings
               if let entry = preferencesView.values[PreferencesKeys.reactionSettings], let value = entry.get(ReactionSettings.self) {
                   reactionSettings = value
               } else {
                   reactionSettings = .default
               }
               return reactionSettings
           }
        actionsDisposable.add(combineLatest(settings, context.reactions.stateValue).start(next: { settings, available in
            updateState { current in
                var current = current
                switch settings.quickReaction {
                case .builtin:
                    if let reaction = available?.enabled.first(where: { $0.value == settings.quickReaction }) {
                        current.quick = .builtin(value: reaction.value, staticFile: reaction.staticIcon._parse(), selectFile: reaction.selectAnimation._parse(), appearFile: reaction.appearAnimation._parse(), isSelected: false)
                    }
                case let .custom(fileId):
                    if context.isPremium {
                        current.quick = .custom(value: settings.quickReaction, fileId: fileId, nil, isSelected: false)
                    } else if let first = available?.enabled.first {
                        current.quick = .builtin(value: first.value, staticFile: first.staticIcon._parse(), selectFile: first.selectAnimation._parse(), appearFile: first.appearAnimation._parse(), isSelected: false)
                    }
                case .stars:
                    break
                }
                return current
            }
        }))
        
        
      
        let signal = combineLatest(queue: prepareQueue, statePromise.get(), stickerPacks, archivedPromise.get(), appearanceSignal, preferencesView, featuredUnreadCount)
            |> map { state, view, archived, appearance, preferencesView, featuredUnreadCount -> TableUpdateTransition in
                
                let hasEmojies = !((view.views[emojiPacksKey] as? ItemCollectionInfosView)?.entriesByNamespace[Namespaces.ItemCollection.CloudEmojiPacks]?.isEmpty ?? true)
                let featuredCount = (view.views[featuredKey] as? OrderedItemListView)?.items.count ?? 0
                
                var stickerSettings = context.stickerSettings
                if let view = preferencesView?.views[preferencesKey] as? PreferencesView {
                    if let value = view.values[stickerSettingsKey]?.get(StickerSettings.self) {
                        stickerSettings = value
                    }
                }
                
                var autoplayMedia = context.autoplayMedia
                if let view = preferencesView?.views[preferencesKey] as? PreferencesView {
                    if let value = view.values[autoplayKey]?.get(AutoplayMediaPreferences.self) {
                        autoplayMedia = value
                    }
                }
                
                let entries = installedStickerPacksControllerEntries(state: state, autoplayMedia: autoplayMedia, stickerSettings: stickerSettings, view: view, featuredCount: featuredCount, featuredUnreadCount: featuredUnreadCount, archived: archived, hasEmojies: hasEmojies).map {AppearanceWrapperEntry(entry: $0, appearance: appearance)}
                return prepareTransition(left: previousEntries.swap(entries), right: entries, initialSize: initialSize.modify({$0}), arguments: arguments)
        } |> afterDisposed {
            actionsDisposable.dispose()
        } |> deliverOnMainQueue
        
        
        disposbale.set(signal.start(next: { [weak self] transition in
            guard let `self` = self else {return}
            
            self.genericView.merge(with: transition)

            self.readyOnce()

            if !transition.isEmpty {
                var start: Int? = nil
                var length: Int = 0
                self.genericView.enumerateItems(with: { item -> Bool in
                    if item is StickerSetTableRowItem {
                        if start == nil {
                            start = item.index
                        }
                        length += 1
                    } else if start != nil {
                        return false
                    }
                    return true
                })
                if let start = start {
                    self.genericView.resortController = TableResortController(resortRange: NSMakeRange(start, length), start: { _ in }, resort: { _ in }, complete: { fromIndex, toIndex in
                        
                        
                        if fromIndex == toIndex {
                            return
                        }
                        
                        let entries = previousEntries.with {$0}.map( {$0.entry })
                        
                        
                        let fromEntry = entries[fromIndex]
                        guard case let .pack(_, _, fromPackInfo, _, _, _, _, _, _) = fromEntry else {
                            return
                        }
                        
                        var referenceId: ItemCollectionId?
                        var beforeAll = false
                        var afterAll = false
                        if toIndex < entries.count {
                            switch entries[toIndex] {
                            case let .pack(_, _, toPackInfo, _, _, _, _, _, _):
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
                        }).start()
                        
                    })
                } else {
                    self.genericView.resortController = nil
                }
            }
            
           
            
        }))
        
        
    }
    
}
