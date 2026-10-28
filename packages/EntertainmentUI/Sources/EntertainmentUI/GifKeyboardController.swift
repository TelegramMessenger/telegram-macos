import Foundation
import TGUIKit
import ColorPalette
import ComponentsUI
import SwiftSignalKit
import Postbox
import TelegramCore
import Cocoa
import FoundationUtils
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import MessageTextUtils
import LocalAnimations
import GeneralRows
import InputDataUI
import InlineMediaGrid
import ChatModeTypes



public struct GIFKeyboardConfiguration : Equatable {
    public static var defaultValue: GIFKeyboardConfiguration {
        return GIFKeyboardConfiguration(emojis: [])
    }
    
    public let emojis: [String]
    
    fileprivate init(emojis: [String]) {
        self.emojis = emojis.map { $0.fixed }
    }
    
    public static func with(appConfiguration: AppConfiguration) -> GIFKeyboardConfiguration {
        if let data = appConfiguration.data, let value = data["gif_search_emojies"] as? [String] {
            return GIFKeyboardConfiguration(emojis: value.map { $0.fixed })
        } else {
            return .defaultValue
        }
    }
    
}

private struct State : Equatable {

    
    struct Entry : Equatable {
        let collection: ChatContextResultCollection?
        let row: ChatContextResult
        
    }
    
    enum TabEntryId : Equatable {
        case recent
        case trending
        case recommended(TelegramMediaFile)
        
        var stableId: AnyHashable {
            switch self {
            case .recent:
                return 0
            case .trending:
                return 1
            case let .recommended(file):
                return file.fileId.id
            }
        }
        
        var search: String? {
            switch self {
            case .recent:
                return nil
            case .trending:
                return ""
            case let .recommended(file):
                return file.stickerText
            }
        }
    }
    
    struct Search : Equatable {
        static let stableId: AnyHashable = AnyHashable(-1)
        var request: String
        var nextOffset: String?
        var items: [Entry]
        var isLoading: Bool = true
    }
    
    var tabs:[TabEntryId] = []
    
    var search: Search?
     
    var tab: TabEntryId = .recent
    
    struct Entries : Equatable {
        var items: [Entry]
        var nextOffset: String?
    }
    
    var entries:[AnyHashable : Entries] = [:]
}

private final class Arguments {
    let context: any AccountContextProtocol
    let selectTab:(State.TabEntryId)->Void
    let sendInlineResult:(ChatContextResultCollection,ChatContextResult, NSView) -> Void
    let sendAppFile:(TelegramMediaFile, NSView, Bool, Bool) -> Void
    let showPreviewSender:(TelegramMediaFile) -> Void

    init(context: any AccountContextProtocol, selectTab:@escaping(State.TabEntryId)->Void, sendInlineResult:@escaping(ChatContextResultCollection,ChatContextResult, NSView)->Void, sendAppFile:@escaping(TelegramMediaFile, NSView, Bool, Bool) -> Void, showPreviewSender:@escaping(TelegramMediaFile) -> Void) {
        self.context = context
        self.selectTab = selectTab
        self.sendInlineResult = sendInlineResult
        self.sendAppFile = sendAppFile
        self.showPreviewSender = showPreviewSender
    }
}

private func _id_gif(_ entry: InputMediaContextRow) -> InputDataIdentifier {
    return .init("_id_gif_\(entry.hashValue)")
}
private func _id_tab(_ stableId: AnyHashable) -> InputDataIdentifier {
    return .init("_id_tab_\(stableId)")
}


private func packEntries(_ state: State, arguments: Arguments, presentation: TelegramPresentationTheme) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var index: Int32 = 0
    let sectionId:Int32 = 0
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("left"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return GeneralRowItem(initialSize, height: 6, stableId: stableId, backgroundColor: .clear)
    }))
    index += 1
    
    
    for tab in state.tabs {
        
        struct Tuple: Equatable {
            let tab: State.TabEntryId
            let selected: Bool
        }
        let tuple = Tuple(tab: tab, selected: tab == state.tab)
        
        let source: GifKeyboardTabRowItem.Source
        let title: String?
        switch tab {
        case .recent:
            source = .icon(tuple.selected ? theme.icons.gif_recent_active : theme.icons.gif_recent)
            title = strings().emojiRecent
        case .trending:
            source = .icon(tuple.selected ? theme.icons.gif_trending_active : theme.icons.gif_trending)
            title = strings().gifsPaneTrending
        case let .recommended(file):
            source = .file(file)
            title = nil
        }
        
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_tab(tuple.tab.stableId), equatable: InputDataEquatable(tuple), comparable: nil, item: { initialSize, stableId in
            return GifKeyboardTabRowItem(initialSize, stableId: stableId, selected: tuple.selected, context: arguments.context, source: source, title: title, select: {
                arguments.selectTab(tab)
            }, theme: presentation)
        }))
    }
    
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("right"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return GeneralRowItem(initialSize, height: 6, stableId: stableId, backgroundColor: .clear)
    }))
    index += 1
    
    return entries
}

