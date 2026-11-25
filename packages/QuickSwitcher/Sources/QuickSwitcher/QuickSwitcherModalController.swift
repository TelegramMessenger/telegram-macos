import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import KeyboardKey
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import TelegramTheme
import Localization
import ColorPalette
import GeneralRows
import ShortPeerRow
import Strings
import InAppSettings
import TelegramIconsTheme
import AppAnalytics

private class QuickSwitcherArguments {
    let context: any AccountContextProtocol
    init(_ context:any AccountContextProtocol) {
        self.context = context
    }
}

private enum QuickSwitcherSeparator : Int32 {
    case recently = 1
    case popular = 2
}

private enum QuickSwitcherStableId : Hashable {
    case peerId(PeerId, SecretChatWrapper?)
    case separator(QuickSwitcherSeparator)
    case empty
    case addAccount
    func hash(into hasher: inout Hasher) {
        hasher.combine(0)
    }
    var effectivePeerId: PeerId? {
        switch self {
        case let .peerId(peerId, secretPeerId):
            return secretPeerId?.peerId ?? peerId
        default:
            return nil
        }
    }
}

private struct SecretChatWrapper : Equatable {
    let peerId:PeerId
}

private enum QuickSwitcherEntry : TableItemListNodeEntry {
    case peer(Int32, AccountWithInfo, Bool, SecretChatWrapper?, Bool)
    case separator(Int32, QuickSwitcherSeparator)
    case addAccount(Int32)
    case empty
    var stableId:QuickSwitcherStableId {
        switch self {
        case let .peer(_, peer, _, secretChat, _):
            return .peerId(peer.peer.id, secretChat)
        case .separator(_, let id):
            return .separator(id)
        case .addAccount:
            return .addAccount
        case .empty:
            return .empty
        }
    }
    
    var index:Int32 {
        switch self {
        case .peer(let index, _, _, _, _):
            return index
        case .separator(let index, _):
            return index
        case let .addAccount(index):
            return index
        case .empty:
            return 0
        }
    }
    
    func item(_ arguments: QuickSwitcherArguments, initialSize: NSSize) -> TableRowItem {
        switch self {
        case let .peer(_, peer, drawSeparator, secretChat, displayAsSaved):
            return ShortPeerRowItem(initialSize, peer: peer.peer, account: peer.account, context: arguments.context, stableId: stableId, height: 40, photoSize: NSMakeSize(30, 30), titleStyle: ControlStyle(font: .medium(.text), foregroundColor: secretChat != nil ? theme.colors.accent : theme.colors.text, highlightColor:.white), drawCustomSeparator: drawSeparator, isLookSavedMessage: displayAsSaved, drawLastSeparator: true, action: {
                
            })
        case .separator(_, let id):
            let text:String
            switch id {
            case .recently:
                text = strings().quickSwitcherRecently
            case .popular:
                text = strings().quickSwitcherPopular
            }
            return SeparatorRowItem(initialSize, stableId, string: text.uppercased())
        case .addAccount:
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().accountSettingsAddAccount, icon: theme.icons.account_add_account, activeIcon: TelegramThemeHooks.shared.image(.iconAccountAddAccount).precomposed(theme.colors.underSelectedColor, flipVertical: true), nameStyle: ControlStyle(font: .normal(.title), foregroundColor: theme.colors.accentIcon), type: .none, viewType: .legacy, action: {
                
            }, border:[BorderType.Right], inset:NSEdgeInsets(left: 0, right: 0), iconTextInset: 50, iconInset: 14)
        case .empty:
            return SearchEmptyRowItem(initialSize, stableId: stableId)
        }
    }
}

private func ==(lhs: QuickSwitcherEntry, rhs: QuickSwitcherEntry) -> Bool {
    switch lhs {
    case let .peer(lhsIndex, lhsPeer, lhsDrawSeparator, lhsSecretChat, lhsDisplayAsSaved):
        if case .peer(lhsIndex, lhsPeer, lhsDrawSeparator, lhsSecretChat, lhsDisplayAsSaved) = rhs {
            return true
        } else {
            return false
        }
    case let .separator(index, sectionId):
        if case .separator(index, sectionId) = rhs {
            return true
        } else {
            return false
        }
    case let .addAccount(index):
        if case .addAccount(index) = rhs {
            return true
        } else {
            return false
        }
    case .empty:
        if case .empty = rhs {
            return true
        } else {
            return false
        }
    }
}
private func <(lhs: QuickSwitcherEntry, rhs: QuickSwitcherEntry) -> Bool {
    return lhs.index < rhs.index
}

