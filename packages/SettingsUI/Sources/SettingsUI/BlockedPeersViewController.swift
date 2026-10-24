
import Cocoa
import TGUIKit
import Postbox
import TelegramCore

import SwiftSignalKit
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
import LocalAnimations


private struct BlockedPeersEditingState: Equatable {
    var editing = false
    var removingPeerIds = Set<PeerId>()

    func withUpdatedEditing(_ editing: Bool) -> BlockedPeersEditingState {
        var state = self
        state.editing = editing
        return state
    }

    func withUpdatedRemoval(_ peerId: PeerId, removing: Bool) -> BlockedPeersEditingState {
        var state = self
        if removing {
            state.removingPeerIds.insert(peerId)
        } else {
            state.removingPeerIds.remove(peerId)
        }
        return state
    }
}

private final class BlockedPeerControllerArguments {
    public let context: any AccountContextProtocol
    
    public let removePeer: (PeerId) -> Void
    public let openPeer:(PeerId) -> Void
    public init(context: any AccountContextProtocol, removePeer: @escaping (PeerId) -> Void, openPeer: @escaping(PeerId)->Void) {
        self.context = context
        self.removePeer = removePeer
        self.openPeer = openPeer
    }
}

private enum BlockedPeerEntryStableId: Hashable {
    case peer(PeerId)
    case empty
    case sectionId(Int32)
    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .peer(peerId):
            hasher.combine(peerId)
        case .empty:
            hasher.combine(0)
        case .sectionId:
            hasher.combine(1)
        }
    }

}

private enum BlockedPeerEntry: Identifiable, Comparable {
    case section(Int32)
    case peerItem(Int32, Int32, Peer, ShortPeerDeleting?, Bool, GeneralViewType)
    case empty(Bool)
    public var stableId: BlockedPeerEntryStableId {
        switch self {
        case let .peerItem(_, _, peer, _, _, _):
            return .peer(peer.id)
        case .empty:
            return .empty
        case let .section(id):
            return .sectionId(id)
        }
    }
    
    public static func ==(lhs: BlockedPeerEntry, rhs: BlockedPeerEntry) -> Bool {
        switch lhs {
        case let .peerItem(lhsSectionId, lhsIndex, lhsPeer, lhsEditing, lhsEnabled, lhsViewType):
            if case let .peerItem(rhsSectionId, rhsIndex, rhsPeer, rhsEditing, rhsEnabled, rhsViewType) = rhs {
                if lhsIndex != rhsIndex {
                    return false
                }
                if !lhsPeer.isEqual(rhsPeer) {
                    return false
                }
                if lhsSectionId != rhsSectionId {
                    return false
                }
                if lhsEditing != rhsEditing {
                    return false
                }
                if lhsEnabled != rhsEnabled {
                    return false
                }
                if rhsViewType != lhsViewType {
                    return false
                }
                return true
            } else {
                return false
            }
        case let .empty(loading):
            if case .empty(loading) = rhs {
                return true
            } else {
                return false
            }
        case let .section(id):
            if case .section(id) = rhs {
                return true
            } else {
                return false
            }
        }
    }
    
    public var index: (Int32, Int32) {
        switch self {
        case .empty:
            return (0, 0)
        case let .peerItem(sectionId, index, _, _, _, _):
            return (sectionId, index)
        case let .section(sectionId):
            return (sectionId, -1)
        }
    }
    
    public static func <(lhs: BlockedPeerEntry, rhs: BlockedPeerEntry) -> Bool {
        return lhs.index < rhs.index
    }
    
    public func item(_ arguments: BlockedPeerControllerArguments, initialSize:NSSize) -> TableRowItem {
        switch self {
        case let .peerItem(_, _, peer, editing, enabled, viewType):
            
            let interactionType:ShortPeerItemInteractionType
            if let editing = editing {
                
                interactionType = .deletable(onRemove: { peerId in
                    arguments.removePeer(peerId)
                }, deletable: editing.editable)
            } else {
                interactionType = .plain
            }
            
            return ShortPeerRowItem(initialSize, peer: peer, account: arguments.context.account, context: arguments.context, stableId: stableId, enabled: enabled, height: 46, photoSize: NSMakeSize(32, 32), inset: NSEdgeInsets(left: 20, right: 20), interactionType: interactionType, generalType: .none, viewType: viewType, action: {
                arguments.openPeer(peer.id)
            }, contextMenuItems: {
                if case .plain = interactionType {
                    return .single([ContextMenuItem(strings().chatInputUnblock, handler: {
                        arguments.removePeer(peer.id)
                    }, itemImage: MenuAnimation.menu_unblock.value)])
                } else {
                    return .single([])
                }
                
            })
        case let .empty(progress):
            return SearchEmptyRowItem(initialSize, stableId: stableId, isLoading: progress, text: strings().blockedPeersEmptyDescrpition, viewType: .singleItem)
        case .section:
            return GeneralRowItem(initialSize, height: 20, stableId: stableId, viewType: .separator)
        }
    }
}

