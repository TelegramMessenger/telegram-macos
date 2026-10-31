import Cocoa
import TGUIKit
import UniqueGiftBackground
import AvatarEditorUI
import Postbox
import SwiftSignalKit
import TelegramCore
import ColorPalette
import TelegramMedia
import AlertsUI
import AudioPlayerCore
import AvatarUI
import ChatListUI
import EntertainmentUI
import GalleryUI
import GeneralRows
import InAppSettings
import LocalAnimations
import Localization
import PremiumStatusUI
import PremiumUI
import StarsUI
import TelegramContext
import TelegramTheme
import TelegramUtils
import InlineStickerLayer

private func profileButtonColor(over background: NSColor, isDark: Bool) -> NSColor {
    let base = background.usingColorSpace(.sRGB) ?? background
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    base.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    let blend: CGFloat = isDark ? 0 : 1
    let opacity: CGFloat = 0.25
    func overlay(_ channel: CGFloat) -> CGFloat {
        let value = channel < 0.5 ? 2 * channel * blend : 1 - 2 * (1 - channel) * (1 - blend)
        return channel + (max(0, min(1, value)) - channel) * opacity
    }
    return NSColor(srgbRed: overlay(red), green: overlay(green), blue: overlay(blue), alpha: 1)
}

private func actionItems<Context: AccountContextProtocol>(item: PeerInfoHeadItem<Context>, width: CGFloat, theme: TelegramPresentationTheme) -> [ActionItem] {
    
    var items:[ActionItem] = []
    
    var rowItemsCount: Int = 1
    
    let isColorfull = item.nameColor != nil
    let actionItemInset = ActionItem.actionItemInsetWidth(isColorfull: isColorfull)
    while width - (ActionItem.actionItemWidth + actionItemInset) > ((ActionItem.actionItemWidth * CGFloat(rowItemsCount)) + (CGFloat(rowItemsCount - 1) * actionItemInset)) {
        rowItemsCount += 1
    }
    rowItemsCount = min(rowItemsCount, 4)



    if let peer = item.peer as? TelegramUser, let arguments = item.arguments as? UserInfoArguments<Context>, peer.id != item.context.peerId {
        if !(item.peerView.peers[item.peerView.peerId] is TelegramSecretChat) {
            items.append(ActionItem(text: strings().peerInfoActionMessage, color: item.accentColor, image: theme.icons.profile_message, animation: .menu_show_message, action: arguments.sendMessage))
        }
        if peer.canCall, !isServicePeer(peer) && !peer.rawDisplayTitle.isEmpty {
            if let cachedData = item.peerView.cachedData as? CachedUserData, cachedData.voiceCallsAvailable {
                items.append(ActionItem(text: strings().peerInfoActionCall, color: item.accentColor, image: theme.icons.profile_call, animation: .menu_call, action: {
                    arguments.call(false)
                }))
            }
        }
        
        let videoConfiguration: VideoCallsConfiguration = VideoCallsConfiguration(appConfiguration: item.context.appConfiguration)
        
        let isVideoPossible: Bool
        switch videoConfiguration.videoCallsSupport {
        case .disabled:
            isVideoPossible = false
        case .full:
            isVideoPossible = true
        case .onlyVideo:
            isVideoPossible = true
        }
        
        
        
        
        if peer.canCall && peer.id != item.context.peerId, !isServicePeer(peer) && !peer.rawDisplayTitle.isEmpty, isVideoPossible {
            if let cachedData = item.peerView.cachedData as? CachedUserData, cachedData.videoCallsAvailable {
                items.append(ActionItem(text: strings().peerInfoActionVideoCall, color: item.accentColor, image: theme.icons.profile_video_call, animation: .menu_video_call, action: {
                    arguments.call(true)
                }))
            }
        }
        if peer.id != item.context.peerId {
            let value = item.peerView.notificationSettings?.isRemovedFromTotalUnreadCount(default: false) ?? false
            items.append(ActionItem(text: value ? strings().peerInfoActionUnmute : strings().peerInfoActionMute, color: item.accentColor, image: value ? theme.icons.profile_unmute : theme.icons.profile_mute, animation: .menu_mute, action: {
                arguments.toggleNotifications(value)
            }))
        }
        
        if !peer.isBot {
            
            let payStars = (item.peerView.cachedData as? CachedUserData)?.sendPaidMessageStars != nil
            if !(item.peerView.peers[item.peerView.peerId] is TelegramSecretChat), arguments.context.peerId != peer.id, !isServicePeer(peer) && !peer.rawDisplayTitle.isEmpty, !payStars {
                items.append(ActionItem(text: strings().peerInfoActionSecretChat, color: item.accentColor, image: theme.icons.profile_secret_chat, animation: .menu_lock, action: arguments.startSecretChat))
            }
            if peer.id != item.context.peerId, item.peerView.peerIsContact, peer.phone != nil {
                items.append(ActionItem(text: strings().peerInfoActionShare, color: item.accentColor, image: theme.icons.profile_share, animation: .menu_forward, action: arguments.shareContact))
            }
            if peer.id != item.context.peerId, !peer.isDeleted, let cachedData = item.peerView.cachedData as? CachedUserData {
                if cachedData.disallowedGifts != .All {
                    items.append(ActionItem(text: strings().peerInfoActionSendGift, color: item.accentColor, image: theme.icons.profile_share, animation: .menu_gift, action: {
                        arguments.giftPremium(cachedData.birthday?.isEligble == true)
                    }))
                }
            }
            if #available(macOS 10.15, *), item.context.appConfiguration.getBoolValue("wallet_available", orElse: false), item.peerView.peerId.namespace == Namespaces.Peer.CloudUser,
               peer.id != item.context.peerId, !peer.isDeleted, peer.botInfo == nil, !peer.flags.contains(.isSupport) {
                let context = item.context
                items.append(ActionItem(text: strings().peerInfoHeadItemSendMoney, color: item.accentColor, image: theme.icons.profile_share, animation: .menu_gram, action: {
                    guard PeerInfoUIHooks.shared.walletHooks.hasWallet(context) else {
                        return
                    }
                    PeerInfoUIHooks.shared.walletHooks.sendMoneyObserved(context, peer)
                }))
            }
            if !(item.peerView.peers[item.peerView.peerId] is TelegramSecretChat), let cachedData = item.peerView.cachedData as? CachedUserData {
                let copyProtectionEnabled = cachedData.flags.contains(.myCopyProtectionEnabled)
                items.append(ActionItem(text: copyProtectionEnabled ? strings().peerInfoCopyProtectionEnableSharing : strings().peerInfoCopyProtectionDisableSharing, color: item.accentColor, image: theme.icons.profile_share, animation: copyProtectionEnabled ? .menu_enable_sharing :  .menu_disable_sharing, action: {
                    if copyProtectionEnabled {
                        if !arguments.context.isPremium {
                            showModalText(for: arguments.context.window, text: strings().peerInfoCopyProtectionRequiresPremium, button: strings().alertLearnMore, callback: { _ in
                                prem(with: PremiumBoardingController(context: arguments.context, source: .noforwards, openFeatures: true), for: arguments.context.window)
                            })
                            return
                        }
                        let otherHasCopyProtection = cachedData.flags.contains(.copyProtectionEnabled)
                        if otherHasCopyProtection != copyProtectionEnabled {
                            verifyAlert_button(for: arguments.context.window, header: strings().peerInfoCopyProtectionEnableSharingConfirmHeader, information: strings().peerInfoCopyProtectionEnableSharingConfirmText(peer.displayTitle), ok: strings().peerInfoCopyProtectionEnableSharingConfirmOK, successHandler: { _ in
                                arguments.toggleCopyProtection(false)
                            })
                        } else {
                            arguments.toggleCopyProtection(false)
                        }
                    } else {
                        if FastSettings.disableSharingModalShownCountAndIncrement() >= 3 && arguments.context.isPremium {
                            if !arguments.context.isPremium {
                                showModalText(for: arguments.context.window, text: strings().peerInfoCopyProtectionRequiresPremium, button: strings().alertLearnMore, callback: { _ in
                                    prem(with: PremiumBoardingController(context: arguments.context, source: .noforwards, openFeatures: true), for: arguments.context.window)
                                })
                                return
                            }
                            arguments.toggleCopyProtection(true)
                        } else {
                            PeerInfoUIHooks.shared.showDisableSharingModal(arguments.context, peer.id, arguments.toggleCopyProtection)
                        }
                    }
                }))
            }
            if peer.id != item.context.peerId, let cachedData = item.peerView.cachedData as? CachedUserData, item.peerView.peerIsContact {
                items.append(ActionItem(text: (!cachedData.isBlocked ? strings().peerInfoBlockUser : strings().peerInfoUnblockUser), color: item.accentColor, image: !cachedData.isBlocked ? theme.icons.profile_block : theme.icons.profile_unblock, animation: cachedData.isBlocked ? .menu_unblock : .menu_restrict, destruct: true, action: {
                    arguments.updateBlocked(peer: peer, !cachedData.isBlocked, false)
                }))
            }
        } else if let botInfo = peer.botInfo {
            
            if peer.id != verifyCodePeerId, let cachedData = item.peerView.cachedData as? CachedUserData {
                items.append(ActionItem(text: !cachedData.isBlocked ? strings().peerInfoStopBot : strings().peerInfoRestartBot, color: item.accentColor, image: !cachedData.isBlocked ? theme.icons.profile_block : theme.icons.profile_unblock, animation: cachedData.isBlocked ? .menu_unblock : .menu_restrict, destruct: true, action: {
                    arguments.updateBlocked(peer: peer, !cachedData.isBlocked, true)
                }))
            }

            if let address = peer.addressName, !address.isEmpty {
                items.append(ActionItem(text: strings().peerInfoBotShare, color: item.accentColor, image: theme.icons.profile_share, animation: .menu_forward, action: {
                    arguments.botShare(address)
                }))
            }
            
            if botInfo.flags.contains(.worksWithGroups) {
                items.append(ActionItem(text: strings().peerInfoBotAddToGroup, color: item.accentColor, image: theme.icons.profile_more, animation: .menu_plus, action: arguments.botAddToGroup))
            }
           
            if let cachedData = item.peerView.cachedData as? CachedUserData, let cachedInfo = cachedData.botInfo {
                for command in cachedInfo.commands {
                    if command.text == "settings" {
                        items.append(ActionItem(text: strings().peerInfoBotSettings, color: item.accentColor, image: theme.icons.profile_more, animation: .menu_plus, action: arguments.botSettings))
                    }
                    if command.text == "help" {
                        items.append(ActionItem(text: strings().peerInfoBotHelp, color: item.accentColor, image: theme.icons.profile_more, animation: .menu_plus, action: arguments.botHelp))
                    }
                    if command.text == "privacy" {
                        items.append(ActionItem(text: strings().peerInfoBotPrivacy, color: item.accentColor, image: theme.icons.profile_more, animation: .menu_plus, action: arguments.botPrivacy))
                    }
                }
                if peer.id != verifyCodePeerId, botInfo.flags.contains(.canEdit) {
                    items.append(ActionItem(text: strings().peerInfoReportBot, color: item.accentColor, image: theme.icons.profile_report, animation: .menu_report, action: arguments.reportBot))
                }
                
                
            }
        }
        
    } else if let peer = item.peer, peer.isSupergroup || peer.isGroup, let arguments = item.arguments as? GroupInfoArguments<Context> {
        let access = peer.groupAccess
        
       
        if access.canAddMembers {
            items.append(ActionItem(text: strings().peerInfoActionAddMembers, color: item.accentColor, image: theme.icons.profile_add_member, animation: .menu_plus, action: {
                arguments.addMember(access.canCreateInviteLink)
            }))
        }
        if let value = item.peerView.notificationSettings?.isRemovedFromTotalUnreadCount(default: false) {
            items.append(ActionItem(text: value ? strings().peerInfoActionUnmute : strings().peerInfoActionMute, color: item.accentColor, image: value ? theme.icons.profile_unmute : theme.icons.profile_mute, animation: value ? .menu_unmuted : .menu_mute, action: {
                arguments.toggleNotifications(value)
            }))
        }
        if peer.isSupergroup {
            items.append(ActionItem(text: strings().peerInfoActionBoostGroup, color: item.accentColor, image: theme.icons.profile_boost, animation: .menu_boost, action: {
                arguments.boosts(peer.groupAccess)
            }))
            if peer.groupAccess.canEditGroupInfo {
                items.append(ActionItem(text: strings().peerInfoActionAcrhivedStories, color: item.accentColor, image: theme.icons.profile_archive, animation: .menu_archive, action: {
                    arguments.archiveStories()
                }))
            }
        }
       
        
        
        if let cachedData = item.peerView.cachedData as? CachedChannelData, let peer = peer as? TelegramChannel {
            if peer.groupAccess.canMakeVoiceChat {
                let isLiveStream = peer.isChannel || peer.flags.contains(.isGigagroup)
                items.append(ActionItem(text: isLiveStream ? strings().peerInfoActionLiveStream : strings().peerInfoActionVoiceChat, color: item.accentColor, image: theme.icons.profile_voice_chat, animation: .menu_video_chat, action: {
                    arguments.makeVoiceChat(cachedData.activeCall, callJoinPeerId: cachedData.callJoinPeerId)
                }))
            }
        } else if let cachedData = item.peerView.cachedData as? CachedGroupData {
            if peer.groupAccess.canMakeVoiceChat {
                items.append(ActionItem(text: strings().peerInfoActionVoiceChat, color: item.accentColor, image: theme.icons.profile_voice_chat, animation: .menu_call, action: {
                    arguments.makeVoiceChat(cachedData.activeCall, callJoinPeerId: cachedData.callJoinPeerId)
                }))
            }
        }
        
        if let cachedData = item.peerView.cachedData as? CachedChannelData {
            if cachedData.statsDatacenterId > 0, cachedData.flags.contains(.canViewStats) {
                items.append(ActionItem(text: strings().peerInfoActionStatistics, color: item.accentColor, image: theme.icons.profile_stats, animation: .menu_statistics, action: {
                    arguments.stats(cachedData.statsDatacenterId)
                }))
            } else if peer.isChannel, peer.isAdmin {
                items.append(ActionItem(text: strings().peerInfoActionStatistics, color: item.accentColor, image: theme.icons.profile_stats, animation: .menu_statistics, action: {
                    arguments.stats(0)
                }))
            }
        }
        if access.canReport {
            items.append(ActionItem(text: strings().peerInfoActionReport, color: item.accentColor, image: theme.icons.profile_report, animation: .menu_report, destruct: false, action: arguments.report))
        }
        
        
        if let group = peer as? TelegramGroup {
            if case .Member = group.membership {
                items.append(ActionItem(text: strings().peerInfoActionLeave, color: item.accentColor, image: theme.icons.profile_leave, animation: .menu_leave, destruct: true, action: arguments.delete))
            }
        } else if let group = peer as? TelegramChannel {
            if case .member = group.participationStatus {
                items.append(ActionItem(text: strings().peerInfoActionLeave, color: item.accentColor, image: theme.icons.profile_leave, animation: .menu_leave, destruct: true, action: arguments.delete))
            }
        }
        if peer.isGroup || peer.isSupergroup || peer.isGigagroup, peer.groupAccess.isCreator {
            items.append(ActionItem(text: strings().peerInfoActionDeleteGroup, color: item.accentColor, image: theme.icons.profile_leave, animation: .menu_delete, destruct: true, action: {
                arguments.delete(force: true)
            }))
        }
        
        
        
    } else if let peer = item.peer as? TelegramChannel, peer.isChannel, let arguments = item.arguments as? ChannelInfoArguments<Context> {
        
        
        if let monoforum = peer.linkedMonoforumId, !peer.isMonoForum {
            switch peer.participationStatus {
            case .member:
                items.append(ActionItem(text: strings().peerInfoActionMessage, color: item.accentColor, image: theme.icons.profile_message, animation: .menu_show_message, action: {
                    arguments.open_chat(monoforum)
                }))
            default:
                break
            }
            
        }
        
        if peer.participationStatus == .left {
            items.append(ActionItem(text: strings().peerInfoActionJoinChannel, color: item.accentColor, image: theme.icons.profile_join_channel, animation: .menu_channel, action: {
                arguments.join_channel()
            }))
        } else if peer.participationStatus == .member {
            items.append(ActionItem(text: strings().peerInfoActionOpenChannel, color: item.accentColor, image: theme.icons.profile_join_channel, animation: .menu_channel, action: {
                arguments.open_channel()
            }))
        }
        
        if let value = item.peerView.notificationSettings?.isRemovedFromTotalUnreadCount(default: false) {
            items.append(ActionItem(text: value ? strings().peerInfoActionUnmute : strings().peerInfoActionMute, color: item.accentColor, image: value ? theme.icons.profile_unmute : theme.icons.profile_mute, animation: value ? .menu_unmuted : .menu_mute, action: {
                arguments.toggleNotifications(value)
            }))
        }
        
        
        
        if let cachedData = item.peerView.cachedData as? CachedChannelData {
                        
            if cachedData.flags.contains(.starGiftsAvailable) {
                items.append(ActionItem(text: strings().peerInfoActionSendGift, color: item.accentColor, image: theme.icons.profile_share, animation: .menu_gift, action: arguments.giftPremium))
            }
            
            switch cachedData.linkedDiscussionPeerId {
            case let .known(peerId):
                if let peerId = peerId {
                    items.append(ActionItem(text: strings().peerInfoActionDiscussion, color: item.accentColor, image: theme.icons.profile_message, animation: .menu_show_message, action: { [weak arguments] in
                        arguments?.peerChat(peerId)
                    }))
                }
            default:
                break
            }
            
            if cachedData.statsDatacenterId > 0, cachedData.flags.contains(.canViewStats) {
                items.append(ActionItem(text: strings().peerInfoActionStatistics, color: item.accentColor, image: theme.icons.profile_stats, animation: .menu_statistics, action: {
                    arguments.stats(cachedData.statsDatacenterId, monetization: cachedData.flags.contains(.canViewRevenue), stars: cachedData.flags.contains(.canViewStarsRevenue))
                }))
            }
        }
        if let cachedData = item.peerView.cachedData as? CachedChannelData {
            if peer.groupAccess.canMakeVoiceChat {
                let isLiveStream = peer.isChannel || peer.flags.contains(.isGigagroup)
                items.append(ActionItem(text: isLiveStream ? strings().peerInfoActionLiveStream : strings().peerInfoActionVoiceChat, color: item.accentColor, image: theme.icons.profile_voice_chat, animation: .menu_video_chat, action: {
                    arguments.makeVoiceChat(cachedData.activeCall, callJoinPeerId: cachedData.callJoinPeerId)
                }))
            }
        }
        
        items.append(ActionItem(text: strings().peerInfoActionBoostChannel, color: item.accentColor, image: theme.icons.profile_boost, animation: .menu_boost, action: {
            arguments.boosts(peer.groupAccess)
        }))
        
        if peer.groupAccess.canEditGroupInfo {
            
            items.append(ActionItem(text: strings().peerInfoActionAcrhivedStories, color: item.accentColor, image: theme.icons.profile_archive, animation: .menu_archive, action: {
                arguments.archiveStories()
            }))
        }
        
        if let address = peer.addressName, !address.isEmpty {
            items.append(ActionItem(text: strings().peerInfoActionShare, color: item.accentColor, image: theme.icons.profile_share, animation: .menu_share, action: arguments.share))
        }
    
        if peer.groupAccess.canReport {
            items.append(ActionItem(text: strings().peerInfoActionReport, color: item.accentColor, image: theme.icons.profile_report, animation: .menu_report, action: arguments.report))
        }
        
        switch peer.participationStatus {
        case .member:
            items.append(ActionItem(text: strings().peerInfoActionLeave, color: item.accentColor, image: theme.icons.profile_leave, animation: .menu_leave, destruct: true, action: arguments.delete))
        default:
            break
        }
    } else if let arguments = item.arguments as? TopicInfoArguments<Context>, let data = arguments.threadData {
        
        let value = data.notificationSettings.isMuted
        
        items.append(ActionItem(text: value ? strings().peerInfoActionUnmute : strings().peerInfoActionMute, color: item.accentColor, image: value ? theme.icons.profile_unmute : theme.icons.profile_mute, animation: .menu_mute, action: {
            arguments.toggleNotifications(value)
        }))
        
        items.append(ActionItem(text: strings().peerInfoActionShare, color: item.accentColor, image: theme.icons.profile_share, animation: .menu_share, action: arguments.share))

    }
    
    if let cachedData = item.peerView.cachedData as? CachedChannelData, item.threadId == nil {
        let disabledTranslation = cachedData.flags.contains(.translationHidden)
        let canTranslate = item.context.sharedContext.baseSettings.translateChats
        
        if canTranslate && disabledTranslation {
            let item = ActionItem(text: strings().peerInfoTranslate, color: item.accentColor, image: theme.icons.profile_translate, animation: .menu_translate, action: { [weak item] in
                if let arguments = item?.arguments as? GroupInfoArguments<Context> {
                    arguments.enableTranslate()
                } else if let arguments = item?.arguments as? ChannelInfoArguments<Context> {
                    arguments.enableTranslate()
                }
            })
            if let index = items.firstIndex(where: { $0.destruct }) {
                items.insert(item, at: index)
            } else {
                items.append(item)
            }
        }
    }
    
    if items.count > rowItemsCount {
        var subItems:[SubActionItem] = []
        while items.count > rowItemsCount - 1 {
            let item = items.removeLast()
            let action = item.action
            subItems.insert(SubActionItem(text: item.text, animation: item.animation, destruct: item.destruct, action: action), at: 0)
        }
        if !subItems.isEmpty {
            items.append(ActionItem(text: strings().peerInfoActionMore, color: item.accentColor, image: theme.icons.profile_more, animation: .menu_plus, action: { }, subItems: subItems))
        }
    }
    
    return items
}

