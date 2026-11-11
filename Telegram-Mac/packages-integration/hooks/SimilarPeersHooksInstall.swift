import Cocoa
import AppAnalytics
import TGUIKit
import Postbox
import PeerInfoUI

func installSimilarPeersUIHooks() {
    var hooks = SimilarPeersHooks(
        openChat: { context, peerId in
        guard let context = context as? AccountContext else {
            return
        }
        let origin = Analytics.shared.unresolvedContext()
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        let controller = ChatAdditionController(context: context, chatLocation: .peer(peerId))
        controller.inheritAnalyticsContext(origin)
        context.bindings.rootNavigation().push(controller) }
    )
    hooks.openChatWithContext = { context, peerId, analyticsContext in
        guard let context = context as? AccountContext else { return }
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        let controller = ChatAdditionController(context: context, chatLocation: .peer(peerId))
        controller.inheritAnalyticsContext(origin)
        context.bindings.rootNavigation().push(controller)
    }
    SimilarPeersHooks.install(hooks)
}