private func blockedPeersControllerEntries(state: BlockedPeersEditingState, blockedState: BlockedPeersContextState) -> [BlockedPeerEntry] {
    
    var entries: [BlockedPeerEntry] = []
    
    var index: Int32 = 0
    var sectionId: Int32 = 0
    let list = blockedState.peers.filter { $0.peer != nil }
    if !list.isEmpty {
        entries.append(.section(sectionId))
        sectionId += 1
    }
    for rendered in list {
        if let peer = rendered.peer {
            var deleting:ShortPeerDeleting? = nil
            if state.editing {
                deleting = ShortPeerDeleting(editable: true)
            }

            entries.append(.peerItem(sectionId, index, peer, deleting, !state.removingPeerIds.contains(peer.id), bestGeneralViewType(list, for: rendered)))
            index += 1
        }
    }
    
    if list.isEmpty {
        entries.append(.empty(blockedState.isLoadingMore))
    } else {
        sectionId += 1
        entries.append(.section(sectionId))
    }
    
    return entries
}

fileprivate func prepareTransition(left:[AppearanceWrapperEntry<BlockedPeerEntry>], right: [AppearanceWrapperEntry<BlockedPeerEntry>], initialSize:NSSize, arguments:BlockedPeerControllerArguments) -> TableUpdateTransition {
    
    let (removed, inserted, updated) = proccessEntriesWithoutReverse(left, right: right) { entry -> TableRowItem in
        return entry.entry.item(arguments, initialSize: initialSize)
    }
    
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: true, grouping: false)
}


open class BlockedPeersViewController<Context: AccountContextProtocol>: EditableViewController<TableView, Context> {

    open override var defaultBarTitle: String {
        return strings().privacySettingsBlockedUsers
    }
    
    
    private let statePromise = ValuePromise(BlockedPeersEditingState(), ignoreRepeated: true)
    private let stateValue = Atomic(value: BlockedPeersEditingState())
    private var removalDisposables: [PeerId: MetaDisposable] = [:]
    
    private let disposable:MetaDisposable = MetaDisposable()
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        genericView.contentInsets = NavigationBarView.contentTopInset

        genericView.getBackgroundColor = {
            theme.colors.listBackground
        }
        
        let context = self.context
        
        let arguments = BlockedPeerControllerArguments(context: context, removePeer: { [weak self] memberId in
            self?.removePeer(memberId)
        }, openPeer: { [weak self] peerId in
            guard let `self` = self else {return}
            if let navigation = self.navigationController {
                BlockedPeersHooks.shared.openPeerInfo(navigation, self.context, peerId)
            }
        })
        
        
        
        let initialSize = atomicSize
        let previousEntries:Atomic<[AppearanceWrapperEntry<BlockedPeerEntry>]> = Atomic(value: [])
        
        
        let signal = combineLatest(statePromise.get(), context.blockedPeersContext.state, appearanceSignal)
            |> deliverOnMainQueue
            |> map { state, blockedState, appearance -> TableUpdateTransition in
                let entries = blockedPeersControllerEntries(state: state, blockedState: blockedState).map{AppearanceWrapperEntry(entry: $0, appearance: appearance)}
                return prepareTransition(left: previousEntries.swap(entries), right: entries, initialSize: initialSize.modify{$0}, arguments: arguments)
            }
        
        disposable.set((signal |> deliverOnMainQueue).start(next: { [weak self] transition in
            if let strongSelf = self {
                strongSelf.genericView.merge(with: transition)
                strongSelf.readyOnce()
                strongSelf.rightBarView.isHidden = strongSelf.genericView.item(at: 0) is SearchEmptyRowItem
            }
        }))
        
        genericView.setScrollHandler { position in
            switch position.direction {
            case .bottom:
                context.blockedPeersContext.loadMore()
            default:
                break
            }
        }
    }
    
    private func removePeer(_ peerId: PeerId) {
        guard self.removalDisposables[peerId] == nil else { return }
        let disposable = MetaDisposable()
        self.removalDisposables[peerId] = disposable
        self.statePromise.set(self.stateValue.modify { $0.withUpdatedRemoval(peerId, removing: true) })
        disposable.set((self.context.blockedPeersContext.remove(peerId: peerId) |> deliverOnMainQueue).start(error: { [weak self, weak disposable] _ in
            guard let self, let disposable else { return }
            self.finishRemoval(peerId, disposable: disposable)
            alert(for: self.context.window, info: strings().unknownError)
        }, completed: { [weak self, weak disposable] in
            guard let self, let disposable else { return }
            self.finishRemoval(peerId, disposable: disposable)
        }))
    }

    private func finishRemoval(_ peerId: PeerId, disposable: MetaDisposable) {
        guard self.removalDisposables[peerId] === disposable else { return }
        self.removalDisposables.removeValue(forKey: peerId)
        self.statePromise.set(self.stateValue.modify { $0.withUpdatedRemoval(peerId, removing: false) })
        disposable.dispose()
    }

    deinit {
        disposable.dispose()
        for disposable in self.removalDisposables.values {
            disposable.dispose()
        }
    }
    
    open override func update(with state: ViewControllerState) {
        super.update(with: state)
        self.statePromise.set(stateValue.modify({$0.withUpdatedEditing(state == .Edit)}))
    }
    
}

