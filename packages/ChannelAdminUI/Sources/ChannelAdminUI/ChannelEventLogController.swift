import Cocoa
import TGUIKit
import TelegramCore
import InAppSettings
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import TelegramTheme
import Localization
import GeneralRows
import AlertsUI
import MessageUtils
import ChatHistoryModel
import ChatUI



extension ChannelAdminEventLogEntry : @retroactive Identifiable {
}

private final class Arguments {
    let context: any AccountContextProtocol
    let toggleReveal:(MessageId)->Void
    init(context: any AccountContextProtocol, toggleReveal: @escaping (MessageId) -> Void) {
        self.context = context
        self.toggleReveal = toggleReveal
    }
}

enum ChannelEventLogState {
    case loading
    case empty(String)
    case history
}

private class SearchContainerView : View {
    let searchView: SearchView = SearchView(frame: NSZeroRect)
    let searchGlass: LiquidGlassView
    let cancelButton = ImageButton()
    var hideSearch:(()->Void)?

    static let edgeInset: CGFloat = 12
    static let height: CGFloat = 40

    required init(frame frameRect: NSRect) {
        self.searchGlass = LiquidGlassView(frame: .zero, cornerRadius: SearchContainerView.height / 2, hasShadow: false, hasBorder: true)
        super.init(frame: frameRect)
        addSubview(searchGlass)
        addSubview(searchView)

        cancelButton.autohighlight = false
        cancelButton.scaleOnClick = true
        cancelButton.setAccessibilityLabel(strings().voiceOverCommonCancel)
        cancelButton.set(handler: { [weak self] _ in
            self?.hideSearch?()
        }, for: .Click)
        addSubview(cancelButton)

        searchView.backgroundColor = .clear
        searchView.layer?.cornerRadius = SearchContainerView.height / 2

        layer?.masksToBounds = false

        updateLocalizationAndTheme(theme: theme)
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        backgroundColor = .clear
        let theme = theme as! TelegramPresentationTheme
        searchView.backgroundColor = .clear
        cancelButton.set(image: TelegramThemeHooks.shared.image(.iconPipClose).precomposed(theme.colors.text), for: .Normal)
        cancelButton.sizeToFit(.zero, NSMakeSize(SearchContainerView.height, SearchContainerView.height), thatFit: true)
        cancelButton.layer?.cornerRadius = SearchContainerView.height / 2
        cancelButton.setGlassEffect(size: NSMakeSize(SearchContainerView.height, SearchContainerView.height))
    }

    override func layout() {
        super.layout()
        let edge = SearchContainerView.edgeInset
        let cancelX = frame.width - edge - cancelButton.frame.width
        cancelButton.setFrameOrigin(NSMakePoint(cancelX, (frame.height - cancelButton.frame.height) / 2))

        let glassWidth = max(0, cancelX - edge - edge)
        let glassFrame = NSMakeRect(edge, 0, glassWidth, frame.height)
        searchGlass.frame = glassFrame
        searchView.frame = glassFrame
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class EmptyView : View {
    private let imageView = ImageView()
    private let textView = TextView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(imageView)
        addSubview(textView)
        imageView.isAccessibilityDecorative = true
    }
    
    func update(_ text: String) {
        
        self.imageView.image = TelegramThemeHooks.shared.image(.iconRecentLogs).precomposed(theme.colors.grayIcon)
        self.imageView.sizeToFit()
        
        let attributed = NSMutableAttributedString()
        _ = attributed.append(string: text, color: theme.colors.grayText, font: .normal(.title))
        attributed.detectBoldColorInString(with: .medium(.title))
        let emptyLayout = TextViewLayout(attributed, alignment: .center)
        emptyLayout.measure(width: 250)
        textView.update(emptyLayout)
                
        setFrameSize(NSMakeSize(250, imageView.frame.height + textView.frame.height + 15))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        
        imageView.centerX(y: 0)
        textView.centerX(y: imageView.frame.maxY + 15)
    }
}

public class ChannelEventLogView : View {
    fileprivate let tableView:TableView = TableView(frame: NSZeroRect, isFlipped: false)
    fileprivate let settings: TextButton = TextButton()
    fileprivate let info: ImageButton = ImageButton()
    private var emptyView:EmptyView = EmptyView(frame: .zero)
    private(set) var inSearch:Bool = false
    fileprivate var searchContainer:SearchContainerView?
    private var progress:ProgressIndicator = ProgressIndicator(frame:NSMakeRect(0, 0, 30, 30))
    
