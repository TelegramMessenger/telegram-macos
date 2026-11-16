import Cocoa
import AppAnalytics
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import LocalAnimations
import GeneralRows

public protocol StatisticsStickerView: View {
    func updateSticker(animation: LocalAnimatedSticker, size: NSSize, context: any AccountContextProtocol, table: TableView?, animated: Bool)
}

public struct StatisticsHooks {
    public let makeStickerView: () -> StatisticsStickerView
    public let makeMonetizationController: (any AccountContextProtocol, PeerId) -> ViewController
    public let makeStarMonetizationController: (any AccountContextProtocol, PeerId) -> ViewController
    public let makeBoostStatsController: (any AccountContextProtocol, PeerId) -> ViewController
    public let openPeerInfo: (any AccountContextProtocol, PeerId) -> Void
    public var openPeerInfoWithContext: ((any AccountContextProtocol, PeerId, AnalyticsContext) -> Void)?
    public func openPeerInfoObserved(_ context: any AccountContextProtocol, _ peerId: PeerId, analyticsContext: AnalyticsContext) {
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: analyticsContext)
        let lifetime = origin.beginPresentation()
        defer { lifetime.end() }
        if let openPeerInfoWithContext {
            openPeerInfoWithContext(context, peerId, origin)
        } else {
            openPeerInfo(context, peerId)
        }
    }
    public let makeSharedRowItem: (NSSize, AnyHashable, any AccountContextProtocol, StoryStatsPublicForwardsContext.State.Forward, GeneralViewType, @escaping () -> Void) -> TableRowItem
    public let openMessage: (any AccountContextProtocol, MessageId) -> Void
    public var openMessageWithContext: ((any AccountContextProtocol, MessageId, AnalyticsContext) -> Void)?
    public func openMessageObserved(_ context: any AccountContextProtocol, _ message: EngineMessage, analyticsContext: AnalyticsContext) {
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: message.id.peerId, inherited: message.containsSecretMedia ? Analytics.shared.unresolvedContext() : analyticsContext)
        let lifetime = origin.beginPresentation()
        defer { lifetime.end() }
        if let openMessageWithContext {
            openMessageWithContext(context, message.id, origin)
        } else {
            openMessage(context, message.id)
        }
    }
    public let showStory: (any AccountContextProtocol, PeerId, Int32) -> Void
    public var showStoryWithContext: ((any AccountContextProtocol, PeerId, Int32, AnalyticsContext) -> Void)?
    public func showStoryObserved(_ context: any AccountContextProtocol, _ peerId: PeerId, _ storyId: Int32, analyticsContext: AnalyticsContext) {
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: analyticsContext)
        let lifetime = origin.beginPresentation()
        defer { lifetime.end() }
        if let showStoryWithContext {
            showStoryWithContext(context, peerId, storyId, origin)
        } else {
            showStory(context, peerId, storyId)
        }
    }
    public let shareLink: (any AccountContextProtocol, String) -> Void
    public let openGiftSlug: (any AccountContextProtocol, String) -> Void

    public init(makeStickerView: @escaping () -> StatisticsStickerView,
                makeMonetizationController: @escaping (any AccountContextProtocol, PeerId) -> ViewController,
                makeStarMonetizationController: @escaping (any AccountContextProtocol, PeerId) -> ViewController,
                makeBoostStatsController: @escaping (any AccountContextProtocol, PeerId) -> ViewController,
                openPeerInfo: @escaping (any AccountContextProtocol, PeerId) -> Void,
                makeSharedRowItem: @escaping (NSSize, AnyHashable, any AccountContextProtocol, StoryStatsPublicForwardsContext.State.Forward, GeneralViewType, @escaping () -> Void) -> TableRowItem,
                openMessage: @escaping (any AccountContextProtocol, MessageId) -> Void,
                showStory: @escaping (any AccountContextProtocol, PeerId, Int32) -> Void,
                shareLink: @escaping (any AccountContextProtocol, String) -> Void,
                openGiftSlug: @escaping (any AccountContextProtocol, String) -> Void) {
        self.makeStickerView = makeStickerView
        self.makeMonetizationController = makeMonetizationController
        self.makeStarMonetizationController = makeStarMonetizationController
        self.makeBoostStatsController = makeBoostStatsController
        self.openPeerInfo = openPeerInfo
        self.makeSharedRowItem = makeSharedRowItem
        self.openMessage = openMessage
        self.showStory = showStory
        self.shareLink = shareLink
        self.openGiftSlug = openGiftSlug
    }

    private static var _shared: StatisticsHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: StatisticsHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("StatisticsHooks.install must be called before the statistics screens are used")
        return .placeholder
    }

    public static func install(_ hooks: StatisticsHooks) {
        assert(Thread.isMainThread, "StatisticsHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = StatisticsHooks(
        makeStickerView: { StatisticsPlaceholderStickerView(frame: .zero) },
        makeMonetizationController: { _, _ in ViewController() },
        makeStarMonetizationController: { _, _ in ViewController() },
        makeBoostStatsController: { _, _ in ViewController() },
        openPeerInfo: { _, _ in },
        makeSharedRowItem: { initialSize, stableId, _, _, viewType, _ in
            GeneralRowItem(initialSize, stableId: stableId, viewType: viewType) },
        openMessage: { _, _ in },
        showStory: { _, _, _ in },
        shareLink: { _, _ in },
        openGiftSlug: { _, _ in }
    )
}

final class StatisticsPlaceholderStickerView: View, StatisticsStickerView {
    func updateSticker(animation: LocalAnimatedSticker, size: NSSize, context: any AccountContextProtocol, table: TableView?, animated: Bool) {

    }
}
