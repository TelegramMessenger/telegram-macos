import Cocoa
import Foundation
import TGUIKit
import TelegramCore
import TGModernGrowingTextView
import Postbox
import SwiftSignalKit
import MtProtoKit
import ThemeSettings
import Translate
import InputView
import TelegramMedia
import InAppSettings
import WalletContext













private let inapp:String = "chat://"



private struct UrlHandlingConfiguration {
    static var defaultValue: UrlHandlingConfiguration {
        return UrlHandlingConfiguration(token: nil, domains: [], urlAuthDomains: [])
    }
    
    public let token: String?
    public let domains: [String]
    public let urlAuthDomains: [String]
    
    fileprivate init(token: String?, domains: [String], urlAuthDomains: [String]) {
        self.token = token
        self.domains = domains
        self.urlAuthDomains = urlAuthDomains
    }
    
    static func with(appConfiguration: AppConfiguration) -> UrlHandlingConfiguration {
        if let data = appConfiguration.data {
            let urlAuthDomains = data["url_auth_domains"] as? [String] ?? []
            if let token = data["autologin_token"] as? String, let domains = data["autologin_domains"] as? [String] {
                return UrlHandlingConfiguration(token: token, domains: domains, urlAuthDomains: urlAuthDomains)
            }
        }
        return .defaultValue
    }
}

private let cachedUrlHandlingPair = Atomic<(config: AppConfiguration, result: UrlHandlingConfiguration)?>(value: nil)

@inline(__always)
private func urlHandlingConfiguration(for appConfiguration: AppConfiguration) -> UrlHandlingConfiguration {
    if let cached = cachedUrlHandlingPair.with({ $0 }), cached.config == appConfiguration {
        return cached.result
    }
    let result = UrlHandlingConfiguration.with(appConfiguration: appConfiguration)
    _ = cachedUrlHandlingPair.swap((appConfiguration, result))
    return result
}




func resolveUsername(username: String, context: AccountContext) -> Signal<Peer?, NoError> {
    if username.hasPrefix(privateTelegramPeerPrefix), let range = username.range(of: privateTelegramPeerPrefix) {
        if let channelId = Int64(username[range.upperBound...]), let id = PeerId._optionalInternalFromInt64Value(channelId) {
            let peerId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: id)
            
            let peerSignal: Signal<Peer?, NoError> = context.account.postbox.transaction { transaction -> Peer? in
                return transaction.getPeer(peerId)
                } |> mapToSignal { peer in
                    if let peer = peer {
                        return .single(peer)
                    } else {
                        return context.engine.peers.findChannelById(channelId: peerId.id._internalGetInt64Value()) |> map { $0?._asPeer() }
                    }
            }
            
            return peerSignal |> deliverOnMainQueue |> map { peer in
                if let peer = peer {
                    if let peer = peer as? TelegramChannel {
                        if peer.participationStatus != .member {
                            return nil
                        }
                    }
                }
                return peer
            }
        } else {
            return .single(nil)
        }
    } else {
        return context.engine.peers.resolvePeerByName(name: username, referrer: nil) |> filter { $0 != .progress } |> mapToSignal { result -> Signal<Peer?, NoError> in
            return .single(result.result?._asPeer())
        } |> deliverOnMainQueue
    }
    
}




var globalLinkExecutor:TextViewInteractions {
    get {
        return TextViewInteractions(processURL:{(link) in
            if let link = link as? inAppLink {
                switch link {
                case .requestSecureId:
                    break // never execute from inapp
                default:
                    execute(inapp:link)
                }
            }
        }, isDomainLink: { value, origin in
            if let value = value as? inAppLink {
                switch value {
                case .external:
                    return true
                default:
                    if let origin = origin {
                        if origin != value.link, !origin.isEmpty && origin != "‌" {
                            return true
                        }
                    }
                    return false
                }
            }
            return false
        }, makeLinkType: { link, url in
            if let link = link as? inAppLink {
                switch link {
                case .botCommand:
                    return .command
                case .hashtag:
                    return .hashtag
                case .code:
                    return .code
                case .followResolvedName:
                    if url.hasPrefix("@") {
                        return .username
                    } else {
                        return .plain
                    }
                case let .external(link, _):
                    if isValidEmail(link) {
                        return .email
                    } else if telegram_me.first(where: {link.contains($0 + "joinchat/")}) != nil {
                        return .inviteLink
                    } else {
                        return .plain
                    }
                case let .stickerPack(_, source, _, _):
                    switch source {
                    case .emoji:
                        return .emojiPack
                    case .stickers:
                        return .stickerPack
                    }
                case .joinchat:
                    return .inviteLink
                default:
                    return .plain
                }
            }
            return .plain
        }, localizeLinkCopy: { type in
            return copyContextText(from: type)
        }, resolveLink: { link in
            return (link as? inAppLink)?.link
        }, copyAttributedString: { string in
            let pb = NSPasteboard.general

 
            let modified: NSMutableAttributedString = string.mutableCopy() as! NSMutableAttributedString
            
            var replaceRanges:[(NSRange, String)] = []
            
            string.enumerateAttributes(in: string.range, options: [.reverse], using: { attr, range, _ in
                if let appLink = attr[NSAttributedString.Key.link] as? inAppLink {
                    switch appLink {
                    case .code, .hashtag, .callback:
                        break
                    default:
                        if appLink.link != modified.string.nsstring.substring(with: range) {
                            modified.addAttribute(TextInputAttributes.textUrl, value: TextInputTextUrlAttribute(url: appLink.link), range: range)
                        }
                    }
                }
                if let sticker = attr[TextInputAttributes.embedded] as? InlineStickerItem {
                    if case let .attribute(emoji) = sticker.source {
                        modified.addAttribute(TextInputAttributes.customEmoji, value: TextInputTextCustomEmojiAttribute(fileId: emoji.fileId, file: emoji.file, emoji: emoji.emoji), range: range)
                        replaceRanges.append((range, emoji.emoji))
                    }
                }
            })
            
            for range in replaceRanges.sorted(by: { $0.0.lowerBound > $1.0.lowerBound }) {
                modified.replaceCharacters(in: range.0, with: range.1)
            }
            
            //modified.removeAttribute(TextInputAttributes.quote, range: modified.range)
            modified.removeAttribute(TextInputAttributes.code, range: modified.range)
            modified.removeAttribute(TextInputAttributes.monospace, range: modified.range)

            let input = ChatTextInputState(attributedText: modified, selectionRange: 0 ..< modified.length)
            
            if !modified.string.isEmpty {
                pb.clearContents()
                let rtf = try? modified.data(from: modified.range, documentAttributes: [NSAttributedString.DocumentAttributeKey.documentType : NSAttributedString.DocumentType.rtf])
                
                
                pb.declareTypes([.rtf, .kInApp], owner: nil)

                let encoder = AdaptedPostboxEncoder()
                let encoded = try? encoder.encode(input)
                
                if let data = encoded {
                    pb.setData(data, forType: .kInApp)
                }
                if let rtf = rtf {
                    pb.setData(rtf, forType: .rtf)
                    pb.setString(modified.string, forType: .string)
                    return true
                }
            }
            
            return false
        }, translate: { text, window in
            let language = Translate.detectLanguage(for: text)
            let toLang = appAppearance.languageCode
            var current: AccountContext?
            appDelegate?.enumerateAccountContexts({ context in
                if context.window === window {
                    current = context
                }
            })
            
            if language != toLang, let context = current {
                return ContextMenuItem(strings().chatContextTranslate, handler: {
                    showModal(with: TranslateModalController(context: context, from: language, toLang: toLang, text: text), for: context.window)
                }, itemImage: MenuAnimation.menu_translate.value)
            } else {
                return nil
            }
        }, longHoverOnLink: { link, view in
            guard let link = link as? inAppLink else { return nil }
            guard let context = appDelegate?.activeContext(for: nil) else { return nil }
            guard let event = NSApp.currentEvent else { return nil }

            switch link {
            case let .followResolvedName(_, username, _, _, _, _, _):
                return (context.engine.peers.resolvePeerByName(name: username, referrer: nil) |> deliverOnMainQueue).start(next: { result in
                    switch result {
                    case let .result(peer):
                        guard let peer = peer else { return }
                        let p = peer._asPeer()
                        let menu = ContextMenu()

                        var title: String = p.displayTitle
                        if let address = p.addressName, !address.isEmpty {
                            title += " (@\(address))"
                        }

                        view.removeAllToolTips()

                        let nameItem = ContextMenuItem(title, handler: {
                            execute(inapp: link)
                        }, image: NSImage(resource: .menuAtsign), removeTail: false)
                        ContextMenuItem.makeItemAvatar(nameItem, account: context.account, peer: p, source: .peer(p, p.smallProfileImage, p.namePeerColor, p.displayLetters, nil, nil))
                        menu.addItem(nameItem)

                        let mouseLocation = view.window?.mouseLocationOutsideOfEventStream ?? .zero
                        let localPoint = view.convert(mouseLocation, from: nil)
                        if !contextMenuOnScreen(), view.window?.isKeyWindow == true, view.bounds.contains(localPoint) {
                            let appMenu = AppMenu(menu: menu)
                            appMenu.show(event: event, view: view)
                        }
                    case .progress:
                        break
                    }
                })
            case let .joinchat(_, hash, _, _):
                return (context.engine.peers.joinLinkInformation(hash) |> deliverOnMainQueue).start(next: { result in
                    let menu = ContextMenu()
                    view.removeAllToolTips()

                    switch result {
                    case let .alreadyJoined(peer):
                        let p = peer._asPeer()
                        var title: String = p.displayTitle
                        if let address = p.addressName, !address.isEmpty {
                            title += " (@\(address))"
                        }
                        let nameItem = ContextMenuItem(title, handler: {
                            execute(inapp: link)
                        }, image: NSImage(resource: .menuAtsign), removeTail: false)
                        ContextMenuItem.makeItemAvatar(nameItem, account: context.account, peer: p, source: .peer(p, p.smallProfileImage, p.namePeerColor, p.displayLetters, nil, nil))
                        menu.addItem(nameItem)
                    case let .invite(invite):
                        let nameItem = ContextMenuItem(invite.title, handler: {
                            execute(inapp: link)
                        }, image: NSImage(resource: .menuAtsign), removeTail: false)
                        let letters = invite.title.prefix(2).map { String($0) }
                        let colors = theme.colors.peerColors(0)
                        let signal = generateEmptyPhoto(NSMakeSize(18, 18), type: .peer(colors: colors, letter: letters, font: .avatar(13), cornerRadius: nil), bubble: false) |> deliverOnMainQueue
                        nameItem.contextObject = signal.start(next: { [weak nameItem] image in
                            if let image = image {
                                nameItem?.image = NSImage(cgImage: image, size: NSMakeSize(18, 18))
                            }
                        })
                        menu.addItem(nameItem)
                    case let .peek(peer, _):
                        let p = peer._asPeer()
                        var title: String = p.displayTitle
                        if let address = p.addressName, !address.isEmpty {
                            title += " (@\(address))"
                        }
                        let nameItem = ContextMenuItem(title, handler: {
                            execute(inapp: link)
                        }, image: NSImage(resource: .menuAtsign), removeTail: false)
                        ContextMenuItem.makeItemAvatar(nameItem, account: context.account, peer: p, source: .peer(p, p.smallProfileImage, p.namePeerColor, p.displayLetters, nil, nil))
                        menu.addItem(nameItem)
                    case .invalidHash:
                        return
                    }
                    let mouseLocation = view.window?.mouseLocationOutsideOfEventStream ?? .zero
                    let localPoint = view.convert(mouseLocation, from: nil)
                    if !contextMenuOnScreen(), view.window?.isKeyWindow == true, view.bounds.contains(localPoint) {
                        let appMenu = AppMenu(menu: menu)
                        appMenu.show(event: event, view: view)
                    }
                })
            default:
                return nil
            }
        })
    }
}

func copyContextText(from type: LinkType) -> String {
    switch type {
    case .username:
        return strings().textContextCopyUsername
    case .command:
        return strings().textContextCopyCommand
    case .hashtag:
        return strings().textContextCopyHashtag
    case .email:
        return strings().textContextCopyEmail
    case .plain:
        return strings().textContextCopyLink
    case .inviteLink:
        return strings().textContextCopyInviteLink
    case .stickerPack:
        return strings().textContextCopyStickerPack
    case .emojiPack:
        return strings().textContextCopyEmojiPack
    case .code:
        return strings().textContextCopyCode
    }
}

