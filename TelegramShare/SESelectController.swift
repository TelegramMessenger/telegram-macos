import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Localization
import Postbox
import InAppSettings
import InputView
import ObjcUtils



private func shareFolderPreferences(context: AccountContext) -> Signal<ChatListFolders, NoError> {
    let request = context.engine.peers.requestChatListFilters()
    let interval = Signal<[ChatListFilter], NoError>.complete() |> delay(20, queue: .concurrentDefaultQueue())
    let refresh = (request |> then(interval)) |> restart
    let remote: Signal<[ChatListFilter]?, NoError> = .single(nil) |> then(refresh |> map { Optional($0) })
    return combineLatest(chatListFilterPreferences(engine: context.engine), remote)
    |> map { cached, remote in
        return ChatListFolders(list: remote ?? cached.list, sidebar: cached.sidebar, showTags: cached.showTags)
    }
    |> distinctUntilChanged
}

private final class Container : Control {
    private let glass = LiquidGlassView(frame: .zero, cornerRadius: 16, hasShadow: false, hasBorder: false)
    private let container = View()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(glass)
        addSubview(container)
        container.backgroundColor = .clear
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(_ accounts: [AccountWithInfo], primary: AccountRecordId, switchAccount: @escaping(AccountRecordId) -> Void, frame: NSRect) {
        
        while container.subviews.count > accounts.count {
            container.subviews.last?.removeFromSuperview()
        }
        while container.subviews.count < accounts.count {
            let view = AccountContainer(frame: NSMakeRect(0, 0, 200, 28))
            container.addSubview(view)
        }
        var y: CGFloat = 2
        var width: CGFloat = 0
        for (i, account) in accounts.enumerated() {
            let view = container.subviews[i] as! AccountContainer
            view.setInfo(account, selected: account.account.id == primary, maxWidth: 200, switchAccount: switchAccount)
            view.setFrameOrigin(NSMakePoint(0, y))
            width = max(view.frame.width, width)
            y += view.frame.height
        }
        
        setFrameSize(NSMakeSize(max(150, width), y + 2))
    }
    
    override func layout() {
        super.layout()
        glass.frame = bounds
        glass.updateLayout(size: bounds.size, transition: .immediate)
        container.frame = bounds
    }
}

private final class AccountContainer : Control {
    private let avatar = AvatarControl(font: .avatar(8))
    private let name = TextView()
    private let container = Control()
    private var selected: ImageView?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        avatar.setFrameSize(NSMakeSize(20, 20))
        addSubview(container)
        container.addSubview(avatar)
        container.addSubview(name)
        
        avatar.userInteractionEnabled = false
        
        name.userInteractionEnabled = false
        name.isSelectable = false
        
        container.set(handler: { [weak self] _ in
            self?.updateColors()
        }, for: .Hover)
        
        container.set(handler: { [weak self] _ in
            self?.updateColors()
        }, for: .Highlight)
        
        container.set(handler: { [weak self] _ in
            self?.updateColors()
        }, for: .Normal)
        
        name.isAccessibilityDecorative = true
        container.scaleOnClick = true
        container.layer?.cornerRadius = 5
    }
    
    private func updateColors() {
        container.backgroundColor = container.controlState == .Hover || container.controlState == .Highlight ? theme.colors.grayForeground.withAlphaComponent(0.6) : .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func setInfo(_ info: AccountWithInfo, selected: Bool, maxWidth: CGFloat, switchAccount: @escaping(AccountRecordId) -> Void) {
        self.avatar.setPeer(account: info.account, peer: info.peer)
        let name = TextViewLayout(.initialize(string: info.peer.displayTitle, color: theme.colors.text, font: .normal(.text)), maximumNumberOfLines: 1)
        name.measure(width: maxWidth - 10 - avatar.frame.width - 10 - 10)
        self.name.update(name)
        container.setAccessibilityLabel(info.peer.displayTitle)
        self.setFrameSize(NSMakeSize(max(150, avatar.frame.width + 10 + 10 + name.layoutSize.width + 10 + 15), 28))
        
        
        if selected {
            let current: ImageView
            if let view = self.selected {
                current = view
            } else {
                current = ImageView()
                current.setAccessibilityLabel(L10n.voiceOverCommonSelected)
                self.selected = current
                container.addSubview(current)
            }
            current.image = NSImage(resource: .menuCheckSelected).precomposed(theme.colors.text)
            current.sizeToFit()
        } else if let view = self.selected {
            performSubviewRemoval(view, animated: true)
            self.selected = nil
        }
        
        
        container.setSingle(handler: { _ in
            switchAccount(info.account.id)
        }, for: .Click)
        
        needsLayout = true
    }
    
    override func layout() {
        super.layout()
        container.frame = self.bounds.insetBy(dx: 2, dy: 0)
        avatar.centerY(x: 8)
        name.centerY(x: avatar.frame.maxX + 10)
        
        if let selected {
            selected.centerY(x: container.frame.width - selected.frame.width - 6)
        }
    }
}

