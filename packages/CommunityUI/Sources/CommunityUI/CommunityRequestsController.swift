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

private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let addRequest: (CommunityPeerRequest) -> Void
    public let declineRequest: (CommunityPeerRequest) -> Void
    public let openChat: (CommunityPeerRequest) -> Void
    public let addAll: () -> Void
    public let declineAll: () -> Void
    public let goBack: () -> Void
    public init(
        context: (any AccountContextProtocol),
        addRequest: @escaping (CommunityPeerRequest) -> Void,
        declineRequest: @escaping (CommunityPeerRequest) -> Void,
        openChat: @escaping (CommunityPeerRequest) -> Void,
        addAll: @escaping () -> Void,
        declineAll: @escaping () -> Void,
        goBack: @escaping () -> Void
    ) {
        self.context = context
        self.addRequest = addRequest
        self.declineRequest = declineRequest
        self.openChat = openChat
        self.addAll = addAll
        self.declineAll = declineAll
        self.goBack = goBack
    }
}

private struct State: Equatable {
    public var requests: [CommunityPeerRequest]?
    public var peers: [PeerId: EnginePeer] = [:]
    public var memberCounts: [PeerId: Int32] = [:]
    public var community: TelegramCommunity? = nil

    public static func == (lhs: State, rhs: State) -> Bool {
        if lhs.requests != rhs.requests { return false }
        if lhs.peers != rhs.peers { return false }
        if lhs.memberCounts != rhs.memberCounts { return false }
        if lhs.community?.id != rhs.community?.id { return false }
        if lhs.community?.title != rhs.community?.title { return false }
        if lhs.community?.defaultBannedRights != rhs.community?.defaultBannedRights { return false }
        return true
    }
}

private let _id_banner = InputDataIdentifier("_id_banner")
private let _id_loading = InputDataIdentifier("_id_loading")
private let _id_empty = InputDataIdentifier("_id_empty")
private let _id_header = InputDataIdentifier("_id_header")
private let _id_add_all = InputDataIdentifier("_id_add_all")
private let _id_decline_all = InputDataIdentifier("_id_decline_all")

private func _id_request(_ peerId: PeerId) -> InputDataIdentifier {
    return InputDataIdentifier("_id_request_\(peerId.toInt64())")
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1

    if state.community?.defaultBannedRights?.flags.contains(.banManageLinkedPeers) == true {
        entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(strings().communityRequestsApprovalInfo, linkHandler: { key in
            if key == "settings" {
                arguments.goBack()
            }
        }), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
        entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1
    }

    guard let requests = state.requests else {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().communityRequestsLoading), data: .init(color: theme.colors.listGrayText, viewType: .singleItem)))
        index += 1
        entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1
        return entries
    }

    if requests.isEmpty {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().communityRequestsEmpty), data: .init(color: theme.colors.listGrayText, viewType: .singleItem)))
        index += 1
        entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1
        return entries
    }

    let n = requests.count
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().communityRequestsSuggestedHeaderOther(n)), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    for (i, request) in requests.enumerated() {
        let viewType = bestGeneralViewType(requests, for: i)
        let chatPeer = state.peers[request.peerId]
        let requesterPeer = state.peers[request.requestedBy]
        let memberCount = state.memberCounts[request.peerId]
        let equatableData = "\(request.peerId)\(request.requestedBy)\(memberCount as Any)"
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_request(request.peerId), equatable: InputDataEquatable(equatableData), comparable: nil, item: { initialSize, stableId in
            return CommunityRequestRowItem(
                initialSize,
                stableId: stableId,
                context: arguments.context,
                request: request,
                chatPeer: chatPeer,
                requesterPeer: requesterPeer,
                memberCount: memberCount,
                viewType: viewType,
                add: { arguments.addRequest(request) },
                decline: { arguments.declineRequest(request) },
                openChat: { arguments.openChat(request) }
            )
        }))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1
    return entries
}

