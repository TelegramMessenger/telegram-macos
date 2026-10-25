import Cocoa
import TGUIKit
import TelegramCore
import InAppSettings
import Postbox
import SwiftSignalKit
import AudioPlayerCore
import ChatHistoryModel
import ChatModeTypes
import ChatUI
import GalleryUI
import GeneralRows
import MessageUtils
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils

public enum PeerMediaSharedEntryStableId : Hashable {
    case messageId(MessageId)
    case search
    case emptySearch
    case date(MessageIndex)
    case sectionId(MessageIndex)
}

//private func bestGeneralViewType(_ array:[PeerMediaSharedEntry], for item: PeerMediaSharedEntry) -> GeneralViewType {
//    for _ in array {
//        if item == array.first && item == array.last {
//            return .modern(position: .single, insets: NSEdgeInsetsMake(7, 7, 7, 12))
//        } else if item == array.first {
//            return .modern(position: .first, insets: NSEdgeInsetsMake(7, 7, 7, 12))
//        } else if item == array.last {
//            return .modern(position: .last, insets: NSEdgeInsetsMake(7, 7, 7, 12))
//        } else {
//            return .modern(position: .inner, insets: NSEdgeInsetsMake(7, 7, 7, 12))
//        }
//    }
//    return .modern(position: .single, insets: NSEdgeInsetsMake(6, 6, 6, 12))
//}

public enum PeerMediaSharedEntry : Comparable, Identifiable {
    case messageEntry(Message, [Message], AutomaticMediaDownloadSettings, GeneralViewType)
    case emptySearchEntry(Bool)
    case date(MessageIndex)
    case sectionId(MessageIndex)
    public var stableId: AnyHashable {
        switch self {
        case let .messageEntry(message, _, _, _):
            return PeerMediaSharedEntryStableId.messageId(message.id)
        case let .date(index):
            return PeerMediaSharedEntryStableId.date(index)
        case let .sectionId(index):
            return PeerMediaSharedEntryStableId.sectionId(index)
        case .emptySearchEntry:
            return PeerMediaSharedEntryStableId.emptySearch
        }
    }
    
    public var index: MessageIndex {
        switch self {
        case let .date(index):
            return index
        case let .sectionId(index):
            return index
        case let .messageEntry(message, _, _, _):
            return MessageIndex(message).peerLocalPredecessor()
        case .emptySearchEntry:
            return MessageIndex.absoluteLowerBound()
        }
    }
    
    public var message:Message? {
        switch self {
        case let .messageEntry(message, _, _, _):
            return message
        default:
            return nil
        }
    }
}

public func <(lhs:PeerMediaSharedEntry, rhs: PeerMediaSharedEntry) -> Bool {
    return lhs.index < rhs.index
}


