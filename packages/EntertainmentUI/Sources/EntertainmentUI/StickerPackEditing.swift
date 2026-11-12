import Cocoa
import AppAnalytics
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import TelegramMediaUtils
import GeneralRows
import InputDataUI
import LocalAnimations
import ChatModeTypes

let stickerPackMaxStickers = 120
private let stickerPackDefaultEmoji = "🫥"

func isOwnStickerPack(_ info: StickerPackCollectionInfo) -> Bool {
    return info.id.namespace == Namespaces.ItemCollection.CloudStickerPacks && info.flags.contains(.isCreator) && !info.flags.contains(.isEmoji)
}

func importSticker(_ image: EntertainmentStickerImage, emojis: [String] = []) -> ImportSticker {
    let resource = LocalFileReferenceMediaResource(localFilePath: image.url.path, randomId: Int64.random(in: Int64.min ... Int64.max), isUniquelyReferencedTemporaryFile: true)
    return ImportSticker(resource: .standalone(resource: resource), emojis: emojis.isEmpty ? [stickerPackDefaultEmoji] : emojis, dimensions: image.dimensions, duration: nil, mimeType: "image/webp", keywords: "")
}

func importSticker(existing file: TelegramMediaFile) -> ImportSticker {
    let reference: FileMediaReference
    if let stickerReference = file.stickerReference {
        reference = .stickerPack(stickerPack: stickerReference, media: file)
    } else {
        reference = .standalone(media: file)
    }
    let emoji = file.stickerText.flatMap { $0.isEmpty ? nil : $0 } ?? stickerPackDefaultEmoji
    return ImportSticker(resource: reference.resourceReference(file.resource), emojis: [emoji], dimensions: file.dimensions ?? PixelDimensions(width: 512, height: 512), duration: file.isVideoSticker ? file.videoDuration : nil, mimeType: file.mimeType, keywords: "")
}

private func stickerFile(_ resource: TelegramMediaResource, image: EntertainmentStickerImage) -> TelegramMediaFile {
    let fileId: MediaId
    if let resource = resource as? CloudDocumentMediaResource {
        fileId = MediaId(namespace: Namespaces.Media.CloudFile, id: resource.fileId)
    } else {
        fileId = MediaId(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min ... Int64.max))
    }
    return TelegramMediaFile(fileId: fileId, partialReference: nil, resource: resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "image/webp", size: nil, attributes: [.FileName(fileName: "sticker.webp"), .Sticker(displayText: stickerPackDefaultEmoji, packReference: nil, maskData: nil), .ImageSize(size: image.dimensions)], alternativeRepresentations: [])
}

private func uploadedStickerFile(context: any AccountContextProtocol, image: EntertainmentStickerImage) -> Signal<TelegramMediaFile?, NoError> {
    return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: context.peerId))
    |> castError(UploadStickerError.self)
    |> mapToSignal { peer -> Signal<UploadStickerStatus, UploadStickerError> in
        guard let peer = peer else {
            return .fail(.generic)
        }
        let resource = LocalFileReferenceMediaResource(localFilePath: image.url.path, randomId: Int64.random(in: Int64.min ... Int64.max), isUniquelyReferencedTemporaryFile: true)
        return context.engine.stickers.uploadSticker(peer: peer, resource: EngineMediaResource(resource), thumbnail: nil, alt: stickerPackDefaultEmoji, dimensions: image.dimensions, duration: nil, mimeType: "image/webp")
    }
    |> map { status -> TelegramMediaFile? in
        if case let .complete(resource, _) = status, let resource = resource._asResource() as? TelegramMediaResource {
            return stickerFile(resource, image: image)
        }
        return nil
    }
    |> filter { $0 != nil }
    |> take(1)
    |> `catch` { _ -> Signal<TelegramMediaFile?, NoError> in
        return .single(nil)
    }
}