private class ForumTopicArguments {
    let context: any AccountContextProtocol
    init(context: any AccountContextProtocol) {
        self.context = context
    }
}

private struct ForumTopicItem : Comparable, Identifiable {
    let item: EngineChatList.Item

    static func < (lhs: ForumTopicItem, rhs: ForumTopicItem) -> Bool {
        return lhs.item.index < rhs.item.index
    }
    static func == (lhs: ForumTopicItem, rhs: ForumTopicItem) -> Bool {
        return lhs.item == rhs.item
    }

    var stableId: EngineChatList.Item.Id {
        return item.id
    }
    func item(_ arguments: ForumTopicArguments, initialSize: NSSize) -> TableRowItem {
        return QuickSwitcherHooks.shared.makeSearchTopicItem(initialSize, self.item.id, self.item, arguments.context)
    }
}

private class QuickSwitcherView : View {
    let tableView:TableView = TableView()
    let textView:TextView = TextView()
    let searchView:SearchView = SearchView(frame: NSMakeRect(0,0, 280, 30))
    let separator:View = View()
    var forumTopicsView: TableView?
    fileprivate var forumTopicItems: [ForumTopicItem] = []
    var inForumMode: Bool {
        return forumTopicsView != nil
    }
    var activeTableView: TableView {
        return forumTopicsView ?? tableView
    }
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(tableView)
        addSubview(searchView)
        addSubview(textView)
        addSubview(separator)
        textView.isSelectable = false
        separator.backgroundColor = theme.colors.border
        self.backgroundColor = theme.colors.background
        let attributed = NSMutableAttributedString()
        _ = attributed.append(string: strings().quickSwitcherDescription, color: theme.colors.grayText, font: .normal(.text))
        attributed.detectBoldColorInString(with: .medium(.text))
        let descLayout = TextViewLayout(attributed, alignment: .center)
        descLayout.measure(width: frameRect.width - 20)
        textView.update(descLayout)
        textView.backgroundColor = theme.colors.background
        layout()
    }
    
    override func layout() {
        super.layout()
        searchView.centerX(y: floorToScreenPixels(backingScaleFactor, (50 - 30)/2))
        tableView.frame = NSMakeRect(0, 50, frame.width, frame.height - 100)
        forumTopicsView?.frame = tableView.frame
        textView.centerX(y: frame.height - floorToScreenPixels(backingScaleFactor, (50 - textView.frame.height)/2) - textView.frame.height)
        separator.frame = NSMakeRect(0, frame.height - 50, frame.width, .borderSize)
    }
    
    func appearForumTopics(_ items: [EngineChatList.Item], context: any AccountContextProtocol, delegate: TableViewDelegate?, animated: Bool) {
        let arguments = ForumTopicArguments(context: context)
        let mapped: [ForumTopicItem] = items.map { .init(item: $0) }
        let animated = animated && self.forumTopicsView == nil

        let tableView = self.forumTopicsView ?? TableView()
        if tableView.superview == nil {
            tableView.frame = self.tableView.frame
            addSubview(tableView)
            self.forumTopicsView = tableView
            tableView.getBackgroundColor = {
                return theme.colors.background
            }
        }

        tableView.delegate = delegate

        let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: self.forumTopicItems, rightList: mapped)
        self.forumTopicItems = mapped

        tableView.beginTableUpdates()
        for deleteIndex in deleteIndices.reversed() {
            tableView.remove(at: deleteIndex)
        }
        for indicesAndItem in indicesAndItems {
            let item = indicesAndItem.1.item(arguments, initialSize: tableView.frame.size)
            _ = tableView.insert(item: item, at: indicesAndItem.0)
        }
        for updateIndex in updateIndices {
            let item = updateIndex.1.item(arguments, initialSize: tableView.frame.size)
            tableView.replace(item: item, at: updateIndex.0, animated: false)
        }
        tableView.endTableUpdates()

        if animated {
            let oneOfThird = frame.width / 3
            tableView.layer?.animatePosition(from: NSMakePoint(oneOfThird * 2, tableView.frame.minY), to: tableView.frame.origin, duration: 0.35, timingFunction: .spring)
            self.tableView.layer?.animatePosition(from: tableView.frame.origin, to: NSMakePoint(-oneOfThird, tableView.frame.minY), duration: 0.35, timingFunction: .spring)
        }

        needsLayout = true
    }

    func cancelForum(animated: Bool) {
        guard let view = self.forumTopicsView else {
            return
        }
        if animated {
            let oneOfThird = frame.width / 3
            view.layer?.animatePosition(from: tableView.frame.origin, to: NSMakePoint(frame.width, view.frame.minY), duration: 0.35, timingFunction: .spring, removeOnCompletion: false, completion: { [weak view] _ in
                view?.removeFromSuperview()
            })
            self.tableView.layer?.animatePosition(from: NSMakePoint(-oneOfThird, tableView.frame.minY), to: tableView.frame.origin, duration: 0.35, timingFunction: .spring)
        } else {
            view.removeFromSuperview()
        }
        self.forumTopicsView = nil
        self.forumTopicItems = []
        needsLayout = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


private func searchEntriesForPeers(_ peers:[AccountWithInfo], recentlyUsed:[(AccountWithInfo, SecretChatWrapper?)], isLoading: Bool, displayAsSaved: Bool, canAddAccount: Bool = false) -> [QuickSwitcherEntry] {
    var entries: [QuickSwitcherEntry] = []
    
    var index:Int32 = 0

    if !recentlyUsed.isEmpty {
        entries.append(.separator(index, .recently))
        index += 1
    }
   
    
    var isset:[PeerId:PeerId] = [:]
    for peer in recentlyUsed {
        if isset[peer.0.peer.id] == nil {
            entries.append(.peer(index, peer.0, peer.0.peer.id != recentlyUsed.last?.0.peer.id, peer.1, displayAsSaved))
            index += 1
            isset[peer.0.peer.id] = peer.0.peer.id
        }
    }
    
    if !recentlyUsed.isEmpty {
        entries.append(.separator(index, .popular))
        index += 1
    }
    
    for peer in peers {
        if isset[peer.peer.id] == nil {
            entries.append(.peer(index, peer, true, nil, displayAsSaved))
            index += 1
            isset[peer.peer.id] = peer.peer.id
        }
    }
    
    if entries.isEmpty && !isLoading {
        entries.append(.empty)
    } else if canAddAccount {
        entries.append(.addAccount(index))
        index += 1
    }
    
    return entries
}

fileprivate func prepareTransition(left:[AppearanceWrapperEntry<QuickSwitcherEntry>], right: [AppearanceWrapperEntry<QuickSwitcherEntry>], initialSize:NSSize, arguments:QuickSwitcherArguments) -> TableUpdateTransition {
    
    let (removed, inserted, updated) = proccessEntriesWithoutReverse(left, right: right) { entry -> TableRowItem in
        return entry.entry.item(arguments, initialSize: initialSize)
    }
    
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: false)
}


