import Foundation
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import Localization
import TelegramTheme
import TelegramIconsTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AlertsUI
import AvatarUI
import ShortPeerRow
import AppAnalytics

private struct Option : Equatable {
    class Function : Equatable {
        let callback: ()->Void
        let toggle: ()->Void
        init(callback:@escaping()->Void, toggle: @escaping()->Void) {
            self.callback = callback
            self.toggle = toggle
        }
        static func == (lhs: Function, rhs: Function) -> Bool {
            return true
        }
    }

    var text: String
    var selected: Bool
    var revealed: Bool
    var peerSelected: Set<PeerId>?
    var count: Int?
    var totalCount: Int?
    var viewType: GeneralViewType
    let stableId: InputDataIdentifier
    var callback: Function
}

private class RowItem : GeneralRowItem {
    let context: any AccountContextProtocol
    let option: Option
    let name: TextViewLayout
    let revealText: TextViewLayout?
    init(_ initialSize: NSSize, context: any AccountContextProtocol, option: Option) {
        self.context = context
        self.option = option
        self.name = .init(.initialize(string: option.text, color: theme.colors.text, font: .normal(.text)))

        if let selected = option.count {
            let attr = NSMutableAttributedString()
            if let total = option.totalCount {
                attr.append(string: "\(selected)/\(total)", color: theme.colors.text, font: .medium(.text))
            } else {
                attr.append(.embedded(name: "Icon_Reply_Group", color: theme.colors.text, resize: false))
                attr.append(string: " \(selected)", color: theme.colors.text, font: .normal(.text))
            }
            self.revealText = .init(attr)
            self.revealText?.measure(width: .greatestFiniteMagnitude)
        } else {
            self.revealText = nil
        }
        super.init(initialSize, height: 40, stableId: option.stableId, viewType: option.viewType)
    }
    
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        self.name.measure(width: width - 60)
        return true
    }
    
    override func viewClass() -> AnyClass {
        return RowView.self
    }

    override var accessibilityLabel: String? {
        return option.text
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .checkBox
    }

    override var accessibilityToggleState: Bool? {
        return option.selected
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    override func accessibilityPerformPress() -> Bool {
        option.callback.callback()
        return true
    }

    override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        guard revealText != nil else {
            return nil
        }
        let callback = option.callback
        return [NSAccessibilityCustomAction(name: option.revealed ? strings().voiceOverCommonCollapse : strings().voiceOverCommonExpand, handler: {
            callback.toggle()
            return true
        })]
    }
}

private final class RowView: GeneralContainableRowView {
    private let selectingControl = SelectingControl(unselectedImage: theme.icons.chatToggleUnselected, selectedImage: theme.icons.chatToggleSelected)
    private let textView = TextView()
    private var countView: InteractiveTextView?
    private var chevron: ImageView?
    private let action = Control()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(selectingControl)
        addSubview(textView)
        
        addSubview(action)
        
        selectingControl.userInteractionEnabled = true
        
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        
        containerView.set(handler: { [weak self] _ in
            guard let item = self?.item as? RowItem else {
                return
            }
            item.option.callback.callback()

        }, for: .Click)
        
        action.set(handler: { [weak self] _ in
            guard let item = self?.item as? RowItem else {
                return
            }
            item.option.callback.toggle()

        }, for: .Click)
        action.setAccessibilityLabel(strings().voiceOverCommonExpand)
        
        selectingControl.set(handler: { [weak self] _ in
            guard let item = self?.item as? RowItem else {
                return
            }
            item.option.callback.callback()
        }, for: .Click)
        
    }
    
    override var additionBorderInset: CGFloat {
        return 30
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        selectingControl.centerY(x: 10)
        textView.centerY(x: selectingControl.frame.maxX + 10)

        action.centerY(x: containerView.frame.width - action.frame.width - 14)

        let gap: CGFloat = 6
        var x: CGFloat = 0
        if let countView {
            countView.centerY(x: x)
            x += countView.frame.width
            if chevron != nil {
                x += gap
            }
        }
        if let chevron {
            chevron.centerY(x: x)
        }
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? RowItem else {
            return
        }
        
        if let revealText = item.revealText {
            let current: InteractiveTextView
            if let view = self.countView {
                current = view
            } else {
                current = InteractiveTextView(frame: .zero)
                self.countView = current
                action.addSubview(current)
            }
            current.userInteractionEnabled = false
            current.set(text: revealText, context: item.context)
        } else if let view = self.countView {
            performSubviewRemoval(view, animated: animated)
            self.countView = nil
        }
        
        if item.option.peerSelected != nil || item.option.totalCount != nil {
            let current: ImageView
            if let view = self.chevron {
                current = view
            } else {
                current = ImageView(frame: .zero)
                current.isAccessibilityDecorative = true
                self.chevron = current
                action.addSubview(current)
            }
            current.isEventLess = true
            current.animates = animated
            current.image = TelegramThemeHooks.shared.image((item.option.revealed ? .iconSmallChevronUp : .iconSmallChevronDown)).precomposed(theme.colors.text)
            current.sizeToFit()
        } else if let view = self.chevron {
            performSubviewRemoval(view, animated: animated)
            self.chevron = nil
        }
        
        let gap: CGFloat = 6
        var actionWidth: CGFloat = 0
        var actionHeight: CGFloat = 0
        if let countView {
            actionWidth += countView.frame.width
            actionHeight = max(actionHeight, countView.frame.height)
        }
        if let chevron {
            if actionWidth > 0 {
                actionWidth += gap
            }
            actionWidth += chevron.frame.width
            actionHeight = max(actionHeight, chevron.frame.height)
        }
        action.setFrameSize(NSSize(width: actionWidth, height: actionHeight))
        action.scaleOnClick = true
        
        selectingControl.set(selected: item.option.selected, animated: animated)
        
        textView.update(item.name)
        needsLayout = true
    }
}

