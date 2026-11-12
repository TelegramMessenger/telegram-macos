import Postbox
import SwiftSignalKit
import TelegramCore

enum ShareMessageDeliveryState {
    case pending
    case delivered
    case failed(PendingMessageFailureReason?)

    init(flags: MessageFlags?, failureReason: PendingMessageFailureReason?) {
        if let flags, flags.contains(.Failed) {
            self = .failed(failureReason)
        } else if flags == nil || !flags!.contains(.Unsent) {
            self = .delivered
        } else {
            self = .pending
        }
    }
}

struct ShareMessageDeliveryOutcome {
    let id: MessageId
    let failed: Bool
    let failureReason: PendingMessageFailureReason?
}

func shareAwaitMessageDelivery(ids: [MessageId], status: @escaping (MessageId) -> Signal<ShareMessageDeliveryState, NoError>) -> Signal<[ShareMessageDeliveryOutcome], NoError> {
    var seen = Set<MessageId>()
    let ids = ids.filter { seen.insert($0).inserted }
    guard !ids.isEmpty else { return .single([]) }
    let outcomes = ids.map { id in
        status(id)
        |> mapToSignal { state -> Signal<ShareMessageDeliveryOutcome, NoError> in
            switch state {
            case .pending: return .complete()
            case .delivered: return .single(ShareMessageDeliveryOutcome(id: id, failed: false, failureReason: nil))
            case let .failed(reason): return .single(ShareMessageDeliveryOutcome(id: id, failed: true, failureReason: reason))
            }
        }
        |> take(1)
    }
    return combineLatest(outcomes) |> take(1)
}
