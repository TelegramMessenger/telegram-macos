import Cocoa
import TGUIKit
import TelegramCore
import SwiftSignalKit
import Postbox
import TelegramContext
import TelegramUtils
import TelegramTheme
import Localization
import GeneralRows
import InputDataUI
import ShortPeerRow
import AppAnalytics



private final class ChannelFilterArguments {
    let context: any AccountContextProtocol
    let toggleFlags:(FilterEvents)->Void
    let toggleParentFlags:(FilterParentEvent)->Void
    let toggleRevealParent:(FilterParentEvent)->Void
    let toggleAdmin:(PeerId)->Void
    let toggleAllAdmins:()->Void
    let toggleRevealAdmins:()->Void
    init(context: any AccountContextProtocol, toggleFlags:@escaping(FilterEvents)->Void, toggleAdmin:@escaping(PeerId)->Void, toggleAllAdmins:@escaping()->Void, toggleParentFlags:@escaping(FilterParentEvent)->Void, toggleRevealParent:@escaping(FilterParentEvent)->Void, toggleRevealAdmins:@escaping()->Void) {
        self.context = context
        self.toggleFlags = toggleFlags
        self.toggleAdmin = toggleAdmin
        self.toggleAllAdmins = toggleAllAdmins
        self.toggleParentFlags = toggleParentFlags
        self.toggleRevealParent = toggleRevealParent
        self.toggleRevealAdmins = toggleRevealAdmins
    }
}

private enum ChannelEventFilterEntryId : Hashable {
    case section(Int32)
    case header(Int32)
    case filter(FilterParentEvent)
    case subfilter(FilterEvents)
    case allAdmins
    case admin(PeerId)
    case adminsLoading
}

private enum ChannelEventFilterEntry : TableItemListNodeEntry {
    case section(Int32, height: CGFloat)
    case header(Int32, Int32, text: String)
    case filter(Int32, Int32, flag: FilterParentEvent, name:String, afterName: CGImage, revealed: Bool, enabled: Bool, viewType: GeneralViewType)
    case subfilter(Int32, Int32, flag: FilterEvents, name:String, enabled: Bool, viewType: GeneralViewType)
    case allAdmins(Int32, Int32, enabled: Bool, viewType: GeneralViewType)
    case admin(Int32, Int32, peer: RenderedChannelParticipant, enabled: Bool, viewType: GeneralViewType)
    case adminsLoading(Int32, Int32, viewType: GeneralViewType)
    var stableId:ChannelEventFilterEntryId {
        switch self {
        case .section(let value, _):
            return .section(value)
        case .header(_, let value, _):
            return .header(value)
        case .filter(_, _, let value, _, _, _, _, _):
            return .filter(value)
        case .subfilter(_, _, let value, _, _, _):
            return .subfilter(value)
        case .adminsLoading:
            return .adminsLoading
        case .allAdmins:
            return .allAdmins
        case .admin(_, _, let value, _, _):
            return .admin(value.peer.id)
        }
    }
    
    var index:Int32 {
        switch self {
        case let .section(section, _):
            return (section * 1000) - section
        case let .header(section, index, _):
            return (section * 1000) + index
        case let .filter(section, index, _, _, _, _, _, _):
            return (section * 1000) + index
        case let .subfilter(section, index, _, _, _, _):
            return (section * 1000) + index
        case .allAdmins(let section, let index, _, _):
            return (section * 1000) + index
        case let .admin(section, index, _, _, _):
            return (section * 1000) + index
        case let .adminsLoading(section, index, _):
            return (section * 1000) + index
        }
    }
    
