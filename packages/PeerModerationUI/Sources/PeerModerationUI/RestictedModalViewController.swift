import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import TelegramTheme
import Localization
import GeneralRows
import InputDataUI
import ShortPeerRow
import AppAnalytics

private final class RestrictedControllerArguments {
    let context: any AccountContextProtocol
    let toggleRight: (TelegramChatBannedRightsFlags, Bool) -> Void
    let changeUntil:()->Void
    let alertError:() -> Void
    let deleteException:()->Void
    let toggleMedia:()->Void
    init(context: any AccountContextProtocol, toggleRight: @escaping (TelegramChatBannedRightsFlags, Bool) -> Void, changeUntil: @escaping () -> Void, alertError: @escaping() -> Void,  deleteException:@escaping()->Void, toggleMedia:@escaping()->Void) {
        self.context = context
        self.toggleRight = toggleRight
        self.changeUntil = changeUntil
        self.alertError = alertError
        self.deleteException = deleteException
        self.toggleMedia = toggleMedia
    }
}

private enum RestrictedEntryStableId: Hashable {
    case info
    case right(TelegramChatBannedRightsFlags)
    case description(Int32)
    case section(Int32)
    case timeout
    case exceptionInfo
    case delete
    func hash(into hasher: inout Hasher) {
        hasher.combine(0)
    }
}

private enum RestrictedEntry: TableItemListNodeEntry {
    case info(Int32, Peer, TelegramUserPresence?, GeneralViewType)
    case rightItem(Int32, Int32, NSAttributedString, TelegramChatBannedRightsFlags, Bool, Bool, GeneralViewType)
    case mediaRightItem(Int32, Int32, String, TelegramChatBannedRightsFlags, Bool, Bool, GeneralViewType)
    case description(Int32, Int32, String, GeneralViewType)
    case section(Int32, CGFloat)
    case timeout(Int32, Int32, String, String, GeneralViewType)
    case exceptionInfo(Int32, Int32, String, GeneralViewType)
    case delete(Int32, Int32, String, GeneralViewType)
    
    
    static func ==(lhs: RestrictedEntry, rhs: RestrictedEntry) -> Bool {
        switch lhs {
        case let .info(lhsSectionId, lhsPeer, lhsPresence, lhsViewType):
            if case let .info(rhsSectionId, rhsPeer, rhsPresence, rhsViewType) = rhs {
                if lhsSectionId != rhsSectionId {
                    return false
                }
                if !arePeersEqual(lhsPeer, rhsPeer) {
                    return false
                }
                if lhsPresence != rhsPresence {
                    return false
                }
                if lhsViewType != rhsViewType {
                    return false
                }
                return true
            } else {
                return false
            }
        case let .rightItem(sectionId, index, text, flags, value, enabled, viewType):
            if case .rightItem(sectionId, index, text, flags, value, enabled, viewType) = rhs {
                return true
            } else {
                return false
            }
        case let .mediaRightItem(sectionId, index, text, flags, value, enabled, viewType):
            if case .mediaRightItem(sectionId, index, text, flags, value, enabled, viewType) = rhs {
                return true
            } else {
                return false
            }
        case let .description(sectionId, index, text, viewType):
            if case .description(sectionId, index, text, viewType) = rhs{
                return true
            } else {
                return false
            }
        case let .section(sectionId, height):
            if case .section(sectionId, height) = rhs{
                return true
            } else {
                return false
            }
        case let .exceptionInfo(sectionId, index, text, viewType):
            if case .exceptionInfo(sectionId, index, text, viewType) = rhs {
                return true
            } else {
                return false
            }
        case let .delete(sectionId, index, text, viewType):
            if case .delete(sectionId, index, text, viewType) = rhs {
                return true
            } else {
                return false
            }
        case let .timeout(sectionId, index, title, value, viewType):
            if case .timeout(sectionId, index, title, value, viewType) = rhs{
                return true
            } else {
                return false
            }
        }
    }
    

