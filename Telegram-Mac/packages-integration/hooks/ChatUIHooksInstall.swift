import AppAnalytics
import TelegramContext
import Cocoa
import CoreLocation
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import CodeSyntax
import CallsUI
import ChatUI
import ChatListUI
import WebAppUI
import ImageCanvasUI
import PeerInfoUI
import AvatarEditorUI

extension GlobalBadgeNode: @retroactive ChatUIBadgeNode {

}

private func mapChatUIEmojiSelectedItem(_ item: ChatUIEmojiSelectedItem) -> EmojiesSectionRowItem.SelectedItem {
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
    return EmojiesSectionRowItem.SelectedItem(source: source, type: type)
}

func installChatUIHooks() {
    ChatNavigationHooks.install(makeChatNavigationHooks())
    var hooks = ChatUIHooks(clearNotifies: { peerId, maxId in
        UNUserNotifications.current?.clearNotifies(peerId, maxId: maxId)
    }, closeEntertainmentPopover: { context in
        context.bindings.entertainmentViewController.closePopover()
    }, updateEntertainment: { context, chatInteraction in
        let controller = context.bindings.entertainmentViewController
        controller.update(with: chatInteraction)
        controller.prepareForPresentation()
    }, showMessageEffectsWindow: { context, peerId, selectedItems, react, view in
        let window = ReactionsWindowController(context.concrete, peerId: peerId, selectedItems: selectedItems.map(mapChatUIEmojiSelectedItem), react: react, moveTop: true, mode: .messageEffects)
        window.show(view)
    }, makeForwardMessagesShareModal: { context, messages, getMessages in
        return ShareModalController(ForwardMessagesObject(context.concrete, messages: messages, getMessages: getMessages))
    }, makeReplyForwardShareModal: { context, message, subject in
        return ShareModalController(ReplyForwardMessageObject(context.concrete, message: message, subject: subject))
    }, navigateToChat: { navigation, context, chatLocation in
        navigateToChat(navigation: navigation, context: context.concrete, chatLocation: chatLocation)
    }, navigateToChatWithFocus: { navigation, context, chatLocation, focusTarget, initialAction in
        navigateToChat(navigation: navigation, context: context.concrete, chatLocation: chatLocation, focusTarget: focusTarget, initialAction: initialAction)
    }, navigateToChatWithFocusAdditional: { navigation, context, chatLocation, focusTarget, initialAction, additional in
        navigateToChat(navigation: navigation, context: context.concrete, chatLocation: chatLocation, focusTarget: focusTarget, initialAction: initialAction, additional: additional)
    }, makeThreadPeerMediaController: { context, peerId, threadInfo, isBot in
        return PeerMediaController(context: context.concrete, peerId: peerId, threadInfo: threadInfo, isBot: isBot)
    }, makePeerMediaController: { context, peerId, isBot in
        return PeerMediaController(context: context.concrete, peerId: peerId, isBot: isBot)
    }, pushPeerInfo: { navigation, context, peerId, threadInfo, stories, mediaMode, albumId in
        PeerInfoController.push(navigation: navigation, context: context.concrete, peerId: peerId, threadInfo: threadInfo, stories: stories, mediaMode: mediaMode, albumId: albumId)
    }, showSingleStory: { context, storyId, initialId, emptyCallback in
        StoryModalController.ShowSingleStory(context: context.concrete, storyId: storyId, initialId: initialId, emptyCallback: emptyCallback)
    }, showStories: { context, isHidden, initialId, singlePeer in
        StoryModalController.ShowStories(context: context.concrete, isHidden: isHidden, initialId: initialId, singlePeer: singlePeer)
    }, showInlineAudioPlayer: { controller, context, tableView in
        let context = context.concrete
        let object = InlineAudioPlayerView.ContextObject(controller: controller, context: context, tableView: tableView, supportTableView: nil)
        context.sharedContext.showInlinePlayer(object)
    }, getAudioPlayer: { context in
        return context.concrete.sharedContext.getAudioPlayer()
    }, makeInlineAudioPlayerContextObject: { controller, context, tableView in
        return InlineAudioPlayerView.ContextObject(controller: controller, context: context.concrete, tableView: tableView, supportTableView: nil)
    }, makeSendAudioModal: { context, chatInteraction in
        return SendAudioModalController(context: context.concrete, chatInteraction: chatInteraction)
    }, makePreviewSender: { urls, chatInteraction, asMedia, attributedString, analyticsContext in
        return PreviewSenderController(urls: urls, chatInteraction: chatInteraction, asMedia: asMedia, attributedString: attributedString, analyticsContext: analyticsContext)
    }, removeChatInteractively: { context, peerId, userId in
        return removeChatInteractively(context: context.concrete, peerId: peerId, userId: userId, offerDeleteForAll: true)
    }, removeThreadInteractively: { context, peerId, threadId, userId in
        return removeChatInteractively(context: context.concrete, peerId: peerId, threadId: threadId, userId: userId, offerDeleteForAll: true)
    }, joinChannel: { context, peerId in
        joinChannel(context: context.concrete, peerId: peerId)
    }, requestOrJoinGroupCall: { context, peerId, joinAs, initialCall, initialInfo, joinHash, reference in
        return requestOrJoinGroupCall(context: context.concrete, peerId: peerId, joinAs: joinAs, initialCall: initialCall, initialInfo: initialInfo, joinHash: joinHash, reference: reference) |> map { result -> ChatGroupCallJoinResult in
            switch result {
            case let .success(callContext):
                return .success(callContext)
            case .fail:
                return .fail
            case let .samePeer(callContext):
                return .samePeer(callContext)
            }
        }
    }, createVoiceChat: { context, peerId in
        createVoiceChat(context: context.concrete, peerId: peerId)
    }, createVoiceChatCanBeScheduled: { context, peerId, canBeScheduled in
        createVoiceChat(context: context.concrete, peerId: peerId, canBeScheduled: canBeScheduled)
    }, makeCodeSyntaxKey: { messageId, range, language, theme in
        return CodeSyntaxKey(messageId: messageId, range: range, language: language, theme: theme as! SyntaxterTheme)
    }, highlightCodeSyntax: { code, language, theme in
        return CodeSyntax.syntax(code: code, language: language, theme: theme as! SyntaxterTheme)
    }, makeDiceRollController: { context, chatInteraction in
        return DiceRollController(context: context.concrete, interactions: chatInteraction)
    }, editForumTopic: { peerId, data, threadId, context in
        ForumUI.editTopic(peerId, data: data, threadId: threadId, context: context.concrete)
    }, openForum: { peerId, addition, context in
        ForumUI.open(peerId, addition: addition, context: context.concrete)
    }, createForumTopic: { peerId, context in
        ForumUI.createTopic(peerId, context: context.concrete)
    }, getGroupCallPanelData: { context, peerId in
        return getGroupCallPanelData(context: context.concrete, peerId: peerId)
    }, savedMessagesChatListItems: { peerId, account in
        return chatListViewForLocation(chatListLocation: .savedMessagesChats(peerId: peerId), location: .Initial(0, nil), filter: nil, account: account) |> map {
            return $0.list.items.reversed()
        }
    }, forumChatListItems: { peerId, account in
        return chatListViewForLocation(chatListLocation: .forum(peerId: peerId), location: .Initial(0, nil), filter: nil, account: account) |> map {
            return $0.list.items.reversed()
        }
    }, botForumChatListItems: { peerId, account in
        return chatListViewForLocation(chatListLocation: .forum(peerId: peerId), location: .Initial(0, nil), filter: nil, account: account) |> map {
            return $0.list.items.reversed()
        } |> map {
            $0.isEmpty ? nil : $0
        }
    }, createGroupDirectly: { context, selectedPeers in
        createGroupDirectly(with: context.concrete, selectedPeers: selectedPeers)
    }, openSpamBot: { context, callback in
        execute(inapp: inAppLink.followResolvedName(link: "@spambot", username: "spambot", postId: nil, forceProfile: false, context: context.concrete, action: nil, callback: callback))
    }, makeChatTitleBadgeNode: { context, excludePeerId, layoutChanged in
        return GlobalBadgeNode(context.account, sharedContext: context.concrete.sharedContext, excludePeerId: excludePeerId, view: View(), layoutChanged: layoutChanged)
    }, makeGroupBadgeNode: { context, excludeGroupId, layoutChanged in
        return GlobalBadgeNode(context.account, sharedContext: context.concrete.sharedContext, excludeGroupId: excludeGroupId, view: View(), layoutChanged: layoutChanged)
    }, generateLiveStreamBadge: { fontSize, outerColor in
        return generateLiveStreamBadge(fontSize: fontSize, outerColor: outerColor)
    }, showAboutCocoonModal: { context in
        showAboutCocoonModal(context: context.concrete)
    }, executeInAppLink: { url, context, openInfo in
        execute(inapp: inApp(for: url, context: context.concrete, openInfo: openInfo))
    }, appIsLocked: {
        return appDelegate?.isLocked()
    }, appIsLockedValue: {
        return appDelegate?.isLockedValue()
    }, makeChannelAdminModal: { context, peerId, adminId, initialParticipant in
        return ChannelAdminModalController(context.concrete, peerId: peerId, adminId: adminId, initialParticipant: initialParticipant, updated: { _ in }, upgradedToSupergroup: { _, _ in })
    })
    hooks.makeForwardMessagesShareModalWithContext = { context, messages, getMessages, analyticsContext in
        let object = ForwardMessagesObject(context.concrete, messages: messages, getMessages: getMessages, analyticsContext: analyticsContext)
        return ShareModalController(object, analyticsContext: analyticsContext)
    }
    hooks.makeForwardMessagesShareModalWithSource = { context, messages, getMessages, analyticsContext, entry in
        let object = ForwardMessagesObject(context.concrete, messages: messages, getMessages: getMessages, analyticsContext: analyticsContext)
        let controller = ShareModalController(object, analyticsContext: analyticsContext)
        controller.setAnalyticsForwardJourney(AnalyticsForwardPickerJourney(context: controller.analyticsContext ?? Analytics.shared.unresolvedContext(), entry: entry))
        return controller
    }
    hooks.attachForwardJourney = { controller, journey in
        if let controller = controller as? ShareModalController {
            controller.setAnalyticsForwardJourney(journey)
        } else {
            journey.discard()
        }
    }
    hooks.attachPreviewJourney = { controller, journey in
        if let controller = controller as? PreviewSenderController {
            controller.analyticsMediaJourney = journey
        } else {
            journey.discard()
        }
    }
    hooks.navigateToChatWithContext = { navigation, context, location, focus, action, additional, analyticsContext in
        navigateToChat(navigation: navigation, context: context.concrete, chatLocation: location, focusTarget: focus, initialAction: action, additional: additional, analyticsContext: analyticsContext)
    }
    hooks.makePeerMediaControllerWithContext = { context, peerId, thread, isBot, analyticsContext in
        PeerMediaController(context: context.concrete, peerId: peerId, threadInfo: thread, isBot: isBot, analyticsContext: analyticsContext)
    }
    hooks.pushPeerInfoWithContext = { navigation, context, peerId, thread, stories, mode, album, analyticsContext in
        PeerInfoController.push(navigation: navigation, context: context.concrete, peerId: peerId, threadInfo: thread, stories: stories, mediaMode: mode, albumId: album, analyticsContext: analyticsContext)
    }
    hooks.showSingleStoryWithContext = { context, storyId, initialId, emptyCallback, analyticsContext in
        StoryModalController.ShowSingleStory(context: context.concrete, storyId: storyId, initialId: initialId, emptyCallback: emptyCallback, analyticsContext: analyticsContext)
    }
    hooks.showStoriesWithContext = { context, isHidden, initialId, singlePeer, analyticsContext in
        StoryModalController.ShowStories(context: context.concrete, isHidden: isHidden, initialId: initialId, singlePeer: singlePeer, analyticsContext: analyticsContext)
    }
    hooks.bindPreviewSendValidation = { controller, isCurrent in
        guard let controller = controller as? PreviewSenderController else { return false }
        return controller.bindSendSourceValidation(isCurrent)
    }
    hooks.forumSidebarToggleImage = { open in
        open ? NSImage(resource: .iconMonoforumToggleFilled) : NSImage(resource: .iconMonoforumToggle)
    }
    hooks.addForumMembers = { context, peerId in selectForumMembers(context: context.concrete, peerId: peerId) }
    hooks.makeForumSidebarRows = { context, onSelect in
        ForumSidebarRowsView(context: context as! AccountContext, onSelect: onSelect)
    }
    hooks.updateForumSidebarPane = { context, owner, controller, open in
        if context.isExternal {
            appDelegate?.supportAccountContextValue?.setForumSidebar(context: context.concrete, owner: owner, controller: controller, open: open)
            return
        }
        appDelegate?.enumerateApplicationContexts { applicationContext in
            if applicationContext.context.window === context.window {
                applicationContext.setForumSidebar(owner: owner, controller: controller, open: open)
            }
        }
    }
    ChatUIHooks.install(hooks)
}


