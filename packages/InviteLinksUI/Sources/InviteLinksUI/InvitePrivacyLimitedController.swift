import Cocoa
import SwiftSignalKit
import TGUIKit
import TelegramCore
import Postbox
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import FoundationUtils
import AlertsUI
import InAppSettings
import AvatarUI
import ShortPeerRow
import AppAnalytics

private final class UpgradeToPremiumRowItem : GeneralRowItem {
    public let headerLayout: TextViewLayout
    public let textLayout: TextViewLayout
    public let context: any AccountContextProtocol
    public let premiumRestrictedUsers: [TelegramForbiddenInvitePeer]
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, premiumRestrictedUsers: [TelegramForbiddenInvitePeer], context: any AccountContextProtocol, viewType: GeneralViewType, action:@escaping()->Void) {
        self.premiumRestrictedUsers = premiumRestrictedUsers
        self.context = context
        
        
        self.headerLayout = .init(.initialize(string: strings().inviteFailedPremiumTitle, color: theme.colors.text, font: .medium(18)), maximumNumberOfLines: 1, alignment: .center)
    
        let text: String
        if premiumRestrictedUsers.count == 1 {
            text = strings().inviteFailedPremiumTextSingle(premiumRestrictedUsers[0].peer._asPeer().compactDisplayTitle)
        } else {
            let extraCount = premiumRestrictedUsers.count - 3

            var peersText = ""
            for i in 0 ..< min(3, premiumRestrictedUsers.count) {
                if extraCount == 0 && i == premiumRestrictedUsers.count - 1 {
                    peersText.append(", ")
                } else if i != 0 {
                    peersText.append(", ")
                }
                peersText.append("**")
                peersText.append(premiumRestrictedUsers[i].peer._asPeer().compactDisplayTitle)
                peersText.append("**")
            }
            
            if extraCount >= 1 {
                text = strings().inviteFailedPremiumTextMultipleAndOther(peersText, extraCount)
            } else {
                text = strings().inviteFailedPremiumTextMultiple(peersText)
            }

        }
        
        self.textLayout = .init(.initialize(string: text, color: theme.colors.text, font: .normal(.text)).detectBold(with: .medium(.text)), alignment: .center)
        
        super.init(initialSize, stableId: stableId, viewType: viewType, action: action)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        headerLayout.measure(width: width - 40)
        textLayout.measure(width: width - 40)
        
        return true
    }
    
    public override var height: CGFloat {
        return 50 + 10 + headerLayout.layoutSize.height + 2 + textLayout.layoutSize.height + 10 + 40 + 40
    }

    public override var accessibilityLabel: String? {
        return headerLayout.attributedString.string
    }

    public override var accessibilityValue: String? {
        return textLayout.attributedString.string
    }
    
    public override func viewClass() -> AnyClass {
        return UpgradeToPremiumRowView.self
    }
}

private final class UpgradeToPremiumRowView : GeneralContainableRowView {
    private let headerView = TextView()
    private let textView = TextView()
    private let action = TextButton()
    private let separatorView = SeparatorView(frame: .zero, text: strings().premiumShowStatusOr)
    
    private var avatars:[AvatarContentView] = []
    private let avatarsContainer = View(frame: NSMakeRect(0, 0, 30 * 3, 30))
    
    private var peers:[Avatar] = []

    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        headerView.userInteractionEnabled = false
        headerView.isSelectable = false
        
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        
        addSubview(headerView)
        addSubview(textView)
        addSubview(separatorView)
        
        addSubview(action)
        action.scaleOnClick = true
        action.autohighlight = false
        
        action.set(handler: { [weak self] _ in
            if let item = self?.item as? GeneralRowItem {
                item.action()
            }
        }, for: .Click)
        
