import Cocoa
import AppAnalytics
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import GalleryUI
import LocalAnimations
import InlineStickers
import ColorPalette

extension MediaAnimatedStickerView: @retroactive GalleryStickerView {
    public func updateSticker(animation: LocalAnimatedSticker, size: NSSize, context: any AccountContextProtocol) {
        guard let context = context as? AccountContext else {
            return
        }
        self.update(with: animation.file, size: size, context: context, parent: nil, table: nil, parameters: animation.parameters, animated: false, positionFlags: nil, approximateSynchronousValue: false)
    }
}

func installGalleryUIHooks() {
    var hooks = GalleryHooks(makeStickerView: {
        return MediaAnimatedStickerView(frame: NSZeroRect)
    }, openAdUrl: { url, context, openInfo in
        guard let context = context as? AccountContext else {
            return
        }
        let link = inApp(for: url.nsstring, context: context, peerId: nil, openInfo: openInfo, hashtag: nil, command: nil, applyProxy: nil, confirm: false)
        execute(inapp: link)
    }, executeLink: { link, afterComplete in
        if let link = link as? inAppLink {
            execute(inapp: link, afterComplete: afterComplete)
        }
    }, openInfo: { context, peerId, toChat, messageId, initialAction in
        guard let context = context as? AccountContext else {
            return
        }
        let navigation = context.bindings.rootNavigation()
        if toChat {
            if peerId == (navigation.controller as? ChatController)?.chatInteraction.peerId {
                if let messageId = messageId {
                    (navigation.controller as? ChatController)?.chatInteraction.focusMessageId(nil, .init(messageId: messageId, string: nil), TableScrollState.CenterEmpty)
                }
            } else {
                navigation.push(ChatAdditionController(context: context, chatLocation: .peer(peerId), focusTarget: messageId != nil ? .init(messageId: messageId!) : nil, initialAction: initialAction))
            }
        } else {
            PeerInfoController.push(navigation: navigation, context: context, peerId: peerId)
        }
    }, showShare: { context, message, messages, window in
        guard let context = context as? AccountContext else {
            return
        }
        if let messages = messages {
            showModal(with: ShareModalController(ShareMessageObject(context, message, messages)), for: window)
        } else {
            showModal(with: ShareModalController(ShareMessageObject(context, message)), for: window)
        }
    }, makeCaption: { context, message, entities, text, close in
        guard let context = context as? AccountContext else {
            return NSAttributedString(string: text)
        }
        let attr = ChatMessageItem.applyMessageEntities(with: [TextEntitiesMessageAttribute(entities: entities)], for: text, message: message, context: context, fontSize: FontSize.text, openInfo: { peerId, toChat, postId, action in
            let navigation = context.bindings.rootNavigation()
            let controller = navigation.controller
            if toChat {
                if peerId == (controller as? ChatController)?.chatInteraction.peerId {
                    if let postId = postId {
                        (controller as? ChatController)?.chatInteraction.focusMessageId(nil, .init(messageId: postId, string: nil), TableScrollState.CenterEmpty)
                    }
                } else {
                    navigation.push(ChatAdditionController(context: context, chatLocation: .peer(peerId), focusTarget: postId != nil ? .init(messageId: postId!) : nil, initialAction: action))
                }
            } else {
                PeerInfoController.push(navigation: navigation, context: context, peerId: peerId)
            }
            close()
        }, botCommand: { commandText in
            _ = Sender.enqueue(input: ChatTextInputState(inputText: commandText), context: context, peerId: message.id.peerId, replyId: nil, threadId: message.threadId, atDate: nil).start()
            close()
        }, hashtag: { hashtag in
            context.bindings.globalSearch(hashtag, message.id.peerId, nil)
            close()
        }, applyProxy: { server in
            applyExternalProxy(server, accountManager: context.sharedContext.accountManager)
            close()
        }, textColor: NSColor(0xffffff), isDark: true, bubbled: false)
        return attr
    }, makeAdMessageText: { context, message in
        guard let context = context as? AccountContext else {
            return NSAttributedString(string: message.text)
        }
        return ChatMessageItem.applyMessageEntities(with: message.attributes, for: message.text, message: message, context: context, fontSize: 13, openInfo: { _, _, _, _ in }, textColor: .white, linkColor: darkPalette.accent, monospacedPre: .white, monospacedCode: .white, isDark: false, bubbled: false)
    }, showAdAbout: { context, window in
        guard let context = context as? AccountContext else {
            return
        }
        showModal(with: SearchAdAboutController(context: context), for: window)
    }, showTranslate: { context, fromLang, toLang, text, window in
        guard let context = context as? AccountContext else {
            return
        }
        showModal(with: TranslateModalController(context: context, from: fromLang, toLang: toLang, text: text), for: window)
    }, canSendHere: { context, message in
        guard let context = context as? AccountContext else {
            return false
        }
        let controller = context.bindings.rootNavigation().controller
        if let peer = message.peers[message.id.peerId], peer.canSendMessage(media: message.media.first), controller is ChatController {
            return true
        }
        return false
    }, sendHere: { context, path in
        guard let context = context as? AccountContext else {
            return
        }
        guard let controller = context.bindings.rootNavigation().controller as? ChatController else {
            return
        }
        let preview = PreviewSenderController(urls: [.init(fileURLWithPath: path)], chatInteraction: controller.chatInteraction, asMedia: true, attributedString: nil)

        let ready = preview.ready.get() |> take(1)

        _ = ready.start(next: { [weak preview] value in
            delay(0.01, closure: { [weak preview] in
                preview?.runDrawer()
            })
        })
        showModal(with: preview, for: context.window)
    }, openSharedMedia: { context, peerId in
        guard let context = context as? AccountContext else {
            return
        }
        context.bindings.rootNavigation().push(PeerMediaController(context: context, peerId: peerId, isBot: false))
    }, openDownloadSearch: { context in
        guard let context = context as? AccountContext else {
            return
        }
        context.bindings.mainViewController.makeDownloadSearch()
    }, pauseGlobalAudio: { context in
        guard let context = context as? AccountContext else {
            return false
        }
        if let pauseMusic = context.sharedContext.getAudioPlayer()?.pause() {
            return pauseMusic
        }
        return false
    }, resumeGlobalAudio: { context in
        guard let context = context as? AccountContext else {
            return
        }
        _ = context.sharedContext.getAudioPlayer()?.play()
    }, makeRateMenuItem: { volume, minValue, maxValue, midValue, didUpdateValue in
        return SliderContextMenuItem(volume: volume, minValue: minValue, maxValue: maxValue, midValue: midValue, drawable: MenuAnimation.menu_speed, drawable_muted: MenuAnimation.menu_speed, didUpdateValue)
    }, openRecognizedLink: { url, context, openInfo, afterComplete in
        guard let context = context as? AccountContext else {
            return
        }
        let link = inApp(for: url.nsstring, context: context, peerId: nil, openInfo: openInfo, confirm: true)
        execute(inapp: link, afterComplete: afterComplete)
    }, stickerSender: { context, message in
        guard let context = context as? AccountContext else {
            return nil
        }
        guard let controller = context.bindings.rootNavigation().controller as? ChatController, controller.chatInteraction.peerId == message.id.peerId else {
            return nil
        }
        let sticker = TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: 0), partialReference: nil, resource: LocalFileMediaResource(fileId: 0), previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "image/webp", size: nil, attributes: [.Sticker(displayText: "", packReference: nil, maskData: nil)], alternativeRepresentations: [])
        guard let peer = controller.chatInteraction.peer, peer.canSendMessage(controller.chatInteraction.mode.isThreadMode, media: sticker, threadData: controller.chatInteraction.presentation.threadInfo, cachedData: controller.chatInteraction.presentation.cachedData) else {
            return nil
        }
        return { [weak controller] path in
            controller?.chatInteraction.sendMedia([MediaSenderContainer(path: path, isFile: false)])
        }
    })
    hooks.showShareWithContext = { context, message, messages, window, analyticsContext in
        guard let context = context as? AccountContext else { return }
        let journey = AnalyticsShareJourney(context: analyticsContext, entry: messages == nil ? .gallerySelection : .galleryGroup, source: .mediaViewer)
        let object = ShareMessageObject(context, message, messages ?? [])
        let controller = ShareModalController(object, analyticsContext: analyticsContext)
        controller.setAnalyticsShareJourney(journey)
        showModal(with: controller, for: window)
    }
    GalleryHooks.install(hooks)
}
