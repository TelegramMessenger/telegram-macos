import Cocoa
import InputView
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import AudioPlayerCore
import ChatHistoryModel
import RichTextEditorUI
import RichTextEditorCore
import TelegramUtils
import TelegramMedia
import TelegramMediaUtils
import TelegramMediaResources
import InAppSettings
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils

public protocol ChatInputControllerView: NSView {
    var inputView: ChatInputView { get }
}

public enum ChatInputInAppLink {
    case external(link: String, Bool)
    case other
}

public enum ChatInputStickerPackPreviewSource : Hashable {
    case stickers(StickerPackReference)
    case emoji(StickerPackReference)
}

@available(macOS 10.15, *)
public struct ChatInputWalletHooks {
    public let walletContext: (any AccountContextProtocol) -> (any ChatWalletContext)?
    public let makeWalletSendController: (any AccountContextProtocol, any ChatWalletContext, Peer, ChatWalletSendHandlers) -> ModalViewController

    public var makeWalletSendControllerWithContext: ((any AccountContextProtocol, any ChatWalletContext, Peer, ChatWalletSendHandlers) -> ModalViewController)?

    public func makeWalletSendControllerObserved(_ context: any AccountContextProtocol, _ walletContext: any ChatWalletContext, _ peer: Peer, _ handlers: ChatWalletSendHandlers) -> ModalViewController {
        let controller: ModalViewController
        if let makeWalletSendControllerWithContext {
            controller = makeWalletSendControllerWithContext(context, walletContext, peer, handlers)
        } else {
            controller = makeWalletSendController(context, walletContext, peer, handlers)
        }
        let onDeinit = controller.onDeinit
        controller.onDeinit = {
            onDeinit?()
        }
        return controller
    }

    public init(walletContext: @escaping (any AccountContextProtocol) -> (any ChatWalletContext)?,
                makeWalletSendController: @escaping (any AccountContextProtocol, any ChatWalletContext, Peer, ChatWalletSendHandlers) -> ModalViewController) {
        self.walletContext = walletContext
        self.makeWalletSendController = makeWalletSendController
    }
}

public struct ChatInputUIHooks {
    public let makeEntertainmentsPopover: (ChatInteraction) -> ViewController
    public let makeSuggestPostPanelModel: (ChatInterfaceState.ChannelSuggestPost, any AccountContextProtocol) -> ChatAccessoryModel
    public let makeUrlPreviewModel: (any AccountContextProtocol, TelegramMediaWebpage, String) -> ChatAccessoryModel
    public let makeEditMessageModel: (ChatEditState, any AccountContextProtocol) -> ChatAccessoryModel
    public let makeForwardPanelModel: ([Message], Bool, any AccountContextProtocol) -> ChatAccessoryModel
    public let makeForwardMessagesModal: (any AccountContextProtocol, [Message]) -> ModalViewController
    public let makeTranslateModal: (any AccountContextProtocol, String?, String, String, @escaping (NSAttributedString) -> Void, @escaping (NSAttributedString) -> Void) -> ModalViewController
    public var makeTranslateModalWithContext: ((any AccountContextProtocol, String?, String, String, @escaping (NSAttributedString) -> Void, @escaping (NSAttributedString) -> Void) -> ModalViewController)?

    public func makeTranslateModalObserved(_ context: any AccountContextProtocol, _ from: String?, _ toLang: String, _ text: String, onUse: @escaping (NSAttributedString) -> Void, onSend: @escaping (NSAttributedString) -> Void) -> ModalViewController {
        func guarded(_ callback: @escaping (NSAttributedString) -> Void) -> (NSAttributedString) -> Void {
            return { translated in
                callback(translated)
            }
        }
        if let makeTranslateModalWithContext {
            return makeTranslateModalWithContext(context, from, toLang, text, guarded(onUse), guarded(onSend))
        } else {
            return makeTranslateModal(context, from, toLang, text, guarded(onUse), guarded(onSend))
        }
    }