class PeerInfoHeadItem<Context: AccountContextProtocol>: GeneralRowItem {
    override var height: CGFloat {
        let insets = self.viewType.innerInset
        var height: CGFloat = 0
        
        if !editing {
            height = photoDimension + insets.bottom + nameLayout.layoutSize.height + statusLayout.layoutSize.height + insets.bottom
            
            if walletBalance != nil {
                height += PeerInfoBalanceView.spacing + PeerInfoBalanceView.height
            }
            if !items.isEmpty {
                let maxActionSize: NSSize = items.max(by: { $0.size.height < $1.size.height })!.size
                height += maxActionSize.height + insets.top
            }
            if self.threadId != nil {
                height += 50
            }
        } else {
            height = photoDimension
        }
        if nameColor != nil || editing {
            height += 20
        }
        if hasProfileStrip {
            height += PeerInfoMusicView.height(colorful: nameColor != nil)
            if nameColor == nil {
                height += 20
            }
        }
        height += 20
        return height
    }
    
    var peerColor: NSColor {
        if let nameColor = nameColor, threadId == nil, !editing {
            return context.peerNameColors.getProfile(nameColor).main
        } else {
            return NSColor(0xffffff, 0)
        }
    }
    
    var profileEmojiColor: NSColor {
        
        if let emojiStatus = peer?.emojiStatus {
            switch emojiStatus.content {
            case let .starGift(_, _, _, _, _, _, _, patternColor, _):
                if backgroundGradient.last!.lightness >= 0.2 {
                    return .init(UInt32(patternColor)).withAlphaComponent(0.5)
                } else {
                    return .init(UInt32(patternColor))
                }
            default:
                break
            }
        }
        
        let color: NSColor
        
        if let nameColor = nameColor, threadId == nil, !editing {
            color = context.peerNameColors.getProfile(nameColor).main
        } else {
            color = theme.colors.text
        }
        if color.lightness >= 0.2 {
            return color.withAlphaComponent(0.5)
        } else {
            return color
        }
    }
    var backgroundGradient: [NSColor] {
        if let emojiStatus = peer?.emojiStatus {
            switch emojiStatus.content {
            case let .starGift(_, _, _, _, _, innerColor, outerColor, _, _):
                return [NSColor(UInt32(innerColor)), NSColor(UInt32(outerColor))]
            default:
                break
            }
        }
        if let nameColor = nameColor, threadId == nil, !editing {
            let colors = context.peerNameColors.getProfile(nameColor)
            return [colors.main, colors.secondary ?? colors.main].compactMap { $0 }
        } else {
            return [NSColor(0xffffff, 0), NSColor(0xffffff, 0)]
        }
    }
    
    var hasBackgroundGradient: Bool {
        if let emojiStatus = peer?.emojiStatus {
            switch emojiStatus.content {
            case .starGift:
                return true
            default:
                break
            }
        }
        if nameColor != nil, threadId == nil, !editing {
            return true
        } else {
            return false
        }
    }
    
