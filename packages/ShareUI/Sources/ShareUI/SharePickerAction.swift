import AppAnalytics
import SwiftSignalKit

final class SharePickerAction {
    private let disposable = MetaDisposable()
    private var generation: UInt64 = 0
    private var pending: UInt64?
    private var closed = false

    func reset() {
        generation &+= 1
        pending = nil
        disposable.set(nil)
    }

    func close() {
        closed = true
        reset()
    }

    private func finish(_ generation: UInt64) -> Bool {
        guard !closed, pending == generation else { return false }
        pending = nil
        return true
    }

    func start<Value, Failure>(context: AnalyticsContext, request: () -> Signal<Value, Failure>, next: @escaping (Value) -> Void, error: @escaping (Failure) -> Void, completed: @escaping () -> Void) {
        guard !closed, pending == nil else { return }
        generation &+= 1
        let generation = self.generation
        pending = generation
        let subscription = MetaDisposable()
        disposable.set(subscription)
        guard !closed, pending == generation else { return }
        let presentation = context.beginPresentation()
        defer { presentation.end() }
        let signal = request()
        guard !closed, pending == generation else { return }
        subscription.set(context.preservingPresentation(signal |> take(1) |> deliverOnMainQueue).start(next: { [weak self] value in
            guard self?.finish(generation) == true else { return }
            next(value)
        }, error: { [weak self] failure in
            guard self?.finish(generation) == true else { return }
            error(failure)
        }, completed: { [weak self] in
            guard self?.finish(generation) == true else { return }
            completed()
        }))
    }

    deinit {
        disposable.dispose()
    }
}