        addSubview(avatarsContainer)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public override func layout() {
        super.layout()
        var avatarRect = containerView.focus(avatarsContainer.subviewsWidthSize)
        avatarRect.origin.y = 0
        self.avatarsContainer.frame = avatarRect

        headerView.centerX(y: 60)
        textView.centerX(y: headerView.frame.maxY + 2)
        
        action.centerX(y: textView.frame.maxY + 10)
        separatorView.frame = NSMakeRect(0, action.frame.maxY, containerView.frame.width, 40)

    }
    
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? UpgradeToPremiumRowItem else {
            return
        }
        
        headerView.update(item.headerLayout)
        textView.update(item.textLayout)
        
        action.set(text: strings().inviteFailedPremiumAction, for: .Normal)
        action.set(background: premiumGradient[1], for: .Normal)
        action.set(color: theme.colors.underSelectedColor, for:.Normal)
        action.set(font: .medium(.text), for: .Normal)
        action.sizeToFit(.zero, NSMakeSize(frame.width - 40, 40), thatFit: true)
        action.layer?.cornerRadius = action.frame.height / 2
        
        
        
        
        
        let peers:[Avatar] = item.premiumRestrictedUsers.prefix(3).reduce([], { current, value in
            var current = current
            current.append(.init(peer: value.peer._asPeer(), index: current.count))
            return current
        })
                
        let photoSize = NSMakeSize(50, 50)

        applyAvatarStack(peers, current: &self.peers, avatars: &avatars, avatarsContainer: avatarsContainer, photoSize: photoSize, animated: animated, makeControl: { avatar in
            AvatarContentView(context: item.context, peer: avatar.peer, message: nil, synchronousLoad: false, size: photoSize, inset: 15)
        })
        
        
    }
}

private final class InviteViaLinkHeaderItem : GeneralRowItem {
    public let textLayout: TextViewLayout
    public init(_ initialSize: NSSize, peers: [Peer], cantInvite: Bool, stableId: AnyHashable, viewType: GeneralViewType) {
        
        let text: String
        if cantInvite {
            if peers.count == 1 {
                text = strings().inviteFailedTextCantSingle(peers[0].compactDisplayTitle)
            } else {
                text = strings().inviteFailedTextCantMultipleOther(peers.count)
            }
        } else {
            if peers.count == 1 {
                text = strings().inviteFailedTextSingle(peers[0].compactDisplayTitle)
            } else {
                text = strings().inviteFailedTextMultipleOther(peers.count)
            }
        }
        
        
        self.textLayout = .init(.initialize(string: text, color: theme.colors.listGrayText, font: .normal(.text)), alignment: .center)
        
        super.init(initialSize, stableId: stableId, viewType: viewType)
        
        _ = makeSize(initialSize.width)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        self.textLayout.measure(width: blockWidth - viewType.innerInset.left - viewType.innerInset.right - 40)
        
        return true
    }
    
    public override var height: CGFloat {
        return 40 + 10 + self.textLayout.layoutSize.height + viewType.innerInset.top + viewType.innerInset.bottom
    }

    public override var accessibilityLabel: String? {
        return textLayout.attributedString.string
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }
    
    public override func viewClass() -> AnyClass {
        return InviteViaLinkHeaderView.self
    }
}