private func pushSelectivePrivacySettings(context: AccountContext, kind: SelectivePrivacySettingsKind, navigation: MajorNavigationController) {
    let privacySignal = context.engine.privacy.requestAccountPrivacySettings()
    let callsSignal: Signal<(VoiceCallSettings, VoipConfiguration)?, NoError>
    if case .voiceCalls = kind {
        callsSignal = combineLatest(context.sharedContext.accountManager.sharedData(keys: [ApplicationSharedPreferencesKeys.voiceCallSettings]), context.account.postbox.preferencesView(keys: [PreferencesKeys.voipConfiguration]))
            |> take(1)
            |> map { sharedData, view -> (VoiceCallSettings, VoipConfiguration)? in
                let voiceCallSettings: VoiceCallSettings = sharedData.entries[ApplicationSharedPreferencesKeys.voiceCallSettings]?.get(VoiceCallSettings.self) ?? .defaultSettings
                let voipConfiguration = view.values[PreferencesKeys.voipConfiguration]?.get(VoipConfiguration.self) ?? .defaultValue
                return (voiceCallSettings, voipConfiguration)
            }
    } else {
        callsSignal = .single(nil)
    }

    _ = (combineLatest(privacySignal, callsSignal)
        |> deliverOnMainQueue).start(next: { info, callSettings in
            let current: SelectivePrivacySettings
            switch kind {
            case .presence:
                current = info.presence
            case .groupInvitations:
                current = info.groupInvitations
            case .voiceCalls:
                current = info.voiceCalls
            case .profilePhoto:
                current = info.profilePhoto
            case .forwards:
                current = info.forwards
            case .phoneNumber:
                current = info.phoneNumber
            case .voiceMessages:
                current = info.voiceMessages
            case .bio:
                current = info.bio
            case .birthday:
                current = info.birthday
            case .gifts:
                current = info.giftsAutoSave
            case .savedMusic:
                current = info.savedMusic
            }

            navigation.push(SelectivePrivacySettingsController(context, kind: kind, current: current, callSettings: kind == .voiceCalls ? info.voiceCallsP2P : nil, phoneDiscoveryEnabled: nil, updated: { updated, updatedCallSettings, _, _ in }))
        })
}

private func detectIDNHomograph(_ host: String) -> (isHomograph: Bool, asciiHost: String?) {

    let asciiHost = (host as NSString).addingPercentEncoding(withAllowedCharacters: .urlHostAllowed)
        .flatMap { URL(string: "http://\($0)")?.host }

    if let asciiHost = asciiHost, asciiHost.lowercased().hasPrefix("xn--") || asciiHost.contains("xn--") {
        return (true, asciiHost)
    }

    return (false, asciiHost ?? host)
}


private func openNoPaidMessagesPeer(_ peer: EnginePeer, token: String, context: AccountContext, window: Window, callback: @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) {
    guard case let .user(user) = peer, user.botInfo == nil, peer.id != context.peerId else {
        let raw = peer._asPeer()
        callback(peer.id, raw.isChannel || raw.isSupergroup || raw.isBot, nil, nil)
        return
    }
    let importSignal = context.engine.peers.importNoPaidMessagesToken(peerId: peer.id, token: token)
    |> map(Optional.init)
    |> `catch` { error -> Signal<EnginePeer?, ImportNoPaidMessagesTokenError> in
        if case .invalidToken = error {
            return .single(nil)
        }
        return .fail(error)
    }
    let _ = showModalProgress(signal: importSignal |> deliverOnMainQueue, for: window).start(next: { updatedPeer in
        let title = (updatedPeer ?? peer)._asPeer().compactDisplayTitle
        callback(peer.id, true, nil, nil)
        if updatedPeer != nil {
            showModalText(for: window, text: strings().inAppLinksFreeMessageLinkApplied(title))
        } else {
            showModalText(for: window, text: strings().inAppLinksFreeMessageLinkInvalid)
        }
    }, error: { _ in
        callback(peer.id, true, nil, nil)
        alert(for: window, info: strings().unknownError)
    })
}


private func openResolvedLinkPeer(_ peer: Peer, messageId: MessageId?, action: ChatInitialAction?, forceProfile: Bool, context: AccountContext, window: Window, callback: @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) {
    do {
        if peer.isForum {
            closeAllModals(window: window)
            if let messageId {
                let signal = context.engine.messages.getMessagesLoadIfNecessary([messageId])
                |> filter { result in
                    if case .result = result { return true }
                    return false
                }
                |> take(1)
                |> deliverOnMainQueue
                _ = (signal).start(next: { result in
                    if case let .result(messages) = result, let threadId = messages.first?.threadId {
                        let focusMessageId = threadId == Int64(messageId.id) ? nil : messageId
                        let ready = ForumUI.openTopic(threadId, peerId: peer.id, context: context, messageId: focusMessageId, animated: true, addition: true)
                        _ = (ready |> take(1)).start(next: { opened in
                            if !opened {
                                ForumUI.open(peer.id, addition: true, context: context)
                            }
                        })
                    }
                })
            } else {
                ForumUI.open(peer.id, addition: true, context: context)
            }
        } else {
            let openChat: Bool
            if case .inputText = action {
                openChat = true
            } else {
                openChat = false
            }
            var peerId = peer.id
            if case .direct = action, let linkedMonoforumId = (peer as? TelegramChannel)?.linkedMonoforumId {
                peerId = linkedMonoforumId
            }
            do {
                callback(peerId, (peer.isChannel || peer.isSupergroup || peer.isBot || openChat) && !forceProfile, messageId, forceProfile ? nil : action)
            }
        }
    }
}

private func openResolvedCommentLink(_ result: ThreadInfo, peer: Peer, threadId: Int32, commentId: Int32?, context: AccountContext) {
    do {
        let threadMessageId = MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: threadId)
        let navigation = context.bindings.rootNavigation()
        let current = navigation.controller as? ChatController
        var commentMessageId: MessageId?
        if let commentId {
            commentMessageId = MessageId(peerId: result.message.peerId, namespace: Namespaces.Message.Cloud, id: commentId)
        }
        if let current, current.chatLocation.peerId == result.message.peerId, current.chatLocation.threadId == result.message.threadId {
            if let commentMessageId {
                current.chatInteraction.focusMessageId(nil, .init(messageId: commentMessageId, string: nil), .CenterEmpty)
            }
        } else {
            let mode: ReplyThreadMode
            if peer.isChannel {
                mode = .comments(origin: threadMessageId)
            } else if peer.isForum {
                mode = .topic(origin: threadMessageId)
            } else {
                mode = .replies(origin: threadMessageId)
            }
            let controller = ChatAdditionController(context: context, chatLocation: .thread(result.message), mode: .thread(mode: mode), focusTarget: .init(messageId: commentMessageId), initialAction: nil, chatLocationContextHolder: result.contextHolder)
            navigation.push(controller)
        }
    }
}

private func openResolvedTopicLink(_ peer: Peer, threadId: Int32, commentId: Int32?, context: AccountContext) {
    do {
        var messageId: MessageId?
        if let commentId {
            messageId = MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: commentId)
        }
        let ready = ForumUI.openTopic(Int64(threadId), peerId: peer.id, context: context, messageId: messageId, animated: true, addition: true)
        _ = (ready |> take(1)).start()
    }
}

private func executeAttachBotLink(_ bot: Peer, botname: String, choose: [String]?, action: ChatInitialAction, messageId: MessageId?, context: AccountContext, window: Window, callback: @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) {
    let openTarget: (Peer) -> Void = { peer in
        do {
            callback(peer.id, true, messageId?.peerId == peer.id ? messageId : nil, action)
        }
    }
    let categories = ["users", "groups", "channels", "bots"]
    if let choose, choose.count == 1, !categories.contains(choose[0]) {
        let signal = context.engine.peers.resolvePeerByName(name: choose[0], referrer: nil)
        |> filter { $0 != .progress }
        |> take(1)
        |> deliverOnMainQueue
        _ = (signal).start(next: { peer in
            if let peer = peer.result { openTarget(peer._asPeer()) }
        })
    } else if let choose, !choose.isEmpty {
        var settings: SelectPeerSettings = .init()
        if choose.contains("users") {
            settings.insert(.contacts)
            settings.insert(.remote)
        }
        if choose.contains("bots") { settings.insert(.bots) }
        if choose.contains("groups") { settings.insert(.groups) }
        if choose.contains("channels") { settings.insert(.channels) }
        let selection = selectModalPeers(window: window, context: context, title: strings().selectPeersTitleSelectChat, limit: 1, behavior: SelectChatsBehavior(settings: settings, excludePeerIds: [], limit: 1))
        _ = (selection |> take(1)).start(next: { peerIds in
            guard let peerId = peerIds.first else { return }
            do {
                let signal = context.account.postbox.loadedPeerWithId(peerId) |> take(1) |> deliverOnMainQueue
                _ = (signal).start(next: { peer in
                    guard peer.id == peerId else { return }
                    openTarget(peer)
                })
            }
        })
    } else {
        let navigation = context.bindings.rootNavigation()
        let initialController = navigation.controller
        let hadController = initialController != nil
        let initialChat = initialController as? ChatController
        let location = initialChat?.chatLocation
        let deliver: (Bool) -> Void = { [weak initialController] forceBotChat in
            if hadController {
                guard let initialController, navigation.controller === initialController else { return }
            } else {
                guard navigation.controller == nil else { return }
            }
            do {
                if let chat = initialController as? ChatController, !forceBotChat {
                    guard chat.chatLocation == location else { return }
                    chat.chatInteraction.invokeInitialAction(action: action)
                } else {
                    openTarget(bot)
                }
            }
        }
        do {
            let signal = context.engine.messages.getAttachMenuBot(botId: bot.id) |> take(1)
            _ = (showModalProgress(signal: signal, for: window)).start(next: { _ in
                deliver(false)
            }, error: { _ in
                deliver(bot.username != botname)
            })
        }
    }
}

private func executeWebAppLink(_ bot: Peer, appname: String, command: String?, messageId: MessageId?, context: AccountContext, window: Window, callback: @escaping (Peer, MessageId?, ChatInitialAction?) -> Void) {
    if appname.isEmpty {
        do {
            BrowserStateContext.get(context).open(tab: .mainapp(bot: .init(bot), source: .inline(startParam: command ?? "")))
        }
        return
    }

    let navigation = context.bindings.rootNavigation()
    let initialChat = navigation.first { $0 is ChatController } as? ChatController
    let location = initialChat?.chatLocation
    let hadChat = initialChat != nil
    let peerId = location?.peerId ?? bot.id
    let isCurrent: () -> Bool = { [weak initialChat] in
        let current = navigation.first { $0 is ChatController } as? ChatController
        if hadChat {
            guard let initialChat, current === initialChat else { return false }
            return initialChat.chatLocation == location
        }
        return current == nil
    }
    var finished = false
    let fallback: (MessageId?) -> Void = { messageId in
        guard !finished else { return }
        finished = true
        guard isCurrent() else { return }
        callback(bot, messageId, nil)
    }
    let open: (BotApp, RequestWebViewResult) -> Void = { [weak initialChat] botApp, result in
        guard !finished else { return }
        finished = true
        guard isCurrent() else { return }
        do {
            if let initialChat {
                initialChat.chatInteraction.invokeInitialAction(action: .openWebview(botPeer: .init(bot), botApp: botApp, result: result))
            } else {
                BrowserStateContext.get(context).open(tab: .straight(bot: .init(bot), peerId: peerId, title: botApp.title, result: result))
            }
        }
    }
    let request: (BotApp, Bool) -> Void = { botApp, allowWrite in
        guard !finished, isCurrent() else { return }
        do {
            let signal = context.engine.messages.requestAppWebView(peerId: peerId, appReference: .id(id: botApp.id, accessHash: botApp.accessHash), payload: command, themeParams: generateWebAppThemeParams(theme), compact: false, fullscreen: false, allowWrite: allowWrite) |> take(1) |> deliverOnMainQueue
            _ = (showModalProgress(signal: signal, for: window)).start(next: { result in
                open(botApp, result)
            }, error: { _ in
                fallback(messageId)
            })
        }
    }
    do {
        let signal = context.engine.messages.getBotApp(botId: bot.id, shortName: appname) |> take(1) |> deliverOnMainQueue
        _ = (showModalProgress(signal: signal, for: window)).start(next: { botApp in
            guard !finished, isCurrent() else { return }
            if !botApp.flags.contains(.notActivated) {
                request(botApp, false)
                return
            }
            let decision = InAppLinkDecision()
            var options: [ModalAlertData.Option] = []
            if botApp.flags.contains(.requiresWriteAccess) {
                options.append(.init(string: strings().botAllowSendMessages(bot.displayTitle), isSelected: true, mandatory: true))
            }
            let data = ModalAlertData(title: nil, info: strings().webAppFirstOpenTerms(strings().botInfoLaunchInfoPrivacyUrl), description: nil, ok: strings().botLaunchApp, options: options, mode: .confirm(text: strings().modalCancel, isThird: false), header: .init(id: "header", value: { initialSize, stableId, presentation in
                return AlertHeaderItem(initialSize, stableId: stableId, presentation: presentation, context: context, peer: .init(bot), info: strings().botMoreAbout, callback: { _ in
                    decision.resolve {
                        guard !finished, isCurrent() else { return }
                        fallback(nil)
                        closeAllModals(window: window)
                    }
                })
            }))
            showModalAlert(for: window, data: data, completion: { result in
                decision.resolve {
                    guard !finished, isCurrent() else { return }
                    FastSettings.markWebAppAsConfirmed(bot.id)
                    request(botApp, result.selected[0] ?? false)
                }
            }, cancel: {
                decision.resolve { finished = true }
            }, onDeinit: {
                decision.dismissed()
            })
        }, error: { _ in
            fallback(messageId)
        })
    }
}