class SelectAccountView: Control {
    private let backgroundLayer = SimpleShapeLayer()
    private let container = Container(frame: NSMakeRect(0, 0, 200, 100))
    init(_ accounts: [AccountWithInfo], primary: AccountRecordId, switchAccount: @escaping(AccountRecordId) -> Void, frame: NSRect) {
        super.init(frame: frame)
        backgroundLayer.frame = frame
        self.layer?.addSublayer(backgroundLayer)
        
        self.container.update(accounts, primary: primary, switchAccount: switchAccount, frame: frame)
        
        self.container.setFrameOrigin(NSMakePoint(frame.width - container.frame.width - 10, 50))
        addSubview(self.container)
        
        self.container.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
        self.container.layer?.animateScaleSpringFrom(anchor: NSMakePoint(container.frame.width, 0), from: 0.1, to: 1, duration: 0.2, bounce: false)
        
        let path = CGMutablePath()
        path.addRect(frame)

        let circleDiameter: CGFloat = 30
        let circleRadius = circleDiameter / 2
                
        let circleCenter = CGPoint(x: frame.width - circleRadius - 10, y: 10 + circleRadius)

        path.addArc(center: circleCenter, radius: circleRadius, startAngle: 0, endAngle: CGFloat(2 * Double.pi), clockwise: false)

        backgroundLayer.path = path
        backgroundLayer.fillRule = .evenOdd
        backgroundLayer.fillColor = NSColor.black.withAlphaComponent(0.25).cgColor
        
        backgroundLayer.path = path
        
        self.setSingle(handler: { [weak self] _ in
            self?.change(opacity: 0, animated: true, removeOnCompletion: false, duration: 0.2, timingFunction: .spring, completion: { [weak self] completed in
                self?.removeFromSuperview()
            })
        }, for: .SingleClick)
        
    }
    
    
    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


class ShareModalView : View {
    let searchView:SearchView = SearchView(frame: NSZeroRect)
    let tableView:TableView = TableView()
    let cancelView:ImageButton = ImageButton()
    let backButton:ImageButton = ImageButton()

    private var photoView: AvatarControl?
    private let headerGlass = GlassContainerView(frame: .zero, spacing: 8)
    private let headerControls = View()
    private let navigationGlass = LiquidGlassView(frame: .zero, cornerRadius: 18, hasShadow: false, hasBorder: false)
    private let searchGlass = LiquidGlassView(frame: .zero, cornerRadius: 18, hasShadow: false, hasBorder: false)
    private let composerGlass = GlassContainerView(frame: .zero, spacing: 8)
    private let composerControls = View()
    private let commentGlass = LiquidGlassView(frame: .zero, cornerRadius: 20, hasShadow: false, hasBorder: false)
    private let sendGlass = LiquidGlassView(frame: .zero, cornerRadius: 20, hasShadow: false, hasBorder: false)
    
    fileprivate let sendButton = ImageButton()
    fileprivate let textView:SE_UITextView = SE_UITextView(frame: NSMakeRect(0, 0, 100, 50))
    fileprivate let actionsContainerView: Control = Control()
    fileprivate let textContainerView: View = View()

    
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        
        addSubview(tableView)
        addSubview(headerGlass)
        addSubview(composerGlass)
        addSubview(headerControls)
        addSubview(composerControls)
        headerControls.backgroundColor = .clear
        composerControls.backgroundColor = .clear
        headerGlass.addGhost(navigationGlass)
        headerGlass.addGhost(searchGlass)
        headerControls.addSubview(cancelView)
        headerControls.addSubview(backButton)
        headerControls.addSubview(searchView)
        composerGlass.addGhost(commentGlass)
        composerGlass.addGhost(sendGlass)
        composerControls.addSubview(textContainerView)
        composerControls.addSubview(actionsContainerView)
        for glass in [navigationGlass, searchGlass, commentGlass, sendGlass] {
            glass.isEventLess = true
        }

        sendButton.setAccessibilityLabel(L10n.voiceOverMessageContextSend)
        actionsContainerView.isAccessibilityDecorative = true
        sendButton.autohighlight = false
        sendButton.scaleOnClick = true

        sendButton.set(image: theme.icons.chatSendMessage, for: .Normal)
        _ = sendButton.sizeToFit()
        
        actionsContainerView.addSubview(sendButton)
        actionsContainerView.setFrameSize(sendButton.frame.width + 20, 50)

        textView.interactions.max_height = 180
        textView.interactions.min_height = 28
        
        textContainerView.addSubview(textView)

        backgroundColor = theme.colors.background
        textContainerView.backgroundColor = .clear
        actionsContainerView.backgroundColor = .clear
        textView.backgroundColor = .clear
        searchView.backgroundColor = .clear

        textView.placeholder = strings().previewSenderCommentPlaceholder
        textView.inputTheme = theme.inputTheme
        
        
        cancelView.set(image: theme.icons.modalClose, for: .Normal)
        cancelView.setAccessibilityLabel(L10n.voiceOverCommonClose)
        cancelView.autohighlight = false
        cancelView.scaleOnClick = true
        _ = cancelView.sizeToFit(.zero, NSMakeSize(30, 30), thatFit: true)
        
        backButton.set(image: theme.icons.chatNavigationBack, for: .Normal)
        backButton.setAccessibilityLabel(L10n.voiceOverCommonBack)
        backButton.autohighlight = false
        backButton.scaleOnClick = true
        _ = backButton.sizeToFit(.zero, NSMakeSize(30, 30), thatFit: true)

        updateNavigationButtons()



    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        backgroundColor = theme.colors.background
        searchView.backgroundColor = .clear
        textContainerView.backgroundColor = .clear
        actionsContainerView.backgroundColor = .clear
        textView.backgroundColor = .clear
    }

    var inDestinationMode: Bool {
        return communityChatsView != nil || forumTopicsView != nil
    }

    var activeTableView: TableView {
        return forumTopicsView ?? communityChatsView ?? tableView
    }