private final class InviteViaLinkHeaderView : GeneralContainableRowView {
    private let textView = TextView()
    private let button = ImageButton()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        addSubview(button)
        
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        
        button.userInteractionEnabled = false
        button.isAccessibilityDecorative = true
    }
    
    public override func layout() {
        super.layout()
        
        button.layer?.cornerRadius = button.frame.height / 2
        button.centerX(y: 0)
        textView.centerX(y: button.frame.maxY + 10)
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? InviteViaLinkHeaderItem else {
            return
        }
        textView.update(item.textLayout)
        
        button.autohighlight = false
        button.set(image: TelegramThemeHooks.shared.image(.iconExportedInvitationLink).precomposed(theme.colors.underSelectedColor), for: .Normal)
        button.set(background: theme.colors.accent, for: .Normal)
        button.sizeToFit(.zero, NSMakeSize(60, 40), thatFit: true)
        
        needsLayout = true
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


private final class Arguments {
    public let context: any AccountContextProtocol
    public let select: SelectPeerInteraction
    public let openPremium:()->Void
    public init(context: any AccountContextProtocol, select: SelectPeerInteraction, openPremium:@escaping()->Void) {
        self.context = context
        self.select = select
        self.openPremium = openPremium
    }
}

private struct State : Equatable {
    public let peerId: PeerId
    public let peers: [PeerEquatable]
    public var peer: PeerEquatable?
    public var cachedData: CachedDataEquatable?
    
    public var forbidden: [TelegramForbiddenInvitePeer]
    
    public var canInvite: Bool {
        var link: String?
        if let data = self.cachedData?.data as? CachedGroupData {
            link = data.exportedInvitation?.link
        } else if let data = self.cachedData?.data as? CachedChannelData {
            link = data.exportedInvitation?.link
        }
        return link != nil
    }
    public var canInviteAnyone: Bool {
        if canInvite {
            if !forbidden.isEmpty {
                for forbidden in forbidden {
                    if !forbidden.premiumRequiredToContact {
                        return true
                    }
                }
                return false
            } else {
                return true
            }
        } else {
            return false
        }
    }
}

private let _id_header = InputDataIdentifier("_id_header")

private let _id_premium = InputDataIdentifier("_id_premium")

private func _id_peer(_ id: PeerId) -> InputDataIdentifier {
    return InputDataIdentifier("_id_peer_\(id.toInt64())")
}
private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
//    entries.append(.sectionId(sectionId, type: .customModern(10)))
//    sectionId += 1
    
    
    let premiumRestrictedUsers = state.forbidden.filter { peer in
        return peer.canInviteWithPremium
    }
    
    if !premiumRestrictedUsers.isEmpty, !arguments.context.isPremium {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_premium, equatable: InputDataEquatable(state), comparable: nil, item: { initialSize, stableId in
            return UpgradeToPremiumRowItem(initialSize, stableId: stableId, premiumRestrictedUsers: premiumRestrictedUsers, context: arguments.context, viewType: .legacy, action: arguments.openPremium)
        }))
        index += 1
    }
    
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: InputDataEquatable(state), comparable: nil, item: { initialSize, stableId in
        return InviteViaLinkHeaderItem(initialSize, peers: state.peers.map { $0.peer }, cantInvite: !state.canInvite, stableId: stableId, viewType: .legacy)
    }))
    index += 1
  
    // entries
    
    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1
    
    struct Tuple : Equatable {
        let peer: PeerEquatable
        let selected: Bool
        let viewType: GeneralViewType
        let selectable: Bool
    }
    
    var items: [Tuple] = []
    
    for (i, peer) in state.peers.enumerated() {
        let value = state.forbidden.first(where: { $0.peer.id == peer.id })?.premiumRequiredToContact
        let canInvite = value == nil || value == false

        items.append(.init(peer: peer, selected: arguments.select.presentation.selected.contains(peer.peer.id), viewType: bestGeneralViewType(state.peers, for: i), selectable: state.canInvite && canInvite))
    }
    
    for item in items {
        
        let interactionType: ShortPeerItemInteractionType
        if item.selectable {
            interactionType = .selectable(arguments.select, side: .right)
        } else {
            interactionType = .plain
        }
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_peer(item.peer.peer.id), equatable: .init(item), comparable: nil, item: { initialSize, stableId in
            return ShortPeerRowItem(initialSize, peer: item.peer.peer, account: arguments.context.account, context: arguments.context, inset: NSEdgeInsets(left: 20, right: 20), interactionType: interactionType, viewType: item.viewType)
        }))
        index += 1
    }
    
    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1
    
    
    return entries
}

