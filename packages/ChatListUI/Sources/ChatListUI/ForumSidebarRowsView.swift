import Cocoa
import TGUIKit
import TelegramCore
import TelegramContext
import ChatUI
import Postbox
import SwiftSignalKit
import Localization
import TelegramTheme
import AlertsUI

private final class SidebarRootRowItem: ChatListRowItem {
    override var stableId: AnyHashable { "chat-sidebar-root" }
    override var hasRevealState: Bool { false }
    override var isForum: Bool { false }
    override var accessibilityCustomActions: [NSAccessibilityCustomAction]? { nil }

    override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        .single([])
    }
}

public final class ForumSidebarRowsView<Context: AccountContextProtocol>: View, ForumSidebarRowsContent, TableViewDelegate {
    public var view: NSView { self }
    private let tableView = TableView(frame: .zero)
    private let context: Context
    private let onSelect: (Int64?, MessageId?) -> Void
    private var kind: ChatSidebarKind = .forum
    private var selection = ForumSidebarSelection()
    private let selectionBar = View()
    private let readButton = TextButton()
    private let muteButton = TextButton()
    private let deleteButton = TextButton()
    public var isSelecting: Bool { selection.isActive }
    public var selectionChanged: ((Bool) -> Void)?
    private var rootRowId: AnyHashable?
    private var searchController: SearchController<Context>?
    private var searchPeerId: PeerId?
    private let searchLoading = MetaDisposable()
    private let inputActivities = MetaDisposable()
    private var activities: [PeerActivitySpace: [PeerListState.InputActivities.Activity]] = [:]
    private var content: (items: [EngineChatList.Item], selectedThreadId: Int64?, kind: ChatSidebarKind, parentPeer: EngineRenderedPeer)?

    public init(context: Context, onSelect: @escaping (Int64?, MessageId?) -> Void) {
        self.context = context
        self.onSelect = onSelect
        super.init(frame: .zero)
        tableView.delegate = self
        tableView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 88, right: 0)
        addSubview(tableView)
        selectionBar.backgroundColor = theme.colors.background
        selectionBar.isHidden = true
        addSubview(selectionBar)
        for (button, title) in [(readButton, strings().chatListSwipingRead), (muteButton, strings().chatListSwipingMute), (deleteButton, strings().chatListSwipingDelete)] {
            button.autoSizeToFit = false
            button.scaleOnClick = true
            button.set(text: title, for: .Normal)
            button.set(font: .medium(13), for: .Normal)
            button.set(color: button === deleteButton ? theme.colors.redUI : theme.colors.accent, for: .Normal)
            selectionBar.addSubview(button)
        }
        readButton.set(handler: { [weak self] _ in self?.applySelection(.read) }, for: .Click)
        muteButton.set(handler: { [weak self] _ in self?.applySelection(.mute) }, for: .Click)
        deleteButton.set(handler: { [weak self] _ in self?.applySelection(.delete) }, for: .Click)
        inputActivities.set((context.account.allPeerInputActivities() |> mapToSignal { values in
            context.account.postbox.transaction { transaction -> [PeerActivitySpace: [PeerListState.InputActivities.Activity]] in
                values.mapValues { entries in
                    entries.compactMap { peerId, activity in
                        transaction.getPeer(peerId).map { PeerListState.InputActivities.Activity($0, activity) }
                    }
                }
            }
        } |> deliverOnMainQueue).start(next: { [weak self] activities in
            guard let self else { return }
            let previous = self.activities
            self.activities = activities
            if let content = self.content {
                let parentId = content.parentPeer.peerId
                guard previous.filter({ $0.key.peerId == parentId }) != activities.filter({ $0.key.peerId == parentId }) else { return }
                self.update(items: content.items, selectedThreadId: content.selectedThreadId, kind: content.kind, parentPeer: content.parentPeer)
            }
        }))
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layout() {
        super.layout()
        tableView.frame = bounds
        searchController?.view.frame = bounds
        selectionBar.frame = NSMakeRect(0, max(0, bounds.height - 60), bounds.width, 60)
        let width = max(0, (bounds.width - 24) / 3)
        for (index, button) in [readButton, muteButton, deleteButton].enumerated() {
            button.frame = NSMakeRect(12 + CGFloat(index) * width, 8, width, 44)
        }
    }

    deinit {
        searchLoading.dispose()
        inputActivities.dispose()
    }

