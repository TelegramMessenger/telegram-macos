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
import TelegramMediaUtils

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

private final class ImageCanvasEntertainment {
    private static var cached: ImageCanvasEntertainment?

    let entertainment: EntertainmentViewController
    let chatInteraction: ChatInteraction
    private weak var context: AccountContext?
    private let accountsDisposable = MetaDisposable()

    private init(context: AccountContext) {
        self.context = context
        self.chatInteraction = ChatInteraction(chatLocation: .peer(PeerId(0)), context: context)
        self.entertainment = EntertainmentViewController(size: NSMakeSize(350, 350), context: context, mode: .common)
        self.entertainment.update(with: chatInteraction)
    }

    deinit {
        accountsDisposable.dispose()
    }

    static func get(_ context: AccountContext) -> ImageCanvasEntertainment {
        if let cached = cached, cached.context === context {
            return cached
        }
        let value = ImageCanvasEntertainment(context: context)
        cached = value
        let accountId = context.account.id
        value.accountsDisposable.set((context.sharedContext.activeAccounts |> deliverOnMainQueue).start(next: { [weak value] accounts in
            if accounts.primary?.id != accountId, let value, cached === value {
                cached = nil
            }
        }))
        return value
    }
}

private final class ImageCanvasStickerPickerImpl: EditImageCanvasStickerPicker {
    private let context: AccountContext
    private let entertainment: EntertainmentViewController
    private let disposable = MetaDisposable()
    private let dragDisposable = MetaDisposable()
    private let visibilityDisposable = MetaDisposable()
    var visibilityChanged: ((Bool) -> Void)?

    init(context: AccountContext) {
        self.context = context
        self.entertainment = ImageCanvasEntertainment.get(context).entertainment
        visibilityDisposable.set((entertainment.viewOnStage |> deliverOnMainQueue).start(next: { [weak self] isShown in
            self?.visibilityChanged?(isShown)
        }))
    }

    deinit {
        disposable.dispose()
        dragDisposable.dispose()
        visibilityDisposable.dispose()
        let interactions = entertainment.interactions
        interactions?.sendSticker = { _, _, _, _ in }
        interactions?.sendAnimatedEmoji = { _, _, _, _, _ in }
        interactions?.sendEmoji = { _, _ in }
        interactions?.sendGIF = { _, _, _ in }
        interactions?.dragItem = nil
    }

    func show(for control: Control, select: @escaping (EditImageCanvasStickerPick) -> Void, drag: @escaping (EditImageCanvasStickerDrag) -> Void) {
        let interactions = entertainment.interactions
        interactions?.sendSticker = { [weak self] file, _, _, _ in
            self?.pick(.file(file), disposable: self?.disposable, select: select)
            self?.entertainment.closePopover()
        }
        interactions?.sendAnimatedEmoji = { [weak self] item, _, _, _, _ in
            self?.pick(.file(item.file._parse()), disposable: self?.disposable, select: select)
            self?.entertainment.closePopover()
        }
        interactions?.sendEmoji = { [weak self] emoji, _ in
            self?.pick(.emoji(emoji), disposable: self?.disposable, select: select)
            self?.entertainment.closePopover()
        }
        interactions?.sendGIF = { [weak self] file, _, _ in
            self?.pick(.file(file), disposable: self?.disposable, select: select)
            self?.entertainment.closePopover()
        }
        var dragImage: CGImage?
        var isDragging = false
        var lastPoint = NSZeroPoint
        interactions?.dragItem = { [weak self] item, image, phase in
            guard let self else {
                return
            }
            switch phase {
            case let .moved(point):
                lastPoint = point
                if let image = image {
                    dragImage = image
                }
                if !isDragging {
                    isDragging = true
                    drag(.moved(dragImage, point))
                    self.pick(item, disposable: self.dragDisposable, select: { pick in
                        if isDragging {
                            dragImage = pick.image
                            drag(.preview(pick))
                        }
                    })
                } else {
                    drag(.moved(dragImage, point))
                }
            case let .ended(point):
                isDragging = false
                dragImage = nil
                self.dragDisposable.set(nil)
                drag(.ended)
                self.pick(item, disposable: self.disposable, select: { pick in
                    drag(.dropped(pick, point))
                })
            }
        }
        showPopover(for: control, with: entertainment)
    }

    func close() {
        entertainment.closePopover()
    }

    private func pick(_ item: EntertainmentDragItem, disposable: MetaDisposable?, select: @escaping (EditImageCanvasStickerPick) -> Void) {
        switch item {
        case let .emoji(emoji):
            if let image = ImageCanvasUIHooks.emojiImage(emoji) {
                select(EditImageCanvasStickerPick(image: image, fileId: nil))
            }
        case let .file(file):
            if file.isAnimated && file.isVideo && !file.isVideoSticker {
                renderGif(file, disposable: disposable, select: select)
            } else {
                render(file, disposable: disposable, select: select)
            }
        }
    }

    private func renderGif(_ file: TelegramMediaFile, disposable: MetaDisposable?, select: @escaping (EditImageCanvasStickerPick) -> Void) {
        let fileId = file.fileId.id
        let fetch = freeMediaFileInteractiveFetched(context: context, fileReference: .standalone(media: file)).start()
        let signal = context.account.postbox.mediaBox.resourceData(file.resource) |> filter { $0.complete } |> take(1) |> deliverOn(resourcesQueue) |> map { data -> EditImageCanvasStickerPick? in
            guard let image = editImageCanvasVideoPreview(path: data.path) else {
                return nil
            }
            return EditImageCanvasStickerPick(image: image, fileId: fileId, animation: EditImageCanvasStickerAnimation(kind: .video, path: data.path))
        }
        let disposableSet = DisposableSet()
        disposableSet.add(fetch)
        disposableSet.add((signal |> deliverOnMainQueue).start(next: { pick in
            if let pick = pick {
                select(pick)
            }
        }))
        disposable?.set(disposableSet)
    }

    private func render(_ file: TelegramMediaFile, disposable: MetaDisposable?, select: @escaping (EditImageCanvasStickerPick) -> Void) {
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
        disposable?.set((combineLatest(image, animation) |> take(1) |> deliverOnMainQueue).start(next: { image, animation in
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
