import Cocoa
import OpusBinding
import Postbox
import TelegramCore
import TGUIKit
import SwiftSignalKit
import TelegramMedia
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import InAppSettings
import ChatModeTypes
import ChatHistoryModel
import ShortPeerRow
import TelegramCallsCore
import MediaRecorderUI
import StarsUI
import InputView

public final class ChatPinnedMessage: Equatable {
    public let messageId: MessageId
    public let message: Message?
    public let isLatest: Bool
    public let index: Int
    public let totalCount: Int
    public let others:[MessageId]
    public init(messageId: MessageId, message: Message?, others: [MessageId] = [], isLatest: Bool, index:Int = 0, totalCount: Int = 1) {
        self.messageId = messageId
        self.message = message
        self.others = others
        self.isLatest = isLatest
        self.index = index
        self.totalCount = totalCount
    }
    
    public static func ==(lhs: ChatPinnedMessage, rhs: ChatPinnedMessage) -> Bool {
        if lhs === rhs {
            return true
        }
        if lhs.messageId != rhs.messageId {
            return false
        }
        if lhs.message?.id != rhs.message?.id {
            return false
        }
        if lhs.message?.stableVersion != rhs.message?.stableVersion {
            return false
        }
        if lhs.isLatest != rhs.isLatest {
            return false
        }
        if lhs.index != rhs.index {
            return false
        }
        if lhs.totalCount != rhs.totalCount {
            return false
        }
        return true
    }
}





public enum ChatPresentationInputQuery: Equatable {
    case none
    case hashtag(String)
    case mention(query: String, includeRecent: Bool)
    case command(String)
    case contextRequest(addressName: String, query: String)
    case emoji(String, firstWord: Bool)
    case stickers(String)
}


public struct ChatActiveGroupCallInfo: Equatable {
    public var activeCall: CachedChannelData.ActiveCall
    public let data: GroupCallPanelData?
    public let callJoinPeerId: PeerId?
    public let joinHash: String?
    public let isLive: Bool
    public init(activeCall: CachedChannelData.ActiveCall, data: GroupCallPanelData?, callJoinPeerId: PeerId?, joinHash: String?, isLive: Bool) {
        self.activeCall = activeCall
        self.data = data
        self.callJoinPeerId = callJoinPeerId
        self.joinHash = joinHash
        self.isLive = isLive
    }
    
    public func withUpdatedData(_ data: GroupCallPanelData?) -> ChatActiveGroupCallInfo {
        return ChatActiveGroupCallInfo(activeCall: self.activeCall, data: data, callJoinPeerId: self.callJoinPeerId, joinHash: self.joinHash, isLive: self.isLive)
    }
    public func withUpdatedActiveCall(_ activeCall: CachedChannelData.ActiveCall) -> ChatActiveGroupCallInfo {
        return ChatActiveGroupCallInfo(activeCall: activeCall, data: self.data, callJoinPeerId: self.callJoinPeerId, joinHash: self.joinHash, isLive: self.isLive)
    }
    public func withUpdatedCallJoinPeerId(_ callJoinPeerId: PeerId?) -> ChatActiveGroupCallInfo {
        return ChatActiveGroupCallInfo(activeCall: activeCall, data: self.data, callJoinPeerId: callJoinPeerId, joinHash: self.joinHash, isLive: self.isLive)
    }
    public func withUpdatedJoinHash(_ joinHash: String?) -> ChatActiveGroupCallInfo {
        return ChatActiveGroupCallInfo(activeCall: self.activeCall, data: self.data, callJoinPeerId: self.callJoinPeerId, joinHash: joinHash, isLive: self.isLive)
    }
}




public struct ChatSearchModeState : Equatable {
    public var inSearch: Bool
    public var peer: EnginePeer?
    public var query: String?
    public var tag: HistoryViewInputTag?
    public var showAll: Bool = false
    public init(inSearch: Bool, peer: EnginePeer? = nil, query: String? = nil, tag: HistoryViewInputTag? = nil, showAll: Bool = false) {
        self.inSearch = inSearch
        self.peer = peer
        self.query = query
        self.tag = tag
        self.showAll = showAll
    }
}

public enum ChatState : Equatable {

    public enum AdditionIcon : Equatable {
        case gigagroup_info
        case monoforum_suggestion
        case channel_gift

        public func resolve(_ theme: TelegramPresentationTheme) -> CGImage {
            switch self {
            case .gigagroup_info:
                return theme.icons.chat_action_gigagroup_info
            case .monoforum_suggestion:
                return theme.icons.chat_action_monoforum
            case .channel_gift:
                return theme.icons.chat_action_gift
            }
        }
    }

    public struct AdditionAction {
        public let icon: AdditionIcon
        public let action: (ChatInteraction, NSView)->Void
        public init(icon: AdditionIcon, action: @escaping (ChatInteraction, NSView)->Void) {
            self.icon = icon
            self.action = action
        }
    }


    case normal
    case selecting
    case block(String)
    case action(String, (ChatInteraction)->Void, right: AdditionAction?, left: AdditionAction?, accent: Bool = false)
    case botStart(String, (ChatInteraction)->Void)
    case channelWithDiscussion(discussionGroupId: PeerId?, leftAction: String, rightAction: String)
    case editing
    case recording(ChatRecordingState)
    case restricted(String)
    case frozen((ChatInteraction)->Void)
}

public func ==(lhs:ChatState, rhs:ChatState) -> Bool {
    switch lhs {
    case .normal:
        if case .normal = rhs {
            return true
        } else {
            return false
        }
    case let .channelWithDiscussion(discussionGroupId, leftAction, rightAction):
        if case .channelWithDiscussion(discussionGroupId, leftAction, rightAction) = rhs {
            return true
        } else {
            return false
        }
    case .selecting:
        if case .selecting = rhs {
            return true
        } else {
            return false
        }
    case .editing:
        if case .editing = rhs {
            return true
        } else {
            return false
        }
    case .recording:
        if case .recording = rhs {
            return true
        } else {
            return false
        }
    case let .block(lhsReason):
        if case let .block(rhsReason) = rhs {
            return lhsReason == rhsReason
        } else {
            return false
        }
    case let .action(lhsAction,_, _, _, lhsAccent):
        if case let .action(rhsAction, _, _, _, rhsAccent) = rhs {
            return lhsAction == rhsAction && lhsAccent == rhsAccent
        } else {
            return false
        }
    case let .botStart(lhsAction,_):
        if case let .botStart(rhsAction, _) = rhs {
            return lhsAction == rhsAction
        } else {
            return false
        }
    case .restricted(let text):
        if case .restricted(text) = rhs {
            return true
        } else {
            return false
        }
    case .frozen:
        if case .frozen = rhs {
            return true
        } else {
            return false
        }
    }
}

public struct ChatPeerStatus : Equatable {
    public let canAddContact: Bool
    public let peerStatusSettings: PeerStatusSettings?
    public init(canAddContact: Bool, peerStatusSettings: PeerStatusSettings?) {
        self.canAddContact = canAddContact
        self.peerStatusSettings = peerStatusSettings
    }
}


public struct SavedMessageTagsValue : Equatable {
    public let tags: [SavedMessageTags.Tag]
    public let files: [Int64: TelegramMediaFile]
    public init(tags: [SavedMessageTags.Tag], files: [Int64: TelegramMediaFile]) {
        self.tags = tags
        self.files = files
    }
}

public struct ChatBotManagerData : Equatable {
    public let bot: TelegramAccountConnectedBot
    public let peer: EnginePeer
    public let settings: PeerStatusSettings.ManagingBot
    public init(bot: TelegramAccountConnectedBot, peer: EnginePeer, settings: PeerStatusSettings.ManagingBot) {
        self.bot = bot
        self.peer = peer
        self.settings = settings
    }
}


