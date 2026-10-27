import Cocoa
import TGUIKit
import TelegramCore
import ObjcUtils
import Postbox
import SwiftSignalKit
import DateUtils
import InAppSettings
import ColorPalette
import AlertsUI
import BoostUI
import ChatHistoryModel
import GeneralRows
import InputTextView
import LocalAnimations
import Localization
import MessageUtils
import PremiumStatusUI
import PremiumUI
import StarsUI
import Strings
import TelegramContext
import TelegramMediaUtils
import TelegramTheme
import TelegramUtils
import InlineStickerLayer

private let forwardKeyString = ":##"

public struct ChatFloatingPhoto {
    public var point: NSPoint
    public var items:[ChatRowItem]
    public var photoView: NSView?
    public var isAnchor: Bool
    var node: ChatFloatingAvatarNode? = nil
    public init(point: NSPoint, items: [ChatRowItem], photoView: NSView?, isAnchor: Bool) {
        self.point = point
        self.items = items
        self.photoView = photoView
        self.isAnchor = isAnchor
    }
}





public final class ChatHistoryBottomRowItem: GeneralRowItem {
    public static let minimumInputOverlayHeight: CGFloat = 40
    public static let messageInputGap: CGFloat = 20

    public static let compactBottomInset: CGFloat = 12

    public static func bottomInset(showsInput: Bool, inputOverlayHeight: CGFloat) -> CGFloat {
        guard showsInput else {
            return compactBottomInset
        }
        return max(minimumInputOverlayHeight, max(0, inputOverlayHeight)) + messageInputGap
    }

    private let bottomInset: Atomic<CGFloat>

    public init(_ initialSize: NSSize, stableId: AnyHashable, bottomInset: Atomic<CGFloat>) {
        self.bottomInset = bottomInset
        super.init(initialSize, stableId: stableId, backgroundColor: .clear, ignoreAtInitialization: true)
    }

    public override var height: CGFloat {
        return bottomInset.with { $0 }
    }

    public override var accessibilityIsSpacer: Bool {
        return true
    }
}



public class ChatRowItem: TableRowItem {
    
    public override var canBeAnchor: Bool {
        return !self.entry.isFakeMessage
    }
    
    public class RowCaption {
        public var id: UInt32
        public var offset: NSPoint
        public var layout: FoldingTextLayout
        public var isLoading: Bool
        public var message: Message
        public var contentInset: CGFloat
        public init(message: Message, id: UInt32, offset: NSPoint, layout: FoldingTextLayout, isLoading: Bool, contentInset: CGFloat) {
            self.id = id
            self.message = message
            self.offset = offset
            self.layout = layout
            self.isLoading = isLoading
            self.contentInset = contentInset
        }
        
        public var invertedSize: CGFloat {
            return offset.y + layout.size.height + contentInset * 2
        }
        public var invertedOffset: CGFloat {
            return offset.y + layout.size.height + contentInset
        }
        
        public func isSame(to other: RowCaption) -> Bool {
            return self.message.id == other.message.id && self.id == other.id && self.layout.string == other.layout.string
        }
        
        public func withUpdatedOffset(_ offset: CGFloat) -> RowCaption {
            return RowCaption(message: self.message, id: self.id, offset: .init(x: 0, y: offset), layout: self.layout, isLoading: self.isLoading, contentInset: self.contentInset)
        }
    }
    
    public var invertMedia: Bool {
        if let media = self.message?.media.first as? TelegramMediaFile, !media.isInteractiveMedia {
            return false
        } else {
            return (self.message?.invertMedia ?? false) && !captionLayouts.isEmpty
        }
    }
    
    public var isAdRow: Bool {
        return message?.adAttribute != nil
    }
    
    public private(set) var chatInteraction:ChatInteraction
    
    let context: any AccountContextProtocol
    public var itemContext: any AccountContextProtocol {
        return context
    }
    public private(set) var peer:Peer?
    public private(set) var entry:ChatHistoryEntry
    public private(set) var message:Message?
    
    public var monoforumState: MonoforumUIState? {
        return entry.additionalData.monoforumState
    }
    
    public var firstMessage: Message? {
        return messages.first
    }
    public var lastMessage: Message? {
        return messages.last
    }
    
    public var messages: [Message] {
        if let message = message {
            return [message]
        }
        return []
    }
    
    public private(set) var itemType:ChatItemType = .Full(rank: nil, rankType: .none, header: .normal)
    
    //right view
    public private(set) var date:TextViewLayout?
    public private(set) var channelViews:TextViewLayout?
    public private(set) var replyCount:TextViewLayout?
    public private(set) var postAuthor:TextViewLayout?
    public private(set) var editedLabel:TextViewLayout?
    public private(set) var paidMessage:TextViewLayout?
    public private(set) var diceStake:TextViewLayout?

    public private(set) var messageEffect: AvailableMessageEffects.MessageEffect?
   
    public private(set) var fullDate:String?
    public private(set) var nameHide: String?
    
    public var nameColor: NSColor {
        if let peer = self.peer, let message = message {
            var nameColor:NSColor = presentation.chat.linkColor(isIncoming, entry.renderType == .bubble)
            
            if let _nameColor = peer.namePeerColor {
                nameColor = context.peerNameColors.get(_nameColor).main
            }
  
            if message.forwardInfo?.psaType != nil, entry.renderType == .list {
                nameColor = presentation.colors.greenUI
            }
            
            if message.adAttribute != nil, let author = message.author {
                nameColor = context.peerNameColors.get(author.namePeerColor ?? .blue).main
            }
            return nameColor
        }
        return presentation.chat.linkColor(isIncoming, entry.renderType == .bubble)
    }
    
    public var forwardNameColor: NSColor {
        if let peer = self.peer, let message = message {
            var nameColor:NSColor = presentation.chat.linkColor(isIncoming, entry.renderType == .bubble)
            
            if let _nameColor = peer.namePeerColor {
                nameColor = context.peerNameColors.get(_nameColor).main
            }
  
            if message.forwardInfo?.psaType != nil, entry.renderType == .list {
                nameColor = presentation.colors.greenUI
            }
            
            if message.adAttribute != nil, let author = message.author {
                nameColor = context.peerNameColors.get(author.namePeerColor ?? .blue).main
            }
            return nameColor
        }
        return presentation.chat.linkColor(isIncoming, entry.renderType == .bubble)
    }


	public var forwardType:ForwardItemType? {
        didSet {
            
        }
    }
    
    
    public var sending: Bool {
        return message?.flags.contains(.Unsent) ?? false
    }

    public private(set) var forwardHeader: TextViewLayout?
    public private(set) var forwardNameLayout: TextViewLayout?
    public private(set) var forwardPhotoPlaceRange: NSRange?
    
    public var captionLayouts:[RowCaption] = []
    public private(set) var authorText:TextViewLayout?
    public private(set) var adminBadge:TextViewLayout?
    public private(set) var adminBadgeIsRank: Bool = false
    public private(set) var adminBadgeRankType: AdminBadgeType = .none
    public private(set) var adminBadgeColor: NSColor?
    public private(set) var adminBadgeCanEdit: Bool = false
    public private(set) var adminBadgeAuthorId: PeerId?

    #if DEBUG
    typealias DebugAdminBadgeState = (badge: TextViewLayout?, isRank: Bool, rankType: AdminBadgeType, color: NSColor?, canEdit: Bool, authorId: PeerId?)

    var debugAdminBadgeState: DebugAdminBadgeState {
        get { (adminBadge, adminBadgeIsRank, adminBadgeRankType, adminBadgeColor, adminBadgeCanEdit, adminBadgeAuthorId) }
        set {
            adminBadge = newValue.badge
            adminBadgeIsRank = newValue.isRank
            adminBadgeRankType = newValue.rankType
            adminBadgeColor = newValue.color
            adminBadgeCanEdit = newValue.canEdit
            adminBadgeAuthorId = newValue.authorId
        }
    }
    #endif
    
    public private(set) var boostBadge:TextViewLayout?
    public private(set) var guestChatBadge: TextViewLayout?

    

    public var replyModel:ChatAccessoryModel?
    
    public var replyMarkupModel:ReplyMarkupNode?

    public var messageIndex:MessageIndex? {
        if let message = message {
            return MessageIndex(message)
        }
        return nil
    }
    
    public var topInset:CGFloat   {
        return 2
    }
    public var defaultContentTopOffset:CGFloat {
        if isBubbled {
            return 10
        } else {
            return 6
        }
    }
    
    public var rightInset:CGFloat {
        if isBubbled {
            return 12
        } else {
            return chatInteraction.presentation.selectionState != nil ? 44.0 : 12
        }
    }
    public var leftInset:CGFloat {
        var inset: CGFloat = 13
        if let monoforum = entry.additionalData.monoforumState {
            if case .vertical = monoforum {
                if isIncoming || !isBubbled {
                    inset += 80 + 9
                }
            }
        }
        return inset
    }

    
    public var _defaultHeight:CGFloat {
        return self.contentOffset.y + defaultContentTopOffset
    }
    
    public var _contentSize:NSSize = NSZeroSize
    public var previousBlockWidth:CGFloat = 0;

    public var bubbleDefaultInnerInset: CGFloat {
        return bubbleContentInset * 2 + additionBubbleInset
    }
    
    public var max_reply_size_width: CGFloat {
        if isBubbleFullFilled {
            return contentSize.width - bubbleContentInset * 2
        } else {
            return bubbleFrameWidth - bubbleDefaultInnerInset
        }
    }
    
    public var min_block_width: CGFloat {
        return 450
    }
    
    public var blockWidth:CGFloat {
        
        var widthForContent: CGFloat = 0
        
        if isBubbled {
            
            var tempWidth: CGFloat = width - self.contentOffset.x - bubbleDefaultInnerInset - (20 + 10 + additionBubbleInset) - 20
            
            if isSharable || hasSource {
                tempWidth -= 35
            }
            if isLikable {
                tempWidth -= 35
            }
            widthForContent = min(tempWidth, min_block_width)
            
            
        } else {
            if case .Full = itemType {
                let additionWidth:CGFloat = date?.layoutSize.width ?? 20
                widthForContent = min(800, width) - self.contentOffset.x - 44 - additionWidth
            } else {
                widthForContent = min(800, width) - self.contentOffset.x - rightSize.width - 44
            }
        }
        
        if forwardType != nil {
            widthForContent -= leftContentInset
        }
        
        if let monoforumState = entry.additionalData.monoforumState {
            if case .vertical = monoforumState {
                if self is ChatServiceItem {
                    widthForContent -= 80
                } else if !isIncoming, isBubbled {
                    widthForContent -= 80
                }
            }
        }
        return widthForContent
    }
    
    public private(set) var rightFrames: ChatRightView.Frames?
    private var rightHeight: CGFloat {
        var height:CGFloat = 16
        if isStateOverlayLayout {
            height = 16
        }
        return height
    }
    public var isIncomingTypingDraft: Bool {
        return message?.attributes.contains(where: { $0 is TypingDraftMessageAttribute }) ?? false
    }

    public var rightSize:NSSize {
        if let _ = message?.adAttribute {
            return .zero
        }
//        if let _ = chatInteraction.mode.customChatContents {
//            return .zero
//        }
        if let frames = rightFrames {
            return NSMakeSize(frames.width, rightHeight)
        } else {
            return .zero
        }
    }
    
    public var contentSize:NSSize {
        return _contentSize
    }
    
    public var realContentSize: NSSize {
        return _contentSize
    }
    
    public var isSticker: Bool {
        let file = message?.anyMedia as? TelegramMediaFile
        return file?.isStaticSticker == true || file?.isAnimatedSticker == true  || file?.isVideoSticker == true
    }
    

    private var _cachedHeight: CGFloat?

    public override var height: CGFloat  {
        if let cached = _cachedHeight {
            return cached
        }
        let result = self._computeHeight()
        _cachedHeight = result
        return result
    }

    private func _computeHeight() -> CGFloat {
        var height:CGFloat = self.contentSize.height + _defaultHeight
        
        guard let message = self.message else {
            return height
        }
        
        if !isBubbled, case .Full = self.itemType, self is ChatMessageItem {
            height += 2
        }
        
        if !captionLayouts.isEmpty {
            let captionHeight: CGFloat = captionLayouts.reduce(0, { $0 + $1.layout.size.height }) + defaultContentInnerInset * CGFloat(captionLayouts.count)
            if let item = self as? ChatGroupedItem {
                switch item.layoutType {
                case .photoOrVideo:
                    height += captionHeight
                case .files:
                    break
                }
            } else {
                height += captionHeight
            }
        }
        if let replyMarkupModel = replyMarkupModel {
            // `precomputedHeight` is a pure function of the row count and
            // doesn't require `measureSize(_:)` to have run first — so we can
            // safely compute the row's total height without first knowing
            // bubble width.
            height += replyMarkupModel.precomputedHeight + defaultReplyMarkupInset
        }
        
        if isBubbled {
            if let additional = additionalLineForDateInBubbleState {
                height += additional
            }
   
            if let replyModel, replyModel.isSideAccessory {
                height = max(48, height, replyOffset + replyModel.size.height + defaultContentTopOffset)
            }
        }
        if let _ = commentsBubbleData {
            height += ChatRowItem.channelCommentsBubbleHeight
        }
        
        if let reactions = self.reactionsLayout {
            height += defaultReactionsInset
            height += reactions.size.height
            
            if invertMedia, commentsBubbleData != nil {
                height += defaultContentInnerInset
            }
        }
        
        if let factCheckLayout {
            height += factCheckLayout.size.height
            height += defaultContentInnerInset
            if captionLayouts.isEmpty && message.text.isEmpty, message.media.first?.isInteractiveMedia == true {
                height += defaultContentInnerInset + 4
            }
        }
        
//        if isBubbled, let _ = replyMarkupModel, replyModel != nil {
//            height += 4
//        }
        
        if contentSize.height == 0 {
            if replyModel != nil {
                height += defaultContentTopOffset
            }
        }
        
        return max(rightSize.height + 8, height)
    }
    
    public var defaultReplyMarkupInset: CGFloat {
        return  (isBubbled ? 4 : defaultContentInnerInset)
    }
    
    public var defaultReactionsInset: CGFloat {
        if isBubbled {
            if isBubbleFullFilled {
                if captionLayouts.isEmpty {
                    return defaultReplyMarkupInset
                }
            } else {
                return defaultContentInnerInset
            }
        }
        return defaultContentInnerInset
    }
    private var _id: String?
    public override var identifier: String {
        if let id = _id {
            return id
        }
        let id: String = super.identifier
        _id = id
        return id
    }
    
    public var defaultContentInnerInset: CGFloat {
        return ChatRowItem.defaultContentInnerInset
    }
    
    public static var defaultContentInnerInset: CGFloat {
        return 7
    }
    
    public var elementsContentInset: CGFloat {
        return 0
    }
    
    public var replyOffset:CGFloat {
        var top:CGFloat = defaultContentTopOffset
        if isBubbled && (authorText != nil || forwardNameLayout != nil) {
            top -= topInset
        } else if isBubbled {
            top += topInset + 1
        }
        if let author = authorText {
            top += author.layoutSize.height + defaultContentInnerInset
        }
        if let author = forwardNameLayout {
            top += author.layoutSize.height + defaultContentInnerInset - 2

            if !isBubbled, let header = forwardHeader {
                top += header.layoutSize.height
            }
        }

        if let value = topicLinkLayout {
            top += value.size.height + defaultContentInnerInset
        }

        if let badge = guestChatBadge {
            top += badge.layoutSize.height
        }

        return top
    }
    
    public var topicLinkOffset:CGFloat {
        var offset = self.replyOffset
        
        if let value = topicLinkLayout {
            offset -= (value.size.height + defaultContentInnerInset)
        }
        return offset
    }
    
    public var isBubbleFullFilled: Bool {
        return false
    }
    
    public var fixedContentSize: Bool {
        return false
    }
    
    public var canBlur: Bool {
        if context.isLite(.blur) {
            return false
        }
        
        return true
    }
    public var shouldBlurService: Bool {
        if !canBlur {
            return false
        }
        if presentation.shouldBlurService, isStateOverlayLayout {
            return true
        } else if isStateOverlayLayout {
            if let message = message, let media = message.anyMedia {
                return isBubbled && media.isInteractiveMedia && captionLayouts.isEmpty
            } else {
                return false
            }
        }
        return false
    }
    
    public var isStateOverlayLayout: Bool {
        if let message = message, let media = message.anyMedia {
            if isSticker {
                return isBubbled
            }
            if let media = media as? TelegramMediaFile, media.isInstantVideo {
                if let data = entry.additionalData.transribeState {
                    switch data {
                    case .loading, .revealed:
                        return false
                    default:
                        break
                    }
                }
            }
            if media is TelegramMediaDice {
                return isBubbled
            }
            
            
            if let attr = message.factCheckAttribute, case .Loaded = attr.content {
                return false
            }
            
            
            if let message = effectiveCommentMessage, message.hasComments && message.hasReactions && message.invertMedia {
                return false
            }
            
            
            if let media = message.media.first as? TelegramMediaStory, let story = message.associatedStories[media.storyId]?.get(Stories.StoredItem.self) {
                switch story {
                case let .item(item):
                    if !item.text.isEmpty {
                        return false
                    }
                case .placeholder:
                    break
                }
            }
            
            if let media = media as? TelegramMediaMap {
                if let liveBroadcastingTimeout = media.liveBroadcastingTimeout {
                    var time:TimeInterval = Date().timeIntervalSince1970
                    if liveBroadcastingTimeout == .max {
                        return false
                    } else {
                        time -= context.timeDifference
                        if Int(time) < Int(message.timestamp) + Int(liveBroadcastingTimeout) {
                            return false
                        }
                    }
                   
                }
                return media.venue == nil
            }
            return isBubbled && media.isInteractiveMedia && (captionLayouts.isEmpty || invertMedia)
        }
        return false
    }
    
    public private(set) var isForceRightLine: Bool = false
    
    public var forwardHeaderInset:NSPoint {
        
        var top:CGFloat = defaultContentTopOffset + 1
        
        
        
        if !isBubbled, forwardHeader == nil {
           // top -= topInset
        } else if isBubbled {
            top -= 1
          //  top -= topInset
        }
        
        if let author = authorText {
            top += author.layoutSize.height
        }
        
        return NSMakePoint(defLeftInset, top)
    }
    
    public var forwardNameInset:NSPoint {
        var top:CGFloat = forwardHeaderInset.y
        
        if let header = forwardHeader, !isBubbled {
            top += (header.layoutSize.height + defaultContentInnerInset)
        }
        
        return NSMakePoint(self.contentOffset.x, top)
    }
    
    public var defLeftInset:CGFloat {
        var inset: CGFloat = leftInset
        if isBubbled {
            if hasPhoto {
                inset += 36
            } else if self.isIncoming, let message = message {
                if let peer = message.peers[message.id.peerId] {
                    if peer.isGroup || peer.isSupergroup {
                        if peer.isForumOrMonoForum, peer.isBot {
                        } else {
                            inset += 36
                        }
                    }
                }
            }
        } else {
            inset += 36 + 10
        }
        
        
        return inset
    }
    
    public var hasPhoto: Bool {
        if let _ = message?.adAttribute {
            return false
        }
        if message?.id.peerId == verifyCodePeerId {
            return true
        }
        if case .searchHashtag = chatInteraction.mode.customChatContents?.kind {
            return true
        }
        if !isBubbled {
            if case .Full = itemType {
                return true
            } else {
                return false
            }
        } else {
            if let message = message, let peer = message.peers[message.id.peerId] {
                if chatInteraction.chatLocation.threadMsgId == effectiveCommentMessage?.id {
                    return false
                }
                if (isIncoming && message.id.peerId == context.peerId) {
                    return true
                }
                if message.id.peerId == repliesPeerId && message.author?.id != context.peerId {
                    return true
                }
                if !peer.isUser && !peer.isSecretChat && !peer.isChannel && isIncoming {
                    if peer.isForumOrMonoForum, peer.isBot {
                        return false
                    }
                    return true
                }
                if message.author != nil, let peer = message.peers[message.id.peerId] as? TelegramChannel {
                    switch peer.info {
                    case let .broadcast(info):
                        return info.flags.contains(.messagesShouldHaveProfiles)
                    default:
                        break
                    }
                }
            }
        }
        if chatInteraction.isGlobalSearchMessage {
            return true
        }
        return false
    }
    
