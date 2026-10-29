import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Localization
import Postbox
import KeyboardKey
import InAppSettings
import InputView
import AlertsUI
import ChatHistoryModel
import ChatUI
import ChatListUI
import EntertainmentUI
import GeneralRows
import InputTextView
import LocalAnimations
import MessageUtils
import ShortPeerRow
import TelegramContext
import TelegramTheme
import TelegramUtils
import Strings
import TelegramMediaUtils
import ChatModeTypes
import InlineStickerLayer
import InputDataUI



fileprivate class ShareModalView : Control, TokenizedProtocol {
    let tokenizedView:TokenizedView
    let basicSearchView: SearchView = SearchView(frame: NSMakeRect(0,0, 260, 30))
    let tableView:TableView = TableView()
    fileprivate let share:ImageButton = ImageButton()
    fileprivate let dismiss:ImageButton = ImageButton()

    
    fileprivate let sendButton = ImageButton()
    fileprivate let emojiButton = ImageButton()
    fileprivate let textView:UITextView = UITextView(frame: NSMakeRect(0, 0, 100, 50))
    fileprivate let actionsContainerView: Control = Control()
    fileprivate let textContainerView: View = View()
    fileprivate let bottomSeparator: View = View()

    fileprivate var sendWithoutSound: (()->Void)? = nil
    fileprivate var scheduleMessage: (()->Void)? = nil
    fileprivate var scheduleWhenOnline: (()->Void)? = nil
    
    fileprivate var presentation: TelegramPresentationTheme? {
        didSet {
            updateLocalizationAndTheme(theme: presentation ?? theme)
        }
    }

    private let topSeparator = View()
    fileprivate var hasShareMenu: Bool = true {
        didSet {
            share.isHidden = !hasShareMenu
            needsLayout = true
        }
    }
    
    
    required init(frame frameRect: NSRect, shareObject: ShareObject, presentation: TelegramPresentationTheme? = nil) {
        tokenizedView = TokenizedView(frame: NSMakeRect(0, 0, 300, 30), localizationFunc: { key in
            return translate(key: key, [])
        }, placeholderKey: shareObject.searchPlaceholderKey, customTheme: {
            return .init(presentation?.colors ?? theme.colors)
        })
        self.presentation = presentation
        super.init(frame: frameRect)
        

        addSubview(tokenizedView)
        addSubview(basicSearchView)
        addSubview(tableView)
        addSubview(topSeparator)
        tokenizedView.delegate = self
        
        tableView.getBackgroundColor = {
            return presentation?.colors.background ?? theme.colors.background
        }
        
        dismiss.disableActions()
        share.disableActions()

        
        addSubview(share)
        addSubview(dismiss)
        
        
        sendButton.contextMenu = { [weak self] in
            
            
            var items:[ContextMenuItem] = []

            items.append(ContextMenuItem(strings().chatSendWithoutSound, handler: {
                self?.sendWithoutSound?()
            }, itemImage: MenuAnimation.menu_mute.value))
            
            items.append(ContextMenuItem(strings().chatSendScheduledMessage, handler: {
                self?.scheduleMessage?()
            }, itemImage: MenuAnimation.menu_schedule_message.value))
            
            
            if !items.isEmpty {
                let menu = ContextMenu(presentation: .current(presentation?.colors ?? theme.colors))
                for item in items {
                    menu.addItem(item)
                }
                return menu
            }
            return nil
        }
        
        sendButton.autohighlight = false

        
        
        actionsContainerView.addSubview(sendButton)
        actionsContainerView.addSubview(emojiButton)
        
        actionsContainerView.setFrameSize(sendButton.frame.width + emojiButton.frame.width + 40, 50)
        actionsContainerView.isAccessibilityDecorative = true
        
        emojiButton.centerY(x: 0)
        sendButton.centerY(x: emojiButton.frame.maxX + 20)
        
    

        textView.interactions.max_height = 180
        textView.interactions.min_height = 50
        
        textContainerView.addSubview(textView)

        addSubview(textContainerView)
        addSubview(actionsContainerView)
        addSubview(bottomSeparator)
        updateLocalizationAndTheme(theme: presentation ?? theme)
    }
    
    var textWidth: CGFloat {
        return frame.width - 10 - actionsContainerView.frame.width
    }
    
    func textViewSize() -> (NSSize, CGFloat) {
        return inputTextViewSize(textView, width: textWidth)
    }
    
    var additionHeight: CGFloat {
        return textViewSize().0.height + 16 + searchView.frame.height + 20
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = theme as! TelegramPresentationTheme
        share.set(image: theme.icons.modalShare, for: .Normal)
        _ = share.sizeToFit()
        share.setAccessibilityLabel(strings().voiceOverCommonShare)
        
        backgroundColor = theme.colors.background
        textContainerView.backgroundColor = theme.colors.background
        actionsContainerView.backgroundColor = theme.colors.background
       // textView.setBackgroundColor(theme.colors.background)
        bottomSeparator.backgroundColor = theme.colors.border
        topSeparator.backgroundColor = theme.colors.border
        
        self.backgroundColor = theme.colors.background

        textView.placeholder = strings().previewSenderCommentPlaceholder
        textView.inputTheme = theme.inputTheme
                 
    //    textView.setPlaceholderAttributedString(.initialize(string:  strings().previewSenderCommentPlaceholder, color: theme.colors.grayText, font: .normal(.text)), update: false)
        
        
        sendButton.set(image: theme.icons.chatSendMessage, for: .Normal)
        _ = sendButton.sizeToFit()
        sendButton.setAccessibilityLabel(strings().voiceOverMessageContextSend)
        
        emojiButton.set(image: theme.icons.chatEntertainment, for: .Normal)
        emojiButton.setAccessibilityLabel(strings().voiceOverCommonEmoji)
        _ = emojiButton.sizeToFit()
        
        backgroundColor = theme.colors.background
       // textView.background = theme.colors.background
//        textView.textColor = theme.colors.text
//        textView.linkColor = theme.colors.link

        dismiss.set(image: inDestinationMode ? theme.icons.chatNavigationBack : theme.icons.modalClose, for: .Normal)

        _ = dismiss.sizeToFit(.zero, NSMakeSize(30, 30), thatFit: true)
        dismiss.setAccessibilityLabel(inDestinationMode ? strings().voiceOverCommonBack : strings().voiceOverCommonClose)
    }
    
    var searchView: NSView {
        if hasCaptionView {
            return tokenizedView
        } else {
            return basicSearchView
        }
    }
    
    var hasCaptionView: Bool = true {
        didSet {
            textContainerView.isHidden = !hasCaptionView
            actionsContainerView.isHidden = !hasCaptionView
            bottomSeparator.isHidden = !hasCaptionView
            
            basicSearchView.isHidden = hasCaptionView
            tokenizedView.isHidden = !hasCaptionView
            dismiss.isHidden = false
            
            if oldValue != hasCaptionView, hasCaptionView {
                textContainerView.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                actionsContainerView.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                bottomSeparator.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                basicSearchView.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                tokenizedView.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                dismiss.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            }
            needsLayout = true
        }
    }
    
    var hasCommentView: Bool = true {
        didSet {
            textContainerView.isHidden = !hasCommentView
            bottomSeparator.isHidden = !hasCommentView
            actionsContainerView.isHidden = !hasCommentView
            needsLayout = true
        }
    }
    
    var hasSendView: Bool = true {
        didSet {
            sendButton.isHidden = !hasSendView
            needsLayout = true
        }
    }
    
    func applyTransition(_ transition: TableUpdateTransition) {
        self.tableView.resetScrollNotifies()
        self.tableView.scroll(to: .up(false))
        self.tableView.merge(with: transition)
        self.tableView.cancelHighlight()
        
        
        let item = self.tableView.item(stableId: UIChatListEntryId.reveal)
        self.topSeparator.change(opacity: item != nil ? 0 : 1, animated: transition.animated)
    }
    
    private var forumTopicItems:[ForumTopicItem] = []
    private var communityChatsView: TableView?
    private var forumTopicsView: TableView?
    
    var inDestinationMode: Bool {
        return communityChatsView != nil || forumTopicsView != nil
    }
    var activeTableView: TableView {
        return forumTopicsView ?? communityChatsView ?? tableView
    }
    
   
    
    private class ForumTopicArguments {
        let context: any AccountContextProtocol
        let presentation: TelegramPresentationTheme
        let select:(Int64)->Void
        init(context: any AccountContextProtocol, presentation: TelegramPresentationTheme, select:@escaping(Int64)->Void) {
            self.context = context
            self.select = select
            self.presentation = presentation
        }
    }
    
    private struct ForumTopicItem : TableItemListNodeEntry {
        let item: EngineChatList.Item
                
        static func < (lhs: ShareModalView.ForumTopicItem, rhs: ShareModalView.ForumTopicItem) -> Bool {
            return lhs.item.index < rhs.item.index
        }
        static func == (lhs: ShareModalView.ForumTopicItem, rhs: ShareModalView.ForumTopicItem) -> Bool {
            return lhs.item == rhs.item
        }
        
        var stableId: EngineChatList.Item.Id {
            return item.id 
        }
        func item(_ arguments: ShareModalView.ForumTopicArguments, initialSize: NSSize) -> TableRowItem {
            let threadId: Int64?
            switch item.id {
            case let .forum(id):
                threadId = id
            case let .chatList(peerId):
                threadId = peerId.toInt64()
            }
            return SearchTopicRowItem(initialSize, stableId: self.item.id, item: self.item, context: arguments.context, action: {
                if let threadId = threadId {
                    arguments.select(threadId)
                }
            }, presentation: arguments.presentation)
        }
    }
    
    func appearForumTopics(_ items: [EngineChatList.Item], peerId: PeerId, interactions: SelectPeerInteraction, delegate: TableViewDelegate?, context: any AccountContextProtocol, animated: Bool) {
        
        let arguments = ForumTopicArguments(context: context, presentation: presentation ?? theme, select: { threadId in
            interactions.action(peerId, threadId)
        })
        
        let mapped:[ForumTopicItem] = items.map {
            .init(item: $0)
        }
        let sourceView = self.activeTableView
        let animated = animated && self.forumTopicsView == nil
        
        let tableView = self.forumTopicsView ?? TableView()
        if tableView.superview == nil {
            tableView.frame = self.tableView.frame
            addSubview(tableView)
            self.forumTopicsView = tableView
            
            tableView.getBackgroundColor = { [weak self] in
                return self?.presentation?.colors.background ?? theme.colors.background
            }
        }
        
        tableView.delegate = delegate
        
        let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: self.forumTopicItems, rightList: mapped)
        
        self.forumTopicItems = mapped

        
        tableView.beginTableUpdates()
        
        for deleteIndex in deleteIndices.reversed() {
            tableView.remove(at: deleteIndex)
        }
        for indicesAndItem in indicesAndItems {
            let item = indicesAndItem.1.item(arguments, initialSize: tableView.frame.size)
            _ = tableView.insert(item: item, at: indicesAndItem.0)
        }
        for updateIndex in updateIndices {
            let item = updateIndex.1.item(arguments, initialSize: tableView.frame.size)
            tableView.replace(item: item, at: updateIndex.0, animated: false)
        }

        tableView.endTableUpdates()
        

        if animated {
            let oneOfThird = frame.width / 3
            tableView.layer?.animatePosition(from: NSMakePoint(oneOfThird * 2, tableView.frame.minY), to: tableView.frame.origin, duration: 0.35, timingFunction: .spring)
            sourceView.layer?.animatePosition(from: sourceView.frame.origin, to: NSMakePoint(-oneOfThird, sourceView.frame.minY), duration: 0.35, timingFunction: .spring)
        }
        
        updateLocalizationAndTheme(theme: presentation ?? theme)
        needsLayout = true
    }
    
    func appearCommunityChats(_ peers: [Peer], interactions: SelectPeerInteraction, delegate: TableViewDelegate?, context: any AccountContextProtocol, animated: Bool, multipleSelection: Bool) {
        let theme = presentation ?? theme
        let sourceView = self.activeTableView
        let animated = animated && self.communityChatsView == nil

        let tableView = self.communityChatsView ?? TableView()
        if tableView.superview == nil {
            tableView.frame = self.tableView.frame
            addSubview(tableView)
            self.communityChatsView = tableView

            tableView.getBackgroundColor = { [weak self] in
                return self?.presentation?.colors.background ?? theme.colors.background
            }
        }

        tableView.delegate = delegate

        tableView.removeAll()
        tableView.beginTableUpdates()
        var index: Int = 0
        for peer in peers {
            let item = ShortPeerRowItem(tableView.frame.size, peer: peer, account: context.account, context: context, stableId: AnyHashable(peer.id), height: 48, photoSize: NSMakeSize(36, 36), titleStyle: ControlStyle(font: .medium(.title), foregroundColor: theme.colors.text), inset: NSEdgeInsets(left: 10, right: 10), drawSeparatorIgnoringInset: true, interactionType: multipleSelection ? .selectable(interactions, side: .right) : .interactable(interactions), action: { [weak interactions] in
                if TelegramUtilsHooks.shared.peerIsForum(peer) || (peer.groupAccess.canManageDirect && peer.isMonoForum) {
                    _ = interactions?.openForum(peer.id, peer.isMonoForum)
                } else {
                    interactions?.action(peer.id, nil)
                }
            }, customTheme: .initialize(theme))
            _ = tableView.insert(item: item, at: index)
            index += 1
        }
        tableView.endTableUpdates()

        if animated {
            let oneOfThird = frame.width / 3
            tableView.layer?.animatePosition(from: NSMakePoint(oneOfThird * 2, tableView.frame.minY), to: tableView.frame.origin, duration: 0.35, timingFunction: .spring)
            sourceView.layer?.animatePosition(from: sourceView.frame.origin, to: NSMakePoint(-oneOfThird, sourceView.frame.minY), duration: 0.35, timingFunction: .spring)
        }

        updateLocalizationAndTheme(theme: presentation ?? theme)
        needsLayout = true
    }

    private func pop(_ view: TableView, revealing sourceView: TableView, animated: Bool) {
        if animated {
            let oneOfThird = frame.width / 3
            view.layer?.animatePosition(from: tableView.frame.origin, to: NSMakePoint(frame.width, view.frame.minY), duration: 0.35, timingFunction: .spring, removeOnCompletion: false, completion: { [weak view] _ in
                view?.removeFromSuperview()
            })
            sourceView.layer?.animatePosition(from: NSMakePoint(-oneOfThird, sourceView.frame.minY), to: sourceView.frame.origin, duration: 0.35, timingFunction: .spring)
        } else {
            view.removeFromSuperview()
        }
        sourceView.cancelSelection()
        updateLocalizationAndTheme(theme: presentation ?? theme)
        self.needsLayout = true
    }

    func popForum(animated: Bool) {
        guard let forumTopicsView else {
            return
        }
        self.forumTopicsView = nil
        self.forumTopicItems = []
        pop(forumTopicsView, revealing: communityChatsView ?? tableView, animated: animated)
    }

    func popCommunity(animated: Bool) {
        guard let communityChatsView else {
            return
        }
        self.communityChatsView = nil
        pop(communityChatsView, revealing: tableView, animated: animated)
    }
    
        
    func tokenizedViewDidChangedHeight(_ view: TokenizedView, height: CGFloat, animated: Bool) {
        if !tokenizedView.isHidden {
            searchView._change(pos: NSMakePoint(10 + (!dismiss.isHidden ? 40 : 0), 10), animated: animated)
            let tableSize = NSMakeSize(frame.width, frame.height - height - 20 - (textContainerView.isHidden ? 0 : textContainerView.frame.height))
            let tablePosition = NSMakePoint(0, height + 20)
            tableView.change(size: tableSize, animated: animated)
            tableView.change(pos: tablePosition, animated: animated)
            communityChatsView?.change(size: tableSize, animated: animated)
            communityChatsView?.change(pos: tablePosition, animated: animated)
            forumTopicsView?.change(size: tableSize, animated: animated)
            forumTopicsView?.change(pos: tablePosition, animated: animated)
            topSeparator.change(pos: NSMakePoint(0, searchView.frame.maxY + 10), animated: animated)
        }
    }
    

    
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        
        transition.updateFrame(view: emojiButton, frame: emojiButton.centerFrameY(x: 0))
        transition.updateFrame(view: actionsContainerView, frame: CGRect.init(origin: CGPoint(x: size.width - actionsContainerView.frame.width, y: size.height - actionsContainerView.frame.height), size: CGSize(width: (sendButton.isHidden ? 0 : (sendButton.frame.width + 20)) + emojiButton.frame.width + 20, height: 50)))
        transition.updateFrame(view: sendButton, frame: sendButton.centerFrameY(x: emojiButton.frame.maxX + 20))
        
        
        transition.updateFrame(view: searchView, frame: CGRect(origin: CGPoint(x: 10 + (!dismiss.isHidden ? 40 : 0), y: 10), size: CGSize(width: size.width - 10 - (!dismiss.isHidden ? 40 : 0) - (share.isHidden ? 10 : 50), height: searchView.frame.height)))
        transition.updateFrame(view: share, frame: CGRect(origin: CGPoint(x: size.width - share.frame.width - 10, y: 10), size: share.frame.size))
        transition.updateFrame(view: dismiss, frame: CGRect(origin: CGPoint(x: 10, y: 10), size: dismiss.frame.size))
        
        transition.updateFrame(view: tableView, frame: NSMakeRect(0, searchView.frame.maxY + 10, size.width, size.height - searchView.frame.height - 20 - (!textContainerView.isHidden ? 50 : 0)))
        transition.updateFrame(view: topSeparator, frame: NSMakeRect(0, searchView.frame.maxY + 10, size.width, .borderSize))
                
        let (textSize, textHeight) = textViewSize()
        
        let textContainerRect = NSMakeRect(0, size.height - textSize.height, size.width, textSize.height)
        transition.updateFrame(view: textContainerView, frame: textContainerRect)
        
        transition.updateFrame(view: textView, frame: CGRect(origin: CGPoint(x: 10, y: 0), size: textSize))
        textView.updateLayout(size: textSize, textHeight: textHeight, transition: transition)
        
        transition.updateFrame(view: bottomSeparator, frame: NSMakeRect(0, size.height - textContainerView.frame.height, size.width, .borderSize))
        
        if let communityChatsView {
            transition.updateFrame(view: communityChatsView, frame: tableView.frame)
        }
        if let forumTopicsView {
            transition.updateFrame(view: forumTopicsView, frame: tableView.frame)
        }
    }
    
    
    fileprivate override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
}

