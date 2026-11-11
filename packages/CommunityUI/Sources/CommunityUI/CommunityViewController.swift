import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import DateUtils
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import ShortPeerRow
import AvatarUI
import TelegramMediaUtils
import AlertsUI
import LocalAnimations
import MessageTextUtils
import AppAnalytics

private enum CommunitySection {
    case joined
    case visible
    case requestable
}

private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let openPeer: (PeerId) -> Void
    public let openApp: (EnginePeer) -> Void
    public let openEdit: () -> Void
    public let openRequests: () -> Void
    public let toggleCollapsed: () -> Void
    public let removeFromCommunity: (PeerId) -> Void
    public let toggleMute: (PeerId, Bool) -> Void
    public let toggleVisible: (PeerId, Bool) -> Void
    public init(context: (any AccountContextProtocol), openPeer: @escaping (PeerId) -> Void, openApp: @escaping (EnginePeer) -> Void, openEdit: @escaping () -> Void, openRequests: @escaping () -> Void, toggleCollapsed: @escaping () -> Void, removeFromCommunity: @escaping (PeerId) -> Void, toggleMute: @escaping (PeerId, Bool) -> Void, toggleVisible: @escaping (PeerId, Bool) -> Void) {
        self.context = context
        self.openPeer = openPeer
        self.openApp = openApp
        self.openEdit = openEdit
        self.openRequests = openRequests
        self.toggleCollapsed = toggleCollapsed
        self.removeFromCommunity = removeFromCommunity
        self.toggleMute = toggleMute
        self.toggleVisible = toggleVisible
    }
}

private struct ChildPreview: Equatable {
    public var messages: [Message]
    public var readCounters: EnginePeerReadCounters

    public static func == (lhs: ChildPreview, rhs: ChildPreview) -> Bool {
        if lhs.readCounters != rhs.readCounters { return false }
        if lhs.messages.count != rhs.messages.count { return false }
        for (l, r) in zip(lhs.messages, rhs.messages) {
            if l.id != r.id || l.stableVersion != r.stableVersion { return false }
        }
        return true
    }
}

private struct ChildEntry: Equatable {
    public let peer: EnginePeer
    public let preview: ChildPreview?
    public let hidden: Bool
}

private struct State: Equatable {
    public var community: TelegramCommunity?
    public var cachedData: CachedCommunityData?
    public var peers: [PeerId: EnginePeer] = [:]
    public var memberCounts: [PeerId: Int32] = [:]
    public var previews: [PeerId: ChildPreview] = [:]
    public var isAdmin: Bool { return community?.hasPermission(.manageLinkedPeers) == true }

    public static func == (lhs: State, rhs: State) -> Bool {
        if lhs.community != rhs.community { return false }
        if lhs.cachedData?.linkedPeers != rhs.cachedData?.linkedPeers { return false }
        if lhs.peers != rhs.peers { return false }
        if lhs.memberCounts != rhs.memberCounts { return false }
        if lhs.previews != rhs.previews { return false }
        return true
    }
}

private func _id_peer(_ id: PeerId) -> InputDataIdentifier {
    return InputDataIdentifier("_id_view_peer_\(id.toInt64())")
}

private func botHasMiniApp(_ peer: EnginePeer) -> Bool {
    if case let .user(user) = peer, user.botInfo?.flags.contains(.hasWebApp) == true {
        return true
    }
    return false
}
private let _id_collapse = InputDataIdentifier("_id_collapse")
private let _id_edit = InputDataIdentifier("_id_edit")
private let _id_requests = InputDataIdentifier("_id_requests")

private func bucket(_ peer: EnginePeer, canViewHistory: Bool, botHasPreview: Bool) -> CommunitySection {
    if case let .channel(channel) = peer, case .member = channel.participationStatus {
        return .joined
    }
    // Bots aren't joinable chats (mirrors iOS): with a preview they read as "you are in", otherwise
    // they fall into the requestable bucket — never the plain "you can join" list.
    if case let .user(user) = peer, user.botInfo != nil {
        return botHasPreview ? .joined : .requestable
    }
    // `communityPeer.can_view_history` (layer 228): the history is readable right now without joining.
    // Public chats stay visible as a fallback for stale caches that predate the flag.
    if canViewHistory || peer.addressName != nil {
        return .visible
    }
    return .requestable
}

