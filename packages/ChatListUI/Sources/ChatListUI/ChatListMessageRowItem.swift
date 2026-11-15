import Cocoa
import TGUIKit
import TelegramCore

import Postbox
import SwiftSignalKit
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows

public class ChatListMessageRowItem: ChatListRowItem {

    public init(_ initialSize:NSSize, context: any AccountContextProtocol, message: Message, id: EngineChatList.Item.Id, query: String, renderedPeer:RenderedPeer, readState: CombinedPeerReadState?, mode: ChatListRowItem.Mode, titleMode: ChatListRowItem.TitleMode, savedMessagesParentPeerId: PeerId?) {
        super.init(initialSize, context: context, stableId: .chatId(id, message.id.peerId, message.id.id), mode: mode, messages: [message], readState: .init(state: readState, isMuted: false), renderedPeer: .init(renderedPeer), highlightText: query, showBadge: false, titleMode: titleMode, savedMessagesParentPeerId: savedMessagesParentPeerId)
    }
    
    public override var stableId: AnyHashable {
        return message!.id
    }

    public override var showsCommunityDropdown: Bool {
        return false
    }

    override func menuState() -> Signal<MenuState, NoError> {
        guard let peerId = self.peerId else {
            return super.menuState()
        }
        let mode = self.mode
        let timestamp = context.timestamp
        return context.account.postbox.transaction { transaction -> MenuState in
            switch mode {
            case .chat:
                let groupId = transaction.getPeerChatListIndex(peerId)?.0 ?? transaction.getPeerChatListInclusion(peerId).groupId ?? .root
                let isMuted = transaction.getPeer(peerId).flatMap { searchPeerIsMuted(transaction, peer: $0, timestamp: timestamp) } ?? false
                return MenuState(isPinned: transaction.getPinnedItemIds(groupId: groupId).contains(.peer(peerId)), isMuted: isMuted, pinGroupId: EngineChatList.Group(groupId))
            case let .topic(threadId, data):
                let threadData = transaction.getMessageHistoryThreadInfo(peerId: peerId, threadId: threadId)?.data.get(MessageHistoryThreadData.self) ?? data
                let isMuted: Bool
                switch threadData.notificationSettings.muteState {
                case let .muted(until):
                    isMuted = until > timestamp
                case .unmuted:
                    isMuted = false
                case .default:
                    isMuted = transaction.getPeer(peerId).flatMap { searchPeerIsMuted(transaction, peer: $0, timestamp: timestamp) } ?? false
                }
                return MenuState(isPinned: transaction.getPeerPinnedThreads(peerId: peerId).contains(threadId), isMuted: isMuted, pinGroupId: .root)
            case let .savedMessages(threadId):
                return MenuState(isPinned: transaction.getPeerPinnedThreads(peerId: peerId).contains(threadId), isMuted: false, pinGroupId: .root)
            }
        } |> deliverOnMainQueue
    }
}