public class SharefilterCallbackObject : ShareObject {
    private let callback:(PeerId, Int64?)->Signal<Never, NoError>
    private let limits: [String]
    public init(_ context: any AccountContextProtocol, limits: [String], callback:@escaping(PeerId, Int64?)->Signal<Never, NoError>) {
        self.callback = callback
        self.limits = limits
        super.init(context)
    }
    
    public override var hasFolders: Bool {
        return false
    }
    
    public override func perform(to peerIds:[PeerId], threadId: Int64?, comment: ChatTextInputState? = nil, sendPaidMessageStars:[PeerId: StarsAmount] = [:]) -> Signal<Never, String> {
        if let peerId = peerIds.first {
            return callback(peerId, threadId) |> castError(String.self)
        } else {
            return .complete()
        }
    }
    
    public override func statusString(_ peer: Peer, presence: PeerStatusStringResult?, autoDeletion: Int32?) -> String? {
        if peer.id == context.peerId {
            return nil
        } else {
            return super.statusString(peer, presence: presence, autoDeletion: autoDeletion)
        }
    }
    
    public override func possibilityPerformTo(_ peer: Peer) -> Bool {
        if !canSendMessagesToPeer(.init(peer)) {
            return false
        }
        if peer.isBot {
            if !limits.contains("bots") {
                return false
            }
        }
        if peer.isUser {
            if !limits.contains("users") {
                return false
            }
        }
        if peer.isChannel {
            if !limits.contains("channels") {
                return false
            }
        }
        if peer.isGroup || peer.isSupergroup || peer.isGigagroup {
            if !limits.contains("groups") {
                return false
            }
        }
        return true
    }
    
    
    public override var multipleSelection: Bool {
        return false
    }
    public override var hasCaptionView: Bool {
        return false
    }
    public override var blockCaptionView: Bool {
        return true
    }
}

//                    let value =

public class ShareChatContextResult : ShareObject, ShareDeliveryProviding {
    private let preparedMessage: PreparedInlineMessage
    public init(_ context: any AccountContextProtocol, preparedMessage: PreparedInlineMessage) {
        self.preparedMessage = preparedMessage
        super.init(context)
    }
    
    public override var messagesCount: Int { 1 }

    func outgoingMessageCount(comment: ChatTextInputState?) -> Int { 1 }


    public override func perform(to peerIds: [PeerId], threadId: Int64?, comment: ChatTextInputState? = nil, sendPaidMessageStars:[PeerId: StarsAmount] = [:]) -> Signal<Never, String> {
        return performWithResults(to: peerIds, threadId: threadId, comment: comment, sendPaidMessageStars: sendPaidMessageStars) |> ignoreValues
    }

    func performWithResults(to peerIds: [PeerId], threadId: Int64?, comment: ChatTextInputState?, sendPaidMessageStars: [PeerId: StarsAmount]) -> Signal<[ShareRecipientDelivery], String> {
        var seen = Set<PeerId>()
        let peerIds = peerIds.filter { seen.insert($0).inserted }
        guard !peerIds.isEmpty else { return .single([]) }
        let threadIds = self.threadIds
        let silent = withoutSound
        let scheduleTime = scheduleDate.map { Int32($0.timeIntervalSince1970) }
        let signals = peerIds.map { peerId -> Signal<ShareRecipientDelivery, NoError> in
            let threadId = threadIds[peerId] ?? threadId
            guard let message = context.engine.messages.outgoingMessageWithChatContextResult(to: peerId, threadId: threadId, botId: preparedMessage.botId, result: preparedMessage.result, replyToMessageId: nil, replyToStoryId: nil, hideVia: false, silentPosting: silent, scheduleTime: scheduleTime, sendPaidMessageStars: sendPaidMessageStars[peerId], postpone: false, correlationId: nil) else {
                return .single(ShareRecipientDelivery(peerId: peerId, comment: nil, content: ShareDeliveryPart(expectedCount: 1, result: [nil])))
            }
            return shareFirstResult(enqueueMessages(account: context.account, peerId: peerId, messages: [message]) |> map { Optional($0) }, or: nil)
            |> map { ShareRecipientDelivery(peerId: peerId, comment: nil, content: ShareDeliveryPart(expectedCount: 1, result: $0)) }
        }
        return (combineLatest(signals) |> take(1) |> castError(String.self))
    }

    public override var hasCaptionView: Bool {
        return false
    }
    
    public override var multipleSelection: Bool {
        return false
    }
    
}

public class ShareLinkObject : ShareObject, ShareDeliveryProviding {
    public let link:String
    public let text: String?
    public init(_ context: any AccountContextProtocol, link:String, text: String? = nil) {
        self.link = link.removingPercentEncoding ?? link
        self.text = text
        super.init(context)
    }
    
    public override var messagesCount: Int {
        return 1
    }
    
    public override var hasLink: Bool {
        return true
    }
    
    public override func shareLink() {
        copyToClipboard(link)
    }
    
    public override func perform(to peerIds:[PeerId], threadId: Int64?, comment: ChatTextInputState? = nil, sendPaidMessageStars:[PeerId: StarsAmount] = [:]) -> Signal<Never, String> {
        return performWithResults(to: peerIds, threadId: threadId, comment: comment, sendPaidMessageStars: sendPaidMessageStars) |> ignoreValues
    }

    func outgoingMessageCount(comment: ChatTextInputState?) -> Int {
        return 1
    }


    func performWithResults(to peerIds: [PeerId], threadId: Int64?, comment: ChatTextInputState?, sendPaidMessageStars: [PeerId: StarsAmount]) -> Signal<[ShareRecipientDelivery], String> {
        var seen = Set<PeerId>()
        let peerIds = peerIds.filter { seen.insert($0).inserted }
        guard !peerIds.isEmpty else { return .single([]) }
        let threadIds = self.threadIds
        var text = self.link
        if let comment, !comment.inputText.isEmpty { text += "\n\(comment.inputText)" }
        let signals = peerIds.map { peerId -> Signal<ShareRecipientDelivery, NoError> in
            let threadId = threadIds[peerId] ?? threadId
            let attributes = self.attributes(peerId, sendPaidMessageStars: sendPaidMessageStars[peerId])
            let message = EnqueueMessage.message(text: text, attributes: attributes, inlineStickers: [:], mediaReference: nil, threadId: threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
            return shareFirstResult(enqueueMessages(account: context.account, peerId: peerId, messages: [message]) |> map { Optional($0) }, or: nil)
            |> map { ShareRecipientDelivery(peerId: peerId, comment: nil, content: ShareDeliveryPart(expectedCount: 1, result: $0)) }
        }
        return (combineLatest(signals) |> take(1) |> castError(String.self))
    }
}


public class ShareContactObject : ShareObject, ShareDeliveryProviding {
    public let user:TelegramUser
    public let media: Media
    public init(_ context: any AccountContextProtocol, user:TelegramUser) {
        self.user = user
        self.media = TelegramMediaContact(firstName: user.firstName ?? "", lastName: user.lastName ?? "", phoneNumber: user.phone ?? "", peerId: user.id, vCardData: nil)
        super.init(context)
    }
    
    public override var messagesCount: Int {
        return 1
    }
    
    public override func possibilityPerformTo(_ peer: Peer) -> Bool {
        return !excludePeerIds.contains(peer.id) && peer.canSendMessage(media: media)
    }
    
    public override func perform(to peerIds:[PeerId], threadId: Int64?, comment: ChatTextInputState? = nil, sendPaidMessageStars:[PeerId: StarsAmount] = [:]) -> Signal<Never, String> {
        return performWithResults(to: peerIds, threadId: threadId, comment: comment, sendPaidMessageStars: sendPaidMessageStars) |> ignoreValues
    }


    func performWithResults(to peerIds: [PeerId], threadId: Int64?, comment: ChatTextInputState?, sendPaidMessageStars: [PeerId: StarsAmount]) -> Signal<[ShareRecipientDelivery], String> {
        var seen = Set<PeerId>()
        let peerIds = peerIds.filter { seen.insert($0).inserted }
        guard !peerIds.isEmpty else { return .single([]) }
        let threadIds = self.threadIds
        let signals = peerIds.map { peerId -> Signal<ShareRecipientDelivery, NoError> in
            let threadId = threadIds[peerId] ?? threadId
            let attributes = self.attributes(peerId, sendPaidMessageStars: sendPaidMessageStars[peerId])
            let commentResult: Signal<ShareDeliveryPart?, NoError>
            if let comment, !comment.inputText.isEmpty {
                let message = EnqueueMessage.message(text: comment.inputText, attributes: attributes, inlineStickers: [:], mediaReference: nil, threadId: threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
                commentResult = shareFirstResult(enqueueMessages(account: context.account, peerId: peerId, messages: [message]) |> map { Optional($0) }, or: nil)
                |> map { ShareDeliveryPart(expectedCount: 1, result: $0) }
            } else {
                commentResult = .single(nil)
            }
            let message = EnqueueMessage.message(text: "", attributes: attributes, inlineStickers: [:], mediaReference: AnyMediaReference.standalone(media: media), threadId: threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])
            let contactResult = shareFirstResult(enqueueMessages(account: context.account, peerId: peerId, messages: [message]) |> map { Optional($0) }, or: nil)
            return combineLatest(commentResult, contactResult)
            |> take(1)
            |> map { ShareRecipientDelivery(peerId: peerId, comment: $0, content: ShareDeliveryPart(expectedCount: 1, result: $1)) }
        }
        return (combineLatest(signals) |> take(1) |> castError(String.self))
    }

}

public class ShareCallbackObject : ShareObject {
    private let callback:([PeerId])->Signal<Never, NoError>
    public init(_ context: any AccountContextProtocol, callback:@escaping([PeerId])->Signal<Never, NoError>) {
        self.callback = callback
        super.init(context)
    }
    
    public override func perform(to peerIds:[PeerId], threadId: Int64?, comment: ChatTextInputState? = nil, sendPaidMessageStars:[PeerId: StarsAmount] = [:]) -> Signal<Never, String> {
        return callback(peerIds) |> castError(String.self)
    }
    
}


public class ShareCallbackPeerTypesObject : ShareObject {
    private let callback:([PeerId])->Signal<Never, NoError>
    private let peerTypes: ReplyMarkupButtonAction.PeerTypes
    public init(_ context: any AccountContextProtocol, peerTypes: ReplyMarkupButtonAction.PeerTypes, callback:@escaping([PeerId])->Signal<Never, NoError>) {
        self.callback = callback
        self.peerTypes = peerTypes
        super.init(context, limit: 1)
    }
    
    public override var hasFolders: Bool {
        return false
    }
    
    public override var multipleSelection: Bool {
        return false
    }
    public override var hasCaptionView: Bool {
        return false
    }
    public override var blockCaptionView: Bool {
        return true
    }
    
    public override func perform(to peerIds:[PeerId], threadId: Int64?, comment: ChatTextInputState? = nil, sendPaidMessageStars:[PeerId: StarsAmount] = [:]) -> Signal<Never, String> {
        return callback(peerIds) |> castError(String.self)
    }
    
    public override func possibilityPerformTo(_ peer: Peer) -> Bool {
        if self.peerTypes.isEmpty {
            return super.possibilityPerformTo(peer)
        }
        if peer.isUser {
            if peerTypes.contains(.users) {
                return canSendMessagesToPeer(.init(peer))
            }
        }
        if peer.isGroup || peer.isSupergroup || peer.isGigagroup {
            if peerTypes.contains(.groups) {
                return canSendMessagesToPeer(.init(peer))
            }
        }
        if peer.isChannel {
            if peerTypes.contains(.channels) {
                return canSendMessagesToPeer(.init(peer))
            }
        }
        if peer.isBot {
            if peerTypes.contains(.bots) {
                return canSendMessagesToPeer(.init(peer))
            }
        }
        return false
    }
    
}


public class ShareMessageObject : ShareObject, ShareDeliveryProviding {
    fileprivate let messageIds:[MessageId]
    private let message:Message
    public let link:String?
    private let exportLinkDisposable = MetaDisposable()
    