public class QuickSwitcherModalController: ModalViewController, TableViewDelegate {
    public func findGroupStableId(for stableId: AnyHashable) -> AnyHashable? {
        return nil
    }
    
    private let context:any AccountContextProtocol
    private let search:ValuePromise<SearchState> = ValuePromise(ignoreRepeated: true)
    private let disposable = MetaDisposable()
    private let forumDisposable = MetaDisposable()
    private var forumPeerId: PeerId?
    fileprivate func start(context: any AccountContextProtocol, recentlyUsed:[PeerId], search:Signal<SearchState, NoError>) -> Signal<([QuickSwitcherEntry], Bool), NoError> {
        
        return search |> mapToSignal { search -> Signal<([QuickSwitcherEntry], Bool), NoError> in
            
            if search.request.isEmpty {
                return combineLatest(context.engine.peers.recentPeers() |> take(1), context.account.postbox.multiplePeersView(recentlyUsed) |> take(1))
                    |> deliverOn(prepareQueue)
                    |> mapToSignal { recentPeers, view -> Signal<([QuickSwitcherEntry], Bool), NoError> in
                        
                        var peers:[Peer] = []
                        
                        switch recentPeers {
                        case let .peers(list):
                            peers = list
                        default:
                            break
                        }
                        
                        var recentl:[(AccountWithInfo, SecretChatWrapper?)] = []
                        for peerId in recentlyUsed {
                            if let peer = view.peers[peerId] {
                                recentl.append((AccountWithInfo(account: context.account, peer: peer), nil))
                            }
                        }
                        let secretChats = recentl.compactMap { $0.0.peer as? TelegramSecretChat }.compactMap { $0.associatedPeerId }
                        
                        if !secretChats.isEmpty {
                            return context.account.postbox.multiplePeersView(secretChats) |> take(1) |> map { secretPeers in
                                var recentl:[(AccountWithInfo, SecretChatWrapper?)] = []
                                for peerId in recentlyUsed {
                                    if let peer = view.peers[peerId] {
                                        if let peer = peer as? TelegramSecretChat {
                                            if let secretPeer = secretPeers.peers[peer.associatedPeerId!] {
                                                recentl.append((AccountWithInfo(account: context.account, peer: secretPeer), SecretChatWrapper(peerId: peer.id)))
                                            }
                                        } else {
                                            recentl.append((AccountWithInfo(account: context.account, peer: peer), nil))
                                        }
                                    }
                                }
                                return (searchEntriesForPeers(peers.map { .init(account: context.account, peer: $0) }, recentlyUsed: recentl, isLoading: false, displayAsSaved: true), false)
                            }
                        } else {
                            return .single((searchEntriesForPeers(peers.map { .init(account: context.account, peer: $0) }, recentlyUsed: recentl, isLoading: false, displayAsSaved: true), false))
                        }
                }
                
            } else  {
                
                var all = search.request.transformKeyboard
                all.insert(search.request.lowercased(), at: 0)
                all = all.uniqueElements
                let localPeers = combineLatest(all.map {
                    return context.account.postbox.searchPeers(query: $0)
                }) |> map { result in
                    return result.reduce([], {
                        return $0 + $1
                    })
                }
                
                let foundLocalPeers = localPeers |> map {
                    return $0.compactMap({$0.chatMainPeer}).filter({!($0 is TelegramSecretChat)})
                }
                                
                let foundRemotePeers = Signal<[Peer], NoError>.single([]) |> then(context.engine.contacts.searchRemotePeers(query: search.request.lowercased()) |> map { $0.0.map({ $0.peer._asPeer() }) + $0.1.map { $0.peer._asPeer() } } )
                
                return combineLatest(combineLatest(foundLocalPeers, foundRemotePeers) |> map {$0 + $1}, context.account.postbox.loadedPeerWithId(context.peerId)) |> map { values -> ([Peer], Bool) in
                    var peers = values.0
                    if strings().peerSavedMessages.lowercased().hasPrefix(search.request.lowercased()) || NSLocalizedString("Peer.SavedMessages", comment: "nil").lowercased().hasPrefix(search.request.lowercased()) {
                        peers.insert(values.1, at: 0)
                    }
                    
                    return (uniquePeers(from: peers), false)
                }
                |> runOn(prepareQueue)
                |> map { values -> ([QuickSwitcherEntry], Bool) in
                    return (searchEntriesForPeers(values.0.map { AccountWithInfo(account: context.account, peer: $0) }, recentlyUsed: [], isLoading: values.1, displayAsSaved: true), values.1)
                }
            }
        }
    }
    
