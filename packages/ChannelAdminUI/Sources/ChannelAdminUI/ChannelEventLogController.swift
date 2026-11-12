import Cocoa
import TGUIKit
import TelegramCore
import InAppSettings
import Postbox
import SwiftSignalKit
import TelegramContext
import TelegramUtils
import TelegramTheme
import Localization
import GeneralRows
import AlertsUI
import MessageUtils
import ChatHistoryModel
import ChatUI
import AvatarUI



extension ChannelAdminEventLogEntry : @retroactive Identifiable {
}

private final class Arguments {
    let context: any AccountContextProtocol
    let toggleReveal:(MessageId)->Void
    init(context: any AccountContextProtocol, toggleReveal: @escaping (MessageId) -> Void) {
        self.context = context
        self.toggleReveal = toggleReveal
    }
}

enum ChannelEventLogState {
    case loading
    case empty(String)
    case history
}

private final class EventLogTitleBarView: TitledBarView {
    let searchView = SearchView(frame: .zero)
    private let glassContainer = GlassContainerView(frame: .zero, spacing: 10)
    private let titleGlass = LiquidGlassView(frame: .zero, cornerRadius: 20, hasShadow: false, hasBorder: true)
    private let searchGlass = LiquidGlassView(frame: .zero, cornerRadius: 20, hasShadow: false, hasBorder: true)
    private let titleContent = View(frame: .zero)
    private let titleText = TextView()
    private let statusText = TextView()
    private let searchContent = View(frame: .zero)
    private let avatar = AvatarStoryControl(font: .avatar(12), size: NSMakeSize(32, 32))
    private var searching = false
    private var searchTransitionId: UInt = 0

    override init(controller: ViewController, _ text: NSAttributedString? = nil, _ status: NSAttributedString? = nil, textInset: CGFloat? = nil) {
        super.init(controller: controller, text, status, textInset: 0)
        addSubview(glassContainer)
        glassContainer.addGhost(titleGlass)
        glassContainer.addGhost(searchGlass)
        addSubview(titleContent)
        containerView.isHidden = true
        titleContent.addSubview(titleText)
        titleContent.addSubview(statusText)
        titleText.isSelectable = false
        statusText.isSelectable = false
        titleText.isEventLess = true
        statusText.isEventLess = true
        titleContent.addSubview(avatar)
        titleContent.layer?.masksToBounds = true
        titleContent.layer?.cornerRadius = 20
        avatar.userInteractionEnabled = false
        addSubview(searchContent)
        searchContent.addSubview(searchView)
        searchContent.layer?.masksToBounds = true
        searchContent.layer?.cornerRadius = 20
        searchContent.isHidden = true
        searchGlass.isHidden = true
        searchContent.layer?.opacity = 0
        ContainedViewLayoutTransition.immediate.updateAlpha(view: searchGlass, alpha: 0)
        searchView.backgroundColor = .clear
    }

    func setPeer(account: Account, peer: Peer) {
        avatar.setPeer(account: account, peer: peer, disableForum: true)
    }