private final class Arguments {
    let context: any AccountContextProtocol
    let toggleBan:(String)->Void
    let toggleRight: (TelegramChatBannedRightsFlags, Bool) -> Void
    let toggleMedia: ()->Void
    let toggleReveal:(InputDataIdentifier)->Void
    let toggleSelected:(InputDataIdentifier)->Void
    let togglePeerSelected:(PeerId, InputDataIdentifier)->Void
    let toggleBanFromCommunity:()->Void
    init(context: any AccountContextProtocol, toggleBan:@escaping(String)->Void, toggleRight: @escaping(TelegramChatBannedRightsFlags, Bool) -> Void, toggleMedia: @escaping()->Void, toggleReveal:@escaping(InputDataIdentifier)->Void, toggleSelected:@escaping(InputDataIdentifier)->Void, togglePeerSelected:@escaping(PeerId, InputDataIdentifier)->Void, toggleBanFromCommunity:@escaping()->Void) {
        self.context = context
        self.toggleBan = toggleBan
        self.toggleRight = toggleRight
        self.toggleMedia = toggleMedia
        self.toggleReveal = toggleReveal
        self.toggleSelected = toggleSelected
        self.togglePeerSelected = togglePeerSelected
        self.toggleBanFromCommunity = toggleBanFromCommunity
    }
}


private struct State : Equatable {
    var channel: TelegramChannel
    var messages: [Message]
    var allPeers:Set<PeerId>
    var reactionAuthor: PeerId?
    var banFully: Bool = true
    var updatedFlags: TelegramChatBannedRightsFlags?
    var mediaRevealed: Bool = false

    var spamRevealed: Bool = false
    var banRevealed: Bool = false
    var deleteRevealed: Bool = false

    var spamSelected: Bool = false
    var banSelected: Bool = false
    var deleteSelected: Bool = false
    var deleteReactionsSelected: Bool = false
    var deleteListSelected: Bool = true

    var spamPeerSelected: Set<PeerId> = Set()
    var banPeerSelected: Set<PeerId> = Set()
    var deletePeerSelected: Set<PeerId> = Set()
    var deleteReactionsPeerSelected: Set<PeerId> = Set()

    var communityId: PeerId? = nil
    var communityChatCount: Int = 0
    var communityBanAvailable: Bool = false
    var banFromCommunity: Bool = false
    var communityCreatorChatIds: [PeerId] = []
    var communityChatPeers: [PeerId: EnginePeer] = [:]
    var communityChatCounts: [PeerId: Int32] = [:]

    var isEmpty: Bool {
        return !spamSelected && !banSelected && !deleteSelected && !deleteReactionsSelected && !deleteListSelected && !banFromCommunity
    }
    
    var text: String {
        if spamSelected, !banSelected && !deleteSelected && !deleteReactionsSelected && !deleteListSelected {
            return strings().supergroupDeleteRestrictionReport
        } else if banSelected, !spamSelected && !deleteSelected && !deleteReactionsSelected && !deleteListSelected {
            return banFully ? strings().supergroupDeleteRestrictionBan : strings().supergroupDeleteRestrictionRestrict
        } else if deleteSelected || deleteReactionsSelected || deleteListSelected, !spamSelected && !banSelected {
            return strings().supergroupDeleteRestrictionDelete
        } else {
            return strings().supergroupDeleteRestrictionProceed
        }
    }

}