    public var isInstantVideo: Bool {
        return self is ChatVideoMessageItem
    }
    
    public var contentOffset:NSPoint {
        
        var left:CGFloat = defLeftInset
        
        var top:CGFloat = defaultContentTopOffset
        
        if message?.adAttribute != nil {
            top = 4
        }
//        
//        if !isBubbled, message?.adAttribute != nil {
//            if !hasPhoto {
//                left -= (36 + 10)
//            }
//        }
        
        if let author = authorText {
            top += author.layoutSize.height
            if !isBubbled {
                top += topInset
            }
        }

        if let value = topicLinkLayout {
            top += value.size.height + defaultContentInnerInset
            if authorText == nil {
                top -= 3
            }
        }

        if let badge = guestChatBadge {
            top += badge.layoutSize.height
        }
        
        if let replyModel = replyModel {
            var apply: Bool = true
            if isBubbled {
                if !hasBubble {
                    apply = false
                }
            }
            if apply {
                top += max(34, replyModel.size.height) //+ ((!isBubbleFullFilled && isBubbled && self is ChatMediaItem) ? 0 : 8)
                
                top += defaultContentInnerInset + 1
                 
//                if (authorText != nil) && self is ChatMessageItem {
//                    top += topInset
//                    //top -= defaultContentInnerInset
//                }
//                else if hasBubble && self is ChatMessageItem {
//                    top -= topInset
//                }
            }
        }
        
        if let forwardNameLayout = forwardNameLayout, !isBubbled || !isInstantVideo  {
            top += forwardNameLayout.layoutSize.height
            //if !isBubbled {
               // top += 2
            //}
        }
        
        if let forwardType = forwardType, !isBubbled {
            if forwardType == .FullHeader || forwardType == .ShortHeader {
                if let forwardHeader = forwardHeader {
                    top += forwardHeader.layoutSize.height + defaultContentInnerInset
                } else {
                    top += bubbleDefaultInnerInset
                }
            }
        }
        
        if isBubbled, let item = self as? ChatMessageItem {
            if item.webpageAboveContent {
                top += topInset
            }
        }
        
        
        if forwardNameLayout != nil {
            left += leftContentInset
        }
        
       
        return NSMakePoint(left, top)
    }
    
    public var leftContentInset: CGFloat {
        return 10
    }
    
    public private(set) var isRead:Bool = false
    
    public override var stableId: AnyHashable {
        return entry.stableId
    }
    
    public override func isEqual(_ object: Any?) -> Bool {
        if let object = object as? ChatRowItem {
            return self.entry == object.entry
        }
        return false
    }
    
    public var hasSource: Bool {
        switch chatInteraction.mode {
        case .pinned:
            return true
        case .customChatContents:
            return false
        default:
            if let message = message {
                for attr in message.attributes {
                    if let attr = attr as? SourceReferenceMessageAttribute {
                        if authorIsChannel {
                            return true
                        }
                        return (chatInteraction.peerId == context.peerId && context.peerId != attr.messageId.peerId) || message.id.peerId == repliesPeerId
                    }
                }
            }
        }
        return false
    }
    
    public var isSelectedMessage: Bool {
        if let message = message {
            return chatInteraction.presentation.isSelectedMessageId(message.id)
        }
        return false
    }
    
    public override var isSelectable: Bool {
        return chatInteraction.chatLocation.threadMsgId != effectiveCommentMessage?.id && self.message?.adAttribute == nil
    }
    
    public var disableInteractions: Bool {
        return false
    }
    
    
    public func openReplyMessage() {
        if let message = message {
            if let replyAttribute = message.replyAttribute {
                if message.id.peerId == repliesPeerId, let threadMessageId = message.replyAttribute?.threadMessageId {
                    chatInteraction.openReplyThread(threadMessageId, false, true, .comments(origin: replyAttribute.messageId))
                } else {
                    chatInteraction.focusMessageId(message.id, .init(messageId: replyAttribute.messageId, quote: replyAttribute.quote), .CenterEmpty)
                }
            } else if let _ = message.quoteAttribute {
                let id = MessageId(peerId: .init(0), namespace: 0, id: 0)
                chatInteraction.focusMessageId(id, .init(messageId: id, string: nil), .CenterEmpty)
            }
        }
    }
    public func openStory() {
        if let message = message {
            if let replyAttribute = message.storyAttribute {
                chatInteraction.openStory(message.id, replyAttribute.storyId)
            }
        }
    }
    
    public func showExpiredStoryError() {
        showModalText(for: context.window, text: strings().chatReplyExpiredStoryError)
    }
    
    public func gotoSourceMessage() {
        if let message = message {
            switch chatInteraction.mode {
            case .pinned:
                let navigation = chatInteraction.interactionContext.bindings.rootNavigation()
                let controller = navigation.previousController as? ChatInterfaceController
                controller?.chatInteraction.focusPinnedMessageId(message.id)
                navigation.back()
            default:
                for attr in message.attributes {
                    if let attr = attr as? SourceReferenceMessageAttribute {
                        if message.id.peerId == repliesPeerId, let threadMessageId = message.replyAttribute?.threadMessageId {
                            chatInteraction.openReplyThread(threadMessageId, false, true, .comments(origin: attr.messageId))
                        } else {
                            switch chatInteraction.mode {
                            case .thread:
                                chatInteraction.focusMessageId(nil, .init(messageId: attr.messageId, string: nil), .CenterEmpty)
                            default:
                                chatInteraction.openInfo(attr.messageId.peerId, true, attr.messageId, nil)
                            }
                        }
                    }
                }
            }
            
        }
    }
    
    internal var _isBigEmoji: Bool?
    public func share() {
        if let message = message {
            showModal(with: ChatHistoryUIHooks.shared.makeShareMessagesModalObserved(context, message), for: context.window)
        }
    }
    
    public var authorIsChannel: Bool {
        guard let message = message else {
            return false
        }
        return ChatRowItem.authorIsChannel(message: message, account: context.account)
    }
    
    private static func authorIsChannel(message: Message, account: Account) -> Bool {
        
        let isCrosspostFromChannel = message.isCrosspostFromChannel(account: account)
        
        var sourceReference: SourceReferenceMessageAttribute?
        for attribute in message.attributes {
            if let attribute = attribute as? SourceReferenceMessageAttribute {
                sourceReference = attribute
                break
            }
        }
        
        var authorIsChannel: Bool = false
        if let peer = message.peers[message.id.peerId] as? TelegramChannel {
            if case .broadcast = peer.info {
                
            } else {
                if isCrosspostFromChannel, let sourceReference = sourceReference, let _ = message.peers[sourceReference.messageId.peerId] as? TelegramChannel {
                    authorIsChannel = true
                }
            }
        } else {
            if isCrosspostFromChannel, let _ = message.forwardInfo?.source as? TelegramChannel {
                authorIsChannel = true
            }
        }
        
        
        return authorIsChannel
    }
    
    public var isLikable: Bool {
        return false
    }
    

    public override func copyAndUpdate(animated: Bool) {
        DispatchQueue.main.async {
            if let table = self.table, self.index != -1 {
                let item = ChatRowItem.item(table.frame.size, from: self.entry, interaction: self.chatInteraction, theme: self.presentation)
                _ = item.makeSize(table.frame.width, oldWidth: 0)
                let transaction = TableUpdateTransition(deleted: [], inserted: [], updated: [(self.index, item)], animated: animated)
                table.merge(with: transaction)
            }
        }
    }
    
    public var shareVisible: Bool {
        
        guard let message = message else {
            return false
        }
        if isSharable {
            if message.isScheduledMessage || message.flags.contains(.Sending) || message.flags.contains(.Failed) || message.flags.contains(.Unsent) {
                return false
            } else {
                return true
            }
        }
        return false
    }
    
    private var reactionPermissionPeer: Peer? {
        guard let message = firstMessage else { return nil }
        return chatInteraction.peer.flatMap { $0.id == message.id.peerId ? $0 : nil } ?? message.peers[message.id.peerId]
    }

    public var canReact: Bool {
        if let message = firstMessage {

            guard let peer = reactionPermissionPeer, canSendReactionsToPeer(EnginePeer(peer)) else {
                return false
            }

            if message.activeEphemeralReplacementMessage != nil {
                return false
            }
            
            if entry.isFakeMessage {
                return false
            }
            
            if chatInteraction.isPeerSavedMessages {
                return false
            }
            if message.id.namespace != Namespaces.Message.Cloud {
                return false
            }
            if message.id.peerId.namespace == Namespaces.Peer.SecretChat {
                return false
            }
            if isUnsent {
                return false
            }
            if isFailed {
                return false
            }
            if message.adAttribute != nil {
                return false
            }
            if unsupported {
                return false
            }
            if message.containsSecretMedia {
                return false
            }
            if let media = message.extendedMedia, let _ = media as? TelegramMediaAction {
                return message.flags.contains(.ReactionsArePossible)
            }
            if let media = message.extendedMedia as? TelegramMediaStory {
                if media.isMention {
                    return false
                }
            }
            return true
        }
        return false
    }
    
    public var isSharable: Bool {
        var peers:[Peer] = []
        if let peer = peer {
            peers.append(peer)
        }
        if let peer = message?.author {
            peers.append(peer)
        }
        
        guard let message = message else {
            return false
        }
        if message.adAttribute != nil {
            return false
        }
        
        if chatInteraction.mode == .preview {
            return false
        }
        
        
        
        if message.isCopyProtected(cachedData: chatInteraction.presentation.cachedData) {
            return false
        }
        
        if case .searchHashtag = chatInteraction.mode.customChatContents?.kind {
            return true
        }
        
        if authorIsChannel {
            return false
        }
        

        
        if let info = message.forwardInfo {
            if let author = info.author {
                peers.append(author)
            }
            
            if let peer = info.source {
                peers.append(peer)
            }
        }
        
        for peer in peers {
            if peer.addressName == "reviews_bot" || peer.addressName == "ReviewInsightsBot" {
                return true
            }
            if let peer = peer as? TelegramChannel {
                switch peer.info {
                case .broadcast:
                    return isIncoming && !chatInteraction.isLogInteraction
                default:
                    return false
                }
            }
            if let peer = peer as? TelegramUser {
                if peer.botInfo != nil {
                    if self is ChatMediaItem && !chatInteraction.isLogInteraction {
                        return true
                    } else if let item = self as? ChatMessageItem {
                        return item.webpageLayout != nil
                    }
                    return false
                }
            }
        }
        
        
        return false
    }
    
    private let _isScam: Bool
    private let _isFake: Bool
    
    public private(set) var isForwardScam: Bool
    public private(set) var isForwardFake: Bool

    public var isFailed: Bool {
        for message in messages {
            if message.flags.contains(.Failed) {
                return true
            }
            if message.attributes.contains(where: {
                ($0 as? EphemeralOutgoingMessageAttribute)?.state == .failed
            }) {
                return true
            }
        }
        return false
    }
    
    public var isPinned: Bool {
        for message in messages {
            if message.tags.contains(.pinned) {
                return true
            }
        }
        return false
    }
    
    public let isIncoming: Bool
    
    public var canHasFloatingPhoto: Bool {
        if chatInteraction.mode.isSavedMode {
            return false
        } else if chatInteraction.mode.isThreadMode, chatInteraction.chatLocation.threadMsgId == message?.id {
            return false
        } else {
            return isIncoming && self.hasPhoto
        }
    }
    
    public var isUnsent: Bool {
        if entry.additionalData.updatingMedia != nil {
            return true
        }
        if let message = message {
            return message.flags.contains(.Unsent)
        }
        return false
    }
    
    public var isEditMarkVisible: Bool {
        var peers:[Peer] = []
        if let peer = peer {
            peers.append(peer)
        }
        if let info = message?.forwardInfo?.author {
            peers.append(info)
        }
        
//        for peer in peers {
//            if let peer = peer as? TelegramUser {
//                if peer.botInfo != nil {
//                    return false
//                }
//            }
//        }
//        
        for message in messages {
            if message.isScheduledMessage {
                return false
            }
//            for attr in message.attributes {
//                if attr is InlineBotMessageAttribute {
//                    return false
//                }
//            }
//            for media in message.media {
//                if media is TelegramMediaMap {
//                    return false
//                }
//            }
            
            if message.isImported {
                return true
            }
            for attr in message.attributes {
                if let attr = attr as? EditedMessageAttribute {
                    return !chatInteraction.isLogInteraction && message.id.peerId != context.peerId && !attr.isHidden
                }
            }
        }
        
        return false
    }
    
    private static func canFillAuthorName(_ message: Message, chatInteraction: ChatInteraction, renderType: ChatItemRenderType, isIncoming: Bool, hasBubble: Bool) -> Bool {
        var canFillAuthorName: Bool = true
        var disable: Bool = false

        if message.adAttribute != nil {
            return false
        }

        if renderType == .bubble, ChatRowItem.isUnsupported(message) {
            return false
        }

        if message.guestChatAttribute != nil {
            return true
        }
      
        switch chatInteraction.chatLocation {
        case .peer, .thread:
            if renderType == .bubble, let peer = coreMessageMainPeer(message) {
                canFillAuthorName = isIncoming && (peer.isGroup || peer.isSupergroup || message.id.peerId == chatInteraction.interactionContext.peerId || message.id.peerId == repliesPeerId || message.id.peerId == verifyCodePeerId || message.adAttribute != nil)
                
               
                if let _ = message.anyMedia as? TelegramMediaGiveaway {
                    disable = true
                }
                
                if let media = message.anyMedia {
                    canFillAuthorName = canFillAuthorName && !media.isInteractiveMedia && hasBubble && isIncoming
                } else if bigEmojiMessage(chatInteraction.interactionContext.sharedContext.baseSettings, message: message) {
                    canFillAuthorName = false
                    disable = true
                }
                if message.isAnonymousMessage, !isIncoming {
                    if let media = message.anyMedia as? TelegramMediaFile {
                        if media.isSticker || media.isAnimatedSticker {
                            disable = true
                        }
                    }
                    if !disable {
                        canFillAuthorName = true
                    }
                }
                if !isIncoming && message.author?.id != chatInteraction.interactionContext.peerId, message.globallyUniqueId != 0 {
                    if let media = message.anyMedia as? TelegramMediaFile {
                        if media.isSticker || media.isAnimatedSticker {
                            disable = true
                        }
                    }
                    if !disable {
                        canFillAuthorName = true
                    }
                }
                
                if let peer = message.peers[message.id.peerId] as? TelegramChannel, peer.isChannel, let _ = message.author {
                    canFillAuthorName = false
                }
                
                if let peer = message.peers[message.id.peerId] as? TelegramChannel, let _ = message.author {
                    switch peer.info {
                    case let .broadcast(info):
                        if info.flags.contains(.messagesShouldHaveProfiles) {
                            if !disable {
                                canFillAuthorName = true
                            }
                        }
                    default:
                        break
                    }
                }
            }
        }
        return canFillAuthorName
    }
    
    public var canFillAuthorName: Bool {
        if let message = message {
            return ChatRowItem.canFillAuthorName(message, chatInteraction: chatInteraction, renderType: renderType, isIncoming: isIncoming, hasBubble: hasBubble)
        }
        return true
    }
    
    public var isBubbled: Bool {
        return renderType == .bubble
    }
    
