import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import InAppSettings
import FoundationUtils
import SwiftSignalKit
import TelegramTheme
import TelegramContext
import TelegramUtils
import ChatModeTypes
import MessageUtils
import Localization


public struct ChatPollStateData : Equatable {
    public let identifiers: [Data]
    public let isLoading: Bool
    public init(identifiers: [Data] = [], isLoading: Bool = false) {
        self.identifiers = identifiers
        self.isLoading = isLoading
    }
}

public struct WalletFiatRateProjection: Equatable {
    public let unitsPerGram: Double
    public let currencySymbol: String

    public init(unitsPerGram: Double, currencySymbol: String) {
        self.unitsPerGram = unitsPerGram
        self.currencySymbol = currencySymbol
    }
}

public struct MessageEntryAdditionalData : Equatable {

    public struct ReactionsProjection : Equatable {
        public let hash: Int32
        public let enabledValues: [MessageReaction.Reaction]

        public init?(from reactions: AvailableReactions?) {
            guard let reactions else { return nil }
            self.hash = reactions.hash
            self.enabledValues = reactions.enabled.map { $0.value }
        }

        public static func ==(lhs: ReactionsProjection, rhs: ReactionsProjection) -> Bool {
            return lhs.hash == rhs.hash
        }

    }

    public struct CachedDataProjection : Equatable {
        public let wallpaper: TelegramWallpaper?

        public init?(from cachedData: CachedPeerData?) {
            guard let cachedData else { return nil }
            if let userData = cachedData as? CachedUserData {
                self.wallpaper = userData.wallpaper
            } else if let channelData = cachedData as? CachedChannelData {
                self.wallpaper = channelData.wallpaper
            } else {
                // CachedGroupData has no per-chat wallpaper.
                self.wallpaper = nil
            }
        }
    }

    public struct AutoDownloadProjection : Equatable {
        public let settings: AutomaticMediaDownloadSettings
        public let hash: UInt64

        public init(_ settings: AutomaticMediaDownloadSettings) {
            self.settings = settings
            var hasher = Hasher()
            hasher.combine(settings.automaticDownload)
            hasher.combine(settings.downloadFolder)
            hasher.combine(settings.automaticSaveDownloadedFiles)
            let cats = [settings.categories.photo, settings.categories.video, settings.categories.files]
            for cat in cats {
                hasher.combine(cat.privateChats)
                hasher.combine(cat.groupChats)
                hasher.combine(cat.channels)
                hasher.combine(cat.fileSize)
            }
            self.hash = UInt64(bitPattern: Int64(hasher.finalize()))
        }

        public static func ==(lhs: AutoDownloadProjection, rhs: AutoDownloadProjection) -> Bool {
            return lhs.hash == rhs.hash
        }

        public func isDownloable(_ message: Message) -> Bool {
            return settings.isDownloable(message)
        }
    }

    public let pollStateData: ChatPollStateData
    public let highlightFoundText: HighlightFoundText?
    public let isThreadLoading: Bool
    public let updatingMedia: ChatUpdatingMessageMedia?
    public let chatTheme: TelegramPresentationTheme?
    public let reactions: ReactionsProjection?
    public let transribeState:TranscribeAudioState?
    public let transcriptionTranslate: ChatLiveTranslateContext.State.TranscriptionResult?
    public let eventLog: AdminLogEvent?
    public let isRevealed: Bool?
    public let translate: ChatLiveTranslateContext.State.Result?
    public var replyTranslate: ChatLiveTranslateContext.State.Result?
    public let storyReadMaxId: Int32?
    public let authorStoryStats: PeerStoryStats?
    public let cachedData: CachedDataProjection?
    public let recommendedChannels: RecommendedChannels?
    public let automaticDownload: AutoDownloadProjection
    public let savedMessageTags: SavedMessageTags?
    public let codeSyntaxData: [CodeSyntaxKey : CodeSyntaxResult]
    public let messageEffect: AvailableMessageEffects.MessageEffect?
    public let factCheckRevealed: Bool
    public let solutionRevealed: Bool
    public let quoteRevealed: Set<Int>
    public let detailsExpanded: Set<Int>
    public let monoforumState: MonoforumUIState?
    public let canHighlightLinks: Bool
    public let summarize: ChatLiveTranslateContext.State.SummarizeResult?
    public let walletFiatRate: WalletFiatRateProjection?

    public var transcribeTranslate: String? {
        return transcriptionTranslate?.text
    }
    public var transcribeTranslateLoading: Bool {
        if case .loading = transcriptionTranslate {
            return true
        }
        return false
    }
    public init(pollStateData: ChatPollStateData = ChatPollStateData(), highlightFoundText: HighlightFoundText? = nil, isThreadLoading: Bool = false, updatingMedia: ChatUpdatingMessageMedia? = nil, chatTheme: TelegramPresentationTheme? = nil, reactions: ReactionsProjection? = nil, transribeState:TranscribeAudioState? = nil, transcriptionTranslate: ChatLiveTranslateContext.State.TranscriptionResult? = nil, eventLog: AdminLogEvent? = nil, isRevealed: Bool? = nil, translate: ChatLiveTranslateContext.State.Result? = nil, replyTranslate: ChatLiveTranslateContext.State.Result? = nil, storyReadMaxId: Int32? = nil, authorStoryStats: PeerStoryStats? = nil, cachedData: CachedDataProjection? = nil, recommendedChannels: RecommendedChannels? = nil, automaticDownload: AutoDownloadProjection = AutoDownloadProjection(.defaultSettings), savedMessageTags: SavedMessageTags? = nil, codeSyntaxData: [CodeSyntaxKey : CodeSyntaxResult] = [:], messageEffect: AvailableMessageEffects.MessageEffect? = nil, factCheckRevealed: Bool = false, solutionRevealed: Bool = false, quoteRevealed: Set<Int> = Set(), detailsExpanded: Set<Int> = Set(), monoforumState: MonoforumUIState? = nil, canHighlightLinks: Bool = true, summarize: ChatLiveTranslateContext.State.SummarizeResult? = nil, walletFiatRate: WalletFiatRateProjection? = nil) {
        self.pollStateData = pollStateData
        self.highlightFoundText = highlightFoundText
        self.isThreadLoading = isThreadLoading
        self.updatingMedia = updatingMedia
        self.chatTheme = chatTheme
        self.reactions = reactions
        self.transribeState = transribeState
        self.transcriptionTranslate = transcriptionTranslate
        self.eventLog = eventLog
        self.isRevealed = isRevealed
        self.translate = translate
        self.replyTranslate = replyTranslate
        self.storyReadMaxId = storyReadMaxId
        self.authorStoryStats = authorStoryStats
        self.cachedData = cachedData
        self.recommendedChannels = recommendedChannels
        self.automaticDownload = automaticDownload
        self.savedMessageTags = savedMessageTags
        self.codeSyntaxData = codeSyntaxData
        self.messageEffect = messageEffect
        self.factCheckRevealed = factCheckRevealed
        self.solutionRevealed = solutionRevealed
        self.quoteRevealed = quoteRevealed
        self.detailsExpanded = detailsExpanded
        self.monoforumState = monoforumState
        self.canHighlightLinks = canHighlightLinks
        self.summarize = summarize
        self.walletFiatRate = walletFiatRate
    }


