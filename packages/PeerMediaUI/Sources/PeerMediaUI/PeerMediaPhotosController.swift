import Cocoa
import CoreMedia
import TGUIKit
import TelegramCore

import Postbox
import SwiftSignalKit
import AlertsUI
import ChatHistoryModel
import ChatModeTypes
import GalleryUI
import GeneralRows
import Localization
import MessageUtils
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import ChatUI
import InputDataUI

enum PeerMediaMonthEntry : TableItemListNodeEntry {
    case line(index: MessageIndex, stableId: MessageIndex, items: [Message], galleryType: GalleryAppearType, viewType: GeneralViewType, gap: Int)
    case date(index: MessageIndex)
    case section(index: MessageIndex)
        
    static func < (lhs: PeerMediaMonthEntry, rhs: PeerMediaMonthEntry) -> Bool {
        if lhs.index != rhs.index {
            return lhs.index > rhs.index
        }
        if lhs.order != rhs.order {
            return lhs.order < rhs.order
        }
        return sharedMediaDisplayPrecedes(lhs.stableId, rhs.stableId)
    }
    
    private var order: Int {
        switch self {
        case .section:
            return 0
        case .date:
            return 1
        case .line:
            return 2
        }
    }
    
    var description: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy";
        switch self {
        case let .line(index, _, _, _, _, _):
            let date = Date(timeIntervalSince1970: TimeInterval(index.timestamp))
            return "items: \(formatter.string(from: date))"
        case let .date(index):
            let date = Date(timeIntervalSince1970: TimeInterval(index.timestamp))
            return "date: \(formatter.string(from: date))"
        case let .section(index):
            let date = Date(timeIntervalSince1970: TimeInterval(index.timestamp))
            return "section: \(formatter.string(from: date))"
        }
    }
    
    func item(_ arguments: PeerMediaPhotosArguments, initialSize: NSSize) -> TableRowItem {
        switch self {
        case let .line(_, stableId, items, galleryType, viewType, gap):
            return PeerPhotosMonthItem(initialSize, stableId: stableId, viewType: viewType, context: arguments.context, chatInteraction: arguments.chatInteraction, items: items, gap: gap, galleryType: galleryType, gallery: arguments.gallery)
        case .date:
            return PeerMediaDateItem(initialSize, index: index, stableId: stableId)
        case .section:
            return GeneralRowItem(initialSize, height: 20, stableId: stableId, viewType: .separator)
        }
    }
    
    var stableId: MessageIndex {
        switch self {
        case let .line(_, stableId, _, _, _, _):
            return stableId
        default:
            return self.index
        }
    }
    
    var index: MessageIndex {
        switch self {
        case let .line(index, _, _, _, _, _):
            return index
        case let .date(index):
            return index
        case let .section(index):
            return index
        }
    }
}

final class PeerMediaPhotosArguments {
    let context: any AccountContextProtocol
    let chatInteraction: ChatInteraction
    let gallerySupplyment: InteractionContentViewProtocol
    let gallery:(Message, GalleryAppearType)->Void
    init(context: any AccountContextProtocol, chatInteraction: ChatInteraction, gallerySupplyment: InteractionContentViewProtocol, gallery:@escaping(Message, GalleryAppearType)->Void) {
        self.context = context
        self.gallerySupplyment = gallerySupplyment
        self.chatInteraction = chatInteraction
        self.gallery = gallery
    }
}



private struct PeerMediaPhotosState : Equatable {
    static func == (lhs: PeerMediaPhotosState, rhs: PeerMediaPhotosState) -> Bool {
        if lhs.view !== rhs.view {
            guard lhs.view?.laterId == rhs.view?.laterId,
                  lhs.view?.earlierId == rhs.view?.earlierId,
                  lhs.view?.holeLater == rhs.view?.holeLater,
                  lhs.view?.holeEarlier == rhs.view?.holeEarlier,
                  lhs.view?.anchorIndex == rhs.view?.anchorIndex else {
                return false
            }
        }
        return lhs.isLoading == rhs.isLoading && lhs.messages == rhs.messages && lhs.searchState == rhs.searchState && lhs.contentSettings == rhs.contentSettings && lhs.scrollPosition == rhs.scrollPosition && lhs.updateType == rhs.updateType && lhs.side == rhs.side && lhs.perRowCount == rhs.perRowCount
    }
    
