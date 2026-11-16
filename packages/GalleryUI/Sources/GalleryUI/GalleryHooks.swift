import Cocoa
import AppAnalytics
import TGUIKit
import Postbox
import TelegramCore
import TelegramContext
import TelegramUtils
import LocalAnimations
import ChatModeTypes

public protocol GalleryContentInteractions: AnyObject {
    var timeCodeInitializer: Double? { get }
    var showMessage: (Message) -> Void { get }
    func remove_timeCodeInitializer()
}

public protocol GalleryStickerView: NSView {
    func updateSticker(animation: LocalAnimatedSticker, size: NSSize, context: any AccountContextProtocol)
}

public struct GalleryHooks {
    public let makeStickerView: () -> GalleryStickerView
    public let openAdUrl: (String, any AccountContextProtocol, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> Void
    public let executeLink: (Any, @escaping (Bool) -> Void) -> Void
    public let openInfo: (any AccountContextProtocol, PeerId, Bool, MessageId?, ChatInitialAction?) -> Void
    public let showShare: (any AccountContextProtocol, Message, [Message]?, Window) -> Void
    public var showShareWithContext: ((any AccountContextProtocol, Message, [Message]?, Window, AnalyticsContext) -> Void)?

    public func showShareObserved(_ context: any AccountContextProtocol, _ message: Message, _ messages: [Message]?, _ window: Window, analyticsContext: AnalyticsContext) {
        let origin = GalleryAnalyticsContext(accountContext: context, inherited: analyticsContext)
        origin.restrict(messages: [message] + (messages ?? []))
        let presentation = origin.context.beginPresentation()
        defer { presentation.end() }
        if let showShareWithContext {
            showShareWithContext(context, message, messages, window, origin.context)
        } else {
            showShare(context, message, messages, window)
        }
    }

    public let makeCaption: (any AccountContextProtocol, Message, [MessageTextEntity], String, @escaping () -> Void) -> NSAttributedString
    public let makeAdMessageText: (any AccountContextProtocol, Message) -> NSAttributedString
    public let showAdAbout: (any AccountContextProtocol, Window) -> Void
    public let showTranslate: (any AccountContextProtocol, String?, String, String, Window) -> Void
    public let canSendHere: (any AccountContextProtocol, Message) -> Bool
    public let sendHere: (any AccountContextProtocol, String) -> Void
    public let openSharedMedia: (any AccountContextProtocol, PeerId) -> Void
    public let openDownloadSearch: (any AccountContextProtocol) -> Void
    public let pauseGlobalAudio: (any AccountContextProtocol) -> Bool
    public let resumeGlobalAudio: (any AccountContextProtocol) -> Void
    public let makeRateMenuItem: (CGFloat, CGFloat, CGFloat, CGFloat, @escaping (CGFloat, Bool) -> Void) -> ContextMenuItem
    public let openRecognizedLink: (String, any AccountContextProtocol, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void, @escaping (Bool) -> Void) -> Void
    public let stickerSender: (any AccountContextProtocol, Message) -> ((String) -> Void)?

    public init(makeStickerView: @escaping () -> GalleryStickerView,
                openAdUrl: @escaping (String, any AccountContextProtocol, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> Void,
                executeLink: @escaping (Any, @escaping (Bool) -> Void) -> Void,
                openInfo: @escaping (any AccountContextProtocol, PeerId, Bool, MessageId?, ChatInitialAction?) -> Void,
                showShare: @escaping (any AccountContextProtocol, Message, [Message]?, Window) -> Void,
                makeCaption: @escaping (any AccountContextProtocol, Message, [MessageTextEntity], String, @escaping () -> Void) -> NSAttributedString,
                makeAdMessageText: @escaping (any AccountContextProtocol, Message) -> NSAttributedString,
                showAdAbout: @escaping (any AccountContextProtocol, Window) -> Void,
                showTranslate: @escaping (any AccountContextProtocol, String?, String, String, Window) -> Void,
                canSendHere: @escaping (any AccountContextProtocol, Message) -> Bool,
                sendHere: @escaping (any AccountContextProtocol, String) -> Void,
                openSharedMedia: @escaping (any AccountContextProtocol, PeerId) -> Void,
                openDownloadSearch: @escaping (any AccountContextProtocol) -> Void,
                pauseGlobalAudio: @escaping (any AccountContextProtocol) -> Bool,
                resumeGlobalAudio: @escaping (any AccountContextProtocol) -> Void,
                makeRateMenuItem: @escaping (CGFloat, CGFloat, CGFloat, CGFloat, @escaping (CGFloat, Bool) -> Void) -> ContextMenuItem,
                openRecognizedLink: @escaping (String, any AccountContextProtocol, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void, @escaping (Bool) -> Void) -> Void,
                stickerSender: @escaping (any AccountContextProtocol, Message) -> ((String) -> Void)?) {
        self.makeStickerView = makeStickerView
        self.openAdUrl = openAdUrl
        self.executeLink = executeLink
        self.openInfo = openInfo
        self.showShare = showShare
        self.makeCaption = makeCaption
        self.makeAdMessageText = makeAdMessageText
        self.showAdAbout = showAdAbout
        self.showTranslate = showTranslate
        self.canSendHere = canSendHere
        self.sendHere = sendHere
        self.openSharedMedia = openSharedMedia
        self.openDownloadSearch = openDownloadSearch
        self.pauseGlobalAudio = pauseGlobalAudio
        self.resumeGlobalAudio = resumeGlobalAudio
        self.makeRateMenuItem = makeRateMenuItem
        self.openRecognizedLink = openRecognizedLink
        self.stickerSender = stickerSender
    }

    private static var _shared: GalleryHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: GalleryHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("GalleryHooks.install must be called before the gallery is used")
        return .placeholder
    }

    public static func install(_ hooks: GalleryHooks) {
        assert(Thread.isMainThread, "GalleryHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = GalleryHooks(
        makeStickerView: { PlaceholderGalleryStickerView(frame: .zero) },
        openAdUrl: { _, _, _ in },
        executeLink: { _, _ in },
        openInfo: { _, _, _, _, _ in },
        showShare: { _, _, _, _ in },
        makeCaption: { _, _, _, text, _ in NSAttributedString(string: text) },
        makeAdMessageText: { _, message in NSAttributedString(string: message.text) },
        showAdAbout: { _, _ in },
        showTranslate: { _, _, _, _, _ in },
        canSendHere: { _, _ in false },
        sendHere: { _, _ in },
        openSharedMedia: { _, _ in },
        openDownloadSearch: { _ in },
        pauseGlobalAudio: { _ in false },
        resumeGlobalAudio: { _ in },
        makeRateMenuItem: { _, _, _, _, _ in ContextMenuItem("") },
        openRecognizedLink: { _, _, _, _ in },
        stickerSender: { _, _ in nil }
    )
}

private final class PlaceholderGalleryStickerView: NSView, GalleryStickerView {
    func updateSticker(animation: LocalAnimatedSticker, size: NSSize, context: any AccountContextProtocol) {
    }
}
