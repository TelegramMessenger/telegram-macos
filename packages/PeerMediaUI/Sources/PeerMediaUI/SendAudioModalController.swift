import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import InAppSettings
import ColorPalette
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import TelegramMediaUtils
import ChatModeTypes
import ChatHistoryModel
import ChatUI
import GeneralRows
import InputDataUI
import LocalAnimations
import AudioPlayerCore
import FilePanels
import InputView
import AppAnalytics

private final class SendAudioMessageIds {
    private let lock = NSLock()
    private var ids: [MediaId: Int32] = [:]

    func id(for fileId: MediaId) -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        if let id = ids[fileId] {
            return id
        }
        let id = Int32(ids.count) + 1
        ids[fileId] = id
        return id
    }
}

private final class SendAudioArguments {
    let context: any AccountContextProtocol
    let chatInteraction: ChatInteraction
    let playAudio: (Message) -> Void
    let sendAudio: (Message) -> Void
    let selectFromFiles: () -> Void
    let searchInteractions: SearchInteractions
    init(context: any AccountContextProtocol, chatInteraction: ChatInteraction, playAudio: @escaping(Message) -> Void, sendAudio: @escaping(Message) -> Void, selectFromFiles: @escaping() -> Void, searchInteractions: SearchInteractions) {
        self.context = context
        self.chatInteraction = chatInteraction
        self.playAudio = playAudio
        self.sendAudio = sendAudio
        self.selectFromFiles = selectFromFiles
        self.searchInteractions = searchInteractions
    }
}

private struct SendAudioState: Equatable {
    var savedMusic: [Message] = []
    var sharedAudio: [Message] = []
    var searchQuery: String = ""
    var searchResults: [Message]?
    var isSearching: Bool = false
    var savedMusicLoaded: Bool = false
    var sharedAudioLoaded: Bool = false
    var showSearch: Bool = false
}

private let _id_select_from_files = InputDataIdentifier("_id_select_from_files")
private let _id_search_row = InputDataIdentifier("_id_search_row")
private let _id_loading = InputDataIdentifier("_id_loading")
private let _id_empty = InputDataIdentifier("_id_empty")

private func _id_saved(_ message: Message) -> InputDataIdentifier {
    return InputDataIdentifier("saved_\(message.id.namespace)_\(message.id.id)_\(message.id.peerId.toInt64())")
}
private func _id_shared(_ message: Message) -> InputDataIdentifier {
    return InputDataIdentifier("shared_\(message.id.namespace)_\(message.id.id)_\(message.id.peerId.toInt64())")
}
private func _id_search(_ message: Message) -> InputDataIdentifier {
    return InputDataIdentifier("search_\(message.id.namespace)_\(message.id.id)_\(message.id.peerId.toInt64())")
}

private func audioViewType(_ array: [Message], for index: Int) -> GeneralViewType {
    return bestGeneralViewType(array, for: index)
}

private final class AudioSearchRowItem: GeneralRowItem {
    fileprivate let searchInteractions: SearchInteractions
    fileprivate let isLoading: Bool
    init(_ initialSize: NSSize, stableId: AnyHashable, searchInteractions: SearchInteractions, isLoading: Bool = false) {
        self.searchInteractions = searchInteractions
        self.isLoading = isLoading
        super.init(initialSize, stableId: stableId)
    }
    override var height: CGFloat {
        return 40 + 20
    }
    override func viewClass() -> AnyClass {
        return AudioSearchRowView.self
    }

    override var accessibilityLabel: String? {
        return strings().voiceOverCommonSearch
    }
}