    func item(_ arguments: ChannelFilterArguments, initialSize: NSSize) -> TableRowItem {
        switch self {
        case let .section(_, height):
            return GeneralRowItem(initialSize, height: height, stableId: stableId, backgroundColor: .clear)
        case .header(_, _, let text):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, viewType: .textTopItem)
        case .allAdmins(_, _, let enabled, let viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().chanelEventFilterAllAdminsNew, type: .selectableLeft(enabled), viewType: viewType, action: {
                arguments.toggleRevealAdmins()
            }, switchAction: {
                arguments.toggleAllAdmins()
            })
        case let .filter(_, _, flag, name, afterName, _, enabled, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: name, type: .selectableLeft(enabled), viewType: viewType, action: {
                arguments.toggleRevealParent(flag)
            }, switchAction: {
                arguments.toggleParentFlags(flag)
            }, afterNameImage: afterName)
        case let .subfilter(_, _, flag, name, enabled, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: name, type: .selectableLeft(enabled), viewType: viewType, action: {
                arguments.toggleFlags(flag)
            })
        case .adminsLoading(_, _, let viewType):
            return LoadingTableItem(initialSize, height: 30, stableId: stableId, viewType: viewType)
        case let .admin( _, _, participant, enabled, viewType):
            
            let status:String
            switch participant.participant {
            case .creator:
                status = strings().adminsOwner
            case .member:
                status = strings().adminsAdmin
            }
            
            let interactions = SelectPeerInteraction()
            interactions.update { current in
                var current = current
                current = current.withToggledSelected(participant.peer.id, peer: participant.peer._asPeer(), toggle: enabled)
                return current
            }
            
            interactions.action = { peerId, _ in
                arguments.toggleAdmin(peerId)
            }
            
            return ShortPeerRowItem(initialSize, peer: participant.peer._asPeer(), account: arguments.context.account, context: arguments.context, stableId: stableId, height: 42, photoSize: NSMakeSize(30, 30), status: status, inset: NSEdgeInsets(left: 20, right: 20), interactionType: .selectable(interactions, side: .left), generalType: .none, viewType: viewType, action: {
                arguments.toggleAdmin(participant.peer.id)
            })
        }
    }
}

private func <(lhs:ChannelEventFilterEntry, rhs: ChannelEventFilterEntry) -> Bool {
    return lhs.index < rhs.index
}

struct ChannelEventFilterState : Equatable {
    fileprivate var allAdmins:Set<PeerId> = Set()
    fileprivate var admins: Set<PeerId> = Set()
    fileprivate var events: Set<FilterEvents> = FilterEvents.all
    
    fileprivate var revealed: Set<FilterParentEvent> = Set()
    fileprivate var isChannel: Bool = false
    fileprivate var adminsRevealed: Bool = false
    
    var isFull: Bool {
        return self.events == FilterEvents.all
    }
    
    var selectedFlags:AdminLogEventsFlags {
        let events = self.events
        var flags: AdminLogEventsFlags = []
        
        let all:[FilterEvents] = [FilterParentEvent.membersAndAdmins, FilterParentEvent.messages, FilterParentEvent.settings].reduce([], { current, value in
            var current = current
            current.append(contentsOf: value.sublist(isChannel))
            return current
        })
        
        for event in events {
            if all.contains(event) {
                flags.insert(event.flags)
            }
        }
        return events.isEmpty ? AdminLogEventsFlags.flags : flags
    }
    var selectedAdmins:[PeerId]? {
        if admins.isEmpty {
            return nil
        } else {
            return Array(allAdmins.subtracting(admins))
        }
    }
    
    var isEmpty: Bool {
        return admins.isEmpty && events.isEmpty
    }
}


private enum FilterParentEvent : Equatable {
    case membersAndAdmins
    case settings
    case messages
    
    func localizedString(_ isChannel: Bool) -> String {
        switch self {
        case .membersAndAdmins:
            return strings().channelEventFilterMembersAndAdmins
        case .settings:
            if isChannel {
                return strings().channelEventFilterChannelSettings
            } else {
                return strings().channelEventFilterGroupSettings
            }
        case .messages:
            return strings().channelEventFilterMessages
        }
    }
    
    func sublist(_ isChannel: Bool) -> [FilterEvents] {
        switch self {
        case .membersAndAdmins:
            if isChannel {
                return [.newAdmins, .newMembers, .leavingMembers]
            } else {
                return [.restrictions, .newAdmins, .newMembers, .leavingMembers]
            }
        case .settings:
            if isChannel {
                return [.groupInfo, .voiceChats]
            } else {
                return [.groupInfo, .invites, .voiceChats]
            }
        case .messages:
            return [.deletedMessages, .editedMessages, .pinnedMessages]
        }
    }
}