    var actionColor: NSColor {
        guard let nameColor = nameColor, threadId == nil, !editing else {
            return theme.colors.background
        }
        let base: NSColor
        if let emojiStatus = peer?.emojiStatus, case let .starGift(_, _, _, _, _, innerColor, outerColor, _, _) = emojiStatus.content {
            let inner = NSColor(rgb: UInt32(bitPattern: innerColor))
            let outer = NSColor(rgb: UInt32(bitPattern: outerColor))
            base = outer.interpolateTo(inner, fraction: 0.1) ?? outer
        } else {
            base = context.peerNameColors.getProfile(nameColor).main
        }
        return profileButtonColor(over: base, isDark: theme.colors.isDark)
    }
    
    var navigationButtonColor: NSColor? {
        guard let nameColor = nameColor, threadId == nil, !editing else {
            return nil
        }
        if let emojiStatus = peer?.emojiStatus, case .starGift = emojiStatus.content {
            return actionColor
        }
        let colors = context.peerNameColors.getProfile(nameColor)
        let outer = colors.secondary ?? colors.main
        return profileButtonColor(over: outer.interpolateTo(colors.main, fraction: 0.1) ?? outer, isDark: theme.colors.isDark)
    }
    
    var headerContainerView: NSView? {
        return (view as? GeneralContainableRowView)?.containerView
    }
    
    var giftStatusTitle: String? {
        if threadId == nil, !editing, let emojiStatus = peer?.emojiStatus, case let .starGift(_, _, title, _, _, _, _, _, _) = emojiStatus.content {
            return title
        }
        return nil
    }
    
    var giftTooltipColor: NSColor {
        let main: NSColor
        if let emojiStatus = peer?.emojiStatus, case let .starGift(_, _, _, _, _, innerColor, _, _, _) = emojiStatus.content {
            main = NSColor(rgb: UInt32(bitPattern: innerColor))
        } else if let nameColor = nameColor {
            main = context.peerNameColors.getProfile(nameColor).main
        } else {
            return actionColor
        }
        let boosted = main.withMultiplied(hue: 1, saturation: 2.2, brightness: 1.5).usingColorSpace(.sRGB) ?? main
        let secondary = boosted.interpolateTo(NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), fraction: 0.6) ?? boosted
        return secondary.interpolateTo(actionColor, fraction: 0.5) ?? secondary
    }
    
    var accentColor: NSColor {
        if let nameColor = nameColor, threadId == nil {
            let textColor = context.peerNameColors.getProfile(nameColor).main.lightness > 0.8 ? NSColor(0x000000) : NSColor(0xffffff)
            return textColor
        } else {
            return theme.colors.accent
        }
    }
    var textColor: NSColor {
        return PeerInfoHeadItem.textColor(peer, threadId: threadId, context: context)
    }
    var grayTextColor: NSColor {
        return PeerInfoHeadItem.grayTextColor(peer, threadId: threadId, context: context)
    }
    
    var nameColor: PeerNameColor? {
        return PeerInfoHeadItem.nameColor(peer)
    }
    
    static func nameColor(_ peer: Peer?) -> PeerNameColor? {
        if let emojiStatus = peer?.emojiStatus {
            switch emojiStatus.content {
            case let .starGift(_, _, _, _, _, innerColor, _, _, _):
                return .other(innerColor)
            default:
                break
            }
        }
        return peer?.profileColor
    }
    static func textColor(_ peer: Peer?, threadId: Int64?, context: Context) -> NSColor {
        if let nameColor = PeerInfoHeadItem.nameColor(peer), threadId == nil {
            let textColor = context.peerNameColors.getProfile(nameColor).main.lightness > 0.8 ? NSColor(0x000000) : NSColor(0xffffff)
            return textColor
        } else {
            return theme.colors.text
        }
    }
    static func grayTextColor(_ peer: Peer?, threadId: Int64?, context: Context) -> NSColor {
        if let nameColor = PeerInfoHeadItem.nameColor(peer), threadId == nil {
            let textColor = context.peerNameColors.getProfile(nameColor).main.lightness > 0.8 ? NSColor(0x000000) : NSColor(0xffffff)
            return textColor.withAlphaComponent(0.4)
        } else {
            if threadId != nil {
                return theme.colors.accent
            } else {
                return theme.colors.grayText
            }
        }
    }
    
    fileprivate var photoDimension:CGFloat {
        return self.threadData != nil ? 60 : 120
    }
    
    
    fileprivate var statusLayout: TextViewLayout
    fileprivate var nameLayout: TextViewLayout
    
    
    var effectivePeer: Peer? {
        return threadPeer?._asPeer() ?? peer
    }
    
    let context: Context
    let peer:Peer?
    let threadPeer: EnginePeer?
    let isVerified: Bool
    let isPremium: Bool
    let isScam: Bool
    let isFake: Bool
    let isMuted: Bool
    let peerView:PeerView
    let hasLiveStream: Bool
    
    let musicFile: TelegramMediaFile?
    let walletBalance: Int64?

    var hasProfileStrip: Bool {
        return !editing && musicFile != nil
    }
    
    let rating: TelegramStarRating?
    
    var result:PeerStatusStringResult {
        didSet {
            nameLayout = TextViewLayout(result.title, maximumNumberOfLines: 1)
            nameLayout.interactions = LinkHooks.shared.globalLinkExecutor()
            statusLayout = TextViewLayout(result.status, maximumNumberOfLines: 1, alwaysStaticItems: true)
        }
    }
    
    private(set) fileprivate var items: [ActionItem] = []
    
    private let fetchPeerAvatar = DisposableSet()
    private let onlineMemberCountDisposable = MetaDisposable()
    
    fileprivate let editing: Bool
    fileprivate let updatingPhotoState:PeerInfoUpdatingPhotoState?
    fileprivate let updatePhoto:(NSImage?, Control?)->Void
    fileprivate let arguments: PeerInfoArguments<Context>
    fileprivate let threadData: MessageHistoryThreadData?
    fileprivate let threadId: Int64?
    fileprivate let stories: PeerExpiringStoryListContext.State?
    fileprivate let avatarStoryComponent: AvatarStoryIndicatorComponent?
    let canEditPhoto: Bool
    
    var statusIsHidden: Bool {
        if let presence = peerView.peerPresences[arguments.peerId] as? TelegramUserPresence {
            switch presence.status {
            case let .lastMonth(isHidden), let .lastWeek(isHidden), let .recently(isHidden):
                return isHidden
            default:
                return false
            }
        }
        return false
    }
    
    
    let peerPhotosDisposable = MetaDisposable()
    
    let giftsContext: ProfileGiftsContext?
    let profileSavedMusic: ProfileSavedMusicContext?
    let savedMusic: ProfileSavedMusicContext.State?
    
    var photos: [TelegramPeerPhoto] = []
    init(_ initialSize:NSSize, stableId:AnyHashable, context: Context, arguments: PeerInfoArguments<Context>, peerView:PeerView, threadData: MessageHistoryThreadData?, threadId: Int64?, stories: PeerExpiringStoryListContext.State? = nil, viewType: GeneralViewType, editing: Bool, updatingPhotoState:PeerInfoUpdatingPhotoState? = nil, updatePhoto:@escaping(NSImage?, Control?)->Void = { _, _ in }, giftsContext: ProfileGiftsContext? = nil, threadPeer: EnginePeer? = nil, savedMusic: ProfileSavedMusicContext.State? = nil, profileSavedMusic: ProfileSavedMusicContext? = nil) {
        let peer = peerViewMainPeer(peerView)
        self.peer = peer
        self.threadPeer = threadPeer
        self.threadData = threadData
        self.peerView = peerView
        self.context = context
        self.editing = editing
        self.threadId = threadId
        self.giftsContext = giftsContext
        self.arguments = arguments
        self.stories = stories
        self.savedMusic = savedMusic
        self.profileSavedMusic = profileSavedMusic
        self.isVerified = peer?.isVerified ?? false
        self.isPremium = peer?.isPremium ?? false
        self.isScam = peer?.isScam ?? false
        self.isFake = peer?.isFake ?? false
        self.isMuted = peerView.notificationSettings?.isRemovedFromTotalUnreadCount(default: false) ?? false
        self.updatingPhotoState = updatingPhotoState
        self.updatePhoto = updatePhoto
        
        if !editing {
            self.musicFile = (peerView.cachedData as? CachedUserData)?.savedMusic
        } else {
            self.musicFile = nil
        }

        if #available(macOS 10.15, *), !editing, threadId == nil, let user = peer as? TelegramUser, peerView.peerId.namespace == Namespaces.Peer.CloudUser,
           user.id != context.peerId, let walletHooks = PeerInfoUIHooks.shared.wallet as? PeerInfoWalletHooks, walletHooks.hasWallet(context),
           let walletCard = (peerView.cachedData as? CachedUserData)?.walletCard, walletCard.balance >= 100_000_000 {
            self.walletBalance = walletCard.balance
        } else {
            self.walletBalance = nil
        }
        
        self.rating = (peerView.cachedData as? CachedUserData)?.starRating
        
        if let storyState = stories, !storyState.items.isEmpty {
            
            let colors: AvatarStoryIndicatorComponent.ActiveColors
            if let profileColor = peer?.profileColor {
                let color = context.peerNameColors.getProfile(profileColor)
                let values: [NSColor] = [color.main.lighter(), color.secondary ?? color.main.lighter().withAlphaComponent(0.8)]
                colors = .init(basic: values, close: values, stream: [NSColor(rgb: 0xFF3777), NSColor(rgb: 0xFF2D55)])
            } else {
                colors = .default
            }
            
            let compoment = AvatarStoryIndicatorComponent(state: storyState, presentation: theme, activeColors: colors, isRoundedRect: peer.map({ TelegramUtilsHooks.shared.peerIsForum($0) }) == true)
            self.avatarStoryComponent = compoment
            
            self.hasLiveStream = storyState.hasLiveItems
           
        } else {
            self.avatarStoryComponent = nil
            self.hasLiveStream = false
        }
        
        let canEditPhoto: Bool
        if let peer = peer as? TelegramUser {
            if peerView.peerIsContact {
                canEditPhoto = peer.photo.isEmpty
            } else if let botInfo = peer.botInfo {
                canEditPhoto = botInfo.flags.contains(.canEdit) 
            } else {
                canEditPhoto = false
            }
        } else if let _ = peer as? TelegramSecretChat {
            canEditPhoto = false
        } else if let peer = peer as? TelegramGroup {
            canEditPhoto = peer.groupAccess.canEditGroupInfo
        } else if let peer = peer as? TelegramChannel {
            canEditPhoto = peer.groupAccess.canEditGroupInfo
        } else {
            canEditPhoto = false
        }
        
        self.canEditPhoto = canEditPhoto && editing
        
        if let peer = peer, threadData == nil {
            if let peerReference = PeerReference(peer) {
                if let largeProfileImage = peer.largeProfileImage {
                    fetchPeerAvatar.add(fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .peer(peer.id), userContentType: .avatar, reference: .avatar(peer: peerReference, resource: largeProfileImage.resource)).start())
                }
                if let smallProfileImage = peer.smallProfileImage {
                    fetchPeerAvatar.add(fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .peer(peer.id), userContentType: .avatar, reference: .avatar(peer: peerReference, resource: smallProfileImage.resource)).start())
                }
            }
        }
        var result = stringStatus(for: peerView, context: context, theme: PeerStatusStringTheme(titleFont: .medium(.huge), titleColor: PeerInfoHeadItem.textColor(peer, threadId: threadId, context: context), statusFont: threadId != nil ? .medium(.text) : .normal(.text), statusColor: PeerInfoHeadItem.grayTextColor(peer, threadId: threadId, context: context), highlightIfActivity: false), expanded: true)
        
        
        
        if let threadData = threadData {
            if let peer = peerViewMonoforumMainPeer(peerView), let threadPeer {
                result = result
                    .withUpdatedTitle(peer.displayTitle)
                    .withUpdatedStatus(threadPeer._asPeer().displayTitle)
            } else {
                result = result
                    .withUpdatedTitle(threadData.info.title)
                    .withUpdatedStatus(peer?.displayTitle ?? "")
            }
        }
        if peerView.peerIsContact, let user = peer as? TelegramUser, user.photo.contains(where: { $0.isPersonal }) {
            result = result.withUpdatedStatus(result.status.string + " \(strings().bullet) " + strings().userInfoSetByYou)
        }
        
        self.result = result
        
        
        nameLayout = TextViewLayout(result.title, maximumNumberOfLines: 1)
        statusLayout = TextViewLayout(result.status, maximumNumberOfLines: 1, alignment: threadData != nil ? .center : .left, alwaysStaticItems: true)
        
        
        super.init(initialSize, stableId: stableId, viewType: viewType, inset: NSEdgeInsets(left: 8, right: 8, top: 8))
        
        
        if let cachedData = peerView.cachedData as? CachedChannelData, threadData == nil, let peer = peer, peer.isGroup || peer.isSupergroup || peer.isGigagroup {
            let onlineMemberCount:Signal<Int32?, NoError>
            if (cachedData.participantsSummary.memberCount ?? 0) > 200 {
                onlineMemberCount = context.peerChannelMemberCategoriesContextsManager.recentOnline(peerId: peerView.peerId) |> map(Optional.init) |> deliverOnMainQueue
            } else {
                onlineMemberCount = context.peerChannelMemberCategoriesContextsManager.recentOnlineSmall(peerId: peerView.peerId)  |> map(Optional.init) |> deliverOnMainQueue
            }
            self.onlineMemberCountDisposable.set(onlineMemberCount.start(next: { [weak self] count in
                guard let `self` = self else {
                    return
                }
                let result = stringStatus(for: peerView, context: context, theme: PeerStatusStringTheme(titleFont: .medium(.huge), titleColor: PeerInfoHeadItem.textColor(peer, threadId: threadId, context: context), statusFont: threadId != nil ? .medium(.text) : .normal(.text), statusColor: PeerInfoHeadItem.grayTextColor(peer, threadId: threadId, context: context), highlightIfActivity: false), onlineMemberCount: count)

                if result != self.result {
                    self.result = result
                    _ = self.makeSize(self.width, oldWidth: 0)
                    self.noteHeightOfRow(animated: true)
                }
            }))
        }
        
        _ = self.makeSize(initialSize.width, oldWidth: 0)
        
        
        if let peer = peer, threadData == nil, peer.hasVideo {
            self.photos = syncPeerPhotos(peerId: peer.id).map { $0.value }
            let signal = peerPhotos(context: context, peerId: peer.id) |> deliverOnMainQueue
            var first: Bool = true
            peerPhotosDisposable.set(signal.start(next: { [weak self] photos in
                let photos = photos.map { $0.value }
                if self?.photos != photos {
                    self?.photos = photos
                    if !first {
                        self?.noteHeightOfRow(animated: true)
                    }
                    first = false
                }
            }))
        }
    }
    
    func showStatusUnlocker() {
        if let peer = peer {
            showModal(with: PremiumShowStatusController(context: context, peer: .init(peer), source: .status), for: context.window)
        }
    }
    
    func previewRatig() {
        if let rating, let peer {
            showModal(with: PeerRatingModalController(context: context, peer: peer, rating: rating, pendingRating: (peerView.cachedData as? CachedUserData)?.pendingStarRating), for: context.window)
        }
    }
    
    func openProfileMusic() {
        
        guard let profileSavedMusic, let savedMusic, let musicFile, let peer = self.peer.flatMap(EnginePeer.init) else {
            return
        }
        
        if let active = PeerInfoUIHooks.shared.activeProfileMusic(context, peer.id) {
            PeerInfoUIHooks.shared.showProfileMusicPlayerList(context, peer, active.playing ?? musicFile, active.state, active.context)
            return
        }
        
        let controller = APProfileSavedController(context: context, peer: peer, profileMusicContext: profileSavedMusic, baseRate: FastSettings.playingRate, volume: FastSettings.volumeRate)
        
        PeerInfoUIHooks.shared.showInlineAudioPlayer(controller, context, self.table, nil)

        controller.start()
        
        PeerInfoUIHooks.shared.showProfileMusicPlayerList(context, peer, musicFile, savedMusic, profileSavedMusic)
        
    }

    func openWalletBalance(morphSource: (() -> NSView?)? = nil) {
        if #available(macOS 10.15, *), let peer {
            PeerInfoUIHooks.shared.walletHooks.showPeerBalanceObserved(context, peer, morphSource)
        }
    }
    
    var colorfulProfile: Bool {
        if let _ = nameColor {
            return true
        } else {
            return false
        }
    }
   
    var isForum: Bool {
        return self.peer.map({ TelegramUtilsHooks.shared.peerIsForum($0) }) == true
    }
    var isTopic: Bool {
        return self.isForum && threadData != nil
    }
    
    func openPeerStory() {
        if let peerId = self.peer?.id {
            let table = self.table
            self.arguments.openStory(.init(peerId: peerId, id: nil, messageId: nil, takeControl: { [weak table] peerId, _, _ in
                var view: NSView?
                table?.enumerateItems(with: { item in
                    if let item = item as? PeerInfoHeadItem, item.peer?.id == peerId {
                        view = item.takeControl()
                    }
                    return view == nil
                })
                return view
            }, setProgress: { [weak self] signal in
                self?.setOpenProgress(signal)
            }))
        }
    }
    
    private func takeControl() -> NSView? {
        if let view = self.view as? PeerInfoHeadView<Context> {
            return view.takeControl()
        }
        return nil
    }
    private func setOpenProgress(_ signal:Signal<Never, NoError>) {
        if let view = self.view as? PeerInfoHeadView<Context> {
            view.setOpenProgress(signal)
        }
    }
    
    deinit {
        fetchPeerAvatar.dispose()
        onlineMemberCountDisposable.dispose()
    }

    override var accessibilityLabel: String? {
        let name = nameLayout.attributedString.string
        if !name.isEmpty {
            return name
        }
        return effectivePeer?.displayTitle
    }
    
    override var accessibilityValue: String? {
        let status = statusLayout.attributedString.string
        return status.isEmpty ? nil : status
    }
    
    override func viewClass() -> AnyClass {
        return PeerInfoHeadView<Context>.self
    }
    
    override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        
        self.items = editing ? [] : actionItems(item: self, width: blockWidth, theme: theme)
        var textWidth = blockWidth - viewType.innerInset.right - viewType.innerInset.left - 10
        if let peer = peer, let controlSize = PremiumStatusControl.controlSize(peer, true, left: false) {
            textWidth -= (controlSize.width + 5)
        }
        if let peer = peer, let controlSize = PremiumStatusControl.controlSize(peer, true, left: true) {
            textWidth -= (controlSize.width + 5)
        }
        nameLayout.measure(width: textWidth)
        statusLayout.measure(width: textWidth)
        
        if let _ = threadData {
            statusLayout.generateAutoBlock(backgroundColor: theme.colors.accent.withAlphaComponent(0.2))
        }
        

        return success
    }

    
    func openNavigationTopics() {
        if let peer = peer, isTopic {
            ForumUI.open(peer.id, addition: true, context: context)
        }
    }
    
    var stateText: String? {
        if isScam {
            return strings().peerInfoScamWarning
        } else if isFake {
            return strings().peerInfoFakeWarning
        } else if isVerified {
            return strings().peerInfoVerifiedTooltip
        } else if isPremium {
            return strings().peerInfoPremiumTooltip
        }
        return nil
    }
    

    
    fileprivate var nameSize: NSSize {
        var stateHeight: CGFloat = 0
        if let peer = peer, let size = PremiumStatusControl.controlSize(peer, true, left: false) {
            stateHeight = max(size.height + 4, nameLayout.layoutSize.height)
        } else {
            stateHeight = nameLayout.layoutSize.height
        }
        var width = nameLayout.layoutSize.width
        if let peer = peer, let size = PremiumStatusControl.controlSize(peer, true, left: false)  {
            width += size.width + 5
        }
        if let peer = peer, let size = PremiumStatusControl.controlSize(peer, true, left: true)  {
            width += size.width + 5
        }
        return NSMakeSize(width, stateHeight)
    }
    
}





