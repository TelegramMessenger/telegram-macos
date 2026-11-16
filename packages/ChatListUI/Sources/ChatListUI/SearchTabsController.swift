import Cocoa
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramContext
import TelegramTheme
import Localization

public final class SearchTabsView: Control {
    fileprivate let tagsView = ScrollableSegmentView(frame: NSMakeRect(0, -10, 0, 40))
    fileprivate var sectionView: NSView?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        backgroundColor = .clear
        tagsView.frame = NSMakeRect(0, -10, frameRect.width, 40)
        addSubview(tagsView)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var sendRightMouseAnyway: Bool {
        return false
    }

    fileprivate func set(sectionView: NSView) {
        self.sectionView?.removeFromSuperview()
        self.sectionView = sectionView
        addSubview(sectionView)
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        tagsView.frame = NSMakeRect(0, -10, frame.width, 40)
        sectionView?.frame = NSMakeRect(0, tagsView.frame.maxY, frame.width, max(0, frame.height - tagsView.frame.maxY))
    }
}

public final class SearchTabsController<Context: AccountContextProtocol>: GenericViewController<SearchTabsView> {
    private let context: Context
    private let tags: [PeerListState.SelectedSearchTag]
    private let openResult: (UIChatListEntryId, MessageId?, Bool) -> Void
    private let close: () -> Void
    private let loading = ValuePromise<Bool>(false, ignoreRepeated: true)
    private let loadingDisposable = MetaDisposable()
    private var section: SectionViewController?
    private var selectedTag: PeerListState.SelectedSearchTag
    private var peerTag: Peer?
    private var query: String?

    public var clearQuery: (() -> Void)?

    public var isLoading: Signal<Bool, NoError> {
        return loading.get()
    }

    public init(context: Context, tags: [PeerListState.SelectedSearchTag], selected: PeerListState.SelectedSearchTag, open: @escaping (UIChatListEntryId, MessageId?, Bool) -> Void, close: @escaping () -> Void) {
        self.context = context
        self.tags = tags
        self.selectedTag = tags.contains(selected) ? selected : tags.first ?? .chats
        self.openResult = open
        self.close = close
        super.init()
        self.bar = .init(height: 0)
    }

    private var visibleTags: [PeerListState.SelectedSearchTag] {
        guard peerTag != nil else {
            return tags
        }
        return tags.filter { tag in
            switch tag {
            case .channels, .apps, .globalPosts, .downloads:
                return false
            default:
                return true
            }
        }
    }

    private var selectedController: SearchController<Context>? {
        guard let section = section, let index = tags.firstIndex(of: selectedTag) else {
            return nil
        }
        return section.sections[index].controller as? SearchController<Context>
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        let context = self.context
        let rect = NSMakeRect(0, 0, frame.width, max(0, frame.height - 30))

        let items = tags.map { tag -> SectionControllerItem in
            let controller = SearchController<Context>(context: context, open: { [weak self] id, messageId, close in
                self?.open(id, messageId: messageId, close: close)
            }, options: tag.searchOptions, frame: rect, target: .common(.root), tags: tag.searchTags(nil, hashtag: nil))
            controller.navigationController = self.navigationController
            controller.setPeerAsTag = { [weak self] peer in
                self?.clearQuery?()
                self?.update(peerTag: peer)
            }
            return SectionControllerItem(title: { "\(tag.rawValue)" }, controller: controller)
        }

        let section = SectionViewController(sections: items, selected: tags.firstIndex(of: selectedTag) ?? 0, hasBar: false)
        section._frameRect = rect
        section.navigationController = self.navigationController
        section.loadViewIfNeeded()
        section.genericView._backgroundColor = .clear
        section.selectionUpdateHandler = { [weak self] index in
            self?.didSelect(index)
        }
        self.section = section

        genericView.set(sectionView: section.view)
        genericView.tagsView.didChangeSelectedItem = { [weak self] item in
            if let tag = PeerListState.SelectedSearchTag(rawValue: Int32(item.uniqueId)) {
                self?.select(tag)
            }
        }

        updateTags(animated: false)
        observeLoading()

        ready.set(section.ready.get())
    }

    public func request(with query: String?) {
        self.query = query
        selectedController?.request(with: query)
    }

    public func resetPeerTag() -> Bool {
        guard peerTag != nil else {
            return false
        }
        update(peerTag: nil)
        return true
    }

    private func open(_ id: UIChatListEntryId?, messageId: MessageId?, close: Bool) {
        guard let id = id else {
            self.close()
            return
        }
        let searchTags = selectedTag.searchTags(peerTag?.id, hashtag: nil)
        openResult(id, messageId, searchTags.peerTag != nil && searchTags.messageTags != nil)
        if close, searchTags.isEmpty {
            self.close()
        }
    }

    private func select(_ tag: PeerListState.SelectedSearchTag) {
        if tag == selectedTag {
            if tag == .chats, peerTag != nil {
                update(peerTag: nil)
            }
            return
        }
        guard let index = tags.firstIndex(of: tag) else {
            return
        }
        selectedTag = tag
        section?.select(index, true)
        selectedController?.request(with: query)
        updateTags(animated: true)
        observeLoading()
    }

    private func didSelect(_ index: Int) {
        guard tags.indices.contains(index) else {
            return
        }
        let tag = tags[index]
        if tag != selectedTag {
            selectedTag = tag
            selectedController?.request(with: query)
            updateTags(animated: true)
        }
        observeLoading()
    }

    private func update(peerTag: Peer?) {
        self.peerTag = peerTag
        if let section = section {
            for (index, tag) in tags.enumerated() {
                (section.sections[index].controller as? SearchController<Context>)?.updateSearchTags(tag.searchTags(peerTag?.id, hashtag: nil))
            }
        }
        if !visibleTags.contains(selectedTag) {
            select(.chats)
        } else {
            selectedController?.request(with: query)
            updateTags(animated: true)
        }
    }

    private func observeLoading() {
        if let controller = selectedController {
            loadingDisposable.set((controller.isLoading.get() |> deliverOnMainQueue).startStrict(next: { [weak self] isLoading in
                self?.loading.set(isLoading)
            }))
        } else {
            loadingDisposable.set(nil)
            loading.set(false)
        }
    }

    private func updateTags(animated: Bool) {
        let presentation = ScrollableSegmentTheme(background: .clear, border: theme.colors.border, selector: theme.colors.accent, inactiveText: theme.colors.grayText, activeText: theme.colors.text, textFont: .normal(.text))
        let insets = NSEdgeInsets(left: 10, right: 10)
        var items: [ScrollableSegmentItem] = []
        for tag in visibleTags {
            let title: String
            switch tag {
            case .chats:
                title = peerTag == nil ? strings().chatListChatsTag : strings().chatListMessagesTag
            case .globalPosts:
                title = strings().chatListPostsTag
            default:
                title = tag.title
            }
            items.append(.init(title: title, index: items.count, uniqueId: Int64(tag.rawValue), selected: tag == selectedTag, insets: insets, icon: nil, theme: presentation, equatable: nil))
        }
        genericView.tagsView.updateItems(items, animated: animated, autoscroll: true)
        genericView.tagsView.theme = presentation
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        if isLoaded() {
            updateTags(animated: false)
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        section?.viewWillAppear(animated)
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        section?.viewDidAppear(animated)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        section?.viewWillDisappear(animated)
        loading.set(false)
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        section?.viewDidDisappear(animated)
    }

    deinit {
        loadingDisposable.dispose()
    }
}
