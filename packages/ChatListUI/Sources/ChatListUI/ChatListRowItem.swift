import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import DateUtils
import SwiftSignalKit
import InAppSettings
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import LocalAnimations
import MessageUtils
import MessageTextUtils
import TelegramMediaUtils
import InputDataUI
import AlertsUI
import AvatarUI
import PremiumStatusUI
import CommunityUI
import WebAppUI
import ChatUI
import ChatHistoryModel
import ChatModeTypes
import InlineStickerLayer


public class ChatListTags {
    
    public struct Extender {
        public var tag: ChatListTag
        public var index: Int
    }
    public var tags: [ChatListTag]
    public var extender: Extender?
    
    public var effective: [ChatListTag] {
        if let extender {
            return tags.prefix(upTo: extender.index) + [extender.tag]
        } else {
            return tags
        }
    }
    
    public init(tags: [ChatListTag], extender: Extender? = nil) {
        self.tags = tags
        self.extender = extender
    }
}

public struct ChatListTag {
    public let text: TextViewLayout
    public let selected: TextViewLayout
    public let color: NSColor
    public let selectedColor: NSColor
    
    public var size: NSSize {
        return NSMakeSize(text.layoutSize.width + 4, text.layoutSize.height + 4)
    }
}

public enum ChatListPinnedType {
    case some
    case last
    case none
    case ad(EngineChatList.AdditionalItem)
}


public final class SelectChatListItemPresentation : Equatable {
    public let selected:Set<ChatLocation>
    public static func ==(lhs:SelectChatListItemPresentation, rhs:SelectChatListItemPresentation) -> Bool {
        return lhs.selected == rhs.selected
    }
    
    public init(_ selected:Set<ChatLocation> = Set()) {
        self.selected = selected
    }
    
    public func deselect(chatLocation:ChatLocation) -> SelectChatListItemPresentation {
        var chatLocations:Set<ChatLocation> = Set<ChatLocation>()
        chatLocations.formUnion(selected)
        let _ = chatLocations.remove(chatLocation)
        return SelectChatListItemPresentation(chatLocations)
    }
    
    public func withToggledSelected(_ chatLocation: ChatLocation) -> SelectChatListItemPresentation {
        var chatLocations:Set<ChatLocation> = Set<ChatLocation>()
        chatLocations.formUnion(selected)
        if chatLocations.contains(chatLocation) {
            let _ = chatLocations.remove(chatLocation)
        } else {
            chatLocations.insert(chatLocation)
        }
        return SelectChatListItemPresentation(chatLocations)
    }
    
}

public enum ChatListRowState : Equatable {
    case plain
    case deletable(onRemove:(ChatLocation)->Void, deletable:Bool)
    
    public static func ==(lhs: ChatListRowState, rhs: ChatListRowState) -> Bool {
        switch lhs {
        case .plain:
            if case .plain = rhs {
                return true
            } else {
                return false
            }
        case .deletable(_, let deletable):
            if case .deletable(_, deletable) = rhs {
                return true
            } else {
                return false
            }
        }
    }
}


func chatListHasUnreadIncomingGramTransfer(_ messages: [Message], readState: EnginePeerReadCounters?, accountPeerId: PeerId) -> Bool {
    return messages.last.map { message in
        guard let readState, readState.count > 0, !readState.isIncomingMessageIndexRead(MessageIndex(message)) else {
            return false
        }
        return message.effectivelyIncoming(accountPeerId) && message.media.contains(where: { media in
            if let media = media as? TelegramMediaAction, case .gramTransfer = media.action {
                return true
            }
            return false
        })
    } ?? false
}

func chatListGramBadgeHidesUnreadCounter(hasGramBadge: Bool, unreadCount: Int32?) -> Bool {
    return hasGramBadge && unreadCount == 1
}

public class ChatListRowItem: TableRowItem {
    static let playsVideoAvatars = false
    

    public struct Badge {
        public let dynamicValue: DynamicCounterTextView.Value
        public let backgroundColor: NSColor
        public let size: NSSize
        public init(dynamicValue: DynamicCounterTextView.Value, backgroundColor: NSColor, size: NSSize) {
            self.dynamicValue = dynamicValue
            self.backgroundColor = backgroundColor
            var mapped = NSMakeSize(max(CGFloat(dynamicValue.values.count) * 10 - 10 + 7, size.width + 8), size.height + 7)
            mapped = NSMakeSize(max(mapped.height,mapped.width), mapped.height)
            self.size = mapped
        }
    }
        
    private var messages:[Message]
    public var message: Message? {
        return messages.first(where: { !$0.text.isEmpty }) ?? messages.first
    }
    
    public let context: any AccountContextProtocol
    public let peer:Peer?
    public let renderedPeer:EngineRenderedPeer?
    public var communityHidden: Bool = false
    public var disableCommunityDropdown: Bool = false
    /// When set (by the community chat list), the row's context menu is replaced
    /// with a "Remove from Community" action instead of the standard chat-list menu.
    public var communityRemoveAction: (() -> Void)? = nil
    public let groupId: EngineChatList.Group
    public let forumTopicData: EngineChatList.ForumTopicData?
    public let forumTopicItems:[EngineChatList.ForumTopicData]
    public var hasForumIcon: Bool {
        if chatNameLayout != nil, forumTopicNameLayout != nil {
            if forumTopicData != nil {
                return true
            } else if let peer = peer, TelegramUtilsHooks.shared.peerIsForum(peer), titleMode == .forumInfo, case .topic = mode {
                return true
            } else if let peer = peer, peer.isCommunity {
                return true
            }
        }
        return false
    }
    
    public var isPaidSubscriptionChannel: Bool {
        return (peer as? TelegramChannel)?.subscriptionUntilDate != nil
    }
    
    public let chatListIndex:ChatListIndex?
    public var peerId:PeerId? {
        switch mode {
        case .savedMessages:
            return context.peerId
        default:
            return renderedPeer?.peerId
        }
    }
    
    public let photo: AvatarNodeState
    
    public var isGroup: Bool {
        return groupId != .root
    }
    
    
    public override var stableId: AnyHashable {
        switch _stableId {
        case let .chatId(id, peerId, _):
            return UIChatListEntryId.chatId(id, peerId, -1)
        default:
            return _stableId
        }
    }
    
    private var _stableId: UIChatListEntryId
    public var entryId: UIChatListEntryId {
        return _stableId
    }
    
    public var isForum: Bool {
        if let peer = peer, TelegramUtilsHooks.shared.peerIsForum(peer) && !peer.displayForumAsTabs(splitState: context.layout) {
            return true
        }
        return false
    }
    public var isTopic: Bool {
        switch self.mode {
        case .topic:
            return true
        case .chat, .savedMessages:
            return false
        }
    }
    
    public var chatLocation: ChatLocation? {
        if let index = chatListIndex {
            return ChatLocation.peer(index.messageIndex.id.peerId)
        }
        return nil
    }

    public let mentionsCount: Int32?
    public let reactionsCount: Int32?
    public let pollVotesCount: Int32?
    public let hasGramBadge: Bool

    public var showsMentionSlot: Bool {
        return mentionsCount != nil || hasGramBadge
    }

    private var displayLayout:TextViewLayout?
    private var displaySelectedLayout:TextViewLayout?
    private var displaySelectedUsesMayItemsFalse: Bool = false
    
    private var dateLayout:TextViewLayout?
    private var dateSelectedLayout:TextViewLayout?


    private var messageLayout:TextViewLayout?
    private var messageSelectedLayout:TextViewLayout?
    private var messageSelectedMaxLines: Int32 = 2
    private var messageSelectedCutout: TextViewCutout? = nil
    
    public private(set) var topicsLayout: ChatListTopicNameAndTextLayout?
    
    private var chatNameLayout:TextViewLayout?
    private var chatNameSelectedLayout:TextViewLayout?

    private var forumTopicNameLayout:TextViewLayout?
    private var forumTopicNameSelectedLayout:TextViewLayout?
    private var displaySelectedPendingWidth: CGFloat?
    private var chatNameSelectedPendingWidth: CGFloat?
    private var forumTopicNameSelectedPendingWidth: CGFloat?
    private var messageSelectedPendingWidth: CGFloat?

            
    public private(set) var peerNotificationSettings:PeerNotificationSettings?
    public private(set) var readState:EnginePeerReadCounters?
    
    
    
    private var badgeNode:BadgeNode? = nil
    private var badgeSelectedNode:BadgeNode? = nil
    private var badgeText: String?
    
    private var shortBadgeNode:BadgeNode? = nil
    private var shortBadgeSelectedNode:BadgeNode? = nil


    private let _animateArchive:Atomic<Bool> = Atomic(value: false)
    
    public var animateArchive:Bool {
        return _animateArchive.swap(false)
    }
    
    public let filter: ChatListFilter
    public let splitState: SplitViewState
    
    public var isCollapsed: Bool {
        if let hideStatus = hideStatus {
            switch hideStatus {
            case .collapsed:
                return context.layout != .minimisize
            default:
                return false
            }
        }
        return false
    }
    
    
    public var canDeleteTopic: Bool {
        if isTopic, let peer = peer as? TelegramChannel, peer.isAdmin {
            if peer.hasPermission(.manageTopics) {
                return true
            }
        }
        return false
    }
    
    public var hasRevealState: Bool {
        return canArchive || (groupId != .root && !isCollapsed)
    }
    
    public var canArchive: Bool {
        if groupId != .root {
            return false
        }
        if mode.savedMessages {
            return false
        }
        if context.peerId == peerId {
            return false
        }
        if case .ad = pinnedType {
            return false
        }
        if self.peer?.id == servicePeerId {
            return false
        }
        if self.peer?.id == verifyCodePeerId {
            return false
        }
        return true
    }
    
    public let associatedGroupId: EngineChatList.Group
    
    public let isMuted:Bool
    
    public var hasUnread: Bool {
        return ctxBadgeNode != nil
    }
    
    public let isVerified: Bool
    public let isPremium: Bool
    public let isScam: Bool
    public let isFake: Bool

    
    public private(set) var photos: [TelegramPeerPhoto] = []
    private let peerPhotosDisposable = MetaDisposable()

    
    public var isOutMessage:Bool {
        if let message = message {
            return !message.flags.contains(.Incoming) && message.id.peerId != context.peerId
        }
        return false
    }
    public var isRead:Bool {
        switch mode {
        case let .topic(_, data):
            if let message = message {
                if data.maxOutgoingReadId >= message.id.id {
                    return true
                }
            }
        default:
            if let peer = peer as? TelegramUser {
                if let _ = peer.botInfo {
                    return !peer.flags.contains(.isSupport)
                }
                if peer.id == context.peerId {
                    return true
                }
            }
            if let peer = peer as? TelegramChannel {
                if case .broadcast = peer.info {
                    return true
                }
            }
            if isForum, let message = message {
                for topic in forumTopicItems.prefix(1) {
                    if topic.maxOutgoingReadMessageId <= message.id {
                        return true
                    }
                }
                
            }
            if let readState = readState {
                if let message = message {
                    return readState.isOutgoingMessageIndexRead(MessageIndex(message))
                }
            }
        }
        
        
        return false
    }
    
    
    public var isUnreadMarked: Bool {
        if let readState = readState {
            return readState.markedUnread
        }
        return false
    }
    
    public var isSecret:Bool {
        if let renderedPeer = renderedPeer {
            return renderedPeer.peers[renderedPeer.peerId]?._asPeer() is TelegramSecretChat
        } else {
            return false
        }
    }
    
    public var isSending:Bool {
        if let message = message {
            return message.flags.contains(.Unsent)
        }
        return false
    }
    
    public var isFailed: Bool {
        return self.hasFailed
    }
    
    public var isSavedMessage: Bool {
        return peer?.id == context.peerId
    }
    public var isAnonynousSavedMessage: Bool {
        return peer?.id.isAnonymousSavedMessages == true
    }
    public var isRepliesChat: Bool {
        return peer?.id == repliesPeerId
    }
    
    public override var identifier: String {
        if hideStatus == .collapsed {
            return super.identifier + "collapsed"
        } else if hideStatus == .normal {
            return super.identifier + "normal"
        }
        return super.identifier
    }
    
    public let hasDraft:Bool
    public let hideContent: Bool
    private let hasFailed: Bool
    public let pinnedType:ChatListPinnedType
    public let activities: [PeerListState.InputActivities.Activity]
    
    public var toolTip: String? {
        return messageLayout?.attributedString.string
    }
    
    public private(set) var isOnline: Bool?
    