    fileprivate var searchInteractions: SearchInteractions?
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(tableView)
        addSubview(emptyView)
        addSubview(settings)
        addSubview(info)
        addSubview(progress)


        info.autohighlight = false
        info.scaleOnClick = true
        settings.autohighlight = false
        settings.scaleOnClick = true
        settings.autoSizeToFit = false

        settings.set(font: .medium(.title), for: .Normal)


        setFrameSize(frameRect.size)
        updateLocalizationAndTheme(theme: theme)
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = theme as! TelegramPresentationTheme
        settings.set(text: strings().channelEventFilterFilters, for: .Normal) //TODOLANG
        settings.set(color: theme.colors.text, for: .Normal)
        settings.set(background: .clear, for: .Highlight)
        settings.set(background: .clear, for: .Normal)
        settings.sizeToFit(NSMakeSize(30, 0), NSMakeSize(0, 40), thatFit: false)
        settings.setFrameSize(NSMakeSize(settings.frame.width, 40))
        settings.layer?.cornerRadius = 20
        settings.setGlassEffect(size: settings.frame.size)

        info.set(image: TelegramThemeHooks.shared.image(.iconChannelPromoInfo).precomposed(theme.colors.text), for: .Normal)
        info.sizeToFit(.zero, NSMakeSize(40, 40), thatFit: true)
        info.layer?.cornerRadius = 20
        info.setGlassEffect(size: NSMakeSize(40, 40))
        info.setAccessibilityLabel(strings().voiceOverCommonInfo)
        needsLayout = true
    }
    
    func updateState(_ state: ChannelEventLogState) {
        self.progress.animates = false
        switch state {
        case .history:
            self.progress.isHidden = true
            self.emptyView.isHidden = true
        case .loading:
            self.progress.isHidden = false
            self.progress.animates = true
            self.emptyView.isHidden = true
        case .empty(let text):
            self.progress.isHidden = true
            self.emptyView.isHidden = false
            self.emptyView.update(text)
        }
        needsLayout = true
    }
    
    fileprivate func toggleSearch() {
        if searchContainer != nil {
            self.hideSearch()
        } else {
            self.showSearch()
        }
       
    }
    
    fileprivate func showSearch() {
        inSearch = true

        let current: SearchContainerView
        if let view = self.searchContainer {
            current = view
        } else {
            current = SearchContainerView(frame: NSMakeRect(0, ChannelEventLogView.searchTopInset, frame.width, SearchContainerView.height))
            current.layer?.animatePosition(from: NSMakePoint(0, -current.frame.height), to: NSMakePoint(0, ChannelEventLogView.searchTopInset))
            self.searchContainer = current
            addSubview(current)
        }
        current.searchView.searchInteractions = searchInteractions
        current.searchView.setString("")
        current.searchView.change(state: .Focus, false)
        current.hideSearch = { [weak self] in
            self?.hideSearch()
        }
    }

    fileprivate func hideSearch() {
        inSearch = false
        if let searchContainer {
            searchContainer.searchView.setString("")
            performSubviewPosRemoval(searchContainer, pos: NSMakePoint(0, -searchContainer.frame.height), animated: true)
        }
        self.searchContainer = nil

    }

    static let searchTopInset: CGFloat = 12 + NavigationBarStyle.defaultHeight