public func InvitePrivacyLimitedController(context: any AccountContextProtocol, peerId: PeerId, peers:[Peer], forbidden: [TelegramForbiddenInvitePeer] = []) -> InputDataModalController {
    
    let peers: [PeerEquatable] = peers.compactMap { $0 }.map { .init($0) }

    let actionsDisposable = DisposableSet()
    var close:(()->Void)? = nil
    
    let initialState = State(peerId: peerId, peers: peers, forbidden: forbidden)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    let selected = SelectPeerInteraction()
    
    
    for peer in peers {
        let value = forbidden.first(where: { $0.peer.id == peer.id })?.premiumRequiredToContact
        let canInvite = value == nil || value == false
        if canInvite {
            selected.toggleSelection(peer.peer)
        }
    }

    let arguments = Arguments(context: context, select: selected, openPremium: {
        FeatureNavigationHooks.shared.showPremiumBoarding(context, context.window, nil, false, nil)
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
   
    let controller = InputDataController(dataSignal: signal, title: strings().inviteFailedTitle)
    controller.analyticsScreen = .peerInfoInviteRestricted
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    
    let data = combineLatest(queue: .mainQueue(), getPeerView(peerId: peerId, postbox: context.account.postbox), getCachedDataView(peerId: peerId, postbox: context.account.postbox))

    actionsDisposable.add(data.start(next: { peer, cachedData in
        updateState { current in
            var current = current
            current.peer = .init(peer)
            current.cachedData = .init(cachedData)
            return current
        }
    }))
    
   
    controller.validateData = { _ in
                
        return .fail(.doSomething(next: { f in
            let state = stateValue.with { $0 }
            if state.canInvite {
                let data = state.cachedData?.data
                let peer = state.peer?.peer

                var link: String?
                if let data = data as? CachedGroupData {
                    link = data.exportedInvitation?.link
                } else if let data = data as? CachedChannelData {
                    link = data.exportedInvitation?.link
                }
                
                if link == nil, let addressName = peer?.addressName {
                    link = context.meUrlPrefix + "\(addressName)"
                }
                if let link = link {
                    let combine = peers.filter { value in
                        return selected.presentation.selected.contains(value.peerId) && forbidden.allSatisfy { !$0.premiumRequiredToContact || $0.peer.id != value.peerId }
                    }.map {
                        return enqueueMessages(account: context.account, peerId: $0.peer.id, messages: [EnqueueMessage.message(text: link, attributes: [], inlineStickers: [:], mediaReference: nil, threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])])
                    }
                    _ = combineLatest(combine).start()
                    if state.canInviteAnyone {
                        delay(0.2, closure: {
                            _ = showModalSuccess(for: context.window, icon: theme.icons.successModalProgress, delay: 0.3).start()
                        })
                    }
                }
            }
        
            close?()
            f(.none)
        }))
        
    }
    
    let modalInteractions = ModalInteractions(acceptTitle: strings().inviteFailedOK, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)
    
    controller.afterTransaction = { [weak modalInteractions] controller in
        if let modalInteractions = modalInteractions {
            modalInteractions.updateDone({ button in
                button.set(text: stateValue.with { $0.canInviteAnyone } ? strings().inviteFailedOK : strings().modalOK, for: .Normal)
            })
        }
    }
    arguments.select.singleUpdater = { [weak modalInteractions] updated in
        modalInteractions?.updateDone { title in
            if stateValue.with({ $0.canInvite }) {
                title.set(text: updated.selected.isEmpty ? strings().inviteFailedSkip : strings().inviteFailedOK, for: .Normal)
            } else {
                title.set(text: strings().modalOK, for: .Normal)
            }
        }
    }
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    close = { [weak modalController] in
        modalController?.close()
    }

    return modalController
}




public func showInvitePrivacyLimitedController(context: any AccountContextProtocol, peerId: PeerId, ids:[PeerId], forbidden: [TelegramForbiddenInvitePeer] = []) {
    let peers:Signal<[Peer], NoError> = context.account.postbox.transaction { transaction in
        var peers: [Peer?] = []
        for id in ids {
            peers.append(transaction.getPeer(id))
        }
        return peers.compactMap { $0 }
    } |> deliverOnMainQueue
    
    _ = peers.start(next: { peers in
        showModal(with: InvitePrivacyLimitedController(context: context, peerId: peerId, peers: peers, forbidden: forbidden), for: context.window)
    })
    
}