private final class AudioSearchRowView: TableRowView {
    private let searchView: SearchView
    required init(frame frameRect: NSRect) {
        searchView = SearchView(frame: NSMakeRect(20, 5, frameRect.width - 40, 40))
        searchView.layer?.cornerRadius = 20
        super.init(frame: frameRect)
        addSubview(searchView)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    override var backdorColor: NSColor {
        return .clear
    }
    override func layout() {
        super.layout()
        searchView.setFrameSize(NSMakeSize(frame.width - 40, 40))
        searchView.setFrameOrigin(NSMakePoint(20, 0))
    }
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        if let item = item as? AudioSearchRowItem {
            searchView.isLoading = item.isLoading
            searchView.searchTheme = SearchTheme(theme.colors.background, theme.search.searchImage, theme.search.clearImage, theme.search.placeholder, theme.search.textColor, theme.search.placeholderColor)
            searchView.searchInteractions = SearchInteractions({ [weak self] state, animated in
                if let item = self?.item as? AudioSearchRowItem {
                    item.searchInteractions.stateModified(state, animated)
                }
            }, { [weak self] state in
                if let item = self?.item as? AudioSearchRowItem {
                    item.searchInteractions.textModified(state)
                }
            })
        }
    }
    override var firstResponder: NSResponder? {
        return searchView.input
    }
}

private func entries(_ state: SendAudioState, arguments: SendAudioArguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    let s_search: Int32 = 0
    let s_files: Int32 = 1
    let s_saved: Int32 = 2
    let s_shared: Int32 = 3
    let s_results: Int32 = 4
    let s_final: Int32 = 5

    let i_search: Int32 = 0
    let i_select_files: Int32 = 100
    let i_saved_header: Int32 = 200
    var i_saved: Int32 = 201
    let i_shared_header: Int32 = 500
    var i_shared: Int32 = 501
    let i_loading: Int32 = 900
    var i_result: Int32 = 1000

    entries.append(.sectionId(s_search, type: .customModern(10)))

    if state.showSearch {
        entries.append(.custom(sectionId: s_search, index: i_search, value: .none, identifier: _id_search_row, equatable: .init(state.isSearching), comparable: nil, item: { initialSize, stableId in
            return AudioSearchRowItem(initialSize, stableId: stableId, searchInteractions: arguments.searchInteractions, isLoading: state.isSearching)
        }))
    }

    if state.searchQuery.isEmpty {
        entries.append(.general(sectionId: s_files, index: i_select_files, value: .none, error: nil, identifier: _id_select_from_files, data: InputDataGeneralData(name: strings().sendAudioSelectFromFiles, color: theme.colors.accent, type: .none, viewType: .singleItem, action: {
            arguments.selectFromFiles()
        })))

        if !state.savedMusic.isEmpty {
            entries.append(.sectionId(s_saved, type: .normal))

            entries.append(.desc(sectionId: s_saved, index: i_saved_header, text: .plain(strings().sendAudioSavedMusic), data: InputDataGeneralTextData(detectBold: false, viewType: .textTopItem)))

            for (i, message) in state.savedMusic.enumerated() {
                let viewType = audioViewType(state.savedMusic, for: i)
                entries.append(.custom(sectionId: s_saved, index: i_saved, value: .none, identifier: _id_saved(message), equatable: nil, comparable: nil, item: { initialSize, stableId in
                    return PeerMediaMusicRowItem(initialSize, arguments.chatInteraction, .messageEntry(message, [], .defaultSettings, viewType), music: { message, _ in
                        arguments.playAudio(message)
                    }, send: { message in
                        arguments.sendAudio(message)
                    }, viewType: viewType, contextMenuItems: { message in
                        return [ContextMenuItem(strings().sendAudioSend, handler: {
                            arguments.sendAudio(message)
                        }, itemImage: MenuAnimation.menu_send_now.value)]
                    }, inModal: true)
                }))
                i_saved += 1
            }
        }

        if !state.sharedAudio.isEmpty {
            entries.append(.sectionId(s_shared, type: .normal))

            entries.append(.desc(sectionId: s_shared, index: i_shared_header, text: .plain(strings().sendAudioSharedAudio), data: InputDataGeneralTextData(detectBold: false, viewType: .textTopItem)))

            for (i, message) in state.sharedAudio.enumerated() {
                let viewType = audioViewType(state.sharedAudio, for: i)
                entries.append(.custom(sectionId: s_shared, index: i_shared, value: .none, identifier: _id_shared(message), equatable: nil, comparable: nil, item: { initialSize, stableId in
                    return PeerMediaMusicRowItem(initialSize, arguments.chatInteraction, .messageEntry(message, [], .defaultSettings, viewType), music: { message, _ in
                        arguments.playAudio(message)
                    }, send: { message in
                        arguments.sendAudio(message)
                    }, viewType: viewType, contextMenuItems: { message in
                        return [ContextMenuItem(strings().sendAudioSend, handler: {
                            arguments.sendAudio(message)
                        }, itemImage: MenuAnimation.menu_send_now.value)]
                    }, inModal: true)
                }))
                i_shared += 1
            }
        }

        if !state.savedMusicLoaded || !state.sharedAudioLoaded {
            if state.sharedAudio.isEmpty {
                entries.append(.sectionId(s_shared, type: .normal))
            }
            entries.append(.custom(sectionId: s_shared, index: i_loading, value: .none, identifier: _id_loading, equatable: nil, comparable: nil, item: { initialSize, stableId in
                return GeneralLoadingRowItem(initialSize, stableId: stableId, viewType: .singleItem)
            }))
        }
    } else {
        entries.append(.sectionId(s_results, type: .normal))

        if let results = state.searchResults, !results.isEmpty {
                for (i, message) in results.enumerated() {
                    let viewType = audioViewType(results, for: i)
                    entries.append(.custom(sectionId: s_results, index: i_result, value: .none, identifier: _id_search(message), equatable: nil, comparable: nil, item: { initialSize, stableId in
                        return PeerMediaMusicRowItem(initialSize, arguments.chatInteraction, .messageEntry(message, [], .defaultSettings, viewType), music: { message, _ in
                            arguments.playAudio(message)
                        }, send: { message in
                            arguments.sendAudio(message)
                        }, viewType: viewType, contextMenuItems: { message in
                            return [ContextMenuItem(strings().sendAudioSend, handler: {
                                arguments.sendAudio(message)
                            }, itemImage: MenuAnimation.menu_send_now.value)]
                        }, inModal: true)
                    }))
                    i_result += 1
                }
            }
        }
    
    entries.append(.sectionId(s_final, type: .normal))

    return entries
}