    public private(set) var hasActiveGroupCall: Bool = false
    
    private var presenceManager:PeerPresenceStatusManager?
    private var relativeDateTimer: RelativeDateUpdateTimer?

    public let hideStatus: ItemHideStatus?
    
    private var groupItems:[EngineChatList.GroupItem.Item] = []
    
    private var textLeftCutout: CGFloat = 0.0
    public let contentImageSize = CGSize(width: 16, height: 16)
    public let contentImageSpacing: CGFloat = 2.0
    public let contentImageTrailingSpace: CGFloat = 5.0
    public private(set) var contentImageSpecs: [(message: Message, media: Media, size: CGSize)] = []


    public let isArchiveItem: Bool
    
    public init(_ initialSize:NSSize, context: any AccountContextProtocol, stableId: UIChatListEntryId, pinnedType: ChatListPinnedType, groupId: EngineChatList.Group, groupItems: [EngineChatList.GroupItem.Item], messages: [Message], unreadCount: Int, activities: [PeerListState.InputActivities.Activity] = [], animateGroup: Bool = false, hideStatus: ItemHideStatus = .normal, hasFailed: Bool = false, filter: ChatListFilter = .allChats, appearMode: PeerListState.AppearMode = .normal, hideContent: Bool = false, getHideProgress:(()->CGFloat?)? = nil, openStory: @escaping(StoryInitialIndex?, Bool, Bool)->Void = { _, _, _ in }, storyState: EngineStorySubscriptions? = nil, isContact: Bool = false) {
        let relativeDateReferenceTimestamp = Date().timeIntervalSince1970
        self.groupId = groupId
        self.peer = nil
        self.mode = .chat
        self.messages = messages
        self.chatListIndex = nil
        self.activities = activities
        self.context = context
        self.mentionsCount = nil
        self.reactionsCount = nil
        self.pollVotesCount = nil
        self.hasGramBadge = false
        self.selectedForum = nil
        self.story = nil
        self.displayAsTopics = false
        self.openStory = openStory
        self.storyState = storyState
        self._stableId = stableId
        self.pinnedType = pinnedType
        self.splitState = context.layout
        self.renderedPeer = nil
        self.forumTopicData = nil
        self.forumTopicItems = []
        self.associatedGroupId = .root
        self.appearMode = appearMode
        self.isMuted = false
        self.isContact = false
        self.isOnline = nil
        self.getHideProgress = getHideProgress
        self.hideStatus = hideStatus
        self.autoremoveTimeout = nil
        self.groupItems = groupItems
        self.isVerified = false
        self.isPremium = false
        self.isScam = false
        self.hideContent = hideContent
        self.isFake = false
        self.openMiniApp = nil
        self.openMiniAppSelected = nil
        self.monoforumMessages = nil
        self.monoforumMessagesSelected = nil
        self.filter = filter
        self.hasFailed = hasFailed
        self.isArchiveItem = true
        self.folders = nil
        self.tags = nil
        self.canPreviewChat = false
        if let storyState = storyState, storyState.items.count > 0 {
            let unseenCount: Int = storyState.items.reduce(0, {
                $0 + ($1.unseenCount > 0 ? 1 : 0)
            })
            
            let hasLiveItems = storyState.items.contains(where: { $0.hasLiveItems })
            
            self.avatarStoryIndicator = .init(stats: .init(totalCount: storyState.items.count, unseenCount: unseenCount, hasUnseenCloseFriends: false, hasLiveItems: hasLiveItems), presentation: theme)
        } else {
            self.avatarStoryIndicator = nil
        }
                
        let titleText:NSMutableAttributedString = NSMutableAttributedString()
        let _ = titleText.append(string: strings().chatListArchivedChats, color: theme.chatList.textColor, font: .medium(.title))
        titleText.setSelected(color: theme.colors.underSelectedColor ,range: titleText.range)
        
        self.displayLayout = TextViewLayout(titleText, maximumNumberOfLines: 1)
        self.displaySelectedUsesMayItemsFalse = true
        
        hasDraft = false
        
    

        
        if let message = messages.first {
            let date:NSMutableAttributedString = NSMutableAttributedString()
            var time:TimeInterval = TimeInterval(message.timestamp)
            time -= context.timeDifference
            let range = date.append(string: DateUtils.string(forMessageListDate: Int32(time)), color: theme.colors.grayText, font: .normal(.short))
            date.setSelected(color: theme.colors.underSelectedColor,range: range)

            self.dateLayout = TextViewLayout(date, mayItems: false)
            self.dateLayout?.measure(width: .greatestFiniteMagnitude)
            
        }
        
        
        let mutedCount = unreadCount
        
        self.highlightText = nil
        self.draft = nil
        
        photo = .ArchivedChats
        self.titleMode = .normal
        super.init(initialSize)

        setupRelativeDateTimer(relativeTo: relativeDateReferenceTimestamp)

        if case .hidden(true) = hideStatus {
            hideItem(animated: false, reload: false)
        }


        _ = _animateArchive.swap(animateGroup)
        
        if mutedCount > 0  {
            badgeText = "\(mutedCount)"
            badgeNode = BadgeNode(.initialize(string: "\(mutedCount)", color: theme.chatList.badgeTextColor, font: .medium(.small)), theme.chatList.badgeMutedBackgroundColor)

        }
        
        var messageText: NSAttributedString
        if groupItems.count == 1 {
            messageText = chatListText(account: context.account, for: message, messagesCount: 1, folder: true)
        } else {
            let textString = NSMutableAttributedString(string: "")
            var isFirst = true
            var wasRead: Bool = false
            for item in groupItems {
                if let chatMainPeer = item.peer.chatMainPeer?._asPeer() {
                    let peerTitle = chatMainPeer.compactDisplayTitle
                    if !peerTitle.isEmpty {
                        if isFirst {
                            isFirst = false
                        } else {
                            textString.append(.initialize(string: ", ", color: !wasRead ? theme.chatList.textColor : theme.chatList.grayTextColor, font: .normal(.text)))
                        }
                        textString.append(.initialize(string: peerTitle, color: item.isUnread ? theme.chatList.textColor : theme.chatList.grayTextColor, font: .normal(.text)))
                        wasRead = !item.isUnread
                    }
                }
            }
            messageText = textString
        }
        
        if messageText.string.isEmpty, let storyState = storyState, storyState.items.count > 0 {
            messageText = .initialize(string: strings().chatListArchiveStoryCountOther(storyState.items.count), color: theme.chatList.grayTextColor, font: .normal(.text))
        }
        
        if let messageText = messageText.trimmed.mutableCopy() as? NSMutableAttributedString, !messageText.string
            .isEmpty {
            self.messageLayout = .init(messageText, maximumNumberOfLines: 2)
            self.messageSelectedMaxLines = 2
            self.messageSelectedCutout = nil
        }

        _ = makeSize(initialSize.width, oldWidth: 0)
    }
    
    private let highlightText: String?
    
    private let draft:EngineChatList.Draft?
    
    public enum Mode {
        case chat
        case savedMessages(Int64)
        case topic(Int64, MessageHistoryThreadData)
        
        public var savedMessages: Bool {
            switch self {
            case .savedMessages:
                return true
            default:
                return false
            }
        }

        public var isForumLike: Bool {
            switch self {
            case .topic, .savedMessages:
                return true
            case .chat:
                return false
            }
        }
        
        public var threadId: Int64? {
            switch self {
            case let .topic(threadId, _):
                return threadId
            case let .savedMessages(threadId):
                return threadId
            default:
                return nil
            }
        }
        public var threadData: MessageHistoryThreadData? {
            switch self {
            case let .topic(_, data):
                return data
            default:
                return nil
            }
        }
        public var isGeneralTopic: Bool {
            return threadId == 1
        }
    }
    public enum TitleMode {
        case normal
        case forumInfo
    }
    
    public let mode: Mode
    public let titleMode: TitleMode
    public let appearMode: PeerListState.AppearMode
    public let getHideProgress:(()->CGFloat?)?
    public let selectedForum: PeerId?
    public let autoremoveTimeout: Int32?
    public let isContact: Bool
    
    
    public let story: EngineChatList.StoryStats?
    public let storyState: EngineStorySubscriptions?
    public let avatarStoryIndicator: AvatarStoryIndicatorComponent?
    
    public let openStory:(StoryInitialIndex?, Bool, Bool)->Void


    public var hasLiveItems: Bool {
        return story?.hasLiveItems == true && self.peer?.id != context.peerId
    }
    

    public var isSelectedForum: Bool {
        if let selectedForum = selectedForum, isForum {
            if selectedForum == peerId {
                return true
            }
        }
        return false
    }
    
    public let displayAsTopics: Bool
    public let folders: FilterData?
    
    
    public let tags: ChatListTags?
    
    public let canPreviewChat: Bool
    
    public let openMiniApp: TextViewLayout?
    public let openMiniAppSelected: TextViewLayout?
    
    public let monoforumMessages: TextViewLayout?
    public let monoforumMessagesSelected: TextViewLayout?


