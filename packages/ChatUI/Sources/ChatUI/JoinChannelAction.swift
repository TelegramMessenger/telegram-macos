import AppAnalytics
import Cocoa
import TelegramCore
import Localization
import Postbox
import SwiftSignalKit
import TGUIKit
import InAppSettings
import ColorPalette
import ThemeSettings
import TelegramTheme
import TelegramContext
import AlertsUI

public func joinChannel(context: any AccountContextProtocol, peerId: PeerId) {
    joinChannel(context: context, peerId: peerId, analyticsContext: nil)
}

public func joinChannel(context: any AccountContextProtocol, peerId: PeerId, analyticsContext: AnalyticsContext?) {
    let origin = Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: analyticsContext ?? Analytics.shared.unresolvedContext())
    let presentation = origin.beginPresentation()
    defer { presentation.end() }
    let signal = context.engine.peers.joinChannel(peerId: peerId, hash: nil) |> take(1) |> deliverOnMainQueue
    _ = origin.preservingPresentation(showModalProgress(signal: signal, for: context.window)).start(next: { outcome in
        switch outcome {
        case .joined:
            _ = origin.preservingPresentation(showModalSuccess(for: context.window, icon: theme.icons.successModalProgress, delay: 1.5)).start()
        case let .webView(webView):
            ChatNavigationHooks.shared.openJoinChatBotWebViewObserved(context, webView.botPeer.id, webView.url, webView.queryId, peerId, analyticsContext: origin)
        }
    }, error: { error in
        let text: String
        switch error {
        case .generic:
            text = strings().unknownError
        case .tooMuchJoined:
            ChatNavigationHooks.shared.showInactiveChannelsOnJoinObserved(context, analyticsContext: origin)
            return
        case .tooMuchUsers:
            text = strings().groupUsersTooMuchError
        case .inviteRequestSent:
            showModalText(for: context.window, text: strings().chatSendJoinRequestInfo, title: strings().chatSendJoinRequestTitle)
            return
        }
        alert(for: context.window, info: text)
    })
}