public func CommunityRequestsController(_ context: (any AccountContextProtocol), communityId: PeerId, openSettings: (() -> Void)? = nil) -> InputDataModalController {
    let actionsDisposable = DisposableSet()
    let initialState = State()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in statePromise.set(stateValue.modify(f)) }

    let requestsContext = context.engine.peers.communityPeerLinkRequestsContext(communityId: communityId)
    let memberCountsDisposable = MetaDisposable()
    actionsDisposable.add(memberCountsDisposable)

    var close: (() -> Void)? = nil

    let arguments = Arguments(
        context: context,
        addRequest: { request in
            requestsContext.update(request, action: .approve)
        },
        declineRequest: { request in
            requestsContext.update(request, action: .deny)
        },
        openChat: { request in
            // A private (invite-only) suggested group can't be previewed → show the invite-only modal whose
            // only action is to message whoever suggested it; a visible one opens directly.
            if request.isVisible == false {
                let chat = stateValue.with { $0.peers[request.peerId] }?._asPeer()
                let owner = stateValue.with { $0.peers[request.requestedBy] }?._asPeer()
                let memberCount = stateValue.with { $0.memberCounts[request.peerId] }
                showModal(with: CommunityPrivateChatController(context: context, chatPeer: chat, requestedBy: owner, memberCount: memberCount, messageOwner: {
                    close?()
                    CommunityHooks.shared.openChat(context, request.requestedBy)
                }), for: context.window)
            } else {
                close?()
                CommunityHooks.shared.openChat(context, request.peerId)
            }
        },
        addAll: {
            verifyAlert(for: context.window, information: strings().communityRequestsAddAllConfirm, successHandler: { _ in
                requestsContext.updateAll(action: .approve)
            })
        },
        declineAll: {
            verifyAlert(for: context.window, information: strings().communityRequestsDeclineAllConfirm, successHandler: { _ in
                requestsContext.updateAll(action: .deny)
            })
        },
        goBack: {
            close?()
            openSettings?()
        }
    )

    actionsDisposable.add(context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: communityId)).start(next: { peer in
        var community: TelegramCommunity? = nil
        if case let .community(c) = peer { community = c }
        updateState { var s = $0; s.community = community; return s }
    }))

    actionsDisposable.add((requestsContext.state |> deliverOnMainQueue).start(next: { requestsState in
        updateState { var s = $0
            s.requests = requestsState.hasLoadedOnce ? requestsState.requests : nil
            s.peers = requestsState.peers
            return s
        }
    }))

    actionsDisposable.add((requestsContext.state
        |> map { Set($0.requests.map { $0.peerId }) }
        |> distinctUntilChanged
        |> deliverOnMainQueue).start(next: { peerIdSet in
            if peerIdSet.isEmpty {
                memberCountsDisposable.set(nil)
                return
            }
            let peerIds = Array(peerIdSet)
            for id in peerIds {
                context.account.viewTracker.forceUpdateCachedPeerData(peerId: id)
            }
            memberCountsDisposable.set(context.engine.data.subscribe(EngineDataMap(peerIds.map { TelegramEngine.EngineData.Item.Peer.CachedData(id: $0) })).start(next: { cachedMap in
                var counts: [PeerId: Int32] = [:]
                for id in peerIds {
                    let cached: CachedPeerData? = cachedMap[id] ?? nil
                    if let c = cached as? CachedChannelData, let mc = c.participantsSummary.memberCount { counts[id] = mc }
                    else if let c = cached as? CachedGroupData, let p = c.participants { counts[id] = Int32(p.participants.count) }
                }
                updateState { var s = $0; s.memberCounts = counts; return s }
            }))
        }))

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().communityRequestsPendingRequests, removeAfterDisappear: false, hasDone: false)
    controller.analyticsScreen = .communityRequests

    // Page in more pending requests as the list scrolls to the bottom (mirrors iOS).
    controller.didLoad = { controller, _ in
        controller.tableView.setScrollHandler { position in
            switch position.direction {
            case .bottom:
                requestsContext.loadMore()
            default:
                break
            }
        }
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().communityRequestsAddAll, accept: {
        arguments.addAll()
    }, cancelTitle: strings().communityRequestsDeclineAll, cancel: {
        arguments.declineAll()
    })
    modalInteractions.glassButtons = true
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(360, 500))
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    controller.centerModalHeader = ModalHeaderData(title: strings().communityRequestsPendingRequests)
    close = { [weak modalController] in modalController?.close() }
    controller.onDeinit = { actionsDisposable.dispose() }
    return modalController
}