    private var forumTopicItems:[ForumTopicItem] = []
    private var forumTopicsView: TableView?
    private var communityChatsView: TableView?

   
    private struct ForumTopicItem : Comparable, Identifiable {
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
            default:
                threadId = nil
            }
            return SE_TopicRowItem(initialSize, stableId: self.item.id, item: self.item, context: arguments.context, action: {
                if let threadId = threadId {
                    arguments.select(threadId)
                }
            }, presentation: arguments.presentation)
        }
    }
    
    private class ForumTopicArguments {
        let context: AccountContext
        let presentation: TelegramPresentationTheme
        let select:(Int64)->Void
        init(context: AccountContext, presentation: TelegramPresentationTheme, select:@escaping(Int64)->Void) {
            self.context = context
            self.select = select
            self.presentation = presentation
        }
    }
    
    
    
    func appearForumTopics(_ items: [EngineChatList.Item], peerId: PeerId, interactions: SelectPeerInteraction, delegate: TableViewDelegate?, context: AccountContext, animated: Bool) {
        
        let arguments = ForumTopicArguments(context: context, presentation: theme, select: { threadId in
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
                return theme.colors.background
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
            push(tableView, hiding: sourceView)
        }

        updateNavigationButtons()

        needsLayout = true
    }

    func appearCommunityChats(_ peers: [Peer], interactions: SelectPeerInteraction, delegate: TableViewDelegate?, context: AccountContext, animated: Bool) {
        let sourceView = self.activeTableView
        let animated = animated && self.communityChatsView == nil

        let tableView = self.communityChatsView ?? TableView()
        if tableView.superview == nil {
            tableView.frame = self.tableView.frame
            addSubview(tableView)
            self.communityChatsView = tableView

            tableView.getBackgroundColor = {
                return theme.colors.background
            }
        }

        tableView.delegate = delegate

        tableView.removeAll()
        tableView.beginTableUpdates()
        var index: Int = 0
        for peer in peers {
            let item = ShortPeerRowItem(tableView.frame.size, peer: peer, account: context.account, context: context, stableId: AnyHashable(peer.id), height: 40, photoSize: NSMakeSize(30, 30), isLookSavedMessage: true, inset: NSEdgeInsets(left: 10, right: 10), interactionType: .selectable(interactions, side: .right), action: { [weak interactions] in
                if peer.isForumOrMonoForum {
                    _ = interactions?.openForum(peer.id, peer.isMonoForum)
                } else {
                    interactions?.action(peer.id, nil)
                }
            })
            _ = tableView.insert(item: item, at: index)
            index += 1
        }
        tableView.endTableUpdates()

        if animated {
            push(tableView, hiding: sourceView)
        }

        updateNavigationButtons()

        needsLayout = true
    }

    private func push(_ view: TableView, hiding sourceView: TableView) {
        let oneOfThrid = frame.width / 3
        view.layer?.animatePosition(from: NSMakePoint(oneOfThrid * 2, view.frame.minY), to: view.frame.origin, duration: 0.35, timingFunction: .spring)
        sourceView.layer?.animatePosition(from: sourceView.frame.origin, to: NSMakePoint(-oneOfThrid, sourceView.frame.minY), duration: 0.35, timingFunction: .spring)
    }

    private func pop(_ view: TableView, revealing sourceView: TableView, animated: Bool) {
        if animated {
            let oneOfThrid = frame.width / 3
            view.layer?.animatePosition(from: tableView.frame.origin, to: NSMakePoint(frame.width, view.frame.minY), duration: 0.35, timingFunction: .spring, removeOnCompletion: false, completion: { [weak view] _ in
                view?.removeFromSuperview()
            })
            sourceView.layer?.animatePosition(from: NSMakePoint(-oneOfThrid, sourceView.frame.minY), to: sourceView.frame.origin, duration: 0.35, timingFunction: .spring)
        } else {
            view.removeFromSuperview()
        }
        sourceView.cancelSelection()
        updateNavigationButtons()
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

    private func updateNavigationButtons() {
        backButton.isHidden = !inDestinationMode
        cancelView.isHidden = inDestinationMode
    }


    
    var textWidth: CGFloat {
        return max(1, frame.width - 88)
    }
    
    func textViewSize() -> (NSSize, CGFloat) {
        let w = textWidth
        let height = self.textView.height(for: w)
        return (NSMakeSize(w, min(max(height, textView.min_height), textView.max_height)), height)
    }
    
    var additionHeight: CGFloat {
        return textViewSize().0.height + 80
    }
    
    func updateWithAccounts(_ accounts: (primary: AccountRecordId?, accounts: [AccountWithInfo]), context: AccountContext) -> Void {
        if accounts.accounts.count > 1, let primary = accounts.primary {
            if photoView == nil {
                photoView = AvatarControl(font: .avatar(12))
                photoView?.setFrameSize(NSMakeSize(30, 30))
                headerControls.addSubview(photoView!)
            }
            if let account = accounts.accounts.first(where: {$0.account.id == primary}) {
                photoView?.setPeer(account: account.account, peer: account.peer)
            }
            photoView?.removeAllHandlers()
            
           
            
            photoView?.set(handler: { [weak self] control in
                guard let `self` = self else {return}
                
                let view = SelectAccountView(accounts.accounts, primary: primary, switchAccount: { recordId in
                    context.sharedContext.switchToAccount(id: recordId, action: nil)
                }, frame: self.bounds)
                
                self.addSubview(view)
                view.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            }, for: .Click)
        } else {
            photoView?.removeFromSuperview()
            photoView = nil
        }
        needsLayout = true
    }
    
    
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        
        let (textSize, textHeight) = textViewSize()
        let composerHeight = textSize.height + 12
        let composerFrame = NSMakeRect(10, size.height - composerHeight - 10, max(0, size.width - 20), composerHeight)
        transition.updateFrame(view: composerGlass, frame: composerFrame)
        composerGlass.updateLayout(size: composerFrame.size, transition: transition)
        transition.updateFrame(view: composerControls, frame: composerFrame)

        let commentFrame = NSMakeRect(0, 0, max(0, composerFrame.width - 48), composerHeight)
        let sendFrame = NSMakeRect(max(0, composerFrame.width - 40), composerHeight - 40, 40, 40)
        composerGlass.setGhostFrame(commentGlass, frame: commentFrame, transition: transition)
        composerGlass.setGhostFrame(sendGlass, frame: sendFrame, transition: transition)
        transition.updateFrame(view: textContainerView, frame: commentFrame)
        transition.updateFrame(view: textView, frame: NSMakeRect(10, 6, textSize.width, textSize.height))
        textView.updateLayout(size: textSize, textHeight: textHeight, transition: transition)
        transition.updateFrame(view: actionsContainerView, frame: sendFrame)
        transition.updateFrame(view: sendButton, frame: NSMakeRect(floor((40 - sendButton.frame.width) / 2), floor((40 - sendButton.frame.height) / 2), sendButton.frame.width, sendButton.frame.height))

        let headerSize = NSMakeSize(size.width, 56)
        transition.updateFrame(view: headerGlass, frame: headerSize.bounds)
        headerGlass.updateLayout(size: headerSize, transition: transition)
        transition.updateFrame(view: headerControls, frame: headerSize.bounds)
        let navigationFrame = NSMakeRect(10, 10, 36, 36)
        let searchFrame = NSMakeRect(54, 10, max(0, size.width - 64 - (photoView == nil ? 0 : 44)), 36)
        headerGlass.setGhostFrame(navigationGlass, frame: navigationFrame, transition: transition)
        headerGlass.setGhostFrame(searchGlass, frame: searchFrame, transition: transition)
        transition.updateFrame(view: cancelView, frame: navigationFrame)
        transition.updateFrame(view: backButton, frame: navigationFrame)
        transition.updateFrame(view: searchView, frame: searchFrame)
        if let photoView {
            let accountFrame = NSMakeRect(size.width - 46, 10, 36, 36)
            transition.updateFrame(view: photoView, frame: accountFrame.focus(photoView.frame.size).offsetBy(dx: accountFrame.minX, dy: accountFrame.minY))
        }

        transition.updateFrame(view: tableView, frame: NSMakeRect(0, 56, size.width, max(0, composerFrame.minY - 62)))

        if let communityChatsView {
            transition.updateFrame(view: communityChatsView, frame: tableView.frame)
        }
        if let forumTopicsView {
            transition.updateFrame(view: forumTopicsView, frame: tableView.frame)
        }
    }
    
    
    override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}


