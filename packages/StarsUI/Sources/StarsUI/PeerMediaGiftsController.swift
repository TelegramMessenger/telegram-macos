import Foundation
import Cocoa
import TelegramCore
import Postbox
import TGUIKit
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import LocalAnimations
import InputDataUI
import GeneralRows
import AlertsUI
import SelectPeersUI
import InlineStickerLayer
import DateUtils



private final class CollectionRowItem : TableStickItem {
    
    struct Item : Comparable, Identifiable {
        let value: State.Collection
        let index: Int
        let selected: Bool
        
        var stableId: AnyHashable {
            return value.stableId
        }
        static func < (lhs: Item, rhs: Item) -> Bool {
            return lhs.index < rhs.index
        }
        
        func makeItem(_ size: NSSize, arguments: Arguments) -> TableRowItem {
            return StarsHooks.shared.makeFilterChipRow(size, stableId, arguments.context, self.text, self.selected, { arguments.collection(self.value, nil) }, { arguments.collectionContextMenu(self.value) })
        }
        
        var text: NSAttributedString {
            let attr = NSMutableAttributedString()
            switch self.value {
            case .all:
                attr.append(
                    string: strings().peerMediaGiftsCollectionAll,
                    color: theme.colors.text,
                    font: .medium(.title)
                )
            case let .collection(value):
                if let file = value.icon {
                    attr.append(
                        string: "\(clown_space)\(value.title)",
                        color: theme.colors.text,
                        font: .medium(.title)
                    )
                    attr.insertEmbedded(.embeddedAnimated(file, playPolicy: .framesCount(1)), for: clown)
                } else {
                    attr.append(
                        string: value.title,
                        color: theme.colors.text,
                        font: .medium(.title)
                    )
                }
            case .add:
                attr.append(
                    string: "\(clown_space)\(strings().peerMediaGiftsCollectionAdd)",
                    color: theme.colors.text,
                    font: .medium(.title)
                )
                attr.insertEmbedded(
                    .embeddedAnimated(LocalAnimatedSticker.menu_add.file, color: theme.colors.text, playPolicy: .framesCount(1)),
                    for: clown
                )
            }
            return attr
        }
    }
    
    fileprivate let items: [Item]
    fileprivate let selected: Int32?
    fileprivate let context: (any AccountContextProtocol)?
    fileprivate let arguments: Arguments?
    fileprivate let _stableId: AnyHashable
    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, filters: [State.Collection], selected: Int32, arguments: Arguments) {
        var items: [Item] = []
        for (i, filter) in filters.enumerated() {
            items.append(.init(value: filter, index: i, selected: filter.stableId == selected))
        }
        self.items = items
        self.context = context
        self.selected = selected
        self.arguments = arguments
        self._stableId = stableId
        super.init(initialSize)
    }
    
    override var stableId: AnyHashable {
        return _stableId
    }
    
    required init(_ initialSize: NSSize) {
        self.arguments = nil
        self.context = nil
        self.items = []
        self._stableId = AnyHashable(InputDataEntryId.custom(_id_collections))
        self.selected = nil
        super.init(initialSize)
        
    }
    
    override var height: CGFloat {
        return 40
    }

    override var accessibilityLabel: String? {
        return strings().voiceOverCommonFilter
    }
    
    override func viewClass() -> AnyClass {
        return CollectionFilterRowView.self
    }
}

private final class CollectionFilterRowView : TableStickView, TableViewDelegate {
    
    private var ignoreNextAnimation: Bool = false

    
    func selectionDidChange(row: Int, item: TableRowItem, byClick: Bool, isNew: Bool) {
        if let item = item as? StarsFilterChipRow {
            item.select()
        }
    }
    
    func selectionWillChange(row: Int, item: TableRowItem, byClick: Bool) -> Bool {
        return true
    }
    
    func isSelectable(row: Int, item: TableRowItem) -> Bool {
        return true
    }
    
    private let tableView = HorizontalTableView(frame: .zero)
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(tableView)
        tableView.getBackgroundColor = {
            .clear
        }
        
        tableView.delegate = self
   

    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var items: [CollectionRowItem.Item] = []
    
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? CollectionRowItem else {
            return
        }
        
        let animated = animated && !ignoreNextAnimation

        
        _ = item.context
        let items = item.items
        let arguments = item.arguments
        
        guard let arguments else {
            return
        }
        
        applyMergedRows(tableView, current: &self.items, items: items, animated: animated, makeItem: { item in
            return item.makeItem(bounds.size, arguments: arguments)
        })
        
        
        tableView.resortController = .init(resortRange: NSMakeRange(1, items.count - 2), start: { _ in }, resort: { _ in }, complete: { [weak self] from, to in
            self?.ignoreNextAnimation = true
            arguments.resort(from, to)
        })
        
        layout()
        
    }
    
    override func layout() {
        super.layout()
        if tableView.listHeight < bounds.width - 40 {
            tableView.frame = focus(NSMakeSize(tableView.listHeight, 40))
        } else {
            tableView.frame = focus(NSMakeSize(bounds.width - 40, 40))
        }
    }
}


