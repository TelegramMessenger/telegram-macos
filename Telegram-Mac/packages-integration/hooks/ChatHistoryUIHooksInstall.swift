import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import CodeSyntax
import RichTextEditorUI
import RichTextEditorCore
import ChatUI
import WalletContext
import WalletUI

extension ChatRowItem {
    var context: AccountContext {
        return self.itemContext as! AccountContext
    }
}

extension inAppLink: ChatHistoryInAppLinkValue {
    var chatHistoryInAppLink: ChatHistoryInAppLink {
        return mapChatHistoryInAppLink(self)
    }
}

extension ReactionsWindowController: @retroactive ChatHistoryReactionsWindow {
    public func showChatHistoryReactions(_ initialView: NSView & StickerFramesCollector) {
        self.show(initialView)
    }
}

extension ForwardMessagesObject: @retroactive ChatHistoryForwardMessagesObject {
    public func chatHistoryPerform(to peerIds: [PeerId], threadId: Int64?) -> Signal<Never, String> {
        return self.perform(to: peerIds, threadId: threadId)
    }

    public func chatHistoryPerformObserved(to peerId: PeerId, threadId: Int64?) -> Signal<ChatHistoryForwardResult, String> {
        return self.performObserved(to: peerId, threadId: threadId) |> map { result in
            switch result {
            case .draftPrepared: return .draftPrepared
            case .destinationReady: return .destinationReady
            case .accepted: return .accepted
            case .partiallyAccepted: return .partiallyAccepted
            case .rejected: return .rejected
            case .acceptanceUnknown: return .acceptanceUnknown
            case .sourceUnavailable: return .sourceUnavailable
            case .targetUnavailable: return .targetUnavailable
            case .restricted: return .restricted
            case .completionUnknown: return .completionUnknown
            }
        }
    }
}

extension AntiSpamBotConfiguration: @retroactive ChatHistoryAntiSpamBotConfiguration {

}

private func mapChatHistoryInAppLink(_ link: inAppLink) -> ChatHistoryInAppLink {
    switch link {
    case let .external(link, confirm):
        return .external(link: link, confirm)
    case let .followResolvedName(link, username, postId, forceProfile, context, action, callback):
        return .followResolvedName(link: link, username: username, postId: postId, forceProfile: forceProfile, context: context, action: action, callback: callback)
    case let .comments(link, username, context, threadId, commentId):
        return .comments(link: link, username: username, context: context, threadId: threadId, commentId: commentId)
    case let .joinchat(link, hash, context, callback):
        return .joinchat(link: link, hash, context: context, callback: callback)
    case let .wallpaper(link, context, preview):
        return .wallpaper(link: link, context: context, preview: preview)
    case let .folder(link, slug, context):
        return .folder(link: link, slug: slug, context: context)
    case let .story(link, username, storyId, messageId, context):
        return .story(link: link, username: username, storyId: storyId, messageId: messageId, context: context)
    case let .boost(link, username, context):
        return .boost(link: link, username: username, context: context)
    default:
        return .other
    }
}

private func mapChatHistoryEmojiSelectedItem(_ item: ChatHistoryEmojiSelectedItem) -> EmojiesSectionRowItem.SelectedItem {
    let source: EmojiesSectionRowItem.SelectedItem.Source
    switch item.source {
    case let .builtin(emoji):
        source = .builtin(emoji)
    case let .custom(fileId):
        source = .custom(fileId)
    }
    let type: EmojiesSectionRowItem.SelectedItem.Selection
    switch item.type {
    case .normal:
        type = .normal
    case .transparent:
        type = .transparent
    }
    return .init(source: source, type: type)
}

