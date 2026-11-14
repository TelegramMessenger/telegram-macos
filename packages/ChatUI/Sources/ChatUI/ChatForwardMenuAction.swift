import AppAnalytics
import Postbox
import TelegramCore

final class ChatForwardMenuAction {
    let analyticsContext: AnalyticsContext
    private weak var chatInteraction: ChatInteraction?
    private let action: ChatDeferredSendAction

    init(chatInteraction: ChatInteraction, sources: [Message]) {
        self.chatInteraction = chatInteraction
        self.action = chatInteraction.captureDeferredSendAction()
        var origin = chatInteraction.captureAnalyticsContext()
        for message in sources {
            if message.containsSecretMedia { origin = Analytics.shared.unresolvedContext() }
            origin = origin.restricting(peerId: message.id.peerId)
        }
        self.analyticsContext = origin
    }

    func openPicker(messages: [Message], entry: AnalyticsFlows.ChatForwardPicker.EntryPoint) {
        guard let chatInteraction, action.takeIfCurrent() else { return }
        chatInteraction.forwardMessagesObserved(messages, analyticsContext: analyticsContext, entry: entry)
    }

    func forward(_ object: ChatHistoryForwardMessagesObject, peerId: PeerId, threadId: Int64?) {
        guard let chatInteraction else { return }
        chatInteraction.quickForward(object, peerId: peerId, threadId: threadId, analyticsContext: analyticsContext, action: action)
    }
}