private final class InAppLinkDecision {
    private var resolved = false
    private var dismissalScheduled = false


    func resolve(_ action: () -> Void) {
        guard !resolved else { return }
        resolved = true
        action()
    }

    func dismissed() {
        guard !dismissalScheduled else { return }
        dismissalScheduled = true
        DispatchQueue.main.async {
            self.resolved = true
        }
    }
}

private func confirmExternalLink(window: Window, information: String, success: @escaping () -> Void, cancel: @escaping () -> Void) {
    let decision = InAppLinkDecision()
    do {
        verifyAlert_button(for: window, header: strings().inAppLinksConfirmOpenExternalHeader, information: information, ok: strings().inAppLinksConfirmOpenExternalOK, successHandler: { _ in
            decision.resolve(success)
        }, cancelHandler: {
            decision.resolve(cancel)
        }, onDeinit: {
            decision.dismissed()
        })
    }
}

private func executeInviteLink(hash: String, context: AccountContext, window: Window, interaction: @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) {
    let openPeer: (Peer, ChatInitialAction?) -> Void = { peer, action in
        do {
            if peer.isForum {
                ForumUI.open(peer.id, addition: true, context: context)
            } else {
                interaction(peer.id, true, nil, action)
            }
        }
    }
    do {
        let signal = context.engine.peers.joinLinkInformation(hash) |> take(1) |> deliverOnMainQueue
        _ = (showModalProgress(signal: signal, for: window)).start(next: { result in
            switch result {
            case let .alreadyJoined(peer):
                openPeer(peer._asPeer(), nil)
            case let .invite(state):
                if state.flags.canRefulfillSubscription {
                    let signal = context.engine.peers.joinChatInteractively(with: hash) |> take(1) |> deliverOnMainQueue
                    _ = (showModalProgress(signal: signal, for: window)).start(next: { outcome in
                        switch outcome {
                        case let .joined(peer):
                            if let peer { openPeer(peer._asPeer(), nil) }
                        case let .webView(webView):
                            openJoinChatBotWebView(context: context, botId: webView.botPeer.id, url: webView.url, queryId: webView.queryId, joinedPeerId: webView.peerId)
                        }
                    }, error: { error in
                        switch error {
                        case .tooMuchJoined:
                            FeatureNavigationHooks.shared.showInactiveChannelsObserved(context, .join)
                        case .requestSent:
                            showModalText(for: window, text: strings().requestJoinSent)
                        case .tooMuchUsers:
                            showModalText(for: window, text: strings().groupUsersTooMuchError)
                        case .flood:
                            showModalText(for: window, text: strings().joinLinkFloodError)
                        case .generic:
                            showModalText(for: window, text: strings().unknownError)
                        }
                    })
                } else if state.subscriptionPricing != nil {
                    let paid = Atomic(value: false)
                    let controller = Star_PurschaseInApp(context: context, invoice: nil, source: .starsChatSubscription(hash: hash), type: .subscription(state), completion: { status in
                        do {
                            guard case let .paid(_, peerId) = status, !paid.swap(true) else { return }
                            guard let peerId else { return }
                            delay(1.0, closure: {
                                interaction(peerId, true, nil, nil)
                            })
                        }
                    })
                    showModal(with: controller, for: window)
                } else if state.flags.requestNeeded {
                    let controller = RequestJoinChatModalController(context: context, joinhash: hash, invite: result, interaction: { peer in
                        openPeer(peer, nil)
                    })
                    showModal(with: controller, for: window)
                } else {
                    let controller = JoinLinkPreviewModalController(context, hash: hash, join: result, interaction: { peer in
                        openPeer(peer, nil)
                    })
                    showModal(with: controller, for: window)
                }
            case let .peek(peer, peek):
                openPeer(peer._asPeer(), .closeAfter(peek))
            case .invalidHash:
                showModalText(for: window, text: strings().linkExpired)
            }
        }, error: { error in
            switch error {
            case .generic:
                showModalText(for: window, text: strings().unknownError)
            case .flood:
                showModalText(for: window, text: strings().joinLinkFloodError)
            }
        })
    }
}


private func executeInvoiceLink(slug: String, context: AccountContext, window: Window) {
    do {
        let signal = showModalProgress(signal: context.engine.payments.fetchBotPaymentInvoice(source: .slug(slug)) |> take(1) |> deliverOnMainQueue, for: window)
        _ = (signal).start(next: { invoice in
            if invoice.currency == XTR {
                showModal(with: Star_PurschaseInApp(context: context, invoice: invoice, source: .slug(slug), type: invoice.subscriptionPeriod != nil ? .botSubscription(invoice) : .bot), for: window)
            } else {
                showModal(with: PaymentsCheckoutController(context: context, source: .slug(slug), invoice: invoice), for: window)
            }
        }, error: { error in
            let text: String
            switch error {
            case .alreadyActive:
                text = strings().paymentsInvoiceAlreadyActive
            case .generic:
                text = strings().paymentsInvoiceNotExists
            case .noPaymentNeeded, .starGiftResellTooEarly:
                text = strings().unknownError
            case .disallowedStarGift:
                text = strings().giftSendDisallowError
            case .starGiftUserLimit:
                text = strings().giftOptionsGiftBuyLimitReached
            }
            showModalText(for: window, text: text)
        })
    }
}


private func notificationCategoryEntryTag(_ section: InAppSettingsSection.NotificationsSubSection.ChatNotificationSubSection) -> NotificationCategoryEntryTag? {
    switch section {
    case .edit:
        return nil
    case .show:
        return .show
    case .preview:
        return .preview
    case .sound:
        return .sound
    case .add_exception:
        return .addException
    case .delete_exceptions:
        return .deleteExceptions
    }
}

