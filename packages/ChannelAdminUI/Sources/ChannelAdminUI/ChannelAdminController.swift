import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import TelegramTheme
import Localization
import Strings
import GeneralRows
import InputDataUI
import ShortPeerRow
import AlertsUI
import AppAnalytics

private func areAllAdminRightsEnabled(_ flags: TelegramChatAdminRightsFlags, peer: EnginePeer, except: TelegramChatAdminRightsFlags) -> Bool {
    return TelegramChatAdminRightsFlags.peerSpecific(peer: peer).subtracting(except).intersection(flags) == TelegramChatAdminRightsFlags.peerSpecific(peer: peer).subtracting(except)
}

private struct AdminSubPermission: Equatable {
    var title: String
    var flags: TelegramChatAdminRightsFlags
    var isSelected: Bool
    var isEnabled: Bool
}

let messageRelatedFlags: [TelegramChatAdminRightsFlags] = [
    .canPostMessages,
    .canEditMessages,
    .canDeleteMessages
]

let storiesRelatedFlags: [TelegramChatAdminRightsFlags] = [
    .canPostStories,
    .canEditStories,
    .canDeleteStories
]


enum RightsItem: Equatable, Hashable {
    enum Sub {
        case messages
        case stories
    }
    
    case direct(TelegramChatAdminRightsFlags)
    case sub(Sub, [TelegramChatAdminRightsFlags])
}


private final class ChannelAdminControllerArguments {
    let context: any AccountContextProtocol
    let toggleRight: (RightsItem, TelegramChatAdminRightsFlags, Bool) -> Void
    let toggleIsOptionExpanded: (RightsItem.Sub) -> Void
    let dismissAdmin: () -> Void
    let cantEditError: () -> Void
    let transferOwnership:()->Void
    let updateRank:(String)->Void
    let toggleProcessJoinRequests: (Bool) -> Void
    init(context: any AccountContextProtocol, toggleRight: @escaping (RightsItem, TelegramChatAdminRightsFlags, Bool) -> Void, toggleIsOptionExpanded: @escaping(RightsItem.Sub) -> Void, dismissAdmin: @escaping () -> Void, cantEditError: @escaping() -> Void, transferOwnership: @escaping()->Void, updateRank: @escaping(String)->Void, toggleProcessJoinRequests: @escaping (Bool) -> Void) {
        self.context = context
        self.toggleRight = toggleRight
        self.toggleIsOptionExpanded = toggleIsOptionExpanded
        self.dismissAdmin = dismissAdmin
        self.cantEditError = cantEditError
        self.transferOwnership = transferOwnership
        self.updateRank = updateRank
        self.toggleProcessJoinRequests = toggleProcessJoinRequests
    }
}

private enum ChannelAdminEntryStableId: Hashable {
    case info
    case right(RightsItem)
    case subRight(RightsItem)
    case description(Int32)
    case changeOwnership
    case section(Int32)
    case roleHeader
    case role
    case roleDesc
    case dismiss
    case processJoinRequests
    func hash(into hasher: inout Hasher) {
        hasher.combine(0)
    }

}

private enum ChannelAdminEntry: TableItemListNodeEntry {
    case info(Int32, PeerEquatable, TelegramUserPresence?, GeneralViewType)
    case rightItem(Int32, Int, String, RightsItem, TelegramChatAdminRightsFlags, Bool, Bool, GeneralViewType)
    case subRightItem(Int32, Int, String, RightsItem, TelegramChatAdminRightsFlags, Bool, Bool, GeneralViewType)
    case roleHeader(Int32, GeneralViewType)
    case roleDesc(Int32, GeneralViewType)
    case role(Int32, String, String, GeneralViewType)
    case description(Int32, Int32, String, GeneralViewType)
    case changeOwnership(Int32, Int32, String, GeneralViewType)
    case dismiss(Int32, Int32, String, GeneralViewType)
    case processJoinRequests(Int32, Bool, GeneralViewType)
    case section(Int32, CGFloat)


    var stableId: ChannelAdminEntryStableId {
        switch self {
        case .info:
            return .info
        case let .rightItem(_, _, _, right, _, _, _, _):
            return .right(right)
        case let .subRightItem(_, _, _, right, _, _, _, _):
            return .subRight(right)
        case .description(_, let index, _, _):
            return .description(index)
        case .changeOwnership:
            return .changeOwnership
        case .dismiss:
            return .dismiss
        case .processJoinRequests:
            return .processJoinRequests
        case .roleHeader:
            return .roleHeader
        case .roleDesc:
            return .roleDesc
        case .role:
            return .role
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
        case let .changeOwnership(sectionId, index, _, _):
            return (sectionId * 1000) + index
            case let .dismiss(sectionId, index, _, _):
            return (sectionId * 1000) + index
        case .rightItem(let sectionId, let index, _, _, _, _, _, _):
            return (sectionId * 1000) + Int32(index) + 10
        case .subRightItem(let sectionId, let index, _, _, _, _, _, _):
            return (sectionId * 1000) + Int32(index) + 10
        case let .processJoinRequests(sectionId, _, _):
            return (sectionId * 1000) + 5
        case let .roleHeader(sectionId, _):
             return (sectionId * 1000)
        case let .role(sectionId, _, _, _):
            return (sectionId * 1000) + 1
        case let .roleDesc(sectionId, _):
            return (sectionId * 1000) + 2
        case let .section(sectionId, _):
            return (sectionId + 1) * 1000 - sectionId
        }
    }
    
    static func <(lhs: ChannelAdminEntry, rhs: ChannelAdminEntry) -> Bool {
        return lhs.index < rhs.index
    }
    