private enum FilterEvents {
    case restrictions
    case newMembers
    case newAdmins
    case groupInfo
    case deletedMessages
    case editedMessages
    case voiceChats
    case sendMessages
    case pinnedMessages
    case leavingMembers
    case invites
    var flags:AdminLogEventsFlags {
        switch self {
        case .newMembers:
            return [.join, .unban]
        case .newAdmins:
            return [.promote]
        case .leavingMembers:
            return  [.leave, .kick]
        case .restrictions:
            return [.unban, .ban]
        case .groupInfo:
            return [.info, .settings]
        case .pinnedMessages:
            return [.pinnedMessages]
        case .editedMessages:
            return [.editMessages]
        case .deletedMessages:
            return [.deleteMessages]
        case .voiceChats:
            return [.calls]
        case .invites:
            return [.invites]
        case .sendMessages:
            return [.sendMessages]
        }
    }
    
    static var all: Set<FilterEvents> {
        return Set([.restrictions,
                    .newMembers,
                    .newAdmins,
                    .groupInfo,
                    .deletedMessages,
                    .editedMessages,
                    .voiceChats,
                    .sendMessages,
                    .pinnedMessages,
                    .leavingMembers,
                    .invites])
    }
    
    func localizedString(_ broadcast:Bool) -> String {
        switch self {
        case .newMembers:
            return strings().channelEventFilterNewMembers
        case .newAdmins:
            return strings().channelEventFilterNewAdmins
        case .leavingMembers:
            return  strings().channelEventFilterLeavingMembers
        case .restrictions:
            return strings().channelEventFilterNewRestrictions
        case .groupInfo:
            return broadcast ? strings().channelEventFilterChannelInfo : strings().channelEventFilterGroupInfo
        case .pinnedMessages:
            return strings().channelEventFilterPinnedMessages
        case .editedMessages:
            return strings().channelEventFilterEditedMessages
        case .deletedMessages:
            return strings().channelEventFilterDeletedMessages
        case .voiceChats:
            return strings().channelEventFilterVoiceChats
        case .invites:
            return strings().channelEventFilterInvites
        case .sendMessages:
            return strings().channelEventFilterSendMessages

        }
    }
}

private func generateEventLogAfter(_ flag: FilterParentEvent, state: ChannelEventFilterState, isChannel: Bool) -> CGImage {
    let sublist = flag.sublist(isChannel)
    let total = sublist.count
    let selected = state.events.filter { sublist.contains($0) }.count
    let revealed = state.revealed.contains(flag)
    
    let layout = TextNode.layoutText(.initialize(string: "\(selected)/\(total)", color: theme.colors.text, font: .medium(.text)), nil, 1, .end, NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude), nil, false, .center)
    let image = TelegramThemeHooks.shared.image(revealed ? .iconSmallChevronUp : .iconSmallChevronDown).precomposed(theme.colors.text, flipVertical: true)

    return generateImage(NSMakeSize(layout.0.size.width + 3 + image.backingSize.width, layout.0.size.height), contextGenerator: { size, ctx in
        ctx.clear(size.bounds)
        
        var rect = size.bounds.focus(layout.0.size)
        rect.origin.x = 0
        layout.1.draw(rect, in: ctx, backingScaleFactor: 2, backgroundColor: .clear)
        
        var imageRect = size.bounds.focus(image.backingSize)
        imageRect.origin.x = rect.maxX + 3
        ctx.draw(image, in: imageRect)
    })!
}


