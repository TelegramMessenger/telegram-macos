import Cocoa
import InputView
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import TelegramMediaUtils
import InlineMediaGrid
import ChatModeTypes

public enum EntertainmentStickerPackPreviewSource: Hashable {
    case stickers(StickerPackReference)
    case emoji(StickerPackReference)
}

public enum EntertainmentPreviewKind {
    case gif
    case animatedSticker
    case sticker
}

public protocol EntertainmentStickerContentView: View {
    func updateSticker(file: TelegramMediaFile, size: NSSize, context: any AccountContextProtocol, table: TableView?, animated: Bool)
    func stickerShake()
    func stickerUpdateMouse()
    func stickerWillRemove()
}

public final class EntertainmentMediaArguments {
    public let sendResult: (ChatContextResultCollection?, ChatContextResult, NSView) -> Void
    public let menuItems: (TelegramMediaFile, NSView) -> Signal<[ContextMenuItem], NoError>
    public let openMessage: (Message) -> Void
    public let messageMenuItems: (Message, NSView) -> Signal<[ContextMenuItem], NoError>
    public var drag: ((ChatContextResult, NSPoint, Bool) -> Bool)?

    public init(sendResult: @escaping (ChatContextResultCollection?, ChatContextResult, NSView) -> Void = { _, _, _ in }, menuItems: @escaping (TelegramMediaFile, NSView) -> Signal<[ContextMenuItem], NoError> = { _, _ in return .single([]) }, openMessage: @escaping (Message) -> Void = { _ in }, messageMenuItems: @escaping (Message, NSView) -> Signal<[ContextMenuItem], NoError> = { _, _ in return .single([]) }) {
        self.sendResult = sendResult
        self.menuItems = menuItems
        self.openMessage = openMessage
        self.messageMenuItems = messageMenuItems
    }
}

public struct EntertainmentStickerImage {
    public let url: URL
    public let dimensions: PixelDimensions

    public init(url: URL, dimensions: PixelDimensions) {
        self.url = url
        self.dimensions = dimensions
    }
}

public struct EntertainmentUIHooks {
    public let makePreviewSender: (TelegramMediaFile, any ChatInteractionProtocol) -> ModalViewController
    public let shareLink: (any AccountContextProtocol, String) -> Void
    public var shareLinkWithContext: ((any AccountContextProtocol, String) -> Void)?
    public func shareLinkObserved(_ context: any AccountContextProtocol, _ link: String) {
        if let shareLinkWithContext {
            shareLinkWithContext(context, link)
        } else {
            shareLink(context, link)
        }
    }
    public let makeChatInteraction: (any AccountContextProtocol, PeerId) -> any ChatInteractionProtocol
    public let currentChatInteraction: (any AccountContextProtocol) -> (any ChatInteractionProtocol)?
    public let makeTopicIconFile: (String, Int32, Bool) -> TelegramMediaFile
    public let inputSource: (any AccountContextProtocol) -> InputSources
    public let makeStickerPackPreview: (any AccountContextProtocol, PeerId?, [EntertainmentStickerPackPreviewSource]) -> ModalViewController
    public let previewViewType: (EntertainmentPreviewKind) -> ModalPreviewControllerView.Type
    public let makeStickerContentView: (Bool, NSRect) -> any EntertainmentStickerContentView
    public let makeContextMediaRowItem: (NSSize, InputMediaContextRow, Int64, any AccountContextProtocol, EntertainmentMediaArguments, ChatContextResultCollection?, AnyHashable) -> TableRowItem
    public let launchSendFlight: (any ChatInteractionProtocol, NSView, NSRect, CALayer?) -> Void
    public let makeStickerImage: (any AccountContextProtocol, Window, ((EntertainmentStickerImage, @escaping () -> Void) -> [ContextMenuItem])?, @escaping (EntertainmentStickerImage) -> Void) -> Void
    public var makeStickerImageWithContext: ((any AccountContextProtocol, Window, ((EntertainmentStickerImage, @escaping () -> Void) -> [ContextMenuItem])?, @escaping (EntertainmentStickerImage) -> Void) -> Void)?