private func makeChatHistoryWalletHooks() -> Any? {
    if #available(macOS 10.15, *) {
        return ChatHistoryWalletHooks(walletContext: { context in
            return (context as! AccountContext).walletContext
        }, makeWalletTransactionController: { context, walletContext, data, timestamp, decryptComment in
            let walletContext = walletContext as! WalletContext
            return WalletTransactionController(context: context as! AccountContext, walletContext: walletContext, subject: .transaction(chatWalletTransaction(walletContext, data: data, timestamp: timestamp)), origin: .chat, decryptCommentOnOpen: decryptComment)
        }, makeWalletGramInfoController: { context, walletContext in
            return WalletInfoController(context: context as! AccountContext, walletContext: walletContext as! WalletContext, mode: .gram)
        }, makeCardView: { frame in
            return WalletChatCardView(frame: frame)
        }, resolveTonAddress: { context, walletContext, address in
            return walletTonAddressActions(context: context as! AccountContext, walletContext: walletContext as! WalletContext, address: address)
            |> map { actions in
                actions.map { ChatWalletTonAddress(owner: $0.owner, send: $0.send, openExplorer: $0.openExplorer) }
            }
        })
    } else {
        return nil
    }
}

@available(macOS 10.15, *)
private func chatWalletTransaction(_ walletContext: WalletContext, data: ChatServiceItem.WalletTransferData, timestamp: Int32) -> WalletContext.Transaction {
    let isLogicalTimeId = !data.transactionId.isEmpty && data.transactionId.allSatisfy(\.isNumber)
    let pendingPresentationId = data.operationId.map { "pending:\($0)" }
    let pendingTransactionId = data.pendingTransactionId.flatMap { $0.isEmpty ? nil : $0 }
    if let current = walletContext.stateValue.transactions.items.first(where: { candidate in
        if let pendingPresentationId, candidate.presentationId == pendingPresentationId {
            return true
        }
        if let pendingTransactionId, walletTransactionHashMatches(candidate.transactionHash, pendingTransactionId) {
            return true
        }
        guard !data.transactionId.isEmpty else {
            return false
        }
        return candidate.id == data.transactionId || walletTransactionHashMatches(candidate.transactionHash, data.transactionId) || (isLogicalTimeId && candidate.logicalTime == data.transactionId)
    }) {
        return current
    }
    let peer: WalletContext.Transaction.Peer
    if let enginePeer = data.peer, enginePeer.id.namespace == Namespaces.Peer.CloudUser, !enginePeer.id.isTelegramNotifications {
        peer = .user(enginePeer, address: data.peerAddress, domain: nil)
    } else if !data.peerAddress.isEmpty {
        peer = .address(data.peerAddress, domain: nil)
    } else {
        peer = .unsupported
    }
    if let operationId = data.operationId, !data.isIncoming {
        return WalletContext.Transaction(
            id: "pending:\(operationId)",
            logicalTime: "0",
            timestamp: timestamp,
            direction: .outgoing,
            amount: -data.amount,
            fee: 0,
            peer: peer,
            comment: data.comment,
            commentEncrypted: data.commentEncrypted,
            status: .pending
        )
    }
    let logicalTime = data.transactionId.split(separator: ":", maxSplits: 1).first.map(String.init) ?? data.transactionId
    return WalletContext.Transaction(
        id: data.transactionId,
        logicalTime: logicalTime,
        timestamp: timestamp,
        direction: data.isIncoming ? .incoming : .outgoing,
        amount: data.amount,
        fee: 0,
        peer: peer,
        comment: data.comment,
        commentEncrypted: data.commentEncrypted
    )
}

@available(macOS 10.15, *)
private func chatWalletTransferSnapshot(_ state: WalletContext.State) -> ChatWalletTransferSnapshot {
    return ChatWalletTransferSnapshot(transactions: state.transactions.items.map { transaction in
        let status: ChatWalletTransferSnapshot.TransactionStatus
        switch transaction.status {
        case .pending:
            status = .pending
        case .completed:
            status = .completed
        case .failed:
            status = .failed
        }
        return ChatWalletTransferSnapshot.Transaction(
            id: transaction.id,
            presentationId: transaction.presentationId,
            transactionHash: transaction.transactionHash,
            isOutgoingTransfer: transaction.direction == .outgoing && transaction.collectible == nil && transaction.kind == .transfer,
            status: status
        )
    }, pendingTransfers: state.pendingTransfers.map { pending in
        let status: ChatWalletTransferSnapshot.PendingStatus
        switch pending.status {
        case .broadcasting:
            status = .broadcasting
        case .pending:
            status = .pending
        case .submissionUnknown:
            status = .submissionUnknown
        case .confirmed:
            status = .confirmed
        }
        return ChatWalletTransferSnapshot.PendingTransfer(id: pending.id, transactionHash: pending.transactionHash, isCollectible: pending.collectibleAddress != nil, status: status)
    })
}