public class ChatPresentationInterfaceState: Equatable {
    
    public struct BotMenu : Equatable {
        public var commands: [BotCommand]
        public var revealed: Bool
        public var menuButton: BotMenuButton
        public init(commands: [BotCommand], revealed: Bool, menuButton: BotMenuButton) {
            self.commands = commands
            self.revealed = revealed
            self.menuButton = menuButton
        }
        
        public var isEmpty: Bool {
            switch self.menuButton {
            case .webView:
                return false
            case .commands:
                return self.commands.isEmpty
            }
        }
    }
    public struct TranslateState : Equatable {
        public var canTranslate: Bool
        public var translate: Bool
        public var from: String?
        public var to: String
        public var paywall: Bool
        public var tone: TranslationTone = .neutral
        public var result:[ChatLiveTranslateContext.State.Key : ChatLiveTranslateContext.State.Result]
        public init(canTranslate: Bool, translate: Bool, from: String? = nil, to: String, paywall: Bool, tone: TranslationTone = .neutral, result: [ChatLiveTranslateContext.State.Key : ChatLiveTranslateContext.State.Result]) {
            self.canTranslate = canTranslate
            self.translate = translate
            self.from = from
            self.to = to
            self.paywall = paywall
            self.tone = tone
            self.result = result
        }
    }
    
    public final class RemovePaidMessageFeeData: Equatable {
        public let peer: EnginePeer
        public let amount: StarsAmount
          
        public init(peer: EnginePeer, amount: StarsAmount) {
              self.peer = peer
              self.amount = amount
          }
          
        public static func ==(lhs: RemovePaidMessageFeeData, rhs: RemovePaidMessageFeeData) -> Bool {
            if lhs === rhs {
                return true
            }
            if lhs.peer != rhs.peer {
                return false
            }
            if lhs.amount != rhs.amount {
                return false
            }
            return true
        }
    }

    
    public let interfaceState: ChatInterfaceState
    public let peer: Peer?
    public let mainPeer: Peer?
    public let accountPeer: Peer?
    public let chatLocation: ChatLocation
    public let chatMode: ChatMode
    public let searchMode: ChatSearchModeState
    public let notificationSettings: TelegramPeerNotificationSettings?
    public let inputQueryResult: ChatPresentationInputQueryResult?
    public let keyboardButtonsMessage: Message?
    public let initialAction:ChatInitialAction?
    public let historyCount:Int?
    public let isBlocked:Bool?
    public let recordingState:ChatRecordingState?
    public let peerStatus:ChatPeerStatus?
    public let pinnedMessageId:ChatPinnedMessage?
    public let urlPreview: (String, TelegramMediaWebpage)?
    public let selectionState: ChatInterfaceSelectionState?
    public let limitConfiguration: LimitsConfiguration
    public let contentSettings: ContentSettings?
    public let sidebarEnabled:Bool?
    public let sidebarShown:Bool?
    public let layout:SplitViewState?
    public let discussionGroupId: CachedChannelData.LinkedDiscussionPeerId
    public let canAddContact:Bool?
    public let isEmojiSection: Bool
    public let canInvokeBasicActions:(delete: Bool, forward: Bool)
    public let isNotAccessible: Bool
    public let hasScheduled: Bool
    public let slowMode: SlowMode?
    public let failedMessageIds:Set<MessageId>
    public let hidePinnedMessage: Bool
    public let canPinMessage: Bool
    public let tempPinnedMaxId: MessageId?
    public let restrictionInfo: PeerAccessRestrictionInfo?
    public let groupCall: ChatActiveGroupCallInfo?
    public let messageSecretTimeout: CachedPeerAutoremoveTimeout?
    public let reportMode: ReportReasonValue?
    public let currentSendAsPeerId: PeerId?
    public let inviteRequestsPending: Int32?
    public let inviteRequestsPendingPeers:[PeerInvitationImportersState.Importer]?
    public let botMenu:BotMenu?
    public let sendAsPeers:[SendAsPeer]?
    public let allowedReactions:PeerAllowedReactions?
    public let attachItems:[AttachMenuBot]
    public let cachedData: CachedPeerData?
    public let presence: TelegramUserPresence?
    public let threadInfo: MessageHistoryThreadData?
    public let translateState: TranslateState?
    public let savedMessageTags: SavedMessageTagsValue?
    public let displaySavedChatsAsTopics: Bool
    
    public let playedMessageEffects: [MessageId]
    
    public let connectedBot: ChatBotManagerData?
    
    public let shortcuts: ShortcutMessageList?
    
    public let adMessage: Message?
    public let acknowledgedPaidMessage: Bool
    public let alwaysPaidMessage: Bool
    
    public let _sendPaidMessageStars: StarsAmount?
    
    public let starsState: StarsContext.State?
    
    public let freezeAccount: Int32
    public let freezeAccountAppealAddressName: String?
    
    public let monoforumState: MonoforumUIState?
    public let monoforumTopics: [MonoforumItem]
    public let removePaidMessageFeeData: RemovePaidMessageFeeData?
    
    public var allowPostSuggestion: Bool {
        if let peer, peer.isMonoForum, !peer.groupAccess.canManageDirect {
            return true
        } else {
            return false
        }
    }
    
    
    public var threadedBot: Bool {
        if let peer = peer, peer.isBot, peer.isForumOrMonoForum, peer.botInfo?.flags.contains(.forumManagedByUser) == true {
            return true
        } else {
            return false
        }
    }
    
    public var hasSetDestructiveTimer: Bool {
        
        if self.chatMode != .history {
            return false
        }
        
        if !self.interfaceState.inputState.inputText.isEmpty {
            return false
        }
        if self.chatLocation.peerId.namespace == Namespaces.Peer.SecretChat {
            return true
        }
        if let value = self.messageSecretTimeout {
            switch value {
            case let .known(value):
                if value != nil {
                    return true
                }
            default:
                return false
            }
        }
        
        return false
    }
    
    public var hasGift: Bool {
        if let peer, peer.isUser, effectiveInput.inputText.isEmpty {
            if let cachedData = cachedData as? CachedUserData, cachedData.flags.contains(.displayGiftButton) {
                return true
            }
            return peer.id == accountPeer?.id
        }
        return false
    }

    public var managedBotNeedsPhoto: Bool {
        if let cachedData = cachedData as? CachedUserData, cachedData.botManagerId != nil, let user = peer as? TelegramUser, user.profileImageRepresentations.isEmpty {
            return true
        }
        return false
    }

    public var inputContext: ChatPresentationInputQuery {
        return inputContextQueryForChatPresentationIntefaceState(self, includeContext: true)
    }
    
    public var messageEffect: AvailableMessageEffects.MessageEffect? {
        return self.interfaceState.messageEffect?.effect
    }
    
    public func canSendReactions(to peer: Peer) -> Bool {
        var ignoreDefault = false
        if peer.id == self.peer?.id, let cachedData = cachedData as? CachedChannelData, let boostsToUnrestrict = cachedData.boostsToUnrestrict, boostsToUnrestrict > 0, let appliedBoosts = cachedData.appliedBoosts, appliedBoosts >= boostsToUnrestrict {
            ignoreDefault = true
        }
        return canSendReactionsToPeer(EnginePeer(peer), ignoreDefault: ignoreDefault)
    }
    
    public var boostNeed: Int32 {
        if let cachedData = cachedData as? CachedChannelData, peer?.isAdmin == false {
            if let boostsToUnrestrict = cachedData.boostsToUnrestrict, slowMode?.timeout != nil {
                let appliedBoosts = cachedData.appliedBoosts ?? 0
                if boostsToUnrestrict > appliedBoosts {
                    return boostsToUnrestrict - appliedBoosts
                }
            }
        }
        return 0
    }
        
