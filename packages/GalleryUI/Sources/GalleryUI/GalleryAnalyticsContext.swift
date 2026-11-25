import AppAnalytics
import Postbox
import TelegramContext
import TelegramCore

final class GalleryAnalyticsContext {
    private(set) var context: AnalyticsContext
    private var presentation: AnalyticsPresentation?

    init(accountContext: any AccountContextProtocol, inherited: AnalyticsContext?, peerId: PeerId? = nil) {
        context = Analytics.shared.captureContext(engine: accountContext.engine, peerId: accountContext.peerId, inherited: inherited ?? Analytics.shared.unresolvedContext())
        if let peerId { context = context.restricting(peerId: peerId) }
    }

    func restrict(peerId: PeerId) {
        replace(context.restricting(peerId: peerId))
    }

    func restrict(messages: [Message]) {
        for message in messages {
            if message.containsSecretMedia { exclude() }
            restrict(peerId: message.id.peerId)
        }
    }

    func exclude() {
        replace(Analytics.shared.unresolvedContext())
    }

    private func replace(_ context: AnalyticsContext) {
        self.context = context
        if presentation != nil {
            let replacement = context.beginPresentation()
            presentation?.end()
            presentation = replacement
        }
    }

    func begin() {
        guard presentation == nil else { return }
        presentation = context.beginPresentation()
    }

    func end() {
        presentation?.end()
        presentation = nil
    }

    deinit {
        end()
    }
}