    fileprivate func startAccounts(context: any AccountContextProtocol, search:Signal<SearchState, NoError>) -> Signal<([QuickSwitcherEntry], Bool), NoError> {
        
        return search |> mapToSignal { search -> Signal<([QuickSwitcherEntry], Bool), NoError> in
            return context.sharedContext.activeAccountsWithInfo
                |> take(1)
                |> deliverOn(prepareQueue)
                |> map { primary, accounts in
                    let peers:[AccountWithInfo] = accounts.sorted(by: { lhs, rhs in
                        if lhs.account.id == primary {
                            return true
                        } else {
                            return false
                        }
                    }).filter { value in
                        return search.request.isEmpty || value.peer.displayTitle.lowercased().contains(search.request.lowercased())
                    }
                    
                    let accountsLimit: Int = normalAccountsLimit
                    let effectiveLimit: Int
                    if context.premiumIsBlocked {
                        effectiveLimit = accountsLimit
                    } else {
                        effectiveLimit = accountsLimit + 1
                    }
                    
                    let canAddAccount = effectiveLimit > peers.count
                    
                    return (searchEntriesForPeers(peers, recentlyUsed: [], isLoading: false, displayAsSaved: false, canAddAccount: canAddAccount), false)
            }
        }
    }

    
    public enum Source {
        case quick
        case accounts
    }
    private let source: Source
    
