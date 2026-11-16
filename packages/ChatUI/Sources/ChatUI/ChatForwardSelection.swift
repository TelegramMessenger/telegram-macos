import AppAnalytics
import Postbox
import SwiftSignalKit
import TelegramCore

final class ChatForwardSelection {
    private let disposable = MetaDisposable()
    private var generation: UInt64 = 0
    private var selectedIds: Set<MessageId>?
    private var journey: AnalyticsForwardPickerJourney?

    func reset() {
        generation &+= 1
        selectedIds = nil
        journey?.discard()
        journey = nil
        disposable.set(nil)
    }

    private func finish(_ generation: UInt64) -> Bool {
        guard self.generation == generation, selectedIds != nil else { return false }
        selectedIds = nil
        return true
    }

    private func sourceCoverage(_ messages: [Message], requested: Set<MessageId>) -> AnalyticsForwardPickerJourney.Spec.SourceCoverage {
        let returned = Set(messages.map { $0.id })
        guard returned.count == messages.count, returned.isSubset(of: requested) else { return .unexpected }
        return returned == requested ? .complete : .partial
    }

    func load(ids: Set<MessageId>, analyticsContext: AnalyticsContext, trackForwarding: Bool, request: () -> Signal<[Message], NoError>, completion: @escaping ([Message], AnalyticsForwardPickerJourney?) -> Void) {
        guard !ids.isEmpty, selectedIds != ids else { return }
        let expectedGeneration = generation &+ 1
        reset()
        guard generation == expectedGeneration, selectedIds == nil else { return }
        selectedIds = ids
        let generation = self.generation
        let presentation = analyticsContext.beginPresentation()
        defer { presentation.end() }
        let journey = trackForwarding ? AnalyticsForwardPickerJourney(context: analyticsContext, entry: .messageSelection, sourceLookup: true) : nil
        guard self.generation == generation, selectedIds != nil else { journey?.discard(); return }
        self.journey = journey
        let pending = MetaDisposable()
        disposable.set(pending)
        guard self.generation == generation, selectedIds != nil else { return }
        let signal = request()
        guard self.generation == generation, selectedIds != nil else { return }
        pending.set(analyticsContext.preservingPresentation(signal |> take(1) |> deliverOnMainQueue).start(next: { [weak self] messages in
            guard let self, self.finish(generation) else { return }
            let journey = self.journey
            self.journey = nil
            var origin = analyticsContext
            for message in messages {
                if message.containsSecretMedia { origin = Analytics.shared.unresolvedContext() }
                origin = origin.restricting(peerId: message.id.peerId)
            }
            let lifetime = origin.beginPresentation()
            defer { lifetime.end() }
            guard !messages.isEmpty else { journey?.sourceUnavailable(); return }
            journey?.sourceReady(coverage: self.sourceCoverage(messages, requested: ids))
            completion(messages, journey)
        }, completed: { [weak self] in
            guard let self, self.finish(generation) else { return }
            self.journey?.discard()
            self.journey = nil
        }))
    }

    deinit {
        journey?.discard()
        disposable.dispose()
    }
}

final class ChatForwardSendPreparation {
    private final class Pending {
        let disposable = MetaDisposable()
        var cancelled: (() -> Void)?

        init(cancelled: @escaping () -> Void) {
            self.cancelled = cancelled
        }

        func finish() {
            cancelled = nil
        }

        func cancel() {
            let cancelled = self.cancelled
            self.cancelled = nil
            disposable.dispose()
            cancelled?()
        }
    }

    private var pending: Pending?

    var isPending: Bool { pending != nil }

    func reset() {
        let pending = self.pending
        self.pending = nil
        pending?.cancel()
    }

    func prepare<Value>(isCurrent: @escaping () -> Bool, invalidated: @escaping () -> Void, request: @escaping () -> Signal<Value, NoError>) -> Signal<Value, NoError> {
        return Signal { [weak self] subscriber in
            guard let self, self.pending == nil, isCurrent() else {
                invalidated()
                subscriber.putCompletion()
                return EmptyDisposable
            }
            let pending = Pending(cancelled: {
                invalidated()
                subscriber.putCompletion()
            })
            self.pending = pending
            let signal = request()
            guard self.pending === pending, isCurrent() else {
                if self.pending === pending { self.pending = nil }
                pending.cancel()
                return EmptyDisposable
            }
            pending.disposable.set((signal |> take(1) |> deliverOnMainQueue).start(next: { [weak self] value in
                guard let self, self.pending === pending else { return }
                guard isCurrent() else { self.reset(); return }
                self.pending = nil
                pending.finish()
                subscriber.putNext(value)
                subscriber.putCompletion()
            }, completed: { [weak self] in
                guard let self, self.pending === pending else { return }
                self.reset()
            }))
            return ActionDisposable { [weak self] in
                if self?.pending === pending { self?.pending = nil }
                pending.cancel()
            }
        }
    }

    deinit {
        reset()
    }
}
