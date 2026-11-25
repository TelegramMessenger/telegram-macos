import TGUIKit
import Postbox
import SwiftSignalKit
import TelegramCore
import TelegramContext
import Localization
import LocalAnimations

func searchPeerReadMenuItem(context: any AccountContextProtocol, peerId: PeerId, target: SearchControllerTarget = .common(.root)) -> Signal<ContextMenuItem?, NoError> {
    if case .savedMessages = target { return .single(nil) }
    guard peerId.namespace != Namespaces.Peer.SecretChat else {
        return .single(nil)
    }
    return context.engine.data.get(
        TelegramEngine.EngineData.Item.Messages.PeerReadCounters(id: peerId),
        TelegramEngine.EngineData.Item.Messages.ChatListGroup(id: peerId),
        TelegramEngine.EngineData.Item.Peer.Peer(id: peerId),
        TelegramEngine.EngineData.Item.Peer.CachedData(id: peerId)
    ) |> mapToSignal { state, group, peer, cachedData -> Signal<ContextMenuItem?, NoError> in
        guard group != nil, let peer else { return .single(nil) }
        let forum = peer._asPeer().isForumOrMonoForum
        let displaysAsMessages = (peer._asPeer() as? TelegramChannel)?.flags.contains(.displayForumAsTabs) == true || (cachedData as? CachedChannelData)?.viewForumAsMessages.knownValue == true
        let readState: Signal<Bool, NoError>
        if forum && displaysAsMessages {
            readState = context.account.postbox.transaction { transaction in
                transaction.getCombinedPeerReadState(peerId)?.isUnread ?? false
            }
        } else {
            readState = .single(state.isUnread)
        }
        return readState |> deliverOnMainQueue |> map { isUnread -> ContextMenuItem? in
            if !isUnread && forum && !displaysAsMessages { return nil }
            if isUnread {
                return ContextMenuItem(strings().chatListContextMaskAsRead, handler: {
                    ChatListRowItem.markAsRead(context: context, peerId: peerId)
                }, itemImage: MenuAnimation.menu_read.value)
            } else {
                return ContextMenuItem(strings().chatListContextMaskAsUnread, handler: {
                    ChatListRowItem.markAsUnread(context: context, peerId: peerId)
                }, itemImage: MenuAnimation.menu_unread.value)
            }
        }
    }
}