class ShareObject {
    let context: AccountContext
    let shareContext:NSExtensionContext
    private let requestFinished: () -> Void
    
    var threadIds: [PeerId : Int32] = [:]

    
    init(_ context: AccountContext, _ shareContext:NSExtensionContext, requestFinished: @escaping () -> Void) {
        self.context = context
        self.shareContext = shareContext
        self.requestFinished = requestFinished
    }
    
    private let progressView = SEModalProgressView()
    
    func perform(to entries:[PeerId], view: NSView, comment: String) {
        
        var signals:[Signal<Float, NoError>] = []
                
        var k:Int = 0
        let total = shareContext.inputItems.reduce(0) { (current, item) -> Int in
            if let item = item as? NSExtensionItem {
                if let _ = item.attributedContentText?.string {
                    return current + 1
                } else if let attachments = item.attachments {
                    return current + attachments.count
                }
            }
            return current
        }
        
        func requestIfNeeded() {
            Queue.mainQueue().async {
                if k == total {
                    self.progressView.frame = view.bounds
                    view.addSubview(self.progressView)
                    
                    self.progressView.layer?.animateAlpha(from: 0, to: 1, duration: 0.35)
                    
                    let signal = combineLatest(signals) |> deliverOnMainQueue
                    
                    let disposable = signal.start(next: { states in
                        
                        let progress = states.reduce(0, { (current, value) -> Float in
                            return current + value
                        })
                        
                        self.progressView.set(progress: CGFloat(min(progress / Float(total), 1)))
                     }, completed: {
                         self.progressView.markComplete()
                         delay(2.0, closure: {
                             self.requestFinished()
                             self.shareContext.completeRequest(returningItems: nil, completionHandler: nil)
                         })
                     })
                    
                    self.progressView.cancelImpl = {
                        self.cancel()
                        disposable.dispose()
                    }
 
                }
            }
        }
                
        for peerId in entries {
            let threadId = threadIds[peerId]

            if !comment.isEmpty {
                signals.append(self.sendText(comment, to: peerId, threadId: threadId))
            }
            
            
            for j in 0 ..< shareContext.inputItems.count {
                if let item = shareContext.inputItems[j] as? NSExtensionItem {
                    if let text = item.attributedContentText?.string {
                        signals.append(sendText(text, to:peerId, threadId: threadId))
                        k += 1
                        requestIfNeeded()
                    } else if let attachments = item.attachments {
                        
                        for i in 0 ..< attachments.count {
                            attachments[i].loadItem(forTypeIdentifier: kUTTypeURL as String, options: nil, completionHandler: { (coding, error) in
                                if let url = coding as? URL {
                                    if !url.isFileURL {
                                        signals.append(self.sendText(url.absoluteString, to:peerId, threadId: threadId))
                                    } else {
                                        signals.append(self.sendMedia(url, to:peerId, threadId: threadId))
                                    }
                                    k += 1
                                } else if let data = coding as? Data, let string = String(data: data, encoding: .utf8), let url = URL(string: string) {
                                    if !url.isFileURL {
                                        signals.append(self.sendText(url.absoluteString, to:peerId, threadId: threadId))
                                    } else {
                                        signals.append(self.sendMedia(url, to:peerId, threadId: threadId))
                                    }
                                    k += 1
                                }
                                requestIfNeeded()
                            })
                            if k != total {
                                attachments[i].loadItem(forTypeIdentifier: kUTTypeImage as String, options: nil, completionHandler: { (coding, error) in
                                    if let data = (coding as? NSImage)?.tiffRepresentation {
                                        signals.append(self.sendMedia(nil, data, to:peerId, threadId: threadId))
                                        k += 1
                                        requestIfNeeded()
                                    }
                                })
                            }
                        }
                    }
                }
            }
        }
        
    }
    
    
    private let queue:Queue = Queue(name: "proccessShareFilesQueue")
    
