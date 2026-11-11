import Cocoa
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
import AlertsUI
import LocalAnimations
import MessageTextUtils
import ChatModeTypes
import InlineStickerLayer
import PremiumStatusUI
import AppAnalytics


private enum PreviewState {
    enum Source {
        case stickers
        case emoji
    }
    struct Collection {
        let info: StickerPackCollectionInfo
        let items: [StickerPackItem]
        let installed: Bool
    }
    case loading(Source)
    case loaded(source: Source, collections: [Collection])
}


private final class StickerPackArguments {
    let context: any AccountContextProtocol
    let send:(TelegramMediaFile, NSView, Bool, Bool)->Void
    let setEmoji:(TelegramMediaFile)->Void

    let addpack:(PreviewState.Source, PreviewState.Collection, Bool)->Void
    let addAll:(PreviewState.Source, [PreviewState.Collection], Bool)->Void

    let share:(String)->Void
    let close:()->Void
    let previewPremium: (TelegramMediaFile, NSView)->Void
    let closePremium: ()->Void
    let addSticker: (PreviewState.Collection, Control)->Void
    let ownStickerMenu: (PreviewState.Collection, TelegramMediaFile)->[ContextMenuItem]
    let reorderSticker: (PreviewState.Collection, TelegramMediaFile, Int)->Void
    init(context: any AccountContextProtocol, send:@escaping(Media, NSView, Bool, Bool)->Void, setEmoji:@escaping(TelegramMediaFile)->Void, addpack:@escaping(PreviewState.Source, PreviewState.Collection, Bool)->Void, addAll:@escaping(PreviewState.Source, [PreviewState.Collection], Bool)->Void, share:@escaping(String)->Void, close:@escaping()->Void, previewPremium: @escaping(TelegramMediaFile, NSView)->Void, closePremium: @escaping()->Void, addSticker: @escaping(PreviewState.Collection, Control)->Void, ownStickerMenu: @escaping(PreviewState.Collection, TelegramMediaFile)->[ContextMenuItem], reorderSticker: @escaping(PreviewState.Collection, TelegramMediaFile, Int)->Void) {
        self.context = context
        self.send = send
        self.setEmoji = setEmoji
        self.addpack = addpack
        self.addAll = addAll
        self.share = share
        self.close = close
        self.previewPremium = previewPremium
        self.closePremium = closePremium
        self.addSticker = addSticker
        self.ownStickerMenu = ownStickerMenu
        self.reorderSticker = reorderSticker
    }
}

extension FeaturedStickerPackItem : @retroactive Equatable {
    public static func == (lhs: FeaturedStickerPackItem, rhs: FeaturedStickerPackItem) -> Bool {
        return lhs.info == rhs.info && lhs.unread == rhs.unread && lhs.topItems == rhs.topItems
    }
}

public enum StickerPackPreviewSource : Hashable {
    case stickers(StickerPackReference)
    case emoji(StickerPackReference)

    public var reference: StickerPackReference {
        switch self {
        case let .stickers(reference):
            return reference
        case let .emoji(reference):
            return reference
        }
    }
}

public enum StickerPackPreviewModalSource {
    case install
    case installGroupEmojiPack
    case removeGroupEmojiPack
}


private final class StickerPremiumRowItem : GeneralRowItem {
    fileprivate let file: TelegramMediaFile
    fileprivate let context: any AccountContextProtocol
    fileprivate let onClose: () -> Void
    fileprivate let onUnlock: () -> Void

    init(_ initialSize: NSSize, stableId: AnyHashable, file: TelegramMediaFile, context: any AccountContextProtocol, onClose: @escaping () -> Void, onUnlock: @escaping () -> Void) {
        self.file = file
        self.context = context
        self.onClose = onClose
        self.onUnlock = onUnlock
        super.init(initialSize, stableId: stableId)
    }

    override var height: CGFloat {
        return 400
    }

    override func viewClass() -> AnyClass {
        return StickerPremiumRowView.self
    }
    
    override var accessibilityLabel: String? {
        return file.stickerText ?? strings().voiceOverCommonSticker
    }

    override var hasBorder: Bool {
        return false
    }
}

private final class StickerPremiumRowView : TableRowView {
    private var holder: StickerPremiumHolderView?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? StickerPremiumRowItem else { return }

        if holder == nil {
            let holder = StickerPremiumHolderView(frame: bounds)
            addSubview(holder)
            self.holder = holder
        }
        holder?.frame = bounds
        holder?.close = item.onClose
        holder?.set(file: item.file, context: item.context, callback: item.onUnlock)
    }

    override func layout() {
        super.layout()
        holder?.frame = bounds
    }
}


