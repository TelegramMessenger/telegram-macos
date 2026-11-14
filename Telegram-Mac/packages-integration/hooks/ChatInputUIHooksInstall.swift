import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import CodeSyntax
import RichTextEditorUI
import RichTextEditorCore
import ChatUI
import WalletUI
import WalletContext
import AppAnalytics
import InputDataUI
import InAppSettings

extension ChatControllerView: @retroactive ChatInputControllerView {

}

private func mapChatInputStickerPackPreviewSource(_ source: ChatInputStickerPackPreviewSource) -> StickerPackPreviewSource {
    switch source {
    case let .stickers(reference):
        return .stickers(reference)
    case let .emoji(reference):
        return .emoji(reference)
    }
}

private func mapChatInputInAppLink(_ value: Any?) -> ChatInputInAppLink? {
    guard let value = value as? inAppLink else {
        return nil
    }
    switch value {
    case let .external(link, confirm):
        return .external(link: link, confirm)
    default:
        return .other
    }
}

private func makeChatInputWalletHooks() -> Any? {
    if #available(macOS 10.15, *) {
        var hooks = ChatInputWalletHooks(walletContext: { context in
            return (context as! AccountContext).walletContext
        }, makeWalletSendController: { context, walletContext, recipient, handlers in
            let transferAnimation: WalletSendTransferAnimation? = handlers.transferAnimation.map { transferAnimation in
                return { (id: String, source: WalletSendTransferAnimationSource?) -> Bool in
                    return transferAnimation(id, source.flatMap { source in
                        return source.window.map { ChatWalletTransferFlightSource(diamond: source.diamond, window: $0, center: source.center, width: source.width) }
                    })
                }
            }
            switch recipient {
            case let .peer(peer):
                return WalletSendController(context: context as! AccountContext, walletContext: walletContext as! WalletContext, peer: peer, transferAnimation: transferAnimation, transferAnimationWillStart: handlers.transferAnimationWillStart, completed: handlers.completed)
            case let .address(address):
                return WalletSendController(context: context as! AccountContext, walletContext: walletContext as! WalletContext, initialAddress: address)
            }
        })
        hooks.normalizeTransferAddress = { address in
            WalletContext.transferAddress(from: address, preserveBounce: true)
        }
        let makeController = hooks.makeWalletSendController
        hooks.makeWalletSendControllerWithContext = { context, walletContext, peer, handlers, analyticsContext in
            let controller = makeController(context, walletContext, peer, handlers)
            controller.analyticsContext = analyticsContext
            if let controller = controller as? InputDataModalController {
                controller.current.analyticsContext = analyticsContext
            }
            return controller
        }
        return hooks
    }
    return nil
}