func showAddedToStickerPack(context: any AccountContextProtocol, info: StickerPackCollectionInfo, analyticsContext: AnalyticsContext) {
    let presentation = analyticsContext.beginPresentation()
    let controller = StickerPackPreviewModalController(context, peerId: nil, references: [.stickers(.id(id: info.id.id, accessHash: info.accessHash))], analyticsContext: analyticsContext)
    controller.analyticsContext = analyticsContext
    let onDeinit = controller.onDeinit
    controller.onDeinit = {
        onDeinit?()
        presentation.end()
    }
    showModal(with: controller, for: context.window)
    showModalText(for: context.window, text: strings().stickerPackEditingStickerAdded(info.title))
}

private func addStickerToFavorites(context: any AccountContextProtocol, image: EntertainmentStickerImage, analyticsContext: AnalyticsContext, journey: AnalyticsStickerJourney?, done: @escaping () -> Void) {
    let presentation = analyticsContext.beginPresentation()
    defer { withExtendedLifetime(presentation) {} }
    let submission = journey?.beginSubmission()
    let signal = uploadedStickerFile(context: context, image: image)
    |> mapToSignal { file -> Signal<SavedStickerUpdateResult?, NoError> in
        guard let file = file else {
            return .single(nil)
        }
        return context.engine.stickers.saveStickerWithResult(file: file)
        |> map(Optional.init)
        |> `catch` { _ -> Signal<SavedStickerUpdateResult?, NoError> in
            return .single(nil)
        }
    }
    |> deliverOnMainQueue

    _ = analyticsContext.preservingPresentation(showModalProgress(signal: signal, for: context.window)).start(next: { result in
        if let result = result {
            submission?.complete { result.locallyApplied ? .accepted : nil }
        }
        switch result?.result {
        case .some(.generic):
            done()
            showModalText(for: context.window, text: strings().chatContextStickerAddedToFavorites)
        case .some(.limitExceeded):
            done()
            showModalText(for: context.window, text: strings().chatContextFavoriteStickersLimitInfo("\(context.premiumLimits.stickers_faved_limit_premium)"), title: strings().chatContextFavoriteStickersLimitTitle, callback: { _ in
                FeatureNavigationHooks.shared.showPremiumLimitObserved(context, .faveStickers, analyticsContext: analyticsContext)
            })
        case .none:
            submission?.complete { .retryableFailure(.requestFailed) }
            showModalText(for: context.window, text: strings().unknownError)
        }
    }, completed: {
        submission?.end()
    })
}

private func createStickerPack(context: any AccountContextProtocol, title: String, image: EntertainmentStickerImage, analyticsContext: AnalyticsContext, journey: AnalyticsStickerJourney?, done: @escaping () -> Void) {
    let presentation = analyticsContext.beginPresentation()
    defer { withExtendedLifetime(presentation) {} }
    let submission = journey?.beginSubmission()
    let signal = context.engine.stickers.createStickerSet(title: title, shortName: "", stickers: [importSticker(image)], thumbnail: nil, type: .stickers(content: .image), software: nil)
    |> map { status -> StickerPackCollectionInfo? in
        if case let .complete(info, _) = status {
            return info
        }
        return nil
    }
    |> filter { $0 != nil }
    |> take(1)
    |> `catch` { _ -> Signal<StickerPackCollectionInfo?, NoError> in
        return .single(nil)
    }
    |> deliverOnMainQueue

    _ = analyticsContext.preservingPresentation(showModalProgress(signal: signal, for: context.window)).start(next: { info in
        if let info = info {
            submission?.complete { .accepted }
            done()
            showAddedToStickerPack(context: context, info: info, analyticsContext: analyticsContext)
        } else {
            submission?.complete { .retryableFailure(.requestFailed) }
            showModalText(for: context.window, text: strings().unknownError)
        }
    }, completed: {
        submission?.end()
    })
}

