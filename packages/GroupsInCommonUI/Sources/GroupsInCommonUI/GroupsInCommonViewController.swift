import Cocoa
import TGUIKit
import TelegramCore

import Postbox
import SwiftSignalKit
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import ShortPeerRow
import InputDataUI
import AppAnalytics

public final class GroupsInCommonArguments {
    public let context: any AccountContextProtocol
    public let open:(PeerId)->Void
    public init(context: any AccountContextProtocol, open: @escaping(PeerId) -> Void) {
        self.open = open
        self.context = context
    }
}


private func _id_peer_id(_ id: PeerId) -> InputDataIdentifier {
    return InputDataIdentifier("_id_peer_id_\(id)")
}

private func commonGroupsEntries(state: GroupsInCommonState, arguments: GroupsInCommonArguments, standalone: Bool) -> [InputDataEntry] {
    
    
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    if standalone {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    }
    
    
    let peers = state.peers.compactMap { $0.chatMainPeer }
    
    struct Tuple : Equatable {
        let peer: PeerEquatable
        let viewType: GeneralViewType
    }
    for (i, peer) in peers.enumerated() {
        var viewType: GeneralViewType = bestGeneralViewType(peers, for: i)
        if !standalone {
            if i == 0 {
                if peers.count > 1 {
                    viewType = .innerItem
                } else {
                    viewType = .lastItem
                }
            }
        }
        let tuple = Tuple(peer: .init(peer), viewType: viewType)
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_peer_id(peer.id), equatable: InputDataEquatable(tuple), comparable: nil, item: { initialSize, stableId in
            return ShortPeerRowItem(initialSize, peer: tuple.peer.peer, account: arguments.context.account, context: arguments.context, stableId: stableId, height: 46, photoSize: NSMakeSize(32, 32), inset: standalone ? NSEdgeInsets(left: 20, right: 20) : NSEdgeInsetsZero, viewType: tuple.viewType, action: {
                arguments.open(tuple.peer.peer.id)
            }, customTheme: .initialize(theme), fullSize: true)
        }))
        index += 1
    }
    if standalone {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    }
    
    return entries
    
}

public func GroupsInCommonViewController(context: any AccountContextProtocol, peerId: PeerId, standalone: Bool = false, analyticsContext: AnalyticsContext? = nil) -> ViewController {
    let origin = Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: analyticsContext ?? Analytics.shared.unresolvedContext())
    let presentation = origin.beginPresentation()
    defer { presentation.end() }

    let actionsDisposable = DisposableSet()
    
    let arguments = GroupsInCommonArguments(context: context, open: { peerId in
        GroupsInCommonHooks.shared.openChatObserved(context, peerId, analyticsContext: origin)
    })
    
    let contextValue: Promise<GroupsInCommonContext> = Promise()
    let peer = origin.preservingPresentation(getPeerView(peerId: peerId, postbox: context.account.postbox) |> take(1))
    contextValue.set(peer |> map { peer in
        let resolvedPeerId = peer?.id ?? peerId
        let resolvedOrigin = Analytics.shared.captureContext(engine: context.engine, peerId: resolvedPeerId, inherited: origin)
        if resolvedOrigin.isExcluded { origin.scope?.exclude() }
        let presentation = resolvedOrigin.beginPresentation()
        defer { presentation.end() }
        return GroupsInCommonContext(account: context.account, peerId: resolvedPeerId)
    })
    let state = origin.preservingPresentation(contextValue.get()) |> mapToSignal {
        origin.preservingPresentation($0.state)
    }
    let dataSignal = state |> map {
        return InputDataSignalValue(entries: commonGroupsEntries(state: $0, arguments: arguments, standalone: standalone))
    }
    
    let controller = InputDataController(dataSignal: dataSignal, title: !standalone ? "" : strings().peerInfoGroupsInCommon, hasDone: false)
    controller.analyticsContext = origin
    controller.bar = .init(height: standalone ? 50 : 0)
    if standalone {
        controller.analyticsScreen = .peerInfoGroupsInCommon
    } else {
        controller.analyticsScreen = .peerInfoMediaGroupsInCommon
    }
    
    controller.contextObject = contextValue
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    controller.getBackgroundColor = {
        if standalone {
            return theme.colors.listBackground
        } else {
            return .clear
        }
    }
    
    controller.didLoad = { controller, _ in
        
        controller.tableView.verticalScrollElasticity = .none
        
        controller.tableView.setScrollHandler { position in
            switch position.direction {
            case .bottom:
                _ = origin.preservingPresentation(contextValue.get() |> take(1)).start(next: { ctx in
                    ctx.loadMore()
                })
                //commonContext.loadMore()
            default:
                break
            }
        }
    }
    
    return controller
}