private final class Arguments {
    let context: any AccountContextProtocol
    let open:(ProfileGiftsContext.State.StarGift, (() -> NSView?)?, Bool)->Void
    let togglePin:(ProfileGiftsContext.State.StarGift)->Void
    let toggleWear:(ProfileGiftsContext.State.StarGift)->Void
    let transfer:(ProfileGiftsContext.State.StarGift)->Void
    let toggleVisibility:(ProfileGiftsContext.State.StarGift)->Void
    let copy:(ProfileGiftsContext.State.StarGift)->Void
    let collection:(State.Collection, ProfileGiftsContext.State.StarGift?)->Void
    let addToCollection:(State.Collection, ProfileGiftsContext.State.StarGift?)->Void
    let collectionContextMenu:(State.Collection)->[ContextMenuItem]
    let resort:(Int, Int)->Void
    var giftMenu: ((ProfileGiftsContext.State.StarGift) -> [ContextMenuItem])?
    var deleteGift: ((ProfileGiftsContext.State.StarGift) -> Void)?
    var setGiftTheme: ((StarGift.UniqueGift) -> Void)?
    init(context: any AccountContextProtocol, open:@escaping(ProfileGiftsContext.State.StarGift, (() -> NSView?)?, Bool)->Void, togglePin:@escaping(ProfileGiftsContext.State.StarGift)->Void, toggleWear:@escaping(ProfileGiftsContext.State.StarGift)->Void, transfer:@escaping(ProfileGiftsContext.State.StarGift)->Void, toggleVisibility:@escaping(ProfileGiftsContext.State.StarGift)->Void, copy:@escaping(ProfileGiftsContext.State.StarGift)->Void, collection:@escaping(State.Collection, ProfileGiftsContext.State.StarGift?)->Void, addToCollection: @escaping(State.Collection, ProfileGiftsContext.State.StarGift?)->Void, collectionContextMenu:@escaping(State.Collection)->[ContextMenuItem], resort:@escaping(Int, Int)->Void) {
        self.context = context
        self.open = open
        self.togglePin = togglePin
        self.toggleWear = toggleWear
        self.transfer = transfer
        self.toggleVisibility = toggleVisibility
        self.copy = copy
        self.collection = collection
        self.addToCollection = addToCollection
        self.collectionContextMenu = collectionContextMenu
        self.resort = resort
    }
}

private struct State : Equatable {
    
    enum Collection : Equatable {
        case all
        case collection(value: StarGiftCollection)
        case add
        
        
        var stableId: Int32 {
            switch self {
            case .all:
                return -1
            case let .collection(value):
                return value.id
            case .add:
                return .max
            }
        }
    }
    
    var gifts: [ProfileGiftsContext.State.StarGift] {
        let collection = collections.first(where: { $0.stableId == selectedCollection }) ?? .all

        switch collection {
        case .all:
            return collectionsState[Collection.all.stableId]?.filteredGifts ?? []
        case let .collection(value):
            return collectionsState[value.id]?.filteredGifts ?? []
        default:
            return []
        }
    }
    
    var state: ProfileGiftsContext.State? {
        return collectionsState[Collection.all.stableId]
    }
    
    var effectiveState: ProfileGiftsContext.State? {
        return collectionsState[selectedCollection] ?? state
    }
    
    mutating func notificationsEnabled(_ value: Bool) {
        collectionsState[Collection.all.stableId]?.notificationsEnabled = value
    }
    
    func contains(collectionId: Int32, gift: ProfileGiftsContext.State.StarGift) -> Bool {
        return gift.collectionIds?.contains(collectionId) == true
    }
    
    var perRowCount: Int = 4
    var peer: EnginePeer?
    var starsState: StarsContext.State?
    var collectionsState:[Int32: ProfileGiftsContext.State] = [:]
    
    var count: Int32 {
        return state?.count ?? 0
    }

    var collections:[Collection] = []
    
    var collection: Collection {
        return self.collections.first(where: { $0.stableId == selectedCollection}) ?? .all
    }

    
    var selectedCollection: Int32 = Collection.all.stableId
    
    var onStage: Bool = false
}

