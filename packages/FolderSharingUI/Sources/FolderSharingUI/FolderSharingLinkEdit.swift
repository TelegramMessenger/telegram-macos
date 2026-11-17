import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramContext


enum FolderSharingLinkEditError {
    case unresolvedPeers([PeerId])
    case generic
}

func folderSharingUnresolvedPeers(_ peerIds: [PeerId], getPeer: (PeerId) -> Peer?) -> [PeerId] {
    return peerIds.filter { id in
        guard let peer = getPeer(id) else {
            return true
        }
        return PeerReference(peer) == nil
    }
}

func folderSharingEditLink(context: any AccountContextProtocol, filterId: Int32, link: ExportedChatFolderLink, selected: Set<PeerId>) -> Signal<ExportedChatFolderLink, FolderSharingLinkEditError> {
    let peerIds = selected == Set(link.peerIds) ? nil : selected.sorted()
    let unresolved: Signal<[PeerId], NoError>
    if let peerIds = peerIds {
        unresolved = context.account.postbox.transaction { transaction in
            return folderSharingUnresolvedPeers(peerIds, getPeer: transaction.getPeer)
        }
    } else {
        unresolved = .single([])
    }
    return unresolved
    |> castError(FolderSharingLinkEditError.self)
    |> mapToSignal { unresolved -> Signal<ExportedChatFolderLink, FolderSharingLinkEditError> in
        guard unresolved.isEmpty else {
            return .fail(.unresolvedPeers(unresolved))
        }
        return context.engine.peers.editChatFolderLink(filterId: filterId, link: link, title: link.title, peerIds: peerIds, revoke: false)
        |> mapError { _ in FolderSharingLinkEditError.generic }
    }
}