    func setSearching(_ value: Bool) {
        guard searching != value else { return }
        layoutSubtreeIfNeeded()
        searching = value
        searchTransitionId &+= 1
        let transitionId = searchTransitionId
        searchContent.isHidden = false
        searchGlass.isHidden = false
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let transition: ContainedViewLayoutTransition = .animated(duration: reduceMotion ? 0.1 : ChatInputSendButton.fieldMotionDuration, curve: .easeOut)
        updateLayout(size: bounds.size, transition: reduceMotion ? .immediate : transition)
        transition.updateAlpha(view: searchContent, alpha: value ? 1 : 0)
        transition.updateAlpha(view: searchGlass, alpha: value ? 1 : 0, completion: { [weak self] _ in
            guard let self, self.searchTransitionId == transitionId else { return }
            self.searchContent.isHidden = !value
            self.searchGlass.isHidden = !value
        })
    }

    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        transition.updateFrame(view: glassContainer, frame: NSRect(origin: .zero, size: size))
        glassContainer.updateLayout(size: size, transition: transition)
        let left = (controller?.leftBarView?.frame.maxX ?? 52) + 10
        let right = (controller?.rightBarView?.frame.minX ?? size.width - 52) - 10
        let availableWidth = max(0, right - left)
        let preferredTitleWidth = max(text?.size().width ?? 0, status?.size().width ?? 0) + 62
        let compactTitleWidth = min(min(260, max(220, preferredTitleWidth)), max(40, availableWidth - 170))
        let titleWidth = compactTitleWidth
        let y = (size.height - 40) / 2
        let titleRect = NSMakeRect(left, y, titleWidth, 40)
        let expandedSearchRect = NSMakeRect(left + compactTitleWidth + 10, y, max(0, availableWidth - compactTitleWidth - 10), 40)
        let searchRect = searching ? expandedSearchRect : NSMakeRect(right - 40, y, 40, 40)
        glassContainer.setGhostFrame(titleGlass, frame: titleRect, transition: transition)
        glassContainer.setGhostFrame(searchGlass, frame: searchRect, transition: transition)
        transition.updateFrame(view: titleContent, frame: titleRect)
        transition.updateFrame(view: searchContent, frame: searchRect)
        avatar.frame = NSMakeRect(4, 4, 32, 32)
        let titleLayout = TextViewLayout(text ?? NSAttributedString(), maximumNumberOfLines: 1)
        let statusLayout = TextViewLayout(status ?? NSAttributedString(), maximumNumberOfLines: 1)
        titleLayout.measure(width: max(1, titleWidth - 58))
        statusLayout.measure(width: max(1, titleWidth - 58))
        titleText.update(titleLayout)
        statusText.update(statusLayout)
        let titleY = floor((40 - titleLayout.layoutSize.height - statusLayout.layoutSize.height - 2) / 2)
        titleText.setFrameOrigin(NSMakePoint(44, titleY))
        statusText.setFrameOrigin(NSMakePoint(44, titleY + titleLayout.layoutSize.height + 2))
        searchView.frame = NSRect(origin: .zero, size: expandedSearchRect.size)
    }

    override func layout() {
        super.layout()
        updateLayout(size: bounds.size, transition: .immediate)
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        searchView.updateLocalizationAndTheme(theme: theme)
        searchView.backgroundColor = .clear
        titleGlass.updateLocalizationAndTheme(theme: theme)
        searchGlass.updateLocalizationAndTheme(theme: theme)
        needsLayout = true
    }

    required init(frame frameRect: NSRect) { fatalError("init(frame:) has not been implemented") }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private final class EmptyView : View {
    private let imageView = ImageView()
    private let textView = TextView()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(imageView)
        addSubview(textView)
        imageView.isAccessibilityDecorative = true
    }
    
    func update(_ text: String) {
        
        self.imageView.image = TelegramThemeHooks.shared.image(.iconRecentLogs).precomposed(theme.colors.grayIcon)
        self.imageView.sizeToFit()
        
        let attributed = NSMutableAttributedString()
        _ = attributed.append(string: text, color: theme.colors.grayText, font: .normal(.title))
        attributed.detectBoldColorInString(with: .medium(.title))
        let emptyLayout = TextViewLayout(attributed, alignment: .center)
        emptyLayout.measure(width: 250)
        textView.update(emptyLayout)
                
        setFrameSize(NSMakeSize(250, imageView.frame.height + textView.frame.height + 15))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        
        imageView.centerX(y: 0)
        textView.centerX(y: imageView.frame.maxY + 15)
    }
}

public class ChannelEventLogView : View {
    fileprivate let tableView:TableView = TableView(frame: NSZeroRect, isFlipped: false)
    fileprivate let settings: TextButton = TextButton()
    fileprivate let info: ImageButton = ImageButton()
    private var emptyView:EmptyView = EmptyView(frame: .zero)
    private var progress:ProgressIndicator = ProgressIndicator(frame:NSMakeRect(0, 0, 30, 30))
    
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(tableView)
        addSubview(emptyView)
        addSubview(settings)
        addSubview(info)
        addSubview(progress)


        info.autohighlight = false
        info.scaleOnClick = true
        settings.autohighlight = false
        settings.scaleOnClick = true
        settings.autoSizeToFit = false

        settings.set(font: .medium(.title), for: .Normal)