    public static func ==(lhs: MessageEntryAdditionalData, rhs: MessageEntryAdditionalData) -> Bool {
        if lhs.isThreadLoading != rhs.isThreadLoading { return false }
        if lhs.factCheckRevealed != rhs.factCheckRevealed { return false }
        if lhs.solutionRevealed != rhs.solutionRevealed { return false }
        if lhs.canHighlightLinks != rhs.canHighlightLinks { return false }
        if lhs.isRevealed != rhs.isRevealed { return false }
        if lhs.storyReadMaxId != rhs.storyReadMaxId { return false }

        if lhs.pollStateData != rhs.pollStateData { return false }
        if lhs.updatingMedia != rhs.updatingMedia { return false }
        if lhs.highlightFoundText != rhs.highlightFoundText { return false }
        if lhs.summarize != rhs.summarize { return false }
        if lhs.walletFiatRate != rhs.walletFiatRate { return false }
        if lhs.translate != rhs.translate { return false }
        if lhs.replyTranslate != rhs.replyTranslate { return false }
        if lhs.transcriptionTranslate != rhs.transcriptionTranslate { return false }
        if lhs.transribeState != rhs.transribeState { return false }
        if lhs.messageEffect != rhs.messageEffect { return false }
        if lhs.eventLog != rhs.eventLog { return false }

        if lhs.cachedData != rhs.cachedData { return false }
        if lhs.reactions != rhs.reactions { return false }
        if lhs.savedMessageTags != rhs.savedMessageTags { return false }
        if lhs.monoforumState != rhs.monoforumState { return false }
        if lhs.recommendedChannels != rhs.recommendedChannels { return false }
        if lhs.authorStoryStats != rhs.authorStoryStats { return false }
        if lhs.quoteRevealed != rhs.quoteRevealed { return false }
        if lhs.detailsExpanded != rhs.detailsExpanded { return false }
        if lhs.automaticDownload != rhs.automaticDownload { return false }
        if lhs.chatTheme != rhs.chatTheme { return false }

        if lhs.codeSyntaxData != rhs.codeSyntaxData { return false }

        return true
    }
}

public struct HighlightFoundText : Equatable {
    public let query: String
    public let isMessage: Bool
    public init(query: String, isMessage: Bool) {
        self.query = query
        self.isMessage = isMessage
    }
}

public struct ChatHistoryEntryData : Equatable {
    public let location: MessageHistoryEntryLocation?
    public let additionData: MessageEntryAdditionalData
    public let autoPlay: AutoplayMediaPreferences?
    public let isFakeMessage: Bool
    public let isBelow: Bool
    public init(_ location: MessageHistoryEntryLocation? = nil, _ additionData: MessageEntryAdditionalData = .init(), _ autoPlay: AutoplayMediaPreferences? = nil, isFakeMessage: Bool = false, isBelow: Bool = false) {
        self.location = location
        self.additionData = additionData
        self.autoPlay = autoPlay
        self.isFakeMessage = isFakeMessage
        self.isBelow = isBelow
    }
    public static func ==(lhs: ChatHistoryEntryData, rhs: ChatHistoryEntryData) -> Bool {
        if lhs.isFakeMessage != rhs.isFakeMessage { return false }
        if lhs.isBelow != rhs.isBelow { return false }
        if lhs.location != rhs.location { return false }
        if lhs.autoPlay != rhs.autoPlay { return false }
        return lhs.additionData == rhs.additionData
    }
}

public enum ChatHistoryEntry: Identifiable, Comparable {
    
    
    public enum TopicType : Equatable {
        case peer(EnginePeer)
        case topic(Int64, Message.AssociatedThreadInfo)
    }
    
    case MessageEntry(Message, MessageIndex, Bool, ChatItemRenderType, ChatItemType, ForwardItemType?, ChatHistoryEntryData)
    case groupedPhotos([ChatHistoryEntry], groupInfo: MessageGroupInfo)
    case UnreadEntry(MessageIndex, ChatItemRenderType, TelegramPresentationTheme, ChatHistoryEntryData)
    case DateEntry(MessageIndex, ChatItemRenderType, TelegramPresentationTheme, ChatHistoryEntryData)
    case bottom(TelegramPresentationTheme)
    case empty(MessageIndex, TelegramPresentationTheme)
    case commentsHeader(Bool, MessageIndex, ChatItemRenderType)
    case repliesHeader(Bool, MessageIndex, ChatItemRenderType)
    case topThreadInset(CGFloat, MessageIndex, ChatItemRenderType)
    case userInfo(PeerStatusSettings, EnginePeer, GroupsInCommonState?, MessageIndex, ChatItemRenderType, TelegramPresentationTheme)
    case topicSeparator(MessageIndex, TopicType, ChatItemRenderType, ChatHistoryEntryData)
    case newThread(MessageIndex, ChatItemRenderType, ChatHistoryEntryData)

    public var message:Message? {
        switch self {
        case let .MessageEntry(message,_, _,_,_,_,_):
            return message
        case .groupedPhotos(_, _):
            return nil
        default:
            return nil
        }
    }
    
    public var firstMessage:Message? {
        switch self {
        case let .MessageEntry(message,_, _,_,_,_,_):
            return message
        case let .groupedPhotos(entries, _):
            return entries.first?.message
        default:
            return nil
        }
    }
    public var messages:[Message] {
        switch self {
        case let .MessageEntry(message,_, _,_,_,_,_):
            return [message]
        case let .groupedPhotos(entries, _):
            return entries.compactMap { $0.message }
        default:
            return []
        }
    }
    
    public var autoplayMedia: AutoplayMediaPreferences {
        switch self {
        case let .MessageEntry(_,_,_,_,_,_,data):
            return data.autoPlay ?? AutoplayMediaPreferences.defaultSettings
        case let .groupedPhotos(entries, _):
            return entries.first?.autoplayMedia ?? AutoplayMediaPreferences.defaultSettings
        default:
            return AutoplayMediaPreferences.defaultSettings
        }
    }
    
    public var renderType: ChatItemRenderType {
        switch self {
        case let .MessageEntry(_,_,_, renderType,_,_,_):
            return renderType
        case .groupedPhotos(let entries, _):
            return entries.first!.renderType
        case let .DateEntry(_, renderType, _, _):
            return renderType
        case .UnreadEntry(_, let renderType, _, _):
            return renderType
        case .bottom:
            return .list
        case .empty:
            return .list
        case let .commentsHeader(_, _, renderType):
            return renderType
        case let .repliesHeader(_, _, renderType):
            return renderType
        case let .topThreadInset(_, _, renderType):
            return renderType
        case let .userInfo(_, _ , _, _, renderType, _):
            return renderType
        case let .topicSeparator(_, _, renderType, _):
            return renderType
        case let .newThread(_, renderType, _):
            return renderType
        }
    }
    public var itemType: ChatItemType? {
        switch self {
        case let .MessageEntry(_, _, _, _, itemType, _, _):
            return itemType
        default:
            return nil
        }
    }
    
    public var location:MessageHistoryEntryLocation? {
        switch self {
        case let .MessageEntry(_,_,_,_,_,_,data):
            return data.location
        default:
            return nil
        }
    }
    
    public var isFakeMessage:Bool {
        switch self {
        case let .MessageEntry(_,_,_,_,_,_,data):
            return data.isFakeMessage
        case let .groupedPhotos(entries, groupInfo: _):
            return entries.first?.isFakeMessage ?? false
        case .topicSeparator:
            return true
        default:
            return false
        }
    }

    public var isBelow: Bool {
        switch self {
        case let .MessageEntry(_,_,_,_,_,_,data):
            return data.isBelow
        case let .groupedPhotos(entries, groupInfo: _):
            return entries.first?.isBelow ?? false
        default:
            return false
        }
    }

    public func additionalData(_ messageId: MessageId) -> MessageEntryAdditionalData {
        switch self {
        case let .MessageEntry(_,_,_,_,_,_,data):
            return data.additionData
        case let .groupedPhotos(entries,_):
            return entries.first(where: { $0.message?.id == messageId})?.additionalData ?? MessageEntryAdditionalData()
        case let .DateEntry(_, _, _, data):
            return data.additionData//MessageEntryAdditionalData(chatTheme: theme)
        case let .topicSeparator(_, _, _, data):
            return data.additionData
        case let .UnreadEntry(_, _, _, data):
            return data.additionData
        default:
            return MessageEntryAdditionalData()
        }
    }
    