private func channelEventFilterEntries(state: ChannelEventFilterState, peer:Peer, admins:[RenderedChannelParticipant]?) -> [ChannelEventFilterEntry] {
    var entries:[ChannelEventFilterEntry] = []
    
    var section:Int32 = 1
    var index:Int32 = 1
    
    entries.append(.section(section, height: 10))
    section += 1
    
    entries.append(.header(section, index, text: strings().channelEventFilterEventsHeader))
    index += 1
    
    
    let filters = [FilterParentEvent.membersAndAdmins, FilterParentEvent.settings, FilterParentEvent.messages]
    for (i, flag) in filters.enumerated() {
        var viewType: GeneralViewType = bestGeneralViewType(filters, for: i)
        let afterName = generateEventLogAfter(flag, state: state, isChannel: peer.isChannel)
        
        let revealed = state.revealed.contains(flag)
        let sublist = flag.sublist(peer.isChannel)

        if i == filters.count - 1, revealed {
            viewType = .innerItem
        }
        
        let selected = state.events.filter { sublist.contains($0) }
        
        entries.append(.filter(section, index, flag: flag, name: flag.localizedString(peer.isChannel), afterName: afterName, revealed: revealed, enabled: selected.count == sublist.count, viewType: viewType))
        
        if revealed {
            for subitem in sublist {
                var position: GeneralViewItemPosition = .inner
                if i == filters.count - 1, subitem == sublist.last {
                    position = .last
                }
                entries.append(.subfilter(section, index, flag: subitem, name: subitem.localizedString(peer.isChannel), enabled: state.events.contains(subitem), viewType: .modern(position: position, insets: NSEdgeInsets.init(top: 10, left: 50, bottom: 14, right: 14))))
            }
        }
    }
    
    entries.append(.section(section, height: 20))
    section += 1
    
    entries.append(.header(section, index, text: strings().channelEventFilterAdminsHeader))
    index += 1
    
    
    entries.append(.allAdmins(section, index, enabled: state.admins.isEmpty, viewType: state.adminsRevealed ? .firstItem : .singleItem))
    index += 1
    
    if state.adminsRevealed {
        if let admins = admins {
            for (i, admin) in admins.enumerated() {
                var viewType: GeneralViewType = .modern(position: .inner, insets: NSEdgeInsets(left: 50, right: 14))
                if i == admins.count - 1 {
                    viewType = .modern(position: .last, insets: NSEdgeInsets(left: 50, right: 14))
                }
                entries.append(.admin(section, index, peer: admin, enabled: !state.admins.contains(admin.peer.id), viewType: viewType))
            }
        } else {
            entries.append(.adminsLoading(section, index, viewType: .lastItem))
            index += 1
        }
    }
    
    
    entries.append(.section(section, height: 20))
    section += 1

    
    return entries
}

private func eventFilterInputDataEntries(_ entries: [ChannelEventFilterEntry], arguments: ChannelFilterArguments) -> [InputDataEntry] {
    var result: [InputDataEntry] = []
    var autoIndex: Int32 = 0
    for entry in entries {
        switch entry {
        case let .section(sectionId, height):
            result.append(.sectionId(sectionId, type: .customModern(height)))
        default:
            let identifier: InputDataIdentifier
            switch entry.stableId {
            case let .section(id):
                identifier = InputDataIdentifier("section_\(id)")
            case let .header(id):
                identifier = InputDataIdentifier("header_\(id)")
            case let .filter(flag):
                switch flag {
                case .membersAndAdmins: identifier = InputDataIdentifier("filter_members")
                case .settings: identifier = InputDataIdentifier("filter_settings")
                case .messages: identifier = InputDataIdentifier("filter_messages")
                }
            case let .subfilter(flag):
                identifier = InputDataIdentifier("subfilter_\(flag.flags.rawValue)")
            case .allAdmins:
                identifier = InputDataIdentifier("allAdmins")
            case let .admin(peerId):
                identifier = InputDataIdentifier("admin_\(peerId.toInt64())")
            case .adminsLoading:
                identifier = InputDataIdentifier("adminsLoading")
            }
            let sectionId: Int32
            switch entry {
            case let .header(s, _, _): sectionId = s
            case let .filter(s, _, _, _, _, _, _, _): sectionId = s
            case let .subfilter(s, _, _, _, _, _): sectionId = s
            case let .allAdmins(s, _, _, _): sectionId = s
            case let .admin(s, _, _, _, _): sectionId = s
            case let .adminsLoading(s, _, _): sectionId = s
            default: sectionId = 0
            }
            result.append(.custom(sectionId: sectionId, index: autoIndex, value: .none, identifier: identifier, equatable: InputDataEquatable(entry), comparable: nil, item: { initialSize, stableId in
                return entry.item(arguments, initialSize: initialSize)
            }))
            autoIndex += 1
        }
    }
    return result
}