private func entries(_ state: State, arguments: Arguments, mediaArguments: EntertainmentMediaArguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    let sectionId:Int32 = 0
    var index: Int32 = 0
        
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("search"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return GeneralRowItem(initialSize, height: 46, stableId: stableId, backgroundColor: .clear)
    }))
    index += 1
    
    let value: [State.Entry]?
    if let search = state.search {
        value = search.items
    } else if let current = state.entries[state.tab.stableId] {
        value = current.items
    } else {
        value = nil
    }
    
    if let value = value {
        
        let values = value.map { $0.row }
        let collections = value.map { $0.collection }
        
        let items = makeMediaEnties(values, peer: PeerReference(arguments.context.myPeer!)!, isSavedGifs: true, initialSize: NSMakeSize(350, 100))
        
        for (i, entry) in items.enumerated() {
            struct Tuple : Equatable {
                let row: InputMediaContextRow
                let collection: ChatContextResultCollection?
            }
            let tuple: Tuple = Tuple(row: entry, collection: collections[i])
            
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_gif(entry), equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
                return EntertainmentUIHooks.shared.makeContextMediaRowItem(initialSize, tuple.row, 0, arguments.context, mediaArguments, tuple.collection, stableId)
            }))
            index += 1
            
            if i != items.count - 1 {
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("_\(index)"), equatable: nil, comparable: nil, item: { initailSize, stableId in
                    return GeneralRowItem(initailSize, height: 1, stableId: stableId, backgroundColor: .clear)
                }))
            }
        }
    }
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("bottom"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return GeneralRowItem(initialSize, height: 46, stableId: stableId, backgroundColor: .clear)
    }))
    index += 1
    
    return entries
}


public final class GifKeyboardView : View {
    public let tableView = TableView()
    public let packsView = HorizontalTableView(frame: NSZeroRect)
    fileprivate var restrictedView:RestrictionWrappedView?
    private let borderView = View()
    private let tabs = View()
    
    public let searchView = SearchView(frame: .zero)
    private let searchContainer = View()
    private let searchBorder = View()
    private let searchBackdrop = View()
    private let searchStatusView = PanelSearchStatusView(frame: .zero)
    private var searchStatus: PanelSearchPresentation = .hidden

    
    public var presentation: TelegramPresentationTheme?

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
        
        self.packsView.getBackgroundColor = {
            .clear
        }
        
        self.tableView.getBackgroundColor = {
            .clear
        }
        addSubview(self.tableView)

        searchContainer.addSubview(searchBackdrop)
        searchContainer.addSubview(searchView)
        searchContainer.addSubview(searchBorder)
        addSubview(searchContainer)
        
        tabs.addSubview(self.packsView)
        addSubview(self.borderView)
        addSubview(tabs)
        addSubview(searchStatusView)
        
        
        
        self.tableView.addScroll(listener: .init(dispatchWhenVisibleRangeUpdated: false, { [weak self] position in
            self?.updateScrollerSearch()
        }))
        
        tableView.scrollerInsets = .init(left: 0, right: 0, top: 46, bottom: 50)
        