func installChatInputUIHooks() {
    var hooks = ChatInputUIHooks(makeEntertainmentsPopover: { chatInteraction in
        if chatInteraction.presentation.state == .editing || chatInteraction.mode.customChatLink != nil {
            let emoji = EmojiesController(chatInteraction.context)
            emoji.analyticsScreen = .chatInputEmoji
            emoji.showsGlassSurface = true
            if let interactions = chatInteraction.context.bindings.entertainmentViewController.interactions {
                emoji.update(with: interactions, chatInteraction: chatInteraction)
            }
            return emoji
        }
        let controller = chatInteraction.context.bindings.entertainmentViewController
        controller.update(with: chatInteraction)
        return controller
    }, makeSuggestPostPanelModel: { data, context in
        return SuggestPostPanelModel(data: data, context: context as! AccountContext)
    }, makeUrlPreviewModel: { context, webpage, url in
        return ChatUrlPreviewModel(context: context as! AccountContext, webpage: webpage, url: url)
    }, makeEditMessageModel: { editState, context in
        return EditMessageModel(state: editState, context: context as! AccountContext)
    }, makeForwardPanelModel: { forwardMessages, hideNames, context in
        return ForwardPanelModel(forwardMessages: forwardMessages, hideNames: hideNames, context: context as! AccountContext)
    }, makeForwardMessagesModal: { context, messages in
        return ShareModalController(ForwardMessagesObject(context as! AccountContext, messages: messages, emptyPerformOnClose: true))
    }, makeTranslateModal: { context, from, toLang, draft, onUse, onSend in
        return TranslateModalController(context: context as! AccountContext, from: from, toLang: toLang, text: draft.inputText, entities: draft.messageTextEntities(), draft: draft, onUse: onUse, onSend: onSend)
    }, makeRichTranslateModal: { context, from, toLang, text, entities, richBlocks, onUseRich in
        return TranslateModalController(context: context as! AccountContext, from: from, toLang: toLang, text: text, entities: entities, richBlocks: richBlocks, onUseRich: onUseRich)
    }, wallet: makeChatInputWalletHooks(), getAudioPlayer: { context in
        return (context as? AccountContext)?.sharedContext.getAudioPlayer()
    }, makeStickerPackPreview: { context, peerId, references in
        return StickerPackPreviewModalController(context as! AccountContext, peerId: peerId, references: references.map(mapChatInputStickerPackPreviewSource))
    }, resolveInAppLink: { value in
        return mapChatInputInAppLink(value)
    }, highlightRichTextSyntax: { language, code, theme, completion in
        let presentationTheme = theme()
        let themeKeys = generateSyntaxThemeParams(presentationTheme, bubbled: false, isIncoming: false)
        let fontSize: CGFloat = 14
        guard let syntaxTheme = SyntaxterTheme(dark: presentationTheme.colors.isDark,
                                               textColor: presentationTheme.colors.text,
                                               textFont: .code(fontSize),
                                               italicFont: .italicMonospace(fontSize),
                                               mediumFont: .semiboldMonospace(fontSize),
                                               themeKeys: themeKeys) else {
            completion([])
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let highlighted = CodeSyntax.syntax(code: code, language: language, theme: syntaxTheme)
            var tokens: [RichTextSyntaxToken] = []
            highlighted.enumerateAttribute(.foregroundColor, in: NSMakeRange(0, highlighted.length), options: []) { value, range, _ in
                if let color = value as? NSColor {
                    tokens.append(RichTextSyntaxToken(range: range, color: color))
                }
            }
            DispatchQueue.main.async {
                completion(tokens)
            }
        }
    }, makeEmojiPicker: { context, sendAnimatedEmoji, sendEmoji in
        let context = context as! AccountContext
        let emojis = EmojiesController(context, ignorePremium: true)
        emojis.analyticsScreen = .appEmojiPicker
        emojis.showsGlassSurface = true
        emojis._frameRect = NSMakeRect(0, 0, 350, 300)
        let interactions = EntertainmentInteractions(.emoji, peerId: context.peerId)
        emojis.update(with: interactions, chatInteraction: ChatInteraction(chatLocation: .peer(context.peerId), context: context))
        interactions.sendAnimatedEmoji = sendAnimatedEmoji
        interactions.sendEmoji = sendEmoji
        return emojis
    }, isEntertainmentSidebarAvailable: { window in
        var result = false
        appDelegate?.enumerateApplicationContexts { applicationContext in
            if applicationContext.isEntertainmentSidebarAvailable(in: window) {
                result = true
            }
        }
        return result
    }, updateEntertainmentSidebar: { animated in
        appDelegate?.enumerateApplicationContexts { applicationContext in
            applicationContext.focusEntertainmentSidebar(FastSettings.sidebarShown, animated: animated)
        }
    }, isEntertainmentSidebarVisible: { window in
        var result = false
        appDelegate?.enumerateApplicationContexts { applicationContext in
            if applicationContext.isEntertainmentSidebarVisible(in: window) {
                result = true
            }
        }
        return result
    })
    hooks.makeTranslateModalWithContext = { context, from, toLang, draft, alwaysUsePeerId, analyticsContext, onUse, onSend in
        TranslateModalController(context: context as! AccountContext, from: from, toLang: toLang, text: draft.inputText, entities: draft.messageTextEntities(), draft: draft, onUse: onUse, onSend: onSend, alwaysUsePeerId: alwaysUsePeerId, analyticsContext: analyticsContext)
    }
    hooks.makeRichTranslateModalWithContext = { context, from, toLang, text, entities, blocks, analyticsContext, onUse in
        TranslateModalController(context: context as! AccountContext, from: from, toLang: toLang, text: text, entities: entities, richBlocks: blocks, onUseRich: onUse, analyticsContext: analyticsContext)
    }
    hooks.makeEmojiPickerWithContext = { context, analyticsContext, sendAnimatedEmoji, sendEmoji in
        let context = context as! AccountContext
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        let emojis = EmojiesController(context, ignorePremium: true)
        emojis.analyticsContext = origin
        emojis.analyticsScreen = .appEmojiPicker
        emojis.showsGlassSurface = true
        emojis._frameRect = NSMakeRect(0, 0, 350, 300)
        let interactions = EntertainmentInteractions(.emoji, peerId: context.peerId)
        let chatInteraction = ChatInteraction(chatLocation: .peer(context.peerId), context: context)
        chatInteraction.inheritedAnalyticsContext = origin
        emojis.update(with: interactions, chatInteraction: chatInteraction)
        interactions.sendAnimatedEmoji = sendAnimatedEmoji
        interactions.sendEmoji = sendEmoji
        return emojis
    }
    ChatInputUIHooks.install(hooks)
}
