import Cocoa
import TGUIKit
import InviteLinksUI
import LocalAnimations

func installInviteLinksUIHooks() {
    InviteLinksHooks.install(InviteLinksHooks(makeStickerHeaderItem: { initialSize, stableId, context, sticker, text, stickerSize, bgColor, modify in
        return AnimatedStickerHeaderItem(initialSize, stableId: stableId, context: context as! AccountContext, sticker: sticker, text: text, stickerSize: stickerSize, bgColor: bgColor, modify: modify)
    }, shareLink: { context, link, window in
        showModal(with: ShareModalController(ShareLinkObject(context as! AccountContext, link: link)), for: window)
    }, openPeerInfo: { context, peerId in
        let context = context as! AccountContext
        PeerInfoController.push(navigation: context.bindings.rootNavigation(), context: context, peerId: peerId)
    }, shareQrImage: { context, path, link, window in
        showModal(with: ShareModalController(QrStudioShareObject(context as! AccountContext, path: path, link: link)), for: window)
    }))
}
