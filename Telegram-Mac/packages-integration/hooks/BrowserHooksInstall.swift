import AppAnalytics
import ChatHistoryModel
import InputDataUI
import PaymentsUI
import StarsUI
import TelegramContext
import TelegramUtils
import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import WebAppUI
import WalletContext

func installBrowserUIHooks() {
    var hooks = BrowserHooks(classifyLink: { context, url in
        guard let context = context as? AccountContext else {
            return .other
        }
        if #available(macOS 10.15, *), WalletContext.isTonConnectUrl(normalizedTelegramLinkQuery(url)) {
            return .tonConnect
        }
        let link = inApp(for: url.nsstring, context: context)
        switch link {
        case .external:
            return .external
        case .shareUrl:
            return .shareUrl
        case let .tonsite(link, _):
            return .tonsite(link)
        case .instantView:
            return .instantView
        default:
            return .other
        }
    }, openLink: { context, url, window, confirm, navigatedAway in
        guard let context = context as? AccountContext else {
            return
        }
        let link = inApp(for: url.nsstring, context: context, openInfo: { peerId, toChat, messageId, initialAction in
            if toChat || initialAction != nil {
                navigateToChat(navigation: context.bindings.rootNavigation(), context: context, chatLocation: .peer(peerId), focusTarget: .init(messageId: messageId), initialAction: initialAction, additional: true, callback: { controller in
                    controller.window?.makeKeyAndOrderFront(nil)
                })
            } else {
                PeerInfoController.push(navigation: context.bindings.rootNavigation(), context: context, peerId: peerId)
                context.window.makeKeyAndOrderFront(nil)
            }
            navigatedAway()
        }, hashtag: nil, command: nil, applyProxy: nil, confirm: confirm)
        execute(inapp: link, window: window)
    }, resolveInstantView: { context, url in
        guard let context = context as? AccountContext else {
            return .single(nil)
        }
        return resolveInstantViewUrl(account: context.account, url: url) |> map { result in
            switch result {
            case let .instantView(_, webPage, _):
                return webPage
            default:
                return nil
            }
        }
    }, shareInlineQuery: { context, inputQuery, chatTypes, peerId, completed in
        guard let context = context as? AccountContext else {
            return
        }
        let action: ChatInitialAction = .inputText(text: .init(inputText: inputQuery), behavior: .automatic)
        if let chatTypes = chatTypes {
            let controller = ShareModalController(SharefilterCallbackObject(context, limits: chatTypes, callback: { peerId, threadId in
                if let threadId = threadId {
                    _ = (ForumUI.openTopic(threadId, peerId: peerId, context: context, animated: true, addition: true, initialAction: action) |> take(1)).start()
                } else {
                    navigateToChat(navigation: context.bindings.rootNavigation(), context: context, chatLocation: .peer(peerId), initialAction: action, additional: true)
                }
                return .complete()
            }))
            showModal(with: controller, for: context.window)
        } else if let peerId = peerId {
            navigateToChat(navigation: context.bindings.rootNavigation(), context: context, chatLocation: .peer(peerId), initialAction: action, additional: true)
        }
        completed()
    }, shareLink: { context, link, window in
        guard let context = context as? AccountContext else {
            return
        }
        showModal(with: ShareModalController(ShareLinkObject(context, link: link)), for: window)
    }, shareViaCallback: { context, window, callback in
        guard let context = context as? AccountContext else {
            return
        }
        showModal(with: ShareModalController(ShareCallbackObject(context, callback: { peerIds in
            callback(peerIds)
            return .complete()
        })), for: window)
    }, openPeerInfo: { context, peerId in
        guard let context = context as? AccountContext else {
            return
        }
        PeerInfoController.push(navigation: context.bindings.rootNavigation(), context: context, peerId: peerId)
    }, openChat: { context, peerId in
        guard let context = context as? AccountContext else {
            return
        }
        navigateToChat(navigation: context.bindings.rootNavigation(), context: context, chatLocation: .peer(peerId))
    }, sharePreparedMessage: { context, bot, preparedMessage, window, completion in
        guard let context = context as? AccountContext else {
            return
        }
        showModal(with: WebbotShareMessageModal(context: context, bot: .init(bot), preparedMessage: preparedMessage, window: window, callback: { status in
            switch status {
            case .success:
                completion(true)
            case .failed:
                completion(false)
            }
        }), for: window)
    }, openPremiumBoarding: { context, window in
        guard let context = context as? AccountContext else {
            return
        }
        prem(with: PremiumBoardingController(context: context), for: window)
    }, openInvoice: { context, invoice, slug, window, completion in
        presentBrowserInvoice(context: context, invoice: invoice, slug: slug, window: window, analyticsContext: Analytics.shared.unresolvedContext(), completion: completion)
    }, showLoginWidget: { context, domain, bot, clientData, flags, matchCodes, userIdHint, oauthUrl, inAppOrigin, completion in
        guard let context = context as? AccountContext else {
            return
        }
        let widgetData = LoginWidgetData(
            domain: domain,
            bot: EnginePeer(bot),
            clientData: clientData,
            flags: flags,
            subject: .url(url: oauthUrl, inAppOrigin: inAppOrigin),
            matchCodes: matchCodes,
            userIdHint: userIdHint
        )
        showLoginWidgetConfirmation(context: context, sharedContext: context.sharedContext, data: widgetData) { result in
            switch result {
            case let .accepted(url):
                completion(.accepted(url: url))
            case .cancelled:
                completion(.cancelled)
            case .failed:
                completion(.failed)
            }
        }
    }, makeRecommendedAppItem: { context, user, afterNameBadge, handler in
        guard let context = context as? AccountContext else {
            return nil
        }
        return ReactionPeerMenu(title: user.displayTitle, handler: handler, peer: user, context: context, reaction: nil, afterNameBadge: afterNameBadge)
    }, makeInstantViewPage: { context, webPage, url, anchor, browser in
        guard let context = context as? AccountContext else {
            preconditionFailure("InstantViewInBrowser requires a concrete AccountContext")
        }
        return InstantViewInBrowser(webPage: webPage, context: context, url: url, anchor: anchor, browser: browser)
    }, showSavedToDownloads: { context, window, layout in
        guard let context = context as? AccountContext else {
            return
        }
        _ = showSaveModal(for: window, context: context, animation: LocalAnimatedSticker.success_saved, shouldBlur: false, text: layout, delay: 3.0).start()
    }, makeStickerView: { frame in
        return MediaAnimatedStickerView(frame: frame)
    }, uploadStory: { context, source, botPeer, text, window in
        guard let context = context as? AccountContext else {
            return
        }
        let signal = Sender.generateMedia(for: .init(path: source), account: context.account, isSecretRelated: false, isUniquelyReferencedTemporaryFile: false) |> deliverOnMainQueue
        _ = signal.startStandalone(next: { media, _ in
            showModal(with: StoryPrivacyModalController(context: context, presentation: theme, reason: .upload(media, .init(botPeer)), text: text), for: window)
        })
    }, selectPeerForWebView: { context, peerType, botPeerId, requestId, buttonId, maxQuantity, window, completion in
        guard let context = context as? AccountContext else {
            return
        }
        selectSpecificPeerForWebView(context: context, peerType: peerType, botPeerId: botPeerId, requestId: requestId, buttonId: buttonId, maxQuantity: maxQuantity, window: window, completion: completion)
    }, makeSharePreviewMessageItem: { initialSize, context, message, heightDidChange in
        let interactions = ChatInteraction(chatLocation: .peer(context.peerId), context: context, isLogInteraction: true)
        let entry = ChatHistoryEntry.MessageEntry(message, .init(message), true, theme.bubbled ? .bubble : .list, .Full(rank: nil, rankType: .none, header: .normal), nil, .init())
        if let widget = message.media.first as? TelegramMediaWidget {
            return ChatHTMLRowItem(initialSize, interactions, context, entry, theme: theme, previewWidget: widget, heightDidChange: heightDidChange)
        }
        return ChatRowItem.item(initialSize, from: entry, interaction: interactions, theme: theme)
    }, makeShareChatContextResultModal: { context, preparedMessage, completion in
        return ShareModalController(ShareChatContextResult(context as! AccountContext, preparedMessage: preparedMessage), completion: completion)
    })
    hooks.makeShareChatContextResultModalWithContext = { context, preparedMessage, analyticsContext, completion in
        return ShareModalController(ShareChatContextResult(context.concrete, preparedMessage: preparedMessage), completion: completion, analyticsContext: analyticsContext)
    }
    hooks.makeShareChatContextResultModalWithResult = { context, preparedMessage, analyticsContext, completion in
        let controller = ShareModalController(ShareChatContextResult(context.concrete, preparedMessage: preparedMessage), analyticsContext: analyticsContext)
        controller.resultCompletion = { result in
            switch result {
            case .accepted: completion(.accepted)
            case .partiallyAccepted: completion(.partiallyAccepted)
            case .rejected: completion(.rejected)
            case .draftPrepared, .destinationReady, .sourceUnavailable, .targetUnavailable, .unknown, .dispatched: completion(.unknown)
            case .cancelled: completion(.cancelled)
            }
        }
        return controller
    }
    hooks.openInvoiceWithContext = { context, invoice, slug, window, analyticsContext, completion in
        presentBrowserInvoice(context: context, invoice: invoice, slug: slug, window: window, analyticsContext: analyticsContext, completion: completion)
    }
    hooks.openChatWithContext = { context, peerId, analyticsContext in
        guard let context = context as? AccountContext else { return }
        navigateToChat(navigation: context.bindings.rootNavigation(), context: context, chatLocation: .peer(peerId), analyticsContext: analyticsContext)
    }
    installBrowserHooks(hooks)
}