private final class NameContainer : View {
    let nameView = TextView()
    var statusControl: PremiumStatusControl?
    var leftStatusControl: PremiumStatusControl?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(nameView)
        layer?.masksToBounds = false
    }
    
    func update<Context: AccountContextProtocol>(_ item: PeerInfoHeadItem<Context>, animated: Bool) {
        self.nameView.update(item.nameLayout)
        let context = item.context
        
        if let peer = item.peer {
            let control = PremiumStatusControl.control(peer, account: item.context.account, inlinePacksContext: item.context.inlinePacksContext, left: false, isSelected: false, isBig: true, color: item.accentColor, cached: self.statusControl, animated: animated)
            if let control = control {
                self.statusControl = control
                self.addSubview(control)
            } else if let view = self.statusControl {
                performSubviewRemoval(view, animated: animated)
                self.statusControl = nil
            }
        } else if let view = self.statusControl {
            performSubviewRemoval(view, animated: animated)
            self.statusControl = nil
        }
        
        if let peer = item.peer {
            let control = PremiumStatusControl.control(peer, account: item.context.account, inlinePacksContext: item.context.inlinePacksContext, left: true, isSelected: false, isBig: true, color: item.accentColor, cached: self.leftStatusControl, animated: animated)
            if let control = control {
                self.leftStatusControl = control
                self.addSubview(control)
            } else if let view = self.leftStatusControl {
                performSubviewRemoval(view, animated: animated)
                self.leftStatusControl = nil
            }
        } else if let view = self.leftStatusControl {
            performSubviewRemoval(view, animated: animated)
            self.leftStatusControl = nil
        }
        
        
        if let stateText = item.stateText, let control = statusControl, let peerId = item.peer?.id {
            control.userInteractionEnabled = item.peer?.isScam == false && item.peer?.isFake == false
            control.scaleOnClick = true
            control.removeAllHandlers()
            
            
            control.set(handler: { control in
                if let emojiStatus = item.peer?.emojiStatus {
                    switch emojiStatus.content {
                    case let .starGift(_, _, _, slug, _, _, _, _, _):
                        PeerInfoUIHooks.shared.executeNftLink(item.context.meUrlDisplayPrefix + "nft/\(slug)", slug, item.context)
                    default:
                        prem(with: PremiumBoardingController(context: context, source: .profile(peerId)), for: context.window)
                    }
                } else {
                    let attr = parseMarkdownIntoAttributedString(stateText, attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .normal(.text), textColor: .white), bold: MarkdownAttributeSet(font: .bold(.text), textColor: .white), link: MarkdownAttributeSet(font: .normal(.text), textColor: nightAccentPalette.link), linkAttribute: { contents in
                        return (NSAttributedString.Key.link.rawValue, contents)
                    }))
                    if !context.premiumIsBlocked {
                        let interactions = TextViewInteractions(processURL: { content in
                            if let content = content as? String {
                                if content == "premium" {
                                    prem(with: PremiumBoardingController(context: context, source: .profile(peerId)), for: context.window)
                                }
                            }
                        })
                        tooltip(for: control, text: "", attributedText: attr, interactions: interactions)
                    }
                }
            }, for: .Click)
        } else {
            statusControl?.scaleOnClick = false
            statusControl?.userInteractionEnabled = false
        }
             
        needsLayout = true
    }
    
    override func layout() {
        super.layout()
        var offset: CGFloat = 0
        if let control = leftStatusControl {
            control.centerY(x: 0, addition: -1)
            offset += control.frame.width + 2
        }
        nameView.centerY(x: offset)
        var inset: CGFloat = nameView.frame.maxX + 5
        if let control = statusControl {
            control.centerY(x: inset, addition: -1)
            inset = control.frame.maxX + 8
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private var shadowImage: CGImage? = {
    return generateImage(CGSize(width: 44.0, height: 44.0), rotatedContext: { size, context in
        context.clear(CGRect(origin: .zero, size: size))
        
        var locations: [CGFloat] = [0.0, 0.3, 1.0]
        let colors: [CGColor] = [NSColor(rgb: 0xffffff, alpha: 0.65).cgColor, NSColor(rgb: 0xffffff, alpha: 0.65).cgColor, NSColor(rgb: 0xffffff, alpha: 0.0).cgColor]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: &locations)!
        context.drawRadialGradient(gradient, startCenter: CGPoint(x: size.width / 2.0, y: size.height / 2.0), startRadius: 0.0, endCenter: CGPoint(x: size.width / 2.0, y: size.height / 2.0), endRadius: size.width / 2.0, options: .drawsAfterEndLocation)
    })
}()


private class GiftIconLayer: SimpleLayer {
    private let context: any AccountContextProtocol
    let gift: ProfileGiftsContext.State.StarGift
    private let size: CGSize
    var glowing: Bool {
        didSet {
            self.shadowLayer.opacity = self.glowing ? 1.0 : 0.0
            
            let color: NSColor
            if self.glowing {
                color = .white
            } else if let layerTintColor = self.shadowLayer.layerTintColor {
                color = NSColor(cgColor: layerTintColor) ?? .white
            } else {
                color = .white
            }
            
            let side = floor(self.size.width * 1.25)
            let starsFrame = CGSize(width: side, height: side).centered(in: CGRect(origin: .zero, size: self.size))
            self.starsLayer.frame = starsFrame
            self.starsLayer.update(color: color, size: starsFrame.size)
        }
    }
    
    let shadowLayer = SimpleLayer()
    let starsLayer = StarsEffectLayer()
    let animationLayer: InlineStickerItemLayer
    
    override init(layer: Any) {
        guard let layer = layer as? GiftIconLayer else {
            fatalError()
        }
                
        let context = layer.context
        let gift = layer.gift
        let size = layer.size
        let glowing = layer.glowing
        
        var file: TelegramMediaFile?
        var color: NSColor = .white
        switch gift.gift {
        case let .generic(gift):
            file = gift.file
        case let .unique(gift):
            for attribute in gift.attributes {
                if case let .model(_, fileValue, _, _) = attribute {
                    file = fileValue
                } else if case let .backdrop(_, _, innerColor, _, _, _, _) = attribute {
                    color = NSColor(rgb: UInt32(bitPattern: innerColor))
                }
            }
        }
        
       
        
        self.animationLayer = .init(account: context.account, file: file!, size: size, playPolicy: .playCount(1))
        
        
        self.shadowLayer.contents = shadowImage
        self.shadowLayer.layerTintColor = color.cgColor
        self.shadowLayer.opacity = glowing ? 1.0 : 0.0
        
        self.context = context
        self.gift = gift
        self.size = size
        self.glowing = glowing
        
        super.init()
        
        let side = floor(size.width * 1.25)
        let starsFrame = CGSize(width: side, height: side).centered(in: CGRect(origin: .zero, size: size))
        self.starsLayer.frame = starsFrame
        self.starsLayer.update(color: glowing ? .white : color, size: starsFrame.size)
        
        self.addSublayer(self.shadowLayer)
        self.addSublayer(self.starsLayer)
        self.addSublayer(self.animationLayer)
    }
    
    init(
        context: any AccountContextProtocol,
        gift: ProfileGiftsContext.State.StarGift,
        size: CGSize,
        glowing: Bool
    ) {
        self.context = context
        self.gift = gift
        self.size = size
        self.glowing = glowing
        
        var file: TelegramMediaFile?
        var color: NSColor = .white
        switch gift.gift {
        case let .generic(gift):
            file = gift.file
        case let .unique(gift):
            for attribute in gift.attributes {
                if case let .model(_, fileValue, _, _) = attribute {
                    file = fileValue
                } else if case let .backdrop(_, _, innerColor, _, _, _, _) = attribute {
                    color = NSColor(rgb: UInt32(bitPattern: innerColor))
                }
            }
        }
        
        self.animationLayer = .init(account: context.account, file: file!, size: size, playPolicy: .playCount(1))

        
        self.shadowLayer.contents = shadowImage
        self.shadowLayer.layerTintColor = color.cgColor
        self.shadowLayer.opacity = glowing ? 1.0 : 0.0
        
        super.init()
        
        let side = floor(size.width * 1.25)
        let starsFrame = CGSize(width: side, height: side).centered(in: CGRect(origin: .zero, size: size))
        self.starsLayer.frame = starsFrame
        self.starsLayer.update(color: glowing ? .white : color, size: starsFrame.size)
        
        self.addSublayer(self.shadowLayer)
        self.addSublayer(self.starsLayer)
        self.addSublayer(self.animationLayer)
    }
    
    required init?(coder: NSCoder) {
        preconditionFailure()
    }
    
    override func layoutSublayers() {
        self.shadowLayer.frame = CGRect(origin: .zero, size: self.bounds.size).insetBy(dx: -4.0, dy: -4.0)
        self.animationLayer.frame = CGRect(origin: .zero, size: self.bounds.size)
    }
    
    func startAnimations(index: Int) {
        let beginTime = Double(index) * 1.5
        
        if self.animation(forKey: "hover") == nil {
            let upDistance = CGFloat.random(in: 1.0 ..< 2.0)
            let downDistance = CGFloat.random(in: 1.0 ..< 2.0)
            let hoverDuration = TimeInterval.random(in: 3.5 ..< 4.5)
            
            let hoverAnimation = CABasicAnimation(keyPath: "transform.translation.y")
            hoverAnimation.duration = hoverDuration
            hoverAnimation.fromValue = -upDistance
            hoverAnimation.toValue = downDistance
            hoverAnimation.autoreverses = true
            hoverAnimation.repeatCount = .infinity
            hoverAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            hoverAnimation.beginTime = beginTime
            hoverAnimation.isAdditive = true
            self.add(hoverAnimation, forKey: "hover")
        }
        
        if self.animationLayer.animation(forKey: "wiggle") == nil {
            let fromRotationAngle = CGFloat.random(in: 0.025 ..< 0.05)
            let toRotationAngle = CGFloat.random(in: 0.025 ..< 0.05)
            let wiggleDuration = TimeInterval.random(in: 2.0 ..< 3.0)
            
            let wiggleAnimation = CABasicAnimation(keyPath: "transform.rotation.z")
            wiggleAnimation.duration = wiggleDuration
            wiggleAnimation.fromValue = -fromRotationAngle
            wiggleAnimation.toValue = toRotationAngle
            wiggleAnimation.autoreverses = true
            wiggleAnimation.repeatCount = .infinity
            wiggleAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            wiggleAnimation.beginTime = beginTime
            wiggleAnimation.isAdditive = true
            self.animationLayer.add(wiggleAnimation, forKey: "wiggle")
        }
        
        if self.shadowLayer.animation(forKey: "glow") == nil {
            let glowDuration = TimeInterval.random(in: 2.0 ..< 3.0)
            
            let glowAnimation = CABasicAnimation(keyPath: "transform.scale")
            glowAnimation.duration = glowDuration
            glowAnimation.fromValue = 1.0
            glowAnimation.toValue = 1.2
            glowAnimation.autoreverses = true
            glowAnimation.repeatCount = .infinity
            glowAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glowAnimation.beginTime = beginTime
            self.shadowLayer.add(glowAnimation, forKey: "glow")
        }
    }
}


private let giftStatusCoverIntroDelay: Double = 0.2
private let giftStatusTooltipDelay: Double = 0.5

private final class SpawnGiftsView: View {
    
    
    
    private var giftsDisposable: Disposable?
    private var gifts: [ProfileGiftsContext.State.StarGift] = []
    private var appliedGiftIds: [Int64] = []

    private var iconPositions: [PositionGenerator.Position] = []
    private let seed = UInt(Date().timeIntervalSince1970)
    
    private var iconLayers: [AnyHashable: GiftIconLayer] = [:]

    private var context: (any AccountContextProtocol)?
    private var peer: EnginePeer?
    private var giftsContext: ProfileGiftsContext?
    
    var avatarFrame: CGRect = .zero
    var exclusionRects: [CGRect] = []
    private var appliedSize: NSSize = .zero
    private var scheduledAnimateIn = false

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
    }
    
    override func mouseDown(with event: NSEvent) {
      //  super.mouseDown(with: event)
        
        let location = self.convert(event.locationInWindow, from: nil)
        
        guard let peer else {
            return
        }
        
        for (_, iconLayer) in self.iconLayers {
            if iconLayer.frame.contains(location), let window = window as? Window {
                if let context = self.context, let unique = iconLayer.gift.gift.unique {
                    let gift = iconLayer.gift
                    let purpose = Star_TransactionPurpose.starGift(
                        gift: gift.gift,
                        convertStars: gift.convertStars,
                        text: gift.text,
                        entities: gift.entities,
                        nameHidden: gift.nameHidden,
                        savedToProfile: gift.savedToProfile,
                        converted: false,
                        fromProfile: true,
                        upgraded: false,
                        prepaidUpgradeHash: gift.prepaidUpgradeHash,
                        transferStars: gift.transferStars,
                        canExportDate: gift.canExportDate,
                        reference: gift.reference,
                        sender: gift.fromPeer,
                        saverId: nil,
                        canTransferDate: gift.canTransferDate,
                        canResaleDate: gift.canResaleDate,
                        dropOriginalDetailsStars: gift.dropOriginalDetailsStars,
                        canUpgrade: gift.canUpgrade,
                        number: gift.number,
                        isRefunded: gift.isRefunded,
                        canCraftAt: gift.canCraftAt,
                        craftChancePermille: unique.craftChancePermille,
                        upgradeStars: gift.upgradeStars
                    )
                    showModal(with: StarGift_Nft_Controller(context: context, gift: gift.gift, source: .quickLook(peer, unique), purpose: purpose, giftsContext: self.giftsContext, pinnedInfo: gift.reference.flatMap { .init(pinnedInfo: gift.pinnedToTop, reference: $0) }), for: window)
                }
            }
        }

        
    }
    
    override var isFlipped: Bool {
        return true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    func update(context: any AccountContextProtocol, giftsContext: ProfileGiftsContext, peer: EnginePeer?, transition: ContainedViewLayoutTransition, avatarTransitionFraction: CGFloat) {
        
        
        self.context = context
        self.peer = peer
        self.giftsContext = giftsContext
        
        guard let peerId = self.peer?.id else {
            return
        }
        
        let iconSize = CGSize(width: 32.0, height: 32.0)
        let layoutItemSize = CGSize(width: 40.0, height: 40.0)
        
        let avatarCenter = CGPoint(x: self.avatarFrame.midX, y: self.avatarFrame.midY)
        
        let giftIds = self.gifts.compactMap { gift in
            if case let .unique(gift) = gift.gift, peer?.effectiveProfileColor != nil {
                return gift.id
            } else {
                return nil
            }
        }
        
        if giftIds.isEmpty {
            self.appliedGiftIds = giftIds
        } else if frame.width > 0, frame.height > 0, !self.avatarFrame.isEmpty {
            if self.iconPositions.isEmpty || self.appliedGiftIds != giftIds || self.appliedSize != frame.size {
                let positionGenerator = PositionGenerator(
                    containerSize: frame.size,
                    centerFrame: self.avatarFrame,
                    exclusionZones: self.exclusionRects,
                    minimumDistance: 42.0,
                    edgePadding: 8.0,
                    seed: self.seed
                )
                self.iconPositions = positionGenerator.generatePositions(count: 12, itemSize: layoutItemSize)
                self.appliedSize = frame.size
            }
            self.appliedGiftIds = giftIds
        }
        
        
        if self.giftsDisposable == nil {
            self.giftsDisposable = combineLatest(
                queue: Queue.mainQueue(),
                giftsContext.state,
                context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
                |> map { peer -> Int64? in
                    if case let .user(user) = peer, case let .starGift(id, _, _, _, _, _, _, _, _) = user.emojiStatus?.content {
                        return id
                    }
                    return nil
                }
                |> distinctUntilChanged
            ).start(next: { [weak self] state, giftStatusId in
                guard let self else {
                    return
                }
                
                let pinnedGifts = state.gifts.filter { gift in
                    if gift.pinnedToTop {
                        if case let .unique(uniqueGift) = gift.gift {
                            return uniqueGift.id != giftStatusId
                        }
                    }
                    return false
                }
                self.gifts = pinnedGifts
                self.update(context: context, giftsContext: giftsContext, peer: peer, transition: transition, avatarTransitionFraction: avatarTransitionFraction)
            })
        }
        
        var validIds = Set<AnyHashable>()
        var index = 0
        for gift in self.gifts.prefix(12) {
            guard index < self.iconPositions.count else {
                break
            }
            let id: AnyHashable
            if case let .unique(uniqueGift) = gift.gift {
                id = uniqueGift.slug
            } else {
                id = index
            }
            validIds.insert(id)
            
            var iconTransition = transition
            let iconPosition = self.iconPositions[index]
            let iconLayer: GiftIconLayer
            if let current = self.iconLayers[id] {
                iconLayer = current
            } else {
                iconTransition = .immediate
                iconLayer = GiftIconLayer(context: context, gift: gift, size: iconSize, glowing: true)
                self.iconLayers[id] = iconLayer
                self.layer?.addSublayer(iconLayer)
                
                if !self.scheduledAnimateIn {
                    iconLayer.animateAlpha(from: 0.0, to: 1.0, duration: 0.2)
                    iconLayer.animateScale(from: 0.01, to: 1.0, duration: 0.2)
                }
                
                iconLayer.startAnimations(index: index)
            }
            iconLayer.glowing = true
            
            let itemDistanceFraction = max(0.0, min(0.5, (iconPosition.distance - self.avatarFrame.width / 2.0) / 144.0))
            let itemScaleFraction = patternScaleValueAt(fraction: min(1.0, avatarTransitionFraction * 1.33), t: itemDistanceFraction, reverse: false)

            func interpolatePosition(from: PositionGenerator.Position, to: PositionGenerator.Position, t: CGFloat) -> PositionGenerator.Position {
                let clampedT = max(0, min(1, t))
                
                let interpolatedDistance = from.distance + (to.distance - from.distance) * clampedT
                let interpolatedAngle = from.angle + (to.angle - from.angle) * clampedT
                
                return PositionGenerator.Position(distance: interpolatedDistance, angle: interpolatedAngle, scale: from.scale)
            }
            
            let centerPosition = PositionGenerator.Position(distance: 0.0, angle: iconPosition.angle, scale: iconPosition.scale)
            let effectivePosition = interpolatePosition(from: iconPosition, to: centerPosition, t: itemScaleFraction)
            
            let relative = effectivePosition.relativeCartesian
            let absolutePosition = CGPoint(x: avatarCenter.x + relative.x, y: avatarCenter.y + relative.y)

            iconTransition.updateFrame(layer: iconLayer, frame: iconSize.centered(around: absolutePosition))
            iconTransition.updateTransformScale(layer: iconLayer, scale: iconPosition.scale * (1.0 - itemScaleFraction))
            iconTransition.updateAlpha(layer: iconLayer, alpha: self.scheduledAnimateIn ? 0 : 1.0 - itemScaleFraction)
            
            index += 1
        }
        
        var removeIds: [AnyHashable] = []
        for (id, layer) in self.iconLayers {
            if !validIds.contains(id) {
                removeIds.append(id)
                layer.animateScale(from: 1.0, to: 0.01, duration: 0.25, removeOnCompletion: false)
                layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.25, removeOnCompletion: false, completion: { _ in
                    layer.removeFromSuperlayer()
                })
            }
        }
        for id in removeIds {
            self.iconLayers.removeValue(forKey: id)
        }
        
        needsDisplay = true
           
    }
    
    func willAnimateIn() {
        self.scheduledAnimateIn = true
        for (_, layer) in self.iconLayers {
            layer.opacity = 0
        }
    }
    
    func animateIn() {
        self.scheduledAnimateIn = false
        let avatarCenter = CGPoint(x: self.avatarFrame.midX, y: self.avatarFrame.midY)
        for (_, layer) in self.iconLayers {
            layer.opacity = 1
            layer.animatePosition(from: avatarCenter, to: layer.position, duration: 0.4, timingFunction: .spring)
        }
    }
    
    deinit {
        giftsDisposable?.dispose()
    }
}