        setFrameSize(frameRect.size)
        updateLocalizationAndTheme(theme: theme)
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = theme as! TelegramPresentationTheme
        settings.set(text: strings().channelEventFilterFilters, for: .Normal)
        settings.set(color: theme.colors.text, for: .Normal)
        settings.set(background: .clear, for: .Highlight)
        settings.set(background: .clear, for: .Normal)
        settings.sizeToFit(NSMakeSize(30, 0), NSMakeSize(0, 40), thatFit: false)
        settings.setFrameSize(NSMakeSize(settings.frame.width, 40))
        settings.layer?.cornerRadius = 20
        settings.setGlassEffect(size: settings.frame.size)

        info.set(image: TelegramThemeHooks.shared.image(.iconChannelPromoInfo).precomposed(theme.colors.text), for: .Normal)
        info.sizeToFit(.zero, NSMakeSize(40, 40), thatFit: true)
        info.layer?.cornerRadius = 20
        info.setGlassEffect(size: NSMakeSize(40, 40))
        info.setAccessibilityLabel(strings().voiceOverCommonInfo)
        needsLayout = true
    }
    
    func updateState(_ state: ChannelEventLogState) {
        self.progress.animates = false
        switch state {
        case .history:
            self.progress.isHidden = true
            self.emptyView.isHidden = true
        case .loading:
            self.progress.isHidden = false
            self.progress.animates = true
            self.emptyView.isHidden = true
        case .empty(let text):
            self.progress.isHidden = true
            self.emptyView.isHidden = false
            self.emptyView.update(text)
        }
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        tableView.frame = NSMakeRect(0, 0, frame.width, frame.height)

        emptyView.center()
        let buttonY = frame.height - settings.frame.height - 12
        settings.setFrameOrigin(NSMakePoint((frame.width - settings.frame.width) / 2, buttonY))
        progress.center()
        info.setFrameOrigin(NSMakePoint(frame.width - info.frame.width - 12, buttonY))

    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private struct State : Equatable {
    var revealed:Set<MessageId> = Set()
    var mediaRevealed: Set<MessageId> = Set()
}

extension AdminLogEventsResult {
    var isGroup: Bool {
        if let peer = peers[peerId] {
            return peer.isSupergroup
        }
        return false
    }
}

private func eventLogItems(_ entries:[ChannelAdminEventLogEntry], state: State, isGroup: Bool, peerId: PeerId, initialSize: NSSize, chatInteraction: ChatInteraction, searchQuery: String) -> [TableRowItem] {
    var items:[TableRowItem] = []
    var index:Int = 0
    
    var groupped: [[ChannelAdminEventLogEntry]] = []
    
    var currentPeerId: PeerId?
    var entriesToProcess = [ChannelAdminEventLogEntry]()

    func processAndClearCurrentEntries() {
        if !entriesToProcess.isEmpty {
            groupped.append(entriesToProcess)
            entriesToProcess.removeAll()
        }
    }

    for entry in entries {
        switch entry.event.action {
        case .deleteMessage:
            if currentPeerId != entry.event.peerId {
                processAndClearCurrentEntries()
                currentPeerId = entry.event.peerId
            }
            entriesToProcess.append(entry)
        default:
            if currentPeerId != nil {
                processAndClearCurrentEntries()
            }
            currentPeerId = nil
            entriesToProcess.append(entry)
            processAndClearCurrentEntries()
        }
    }

    processAndClearCurrentEntries()
    
    let getGroupMessageId:([ChannelAdminEventLogEntry]) -> MessageId? = { group in
        let last = group[group.count - 1]
        switch last.event.action {
        case let .deleteMessage(message):
            return message.id
        default:
            return nil
        }
    }
    
    for group in groupped {
        for (i, entry) in group.enumerated() {
            switch entry.event.action {
            case let .editMessage(prev, new):
                let updatedMedia: TelegramMediaWebpage = .init(webpageId: MediaId(namespace: 0, id: 0), content: .Loaded(.init(url: "", displayUrl: "", hash: 0, type: "edited", websiteName: strings().channelEventLogOriginalMessage, title: nil, text: prev.text, embedUrl: nil, embedType: nil, embedSize: nil, duration: nil, author: nil, isMediaLargeByDefault: true, imageIsVideoCover: false, image: prev.media.first as? TelegramMediaImage, file: prev.media.first as? TelegramMediaFile, story: nil, attributes: [], instantPage: nil)))
                
                let new = new.withUpdatedMedia([updatedMedia])
                
                let item = ChatRowItem.item(initialSize, from: .MessageEntry(new, MessageIndex(new), true, theme.bubbled ? .bubble : .list, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(highlightFoundText: .init(query: searchQuery, isMessage: true), eventLog: entry.event, isRevealed: state.mediaRevealed.contains(new.id)), AutoplayMediaPreferences.defaultSettings)), interaction: chatInteraction, theme: theme) as? ChatRowItem
                
                if let item = item {
                    items.append(item)
                }
            case let .deleteMessage(message):
                var message = ChannelAdminUIHooks.shared.messageWithUpdatedTimestamp(message, entry.event.date)
                
                guard let groupId = getGroupMessageId(group) else {
                    return items
                }
                
                if i == group.count - 1, group.count > 1, !state.revealed.contains(groupId) {
                    let attribute = ReplyMarkupMessageAttribute(rows: [.init(buttons: [.init(title: strings().eventLogServiceShowMoreOther(group.count - 1), titleWhenForwarded: nil, action: .text, style: nil)])], flags: [.inline], placeholder: nil)
                    message = message.withUpdatedReplyMarkupAttribute(attribute)
                }
                if group.count == 1 || state.revealed.contains(groupId) || i == group.count - 1 {
                    items.append(ChatRowItem.item(initialSize, from: .MessageEntry(ChannelAdminUIHooks.shared.messageWithUpdatedTimestamp(message, entry.event.date), MessageIndex(message), true, theme.bubbled ? .bubble : .list, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(highlightFoundText: .init(query: searchQuery, isMessage: true), eventLog: entry.event, isRevealed: state.mediaRevealed.contains(message.id)), AutoplayMediaPreferences.defaultSettings)), interaction: chatInteraction, theme: theme))
                }
            case let .sendMessage(message):
                items.append(ChatRowItem.item(initialSize, from: .MessageEntry(ChannelAdminUIHooks.shared.messageWithUpdatedTimestamp(message, entry.event.date), MessageIndex(message), true, theme.bubbled ? .bubble : .list, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(highlightFoundText: .init(query: searchQuery, isMessage: true), eventLog: entry.event, isRevealed: state.mediaRevealed.contains(message.id)), AutoplayMediaPreferences.defaultSettings)), interaction: chatInteraction, theme: theme))
            case let .updatePinned(message):
                if let message = message {
                    items.append(ChatRowItem.item(initialSize, from: .MessageEntry(ChannelAdminUIHooks.shared.messageWithUpdatedTimestamp(message, entry.event.date), MessageIndex(message), true, theme.bubbled ? .bubble : .list, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(highlightFoundText: .init(query: searchQuery, isMessage: true), eventLog: entry.event, isRevealed: state.mediaRevealed.contains(message.id)), AutoplayMediaPreferences.defaultSettings)), interaction: chatInteraction, theme: theme))
                }
            default:
                break
            }
        }
        if let entry = group.first {
            let id = getGroupMessageId(group)
            let groupRevealed = id != nil ? state.revealed.contains(id!) : false
            items.append(ServiceEventLogItem(initialSize, entry: entry, isGroup: isGroup, chatInteraction: chatInteraction, group: group, groupRevealed: groupRevealed, toggleGroup: {
                if let id = id {
                    chatInteraction.executeReplymarkup(id)
                }
            }))
            index += 1
        }
    }
    
    
    items.insert(GeneralRowItem(.zero, height: 60, stableId: -1000, backgroundColor: .clear), at: 0)
    items.append(GeneralRowItem(.zero, height: NavigationBarStyle.defaultHeight + 10, stableId: 1000, backgroundColor: .clear))
    
    for (i, item) in items.enumerated() {
        _ = item.makeSize(initialSize.width, oldWidth: initialSize.width)
        item._index = i
    }
    return items
}

