import AlertsUI
import Localization
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramCore

func shareObserveDelivery(_ deliveries: [ShareRecipientDelivery], context: any AccountContextProtocol) {
    let ids = deliveries.flatMap { ($0.comment?.messageIds ?? []) + $0.content.messageIds }
    guard !ids.isEmpty else { return }
    let outcomes = shareAwaitMessageDelivery(ids: ids, status: { id in
        combineLatest(context.engine.data.subscribe(TelegramEngine.EngineData.Item.Messages.Message(id: id)), context.account.pendingMessageManager.pendingMessageStatus(id))
        |> map { message, status in ShareMessageDeliveryState(flags: message?.flags, failureReason: status.1) }
    })
    _ = (outcomes |> deliverOnMainQueue).startStandalone(next: { outcomes in
        let failed = outcomes.filter { $0.failed }
        guard let first = failed.first else { return }
        _ = context.engine.messages.deleteMessagesInteractively(messageIds: failed.map { $0.id }, type: .forEveryone).startStandalone()
        let reason = failed.compactMap { $0.failureReason }.first
        _ = (context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: first.id.peerId)) |> deliverOnMainQueue).startStandalone(next: { peer in
            let text: String
            switch reason {
            case .slowmodeActive: text = strings().chatSendMessageSlowmodeError
            case .flood: text = strings().chatSendMessageErrorFlood
            default: text = strings().shareIncompleteDelivery
            }
            alert(for: context.window, header: peer?.debugDisplayTitle, info: text)
        })
    })
}
