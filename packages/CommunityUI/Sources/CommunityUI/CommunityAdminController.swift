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

private func communityAdminRightsErrorText(_ error: UpdateChannelAdminRightsError, isGroup: Bool) -> String {
    switch error {
    case .notMemberCannotInvite:
        return strings().channelAdminsPromoteUnmemberAdminError
    case .userBlocked:
        return isGroup ? strings().groupErrorAddBlocked : strings().channelErrorAddBlocked
    case .adminsTooMuch, .generic:
        return strings().channelAdminsAddAdminError
    case let .addMemberError(error):
        switch error {
        case .notMutualContact:
            return isGroup ? strings().groupInfoAddUserLeftError : strings().channelInfoAddUserLeftError
        case .limitExceeded:
            return strings().channelErrorAddTooMuch
        case .botDoesntSupportGroups:
            return strings().channelBotDoesntSupportGroups
        case .tooMuchBots:
            return strings().channelTooMuchBots
        case .tooMuchJoined:
            return strings().inviteChannelsTooMuch
        case .restricted:
            return isGroup ? strings().groupErrorAddBlocked : strings().channelErrorAddBlocked
        case .kicked:
            return strings().channelAddAdminKickedError
        case .bot, .generic:
            return strings().channelAdminsAddAdminError
        }
    }
}

private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let toggleFlag: (TelegramChatAdminRightsFlags) -> Void
    public let dismissAdmin: () -> Void
    public init(context: (any AccountContextProtocol), toggleFlag: @escaping (TelegramChatAdminRightsFlags) -> Void, dismissAdmin: @escaping () -> Void) {
        self.context = context
        self.toggleFlag = toggleFlag
        self.dismissAdmin = dismissAdmin
    }
}

private struct State: Equatable {
    public var peer: EnginePeer? = nil
    public var flags: TelegramChatAdminRightsFlags
    public var updating: Bool = false

    public static func == (lhs: State, rhs: State) -> Bool {
        if lhs.peer?.id != rhs.peer?.id { return false }
        if lhs.flags != rhs.flags { return false }
        if lhs.updating != rhs.updating { return false }
        return true
    }
}

private let _id_peer_header = InputDataIdentifier("_id_peer_header")
private let _id_can_change_info = InputDataIdentifier("_id_can_change_info")
private let _id_can_manage_linked = InputDataIdentifier("_id_can_manage_linked")
private let _id_can_ban_users = InputDataIdentifier("_id_can_ban_users")
private let _id_dismiss = InputDataIdentifier("_id_dismiss")

private func entries(_ state: State, isCreator: Bool, isExistingAdmin: Bool, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1

    if let peer = state.peer {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_peer_header, equatable: InputDataEquatable(peer.id), comparable: nil, item: { initialSize, stableId in
            return ShortPeerRowItem(initialSize, peer: peer._asPeer(), account: arguments.context.account, context: arguments.context, stableId: stableId, height: 50, photoSize: NSMakeSize(40, 40), inset: NSEdgeInsets(left: 20, right: 20), viewType: .singleItem)
        }))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().communityAdminPermissionsHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    let enabled = !isCreator && !state.updating

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_can_change_info, data: .init(name: strings().communityAdminEditName, color: theme.colors.text, type: .switchable(state.flags.contains(.canChangeInfo)), viewType: .firstItem, enabled: enabled, action: {
        arguments.toggleFlag(.canChangeInfo)
    })))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_can_manage_linked, data: .init(name: strings().communityAdminEditGroupList, color: theme.colors.text, type: .switchable(state.flags.contains(.canManageLinkedPeers)), viewType: .innerItem, enabled: enabled, action: {
        arguments.toggleFlag(.canManageLinkedPeers)
    })))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_can_ban_users, data: .init(name: strings().communityAdminBanMembers, color: theme.colors.text, type: .switchable(state.flags.contains(.canBanUsers)), viewType: .lastItem, enabled: enabled, action: {
        arguments.toggleFlag(.canBanUsers)
    })))
    index += 1

    if isExistingAdmin && !isCreator {
        entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1

        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_dismiss, data: .init(name: strings().communityAdminDismiss, color: theme.colors.redUI, type: .none, viewType: .singleItem, enabled: !state.updating, action: {
            arguments.dismissAdmin()
        })))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1
    return entries
}

