import Cocoa
import AppAnalytics
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext

public struct GroupsInCommonHooks {
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

    private static var _shared: GroupsInCommonHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: GroupsInCommonHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("GroupsInCommonHooks.install must be called before the groups in common screen is used")
        return .placeholder
    }

    public static func install(_ hooks: GroupsInCommonHooks) {
        assert(Thread.isMainThread, "GroupsInCommonHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = GroupsInCommonHooks(
        openChat: { _, _ in }
    )
}
