import Cocoa
import TGUIKit
import TelegramMedia
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import InAppSettings
import ChatModeTypes
import AppAnalytics

public protocol PremiumStickerView: AnyObject {
    func updatePremiumSticker(file: TelegramMediaFile, size: NSSize, context: any AccountContextProtocol, tint: NSColor?, animated: Bool)
    func updatePremiumStickerLayout(size: NSSize, transition: ContainedViewLayoutTransition)
}

public struct PremiumHooks {
    public let openChat: (any AccountContextProtocol, PeerId, ChatInitialAction?) -> Void
    public let makeStickerView: (NSRect) -> NSView
    public let applyMessageEntities: ([MessageTextEntity], String, any AccountContextProtocol, CGFloat, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void, NSColor?, Bool, Bool) -> NSAttributedString
    public let showStickerPackPreview: (any AccountContextProtocol, String) -> Void
    public let openBusinessFeature: (any AccountContextProtocol, PremiumValue) -> Void
    public let preloadVideo: (any AccountContextProtocol, TelegramMediaFile) -> Signal<Never, NoError>
    public let openLink: (any AccountContextProtocol, String, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> Void
    public var openLinkWithContext: ((any AccountContextProtocol, String, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void, AnalyticsContext) -> Void)?

    public func openLinkObserved(_ context: any AccountContextProtocol, _ url: String, _ openInfo: @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void, analyticsContext: AnalyticsContext) {
        let presentation = analyticsContext.beginPresentation()
        defer { presentation.end() }
        let callback: (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void = { peerId, isChat, messageId, action in
            let destination = analyticsContext.restricting(peerId: peerId)
            let delivery = destination.beginPresentation()
            defer { delivery.end() }
            openInfo(peerId, isChat, messageId, action)
        }
        if let openLinkWithContext {
            openLinkWithContext(context, url, callback, analyticsContext)
        } else {
            openLink(context, url, callback)
        }
    }

    public var showStickerPackPreviewWithContext: ((any AccountContextProtocol, String, AnalyticsContext) -> Void)?
    public var openBusinessFeatureWithContext: ((any AccountContextProtocol, PremiumValue, AnalyticsContext) -> Void)?
    public var openChatWithContext: ((any AccountContextProtocol, PeerId, ChatInitialAction?, AnalyticsContext) -> Void)?

    public func openChatObserved(_ context: any AccountContextProtocol, _ peerId: PeerId, _ action: ChatInitialAction?, analyticsContext inheritedContext: AnalyticsContext) {
        let analyticsContext = inheritedContext.restricting(peerId: peerId)
        let presentation = analyticsContext.beginPresentation()
        defer { presentation.end() }
        if let openChatWithContext {
            openChatWithContext(context, peerId, action, analyticsContext)
        } else {
            openChat(context, peerId, action)
        }
    }

    public func showStickerPackPreviewObserved(_ context: any AccountContextProtocol, _ shortName: String, analyticsContext: AnalyticsContext) {
        let presentation = analyticsContext.beginPresentation()
        defer { presentation.end() }
        if let showStickerPackPreviewWithContext {
            showStickerPackPreviewWithContext(context, shortName, analyticsContext)
        } else {
            showStickerPackPreview(context, shortName)
        }
    }

    public func openBusinessFeatureObserved(_ context: any AccountContextProtocol, _ value: PremiumValue, analyticsContext: AnalyticsContext) {
        let presentation = analyticsContext.beginPresentation()
        defer { presentation.end() }
        if let openBusinessFeatureWithContext {
            openBusinessFeatureWithContext(context, value, analyticsContext)
        } else {
            openBusinessFeature(context, value)
        }
    }

    public init(openChat: @escaping (any AccountContextProtocol, PeerId, ChatInitialAction?) -> Void,
                makeStickerView: @escaping (NSRect) -> NSView,
                applyMessageEntities: @escaping ([MessageTextEntity], String, any AccountContextProtocol, CGFloat, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void, NSColor?, Bool, Bool) -> NSAttributedString,
                showStickerPackPreview: @escaping (any AccountContextProtocol, String) -> Void,
                openBusinessFeature: @escaping (any AccountContextProtocol, PremiumValue) -> Void,
                preloadVideo: @escaping (any AccountContextProtocol, TelegramMediaFile) -> Signal<Never, NoError>,
                openLink: @escaping (any AccountContextProtocol, String, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> Void) {
        self.openChat = openChat
        self.makeStickerView = makeStickerView
        self.applyMessageEntities = applyMessageEntities
        self.showStickerPackPreview = showStickerPackPreview
        self.openBusinessFeature = openBusinessFeature
        self.preloadVideo = preloadVideo
        self.openLink = openLink
    }

    private static var value: PremiumHooks?

    public static var shared: PremiumHooks {
        guard let value = value else {
            preconditionFailure("PremiumHooks not installed")
        }
        return value
    }

    public static func install(_ hooks: PremiumHooks) {
        self.value = hooks
    }
}

public func installPremiumHooks(_ hooks: PremiumHooks) {
    PremiumHooks.install(hooks)
}