private let _id_report = InputDataIdentifier("_id_report")
private let _id_ban = InputDataIdentifier("_id_ban")
private let _id_ban_community = InputDataIdentifier("_id_ban_community")
private let _id_delete_all = InputDataIdentifier("_id_delete_all")
private let _id_delete_all_sub_messages = InputDataIdentifier("_id_delete_all_sub_messages")
private let _id_delete_reactions = InputDataIdentifier("_id_delete_reactions")
private let _id_delete = InputDataIdentifier("_id_delete")
private func _id_peer(_ id: PeerId, _ section: InputDataIdentifier) -> InputDataIdentifier {
    return .init("_id_peer_\(id.toInt64())_\(section.identifier)")
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
    
//    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().supergroupDeleteRestrictionHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
//    index += 1
    
    var options: [Option] = []
    
    let firstOptionText: String
    if state.reactionAuthor != nil {
        firstOptionText = strings().deleteGroupMessagesDeleteReaction
    } else {
        firstOptionText = state.messages.count == 1 ? strings().supergroupDeleteRestrictionDeleteMessage : strings().supergroupDeleteRestrictionDeleteMessageMulti
    }
    options.append(.init(text: firstOptionText, selected: state.deleteListSelected || state.deleteSelected, revealed: false, viewType: .firstItem, stableId: _id_delete, callback: .init(callback: {
        arguments.toggleSelected(_id_delete)
    }, toggle: { })))
    
    options.append(.init(text: strings().supergroupDeleteRestrictionReportSpam, selected: state.spamSelected, revealed: state.spamRevealed, viewType: .innerItem, stableId: _id_report, callback: .init(callback: {
        arguments.toggleSelected(_id_report)
    }, toggle: { })))
    

    let canDeleteReactions = state.channel.hasPermission(.deleteAllMessages)
    let useSubOptions = canDeleteReactions && state.allPeers.count == 1
    let deleteAllIsLast = !state.channel.hasPermission(.banMembers)

    let singlePeerTitle: String? = {
        guard let peerId = state.allPeers.first else { return nil }
        for message in state.messages {
            if let peer = message.peers[peerId] ?? (message.author?.id == peerId ? message.author : nil) ?? (message.effectiveAuthor?.id == peerId ? message.effectiveAuthor : nil) {
                return peer.compactDisplayTitle
            }
        }
        return nil
    }()

    if useSubOptions {
        let subSelectedCount = (state.deleteSelected ? 1 : 0) + (state.deleteReactionsSelected ? 1 : 0)
        let title = singlePeerTitle.map { strings().deleteGroupMessagesDeleteAllFromPeer($0) } ?? strings().supergroupDeleteRestrictionDeleteAllMessages
        options.append(.init(text: title, selected: state.deleteSelected || state.deleteReactionsSelected, revealed: state.deleteRevealed, peerSelected: nil, count: subSelectedCount, totalCount: 2, viewType: deleteAllIsLast && !state.deleteRevealed ? .lastItem : .innerItem, stableId: _id_delete_all, callback: .init(callback: {
            arguments.toggleSelected(_id_delete_all)
        }, toggle: {
            arguments.toggleReveal(_id_delete_all)
        })))
    } else {
        options.append(.init(text: state.allPeers.count == 1 ? strings().supergroupDeleteRestrictionDeleteAllMessages : strings().supergroupDeleteRestrictionDeleteAllMessagesMulti, selected: state.deleteSelected, revealed: state.deleteRevealed, peerSelected: state.allPeers.count == 1 ? nil : state.deletePeerSelected, count: state.allPeers.count == 1 ? nil : state.allPeers.count, viewType: deleteAllIsLast ? .lastItem : .innerItem, stableId: _id_delete_all, callback: .init(callback: {
            arguments.toggleSelected(_id_delete_all)
        }, toggle: {
            arguments.toggleReveal(_id_delete_all)
        })))
    }

    if state.channel.hasPermission(.banMembers) {
        options.append(.init(text: state.allPeers.count == 1 ? (!state.banFully ? strings().supergroupDeleteRestrictionRestrictUser : strings().supergroupDeleteRestrictionBanUser) : (!state.banFully ? strings().supergroupDeleteRestrictionRestrictUserMulti : strings().supergroupDeleteRestrictionBanUserMulti), selected: state.banSelected, revealed: state.banRevealed, peerSelected: state.allPeers.count == 1 ? nil : state.banPeerSelected, count: state.allPeers.count == 1 ? nil : state.allPeers.count, viewType: !state.banRevealed || state.allPeers.count == 1 ? .lastItem : .innerItem, stableId: _id_ban, callback: .init(callback: {
            arguments.toggleSelected(_id_ban)
        }, toggle: {
            arguments.toggleReveal(_id_ban)
        })))
    }
   
    
    let peers: [EnginePeer] = state.allPeers.compactMap { peerId in
        var peer: Peer?
        for message in state.messages {
            peer = message.peers[peerId]
            if peer == nil, message.author?.id == peerId {
                peer = message.author
            }
            if peer == nil, message.effectiveAuthor?.id == peerId {
                peer = message.effectiveAuthor
            }
            if peer != nil {
                break
            }
        }
        if let peer {
            return .init(peer)
        } else {
            return nil
        }
        
    }
    
    for option in options {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: option.stableId, equatable: .init(option), comparable: nil, item: { initialSize, stableId in
            return RowItem(initialSize, context: arguments.context, option: option)
        }))

        if option.stableId == _id_delete_all, useSubOptions, option.revealed {
            let isLastBlock = !state.channel.hasPermission(.banMembers)
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: .init("_id_sub_delete_messages"), data: .init(name: strings().supergroupDeleteRestrictionDeleteAllMessages, color: theme.colors.text, type: .selectableLeft(state.deleteSelected), viewType: .innerItem, action: {
                arguments.toggleSelected(_id_delete_all_sub_messages)
            })))
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: .init("_id_sub_delete_reactions"), data: .init(name: strings().deleteGroupMessagesDeleteAllReactions, color: theme.colors.text, type: .selectableLeft(state.deleteReactionsSelected), viewType: isLastBlock ? .lastItem : .innerItem, action: {
                arguments.toggleSelected(_id_delete_reactions)
            })))
            continue
        }

        if option.revealed, !peers.isEmpty {
            struct Tuple : Equatable {
                let peer: EnginePeer
                let selected: Bool
                let viewType: GeneralViewType
            }
            var items: [Tuple] = []
            for peer in peers {
                var viewType: GeneralViewType = .modern(position: .inner, insets: NSEdgeInsets(left: 40, right: 14))
                if option == options.last, peer == peers.last {
                    viewType = .modern(position: .last, insets: NSEdgeInsets(left: 41, right: 14))
                }
                items.append(.init(peer: peer, selected: option.peerSelected?.contains(peer.id) == true, viewType: viewType))
            }
            
            let interactions = SelectPeerInteraction()
            if let selected = option.peerSelected {
                interactions.update { current in
                    var current = current
                    for peerId in selected {
                        if let peer = peers.first(where: { $0.id == peerId}) {
                            current = current.withToggledSelected(peerId, peer: peer._asPeer(), toggle: true)
                        }
                    }
                    return current
                }
            }
            
            
            interactions.action = { peerId, _ in
                arguments.togglePeerSelected(peerId, option.stableId)
            }
            
            for item in items {
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_peer(item.peer.id, option.stableId), equatable: .init(item), comparable: nil, item: { initialSize, stableId in
                    return ShortPeerRowItem(initialSize, peer: item.peer._asPeer(), account: arguments.context.account, context: arguments.context, height: 40, photoSize: NSMakeSize(26, 26), inset: NSEdgeInsets(left: 20, right: 20), interactionType: .selectable(interactions, side: .left), viewType: item.viewType)
                }))

            }
        }
    }

    if state.communityBanAvailable {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_ban_community, data: .init(name: strings().deleteGroupMessagesBanFromCommunity, color: theme.colors.text, type: .switchable(state.banFromCommunity), viewType: .singleItem, action: {
            arguments.toggleBanFromCommunity()
        })))
        index += 1
        let footer = strings().deleteGroupMessagesRemovedFromChatsCountOther(state.communityChatCount)
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(footer), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
    }

        if state.channel.hasPermission(.banMembers), let defaultBannedRights = state.channel.defaultBannedRights, state.banSelected {
        
        if !state.banFully {
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
            
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().chatManageMessagesWhatOther(state.banPeerSelected.count)), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
            index += 1
            
            var currentRightsFlags: TelegramChatBannedRightsFlags

            if let updatedFlags = state.updatedFlags {
                currentRightsFlags = updatedFlags
            } else {
                currentRightsFlags = defaultBannedRights.flags
                
                currentRightsFlags.insert(.banSendText)
                currentRightsFlags.insert(.banSendMedia)

                for right in banSendMediaSubList().map ({ $0.0 }) {
                    currentRightsFlags.insert(right)
                }
            }
            

            let list = allGroupPermissionList(peer: state.channel)
            for (i, (right, _)) in list.enumerated() {
                
                let defaultEnabled = !defaultBannedRights.flags.contains(right)


                let string: NSMutableAttributedString = NSMutableAttributedString()
                string.append(string: ChatPanelsHooks.shared.stringForGroupPermission(right, state.channel), color: theme.colors.text, font: .normal(.title))

                var afterNameImage: CGImage?
                
                if right == .banSendMedia {
                    let count = banSendMediaSubList().filter({ (currentRightsFlags.contains($0.0)) }).count
                    afterNameImage = generateAfterMedia( "\(count)/\(banSendMediaSubList().count)", revealed: state.mediaRevealed)
                } else {
                    afterNameImage = nil
                }
                
                let rightEnabled = defaultEnabled && currentRightsFlags.contains(right)

                entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: .init("_id_right_\(right.rawValue)"), data: .init(name: string.string, color: theme.colors.text, type: .switchable(rightEnabled), viewType: bestGeneralViewType(list, for: i), enabled: defaultEnabled, action: {
                    let action:()->Void
                    if right == .banSendMedia {
                        action = arguments.toggleMedia
                    } else {
                        action = {
                            arguments.toggleRight(right, rightEnabled)
                        }
                    }
                    action()
                }, switchAction: {
                    arguments.toggleRight(right, rightEnabled)
                }, nameAttributed: string, afterNameImage: afterNameImage)))
                
                if right == .banSendMedia, state.mediaRevealed {
                    for (subRight, _) in banSendMediaSubList() {
                        let string = ChatPanelsHooks.shared.stringForGroupPermission(subRight, state.channel)
                        let defaultEnabled = !defaultBannedRights.flags.contains(subRight)
                        let subRightEnabled = defaultEnabled && currentRightsFlags.contains(subRight)
                        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: .init("_id_right_\(right.rawValue)_\(subRight.rawValue)"), data: .init(name: string, color: theme.colors.text, type: .selectableLeft(subRightEnabled), viewType: .innerItem, enabled: defaultEnabled, action: {
                            arguments.toggleRight(subRight, subRightEnabled)
                        })))
                    }
                }
            }

            
        }
        
        if state.banSelected {
            let text: String
            if state.banFully {
                text = strings().chatManageMessagesRestrictPartiallyOther(state.banPeerSelected.count)
            } else {
                text = strings().chatManageMessagesRestrictFullyOther(state.banPeerSelected.count)
            }
            entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(text, linkHandler: { type in
                arguments.toggleBan(type)
            }), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
            index += 1

        }
       
    }
    

    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