private func giftMenuItems(_ profile: ProfileGiftsContext.State.StarGift, state: State, arguments: Arguments) -> [ContextMenuItem] {
    guard let reference = profile.reference, let owner = state.peer, owner.id == arguments.context.peerId || owner._asPeer().groupAccess.isCreator else {
        return []
    }
    let addItem = ContextMenuItem(strings().peerMediaGiftsCollectionContextAddToCollection, itemImage: MenuAnimation.menu_add_to_folder.value)
    let addMenu = ContextMenu()
    addMenu.addItem(ContextMenuItem(strings().peerMediaGiftsCollectionContextNewCollection, handler: {
        arguments.collection(.add, profile)
    }, itemImage: MenuAnimation.menu_folder_add.value))
    for collection in state.collections {
        if case let .collection(value) = collection {
            if addMenu.items.count == 1 {
                addMenu.addItem(ContextSeparatorItem())
            }
            let item = ContextMenuItem(value.title, handler: {
                arguments.addToCollection(collection, profile)
            }, state: state.contains(collectionId: value.id, gift: profile) ? .on : nil)
            if let file = value.icon {
                StarsHooks.shared.applyMenuItemEmoji(item, arguments.context, file)
            }
            addMenu.addItem(item)
        }
    }
    addItem.submenu = addMenu
    if profile.gift.generic != nil {
        let canDelete = starGiftCanDelete(gift: profile.gift, reference: reference, owner: owner, accountPeerId: arguments.context.peerId, converted: false, fromProfile: true, upgraded: false, refunded: profile.isRefunded)
        let delete: (() -> Void)? = canDelete ? { arguments.deleteGift?(profile) } : nil
        return genericGiftMenuItems(collections: addItem, savedToProfile: profile.savedToProfile, toggleVisibility: {
            arguments.toggleVisibility(profile)
        }, delete: delete)
    }
    var items: [ContextMenuItem] = [addItem, ContextSeparatorItem()]
    if let unique = profile.gift.unique {
        if state.selectedCollection == State.Collection.all.stableId {
            items.append(ContextMenuItem(profile.pinnedToTop ? strings().chatListContextUnpin : strings().chatListContextPin, handler: {
                arguments.togglePin(profile)
            }, itemImage: profile.pinnedToTop ? MenuAnimation.menu_unpin.value : MenuAnimation.menu_pin.value))
        }
        let wearing: Bool
        if case let .starGift(id, _, _, _, _, _, _, _, _)? = state.peer?.emojiStatus?.content {
            wearing = id == unique.id
        } else {
            wearing = false
        }
        items.append(ContextMenuItem(wearing ? strings().giftContextTakeOff : strings().giftContextWear, handler: {
            arguments.toggleWear(profile)
        }, itemImage: wearing ? MenuAnimation.menu_wearoff.value : MenuAnimation.menu_wear.value))
        items.append(ContextMenuItem(strings().modalCopyLink, handler: {
            arguments.copy(profile)
        }, itemImage: MenuAnimation.menu_copy_link.value))
        items.append(ContextMenuItem(strings().storyMyInputShare, handler: {
            StarsHooks.shared.shareLink(arguments.context, unique.link(arguments.context), arguments.context.window)
        }, itemImage: MenuAnimation.menu_share.value))
        if owner.id == arguments.context.peerId, unique.flags.contains(.isThemeAvailable) {
            items.append(ContextMenuItem(strings().giftContextMenuSetAsTheme, handler: {
                arguments.setGiftTheme?(unique)
            }, itemImage: MenuAnimation.menu_change_colors.value))
        }
        if unique.craftChancePermille != nil {
            items.append(ContextMenuItem(strings().starGiftCraftMenuItem, handler: {
                arguments.open(profile, nil, true)
            }, itemImage: MenuAnimation.menu_craft.value))
        }
        if let moveToGifts = StarsHooks.shared.giftMoveToGiftsAction(arguments.context, arguments.context.window, unique) {
            items.append(ContextMenuItem(strings().giftTransferMoveToGifts, handler: moveToGifts, itemImage: MenuAnimation.menu_replace.value))
        }
    }
    items.append(ContextMenuItem(profile.savedToProfile ? strings().giftContextHide : strings().giftContextShow, handler: {
        arguments.toggleVisibility(profile)
    }, itemImage: profile.savedToProfile ? MenuAnimation.menu_show.value : MenuAnimation.menu_hide.value))
    if profile.gift.unique != nil {
        items.append(ContextMenuItem(strings().giftContextTransfer, handler: {
            arguments.transfer(profile)
        }, itemImage: MenuAnimation.menu_transfer.value))
    }
    return items
}

private func _id_stars_gifts(_ index: Int) -> InputDataIdentifier {
    return InputDataIdentifier("_id_stars_gifts_\(index)")
}
private let _id_collections = InputDataIdentifier("_id_collections")
private let _id_empty = InputDataIdentifier("_id_empty")
private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    let index: Int32 = 0
    
    let access = state.peer?.id == arguments.context.peerId || state.peer?._asPeer().groupAccess.isCreator == true
    
    if state.collections.isEmpty {
        entries.append(.sectionId(sectionId, type: .customModern(8)))
        sectionId += 1
    } else {
        
        entries.append(.sectionId(sectionId, type: .customModern(0)))
        sectionId += 1
        
        
        let collections = state.collections.filter { value in
            if let state = state.collectionsState[value.stableId] {
                if !access {
                    return !state.gifts.isEmpty
                } else {
                    return true
                }
            } else {
                return value == .add
            }
        }
        
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_collections, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return CollectionRowItem(initialSize, stableId: stableId, context: arguments.context, filters: collections, selected: state.selectedCollection, arguments: arguments)
        }))
        
        entries.append(.sectionId(sectionId, type: .customModern(12)))
        sectionId += 1
    }
    
    _ = arguments.context.appConfiguration.getGeneralValue("stargifts_collection_gifts_limit", orElse: 500)

    let chunks: [[GiftOptionsRowItem.Option]]
    let collection = state.collections.first(where: { $0.stableId == state.selectedCollection }) ?? .all
    let list = state.gifts.map { GiftOptionsRowItem.Option.initialize($0, context: arguments.context) }
    chunks = list.chunks(state.perRowCount)

    
    if !chunks.isEmpty {
        for (i, chunk) in chunks.enumerated() {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_stars_gifts(i), equatable: .init(chunk), comparable: nil, item: { initialSize, stableId in
                return GiftOptionsRowItem(initialSize, stableId: stableId, context: arguments.context, options: chunk, perRowCount: state.perRowCount, fitToSize: list.count == 1, insets: NSEdgeInsets(left: 5, right: 5), callback: { option, morphSource in
                    if let value = option.nativeProfileGift {
                        arguments.open(value, morphSource, false)
                    } else {
                        arguments.addToCollection(collection, nil)
                    }
                }, contextMenu: { option in
                    guard let profile = option.nativeProfileGift else { return [] }
                    return arguments.giftMenu?(profile) ?? []
                })
            }))
            
            entries.append(.sectionId(sectionId, type: .customModern(10)))
            sectionId += 1
        }
    } else {
        if access {
            switch collection {
            case .collection:
                entries.append(.custom(
                    sectionId: sectionId,
                    index: index,
                    value: .none,
                    identifier: _id_empty,
                    equatable: .init(state.selectedCollection),
                    comparable: nil,
                    item: { initialSize, stableId in
                        return SearchEmptyRowItem(
                            initialSize,
                            stableId: stableId,
                            header: strings().peerMediaGiftsCollectionEmptyHeader,
                            text: strings().peerMediaGiftsCollectionEmptyText,
                            action: .init(
                                click: {
                                    arguments.addToCollection(collection, nil)
                                },
                                title: strings().peerMediaGiftsCollectionEmptyAction
                            )
                        )
                    }
                ))
            default:
                break
            }
        }
    }
   
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