    public override var messagesCount: Int {
        return messageIds.count
    }
    
    public init(_ context: any AccountContextProtocol, _ message:Message, _ groupMessages:[Message] = []) {
        self.messageIds = groupMessages.isEmpty ? [message.id] : groupMessages.map{$0.id}
        self.message = message
        var peer = coreMessageMainPeer(message) as? TelegramChannel
        var messageId = message.id
        if let author = message.forwardInfo?.author as? TelegramChannel {
            peer = author
            messageId = message.forwardInfo?.sourceMessageId ?? message.id
        }
        //            peer = coreMessageMainPeer(message) as? TelegramChannel
        //        }
        if let peer = peer, let address = peer.username {
            switch peer.info {
            case .broadcast:
                self.link = context.meUrlPrefix + address + "/" + "\(messageId.id)"
            default:
                self.link = nil
            }
        } else {
            self.link = nil
        }
        super.init(context)
    }
    
    public override var hasLink: Bool {
        return link != nil
    }
    
    public override func shareLink() {
        if let link = link {
            exportLinkDisposable.set(context.engine.messages.exportMessageLink(peerId: messageIds[0].peerId, messageId: messageIds[0]).start(next: { valueLink in
                if let valueLink = valueLink {
                    copyToClipboard(valueLink)
                } else {
                    copyToClipboard(link)
                }
            }))
        }
    }

    deinit {
        exportLinkDisposable.dispose()
    }

    public override func perform(to peerIds:[PeerId], threadId: Int64?, comment: ChatTextInputState? = nil, sendPaidMessageStars:[PeerId: StarsAmount] = [:]) -> Signal<Never, String> {
        return performWithResults(to: peerIds, threadId: threadId, comment: comment, sendPaidMessageStars: sendPaidMessageStars) |> ignoreValues
    }


    func performWithResults(to peerIds: [PeerId], threadId: Int64?, comment: ChatTextInputState?, sendPaidMessageStars: [PeerId: StarsAmount]) -> Signal<[ShareRecipientDelivery], String> {
        var seen = Set<PeerId>()
        let peerIds = peerIds.filter { seen.insert($0).inserted }
        guard !self.messageIds.isEmpty, !peerIds.isEmpty else { return .single([]) }
        
        let context = self.context
        let messageIds = self.messageIds
        var signals: [Signal<ShareRecipientDelivery, NoError>] = []
        let date = self.scheduleDate
        let withoutSound = self.withoutSound
        let threadIds = self.threadIds
        for peerId in peerIds {
            let captionAttributes = self.attributes(peerId, sendPaidMessageStars: sendPaidMessageStars[peerId])
            let viewSignal: Signal<(Peer, PeerId?), NoError> = combineLatest(context.account.postbox.loadedPeerWithId(peerId), getCachedDataView(peerId: peerId, postbox: context.account.postbox))
            |> take(1)
            |> map { peer, cachedData in
                if let cachedData = cachedData as? CachedChannelData {
                    return (peer, cachedData.sendAsPeerId)
                } else {
                    return (peer, nil)
                }
            }
            
            let threadId = threadIds[peerId] ?? threadId
            
            let expectedCommentCount = comment?.inputText.isEmpty == false ? 1 : 0
            let unknown = ShareRecipientDelivery(peerId: peerId, comment: expectedCommentCount == 0 ? nil : ShareDeliveryPart(expectedCount: 1, result: nil), content: ShareDeliveryPart(expectedCount: messageIds.count, result: nil))
            let delivery = viewSignal |> mapToSignal { (peer, sendAs) -> Signal<ShareRecipientDelivery, NoError> in
                let forward: Signal<[MessageId?], NoError> = Sender.forwardMessages(messageIds: messageIds, context: context, peerId: peerId, replyId: nil, threadId: threadId, silent: FastSettings.isChannelMessagesMuted(peerId) || withoutSound, atDate: date, sendAsPeerId: sendAs, sendPaidMessageStars: sendPaidMessageStars[peerId])
                var caption: Signal<[MessageId?], NoError>?
                if let comment = comment, !comment.inputText.isEmpty, peer.canSendMessage() {
                    let parsingUrlType: ParsingType
                    if peerId.namespace != Namespaces.Peer.SecretChat {
                        parsingUrlType = [.Hashtags]
                    } else {
                        parsingUrlType = [.Links, .Hashtags]
                    }
                                    
                    var attributes:[MessageAttribute] = [TextEntitiesMessageAttribute(entities: comment.messageTextEntities(parsingUrlType))]
                    attributes += captionAttributes
                    if let sendAs = sendAs {
                        attributes.append(SendAsMessageAttribute(peerId: sendAs))
                    }
                    
                    caption = Sender.enqueue(message: EnqueueMessage.message(text: comment.inputText, attributes: attributes, inlineStickers: [:], mediaReference: nil, threadId: threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: []), context: context, peerId: peerId)
                }
                let commentResult: Signal<ShareDeliveryPart?, NoError>
                if let caption {
                    commentResult = shareFirstResult(caption |> map { Optional($0) }, or: nil)
                    |> map { ShareDeliveryPart(expectedCount: 1, result: $0) }
                } else if expectedCommentCount > 0 {
                    commentResult = .single(ShareDeliveryPart(expectedCount: 1, result: [nil]))
                } else {
                    commentResult = .single(nil)
                }
                return (commentResult |> mapToSignal { commentResult in
                    shareFirstResult(forward |> map { Optional($0) }, or: nil)
                    |> map { ShareRecipientDelivery(peerId: peerId, comment: commentResult, content: ShareDeliveryPart(expectedCount: messageIds.count, result: $0)) }
                })
            }
            signals.append(shareFirstResult(delivery, or: unknown))
        }
        return (combineLatest(signals) |> take(1) |> castError(String.self))
    }
    
    public override func possibilityPerformTo(_ peer:Peer) -> Bool {
        return message.possibilityForwardTo(peer)
    }
}



public class ShareStoryObject : ShareObject {
    private let media:Media
    private let _hasLink: Bool
    private let storyId: StoryId
    private let repostAction:()->Void
    public init(_ context: any AccountContextProtocol, media: Media, hasLink: Bool, storyId: StoryId, additionTopItems:ShareAdditionItems?, repostAction:@escaping()->Void) {
        self.media = media
        self._hasLink = hasLink
        self.storyId = storyId
        self.repostAction = repostAction
        super.init(context, additionTopItems: additionTopItems)
    }
    
    public override var messagesCount: Int {
        return 1
    }
    
    public override var hasLink: Bool {
        return _hasLink
    }
    
    public override func shareLink() {
        if _hasLink {
            let signal = context.engine.messages.exportStoryLink(peerId: storyId.peerId, id: storyId.id) |> deliverOnMainQueue
            _ = signal.start(next: { link in
                if let link = link {
                    copyToClipboard(link)
                }
            })
        }
    }

    deinit {
    }

    public override func perform(to peerIds:[PeerId], threadId: Int64?, comment: ChatTextInputState? = nil, sendPaidMessageStars:[PeerId: StarsAmount] = [:]) -> Signal<Never, String> {
        
        let context = self.context
        var signals: [Signal<[MessageId?], NoError>] = []
        let attrs:(PeerId)->[MessageAttribute] = { [weak self] peerId in
            return self?.attributes(peerId, sendPaidMessageStars: sendPaidMessageStars[peerId]) ?? []
        }
        let date = self.scheduleDate
        let withoutSound = self.withoutSound
        let threadIds = self.threadIds
        let media = self.media
        
        let needRepost = peerIds.contains(where: { $0.id._internalGetInt64Value() == 1000 && $0.namespace._internalGetInt32Value() == 7 })
        
        let peerIds = peerIds.filter { $0.id._internalGetInt64Value() != 1000 && $0.namespace._internalGetInt32Value() != 7 }
        
        if needRepost {
            self.repostAction()
        }
        
        for peerId in peerIds {
            let viewSignal: Signal<(Peer, PeerId?), NoError> = combineLatest(context.account.postbox.loadedPeerWithId(peerId), getCachedDataView(peerId: peerId, postbox: context.account.postbox))
            |> take(1)
            |> map { peer, cachedData in
                if let cachedData = cachedData as? CachedChannelData {
                    return (peer, cachedData.sendAsPeerId)
                } else {
                    return (peer, nil)
                }
            }
            
            let threadId = threadIds[peerId] ?? threadId
            
            signals.append(viewSignal |> mapToSignal { (peer, sendAs) in
                
                let forward: Signal<[MessageId?], NoError> = Sender.enqueue(media: media, context: context, peerId: peerId, replyId: nil, threadId: threadId, silent: withoutSound, atDate: date)
                var caption: Signal<[MessageId?], NoError>?
                if let comment = comment, !comment.inputText.isEmpty, peer.canSendMessage() {
                    let parsingUrlType: ParsingType
                    if peerId.namespace != Namespaces.Peer.SecretChat {
                        parsingUrlType = [.Hashtags]
                    } else {
                        parsingUrlType = [.Links, .Hashtags]
                    }
                                    
                    var attributes:[MessageAttribute] = [TextEntitiesMessageAttribute(entities: comment.messageTextEntities(parsingUrlType))]
                    attributes += attrs(peerId)
                    if let sendAs = sendAs {
                        attributes.append(SendAsMessageAttribute(peerId: sendAs))
                    }
                    if withoutSound {
                        attributes.append(NotificationInfoMessageAttribute(flags: [.muted]))
                    }
                    if let date = date {
                        attributes.append(OutgoingScheduleInfoMessageAttribute(scheduleTime: Int32(date.timeIntervalSince1970), repeatPeriod: nil))
                    }
                    caption = Sender.enqueue(message: EnqueueMessage.message(text: comment.inputText, attributes: attributes, inlineStickers: [:], mediaReference: nil, threadId: threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: []), context: context, peerId: peerId)
                }
                if let caption = caption {
                    return caption |> then(forward)
                } else {
                    return forward
                }
            })
        }
        return combineLatest(signals)
        |> castError(String.self)
        |> ignoreValues
    }
    
    public override func possibilityPerformTo(_ peer:Peer) -> Bool {
        if peer.isSecretChat {
            return false
        } else if !peer.canSendMessage(false) {
            return false
        } else if let peer = peer as? TelegramChannel {
            if peer.hasBannedRights(.banSendMedia) {
                return false
            }
        }
        return true
    }
}

public final class ReplyForwardMessageObject : ShareObject {
    private let subject: EngineMessageReplySubject
    private let message: Message
    public init(_ context: any AccountContextProtocol, message: Message, subject: EngineMessageReplySubject) {
        self.subject = subject
        self.message = message
        super.init(context)
    }
    
    public override var messagesCount: Int {
        return 1
    }
    
    public override var multipleSelection: Bool {
        return false
    }
    
    public override func statusString(_ peer: Peer, presence: PeerStatusStringResult?, autoDeletion: Int32?) -> String? {
        return peer.id == context.peerId ? nil : presence?.status.string
    }

    
    public override func possibilityPerformTo(_ peer: Peer) -> Bool {
        let canSend = peer.canSendMessage(media: message.media.first)
        if peer.id.namespace == Namespaces.Peer.SecretChat {
            return false
        }
        return !excludePeerIds.contains(peer.id) && canSend
    }
    
    public override func perform(to peerIds: [PeerId], threadId: Int64?, comment: ChatTextInputState? = nil, sendPaidMessageStars:[PeerId: StarsAmount] = [:]) -> Signal<Never, String> {
        
        if let peerId = peerIds.first {
            let context = self.context
            let subject = self.subject
            let messageId = subject.messageId
            let peers = context.account.postbox.transaction { transaction -> Peer? in
                return transaction.getPeer(peerId)
            }
            
            let messages: Signal<[Message], NoError> = context.account.postbox.transaction { transaction in
                var list:[Message] = []
                if let message = transaction.getMessage(messageId) {
                    list.append(message)
                }
                return list
            }
            
            return combineLatest(messages, peers)
                |> deliverOnMainQueue
                |> castError(String.self)
                |> mapToSignal {  messages, peer in
                    
                    _ = messages.map { $0.id }
                    
                    let navigation = self.context.bindings.rootNavigation()
                    if let peer = peer {
                        
                        if let controller = navigation.controller as? ChatInterfaceController, controller.chatInteraction.chatLocation == .peer(peerId) {
                            controller.chatInteraction.update({ current in
                                current.withoutSelectionState().updatedInterfaceState {
                                    $0.withUpdatedReplyMessageId(subject)
                                }
                            })
                        } else {
                            let initialAction: ChatInitialAction = .reply(subject, behavior: .automatic)
                            
                            if let threadId = threadId {
                                return ForumUI.openTopic(threadId, peerId: peerId, context: context, animated: true, addition: true, initialAction: initialAction, isMonoforum: peer.isMonoForum) |> filter {$0}
                                |> take(1)
                                |> ignoreValues
                                |> castError(String.self)
                            }
                            
                            (navigation.controller as? ChatInterfaceController)?.chatInteraction.update({ $0.withoutSelectionState() })
                            
                            var existed: Bool = false
                            navigation.enumerateControllers { controller, _ in
                                if let controller = controller as? ChatInterfaceController, controller.chatInteraction.peerId == peerId {
                                    existed = true
                                }
                                return existed
                            }
                            let newone: ChatInterfaceController
                            
                            if existed {
                                newone = ShareUIHooks.shared.makeChatController(context, .peer(peerId), initialAction)
                            } else {
                                newone = ShareUIHooks.shared.makeChatAdditionController(context, .peer(peerId), initialAction)
                            }
                            navigation.push(newone)
                            return newone.ready.get() |> filter {$0} |> take(1) |> ignoreValues |> castError(String.self)
                        }
                    }
                    return .complete()
                }
        }
        return .complete()
    }
    
    
}

public enum ForwardMessagesResult {
    case draftPrepared
    case destinationReady
    case accepted
    case partiallyAccepted
    case rejected
    case acceptanceUnknown
    case sourceUnavailable
    case targetUnavailable
    case restricted
    case completionUnknown
}

public final class ForwardMessagesObject : ShareObject {
    fileprivate let messages: [Message]
    
    public var messageIds: [MessageId] {
        return messages.map { $0.id }
    }
    private let disposable = MetaDisposable()
    private let album: Bool
    private let getMessages:(([MessageId], Bool)->Signal<[Message], NoError>)?

    public init(_ context: any AccountContextProtocol, messages: [Message], emptyPerformOnClose: Bool = false, album: Bool = false, getMessages:(([MessageId], Bool)->Signal<[Message], NoError>)? = nil) {

        self.messages = messages
        self.album = album
        self.getMessages = getMessages
        super.init(context, emptyPerformOnClose: emptyPerformOnClose)
    }
    
    public override var messagesCount: Int {
        return messages.count
    }
    
