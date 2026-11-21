import Cocoa
import TelegramCore

import SwiftSignalKit
import Postbox
import TGUIKit
import AvatarEditorUI
import TelegramContext
import TelegramUtils
import WebAppUI



protocol PeerInfoSection {
    var rawValue: UInt32 { get }
    func isEqual(to: PeerInfoSection) -> Bool
    func isOrderedBefore(_ section: PeerInfoSection) -> Bool
}

class PeerInfoState : Equatable {
    
    static func ==(lhs:PeerInfoState, rhs:PeerInfoState) -> Bool {
        return false
    }
}

protocol PeerInfoEntryStableId {
    func isEqual(to: PeerInfoEntryStableId) -> Bool
    var hashValue: Int { get }
}

struct IntPeerInfoEntryStableId: PeerInfoEntryStableId {
    let value: Int
    
    func isEqual(to: PeerInfoEntryStableId) -> Bool {
        if let to = to as? IntPeerInfoEntryStableId, to.value == self.value {
            return true
        } else {
            return false
        }
    }
    
    var hashValue: Int {
        return self.value.hashValue
    }
}



protocol PeerInfoEntry {
    var stableId: PeerInfoEntryStableId { get }
    func isEqual(to: PeerInfoEntry) -> Bool
    func isOrderedBefore(_ entry: PeerInfoEntry) -> Bool
    func item<C: AccountContextProtocol>(initialSize:NSSize, arguments:PeerInfoArguments<C>) -> TableRowItem
}


func peerInfoEntries<Context: AccountContextProtocol>(view: PeerView, threadData: MessageHistoryThreadData?, threadPeer: EnginePeer?, arguments: PeerInfoArguments<Context>, inputActivities: [PeerId: PeerInputActivity], channelMembers: [RenderedChannelParticipant], mediaTabsData: PeerMediaTabsData, inviteLinksCount: Int32, joinRequestsCount: Int32, availableReactions: AvailableReactions?, source: PeerInfoController<Context>.Source, stories: PeerExpiringStoryListContext.State?, personalChannel: UserInfoPersonalChannel?, revenueState: StarsRevenueStatsContextState?, tonRevenueState: StarsRevenueStatsContextState?, webAppPermissionsState: WebAppPermissionsState?, savedMuicProfileState: ProfileSavedMusicContext.State?, globalNotificationSettings: GlobalNotificationSettings) -> [PeerInfoEntry] {
    let mutedByDefault = peerViewMainPeer(view).map { !globalNotificationSettings.postboxAccessor.defaultIncludePeer($0) } ?? false
    if let threadData = threadData {
        return topicInfoEntries(view: view, threadData: threadData, threadPeer: threadPeer, arguments: arguments, mediaTabsData: mediaTabsData)
    } else if peerViewMainPeer(view) is TelegramUser {
        return userInfoEntries(view: view, arguments: arguments, mediaTabsData: mediaTabsData, source: source, stories: stories, personalChannel: personalChannel, revenueState: revenueState, tonRevenueState: tonRevenueState, webAppPermissionsState: webAppPermissionsState, savedMuicProfileState: savedMuicProfileState, mutedByDefault: mutedByDefault)
    } else if let channel = peerViewMainPeer(view) as? TelegramChannel {
        switch channel.info {
        case .broadcast:
            return channelInfoEntries(view: view, arguments: arguments, mediaTabsData: mediaTabsData, inviteLinksCount: inviteLinksCount, joinRequestsCount: joinRequestsCount, availableReactions: availableReactions, stories: stories, revenueState: revenueState, tonRevenueState: tonRevenueState, mutedByDefault: mutedByDefault)
        case .group:
            return groupInfoEntries(view: view, arguments: arguments, inputActivities: inputActivities, channelMembers: channelMembers, mediaTabsData: mediaTabsData, inviteLinksCount: inviteLinksCount, joinRequestsCount: joinRequestsCount, availableReactions: availableReactions, revenueState: revenueState, mutedByDefault: mutedByDefault)
        }
    } else if peerViewMainPeer(view) is TelegramGroup {
        return groupInfoEntries(view: view, arguments: arguments, inputActivities: inputActivities, mediaTabsData: mediaTabsData, inviteLinksCount: inviteLinksCount, joinRequestsCount: joinRequestsCount, availableReactions: availableReactions, revenueState: revenueState, mutedByDefault: mutedByDefault)
    }
    return []
}
