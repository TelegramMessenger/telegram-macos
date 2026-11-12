import AppAnalytics
import AlertsUI
import ChatHistoryModel
import Dispatch
import Localization
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramCore
import TGUIKit

final class ProfileOwnContactShareAction {
    private typealias Spec = AnalyticsFlows.PeerInfoShareOwnContact
    private let disposable = MetaDisposable()
    private var generation: UInt64 = 0
    private var pending: UInt64?
    private var confirmation: UInt64?
    private var flow: AnalyticsFlow<Spec>?

    func reset() {
        generation &+= 1
        pending = nil
        confirmation = nil
        flow?.discard()
        flow = nil
        disposable.set(nil)
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        return pending == generation
    }

    private func finish(_ outcome: AnalyticsFlowOutcome) {
        let flow = self.flow
        self.flow = nil
        reset()
        flow?.finish(outcome)
    }

    private func request<Value>(_ generation: UInt64, origin: AnalyticsContext, build: () -> Signal<Value, NoError>, next: @escaping (Value) -> Void, empty: (() -> Void)? = nil) {
        guard isCurrent(generation) else { return }
        let subscription = MetaDisposable()
        disposable.set(subscription)
        guard isCurrent(generation) else { return }
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        let signal = build()
        guard isCurrent(generation) else { return }
        var received = false
        subscription.set(origin.preservingPresentation(signal |> take(1) |> deliverOnMainQueue).start(next: { [weak self] value in
            guard self?.isCurrent(generation) == true else { return }
            received = true
            next(value)
        }, completed: { [weak self] in
            guard let self, self.isCurrent(generation), !received else { return }
            if let empty { empty() } else { self.reset() }
        }))
    }

    func start(context: any AccountContextProtocol, peerId: PeerId, analyticsContext: AnalyticsContext) {
        guard pending == nil else { return }
        generation &+= 1
        let generation = self.generation
        pending = generation
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext).restricting(peerId: peerId)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        let flow = AnalyticsFlow<Spec>(analytics: Analytics.shared, scope: origin.scope, source: .peerInfo)
        guard isCurrent(generation) else { flow.discard(); return }
        self.flow = flow
        flow.step(.request)
        request(generation, origin: origin, build: {
            context.account.postbox.transaction { $0.getPeer(peerId) }
        }, next: { [weak self] peer in
            guard let self else { return }
            guard let peer else {
                self.flow?.set(result: .targetUnavailable)
                self.flow?.step(.targetUnavailable)
                self.finish(.fail)
                return
            }
            let origin = origin.restricting(peerId: peer.id)
            let lifetime = origin.beginPresentation()
            self.flow?.step(.targetReady)
            self.confirmation = generation
            self.flow?.step(.openConfirmation)
            guard self.isCurrent(generation) else { return }
            verifyAlert_button(for: context.window, information: strings().peerInfoConfirmShareInfo(peer.displayTitle), successHandler: { [weak self] _ in
                withExtendedLifetime(lifetime) {
                    guard let self, self.isCurrent(generation), self.confirmation == generation else { return }
                    self.confirmation = nil
                    let delivery = origin.beginPresentation()
                    defer { delivery.end() }
                    self.flow?.step(.confirm)
                    self.send(generation, context: context, peerId: peerId, origin: origin)
                }
            }, cancelHandler: { [weak self] in
                withExtendedLifetime(lifetime) {
                    guard let self, self.isCurrent(generation), self.confirmation == generation else { return }
                    self.confirmation = nil
                    let delivery = origin.beginPresentation()
                    defer { delivery.end() }
                    self.flow?.step(.cancel)
                    self.finish(.cancelled)
                }
            }, onDeinit: { [weak self] in
                DispatchQueue.main.async {
                    withExtendedLifetime(lifetime) {
                        guard let self, self.isCurrent(generation), self.confirmation == generation else { return }
                        self.reset()
                    }
                }
            })
        })
    }

    private func send(_ generation: UInt64, context: any AccountContextProtocol, peerId: PeerId, origin: AnalyticsContext) {
        request(generation, origin: origin, build: {
            context.account.postbox.transaction { $0.getPeer(context.peerId) }
        }, next: { [weak self] peer in
            guard let self else { return }
            let origin = peer.map { origin.restricting(peerId: $0.id) } ?? origin
            let presentation = origin.beginPresentation()
            defer { presentation.end() }
            guard let peer = peer as? TelegramUser, peer.id == context.peerId else {
                self.flow?.set(result: .sourceUnavailable)
                self.flow?.step(.sourceUnavailable)
                self.finish(.fail)
                return
            }
            self.flow?.step(.sourceReady)
            self.request(generation, origin: origin, build: {
                self.flow?.step(.submit)
                let message = EnqueueMessage.message(text: "", attributes: [], inlineStickers: [:], mediaReference: AnyMediaReference.standalone(media: TelegramMediaContact(firstName: peer.firstName ?? "", lastName: peer.lastName ?? "", phoneNumber: peer.phone ?? "", peerId: peer.id, vCardData: nil)), threadId: nil, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                var terminal = false
                let signal = Sender.enqueue(message: message, context: context, peerId: peerId)
                |> beforeNext { _ in terminal = true }
                |> beforeCompleted { terminal = true }
                |> afterDisposed { [weak self] in
                    guard !terminal, let self, self.isCurrent(generation) else { return }
                    self.reset()
                }
                return showModalProgress(signal: signal, for: context.window)
            }, next: { [weak self] result in
                self?.complete(result)
            }, empty: { [weak self] in self?.complete(nil) })
        })
    }

    private func complete(_ result: [MessageId?]?) {
        guard let result, result.count == 1 else {
            flow?.set(result: .acceptanceUnknown)
            flow?.step(.acceptanceUnknown)
            finish(.fail)
            return
        }
        if result[0] != nil {
            flow?.set(result: .accepted)
            flow?.step(.accepted)
            finish(.success)
        } else {
            flow?.set(result: .rejected)
            flow?.step(.rejected)
            finish(.fail)
        }
    }

    deinit {
        disposable.dispose()
        flow?.discard()
    }
}
