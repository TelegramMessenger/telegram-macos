import Foundation

public final class AnalyticsMessageSend: AnalyticsRevocable {
    private let scope: AnalyticsScope
    private weak var analytics: Analytics?
    private var event: AnalyticsEvent?

    public init?(context: AnalyticsContext, kind: AnalyticsValues.MessageKind, peerType: AnalyticsValues.PeerType?, hasReply: Bool, scheduled: Bool, silent: Bool) {
        guard let scope = context.scope, peerType != .secretChat else { return nil }
        self.scope = scope
        self.analytics = context.analytics
        let admitted = scope.perform {
            guard context.analytics != nil, !context.isExcluded else { return false }
            event = AnalyticsEvents.chatMessageSend(kind: kind, peerType: peerType, hasReply: hasReply, scheduled: scheduled, silent: silent)
            scope.observe(self)
            return true
        } ?? false
        if !admitted { return nil }
    }

    public func complete(expectedCount: Int, resultCount: Int, acceptedCount: Int) {
        scope.perform {
            guard let event else { return }
            revokeAnalytics()
            guard expectedCount > 0, resultCount == expectedCount, acceptedCount == expectedCount else { return }
            analytics?.send(event, scope: scope)
        }
    }

    public func discard() {
        scope.policy.sync { revokeAnalytics() }
    }

    func revokeAnalytics() {
        event = nil
        scope.removeObserver(self)
    }

    deinit {
        discard()
    }
}
