import Cocoa
import TGUIKit
import TelegramCore
import SwiftSignalKit
import Postbox
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import GeneralRows
import InputDataUI
import AppAnalytics


private final class Arguments {
    let context: any AccountContextProtocol
    let retry: () -> Void
    let toggleSelected:(StoryId)->Void
    init(context: any AccountContextProtocol, retry: @escaping () -> Void, toggleSelected:@escaping(StoryId)->Void) {
        self.context = context
        self.retry = retry
        self.toggleSelected = toggleSelected
    }
}


private struct State : Equatable {
    var folderId: Int64
    var peerId: PeerId
    var listState: PeerStoryListContext.State?
    var albumState: PeerStoryListContext.State?
    var perRowCount: Int = 3
    var desiredMembership: [Int32: Bool] = [:]
    var selectionOrder: [Int32] = []
    var isSubmitted = false
    var isClosed = false

    var isReady: Bool {
        guard folderId > 0, Int32(exactly: folderId) != nil, let listState, let albumState else { return false }
        return !listState.isCached && !albumState.isCached && albumState.loadMoreToken == nil
            && listState.peerReference?.id == peerId && albumState.peerReference?.id == peerId
    }

    func isMember(_ id: Int32) -> Bool {
        return self.albumState?.items.contains(where: { $0.id.peerId == peerId && $0.id.id == id }) == true
    }

    func selected(_ story: EngineStoryItem) -> Bool {
        return self.desiredMembership[story.id] ?? self.isMember(story.id)
    }

    var selectedCount: Int {
        var count = max(0, self.albumState?.totalCount ?? 0)
        for (id, selected) in self.desiredMembership {
            let member = self.isMember(id)
            if selected && !member { count += 1 }
            if !selected && member { count -= 1 }
        }
        return max(0, count)
    }

    mutating func toggle(_ storyId: StoryId, limit: Int) -> Bool {
        guard self.isReady, !self.isSubmitted, !self.isClosed, storyId.peerId == self.peerId,
              let story = self.listState?.items.first(where: { $0.id == storyId })?.storyItem,
              story.id == storyId.id, story.id > 0, !story.isPending else { return false }
        let selected = !self.selected(story)
        if selected && self.selectedCount >= max(0, limit) { return true }
        self.desiredMembership[story.id] = selected
        if !self.selectionOrder.contains(story.id) { self.selectionOrder.append(story.id) }
        return false
    }

    private func currentStory(_ id: Int32) -> EngineStoryItem? {
        return self.listState?.items.first(where: { $0.id.peerId == peerId && $0.id.id == id })?.storyItem
            ?? self.albumState?.items.first(where: { $0.id.peerId == peerId && $0.id.id == id })?.storyItem
    }

    var needsSelectionPage: Bool {
        guard self.isReady, self.listState?.loadMoreToken != nil else { return false }
        return self.selectionOrder.contains(where: { id in
            self.desiredMembership[id] != self.isMember(id) && self.currentStory(id) == nil
        })
    }

    mutating func reconcileSelection() {
        guard self.isReady else { return }
        self.selectionOrder = self.selectionOrder.filter { id in
            if let story = self.currentStory(id) {
                return story.id == id && story.id > 0 && !story.isPending
            }
            return self.listState?.loadMoreToken != nil
        }
        let retainedIds = Set(self.selectionOrder)
        self.desiredMembership = self.desiredMembership.filter { retainedIds.contains($0.key) }
    }

    func changes() -> (added: [EngineStoryItem], removed: [EngineStoryItem])? {
        guard self.isReady, !self.isSubmitted, !self.isClosed else { return nil }
        var added: [EngineStoryItem] = []
        var removed: [EngineStoryItem] = []
        for id in self.selectionOrder {
            guard let selected = self.desiredMembership[id], selected != self.isMember(id) else { continue }
            guard let story = self.currentStory(id), story.id == id, story.id > 0, !story.isPending else { return nil }
            if selected { added.append(story) } else { removed.append(story) }
        }
        return (added, removed)
    }
}