    public var psaButton: NSAttributedString? {
        if let info = message?.forwardInfo?.psaType {
            let text = localizedPsa("psa.text", type: info)
            
            let attributedText = parseMarkdownIntoAttributedString(text, attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .normal(.text), textColor: .white), bold: MarkdownAttributeSet(font: .bold(.text), textColor: .white), link: MarkdownAttributeSet(font: .normal(.text), textColor: .link), linkAttribute: { contents in
                return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink(contents, { url in
                    LinkHooks.shared.openExternalLink(url, false)
                }))
            }))
            return attributedText
        }
        return nil
    }
    
    public var isPsa: Bool {
        return message?.forwardInfo?.psaType != nil
    }
    
    public var hasHeader: Bool {
        return !(hasBubble && authorText == nil && replyModel == nil && forwardNameLayout == nil)
    }
    
    public var hasBubble: Bool 
    
    public static func hasBubble(_ message: Message?, entry: ChatHistoryEntry, type: ChatItemType, sharedContext: any SharedAccountContextProtocol) -> Bool {
        if let message = message, let media = message.anyMedia {
            
            
            if message.adAttribute != nil {
                return true
            }
            
            if let file = media as? TelegramMediaFile {
                if file.isStaticSticker {
                    return false
                }
                if file.isVideoSticker {
                    return false
                }
                if file.isAnimatedSticker {
                    return false
                }
                if file.isInstantVideo {
                    if let data = entry.additionalData.transribeState {
                        switch data {
                        case .loading, .revealed:
                            return true
                        default:
                            break
                        }
                    }
                    return false //!message.text.isEmpty || (message.replyAttribute != nil && !file.isInstantVideo) || (message.forwardInfo != nil && !file.isInstantVideo)
                }
            }
            if media is TelegramMediaDice {
                return false
            }
            
            for attr in message.attributes {
                if let _ = attr as? InlineBotMessageAttribute {
                    return true
                }
            }
            
            var peer: Peer?
            for attr in message.attributes {
                if let _ = attr as? SourceReferenceMessageAttribute {
                    if let info = message.forwardInfo {
                        peer = info.author
                    }
                    break
                }
            }
            
            if let _peer = coreMessageMainPeer(message) as? TelegramChannel, case let .broadcast(info) = _peer.info {
                if info.flags.contains(.hasDiscussionGroup) {
                    return true
                }
                peer = _peer
            } else if let author = message.effectiveAuthor, peer == nil {
                if author is TelegramSecretChat {
                    peer = coreMessageMainPeer(message)
                } else {
                    peer = author
                }
            }
            
//            if message.groupInfo != nil {
//                switch entry {
//                case .groupedPhotos(let entries, _):
//                    let prettyCount = entries.filter { $0.message?.anyMedia?.isInteractiveMedia ?? false }.count
//                    return !message.text.isEmpty || message.replyAttribute != nil || message.forwardInfo != nil || entries.count == 1 || prettyCount != entries.count
//                default:
//                    return true
//                }
//            }
        
        } else if let message = message {
            if entry.additionalData.eventLog != nil {
                return true
            }
            if message.adAttribute != nil {
                return true
            }
            return !bigEmojiMessage(sharedContext.baseSettings, message: message)
        }
        return true
    }
    
    public var fillPhoto: Bool {
        if self.renderType != .bubble {
            return true
        } else if chatInteraction.isLogInteraction {
            return true
        } else if chatInteraction.mode.isSavedMode {
            return true
        }
        return false
    }
    
    public let renderType: ChatItemRenderType
    private struct BubbleMerge {
        let above: Bool
        let below: Bool
        let hasInlineKeyboard: Bool
        let isThreadRoot: Bool
    }

    private var bubbleMerge: BubbleMerge? = nil

    private var bubbleNeighbors: MessageBubbleImageNeighbors? {
        guard let merge = bubbleMerge else {
            return nil
        }
        if merge.isThreadRoot {
            return .extracted
        }
        var below = merge.below || merge.hasInlineKeyboard
        if !below, case .MessageEntry = entry, reactionsLayout?.presentation.isOutOfBounds == true {
            below = true
        }
        return ChatRowItem.bubbleNeighbors(mergedAbove: merge.above, mergedBelow: below, side: merge.hasInlineKeyboard)
    }

    static func bubbleNeighbors(mergedAbove: Bool, mergedBelow: Bool, side: Bool) -> MessageBubbleImageNeighbors {
        if mergedBelow && mergedAbove {
            return .both
        } else if mergedBelow {
            return .top(side: side)
        } else if mergedAbove {
            return side ? .side : .bottom
        } else {
            return side ? .side : MessageBubbleImageNeighbors.none
        }
    }

    public func mediaBubbleCorners(inset: CGFloat) -> ImageCorners? {
        guard let neighbors = bubbleNeighbors else {
            return nil
        }
        return messageBubbleCorners(incoming: isIncoming, neighbors: neighbors, inset: inset)
    }

    public var bubbleImage:(CGImage, NSEdgeInsets)? {
        guard let neighbors = bubbleNeighbors else {
            return nil
        }
        return messageBubbleImageModern(incoming: isIncoming, fillColor: .black, strokeColor: .clear, neighbors: neighbors)
    }

    public let downloadSettings: AutomaticMediaDownloadSettings
    
    public let presentation: TelegramPresentationTheme


    
    private var _approximateSynchronousValue: Bool = false
    public var approximateSynchronousValue: Bool {
        get {
            let result = _approximateSynchronousValue
            _approximateSynchronousValue = false
            return result
        }
    }
    
    private var _avatarSynchronousValue: Bool = false
    public static var channelCommentsBubbleHeight: CGFloat {
        return 42
    }
    public static var channelCommentsHeight: CGFloat {
        return 16
    }
    
    public var effectiveCommentMessage: Message? {
        switch entry {
        case let .MessageEntry(message, _, _, _, _, _, _):
            return message
        case let .groupedPhotos(entries, groupInfo: _):
            return entries.first?.message
        default:
            return nil
        }
    }
    
    public var channelHasCommentButton: Bool {
        if chatInteraction.mode == .scheduled || chatInteraction.isLogInteraction {
            return false
        }
        if let message = effectiveCommentMessage, let peer = message.peers[message.id.peerId] as? TelegramChannel {
            switch peer.info {
            case let .broadcast(info):
                if info.flags.contains(.hasDiscussionGroup) {
                    if message.flags.contains(.Sending) || message.flags.contains(.Failed) || message.flags.contains(.Unsent) {
                        switch chatInteraction.presentation.discussionGroupId {
                        case .unknown:
                            return false
                        case .known:
                            return true
                        }
                    }
                    for attr in message.attributes {
                        if let attr = attr as? ReplyThreadMessageAttribute {
                            switch chatInteraction.presentation.discussionGroupId {
                            case .unknown:
                                return true
                            case let .known(peerId):
                                return attr.commentsPeerId == peerId
                            }
                        }
                    }
                    
                }
            default:
                break
            }
        }
        
        return false
    }
    
    private var _commentsBubbleData: ChannelCommentsRenderData?
    private var _commentsBubbleDataOverlay: ChannelCommentsRenderData?
    
    public var commentsBubbleDataOverlay: ChannelCommentsRenderData? {
        if let commentsBubbleDataOverlay = _commentsBubbleDataOverlay {
            return commentsBubbleDataOverlay
        }
        
        if chatInteraction.isLogInteraction {
            return nil
        }
        if chatInteraction.mode == .preview {
            return nil
        }
        
        if !isStateOverlayLayout || hasBubble || !channelHasCommentButton {
            return nil
        }
        if let message = effectiveCommentMessage, let peer = message.peers[message.id.peerId] as? TelegramChannel {
            switch peer.info {
            case let .broadcast(info):
                if info.flags.contains(.hasDiscussionGroup) {
                    var count: Int32 = 0
                    var hasUnread: Bool = false
                    for attr in message.attributes {
                        if let attribute = attr as? ReplyThreadMessageAttribute {
                            count = attribute.count
                            if let maxMessageId = attribute.maxMessageId, let maxReadMessageId = attribute.maxReadMessageId {
                                hasUnread = maxReadMessageId < maxMessageId
                            }
                            break
                        }
                    }
                    let title: String = "\(Int(count).prettyRounded)"
                    let textColor = isBubbled && presentation.backgroundMode.hasWallpaper ? presentation.chatServiceItemTextColor : presentation.colors.accent
                    
                    var texts:[ChannelCommentsRenderData.Text] = []
                    if count > 0 {
                        texts.append(ChannelCommentsRenderData.Text.init(text: .initialize(string: title, color: textColor, font: .normal(.short)), animation: .numeric, index: 0))
                    }
                    
                    _commentsBubbleDataOverlay = ChannelCommentsRenderData(context: chatInteraction.interactionContext, message: message, hasUnread: hasUnread, title: texts, peers: [], drawBorder: true, isLoading: entry.additionalData.isThreadLoading, bubbleMode: renderType == .bubble, handler: { [weak self] in
                        self?.chatInteraction.openReplyThread(message.id, true, false, .comments(origin: message.id))
                    })
                }
            default:
                break
            }
        }
        return _commentsBubbleDataOverlay
    }
    
    public var commentsBubbleData: ChannelCommentsRenderData? {
        if let commentsBubbleData = _commentsBubbleData {
            return commentsBubbleData
        }
        if chatInteraction.isLogInteraction {
            return nil
        }
        if !channelHasCommentButton {
            return nil
        }
        if chatInteraction.mode == .preview {
            return nil
        }
        
        if isStateOverlayLayout, let media = effectiveCommentMessage?.anyMedia, !media.isInteractiveMedia {
            return nil
        } else if (self is ChatVideoMessageItem) {
            return nil
        }
        if let message = effectiveCommentMessage, let peer = message.peers[message.id.peerId] as? TelegramChannel {
            
            if let messageItem = self as? ChatMessageItem, messageItem.containsBigEmoji  {
                return nil
            }
            
            switch peer.info {
            case let .broadcast(info):
                if info.flags.contains(.hasDiscussionGroup) {
                    
                    var latestPeers:[Peer] = []
                    var count: Int32 = 0
                    var hasUnread = false
                    for attr in message.attributes {
                        if let attribute = attr as? ReplyThreadMessageAttribute {
                            count = attribute.count
                            if let maxMessageId = attribute.maxMessageId {
                                if let maxReadMessageId = attribute.maxReadMessageId {
                                    hasUnread = maxReadMessageId < maxMessageId
                                } else {
                                    hasUnread = false
                                }
                            }
                            latestPeers = message.peers.filter { peerId, _ -> Bool in
                                return attribute.latestUsers.contains(peerId)
                            }.map { $0.1 }
                            break
                        }
                    }
                    
                    var title: [(String, ChannelCommentsRenderData.Text.Animation, Int)] = []
                    if count == 0 {
                        title = [(strings().channelCommentsLeaveComment, .crossFade, 0)]
                    } else {
                        var text = strings().channelCommentsCountOther(Int(count))
                        let pretty = "\(Int(count).formattedWithSeparator)"
                        text = text.replacingOccurrences(of: "\(count)", with: pretty)
                        
                        let range = text.nsstring.range(of: pretty)
                        if range.location != NSNotFound {
                            title.append((text.nsstring.substring(to: range.location), .crossFade, 0))
                            var index: Int = 0
                            for _ in range.lowerBound ..< range.upperBound {
                                let symbol = text.nsstring.substring(with: NSMakeRange(range.location + index, 1))
                                title.append((symbol, .numeric, index + 1))
                                index += 1
                            }
                            title.append((text.nsstring.substring(from: range.upperBound), .crossFade, range.length + 1))
                        } else {
                            title.append((text, .crossFade, 0))
                        }
                    }
                    
                    title = title.filter { !$0.0.isEmpty }
                    
                    let texts:[ChannelCommentsRenderData.Text] = title.map {
                        return ChannelCommentsRenderData.Text(text: .initialize(string: $0.0, color: presentation.colors.accentIcon, font: .normal(.title)), animation: $0.1, index: $0.2)
                    }
                    
                    _commentsBubbleData = ChannelCommentsRenderData(context: chatInteraction.interactionContext, message: message, hasUnread: hasUnread, title: texts, peers: latestPeers, drawBorder: !isBubbleFullFilled || !captionLayouts.isEmpty, isLoading: entry.additionalData.isThreadLoading, bubbleMode: renderType == .bubble, handler: { [weak self] in
                        self?.chatInteraction.openReplyThread(message.id, true, false, .comments(origin: message.id))
                    })
                }
            default:
                break
            }
        }
        return _commentsBubbleData
    }
    
    
    private var _topicLinkLayout: TopicReplyItemLayout?
    public var topicLinkLayout: TopicReplyItemLayout? {
        if let value = _topicLinkLayout {
            return value
        } else if let message = self.message, let threadInfo = message.associatedThreadInfo, chatInteraction.mode == .history || (chatInteraction.mode == .preview && chatInteraction.chatLocation.threadId == nil), let peer = message.peers[message.id.peerId], TelegramUtilsHooks.shared.peerIsForum(peer), !peer.displayForumAsTabs(splitState: chatInteraction.interactionContext.layout) {
            var ignore: Bool = false
            
            if renderType == .bubble {
                let header: ChatItemType.Header
                switch itemType {
                case let .Full(_, _, current):
                    header = current
                case let .Short(_, _, current):
                    header = current
                }
                switch header {
                case .short:
                    ignore = true
                default:
                    break
                }
            } else {
                switch itemType {
                case .Short:
                    ignore = true
                default:
                    break
                }
            }
            if !ignore {
                let value = TopicReplyItemLayout(context: context, message: message, isIncoming: isIncoming, isBubbled: isBubbled, threadData: threadInfo, maxiumLines: 2, isSideAccessory: isBubbled && !hasBubble)
                _topicLinkLayout = value
                return value
            }
        }
        return nil
    }

    
    private var _reactionsLayout: ChatReactionsLayout?
    public var reactionsLayout: ChatReactionsLayout? {
        if let value = _reactionsLayout {
            return value
        } else if let message = self.messages.first {
            if chatInteraction.isLogInteraction {
                return nil
            }
            
            if entry.isFakeMessage {
                return nil
            }
            if chatInteraction.isPeerSavedMessages {
                return nil
            }
            if unsupported {
                return nil
            }
            let reactions = message.effectiveReactions(context.peerId, isTags: context.peerId == chatInteraction.peerId)
            let currentTag: MessageReaction.Reaction?
            if case let .customTag(buffer, _) = chatInteraction.presentation.searchMode.tag {
                currentTag = ReactionsMessageAttribute.reactionFromMessageTag(tag: buffer)
            } else {
                currentTag = nil
            }
            let context = self.context
            let chatInteraction = self.chatInteraction
            if let reactions = reactions, !reactions.reactions.isEmpty, let available = context.reactions.available {
                let layout = ChatReactionsLayout(context: chatInteraction.interactionContext, message: message, available: available, peerAllowed: chatInteraction.presentation.allowedReactions, savedMessageTags: entry.additionalData.savedMessageTags, engine: chatInteraction.interactionContext.reactions, theme: presentation, renderType: renderType, currentTag: currentTag, isIncoming: isIncoming, isOutOfBounds: isBubbleFullFilled && (self.captionLayouts.isEmpty || invertMedia) && (commentsBubbleData == nil || !invertMedia), hasWallpaper: presentation.hasWallpaper, stateOverlayTextColor: isStateOverlayLayout ? stateOverlayTextColor : (!hasBubble ? presentation.colors.grayText : presentation.chat.grayText(isIncoming, entry.renderType == .bubble)), reactionPeer: { [weak self] in
                    self?.reactionPermissionPeer
                }, openInfo: { peerId in
                    ChatHistoryUIHooks.shared.pushReactionPeerInfoObserved(context.bindings.rootNavigation(), context, peerId, message.id)
                }, runEffect: { [weak chatInteraction] value, isLarge in
                    chatInteraction?.runReactionEffect(value, message.id, isLarge)
                }, tagAction: { [weak chatInteraction] reaction in
                    if !context.isPremium {
                        prem(with: PremiumBoardingController(context: context, source: .saved_tags, openFeatures: true), for: context.window)
                    } else {
                        chatInteraction?.setLocationTag(.customTag(ReactionsMessageAttribute.messageTag(reaction: reaction), nil))
                    }
                }, starReact: { [weak self] in
                    guard self?.canReact == true else { return }
                    showModal(with: Star_ReactionsController(context: context, source: .message(.init(message))), for: context.window)
                })
                
                _reactionsLayout = layout
                return layout
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
    
    private var _factCheckLayout: FactCheckMessageLayout?
    public var factCheckLayout: FactCheckMessageLayout? {
        if let factCheckLayout = _factCheckLayout {
            return factCheckLayout
        } else if let message = message, let factCheck = message.factCheckAttribute {
            if case .Loaded = factCheck.content {
                _factCheckLayout = .init(message, factCheck: factCheck, context: context, presentation: wpPresentation, chatInteraction: chatInteraction, revealed: entry.additionalData.factCheckRevealed)
            }
        }
        return _factCheckLayout
    }
    
    public var forceBackgroundColor: NSColor? = nil
    public let wpPresentation: WPLayoutPresentation

    
    
    public init(_ initialSize:NSSize, _ chatInteraction:ChatInteraction, _ context: any AccountContextProtocol, _ object: ChatHistoryEntry, theme: TelegramPresentationTheme) {
        self.entry = object
        self.context = chatInteraction.interactionContext
        self.presentation = theme
        self.chatInteraction = chatInteraction
        self.downloadSettings = object.additionalData.automaticDownload.settings
        self._approximateSynchronousValue = Thread.isMainThread
        self._avatarSynchronousValue = Thread.isMainThread
        self.messageEffect = object.additionalData.messageEffect
        
        
        var message: Message?
        var isRead: Bool = true
        var itemType: ChatItemType = .Full(rank: nil, rankType: .none, header: .normal)
        var fwdType: ForwardItemType? = nil
        var renderType:ChatItemRenderType = .list
        
        let message_primary_edited_date = context.appConfiguration.getBoolValue("message_primary_edited_date", orElse: false)
        
        var object = object
        var captionMessage: Message? = object.message

        var hasGroupCaption: Bool = object.message?.text.isEmpty == false
        if case let .groupedPhotos(entries, _) = object {
            object = entries.filter({!$0.message!.media.isEmpty}).first!
            
            loop: for entry in entries {
                if let _ = captionMessage, !entry.message!.text.isEmpty {
                    captionMessage = nil
                    hasGroupCaption = false
                    break loop
                }
                if !entry.message!.text.isEmpty {
                    captionMessage = entry.message!
                    hasGroupCaption = true
                    break loop
                }
            }
            if captionMessage == nil {
                captionMessage = object.message!
            }
        }

        
        if case let .MessageEntry(_message, _, _isRead, _renderType, _itemType, _fwdType, _) = object {
            message = _message
            isRead = _isRead
            itemType = _itemType
            switch _itemType {
            case .Full:
                fwdType = .FullHeader
            default:
                fwdType = _fwdType
            }
            renderType = _renderType
        }
        
        let activity: PeerNameColors.Colors
        let pattern: Int64?
        let isIncoming: Bool
        if let message = object.firstMessage {
            activity = theme.chat.webPreviewActivity(context.peerNameColors, message: message, account: context.account, bubbled: entry.renderType == .bubble)
            pattern = theme.chat.webPreviewPattern(message)
            isIncoming = message.isIncoming(context.account, object.renderType == .bubble)
        } else {
            activity = .init(main: .clear)
            pattern = nil
            isIncoming = false
        }
        self.wpPresentation = WPLayoutPresentation(text: theme.chat.textColor(isIncoming, entry.renderType == .bubble), activity: activity, link: theme.chat.linkColor(isIncoming, entry.renderType == .bubble), selectText: theme.chat.selectText(isIncoming, entry.renderType == .bubble), ivIcon: theme.chat.instantPageIcon(isIncoming, entry.renderType == .bubble, presentation: theme), renderType: entry.renderType, pattern: pattern)
        
       
        
        
        var hiddenFwdTooltip:(()->Void)? = nil
        
       
        
        
        
        var isStateOverlayLayout: Bool {
            
            if renderType == .bubble, let message = captionMessage, let media = message.anyMedia {
                if let file = media as? TelegramMediaFile {
                    if file.isStaticSticker || file.isAnimatedSticker || file.isVideoSticker  {
                        return renderType == .bubble
                    }
                    if file.isInstantVideo {
                        if let data = object.additionalData.transribeState {
                            switch data {
                            case .loading, .revealed:
                                return false
                            default:
                                break
                            }
                        }
                        return renderType == .bubble
                    }
                    
                }
                if media is TelegramMediaDice {
                    return renderType == .bubble
                }
                
                if let attr = message.factCheckAttribute, case .Loaded = attr.content {
                    return false
                }
                
                if message.hasComments && message.hasReactions && message.invertMedia {
                    return false
                }
                
                if let media = message.media.first as? TelegramMediaStory, let story = message.associatedStories[media.storyId]?.get(Stories.StoredItem.self) {
                    switch story {
                    case let .item(item):
                        if !item.text.isEmpty {
                            return false
                        }
                    case .placeholder:
                        break
                    }
                }
                
                if let media = media as? TelegramMediaMap {
                    if let liveBroadcastingTimeout = media.liveBroadcastingTimeout {
                        if liveBroadcastingTimeout == .max {
                            return false
                        } else {
                            var time:TimeInterval = Date().timeIntervalSince1970
                            time -= context.timeDifference
                            if Int(time) < Int(message.timestamp) + Int(liveBroadcastingTimeout) {
                                return false
                            }
                        }
                        
                    }
                    return media.venue == nil
                }
                return media.isInteractiveMedia && (!hasGroupCaption || message.invertMedia)
            } else if let message = message, bigEmojiMessage(context.sharedContext.baseSettings, message: message), renderType == .bubble {
                return true
            }
            return false
        }
        
        var stateOverlayTextColor: NSColor {
            if let media = message?.anyMedia, media.isInteractiveMedia || media is TelegramMediaMap {
                 return NSColor(0xffffff)
            } else {
                return theme.chatServiceItemTextColor
            }
        }
        
        if message?.id.peerId == context.peerId {
            itemType = .Full(rank: nil, rankType: .none, header: .normal)
        }
        self.renderType = renderType
        self.message = message
        
        var isForwardScam: Bool = false
        var isScam = false
        var isForwardFake: Bool = false
        var isFake = false
        if let message = message, let peer = coreMessageMainPeer(message) {
            if peer.isGroup || peer.isSupergroup {
                if let author = message.forwardInfo?.author {
                    isForwardScam = author.isScam
                }
                if let author = message.author, case .Full = itemType {
                    isScam = author.isScam
                }
                if let author = message.forwardInfo?.author {
                    isForwardFake = author.isFake
                }
                if let author = message.author, case .Full = itemType {
                    isFake = author.isFake
                }
            }
        }
        
        self._isScam = isScam
        self.isForwardScam = isForwardScam
            
        self._isFake = isFake
        self.isForwardFake = isForwardFake
        
        if let message = message {
            let isBubbled = renderType == .bubble
            let hasBubble = ChatRowItem.hasBubble(captionMessage ?? message, entry: entry, type: itemType, sharedContext: context.sharedContext)
            self.hasBubble = isBubbled && hasBubble
            let isIncoming: Bool = message.isIncoming(context.account, renderType == .bubble)

            self.isIncoming = isIncoming

            
            if case .bubble = renderType , hasBubble{
                var mergedAbove = false
                var mergedBelow = false
                switch object.itemType {
                case let .Short(_, _, header):
                    mergedAbove = header == .short
                    mergedBelow = true
                case let .Full(_, _, header):
                    mergedAbove = header == .short
                case nil:
                    break
                }
                let isThreadRoot: Bool
                switch entry {
                case let .MessageEntry(message, _, _, _, _, _, _):
                    isThreadRoot = chatInteraction.chatLocation.threadMsgId == message.id
                case let .groupedPhotos(entries, groupInfo: _):
                    isThreadRoot = chatInteraction.chatLocation.threadMsgId == entries.first?.message?.id
                default:
                    isThreadRoot = false
                }
                bubbleMerge = BubbleMerge(above: mergedAbove, below: mergedBelow, hasInlineKeyboard: message.isHasInlineKeyboard, isThreadRoot: isThreadRoot)
            }
            
            self.itemType = itemType
            self.isRead = isRead
            
            if let info = message.forwardInfo, message.isImported {
                if let author = info.author {
                    self.peer = author
                } else if let signature = info.authorSignature {
                    
                    self.peer = TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(0)), accessHash: nil, firstName: signature, lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
                } else {
                    self.peer = message.chatPeer(context.peerId)
                }
            } else if let info = message.forwardInfo, chatInteraction.peerId == context.account.peerId || (object.renderType == .list && info.psaType != nil) {
                if info.author == nil, let signature = info.authorSignature {
                    self.peer = TelegramUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(0)), accessHash: nil, firstName: signature, lastName: nil, username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
                } else if (object.renderType == .list && info.psaType != nil) {
                    self.peer = info.author ?? message.chatPeer(context.peerId)
                } else {
                    self.peer = message.chatPeer(context.peerId)
                }
            } else {
                self.peer = message.chatPeer(context.peerId)
            }
            
            var isHasSource: Bool = false
            
            for attr in message.attributes {
                if let _ = attr as? SourceReferenceMessageAttribute {
                    isHasSource = true
                    break
                }
            }
            
            if let peer = peer, peer.isChannel {
                for attr in message.attributes {
                    if let attr = attr as? AuthorSignatureMessageAttribute {
                        if !message.flags.contains(.Failed) {
                            let attr: NSAttributedString = .initialize(string: attr.signature.prefixWithDots(13), color: isStateOverlayLayout ? stateOverlayTextColor : !hasBubble ? presentation.colors.grayText : presentation.chat.grayText(isIncoming, object.renderType == .bubble), font: renderType == .bubble ? .normal(.small) : .normal(.short))
                            postAuthor = TextViewLayout(attr, maximumNumberOfLines: 1)
                            
                            postAuthor?.measure(width: .greatestFiniteMagnitude)
                        }
                        break
                    }
                }
            }
            if let peer = peer, peer.isSupergroup, message.isAnonymousMessage {
                for attr in message.attributes {
                    if let attr = attr as? AuthorSignatureMessageAttribute {
                        if !message.flags.contains(.Failed) {
                            let badge: NSAttributedString = .initialize(string: " " + attr.signature, color: !hasBubble ? presentation.colors.grayText : presentation.chat.grayText(isIncoming, object.renderType == .bubble), font: .normal(.short))
                        
                            adminBadge = TextViewLayout(badge, maximumNumberOfLines: 1, truncationType: .end, alignment: .left)
                            adminBadge?.mayItems = false
                            adminBadge?.measure(width: .greatestFiniteMagnitude)
                        }
                        break
                    }
                }
            }
            if postAuthor == nil, ChatRowItem.authorIsChannel(message: message, account: context.account) {
                if let author = message.forwardInfo?.authorSignature {
                    let attr: NSAttributedString = .initialize(string: author, color: isStateOverlayLayout ? stateOverlayTextColor : !hasBubble ? presentation.colors.grayText : presentation.chat.grayText(isIncoming, object.renderType == .bubble), font: renderType == .bubble ? .normal(.small) : .normal(.short))
                    postAuthor = TextViewLayout(attr, maximumNumberOfLines: 1)
                }
            }
            
            
            if let peer = coreMessageMainPeer(message) as? TelegramUser, peer.botInfo != nil || peer.id == context.peerId {
                if !peer.flags.contains(.isSupport) {
                    self.isRead = true
                }
            }
            
            if let info = message.forwardInfo, !message.isImported {
                
                
                var accept:Bool = !isHasSource && message.id.peerId != context.peerId
                
                if let media = message.anyMedia as? TelegramMediaFile {
                    for attr in media.attributes {
                        switch attr {
                        case let .Audio(isVoice, _, _, _, _):
                            if !isVoice, let forwardInfo = message.forwardInfo, let source = forwardInfo.source, source.isChannel {
                                accept = accept && forwardInfo.author?.id == forwardInfo.source?.id
                            } else {
                                accept = accept && isVoice
                            }
                        default:
                            break
                        }
                    }
                }
                if !hasBubble && renderType == .bubble, message.forwardInfo?.psaType != nil {
                    accept = false
                } else if (entry.renderType == .list && message.forwardInfo?.psaType != nil) {
                    accept = false
                }
                
                if accept || (ChatRowItem.authorIsChannel(message: message, account: context.account) && info.author?.id != message.chatPeer(context.peerId)?.id), message.id.peerId != verifyCodePeerId {
                    forwardType = fwdType
                    
                    var attr = NSMutableAttributedString()

                    if ChatRowItem.authorIsChannel(message: message, account: context.account) {
                        if let author = info.author {
                            let range = attr.append(string: author.displayTitle, color: presentation.chat.linkColor(isIncoming, object.renderType == .bubble), font: .medium(.text))
                            
                            let appLink = ChatHistoryLink.peerInfo(link: "", peerId: author.id, action: nil, openChat: !(author is TelegramUser), postId: info.sourceMessageId?.id, callback: chatInteraction.openInfo)
                            attr.add(link: appLink, for: range, color: presentation.chat.linkColor(isIncoming, object.renderType == .bubble))
                        } else {
                            let color = presentation.chat.linkColor(isIncoming, object.renderType == .bubble)
                            let range = attr.append(string: info.authorTitle, color: color, font: .normal(.text))
                            attr.add(link: LinkHooks.shared.callbackLink("hid", { _ in
                                hiddenFwdTooltip?()
                            }), for: range, color: color)
                        }
                    } else {
                        
                        let color: NSColor
                        if message.forwardInfo?.psaType != nil {
                            color = presentation.chat.greenUI(isIncoming, object.renderType == .bubble)
                        } else {
                            color = presentation.chat.linkColor(isIncoming, object.renderType == .bubble)
                        }
                        
                        if let source = info.source, source.isChannel {
                            var range = attr.append(string: source.displayTitle, color: color, font: .medium(.text))
                            if info.author?.id != source.id {
                                let subrange = attr.append(string: " (\(info.authorTitle))", color: color, font: .medium(.text))
                                range.length += subrange.length
                            }
                            
                            let link = source.addressName == nil ? context.meUrlPrefix + "c/\(source.id.id._internalGetInt64Value())/\(info.sourceMessageId?.id != nil ? "\(info.sourceMessageId!.id)" : "")" : context.meUrlPrefix + "\(source.addressName!)/\(info.sourceMessageId?.id != nil ? "\(info.sourceMessageId!.id)" : "")"
                            let appLink = ChatHistoryLink.inApp(for: link.nsstring, context: context, peerId: nil, openInfo: chatInteraction.openInfo)
                            attr.add(link: appLink, for: range, color: color)
                            
                        } else {
                            let range = attr.append(string: info.authorTitle, color: color, font: info.author == nil ? .normal(.text) : .medium(.text))
                            
                            var linkAbility: Bool = true
                            if let channel = info.author as? TelegramChannel {
                                if channel.username == nil && channel.participationStatus != .member {
                                    linkAbility = false
                                }
                            }
                            if linkAbility, let author = info.author {
                                attr.add(link: ChatHistoryLink.peerInfo(link: "", peerId: author.id, action:nil, openChat: author.isChannel, postId: info.sourceMessageId?.id, callback:chatInteraction.openInfo), for: range, color: color)
                            } else if info.author == nil {
                                attr.add(link: LinkHooks.shared.callbackLink("hid", { _ in
                                    hiddenFwdTooltip?()
                                }), for: range, color: color)
                                
                            }
                        }
                    }
                    
                    
                    var isInstantVideo: Bool {
                        if let media = message.anyMedia as? TelegramMediaFile {
                            if media.isInstantVideo {
                                if let data = object.additionalData.transribeState {
                                    switch data {
                                    case .loading, .revealed:
                                        return false
                                    default:
                                        break
                                    }
                                }
                            }
                            return media.isInstantVideo
                        }
                        return false
                    }
                    
                    let forwardNameColor: NSColor
                    if message.forwardInfo?.psaType != nil {
                        forwardNameColor = theme.chat.greenUI(isIncoming, object.renderType == .bubble)
                    } else if isForwardScam {
                        forwardNameColor = theme.chat.redUI(isIncoming, object.renderType == .bubble)
                    } else if !hasBubble {
                        forwardNameColor = presentation.colors.grayText
                    } else if isIncoming {
                        forwardNameColor = presentation.chat.linkColor(isIncoming, object.renderType == .bubble)
                    } else {
                        forwardNameColor = presentation.chat.grayText(isIncoming || isInstantVideo, object.renderType == .bubble)
                    }
                    
                    if renderType == .bubble {
                        
                        let text: String
                        let linkString: String
                        if let psaType = message.forwardInfo?.psaType {
                            text = localizedPsa("psa.title.bubbles_new", type: psaType, args: [attr.string])
                            linkString = psaType
                        } else {
                            var fullName = attr.string
                            if let signature = message.forwardInfo?.authorSignature, message.isAnonymousMessage {
                                fullName += " (\(signature))"
                            }
                            if message.forwardInfo?.author != nil {
                                text = strings().chatBubblesForwardedFromWithPhoto(fullName)
                            } else {
                                text = strings().chatBubblesForwardedFromNew(fullName)
                            }
                            linkString = fullName
                        }
                        if !attr.string.isEmpty, let link = attr.attribute(NSAttributedString.Key.link, at: 0, effectiveRange: nil) {
                            let newAttr = NSAttributedString.initialize(string: text, color: forwardNameColor, font: .normal(.short))
                            attr = newAttr.mutableCopy() as! NSMutableAttributedString

                            
                            let range = attr.string.nsstring.range(of: linkString)
                            
                            
                            let hashRange = attr.string.nsstring.range(of: forwardKeyString)
                            if hashRange.location != NSNotFound, hashRange.max < range.min {
                                attr.addAttribute(.foregroundColor, value: NSColor.clear, range: NSMakeRange(hashRange.location + 1, hashRange.length - 1))
                                self.forwardPhotoPlaceRange = NSMakeRange(hashRange.location + 1, hashRange.length - 1)
                            }

                            if range.location != NSNotFound {
                                attr.addAttribute(.link, value: link, range: range)
                                if message.forwardInfo?.author != nil || message.forwardInfo == nil {
                                    attr.addAttribute(.font, value: NSFont.medium(.short), range: range)
                                }
                            }
                        } else {
                            let newAttr = NSAttributedString.initialize(string: text, color: forwardNameColor, font: .normal(.short))
                            attr = newAttr.mutableCopy() as! NSMutableAttributedString
                        }
                        
                    } else {
                        _ = attr.append(string: " ")
                        _ = attr.append(string: DateUtils.string(forLastSeen: info.date), color: renderType == .bubble ? forwardNameColor : presentation.colors.grayText, font: .normal(.short))
                    }

                    
                    forwardNameLayout = TextViewLayout(attr, maximumNumberOfLines: renderType == .bubble ? 2 : 1, truncationType: .end, alwaysStaticItems: true)
                    forwardNameLayout?.interactions = LinkHooks.shared.globalLinkExecutor()
                }
            }
            
            if !message.isExpiredStory, let story = message.media.first as? TelegramMediaStory, let author = message.peers[story.storyId.peerId] {
                let forwardNameColor: NSColor
                if isForwardScam {
                    forwardNameColor = theme.chat.redUI(isIncoming, object.renderType == .bubble)
                } else if !hasBubble {
                    forwardNameColor = presentation.colors.grayText
                } else if isIncoming {
                    forwardNameColor = presentation.chat.linkColor(isIncoming, object.renderType == .bubble)
                } else {
                    forwardNameColor = presentation.chat.grayText(isIncoming, object.renderType == .bubble)
                }
                
                var attr: NSMutableAttributedString = NSMutableAttributedString()
                let fullName = author.compactDisplayTitle
                
                let text = strings().chatBubblesForwardedStory(fullName)
                
                let newAttr = parseMarkdownIntoAttributedString(text, attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .normal(.short), textColor: forwardNameColor), link: MarkdownAttributeSet(font: .medium(.short), textColor: forwardNameColor), linkAttribute: { contents in
                    return (NSAttributedString.Key.link.rawValue, ChatHistoryLink.peerInfo(link: "", peerId: author.id, action: nil, openChat: false, postId: nil, callback:chatInteraction.openInfo))
                }))
                attr = newAttr.mutableCopy() as! NSMutableAttributedString

                forwardNameLayout = TextViewLayout(attr, maximumNumberOfLines: renderType == .bubble ? 2 : 1, truncationType: .end, alwaysStaticItems: true)
                forwardNameLayout?.interactions = LinkHooks.shared.globalLinkExecutor()

            }
            
            let fillName: Bool
            var rank: String?
            var rankType: AdminBadgeType = .none
            switch itemType {
            case let .Full(r, rt, header):
                rank = r
                rankType = rt
                fillName = header == .normal
            case let .Short(r, rt, header):
                rank = r
                rankType = rt
                fillName = header == .normal && theme.bubbled
            }
            
            if fillName {
                
                let canFillAuthorName: Bool = ChatRowItem.canFillAuthorName(message, chatInteraction: chatInteraction, renderType: renderType, isIncoming: isIncoming, hasBubble: hasBubble)

                if isForwardScam || canFillAuthorName {
                    self.isForwardScam = false
                }
                
                var titlePeer:Peer? = self.peer
                var title:String = self.peer?.displayTitle ?? ""
                
                
                
                if object.renderType == .list, let _ = message.forwardInfo?.psaType {
                    
                } else if let peer = message.peers[message.id.peerId] as? TelegramChannel, case let .broadcast(info) = peer.info {
                    if info.flags.contains(.messagesShouldHaveProfiles) {
                        titlePeer = message.author ?? self.peer
                        title = titlePeer?.displayTitle ?? ""
                    }
                } else if let peer = coreMessageMainPeer(message) as? TelegramChannel, case .broadcast(_) = peer.info, message.adAttribute == nil {
                    title = peer.displayTitle
                    titlePeer = peer
                }
                
                let attr:NSMutableAttributedString = NSMutableAttributedString()

                if let peer = titlePeer {
                    var nameColor:NSColor = presentation.chat.linkColor(isIncoming, object.renderType == .bubble)

                    if let _nameColor = peer.namePeerColor {
                        nameColor = context.peerNameColors.get(_nameColor).main
                    }
                    if coreMessageMainPeer(message) is TelegramChannel || coreMessageMainPeer(message) is TelegramGroup {
                        if context.peerId != peer.id {
                            if object.renderType == .bubble, message.isAnonymousMessage, !isIncoming {
                                nameColor = theme.colors.accentIconBubble_outgoing
                            } else if object.renderType == .bubble, message.author?.id != context.peerId, !isIncoming {
                                nameColor = theme.colors.accentIconBubble_outgoing
                            }
                        }
                    }

                    if message.forwardInfo?.psaType != nil, object.renderType == .list {
                        nameColor = theme.colors.greenUI
                    }

                    if message.adAttribute != nil, let author = message.author {
                        nameColor = context.peerNameColors.get(author.namePeerColor ?? .blue).main
                    }


                    if let guestAttr = message.guestChatAttribute, let bot = message.author, let address = bot.username {
                        let linkColor = theme.chat.linkColor(isIncoming, hasBubble && isBubbled)
                        let grayColor = !hasBubble ? theme.colors.grayText : theme.chat.grayText(isIncoming, object.renderType == .bubble)
                        let botRange = attr.append(string: "@" + address, color: linkColor, font: .medium(.text))
                        attr.addAttribute(NSAttributedString.Key.link, value: ChatHistoryLink.peerInfo(link: "", peerId: bot.id, action: nil, openChat: false, postId: nil, callback: chatInteraction.openInfo), range: botRange)
                        if let caller = message.peers[guestAttr.peerId] {
                            _ = attr.append(string: strings().chatRowBotForConnector, color: grayColor, font: .medium(.text))
                            _ = attr.append(string: caller.compactDisplayTitle, color: linkColor, font: .medium(.text))
                        }
                    } else {
                        if canFillAuthorName {
                            let range = attr.append(string: title, color: nameColor, font: .medium(.text))
                            if peer.id.id._internalGetInt64Value() != 0 {
                                attr.addAttribute(NSAttributedString.Key.link, value: ChatHistoryLink.peerInfo(link: "", peerId:peer.id, action:nil, openChat: peer.isChannel, postId: nil, callback: chatInteraction.openInfo), range: range)
                            } else {
                                nameHide = strings().chatTooltipHiddenForwardName
                            }
                        }


                        if let bot = message.inlinePeer, message.hasInlineAttribute, let address = bot.username {
                            if message.forwardInfo?.psaType == nil, !isBubbled || hasBubble {
                                if attr.length > 0 {
                                    _ = attr.append(string: " ")
                                }
                                _ = attr.append(string: "\(strings().chatMessageVia) ", color: !hasBubble ? theme.colors.grayText : theme.chat.grayText(isIncoming, object.renderType == .bubble), font:.medium(.text))
                                let range = attr.append(string: "@" + address, color: theme.chat.linkColor(isIncoming, hasBubble && isBubbled), font:.medium(.text))
                                attr.addAttribute(NSAttributedString.Key.link, value: LinkHooks.shared.callbackLink("@" + address, { (parameter) in
                                    chatInteraction.updateInput(with: parameter + " ")
                                }), range: range)
                            }
                        }
                    }
                    if canFillAuthorName {
                        var badge: NSAttributedString? = nil
                        if let rank = rank {
                            let badgeColor: NSColor
                            switch rankType {
                            case .owner:
                                badgeColor = premiumGradient[1]
                            case .admin:
                                badgeColor = theme.colors.greenUI
                            case .none:
                                badgeColor = !hasBubble ? theme.colors.grayText : theme.chat.grayText(isIncoming, object.renderType == .bubble)
                            }
                            badge = .initialize(string: " " + rank, color: badgeColor, font: .normal(.short))
                            self.adminBadgeIsRank = rankType != .none
                            self.adminBadgeRankType = rankType
                            self.adminBadgeColor = rankType != .none ? badgeColor : nil
                        }
                        else if ChatRowItem.authorIsChannel(message: message, account: context.account) {
                            badge = .initialize(string: " " + strings().chatChannelBadge, color: !hasBubble ? theme.colors.grayText : theme.chat.grayText(isIncoming, object.renderType == .bubble), font: .normal(.short))
                            self.adminBadgeIsRank = false
                            self.adminBadgeColor = nil
                        }
                        if let badge = badge {
                            adminBadge = TextViewLayout(badge, maximumNumberOfLines: 1, truncationType: .end, alignment: .left)
                            adminBadge?.mayItems = false
                            adminBadge?.measure(width: .greatestFiniteMagnitude)
                        }

                        if let _ = rank, let authorId = (titlePeer ?? message.author)?.id, let channel = chatInteraction.peer as? TelegramChannel {
                            let canEditTag = (authorId == context.peerId && channel.hasPermission(.editRank)) || channel.hasPermission(.manageRanks)
                            self.adminBadgeCanEdit = canEditTag
                            self.adminBadgeAuthorId = authorId
                        }

                        var boostBadge: NSMutableAttributedString? = nil
                        if let boostAttribute = message.boostAttribute {
                            boostBadge = NSMutableAttributedString()
                            boostBadge?.append(string: " \(boostAttribute.count)", color: nameColor, font: .normal(.short))
                            boostBadge?.insert(.embedded(name: boostAttribute.count > 1 ? "Icon_Boost_Indicator_Multiple" : "Icon_Boost_Indicator_Single", color: nameColor, resize: false), at: 1)
                        }
                        if let boostBadge = boostBadge {
                            self.boostBadge = TextViewLayout(boostBadge, maximumNumberOfLines: 1, truncationType: .end, alignment: .left)
                            self.boostBadge?.mayItems = false
                            self.boostBadge?.measure(width: .greatestFiniteMagnitude)
                        }
                    }
                    
                    if attr.length > 0 {
                        authorText = TextViewLayout(attr, maximumNumberOfLines: 1, truncationType: .end, alignment: .left)
                        authorText?.mayItems = false
                        authorText?.interactions = LinkHooks.shared.globalLinkExecutor()
                    }
                }

//                if let _ = message.guestChatAttribute {
//                    let badgeColor = theme.colors.greenUI
//                    let bgColor = badgeColor.withAlphaComponent(0.15)
//                    let badgeAttr = NSMutableAttributedString()
//
//                    _ = badgeAttr.append(string: "\(clown)Only visible to you", color: badgeColor, font: .medium(.short))
//                    badgeAttr.insertEmbedded(.embedded(name: "Icon_Eye_Off", color: badgeColor, resize: false), for: clown)
//                    let layout = TextViewLayout(badgeAttr, maximumNumberOfLines: 1, truncationType: .end, alignment: .left)
//                    layout.mayItems = false
//                    layout.measure(width: .greatestFiniteMagnitude)
//                    layout.generateAutoBlock(backgroundColor: bgColor, minusHeight: 0, yInset: 1)
//                    guestChatBadge = layout
//                }
            }

            let hasActiveEphemeralReplacement = message.activeEphemeralReplacementMessage != nil
            if Namespaces.Message.allEphemeral.contains(message.id.namespace) || Namespaces.Message.allWelcomeMessages.contains(message.id.namespace) || hasActiveEphemeralReplacement {
                let badgeColor = theme.colors.greenUI
                let badgeAttr = NSMutableAttributedString()
                let badgeText: String
                if isIncoming || hasActiveEphemeralReplacement {
                    badgeText = strings().welcomeMessageOnlyVisibleToYou
                } else {
                    let receiverId = message.attributes.compactMap {
                        ($0 as? EphemeralOutgoingMessageAttribute)?.botPeerId
                    }.first
                    let receiver = receiverId.flatMap { message.peers[$0] }
                    let receiverName = receiver?.addressName.flatMap { $0.isEmpty ? nil : "@\($0)" } ?? receiver?.compactDisplayTitle ?? "bot"
                    badgeText = strings().welcomeMessageOnlyVisibleTo(receiverName)
                }
                _ = badgeAttr.append(string: "\(clown)\(badgeText)", color: badgeColor, font: .medium(.short))
                badgeAttr.insertEmbedded(.embedded(name: "Icon_Eye_Off", color: badgeColor, resize: false), for: clown)
                let layout = TextViewLayout(badgeAttr, maximumNumberOfLines: 1, truncationType: .end, alignment: .left)
                layout.mayItems = false
                layout.measure(width: .greatestFiniteMagnitude)
                layout.generateAutoBlock(backgroundColor: badgeColor.withAlphaComponent(0.15), minusHeight: 0, yInset: 1)
                guestChatBadge = layout
            }
            
            let dateFormatter = DateSelectorUtil.chatDateFormatter
            let dateColor = isStateOverlayLayout ? stateOverlayTextColor : (!hasBubble ? theme.colors.grayText : theme.chat.grayText(isIncoming, object.renderType == .bubble))
            
            let dateFont: NSFont = renderType == .bubble ? .normal(.small) : .normal(.short)

            
            if let attribute = message.pendingProcessingAttribute {
                var time:TimeInterval = TimeInterval(attribute.approximateCompletionTime)
                time -= context.timeDifference
                
                let dateText = dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(time)))
                
                let attr: NSMutableAttributedString = NSAttributedString.initialize(string: strings().chatVideoProccessingMessageTime(dateText), color: dateColor, font: dateFont).mutableCopy() as! NSMutableAttributedString
                
                self.date = TextViewLayout(attr, maximumNumberOfLines: 1)
                self.date?.measure(width: .greatestFiniteMagnitude)

            } else  if message.timestamp != scheduleWhenOnlineTimestamp && message.adAttribute == nil, chatInteraction.mode.customChatContents == nil, (message.editedTime == nil || !message_primary_edited_date) {
                var time:TimeInterval = TimeInterval(message.timestamp)
                time -= context.timeDifference
                
                
                let attr: NSMutableAttributedString = NSAttributedString.initialize(string: dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(time))), color: dateColor, font: dateFont).mutableCopy() as! NSMutableAttributedString
                
                if let attribute = message.inlineBotAttribute, let peerId = attribute.peerId, let peer = message.peers[peerId] {
                    attr.insert(.initialize(string: "\(attribute.title ?? peer.displayTitle), ", color: dateColor, font: dateFont), at: 0)
                }
                
                if let repeatPeriod = message.scheduleRepeatPeriod {
                    let repeatString: String
                    switch repeatPeriod {
                    case 60:
                        repeatString = strings().chatMessageRepeat1Min
                    case 300:
                        repeatString = strings().chatMessageRepeat5Min
                    case 86400:
                        repeatString = strings().chatMessageRepeatDaily
                    case 7 * 86400:
                        repeatString = strings().chatMessageRepeatWeekly
                    case 14 * 86400:
                        repeatString = strings().chatMessageRepeatBiweekly
                    case 30 * 86400:
                        repeatString = strings().chatMessageRepeatMonthly
                    case 91 * 86400:
                        repeatString = strings().chatMessageRepeatEvery3Months
                    case 182 * 86400:
                        repeatString = strings().chatMessageRepeatEvery6Months
                    case 365 * 86400:
                        repeatString = strings().chatMessageRepeatYearly
                    default:
                        repeatString = ""
                    }

                    attr.insert(.initialize(string: repeatString + " ", color: dateColor, font: dateFont), at: 0)
                }
                
                self.date = TextViewLayout(attr, maximumNumberOfLines: 1)
                self.date?.measure(width: .greatestFiniteMagnitude)
            } else if let _ = message.adAttribute {
                let text = ""//adAttr.messageType == .recommended ? strings().chatMessageRecommended : strings().chatMessageSponsored
                let attr: NSAttributedString = .initialize(string: text, color: isStateOverlayLayout ? stateOverlayTextColor : (!hasBubble ? theme.colors.grayText : theme.chat.grayText(isIncoming, object.renderType == .bubble)), font: renderType == .bubble ? .normal(.small) : .normal(.short))
                self.date = TextViewLayout(attr, maximumNumberOfLines: 1)
                self.date?.measure(width: .greatestFiniteMagnitude)
            }

        } else {
            self.isIncoming = false
            self.hasBubble = false
        }
 
        
        
        super.init(initialSize)
        
        hiddenFwdTooltip = { [weak self] in
            guard let view = self?.view as? ChatRowView else { return }
            view.showHiddenForwardTooltip()
        }
        
        let editedAttribute = messages.compactMap({
            return $0.editedAttribute
        }).sorted(by: {
            $0.date < $1.date
        }).first
        
        
        
        if let message = message {
            
            let formatter = DateSelectorUtil.chatFullDateFormatter
            //
            var fullDate: String = message.timestamp == scheduleWhenOnlineTimestamp ? "" : formatter.string(from: Date(timeIntervalSince1970: TimeInterval(message.timestamp) - context.timeDifference))
            
            let threadId: Int64? = chatInteraction.chatLocation.threadId
            
            if let message = effectiveCommentMessage {
                for attribute in message.attributes {
                    if let attribute = attribute as? ReplyThreadMessageAttribute, attribute.count > 0 {
                        if let peer = chatInteraction.peer, peer.isSupergroup, !chatInteraction.mode.isThreadMode {
                            let attr: NSAttributedString = .initialize(string: Int(attribute.count).prettyNumber, color: isStateOverlayLayout ? stateOverlayTextColor : !hasBubble ? theme.colors.grayText : theme.chat.grayText(isIncoming, object.renderType == .bubble), font: renderType == .bubble ? .normal(.small) : .normal(.short))
                            self.replyCount = TextViewLayout(attr, maximumNumberOfLines: 1)
                        }
                        break
                    }
                }
            }
            
            if let paidStars = message.paidStarsAttribute, message.id.peerId.namespace != Namespaces.Peer.CloudUser {
                let count: Int
                switch entry {
                case let .groupedPhotos(values, _):
                    count = values.count
                case .MessageEntry:
                    count = 1
                default:
                    count = 0
                }
                let attr: NSAttributedString = .initialize(string: "\(Int64(count) * paidStars.stars.value)", color: isStateOverlayLayout ? stateOverlayTextColor : !hasBubble ? theme.colors.grayText : theme.chat.grayText(isIncoming, object.renderType == .bubble), font: renderType == .bubble ? .normal(.small) : .normal(.short))
                paidMessage = TextViewLayout(attr, maximumNumberOfLines: 1)
                paidMessage?.measure(width: .greatestFiniteMagnitude)
            }

            if let dice = message.anyMedia as? TelegramMediaDice, let tonAmount = dice.tonAmount, tonAmount > 0 {
                let tonValue = Double(tonAmount) / 1_000_000_000
                let formattedAmount = String(format: "%.2f", tonValue)
                let attr: NSAttributedString = .initialize(string: formattedAmount, color: isStateOverlayLayout ? stateOverlayTextColor : !hasBubble ? theme.colors.grayText : theme.chat.grayText(isIncoming, object.renderType == .bubble), font: renderType == .bubble ? .normal(.small) : .normal(.short))
                diceStake = TextViewLayout(attr, maximumNumberOfLines: 1)
                diceStake?.measure(width: .greatestFiniteMagnitude)
            }

            if editedAttribute != nil || message.id.namespace == Namespaces.Message.Cloud {
                if isEditMarkVisible || isUnsent, message.id.peerId != context.peerId, let editedAttribute {
                    
                    
                    var string = strings().chatMessageEdited
                    
                    if message_primary_edited_date {
                        string = strings().chatRowEdited(stringForMediumDate(timestamp: editedAttribute.date))
                    }
                                        
                    let attr: NSAttributedString = .initialize(string: string, color: isStateOverlayLayout ? stateOverlayTextColor : !hasBubble ? theme.colors.grayText : theme.chat.grayText(isIncoming, object.renderType == .bubble), font: renderType == .bubble ? .normal(.small) : .normal(.short))
                    editedLabel = TextViewLayout(attr, maximumNumberOfLines: 1)
                    editedLabel?.measure(width: .greatestFiniteMagnitude)
                }
                
                
                if let attribute = editedAttribute {
                    let formatterEdited = DateSelectorUtil.chatFullDateFormatter
                    fullDate = "\(fullDate) (\(formatterEdited.string(from: Date(timeIntervalSince1970: TimeInterval(attribute.date)))))"
                }
            } else if message.isImported, let forwardInfo = message.forwardInfo  {
                let formatter = DateSelectorUtil.chatImportedFormatter
                let text: String
                if forwardInfo.date == message.timestamp {
                    text = strings().chatMessageImportedShort
                } else {
                   text = strings().chatMessageImported(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(forwardInfo.date))))
                }
                let attr: NSAttributedString = .initialize(string: text, color: isStateOverlayLayout ? stateOverlayTextColor : !hasBubble ? theme.colors.grayText : theme.chat.grayText(isIncoming, object.renderType == .bubble), font: renderType == .bubble ? .normal(.small) : .normal(.short))
                editedLabel = TextViewLayout(attr, maximumNumberOfLines: 1)
                editedLabel?.measure(width: .greatestFiniteMagnitude)
                fullDate = strings().chatMessageImportedText + "\n\n" + fullDate
            } else if let forwardInfo = message.forwardInfo {
                let formatterEdited = DateSelectorUtil.chatFullDateFormatter
                fullDate = "\(fullDate) (\(formatterEdited.string(from: Date(timeIntervalSince1970: TimeInterval(forwardInfo.date)))))"
            }
            let replyPresentation = { [self] in ChatAccessoryPresentation(background: hasBubble ? theme.chat.backgroundColor(isIncoming, object.renderType == .bubble) : isBubbled ?  theme.colors.grayForeground : theme.colors.background, colors: theme.chat.replyTitle(self), enabledText: theme.chat.replyText(self), disabledText: theme.chat.replyDisabledText(self), quoteIcon: theme.chat.replyQuote(self), pattern: theme.chat.replyPattern(self), giftEmojiFileId: theme.chat.replyGiftEmojiId(self), app: theme) }

            for attribute in message.attributes {
                if let attribute = attribute as? ReplyMessageAttribute, let replyMessage = message.associatedMessages[attribute.messageId] {
                    
                    var ignore: Bool = false
                    if threadId == message.threadId && Int64(attribute.messageId.id) == threadId {
                        ignore = true
                    }
                    
                    if message.media.first is TelegramMediaGiveawayResults {
                        ignore = true
                    }
                    if !ignore {
                        
                        let isQuote = attribute.isQuote
                        
                        if replyMessage.isExpiredStory, let media = replyMessage.media.first as? TelegramMediaStory {
                            self.replyModel = ExpiredStoryReplyModel(message: message, storyId: media.storyId, bubbled: renderType == .bubble, context: context, presentation: replyPresentation())
                        } else {
                            self.replyModel = ReplyModel(message: message, replyMessageId: attribute.messageId, context: context, replyMessage: replyMessage, quote: isQuote ? attribute.quote : nil, autodownload: downloadSettings.isDownloable(replyMessage), presentation: replyPresentation(), translate: entry.additionalData.replyTranslate)
                        }
                        replyModel?.isSideAccessory = isBubbled && !hasBubble
                    }
                }
                if let attribute = attribute as? ReplyStoryAttribute {
                    if let story = message.associatedStories[attribute.storyId]?.get(Stories.StoredItem.self) {
                        self.replyModel = StoryReplyModel(message: message, storyId: attribute.storyId, story: story, context: context, presentation: replyPresentation())
                        replyModel?.isSideAccessory = isBubbled && !hasBubble
                    }
                }
                if let attribute = attribute as? QuotedReplyMessageAttribute, self.replyModel == nil {
                    if let attr = message.replyAttribute, message.associatedMessages[attr.messageId] == nil {
                        self.replyModel = ReplyModel(message: message, replyMessageId: message.id, context: context, replyMessage: message, quote: attribute.quote, presentation: replyPresentation(), customHeader: attribute.authorName)
                    } else if message.replyAttribute == nil {
                        self.replyModel = ReplyModel(message: message, replyMessageId: message.id, context: context, replyMessage: message, quote: attribute.quote, presentation: replyPresentation(), customHeader: attribute.authorName)
                    }
                }
                if let attribute = attribute as? ViewCountMessageAttribute {
                    let attr: NSAttributedString = .initialize(string: max(1, attribute.count).prettyNumber, color: isStateOverlayLayout ? stateOverlayTextColor : !hasBubble ? theme.colors.grayText : theme.chat.grayText(isIncoming, object.renderType == .bubble), font: renderType == .bubble ? .normal(.small) : .normal(.short))

                    self.channelViews = TextViewLayout(attr, maximumNumberOfLines: 1)
                    var author: String = ""
                    var forwardCount: Int?
                    for attr in message.attributes {
                        if let attr = attr as? AuthorSignatureMessageAttribute {
                            author = "\(attr.signature), "
                        } else if let attr = attr as? ForwardCountMessageAttribute {
                            forwardCount = attr.count
                        }
                    }

                    var statsParts: [String] = []
                    if attribute.count >= 1000 {
                        statsParts.append("\(attribute.count.separatedNumber) \(strings().chatMessageTooltipViews)")
                    }
                    if let forwardCount = forwardCount, forwardCount > 0 {
                        let shares = strings().channelStatsSharesCountOther(forwardCount).replacingOccurrences(of: "\(forwardCount)", with: forwardCount.separatedNumber)
                        statsParts.append(shares)
                    }

                    if !statsParts.isEmpty {
                        fullDate = "\(author)\(statsParts.joined(separator: ", ")), \(fullDate)"
                    } else {
                        fullDate = "\(author)\(fullDate)"
                    }
                }
               
                if let story = message.media.first as? TelegramMediaStory, message.isExpiredStory {
                    self.replyModel = ExpiredStoryReplyModel(message: message, storyId: story.storyId, bubbled: renderType == .bubble, context: context, presentation: replyPresentation())
                    replyModel?.isSideAccessory = isBubbled && !hasBubble
                } else if let storyReply = message.storyAttribute, message.isExpiredReplyStory {
                    self.replyModel = ExpiredStoryReplyModel(message: message, storyId: storyReply.storyId, bubbled: renderType == .bubble, context: context, presentation: replyPresentation())
                    replyModel?.isSideAccessory = isBubbled && !hasBubble
                }
                
                let paid: Bool
                if let invoice = message.anyMedia as? TelegramMediaInvoice {
                    paid = invoice.receiptMessageId != nil
                } else {
                    paid = false
                }
                if let attribute = attribute as? ReplyMarkupMessageAttribute, attribute.flags.contains(.inline) {
                    if message.restrictedText(context.contentSettings) == nil {
                        if !message.hasExtendedMedia {
                            let xtrAmount: Int64?
                            if let invoice = message.anyMedia as? TelegramMediaInvoice, invoice.currency == XTR {
                                xtrAmount = invoice.totalAmount
                            } else {
                                xtrAmount = nil
                            }
                            replyMarkupModel = ReplyMarkupNode(attribute.rows, attribute.flags, chatInteraction.processBotKeyboard(with: message), theme, paid: paid, xtrAmount: xtrAmount, outerCornerRadius: isBubbled ? 12 : 0, roundsTopCorners: false)
                        }
                    }
                } else if let attribute = attribute as? SuggestedPostMessageAttribute {
                    if attribute.state == nil, let _ = message.peers[message.id.peerId], isIncoming {
                        
                        let markupAttribute = attribute.replyMarkup(isIncoming: isIncoming)
                        replyMarkupModel = ReplyMarkupNode(markupAttribute.rows, markupAttribute.flags, chatInteraction.processBotKeyboard(with: message), theme, paid: paid, xtrAmount: nil, isPostSuggest: true, outerCornerRadius: isBubbled ? 12 : 0, roundsTopCorners: false)
                    }
                }
            }

            if entry.additionalData.summarize != nil {
                self.replyModel = SummarizeReplyModel(messageId: message.id, context: context, presentation: replyPresentation(), dismiss: { [weak chatInteraction] in
                    chatInteraction?.clearSummarize(message.id)
                })
                replyModel?.isSideAccessory = isBubbled && !hasBubble
            }

            if message.adAttribute == nil, chatInteraction.mode.customChatContents == nil {
                self.fullDate = fullDate
            }
        }
    }

    func tooltipCountdownText() -> String? {
        guard let attr = message?.autoremoveAttribute, let begin = attr.countdownBeginTime, let fullDate else {
            return nil
        }
        let left = Int(begin) + Int(attr.timeout) - Int(chatInteraction.interactionContext.timestamp)
        guard left >= 0 else {
            return nil
        }
        return fullDate + "\n\n" + strings().chatContextMenuAutoDelete(smartTimeleftText(left))
    }

    public init(_ initialSize:NSSize, _ chatInteraction:ChatInteraction, _ entry: ChatHistoryEntry, theme: TelegramPresentationTheme) {
        self.entry = entry
        self.context = chatInteraction.interactionContext
        self.message = entry.message
        self.chatInteraction = chatInteraction
        self.renderType = entry.renderType
        self.downloadSettings = .defaultSettings
        self.presentation = theme
        self.isIncoming = false
        self.hasBubble = false
        self._isScam = false
        self.isForwardScam = false
        self._isFake = false
        self.isForwardFake = false
        self.wpPresentation = .init(text: .clear, activity: .init(main: .clear), link: .clear, selectText: .clear, ivIcon: theme.icons.ivAudioPlay, renderType: entry.renderType, pattern: nil)
        super.init(initialSize)
    }
    
    public static func item(_ initialSize:NSSize, from entry:ChatHistoryEntry, interaction:ChatInteraction, theme: TelegramPresentationTheme) -> TableRowItem {
        
        switch entry {
        case .UnreadEntry:
            return ChatUnreadRowItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
        case .groupedPhotos:
            return ChatGroupedItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
        case .DateEntry:
            return ChatDateStickItem(initialSize, entry, interaction: interaction, theme: theme)
        case .bottom:
            return ChatHistoryBottomRowItem(initialSize, stableId: entry.stableId, bottomInset: interaction.bottomInset)
        case let .empty(_, theme):
            return GeneralRowItem(initialSize, height: theme.bubbled ? 10 : 20, stableId: entry.stableId, backgroundColor: .clear, ignoreAtInitialization: true)
        case .commentsHeader:
            return ChatCommentsHeaderItem(initialSize, entry, interaction: interaction, theme: theme)
        case .repliesHeader:
            return RepliesHeaderRowItem(initialSize, entry: entry)
        case let .topThreadInset(height, _, _):
            return GeneralRowItem(initialSize, height: height, stableId: entry.stableId, backgroundColor: .clear)
        case let .userInfo(status, peer, commonGroups, _, _, theme):
            return ChatUserInfoRowItem(initialSize, interaction, entry, settings: status, peer: peer, commonGroups: commonGroups, theme: theme)
        case .topicSeparator:
            return ChatTopicSeparatorItem(initialSize, entry, interaction: interaction, theme: theme)
        case .newThread:
            return ChatNewThreadRowItem(initialSize, entry: entry, chatInteraction: interaction, presentation: theme)
        default:
            break
        }
        
        if let message = entry.message {
            if message.attributes.contains(where: { $0 is RichTextMessageAttribute }) {
                return ChatRichTextRowItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
            }
            if message.adAttribute != nil {
                return ChatMessageItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
            } else if message.media.count == 0 || message.anyMedia is TelegramMediaWebpage {
                return ChatMessageItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
            } else {
                if message.id.peerId.namespace != Namespaces.Peer.SecretChat, message.autoclearTimeout != nil {
                    if let media = message.media.first, media is TelegramMediaImage || (media.isVideoFile && !media.isInstantVideo) {
                        return ChatServiceItem(initialSize, interaction,interaction.interactionContext, entry, theme: theme)
                    }
                }
                if message.media.first is TelegramMediaGiveawayResults {
                    return ChatGiveawayResultRowItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
                } else if message.media.first is TelegramMediaGiveaway {
                    return ChatGiveawayRowItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
                }
                if let action = message.media[0] as? TelegramMediaAction {
                   switch action.action {
                   case .giftCode:
                       return ChatGiveawayGiftRowItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
                   case .prizeStars:
                       return ChatGiveawayGiftRowItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
                   case .phoneCall:
                       return ChatCallRowItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
                   case .conferenceCall:
                       return ChatCallRowItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
//                   case .starGift:
//                       return ChatServiceStarsGiftItem(initialSize, interaction, interaction.context, entry, theme: theme)
                   default:
                       return ChatServiceItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
                   }
               } else if let file = message.media[0] as? TelegramMediaFile {
                    if file.isVideoSticker {
                        return ChatGIFMediaItem(initialSize, interaction, interaction.interactionContext,entry, theme: theme)
                    } else if file.isInstantVideo {
                        if let data = entry.additionalData.transribeState {
                            switch data {
                            case .loading, .revealed:
                                return ChatVoiceRowItem(initialSize,interaction, interaction.interactionContext,entry, theme: theme)
                            default:
                                break
                            }
                        }
                        return ChatVideoMessageItem(initialSize, interaction, interaction.interactionContext,entry, theme: theme)
                    } else if file.isVideo && !file.isAnimated {
                        return ChatMediaItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
                    } else if file.isStaticSticker {
                        return ChatMediaItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
                    } else if file.isVoice {
                        return ChatVoiceRowItem(initialSize,interaction, interaction.interactionContext, entry, theme: theme)
                    } else if file.isVideo && file.isAnimated {
                        return ChatMediaItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
                    } else if !file.isVideo && (file.isAnimated && !file.mimeType.hasSuffix("gif")) {
                        return ChatMediaItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
                    } else if file.isMusic {
                        return ChatMusicRowItem(initialSize,interaction, interaction.interactionContext, entry, theme: theme)
                    } else if file.isAnimatedSticker {
                        return ChatAnimatedStickerItem(initialSize,interaction, interaction.interactionContext, entry, theme: theme)
                    }
                    return ChatFileMediaItem(initialSize,interaction, interaction.interactionContext, entry, theme: theme)
                } else if let story = message.media[0] as? TelegramMediaStory {
                    if message.isExpiredStory && !story.isMention {
                        return ChatRowItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
                    } else {
                        if story.isMention {
                            return ChatServiceItem(initialSize, interaction,interaction.interactionContext, entry, theme: theme)
                        } else {
                            return ChatMediaItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
                        }
                    }
                } else if message.media[0] is TelegramMediaMap {
                    return ChatMapRowItem(initialSize,interaction, interaction.interactionContext, entry, theme: theme)
                } else if message.media[0] is TelegramMediaContact {
                    return ChatContactRowItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
                } else if let media = message.media[0] as? TelegramMediaInvoice {
                    if let extendedMedia = media.extendedMedia {
                        switch extendedMedia {
                        case .preview:
                            return ChatInvoiceItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
                        case .full:
                            return ChatMediaItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
                        }
                    } else {
                        return ChatInvoiceItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
                    }
                } else if message.media[0] is TelegramMediaExpiredContent {
                    return ChatServiceItem(initialSize, interaction,interaction.interactionContext, entry, theme: theme)
                } else if message.anyMedia is TelegramMediaGame {
                    return ChatMessageItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
                } else if message.anyMedia is TelegramMediaPoll {
                    return ChatPollItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
                } else if message.anyMedia is TelegramMediaTodo {
                    return ChatRowTodoItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
                } else if message.anyMedia is TelegramMediaUnsupported {
                    return ChatMessageItem(initialSize, interaction, interaction.interactionContext,entry, theme: theme)
                } else if message.anyMedia is TelegramMediaDice {
                    return ChatMediaDice(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
                } else if message.anyMedia is TelegramMediaPaidContent {
                    return ChatMediaPaidContentItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
                }
                
                return ChatMediaItem(initialSize, interaction, interaction.interactionContext, entry, theme: theme)
            }
            
        }
        
        fatalError("no item for entry")
        
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        _cachedHeight = nil

        let result = super.makeSize(width, oldWidth: oldWidth)
        isForceRightLine = false
                
        commentsBubbleData?.makeSize()
        commentsBubbleDataOverlay?.makeSize()
        
        _commentsBubbleData?.drawBorder = !isBubbleFullFilled || !captionLayouts.isEmpty
        
       
        
//        if !(self is ChatGroupedItem) {
//            for layout in captionLayouts {
//                layout.layout.dropLayoutSize()
//            }
//        }
        
        let cachedContentOffset = contentOffset
        let metadataWidth = hasBubble ? 60 : max(150, width - cachedContentOffset.x - 44 - 150)
        if let channelViews = channelViews, channelViews.constrainedWidth != metadataWidth || channelViews.layoutSize == .zero {
            channelViews.measure(width: metadataWidth)
        }
        if let replyCount = replyCount, replyCount.constrainedWidth != metadataWidth || replyCount.layoutSize == .zero {
            replyCount.measure(width: metadataWidth)
        }


        self.rightFrames = isIncomingTypingDraft ? nil : ChatRightView.Frames(self, size: NSMakeSize(.greatestFiniteMagnitude, rightHeight))

        let cachedRightSize = rightSize
        let cachedBlockWidth = blockWidth
        var widthForContent: CGFloat = cachedBlockWidth
        if previousBlockWidth != widthForContent {
            self.previousBlockWidth = widthForContent
            _contentSize = self.makeContentSize(widthForContent)
        }
        
       
        
        
        var maxContentWidth = _contentSize.width
        if hasBubble {
            maxContentWidth -= bubbleDefaultInnerInset
        }
        
        if isBubbled && isBubbleFullFilled {
            widthForContent = maxContentWidth
        } else if fixedContentSize {
            widthForContent = maxContentWidth
        }
        
        if let factCheckLayout {
            if isBubbled {
                if isBubbleFullFilled {
                    factCheckLayout.measure(for: widthForContent + defaultContentInnerInset)
                } else {
                    if let webpageLayout = (self as? ChatMessageItem)?.webpageLayout {
                        factCheckLayout.measure(for: webpageLayout.size.width)
                    } else {
                        factCheckLayout.measure(for: max(_contentSize.width, 220))
                    }
                }
            } else {
                factCheckLayout.measure(for: max(_contentSize.width, widthForContent - cachedRightSize.width))
            }
        }

        if let reactions = reactionsLayout {
            if isBubbled {
                if !hasBubble {
                    reactions.measure(for: min(320, cachedBlockWidth))
                } else if reactions.presentation.isOutOfBounds {
                    reactions.measure(for: _contentSize.width + 40)
                } else {
                    var w = widthForContent
                    if let item = self as? ChatMessageItem {
                        if item.webpageLayout != nil {
                            w = _contentSize.width
                        }
                    } else if let _ = self as? ChatGiveawayRowItem {
                        w = _contentSize.width
                    }
                    reactions.measure(for: w)
                }
            } else {
                reactions.measure(for: max(_contentSize.width, widthForContent - cachedRightSize.width))
            }
        }
    
        
        if !(self is ChatGroupedItem) {
            for layout in captionLayouts {
                layout.layout.measure(width: maxContentWidth - defaultContentInnerInset)
            }
        }
        
        for layout in captionLayouts {
            if layout.isLoading {
                layout.layout.makeImageBlock(backgroundColor: .blackTransparent)
            }
        }
        
        if let forwardNameLayout = forwardNameLayout {
            var w = widthForContent
            if isBubbled && !hasBubble {
                w = width - _contentSize.width - 85 - (monoforumState == .vertical ? 80 : 0)
            }
            let forwardWidth = min(w, 250)
            if forwardNameLayout.constrainedWidth != forwardWidth || forwardNameLayout.layoutSize == .zero {
                forwardNameLayout.measure(width: forwardWidth)
            }
        }
        
        if (forwardType == .FullHeader || forwardType == .ShortHeader) && (entry.renderType == .bubble || message?.forwardInfo?.psaType == nil), renderType == .list {
            
            let color: NSColor
            let text: String
            if let psaType = message?.forwardInfo?.psaType {
                color = presentation.chat.greenUI(isIncoming, isBubbled)
                text = localizedPsa("psa.title", type: psaType)
            } else {
                color = !hasBubble ? presentation.colors.grayText : presentation.chat.grayText(isIncoming, renderType == .bubble)
                text = strings().messagesForwardHeader
            }
            
            let attributedText = NSAttributedString.initialize(string: text, color: color, font: .normal(.text))
            if forwardHeader?.attributedString.isEqual(to: attributedText) != true {
                forwardHeader = .init(attributedText, maximumNumberOfLines: 1)
            }
            if let forwardHeader = forwardHeader, forwardHeader.constrainedWidth != .greatestFiniteMagnitude || forwardHeader.layoutSize == .zero {
                forwardHeader.measure(width: .greatestFiniteMagnitude)
            }
        } else {
            forwardHeader = nil
        }
        
        
        
        if let value = topicLinkLayout {
            if !isBubbled {
                value.measure(widthForContent)
            } else  {
                if let item = self as? ChatMessageItem, item.webpageLayout == nil && !value.isSideAccessory {
                    if isBubbled {
                        value.measure(max(cachedBlockWidth, 200))
                    } else {
                        value.measure(max(contentSize.width, 200))
                    }
                } else {
                    if !hasBubble {
                        value.measure(min(width - _contentSize.width - cachedContentOffset.x - 80, 300))
                    } else {
                        value.measure(_contentSize.width - bubbleDefaultInnerInset)
                    }
                }
            }
        }
        
        
        if !canFillAuthorName, let replyModel = replyModel, let authorText = authorText, replyModel.isSideAccessory {
            var adminWidth: CGFloat = 0
            if let adminBadge = adminBadge {
                adminWidth += adminBadge.layoutSize.width
            }
            if let boostBadge = boostBadge {
                adminWidth += boostBadge.layoutSize.width
            }
            let authorWidth = replyModel.size.width - 10 - adminWidth
            if authorText.constrainedWidth != authorWidth || authorText.layoutSize == .zero {
                authorText.measure(width: authorWidth)
            }
            
            replyModel.topOffset = authorText.layoutSize.height + 6
            replyModel.measureSize(replyModel.width, sizeToFit: replyModel.sizeToFit)
        } else {
            var adminWidth: CGFloat = 0
            if let adminBadge = adminBadge {
                adminWidth += adminBadge.layoutSize.width
            }
            if let boostBadge = boostBadge {
                adminWidth += boostBadge.layoutSize.width
            }
            var supplyOffset: CGFloat = 0
            if !isBubbled {
                supplyOffset += cachedRightSize.width
            }
            
            let authorWidth = widthForContent - adminWidth - supplyOffset
            if let authorText = authorText, authorText.constrainedWidth != authorWidth || authorText.layoutSize == .zero {
                authorText.measure(width: authorWidth)
            }

        }

        if let guestChatBadge = guestChatBadge {
            let availableWidth = max(1, widthForContent - 10)
            let hasLayout = guestChatBadge.hasBlock && guestChatBadge.layoutSize != .zero
            let fits = guestChatBadge.isPerfectSized && guestChatBadge.layoutSize.width <= widthForContent
            if !hasLayout || (!fits && guestChatBadge.constrainedWidth != availableWidth) {
                guestChatBadge.measure(width: availableWidth)
                guestChatBadge.generateAutoBlock(backgroundColor: theme.colors.greenUI.withAlphaComponent(0.15), minusHeight: 0, yInset: 1)
            }
        }
        
         if hasBubble && !isBubbleFullFilled {
            if _contentSize.width < cachedRightSize.width {
                if !(self is ChatMessageItem)  {
                    _contentSize.width = cachedRightSize.width
                } else if additionalLineForDateInBubbleState != nil {
                    _contentSize.width = cachedRightSize.width
                }
            }
        }
        

        if !isBubbled {
            if let replyModel = replyModel {
                replyModel.measureSize(widthForContent, sizeToFit: true)
                if replyModel.size.width < _contentSize.width {
                    replyModel.measureSize(_contentSize.width, sizeToFit: false)
                }
            }
        } else if let replyModel = replyModel {
            if !replyModel.isSideAccessory {
                replyModel.measureSize(max(cachedBlockWidth - bubbleDefaultInnerInset, 200), sizeToFit: true)
                let fill_size = max_reply_size_width
                if replyModel.size.width < fill_size || isBubbleFullFilled {
                    replyModel.measureSize(fill_size, sizeToFit: false)
                }
            } else {
                let bubbleFrame = ChatRowGeometry.bubbleFrame(.init(
                    rowWidth: width,
                    layoutFrame: NSMakeRect(defLeftInset, 0, bubbleFrameWidth, 0),
                    leftInset: leftInset,
                    isIncoming: isIncoming,
                    isCenteredThread: chatInteraction.mode.isThreadMode && chatInteraction.chatLocation.threadMsgId == message?.id
                ))
                let contentFrame = ChatRowGeometry.contentFrame(.init(item: self, bubbleFrame: bubbleFrame))
                let sideFrame = ChatRowGeometry.sideAccessoryFrame(.init(item: self, size: .zero, offset: 0, contentFrame: contentFrame))
                let availableWidth = max(1, isIncoming ? width - rightInset - sideFrame.minX : sideFrame.maxX - leftInset)
                let preferredWidth = _contentSize.width == 0 ? 200 : _contentSize.width - bubbleContentInset * 2
                replyModel.measureSize(min(preferredWidth, availableWidth), sizeToFit: true)
                if replyModel.size.width > availableWidth {
                    replyModel.measureSize(availableWidth, sizeToFit: false)
                }
            }
        }
        
        if isBubbled {
            replyMarkupModel?.measureSize(bubbleFrame.width - additionBubbleInset)
        } else {
            if let item = self as? ChatMessageItem {
                if item.webpageLayout != nil {
                    replyMarkupModel?.measureSize(_contentSize.width)
                } else if _contentSize.width < 200 {
                    replyMarkupModel?.measureSize(max(_contentSize.width, min(cachedBlockWidth, 320)))
                } else {
                    replyMarkupModel?.measureSize(_contentSize.width)
                }
            } else {
                 replyMarkupModel?.measureSize(_contentSize.width)
            }
        }
        
        
        return result
    }
    
    deinit {
        var bp:Int = 0
        bp += 1
    }
    
    public var bubbleContentInset: CGFloat {
        return 11
    }
    
    public var additionBubbleInset: CGFloat {
        return 6
    }
    
    public var insetBetweenContentAndDate: CGFloat {
        return 10
    }
    
    public var maxTitleWidth: CGFloat {
        let nameWidth:CGFloat
        if hasBubble {
            nameWidth = (authorText?.layoutSize.width ?? 0) + statusSize + (adminBadge?.layoutSize.width ?? 0) + (boostBadge?.layoutSize.width ?? 0)
        } else {
            nameWidth = 0
        }

        let forwardWidth = hasBubble ? (forwardNameLayout?.layoutSize.width ?? 0) + forwardStatusSize + (isPsa ? 30 : 0) : 0
        
        let replyWidth = min(hasBubble ? (replyModel?.size.width ?? 0) : 0, 200)
        
        let topicReplyWidth = min(hasBubble ? (topicLinkLayout?.size.width ?? 0) : 0, 200)

        let badgeWidth = hasBubble ? (guestChatBadge?.layoutSize.width ?? 0) : 0

        return max(nameWidth, forwardWidth, replyWidth, topicReplyWidth, badgeWidth)//min(max(max(nameWidth, forwardWidth), replyWidth), contentSize.width)
    }
    
    public var hasStatus: Bool {
        if let peer = self.peer, let message = self.message, PremiumStatusControl.hasControl(peer, left: false) {
            if authorText != nil, let peer = message.peers[message.id.peerId] {
                if peer.isGroup || peer.isSupergroup || peer.isGigagroup {
                    return true
                }
            }
        }
        return false
    }
    
    public var statusSize: CGFloat {
        if let peer = self.peer, hasStatus, let controlSize = PremiumStatusControl.controlSize(peer, false, left: false) {
            return controlSize.width
        }
        return 0
    }
    public var forwardStatusSize: CGFloat {
        if let peer = self.peer, false, let controlSize = PremiumStatusControl.controlSize(peer, false, left: false) {
            return controlSize.width
        }
        return 0
    }
    
    public func statusLayer(_ cached: PremiumStatusLayer?, animated: Bool) -> PremiumStatusLayer? {
        if let peer = peer, let attr = authorText?.attributedString, !attr.string.isEmpty, hasStatus {
            if let color = attr.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor {
                return PremiumStatusLayer.layer(peer, account: context.account, inlinePacksContext: context.inlinePacksContext, left: false, isSelected: false, color: color, cached: cached, animated: animated)
            }
        }
        return nil
    }

    public func status(_ cached: PremiumStatusControl?, animated: Bool) -> PremiumStatusControl? {
        if let peer = peer, let attr = authorText?.attributedString, !attr.string.isEmpty, hasStatus {
            if let color = attr.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor {
                return PremiumStatusControl.control(peer, account: context.account, inlinePacksContext: context.inlinePacksContext, left: false, isSelected: false, color: color, cached: cached, animated: animated)
            }
        }
        return nil
    }
    
    /// Width-only computation for the bubble. Independent of `self.height`
    /// so it can be called during `makeSize` without triggering the
    /// height-cache materialization (the full `bubbleFrame` reads `height`
    /// for its `rect.size.height` seed).
    public var bubbleFrameWidth: CGFloat {
        let nameWidth: CGFloat
        if hasBubble {
            nameWidth = ((authorText?.layoutSize.width ?? 0) + 8) + statusSize + (adminBadge?.layoutSize.width ?? 0) + (boostBadge?.layoutSize.width ?? 0)
        } else {
            nameWidth = 0
        }

        let forwardWidth = hasBubble ? (forwardNameLayout?.layoutSize.width ?? 0) + forwardStatusSize + (isPsa ? 30 : 0) : 0
        let replyWidth: CGFloat = hasBubble ? (replyModel?.size.width ?? 0) : 0
        let topicLinkWidth: CGFloat = hasBubble ? (topicLinkLayout?.size.width ?? 0) : 0
        let badgeWidth: CGFloat = hasBubble ? (guestChatBadge?.layoutSize.width ?? 0) : 0

        var width = contentSize.width

        if additionalLineForDateInBubbleState == nil && rightSize.width > 0 {
            if let lastLine = lastLineContentWidth {
                if lastLine.single {
                    width = max(width, lastLine.width)
                    if width + rightSize.width < blockWidth {
                        let effective = lastLine.width + rightSize.width
                        if effective > contentSize.width {
                            width += rightSize.width + insetBetweenContentAndDate + bubbleContentInset * 2
                        } else {
                            width += bubbleDefaultInnerInset
                        }
                    } else {
                        let effective = lastLine.width + rightSize.width + insetBetweenContentAndDate
                        let add = effective - width
                        if add > 0 {
                            width += add
                        }
                        width += bubbleDefaultInnerInset
                    }
                } else {
                    width += bubbleDefaultInnerInset
                }
            } else {
                width += bubbleDefaultInnerInset
            }
        } else {
            width += bubbleDefaultInnerInset
        }

        width = max(nameWidth + bubbleDefaultInnerInset, width)
        width = max(width, replyWidth + bubbleDefaultInnerInset)
        width = max(width, forwardWidth + bubbleDefaultInnerInset)
        width = max(width, topicLinkWidth + bubbleDefaultInnerInset)
        width = max(width, badgeWidth + bubbleDefaultInnerInset)

        if let reactions = reactionsLayout, !reactions.presentation.isOutOfBounds {
            width = max(reactions.size.width + bubbleDefaultInnerInset, width)
        }

        if let factCheckLayout = factCheckLayout {
            width = max(factCheckLayout.size.width + bubbleDefaultInnerInset, width)
        }

        if let commentsBubbleData = commentsBubbleData {
            width = max(width, commentsBubbleData.size(hasBubble, false).width + (isBubbled ? 0 : 10))
        }

        return width
    }

    public var bubbleFrame: NSRect {
        var rect = NSMakeRect(defLeftInset, 2, bubbleFrameWidth, height - 4)

        if isBubbled, let replyMarkup = replyMarkupModel {
            rect.size.height -= (replyMarkup.precomputedHeight + defaultReplyMarkupInset)
        }

        if let reactions = self.reactionsLayout {
            if reactions.presentation.isOutOfBounds {
                rect.size.height -= defaultReactionsInset
                rect.size.height -= reactions.size.height
            }
        }

        return rect
    }
    
    public func upsideContentOffset(_ base: NSPoint, hasUpsideSomething: Bool) -> NSPoint {
        var offset = base

        if hasBubble, isBubbleFullFilled, !hasUpsideSomething {
            offset.y -= (defaultContentInnerInset )
        } else if hasBubble, !isBubbleFullFilled, hasUpsideSomething {
            offset.y += defaultContentInnerInset
        } else if hasBubble, isBubbleFullFilled, hasUpsideSomething {
            offset.y += topInset
        }
        return offset
    }
    
    public func fullFilledBubbleFrame(_ base: NSRect, mediaBubbleCornerInset: CGFloat) -> NSRect {
        var frame = base

        if isBubbleFullFilled {
            frame.size.width = contentSize.width + additionBubbleInset
            if hasBubble {
                frame.size.width += mediaBubbleCornerInset * 2
            }
        }
        return frame
    }

    
    
    /// Static so a subclass can answer it before `super.init` — the layout overrides it drives are
    /// consulted from inside `ChatRowItem.init`, long before `self.message` exists.
    public static func isUnsupported(_ message: Message?) -> Bool {
        guard let message = message else {
            return false
        }
        // A rich message (RichTextMessageAttribute) carries its content in the attribute and is sent with
        // empty text + no `message.media`; it is rendered by ChatRichTextRowItem (InstantPage V2), so it is
        // NOT an unsupported/empty message and must not show the "please update" placeholder + button.
        if message.attributes.contains(where: { $0 is RichTextMessageAttribute }) {
            return false
        }
        guard message.text.isEmpty else {
            return false
        }
        // Media this build cannot parse is unsupported whoever sent it. `inlinePeer` is non-nil for every
        // message in a bot chat, so it may only gate the weaker case below — a message that is merely
        // empty, which upstream leaves blank there.
        if message.anyMedia is TelegramMediaUnsupported {
            return true
        }
        return message.media.isEmpty && message.inlinePeer == nil
    }

    public var unsupported: Bool {
        return ChatRowItem.isUnsupported(self.message)
    }
    
    public var isBigEmoji: Bool {
        return false
    }
    
    public var additionalLineForDateInBubbleState: CGFloat? {

        if unsupported {
            return rightSize.height
        }
        if isBigEmoji {
            return rightSize.height
        }
        if message?.isExpiredStory == true {
             return rightSize.height / 2
        }
  
        if let lastLine = lastLineContentWidth {
            if lastLine.single && !isBubbleFullFilled {
                if contentOffset.x + lastLine.width + (rightSize.width + insetBetweenContentAndDate) > blockWidth {
                    return rightSize.height
                } else {
                    return nil
                }
            } else {
                if max(realContentSize.width, maxTitleWidth) < lastLine.width + (rightSize.width + insetBetweenContentAndDate) {
                    return rightSize.height
                } else {
                    return nil
                }
            }
        }
        return isForceRightLine ? rightSize.height : nil
    }
    
    public func deleteMessage() {
        _ = context.account.postbox.transaction { [weak message] transaction -> Void in
            if let message = message {
                if let _ = message.groupingKey {
                    let messages = transaction.getMessageGroup(message.id)
                    if let messages = messages {
                        transaction.deleteMessages(messages.map { $0.id }, forEachMedia: { media in
                            
                        })
                    }
                } else {
                    transaction.deleteMessages([message.id], forEachMedia: { media in
                        
                    })
                }
                
            }
        }.start()
    }
    
    public func openTopic() {
        if let message = message, let threadId = message.threadId {
            if chatInteraction.mode == .preview {
                chatInteraction.previewTopic(threadId)
                return
            }
            let isLog = chatInteraction.isLogInteraction
            _ = (ChatHistoryUIHooks.shared.openTopic(threadId, chatInteraction.peerId, context, isLog ? nil : message.id) |> take(1)).start()
        }
    }
    
    public func openForwardInfo() {
        if let author = message?.forwardInfo?.author {
            chatInteraction.openInfoFromMessage(author.id, false, nil, nil, message: message)
        }
    }
    
    public func openInfo() {
        switch chatInteraction.chatLocation {
        case .peer, .thread:
            if let peer = peer {
                let messageId: MessageId?
                if chatInteraction.isGlobalSearchMessage {
                    messageId = self.message?.id
                } else if case .searchHashtag = chatInteraction.mode.customChatContents?.kind {
                    messageId = self.message?.id
                } else {
                    messageId = nil
                }
                if let message = message {
                    context.engine.messages.ensureMessagesAreLocallyAvailable(messages: [.init(message)])
                }
                if peer.id == self.message?.id.peerId, messageId == nil {
                    chatInteraction.openInfoFromMessage(peer.id, false, nil, nil, message: message)
                } else {
                    chatInteraction.openInfoFromMessage(peer.id, !(peer is TelegramUser) || messageId != nil, messageId, nil, message: message)
                }
            }
        }
        
    }
    
    public func toggleSelect() {
        if let message = self.message {
            chatInteraction.withToggledSelectedMessage({ current in
                return current.withToggledSelectedMessage(message.id)
            })
        }
       
    }
    
    public func resendMessage(_ ids: [MessageId]) {
       _ = resendMessages(account: context.account, messageIds: ids).start()
    }
    public func resendFailed(_ messageId: MessageId) {
        if Namespaces.Message.allWelcomeMessages.contains(messageId.namespace) || Namespaces.Message.allEphemeral.contains(messageId.namespace) {
            let _ = chatInteraction.interactionContext.engine.messages.retryEphemeralOutgoingMessage(messageId: messageId).startStandalone()
            return
        }
        let signal = chatInteraction.interactionContext.account.postbox.transaction { transaction -> [MessageId] in
            return transaction.getMessageFailedGroup(messageId)?.compactMap({$0.id}) ?? []
        } |> deliverOnMainQueue

        
        _ = signal.start(next: { [weak self] ids in
            guard let context = self?.chatInteraction.interactionContext else {
                return
            }
            if !ids.isEmpty {
                
                verifyAlert_button(for: context.window, header: strings().alertSendErrorHeader, information: strings().alertSendErrorText, ok: strings().alertSendErrorResend, option: strings().alertSendErrorDelete, successHandler: { result in
                    switch result {
                    case .basic:
                        self?.resendMessage([messageId])
                    case .thrid:
                        if ids.count > 1 {
                            self?.resendMessage(ids)
                        } else {
                            self?.deleteMessage()
                        }
                    }
                })
                
//                    default:
//                        break
//                    }
//                })
            }
        })
    }
    
    public func makeContentSize(_ width:CGFloat) -> NSSize {
        
        return NSZeroSize
    }
    
    public override func viewClass() -> AnyClass {
        return ChatRowView.self
    }
    
    public func boost(morphSource: (() -> NSView?)? = nil) {
        if let peerId = self.message?.id.peerId {
            let context = self.context
            
            let signal: Signal<(Peer, ChannelBoostStatus?, MyBoostStatus?)?, NoError> = context.account.postbox.loadedPeerWithId(peerId) |> mapToSignal { value in
                return combineLatest(context.engine.peers.getChannelBoostStatus(peerId: value.id), context.engine.peers.getMyBoostStatus()) |> map {
                    (value, $0, $1)
                }
            }
            _ = showModalProgress(signal: signal, for: context.window).start(next: { value in
                if let value = value, let boosts = value.1 {
                    showModal(with: BoostChannelModalController(context: context, peer: value.0, boosts: boosts, myStatus: value.2), for: context.window, morphSource: morphSource)
                } else {
                    alert(for: context.window, info: strings().unknownError)
                }
            })
        }
    }
    
    public func adminBadgeInteraction(_ view: NSView) {
        let context = self.context

        if adminBadgeCanEdit, let authorId = adminBadgeAuthorId, let channel = chatInteraction.peer as? TelegramChannel {
            let peerId = channel.id
            let fetchParticipant = context.peerChannelMemberCategoriesContextsManager.fetchParticipant(peerId: peerId, participantId: authorId)
            _ = (showModalProgress(signal: fetchParticipant, for: context.window)).start(next: { [weak self, weak view] rendered in
                guard let self, let rendered = rendered else { return }
                showModal(with: ChatHistoryUIHooks.shared.makeChannelParticipantControllerObserved(self.context, peerId, rendered), for: self.context.window, morphSource: { [weak view] in view })
            })
        } else {
            let tag = adminBadge?.attributedString.string.trimmingCharacters(in: .whitespaces) ?? ""
            let authorName = message?.author?.compactDisplayTitle ?? ""
            let groupName = chatInteraction.peer?.compactDisplayTitle ?? ""
            ChatNavigationHooks.shared.showUserTagInfoObserved(context, tag, authorName, groupName, adminBadgeRankType, context.window)
        }
    }

    public var accessibilityModel: ChatMessageAccessibility? {
        return accessibilityModel(details: true)
    }

    private var accessibilityAnnouncesAuthor: Bool {
        let chatPeer = self.peer ?? message.flatMap { $0.peers[$0.id.peerId] }
        if chatPeer is TelegramGroup {
            return true
        }
        if let channel = chatPeer as? TelegramChannel, case .group = channel.info {
            return true
        }
        return false
    }

    private var accessibilitySelected: Bool? {
        guard let message = message, let selection = chatInteraction.presentation.selectionState else {
            return nil
        }
        return selection.selectedIds.contains(message.id)
    }

    private func accessibilityModel(details: Bool) -> ChatMessageAccessibility? {
        guard let message = message else {
            return nil
        }
        let accountPeerId = context.peerId
        let incoming = message.effectivelyIncoming(accountPeerId)
        let kind = accessibilityKind
        let announceAuthor = accessibilityAnnouncesAuthor
        var reply: ChatMessageAccessibility.Reply?
        if let attribute = message.replyAttribute, let replied = message.associatedMessages[attribute.messageId] {
            var text = ""
            if details {
                let repliedKind = ChatMessageAccessibility.kind(for: replied)
                if case let .text(value) = repliedKind {
                    text = value
                } else {
                    text = ChatMessageAccessibility(kind: repliedKind, isIncoming: true, authorName: nil, announceAuthor: false, caption: nil, date: "", status: .none).label
                }
            }
            reply = .init(authorName: replied.author?.displayTitle, isIncoming: replied.effectivelyIncoming(accountPeerId), text: text)
        }
        var forward: ChatMessageAccessibility.Forward?
        if let info = message.forwardInfo {
            if info.author?.id == accountPeerId {
                forward = .you
            } else if let name = info.author?.displayTitle ?? info.authorSignature {
                forward = .from(name)
            }
        }
        guard details else {
            return ChatMessageAccessibility(kind: kind, isIncoming: incoming, authorName: message.author?.displayTitle, announceAuthor: announceAuthor, caption: nil, date: "", status: .none, reply: reply, forward: forward, pluralRecipients: announceAuthor)
        }
        let status: ChatMessageAccessibility.Status
        if incoming {
            status = .none
        } else if isFailed {
            status = .failed
        } else if isUnsent {
            status = .sending
        } else {
            let consumed = message.attributes.compactMap { $0 as? ConsumableContentMessageAttribute }.first?.consumed
            status = .sent(read: isRead, played: ChatMessageAccessibility.isConsumable(kind) ? (consumed ?? false) : nil)
        }
        let date = ChatMessageAccessibility.dateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(message.timestamp)))
        return ChatMessageAccessibility(kind: kind, isIncoming: incoming, authorName: message.author?.displayTitle, announceAuthor: announceAuthor, caption: ChatMessageAccessibility.caption(for: message, kind: kind), date: date, status: status, reply: reply, forward: forward, isSelected: accessibilitySelected, pluralRecipients: announceAuthor)
    }

    open var accessibilityKind: ChatMessageAccessibility.Kind {
        guard let message = message else {
            return .text("")
        }
        return ChatMessageAccessibility.kind(for: message)
    }

    open override var accessibilityHasContent: Bool {
        return message != nil
    }

    open override var accessibilityLabel: String? {
        return accessibilityModel(details: false)?.label
    }

    open override var accessibilityValue: String? {
        return accessibilityModel(details: true)?.value
    }

    open override var accessibilityHelp: String? {
        guard message != nil else {
            return nil
        }
        return ChatMessageAccessibility(kind: accessibilityKind, isIncoming: true, authorName: nil, announceAuthor: false, caption: nil, date: "", status: .none, isSelected: accessibilitySelected).help
    }

    open override func accessibilityPerformPress() -> Bool {
        guard chatInteraction.presentation.selectionState != nil, isSelectable else {
            return false
        }
        let ids = messages.map { $0.id }
        guard !ids.isEmpty else {
            return false
        }
        chatInteraction.withToggledSelectedMessage({ current in
            let select = !ids.allSatisfy { current.isSelectedMessageId($0) }
            return ids.reduce(current, { current, id in
                if current.isSelectedMessageId(id) != select {
                    return current.withToggledSelectedMessage(id)
                }
                return current
            })
        })
        return true
    }

    open override var accessibilityCustomActions: [NSAccessibilityCustomAction]? {
        guard message != nil, chatInteraction.presentation.selectionState == nil else {
            return nil
        }
        var actions: [NSAccessibilityCustomAction] = []
        if chatInteraction.presentation.canReplyInRestrictedMode {
            actions.append(NSAccessibilityCustomAction(name: strings().voiceOverMessageContextReply, handler: { [weak self] in
                return self?.replyAction() ?? false
            }))
        }
        actions.append(NSAccessibilityCustomAction(name: strings().voiceOverMessageContextOpenMessageMenu, handler: { [weak self] in
            return self?.view?.accessibilityPerformShowMenu() ?? false
        }))
        return actions
    }

    public func replyAction() -> Bool {
        if chatInteraction.presentation.canReplyInRestrictedMode, chatInteraction.chatLocation.threadMsgId != effectiveCommentMessage?.id, let message = message {
            chatInteraction.setupReplyMessage(message, .init(messageId: message.id, quote: nil, innerSubject: nil))
            return true
        }
        return false
    }
    public func editAction() -> Bool {
         if chatInteraction.presentation.state == .normal || chatInteraction.presentation.state == .editing, chatInteraction.chatLocation.threadMsgId != effectiveCommentMessage?.id {
            if let message = message, canEditMessage(message, chatInteraction: chatInteraction, context: context) {
                chatInteraction.beginEditingMessage(message)
                return true
            }
        }
        return false
    }
    public func forwardAction() -> Bool {
        if chatInteraction.presentation.state != .selecting, let message = message {
            if canForwardMessage(message, chatInteraction: chatInteraction) {
                chatInteraction.forwardMessages([message])
                return true
            }
        }
        return false
    }
    
    public func reactAction() -> Bool {
        if canReact {
            
            
            
            let context = self.context
            let value = ChatHistoryUIHooks.shared.reactionSettings(context).quickReaction
            let message = self.message
            
            guard let message = message else {
                return false
            }
            
            var reaction: MessageReaction.Reaction?
            
            let messageId = message.id
            let builtinEnabled = self.entry.additionalData.reactions?.enabledValues ?? []
            let allowed = chatInteraction.presentation.allowedReactions
            if let allowed = allowed {
                switch allowed {
                case .all:
                    switch value {
                    case .builtin:
                        reaction = value
                    case .custom:
                        reaction = context.isPremium ? value : builtinEnabled.first
                    case .stars:
                        break
                    }
                case let .limited(array):
                    if array.contains(value) {
                        reaction = value
                    } else {
                        reaction = builtinEnabled.first(where: { array.contains($0) })
                    }
                case .empty:
                    break
                }
            } else {
                switch value {
                case .custom:
                    reaction = context.isPremium ? value : builtinEnabled.first
                case .builtin:
                    reaction = value
                case .stars:
                    break
                }
            }
            if let reaction = reaction {
                if context.isFrozen {
                    ChatInterfaceHooks.shared.freezeAlert(context)
                } else {
                    context.reactions.react(messageId, values: ChatHistoryUIHooks.shared.messageNewReactions(message, reaction.toUpdate(), context.peerId == message.id.peerId))
                }
            }
        }
        return false
    }
    
    public override var menuAdditionView: Signal<Window?, NoError> {
        if canReact {
            
            let context = self.context
            
            guard let message = self.message, let peer = chatInteraction.presentation.mainPeer else {
                return .single(nil)
            }
            let peerId = self.chatInteraction.peerId
            let openSavedTagsPremium: () -> Void = {
                prem(with: PremiumBoardingController(context: context, source: .saved_tags, openFeatures: true), for: context.window)
            }
            
            let builtin = context.reactions.stateValue
            let peerAllowed: Signal<PeerAllowedReactions?, NoError> = getCachedDataView(peerId: peerId, postbox: context.account.postbox)
            |> map { cachedData in
                if let cachedData = cachedData as? CachedGroupData {
                    return cachedData.reactionSettings.knownValue?.allowedReactions
                } else if let cachedData = cachedData as? CachedChannelData {
                    return cachedData.reactionSettings.knownValue?.allowedReactions
                } else {
                    return nil
                }
            }
            |> take(1)
            
            let starsAllowed: Signal<Bool?, NoError> = getCachedDataView(peerId: peerId, postbox: context.account.postbox)
            |> map { cachedData in
                if let cachedData = cachedData as? CachedGroupData {
                    return cachedData.reactionSettings.knownValue?.starsAllowed
                } else if let cachedData = cachedData as? CachedChannelData {
                    return cachedData.reactionSettings.knownValue?.starsAllowed
                } else {
                    return nil
                }
            }
            |> take(1)
            
            let maximumReactionsLimit: Signal<Int32?, NoError> = getCachedDataView(peerId: peerId, postbox: context.account.postbox)
            |> map { cachedData in
                if let cachedData = cachedData as? CachedChannelData {
                    return cachedData.reactionSettings.knownValue?.maxReactionCount
                } else {
                    return nil
                }
            }
            |> take(1)

            
            let isTags = context.peerId == peerId

            
            
            let reactions:Signal<[RecentReactionItem], NoError> = context.diceCache.top_reactions |> map { view in
                
                var recentReactionsView: OrderedItemListView?
                var topReactionsView: OrderedItemListView?
                var defaultTagReactions: OrderedItemListView?
                for orderedView in view.orderedItemListsViews {
                    if orderedView.collectionId == Namespaces.OrderedItemList.CloudRecentReactions {
                        recentReactionsView = orderedView
                    } else if orderedView.collectionId == Namespaces.OrderedItemList.CloudTopReactions {
                        topReactionsView = orderedView
                    } else if orderedView.collectionId == Namespaces.OrderedItemList.CloudDefaultTagReactions {
                        defaultTagReactions = orderedView
                    }
                }
                var recentReactionsItems:[RecentReactionItem] = []
                var topReactionsItems:[RecentReactionItem] = []
                var defaultTagReactionsItems:[RecentReactionItem] = []

                if let recentReactionsView = recentReactionsView {
                    for item in recentReactionsView.items {
                        guard let item = item.contents.get(RecentReactionItem.self) else {
                            continue
                        }
                        recentReactionsItems.append(item)
                    }
                }
                if let defaultTagReactions = defaultTagReactions {
                    for item in defaultTagReactions.items {
                        guard let item = item.contents.get(RecentReactionItem.self) else {
                            continue
                        }
                        defaultTagReactionsItems.append(item)
                    }
                }
                if let topReactionsView = topReactionsView {
                    for item in topReactionsView.items {
                        guard let item = item.contents.get(RecentReactionItem.self) else {
                            continue
                        }
                        topReactionsItems.append(item)
                    }
                }
                if !defaultTagReactionsItems.isEmpty, isTags {
                    return defaultTagReactionsItems
                }
                return topReactionsItems.filter { value in
                    if context.isPremium {
                        return true
                    } else {
                        if case .custom = value.content {
                            return false
                        } else {
                            return true
                        }
                    }
                }
            }
            
            
            let tagsThreadId = chatInteraction.chatLocation.threadId
            let orderedReactions: Signal<[RecentReactionItem], NoError>
            if isTags {
                orderedReactions = reactions |> mapToSignal { defaults -> Signal<[RecentReactionItem], NoError> in
                    return context.engine.data.get(TelegramEngine.EngineData.Item.Messages.SavedMessageTagStats(peerId: context.peerId, threadId: tagsThreadId))
                    |> mapToSignal { stats -> Signal<[RecentReactionItem], NoError> in
                        let used = stats.filter { $0.value > 0 }.sorted(by: { lhs, rhs in
                            if lhs.value != rhs.value {
                                return lhs.value > rhs.value
                            }
                            return lhs.key < rhs.key
                        }).map(\.key)
                        var fileIds: [Int64] = []
                        for reaction in used {
                            if case let .custom(fileId) = reaction, !fileIds.contains(fileId) {
                                fileIds.append(fileId)
                            }
                        }
                        return context.engine.stickers.resolveInlineStickers(fileIds: fileIds)
                        |> map { files -> [RecentReactionItem] in
                            var result: [RecentReactionItem] = []
                            for reaction in used {
                                switch reaction {
                                case let .builtin(emoji):
                                    result.append(RecentReactionItem(.builtin(emoji)))
                                case let .custom(fileId):
                                    if let file = files[fileId] {
                                        result.append(RecentReactionItem(.custom(TelegramMediaFile.Accessor(file))))
                                    }
                                case .stars:
                                    break
                                }
                            }
                            let reactionKey:(RecentReactionItem) -> String = { item in
                                switch item.content {
                                case let .builtin(emoji):
                                    return "b" + emoji
                                case let .custom(file):
                                    return "c\(file.fileId.id)"
                                case .stars:
                                    return "s"
                                }
                            }
                            var existing = Set(result.map(reactionKey))
                            for item in defaults where existing.insert(reactionKey(item)).inserted {
                                result.append(item)
                            }
                            return result
                        }
                    }
                }
            } else {
                orderedReactions = reactions
            }

            let signal = combineLatest(queue: .mainQueue(), builtin, peerAllowed, orderedReactions, maximumReactionsLimit, starsAllowed)
            |> take(1)

            let canApplyReaction: () -> Bool = { [weak self] in self?.canReact == true }

            return (signal) |> map { builtin, peerAllowed, reactions, maximumReactionsLimit, starsAllowed in
                let enabled = builtin?.enabled ?? []

                var available:[ContextReaction] = []
                
                let allowed = peerAllowed
                
                var accessToAll: Bool
                
                let isSelected:(MessageReaction.Reaction)->Bool = { reaction in
                    return message.effectiveReactions(isTags: isTags)?.contains(where: { $0.value == reaction && $0.isSelected }) ?? false
                }

                if isTags {
                    accessToAll = true
                } else if peer.isChannel {
                   accessToAll = false
                } else if let peerAllowed = peerAllowed {
                    switch peerAllowed {
                    case .all:
                        accessToAll = true
                    case .limited, .empty:
                        accessToAll = false
                    }
                } else {
                    accessToAll = true
                }
                
                if !accessToAll {
                    if let reactions = builtin {
                        if let allowed = allowed {
                            switch allowed {
                            case .all:
                                available = reactions.enabled.map {
                                    .builtin(value: $0.value, staticFile: $0.staticIcon._parse(), selectFile: $0.selectAnimation._parse(), appearFile: $0.appearAnimation._parse(), isSelected: isSelected($0.value))
                                }
                            case let .limited(array):
                                available = array.compactMap { reaction in
                                    switch reaction {
                                    case .builtin:
                                        if let first = reactions.enabled.first(where: { $0.value == reaction }) {
                                            return .builtin(value: first.value, staticFile: first.staticIcon._parse(), selectFile: first.selectAnimation._parse(), appearFile: first.appearAnimation._parse(), isSelected: isSelected(reaction))
                                        } else {
                                            return nil
                                        }
                                    case let .custom(fileId):
                                        return .custom(value: reaction, fileId: fileId, nil, isSelected: isSelected(reaction))
                                    case .stars:
                                        return nil
                                    }
                                }
                            case .empty:
                                available = []
                            }
                        } else {
                            available = []
                        }
                    }
                } else {
                    available = reactions.compactMap { value in
                        switch value.content {
                        case let .builtin(emoji):
                            if let generic = enabled.first(where: { $0.value.string == emoji }) {
                                return .builtin(value: generic.value, staticFile: generic.staticIcon._parse(), selectFile: generic.selectAnimation._parse(), appearFile: generic.appearAnimation._parse(), isSelected: isSelected(generic.value))
                            } else {
                                return nil
                            }
                        case let .custom(file):
                            let fileId = file.fileId.id
                            return .custom(value: .custom(fileId), fileId: fileId, file._parse(), isSelected: isSelected(.custom(fileId)))
                        case .stars:
                            return nil
                        }
                    }
                }
                
                var uniqueLimit: Int = .max
                
                if let maximumReactionsLimit = maximumReactionsLimit {
                    uniqueLimit = Int(maximumReactionsLimit)
                } else if let value = context.appConfiguration.data?["reactions_uniq_max"] as? Double {
                    uniqueLimit = Int(value)
                }
                
                            
                if let reactions = message.effectiveReactions(isTags: isTags), reactions.count >= uniqueLimit {
                    available = reactions.compactMap { reaction in
                        switch reaction.value {
                        case let .custom(fileId):
                            if !accessToAll {
                                let mediaId = MediaId(namespace: Namespaces.Media.CloudFile, id: fileId)
                                return .custom(value: reaction.value, fileId: fileId, message.associatedMedia[mediaId] as? TelegramMediaFile, isSelected: isSelected(reaction.value))
                            } else {
                                return nil
                            }
                        case .builtin:
                            if let generic = enabled.first(where: { $0.value == reaction.value }) {
                                return .builtin(value: generic.value, staticFile: generic.staticIcon._parse(), selectFile: generic.selectAnimation._parse(), appearFile: generic.appearAnimation._parse(), isSelected: isSelected(reaction.value))
                            } else {
                                return nil
                            }
                        case .stars:
                            return nil
                        }
                    }
                    accessToAll = false
                }
                
                if let starsAllowed, starsAllowed {
                    available.insert(.stars(file: LocalAnimatedSticker.premium_reaction_6.file, isSelected: isSelected(.stars)), at: 0)
                }
                
                guard !available.isEmpty else {
                    return nil
                }
                
                
                if accessToAll {
                    available = Array(available.prefix(7))
                }
                
                if isTags, !context.isPremium {
                   accessToAll = false
                }
                
                
                let width = ContextAddReactionsListView.width(for: available.count, maxCount: 7, allowToAll: accessToAll)
                let aboveText: String?
                if isTags {
                    if context.isPremium {
                        aboveText = strings().chatReactionsTagMessage
                    } else {
                        aboveText = strings().chatReactionsTagMessagePremium
                    }
                } else {
                    aboveText = nil
                }
                
                let w_width = width + 20 + (accessToAll ? 0 : 0)
                
                let aboveLayout: TextViewLayout?
                if let aboveText = aboveText {
                    let color = theme.colors.darkGrayText.withAlphaComponent(0.8)
                    let link = theme.colors.link.withAlphaComponent(0.8)
                    let attributed = parseMarkdownIntoAttributedString(aboveText, attributes: .init(body: .init(font: .normal(.text), textColor: color), bold: .init(font: .medium(.text), textColor: color), link: .init(font: .normal(.text), textColor: link), linkAttribute: { link in
                        return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink("", { _ in
                            openSavedTagsPremium()
                        }))
                    })).detectBold(with: .medium(.text))
                    aboveLayout = TextViewLayout(attributed, maximumNumberOfLines: 2, alignment: .center)
                    aboveLayout?.measure(width: w_width - 24)
                    aboveLayout?.interactions = LinkHooks.shared.globalLinkExecutor()
                } else {
                    aboveLayout = nil
                }
                
                let rect = NSMakeRect(0, 0, w_width, 40 + 20 + (aboveLayout != nil ? aboveLayout!.layoutSize.height + 4 : 0))
                
                
                let panel = Window(contentRect: rect, styleMask: [.fullSizeContentView], backing: .buffered, defer: false)
                panel._canBecomeMain = false
                panel._canBecomeKey = false
                panel.level = .popUpMenu
                panel.backgroundColor = .clear
                panel.isOpaque = false
                panel.hasShadow = false
                

                let reveal:((ContextAddReactionsListView & StickerFramesCollector)->Void)?
                
                
                var selectedItems: [ChatHistoryEmojiSelectedItem] = []

                if let reactions = message.effectiveReactions(isTags: isTags) {
                    for reaction in reactions {
                        if reaction.isSelected {
                            switch reaction.value {
                            case let .builtin(emoji):
                                selectedItems.append(.init(source: .builtin(emoji), type: .transparent))
                            case let .custom(fileId):
                                selectedItems.append(.init(source: .custom(fileId), type: .transparent))
                            case .stars:
                                break
                            }
                        }
                    }
                }
                
                let orderedTagItems: [RecentReactionItem]? = isTags ? reactions : nil

                if accessToAll {
                    reveal = { view in
                        let react: (StickerPackItem, NSRect?, Bool) -> Void = { sticker, fromRect, isLarge in
                            guard isTags || canApplyReaction() else { return }
                            let parsedFile = sticker.file._parse()
                            let value: UpdateMessageReaction
                            if let bundle = parsedFile.stickerText {
                                value = .builtin(bundle)
                            } else {
                                value = .custom(fileId: parsedFile.fileId.id, file: parsedFile)
                            }
                            var contains: Bool = false
                            for reaction in reactions {
                                switch reaction.content {
                                case let .custom(file):
                                    if file.fileId == parsedFile.fileId {
                                        contains = true
                                        break
                                    }
                                default:
                                    break
                                }
                            }

                            if isTags, !context.isPremium {
                                openSavedTagsPremium()
                            } else {
                                if case .custom = value, !context.isPremium && parsedFile.isPremiumEmoji, !contains {
                                    showModalText(for: context.window, text: strings().customReactionPremiumAlert, callback: { _ in
                                        prem(with: PremiumBoardingController(context: context, source: .premium_stickers), for: context.window)
                                    })
                                } else {
                                    let updated = ChatHistoryUIHooks.shared.messageNewReactions(message, value, isTags)
                                    context.reactions.react(message.id, values: updated, fromRect: fromRect, storeAsRecentlyUsed: true, isLarge: isLarge)
                                }
                            }
                        }
                        let window = ChatHistoryUIHooks.shared.makeReactionsWindow(context, message.id.peerId, selectedItems, orderedTagItems, { sticker, fromRect in
                            react(sticker, fromRect, false)
                        }, isTags ? nil : { sticker, fromRect in
                            react(sticker, fromRect, true)
                        })
//                        let transition = ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeOut)
//                        transition.updateFrame(view: view, frame: CGRect(origin: view.frame.origin, size: NSMakeSize(view.frame.width, 60)))
//                        view.updateLayout(size: view.frame.size, transition: transition)
                        window.showChatHistoryReactions(view)
                    }
                } else {
                    reveal = nil
                }
                
                
                let view = ContextAddReactionsListView(frame: rect, context: context, list: available, add: { value, checkPrem, fromRect in
                    guard isTags || canApplyReaction() else { return }
                    if isTags, !context.isPremium {
                        openSavedTagsPremium()
                    } else {
                        if value == .stars {
                            context.reactions.sendStarsReaction(message.id, count: 1, fromRect: fromRect)
                        } else {
                            context.reactions.react(message.id, values: ChatHistoryUIHooks.shared.messageNewReactions(message, value.toUpdate(), isTags), fromRect: fromRect, storeAsRecentlyUsed: true)
                        }
                    }
                }, addLarge: isTags ? nil : { value, fromRect in
                    guard isTags || canApplyReaction() else { return }
                    context.reactions.react(message.id, values: ChatHistoryUIHooks.shared.messageNewReactions(message, value.toUpdate(), isTags), fromRect: fromRect, storeAsRecentlyUsed: true, isLarge: true)
                }, radiusLayer: nil, revealReactions: reveal, aboveText: aboveLayout, message: message)
                
                
                panel.contentView?.addSubview(view)
                panel.contentView?.wantsLayer = true
                view.autoresizingMask = [.width, .height]
                return panel
            }
        }
        return .single(nil)
    }
    
    public override var instantlyResize: Bool {
        return forwardType != nil
    }
    
    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        if let message = message, !context.isFrozen {
            return chatMenuItems(for: message, entry: entry, textLayout: nil, chatInteraction: chatInteraction)
        }
        return super.menuItems(in: location)
    }
    
    public var stateOverlayTextColor: NSColor {
       guard let media = self.message?.anyMedia else {
           return self.presentation.chatServiceItemTextColor
       }
        if let file = media as? TelegramMediaFile, file.isInstantVideo {
            return self.presentation.chatServiceItemTextColor
        } else if media is TelegramMediaMap {
            return NSColor(0xffffff)
        }
        
       if media.isInteractiveMedia {
            return NSColor(0xffffff)
       } else {
           return self.presentation.chatServiceItemTextColor
       }
    }
    public var isInteractiveMedia: Bool {
        guard let media = self.message?.anyMedia else {
            return false
        }
        return media.isInteractiveMedia
    }
    
    public struct LastLineData {
        public let width: CGFloat
        public let single: Bool
    }
    public var lastLineContentWidth: LastLineData? {
        if let reactionsLayout = reactionsLayout {
            var oneLine = reactionsLayout.oneLine
            if let item = self as? ChatMessageItem {
                if item.webpageLayout != nil {
                    oneLine = false
                }
            }
            if !reactionsLayout.presentation.isOutOfBounds {
                return LastLineData(width: reactionsLayout.lastLineSize.width, single: oneLine)
            }
        }
        if let factCheckLayout {
            return LastLineData(width: factCheckLayout.size.width, single: false)
        }

        let groupedItem = self as? ChatGroupedItem
        let firstCaption = captionLayouts.first
        var resolvedFilesCaption: RowCaption?? = nil
        @inline(__always) func captionByLastMessage() -> RowCaption? {
            if let cached = resolvedFilesCaption {
                return cached
            }
            let stableId = self.lastMessage?.stableId
            let value = captionLayouts.first(where: { $0.id == stableId })
            resolvedFilesCaption = .some(value)
            return value
        }

        if captionLayouts.count == 1, !invertMedia {
            if let item = groupedItem {
                switch item.layoutType {
                case .files:
                    if let caption = captionByLastMessage()?.layout {
                        if let line = caption.lastLine {
                            return LastLineData(width: line.isRTL || caption.lastLineIsQuote ? blockWidth : line.frame.width, single: caption.linesCount == 1)
                        }
                    }
                case .photoOrVideo:
                    if let caption = firstCaption?.layout {
                        if let line = caption.lastLine {
                            return LastLineData(width: line.isRTL || caption.lastLineIsQuote ? blockWidth : line.frame.width, single: caption.linesCount == 1 && !isBubbleFullFilled)
                        }
                    }
                }
            } else {
                if let caption = firstCaption?.layout {
                    if let line = caption.lastLine {
                        return LastLineData(width: line.isRTL || caption.lastLineIsQuote ? blockWidth : line.frame.width, single: caption.linesCount == 1 && !isBubbleFullFilled)
                    }
                }
            }
        } else if captionLayouts.count > 1 {
            if let item = groupedItem {
                switch item.layoutType {
                case .files:
                    if let caption = captionByLastMessage()?.layout {
                        if let line = caption.lastLine {
                            return LastLineData(width: line.isRTL || caption.lastLineIsQuote ? blockWidth : line.frame.width, single: caption.linesCount == 1)
                        }
                    }
                case .photoOrVideo:
                    if let caption = firstCaption?.layout {
                        if let line = caption.lastLine {
                            return LastLineData(width: line.isRTL || caption.lastLineIsQuote ? blockWidth : line.frame.width, single: caption.linesCount == 1)
                        }
                    }
                }
            }
        }
        
        if let item = self as? ChatMessageItem {
            if item.actionButtonText != nil || item.papercutLayout != nil {
                return nil
            }
            if item.textLayout.lastLineIsRtl {
                return nil
            }
            if item.textLayout.lastLineIsBlock {
                return LastLineData(width: item.textLayout.size.width, single: false)
            }
            if let _ = item.webpageLayout, !item.webpageAboveContent {
                return nil
            }
            if let line = item.textLayout.lastLine {
                return LastLineData(width: line.frame.width, single: item.textLayout.linesCount == 1)
            }
        }
        return nil
    }
    
    public func invokeMessageEffect() {
        if let message = message {
            let mirror = self.renderType == .list ? false : message.isIncoming(context.account, renderType == .bubble)
            chatInteraction.runPremiumScreenEffect(message, mirror, false)
        }
    }
    
    
    public func revealBlockAtIndex(_ index: Int, messageId: MessageId? = nil) {
        if let messageId = messageId ?? self.message?.id {
            chatInteraction.toggleQuote(QuoteMessageIndex(messageId: messageId, index: index))
        }
    }
    
    public override func inset(for text: String, range: NSRange?) -> CGFloat {
        for captionLayout in captionLayouts {
            if let rect = captionLayout.layout.rect(for: text, range: range) {
                return rect.maxY
            }
        }
        return super.inset(for: text, range: range)
    }


}