    func item(_ arguments: ChannelAdminControllerArguments, initialSize: NSSize) -> TableRowItem {
        switch self {
        case let .section(_, height):
            return GeneralRowItem(initialSize, height: height, stableId: stableId, viewType: .separator)
        case let .info(_, peer, presence, viewType):
            let peer = peer.peer
            var string:String = peer.isBot ? strings().presenceBot : strings().peerStatusRecently
            var color:NSColor = theme.colors.grayText
            if let presence = presence, !peer.isBot {
                let timestamp = CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970
                (string, _, color) = stringAndActivityForUserPresence(presence, timeDifference: arguments.context.timeDifference, relativeTo: Int32(timestamp))
            }
            return ShortPeerRowItem(initialSize, peer: peer, account: arguments.context.account, context: arguments.context, stableId: stableId, enabled: true, height: 60, photoSize: NSMakeSize(40, 40), statusStyle: ControlStyle(font: .normal(.title), foregroundColor: color), status: string, inset: NSEdgeInsets(left: 20, right: 20), viewType: viewType, action: {})
        case let .rightItem(_, _, name, right, flags, value, enabled, viewType):
            
            let string: NSMutableAttributedString = NSMutableAttributedString()
            string.append(string: name, color: theme.colors.text, font: .normal(.title))
            
            switch right {
            case let .sub(_, subRights):
                let selectedCount = subRights.filter { flags.contains($0) }.count
                string.append(string: " \(selectedCount)/\(subRights.count)", color: theme.colors.text, font: .bold(.short))
            default:
                break
            }
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: name, nameAttributed: string, nameStyle: ControlStyle(font: .normal(.title), foregroundColor: enabled ? theme.colors.text : theme.colors.grayText), type: .switchable(value), viewType: viewType, action: {
                switch right {
                case .direct:
                    arguments.toggleRight(right, flags, !value)
                case let .sub(type, _):
                    arguments.toggleIsOptionExpanded(type)
                }
            }, enabled: enabled, switchAppearance: SwitchViewAppearance(backgroundColor: theme.colors.background, stateOnColor: enabled ? theme.colors.accent : theme.colors.accent.withAlphaComponent(0.6), stateOffColor: enabled ? theme.colors.redUI : theme.colors.redUI.withAlphaComponent(0.6), disabledColor: .grayBackground, borderColor: .clear), disabledAction: {
                arguments.cantEditError()
            }, switchAction: {
                arguments.toggleRight(right, flags, !value)
            })
        case let .subRightItem(_, _, name, right, flags, value, enabled, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: name, nameStyle: ControlStyle(font: .normal(.title), foregroundColor: enabled ? theme.colors.text : theme.colors.grayText), type: .selectableLeft(value), viewType: viewType, action: {
                arguments.toggleRight(right, flags, !value)
            }, enabled: enabled, disabledAction: {
                arguments.cantEditError()
            })

        case let .changeOwnership(_, _, text, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: text, nameStyle: blueActionButton, type: .next, viewType: viewType, action: arguments.transferOwnership)
        case let .dismiss(_, _, text, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: text, nameStyle: redActionButton, type: .next, viewType: viewType, action: arguments.dismissAdmin)
        case let .processJoinRequests(_, value, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().channelAdminProcessJoinRequests, type: .switchable(value), viewType: viewType, action: {
                arguments.toggleProcessJoinRequests(!value)
            }, switchAction: {
                arguments.toggleProcessJoinRequests(!value)
            })
        case let .roleHeader(_, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: strings().channelAdminRoleHeader, viewType: viewType)
        case let .role(_, text, placeholder, viewType):
            return InputDataRowItem(initialSize, stableId: stableId, mode: .plain, error: nil, viewType: viewType, currentText: text, placeholder: nil, inputPlaceholder: placeholder, filter: { text in
                let filtered = text.filter { character -> Bool in
                    return !String(character).containsOnlyEmoji
                }
                return filtered
            }, updated: arguments.updateRank, limit: 16)
        case let .roleDesc(_, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: "", viewType: viewType)
        case let .description(_, _, name, viewType):
            return GeneralTextRowItem(initialSize, stableId: stableId, text: name, viewType: viewType)
        }
        //return TableRowItem(initialSize)
    }
}

private struct ChannelAdminControllerState: Equatable {
    var updatedFlags: TelegramChatAdminRightsFlags?
    var updating: Bool
    var editable:Bool
    var rank:String?
    var initialRank:String?
    var expandedPermissions: Set<RightsItem.Sub> = Set()
    var processJoinRequests: Bool = false
    init(updatedFlags: TelegramChatAdminRightsFlags? = nil, updating: Bool = false, editable: Bool = false, rank: String?, initialRank: String?, expandedPermissions: Set<RightsItem.Sub>, processJoinRequests: Bool = false) {
        self.updatedFlags = updatedFlags
        self.updating = updating
        self.editable = editable
        self.rank = rank
        self.initialRank = initialRank
        self.expandedPermissions = expandedPermissions
        self.processJoinRequests = processJoinRequests
    }
    
    func withUpdatedUpdatedFlags(_ updatedFlags: TelegramChatAdminRightsFlags?) -> ChannelAdminControllerState {
        return ChannelAdminControllerState(updatedFlags: updatedFlags, updating: self.updating, editable: self.editable, rank: self.rank, initialRank: self.initialRank, expandedPermissions: self.expandedPermissions, processJoinRequests: self.processJoinRequests)
    }

    func withUpdatedEditable(_ editable:Bool) -> ChannelAdminControllerState {
        return ChannelAdminControllerState(updatedFlags: updatedFlags, updating: self.updating, editable: editable, rank: self.rank, initialRank: self.initialRank, expandedPermissions: self.expandedPermissions, processJoinRequests: self.processJoinRequests)
    }

    func withUpdatedUpdating(_ updating: Bool) -> ChannelAdminControllerState {
        return ChannelAdminControllerState(updatedFlags: self.updatedFlags, updating: updating, editable: self.editable, rank: self.rank, initialRank: self.initialRank, expandedPermissions: self.expandedPermissions, processJoinRequests: self.processJoinRequests)
    }

    func withUpdatedRank(_ rank: String?) -> ChannelAdminControllerState {
        return ChannelAdminControllerState(updatedFlags: self.updatedFlags, updating: updating, editable: self.editable, rank: rank, initialRank: self.initialRank, expandedPermissions: self.expandedPermissions, processJoinRequests: self.processJoinRequests)
    }
}

public func stringForRight(right: TelegramChatAdminRightsFlags, isGroup: Bool, defaultBannedRights: TelegramChatBannedRights?, isBot: Bool = false) -> String {
    if right.contains(.canChangeInfo) {
        return isGroup ? strings().groupEditAdminPermissionChangeInfo : strings().channelEditAdminPermissionChangeInfo
    } else if right.contains(.canPostMessages) {
        return strings().channelEditAdminPermissionPostMessages
    } else if right.contains(.canEditMessages) {
        return strings().channelEditAdminPermissionEditMessages
    } else if right.contains(.canDeleteMessages) {
        return strings().channelEditAdminPermissionDeleteMessages
    } else if right.contains(.canBanUsers) {
        return strings().channelEditAdminPermissionBanUsers
    } else if right.contains(.canInviteUsers) {
        if isGroup {
            if let defaultBannedRights = defaultBannedRights, defaultBannedRights.flags.contains(.banAddMembers) {
                return strings().channelEditAdminPermissionInviteMembers
            } else {
                return strings().channelEditAdminPermissionInviteViaLink
            }
        } else {
            return strings().channelEditAdminPermissionInviteSubscribers
        }

    } else if right.contains(.canManageDirect) {
        return strings().channelEditAdminPermissionManageDirect
    } else if right.contains(.canManageWelcomeMessages) {
        return isBot ? strings().channelEditAdminPermissionSendWelcomeMessages : strings().channelEditAdminPermissionManageWelcomeMessages
    } else if right.contains(.canPinMessages) {
        return strings().channelEditAdminPermissionPinMessages
    } else if right.contains(.canAddAdmins) {
        return strings().channelEditAdminPermissionAddNewAdmins
    } else if right.contains(.canBeAnonymous) {
        return strings().channelEditAdminPermissionAnonymous
    } else if right.contains(.canManageCalls) {
        return strings().channelEditAdminManageCalls
    } else if right.contains(.canManageTopics) {
        return strings().channelEditAdminManageTopics
    } else if right.contains(.canPostStories) {
        return strings().channelEditAdminPostStories
    } else if right.contains(.canDeleteStories) {
        return strings().channelEditAdminDeleteStories
    } else if right.contains(.canEditStories) {
        return strings().channelEditAdminEditStories
    } else {
        return ""
    }
}