    public var totalBoostNeed: Int32? {
        if let cachedData = cachedData as? CachedChannelData, peer?.isAdmin == false {
            if let boostsToUnrestrict = cachedData.boostsToUnrestrict {
                let appliedBoosts = cachedData.appliedBoosts ?? 0
                if boostsToUnrestrict > appliedBoosts {
                    return boostsToUnrestrict
                } else {
                    return 0
                }
            }
        }
        return nil
    }
    
    public var restrictedByBoosts: Bool {
        if let cachedData = cachedData as? CachedChannelData, peer?.isAdmin == false {
            if let boostsToUnrestrict = cachedData.boostsToUnrestrict {
                return boostsToUnrestrict > 0
            }
        }
        return false
    }
    
    public var effectiveInputContext: ChatPresentationInputQuery {
        let current = inputContextQueryForChatPresentationIntefaceState(self, includeContext: true)
        if case .contextRequest = current {
            let without = inputContextQueryForChatPresentationIntefaceState(self, includeContext: false)
            
            return without
        } else {
            return current
        }
    }
    
    public var isKeyboardActive:Bool {
        guard let reply = keyboardButtonsMessage?.replyMarkup else {
            return false
        }
        
        return reply.rows.count > 0 && !reply.flags.contains(.persistent)
    }
    
    public var canPinMessageInPeer: Bool {
        if let peer = peer as? TelegramChannel, peer.hasPermission(.pinMessages) || (peer.isChannel && peer.hasPermission(.editAllMessages)) {
            return true
        } else if let peer = peer as? TelegramGroup, peer.canPinMessage {
            return true
        } else if let _ = peer as? TelegramSecretChat {
            return false
        } else {
            return canPinMessage
        }
    }
    
    public var canReplyInRestrictedMode: Bool {
        if state == .normal {
            return true
        } else if case .restricted = state, let peer = self.peer, peer.isForumOrMonoForum, case .history = self.chatMode {
            return true
        } else if let peer = peer, peer.isChannel {
            return peer.isChannel
        }
        return false
    }
    
    
    public var sendPaidMessageStars: StarsAmount? {
        if let _sendPaidMessageStars {
            return _sendPaidMessageStars.value > 0 ? _sendPaidMessageStars : nil
        } else if let cachedData = cachedData as? CachedUserData {
            return cachedData.sendPaidMessageStars.flatMap { $0.value > 0 ? $0 : nil }
        } else if let peer = peer as? TelegramChannel, !peer.isAdmin, let stars = peer.sendPaidMessageStars, stars.value > 0 {
            return stars
        } else {
            return nil
        }
    }
    
    public var isTopicMode: Bool {
        if let peer = peer, ChatInterfaceHooks.shared.peerIsForum(peer), peer.displayForumAsTabs {
            return chatLocation.threadId != nil
        }
        return chatMode.isTopicMode
    }
    
    public var isMonoforum: Bool {
        if let peer, peer.isMonoForum {
            return true
        } else {
            return false
        }
    }
    