    var stableId: RestrictedEntryStableId {
        switch self {
        case .info:
            return .info
        case .timeout:
            return .timeout
        case let .rightItem(_, _, _, right, _, _, _):
            return .right(right)
        case let .mediaRightItem(_, _, _, right, _, _, _):
            return .right(right)
        case .description(_, let index, _, _):
            return .description(index)
        case .exceptionInfo:
            return .exceptionInfo
        case .delete:
            return .delete
        case .section(let sectionId, _):
            return .section(sectionId)
        }
    }
    
    var index:Int32 {
        switch self {
        case .info(let sectionId, _, _, _):
            return (sectionId * 1000) + 0
        case .description(let sectionId, let index, _, _):
            return (sectionId * 1000) + index
        case .delete(let sectionId, let index, _, _):
            return (sectionId * 1000) + index
        case .exceptionInfo(let sectionId, let index, _, _):
            return (sectionId * 1000) + index
        case .rightItem(let sectionId, let index, _, _, _, _, _):
            return (sectionId * 1000) + Int32(index) + 10
        case .mediaRightItem(let sectionId, let index, _, _, _, _, _):
            return (sectionId * 1000) + Int32(index) + 10
        case .section(let sectionId, _):
            return (sectionId + 1) * 1000 - sectionId
        case .timeout(let sectionId, let index, _, _, _):
            return (sectionId * 1000) + index
        }
    }
    
    static func <(lhs: RestrictedEntry, rhs: RestrictedEntry) -> Bool {
        return lhs.index < rhs.index
    }
    
    func item(_ arguments: RestrictedControllerArguments, initialSize: NSSize) -> TableRowItem {
        switch self {
        case let .section(_, height):
            return GeneralRowItem(initialSize, height: height, stableId: stableId, viewType: .separator)
        case let .info(_, peer, presence, viewType):
            var string:String = peer.isBot ? strings().presenceBot : strings().peerStatusRecently
            var color:NSColor = theme.colors.grayText
            
            if let presence = presence {
                let timestamp = CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970
                (string,_, color) = stringAndActivityForUserPresence(presence, timeDifference: arguments.context.timeDifference, relativeTo: Int32(timestamp))
            }
            return ShortPeerRowItem(initialSize, peer: peer, account: arguments.context.account, context: arguments.context, stableId: stableId, enabled: true, height: 60, photoSize: NSMakeSize(40, 40), statusStyle: ControlStyle(font: .normal(.title), foregroundColor: color), status: string, borderType: [], drawCustomSeparator: false, drawLastSeparator: false, inset: NSEdgeInsets(left: 25, right: 25), drawSeparatorIgnoringInset: false, viewType: viewType, action: {})
        case let .rightItem(_, _, name, right, value, enabled, viewType):
            let action:()->Void
            if right == .banSendMedia {
                action = arguments.toggleMedia
            } else {
                action = {
                    arguments.toggleRight(right, !value)
                }
            }
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: name.string, nameAttributed: name, nameStyle: ControlStyle(font: .normal(.title), foregroundColor: enabled ? theme.colors.text : theme.colors.grayText), type: .switchable(value), viewType: viewType, action: action, enabled: enabled, switchAppearance: SwitchViewAppearance(backgroundColor: .white, stateOnColor: theme.colors.accent, stateOffColor: theme.colors.redUI, disabledColor: theme.colors.grayBackground, borderColor: .clear), disabledAction: {
                arguments.alertError()
            }, switchAction: {
                arguments.toggleRight(right, !value)
            })
        case let .mediaRightItem(_, _, name, right, value, enabled, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: name, nameStyle: ControlStyle(font: .normal(.title), foregroundColor: enabled ? theme.colors.text : theme.colors.grayText), type: .selectableLeft(value), viewType: viewType, action: {
                arguments.toggleRight(right, !value)
            }, enabled: enabled, switchAppearance: SwitchViewAppearance(backgroundColor: .white, stateOnColor: theme.colors.accent, stateOffColor: theme.colors.redUI, disabledColor: theme.colors.grayBackground, borderColor: .clear), disabledAction: {
                arguments.alertError()
            })
        case let .description(_, _, name, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: name, viewType: viewType)
        case let .timeout(_, _, title, value, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: title, type: .nextContext(value), viewType: viewType, action: {
                arguments.changeUntil()
            })
        case let .exceptionInfo(_, _, text, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: text, viewType: viewType)
        case let .delete(_, _, name, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: name, nameStyle: redActionButton, type: .next, viewType: viewType, action: arguments.deleteException)
        }
    }
}