    deinit {
        disposable.dispose()
    }
    
    public override var multipleSelection: Bool {
        return false
    }
    
    public override func possibilityPerformTo(_ peer: Peer) -> Bool {
        let canSend = messages.map {
            return peer.canSendMessage(media: $0.media.first)
        }.allSatisfy { $0 }
        return !excludePeerIds.contains(peer.id) && canSend
    }
    
    
    
    public override func perform(to peerIds: [PeerId], threadId: Int64?, comment: ChatTextInputState? = nil, sendPaidMessageStars:[PeerId: StarsAmount] = [:]) -> Signal<Never, String> {
        return (performForward(to: peerIds, threadId: threadId, comment: comment, sendPaidMessageStars: sendPaidMessageStars))
    }

    public func performObserved(to peerId: PeerId, threadId: Int64?) -> Signal<ForwardMessagesResult, String> {
        return performObserved(to: peerId, threadId: threadId, comment: nil, sendPaidMessageStars: [:])
    }

    public func performObserved(to peerId: PeerId, threadId: Int64?, comment: ChatTextInputState?, sendPaidMessageStars: [PeerId: StarsAmount]) -> Signal<ForwardMessagesResult, String> {
        return Signal { subscriber in
            var observed = false
            let signal = self.performForward(to: [peerId], threadId: threadId, comment: comment, sendPaidMessageStars: sendPaidMessageStars, observedResult: { result in
                observed = true
                subscriber.putNext(result)
            })
            return (signal).start(error: { subscriber.putError($0) }, completed: {
                if !observed { subscriber.putNext(.completionUnknown) }
                subscriber.putCompletion()
            })
        }
    }

    private func performForward(to peerIds: [PeerId], threadId: Int64?, comment: ChatTextInputState?, sendPaidMessageStars: [PeerId: StarsAmount], observedResult: ((ForwardMessagesResult) -> Void)? = nil) -> Signal<Never, String> {
        
        if peerIds.count == 1 {
            let context = self.context
            let album = self.album
            let messageIds = self.messageIds
            let comment = comment != nil ? comment!.inputText.isEmpty ? nil : comment : nil
            let peers = context.account.postbox.transaction { transaction -> Peer? in
                for peerId in peerIds {
                    if let peer = transaction.getPeer(peerId) {
                        return peer
                    }
                }
                return nil
            }
            
            let messages: Signal<[Message], NoError>
            if let getMessages = self.getMessages {
                messages = getMessages(messageIds, album)
            } else {
                messages = context.account.postbox.transaction { transaction in
                    var list:[Message] = []
                    for messageId in messageIds {
                        if let messages = transaction.getMessageGroup(messageId), album {
                            list.append(contentsOf: messages)
                        } else if let message = transaction.getMessage(messageId) {
                            list.append(message)
                        }
                    }
                    return list
                }
            }
            
            return combineLatest(messages, peers)
                |> take(1)
                |> deliverOnMainQueue
                |> castError(String.self)
                |> mapToSignal {  messages, peer in

                    let messageIds = messages.map { $0.id }
                    guard !messageIds.isEmpty else { observedResult?(.sourceUnavailable); return .complete() }
                    if peer == nil { observedResult?(.targetUnavailable); return .complete() }
                    
                    if let peer = peer, peer.isChannel {
                        for message in messages {
                            if message.isPublicPoll {
                                observedResult?(.restricted)
                                return .fail(strings().pollForwardError)
                            }
                        }
                    }
                    
                    
                    let navigation = self.context.bindings.rootNavigation()
                    if let peerId = peerIds.first {
                        if peerId == context.peerId, !messageIds.contains(where: { $0.peerId == context.peerId }) {
                            let commentResult: Signal<[MessageId?], NoError>
                            let expectedCommentCount: Int
                            if let comment = comment, !comment.inputText.isEmpty {
                                let parsingUrlType: ParsingType
                                if peerId.namespace != Namespaces.Peer.SecretChat {
                                    parsingUrlType = [.Hashtags]
                                } else {
                                    parsingUrlType = [.Links, .Hashtags]
                                }
                                let attributes:[MessageAttribute] = [TextEntitiesMessageAttribute(entities: comment.messageTextEntities(parsingUrlType))]
                                expectedCommentCount = 1
                                commentResult = Sender.enqueue(message: EnqueueMessage.message(text: comment.inputText, attributes: attributes, inlineStickers: [:], mediaReference: nil, threadId: threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: []), context: context, peerId: peerId)
                            } else {
                                expectedCommentCount = 0
                                commentResult = .single([])
                            }
                            let forwardResult = Sender.forwardMessages(messageIds: messageIds, context: context, peerId: context.account.peerId, replyId: nil, threadId: threadId)
                            let accepted = combineLatest(shareFirstResult(commentResult |> map(Optional.some), or: nil), shareFirstResult(forwardResult |> map(Optional.some), or: nil))
                            |> take(1)
                            |> deliverOnMainQueue
                            if let controller = context.bindings.rootNavigation().controller as? ChatInterfaceController {
                                controller.chatInteraction.update({$0.withoutSelectionState()})
                            }
                            return (accepted)
                            |> map { commentIds, forwardedIds in
                                let delivery = ShareRecipientDelivery(peerId: peerId, comment: expectedCommentCount == 0 ? nil : ShareDeliveryPart(expectedCount: expectedCommentCount, result: commentIds), content: ShareDeliveryPart(expectedCount: messageIds.count, result: forwardedIds))
                                switch delivery.status {
                                case .accepted:
                                    observedResult?(.accepted)
                                    delay(0.2, closure: {
                                        _ = (showModalSuccess(for: context.window, icon: theme.icons.successModalProgress, delay: 1.0)).start()
                                    })
                                case .partial: observedResult?(.partiallyAccepted)
                                case .rejected: observedResult?(.rejected)
                                case .unknown, .notAttempted: observedResult?(.acceptanceUnknown)
                                }
                            }
                            |> ignoreValues
                            |> castError(String.self)
                        } else if let peer = peer, !peer.isCommunity {
                            if peerId == context.peerId, let controller = navigation.controller as? ChatInterfaceController, controller.chatInteraction.presentation.recordingState != nil {
                                //TODOLANG
                                showModalText(for: context.window, text: "Finish or discard the current recording before forwarding to Saved Messages.")
                                observedResult?(.restricted)
                                return .complete()
                            }

                            let comment = peer.canSendMessage() ? comment : nil
                            let threadId = peerId == context.peerId ? nil : threadId

                            if threadId == nil, let controller = navigation.controller as? ChatInterfaceController, controller.chatInteraction.chatLocation == .peer(peerId), peerId != context.peerId || (controller.chatInteraction.mode == .history && controller.chatInteraction.presentation.withoutSelectionState().state == .normal) {
                                controller.chatInteraction.update({ current in
                                    current.withoutSelectionState().updatedInterfaceState {
                                        $0.withUpdatedForwardMessageIds(messageIds).withUpdatedInputState(comment ?? current.effectiveInput)
                                    }
                                })
                                observedResult?(.draftPrepared)
                            } else {
                                
                                let initialAction: ChatInitialAction = .forward(messageIds: messageIds, text: comment, behavior: .automatic)

                                if let threadId = threadId {
                                    return ForumUI.openTopic(threadId, peerId: peerId, context: context, animated: true, addition: true, initialAction: initialAction, isMonoforum: peer.isMonoForum) |> filter {$0}
                                    |> take(1)
                                    |> beforeNext { _ in observedResult?(.destinationReady) }
                                    |> ignoreValues
                                    |> castError(String.self)
                                }
                                
                                (navigation.controller as? ChatInterfaceController)?.chatInteraction.update({ $0.withoutSelectionState() })
                                
                                var existed: Bool = false
                                navigation.enumerateControllers { controller, _ in
                                    if let controller = controller as? ChatInterfaceController, controller.chatInteraction.peerId == peerId {
                                        existed = true
                                    }
                                    return existed
                                }
                                let newone: ChatInterfaceController
                                
                                if existed {
                                    newone = ShareUIHooks.shared.makeChatController(context, .peer(peerId), initialAction)
                                } else {
                                    newone = ShareUIHooks.shared.makeChatAdditionController(context, .peer(peerId), initialAction)
                                }
                                navigation.push(newone)

                                return (newone.ready.get() |> filter {$0} |> take(1) |> beforeNext { _ in observedResult?(.destinationReady) } |> ignoreValues |> castError(String.self))
                            }
                        }
                    } else {
                        if let controller = navigation.controller as? ChatInterfaceController {
                            controller.chatInteraction.update({$0.withoutSelectionState().updatedInterfaceState({$0.withUpdatedForwardMessageIds(messageIds)})})
                        }
                    }
                    return .complete()
                }
        } else {
            let navigation = self.context.bindings.rootNavigation()
            
            if let controller = navigation.controller as? ChatInterfaceController {
                controller.chatInteraction.update({ $0.withoutSelectionState() })
            }
            
            let context = self.context
            let messageIds = self.messageIds
            var signals: [Signal<[MessageId?], NoError>] = []
            let attrs:(PeerId)->[MessageAttribute] = { [weak self] peerId in
                return self?.attributes(peerId, sendPaidMessageStars: sendPaidMessageStars[peerId]) ?? []
            }
            let date = self.scheduleDate
            let withoutSound = self.withoutSound
            for peerId in peerIds {
                let viewSignal: Signal<(Peer, PeerId?), NoError> = combineLatest(context.account.postbox.loadedPeerWithId(peerId), getCachedDataView(peerId: peerId, postbox: context.account.postbox))
                |> take(1)
                |> map { peer, cachedData in
                    if let cachedData = cachedData as? CachedChannelData {
                        return (peer, cachedData.sendAsPeerId)
                    } else {
                        return (peer, nil)
                    }
                }
                let threadId = threadIds[peerId] ?? threadId
                
                signals.append(viewSignal |> mapToSignal { (peer, sendAs) in
                    let forward: Signal<[MessageId?], NoError> = Sender.forwardMessages(messageIds: messageIds, context: context, peerId: peerId, replyId: nil, threadId: threadId, silent: FastSettings.isChannelMessagesMuted(peerId) || withoutSound, atDate: date, sendAsPeerId: sendAs)
                    var caption: Signal<[MessageId?], NoError>?
                    if let comment = comment, !comment.inputText.isEmpty, peer.canSendMessage() {
                        let parsingUrlType: ParsingType
                        if peerId.namespace != Namespaces.Peer.SecretChat {
                            parsingUrlType = [.Hashtags]
                        } else {
                            parsingUrlType = [.Links, .Hashtags]
                        }
                                        
                        var attributes:[MessageAttribute] = [TextEntitiesMessageAttribute(entities: comment.messageTextEntities(parsingUrlType))]
                        attributes += attrs(peerId)
                        if let sendAs = sendAs {
                            attributes.append(SendAsMessageAttribute(peerId: sendAs))
                        }
                        
                        caption = Sender.enqueue(message: EnqueueMessage.message(text: comment.inputText, attributes: attributes, inlineStickers: [:], mediaReference: nil, threadId: threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: []), context: context, peerId: peerId)
                    }
                    if let caption = caption {
                        return (caption |> then(forward))
                    } else {
                        return (forward)
                    }
                })
            }
            return combineLatest(signals)
            |> castError(String.self)
            |> ignoreValues
        }
        
        
    }
    
    public override var searchPlaceholderKey: String {
        return "ShareModal.Search.ForwardPlaceholder"
    }
}


public enum SelectablePeersEntryStableId : Hashable {
    case plain(PeerId, ChatListIndex)
    case emptySearch
    case separator(ChatListIndex)
    case folders
    public func hash(into hasher: inout Hasher) {
        switch self {
        case let .plain(peerId, _):
            hasher.combine(peerId)
        case .separator(let index):
            hasher.combine(index)
        case .emptySearch:
            hasher.combine(0)
        case .folders:
            hasher.combine(-1)
        }
    }
}

public enum SelectablePeersEntry : Comparable, Identifiable {
    case folders([ChatListFilter], ChatListFilter)
    case secretChat(Peer, PeerId, ChatListIndex, PeerStatusStringResult?, Bool, Bool)
    //peer, index, presence, autoDeletion, separator, multiple
    case plain(RenderedPeer, ChatListIndex, PeerStatusStringResult?, Int32?, Bool, Bool)
    case separator(String, ChatListIndex)
    case emptySearch
    public var stableId: SelectablePeersEntryStableId {
        switch self {
        case let .plain(peer, index, _, _, _, _):
            return .plain(peer.peerId, index)
        case let .secretChat(_, peerId, index, _, _, _):
            return .plain(peerId, index)
        case let .separator(_, index):
            return .separator(index)
        case .emptySearch:
            return .emptySearch
        case .folders:
            return .folders
        }
    }
    
