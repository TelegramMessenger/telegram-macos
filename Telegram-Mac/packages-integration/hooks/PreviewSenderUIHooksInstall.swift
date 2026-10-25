import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import PreviewSenderUI
import ImageCanvasUI
import EntertainmentUI
import ChatUI
import AlertsUI
import Localization
import TelegramTheme
import TelegramUtils

extension EmojiesController: @retroactive PreviewSenderEmojiesController {

}

private func mapPreviewSenderEmojiSelectedItem(_ item: PreviewSenderEmojiSelectedItem) -> EmojiesSectionRowItem.SelectedItem {
    let source: EmojiesSectionRowItem.SelectedItem.Source
    switch item.source {
    case let .builtin(emoji):
        source = .builtin(emoji)
    case let .custom(fileId):
        source = .custom(fileId)
    }
    let type: EmojiesSectionRowItem.SelectedItem.Selection
    switch item.type {
    case .normal:
        type = .normal
    case .transparent:
        type = .transparent
    }
    return EmojiesSectionRowItem.SelectedItem(source: source, type: type)
}

func installPreviewSenderUIHooks() {
    PreviewSenderUIHooks.install(PreviewSenderUIHooks(makeEmojies: { context, presentation in
        let emojis = EmojiesController(context as! AccountContext, presentation: presentation)
        return emojis
    }, updateEmojies: { emoji, peerId, sendEmoji, sendAnimatedEmoji, chatInteraction in
        let interactions = EntertainmentInteractions(.emoji, peerId: peerId)

        interactions.sendEmoji = sendEmoji
        interactions.sendAnimatedEmoji = sendAnimatedEmoji

        (emoji as! EmojiesController).update(with: interactions, chatInteraction: chatInteraction)
    }, showMessageEffectsWindow: { context, peerId, selectedItems, react, view in
        let window = ReactionsWindowController(context as! AccountContext, peerId: peerId, selectedItems: selectedItems.map(mapPreviewSenderEmojiSelectedItem), react: react, moveTop: true, mode: .messageEffects)
        window.show(view)
    }))
}

private final class ImageCanvasStickerPickerImpl: EditImageCanvasStickerPicker {
    private let context: AccountContext
    private let entertainment: EntertainmentViewController
    private let chatInteraction: ChatInteraction
    private let disposable = MetaDisposable()
    private let visibilityDisposable = MetaDisposable()
    private var isBound = false
    var visibilityChanged: ((Bool) -> Void)?

    init(context: AccountContext) {
        self.context = context
        self.chatInteraction = ChatInteraction(chatLocation: .peer(PeerId(0)), context: context)
        self.entertainment = EntertainmentViewController(size: NSMakeSize(350, 350), context: context, mode: .common)
        visibilityDisposable.set((entertainment.viewOnStage |> deliverOnMainQueue).start(next: { [weak self] isShown in
            self?.visibilityChanged?(isShown)
        }))
    }

    deinit {
        disposable.dispose()
        visibilityDisposable.dispose()
    }

    func show(for control: Control, select: @escaping (EditImageCanvasStickerPick) -> Void) {
        if !isBound {
            isBound = true
            entertainment.update(with: chatInteraction)
        }
        let interactions = entertainment.interactions
        interactions?.sendSticker = { [weak self] file, _, _, _ in
            self?.render(file, select: select)
            self?.entertainment.closePopover()
        }
        interactions?.sendAnimatedEmoji = { [weak self] item, _, _, _, _ in
            self?.render(item.file._parse(), select: select)
            self?.entertainment.closePopover()
        }
        interactions?.sendEmoji = { [weak self] emoji, _ in
            if let image = ImageCanvasUIHooks.emojiImage(emoji) {
                select(EditImageCanvasStickerPick(image: image, fileId: nil))
            }
            self?.entertainment.closePopover()
        }
        interactions?.sendGIF = { [weak self] _, _, _ in
            self?.entertainment.closePopover()
        }
        showPopover(for: control, with: entertainment)
    }

    func close() {
        entertainment.closePopover()
    }

    private func render(_ file: TelegramMediaFile, select: @escaping (EditImageCanvasStickerPick) -> Void) {
        let size = NSMakeSize(1024, 1024)
        let aspectSize = file.dimensions?.size.aspectFitted(size) ?? size
        let reference = FileMediaReference.standalone(media: file)
        let signal: Signal<ImageDataTransformation, NoError>
        let isVideo = file.fileName == "webm-preview" || file.isVideoSticker
        let animationKind: EditImageCanvasStickerAnimation.Kind?
        if file.mimeType == "image/webp" {
            signal = chatMessageSticker(postbox: context.account.postbox, file: reference, small: false, scale: 1.0, fetched: true, onlyFullSize: true)
            animationKind = nil
        } else {
            signal = chatMessageAnimatedSticker(postbox: context.account.postbox, file: reference, small: false, scale: 1.0, size: aspectSize, fetched: true, onlyFullSize: true, thumbAtFrame: 0, isVideo: isVideo)
            animationKind = isVideo ? .webm : .lottie
        }
        let arguments = TransformImageArguments(corners: ImageCorners(), imageSize: aspectSize, boundingSize: aspectSize, intrinsicInsets: NSEdgeInsets(), scale: 1.0)
        let fileId = file.fileId.id
        let image = signal |> filter { $0.data.fullSizeComplete } |> map { data -> CGImage? in
            return data.execute(arguments, data.data)?.generateImage()
        } |> filter { $0 != nil } |> take(1)
        let animation: Signal<EditImageCanvasStickerAnimation?, NoError>
        if let animationKind = animationKind {
            animation = context.account.postbox.mediaBox.resourceData(file.resource) |> filter { $0.complete } |> take(1) |> map { data in
                return EditImageCanvasStickerAnimation(kind: animationKind, path: data.path)
            }
        } else {
            animation = .single(nil)
        }
        disposable.set((combineLatest(image, animation) |> take(1) |> deliverOnMainQueue).start(next: { image, animation in
            if let image = image {
                select(EditImageCanvasStickerPick(image: image, fileId: fileId, animation: animation))
            }
        }))
    }
}

func installImageCanvasUIHooks() {
    ImageCanvasUIHooks.install(ImageCanvasUIHooks(makeStickerPicker: { context in
        guard let context = context as? AccountContext else {
            return nil
        }
        return ImageCanvasStickerPickerImpl(context: context)
    }, confirm: { window, information, ok, action in
        verifyAlert(for: window, information: information, ok: ok, successHandler: { _ in
            action()
        }, presentation: TelegramThemeHooks.shared.darkAppearance())
    }))
}