func ChannelEventFilterModalController(context: any AccountContextProtocol, peerId: PeerId, isChannel: Bool, admins: [RenderedChannelParticipant], state: ChannelEventFilterState = ChannelEventFilterState(), updated: @escaping (ChannelEventFilterState) -> Void) -> InputDataModalController {

    var initialState = state
    initialState.isChannel = isChannel

    let stateValue = Atomic(value: initialState)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let updateState: ((ChannelEventFilterState) -> ChannelEventFilterState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var close: (() -> Void)?

    let arguments = ChannelFilterArguments(context: context, toggleFlags: { flags in
        updateState { current in
            var current = current
            if current.events.contains(flags) {
                current.events.remove(flags)
            } else {
                current.events.insert(flags)
            }
            return current
        }
    }, toggleAdmin: { peerId in
        updateState { current in
            var current = current
            if current.admins.contains(peerId) {
                current.admins.remove(peerId)
            } else {
                current.admins.insert(peerId)
            }
            return current
        }
    }, toggleAllAdmins: {
        updateState { current in
            var current = current
            if !current.admins.isEmpty {
                current.admins.removeAll()
            } else {
                current.admins = current.allAdmins
            }
            return current
        }
    }, toggleParentFlags: { flags in
        updateState { current in
            var current = current
            let sublist = flags.sublist(isChannel)
            let selected = current.events.filter { sublist.contains($0) }
            if selected.count == sublist.count {
                for item in sublist {
                    current.events.remove(item)
                }
            } else {
                for item in sublist {
                    current.events.insert(item)
                }
            }
            return current
        }
    }, toggleRevealParent: { flag in
        updateState { current in
            var current = current
            if current.revealed.contains(flag) {
                current.revealed.remove(flag)
            } else {
                current.revealed.insert(flag)
            }
            return current
        }
    }, toggleRevealAdmins: {
        updateState { current in
            var current = current
            current.adminsRevealed = !current.adminsRevealed
            return current
        }
    })

    let adminsSignal = Signal<[RenderedChannelParticipant], NoError>.single(admins)

    let antiSpamBotConfiguration = AntiSpamBotConfiguration.with(appConfiguration: context.appConfiguration)
    let antiSpamBotPeerPromise = Promise<RenderedChannelParticipant?>(nil)
    if let antiSpamBotId = antiSpamBotConfiguration.antiSpamBotId {
        antiSpamBotPeerPromise.set(context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: antiSpamBotId))
        |> map { peer in
            if let peer = peer, case let .user(user) = peer {
                return RenderedChannelParticipant(participant: .member(id: user.id, invitedAt: 0, adminInfo: nil, banInfo: nil, rank: nil, subscriptionUntilDate: nil), peer: .init(user))
            } else {
                return nil
            }
        })
    }

    let adminsWithBot = combineLatest(adminsSignal, antiSpamBotPeerPromise.get()) |> map { admins, antispamAdmin in
        return [antispamAdmin].compactMap { $0 } + admins
    }

    let signal: Signal<InputDataSignalValue, NoError> = combineLatest(statePromise.get(), context.account.postbox.loadedPeerWithId(peerId), adminsWithBot) |> map { state, peer, admins in

        let entries = channelEventFilterEntries(state: state, peer: peer, admins: admins)

        updateState { current in
            var current = current
            current.allAdmins = Set(admins.map { $0.peer.id })
            return current
        }
        return InputDataSignalValue(entries: eventFilterInputDataEntries(entries, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().channelAdminsRecentActions, getBackgroundColor: {
        theme.colors.listBackground
    })
    controller.analyticsScreen = .peerInfoRecentActionsEventTypes

    let modalInteractions = ModalInteractions(acceptTitle: strings().modalDone, accept: {
        updated(stateValue.with { $0 })
        close?()
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(350, 300))

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    controller.centerModalHeader = ModalHeaderData(title: strings().channelAdminsRecentActions)

    close = { [weak modalController] in
        modalController?.close()
    }

    return modalController
}