public func convertEntries(from update: PeerMediaUpdate, tags: MessageTags, timeDifference: TimeInterval, isExternalSearch: Bool) -> [PeerMediaSharedEntry] {
    var converted:[PeerMediaSharedEntry] = []
   
    
    struct Item {
        let date: PeerMediaSharedEntry
        let section: PeerMediaSharedEntry
        let items:[PeerMediaSharedEntry]
        init(_ date: PeerMediaSharedEntry, _ section: PeerMediaSharedEntry, _ items: [PeerMediaSharedEntry]) {
            self.date = date
            self.section = section
            self.items = items.sorted(by: >)
        }
    }
    
    
    var tempItems:[(PeerMediaSharedEntry, PeerMediaSharedEntry?)] = []

    // Rich messages carry their medias in an instant page; expand each into one synthetic message per
    // matching media so every file/track/etc. becomes its own row.
    let messages = expandSharedMediaMessages(update.messages, where: sharedMediaPredicate(for: tags))

    for i in 0 ..< messages.count {

        let message = messages[i]

        let next = i < messages.count - 1 ? messages[i + 1] : nil
        

        
        if let nextMessage = next {
            
            let timestamp = Int32(min(TimeInterval(message.timestamp) - timeDifference, TimeInterval(Int32.max)))
            let nextTimestamp = Int32(min(TimeInterval(nextMessage.timestamp) - timeDifference, TimeInterval(Int32.max)))

            
            let dateId = mediaDateId(for: timestamp)
            let nextDateId = mediaDateId(for: nextTimestamp)
            if dateId != nextDateId {
                let index = MessageIndex(id: message.id, timestamp: Int32(dateId))
                tempItems.append((.date(index), .sectionId(index.peerLocalSuccessor())))
            }
        } else {
            let timestamp = Int32(min(TimeInterval(message.timestamp) - timeDifference, TimeInterval(Int32.max)))
            let dateId = mediaDateId(for: timestamp)
            let index = MessageIndex(id: message.id, timestamp: Int32(dateId))
            tempItems.append((.date(index), .sectionId(index.peerLocalSuccessor())))
        }
        tempItems.append((.messageEntry(message, isExternalSearch ? update.messages : [], update.automaticDownload, .singleItem), nil))

    }
    
    
    var groupItems:[Item] = []
    var current:[PeerMediaSharedEntry] = []
    for item in tempItems.sorted(by: { $0.0 < $1.0 }) {
        switch item.0 {
        case .date:
            if !current.isEmpty {
                groupItems.append(Item(item.0, item.1!, Array(current.reversed())))
                current.removeAll()
            }
        case .messageEntry:
            current.append(item.0)
        default:
            fatalError()
        }
    }
    
    if !current.isEmpty {
        if !groupItems.isEmpty {
            let item = groupItems.last!
            groupItems[groupItems.count - 1] = Item(item.date, item.section, item.items + current.reversed())
        } else {
            groupItems.append(.init(current.last!, .sectionId(current.last!.index.peerLocalSuccessor()), Array(current.reversed())))
        }
    }
    
    
    for (i, group) in groupItems.reversed().enumerated() {
        if i != 0 {
           // converted.append(group.section)
            converted.append(group.date)
        }
      
        
        for item in group.items {
            switch item {
            case let .messageEntry(message, messages, settings, _):
                var viewType = bestGeneralViewType(group.items, for: item)
                
                if i == 0, item == group.items.first {
                    if group.items.count > 1 {
                        viewType = .innerItem
                    } else {
                        viewType = .lastItem
                    }
                }
//                viewType = .modern(position: .inner, insets: NSEdgeInsetsMake(10, 10, 10, 12))

                converted.append(.messageEntry(message, messages, settings, viewType))
            default:
                fatalError()
            }
        }
    }
    
   
    
    if !tempItems.isEmpty {
        //converted.append(.sectionId(MessageIndex.absoluteLowerBound()))
    }

    if update.updateType == .search {
        if converted.isEmpty {
            converted.append(.emptySearchEntry(false))
        }
    } else if update.updateType == .loading {
        if converted.isEmpty {
            converted.append(.emptySearchEntry(true))
        }
    }
    converted = converted.sorted(by: <)

  
    
    return converted
}

private final class Arguments {
    let context: any AccountContextProtocol
    let gallery:(Message, GalleryAppearType)->Void
    let music:(Message, GalleryAppearType)->Void
    init(context: any AccountContextProtocol, gallery: @escaping(Message, GalleryAppearType) -> Void, music: @escaping(Message, GalleryAppearType)->Void) {
        self.context = context
        self.gallery = gallery
        self.music = music
    }
}

fileprivate func preparedMediaTransition(from fromView:[AppearanceWrapperEntry<PeerMediaSharedEntry>]?, to toView:[AppearanceWrapperEntry<PeerMediaSharedEntry>], arguments: Arguments, initialSize:NSSize, interaction:ChatInteraction, animated:Bool, scroll:TableScrollState, tags:MessageTags) -> TableUpdateTransition {
    let (removed,inserted,updated) = proccessEntries(fromView, right: toView, { entry -> TableRowItem in
        
        switch entry.entry {
        case let .messageEntry(message, _, _, viewType):
            let rowInset = NSEdgeInsets(left: 0, right: 0)
            if tags == .file, message.anyMedia is TelegramMediaFile {
                return PeerMediaFileRowItem(initialSize, interaction, entry.entry, gallery: arguments.gallery, viewType: viewType, inset: rowInset)
            } else if tags == .webPage {
                return PeerMediaWebpageRowItem(initialSize,interaction, entry.entry, gallery: arguments.gallery, viewType: viewType, inset: rowInset)
            } else if tags == .music, message.anyMedia is TelegramMediaFile {
                return PeerMediaMusicRowItem(initialSize, interaction, entry.entry, gallery: arguments.gallery, music: arguments.music, viewType: viewType, inset: rowInset)
            } else if tags == .voiceOrInstantVideo, message.anyMedia is TelegramMediaFile {
                return PeerMediaVoiceRowItem(initialSize,interaction, entry.entry, gallery: arguments.gallery, music: arguments.music, viewType: viewType, inset: rowInset)
            } else {
                return GeneralRowItem(initialSize, height: 1, stableId: entry.stableId)
            }
        case .date(let index):
            return PeerMediaDateItem(initialSize, index: index, stableId: entry.stableId)
        case .sectionId:
            return GeneralRowItem(initialSize, height: 20, stableId: entry.stableId, viewType: .separator)
        case .emptySearchEntry:
            return SearchEmptyRowItem(initialSize, stableId: entry.stableId, isLoading: false, viewType: .separator)
        }
        
    })
    
    for item in inserted {
        _ = item.1.makeSize(initialSize.width, oldWidth: initialSize.width)
    }
    for item in updated {
        _ = item.1.makeSize(initialSize.width, oldWidth: initialSize.width)
    }
    
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated:updated, animated:animated, state:scroll)
}