private func communityChildPreviewSignal(context: (any AccountContextProtocol), peerId: PeerId) -> Signal<(PeerId, ChildPreview), NoError> {
    var ignoredNamespaces = Set<Int32>()
    ignoredNamespaces = ignoredNamespaces.union(Namespaces.Message.allNonRegular)
    ignoredNamespaces = ignoredNamespaces.union(Namespaces.Message.allEphemeral)
    return combineLatest(
        context.account.postbox.aroundMessageHistoryViewForLocation(.peer(peerId: peerId, threadId: nil), anchor: .upperBound, ignoreMessagesInTimestampRange: nil, ignoreMessageIds: Set(), count: 10, clipHoles: false, fixedCombinedReadStates: nil, topTaggedMessageIdNamespaces: Set(), tag: nil, appendMessagesFromTheSameGroup: false, namespaces: .not(ignoredNamespaces), orderStatistics: []),
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Messages.PeerReadCounters(id: peerId))
    ) |> map { viewData, readCounters -> (PeerId, ChildPreview) in
        let (view, _, _) = viewData
        var messages: [Message] = []
        for i in (0 ..< view.entries.count).reversed() {
            if messages.isEmpty {
                messages.append(view.entries[i].message)
            } else if messages[0].groupingKey != nil && messages[0].groupingKey == view.entries[i].message.groupingKey {
                messages.append(view.entries[i].message)
            }
        }
        messages = messages.reversed()
        return (peerId, ChildPreview(messages: messages, readCounters: readCounters))
    }
}

