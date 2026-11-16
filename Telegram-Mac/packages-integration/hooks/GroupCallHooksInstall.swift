import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import CallsUI
import TelegramCallsCore

func installGroupCallUIHooks() {
    GroupCallUIHooks.install(GroupCallUIHooks(groupCallThemeMembersColor: {
        return GroupCallTheme.membersColor
    }, groupCallThemeGrayStatusColor: {
        return GroupCallTheme.grayStatusColor
    }, groupCallThemeSpeakInactiveColor: {
        return GroupCallTheme.speakInactiveColor
    }, groupCallThemeSpeakLockedColor: {
        return GroupCallTheme.speakLockedColor
    }, groupCallThemeSpeakDisabledColor: {
        return GroupCallTheme.speakDisabledColor
    }, groupCallThemeCustomTheme: {
        return GroupCallTheme.customTheme
    }, groupCallThemeInviteIcon: {
        return GroupCallTheme.inviteIcon
    }, groupCallThemeShareIcon: {
        return GroupCallTheme.shareIcon
    }, requestOrJoinConferenceCall: { context, initialInfo, reference in
        return requestOrJoinConferenceCall(context: context.concrete, initialInfo: initialInfo, reference: reference) |> map { result -> GroupCallJoinResult in
            switch result {
            case let .success(callContext):
                return .success(callContext)
            case .fail:
                return .fail
            case let .samePeer(callContext):
                return .samePeer(callContext)
            }
        }
    }, applyGroupCallResult: { sharedContext, callContext in
        guard let callContext = callContext as? GroupCallContext else {
            return
        }
        applyGroupCallResult(sharedContext.concrete, callContext)
    }, makeRTMPStartController: { context, peerId, scheduleDate, completion in
        return RTMPStartController(context: context.concrete, peerId: peerId, scheduleDate: scheduleDate, completion: completion)
    }, makeShareLinkModal: { context, link, presentation, peerIds in
        return ShareModalController(ShareLinkObject(context.concrete, link: link, defaultSelectedIds: peerIds), presentation: presentation)
    }))
}