private func makeChatNavigationHooks() -> ChatNavigationHooks {
    var hooks = ChatNavigationHooks()
    hooks.widgetWalletAvailable = { context in
        guard #available(macOS 10.15, *), let context = context as? AccountContext else { return false }
        return widgetWalletAvailable(context)
    }
    hooks.openWidgetWallet = { context, message, call, complete in
        guard #available(macOS 10.15, *), let context = context as? AccountContext else { complete(.failure(.notAllowed)); return }
        openWidgetWallet(context: context, message: message, call: call, complete: complete)
    }
    hooks.showAddTonBalance = { context, amount, window in
        showModal(with: AddTonBalanceController(context: context, tonAmount: amount), for: window)
    }
    hooks.makeCalendarModal = { context, peerId, threadId, current, select in
        if threadId != nil || peerId.namespace == Namespaces.Peer.SecretChat {
            return PlainCalendarModalController(window: context.window, current: current, select: select)
        }
        return ChatCalendarController(context: context, peerId: peerId, current: current, select: select)
    }
    hooks.makeSearchCalendar = { context, peerId, threadId, current, select in
        return ChatCalendarSearchController(context: context, peerId: peerId, threadId: threadId, current: current, select: select)
    }
    hooks.makeBirthdayCalendar = { window, date in
        return CalendarController(NSMakeRect(0, 0, 300, 300), window, current: date, lowYear: 1900, canBeNoYear: true, selectHandler: { _ in }, autoclose: false)
    }
    hooks.makeDateSelector = { context, defaultDate, repeatPeriod, mode, selectedAt, infoText in
        let selectorMode: DateSelectorModalController.Mode
        switch mode {
        case let .schedule(peerId):
            selectorMode = .schedule(peerId)
        case let .date(title, doneTitle):
            selectorMode = .date(title: title, doneTitle: doneTitle)
        case let .dateAction(title, done, action):
            selectorMode = .dateAction(title: title, done: done, action: .init(string: action.string, callback: action.callback))
        }
        if let defaultDate {
            return DateSelectorModalController(context: context, defaultDate: defaultDate, repeatPeriod: repeatPeriod, mode: selectorMode, selectedAt: selectedAt, infoText: infoText)
        } else {
            return DateSelectorModalController(context: context, repeatPeriod: repeatPeriod, mode: selectorMode, selectedAt: selectedAt, infoText: infoText)
        }
    }
    hooks.showGigagroupLanding = { context, peerId, window in
        showModal(with: GigagroupLandingController(context: context, peerId: peerId), for: window)
    }
    hooks.pushGroupsInCommon = { context, peerId in
        context.bindings.rootNavigation().push(GroupsInCommonViewController(context: context, peerId: peerId, standalone: true))
    }
    hooks.pushGroupsInCommonWithContext = { context, peerId, analyticsContext in
        context.bindings.rootNavigation().push(GroupsInCommonViewController(context: context, peerId: peerId, standalone: true, analyticsContext: analyticsContext))
    }
    hooks.showInactiveChannelsOnJoin = { context in
        showInactiveChannels(context: context, source: .join)
    }
    hooks.showInactiveChannelsOnJoinWithContext = { context, analyticsContext in
        showInactiveChannels(context: context, source: .join, analyticsContext: analyticsContext)
    }
    hooks.showFrozenAccount = { context, window in
        showModal(with: FrozenAccountController(context: context), for: window)
    }
    hooks.pushMessageStats = { context, messageId in
        context.bindings.rootNavigation().push(MessageStatsController(context, subject: .messageId(messageId)))
    }
    hooks.pushMessageStatsWithContext = { context, messageId, analyticsContext in
        context.bindings.rootNavigation().push(MessageStatsController(context, subject: .messageId(messageId), analyticsContext: analyticsContext))
    }
    hooks.openHTMLPage = { context, url in
        BrowserStateContext.get(context).open(tab: .tonsite(url: url.absoluteString))
    }
    hooks.showVerifyAgeAlert = { context, window in
        showModal(with: VerifyAgeAlertController(context: context), for: window)
    }
    hooks.chatExportMenuTitle = {
        return chatExportMenuTitle()
    }
    hooks.showChatExport = { context, peer in
        showChatExportModal(context: context, peer: peer)
    }
    hooks.canExportChat = { peer, cachedData in
        return !chatExportIsRestricted(peer: peer, cachedData: cachedData)
    }
    hooks.makeRequestJoinMemberListController = { context, peerId, manager, openInviteLinks in
        return RequestJoinMemberListController(context: context, peerId: peerId, manager: manager, openInviteLinks: openInviteLinks)
    }
    hooks.makeInviteLinksController = { context, peerId, isChannel in
        return InviteLinksController(context: context, peerId: peerId, isChannel: isChannel, manager: nil)
    }
    hooks.showPaymentsReceipt = { context, messageId, invoice, window in
        showModal(with: PaymentsReceiptController(context: context, messageId: messageId, invoice: invoice), for: window)
    }
    hooks.showPaymentsCheckout = { context, messageId, invoice, window in
        showModal(with: PaymentsCheckoutController(context: context, source: .message(messageId), invoice: invoice), for: window)
    }
    hooks.showPaymentsReceiptWithContext = { context, messageId, invoice, window, analyticsContext in
        showModal(with: PaymentsReceiptController(context: context, messageId: messageId, invoice: invoice, analyticsContext: analyticsContext), for: window)
    }
    hooks.showPaymentsCheckoutWithContext = { context, messageId, invoice, window, analyticsContext in
        showModal(with: PaymentsCheckoutController(context: context, source: .message(messageId), invoice: invoice, analyticsContext: analyticsContext), for: window)
    }
    hooks.applyExternalProxy = { server, accountManager in
        applyExternalProxy(server, accountManager: accountManager)
    }
    hooks.makeProxyListController = { accountManager, network, push in
        return proxyListController(accountManager: accountManager, network: network, pushController: push)
    }
    hooks.showWallpaperPreview = { context, wallpaper, messageId, complete, window in
        showModal(with: WallpaperPreviewController(context, wallpaper: wallpaper, source: .message(messageId, nil), onComplete: { _ in
            complete()
        }), for: window)
    }
    hooks.showChatWallpaperSelector = { context, wallpaper, peer, complete, window in
        showModal(with: ChatWallpaperModalController(context, selected: wallpaper, source: .chat(peer, nil), onComplete: { _ in
            complete()
        }), for: window)
    }
    hooks.pushBusinessQuickReplies = { context in
        context.bindings.rootNavigation().push(BusinessQuickReplyController(context: context))
    }
    hooks.pushBusinessChatbot = { context in
        context.bindings.rootNavigation().push(BusinessChatbotController(context: context))
    }
    hooks.makeQuickReplyRowItem = { size, stableId, shortcut, context, query in
        return QuickReplyRowItem(size, stableId: stableId, reply: shortcut, context: context, editing: false, viewType: .legacy, open: { _ in
        }, editName: { _ in
        }, remove: { _ in
        }, selected: query)
    }
    hooks.showEditTagLabel = { context, reaction, label, window in
        showModal(with: EditTagLabelController(context: context, reaction: reaction, label: label), for: window)
    }
    hooks.showEditTagLabelWithContext = { context, reaction, label, window, analyticsContext in
        showModal(with: EditTagLabelController(context: context, reaction: reaction, label: label, analyticsContext: analyticsContext), for: window)
    }
    hooks.showUserTagInfo = { context, tag, authorName, groupName, badgeType, window in
        let config = UserTagInfoConfiguration(tag: tag, authorName: authorName, groupName: groupName, badgeType: badgeType, canEditRank: false)
        showModal(with: UserTagInfoModalController(context: context, configuration: config), for: window)
    }
    hooks.showUserTagInfoWithContext = { context, tag, authorName, groupName, badgeType, window, analyticsContext in
        let config = UserTagInfoConfiguration(tag: tag, authorName: authorName, groupName: groupName, badgeType: badgeType, canEditRank: false)
        showModal(with: UserTagInfoModalController(context: context, configuration: config, analyticsContext: analyticsContext), for: window)
    }
    hooks.showReportDetails = { context, reason, updated, window in
        showModal(with: ReportDetailsController(context: context, reason: reason, updated: updated), for: window)
    }
    hooks.reportSponsoredAd = { context, opaqueId, removeAd, window in
        _ = showModalProgress(signal: context.engine.messages.reportAdMessage(opaqueId: opaqueId, option: nil), for: window).startStandalone(next: { result in
            switch result {
            case .reported:
                showModalText(for: window, text: strings().chatMessageSponsoredReportAready)
            case .adsHidden:
                break
            case let .options(title, options):
                showComplicatedReport(context: context, title: title, info: strings().chatMessageSponsoredReportLearnMore, header: strings().chatMessageSponsoredReport, data: .init(subject: .list(options.map { .init(string: $0.text, id: $0.option) }), title: strings().chatMessageSponsoredReportOptionTitle), report: { report in
                    return context.engine.messages.reportAdMessage(opaqueId: opaqueId, option: report.id) |> `catch` { error in
                        return .single(.reported)
                    } |> deliverOnMainQueue |> map { result in
                        switch result {
                        case let .options(_, options):
                            return .init(subject: .list(options.map { .init(string: $0.text, id: $0.option) }), title: report.string)
                        case .reported:
                            showModalText(for: window, text: strings().chatMessageSponsoredReportSuccess)
                            removeAd()
                            return nil
                        case .adsHidden:
                            return nil
                        }
                    }
                })
            }
        }, error: { error in
            switch error {
            case .premiumRequired:
                prem(with: PremiumBoardingController(context: context, source: .no_ads, openFeatures: true), for: window)
            case .generic:
                break
            }
        })
    }
    hooks.reportMessages = { context, ids, title in
        reportComplicated(context: context, subject: .messages(ids), title: title)
    }
    hooks.selectChannelOwner = { context, peer, title, status in
        let behavior = SelectChannelOwnerBehavior(peerId: peer.id, peerChannelMemberContextsManager: context.peerChannelMemberCategoriesContextsManager, limit: 1)
        return selectModalPeers(window: context.window, context: context, title: title, status: status, limit: 1, behavior: behavior) |> map { selected in
            return selected.first.map { ($0, behavior.participants[$0]?.participant) }
        }
    }
    hooks.selectRichTextButtonUser = { context, title in
        return selectModalPeers(window: context.window, context: context, title: title, settings: [.contacts, .remote, .bots], limit: 1)
        |> mapToSignal { ids -> Signal<Peer?, NoError> in
            guard let id = ids.first, id.namespace == Namespaces.Peer.CloudUser else { return .single(nil) }
            return context.account.postbox.transaction { transaction -> Peer? in
                guard let peer = transaction.getPeer(id) as? TelegramUser else { return nil }
                return peer
            }
        }
    }
    hooks.selectSpecificPeer = { context, peerType, messageId, buttonId, maxQuantity in
        selectSpecificPeer(context: context, peerType: peerType, messageId: messageId, buttonId: buttonId, maxQuantity: maxQuantity)
    }
    hooks.pushTwoStepVerificationUnlock = { context, present in
        context.bindings.rootNavigation().push(twoStepVerificationUnlockController(context: context, mode: .access(nil), presentController: { value in
            present(value.controller, value.root, value.animated)
        }))
    }
    hooks.updateAccountBirthday = { date, context in
        editAccountUpdateBirthday(date, context: context)
    }
    hooks.makeEditAccountInfoItem = { size, stableId, account, state, updateText in
        let editState = EditInfoState(stateInited: state.stateInited, firstName: state.firstName, lastName: state.lastName, phone: state.phone, representation: state.representation, peer: state.peer, peerStatusSettings: state.peerStatusSettings, addToException: state.addToException, note: state.note)
        return EditAccountInfoItem(size, stableId: stableId, account: account, state: editState, viewType: .singleItem, updateText: updateText)
    }
    hooks.makeSelectColorController = { context, peer in
        return SelectColorController(context: context, peer: peer)
    }
    hooks.showAutoremoveMessages = { context, peer, window in
        showModal(with: AutoremoveMessagesController(context: context, peer: peer, onlyDelete: true), for: window)
    }
    hooks.generateChatThemeThumb = { palette, bubbled, backgroundMode in
        return generateChatThemeThumb(palette: palette, bubbled: bubbled, backgroundMode: backgroundMode)
    }
    hooks.showChatGallery = { context, message, delegate, interactions, type, reversed, chatMode, chatLocation, contextHolder, cachedPeerData in
        showChatGallery(context: context, message: message, delegate, interactions, type: galleryAppearType(type), reversed: reversed, chatMode: chatMode, chatLocation: chatLocation, contextHolder: contextHolder, cachedPeerData: cachedPeerData)
    }
    hooks.showChatGalleryWithContext = { context, message, delegate, interactions, type, reversed, chatMode, chatLocation, contextHolder, cachedPeerData, analyticsContext in
        showChatGallery(context: context, message: message, delegate, interactions, type: galleryAppearType(type), reversed: reversed, chatMode: chatMode, chatLocation: chatLocation, contextHolder: contextHolder, cachedPeerData: cachedPeerData, analyticsContext: analyticsContext)
    }
    hooks.showPhotosGallery = { context, peerId, firstStableId, delegate, interactions in
        showPhotosGallery(context: context, peerId: peerId, firstStableId: firstStableId, delegate, interactions)
    }
    hooks.showInstantViewGallery = { context, medias, firstIndex, firstStableId, parent, delegate, interactions in
        showInstantViewGallery(context: context, medias: medias, firstIndex: firstIndex, firstStableId: firstStableId, parent: parent, delegate, interactions)
    }
    hooks.showGalleryMedia = { context, medias, parent, firstIndex, firstStableId, delegate, interactions in
        showGalleryMedia(context: context, medias: medias, parent: parent, firstIndex: firstIndex, firstStableId: firstStableId, delegate, interactions)
    }
    hooks.roundToStandardQuality = { size in
        return roundToStandardQuality(size: size)
    }
    hooks.startPhoneCall = { context, peerId, isVideo in
        return (phoneCall(context: context, peerId: peerId, isVideo: isVideo) |> deliverOnMainQueue).start(next: { result in
            applyUIPCallResult(context, result)
        })
    }
    hooks.showJoinVoiceChatAlert = { context, data, peer, join, window in
        showModal(with: JoinVoiceChatAlertController(context: context, groupCall: data, peer: peer, join: join), for: window)
    }
    hooks.selectGroupCallJoiner = { context, peerId, completion in
        selectGroupCallJoiner(context: context, peerId: peerId, completion: completion)
    }
    hooks.applyGroupCallResult = { sharedContext, callContext in
        GroupCallUIHooks.shared.applyGroupCallResult(sharedContext, callContext)
    }
    hooks.showNewTodo = { chatInteraction, source, window, morphSource in
        let todoSource: NewTodoSourceType
        switch source {
        case .create:
            todoSource = .create
        case let .edit(message, taskId):
            todoSource = .edit(message, taskId: taskId)
        case let .addOption(message):
            todoSource = .addOption(message)
        }
        showModal(with: NewTodoController(chatInteraction: chatInteraction, source: todoSource), for: window, morphSource: morphSource)
    }
    hooks.showNewPoll = { chatInteraction, source, window, morphSource in
        let pollSource: NewPollSource
        switch source {
        case .new:
            pollSource = .new
        case let .addOption(messageId, existingOptions):
            pollSource = .addOption(messageId: messageId, existingOptions: existingOptions)
        }
        showModal(with: NewPollController(chatInteraction: chatInteraction, source: pollSource), for: window, morphSource: morphSource)
    }
    hooks.showPollResult = { context, message, option, window in
        showModal(with: PollResultController(context: context, message: message, scrollToOption: option), for: window)
    }
    hooks.pushMessagePollStats = { context, messageId in
        context.bindings.rootNavigation().push(MessagePollStatsController(context: context, messageId: messageId))
    }
    hooks.showLocationPreview = { context, map, peer, messageId, window in
        showModal(with: LocationModalPreview(context, map: map, peer: peer, messageId: messageId), for: window)
    }
    hooks.showLocationPicker = { chatInteraction, window, morphSource in
        showModal(with: LocationModalController(chatInteraction, analyticsContext: chatInteraction.captureAnalyticsContext()), for: window, morphSource: morphSource)
    }
    hooks.showLocationSelector = { chatInteraction, select, window in
        let picker = LocationModalController(chatInteraction, destination: .select)
        picker.selectCallback = select
        showModal(with: picker, for: window)
    }
    hooks.showLocationSelectorWithContext = { chatInteraction, select, window, analyticsContext in
        let picker = LocationModalController(chatInteraction, destination: .select, analyticsContext: analyticsContext)
        picker.selectCallback = select
        showModal(with: picker, for: window)
    }
    let browserTabData: (ChatBrowserTab) -> BrowserTabData.Data = { tab in
        let data: BrowserTabData.Data
        switch tab {
        case let .webapp(bot, peerId, buttonText, url, payload, threadId, replyTo, fromMenu):
            data = .webapp(bot: bot, peerId: peerId, buttonText: buttonText, url: url, payload: payload, threadId: threadId, replyTo: replyTo, fromMenu: fromMenu)
        case let .simple(bot, url, buttonText, source):
            data = .simple(bot: bot, url: url, buttonText: buttonText, source: source)
        case let .straight(bot, peerId, title, result):
            data = .straight(bot: bot, peerId: peerId, title: title, result: result)
        case let .instantView(url, webPage, anchor):
            data = .instantView(url: url, webPage: webPage, anchor: anchor)
        case let .game(url, peerId, messageId):
            data = .game(url: url, peerId: peerId, messageId: messageId)
        }
        return data
    }
    hooks.openBrowserTab = { context, tab in
        BrowserStateContext.get(context).open(tab: browserTabData(tab))
    }
    hooks.openBrowserTabWithContext = { context, tab, analyticsContext in
        BrowserStateContext.get(context).open(tab: browserTabData(tab), analyticsContext: analyticsContext)
    }
    hooks.installAttachMenuBot = { context, peer, completion in
        installAttachMenuBot(context: context, peer: peer, completion: completion)
    }
    hooks.installAttachMenuBotWithContext = { context, peer, analyticsContext, completion in
        installAttachMenuBot(context: context, peer: peer, analyticsContext: analyticsContext, completion: completion)
    }
    hooks.openJoinChatBotWebView = { context, botId, url, queryId, joinedPeerId in
        openJoinChatBotWebView(context: context, botId: botId, url: url, queryId: queryId, joinedPeerId: joinedPeerId)
    }
    hooks.openJoinChatBotWebViewWithContext = { context, botId, url, queryId, joinedPeerId, analyticsContext in
        openJoinChatBotWebView(context: context, botId: botId, url: url, queryId: queryId, joinedPeerId: joinedPeerId, analyticsContext: analyticsContext)
    }
    hooks.makeInlineWebViewRowItem = { size, text, url, account, callback in
        return ContextInlineWebViewRowItem(size, text: text, url: url, account: account, callback: callback)
    }
    hooks.openPhotoEditor = { context, image in
        let context = context as! AccountContext
        let resource: Signal<MediaResourceData, NoError>
        let isVideo: Bool
        let peerId = context.peerId
        if let video = image.videoRepresentations.last {
            resource = context.account.postbox.mediaBox.resourceData(video.resource)
            isVideo = true
        } else if let rep = image.representationForDisplayAtSize(.init(640, 640)) {
            resource = context.account.postbox.mediaBox.resourceData(rep.resource)
            isVideo = false
        } else {
            resource = .complete()
            isVideo = false
        }
        
        let photoDisposable = MetaDisposable()
        
        let updatePhoto:(Signal<NSImage, NoError>)->Void = { image in
            let signal = image |> mapToSignal {
                putToTemp(image: $0, compress: true)
            } |> deliverOnMainQueue
            _ = signal.start(next: { path in
                guard let controller = EditImageModalController(URL(fileURLWithPath: path), context: context, settings: .disableSizes(dimensions: .square, circle: true), doneString: strings().modalSet) else { return }
                showModal(with: controller, for: context.window, animationType: .scaleCenter)
                
                let updateSignal = controller.result |> map { path, _ -> TelegramMediaResource in
                    return LocalFileReferenceMediaResource(localFilePath: path.path, randomId: arc4random64())
                    } |> castError(UploadPeerPhotoError.self) |> mapToSignal { resource -> Signal<UpdatePeerPhotoStatus, UploadPeerPhotoError> in
                        return context.engine.accountData.updateAccountPhoto(resource: EngineMediaResource(resource), videoResource: nil, videoStartTimestamp: nil, markup: nil, mapResourceToAvatarSizes: { resource, representations in
                            return mapResourceToAvatarSizes(engine: context.engine, resource: resource, representations: representations)
                        })
                    } |> deliverOnMainQueue
                
                photoDisposable.set(updateSignal.start(next: { result in
                    switch result {
                    case .complete:
                        showModalText(for: context.window, text: strings().chatServiceSuggestSuccess)
                    default:
                        break
                    }
                }, error: { error in
                    showModalText(for: context.window, text: strings().unknownError)
                }))
            })
        }
        
        
            
        let updateVideo:(Signal<VideoAvatarGeneratorState, NoError>) -> Void = { signal in
                            
            let updateSignal: Signal<UpdatePeerPhotoStatus, UploadPeerPhotoError> = signal
            |> castError(UploadPeerPhotoError.self)
            |> mapToSignal { state in
                switch state {
                case .error:
                    return .fail(.generic)
                case .start:
                    return .next(.progress(0))
                case let .progress(value):
                    return .next(.progress(value * 0.2))
                case let .complete(thumb, video, keyFrame):
                    let (thumbResource, videoResource) = (LocalFileReferenceMediaResource(localFilePath: thumb, randomId: arc4random64(), isUniquelyReferencedTemporaryFile: true),
                                                          LocalFileReferenceMediaResource(localFilePath: video, randomId: arc4random64(), isUniquelyReferencedTemporaryFile: true))
                    return context.engine.peers.updatePeerPhoto(peerId: peerId, photo: context.engine.peers.uploadedPeerPhoto(resource: EngineMediaResource(thumbResource)), video: context.engine.peers.uploadedPeerVideo(resource: EngineMediaResource(videoResource)) |> map(Optional.init), videoStartTimestamp: keyFrame, mapResourceToAvatarSizes: { resource, representations in
                        return mapResourceToAvatarSizes(engine: context.engine, resource: resource, representations: representations)
                    }) |> map { result in
                        switch result {
                        case let .progress(current):
                            return .progress(0.2 + (current * 0.8))
                        default:
                            return result
                        }
                    }
                }
            } |> deliverOnMainQueue
            photoDisposable.set(updateSignal.start(next: { result in
                switch result {
                case .complete:
                    showModalText(for: context.window, text: strings().chatServiceSuggestSuccess)
                default:
                    break
                }
            }, error: { error in
                showModalText(for: context.window, text: strings().unknownError)
            }))
        }
        
        let data = resource |> filter { $0.complete } |> take(1)
        
        _ = showModalProgress(signal: data, for: context.window).start(next: { data in
            let ext: String
            if isVideo {
                ext = ".mp4"
            } else {
                ext = ".jpeg"
            }
            let path = NSTemporaryDirectory() + data.path.nsstring.lastPathComponent + ext
            
            try? FileManager.default.copyItem(atPath: data.path, toPath: path)
            
            if isVideo {
                selectVideoAvatar(context: context, path: path, localize: "", signal: { signal in
                    updateVideo(signal)
                })
            } else {
                if let image = NSImage(contentsOf: .init(fileURLWithPath: path)) {
                    updatePhoto(.single(image))
                }
            }
        })
    }
    hooks.setPeerPhoto = { context, peerId in
        let context = context as! AccountContext
        let photoDisposable = MetaDisposable()

        let applyUpdate: (Signal<UpdatePeerPhotoStatus, UploadPeerPhotoError>) -> Void = { signal in
            photoDisposable.set((signal |> deliverOnMainQueue).start(error: { _ in
                showModalText(for: context.window, text: strings().unknownError)
            }, completed: {
                resetPeerPhotos(peerId: peerId)
            }))
        }

        let updatePhoto: (Signal<NSImage, NoError>) -> Void = { image in
            let signal = image |> mapToSignal {
                putToTemp(image: $0, compress: true)
            } |> deliverOnMainQueue
            _ = signal.start(next: { path in
                guard let controller = EditImageModalController(URL(fileURLWithPath: path), context: context, settings: .disableSizes(dimensions: .square, circle: true), doneString: strings().modalSet) else { return }
                showModal(with: controller, for: context.window, animationType: .scaleCenter)

                let updateSignal: Signal<UpdatePeerPhotoStatus, UploadPeerPhotoError> = controller.result |> take(1) |> map { path, _ -> TelegramMediaResource in
                    return LocalFileReferenceMediaResource(localFilePath: path.path, randomId: arc4random64())
                } |> castError(UploadPeerPhotoError.self) |> mapToSignal { resource -> Signal<UpdatePeerPhotoStatus, UploadPeerPhotoError> in
                    return context.engine.peers.updatePeerPhoto(peerId: peerId, photo: context.engine.peers.uploadedPeerPhoto(resource: EngineMediaResource(resource)), mapResourceToAvatarSizes: { resource, representations in
                        return mapResourceToAvatarSizes(engine: context.engine, resource: resource, representations: representations)
                    })
                }
                applyUpdate(updateSignal)
            })
        }

        let updateVideo: (Signal<VideoAvatarGeneratorState, NoError>) -> Void = { signal in
            let updateSignal: Signal<UpdatePeerPhotoStatus, UploadPeerPhotoError> = signal
            |> castError(UploadPeerPhotoError.self)
            |> mapToSignal { state in
                switch state {
                case .error:
                    return .fail(.generic)
                case .start:
                    return .next(.progress(0))
                case let .progress(value):
                    return .next(.progress(value * 0.2))
                case let .complete(thumb, video, keyFrame):
                    let (thumbResource, videoResource) = (LocalFileReferenceMediaResource(localFilePath: thumb, randomId: arc4random64(), isUniquelyReferencedTemporaryFile: true),
                                                          LocalFileReferenceMediaResource(localFilePath: video, randomId: arc4random64(), isUniquelyReferencedTemporaryFile: true))
                    return context.engine.peers.updatePeerPhoto(peerId: peerId, photo: context.engine.peers.uploadedPeerPhoto(resource: EngineMediaResource(thumbResource)), video: context.engine.peers.uploadedPeerVideo(resource: EngineMediaResource(videoResource)) |> map(Optional.init), videoStartTimestamp: keyFrame, mapResourceToAvatarSizes: { resource, representations in
                        return mapResourceToAvatarSizes(engine: context.engine, resource: resource, representations: representations)
                    }) |> map { result in
                        switch result {
                        case let .progress(current):
                            return .progress(0.2 + (current * 0.8))
                        default:
                            return result
                        }
                    }
                }
            }
            applyUpdate(updateSignal)
        }

        filePanel(with: photoExts + videoExts, allowMultiple: false, canChooseDirectories: false, for: context.window, completion: { paths in
            if let path = paths?.first, let image = NSImage(contentsOfFile: path) {
                updatePhoto(.single(image))
            } else if let path = paths?.first {
                selectVideoAvatar(context: context, path: path, localize: "", signal: { signal in
                    updateVideo(signal)
                })
            }
        })
    }
    let editImageWithEvents: (any AccountContextProtocol, URL, EditedImageData?, AnalyticsContext, @escaping () -> Void, @escaping () -> Void) -> Signal<(URL, EditedImageData?), NoError> = { context, url, defaultData, analyticsContext, cancelled, dismissed in
        let presentation = analyticsContext.beginPresentation()
        let context = context as! AccountContext
        guard let controller = EditImageModalController(url, context: context, defaultData: defaultData) else {
            dismissed()
            return .complete()
        }
        controller.analyticsContext = analyticsContext
        controller.onCancelled = cancelled
        let onClose = controller.onClose
        controller.onClose = {
            onClose()
            dismissed()
        }
        let onDeinit = controller.onDeinit
        controller.onDeinit = {
            onDeinit?()
            dismissed()
            presentation.end()
        }
        showModal(with: controller, for: context.window, animationType: .scaleCenter)
        return controller.result
    }
    hooks.editImageWithEvents = editImageWithEvents
    hooks.editImageWithContext = { context, url, defaultData, analyticsContext in
        editImageWithEvents(context, url, defaultData, analyticsContext, {}, {})
    }
    hooks.editImage = { context, url, defaultData in
        editImageWithEvents(context, url, defaultData, Analytics.shared.unresolvedContext(), {}, {})
    }
    #if DEBUG
    hooks.showFirstGramsModal = { context, window in
        showFirstGramsModal(context: context, window: window)
    }
    #endif
    return hooks
}