open class ChannelEventLogController<Context: AccountContextProtocol>: TelegramGenericViewController<ChannelEventLogView, Context> {
    private let peerId:PeerId
    private let peer: EnginePeer
    private let chatInteraction:ChatInteraction
    private var inSearch = false
    private let disposable = MetaDisposable()
    private let searchState:ValuePromise<SearchState> = ValuePromise(SearchState(state: .None, request: nil), ignoreRepeated: true)
    private let filterDisposable = MetaDisposable()
    private let updateFilterDisposable = MetaDisposable()
    
    private var isGroup: Bool = true
    
    private let scrollDownOnNext: Atomic<Bool> = Atomic(value: false)
    
    private let filterStateValue:ValuePromise<ChannelEventFilterState> = ValuePromise(ChannelEventFilterState())
    private let filterState:Atomic<ChannelEventFilterState> = Atomic(value: ChannelEventFilterState())

    private func updateFilter(_ f:(ChannelEventFilterState)->ChannelEventFilterState) -> Void {
        self.filterStateValue.set(filterState.modify(f))
    }
        
    open override var defaultBarStatus: String? {
        let state = self.filterState.with { $0 }
        
        if state.isFull {
            return strings().telegramChannelEventLogController
        } else {
            return strings().channelEventLogsTitleSelected
        }
        
    }
    