private final class CommunityChatRowItem: GeneralRowItem {
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let peer: EnginePeer
    fileprivate let hidden: Bool
    fileprivate let titleLayout: TextViewLayout
    fileprivate let messageLayout: TextViewLayout?
    fileprivate let dateLayout: TextViewLayout?
    fileprivate let badgeNode: BadgeNode?
    fileprivate let openAction: () -> Void
    fileprivate let canRemove: Bool
    fileprivate let isMuted: Bool
    fileprivate let removeAction: (() -> Void)?
    fileprivate let muteAction: (() -> Void)?
    fileprivate let visibleAction: (() -> Void)?
    fileprivate let openAppAction: (() -> Void)?
    fileprivate let openAppLayout: TextViewLayout?

    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), peer: EnginePeer, messages: [Message], readState: EnginePeerReadCounters?, hidden: Bool, viewType: GeneralViewType, canRemove: Bool = false, isMuted: Bool = false, action: @escaping () -> Void, removeAction: (() -> Void)? = nil, muteAction: (() -> Void)? = nil, visibleAction: (() -> Void)? = nil, openAppAction: (() -> Void)? = nil) {
        self.context = context
        self.peer = peer
        self.hidden = hidden
        self.openAction = action
        self.canRemove = canRemove
        self.isMuted = isMuted
        self.removeAction = removeAction
        self.muteAction = muteAction
        self.visibleAction = visibleAction
        self.openAppAction = openAppAction
        if openAppAction != nil {
            let layout = TextViewLayout(.initialize(string: strings().chatListOpenMiniApp, color: theme.colors.accent, font: .medium(.short)))
            layout.measure(width: .greatestFiniteMagnitude)
            self.openAppLayout = layout
        } else {
            self.openAppLayout = nil
        }

        let title = NSMutableAttributedString()
        _ = title.append(string: peer._asPeer().displayTitle, color: theme.colors.text, font: .medium(.title))
        self.titleLayout = TextViewLayout(title, maximumNumberOfLines: 1)

        let topMessage = messages.first(where: { !$0.text.isEmpty }) ?? messages.first
        if let topMessage = topMessage {
            let attr = chatListText(account: context.account, for: topMessage, messagesCount: messages.count, renderedPeer: EngineRenderedPeer(peer: peer), isPremium: context.isPremium)
            if !attr.trimmed.string.isEmpty {
                self.messageLayout = TextViewLayout(attr.trimmed, maximumNumberOfLines: 1)
            } else {
                self.messageLayout = nil
            }
        } else {
            self.messageLayout = nil
        }

        if let topMessage = messages.first {
            var time: TimeInterval = TimeInterval(topMessage.timestamp)
            time -= context.timeDifference
            let date = NSMutableAttributedString()
            _ = date.append(string: DateUtils.string(forMessageListDate: Int32(time)), color: theme.colors.grayText, font: .normal(.short))
            self.dateLayout = TextViewLayout(date, maximumNumberOfLines: 1)
        } else {
            self.dateLayout = nil
        }

        if let unreadCount = readState?.count, unreadCount > 0 {
            let isMuted = readState?.isMuted ?? false
            self.badgeNode = BadgeNode(.initialize(string: "\(unreadCount)", color: theme.chatList.badgeTextColor, font: .medium(.small)), isMuted ? theme.chatList.badgeMutedBackgroundColor : theme.chatList.badgeBackgroundColor)
        } else if readState?.markedUnread == true {
            self.badgeNode = BadgeNode(.initialize(string: " ", color: theme.chatList.badgeTextColor, font: .medium(.small)), theme.chatList.badgeBackgroundColor)
        } else {
            self.badgeNode = nil
        }

        super.init(initialSize, height: 64, stableId: stableId, viewType: viewType, inset: NSEdgeInsets(left: 20, right: 20))
    }

    public override var accessibilityLabel: String? {
        return titleLayout.attributedString.string
    }

    public override var accessibilityValue: String? {
        var parts: [String] = []
        if let messageLayout {
            parts.append(messageLayout.attributedString.string)
        }
        if let dateLayout {
            parts.append(dateLayout.attributedString.string)
        }
        if isMuted {
            parts.append(strings().voiceOverCommonMuted)
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        let textX: CGFloat = 10 + 44 + 10
        let rightPad: CGFloat = 12
        let appButtonW: CGFloat = openAppLayout != nil ? (openAppLayout!.layoutSize.width + 20 + 8) : 0
        dateLayout?.measure(width: .greatestFiniteMagnitude)
        let dateW = openAppLayout != nil ? 0 : (dateLayout?.layoutSize.width ?? 0)
        titleLayout.measure(width: max(20, blockWidth - textX - rightPad - dateW - appButtonW - 6))
        let badgeW = badgeNode?.size.width ?? 0
        messageLayout?.measure(width: max(20, blockWidth - textX - rightPad - badgeW - appButtonW - 6))
        return true
    }

    public override func viewClass() -> AnyClass {
        return CommunityChatRowView.self
    }

    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        var items: [ContextMenuItem] = []
        if let openAppAction = self.openAppAction {
            items.append(.init(strings().chatListOpenMiniApp, handler: openAppAction, itemImage: MenuAnimation.menu_folder_bot.value))
        }
        if let muteAction = self.muteAction {
            items.append(.init(isMuted ? strings().communityViewUnmute : strings().communityViewMute, handler: muteAction, itemImage: isMuted ? MenuAnimation.menu_unmuted.value : MenuAnimation.menu_mute.value))
        }
        if canRemove, let visibleAction = self.visibleAction {
            items.append(.init(hidden ? strings().communityViewShowChat : strings().communityViewHideChat, handler: visibleAction, itemImage: hidden ? MenuAnimation.menu_eye.value : MenuAnimation.menu_eye_slash.value))
        }
        if canRemove, let removeAction = self.removeAction {
            items.append(.init(strings().communityViewRemoveFromCommunity, handler: removeAction, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
        }
        return .single(items)
    }
}

private final class CommunityChatRowView: GeneralContainableRowView {
    private let titleView = TextView()
    private let messageView = InteractiveTextView()
    private let dateView = TextView()
    private var avatar: AvatarControl?
    private var badgeView: View?
    private var hiddenView: ImageView?
    private var appButton: TextButton?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for view in [titleView, dateView] {
            view.userInteractionEnabled = false
            view.isSelectable = false
            addSubview(view)
        }
        messageView.userInteractionEnabled = false
        addSubview(messageView)
        containerView.scaleOnClick = true
        containerView.set(handler: { [weak self] _ in
            if let item = self?.item as? CommunityChatRowItem {
                item.openAction()
            }
        }, for: .Click)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var additionBorderInset: CGFloat {
        return 44 + 6
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? CommunityChatRowItem else { return }

        let avatar: AvatarControl
        if let current = self.avatar {
            avatar = current
        } else {
            avatar = AvatarControl(font: .avatar(20.0))
            avatar.userInteractionEnabled = false
            avatar.setFrameSize(NSMakeSize(44, 44))
            self.avatar = avatar
            addSubview(avatar)
        }
        avatar.setPeer(account: item.context.account, peer: item.peer._asPeer())

        if item.hidden {
            let current: ImageView
            if let view = self.hiddenView {
                current = view
            } else {
                current = ImageView()
                current.isEventLess = true
                current.isAccessibilityDecorative = true
                self.hiddenView = current
                addSubview(current)
            }
            current.image = generateCommunityHiddenIcon(backgroundColor: theme.colors.background, iconColor: theme.colors.grayIcon)
            current.sizeToFit()
        } else if let view = self.hiddenView {
            performSubviewRemoval(view, animated: false)
            self.hiddenView = nil
        }

        titleView.update(item.titleLayout)
        messageView.set(text: item.messageLayout, context: item.context)
        messageView.isHidden = item.messageLayout == nil
        dateView.update(item.dateLayout)
        dateView.isHidden = item.dateLayout == nil || item.openAppAction != nil

        if let openAppAction = item.openAppAction, let layout = item.openAppLayout {
            let current: TextButton
            if let view = self.appButton {
                current = view
            } else {
                current = TextButton()
                current.scaleOnClick = true
                current.autohighlight = false
                self.appButton = current
                addSubview(current)
            }
            current.set(font: .medium(.short), for: .Normal)
            current.set(color: theme.colors.accent, for: .Normal)
            current.set(background: theme.colors.accent.withAlphaComponent(0.1), for: .Normal)
            current.set(text: strings().chatListOpenMiniApp, for: .Normal)
            current.setFrameSize(NSMakeSize(layout.layoutSize.width + 20, 24))
            current.layer?.cornerRadius = 12
            current.removeAllHandlers()
            current.set(handler: { _ in
                openAppAction()
            }, for: .Click)
        } else if let view = self.appButton {
            performSubviewRemoval(view, animated: false)
            self.appButton = nil
        }

        if let badgeNode = item.badgeNode {
            let current: View
            if let view = self.badgeView {
                current = view
            } else {
                current = View()
                current.userInteractionEnabled = false
                self.badgeView = current
                addSubview(current)
            }
            current.setFrameSize(badgeNode.size)
            badgeNode.view = current
            badgeNode.setNeedDisplay()
        } else if let view = self.badgeView {
            performSubviewRemoval(view, animated: false)
            self.badgeView = nil
        }
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        guard item is CommunityChatRowItem else { return }
        avatar?.centerY(x: 10)
        if let hiddenView = hiddenView, let avatar = avatar {
            hiddenView.setFrameOrigin(NSMakePoint(avatar.frame.maxX - hiddenView.frame.width + 2, avatar.frame.maxY - hiddenView.frame.height + 2))
        }
        let textX: CGFloat = 10 + 44 + 10
        titleView.setFrameOrigin(NSMakePoint(textX, 12))
        if !dateView.isHidden {
            dateView.setFrameOrigin(NSMakePoint(containerView.frame.width - dateView.frame.width - 12, 13))
        }
        let messageY = titleView.frame.maxY + 3
        if !messageView.isHidden {
            messageView.setFrameOrigin(NSMakePoint(textX, messageY))
        }
        if let appButton = appButton {
            appButton.centerY(x: containerView.frame.width - appButton.frame.width - 12)
        }
        if let badgeView = badgeView {
            let rightEdge: CGFloat
            if let appButton = appButton {
                rightEdge = appButton.frame.minX - 8
            } else {
                rightEdge = containerView.frame.width - 12
            }
            let badgeY = messageView.isHidden ? (containerView.frame.height - badgeView.frame.height - 12) : (messageY + (messageView.frame.height - badgeView.frame.height) / 2)
            badgeView.setFrameOrigin(NSMakePoint(rightEdge - badgeView.frame.width, badgeY))
        }
    }
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1

    if let community = state.community {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_collapse, data: .init(name: strings().communityViewShowAsOneChat, color: theme.colors.text, type: .switchable(community.collapsedInDialogs == true), viewType: .singleItem, action: {
            arguments.toggleCollapsed()
        })))
        index += 1
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().communityViewShowAsOneChatInfo), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1

        if state.isAdmin {
            entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1
            let pending = state.cachedData?.pendingRequests ?? 0
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_edit, data: .init(name: strings().communityViewEditCommunity, color: theme.colors.text, type: .next, viewType: pending > 0 ? .firstItem : .singleItem, action: {
                arguments.openEdit()
            })))
            index += 1
            if pending > 0 {
                entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_requests, data: .init(name: strings().communityViewPendingRequests, color: theme.colors.text, type: .badge("\(pending)", theme.colors.accent), viewType: .lastItem, action: {
                    arguments.openRequests()
                })))
                index += 1
            }
        }
        entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1
    }

    guard let cachedData = state.cachedData else {
        return entries
    }
    let resolved: [EnginePeer] = cachedData.linkedPeers.compactMap { state.peers[$0.peerId] }
    var hiddenById: [PeerId: Bool] = [:]
    var canViewHistoryById: [PeerId: Bool] = [:]
    for linkedPeer in cachedData.linkedPeers {
        hiddenById[linkedPeer.peerId] = (linkedPeer.visible == false)
        canViewHistoryById[linkedPeer.peerId] = linkedPeer.canViewHistory
    }

    func appendSection(_ section: CommunitySection, _ title: String) {
        var rows = resolved.filter { bucket($0, canViewHistory: canViewHistoryById[$0.id] ?? false, botHasPreview: state.previews[$0.id]?.messages.isEmpty == false) == section }
        if rows.isEmpty { return }
        if section != .requestable {
            rows = rows.sorted { lhs, rhs in
                let lhsTimestamp = state.previews[lhs.id]?.messages.first?.timestamp ?? 0
                let rhsTimestamp = state.previews[rhs.id]?.messages.first?.timestamp ?? 0
                return lhsTimestamp > rhsTimestamp
            }
        }
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(title), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
        for (i, peer) in rows.enumerated() {
            if section == .requestable {
                let viewType = bestGeneralViewType(rows, for: i)
                let status: String?
                if let count = state.memberCounts[peer.id], count > 0 {
                    status = strings().communityViewMembersOther(Int(count))
                } else {
                    status = nil
                }
                var customAction: ShortPeerRowItem.CustomAction? = nil
                if botHasMiniApp(peer) {
                    customAction = .init(title: strings().chatListOpenMiniApp, callback: {
                        arguments.openApp(peer)
                    })
                }
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_peer(peer.id), equatable: InputDataEquatable(peer), comparable: nil, item: { initialSize, stableId in
                    return ShortPeerRowItem(initialSize, peer: peer._asPeer(), account: arguments.context.account, context: arguments.context, stableId: stableId, status: status, inset: NSEdgeInsets(left: 20, right: 20), generalType: customAction != nil ? .none : .next, viewType: viewType, action: {
                        arguments.openPeer(peer.id)
                    }, customAction: customAction)
                }))
                index += 1
            } else {
                let preview = state.previews[peer.id]
                let viewType = bestGeneralViewType(rows, for: i)
                let hidden = hiddenById[peer.id] ?? false
                let isMuted = preview?.readCounters.isMuted ?? false
                let canRemove = state.isAdmin
                let canMute = section == .joined
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_peer(peer.id), equatable: InputDataEquatable(ChildEntry(peer: peer, preview: preview, hidden: hidden)), comparable: nil, item: { initialSize, stableId in
                    return CommunityChatRowItem(initialSize, stableId: stableId, context: arguments.context, peer: peer, messages: preview?.messages ?? [], readState: preview?.readCounters, hidden: hidden, viewType: viewType, canRemove: canRemove, isMuted: isMuted, action: {
                        arguments.openPeer(peer.id)
                    }, removeAction: canRemove ? {
                        arguments.removeFromCommunity(peer.id)
                    } : nil, muteAction: canMute ? {
                        arguments.toggleMute(peer.id, isMuted)
                    } : nil, visibleAction: canRemove ? {
                        arguments.toggleVisible(peer.id, hidden)
                    } : nil, openAppAction: botHasMiniApp(peer) ? {
                        arguments.openApp(peer)
                    } : nil)
                }))
                index += 1
            }
        }
        entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1
    }

    appendSection(.joined, strings().communityViewSectionChatsYouAreIn)
    appendSection(.visible, strings().communityViewSectionChatsYouCanJoin)
    appendSection(.requestable, strings().communityViewSectionChatsYouCanRequestToJoin)

    return entries
}