@available(macOS 10.15, *)
extension WalletContext: @retroactive ChatWalletContext {
    public func openChatTonConnectRequest(sessionId: Int64, messageId: MessageId) {
        self.openTonConnectRequest(sessionId: sessionId, messageId: messageId)
    }

    public var chatFiatRate: ChatWalletFiatRate? {
        let fiat = self.stateValue.fiat
        guard let rate = fiat.rates.currentValue?[fiat.selectedCurrency] else {
            return nil
        }
        return ChatWalletFiatRate(unitsPerGram: rate.unitsPerGram, currencySymbol: fiat.selectedCurrency.symbol)
    }

    public var chatFiatRateState: Signal<ChatWalletFiatRate?, NoError> {
        return self.state
        |> map { state -> ChatWalletFiatRate? in
            guard let rate = state.fiat.selectedRate else {
                return nil
            }
            return ChatWalletFiatRate(unitsPerGram: rate.unitsPerGram, currencySymbol: state.fiat.selectedCurrency.symbol)
        }
        |> distinctUntilChanged
    }

    public var chatTransferSnapshot: ChatWalletTransferSnapshot {
        return chatWalletTransferSnapshot(self.stateValue)
    }

    public var chatTransferState: Signal<ChatWalletTransferSnapshot, NoError> {
        return self.state |> map { chatWalletTransferSnapshot($0) }
    }
}

private func makeChatHistoryRichTextHooks() -> Any? {
    if #available(macOS 12, *) {
        return ChatHistoryRichTextHooks(blocksFromInAppPasteboard: {
            return richTextBlocksFromInAppPasteboard()
        }, installSyntaxHighlighter: { editor, theme in
            RichTextEditorCoordinator.installSyntaxHighlighter(on: editor, theme: theme)
        }, makeMediaContentView: { media, width, spoiler, context, interaction in
            return RichTextEditorCoordinator.makeMediaContentView(media: media, width: width, spoiler: spoiler, context: context, interaction: interaction)
        }, makeCollageTileView: { media, size, spoiler, context, interaction in
            return RichTextEditorCoordinator.makeCollageTileView(media: media, size: size, spoiler: spoiler, context: context, interaction: interaction)
        }, makeSliderView: { mediaIDs, width, media, context in
            return RichTextEditorCoordinator.makeSliderView(mediaIDs: mediaIDs, width: width, media: media, context: context)
        }, makeSpoilerEffect: {
            return RichEditorSpoilerEffect()
        })
    } else {
        return nil
    }
}

