import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import ChatListUI
import CrashReports
import ApiCredentials

extension FWDNavigationAction: @retroactive ChatListForwardAction {

}

extension PeerInfoController: @retroactive ChatListPeerInfoController {

}

extension ChatController: @retroactive ChatListChatController {

}

private let crashReportStore = CrashReportStore(handledKey: "crashReports.handledUntil." + ApiEnvironment.prefix)

private var crashReportSource: String {
    #if APP_STORE
    return "appstore"
    #elseif STABLE
    return "stable"
    #elseif BETA
    return "beta"
    #elseif ALPHA
    return "alpha"
    #elseif GITHUB
    return "github"
    #else
    return "debug"
    #endif
}

private func crashReportIcon() -> CGImage? {
    var rect = NSMakeRect(0, 0, 60, 60)
    return NSApp.applicationIconImage?.cgImage(forProposedRect: &rect, context: nil, hints: nil)
}

private func sendCrashReports(_ reports: [CrashReport], context: AccountContext) {
    _ = (context.engine.peers.resolvePeerByName(name: crashReportsBotUsername, referrer: nil) |> filter { $0 != .progress } |> take(1) |> deliverOnMainQueue).start(next: { result in
        guard let peer = result.result else {
            showModalText(for: context.window, text: strings().crashReportCouldNotOpenBot(crashReportsBotUsername))
            return
        }
        navigateToChat(navigation: context.bindings.rootNavigation(), context: context, chatLocation: .peer(peer.id), callback: { controller in
            let newest = reports.first
            let caption = NSAttributedString(string: strings().crashReportCaption(newest?.appVersion ?? "", newest?.buildVersion ?? "", crashReportSource))
            let preview = PreviewSenderController(urls: reports.map { $0.url }, chatInteraction: controller.chatInteraction, asMedia: false, attributedString: caption)
            showModal(with: preview, for: context.window)
        })
    })
}

private func mapChatListInAppLink(_ link: inAppLink) -> ChatListInAppLink {
    switch link {
    case let .followResolvedName(link, username, postId, forceProfile, context, action, callback):
        return .followResolvedName(link: link, username: username, postId: postId, forceProfile: forceProfile, context: context, action: action, callback: callback)
    default:
        return .other
    }
}

