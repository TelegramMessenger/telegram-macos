import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import ChatModeTypes
import AudioPlayerCore

public protocol StorageUsageChatInteraction: AnyObject {

}

public protocol StorageUsageGifsView: NSView {
    var tableView: TableView { get }
}

public protocol StorageUsagePeerMediaController: ViewController {

}

public protocol StorageUsageEmptyRowItem: TableRowItem {

}

public struct DataUsageHooks {
    public let makeStorageUsageController: (any AccountContextProtocol) -> ViewController
    public let shareLink: (any AccountContextProtocol, String) -> Void
    public let makeAddExceptionModal: (any AccountContextProtocol, CacheStorageSettings.PeerStorageCategory, [StorageCacheException], @escaping ([PeerId]) -> Signal<Never, NoError>) -> ModalViewController
    public let showQuickLookPreview: (any AccountContextProtocol, TelegramMediaFile, ChatHistoryEntryId, InteractionContentViewProtocol?) -> Void
    public let getAudioPlayer: (any AccountContextProtocol) -> APController?
    public let showInlineAudioPlayer: (APController, any AccountContextProtocol, TableView?) -> Void
    public let openForum: (PeerId, Bool, any AccountContextProtocol, Int64) -> Void
    public let makeChatAdditionController: (any AccountContextProtocol, ChatLocation, MessageId) -> ViewController
    public let showChatGallery: (any AccountContextProtocol, Message, InteractionContentViewProtocol?) -> Void
    public let clearWidgetStorage: (any AccountContextProtocol, PeerId?) -> Void

    public init(makeStorageUsageController: @escaping (any AccountContextProtocol) -> ViewController,
                shareLink: @escaping (any AccountContextProtocol, String) -> Void,
                makeAddExceptionModal: @escaping (any AccountContextProtocol, CacheStorageSettings.PeerStorageCategory, [StorageCacheException], @escaping ([PeerId]) -> Signal<Never, NoError>) -> ModalViewController,
                showQuickLookPreview: @escaping (any AccountContextProtocol, TelegramMediaFile, ChatHistoryEntryId, InteractionContentViewProtocol?) -> Void,
                getAudioPlayer: @escaping (any AccountContextProtocol) -> APController?,
                showInlineAudioPlayer: @escaping (APController, any AccountContextProtocol, TableView?) -> Void,
                openForum: @escaping (PeerId, Bool, any AccountContextProtocol, Int64) -> Void,
                makeChatAdditionController: @escaping (any AccountContextProtocol, ChatLocation, MessageId) -> ViewController,
                showChatGallery: @escaping (any AccountContextProtocol, Message, InteractionContentViewProtocol?) -> Void,
                clearWidgetStorage: @escaping (any AccountContextProtocol, PeerId?) -> Void) {
        self.makeStorageUsageController = makeStorageUsageController
        self.shareLink = shareLink
        self.makeAddExceptionModal = makeAddExceptionModal
        self.showQuickLookPreview = showQuickLookPreview
        self.getAudioPlayer = getAudioPlayer
        self.showInlineAudioPlayer = showInlineAudioPlayer
        self.openForum = openForum
        self.makeChatAdditionController = makeChatAdditionController
        self.showChatGallery = showChatGallery
        self.clearWidgetStorage = clearWidgetStorage
    }

    private static var _shared: DataUsageHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: DataUsageHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("DataUsageHooks.install must be called before the data and storage screens are used")
        return .placeholder
    }

    public static func install(_ hooks: DataUsageHooks) {
        assert(Thread.isMainThread, "DataUsageHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = DataUsageHooks(makeStorageUsageController: { _ in
        ViewController()
    }, shareLink: { _, _ in
    }, makeAddExceptionModal: { _, _, _, _ in
        ModalViewController()
    }, showQuickLookPreview: { _, _, _, _ in
    }, getAudioPlayer: { _ in
        nil
    }, showInlineAudioPlayer: { _, _, _ in
    }, openForum: { _, _, _, _ in
    }, makeChatAdditionController: { _, _, _ in
        ViewController()
    }, showChatGallery: { _, _, _ in
    }, clearWidgetStorage: { _, _ in
    })
}
