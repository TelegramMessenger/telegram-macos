import Cocoa
import AppAnalytics
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import LocalAnimations
import GeneralRows
import StatisticsUI

extension MediaAnimatedStickerView: @retroactive StatisticsStickerView {

}

func installStatisticsUIHooks() {
    var hooks = StatisticsHooks(
        makeStickerView: { MediaAnimatedStickerView(frame: NSZeroRect) },
        makeMonetizationController: { context, peerId in
        FragmentMonetizationController(context: context as! AccountContext, peerId: peerId) },
        makeStarMonetizationController: { context, peerId in
        FragmentStarMonetizationController(context: context as! AccountContext, peerId: peerId, revenueContext: nil) },
        makeBoostStatsController: { context, peerId in
        ChannelBoostStatsController(context: context as! AccountContext, peerId: peerId) },
        openPeerInfo: { context, peerId in
        guard let context = context as? AccountContext else {
            return
        }
        PeerInfoController.push(navigation: context.bindings.rootNavigation(), context: context, peerId: peerId) },
        makeSharedRowItem: { initialSize, stableId, context, forward, viewType, action in
        MessageSharedRowItem(initialSize, stableId: stableId, context: context as! AccountContext, forward: forward, viewType: viewType, action: action) },
        openMessage: { context, messageId in
        guard let context = context as? AccountContext else {
            return
        }
        let origin = Analytics.shared.unresolvedContext()
        let lifetime = origin.beginPresentation()
        defer { lifetime.end() }
        let controller = ChatAdditionController(context: context, chatLocation: .peer(messageId.peerId), focusTarget: .init(messageId: messageId))
        controller.inheritAnalyticsContext(origin)
        context.bindings.rootNavigation().push(controller) },
        showStory: { context, peerId, storyId in
        StoryModalController.ShowSingleStory(context: context as! AccountContext, storyId: .init(peerId: peerId, id: storyId), initialId: nil) },
        shareLink: { context, link in
        showModal(with: ShareModalController(ShareLinkObject(context, link: link)), for: context.window) },
        openGiftSlug: { context, slug in
        execute(inapp: .gift(link: "", slug: slug, context: context as! AccountContext)) }
    )
    hooks.showStoryWithContext = { context, peerId, storyId, analyticsContext in
        StoryModalController.ShowSingleStory(context: context as! AccountContext, storyId: .init(peerId: peerId, id: storyId), initialId: nil, analyticsContext: analyticsContext)
    }
    hooks.openMessageWithContext = { context, messageId, analyticsContext in
        guard let context = context as? AccountContext else { return }
        let controller = ChatAdditionController(context: context, chatLocation: .peer(messageId.peerId), focusTarget: .init(messageId: messageId))
        controller.inheritAnalyticsContext(analyticsContext)
        context.bindings.rootNavigation().push(controller)
    }
    hooks.openPeerInfoWithContext = { context, peerId, analyticsContext in
        guard let context = context as? AccountContext else { return }
        PeerInfoController.push(navigation: context.bindings.rootNavigation(), context: context, peerId: peerId, analyticsContext: analyticsContext)
    }
    StatisticsHooks.install(hooks)
}