    private func prepareMedia(_ path: URL?, _ pasteData: Data? = nil) -> Signal<StandaloneMedia, NoError> {
        return Signal { subscriber in
            
            let data = pasteData ?? (path != nil ? try? Data(contentsOf: path!) : nil)
            
            if let data = data {
                var forceImage: Bool = false
                if let _ = NSImage(data: data) {
                    if let path = path {
                        let mimeType = MIMEType(path.path)
                        if mimeType.hasPrefix("image/") && !mimeType.hasSuffix("gif") {
                            forceImage = true
                        }
                    } else {
                        forceImage = true
                    }
                }
                
                if forceImage {
                    let options = NSMutableDictionary()
                    options.setValue(true as NSNumber, forKey: kCGImageSourceCreateThumbnailWithTransform as String)
                    options.setValue(1280 as NSNumber, forKey: kCGImageSourceThumbnailMaxPixelSize as String)
                    options.setValue(true as NSNumber, forKey: kCGImageSourceCreateThumbnailFromImageAlways as String)
                    
                    if let imageSource = CGImageSourceCreateWithData(data as CFData, nil) {
                        let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options)
                        if let image = image, let data = NSImage(cgImage: image, size: image.backingSize).tiffRepresentation(using: .jpeg, factor: 0.83) {
                            let imageRep = NSBitmapImageRep(data: data)
                            if let data = imageRep?.representation(using: .jpeg, properties: [:]) {
                                subscriber.putNext(StandaloneMedia.image(data))
                            }
                        }
                    }

                } else {
                    var mimeType: String = "application/octet-stream"
                    let fileName: String
                    if let path = path {
                        mimeType = MIMEType(path.path)
                        fileName = path.path.nsstring.lastPathComponent
                    } else {
                        fileName = "Unnamed.file"
                    }
                    
                    subscriber.putNext(StandaloneMedia.file(data: data, mimeType: mimeType, attributes: [.FileName(fileName: fileName)]))
                }
                
            }
            
            subscriber.putCompletion()
            return EmptyDisposable
        } |> runOn(queue)
    }
    
    
    
    private func sendMedia(_ path:URL?, _ data: Data? = nil, to peerId:PeerId, threadId: Int32?) -> Signal<Float, NoError> {
        return Signal<Float, NoError>.single(0) |> then(prepareMedia(path, data) |> mapToSignal { media -> Signal<Float, NoError> in
            return standaloneSendMessage(account: self.context.account, peerId: peerId, text: "", attributes: [], media: media, replyToMessageId: nil, threadId: threadId) |> `catch` {_ in return .complete()}
        })
    }
    
    private func sendText(_ text:String, to peerId:PeerId, threadId: Int32?) -> Signal<Float, NoError> {
        return Signal<Float, NoError>.single(0) |> then(standaloneSendMessage(account: context.account, peerId: peerId, text: text, attributes: [], media: nil, replyToMessageId: nil, threadId: threadId) |> `catch` {_ in return .complete()} |> map {_ in return 1})
    }
    
    func cancel() {
        requestFinished()
        let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
        shareContext.cancelRequest(withError: cancelError)
    }
}



enum SelectablePeersEntryStableId : Hashable {
    case plain(Peer)
    case emptySearch
    case folders
    
    func hash(into hasher: inout Hasher) {
        switch self {
        case .plain(let peer):
            hasher.combine("plain")
            hasher.combine(peer.id.toInt64())
        case .emptySearch:
            hasher.combine("emptySearch")
        case .folders:
            hasher.combine("folder")
        }
    }
    
    static func ==(lhs:SelectablePeersEntryStableId, rhs:SelectablePeersEntryStableId) -> Bool {
        switch lhs {
        case let .plain(lhsPeer):
            if case let .plain(rhsPeer) = rhs {
                return lhsPeer.isEqual(rhsPeer)
            } else {
                return false
            }
        case .emptySearch:
            if case .emptySearch = rhs {
                return true
            } else {
                return false
            }
        case .folders:
            if case .folders = rhs {
                return true
            } else {
                return false
            }
        }
    }
}

enum SelectablePeersEntry : Comparable, Identifiable {
    case plain(Peer, ChatListIndex)
    case emptySearch
    case folders([ChatListFilter], ChatListFilter)
    var stableId: SelectablePeersEntryStableId {
        switch self {
        case let .plain(peer,_):
            return .plain(peer)
        case .emptySearch:
            return .emptySearch
        case .folders:
            return .folders
        }
    }
    
    var index:ChatListIndex {
        switch self {
        case let .plain(_,id):
            return id
        case .emptySearch:
            return ChatListIndex(pinningIndex: nil, messageIndex: MessageIndex.absoluteLowerBound())
        case .folders:
            return ChatListIndex(pinningIndex: 0, messageIndex: MessageIndex.absoluteUpperBound())
        }
    }
}

func <(lhs:SelectablePeersEntry, rhs:SelectablePeersEntry) -> Bool {
    return lhs.index < rhs.index
}

