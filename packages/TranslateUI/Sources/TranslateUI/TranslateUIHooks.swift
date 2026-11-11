import Cocoa
import TGUIKit
import TelegramCore
import TelegramContext
import AppAnalytics

public struct TranslateUIHooks {
    public let showAboutCocoonModal: (any AccountContextProtocol) -> Void
    public var showAboutCocoonModalWithContext: ((any AccountContextProtocol, AnalyticsContext) -> Void)?

    public func showAboutCocoonModalObserved(_ context: any AccountContextProtocol, analyticsContext: AnalyticsContext) {
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        if let showAboutCocoonModalWithContext {
            showAboutCocoonModalWithContext(context, origin)
        } else {
            showAboutCocoonModal(context)
        }
    }

    public let shareLink: (any AccountContextProtocol, String) -> Void
    public var shareLinkWithContext: ((any AccountContextProtocol, String, AnalyticsContext) -> Void)?

    public func shareLinkObserved(_ context: any AccountContextProtocol, _ link: String, analyticsContext: AnalyticsContext) {
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        if let shareLinkWithContext {
            shareLinkWithContext(context, link, origin)
        } else {
            shareLink(context, link)
        }
    }

    public let followResolvedName: (String, String, any AccountContextProtocol) -> Void
    public var followResolvedNameWithContext: ((String, String, any AccountContextProtocol, AnalyticsContext) -> Void)?

    public func followResolvedNameObserved(_ handle: String, _ username: String, _ context: any AccountContextProtocol, analyticsContext: AnalyticsContext) {
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        if let followResolvedNameWithContext {
            followResolvedNameWithContext(handle, username, context, origin)
        } else {
            followResolvedName(handle, username, context)
        }
    }
    public let showStyleEmojiPicker: (any AccountContextProtocol, Control, @escaping (TelegramMediaFile) -> Void) -> Void
    public var showStyleEmojiPickerWithContext: ((any AccountContextProtocol, Control, AnalyticsContext, @escaping (TelegramMediaFile) -> Void) -> Void)?

    public func showStyleEmojiPickerObserved(_ context: any AccountContextProtocol, _ control: Control, analyticsContext: AnalyticsContext, selected: @escaping (TelegramMediaFile) -> Void) {
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        let completion: (TelegramMediaFile) -> Void = { file in
            let current = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: origin)
            let presentation = current.beginPresentation()
            defer { presentation.end() }
            selected(file)
        }
        if let showStyleEmojiPickerWithContext {
            showStyleEmojiPickerWithContext(context, control, origin, completion)
        } else {
            showStyleEmojiPicker(context, control, completion)
        }
    }

    public init(showAboutCocoonModal: @escaping (any AccountContextProtocol) -> Void,
                shareLink: @escaping (any AccountContextProtocol, String) -> Void,
                followResolvedName: @escaping (String, String, any AccountContextProtocol) -> Void,
                showStyleEmojiPicker: @escaping (any AccountContextProtocol, Control, @escaping (TelegramMediaFile) -> Void) -> Void) {
        self.showAboutCocoonModal = showAboutCocoonModal
        self.shareLink = shareLink
        self.followResolvedName = followResolvedName
        self.showStyleEmojiPicker = showStyleEmojiPicker
    }

    private static var _shared: TranslateUIHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: TranslateUIHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("TranslateUIHooks.install must be called before translate screens are used")
        return .placeholder
    }

    public static func install(_ hooks: TranslateUIHooks) {
        assert(Thread.isMainThread, "TranslateUIHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = TranslateUIHooks(showAboutCocoonModal: { _ in
    }, shareLink: { _, _ in
    }, followResolvedName: { _, _, _ in
    }, showStyleEmojiPicker: { _, _, _ in
    })
}