private func addStickerToPack(context: any AccountContextProtocol, info: StickerPackCollectionInfo, image: EntertainmentStickerImage, analyticsContext: AnalyticsContext, journey: AnalyticsStickerJourney?, done: @escaping () -> Void) {
    let presentation = analyticsContext.beginPresentation()
    defer { withExtendedLifetime(presentation) {} }
    let submission = journey?.beginSubmission()
    let signal = context.engine.stickers.addStickerToStickerSet(packReference: .id(id: info.id.id, accessHash: info.accessHash), sticker: importSticker(image))
    |> deliverOnMainQueue
    _ = analyticsContext.preservingPresentation(showModalProgress(signal: signal, for: context.window)).start(next: { accepted in
        submission?.complete { accepted ? .accepted : .retryableFailure(.requestFailed) }
    }, error: { _ in
        submission?.complete { .retryableFailure(.requestFailed) }
        showModalText(for: context.window, text: strings().unknownError)
    }, completed: {
        submission?.end()
        done()
        showAddedToStickerPack(context: context, info: info, analyticsContext: analyticsContext)
    })
}

func showNewStickerPackTitle(context: any AccountContextProtocol, analyticsContext: AnalyticsContext, journey: AnalyticsStickerJourney?, apply: @escaping (String) -> Void) {
    showModal(with: StickerPackTitleController(context: context, title: strings().stickerPackEditingNewSet, text: strings().stickerPackEditingNewSetText, value: "", analyticsContext: analyticsContext, journey: journey, apply: apply), for: context.window)
}

func presentCreateSticker(context: any AccountContextProtocol, chatInteraction: (any ChatInteractionProtocol)?, analyticsContext: AnalyticsContext) {
    let journey = AnalyticsStickerJourney(context: analyticsContext, entry: .composerCreate, source: .chatInputStickers)
    let myPacks = Atomic<[StickerPackCollectionInfo]>(value: [])
    _ = context.engine.stickers.getMyStickerSets().start(next: { sets in
        _ = myPacks.swap(sets.map { $0.0 }.filter { $0.id.namespace == Namespaces.ItemCollection.CloudStickerPacks && !$0.flags.contains(.isEmoji) })
    })

    EntertainmentUIHooks.shared.makeStickerImageObserved(context, context.window, analyticsContext: analyticsContext, journey: journey, doneMenu: { image, close in
        var items: [ContextMenuItem] = []
        if let chatInteraction = chatInteraction {
            items.append(ContextMenuItem(strings().stickerPackEditingSendSticker, handler: {
                journey.chooseDestination(.send)
                let request = journey.prepareSend()
                let presentation = analyticsContext.beginPresentation()
                defer { withExtendedLifetime(presentation) {} }
                close()
                EntertainmentUIHooks.shared.sendCreatedStickerObserved(chatInteraction, file: stickerFile(LocalFileReferenceMediaResource(localFilePath: image.url.path, randomId: Int64.random(in: Int64.min ... Int64.max), isUniquelyReferencedTemporaryFile: true), image: image), analyticsContext: analyticsContext, request: request)
            }, itemImage: MenuAnimation.menu_send_now.value))
        }
        items.append(ContextMenuItem(strings().chatContextAddFavoriteSticker, handler: {
            journey.chooseDestination(.favorites)
            addStickerToFavorites(context: context, image: image, analyticsContext: analyticsContext, journey: journey, done: close)
        }, itemImage: MenuAnimation.menu_add_to_favorites.value))

        let packs = ContextMenu()
        packs.addItem(ContextMenuItem(strings().stickerPackEditingNewSet, handler: {
            journey.chooseDestination(.newPack)
            showNewStickerPackTitle(context: context, analyticsContext: analyticsContext, journey: journey, apply: { title in
                createStickerPack(context: context, title: title, image: image, analyticsContext: analyticsContext, journey: journey, done: close)
            })
        }, itemImage: MenuAnimation.menu_plus.value))
        let available = myPacks.with { $0 }
        if !available.isEmpty {
            packs.addItem(ContextSeparatorItem())
        }
        for info in available {
            packs.addItem(ContextMenuItem(info.title, handler: {
                journey.chooseDestination(.existingPack)
                if Int(info.count) >= stickerPackMaxStickers {
                    journey.blocked(.packLimit)
                    showModalText(for: context.window, text: strings().stickerPackEditingSetFull)
                } else {
                    addStickerToPack(context: context, info: info, image: image, analyticsContext: analyticsContext, journey: journey, done: close)
                }
            }))
        }
        let addToPack = ContextMenuItem(strings().stickerPackEditingAddToSet, itemImage: MenuAnimation.menu_add.value)
        addToPack.submenu = packs
        items.append(addToPack)

        return items
    }, completion: { _ in })
}