    public init(_ initialSize:NSSize, context: any AccountContextProtocol, stableId: UIChatListEntryId, mode: Mode, messages: [Message], index: ChatListIndex? = nil, readState:EnginePeerReadCounters? = nil, draft:EngineChatList.Draft? = nil, pinnedType:ChatListPinnedType = .none, renderedPeer:EngineRenderedPeer, peerPresence: EnginePeer.Presence? = nil, forumTopicData: EngineChatList.ForumTopicData? = nil, forumTopicItems:[EngineChatList.ForumTopicData] = [], activities: [PeerListState.InputActivities.Activity] = [], highlightText: String? = nil, associatedGroupId: EngineChatList.Group = .root, isMuted:Bool = false, hasFailed: Bool = false, hasUnreadMentions: Bool = false, hasUnreadReactions: Bool = false, hasUnreadVotes: Bool = false, showBadge: Bool = true, filter: ChatListFilter = .allChats, hideStatus: ItemHideStatus? = nil, titleMode: TitleMode = .normal, appearMode: PeerListState.AppearMode = .normal, hideContent: Bool = false, getHideProgress:(()->CGFloat?)? = nil, selectedForum: PeerId? = nil, autoremoveTimeout: Int32? = nil, story: EngineChatList.StoryStats? = nil, openStory: @escaping(StoryInitialIndex?, Bool, Bool)->Void = { _, _, _ in }, storyState: EngineStorySubscriptions? = nil, isContact: Bool = false, displayAsTopics: Bool = false, folders: FilterData? = nil, communityCategories: [PeerId: ChatListFilterPeerCategories] = [:], canPreviewChat: Bool = false) {
        let relativeDateReferenceTimestamp = Date().timeIntervalSince1970
        
        
        if !forumTopicItems.isEmpty {
            var bp = 0
            bp += 1
        }
        
        var draft = draft
        
        if let peer = renderedPeer.chatMainPeer?._asPeer() as? TelegramChannel {
            if !peer.hasPermission(.sendSomething) {
                draft = nil
            }
        }
        
        if let value = draft {
            if value.text.isEmpty {
                draft = nil
            }
        }
        
        if let peerPresence = peerPresence?._asPresence(), context.peerId != renderedPeer.peerId, renderedPeer.peerId != servicePeerId {
            let timestamp = CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970
            let relative = relativeUserPresenceStatus(peerPresence, timeDifference: context.timeDifference, relativeTo: Int32(timestamp))
            switch relative {
            case .online:
                self.isOnline = true
            default:
                self.isOnline = false
            }
        } else {
            self.isOnline = nil
        }
        
        if let peer = renderedPeer.chatMainPeer?._asPeer() as? TelegramChannel, peer.flags.contains(.hasActiveVoiceChat) {
            self.hasActiveGroupCall = mode.threadId == nil
        }
        
        self.mode = mode
        self.titleMode = titleMode
        self.chatListIndex = index
        self.renderedPeer = renderedPeer
        self.context = context
        self.story = story
        self.openStory = openStory
        self.messages = messages
        self.activities = activities
        self.pinnedType = pinnedType
        self.splitState = context.layout
        self.hideStatus = hideStatus
        self.autoremoveTimeout = autoremoveTimeout
        self.getHideProgress = getHideProgress
        self.forumTopicData = forumTopicData
        self.forumTopicItems = forumTopicItems
        self.selectedForum = selectedForum
        self.storyState = storyState
        self.hasDraft = draft != nil
        self.draft = draft
        self.peer = renderedPeer.chatMainPeer?._asPeer()
        self.groupId = .root
        self.hasFailed = hasFailed
        self.filter = filter
        self.isArchiveItem = false
        self.displayAsTopics = displayAsTopics
        self.hideContent = hideContent
        self.appearMode = appearMode
        self.associatedGroupId = associatedGroupId
        self.highlightText = highlightText
        self._stableId = stableId
        self.isContact = isContact
        self.folders = folders
        self.canPreviewChat = canPreviewChat
        
        
        self.hasGramBadge = chatListHasUnreadIncomingGramTransfer(messages, readState: readState, accountPeerId: context.peerId)

        if let peer, let botInfo = peer.botInfo, botInfo.flags.contains(.hasWebApp), readState == nil || readState?.count == 0, !hasGramBadge, splitState != .minimisize {
            self.openMiniApp = .init(.initialize(string: strings().chatListOpenMiniApp, color: theme.colors.underSelectedColor, font: .medium(.text)), alignment: .center)
            self.openMiniApp?.measure(width: .greatestFiniteMagnitude)
            
            self.openMiniAppSelected = .init(.initialize(string: strings().chatListOpenMiniApp, color: theme.colors.accentSelect, font: .medium(.text)), alignment: .center)
            self.openMiniAppSelected?.measure(width: .greatestFiniteMagnitude)
        } else {
            self.openMiniApp = nil
            self.openMiniAppSelected = nil
        }
        
        if let peer = peer, peer.isMonoForum {
            self.monoforumMessages = .init(.initialize(string: strings().chatListMonoforumHolder, color: theme.colors.grayText, font: .normal(.small)), alignment: .center)
            self.monoforumMessagesSelected = .init(.initialize(string: strings().chatListMonoforumHolder, color: theme.colors.accentSelect, font: .normal(.small)), alignment: .center)
            
            self.monoforumMessages?.measure(width: .greatestFiniteMagnitude)
            self.monoforumMessagesSelected?.measure(width: .greatestFiniteMagnitude)

        } else {
            self.monoforumMessages = nil
            self.monoforumMessagesSelected = nil
        }
        
        if let folders, folders.showTags, let peer, splitState != .minimisize, mode.threadData == nil {
            var tags: [ChatListTag] = []
            var filtered: [ChatListFilter] = []
            for tab in folders.tabs {
                if tab != filter {
                    if tab.contains(peer, groupId: groupId._asGroup(), isRemovedFromTotalUnreadCount: isMuted, isUnread: readState?.count != 0, isContact: isContact, communityCategories: communityCategories) {
                        filtered.append(tab)
                    }
                }
            }
            for tab in filtered {
                let color: NSColor?
                if let dataColor = tab.data?.color {
                    let index = Int(dataColor.rawValue)
                    color = theme.colors.peerColors(index % 7).bottom
                } else {
                    color = nil
                }
                if let color = color {
                    
                    let attr = NSMutableAttributedString()
                    attr.append(string: tab.title.uppercased(), color: color, font: .bold(10))
                    InlineStickerItem.apply(to: attr, associatedMedia: [:], entities: tab.entities, isPremium: context.isPremium, playPolicy: tab.enableAnimations ? nil : .framesCount(1))

                    
                    let attrSelected = NSMutableAttributedString()
                    attrSelected.append(string: tab.title.uppercased(), color: theme.colors.accentSelect, font: .bold(10))
                    InlineStickerItem.apply(to: attrSelected, associatedMedia: [:], entities: tab.entities, isPremium: context.isPremium)

                    
                    let text = TextViewLayout(attr)
                    text.measure(width: .greatestFiniteMagnitude)
                    
                    let textSelected = TextViewLayout(attrSelected)
                    textSelected.measure(width: .greatestFiniteMagnitude)

                    tags.append(.init(text: text, selected: textSelected, color: color.withAlphaComponent(0.1), selectedColor: theme.colors.underSelectedColor))
                }
            }
            if !tags.isEmpty {
                self.tags = .init(tags: tags, extender: nil)
            } else {
                self.tags = nil
            }
        } else {
            self.tags = nil
        }
        
        if let peer = peer {
            self.isVerified = peer.isVerified
            self.isPremium = peer.isPremium && peer.id != context.peerId
            self.isScam = peer.isScam
            self.isFake = peer.isFake
        } else {
            self.isVerified = false
            self.isScam = false
            self.isFake = false
            self.isPremium = false
        }
        
       
        self.isMuted = isMuted
        self.readState = readState
        
        if let story = story, peer?.id != context.peerId {
            self.avatarStoryIndicator = .init(stats: story, presentation: theme, isRoundedRect: peer.map { TelegramUtilsHooks.shared.peerIsForum($0) } == true)
        } else {
            self.avatarStoryIndicator = nil
        }
        
        
        let titleText:NSMutableAttributedString = NSMutableAttributedString()
        let isTopic: Bool
        switch mode {
        case .chat, .savedMessages:
            let text: String?
            if case .savedMessages = mode, peer?.id == context.peerId {
                text = strings().peerMyNotes
            } else if peer?.id == context.peerId {
                text = strings().peerSavedMessages
            } else {
                if let peer = peer, peer.isMonoForum {
                    text = renderedPeer.chatOrMonoforumMainPeer?._asPeer().displayTitle
                } else {
                    text = peer?.displayTitle
                }
            }
            let _ = titleText.append(string: text, color: renderedPeer.peers[renderedPeer.peerId]?._asPeer() is TelegramSecretChat ? theme.chatList.secretChatTextColor : theme.chatList.textColor, font: .medium(.title))
            isTopic = false
        case let .topic(_, data):
            let _ = titleText.append(string: data.info.title, color: theme.chatList.textColor, font: .medium(.title))
            isTopic = true
        }
        titleText.setSelected(color: theme.colors.underSelectedColor ,range: titleText.range)
        
        self.displayLayout = TextViewLayout(titleText, maximumNumberOfLines: 1)
        self.displaySelectedUsesMayItemsFalse = false
                
        if !forumTopicItems.isEmpty, let message = messages.first, tags == nil {
            self.topicsLayout = .init(context, message: message, items: forumTopicItems, draft: draft)
        }
    
        
        if case let .ad(item) = pinnedType {
            let sponsored:NSMutableAttributedString = NSMutableAttributedString()
            let range: NSRange
            switch item.promoInfo.content {
            case let .psa(type, _):
                range = sponsored.append(string: localizedPsa("psa.chatlist", type: type), color: theme.colors.grayText, font: .normal(.short))
            case .proxy:
                range = sponsored.append(string: strings().chatListSponsoredChannel, color: theme.colors.grayText, font: .normal(.short))
            }
            sponsored.setSelected(color: theme.colors.underSelectedColor, range: range)

            self.dateLayout = TextViewLayout(sponsored, mayItems: false)
            self.dateLayout?.measure(width: .greatestFiniteMagnitude)
            
        } else if let message = messages.first {
            let date:NSMutableAttributedString = NSMutableAttributedString()
            var time:TimeInterval = TimeInterval(message.timestamp)
            time -= context.timeDifference
            let range = date.append(string: DateUtils.string(forMessageListDate: Int32(time)), color: theme.colors.grayText, font: .normal(.short))
            date.setSelected(color: theme.colors.underSelectedColor, range: range)

            self.dateLayout = TextViewLayout(date, mayItems: false)
            self.dateLayout?.measure(width: .greatestFiniteMagnitude)
                      
            if forumTopicItems.isEmpty || tags != nil {
                var author: Peer?
                if message.isImported, let info = message.forwardInfo {
                    if let peer = info.author {
                        author = peer
                    } else if let signature = info.authorSignature {
                        author = TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(0)), accessHash: nil, firstName: signature, lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
                    }
                } else {
                    author = message.author
                }
                if let author = author, let peer = peer, peer as? TelegramUser == nil, !peer.isChannel, draft == nil {
                    if !(message.extendedMedia is TelegramMediaAction) {
                        var peerText: String = (author.id == context.account.peerId ? "\(strings().chatListYou)" : author.displayTitle)
                        
                        let topicNameAttributed = NSMutableAttributedString()

                        if let forumTopicData = forumTopicData, TelegramUtilsHooks.shared.peerIsForum(peer) {
                            _ = topicNameAttributed.append(string: forumTopicData.title, color: theme.chatList.peerTextColor, font: .normal(.text))
                        } else if TelegramUtilsHooks.shared.peerIsForum(peer), titleMode == .forumInfo, case let .topic(_, data) = mode {
                            peerText = author.compactDisplayTitle
                            _ = topicNameAttributed.append(string: data.info.title, color: theme.chatList.peerTextColor, font: .normal(.text))
                        } else if peer.isCommunity, let childPeer = message.peers[message.id.peerId], childPeer.id != peer.id {
                            peerText = author.compactDisplayTitle
                            _ = topicNameAttributed.append(string: childPeer.displayTitle, color: theme.chatList.peerTextColor, font: .normal(.text))
                        }

                        if !topicNameAttributed.string.isEmpty {
                            self.forumTopicNameLayout = .init(topicNameAttributed, maximumNumberOfLines: 1)
                        }
                        
                        let attr = NSMutableAttributedString()
                        _ = attr.append(string: peerText, color: theme.chatList.peerTextColor, font: .normal(.text))
                        
                        if author.id != context.account.peerId, !isTopic {
                            attr.insert(.embeddedAvatar(.init(author)), at: 0)
                        }
                        attr.setSelected(color: theme.colors.underSelectedColor, range: attr.range)

                        if !attr.string.isEmpty {
                            self.chatNameLayout = .init(attr, maximumNumberOfLines: 1)
                        }
                    }
                }
                
                let isSecret: Bool
                isSecret = renderedPeer.peers[renderedPeer.peerId]?._asPeer() is TelegramSecretChat
                
                var contentImageSpecs = self.contentImageSpecs
                let contentImageSize = self.contentImageSize
                
                if draft == nil, !isSecret, forumTopicItems.isEmpty {
                    var index: Int32 = 0
                    let insert:(Message, Media, Bool)->Void = { message, media, increment in
                        var message = message
                        if increment {
                            message = message.withUpdatedId(.init(peerId: message.id.peerId, namespace: message.id.namespace, id: message.id.id + index))
                        }
                        if let image = media as? TelegramMediaImage {
                            if let _ = largestImageRepresentation(image.representations) {
                                let fitSize = contentImageSize
                                contentImageSpecs.append((message, image, fitSize))
                            }
                        } else if let file = media as? TelegramMediaFile {
                            if file.isVideo, !file.isInstantVideo, let _ = file.dimensions, !file.probablySticker {
                                let fitSize = contentImageSize
                                contentImageSpecs.append((message, file, fitSize))
                            }
                        }
                        index += 1
                    }
                    
                    for message in messages {
                        inner: for media in message.media {
                            if let media = media as? TelegramMediaPaidContent {
                                for extended in media.extendedMedia {
                                    switch extended {
                                    case let .preview(dimensions, immediateThumbnailData, _):
                                        if let immediateThumbnailData, let dimensions {
                                            insert(message, TelegramMediaImage(dimension: dimensions, immediateThumbnailData: immediateThumbnailData), true)
                                        }
                                    case let .full(media):
                                        insert(message, media, true)
                                    }
                                }
                            } else if !message.containsSecretMedia && !message.isMediaSpoilered {
                                insert(message, media, false)
                            }
                        }
                    }
                    self.contentImageSpecs = contentImageSpecs
                }
            }
        }
        
        contentImageSpecs = Array(contentImageSpecs.prefix(3))
        
        for i in 0 ..< contentImageSpecs.count {
            if i != 0 {
                textLeftCutout += contentImageSpacing
            }
            textLeftCutout += contentImageSpecs[i].size.width
            if i == contentImageSpecs.count - 1 {
                textLeftCutout += contentImageTrailingSpace
            }
        }
        if let _ = messages.first(where: { $0.storyAttribute != nil }) {
            textLeftCutout += 20
        }

        if hasUnreadMentions && !hasGramBadge {
            self.mentionsCount = 1
        } else {
            self.mentionsCount = nil
        }
       
        if hasUnreadReactions && !hasGramBadge {
            self.reactionsCount = 1
        } else {
            self.reactionsCount = nil
        }
        if hasUnreadVotes && !hasGramBadge {
            self.pollVotesCount = 1
        } else {
            self.pollVotesCount = nil
        }
        
        let isEmpty: Bool
        
        switch mode {
        case .topic:
            isEmpty = titleMode == .normal
        case .chat, .savedMessages:
            isEmpty = false
        }
        
