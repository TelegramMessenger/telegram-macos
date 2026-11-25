import AppAnalytics
import AlertsUI
import Foundation
import Localization
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramCore
import TelegramTheme
import TelegramUtils
import TGUIKit

final class JoinChatWebViewOperation {
    let uniqueId: BrowserTabData.Unique
    private let context: any AccountContextProtocol
    private let botId: PeerId
    private let queryId: Int64
    private var peerId: PeerId?
    private var origin: AnalyticsContext
    private weak var owner: BrowserStateContext?
    private let finished: (JoinChatWebViewOperation) -> Void
    private let decisions = MetaDisposable()
    private let lookup = MetaDisposable()
    private let urlRequest = MetaDisposable()
    private let pendingOpen = MetaDisposable()
    private var bot: EnginePeer?
    private var initialResult: RequestWebViewResult?
    private var latestUrl: String?
    private var openedUrl: String?
    private var waitingForOpen = false
    private var ended = false

    init(context: any AccountContextProtocol, owner: BrowserStateContext, botId: PeerId, url: String?, queryId: Int64, peerId: PeerId?, analyticsContext: AnalyticsContext?, finished: @escaping (JoinChatWebViewOperation) -> Void) {
        self.context = context
        self.owner = owner
        self.botId = botId
        self.queryId = queryId
        self.peerId = peerId
        self.uniqueId = .webapp(queryId)
        let inherited = peerId == nil ? Analytics.shared.unresolvedContext() : analyticsContext ?? Analytics.shared.unresolvedContext()
        self.origin = Analytics.shared.captureContext(engine: context.engine, peerId: peerId ?? botId, inherited: inherited).restricting(peerId: botId)
        self.finished = finished
        if let url {
            self.initialResult = RequestWebViewResult(flags: [], queryId: queryId, url: url, keepAliveSignal: nil)
        }
    }

    func start() {
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        decisions.set((context.account.stateManager.joinChatWebViewDecisions |> deliverOnMainQueue).start(next: { [weak self] values in
            self?.receive(values)
        }, completed: { [weak self] in
            self?.cancel(closeTab: true)
        }))
        guard !ended else { return }
        var receivedPeer = false
        let peerSignal = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: botId)) |> take(1) |> deliverOnMainQueue
        lookup.set(origin.preservingPresentation(peerSignal).start(next: { [weak self] peer in
            guard let self, !self.ended else { return }
            receivedPeer = true
            guard let peer, peer.id == self.botId else {
                self.finish(error: true)
                return
            }
            self.bot = peer
            self.presentLatest()
        }, completed: { [weak self] in
            if !receivedPeer { self?.cancel(closeTab: true) }
        }))
        guard !ended, initialResult == nil else { return }
        var receivedUrl = false
        let signal = context.engine.messages.requestChatJoinWebView(queryId: queryId, themeParams: generateWebAppThemeParams(theme)) |> take(1) |> deliverOnMainQueue
        urlRequest.set(origin.preservingPresentation(signal).start(next: { [weak self] result in
            guard let self, !self.ended else { return }
            receivedUrl = true
            self.initialResult = result
            self.presentLatest()
        }, error: { [weak self] _ in
            self?.finish(error: true)
        }, completed: { [weak self] in
            if !receivedUrl { self?.cancel(closeTab: true) }
        }))
    }

    private func receive(_ values: [JoinChatWebViewDecision]) {
        guard !ended else { return }
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        for decision in values {
            guard decision.queryId == queryId, peerId == nil || peerId == decision.peerId else { continue }
            peerId = decision.peerId
            origin = origin.restricting(peerId: decision.peerId)
            switch decision.result {
            case let .webView(url):
                latestUrl = url
            case .approved, .declined, .queued:
                finish(result: decision.result)
                return
            }
        }
        presentLatest()
    }

    private func presentLatest() {
        guard !ended, !waitingForOpen, let owner, let bot, let initialResult else { return }
        let url = latestUrl ?? initialResult.url
        guard openedUrl != url else { return }
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        let result = RequestWebViewResult(flags: initialResult.flags, queryId: initialResult.queryId ?? queryId, url: url, keepAliveSignal: initialResult.keepAliveSignal)
        let tab: BrowserTabData.Data = .straight(bot: bot, peerId: peerId ?? botId, title: bot._asPeer().displayTitle, result: result)
        if openedUrl != nil { owner.closeJoinChatTab(uniqueId: uniqueId) }
        guard !ended else { return }
        waitingForOpen = true
        let request = MetaDisposable()
        pendingOpen.set(request)
        request.set(owner.openCancellable(tab: tab, uniqueId: uniqueId, analyticsContext: origin, completion: { [weak self] opened in
            guard let self, !self.ended else { return }
            self.waitingForOpen = false
            guard opened else {
                self.cancel(closeTab: true)
                return
            }
            self.openedUrl = url
            self.presentLatest()
        }))
    }

    func cancel(closeTab: Bool) {
        finish(closeTab: closeTab)
    }

    private func finish(result: JoinChatWebViewResult? = nil, error: Bool = false, closeTab: Bool = true) {
        guard !ended else { return }
        ended = true
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        decisions.dispose()
        lookup.dispose()
        urlRequest.dispose()
        pendingOpen.dispose()
        finished(self)
        if closeTab { owner?.closeJoinChatTab(uniqueId: uniqueId) }
        if error {
            alert(for: context.window, info: strings().unknownError)
        } else if let result {
            switch result {
            case .approved:
                _ = origin.preservingPresentation(showModalSuccess(for: context.window, icon: theme.icons.successModalProgress, delay: 1.5)).start()
            case .declined:
                alert(for: context.window, info: strings().unknownError)
            case .queued:
                showModalText(for: context.window, text: strings().chatSendJoinRequestInfo, title: strings().chatSendJoinRequestTitle)
            case .webView:
                break
            }
        }
    }

    deinit {
        decisions.dispose()
        lookup.dispose()
        urlRequest.dispose()
        pendingOpen.dispose()
    }
}