func execute(inapp:inAppLink, window: Window? = nil, isExternal: Bool = false, afterComplete: @escaping(Bool)->Void = { _ in }) {

    let getWindow:(AccountContext)->Window = { context in
        return window ?? context.window
    }
    

    switch inapp {
    case let .external(link, needConfirm):
        
        if link.isEmpty {
            return
        }
        var url:String = link.trimmed

        var reversedUrl = String(url.reversed())
        while reversedUrl.components(separatedBy: "#").count > 2 {
            if let index = reversedUrl.range(of: "#") {
                reversedUrl.replaceSubrange(index, with: "32%")
            }
        }
        url = String(reversedUrl.reversed())
        if isValidEmail(url) {
            if !url.hasPrefix("mailto:") {
                url = "mailto:" + url
            }
        } else if !url.hasPrefix("http") && !url.hasPrefix("ftp") {
            if let range = url.range(of: "://") {
                if url.length > 10, range.lowerBound > url.index(url.startIndex, offsetBy: 10) {
                    url = "http://" + url
                }
            } else if !url.hasPrefix("mailto:") {
                url = "http://" + url
            }
        }
        
        let urlValue = url


        let escaped = escape(with:url)
        if let urlQueryAllowed = Optional(escaped) {
            if let url = URL(string: urlQueryAllowed) ?? URL(string: urlValue) {
                var needConfirm = needConfirm || url.host != URL(string: urlValue)?.host

                var idnWarning: String? = nil
                if let host = url.host {
                    let (isHomograph, asciiHost) = detectIDNHomograph(host)
                    if isHomograph {
                        needConfirm = true
                        if let asciiHost = asciiHost, asciiHost != host {
                            idnWarning = strings().inAppLinksIDNWarning(host, asciiHost)
                        }
                    }
                }

                if needConfirm {
                    let allowed = appDelegate?.allowedDomains ?? []
                    if let url = URL(string: urlValue) {
                        if let host = url.host, allowed.contains(host) {
                            needConfirm = false
                            idnWarning = nil
                        }
                    }
                }

                if let withToken = appDelegate?.tryApplyAutologinToken(url.absoluteString), let url = URL(string: withToken) {
                    NSWorkspace.shared.open(url)
                    afterComplete(true)
                    return
                }

                let removePecentEncoding = url.host == URL(string: urlValue)?.host
                let success:()->Void = {

                    var path = url.absoluteString
                    let supportSchemes:[String] = ["itunes.apple.com"]
                    for scheme in supportSchemes {
                        var url:URL? = nil
                        if path.contains(scheme) {
                            switch scheme {
                            case supportSchemes[0]: // itunes
                               path = "itms://" + path.nsstring.substring(from: path.nsstring.range(of: scheme).location)
                               url = URL(string: path)
                            default:
                                continue
                            }
                        }
                        if let url = url {
                            NSWorkspace.shared.open(url)
                            afterComplete(true)
                            return
                        }
                    }
                    afterComplete(true)
                    NSWorkspace.shared.open(url)
                }
                if needConfirm {
                    let displayUrl = removePecentEncoding ? (url.absoluteString.removingPercentEncoding ?? url.absoluteString) : escaped
                    var information = strings().inAppLinksConfirmOpenExternalNew(displayUrl)
                    if let idnWarning = idnWarning {
                        information += "\n\n" + idnWarning
                    }
                    confirmExternalLink(window: mainWindow, information: information, success: success, cancel: { afterComplete(false) })
                } else {
                    success()
                }
            }

        }
    case let .peerInfo(_, peerId, action, openChat, postId, callback):
        let messageId:MessageId?
        if let postId = postId {
            messageId = MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: MessageId.Id(postId))
        } else {
            messageId = nil
        }
        callback(peerId, openChat, messageId, action)
        afterComplete(true)
    case let .comments(_, username, context, threadId, commentId):
        

        enum Error {
            case doesntExists
            case privateAccess
            case generic
        }
        
        var peerSignal: Signal<Peer, Error> = .fail(.doesntExists)
        if username.hasPrefix(privateTelegramPeerPrefix), let range = username.range(of: privateTelegramPeerPrefix) {
            if let channelId = Int64(username[range.upperBound...]), let id = PeerId._optionalInternalFromInt64Value(channelId) {
                let peerId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: id)
                peerSignal = context.account.postbox.transaction { transaction -> Peer? in
                    return transaction.getPeer(peerId)
                } |> mapToSignalPromotingError { peer in
                    if let peer = peer {
                        return .single(peer)
                    } else {
                        return context.engine.peers.findChannelById(channelId: peerId.id._internalGetInt64Value())
                            |> mapToSignalPromotingError { value in
                                if let value = value {
                                    return .single(value._asPeer())
                                } else {
                                    return .fail(.privateAccess)
                                }
                            }
                        
                    }
                }
            }
        } else {
            peerSignal = context.engine.peers.resolvePeerByName(name: username, referrer: nil) |> filter { $0 != .progress } |> mapToSignalPromotingError { result -> Signal<Peer, Error> in
                if let result = result.result {
                    return .single(result._asPeer())
                } else {
                    return .fail(.doesntExists)
                }
            } |> mapError { _ in
                return .doesntExists
            }
        }
        
        let signal:Signal<(ThreadInfo, Peer), Error> = (peerSignal |> take(1)) |> mapToSignal { peer in
            let messageId: MessageId = MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: threadId)
            return fetchAndPreloadReplyThreadInfo(context: context, subject: peer.isChannel ? .channelPost(messageId) : .groupMessage(messageId))
                |> map {
                    return ($0, peer)
                } |> mapError { error in
                    switch error {
                    case .generic:
                        return .generic
                    }
            }
        } |> deliverOnMainQueue

        
        _ = (showModalProgress(signal: signal |> take(1), for: getWindow(context))).start(next: { values in
            let (result, peer) = values
            openResolvedCommentLink(result, peer: peer, threadId: threadId, commentId: commentId, context: context)
        }, error: { error in
            switch error {
            case .doesntExists:
                showModalText(for: getWindow(context), text: strings().alertUserDoesntExists)
            case .privateAccess:
                showModalText(for: getWindow(context), text: strings().alertPrivateChannelAccessError)
            case .generic:
                break
            }
        })
        
        afterComplete(true)
    case let .topic(_, username, context, threadId, commentId):
        

        enum Error {
            case doesntExists
            case privateAccess
            case generic
        }
        
        var peerSignal: Signal<Peer, Error> = .fail(.doesntExists)
        if username.hasPrefix(privateTelegramPeerPrefix), let range = username.range(of: privateTelegramPeerPrefix) {
            if let channelId = Int64(username[range.upperBound...]), let id = PeerId._optionalInternalFromInt64Value(channelId) {
                let peerId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: id)
                peerSignal = context.account.postbox.transaction { transaction -> Peer? in
                    return transaction.getPeer(peerId)
                } |> mapToSignalPromotingError { peer in
                    if let peer = peer {
                        return .single(peer)
                    } else {
                        return context.engine.peers.findChannelById(channelId: peerId.id._internalGetInt64Value())
                            |> mapToSignalPromotingError { value in
                                if let value = value {
                                    return .single(value._asPeer())
                                } else {
                                    return .fail(.privateAccess)
                                }
                            }
                        
                    }
                }
            }
        } else {
            peerSignal = context.engine.peers.resolvePeerByName(name: username, referrer: nil) |> filter { $0 != .progress} |> mapToSignalPromotingError { result -> Signal<Peer, Error> in
                if let result = result.result {
                    return .single(result._asPeer())
                } else {
                    return .fail(.doesntExists)
                }
            } |> mapError { _ in
                return .doesntExists
            }
        }
        _ = (peerSignal |> take(1) |> deliverOnMainQueue).start(next: { peer in
            openResolvedTopicLink(peer, threadId: threadId, commentId: commentId, context: context)
        }, error: { error in
            switch error {
            case .doesntExists:
                showModalText(for: getWindow(context), text: strings().alertUserDoesntExists)
            case .privateAccess:
                showModalText(for: getWindow(context), text: strings().alertPrivateChannelAccessError)
            case .generic:
                break
            }
        })

        afterComplete(true)
    case let .followResolvedName(_, username, postId, forceProfile, context, action, callback):
        
        let invokeCallback:(Peer, MessageId?, ChatInitialAction?) -> Void = { peer, messageId, action in
            openResolvedLinkPeer(peer, messageId: messageId, action: action, forceProfile: forceProfile, context: context, window: getWindow(context), callback: callback)
        }

        if username.hasPrefix(privateTelegramPeerPrefix), let range = username.range(of: privateTelegramPeerPrefix) {
            if let channelId = Int64(username[range.upperBound...]), let id = PeerId._optionalInternalFromInt64Value(channelId) {
                let peerId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: id)
                
                let peerSignal: Signal<Peer?, NoError> = context.account.postbox.transaction { transaction -> Peer? in
                    return transaction.getPeer(peerId)
                    } |> mapToSignal { peer in
                        if let peer = peer {
                            return .single(peer)
                        } else {
                            return context.engine.peers.findChannelById(channelId: peerId.id._internalGetInt64Value()) |> map { $0?._asPeer() }
                        }
                }
                
                _ = (showModalProgress(signal: peerSignal |> take(1) |> deliverOnMainQueue, for: getWindow(context))).start(next: { peer in
                    if let peer = peer {
                        let messageId:MessageId?
                        if let postId = postId {
                            messageId = MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: postId)
                        } else {
                            messageId = nil
                        }
                        if let peer = peer as? TelegramChannel {
                            if peer.participationStatus == .kicked {
                                showModalText(for: getWindow(context), text: strings().alertPrivateChannelAccessError)
                                return
                            }
                        }
                        invokeCallback(peer, messageId, action)
                    } else {
                        showModalText(for: getWindow(context), text: strings().alertPrivateChannelAccessError)
                    }
                })
            } else {
                showModalText(for: getWindow(context), text: strings().alertPrivateChannelAccessError)
            }
        } else {
            let phone = username.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            let signal: Signal<EnginePeer?, NoError>
            if phone == username {
                signal = context.engine.peers.resolvePeerByPhone(phone: phone)
            } else {
                let referrer: String?
                if let action {
                    switch action {
                    case let .start(parameter, _):
                        let prefix = context.appConfiguration.getStringValue("starref_start_param_prefixes", orElse: "_tgref_")
                        if parameter.hasPrefix(prefix) {
                            referrer = String(parameter.suffix(parameter.length - prefix.length))
                        } else {
                            referrer = nil
                        }
                    default:
                        referrer = nil
                    }
                } else {
                    referrer = nil
                }
                signal = context.engine.peers.resolvePeerByName(name: username, referrer: referrer) |> filter { $0 != .progress } |> map { $0.result }
            }
                
            let _ = (showModalProgress(signal: signal |> take(1) |> mapToSignal { result -> Signal<Peer?, NoError> in
                return .single(result?._asPeer())
            } |> deliverOnMainQueue, for: getWindow(context))).start(next: { peer in
                if let peer = peer {
                    let messageId:MessageId?
                    if let postId = postId {
                        messageId = MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: postId)
                    } else {
                        messageId = nil
                    }
                    
                    if peer.isBot {
                        if let action = action {
                            switch action {
                            case let .attachBot(botname, _, choose):
                                executeAttachBotLink(peer, botname: botname, choose: choose, action: action, messageId: messageId, context: context, window: getWindow(context), callback: callback)

                            case let .makeWebview(appname, command):
                                executeWebAppLink(peer, appname: appname, command: command, messageId: messageId, context: context, window: getWindow(context), callback: invokeCallback)

                            default:
                                invokeCallback(peer, messageId, action)
                            }
                        } else {
                            invokeCallback(peer, messageId, action)
                        }
                    } else {
                        invokeCallback(peer, messageId, action)
                    }
                } else {
                    alert(for: getWindow(context), info: strings().alertUserDoesntExists)
                    //showModalText(for: context.window, text: strings().alertUserDoesntExists)
                }
                    
            })
        }
        afterComplete(true)
    case let .contactToken(_, token, freeToken, context, callback):
        let window = getWindow(context)
        let signal = context.engine.peers.importContactToken(token: token) |> deliverOnMainQueue
        let _ = showModalProgress(signal: signal, for: window).start(next: { peer in
            guard let peer else {
                alert(for: window, info: strings().alertUserDoesntExists)
                return
            }
            if let freeToken {
                openNoPaidMessagesPeer(peer, token: freeToken, context: context, window: window, callback: callback)
            } else {
                callback(peer.id, true, nil, nil)
            }
        })
        afterComplete(true)
    case let .noPaidMessagesToken(_, username, token, context, callback):
        let window = getWindow(context)
        let phone = username.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        let signal: Signal<EnginePeer?, NoError>
        if phone == username {
            signal = context.engine.peers.resolvePeerByPhone(phone: phone)
        } else {
            signal = context.engine.peers.resolvePeerByName(name: username, referrer: nil) |> filter { $0 != .progress } |> map { $0.result }
        }
        let _ = showModalProgress(signal: signal |> deliverOnMainQueue, for: window).start(next: { peer in
            guard let peer else {
                alert(for: window, info: strings().alertUserDoesntExists)
                return
            }
            openNoPaidMessagesPeer(peer, token: token, context: context, window: window, callback: callback)
        })
        afterComplete(true)
    case let .inviteBotToGroup(_, username, context, action, rights, isChannel, callback):
        let _ = showModalProgress(signal: context.engine.peers.resolvePeerByName(name: username, referrer: nil) |> filter { $0.result != nil } |> map { $0.result! } |> deliverOnMainQueue, for: getWindow(context)).start(next: { botPeerId in
            
            
            var payload: String = ""
            if let action = action {
                switch action {
                case let .start(data, _):
                    payload = data
                default:
                    break
                }
            }
            let title: String
            if isChannel {
                title = strings().selectPeersTitleSelectChannel
            } else if payload.isEmpty {
                title = strings().selectPeersTitleSelectGroupOrChannel
            } else {
                title = strings().selectPeersTitleSelectGroup
            }
            
            let result = selectModalPeers(window: getWindow(context), context: context, title: title, behavior: SelectChatsBehavior(settings: isChannel ? [.channels, .checkInvite] : payload.isEmpty ? [.groups, .channels, .checkInvite] : [.groups, .checkInvite], limit: 1), confirmation: { peerIds -> Signal<Bool, NoError> in
                return .single(true)
            })
            |> filter { $0.first != nil }
            |> map { $0.first! }
            |> mapToSignal { sourceId in
                return combineLatest( context.account.postbox.loadedPeerWithId(botPeerId._asPeer().id), context.account.postbox.loadedPeerWithId(sourceId)) |> map {
                    (dest: $0, source: $1)
                }
            } |> deliverOnMainQueue
            
                        
            _ = result.start(next: { values in
                     
                
                let add:(PeerId)->Void = { peerId in
                    if payload.isEmpty || values.dest.isChannel {
                        addBotAsMember(context: context, peer: values.source, to: values.dest, completion: { peerId in
                            callback(peerId, true, nil, action)
                        }, error: { error in
                            alert(for: getWindow(context), info: error)
                        })
                    } else {
                        let signal = showModalProgress(signal: context.engine.messages.requestStartBotInGroup(botPeerId: botPeerId._asPeer().id, groupPeerId: peerId, payload: payload), for: context.window)
                            
                        _ = signal.start(next: { result in
                            switch result {
                            case let .channelParticipant(participant):
                                context.peerChannelMemberCategoriesContextsManager.externallyAdded(peerId: peerId, participant: participant)
                            case .none:
                                break
                            }
                            callback(peerId, true, nil, nil)
                        }, error: { error in
                            alert(for: getWindow(context), info: strings().unknownError)
                        })
                    }
                    
                }
                
                let addAdmin:()->Void = {
                    showModal(with: ChannelBotAdminController(context: context, peer: values.source, admin: values.dest, rights: rights, callback: { peerId in
                        add(peerId)
                    }), for: getWindow(context))
                }
                let addSimple:()->Void = {
                    verifyAlert_button(for: getWindow(context), information: strings().confirmAddBotToGroup(values.dest.displayTitle), successHandler: { _ in
                        add(values.dest.id)
                    })
                }
                if let peer = values.source as? TelegramChannel {
                    if peer.groupAccess.isCreator {
                        addAdmin()
                    } else if let adminRights = peer.adminRights, adminRights.rights.contains(.canAddAdmins) {
                        addAdmin()
                    } else {
                        addSimple()
                    }
                } else if let peer = values.source as? TelegramGroup {
                    switch peer.role {
                    case .creator:
                        addAdmin()
                    default:
                        addSimple()
                    }
                }
            })
            
        })
        afterComplete(true)
    case let .botCommand(command, interaction):
        interaction(command)
        afterComplete(true)
    case let .hashtag(hashtag, interaction):
        interaction(hashtag)
        afterComplete(true)
    case let .joinchat(_, hash, context, interaction):
        executeInviteLink(hash: hash, context: context, window: getWindow(context), interaction: interaction)
        afterComplete(true)
    case let .callback(param, interaction):
        interaction(param)
        afterComplete(true)
    case let .code(param, interaction):
        interaction(param)
        afterComplete(true)
    case let .logout(interaction):
        interaction()
        afterComplete(true)
    case let .shareUrl(_, context, url, text):
        if !url.hasPrefix("@") {
            showModal(with: ShareModalController(ShareLinkObject(context, link: url, text: text)), for: getWindow(context))
        }
        afterComplete(true)
    case let .wallpaper(_, context, preview):
        switch preview {
        case let .gradient(id, colors, settings):
            let wallpaper: TelegramWallpaper = .gradient(.init(id: id, colors: colors.map { $0.argb }, settings: settings))
            showModal(with: WallpaperPreviewController(context, wallpaper: Wallpaper(wallpaper), source: .link(wallpaper)), for: context.window)
        case let .color(color):
            let wallpaper: TelegramWallpaper = .color(color.argb)
            showModal(with: WallpaperPreviewController(context, wallpaper: Wallpaper(wallpaper), source: .link(wallpaper)), for: context.window)
        case let .slug(slug, settings):
            _ = showModalProgress(signal: getWallpaper(network: context.account.network, slug: slug) |> deliverOnMainQueue, for: context.window).start(next: { wallpaper in
                showModal(with: WallpaperPreviewController(context, wallpaper: Wallpaper(wallpaper).withUpdatedSettings(settings), source: .link(wallpaper)), for: context.window)
            }, error: { error in
                switch error {
                case .generic:
                    showModalText(for: getWindow(context), text: strings().wallpaperPreviewDoesntExists)
                }
            })
        }
        afterComplete(true)
    case let .stickerPack(_, reference, context, peerId):
        showModal(with: StickerPackPreviewModalController(context, peerId: peerId, references: [reference]), for: getWindow(context))
        afterComplete(true)
    case let .confirmPhone(_, context, phone, hash):
        _ = showModalProgress(signal: context.engine.auth.requestCancelAccountResetData(hash: hash) |> deliverOnMainQueue, for: context.window).start(next: { data in
            showModal(with: cancelResetAccountController(context: context, phone: phone, data: data), for: context.window)
        }, error: { error in
            switch error {
            case .limitExceeded:
                alert(for: getWindow(context), info: strings().loginFloodWait)
            case .generic:
                alert(for: getWindow(context), info: strings().unknownError)
            }
        })
        afterComplete(true)
    case let .socks(_, settings, _, applyProxy):
        applyProxy(settings)
        afterComplete(true)

    case .nothing:
        afterComplete(true)
    case let .requestSecureId(_, context, value):
        if value.nonce.isEmpty {
            alert(for: getWindow(context), info: value.isModern ? "nonce is empty" : "payload is empty")
            return
        }
        _ = showModalProgress(signal: (requestSecureIdForm(accountPeerId: context.peerId, postbox: context.account.postbox, network: context.account.network, peerId: value.peerId, scope: value.scope, publicKey: value.publicKey) |> mapToSignal { form in
            return context.account.postbox.loadedPeerWithId(context.peerId) |> castError(RequestSecureIdFormError.self) |> map { peer in
                return (form, peer)
            }
        } |> deliverOnMainQueue), for: getWindow(context)).start(next: { form, peer in
            let passport = PassportWindowController(context: context, peer: peer, request: value, form: form)
            passport.show()
        }, error: { error in
            switch error {
            case .serverError(let text):
                alert(for: getWindow(context), info: text)
            case .generic:
                alert(for: getWindow(context), info: "An error occured")
            case .versionOutdated:
                updateAppAsYouWish(text: strings().secureIdAppVersionOutdated, updateApp: true)
            }
        })
        afterComplete(true)
    case let .applyLocalization(_, context, value):
        _ = showModalProgress(signal: context.engine.localization.requestLocalizationPreview(identifier: value) |> deliverOnMainQueue, for: getWindow(context)).start(next: { info in
            if appAppearance.language.primaryLanguage.languageCode == info.languageCode {
                alert(for: getWindow(context), info: strings().applyLanguageChangeLanguageAlreadyActive(info.title))
            } else if info.totalStringCount == 0 {
                verifyAlert_button(for: getWindow(context), header: strings().applyLanguageUnsufficientDataTitle, information: strings().applyLanguageUnsufficientDataText(info.title), cancel: "", option: strings().applyLanguageUnsufficientDataOpenPlatform, successHandler: { result in
                    switch result {
                    case .basic:
                        break
                    case .thrid:
                        execute(inapp: inAppLink.external(link: info.platformUrl, false))
                    }
                })
            } else {
                showModal(with: LocalizationPreviewModalController(context, info: info), for: getWindow(context))
            }
           
        }, error: { error in
            switch error {
            case .generic:
                alert(for: getWindow(context), info: strings().localizationPreviewErrorGeneric)
            }
        })
        afterComplete(true)
    case let .theme(_, context, name):
        _ = showModalProgress(signal: getTheme(account: context.account, slug: name), for: getWindow(context)).start(next: { value in
            if value.file == nil, let _ = value.settings {
                showModal(with: ThemePreviewModalController(context: context, source: .cloudTheme(value)), for: getWindow(context))
            } else if value.file == nil {
                showEditThemeModalController(context: context, theme: value)
            } else {
                showModal(with: ThemePreviewModalController(context: context, source: .cloudTheme(value)), for: getWindow(context))
            }
        }, error: { error in
            switch error {
            case .generic:
                alert(for: getWindow(context), info: strings().themeGetThemeError)
            case .unsupported:
                alert(for: getWindow(context), info: strings().themeGetThemeError)
            case .slugInvalid:
                alert(for: getWindow(context), info: strings().themeGetThemeError)
            }
        })
        afterComplete(true)
    case let .story(_, username, storyId, messageId, context):
        let signal = showModalProgress(signal: context.engine.peers.resolvePeerByName(name: username, referrer: nil) |> filter { $0 != .progress } |> map { $0.result?._asPeer() }, for: getWindow(context))
        _ = (signal).start(next: { peer in
            if let peer = peer {
                let controller = context.bindings.rootNavigation().controller as? ChatController
                if let messageId = messageId, controller?.chatLocation.peerId == messageId.peerId {
                    controller?.chatInteraction.openStoryObserved(messageId, .init(peerId: peer.id, id: storyId))
                } else {
                    StoryModalController.ShowSingleStory(context: context, storyId: .init(peerId: peer.id, id: storyId), initialId: nil, emptyCallback: {
                        showModalText(for: getWindow(context), text: strings().storyErrorNotExist)
                    })
                }
            } else {
                showModalText(for: getWindow(context), text: strings().alertUserDoesntExists)
            }
        })
        afterComplete(true)
    case let .unsupportedScheme(_, context, path):
        _ = (context.engine.resolve.getDeepLinkInfo(path: path) |> deliverOnMainQueue).start(next: { info in
            if let info = info {
               updateAppAsYouWish(text: info.message, updateApp: info.updateApp)
            }
        })
        afterComplete(true)
    case let .tonTransfer(link, context, _):
        if #available(macOS 10.15, *), !WalletConfiguration.with(appConfiguration: context.appConfiguration).isAvailable {
            showModalText(for: context.window, text: strings().inAppLinksWalletUnavailable)
        } else if #available(macOS 10.15, *), let walletContext = context.walletContext {
            showModal(with: WalletSendController(context: context, walletContext: walletContext, initialAddress: link), for: context.window)
        }
        afterComplete(true)
    case let .sendGrams(_, context, data):
        if #available(macOS 10.15, *), !WalletConfiguration.with(appConfiguration: context.appConfiguration).isAvailable {
            showModalText(for: context.window, text: strings().inAppLinksWalletUnavailable)
        } else if #available(macOS 10.15, *), let walletContext = context.walletContext {
            let window = getWindow(context)
            switch data {
            case .invalid:
                showModalText(for: window, text: strings().inAppLinksInvalidWalletLink)
            case .wallet:
                showWallet(context: context, for: window)
            case let .send(recipient, amount):
                switch walletContext.stateValue.phase {
                case .empty, .creating, .failed:
                    showWallet(context: context, for: window)
                case .restoring, .wallet:
                    switch recipient {
                    case let .address(address):
                        showModal(with: WalletSendController(context: context, walletContext: walletContext, initialAddress: address, initialAmount: amount), for: window)
                    case let .username(username):
                        let signal = context.engine.peers.resolvePeerByName(name: username, referrer: nil)
                        |> filter { $0 != .progress }
                        |> take(1)
                        |> map { $0.result?._asPeer() as? TelegramUser }
                        |> deliverOnMainQueue
                        _ = showModalProgress(signal: signal, for: window).start(next: { user in
                            guard let user else {
                                showModalText(for: window, text: strings().alertUserDoesntExists)
                                return
                            }
                            showModal(with: WalletSendController(context: context, walletContext: walletContext, peer: user, initialAmount: amount, completed: {
                                closeAllModals(window: window)
                                context.bindings.rootNavigation().push(ChatController(context: context, chatLocation: .peer(user.id)))
                            }), for: window)
                        })
                    }
                }
            }
        }
        afterComplete(true)
    case .instantView:
        afterComplete(true)
    case let .settings(_, context, section):
        let controller: ViewController
        switch section {
        case .themes:
            controller = AppAppearanceViewController(context: context)
        case let .devices(subSection):
            switch subSection {
            case .none:
                controller = RecentSessionsController(context)
            case .terminate_sessions:
                verifyAlert_button(for: getWindow(context), information: strings().recentSessionsConfirmTerminateOthers, successHandler: { _ in
                    _ = showModalProgress(signal: context.activeSessionsContext.removeOther(), for: getWindow(context)).start()
                })
                afterComplete(true)
                return
            case .auto_terminate:
                controller = RecentSessionsController(context, focusOnItemTag: .autoTerminate)
            }
        case let .folders(subSection):
            switch subSection {
            case .none, .edit:
                controller = ChatListFiltersListController(context: context)
            case .new:
                controller = ChatListFilterController(context: context, filter: ChatListFilter.new(excludeIds: []), isNew: true)
            }
        case let .privacy(subSection):
            switch subSection {
            case .none:
                controller = PrivacyAndSecurityViewController(context, initialSettings: nil, focusOnItemTag: nil, twoStepVerificationConfiguration: nil)
            case .phone:
                pushSelectivePrivacySettings(context: context, kind: .phoneNumber, navigation: context.bindings.rootNavigation())
                afterComplete(true)
                return
            case .calls:
                pushSelectivePrivacySettings(context: context, kind: .voiceCalls, navigation: context.bindings.rootNavigation())
                afterComplete(true)
                return
            case .p2p:
                pushSelectivePrivacySettings(context: context, kind: .voiceCalls, navigation: context.bindings.rootNavigation())
                afterComplete(true)
                return
            case .forwards:
                pushSelectivePrivacySettings(context: context, kind: .forwards, navigation: context.bindings.rootNavigation())
                afterComplete(true)
                return
            case .profile_photos:
                pushSelectivePrivacySettings(context: context, kind: .profilePhoto, navigation: context.bindings.rootNavigation())
                afterComplete(true)
                return
            case .bio:
                pushSelectivePrivacySettings(context: context, kind: .bio, navigation: context.bindings.rootNavigation())
                afterComplete(true)
                return
            case .birthday:
                pushSelectivePrivacySettings(context: context, kind: .birthday, navigation: context.bindings.rootNavigation())
                afterComplete(true)
                return
            case .gifts:
                pushSelectivePrivacySettings(context: context, kind: .gifts, navigation: context.bindings.rootNavigation())
                afterComplete(true)
                return
            case .saved_music:
                pushSelectivePrivacySettings(context: context, kind: .savedMusic, navigation: context.bindings.rootNavigation())
                afterComplete(true)
                return
            case .blocked:
                controller = BlockedPeersViewController(context)
            case .passcode:
                controller = PasscodeSettingsViewController(context)
            case .two_step:
                context.bindings.rootNavigation().push(twoStepVerificationUnlockController(context: context, mode: .access(nil), presentController: { controller, root, animated in
                    let navigation = context.bindings.rootNavigation()
                    if root {
                        navigation.removeUntil(PrivacyAndSecurityViewController.self)
                    }
                    if !animated {
                        navigation.stackInsert(controller, at: navigation.stackCount)
                    } else {
                        navigation.push(controller)
                    }
                }))
                afterComplete(true)
                return
            case .email:
                let signal = context.engine.auth.twoStepAuthData()
                    |> map(Optional.init)
                    |> `catch` { _ -> Signal<TwoStepAuthData?, NoError> in
                        return .single(nil)
                    }
                    |> map { $0?.loginEmailPattern }
                    |> deliverOnMainQueue
                _ = signal.start(next: { emailPattern in
                    showModal(with: SetupEmailController(context: context, pattern: emailPattern), for: context.window)
                })
                afterComplete(true)
                return
            case let .auto_delete(autoDeleteSubSection):
                switch autoDeleteSubSection {
                case .none, .delete_all:
                    let signal = context.engine.privacy.requestAccountPrivacySettings() |> deliverOnMainQueue
                    _ = signal.start(next: { privacy in
                        context.bindings.rootNavigation().push(GlobalAutoremoveMessagesController(context: context, privacy: privacy, updated: { timeout, deleteAll in
                            _ = context.engine.privacy.updateGlobalMessageRemovalTimeout(timeout: timeout).start()
                        }))
                    })
                    afterComplete(true)
                    return
                }
            case .data_settings:
                controller = WebSessionsController(context)
            }
        case .enable_log:
            if !Logger.shared.logToFile {
                MTLogSetEnabled(true)
                _ = updateLoggingSettings(accountManager: context.sharedContext.accountManager, {
                    $0.withUpdatedLogToFile(true)
                }).start()
                Logger.shared.logToFile = true
                verifyAlert(
                    for: getWindow(context),
                    information: strings().logRestartInfo,
                    ok: strings().commonRestart,
                    successHandler: { _ in
                        restartApp()
                    }
                )
            } else {
                showModalText(for: getWindow(context), text: strings().logsEnabled)
            }
            
            afterComplete(true)
            return
        case .password:
            controller = twoStepVerificationUnlockController(context: context, mode: .access(nil), presentController:  { controller, isRoot, animated in
                let navigation = context.bindings.rootNavigation()
                if isRoot {
                    navigation.removeUntil(PrivacyAndSecurityViewController.self)
                }

                if !animated {
                    navigation.stackInsert(controller, at: navigation.stackCount)
                } else {
                    navigation.push(controller)
                }
            })
        case .phone_privacy:
            let privacySignal = context.privacy |> take(1) |> deliverOnMainQueue

            let _ = (privacySignal
                |> deliverOnMainQueue).startStandalone(next: { info in
                if let info = info {
                    context.bindings.rootNavigation().push(SelectivePrivacySettingsController(context, kind: .birthday, current: info.birthday, callSettings: nil, phoneDiscoveryEnabled: nil, updated: { updated, updatedCallSettings, _, _ in
                        context.updatePrivacy(updated, kind: .birthday)
                    }))
                }
            })
            afterComplete(true)
            return
        case let .send_gift(subSection):
            switch subSection {
            case .none:
                multigift(context: context)
            case .self_:
                showModal(with: GiftingController(context: context, peerId: context.peerId, isBirthday: false), for: getWindow(context))
            }
            afterComplete(true)
            return
        case .ask_question:
            _ = showModalProgress(signal: context.engine.peers.supportPeerId(), for: getWindow(context)).start(next: { peerId in
                if let peerId = peerId {
                    context.bindings.rootNavigation().push(ChatController(context: context, chatLocation: .peer(peerId)))
                }
            })
            afterComplete(true)
            return
        case .faq:
            openFaq(context: context)
            afterComplete(true)
            return
        case .privacy_policy:
            execute(inapp: .external(link: "https://telegram.org/privacy", true))
            afterComplete(true)
            return
        case .search:
            let mainController = context.bindings.mainViewController
            mainController.showPreferences()
            if let accountController = mainController.tabController.tab(at: mainController.settingsIndex).controller as? AccountViewController {
                accountController.focusOnSearch = true
                if accountController.isLoaded() {
                    _ = (accountController.ready.get() |> filter { $0 } |> take(1) |> deliverOnMainQueue).start(next: { [weak accountController] _ in
                        DispatchQueue.main.async {
                            accountController?.searchView.change(state: .Focus, true)
                        }
                    })
                }
            }
            afterComplete(true)
            return
        case let .business(subSection):
            switch subSection {
            case .none:
                context.bindings.rootNavigation().push(PremiumBoardingController(context: context, source: .business_standalone, focusOnItemTag: nil))
            case .do_not_hide_ads:
                context.bindings.rootNavigation().push(PremiumBoardingController(context: context, source: .business_standalone, focusOnItemTag: .toggleAds))
            }
            afterComplete(true)
            return
        case let .stars(subSection):
            switch subSection {
            case .none:
                showModal(with: Star_ListScreen(context: context, source: .account), for: getWindow(context))
            case .top_up:
                showModal(with: Star_ListScreen(context: context, source: .buy(suffix: nil, amount: nil)), for: getWindow(context))
            case .stats:
                context.bindings.rootNavigation().push(FragmentStarMonetizationController(context: context, peerId: context.peerId, revenueContext: nil))
            case .gift:
                multigift(context: context, type: .stars)
            case .earn:
                context.bindings.rootNavigation().push(Affiliate_PeerController(context: context, peerId: context.peerId))
            }
            afterComplete(true)
            return
        case .premium:
            showModal(with: PremiumBoardingController(context: context, source: .settings), for: getWindow(context))
            afterComplete(true)
            return
        case .language:
            controller = LanguageController(context)
        case let .translation(subSection):
            switch subSection {
            case .none:
                controller = LanguageController(context)
            case .do_not_translate:
                controller = LanguageController(context, focusOnItemTag: .doNotTranslate)
            }
        case .ton:
            showModal(with: Star_ListScreen(context: context, currency: .ton, source: .account), for: getWindow(context))
            afterComplete(true)
            return
        case let .appearance(subSection):
            switch subSection {
            case .none:
                controller = AppAppearanceViewController(context: context)
            case .text_size:
                controller = AppAppearanceViewController(context: context, focusOnItemTag: .fontSize)
            case .wallpapers:
                showModal(with: ChatWallpaperModalController(context), for: getWindow(context))
                afterComplete(true)
                return
            case .themes:
                controller = AppAppearanceViewController(context: context, focusOnItemTag: .theme)
            case .color_theme:
                controller = AppAppearanceViewController(context: context, focusOnItemTag: .accentColor)
            case .stickers_and_emoji(let stickersSubSection):
                switch stickersSubSection {
                case .none:
                    controller = InstalledStickerPacksController(context)
                case .emoji:
                    controller = InstalledStickerPacksController(context)
                }
            }
        case let .data(subSection):
            switch subSection {
            case .none:
                controller = DataAndStorageViewController(context)
            case .storage:
                controller = StorageUsageController(context)
            case .network:
                controller = networkUsageStatsController(context: context)
            case .auto_download:
                controller = DataAndStorageViewController(context, focusOnItemTag: .automaticDownloadReset)
            case .proxy(let proxySubSection):
                let proxyController = proxyListController(accountManager: context.sharedContext.accountManager, network: context.account.network, share: { _ in }, pushController: { vc in
                    context.bindings.rootNavigation().push(vc)
                })
                context.bindings.rootNavigation().push(proxyController)
                if proxySubSection == .add {
                    delay(0.3, closure: {
                        context.bindings.rootNavigation().push(addProxyController(accountManager: context.sharedContext.accountManager, network: context.account.network, settings: nil))
                    })
                }
                afterComplete(true)
                return
            }
        case let .notifications(subSection):
            switch subSection {
            case .none:
                controller = NotificationPreferencesController(context)
            case .include_channels:
                controller = NotificationPreferencesController(context, focusOnItemTag: .includeChannels)
            case .include_muted_chats:
                controller = NotificationPreferencesController(context, focusOnItemTag: .includeMutedChats)
            case .count_unread_messages:
                controller = NotificationPreferencesController(context, focusOnItemTag: .unreadCountCategory)
            case .sound:
                controller = NotificationPreferencesController(context, focusOnItemTag: .tone)
            case .message_effect:
                controller = NotificationPreferencesController(context, focusOnItemTag: .messageEffect)
            case .badge:
                controller = NotificationPreferencesController(context, focusOnItemTag: .badgeEnabled)
            case .show:
                controller = NotificationPreferencesController(context, focusOnItemTag: .messagePreviews)
            case .accounts:
                controller = NotificationPreferencesController(context, focusOnItemTag: .allAccounts)
            case .new_contacts:
                controller = NotificationPreferencesController(context, focusOnItemTag: .joinedNotifications)
            case .reset:
                controller = NotificationPreferencesController(context, focusOnItemTag: .reset)
            case let .private_chats(chatSubSection):
                controller = NotificationCategorySettingsController(context: context, category: .privateChats, focusOnItemTag: chatSubSection.flatMap(notificationCategoryEntryTag))
            case let .groups(chatSubSection):
                controller = NotificationCategorySettingsController(context: context, category: .groupChats, focusOnItemTag: chatSubSection.flatMap(notificationCategoryEntryTag))
            case let .channels(chatSubSection):
                controller = NotificationCategorySettingsController(context: context, category: .channels, focusOnItemTag: chatSubSection.flatMap(notificationCategoryEntryTag))
            case let .stories(storiesSubSection):
                let tag: NotificationCategoryEntryTag?
                switch storiesSubSection {
                case .new:
                    tag = .show
                case .important:
                    tag = .important
                case .show_sender:
                    tag = .preview
                case .sound:
                    tag = .sound
                case .add_exception:
                    tag = .addException
                case .delete_exceptions:
                    tag = .deleteExceptions
                case .none:
                    tag = nil
                }
                controller = NotificationCategorySettingsController(context: context, category: .stories, focusOnItemTag: tag)
            case let .reactions(reactionsSubSection):
                let tag: ReactionNotificationEntryTag?
                switch reactionsSubSection {
                case .messages:
                    tag = .messages
                case .stories:
                    tag = nil
                case .show_sender:
                    tag = .showSender
                case .sound:
                    tag = .sound
                case .none:
                    tag = nil
                }
                controller = ReactionNotificationSettingsController(context: context, focusOnItemTag: tag)
            }
        case let .calls(subSection):
            switch subSection {
            case .none:
                context.bindings.mainViewController.showCalls()
            case .start_call:
                showNewCallModal(context: context)
            }
            afterComplete(true)
            return
        case let .edit_profile(subSection):
            let focusTag: EditSettingsEntryTag? = subSection == .username ? .username : nil
            EditAccountInfoController(context: context, focusOnItemTag: focusTag, f: { controller in
                context.bindings.rootNavigation().push(controller)
            })
            afterComplete(true)
            return
        case .change_number:
            let navigation = MajorNavigationController(PhoneNumberIntroController.self, PhoneNumberIntroController(context), context.window)
            navigation.alwaysAnimate = true
            navigation._frameRect = NSMakeRect(0, 0, 350, 400)
            navigation.readyOnce()
            showModal(with: navigation, for: context.window)
            afterComplete(true)
            return
        case .my_stories:
            let listContext = PeerStoryListContext(account: context.account, peerId: context.peerId, isArchived: false, folderId: nil)
            controller = StoryMediaController(context: context, peerId: context.peerId, listContext: listContext, standalone: true)
        case .general:
            context.bindings.mainViewController.showPreferences()
            afterComplete(true)
            return
        case .chat:
            context.bindings.mainViewController.showChatList()
            afterComplete(true)
            return
        }
        context.bindings.rootNavigation().push(controller)
        afterComplete(true)
    case let .joinGroupCall(_, context, peerId, callId):
        selectGroupCallJoiner(context: context, peerId: peerId, completion: { peerId, schedule, isStream in
            _ = requestOrJoinGroupCall(context: context, peerId: peerId, joinAs: context.peerId, initialCall: callId, reference: nil).start(next: { result in
                switch result {
                case let .success(callContext), let .samePeer(callContext):
                    applyGroupCallResult(context.sharedContext, callContext)
                default:
                    alert(for: getWindow(context), info: strings().errorAnError)
                }
            })
        })
       
        afterComplete(true)
    case let .invoice(_, context, slug):
        executeInvoiceLink(slug: slug, context: context, window: getWindow(context))
        afterComplete(true)
    case let .premiumOffer(_, ref, context):
        if !context.premiumIsBlocked {
            if context.isPremium {
                showModalText(for: getWindow(context), text: strings().premiumOffsetAlreadyHave)
            } else {
                if let modal = findModal(PremiumBoardingController.self) {
                    modal.buy()
                } else {
                    prem(with: PremiumBoardingController(context: context, source: .deeplink(ref)), for: getWindow(context))
                }
            }
        }
        afterComplete(true)
    case .restorePurchase(_, _):
        if let modal = findModal(PremiumBoardingController.self) {
            modal.restore()
        }
        afterComplete(true)
    case let .urlAuth(link, context):
        _ = showModalProgress(signal: context.engine.messages.requestMessageActionUrlAuth(subject: .url(url: link, inAppOrigin: nil)), for: getWindow(context)).start(next: { result in
            switch result {
            case let .accepted(url):
                if let url {
                    execute(inapp: .external(link: url, false))
                }
            case .default:
                execute(inapp: .external(link: link, true))
            case let .request(domain, bot, clientData, flags, matchCodes, userIdHint):
                let data = LoginWidgetData(
                    domain: domain,
                    bot: EnginePeer(bot),
                    clientData: clientData,
                    flags: flags,
                    subject: .url(url: link, inAppOrigin: nil),
                    matchCodes: matchCodes,
                    userIdHint: userIdHint
                )
                showLoginWidgetConfirmation(context: context, sharedContext: context.sharedContext, data: data)
            }
        })
        afterComplete(true)
    case let .folder(_, slug, context):
        loadAndShowSharedFolder(context: context, slug: slug)
        afterComplete(true)
    case let .loginCode(_, code):
        appDelegate?.applyExternalLoginCode(code)
        afterComplete(true)
    case let .boost(_, username, context):
        let signal: Signal<(Peer, ChannelBoostStatus?, MyBoostStatus?)?, NoError> = resolveUsername(username: username, context: context) |> mapToSignal { value in
            if let value = value {
                return combineLatest(context.engine.peers.getChannelBoostStatus(peerId: value.id), context.engine.peers.getMyBoostStatus()) |> map {
                    (value, $0, $1)
                }
            } else {
                return .single(nil)
            }
        }
        _ = showModalProgress(signal: signal, for: getWindow(context)).start(next: { value in
            if let value = value, let boosts = value.1 {
                showModal(with: BoostChannelModalController(context: context, peer: value.0, boosts: boosts, myStatus: value.2 ), for: getWindow(context))
            } else {
                if value == nil {
                    if username.contains(privateTelegramPeerPrefix) {
                        alert(for: getWindow(context), info: strings().channelBoostPrivateError)
                    } else {
                        alert(for: getWindow(context), info: strings().alertUserDoesntExists)
                    }
                } else {
                    alert(for: getWindow(context), info: strings().unknownError)
                }
                
            }
        })
        afterComplete(true)
    case let .gift(_, slug, context):
        _ = showModalProgress(signal: context.engine.payments.checkPremiumGiftCode(slug: slug), for: getWindow(context)).start(next: { info in
            if let info = info {
                showModal(with: GiftLinkModalController(context: context, info: info), for: getWindow(context))
            } else {
                alert(for: getWindow(context), info: strings().unknownError)
            }
        })
        afterComplete(true)
    case let .multigift(_, context):
        let behaviour = SelectContactsBehavior.init(settings: [.contacts, .remote, .excludeBots], excludePeerIds: [], limit: 10)
        
        _ = selectModalPeers(window: getWindow(context), context: context, title: strings().premiumGiftTitle, behavior: behaviour).start(next: { peerIds in
            
            showModal(with: PremiumGiftingController(context: context, peerIds: peerIds), for: getWindow(context))
        })
        afterComplete(true)
    case .businessLink(link: _, slug: let slug, context: let context):
        _ = showModalProgress(signal: context.engine.peers.resolveMessageLink(slug: slug), for: getWindow(context)).startStandalone(next: { link in
            if let link {
                let navigation = context.bindings.rootNavigation()
                let current = navigation.controller as? ChatController
                let textState = ChatTextInputState(inputText: link.message, selectionRange: link.message.length ..< link.message.length, attributes: chatTextAttributes(from: TextEntitiesMessageAttribute(entities: link.entities), associatedMedia: [:]))
                if let current {
                    if current.chatLocation.peerId == link.peer.id {
                        current.chatInteraction.invokeInitialAction(action: .inputText(text: textState, behavior: .automatic))
                    } else {
                        current.chatInteraction.openInfo(link.peer.id, true, nil, .inputText(text: textState, behavior: .automatic))
                    }
                } else {
                    navigation.push(ChatAdditionController(context: context, chatLocation: .peer(link.peer.id), initialAction: .inputText(text: textState, behavior: .automatic)))
                }
            } else {
                showModalText(for: getWindow(context), text: strings().chatLinkUnavailable)
            }
        })
        afterComplete(true)
    case let .tonsite(link, context):
        BrowserStateContext.get(context).open(tab: .tonsite(url: link))
        afterComplete(true)
    case let .starsTopup(_, amount, purpose, context):
        let balance = context.starsContext.state |> map { $0?.balance } |> take(1) |> deliverOnMainQueue
        _ = balance.startStandalone(next: { balance in
            if let balance = balance {
                if balance.value > amount {
                    showModalText(for: getWindow(context), text: strings().starsYouHaveEnough, callback: { value in
                        showModal(with: Star_ListScreen(context: context, source: .buy(suffix: purpose, amount: nil)), for: getWindow(context))
                    })
                } else {
                    showModal(with: Star_ListScreen(context: context, source: .buy(suffix: purpose, amount: amount)), for: getWindow(context))
                }
            }
        })
        afterComplete(true)
    case let .nft(_, slug, context):
        _ = showModalProgress(signal: context.engine.payments.getUniqueStarGift(slug: slug), for: getWindow(context)).start(next: { gift in
            showModal(with: StarGift_Nft_Controller(context: context, gift: .unique(gift), source: .quickLook(nil, gift), transaction: nil), for: getWindow(context))
        }, error: { error in
            switch error {
            case .alreadyBurned:
                showModalText(for: getWindow(context), text: strings().chatServiceGiftUsedForCrafting)
            default:
                showModalText(for: getWindow(context), text: strings().unknownError)
            }
        })
        afterComplete(true)
    case let .joinCall(_, slug, context):
                
        _ = showModalProgress(signal: context.engine.calls.getCurrentGroupCall(reference: .link(slug: slug)), for: getWindow(context)).start(next: { summary in
            if let summary {
                showModal(with: JoinGroupCallController(context: context, summary: summary, reference: .link(slug: slug)), for: getWindow(context))
            }
        }, error: { error in
            switch error {
            case .generic:
                showModalText(for: getWindow(context), text: strings().groupCallInviteLinkExpired)
            }
        })
        afterComplete(true)
    case let .starsInfo(_, context, isTon):
        showModal(with: Star_ListScreen(context: context, currency: isTon ? .ton : .stars, source: .account), for: getWindow(context))
        afterComplete(true)
    case let .auction(_, slug, context):
        let signal = context.giftAuctionsManager.auctionContext(for: .slug(slug)) |> deliverOnMainQueue

        _ = showModalProgress(signal: signal, for: getWindow(context)).startStandalone(next: { auctionContext in
            if let auctionContext {
                if auctionContext.isActive {
                    showModal(with: Star_AuctionBidController(context: context, peerId: context.peerId, gift: auctionContext.gift.generic!, auctionContext: auctionContext), for: getWindow(context))
                } else {
                    showModal(with: Star_AuctionPreviewController(context: context, auctionContext: auctionContext, peerId: context.peerId, callback: {
                        
                        if auctionContext.gift.generic?.upgradeVariantsCount != nil {
                            _ = showModalProgress(signal: context.engine.payments.getStarGiftUpgradeAttributes(giftId: auctionContext.gift.giftId), for: getWindow(context)).startStandalone(next: { attributes in
                                if let attributes {
                                    showModal(with: StarGift_SelfAuction_Controller(context: context, gift: auctionContext.gift, attributes: attributes, giftAuctionContext: auctionContext), for: getWindow(context))
                                }
                            })
                        } else {
                            showModal(with: PreviewStarGiftController(context: context, option: .starGift(option: PeerStarGift(media: auctionContext.gift.generic!.file, stars: 0, limited: true, native: auctionContext.gift)), peer: .init(context.myPeer!), disallowedGifts: .init(), starGiftsProfile: nil), for: getWindow(context))
                        }
                        
                        
                    }), for: getWindow(context))
                }
            } else {
                showModalText(for: getWindow(context), text: strings().auctionErrorNotExists)
            }
        })
        afterComplete(true)
    case let .oauth(_, token, context):
        guard isExternal else {
            afterComplete(false)
            return
        }
        let oauthUrl = "tg://oauth?token=\(token)"
        _ = showModalProgress(signal: context.engine.messages.requestMessageActionUrlAuth(subject: .url(url: oauthUrl, inAppOrigin: nil)), for: getWindow(context)).start(next: { result in
            switch result {
            case let .accepted(url):
                if let url = url {
                    execute(inapp: .external(link: url, false))
                } else {
                    showModalText(for: getWindow(context), text: strings().inAppLinksLoginSuccess)
                }
            case .default:
                showModalText(for: getWindow(context), text: strings().inAppLinksAuthFailed)
            case let .request(domain, bot, clientData, flags, matchCodes, userIdHint):
                let data = LoginWidgetData(
                    domain: domain,
                    bot: EnginePeer(bot),
                    clientData: clientData,
                    flags: flags,
                    subject: .url(url: oauthUrl, inAppOrigin: nil),
                    matchCodes: matchCodes,
                    userIdHint: userIdHint
                )
                showLoginWidgetConfirmation(context: context, sharedContext: context.sharedContext, data: data)
            }
        })
        afterComplete(true)
    case let .createBot(_, context, managerUsername, botUsername, title):
        _ = (context.engine.peers.resolvePeerByName(name: managerUsername, referrer: nil) |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
            guard case let .result(result) = result else {
                return .complete()
            }
            return .single(result)
        } |> deliverOnMainQueue).start(next: { peer in
            if let peer = peer, let user = peer._asPeer() as? TelegramUser, let botInfo = user.botInfo, botInfo.flags.contains(.canManageBots) {
                showModal(with: CreateBotModalController(context: context, managerUsername: managerUsername, botUsername: botUsername, botTitle: title), for: getWindow(context))
            } else {
                showModalText(for: getWindow(context), text: strings().inAppLinksBotManagementDisabled(managerUsername))
            }
        })
        afterComplete(true)
    case let .addStyle(_, slug, context):
        let signal = fetchAiStylePreviewInfo(context: context, slug: slug) |> deliverOnMainQueue
        _ = (showModalProgress(signal: signal, for: getWindow(context))).start(next: { info in
            if let info {
                showModal(with: AiStylePreviewModalController(context: context, slug: slug, info: info), for: getWindow(context))
            } else {
                showModalText(for: getWindow(context), text: strings().inAppLinksStyleNotFound)
            }
        })
        afterComplete(true)
    }

}