private class CollectionPanel : View {
    private var add = TextButton()
    private var arguments: Arguments?

    private var collection: State.Collection?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.backgroundColor = .clear
        self.layer?.masksToBounds = false
        addSubview(add)

        add.set(handler: { [weak self] _ in
            if let arguments = self?.arguments, let collection = self?.collection {
                arguments.addToCollection(collection, nil)
            }
        }, for: .Click)

        add.setGlassEffect(tintColor: theme.colors.accent)
    }


    func update(collection: State.Collection, arguments: Arguments) {

        self.arguments = arguments
        self.collection = collection

        self.backgroundColor = .clear

        self.add.set(font: .medium(.text), for: .Normal)
        self.add.set(color: theme.colors.text, for: .Normal)
        self.add.set(text: strings().peerMediaGiftsCollectionPanelAddGifts, for: .Normal)
        self.add.sizeToFit(.zero, NSMakeSize(frame.width - 40, 40), thatFit: true)

        self.add.scaleOnClick = true
        self.add.autohighlight = false

        self.add.layer?.cornerRadius = 20

        needsLayout = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        add.frame = NSMakeRect(10, 0, frame.width - 20, 40)
    }
}

public class PeerMediaGiftsExternalArguments {
    public let setAlbum:(Int32)->Void
    public init(setAlbum:@escaping(Int32)->Void) {
        self.setAlbum = setAlbum
    }
}