    public override func layout() {
        super.layout()
        tableView.frame = NSMakeRect(0, 0, frame.width, frame.height)

        emptyView.center()
        let buttonY = frame.height - settings.frame.height - 12
        settings.setFrameOrigin(NSMakePoint((frame.width - settings.frame.width) / 2, buttonY))
        progress.center()
        info.setFrameOrigin(NSMakePoint(frame.width - info.frame.width - 12, buttonY))

        if let searchContainer {
            searchContainer.frame = NSMakeRect(0, ChannelEventLogView.searchTopInset, frame.width, SearchContainerView.height)
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct State : Equatable {
    var revealed:Set<MessageId> = Set()
}

extension AdminLogEventsResult {
    var isGroup: Bool {
        if let peer = peers[peerId] {
            return peer.isSupergroup
        }
        return false
    }
}

private func eventLogItems(_ entries:[ChannelAdminEventLogEntry], state: State, isGroup: Bool, peerId: PeerId, initialSize: NSSize, chatInteraction: ChatInteraction, searchQuery: String) -> [TableRowItem] {
    var items:[TableRowItem] = []
    var index:Int = 0
    
    var groupped: [[ChannelAdminEventLogEntry]] = []
    
    var currentPeerId: PeerId?
    var entriesToProcess = [ChannelAdminEventLogEntry]()

    func processAndClearCurrentEntries() {
        if !entriesToProcess.isEmpty {
            groupped.append(entriesToProcess)
            entriesToProcess.removeAll()
        }
    }

    for entry in entries {
        switch entry.event.action {
        case .deleteMessage:
            if currentPeerId != entry.event.peerId {
                processAndClearCurrentEntries()
                currentPeerId = entry.event.peerId
            }
            entriesToProcess.append(entry)
        default:
            if currentPeerId != nil {
                processAndClearCurrentEntries()
            }
            currentPeerId = nil
            entriesToProcess.append(entry)
            processAndClearCurrentEntries()
        }
    }

    processAndClearCurrentEntries()
    
    let getGroupMessageId:([ChannelAdminEventLogEntry]) -> MessageId? = { group in
        let last = group[group.count - 1]
        switch last.event.action {
        case let .deleteMessage(message):
            return message.id
        default:
            return nil
        }
    }
    
    for group in groupped {
        for (i, entry) in group.enumerated() {
            switch entry.event.action {
            case let .editMessage(prev, new):
                let updatedMedia: TelegramMediaWebpage = .init(webpageId: MediaId(namespace: 0, id: 0), content: .Loaded(.init(url: "", displayUrl: "", hash: 0, type: "edited", websiteName: strings().channelEventLogOriginalMessage, title: nil, text: prev.text, embedUrl: nil, embedType: nil, embedSize: nil, duration: nil, author: nil, isMediaLargeByDefault: true, imageIsVideoCover: false, image: prev.media.first as? TelegramMediaImage, file: prev.media.first as? TelegramMediaFile, story: nil, attributes: [], instantPage: nil)))
                
                let new = new.withUpdatedMedia([updatedMedia])
                
                let item = ChatRowItem.item(initialSize, from: .MessageEntry(new, MessageIndex(new), true, theme.bubbled ? .bubble : .list, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(highlightFoundText: .init(query: searchQuery, isMessage: true), eventLog: entry.event), AutoplayMediaPreferences.defaultSettings)), interaction: chatInteraction, theme: theme) as? ChatRowItem
                
                if let item = item {
                    items.append(item)
                }
            case let .deleteMessage(message):
                var message = ChannelAdminUIHooks.shared.messageWithUpdatedTimestamp(message, entry.event.date)
                
                guard let groupId = getGroupMessageId(group) else {
                    return items
                }
                
                if i == group.count - 1, group.count > 1, !state.revealed.contains(groupId) {
                    let attribute = ReplyMarkupMessageAttribute(rows: [.init(buttons: [.init(title: strings().eventLogServiceShowMoreOther(group.count - 1), titleWhenForwarded: nil, action: .text, style: nil)])], flags: [.inline], placeholder: nil)
                    message = message.withUpdatedReplyMarkupAttribute(attribute)
                }
                if group.count == 1 || state.revealed.contains(groupId) || i == group.count - 1 {
                    items.append(ChatRowItem.item(initialSize, from: .MessageEntry(ChannelAdminUIHooks.shared.messageWithUpdatedTimestamp(message, entry.event.date), MessageIndex(message), true, theme.bubbled ? .bubble : .list, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(highlightFoundText: .init(query: searchQuery, isMessage: true), eventLog: entry.event), AutoplayMediaPreferences.defaultSettings)), interaction: chatInteraction, theme: theme))
                }
            case let .sendMessage(message):
                items.append(ChatRowItem.item(initialSize, from: .MessageEntry(ChannelAdminUIHooks.shared.messageWithUpdatedTimestamp(message, entry.event.date), MessageIndex(message), true, theme.bubbled ? .bubble : .list, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(highlightFoundText: .init(query: searchQuery, isMessage: true), eventLog: entry.event), AutoplayMediaPreferences.defaultSettings)), interaction: chatInteraction, theme: theme))
            case let .updatePinned(message):
                if let message = message {
                    items.append(ChatRowItem.item(initialSize, from: .MessageEntry(ChannelAdminUIHooks.shared.messageWithUpdatedTimestamp(message, entry.event.date), MessageIndex(message), true, theme.bubbled ? .bubble : .list, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(highlightFoundText: .init(query: searchQuery, isMessage: true), eventLog: entry.event), AutoplayMediaPreferences.defaultSettings)), interaction: chatInteraction, theme: theme))
                }
            default:
                break
            }
        }
        if let entry = group.first {
            let id = getGroupMessageId(group)
            let groupRevealed = id != nil ? state.revealed.contains(id!) : false
            items.append(ServiceEventLogItem(initialSize, entry: entry, isGroup: isGroup, chatInteraction: chatInteraction, group: group, groupRevealed: groupRevealed, toggleGroup: {
                if let id = id {
                    chatInteraction.executeReplymarkup(id)
                }
            }))
            index += 1
        }
    }
    
    
    items.insert(GeneralRowItem(.zero, height: 60, stableId: -1000, backgroundColor: .clear), at: 0)
    items.append(GeneralRowItem(.zero, height: NavigationBarStyle.defaultHeight + 10, stableId: 1000, backgroundColor: .clear))
    
    for (i, item) in items.enumerated() {
        _ = item.makeSize(initialSize.width, oldWidth: initialSize.width)
        item._index = i
    }
    return items
}