private func updateAppAsYouWish(text: String, updateApp: Bool) {
    //
    if updateApp {
        verifyAlert_button(for: mainWindow, header: appName, information: text, ok: strings().alertButtonOKUpdateApp, cancel: strings().modalCancel, option: nil, successHandler: { _ in
            if updateApp {
                #if APP_STORE
                execute(inapp: inAppLink.external(link: itunesAppLink, false))
                #else
                (NSApp.delegate as? AppDelegate)?.checkForUpdates(updateApp)
                #endif
            }
        })
    } else {
        alert(for: mainWindow, info: text, ok: strings().modalOK)
    }
    
}

enum inAppLink {
    
    
    case external(link:String, Bool) // link, confirm
    case tonsite(link: String, context: AccountContext)
    case peerInfo(link: String, peerId:PeerId, action:ChatInitialAction?, openChat:Bool, postId:Int32?, callback:(PeerId, Bool, MessageId?, ChatInitialAction?)->Void)
    case followResolvedName(link: String, username:String, postId:Int32?, forceProfile: Bool, context: AccountContext, action:ChatInitialAction?, callback:(PeerId, Bool, MessageId?, ChatInitialAction?)->Void)
    case noPaidMessagesToken(link: String, username: String, token: String, context: AccountContext, callback:(PeerId, Bool, MessageId?, ChatInitialAction?)->Void)
    case contactToken(link: String, token: String, freeToken: String?, context: AccountContext, callback:(PeerId, Bool, MessageId?, ChatInitialAction?)->Void)
    case comments(link: String, username:String, context: AccountContext, threadId: Int32, commentId: Int32?)
    case topic(link: String, username:String, context: AccountContext, threadId: Int32, commentId: Int32?)
    case inviteBotToGroup(link: String, username:String, context: AccountContext, action:ChatInitialAction?, rights: String?, isChannel: Bool, callback:(PeerId, Bool, MessageId?, ChatInitialAction?)->Void)
    case botCommand(String, (String)->Void)
    case callback(String, (String)->Void)
    case code(String, (String)->Void)
    case hashtag(String, (String)->Void)
    case shareUrl(link: String, AccountContext, String, String?)
    case joinchat(link: String, String, context: AccountContext, callback:(PeerId, Bool, MessageId?, ChatInitialAction?)->Void)
    case logout(()->Void)
    case stickerPack(link: String, StickerPackPreviewSource, context: AccountContext, peerId:PeerId?)
    case confirmPhone(link: String, context: AccountContext, phone: String, hash: String)
    case nothing
    case socks(link: String, ProxyServerSettings, context: AccountContext, applyProxy:(ProxyServerSettings)->Void)
    case requestSecureId(link: String, context: AccountContext, value: inAppSecureIdRequest)
    case unsupportedScheme(link: String, context: AccountContext, path: String)
    case applyLocalization(link: String, context: AccountContext, value: String)
    case wallpaper(link: String, context: AccountContext, preview: WallpaperPreview)
    case theme(link: String, context: AccountContext, name: String)
    case tonTransfer(link: String, context: AccountContext, data: ParsedWalletUrl)
    case sendGrams(link: String, context: AccountContext, data: ParsedSendGramsLink)
    case instantView(link: String, webpage: TelegramMediaWebpage, anchor: String?)
    case settings(link: String, context: AccountContext, section: InAppSettingsSection)
    case joinGroupCall(link: String, context: AccountContext, peerId: PeerId, call: CachedChannelData.ActiveCall)
    case invoice(link: String, context: AccountContext, slug: String)
    case premiumOffer(link: String, ref: String?, context: AccountContext)
    case restorePurchase(link: String, context: AccountContext)
    case urlAuth(link: String, context: AccountContext)
    case loginCode(link: String, code: String)
    case folder(link: String, slug: String, context: AccountContext)
    case story(link: String, username: String, storyId: Int32, messageId: MessageId?, context: AccountContext)
    case boost(link: String, username: String, context: AccountContext)
    case gift(link: String, slug: String, context: AccountContext)
    case businessLink(link: String, slug: String, context: AccountContext)
    case starsTopup(link: String, amount: Int64, purpose: String, context: AccountContext)
    case multigift(link: String, context: AccountContext)
    case nft(link: String, slug: String, context: AccountContext)
    case joinCall(link: String, slug: String, context: AccountContext)
    case starsInfo(link: String, context: AccountContext, isTon: Bool)
    case auction(link: String, slug: String, context: AccountContext)
    case oauth(link: String, token: String, context: AccountContext)
    case createBot(link: String, context: AccountContext, managerUsername: String, botUsername: String, title: String?)
    case addStyle(link: String, slug: String, context: AccountContext)
    var link: String {
        switch self {
        case let .noPaidMessagesToken(link, _, _, _, _), let .contactToken(link, _, _, _, _):
            return link
        case let .external(link,_):
            if link.hasPrefix("mailto:") {
                return link.replacingOccurrences(of: "mailto:", with: "")
            }
            return link
        case let .peerInfo(link, _, _, _, _, _):
            return link
        case let .comments(link, _, _, _, _):
            return link
        case let .topic(link, _, _, _, _):
            return link
        case let .followResolvedName(link, _, _, _, _, _, _):
            return link
        case let .inviteBotToGroup(link, _, _, _, _, _, _):
            return link
        case let .botCommand(link, _), let .callback(link, _), let .code(link, _), let .hashtag(link, _):
            return link
        case let .shareUrl(link, _, _, _):
            return link
        case let .joinchat(link, _, _, _):
            return link
        case let .stickerPack(link, _, _, _):
            return link
        case let .confirmPhone(link, _, _, _):
            return link
        case let .socks(link, _, _, _):
            return link
        case let .requestSecureId(link, _, _):
            return link
        case let .unsupportedScheme(link, _, _):
            return link
        case let .applyLocalization(link, _, _):
            return link
        case let .wallpaper(link, _, _):
            return link
        case let .theme(link, _, _):
            return link
        case let .tonTransfer(link, _, _):
            return link
        case let .sendGrams(link, _, _):
            return link
        case let .instantView(link, _, _):
            return link
        case let .settings(link, _, _):
            return link
        case let .joinGroupCall(link, _, _, _):
            return link
        case let .invoice(link, _, _):
            return link
        case let .premiumOffer(link, _, _):
            return link
        case let .restorePurchase(link, _):
            return link
        case let .urlAuth(link, _):
            return link
        case let .folder(link, _, _):
            return link
        case let .loginCode(link, _):
            return link
        case let .story(link, _, _, _, _):
            return link
        case let .boost(link, _, _):
            return link
        case let .gift(link, _, _):
            return link
        case let .multigift(link, _):
            return link
        case let .businessLink(link, _, _):
            return link
        case let .tonsite(link, _):
            return link
        case let .starsTopup(link, _, _, _):
            return link
        case let .nft(link, _, _):
            return link
        case let .joinCall(link, _, _):
            return link
        case let .starsInfo(link, _, _):
            return link
        case let .auction(link, _, _):
            return link
        case let .oauth(link, _, _):
            return link
        case let .createBot(link, _, _, _, _):
            return link
        case let .addStyle(link, _, _):
            return link
        case .nothing:
            return ""
        case .logout:
            return ""
        }
    }
}