    var isLoading: Bool
    var messages:[Message]
    var searchState: SearchState
    var contentSettings: ContentSettings
    var scrollPosition: ChatHistoryViewScrollPosition?
    var updateType: ChatHistoryViewUpdateType?
    var side: TableSavingSide?
    var view: MessageHistoryView?
    var perRowCount: Int
    init(isLoading: Bool, messages: [Message], searchState: SearchState, contentSettings: ContentSettings, scrollPosition: ChatHistoryViewScrollPosition?, updateType: ChatHistoryViewUpdateType?, side: TableSavingSide?, perRowCount: Int) {
        self.isLoading = isLoading
        self.messages = messages.reversed().filter { $0.restrictedText(contentSettings) == nil }
        self.searchState = searchState
        self.contentSettings = contentSettings
        self.updateType = updateType
        self.scrollPosition = scrollPosition
        self.side = side
        self.perRowCount = perRowCount
    }
}

struct PeerMediaGridBounds {
    let laterIndex: MessageIndex?
    let earlierIndex: MessageIndex?
    let holeLater: Bool
    let holeEarlier: Bool

    static let complete = PeerMediaGridBounds(laterIndex: nil, earlierIndex: nil, holeLater: false, holeEarlier: false)

    init(laterIndex: MessageIndex?, earlierIndex: MessageIndex?, holeLater: Bool, holeEarlier: Bool) {
        self.laterIndex = laterIndex
        self.earlierIndex = earlierIndex
        self.holeLater = holeLater
        self.holeEarlier = holeEarlier
    }

    init(view: MessageHistoryView?) {
        if let view {
            self.init(laterIndex: view.laterId, earlierIndex: view.earlierId, holeLater: view.holeLater, holeEarlier: view.holeEarlier)
        } else {
            self = .complete
        }
    }
}

struct PeerMediaGridHint {
    let perRowCount: Int
    private(set) var rowStarts: [MessageId: Bool]

    init(perRowCount: Int) {
        self.perRowCount = perRowCount
        self.rowStarts = [:]
    }

    func recording(_ entries: [PeerMediaMonthEntry], perRowCount: Int) -> PeerMediaGridHint {
        var result = perRowCount == self.perRowCount ? self : PeerMediaGridHint(perRowCount: perRowCount)
        var isFirstRowOfMonth = true
        for entry in entries {
            switch entry {
            case .date, .section:
                isFirstRowOfMonth = true
            case let .line(_, _, items, _, _, _):
                let isEdge = isFirstRowOfMonth && items.count < perRowCount
                for (index, message) in items.enumerated() {
                    result.rowStarts[message.id] = index == 0 && !isEdge
                }
                isFirstRowOfMonth = false
            }
        }
        return result
    }
}