private final class StickerLoadingRowItem : GeneralRowItem {
    override var height: CGFloat {
        return 300
    }

    override func viewClass() -> AnyClass {
        return StickerLoadingRowView.self
    }
    
    override var accessibilityLabel: String? {
        return strings().voiceOverCommonLoading
    }
    
    override var accessibilityRole: NSAccessibility.Role? {
        return .staticText
    }
    
    override var accessibilityIncludesChildren: Bool {
        return false
    }

    override var hasBorder: Bool {
        return false
    }
}

private final class StickerLoadingRowView : TableRowView {
    private let indicator = ProgressIndicator(frame: NSMakeRect(0, 0, 30, 30))

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(indicator)
        indicator.animates = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func layout() {
        super.layout()
        indicator.center()
    }
}


private struct State : Equatable {
    var preview: PreviewStateEquatable
    var installed: Set<StickerPackPreviewSource>
    var premiumFile: TelegramMediaFile?
    var isEditing: Bool = false
    var titleOverride: String?

    static func == (lhs: State, rhs: State) -> Bool {
        return lhs.preview === rhs.preview
            && lhs.installed == rhs.installed
            && lhs.premiumFile?.fileId == rhs.premiumFile?.fileId
            && lhs.isEditing == rhs.isEditing
            && lhs.titleOverride == rhs.titleOverride
    }
}

private final class PreviewStateEquatable {
    let value: PreviewState
    init(_ value: PreviewState) {
        self.value = value
    }
}


private func entries(_ state: State, controllerSource: StickerPackPreviewModalSource, arguments: StickerPackArguments, premiumFile: TelegramMediaFile?) -> [InputDataEntry] {
    var result: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    if let premiumFile {
        result.append(.sectionId(sectionId, type: .customModern(0)))
        sectionId += 1
        result.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: InputDataIdentifier("premium_preview"), equatable: .init(premiumFile.fileId.id), comparable: nil, item: { initialSize, stableId in
            return StickerPremiumRowItem(initialSize, stableId: stableId, file: premiumFile, context: arguments.context, onClose: {
                arguments.closePremium()
            }, onUnlock: {
                FeatureNavigationHooks.shared.showPremiumBoarding(arguments.context, arguments.context.window, .premiumStickers, false, nil)
                arguments.closePremium()
            })
        }))
        index += 1
        return result
    }

    switch state.preview.value {
    case .loading:
        result.append(.sectionId(sectionId, type: .customModern(0)))
        sectionId += 1
        result.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: InputDataIdentifier("loading"), equatable: nil, comparable: nil, item: { initialSize, stableId in
            return StickerLoadingRowItem(initialSize, stableId: stableId)
        }))
        index += 1
    case let .loaded(source, collections):
        let isInstalled: (PreviewState.Collection) -> Bool = { collection in
            if collection.installed { return true }
            switch source {
            case .emoji:
                return state.installed.contains(.emoji(.name(collection.info.shortName)))
            case .stickers:
                return state.installed.contains(.stickers(.name(collection.info.shortName)))
            }
        }

        result.append(.sectionId(sectionId, type: .customModern(4)))
        sectionId += 1

        let stickerArguments = StickerPanelArguments(context: arguments.context, sendMedia: { media, view, silent, schedule, _ in
            if let media = media as? TelegramMediaFile {
                if media.isPremiumSticker && !arguments.context.isPremium {
                    arguments.previewPremium(media, view)
                } else {
                    arguments.send(media, view, silent, schedule)
                }
            }
        }, showPack: { _ in
        }, addPack: { _ in
        }, navigate: { _ in
        }, clearRecent: {
        }, removePack: { _ in
        }, closeInlineFeatured: { _ in
        }, openFeatured: { _ in
        }, selectEmojiCategory: { _ in
        }, mode: .common, canSchedule: {
            let interactions = EntertainmentUIHooks.shared.currentChatInteraction(arguments.context)
            return interactions?.presentationSendPaidMessageStars == nil
        })

        for collection in collections {
            let installed = isInstalled(collection)
            switch source {
            case .emoji:
                let chunks = collection.items.chunks(32)
                for (i, items) in chunks.enumerated() {
                    let info: StickerPackCollectionInfo? = i != 0 ? nil : collection.info
                    let ids = items.map { $0.file.fileId.id }
                    result.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: InputDataIdentifier("emoji_\(collection.info.id.id)_\(i)"), equatable: .init(EmojiChunkEquatable(ids: ids, installed: installed)), comparable: nil, item: { initialSize, stableId in
                        return EmojiesSectionRowItem(initialSize, stableId: stableId, context: arguments.context, revealed: true, installed: installed, info: info, items: items, mode: .preview, callback: { item, _, _, _ in
                            arguments.setEmoji(item.file._parse())
                        }, installPack: { _, _ in
                            arguments.addpack(source, collection, false)
                        })
                    }))
                    index += 1
                }
            case .stickers:
                let files = collection.items.map { $0.file._parse() }
                let ids = files.map { $0.fileId.id }
                let isOwn = controllerSource == .install && collections.count == 1 && isOwnStickerPack(collection.info)
                let canAdd = isOwn && collection.items.count < stickerPackMaxStickers
                let isEditing = isOwn && state.isEditing
                let addTile: StickerPackPanelAddTile? = canAdd ? StickerPackPanelAddTile(position: .trailing, accessibilityLabel: strings().stickerPackPreviewModalControllerAddSticker, action: { control in
                    arguments.addSticker(collection, control)
                }) : nil
                let editing: StickerPackPanelEditing? = isOwn ? StickerPackPanelEditing(isEditing: isEditing, menuItems: { file in
                    return arguments.ownStickerMenu(collection, file)
                }, reorder: { file, index in
                    arguments.reorderSticker(collection, file, index)
                }) : nil
                result.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: InputDataIdentifier("stickers_\(collection.info.id.id)"), equatable: .init(StickerChunkEquatable(ids: ids, installed: installed, canAdd: canAdd, isEditing: isEditing)), comparable: nil, item: { initialSize, stableId in
                    return StickerPackPanelRowItem(initialSize, context: arguments.context, arguments: stickerArguments, files: files, packInfo: .emojiRelated, collectionId: .pack(collection.info.id), canSend: EntertainmentUIHooks.shared.currentChatInteraction(arguments.context) != nil, isPreview: true, addTile: addTile, editing: editing)
                }))
                index += 1
            }
        }

        result.append(.sectionId(sectionId, type: .customModern(10)))
        sectionId += 1
    }

    return result
}