private func _id_row(_ i: Int) -> InputDataIdentifier {
    return .init("_id_row_\(i)")
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    
    guard state.isReady else {
        if state.listState == nil || state.albumState == nil || state.listState?.isLoading == true || state.albumState?.isLoading == true {
            return [.loading]
        }
        return [.general(sectionId: 0, index: 0, value: .none, error: nil, identifier: InputDataIdentifier("retry"), data: .init(name: strings().loginConnectionErrorTryAgain, color: theme.colors.accent, type: .none, viewType: .singleItem, action: arguments.retry))]
    }
    var entries:[InputDataEntry] = []
    
    let sectionId:Int32 = 0
    let index: Int32 = 0
    
//    entries.append(.sectionId(sectionId, type: .normal))
//    sectionId += 1
  
    if let listState = state.listState, let peerReference = listState.peerReference {
        let chunks = listState.items.chunks(state.perRowCount)
        struct Tuple : Equatable {
            var chunk: [PeerStoryListContext.State.Item]
            var viewType: GeneralViewType
            var perRowCount: Int
            var selected: Set<StoryId>
        }
        var tuples: [Tuple] = []
        
        for (i, chunk) in chunks.enumerated() {
            let viewType: GeneralViewType = .modern(position: bestGeneralViewType(chunks, for: i).position, insets: NSEdgeInsetsMake(0, 0, 0, 0))

            tuples.append(.init(chunk: chunk, viewType: viewType, perRowCount: state.perRowCount, selected: Set(chunk.compactMap { value in
                if state.selected(value.storyItem) {
                    return value.id
                } else {
                    return nil
                }
            })))
        }
        for (i, tuple) in tuples.enumerated() {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_row(i), equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
                return StoryMonthRowItem(initialSize, stableId: stableId, context: arguments.context, standalone: true, peerId: peerReference.id, peerReference: peerReference, items: tuple.chunk, selected: tuple.selected, pinnedIds: [], rowCount: tuple.perRowCount, viewType: tuple.viewType, openStory: { _ in }, toggleSelected: arguments.toggleSelected, menuItems: { story in
                    return []
                })
            }))
        }
        
    }
    
    // entries
//    
//    entries.append(.sectionId(sectionId, type: .normal))
//    sectionId += 1
    
    return entries
    
   
}