func peerMediaMonthEntries(messages: [Message], perRowCount: Int, timeDifference: Int32, isExternalSearch: Bool, bounds: PeerMediaGridBounds, hint: PeerMediaGridHint?) -> [PeerMediaMonthEntry] {
    let galleryType: GalleryAppearType = isExternalSearch ? .messages(messages) : .history
    let viewType: GeneralViewType = .modern(position: .inner, insets: NSEdgeInsetsMake(0, 0, 0, 0))
    let perRowCount = max(1, perRowCount)

    var months: [(index: MessageIndex, items: [Message])] = []
    var current: [Message] = []
    var currentDateId: Int64?
    for message in messages {
        let dateId = mediaDateId(for: message.timestamp - timeDifference)
        if let currentDateId, currentDateId != dateId, let last = current.last {
            months.append((MessageIndex(id: MessageId(peerId: last.id.peerId, namespace: last.id.namespace, id: 0), timestamp: Int32(currentDateId)), current))
            current.removeAll()
        }
        currentDateId = dateId
        current.append(message)
    }
    if let currentDateId, let last = current.last {
        months.append((MessageIndex(id: MessageId(peerId: last.id.peerId, namespace: last.id.namespace, id: 0), timestamp: Int32(currentDateId)), current))
    }

    let rowStarts = hint?.perRowCount == perRowCount ? hint?.rowStarts ?? [:] : [:]
    func monthOf(_ index: MessageIndex) -> Int64 {
        return mediaDateId(for: index.timestamp - timeDifference)
    }

    var entries: [PeerMediaMonthEntry] = []
    for (monthIndex, month) in months.enumerated() {
        let items = month.items
        let dateId = Int64(month.index.timestamp)
        let startLoaded = isExternalSearch || monthIndex > 0 || (bounds.laterIndex.map { monthOf($0) != dateId } ?? !bounds.holeLater)
        let endLoaded = isExternalSearch || monthIndex < months.count - 1 || (bounds.earlierIndex.map { monthOf($0) != dateId } ?? !bounds.holeEarlier)

        let leading: Int
        if startLoaded {
            leading = 0
        } else if let anchor = items.firstIndex(where: { rowStarts[$0.id] == true }) {
            leading = anchor % perRowCount
        } else if endLoaded {
            leading = items.count % perRowCount
        } else {
            leading = 0
        }

        if monthIndex > 0 {
            entries.append(.date(index: month.index))
        }
        var position = 0
        while position < items.count {
            let length = position == 0 && leading > 0 ? leading : perRowCount
            let chunk = Array(items[position ..< min(position + length, items.count)])
            let gap = position == 0 && leading > 0 ? perRowCount - leading : 0
            entries.append(.line(index: month.index, stableId: MessageIndex(chunk[0]), items: chunk, galleryType: galleryType, viewType: viewType, gap: gap))
            position += length
        }
    }
    return entries
}

fileprivate func prepareTransition(left:[AppearanceWrapperEntry<PeerMediaMonthEntry>], right: [AppearanceWrapperEntry<PeerMediaMonthEntry>], animated: Bool, scrollPostion: ChatHistoryViewScrollPosition?, updateType: ChatHistoryViewUpdateType?, side: TableSavingSide?, initialSize:NSSize, arguments: PeerMediaPhotosArguments) -> TableUpdateTransition {
    let (removed, inserted, updated) = proccessEntriesWithoutReverse(left, right: right) { entry -> TableRowItem in
        return entry.entry.item(arguments, initialSize: initialSize)
    }
    
    var scrollState: TableScrollState = .none(nil)
    if let scrollPostion = scrollPostion {
        switch scrollPostion {
        case .index(_, let position, _, _):
            scrollState = position
        default:
            break
        }
    } else {
        if let updateType = updateType {
            switch updateType {
            case .Initial:
                scrollState = .none(nil)
            case .Generic(let type):
                switch type {
                case .Initial, .FillHole, .UpdateVisible:
                    scrollState = .saveVisible(side ?? .upper, false)
                default:
                    break
                }
            }
        }
    }
    
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: animated, state: scrollState)
}


private struct SearchResult {
    let result: [Message]?
}

private struct FindSearchMessage {
    let message:Message?
    let loaded:Bool
}

private final class PeerMediaSupplyment : InteractionContentViewProtocol {
    private weak var tableView: TableView?
    init(tableView: TableView) {
        self.tableView = tableView
    }
    
    func contentInteractionView(for stableId: AnyHashable, animateIn: Bool) -> NSView? {
        if let stableId = stableId.base as? ChatHistoryEntryId, let tableView = tableView {
            switch stableId {
            case let .message(message):
                var found: NSView? = nil
                tableView.enumerateItems { item -> Bool in
                    if let item = item as? PeerPhotosMonthItem {
                        if item.contains(message.id) {
                            found = item.view?.interactionContentView(for: message.id, animateIn: animateIn)
                        }
                    }
                    return found == nil
                }
                return found
            default:
                break
            }
        }
        return nil
    }
    func interactionControllerDidFinishAnimation(interactive: Bool, for stableId: AnyHashable) {
        
    }
    func addAccesoryOnCopiedView(for stableId: AnyHashable, view: NSView) {
        addPeerPhotosAccesoryOnCopiedView(for: stableId, view: view, tableView: tableView)
    }
    func videoTimebase(for stableId: AnyHashable) -> CMTimebase? {
        return nil
    }
    func applyTimebase(for stableId: AnyHashable, timebase: CMTimebase?) {
        
    }
}