    public var state:ChatState {
        if self.selectionState == nil {
            if let initialAction = initialAction, case .start = initialAction  {
                return .botStart(strings().chatInputStartBot, { chatInteraction in
                    chatInteraction.invokeInitialAction()
                })
            }
            
            
            if let recordingState = recordingState {
                return .recording(recordingState)
            }
            
            if self.interfaceState.editState != nil {
                return .editing
            }
            if self.interfaceState.themeEditing {
                return .block("")
            }
            if self.chatMode == .preview {
                return .block("")
            }
            
            if self.freezeAccount != 0, self.peer?.addressName?.lowercased() != self.freezeAccountAppealAddressName {
                return .frozen({ chatInteraction in
                    chatInteraction.freezeAccountAlert()
                })
            }
            
            if case .searchHashtag = chatMode.customChatContents?.kind {
                return .action(strings().navigationClose, { chatInteraction in
                    chatInteraction.context.bindings.rootNavigation().back()
                }, right: nil, left: nil)
            }
            
            
            if self.peer?.restrictionText(contentSettings) != nil {
                return .action(strings().navigationClose, { chatInteraction in
                    chatInteraction.context.bindings.rootNavigation().back()
                }, right: nil, left: nil)
            }

            if let contents = chatMode.customChatContents, let count = self.historyCount, let limit = contents.messageLimit, count >= limit {
                if contents.kind == .welcomeMessages {
                    return .block(strings().welcomeMessageLimitReached(limit))
                } else {
                    return .block(strings().chatQuickReplyMessageLimitReachedTextOther(limit))
                }
            }
            
            if searchMode.tag != nil {
                return .action(!searchMode.showAll ? strings().chatStateShowOtherMessages : strings().chatStateHideOtherMessages, { chatInteraction in
                    chatInteraction.update { current in
                        var search = current.searchMode
                        search.showAll = !search.showAll
                        return current.updatedSearchMode(search)
                    }
                }, right: nil, left: nil)
            }
            
//            if let cachedData = cachedData as? CachedUserData, let starsState, let starsAmount = cachedData.sendPaidMessageStars, let peer {
//                if (!self.acknowledgedPaidMessage && alwaysPaidMessage) || starsState.balance.value < starsAmount.value {
//                    return .paidMessage(starsAmount, { chatInteraction in
//                        let amount = strings().starListItemCountOther(Int(starsAmount.value))
//                        if starsState.balance.value > starsAmount.value {
//                            verifyAlert(for: chatInteraction.context.window, header: strings().chatPayStarsConfirmTitle, information: strings().chatPayStarsConfirmText(peer.displayTitle, amount, amount), ok: strings().chatPayStarsConfirmPay, option: strings().chatPayStarsConfirmCheckbox, optionIsSelected: false, successHandler: { result in
//                                chatInteraction.update({ current in
//                                    return current
//                                        .withUpdatedAcknowledgedPaidMessage(true)
//                                        .withUpdatedAlwaysPaidMessage(result != .thrid)
//                                })
//                            })
//                        } else {
//                            showModal(with: Star_ListScreen(context:chatInteraction.context, source: .buy(suffix: nil, amount: starsAmount.value)), for: chatInteraction.context.window)
//                        }
//                                                
//                    })
//                }
//            }
            
            
            if let peer = peer, peer.maybePremiumRequired {
                if let cachedData = cachedData as? CachedUserData, cachedData.flags.contains(.premiumRequired), accountPeer?.isPremium == false {
                    return .block(strings().chatInputPremiumRequiredState(peer.compactDisplayTitle))
                }
            }
            if chatLocation.peerId == repliesPeerId {
                return .action(notificationSettings?.isMuted ?? false ? strings().chatInputUnmute : strings().chatInputMute, { chatInteraction in
                    chatInteraction.toggleNotifications(nil)
                }, right: nil, left: nil)
            }

            if chatMode.isSavedMessagesThread, let threadId64 = chatLocation.threadId {
                if PeerId(threadId64) != accountPeer?.id {
                    return .action(strings().chatInputOpenChat, { chatInteraction in
                        chatInteraction.openInfo(PeerId(threadId64), true, nil, nil)
                    }, right: nil, left: nil)
                }
            }
            
            
            if chatMode.isThreadMode, chatLocation.peerId == accountPeer?.id, let threadId64 = chatLocation.threadId {
                return .action(strings().chatInputOpenChat, { chatInteraction in
                    chatInteraction.openInfo(PeerId(threadId64), true, nil, nil)
                }, right: nil, left: nil)
            }
            
            switch chatMode {
            case .pinned:
                if canPinMessageInPeer {
                    return .action(strings().chatPinnedUnpinAllOther(pinnedMessageId?.totalCount ?? 0), { chatInteraction in
                        let navigation = chatInteraction.context.bindings.rootNavigation()
                        (navigation.previousController as? ChatInterfaceController)?.chatInteraction.unpinAllMessages()
                    }, right: nil, left: nil)
                } else {
                    return .action(strings().chatPinnedDontShow, { chatInteraction in
                        let navigation = chatInteraction.context.bindings.rootNavigation()
                        (navigation.previousController as? ChatInterfaceController)?.chatInteraction.unpinAllMessages()
                    }, right: nil, left: nil)
                }
                
            default:
                break
            }
            
            if let peer = peer as? TelegramChannel {
                #if APP_STORE
                if let restrictionInfo = restrictionInfo {
                    for rule in restrictionInfo.rules {
                        if rule.platform == "ios" || rule.platform == "all" {
                            return .action(strings().chatInputClose, { chatInteraction in
                                chatInteraction.back()
                            }, right: nil, left: nil)
                        }
                    }
                }
                #endif

                if peer.flags.contains(.isGigagroup) {
                    if peer.participationStatus == .left {
                        return .action(strings().chatInputJoin, { chatInteraction in
                            chatInteraction.joinChannel()
                        }, right: nil, left: nil, accent: true)
                    } else if peer.adminRights == nil && !peer.groupAccess.isCreator {
                        if let notificationSettings = notificationSettings {
                            return .action(notificationSettings.isMuted ? strings().chatInputUnmute : strings().chatInputMute, { chatInteraction in
                                chatInteraction.toggleNotifications(nil)
                            }, right: .init(icon: .gigagroup_info, action: { _, control in
                                tooltip(for: control, text: strings().chatGigagroupHelp)
                            }), left: nil)
                        } else {
                            return .action(strings().chatInputMute, { chatInteraction in
                                chatInteraction.toggleNotifications(nil)
                            }, right: .init(icon: .gigagroup_info, action: { _, control in

                            }), left: nil)
                        }
                    }

                }
                
                switch chatMode {
                case .thread:
                    if let data = threadInfo {
                        if data.isClosed, peer.adminRights == nil && !peer.flags.contains(.isCreator) && !data.isOwnedByMe {
                            return .restricted(strings().chatInputTopicClosed)
                        }
                    }
                    if peer.participationStatus == .left {
                        if peer.flags.contains(.joinToSend) || chatMode.isTopicMode {
                            return .action(strings().chatInputJoin, { chatInteraction in
                                chatInteraction.joinChannel()
                            }, right: nil, left: nil, accent: true)
                        } else {
                            return .normal
                        }
                    } else if peer.participationStatus == .kicked {
                        return .restricted(strings().chatCommentsKicked)
                    } else if peer.participationStatus == .member {
                        return .normal
                    }
                    
                case .history:
                    if ChatInterfaceHooks.shared.peerIsForum(peer) {
                        let viewForumAsMessages = (cachedData as? CachedChannelData)?.viewForumAsMessages.knownValue
                        if viewForumAsMessages == false || viewForumAsMessages == nil {
                            if interfaceState.replyMessage == nil && chatLocation.threadId == nil {
                                return .restricted(strings().chatInputReplyToAnswer)
                            }
                        }
                    } else if peer.isMonoForum, chatLocation.threadId == nil, peer.isAdmin {
                        if interfaceState.replyMessage == nil {
                            return .restricted(strings().chatInputReplyToAnswerMonoforumNew)
                        }
                    }
                default:
                    break
                }
                
                
                var monoforum: ChatState.AdditionAction? = nil
                var gift: ChatState.AdditionAction? = nil
                
                if peer.participationStatus == .left || peer.participationStatus == .kicked {
                    if peer.flags.contains(.isMonoforum) {
                        return .normal
                    }
                }
                
                if peer.participationStatus == .member, let monoforumId = peer.linkedMonoforumId {
                    switch peer.info {
                    case let .broadcast(info):
                        if info.flags.contains(.hasMonoforum) {
                            monoforum = .init(icon: .monoforum_suggestion, action: { chatInteraction, _ in
                                chatInteraction.openMonoforum(monoforumId)
                            })
                        }
                    default:
                        break
                    }
                }
                if let cachedData = cachedData as? CachedChannelData, cachedData.flags.contains(.starGiftsAvailable) {
                    gift = .init(icon: .channel_gift, action: { chatInteraction, control in
                        showModal(with: GiftingController(context: chatInteraction.context, peerId: peer.id, isBirthday: false), for: chatInteraction.context.window, morphSource: { [weak control] in control })
                    })
                }
               
                
                if peer.participationStatus == .left {
                    return .action(strings().chatInputJoin, { chatInteraction in
                        chatInteraction.joinChannel()
                    }, right: nil, left: nil, accent: true)
                } else if peer.participationStatus == .kicked {
                    return .action(strings().chatInputDelete, { chatInteraction in
                        chatInteraction.removeAndCloseChat()
                    }, right: nil, left: nil)
                } else if !peer.canSendMessage(chatMode.isThreadMode), let notificationSettings = notificationSettings, peer.isChannel {
                    return .action(notificationSettings.isMuted ? strings().chatInputUnmute : strings().chatInputMute, { chatInteraction in
                        chatInteraction.toggleNotifications(nil)
                    }, right: gift, left: monoforum)
                }
            } else if let peer = peer as? TelegramGroup {
                if  peer.membership == .Left {
                    return .action(strings().chatInputReturn,{ chatInteraction in
                        chatInteraction.returnGroup()
                    }, right: nil, left: nil)
                } else if peer.membership == .Removed {
                    return .action(strings().chatInputDelete, { chatInteraction in
                        chatInteraction.removeAndCloseChat()
                    }, right: nil, left: nil)
                }
            } else if let peer = peer as? TelegramSecretChat, let mainPeer = mainPeer {
                
                switch peer.embeddedState {
                case .terminated:
                    return .action(strings().chatInputDelete, { chatInteraction in
                        chatInteraction.removeAndCloseChat()
                    }, right: nil, left: nil)
                case .handshake:
                    return .restricted(strings().chatInputSecretChatWaitingToUserOnline(mainPeer.compactDisplayTitle))
                default:
                    break
                }
            }
            
            if let peer = peer, !peer.canSendMessage(chatMode.isThreadMode), let notificationSettings = notificationSettings, peer.isChannel {
                return .action(notificationSettings.isMuted ? strings().chatInputUnmute : strings().chatInputMute, { chatInteraction in
                    chatInteraction.toggleNotifications(nil)
                }, right: nil, left: nil)
            }
            
            //, !peer.hasPermission(.sendSomething)
            
            if let peer = peer as? TelegramChannel {
                if let text = permissionText(from: peer, for: .banSendText) {
                    
                    let isPersonalRestriction = peer.hasBannedPermission(.banSendText)?.1 ?? false
                    
                    if let cachedData = cachedData as? CachedChannelData, let boostsToRestrict = cachedData.boostsToUnrestrict, !isPersonalRestriction {
                        let appliedBoosts = cachedData.appliedBoosts ?? 0
                        if boostsToRestrict > appliedBoosts {
                            return .action(strings().boostGroupChatInputAction, { chatInteraction in
                                chatInteraction.boostToUnrestrict(.unblockText(boostsToRestrict))
                            }, right: nil, left: nil)
                        }
                    } else {
                        return .restricted(text)
                    }
                }
            }
            
            if let blocked = isBlocked, blocked {
                
                if let peer = peer, peer.isBot {
                    return .action(strings().chatInputRestart, { chatInteraction in
                        chatInteraction.unblock()
                        chatInteraction.startBot()
                    }, right: nil, left: nil)
                }
                
                return .action(strings().chatInputUnblock, { chatInteraction in
                    chatInteraction.unblock()
                }, right: nil, left: nil)
            }
            
            if let peer = peer as? TelegramUser {
                if let _ = peer.botInfo, let historyCount = historyCount, historyCount == 0 {
                    return .botStart(strings().chatInputStartBot, { chatInteraction in
                        chatInteraction.startBot()
                    })
                }
            }
           
            
            return .normal
        } else {
            return .selecting
        }
    }
    