    public init(_ context: any AccountContextProtocol, source: Source = .quick) {
        self.context = context
        self.source = source
        super.init(frame: NSMakeRect(0, 0, 300, 360))
        bar = .init(height: 0)
        switch source {
        case .quick:
            self.analyticsScreen = .macosQuickSwitcher
        case .accounts:
            self.analyticsScreen = .macosAccountSwitcher
        }
    }
    
    public override func viewClass() -> AnyClass {
        return QuickSwitcherView.self
    }
    
    private var genericView:QuickSwitcherView {
        return self.view as! QuickSwitcherView
    }
    
    public override func firstResponder() -> NSResponder? {
        return genericView.searchView.input
    }
    
    public override func escapeKeyAction() -> KeyHandlerResult {
        if genericView.inForumMode {
            cancelForum(animated: true)
            return .invoked
        }
        return .rejected
    }
    
    deinit {
        disposable.dispose()
        forumDisposable.dispose()
    }
    
    public override func becomeFirstResponder() -> Bool? {
        return true
    }
    
    public func selectionWillChange(row:Int, item:TableRowItem, byClick: Bool) -> Bool {
        return item is ShortPeerRowItem || item is GeneralInteractedRowItem || item is QuickSwitcherTopicRowItem
    }
    
    public func selectionDidChange(row:Int, item:TableRowItem, byClick:Bool, isNew:Bool) -> Void {
        if byClick {
            _ = returnKeyAction()
        }
    }
    
    public func isSelectable(row:Int, item:TableRowItem) -> Bool {
        return true
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        genericView.tableView.delegate = self
        search.set(SearchState(state: .None, request: nil))
        
        let searchInteractions = SearchInteractions({ [weak self] state, _ in
            self?.search.set(state)
        }, { [weak self] state in
            self?.search.set(state)
        })
        
        let arguments = QuickSwitcherArguments(context)
        
        genericView.searchView.searchInteractions = searchInteractions
        
        genericView.searchView.change(state: .Focus, false)
        
        
        let previous:Atomic<[AppearanceWrapperEntry<QuickSwitcherEntry>]> = Atomic(value: [])
        let initialSize = atomicSize
        
        let signal: Signal<([QuickSwitcherEntry], Bool), NoError>
        switch source {
        case .quick:
            signal = start(context: context, recentlyUsed: Array(QuickSwitcherHooks.shared.recentlyPeerUsed(context).prefix(3)), search: search.get())
        case .accounts:
            signal = startAccounts(context: context, search: search.get())
        }
        
        disposable.set((combineLatest(signal, appearanceSignal) |> map { value, appearance -> (TableUpdateTransition, Bool) in
            let entries = value.0.map{AppearanceWrapperEntry(entry: $0, appearance: appearance)}
            return (prepareTransition(left: previous.swap(entries), right: entries, initialSize: initialSize.modify {$0}, arguments: arguments), value.1)
        } |> deliverOnMainQueue).start(next: { [weak self] value in
            self?.genericView.tableView.merge(with: value.0)
            self?.genericView.searchView.isLoading = value.1
            self?.genericView.tableView.cancelSelection()
            self?.genericView.tableView.selectNext(false)
            self?.readyOnce()
        }))
        
    }
    
