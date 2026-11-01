import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import ChannelAdminUI

func installChannelAdminUIHooks() {
    ChannelAdminUIHooks.install(ChannelAdminUIHooks(messageWithUpdatedTimestamp: { message, timestamp in
        return message.withUpdatedTimestamp(timestamp)
    }, getAudioPlayer: { context in
        return (context as! AccountContext).sharedContext.getAudioPlayer()
    }, makeInlineAudioPlayerContextObject: { controller, context, tableView, supportTableView in
        return InlineAudioPlayerView.ContextObject(controller: controller, context: context as! AccountContext, tableView: tableView, supportTableView: supportTableView)
    }, showInlineAudioPlayer: { controller, context, tableView, supportTableView in
        let context = context as! AccountContext
        let object = InlineAudioPlayerView.ContextObject(controller: controller, context: context, tableView: tableView, supportTableView: supportTableView)
        context.sharedContext.showInlinePlayer(object)
    }, pushPeerInfo: { navigation, context, peerId in
        PeerInfoController.push(navigation: navigation, context: context as! AccountContext, peerId: peerId)
    }, participantModerationMenuItems: { context, channel, member, participant in
        return channelParticipantModerationMenuItems(context: context, channel: channel, member: member, participant: participant)
    }))
}