func inApp(for url:NSString, context: AccountContext? = nil, peerId:PeerId? = nil, messageId: MessageId? = nil, openInfo:((PeerId, Bool, MessageId?, ChatInitialAction?)->Void)? = nil, hashtag:((String)->Void)? = nil, command:((String)->Void)? = nil, applyProxy:((ProxyServerSettings) -> Void)? = nil, confirm: Bool = false) -> inAppLink {

    let source = normalizedTelegramLinkQuery(url as String)
    if #available(macOS 10.15, *), let context, let walletContext = context.walletContext, WalletContext.isTonConnectUrl(source) {
        guard WalletConfiguration.with(appConfiguration: context.appConfiguration).isAvailable else {
            return .callback(source, { _ in
                showModalText(for: context.window, text: strings().inAppLinksWalletUnavailable)
            })
        }
        return .callback(source, { walletContext.processTonConnectUrl($0) })
    }

    let options = InAppLinkParsingOptions(
        peerId: peerId,
        messageId: messageId,
        urlAuthDomains: context.map { urlHandlingConfiguration(for: $0.appConfiguration).urlAuthDomains } ?? [],
        hasContext: context != nil,
        hasOpenInfo: openInfo != nil,
        hasHashtag: hashtag != nil,
        hasCommand: command != nil,
        hasApplyProxy: applyProxy != nil,
        confirm: confirm
    )
    switch parseInAppLink(url, options: options) {
    case let .external(link, confirm):
        return .external(link: link, confirm)
    case let .tonsite(link):
        guard let context else { return .nothing }
        return .tonsite(link: link, context: context)
    case let .followResolvedName(link, username, postId, forceProfile, action):
        guard let context, let openInfo else { return .nothing }
        return .followResolvedName(link: link, username: username, postId: postId, forceProfile: forceProfile, context: context, action: action.map(chatInitialAction), callback: openInfo)
    case let .contactToken(link, token, freeToken):
        guard let context, let openInfo else { return .nothing }
        return .contactToken(link: link, token: token, freeToken: freeToken, context: context, callback: openInfo)
    case let .noPaidMessagesToken(link, username, token):
        guard let context, let openInfo else { return .nothing }
        return .noPaidMessagesToken(link: link, username: username, token: token, context: context, callback: openInfo)
    case let .comments(link, username, threadId, commentId):
        guard let context else { return .nothing }
        return .comments(link: link, username: username, context: context, threadId: threadId, commentId: commentId)
    case let .topic(link, username, threadId, commentId):
        guard let context else { return .nothing }
        return .topic(link: link, username: username, context: context, threadId: threadId, commentId: commentId)
    case let .inviteBotToGroup(link, username, action, rights, isChannel):
        guard let context, let openInfo else { return .nothing }
        return .inviteBotToGroup(link: link, username: username, context: context, action: action.map(chatInitialAction), rights: rights, isChannel: isChannel, callback: openInfo)
    case let .botCommand(value):
        guard let command else { return .nothing }
        return .botCommand(value, command)
    case let .hashtag(value):
        guard let hashtag else { return .nothing }
        return .hashtag(value, hashtag)
    case let .shareUrl(link, url, text):
        guard let context else { return .nothing }
        return .shareUrl(link: link, context, url, text)
    case let .joinchat(link, invite):
        guard let context, let openInfo else { return .nothing }
        return .joinchat(link: link, invite, context: context, callback: openInfo)
    case let .stickerPack(link, source, peerId):
        guard let context else { return .nothing }
        return .stickerPack(link: link, stickerPackSource(source), context: context, peerId: peerId)
    case let .confirmPhone(link, phone, hash):
        guard let context else { return .nothing }
        return .confirmPhone(link: link, context: context, phone: phone, hash: hash)
    case .nothing:
        return .nothing
    case let .socks(link, settings):
        guard let context, let applyProxy else { return .nothing }
        return .socks(link: link, settings, context: context, applyProxy: applyProxy)
    case let .requestSecureId(link, value):
        guard let context else { return .nothing }
        return .requestSecureId(link: link, context: context, value: value)
    case let .unsupportedScheme(link, path):
        guard let context else { return .nothing }
        return .unsupportedScheme(link: link, context: context, path: path)
    case let .applyLocalization(link, value):
        guard let context else { return .nothing }
        return .applyLocalization(link: link, context: context, value: value)
    case let .wallpaper(link, preview):
        guard let context else { return .nothing }
        return .wallpaper(link: link, context: context, preview: preview)
    case let .theme(link, name):
        guard let context else { return .nothing }
        return .theme(link: link, context: context, name: name)
    case let .tonTransfer(link, data):
        guard let context else { return .nothing }
        if #available(macOS 10.15, *), WalletContext.transferAddress(from: link) == nil {
            return .nothing
        }
        return .tonTransfer(link: link, context: context, data: data)
    case let .sendGrams(link, data):
        guard let context else { return .nothing }
        return .sendGrams(link: link, context: context, data: data)
    case let .settings(link, section):
        guard let context else { return .nothing }
        return .settings(link: link, context: context, section: section)
    case let .invoice(link, slug):
        guard let context else { return .nothing }
        return .invoice(link: link, context: context, slug: slug)
    case let .premiumOffer(link, ref):
        guard let context else { return .nothing }
        return .premiumOffer(link: link, ref: ref, context: context)
    case let .restorePurchase(link):
        guard let context else { return .nothing }
        return .restorePurchase(link: link, context: context)
    case let .urlAuth(link):
        guard let context else { return .nothing }
        return .urlAuth(link: link, context: context)
    case let .loginCode(link, code):
        return .loginCode(link: link, code: code)
    case let .folder(link, slug):
        guard let context else { return .nothing }
        return .folder(link: link, slug: slug, context: context)
    case let .story(link, username, storyId, messageId):
        guard let context else { return .nothing }
        return .story(link: link, username: username, storyId: storyId, messageId: messageId, context: context)
    case let .boost(link, username):
        guard let context else { return .nothing }
        return .boost(link: link, username: username, context: context)
    case let .gift(link, slug):
        guard let context else { return .nothing }
        return .gift(link: link, slug: slug, context: context)
    case let .businessLink(link, slug):
        guard let context else { return .nothing }
        return .businessLink(link: link, slug: slug, context: context)
    case let .starsTopup(link, amount, purpose):
        guard let context else { return .nothing }
        return .starsTopup(link: link, amount: amount, purpose: purpose, context: context)
    case let .multigift(link):
        guard let context else { return .nothing }
        return .multigift(link: link, context: context)
    case let .nft(link, slug):
        guard let context else { return .nothing }
        return .nft(link: link, slug: slug, context: context)
    case let .joinCall(link, slug):
        guard let context else { return .nothing }
        return .joinCall(link: link, slug: slug, context: context)
    case let .starsInfo(link, isTon):
        guard let context else { return .nothing }
        return .starsInfo(link: link, context: context, isTon: isTon)
    case let .auction(link, slug):
        guard let context else { return .nothing }
        return .auction(link: link, slug: slug, context: context)
    case let .oauth(link, token):
        guard let context else { return .nothing }
        return .oauth(link: link, token: token, context: context)
    case let .createBot(link, managerUsername, botUsername, title):
        guard let context else { return .nothing }
        return .createBot(link: link, context: context, managerUsername: managerUsername, botUsername: botUsername, title: title)
    case let .addStyle(link, slug):
        guard let context else { return .nothing }
        return .addStyle(link: link, slug: slug, context: context)
    }
}

