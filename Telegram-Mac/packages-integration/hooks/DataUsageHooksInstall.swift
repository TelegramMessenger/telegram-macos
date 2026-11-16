import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import DataUsageUI
import HTMLBubbles

extension ChatInteraction: @retroactive StorageUsageChatInteraction {

}

extension PeerMediaGifsView: @retroactive StorageUsageGifsView {

}

extension PeerMediaController: @retroactive StorageUsagePeerMediaController {

}

extension PeerMediaEmptyRowItem: @retroactive StorageUsageEmptyRowItem {

}

private class AddExceptionCallbackObject : ShareObject {
    private let callback:([PeerId])->Signal<Never, NoError>
    private let exceptions: [StorageCacheException]
    private let category: CacheStorageSettings.PeerStorageCategory
    init(_ context: AccountContext, category: CacheStorageSettings.PeerStorageCategory, exceptions: [StorageCacheException], callback:@escaping([PeerId])->Signal<Never, NoError>) {
        self.callback = callback
        self.category = category
        self.exceptions = exceptions
        super.init(context)
    }
    
    override var hasFolders: Bool {
        return false
    }
    
    
    override func statusString(_ peer: Peer, presence: PeerStatusStringResult?, autoDeletion: Int32?) -> String? {
        return nil
    }
    
    override func possibilityPerformTo(_ peer: Peer) -> Bool {
        if exceptions.contains(where: { $0.peer.peer.id == peer.id }) {
            return false
        }
        switch category {
        case .privateChats:
            return peer.isBot || peer.isUser
        case .groups:
            return peer.isGroup || peer.isSupergroup || peer.isGigagroup
        case .channels:
            return peer.isChannel
        case .stories:
            return peer.isUser
        }
    }
    
    override func statusStyle(_ peer: Peer, presence: PeerStatusStringResult?, autoDeletion: Int32?) -> ControlStyle {
        return ControlStyle(font: .normal(.text), foregroundColor: theme.colors.grayText, highlightColor: .white)
    }
    
    override var interactionOk: String {
        return strings().modalDone
    }
    
    override var hasCaptionView: Bool {
        return false
    }
    
    override var multipleSelection: Bool {
        return false
    }
    override var mutableSelection: Bool {
        return false
    }
    override var hasInteraction: Bool {
        return false
    }
    override var selectTopics: Bool {
        return false
    }
    
    override var searchPlaceholderKey: String {
        return "SearchField.Search"
    }
    
    override func perform(to peerIds:[PeerId], threadId: Int64?, comment: ChatTextInputState? = nil, sendPaidMessageStars: [PeerId: StarsAmount] = [:]) -> Signal<Never, String> {
        return callback(peerIds) |> castError(String.self)
    }
}

func installDataUsageUIHooks() {
    DataUsageHooks.install(DataUsageHooks(makeStorageUsageController: { context in
        return StorageUsageController(context as! AccountContext)
    }, shareLink: { context, link in
        guard let context = context as? AccountContext else {
            return
        }
        showModal(with: ShareModalController(ShareLinkObject(context, link: link)), for: context.window)
    }, makeAddExceptionModal: { context, category, exceptions, callback in
        return ShareModalController(AddExceptionCallbackObject(context as! AccountContext, category: category, exceptions: exceptions, callback: callback))
    }, showQuickLookPreview: { context, file, id, gallery in
        QuickLookPreview.current.show(context: context as! AccountContext, with: file, stableId: id, gallery)
    }, getAudioPlayer: { context in
        return (context as! AccountContext).sharedContext.getAudioPlayer()
    }, showInlineAudioPlayer: { controller, context, tableView in
        let object = InlineAudioPlayerView.ContextObject(controller: controller, context: context as! AccountContext, tableView: tableView, supportTableView: nil)
        context.bindings.rootNavigation().header?.show(true, contextObject: object)
    }, openForum: { peerId, addition, context, threadId in
        ForumUI.open(peerId, addition: addition, context: context as! AccountContext, threadId: threadId)
    }, makeChatAdditionController: { context, chatLocation, messageId in
        return ChatAdditionController(context: context as! AccountContext, chatLocation: chatLocation, focusTarget: .init(messageId: messageId))
    }, showChatGallery: { context, message, delegate in
        showChatGallery(context: context, message: message, delegate, nil, type: .alone, chatMode: nil, chatLocation: nil)
    }, clearWidgetStorage: { context, peerId in
        HTMLWidgetStorage.shared.removeAll(basePath: context.account.basePath, peerId: peerId)
    }))
}