open class ChannelEventLogController<Context: AccountContextProtocol>: TelegramGenericViewController<ChannelEventLogView, Context> {
    private let peerId:PeerId
    private let peer: EnginePeer
    private let chatInteraction:ChatInteraction
    private let disposable = MetaDisposable()
    private let searchState:ValuePromise<SearchState> = ValuePromise(SearchState(state: .None, request: nil), ignoreRepeated: true)
    private let filterDisposable = MetaDisposable()
    private let updateFilterDisposable = MetaDisposable()
    
    private var isGroup: Bool = true
    
    private let scrollDownOnNext: Atomic<Bool> = Atomic(value: false)
    
    private let filterStateValue:ValuePromise<ChannelEventFilterState> = ValuePromise(ChannelEventFilterState())
    private let filterState:Atomic<ChannelEventFilterState> = Atomic(value: ChannelEventFilterState())

    private func updateFilter(_ f:(ChannelEventFilterState)->ChannelEventFilterState) -> Void {
        self.filterStateValue.set(filterState.modify(f))
    }
        
    open override var defaultBarStatus: String? {
        let state = self.filterState.with { $0 }
        
        if state.isFull {
            return strings().telegramChannelEventLogController
        } else {
            return strings().channelEventLogsTitleSelected
        }
        
    }
    
    open override var defaultBarTitle: String {
        return self.peer._asPeer().displayTitle
    }
    
    open override func viewClass() -> AnyClass {
        return ChannelEventLogView.self
    }
    