        if let peer = peer, peer.id != context.peerId && peer.id != repliesPeerId, !peer.id.isAnonymousSavedMessages, !isEmpty {
            if peer.isMonoForum, let photoPeer = renderedPeer.chatOrMonoforumMainPeer?._asPeer() {
                self.photo = .PeerAvatar(peer, TelegramUtilsHooks.shared.peerLetters(peer), photoPeer.smallProfileImage, photoPeer.namePeerColor, nil, nil, peer.groupAccess.canManageDirect, nil)
            } else {
                self.photo = .PeerAvatar(peer, TelegramUtilsHooks.shared.peerLetters(peer), peer.smallProfileImage, peer.namePeerColor, nil, nil, peer.isForumOrMonoForum || peer.isCommunity, nil)
            }
        } else {
            self.photo = .Empty
        }
        
        super.init(initialSize)

        setupRelativeDateTimer(relativeTo: relativeDateReferenceTimestamp)

        if case .hidden(true) = hideStatus {
            hideItem(animated: false, reload: false)
        }

        if showBadge, !chatListGramBadgeHidesUnreadCounter(hasGramBadge: hasGramBadge, unreadCount: readState?.count) {
            
            let isMuted = isMuted || (readState?.isMuted ?? false)
            
            if let unreadCount = readState?.count, unreadCount > 0, mentionsCount == nil || (unreadCount > 1 || mentionsCount! != unreadCount)  {

                badgeText = "\(unreadCount)"
                badgeNode = BadgeNode(.initialize(string: "\(unreadCount)", color: theme.chatList.badgeTextColor, font: .medium(.small)), isMuted ? theme.chatList.badgeMutedBackgroundColor : theme.chatList.badgeBackgroundColor)

            } else if isUnreadMarked && mentionsCount == nil {
                badgeText = " "
                badgeNode = BadgeNode(.initialize(string: " ", color: theme.chatList.badgeTextColor, font: .medium(.small)), isMuted ? theme.chatList.badgeMutedBackgroundColor : theme.chatList.badgeBackgroundColor)

            }
        }
       
        
      
        if self.isOnline == true, let presence = peerPresence?._asPresence() {
            presenceManager = PeerPresenceStatusManager(update: { [weak self] in
                self?.isOnline = false
                self?.redraw(animated: true)
            })
            presenceManager?.reset(presence: presence, timeDifference: Int32(context.timeDifference))
        }
        
        if forumTopicItems.isEmpty || tags != nil {
            var messageText: NSAttributedString?
            var textCutout: TextViewCutout?
            if case let .ad(promo) = pinnedType, message == nil {
                switch promo.promoInfo.content {
                case let .psa(_, message):
                    if let message = message {
                        let attr = NSMutableAttributedString()
                        _ = attr.append(string: message, color: theme.colors.grayText, font: .normal(.text))
                        attr.setSelected(color: theme.colors.underSelectedColor, range: attr.range)
                        messageText = attr
                    }
                default:
                    break
                }
            } else {
                messageText = chatListText(account: context.account, for: message, messagesCount: messages.count, renderedPeer: renderedPeer, draft: draft, folder: false, applyUserName: false, isPremium: context.isPremium)
                if !textLeftCutout.isZero {
                    textCutout = TextViewCutout(topLeft: CGSize(width: textLeftCutout, height: 14))
                }
            }
            if let messageText = messageText?.trimmed, !messageText.string.isEmpty {
                self.messageLayout = .init(messageText, maximumNumberOfLines: chatNameLayout != nil || tags != nil ? 1 : 2, cutout: textCutout)
                
                self.messageSelectedMaxLines = chatNameLayout != nil || tags != nil ? 1 : 2
                self.messageSelectedCutout = textCutout
            }
        }
        