func installChatListUIHooks() {
    var hooks = ChatListUIHooks(makeShareLinkModal: { context, link in
        return ShareModalController(ShareLinkObject(context.concrete, link: link))
    }, pushPeerInfo: { navigation, context, peerId in
        PeerInfoController.push(navigation: navigation, context: context.concrete, peerId: peerId)
    }, makePremiumStatusController: { context, callback, peer in
        return PremiumStatusController(context.concrete, callback: callback, peer: peer)
    }, makeChatListFilterController: { context, filter in
        return ChatListFilterController(context: context.concrete, filter: filter)
    }, makeChatListFiltersListController: { context in
        return ChatListFiltersListController(context: context.concrete)
    }, filterContextMenuItems: { filter, unreadCount, allMuted, context in
        return filterContextMenuItems(filter, unreadCount: unreadCount, includeAllMuted: allMuted, context: context.concrete)
    }, makeAddContactModal: { context in
        return AddContactModalController(context.concrete)
    }, composeCreateGroup: { context in
        context?.concrete.composeCreateGroup()
    }, composeCreateSecretChat: { context in
        context?.concrete.composeCreateSecretChat()
    }, composeCreateChannel: { context in
        context?.concrete.composeCreateChannel()
    }, navigateToChat: { navigation, context, chatLocation, focusTarget, initialAction, additional, animated, navigationStyle in
        navigateToChat(navigation: navigation, context: context.concrete, chatLocation: chatLocation, focusTarget: focusTarget, initialAction: initialAction, additional: additional, animated: animated, navigationStyle: navigationStyle)
    }, makeChatController: { context, chatLocation, initialAction in
        return ChatController(context: context.concrete, chatLocation: chatLocation, initialAction: initialAction)
    }, makeChatControllerWithMode: { context, chatLocation, mode, holder in
        return ChatController(context: context.concrete, chatLocation: chatLocation, mode: mode, chatLocationContextHolder: holder)
    }, makeChatAdditionController: { context, chatLocation in
        return ChatAdditionController(context: context.concrete, chatLocation: chatLocation)
    }, makeChatAdditionControllerWithFocus: { context, chatLocation, focusTarget, initialAction in
        return ChatAdditionController(context: context.concrete, chatLocation: chatLocation, focusTarget: focusTarget, initialAction: initialAction)
    }, makeChatAdditionControllerWithMode: { context, chatLocation, mode in
        return ChatAdditionController(context: context.concrete, chatLocation: chatLocation, mode: mode)
    }, makeSharedFolderClosureController: { context, content in
        return SharedFolderClosureController(context: context.concrete, content: content)
    }, openPrivacySettings: { context in
        execute(inapp: .settings(link: "tg://settings/privacy", context: context.concrete, section: .privacy(nil)))
    }, appPasslock: {
        return (NSApp.delegate as? AppDelegate)?.passlock
    }, storyListViewClass: {
        return StoryListView.self
    }, makeCommunityListController: { context, communityId in
        return CommunityListController(context.concrete, communityId: communityId)
    }, externalContext: { peerId, accountId in
        return appDelegate?.supportAccountContextValue?.getExternalContext(peerId: peerId, accountId: accountId)
    }, updateGlobalPeer: { context in
        context.concrete.updateGlobalPeer()
    }, showFastChatSettings: { context in
        context.concrete.bindings.mainViewController.showFastChatSettings()
    }, chatListCollapseOrExpandArchive: { context in
        context.concrete.bindings.mainViewController.chatList.collapseOrExpandArchive()
    }, chatListToggleHideArchive: { context in
        context.concrete.bindings.mainViewController.chatList.toggleHideArchive()
    }, chatListSetAnimateGroupNextTransition: { context, groupId in
        context.concrete.bindings.mainViewController.chatList.setAnimateGroupNextTransition(groupId)
    }, chatListHidePromoItem: { context, peerId in
        context.concrete.bindings.mainViewController.chatList.hidePromoItem(peerId)
    }, openPeerInNewWindow: { context, peerId in
        let context = context.concrete
        context.sharedContext.openPeerInNewWindow(peerId: peerId, parent: context)
    }, chatListFilterId: { filter in
        return filter.id
    }, makeStickerHeaderItem: { initialSize, stableId, context, sticker, text, bgColor, isFullView in
        return AnimatedStickerHeaderItem(initialSize, stableId: stableId, context: context.concrete, sticker: sticker, text: text, bgColor: bgColor, isFullView: isFullView)
    }, inApp: { query, context, peerId, openInfo in
        return mapChatListInAppLink(inApp(for: query as NSString, context: context.concrete, peerId: peerId, openInfo: openInfo, hashtag: nil, command: nil, applyProxy: nil, confirm: false))
    }, makeForwardMessagesModal: { context, messages in
        return ShareModalController(ForwardMessagesObject(context.concrete, messages: messages))
    }, multigift: { context, selected, morphSource in
        multigift(context: context.concrete, selected: selected, morphSource: morphSource)
    }, makeTabBadgeNode: { context in
        return GlobalBadgeNode(context.account, sharedContext: context.concrete.sharedContext, dockTile: true, view: View(), removeWhenSidebar: true)
    }, makeTabAllBadgeNode: { context in
        return GlobalBadgeNode(context.account, sharedContext: context.concrete.sharedContext, collectAllAccounts: true, view: View(), applyFilter: false)
    }, makeSearchAdAboutController: { context in
        return SearchAdAboutController(context: context.concrete)
    }, navigateToChatWithCallback: { navigation, context, chatLocation, mode, focusTarget, initialAction, chatLocationContextHolder, additional, navigationStyle, callback in
        navigateToChat(navigation: navigation, context: context.concrete, chatLocation: chatLocation, mode: mode, focusTarget: focusTarget, initialAction: initialAction, chatLocationContextHolder: chatLocationContextHolder, additional: additional, navigationStyle: navigationStyle, callback: callback)
    }, mainEffectiveNavigation: { context in
        return context.concrete.bindings.mainViewController.effectiveNavigation
    }, makeChatListController: { context, modal, mode in
        return ChatListController(context.concrete, modal: modal, mode: mode)
    }, makeCreateForumTopicController: { context, peerId in
        return ForumTopicInfoController(context: context.concrete, purpose: .create, peerId: peerId)
    }, makeEditForumTopicController: { context, peerId, data, threadId in
        return ForumTopicInfoController(context: context.concrete, purpose: .edit(data, threadId), peerId: peerId)
    }, formatPhoneNumber: { context, number in
        return formatPhoneNumber(context: context.concrete, number: number)
    }, crashReportCard: { context in
        return crashReportStore.reports |> deliverOnMainQueue |> map { reports -> ChatListCrashReportCard? in
            guard let newest = reports.first else {
                return nil
            }
            let title = reports.count == 1 ? strings().crashReportCardTitle : strings().crashReportCardTitleTimesOther(reports.count)
            let info = strings().crashReportCardInfo
            return ChatListCrashReportCard(id: newest.incidentId, title: title, info: info, icon: crashReportIcon(), action: {
                crashReportStore.markHandled(reports)
                sendCrashReports(reports, context: context.concrete)
            }, dismiss: {
                crashReportStore.markHandled(reports)
            })
        }
    })
    hooks.navigateToChatWithContext = { navigation, context, chatLocation, mode, focusTarget, initialAction, holder, additional, style, callback in
        navigateToChat(navigation: navigation, context: context.concrete, chatLocation: chatLocation, mode: mode, focusTarget: focusTarget, initialAction: initialAction, chatLocationContextHolder: holder, additional: additional, navigationStyle: style, callback: callback)
    }
    ChatListUIHooks.install(hooks)
}