        self.layout()
    }
 
    
    public func updateRestricion(_ peer: Peer?, cachedData: CachedPeerData?, animated: Bool) {
        if let peer = peer, let text = permissionText(from: peer, for: .banSendGifs, cachedData: cachedData) {
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
    
    public override func layout() {
        super.layout()
        self.updateLayout(self.frame.size, transition: .immediate)
    }
    
    private func updateScrollerSearch() {
        self.updateLayout(self.frame.size, transition: .immediate)
    }
    
    public func updateLayout(_ size: NSSize, transition: ContainedViewLayoutTransition) {
        
        let initial: CGFloat = searchState?.state == .Focus ? -46 : 0

        transition.updateFrame(view: tabs, frame: NSMakeRect(0, initial, size.width, 46))
        transition.updateFrame(view: packsView, frame: tabs.focus(NSMakeSize(size.width, 36)))
        transition.updateFrame(view: borderView, frame: NSMakeRect(0, tabs.frame.maxY, size.width, .borderSize))

        
        let searchDest = max(0, min((tableView.firstItem?.frame.minY ?? 0) + (tableView.clipView.destination?.y ?? tableView.documentOffset.y), 46))
                
        transition.updateFrame(view: searchContainer, frame: NSMakeRect(0, min(max(tabs.frame.maxY - searchDest, 0), tabs.frame.maxY), size.width, 46))
        transition.updateFrame(view: searchView, frame: searchContainer.focus(NSMakeSize(size.width - 16, 30)))
        transition.updateFrame(view: searchBorder, frame: NSMakeRect(0, searchContainer.frame.height - .borderSize, size.width, .borderSize))
        
        transition.updateFrame(view: tableView, frame: NSMakeRect(0, tabs.frame.maxY, size.width, size.height))

        transition.updateFrame(view: searchStatusView, frame: NSMakeRect(0, searchContainer.frame.maxY, size.width, max(0, size.height - searchContainer.frame.maxY - 56)))

        if let restrictedView = restrictedView {
            transition.updateFrame(view: restrictedView, frame: size.bounds)
        }

        let alpha: CGFloat = searchState?.state == .Focus && tableView.documentOffset.y > 0 ? 1 : 0
        transition.updateAlpha(view: searchBorder, alpha: alpha)
        transition.updateFrame(view: searchBackdrop, frame: searchContainer.bounds)
        if isGlass {
            transition.updateAlpha(view: searchBackdrop, alpha: alpha)
            let hidden = searchState?.state == .Focus ? 0 : searchDest / 46
            transition.updateAlpha(view: searchContainer, alpha: 1 - hidden)
        } else {
            transition.updateAlpha(view: searchContainer, alpha: 1)
        }
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let border: NSColor = isGlass ? theme.colors.grayIcon.withAlphaComponent(0.1) : theme.colors.border
        self.backgroundColor = isGlass ? .clear : theme.colors.background
        searchStatusView.updateSearchStatus(searchStatus, kind: .gifs, query: searchView.query, theme: presentation ?? (theme as! TelegramPresentationTheme))
        borderView.backgroundColor = border
        tabs.backgroundColor = isGlass ? .clear : theme.colors.background
        searchContainer.backgroundColor = isGlass ? .clear : theme.colors.background
        searchBorder.backgroundColor = border
        searchBackdrop.backgroundColor = theme.colors.background.withAlphaComponent(0.85)
        searchBackdrop.isHidden = !isGlass
        self.searchView.updateLocalizationAndTheme(theme: theme)
        if isGlass {
            let searchBackground = theme.colors.vibrant.mixedWith(NSColor(0x000000), alpha: 0.1)
            self.searchView.searchTheme = SearchTheme(searchBackground, theme.search.searchImage, theme.search.clearImage, theme.search.placeholder, theme.search.textColor, theme.search.placeholderColor)
        } else {
            self.searchView.searchTheme = theme.search
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    private var searchState: SearchState? = nil

    public func updateSearchState(_ searchState: SearchState, animated: Bool) {
        self.searchState = searchState

        let transition: ContainedViewLayoutTransition
        if animated {
            transition = .animated(duration: 0.2, curve: .easeOut)
        } else {
            transition = .immediate
        }
        self.updateLayout(self.frame.size, transition: transition)
    }
    
    func update(sections: TableUpdateTransition, packs: TableUpdateTransition, searchStatus: PanelSearchPresentation) {
        self.searchStatus = searchStatus
        searchStatusView.updateSearchStatus(searchStatus, kind: .gifs, query: searchView.query, theme: presentation ?? theme)
        self.tableView.merge(with: sections)
        self.packsView.merge(with: packs)
    }
}

public final class GifKeyboardController<Context: AccountContextProtocol> : TelegramGenericViewController<GifKeyboardView, Context> {
    public override var defaultBarTitle: String {
        return localizedString("Telegram.GifKeyboardController")
    }
    
    private let disposable = MetaDisposable()
    
    private var interactions: EntertainmentInteractions?
    private weak var chatInteraction: (any ChatInteractionProtocol)?
    
    private var updateState: (((State) -> State) -> Void)? = nil
    
    public var makeSearchCommand:((ESearchCommand)->Void)?
    
    public var mode: EntertainmentViewController.Mode = .common
   
    private let searchValue = ValuePromise<SearchState>(.init(state: .None, request: nil))
    private var searchState: SearchState = .init(state: .None, request: nil) {
        didSet {
            self.searchValue.set(searchState)
        }
    }
    private var presentation: TelegramPresentationTheme?
    
    public init(_ context: Context, presentation: TelegramPresentationTheme? = nil) {
        self.presentation = presentation
        super.init(context)
        bar = .init(height: 0)
    }
    
    deinit {
        disposable.dispose()
    }
    

    
    private func updateSearchState(_ state: SearchState) {
        let changed = self.searchState.request.trimmingCharacters(in: .whitespacesAndNewlines) != state.request.trimmingCharacters(in: .whitespacesAndNewlines)
        self.searchState = state
        if changed && !state.request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.makeSearchCommand?(.loading)
        }
        if self.isLoaded() == true {
            self.genericView.updateSearchState(state, animated: true)
        }
    }
    
    public func update(with interactions:EntertainmentInteractions?, chatInteraction: any ChatInteractionProtocol) {
        self.interactions = interactions
        self.chatInteraction = chatInteraction
        if isLoaded() {
            genericView.updateRestricion(chatInteraction.presentationPeer, cachedData: chatInteraction.presentationCachedData, animated: false)
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let chatInteraction = chatInteraction {
            genericView.updateRestricion(chatInteraction.presentationPeer, cachedData: chatInteraction.presentationCachedData, animated: false)
        }
    }
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let chatInteraction = chatInteraction {
            genericView.updateRestricion(chatInteraction.presentationPeer, cachedData: chatInteraction.presentationCachedData, animated: false)
        }
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: presentation ?? theme)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        
        genericView.presentation = presentation
        
        let emojies = GIFKeyboardConfiguration.with(appConfiguration: context.appConfiguration)
                
       
        
        let context = self.context
        let mode = self.mode
        let actionsDisposable = DisposableSet()
        let disposableDict = DisposableDict<AnyHashable>()
        actionsDisposable.add(disposableDict)
        let initialSize = self.atomicSize

        
        
       
        
        let initialState = State()
        
        let statePromise = ValuePromise<State>(ignoreRepeated: true)
        let stateValue = Atomic(value: initialState)
        let updateState: ((State) -> State) -> Void = { f in
            statePromise.set(stateValue.modify (f))
        }
        
        let updateSearchCommand:()->Void = { [weak self] in
            self?.makeSearchCommand?(.normal)
        }
        var searchRequests = PanelSearchRequestTracker<AnyHashable>()
        let makeSearch:(State.TabEntryId?, String, String)->Void = { tab, query, nextOffset in
            let stableId: AnyHashable = tab?.stableId ?? State.Search.stableId
            if tab != nil && nextOffset.isEmpty && stateValue.with({ $0.entries[stableId] == nil }) {
                searchRequests.clearCompleted(stableId)
            }
            guard let request = searchRequests.begin(key: stableId, query: query, offset: nextOffset) else { return }
            var searchSignal = context.engine.stickers.searchGifs(query: query, nextOffset: nextOffset)
            if tab == nil && nextOffset.isEmpty {
                searchSignal = searchSignal |> delay(0.2, queue: .mainQueue())
            }
            let applyResult: (ChatContextResultCollection?) -> Void = { result in
                guard let completion = searchRequests.finish(request, nextOffset: result?.nextOffset) else { return }
                let entries = (result?.results ?? []).map { State.Entry(collection: nil, row: $0) }
                let id: (State.Entry) -> AnyHashable = { entry in
                    if case let .internalReference(value) = entry.row, let file = value.file {
                        return AnyHashable(file.fileId)
                    }
                    return AnyHashable(entry.row.id)
                }
                updateState { current in
                    var current = current
                    if tab == nil {
                        guard var search = current.search, search.request == query else { return current }
                        search.items = panelSearchAppendingUnique(search.items, entries, id: id)
                        search.nextOffset = completion.nextOffset
                        search.isLoading = false
                        current.search = search
                    } else {
                        var state = current.entries[stableId] ?? .init(items: [], nextOffset: nil)
                        state.items = panelSearchAppendingUnique(state.items, entries, id: id)
                        state.nextOffset = completion.nextOffset
                        current.entries[stableId] = state
                    }
                    return current
                }
                if tab == nil {
                    updateSearchCommand()
                }
            }
            disposableDict.set((searchSignal |> take(1) |> deliverOnMainQueue).start(next: applyResult, completed: {
                applyResult(nil)
            }), forKey: stableId)
        }

        let updateSearchState:(SearchState)->Void = { searchState in
            let query = searchState.state == .Focus ? searchState.request.trimmingCharacters(in: .whitespacesAndNewlines) : ""
            guard stateValue.with({ $0.search?.request ?? "" }) != query else { return }
            searchRequests.reset(State.Search.stableId)
            disposableDict.set(nil, forKey: State.Search.stableId)
            updateState { current in
                var current = current
                current.search = query.isEmpty ? nil : .init(request: query, nextOffset: nil, items: [])
                return current
            }
            if query.isEmpty {
                updateSearchCommand()
            } else {
                makeSearch(nil, query, "")
            }
        }

        let searchInteractions = SearchInteractions({ [weak self] state, _ in
            self?.updateSearchState(state)
            updateSearchState(state)
        }, { [weak self] state in
            self?.updateSearchState(state)
            updateSearchState(state)
        })
        
        genericView.searchView.searchInteractions = searchInteractions
        
        
        let arguments = Arguments(context: context, selectTab: { [weak self] tab in
            updateState { current in
                var current = current
                current.tab = tab
                return current
            }
            
            let cached = stateValue.with { $0.entries[tab.stableId] }
            
            if let search = tab.search, cached == nil {
                makeSearch(tab, search, "")
            }
            self?.genericView.tableView.scroll(to: .up(true))
            self?.genericView.packsView.scroll(to: .center(id: InputDataEntryId.custom(_id_tab(tab.stableId)), innerId: nil, animated: true, focus: .init(focus: false), inset: 0))
        }, sendInlineResult: { [weak self] results, result, view in
            if let slowMode = self?.chatInteraction?.presentationSlowMode, slowMode.hasLocked {
                showSlowModeTimeoutTooltip(slowMode, for: view)
            } else {
                if let chatInteraction = self?.chatInteraction {
                    EntertainmentUIHooks.shared.launchSendFlight(chatInteraction, view, view.bounds, view.layer)
                }
                self?.chatInteraction?.sendInlineResult(results, result)
                self?.makeSearchCommand?(.close)
                self?.interactions?.close()
            }
        }, sendAppFile: { [weak self] file, view, silent, schedule in
            if let slowMode = self?.chatInteraction?.presentationSlowMode, slowMode.hasLocked {
                showSlowModeTimeoutTooltip(slowMode, for: view)
            } else {
                if !schedule, let chatInteraction = self?.chatInteraction {
                    EntertainmentUIHooks.shared.launchSendFlight(chatInteraction, view, view.bounds, view.layer)
                }
                self?.interactions?.sendGIF(file, silent, schedule)
                self?.makeSearchCommand?(.close)
                self?.interactions?.close()
            }
        }, showPreviewSender: { [weak self] file in
            if let chatInteraction = self?.chatInteraction {
                showModal(with: EntertainmentUIHooks.shared.makePreviewSender(file, chatInteraction), for: context.window)
                self?.makeSearchCommand?(.close)
                self?.interactions?.close()
            }
        })
        
        let mediaArguments: EntertainmentMediaArguments = .init(sendResult: { collection, result, view in
            switch result {
            case let .internalReference(values):
                if let collection = collection {
                    arguments.sendInlineResult(collection, result, view)
                }else if let file = values.file {
                    arguments.sendAppFile(file, view, false, false)
                }
            default:
                break
            }
        }, menuItems: { file, view in
            if mode == .common {
                return context.account.postbox.transaction { transaction -> [ContextMenuItem] in
                    var items: [ContextMenuItem] = []
                    if let mediaId = file.id {
                        let gifItems = transaction.getOrderedListItems(collectionId: Namespaces.OrderedItemList.CloudRecentGifs).compactMap { $0.contents.get(RecentMediaItem.self) }
                        if let _ = gifItems.firstIndex(where: {$0.media.id == mediaId}) {
                            items.append(ContextMenuItem(strings().messageContextRemoveGif, handler: {
                                let _ = removeSavedGif(postbox: context.account.postbox, mediaId: mediaId).start()
                                showModalText(for: context.window, text: strings().chatContextGifRemoved)
                            }, itemImage: MenuAnimation.menu_remove_gif.value))
                        } else {
                            items.append(ContextMenuItem(strings().messageContextSaveGif, handler: {
                                let limit = context.isPremium ? context.premiumLimits.saved_gifs_limit_premium : context.premiumLimits.saved_gifs_limit_default
                                if limit <= gifItems.count, !context.isPremium {
                                    showModalText(for: context.window, text: strings().chatContextFavoriteGifsLimitInfo("\(context.premiumLimits.saved_gifs_limit_premium)"), title: strings().chatContextFavoriteGifsLimitTitle, callback: { value in
                                        FeatureNavigationHooks.shared.showPremiumLimit(context, .savedGifs)
                                    })
                                } else {
                                    showModalText(for: context.window, text: strings().chatContextGifAdded)
                                }
                                let _ = addSavedGif(postbox: context.account.postbox, fileReference: FileMediaReference.savedGif(media: file)).start()
                            }, itemImage: MenuAnimation.menu_add_gif.value))
                        }
                        items.append(ContextMenuItem(strings().chatSendWithoutSound, handler: {
                            arguments.sendAppFile(file, view, true, false)
                        }, itemImage: MenuAnimation.menu_mute.value))
                        
                        items.append(ContextMenuItem(strings().chatSendScheduledMessage, handler: {
                            arguments.sendAppFile(file, view, false, true)
                        }, itemImage: MenuAnimation.menu_schedule_message.value))
                        
                        items.append(ContextMenuItem(strings().gifKeyboardAddCaption, handler: {
                            arguments.showPreviewSender(file)
                        }, itemImage: MenuAnimation.menu_bio.value))
                        
                        items.append(ContextMenuItem(strings().chatContextSaveMedia, handler: {
                            saveAs(file, account: context.account)
                        }, itemImage: MenuAnimation.menu_save_as.value, keyEquivalent: .cmds))
                    }
                    return items
                }
            } else {
                return .single([])
            }
        }, openMessage: { message in
            
        }, messageMenuItems: { message, view in
            return .single([])
        })
        mediaArguments.drag = { [weak self] result, point, ended in
            guard let dragItem = self?.interactions?.dragItem, case let .internalReference(values) = result, let file = values.file else {
                return false
            }
            dragItem(.file(file), nil, ended ? .ended(point) : .moved(point))
            return true
        }

        self.updateState = { f in
            updateState(f)
        }
        let presentation = self.presentation
        
        let takePresentation:()->TelegramPresentationTheme = {
            return presentation ?? theme
        }
        
        let signal:Signal<(sections: InputDataSignalValue, packs: InputDataSignalValue, state: State), NoError> = statePromise.get()
        |> deliverOnPrepareQueue
        |> map { state in
            let sections = InputDataSignalValue(entries: entries(state, arguments: arguments, mediaArguments: mediaArguments))
            let packs = InputDataSignalValue(entries: packEntries(state, arguments: arguments, presentation: takePresentation()))
            return (sections: sections, packs: packs, state: state)
        }
        
        
        let previousSections: Atomic<[AppearanceWrapperEntry<InputDataEntry>]> = Atomic(value: [])
        let previousPacks: Atomic<[AppearanceWrapperEntry<InputDataEntry>]> = Atomic(value: [])

        
        let onMainQueue: Atomic<Bool> = Atomic(value: false)
        
        let inputArguments = InputDataArguments(select: { _, _ in
            
        }, dataUpdated: {
            
        })
        
        let transition: Signal<(sections: TableUpdateTransition, packs: TableUpdateTransition, state: State), NoError> = combineLatest(queue: .mainQueue(), appearanceSignal, signal) |> mapToQueue { appearance, state in
            let sectionEntries = state.sections.entries.map({AppearanceWrapperEntry(entry: $0, appearance: appearance)})
            let packEntries = state.packs.entries.map({AppearanceWrapperEntry(entry: $0, appearance: appearance)})

            let onMain = onMainQueue.swap(false)
                        
            let sectionsTransition = prepareInputDataTransition(left: previousSections.swap(sectionEntries), right: sectionEntries, animated: state.sections.animated, searchState: state.sections.searchState, initialSize: initialSize.with{$0}, arguments: inputArguments, onMainQueue: onMain)
            
            
            let packsTransition = prepareInputDataTransition(left: previousPacks.swap(packEntries), right: packEntries, animated: state.packs.animated, searchState: state.packs.searchState, initialSize: initialSize.with{$0}, arguments: inputArguments, onMainQueue: onMain)

            return combineLatest(sectionsTransition, packsTransition) |> map { values in
                return (sections: values.0, packs: values.1, state: state.state)
            }
            
        } |> deliverOnMainQueue
        
        
        self.disposable.set(transition.start(next: { [weak self] sections, packs, state in
            self?.genericView.update(sections: sections, packs: packs, searchStatus: .resolve(isSearching: state.search != nil, isLoading: state.search?.isLoading ?? false, hasResults: !(state.search?.items.isEmpty ?? true)))
            self?.readyOnce()
        }))
        
        let recent: Signal<[State.Entry], NoError> = context.account.postbox.combinedView(keys: [.orderedItemList(id: Namespaces.OrderedItemList.CloudRecentGifs)]) |> map { view in
            
            let view = view.views[.orderedItemList(id: Namespaces.OrderedItemList.CloudRecentGifs)]! as! OrderedItemListView
            
            let result: [ChatContextResult] = view.items.compactMap({ $0.contents.get(RecentMediaItem.self)?.media._parse() }).map { file in
                let reference = ChatContextResult.InternalReference(queryId: 0, id: "gif-panel", type: "gif", title: nil, description: nil, image: nil, file: file, message: .auto(caption: "", entities: nil, replyMarkup: nil))
                return .internalReference(reference)
            }
            
            var entries:[State.Entry] = []
            for value in result {
                entries.append(.init(collection: nil, row: value))
            }
            return entries
        }
        
        let tabs: Signal<[TelegramMediaFile], NoError> = context.engine.stickers.loadedStickerPack(reference: .animatedEmoji, forceActualized: false) |> map { info in
            switch info {
            case let .result(_, items, _):
                return emojies.emojis.compactMap { emoji in
                    if let first = items.first(where: { $0.file._parse().stickerText == emoji }) {
                        return first.file._parse()
                    }
                    return nil
                }
            default:
                return []
            }
        }
        
        actionsDisposable.add(combineLatest(recent, tabs).start(next: { recent, tabs in
            updateState { current in
                var current = current
                current.entries[State.TabEntryId.recent.stableId] = State.Entries(items: recent, nextOffset: nil)
                
                var tabsEntries: [State.TabEntryId] = []
                if !recent.isEmpty {
                    tabsEntries.append(.recent)
                }
                tabsEntries.append(.trending)
                for tab in tabs {
                    tabsEntries.append(.recommended(tab))
                }
                if recent.isEmpty && current.tab == .recent {
                    current.tab = .trending
                }
                current.tabs = tabsEntries
                return current
            }
        }))
        
        self.onDeinit = {
            actionsDisposable.dispose()
            _ = previousSections.swap([])
            _ = previousPacks.swap([])
        }
        
        genericView.tableView.setScrollHandler { position in
            switch position.direction {
            case .bottom:
                let state = stateValue.with { $0 }
                if let search = state.search {
                    if let nextOffset = search.nextOffset {
                        makeSearch(nil, search.request, nextOffset)
                    }
                } else {
                    if let value = state.entries[state.tab.stableId], let nextOffset = value.nextOffset {
                        if let search = state.tab.search {
                            makeSearch(state.tab, search, nextOffset)
                        }
                    }
                }
            default:
                break
            }
        }
        
        makeSearch(.trending, "", "")
        
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.updateState? { current in
            var current = current
            current.entries = current.entries.filter({ $0.key == current.tab.stableId || $0.key == State.TabEntryId.recent.stableId })
            return current
        }
    }
    
    public override func scrollup(force: Bool = false) {
        super.scrollup(force: force)
        self.makeSearchCommand?(.close)
        self.genericView.tableView.scroll(to: .up(true))
    }
}