    public var canScheduleWhenOnline: Bool {
        if let presence = self.presence {
            switch presence.status {
            case .present:
                return true
            default:
                return false
            }
        }
        return false
    }

    public var isKeyboardShown:Bool {
        if let keyboard = keyboardButtonsMessage, let attribute = keyboard.replyMarkup {
            return interfaceState.messageActionsState.closedButtonKeyboardMessageId != keyboard.id && attribute.hasButtons && state == .normal

        }
        return false
    }
    
    public var isShowSidebar: Bool {
        if let sidebarEnabled = sidebarEnabled, let peer = peer, let sidebarShown = sidebarShown {
            return sidebarEnabled && peer.canSendMessage(chatMode.isThreadMode) && sidebarShown
        }
        return false
    }
    
    public var slowModeMultipleLocked: Bool {
        if let _ = self.slowMode {
            
            var keys:[Int64:Int64] = [:]
            var forwardMessages:[Message] = []
            for message in self.interfaceState.forwardMessages {
                if let groupingKey = message.groupingKey {
                    if keys[groupingKey] == nil {
                        keys[groupingKey] = groupingKey
                        forwardMessages.append(message)
                    }
                } else {
                    forwardMessages.append(message)
                }
            }
            if forwardMessages.count > 1 || (!effectiveInput.inputText.isEmpty && forwardMessages.count == 1) {
                return true
            } else if effectiveInput.inputText.length > 4096 {
                return true
            }
        }
        return false
    }
    
    public var slowModeErrorText: String? {
        if let slowMode = self.slowMode, slowMode.hasLocked {
            return slowMode.errorText
        } else if slowModeMultipleLocked {
            if effectiveInput.inputText.length > 4096 {
                return strings().slowModeTooLongError
            }
            return strings().slowModeForwardCommentError
        } else {
            return nil
        }
    }
    
    public var abilityToSend:Bool {
        if state == .normal {
            if let suggestPost = interfaceState.suggestPost, suggestPost.amount == nil {
                return false
            }
            if let slowMode = self.slowMode {
                if slowMode.hasLocked {
                    return false
                } else if self.slowModeMultipleLocked {
                    return false
                }
            }
            return (!effectiveInput.inputText.isEmpty || !interfaceState.forwardMessageIds.isEmpty)
        } else if let editState = interfaceState.editState {
            if editState.message.media.count == 0 {
                return !effectiveInput.inputText.isEmpty
            } else {
                for media in editState.message.media {
                    if !(media is TelegramMediaWebpage) {
                        return true
                    }
                }
                return !effectiveInput.inputText.isEmpty
            }
        }
        
        return false
    }
    
    
    
    public var effectiveInput:ChatTextInputState {
        if let editState = interfaceState.editState {
            return editState.inputState
        } else {
            return interfaceState.inputState
        }
    }
    
    public init(chatLocation: ChatLocation, chatMode: ChatMode) {
        self.interfaceState = ChatInterfaceState()
        self.peer = nil
        self.notificationSettings = nil
        self.inputQueryResult = nil
        self.keyboardButtonsMessage = nil
        self.initialAction = nil
        self.historyCount = 0
        self.searchMode = .init(inSearch: false)
        self.recordingState = nil
        self.isBlocked = nil
        self.peerStatus = nil
        self.pinnedMessageId = nil
        self.urlPreview = nil
        self.selectionState = nil
        self.sidebarEnabled = nil
        self.sidebarShown = nil
        self.layout = nil
        self.canAddContact = nil
        self.isEmojiSection = FastSettings.entertainmentState == .emoji
        self.chatLocation = chatLocation
        self.chatMode = chatMode
        self.canInvokeBasicActions = (delete: false, forward: false)
        self.isNotAccessible = false
        self.restrictionInfo = nil
        self.mainPeer = nil
        self.limitConfiguration = LimitsConfiguration.defaultValue
        self.discussionGroupId = .unknown
        self.slowMode = nil
        self.hasScheduled = false
        self.failedMessageIds = Set()
        self.hidePinnedMessage = false
        self.canPinMessage = false
        self.tempPinnedMaxId = nil
        self.groupCall = nil
        self.messageSecretTimeout = nil
        self.reportMode = nil
        self.botMenu = nil
        self.inviteRequestsPending = nil
        self.inviteRequestsPendingPeers = nil
        self.currentSendAsPeerId = nil
        self.sendAsPeers = nil
        self.allowedReactions = nil
        self.attachItems = []
        self.cachedData = nil
        self.threadInfo = nil
        self.translateState = nil
        self.presence = nil
        self.savedMessageTags = nil
        self.accountPeer = nil
        self.displaySavedChatsAsTopics = false
        self.shortcuts = nil
        self.connectedBot = nil
        self.contentSettings = nil
        self.playedMessageEffects = []
        self.adMessage = nil
        self.acknowledgedPaidMessage = false
        self.alwaysPaidMessage = false
        self.starsState = nil
        self._sendPaidMessageStars = nil
        self.freezeAccount = 0
        self.freezeAccountAppealAddressName = nil
        self.monoforumState = nil
        self.monoforumTopics = []
        self.removePaidMessageFeeData = nil
    }
    