private func stickerPackSource(_ source: ParsedStickerPack) -> StickerPackPreviewSource {
    switch source {
    case let .stickers(name):
        return .stickers(.name(name))
    case let .emoji(name):
        return .emoji(.name(name))
    }
}

private func chatInitialAction(_ action: ParsedChatLinkAction) -> ChatInitialAction {
    switch action {
    case let .start(parameter, behavior):
        return .start(parameter: parameter, behavior: behavior)
    case let .inputText(text, behavior):
        return .inputText(text: ChatTextInputState(inputText: text), behavior: behavior)
    case let .source(messageId, timecode):
        return .source(messageId, timecode)
    case let .joinVoiceChat(hash):
        return .joinVoiceChat(hash)
    case let .attachBot(bot, payload, choose):
        return .attachBot(bot, payload, choose)
    case let .makeWebview(appname, command):
        return .makeWebview(appname: appname, command: command)
    case let .album(album, mode):
        return .album(album: album, mode: mode == .stories ? .stories : .gifts)
    case let .openMedia(timecode):
        return .openMedia(timecode)
    case let .pollOption(data):
        return .pollOption(data)
    case .direct:
        return .direct
    }
}

func resolveInstantViewUrl(account: Account, url: String) -> Signal<inAppLink, NoError> {
    return webpagePreview(account: account, urls: [url]) |> filter { $0 != .progress } |> map { $0.result }
        |> mapToSignal { webpage -> Signal<inAppLink, NoError> in
            if let webpage = webpage {
                
                if case let .Loaded(content) = webpage.content {
                    if content.instantPage != nil {
                        var anchorValue: String?
                        if let anchorRange = url.range(of: "#") {
                            let anchor = url[anchorRange.upperBound...]
                            if !anchor.isEmpty {
                                anchorValue = String(anchor)
                            }
                        }
                        return .single(.instantView(link: url, webpage: webpage, anchor: anchorValue))
                    } else {
                        return .single(.external(link: url, false))
                    }
                } else {
                    return .complete()
                }
            } else {
                return .single(.external(link: url, false))
            }
    }
}

