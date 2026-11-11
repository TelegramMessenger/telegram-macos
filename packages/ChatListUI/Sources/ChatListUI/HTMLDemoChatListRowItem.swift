import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import HTMLBubbles

final class HTMLDemoChatListRowItem: ChatListRowItem {
    init(_ initialSize: NSSize, context: any AccountContextProtocol, stableId: UIChatListEntryId, chat: HTMLDemoChat) {
        super.init(initialSize, context: context, stableId: stableId, mode: .chat, messages: HTMLDemoChatListRowItem.previewMessages(chat), index: nil, readState: nil, pinnedType: .none, renderedPeer: EngineRenderedPeer(peer: EnginePeer(chat.peer)), isContact: true)
    }

    override var isFixedItem: Bool {
        return true
    }

    override var hasRevealState: Bool {
        return false
    }

    override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        return .single([])
    }

    private static func previewMessages(_ chat: HTMLDemoChat) -> [Message] {
        let text = chat.previewText
        guard !text.isEmpty else {
            return []
        }
        var peers = SimpleDictionary<PeerId, Peer>()
        peers[chat.peer.id] = chat.peer
        let message = Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: chat.peer.id, namespace: Namespaces.Message.Local, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: Int32(Date().timeIntervalSince1970), flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: chat.peer, text: text, attributes: [], media: [], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
        return [message]
    }
}
