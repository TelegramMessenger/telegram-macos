import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import CodeSyntax
import ChatUI

extension ChatInteraction {
    var context: AccountContext {
        return self.interactionContext as! AccountContext
    }
    var enqueueCodeSyntax: (MessageId, NSRange, String, String, SyntaxterTheme)->Void {
        get {
            let value = self.interactionEnqueueCodeSyntax
            return { messageId, range, code, language, theme in
                value(messageId, range, code, language, theme)
            }
        }
        set {
            self.interactionEnqueueCodeSyntax = { messageId, range, code, language, theme in
                newValue(messageId, range, code, language, theme as! SyntaxterTheme)
            }
        }
    }
}

extension SyntaxterTheme: @retroactive ChatInterfaceSyntaxTheme {

}

extension FWDNavigationAction: @retroactive ChatInterfaceForwardAction {

}

extension ShareInlineResultNavigationAction: @retroactive ChatInterfaceInlineResultAction {

}

private func mapChatInterfaceInAppLink(_ link: inAppLink) -> ChatInterfaceInAppLink {
    switch link {
    case let .external(link, confirm):
        return .external(link: link, confirm)
    case let .followResolvedName(link, username, postId, forceProfile, context, action, callback):
        return .followResolvedName(link: link, username: username, postId: postId, forceProfile: forceProfile, context: context, action: action, callback: callback)
    case let .joinchat(link, hash, context, callback):
        return .joinchat(link: link, hash, context: context, callback: callback)
    case let .wallpaper(link, context, preview):
        return .wallpaper(link: link, context: context, preview: preview)
    case let .theme(link, context, name):
        return .theme(link: link, context: context, name: name)
    case let .instantView(link, webpage, anchor):
        return .instantView(link: link, webpage: webpage, anchor: anchor)
    default:
        return .other
    }
}

func installChatInterfaceUIHooks() {
    installChatInterfaceHooks(ChatInterfaceHooks(freezeAlert: { context in
        guard let context = context as? AccountContext else {
            return
        }
        context.freezeAlert()
    }, resolveUsername: { username, context in
        guard let context = context as? AccountContext else {
            return .single(nil)
        }
        return resolveUsername(username: username, context: context)
    }, makeGroupCallPanelData: { context, peerId, isChannel, data in
        guard let context = context as? AccountContext else {
            return .single(nil)
        }
        return context.sharedContext.groupCallContext |> take(1) |> mapToSignalPromotingError { groupCallContext in
            return .single(GroupCallPanelData(peerId: peerId, isChannel: isChannel, info: data.info, topParticipants: data.topParticipants, participantCount: data.info.participantCount, activeSpeakers: [], groupCall: groupCallContext))
        }
    }, setChatInterfaceTempState: { context, state, peerId, threadId in
        guard let context = context as? AccountContext else {
            return
        }
        context.setChatInterfaceTempState(state, for: peerId, threadId: threadId)
    }, inputSource: { context in
        guard let context = context as? AccountContext else {
            preconditionFailure("input source requires a concrete AccountContext")
        }
        return context.sharedContext.inputSource
    }, executeUrl: { chatInteraction, url in
        execute(inapp: inApp(for: url.nsstring, context: chatInteraction.context, openInfo: chatInteraction.openInfo, hashtag: chatInteraction.modalSearch, command: chatInteraction.sendPlainText, applyProxy: chatInteraction.applyProxy))
    }, executeConfirmedUrl: { chatInteraction, url in
        execute(inapp: inApp(for: url.nsstring, context: chatInteraction.context, openInfo: chatInteraction.openInfo, hashtag: chatInteraction.modalSearch, command: chatInteraction.sendPlainText, applyProxy: chatInteraction.applyProxy, confirm: true))
    }, shareSwitchInlineQuery: { context, peerTypes, text in
        guard let context = context as? AccountContext else {
            return
        }
        let object = ShareCallbackPeerTypesObject(context, peerTypes: peerTypes, callback: { peerIds in
            if let peerId = peerIds.first {
                let controller = ChatAdditionController(context: context, chatLocation: .peer(peerId), initialAction: .inputText(text: .init(inputText: text), behavior: .automatic))
                context.bindings.rootNavigation().push(controller)
            }
            return .complete()
        })
        showModal(with: ShareModalController(object), for: context.window)
    }, showLoginWidgetConfirmation: { context, domain, bot, clientData, flags, subject, matchCodes, userIdHint in
        guard let context = context as? AccountContext else {
            return
        }
        let data = LoginWidgetData(
            domain: domain,
            bot: bot,
            clientData: clientData,
            flags: flags,
            subject: subject,
            matchCodes: matchCodes,
            userIdHint: userIdHint
        )
        showLoginWidgetConfirmation(context: context, sharedContext: context.sharedContext, data: data)
    }, makeNewPollController: { chatInteraction, isQuiz in
        return NewPollController(chatInteraction: chatInteraction, isQuiz: isQuiz)
    }, makeTopicIconFile: { title, iconColor, isGeneral in
        return ForumUI.makeIconFile(title: title, iconColor: iconColor, isGeneral: isGeneral)
    }, peerIsForum: { peer in
        return peer.isForum
    }, urlPreviewInAppLink: { detectedUrl, context in
        guard let context = context as? AccountContext else {
            return .other
        }
        let link = inApp(for: detectedUrl.nsstring, context: context, peerId: nil, openInfo: { _, _, _, _ in }, hashtag: { _ in }, command: { _ in }, applyProxy: { _ in }, confirm: false)
        return mapChatInterfaceInAppLink(link)
    }))
}