open class PeerMediaPhotosController<Context: AccountContextProtocol>: TableViewController<Context>, PeerMediaSearchable {

    open override var defaultBarTitle: String {
        return localizedString("Telegram.PeerMediaPhotosController")
    }

    private let peerId: PeerId
    private let disposable = MetaDisposable()
    private let historyDisposable = MetaDisposable()
    private let chatInteraction: ChatInteraction
    private let previous: Atomic<[AppearanceWrapperEntry<PeerMediaMonthEntry>]> = Atomic(value: [])
    private let tags: MessageTags
    private var isExternalSearch: Bool = false
    private let location: ValuePromise<ChatHistoryLocation> = ValuePromise(ignoreRepeated: false)
    private var locationValue: ChatHistoryLocation? = nil
    private var isTopHistory: (()->Bool)? = nil
    private var updatePerRowCount:((Int) -> Void)? = nil
    private var threadInfo: ThreadInfo?
    private var pendingLocation: ChatHistoryLocation?
    private var pendingLocationScheduled = false
    private var lastNavigationTime: CFTimeInterval = 0
    private func setLocation(_ location: ChatHistoryLocation) -> Void {
        #if DEBUG
        PeerMediaGridDebug.locationChanges += 1
        #endif
        self.location.set(location)
        self.locationValue = location
    }
    
    private func navigate(to location: ChatHistoryLocation) {
        let interval: CFTimeInterval = 0.2
        let elapsed = CACurrentMediaTime() - self.lastNavigationTime
        if elapsed >= interval {
            self.pendingLocation = nil
            self.lastNavigationTime = CACurrentMediaTime()
            self.setLocation(location)
        } else {
            self.pendingLocation = location
            if !self.pendingLocationScheduled {
                self.pendingLocationScheduled = true
                DispatchQueue.main.asyncAfter(deadline: .now() + (interval - elapsed), execute: { [weak self] in
                    guard let self else {
                        return
                    }
                    self.pendingLocationScheduled = false
                    if let pending = self.pendingLocation {
                        self.pendingLocation = nil
                        if pending != self.locationValue {
                            self.lastNavigationTime = CACurrentMediaTime()
                            self.setLocation(pending)
                        }
                    }
                })
            }
        }
    }
    
    public init(_ context: Context, chatInteraction: ChatInteraction, threadInfo: ThreadInfo?, peerId: PeerId, tags: MessageTags) {
        self.peerId = peerId
        self.threadInfo = threadInfo
        self.chatInteraction = chatInteraction
        self.tags = tags
        super.init(context)
        bar = .init(height: 0)
    }
    
    private var perRowCount: Int {
        return PeerMediaGridSizing(width: atomicSize.with { $0.width }, maximumColumns: 7).columns
    }
    
    private func perPageCount() -> Int {
        let size = atomicSize.with { $0 }
        return PeerMediaGridSizing(width: size.width, maximumColumns: 7).itemCount(height: size.height) * 10
    }
    