public func DeleteGroupMessagesController(context: any AccountContextProtocol, channel: TelegramChannel, messages: [Message], allPeers:Set<PeerId>, reactionAuthor: PeerId? = nil, analyticsContext: AnalyticsContext? = nil, onComplete:@escaping()->Void) -> InputDataModalController {

    let inherited = messages.contains(where: { $0.containsSecretMedia }) ? Analytics.shared.unresolvedContext() : (analyticsContext ?? Analytics.shared.unresolvedContext())
    var origin = Analytics.shared.captureContext(engine: context.engine, peerId: channel.id, inherited: inherited)
    for message in messages {
        origin = origin.restricting(peerId: message.id.peerId)
        if let author = message.author {
            origin = origin.restricting(peerId: author.id)
        }
    }
    for peerId in allPeers.union([reactionAuthor, channel.linkedCommunityId, channel.linkedMonoforumId].compactMap { $0 }) {
        origin = origin.restricting(peerId: peerId)
    }
    let analyticsOrigin = origin
    let presentation = analyticsOrigin.beginPresentation()
    defer { presentation.end() }
    let actionsDisposable = DisposableSet()

    let initialState = State(channel: channel, messages: messages, allPeers: allPeers, reactionAuthor: reactionAuthor)
    
    let messagesPeerId = channel.isMonoForum ? channel.linkedMonoforumId ?? channel.id : channel.id
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        let presentation = analyticsOrigin.beginPresentation()
        defer { presentation.end() }
        statePromise.set(stateValue.modify (f))
    }
    
    var close:(()->Void)? = nil

    let arguments = Arguments(context: context, toggleBan: { type in
        updateState { current in
            var current = current
            current.banFully = type == "full"
            return current
        }
    }, toggleRight: { rights, value in
                
        guard var defaultBannedRightsFlags = channel.defaultBannedRights?.flags else {
            return
        }
        
        defaultBannedRightsFlags.insert(.banSendText)
        defaultBannedRightsFlags.insert(.banSendMedia)

        for right in banSendMediaSubList().map ({ $0.0 }) {
            defaultBannedRightsFlags.insert(right)
        }
        
        updateState { state in
            var state = state
            var effectiveRightsFlags: TelegramChatBannedRightsFlags
            if let updatedFlags = state.updatedFlags {
                effectiveRightsFlags = updatedFlags
            } else {
                effectiveRightsFlags = defaultBannedRightsFlags
            }
            if value {
                effectiveRightsFlags.remove(rights)
                effectiveRightsFlags = effectiveRightsFlags.subtracting(ChatPanelsHooks.shared.groupPermissionDependencies(rights))
            } else {
                effectiveRightsFlags.insert(rights)
                effectiveRightsFlags = effectiveRightsFlags.union(ChatPanelsHooks.shared.groupPermissionDependencies(rights))
            }
            state.updatedFlags = effectiveRightsFlags
            return state
        }
    }, toggleMedia: {
        updateState { current in
            var current = current
            current.mediaRevealed = !current.mediaRevealed
            return current
        }
    }, toggleReveal: { id in
        updateState { current in
            var current = current
            if id == _id_ban {
                current.banRevealed = !current.banRevealed
            } else if id == _id_report {
                current.spamRevealed = !current.spamRevealed
            } else if id == _id_delete_all {
                current.deleteRevealed = !current.deleteRevealed
            }
            return current
        }
    }, toggleSelected: { id in
        updateState { current in
            var current = current
            if id == _id_ban {
                current.banSelected = !current.banSelected
                if current.banSelected {
                    current.banPeerSelected = current.allPeers
                } else {
                    current.banPeerSelected = Set()
                }
            } else if id == _id_report {
                current.spamSelected = !current.spamSelected
                if current.spamSelected {
                    current.spamPeerSelected = current.allPeers
                } else {
                    current.spamPeerSelected = Set()
                }
            } else if id == _id_delete_all {
                let canDeleteReactions = current.channel.hasPermission(.deleteAllMessages)
                let isSubOptionsMode = canDeleteReactions && current.allPeers.count == 1
                if isSubOptionsMode {
                    let anySelected = current.deleteSelected || current.deleteReactionsSelected
                    current.deleteSelected = !anySelected
                    current.deleteReactionsSelected = !anySelected
                    current.deletePeerSelected = !anySelected ? current.allPeers : Set()
                    current.deleteReactionsPeerSelected = !anySelected ? current.allPeers : Set()
                } else {
                    current.deleteSelected = !current.deleteSelected
                    if current.deleteSelected {
                        current.deletePeerSelected = current.allPeers
                    } else {
                        current.deletePeerSelected = Set()
                    }
                }
            } else if id == _id_delete_all_sub_messages {
                current.deleteSelected = !current.deleteSelected
                if current.deleteSelected {
                    current.deletePeerSelected = current.allPeers
                } else {
                    current.deletePeerSelected = Set()
                }
            } else if id == _id_delete_reactions {
                current.deleteReactionsSelected = !current.deleteReactionsSelected
                if current.deleteReactionsSelected {
                    current.deleteReactionsPeerSelected = current.allPeers
                } else {
                    current.deleteReactionsPeerSelected = Set()
                }
            } else if id == _id_delete {
                current.deleteListSelected = !current.deleteListSelected
            }
            return current
        }
    }, togglePeerSelected: { peerId, id in
        updateState { current in
            var current = current
            if id == _id_ban {
                if !current.banPeerSelected.contains(peerId) {
                    current.banPeerSelected.insert(peerId)
                } else {
                    current.banPeerSelected.remove(peerId)
                }
                current.banSelected = !current.banPeerSelected.isEmpty

            } else if id == _id_report {
                if !current.spamPeerSelected.contains(peerId) {
                    current.spamPeerSelected.insert(peerId)
                } else {
                    current.spamPeerSelected.remove(peerId)
                }
                current.spamSelected = !current.spamPeerSelected.isEmpty

            } else if id == _id_delete_all {
                if !current.deletePeerSelected.contains(peerId) {
                    current.deletePeerSelected.insert(peerId)
                } else {
                    current.deletePeerSelected.remove(peerId)
                }
                current.deleteSelected = !current.deletePeerSelected.isEmpty
            } else if id == _id_delete_reactions {
                if !current.deleteReactionsPeerSelected.contains(peerId) {
                    current.deleteReactionsPeerSelected.insert(peerId)
                } else {
                    current.deleteReactionsPeerSelected.remove(peerId)
                }
                current.deleteReactionsSelected = !current.deleteReactionsPeerSelected.isEmpty
            }
            return current
        }
    }, toggleBanFromCommunity: {
        updateState { current in
            var current = current
            current.banFromCommunity = !current.banFromCommunity
            return current
        }
    })

    if let communityId = channel.linkedCommunityId, case .group = channel.info, allPeers.count == 1, let participantId = allPeers.first {
        let contextSignal = combineLatest(
            context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: communityId)),
            context.engine.peers.communityParticipantJoinedChats(communityId: communityId, participantId: participantId)
        )
        |> mapToSignal { communityPeer, joinedChats -> Signal<(EnginePeer?, CommunityParticipantJoinedChats, [PeerId: Int32]), NoError> in
            let peerIds = [communityPeer?.id].compactMap { $0 } + joinedChats.creatorChatIds + joinedChats.joinedChatIds + Array(joinedChats.peers.keys) + joinedChats.peers.values.map { $0.id }
            let resolvedOrigin = peerIds.reduce(analyticsOrigin) { $0.restricting(peerId: $1) }
            if resolvedOrigin.isExcluded {
                analyticsOrigin.scope?.exclude()
            }
            let presentation = resolvedOrigin.beginPresentation()
            defer { presentation.end() }
            if joinedChats.creatorChatIds.isEmpty {
                return .single((communityPeer, joinedChats, [:]))
            }
            return resolvedOrigin.preservingPresentation(context.engine.data.subscribe(EngineDataMap(joinedChats.creatorChatIds.map { TelegramEngine.EngineData.Item.Peer.ParticipantCount(id: $0) })))
            |> map { countsMap -> (EnginePeer?, CommunityParticipantJoinedChats, [PeerId: Int32]) in
                var counts: [PeerId: Int32] = [:]
                for id in joinedChats.creatorChatIds {
                    if let maybeCount = countsMap[id], let c = maybeCount {
                        counts[id] = Int32(c)
                    }
                }
                return (communityPeer, joinedChats, counts)
            }
        }
        actionsDisposable.add(analyticsOrigin.preservingPresentation(contextSignal).start(next: { communityPeer, joinedChats, creatorCounts in
            var available = false
            var totalCount = 0
            if case let .community(community) = communityPeer, community.hasPermission(.banUsers) {
                let chatIds = Set(joinedChats.creatorChatIds + joinedChats.joinedChatIds)
                totalCount = chatIds.count
                available = !chatIds.isEmpty
            }
            updateState { current in
                var current = current
                current.communityId = communityId
                current.communityChatCount = totalCount
                current.communityBanAvailable = available
                current.communityCreatorChatIds = joinedChats.creatorChatIds
                current.communityChatPeers = joinedChats.peers
                current.communityChatCounts = creatorCounts
                return current
            }
        }))
    }

    let signal = analyticsOrigin.preservingPresentation(statePromise.get() |> deliverOnPrepareQueue) |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controllerTitle: String
    if reactionAuthor != nil {
        controllerTitle = strings().deleteGroupMessagesReactionTitle
    } else {
        controllerTitle = strings().supergroupDeleteRestrictionMultiTitleOther(messages.count)
    }
    let controller = InputDataController(dataSignal: signal, title: controllerTitle)
    controller.analyticsContext = analyticsOrigin
    controller.analyticsScreen = .chatDeleteOptions
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    let messageIds = messages.map { $0.id }
    let peerId = channel.id
    
    controller.validateData = { _ in
        let state = stateValue.with { $0 }
        let selectedPeers = state.allPeers.union(state.banPeerSelected).union(state.spamPeerSelected).union(state.deletePeerSelected).union(state.deleteReactionsPeerSelected).union([state.communityId].compactMap { $0 }).union(state.communityCreatorChatIds).union(state.communityChatPeers.keys).union(state.communityChatPeers.values.map { $0.id })
        let operationOrigin = selectedPeers.reduce(Analytics.shared.captureContext(engine: context.engine, peerId: messagesPeerId, inherited: analyticsOrigin)) { $0.restricting(peerId: $1) }
        if operationOrigin.isExcluded {
            analyticsOrigin.scope?.exclude()
        }
        let presentation = operationOrigin.beginPresentation()
        defer { presentation.end() }
        var signals:[Signal<Void, NoError>] = []

        if state.deleteListSelected {
            if let reactionAuthor, let messageId = messageIds.first {
                _ = operationOrigin.preservingPresentation(context.engine.messages.deleteReaction(messageId: messageId, authorId: reactionAuthor)).start()
            } else {
                signals.append(context.engine.messages.deleteMessagesInteractively(messageIds: messageIds, type: .forEveryone))
            }
        }
        
        if state.banSelected {
            for memberId in state.banPeerSelected {
                var rights: TelegramChatBannedRightsFlags
                var flags: TelegramChatBannedRightsFlags = []
                if state.banFully {
                    rights = [.banReadMessages]
                } else if let defaultBannedRightsFlags = channel.defaultBannedRights?.flags {
                    if let updatedFlags = state.updatedFlags {
                        rights = updatedFlags
                    } else {
                        rights = defaultBannedRightsFlags
                        rights.insert(.banSendText)
                        rights.insert(.banSendMedia)
                        for right in banSendMediaSubList().map ({ $0.0 }) {
                            rights.insert(right)
                        }
                    }
                } else {
                    rights = []
                }
                if state.banFully {
                    flags = rights
                } else {
                    var list = allGroupPermissionList(peer: state.channel).map { $0.0 }
                    list.append(contentsOf: banSendMediaSubList().map { $0.0 })
                    
                    
                    for right in list {
                        if !rights.contains(right) {
                            flags.insert(right)
                        }
                    }
                }
                
                
                
                signals.append(context.peerChannelMemberCategoriesContextsManager.updateMemberBannedRights(peerId: messagesPeerId, memberId: memberId, bannedRights: .init(flags: flags, untilDate: Int32.max)))
            }
        }
        
        if state.spamSelected {
            signals.append(context.engine.peers.reportPeerMessages(messageIds: messageIds, reason: .spam, message: ""))
        }
        
        if state.deleteSelected {
            for memberId in state.deletePeerSelected {
                signals.append(context.engine.messages.clearAuthorHistory(peerId: peerId, memberId: memberId))
            }
        }

        if state.deleteReactionsSelected {
            for memberId in state.deleteReactionsPeerSelected {
                _ = operationOrigin.preservingPresentation(context.engine.messages.deleteAllReactionsWithAuthor(peerId: messagesPeerId, authorId: memberId)).start()
            }
        }

        let commit: () -> Void = {
            let presentation = operationOrigin.beginPresentation()
            defer { presentation.end() }
            if state.banFromCommunity, let communityId = state.communityId, let participantId = state.allPeers.first {
                _ = operationOrigin.preservingPresentation(context.engine.peers.toggleCommunityParticipantBanned(communityId: communityId, participantId: participantId, banned: true)).start()
            }
            if state.deleteListSelected, reactionAuthor == nil {
                Analytics.shared.send(AnalyticsEvents.chatMessageDelete(count: AnalyticsValues.Count(bucketing: messageIds.count), forEveryone: true))
            }
            _ = operationOrigin.preservingPresentation(combineLatest(signals)).start()
            close?()
            onComplete()
        }

        if state.banFromCommunity, !state.communityCreatorChatIds.isEmpty, let participantId = state.allPeers.first {
            let userName: String = {
                for message in messages {
                    if let peer = message.peers[participantId] {
                        return peer.compactDisplayTitle
                    }
                    if message.author?.id == participantId, let author = message.author {
                        return author.compactDisplayTitle
                    }
                }
                return ""
            }()
            let chats: [(peer: EnginePeer, members: Int32?)] = state.communityCreatorChatIds.compactMap { id in
                guard let peer = state.communityChatPeers[id] else { return nil }
                return (peer, state.communityChatCounts[id])
            }
            let count = state.communityCreatorChatIds.count
            let info = strings().deleteGroupMessagesCommunityBanWarningOther(count, userName)
            let header = ModalAlertData.Header(id: "community_ban_warning") { initialSize, stableId, _ in
                let presentation = operationOrigin.beginPresentation()
                defer { presentation.end() }
                return CommunityBanWarningItem(initialSize, stableId: stableId, context: context, chats: chats)
            }
            let confirmationPresentation = operationOrigin.beginPresentation()
            verifyAlert(for: context.window, header: strings().deleteGroupMessagesWarningTitle, information: info, ok: strings().deleteGroupMessagesBan, successHandler: { _ in
                commit()
            }, onDeinit: {
                confirmationPresentation.end()
            }, headerItem: header)
        } else {
            commit()
        }
        return .none
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().supergroupDeleteRestrictionProceed, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
    modalController.analyticsContext = analyticsOrigin
    
    controller.afterTransaction = { [weak modalInteractions] _ in
        let presentation = analyticsOrigin.beginPresentation()
        defer { presentation.end() }
        modalInteractions?.updateDone { button in
            let state = stateValue.with { $0 }
            button.isEnabled = !state.isEmpty
            
            button.set(text: state.text, for: .Normal)
        }
    }
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: {
        close?()
    })
    
    close = { [weak modalController] in
        let presentation = analyticsOrigin.beginPresentation()
        defer { presentation.end() }
        modalController?.modal?.close()
    }

    return modalController
}

