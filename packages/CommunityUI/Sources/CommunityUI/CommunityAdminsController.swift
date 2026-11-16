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
    public let addAdmin: () -> Void
    public let openAdmin: (RenderedChannelParticipant) -> Void
    public init(context: (any AccountContextProtocol), addAdmin: @escaping () -> Void, openAdmin: @escaping (RenderedChannelParticipant) -> Void) {
        self.context = context
        self.addAdmin = addAdmin
        self.openAdmin = openAdmin
    }
}

private struct State: Equatable {
    public var community: TelegramCommunity? = nil
    public var admins: [RenderedChannelParticipant]? = nil

    public static func == (lhs: State, rhs: State) -> Bool {
        if lhs.community?.id != rhs.community?.id { return false }
        if lhs.community?.title != rhs.community?.title { return false }
        if lhs.community?.defaultBannedRights != rhs.community?.defaultBannedRights { return false }
        if let la = lhs.admins, let ra = rhs.admins {
            if la.map({ $0.peer.id }) != ra.map({ $0.peer.id }) { return false }
        } else if (lhs.admins == nil) != (rhs.admins == nil) {
            return false
        }
        return true
    }
}

private let _id_add_admin = InputDataIdentifier("_id_add_admin")
private func _id_admin(_ id: PeerId) -> InputDataIdentifier {
    return InputDataIdentifier("_id_admin_\(id.toInt64())")
}

private func statusText(for participant: RenderedChannelParticipant) -> String {
    switch participant.participant {
    case .creator:
        return strings().communityAdminsStatusCreator
    case let .member(_, _, adminInfo, _, _, _):
        if let adminInfo = adminInfo {
            let promoterTitle = participant.peers[adminInfo.promotedBy]?._asPeer().displayTitle ?? ""
            if promoterTitle.isEmpty {
                return strings().communityAdminsStatusAdmin
            }
            return strings().communityAdminsStatusPromotedBy(promoterTitle)
        }
        return strings().communityAdminsStatusAdmin
    }
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1

    if state.community?.hasPermission(.changeInfo) == true {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_add_admin, data: .init(name: strings().communityAdminsAddAdmin, color: theme.colors.accent, type: .next, viewType: .singleItem, action: {
            arguments.addAdmin()
        })))
        index += 1
        entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1
    }

    guard let admins = state.admins else {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().communityAdminsLoading), data: .init(color: theme.colors.listGrayText, viewType: .singleItem)))
        index += 1
        entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1
        return entries
    }

    if !admins.isEmpty {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().communityAdminsHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1

        for (i, participant) in admins.enumerated() {
            let viewType = bestGeneralViewType(admins, for: i)
            let status = statusText(for: participant)
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_admin(participant.peer.id), equatable: InputDataEquatable(participant.peer.id), comparable: nil, item: { initialSize, stableId in
                return ShortPeerRowItem(initialSize, peer: participant.peer._asPeer(), account: arguments.context.account, context: arguments.context, stableId: stableId, status: status, inset: NSEdgeInsets(left: 20, right: 20), generalType: .none, viewType: viewType, action: {
                    arguments.openAdmin(participant)
                })
            }))
            index += 1
        }
    }

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1
    return entries
}

public func CommunityAdminsController(_ context: (any AccountContextProtocol), communityId: PeerId) -> InputDataController {
    let actionsDisposable = DisposableSet()
    let initialState = State()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in statePromise.set(stateValue.modify(f)) }

    let arguments = Arguments(
        context: context,
        addAdmin: {
            let excludePeerIds = stateValue.with { ($0.admins ?? []).map { $0.peer.id } }
            _ = (CommunityHooks.shared.selectAdmin(context, strings().communityAdminsAddAdmin, excludePeerIds) |> map { $0.first }).start(next: { adminId in
                if let adminId = adminId {
                    showModal(with: CommunityAdminController(context, communityId: communityId, adminId: adminId, initialParticipant: nil), for: context.window)
                }
            })
        },
        openAdmin: { participant in
            showModal(with: CommunityAdminController(context, communityId: communityId, adminId: participant.peer.id, initialParticipant: participant.participant), for: context.window)
        }
    )

    actionsDisposable.add(context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: communityId)).start(next: { peer in
        var community: TelegramCommunity? = nil
        if case let .community(c) = peer { community = c }
        updateState { var s = $0; s.community = community; return s }
    }))

    let (adminsDisposable, _) = context.peerChannelMemberCategoriesContextsManager.admins(peerId: communityId, updated: { membersState in
        if case .loading = membersState.loadingState, membersState.list.isEmpty {
            updateState { var s = $0; s.admins = nil; return s }
        } else {
            updateState { var s = $0; s.admins = membersState.list; return s }
        }
    })
    actionsDisposable.add(adminsDisposable)

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().communityAdminsTitle, removeAfterDisappear: false, hasDone: false)
    controller.analyticsScreen = .communityAdmins
    controller.onDeinit = { actionsDisposable.dispose() }
    return controller
}