    public var index:ChatListIndex {
        switch self {
        case let .plain(_, id, _, _, _, _):
            return id
        case let .secretChat(_, _, id, _, _, _):
            return id
        case let .separator(_, index):
            return index
        case .emptySearch:
            return ChatListIndex(pinningIndex: nil, messageIndex: MessageIndex.absoluteLowerBound())
        case .folders:
            return ChatListIndex(pinningIndex: 0, messageIndex: MessageIndex.absoluteUpperBound())
        }
    }
}

public func <(lhs:SelectablePeersEntry, rhs:SelectablePeersEntry) -> Bool {
    return lhs.index < rhs.index
}

public func ==(lhs:SelectablePeersEntry, rhs:SelectablePeersEntry) -> Bool {
    switch lhs {
    case let .plain(peer, index, presence, autoDeletion, separator, multiple):
        if case .plain(peer, index, presence, autoDeletion, separator, multiple) = rhs {
            return true
        } else {
            return false
        }
    case let .secretChat(lhsPeer, peerId, index, presence, separator, multiple):
        if case .secretChat(let rhsPeer, peerId, index, presence, separator, multiple) = rhs {
            return lhsPeer.isEqual(rhsPeer)
        } else {
            return false
        }
    case let .separator(text, index):
        if case .separator(text, index) = rhs {
            return true
        } else {
            return false
        }
    case let .folders(filters, current):
        if case .folders(filters, current) = rhs {
            return true
        } else {
            return false
        }
    case .emptySearch:
        if case .emptySearch = rhs {
            return true
        } else {
            return false
        }
    }
}



fileprivate func prepareEntries(from:[SelectablePeersEntry]?, to:[SelectablePeersEntry], context: any AccountContextProtocol, initialSize:NSSize, animated:Bool, multipleSelection: Bool, selectInteraction:SelectPeerInteraction, share: ShareObject) -> TableUpdateTransition {
  
    let (deleted,inserted,updated) = proccessEntries(from, right: to, { entry -> TableRowItem in
        
        switch entry {
        case let .plain(renderedPeer, _, presence, autoDeletion, drawSeparator, multiple):
            let theme = share.presentation ?? theme
            
            guard let peer = renderedPeer.peer else {
                return .init(initialSize)
            }
            
            return ShortPeerRowItem(initialSize, peer: peer, account: context.account, context: context, stableId: entry.stableId, height: 48, photoSize:NSMakeSize(36, 36), titleStyle: ControlStyle(font: .medium(.title), foregroundColor: theme.colors.text), statusStyle: share.statusStyle(peer, presence: presence, autoDeletion: autoDeletion), status: share.statusString(peer, presence: presence, autoDeletion: autoDeletion), drawCustomSeparator: drawSeparator, isLookSavedMessage : peer.id == context.peerId, inset:NSEdgeInsets(left: 10, right: 10), drawSeparatorIgnoringInset: true, interactionType: multiple ? .selectable(selectInteraction, side: .right) : .interactable(selectInteraction), action: {
                if peer.isCommunity {
                    selectInteraction.toggleSelection(peer)
                } else if share.selectTopics, TelegramUtilsHooks.shared.peerIsForum(peer) || (peer.groupAccess.canManageDirect && peer.isMonoForum) {
                    _ = selectInteraction.openForum(peer.id, peer.isMonoForum)
                } else {
                    selectInteraction.action(peer.id, nil)
                }
            }, contextMenuItems: {
                return .single([
                    .init(strings().shareModalSelect, handler: {
                        if share.mutableSelection {
                            selectInteraction.activateSelection(peer)
                        }
                    }, itemImage: MenuAnimation.menu_select_messages.value)
                ])
            }, highlightVerified: true, customTheme: .initialize(theme), drawStarsPaid: share.messagesCount > 0 && peer.id != context.peerId ? peer.sendPaidMessageStars : nil, monoforumPeer: renderedPeer.chatOrMonoforumMainPeer)
        case let .secretChat(peer, peerId, _, _, drawSeparator, multiple):
            let theme = share.presentation ?? theme
            return ShortPeerRowItem(initialSize, peer: peer, account: context.account, context: context, peerId: peerId, stableId: entry.stableId, height: 48, photoSize:NSMakeSize(36, 36), titleStyle: ControlStyle(font: .medium(.title), foregroundColor: theme.colors.accent), statusStyle: ControlStyle(font: .normal(.text), foregroundColor: theme.colors.grayText), status: strings().composeSelectSecretChat.lowercased(), drawCustomSeparator: drawSeparator, isLookSavedMessage : peer.id == context.peerId, inset:NSEdgeInsets(left: 10, right: 10), drawSeparatorIgnoringInset: true, interactionType: multiple ? .selectable(selectInteraction, side: .right) : .plain, action: {
                selectInteraction.action(peerId, nil)
            }, customTheme: .initialize(theme))
        case let .separator(text, _):
            let theme = share.presentation ?? theme
            return SeparatorRowItem(initialSize, entry.stableId, string: text, customTheme: .initialize(theme))
        case .emptySearch:
            let theme = share.presentation ?? theme
            return SearchEmptyRowItem(initialSize, stableId: entry.stableId, icon: theme.icons.emptySearch, customTheme: .initialize(theme))
        case let .folders(filters, current):
            let theme = share.presentation ?? theme
            return ChatListRevealItem(initialSize, context: context, tabs: filters, selected: current, counters: ChatListFilterBadges(total: 0, filters: []), action: selectInteraction.updateFolder, presentation: theme, customBackgroundColor: theme.colors.background)
        }
        
        
    })
    
    
    return TableUpdateTransition(deleted: deleted, inserted: inserted, updated: updated, animated: animated, state: animated ? .none(nil) : .saveVisible(.lower, false), grouping: true, animateVisibleOnly: false)
    
}

fileprivate func canDisplaySharePeer(_ peer: Peer, share: ShareObject) -> Bool {
    if peer.isCommunity {
        return share.selectTopics || share.canSelectCommunity
    }
    return share.possibilityPerformTo(peer)
}



public class ShareModalController: ModalViewController, Notifable, TableViewDelegate {

    private enum Destination: Equatable {
        case community(PeerId)
        case forum(PeerId, isMonoforum: Bool)

        var peerId: PeerId {
            switch self {
            case let .community(peerId), let .forum(peerId, _):
                return peerId
            }
        }
    }
    
    private let recipientAction = SharePickerAction()
    private let premiumAction = SharePickerAction()
    private var pickerClosed = false

    private let share:ShareObject
    private let selectInteractions:SelectPeerInteraction = SelectPeerInteraction()
    private let search:Promise<SearchState> = Promise()
    private let destinationPeerId:ValuePromise<PeerId?> = ValuePromise(nil, ignoreRepeated: true)
    private var destinationStack: [Destination] = []
    private var communityChildPeerIds: [PeerId: Set<PeerId>] = [:]
    private let disposable:MetaDisposable = MetaDisposable()
    private let updatePremiumRequiredDisposable = MetaDisposable()
    private let exportLinkDisposable:MetaDisposable = MetaDisposable()
    private let tokenDisposable: MetaDisposable = MetaDisposable()
    private let filterDisposable = MetaDisposable()
    
    private var contextQueryState: (ChatPresentationInputQuery?, Disposable)?
    private let inputContextHelper: InputContextHelper
    private let contextChatInteraction: ChatInteraction
    
    private let communityDisposable = MetaDisposable()
    private let forumDisposable = MetaDisposable()
    
    
    private let multipleSelection: ValuePromise<Bool> = ValuePromise(false, ignoreRepeated: true)

    
    public func notify(with value: Any, oldValue: Any, animated: Bool) {
        if let value = value as? SelectPeerPresentation, let oldValue = oldValue as? SelectPeerPresentation {
            
            genericView.hasCaptionView = value.multipleSelection && !share.blockCaptionView
            genericView.hasSendView = value.multipleSelection && !share.blockCaptionView
            if value.multipleSelection && !share.blockCaptionView {
                search.set(combineLatest(genericView.tokenizedView.textUpdater, genericView.tokenizedView.stateValue.get()) |> map { SearchState(state: $1, request: $0)})
            } else {
                search.set(genericView.basicSearchView.searchValue)
            }
            
            self.multipleSelection.set(value.multipleSelection)
            
            if value.selected != oldValue.selected || value.comment != oldValue.comment {
                recipientAction.reset()
                premiumAction.reset()
            }
            let added = value.selected.subtracting(oldValue.selected)
            let removed = oldValue.selected.subtracting(value.selected)

            
            let selected = value.selected.filter {
                $0.namespace._internalGetInt32Value() != ChatListFilterPeerCategories.Namespace
            }
            
            if let limit = self.share.limit, selected.count > limit, added.count == 1 {
                DispatchQueue.main.async { [unowned self] in
                    self.selectInteractions.update(animated: true, { current in
                        var current = current
                        for peerId in added {
                            if let peer = current.peers[peerId] {
                                current = current.withToggledSelected(peerId, peer: peer)
                            }
                        }
                        return current
                    })
                    self.share.limitReached()
                }
                return
            }
            
            let tokens:[SearchToken] = added.map { item in
                let title = item == share.context.account.peerId ? strings().peerSavedMessages : value.peers[item]?.compactDisplayTitle ?? strings().peerDeletedUser
                return SearchToken(name: title, uniqueId: item.toInt64())
            }
            genericView.tokenizedView.addTokens(tokens: tokens, animated: animated)
            genericView.sendButton.isEnabled = !value.selected.isEmpty || share.alwaysEnableDone
            let idsToRemove:[Int64] = removed.map {
                $0.toInt64()
            }
            genericView.tokenizedView.removeTokens(uniqueIds: idsToRemove, animated: animated)
            self.modal?.interactions?.updateEnables(!value.selected.isEmpty || share.alwaysEnableDone)
            
            if value.inputQueryResult != oldValue.inputQueryResult {
                inputContextHelper.context(with: value.inputQueryResult, for: self.genericView, relativeView: self.genericView.textContainerView, position: .above, selectIndex: nil, animated: animated)
            }
            if let (possibleQueryRange, possibleTypes, _) = textInputStateContextQueryRangeAndType(ChatTextInputState(inputText: value.comment.string, selectionRange: value.comment.range.min ..< value.comment.range.max, attributes: []), includeContext: false) {
                if possibleTypes.contains(.mention) {
                    let peers: [Peer] = value.peers.compactMap { (_, value) in
                        if value.isGroup || value.isSupergroup {
                            return value
                        } else {
                            return nil
                        }
                    }
                    let query = String(value.comment.string[possibleQueryRange])
                    if let (updatedContextQueryState, updatedContextQuerySignal) = chatContextQueryForSearchMention(chatLocations: peers.map { .peer($0.id) }, .mention(query: query, includeRecent: false), currentQuery: self.contextQueryState?.0, context: share.context) {
                        self.contextQueryState?.1.dispose()
                        var inScope = true
                        var inScopeResult: ((ChatPresentationInputQueryResult?) -> ChatPresentationInputQueryResult?)?
                        self.contextQueryState = (updatedContextQueryState, (updatedContextQuerySignal |> deliverOnMainQueue).start(next: { [weak self] result in
                            if let strongSelf = self {
                                if Thread.isMainThread && inScope {
                                    inScope = false
                                    inScopeResult = result
                                } else {
                                    strongSelf.selectInteractions.update(animated: animated, {
                                        $0.updatedInputQueryResult { previousResult in
                                            return result(previousResult)
                                        }
                                    })
                                    
                                }
                            }
                        }))
                        inScope = false
                        if let inScopeResult = inScopeResult {
                            selectInteractions.update(animated: animated, {
                                $0.updatedInputQueryResult { previousResult in
                                    return inScopeResult(previousResult)
                                }
                            })
                        }
                    } else {
                        selectInteractions.update(animated: animated, {
                            $0.updatedInputQueryResult { _ in
                                return nil
                            }
                        })
                    }
                } else {
                    selectInteractions.update(animated: animated, {
                        $0.updatedInputQueryResult { _ in
                            return nil
                        }
                    })
                }
            } else {
                selectInteractions.update(animated: animated, {
                    $0.updatedInputQueryResult { _ in
                        return nil
                    }
                })
            }
        } else if let value = value as? ChatPresentationInterfaceState, let oldValue = oldValue as? ChatPresentationInterfaceState {
            if value.effectiveInput != oldValue.effectiveInput {
                updateInput(value, prevState: oldValue, animated)
            }
        }
        
       // _ = self.window?.makeFirstResponder(firstResponder())
    }
    
    private func updateInput(_ state:ChatPresentationInterfaceState, prevState: ChatPresentationInterfaceState, _ animated:Bool = true) -> Void {
        
        genericView.textView.set(state.effectiveInput)

//        if textView.string() != state.effectiveInput.inputText || state.effectiveInput.attributes != prevState.effectiveInput.attributes  {
//            textView.animates = false
//            textView.setAttributedString(state.effectiveInput.attributedString(), animated:animated)
//            textView.animates = true
//        }
//        let range = NSMakeRange(state.effectiveInput.selectionRange.lowerBound, state.effectiveInput.selectionRange.upperBound - state.effectiveInput.selectionRange.lowerBound)
//        if textView.selectedRange().location != range.location || textView.selectedRange().length != range.length {
//            textView.setSelectedRange(range)
//        }
      //  textViewTextDidChangeSelectedRange(range)
    }
    
    public func isEqual(to other: Notifable) -> Bool {
        if let other = other as? ModalViewController {
            return other == self
        }
        return false
    }
    
    fileprivate var genericView:ShareModalView {
        return self.view as! ShareModalView
    }
    
    public override func viewClass() -> AnyClass {
        return ShareModalView.self
    }
    
    public override func initializer() -> NSView {
        let vz = viewClass() as! ShareModalView.Type
        return vz.init(frame: NSMakeRect(_frameRect.minX, _frameRect.minY, _frameRect.width, _frameRect.height - bar.height), shareObject: share, presentation: self.presentation);
    }

    
    public override var modal: Modal? {
        didSet {
            modal?.interactions?.updateEnables(false)
        }
    }
    
    public func selectionDidChange(row: Int, item: TableRowItem, byClick: Bool, isNew: Bool) {
        
    }
    
    public func selectionWillChange(row: Int, item: TableRowItem, byClick: Bool) -> Bool {
        return !selectInteractions.presentation.multipleSelection && !(item is SeparatorRowItem)
    }
    
    public func isSelectable(row: Int, item: TableRowItem) -> Bool {
        return !selectInteractions.presentation.multipleSelection
    }
    
    public func findGroupStableId(for stableId: AnyHashable) -> AnyHashable? {
        return nil
    }
    


    private func activate(_ item: TableRowItem, in tableView: TableView) {
        do {
            _ = tableView.select(item: item)
            if let item = item as? ShortPeerRowItem {
                switch item.interactionType {
                case .selectable:
                    selectInteractions.activateSelection(item.peer)
                default:
                    item.action()
                }
            } else if let item = item as? GeneralRowItem {
                item.action()
            }
        }
    }