        _ = makeSize(initialSize.width, oldWidth: 0)
        
        
        if ChatListRowItem.playsVideoAvatars, let peer = peer, peer.isPremium, peer.id != context.peerId, peer.hasVideo, !TelegramUtilsHooks.shared.isLite(.animations) {
            self.photos = syncPeerPhotos(peerId: peer.id).map { $0.value }
            let signal = peerPhotos(context: context, peerId: peer.id, force: false) |> deliverOnMainQueue
            peerPhotosDisposable.set(signal.start(next: { [weak self] photos in
                let photos = photos.map { $0.value }
                if self?.photos != photos {
                    self?.photos = photos
                    DispatchQueue.main.async {
                        self?.noteHeightOfRow(animated: true)
                    }
                }
            }))
        }
    }
    
    public let margin:CGFloat = 9
    
    
    public var isPinned: Bool {
        switch pinnedType {
        case .some:
            return true
        case .last:
            return true
        default:
            return false
        }
    }
    public var isClosedTopic: Bool {
        switch self.mode {
        case let .topic(_, threadData):
            return threadData.isClosed
        case .chat, .savedMessages:
            return false
        }
    }
    
    public var badgeMuted: Bool {
        let isMuted = isMuted || (readState?.isMuted ?? false)

        return isMuted
    }
    
    public var isLastPinned: Bool {
        switch pinnedType {
        case .last:
            return true
        default:
            return false
        }
    }
    
    
    public var isFixedItem: Bool {
        switch pinnedType {
        case .some, .ad, .last:
            return true
        default:
            return false
        }
    }

    public var canResortPinned: Bool {
        switch mode {
        case .topic:
            if let peer = self.peer as? TelegramChannel {
                return peer.hasPermission(.pinMessages)
            } else {
                return false
            }
        default:
            return true
        }
    }


    public var isAd: Bool {
        switch pinnedType {
        case .ad:
            return true
        default:
            return false
        }
    }
    
    public var titleWidth:CGFloat {
        var dateSize:CGFloat = 0
        if let dateLayout = dateLayout {
            dateSize = dateLayout.layoutSize.width
        }
        
        let peer = self.renderedPeer?.chatOrMonoforumMainPeer?._asPeer() ?? self.peer
        
        var offset: CGFloat = 0
        if let peer = peer, peer.id != context.peerId, let controlSize = PremiumStatusControl.controlSize(peer, false, left: false) {
            offset += controlSize.width + 4
        }
        if let peer = peer, peer.id != context.peerId, let controlSize = PremiumStatusControl.controlSize(peer, false, left: true) {
            offset += controlSize.width + 4
        }
        if isMuted {
            offset += theme.icons.dialogMuteImage.backingSize.width + 4
        }
        if isSecret {
            offset += 10
        }
        
        if let ctxMonoforumMessages {
            offset += ctxMonoforumMessages.layoutSize.width + 10
        }
        
        offset += (leftInset - 20)
        
        if appearMode == .short {
            offset += 20
        }

        if isClosedTopic {
            offset += 10
        }
        offset += 5
        return max(200, size.width) - margin * 3 - dateSize - (isOutMessage ? isRead ? 20 : 12 : 0) - offset
    }
    
    public var chatNameWidth:CGFloat {
        var w:CGFloat = 0
        if let badgeNode = badgeNode {
            w += badgeNode.size.width + 5
        }
        if showsMentionSlot {
            w += 24
        }
        if let _ = reactionsCount {
            w += 24
        }
        if let _ = pollVotesCount {
            w += 24
        }
        w += (leftInset - 20)
        
        if let topicsLayout = forumTopicNameLayout, let _ = tags {
            w += topicsLayout.layoutSize.width + 5
            w += 40
        }
        if let _ = tags, !contentImageSpecs.isEmpty {
            w += CGFloat(contentImageSpecs.count) * 16
            w += 40
        }

        return max(200, size.width) - margin * 3 - w - (isOutMessage ? isRead ? 20 : 12 : 0)
    }
    
    public var messageWidth:CGFloat {
        var w: CGFloat = 0
        if let badgeNode = badgeNode {
            w += badgeNode.size.width + 5
        }
        if showsMentionSlot {
            w += 24
        }
        if let _ = reactionsCount {
            w += 24
        }
        if isPinned && badgeNode == nil {
            w += 20
        }
        
        if let openMiniApp {
            w += openMiniApp.layoutSize.width + 20
        }
        
        w += (leftInset - 20)
        
        if let chatNameLayout = chatNameLayout, let _ = tags {
            w += chatNameLayout.layoutSize.width + 5
        }
        if let topicsLayout = forumTopicNameLayout, let _ = tags {
            w += topicsLayout.layoutSize.width + 5
        }
        if let _ = tags, !contentImageSpecs.isEmpty {
            w += CGFloat(contentImageSpecs.count) * 16
        }
        
        return (max(200, size.width) - margin * 3) - w - (chatNameLayout != nil ? textLeftCutout : 0)
    }
    
    public var inputActivityWidth: CGFloat {
        var w: CGFloat = 0
        if let badgeNode = badgeNode {
            w += badgeNode.size.width + 5
        }
        if showsMentionSlot {
            w += 24
        }
        if let _ = reactionsCount {
            w += 24
        }
        if isPinned && badgeNode == nil {
            w += 20
        }
        w += (leftInset - 20)
        
        return (max(200, size.width) - margin * 3) - w - (chatNameLayout != nil ? textLeftCutout : 0)
    }
    
    public var leftInset:CGFloat {
        switch mode {
        case .chat, .savedMessages:
            return 50 + (10 * 2.0)
        case .topic:
            if titleMode == .forumInfo {
                return 50 + (10 * 2.0)
            } else {
                if appearMode == .short {
                    return 35
                } else {
                    return 30 + (10 * 2.0)
                }
            }
        }
    }
    
    public var shouldHideContent: Bool {
        return hideContent || context.layout == .minimisize
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        

        displayLayout?.measure(width: titleWidth)
        displaySelectedPendingWidth = titleWidth

        
        if let forumTopicNameLayout = forumTopicNameLayout, let chatNameLayout = self.chatNameLayout {
            var width = chatNameWidth / 2 - 20
            chatNameLayout.measure(width: width)
            chatNameSelectedPendingWidth = width
            
            width = chatNameWidth - chatNameLayout.layoutSize.width - 20
            forumTopicNameLayout.measure(width: width)
            forumTopicNameSelectedPendingWidth = width
        } else {
            chatNameLayout?.measure(width: chatNameWidth)
            chatNameSelectedPendingWidth = chatNameWidth
        }
        

        messageLayout?.measure(width: messageWidth)
        messageSelectedPendingWidth = messageWidth
        

        self.topicsLayout?.measure(messageWidth)
   
        
        if let tags = self.tags {
            var maxX: CGFloat = 0
            let prevExtender = tags.extender
            tags.extender = nil
            for i in 0 ..< tags.tags.count {
                maxX += tags.tags[i].size.width + 3
                if maxX + 20 > chatNameWidth - 20 {
                    if prevExtender?.index != i  {
                        let color = theme.colors.grayIcon
                        let text = TextViewLayout(.initialize(string: "+\(tags.tags.count - i)", color: color, font: .bold(10)))
                        let selectedText = TextViewLayout(.initialize(string: "+\(tags.tags.count - i)", color: theme.colors.accentSelect, font: .bold(10)))
                        
                        text.measure(width: .greatestFiniteMagnitude)
                        selectedText.measure(width: .greatestFiniteMagnitude)
                        let tag = ChatListTag(text: text, selected: selectedText, color: color.withAlphaComponent(0.1), selectedColor: theme.colors.underSelectedColor)
                        tags.extender = .init(tag: tag, index: i)
                    } else {
                        tags.extender = prevExtender
                    }
                    
                    break
                }
            }
        }
        
        return result
    }
    
    public func openWebApp() {
        if let peer = peer {
            BrowserStateContext.get(context).open(tab: .mainapp(bot: .init(peer), source: .generic))
        }
    }
    
    
    public func openPeerStory() {
        if let peerId = peerId {
            let table = self.table
            self.openStory(.init(peerId: peerId, id: nil, messageId: nil, takeControl: { [weak table] peerId, _, storyId in
                var view: NSView?
                table?.enumerateItems(with: { item in
                    if let item = item as? ChatListRowItem, item.peerId == peerId {
                        view = item.takeStoryControl()
                    }
                    return view == nil
                })
                return view
            }, setProgress: { [weak self] signal in
                self?.setStoryProgress(signal)
            }), true, false)
        } else if let storyState = self.storyState, !storyState.items.isEmpty {
            let table = self.table
            self.openStory(.init(peerId: storyState.items[0].peer.id, id: nil, messageId: nil, takeControl: { [weak table] peerId, _, storyId in
                var view: NSView?
                table?.enumerateItems(with: { item in
                    if let item = item as? ChatListRowItem, item.peerId == nil {
                        view = item.takeStoryControl()
                    }
                    return view == nil
                })
                return view
            }, setProgress: { [weak self] signal in
                self?.setStoryProgress(signal)
            }), false, true)
        }
    }

    public var isCommunity: Bool {
        return peer?.isCommunity == true
    }

    public var owningCommunityId: PeerId? {
        return (peer as? TelegramChannel)?.linkedCommunityId
    }

    public var showsCommunityDropdown: Bool {
        return owningCommunityId != nil && !disableCommunityDropdown && !isTopic
    }

    public func openCommunityPreview() {
        if let communityId = owningCommunityId {
            showCommunityView(context, communityId: communityId)
        }
    }

    private func takeStoryControl() -> NSView? {
        (self.view as? ChatListRowView)?.takeStoryControl()
    }
    private func setStoryProgress(_ signal:Signal<Never, NoError>)  {
        (self.view as? ChatListRowView)?.setStoryProgress(signal)
    }
    
    public var markAsUnread: Bool {
        return !isSecret && !isUnreadMarked && badgeNode == nil && !showsMentionSlot && !self.mode.savedMessages
    }
    
    public func collapseOrExpandArchive() {
        ChatListRowItem.collapseOrExpandArchive(context: context)
    }
    
    public static func collapseOrExpandArchive(context: any AccountContextProtocol) {
        ChatListUIHooks.shared.chatListCollapseOrExpandArchive(context)
    }
    
    public static func toggleHideArchive(context: any AccountContextProtocol) {
        ChatListUIHooks.shared.chatListToggleHideArchive(context)
    }
    
    public func toggleHideArchive() {
        ChatListRowItem.toggleHideArchive(context: context)
    }

    public static func accessibilityLabel(title: String?, unreadCount: Int32?) -> String? {
        guard let title = title, !title.isEmpty else {
            return nil
        }
        if let count = unreadCount, count > 0 {
            return title + "\n" + strings().voiceOverChatUnreadMessagesOther(Int(count))
        }
        return title
    }

    public static func accessibilityValue(isArchive: Bool, hasMessage: Bool, incoming: Bool, author: String?, read: Bool, preview: String?) -> String? {
        let preview = preview?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if isArchive {
            return preview.isEmpty ? nil : preview
        }
        guard hasMessage else {
            return strings().voiceOverChatListMessageEmpty
        }
        var parts: [String] = [incoming ? strings().voiceOverChatListMessage : strings().voiceOverChatListOutgoingMessage]
        if incoming, let author = author?.trimmingCharacters(in: .whitespacesAndNewlines), !author.isEmpty {
            parts.append(strings().voiceOverChatListMessageFrom(author))
        }
        if !incoming, read {
            parts.append(strings().voiceOverChatListMessageRead)
        }
        if !preview.isEmpty {
            parts.append(preview)
        }
        return parts.joined(separator: "\n")
    }

    public override var accessibilityLabel: String? {
        return ChatListRowItem.accessibilityLabel(title: displayLayout?.attributedString.string, unreadCount: readState?.count)
    }

    public override var accessibilityValue: String? {
        let message = messages.first
        return ChatListRowItem.accessibilityValue(isArchive: isGroup, hasMessage: message != nil, incoming: message?.flags.contains(.Incoming) ?? false, author: chatNameLayout?.attributedString.string, read: isRead, preview: messageLayout?.attributedString.string)
    }

    public override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        var actions: [NSAccessibilityCustomAction] = []
        if avatarStoryIndicator != nil, !showsCommunityDropdown, context.layout != .minimisize, selectedForum == nil {
            actions.append(NSAccessibilityCustomAction(name: strings().voiceOverCommonStories, handler: { [weak self] in
                self?.openPeerStory()
                return true
            }))
        }
        if isGroup || isAd || context.isFrozen {
            return actions.isEmpty ? nil : actions
        }
        if let communityRemoveAction = self.communityRemoveAction {
            actions.append(NSAccessibilityCustomAction(name: strings().chatListRemoveFromCommunity, handler: {
                communityRemoveAction()
                return true
            }))
            return actions
        }
        let context = self.context
        let isUnread = badgeNode != nil || showsMentionSlot || isUnreadMarked
        let pinTitle = isPinned ? strings().chatListContextUnpin : strings().chatListContextPin
        let muteTitle = isMuted ? strings().chatListContextUnmute : strings().chatListContextMute

        if case let .topic(threadId, data) = mode {
            guard let peer = peer as? TelegramChannel else {
                return actions.isEmpty ? nil : actions
            }
            if isUnread {
                let peerId = peer.id
                actions.append(NSAccessibilityCustomAction(name: strings().chatListContextMaskAsRead, handler: {
                    ChatListRowItem.markTopicAsRead(context: context, peerId: peerId, threadId: threadId)
                    return true
                }))
            }
            if peer.hasPermission(.pinMessages) {
                actions.append(NSAccessibilityCustomAction(name: pinTitle, handler: { [weak self] in
                    self?.togglePinned()
                    return true
                }))
            }
            actions.append(NSAccessibilityCustomAction(name: muteTitle, handler: { [weak self] in
                self?.toggleMuted()
                return true
            }))
            if data.isOwnedByMe || peer.isAdmin {
                actions.append(NSAccessibilityCustomAction(name: strings().chatListContextDelete, handler: { [weak self] in
                    self?.delete()
                    return true
                }))
            }
            return actions
        }

        if groupId == .root {
            actions.append(NSAccessibilityCustomAction(name: pinTitle, handler: { [weak self] in
                self?.togglePinned()
                return true
            }))
        }

        guard let peerId = peerId, let mainPeer = peer, let peer = renderedPeer?.peers[peerId]?._asPeer() else {
            return actions.isEmpty ? nil : actions
        }

        if groupId == .root, canArchive || associatedGroupId != .root {
            if associatedGroupId == .root {
                actions.append(NSAccessibilityCustomAction(name: strings().chatListSwipingArchive, handler: { [weak self] in
                    self?.toggleArchive()
                    return true
                }))
            } else {
                actions.append(NSAccessibilityCustomAction(name: strings().chatListSwipingUnarchive, handler: { [weak self] in
                    self?.toggleArchive(unarchive: true)
                    return true
                }))
            }
        }

        if context.peerId != peer.id, !mode.savedMessages {
            actions.append(NSAccessibilityCustomAction(name: muteTitle, handler: { [weak self] in
                self?.toggleMuted()
                return true
            }))
        }

        if !isSecret, !mode.savedMessages {
            if markAsUnread {
                actions.append(NSAccessibilityCustomAction(name: strings().chatListContextMaskAsUnread, handler: {
                    ChatListRowItem.markAsUnread(context: context, peerId: peerId)
                    return true
                }))
            } else if isUnread {
                actions.append(NSAccessibilityCustomAction(name: strings().chatListContextMaskAsRead, handler: {
                    ChatListRowItem.markAsRead(context: context, peerId: peerId)
                    return true
                }))
            }
        }

        let deleteTitle: String?
        if mode.savedMessages {
            deleteTitle = strings().chatListContextDelete
        } else if mainPeer is TelegramUser {
            deleteTitle = strings().chatListContextDeleteChat
        } else if peer is TelegramGroup {
            deleteTitle = strings().chatListContextDeleteAndExit
        } else if let peer = peer as? TelegramChannel, !peer.flags.contains(.hasGeo) {
            if case .broadcast = peer.info {
                deleteTitle = strings().chatListContextLeaveChannel
            } else {
                deleteTitle = strings().chatListContextLeaveGroup
            }
        } else {
            deleteTitle = nil
        }
        if let deleteTitle = deleteTitle {
            actions.append(NSAccessibilityCustomAction(name: deleteTitle, handler: { [weak self] in
                self?.delete()
                return true
            }))
        }
        return actions
    }

    public static func markAsUnread(context: any AccountContextProtocol, peerId: PeerId) {
        _ = context.engine.messages.togglePeersUnreadMarkInteractively(peerIds: [peerId], setToValue: true).start()
    }

    public static func markAsRead(context: any AccountContextProtocol, peerId: PeerId) {
        _ = context.engine.messages.togglePeersUnreadMarkInteractively(peerIds: [peerId], setToValue: false).start()
        _ = clearPeerUnseenPersonalMessagesInteractively(account: context.account, peerId: peerId, threadId: nil).start()
    }

    public static func markTopicAsRead(context: any AccountContextProtocol, peerId: PeerId, threadId: Int64) {
        _ = context.engine.messages.markForumThreadAsRead(peerId: peerId, threadId: threadId).start()
    }

    public func toggleUnread() {
        if let peerId = peerId {
            switch mode {
            case .chat:
                _ = context.engine.messages.togglePeersUnreadMarkInteractively(peerIds: [peerId], setToValue: nil).start()
            case .topic:
                break
            case .savedMessages:
                break
            }
        }
    }
    
    public func toggleMuted() {
        let peerId = renderedPeer?.chatMainPeer?.id ?? peerId
        if let peerId = peerId {
            ChatListRowItem.toggleMuted(context: context, peerId: peerId, isMuted: isMuted, threadId: self.mode.threadId)
        }
    }
    public func delete() {
        if let peerId = peerId {
            let signal = ChatUIHooks.shared.removeThreadInteractively(context, peerId, self.mode.threadId, peer?.id)
            _ = signal.start()
        }
    }
    
    public static func toggleMuted(context: any AccountContextProtocol, peerId: PeerId, isMuted: Bool, threadId: Int64?) {
        if isMuted {
            _ = context.engine.peers.togglePeerMuted(peerId: peerId, threadId: threadId).start()
        } else {
            var options:[ModalOptionSet] = []
            
            options.append(ModalOptionSet(title: strings().chatListMute1Hour, selected: false, editable: true))
            options.append(ModalOptionSet(title: strings().chatListMute4Hours, selected: false, editable: true))
            options.append(ModalOptionSet(title: strings().chatListMute8Hours, selected: false, editable: true))
            options.append(ModalOptionSet(title: strings().chatListMute1Day, selected: false, editable: true))
            options.append(ModalOptionSet(title: strings().chatListMute3Days, selected: false, editable: true))
            options.append(ModalOptionSet(title: strings().chatListMuteForever, selected: true, editable: true))
            
            let intervals:[Int32] = [60 * 60, 60 * 60 * 4, 60 * 60 * 8, 60 * 60 * 24, 60 * 60 * 24 * 3, Int32.max]
            
            showModal(with: ModalOptionSetController(context: context, options: options, selectOne: true, actionText: (strings().chatInputMute, theme.colors.accent), title: strings().peerInfoNotifications, result: { result in
                
                for (i, option) in result.enumerated() {
                    inner: switch option {
                    case .selected:
                        _ = context.engine.peers.updatePeerMuteSetting(peerId: peerId, threadId: threadId, muteInterval: intervals[i]).start()
                        break
                    default:
                        break inner
                    }
                }
                
            }), for: context.window)
        }
    }
    
    public func togglePinned() {
        if let peerId = peerId {
            ChatListRowItem.togglePinned(context: context, peerId: peerId, isPinned: self.isPinned, mode: self.mode, filter: filter, associatedGroupId: associatedGroupId)
        }
    }
    
    public static func togglePinned(context: any AccountContextProtocol, peerId: PeerId, isPinned: Bool, mode: ChatListRowItem.Mode, filter: ChatListFilter, associatedGroupId: EngineChatList.Group) {
        
        
        switch mode {
        case let .topic(threadId, _):
            let signal = context.engine.peers.toggleForumChannelTopicPinned(id: peerId, threadId: threadId) |> deliverOnMainQueue
            _ = signal.start(error: { error in
                switch error {
                case let .limitReached(count):
                    alert(for: context.window, info: strings().chatListContextPinErrorTopicsOther(count))
                default:
                    alert(for: context.window, info: strings().unknownError)
                }
            })
        case let .savedMessages(threadId):
            let signal = context.engine.peers.toggleForumChannelTopicPinned(id: context.peerId, threadId: threadId) |> deliverOnMainQueue
            _ = signal.start(error: { error in
                switch error {
                case let .limitReached(count):
                    alert(for: context.window, info: strings().chatListContextPinErrorTopicsOther(count))
                default:
                    alert(for: context.window, info: strings().unknownError)
                }
            })
        case .chat:
            let location: TogglePeerChatPinnedLocation
            let itemId: PinnedItemId = .peer(peerId)
            if case .filter = filter {
                location = .filter(ChatListUIHooks.shared.chatListFilterId(filter))
            } else {
                location = .group(associatedGroupId._asGroup())
            }
            let context = context
            
            _ = (context.engine.peers.toggleItemPinned(location: location, itemId: itemId) |> deliverOnMainQueue).start(next: { result in
                switch result {
                case .limitExceeded:
                    if context.isPremium {
                        verifyAlert_button(for: context.window, information: strings().chatListContextPinErrorNew2, ok: strings().alertOK, cancel: "", option: strings().chatListContextPinErrorNewSetupFolders, successHandler: { result in
                            switch result {
                            case .thrid:
                                context.bindings.rootNavigation().push(ChatListUIHooks.shared.makeChatListFiltersListController(context))
                            default:
                                break
                            }
                        })

                    } else {
                        if case .filter = filter {
                            FeatureNavigationHooks.shared.showPremiumLimit(context, .pinInFolders(.group(ChatListUIHooks.shared.chatListFilterId(filter))))
                        } else {
                            if case .archive = associatedGroupId {
                                FeatureNavigationHooks.shared.showPremiumLimit(context, .pinInArchive)
                            } else {
                                FeatureNavigationHooks.shared.showPremiumLimit(context, .pin)
                            }
                        }
                    }
                default:
                    break
                }
            })
        }
    }
    
    public func toggleArchive(unarchive: Bool = false) {
        ChatListRowItem.toggleArchive(context: context, associatedGroupId: unarchive ? .archive : associatedGroupId, peerId: peerId)
    }
    
    public static func toggleArchive(context: any AccountContextProtocol, associatedGroupId: EngineChatList.Group?, peerId: PeerId?) {
        if let peerId = peerId {
            switch associatedGroupId {
            case .root:
                ChatListUIHooks.shared.chatListSetAnimateGroupNextTransition(context, EngineChatList.Group.archive)
                _ = context.engine.peers.updatePeersGroupIdInteractively(peerIds: [peerId], groupId: .archive).start()
            default:
                _ = context.engine.peers.updatePeersGroupIdInteractively(peerIds: [peerId], groupId: .root).start()
            }
            _ = showModalSuccess(for: context.window, icon: theme.icons.successModalProgress, delay: 2.0).start()
        }
    }
    
    public static func toggleTopic(context: any AccountContextProtocol, peerId: PeerId, threadId: Int64, isClosed: Bool) {
        _ = context.engine.peers.setForumChannelTopicClosed(id: peerId, threadId: threadId, isClosed: !isClosed).start()
    }
    
    
    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        guard !context.isFrozen else {
            return .complete()
        }
        return chatListMenuItems()
    }

    private func chatListMenuItems() -> Signal<[ContextMenuItem], NoError> {
        if let communityRemoveAction = self.communityRemoveAction {
            return .single([ContextMenuItem(strings().chatListRemoveFromCommunity, handler: communityRemoveAction, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value)])
        }
        
        _ = self.message
        let context = self.context
        let peerId = self.peerId
        let effectivePeerId = self.renderedPeer?.chatMainPeer?.id ?? self.peerId
        let peer = self.peer
        let filter = self.filter
        let isMuted = self.isMuted
        let associatedGroupId = self.associatedGroupId
        let isAd = self.isAd
        let renderedPeer = self.renderedPeer
        let canArchive = self.canArchive
        let groupId = self.groupId
        let markAsUnread = self.markAsUnread
        let isPinned = self.isPinned
        let hideStatus = hideStatus
        let isSecret = self.isSecret
        let isUnread = badgeNode != nil || showsMentionSlot || isUnreadMarked
        let threadId = self.mode.threadId
        let mode = self.mode
        let isClosedTopic = self.isClosedTopic
        _ = self.isForum
        _ = self.entryId
       
        let deleteChat:()->Void = {
            if let peerId = peerId {
                let signal = ChatUIHooks.shared.removeThreadInteractively(context, peerId, threadId, peer?.id)
                _ = signal.start()
            }
        }
        
        let togglePin:()->Void = {
            if let peerId = peerId {
                ChatListRowItem.togglePinned(context: context, peerId: peerId, isPinned: isPinned, mode: mode, filter: filter, associatedGroupId: associatedGroupId)
            }
        }
        
        let previewChat:()->Void = {
            if let peerId = peerId {
                ChatListRowItem.previewChat(peerId: peerId, peer: peer, context: context)
            }
        }
        
        let toggleArchive:(Bool)->Void = { unarchive in
            if let peerId = peerId {
                ChatListRowItem.toggleArchive(context: context, associatedGroupId: unarchive ? .archive : associatedGroupId, peerId: peerId)
            }
        }
        
        let toggleMute:()->Void = {
            if let peerId = effectivePeerId {
                ChatListRowItem.toggleMuted(context: context, peerId: peerId, isMuted: isMuted, threadId: threadId)
            }
        }
        let toggleTopic:()->Void = {
            if let peerId = peerId, let threadId = threadId {
                ChatListRowItem.toggleTopic(context: context, peerId: peerId, threadId: threadId, isClosed: isClosedTopic)
            }
        }
        
        if case let .topic(_, data) = self.mode, let peer = peer as? TelegramChannel, let threadId = threadId {
            
            var items:[ContextMenuItem] = []
            
            if isUnread {
                items.append(ContextMenuItem(strings().chatListContextMaskAsRead, handler: {
                    ChatListRowItem.markTopicAsRead(context: context, peerId: peer.id, threadId: threadId)
                }, itemImage: MenuAnimation.menu_read.value))
            }
            
            if !peer.hasSensitiveContent(platform: "ios") {
                items.append(ContextMenuItem(strings().chatListContextPreview, handler: {
                    ChatListRowItem.previewTopic(peerId: peer.id, threadId: threadId, context: context)
                }, itemImage: MenuAnimation.menu_eye.value))
            }

            if peer.hasPermission(.pinMessages) {
                items.append(ContextMenuItem(!isPinned ? strings().chatListContextPin : strings().chatListContextUnpin, handler: togglePin, itemImage: !isPinned ? MenuAnimation.menu_pin.value : MenuAnimation.menu_unpin.value))
            }

            
            items.append(ContextMenuItem(isMuted ? strings().chatListContextUnmute : strings().chatListContextMute, handler: toggleMute, itemImage: isMuted ? MenuAnimation.menu_unmuted.value : MenuAnimation.menu_mute.value))
                        
            if threadId == 1, peer.hasPermission(.manageTopics), let peerId = peerId {
                items.append(ContextMenuItem(data.isHidden ? strings().chatListContextUnhideGeneral : strings().chatListContextHideGeneral, handler: {
                    
                    _ = context.engine.peers.setForumChannelTopicHidden(id: peerId, threadId: threadId, isHidden: !data.isHidden).start()
                    
                }, itemImage: !data.isHidden ? MenuAnimation.menu_hide.value : MenuAnimation.menu_show.value))

            }
            
            if data.isOwnedByMe || peer.isAdmin {
                items.append(ContextMenuItem(!isClosedTopic ? strings().chatListContextPause : strings().chatListContextStart, handler: toggleTopic, itemImage: !isClosedTopic ? MenuAnimation.menu_pause.value : MenuAnimation.menu_play.value))
                
                items.append(ContextSeparatorItem())
                items.append(ContextMenuItem(strings().chatListContextDelete, handler: deleteChat, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
            }
            
           
 
            
            return .single(items)
        }
        
        let cachedData:Signal<CachedPeerData?, NoError>
        if let peerId = peerId {
            cachedData = getCachedDataView(peerId: peerId, postbox: context.account.postbox)
        } else {
            cachedData = .single(nil)
        }
        
        let soundsDataSignal = combineLatest(queue: .mainQueue(), appNotificationSettings(accountManager: context.sharedContext.accountManager), context.engine.peers.notificationSoundList(), context.account.postbox.transaction { transaction -> TelegramPeerNotificationSettings? in
            if let peerId = peerId {
                return transaction.getPeerNotificationSettings(id: peerId) as? TelegramPeerNotificationSettings
            } else {
                return nil
            }
        })
        
        

        return combineLatest(queue: .mainQueue(), chatListFilterPreferences(engine: context.engine), cachedData, soundsDataSignal, context.engine.messages.chatList(group: .archive, count: 1000) |> take(1), context.engine.data.get(TelegramEngine.EngineData.Item.Peer.DisplaySavedChatsAsTopics())) |> take(1) |> map { filters, cachedData, soundsData, archived, displaySavedChatsAsTopics -> [ContextMenuItem] in
            
            var items:[ContextMenuItem] = []
            
            let canDeleteForAll: Bool?
            if let cachedData = cachedData as? CachedChannelData {
                canDeleteForAll = cachedData.flags.contains(.canDeleteHistory)
            } else {
                canDeleteForAll = nil
            }
            
            var headGroup: [ContextMenuItem] = []
            var zeroGroup: [ContextMenuItem] = []
            var firstGroup:[ContextMenuItem] = []
            var secondGroup:[ContextMenuItem] = []
            var thirdGroup:[ContextMenuItem] = []

           
            
            if let mainPeer = peer, let peerId = peerId, let peer = renderedPeer?.peers[peerId] {
                
                headGroup.append(ContextMenuItem(strings().accountOpenInWindow, handler: {
                    ChatListUIHooks.shared.openPeerInNewWindow(context, peerId)
                }, itemImage: MenuAnimation.menu_open_with.value))
                
                if peerId == context.peerId, case .chat = mode {
                    zeroGroup.append(ContextMenuItem(strings().chatSavedMessagesViewAsMessages, handler: {
                        context.engine.peers.updateSavedMessagesViewAsTopics(value: false)
                    }, itemImage: !displaySavedChatsAsTopics ? MenuAnimation.menu_check_selected.value : nil))
                    
                    zeroGroup.append(ContextMenuItem(strings().chatSavedMessagesViewAsChats, handler: {
                        context.engine.peers.updateSavedMessagesViewAsTopics(value: true)
                    }, itemImage: displaySavedChatsAsTopics ? MenuAnimation.menu_check_selected.value : nil))
                }

                if peer._asPeer().isCommunity {
                    zeroGroup.append(ContextMenuItem(strings().chatListUngroup, handler: {
                        verifyAlert(for: context.window, header: strings().chatListUngroupChats, information: strings().chatListUngroupChatsInfo, ok: strings().chatListUngroup, successHandler: { _ in
                            let disposable = MetaDisposable()
                            disposable.set(context.engine.peers.toggleCommunityCollapsedInDialogs(communityId: peerId, collapsed: false).start(error: { _ in
                                disposable.dispose()
                            }, completed: {
                                disposable.dispose()
                            }))
                        })
                    }, itemImage: MenuAnimation.menu_expand.value))
                }

                if !isAd && groupId == .root {
                    firstGroup.append(ContextMenuItem(!isPinned ? strings().chatListContextPin : strings().chatListContextUnpin, handler: togglePin, itemImage: !isPinned ? MenuAnimation.menu_pin.value : MenuAnimation.menu_unpin.value))
                }
                
                
                
                
                if groupId == .root, (canArchive || associatedGroupId != .root) {
                    
                    let isArchived = archived.items.contains(where: { $0.renderedPeer.peerId == peerId })

                    
                    secondGroup.append(ContextMenuItem(associatedGroupId == .root && !isArchived ? strings().chatListSwipingArchive : strings().chatListSwipingUnarchive, handler: {
                        toggleArchive(isArchived)
                    }, itemImage: associatedGroupId == .root && !isArchived ? MenuAnimation.menu_archive.value : MenuAnimation.menu_unarchive.value))
                }
                
                if context.peerId != peer.id, !isAd, !mode.savedMessages {
                    let muteItem = ContextMenuItem(isMuted ? strings().chatListContextUnmute : strings().chatListContextMute, handler: toggleMute, itemImage: isMuted ? MenuAnimation.menu_unmuted.value : MenuAnimation.menu_mute.value)
                    
                    let sound: ContextMenuItem = ContextMenuItem(strings().chatListContextSound, handler: {
                        
                    }, itemImage: MenuAnimation.menu_music.value)
                    
                    let soundList = ContextMenu()
                    
                    
                    let selectedSound: PeerMessageSound
                    if let peerNotificationSettings = soundsData.2 {
                        selectedSound = peerNotificationSettings.messageSound
                    } else {
                        selectedSound = .default
                    }
                    
                    let playSound:(PeerMessageSound) -> Void = { tone in
                        let effectiveTone: PeerMessageSound
                        if tone == .default {
                            effectiveTone = soundsData.0.tone
                        } else {
                            effectiveTone = tone
                        }
                        
                        if effectiveTone != .default && effectiveTone != .none {
                            let path = fileNameForNotificationSound(postbox: context.account.postbox, sound: effectiveTone, defaultSound: nil, list: soundsData.1?.sounds)
                            
                            _ = path.start(next: { resource in
                                if let resource = resource {
                                    let path = resourcePath(context.account.postbox, resource)
                                    SoundEffectPlay.play(postbox: context.account.postbox, path: path)
                                }
                            })
                        }
                    }
                    
                    let updateSound:(PeerMessageSound)->Void = { tone in
                        playSound(tone)
                        _ = context.engine.peers.updatePeerNotificationSoundInteractive(peerId: peerId, threadId: threadId, sound: tone).start()

                    }
                    
                    soundList.addItem(ContextMenuItem(localizedPeerNotificationSoundString(sound: .default, default: nil, list: nil), handler: {
                        updateSound(.default)
                    }, hover: {
                        playSound(.default)
                    }, state: selectedSound == .default ? .on : nil))
                    
                    soundList.addItem(ContextMenuItem(localizedPeerNotificationSoundString(sound: .none, default: nil, list: nil), handler: {
                        updateSound(.none)
                    }, hover: {
                        playSound(.none)
                    }, state: selectedSound == .none ? .on : nil))
                    soundList.addItem(ContextSeparatorItem())
                    
                    
                    
                    if let sounds = soundsData.1 {
                        for sound in sounds.sounds {
                            let tone: PeerMessageSound = .cloud(fileId: sound.file.fileId.id)
                            soundList.addItem(ContextMenuItem(localizedPeerNotificationSoundString(sound: .cloud(fileId: sound.file.fileId.id), default: nil, list: sounds.sounds), handler: {
                                updateSound(tone)
                            }, hover: {
                                playSound(tone)
                            }, state: selectedSound == .cloud(fileId: sound.file.fileId.id) ? .on : nil))
                        }
                        if !sounds.sounds.isEmpty {
                            soundList.addItem(ContextSeparatorItem())
                        }
                    }
                    
                 
                    for i in 0 ..< 12 {
                        let sound: PeerMessageSound = .bundledModern(id: Int32(i))
                        soundList.addItem(ContextMenuItem(localizedPeerNotificationSoundString(sound: sound, default: nil, list: soundsData.1?.sounds), handler: {
                            updateSound(sound)
                        }, hover: {
                            playSound(sound)
                        }, state: selectedSound == sound ? .on : nil))
                    }
                    soundList.addItem(ContextSeparatorItem())
                    for i in 0 ..< 8 {
                        let sound: PeerMessageSound = .bundledClassic(id: Int32(i))
                        soundList.addItem(ContextMenuItem(localizedPeerNotificationSoundString(sound: sound, default: nil, list: soundsData.1?.sounds), handler: {
                            updateSound(sound)
                        }, hover: {
                            playSound(sound)
                        }, state: selectedSound == sound ? .on : nil))
                    }
                    
                    
                    sound.submenu = soundList
                    
                    
                    if !isMuted, let peerId = effectivePeerId {
                        let submenu = ContextMenu()
                        submenu.addItem(ContextMenuItem(strings().chatListMute1Hour, handler: {
                            _ = context.engine.peers.updatePeerMuteSetting(peerId: peerId, threadId: threadId, muteInterval: 60 * 60 * 1).start()
                        }, itemImage: MenuAnimation.menu_mute_for_1_hour.value))
                        
                        submenu.addItem(ContextMenuItem(strings().chatListMute8Hours, handler: {
                            _ = context.engine.peers.updatePeerMuteSetting(peerId: peerId, threadId: threadId, muteInterval: 60 * 60 * 8).start()
                        }, itemImage: MenuAnimation.menu_mute_for_1_hour.value))
                        
                        submenu.addItem(ContextMenuItem(strings().chatListMute3Days, handler: {
                            _ = context.engine.peers.updatePeerMuteSetting(peerId: peerId, threadId: threadId, muteInterval: 60 * 60 * 24 * 3).start()
                        }, itemImage: MenuAnimation.menu_mute_for_2_days.value))
                        
                        submenu.addItem(ContextSeparatorItem())
                        
                        submenu.addItem(ContextMenuItem(strings().chatListMuteUntil, handler: {
                            FeatureNavigationHooks.shared.selectDate(context, context.window, nil, nil, .date(title: strings().chatListMuteUntilTitle, doneTitle: strings().chatListMuteUntilOK), { date, _ in
                                _ = context.engine.peers.updatePeerMuteSetting(peerId: peerId, threadId: threadId, muteInterval: Int32(date.timeIntervalSince1970 - Date().timeIntervalSince1970)).start()
                            })
                        }, itemImage: MenuAnimation.menu_schedule_message.value))
                        
                        submenu.addItem(ContextMenuItem(strings().chatListMuteForever, handler: {
                            _ = context.engine.peers.updatePeerMuteSetting(peerId: peerId, threadId: threadId, muteInterval: Int32.max).start()
                        }, itemImage: MenuAnimation.menu_mute.value))

                        
                        submenu.addItem(ContextSeparatorItem())
                        submenu.addItem(sound)
                        
                        muteItem.submenu = submenu
                    } else {
                         let submenu = ContextMenu()
                         submenu.addItem(sound)
                         muteItem.submenu = submenu
                     }
                     
                     
                    
                    firstGroup.append(muteItem)
                }
                
                if mainPeer is TelegramUser, !mode.savedMessages {
                    thirdGroup.append(ContextMenuItem(strings().chatListContextClearHistory, handler: {
                        clearHistory(context: context, peer: peer._asPeer(), mainPeer: mainPeer, canDeleteForAll: canDeleteForAll)
                    }, itemImage: MenuAnimation.menu_clear_history.value))
                    thirdGroup.append(ContextMenuItem(strings().chatListContextDeleteChat, handler: deleteChat, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                }
                
                if !isSecret {
                    if markAsUnread {
                        firstGroup.append(ContextMenuItem(strings().chatListContextMaskAsUnread, handler: {
                            ChatListRowItem.markAsUnread(context: context, peerId: peerId)
                        }, itemImage: MenuAnimation.menu_unread.value))
                        
                    } else if isUnread {
                        firstGroup.append(ContextMenuItem(strings().chatListContextMaskAsRead, handler: {
                            ChatListRowItem.markAsRead(context: context, peerId: peerId)
                        }, itemImage: MenuAnimation.menu_read.value))
                    }
                }
                
                if isAd {
                    firstGroup.append(ContextMenuItem(strings().chatListContextHidePromo, handler: {
                        ChatListUIHooks.shared.chatListHidePromoItem(context, peerId)
                    }, itemImage: MenuAnimation.menu_archive.value))
                }
                if let peer = peer._asPeer() as? TelegramGroup, !isAd, !mode.savedMessages {
                    thirdGroup.append(ContextMenuItem(strings().chatListContextClearHistory, handler: {
                        clearHistory(context: context, peer: peer, mainPeer: mainPeer, canDeleteForAll: canDeleteForAll)
                    }, itemImage: MenuAnimation.menu_delete.value))
                    thirdGroup.append(ContextMenuItem(strings().chatListContextDeleteAndExit, handler: deleteChat, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                } else if let peer = peer._asPeer() as? TelegramChannel, !isAd, !peer.flags.contains(.hasGeo), !mode.savedMessages {
                    
                    if case .broadcast = peer.info {
                        thirdGroup.append(ContextMenuItem(strings().chatListContextLeaveChannel, handler: deleteChat, itemMode: .destruct, itemImage: MenuAnimation.menu_leave.value))
                    } else if !isAd {
                        if peer.addressName == nil {
                            thirdGroup.append(ContextMenuItem(strings().chatListContextClearHistory, handler: {
                                clearHistory(context: context, peer: peer, mainPeer: mainPeer, canDeleteForAll: canDeleteForAll)
                            }, itemImage: MenuAnimation.menu_clear_history.value))
                        } 
                        thirdGroup.append(ContextMenuItem(strings().chatListContextLeaveGroup, handler: deleteChat, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                    }
                }
                
            } else {
                if !isAd, groupId == .root {
                    firstGroup.append(ContextMenuItem(!isPinned ? strings().chatListContextPin : strings().chatListContextUnpin, handler: togglePin, itemImage: isPinned ? MenuAnimation.menu_unpin.value : MenuAnimation.menu_pin.value))
                }
            }
            
            if mode.savedMessages {
                thirdGroup.append(ContextSeparatorItem())
                thirdGroup.append(ContextMenuItem(strings().chatListContextDelete, handler: deleteChat, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
            }
            
            if groupId != .root, context.layout != .minimisize, let hideStatus = hideStatus, !mode.savedMessages {
                switch hideStatus {
                case .collapsed:
                    firstGroup.append(ContextMenuItem(strings().chatListRevealActionExpand, handler: {
                        ChatListRowItem.collapseOrExpandArchive(context: context)
                    }, itemImage: MenuAnimation.menu_expand.value))
                default:
                    firstGroup.append(ContextMenuItem(strings().chatListRevealActionCollapse, handler: {
                        ChatListRowItem.collapseOrExpandArchive(context: context)
                    }, itemImage: MenuAnimation.menu_collapse.value))
                }
            }
            
            if peerId != nil {
                firstGroup.append(ContextMenuItem(strings().chatListContextPreview, handler: {
                    previewChat()
                }, itemImage: MenuAnimation.menu_eye.value))
            }
            
            var submenu: [ContextMenuItem] = []
            if let peerId = peerId, peerId.namespace != Namespaces.Peer.SecretChat, !mode.savedMessages {
                for item in filters.list {
                    inner: switch item {
                    case .allChats:
                        break inner;
                    case let .filter(_, _, _, data):
                        
                        let attr = NSMutableAttributedString()
                        attr.append(string: item.title, color: theme.colors.text, font: .normal(.text))
                        InlineStickerItem.apply(to: attr, associatedMedia: [:], entities: item.entities, isPremium: true, playPolicy: item.enableAnimations ? nil : .framesCount(1))

                        
                        let menuItem = ContextMenuItem(item.title, handler: {
                            
                            let limit = context.isPremium ? context.premiumLimits.dialog_filters_chats_limit_premium : context.premiumLimits.dialog_filters_chats_limit_default
                            
                            let isEnabled = data.includePeers.peers.contains(peerId) || data.includePeers.peers.count < limit
                            if !data.includePeers.peers.contains(peerId) {
                            }
                            if isEnabled {
                                _ = context.engine.peers.updateChatListFiltersInteractively({ list in
                                    var list = list
                                    for (i, folder) in list.enumerated() {
                                        if ChatListUIHooks.shared.chatListFilterId(folder) == ChatListUIHooks.shared.chatListFilterId(item), var folderData = folder.data {
                                            if data.includePeers.peers.contains(peerId) {
                                                var peers = folderData.includePeers.peers
                                                peers.removeAll(where: { $0 == peerId })
                                                folderData.includePeers.setPeers(peers)
                                            } else {
                                                folderData.excludePeers.removeAll(where: { $0 == peerId })
                                                folderData.includePeers.setPeers(folderData.includePeers.peers + [peerId])
                                            }
                                            list[i] = list[i].withUpdatedData(folderData)
                                        }
                                    }
                                    return list
                                }).start()
                            } else {
                                if context.isPremium {
                                    alert(for: context.window, info: strings().chatListFilterIncludeLimitReached)
                                } else {
                                    FeatureNavigationHooks.shared.showPremiumLimit(context, .chatInFolders)
                                }
                            }
                           
                        }, state: data.includePeers.peers.contains(peerId) ? .on : nil, itemImage: ChatHistoryUIHooks.shared.folderEmoticonDrawable(FolderIcon(item).emoticon).value, attributedTitle: attr, customTextView: {
                            let layout = TextViewLayout(attr)
                            layout.measure(width: .greatestFiniteMagnitude)

                            let textView = InteractiveTextView()
                            textView.userInteractionEnabled = false
                            textView.textView.isSelectable = false
                            textView.set(text: layout, context: context)
                            return textView
                        })
                        submenu.append(menuItem)
                        menuItem.isEnabled = !data.includePeers.peers.contains(peerId) || data.includePeers.peers.count > 1
                    }
                }
            }
            
            if !submenu.isEmpty {
                let item = ContextMenuItem(strings().chatListFilterAddToFolder, itemImage: MenuAnimation.menu_add_to_folder.value)
                let menu = ContextMenu()
                for item in submenu {
                    menu.addItem(item)
                }
                item.submenu = menu
                secondGroup.append(item)
            }

            if let peerId = peerId, peerId.namespace != Namespaces.Peer.SecretChat, !isAd, case .chat = mode, case let .filter(filterId, _, _, _) = filter {
                secondGroup.append(ContextMenuItem(strings().chatListFilterRemoveFromFolder, handler: {
                    let limit = context.isPremium ? context.premiumLimits.dialog_filters_chats_limit_premium : context.premiumLimits.dialog_filters_chats_limit_default
                    _ = context.engine.peers.updateChatListFiltersInteractively({ list in
                        var list = list
                        if let index = list.firstIndex(where: { $0.id == filterId }), var data = list[index].data {
                            if data.isShared || data.categories.isEmpty {
                                _ = data.includePeers.removePeer(peerId)
                            } else {
                                if !data.excludePeers.contains(peerId), data.excludePeers.count >= limit {
                                    Queue.mainQueue().async {
                                        alert(for: context.window, info: strings().chatListFilterExcludeLimitReachedNew(Int(limit)))
                                    }
                                    return list
                                }
                                _ = data.addExcludePeer(peerId: peerId)
                            }
                            list[index] = list[index].withUpdatedData(data)
                        }
                        return list
                    }).start()
                }, itemImage: MenuAnimation.menu_unarchive.value))
            }
            
            let blocks:[[ContextMenuItem]] = [headGroup, zeroGroup, firstGroup,
                                              secondGroup,
                                              thirdGroup].filter { !$0.isEmpty }
            
            for (i, block) in blocks.enumerated() {
                if i == 0 {
                    items.append(contentsOf: block)
                } else {
                    items.append(ContextSeparatorItem())
                    items.append(contentsOf: block)
                }
            }
            return items
        }
    }
    
    public var ctxDisplayLayout:TextViewLayout? {
        if isActiveSelected {
            if displaySelectedLayout == nil, let src = displayLayout?.attributedString {
                let selected = src.mutableCopy() as! NSMutableAttributedString
                if let color = selected.attribute(.selectedColor, at: 0, effectiveRange: nil) {
                    selected.addAttribute(NSAttributedString.Key.foregroundColor, value: color, range: selected.range)
                    if displaySelectedUsesMayItemsFalse {
                        displaySelectedLayout = TextViewLayout(selected, mayItems: false)
                    } else {
                        displaySelectedLayout = TextViewLayout(selected, maximumNumberOfLines: 1)
                    }
                }
            }
            if let width = displaySelectedPendingWidth {
                displaySelectedPendingWidth = nil
                displaySelectedLayout?.measure(width: width)
            }
            return displaySelectedLayout
        }
        return displayLayout
    }
    
    public var ctxOpenMiniApp: TextViewLayout? {
        if isActiveSelected {
            return openMiniAppSelected
        }
        return openMiniApp
    }
    
    public var ctxMonoforumMessages: TextViewLayout? {
        if isActiveSelected {
            return monoforumMessagesSelected
        }
        return monoforumMessages
    }
    
    public var isActiveSelected: Bool {
        return isSelected && context.layout != .single && !(isForum && !isTopic)
    }
    
    public var isReplyToStory: Bool {
        if self.messages.first(where: { $0.storyAttribute != nil }) != nil {
            if isForum && !isTopic {
                return false
            }
            return true
        }
        return false
    }
    
    public var ctxChatNameLayout:TextViewLayout? {
        if isActiveSelected {
            if chatNameSelectedLayout == nil, let src = chatNameLayout?.attributedString {
                let selectedText = src.mutableCopy() as! NSMutableAttributedString
                if let color = selectedText.attribute(.selectedColor, at: 0, effectiveRange: nil) {
                    selectedText.addAttribute(NSAttributedString.Key.foregroundColor, value: color, range: selectedText.range)
                }
                chatNameSelectedLayout = .init(selectedText, maximumNumberOfLines: 1)
            }
            if let width = chatNameSelectedPendingWidth {
                chatNameSelectedPendingWidth = nil
                chatNameSelectedLayout?.measure(width: width)
            }
            return chatNameSelectedLayout
        }
        return chatNameLayout
    }
    
    public var ctxForumTopicNameLayout:TextViewLayout? {
        if isActiveSelected {
            if forumTopicNameSelectedLayout == nil, let src = forumTopicNameLayout?.attributedString {
                let selectedText = src.mutableCopy() as! NSMutableAttributedString
                selectedText.addAttribute(NSAttributedString.Key.foregroundColor, value: theme.colors.underSelectedColor, range: selectedText.range)
                forumTopicNameSelectedLayout = .init(selectedText, maximumNumberOfLines: 1)
            }
            if let width = forumTopicNameSelectedPendingWidth {
                forumTopicNameSelectedPendingWidth = nil
                forumTopicNameSelectedLayout?.measure(width: width)
            }
            return forumTopicNameSelectedLayout
        }
        return forumTopicNameLayout
    }
    
    
    public var ctxMessageText:TextViewLayout? {
        if self.activities.isEmpty {
            if isActiveSelected {
                if messageSelectedLayout == nil, let src = messageLayout?.attributedString {
                    let selectedText = src.mutableCopy() as! NSMutableAttributedString
                    if let color = selectedText.attribute(.selectedColor, at: 0, effectiveRange: nil) {
                        selectedText.addAttribute(NSAttributedString.Key.foregroundColor, value: color, range: selectedText.range)
                        messageSelectedLayout = .init(selectedText, maximumNumberOfLines: messageSelectedMaxLines, cutout: messageSelectedCutout)
                    }
                }
                if let width = messageSelectedPendingWidth {
                    messageSelectedPendingWidth = nil
                    messageSelectedLayout?.measure(width: width)
                }
                return messageSelectedLayout
            }
            return messageLayout
        }
        return nil
    }
    
    public var ctxDateLayout:TextViewLayout? {
        if hasDraft {
            return nil
        }
        if isActiveSelected {
            if dateSelectedLayout == nil, let src = dateLayout?.attributedString {
                let selectedDate = src.mutableCopy() as! NSMutableAttributedString
                if let color = selectedDate.attribute(.selectedColor, at: 0, effectiveRange: nil) {
                    selectedDate.addAttribute(NSAttributedString.Key.foregroundColor, value: color, range: selectedDate.range)
                    let layout = TextViewLayout(selectedDate, mayItems: false)
                    layout.measure(width: .greatestFiniteMagnitude)
                    dateSelectedLayout = layout
                }
            }
            return dateSelectedLayout
        }
        return dateLayout
    }
    
    public var ctxBadgeNode:BadgeNode? {
        if isActiveSelected {
            if badgeSelectedNode == nil, let text = badgeText {
                if let source = shortBadgeSelectedNode {
                    badgeSelectedNode = BadgeNode(textFrom: source, theme.chatList.badgeSelectedBackgroundColor)
                } else {
                    badgeSelectedNode = BadgeNode(.initialize(string: text, color: theme.chatList.badgeSelectedTextColor, font: .medium(.small)), theme.chatList.badgeSelectedBackgroundColor)
                }
            }
            return badgeSelectedNode
        }
        return badgeNode
    }

    public var ctxShortBadgeNode:BadgeNode? {
        if isActiveSelected {
            if shortBadgeSelectedNode == nil, let text = badgeText {
                if let source = badgeSelectedNode {
                    shortBadgeSelectedNode = BadgeNode(textFrom: source, theme.chatList.badgeSelectedBackgroundColor)
                } else {
                    shortBadgeSelectedNode = BadgeNode(.initialize(string: text, color: theme.chatList.badgeSelectedTextColor, font: .medium(.small)), theme.chatList.badgeSelectedBackgroundColor)
                }
            }
            return shortBadgeSelectedNode
        }
        if shortBadgeNode == nil, let source = badgeNode {
            shortBadgeNode = BadgeNode(textFrom: source, source.fillColor)
        }
        return shortBadgeNode
    }
    
//    var ctxBadge: Badge? {
//        if isSelected && context.layout != .single {
//            return badgeSelected
//        }
//        return badge
//    }
    
    
    public override var instantlyResize: Bool {
        return true
    }

    private func setupRelativeDateTimer(relativeTo timestamp: TimeInterval) {
        guard let message = messages.first else { return }
        var relativeDateTimestamps: [Int32] = []
        for attribute in message.attributes {
            if let attribute = attribute as? TextEntitiesMessageAttribute {
                for entity in attribute.entities {
                    if case let .FormattedDate(format, timestamp) = entity.type, case .relative = format {
                        relativeDateTimestamps.append(timestamp)
                    }
                }
                break
            }
        }
        relativeDateTimer?.invalidate()
        relativeDateTimer = RelativeDateUpdateTimer(timestamps: relativeDateTimestamps, relativeTo: timestamp, update: { [weak self] in
            self?.updateRelativeDates()
        })
    }

    private func updateRelativeDates() {
        var hasChanges = false
        for layout in [messageLayout, messageSelectedLayout].compactMap({ $0 }) {
            let mutable = layout.attributedString.mutableCopy() as! NSMutableAttributedString
            var replacements: [(NSRange, String, TextViewFormattedDateData)] = []
            mutable.enumerateAttribute(TextInputAttributes.formattedDate, in: NSRange(location: 0, length: mutable.length), options: []) { value, range, _ in
                if let data = value as? TextViewFormattedDateData, data.isRelative {
                    let newText = formatDateTimeEntity(format: .relative, date: data.date)
                    if newText != data.text {
                        replacements.append((range, newText, data))
                    }
                }
            }
            for (range, newText, oldData) in replacements.reversed() {
                let currentAttributes = mutable.attributes(at: range.location, effectiveRange: nil)
                var updatedAttributes = currentAttributes
                updatedAttributes[TextInputAttributes.formattedDate] = TextViewFormattedDateData(text: newText, date: oldData.date, isRelative: true)
                mutable.replaceCharacters(in: range, with: NSAttributedString(string: newText, attributes: updatedAttributes))
                hasChanges = true
            }
            if !replacements.isEmpty {
                layout.setAttributedString(mutable)
            }
        }
        if hasChanges {
            let width = messageLayout?.constrainedWidth ?? 0
            if width > 0 {
                messageLayout?.measure(width: width)
                messageSelectedPendingWidth = width
            }
            redraw(animated: false)
        }
    }

    deinit {
        relativeDateTimer?.invalidate()
        peerPhotosDisposable.dispose()
    }

    public override func viewClass() -> AnyClass {
        return ChatListRowView.self
    }
  
    public override var height: CGFloat {
        if let hideStatus = hideStatus {
            switch hideStatus {
            case .collapsed:
                return width == 82 ? 70 : 35
            default:
                break
            }
        }
        if shouldHideContent {
            return 70
        }
        
        switch mode {
        case .chat, .savedMessages:
            return 70
        case .topic:
            return 53 + (displayLayout?.layoutSize.height ?? 17)
        }
    }
    
    public func previewChat() {
        guard let peerId = peerId else {
            return
        }
        if let peer = self.peer, !peer.hasSensitiveContent(platform: "ios") {
            if case let .topic(threadId, _) = mode {
                ChatListRowItem.previewTopic(peerId: peerId, threadId: threadId, context: context)
            } else {
                ChatListRowItem.previewChat(peerId: peerId, peer: peer, context: context)
            }
        }
    }
    
    public static func previewChat(peerId: PeerId, peer: Peer?, context: any AccountContextProtocol) {
        if peer?.isCommunity == true {
            showCommunityView(context, communityId: peerId)
            return
        }

        showPreview(context: context, chatLocation: .peer(peerId), holder: nil)
    }

    public static func previewTopic(peerId: PeerId, threadId: Int64, context: any AccountContextProtocol) {
        let threadMessageId = makeThreadIdMessageId(peerId: peerId, threadId: threadId)
        _ = (fetchAndPreloadReplyThreadInfo(context: context, subject: .groupMessage(threadMessageId), preload: false) |> take(1) |> deliverOnMainQueue).start(next: { result in
            showPreview(context: context, chatLocation: .thread(result.message), holder: result.contextHolder)
        })
    }

    private static func showPreview(context: any AccountContextProtocol, chatLocation: ChatLocation, holder: Atomic<ChatLocationContextHolder?>?) {
        let controller = ChatListUIHooks.shared.makeChatControllerWithMode(context, chatLocation, .preview, holder)
        let navigation:NavigationViewController = NavigationViewController(controller, context.window)
        navigation._frameRect = NSMakeRect(0, 0, 400, 500)
        
        let modalController = ChatPreviewModalController(navigation)
        showModal(with: modalController, for: context.window)
        navigation.modal = modalController.modal
    }
    
}

private final class ChatPreviewModalController: ModalController {
    override init(_ controller: NavigationViewController) {
        super.init(controller)
        self.bar = NavigationBarStyle(height: 0)
    }
}