private final class PeerInfoHeadView<Context: AccountContextProtocol> : GeneralContainableRowView {
    private let photoContainer = Control(frame: NSMakeRect(0, 20, 120, 120))
    private let photoView: AvatarStoryControl = AvatarStoryControl(font: .avatar(30), size: NSMakeSize(120, 120))
    private var liveStreamView: ImageView?
    private var photoVideoView: MediaPlayerView?
    private var photoVideoPlayer: MediaPlayer?
    
    private var ratingView: PeerRatingView?
   
    private var musicView: PeerInfoMusicView?
    private var preloadedWalletCard: WalletCard?
    private var balanceView: PeerInfoBalanceView?

    private let backgroundView = PeerInfoBackgroundView(frame: .zero)
    
    private var emojiSpawn: PeerInfoSpawnEmojiView?
    private var uniqueBackground: UniqueGiftBackgroundView?
    private var uniqueBackgroundContent: UniqueGiftBackgroundContent?
    private let spawnGiftsView: SpawnGiftsView = .init(frame: .zero)
    
    private let nameView = NameContainer(frame: .zero)
    private let statusView = TextView()
    
    private let statusContainer = View()
    private var showStatusView: TextButton?
    

    private let actionsView = View()
    private weak var giftTooltip: ShimmerTooltipView?
    private var didRunGiftStatusIntro = false
    private var photoEditableView: PeerInfoPhotoEditableView?
    