public func CommunityViewController(_ context: (any AccountContextProtocol), communityId: PeerId, canAddChats: Bool) -> InputDataModalController {
    let actionsDisposable = DisposableSet()
    let initialState = State()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in statePromise.set(stateValue.modify(f)) }

    var close: (() -> Void)? = nil

    let arguments = Arguments(context: context, openPeer: { peerId in
        close?()
        CommunityHooks.shared.openChat(context, peerId)
    }, openApp: { peer in
        close?()
        CommunityHooks.shared.openMainApp(context, peer)
    }, openEdit: {
        close?()
        CommunityHooks.shared.openCommunityEdit(context, communityId)
    }, openRequests: {
        showModal(with: CommunityRequestsController(context, communityId: communityId, openSettings: {
            close?()
            CommunityHooks.shared.openCommunityEdit(context, communityId)
        }), for: context.window)
    }, toggleCollapsed: {
        let current = stateValue.with { $0.community?.collapsedInDialogs == true }
        actionsDisposable.add((context.engine.peers.toggleCommunityCollapsedInDialogs(communityId: communityId, collapsed: !current) |> deliverOnMainQueue).start(error: { _ in
            alert(for: context.window, info: strings().communityViewSomethingWentWrong)
        }))
    }, removeFromCommunity: { peerId in
        verifyAlert(for: context.window, information: strings().communityViewRemoveChatConfirm, ok: strings().communityViewRemove, successHandler: { _ in
            actionsDisposable.add((context.engine.peers.toggleCommunityPeerLink(communityId: communityId, peerId: peerId, action: .unlink) |> deliverOnMainQueue).start(error: { _ in
                alert(for: context.window, info: strings().communityViewSomethingWentWrong)
            }))
        })
    }, toggleMute: { peerId, _ in
        actionsDisposable.add(context.engine.peers.togglePeerMuted(peerId: peerId, threadId: nil).startStandalone())
    }, toggleVisible: { peerId, newVisible in
        // Re-link the chat with the new visibility flag (does not unlink) — mirrors iOS's hide/show.
        actionsDisposable.add((context.engine.peers.toggleCommunityPeerLink(communityId: communityId, peerId: peerId, action: .link(visible: newVisible)) |> deliverOnMainQueue).start(error: { _ in
            alert(for: context.window, info: strings().communityViewSomethingWentWrong)
        }))
    })

    actionsDisposable.add(combineLatest(
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: communityId)),
        context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.CachedData(id: communityId))
    ).start(next: { peer, cachedData in
        var community: TelegramCommunity? = nil
        if case let .community(value) = peer { community = value }
        updateState { var c = $0; c.community = community; c.cachedData = cachedData as? CachedCommunityData; return c }
    }))
    context.account.viewTracker.forceUpdateCachedPeerData(peerId: communityId)

    let linkedPeerIds = statePromise.get()
        |> map { ($0.cachedData?.linkedPeers ?? []).map { $0.peerId } }
        |> distinctUntilChanged
    actionsDisposable.add(linkedPeerIds.start(next: { ids in
        for id in ids { context.account.viewTracker.forceUpdateCachedPeerData(peerId: id) }
    }))
    let peersSignal = linkedPeerIds |> mapToSignal { ids -> Signal<([PeerId: EnginePeer], [PeerId: Int32]), NoError> in
        if ids.isEmpty { return .single(([:], [:])) }
        return combineLatest(
            context.engine.data.subscribe(EngineDataMap(ids.map { TelegramEngine.EngineData.Item.Peer.Peer(id: $0) })),
            context.engine.data.subscribe(EngineDataMap(ids.map { TelegramEngine.EngineData.Item.Peer.CachedData(id: $0) }))
        ) |> map { peers, cachedDatas in
            var peerMap: [PeerId: EnginePeer] = [:]
            var counts: [PeerId: Int32] = [:]
            for id in ids {
                if let maybePeer = peers[id], let peer = maybePeer { peerMap[id] = peer }
                let cached: CachedPeerData? = cachedDatas[id] ?? nil
                if let c = cached as? CachedChannelData, let memberCount = c.participantsSummary.memberCount { counts[id] = memberCount }
                else if let c = cached as? CachedGroupData, let p = c.participants { counts[id] = Int32(p.participants.count) }
            }
            return (peerMap, counts)
        }
    }
    actionsDisposable.add(peersSignal.start(next: { peers, counts in
        updateState { var c = $0; c.peers = peers; c.memberCounts = counts; return c }
    }))

    let previewsSignal = linkedPeerIds |> mapToSignal { ids -> Signal<[PeerId: ChildPreview], NoError> in
        if ids.isEmpty { return .single([:]) }
        return combineLatest(ids.map { communityChildPreviewSignal(context: context, peerId: $0) })
        |> map { values -> [PeerId: ChildPreview] in
            var result: [PeerId: ChildPreview] = [:]
            for (peerId, preview) in values { result[peerId] = preview }
            return result
        }
    }
    actionsDisposable.add(previewsSignal.start(next: { previews in
        updateState { var c = $0; c.previews = previews; return c }
    }))

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().communityViewTitle, removeAfterDisappear: false, hasDone: false)
    controller.analyticsScreen = .community
    controller.getTitle = { return stateValue.with { $0.community?.title } ?? strings().communityViewTitle }
    controller.onDeinit = { actionsDisposable.dispose() }

    let bottomAction: () -> Void = {
        let excluded = stateValue.with { ($0.cachedData?.linkedPeers ?? []).map { $0.peerId } }
        actionsDisposable.add(CommunityHooks.shared.selectChatToAdd(context, strings().communityViewAddChatToCommunity, excluded).start(next: { peerIds in
            guard let peerId = peerIds.first else { return }
            showModal(with: CommunityAddController(context, communityId: communityId, peerId: peerId, completed: {
                context.account.viewTracker.forceUpdateCachedPeerData(peerId: communityId)
            }), for: context.window)
        }))
    }

    // Only members allowed to add chats get the bottom bar at all — without the right,
    // the modal is built without any interactions so no button (or empty bar) is shown.
    let modalInteractions: ModalInteractions? = canAddChats ? ModalInteractions(acceptTitle: strings().communityViewAddChatToCommunity, accept: {
        bottomAction()
    }, singleButton: true) : nil

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(360, 500))

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })

    close = { [weak modalController] in modalController?.close() }
    return modalController
}

public func showCommunityView(_ context: (any AccountContextProtocol), communityId: PeerId) {
    let signal = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: communityId)) |> deliverOnMainQueue
    _ = signal.start(next: { peer in
        var canAddChats = false
        if case let .community(community) = peer {
            if community.hasPermission(.manageLinkedPeers) {
                canAddChats = true
            } else {
                canAddChats = community.defaultBannedRights?.flags.contains(.banManageLinkedPeers) != true
            }
        }
        showModal(with: CommunityViewController(context, communityId: communityId, canAddChats: canAddChats), for: context.window)
    })
}