    public func makeStickerImageObserved(_ context: any AccountContextProtocol, _ window: Window, doneMenu: ((EntertainmentStickerImage, @escaping () -> Void) -> [ContextMenuItem])?, completion: @escaping (EntertainmentStickerImage) -> Void) {
        if let makeStickerImageWithContext {
            makeStickerImageWithContext(context, window, doneMenu, completion)
        } else {
            makeStickerImage(context, window, doneMenu, completion)
        }
    }
    public var appendPackEmojiWithContext: ((any ChatInteractionProtocol, NSAttributedString) -> Void)?
    public func appendPackEmojiObserved(_ interaction: any ChatInteractionProtocol, text: NSAttributedString) {
        if let appendPackEmojiWithContext {
            appendPackEmojiWithContext(interaction, text)
        } else {
            _ = interaction.appendText(text, selectedRange: nil)
        }
    }

    public var sendPackStickerWithContext: ((any ChatInteractionProtocol, TelegramMediaFile, Bool, Bool) -> Void)?
    public func sendPackStickerObserved(_ interaction: any ChatInteractionProtocol, file: TelegramMediaFile, silent: Bool, scheduled: Bool) {
        if let sendPackStickerWithContext {
            sendPackStickerWithContext(interaction, file, silent, scheduled)
        } else {
            interaction.sendFile(file, silent: silent, query: nil, scheduled: scheduled, collectionId: nil)
        }
    }



    public let openStickersBot: (any AccountContextProtocol) -> Void
    public var openStickersBotWithContext: ((any AccountContextProtocol) -> Void)?
    public func openStickersBotObserved(_ context: any AccountContextProtocol) {
        if let openStickersBotWithContext {
            openStickersBotWithContext(context)
        } else {
            openStickersBot(context)
        }
    }

    public init(makePreviewSender: @escaping (TelegramMediaFile, any ChatInteractionProtocol) -> ModalViewController,
                shareLink: @escaping (any AccountContextProtocol, String) -> Void,
                makeChatInteraction: @escaping (any AccountContextProtocol, PeerId) -> any ChatInteractionProtocol,
                currentChatInteraction: @escaping (any AccountContextProtocol) -> (any ChatInteractionProtocol)?,
                makeTopicIconFile: @escaping (String, Int32, Bool) -> TelegramMediaFile,
                inputSource: @escaping (any AccountContextProtocol) -> InputSources,
                makeStickerPackPreview: @escaping (any AccountContextProtocol, PeerId?, [EntertainmentStickerPackPreviewSource]) -> ModalViewController,
                previewViewType: @escaping (EntertainmentPreviewKind) -> ModalPreviewControllerView.Type,
                makeStickerContentView: @escaping (Bool, NSRect) -> any EntertainmentStickerContentView,
                makeContextMediaRowItem: @escaping (NSSize, InputMediaContextRow, Int64, any AccountContextProtocol, EntertainmentMediaArguments, ChatContextResultCollection?, AnyHashable) -> TableRowItem,
                launchSendFlight: @escaping (any ChatInteractionProtocol, NSView, NSRect, CALayer?) -> Void = { _, _, _, _ in },
                makeStickerImage: @escaping (any AccountContextProtocol, Window, ((EntertainmentStickerImage, @escaping () -> Void) -> [ContextMenuItem])?, @escaping (EntertainmentStickerImage) -> Void) -> Void = { _, _, _, _ in },
                openStickersBot: @escaping (any AccountContextProtocol) -> Void = { _ in }) {
        self.makePreviewSender = makePreviewSender
        self.shareLink = shareLink
        self.makeChatInteraction = makeChatInteraction
        self.currentChatInteraction = currentChatInteraction
        self.makeTopicIconFile = makeTopicIconFile
        self.inputSource = inputSource
        self.makeStickerPackPreview = makeStickerPackPreview
        self.previewViewType = previewViewType
        self.makeStickerContentView = makeStickerContentView
        self.makeContextMediaRowItem = makeContextMediaRowItem
        self.launchSendFlight = launchSendFlight
        self.makeStickerImage = makeStickerImage
        self.openStickersBot = openStickersBot
    }

    private static var _shared: EntertainmentUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: EntertainmentUIHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("EntertainmentUIHooks.install must be called before the entertainment panel is used")
        fatalError("EntertainmentUIHooks.install must be called before the entertainment panel is used")
    }

    public static func install(_ hooks: EntertainmentUIHooks) {
        assert(Thread.isMainThread, "EntertainmentUIHooks.install must be called on the main thread")
        _shared = hooks
    }
}