private final class CommunityBanWarningItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let chats: [(peer: EnginePeer, members: Int32?)]
    fileprivate let titles: [TextViewLayout]
    fileprivate let subtitles: [TextViewLayout]

    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, chats: [(peer: EnginePeer, members: Int32?)]) {
        self.context = context
        self.chats = chats
        self.titles = chats.map { chat in
            TextViewLayout(.initialize(string: chat.peer._asPeer().displayTitle, color: theme.colors.text, font: .medium(.text)), maximumNumberOfLines: 1)
        }
        self.subtitles = chats.map { chat in
            let str: String
            if let members = chat.members, members > 0 {
                str = strings().deleteGroupMessagesMemberCountOther(Int(members))
            } else {
                str = ""
            }
            return TextViewLayout(.initialize(string: str, color: theme.colors.grayText, font: .normal(.short)), maximumNumberOfLines: 1)
        }
        super.init(initialSize, stableId: stableId)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        for layout in titles {
            layout.measure(width: width - 90)
        }
        for layout in subtitles {
            layout.measure(width: width - 90)
        }
        return true
    }

    override var height: CGFloat {
        return CGFloat(max(1, chats.count)) * 48
    }

    override func viewClass() -> AnyClass {
        return CommunityBanWarningView.self
    }

    override var accessibilityLabel: String? {
        let lines = zip(titles, subtitles).map { title, subtitle -> String in
            let sub = subtitle.attributedString.string
            return sub.isEmpty ? title.attributedString.string : title.attributedString.string + ", " + sub
        }
        return lines.isEmpty ? nil : lines.joined(separator: ". ")
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }
}