public enum PeerMediaUpdateState {
    case search
    case history
    case loading
}

public struct PeerMediaUpdate {
    public let messages:[Message]
    public let updateType: PeerMediaUpdateState
    public let laterId: MessageIndex?
    public let earlierId: MessageIndex?
    public let automaticDownload: AutomaticMediaDownloadSettings
    public let searchState: SearchState
    public let contentSettings: ContentSettings
    public init (messages: [Message] = [], updateType:PeerMediaUpdateState = .loading, laterId:MessageIndex? = nil, earlierId:MessageIndex? = nil, automaticDownload: AutomaticMediaDownloadSettings = .defaultSettings, searchState: SearchState = SearchState(state: .None, request: nil), contentSettings: ContentSettings = ContentSettings.default) {
        self.messages = messages.filter { $0.restrictedText(contentSettings) == nil }
        self.updateType = updateType
        self.laterId = laterId
        self.earlierId = earlierId
        self.automaticDownload = automaticDownload
        self.searchState = searchState
        self.contentSettings = contentSettings
    }
    
    public func withUpdatedUpdatedType(_ updateType:PeerMediaUpdateState) -> PeerMediaUpdate {
        return PeerMediaUpdate(messages: self.messages, updateType: updateType, laterId: self.laterId, earlierId: self.earlierId, automaticDownload: self.automaticDownload, searchState: self.searchState, contentSettings: contentSettings)
    }
}


open class PeerMediaListController<Context: AccountContextProtocol>: TableViewController<Context>, PeerMediaSearchable {

    open override var defaultBarTitle: String {
        return localizedString("Telegram.PeerMediaListController")
    }
    
    private var peerId:PeerId
    private var chatInteraction:ChatInteraction
    private let disposable: MetaDisposable = MetaDisposable()
    private let entires = Atomic<[AppearanceWrapperEntry<PeerMediaSharedEntry>]?>(value: nil)
    private let updateView = Atomic<PeerMediaUpdate?>(value: nil)
    private let mediaSearchState:ValuePromise<MediaSearchState> = ValuePromise(ignoreRepeated: true)
    private let searchState:Promise<SearchState> = Promise()
    private let searchLoadMore = ValuePipe<Void>()
    private var isExternalSearch: Bool = false
    private let externalSearch:Promise<ExternalSearchMessages?> = Promise(nil)

    public func setSearchValue(_ value: Signal<SearchState, NoError>) {
        searchState.set(value)
    }
    