private struct RestrictedControllerState: Equatable {
    var referenceTimestamp: Int32
    var updatedFlags: TelegramChatBannedRightsFlags?
    var updatedTimeout: Int32?
    var updating: Bool = false
    var mediaRevealed: Bool = false
}
private func completeRights(_ flags: TelegramChatBannedRightsFlags) -> TelegramChatBannedRightsFlags {
    var result = flags
    result.remove(.banReadMessages)
    if result.contains(.banSendGifs) {
        result.insert(.banSendStickers)
        result.insert(.banSendGifs)
        result.insert(.banSendGames)
        result.insert(.banSendInline)
    } else {
        result.remove(.banSendStickers)
        result.remove(.banSendGifs)
        result.remove(.banSendGames)
        result.insert(.banSendInline)
    }
    return result
}


private func restrictedEntries(state: RestrictedControllerState, accountPeerId: PeerId, channelView: PeerView, memberView: PeerView, initialParticipant: ChannelParticipant?, initialBannedBy: Peer?) -> [RestrictedEntry] {
    var index:Int32 = 0
    var sectionId:Int32 = 0
    var entries:[RestrictedEntry] = []
    
    entries.append(.section(sectionId, 10))
    sectionId += 1
    
    
    
    if let peer = channelView.peers[channelView.peerId] as? TelegramChannel, let defaultBannedRights = peer.defaultBannedRights, let member = memberView.peers[memberView.peerId] {
        entries.append(.info(sectionId, member, memberView.peerPresences[member.id] as? TelegramUserPresence, .singleItem))
        
        entries.append(.section(sectionId, 20))
        sectionId += 1
        
        entries.append(.description(sectionId, index, strings().groupPermissionSectionTitle, .textTopItem))
        index += 1

        let currentRightsFlags: TelegramChatBannedRightsFlags
        if let updatedFlags = state.updatedFlags {
            currentRightsFlags = updatedFlags
        } else if let initialParticipant = initialParticipant, case let .member(_, _, _, maybeBanInfo, _, _) = initialParticipant, let banInfo = maybeBanInfo {
            currentRightsFlags = banInfo.rights.flags
        } else {
            currentRightsFlags = defaultBannedRights.flags
        }
        
        let currentTimeout: Int32
        if let updatedTimeout = state.updatedTimeout {
            currentTimeout = updatedTimeout
        } else if let initialParticipant = initialParticipant, case let .member(_, _, _, maybeBanInfo, _, _) = initialParticipant, let banInfo = maybeBanInfo {
            currentTimeout = banInfo.rights.untilDate
        } else {
            currentTimeout = Int32.max
        }
        
        let currentTimeoutString: String
        if currentTimeout == 0 || currentTimeout == Int32.max {
            currentTimeoutString = strings().timerForever
        } else {
            let remainingTimeout = currentTimeout - state.referenceTimestamp
            currentTimeoutString = timeIntervalString(Int(remainingTimeout))
        }
        
        let list = allGroupPermissionList(peer: peer)
        for (i, (right, _)) in list.enumerated() {
            
            let string: NSMutableAttributedString = NSMutableAttributedString()
            string.append(string: stringForGroupPermission(right: right, channel: peer), color: theme.colors.text, font: .normal(.title))
            
            if right == .banSendMedia {
                let count = banSendMediaSubList().filter({ !(currentRightsFlags.contains($0.0)) }).count
                string.append(string: " \(count)/\(banSendMediaSubList().count)", color: theme.colors.text, font: .bold(.small))
            }
            
            let defaultEnabled = !defaultBannedRights.flags.contains(right)
            entries.append(.rightItem(sectionId, index, string, right, defaultEnabled && !currentRightsFlags.contains(right), defaultEnabled && !state.updating, bestGeneralViewType(list, for: i)))
            index += 1
            if right == .banSendMedia, state.mediaRevealed {
                for (subRight, _) in banSendMediaSubList() {
                    let defaultEnabled = !defaultBannedRights.flags.contains(subRight)
                    entries.append(.mediaRightItem(sectionId, index, stringForGroupPermission(right: subRight, channel: peer), subRight, defaultEnabled && !currentRightsFlags.contains(subRight), defaultEnabled && !state.updating, .innerItem))
                    index += 1
                }
            }
        }
        
        entries.append(.section(sectionId, 20))
        sectionId += 1
        
      
        
        if let initialParticipant = initialParticipant, case let .member(_, _, _, maybeBanInfo, _, _) = initialParticipant, let banInfo = maybeBanInfo, let initialBannedBy = initialBannedBy {
            entries.append(.timeout(sectionId, index, strings().groupPermissionDuration, currentTimeoutString, .firstItem))
            index += 1
            entries.append(.delete(sectionId, index, strings().groupPermissionDelete, .lastItem))
            index += 1
            entries.append(.exceptionInfo(sectionId, index, strings().groupPermissionAddedInfo(initialBannedBy.displayTitle, stringForRelativeSymbolicTimestamp(relativeTimestamp: banInfo.timestamp, relativeTo: state.referenceTimestamp)), .textBottomItem))
            index += 1
        } else {
            entries.append(.timeout(sectionId, index, strings().groupPermissionDuration, currentTimeoutString, .singleItem))
            index += 1
        }

    } else if let group = channelView.peers[channelView.peerId] as? TelegramGroup, let defaultBannedRights = group.defaultBannedRights, let member = memberView.peers[memberView.peerId] {
        entries.append(.info(sectionId, member, memberView.peerPresences[member.id] as? TelegramUserPresence, .singleItem))

        
        entries.append(.section(sectionId, 20))
        sectionId += 1

        entries.append(.description(sectionId, index, strings().groupPermissionSectionTitle, .textTopItem))
        index += 1
        
        let currentRightsFlags: TelegramChatBannedRightsFlags
        if let updatedFlags = state.updatedFlags {
            currentRightsFlags = updatedFlags
        } else if let initialParticipant = initialParticipant, case let .member(_, _, _, maybeBanInfo, _, _) = initialParticipant, let banInfo = maybeBanInfo {
            currentRightsFlags = banInfo.rights.flags
        } else {
            currentRightsFlags = defaultBannedRights.flags
        }
        
        let currentTimeout: Int32
        if let updatedTimeout = state.updatedTimeout {
            currentTimeout = updatedTimeout
        } else if let initialParticipant = initialParticipant, case let .member(_, _, _, maybeBanInfo, _, _) = initialParticipant, let banInfo = maybeBanInfo {
            currentTimeout = banInfo.rights.untilDate
        } else {
            currentTimeout = Int32.max
        }
        
        let currentTimeoutString: String
        if currentTimeout == 0 || currentTimeout == Int32.max {
            currentTimeoutString = strings().timerForever
        } else {
            let remainingTimeout = currentTimeout - state.referenceTimestamp
            currentTimeoutString = timeIntervalString(Int(remainingTimeout))
        }
                
        let list = allGroupPermissionList(peer: group)
        for (i, (right, _)) in list.enumerated() {
            
            let string: NSMutableAttributedString = NSMutableAttributedString()
            string.append(string: stringForGroupPermission(right: right, channel: nil), color: theme.colors.text, font: .normal(.title))
            
            if right == .banSendMedia {
                let count = banSendMediaSubList().filter({ !(currentRightsFlags.contains($0.0)) }).count
                string.append(string: " \(count)/\(banSendMediaSubList().count)", color: theme.colors.text, font: .bold(.small))
            }
            
            let defaultEnabled = !defaultBannedRights.flags.contains(right)
            entries.append(.rightItem(sectionId, index, string, right, defaultEnabled && !currentRightsFlags.contains(right), defaultEnabled && !state.updating, bestGeneralViewType(list, for: i)))
            index += 1
            if right == .banSendMedia, state.mediaRevealed {
                for (subRight, _) in banSendMediaSubList() {
                    let defaultEnabled = !defaultBannedRights.flags.contains(subRight)
                    entries.append(.mediaRightItem(sectionId, index, stringForGroupPermission(right: subRight, channel: nil), subRight, defaultEnabled && !currentRightsFlags.contains(subRight), defaultEnabled && !state.updating, .innerItem))
                    index += 1
                }
            }
        }
        
        entries.append(.section(sectionId, 20))
        sectionId += 1
        
        if let initialParticipant = initialParticipant, case let .member(_, _, _, maybeBanInfo, _, _) = initialParticipant, let banInfo = maybeBanInfo, let initialBannedBy = initialBannedBy {
            entries.append(.timeout(sectionId, index, strings().groupPermissionDuration, currentTimeoutString, .firstItem))
            index += 1
            entries.append(.delete(sectionId, index, strings().groupPermissionDelete, .lastItem))
            index += 1
            entries.append(.exceptionInfo(sectionId, index, strings().groupPermissionAddedInfo(initialBannedBy.displayTitle, stringForRelativeSymbolicTimestamp(relativeTimestamp: banInfo.timestamp, relativeTo: state.referenceTimestamp)), .textBottomItem))
            index += 1
        } else {
            entries.append(.timeout(sectionId, index, strings().groupPermissionDuration, currentTimeoutString, .singleItem))
            index += 1
        }
    }


    entries.append(.section(sectionId, 20))
    sectionId += 1
    
    return entries
}

