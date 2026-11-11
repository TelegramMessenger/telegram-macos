import SwiftSignalKit

func storyPaidReplyBalanceReady(_ balance: Signal<Int64?, NoError>, required: Int64, isCurrent: @escaping () -> Bool = { true }) -> Signal<Void, NoError> {
    guard required >= 0 else { return .complete() }
    return balance |> filter { $0.map { $0 >= required } ?? false } |> take(1) |> filter { _ in isCurrent() } |> map { _ in () }
}
