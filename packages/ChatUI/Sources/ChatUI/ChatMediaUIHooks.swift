import Cocoa
import AppAnalytics
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import ChatModeTypes
import AudioPlayerCore

public protocol ChatMediaParentRowItem: AnyObject {
    var peer: Peer? { get }
    var chatInteraction: ChatInteraction { get }
}

public enum ChatMediaStickerPackPreviewSource : Hashable {
    case stickers(StickerPackReference)
    case emoji(StickerPackReference)
}

public struct ChatMediaUIHooks {
    public let getAudioPlayer: ((any AccountContextProtocol)?) -> APController?
    public let showQuickLookPreview: (any AccountContextProtocol, Media, ChatHistoryEntryId?, InteractionContentViewProtocol?) -> Void
    public let makeStickerPackPreview: (any AccountContextProtocol, PeerId?, [ChatMediaStickerPackPreviewSource]) -> ModalViewController
    public var makeStickerPackPreviewWithContext: ((any AccountContextProtocol, PeerId?, [ChatMediaStickerPackPreviewSource], AnalyticsContext) -> ModalViewController)?

    public func makeStickerPackPreviewObserved(_ context: any AccountContextProtocol, _ peerId: PeerId?, _ sources: [ChatMediaStickerPackPreviewSource], analyticsContext: AnalyticsContext) -> ModalViewController {
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: peerId ?? context.peerId, inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        let controller: ModalViewController
        if let makeStickerPackPreviewWithContext {
            controller = makeStickerPackPreviewWithContext(context, peerId, sources, origin)
        } else {
            controller = makeStickerPackPreview(context, peerId, sources)
        }
        controller.analyticsContext = origin
        return controller
    }

    public init(getAudioPlayer: @escaping ((any AccountContextProtocol)?) -> APController?,
                showQuickLookPreview: @escaping (any AccountContextProtocol, Media, ChatHistoryEntryId?, InteractionContentViewProtocol?) -> Void,
                makeStickerPackPreview: @escaping (any AccountContextProtocol, PeerId?, [ChatMediaStickerPackPreviewSource]) -> ModalViewController) {
        self.getAudioPlayer = getAudioPlayer
        self.showQuickLookPreview = showQuickLookPreview
        self.makeStickerPackPreview = makeStickerPackPreview
    }

    private static var _shared: ChatMediaUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: ChatMediaUIHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("ChatMediaUIHooks.install must be called before chat media views are used")
        return .placeholder
    }

    public static func install(_ hooks: ChatMediaUIHooks) {
        assert(Thread.isMainThread, "ChatMediaUIHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = ChatMediaUIHooks(getAudioPlayer: { _ in
        nil
    }, showQuickLookPreview: { _, _, _, _ in
    }, makeStickerPackPreview: { _, _, _ in
        ModalViewController()
    })
}