extension NSMutableAttributedString {
    func detectLinks(type:ParsingType, onlyInApp: Bool = false, context:AccountContext? = nil, color:NSColor = theme.colors.link, openInfo:((PeerId, Bool, MessageId?, ChatInitialAction?)->Void)? = nil, hashtag:((String)->Void)? = nil, command:((String)->Void)? = nil, applyProxy:((ProxyServerSettings)->Void)? = nil, dotInMention: Bool = false) -> Void {
        let copy = detectedTextLinks(in: self.string, type: type, dotInMention: dotInMention).map { $0.range }

        self.beginEditing()
        for range in copy {
            var addLinkAttrs: Bool = false
            
            if range.location != NSNotFound {
                let sublink = (self.string as NSString).substring(with: range)
                if let context = context {
                    let link = inApp(for: sublink as NSString, context: context, openInfo: openInfo, hashtag: hashtag, command: command, applyProxy: applyProxy)
                    if onlyInApp {
                        switch link {
                        case let .external(link, _):
                            let allowed = ["telegram.org", "telegram.dog", "telegram.me", "telegra.ph", "telesco.pe"]
                            if let url = URL(string: link) {
                                if let host = url.host, allowed.contains(host) {
                                    self.addAttribute(NSAttributedString.Key.link, value: inAppLink.external(link: sublink, false), range: range)
                                    addLinkAttrs = true
                                } else if allowed.contains(link) {
                                    self.addAttribute(NSAttributedString.Key.link, value: inAppLink.external(link: sublink, false), range: range)
                                    addLinkAttrs = true
                                }
                            } else {
                                continue
                            }
                        default:
                            self.addAttribute(NSAttributedString.Key.link, value: link, range: range)
                            addLinkAttrs = true
                        }
                    } else {
                        self.addAttribute(NSAttributedString.Key.link, value: link, range: range)
                        addLinkAttrs = true
                    }
                } else {
                    if !onlyInApp {
                        self.addAttribute(NSAttributedString.Key.link, value: inAppLink.external(link: sublink, false), range: range)
                        addLinkAttrs = true
                    }
                }
                if addLinkAttrs {
                    self.addAttribute(NSAttributedString.Key.foregroundColor, value: color, range: range)
                    self.addAttribute(.cursor, value: NSCursor.pointingHand, range: range)
                }
            }
            
        }
        self.endEditing()
        
    }
    
}
