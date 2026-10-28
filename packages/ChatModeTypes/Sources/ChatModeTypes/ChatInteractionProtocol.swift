import Foundation
import TGUIKit
import TelegramCore
import Postbox
import TelegramContext
import TelegramUtils

public protocol ChatPresentationSnapshot {
    var snapshotPeer: Peer? { get }
    var snapshotCachedData: (any CachedPeerData)? { get }
}

public protocol ChatInteractionProtocol: AnyObject {
    var peerId: PeerId { get }
    var peer: Peer? { get }
    var activitySpace: PeerActivitySpace { get }
    var interactionContext: any AccountContextProtocol { get }
    var presentationPeer: Peer? { get }
    var presentationCachedData: (any CachedPeerData)? { get }
    var presentationSlowMode: SlowMode? { get }
    var presentationSendPaidMessageStars: StarsAmount? { get }
    var presentationIsNormalState: Bool { get }
    var sendPlainText: (String) -> Void { get }
    var sendInlineResult: (ChatContextResultCollection, ChatContextResult) -> Void { get }
    var appendAttributedText: (NSAttributedString) -> Void { get }
    var showEmojiUseTooltip: () -> Void { get }
    func sendFile(_ file: TelegramMediaFile, silent: Bool, query: String?, scheduled: Bool, collectionId: ItemCollectionId?)
    @discardableResult func appendText(_ text: NSAttributedString, selectedRange: Range<Int>?) -> Range<Int>
    func setIsEmojiSection(_ value: Bool)
    func add(observer: Notifable)
    func remove(observer: Notifable)
}