    open override var defaultBarTitle: String {
        return self.peer._asPeer().displayTitle
    }
    
    open override func viewClass() -> AnyClass {
        return ChannelEventLogView.self
    }
    

    private func showFilter() {
        let state = filterState.with { $0 }
        let context = self.context
        let peerId = self.peerId
        let isChannel = !self.isGroup
        let adminsPromise = ValuePromise<[RenderedChannelParticipant]?>(nil)
        _ = context.peerChannelMemberCategoriesContextsManager.admins(peerId: peerId, updated: { membersState in
            if case .loading = membersState.loadingState, membersState.list.isEmpty {
                adminsPromise.set(nil)
            } else {
                adminsPromise.set(membersState.list)
            }
        })
            
        let admins = adminsPromise.get() |> filter { $0 != nil } |> take(1) |> map { $0! }
        filterDisposable.set(showModalProgress(signal: admins, for: context.window).start(next: { [weak self] admins in
            showModal(with: ChannelEventFilterModalController(context: context, peerId: peerId, isChannel: isChannel, admins: admins, state: state, updated: { [weak self] updatedState in
                
                _ = self?.scrollDownOnNext.swap(true)
                self?.updateFilter { _ in
                    return updatedState
                }
                _ = self?.scrollDownOnNext.swap(true)
                self?.requestUpdateCenterBar()
        }), for: context.window)
            
        }))
    }
    
    public init(_ context: Context, peer: EnginePeer) {
        self.peerId = peer.id
        self.peer = peer
        chatInteraction = ChatInteraction(chatLocation: .peer(peerId), context: context, isLogInteraction: true)
        chatInteraction.update {
            $0.updatedPeer { _ in
                peer._asPeer()
            }
        }
        super.init(context)
        
    }
    
    open override var enableBack: Bool {
        return true
    }
    
    deinit {
        disposable.dispose()
        filterDisposable.dispose()
        updateFilterDisposable.dispose()
    }
    
    open override func getCenterBarViewOnce() -> TitledBarView {
        let bar = EventLogTitleBarView(controller: self)
        bar.setPeer(account: context.account, peer: peer._asPeer())
        return bar
    }

    open override func requestUpdateCenterBar() {
        super.requestUpdateCenterBar()
        centerBarView.needsLayout = true
    }

    private var searchView: SearchView? {
        return (centerBarView as? EventLogTitleBarView)?.searchView
    }

    private var searchButtonImage: CGImage {
        return inSearch ? TelegramThemeHooks.shared.image(.iconPipClose).precomposed(theme.colors.text) : theme.icons.chatSearch
    }

    private func toggleSearch() {
        if inSearch { hideSearch() } else { showSearch() }
    }

