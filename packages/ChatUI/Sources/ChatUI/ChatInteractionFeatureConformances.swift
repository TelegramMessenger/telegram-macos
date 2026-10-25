import Foundation
import Postbox
import TelegramCore
import TelegramContext
import TelegramUtils
import ChatModeTypes
import InputView

extension ChatInteraction: ChatInteractionProtocol {
    public var presentationPeer: Peer? {
        return self.presentation.peer
    }
    public var presentationCachedData: (any CachedPeerData)? {
        return self.presentation.cachedData
    }
    public var presentationSlowMode: SlowMode? {
        return self.presentation.slowMode
    }
    public var presentationSendPaidMessageStars: StarsAmount? {
        return self.presentation.sendPaidMessageStars
    }
    public var presentationIsNormalState: Bool {
        return self.presentation.state == .normal
    }
    public func sendFile(_ file: TelegramMediaFile, silent: Bool, query: String?, scheduled: Bool, collectionId: ItemCollectionId?) {
        self.sendAppFile(file, silent, query, scheduled, collectionId, nil, nil)
    }
    public func setIsEmojiSection(_ value: Bool) {
        self.update({ $0.withUpdatedIsEmojiSection(value) })
    }
}

extension ChatPresentationInterfaceState: ChatPresentationSnapshot {
    public var snapshotPeer: Peer? {
        return self.peer
    }
    public var snapshotCachedData: (any CachedPeerData)? {
        return self.cachedData
    }
}
