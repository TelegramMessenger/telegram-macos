import Cocoa
import InputView
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramMediaUtils
import InlineMediaGrid
import ChatModeTypes
import ChatUI
import EntertainmentUI
import ImageCanvasUI
import TextRecognizing

extension ChatMediaContentView: @retroactive EntertainmentStickerContentView {
    public func updateSticker(file: TelegramMediaFile, size: NSSize, context: any AccountContextProtocol, table: TableView?, animated: Bool) {
        self.update(with: file, size: size, context: context, parent: nil, table: table, parameters: nil, animated: animated, positionFlags: nil, approximateSynchronousValue: false)
    }
    public func stickerShake() {
        self.shake()
    }
    public func stickerUpdateMouse() {
        self.updateMouse()
    }
    public func stickerWillRemove() {
        self.willRemove()
    }
}

private func stickerImageDimensions(_ url: URL) -> PixelDimensions {
    if let source = CGImageSourceCreateWithURL(url as CFURL, nil), let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any], let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int {
        return PixelDimensions(width: Int32(width), height: Int32(height))
    }
    return PixelDimensions(width: 512, height: 512)
}

private func makeWholeStickerImage(_ image: CGImage) -> Signal<EntertainmentStickerImage?, NoError> {
    return Signal { subscriber in
        var result: EntertainmentStickerImage?
        if let (data, size) = stickerWebP(from: image) {
            let url = URL(fileURLWithPath: NSTemporaryDirectory() + "sticker_\(Int64.random(in: 0 ... Int64.max)).webp")
            if (try? data.write(to: url)) != nil {
                result = EntertainmentStickerImage(url: url, dimensions: PixelDimensions(width: Int32(size.width), height: Int32(size.height)))
            }
        }
        subscriber.putNext(result)
        subscriber.putCompletion()
        return EmptyDisposable
    }
    |> runOn(.concurrentDefaultQueue())
    |> deliverOnMainQueue
}

private func presentStickerImageEditor(context: any AccountContextProtocol, window: Window, doneMenu: ((EntertainmentStickerImage, @escaping () -> Void) -> [ContextMenuItem])?, completion: @escaping (EntertainmentStickerImage) -> Void) {
    filePanel(with: photoExts + ["webp"], allowMultiple: false, for: window, completion: { paths in
        guard let paths else {
            return
        }
        guard let path = paths.first, let image = NSImage(contentsOfFile: path)?._cgImage else {
            return
        }
        if #available(macOS 14.0, *) {
            let stickerImage: (URL) -> EntertainmentStickerImage = { url in
                return EntertainmentStickerImage(url: url, dimensions: stickerImageDimensions(url))
            }
            let menu: ((URL, @escaping () -> Void) -> [ContextMenuItem])? = doneMenu.map { doneMenu in
                return { url, close in
                    return doneMenu(stickerImage(url), close)
                }
            }
            let controller = EditImageCutoutController(image: image, allowsWholeImage: true, doneMenu: menu, completion: { url in
                completion(stickerImage(url))
            }, closeHandler: {})
            let onDeinit = controller.onDeinit
            controller.onDeinit = {
                onDeinit?()
            }
            showModal(with: controller, for: window, animationType: .scaleCenter)
        } else {
            _ = (makeWholeStickerImage(image)).start(next: { result in
                if let result = result {
                    completion(result)
                } else {
                }
            })
        }
    })
}