private func canEditAdminRights(accountPeerId: PeerId, channelView: PeerView, initialParticipant: ChannelParticipant?) -> Bool {
    if let channel = channelView.peers[channelView.peerId] as? TelegramChannel {
        if channel.flags.contains(.isCreator) {
            return true
        } else if let initialParticipant = initialParticipant {
            switch initialParticipant {
            case .creator:
                return false
            case let .member(_, _, adminInfo, _, _, _):
                if let adminInfo = adminInfo {
                    return adminInfo.canBeEditedByAccountPeer || adminInfo.promotedBy == accountPeerId
                } else {
                    return channel.hasPermission(.addAdmins)
                }
            }
        } else {
            return channel.hasPermission(.addAdmins)
        }
    } else if let group = channelView.peers[channelView.peerId] as? TelegramGroup {
        if case .creator = group.role {
            return true
        } else {
            return false
        }
    } else {
        return false
    }
}


private func channelAdminControllerEntries(state: ChannelAdminControllerState, accountPeerId: PeerId, channelView: PeerView, adminView: PeerView, initialParticipant: ChannelParticipant?) -> [ChannelAdminEntry] {
    var entries: [ChannelAdminEntry] = []
    
    var sectionId:Int32 = 1
    
    entries.append(.section(sectionId, 10))
    sectionId += 1
    
    var descId: Int32 = 0
    
    var addAdminsEnabled: Bool = false
    if let channel = channelView.peers[channelView.peerId] as? TelegramChannel, let admin = adminView.peers[adminView.peerId] {
        entries.append(.info(sectionId, .init(admin), adminView.peerPresences[admin.id] as? TelegramUserPresence, .singleItem))
        
        let isGroup: Bool
        let maskRightsFlags: TelegramChatAdminRightsFlags = .peerSpecific(peer: .init(channel))
        let rightsOrder: [RightsItem]
        
        switch channel.info {
        case .broadcast:
            isGroup = false
            rightsOrder = [
                .direct(.canChangeInfo),
                .sub(.messages, messageRelatedFlags),
                .sub(.stories, storiesRelatedFlags),
                .direct(.canManageDirect),
                .direct(.canInviteUsers),
                .direct(.canManageCalls),
                .direct(.canManageWelcomeMessages),
                .direct(.canAddAdmins)
            ]
        case .group:
            isGroup = true
            if channel.flags.contains(.isForum) {
                rightsOrder = [
                    .direct(.canChangeInfo),
                    .direct(.canDeleteMessages),
                    .direct(.canBanUsers),
                    .direct(.canInviteUsers),
                    .direct(.canPinMessages),
                    .direct(.canManageTopics),
                    .direct(.canManageCalls),
                    .direct(.canManageWelcomeMessages),
                    .direct(.canBeAnonymous),
                    .direct(.canAddAdmins)
                ]
            } else {
                rightsOrder = [
                    .direct(.canChangeInfo),
                    .direct(.canDeleteMessages),
                    .direct(.canBanUsers),
                    .direct(.canInviteUsers),
                    .direct(.canPinMessages),
                    .sub(.stories, storiesRelatedFlags),
                    .direct(.canManageCalls),
                    .direct(.canManageWelcomeMessages),
                    .direct(.canBeAnonymous),
                    .direct(.canAddAdmins)
                ]
            }
    }

        
        if canEditAdminRights(accountPeerId: accountPeerId, channelView: channelView, initialParticipant: initialParticipant) {
            
            var isCreator = false
            if let initialParticipant = initialParticipant, case .creator = initialParticipant {
                isCreator = true
            }
            
            if channel.isSupergroup {
                entries.append(.section(sectionId, 20))
                sectionId += 1
                let placeholder = isCreator ? strings().channelAdminRolePlaceholderOwner : strings().channelAdminRolePlaceholderAdmin
                entries.append(.roleHeader(sectionId, .textTopItem))
                entries.append(.role(sectionId, state.rank ?? "", placeholder, .singleItem))
                entries.append(.description(sectionId, descId, isCreator ? strings().channelAdminRoleOwnerDesc : strings().channelAdminRoleAdminDesc, .textBottomItem))
                descId += 1
            }
            entries.append(.section(sectionId, 20))
            sectionId += 1
            
           
            if (channel.isSupergroup) || channel.isChannel {
                if !isCreator || channel.isChannel {
                    entries.append(.description(sectionId, descId, strings().channelAdminWhatCanAdminDo, .textTopItem))
                    descId += 1
                }
               
                
                var accountUserRightsFlags: TelegramChatAdminRightsFlags
                if channel.flags.contains(.isCreator) {
                    accountUserRightsFlags = maskRightsFlags
                } else if let adminRights = channel.adminRights {
                    accountUserRightsFlags = maskRightsFlags.intersection(adminRights.rights)
                } else {
                    accountUserRightsFlags = []
                }
                
                let currentRightsFlags: TelegramChatAdminRightsFlags
                if let updatedFlags = state.updatedFlags {
                    currentRightsFlags = updatedFlags
                } else if let initialParticipant = initialParticipant, case let .member(_, _, maybeAdminRights, _, _, _) = initialParticipant, let adminRights = maybeAdminRights {
                    currentRightsFlags = adminRights.rights.rights
                } else if let adminRights = channel.adminRights {
                    currentRightsFlags = adminRights.rights.subtracting([.canAddAdmins])
                } else {
                    currentRightsFlags = accountUserRightsFlags.subtracting([.canAddAdmins])
                }
                
                if accountUserRightsFlags.contains(.canAddAdmins) {
                    addAdminsEnabled = currentRightsFlags.contains(.canAddAdmins)
                }
                
                var index = 0
                
                var list: [RightsItem] = []
                rightsLoop: for value in rightsOrder {
                    switch value {
                    case let .direct(right):
                        if !accountUserRightsFlags.contains(right) {
                            continue rightsLoop
                        }
                        list.append(value)
                    case let .sub(_, subRights):
                        let filteredSubRights = subRights.filter({ accountUserRightsFlags.contains($0) })
                        if filteredSubRights.isEmpty {
                            continue rightsLoop
                        }
                        list.append(value)
                    }
                

                }
                
                
                let showProcessJoinRequests = isGroup && (admin as? TelegramUser)?.botInfo?.flags.contains(.isGuardBot) == true
                let lastRightIndex = list.count - 1

                for (i, rights) in list.enumerated() {
                    let rightViewType: GeneralViewType
                    if showProcessJoinRequests && i == lastRightIndex {
                        rightViewType = .innerItem
                    } else {
                        rightViewType = bestGeneralViewType(list, for: i)
                    }
                    switch rights {
                    case let .direct(right):
                        entries.append(.rightItem(sectionId, index, stringForRight(right: right, isGroup: isGroup, defaultBannedRights: channel.defaultBannedRights, isBot: admin.isBot), rights, currentRightsFlags, currentRightsFlags.contains(right), !state.updating, rightViewType))
                        index += 1
                    case let .sub(type, subRights):

                        let isSelected = subRights.allSatisfy({ currentRightsFlags.contains($0) })
                        let isExpanded = state.expandedPermissions.contains(type)

                        let title: String
                        switch type {
                        case .messages:
                            title = strings().channelEditAdminPermissionManageMessages
                        case .stories:
                            title = strings().channelEditAdminPermissionManageStories
                        }
                        entries.append(.rightItem(sectionId, index, title, rights, currentRightsFlags, isSelected, !state.updating, rightViewType))

                        if isExpanded {
                            for right in subRights {
                                entries.append(.subRightItem(sectionId, index, stringForRight(right: right, isGroup: isGroup, defaultBannedRights: channel.defaultBannedRights, isBot: admin.isBot), .direct(right), currentRightsFlags, currentRightsFlags.contains(right), !state.updating, .innerItem))
                            }
                        }
                    }
                }

                if showProcessJoinRequests {
                    entries.append(.processJoinRequests(sectionId, state.processJoinRequests, .lastItem))
                    entries.append(.description(sectionId, descId, strings().channelAdminProcessJoinRequestsInfo, .textBottomItem))
                    descId += 1
                } else if !isCreator || channel.isChannel {
                    entries.append(.description(sectionId, descId, addAdminsEnabled ? strings().channelAdminAdminAccess : strings().channelAdminAdminRestricted, .textBottomItem))
                    descId += 1
                }

                if channel.flags.contains(.isCreator), !admin.isBot  {
                    if admin.id != accountPeerId {
                        
                        var canTransfer = false
                        if admin.botInfo == nil && !admin.isDeleted && channel.flags.contains(.isCreator) && areAllAdminRightsEnabled(currentRightsFlags, peer: .channel(channel), except: .canBeAnonymous) {
                            canTransfer = true
                        }

                        if (channel.isChannel || channel.isSupergroup) && canTransfer {
                            entries.append(.section(sectionId, 20))
                            sectionId += 1
                            entries.append(.changeOwnership(sectionId, descId, channel.isChannel ? strings().channelAdminTransferOwnershipChannel : strings().channelAdminTransferOwnershipGroup, .singleItem))
                        }
                    }
                }
            }

            
        } else if let initialParticipant = initialParticipant, case let .member(_, _, maybeAdminInfo, _, _, _) = initialParticipant, let adminInfo = maybeAdminInfo {
            
            entries.append(.section(sectionId, 20))
            sectionId += 1
            
            if let rank = state.rank {
                entries.append(.section(sectionId, 20))
                sectionId += 1
                entries.append(.roleHeader(sectionId, .textTopItem))
                entries.append(.description(sectionId, descId, rank, .textTopItem))
                descId += 1
                entries.append(.section(sectionId, 20))
                sectionId += 1
            }
            
            var index = 0
            for (i, rights) in rightsOrder.enumerated() {
                switch rights {
                case let .direct(right):
                    entries.append(.rightItem(sectionId, index, stringForRight(right: right, isGroup: isGroup, defaultBannedRights: channel.defaultBannedRights, isBot: admin.isBot), rights, adminInfo.rights.rights, adminInfo.rights.rights.contains(right), false, bestGeneralViewType(rightsOrder, for: i)))
                    index += 1
                case let .sub(type, subRights):
                    let currentRightsFlags = adminInfo.rights.rights
                    let isSelected = subRights.allSatisfy({ currentRightsFlags.contains($0) })
                    let isExpanded = state.expandedPermissions.contains(type)

                    let title: String
                    switch type {
                    case .messages:
                        title = strings().channelEditAdminPermissionManageMessages
                    case .stories:
                        title = strings().channelEditAdminPermissionManageStories
                    }
                    entries.append(.rightItem(sectionId, index, title, rights, currentRightsFlags, isSelected, false, bestGeneralViewType(rightsOrder, for: i)))
                    
                    if isExpanded {
                        for right in subRights {
                            entries.append(.subRightItem(sectionId, index, stringForRight(right: right, isGroup: isGroup, defaultBannedRights: channel.defaultBannedRights, isBot: admin.isBot), .direct(right), currentRightsFlags, currentRightsFlags.contains(right), false, .innerItem))
                        }
                    }
                }
            }
            entries.append(.description(sectionId, descId, strings().channelAdminCantEditRights, .textBottomItem))
            descId += 1
        } else if let initialParticipant = initialParticipant, case .creator = initialParticipant {
            
            entries.append(.section(sectionId, 20))
            sectionId += 1
            
            if let rank = state.rank {
                entries.append(.section(sectionId, 20))
                sectionId += 1
                entries.append(.roleHeader(sectionId, .textTopItem))
                entries.append(.description(sectionId, descId, rank, .textBottomItem))
                descId += 1
                entries.append(.section(sectionId, 20))
                sectionId += 1
            }
            
            var index = 0
            for (i, rights) in rightsOrder.enumerated() {
                switch rights {
                case let .direct(right):
                    entries.append(.rightItem(sectionId, index, stringForRight(right: right, isGroup: isGroup, defaultBannedRights: channel.defaultBannedRights, isBot: admin.isBot), rights, maskRightsFlags, true, false, bestGeneralViewType(rightsOrder, for: i)))
                    index += 1
                case let .sub(type, subRights):
                    let currentRightsFlags = maskRightsFlags
                    _ = subRights.allSatisfy({ currentRightsFlags.contains($0) })
                    let isExpanded = state.expandedPermissions.contains(type)

                    let title: String
                    switch type {
                    case .messages:
                        title = strings().channelEditAdminPermissionManageMessages
                    case .stories:
                        title = strings().channelEditAdminPermissionManageStories
                    }
                    entries.append(.rightItem(sectionId, index, title, rights, currentRightsFlags, true, false, bestGeneralViewType(rightsOrder, for: i)))
                    
                    if isExpanded {
                        for right in subRights {
                            entries.append(.subRightItem(sectionId, index, stringForRight(right: right, isGroup: isGroup, defaultBannedRights: channel.defaultBannedRights, isBot: admin.isBot), .direct(right), currentRightsFlags, true, false, .innerItem))
                        }
                    }
                }
            }
            entries.append(.description(sectionId, descId, strings().channelAdminCantEditRights, .textBottomItem))
            descId += 1
        }
        
        
        
    } else if let group = channelView.peers[channelView.peerId] as? TelegramGroup, let admin = adminView.peers[adminView.peerId] {
        entries.append(.info(sectionId, .init(admin), adminView.peerPresences[admin.id] as? TelegramUserPresence, .singleItem))

        var isCreator = false
        if let initialParticipant = initialParticipant, case .creator = initialParticipant {
            isCreator = true
        }
        
        let placeholder = isCreator ? strings().channelAdminRolePlaceholderOwner : strings().channelAdminRolePlaceholderAdmin
        
        
        entries.append(.section(sectionId, 20))
        sectionId += 1
        
        entries.append(.roleHeader(sectionId, .textTopItem))
        entries.append(.role(sectionId, state.rank ?? "", placeholder, .singleItem))
        entries.append(.description(sectionId, descId, isCreator ? strings().channelAdminRoleOwnerDesc : strings().channelAdminRoleAdminDesc, .textBottomItem))
        descId += 1
        
        entries.append(.section(sectionId, 20))
        sectionId += 1
        
        if !isCreator {
            entries.append(.description(sectionId, descId, strings().channelAdminWhatCanAdminDo, .textTopItem))
            descId += 1
            
            let isGroup = true
            let maskRightsFlags: TelegramChatAdminRightsFlags = .internal_groupSpecific
            let rightsOrder: [RightsItem] = [
                .direct(.canChangeInfo),
                .direct(.canDeleteMessages),
                .direct(.canBanUsers),
                .direct(.canInviteUsers),
                .direct(.canManageCalls),
                .direct(.canManageWelcomeMessages),
                .direct(.canPinMessages),
                .direct(.canBeAnonymous),
                .direct(.canAddAdmins)
            ]
            
            let accountUserRightsFlags: TelegramChatAdminRightsFlags = maskRightsFlags
            
            let currentRightsFlags: TelegramChatAdminRightsFlags
            if let updatedFlags = state.updatedFlags {
                currentRightsFlags = updatedFlags
            } else if let initialParticipant = initialParticipant, case let .member(_, _, maybeAdminRights, _, _, _) = initialParticipant, let adminRights = maybeAdminRights {
                currentRightsFlags = adminRights.rights.rights.subtracting(.canAddAdmins)
            } else {
                currentRightsFlags = accountUserRightsFlags.subtracting([.canAddAdmins, .canBeAnonymous])
            }
            
            var index = 0
            
            var list: [RightsItem] = []
            for rights in rightsOrder {
                switch rights {
                case let .direct(right):
                    if accountUserRightsFlags.contains(right) {
                        list.append(rights)
                    }
                case let .sub(_, subRights):
                    let filteredSubRights = subRights.filter({ accountUserRightsFlags.contains($0) })
                    if filteredSubRights.isEmpty {
                        continue
                    }
                    list.append(rights)
                }
            }
            
            
            let showProcessJoinRequests = (admin as? TelegramUser)?.botInfo?.flags.contains(.isGuardBot) == true
            let lastRightIndex = list.count - 1

            for (i, rights) in list.enumerated() {
                let rightViewType: GeneralViewType
                if showProcessJoinRequests && i == lastRightIndex {
                    rightViewType = .innerItem
                } else {
                    rightViewType = bestGeneralViewType(list, for: i)
                }
                switch rights {
                case let .direct(right):
                    entries.append(.rightItem(sectionId, index, stringForRight(right: right, isGroup: isGroup, defaultBannedRights: group.defaultBannedRights, isBot: admin.isBot), rights, currentRightsFlags, currentRightsFlags.contains(right), !state.updating, rightViewType))
                    index += 1
                case .sub(_, _):
                    break
                }
            }

            if showProcessJoinRequests {
                entries.append(.processJoinRequests(sectionId, state.processJoinRequests, .lastItem))
                entries.append(.description(sectionId, descId, strings().channelAdminProcessJoinRequestsInfo, .textBottomItem))
                descId += 1
            } else if accountUserRightsFlags.contains(.canAddAdmins) {
                entries.append(.description(sectionId, descId, currentRightsFlags.contains(.canAddAdmins) ? strings().channelAdminAdminAccess : strings().channelAdminAdminRestricted, .textBottomItem))
                descId += 1
            }
            
            if case .creator = group.role, !admin.isBot {
                if currentRightsFlags.contains(maskRightsFlags) {
                    if admin.id != accountPeerId {
                        entries.append(.section(sectionId, 20))
                        sectionId += 1
                        entries.append(.changeOwnership(sectionId, descId, strings().channelAdminTransferOwnershipGroup, .singleItem))
                    }
                }
            }
        }
    }
    
    var canDismiss: Bool = false
    if let channel = peerViewMainPeer(channelView) as? TelegramChannel {
        
        if let initialParticipant = initialParticipant {
            if channel.flags.contains(.isCreator) {
                canDismiss = initialParticipant.adminInfo != nil
            } else {
                switch initialParticipant {
                case .creator:
                    break
                case let .member(_, _, adminInfo, _, _, _):
                    if let adminInfo = adminInfo {
                        if adminInfo.promotedBy == accountPeerId || adminInfo.canBeEditedByAccountPeer {
                            canDismiss = true
                        }
                    }
                }
            }
        }
    } else if let group = peerViewMainPeer(channelView) as? TelegramGroup {
        canDismiss = group.groupAccess.isCreator
    }
    
    if canDismiss {
        entries.append(.section(sectionId, 20))
        sectionId += 1
        
        entries.append(.dismiss(sectionId, descId, strings().channelAdminDismiss, .singleItem))
        descId += 1
    }
    
    entries.append(.section(sectionId, 20))
    sectionId += 1
    
    return entries
}