    public override func viewDidResized(_ size: NSSize) {
        super.viewDidResized(size)
        
        updatePerRowCount?(self.perRowCount)
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        self.genericView.verticalScrollElasticity = .none
        self.genericView.clipView.skipsDisplayOnScroll = true

        #if DEBUG
        if self.tags == .photoOrVideo {
            PeerMediaGridDebug.tables.add(self.genericView)
        }
        #endif

        self.genericView.getBackgroundColor = {
            theme.colors.background
        }
                
        let context = self.context
        let peerId = self.peerId
        let threadId = self.threadInfo?.message.threadId
        let initialSize = self.atomicSize
        let tags = self.tags
        let isExternalSearch = self.isExternalSearch
        let perPageCount = self.perPageCount

        self.genericView.set(stickClass: PeerMediaDateItem.self, handler: { item in
            
        })
        
        self.genericView.needUpdateVisibleAfterScroll = true
        self.searchState.set(.single(SearchState(state: .None, request: nil)))
        self.genericView.emptyItem = PeerMediaEmptyRowItem(NSZeroSize, tags: self.tags)
        

        let requestCount = perPageCount()
        
        setLocation(.Initial(count: requestCount, scrollPosition: nil))
        
        
        let initialState = PeerMediaPhotosState(isLoading: false, messages: [], searchState: SearchState(state: .None, request: nil), contentSettings: context.contentSettings, scrollPosition: nil, updateType: nil, side: nil, perRowCount: self.perRowCount)
        let state: ValuePromise<PeerMediaPhotosState> = ValuePromise(ignoreRepeated: true)
        let stateValue: Atomic<PeerMediaPhotosState> = Atomic(value: initialState)
        let updateState:((PeerMediaPhotosState)->PeerMediaPhotosState) -> Void = { f in
            state.set(stateValue.modify(f))
        }
        
        updatePerRowCount = { value in
            updateState { current in
                var current = current
                current.perRowCount = value
                return current
            }
        }
        
        let supplyment = PeerMediaSupplyment(tableView: genericView)
        
        let mode: ChatMode
        let chatLocation = chatInteraction.chatLocation
        
        let contextHolder: Atomic<ChatLocationContextHolder?>
        if let threadInfo = threadInfo {
            mode = .thread(mode: .topic(origin: threadInfo.message.effectiveTopId))
            contextHolder = threadInfo.contextHolder
        } else {
            mode = .history
            contextHolder = .init(value: nil)
        }
        
        let arguments = PeerMediaPhotosArguments(context: context, chatInteraction: chatInteraction, gallerySupplyment: supplyment, gallery: { [weak self] message, type in
            
            let accept:()->Void = { [weak self] in
                let parameters = ChatMediaGalleryParameters(showMedia: { _ in }, showMessage: { message in
                    self?.chatInteraction.focusMessageId(nil, .init(messageId: message.id, string: nil), .center(id: 0, innerId: nil, animated: false, focus: .init(focus: true), inset: 0))
                }, isWebpage: false, media: message.anyMedia!, automaticDownload: true)

                // Rich messages are expanded into synthetic per-media messages and aren't in the live
                // tagged history under one id — page the prepared list via `.messages`.
                let galleryType = sharedMediaGalleryType(for: message, fallback: type, preparedMessages: stateValue.with { $0.messages })
                showChatGallery(context: context, message: message, supplyment, parameters, type: galleryType, reversed: true, chatMode: mode, chatLocation: chatLocation, contextHolder: contextHolder, cachedPeerData: self?.chatInteraction.presentation.cachedData)
            }
            
            if message.isSensitiveContent(platform: "ios") {
                
                if !context.contentConfig.sensitiveContentEnabled, context.contentConfig.canAdjustSensitiveContent {
                    let need_verification = context.appConfiguration.getBoolValue("need_age_video_verification", orElse: false)
                    
                    if need_verification {
                        if let controller = FeatureNavigationHooks.shared.makeVerifyAgeController(context) { showModal(with: controller, for: context.window) }
                        return
                    }
                }
                if context.contentConfig.sensitiveContentEnabled {
                    accept()
                } else {
                    verifyAlert(for: context.window, header: strings().chatSensitiveContent, information: strings().chatSensitiveContentConfirm, ok: strings().chatSensitiveContentConfirmOk, option: context.contentConfig.canAdjustSensitiveContent ? strings().chatSensitiveContentConfirmThird : nil, optionIsSelected: false, successHandler: { result in
                        
                        if result == .thrid {
                            let _ = updateRemoteContentSettingsConfiguration(postbox: context.account.postbox, network: context.account.network, sensitiveContentEnabled: true).start()
                        }
                        accept()
                    })
                }
            } else {
                accept()
            }
            
        })
        
        /*
         layoutItem.chatInteraction.focusMessageId(nil, message.id, .center(id: 0, innerId: nil, animated: false, focus: .init(focus: true), inset: 0))

         */
        
        let animated:Atomic<Bool> = Atomic(value:false)

        
        let applyHole:() -> Void = { [weak self] in
            guard let `self` = self, let value = self.locationValue else {
                return
            }
            self.setLocation(value)
        }
        
        let chatLocationInput: ChatLocationInput = self.chatLocationInput
        let searchLoadMore = self.searchLoadMore.signal()
        
        
        let history: Signal<(ChatHistoryViewUpdate?, SearchResult?, SearchState, TableSavingSide?), NoError> = combineLatest(searchState.get(), location.get(), externalSearch.get()) |> mapToSignal { search, location, externalSearch in
            if let externalSearch = externalSearch {
                return .single((nil, SearchResult(result: externalSearch.messages), search, nil))
            } else if !search.request.isEmpty {
                
                return peerMediaSearchMessages(loadMore: searchLoadMore, request: { state in
                    context.engine.messages.searchMessages(location: .peer(peerId: peerId, fromId: nil, tags: tags, reactions: [], threadId: threadId, minDate: nil, maxDate: nil), query: search.request, state: state)
                    |> delay(0.2, queue: .concurrentDefaultQueue())
                }) |> map { (nil, SearchResult(result: $0), search, nil) }
            } else {
                return chatHistoryViewForLocation(location, context: context, chatLocation: .peer(peerId), fixedCombinedReadStates: nil, tag: .tag(tags), chatLocationInput: chatLocationInput) |> map { ($0, nil, search, location.side) }
            }
        }
        
        let historyView: Atomic<MessageHistoryView?> = Atomic(value: nil)
        
        historyDisposable.set(history.start(next: { update in
            
            var messages:[Message]? = nil
            var isLoading: Bool = false
            let view: MessageHistoryView?
            let updateType: ChatHistoryViewUpdateType?

            var scroll: ChatHistoryViewScrollPosition?
            if let update = update.0 {
                switch update {
                case let .Loading(_, ut):
                    view = nil
                    isLoading = true
                    updateType = ut
                case let .HistoryView(_view, _type, _scroll, _):
                    view = _view
                    scroll = _scroll
                    isLoading = _view.isLoading
                    updateType = _type
                }
                
                switch updateType {
                case let .Generic(type: type):
                    switch type {
                    case .FillHole:
                        DispatchQueue.main.async(execute: applyHole)
                    default:
                        break
                    }
                default:
                    break
                }
                messages = view?.entries.map { value in
                    return value.message
                } ?? []
            } else if let update = update.1 {
                if let search = update.result {
                    messages = search
                } else {
                    isLoading = true
                }
                view = nil
                updateType = nil
            } else {
                view = nil
                updateType = nil
            }
            
            
            updateState { state in
                var state = state
                state.isLoading = isLoading
                if let messages = messages {
                    // Rich messages keep their photos/videos in an instant page; expand each into one
                    // synthetic message per media so every photo/video gets its own grid cell.
                    let predicate = sharedMediaPredicate(for: tags)
                    if !isExternalSearch {
                        state.messages = expandSharedMediaMessages(messages.reversed(), where: predicate, reverseMedia: true)
                    } else {
                        state.messages = expandSharedMediaMessages(messages, where: predicate, reverseMedia: true)
                    }
                }
                state.searchState = update.2
                state.scrollPosition = scroll
                state.updateType = updateType
                state.side = update.3
                state.view = view
                return state
            }
        }))
        
        let previous = self.previous
        let gridHint: Atomic<PeerMediaGridHint?> = Atomic(value: nil)
        

        
        let transition: Signal<(TableUpdateTransition, PeerMediaPhotosState), NoError> = combineLatest(queue: prepareQueue, state.get(), appearanceSignal) |> map { state, appearance in
            let monthEntries = peerMediaMonthEntries(messages: state.messages, perRowCount: state.perRowCount, timeDifference: Int32(context.timeDifference), isExternalSearch: isExternalSearch, bounds: isExternalSearch ? .complete : PeerMediaGridBounds(view: state.view), hint: gridHint.with { $0 })
            _ = gridHint.modify { ($0 ?? PeerMediaGridHint(perRowCount: state.perRowCount)).recording(monthEntries, perRowCount: state.perRowCount) }
            let entries = monthEntries.map { AppearanceWrapperEntry(entry: $0, appearance: appearance) }
            return (prepareTransition(left: previous.swap(entries), right: entries, animated: animated.swap(true), scrollPostion: state.scrollPosition, updateType: state.updateType, side: state.side, initialSize: initialSize.with { $0 }, arguments: arguments), state)
        } |> deliverOnMainQueue
        
        
        var previousSearch: SearchState = SearchState(state: .None, request: nil)
        
        
        disposable.set(transition.start(next: { [weak self] transition, state in
            guard let `self` = self else {
                return
            }
            
            if previousSearch != state.searchState {
                self.scrollup()
            }
            previousSearch = state.searchState
            #if DEBUG
            PeerMediaGridDebug.lastMerge = "\(transition.state) \(String(describing: state.updateType)) d\(transition.deleted.count)/i\(transition.inserted.count)/u\(transition.updated.count)"
            PeerMediaGridDebug.willMerge?(self.genericView)
            let mergeStart = CACurrentMediaTime()
            #endif
            self.genericView.merge(with: transition)
            #if DEBUG
            let mergeSeconds = CACurrentMediaTime() - mergeStart
            PeerMediaGridDebug.merges += 1
            PeerMediaGridDebug.mergeSeconds += mergeSeconds
            PeerMediaGridDebug.worstMergeSeconds = max(PeerMediaGridDebug.worstMergeSeconds, mergeSeconds)
            PeerMediaGridDebug.didMerge?(self.genericView)
            #endif
            let searchState = MediaSearchState(state: state.searchState, animated: transition.animated, isLoading: state.isLoading)
            self.mediaSearchState.set(searchState)
            self.readyOnce()
            
            _ = historyView.swap(state.view)
        }))
        
        genericView.setScrollHandler { [weak self] scroll in
            if stateValue.with({ !$0.searchState.request.isEmpty }) {
                if scroll.direction == .bottom {
                    self?.searchLoadMore.putNext(())
                }
                return
            }
            let view = historyView.with { $0 }
            if let view = view, let strongSelf = self {
                var messageIndex:MessageIndex?
                
                switch scroll.direction {
                case .top:
                    if view.laterId != nil {
                        for i in 0 ..< strongSelf.genericView.count {
                            if let item = strongSelf.genericView.item(at: i) as? PeerPhotosMonthItem {
                                if let message = item.items.first {
                                    messageIndex = MessageIndex(message)
                                    break
                                }
                            }
                        }
                    } else if view.laterId == nil, !view.holeLater, let locationValue = strongSelf.locationValue, !locationValue.isAtUpperBound, view.anchorIndex != .upperBound {
                        messageIndex = .upperBound(peerId: strongSelf.chatInteraction.peerId)
                    }
                case .bottom:
                    if view.earlierId != nil {
                        for i in stride(from: strongSelf.genericView.count - 1, to: -1, by: -1) {
                            if let item = strongSelf.genericView.item(at: i) as? PeerPhotosMonthItem {
                                if let message = item.items.last {
                                    messageIndex = MessageIndex(message)
                                    break
                                }
                            }
                        }
                    }
                case .none:
                    break
                }
                if let messageIndex = messageIndex {
                    let location: ChatHistoryLocation = .Navigation(index: MessageHistoryAnchorIndex.message(messageIndex), anchorIndex: MessageHistoryAnchorIndex.message(messageIndex), count: strongSelf.perPageCount(), side: scroll.direction == .bottom ? .upper : .lower)
                    guard location != strongSelf.locationValue else {
                        return
                    }
                    strongSelf.navigate(to: location)
                }
            }
        }
        
        onDeinit = {
            _ = historyView.swap(nil)
        }
        isTopHistory = {
            return historyView.with { $0?.laterId == nil }
        }
    }
    