func ==(lhs:SelectablePeersEntry, rhs:SelectablePeersEntry) -> Bool {
    switch lhs {
    case let .plain(lhsPeer, lhsIndex):
        if case let .plain(rhsPeer, rhsIndex) = rhs {
            return lhsPeer.isEqual(rhsPeer) && lhsIndex == rhsIndex
        } else {
            return false
        }
    case .emptySearch:
        if case .emptySearch = rhs {
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
    }
}



fileprivate func prepareEntries(from:[SelectablePeersEntry]?, to:[SelectablePeersEntry], context: AccountContext, initialSize:NSSize, animated:Bool, selectInteraction:SelectPeerInteraction) -> Signal<TableEntriesTransition<[SelectablePeersEntry]>, NoError> {
    
    return Signal {subscriber in
        let (deleted,inserted,updated) = proccessEntries(from, right: to, { entry -> TableRowItem in
            switch entry {
            case let .plain(peer, _):
                return ShortPeerRowItem(initialSize, peer: peer, account: context.account, context: context, height:40, photoSize:NSMakeSize(30,30), isLookSavedMessage: true, inset:NSEdgeInsets(left: 10, right:10), interactionType:.selectable(selectInteraction, side: .right), action: {
                    if peer.isCommunity {
                        selectInteraction.toggleSelection(peer)
                    } else if peer.isForumOrMonoForum {
                        _ = selectInteraction.openForum(peer.id, peer.isMonoForum)
                    } else {
                        selectInteraction.action(peer.id, nil)
                    }
                })
            case .emptySearch:
                return SearchEmptyRowItem(initialSize, stableId: SelectablePeersEntryStableId.emptySearch)
            case let .folders(filters, current):
                return SEFoldersRowItem(initialSize, context: context, tabs: filters, selected: current, action: selectInteraction.updateFolder)
            }
        })
        
        let transition = TableEntriesTransition<[SelectablePeersEntry]>(deleted: deleted, inserted: inserted, updated:updated, entries:to, animated:animated, state: .none(nil))
        
        subscriber.putNext(transition)
        subscriber.putCompletion()
        return EmptyDisposable
        
    }
    
}

fileprivate struct SearchState : Equatable {
    let state:SearchFieldState
    let request:String
    init(state:SearchFieldState, request:String?) {
        self.state = state
        self.request = request ?? ""
    }
}

fileprivate func ==(lhs:SearchState, rhs:SearchState) -> Bool {
    return lhs.state == rhs.state && lhs.request == rhs.request
}

class SESelectController: GenericViewController<ShareModalView>, Notifable, TableViewDelegate {

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

    private let share:ShareObject
    private let selectInteractions:SelectPeerInteraction = SelectPeerInteraction()
    private let search:ValuePromise<SearchState> = ValuePromise(ignoreRepeated: true)
    private let inSearchSelected:Atomic<[PeerId]> = Atomic(value:[])
    private let disposable:MetaDisposable = MetaDisposable()
    private let accountsDisposable = MetaDisposable()
    private let filterDisposable = MetaDisposable()
    private let forumDisposable = MetaDisposable()
    private let communityDisposable = MetaDisposable()

    private let destinationPeerId:ValuePromise<PeerId?> = ValuePromise(nil, ignoreRepeated: true)
    private var destinationStack: [Destination] = []
    private var communityChildPeerIds: [PeerId: Set<PeerId>] = [:]


    func notify(with value: Any, oldValue: Any, animated: Bool) {
        if let value = value as? SelectPeerPresentation, let oldValue = oldValue as? SelectPeerPresentation {
            if genericView.searchView.state == .Focus {
                let new = value.selected.subtracting(oldValue.selected)
                _ = inSearchSelected.modify { (peers) -> [PeerId] in
                    return new + peers
                }
            } else {
                
            }
        }
    }
    
    func inputDidUpdateLayout(animated: Bool) {
        genericView.updateLayout(size: frame.size, transition: animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate)
    }

    private func set(_ state: Updated_ChatTextInputState) {
        self.selectInteractions.update {
            $0.withUpdatedComment(.init(string: state.inputText.string, range: NSMakeRange(state.selectionRange.lowerBound, state.selectionRange.upperBound - state.selectionRange.lowerBound)))
        }
    }
    
    func selectionDidChange(row: Int, item: TableRowItem, byClick: Bool, isNew: Bool) {
        
    }
    
    func selectionWillChange(row: Int, item: TableRowItem, byClick: Bool) -> Bool {
        return !selectInteractions.presentation.multipleSelection
    }
    
    func isSelectable(row: Int, item: TableRowItem) -> Bool {
        return !selectInteractions.presentation.multipleSelection
    }
    
    func findGroupStableId(for stableId: AnyHashable) -> AnyHashable? {
        return nil
    }
    
    
    func isEqual(to other: Notifable) -> Bool {
        return false
    }
    
    private func clearDestinationSearch() {
        genericView.searchView.setString("")
    }

    private func pushDestination(_ destination: Destination) {
        guard destinationStack.last != destination else {
            return
        }
        destinationStack.append(destination)
        destinationPeerId.set(destination.peerId)
    }

    private func popDestination(animated: Bool) {
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
        genericView.searchView.cancel(animated)
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

    private func openForum(_ peerId: PeerId, isMonoforum: Bool, animated: Bool) {
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
        
        
        forumDisposable.set(signal.start(next: { [weak self] items in
            self?.genericView.appearForumTopics(items, peerId: peerId, interactions: selectInteractions, delegate: self, context: context, animated: animated)
        }))
    }

    private func openCommunity(_ peerId: PeerId, animated: Bool) {
        let destination: Destination = .community(peerId)
        guard destinationStack.last != destination else {
            return
        }
        pushDestination(destination)
        clearDestinationSearch()

        let context = share.context
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

        let loaded = showModalProgress(signal: childPeers, for: context.window)

        let signal: Signal<(Set<PeerId>, [Peer]), NoError> = combineLatest(loaded, self.search.get()) |> map { peers, query -> (Set<PeerId>, [Peer]) in
            let items = peers.filter { peer in
                return !peer.isCommunity && peer.canSendMessage(false)
            }
            let childPeerIds = Set(items.map { $0.id })
            if query.request.isEmpty {
                return (childPeerIds, items)
            } else {
                return (childPeerIds, items.filter { $0.displayTitle.lowercased().contains(query.request.lowercased()) })
            }
        } |> deliverOnMainQueue

        communityDisposable.set(signal.start(next: { [weak self] childPeerIds, peers in
            guard let self else {
                return
            }
            if self.communityChildPeerIds[peerId] != childPeerIds {
                self.communityChildPeerIds[peerId] = childPeerIds
                selectInteractions.refreshSelection(animated: true)
            }
            self.genericView.appearCommunityChats(peers, interactions: selectInteractions, delegate: self, context: context, animated: animated)
        }))
    }


    override func viewDidLoad() {
        super.viewDidLoad()
        let context = self.share.context
        
        accountsDisposable.set((self.share.context.sharedContext.activeAccountsWithInfo |> deliverOnMainQueue).start(next: { [weak self] accounts in
            self?.genericView.updateWithAccounts(accounts, context: context)
        }))
        
       
        
        search.set(SearchState(state: .None, request: nil))
        
        let previous:Atomic<[SelectablePeersEntry]?> = Atomic(value: nil)
        let initialSize = self.atomicSize.modify({$0})
        let account = share.context.account
        let table = genericView.tableView
        let selectInteraction = self.selectInteractions
        selectInteraction.add(observer: self)
        
        
        selectInteraction.isPeerSelected = { [weak self] peerId, peer, presentation in
            guard let self, peer.isCommunity else {
                return presentation.selected.contains(peerId)
            }
            guard let childPeerIds = self.communityChildPeerIds[peerId] else {
                return false
            }
            return !childPeerIds.isDisjoint(with: presentation.selected)
        }

        selectInteraction.action = { [weak self] peerId, threadId in
            guard let self else {
                return
            }
            if let threadId = threadId {
                let peer = context.account.postbox.loadedPeerWithId(peerId) |> deliverOnMainQueue
                _ = peer.start(next: { [weak self] peer in
                    self?.selectInteractions.toggleSelection(peer)
                    self?.popForum(peerId: peerId, animated: true)
                })
                self.share.threadIds[peerId] = Int32(clamping: threadId)
                return
            }

        }

        selectInteraction.openForum = { [weak self] peerId, isMonoforum in
            self?.openForum(peerId, isMonoforum: isMonoforum, animated: true)
            return true
        }

        selectInteraction.openCommunity = { [weak self] peerId in
            self?.openCommunity(peerId, animated: true)
            return true
        }

        struct FilterData : Equatable {
            var filter: ChatListFilter
            var tabs: [ChatListFilter]
        }
        
        let filter = ValuePromise<FilterData>(ignoreRepeated: true)
        let filterValue = Atomic<FilterData>(value: FilterData(filter: .allChats, tabs: []))
        
        weak var weakController = self
        func updateFilter(_ f:(FilterData)->FilterData) {
            let previous = filterValue.with { $0 }
            let data = filterValue.modify(f)
            if previous.filter != data.filter {
                weakController?.genericView.tableView.scroll(to: .up(true))
            }
            filter.set(data)
        }
        
        var first = true
        
        let filterView = shareFolderPreferences(context: context) |> deliverOnMainQueue
        filterDisposable.set(filterView.start(next: { [weak self] filters in
            guard self != nil else { return }
            updateFilter( { current in
                var current = current
                current.tabs = filters.list
                if !first, let updated = filters.list.first(where: { $0.id == current.filter.id }) {
                    current.filter = updated
                } else {
                    current.filter = .allChats
                }
                return current
            })
            first = false
        }))
        
        selectInteraction.updateFolder = { filter in
            updateFilter { current in
                var current = current
                current.filter = filter
                return current
            }
        }
        
        
        genericView.tableView.set(stickClass: SEFoldersRowItem.self, handler: { _ in
            
        })
        
        
        self.genericView.textView.interactions.inputDidUpdate = { [weak self] state in
            guard let `self` = self else {
                return
            }
            self.set(state)
            self.inputDidUpdateLayout(animated: true)
        }
        
        self.genericView.textView.interactions.processEnter = { [weak self] event in
            guard let self else { return false }
            if !selectInteraction.presentation.selected.isEmpty {
                self.share.perform(to: Array(selectInteraction.presentation.selected), view: self.view, comment: selectInteraction.presentation.comment.string)
                return true
            } else {
                return false
            }
        }
        self.genericView.textView.interactions.processPaste = { pasteboard in
            return false
        }
        self.genericView.textView.interactions.processAttriburedCopy = { attributedString in
            return false
        }
        
        
        let inSearchSelected = self.inSearchSelected
        
        let chatList: Signal<(EngineChatList, FilterData), NoError> = filter.get() |> mapToSignal { data in
            let signal = chatListViewForLocation(chatListLocation: .chatList(groupId: .root), location: .Initial(100, nil), filter: data.filter, account: context.account) |> take(1)
            return  signal |> map { view in
                return (view.list, data)
            }
        }
        
        
        
        let list:Signal<TableEntriesTransition<[SelectablePeersEntry]>, NoError> = combineLatest(search.get() |> distinctUntilChanged, chatList, account.postbox.loadedPeerWithId(account.peerId), destinationPeerId.get()) |> mapToSignal { search, chatList, mainPeer, destinationPeerId -> Signal<TableEntriesTransition<[SelectablePeersEntry]>, NoError> in

            if search.state == .None && destinationPeerId == nil {
                var entries:[SelectablePeersEntry] = []
                
                let fromSearch = inSearchSelected.modify({$0})
                let fromSetIds:Set<PeerId> = Set(fromSearch)
                var fromPeers:[PeerId:Peer] = [:]
                var contains:[PeerId:Peer] = [:]
                
                if chatList.1.tabs.count > 1 {
                    entries.append(.folders(chatList.1.tabs, chatList.1.filter))
                }
                
                if chatList.1.filter == .allChats {
                    let index = MessageIndex(id: MessageId(peerId: PeerId(0), namespace: 0, id: Int32.max), timestamp: Int32.max)
                    entries.append(.plain(mainPeer, ChatListIndex.init(pinningIndex: 0, messageIndex: index)))
                    contains[mainPeer.id] = mainPeer
                }
                
                for entry in chatList.0.items {
                    if let peer = entry.renderedPeer.chatMainPeer?._asPeer() {
                        if !fromSetIds.contains(peer.id), contains[peer.id] == nil {
                            if peer.canSendMessage(false) {
                                entries.append(.plain(peer, entry.chatListIndex))
                                contains[peer.id] = peer
                            }
                        } else {
                            fromPeers[peer.id] = peer
                        }
                    }
                }
                
                var i:Int32 = Int32.max
                for peerId in fromSearch {
                    if let peer = fromPeers[peerId] , contains[peer.id] == nil {
                        let index = MessageIndex(id: MessageId(peerId: peer.id, namespace: 1, id: i), timestamp: i)
                        entries.append(.plain(peer, ChatListIndex(pinningIndex: nil, messageIndex: index)))
                        contains[peer.id] = peer
                    }
                    i -= 1
                }
                entries.sort(by: <)
                
                return prepareEntries(from: previous.swap(entries), to: entries, context: context, initialSize: initialSize, animated: true, selectInteraction:selectInteraction)
            } else if destinationPeerId == nil {
                
                let signal: Signal<[Peer], NoError>
                
                if search.request.isEmpty {
                    signal = context.engine.peers.recentPeers() |> map { recent -> [Peer] in
                        switch recent {
                        case .disabled:
                            return []
                        case let .peers(peers):
                            return peers
                        }
                    }
                    |> deliverOn(prepareQueue)
                } else {
                    let foundLocalPeers = account.postbox.searchPeers(query: search.request.lowercased()) |> map {$0.compactMap { $0.chatMainPeer} }

                    let foundRemotePeers:Signal<[Peer], NoError> = .single([]) |> then ( context.engine.contacts.searchRemotePeers(query: search.request.lowercased()) |> map { $0.map { $0.peer._asPeer() } + $1.map { $0.peer._asPeer() } } )

                    signal = combineLatest(foundLocalPeers, foundRemotePeers) |> map {$0 + $1}
                    
                }
                
                let assignSavedMessages:Bool
                if search.request.isEmpty {
                    assignSavedMessages = true
                } else if L10n.peerSavedMessages.lowercased().hasPrefix(search.request.lowercased()) {
                    assignSavedMessages = true
                } else {
                    assignSavedMessages = false
                }

                
                return signal |> mapToSignal { peers in
                    var entries:[SelectablePeersEntry] = []
                    var i:Int32 = Int32.max
                    
                    var contains: Set<PeerId> = Set()
                    if assignSavedMessages {
                        entries.append(.plain(mainPeer, ChatListIndex(pinningIndex: 0, messageIndex: MessageIndex.absoluteUpperBound())))
                        contains.insert(mainPeer.id)
                    }
                   
                    
                    for peer in peers {
                        if peer.canSendMessage(false), !contains.contains(peer.id) {
                            let index = MessageIndex(id: MessageId(peerId: peer.id, namespace: 1, id: i), timestamp: i)
                            entries.append(.plain(peer, ChatListIndex(pinningIndex: nil, messageIndex: index)))
                            contains.insert(peer.id)
                            i -= 1
                        }
                        
                    }
                    entries.sort(by: <)
                    return prepareEntries(from: previous.swap(entries), to: entries, context: context, initialSize: initialSize, animated: true, selectInteraction:selectInteraction)
                }
                
            } else {
                return .complete()
            }
        }
        
        disposable.set((list |> deliverOnMainQueue).start(next: { [weak self] (transition) in
            table.resetScrollNotifies()
            table.merge(with:transition)
            self?.readyOnce()
        }))
        
        self.genericView.searchView.searchInteractions = SearchInteractions({ [weak self] state, _ in
            self?.search.set(SearchState(state: state.state, request: state.request))
        }, { [weak self] state in
            self?.search.set(SearchState(state: state.state, request: state.request))
        })
        
        self.genericView.sendButton.set(handler: { [weak self] _ in
            guard let self else { return }
            self.share.perform(to: Array(selectInteraction.presentation.selected), view: self.view, comment: selectInteraction.presentation.comment.string)
        }, for: .Click)
        
        self.genericView.cancelView.set(handler: { [weak self] _ in
            self?.share.cancel()
        }, for: .Click)
        
        self.genericView.backButton.set(handler: { [weak self] _ in
            self?.popDestination(animated: true)
        }, for: .Click)
        
    }
    
    override var canBecomeResponder: Bool {
        return true
    }
    
    override func becomeFirstResponder() -> Bool? {
        return false
    }
    
    override func firstResponder() -> NSResponder? {
        return genericView.searchView.input
    }
    
    override func escapeKeyAction() -> KeyHandlerResult {
        if !destinationStack.isEmpty {
            popDestination(animated: true)
            return .invoked
        }
        if genericView.searchView.state == .Focus, !genericView.searchView.query.isEmpty {
            return genericView.searchView.changeResponder() ? .invoked : .rejected
        }
        share.cancel()
        return .invoked
    }
    
    
    init(_ share:ShareObject) {
        self.share = share
        super.init(frame: NSMakeRect(0, 0, 300, 400))
    }
    
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        disposable.set(nil)
    }
    
    deinit {
        disposable.dispose()
        accountsDisposable.dispose()
        filterDisposable.dispose()
        forumDisposable.dispose()
        communityDisposable.dispose()
    }
    
}