private func getTransferErrorText(_ error: ChatOwnershipTransferError, isGroup: Bool) -> String? {
    var errorText: String? = nil
    switch error {
    case .generic:
        errorText = strings().unknownError
    case .tooMuchJoined:
        errorText = strings().inviteChannelsTooMuch
    case .authSessionTooFresh:
        errorText = strings().channelTransferOwnerErrorText
    case .twoStepAuthMissing:
        errorText = strings().channelTransferOwnerErrorText
    case .twoStepAuthTooFresh:
        errorText = strings().channelTransferOwnerErrorText
    case .invalidPassword:
        errorText = nil
    case .requestPassword:
        errorText = nil
    case .restricted, .userBlocked:
        errorText = isGroup ? strings().groupTransferOwnerErrorPrivacyRestricted : strings().channelTransferOwnerErrorPrivacyRestricted
    case .adminsTooMuch:
         errorText = isGroup ? strings().groupTransferOwnerErrorAdminsTooMuch : strings().channelTransferOwnerErrorAdminsTooMuch
    case .userPublicChannelsTooMuch:
        errorText = strings().channelTransferOwnerErrorPublicChannelsTooMuch
    case .limitExceeded:
        errorText = strings().loginFloodWait
    case .userLocatedGroupsTooMuch:
        errorText = strings().groupOwnershipTransferErrorLocatedGroupsTooMuch
    }
    
    return errorText
}

