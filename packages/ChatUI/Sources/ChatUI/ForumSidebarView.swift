import Cocoa
import TGUIKit
import TelegramCore
import TelegramTheme
import TelegramContext
import Localization
import Postbox

public protocol ForumSidebarRowsContent: AnyObject {
    var view: NSView { get }
    func update(items: [EngineChatList.Item], selectedThreadId: Int64?, kind: ChatSidebarKind, parentPeer: EngineRenderedPeer)
    func search(query: String?, peerId: PeerId, loadingUpdated: @escaping (Bool) -> Void)
    func selectSearchResult()
    var isSelecting: Bool { get }
    var selectionChanged: ((Bool) -> Void)? { get set }
    func setSelecting(_ selecting: Bool)
}

public extension ForumSidebarRowsContent {
    var isSelecting: Bool { false }
    var selectionChanged: ((Bool) -> Void)? { get { nil } set { } }
    func setSelecting(_ selecting: Bool) { }
}

final class ForumSidebarView: View {
    private let contentView = View(frame: .zero)
    private let titleLabel = NSTextField(labelWithString: "")
    private let searchView = SearchView(frame: .zero)
    private let newTopicButton = TextButton()
    private let doneButton = TextButton()
    private var canCreateTopics = false
    private let bottomShadowView = EdgeEffectView()
    private let separator = View(frame: .zero)
    private var rowsContent: (any ForumSidebarRowsContent)?
    private var items: [MonoforumItem] = []
    private var selectedThreadId: Int64?
    private var peerId: PeerId?
    private var kind: ChatSidebarKind = .forum
    private var parentPeer: EngineRenderedPeer?
    var onSelect: ((Int64?, MessageId?) -> Void)?
    var onNewTopic: (() -> Void)?