    public func setExternalSearch(_ value: Signal<ExternalSearchMessages?, NoError>, _ loadMore: @escaping () -> Void) {
        externalSearch.set(value)
        self.isExternalSearch = true
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
    public func toggleSearch() {
        let old = self.isSearch
        self.isSearch = !old
    }
    private let threadInfo: ThreadInfo?

    
    public init(context: Context, peerId: PeerId, threadInfo: ThreadInfo?, chatInteraction: ChatInteraction) {
        self.peerId = peerId
        self.threadInfo = threadInfo
        self.chatInteraction = chatInteraction
        super.init(context)
        bar = .init(height: 0)
    }
    
    
    deinit {
        disposable.dispose()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    public override func findGroupStableId(for stableId: AnyHashable) -> AnyHashable? {
        if let stableId = stableId.base as? ChatHistoryEntryId {
            switch stableId {
            case let .message(message):
                return PeerMediaSharedEntryStableId.messageId(message.id)
            default:
                break
            }
        }
        return nil
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        
        
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        genericView.stopMerge()
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        self.genericView.verticalScrollElasticity = .none

        
        genericView.getBackgroundColor = {
            .clear
        }
    }
    
    private var chatLocationInput: ChatLocationInput {
        let location: ChatLocationInput
        if let threadInfo = threadInfo {
            location = context.chatLocationInput(for: .thread(threadInfo.message), contextHolder: threadInfo.contextHolder)
        } else {
            location = .peer(peerId: peerId, threadId: nil)
        }
        return location
    }
    
    public func load(with tagMask:MessageTags) -> Void {
        if tagMask.contains(.file) {
        } else if tagMask.contains(.webPage) {
        } else if tagMask.contains(.music) {
        } else if tagMask.contains(.voiceOrInstantVideo) {
        }
     
        
        
        genericView.clipView.scroll(to: NSMakePoint(0, -genericView.contentInsets.top), animated: false)

        let isExternalSearch = self.isExternalSearch
        
        let location = ValuePromise<ChatHistoryLocation>(ignoreRepeated: true)
        searchState.set(.single(SearchState(state: .None, request: nil)))
        genericView.emptyItem = PeerMediaEmptyRowItem(atomicSize.modify {$0}, tags: tagMask)

        genericView.set(stickClass: PeerMediaDateItem.self, handler: { item in
            
        })
        
        let historyPromise: Promise<PeerMediaUpdate> = Promise()
        let context = self.context
        let peerId = self.peerId
        let threadId = self.threadInfo?.message.threadId
        
        let chatLocationInput = self.chatLocationInput
        let searchLoadMore = self.searchLoadMore.signal()

        
        let historyViewUpdate = combineLatest(location.get(), searchState.get(), externalSearch.get()) |> deliverOnMainQueue
         |> mapToSignal { [weak self] location, searchState, externalSearch -> Signal<PeerMediaUpdate, NoError> in
            if let strongSelf = self {
                if let externalSearch = externalSearch {
                    return .single(PeerMediaUpdate(messages: externalSearch.messages, updateType: .history, laterId: nil, earlierId: nil, searchState: searchState, contentSettings: context.contentSettings))
                } else if searchState.request.isEmpty {
                    return combineLatest(queue: prepareQueue, chatHistoryViewForLocation(location, context: context, chatLocation: .peer(peerId), fixedCombinedReadStates: nil, tag: .tag(tagMask), additionalData: [], chatLocationInput: chatLocationInput), automaticDownloadSettings(postbox: context.account.postbox)) |> mapToQueue { view, settings -> Signal<PeerMediaUpdate, NoError> in
                        switch view {
                        case .Loading:
                            return .single(PeerMediaUpdate())
                        case let .HistoryView(view: view, type: _, scrollPosition: _, initialData: _):
                            var messages:[Message] = []
                            for entry in view.entries {
                                messages.append(entry.message)
                            }
                            
                            let laterId = view.laterId
                            let earlierId = view.earlierId

                            return .single(PeerMediaUpdate(messages: messages, updateType: .history, laterId: laterId, earlierId: earlierId, automaticDownload: settings, searchState: searchState, contentSettings: context.contentSettings))
                        }
                    }
                } else {
                    let searchMessagesLocation: SearchMessagesLocation
                    searchMessagesLocation = .peer(peerId: peerId, fromId: nil, tags: tagMask, reactions: nil, threadId: threadId, minDate: nil, maxDate: nil)
                    
                    let update = strongSelf.updateView.modify {$0?.withUpdatedUpdatedType(.loading)} ?? PeerMediaUpdate()
                    return peerMediaSearchMessages(loadMore: searchLoadMore, request: { state in
                        context.engine.messages.searchMessages(location: searchMessagesLocation, query: searchState.request, state: state)
                    }) |> map { messages -> PeerMediaUpdate in
                        if let messages {
                            return PeerMediaUpdate(messages: messages, updateType: .search, laterId: nil, earlierId: nil, searchState: searchState, contentSettings: context.contentSettings)
                        }
                        return update
                    }
                    
                }
            }
           
            return .complete()
        }
        
        let animated:Atomic<Bool> = Atomic(value:false)
        
        let chatInteraction = self.chatInteraction
        let initialSize = self.atomicSize
        
        
        let _updateView = self.updateView
        let _entries = self.entires
        
        
        let chatLocation = chatInteraction.chatLocation
        
        let mode: ChatMode
        let contextHolder: Atomic<ChatLocationContextHolder?>
        if let threadInfo = threadInfo {
            mode = .thread(mode: .topic(origin: threadInfo.message.effectiveTopId))
            contextHolder = threadInfo.contextHolder
        } else {
            mode = .history
            contextHolder = .init(value: nil)
        }
        
        
        let arguments = Arguments(context: context, gallery: { [weak self] message, type in
            if let media = message.media.first {
                let interactions = ChatMediaLayoutParameters(presentation: .Empty, media: media)
                interactions.showMedia = { message in
                    self?.chatInteraction.focusMessageId(nil, .init(messageId: message.id, string: nil), .none(nil))
                }
                interactions.showMessage = { message in
                    self?.chatInteraction.focusMessageId(nil, .init(messageId: message.id, string: nil), .center(id: 0, innerId: nil, animated: false, focus: .init(focus: true), inset: 0))
                }
                showChatGallery(context: context, message: message, self?.genericView, interactions, type: type, chatMode: mode, chatLocation: chatLocation, contextHolder: contextHolder, cachedPeerData: self?.chatInteraction.presentation.cachedData)
            }
        }, music: { message, type in
            
            if let controller = PeerMediaUIHooks.shared.getAudioPlayer(context), controller.playOrPause(message.id) {
                return
            }
            let messages: [Message]
            switch type {
            case let .messages(value):
                messages = value
            default:
                messages = []
            }
            
            if let file = message.media.first as? TelegramMediaFile  {
                let controller: APController
                if file.isMusic {
                    controller = APChatMusicController(context: context, chatLocationInput: chatLocationInput, mode: mode, index: MessageIndex(message), baseRate: FastSettings.playingMusicRate, messages: messages)
                } else {
                    controller = APChatVoiceController(context: context, chatLocationInput: chatLocationInput, mode: mode, index: MessageIndex(message), baseRate: FastSettings.playingRate, volume: FastSettings.volumeRate)
                }
                chatInteraction.inlineAudioPlayer(controller)
                controller.start()
            }
            
        })
        
        
        let historyViewTransition = combineLatest(queue: prepareQueue,historyPromise.get(), appearanceSignal) |> map { update, appearance -> (transition: TableUpdateTransition, previousUpdate: PeerMediaUpdate?, currentUpdate: PeerMediaUpdate) in
            let animated = animated.swap(true)
            var scroll:TableScrollState = animated ? .none(nil) : .saveVisible(.upper, false)
            
            
            
            let entries = convertEntries(from: update, tags: tagMask, timeDifference: context.timeDifference, isExternalSearch: isExternalSearch).map({AppearanceWrapperEntry(entry: $0, appearance: appearance)})
            let previous = _entries.swap(entries)
            let previousUpdate = _updateView.swap(update)
            
            if previousUpdate?.searchState != update.searchState {
                scroll = .upOffset(animated, 0)
            }
            
            let transition = preparedMediaTransition(from: previous, to: entries, arguments: arguments, initialSize: initialSize.modify({$0}), interaction: chatInteraction, animated: previousUpdate?.searchState.state != update.searchState.state, scroll:scroll, tags:tagMask)
            
            return (transition: transition, previousUpdate: previousUpdate, currentUpdate: update)

        } |> deliverOnMainQueue
        
        
        disposable.set(historyViewTransition.start(next: { [weak self] values in
            guard let `self` = self else {return}
            
            let state = MediaSearchState(state: values.currentUpdate.searchState, animated: values.currentUpdate.searchState != values.previousUpdate?.searchState, isLoading: values.currentUpdate.updateType == .loading)
            self.genericView.merge(with: values.transition)
            self.mediaSearchState.set(state)
            self.readyOnce()
            if let controller = PeerMediaUIHooks.shared.getAudioPlayer(context), let header = self.navigationController?.header, header.needShown {
                let tableView = (self.navigationController?.first {$0 is ChatController<Context>} as? ChatController<Context>)?.genericView.tableView
                let object = PeerMediaUIHooks.shared.makeInlineAudioPlayerContextObject(controller, context, tableView, self.genericView)
                header.view.update(with: object)
            }
        }))
        
        historyPromise.set(historyViewUpdate)

        
        let perPageCount:()->Int = { [weak self] in
            guard let `self` = self else {
                return 0
            }
            return Int(self.frame.height / 50)
        }
        
        var requestCount: Int = perPageCount() + 5
        
        
        location.set(.Initial(count: requestCount, scrollPosition: nil))
     
        genericView.setScrollHandler { [weak self] scroll in
            switch scroll.direction {
            case .bottom:
                if self?.updateView.with({ $0?.searchState.request.isEmpty == false }) == true {
                    self?.searchLoadMore.putNext(())
                } else {
                    _ = animated.swap(false)
                    requestCount += perPageCount() * 3
                    location.set(.Initial(count: requestCount, scrollPosition: nil))
                }
            default:
                break
            }
        }
        
    }
    
    public override func navigationHeaderDidNoticeAnimation(_ current: CGFloat, _ previous: CGFloat, _ animated: Bool) -> () -> Void {
        return {
            
        }
    }
    
}