public func SendAudioModalController(context: any AccountContextProtocol, chatInteraction: ChatInteraction) -> InputDataModalController {

    let actionsDisposable = DisposableSet()
    let messageIds = SendAudioMessageIds()
    let sharedAudioLoadMore = ValuePipe<Void>()
    let searchLoadMore = ValuePipe<Void>()

    let initialState = SendAudioState()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((SendAudioState) -> SendAudioState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var close: (() -> Void)? = nil
    var getController: (() -> InputDataController?)? = nil

    let arguments = SendAudioArguments(context: context, chatInteraction: chatInteraction, playAudio: { message in
        if let file = message.media.first as? TelegramMediaFile {
            let controller = PeerMediaUIHooks.shared.getAudioPlayer(context)
            if let controller = controller, controller.currentSong?.resource.id == file.resource.id {
                _ = controller.playOrPause()
            } else {
                let musicText = file.musicText
                let wrapper = APSingleWrapper(resource: file.resource, name: musicText.0, performer: musicText.1, duration: file.duration, id: file.fileId)
                let player = APSingleResourceController(context: context, wrapper: wrapper, streamable: true)
                PeerMediaUIHooks.shared.showInlineAudioPlayer(player, context, getController?()?.tableView, nil)
                player.start()
            }
        }
    }, sendAudio: { message in
        if let file = message.media.first as? TelegramMediaFile {
            chatInteraction.sendMedias([file], ChatTextInputState(), false, nil, false, nil, false, nil, false)
            close?()
        }
    }, selectFromFiles: {
        filePanel(with: ["mp3", "m4a", "aac", "flac", "ogg", "wav", "opus"], allowMultiple: true, for: context.window, completion: { paths in
            if let paths = paths {
                chatInteraction.showPreviewSender(paths.map { URL(fileURLWithPath: $0) }, true, nil)
                close?()
            }
        })
    }, searchInteractions: SearchInteractions({ state, _ in
        updateState { current in
            var current = current
            if state.state == .None {
                current.showSearch = false
                current.searchQuery = ""
                current.searchResults = nil
                current.isSearching = false
            }
            return current
        }
    }, { state in
        let query = state.request
        updateState { current in
            var current = current
            current.searchQuery = query
            current.isSearching = !query.isEmpty
            if query.isEmpty {
                current.searchResults = nil
            }
            return current
        }
    }))

    let savedMusicContext = ProfileSavedMusicContext(account: context.account, peerId: context.account.peerId)
    actionsDisposable.add((savedMusicContext.state |> deliverOnMainQueue).start(next: { state in
        let messages: [Message] = state.files.compactMap { file in
            let messageId = MessageId(peerId: context.account.peerId, namespace: Namespaces.Message.Local, id: messageIds.id(for: file.fileId))
            return Message(stableId: UInt32(abs(messageId.id)), stableVersion: 0, id: messageId, globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0, flags: [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: nil, text: "", attributes: [], media: [file], peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
        }
        updateState { current in
            var current = current
            current.savedMusic = messages
            switch state.dataState {
            case .loading:
                current.savedMusicLoaded = false
            case .ready:
                current.savedMusicLoaded = true
            }
            return current
        }
    }))

    let sharedAudioSignal = peerMediaSearchMessages(loadMore: sharedAudioLoadMore.signal(), request: { state in
        context.engine.messages.searchMessages(location: .general(scope: .everywhere, groupId: nil, tags: [.music], minDate: nil, maxDate: nil, folderId: nil, communityId: nil), query: "", state: state)
    })
    actionsDisposable.add((sharedAudioSignal |> deliverOnMainQueue).start(next: { messages in
        updateState { current in
            var current = current
            if let messages {
                current.sharedAudio = messages
            }
            current.sharedAudioLoaded = messages != nil
            return current
        }
    }))

    let searchDisposable = MetaDisposable()
    actionsDisposable.add(searchDisposable)

    actionsDisposable.add((statePromise.get() |> map { $0.searchQuery } |> distinctUntilChanged |> deliverOnMainQueue).start(next: { query in
        if !query.isEmpty {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

            let sharedSearch: Signal<[Message], NoError> = peerMediaSearchMessages(loadMore: searchLoadMore.signal(), request: { state in
                context.engine.messages.searchMessages(location: .general(scope: .everywhere, groupId: nil, tags: [.music], minDate: nil, maxDate: nil, folderId: nil, communityId: nil), query: trimmedQuery, state: state)
            }) |> filter { $0 != nil } |> map { $0 ?? [] }

            let botSearch: Signal<[Message], NoError>
            if let data = context.appConfiguration.data, let searchBot = data["music_search_username"] as? String, !searchBot.isEmpty, trimmedQuery.count >= 3 {
                botSearch = context.engine.peers.resolvePeerByName(name: searchBot, referrer: nil)
                |> mapToSignal { result -> Signal<EnginePeer?, NoError> in
                    guard case let .result(result) = result else {
                        return .complete()
                    }
                    return .single(result)
                }
                |> mapToSignal { peer -> Signal<[ChatContextResult], NoError> in
                    guard let peer = peer else {
                        return .single([])
                    }
                    return sendAudioBotSearchResults(loadMore: searchLoadMore.signal(), request: { offset in
                        context.engine.messages.requestChatContextResults(botId: peer.id, peerId: context.account.peerId, query: trimmedQuery, offset: offset)
                        |> map { $0?.results }
                        |> `catch` { _ -> Signal<ChatContextResultCollection?, NoError> in
                            return .single(nil)
                        }
                    })
                }
                |> map { results -> [Message] in
                    let peerId = context.account.peerId
                    var messages: [Message] = []
                    let peers = SimpleDictionary<PeerId, Peer>()
                    for result in results {
                        switch result {
                        case let .internalReference(internalReference):
                            if let file = internalReference.file {
                                let messageId = MessageId(peerId: peerId, namespace: Namespaces.Message.Local, id: messageIds.id(for: file.fileId))
                                let stableId = UInt32(messageId.id)
                                messages.append(Message(stableId: stableId, stableVersion: 0, id: messageId, globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0, flags: [], tags: [.music], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: nil, text: "", attributes: [], media: [file], peers: peers, associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:]))
                            }
                        default:
                            break
                        }
                    }
                    return messages
                }
            } else {
                botSearch = .single([])
            }

            let combined = combineLatest(sharedSearch, botSearch)
            |> deliverOnMainQueue
            searchDisposable.set(combined.start(next: { shared, bot in
                updateState { current in
                    var current = current
                    var allMessages = shared
                    var existingIds = Set(allMessages.map { $0.id })
                    for msg in bot {
                        if existingIds.insert(msg.id).inserted {
                            allMessages.append(msg)
                        }
                    }
                    current.searchResults = allMessages
                    current.isSearching = false
                    return current
                }
            }))
        } else {
            searchDisposable.set(nil)
        }
    }))

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().sendAudioTitle)
    controller.analyticsScreen = .chatAttachAudio

    getController = { [weak controller] in controller }

    controller.didLoad = { controller, _ in
        controller.tableView.setScrollHandler { [weak savedMusicContext] scroll in
            guard scroll.direction == .bottom else {
                return
            }
            if stateValue.with({ $0.searchQuery.isEmpty }) {
                savedMusicContext?.loadMore()
                sharedAudioLoadMore.putNext(())
            } else {
                searchLoadMore.putNext(())
            }
        }
    }

    var progressOverlay: ProgressIndicator? = nil
    var emptyOverlay: MediaAnimatedStickerView? = nil

    controller.afterTransaction = { controller in
        let state = stateValue.with { $0 }
        let showProgress = !state.searchQuery.isEmpty && state.isSearching
        let searchEmpty = !state.searchQuery.isEmpty && !state.isSearching && (state.searchResults?.isEmpty == true)
        let contentEmpty = state.searchQuery.isEmpty && state.savedMusicLoaded && state.sharedAudioLoaded && state.savedMusic.isEmpty && state.sharedAudio.isEmpty
        let showEmpty = searchEmpty || contentEmpty

        if showProgress {
            if progressOverlay == nil {
                let indicator = ProgressIndicator(frame: NSMakeRect(0, 0, 30, 30))
                indicator.animates = true
                indicator.progressColor = theme.colors.text
                controller.tableView.addSubview(indicator)
                progressOverlay = indicator
            }
            progressOverlay?.center()
        } else {
            progressOverlay?.removeFromSuperview()
            progressOverlay = nil
        }

        if showEmpty {
            if emptyOverlay == nil {
                let sticker = LocalAnimatedSticker.duck_empty
                let stickerSize = NSMakeSize(100, 100)
                let view = MediaAnimatedStickerView(frame: NSMakeRect(0, 0, stickerSize.width, stickerSize.height))
                view.update(with: sticker.file, size: stickerSize, context: context, parent: nil, table: nil, parameters: sticker.parameters, animated: false, positionFlags: nil, approximateSynchronousValue: false)
                controller.tableView.addSubview(view)
                emptyOverlay = view
            }
            emptyOverlay?.center()
        } else {
            emptyOverlay?.removeFromSuperview()
            emptyOverlay = nil
        }
    }

    controller.onDeinit = {
        actionsDisposable.dispose()
        _ = savedMusicContext
        _ = progressOverlay
        _ = emptyOverlay
    }

    let modalController = InputDataModalController(controller, modalInteractions: nil)
    modalController.fixedHeight = 500

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })

    let searchIcon = TelegramThemeHooks.shared.image(.iconTouchBarSearch).precomposed(theme.colors.accentIcon)
    controller.rightModalHeader = ModalHeaderData(image: searchIcon, handler: { [weak controller] in
        let willShow = !stateValue.with({ $0.showSearch })
        updateState { current in
            var current = current
            current.showSearch = !current.showSearch
            if !current.showSearch {
                current.searchQuery = ""
                current.searchResults = nil
                current.isSearching = false
            }
            return current
        }
        if willShow {
            delay(0.1, closure: {
                if let view = controller?.tableView.item(stableId: InputDataEntryId.custom(_id_search_row))?.view as? AudioSearchRowView {
                    _ = view.window?.makeFirstResponder(view.firstResponder)
                }
            })
        }
    })

    close = { [weak modalController] in
        modalController?.modal?.close()
    }

    return modalController
}