private func galleryAppearType(_ type: ChatGalleryAppearType) -> GalleryAppearType {
    switch type {
    case .alone:
        return .alone
    case .history:
        return .history
    case let .profile(peerId):
        return .profile(peerId)
    case .secret:
        return .secret
    case .recentDownloaded:
        return .recentDownloaded
    case let .messages(messages):
        return .messages(messages)
    }
}

extension CalendarController: @retroactive ChatBirthdayCalendar {
}

extension QuickReplyRowItem: @retroactive ChatQuickReplyRow {
}

extension ChatInteraction: @retroactive LocationChatInteraction {
    public var locationContext: (any AccountContextProtocol) {
        return self.interactionContext
    }
    public var locationPeerId: PeerId {
        return self.peerId
    }
    public func sendPickedLocation(_ coordinate: CLLocationCoordinate2D, _ venue: MapVenue?) {
        self.sendLocation(coordinate, venue)
    }
}

extension ChatInteraction: @retroactive NewPollChatInteraction {
    public var pollContext: (any AccountContextProtocol) {
        return self.interactionContext
    }
    public var pollPeerId: PeerId {
        return self.peerId
    }
    public var pollMainPeer: Peer? {
        return self.presentation.mainPeer
    }
    public func sendPollMedias(_ medias: [Media], _ caption: ChatTextInputState, _ isCollage: Bool, _ additionText: ChatTextInputState?, _ silent: Bool, _ atDate: NewPollSchedule?, _ isSpoiler: Bool, _ messageEffect: AvailableMessageEffects.MessageEffect?, _ leadingText: Bool) {
        self.sendMedias(medias, caption, isCollage, additionText, silent, atDate.flatMap { ChatInteraction.Schedule(date: $0.date, repeatPeriod: $0.repeatPeriod) }, isSpoiler, messageEffect, leadingText)
    }
    public func appendPollOption(_ messageId: MessageId, _ option: TelegramMediaPollOption) {
        self.addPollOption(messageId, option)
    }
}

extension MediaPreviewEditControl: @retroactive ChatMediaEditControl {}