private final class CommunityBanWarningView: GeneralRowView {
    private var avatars: [AvatarControl] = []
    private var titleViews: [TextView] = []
    private var subtitleViews: [TextView] = []

    override var backdorColor: NSColor {
        return .clear
    }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? CommunityBanWarningItem else { return }

        while avatars.count > item.chats.count {
            avatars.removeLast().removeFromSuperview()
            titleViews.removeLast().removeFromSuperview()
            subtitleViews.removeLast().removeFromSuperview()
        }
        while avatars.count < item.chats.count {
            let avatar = AvatarControl(font: .avatar(13))
            avatar.setFrameSize(NSMakeSize(36, 36))
            avatar.userInteractionEnabled = false
            let title = TextView()
            title.userInteractionEnabled = false
            title.isSelectable = false
            let subtitle = TextView()
            subtitle.userInteractionEnabled = false
            subtitle.isSelectable = false
            addSubview(avatar)
            addSubview(title)
            addSubview(subtitle)
            avatars.append(avatar)
            titleViews.append(title)
            subtitleViews.append(subtitle)
        }

        for (i, chat) in item.chats.enumerated() {
            avatars[i].setPeer(account: item.context.account, peer: chat.peer._asPeer())
            titleViews[i].update(item.titles[i])
            subtitleViews[i].update(item.subtitles[i])
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? CommunityBanWarningItem else { return }
        let rowHeight: CGFloat = 48
        let inset: CGFloat = 20
        let textX = inset + 36 + 10
        for i in 0 ..< avatars.count {
            let top = CGFloat(i) * rowHeight
            avatars[i].setFrameOrigin(NSMakePoint(inset, top + (rowHeight - 36) / 2))
            let hasSub = !item.subtitles[i].attributedString.string.isEmpty
            if hasSub {
                titleViews[i].setFrameOrigin(NSMakePoint(textX, top + 8))
                subtitleViews[i].setFrameOrigin(NSMakePoint(textX, top + 27))
            } else {
                titleViews[i].setFrameOrigin(NSMakePoint(textX, top + (rowHeight - titleViews[i].frame.height) / 2))
            }
        }
    }
}