    public func setSelecting(_ selecting: Bool) {
        guard !selecting || (kind == .forum && !context.isFrozen) else { return }
        selection.setActive(selecting)
        selectionBar.isHidden = !selecting
        if let content { update(items: content.items, selectedThreadId: content.selectedThreadId, kind: content.kind, parentPeer: content.parentPeer) }
        selectionChanged?(selecting)
    }

    private var selectedRows: [ChatListRowItem] {
        tableView.allItems.compactMap { $0 as? ChatListRowItem }.filter { row in row.mode.threadId.map { selection.selectedIds.contains($0) } == true }
    }

    private enum SelectionAction { case read, mute, delete }

    private func applySelection(_ action: SelectionAction) {
        guard let content, !context.isFrozen else { return }
        let rows = selectedRows
        guard !rows.isEmpty else { return }
        let ids = rows.compactMap { $0.mode.threadId }
        let peerId = content.parentPeer.peerId
        switch action {
        case .read:
            for id in ids { ChatListRowItem.markTopicAsRead(context: context, peerId: peerId, threadId: id) }
        case .mute:
            let unmute = rows.allSatisfy { $0.isMuted }
            for id in ids { _ = context.engine.peers.updatePeerMuteSetting(peerId: peerId, threadId: id, muteInterval: unmute ? 0 : Int32.max).start() }
        case .delete:
            guard rows.allSatisfy({ $0.canDeleteTopic }) else { return }
            verifyAlert(for: context.window, header: strings().forumSidebarRowsViewDeleteTopics, information: strings().forumSidebarRowsViewDeleteTopicsInfoOther(ids.count), ok: strings().chatListContextDelete, successHandler: { [weak self] _ in
                guard let self, !self.context.isFrozen else { return }
                let current = self.selectedRows
                guard Set(current.compactMap { $0.mode.threadId }) == Set(ids), current.allSatisfy({ $0.canDeleteTopic }) else { return }
                _ = self.context.engine.peers.removeForumChannelThreads(id: peerId, threadIds: ids).start()
                self.setSelecting(false)
            })
            return
        }
        setSelecting(false)
    }

    private func updateSelectionActions() {
        let rows = selectedRows
        readButton.isEnabled = !rows.isEmpty
        muteButton.isEnabled = !rows.isEmpty
        deleteButton.isEnabled = !rows.isEmpty && rows.allSatisfy { $0.canDeleteTopic }
        muteButton.set(text: !rows.isEmpty && rows.allSatisfy({ $0.isMuted }) ? strings().chatListSwipingUnmute : strings().chatListSwipingMute, for: .Normal)
    }

    public func selectSearchResult() {
        guard let controller = searchController, let item = controller.genericView.highlightedItem() else { return }
        _ = controller.genericView.select(item: item)
    }

