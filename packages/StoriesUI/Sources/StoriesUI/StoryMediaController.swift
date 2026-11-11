import Cocoa
import TGUIKit
import TelegramCore
import SwiftSignalKit
import Postbox
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import GeneralRows
import InputDataUI
import AlertsUI
import LocalAnimations
import ChatUI
import InlineStickerLayer
import AppAnalytics



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
            return FilterChipRowItem(size, stableId: stableId, context: arguments.context, text: self.text, selected: self.selected, select: { arguments.collection(self.value, nil) }, contextMenu: { arguments.collectionContextMenu(self.value) })
        }
        
        var text: NSAttributedString {
            let attr = NSMutableAttributedString()
            switch self.value {
            case .all:
                attr.append(
                    string: strings().storyMediaAlbumAll,
                    color: theme.colors.text,
                    font: .medium(.title)
                )
            case let .collection(value):
                attr.append(
                    string: value.title,
                    color: theme.colors.text,
                    font: .medium(.title)
                )
            case .add:
                attr.append(
                    string: "\(clown_space)\(strings().storyMediaAlbumAdd)",
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
    fileprivate let selected: Int64?
    fileprivate let context: (any AccountContextProtocol)?
    fileprivate let arguments: Arguments?
    fileprivate let _stableId: AnyHashable
    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, filters: [State.Collection], selected: Int64, arguments: Arguments) {
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
    
    override func viewClass() -> AnyClass {
        return CollectionFilterRowView.self
    }

    override var accessibilityLabel: String? {
        return strings().voiceOverCommonFilter
    }
}

private final class CollectionFilterRowView : TableStickView, TableViewDelegate {
    func selectionDidChange(row: Int, item: TableRowItem, byClick: Bool, isNew: Bool) {
        if let item = item as? FilterChipRowItem {
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
        _ = item.context
        let items = item.items
        let arguments = item.arguments
        
        guard let arguments else {
            return
        }
        
        applyMergedRows(tableView, current: &self.items, items: items, animated: animated, makeItem: { item in
            return item.makeItem(bounds.size, arguments: arguments)
        })
        

        let albumIndices = items.indices.filter { index in
            if case .collection = items[index].value { return true }
            return false
        }
        if arguments.state()?.access(arguments.context.peerId) == true, let first = albumIndices.first, albumIndices.count > 1 {
            tableView.resortController = .init(resortRange: NSMakeRange(first, albumIndices.count), start: { _ in }, resort: { _ in }, complete: { [weak self] from, to in
                guard let self else { return }
                let matchesSnapshot = self.items.map(\.stableId) == items.map(\.stableId)
                let validIndices = albumIndices.contains(from) && albumIndices.contains(to)
                if matchesSnapshot && validIndices {
                    self.items.move(at: from, to: to)
                    self.items = self.items.enumerated().map { index, item in
                        CollectionRowItem.Item(value: item.value, index: index, selected: item.selected)
                    }
                } else {
                    self.tableView.removeAll()
                    self.items.removeAll()
                }
                if let currentItem = self.item {
                    self.set(item: currentItem, animated: false)
                }
                guard matchesSnapshot, validIndices, from != to,
                      case let .collection(source) = items[from].value,
                      case let .collection(target) = items[to].value else { return }
                arguments.resort(source.id, target.id)
            })
        } else {
            tableView.resortController = nil
        }
        
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


private enum Entry : TableItemListNodeEntry {
    case headerText(index: MessageIndex, stableId: MessageIndex, text: String, viewType: GeneralViewType)
    case month(index: MessageIndex, stableId: MessageIndex, peerId: PeerId, peerReference: PeerReference, items: [StoryListContextState.Item], selected: Set<StoryId>?, pinnedIds: [Int32], rowCount: Int, viewType: GeneralViewType, nextRowCount: Int?, collections: [State.Collection])
    case date(index: MessageIndex)
    case section(index: MessageIndex, height: CGFloat)
    case collections(index: MessageIndex, [State.Collection], Int64)
    case emptySelf(index: MessageIndex, collection: State.Collection, viewType: GeneralViewType)
    static func < (lhs: Entry, rhs: Entry) -> Bool {
        return lhs.index < rhs.index
    }

    func item(_ arguments: Arguments, initialSize: NSSize) -> TableRowItem {
        switch self {
        case let .headerText(_, stableId, text, viewType):
            return GeneralBlockTextRowItem(initialSize, stableId: stableId, viewType: viewType, text: text, font: .normal(.text))
        case let .month(_, stableId, peerId, peerReference, items, selected, pinnedIds, rowCount, viewType, nextRowCount, collections):
            return StoryMonthRowItem(initialSize, stableId: stableId, context: arguments.context, standalone: arguments.standalone, peerId: peerId, peerReference: peerReference, items: items, selected: selected, pinnedIds: pinnedIds, rowCount: rowCount, nextRowCount: nextRowCount, clipsToPosts: !arguments.standalone, viewType: viewType, openStory: arguments.openStory, toggleSelected: arguments.toggleSelected, menuItems: { [arguments] story in
                var items: [ContextMenuItem] = []
                if selected == nil, arguments.isMy, let state = arguments.state() {
                    
                    let addItem = ContextMenuItem(
                        strings().storyMediaAlbumContextMenuAddToAlbum,
                        handler: {},
                        itemImage: MenuAnimation.menu_add_to_folder.value
                    )

                    let foldersLimit = arguments.context.appConfiguration.getGeneralValue("stories_albums_limit", orElse: 16)

                    let addMenu = ContextMenu()
                    if foldersLimit > state.folderCount {
                        addMenu.addItem(ContextMenuItem(
                            strings().storyMediaAlbumContextMenuNewAlbum,
                            handler: {
                                arguments.collection(.add, story)
                            },
                            itemImage: MenuAnimation.menu_folder_add.value
                        ))

                        addMenu.addItem(ContextSeparatorItem())
                    }

                    
                    for collection in collections {
                        switch collection {
                        case let .collection(value):
                            
                            let contains = state.contains(collectionId: value.id, story: story.storyItem)
                            
                            let item = ContextMenuItem(value.title, handler: {
                                arguments.addToCollection(collection, story)
                            }, state: contains ? .on : nil)
                            
                            if let preview = state.previews {
                                if let folder = preview.folder.first(where: { $0.folder.id == collection.stableId }), let story = folder.item {
                                    ContextMenuItem.makeFolderPreview(item, context: arguments.context, peerReference: preview.peer, story: story)
                                }
                            }
                            
                            
                            addMenu.addItem(item)
                            
                        default:
                            break
                        }
                    }
                    
                    if !addMenu.items.isEmpty  {
                        addItem.submenu = addMenu
                        
                        items.append(addItem)
                        items.append(ContextSeparatorItem())
                    }

                    if !story.storyItem.isPinned {
                        items.append(ContextMenuItem(strings().storyMediaUnarchive, handler: { [weak arguments] in
                            arguments?.toggleStory(story.storyItem)
                        }, itemImage: MenuAnimation.menu_save_to_profile.value))
                    } else {
                        items.append(ContextMenuItem(strings().storyMediaArchive, handler: { [weak arguments] in
                            arguments?.toggleStory(story.storyItem)
                        }, itemImage: MenuAnimation.menu_archive.value))
                    }
                    
                    items.append(ContextMenuItem(pinnedIds.contains(story.storyItem.id) ? strings().messageContextUnpin : strings().messageContextPin, handler: { [weak arguments] in
                        arguments?.togglePinned(story.storyItem)
                    }, itemImage: pinnedIds.contains(story.storyItem.id) ? MenuAnimation.menu_unpin.value : MenuAnimation.menu_pin.value))
                    
                    items.append(ContextMenuItem(strings().messageContextSelect, handler: { [weak arguments] in
                        arguments?.toggleSelected(.init(peerId: peerId, id: story.storyItem.id))
                    }, itemImage: MenuAnimation.menu_check_selected.value))
                    
                    items.append(ContextSeparatorItem())
                    
                    items.append(ContextMenuItem(strings().messageContextDelete, handler: { [weak arguments] in
                        arguments?.deleteStory(story.storyItem)
                    }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                }
                return items
            })
        case let .emptySelf(index, collection, viewType):
            if collection != .all {
                return SearchEmptyRowItem(
                    initialSize,
                    stableId: stableId,
                    header: strings().storyMediaAlbumEmptyHeader,
                    text: strings().storyMediaAlbumEmptyText,
                    action: .init(
                        click: {
                            arguments.addToCollection(collection, nil)
                        },
                        title: strings().storyMediaAlbumEmptyAction
                    )
                )
            } else {
                return StoryMyEmptyRowItem(initialSize, stableId: index, context: arguments.context, viewType: viewType, isArchive: arguments.isArchive, showArchive: arguments.showArchive)
            }
        case .date:
            return PeerMediaDateItem(initialSize, index: index, stableId: stableId, inset: !arguments.standalone ? .init() : NSEdgeInsets(left: 20, right: 20))
        case let .collections(_, collections, selected):
            return CollectionRowItem(initialSize, stableId: stableId, context: arguments.context, filters: collections, selected: selected, arguments: arguments)
        case let .section(_, height):
            return GeneralRowItem(initialSize, height: height, stableId: stableId, viewType: .separator)
        }
    }
    
    var stableId: MessageIndex {
        switch self {
        case let .month(_, stableId, _, _, _, _, _, _, _, _, _):
            return stableId
        default:
            return self.index
        }
    }
    
    var index: MessageIndex {
        switch self {
        case let .month(index, _, _, _, _, _, _, _, _, _, _):
            return index
        case let .headerText(index, _, _, _):
            return index
        case let .emptySelf(index, _, _):
            return index
        case let .date(index):
            return index
        case let .section(index, _):
            return index
        case let .collections(index, _, _):
            return index
        }
    }
}

private final class Arguments {
    let context: any AccountContextProtocol
    let standalone: Bool
    let isArchive: Bool
    let isMy: Bool
    let openStory:(StoryInitialIndex?)->Void
    let toggleSelected:(StoryId)->Void
    let showArchive:()->Void
    let archiveSelected:()->Void
    let toggleStory: (EngineStoryItem)->Void
    let deleteStory:(EngineStoryItem)->Void
    let togglePinned:(EngineStoryItem)->Void
    let deleteSelected:()->Void
    let togglePinSelected:()->Void
    let collection:(State.Collection, StoryListContextState.Item?)->Void
    let addToCollection:(State.Collection, StoryListContextState.Item?)->Void
    let collectionContextMenu:(State.Collection)->[ContextMenuItem]
    let resort:(Int64, Int64)->Void
    let state:()->State?
    init(context: any AccountContextProtocol, standalone: Bool, isArchive: Bool, isMy: Bool, openStory: @escaping(StoryInitialIndex?)->Void, toggleSelected:@escaping(StoryId)->Void, showArchive:@escaping()->Void, archiveSelected:@escaping()->Void, toggleStory: @escaping(EngineStoryItem)->Void, deleteStory:@escaping(EngineStoryItem)->Void, deleteSelected:@escaping()->Void, togglePinned:@escaping(EngineStoryItem)->Void, togglePinSelected:@escaping()->Void, collection:@escaping(State.Collection, StoryListContextState.Item?)->Void, addToCollection: @escaping(State.Collection, StoryListContextState.Item?)->Void, collectionContextMenu:@escaping(State.Collection)->[ContextMenuItem], resort:@escaping(Int64, Int64)->Void, state:@escaping()->State?) {
        self.context = context
        self.standalone = standalone
        self.isArchive = isArchive
        self.isMy = isMy
        self.openStory = openStory
        self.showArchive = showArchive
        self.toggleSelected = toggleSelected
        self.archiveSelected = archiveSelected
        self.toggleStory = toggleStory
        self.deleteStory = deleteStory
        self.deleteSelected = deleteSelected
        self.togglePinned = togglePinned
        self.togglePinSelected = togglePinSelected
        self.collection = collection
        self.addToCollection = addToCollection
        self.collectionContextMenu = collectionContextMenu
        self.resort = resort
        self.state = state
    }
}

private struct State : Equatable {
    
    enum Collection : Equatable {
        case all
        case collection(value: PeerStoryListContext.State.Folder)
        case add
        
        var stableId: Int64 {
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
    
    struct Preview: Equatable {
        struct Folder : Equatable {
            var folder: StoryListContext.State.Folder
            var item: EngineStoryItem?
        }
        var peer: PeerReference
        var folder: [Folder]
    }
    
    var state:PeerStoryListContext.State? {
        return collectionStates[selectedCollection] ?? collectionStates[Collection.all.stableId]
    }
    
    var mainState: PeerStoryListContext.State? {
        return collectionStates[Collection.all.stableId]
    }
    
    func contains(collectionId: Int64, story: EngineStoryItem) -> Bool {
        if let album = collectionStates[collectionId] {
            if album.items.contains(where: { $0.id.id == story.id }) { return true }
            if !album.isCached, album.loadMoreToken == nil { return false }
        }
        let currentStory = mainState?.items.first(where: { $0.id.id == story.id })?.storyItem ?? story
        return currentStory.folderIds?.contains(collectionId) == true
    }
    

    var selected:Set<StoryId>? = nil
    var perRowCount: Int
    var peer: EnginePeer?
    var collectionStates:[Int64: PeerStoryListContext.State] = [:]
    var onStage: Bool = false
    
    var previews: Preview?
    
    func access(_ accountPeerId: PeerId) -> Bool {
        return peer?.id == accountPeerId || peer?._asPeer().groupAccess.canManageStories == true
    }
    
    var collections: [Collection] = []
    var selectedCollection: Int64 = Collection.all.stableId
    
    var collection: Collection {
        return self.collections.first(where: { $0.stableId == selectedCollection}) ?? .all
    }
    
    var folderCount: Int {
        return collections.reduce(0, { current, value in
            switch value {
            case .collection:
                return current + 1
            default:
                return current
            }
        })
    }

    init(state: PeerStoryListContext.State?, selected:Set<StoryId>?, perRowCount: Int) {
        self.collectionStates[Collection.all.stableId] = state
        self.selected = selected
        self.perRowCount = perRowCount
    }
}

private let _id_collections = InputDataIdentifier("_id_collections")

private func entries(_ state: State, arguments: Arguments) -> [Entry] {
    var entries:[Entry] = []
    
    let standalone = arguments.standalone

    let selected = state.selected
    
    let perRowCount = state.perRowCount
    
    var index = MessageIndex.absoluteLowerBound()

    
    if !arguments.standalone, !state.collections.isEmpty {
        entries.append(.collections(index: index, state.collections, state.selectedCollection))
        index = index.peerLocalSuccessor()
        entries.append(.section(index: index, height: 12))
        index = index.peerLocalSuccessor()
    }

    if let contextState = state.state, !contextState.items.isEmpty, let peerReference = contextState.peerReference {
        
        
        
        let items = contextState.items.uniqueElements
        let peerId = peerReference.id
        let viewType: GeneralViewType = .modern(position: .single, insets: NSEdgeInsetsMake(0, 0, 0, 0))
        
        entries.append(.month(index: MessageIndex.absoluteUpperBound(), stableId: MessageIndex.absoluteUpperBound(), peerId: peerId, peerReference: peerReference, items: items, selected: selected, pinnedIds: contextState.pinnedIds, rowCount: perRowCount, viewType: viewType, nextRowCount: nil, collections: state.collections))

        var index = MessageIndex.absoluteUpperBound()
        
        if standalone {
            if arguments.isArchive, arguments.isMy {
                entries.append(.section(index: index, height: 20))
                index = index.peerLocalPredecessor()
                entries.insert(.headerText(index: index, stableId: index, text: strings().storyMediaArchiveText, viewType: .singleItem), at: 0)
                index = index.peerLocalPredecessor()
            } else if arguments.isMy {
                entries.insert(.section(index: index, height: 20), at: 0)
                index = index.peerLocalPredecessor()
            }
            entries.append(.section(index: index, height: 20))
            index = index.peerLocalPredecessor()
        } else {
            if standalone {
                entries.append(.section(index: index, height: 20))
                index = index.peerLocalSuccessor()
            }
        }

    } else {
        if standalone {
            entries.append(.section(index: index, height: 20))
            index = index.peerLocalSuccessor()
        }
        if arguments.isMy {
            entries.append(.emptySelf(index: index, collection: state.collection, viewType: .singleItem))
        }
    }

    var updated:[Entry] = []
    

    var j: Int = 0
    for entry in entries {
        switch entry {
        case let .month(index, _, peerId, peerReference, items, _, pinnedIds, rowCount, _, _, collections):
            let chunks = items.chunks(state.perRowCount)
            for (i, chunk) in chunks.enumerated() {
                let item = chunk[0]
                let stableId = MessageIndex(id: MessageId(peerId: index.id.peerId, namespace: 0, id: item.storyItem.id), timestamp: item.storyItem.timestamp)

                let viewType: GeneralViewType = bestGeneralViewType(chunks, for: i)
                let updatedViewType: GeneralViewType = .modern(position: viewType.position, insets: NSEdgeInsetsMake(0, 0, 0, 0))
                let nextRowCount = i + 1 < chunks.count ? chunks[i + 1].count : nil
                updated.append(.month(index: index, stableId: stableId, peerId: peerId, peerReference: peerReference, items: chunk, selected: selected, pinnedIds: pinnedIds, rowCount: rowCount, viewType: updatedViewType, nextRowCount: nextRowCount, collections: collections))
            }
            j += 1
        case .date:
            updated.append(entry)
        case .emptySelf:
            updated.append(entry)
        case .section:
            updated.append(entry)
        case .headerText:
            updated.append(entry)
        case .collections:
            updated.append(entry)
        }
    }

 
    
    return updated
}




fileprivate func prepareTransition(left:[AppearanceWrapperEntry<Entry>], right: [AppearanceWrapperEntry<Entry>], animated: Bool, initialSize:NSSize, arguments: Arguments) -> TableUpdateTransition {
    let (removed, inserted, updated) = proccessEntriesWithoutReverse(left, right: right) { entry -> TableRowItem in
        return entry.entry.item(arguments, initialSize: initialSize)
    }
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: animated, state: .none(nil))
}


public final class StoryMediaView : View {
    
    fileprivate var willMove: ((NSWindow?)->Void)? = nil

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        
        self.willMove?(newWindow)
    }
    
    private class Panel : View {
        private static let buttonHeight: CGFloat = 40
        private var pin = ImageButton()
        private var archive = TextButton()
        private var delete = ImageButton()

        private var arguments: Arguments?

        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            self.layer?.masksToBounds = false
            addSubview(pin)
            addSubview(archive)
            addSubview(delete)

            self.pin.autohighlight = false
            self.pin.scaleOnClick = true

            self.archive.autohighlight = false
            self.archive.scaleOnClick = true

            self.delete.autohighlight = false
            self.delete.scaleOnClick = true

            let iconSize = NSMakeSize(Panel.buttonHeight, Panel.buttonHeight)
            self.pin.setGlassEffect(size: iconSize)
            self.archive.setGlassEffect()
            self.delete.setGlassEffect(size: iconSize)

            self.pin.setAccessibilityLabel(strings().voiceOverCommonPin)
            self.delete.setAccessibilityLabel(strings().voiceOverCommonDelete)

            delete.set(handler: { [weak self] _ in
                self?.arguments?.deleteSelected()
            }, for: .Click)


            archive.set(handler: { [weak self] _ in
                if let arguments = self?.arguments {
                    arguments.archiveSelected()
                }
            }, for: .Click)

            pin.set(handler: { [weak self] _ in
                if let arguments = self?.arguments {
                    arguments.togglePinSelected()
                }
            }, for: .Click)
        }


        func update(selected: Set<StoryId>, isArchive: Bool, arguments: Arguments) {

            self.arguments = arguments

            self.border = []
            self.backgroundColor = .clear

            self.pin.set(image: theme.icons.chatSwiping_pin, for: .Normal)
            self.pin.sizeToFit(.zero, NSMakeSize(Panel.buttonHeight, Panel.buttonHeight), thatFit: true)

            self.archive.set(font: .medium(.text), for: .Normal)
            self.archive.set(color: theme.colors.text, for: .Normal)
            self.archive.set(text: isArchive ? strings().storyMediaUnarchive : strings().storyMediaArchive, for: .Normal)
            self.archive.sizeToFit(NSMakeSize(20, 0), NSMakeSize(0, Panel.buttonHeight), thatFit: false)

            self.delete.set(image: TelegramThemeHooks.shared.image(.iconMessageActionPanelDelete).precomposed(theme.colors.text), for: .Normal)
            self.delete.sizeToFit(.zero, NSMakeSize(Panel.buttonHeight, Panel.buttonHeight), thatFit: true)

            self.pin.isEnabled = !selected.isEmpty
            self.archive.isEnabled = !selected.isEmpty
            self.delete.isEnabled = !selected.isEmpty

            needsLayout = true
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layout() {
            super.layout()
            pin.centerY(x: 12)
            archive.center()
            delete.centerY(x: frame.width - delete.frame.width - 12)
        }
    }
    
    private class FolderPanel : View {
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

            self.border = []
            self.backgroundColor = .clear

            self.add.set(font: .medium(.text), for: .Normal)
            self.add.set(color: theme.colors.text, for: .Normal)
            self.add.set(text: strings().storyMediaAlbumButtonAddStories, for: .Normal)
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

    
    public let tableView: TableView
    private var panel: Panel?
    private var folderPanel: FolderPanel?
    
    public required init(frame frameRect: NSRect) {
        self.tableView = .init(frame: frameRect.size.bounds)
        super.init(frame: frameRect)
        addSubview(tableView)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private static let panelHeight: CGFloat = 50

    fileprivate func updateState(_ state: State, arguments: Arguments, animated: Bool) {

        if let selected = state.selected, !selected.isEmpty, state.onStage {

            if let view = self.folderPanel {
                performSubviewPosRemoval(view, pos: NSMakePoint(0, frame.height + view.frame.height), animated: animated)
                self.folderPanel = nil
            }

            let current: Panel
            if let view = self.panel {
                current = view
            } else {
                current = Panel(frame: NSMakeRect(0, frame.height - StoryMediaView.panelHeight, frame.width, StoryMediaView.panelHeight))
                current.autoresizingMask = [.width, .minYMargin]
                self.panel = current
                addSubview(current)

                if animated {
                    current.layer?.animatePosition(from: NSMakePoint(0, frame.height), to: current.frame.origin)
                }
            }
            current.update(selected: selected, isArchive: arguments.isArchive, arguments: arguments)
        } else {

            if let view = self.panel {
                performSubviewPosRemoval(view, pos: NSMakePoint(0, frame.height + view.frame.height), animated: animated)
                self.panel = nil
            }

            if state.access(arguments.context.peerId), state.selectedCollection != State.Collection.all.stableId, let storyState = state.state, !storyState.items.isEmpty, state.onStage {
                let current: FolderPanel
                if let view = self.folderPanel {
                    current = view
                } else {
                    current = FolderPanel(frame: NSMakeRect(0, frame.height - StoryMediaView.panelHeight, frame.width, StoryMediaView.panelHeight))
                    current.autoresizingMask = [.width, .minYMargin]
                    self.folderPanel = current
                    addSubview(current)

                    if animated {
                        current.layer?.animatePosition(from: NSMakePoint(0, frame.height), to: current.frame.origin)
                    }
                }
                current.update(collection: state.collection, arguments: arguments)
            } else if let view = self.folderPanel {
                performSubviewPosRemoval(view, pos: NSMakePoint(0, frame.height + view.frame.height), animated: animated)
                self.folderPanel = nil
            }
        }
        tableView.contentInsets = .init(top: tableView.contentInsets.top, left: 0, bottom: self.panel != nil || folderPanel != nil ? StoryMediaView.panelHeight + 10 : 0, right: 0)
    }

    public override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }

    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        if let panel = self.panel {
            transition.updateFrame(view: panel, frame: NSMakeRect(0, size.height - StoryMediaView.panelHeight, size.width, StoryMediaView.panelHeight))
        }
        if let panel = self.folderPanel {
            transition.updateFrame(view: panel, frame: NSMakeRect(0, size.height - StoryMediaView.panelHeight, size.width, StoryMediaView.panelHeight))
        }
        transition.updateFrame(view: tableView, frame: size.bounds)
    }
}

private struct StoryReferenceEntry : Comparable, Identifiable {
    var index: Int
    var story: EngineStoryItem
    
    var stableId: AnyHashable {
        return story.id
    }
    static func <(lhs: StoryReferenceEntry, rhs: StoryReferenceEntry) -> Bool {
        return lhs.index < rhs.index
    }
}


public final class StoryMediaController<Context: AccountContextProtocol> : TelegramGenericViewController<StoryMediaView, Context> {

    public override var defaultBarTitle: String {
        return localizedString("Telegram.StoryMediaController")
    }
    
    private let actionsDisposable = DisposableSet()
    private let deleteStoriesDisposable = MetaDisposable()
    private var deleteStoriesOperationId: UUID?
    private var acceptsStoryDeletion = true
    private let pinStoriesDisposable = MetaDisposable()
    private var pinStoriesOperationId: UUID?
    private var acceptsStoryPinning = true
    private let profileStoriesDisposable = MetaDisposable()
    private var profileStoriesOperationId: UUID?
    private var acceptsStoryProfileChanges = true
    private let collectionMutationDisposable = MetaDisposable()
    private var collectionMutationOperationId: UUID?
    private var acceptsCollectionMutation = true
    private var collectionMutationGeneration = UUID()
    private let collectionsDisposable = DisposableDict<Int64>()
    private var collectionsContexts:[Int64: PeerStoryListContext] = [:]

    private let peerId: EnginePeer.Id
    private let standalone: Bool
    private let isArchived: Bool
    private var statePromise: ValuePromise<State> = ValuePromise(ignoreRepeated: true)
    private var stateValue: Atomic<State> = Atomic(value: State(state: nil, selected: nil, perRowCount: 4))
    private let listContext: StoryListContext
    private let archiveContext: PeerStoryListContext?
    
    public weak var parentController: (any StoryMediaParentController)?
    
    private var peerListContext: PeerStoryListContext? {
        return listContext as? PeerStoryListContext
    }
    
    public var currentContext: StoryListContext {
        let folderId = self.stateValue.with { $0.selectedCollection }
        if folderId == State.Collection.all.stableId {
            return self.listContext
        } else {
            return collectionsContexts[folderId] ?? self.listContext
        }
    }

    
    public var parentToggleSelection: (()->Void)?

    private func updateState(_ f:(State) -> State) {
        statePromise.set(stateValue.modify (f))
    }

    
    private var editButton:ImageButton? = nil
    private var doneButton:TextButton? = nil

    public override func requestUpdateRightBar() {
        editButton?.style = navigationButtonStyle
        editButton?.set(image: theme.icons.chatActions, for: .Normal)
        editButton?.set(image: theme.icons.chatActionsActive, for: .Highlight)

        
        editButton?.setFrameSize(70, 50)
        editButton?.center()
        doneButton?.set(color: theme.colors.accent, for: .Normal)
        doneButton?.style = navigationButtonStyle
    }
    
    private func addCollection(_ story: PeerStoryListContext.State.Item?) {
        guard self.acceptsCollectionMutation, self.collectionMutationOperationId == nil else { return }
        let generation = self.collectionMutationGeneration
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
                inputPlaceholder: strings().storyMediaAlbumNewPlaceholder,
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
            title: strings().storyMediaAlbumNewTitle,
            info: strings().storyMediaAlbumNewInfo,
            description: nil,
            ok: strings().storyMediaAlbumNewOk,
            options: [],
            mode: .confirm(text: strings().modalCancel, isThird: false),
            footer: footer
        )

        if let window = self.window {
            showModalAlert(for: window, data: data, completion: { [weak self] result in
                guard let self, self.collectionMutationGeneration == generation else { return }
                self.createCollection(title: text, story: story)
            })
        }
    }

    private func createCollection(title: String, story: PeerStoryListContext.State.Item?) {
        guard self.acceptsCollectionMutation, self.collectionMutationOperationId == nil,
              let peerListContext = self.peerListContext, let window = self.window else { return }
        if let story, story.id.peerId != self.peerId || story.id.id != story.storyItem.id {
            alert(for: window, info: strings().unknownError)
            return
        }
        guard !title.isEmpty else { return }
        let operationId = UUID()
        self.collectionMutationOperationId = operationId
        let requestDisposable = MetaDisposable()
        self.collectionMutationDisposable.set(requestDisposable)
        let signal = Signal<Int64?, NoError> { subscriber in
            return peerListContext.addFolder(title: title, items: story.map { [$0.storyItem] } ?? [], completion: { id in
                subscriber.putNext(id)
                subscriber.putCompletion()
            })
        }
        |> deliverOnMainQueue
        |> afterDisposed { [weak self] in
            if self?.collectionMutationOperationId == operationId {
                self?.collectionMutationOperationId = nil
            }
        }
        requestDisposable.set(showModalProgress(signal: signal, for: window).start(next: { [weak self] id in
            guard let self, self.acceptsCollectionMutation, self.collectionMutationOperationId == operationId else { return }
            if let id {
                self.updateState { current in
                    var current = current
                    current.selectedCollection = id
                    return current
                }
            } else {
                alert(for: window, info: strings().unknownError)
            }
        }))
    }

    private func updateCollection(id: Int64, title: String?) {
        guard self.acceptsCollectionMutation, self.collectionMutationOperationId == nil,
              let peerListContext = self.peerListContext, let window = self.window else { return }
        let operationId = UUID()
        self.collectionMutationOperationId = operationId
        let requestDisposable = MetaDisposable()
        self.collectionMutationDisposable.set(requestDisposable)
        let signal = Signal<Bool, NoError> { subscriber in
            let completion: (Bool) -> Void = { success in
                subscriber.putNext(success)
                subscriber.putCompletion()
            }
            if let title {
                return peerListContext.renameFolder(id: id, title: title, completion: completion)
            } else {
                return peerListContext.removeFolder(id: id, completion: completion)
            }
        }
        |> deliverOnMainQueue
        |> afterDisposed { [weak self] in
            if self?.collectionMutationOperationId == operationId {
                self?.collectionMutationOperationId = nil
            }
        }
        requestDisposable.set(showModalProgress(signal: signal, for: window).start(next: { [weak self] success in
            guard let self, self.acceptsCollectionMutation, self.collectionMutationOperationId == operationId else { return }
            if success {
                if title != nil {
                    showModalText(for: window, text: strings().storyMediaAlbumUpdateSuccess)
                }
            } else {
                alert(for: window, info: strings().unknownError)
            }
        }))
    }

    private func updateCollectionStories(id: Int64, added: [EngineStoryItem], removed: [Int32], successText: String?) {
        guard self.acceptsCollectionMutation, self.collectionMutationOperationId == nil,
              let folderContext = self.collectionsContexts[id], let window = self.window,
              !added.isEmpty || !removed.isEmpty else { return }
        let operationId = UUID()
        self.collectionMutationOperationId = operationId
        let requestDisposable = MetaDisposable()
        self.collectionMutationDisposable.set(requestDisposable)
        let signal = Signal<Bool, NoError> { subscriber in
            return folderContext.updateFolderStories(id: id, added: added, removed: removed, completion: { success in
                subscriber.putNext(success)
                subscriber.putCompletion()
            })
        }
        |> deliverOnMainQueue
        |> afterDisposed { [weak self] in
            if self?.collectionMutationOperationId == operationId {
                self?.collectionMutationOperationId = nil
            }
        }
        requestDisposable.set(showModalProgress(signal: signal, for: window).start(next: { [weak self] success in
            guard let self, self.acceptsCollectionMutation, self.collectionMutationOperationId == operationId else { return }
            if success {
                if let successText { showModalText(for: window, text: successText) }
            } else {
                alert(for: window, info: strings().unknownError)
            }
        }))
    }

    private func reorderCollections(from: Int64, to: Int64) {
        guard self.acceptsCollectionMutation, self.collectionMutationOperationId == nil,
              let peerListContext = self.peerListContext, let window = self.window else { return }
        let state = self.stateValue.with { $0 }
        guard state.access(self.context.peerId), from != to else { return }
        var ids = state.collections.compactMap { collection -> Int64? in
            if case let .collection(value) = collection { return value.id }
            return nil
        }
        guard let source = ids.firstIndex(of: from), let target = ids.firstIndex(of: to) else { return }
        ids.move(at: source, to: target)
        let operationId = UUID()
        self.collectionMutationOperationId = operationId
        let requestDisposable = MetaDisposable()
        self.collectionMutationDisposable.set(requestDisposable)
        let signal = Signal<Bool, NoError> { subscriber in
            return peerListContext.reorderFolders(ids: ids, completion: { success in
                subscriber.putNext(success)
                subscriber.putCompletion()
            })
        }
        |> deliverOnMainQueue
        |> afterDisposed { [weak self] in
            if self?.collectionMutationOperationId == operationId {
                self?.collectionMutationOperationId = nil
            }
        }
        requestDisposable.set(showModalProgress(signal: signal, for: window).start(next: { [weak self] success in
            guard let self, self.acceptsCollectionMutation, self.collectionMutationOperationId == operationId else { return }
            if !success { alert(for: window, info: strings().unknownError) }
        }))
    }

    public override func getRightBarViewOnce() -> BarView {
        let back = BarView(70, controller: self) //MajorBackNavigationBar(self, account: account, excludePeerId: peerId)
        
        let editButton = ImageButton()
        editButton.setAccessibilityLabel(strings().voiceOverCommonMore)
       // editButton.disableActions()
        back.addSubview(editButton)
        
        self.editButton = editButton
//
        let doneButton = TextButton()
      //  doneButton.disableActions()
        doneButton.set(font: .medium(.text), for: .Normal)
        doneButton.set(text: strings().navigationDone, for: .Normal)
        
        
        _ = doneButton.sizeToFit()
        back.addSubview(doneButton)
        doneButton.center()
        
        self.doneButton = doneButton

        doneButton.set(handler: { [weak self] _ in
            self?.toggleSelection()
        }, for: .Click)
        
        doneButton.isHidden = true
        
        _ = self.context
        let isArchived = self.isArchived
        _ = self.stateValue
        
        
        editButton.contextMenu = { [weak self] in
            
            let menu = ContextMenu()
            
                       
            if !isArchived {
                menu.addItem(ContextMenuItem(strings().storyMediaContextArchive, handler: {
                    self?.openArchive()
                }, itemImage: MenuAnimation.menu_archive.value))
            }
            let selecting = self?.stateValue.with { $0.selected != nil } == true
            let hasItems = self?.stateValue.with { $0.state?.items.count } != 0
            if hasItems {
                menu.addItem(ContextMenuItem(selecting ? strings().storyMediaDone : strings().storyMediaSelect, handler: {
                    self?.toggleSelection()
                }, itemImage: MenuAnimation.menu_select_multiple.value))
            }

            return menu
        }
        requestUpdateRightBar()
        return back
    }

    public override func menuItems() -> [ContextMenuItem] {
        let state = stateValue.with { $0 }
        
        var items: [ContextMenuItem] = []
        
        let foldersLimit = context.appConfiguration.getGeneralValue("stories_albums_limit", orElse: 16)
        
        items.append(ContextMenuItem(strings().chatContextEdit1, handler: { [weak self] in
            self?.parentController?.changeState()
        }, itemImage: MenuAnimation.menu_edit.value))
        
        if state.access(context.peerId), !self.isArchived, foldersLimit > state.folderCount {
            items.append(ContextSeparatorItem())
            items.append(ContextMenuItem(
                strings().storyMediaAlbumContextMenuAddFolder,
                handler: { [weak self] in
                    self?.addCollection(nil)
                },
                itemImage: MenuAnimation.menu_add.value
            ))
        }

                
        return items
    }
    
    public func toggleSelection() {
        
        let button = self.rightBarView as? TextButtonBarView
        
        
        updateState { current in
            var current = current
            if current.selected == nil {
                current.selected = []
            } else {
                current.selected = nil
            }
            return current
        }
        
        button?.set(text: stateValue.with { $0.selected != nil } ? strings().storyMediaDone : strings().storyMediaSelect, for: .Normal)
    }
    
    private func openArchive() {
        if let archiveContext = self.archiveContext {
            self.navigationController?.push(StoryMediaController(context: context, peerId: peerId, listContext: archiveContext, standalone: self.standalone, isArchived: true).analytics(.storiesArchive))
        }
    }
    
    public static func push(context: Context, peerId: PeerId, listContext: PeerStoryListContext, standalone: Bool = false, isArchived: Bool = false) {
        if let controller = context.bindings.rootNavigation().controller as? StoryMediaController {
            if controller.isArchived == isArchived && controller.standalone == standalone {
                return
            }
        }
        context.bindings.rootNavigation().push(StoryMediaController(context: context, peerId: peerId, listContext: listContext, standalone: standalone, isArchived: isArchived))
    }
    
    public init(context: Context, peerId: EnginePeer.Id, listContext: StoryListContext, standalone: Bool = false, isArchived: Bool = false) {
        self.peerId = peerId
        self.isArchived = isArchived
        self.standalone = standalone
        self.listContext = listContext
        if !isArchived {
            self.archiveContext = .init(account: context.account, peerId: peerId, isArchived: true, folderId: nil)
        } else {
            self.archiveContext = nil
        }
        super.init(context)
        self.bar = standalone ? .init(height: 50) : .init(height: 0)
        if isArchived {
            self.analyticsScreen = standalone ? AnalyticsScreen.storiesArchive : AnalyticsScreen.peerInfoMediaArchivedStories
        } else {
            self.analyticsScreen = .peerInfoMediaStories
        }
    }
    
    
    public override func viewDidResized(_ size: NSSize) {
        super.viewDidResized(size)
        
        updateState { current in
            var current = current
            current.perRowCount = self.perRowCount
            return current
        }
    }
    
    public func selectAlbum(_ album: Int32) {
        updateState { current in
            var current = current
            current.selectedCollection = Int64(album)
            return current
        }
    }
    
    public override var removeAfterDisapper: Bool {
        return false
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        genericView.tableView.verticalScrollElasticity = .none

        
        
        
//        genericView.tableView.set(stickClass: CollectionRowItem.self, handler: { _ in
//            
//        })
        
        genericView.willMove = { [weak self] window in
            self?.updateState { current in
                var current = current
                current.onStage = window != nil
                return current
            }
        }
        
        let context = self.context
        let peerId = self.peerId
        let initialSize = self.atomicSize
        let isArchived = self.isArchived
        let standalone = self.standalone
        
        genericView.tableView.getBackgroundColor = {
            return standalone ? theme.colors.background : theme.colors.listBackground
        }
        
        genericView.tableView.setScrollHandler({ [weak self] _ in
            
            guard let self else {
                return
            }
            let state = self.stateValue.with { $0 }
            if state.selectedCollection == State.Collection.all.stableId {
                listContext.loadMore(completion: {
                    
                })
            } else {
                self.collectionsContexts[state.selectedCollection]?.loadMore(completion: {
                    
                })
            }
            
        })
        let maxPinLimit = context.appConfiguration.getGeneralValue("stories_pinned_to_top_count_max", orElse: 3)
        
        
        let renameCollection:(State.Collection)->Void = { [weak self] collection in
        
            guard let self else {
                return
            }
            
            switch collection {
            case let .collection(value):
                guard self.acceptsCollectionMutation, self.collectionMutationOperationId == nil else { return }
                let generation = self.collectionMutationGeneration
                var text: String = value.title

                var footer: ModalAlertData.Footer = .init(id: "footer", value: { initialSize, stableId, presentation, updateData in
                    return InputDataRowItem(
                        initialSize,
                        stableId: stableId,
                        mode: .plain,
                        error: nil,
                        viewType: .singleItem,
                        currentText: value.title,
                        placeholder: nil,
                        inputPlaceholder: strings().storyMediaAlbumUpdatePlaceholder,
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
                    title: strings().storyMediaAlbumUpdateTitle,
                    info: strings().storyMediaAlbumUpdateInfo,
                    description: nil,
                    ok: strings().storyMediaAlbumUpdateOk,
                    options: [],
                    mode: .confirm(text: strings().modalCancel, isThird: false),
                    footer: footer
                )

                if let window = self.window {
                    showModalAlert(for: window, data: data, completion: { [weak self, weak window] result in
                        guard let self, window != nil, self.collectionMutationGeneration == generation else {
                            return
                        }
                        self.updateCollection(id: value.id, title: text)
                    })
                }

            default:
                break
            }
        }
        
        let share:(State.Collection)->Void = { [weak self] collection in
            guard let self else {
                return
            }
            switch collection {
            case let .collection(value):
                let peer = self.stateValue.with { $0.peer }
                if let address = peer?._asPeer().addressName, let window = self.window {
                    StoriesHooks.shared.showShareLink(context, context.meUrlPrefix + "\(address)/a/\(value.id)", window)
                }
            default:
                break
            }
        }
        
        
        let addToCollection:(State.Collection, StoryListContextState.Item?)->Void = { [weak self] collection, story in
            guard let self, self.acceptsCollectionMutation, self.collectionMutationOperationId == nil, let window = self.window else { return }
            switch collection {
            case let .collection(value):
                guard self.collectionsContexts[value.id] != nil else { return }
                if let story {
                    guard story.id.peerId == peerId, story.id.id == story.storyItem.id else {
                        alert(for: window, info: strings().unknownError)
                        return
                    }
                    let contains = self.stateValue.with { $0.contains(collectionId: value.id, story: story.storyItem) }
                    self.updateCollectionStories(id: value.id, added: contains ? [] : [story.storyItem], removed: contains ? [story.id.id] : [], successText: contains ? strings().storyMediaAlbumAlertRemoved(value.title) : strings().storyMediaAlbumAlertAdded(value.title))
                } else {
                    let generation = self.collectionMutationGeneration
                    var submitted = false
                    showModal(with: SelectStoryModalController(context: context, folderId: value.id, peerId: peerId, listContext: self.peerListContext, albumContext: self.collectionsContexts[value.id], callback: { [weak self] selected, unselected in
                        guard let self, self.acceptsCollectionMutation, self.collectionMutationGeneration == generation, !submitted else { return }
                        submitted = true
                        self.updateCollectionStories(id: value.id, added: selected, removed: unselected.map(\.id), successText: nil)
                    }), for: window)
                }
            default:
                break
            }
        }

        self.setCenterTitle(isArchived ? strings().storyMediaTitleArchive : peerId == context.peerId ? strings().storyMediaTitleMyStories : "")
        
        let setProfileStories: ([Int32: EngineStoryItem], Set<StoryId>?, Bool) -> Void = { [weak self] stories, selected, single in
            guard let self, self.acceptsStoryProfileChanges, self.profileStoriesOperationId == nil,
                  self.pinStoriesOperationId == nil, self.deleteStoriesOperationId == nil, !stories.isEmpty else { return }
            let operationId = UUID()
            self.profileStoriesOperationId = operationId
            let requestDisposable = MetaDisposable()
            self.profileStoriesDisposable.set(requestDisposable)
            let signal = context.engine.messages.updateStoriesArePinned(peerId: peerId, ids: stories, isPinned: isArchived)
            |> deliverOnMainQueue
            |> afterDisposed { [weak self] in
                if self?.profileStoriesOperationId == operationId { self?.profileStoriesOperationId = nil }
            }
            requestDisposable.set(showModalProgress(signal: signal, for: context.window).start(error: { [weak self] _ in
                guard let self, self.acceptsStoryProfileChanges, self.profileStoriesOperationId == operationId else { return }
                alert(for: context.window, info: strings().unknownError)
            }, completed: { [weak self] in
                guard let self, self.acceptsStoryProfileChanges, self.profileStoriesOperationId == operationId else { return }
                if let selected {
                    self.updateState { current in
                        var current = current
                        if let currentSelection = current.selected {
                            current.selected = currentSelection.subtracting(selected)
                        }
                        return current
                    }
                    guard self.acceptsStoryProfileChanges, self.profileStoriesOperationId == operationId else { return }
                    if self.stateValue.with({ $0.selected?.isEmpty == true }) {
                        self.toggleSelection()
                    }
                }
                guard self.acceptsStoryProfileChanges, self.profileStoriesOperationId == operationId else { return }
                let text: String
                let title: String?
                if isArchived {
                    text = peerId.namespace == Namespaces.Peer.CloudChannel ? strings().storyTooltipSavedToProfileChannel : strings().storyTooltipSavedToProfile
                    title = single ? strings().storyTooltipSavedTitle : nil
                } else {
                    text = peerId.namespace == Namespaces.Peer.CloudChannel ? strings().storyTooltipRemovedFromProfileChannel : strings().storyTooltipRemovedFromProfile
                    title = single ? strings().storyTooltipRemovedTitle : nil
                }
                showModalText(for: context.window, text: text, title: title)
            }))
        }

        let pinStories: ([Int32], String, Set<StoryId>?) -> Void = { [weak self] ids, text, selected in
            guard let self, self.acceptsStoryPinning, self.pinStoriesOperationId == nil, self.profileStoriesOperationId == nil, self.deleteStoriesOperationId == nil else { return }
            guard ids.count <= maxPinLimit else {
                showModalText(for: context.window, text: strings().storyMediaTooltipLimitOther(Int(maxPinLimit)))
                return
            }
            let operationId = UUID()
            self.pinStoriesOperationId = operationId
            let requestDisposable = MetaDisposable()
            self.pinStoriesDisposable.set(requestDisposable)
            let signal = context.engine.messages.updatePinnedToTopStories(peerId: peerId, ids: ids)
            |> deliverOnMainQueue
            |> afterDisposed { [weak self] in
                if self?.pinStoriesOperationId == operationId { self?.pinStoriesOperationId = nil }
            }
            requestDisposable.set(showModalProgress(signal: signal, for: context.window).start(error: { [weak self] _ in
                guard let self, self.acceptsStoryPinning, self.pinStoriesOperationId == operationId else { return }
                alert(for: context.window, info: strings().unknownError)
            }, completed: { [weak self] in
                guard let self, self.acceptsStoryPinning, self.pinStoriesOperationId == operationId else { return }
                self.updateState { current in
                    var current = current
                    for collectionId in current.collectionStates.keys {
                        current.collectionStates[collectionId]?.pinnedIds = ids
                    }
                    if let selected, let currentSelection = current.selected {
                        current.selected = currentSelection.subtracting(selected)
                    }
                    return current
                }
                guard self.acceptsStoryPinning, self.pinStoriesOperationId == operationId else { return }
                if selected != nil, self.stateValue.with({ $0.selected?.isEmpty == true }) {
                    self.toggleSelection()
                }
                guard self.acceptsStoryPinning, self.pinStoriesOperationId == operationId else { return }
                showModalText(for: context.window, text: text)
            }))
        }

        let deleteStories: ([Int32], (() -> Void)?) -> Void = { [weak self] ids, completion in
            guard let self, self.acceptsStoryDeletion, self.deleteStoriesOperationId == nil, self.profileStoriesOperationId == nil, self.pinStoriesOperationId == nil, !ids.isEmpty else { return }
            let operationId = UUID()
            self.deleteStoriesOperationId = operationId
            let requestDisposable = MetaDisposable()
            self.deleteStoriesDisposable.set(requestDisposable)
            let signal = context.engine.messages.deleteStories(peerId: peerId, ids: ids)
            |> deliverOnMainQueue
            |> afterDisposed { [weak self] in
                if self?.deleteStoriesOperationId == operationId { self?.deleteStoriesOperationId = nil }
            }
            requestDisposable.set(showModalProgress(signal: signal, for: context.window).start(error: { [weak self] _ in
                guard let self, self.acceptsStoryDeletion, self.deleteStoriesOperationId == operationId else { return }
                alert(for: context.window, info: strings().unknownError)
            }, completed: { [weak self] in
                guard let self, self.acceptsStoryDeletion, self.deleteStoriesOperationId == operationId else { return }
                _ = showModalSuccess(for: context.window, icon: theme.icons.successModalProgress, delay: 3).startStandalone()
                completion?()
            }))
        }

        let arguments = Arguments(context: context, standalone: standalone, isArchive: isArchived, isMy: peerId == context.peerId || isArchived, openStory: { [weak self] initialId in
            if let self {
                let list = self.currentContext
                let origin = Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: self.analyticsContext ?? Analytics.shared.unresolvedContext())
                StoriesHooks.shared.showListStoryObserved(context, list, peerId, initialId, analyticsContext: origin)
            }
        }, toggleSelected: { [weak self] storyId in
            
            let value = self?.stateValue.with { $0.selected != nil }
            if value == false {
                self?.parentToggleSelection?()
            }
            
            self?.updateState { current in
                var current = current
                if var selected = current.selected {
                    if selected.contains(storyId) {
                        selected.remove(storyId)
                    } else {
                        selected.insert(storyId)
                    }
                    current.selected = selected
                } else {
                    current.selected = Set([storyId])
                }
                return current
            }
        }, showArchive: { [weak self] in
            self?.openArchive()
        }, archiveSelected: { [weak self] in
            guard let self, self.acceptsStoryProfileChanges, self.profileStoriesOperationId == nil,
                  self.pinStoriesOperationId == nil, self.deleteStoriesOperationId == nil else { return }
            let state = self.stateValue.with { $0 }
            guard let selected = state.selected, !selected.isEmpty else { return }
            let list = (state.state?.items ?? []) + (state.mainState?.items ?? [])
            var stories: [Int32: EngineStoryItem] = [:]
            for selectedId in selected {
                guard selectedId.peerId == peerId, let story = list.first(where: { $0.id == selectedId }) else {
                    alert(for: context.window, info: strings().unknownError)
                    return
                }
                stories[story.storyItem.id] = story.storyItem
            }
            setProfileStories(stories, selected, false)
        }, toggleStory: { story in
            setProfileStories([story.id: story], nil, true)
        }, deleteStory: { story in
            verifyAlert_button(for: context.window, information: strings().storyConfirmDelete, ok: strings().modalDelete, successHandler: { _ in
                deleteStories([story.id], nil)
            })
        }, deleteSelected: { [weak self] in
            let ids: [Int32] = self?.stateValue.with { state in state.selected?.map { $0.id } } ?? []
            guard !ids.isEmpty else { return }
            verifyAlert_button(for: context.window, information: strings().storyMediaDeleteConfirmOther(ids.count), ok: strings().modalDelete, successHandler: { _ in
                deleteStories(ids, { [weak self] in
                    guard let self else { return }
                    self.updateState { current in
                        var current = current
                        if let selected = current.selected {
                            current.selected = Set(selected.filter { !ids.contains($0.id) })
                        }
                        return current
                    }
                    if self.stateValue.with({ $0.selected?.isEmpty == true }) {
                        self.toggleSelection()
                    }
                })
            })

        }, togglePinned: { [weak self] story in
            guard let self, let state = self.stateValue.with({ $0.mainState }) else { return }
            var pinned = state.pinnedIds
            let text: String
            if let index = pinned.firstIndex(of: story.id) {
                pinned.remove(at: index)
                text = strings().storyMediaTooltipUnpinnedOther(1)
            } else {
                pinned.append(story.id)
                text = strings().storyMediaTooltipPinnedOther(1)
            }
            pinStories(pinned, text, nil)
        }, togglePinSelected: { [weak self] in
            guard let self else { return }
            let state = self.stateValue.with { $0 }
            guard let list = state.mainState, let selected = state.selected, !selected.isEmpty,
                  selected.allSatisfy({ $0.peerId == peerId }) else { return }
            var pinned = list.pinnedIds
            for id in selected.map({ $0.id }).sorted() where !pinned.contains(id) {
                pinned.append(id)
            }
            pinStories(pinned, strings().storyMediaTooltipPinnedOther(selected.count), selected)
        }, collection: { [weak self] collection, story in
            if collection == .add {
                self?.addCollection(story)
            } else {
                self?.updateState { current in
                    var current = current
                    current.selectedCollection = collection.stableId
                    return current
                }
            }
            
            self?.parentController?.currentMainTableView?(self?.parentController?.genericView.mainTable, true, true)
        }, addToCollection: { collection, story in
    //        let state = stateValue.with { $0 }
    //        let collection = state.collections.first(where: { $0.stableId == state.selectedCollection }) ?? .all
            addToCollection(collection, story)
        }, collectionContextMenu: { [weak self] collection in
            
            guard let self else {
                return []
            }
            
            switch collection {
            case .add:
               return []
            case .all:
                return []
            case let .collection(value):
                var items: [ContextMenuItem] = []
                
                let state = self.stateValue.with { $0 }
                let access = state.access(context.peerId)

                if access {
                    items.append(ContextMenuItem(
                        strings().storyMediaAlbumContextMenuAddStories,
                        handler: {
                            addToCollection(collection, nil)
                        },
                        itemImage: MenuAnimation.menu_add.value
                    ))
                    if state.peer?.addressName != nil {
                        items.append(ContextMenuItem(
                            strings().modalShare,
                            handler: {
                                share(collection)
                            },
                            itemImage: MenuAnimation.menu_share.value
                        ))
                    }

                    items.append(ContextMenuItem(
                        strings().storyMediaAlbumContextMenuRename,
                        handler: {
                            renameCollection(collection)
                        },
                        itemImage: MenuAnimation.menu_edit.value
                    ))

                    items.append(ContextSeparatorItem())

                    items.append(ContextMenuItem(
                        strings().storyMediaAlbumContextMenuDelete,
                        handler: { [weak self] in
                            if let self, self.acceptsCollectionMutation, self.collectionMutationOperationId == nil, let window = self.window {
                                let generation = self.collectionMutationGeneration
                                verifyAlert(
                                    for: window,
                                    information: strings().storyMediaAlbumContextMenuDeleteConfirm(value.title),
                                    successHandler: { [weak self] _ in
                                        guard let self, self.collectionMutationGeneration == generation else { return }
                                        self.updateCollection(id: value.id, title: nil)
                                    }
                                )
                            }
                        },
                        itemMode: .destruct,
                        itemImage: MenuAnimation.menu_delete.value
                    ))
                }
               
                return items
            }
        }, resort: { [weak self] from, to in
            self?.reorderCollections(from: from, to: to)
        }, state: { [weak self] in
            let state = self?.stateValue.with { $0 }
            return state
        })
        
        let foldersLimit = context.appConfiguration.getGeneralValue("stories_albums_limit", orElse: 16)

        let stateSignal = listContext.state |> deliverOnMainQueue
        let peer = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        
        
        actionsDisposable.add(combineLatest(queue: .mainQueue(), stateSignal, peer).start(next: { [weak self] state, peer in
            
            guard let self else {
                return
            }
            
            let prevCollections = self.stateValue.with { $0.collections }
            
            self.updateState { current in
                var current = current
                current.collectionStates[State.Collection.all.stableId] = state
                current.peer = peer
                if !isArchived {
                    let validFolderIds = Set(state.availableFolders.map(\.id))
                    current.collectionStates = current.collectionStates.filter { key, _ in
                        key == State.Collection.all.stableId || validFolderIds.contains(key)
                    }
                    current.collections = []
                    if !state.availableFolders.isEmpty {
                        current.collections = [.all] + state.availableFolders.map { .collection(value: $0) }
                        if current.access(context.peerId), current.folderCount < foldersLimit  {
                            current.collections.append(.add)
                        }
                    }
                    if !current.collections.contains(where: { $0.stableId == current.selectedCollection }) {
                        current.selectedCollection = State.Collection.all.stableId
                    }
                }
                return current
            }
            let currentCollections = self.stateValue.with { $0.collections }

            if prevCollections != currentCollections {
                let previewsSignal = PeerStoryListContext.folderPreviews(peerId: peerId, account: context.account) |> deliverOnPrepareQueue
                self.actionsDisposable.add(previewsSignal.startStrict(next: { [weak self] value in
                    self?.updateState { current in
                        var current = current
                        current.previews = .init(peer: value.peer, folder: value.1.map {
                            .init(folder: $0.folder, item: $0.item)
                        })
                        return current
                    }
                }))
            }
            
            if state.totalCount > 0 {
                self.setCenterStatus(strings().chatListArchiveStoryCountOther(state.totalCount).lowercased())
            } else {
                self.setCenterStatus(nil)
            }
            
            var validKeys:Set<Int64> = Set()
            
            for collection in state.availableFolders {
                if self.collectionsContexts[collection.id] == nil {
                    let value = PeerStoryListContext(account: context.account, peerId: peerId, isArchived: self.isArchived, folderId: collection.id)
                    
                    self.collectionsContexts[collection.id] = value
                    self.collectionsDisposable.set(value.state.start(next: { [weak self] state in
                        self?.updateState { current in
                            var current = current
                            current.collectionStates[collection.id] = state
                            return current
                        }
                    }), forKey: collection.id)
                }
                validKeys.insert(collection.id)
            }
            
            var removeKeys:Set<Int64> = Set()
            for (key, _) in self.collectionsContexts {
                if !validKeys.contains(key) {
                    removeKeys.insert(key)
                }
            }
            for key in removeKeys {
                self.collectionsContexts.removeValue(forKey: key)
                self.collectionsDisposable.set(nil, forKey: key)
            }
            
        }))


        let signal: Signal<([Entry], State), NoError> = statePromise.get() |> deliverOnPrepareQueue |> map { state in
            return (entries(state, arguments: arguments), state)
        }

        let previous: Atomic<[AppearanceWrapperEntry<Entry>]> = Atomic(value: [])
        let first = Atomic(value: true)

        let transition: Signal<(TableUpdateTransition, State), NoError> = combineLatest(signal, appearanceSignal) |> map { values, appearance -> (TableUpdateTransition, State) in
            let entries = values.0.map { AppearanceWrapperEntry(entry: $0, appearance: appearance)}
            return (prepareTransition(left: previous.swap(entries), right: entries, animated: !first.swap(false), initialSize: initialSize.with { $0 }, arguments: arguments), values.1)
        } |> deliverOnMainQueue

        actionsDisposable.add(transition.start(next: { [weak self, weak arguments] (transition, state) in
            guard let arguments = arguments else {
                return
            }
            self?.genericView.tableView.merge(with: transition)
            self?.readyOnce()
            
            self?.genericView.updateState(state, arguments: arguments, animated: transition.animated)
            self?.doneButton?.isHidden = state.selected == nil
            self?.editButton?.isHidden = state.selected != nil
            
        }))
        
    }
    
    public override func escapeKeyAction() -> KeyHandlerResult {
        let selecting = self.stateValue.with({ $0.selected != nil })
        if selecting {
            self.toggleSelection()
            return .invoked
        } else {
            return super.escapeKeyAction()
        }
    }
    
    public override var enableBack: Bool {
        return true
    }
    
    private var perRowCount: Int {
        var rowCount:Int = 6
        var perWidth: CGFloat = 0
        let blockWidth = atomicSize.with ({ $0.width })//min(600, atomicSize.with { $0.width }) - (standalone ? 60 : 0)
        while true {
            let maximum = blockWidth - CGFloat(rowCount * 2)
            perWidth = maximum / CGFloat(rowCount)
            if perWidth >= 100 {
                break
            } else {
                rowCount -= 1
            }
        }
        return rowCount
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        self.acceptsStoryPinning = false
        self.pinStoriesOperationId = nil
        self.acceptsStoryProfileChanges = false
        self.profileStoriesOperationId = nil
        self.acceptsStoryDeletion = false
        self.deleteStoriesOperationId = nil
        self.acceptsCollectionMutation = false
        self.collectionMutationGeneration = UUID()
        self.collectionMutationOperationId = nil
        self.collectionMutationDisposable.set(nil)
        self.pinStoriesDisposable.set(nil)
        self.profileStoriesDisposable.set(nil)
        self.deleteStoriesDisposable.set(nil)
        super.viewWillDisappear(animated)
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        self.acceptsStoryDeletion = true
        self.acceptsStoryPinning = true
        self.acceptsStoryProfileChanges = true
        self.acceptsCollectionMutation = true
    }
    
    deinit {
        collectionMutationDisposable.dispose()
        collectionsDisposable.dispose()
        deleteStoriesDisposable.dispose()
        pinStoriesDisposable.dispose()
        profileStoriesDisposable.dispose()
        actionsDisposable.dispose()
    }
}