func showExistingStickerPicker<Context: AccountContextProtocol>(context: Context, control: Control, analyticsContext: AnalyticsContext, journey: AnalyticsStickerJourney? = nil, picked: @escaping (TelegramMediaFile) -> Void) {
    let presentation = analyticsContext.beginPresentation()
    let controller = NStickersViewController(context)
    controller.analyticsContext = analyticsContext
    controller.onDeinit = {
        journey?.endInteraction()
        presentation.end()
    }
    controller.mode = .intro
    let chatInteraction = EntertainmentUIHooks.shared.makeChatInteraction(context, context.peerId)
    let interactions = EntertainmentInteractions(.stickers, peerId: context.peerId)
    interactions.sendSticker = { [weak controller] file, _, _, _ in
        _ = chatInteraction
        journey?.existingStickerSelected()
        picked(file)
        controller?.closePopover()
    }
    controller.update(with: interactions, chatInteraction: chatInteraction)
    showPopover(for: control, with: controller, edge: .maxY, static: true)
}

private let _id_title = InputDataIdentifier("_id_title")

private struct StickerPackTitleState: Equatable {
    var title: String
}

func StickerPackTitleController(context: any AccountContextProtocol, title: String, text: String, value: String, analyticsContext: AnalyticsContext, journey: AnalyticsStickerJourney? = nil, apply: @escaping (String) -> Void) -> InputDataModalController {
    let presentation = analyticsContext.beginPresentation()
    var didResolve = false
    var close: (() -> Void)? = nil

    let initialState = StickerPackTitleState(title: value)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((StickerPackTitleState) -> StickerPackTitleState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state -> InputDataSignalValue in
        var entries: [InputDataEntry] = []
        var sectionId: Int32 = 0
        var index: Int32 = 0

        entries.append(.sectionId(sectionId, type: .customModern(10)))
        sectionId += 1

        entries.append(.input(sectionId: sectionId, index: index, value: .string(state.title), error: nil, identifier: _id_title, mode: .plain, data: .init(viewType: .singleItem), placeholder: nil, inputPlaceholder: strings().stickerPackEditingNamePlaceholder, filter: { $0 }, limit: 64))
        index += 1
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(text), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1

        entries.append(.sectionId(sectionId, type: .customModern(20)))
        sectionId += 1

        return InputDataSignalValue(entries: entries)
    }

    let controller = InputDataController(dataSignal: signal, title: title, afterDisappear: {
        if !didResolve {
            didResolve = true
            journey?.endInteraction()
        }
    })
    controller.analyticsScreen = .stickersSetTitle
    controller.analyticsContext = analyticsContext
    controller.onDeinit = {
        if !didResolve { journey?.endInteraction() }
        presentation.end()
    }

    controller.updateDatas = { data in
        updateState { current in
            var current = current
            current.title = data[_id_title]?.stringValue ?? ""
            return current
        }
        return .none
    }

    controller.validateData = { _ in
        let value = stateValue.with { $0.title }.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty {
            journey?.blocked(.emptyName)
            return .fail(.fields([_id_title: .shake]))
        }
        didResolve = true
        journey?.nameAccepted()
        close?()
        apply(value)
        return .none
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().modalDone, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(300, 300))
    modalController.analyticsContext = analyticsContext

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        didResolve = true
        journey?.cancelNaming()
        modalController?.close()
    })

    close = { [weak modalController] in
        modalController?.modal?.close()
    }

    return modalController
}