public func SelectStoryModalController(context: any AccountContextProtocol, folderId: Int64, peerId: PeerId, listContext: PeerStoryListContext?, albumContext: PeerStoryListContext? = nil, callback: @escaping([EngineStoryItem], [EngineStoryItem])->Void) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let initialState = State(folderId: folderId, peerId: peerId)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    let listContext = listContext ?? PeerStoryListContext(account: context.account, peerId: peerId, isArchived: false, folderId: nil)
    
    let albumContext = albumContext ?? PeerStoryListContext(account: context.account, peerId: peerId, isArchived: false, folderId: folderId)
    var albumRequestedTokens = Set<AnyHashable>()
    var albumWasCached = true
    var listRequestedTokens = Set<AnyHashable>()
    var listWasCached = true

    var getController:(()->ViewController?)? = nil
    var close:(()->Void)? = nil
    
    var window:Window {
        get {
            return bestWindow(context, getController?())
        }
    }
    
    let loadSelectionPage: () -> Void = { [weak listContext] in
        let state = stateValue.with { $0 }
        if !state.isClosed, !state.isSubmitted, state.needsSelectionPage, state.listState?.isLoading == false,
           let token = state.listState?.loadMoreToken, listRequestedTokens.insert(token).inserted {
            listContext?.loadMore()
        }
    }

    actionsDisposable.add((listContext.state |> deliverOnMainQueue).start(next: { listState in
        guard !stateValue.with({ $0.isClosed || $0.isSubmitted }) else { return }
        if listState.isCached && !listWasCached { listRequestedTokens.removeAll() }
        listWasCached = listState.isCached
        updateState { current in
            var current = current
            current.listState = listState
            current.reconcileSelection()
            return current
        }
        loadSelectionPage()
    }))
    
    actionsDisposable.add((albumContext.state |> deliverOnMainQueue).start(next: { [weak albumContext] albumState in
        guard !stateValue.with({ $0.isClosed || $0.isSubmitted }) else { return }
        if albumState.isCached && !albumWasCached { albumRequestedTokens.removeAll() }
        albumWasCached = albumState.isCached
        updateState { current in
            var current = current
            current.albumState = albumState
            current.reconcileSelection()
            return current
        }
        if !stateValue.with({ $0.isClosed || $0.isSubmitted || $0.albumState != albumState }), !albumState.isCached, !albumState.isLoading,
           let token = albumState.loadMoreToken, albumRequestedTokens.insert(token).inserted {
            albumContext?.loadMore()
        }
        loadSelectionPage()
    }))

    let limit = max(0, Int(context.appConfiguration.getGeneralValue("stories_album_stories_limit", orElse: 1000)))
    let arguments = Arguments(context: context, retry: { [weak listContext, weak albumContext] in
        let state = stateValue.with { $0 }
        guard !state.isClosed, !state.isSubmitted else { return }
        if state.listState?.isCached != false || state.needsSelectionPage, state.listState?.isLoading != true {
            if let token = state.listState?.loadMoreToken { listRequestedTokens.insert(token) }
            listContext?.loadMore()
        }
        let current = stateValue.with { $0 }
        if !current.isClosed, !current.isSubmitted, let albumState = current.albumState, !albumState.isLoading, let token = albumState.loadMoreToken {
            albumRequestedTokens.insert(token)
            albumContext?.loadMore()
        }
    }, toggleSelected: { storyId in
        var failedToAdd = false
        updateState { current in
            var current = current
            failedToAdd = current.toggle(storyId, limit: limit)
            return current
        }
        if failedToAdd { showModalText(for: window, text: strings().selectStoryLimitReached) }
    })

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    let controller = InputDataController(
        dataSignal: signal,
        title: strings().selectStoryTitle
    )
    controller.analyticsScreen = .storiesAlbumPicker

    
    getController = { [weak controller] in
        return controller
    }
    
    controller.validateData = { _ in
        let state = stateValue.with { $0 }
        guard !state.isClosed, !state.isSubmitted else { return .fail(.none) }
        guard let changes = state.changes() else {
            arguments.retry()
            return .fail(.none)
        }
        guard changes.added.isEmpty || state.selectedCount <= limit else {
            showModalText(for: window, text: strings().selectStoryLimitReached)
            return .fail(.none)
        }
        updateState { current in
            var current = current
            current.isSubmitted = true
            return current
        }
        guard !stateValue.with({ $0.isClosed }) else { return .fail(.none) }
        callback(changes.added, changes.removed)
        close?()
        return .none
    }

    controller.afterDisappear = { [weak controller] in
        updateState { current in
            var current = current
            current.isClosed = true
            return current
        }
        actionsDisposable.dispose()
        controller?.contextObject = nil
    }
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    let modalInteractions = ModalInteractions(
        acceptTitle: strings().selectStoryAccept,
        accept: { [weak controller] in
            _ = controller?.returnKeyAction()
        },
        inset: 10,
        singleButton: true
    )

    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(380, 0))
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    controller.contextObject = (listContext, albumContext)
    
    
    controller.didLoad = { [weak listContext] controller, _ in
        controller.tableView.setScrollHandler { position in
            switch position.direction {
            case .bottom:
                if !stateValue.with({ $0.isClosed || $0.isSubmitted }) { listContext?.loadMore() }
            default:
                break
            }
        }
    }
    
    close = { [weak modalController] in
        modalController?.close()
    }
    
    return modalController
}