extension MediaAnimatedStickerView: @retroactive BrowserStickerView {
    public func updateBrowserSticker(file: TelegramMediaFile, size: NSSize, context: any AccountContextProtocol, tint: NSColor?, animated: Bool) {
        guard let context = context as? AccountContext else {
            return
        }
        if let tint = tint {
            self.update(with: file, size: size, context: context, table: nil, parameters: ChatAnimatedStickerMediaLayoutParameters(playPolicy: .loop, alwaysAccept: true, media: file, colors: [.init(keyPath: "", color: tint)], noThumb: true), animated: animated)
        } else {
            self.update(with: file, size: size, context: context, table: nil, animated: animated)
        }
    }
}

private func presentBrowserInvoice(context: any AccountContextProtocol, invoice: TelegramMediaInvoice, slug: String, window: Window, analyticsContext: AnalyticsContext, completion: @escaping (String) -> Void) {
    let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext)
    let lifetime = origin.beginPresentation()
    let result = Atomic(value: "cancelled")
    let update: (String) -> Void = { status in
        _ = result.modify { current in current == "paid" ? current : status }
    }
    let controller: InputDataModalController
    if invoice.currency == XTR {
        controller = Star_PurschaseInApp(context: context, invoice: invoice, source: .slug(slug), type: invoice.subscriptionPeriod != nil ? .botSubscription(invoice) : .bot, analyticsContext: origin, completion: { update($0.rawValue) })
    } else {
        controller = PaymentsCheckoutController(context: context, source: .slug(slug), invoice: invoice, analyticsContext: origin, completion: { update($0.rawValue) })
    }
    let onDeinit = controller.onDeinit
    controller.onDeinit = {
        let delivery = origin.beginPresentation()
        defer { delivery.end(); lifetime.end() }
        onDeinit?()
        completion(result.with { $0 })
    }
    showModal(with: controller, for: window)
}