public func PeerMediaGiftsController(context: any AccountContextProtocol, peerId: PeerId, starGiftsProfile: ProfileGiftsContext? = nil) -> InputDataController {

    let actionsDisposable = DisposableSet()
    let collectionsDisposable = DisposableDict<Int32>()

    actionsDisposable.add(collectionsDisposable)
    
    let initialState = State()
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var getController:(()->ViewController?)? = nil
    
    var window:Window {
        get {
            return bestWindow(context, getController?())
        }
    }
    
    var collectionsContexts:[Int32: ProfileGiftsContext] = [:]

    let giftsContext = starGiftsProfile ?? ProfileGiftsContext(account: context.account, peerId: peerId)
    
    
    let collectionsContext = ProfileGiftsCollectionsContext(account: context.account, peerId: peerId, allGiftsContext: giftsContext)
    
    
    let takeContext:() -> ProfileGiftsContext? = { [weak giftsContext, weak collectionsContext] in
        let collection = stateValue.with { $0.collection }
        
        switch collection {
        case .all:
            return giftsContext
        case let .collection(value):
            return collectionsContext?.giftsContextForCollection(id: value.id)
        default:
            return nil
        }
    }
    
        
    let peer = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
    
    let collectionsLimit = context.appConfiguration.getGeneralValue("stargifts_collections_limit", orElse: 10)
    let collectionGiftsLimit = context.appConfiguration.getGeneralValue("stargifts_collection_gifts_limit", orElse: 500)
    
    actionsDisposable.add(combineLatest(queue: .mainQueue(), giftsContext.state, peer, context.starsContext.state, collectionsContext.state).startStrict(next: { [weak collectionsDisposable] gifts, peer, starsState, collectionsState in
        updateState { current in
            var current = current
            current.collectionsState[State.Collection.all.stableId] = gifts
            current.peer = peer
            current.starsState = starsState
            if !collectionsState.collections.isEmpty {
                current.collections = [.all] + collectionsState.collections.map { .collection(value: $0) }
            }
            let access = peer?.id == context.peerId || peer?._asPeer().groupAccess.isCreator == true
            
            if access, !collectionsState.collections.isEmpty, collectionsLimit > collectionsState.collections.count {
                current.collections += [.add]
            }
            if !current.collections.contains(where: { $0.stableId == current.selectedCollection }) {
                current.selectedCollection = State.Collection.all.stableId
            }
            return current
        }
        
        var validKeys:Set<Int32> = Set()
        
        for collection in collectionsState.collections {
            if collectionsContexts[collection.id] == nil {
                let value = collectionsContext.giftsContextForCollection(id: collection.id)
                collectionsContexts[collection.id] = value
                collectionsDisposable?.set(value.state.start(next: { state in
                    updateState { current in
                        var current = current
                        current.collectionsState[collection.id] = state
                        return current
                    }
                }), forKey: collection.id)
            }
            validKeys.insert(collection.id)
        }
        
        var removeKeys:Set<Int32> = Set()
        for (key, _) in collectionsContexts {
            if !validKeys.contains(key) {
                removeKeys.insert(key)
            }
        }
        for key in removeKeys {
            collectionsContexts.removeValue(forKey: key)
            collectionsDisposable?.set(nil, forKey: key)
        }
    }))
    
    let renameCollection:(State.Collection)->Void = { [weak collectionsContext] collection in
        guard let collectionsContext else {
            return
        }
        
        switch collection {
        case let .collection(value):
            
            var text: String = ""
            var footer: ModalAlertData.Footer = .init(id: "footer", value: { initialSize, stableId, presentation, updateData in
                return InputDataRowItem(
                    initialSize,
                    stableId: stableId,
                    mode: .plain,
                    error: nil,
                    viewType: .singleItem,
                    currentText: value.title,
                    placeholder: nil,
                    inputPlaceholder: strings().peerMediaGiftsCollectionUpdatePlaceholder,
                    filter: { $0 },
                    updated: { updated in
                        text = updated
                        DispatchQueue.main.async(execute: updateData)
                    },
                    limit: 16
                )
            })

            footer.validateData = { _ in
                if text.isEmpty {
                    return .fail(.fields([InputDataIdentifier("footer") : .shake]))
                } else {
                    return .none
                }
            }

            let data = ModalAlertData(
                title: strings().peerMediaGiftsCollectionUpdateTitle,
                info: strings().peerMediaGiftsCollectionUpdateInfo,
                description: nil,
                ok: strings().peerMediaGiftsCollectionUpdateOk,
                options: [],
                mode: .confirm(text: strings().modalCancel, isThird: false),
                footer: footer
            )

            showModalAlert(for: window, data: data, completion: { result in
                actionsDisposable.add(
                    collectionsContext.renameCollection(id: value.id, title: text).start()
                )
            })

        default:
            break
        }
        
    }
    
    let addToCollection:(State.Collection, ProfileGiftsContext.State.StarGift?)->Void = { [weak collectionsContext] collection, gift in
        
        guard let collectionsContext else {
            return
        }
        
        switch collection {
        case let .collection(value):
            if let gift, let reference = gift.reference {
                
                let state = stateValue.with { $0 }
                let contains = state.contains(collectionId: value.id, gift: gift)
                if contains {
                    actionsDisposable.add(collectionsContext.removeGifts(id: value.id, gifts: [reference]).start())
                    showModalText(
                        for: window,
                        text: strings().peerMediaGiftsCollectionAlertRemoved(value.title)
                    )
                } else {
                    actionsDisposable.add(collectionsContext.addGifts(id: value.id, gifts: [gift]).start())
                    showModalText(
                        for: window,
                        text: strings().peerMediaGiftsCollectionAlertAdded(value.title)
                    )
                }

            } else {
                
                showModal(with: StarsHooks.shared.makeSelectGiftsModal(context, value.id, peerId, { [weak collectionsContext] selected, unselected in
                    
                  
                    var actions: [ProfileGiftsCollectionsContext.UpdateAction] = []
                    
                    if !selected.isEmpty {
                        actions.append(.addGifts(selected))
                    }
                    if !unselected.isEmpty {
                        actions.append(.removeGifts(unselected.compactMap(\.reference)))
                    }
                    if let collectionsContext {
                        actionsDisposable.add(collectionsContext.updateCollection(id: value.id, actions: actions).startStrict(next: { _ in
                            starGiftsProfile?.reload()
                        }))
                    }
                    

                }), for: context.window)
            }
            
        default:
            break
        }
    }
    
    let share:(State.Collection)->Void = { collection in
        switch collection {
        case let .collection(value):
            let peer = stateValue.with { $0.peer }
            if let address = peer?._asPeer().addressName {
                StarsHooks.shared.shareLink(context, context.meUrlPrefix + "\(address)/c/\(value.id)", window)
            }
        default:
            break
        }
    }

    var profileMenu: ((ProfileGiftsContext.State.StarGift) -> [ContextMenuItem])?
    let arguments = Arguments(context: context, open: { option, morphSource, crafting in

        let toPeer = stateValue.with { $0.peer }
        let fromPeer = option.fromPeer
        
        guard let toPeer else {
            return
        }
        let menuItems: (() -> [ContextMenuItem])? = toPeer.id == context.peerId || toPeer._asPeer().groupAccess.isCreator ? { profileMenu?(option) ?? [] } : nil

        let transaction = StarsContext.State.Transaction(flags: [], id: "", count: .init(amount: .init(value: option.gift.generic?.price ?? 0, nanos: 0), currency: .stars), date: option.date, peer: .peer(toPeer), title: "", description: nil, photo: nil, transactionDate: nil, transactionUrl: nil, paidMessageId: nil, giveawayMessageId: nil, media: [], subscriptionPeriod: nil, starGift: option.gift, floodskipNumber: nil, starrefCommissionPermille: nil, starrefPeerId: nil, starrefAmount: nil, paidMessageCount: nil, premiumGiftMonths: nil, adsProceedsFromDate: nil, adsProceedsToDate: nil)
        
        
        let purpose: Star_TransactionPurpose = .starGift(gift: option.gift, convertStars: option.convertStars ?? 0, text: option.text, entities: option.entities, nameHidden: option.fromPeer != nil, savedToProfile: option.savedToProfile, converted: option.convertStars == nil, fromProfile: true, upgraded: false, prepaidUpgradeHash: option.prepaidUpgradeHash, transferStars: option.convertStars, canExportDate: option.canExportDate, reference: option.reference, sender: nil, saverId: nil, canTransferDate: nil, canResaleDate: nil, dropOriginalDetailsStars: option.dropOriginalDetailsStars, canUpgrade: option.canUpgrade, number: option.number, isRefunded: option.isRefunded, canCraftAt: option.canCraftAt, craftChancePermille: option.gift.unique?.craftChancePermille, upgradeStars: option.upgradeStars)
        
        switch option.gift {
        case let .unique(gift):
            showModal(with: StarGift_Nft_Controller(context: context, gift: option.gift, source: .quickLook(toPeer, gift), transaction: transaction, purpose: .starGift(gift: option.gift, convertStars: option.convertStars, text: option.text, entities: option.entities, nameHidden: option.nameHidden, savedToProfile: option.savedToProfile, converted: false, fromProfile: true, upgraded: false, prepaidUpgradeHash: option.prepaidUpgradeHash, transferStars: option.transferStars, canExportDate: option.canExportDate, reference: option.reference, sender: option.fromPeer, saverId: nil, canTransferDate: option.canTransferDate, canResaleDate: option.canResaleDate, dropOriginalDetailsStars: option.dropOriginalDetailsStars, canUpgrade: option.canUpgrade, number: option.number, isRefunded: false, canCraftAt: option.canCraftAt, craftChancePermille: option.gift.unique?.craftChancePermille, upgradeStars: option.upgradeStars), giftsContext: takeContext(), pinnedInfo: option.reference.flatMap { .init(pinnedInfo: option.pinnedToTop, reference: $0) }, giftMenuItems: menuItems, openCrafting: crafting), for: context.window, morphSource: morphSource)
        default:
            showModal(with: Star_TransactionScreen(context: context, fromPeerId: peerId, peer: fromPeer, transaction: transaction, purpose: purpose, reference: option.reference, profileContext: takeContext(), giftMenuItems: menuItems), for: context.window, morphSource: morphSource)
        }
        

    }, togglePin: { option in
        if let reference = option.reference {
            var pinned = stateValue.with { $0.state?.gifts.filter({ $0.pinnedToTop }) ?? [] }
            if !option.pinnedToTop {
                pinned.insert(option, at: 0)
                pinned = Array(pinned.prefix(6))
            } else {
                pinned.removeAll(where: { $0.reference == reference })
            }
            takeContext()?.updatePinnedToTopStarGifts(references: pinned.compactMap(\.reference))
        }
    }, toggleWear: { option in
        let peer = stateValue.with({ $0.peer?._asPeer() })
        if let peer, let unique = option.gift.unique, let file = unique.file {
            context.reactions.setStatus(file, peer: peer, timestamp: context.timestamp, timeout: nil, fromRect: nil, starGift: unique)
        }
    }, transfer: { option in
        let state = stateValue.with { $0 }
        let canExportDate: Int32? = option.canExportDate
        let transferStars: Int64? = option.transferStars
        guard let reference = option.reference, let unique = option.gift.unique else {
            return
        }
        if unique.hostPeerId != nil, unique.giftAddress != nil {
            verifyAlert(for: window, header: strings().starGiftActionLockedTitle, information: strings().starGiftActionLockedText, ok: strings().starGiftActionLockedOpen, successHandler: { _ in
                LinkHooks.shared.openExternalLink(strings().starGiftActionLockedURL, false)
            })
            return
        }
        if let canTransferDate = option.canTransferDate, canTransferDate > context.timestamp {
            alert(for: window, header: strings().giftTransferUnavailableTitle, info: strings().giftTransferUnavailableText(stringForFullDate(timestamp: canTransferDate)))
            return
        }
        showGiftTransfer(context: context, window: window, gift: unique, reference: reference, giftsContext: takeContext() ?? giftsContext, canExportDate: canExportDate, transferStars: transferStars, transfer: { peer, dismiss in
            if let transferStars, let starsState = state.starsState, starsState.balance.value < transferStars {
                FeatureNavigationHooks.shared.showStarsPurchaseWithContext(context, window, .stars, nil, transferStars)
                return
            }
            dismiss()
            if let giftsContext = takeContext() {
                _ = (giftsContext.transferStarGift(prepaid: transferStars == nil, reference: reference, peerId: peer.id)).startStandalone()
            }
            _ = (showModalSuccess(for: context.window, icon: theme.icons.successModalProgress, delay: 1.5)).start()
        })
    }, toggleVisibility: { option in
        if let reference = option.reference {
            takeContext()?.updateStarGiftAddedToProfile(reference: reference, added: !option.savedToProfile)
        }
    }, copy: { option in
        copyToClipboard(option.gift.unique!.link(context))
        showModalText(for: window, text: strings().contextAlertCopied)
    }, collection: { collection, gift in
        if collection == .add {
            
            var text: String = ""
            
            var footer: ModalAlertData.Footer = .init(id: "footer", value: { initialSize, stableId, presentation, updateData in
                return InputDataRowItem(
                    initialSize,
                    stableId: stableId,
                    mode: .plain,
                    error: nil,
                    viewType: .singleItem,
                    currentText: "",
                    placeholder: nil,
                    inputPlaceholder: strings().peerMediaGiftsCollectionNewPlaceholder,
                    filter: { $0 },
                    updated: { updated in
                        text = updated
                        DispatchQueue.main.async(execute: updateData)
                    },
                    limit: 16
                )
            })

            footer.validateData = { _ in
                if text.isEmpty {
                    return .fail(.fields([InputDataIdentifier("footer") : .shake]))
                } else {
                    return .none
                }
            }

            let data = ModalAlertData(
                title: strings().peerMediaGiftsCollectionNewTitle,
                info: strings().peerMediaGiftsCollectionNewInfo,
                description: nil,
                ok: strings().peerMediaGiftsCollectionNewOk,
                options: [],
                mode: .confirm(text: strings().modalCancel, isThird: false),
                footer: footer
            )

            
            showModalAlert(for: window, data: data, completion: { result in
                actionsDisposable.add(collectionsContext.createCollection(title: text, starGifts: gift.flatMap({ [$0] }) ?? []).start(next: { collection in
                    
                    updateState { current in
                        var current = current
                        if let id = collection?.id {
                            current.selectedCollection = id
                        }
                        return current
                    }
                }))
            })
        } else {
            updateState { current in
                var current = current
                current.selectedCollection = collection.stableId
                return current
            }
        }
    }, addToCollection: { collection, gift in
        addToCollection(collection, gift)
    }, collectionContextMenu: { [weak collectionsContext] collection in
        switch collection {
        case .add:
           return []
        case .all:
            return []
        case let .collection(value):
            var items: [ContextMenuItem] = []
            
            let state = stateValue.with { $0 }
            let access = state.peer?.id == context.peerId || state.peer?._asPeer().groupAccess.isCreator == true

            if access {
                items.append(ContextMenuItem(
                    strings().peerMediaGiftsCollectionContextAddGifts,
                    handler: {
                        addToCollection(collection, nil)
                    },
                    itemImage: MenuAnimation.menu_add.value
                ))

                items.append(ContextMenuItem(
                    strings().peerMediaGiftsCollectionContextRename,
                    handler: {
                        renameCollection(collection)
                    },
                    itemImage: MenuAnimation.menu_edit.value
                ))
                let peer = stateValue.with { $0.peer }
                if peer?.addressName != nil {
                    items.append(ContextMenuItem(
                        strings().modalShare,
                        handler: {
                            share(collection)
                        },
                        itemImage: MenuAnimation.menu_share.value
                    ))
                }
               

                items.append(ContextSeparatorItem())

                items.append(ContextMenuItem(
                    strings().peerMediaGiftsCollectionContextDelete,
                    handler: {
                        verifyAlert(
                            for: window,
                            information: strings().peerMediaGiftsCollectionContextDeleteConfirm(value.title),
                            successHandler: { _ in
                                if let collectionsContext {
                                    actionsDisposable.add(collectionsContext.deleteCollection(id: collection.stableId).start())
                                }
                            }
                        )
                    },
                    itemMode: .destruct,
                    itemImage: MenuAnimation.menu_delete.value
                ))

            }
           
            return items
        }
    }, resort: { [weak collectionsContext] from, to in
        
        let state = stateValue.with { $0 }
        var list = state.collections
        list.move(at: from, to: to)
        
        _ = collectionsContext?.reorderCollections(order: list.compactMap { value in
            switch value {
            case let .collection(value):
                return value.id
            default:
                return nil
            }
        }).start()
    })
    
    arguments.setGiftTheme = { gift in
        actionsDisposable.add(setStarGiftAsChatTheme(context: context, window: window, gift: gift, completion: {}))
    }
    arguments.deleteGift = { [weak giftsContext] gift in
        guard let reference = gift.reference, let owner = stateValue.with({ $0.peer }), starGiftCanDelete(gift: gift.gift, reference: reference, owner: owner, accountPeerId: context.peerId, converted: false, fromProfile: true, upgraded: false, refunded: gift.isRefunded) else {
            return
        }
        verifyAlert(for: window, header: strings().giftDeleteTitle, information: strings().giftDeleteText, ok: strings().modalDelete, successHandler: { _ in
            let signal = context.engine.payments.deleteStarGift(reference: reference) |> deliverOnMainQueue
            _ = showModalProgress(signal: signal, for: window).startStandalone(completed: {
                let state = stateValue.with { $0 }
                func reload(_ giftContext: ProfileGiftsContext, state: ProfileGiftsContext.State?) {
                    if let state, state.filter != .All || state.sorting != .date {
                        giftContext.updateFilter(state.filter == .All ? .unlimited : .All)
                        giftContext.updateFilter(state.filter)
                    } else {
                        giftContext.reload()
                    }
                }
                if let giftsContext {
                    reload(giftsContext, state: state.state)
                }
                for (id, collection) in collectionsContexts {
                    reload(collection, state: state.collectionsState[id])
                }
            })
        })
    }
    profileMenu = { [weak arguments] original in
        guard let arguments, let reference = original.reference else { return [] }
        let state = stateValue.with { $0 }
        guard let current = state.gifts.first(where: { $0.reference == reference }) ?? state.state?.gifts.first(where: { $0.reference == reference }) else { return [] }
        return giftMenuItems(current, state: state, arguments: arguments)
    }
    arguments.giftMenu = profileMenu

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: "")
    controller.bar = .init(height: 0)
    
    controller._menuItems = {
        var items: [ContextMenuItem] = []
        
        let state = stateValue.with { $0 }
        
        if let peer = state.peer?._asPeer(), peer.id == context.peerId || peer.groupAccess.isCreator {
            items.append(ContextMenuItem(strings().peerMediaGiftsCollectionContextAddCollection, handler: {
                arguments.collection(.add, nil)
            }, itemImage: MenuAnimation.menu_add.value))
            
            items.append(ContextSeparatorItem())
        }
        
        
        if let peer = state.peer?._asPeer(), peer.isChannel, let notificationsEnabled = state.state?.notificationsEnabled {
            items.append(ContextMenuItem(strings().peerInfoGiftsChannelNotify, handler: {
                _ = context.engine.payments.toggleStarGiftsNotifications(peerId: peer.id, enabled: !notificationsEnabled).start()
                updateState { current in
                    var current = current
                    current.notificationsEnabled(!notificationsEnabled)
                    return current
                }
                showModalText(for: context.window, text: !notificationsEnabled ? strings().peerInfoGiftsChannelNotifyTooltip : strings().peerInfoGiftsChannelNotifyDisabledTooltip)
            }, state: notificationsEnabled ? .on : nil))
            
            items.append(ContextSeparatorItem())
        }
        if let peer = state.peer?._asPeer(), let giftState = state.effectiveState {
            
            
            let allFiltes: [ProfileGiftsContext.Filters] = [.unlimited, .limitedUpgradable, .limitedNonUpgradable, .unique]
            
            let switchToFilter: (ProfileGiftsContext.Filters) -> Void = { value in
                var updatedFilter = giftState.filter
                updatedFilter.remove(.unlimited)
                updatedFilter.remove(.limitedUpgradable)
                updatedFilter.remove(.limitedNonUpgradable)
                updatedFilter.remove(.unique)
                updatedFilter.insert(value)
                takeContext()?.updateFilter(updatedFilter)
            }
            
            let toggleFilter: (ProfileGiftsContext.Filters) -> Void = { value in
                var updatedFilter = giftState.filter
                
                let allEnabled = allFiltes.allSatisfy({ updatedFilter.contains($0) })
                
                if allEnabled && value != .hidden && value != .displayed {
                    switchToFilter(value)
                } else {
                    if updatedFilter.contains(value) {
                        updatedFilter.remove(value)
                    } else {
                        updatedFilter.insert(value)
                    }
                    if !updatedFilter.contains(.unlimited) && !updatedFilter.contains(.limitedUpgradable) && !updatedFilter.contains(.limitedNonUpgradable) && !updatedFilter.contains(.unique) {
                        updatedFilter.insert(.unlimited)
                    }
                    
                    if !updatedFilter.contains(.displayed) && !updatedFilter.contains(.hidden) {
                        if value == .displayed {
                            updatedFilter.insert(.hidden)
                        } else {
                            updatedFilter.insert(.displayed)
                        }
                    }
                    takeContext()?.updateFilter(updatedFilter)
                }
            }
            
            if state.selectedCollection == State.Collection.all.stableId {
                items.append(ContextMenuItem(giftState.sorting == .value ? strings().peerInfoGiftsSortByDate : strings().peerInfoGiftsSortByValue, handler: {
                    takeContext()?.updateSorting(giftState.sorting == .value ? .date : .value)
                }))
                
                items.append(ContextSeparatorItem())
            }
            
            items.append(ContextMenuItem(strings().peerInfoGiftsUnlimited, handler: {
                toggleFilter(.unlimited)
            }, state: giftState.filter.contains(.unlimited) ? .on : nil))
            
            items.append(ContextMenuItem(strings().peerInfoGiftsLimited, handler: {
                toggleFilter(.limitedNonUpgradable)
            }, state: giftState.filter.contains(.limitedNonUpgradable) ? .on : nil))
            
            items.append(ContextMenuItem(strings().selectGiftsFilterUpgradable, handler: {
                toggleFilter(.limitedUpgradable)
            }, state: giftState.filter.contains(.limitedUpgradable) ? .on : nil))
            
            items.append(ContextMenuItem(strings().peerInfoGiftsUnique, handler: {
                toggleFilter(.unique)
            }, state: giftState.filter.contains(.unique) ? .on : nil))
            
            if peer.groupAccess.canManageGifts || peer.id == context.peerId {
                items.append(ContextSeparatorItem())
                
                items.append(ContextMenuItem(strings().peerInfoGiftsDisplayed, handler: {
                    toggleFilter(.displayed)
                }, state: giftState.filter.contains(.displayed) ? .on : nil))
                
                items.append(ContextMenuItem(strings().peerInfoGiftsHidden, handler: {
                    toggleFilter(.hidden)
                }, state: giftState.filter.contains(.hidden) ? .on : nil))
            }
           
        }
       
        
        return items
    }
    
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
        collectionsContexts = [:]
    }
    
    weak var panelView: CollectionPanel?
    
    
    controller.didResize = { controller in
        var rowCount:Int = 3
        var perWidth: CGFloat = 0
        let blockWidth = max(380, controller.atomicSize.with { $0.width })
        while true {
            let maximum = blockWidth - CGFloat(rowCount * 2)
            perWidth = maximum / CGFloat(rowCount)
            if perWidth >= 135 {
                break
            } else {
                rowCount -= 1
            }
        }
        updateState { current in
            var current = current
            current.perRowCount = rowCount
            return current
        }
        
        if let panelView, let parent = panelView.superview {
            panelView.frame = NSMakeRect(0, parent.frame.height - 50, parent.frame.width, 50)
        }
        
    }
    
    controller.willMove = { window in
        updateState { current in
            var current = current
            current.onStage = window != nil
            return current
        }
    }
    
    controller.getBackgroundColor = {
        theme.colors.listBackground
    }
    
    controller.didLoad = { [weak giftsContext, weak collectionsContext] controller, _ in
        
        controller.tableView.verticalScrollElasticity = .none

        
        
        
        controller.tableView.setScrollHandler { position in
            switch position.direction {
            case .bottom:
                let state = stateValue.with { $0 }
                if state.selectedCollection == State.Collection.all.stableId {
                    giftsContext?.loadMore()
                } else {
                    collectionsContext?.giftsContextForCollection(id: state.selectedCollection).loadMore()
                }
            default:
                break
            }
        }
    }
    
    
    actionsDisposable.add((statePromise.get() |> deliverOnMainQueue).startStrict(next: { [weak controller] state in
        
        guard let controller, controller.isLoaded() else {
            return
        }
        
        
        let access = state.peer?.id == arguments.context.peerId || state.peer?._asPeer().groupAccess.isCreator == true

        
        if access, state.selectedCollection != State.Collection.all.stableId, !state.gifts.isEmpty, state.count < collectionGiftsLimit {

            let parent = controller.genericView

            let current: CollectionPanel
            if let view = panelView {
                current = view
            } else {
                current = CollectionPanel(frame: NSMakeRect(0, parent.frame.height - 50, parent.frame.width, 50))
                current.autoresizingMask = [.width, .minYMargin]
                parent.addSubview(current)
                panelView = current

                current.layer?.animatePosition(from: NSMakePoint(0, parent.frame.height), to: current.frame.origin)
            }

            current.update(collection: state.collection, arguments: arguments)
        } else if let view = panelView, let parent = view.superview {
            performSubviewPosRemoval(view, pos: NSMakePoint(0, parent.frame.height), animated: true)
            panelView = nil
        }
    }))
    
    controller.contextObject = (giftsContext, collectionsContext, collectionsContexts)
    controller.contextObject_second = PeerMediaGiftsExternalArguments(setAlbum: { value in
        updateState { current in
            var current = current
            current.selectedCollection = value
            return current
        }
    })
    return controller
    
}