func installChatHistoryUIHooks() {
    var hooks = ChatHistoryUIHooks(peerInfoLink: { link, peerId, action, openChat, postId, callback in
        return inAppLink.peerInfo(link: link, peerId: peerId, action: action, openChat: openChat, postId: postId, callback: callback)
    }, followResolvedNameLink: { link, username, postId, forceProfile, context, action, callback in
        return inAppLink.followResolvedName(link: link, username: username, postId: postId, forceProfile: forceProfile, context: context as! AccountContext, action: action, callback: callback)
    }, botCommandLink: { command, callback in
        return inAppLink.botCommand(command, callback)
    }, codeLink: { code, callback in
        return inAppLink.code(code, callback)
    }, hashtagLink: { hashtag, callback in
        return inAppLink.hashtag(hashtag, callback)
    }, externalLink: { link, confirm in
        return inAppLink.external(link: link, confirm)
    }, giftLink: { link, slug, context in
        return inAppLink.gift(link: link, slug: slug, context: context as! AccountContext)
    }, inAppLink: { url, context, peerId, messageId, openInfo, hashtag, command, applyProxy, confirm in
        return inApp(for: url, context: context as? AccountContext, peerId: peerId, messageId: messageId, openInfo: openInfo, hashtag: hashtag, command: command, applyProxy: applyProxy, confirm: confirm)
    }, executeLink: { link in
        execute(inapp: link as! inAppLink)
    }, detectLinks: { string, type, onlyInApp, context, color, openInfo, hashtag, command, applyProxy, dotInMention in
        string.detectLinks(type: type, onlyInApp: onlyInApp, context: context as? AccountContext, color: color, openInfo: openInfo, hashtag: hashtag, command: command, applyProxy: applyProxy, dotInMention: dotInMention)
    }, copyContextText: { type in
        return copyContextText(from: type)
    }, applyCodeSyntax: { string, range, language, message, isIncoming, bubbled, isDark, textColor, fontSize, codeSyntaxData, loadCodeSyntax in
        if let language = language?.lowercased() {

            let themeKeys = generateSyntaxThemeParams(theme, bubbled: bubbled, isIncoming: isIncoming)

            let code = string.attributedSubstring(from: range).string
            let theme = SyntaxterTheme(dark: isDark, textColor: textColor, textFont: .code(fontSize), italicFont: .italicMonospace(fontSize), mediumFont: .semiboldMonospace(fontSize), themeKeys: themeKeys)!
            var cachedData: CodeSyntaxResult? = nil

            if let messageId = message?.id {
                cachedData = codeSyntaxData[.init(messageId: messageId, range: range, language: language, theme: theme)]
            } else {
                cachedData = .init(resut: CodeSyntax.syntax(code: code, language: language, theme: theme))
            }

            if let resut = cachedData?.resut {
                CodeSyntax.apply(resut, to: string, offset: range.location)
            } else if let messageId = message?.id {
                DispatchQueue.main.async {
                    loadCodeSyntax(messageId, range, code, language, theme)
                }
            }
        }
    }, generateSyntaxThemeParams: { presentationTheme, bubbled, isIncoming in
        return generateSyntaxThemeParams(presentationTheme, bubbled: bubbled, isIncoming: isIncoming)
    }, makeShareMessageModal: { context, message in
        return ShareModalController(ShareMessageObject(context as! AccountContext, message))
    }, makeShareGroupedMessagesModal: { context, message, messages in
        return ShareModalController(ShareMessageObject(context as! AccountContext, message, messages))
    }, pushReactionPeerInfo: { navigation, context, peerId, messageId in
        PeerInfoController.push(navigation: navigation, context: context as! AccountContext, peerId: peerId, source: .reaction(messageId))
    }, pushEditPeerInfo: { navigation, context, peerId in
        PeerInfoController.push(navigation: navigation, context: context as! AccountContext, peerId: peerId, initialState: .Edit)
    }, openTopic: { threadId, peerId, context, messageId in
        return ForumUI.openTopic(threadId, peerId: peerId, context: context as! AccountContext, messageId: messageId, animated: true, addition: true)
    }, makeChannelParticipantController: { context, peerId, participant in
        return ChannelParticipantController(context: context as! AccountContext, peerId: peerId, participant: participant)
    }, participantModerationMenuItems: { context, channel, member, participant in
        return channelParticipantModerationMenuItems(context: context, channel: channel, member: member, participant: participant)
    }, makeRestrictedModalController: { context, peerId, memberId, initialParticipant, updated in
        return RestrictedModalController(context as! AccountContext, peerId: peerId, memberId: memberId, initialParticipant: initialParticipant, updated: updated)
    }, makeChannelAdminModalController: { context, peerId, adminId, initialParticipant, updated, upgradedToSupergroup in
        return ChannelAdminModalController(context as! AccountContext, peerId: peerId, adminId: adminId, initialParticipant: initialParticipant, updated: updated, upgradedToSupergroup: upgradedToSupergroup)
    }, makeFragmentAdsInfoController: { context, message, interactions in
        return FragmentAdsInfoController(context: context as! AccountContext, message: message, interactions: interactions)
    }, makeRichMessageTranslateModal: { context, from, toLang, text, entities, messageId, richMessagePage, onToneChanged, translateEntireChat in
        return TranslateModalController(context: context as! AccountContext, from: from, toLang: toLang, text: text, entities: entities, canBreak: true, messageId: messageId, isRichMessage: true, richMessagePage: richMessagePage, dismissOnly: true, onToneChanged: onToneChanged, translateEntireChat: translateEntireChat)
    }, makePollTranslateModal: { context, from, toLang, text, entities, messageId, onToneChanged, translateEntireChat in
        return TranslateModalController(context: context as! AccountContext, from: from, toLang: toLang, text: text, entities: entities, canBreak: false, messageId: messageId, dismissOnly: true, onToneChanged: onToneChanged, translateEntireChat: translateEntireChat)
    }, makeMessageTranslateModal: { context, from, toLang, text, entities, messageId, onToneChanged, translateEntireChat in
        return TranslateModalController(context: context as! AccountContext, from: from, toLang: toLang, text: text, entities: entities, messageId: messageId, dismissOnly: true, onToneChanged: onToneChanged, translateEntireChat: translateEntireChat)
    }, makeSelectedTextTranslateModal: { context, from, toLang, text, entities, onToneChanged, translateEntireChat in
        return TranslateModalController(context: context as! AccountContext, from: from, toLang: toLang, text: text, entities: entities, dismissOnly: true, onToneChanged: onToneChanged, translateEntireChat: translateEntireChat)
    }, makeTranscriptionTranslateModal: { context, from, toLang, text, messageId, onToneChanged, translateEntireChat in
        return TranslateModalController(context: context as! AccountContext, from: from, toLang: toLang, text: text, messageId: messageId, dismissOnly: true, onToneChanged: onToneChanged, translateEntireChat: translateEntireChat)
    }, communityFilterCategories: { account in
        return communityFilterCategories(account: account)
    }, chatListFilterPredicate: { filter, communityCategories in
        return chatListFilterPredicate(for: filter, communityCategories: communityCategories)
    }, chatListFilterIsAllChats: { filter in
        return filter.isAllChats
    }, forumChatListItems: { peerId, account in
        return chatListViewForLocation(chatListLocation: .forum(peerId: peerId), location: .Initial(100, nil), filter: nil, account: account) |> filter {
            !$0.list.isLoading
        } |> map {
            $0.list.items
        }
    }, makeDownloadSearch: { context in
        context.bindings.mainViewController.makeDownloadSearch()
    }, folderEmoticonDrawable: { emoticon in
        return emoticon.drawable
    }, makeForwardMessagesObject: { context, messages, album, getMessages in
        return ForwardMessagesObject(context as! AccountContext, messages: messages, album: album, getMessages: getMessages)
    }, antiSpamBotConfiguration: { appConfiguration in
        return AntiSpamBotConfiguration.with(appConfiguration: appConfiguration)
    }, checkForUpdates: {
        (NSApp.delegate as? AppDelegate)?.checkForUpdates("")
    }, navigateToScheduledChat: { navigation, context, chatLocation in
        navigateToChat(navigation: navigation, context: context as! AccountContext, chatLocation: chatLocation, mode: .scheduled)
    }, requestPhoneCall: { context, peerId, isVideo in
        return (phoneCall(context: context, peerId: peerId, isVideo: isVideo) |> deliverOnMainQueue).start(next: { result in
            applyUIPCallResult(context, result)
        })
    }, joinConferenceCall: { context, initialInfo, reference in
        let context = context as! AccountContext
        return requestOrJoinConferenceCall(context: context, initialInfo: initialInfo, reference: reference).start(next: { result in
            switch result {
            case let .samePeer(callContext), let .success(callContext):
                applyGroupCallResult(context.sharedContext, callContext)
            default:
                alert(for: context.window, info: strings().errorAnError)
            }
        })
    }, storyLayoutViewSize: {
        return StoryLayoutView.size
    }, giftStickers: { context in
        return (context as! AccountContext).giftStickers
    }, messageNewReactions: { message, reaction, isTags in
        return message.newReactions(with: reaction, isTags: isTags)
    }, makeReactionsWindow: { context, peerId, selectedItems, orderedTags, react, reactLarge in
        return ReactionsWindowController(context as! AccountContext, peerId: peerId, selectedItems: selectedItems.map(mapChatHistoryEmojiSelectedItem), react: react, reactLarge: reactLarge, orderedTags: orderedTags)
    }, currencyAmount: { context, amount, comission in
        return (context as! AccountContext).amount(amount: amount, comission: comission)
    }, currentCountriesConfiguration: { context in
        return (context as! AccountContext).currentCountriesConfiguration
    }, reactionSettings: { context in
        return (context as! AccountContext).reactionSettings
    }, chatListFilterTitle: { filter in
        return filter.title
    }, showCommunityView: { context, communityId in
        showCommunityView(context, communityId: communityId)
    }, emptyChatControllerType: {
        return EmptyChatViewController.self
    }, wallet: makeChatHistoryWalletHooks(), richText: makeChatHistoryRichTextHooks())
    hooks.makeShareMessagesModalWithContext = { context, message, groupedMessages in
        let controller = ShareModalController(ShareMessageObject(context.concrete, message, groupedMessages ?? []))
        return controller
    }
    hooks.makeForwardMessagesObjectWithContext = { context, messages, album, getMessages in
        return ForwardMessagesObject(context.concrete, messages: messages, album: album, getMessages: getMessages)
    }
    hooks.pushReactionPeerInfoWithContext = { navigation, context, peerId, messageId in
        PeerInfoController.push(navigation: navigation, context: context.concrete, peerId: peerId, source: .reaction(messageId))
    }
    hooks.makeChannelParticipantControllerWithContext = { context, peerId, participant in
        return ChannelParticipantController(context: context.concrete, peerId: peerId, participant: participant)
    }
    hooks.makeTranslateModalWithContext = { context, from, toLang, text, entities, source, onToneChanged, translateEntireChat in
        switch source {
        case let .richMessage(id, page):
            return TranslateModalController(context: context.concrete, from: from, toLang: toLang, text: text, entities: entities, canBreak: true, messageId: id, isRichMessage: true, richMessagePage: page, dismissOnly: true, onToneChanged: onToneChanged, translateEntireChat: translateEntireChat)
        case let .poll(id):
            return TranslateModalController(context: context.concrete, from: from, toLang: toLang, text: text, entities: entities, canBreak: false, messageId: id, dismissOnly: true, onToneChanged: onToneChanged, translateEntireChat: translateEntireChat)
        case let .message(id):
            return TranslateModalController(context: context.concrete, from: from, toLang: toLang, text: text, entities: entities, messageId: id, dismissOnly: true, onToneChanged: onToneChanged, translateEntireChat: translateEntireChat)
        case .selectedText:
            return TranslateModalController(context: context.concrete, from: from, toLang: toLang, text: text, entities: entities, dismissOnly: true, onToneChanged: onToneChanged, translateEntireChat: translateEntireChat)
        case let .transcription(id):
            return TranslateModalController(context: context.concrete, from: from, toLang: toLang, text: text, messageId: id, dismissOnly: true, onToneChanged: onToneChanged, translateEntireChat: translateEntireChat)
        }
    }
    hooks.executeLinkWithContext = { link in
        execute(inapp: link as! inAppLink)
    }
    ChatHistoryUIHooks.install(hooks)
}

@available(macOS 10.15, *)
extension WalletChatCardView: @retroactive ChatWalletCardView {}