private func channelAdminInputDataEntries(_ entries: [ChannelAdminEntry], arguments: ChannelAdminControllerArguments) -> [InputDataEntry] {
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
            case let .right(item):
                identifier = InputDataIdentifier("right_\(item.hashValue)")
            case let .subRight(item):
                identifier = InputDataIdentifier("subRight_\(item.hashValue)")
            case let .description(index):
                identifier = InputDataIdentifier("description_\(index)")
            case .changeOwnership:
                identifier = InputDataIdentifier("changeOwnership")
            case let .section(sectionId):
                identifier = InputDataIdentifier("section_\(sectionId)")
            case .roleHeader:
                identifier = InputDataIdentifier("roleHeader")
            case .role:
                identifier = InputDataIdentifier("role")
            case .roleDesc:
                identifier = InputDataIdentifier("roleDesc")
            case .dismiss:
                identifier = InputDataIdentifier("dismiss")
            case .processJoinRequests:
                identifier = InputDataIdentifier("processJoinRequests")
            }
            let sectionId: Int32
            switch entry {
            case let .info(s, _, _, _): sectionId = s
            case let .rightItem(s, _, _, _, _, _, _, _): sectionId = s
            case let .subRightItem(s, _, _, _, _, _, _, _): sectionId = s
            case let .roleHeader(s, _): sectionId = s
            case let .roleDesc(s, _): sectionId = s
            case let .role(s, _, _, _): sectionId = s
            case let .description(s, _, _, _): sectionId = s
            case let .changeOwnership(s, _, _, _): sectionId = s
            case let .dismiss(s, _, _, _): sectionId = s
            case let .processJoinRequests(s, _, _): sectionId = s
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

public func ChannelAdminModalController<Context: AccountContextProtocol>(_ context: Context, peerId: PeerId, adminId: PeerId, initialParticipant: ChannelParticipant?, updated: @escaping (TelegramChatAdminRights?) -> Void, upgradedToSupergroup: @escaping (PeerId, @escaping () -> Void) -> Void, analyticsContext: AnalyticsContext? = nil) -> InputDataModalController {
    let origin = Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: analyticsContext ?? Analytics.shared.unresolvedContext()).restricting(peerId: adminId).restricting(peerId: initialParticipant?.peerId ?? adminId)
    let presentation = origin.beginPresentation()
    defer { presentation.end() }
    let updated: (TelegramChatAdminRights?) -> Void = { [updated] rights in
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        updated(rights)
    }
    let upgradedToSupergroup: (PeerId, @escaping () -> Void) -> Void = { [upgradedToSupergroup] peerId, completion in
        let targetOrigin = origin.restricting(peerId: peerId)
        let presentation = targetOrigin.beginPresentation()
        defer { presentation.end() }
        upgradedToSupergroup(peerId) {
            let presentation = targetOrigin.beginPresentation()
            defer { presentation.end() }
            completion()
        }
    }

    let combinedPromise: Promise<CombinedView> = Promise()

    var peerId = peerId

    let initialValue = ChannelAdminControllerState(rank: initialParticipant?.rank, initialRank: initialParticipant?.rank, expandedPermissions: Set())
    let stateValue = Atomic(value: initialValue)
    let statePromise = ValuePromise(initialValue, ignoreRepeated: true)
    let updateState: ((ChannelAdminControllerState) -> ChannelAdminControllerState) -> Void = { f in
        statePromise.set(stateValue.modify { f($0) })
    }

    var close: (() -> Void)?

    let actionsDisposable = DisposableSet()

    let updateRightsDisposable = MetaDisposable()
    actionsDisposable.add(updateRightsDisposable)

    actionsDisposable.add(context.account.postbox.transaction { transaction in
        var canEdit = false
        if let channel = transaction.getPeer(peerId) as? TelegramChannel {
            if channel.flags.contains(.isCreator) {
                canEdit = true
            } else if let initialParticipant = initialParticipant {
                switch initialParticipant {
                case .creator:
                    canEdit = false
                case let .member(_, _, adminInfo, _, _, _):
                    if let adminInfo = adminInfo {
                        canEdit = adminInfo.canBeEditedByAccountPeer || adminInfo.promotedBy == context.account.peerId
                    } else {
                        canEdit = channel.hasPermission(.addAdmins)
                    }
                }
            } else {
                canEdit = channel.hasPermission(.addAdmins)
            }
        } else if let _ = transaction.getPeer(peerId) as? TelegramGroup {
            canEdit = true
        }
        var isCurrentGuardBot = false
        if let cachedData = transaction.getPeerCachedData(peerId: peerId) as? CachedChannelData {
            isCurrentGuardBot = cachedData.guardBotId == adminId
        }
        updateState { current in
            var current = current.withUpdatedEditable(canEdit)
            if isCurrentGuardBot {
                current.processJoinRequests = true
            }
            return current
        }
    }.start())

    let suppressDismiss = Atomic<Bool>(value: false)
    let dismissImpl: () -> Void = {
        if suppressDismiss.swap(false) {
            updateState { current in
                return current.withUpdatedUpdating(false)
            }
            return
        }
        close?()
    }

    var okClick: (() -> Void)?

    let latestChannelView = Atomic<PeerView?>(value: nil)
    let latestAdminView = Atomic<PeerView?>(value: nil)

    let handleAdminRightsError: (UpdateChannelAdminRightsError) -> Void = { error in
        updateState { $0.withUpdatedUpdating(false) }
        let isGroup = latestChannelView.with { view -> Bool in
            guard let view, let peer = peerViewMainPeer(view) else { return true }
            return peer.isGroup || peer.isSupergroup
        }
        alert(for: context.window, info: channelAdminRightsErrorText(error, isGroup: isGroup))
    }

    let arguments = ChannelAdminControllerArguments(context: context, toggleRight: { rights, flags, value in
        updateState { current in
            var updated = flags

            var combinedRight: TelegramChatAdminRightsFlags
            switch rights {
            case let .direct(right):
                combinedRight = right
            case let .sub(_, right):
                combinedRight = []
                for flag in right {
                    combinedRight.insert(flag)
                }
            }

            if !value {
                updated.remove(combinedRight)
            } else {
                updated.insert(combinedRight)
            }
            return current.withUpdatedUpdatedFlags(updated)
        }
    }, toggleIsOptionExpanded: { flag in
        updateState { state in
            var state = state

            if state.expandedPermissions.contains(flag) {
                state.expandedPermissions.remove(flag)
            } else {
                state.expandedPermissions.insert(flag)
            }

            return state
        }
    }, dismissAdmin: {
        updateState { current in
            return current.withUpdatedUpdating(true)
        }
        if peerId.namespace == Namespaces.Peer.CloudGroup {
            updateRightsDisposable.set((context.engine.peers.removeGroupAdmin(peerId: peerId, adminId: adminId)
                |> deliverOnMainQueue).start(error: { _ in
                }, completed: {
                    updated(nil)
                    dismissImpl()
                }))
        } else {
            updateRightsDisposable.set((context.peerChannelMemberCategoriesContextsManager.updateMemberAdminRights(peerId: peerId, memberId: adminId, adminRights: nil, rank: stateValue.with { $0.rank }) |> deliverOnMainQueue).start(error: handleAdminRightsError, completed: {
                updated(nil)
                dismissImpl()
            }))
        }
    }, cantEditError: {
        showModalText(for: context.window, text: strings().channelAdminCantEdit)
    }, transferOwnership: {
        _ = (combineLatest(queue: .mainQueue(), context.account.postbox.loadedPeerWithId(peerId), context.account.postbox.loadedPeerWithId(adminId))).start(next: { peer, admin in

            let header: String
            let text: String
            if peer.isChannel {
                header = strings().channelAdminTransferOwnershipConfirmChannelTitle
                text = strings().channelAdminTransferOwnershipConfirmChannelText(peer.displayTitle, admin.displayTitle)
            } else {
                header = strings().channelAdminTransferOwnershipConfirmGroupTitle
                text = strings().channelAdminTransferOwnershipConfirmGroupText(peer.displayTitle, admin.displayTitle)
            }
            let isGroup = peer.isSupergroup || peer.isGroup

            let checkPassword:(PeerId)->Void = { peerId in
                showModal(with: InputPasswordController(context: context, title: strings().channelAdminTransferOwnershipPasswordTitle, desc: strings().channelAdminTransferOwnershipPasswordDesc, checker: { pwd in
                    return context.peerChannelMemberCategoriesContextsManager.transferOwnership(peerId: peerId, memberId: admin.id, password: pwd)
                        |> deliverOnMainQueue
                        |> ignoreValues
                        |> `catch` { error -> Signal<Never, InputPasswordValueError> in
                            let errorText: String? = getTransferErrorText(error, isGroup: isGroup)
                            switch error {
                            case .invalidPassword:
                                return .fail(.wrong)
                            default:
                                if let errorText = errorText {
                                    return .fail(.custom(errorText))
                                } else {
                                    return .fail(.generic)
                                }
                            }
                    }  |> afterCompleted {
                        dismissImpl()
                        _ = showModalSuccess(for: context.window, icon: theme.icons.successModalProgress, delay: 2.0)
                    }
                }), for: context.window)
            }

            let transfer:(PeerId, Bool, Bool)->Void = { _peerId, isGroup, convert in
                actionsDisposable.add(showModalProgress(signal: context.engine.peers.checkOwnershipTranfserAvailability(memberId: adminId), for: context.window).start(error: { error in
                    let errorText: String? = getTransferErrorText(error, isGroup: isGroup)
                    var install2Fa = false
                    switch error {
                    case .twoStepAuthMissing:
                        install2Fa = true
                    default:
                        break
                    }

                    if let errorText = errorText {
                        verifyAlert_button(for: context.window, header: strings().channelTransferOwnerErrorTitle, information: errorText, ok: strings().modalOK, cancel: strings().modalCancel, option: install2Fa ? strings().channelTransferOwnerErrorEnable2FA : nil, successHandler: { result in
                            switch result {
                            case .basic:
                                break
                            case .thrid:
                                dismissImpl()
                                if let emptyChatType = FeatureNavigationHooks.shared.emptyChatControllerType() {
                                    context.bindings.rootNavigation().removeUntil(emptyChatType)
                                }
                                if let unlockController = FeatureNavigationHooks.shared.makeTwoStepAccessController(context, { controller, isRoot, animated in
                                    let navigation = context.bindings.rootNavigation()
                                    if isRoot, let emptyChatType = FeatureNavigationHooks.shared.emptyChatControllerType() {
                                        navigation.removeUntil(emptyChatType)
                                    }
                                    if !animated {
                                        navigation.stackInsert(controller, at: navigation.stackCount)
                                    } else {
                                        navigation.push(controller)
                                    }
                                }) {
                                    context.bindings.rootNavigation().push(unlockController)
                                }
                            }
                        })
                    } else {
                        if convert {
                            actionsDisposable.add(showModalProgress(signal: context.engine.peers.convertGroupToSupergroup(peerId: peer.id), for: context.window).start(next: { upgradedPeerId in
                                upgradedToSupergroup(upgradedPeerId, {
                                    peerId = upgradedPeerId
                                    combinedPromise.set(context.account.postbox.combinedView(keys: [.peer(peerId: upgradedPeerId, components: .all), .peer(peerId: adminId, components: .all)]))
                                    checkPassword(upgradedPeerId)
                                })
                            }, error: { error in
                                switch error {
                                case .tooManyChannels:
                                    FeatureNavigationHooks.shared.showInactiveChannels(context, .upgrade)
                                case .generic:
                                    alert(for: context.window, info: strings().unknownError)
                                }
                            }))
                        } else {
                           checkPassword(peer.id)
                        }
                    }
                }))
            }

            verifyAlert_button(for: context.window, header: header, information: text, ok: strings().channelAdminTransferOwnershipConfirmOK, successHandler: { _ in
                transfer(peerId, isGroup, peer.isGroup)
            })
        })
    }, updateRank: { rank in
        updateState {
            $0.withUpdatedRank(rank)
        }
    }, toggleProcessJoinRequests: { value in
        if value {
            let botName = (latestAdminView.with({ $0 })?.peers[adminId] as? TelegramUser)?.displayTitle ?? ""
            verifyAlert(for: context.window, header: strings().channelAdminApproveMembersHeader, information: strings().channelAdminApproveMembersInfo(botName), ok: strings().channelAdminApproveMembersEnable, successHandler: { _ in
                updateState { current in
                    var current = current
                    current.processJoinRequests = true
                    return current
                }
                _ = context.engine.peers.toggleChannelJoinRequest(peerId: peerId, enabled: true, guardBotId: adminId).start()
            })
        } else {
            updateState { current in
                var current = current
                current.processJoinRequests = false
                return current
            }
            _ = context.engine.peers.toggleChannelJoinRequest(peerId: peerId, enabled: true, guardBotId: nil).start()
        }
    })

    combinedPromise.set(context.account.postbox.combinedView(keys: [.peer(peerId: peerId, components: .all), .peer(peerId: adminId, components: .all)]))

    let signal = combineLatest(statePromise.get(), combinedPromise.get(), appearanceSignal)
        |> deliverOn(prepareQueue)
        |> map { state, combinedView, appearance -> InputDataSignalValue in
            let channelView = combinedView.views[.peer(peerId: peerId, components: .all)] as! PeerView
            let adminView = combinedView.views[.peer(peerId: adminId, components: .all)] as! PeerView
            _ = latestChannelView.swap(channelView)
            _ = latestAdminView.swap(adminView)
            let result = channelAdminControllerEntries(state: state, accountPeerId: context.account.peerId, channelView: channelView, adminView: adminView, initialParticipant: initialParticipant)
            return InputDataSignalValue(entries: channelAdminInputDataEntries(result, arguments: arguments))
        }

    let controller = InputDataController(dataSignal: signal, title: strings().adminsAdmin, getBackgroundColor: {
        theme.colors.listBackground
    })
    controller.analyticsContext = origin
    controller.analyticsScreen = .peerInfoAdminsRights

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    controller._externalFirstResponder = { [weak controller] in
        let view = controller?.tableView.item(stableId: InputDataEntryId.custom(InputDataIdentifier("role")))?.view as? InputDataRowView
        return view?.textView
    }

    controller.afterTransaction = { controller in
        controller.modal?.interactions?.updateDone { button in
            let canEdit = stateValue.with { $0.editable }
            button.isEnabled = canEdit
            button.set(text: strings().navigationDone, for: .Normal)
        }
    }

    okClick = {
        guard let channelView = latestChannelView.with({ $0 }) else { return }
        guard let adminView = latestAdminView.with({ $0 }) else { return }
        let canEdit = canEditAdminRights(accountPeerId: context.account.peerId, channelView: channelView, initialParticipant: initialParticipant)

        if let channel = channelView.peers[channelView.peerId] as? TelegramChannel {
            if let initialParticipant = initialParticipant {
                var updateFlags: TelegramChatAdminRightsFlags?
                updateState { current in
                    updateFlags = current.updatedFlags
                    if let _ = updateFlags {
                        return current.withUpdatedUpdating(true)
                    } else {
                        return current
                    }
                }

                if updateFlags == nil {
                    switch initialParticipant {
                    case let .creator(_, info, _):
                        if stateValue.with ({ $0.rank != $0.initialRank }) {
                            updateFlags = info?.rights.rights ?? .internal_groupSpecific
                        }
                    case let .member(_, _, adminInfo, _, _, _):
                        if adminInfo?.rights == nil {
                            let maskRightsFlags: TelegramChatAdminRightsFlags
                            switch channel.info {
                            case .broadcast:
                                maskRightsFlags = .internal_broadcastSpecific
                            case .group:
                                maskRightsFlags = .internal_groupSpecific
                            }

                            if channel.flags.contains(.isCreator) {
                                updateFlags = maskRightsFlags.subtracting([.canAddAdmins, .canBeAnonymous])
                            } else if let adminRights = channel.adminRights {
                                updateFlags = maskRightsFlags.intersection(adminRights.rights).subtracting([.canAddAdmins, .canBeAnonymous])
                            } else {
                                updateFlags = []
                            }
                        }
                    }
                }
                if updateFlags == nil && stateValue.with ({ $0.rank != $0.initialRank }) {
                    updateFlags = initialParticipant.adminInfo?.rights.rights
                }

                let guardBotId: PeerId?
                if stateValue.with({ $0.processJoinRequests }), let user = adminView.peers[adminId] as? TelegramUser, user.botInfo?.flags.contains(.isGuardBot) == true {
                    guardBotId = adminId
                } else {
                    guardBotId = nil
                }
                if let updateFlags = updateFlags {
                    updateState { current in
                        return current.withUpdatedUpdating(true)
                    }
                    updateRightsDisposable.set((context.peerChannelMemberCategoriesContextsManager.updateMemberAdminRights(peerId: peerId, memberId: adminId, adminRights: TelegramChatAdminRights(rights: updateFlags), rank: stateValue.with { $0.rank }, guardBotId: guardBotId) |> deliverOnMainQueue).start(error: handleAdminRightsError, completed: {
                        updated(TelegramChatAdminRights(rights: updateFlags))
                        dismissImpl()
                    }))
                } else if let guardBotId = guardBotId {
                    updateState { current in
                        return current.withUpdatedUpdating(true)
                    }
                    updateRightsDisposable.set((context.engine.peers.toggleChannelJoinRequest(peerId: peerId, enabled: true, guardBotId: guardBotId) |> deliverOnMainQueue).start(error: { _ in
                    }, completed: {
                        dismissImpl()
                    }))
                } else {
                    dismissImpl()
                }
            } else if canEdit {
                var updateFlags: TelegramChatAdminRightsFlags?
                updateState { current in
                    updateFlags = current.updatedFlags
                    return current.withUpdatedUpdating(true)
                }

                if updateFlags == nil {
                    let maskRightsFlags: TelegramChatAdminRightsFlags
                    switch channel.info {
                    case .broadcast:
                        maskRightsFlags = .internal_broadcastSpecific
                    case .group:
                        maskRightsFlags = .internal_groupSpecific
                    }

                    if channel.flags.contains(.isCreator) {
                        updateFlags = maskRightsFlags.subtracting(.canAddAdmins)
                    } else if let adminRights = channel.adminRights {
                        updateFlags = maskRightsFlags.intersection(adminRights.rights).subtracting(.canAddAdmins)
                    } else {
                        updateFlags = []
                    }
                }

                if let updateFlags = updateFlags {
                    updateState { current in
                        return current.withUpdatedUpdating(true)
                    }

                    if let peer = adminView.peers[adminId] {

                        let updateRights = {
                            let guardBotId: PeerId?
                            if stateValue.with({ $0.processJoinRequests }), let user = peer as? TelegramUser, user.botInfo?.flags.contains(.isGuardBot) == true {
                                guardBotId = adminId
                            } else {
                                guardBotId = nil
                            }
                            updateRightsDisposable.set((context.peerChannelMemberCategoriesContextsManager.updateMemberAdminRights(peerId: peerId, memberId: adminId, adminRights: TelegramChatAdminRights(rights: updateFlags), rank: stateValue.with { $0.rank }, guardBotId: guardBotId) |> deliverOnMainQueue).start(error: handleAdminRightsError, completed: {
                                updated(TelegramChatAdminRights(rights: updateFlags))
                                dismissImpl()
                            }))
                        }

                        if peer.isBot {
                            updateRights()
                        } else {
                            updateRightsDisposable.set(context.peerChannelMemberCategoriesContextsManager.addMembers(peerId: peerId, memberIds: [adminId]).start(next: { peerIds in
                                updateRights()
                            }, error: { error in

                                switch error {
                                case .notMutualContact, .limitExceeded, .tooMuchJoined, .generic, .kicked:
                                    FeatureNavigationHooks.shared.showInvitePrivacyLimited(context, peerId, [adminId], [])
                                case let .restricted(peer):
                                    FeatureNavigationHooks.shared.showInvitePrivacyLimited(context, peerId, [adminId], peer != nil ? [peer!] : [])
                                default:
                                    break
                                }

                                dismissImpl()
                            }))
                        }
                    }
                }
            }
        } else if let _ = channelView.peers[channelView.peerId] as? TelegramGroup {
            var updateFlags: TelegramChatAdminRightsFlags?
            updateState { current in
                updateFlags = current.updatedFlags
                return current
            }

            let maskRightsFlags: TelegramChatAdminRightsFlags = .internal_groupSpecific
            let defaultFlags = maskRightsFlags.subtracting(.canAddAdmins)

            if updateFlags == nil {
                updateFlags = defaultFlags
            }

            if let updateFlags = updateFlags {
                let processJoinRequestsEnabled = stateValue.with({ $0.processJoinRequests })
                let bot = adminView.peers[adminId] as? TelegramUser
                let supportsGuard = bot?.botInfo?.flags.contains(.isGuardBot) == true
                let needsGuardBot = processJoinRequestsEnabled && supportsGuard
                if !needsGuardBot && initialParticipant?.adminInfo == nil && updateFlags == defaultFlags && stateValue.with ({ $0.rank == $0.initialRank }) {
                    updateState { current in
                        return current.withUpdatedUpdating(true)
                    }
                    updateRightsDisposable.set((context.engine.peers.addGroupAdmin(peerId: peerId, adminId: adminId)
                        |> deliverOnMainQueue).start(completed: {
                            dismissImpl()
                        }))
                } else if needsGuardBot || updateFlags != defaultFlags || stateValue.with ({ $0.rank != $0.initialRank }) {
                    let signal = context.engine.peers.convertGroupToSupergroup(peerId: peerId)
                        |> map(Optional.init)
                        |> deliverOnMainQueue
                        |> `catch` { error -> Signal<PeerId?, NoError> in
                            switch error {
                            case .tooManyChannels:
                                FeatureNavigationHooks.shared.showInactiveChannels(context, .upgrade)
                            case .generic:
                                alert(for: context.window, info: strings().unknownError)
                            }
                            updateState { current in
                                return current.withUpdatedUpdating(false)
                            }
                            return .single(nil)
                        }
                        |> mapToSignal { upgradedPeerId -> Signal<PeerId?, NoError> in
                            guard let upgradedPeerId = upgradedPeerId else {
                                return .single(nil)
                            }

                            let guardBotId: PeerId? = (processJoinRequestsEnabled && supportsGuard) ? adminId : nil
                            return  context.peerChannelMemberCategoriesContextsManager.updateMemberAdminRights(peerId: upgradedPeerId, memberId: adminId, adminRights: TelegramChatAdminRights(rights: updateFlags), rank: stateValue.with { $0.rank }, guardBotId: guardBotId)
                                |> map { _ -> PeerId? in upgradedPeerId }
                                |> `catch` { error -> Signal<PeerId?, NoError> in
                                    handleAdminRightsError(error)
                                    return .single(nil)
                                }
                        }
                        |> deliverOnMainQueue

                    updateState { current in
                        return current.withUpdatedUpdating(true)
                    }

                    updateRightsDisposable.set(showModalProgress(signal: signal, for: context.window).start(next: { upgradedPeerId in
                        if let upgradedPeerId = upgradedPeerId {
                            let (disposable, _) = context.peerChannelMemberCategoriesContextsManager.admins(peerId: upgradedPeerId, updated: { state in
                                if case .ready = state.loadingState {
                                    upgradedToSupergroup(upgradedPeerId, {

                                    })
                                    dismissImpl()
                                }
                            })
                            actionsDisposable.add(disposable)
                        }
                    }))
                } else {
                    dismissImpl()
                }
            } else {
                dismissImpl()
            }
        }
    }

    controller.returnKeyInvocation = { _, _ in
        okClick?()
        return .nothing
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().modalSave, accept: {
        okClick?()
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(350, 360))
    modalController.analyticsContext = origin

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    controller.centerModalHeader = ModalHeaderData(title: strings().adminsAdmin)

    close = { [weak modalController] in
        modalController?.close()
    }

    return modalController
}