    public let makeRichTranslateModal: (any AccountContextProtocol, String?, String, String, [MessageTextEntity], [Block], @escaping ([Block]) -> Void) -> ModalViewController
    public var makeRichTranslateModalWithContext: ((any AccountContextProtocol, String?, String, String, [MessageTextEntity], [Block], @escaping ([Block]) -> Void) -> ModalViewController)?

    public func makeRichTranslateModalObserved(_ context: any AccountContextProtocol, _ from: String?, _ toLang: String, _ text: String, _ entities: [MessageTextEntity], _ blocks: [Block], onUse: @escaping ([Block]) -> Void) -> ModalViewController {
        if let makeRichTranslateModalWithContext {
            return makeRichTranslateModalWithContext(context, from, toLang, text, entities, blocks, onUse)
        } else {
            return makeRichTranslateModal(context, from, toLang, text, entities, blocks, onUse)
        }
    }
    public let wallet: Any?
    public let getAudioPlayer: ((any AccountContextProtocol)?) -> APController?
    public let makeStickerPackPreview: (any AccountContextProtocol, PeerId?, [ChatInputStickerPackPreviewSource]) -> ModalViewController
    public let resolveInAppLink: (Any?) -> ChatInputInAppLink?
    public let highlightRichTextSyntax: (String, String, @escaping () -> TelegramPresentationTheme, @escaping ([RichTextSyntaxToken]) -> Void) -> Void
    public let makeEmojiPicker: (any AccountContextProtocol, @escaping (StickerPackItem, StarGift.UniqueGift?, StickerPackCollectionInfo?, Int32?, NSRect?) -> Void, @escaping (String, CGRect?) -> Void) -> ViewController
    public var makeEmojiPickerWithContext: ((any AccountContextProtocol, @escaping (StickerPackItem, StarGift.UniqueGift?, StickerPackCollectionInfo?, Int32?, NSRect?) -> Void, @escaping (String, CGRect?) -> Void) -> ViewController)?

    public func makeEmojiPickerObserved(_ context: any AccountContextProtocol, sendAnimatedEmoji: @escaping (StickerPackItem, StarGift.UniqueGift?, StickerPackCollectionInfo?, Int32?, NSRect?) -> Void, sendEmoji: @escaping (String, CGRect?) -> Void) -> ViewController {
        let animated: (StickerPackItem, StarGift.UniqueGift?, StickerPackCollectionInfo?, Int32?, NSRect?) -> Void = { sticker, gift, collection, index, rect in
            sendAnimatedEmoji(sticker, gift, collection, index, rect)
        }
        let plain: (String, CGRect?) -> Void = { emoji, rect in
            sendEmoji(emoji, rect)
        }
        if let makeEmojiPickerWithContext {
            return makeEmojiPickerWithContext(context, animated, plain)
        } else {
            let controller = makeEmojiPicker(context, animated, plain)
            return controller
        }
    }
    public let isEntertainmentSidebarAvailable: (NSWindow?) -> Bool
    public let isEntertainmentSidebarVisible: (NSWindow?) -> Bool
    public let updateEntertainmentSidebar: (Bool) -> Void
    public let escapeEntertainmentSidebar: (NSWindow?) -> Bool