    public override func returnKeyAction() -> KeyHandlerResult {
        if genericView.inForumMode, let forumPeerId = self.forumPeerId {
            if let selectedItem = genericView.forumTopicsView?.selectedItem() as? QuickSwitcherTopicRowItem, let threadId = selectedItem.threadId {
                _ = QuickSwitcherHooks.shared.openForumTopic(threadId, forumPeerId, context, true)
                close()
            }
            return .invoked
        }
        if let selectedItem = genericView.tableView.selectedItem() as? ShortPeerRowItem {
            switch source {
            case .quick:
                if TelegramUtilsHooks.shared.peerIsForum(selectedItem.peer) {
                    openForum(selectedItem.peer.id, animated: true)
                    return .invoked
                }
                let query = self.genericView.searchView.query
                var peerId = selectedItem.peer.id
                var messageId: MessageId? = nil
                let link = QuickSwitcherHooks.shared.inAppLink(query as NSString, context, peerId)
                switch link {
                case let .followResolvedName(_, _, postId, _, _, _, _):
                    if let postId = postId {
                        messageId = MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: postId)
                    }
                default:
                    break
                }

                if let stableId = selectedItem.stableId as? QuickSwitcherStableId, let effectivePeerId = stableId.effectivePeerId {
                    peerId = effectivePeerId
                }

                QuickSwitcherHooks.shared.navigateToChatWithFocus(context.bindings.rootNavigation(), context, .peer(peerId), messageId)

            case .accounts:
                context.sharedContext.switchToAccount(id: selectedItem.account.id, action: nil)
            }

            close()
        } else if genericView.tableView.selectedItem() is GeneralInteractedRowItem {
            var accounts: [Peer] = []
            genericView.tableView.enumerateItems(with: { item in
                if let item = item as? ShortPeerRowItem {
                    accounts.append(item.peer)
                }
                return true
            })
            let hasPremium = accounts.contains(where: { $0.isPremium })
            if accounts.count == normalAccountsLimit {
                if hasPremium {
                    context.sharedContext.beginNewAuth(testingEnvironment: false)
                } else {
                    QuickSwitcherHooks.shared.showAccountsLimit(context, accounts.count)
                }
            } else {
                context.sharedContext.beginNewAuth(testingEnvironment: false)
            }
            close()
        }
        return .invoked
    }
    
    private func openForum(_ peerId: PeerId, animated: Bool) {
        self.forumPeerId = peerId
        genericView.searchView.setString("")

        let context = self.context

        var filter = QuickSwitcherHooks.shared.forumChatListView(peerId, context.account) |> filter {
            !$0.list.isLoading
        } |> take(1)

        filter = showModalProgress(signal: filter, for: context.window)

        let signal: Signal<[EngineChatList.Item], NoError> = combineLatest(filter, self.search.get()) |> map { update, query in
            let items = Array(update.list.items.reversed())
            if query.request.isEmpty {
                return items
            } else {
                return items.filter { item in
                    let title = item.threadData?.info.title ?? ""
                    return title.lowercased().contains(query.request.lowercased())
                }
            }
        } |> deliverOnMainQueue

        forumDisposable.set(signal.start(next: { [weak self] items in
            guard let self else { return }
            self.genericView.appearForumTopics(items, context: context, delegate: self, animated: animated)
            self.genericView.forumTopicsView?.cancelSelection()
            self.genericView.forumTopicsView?.selectNext(false)
        }))
    }

    private func cancelForum(animated: Bool) {
        self.forumPeerId = nil
        self.forumDisposable.set(nil)
        self.genericView.cancelForum(animated: animated)
        self.genericView.searchView.setString("")
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.activeTableView.selectPrev()
            return .invoked
        }, with: modal!, for: .UpArrow, priority: .modal)

        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.activeTableView.selectNext()
            return .invoked
        }, with: modal!, for: .DownArrow, priority: .modal)

        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.activeTableView.selectNext()
            return .invoked
        }, with: modal!, for: .Tab, priority: .modal)


        let digitKeys: [KeyboardKey] = [.One, .Two, .Three, .Four, .Five, .Six, .Seven, .Eight, .Nine]
        for (index, key) in digitKeys.enumerated() {
            self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
                guard let self, self.genericView.searchView.query.isEmpty else {
                    return .rejected
                }
                self.genericView.activeTableView.selectAt(index)
                return .invoked
            }, with: modal!, for: key, priority: .modal, modifierFlags: [.command])
        }
        
    }
    
    public override var hasBorder: Bool {
        return false
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        window?.removeAllHandlers(for: self)
    }
}