private func restrictedInputDataEntries(_ entries: [RestrictedEntry], arguments: RestrictedControllerArguments) -> [InputDataEntry] {
    var result: [InputDataEntry] = []
    var autoIndex: Int32 = 0
    for entry in entries {
        switch entry {
        case let .section(sectionId, height):
            result.append(.sectionId(sectionId, type: .customModern(height)))
        default:
            let identifier: InputDataIdentifier
            switch entry.stableId {
            case .info:
                identifier = InputDataIdentifier("info")
            case let .right(flags):
                identifier = InputDataIdentifier("right_\(flags.rawValue)")
            case let .description(index):
                identifier = InputDataIdentifier("description_\(index)")
            case .timeout:
                identifier = InputDataIdentifier("timeout")
            case .exceptionInfo:
                identifier = InputDataIdentifier("exceptionInfo")
            case .delete:
                identifier = InputDataIdentifier("delete")
            case let .section(sectionId):
                identifier = InputDataIdentifier("section_\(sectionId)")
            }
            let sectionId: Int32
            switch entry {
            case let .info(s, _, _, _): sectionId = s
            case let .rightItem(s, _, _, _, _, _, _): sectionId = s
            case let .mediaRightItem(s, _, _, _, _, _, _): sectionId = s
            case let .description(s, _, _, _): sectionId = s
            case let .timeout(s, _, _, _, _): sectionId = s
            case let .exceptionInfo(s, _, _, _): sectionId = s
            case let .delete(s, _, _, _): sectionId = s
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

public func RestrictedModalController(_ context: any AccountContextProtocol, peerId: PeerId, memberId: PeerId, initialParticipant: ChannelParticipant?, updated: @escaping (TelegramChatBannedRights) -> Void, analyticsContext: AnalyticsContext? = nil) -> InputDataModalController {
    let origin = Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: analyticsContext ?? Analytics.shared.unresolvedContext()).restricting(peerId: memberId).restricting(peerId: initialParticipant?.peerId ?? memberId)
    let presentation = origin.beginPresentation()
    defer { presentation.end() }
    let updated: (TelegramChatBannedRights) -> Void = { [updated] rights in
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        updated(rights)
    }

    let initialState = RestrictedControllerState(referenceTimestamp: Int32(Date().timeIntervalSince1970), updatedFlags: nil, updatedTimeout: nil, updating: false)

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((RestrictedControllerState) -> RestrictedControllerState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }

    var close: (() -> Void)?

    let actionsDisposable = DisposableSet()

    let updateRightsDisposable = MetaDisposable()
    actionsDisposable.add(updateRightsDisposable)

    let peerView = Promise<PeerView>()
    peerView.set(context.account.viewTracker.peerView(peerId))

    let latestChannelView = Atomic<PeerView?>(value: nil)
    let latestMemberView = Atomic<PeerView?>(value: nil)
    let hasExceptionInfo = Atomic<Bool>(value: false)

    var okClicked: (() -> Void)?
    var getTableView: (() -> TableView?)?

    let arguments = RestrictedControllerArguments(context: context, toggleRight: { rights, value in
        let _ = (peerView.get()
            |> take(1)
            |> deliverOnMainQueue).start(next: { view in

                var defaultBannedRightsFlagsValue: TelegramChatBannedRightsFlags?
                guard let peer = view.peers[peerId] else {
                    return
                }
                if let channel = peer as? TelegramChannel, let initialRightFlags = channel.defaultBannedRights?.flags {
                    defaultBannedRightsFlagsValue = initialRightFlags
                } else if let group = peer as? TelegramGroup, let initialRightFlags = group.defaultBannedRights?.flags {
                    defaultBannedRightsFlagsValue = initialRightFlags
                }
                guard let defaultBannedRightsFlags = defaultBannedRightsFlagsValue else {
                    return
                }
                updateState { state in
                    var state = state
                    var effectiveRightsFlags: TelegramChatBannedRightsFlags
                    if let updatedFlags = state.updatedFlags {
                        effectiveRightsFlags = updatedFlags
                    } else if let initialParticipant = initialParticipant, case let .member(_, _, _, banInfo?, _, _) = initialParticipant {
                        effectiveRightsFlags = banInfo.rights.flags
                    } else {
                        effectiveRightsFlags = defaultBannedRightsFlags
                    }
                    if value {
                        effectiveRightsFlags.remove(rights)
                        effectiveRightsFlags = effectiveRightsFlags.subtracting(groupPermissionDependencies(rights))
                    } else {
                        effectiveRightsFlags.insert(rights)
                        effectiveRightsFlags = effectiveRightsFlags.union(groupPermissionDependencies(rights))
                    }
                    state.updatedFlags = effectiveRightsFlags
                    return state
                }
            })
    }, changeUntil: {
        guard let tableView = getTableView?() else { return }

        if let index = tableView.index(hash: InputDataEntryId.custom(InputDataIdentifier("timeout"))) {

            let applyValue: (Int32?) -> Void = { value in
                updateState { state in
                    var state = state
                    state.updatedTimeout = value
                    return state
                }
            }

            let intervals: [Int32] = [
                1 * 60 * 60 * 24,
                7 * 60 * 60 * 24,
                30 * 60 * 60 * 24
            ]
            if let view = (tableView.viewNecessary(at: index) as? GeneralInteractedRowView)?.textView {
                var items:[ContextMenuItem] = []
                for interval in intervals {
                    items.append(ContextMenuItem(timeIntervalString(Int(interval)), handler: {
                        applyValue(initialState.referenceTimestamp + interval)
                    }))
                }
                items.append(ContextMenuItem(strings().channelBanForever, handler: {
                    applyValue(Int32.max)
                }))

                let menu = ContextMenu()
                for item in items {
                    menu.addItem(item)
                }

                if let event = NSApp.currentEvent {
                    let value = AppMenu(menu: menu)
                    value.show(event: event, view: view)
                }
            }
        }
    }, alertError: {
        let _ = (peerView.get()
            |> take(1)
            |> deliverOnMainQueue).start(next: { view in
                if let peer = peerViewMainPeer(view) {
                    showModalText(for: context.window, text: peer.isSupergroup || peer.isGroup ? strings().channelExceptionDisabledOptionGroup : strings().channelExceptionDisabledOptionChannel)
                }
            })
    }, deleteException: {
        updated(TelegramChatBannedRights(flags: TelegramChatBannedRightsFlags(rawValue: 0), untilDate: 0))
        close?()
    }, toggleMedia: {
        updateState { current in
            var current = current
            current.mediaRevealed = !current.mediaRevealed
            return current
        }
    })

    var keys: [PostboxViewKey] = [.peer(peerId: peerId, components: .all), .peer(peerId: memberId, components: .all)]
    if let banInfo = initialParticipant?.banInfo {
        keys.append(.peer(peerId: banInfo.restrictedBy, components: []))
    }
    let combinedView = context.account.postbox.combinedView(keys: keys)

    let signal: Signal<InputDataSignalValue, NoError> = combineLatest(queue: prepareQueue, appearanceSignal, statePromise.get(), combinedView) |> map { appearance, state, combinedView in

        let channelView = combinedView.views[.peer(peerId: peerId, components: .all)] as! PeerView
        let memberView = combinedView.views[.peer(peerId: memberId, components: .all)] as! PeerView
        _ = latestChannelView.swap(channelView)
        _ = latestMemberView.swap(memberView)
        var initialBannedByPeer: Peer?
        if let banInfo = initialParticipant?.banInfo {
            initialBannedByPeer = (combinedView.views[.peer(peerId: banInfo.restrictedBy, components: [])] as? PeerView)?.peers[banInfo.restrictedBy]
        }

        let entries = restrictedEntries(state: state, accountPeerId: context.account.peerId, channelView: channelView, memberView: memberView, initialParticipant: initialParticipant, initialBannedBy: initialBannedByPeer)
        let hasException = entries.contains(where: {
            if case .exceptionInfo = $0 { return true }
            return false
        })
        _ = hasExceptionInfo.swap(hasException)

        return InputDataSignalValue(entries: restrictedInputDataEntries(entries, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().groupPermissionTitle, getBackgroundColor: {
        theme.colors.listBackground
    })
    controller.analyticsContext = origin
    controller.analyticsScreen = .peerInfoPermissionsException

    getTableView = { [weak controller] in
        return controller?.tableView
    }

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    controller.afterTransaction = { controller in
        if let memberView = latestMemberView.with({ $0 }) {
            controller.modal?.interactions?.updateDone({ button in
                if let peer = peerViewMainPeer(memberView) as? TelegramChannel {
                    button.isEnabled = peer.hasPermission(.banMembers)
                }
            })
        }
        controller.modal?.interactions?.updateCancel({ button in
            if hasExceptionInfo.with({ $0 }) {
                button.set(text: strings().groupPermissionDelete, for: .Normal)
                button.set(color: theme.colors.redUI, for: .Normal)
            } else {
                button.set(text: "", for: .Normal)
            }
        })
    }

    okClicked = {
        let _ = (peerView.get()
            |> take(1)
            |> deliverOnMainQueue).start(next: { view in

            var defaultBannedRightsFlagsValue: TelegramChatBannedRightsFlags?
            guard let peer = view.peers[peerId] else {
                return
            }
            if let channel = peer as? TelegramChannel, let initialRightFlags = channel.defaultBannedRights?.flags {
                defaultBannedRightsFlagsValue = initialRightFlags
            } else if let group = peer as? TelegramGroup, let initialRightFlags = group.defaultBannedRights?.flags {
                defaultBannedRightsFlagsValue = initialRightFlags
            }
            guard let defaultBannedRightsFlags = defaultBannedRightsFlagsValue else {
                return
            }

            guard let channelView = latestChannelView.with({ $0 }) else { return }

            var resolvedRights: TelegramChatBannedRights?
            if let initialParticipant = initialParticipant {
                var updateFlags: TelegramChatBannedRightsFlags?
                var updateTimeout: Int32?
                updateState { current in
                    updateFlags = current.updatedFlags
                    updateTimeout = current.updatedTimeout
                    return current
                }

                if updateFlags == nil && updateTimeout == nil {
                    if case let .member(_, _, _, maybeBanInfo, _, _) = initialParticipant {
                        if maybeBanInfo == nil {
                            updateFlags = defaultBannedRightsFlags
                            updateTimeout = Int32.max
                        }
                    }
                }

                if updateFlags != nil || updateTimeout != nil {
                    let currentRightsFlags: TelegramChatBannedRightsFlags
                    if let updatedFlags = updateFlags {
                        currentRightsFlags = updatedFlags
                    } else if case let .member(_, _, _, maybeBanInfo, _, _) = initialParticipant, let banInfo = maybeBanInfo {
                        currentRightsFlags = banInfo.rights.flags
                    } else {
                        currentRightsFlags = defaultBannedRightsFlags
                    }

                    let currentTimeout: Int32
                    if let updateTimeout = updateTimeout {
                        currentTimeout = updateTimeout
                    } else if case let .member(_, _, _, maybeBanInfo, _, _) = initialParticipant, let banInfo = maybeBanInfo {
                        currentTimeout = banInfo.rights.untilDate
                    } else {
                        currentTimeout = Int32.max
                    }

                    resolvedRights = TelegramChatBannedRights(flags: completeRights(currentRightsFlags), untilDate: currentTimeout)
                }
            } else if let _ = channelView.peers[channelView.peerId] as? TelegramChannel {
                var updateFlags: TelegramChatBannedRightsFlags?
                var updateTimeout: Int32?
                updateState { state in
                    var state = state
                    updateFlags = state.updatedFlags
                    updateTimeout = state.updatedTimeout
                    state.updating = false
                    return state
                }

                if updateFlags == nil {
                    updateFlags = defaultBannedRightsFlags
                }
                if updateTimeout == nil {
                    updateTimeout = Int32.max
                }

                if let updateFlags = updateFlags, let updateTimeout = updateTimeout {
                   resolvedRights = TelegramChatBannedRights(flags: completeRights(updateFlags), untilDate: updateTimeout)
                }
            }

            var previousRights: TelegramChatBannedRights?
            if let initialParticipant = initialParticipant, case let .member(_, _, _, banInfo, _, _) = initialParticipant, banInfo != nil {
                previousRights = banInfo?.rights
            }
            if let resolvedRights = resolvedRights, previousRights != resolvedRights {
                let cleanResolvedRightsFlags = resolvedRights.flags.union(defaultBannedRightsFlags)
                let cleanResolvedRights = TelegramChatBannedRights(flags: cleanResolvedRightsFlags, untilDate: resolvedRights.untilDate)

                if cleanResolvedRights.flags.isEmpty && previousRights == nil {
                    close?()
                } else {
                    updated(cleanResolvedRights)
                }
            }
        })
    }

    controller.returnKeyInvocation = { _, _ in
        close?()
        okClicked?()
        return .nothing
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().modalApply, accept: {
        close?()
        okClicked?()
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(350, 360))
    modalController.analyticsContext = origin

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    controller.centerModalHeader = ModalHeaderData(title: strings().groupPermissionTitle)

    close = { [weak modalController] in
        modalController?.close()
    }

    return modalController
}