    private func showFilter() {
        let state = filterState.with { $0 }
        let context = self.context
        let peerId = self.peerId
        let isChannel = !self.isGroup
        let adminsPromise = ValuePromise<[RenderedChannelParticipant]?>(nil)
        _ = context.peerChannelMemberCategoriesContextsManager.admins(peerId: peerId, updated: { membersState in
            if case .loading = membersState.loadingState, membersState.list.isEmpty {
                adminsPromise.set(nil)
            } else {
                adminsPromise.set(membersState.list)
            }
        })
            
        let admins = adminsPromise.get() |> filter { $0 != nil } |> take(1) |> map { $0! }
        filterDisposable.set(showModalProgress(signal: admins, for: context.window).start(next: { [weak self] admins in
            showModal(with: ChannelEventFilterModalController(context: context, peerId: peerId, isChannel: isChannel, admins: admins, state: state, updated: { [weak self] updatedState in
                
                _ = self?.scrollDownOnNext.swap(true)
                self?.updateFilter { _ in
                    return updatedState
                }
                _ = self?.scrollDownOnNext.swap(true)
                self?.requestUpdateCenterBar()
        }), for: context.window)
            
        }))
    }
    
    public init(_ context: Context, peer: EnginePeer) {
        self.peerId = peer.id
        self.peer = peer
        chatInteraction = ChatInteraction(chatLocation: .peer(peerId), context: context, isLogInteraction: true)
        chatInteraction.update {
            $0.updatedPeer { _ in
                peer._asPeer()
            }
        }
        super.init(context)
        
    }
    
    open override var enableBack: Bool {
        return true
    }
    
    deinit {
        disposable.dispose()
        filterDisposable.dispose()
        updateFilterDisposable.dispose()
    }
    
    open override func requestUpdateRightBar() {
        super.requestUpdateRightBar()
        (self.rightBarView as? ImageBarView)?.set(image: theme.icons.chatSearch)
    }
    
    open override func getRightBarViewOnce() -> BarView {
        let bar = ImageBarView(controller: self, theme.icons.chatSearch)
        bar.button.set(handler: { [weak self] _ in
            self?.genericView.toggleSearch()
        }, for: .Click)
        
        
        bar.button.scaleOnClick = true
        
        return bar
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let controller = ChannelAdminUIHooks.shared.getAudioPlayer(context), let header = self.navigationController?.header, header.needShown {
            let object = ChannelAdminUIHooks.shared.makeInlineAudioPlayerContextObject(controller, context, genericView.tableView, nil)
            header.view.update(with: object)
        }
    }
    
