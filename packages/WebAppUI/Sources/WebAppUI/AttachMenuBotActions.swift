import Cocoa
import AppAnalytics
import Foundation
import WebKit
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import InAppSettings
import FoundationUtils
import ObjcUtils
import KeyboardKey
import TelegramIconsTheme
import TelegramMedia
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import LocalAnimations
import FilePanels
import TelegramLinks
import PremiumStatusUI
import SystemPermissions
import Svg
import LocalAuthentication

public func installAttachMenuBot(context: (any AccountContextProtocol), peer: Peer, completion: @escaping(Bool)->Void) {
    installAttachMenuBot(context: context, peer: peer, analyticsContext: nil, completion: completion)
}

public func installAttachMenuBot(context: any AccountContextProtocol, peer: Peer, analyticsContext: AnalyticsContext?, completion: @escaping (Bool) -> Void) {
    let origin = analyticsContext.map {
        Analytics.shared.captureContext(engine: context.engine, peerId: peer.id, inherited: $0)
    }
    let presentation = origin?.beginPresentation()
    defer { presentation?.end() }
    var signal = context.engine.messages.addBotToAttachMenu(botId: peer.id, allowWrite: true) |> take(1) |> deliverOnMainQueue
    if let origin { signal = origin.preservingPresentation(signal) }
    _ = signal.start(next: { value in
        if value { completion(value) }
    })
}

public func openWebBot(_ bot: AttachMenuBot, context: (any AccountContextProtocol)) {
    openWebBot(bot, context: context, analyticsContext: nil)
}

public func openWebBot(_ bot: AttachMenuBot, context: any AccountContextProtocol, analyticsContext: AnalyticsContext?) {
    let tab: BrowserTabData.Data = .simple(bot: bot.peer, url: nil, buttonText: "", source: .settings)
    let origin = BrowserAnalyticsOrigin(account: context, data: tab, inherited: analyticsContext)
    var opened = false
    let open: () -> Void = {
        guard !opened else { return }
        opened = true
        origin.perform {
            BrowserStateContext.get(context).open(tab: tab, analyticsContext: origin.context)
        }
    }
    if bot.flags.contains(.showInSettingsDisclaimer) || bot.flags.contains(.notActivated) {
        let options: [ModalAlertData.Option] = [.init(string: strings().webBotAccountDisclaimerThird, isSelected: false, mandatory: true)]
        var description: ModalAlertData.Description?
        let installBot = !bot.flags.contains(.notActivated) && bot.peer._asPeer().botInfo?.flags.contains(.canBeAddedToAttachMenu) == true && !bot.flags.contains(.showInAttachMenu)
        if installBot {
            description = .init(string: strings().webBotAccountDesclaimerDesc(bot.shortName), onlyWhenEnabled: false)
        }
        let data = ModalAlertData(title: strings().webBotAccountDisclaimerTitle, info: strings().webBotAccountDisclaimerText, description: description, ok: strings().webBotAccountDisclaimerOK, options: options)
        let decision = BrowserDecision(origin: origin)
        showModalAlert(for: context.window, data: data, completion: { _ in
            decision.resolve {
                _ = origin.preserving(context.engine.messages.acceptAttachMenuBotDisclaimer(botId: bot.peer.id)).start()
                installAttachMenuBot(context: context, peer: bot.peer._asPeer(), analyticsContext: origin.context, completion: { value in
                    guard value else { return }
                    if installBot {
                        showModalText(for: context.window, text: strings().webAppAttachSuccess(bot.peer._asPeer().displayTitle))
                    }
                    open()
                })
            }
        }, cancel: {
            decision.resolve {}
        }, onDeinit: {
            decision.dismissed()
        })
    } else {
        open()
    }
}

public func openJoinChatBotWebView(context: (any AccountContextProtocol), botId: PeerId, url: String?, queryId: Int64, joinedPeerId: PeerId?) {
    openJoinChatBotWebView(context: context, botId: botId, url: url, queryId: queryId, joinedPeerId: joinedPeerId, analyticsContext: nil)
}

public func openJoinChatBotWebView(context: any AccountContextProtocol, botId: PeerId, url: String?, queryId: Int64, joinedPeerId: PeerId?, analyticsContext: AnalyticsContext?) {
    BrowserStateContext.get(context).openJoinChatWebView(botId: botId, url: url, queryId: queryId, peerId: joinedPeerId, analyticsContext: analyticsContext)
}