    public init(makeEntertainmentsPopover: @escaping (ChatInteraction) -> ViewController,
                makeSuggestPostPanelModel: @escaping (ChatInterfaceState.ChannelSuggestPost, any AccountContextProtocol) -> ChatAccessoryModel,
                makeUrlPreviewModel: @escaping (any AccountContextProtocol, TelegramMediaWebpage, String) -> ChatAccessoryModel,
                makeEditMessageModel: @escaping (ChatEditState, any AccountContextProtocol) -> ChatAccessoryModel,
                makeForwardPanelModel: @escaping ([Message], Bool, any AccountContextProtocol) -> ChatAccessoryModel,
                makeForwardMessagesModal: @escaping (any AccountContextProtocol, [Message]) -> ModalViewController,
                makeTranslateModal: @escaping (any AccountContextProtocol, String?, String, String, @escaping (NSAttributedString) -> Void, @escaping (NSAttributedString) -> Void) -> ModalViewController,
                makeRichTranslateModal: @escaping (any AccountContextProtocol, String?, String, String, [MessageTextEntity], [Block], @escaping ([Block]) -> Void) -> ModalViewController,
                wallet: Any?,
                getAudioPlayer: @escaping ((any AccountContextProtocol)?) -> APController?,
                makeStickerPackPreview: @escaping (any AccountContextProtocol, PeerId?, [ChatInputStickerPackPreviewSource]) -> ModalViewController,
                resolveInAppLink: @escaping (Any?) -> ChatInputInAppLink?,
                highlightRichTextSyntax: @escaping (String, String, @escaping () -> TelegramPresentationTheme, @escaping ([RichTextSyntaxToken]) -> Void) -> Void,
                makeEmojiPicker: @escaping (any AccountContextProtocol, @escaping (StickerPackItem, StarGift.UniqueGift?, StickerPackCollectionInfo?, Int32?, NSRect?) -> Void, @escaping (String, CGRect?) -> Void) -> ViewController,
                isEntertainmentSidebarAvailable: @escaping (NSWindow?) -> Bool,
                updateEntertainmentSidebar: @escaping (Bool) -> Void,
                isEntertainmentSidebarVisible: @escaping (NSWindow?) -> Bool = { _ in false },
                escapeEntertainmentSidebar: @escaping (NSWindow?) -> Bool = { _ in false }) {
        self.makeEntertainmentsPopover = makeEntertainmentsPopover
        self.makeSuggestPostPanelModel = makeSuggestPostPanelModel
        self.makeUrlPreviewModel = makeUrlPreviewModel
        self.makeEditMessageModel = makeEditMessageModel
        self.makeForwardPanelModel = makeForwardPanelModel
        self.makeForwardMessagesModal = makeForwardMessagesModal
        self.makeTranslateModal = makeTranslateModal
        self.makeRichTranslateModal = makeRichTranslateModal
        self.wallet = wallet
        self.getAudioPlayer = getAudioPlayer
        self.makeStickerPackPreview = makeStickerPackPreview
        self.resolveInAppLink = resolveInAppLink
        self.highlightRichTextSyntax = highlightRichTextSyntax
        self.makeEmojiPicker = makeEmojiPicker
        self.isEntertainmentSidebarAvailable = isEntertainmentSidebarAvailable
        self.updateEntertainmentSidebar = updateEntertainmentSidebar
        self.isEntertainmentSidebarVisible = isEntertainmentSidebarVisible
        self.escapeEntertainmentSidebar = escapeEntertainmentSidebar
    }

    @available(macOS 10.15, *)
    public var walletHooks: ChatInputWalletHooks {
        return wallet as! ChatInputWalletHooks
    }

    private static var _shared: ChatInputUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: ChatInputUIHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("ChatInputUIHooks.install must be called before the chat input is used")
        return .placeholder
    }

    public static func install(_ hooks: ChatInputUIHooks) {
        assert(Thread.isMainThread, "ChatInputUIHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = ChatInputUIHooks(makeEntertainmentsPopover: { _ in
        ViewController()
    }, makeSuggestPostPanelModel: { _, context in
        ChatAccessoryModel(context: context)
    }, makeUrlPreviewModel: { context, _, _ in
        ChatAccessoryModel(context: context)
    }, makeEditMessageModel: { _, context in
        ChatAccessoryModel(context: context)
    }, makeForwardPanelModel: { _, _, context in
        ChatAccessoryModel(context: context)
    }, makeForwardMessagesModal: { _, _ in
        ModalViewController()
    }, makeTranslateModal: { _, _, _, _, _, _ in
        ModalViewController()
    }, makeRichTranslateModal: { _, _, _, _, _, _, _ in
        ModalViewController()
    }, wallet: nil, getAudioPlayer: { _ in
        nil
    }, makeStickerPackPreview: { _, _, _ in
        ModalViewController()
    }, resolveInAppLink: { _ in
        nil
    }, highlightRichTextSyntax: { _, _, _, completion in
        completion([])
    }, makeEmojiPicker: { _, _, _ in
        ViewController()
    }, isEntertainmentSidebarAvailable: { _ in
        false
    }, updateEntertainmentSidebar: { _ in
    })
}