    private var listener: TableScrollListener!
    
    
    private var activeDragging: Bool = false {
        didSet {
            self.item?.noteHeightOfRow(animated: true)
        }
    }
    
    override func updateColors() {
        super.updateColors()
        guard let item = item as? PeerInfoHeadItem<Context> else {
            return
        }
        self.backgroundView.gradient = item.backgroundGradient
    }
 

    
    override var backdorColor: NSColor {
        guard let item = item as? PeerInfoHeadItem<Context> else {
            return super.backdorColor
        }
        return item.editing ? .clear : .clear
    }
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        photoView.setFrameSize(NSMakeSize(120, 120))

        
        
        addSubview(backgroundView)
        
        photoContainer.addSubview(photoView)
        
        photoContainer.layer?.masksToBounds = false
        actionsView.layer?.masksToBounds = false
        statusContainer.layer?.masksToBounds = false

        addSubview(spawnGiftsView)

        
        addSubview(photoContainer)
        addSubview(nameView)
        addSubview(actionsView)
        
        
        statusContainer.addSubview(statusView)
        addSubview(statusContainer)
        
        
        
        listener = .init(dispatchWhenVisibleRangeUpdated: false, { [weak self] position in
            self?.updateSpawnerFraction()
        })
       
        
        
        
        photoView.userInteractionEnabled = false
        
        photoContainer.set(handler: { [weak self] _ in
            if let item = self?.item as? PeerInfoHeadItem<Context> {
                if let stories = item.stories, !stories.items.isEmpty {
                    item.openPeerStory()
                } else {
                    if let peer = item.peer, let _ = peer.largeProfileImage, self?.topicPhotoView == nil {
                        showPhotosGallery(context: item.context, peerId: peer.id, firstStableId: item.stableId, item.table, nil)
                    }
                }
            }
        }, for: .Click)
        
        photoContainer.contextMenu = { [weak self] in
            if let item = self?.item as? PeerInfoHeadItem<Context>, let stories = item.stories, !stories.items.isEmpty {
                let menu = ContextMenu()
                menu.addItem(ContextMenuItem(strings().peerInfoContextOpenPhoto, handler: { [weak item] in
                    if let item = item {
                        if let peer = item.peer, let _ = peer.largeProfileImage {
                            showPhotosGallery(context: item.context, peerId: peer.id, firstStableId: item.stableId, item.table, nil)
                        }
                    }
                }, itemImage: MenuAnimation.menu_shared_media.value))
                return menu
            }
            return nil
        }
        
        
        registerForDraggedTypes([.tiff, .string, .kUrl, .kFileUrl])
        