private struct EmojiChunkEquatable : Equatable {
    let ids: [Int64]
    let installed: Bool
}

private struct StickerChunkEquatable : Equatable {
    let ids: [Int64]
    let installed: Bool
    let canAdd: Bool
    let isEditing: Bool
}


public func StickerPackPreviewModalController(_ context: any AccountContextProtocol, peerId: PeerId?, references: [StickerPackPreviewSource], onAdd: (() -> Void)? = nil, source controllerSource: StickerPackPreviewModalSource = .install, analyticsContext: AnalyticsContext? = nil) -> InputDataModalController {

    let origin = Analytics.shared.captureContext(engine: context.engine, peerId: peerId ?? context.peerId, inherited: analyticsContext ?? Analytics.shared.unresolvedContext())
    let presentation = origin.beginPresentation()
    defer { presentation.end() }
    let actionsDisposable = DisposableSet()
    let getAnalyticsContext: () -> AnalyticsContext = {
        Analytics.shared.captureContext(engine: context.engine, peerId: peerId ?? context.peerId, inherited: origin)
    }

    let initialState = State(preview: PreviewStateEquatable(.loading(.stickers)), installed: Set(), premiumFile: nil)
    let statePromise = ValuePromise<State>(initialState, ignoreRepeated: true)
    let stateValue = Atomic<State>(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        statePromise.set(stateValue.modify(f))
    }

    var close: (() -> Void)? = nil

    let reloadCounter = Atomic<Int>(value: 0)
    let reloadPromise = ValuePromise<Int>(0, ignoreRepeated: true)
    let reload: () -> Void = {
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        reloadPromise.set(reloadCounter.modify { $0 + 1 })
    }

    let packReference: (PreviewState.Collection) -> StickerPackReference = { collection in
        return .id(id: collection.info.id.id, accessHash: collection.info.accessHash)
    }

    let currentItems: (PreviewState.Collection) -> [StickerPackItem] = { collection in
        if case let .loaded(_, collections) = stateValue.with({ $0.preview.value }), let value = collections.first(where: { $0.info.id == collection.info.id }) {
            return value.items
        }
        return collection.items
    }

    let updateItems: (PreviewState.Collection, ([StickerPackItem]) -> [StickerPackItem]) -> Void = { collection, f in
        updateState { current in
            var current = current
            if case let .loaded(source, collections) = current.preview.value {
                current.preview = PreviewStateEquatable(.loaded(source: source, collections: collections.map { value in
                    if value.info.id == collection.info.id {
                        return PreviewState.Collection(info: value.info, items: f(value.items), installed: value.installed)
                    }
                    return value
                }))
            }
            return current
        }
    }

    let setEditing: (Bool) -> Void = { value in
        updateState { current in
            var current = current
            current.isEditing = value
            return current
        }
    }

    let addToPack: (PreviewState.Collection, ImportSticker, AnalyticsContext, AnalyticsStickerJourney) -> Void = { collection, sticker, analyticsContext, journey in
        let presentation = analyticsContext.beginPresentation()
        defer { withExtendedLifetime(presentation) {} }
        let submission = journey.beginSubmission()
        let title = stateValue.with { $0.titleOverride } ?? collection.info.title
        _ = analyticsContext.preservingPresentation(showModalProgress(signal: context.engine.stickers.addStickerToStickerSet(packReference: packReference(collection), sticker: sticker), for: context.window) |> deliverOnMainQueue).start(next: { accepted in
            submission?.complete { accepted ? .accepted : .terminalFailure(.requestFailed) }
        }, error: { _ in
            submission?.complete { .terminalFailure(.requestFailed) }
            showModalText(for: context.window, text: strings().unknownError)
        }, completed: {
            submission?.end()
            reload()
            showModalText(for: context.window, text: strings().stickerPackPreviewModalControllerStickerAdded(title))
        })
    }

    let replaceSticker: (PreviewState.Collection, TelegramMediaFile) -> Void = { collection, file in
        let analyticsContext = getAnalyticsContext()
        let journey = AnalyticsStickerJourney(context: analyticsContext, entry: .packReplace, source: .stickersSet)
        let emojis = currentItems(collection).first(where: { $0.file.fileId == file.fileId })?.getStringRepresentationsOfIndexKeys() ?? []
        EntertainmentUIHooks.shared.makeStickerImageObserved(context, context.window, analyticsContext: analyticsContext, journey: journey, doneMenu: nil, completion: { image in
            let submission = journey.beginSubmission()
            _ = analyticsContext.preservingPresentation(showModalProgress(signal: context.engine.stickers.replaceStickerWithResult(previousSticker: .stickerPack(stickerPack: packReference(collection), media: file), sticker: importSticker(image, emojis: emojis)), for: context.window) |> deliverOnMainQueue).start(next: { applied in
                submission?.complete { applied ? .accepted : nil }
            }, error: { _ in
                submission?.complete { .terminalFailure(.requestFailed) }
                showModalText(for: context.window, text: strings().unknownError)
            }, completed: {
                submission?.end()
                reload()
                showModalText(for: context.window, text: strings().stickerPackPreviewModalControllerStickerUpdated)
            })
        })
    }

    let deleteSticker: (PreviewState.Collection, TelegramMediaFile) -> Void = { collection, file in
        let analyticsContext = getAnalyticsContext()
        let presentation = analyticsContext.beginPresentation()
        defer { presentation.end() }
        let remaining = currentItems(collection).filter { $0.file.fileId != file.fileId }
        if remaining.isEmpty {
            _ = analyticsContext.preservingPresentation(context.engine.stickers.deleteStickerSet(packReference: packReference(collection))).start()
            close?()
        } else {
            updateItems(collection, { _ in remaining })
            _ = analyticsContext.preservingPresentation(context.engine.stickers.deleteStickerFromStickerSet(sticker: .stickerPack(stickerPack: packReference(collection), media: file))).start()
        }
    }

    let editTitle: (PreviewState.Collection) -> Void = { collection in
        let analyticsContext = getAnalyticsContext()
        let journey = AnalyticsStickerJourney(context: analyticsContext, entry: .packRename, source: .stickersSet)
        let value = stateValue.with { $0.titleOverride } ?? collection.info.title
        showModal(with: StickerPackTitleController(context: context, title: strings().stickerPackPreviewModalControllerEditNameTitle, text: strings().stickerPackPreviewModalControllerEditNameText, value: value, analyticsContext: analyticsContext, journey: journey, apply: { title in
            updateState { current in
                var current = current
                current.titleOverride = title
                return current
            }
            let submission = journey.beginSubmission()
            _ = analyticsContext.preservingPresentation(context.engine.stickers.renameStickerSetWithResult(packReference: packReference(collection), title: title)).start(next: { applied in
                submission?.complete { applied ? .accepted : nil }
            }, error: { _ in
                submission?.complete { .terminalFailure(.requestFailed) }
            }, completed: {
                submission?.end()
            })
        }), for: context.window)
    }

    let deletePack: (PreviewState.Collection) -> Void = { collection in
        let analyticsContext = getAnalyticsContext()
        let presentation = analyticsContext.beginPresentation()
        defer { presentation.end() }
        let confirmationPresentation = analyticsContext.beginPresentation()
        verifyAlert(for: context.window, header: strings().stickerPackPreviewModalControllerDeleteSetHeader, information: strings().stickerPackPreviewModalControllerDeleteSetInfo, ok: strings().messageContextDelete, successHandler: { _ in
            let presentation = analyticsContext.beginPresentation()
            defer { presentation.end() }
            _ = analyticsContext.preservingPresentation(context.engine.stickers.deleteStickerSet(packReference: packReference(collection))).start()
            close?()
        }, onDeinit: {
            confirmationPresentation.end()
        })
    }

    let arguments = StickerPackArguments(context: context, send: { media, view, silent, schedule in
        let analyticsContext = getAnalyticsContext()
        let presentation = analyticsContext.beginPresentation()
        defer { presentation.end() }
        let interactions = EntertainmentUIHooks.shared.currentChatInteraction(context)
        if let interactions = interactions, let media = media as? TelegramMediaFile, media.maskData == nil {
            if let slowMode = interactions.presentationSlowMode, slowMode.hasLocked {
                showSlowModeTimeoutTooltip(slowMode, for: view)
            } else {
                EntertainmentUIHooks.shared.sendPackStickerObserved(interactions, file: media, silent: silent, scheduled: schedule, analyticsContext: analyticsContext)
                close?()
            }
        }
    }, setEmoji: { file in
        let analyticsContext = getAnalyticsContext()
        let presentation = analyticsContext.beginPresentation()
        defer { presentation.end() }
        let interactions = EntertainmentUIHooks.shared.currentChatInteraction(context)
        guard let interactions = interactions else { return }
        if context.isPremium {
            if interactions.presentationIsNormalState {
                EntertainmentUIHooks.shared.appendPackEmojiObserved(interactions, text: .makeAnimated(file, text: file.customEmojiText ?? ""), analyticsContext: analyticsContext)
                interactions.showEmojiUseTooltip()
                close?()
            }
        } else {
            showModalText(for: context.window, text: strings().emojiPackPremiumAlert, callback: { _ in
                let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext)
                FeatureNavigationHooks.shared.showPremiumBoardingObserved(context, context.window, .premiumEmoji, false, nil, analyticsContext: origin)
            })
        }
    }, addpack: { source, collection, shouldClose in
        let analyticsContext = getAnalyticsContext()
        let presentation = analyticsContext.beginPresentation()
        defer { presentation.end() }
        switch controllerSource {
        case .install:
            let title: String
            let text: String
            if !collection.installed {
                _ = analyticsContext.preservingPresentation(context.engine.stickers.addStickerPackInteractively(info: collection.info, items: collection.items)).start()
                switch source {
                case .stickers:
                    title = strings().stickerPackAddedTitle
                    text = strings().stickerPackAddedInfo(collection.info.title)
                case .emoji:
                    title = strings().emojiPackAddedTitle
                    text = strings().emojiPackAddedInfo(collection.info.title)
                }
            } else {
                switch source {
                case .stickers:
                    title = strings().stickerPackRemovedTitle
                    text = strings().stickerPackRemovedInfo(collection.info.title)
                case .emoji:
                    title = strings().emojiPackRemovedTitle
                    text = strings().emojiPackRemovedInfo(collection.info.title)
                }
                _ = analyticsContext.preservingPresentation(context.engine.stickers.removeStickerPackInteractively(id: collection.info.id, option: .archive)).start()
            }
            showModalText(for: context.window, text: text, title: title)

            if shouldClose {
                close?()
            } else {
                updateState { current in
                    var current = current
                    switch source {
                    case .emoji:
                        current.installed.insert(.emoji(.name(collection.info.shortName)))
                    case .stickers:
                        current.installed.insert(.stickers(.name(collection.info.shortName)))
                    }
                    return current
                }
            }
            onAdd?()
        default:
            close?()
            onAdd?()
        }
    }, addAll: { source, collections, shouldClose in
        let analyticsContext = getAnalyticsContext()
        let presentation = analyticsContext.beginPresentation()
        defer { presentation.end() }
        let signals = collections.map {
            context.engine.stickers.addStickerPackInteractively(info: $0.info, items: $0.items)
        }
        _ = analyticsContext.preservingPresentation(combineLatest(signals)).start()

        if shouldClose {
            close?()
        } else {
            updateState { current in
                var current = current
                for collection in collections {
                    switch source {
                    case .emoji:
                        current.installed.insert(.emoji(.name(collection.info.shortName)))
                    case .stickers:
                        current.installed.insert(.stickers(.name(collection.info.shortName)))
                    }
                }
                return current
            }
        }

        onAdd?()

    }, share: { link in
        let analyticsContext = getAnalyticsContext()
        let presentation = analyticsContext.beginPresentation()
        defer { presentation.end() }
        close?()
        EntertainmentUIHooks.shared.shareLinkObserved(context, link, analyticsContext: analyticsContext)
    }, close: {
        close?()
    }, previewPremium: { file, _ in
        updateState { current in
            var current = current
            current.premiumFile = file
            return current
        }
    }, closePremium: {
        updateState { current in
            var current = current
            current.premiumFile = nil
            return current
        }
    }, addSticker: { collection, control in
        guard let event = NSApp.currentEvent else {
            return
        }
        var items: [ContextMenuItem] = []
        items.append(ContextMenuItem(strings().stickerPackPreviewModalControllerCreateSticker, handler: {
            let analyticsContext = getAnalyticsContext()
            let journey = AnalyticsStickerJourney(context: analyticsContext, entry: .packAddImage, source: .stickersSet)
            EntertainmentUIHooks.shared.makeStickerImageObserved(context, context.window, analyticsContext: analyticsContext, journey: journey, doneMenu: nil, completion: { image in
                addToPack(collection, importSticker(image), analyticsContext, journey)
            })
        }, itemImage: MenuAnimation.menu_plus.value))
        items.append(ContextMenuItem(strings().stickerPackPreviewModalControllerAddExistingSticker, handler: { [weak control] in
            guard let control = control else {
                return
            }
            let analyticsContext = getAnalyticsContext()
            let journey = AnalyticsStickerJourney(context: analyticsContext, entry: .packAddExisting, source: .stickersSet)
            showExistingStickerPicker(context: context, control: control, analyticsContext: analyticsContext, journey: journey, picked: { file in
                addToPack(collection, importSticker(existing: file), analyticsContext, journey)
            })
        }, itemImage: MenuAnimation.menu_view_sticker_set.value))
        ContextMenu.show(items: items, view: control, event: event)
    }, ownStickerMenu: { collection, file in
        var items: [ContextMenuItem] = []
        items.append(ContextMenuItem(strings().stickerPackPreviewModalControllerReplaceSticker, handler: {
            replaceSticker(collection, file)
        }, itemImage: MenuAnimation.menu_replace.value))
        if !stateValue.with({ $0.isEditing }) {
            items.append(ContextMenuItem(strings().stickerPackPreviewModalControllerReorder, handler: {
                setEditing(true)
            }, itemImage: MenuAnimation.menu_list.value))
        }
        let delete = ContextMenuItem(strings().messageContextDelete, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value)
        let submenu = ContextMenu()
        submenu.addItem(ContextMenuItem(strings().stickerPackPreviewModalControllerDeleteForEveryone, handler: {
            deleteSticker(collection, file)
        }, itemMode: .destruct))
        delete.submenu = submenu
        items.append(delete)
        return items
    }, reorderSticker: { collection, file, index in
        let analyticsContext = getAnalyticsContext()
        let presentation = analyticsContext.beginPresentation()
        defer { presentation.end() }
        updateItems(collection, { items in
            var items = items
            if let from = items.firstIndex(where: { $0.file.fileId == file.fileId }) {
                let item = items.remove(at: from)
                items.insert(item, at: min(index, items.count))
            }
            return items
        })
        _ = analyticsContext.preservingPresentation(context.engine.stickers.reorderSticker(sticker: .standalone(media: file), position: index)).start()
    })

    let signal = origin.preservingPresentation(statePromise.get() |> deliverOnPrepareQueue) |> map { state -> InputDataSignalValue in
        return InputDataSignalValue(entries: entries(state, controllerSource: controllerSource, arguments: arguments, premiumFile: state.premiumFile))
    }

    let modalTitle: String
    switch controllerSource {
    case .installGroupEmojiPack:
        modalTitle = strings().stickerPackPreviewSetGroup
    case .removeGroupEmojiPack:
        modalTitle = strings().stickerPackPreviewRemoveGroup
    case .install:
        if let first = references.first, case .emoji = first {
            modalTitle = strings().stickerPackEmoji
        } else {
            modalTitle = strings().stickerPackStickers
        }
    }

    let controller = InputDataController(dataSignal: signal, title: modalTitle)
    controller.analyticsContext = origin
    controller.analyticsScreen = .stickersSet

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let pendingAddAction: Atomic<(() -> Void)?> = Atomic(value: nil)

    let modalInteractions = ModalInteractions(acceptTitle: "", accept: {
        pendingAddAction.with { $0 }?()
    }, singleButton: true)
    modalInteractions.isEventless = true

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(350, 400))
    modalController.analyticsContext = origin
    modalController.fixedHeight = 300

    close = { [weak modalController] in
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        modalController?.close()
    }

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: {
        close?()
    })

    controller.rightModalHeader = ModalHeaderData(image: theme.icons.chatActionsActive, handler: {
    }, contextMenu: {
        let state = stateValue.with { $0 }
        guard case let .loaded(source, collections) = state.preview.value else {
            return []
        }
        var items: [ContextMenuItem] = []

        items.append(ContextMenuItem(strings().modalShare, handler: {
            let shareText: String = collections.reduce("", { current, value in
                let text: String
                switch source {
                case .emoji:
                    text = context.meUrlPrefix + "addemoji/\(value.info.shortName)"
                case .stickers:
                    text = context.meUrlPrefix + "addstickers/\(value.info.shortName)"
                }
                return current + text + "\n"
            })
            arguments.share(shareText.trimmed)
        }, itemImage: MenuAnimation.menu_share.value))

        if controllerSource == .install, collections.count == 1 {
            let collection = collections[0]
            let isInstalled: Bool = {
                if collection.installed { return true }
                switch source {
                case .emoji:
                    return state.installed.contains(.emoji(.name(collection.info.shortName)))
                case .stickers:
                    return state.installed.contains(.stickers(.name(collection.info.shortName)))
                }
            }()
            if source == .stickers, isOwnStickerPack(collection.info) {
                items.append(ContextSeparatorItem())
                if !collection.items.isEmpty, !state.isEditing {
                    items.append(ContextMenuItem(strings().stickerPackPreviewModalControllerReorder, handler: {
                        setEditing(true)
                    }, itemImage: MenuAnimation.menu_list.value))
                }
                items.append(ContextMenuItem(strings().stickerPackPreviewModalControllerEditName, handler: {
                    editTitle(collection)
                }, itemImage: MenuAnimation.menu_edit.value))
                let deleteHandler: (() -> Void)? = isInstalled ? nil : {
                    deletePack(collection)
                }
                let delete = ContextMenuItem(strings().messageContextDelete, handler: deleteHandler, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value)
                if isInstalled {
                    let submenu = ContextMenu()
                    submenu.addItem(ContextMenuItem(strings().stickerPackPreviewModalControllerDeleteForEveryone, handler: {
                        deletePack(collection)
                    }, itemMode: .destruct))
                    submenu.addItem(ContextMenuItem(strings().stickerPackPreviewModalControllerRemoveForMe, handler: {
                        arguments.addpack(source, collection, true)
                    }))
                    delete.submenu = submenu
                }
                items.append(delete)
                items.append(ContextSeparatorItem())
                items.append(ContextMenuItem(strings().stickerPackPreviewModalControllerStickersBotHint, handler: {
                    let analyticsContext = getAnalyticsContext()
                    let presentation = analyticsContext.beginPresentation()
                    defer { presentation.end() }
                    close?()
                    EntertainmentUIHooks.shared.openStickersBotObserved(context, analyticsContext: analyticsContext)
                }))
            } else if isInstalled {
                items.append(ContextMenuItem(strings().messageContextDelete, handler: {
                    arguments.addpack(source, collection, true)
                }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
            }
        }

        return items
    })

    func namespaceForMode(_ mode: StickerPackPreviewSource) -> ItemCollectionId.Namespace {
        switch mode {
        case .stickers:
            return Namespaces.ItemCollection.CloudStickerPacks
        case .emoji:
            return Namespaces.ItemCollection.CloudEmojiPacks
        }
    }
    let namespaces = references.map { namespaceForMode($0) }
    let namespace = namespaces.first ?? Namespaces.ItemCollection.CloudStickerPacks

    let packsSignal = origin.preservingPresentation(reloadPromise.get()) |> mapToSignal { _ in
        return combineLatest(references.map {
            context.engine.stickers.loadedStickerPack(reference: $0.reference, forceActualized: true)
        })
    } |> deliverOnMainQueue

    actionsDisposable.add(origin.preservingPresentation(packsSignal).start(next: { [weak modalController] result in
        let isEmpty = result.filter { value in
            switch value {
            case .none: return true
            default: return false
            }
        }.count == result.count

        let isLoaded = result.filter { value in
            switch value {
            case .fetching: return true
            default: return false
            }
        }.isEmpty

        let source: PreviewState.Source = namespace == Namespaces.ItemCollection.CloudEmojiPacks ? .emoji : .stickers

        let collections: [PreviewState.Collection] = result.compactMap { value in
            switch value {
            case let .result(info, items, installed):
                return .init(info: info._parse(), items: items, installed: installed)
            default:
                return nil
            }
        }

        let preview: PreviewState = isLoaded ? .loaded(source: source, collections: collections) : .loading(source)

        if isEmpty {
            alert(for: context.window, info: strings().stickerSetDontExist)
            modalController?.close()
        } else {
            updateState { current in
                var current = current
                current.preview = PreviewStateEquatable(preview)
                return current
            }
        }
    }))

    let lastTitle: Atomic<String?> = Atomic(value: nil)

    let applyState: (State) -> Void = { [weak modalController, weak controller] state in
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        let headerTitle: String
        if case let .loaded(source, collections) = state.preview.value {
            if collections.count == 1 {
                headerTitle = state.titleOverride ?? collections[0].info.title
            } else {
                switch source {
                case .emoji:
                    headerTitle = strings().stickerPackEmoji
                case .stickers:
                    headerTitle = strings().stickerPackStickers
                }
            }
        } else {
            headerTitle = modalTitle
        }

        let previousTitle = lastTitle.swap(headerTitle)
        if previousTitle != headerTitle, let controller {
            controller.centerModalHeader = ModalHeaderData(title: headerTitle)
            modalController?.modal?.updateLocalizationAndTheme(theme: theme)
        }

        guard case let .loaded(source, collections) = state.preview.value, state.premiumFile == nil else {
            _ = pendingAddAction.swap(nil)
            modalController?.modal?.interactions?.updateDone { button in
                button.isHidden = true
            }
            modalController?.hidesInteractionsBottomInset = true
            return
        }

        let isInstalled: (PreviewState.Collection) -> Bool = { collection in
            if collection.installed { return true }
            switch source {
            case .emoji:
                return state.installed.contains(.emoji(.name(collection.info.shortName)))
            case .stickers:
                return state.installed.contains(.stickers(.name(collection.info.shortName)))
            }
        }
        let notInstalledCount = collections.filter { !isInstalled($0) }.count
        let isOwnInstalled = controllerSource == .install && source == .stickers && collections.count == 1 && isOwnStickerPack(collections[0].info) && isInstalled(collections[0])

        let title: String?
        switch controllerSource {
        case .install:
            let allInstalled = !collections.contains(where: { !isInstalled($0) })
            if isOwnInstalled {
                title = state.isEditing ? strings().modalDone.uppercased() : strings().stickerPackPreviewModalControllerEditStickers
            } else if allInstalled {
                title = nil
            } else {
                switch source {
                case .emoji:
                    title = collections.count == 1
                        ? strings().emojiPackSetsAddOther(collections[0].items.count).uppercased()
                        : strings().emojiPackSetsAddOther(notInstalledCount).uppercased()
                case .stickers:
                    title = collections.count == 1
                        ? strings().stickerPackAdd1Other(collections[0].items.count).uppercased()
                        : strings().stickerPackSetsAdd1Other(notInstalledCount).uppercased()
                }
            }
        case .installGroupEmojiPack:
            title = strings().stickerPackPreviewSetGroup
        case .removeGroupEmojiPack:
            title = strings().stickerPackPreviewRemoveGroup
        }

        _ = pendingAddAction.swap({
            if isOwnInstalled {
                setEditing(!stateValue.with { $0.isEditing })
            } else if collections.count == 1 {
                arguments.addpack(source, collections[0], true)
            } else {
                arguments.addAll(source, collections, true)
            }
        })

        modalController?.modal?.interactions?.updateDone { button in
            if let title {
                button.isHidden = false
                button.set(text: title, for: .Normal)
            } else {
                button.isHidden = true
            }
        }
        modalController?.hidesInteractionsBottomInset = (title == nil)
    }

    actionsDisposable.add(origin.preservingPresentation(statePromise.get() |> deliverOnMainQueue).start(next: { state in
        applyState(state)
    }))

    controller.didAppear = { _ in
        applyState(stateValue.with { $0 })
    }

    return modalController
}