    private func invokeShortCut(_ index: Int) {
        let tableView = genericView.activeTableView
        if tableView.count > index {
            activate(tableView.item(at: index), in: tableView)
        }
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        let context = self.share.context
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.activeTableView.highlightPrev()
            return .invoked
        }, with: self, for: .UpArrow, priority: .modal)
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.activeTableView.highlightNext()
            return .invoked
        }, with: self, for: .DownArrow, priority: .modal)
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            guard let `self` = self else {return .rejected}
            let tableView = self.genericView.activeTableView
            if let highlighted = tableView.highlightedItem() {
                self.activate(highlighted, in: tableView)
            }
            
            return .rejected
        }, with: self, for: .Return, priority: .low)
        
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            do {
                self?.selectInteractions.action(context.peerId, nil)
            }
            return .invoked
        }, with: self, for: .Zero, priority: self.responderPriority, modifierFlags: [.command])
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.invokeShortCut(0)
            return .invoked
        }, with: self, for: .One, priority: self.responderPriority, modifierFlags: [.command])
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.invokeShortCut(1)
            return .invoked
        }, with: self, for: .Two, priority: self.responderPriority, modifierFlags: [.command])
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.invokeShortCut(2)
            return .invoked
        }, with: self, for: .Three, priority: self.responderPriority, modifierFlags: [.command])
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.invokeShortCut(3)
            return .invoked
        }, with: self, for: .Four, priority: self.responderPriority, modifierFlags: [.command])
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.invokeShortCut(4)
            return .invoked
        }, with: self, for: .Five, priority: self.responderPriority, modifierFlags: [.command])
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.invokeShortCut(5)
            return .invoked
        }, with: self, for: .Six, priority: self.responderPriority, modifierFlags: [.command])
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.invokeShortCut(6)
            return .invoked
        }, with: self, for: .Seven, priority: self.responderPriority, modifierFlags: [.command])
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.invokeShortCut(7)
            return .invoked
        }, with: self, for: .Eight, priority: self.responderPriority, modifierFlags: [.command])
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.invokeShortCut(8)
            return .invoked
        }, with: self, for: .Nine, priority: self.responderPriority, modifierFlags: [.command])
        
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.textView.inputApplyTransform(.attribute(TextInputAttributes.bold))
            return .invoked
        }, with: self, for: .B, priority: self.responderPriority, modifierFlags: [.command])
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.textView.inputApplyTransform(.url)
            return .invoked
        }, with: self, for: .U, priority: self.responderPriority, modifierFlags: [.command])
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.textView.inputApplyTransform(.attribute(TextInputAttributes.italic))
            return .invoked
        }, with: self, for: .I, priority: self.responderPriority, modifierFlags: [.command])
        
        self.window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.textView.inputApplyTransform(.attribute(TextInputAttributes.monospace))
            return .invoked
        }, with: self, for: .K, priority: self.responderPriority, modifierFlags: [.command, .shift])
    }
    
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.window?.removeAllHandlers(for: self)
        self.contextChatInteraction.remove(observer: self)
    }
    
    public override var handleAllEvents: Bool {
        return true
    }
    
    public override var responderPriority: HandlerPriority {
        return .modal
    }
    
    private func clearDestinationSearch() {
        genericView.basicSearchView.setString("")
        genericView.tokenizedView.setString("")
    }

    private func pushDestination(_ destination: Destination) {
        guard destinationStack.last != destination else {
            return
        }
        destinationStack.append(destination)
        destinationPeerId.set(destination.peerId)
    }

    private func openForum(_ peerId: PeerId, isMonoforum: Bool, animated: Bool) {
        guard !pickerClosed else { return }
        recipientAction.reset()
        premiumAction.reset()
        let destination: Destination = .forum(peerId, isMonoforum: isMonoforum)
        guard destinationStack.last != destination else {
            return
        }
        pushDestination(destination)
        clearDestinationSearch()

        let context = share.context
        let selectInteractions = self.selectInteractions
        var filter = chatListViewForLocation(chatListLocation: isMonoforum ? .savedMessagesChats(peerId: peerId) : .forum(peerId: peerId), location: .Initial(100, nil), filter: nil, account: context.account) |> filter {
            !$0.list.isLoading
        } |> take(1)
        filter = showModalProgress(signal: filter, for: context.window)
        let signal: Signal<[EngineChatList.Item], NoError> = combineLatest(filter, self.search.get()) |> map { update, query in
            let items = update.list.items.reversed().filter {
                $0.renderedPeer.peer?._asPeer().canSendMessage(true, threadData: $0.threadData) ?? true
            }
            if query.request.isEmpty {
                return items
            } else {
                return items.filter { item in
                    let title = item.threadData?.info.title ?? ""
                    return title.lowercased().contains(query.request.lowercased())
                }
            }
        } |> deliverOnMainQueue
        
        
        forumDisposable.set((signal).start(next: { [weak self] items in
            self?.genericView.appearForumTopics(items, peerId: peerId, interactions: selectInteractions, delegate: self, context: context, animated: animated)
        }))


    }

    private func openCommunity(_ peerId: PeerId, animated: Bool) {
        guard !pickerClosed else { return }
        recipientAction.reset()
        premiumAction.reset()
        let destination: Destination = .community(peerId)
        guard destinationStack.last != destination else {
            return
        }
        pushDestination(destination)
        clearDestinationSearch()

        let context = share.context
        let share = self.share
        let selectInteractions = self.selectInteractions

        context.account.viewTracker.forceUpdateCachedPeerData(peerId: peerId)

        let linkedPeerIds: Signal<[PeerId], NoError> = context.engine.data.subscribe(
            TelegramEngine.EngineData.Item.Peer.CachedData(id: peerId)
        )
        |> mapToSignal { cachedData -> Signal<[PeerId], NoError> in
            guard let cachedData = cachedData as? CachedCommunityData else {
                return .never()
            }
            return .single(cachedData.linkedPeers.compactMap { linkedPeer in
                return linkedPeer.peerId == peerId ? nil : linkedPeer.peerId
            })
        }
        |> distinctUntilChanged

        let childPeers: Signal<[Peer], NoError> = linkedPeerIds
        |> mapToSignal { peerIds -> Signal<[Peer], NoError> in
            if peerIds.isEmpty {
                return .single([])
            }
            return context.engine.data.subscribe(
                EngineDataMap(peerIds.map { TelegramEngine.EngineData.Item.Peer.Peer(id: $0) })
            )
            |> map { peers -> [Peer] in
                return peerIds.compactMap { peerId in
                    guard let peer = peers[peerId] ?? nil else {
                        return nil
                    }
                    return peer._asPeer()
                }
            }
        }
        |> take(1)

        let loaded = showModalProgress(
            signal: childPeers,
            for: context.window
        )
        let signal: Signal<(Set<PeerId>, [Peer]), NoError> = combineLatest(loaded, self.search.get()) |> map { peers, query -> (Set<PeerId>, [Peer]) in
            let items = peers.filter { peer in
                return !peer.isCommunity && share.possibilityPerformTo(peer)
            }
            let childPeerIds = Set(items.map { $0.id })
            if query.request.isEmpty {
                return (childPeerIds, items)
            } else {
                return (childPeerIds, items.filter { $0.displayTitle.lowercased().contains(query.request.lowercased()) })
            }
        } |> deliverOnMainQueue

        communityDisposable.set((signal).start(next: { [weak self] childPeerIds, peers in
            guard let self else {
                return
            }
            if self.communityChildPeerIds[peerId] != childPeerIds {
                self.communityChildPeerIds[peerId] = childPeerIds
                selectInteractions.refreshSelection(animated: true)
            }
            self.genericView.appearCommunityChats(peers, interactions: selectInteractions, delegate: self, context: context, animated: animated, multipleSelection: self.share.multipleSelection)
        }))
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: self.presentation ?? theme)
    }
    
    public func processEnter(_ event: NSEvent) -> Bool {
        if FastSettings.checkSendingAbility(for: event) {
            return true
        }
        return false
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()

        selectInteractions.isPeerSelected = { [weak self] peerId, peer, presentation in
            guard let self,
                  peer.isCommunity,
                  self.share.selectTopics,
                  !self.share.canSelectCommunity else {
                return presentation.selected.contains(peerId)
            }
            guard let childPeerIds = self.communityChildPeerIds[peerId] else {
                return false
            }
            return !childPeerIds.isDisjoint(with: presentation.selected)
        }
        
        if let link = self.share as? ShareLinkObject, let text = link.text, !text.isEmpty {
            self.genericView.textView.interactions.update({ _ in
                return .init(inputText: .initialize(string: text))
            })
            self.contextChatInteraction.update({
                $0.withUpdatedEffectiveInputState(self.genericView.textView.interactions.presentation.textInputState())
            })
        }
        
        self.genericView.textView.interactions.inputDidUpdate = { [weak self] state in
            guard let `self` = self else {
                return
            }
            self.set(state)
            self.inputDidUpdateLayout(animated: true)
        }
        
        self.genericView.textView.interactions.processEnter = { [weak self] event in
            return self?.processEnter(event) ?? true
        }
        self.genericView.textView.interactions.processPaste = { pasteboard in
            return false
        }
        self.genericView.textView.interactions.processAttriburedCopy = { attributedString in
            return LinkHooks.shared.globalLinkExecutor().copyAttributedString(attributedString)
        }
        
        contextChatInteraction.movePeerToInput = { [weak self] (peer) in
            if let strongSelf = self {
                let textInputState = strongSelf.contextChatInteraction.presentation.effectiveInput
                if let (range, _, _) = textInputStateContextQueryRangeAndType(textInputState, includeContext: false) {
                    let inputText = textInputState.inputText
                    
                    let name:String = peer.addressName ?? peer.compactDisplayTitle
                    
                    let distance = inputText.distance(from: range.lowerBound, to: range.upperBound)
                    let replacementText = name + " "
                    
                    let atLength = peer.addressName != nil ? 0 : 1
                    
                    let range = strongSelf.contextChatInteraction.appendText(replacementText, selectedRange: textInputState.selectionRange.lowerBound - distance - atLength ..< textInputState.selectionRange.upperBound)
                    
                    if peer.addressName == nil {
                        let state = strongSelf.contextChatInteraction.presentation.effectiveInput
                        var attributes = state.attributes
                        attributes.append(.uid(range.lowerBound ..< range.upperBound - 1, peer.id.id._internalGetInt64Value()))
                        let updatedState = ChatTextInputState(inputText: state.inputText, selectionRange: state.selectionRange, attributes: attributes)
                        strongSelf.contextChatInteraction.update({$0.withUpdatedEffectiveInputState(updatedState)})
                    }
                }
            }
        }
        
        genericView.presentation = presentation
        
        
        let initialSize = self.atomicSize.modify({$0})
        let context = self.share.context
        let share = self.share
        let selectInteraction = self.selectInteractions
        selectInteraction.add(observer: self)
        
        
        selectInteractions.update(animated: false, {
            $0.withUpdatedMultipleSelection(share.multipleSelection)
        })
        
        if share.multipleSelection {
            search.set(combineLatest(genericView.tokenizedView.textUpdater, genericView.tokenizedView.stateValue.get()) |> map { SearchState(state: $1, request: $0)})
        } else {
            search.set(genericView.basicSearchView.searchValue)
        }
        self.multipleSelection.set(share.multipleSelection)
        
        
        self.notify(with: self.selectInteractions.presentation, oldValue: self.selectInteractions.presentation, animated: false)
        self.contextChatInteraction.add(observer: self)

        self.genericView.textView.context = context
        self.genericView.tableView.delegate = self
        
        let interactions = EntertainmentInteractions(.emoji, peerId: PeerId(0))
        interactions.sendEmoji = { [weak self] emoji, fromRect in
            _ = self?.contextChatInteraction.appendText(.initialize(string: emoji))
            _ = self?.window?.makeFirstResponder(self?.genericView.textView.inputView)
        }
        interactions.sendAnimatedEmoji = { [weak self] sticker, _, _, _, fromRect in
            let text = (sticker.file._parse().customEmojiText ?? sticker.file._parse().stickerText ?? "😀").fixed
            _ = self?.contextChatInteraction.appendText(.makeAnimated(sticker.file._parse(), text: text))
            _ = self?.window?.makeFirstResponder(self?.genericView.textView.inputView)
        }
        emoji.update(with: interactions, chatInteraction: self.contextChatInteraction)
        
        genericView.emojiButton.set(handler: { [weak self] control in
            self?.showEmoji(for: control)
        }, for: .Hover)

        
        genericView.hasShareMenu = self.share.hasLink
        let presentation = self.presentation
        
        
        genericView.dismiss.set(handler: { [weak self] _ in
            if self?.destinationStack.isEmpty == false {
                self?.popDestination(animated: true)
            } else {
                self?.close()
            }
        }, for: .Click)
        
              
     
        
        let previous:Atomic<[SelectablePeersEntry]?> = Atomic(value: nil)
        
        selectInteraction.premiumRequiredAction = { [weak self] peerId in
            self?.showPremiumRequired(peerId)
        }

        selectInteraction.action = { [weak self] peerId, threadId in
            guard let self else { return }
            self.selectRecipient(peerId, threadId: threadId)
        }

        selectInteraction.openForum = { [weak self] peerId, isMonoforum in
            if share.selectTopics {
                self?.openForum(peerId, isMonoforum: isMonoforum, animated: true)
            }
            return share.selectTopics
        }

        selectInteraction.openCommunity = { [weak self] peerId in
            if share.selectTopics {
                self?.openCommunity(peerId, animated: true)
            }
            return share.selectTopics
        }

        genericView.share.contextMenu = { [weak self] in
            let menu = ContextMenu(presentation: .current(presentation?.colors ?? theme.colors))
            menu.addItem(ContextMenuItem(strings().modalCopyLink, handler: {
                if share.hasLink {
                    share.shareLink()
                    if let window = self?.window {
                        showModalText(for: window, text: strings().shareLinkCopied)
                    }
                }
            }, itemImage: MenuAnimation.menu_copy_link.value))
            return menu
        }
        
        genericView.sendButton.set(handler: { [weak self] _ in
            if let strongSelf = self, !selectInteraction.presentation.selected.isEmpty {
                _ = strongSelf.invoke()
            }
        }, for: .SingleClick)
        

        genericView.sendWithoutSound = { [weak self] in
            self?.share.withoutSound = true
            _ = self?.invoke()
        }
        genericView.scheduleMessage = { [weak self] in
            guard let share = self?.share else {
                return
            }
            let context = share.context
            let peerId = share.context.peerId
            FeatureNavigationHooks.shared.selectDate(context, context.window, nil, nil, .schedule(peerId), { date, _ in
                self?.share.scheduleDate = date
                _ = self?.invoke()
            })
        }
        
        genericView.scheduleWhenOnline = { [weak self] in
            guard let share = self?.share else {
                return
            }
            _ = share.context
            _ = share.context.peerId
            self?.share.scheduleDate = scheduleWhenOnlineDate
            _ = self?.invoke()
        }
        
        tokenDisposable.set(genericView.tokenizedView.tokensUpdater.start(next: { tokens in
            let ids = Set(tokens.map({PeerId($0.uniqueId)}))
            let unselected = selectInteraction.presentation.selected.symmetricDifference(ids)
            
            selectInteraction.update( { unselected.reduce($0, { current, value in
                return current.deselect(peerId: value)
            })})

        }))
        

        
        
        let defaultItems = context.account.postbox.transaction { transaction -> [Peer] in
            var peers:[Peer] = []
            
            if let addition = share.additionTopItems {
                for item in addition.items {
                    if share.defaultSelectedIds.contains(item.peer.id) {
                        peers.append(item.peer)
                    }
                }
            }
           
            for peerId in share.defaultSelectedIds  {
                if let peer = transaction.getPeer(peerId) {
                    peers.append(peer)
                }
            }
            return peers
        }
        
        
        
        let filter = ValuePromise<FilterData>(ignoreRepeated: true)
        let filterValue = Atomic<FilterData>(value: FilterData(filter: .allChats, tabs: [], sidebar: false, request: .Initial(50, nil)))
        
        let updateFilter:((FilterData)->FilterData)->Void = { [weak self] f in
            let previous = filterValue.with { $0 }
            let data = filterValue.modify(f)
            if previous.filter != data.filter {
                self?.genericView.tableView.scroll(to: .up(true))
            }
            filter.set(data)
        }
        
        
        
        if share.hasFolders {
            var first: Bool = true
            let filterView = chatListFilterPreferences(engine: context.engine) |> deliverOnMainQueue
            filterDisposable.set(filterView.start(next: { filters in
                updateFilter( { current in
                    var current = current
                    current = current.withUpdatedTabs(filters.list)
                    if !first, let updated = filters.list.first(where: { ShareUIHooks.shared.chatListFilterId($0) == ShareUIHooks.shared.chatListFilterId(current.filter) }) {
                        current = current.withUpdatedFilter(updated)
                    } else {
                        current = current.withUpdatedFilter(.allChats)
                    }
                    return current
                } )
                first = false
            }))
            
        } else {
            filter.set(.init())
        }
       
        genericView.tableView.set(stickClass: ChatListRevealItem.self, handler: { _ in
            
        })
                
        selectInteraction.updateFolder = { filter in
            updateFilter {
                $0.withUpdatedFilter(filter)
            }
        }
        
        let chatList: Signal<(EngineChatList, FilterData), NoError> = filter.get() |> mapToSignal { data in
            let signal = chatListViewForLocation(chatListLocation: .chatList(groupId: .root), location: data.request, filter: data.filter, account: context.account) |> take(1)
            return  signal |> map { view in
                return (view.list, data)
            }
        }
        
        
        let list:Signal<TableUpdateTransition, NoError> = combineLatest(queue: prepareQueue, search.get() |> distinctUntilChanged, destinationPeerId.get(), multipleSelection.get(), chatList) |> mapToSignal { query, destinationPeerId, multipleSelection, chatList -> Signal<TableUpdateTransition, NoError> in
            
            if query.request.isEmpty {
                if !multipleSelection && query.state == .Focus && destinationPeerId == nil {
                    return combineLatest(context.account.postbox.loadedPeerWithId(context.peerId), context.engine.peers.recentPeers() |> deliverOnPrepareQueue, context.engine.peers.recentlySearchedPeers() |> deliverOnPrepareQueue) |> map { user, rawTop, recent -> TableUpdateTransition in
                        
                        var entries:[SelectablePeersEntry] = []
                        
                        let top:[Peer]
                        switch rawTop {
                        case let .peers(peers):
                            top = peers
                        default:
                            top = []
                        }
                        
                        
                        var contains:[PeerId:PeerId] = [:]
                        
                        var indexId:Int32 = Int32.max
                        
                        let chatListIndex:()-> ChatListIndex = {
                            let index = MessageIndex(id: MessageId(peerId: PeerId(0), namespace: 1, id: indexId), timestamp: indexId)
                            indexId -= 1
                            return ChatListIndex(pinningIndex: nil, messageIndex: index)
                        }
                        
                        
                        entries.append(.plain(.init(peer: user), ChatListIndex(pinningIndex: 0, messageIndex: MessageIndex(id: MessageId(peerId: PeerId(0), namespace: 0, id: Int32.max), timestamp: Int32.max)), nil, nil, top.isEmpty && recent.isEmpty, multipleSelection))
                        contains[user.id] = user.id
                        
                        if !top.isEmpty {
                            entries.insert(.separator(strings().searchSeparatorPopular.uppercased(), chatListIndex()), at: 0)
                            
                            var count: Int32 = 0
                            for peer in top {
                                if contains[peer.id] == nil {
                                    if canDisplaySharePeer(peer, share: share) {
                                        entries.insert(.plain(.init(peer: peer), chatListIndex(), nil, nil, count < 4, multipleSelection), at: 0)
                                        contains[peer.id] = peer.id
                                        count += 1
                                    }
                                }
                                if count >= 5 {
                                    break
                                }
                            }
                        }
                        
                        if !recent.isEmpty {
                            
                            entries.insert(.separator(strings().searchSeparatorRecent.uppercased(), chatListIndex()), at: 0)
                            
                            for rendered in recent {
                                if let peer = rendered.peer.chatMainPeer {
                                    if contains[peer.id] == nil {
                                        if canDisplaySharePeer(peer, share: share) {
                                            entries.insert(.plain(rendered.peer, chatListIndex(), nil, nil, true, multipleSelection), at: 0)
                                            contains[peer.id] = peer.id
                                        }
                                    }
                                }
                            }
                        }
                        
                        entries.sort(by: <)
                        
                        return prepareEntries(from: previous.swap(entries), to: entries, context: context, initialSize: initialSize, animated: true, multipleSelection: multipleSelection, selectInteraction:selectInteraction, share: share)
                        
                    } |> take(1)
                } else {
                    var peerIds:[PeerId] = []
                    for entry in chatList.0.items {
                        peerIds.append(entry.renderedPeer.peerId)

                    }
                    let keys = peerIds.map {PostboxViewKey.peer(peerId: $0, components: .all)}
                    return combineLatest(context.account.postbox.combinedView(keys: keys), context.account.postbox.loadedPeerWithId(context.peerId)) |> map { values, selfPeer -> (EngineChatList, FilterData, [PeerId: PeerStatusStringResult], Peer) in
                        var presences:[PeerId: PeerStatusStringResult] = [:]
                        for value in values.views {
                            if let view = value.value as? PeerView {
                                presences[view.peerId] = stringStatus(for: view, context: context, theme: .init(presentation?.colors ?? theme.colors))
                            }
                        }
                        return (chatList.0, chatList.1, presences, selfPeer)
                    } |> deliverOn(prepareQueue) |> take(1) |> map { value -> TableUpdateTransition in
                        var entries:[SelectablePeersEntry] = []
                        
                        
                        
                        var contains:[PeerId:PeerId] = [:]
                        
                        var offset: Int32 = Int32.max
                        
                        if let additionTopItems = share.additionTopItems {
                            var index = ChatListIndex(pinningIndex: 0, messageIndex: MessageIndex(id: MessageId(peerId: PeerId(0), namespace: 0, id: offset), timestamp: offset))

                            if !additionTopItems.topSeparator.isEmpty {
                                entries.append(.separator(additionTopItems.topSeparator, index))
                                offset -= 1
                            }
                            
                            
                            for item in additionTopItems.items {
                                index = ChatListIndex(pinningIndex: 0, messageIndex: MessageIndex(id: MessageId(peerId: PeerId(0), namespace: 0, id: offset), timestamp: offset))
                                let theme = PeerStatusStringTheme(titleColor: presentation?.colors.text ?? theme.colors.text, statusColor: presentation?.colors.grayText ?? theme.colors.grayText)
                                
                                let status = NSAttributedString.initialize(string: item.status, color: theme.statusColor, font: theme.statusFont)
                                let title = NSAttributedString.initialize(string: item.peer.displayTitle, color: theme.titleColor, font: theme.titleFont)
                                entries.append(.plain(.init(peer: item.peer), index, PeerStatusStringResult(title, status), nil, true, multipleSelection && additionTopItems.selectable))
                                offset -= 1
                            }
                            if !additionTopItems.bottomSeparator.isEmpty {
                                index = ChatListIndex(pinningIndex: 0, messageIndex: MessageIndex(id: MessageId(peerId: PeerId(0), namespace: 0, id: offset), timestamp: offset))
                                entries.append(.separator(additionTopItems.bottomSeparator, index))
                                offset -= 1
                            }
                        }
                        
                        if !share.excludePeerIds.contains(value.3.id), value.1.isEmpty || value.1.filter == .allChats {
                            entries.append(.plain(.init(peer: value.3), ChatListIndex(pinningIndex: 0, messageIndex: MessageIndex(id: MessageId(peerId: PeerId(0), namespace: 0, id: offset), timestamp: offset)), nil, nil, true, multipleSelection))
                            contains[value.3.id] = value.3.id
                        }
                        
                        for item in value.0.items {
                            if let main = item.renderedPeer.peer?._asPeer() {
                                if contains[main.id] == nil {
                                    if canDisplaySharePeer(main, share: share) {
                                        if let peer = item.renderedPeer.chatMainPeer?._asPeer() {
                                            if main.id.namespace == Namespaces.Peer.SecretChat {
                                                entries.append(.secretChat(peer, main.id, item.chatListIndex, value.2[peer.id], true, multipleSelection))
                                            } else {
                                                entries.append(.plain(.init(item.renderedPeer), item.chatListIndex, value.2[peer.id], item.autoremoveTimeout, true, multipleSelection))
                                            }
                                        }
                                        contains[main.id] = main.id
                                    }
                                }
                            }
                        }
                        
                        if !value.1.isEmpty {
                            entries.append(.folders(value.1.tabs, value.1.filter))
                        }
                        
                        entries.sort(by: <)
                        
                        return prepareEntries(from: previous.swap(entries), to: entries, context: context, initialSize: initialSize, animated: true, multipleSelection: multipleSelection, selectInteraction:selectInteraction, share: share)
                    }
                }
                
                
            } else if destinationPeerId == nil {
                
                
                var all = query.request.transformKeyboard
                all.insert(query.request.lowercased(), at: 0)
                all = all.uniqueElements
                let localPeers = combineLatest(all.map {
                    return context.account.postbox.searchPeers(query: $0)
                }) |> map { result in
                    return result.reduce([], {
                        return $0 + $1
                    })
                }
                
                let remotePeers = Signal<[RenderedPeer], NoError>.single([]) |> then( context.engine.contacts.searchRemotePeers(query: query.request.lowercased()) |> map { $0.0.map {RenderedPeer($0)} + $0.1.map {RenderedPeer($0)} } )
                
                return combineLatest(localPeers, remotePeers) |> map {$0 + $1} |> mapToSignal { peers -> Signal<([RenderedPeer], [PeerId: PeerStatusStringResult], Peer), NoError> in
                    let keys = peers.map {PostboxViewKey.peer(peerId: $0.peerId, components: .all)}
                    return combineLatest(context.account.postbox.combinedView(keys: keys), context.account.postbox.loadedPeerWithId(context.peerId)) |> map { values, selfPeer -> ([RenderedPeer], [PeerId: PeerStatusStringResult], Peer) in
                        
                        var presences:[PeerId: PeerStatusStringResult] = [:]
                        for value in values.views {
                            if let view = value.value as? PeerView {
                                presences[view.peerId] = stringStatus(for: view, context: context, theme: .init(presentation?.colors ?? theme.colors))
                            }
                        }
                        
                        return (peers, presences, selfPeer)
                        
                    } |> take(1)
                } |> deliverOn(prepareQueue) |> map { values -> TableUpdateTransition in
                        var entries:[SelectablePeersEntry] = []
                        var contains:[PeerId:PeerId] = [:]
                        var i:Int32 = Int32.max
                        if query.request.isSavedMessagesText || values.0.contains(where: {$0.peerId == context.peerId}), !share.excludePeerIds.contains(values.2.id) {
                            let index = MessageIndex(id: MessageId(peerId: PeerId(0), namespace: 0, id: i), timestamp: i)
                            entries.append(.plain(.init(peer: values.2), ChatListIndex(pinningIndex: 0, messageIndex: index), nil, nil, true, multipleSelection))
                            i -= 1
                            contains[values.2.id] = values.2.id
                        }
                        for renderedPeer in values.0 {
                            if let main = renderedPeer.peer {
                                if contains[main.id] == nil {
                                    if canDisplaySharePeer(main, share: share) {
                                        if let peer = renderedPeer.chatMainPeer {
                                            
                                            let index = MessageIndex(id: MessageId(peerId: PeerId(0), namespace: 0, id: i), timestamp: i)
                                            let id = ChatListIndex(pinningIndex: nil, messageIndex: index)
                                            i -= 1
                                                                                        
                                            if main.id.namespace == Namespaces.Peer.SecretChat {
                                                entries.append(.secretChat(peer, main.id, id, values.1[peer.id], true, multipleSelection))
                                            } else {
                                                entries.append(.plain(renderedPeer, id, values.1[peer.id], nil, true, multipleSelection))
                                            }
                                        }
                                        contains[main.id] = main.id
                                    }
                                }
                            }
                        }
                        if entries.isEmpty {
                            entries.append(.emptySearch)
                        }
                    
                        entries.sort(by: <)
                    
                        return prepareEntries(from: previous.swap(entries), to: entries, context: context, initialSize: initialSize, animated: false, multipleSelection: multipleSelection, selectInteraction:selectInteraction, share: share)
                }
            } else {
                return .complete()
            }
        } |> deliverOnMainQueue
        
        let signal:Signal<TableUpdateTransition, NoError> = defaultItems |> deliverOnMainQueue |> mapToSignal { [weak self] defaultSelected in
            
            self?.selectInteractions.update(animated: false, { value in
                var value = value
                for peer in defaultSelected {
                    value = value.withToggledSelected(peer.id, peer: peer)
                }
                return value
            })
            
            return list
        } |> deliverOnMainQueue
        
        disposable.set(signal.start(next: { [weak self] transition in
            self?.genericView.applyTransition(transition)
            self?.updatePremiumRequired()
            self?.readyOnce()
        }))
    }

    private func updatePremiumRequired() {
        var ids: [EnginePeer.Id] = []
        let context = self.share.context
        genericView.tableView.enumerateItems(with: { item in
            if let item = item as? ShortPeerRowItem {
                if item.peerId != context.peerId, item.peerId.namespace != Namespaces.Peer.SecretChat {
                    ids.append(item.peerId)
                }
            }
            return true
        })
        if !context.isPremium {
            let signal = context.engine.peers.isPremiumRequiredToContact(ids) |> deliverOnMainQueue
            
            updatePremiumRequiredDisposable.set(signal.startStrict(next: { [weak self] peerIds in
                self?.selectInteractions.update {
                    $0.withUpdatedPremiumRequired(Set(peerIds.map({ $0.key })))
                }
            }))
        }
    }
    
    public override var canBecomeResponder: Bool {
        return true
    }
    
    public override func becomeFirstResponder() -> Bool? {
        _ = window?.makeFirstResponder(nil)
        return false
    }
    
    
    public override func firstResponder() -> NSResponder? {
        if window?.firstResponder == genericView.textView.inputView {
            return genericView.textView.inputView
        }
        
        if let event = NSApp.currentEvent {
            if event.type == .keyDown {
                switch event.keyCode {
                case KeyboardKey.UpArrow.rawValue:
                    return window?.firstResponder
                case KeyboardKey.DownArrow.rawValue:
                    return window?.firstResponder
                default:
                    break
                }
            }
        }
        
        if selectInteractions.presentation.multipleSelection {
            return genericView.tokenizedView.responder
        } else {
            return genericView.basicSearchView.input
        }
    }
    
    public override func returnKeyAction() -> KeyHandlerResult {
        if let event = NSApp.currentEvent, !FastSettings.checkSendingAbility(for: event) {
            return .rejected
        }
        return invoke()
    }
    
    private func performShare(to peerIds: [PeerId], threadId: Int64?, comment: ChatTextInputState?, sendPaidMessageStars: [PeerId: StarsAmount]) -> Signal<Bool, String> {
        let share = self.share
        if let forward = share as? ForwardMessagesObject, peerIds.count == 1, let peerId = peerIds.first {
            return (forward.performObserved(to: peerId, threadId: threadId, comment: comment, sendPaidMessageStars: sendPaidMessageStars))
            |> mapToSignal { [weak self] result -> Signal<Bool, String> in
                guard let self, !self.pickerClosed else { return .complete() }
                let successful: Bool
                switch result {
                case .draftPrepared: self.deliveryResult = .draftPrepared; successful = true
                case .destinationReady: self.deliveryResult = .destinationReady; successful = true
                case .accepted: self.deliveryResult = .accepted; successful = true
                case .partiallyAccepted: self.deliveryResult = .partiallyAccepted; successful = false
                case .rejected: self.deliveryResult = .rejected; successful = false
                case .sourceUnavailable: self.deliveryResult = .sourceUnavailable; successful = false
                case .targetUnavailable: self.deliveryResult = .targetUnavailable; successful = false
                case .acceptanceUnknown, .completionUnknown: self.deliveryResult = .unknown; successful = false
                case .restricted: return .complete()
                }
                if successful { return .single(true) }
                self.success = false
                self.close()
                alert(for: share.context.window, info: strings().shareIncompleteDelivery, onDeinit: {
                })
                return .single(false)
            }
        }
        if let deliveryShare = share as? ShareDeliveryProviding {
            return deliveryShare.performWithResults(to: peerIds, threadId: threadId, comment: comment, sendPaidMessageStars: sendPaidMessageStars)
            |> map { [weak self] results in
                guard let self, !self.pickerClosed else { return false }
                let result = SharePickerResult(deliveries: results)
                self.deliveryResult = result
                if result == .accepted { return true }
                self.success = false
                self.close()
                alert(for: share.context.window, info: strings().shareIncompleteDelivery, onDeinit: {
                })
                return false
            }
        }
        return Signal { [weak self] subscriber in
            guard let self, !self.pickerClosed else {
                subscriber.putCompletion()
                return EmptyDisposable
            }
            let signal = share.perform(to: peerIds, threadId: threadId, comment: comment, sendPaidMessageStars: sendPaidMessageStars)
            guard !self.pickerClosed else {
                subscriber.putCompletion()
                return EmptyDisposable
            }
            return (signal).start(error: { error in
                subscriber.putError(error)
            }, completed: {
                subscriber.putNext(true)
                subscriber.putCompletion()
            })
        }
    }




    private func showPremiumRequired(_ peerId: PeerId) {
        guard !pickerClosed else { return }
        let context = share.context
        premiumAction.start(request: { [weak self] in
            return context.account.postbox.loadedPeerWithId(peerId)
        }, next: { [weak self] peer in
            guard let self, !self.pickerClosed else { return }
            let consumed = Atomic(value: false)
            showModalText(for: context.window, text: strings().peerForwardPremiumRequired(peer.compactDisplayTitle), button: strings().alertLearnMore, callback: { [weak self] _ in
                do {
                    guard let self, !self.pickerClosed, !consumed.swap(true) else { return }
                    FeatureNavigationHooks.shared.showPremiumBoardingObserved(context, context.window, nil, false, nil)
                }
            })
        }, error: { _ in }, completed: {})
        genericView.activeTableView.cancelSelection()
    }

    private func selectRecipient(_ peerId: PeerId, threadId: Int64?) {
        guard !pickerClosed else { return }
        if selectInteractions.presentation.premiumRequired.contains(peerId) {
            selectInteractions.premiumRequiredAction?(peerId)
            return
        }
        let context = share.context
        if share.multipleSelection, let threadId {
            recipientAction.start(request: {
                context.account.postbox.loadedPeerWithId(peerId)
            }, next: { [weak self] peer in
                guard let self, !self.pickerClosed else { return }
                self.share.threadIds[peerId] = threadId
                self.selectInteractions.toggleSelection(peer)
                self.popForum(peerId: peerId, animated: true)
            }, error: { _ in }, completed: {})
            return
        }
        let comment = contextChatInteraction.presentation.interfaceState.inputState
        recipientAction.start(request: {
            self.performShare(to: [peerId], threadId: threadId, comment: comment, sendPaidMessageStars: [:])
        }, next: { [weak self] performed in
            guard let self, !self.pickerClosed, performed else { return }
            self.success = true
            self.close()
        }, error: { [weak self] error in
            guard let self, !self.pickerClosed else { return }
            alert(for: context.window, info: error, onDeinit: {
            })
        }, completed: {})
    }

    private func invoke() -> KeyHandlerResult {
        guard !pickerClosed else { return .rejected }
        if !genericView.tokenizedView.query.isEmpty {
            let tableView = genericView.activeTableView
            if !tableView.isEmpty {
                activate(tableView.item(at: 0), in: tableView)
            }
            return .invoked
        }
        if !selectInteractions.presentation.peers.isEmpty || share.alwaysEnableDone {

            let ids = selectInteractions.presentation.selected

            let account = share.context.account
            let context = share.context
            let input = self.contextChatInteraction.presentation.interfaceState.inputState
            recipientAction.start(request: { [weak self] in
                guard let self, !self.pickerClosed else { return Signal<Bool, String>.complete() }

                let peerAndData:Signal<[(TelegramChannel, CachedChannelData?)], NoError> = share.context.account.postbox.transaction { transaction in
                    var result:[(TelegramChannel, CachedChannelData?)] = []
                    for id in ids {
                        if let peer = transaction.getPeer(id) as? TelegramChannel {
                            result.append((peer, transaction.getPeerCachedData(peerId: id) as? CachedChannelData))
                        }
                    }
                    return result
                } |> deliverOnMainQueue

                let signal = peerAndData |> mapToSignal { peerAndData in
                    return account.postbox.unsentMessageIdsView() |> take(1) |> map {
                        (peerAndData, Set($0.ids.map { $0.peerId }))
                    }
                } |> deliverOnMainQueue

                return combineLatest(queue: .mainQueue(), signal, context.starsContext.state |> take(1))
                |> take(1)
                |> castError(String.self)
                |> mapToSignal { [weak self] values -> Signal<Bool, String> in
                    guard let self, !self.pickerClosed else { return .complete() }
                    let (peerAndData, unsentIds) = values.0
                    let starsState = values.1
                    let share = self.share
                    let comment = input.inputText
                    let invoke: ([PeerId: StarsAmount]) -> Signal<Bool, String> = { [weak self] sendPaidMessageStars in
                        return Signal { subscriber in
                            guard let self, !self.pickerClosed else {
                                subscriber.putCompletion()
                                return EmptyDisposable
                            }
                            self.genericView.tokenizedView.removeAllFailed(animated: true)
                            return self.performShare(to: Array(ids), threadId: nil, comment: input, sendPaidMessageStars: sendPaidMessageStars).start(next: { result in
                                subscriber.putNext(result)
                            }, error: { error in
                                subscriber.putError(error)
                            }, completed: {
                                subscriber.putCompletion()
                            })
                        }
                    }
                    enum ShareFailedTarget {
                        case token
                        case comment
                        case stars(StarsAmount)
                    }
                    struct ShareFailedReason {
                        let peerId:PeerId
                        let reason: String
                        let target: ShareFailedTarget
                    }

                    var failed:[ShareFailedReason] = []
                    var sendPaidMessageStars: [PeerId: StarsAmount] = [:]

                    if !(share is ShareSelectCallbackObject) {

                        for (peer, cachedData) in peerAndData {
                            inner: switch peer.info {
                            case let .group(info):
                                if info.flags.contains(.slowModeEnabled) && (peer.adminRights == nil && !peer.flags.contains(.isCreator)) {
                                    if let cachedData = cachedData, let validUntil = cachedData.slowModeValidUntilTimestamp {
                                        if validUntil > share.context.timestamp {
                                            failed.append(ShareFailedReason(peerId: peer.id, reason: slowModeTooltipText(validUntil - share.context.timestamp), target: .token))
                                        }
                                    }
                                    if !comment.isEmpty {
                                        failed.append(ShareFailedReason(peerId: peer.id, reason: strings().slowModeForwardCommentError, target: .comment))
                                    }
                                    if unsentIds.contains(peer.id) {
                                        failed.append(ShareFailedReason(peerId: peer.id, reason: strings().slowModeMultipleError, target: .token))
                                    }
                                }
                                if (peer.adminRights == nil && !peer.flags.contains(.isCreator)) {
                                    if let stars = peer.sendPaidMessageStars, peer.id != account.peerId {
                                        failed.append(ShareFailedReason(peerId: peer.id, reason: "", target: .stars(stars)))
                                        sendPaidMessageStars[peer.id] = stars
                                    }
                                }

                            default:
                                break inner
                            }
                        }
                    }

                    let blockingFailures = failed.filter {
                        if case .stars = $0.target { return false }
                        return true
                    }
                    if !blockingFailures.isEmpty {
                        self.genericView.tokenizedView.markAsFailed(blockingFailures.map {
                            $0.peerId.toInt64()
                        }, animated: true)

                        let last = blockingFailures.last!

                        switch last.target {
                        case .comment:
                            self.genericView.textView.shake()
                            tooltip(for: self.genericView.bottomSeparator, text: last.reason)
                        case .token:
                            self.genericView.tokenizedView.addTooltip(for: last.peerId.toInt64(), text: last.reason)
                        case .stars:
                            break
                        }

                        return .single(false)
                    }
                    let payStars = sendPaidMessageStars.values.reduce(Int64(0), { $0 + $1.value })
                    if payStars == 0 { return invoke(sendPaidMessageStars) }
                    let messagesCount = (share as? ShareDeliveryProviding)?.outgoingMessageCount(comment: input) ?? (share.messagesCount + (input.inputText.isEmpty ? 0 : 1))
                    let starsPrice = payStars * Int64(messagesCount)
                    let amount = strings().starListItemCountOther(Int(starsPrice))
                    let messageCountText = strings().chatPayStarsConfirmMessagesOther(messagesCount)
                    let info = strings().sharePayConfirmText(strings().sharePayConfirmUserCountOther(sendPaidMessageStars.count), amount, messageCountText)
                    return (sharePickerConfirmation(window: context.window, header: strings().chatPayStarsConfirmTitle, information: info, ok: strings().chatPayStarsConfirmPayOther(messagesCount)))
                    |> castError(String.self)
                    |> mapToSignal { [weak self] confirmed -> Signal<Bool, String> in
                        guard let self, !self.pickerClosed else { return .single(false) }
                        guard confirmed else { return .single(false) }
                        if let starsState, starsState.balance.value >= starsPrice {
                            return invoke(sendPaidMessageStars)
                        }
                        FeatureNavigationHooks.shared.showStarsPurchaseWithContext(context, context.window, .stars, nil, starsPrice)
                        return .single(false)
                    }
                }
            }, next: { [weak self] performed in
                guard let self, !self.pickerClosed, performed else { return }
                self.emoji.popover?.hide()
                self.success = true
                self.close()
                if !ids.isEmpty { self.showSuccess() }
            }, error: { [weak self] error in
                guard let self, !self.pickerClosed else { return }
                alert(for: context.window, info: error, onDeinit: {
                })
            }, completed: {})

            return .invoked
        }
        if share is ForwardMessagesObject {
            let tableView = genericView.activeTableView
            if tableView.highlightedItem() == nil, !tableView.isEmpty {
                let item = tableView.item(at: 0)
                activate(item, in: tableView)
                return .invoked
            }
        }

        return .rejected
    }

    private func popDestination(animated: Bool) {
        guard !pickerClosed else { return }
        recipientAction.reset()
        premiumAction.reset()
        guard let destination = destinationStack.popLast() else {
            return
        }
        switch destination {
        case .community:
            communityDisposable.set(nil)
            genericView.popCommunity(animated: animated)
        case .forum:
            forumDisposable.set(nil)
            genericView.popForum(animated: animated)
        }
        clearDestinationSearch()
        destinationPeerId.set(destinationStack.last?.peerId)
    }

    private func popForum(peerId: PeerId, animated: Bool) {
        guard let destination = destinationStack.last,
              case let .forum(currentPeerId, _) = destination,
              currentPeerId == peerId else {
            return
        }
        popDestination(animated: animated)
    }
    
    public override func escapeKeyAction() -> KeyHandlerResult {
        if genericView.activeTableView.highlightedItem() != nil {
            genericView.activeTableView.cancelHighlight()
            return .invoked
        }
        if !destinationStack.isEmpty {
            self.popDestination(animated: true)
            return .invoked
        }
        if genericView.tokenizedView.state == .Focus {
            _ = window?.makeFirstResponder(nil)
            return .invoked
        }
        
        return .rejected
    }

    private let emoji: ShareEmojiesController
    private let presentation: TelegramPresentationTheme?
    private var completion:((Bool)->Void)? = nil
    
    private var success: Bool = false
    private var deliveryResult: SharePickerResult?
    public var resultCompletion: ((SharePickerResult) -> Void)?
    

    public init(_ share:ShareObject, presentation: TelegramPresentationTheme? = nil, completion:((Bool)->Void)? = nil) {
        self.share = share
        self.completion = completion
        self.presentation = presentation
        self.share.presentation = presentation
        emoji = ShareUIHooks.shared.makeEmojies(share.context, presentation)
        self.contextChatInteraction = ChatInteraction(chatLocation: .peer(PeerId(0)), context: share.context)
        inputContextHelper = InputContextHelper(chatInteraction: contextChatInteraction)
        super.init(frame: NSMakeRect(0, 0, 360, 400))
        bar = .init(height: 0)
        let isShare = share is ShareLinkObject || share is ShareContactObject || share is ShareMessageObject || share is ShareStoryObject || share is ReplyForwardMessageObject || share is ForwardMessagesObject || share is ShareChatContextResult
    }

    public func showEmoji(for control: Control) {
        showPopover(for: control, with: emoji)
    }
    
    public override func didResizeView(_ size: NSSize, animated: Bool) {
      //  self.genericView.updateLayout(size: size, transition: animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate)
    }
    
    public func inputDidUpdateLayout(animated: Bool) {
        updateSize(frame.width, animated: animated)
    }

    private func set(_ state: Updated_ChatTextInputState) {
        self.selectInteractions.update {
            $0.withUpdatedComment(.init(string: state.inputText.string, range: NSMakeRange(state.selectionRange.lowerBound, state.selectionRange.upperBound - state.selectionRange.lowerBound)))
        }
        self.contextChatInteraction.update({
            $0.withUpdatedEffectiveInputState(state.textInputState())
        })
    }
    
    
    private func updateSize(_ width: CGFloat, animated: Bool) {
        if let contentSize = self.window?.contentView?.frame.size {
            self.modal?.resize(with:NSMakeSize(width, min(contentSize.height - 100, max(400, genericView.tableView.listHeight + max(genericView.additionHeight, 88)))), animated: animated)
        }
    }
    
    public override var modalInteractions: ModalInteractions? {
        if !share.hasCaptionView, share.hasInteraction {
            return ModalInteractions(acceptTitle: share.interactionOk, accept: { [weak self] in
                _ = self?.invoke()
            }, singleButton: true)
        } else {
            return nil
        }
    }
    
    public override func measure(size: NSSize) {
        self.modal?.resize(with:NSMakeSize(genericView.frame.width, min(size.height - 100, max(400, genericView.tableView.listHeight + max(genericView.additionHeight, 88)))), animated: false)
    }
    
    public override var dynamicSize: Bool {
        return true
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }
    
    public func showSuccess() {
        if let window = self.window {
            showModalText(for: window, text: share.successText)
        }
    }
    
    public override func close(animationType: ModalAnimationCloseBehaviour = .common) {
        guard !pickerClosed else { return }
        pickerClosed = true
        recipientAction.close()
        premiumAction.close()
        if self.share.emptyPerformOnClose {
            _ = self.share.perform(to: [], threadId: nil).start()
        }
        
        super.close(animationType: animationType)
        
        self.resultCompletion?(deliveryResult ?? (success ? .dispatched : .cancelled))
        self.completion?(success)
    }
    
    deinit {
        disposable.dispose()
        tokenDisposable.dispose()
        exportLinkDisposable.dispose()
        communityDisposable.dispose()
        forumDisposable.dispose()
        filterDisposable.dispose()
        updatePremiumRequiredDisposable.dispose()
    }
    
    public override var modalTheme: ModalViewController.Theme {
        return .init(presentation: presentation ?? theme)
    }
    public override var containerBackground: NSColor {
        let theme = presentation ?? theme
        return theme.colors.background
    }
}