func installEntertainmentUIHooks() {
    var hooks = EntertainmentUIHooks(makePreviewSender: { file, chatInteraction in
        return PreviewSenderController(appFile: file, chatInteraction: chatInteraction as! ChatInteraction)
    }, shareLink: { context, link in
        let context = context as! AccountContext
        showModal(with: ShareModalController(ShareLinkObject(context, link: link)), for: context.window)
    }, makeChatInteraction: { context, peerId in
        return ChatInteraction(chatLocation: .peer(peerId), context: context)
    }, currentChatInteraction: { context in
        return (context.bindings.rootNavigation().controller as? ChatInterfaceController)?.chatInteraction
    }, makeTopicIconFile: { title, iconColor, isGeneral in
        return ChatInterfaceHooks.shared.makeTopicIconFile(title, iconColor, isGeneral)
    }, inputSource: { context in
        return ChatInterfaceHooks.shared.inputSource(context)
    }, makeStickerPackPreview: { context, peerId, sources in
        return ChatInputUIHooks.shared.makeStickerPackPreview(context, peerId, sources.map { source in
            switch source {
            case let .stickers(reference):
                return .stickers(reference)
            case let .emoji(reference):
                return .emoji(reference)
            }
        })
    }, previewViewType: { kind in
        switch kind {
        case .gif:
            return GifPreviewModalView.self
        case .animatedSticker:
            return AnimatedStickerPreviewModalView.self
        case .sticker:
            return StickerPreviewModalView.self
        }
    }, makeStickerContentView: { animated, frame in
        return animated ? MediaAnimatedStickerView(frame: frame) : ChatStickerContentView(frame: frame)
    }, makeContextMediaRowItem: { initialSize, row, index, context, arguments, collection, stableId in
        let mediaArguments = ContextMediaArguments(sendResult: arguments.sendResult, menuItems: arguments.menuItems, openMessage: arguments.openMessage, messageMenuItems: arguments.messageMenuItems)
        mediaArguments.drag = { result, point, ended in
            return arguments.drag?(result, point, ended) ?? false
        }
        return ContextMediaRowItem(initialSize, row, index, context, mediaArguments, collection: collection, stableId: stableId)
    }, launchSendFlight: { chatInteraction, view, rect, sourceLayer in
        guard let chatInteraction = chatInteraction as? ChatInteraction, let source = ChatMediaSendFlightSource(view: view, rect: rect, sourceLayer: sourceLayer) else {
            return
        }
        chatInteraction.mediaSendFlight?.launch(source)
    }, makeStickerImage: { context, window, doneMenu, completion in
        presentStickerImageEditor(context: context, window: window, doneMenu: doneMenu, completion: completion)
    }, openStickersBot: { context in
        guard let context = context as? AccountContext else {
            return
        }
        execute(inapp: inApp(for: (context.meUrlPrefix + "stickers").nsstring, context: context, openInfo: { peerId, _, _, _ in
            context.bindings.rootNavigation().push(ChatAdditionController(context: context, chatLocation: .peer(peerId)))
        }))
    })
    hooks.shareLinkWithContext = { context, link in
        showModal(with: ShareModalController(ShareLinkObject(context, link: link)), for: context.window)
    }
    hooks.openStickersBotWithContext = { context in
        guard let context = context as? AccountContext else { return }
        execute(inapp: inApp(for: (context.meUrlPrefix + "stickers").nsstring, context: context, openInfo: { peerId, _, _, _ in
            let controller = ChatAdditionController(context: context, chatLocation: .peer(peerId))
            context.bindings.rootNavigation().push(controller)
        }))
    }
    hooks.makeStickerImageWithContext = { context, window, doneMenu, completion in
        presentStickerImageEditor(context: context, window: window, doneMenu: doneMenu, completion: completion)
    }
    hooks.appendPackEmojiWithContext = { interaction, text in
        if let interaction = interaction as? ChatInteraction {
            interaction.appendTextObserved(text)
        } else {
            _ = interaction.appendText(text, selectedRange: nil)
        }
    }
    hooks.sendPackStickerWithContext = { interaction, file, silent, scheduled in
        if let interaction = interaction as? ChatInteraction {
            interaction.sendAppFileObserved(file, silent, nil, scheduled, nil, nil, nil)
        } else {
            interaction.sendFile(file, silent: silent, query: nil, scheduled: scheduled, collectionId: nil)
        }
    }
    EntertainmentUIHooks.install(hooks)
}
