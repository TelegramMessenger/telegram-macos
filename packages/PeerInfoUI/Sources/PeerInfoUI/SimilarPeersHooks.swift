import Cocoa
import AppAnalytics
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext

public struct SimilarPeersHooks {
    public let openChat: (any AccountContextProtocol, PeerId) -> Void
    public var openChatWithContext: ((any AccountContextProtocol, PeerId, AnalyticsContext) -> Void)?
    public func openChatObserved(_ context: any AccountContextProtocol, _ peerId: PeerId, analyticsContext: AnalyticsContext) {
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        if let openChatWithContext {
            openChatWithContext(context, peerId, origin)
        } else {
            openChat(context, peerId)
        }
    }

    public init(openChat: @escaping (any AccountContextProtocol, PeerId) -> Void) {
        self.openChat = openChat
    }

    private static var _shared: SimilarPeersHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: SimilarPeersHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("SimilarPeersHooks.install must be called before the similar peers screens are used")
        return .placeholder
    }

    public static func install(_ hooks: SimilarPeersHooks) {
        assert(Thread.isMainThread, "SimilarPeersHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = SimilarPeersHooks(
        openChat: { _, _ in }
    )
}