    open override func escapeKeyAction() -> KeyHandlerResult {
        if genericView.inSearch {
            genericView.hideSearch()
            return .invoked
        }
        return super.escapeKeyAction()
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            if let strongSelf = self {
                if !strongSelf.genericView.inSearch {
                    strongSelf.genericView.showSearch()
                } else {
                    strongSelf.genericView.hideSearch()
                }
            }
            return .invoked
            }, with: self, for: .F, modifierFlags: [.command])
    }
    
    open override var backdorColor: NSColor {
        return theme.colors.listBackground
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        genericView.tableView.getBackgroundColor = {
            return .clear
        }
        
        let statePromise = ValuePromise(State(), ignoreRepeated: true)
        let stateValue = Atomic(value: State())
        let updateState: ((State) -> State) -> Void = { f in
            statePromise.set(stateValue.modify (f))
        }
        
        let searchState = self.searchState
        let context = self.context
        let initialSize = self.atomicSize
        let chatInteraction = self.chatInteraction
        let peerId = self.peerId
        let eventLogContext = context.engine.peers.channelAdminEventLog(peerId: peerId)
        let scrollDownOnNext = self.scrollDownOnNext
        
        let searchQuery: Atomic<String> = Atomic(value: "")

        let arguments = Arguments(context: context, toggleReveal: { messageId in
            updateState { current in
                var current = current
                if current.revealed.contains(messageId) {
                    current.revealed.remove(messageId)
                } else {
                    current.revealed.insert(messageId)
                }
                return current
            }
        })
        
        chatInteraction.executeReplymarkup = { messageId in
            arguments.toggleReveal(messageId)
        }
        
        chatInteraction.focusMessageId = { [weak self] messageId, focusTarget, _ in
            self?.navigationController?.push(ChatAdditionController(context: context, chatLocation: .peer(peerId), focusTarget: focusTarget))
        }
        

        genericView.info.set(handler: { _ in
            alert(for: context.window, header: strings().channelEventLogAlertHeader, info: strings().channelEventLogAlertInfo)
        }, for: .Click)
        
        
        genericView.settings.set(handler: { [weak self] _ in
            self?.showFilter()
        }, for: .Click)
        
        genericView.searchInteractions = SearchInteractions({ state, _ in
            _ = searchQuery.swap(state.request)
            _ = scrollDownOnNext.swap(true)
            searchState.set(state)
            _ = scrollDownOnNext.swap(true)
        }, { state in
            _ = searchQuery.swap(state.request)
            _ = scrollDownOnNext.swap(true)
            searchState.set(state)
            _ = scrollDownOnNext.swap(true)
        })
        

        self.chatInteraction.openInfo = { [weak self] peerId, _, _, _ in
            if let navigation = self?.navigationController {
                ChannelAdminUIHooks.shared.pushPeerInfo(navigation, context, peerId)
            }
        }
        
        self.chatInteraction.inlineAudioPlayer = { [weak self] controller in
            ChannelAdminUIHooks.shared.showInlineAudioPlayer(controller, context, self?.genericView.tableView, nil)
        }
        
        let updateFilter = combineLatest(queue: .mainQueue(), searchState.get(), filterStateValue.get())
        
        updateFilterDisposable.set(updateFilter.start(next: { search, filter in
            eventLogContext.setFilter(.init(query: search.request, events: filter.selectedFlags, adminPeerIds: filter.selectedAdmins))
        }))

        let isGroup = !peer._asPeer().isChannel
        
        let signal: Signal<([TableRowItem], ([ChannelAdminEventLogEntry], Bool, ChannelAdminEventLogUpdateType, Bool), Bool), NoError> = combineLatest(eventLogContext.get(), statePromise.get()) |> map { result, state in
            let items = eventLogItems(result.0.reversed(), state: state, isGroup: isGroup, peerId: peerId, initialSize: initialSize.with { $0 }, chatInteraction: chatInteraction, searchQuery: searchQuery.with { $0 })
             return (items, result, isGroup)

        } |> deliverOnMainQueue
        
        
        
        disposable.set(signal.start(next: { [weak self] items, result, isGroup in
            guard let self else {
                return
            }
            
            let tableView = self.genericView.tableView

            let (deleteIndices, indicesAndItems, updatedAndItems) = mergeListsStableWithUpdates(leftList: tableView.allItems, rightList: items)
            
            let animated: Bool
            let scrollState: TableScrollState
            if scrollDownOnNext.swap(false) {
                scrollState = .down(false)
                animated = false
            } else {
                scrollState = .saveVisible(.upper, false)
                animated = false
            }
            
            let transition = TableUpdateTransition(deleted: deleteIndices, inserted: indicesAndItems.map { ($0.0, $0.1) }, updated: updatedAndItems.map { ($0.0, $0.1) }, animated: animated, state: scrollState, grouping: true)
            
            tableView.merge(with: transition)
            
           

            self.isGroup = isGroup
            
            switch result.2 {
            case .initial:
                self.genericView.updateState(.loading)
            case .load, .generic:
                if items.isEmpty {
                    self.genericView.updateState(.empty(!isGroup ? strings().channelEventLogEmptyText : strings().groupEventLogEmptyText))
                } else {
                    self.genericView.updateState(.history)
                }
            }
            self.readyOnce()
        }))
        
        genericView.tableView.setScrollHandler { scroll in
            switch scroll.direction {
            case .bottom:
                eventLogContext.loadMoreEntries()
            default:
                break
            }
        }
            

    }
    
    
}