public final class CommunityRequestRowItem: GeneralRowItem {
    public let context: (any AccountContextProtocol)
    public let request: CommunityPeerRequest
    public let chatPeer: EnginePeer?
    public let requesterPeer: EnginePeer?
    public let memberCount: Int32?
    public let add: () -> Void
    public let decline: () -> Void

    public let line1Layout: TextViewLayout
    public let line2Layout: TextViewLayout
    public let line3Layout: TextViewLayout?

    public init(
        _ initialSize: NSSize,
        stableId: AnyHashable,
        context: (any AccountContextProtocol),
        request: CommunityPeerRequest,
        chatPeer: EnginePeer?,
        requesterPeer: EnginePeer?,
        memberCount: Int32?,
        viewType: GeneralViewType,
        add: @escaping () -> Void,
        decline: @escaping () -> Void,
        openChat: @escaping () -> Void
    ) {
        self.context = context
        self.request = request
        self.chatPeer = chatPeer
        self.requesterPeer = requesterPeer
        self.memberCount = memberCount
        self.add = add
        self.decline = decline

        let requesterName = requesterPeer?._asPeer().compactDisplayTitle ?? strings().communityRequestsSomeone
        let line1Attr = NSMutableAttributedString()
        let nameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.medium(.text),
            .foregroundColor: theme.colors.accent
        ]
        let suffixAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.normal(.text),
            .foregroundColor: theme.colors.grayText
        ]
        line1Attr.append(NSAttributedString(string: requesterName, attributes: nameAttrs))
        line1Attr.append(NSAttributedString(string: strings().communityRequestsSuggestsGroupSuffix, attributes: suffixAttrs))
        line1Layout = TextViewLayout(line1Attr, maximumNumberOfLines: 1)

        let chatTitle = chatPeer?._asPeer().displayTitle ?? strings().communityRequestsUnknown
        line2Layout = TextViewLayout(.initialize(string: chatTitle, color: theme.colors.text, font: .medium(.text)), maximumNumberOfLines: 1)

        if let count = memberCount, count > 0 {
            let membersStr = strings().communityRequestsMembersCountOther(Int(count))
            var line3Str = membersStr
            if request.isVisible == false {
                line3Str += strings().communityRequestsVisibleOnlyToMembersSuffix
            }
            line3Layout = TextViewLayout(.initialize(string: line3Str, color: theme.colors.grayText, font: .normal(.short)), maximumNumberOfLines: 1)
        } else if request.isVisible == false {
            line3Layout = TextViewLayout(.initialize(string: strings().communityRequestsVisibleOnlyToMembers, color: theme.colors.grayText, font: .normal(.short)), maximumNumberOfLines: 1)
        } else {
            line3Layout = nil
        }

        super.init(initialSize, stableId: stableId, viewType: viewType, action: openChat)
    }

    public override var accessibilityLabel: String? {
        return line2Layout.attributedString.string
    }

    public override var accessibilityValue: String? {
        return [line1Layout.attributedString.string, line3Layout?.attributedString.string].compactMap { $0 }.joined(separator: ", ")
    }

    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        let avatarW: CGFloat = 40
        let inset = viewType.innerInset.left
        let textW = blockWidth - inset - avatarW - 10 - inset
        line1Layout.measure(width: textW)
        line2Layout.measure(width: textW)
        line3Layout?.measure(width: textW)
        return result
    }

    public override var height: CGFloat {
        var textH = line1Layout.layoutSize.height + 2 + line2Layout.layoutSize.height
        if let l3 = line3Layout {
            textH += 2 + l3.layoutSize.height
        }
        let buttonH: CGFloat = 24
        return 10 + textH + 8 + buttonH + 10
    }

    public override func viewClass() -> AnyClass { return CommunityRequestRowView.self }
}