    public init(interfaceState: ChatInterfaceState, peer: Peer?, notificationSettings:TelegramPeerNotificationSettings?, inputQueryResult: ChatPresentationInputQueryResult?, keyboardButtonsMessage:Message?, initialAction:ChatInitialAction?, historyCount:Int?, searchMode: ChatSearchModeState, recordingState: ChatRecordingState?, isBlocked:Bool?, peerStatus: ChatPeerStatus?, pinnedMessageId:ChatPinnedMessage?, urlPreview: (String, TelegramMediaWebpage)?, selectionState: ChatInterfaceSelectionState?, sidebarEnabled: Bool?, sidebarShown: Bool?, layout:SplitViewState?, canAddContact:Bool?, isEmojiSection: Bool, chatLocation: ChatLocation, chatMode: ChatMode, canInvokeBasicActions: (delete: Bool, forward: Bool), isNotAccessible: Bool, restrictionInfo: PeerAccessRestrictionInfo?, mainPeer: Peer?, limitConfiguration: LimitsConfiguration, discussionGroupId: CachedChannelData.LinkedDiscussionPeerId, slowMode: SlowMode?, hasScheduled: Bool, failedMessageIds: Set<MessageId>, hidePinnedMessage: Bool, canPinMessage: Bool, tempPinnedMaxId: MessageId?, groupCall: ChatActiveGroupCallInfo?, messageSecretTimeout: CachedPeerAutoremoveTimeout?, reportMode: ReportReasonValue?, botMenu: BotMenu?, inviteRequestsPending: Int32?, inviteRequestsPendingPeers: [PeerInvitationImportersState.Importer]?, currentSendAsPeerId: PeerId?, sendAsPeers:[SendAsPeer]?, allowedReactions:PeerAllowedReactions?, attachItems: [AttachMenuBot], cachedData: CachedPeerData?, threadInfo: MessageHistoryThreadData?, translateState: TranslateState?, presence: TelegramUserPresence?, savedMessageTags: SavedMessageTagsValue?, accountPeer: Peer?, displaySavedChatsAsTopics: Bool, shortcuts: ShortcutMessageList?, connectedBot: ChatBotManagerData?, contentSettings: ContentSettings?, playedMessageEffects: [MessageId], adMessage: Message?, acknowledgedPaidMessage: Bool, alwaysPaidMessage: Bool, starsState: StarsContext.State?, sendPaidMessageStars: StarsAmount?, freezeAccount: Int32, freezeAccountAppealAddressName: String?, monoforumState: MonoforumUIState?, monoforumTopics: [MonoforumItem], removePaidMessageFeeData: RemovePaidMessageFeeData?) {
        self.interfaceState = interfaceState
        self.peer = peer
        self.notificationSettings = notificationSettings
        self.inputQueryResult = inputQueryResult
        self.keyboardButtonsMessage = keyboardButtonsMessage
        self.initialAction = initialAction
        self.historyCount = historyCount
        self.searchMode = searchMode
        self.recordingState = recordingState
        self.isBlocked = isBlocked
        self.peerStatus = peerStatus
        self.pinnedMessageId = pinnedMessageId
        self.urlPreview = urlPreview
        self.selectionState = selectionState
        self.sidebarEnabled = sidebarEnabled
        self.sidebarShown = sidebarShown
        self.layout = layout
        self.canAddContact = canAddContact
        self.isEmojiSection = isEmojiSection
        self.chatLocation = chatLocation
        self.canInvokeBasicActions = canInvokeBasicActions
        self.isNotAccessible = isNotAccessible
        self.restrictionInfo = restrictionInfo
        self.mainPeer = mainPeer
        self.limitConfiguration = limitConfiguration
        self.discussionGroupId = discussionGroupId
        self.slowMode = slowMode
        self.hasScheduled = hasScheduled
        self.failedMessageIds = failedMessageIds
        self.chatMode = chatMode
        self.hidePinnedMessage = hidePinnedMessage
        self.canPinMessage = canPinMessage
        self.tempPinnedMaxId = tempPinnedMaxId
        self.groupCall = groupCall
        self.messageSecretTimeout = messageSecretTimeout
        self.reportMode = reportMode
        self.botMenu = botMenu
        self.inviteRequestsPending = inviteRequestsPending
        self.inviteRequestsPendingPeers = inviteRequestsPendingPeers
        self.currentSendAsPeerId = currentSendAsPeerId
        self.sendAsPeers = sendAsPeers
        self.allowedReactions = allowedReactions
        self.attachItems = attachItems
        self.cachedData = cachedData
        self.threadInfo = threadInfo
        self.translateState = translateState
        self.presence = presence
        self.savedMessageTags = savedMessageTags
        self.accountPeer = accountPeer
        self.displaySavedChatsAsTopics = displaySavedChatsAsTopics
        self.shortcuts = shortcuts
        self.connectedBot = connectedBot
        self.contentSettings = contentSettings
        self.playedMessageEffects = playedMessageEffects
        self.adMessage = adMessage
        self.acknowledgedPaidMessage = acknowledgedPaidMessage
        self.alwaysPaidMessage = alwaysPaidMessage
        self.starsState = starsState
        self._sendPaidMessageStars = sendPaidMessageStars
        self.freezeAccount = freezeAccount
        self.freezeAccountAppealAddressName = freezeAccountAppealAddressName
        self.monoforumState = monoforumState
        self.monoforumTopics = monoforumTopics
        self.removePaidMessageFeeData = removePaidMessageFeeData
    }
    
    public static func ==(lhs: ChatPresentationInterfaceState, rhs: ChatPresentationInterfaceState) -> Bool {
        if lhs.interfaceState != rhs.interfaceState {
            return false
        }
        if lhs.removePaidMessageFeeData != rhs.removePaidMessageFeeData {
            return false
        }
        if lhs.discussionGroupId != rhs.discussionGroupId {
            return false
        }
        if let lhsPeer = lhs.peer, let rhsPeer = rhs.peer {
            if !lhsPeer.isEqual(rhsPeer) {
                return false
            }
        } else if (lhs.peer == nil) != (rhs.peer == nil) {
            return false
        }
        if lhs.translateState != rhs.translateState {
            return false
        }
        if lhs.contentSettings != rhs.contentSettings {
            return false
        }
        
        if lhs.playedMessageEffects != rhs.playedMessageEffects {
            return false
        }
        if lhs.freezeAccountAppealAddressName != rhs.freezeAccountAppealAddressName {
            return false
        }
        
        if lhs.freezeAccount != rhs.freezeAccount {
            return false
        }
        
        if let lhsPeer = lhs.mainPeer, let rhsPeer = rhs.mainPeer {
            if !lhsPeer.isEqual(rhsPeer) {
                return false
            }
        } else if (lhs.mainPeer == nil) != (rhs.mainPeer == nil) {
            return false
        }
        if let lhsPeer = lhs.accountPeer, let rhsPeer = rhs.accountPeer {
            if !lhsPeer.isEqual(rhsPeer) {
                return false
            }
        } else if (lhs.accountPeer == nil) != (rhs.accountPeer == nil) {
            return false
        }
        if lhs.tempPinnedMaxId != rhs.tempPinnedMaxId {
            return false
        }
        if lhs.inviteRequestsPending != rhs.inviteRequestsPending {
            return false
        }
        if lhs.inviteRequestsPendingPeers != rhs.inviteRequestsPendingPeers {
            return false
        }
        if lhs.restrictionInfo != rhs.restrictionInfo {
            return false
        }
        if lhs.limitConfiguration != rhs.limitConfiguration {
            return false
        }
        if lhs.botMenu != rhs.botMenu {
            return false
        }
        if lhs.chatLocation != rhs.chatLocation {
            return false
        }
        if lhs.hasScheduled != rhs.hasScheduled {
            return false
        }
        if lhs.chatMode != rhs.chatMode {
            return false
        }
        if lhs.canPinMessage != rhs.canPinMessage {
            return false
        }
        if lhs.hidePinnedMessage != rhs.hidePinnedMessage {
            return false
        }
        if lhs.state != rhs.state {
            return false
        }
        if lhs.slowMode != rhs.slowMode {
            return false
        }
        if lhs.searchMode != rhs.searchMode {
            return false
        }
        if lhs.sidebarEnabled != rhs.sidebarEnabled {
            return false
        }
        if lhs.sidebarShown != rhs.sidebarShown {
            return false
        }
        if lhs.layout != rhs.layout {
            return false
        }
        if lhs.canAddContact != rhs.canAddContact {
            return false
        }
        if lhs.reportMode != rhs.reportMode {
            return false
        }
        if lhs.shortcuts != rhs.shortcuts {
            return false
        }
        if lhs.connectedBot != rhs.connectedBot {
            return false
        }
        if lhs.recordingState != rhs.recordingState {
            return false
        }
        if lhs.currentSendAsPeerId != rhs.currentSendAsPeerId {
            return false
        }
        if lhs.inputQueryResult != rhs.inputQueryResult {
            return false
        }
        
        if lhs.initialAction != rhs.initialAction {
            return false
        }
        
        if lhs.historyCount != rhs.historyCount {
            return false
        }
        
        if lhs.isBlocked != rhs.isBlocked {
            return false
        }
        
        if lhs.peerStatus != rhs.peerStatus {
            return false
        }
        if lhs.isNotAccessible != rhs.isNotAccessible {
            return false
        }
        
        if lhs.selectionState != rhs.selectionState {
            return false
        }
        if lhs.sendAsPeers != rhs.sendAsPeers {
            return false
        }
        if lhs.groupCall != rhs.groupCall {
            return false
        }
        if lhs.messageSecretTimeout != rhs.messageSecretTimeout {
            return false
        }
        
        if lhs.pinnedMessageId != rhs.pinnedMessageId {
            return false
        }
        if lhs.isEmojiSection != rhs.isEmojiSection {
            return false
        }
        if lhs.failedMessageIds != rhs.failedMessageIds {
            return false
        }
        if lhs.allowedReactions != rhs.allowedReactions {
            return false
        }
        if lhs.savedMessageTags != rhs.savedMessageTags {
            return false
        }
        
        if lhs.acknowledgedPaidMessage != rhs.acknowledgedPaidMessage {
            return false
        }
        if lhs.alwaysPaidMessage != rhs.alwaysPaidMessage {
            return false
        }
        if lhs.starsState != rhs.starsState {
            return false
        }
        
        if lhs._sendPaidMessageStars != rhs._sendPaidMessageStars || lhs.sendPaidMessageStars != rhs.sendPaidMessageStars {
            return false
        }
        
        if lhs.displaySavedChatsAsTopics != rhs.displaySavedChatsAsTopics {
            return false
        }
        
        if let lhsUrlPreview = lhs.urlPreview, let rhsUrlPreview = rhs.urlPreview {
            if lhsUrlPreview.0 != rhsUrlPreview.0 {
                return false
            }
            if !lhsUrlPreview.1.isEqual(to: rhsUrlPreview.1) {
                return false
            }
        } else if (lhs.urlPreview != nil) != (rhs.urlPreview != nil) {
            return false
        }
        
        if let lhsMessage = lhs.keyboardButtonsMessage, let rhsMessage = rhs.keyboardButtonsMessage {
            if  lhsMessage.id != rhsMessage.id || lhsMessage.stableVersion != rhsMessage.stableVersion {
                return false
            }
        } else if (lhs.keyboardButtonsMessage == nil) != (rhs.keyboardButtonsMessage == nil) {
            return false
        }
        
        if lhs.effectiveInput != rhs.effectiveInput {
            if lhs.inputContext != rhs.inputContext {
                return false
            }
        }
        
        if lhs.canInvokeBasicActions != rhs.canInvokeBasicActions {
            return false
        }
        
        if let lhsCachedData = lhs.cachedData, let rhsCachedData = rhs.cachedData {
            if !lhsCachedData.isEqual(to: rhsCachedData) {
                return false
            }
        } else if (lhs.cachedData != nil) != (rhs.cachedData != nil) {
            return false
        }
        
        if lhs.threadInfo != rhs.threadInfo {
            return false
        }
        if lhs.presence != rhs.presence {
            return false
        }
        if lhs.adMessage != rhs.adMessage {
            return false
        }
        if lhs.monoforumState != rhs.monoforumState {
            return false
        }
        if lhs.monoforumTopics != rhs.monoforumTopics {
            return false
        }
        return true
    }
    
