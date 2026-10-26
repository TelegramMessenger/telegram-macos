import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import TelegramContext
import LocalAnimations
import GeneralRows

public struct InviteLinksHooks {
    public let makeStickerHeaderItem: (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString, NSSize, NSColor?, [String]?) -> TableRowItem
    public let shareLink: (any AccountContextProtocol, String, Window) -> Void
    public let openPeerInfo: (any AccountContextProtocol, PeerId) -> Void
    public let shareQrImage: (any AccountContextProtocol, String, String, Window) -> Void

    public init(makeStickerHeaderItem: @escaping (NSSize, AnyHashable, any AccountContextProtocol, LocalAnimatedSticker?, NSAttributedString, NSSize, NSColor?, [String]?) -> TableRowItem,
                shareLink: @escaping (any AccountContextProtocol, String, Window) -> Void,
                openPeerInfo: @escaping (any AccountContextProtocol, PeerId) -> Void,
                shareQrImage: @escaping (any AccountContextProtocol, String, String, Window) -> Void) {
        self.makeStickerHeaderItem = makeStickerHeaderItem
        self.shareLink = shareLink
        self.openPeerInfo = openPeerInfo
        self.shareQrImage = shareQrImage
    }

    private static var _shared: InviteLinksHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: InviteLinksHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("InviteLinksHooks.install must be called before invite link screens are used")
        return .placeholder
    }

    public static func install(_ hooks: InviteLinksHooks) {
        assert(Thread.isMainThread, "InviteLinksHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = InviteLinksHooks(makeStickerHeaderItem: { initialSize, stableId, _, _, _, _, _, _ in
        GeneralRowItem(initialSize, stableId: stableId)
    }, shareLink: { _, _, _ in

    }, openPeerInfo: { _, _ in

    }, shareQrImage: { _, _, _, _ in

    })
}
