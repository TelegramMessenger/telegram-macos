import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import LocalAnimations
import ForumSettingsUI
import SidebarUI

func installForumSettingsUIHooks() {
    ForumSettingsHooks.install(ForumSettingsHooks(
        makeStickerHeaderItem: { initialSize, stableId, context, sticker, text, stickerSize, bgColor, image in
        AnimatedStickerHeaderItem(initialSize, stableId: stableId, context: context as! AccountContext, sticker: sticker, text: text, stickerSize: stickerSize, bgColor: bgColor, image: image) },
        sidebarImage: { image in
        sidebarImage(image) },
        sidebarPreviewImage: { NSImage(resource: .iconForumSidebar) }
    ))
}
