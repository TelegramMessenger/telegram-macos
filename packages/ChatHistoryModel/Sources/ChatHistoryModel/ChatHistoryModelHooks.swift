import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import InAppSettings
import TelegramContext
import TelegramUtils
import ChatModeTypes
import InputView

public struct ChatInputContextQueryTypes: OptionSet {
    public var rawValue: Int32

    public init() {
        self.rawValue = 0
    }

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    public static let hashtag = ChatInputContextQueryTypes(rawValue: (1 << 0))
    public static let mention = ChatInputContextQueryTypes(rawValue: (1 << 1))
    public static let command = ChatInputContextQueryTypes(rawValue: (1 << 2))
    public static let contextRequest = ChatInputContextQueryTypes(rawValue: (1 << 3))
    public static let stickers = ChatInputContextQueryTypes(rawValue: (1 << 4))
    public static let emoji = ChatInputContextQueryTypes(rawValue: (1 << 5))
    public static let emojiFast = ChatInputContextQueryTypes(rawValue: (1 << 6))
    public static let swapEmoji = ChatInputContextQueryTypes(rawValue: (1 << 7))
}

public struct ChatHistoryModelHooks {
    public let applyMessageEntities: ([MessageAttribute], String, Message?, any AccountContextProtocol, CGFloat, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void, NSColor, NSColor, NSColor, NSColor, Bool, Bool) -> NSAttributedString
    public let showAboutCocoonModal: (any AccountContextProtocol) -> Void
    public let getChatInterfaceTempState: ((any AccountContextProtocol)?, PeerId?, Int64?) -> ChatInterfaceTempState?
    public let isLite: (LiteModeKey) -> Bool
    public let textInputStateContextQueryRange: (ChatTextInputState, Bool) -> (Range<String.Index>, ChatInputContextQueryTypes, Range<String.Index>?)?
    public let makeEmojiPicker: (any AccountContextProtocol, @escaping (StickerPackItem, StarGift.UniqueGift?, StickerPackCollectionInfo?, Int32?, NSRect?) -> Void, @escaping (String, CGRect?) -> Void) -> ViewController
    public let peerNameColor: (Int) -> NSColor
    public let peerIsForum: (Peer) -> Bool
    public let verifyAlert: (Window, String, String, @escaping () -> Void) -> Void

    public init(applyMessageEntities: @escaping ([MessageAttribute], String, Message?, any AccountContextProtocol, CGFloat, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void, NSColor, NSColor, NSColor, NSColor, Bool, Bool) -> NSAttributedString,
                showAboutCocoonModal: @escaping (any AccountContextProtocol) -> Void,
                getChatInterfaceTempState: @escaping ((any AccountContextProtocol)?, PeerId?, Int64?) -> ChatInterfaceTempState?,
                isLite: @escaping (LiteModeKey) -> Bool,
                textInputStateContextQueryRange: @escaping (ChatTextInputState, Bool) -> (Range<String.Index>, ChatInputContextQueryTypes, Range<String.Index>?)?,
                makeEmojiPicker: @escaping (any AccountContextProtocol, @escaping (StickerPackItem, StarGift.UniqueGift?, StickerPackCollectionInfo?, Int32?, NSRect?) -> Void, @escaping (String, CGRect?) -> Void) -> ViewController,
                peerNameColor: @escaping (Int) -> NSColor,
                peerIsForum: @escaping (Peer) -> Bool,
                verifyAlert: @escaping (Window, String, String, @escaping () -> Void) -> Void) {
        self.applyMessageEntities = applyMessageEntities
        self.showAboutCocoonModal = showAboutCocoonModal
        self.getChatInterfaceTempState = getChatInterfaceTempState
        self.isLite = isLite
        self.textInputStateContextQueryRange = textInputStateContextQueryRange
        self.makeEmojiPicker = makeEmojiPicker
        self.peerNameColor = peerNameColor
        self.peerIsForum = peerIsForum
        self.verifyAlert = verifyAlert
    }

    private static var _shared: ChatHistoryModelHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: ChatHistoryModelHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("ChatHistoryModelHooks.install must be called before the chat interface model is used")
        return .placeholder
    }

    public static func install(_ hooks: ChatHistoryModelHooks) {
        assert(Thread.isMainThread, "ChatHistoryModelHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = ChatHistoryModelHooks(applyMessageEntities: { _, text, _, _, _, _, _, _, _, _, _, _ in
        NSAttributedString(string: text)
    }, showAboutCocoonModal: { _ in
    }, getChatInterfaceTempState: { _, _, _ in
        nil
    }, isLite: { _ in
        false
    }, textInputStateContextQueryRange: { _, _ in
        nil
    }, makeEmojiPicker: { _, _, _ in
        ViewController()
    }, peerNameColor: { _ in
        NSColor.black
    }, peerIsForum: { _ in
        false
    }, verifyAlert: { _, _, _, _ in
    })
}
