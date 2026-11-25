import AppAnalytics
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramCore
import TGUIKit

final class BrowserPreparedShareAction {
    private var generation: UInt64 = 0
    private var active = false
    private let request = MetaDisposable()
    private weak var preview: ModalViewController?
    private var journey: AnalyticsPreparedShareJourney?

    func reset() {
        generation &+= 1
        active = false
        journey?.discard()
        journey = nil
        let preview = self.preview
        self.preview = nil
        request.set(nil)
        preview?.close()
    }

    private func isCurrent(_ generation: UInt64) -> Bool {
        return active && self.generation == generation
    }

    private func finish(_ generation: UInt64) -> Bool {
        guard isCurrent(generation) else { return false }
        active = false
        journey = nil
        preview = nil
        request.set(nil)
        return self.generation == generation
    }

    func open(context: any AccountContextProtocol, bot: Peer, id: String, window: Window, analyticsContext: AnalyticsContext, canPresent: @escaping () -> Bool, completion: @escaping (Bool) -> Void) {
        guard !active, !id.isEmpty else { return }
        generation &+= 1
        let generation = self.generation
        active = true
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext).restricting(peerId: bot.id)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        let pending = MetaDisposable()
        request.set(pending)
        guard canPresent(), isCurrent(generation) else {
            _ = finish(generation)
            return
        }
        let journey = AnalyticsPreparedShareJourney(context: origin)
        self.journey = journey
        var received = false
        let signal = showModalProgress(signal: context.engine.messages.getPreparedInlineMessage(botId: bot.id, id: id) |> take(1) |> deliverOnMainQueue, for: window)
        guard canPresent(), isCurrent(generation) else {
            _ = finish(generation)
            return
        }
        pending.set(origin.preservingPresentation(signal).start(next: { [weak self] preparedMessage in
            guard let self, self.isCurrent(generation) else { return }
            received = true
            guard canPresent() else {
                _ = self.finish(generation)
                return
            }
            guard let preparedMessage else {
                if self.finish(generation) {
                    journey.metadataUnavailable()
                    completion(false)
                }
                return
            }
            let origin = origin.restricting(peerId: preparedMessage.botId)
            let presentation = origin.beginPresentation()
            defer { presentation.end() }
            journey.metadataReady()
            let preview = WebbotShareMessageModal(context: context, bot: EnginePeer(bot), preparedMessage: preparedMessage, window: window, analyticsContext: origin, analyticsJourney: journey, callback: { [weak self] status in
                guard let self, self.finish(generation), canPresent() else { return }
                let delivery = origin.beginPresentation()
                defer { delivery.end() }
                switch status {
                case .success: completion(true)
                case .failed: completion(false)
                }
            })
            guard canPresent(), self.isCurrent(generation) else {
                _ = self.finish(generation)
                preview.close()
                return
            }
            self.preview = preview
            journey.previewOpened()
            showModal(with: preview, for: window)
        }, completed: { [weak self] in
            guard !received, let self, self.finish(generation), canPresent() else { return }
            journey.metadataUnavailable()
            completion(false)
        }))
    }

    deinit {
        journey?.discard()
        request.dispose()
        preview?.close()
    }
}