    public func search(query: String?, peerId: PeerId, loadingUpdated: @escaping (Bool) -> Void) {
        tableView.isHidden = query != nil
        if query == nil || searchPeerId != peerId {
            if let controller = searchController {
                controller.viewWillDisappear(false)
                controller.view.removeFromSuperview()
                controller.viewDidDisappear(false)
            }
            searchController = nil
            searchPeerId = nil
            searchLoading.set(nil)
            loadingUpdated(false)
        }
        guard let query else { return }
        if searchController == nil {
            let controller = SearchController<Context>(context: context, open: { [weak self] id, messageId, _ in
                guard let self, let id, case let .chatId(itemId, _, _) = id else { return }
                switch itemId {
                case let .forum(threadId):
                    self.onSelect(threadId, messageId)
                case .chatList where self.kind.usesSourceChats:
                    if case let .chatList(sourcePeerId) = itemId {
                        self.onSelect(sourcePeerId.toInt64(), messageId)
                    }
                default:
                    break
                }
            }, options: [.chats, .messages], frame: bounds, target: kind.usesSourceChats ? .savedMessages(peerId) : .forum(peerId))
            controller.navigationController = context.bindings.rootNavigation()
            controller.view.frame = bounds
            controller.genericView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: tableView.contentInsets.bottom, right: 0)
            controller.viewWillAppear(false)
            addSubview(controller.view)
            controller.viewDidAppear(false)
            searchController = controller
            searchPeerId = peerId
            searchLoading.set((controller.isLoading.get() |> deliverOnMainQueue).start(next: loadingUpdated))
        }
        searchController?.request(with: query)
    }

    public func update(items: [EngineChatList.Item], selectedThreadId: Int64?, kind: ChatSidebarKind, parentPeer: EngineRenderedPeer) {
        if self.kind != kind { selection.setActive(false); selectionBar.isHidden = true; selectionChanged?(false) }
        self.kind = kind
        selection.retain(Set(items.compactMap { item in if case let .forum(id) = item.id { return id }; return nil }))
        self.content = (items, selectedThreadId, kind, parentPeer)
        let canCreate = kind.showsNewTopic && (parentPeer.peer?._asPeer() as? TelegramChannel)?.hasPermission(.createTopics) == true
        tableView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: canCreate || selection.isActive ? 88 : 0, right: 0)
        let previousOffset = tableView.clipView.bounds.origin
        tableView.removeAll()
        var rows: [(Int, TableRowItem)] = []
        var selectedRow: ChatListRowItem?
        let messages = items.flatMap(\.messages).sorted { $0.index > $1.index }.prefix(1).map { $0._asMessage() }
        let root = SidebarRootRowItem(NSMakeSize(max(bounds.width, 320), 70), context: context, stableId: .chatId(.chatList(parentPeer.peerId), parentPeer.peerId, -1), mode: .chat, messages: messages, renderedPeer: parentPeer, titleOverride: kind != .channelMessages ? localizedString("Chat.Sidebar.AllMessages") : nil)
        root.isForumSidebarRow = true
        rows.append((0, root))
        rootRowId = root.stableId
        if selectedThreadId == nil { selectedRow = root }
        for item in items {
            let threadId: Int64
            let mode: ChatListRowItem.Mode
            if kind.usesSourceChats {
                threadId = item.renderedPeer.peerId.toInt64()
                mode = .savedMessages(threadId)
            } else {
                guard case let .forum(id) = item.id, let threadData = item.threadData else { continue }
                threadId = id
                mode = .topic(id, threadData)
            }
            let space = PeerActivitySpace(peerId: parentPeer.peerId, category: .thread(threadId))
            let row = ChatListRowItem(NSMakeSize(max(bounds.width, 320), 70), context: context, stableId: .chatId(item.id, item.renderedPeer.peerId, -1), mode: mode, messages: item.messages.map { $0._asMessage() }, index: item.chatListIndex, readState: item.readCounters, draft: item.draft, pinnedType: item.chatListIndex.pinningIndex == nil ? .none : .some, renderedPeer: item.renderedPeer, peerPresence: item.presence, forumTopicData: item.forumTopicData, forumTopicItems: item.topForumTopicItems, activities: activities[space] ?? [], isMuted: item.isMuted, hasFailed: item.hasFailed, hasUnreadMentions: item.hasUnseenMentions, hasUnreadReactions: item.hasUnseenReactions, hasUnreadVotes: item.hasUnseenPollVotes, story: item.storyStats, isContact: item.isContact, titleOverride: kind == .channelMessages ? item.renderedPeer.peer?._asPeer().displayTitle : nil, savedMessagesParentPeerId: kind.usesSourceChats ? parentPeer.peerId : nil)
            row.isForumSidebarRow = true
            row.sidebarSelection = selection.isActive ? selection.selectedIds.contains(threadId) : nil
            rows.append((rows.count, row))
            if threadId == selectedThreadId {
                selectedRow = row
            }
        }
        tableView.merge(with: TableUpdateTransition(deleted: [], inserted: rows, updated: [], animated: false), appearAnimated: false)
        if let selectedRow, !selection.isActive {
            _ = tableView.select(item: selectedRow, notify: false)
        }
        tableView.clipView.scroll(to: previousOffset, animated: false)
        updateSelectionActions()
    }

    public func selectionDidChange(row: Int, item: TableRowItem, byClick: Bool, isNew: Bool) {
        if item.stableId == rootRowId {
            onSelect(nil, nil)
        } else if let item = item as? ChatListRowItem, let threadId = item.mode.threadId {
            onSelect(threadId, nil)
        }
    }

    public func selectionWillChange(row: Int, item: TableRowItem, byClick: Bool) -> Bool {
        if selection.isActive {
            guard let row = item as? ChatListRowItem, let id = row.mode.threadId else { return false }
            selection.toggle(id)
            if let content { update(items: content.items, selectedThreadId: content.selectedThreadId, kind: content.kind, parentPeer: content.parentPeer) }
            return false
        }
        return item is ChatListRowItem
    }

    public func isSelectable(row: Int, item: TableRowItem) -> Bool {
        item is ChatListRowItem && (!selection.isActive || item.stableId != rootRowId)
    }
}
