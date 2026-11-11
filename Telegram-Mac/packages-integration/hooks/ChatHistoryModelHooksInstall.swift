import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import InAppSettings
import ChatHistoryModel
import AppAnalytics

func installChatHistoryModelHooks() {
    ChatHistoryModelHooks.install(ChatHistoryModelHooks(applyMessageEntities: { attributes, text, message, context, fontSize, openInfo, textColor, linkColor, monospacedPre, monospacedCode, isDark, bubbled in
        guard let context = context as? AccountContext else {
            return NSAttributedString(string: text)
        }
        return ChatMessageItem.applyMessageEntities(with: attributes, for: text, message: message, context: context, fontSize: fontSize, openInfo: openInfo, textColor: textColor, linkColor: linkColor, monospacedPre: monospacedPre, monospacedCode: monospacedCode, isDark: isDark, bubbled: bubbled)
    }, showAboutCocoonModal: { context in
        guard let context = context as? AccountContext else {
            return
        }
        showAboutCocoonModal(context: context)
    }, getChatInterfaceTempState: { context, peerId in
        guard let context = context as? AccountContext else {
            return nil
        }
        return context.getChatInterfaceTempState(peerId)
    }, isLite: { key in
        return isLite(key)
    }, textInputStateContextQueryRange: { inputState, includeContext in
        if let (range, types, additionalRange) = textInputStateContextQueryRangeAndType(inputState, includeContext: includeContext) {
            return (range, ChatInputContextQueryTypes(rawValue: types.rawValue), additionalRange)
        }
        return nil
    }, makeEmojiPicker: { context, sendAnimatedEmoji, sendEmoji in
        guard let context = context as? AccountContext else {
            return ViewController()
        }
        let emojis = EmojiesController(context, ignorePremium: true)
        emojis.analyticsScreen = .appEmojiPicker
        emojis._frameRect = NSMakeRect(0, 0, 350, 300)
        let interactions = EntertainmentInteractions(.emoji, peerId: context.peerId)
        emojis.update(with: interactions, chatInteraction: ChatInteraction(chatLocation: .peer(context.peerId), context: context))

        interactions.sendAnimatedEmoji = sendAnimatedEmoji
        interactions.sendEmoji = sendEmoji
        return emojis
    }, peerNameColor: { index in
        return theme.chat.peerName(index)
    }, peerIsForum: { peer in
        return peer.isForum
    }, verifyAlert: { window, information, ok, success in
        verifyAlert_button(for: window, information: information, ok: ok, successHandler: { _ in
            success()
        })
    }))
}