    init(frame: NSRect, context: (any AccountContextProtocol)? = nil, rowsContent: (any ForumSidebarRowsContent)? = nil) {
        super.init(frame: frame)
        self.rowsContent = rowsContent
        if let context {
            self.rowsContent = ChatUIHooks.shared.makeForumSidebarRows?(context, { [weak self] threadId, messageId in
                self?.onSelect?(threadId, messageId)
            })
        }
        self.rowsContent?.selectionChanged = { [weak self] _ in self?.updateControls() }
        doneButton.set(text: strings().modalDone, for: .Normal)
        doneButton.set(font: .medium(13), for: .Normal)
        doneButton.set(color: theme.colors.accent, for: .Normal)
        doneButton.set(handler: { [weak self] _ in self?.rowsContent?.setSelecting(false) }, for: .Click)
        contentView.addSubview(doneButton)
        wantsLayer = true
        layer?.cornerRadius = 20
        layer?.masksToBounds = false
        layer?.borderWidth = 1
        layer?.borderColor = theme.colors.border.withAlphaComponent(0.5).cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.16
        layer?.shadowRadius = 14
        layer?.shadowOffset = NSMakeSize(0, -5)
        backgroundColor = theme.colors.background
        contentView.wantsLayer = true
        contentView.layer?.cornerRadius = 20
        contentView.layer?.masksToBounds = true
        contentView.backgroundColor = theme.colors.background
        addSubview(contentView)
        titleLabel.font = .medium(.title)
        titleLabel.textColor = theme.colors.text
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        searchView.searchTheme = .init(theme.colors.background, theme.search.searchImage, theme.search.clearImage, {
            strings().chatListSearchPlaceholder
        }, theme.search.textColor, theme.search.placeholderColor)
        searchView.layer?.borderWidth = 1
        searchView.layer?.borderColor = theme.colors.border.withAlphaComponent(0.75).cgColor
        searchView.searchInteractions = SearchInteractions({ [weak self] state, _ in
            self?.updateSearch(state)
        }, { [weak self] state in
            self?.updateSearch(state)
        })
        newTopicButton.autoSizeToFit = false
        newTopicButton.scaleOnClick = true
        newTopicButton.animates = true
        newTopicButton.layer?.cornerRadius = 22
        newTopicButton.set(text: strings().forumTopicTitleCreate, for: .Normal)
        newTopicButton.set(font: .medium(15), for: .Normal)
        newTopicButton.set(color: .white, for: .Normal)
        newTopicButton.set(background: theme.colors.accent, for: .Normal)
        newTopicButton.set(background: theme.colors.accent.withAlphaComponent(0.8), for: .Highlight)
        newTopicButton.setAccessibilityLabel(strings().forumTopicTitleCreate)
        newTopicButton.set(handler: { [weak self] _ in self?.onNewTopic?() }, for: .Click)
        bottomShadowView.isEventLess = true
        separator.backgroundColor = theme.colors.border.withAlphaComponent(0.55)
        contentView.addSubview(titleLabel)
        contentView.addSubview(searchView)
        contentView.addSubview(separator)
        if let rowsContent = self.rowsContent {
            contentView.addSubview(rowsContent.view)
        }
        contentView.addSubview(bottomShadowView)
        contentView.addSubview(newTopicButton)
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateSearch(_ state: SearchState) {
        guard let peerId else { return }
        rowsContent?.search(query: state.state == .Focus ? state.request : nil, peerId: peerId, loadingUpdated: { [weak self] loading in
            self?.searchView.isLoading = loading
        })
    }

    func set(items: [MonoforumItem], selectedThreadId: Int64?, title: String, peerId: PeerId, kind: ChatSidebarKind, parentPeer: EngineRenderedPeer) {
        self.peerId = peerId
        self.kind = kind
        self.parentPeer = parentPeer
        self.items = items
        self.selectedThreadId = selectedThreadId
        titleLabel.stringValue = title
        canCreateTopics = kind.showsNewTopic && (parentPeer.peer?._asPeer() as? TelegramChannel)?.hasPermission(.createTopics) == true
        updateControls()
        updateRows()
        needsLayout = true
    }

    private func updateControls() {
        let selecting = rowsContent?.isSelecting == true
        searchView.userInteractionEnabled = !selecting
        newTopicButton.isHidden = !canCreateTopics || selecting
        bottomShadowView.isHidden = !canCreateTopics || selecting
        doneButton.isHidden = !selecting
        needsLayout = true
    }

    func rowsSelectionEnded() { _ = cancelSelection() }

    func cancelSelection() -> Bool {
        guard rowsContent?.isSelecting == true else { return false }
        rowsContent?.setSelecting(false)
        return true
    }

    func beginSelection() {
        cancelSearch()
        rowsContent?.setSelecting(true)
    }

    private func updateRows() {
        guard let parentPeer else { return }
        rowsContent?.update(items: items.compactMap(\.item), selectedThreadId: selectedThreadId, kind: kind, parentPeer: parentPeer)
    }

    func focusSearch() {
        guard rowsContent?.isSelecting != true else { return }
        searchView.change(state: .Focus, true)
        window?.makeFirstResponder(searchView.input)
    }

    @discardableResult func cancelSearch() -> Bool {
        guard searchView.state == .Focus else { return false }
        searchView.cancel(true)
        return true
    }

    func activateSearchResult() -> Bool {
        guard searchView.state == .Focus, window?.firstResponder === searchView.input else { return false }
        rowsContent?.selectSearchResult()
        return true
    }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 20, cornerHeight: 20, transform: nil)
        contentView.frame = bounds
        let titleHeight = titleLabel.intrinsicContentSize.height
        let titleInset: CGFloat = rowsContent?.isSelecting == true ? 58 : 10
        titleLabel.frame = NSMakeRect(titleInset, floor((50 - titleHeight) / 2), max(0, bounds.width - titleInset * 2), titleHeight)
        doneButton.frame = NSMakeRect(max(0, bounds.width - 60), 9, 50, 32)
        searchView.frame = NSMakeRect(10, 50, max(0, bounds.width - 20), 30)
        searchView.updateLayout(size: searchView.frame.size, transition: .immediate)
        let rowsTop: CGFloat = 90
        separator.frame = NSMakeRect(0, rowsTop - 1, bounds.width, 1)
        rowsContent?.view.frame = NSMakeRect(0, rowsTop, bounds.width, max(0, bounds.height - rowsTop))
        let shadowTop = max(rowsTop, bounds.height - 96)
        let shadowRect = NSMakeRect(0, shadowTop, bounds.width, max(0, bounds.height - shadowTop))
        bottomShadowView.frame = shadowRect
        bottomShadowView.update(color: theme.colors.background, alpha: 0.6, edge: .top, edgeSize: min(60, shadowRect.height), rect: shadowRect, transition: .immediate)
        newTopicButton.frame = NSMakeRect(20, max(0, bounds.height - 60), max(0, bounds.width - 40), 44)
    }
}