        layout()
    }
    
    private func updateSpawnerFraction() {
        if let item = self.item as? PeerInfoHeadItem<Context>, let table = item.table {
            let position = table.scrollPosition().current
            let y = position.rect.minY - table.frame.height
            let clamp = min(max(0, y), item.height)
            let fraction = min(1, (clamp / item.height) + 0.3)
            let photoFraction = min(1, (clamp / item.height))

            self.emojiSpawn?.fraction = fraction
            self.uniqueBackground?.patternTransitionFraction = photoFraction
            
            var tr = CATransform3DIdentity
            tr = CATransform3DTranslate(tr, photoContainer.frame.width / 2, photoContainer.frame.height / 2, 0)
            tr = CATransform3DScale(tr,  1 - photoFraction,  1 - photoFraction, 1)
            tr = CATransform3DTranslate(tr, -photoContainer.frame.width / 2, -photoContainer.frame.height / 2, 0)
            if self.emojiSpawn != nil || self.uniqueBackground != nil {
                photoContainer.layer?.transform = tr
            } else {
                photoContainer.layer?.transform = CATransform3DIdentity
            }
            if let peer = item.peer, let giftsContext = item.giftsContext {
                spawnGiftsView.update(context: item.context, giftsContext: giftsContext, peer: .init(peer), transition: .immediate, avatarTransitionFraction: photoFraction)
            }
            
        }
    }
    
    override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if activeDragging {
            activeDragging = false
            if let item = item as? PeerInfoHeadItem<Context> {
                if let tiff = sender.draggingPasteboard.data(forType: .tiff), let image = NSImage(data: tiff) {
                    item.updatePhoto(image, self.photoEditableView)
                    return true
                } else {
                    let list = sender.draggingPasteboard.propertyList(forType: .kFilenames) as? [String]
                    if  let list = list {
                        if let first = list.first, let image = NSImage(contentsOfFile: first) {
                            item.updatePhoto(image, self.photoEditableView)
                            return true
                        }
                    }
                }
            }
        }
         return false
    }
    
    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let item = item as? PeerInfoHeadItem<Context>, !item.editing, let peer = item.peer, peer.groupAccess.canEditGroupInfo {
            if let tiff = sender.draggingPasteboard.data(forType: .tiff), let _ = NSImage(data: tiff) {
                activeDragging = true
            } else {
                let list = sender.draggingPasteboard.propertyList(forType: .kFilenames) as? [String]
                if let list = list {
                    let list = list.filter { path -> Bool in
                        if let size = fs(path) {
                            return size <= 5 * 1024 * 1024
                        }
                        return false
                    }
                    activeDragging = list.count == 1 && NSImage(contentsOfFile: list[0]) != nil
                } else {
                    activeDragging = false
                }
            }
            
        } else {
            activeDragging = false
        }
        return .generic
    }
    override public func draggingExited(_ sender: NSDraggingInfo?) {
        activeDragging = false
    }
    public override func draggingEnded(_ sender: NSDraggingInfo) {
        activeDragging = false
    }
    
    @objc func updatePlayerIfNeeded() {
        let accept = window != nil && window!.isKeyWindow && !NSIsEmptyRect(visibleRect) && !isDynamicContentLocked
        if let photoVideoPlayer = photoVideoPlayer {
            if accept {
                photoVideoPlayer.play()
            } else {
                photoVideoPlayer.pause()
            }
        }
    }
    
    override func addAccesoryOnCopiedView(innerId: AnyHashable, view: NSView) {
        photoVideoPlayer?.seek(timestamp: 0)
    }
    
    override func viewDidUpdatedDynamicContent() {
        super.viewDidUpdatedDynamicContent()
        updatePlayerIfNeeded()
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateListeners()
        updatePlayerIfNeeded()
        updateAnimatableContent()
    }
    
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateListeners()
        updatePlayerIfNeeded()
        updateAnimatableContent()

    }
    
    func updateListeners() {
        if let window = window {
            NotificationCenter.default.removeObserver(self)
            NotificationCenter.default.addObserver(self, selector: #selector(updatePlayerIfNeeded), name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(updatePlayerIfNeeded), name: NSWindow.didResignKeyNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(updatePlayerIfNeeded), name: NSView.boundsDidChangeNotification, object: item?.table?.clipView)
            NotificationCenter.default.addObserver(self, selector: #selector(updatePlayerIfNeeded), name: NSView.boundsDidChangeNotification, object: self)
            NotificationCenter.default.addObserver(self, selector: #selector(updatePlayerIfNeeded), name: NSView.frameDidChangeNotification, object: item?.table?.view)
        } else {
            removeNotificationListeners()
        }
    }
    
    func removeNotificationListeners() {
        NotificationCenter.default.removeObserver(self)
    }
    
    deinit {
        removeNotificationListeners()
    }
    
    
    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        
        let statusContainerSize: NSSize
        statusContainerSize = NSMakeSize(statusContainer.subviewsWidthSize.width + 4, statusContainer.subviewsWidthSize.height)
        

        transition.updateFrame(view: backgroundView, frame: NSRect(x: 0, y: -110, width: containerView.frame.width, height: containerView.frame.height + 110))
        backgroundView.updateLayout(size: backgroundView.frame.size, transition: transition)
        
        transition.updateFrame(view: spawnGiftsView, frame: NSRect(origin: .zero, size: containerView.frame.size))

        guard let item = item as? PeerInfoHeadItem<Context> else {
            return
        }

        transition.updateFrame(view: photoContainer, frame: photoContainer.centerFrameX(y: 20))
        if let uniqueBackground, let content = uniqueBackgroundContent {
            let backgroundFrame = NSRect(x: 0, y: -110, width: containerView.frame.width, height: containerView.frame.height + 110)
            transition.updateFrame(view: uniqueBackground, frame: backgroundFrame)
            let avatarCenter = NSMakePoint(backgroundFrame.width / 2, photoContainer.frame.midY - backgroundFrame.minY)
            uniqueBackground.update(context: item.context, content: content, style: .profile(avatarCenter: avatarCenter, avatarSize: photoContainer.frame.width, defaultHeight: containerView.frame.height, gradientCenter: NSMakePoint(0.5, 0.45)))
        }
        transition.updateFrame(view: photoView, frame: photoView.centerFrame())
        if let editable = photoEditableView {
            transition.updateFrame(view: editable, frame: editable.centerFrame())
        }
        
        if let liveStreamView {
            transition.updateFrame(view: liveStreamView, frame: liveStreamView.centerFrameX(y: photoContainer.frame.height - floorToScreenPixels(liveStreamView.frame.height * 0.7)))
        }

        if let emoji = emojiSpawn {
            transition.updateFrame(view: emoji, frame: emoji.centerFrameX(y: 20))
        }

        if item.isTopic {
            transition.updateFrame(view: nameView, frame: nameView.centerFrameX(y: photoContainer.frame.maxY - 12))
            let statusContainerFrame = CGRect(
                x: floor((containerView.frame.width - statusContainerSize.width) / 2),
                       y: nameView.frame.maxY + 4,
                       width: statusContainerSize.width,
                       height: statusContainerSize.height
                   )
            transition.updateFrame(view: statusContainer, frame: statusContainerFrame)
        } else {
            transition.updateFrame(view: nameView, frame: nameView.centerFrameX(y: photoContainer.frame.maxY + item.viewType.innerInset.top))
            let statusContainerFrame = CGRect(
                        x: floor((containerView.frame.width - statusContainerSize.width) / 2),
                        y: nameView.frame.maxY,
                        width: statusContainerSize.width,
                        height: statusContainerSize.height
                    )
            transition.updateFrame(view: statusContainer, frame: statusContainerFrame)
        }

        let actionsY = containerView.frame.height - actionsView.frame.height - (item.nameColor != nil ? 16 : 0) - (item.hasProfileStrip ? PeerInfoMusicView.height(colorful: item.colorfulProfile) + (item.nameColor == nil ? 16 : -4) : 0)
        transition.updateFrame(view: actionsView, frame: actionsView.centerFrameX(y: actionsY))

        if let photo = topicPhotoView {
            let photoX = floorToScreenPixels(backingScaleFactor, photoContainer.frame.width - item.photoDimension) / 2
            let photoY = floorToScreenPixels(backingScaleFactor, photoContainer.frame.height - item.photoDimension) / 2
            let frame = NSRect(x: photoX, y: photoY, width: item.photoDimension, height: item.photoDimension)
            transition.updateFrame(view: photo, frame: frame)
        }

        if let showStatus = showStatusView {
            transition.updateFrame(view: showStatus, frame: showStatus.centerFrameY(x: statusView.frame.maxX + 4))
        }

        var statusOffset: CGFloat = 0
        if let rating = ratingView {
            transition.updateFrame(view: rating, frame: rating.centerFrameY(x: 0))
            statusOffset = rating.smallSize.width + 3
        }
        
        if let balanceView {
            let size = balanceView.size
            let frame = NSMakeRect(floor((containerView.frame.width - size.width) / 2), statusContainer.frame.maxY + PeerInfoBalanceView.spacing, size.width, size.height)
            let balanceTransition: ContainedViewLayoutTransition = balanceView.frame.isEmpty ? .immediate : transition
            balanceTransition.updateFrame(view: balanceView, frame: frame)
        }
        if let musicView {
            let stripHeight = PeerInfoMusicView.height(colorful: item.colorfulProfile)
            transition.updateFrame(view: musicView, frame: NSMakeRect(0, containerView.frame.height - stripHeight, containerView.frame.width, stripHeight))
        }

        transition.updateFrame(view: statusView, frame: statusView.centerFrameY(x: statusOffset))

        updateSpawnGiftsGeometry()
        layoutGiftTooltip()
    }
    
    private func runGiftStatusIntroIfNeeded(_ item: PeerInfoHeadItem<Context>) {
        guard item.giftStatusTitle != nil else {
            giftTooltip?.hide()
            return
        }
        guard !didRunGiftStatusIntro else {
            return
        }
        didRunGiftStatusIntro = true
        emojiSpawn?.animateIn(delay: giftStatusCoverIntroDelay)
        spawnGiftsView.willAnimateIn()
        delay(giftStatusCoverIntroDelay) { [weak self] in
            self?.spawnGiftsView.animateIn()
        }
        delay(giftStatusTooltipDelay) { [weak self] in
            self?.showGiftTooltip()
        }
    }
    
    private var giftTooltipAnchor: NSRect? {
        guard let control = nameView.statusControl else {
            return nil
        }
        return containerView.convert(control.frame, from: nameView)
    }
    
    private func showGiftTooltip() {
        guard let item = self.item as? PeerInfoHeadItem<Context>, let title = item.giftStatusTitle, let anchor = giftTooltipAnchor, window != nil, !visibleRect.isEmpty else {
            return
        }
        let tooltip = ShimmerTooltipView(text: .initialize(string: title, color: .white, font: .semibold(11)), color: item.giftTooltipColor)
        tooltip.show(in: containerView, pointingAt: anchor)
        giftTooltip = tooltip
    }
    
    private func layoutGiftTooltip() {
        if let tooltip = giftTooltip, let anchor = giftTooltipAnchor {
            tooltip.update(anchor: anchor)
        }
    }
    
    private func updateSpawnGiftsGeometry() {
        let size = containerView.frame.size
        guard size.width > 0, size.height > 0 else {
            return
        }
        
        var exclusionRects: [CGRect] = []
        
        let titleWidth = max(140.0, nameView.frame.width, balanceView?.frame.width ?? 0) + 42.0
        let titleTop = min(nameView.frame.minY, photoContainer.frame.maxY + 6.0)
        let titleBottom = max(nameView.frame.maxY, statusContainer.frame.maxY, balanceView?.frame.maxY ?? 0)
        if titleBottom > titleTop {
            exclusionRects.append(CGRect(x: floor((size.width - titleWidth) / 2), y: titleTop, width: titleWidth, height: titleBottom - titleTop))
        }
        
        var bottomY = actionsView.frame.minY
        if let musicView {
            bottomY = min(bottomY, musicView.frame.minY)
        }
        bottomY = max(0, bottomY - 6.0)
        if size.height > bottomY {
            exclusionRects.append(CGRect(x: 0, y: bottomY, width: size.width, height: size.height - bottomY))
        }
        
        spawnGiftsView.avatarFrame = photoContainer.frame
        spawnGiftsView.exclusionRects = exclusionRects
        
        updateSpawnerFraction()
    }

    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func _actionItemWidth(_ items: [ActionItem]) -> CGFloat {
        guard let item = self.item as? PeerInfoHeadItem<Context> else {
            return 0
        }

        let actionItemInset = ActionItem.actionItemInsetWidth(isColorfull: item.nameColor != nil)
        let sideInset: CGFloat = 14
        let width = (item.blockWidth - sideInset - item.inset.left - item.inset.right - (actionItemInset * CGFloat(items.count - 1)))

        return min(170, width / CGFloat(items.count))
    }
    
    private func layoutActionItems(_ items: [ActionItem], animated: Bool) {
        
        if !items.isEmpty, let rowItem = self.item as? PeerInfoHeadItem<Context> {
            let maxActionSize: NSSize = items.max(by: { $0.size.height < $1.size.height })!.size
            
            
            while actionsView.subviews.count > items.count {
                actionsView.subviews.removeLast()
            }
            while actionsView.subviews.count < items.count {
                actionsView.addSubview(ActionButton(frame: .zero))
            }
            
            let inset: CGFloat = 0

            let actionItemWidth = _actionItemWidth(items)
            let actionItemInset = ActionItem.actionItemInsetWidth(isColorfull: rowItem.nameColor != nil)

            actionsView.change(size: NSMakeSize(actionItemWidth * CGFloat(items.count) + CGFloat(items.count - 1) * actionItemInset, maxActionSize.height), animated: animated)

            var x: CGFloat = inset
            let useGlass = System.liquidGlass && rowItem.nameColor != nil && rowItem.threadId == nil && !rowItem.editing

            for (i, item) in items.enumerated() {
                let view = actionsView.subviews[i] as! ActionButton
                view.updateAndLayout(item: item, bgColor: rowItem.actionColor, useGlass: useGlass)
                if item.subItems?.isEmpty == false, let menu = view.contextMenu {
                    view.contextMenu = {
                        return menu()
                    }
                }
                view.setFrameSize(NSMakeSize(actionItemWidth, maxActionSize.height))
                view.change(pos: NSMakePoint(x, 0), animated: false)
                x += actionItemWidth + actionItemInset
            }
            
        } else {
            actionsView.removeAllSubviews()
        }
        
    }
    
    private var videoRepresentation: TelegramMediaImage.VideoRepresentation?
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? PeerInfoHeadItem<Context> else {
            return
        }
        
        spawnGiftsView.change(opacity: item.editing ? 0 : 1, animated: animated)
        
        item.table?.addScroll(listener: listener)
        
        if let monoforum = peerViewMonoforumMainPeer(item.peerView), let peer = item.effectivePeer, item.threadPeer == nil {
            photoView.setState(account: item.context.account, state: .PeerAvatar(peer, TelegramUtilsHooks.shared.peerLetters(monoforum), monoforum.smallProfileImage, monoforum.namePeerColor, nil, nil, true, nil))
        } else {
            photoView.setPeer(account: item.context.account, peer: item.effectivePeer)
        }
        

        updatePhoto(item, animated: animated)
        
        photoView.isHidden = item.isTopic
        photoContainer.setAccessibilityLabel(strings().voiceOverCommonPhotoOf(item.effectivePeer?.displayTitle ?? item.nameLayout.attributedString.string))

        if !item.photos.isEmpty {
            
            if let first = item.photos.first, let video = first.image.videoRepresentations.last, item.updatingPhotoState == nil {
               
                let equal = videoRepresentation?.resource.id == video.resource.id
                
                if !equal {
                    
                    self.photoVideoView?.removeFromSuperview()
                    self.photoVideoView = nil
                    
                    self.photoVideoView = MediaPlayerView(backgroundThread: true)
                    if #available(macOS 10.15, *) {
                        self.photoView.layer?.cornerCurve = .circular
                    } 
                    if let photoEditableView = self.photoEditableView {
                        photoContainer.addSubview(self.photoVideoView!, positioned: .below, relativeTo: photoEditableView)
                    } else {
                        photoContainer.addSubview(self.photoVideoView!)

                    }
                    self.photoVideoView!.isEventLess = true
                    
                    self.photoVideoView!.frame = self.photoView.frame

                    
                    let file = TelegramMediaFile(fileId: MediaId(namespace: 0, id: arc4random64()), partialReference: nil, resource: video.resource, previewRepresentations: first.image.representations, videoThumbnails: [], immediateThumbnailData: nil, mimeType: "video/mp4", size: video.resource.size, attributes: [], alternativeRepresentations: [])
                    
                    
                    let reference: MediaResourceReference
                    
                    if let peer = item.peer, let peerReference = PeerReference(peer) {
                        reference = MediaResourceReference.avatar(peer: peerReference, resource: file.resource)
                    } else {
                        reference = MediaResourceReference.standalone(resource: file.resource)
                    }
                    let userLocation: MediaResourceUserLocation
                    if let id = item.peer?.id {
                        userLocation = .peer(id)
                    } else {
                        userLocation = .other
                    }
                    
                    let mediaPlayer = MediaPlayer(postbox: item.context.account.postbox, userLocation: userLocation, userContentType: .avatar, reference: reference, streamable: true, video: true, preferSoftwareDecoding: false, enableSound: false, fetchAutomatically: true)
                    
                    mediaPlayer.actionAtEnd = .loop(nil)
                    
                    self.photoVideoPlayer = mediaPlayer
                    
                    if let seekTo = video.startTimestamp {
                        mediaPlayer.seek(timestamp: seekTo)
                    }
                    mediaPlayer.attachPlayerView(self.photoVideoView!)
                    self.videoRepresentation = video
                    updatePlayerIfNeeded()
                }
                
                
            } else {
                self.photoVideoPlayer = nil
                self.photoVideoView?.removeFromSuperview()
                self.photoVideoView = nil
                self.videoRepresentation = nil
            }
        } else {
            self.photoVideoPlayer = nil
            self.photoVideoView?.removeFromSuperview()
            self.photoVideoView = nil
            self.videoRepresentation = nil
        }
        

        let uniqueContent = !item.editing && item.colorfulProfile ? item.peer?.emojiStatus.flatMap(UniqueGiftBackgroundContent.init(emojiStatus:)) : nil
        if let uniqueContent {
            if self.uniqueBackground == nil {
                let current = UniqueGiftBackgroundView(frame: backgroundView.frame)
                addSubview(current, positioned: .above, relativeTo: backgroundView)
                self.uniqueBackground = current
            }
            self.uniqueBackgroundContent = uniqueContent
        } else if let view = self.uniqueBackground {
            performSubviewRemoval(view, animated: animated)
            self.uniqueBackground = nil
            self.uniqueBackgroundContent = nil
        }

        if uniqueContent == nil, let emoji = item.peer?.profileBackgroundEmojiId, !item.editing, item.hasBackgroundGradient {
            let current: PeerInfoSpawnEmojiView
            if let view = self.emojiSpawn {
                current = view
            } else {
                var rect = focus(NSMakeSize(180, 180))
                rect.origin.y = 0
                current = PeerInfoSpawnEmojiView(frame: rect)
                self.emojiSpawn = current
                addSubview(current, positioned: .above, relativeTo: backgroundView)
            }
            
            current.set(fileId: emoji, color: item.profileEmojiColor, context: item.context, animated: animated)
        } else if let view = self.emojiSpawn {
            performSubviewRemoval(view, animated: animated)
            self.emojiSpawn = nil
        }
        
        if let rating = item.rating, !item.editing {
            let current: PeerRatingView
            if let view = self.ratingView {
                current = view
            } else {
                current = PeerRatingView(frame: .zero)
                self.ratingView = current
                statusContainer.addSubview(current)
            }
            current.set(data: rating, context: item.context, borderColor: NSColor(0xffffff), bgColor: NSColor(0xffffff), textColor: item.colorfulProfile ? item.backgroundGradient[0] : NSColor(0x000000), animated: animated)
            
            current.change(size: current.smallSize, animated: animated)
            current.updateLayout(size: current.smallSize, transition: animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate)
            
            current.setSingle(handler: { [weak item] _ in
                item?.previewRatig()
            }, for: .Click)
            
        } else if let view = self.ratingView {
            performSubviewRemoval(view, animated: animated)
            self.ratingView = nil
        }
        
        if let musicFile = item.musicFile, !item.editing {
            let current: PeerInfoMusicView
            if let view = self.musicView {
                current = view
            } else {
                let musicHeight = PeerInfoMusicView.height(colorful: item.colorfulProfile)
                current = PeerInfoMusicView(frame: NSMakeRect(0, item.height - musicHeight, frame.width, musicHeight))
                self.musicView = current
                self.addSubview(current)
            }
            let colorfullText = PeerInfoHeadItem<Context>.textColor(item.peer, threadId: item.threadId, context: item.context)
            
            let primaryColor = item.colorfulProfile ? colorfullText : theme.colors.accent
            let secondaryColor = item.colorfulProfile ? colorfullText.withAlphaComponent(0.75) : theme.colors.grayText
            let backgroundColor = item.colorfulProfile ? item.actionColor : .clear
            
            current.update(file: musicFile, primaryText: primaryColor, secondaryText: secondaryColor, backgroundColor: backgroundColor, colorfull: item.colorfulProfile, context: item.context)
                        
            current.control.setSingle(handler: { [weak item] _ in
                item?.openProfileMusic()
            }, for: .Click)
            
        } else if let view = self.musicView {
            performSubviewRemoval(view, animated: animated)
            self.musicView = nil
        }

        if let walletBalance = item.walletBalance, !item.editing {
            if #available(macOS 10.15, *), let card = (item.peerView.cachedData as? CachedUserData)?.walletCard, card != self.preloadedWalletCard {
                self.preloadedWalletCard = card
                PeerInfoUIHooks.shared.walletHooks.preloadPeerCard(item.context, card)
            }
            let current: PeerInfoBalanceView
            if let view = self.balanceView {
                current = view
            } else {
                current = PeerInfoBalanceView(frame: .zero)
                self.balanceView = current
                self.addSubview(current)
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            current.update(balance: walletBalance, textColor: item.textColor, iconColor: item.colorfulProfile ? item.textColor : theme.colors.accent, backgroundColor: item.actionColor, colorfull: item.colorfulProfile, useGlass: System.liquidGlass && item.nameColor != nil && item.threadId == nil && !item.editing)

            current.control.setSingle(handler: { [weak item, weak current] _ in
                item?.openWalletBalance(morphSource: { [weak current] in current?.control })
            }, for: .Click)
        } else if let view = self.balanceView {
            performSubviewRemoval(view, animated: animated)
            self.balanceView = nil
        }
        
        if  item.hasLiveStream {
            let current: ImageView
            if let view = liveStreamView {
                current = view
            } else {
                current = ImageView()
                current.setAccessibilityLabel(strings().voiceOverCommonLive)
                self.liveStreamView = current
                photoContainer.addSubview(current)
            }
            current.image = generateLiveStreamBadge(fontSize: .small, outerColor: theme.colors.background)
            current.sizeToFit()
        } else if let view = liveStreamView {
            performSubviewRemoval(view, animated: animated)
            self.liveStreamView = nil
        }
        
        self.updateSpawnerFraction()
        
        self.photoVideoView?.layer?.cornerRadius = item.isForum ? self.photoView.frame.height / 3 : self.photoView.frame.height / 2
        
        nameView.change(size: item.nameSize, animated: animated)
        nameView.update(item, animated: animated)
        runGiftStatusIntroIfNeeded(item)
        
        nameView.change(opacity: item.editing ? 0 : 1, animated: animated)
        statusContainer.change(opacity: item.editing ? 0 : 1, animated: animated)
        
        backgroundView.change(opacity: item.editing || !item.colorfulProfile || uniqueBackground != nil ? 0 : 1, animated: animated)

        statusView.update(item.statusLayout)
        statusView.isSelectable = item.threadId == nil
        statusView.scaleOnClick = item.threadId != nil
        
        
        
        statusView.removeAllHandlers()
        if item.isTopic {
            statusView.set(handler: { [weak item] _ in
                if let item = item {
                    item.openNavigationTopics()
                }
            }, for: .Click)
        }
        
        
        
        layoutActionItems(item.items, animated: animated)
        
        
        photoContainer.userInteractionEnabled = !item.editing
        
        
        if item.canEditPhoto || self.activeDragging || item.updatingPhotoState != nil {
            if photoEditableView == nil {
                photoEditableView = .init(frame: NSMakeRect(0, 0, item.photoDimension, item.photoDimension))
                photoContainer.addSubview(photoEditableView!)
                if animated {
                    photoEditableView?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            photoEditableView?.layer?.cornerRadius = item.isForum ? item.photoDimension / 3 : item.photoDimension / 2
            
            photoEditableView?.updateState(item.updatingPhotoState, animated: animated)
            photoEditableView?.setup = item.updatePhoto
        } else {
            if let photoEditableView = self.photoEditableView {
                self.photoEditableView = nil
                if animated {
                    photoEditableView.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak photoEditableView] _ in
                        photoEditableView?.removeFromSuperview()
                    })
                } else {
                    photoEditableView.removeFromSuperview()
                }
            }
        }
        
        
        
        photoContainer.scaleOnClick = true
        
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate
        if let avatarStoryComponent = item.avatarStoryComponent {
            photoView.update(component: avatarStoryComponent, availableSize: NSMakeSize(item.photoDimension - 6, item.photoDimension - 6), transition: transition)
            self.photoVideoView?._change(size: NSMakeSize(item.photoDimension - 6, item.photoDimension - 6), animated: animated)
            self.photoVideoView?._change(pos: NSMakePoint(3, 3), animated: animated)
        } else  {
            photoView.update(component: nil, availableSize: NSMakeSize(item.photoDimension, item.photoDimension), transition: transition)
            self.photoVideoView?._change(size: NSMakeSize(item.photoDimension, item.photoDimension), animated: animated)
            self.photoVideoView?._change(pos: NSMakePoint(0, 0), animated: animated)
        }
        

        if item.statusIsHidden {
            let current: TextButton
            if let view = self.showStatusView {
                current = view
            } else {
                current = TextButton()
                current.set(font: .medium(.small), for: .Normal)
                current.scaleOnClick = true
                statusContainer.addSubview(current)
                self.showStatusView = current
            }
            current.set(color: item.accentColor, for: .Normal)
            current.set(background: item.accentColor.withAlphaComponent(0.2), for: .Normal)
            current.set(text: strings().peerStatusShow, for: .Normal)
            current.sizeToFit(NSMakeSize(5, 5))
            current.layer?.cornerRadius = current.frame.height * 0.5
            current.removeAllHandlers()
            current.set(handler: { [weak item] _ in
                item?.showStatusUnlocker()
            }, for: .Click)
        } else if let view = showStatusView {
            performSubviewRemoval(view, animated: animated)
            self.showStatusView = nil
        }
        
        
        
        self.updateLayout(size: NSMakeSize(frame.width, item.height), transition: transition)
        
        updateListeners()
        
    }
    
    
    
    override func interactionContentView(for innerId: AnyHashable, animateIn: Bool ) -> NSView {
        return photoView.avatar
    }
    
    override func copy() -> Any {
        return photoView.copy()
    }
    
    private var inlineTopicPhotoLayer: InlineStickerItemLayer?
    private var topicPhotoView: Control?

    private func updatePhoto(_ item: PeerInfoHeadItem<Context>, animated: Bool) {
        let context = item.context
        
        if let threadData = item.threadData, item.isForum {
            let size = NSMakeSize(item.photoDimension, item.photoDimension)
            let topicView: Control
            if let view = self.topicPhotoView {
                topicView = view
            } else {
                topicView = Control(frame: size.bounds)
                topicView.scaleOnClick = true
                topicView.setAccessibilityLabel(strings().voiceOverCommonEmoji)
                self.topicPhotoView = topicView
                photoContainer.addSubview(topicView)
                
                topicView.set(handler: { [weak self] _ in
                    if let file = self?.inlineTopicPhotoLayer?.file {
                        let reference = file.emojiReference ?? file.stickerReference
                        if let reference = reference {
                            showModal(with: StickerPackPreviewModalController(context, peerId: nil, references: [.emoji(reference)]), for: context.window)
                        }
                    }
                }, for: .Click)
            }
                        
            let current: InlineStickerItemLayer
            if let layer = self.inlineTopicPhotoLayer, layer.file?.fileId.id == threadData.info.icon {
                current = layer
            } else {
                if let layer = inlineTopicPhotoLayer {
                    performSublayerRemoval(layer, animated: animated)
                    self.inlineTopicPhotoLayer = nil
                }
                let info = threadData.info
                if let fileId = info.icon {
                    current = .init(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: .init(fileId: fileId, file: nil, emoji: ""), size: size, playPolicy: .loop)
                } else {
                    let file = ForumUI.makeIconFile(title: info.title, iconColor: info.iconColor, isGeneral: item.threadId == 1)
                    current = .init(account: context.account, file: file, size: size, playPolicy: .loop)
                }
                current.superview = topicView
                topicView.layer?.addSublayer(current)
                self.inlineTopicPhotoLayer = current
            }
        } else {
            if let layer = inlineTopicPhotoLayer {
                performSublayerRemoval(layer, animated: animated)
                self.inlineTopicPhotoLayer = nil
            }
            if let view = self.topicPhotoView {
                performSubviewRemoval(view, animated: animated)
                self.topicPhotoView = nil
            }
        }
        self.updateAnimatableContent()
    }
    



    override func updateAnimatableContent() -> Void {
        let checkValue:(InlineStickerItemLayer)->Void = { value in
            if let superview = value.superview {
                var isKeyWindow: Bool = false
                if let window = superview.window {
                    if !window.canBecomeKey {
                        isKeyWindow = true
                    } else {
                        isKeyWindow = window.isKeyWindow
                    }
                }
                value.isPlayable = superview.visibleRect != .zero && isKeyWindow
            }
        }
        if let value = inlineTopicPhotoLayer {
            checkValue(value)
        }
    }
    
    func takeControl() -> NSView? {
        return self.photoView
    }
    func setOpenProgress(_ signal:Signal<Never, NoError>) {
        SetOpenStoryDisposable(self.photoView.pushLoadingStatus(signal: signal))
    }
    
    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        self.spawnGiftsView.mouseDown(with: event)
    }
}