    public func updatedInterfaceState(_ f: (ChatInterfaceState) -> ChatInterfaceState) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: f(self.interfaceState), peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
        
    }

    public func updatedKeyboardButtonsMessage(_ message: Message?) -> ChatPresentationInterfaceState {
        let interface = ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:message, initialAction:self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
        
        if let peerId = peer?.id, let keyboardMessage = interface.keyboardButtonsMessage {
            if keyboardButtonsMessage?.id != keyboardMessage.id || keyboardButtonsMessage?.stableVersion != keyboardMessage.stableVersion {
                if peerId.namespace == Namespaces.Peer.CloudChannel || peerId.namespace == Namespaces.Peer.CloudGroup {
                    return interface.updatedInterfaceState({$0.withUpdatedMessageActionsState({$0.withUpdatedProcessedSetupReplyMessageId(keyboardMessage.id)})})
                }
            }
            
        }
        return interface
    }
    
    public func updatedPeer(_ f: (Peer?) -> Peer?) -> ChatPresentationInterfaceState {
        
        let peer = f(self.peer)
        
        var restrictionInfo: PeerAccessRestrictionInfo? = self.restrictionInfo
        if let peer = peer as? TelegramChannel, let info = peer.restrictionInfo {
            restrictionInfo = info
        }
        
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func updatedMainPeer(_ mainPeer: Peer?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: restrictionInfo, mainPeer: mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func updatedNotificationSettings(_ notificationSettings:TelegramPeerNotificationSettings?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer:self.peer, notificationSettings: notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    
    
    public func updatedHistoryCount(_ historyCount:Int?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer:self.peer, notificationSettings: notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:self.initialAction, historyCount: historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func updatedSearchMode(_ searchMode: ChatSearchModeState) -> ChatPresentationInterfaceState {


        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer:self.peer, notificationSettings: notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:self.initialAction, historyCount: historyCount, searchMode: searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func updatedInputQueryResult(_ f: (ChatPresentationInputQueryResult?) -> ChatPresentationInputQueryResult?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: f(self.inputQueryResult), keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func updatedInitialAction(_ initialAction:ChatInitialAction?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    
    public func withRecordingState(_ state:ChatRecordingState) -> ChatPresentationInterfaceState {
         return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: state, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withoutRecordingState() -> ChatPresentationInterfaceState {
         return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: nil, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedBlocked(_ blocked:Bool) -> ChatPresentationInterfaceState {
         return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: blocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedPinnedMessageId(_ pinnedMessageId:ChatPinnedMessage?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    
    public func withUpdatedPeerStatusSettings(_ peerStatus:ChatPeerStatus?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withEditMessage(_ message:Message) -> ChatPresentationInterfaceState {
        return self.updatedInterfaceState({$0.withEditMessage(message)})
    }
    
    public func withoutEditMessage() -> ChatPresentationInterfaceState {
        return self.updatedInterfaceState({$0.withoutEditMessage()})
    }
    
    public func withUpdatedEffectiveInputState(_ inputState: ChatTextInputState) -> ChatPresentationInterfaceState {
        return self.updatedInterfaceState({$0.withUpdatedInputState(inputState)})
    }
    
    public func updatedUrlPreview(_ urlPreview: (String, TelegramMediaWebpage)?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    
    public func isSelectedMessageId(_ messageId:MessageId) -> Bool {
        if let selectionState = selectionState {
            return selectionState.selectedIds.contains(messageId)
        }
        return false
    }
    
    public func withUpdatedSelectedMessage(_ messageId: MessageId) -> ChatPresentationInterfaceState {
        var selectedIds = Set<MessageId>()
        if let selectionState = self.selectionState {
            selectedIds.formUnion(selectionState.selectedIds)
        }
        if selectedIds.count < 100 {
            selectedIds.insert(messageId)
        } else {
            NSSound.beep()
        }
        
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState?.withUpdatedSelectedIds(selectedIds), sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedSelectedMessages(_ ids:Set<MessageId>) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState?.withUpdatedSelectedIds(ids), sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withToggledSelectedMessage(_ messageId: MessageId) -> ChatPresentationInterfaceState {
        var selectedIds = Set<MessageId>()
        if let selectionState = self.selectionState {
            selectedIds.formUnion(selectionState.selectedIds)
        }
        let isSelected: Bool = selectedIds.contains(messageId)
        if isSelected {
            let _ = selectedIds.remove(messageId)
        } else {
            if selectedIds.count < 100 {
                selectedIds.insert(messageId)
            } else {
                NSSound.beep()
            }
        }
        
        var selectionState: ChatInterfaceSelectionState = self.selectionState?.withUpdatedSelectedIds(selectedIds) ?? ChatInterfaceSelectionState(selectedIds: selectedIds, lastSelectedId: nil)
        
        if let event = NSApp.currentEvent {
            if !event.modifierFlags.contains(.shift) {
                if !isSelected {
                    selectionState = selectionState.withUpdatedLastSelected(messageId)
                } else {
                    var foundBestOption: Bool = false
                    for id in selectedIds {
                        if id > messageId {
                            selectionState = selectionState.withUpdatedLastSelected(id)
                            foundBestOption = true
                            break
                        }
                    }
                    if !foundBestOption {
                        selectionState = selectionState.withUpdatedLastSelected(messageId)
                    }
                }
            }
        }
        
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withRemovedSelectedMessage(_ messageId: MessageId) -> ChatPresentationInterfaceState {
        var selectedIds = Set<MessageId>()
        if let selectionState = self.selectionState {
            selectedIds.formUnion(selectionState.selectedIds)
        }
        let _ = selectedIds.remove(messageId)
        
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState?.withUpdatedSelectedIds(selectedIds), sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }

    
    public func withoutSelectionState() -> ChatPresentationInterfaceState {
         return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: nil, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withSelectionState() -> ChatPresentationInterfaceState {
         return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: ChatInterfaceSelectionState(selectedIds: [], lastSelectedId: nil), sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }

    public func withoutInitialAction() -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: nil, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedIsEmojiSection(_ isEmojiSection:Bool) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction:initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedBasicActions(_ canInvokeBasicActions:(delete: Bool, forward: Bool)) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }

    
    public func withUpdatedIsNotAccessible(_ isNotAccessible:Bool) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: self.limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedLimitConfiguration(_ limitConfiguration:LimitsConfiguration) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedDiscussionGroupId(_ discussionGroupId: CachedChannelData.LinkedDiscussionPeerId) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    public func updateSlowMode(_ f: (SlowMode?)->SlowMode?) -> ChatPresentationInterfaceState {
        
        let updated = f(self.slowMode)
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: self.discussionGroupId, slowMode: updated, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    public func withUpdatedHasScheduled(_ hasScheduled: Bool) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    public func withUpdatedHidePinnedMessage(_ hidePinnedMessage: Bool) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedCanPinMessage(_ canPinMessage: Bool) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedTempPinnedMaxId(_ tempPinnedMaxId: MessageId?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func updatedGroupCall(_ f: (ChatActiveGroupCallInfo?)->ChatActiveGroupCallInfo?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: f(self.groupCall), messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }

    public func withUpdatedMessageSecretTimeout(_ messageSecretTimeout: CachedPeerAutoremoveTimeout?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }

    public func withUpdatedRepotMode(_ reportMode: ReportReasonValue?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedInviteRequestsPending(_ inviteRequestsPending: Int32?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    public func withUpdatedInviteRequestsPendingPeers(_ inviteRequestsPendingPeers: [PeerInvitationImportersState.Importer]?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedCurrentSendAsPeerId(_ currentSendAsPeerId: PeerId?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }

    public func withUpdatedSendAsPeers(_ sendAsPeers: [SendAsPeer]?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedAllowedReactions(_ reactions: PeerAllowedReactions?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: reactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }


    public func updateBotMenu(_ f:(BotMenu?)->BotMenu?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: f(self.botMenu), inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }

    public func withUpdatedAttachItems(_ attachItems: [AttachMenuBot]) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedCachedData(_ cachedData: CachedPeerData?) -> ChatPresentationInterfaceState {
        
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedThreadInfo(_ threadInfo: MessageHistoryThreadData?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }

    
    public func withUpdatedTranslateState(_ translateState: TranslateState?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }

    public func withUpdatedPresence(_ presence: TelegramUserPresence?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    public func withUpdatedSavedMessageTags(_ savedMessageTags: SavedMessageTagsValue?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedAccountPeer(_ accountPeer: Peer?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    public func withUpdatedDisplaySavedChatsAsTopics(_ displaySavedChatsAsTopics: Bool) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedShortcuts(_ shortcuts: ShortcutMessageList?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    public func withUpdatedConnectedBot(_ connectedBot: ChatBotManagerData?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedContentSettings(_ contentSettings: ContentSettings?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedPlayedMessageEffects(_ playedMessageEffects: [MessageId]) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedAdMessage(_ adMessage: Message?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedAcknowledgedPaidMessage(_ acknowledgedPaidMessage: Bool) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedAlwaysPaidMessage(_ alwaysPaidMessage: Bool) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }

    public func withUpdatedStarsState(_ starsState: StarsContext.State?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedSendPaidMessageStars(_ sendPaidMessageStars: StarsAmount?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    
    public func withUpdatedFreezeAccount(_ freezeAccount: Int32) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedFreezeAccountAddressName(_ freezeAccountAppealAddressName: String?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
    public func withUpdatedMonoforumState(_ monoforumState: MonoforumUIState?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }

    public func withUpdatedMonoforumTopics(_ monoforumTopics: [MonoforumItem]) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }

    public func withUpdatedChatLocation(_ chatLocation: ChatLocation) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }

    
    public func withUpdatedRemovePaidMessageFeeData(_ removePaidMessageFeeData: RemovePaidMessageFeeData?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: removePaidMessageFeeData)
    }

    public func withToggledSidebarEnabled(_ enabled: Bool?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: enabled, sidebarShown: self.sidebarShown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }

    public func withToggledSidebarShown(_ shown: Bool?) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(interfaceState: self.interfaceState, peer: self.peer, notificationSettings: self.notificationSettings, inputQueryResult: self.inputQueryResult, keyboardButtonsMessage:self.keyboardButtonsMessage, initialAction: self.initialAction, historyCount: self.historyCount, searchMode: self.searchMode, recordingState: self.recordingState, isBlocked: self.isBlocked, peerStatus: self.peerStatus, pinnedMessageId: self.pinnedMessageId, urlPreview: self.urlPreview, selectionState: self.selectionState, sidebarEnabled: self.sidebarEnabled, sidebarShown: shown, layout: self.layout, canAddContact: self.canAddContact, isEmojiSection: self.isEmojiSection, chatLocation: self.chatLocation, chatMode: self.chatMode, canInvokeBasicActions: self.canInvokeBasicActions, isNotAccessible: self.isNotAccessible, restrictionInfo: self.restrictionInfo, mainPeer: self.mainPeer, limitConfiguration: limitConfiguration, discussionGroupId: discussionGroupId, slowMode: self.slowMode, hasScheduled: self.hasScheduled, failedMessageIds: self.failedMessageIds, hidePinnedMessage: self.hidePinnedMessage, canPinMessage: self.canPinMessage, tempPinnedMaxId: self.tempPinnedMaxId, groupCall: self.groupCall, messageSecretTimeout: self.messageSecretTimeout, reportMode: self.reportMode, botMenu: self.botMenu, inviteRequestsPending: self.inviteRequestsPending, inviteRequestsPendingPeers: self.inviteRequestsPendingPeers, currentSendAsPeerId: self.currentSendAsPeerId, sendAsPeers: self.sendAsPeers, allowedReactions: self.allowedReactions, attachItems: self.attachItems, cachedData: self.cachedData, threadInfo: self.threadInfo, translateState: self.translateState, presence: self.presence, savedMessageTags: self.savedMessageTags, accountPeer: self.accountPeer, displaySavedChatsAsTopics: self.displaySavedChatsAsTopics, shortcuts: self.shortcuts, connectedBot: self.connectedBot, contentSettings: self.contentSettings, playedMessageEffects: self.playedMessageEffects, adMessage: self.adMessage, acknowledgedPaidMessage: self.acknowledgedPaidMessage, alwaysPaidMessage: self.alwaysPaidMessage, starsState: self.starsState, sendPaidMessageStars: self._sendPaidMessageStars, freezeAccount: self.freezeAccount, freezeAccountAppealAddressName: self.freezeAccountAppealAddressName, monoforumState: self.monoforumState, monoforumTopics: self.monoforumTopics, removePaidMessageFeeData: self.removePaidMessageFeeData)
    }
    
}
