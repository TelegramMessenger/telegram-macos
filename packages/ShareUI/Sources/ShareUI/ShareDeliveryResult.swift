import AppAnalytics
import InputView
import TelegramCore
import Postbox
import SwiftSignalKit

public enum SharePickerResult: Equatable {
    case draftPrepared
    case destinationReady
    case sourceUnavailable
    case targetUnavailable
    case accepted
    case partiallyAccepted
    case rejected
    case unknown
    case cancelled
    case dispatched
}

extension SharePickerResult {
    init(deliveries: [ShareRecipientDelivery]) {
        let statuses = deliveries.map { $0.status }
        if statuses.isEmpty || statuses.contains(.unknown) || statuses.contains(.notAttempted) {
            self = .unknown
        } else if statuses.allSatisfy({ $0 == .accepted }) {
            self = .accepted
        } else if statuses.contains(.partial) || statuses.contains(.accepted) {
            self = .partiallyAccepted
        } else {
            self = .rejected
        }
    }
}

enum ShareDeliveryStatus: Equatable {
    case accepted
    case partial
    case rejected
    case unknown
    case notAttempted
}

struct ShareDeliveryPart: Equatable {
    let expectedCount: Int
    let acceptedCount: Int?
    let messageIds: [MessageId]

    init(expectedCount: Int, result: [MessageId?]?) {
        self.expectedCount = expectedCount
        self.messageIds = result?.compactMap { $0 } ?? []
        if expectedCount > 0, let result, result.count == expectedCount {
            self.acceptedCount = result.compactMap { $0 }.count
        } else {
            self.acceptedCount = nil
        }
    }

    var status: ShareDeliveryStatus {
        guard expectedCount > 0 else { return .notAttempted }
        guard let acceptedCount else { return .unknown }
        if acceptedCount == expectedCount { return .accepted }
        return acceptedCount == 0 ? .rejected : .partial
    }
}

struct ShareRecipientDelivery: Equatable {
    let peerId: PeerId
    let comment: ShareDeliveryPart?
    let content: ShareDeliveryPart

    var status: ShareDeliveryStatus {
        let statuses = ([content] + (comment.map { [$0] } ?? [])).map { $0.status }
        if statuses.contains(.unknown) { return .unknown }
        if statuses.allSatisfy({ $0 == .notAttempted }) { return .notAttempted }
        if statuses.allSatisfy({ $0 == .accepted }) { return .accepted }
        if statuses.contains(.partial) || statuses.contains(.accepted) { return .partial }
        return .rejected
    }
}

func shareFirstResult<Value, Failure>(_ signal: Signal<Value, Failure>, or fallback: Value) -> Signal<Value, Failure> {
    return Signal { subscriber in
        var received = false
        return (signal |> take(1) |> deliverOnMainQueue).start(next: { value in
            received = true
            subscriber.putNext(value)
        }, error: { error in
            subscriber.putError(error)
        }, completed: {
            if !received { subscriber.putNext(fallback) }
            subscriber.putCompletion()
        })
    }
}


protocol ShareDeliveryProviding: AnyObject {
    var messagesCount: Int { get }
    func outgoingMessageCount(comment: ChatTextInputState?) -> Int
    func sharingAnalyticsContext(_ inherited: AnalyticsContext?) -> AnalyticsContext
    func performWithResults(to peerIds: [PeerId], threadId: Int64?, comment: ChatTextInputState?, sendPaidMessageStars: [PeerId: StarsAmount], analyticsContext: AnalyticsContext?) -> Signal<[ShareRecipientDelivery], String>
}

extension ShareDeliveryProviding {
    func outgoingMessageCount(comment: ChatTextInputState?) -> Int {
        return messagesCount + (comment?.inputText.isEmpty == false ? 1 : 0)
    }
}