    public var additionalData: MessageEntryAdditionalData {
        switch self {
        case let .MessageEntry(_,_,_,_,_,_,data):
            return data.additionData
        case let .groupedPhotos(entries,_):
            return entries.first?.additionalData ?? MessageEntryAdditionalData()
        case let .DateEntry(_, _, _, additionalData):
            return additionalData.additionData
        case let .topicSeparator(_, _, _, data):
            return data.additionData
        case let .UnreadEntry(_, _, _, data):
            return data.additionData
        case let .newThread(_, _, data):
            return data.additionData
        default:
            return MessageEntryAdditionalData()
        }
    }
    public var isRevealed: Bool {
        switch self {
        case let .MessageEntry(_,_,_,_,_,_,data):
            return data.additionData.isRevealed ?? false
        case let .groupedPhotos(entries,_):
            return entries.contains(where: { $0.isRevealed == true })
        default:
            return true
        }
    }
    
    public var stableId: ChatHistoryEntryId {
        switch self {
        case let .MessageEntry(message, _, _, _, _, _, _):
            return .message(message)
        case .groupedPhotos(_, let info):
            return .groupedPhotos(groupInfo: info)
        case let .DateEntry(index, _, _, _):
            return .date(index)
        case .UnreadEntry:
            return .unread
        case .bottom:
            return .bottom
        case let .empty(index, _):
            return .empty(index)
        case .commentsHeader:
            return .commentsHeader
        case .repliesHeader:
            return .repliesHeader
        case .topThreadInset:
            return .topThreadInset
        case let .topicSeparator(index, _, _, _):
            return .topicSeparator(index)
        case let .newThread(index, _, _):
            return .newThread(index)
        case .userInfo:
            return .userInfo
        }
    }
    
    public var index: MessageIndex {
        switch self {
        case let .MessageEntry(_,index, _, _, _, _,_):
            return index
        case let .groupedPhotos(entries, _):
            return entries.last!.index
        case let .UnreadEntry(index, _, _, _):
            return index
        case let .DateEntry(index, _, _, _):
            return index
        case .bottom:
            return MessageIndex.absoluteUpperBound()
        case let .commentsHeader(_, index, _):
            return index
        case let .repliesHeader(_, index, _):
            return index
        case let .topThreadInset(_, index, _):
            return index
        case let .empty(index, _):
            return index
        case let .userInfo(_, _, _, index, _, _):
            return index
        case let .topicSeparator(index, _, _, _):
            return index
        case let .newThread(index, _, _):
            return index
        }
    }
    
    
    public var scrollIndex: MessageIndex {
        switch self {
        case let .MessageEntry(message, _, _, _, _, _, _):
            return MessageIndex(message)
        case let .groupedPhotos(entries, _):
            return entries.last!.index
        case let .UnreadEntry(index, _, _, _):
            return index
        case let .DateEntry(index, _, _, _):
            return index
        case .bottom:
            return MessageIndex.absoluteUpperBound()
        case let .commentsHeader(_, index, _):
            return index
        case let .repliesHeader(_, index, _):
            return index
        case let .topThreadInset(_, index, _):
            return index
        case let .empty(index, _):
            return index
        case let .userInfo(_, _, _, index, _, _):
            return index
        case let .topicSeparator(index, _, _, _):
            return index
        case let .newThread(index, _, _):
            return index
        }
    }
    
    public func withUpdatedItemType(_ itemType: ChatItemType) -> ChatHistoryEntry {
        switch self {
        case let .MessageEntry(message, index, read, renderType, _, forwardType, data):
            return .MessageEntry(message, index, read, renderType, itemType, forwardType, data)
        default:
            return self
        }
    }
    public func withUpdatedMessageMedia(_ media: Media) -> ChatHistoryEntry {
        switch self {
        case let .MessageEntry(message, index, read, renderType, itemType, forwardType, data):
            return .MessageEntry(message.withUpdatedMedia([media]), index, read, renderType, itemType, forwardType, data)
        default:
            return self
        }
    }
}

public func isEqualMessageList(lhs:[Message], rhs:[Message]) -> Bool {
    if lhs.count != rhs.count {
        return false 
    } else {
        for (i, message) in lhs.enumerated() {
            if !isEqualMessages(message, rhs[i]) {
                return false
            }
        }
    }
    return true
}


public func ==(lhs: ChatHistoryEntry, rhs: ChatHistoryEntry) -> Bool {
    switch lhs {
    case let .MessageEntry(lMsg, lIdx, lRead, lRender, lType, lFwd, lData):
        guard case let .MessageEntry(rMsg, rIdx, rRead, rRender, rType, rFwd, rData) = rhs else {
            return false
        }
        if lRead != rRead { return false }
        if lRender != rRender { return false }
        if lIdx != rIdx { return false }
        if lFwd != rFwd { return false }
        if lType != rType { return false }
        if lData != rData { return false }
        return lMsg == rMsg
    case let .groupedPhotos(lhsEntries, lhsGroupingKey):
        guard case let .groupedPhotos(rhsEntries, rhsGroupingKey) = rhs else {
            return false
        }
        if lhsGroupingKey != rhsGroupingKey { return false }
        if lhsEntries.count != rhsEntries.count { return false }
        for i in 0 ..< lhsEntries.count {
            if lhsEntries[i] != rhsEntries[i] {
                return false
            }
        }
        return true
    case let .UnreadEntry(lIdx, lRender, lTheme, lData):
        guard case let .UnreadEntry(rIdx, rRender, rTheme, rData) = rhs else {
            return false
        }
        if lRender != rRender { return false }
        if lIdx != rIdx { return false }
        if lData != rData { return false }
        return lTheme == rTheme
    case let .DateEntry(lIdx, lRender, lTheme, lData):
        guard case let .DateEntry(rIdx, rRender, rTheme, rData) = rhs else {
            return false
        }
        if lRender != rRender { return false }
        if lIdx != rIdx { return false }
        if lData != rData { return false }
        return lTheme == rTheme
    case let .bottom(lhsTheme):
        guard case let .bottom(rhsTheme) = rhs else {
            return false
        }
        return lhsTheme == rhsTheme
    case let .empty(lhsIndex, lhsTheme):
        guard case let .empty(rhsIndex, rhsTheme) = rhs else {
            return false
        }
        if lhsIndex != rhsIndex { return false }
        return lhsTheme == rhsTheme
    case let .commentsHeader(lEmpty, lIdx, lType):
        guard case let .commentsHeader(rEmpty, rIdx, rType) = rhs else {
            return false
        }
        if lEmpty != rEmpty { return false }
        if lType != rType { return false }
        return lIdx == rIdx
    case let .repliesHeader(lEmpty, lIdx, lType):
        guard case let .repliesHeader(rEmpty, rIdx, rType) = rhs else {
            return false
        }
        if lEmpty != rEmpty { return false }
        if lType != rType { return false }
        return lIdx == rIdx
    case let .topThreadInset(lValue, lIdx, lType):
        guard case let .topThreadInset(rValue, rIdx, rType) = rhs else {
            return false
        }
        if lValue != rValue { return false }
        if lType != rType { return false }
        return lIdx == rIdx
    case let .userInfo(lValue, lPeer, lGroups, lIdx, lRender, lTheme):
        guard case let .userInfo(rValue, rPeer, rGroups, rIdx, rRender, rTheme) = rhs else {
            return false
        }
        if lRender != rRender { return false }
        if lIdx != rIdx { return false }
        if lValue != rValue { return false }
        if lGroups != rGroups { return false }
        if lPeer != rPeer { return false }
        return lTheme == rTheme
    case let .topicSeparator(lIdx, lPeer, lType, lData):
        guard case let .topicSeparator(rIdx, rPeer, rType, rData) = rhs else {
            return false
        }
        if lType != rType { return false }
        if lIdx != rIdx { return false }
        if lData != rData { return false }
        return lPeer == rPeer
    case let .newThread(lIdx, lType, lData):
        guard case let .newThread(rIdx, rType, rData) = rhs else {
            return false
        }
        if lType != rType { return false }
        if lIdx != rIdx { return false }
        return lData == rData
    }
}