    private let mediaSearchState:ValuePromise<MediaSearchState> = ValuePromise(ignoreRepeated: true)
    private let searchState:Promise<SearchState> = Promise()
    private let searchLoadMore = ValuePipe<Void>()
    
    public func setSearchValue(_ value: Signal<SearchState, NoError>) {
        searchState.set(value)
    }
    
    private let externalSearch:Promise<ExternalSearchMessages?> = Promise(nil)
    
    public func setExternalSearch(_ value: Signal<ExternalSearchMessages?, NoError>, _ loadMore: @escaping () -> Void) {
        externalSearch.set(value)
        self.isExternalSearch = true
    }
    
    private var chatLocationInput: ChatLocationInput {
        let chatLocationInput: ChatLocationInput
        if let threadInfo = threadInfo {
            chatLocationInput = context.chatLocationInput(for: .thread(threadInfo.message), contextHolder: threadInfo.contextHolder)
        } else {
            chatLocationInput = .peer(peerId: peerId, threadId: nil)
        }
        return chatLocationInput
    }
    
    public func jumpTo(_ toMessage: Message) -> Void {

        let historyView = chatHistoryViewForLocation(.InitialSearch(location: .id(toMessage.id, nil, nil), count: perPageCount()), context: context, chatLocation: .peer(peerId), fixedCombinedReadStates: nil, tag: .tag(.photoOrVideo), additionalData: [], chatLocationInput: self.chatLocationInput)
        
        let signal = historyView
            |> mapToSignal { historyView -> Signal<(Message?, Bool), NoError> in
                switch historyView {
                case .Loading:
                    return .single((nil, true))
                case let .HistoryView(view, _, _, _):
                    for entry in view.entries {
                        if entry.message.id == toMessage.id {
                            return .single((entry.message, false))
                        }
                    }
                    return .single((nil, false))
                }
            } |> take(until: { index in
                return SignalTakeAction(passthrough: index.0 != nil, complete: !index.1)
            }) |> map { $0.0 }
        
        _ = showModalProgress(signal: signal, for: context.window).start(next: { [weak self] message in
            if let strongSelf = self, let message = message {
                let message = message
                let toIndex = MessageIndex(message)
                let requestCount = strongSelf.perPageCount()
                
                DispatchQueue.main.async { [weak strongSelf] in
                    strongSelf?.pendingLocation = nil
                    strongSelf?.location.set(.Scroll(index: .message(toIndex), anchorIndex: .message(toIndex), sourceIndex: .message(toIndex), scrollPosition: .top(id: MessageIndex(message), innerId: nil, animated: true, focus: .init(focus: true), inset: 0), count: requestCount, animated: true))
                }
            }
        })
    }
    
    public var mediaSearchValue:Signal<MediaSearchState, NoError> {
        return mediaSearchState.get()
    }
    private var isSearch: Bool = false {
        didSet {
            if isSearch {
                searchState.set(.single(.init(state: .Focus, request: nil)))
            } else {
                searchState.set(.single(.init(state: .None, request: nil)))
            }
        }
    }
    
    public override func findGroupStableId(for stableId: AnyHashable) -> AnyHashable? {
        var updatedStableId: AnyHashable?
        if let stableId = stableId.base as? MessageIndex {
            self.genericView.enumerateItems(with: { item in
                if let item = item as? PeerPhotosMonthItem {
                    if item.items.contains(where: { $0.id == stableId.id }) {
                        updatedStableId = item.stableId
                        return false
                    }
                }
                return true
            })
        }
        return updatedStableId
    }
    
    public var onTheTop: Bool {
        return self.isTopHistory?() ?? true
    }
    
    public func toggleSearch() {
        let old = self.isSearch
        self.isSearch = !old
    }
    
    deinit {
        disposable.dispose()
        historyDisposable.dispose()
        _ = previous.swap([])
    }
    
}