final class ForumSidebarController: GenericViewController<ForumSidebarView>, TrailingOverlayAdaptable {
    private let context: any AccountContextProtocol
    private var compactOverlay = false
    private var newTopicRequested = false
    private var isPresented = false
    private var pendingUpdate: ((ForumSidebarView) -> Void)?
    var onSelect: ((Int64?, MessageId?) -> Void)?
    var onNewTopic: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onNavigationChanged: (() -> Void)?

    init(context: any AccountContextProtocol) {
        self.context = context
        super.init(frame: NSMakeRect(0, 0, 358, 0))
        bar = .init(height: 0)
        insets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 8)
        context.bindings.rootNavigation().add(listener: WeakReference(value: self))
    }

    override func initializer() -> ForumSidebarView {
        let view = ForumSidebarView(frame: initializationRect, context: context)
        view.onSelect = { [weak self] threadId, messageId in
            guard let self else { return }
            self.onSelect?(threadId, messageId)
            if self.compactOverlay {
                self.onDismiss?()
            }
        }
        view.onNewTopic = { [weak self] in self?.requestNewTopic() }
        return view
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        readyOnce()
    }

    override func navigationWillChangeController() {
        super.navigationWillChangeController()
        onNavigationChanged?()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isPresented = true
        if let pendingUpdate {
            self.pendingUpdate = nil
            pendingUpdate(genericView)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        isPresented = false
        super.viewWillDisappear(animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        newTopicRequested = false
        context.window.set(handler: { [weak self] _ in
            guard let self, !hasModals(self.context.window), !contextMenuOnScreen() else { return .rejected }
            return self.escapeKeyAction()
        }, with: self, for: .Escape, priority: .supreme)
        context.window.set(handler: { [weak self] _ in
            guard let self, !hasModals(self.context.window), !contextMenuOnScreen() else { return .rejected }
            self.genericView.focusSearch()
            return .invoked
        }, with: self, for: .K, priority: .high, modifierFlags: [.command])
        context.window.set(handler: { [weak self] _ in
            guard let self, !hasModals(self.context.window), !contextMenuOnScreen() else { return .rejected }
            return self.genericView.activateSearchResult() ? .invoked : .rejected
        }, with: self, for: .Return, priority: .modal, modifierFlags: [])
    }

    override func viewDidDisappear(_ animated: Bool) {
        context.window.removeAllHandlers(for: self)
        genericView.cancelSearch()
        genericView.rowsSelectionEnded()
        super.viewDidDisappear(animated)
    }

    func performNewTopic() { requestNewTopic() }

    private func requestNewTopic() {
        guard !newTopicRequested else { return }
        newTopicRequested = true
        if compactOverlay {
            onDismiss?()
        }
        onNewTopic?()
    }

    override func escapeKeyAction() -> KeyHandlerResult {
        if genericView.cancelSelection() { return .invoked }
        if compactOverlay {
            onDismiss?()
            return .invoked
        }
        return genericView.cancelSearch() ? .invoked : .rejected
    }

    func set(items: [MonoforumItem], selectedThreadId: Int64?, title: String, peerId: PeerId, kind: ChatSidebarKind, parentPeer: EngineRenderedPeer) {
        let update: (ForumSidebarView) -> Void = { view in
            view.set(items: items, selectedThreadId: selectedThreadId, title: title, peerId: peerId, kind: kind, parentPeer: parentPeer)
        }
        if isPresented {
            update(genericView)
        } else {
            pendingUpdate = update
        }
    }

    var isCompactOverlay: Bool { compactOverlay }

    func setTrailingOverlayMode(_ compact: Bool) {
        compactOverlay = compact
    }

    func dismissTrailingOverlay() {
        onDismiss?()
    }
}