public func <(lhs: ChatHistoryEntry, rhs: ChatHistoryEntry) -> Bool {
    let lhsIndex = lhs.index
    let rhsIndex = rhs.index
    if lhsIndex == rhsIndex {
        let lhsFake = lhs.isFakeMessage
        let rhsFake = rhs.isFakeMessage
        if lhsFake && !rhsFake {
            return !lhs.isBelow
        } else if !lhsFake && rhsFake {
            return rhs.isBelow
        }
        return lhs.stableId.stableIndex < rhs.stableId.stableIndex
    } else {
        return lhsIndex < rhsIndex
    }
}

private var index = 0

public func messageEntries(_ messagesEntries: [MessageHistoryEntry], location: ChatLocation? = nil, maxReadIndex:MessageIndex? = nil, includeHoles: Bool = true, dayGrouping: Bool = false, renderType: ChatItemRenderType = .list, includeBottom:Bool = false, timeDifference: TimeInterval = 0, ranks:CachedChannelAdminRanks? = nil, pollAnswersLoading: [MessageId : ChatPollStateData] = [:], threadLoading: MessageId? = nil, groupingPhotos: Bool = false, autoplayMedia: AutoplayMediaPreferences? = nil, searchState: SearchMessagesResultState? = nil, animatedEmojiStickers: [String: StickerPackItem] = [:], topFixedMessages: [Message]? = nil, customChannelDiscussionReadState: MessageId? = nil, customThreadOutgoingReadState: MessageId? = nil, addRepliesHeader: Bool = false, addWelcomeMessagesHeader: Bool = false, addTopThreadInset: CGFloat? = nil, updatingMedia: [MessageId: ChatUpdatingMessageMedia] = [:], adMessage:Message? = nil, dynamicAdMessages: [Message] = [], chatTheme: TelegramPresentationTheme = theme, reactions: AvailableReactions? = nil, transribeState: [MessageId : TranscribeAudioState] = [:], topicCreatorId: PeerId? = nil, mediaRevealed: Set<MessageId> = Set(), translate: ChatLiveTranslateContext.State? = nil, storyState: PeerExpiringStoryListContext.State? = nil, peerStoryStats: [PeerId : PeerStoryStats] = [:], cachedData: CachedPeerData? = nil, peer: Peer? = nil, holeLater: Bool = false, holeEarlier: Bool = false, recommendedChannels: RecommendedChannels? = nil, includeJoin: Bool = false, earlierId: MessageIndex? = nil, laterId: MessageIndex? = nil, automaticDownload: AutomaticMediaDownloadSettings = .defaultSettings, savedMessageTags: SavedMessageTags? = nil, contentSettings: ContentSettings? = nil, codeSyntaxData: [CodeSyntaxKey : CodeSyntaxResult] = [:], messageEffects: AvailableMessageEffects? = nil, factCheckRevealed: Set<MessageId> = Set(), solutionRevealed: Set<MessageId> = Set(), quoteRevealed: Set<QuoteMessageIndex> = Set(), detailsExpanded: Set<DetailsMessageIndex> = Set(), peerStatus: PeerStatusSettings? = nil, commonGroups: GroupsInCommonState? = nil, monoforumState: MonoforumUIState? = nil, accountPeerId: PeerId? = nil, contentConfig: ContentSettingsConfiguration = .default, walletFiatRate: WalletFiatRateProjection? = nil) -> [ChatHistoryEntry] {
    var entries: [ChatHistoryEntry] = []
    


    var groupedPhotos:[ChatHistoryEntry] = []
    var groupInfo: MessageGroupInfo?
        
    var messagesEntries = messagesEntries
    
    if let cachedData = cachedData as? CachedChannelData, cachedData.isNotAccessible {
        messagesEntries = []
    }
    
    var topMessageIndex: Int? = nil
    if let topMessages = topFixedMessages, !topMessages.isEmpty {
        messagesEntries.insert(contentsOf: topMessages.map { MessageHistoryEntry(message: $0, isRead: true, location: nil, monthLocation: nil, attributes: .init(authorIsContact: false))}, at: 0)
        topMessageIndex = topMessages.count - 1
    }
    
    if let _ = peer?.restrictionText(contentSettings) {
        return []
    }
    
    
    var joinMessage: Message?
    if let channelPeer = peer {
        if case let .peer(peerId) = location, case let cachedData = cachedData as? CachedChannelData, let invitedOn = cachedData?.invitedOn, includeJoin {
            joinMessage = Message(
                stableId: UInt32.max - 1000,
                stableVersion: 0,
                id: MessageId(peerId: peerId, namespace: Namespaces.Message.Local, id: 0),
                globallyUniqueId: nil,
                groupingKey: nil,
                groupInfo: nil,
                threadId: nil,
                timestamp: invitedOn,
                flags: [.Incoming],
                tags: [],
                globalTags: [],
                localTags: [],
                customTags: [],
                forwardInfo: nil,
                author: channelPeer,
                text: "",
                attributes: [],
                media: [TelegramMediaAction(action: .joinedByRequest)],
                peers: SimpleDictionary<PeerId, Peer>([channelPeer.id : channelPeer]),
                associatedMessages: SimpleDictionary<MessageId, Message>(),
                associatedMessageIds: [],
                associatedMedia: [:],
                associatedThreadInfo: nil,
                associatedStories: [:]
            )
        } else if let peer = channelPeer as? TelegramChannel, case .broadcast = peer.info, case .member = peer.participationStatus, includeJoin {
            joinMessage = Message(
                stableId: UInt32.max - 1000,
                stableVersion: 0,
                id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Local, id: 0),
                globallyUniqueId: nil,
                groupingKey: nil,
                groupInfo: nil,
                threadId: nil,
                timestamp: peer.creationDate,
                flags: [.Incoming],
                tags: [],
                globalTags: [],
                localTags: [], 
                customTags: [],
                forwardInfo: nil,
                author: channelPeer,
                text: "",
                attributes: [],
                media: [TelegramMediaAction(action: .joinedChannel)],
                peers: SimpleDictionary<PeerId, Peer>([channelPeer.id : channelPeer]),
                associatedMessages: SimpleDictionary<MessageId, Message>(),
                associatedMessageIds: [],
                associatedMedia: [:],
                associatedThreadInfo: nil,
                associatedStories: [:]
            )
        }
    }
    
    let isNewThread = messagesEntries.last?.message.threadId == EngineMessage.newTopicThreadId
    
    messagesEntries = messagesEntries.filter { entry in
        if isNewThread, entry.message.threadId != EngineMessage.newTopicThreadId {
            return false
        } else if topicCreatorId != nil {
            if let action = entry.message.media.first as? TelegramMediaAction {
                switch action.action {
                case .topicCreated:
                    return false
                default:
                    return true
                }
            }
        } else if let action = entry.message.media.first as? TelegramMediaAction, let replyAttribute = entry.message.replyAttribute {
            switch action.action {
            case .todoAppendTasks, .todoCompletions:
                return entry.message.associatedMessages[replyAttribute.messageId] != nil
            default:
                break
            }
        }
        return true
    }
    
    let insertPendingProccessing:(ChatHistoryEntry)->Void = { entry in
        if let message = entry.firstMessage, message.pendingProcessingAttribute != nil {
            let action = TelegramMediaAction(action: .customText(text: strings().chatVideoProccessingService, entities: [], additionalAttributes: nil))
            let service = message.withUpdatedMedia([action]).withUpdatedStableId(message.stableId + UInt32(Int32.max))
            
            
            entries.append(.MessageEntry(service, MessageIndex(service), false, renderType, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(isFakeMessage: true)))
        }
    }
    
    let insertPaidMessage:(ChatHistoryEntry)->Void = { entry in
        if let message = entry.firstMessage, let attr = message.paidStarsAttribute {
            
            let count: Int
            switch entry {
            case let .groupedPhotos(values, _):
                count = values.count
            case .MessageEntry:
                count = 1
            default:
                count = 0
            }
            
            let text: String
            let price = Int(attr.stars.value) * count
            if let author = message.author, message.peers[message.id.peerId]?.isUser == true {
                if count == 1 {
                    if author.id == message.id.peerId {
                        text = strings().notificationPaidMessage(author.compactDisplayTitle, strings().starListItemCountOther(Int(price)))
                    } else {
                        text = strings().notificationPaidMessageYou(strings().starListItemCountOther(Int(price)))
                    }
                } else {
                    let messageText = strings().notificationPaidMessagesOther(count)
                    if author.id == message.id.peerId {
                        text = strings().notificationPaidMessageMany(author.compactDisplayTitle, strings().starListItemCountOther(Int(price)), messageText)
                    } else {
                        text = strings().notificationPaidMessageYouMany(strings().starListItemCountOther(Int(price)), messageText)
                    }
                }
            } else {
                text = ""
            }
            
            if !text.isEmpty {
                let action = TelegramMediaAction(action: .customText(text: text, entities: [], additionalAttributes: nil))
                let service = message.withUpdatedMedia([action]).withUpdatedStableId(message.stableId + UInt32(Int32.max))
                entries.append(.MessageEntry(service, MessageIndex(service), false, renderType, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(isFakeMessage: true)))
            }
        }
    }

    let insertDiceGameOutcome:(ChatHistoryEntry)->Void = { entry in
        if let message = entry.firstMessage {

            for media in message.media {
                if let dice = media as? TelegramMediaDice, let gameOutcome = dice.gameOutcome {
                    if gameOutcome.tonAmount > 0 {
                        let tonAmount = Double(gameOutcome.tonAmount) / 1_000_000_000
                        let text: String
                        if let author = message.author, author.id != accountPeerId {
                            text = strings().chatHistoryDiceWonOther(author.compactDisplayTitle, String(format: "%.2f", tonAmount))
                        } else {
                            text = strings().chatHistoryDiceWonYou(String(format: "%.2f", tonAmount))
                        }
                        let action = TelegramMediaAction(action: .customText(text: text, entities: [], additionalAttributes: nil))
                        let service = message.withUpdatedMedia([action]).withUpdatedStableId(message.stableId + UInt32(Int32.max) - 1)
                        let serviceEntry: ChatHistoryEntry = .MessageEntry(service, MessageIndex(service), false, renderType, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(isFakeMessage: true, isBelow: true))
                        entries.append(serviceEntry)
                    }
                    break
                }
            }
        }
    }

    let insertTopicSeparator:(ChatHistoryEntry, MessageHistoryEntry?, MessageHistoryEntry?)->Void = { entry, prev, next in
        if let message = entry.firstMessage, let _ = monoforumState {
            let nextId = next?.message.threadId
            if let nextId, nextId != message.threadId, location?.threadId == nil {
                let nextPeerId = PeerId(nextId)
                let peer = next?.message.peers[nextPeerId]
                if let next {
                    let type: ChatHistoryEntry.TopicType?
                    if let peer {
                        type = .peer(.init(peer))
                    } else if let info = next.message.associatedThreadInfo {
                        type = .topic(nextId, info)
                    } else {
                        type = nil
                    }
                    if let type {
                        entries.append(.topicSeparator(MessageIndex(next.message), type, renderType, ChatHistoryEntryData(nil, entry.additionalData)))
                    }
                }
            }
        }
    }
    
    let insertSuggestPostHeader:(ChatHistoryEntry)->Void = { entry in
        if let message = entry.firstMessage, let attr = message.suggestPostAttribute {
            
            let action = TelegramMediaAction(action: .customText(text: "post_suggest:\(attr.amount?.amount.value ?? 0):\(attr.timestamp ?? 0):\(attr.amount?.currency.stringValue ?? XTR)", entities: [], additionalAttributes: nil))
            let service = message.withUpdatedMedia([action]).withUpdatedStableId(message.stableId + UInt32(Int32.max)).withUpdatedTimestamp(message.timestamp - 1)
            entries.append(.MessageEntry(service, MessageIndex(service), false, renderType, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, entry.additionalData, isFakeMessage: true)))

        }
    }
    
    
    let sharedReactionsProjection: MessageEntryAdditionalData.ReactionsProjection? = .init(from: reactions)
    let sharedCachedDataProjection: MessageEntryAdditionalData.CachedDataProjection? = .init(from: cachedData)
    let sharedAutoDownloadProjection = MessageEntryAdditionalData.AutoDownloadProjection(automaticDownload)

    var codeSyntaxByMessage: [MessageId: [CodeSyntaxKey: CodeSyntaxResult]] = [:]
    if !codeSyntaxData.isEmpty {
        for (key, value) in codeSyntaxData {
            codeSyntaxByMessage[key.messageId, default: [:]][key] = value
        }
    }

    var quoteRevealedByMessage: [MessageId: Set<Int>] = [:]
    if !quoteRevealed.isEmpty {
        for q in quoteRevealed {
            quoteRevealedByMessage[q.messageId, default: []].insert(q.index)
        }
    }
    let emptyQuoteRevealed: Set<Int> = []

    var detailsExpandedByMessage: [MessageId: Set<Int>] = [:]
    if !detailsExpanded.isEmpty {
        for d in detailsExpanded {
            detailsExpandedByMessage[d.messageId, default: []].insert(d.index)
        }
    }
    let emptyDetailsExpanded: Set<Int> = []

    let translateCanTranslate = translate?.canTranslate ?? false
    let translateTranslate = translate?.translate ?? false
    let translateTo = translate?.to
    let canHighlightLinksDefault: Bool = {
        if peer?.isUser == false {
            return true
        }
        return peerStatus?.contains(.canReport) == true ? false : true
    }()

    var hasIncomingAfter = [Bool](repeating: false, count: messagesEntries.count)
    var incomingSeen = false
    for index in stride(from: messagesEntries.count - 1, through: 0, by: -1) {
        hasIncomingAfter[index] = incomingSeen
        if messagesEntries[index].message.flags.contains(.Incoming) {
            incomingSeen = true
        }
    }

    for (i, entry) in messagesEntries.enumerated() {
        var message = entry.message.withAppliedEphemeralReplacementMessage()
        
    
        if message.media.isEmpty {
            if message.text.length <= 7 {
                
                let customRange: [(NSRange, Int64)] = message.textEntities?.entities.compactMap { entity in
                    if case let .CustomEmoji(_, fileId) = entity.type {
                        let range = NSMakeRange(entity.range.lowerBound, entity.range.upperBound - entity.range.lowerBound)
                        return (range, fileId)
                    }
                    return nil
                } ?? []
                
                
                let original = message.text.withoutColorizer
                
                let fullCustom = customRange.first(where: { $0.0.intersection(NSMakeRange(0, message.text.length)) != nil })
                
                if let custom = fullCustom, original.isSingleEmoji {
                    let mediaId = MediaId(namespace: Namespaces.Media.CloudFile, id: custom.1)

                    if let file = message.associatedMedia[mediaId] as? TelegramMediaFile {
                        var file = file
                        var attributes = file.attributes
                        attributes.append(.FileName(fileName: "telegram-animoji.tgs"))
                        attributes.append(.Sticker(displayText: original, packReference: nil, maskData: nil))
                        
                        file = file.withUpdatedAttributes(attributes)
                        message = message.withUpdatedMedia([file])
                            .withUpdatedText(original)
                    }
                }
                
                if fullCustom == nil, !animatedEmojiStickers.isEmpty, original.containsEmoji, let item = animatedEmojiStickers[original.withoutColorizer.emojiUnmodified], original.isSingleEmoji {
                    var file = item.file._parse()
                    var attributes = file.attributes
                    attributes.removeAll { attr in
                        if case .FileName = attr {
                            return true
                        } else {
                            return false
                        }
                    }
                    attributes = attributes.map { attribute -> TelegramMediaFileAttribute in
                        switch attribute {
                        case let .Sticker(_, packReference, maskData):
                            return .Sticker(displayText: original, packReference: packReference, maskData: maskData)
                        default:
                            return attribute
                        }
                    }
                    var disableStickers: Bool = false
                    if let peer = coreMessageMainPeer(message) as? TelegramChannel {
                        if permissionText(from: peer, for: [.banSendGifs, .banSendStickers]) != nil {
                            disableStickers = true
                        }
                    }
                    if !disableStickers {
                        attributes.append(.FileName(fileName: "telegram-animoji.tgs"))
                        file = file.withUpdatedAttributes(attributes)
                        message = message.withUpdatedMedia([file])
                    }
                }
            }
        }
        
        if let updating = updatingMedia[message.id] {
            message = message.withUpdatedText(updating.text)
            var attributes = message.attributes
            if let entities = updating.entities, let index = attributes.firstIndex(where: { $0 is TextEntitiesMessageAttribute }) {
                attributes[index] = entities
            }
            message = message.withUpdatedAttributes(attributes)
            inner: switch updating.media {
            case let .update(media):
                message = message.withUpdatedMedia([media.media])
            default:
                break inner
            }
        }
        
        
        var disableEntry = false
        if let action = message.extendedMedia as? TelegramMediaAction {
            switch action.action {
            case .historyCleared:
                disableEntry = true
            case .groupMigratedToChannel:
                disableEntry = true
            case .channelMigratedFromGroup:
                disableEntry = true
            case .peerJoined:
                disableEntry = false
            default:
                break
            }
        }
        
        if disableEntry {
            continue
        }
        
        
        
        var prev:MessageHistoryEntry? = nil
        var next:MessageHistoryEntry? = nil
        
        if i > 0 {
            loop: for k in stride(from: i - 1, to: -1, by: -1) {
                let current = messagesEntries[k]
                if let groupInfo = message.groupInfo {
                    if current.message.groupInfo == groupInfo {
                        continue loop
                    } else {
                        prev = current
                        break loop
                    }
                } else {
                    prev = current
                    break loop
                }
            }
            
        }
        if i < messagesEntries.count - 1 {
            loop: for k in i + 1 ..< messagesEntries.count {
                let current = messagesEntries[k]
                if let groupInfo = message.groupInfo {
                    if current.message.groupInfo == groupInfo {
                        continue loop
                    } else {
                        next = current
                        break loop
                    }
                } else {
                    next = current
                    break loop
                }
            }
        }
        
        
        let rawRank = message.author.flatMap { ranks?.ranks[$0.id] }
        var rank:String? = nil
        var rankType: AdminBadgeType = .none
        if let rawRank = rawRank {
            switch rawRank {
            case let .admin(customTitle):
                rank = customTitle ?? strings().chatAdminBadge
                rankType = .admin
            case let .owner(customTitle):
                rank = customTitle ?? strings().chatOwnerBadge
                rankType = .owner
            case let .member(customTitle):
                rank = customTitle
                rankType = .none
            }
        } else if let topicCreatorId = topicCreatorId {
            if message.author?.id == topicCreatorId {
                rank = strings().chatTopicBadge
                rankType = .admin
            }
        }
        if rank == nil, let rankAttr = message.attributes.first(where: { $0 is ParticipantRankMessageAttribute }) as? ParticipantRankMessageAttribute, !rankAttr.rank.isEmpty {
            rank = rankAttr.rank

        }

        var itemType:ChatItemType = .Full(rank: rank, rankType: rankType, header: .normal)
        var fwdType:ForwardItemType? = nil
        
        if message.itHasRestrictedContent, message.restrictedText(contentSettings, contentConfig: contentConfig) != nil {
            message = message.withUpdatedMedia([]).withUpdatedText(" ")
        }
                
        if renderType == .list {
            if let prev = prev {
                var actionShortAccess: Bool = true
                if let action = prev.message.extendedMedia as? TelegramMediaAction {
                    switch action.action {
                    case .phoneCall:
                        actionShortAccess = true
                    default:
                        actionShortAccess = false
                    }
                }
                
                if message.author?.id == prev.message.author?.id, (message.timestamp - prev.message.timestamp) < simpleDif, actionShortAccess, let peer = message.peers[message.id.peerId] {
                    if let peer = peer as? TelegramChannel, case .broadcast(_) = peer.info {
                        itemType = .Full(rank: rank, rankType: rankType, header: .normal)
                    } else {
                        var canShort:Bool = (message.media.isEmpty || message.anyMedia?.isInteractiveMedia == false) || message.forwardInfo == nil || renderType == .list
                        
                        if message.guestChatAttribute != nil {
                            canShort = false
                        }
                        
//                        attrsLoop: for attr in message.attributes {
//                            let contains = allowAttributes.contains(where: { type(of: attr) == $0 })
//                            if !contains {
//                                canShort = false
//                                break attrsLoop
//                            }
//                        }
                        if message.threadId != prev.message.threadId {
                           // canShort = false
                        }
                        itemType = !canShort ? .Full(rank: rank, rankType: rankType, header: .normal) : .Short(rank: rank, rankType: rankType, header: .normal)
                        
                    }
                } else {
                    itemType = .Full(rank: rank, rankType: rankType, header: .normal)
                }
            } else {
                itemType = .Full(rank: rank, rankType: rankType, header: .normal)
            }
        } else {
            
            let isSameGroup:(Message, Message) -> Bool = { upper, lower in
                guard let accountPeerId else {
                    return false
                }
                let isWelcome = Namespaces.Message.allWelcomeMessages.contains(upper.id.namespace) && Namespaces.Message.allWelcomeMessages.contains(lower.id.namespace)
                if !isWelcome && chatDateId(for: upper.timestamp) != chatDateId(for: lower.timestamp) {
                    return false
                }
                if let maxReadIndex = maxReadIndex, maxReadIndex >= upper.index && maxReadIndex < lower.index {
                    return false
                }
                if let peer = upper.peers[upper.id.peerId], ChatHistoryModelHooks.shared.peerIsForum(peer), upper.threadId != lower.threadId {
                    return false
                }
                return shouldMergeBubbles(upper: upper, lower: lower, accountPeerId: accountPeerId)
            }

            if let next = next {
                if isSameGroup(message, next.message) {
                    if let prev = prev {
                        itemType = .Short(rank: rank, rankType: rankType, header: isSameGroup(prev.message, message) ? .short : .normal)
                    } else {
                        itemType = .Short(rank: rank, rankType: rankType, header: .normal)
                    }
                } else {
                    if let prev = prev {
                        let shouldGroup = isSameGroup(prev.message, message)
                        itemType = .Full(rank: rank, rankType: rankType, header: shouldGroup ? .short : .normal)
                    } else {
                        itemType = .Full(rank: rank, rankType: rankType, header:  .normal)
                    }
                }
            } else {
                if let prev = prev {
                    let shouldGroup = isSameGroup(prev.message, message)
                    itemType = .Full(rank: rank, rankType: rankType, header: shouldGroup ? .short : .normal)
                } else {
                    itemType = .Full(rank: rank, rankType: rankType, header: .normal)
                }
            }
        }
        
        
        
        
        if message.forwardInfo != nil, !message.isImported {
            if case .Short = itemType {
                if let prev = prev {
                    if prev.message.forwardInfo != nil, message.timestamp - prev.message.timestamp < simpleDif  {
                        fwdType = .Inside
                        if let next = next  {
                            if message.author?.id != next.message.author?.id || next.message.timestamp - message.timestamp > simpleDif || next.message.forwardInfo == nil {
                                fwdType = .Bottom
                            }
                        } else {
                            fwdType = .Bottom
                        }
                    } else {
                        fwdType = .ShortHeader
                    }
                }
            } else {
                fwdType = .ShortHeader
            }
        }
        
        if let forwardType = fwdType, forwardType == .ShortHeader || forwardType == .FullHeader, renderType != .bubble {
            itemType = .Full(rank: rank, rankType: rankType, header: .normal)
            if forwardType == .ShortHeader {
                if let next = next  {
                    if next.message.forwardInfo != nil && (message.author?.id == next.message.author?.id || next.message.timestamp - message.timestamp < simpleDif) {
                        fwdType = .FullHeader
                    }
                    
                }
            }
        }
        
        let additionalData: MessageEntryAdditionalData
        var highlightFoundText: HighlightFoundText? = nil
        
        
        if let searchState = searchState, !message.text.isEmpty, searchState.containsMessage(message) {
            highlightFoundText = HighlightFoundText(query: searchState.query, isMessage: true)
        }
        
        let pollData = pollAnswersLoading[message.id] ?? ChatPollStateData()
        
        var messageTranslate: ChatLiveTranslateContext.State.Result?
        var replyTranslate: ChatLiveTranslateContext.State.Result?
        if let translate = translate, let translateTo = translateTo {
            messageTranslate = translate.result[.Key(id: message.id, toLang: translateTo)]
            if let reply = message.replyAttribute, let replyMessage = message.associatedMessages[reply.messageId] {
                replyTranslate = translate.result[.init(id: replyMessage.id, toLang: translateTo)]
            } else {
                replyTranslate = nil
            }
            if translateCanTranslate, translateTranslate {
                if let _ = message.translationAttribute(toLang: translateTo) {
                    messageTranslate = .complete(toLang: translateTo)
                }
                if let reply = message.replyAttribute, let replyMessage = message.associatedMessages[reply.messageId] {
                    if let _ = replyMessage.translationAttribute(toLang: translateTo) {
                        replyTranslate = .complete(toLang: translateTo)
                    }
                }
            }
        }

        let messageEffect: AvailableMessageEffects.MessageEffect?
        if let effectAttribute = message.effectAttribute {
            messageEffect = messageEffects?.messageEffects.first(where: { $0.id == effectAttribute.id })
        } else {
            messageEffect = nil
        }

        let entryQuoteRevealed = quoteRevealedByMessage[message.id] ?? emptyQuoteRevealed
        let entryDetailsExpanded = detailsExpandedByMessage[message.id] ?? emptyDetailsExpanded

        var transcriptionTranslate: ChatLiveTranslateContext.State.TranscriptionResult?
        if let translate = translate, let translateTo = translateTo, translateCanTranslate, translateTranslate {
            transcriptionTranslate = translate.transcriptionResult[.Key(id: message.id, toLang: translateTo)]
        }

        let summarize = translate?.summarizeResult[.Key(id: message.id)]

        let entryCodeSyntax = codeSyntaxByMessage[message.id] ?? [:]

        let entryWalletFiatRate: WalletFiatRateProjection?
        if let walletFiatRate, let action = message.extendedMedia as? TelegramMediaAction, case .gramTransfer = action.action {
            entryWalletFiatRate = walletFiatRate
        } else {
            entryWalletFiatRate = nil
        }

        additionalData = MessageEntryAdditionalData(pollStateData: pollData, highlightFoundText: highlightFoundText, isThreadLoading: threadLoading == message.id, updatingMedia: updatingMedia[message.id], chatTheme: chatTheme, reactions: sharedReactionsProjection, transribeState: transribeState[message.id], transcriptionTranslate: transcriptionTranslate, isRevealed: mediaRevealed.contains(message.id), translate: messageTranslate, replyTranslate: replyTranslate, storyReadMaxId: (message.media.first is TelegramMediaStory) ? storyState?.maxReadId : nil, authorStoryStats: message.author.flatMap { peerStoryStats[$0.id] }, cachedData: sharedCachedDataProjection, automaticDownload: sharedAutoDownloadProjection, savedMessageTags: savedMessageTags, codeSyntaxData: entryCodeSyntax, messageEffect: messageEffect, factCheckRevealed: factCheckRevealed.contains(message.id), solutionRevealed: solutionRevealed.contains(message.id), quoteRevealed: entryQuoteRevealed, detailsExpanded: entryDetailsExpanded, monoforumState: monoforumState, canHighlightLinks: canHighlightLinksDefault, summarize: summarize, walletFiatRate: entryWalletFiatRate)
        let data = ChatHistoryEntryData(entry.location, additionalData, autoplayMedia)
        
       
        
        let timestamp = Int32(min(TimeInterval(message.timestamp) - timeDifference, TimeInterval(Int32.max)))
        
        
        var isRead = entry.isRead
        if !message.flags.contains(.Incoming) {
            if hasIncomingAfter[i] {
                isRead = true
            }
        }
        
        if let customThreadOutgoingReadState = customThreadOutgoingReadState {
            isRead = customThreadOutgoingReadState >= message.id
        }
        
        if let customChannelDiscussionReadState = customChannelDiscussionReadState {
            attibuteLoop: for i in 0 ..< message.attributes.count {
                if let attribute = message.attributes[i] as? ReplyThreadMessageAttribute {
                    if let maxReadMessageId = attribute.maxReadMessageId {
                        if maxReadMessageId < customChannelDiscussionReadState.id {
                            var attributes = message.attributes
                            attributes[i] = ReplyThreadMessageAttribute(count: attribute.count, latestUsers: attribute.latestUsers, commentsPeerId: attribute.commentsPeerId, maxMessageId: attribute.maxMessageId, maxReadMessageId: customChannelDiscussionReadState.id)
                            message = message.withUpdatedAttributes(attributes)
                        }
                    }
                    break attibuteLoop
                }
            }
        }

        
 
        let entry: ChatHistoryEntry = .MessageEntry(message, MessageIndex(id: message.id, timestamp: timestamp), isRead, renderType, itemType, fwdType, data)
        
        if let key = message.groupInfo, groupingPhotos, message.id.peerId.namespace == Namespaces.Peer.SecretChat || !message.containsSecretMedia, !message.media.isEmpty {
            if groupInfo == nil {
                groupInfo = key
                groupedPhotos.append(entry.withUpdatedItemType(itemType))
            } else if groupInfo == key {
                groupedPhotos.append(entry.withUpdatedItemType(itemType))
            } else {
                if groupedPhotos.count > 0 {
                    if let groupInfo = groupInfo {
                        if groupedPhotos.count > 1 {
                            let entry: ChatHistoryEntry = .groupedPhotos(groupedPhotos, groupInfo: groupInfo)
                            entries.append(entry)
                            insertPendingProccessing(entry)
                            insertPaidMessage(entry)
                            insertDiceGameOutcome(entry)
                            insertTopicSeparator(entry, prev, next)
                            insertSuggestPostHeader(entry)
                        } else if let single = groupedPhotos.first {
                            entries.append(single)
                            insertPendingProccessing(single)
                            insertPaidMessage(single)
                            insertDiceGameOutcome(single)
                            insertTopicSeparator(single, prev, next)
                            insertSuggestPostHeader(single)
                        }
                    }
                    groupedPhotos.removeAll()
                }

                groupInfo = key
                groupedPhotos.append(entry.withUpdatedItemType(itemType))
            }
        } else {
            entries.append(entry)
            insertPendingProccessing(entry)
            insertPaidMessage(entry)
            insertDiceGameOutcome(entry)
            insertSuggestPostHeader(entry)
            insertTopicSeparator(entry, prev, next)
        }
        
        prev = nil
        next = nil
        
        if i > 0 {
            prev = messagesEntries[i - 1]
        }
        if i < messagesEntries.count - 1 {
            next = messagesEntries[i + 1]
        }
        
        if prev == nil && dayGrouping {
            let timestamp = Int32(min(TimeInterval(message.timestamp) - timeDifference, TimeInterval(Int32.max)))

            let dateId = chatDateId(for: timestamp)
            let index = MessageIndex(id: MessageId(peerId: message.id.peerId, namespace: Namespaces.Message.Local, id: 0), timestamp: Int32(dateId))
            entries.append(.DateEntry(index, renderType, chatTheme, .init(nil, additionalData)))
        }
        
       
        
        if let next = next, dayGrouping {
            let timestamp = Int32(min(TimeInterval(message.timestamp) - timeDifference, TimeInterval(Int32.max)))
            let nextTimestamp = Int32(min(TimeInterval(next.message.timestamp) - timeDifference, TimeInterval(Int32.max)))

            let dateId = chatDateId(for: timestamp)
            let nextDateId = chatDateId(for: nextTimestamp)
            
            
            if dateId != nextDateId {
                let index = MessageIndex(id: MessageId(peerId: message.id.peerId, namespace: Namespaces.Message.Local, id: INT_MAX), timestamp: Int32(nextDateId))
                entries.append(.DateEntry(index, renderType, chatTheme, .init(nil, additionalData)))
            }
        }
        if let topMessageIndex = topMessageIndex, topMessageIndex == i {
            let timestamp = Int32(min(TimeInterval(message.timestamp) - timeDifference, TimeInterval(Int32.max)))

            entries.append(.commentsHeader(i == messagesEntries.count - 1, MessageIndex(id: message.id, timestamp: timestamp).peerLocalSuccessor(), renderType))
        }
    }
    
    if let lowerTimestamp = messagesEntries.last?.message.timestamp, let upperTimestamp = messagesEntries.first?.message.timestamp {
        if let joinMessage = joinMessage {
            var insertAtPosition: Int?
            if joinMessage.timestamp >= lowerTimestamp && laterId == nil {
                insertAtPosition = entries.count
            } else if joinMessage.timestamp < lowerTimestamp && joinMessage.timestamp > upperTimestamp {
                for i in 0 ..< entries.count {
                    if let timestamp = entries[i].message?.timestamp, timestamp > joinMessage.timestamp {
                        insertAtPosition = i
                        break
                    }
                }
            }
            if insertAtPosition != nil {
                entries.append(.MessageEntry(joinMessage, MessageIndex(joinMessage), true, renderType, .Full(rank: nil, rankType: .none, header: .normal), nil, .init(nil, .init(recommendedChannels: recommendedChannels), autoplayMedia)))
            }
        }
    }

    var hasUnread = false
    if let maxReadIndex = maxReadIndex {
        let timestamp = Int32(min(TimeInterval(maxReadIndex.timestamp) - timeDifference, TimeInterval(Int32.max)))
        entries.append(.UnreadEntry(maxReadIndex.withUpdatedTimestamp(timestamp), renderType, chatTheme, .init(nil, .init(chatTheme: chatTheme, monoforumState: monoforumState))))
        hasUnread = true
    }
    
    
    
    if includeBottom, laterId == nil {
        entries.append(.bottom(chatTheme))
    }
    
    if !groupedPhotos.isEmpty, let key = groupInfo {
        if groupedPhotos.count == 1 {
            entries.append(groupedPhotos[0])
            insertPendingProccessing(groupedPhotos[0])
            insertPaidMessage(groupedPhotos[0])
            insertDiceGameOutcome(groupedPhotos[0])
            insertSuggestPostHeader(groupedPhotos[0])
            insertTopicSeparator(groupedPhotos[0], messagesEntries.count >= 2 ? messagesEntries[messagesEntries.count - 2] : nil, nil)
        } else {
            let entry: ChatHistoryEntry = .groupedPhotos(groupedPhotos, groupInfo: key)
            entries.append(entry)
            insertPendingProccessing(entry)
            insertPaidMessage(entry)
            insertDiceGameOutcome(entry)
            insertSuggestPostHeader(entry)
            insertTopicSeparator(entry, messagesEntries.count >= 2 ? messagesEntries[messagesEntries.count - 2] : nil, nil)
        }
    }
    
    if addRepliesHeader {
        entries.insert(.repliesHeader(true, MessageIndex.absoluteLowerBound().globalSuccessor(), renderType), at: 0)
    }

    if addWelcomeMessagesHeader, let peer = peer {
        let texts = [strings().welcomeMessageServiceInfo, strings().welcomeMessageServiceDelete]
        for (i, text) in texts.enumerated().reversed() {
            let action = TelegramMediaAction(action: .customText(text: text, entities: [], additionalAttributes: nil))
            let message = Message(
                stableId: UInt32.max - 2000 - UInt32(i),
                stableVersion: 0,
                id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Local, id: 2000 + Int32(i)),
                globallyUniqueId: nil,
                groupingKey: nil,
                groupInfo: nil,
                threadId: nil,
                timestamp: 1,
                flags: [.Incoming],
                tags: [],
                globalTags: [],
                localTags: [],
                customTags: [],
                forwardInfo: nil,
                author: peer,
                text: "",
                attributes: [],
                media: [action],
                peers: SimpleDictionary<PeerId, Peer>([peer.id : peer]),
                associatedMessages: SimpleDictionary<MessageId, Message>(),
                associatedMessageIds: [],
                associatedMedia: [:],
                associatedThreadInfo: nil,
                associatedStories: [:]
            )
            entries.insert(.MessageEntry(message, MessageIndex(message), true, renderType, .Full(rank: nil, rankType: .none, header: .normal), nil, .init(nil, .init(), autoplayMedia)), at: 0)
        }
    }
    if let addTopThreadInset = addTopThreadInset {
        entries.insert(.topThreadInset(addTopThreadInset, MessageIndex.absoluteLowerBound(), renderType), at: 0)
    }
    
    if let monoforumState, monoforumState == .horizontal {
        entries.insert(.topThreadInset(40, MessageIndex.absoluteLowerBound(), renderType), at: 0)
    }

  
    if !dynamicAdMessages.isEmpty {
        for message in dynamicAdMessages {
            entries.append(.MessageEntry(message, MessageIndex(message), true, renderType, .Full(rank: nil, rankType: .none, header: .normal), nil, .init(nil, .init(), autoplayMedia)))
        }
    }
    
    if let peerStatus, peerStatus.phoneCountry != nil, let message = messagesEntries.first, let peer = message.message.peers[message.message.id.peerId] {
        entries.append(.userInfo(peerStatus, .init(peer), commonGroups, MessageIndex.absoluteLowerBound(), renderType, chatTheme))
    }

    
    if let lastMessage = entries.last(where: { $0.message != nil })?.message {
        var nextAdMessageId: Int32 = 1
        
        let fixedAdMessageStableId: UInt32 = UInt32.max - 5000

        if adMessage != nil {
            entries.append(.empty(MessageIndex(id: .init(peerId: lastMessage.id.peerId, namespace: lastMessage.id.namespace, id: Int32.max - 150), timestamp: Int32.max - 150), chatTheme))
            nextAdMessageId += 1
        }
        if let message = adMessage {
            let updatedMessage = Message(
                stableId: fixedAdMessageStableId,
                stableVersion: message.stableVersion,
                id: MessageId(peerId: message.id.peerId, namespace: message.id.namespace, id: nextAdMessageId),
                globallyUniqueId: nil,
                groupingKey: nil,
                groupInfo: nil,
                threadId: nil,
                timestamp: (Int32.max - 100) + nextAdMessageId,
                flags: message.flags,
                tags: message.tags,
                globalTags: message.globalTags,
                localTags: message.localTags,
                customTags: message.customTags,
                forwardInfo: message.forwardInfo,
                author: message.author,
                text: message.text,
                attributes: message.attributes,
                media: message.media,
                peers: message.peers,
                associatedMessages: message.associatedMessages,
                associatedMessageIds: message.associatedMessageIds,
                associatedMedia: [:],
                associatedThreadInfo: message.associatedThreadInfo,
                associatedStories: message.associatedStories
            )
            nextAdMessageId += 1
            
            let timestamp = Int32(min(TimeInterval(updatedMessage.timestamp) - timeDifference, TimeInterval(Int32.max)))
            entries.append(.MessageEntry(updatedMessage, MessageIndex(updatedMessage.withUpdatedTimestamp(timestamp)), true, renderType, .Full(rank: nil, rankType: .none, header: .normal), nil, .init(nil, .init(), autoplayMedia)))
            
        }
    }
    
    if let botInfo = peer?.botInfo, botInfo.flags.contains(.hasForum), let location, !isNewThread, botInfo.flags.contains(.forumManagedByUser) {
        if location.threadId == nil {
            entries.append(.newThread(MessageIndex.absoluteUpperBound(), renderType, .init(nil, .init(monoforumState: monoforumState))))
        }
    }

    var sorted = entries.sorted()


    if hasUnread, sorted.count >= 2 {
        if  case .UnreadEntry = sorted[sorted.count - 2] {
            sorted.remove(at: sorted.count - 2)
        }
    }
    

    return sorted
}

