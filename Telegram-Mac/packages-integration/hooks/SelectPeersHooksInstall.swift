import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import SelectPeersUI

extension MediaAnimatedStickerView: @retroactive SelectBotRequestStickerView {
    public func updateSelectBotRequestSticker(sticker: LocalAnimatedSticker, size: NSSize, context: any AccountContextProtocol, parent: Message?, table: TableView?, animated: Bool, positionFlags: LayoutPositionFlags?, approximateSynchronousValue: Bool) {
        guard let context = context as? AccountContext else {
            return
        }
        self.update(with: sticker.file, size: size, context: context, parent: parent, table: table, parameters: sticker.parameters, animated: animated, positionFlags: positionFlags, approximateSynchronousValue: approximateSynchronousValue)
    }
}

func installSelectPeersUIHooks() {
    SelectPeersHooks.install(SelectPeersHooks(makeStickerView: { frame in
        return MediaAnimatedStickerView(frame: frame)
    }, stringForRight: { right, isGroup, defaultBannedRights in
        return stringForRight(right: right, isGroup: isGroup, defaultBannedRights: defaultBannedRights)
    }, makeCreateBotModalController: { context, managerUsername, botUsername, botTitle, completion in
        return CreateBotModalController(context: context as! AccountContext, managerUsername: managerUsername, botUsername: botUsername, botTitle: botTitle, openAutomatically: false, viaDeeplink: false, completion: completion)
    }, createGroupDirectly: { context, selectedPeers, requires, onCreate in
        createGroupDirectly(with: context as! AccountContext, selectedPeers: selectedPeers, requires: requires, onCreate: onCreate)
    }, makeCreateChannelController: { context, requires, onComplete in
        return CreateChannelController(context: context as! AccountContext, requires: requires, onComplete: onComplete)
    }, navigateToChat: { navigation, context, chatLocation in
        navigateToChat(navigation: navigation, context: context as! AccountContext, chatLocation: chatLocation)
    }))
}
