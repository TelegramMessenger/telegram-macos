import AppAnalytics
import AlertsUI
import InputDataUI
import Localization
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramCore
import TGUIKit

final class InviteJoinAction {
    private var closed = false
    private var nextId: UInt64 = 0
    private var pending: UInt64?

    func begin() -> UInt64? {
        guard !closed, pending == nil else { return nil }
        nextId &+= 1
        pending = nextId
        return nextId
    }

    func take(_ id: UInt64, terminal: Bool) -> Bool {
        guard !closed, pending == id else { return false }
        pending = nil
        if terminal { closed = true }
        return true
    }

    func detach(_ id: UInt64) -> ((Bool) -> Bool)? {
        guard take(id, terminal: true) else { return nil }
        let consumed = Atomic(value: false)
        return { _ in !consumed.swap(true) }
    }

    func close() {
        closed = true
        pending = nil
    }
}

func performInviteJoin(context: any AccountContextProtocol, hash: String, window: Window, analyticsContext: AnalyticsContext, requestSentAsSuccess: Bool, takeResult: @escaping (Bool) -> Bool, close: @escaping () -> Void, interaction: @escaping (Peer) -> Void) -> Disposable {
    let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext)
    let presentation = origin.beginPresentation()
    defer { presentation.end() }
    let signal = context.engine.peers.joinChatInteractively(with: hash) |> take(1) |> deliverOnMainQueue
    return origin.preservingPresentation(showModalProgress(signal: signal, for: window)).start(next: { outcome in
        guard takeResult(true) else { return }
        switch outcome {
        case let .joined(peer):
            if let peer {
                let destination = origin.restricting(peerId: peer.id)
                let delivery = destination.beginPresentation()
                defer { delivery.end() }
                interaction(peer._asPeer())
            }
            close()
        case let .webView(webView):
            close()
            FeatureNavigationHooks.shared.openJoinChatBotWebViewObserved(context, webView.botPeer.id, webView.url, webView.queryId, webView.peerId, analyticsContext: origin)
        }
    }, error: { error in
        guard takeResult(false) else { return }
        let text: String
        switch error {
        case .generic:
            text = strings().unknownError
        case .tooMuchJoined:
            FeatureNavigationHooks.shared.showInactiveChannelsObserved(context, .join, analyticsContext: origin)
            return
        case .tooMuchUsers:
            text = strings().groupUsersTooMuchError
        case .requestSent:
            if requestSentAsSuccess {
                showModalText(for: context.window, text: strings().requestJoinSent)
                return
            }
            text = strings().unknownError
        case .flood:
            text = strings().joinLinkFloodError
        }
        alert(for: context.window, info: text)
    }, completed: {
        _ = takeResult(false)
    })
}