    private func showSearch() {
        guard !inSearch, let bar = centerBarView as? EventLogTitleBarView else { return }
        inSearch = true
        bar.setSearching(true)
        bar.layoutSubtreeIfNeeded()
        bar.searchView.setString("")
        bar.searchView.change(state: .Focus, false)
        bar.searchView.updateClearVisibility(false)
        requestUpdateRightBar()
    }

    private func hideSearch() {
        guard inSearch, let bar = centerBarView as? EventLogTitleBarView else { return }
        inSearch = false
        bar.searchView.setString("")
        bar.searchView.change(state: .None, false)
        bar.setSearching(false)
        window?.makeFirstResponder(genericView.tableView)
        requestUpdateRightBar()
    }

    open override func firstResponder() -> NSResponder? {
        return inSearch ? searchView?.input : super.firstResponder()
    }

    open override func requestUpdateRightBar() {
        super.requestUpdateRightBar()
        if let bar = rightBarView as? ImageBarView {
            if bar.button.imageView.image != searchButtonImage, bar.window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                let transition = CATransition()
                transition.type = .fade
                transition.duration = ChatInputSendButton.fieldMotionDuration
                transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
                bar.button.imageView.layer?.add(transition, forKey: "eventLogSearchIcon")
            }
            bar.set(image: searchButtonImage)
            bar.button.setAccessibilityLabel(inSearch ? strings().voiceOverCommonCancel : strings().voiceOverCommonSearch)
        }
    }

    open override func getRightBarViewOnce() -> BarView {
        let bar = ImageBarView(controller: self, searchButtonImage)
        bar.button.set(handler: { [weak self] _ in self?.toggleSearch() }, for: .Click)
        bar.button.setAccessibilityLabel(strings().voiceOverCommonSearch)
        bar.button.scaleOnClick = true
        return bar
    }

    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if let controller = ChannelAdminUIHooks.shared.getAudioPlayer(context), let header = self.navigationController?.header, header.needShown {
            let object = ChannelAdminUIHooks.shared.makeInlineAudioPlayerContextObject(controller, context, genericView.tableView, nil)
            header.view.update(with: object)
        }
    }
    
    open override func escapeKeyAction() -> KeyHandlerResult {
        if inSearch {
            hideSearch()
            return .invoked
        }
        return super.escapeKeyAction()
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            if let strongSelf = self {
                strongSelf.toggleSearch()
            }
            return .invoked
            }, with: self, for: .F, modifierFlags: [.command])
    }
    
    open override var backdorColor: NSColor {
        return theme.colors.listBackground
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        
        genericView.tableView.getBackgroundColor = {
            return .clear
        }
        
        let statePromise = ValuePromise(State(), ignoreRepeated: true)
        let stateValue = Atomic(value: State())
        let updateState: ((State) -> State) -> Void = { f in
            statePromise.set(stateValue.modify (f))
        }
        
        let searchState = self.searchState
        let context = self.context
        let initialSize = self.atomicSize
        let chatInteraction = self.chatInteraction
        let peerId = self.peerId
        let eventLogContext = context.engine.peers.channelAdminEventLog(peerId: peerId)
        let scrollDownOnNext = self.scrollDownOnNext
        
        let searchQuery: Atomic<String> = Atomic(value: "")

        let arguments = Arguments(context: context, toggleReveal: { messageId in
            updateState { current in
                var current = current
                if current.revealed.contains(messageId) {
                    current.revealed.remove(messageId)
                } else {
                    current.revealed.insert(messageId)
                }
                return current
            }
        })
        
        chatInteraction.executeReplymarkup = { messageId in
            arguments.toggleReveal(messageId)
        }

        chatInteraction.revealMedia = { message in
            let reveal = {
                updateState { current in
                    var current = current
                    current.mediaRevealed.insert(message.id)
                    return current
                }
            }
            if message.isSensitiveContent(platform: "ios", contentSettings: context.contentSettings), !context.contentConfig.sensitiveContentEnabled {
                if context.contentConfig.canAdjustSensitiveContent, context.appConfiguration.getBoolValue("need_age_video_verification", orElse: false) {
                    ChatNavigationHooks.shared.showVerifyAgeAlert(context, context.window)
                    return
                }
                verifyAlert(for: context.window, header: strings().chatSensitiveContent, information: strings().chatSensitiveContentConfirm, ok: strings().chatSensitiveContentConfirmOk, successHandler: { _ in
                    reveal()
                })
            } else {
                reveal()
            }
        }
        
        chatInteraction.focusMessageId = { [weak self] messageId, focusTarget, _ in
            self?.navigationController?.push(ChatAdditionController(context: context, chatLocation: .peer(peerId), focusTarget: focusTarget))
        }
        

        genericView.info.set(handler: { _ in
            alert(for: context.window, header: strings().channelEventLogAlertHeader, info: strings().channelEventLogAlertInfo)
        }, for: .Click)
        
        
        genericView.settings.set(handler: { [weak self] _ in
            self?.showFilter()
        }, for: .Click)
        
        searchView?.searchInteractions = SearchInteractions({ [weak self] state, _ in
            _ = searchQuery.swap(state.request)
            _ = scrollDownOnNext.swap(true)
            searchState.set(state)
            _ = scrollDownOnNext.swap(true)
            if state.state == .None { self?.hideSearch() }
        }, { [weak self] state in
            self?.searchView?.updateClearVisibility(!state.request.isEmpty)
            _ = searchQuery.swap(state.request)
            _ = scrollDownOnNext.swap(true)
            searchState.set(state)
            _ = scrollDownOnNext.swap(true)
        })
        

        self.chatInteraction.openInfo = { [weak self] peerId, _, _, _ in
            if let navigation = self?.navigationController {
                ChannelAdminUIHooks.shared.pushPeerInfo(navigation, context, peerId)
            }
        }
        
        self.chatInteraction.inlineAudioPlayer = { [weak self] controller in
            ChannelAdminUIHooks.shared.showInlineAudioPlayer(controller, context, self?.genericView.tableView, nil)
        }
        
        let updateFilter = combineLatest(queue: .mainQueue(), searchState.get(), filterStateValue.get())
        
        updateFilterDisposable.set(updateFilter.start(next: { search, filter in
            eventLogContext.setFilter(.init(query: search.request, events: filter.selectedFlags, adminPeerIds: filter.selectedAdmins))
        }))

        let isGroup = !peer._asPeer().isChannel
        
        let signal: Signal<([TableRowItem], ([ChannelAdminEventLogEntry], Bool, ChannelAdminEventLogUpdateType, Bool), Bool), NoError> = combineLatest(eventLogContext.get(), statePromise.get()) |> map { result, state in
            let items = eventLogItems(result.0.reversed(), state: state, isGroup: isGroup, peerId: peerId, initialSize: initialSize.with { $0 }, chatInteraction: chatInteraction, searchQuery: searchQuery.with { $0 })
             return (items, result, isGroup)

        } |> deliverOnMainQueue
        
        
        
        disposable.set(signal.start(next: { [weak self] items, result, isGroup in
            guard let self else {
                return
            }
            
            let tableView = self.genericView.tableView

            let (deleteIndices, indicesAndItems, updatedAndItems) = mergeListsStableWithUpdates(leftList: tableView.allItems, rightList: items)
            
            let animated: Bool
            let scrollState: TableScrollState
            if scrollDownOnNext.swap(false) {
                scrollState = .down(false)
                animated = false
            } else {
                scrollState = .saveVisible(.upper, false)
                animated = false
            }
            
            let transition = TableUpdateTransition(deleted: deleteIndices, inserted: indicesAndItems.map { ($0.0, $0.1) }, updated: updatedAndItems.map { ($0.0, $0.1) }, animated: animated, state: scrollState, grouping: true)
            
            tableView.merge(with: transition)
            
           

            self.isGroup = isGroup
            
            switch result.2 {
            case .initial:
                self.genericView.updateState(.loading)
            case .load, .generic:
                if items.isEmpty {
                    self.genericView.updateState(.empty(!isGroup ? strings().channelEventLogEmptyText : strings().groupEventLogEmptyText))
                } else {
                    self.genericView.updateState(.history)
                }
            }
            self.readyOnce()
        }))
        
        genericView.tableView.setScrollHandler { scroll in
            switch scroll.direction {
            case .bottom:
                eventLogContext.loadMoreEntries()
            default:
                break
            }
        }
            

    }
    
    
}

