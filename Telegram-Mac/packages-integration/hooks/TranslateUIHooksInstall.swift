import Cocoa
import TGUIKit
import TelegramCore
import TranslateUI
import AppAnalytics

func installTranslateUIHooks() {
    var hooks = TranslateUIHooks(showAboutCocoonModal: { context in
        showAboutCocoonModal(context: context as! AccountContext)
    }, shareLink: { context, link in
        let context = context as! AccountContext
        showModal(with: ShareModalController(ShareLinkObject(context, link: link)), for: context.window)
    }, followResolvedName: { handle, username, context in
        execute(inapp: .followResolvedName(link: handle, username: username, postId: nil, forceProfile: true, context: context as! AccountContext, action: nil, callback: { _, _, _, _ in }))
    }, showStyleEmojiPicker: { context, control, selected in
        let context = context as! AccountContext
        let emojis = EmojiesController(context, mode: .status, ignorePremium: true)
        emojis.analyticsScreen = .appEmojiPicker
        emojis._frameRect = NSMakeRect(0, 0, 350, 300)

        let interactions = EntertainmentInteractions(.emoji, peerId: context.peerId)
        emojis.update(with: interactions, chatInteraction: ChatInteraction(chatLocation: .peer(context.peerId), context: context))

        interactions.sendAnimatedEmoji = { sticker, _, _, _, _ in
            let file = sticker.file._parse()
            selected(file)
            closeAllPopovers(for: context.window)
        }

        showPopover(for: control, with: emojis)
    })
    hooks.shareLinkWithContext = { context, link, analyticsContext in
        showModal(with: ShareModalController(ShareLinkObject(context, link: link), analyticsContext: analyticsContext), for: context.window)
    }
    hooks.showAboutCocoonModalWithContext = { context, analyticsContext in
        showAboutCocoonModal(context: context as! AccountContext, analyticsContext: analyticsContext)
    }
    hooks.showStyleEmojiPickerWithContext = { context, control, analyticsContext, selected in
        let context = context as! AccountContext
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        let emojis = EmojiesController(context, mode: .status, ignorePremium: true)
        emojis.analyticsContext = origin
        emojis.analyticsScreen = .appEmojiPicker
        emojis.showsGlassSurface = true
        emojis._frameRect = NSMakeRect(0, 0, 350, 300)
        let interactions = EntertainmentInteractions(.emoji, peerId: context.peerId)
        let chatInteraction = ChatInteraction(chatLocation: .peer(context.peerId), context: context)
        chatInteraction.inheritedAnalyticsContext = origin
        emojis.update(with: interactions, chatInteraction: chatInteraction)
        interactions.sendAnimatedEmoji = { sticker, _, _, _, _ in
            let current = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: origin)
            let presentation = current.beginPresentation()
            defer { presentation.end() }
            selected(sticker.file._parse())
            closeAllPopovers(for: context.window)
        }
        showPopover(for: control, with: emojis)
    }
    hooks.followResolvedNameWithContext = { handle, username, context, analyticsContext in
        execute(inapp: .followResolvedName(link: handle, username: username, postId: nil, forceProfile: true, context: context as! AccountContext, action: nil, callback: { _, _, _, _ in }), analyticsContext: analyticsContext)
    }
    TranslateUIHooks.install(hooks)
}