public final class CommunityRequestRowView: GeneralContainableRowView {
    private let avatar = AvatarControl(font: .avatar(14))
    private let line1View = TextView()
    private let line2View = TextView()
    private let line3View = TextView()
    private var addButton: TextButton?
    private var declineButton: TextButton?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        avatar.setFrameSize(NSMakeSize(40, 40))
        avatar.userInteractionEnabled = false

        line1View.userInteractionEnabled = false
        line1View.isSelectable = false
        line2View.userInteractionEnabled = false
        line2View.isSelectable = false
        line3View.userInteractionEnabled = false
        line3View.isSelectable = false

        addSubview(avatar)
        addSubview(line1View)
        addSubview(line2View)
        addSubview(line3View)

        // Tapping the row (outside the Add/Decline buttons) opens/previews the chat — for a private group
        // this surfaces the invite-only modal (item.action == openChat).
        containerView.set(handler: { [weak self] _ in
            (self?.item as? GeneralRowItem)?.action()
        }, for: .Click)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? CommunityRequestRowItem else { return }

        avatar.setPeer(account: item.context.account, peer: item.chatPeer?._asPeer())
        line1View.update(item.line1Layout)
        line2View.update(item.line2Layout)

        if let l3 = item.line3Layout {
            line3View.update(l3)
            line3View.isHidden = false
        } else {
            line3View.isHidden = true
        }

        let addCurrent: TextButton
        if let existing = addButton {
            addCurrent = existing
        } else {
            addCurrent = TextButton()
            addCurrent.scaleOnClick = true
            addSubview(addCurrent)
            addButton = addCurrent
            addCurrent.set(handler: { [weak self] _ in
                (self?.item as? CommunityRequestRowItem)?.add()
            }, for: .Click)
        }
        addCurrent.set(font: .medium(.text), for: .Normal)
        addCurrent.set(color: theme.colors.underSelectedColor, for: .Normal)
        addCurrent.set(background: theme.colors.accent, for: .Normal)
        addCurrent.set(text: strings().communityRequestsAdd, for: .Normal)
        addCurrent.sizeToFit(NSMakeSize(10, 6))
        addCurrent.layer?.cornerRadius = addCurrent.frame.height / 2

        let declineCurrent: TextButton
        if let existing = declineButton {
            declineCurrent = existing
        } else {
            declineCurrent = TextButton()
            declineCurrent.scaleOnClick = true
            addSubview(declineCurrent)
            declineButton = declineCurrent
            declineCurrent.set(handler: { [weak self] _ in
                (self?.item as? CommunityRequestRowItem)?.decline()
            }, for: .Click)
        }
        declineCurrent.set(font: .medium(.text), for: .Normal)
        declineCurrent.set(color: theme.colors.text, for: .Normal)
        declineCurrent.set(background: theme.colors.grayBackground, for: .Normal)
        declineCurrent.set(text: strings().communityRequestsDecline, for: .Normal)
        declineCurrent.sizeToFit(NSMakeSize(10, 6))
        declineCurrent.layer?.cornerRadius = declineCurrent.frame.height / 2

        needsLayout = true
    }

    public override func layout() {
        super.layout()
        guard let item = item as? CommunityRequestRowItem else { return }

        let inset = item.viewType.innerInset.left
        avatar.setFrameOrigin(NSMakePoint(inset, 10))
        let textX = avatar.frame.maxX + 10

        var y: CGFloat = 10
        line1View.setFrameOrigin(NSMakePoint(textX, y))
        y = line1View.frame.maxY + 2
        line2View.setFrameOrigin(NSMakePoint(textX, y))
        y = line2View.frame.maxY + 2
        if !line3View.isHidden {
            line3View.setFrameOrigin(NSMakePoint(textX, y))
            y = line3View.frame.maxY + 2
        }
        y += 6

        if let dec = declineButton {
            dec.setFrameOrigin(NSMakePoint(textX, y))
            if let add = addButton {
                add.setFrameOrigin(NSMakePoint(dec.frame.maxX + 8, y))
            }
        }
    }
}
