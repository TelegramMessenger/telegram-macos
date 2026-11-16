import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import ChatUI

extension ChatRowItem: @retroactive ChatMediaParentRowItem {

}

private func mapChatMediaStickerPackPreviewSource(_ source: ChatMediaStickerPackPreviewSource) -> StickerPackPreviewSource {
    switch source {
    case let .stickers(reference):
        return .stickers(reference)
    case let .emoji(reference):
        return .emoji(reference)
    }
}

func installChatMediaUIHooks() {
    var hooks = ChatMediaUIHooks(getAudioPlayer: { context in
        return (context as? AccountContext)?.sharedContext.getAudioPlayer()
    }, showQuickLookPreview: { context, media, stableId, delegate in
        QuickLookPreview.current.show(context: context as! AccountContext, with: media, stableId: stableId, delegate)
    }, makeStickerPackPreview: { context, peerId, references in
        return StickerPackPreviewModalController(context as! AccountContext, peerId: peerId, references: references.map(mapChatMediaStickerPackPreviewSource))
    })
    hooks.makeStickerPackPreviewWithContext = { context, peerId, references, analyticsContext in
        return StickerPackPreviewModalController(context, peerId: peerId, references: references.map(mapChatMediaStickerPackPreviewSource), analyticsContext: analyticsContext)
    }
    ChatMediaUIHooks.install(hooks)
}