public func CommunityAdminController(_ context: (any AccountContextProtocol), communityId: PeerId, adminId: PeerId, initialParticipant: ChannelParticipant?) -> InputDataModalController {
    let actionsDisposable = DisposableSet()

    var isCreator = false
    var isExistingAdmin = false
    var initialFlags: TelegramChatAdminRightsFlags

    switch initialParticipant {
    case .creator:
        isCreator = true
        isExistingAdmin = true
        initialFlags = TelegramChatAdminRightsFlags.allCommunity
    case let .member(_, _, adminInfo, _, _, _):
        if let adminInfo = adminInfo {
            isExistingAdmin = true
            initialFlags = adminInfo.rights.rights
        } else {
            isExistingAdmin = false
            initialFlags = TelegramChatAdminRightsFlags.allCommunity
        }
    case nil:
        isExistingAdmin = false
        initialFlags = TelegramChatAdminRightsFlags.allCommunity
    }

    let initialState = State(flags: initialFlags)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in statePromise.set(stateValue.modify(f)) }

    var close: (() -> Void)? = nil

    let arguments = Arguments(
        context: context,
        toggleFlag: { flag in
            updateState { var s = $0
                if s.flags.contains(flag) {
                    s.flags.remove(flag)
                } else {
                    s.flags.insert(flag)
                }
                return s
            }
        },
        dismissAdmin: {
            verifyAlert(for: context.window, information: strings().communityAdminDismissConfirm, successHandler: { _ in
                updateState { var s = $0; s.updating = true; return s }
                actionsDisposable.add((context.peerChannelMemberCategoriesContextsManager.updateMemberAdminRights(peerId: communityId, memberId: adminId, adminRights: nil, rank: nil) |> deliverOnMainQueue).start(error: { error in
                    updateState { var s = $0; s.updating = false; return s }
                    alert(for: context.window, info: communityAdminRightsErrorText(error, isGroup: true))
                }, completed: {
                    close?()
                }))
            })
        }
    )

    actionsDisposable.add(context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: adminId)).start(next: { peer in
        updateState { var s = $0; s.peer = peer; return s }
    }))

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, isCreator: isCreator, isExistingAdmin: isExistingAdmin, arguments: arguments))
    }

    let acceptTitle = isExistingAdmin ? strings().communityAdminSave : strings().communityAdminAddAdmin

    let controller = InputDataController(dataSignal: signal, title: strings().communityAdminAddAdmin, removeAfterDisappear: false, hasDone: false)
    controller.analyticsScreen = .communityAdminsRights
    controller.onDeinit = { actionsDisposable.dispose() }

    let performSave: () -> Void = {
        let state = stateValue.with { $0 }
        if state.updating { return }
        updateState { var s = $0; s.updating = true; return s }
        actionsDisposable.add((context.peerChannelMemberCategoriesContextsManager.updateMemberAdminRights(peerId: communityId, memberId: adminId, adminRights: TelegramChatAdminRights(rights: state.flags), rank: nil) |> deliverOnMainQueue).start(error: { error in
            updateState { var s = $0; s.updating = false; return s }
            alert(for: context.window, info: communityAdminRightsErrorText(error, isGroup: true))
        }, completed: {
            close?()
        }))
    }

    let modalInteractions = ModalInteractions(acceptTitle: acceptTitle, accept: {
        performSave()
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(350, 360))

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    controller.centerModalHeader = ModalHeaderData(title: strings().communityAdminAddAdmin)

    close = { [weak modalController] in modalController?.close() }
    return modalController
}
