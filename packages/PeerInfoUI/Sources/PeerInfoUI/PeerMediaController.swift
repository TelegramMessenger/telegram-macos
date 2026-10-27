 import Cocoa
 import TGUIKit
 import TelegramCore
 
 import SwiftSignalKit
 import Postbox
 import TelegramContext
 import AlertsUI
 import CaptureExclusion
 import ChatHistoryModel
 import ChatListUI
 import ChatModeTypes
 import ChatUI
 import GeneralRows
  import InputDataUI
 import LocalAnimations
 import Localization
 import MessageUtils
 import PeerMediaUI
 import SelectPeersUI
 import ShareUI
 import StarsUI
 import StoriesUI
 import TelegramLinks
 import TelegramTheme
 import TelegramUtils
 
 
 
 
 private final class SearchContainerView : View {
    fileprivate let searchView: SearchView = SearchView(frame: NSMakeRect(0, 0, 200, 30))
    fileprivate let close: ImageButton = ImageButton()
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(searchView)
        addSubview(close)
        close.setAccessibilityLabel(strings().voiceOverCommonClose)
        layer?.cornerRadius = PeerMediaTabsView.height / 2
        updateLocalizationAndTheme(theme: theme)
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = theme as! TelegramPresentationTheme
        borderColor = theme.colors.border
        backgroundColor = theme.colors.background
        close.set(image: theme.icons.dismissPinned, for: .Normal)
        _ = close.sizeToFit()
    }
    
    override func layout() {
        super.layout()
        searchView.setFrameSize(NSMakeSize(frame.width - close.frame.width - 30, 30))
        searchView.centerY(x: 10)
        close.centerY(x: searchView.frame.maxX + 10)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
 }
 
 private let tabSwipeVelocityWindow: TimeInterval = 0.1
 private let tabSwipeSwitchVelocity: CGFloat = 180
 private let tabSwipeSwitchFraction: CGFloat = 0.35
 
 private enum PeerMediaAnimationDirection {
    case leftToRight
    case rightToLeft
    case interactive
 }
 private let sectionOffset: CGFloat = 0
 
 public final class PeerMediaContainerView : View {

    private let actionsPanelView:MessageActionsPanelView = MessageActionsPanelView(frame: NSMakeRect(0,0,0, 52))
    
    fileprivate let view: PeerMediaControllerView
    fileprivate var emptyView: PeerMediaEmptyRowView?
    fileprivate var emptyItem: PeerMediaEmptyRowItem?
    init(frame frameRect: NSRect, isSegmentHidden: Bool) {
        view = PeerMediaControllerView(frame: NSMakeRect(0, 0, PeerMediaContainerView.blockWidth(frameRect.width), frameRect.height - sectionOffset), isSegmentHidden: isSegmentHidden)
        super.init(frame: frameRect)
        addSubview(view)
        addSubview(actionsPanelView)
        actionsPanelView.isHidden = true
//        backgroundColor = theme.colors.listBackground
        layout()
    }
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
    }
    
    public override func scrollWheel(with event: NSEvent) {
        view.scrollWheel(with: event)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    var didMoveToWindow: (() -> Void)?

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            didMoveToWindow?()
        }
    }

     public override func setFrameOrigin(_ newOrigin: NSPoint) {
         super.setFrameOrigin(newOrigin)
     }

    private static func blockWidth(_ width: CGFloat) -> CGFloat {
        return min(600, width - 40)
    }

    public override func layout() {
        super.layout()

        let blockWidth = PeerMediaContainerView.blockWidth(frame.width)
        
        
        view.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - blockWidth) / 2), sectionOffset, blockWidth, frame.height - sectionOffset)
        
        let inset:CGFloat = view.isSelectionState ? 54 : 0
        actionsPanelView.frame = NSMakeRect(0, frame.height - inset, frame.width, 52)
        actionsPanelView.isHidden = !view.isSelectionState
        emptyView?.frame = bounds
    }
    
    var mainView:NSView? {
        return self.view.mainView
    }
    
    var headerOverflow: CGFloat? {
        get {
            return view.headerOverflow
        }
        set {
            view.headerOverflow = newValue
            layer?.masksToBounds = newValue == nil
        }
    }
    
    func setHeaderPinned(_ pinned: Bool, animated: Bool) {
        view.setHeaderPinned(pinned, animated: animated)
    }
    
    public var mainTable: TableView? {
        if let tableView = self.view.mainView as? TableView {
            return tableView
        } else if let view = self.view.mainView as? InputDataView {
            return view.tableView
        } else if let view = self.view.mainView as? PeerMediaGifsView {
            return view.tableView
        } else if let view = self.view.mainView as? StoryMediaView {
            return view.tableView
        }
        return nil
    }
    
    func updateInteraction(_ chatInteraction:ChatInteraction) {
        self.view.updateInteraction(chatInteraction)
        actionsPanelView.prepare(with: chatInteraction)
    }
    
    
    fileprivate func updateMainView(with view:NSView, animated:PeerMediaAnimationDirection?) {
        self.view.updateMainView(with: view, animated: animated)
    }
    
    func updateSearchState(_ state: MediaSearchState, updateSearchState:@escaping(SearchState)->Void, toggle:@escaping()->Void) {
        self.view.updateSearchState(state, updateSearchState: updateSearchState, toggle: toggle)
    }
     
     func updateEmpty(_ isEmpty: Bool, animated: Bool) {
         self.topPanelView.isHidden = isEmpty
         self.view.needsLayout = true
         if isEmpty {
             let current: PeerMediaEmptyRowView
             if let view = self.emptyView {
                 current = view
             } else {
                 current = .init(frame: self.bounds)
                 self.emptyView = current
                 self.addSubview(current)
                 if animated {
                     self.emptyView?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                 }
             }
             
             let item = self.emptyItem ?? PeerMediaEmptyRowItem(bounds.size, tags: nil)
             self.emptyItem = item
             current.set(item: item, animated: animated)
         } else if let view = emptyView {
             performSubviewRemoval(view, animated: animated)
             self.emptyView = nil
             self.emptyItem = nil
         }
     }
    
    func changeState(selectState:Bool, animated:Bool) {
        self.view.changeState(selectState: selectState, animated: animated)
        actionsPanelView.isHidden = !selectState
        let inset:CGFloat = selectState ? 54 : 0
        actionsPanelView.change(pos: NSMakePoint(0, frame.height - inset), animated: animated)
    }
    
    var activePanel: View {
        return self.view.activePanel
    }
    
    
    fileprivate var tabsView: PeerMediaTabsView {
        return self.view.tabsView
    }
     fileprivate var topPanelView: NSView {
         return self.view.topPanelView
     }
    fileprivate var searchPanelView: SearchContainerView? {
        return self.view.searchPanelView
    }
    
    fileprivate func updateTabs(_ tabs: [PeerMediaTabsView.Tab], selected: Int64?, account: Account, animated: Bool) {
        view.updateTabs(tabs, selected: selected, account: account, animated: animated)
    }
 }
 
 class PeerMediaControllerView : View {
    
    private static let tabsTopInset: CGFloat = 12
    private static let tabsBottomInset: CGFloat = 12
    private static var topPanelHeight: CGFloat {
        return tabsTopInset + PeerMediaTabsView.height + tabsBottomInset
    }
    private static let contentCornerRadius: CGFloat = 20
    private static let headerEdgeExtension: CGFloat = 68
    private static let headerEdgeFadeHeight: CGFloat = 60
    
    fileprivate let topPanelView = View()
    fileprivate let tabsView = PeerMediaTabsView(frame: .zero)
    fileprivate var searchPanelView: SearchContainerView?
    private let contentView = View()
    private let headerUnderlayView = View()
    private let headerEdgeView = EdgeEffectView(frame: .zero)
    private var pageScrollObservers: [ObjectIdentifier: NSObjectProtocol] = [:]
    
    var headerOverflow: CGFloat? {
        didSet {
            if headerOverflow != oldValue {
                contentView.layer?.cornerRadius = headerOverflow == nil ? PeerMediaControllerView.contentCornerRadius : 0
                needsLayout = true
            }
        }
    }
    
    private(set) weak var mainView:NSView?
    private var previousPage: NSView?
    private var nextPage: NSView?
    private var swipeOffset: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        mainTable?.scrollWheel(with: event)
    }
    
    var mainTable: TableView? {
        if let tableView = self.mainView as? TableView {
            return tableView
        } else if let view = self.mainView as? InputDataView {
            return view.tableView
        } else if let view = self.mainView as? StoryMediaView {
            return view.tableView
        } else if let view = self.mainView as? PeerMediaGifsView {
            return view.tableView
        }
        return nil
    }
    
    fileprivate var isSelectionState:Bool = false
    private var chatInteraction:ChatInteraction?
    private var searchState: SearchState?
    init(frame frameRect:NSRect, isSegmentHidden: Bool) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false
        contentView.layer?.masksToBounds = true
        contentView.layer?.cornerRadius = PeerMediaControllerView.contentCornerRadius
        contentView.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        headerUnderlayView.layer?.opacity = 0
        headerEdgeView.layer?.opacity = 0
        headerEdgeView.isEventLess = true
        addSubview(headerUnderlayView)
        addSubview(contentView)
        addSubview(headerEdgeView)
        topPanelView.layer?.masksToBounds = false
        topPanelView.isEventLess = true
        addSubview(topPanelView)
        topPanelView.isHidden = isSegmentHidden
        topPanelView.addSubview(tabsView)
        updateLocalizationAndTheme(theme: theme)
        layout()
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        backgroundColor = theme.colors.listBackground
        headerUnderlayView.backgroundColor = theme.colors.listBackground
        tabsView.updateLocalizationAndTheme(theme: theme)
        searchPanelView?.updateLocalizationAndTheme(theme: theme)
        updateHeaderEdge()
    }

    private func updateHeaderEdge() {
        guard let headerOverflow = headerOverflow else {
            headerEdgeView.isHidden = true
            return
        }
        let edgeFrame = NSMakeRect(0, -headerOverflow, frame.width, headerOverflow + PeerMediaControllerView.headerEdgeExtension)
        let blur: EdgeEffectView.Blur? = System.blurEnabled ? EdgeEffectView.Blur(rect: edgeFrame, edgeSize: PeerMediaControllerView.headerEdgeFadeHeight) : nil
        headerEdgeView.isHidden = false
        headerEdgeView.frame = edgeFrame
        headerEdgeView.update(color: theme.colors.listBackground, blur: blur, edge: .bottom, edgeSize: PeerMediaControllerView.headerEdgeFadeHeight, rect: edgeFrame, transition: .immediate)
    }
    
    deinit {
        for observer in pageScrollObservers.values {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    func setHeaderPinned(_ pinned: Bool, animated: Bool) {
        headerUnderlayView.change(opacity: pinned ? 1 : 0, animated: animated)
        headerEdgeView.change(opacity: pinned ? 1 : 0, animated: animated)
        if !pinned {
            for view in contentView.subviews {
                scrollPageToTop(view)
            }
        }
    }
    
    private func scrollPageToTop(_ view: NSView) {
        guard let table = pageTable(view) else {
            return
        }
        let top = -table.contentInsets.top
        if table.liveDocumentOffset.y != top {
            table.clipView.scroll(to: NSMakePoint(0, top))
            table.reflectScrolledClipView(table.clipView)
        }
    }
    
    func updateInteraction(_ chatInteraction:ChatInteraction) {
        self.chatInteraction = chatInteraction
    }
    
    var contentBounds: NSRect {
        return NSMakeRect(0, 0, frame.width, contentHeight)
    }
    
    private var panelHeight: CGFloat {
        return topPanelView.isHidden ? 0 : PeerMediaControllerView.topPanelHeight
    }
    
    private var contentTop: CGFloat {
        if let headerOverflow = headerOverflow {
            return -headerOverflow
        } else {
            return panelHeight
        }
    }
    
    private var pageTopInset: CGFloat {
        if let headerOverflow = headerOverflow {
            return headerOverflow + panelHeight
        } else {
            return 0
        }
    }
    
    private var contentHeight: CGFloat {
        return max(0, frame.height - (isSelectionState ? 70 : 0) - contentTop)
    }
    
    private var tabsFrame: NSRect {
        let size = tabsView.size(fitting: frame.width)
        return NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - size.width) / 2), PeerMediaControllerView.tabsTopInset, size.width, size.height)
    }
    
    fileprivate func updateTabs(_ tabs: [PeerMediaTabsView.Tab], selected: Int64?, account: Account, animated: Bool) {
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.4, curve: .spring) : .immediate
        tabsView.update(tabs: tabs, selected: selected, account: account, animated: animated)
        tabsView.apply(frame: tabsFrame, transition: transition)
    }
    
    fileprivate var hasPreviousPage: Bool {
        return previousPage != nil
    }
    
    fileprivate var hasNextPage: Bool {
        return nextPage != nil
    }
    
    fileprivate func setNeighborPages(previous: NSView?, next: NSView?) {
        previousPage = previous
        nextPage = next
        for view in [previous, next].compactMap({ $0 }) where view.superview !== contentView {
            view.frame = contentView.bounds
            view.alphaValue = 0
            if let mainView = mainView {
                contentView.addSubview(view, positioned: .below, relativeTo: mainView)
            } else {
                contentView.addSubview(view)
            }
        }
        layoutPages()
    }
    
    fileprivate func finishTransition() {
        for view in contentView.subviews {
            view.layer?.removeAnimation(forKey: "position")
        }
    }
    
    fileprivate func updateSwipeOffset(_ offset: CGFloat) {
        swipeOffset = offset
        layoutPages()
    }
    
    fileprivate func cancelSwipe(animated: Bool) {
        let side: CGFloat = swipeOffset > 0 ? -1 : 1
        let visibleNeighbor = swipeOffset > 0 ? previousPage : (swipeOffset < 0 ? nextPage : nil)
        swipeOffset = 0
        guard animated else {
            pagesDidSettle()
            return
        }
        if let visibleNeighbor = visibleNeighbor {
            visibleNeighbor.layer?.animatePosition(from: visibleNeighbor.frame.origin, to: NSMakePoint(side * contentView.frame.width, visibleNeighbor.frame.minY), duration: 0.4, timingFunction: .spring, removeOnCompletion: false)
        }
        mainView?._change(pos: NSZeroPoint, animated: true, duration: 0.4, timingFunction: .spring, completion: { [weak self] completed in
            if completed {
                self?.pagesDidSettle()
            }
        })
    }
    
    private func pagesDidSettle() {
        finishTransition()
        layoutPages()
        notifyPagesMoved()
    }
    
    private func notifyPagesMoved() {
        for view in contentView.subviews {
            if let table = pageTable(view) {
                NotificationCenter.default.post(name: NSView.boundsDidChangeNotification, object: table.clipView)
            }
        }
    }
    
    private func pageTable(_ view: NSView) -> TableView? {
        if let view = view as? TableView {
            return view
        } else if let view = view as? InputDataView {
            return view.tableView
        } else if let view = view as? StoryMediaView {
            return view.tableView
        } else if let view = view as? PeerMediaGifsView {
            return view.tableView
        } else {
            return nil
        }
    }
    
    private func preparePage(_ view: NSView) {
        guard headerOverflow != nil else {
            return
        }
        if let table = pageTable(view) {
            let topInset = pageTopInset
            if table.contentInsets.top != topInset {
                let progress = table.liveDocumentOffset.y + table.contentInsets.top
                var insets = table.contentInsets
                insets.top = topInset
                table.contentInsets = insets
                table.clipView.scroll(to: NSMakePoint(0, progress - topInset))
                table.reflectScrolledClipView(table.clipView)
                table.updateStickInset(topInset, animated: false)
            }
            let key = ObjectIdentifier(table)
            if pageScrollObservers[key] == nil {
                pageScrollObservers[key] = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: table.clipView, queue: nil, using: { [weak self, weak view] _ in
                    if let self = self, let view = view {
                        self.updatePageMask(view)
                    }
                })
            }
        }
        updatePageMask(view)
    }
    
    private func updatePageMask(_ view: NSView) {
        guard let layer = view.layer else {
            return
        }
        let mask: CALayer
        if let current = layer.mask {
            mask = current
        } else {
            mask = CALayer()
            mask.backgroundColor = NSColor.black.cgColor
            mask.cornerRadius = PeerMediaControllerView.contentCornerRadius
            mask.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            layer.mask = mask
        }
        var top: CGFloat = 0
        if let table = pageTable(view) {
            let tableTop = table === view ? 0 : table.frame.minY
            top = max(-PeerMediaControllerView.contentCornerRadius, tableTop - table.liveDocumentOffset.y)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mask.frame = NSMakeRect(0, top, view.frame.width, max(0, view.frame.height - top))
        CATransaction.commit()
    }
    
    private func layoutPages(transition: ContainedViewLayoutTransition = .immediate) {
        let bounds = contentView.bounds
        if let mainView = mainView {
            transition.updateFrame(view: mainView, frame: bounds.offsetBy(dx: swipeOffset, dy: 0))
        }
        let visibleNeighbor = swipeOffset > 0 ? previousPage : (swipeOffset < 0 ? nextPage : nil)
        for view in contentView.subviews where view !== mainView {
            if view === visibleNeighbor {
                view.alphaValue = 1
                transition.updateFrame(view: view, frame: bounds.offsetBy(dx: swipeOffset + (view === previousPage ? -bounds.width : bounds.width), dy: 0))
            } else if view.layer?.animation(forKey: "position") == nil {
                view.alphaValue = 0
                transition.updateFrame(view: view, frame: bounds)
                if let mainView = mainView, let index = contentView.subviews.firstIndex(of: view), let mainIndex = contentView.subviews.firstIndex(of: mainView), index > mainIndex {
                    contentView.addSubview(view, positioned: .below, relativeTo: mainView)
                }
            }
        }
        for view in contentView.subviews {
            preparePage(view)
        }
    }
    
    fileprivate func updateMainView(with view:NSView, animated:PeerMediaAnimationDirection?) {
        var animated = animated
        let isNextPage = view === nextPage
        if animated == .interactive, view !== nextPage, view !== previousPage {
            animated = .leftToRight
        }
        if previousPage === view {
            previousPage = nil
        }
        if nextPage === view {
            nextPage = nil
        }
        swipeOffset = 0
        view.alphaValue = 1
        if view.superview !== contentView {
            contentView.addSubview(view)
        }
        
        let timingFunction: CAMediaTimingFunctionName = .spring
        let duration: TimeInterval = 0.4
        
        let previousMain = mainView
        self.mainView = view
        
        if let animated = animated {
            if let previousMain = previousMain, previousMain !== view {
                let settle: (Bool) -> Void = { [weak self] completed in
                    if completed {
                        self?.pagesDidSettle()
                    }
                }
                contentView.addSubview(previousMain, positioned: .below, relativeTo: view)
                let origin = previousMain.frame.origin
                switch animated {
                case .leftToRight:
                    previousMain.layer?.animatePosition(from: origin, to: NSMakePoint(origin.x - previousMain.frame.width, origin.y), duration: duration, timingFunction: timingFunction, removeOnCompletion: false, completion: settle)
                    view.layer?.animatePosition(from: NSMakePoint(view.frame.width, origin.y), to: NSMakePoint(0, origin.y), duration: duration, timingFunction: timingFunction)
                case .rightToLeft:
                    previousMain.layer?.animatePosition(from: origin, to: NSMakePoint(origin.x + previousMain.frame.width, origin.y), duration: duration, timingFunction: timingFunction, removeOnCompletion: false, completion: settle)
                    view.layer?.animatePosition(from: NSMakePoint(-view.frame.width, origin.y), to: NSMakePoint(0, origin.y), duration: duration, timingFunction: timingFunction)
                case .interactive:
                    let exitX = isNextPage ? -previousMain.frame.width : previousMain.frame.width
                    previousMain.layer?.animatePosition(from: origin, to: NSMakePoint(exitX, origin.y), duration: duration, timingFunction: timingFunction, removeOnCompletion: false)
                    view._change(pos: NSZeroPoint, animated: true, duration: duration, timingFunction: timingFunction, completion: settle)
                }
            }
        }
        layoutPages()
    }
    
    func updateSearchState(_ state: MediaSearchState, updateSearchState:@escaping(SearchState)->Void, toggle:@escaping()->Void) {
        self.searchState = state.state
        switch state.state.state {
        case .Focus:
            if searchPanelView == nil {
                let searchPanelView = SearchContainerView(frame: searchPanelFrame)
                self.searchPanelView = searchPanelView
                topPanelView.addSubview(searchPanelView)
                searchPanelView.searchView.change(state: .Focus, false)
                searchPanelView.searchView.searchInteractions = SearchInteractions({ _, _ in
    
                }, updateSearchState)
    
                searchPanelView.close.set(handler: { _ in
                    toggle()
                }, for: .Click)
    
                if state.animated {
                    searchPanelView.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    searchPanelView.layer?.animatePosition(from: NSMakePoint(searchPanelView.frame.minX, searchPanelView.frame.minY - 10), to: searchPanelView.frame.origin, duration: 0.4, timingFunction: .spring)
                }
            }
    
            guard let searchPanelView = self.searchPanelView else {
                fatalError()
            }
            searchPanelView.searchView.isLoading = state.isLoading
            tabsView._change(opacity: 0, animated: state.animated)
        case .None:
            tabsView._change(opacity: 1, animated: state.animated)
            if let searchPanelView = self.searchPanelView {
                self.searchPanelView = nil
                performSubviewRemoval(searchPanelView, animated: state.animated)
            }
        }
    }
    
    func changeState(selectState:Bool, animated:Bool) {
        assert(mainView != nil)

        self.isSelectionState = selectState
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeInOut) : .immediate
        transition.updateFrame(view: contentView, frame: NSMakeRect(0, contentTop, frame.width, contentHeight))
        layoutPages(transition: transition)
    }
    
    var activePanel: View {
        if let searchPanel = self.searchPanelView {
            return searchPanel
        } else {
            return tabsView
        }
    }
    
    private var searchPanelFrame: NSRect {
        return NSMakeRect(0, PeerMediaControllerView.tabsTopInset, frame.width, PeerMediaTabsView.height)
    }
    
    override func layout() {
        topPanelView.frame = NSMakeRect(0, 0, frame.width, PeerMediaControllerView.topPanelHeight)
        tabsView.frame = tabsFrame
        searchPanelView?.frame = searchPanelFrame
        headerUnderlayView.frame = NSMakeRect(0, -(headerOverflow ?? 0), frame.width, headerOverflow ?? 0)
        contentView.frame = NSMakeRect(0, contentTop, frame.width, contentHeight)
        updateHeaderEdge()
        layoutPages()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
 }
 
 private extension PeerMediaCollectionMode {
     func title(_ peer: Peer?) -> String {
        if self == .members {
            return strings().peerMediaMembers
        }
        if self == .photoOrVideo {
            return strings().peerMediaMedia
        }
        if self == .file {
            return strings().peerMediaFiles
        }
        if self == .webpage {
            return strings().peerMediaLinks
        }
        if self.tagsValue == .music {
            return strings().peerMediaMusic
        }
        if self == .voice {
            return strings().peerMediaVoice
        }
        if self == .commonGroups {
            return strings().peerMediaCommonGroups
        }
         if self == .similarBots {
            return strings().peerMediaSimilarBots
        }
        if self == .similarChannels {
            return strings().peerMediaSimilarChannels
        }
        if self == .gifs {
            return strings().peerMediaGifs
        }
         if self == .gifts {
             return strings().peerMediaGifts
         }
        if self == .stories {
            if peer?.isBot == true {
                return strings().peerMediaPreview
            } else if peer is TelegramChannel {
                return strings().peerMediaPosts
            } else {
                return strings().peerMediaStories
            }
        }
        if self == .archiveStories {
             return strings().peerMediaArchivePosts
        }
        if self == .savedMessages {
            return strings().peerMediaSavedMessages
        }
        if self == .saved {
            return strings().peerMediaSaved
        }
        if self == .polls {
            return strings().peerMediaPolls
        }
        return ""
    }
     
     var profileTab: TelegramProfileTab? {
         switch self {
         case .saved:
             return nil
         case .file:
             return .files
         case .webpage:
             return .links
         case .music:
             return .music
         case .voice:
             return .voice
         case .gifs:
             return .gifs
         case .commonGroups:
             return nil
         case .similarChannels:
             return nil
         case .similarBots:
             return nil
         case .stories:
             return .posts
         case .gifts:
             return .gifts
         case .savedMessages:
             return nil
         case .members:
             return nil
         case .archiveStories:
             return nil
         case .photoOrVideo:
             return .media
         case .polls:
             return nil
         }
     }
 }
 
 public struct PeerMediaExternalSearchData {
    let searchResult: Signal<ExternalSearchMessages?, NoError>
    let loadMore:()->Void
    let initialTags: MessageTags
    init(initialTags: MessageTags, searchResult: Signal<ExternalSearchMessages?, NoError>, loadMore: @escaping()->Void) {
        self.searchResult = searchResult
        self.loadMore = loadMore
        self.initialTags = initialTags
    }
    
    
    var initialMode: PeerMediaCollectionMode {
        if initialTags == .photo || initialTags == .video || initialTags == .photoOrVideo {
            return .photoOrVideo
        } else if initialTags == .gif {
            return .gifs
        } else if initialTags == .file {
            return .file
        } else if initialTags == .voiceOrInstantVideo {
            return .voice
        } else if initialTags == .webPage {
            return .webpage
        } else if initialTags == .music {
            return .music
        }
        preconditionFailure("not supported")
    }
 }
 
 public class PeerMediaController<Context: AccountContextProtocol>: EditableViewController<PeerMediaContainerView, Context>, Notifable {
    
    private let peerId:PeerId
    private var peer:Peer?
    private var peerView: PeerView? {
        didSet {
            if isLoaded(), let peerView = peerView, isProfileIntended {
                let context = self.context
                
                if let cachedData = peerView.cachedData as? CachedChannelData, let peer = peerViewMainPeer(peerView), peer.isGroup || peer.isSupergroup || peer.isGigagroup {
                    let onlineMemberCount:Signal<Int32?, NoError>
                    if (cachedData.participantsSummary.memberCount ?? 0) > 200 {
                        onlineMemberCount = context.peerChannelMemberCategoriesContextsManager.recentOnline(peerId: self.peerId)  |> map(Optional.init) |> deliverOnMainQueue
                    } else {
                        onlineMemberCount = context.peerChannelMemberCategoriesContextsManager.recentOnlineSmall(peerId: self.peerId)  |> map(Optional.init) |> deliverOnMainQueue
                    }
                    self.onlineMemberCountDisposable.set(onlineMemberCount.start(next: { [weak self] count in
                        guard let `self` = self else {
                            return
                        }
                        let result = stringStatus(for: peerView, context: context, theme: PeerStatusStringTheme(titleFont: .medium(.title)), onlineMemberCount: count)
                        self.centerBarView.text = result.title
                        if self.mode == .members {
                            self.centerBarView.status = result.status
                        }
                    }))
                } else {
                    let result = stringStatus(for: peerView, context: context, theme: PeerStatusStringTheme(titleFont: .medium(.title)), onlineMemberCount: 0)
                    self.centerBarView.text = result.title
                    if self.mode == .members {
                        self.centerBarView.status = result.status
                    }
                }
            }
        }
    }
    
    private let modeValue: ValuePromise<PeerMediaCollectionMode?> = ValuePromise(nil, ignoreRepeated: true)
    private let tabsSignal:Promise<(tabs: [PeerMediaCollectionMode], selected: PeerMediaCollectionMode?, hasLoaded: Bool)> = Promise()
    
    var tabsValue: Signal<PeerMediaTabsData, NoError> {
        return tabsSignal.get() |> map {
            PeerMediaTabsData(collections: $0.tabs, loaded: $0.hasLoaded)
        } |> distinctUntilChanged
    }
     
     
    
    private let tabsDisposable = MetaDisposable()
    private let giftIconsDisposable = MetaDisposable()
    private let starGiftsProfile: ProfileGiftsContext?
    private var giftIcons: [ProfileGiftsContext.State.StarGift] = []
    private var currentTabs: (tabs: [PeerMediaCollectionMode], selected: PeerMediaCollectionMode?)?
    
    private enum TabSwipeAxis {
        case undecided
        case horizontal
        case blocked
        case vertical
    }
    
    private struct TabSwipeGesture {
        var axis: TabSwipeAxis = .undecided
        var beganPassedThrough: Bool = false
        var samples: [(timestamp: TimeInterval, delta: CGFloat)] = []
    }
    
    private var tabSwipe: TabSwipeGesture?
    private var swallowsTabSwipeMomentum: Bool = false
    private var tabSwipeOffset: CGFloat = 0
    private var interactiveSwitchMode: PeerMediaCollectionMode?
     
    private var mode:PeerMediaCollectionMode?
    
    private let mediaGrid:PeerMediaPhotosController<Context>
    private let gifs: PeerMediaPhotosController<Context>
    private let stories: StoryMediaController<Context>
    private let archiveStories: StoryMediaController<Context>?
    private let saved: InputDataController
    private var savedMessages: InputDataController?
    private var gifts: ViewController?

    private let listControllers:[PeerMediaListController<Context>]
    private var pollsController: InputDataController?
    private let members: ViewController
    private let commonGroups: ViewController
    private let similarChannels: ViewController
    private let similarBots: ViewController

     private let statusDisposable = MetaDisposable()
    
     private let tagsList:[PeerMediaCollectionMode] = [.members, .stories, .archiveStories, .photoOrVideo, .saved, .file, .webpage, .music, .voice, .gifs, .commonGroups, .similarChannels, .similarBots, .gifts]
     private let tabsOrder:[PeerMediaCollectionMode] = [.savedMessages, .members, .stories, .archiveStories, .photoOrVideo, .saved, .file, .webpage, .music, .voice, .gifs, .polls, .commonGroups, .similarChannels, .similarBots, .gifts]
    
    
    private var currentTagListIndex: Int {
        if let mode = self.mode {
            return Int(mode.rawValue)
        } else {
            return 0
        }
    }
    private var interactions:ChatInteraction
    private let messagesActionDisposable:MetaDisposable = MetaDisposable()
    private let loadFwdMessagesDisposable = MetaDisposable()
    private let loadSelectionMessagesDisposable = MetaDisposable()
    private let searchValueDisposable = MetaDisposable()
    private let onlineMemberCountDisposable = MetaDisposable()
    private let externalSearchData: PeerMediaExternalSearchData?
    private let toggleDisposable = MetaDisposable()
    private let externalDisposable = MetaDisposable()
    private var currentController: ViewController?
     
    private let storyListContext: StoryListContext
    private let archiveStoryListContext: StoryListContext?
    private let threadInfo: ThreadInfo?
    private var captureExclusionToken: CaptureExclusionManager.Token?
    private weak var captureExclusionWindow: NSWindow?
    private var isCaptureProtected: Bool = false

    public var currentMainTableView:((TableView?, Bool, Bool)->Void)? = nil {
        didSet {
            if isLoaded() {
                currentMainTableView?(genericView.mainTable, false, false)
            }
        }
    }
    
    private let isProfileIntended: Bool
     private var initialMode: PeerMediaCollectionMode?
    
    private let editing: ValuePromise<Bool> = ValuePromise(false, ignoreRepeated: true)
    public override var state:ViewControllerState {
        didSet {
            let newValue = state
            
            if newValue != oldValue {
                stories.toggleSelection()
                archiveStories?.toggleSelection()
            }
            
            genericView.mainTable?.scroll(to: .upOffset(true, 0), completion: { [weak self] _ in
                self?.editing.set(newValue == .Edit)
            })
        }
    }
    
     public init(context: Context, peerId:PeerId, threadInfo: ThreadInfo? = nil, isProfileIntended:Bool = false, externalSearchData: PeerMediaExternalSearchData? = nil, isBot: Bool, mode: PeerMediaCollectionMode? = nil, starGiftsProfile: ProfileGiftsContext? = nil) {
        self.externalSearchData = externalSearchData
        self.peerId = peerId
        self.mode = mode
        self.threadInfo = threadInfo
        self.isProfileIntended = isProfileIntended
        self.initialMode = mode
        self.starGiftsProfile = starGiftsProfile
        if peerId == context.peerId, !isProfileIntended {
            self.savedMessages = SavedPeersController(context: context)
        } else {
            self.savedMessages = nil
        }
         if peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.CloudChannel, !isBot {
             self.gifts = PeerMediaGiftsController(context: context, peerId: peerId, starGiftsProfile: starGiftsProfile)
        } else {
            self.gifts = nil
        }
        self.interactions = ChatInteraction(chatLocation: .peer(peerId), context: context)
        self.mediaGrid = PeerMediaPhotosController(context, chatInteraction: interactions, threadInfo: threadInfo, peerId: peerId, tags: .photoOrVideo)
         if isBot {
             self.storyListContext = BotPreviewStoryListContext(account: context.account, engine: context.engine, peerId: peerId, language: nil, assumeEmpty: false)
         } else {
             self.storyListContext = PeerStoryListContext(account: context.account, peerId: peerId, isArchived: false, folderId: nil)
         }
         
        if peerId == context.peerId, threadInfo == nil, isProfileIntended {
            let archiveStoryListContext = PeerStoryListContext(account: context.account, peerId: peerId, isArchived: true, folderId: nil)
            self.archiveStoryListContext = archiveStoryListContext
            self.archiveStories = StoryMediaController(context: context, peerId: peerId, listContext: archiveStoryListContext, isArchived: true)
        } else {
            self.archiveStoryListContext = nil
            self.archiveStories = nil
        }
        self.saved = PeerMediaSavedMessagesController(context: context, peerId: peerId)
         
        var updateTitle:((ExternalSearchMessages)->Void)? = nil
        
        if let external = externalSearchData {
            modeValue.set(external.initialMode)
            let signal = (external.searchResult |> deliverOnMainQueue)
            externalDisposable.set(signal.start(next: { result in
                if let result = result {
                    updateTitle?(result)
                }
            }))
        }
        
        var listControllers: [PeerMediaListController<Context>] = []
        for _ in tagsList.filter ({ !$0.tagsValue.isEmpty }) {
            listControllers.append(PeerMediaListController(context: context, peerId: peerId, threadInfo: threadInfo, chatInteraction: interactions))
        }
        self.listControllers = listControllers
        
        self.members = PeerMediaGroupMembersController(context: context, peerId: peerId, editing: editing.get())
        self.commonGroups = PeerInfoNavigationHooks.shared.makeGroupsInCommonControllerObserved(context, peerId)
        self.gifs = PeerMediaPhotosController(context, chatInteraction: interactions, threadInfo: threadInfo, peerId: peerId, tags: .gif)
        self.stories = StoryMediaController(context: context, peerId: peerId, listContext: storyListContext)
        self.similarChannels = SimilarChannelsController(context: context, peerId: peerId, recommendedChannels: nil)
        self.similarBots = SimilarBotsController(context: context, peerId: peerId, recommendedBots: nil)

         
        super.init(context)
         
         
         
         self.stories.parentToggleSelection = { [weak self] in
             self?.changeState()
         }
         
         self.archiveStories?.parentToggleSelection = { [weak self] in
             self?.changeState()
         }
        
        updateTitle = { [weak self] result in
            if let title = result.title {
                self?.setCenterTitle(title)
            }
        }
         
        stories.parentController = self
        archiveStories?.parentController = self
    }

    var unableToHide: Bool {
        return self.genericView.activePanel is SearchContainerView || self.state != .Normal || !onTheTop
    }
     
    private(set) var isProfileBlockVisible: Bool = false

    func setProfileBlockVisible(_ visible: Bool) {
        guard isProfileBlockVisible != visible else {
            return
        }
        isProfileBlockVisible = visible
        genericView.setHeaderPinned(visible, animated: true)
        if visible {
            viewWillAppear(false)
            viewDidAppear(false)
        } else {
            viewWillDisappear(false)
            viewDidDisappear(false)
        }
    }
     
     var hasSearch: Bool {
         switch mode {
         case .commonGroups:
             return false
         case .stories, .archiveStories, .gifts:
             return false
         default:
             return self.externalSearchData == nil
         }
     }
     
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        interactions.add(observer: self)

        if let mode = self.mode {
            self.controller(for: mode).viewDidAppear(animated)
        }
        
        
        
        
        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            guard let `self` = self, !self.hasSearch else {
                return .rejected
            }
            if self.mode == .members {
                self.searchGroupUsers()
                return .invoked
            }
            if let mode = self.mode {
                (self.controller(for: mode) as? PeerMediaSearchable)?.toggleSearch()
            }
            return .invoked
        }, with: self, for: .F, modifierFlags: [.command])
        
        window?.set(handler: { [weak self] _ -> KeyHandlerResult in
            guard let `self` = self else {
                return .rejected
            }
            if self.genericView.searchPanelView != nil {
                return .rejected
            }
            return .invoked
        }, with: self, for: .Tab)
        
        guard let navigationController = self.navigationController, isProfileIntended else {
            return
        }
        if let controller = navigationController.controller as? PeerInfoController<Context> {
            controller.swapNavigationBar(leftView: self.leftBarView, centerView: self.centerBarView, rightView: self.rightBarView, animation: .crossfade)
            
        }

    }
     
     public override var barIsReal: Bool {
         return context.peerId == self.peerId && !isProfileIntended
     }
     
     public override func requestUpdateRightBar() {
         super.requestUpdateRightBar()
         editButton?.set(color: theme.colors.text, for: .Normal)
         rightBarView?.needsLayout = true
     }

     public override func updateEditStateTitles() {
         guard let editButton else { return }
         let pillHeight = StackedBarView.pillHeight
         switch state {
         case .Normal:
             editButton.set(image: theme.icons.chatActions, for: .Normal)
             editButton.set(text: "", for: .Normal)
             _ = editButton.sizeToFit(.zero, NSMakeSize(pillHeight, pillHeight), thatFit: true)
         case .Edit:
             editButton.removeImage(for: .Normal)
             editButton.set(text: doneString, for: .Normal)
             _ = editButton.sizeToFit(NSMakeSize(20, 0), NSMakeSize(.greatestFiniteMagnitude, pillHeight), thatFit: false)
         case .Some:
             editButton.removeImage(for: .Normal)
             editButton.set(text: someString, for: .Normal)
             _ = editButton.sizeToFit(NSMakeSize(20, 0), NSMakeSize(.greatestFiniteMagnitude, pillHeight), thatFit: false)
         }
     }

     public override func changeState() {
         if state == .Normal {
             editButton?.showContextMenu()
         } else {
             super.changeState()
         }
     }
     
     
     func setMode(_ mode: PeerMediaCollectionMode) {
         self.toggle(with: mode, animated: true)
     }
     
     public override func loadView() {
         super.loadView()

         let searchBtn = stackedBar.insertButton(at: 0, image: theme.icons.chatSearch) { [weak self] in
             guard let self = self else { return }
             if let mode = self.mode, self.hasSearch {
                 switch mode {
                 case .members:
                     self.searchGroupUsers()
                 default:
                     (self.controller(for: mode) as? PeerMediaSearchable)?.toggleSearch()
                 }
             }
         }
         self.searchBarButton = searchBtn

         editButton?.contextMenu = { [weak self] in
             var items:[ContextMenuItem] = []
             if let menuItems = self?.currentController?.menuItems(), !menuItems.isEmpty {
                 items.append(ContextSeparatorItem())
                 items.append(contentsOf: menuItems)
             } else {
                 items.append(ContextMenuItem(strings().chatContextEdit1, handler: { [weak self] in
                     self?.update(with: .Edit)
                 }, itemImage: MenuAnimation.menu_edit.value))
             }
             let menu = ContextMenu(betterInside: true)
             for item in items {
                 menu.addItem(item)
             }
             return menu
         }

         requestUpdateRightBar()
     }

    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        interactions.remove(observer: self)
        
        if let mode = mode {
            let controller = self.controller(for: mode)
            controller.viewDidDisappear(animated)
            if let controller = controller as? PeerMediaSearchable {
                controller.setSearchValue(.single(.init(state: .None, request: nil)))
            }
        }
        
        if let navigationController = navigationController, isProfileIntended {
            navigationController.controller.swapNavigationBar(leftView: navigationController.controller.leftBarView, centerView: navigationController.controller.centerBarView, rightView: navigationController.controller.rightBarView, animation: .crossfade)
        }
    }
    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        applyCaptureExclusionIfNeeded()

        if let mode = mode {
            let controller = self.controller(for: mode)
            controller.viewWillAppear(animated)
        }
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        window?.removeAllHandlers(for: self)

        if let mode = mode {
            let controller = self.controller(for: mode)
            controller.viewWillDisappear(animated)
        }
    }

    private func updateCaptureExclusion(_ isProtected: Bool) {
        isCaptureProtected = isProtected
        if isProtected {
            if captureExclusionToken == nil, let window = self.window {
                captureExclusionToken = context.captureExclusionManager.addExclusion(for: window, view: genericView)
                captureExclusionWindow = window
            }
        } else {
            removeCaptureExclusion()
        }
    }

    private func applyCaptureExclusionIfNeeded() {
        if isCaptureProtected, captureExclusionToken == nil, let window = self.window {
            captureExclusionToken = context.captureExclusionManager.addExclusion(for: window, view: genericView)
            captureExclusionWindow = window
        }
    }

    private func removeCaptureExclusion() {
        if let token = captureExclusionToken, let window = captureExclusionWindow {
            context.captureExclusionManager.removeExclusion(token, for: window)
        }
        captureExclusionToken = nil
        captureExclusionWindow = nil
    }
    
    public func notify(with value: Any, oldValue: Any, animated: Bool) {
        if let value = value as? ChatPresentationInterfaceState, let oldValue = oldValue as? ChatPresentationInterfaceState {
            
            let context = self.context
            if value.selectionState != oldValue.selectionState {
                if let selectionState = value.selectionState {
                    let ids = Array(selectionState.selectedIds)
                    loadSelectionMessagesDisposable.set((context.account.postbox.messagesAtIds(ids) |> deliverOnMainQueue).start( next:{ [weak self] messages in
                        var canDelete:Bool = !ids.isEmpty
                        var canForward:Bool = !ids.isEmpty
                        if let interactions = self?.interactions {
                            for message in messages {
                                if !canDeleteMessage(message, account: context.account, chatLocation: interactions.chatLocation, mode: .history) {
                                    canDelete = false
                                }
                                if !canForwardMessage(message, chatInteraction: interactions) {
                                    canForward = false
                                }
                            }
                            interactions.update({$0.withUpdatedBasicActions((canDelete, canForward))})
                        }
                       
                    }))
                } else {
                    interactions.update({$0.withUpdatedBasicActions((false, false))})
                }
            }
            
            if (value.state == .selecting) != (oldValue.state == .selecting) {
                self.state = value.state == .selecting ? .Edit : .Normal

                if let bar = rightBarView {
                    let transition: ContainedViewLayoutTransition = .animated(duration: 0.3, curve: .spring)
                    _ = bar.fit(to: bar.frame.width, transition: transition)
                    bar.updateLayout(size: bar.frame.size, transition: transition)
                }

                genericView.changeState(selectState: value.state == .selecting && self.mode != .members && self.mode != .stories && self.mode != .archiveStories, animated: animated)
            }
            
        }
    }
    
    
    public func isEqual(to other: Notifable) -> Bool {
        if let other = other as? PeerMediaController {
            return self == other
        }
        return false
    }
     
     public override func readyOnce() {
         let didSetReady = self.didSetReady
         super.readyOnce()
         
         if !didSetReady, let mode = initialMode {
             self.applyReadyController(mode: mode, animated: false)
         }
         
     }
     
     func selectStoryAlbum(_ album: Int32) {
         self.stories.selectAlbum(album)
     }
     func selectGiftsAlbum(_ album: Int32) {
        let arguments = (self.gifts as? InputDataController)?.contextObject_second as? PeerMediaGiftsExternalArguments
         arguments?.setAlbum(album)
     }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        

        
        genericView.updateInteraction(interactions)

        genericView.didMoveToWindow = { [weak self] in
            guard let self else { return }
            if let peerView = self.peerView, let peer = peerViewMainPeer(peerView) {
                let isProtected = peer.id.isSecretChat || peer.isCopyProtected(cachedData: peerView.cachedData)
                self.updateCaptureExclusion(isProtected)
            }
            if let window = self.genericView.window as? Window {
                window.remove(object: self.genericView, for: .scrollWheel)
                window.set(mouseHandler: { [weak self] event -> KeyHandlerResult in
                    return self?.handleTabSwipe(event) ?? .rejected
                }, with: self.genericView, for: .scrollWheel, priority: .modal)
            }
        }

        if externalSearchData != nil {
            updateSearchBarVisibility(false, animated: false)
        }

        
        let tabsOrder = self.tabsOrder
        
        let context = self.context
        let peerId = self.peerId
        let threadInfo = self.threadInfo
        let isProfileIntended = self.isProfileIntended
        let initialMode = self.initialMode
        
        let membersTab:Signal<(tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool), NoError>
        let storiesTab:Signal<(tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool), NoError>
        let archiveStoriesTab:Signal<(tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool), NoError>
        let commonGroupsTab:Signal<(tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool), NoError>
        let similarChannels:Signal<(tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool), NoError>
        let similarBots:Signal<(tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool), NoError>
        let savedMessagesTab:Signal<(tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool), NoError>
        let giftsTab:Signal<(tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool), NoError>
        let savedTab:Signal<(tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool), NoError>
        let pollsTab:Signal<(tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool), NoError>

        
        giftsTab = context.account.postbox.peerView(id: peerId) |> map { view -> (exist: Bool, loaded: Bool) in
            if let cachedData = view.cachedData as? CachedUserData {
                if let starGiftsCount = cachedData.starGiftsCount, starGiftsCount > 0 {
                    return (exist: true, loaded: true)
                }
            }
            if let cachedData = view.cachedData as? CachedChannelData {
                if let starGiftsCount = cachedData.starGiftsCount, starGiftsCount > 0 {
                    return (exist: !cachedData.isNotAccessible, loaded: true)
                }
            }
            return (exist: false, loaded: true)
        } |> map { data -> (tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool) in
            return (tag: .gifts, exists: data.exist, hasLoaded: data.loaded)
        }

        
        membersTab = context.account.postbox.peerView(id: peerId) |> map { view -> (exist: Bool, loaded: Bool) in
            if threadInfo != nil {
                return (exist: false, loaded: true)
            }
            if (view.cachedData as? CachedGroupData) != nil {
                return (exist: true, loaded: true)
            } else if let cachedData = view.cachedData as? CachedChannelData {
                if let peer = peerViewMainPeer(view), peer.isSupergroup || peer.isGigagroup, !peer.isMonoForum {
                    return (exist: !cachedData.isNotAccessible, loaded: true)
                } else {
                    return (exist: false, loaded: true)
                }
            } else {
                return (exist: false, loaded: true)
            }
        } |> map { data -> (tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool) in
            return (tag: .members, exists: data.exist, hasLoaded: data.loaded)
        }
        
        commonGroupsTab = context.account.postbox.peerView(id: peerId) |> map { view -> (exist: Bool, loaded: Bool) in
            if threadInfo != nil {
                return (exist: false, loaded: true)
            }
            if view.peerId.namespace == Namespaces.Peer.SecretChat {
                return (exist: false, loaded: false)
            }
            if let cachedData = view.cachedData as? CachedUserData {
                return (exist: cachedData.commonGroupCount > 0, loaded: true)
            } else {
                return (exist: false, loaded: true)
            }
        } |> map { data -> (tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool) in
            return (tag: .commonGroups, exists: data.exist, hasLoaded: data.loaded)
        }
        
        if threadInfo == nil, peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.CloudChannel {
            storiesTab = storyListContext.state |> map { state -> (exist: Bool, loaded: Bool) in
                return (exist: state.totalCount > 0, loaded: true)
            } |> map { data -> (tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool) in
                return (tag: .stories, exists: data.exist, hasLoaded: data.loaded)
            }
        } else {
            storiesTab = .single((tag: .stories, exists: false, hasLoaded: true))
        }
        
        if let archiveStoryListContext {
            archiveStoriesTab = archiveStoryListContext.state |> map { state -> (exist: Bool, loaded: Bool) in
                return (exist: state.totalCount > 0, loaded: true)
            } |> map { data -> (tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool) in
                return (tag: .archiveStories, exists: data.exist, hasLoaded: data.loaded)
            }
        } else {
            archiveStoriesTab = .single((tag: .archiveStories, exists: false, hasLoaded: true))
        }
        
        
        if threadInfo == nil, peerId.namespace == Namespaces.Peer.CloudChannel {
            similarChannels = context.engine.peers.recommendedChannels(peerId: peerId) |> map { channels -> (exist: Bool, loaded: Bool) in
                return (exist: (channels?.channels.count ?? 0) > 0, loaded: true)
            } |> map { data -> (tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool) in
                return (tag: .similarChannels, exists: data.exist, hasLoaded: data.loaded)
            }
        } else {
            similarChannels = .single((tag: .similarChannels, exists: false, hasLoaded: true))
        }
        
        if threadInfo == nil, peerId.namespace == Namespaces.Peer.CloudUser {
            similarBots = context.engine.peers.recommendedBots(peerId: peerId) |> map { bots -> (exist: Bool, loaded: Bool) in
                return (exist: (bots?.bots.count ?? 0) > 0, loaded: true)
            } |> map { data -> (tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool) in
                return (tag: .similarBots, exists: data.exist, hasLoaded: data.loaded)
            }
        } else {
            similarBots = .single((tag: .similarBots, exists: false, hasLoaded: true))
        }
        
        if threadInfo == nil, peerId == context.peerId, !isProfileIntended {
            let savedKeyId = PostboxViewKey.savedMessagesIndex(peerId: context.peerId)
            let viewSignal: Signal<Int, NoError> = context.account.postbox.combinedView(keys: [savedKeyId]) |> map {
                return ($0.views[savedKeyId] as? MessageHistorySavedMessagesIndexView)?.items.count ?? 0
            }

            savedMessagesTab = viewSignal |> map { state -> (exist: Bool, loaded: Bool) in
                return (exist: state > 0, loaded: true)
            } |> map { data -> (tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool) in
                return (tag: .savedMessages, exists: data.exist, hasLoaded: data.loaded)
            }
        } else {
            savedMessagesTab = .single((tag: .savedMessages, exists: false, hasLoaded: true))
        }
        
        if peerId != context.peerId, threadInfo == nil {
            savedTab = context.account.viewTracker.aroundMessageOfInterestHistoryViewForLocation(.peer(peerId: context.peerId, threadId: peerId.toInt64()), count: 3, tag: nil)
            |> map { (view, _, _) -> (tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool) in
                let hasLoaded = view.entries.count >= 1 || (!view.isLoading)
                return (tag: .saved, exists: !view.entries.isEmpty, hasLoaded: hasLoaded)
            }
        } else {
            savedTab = .single((tag: .saved, exists: false, hasLoaded: true))
        }
        
        if peerId != context.peerId {
            pollsTab = context.account.viewTracker.aroundMessageOfInterestHistoryViewForLocation(.peer(peerId: peerId, threadId: nil), count: 3, tag: .tag(.polls))
            |> map { (view, _, _) -> (tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool) in
                let hasLoaded = view.entries.count >= 1 || (!view.isLoading)
                return (tag: .polls, exists: !view.entries.isEmpty, hasLoaded: hasLoaded)
            }
        } else {
            pollsTab = .single((tag: .polls, exists: false, hasLoaded: true))
        }
        
       

        let location: ChatLocationInput
        if let threadInfo = threadInfo {
            location = context.chatLocationInput(for: .thread(threadInfo.message), contextHolder: threadInfo.contextHolder)
        } else {
            location = .peer(peerId: peerId, threadId: nil)
        }
        
        let tabItems: [Signal<(tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool), NoError>] = self.tagsList.filter { !$0.tagsValue.isEmpty }.map { tags -> Signal<(tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool), NoError> in
            return context.account.viewTracker.aroundMessageOfInterestHistoryViewForLocation(location, count: 3, tag: .tag(tags.tagsValue))
            |> map { (view, _, _) -> (tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool) in
                let hasLoaded = view.entries.count >= 1 || (!view.isLoading)
                return (tag: tags, exists: !view.entries.isEmpty && (!isProfileIntended || (context.peerId != peerId)), hasLoaded: hasLoaded)
            }
        }
        
        let mainTab = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.ProfileMainTab(id: peerId))
        
        let mergedTabs = combineLatest(membersTab, combineLatest(tabItems), commonGroupsTab, storiesTab, archiveStoriesTab, similarChannels, similarBots, savedMessagesTab, savedTab, giftsTab, pollsTab, mainTab) |> map { members, general, commonGroups, stories, archiveStories, similarChannels, similarBots, savedMessagesTab, savedTab, giftsTab, pollsTab, mainTab -> [(tag: PeerMediaCollectionMode, exists: Bool, hasLoaded: Bool)] in
            var general = general
            var bestIndex: Int = 0
            for general in general {
                if general.tag == .photoOrVideo && general.exists {
                    bestIndex += 1
                    break
                }
            }
            general.insert(savedTab, at: bestIndex)
            general.append(pollsTab)
            general.insert(members, at: 0)
            general.append(commonGroups)
            general.insert(archiveStories, at: 0)
            general.insert(giftsTab, at: 0)
            general.insert(stories, at: 0)
            general.append(similarChannels)
            general.append(similarBots)
            general.insert(savedMessagesTab, at: 0)
            
            if let mainTab {
                if let firstIndex = general.firstIndex(where: { $0.tag.profileTab == mainTab }) {
                    general.move(at: firstIndex, to: 0)
                }
            }
            
            return general
        }
        
        let tabSignal = combineLatest(queue: .mainQueue(), mergedTabs, modeValue.get())
        |> map { tabs, selected -> (tabs: [PeerMediaCollectionMode], selected: PeerMediaCollectionMode?, hasLoaded: Bool) in
            var selectedValue = selected
            if selected == nil || !tabs.contains(where: { $0.exists && $0.tag == selected }) {
                if let selected = selected {
                    let index = tabsOrder.firstIndex(of: selected)!
                    var perhapsBest: PeerMediaCollectionMode?
                    for i in stride(from: index, to: -1, by: -1) {
                        if tabs.contains(where: { $0.exists && $0.tag == tabsOrder[i] }) {
                            perhapsBest = tabsOrder[i]
                            break
                        }
                    }
                    selectedValue = perhapsBest ?? tabs.filter { $0.exists }.last?.tag ?? selected
                } else {
                    selectedValue = initialMode ?? tabs.filter { $0.exists }.first?.tag
                }
                
            }
            return (tabs: tabs.filter { $0.exists }.map { $0.tag }, selected: selectedValue, hasLoaded: tabs.first?.hasLoaded ?? false)
        }
        
        tabsSignal.set(tabSignal)
        
        let distinctTabs: Signal<(tabs: [PeerMediaCollectionMode], selected: PeerMediaCollectionMode?, hasLoaded: Bool), NoError> = tabsSignal.get()
        |> distinctUntilChanged(isEqual: { lhs, rhs in
            return lhs.tabs == rhs.tabs && lhs.selected == rhs.selected && lhs.hasLoaded == rhs.hasLoaded
        })

        let data: Signal<(tabs: [PeerMediaCollectionMode], selected: PeerMediaCollectionMode?, hasLoaded: Bool), NoError> = distinctTabs |> deliverOnMainQueue |> mapToSignal { [weak self] data in
            guard let `self` = self else {
                return .complete()
            }
            if let selected = data.selected, let controller = self.prepareController(for: selected) {
                return controller.ready.get() |> map { _ in
                    return data
                }
            } else {
                return .single(data)
            }
        }
        |> distinctUntilChanged(isEqual: { lhs, rhs -> Bool in
            if lhs.tabs != rhs.tabs {
                return false
            }
            if lhs.hasLoaded != rhs.hasLoaded {
                return false
            }
            if lhs.selected != rhs.selected {
                return false
            }
            return true
        })
        
        let ready = data |> map { _ in return true }
        
        genericView.tabsView.didSelect = { [weak self] id in
            guard let self, let newMode = PeerMediaCollectionMode(rawValue: Int32(id)) else {
                return
            }
            if newMode == self.mode, let mainTable = self.genericView.mainTable {
                self.currentMainTableView?(mainTable, true, true)
            }
            if let index = self.genericView.tabsView.index(of: id) {
                self.genericView.tabsView.setSelection(position: CGFloat(index), animated: true)
            }
            self.modeValue.set(newMode)
        }
        
        if let starGiftsProfile = self.starGiftsProfile {
            let icons = starGiftsProfile.state
            |> map { Array($0.gifts.prefix(3)) }
            |> distinctUntilChanged
            |> deliverOnMainQueue
            giftIconsDisposable.set(icons.start(next: { [weak self] icons in
                guard let self else {
                    return
                }
                self.giftIcons = icons
                self.updateTabsView(animated: true)
            }))
        }
        
        
        interactions.forwardMessages = { messages in
            showModal(with: ShareModalController(ForwardMessagesObject(context, messages: messages)), for: context.window)
        }
        
        let openChat:(PeerId, ChatFocusTarget?)->Void = { [weak self] id, focusTarget in
            let location: ChatLocation
            let mode: ChatMode
            if let threadInfo = threadInfo, peerId == id {
            
                location = .thread(threadInfo.message)
                if threadInfo.isMonoforumPost {
                    mode = .history
                } else {
                    mode = .thread(mode: .topic(origin: threadInfo.message.effectiveTopId))
                }
            } else {
                location = .peer(id)
                mode = .history
            }
            PeerInfoUIHooks.shared.navigateToChatObserved(self?.navigationController, context, location, mode, focusTarget, threadInfo?.contextHolder)

        }
        
        interactions.focusMessageId = { _, focusMessageId, _ in
            openChat(peerId, focusMessageId)
        }
        
        interactions.inlineAudioPlayer = { [weak self] controller in
            guard let navigation = self?.navigationController else {
                return
            }
            let tableView = (navigation.first { $0 is ChatController<Context>} as? ChatController<Context>)?.genericView.tableView
            PeerInfoUIHooks.shared.showInlineAudioPlayer(controller, context, tableView, self?.currentTable)
        }
        
        let openInfo: (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void = { [weak self] peerId, toChat, postId, action in
            if let strongSelf = self {
                if toChat {
                    openChat(peerId, .init(messageId: postId))
                } else {
                    if let navigation = strongSelf.navigationController {
                        PeerInfoController<Context>.push(navigation: navigation, context: context, peerId: peerId, threadInfo: threadInfo)
                    }
                }
            }
        }
        
        interactions.openInfo = { peerId, toChat, postId, action in
            openInfo(peerId, toChat, postId, action)
        }

        interactions.deleteMessages = { [weak self] messageIds, _ in
            if let strongSelf = self, let peer = strongSelf.peer {
                
                let adminsPromise = ValuePromise<[RenderedChannelParticipant]>([])
                _ = context.peerChannelMemberCategoriesContextsManager.admins(peerId: peerId, updated: { membersState in
                    if case .loading = membersState.loadingState, membersState.list.isEmpty {
                        adminsPromise.set([])
                    } else {
                        adminsPromise.set(membersState.list)
                    }
                })
                
                
                self?.messagesActionDisposable.set(combineLatest(queue: .mainQueue(), context.account.postbox.messagesAtIds(messageIds), adminsPromise.get()).start( next:{ [weak strongSelf] messages, admins in
                    if let strongSelf = strongSelf {
                        var canDelete:Bool = true
                        var canDeleteForEveryone = true
                        var otherCounter:Int32 = 0
                        var _mustDeleteForEveryoneMessage: Bool = true
                        for message in messages {
                            if !canDeleteMessage(message, account: context.account, chatLocation: strongSelf.interactions.chatLocation, mode: .history) {
                                canDelete = false
                            }
                            if !mustDeleteForEveryoneMessage(message) {
                                _mustDeleteForEveryoneMessage = false
                            }
                            if !canDeleteForEveryoneMessage(message, context: context) {
                                canDeleteForEveryone = false
                            } else {
                                if message.effectiveAuthor?.id != context.peerId && !(context.limitConfiguration.canRemoveIncomingMessagesInPrivateChats && message.peers[message.id.peerId] is TelegramUser)  {
                                    if let peer = message.peers[message.id.peerId] as? TelegramGroup {
                                        inner: switch peer.role {
                                        case .member:
                                            otherCounter += 1
                                        default:
                                            break inner
                                        }
                                    } else {
                                        otherCounter += 1
                                    }
                                }
                            }
                        }
                        
                        if otherCounter > 0 || peer.id == context.peerId {
                            canDeleteForEveryone = false
                        }
                        if messages.isEmpty {
                            strongSelf.interactions.update({$0.withoutSelectionState()})
                            return
                        }
                        
                        let context = strongSelf.context
                        
                        if canDelete {
                            let isAdmin = admins.filter({$0.peer.id == messages[0].author?.id}).first != nil
                            if mustManageDeleteMessages(messages, for: peer, account: strongSelf.context.account), let memberId = messages[0].author?.id, !isAdmin {
                                
                                let options:[ModalOptionSet] = [ModalOptionSet(title: strings().supergroupDeleteRestrictionDeleteMessage, selected: true, editable: true),
                                                                ModalOptionSet(title: strings().supergroupDeleteRestrictionBanUser, selected: false, editable: true),
                                                                ModalOptionSet(title: strings().supergroupDeleteRestrictionReportSpam, selected: false, editable: true),
                                                                ModalOptionSet(title: strings().supergroupDeleteRestrictionDeleteAllMessages, selected: false, editable: true)]
                                showModal(with: ModalOptionSetController(context: context, options: options, actionText: (strings().modalOK, theme.colors.accent), title: strings().supergroupDeleteRestrictionTitle, result: { [weak strongSelf] result in
                                    
                                    var signals:[Signal<Void, NoError>] = []
                                    if result[0] == .selected {
                                        signals.append(context.engine.messages.deleteMessagesInteractively(messageIds: messages.map {$0.id}, type: .forEveryone))
                                    }
                                    if result[1] == .selected {
                                        signals.append(context.peerChannelMemberCategoriesContextsManager.updateMemberBannedRights(peerId: peer.id, memberId: memberId, bannedRights: TelegramChatBannedRights(flags: [.banReadMessages], untilDate: Int32.max)))
                                    }
                                    if result[2] == .selected {
                                        signals.append(context.engine.peers.reportPeerMessages(messageIds: messageIds, reason: .spam, message: ""))
                                    }
                                    if result[3] == .selected {
                                        signals.append(context.engine.messages.clearAuthorHistory(peerId: peer.id, memberId: memberId))
                                    }
                                    
                                    _ = showModalProgress(signal: combineLatest(signals), for: context.window).start()
                                    strongSelf?.interactions.update({$0.withoutSelectionState()})
                                    
                                }), for: context.window)
                            } else {
                                let thrid:String? = (canDeleteForEveryone ? peer.isUser ? strings().chatMessageDeleteForMeAndPerson(peer.compactDisplayTitle) : strings().chatConfirmDeleteMessagesForEveryone : nil)
                                
                                verifyAlert(for: context.window, header: thrid == nil ? strings().chatConfirmActionUndonable : strings().chatConfirmDeleteMessages1Other(messages.count), information: thrid == nil ? _mustDeleteForEveryoneMessage ? strings().chatConfirmDeleteForEveryoneOther(messages.count) : strings().chatConfirmDeleteMessages1Other(messages.count) : nil, ok: strings().confirmDelete, option: thrid, successHandler: { [weak strongSelf] result in
                                    
                                    guard let `strongSelf` = strongSelf else {
                                        return
                                    }
                                    let type:InteractiveMessagesDeletionType
                                    switch result {
                                    case .basic:
                                        type = .forLocalPeer
                                    case .thrid:
                                        type = .forEveryone
                                    }
                                    _ = context.engine.messages.deleteMessagesInteractively(messageIds: messageIds, type: type).start()
                                    strongSelf.interactions.update({$0.withoutSelectionState()})
                                })
                            }
                        }
                    }
                }))
            }
        }
        
        let peerSignal = context.account.viewTracker.peerView(peerId) |> deliverOnMainQueue |> beforeNext({ [weak self] peerView in
            self?.peer = peerView.peers[peerView.peerId]
            self?.peerView = peerView
        }) |> map { view -> Bool in
            return true
        }
        
        let combined = combineLatest( [peerSignal |> take(1), ready, self.tabsSignal.get() |> map { $0.hasLoaded }] ) |> map { result -> Bool in
            return result[0] && result[1] && result[2]
        }
        
        self.ready.set(combined |> deliverOnMainQueue)
        
    
        
        var firstTabAppear = true
        tabsDisposable.set((data |> deliverOnMainQueue).start(next: { [weak self] tabs, selected, hasLoaded in
            if hasLoaded, let `self` = self {
                self.currentTabs = (tabs: tabs, selected: selected)
                self.updateTabsView(animated: !firstTabAppear)
                self.prepareNeighborTabs()

                if context.peerId == peerId || peer?.groupAccess.canEditGroupInfo == true {
                    self.genericView.tabsView.menuItems = { id, index in
                        let mediaTab = PeerMediaCollectionMode(rawValue: Int32(id))
                        var items: [ContextMenuItem] = []
                        if index != 0, let profileTab = mediaTab?.profileTab {
                            items.append(ContextMenuItem(
                                strings().profileTabContextMenuSetAsMain,
                                handler: {
                                    _ = context.engine.peers.setMainProfileTab(peerId: peerId, tab: profileTab).start()
                                }
                            ))
                        }
                        return items
                    }
                } else {
                    self.genericView.tabsView.menuItems = nil
                }
                
                self.genericView.updateEmpty(tabs.isEmpty, animated: !firstTabAppear)
                if let selected = selected {
                    self.toggle(with: selected, animated: !firstTabAppear)
                }
                
                firstTabAppear = false
                
                if tabs.isEmpty, self.isProfileIntended {
                    if self.genericView.superview != nil {
                        self.viewWillDisappear(true)
                        self.genericView.removeFromSuperview()
                        self.viewDidDisappear(true)
                    }
                }
            }
        }))
        
    
        let storiesCount = self.storyListContext.state |> map { Int32($0.totalCount) }
        let commonGroupsCount = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.CommonGroupCount(id: peerId)) |> map { Int32($0 ?? 0) }
        let similarChannelsCount = context.engine.peers.recommendedChannels(peerId: peerId) |> map { $0?.count ?? 0 }
        let similarBotsCount = context.engine.peers.recommendedBots(peerId: peerId) |> map { Int32($0?.bots.count ?? 0) }

        let savedMessagesCount: Signal<Int32, NoError> = context.engine.messages.savedMessagesPeersStats() |> map { Int32($0 ?? 0) }

        
        let savedCount = self.context.engine.data.subscribe(
        TelegramEngine.EngineData.Item.Messages.MessageCount(peerId: self.context.account.peerId, threadId: peerId.toInt64(), tag: [])
        ) |> map { Int32($0 ?? 0) }

        
        let archiveStoriesCount: Signal<Int32, NoError>
        if let archiveStoryListContext {
            archiveStoriesCount = archiveStoryListContext.state |> map { Int32($0.totalCount) }
        } else {
            archiveStoriesCount = .single(0)
        }
        let giftsCount: Signal<Int32, NoError> = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.StarGiftsCount(id: peerId)) |> map { $0 ?? 0 }
        
        
        
        var summaries: [MessageTags] = []
        summaries.append(.photo)
        summaries.append(.video)
        summaries.append(.gif)
        summaries.append(.file)
        summaries.append(.webPage)
        summaries.append(.voiceOrInstantVideo)
        summaries.append(.music)
        
        let mediaPeerId = threadInfo?.message.peerId ?? peerId
        let threadId = threadInfo?.message.threadId

        let counters: Signal<(PeerMediaCollectionMode?, [PeerMediaCollectionMode: Int32]), NoError> = combineLatest(self.modeValue.get(), context.engine.data.subscribe(EngineDataMap(
            summaries.map { TelegramEngine.EngineData.Item.Messages.MessageCount(peerId: mediaPeerId, threadId: threadId, tag: $0) }
        )), storiesCount, archiveStoriesCount, similarChannelsCount, similarBotsCount, commonGroupsCount, savedMessagesCount, savedCount, giftsCount)
        |> map { mode, summaries, storiesCount, archiveStoriesCount, similarChannelsCount, similarBotsCount, commonGroupsCount, savedMessagesCount, savedCount, giftsCount -> (PeerMediaCollectionMode?, [PeerMediaCollectionMode: Int32]) in
            var result: [PeerMediaCollectionMode: Int32] = [:]
            var photoOrVideo: Int32 = 0
            for (key, count) in summaries {
                switch key.tag {
                case .photo, .video:
                    photoOrVideo += count.flatMap(Int32.init) ?? 0
                case .gif:
                    result[.gifs] = count.flatMap(Int32.init) ?? 0
                case .file:
                    result[.file] = count.flatMap(Int32.init) ?? 0
                case .webPage:
                    result[.webpage] = count.flatMap(Int32.init) ?? 0
                case .voiceOrInstantVideo:
                    result[.voice] = count.flatMap(Int32.init) ?? 0
                case .music:
                    result[.music] = count.flatMap(Int32.init) ?? 0
                default:
                    break
                }
                result[.stories] = storiesCount
                result[.archiveStories] = archiveStoriesCount
                result[.similarChannels] = similarChannelsCount
                result[.commonGroups] = commonGroupsCount
                result[.photoOrVideo] = photoOrVideo
                result[.savedMessages] = savedMessagesCount
                result[.saved] = savedCount
                result[.gifts] = giftsCount
                result[.similarBots] = similarBotsCount
            }
            return (mode, result)
        } |> deliverOnMainQueue
        
                        
        statusDisposable.set(counters.start(next: { [weak self] mode, result in
            if let mode = mode, let count = result[mode].flatMap(Int.init) {
                let string: String?
                switch mode {
                case .photoOrVideo:
                    string = strings().sharedMediaMediaCountOther(count)
                case .file:
                    string = strings().sharedMediaFileCountOther(count)
                case .voice:
                    string = strings().sharedMediaVoiceCountOther(count)
                case .webpage:
                    string = strings().sharedMediaLinkCountOther(count)
                case .music:
                    string = strings().sharedMediaMusicCountOther(count)
                case .gifs:
                    string = strings().sharedMediaGifCountOther(count)
                case .archiveStories:
                    string = strings().sharedMediaArchiveStoryCountOther(count)
                case .stories:
                    if self?.peer?.isBot == true {
                        string = strings().sharedMediaBotPreviewCountOther(count)
                    } else {
                        string = strings().sharedMediaStoryCountOther(count)
                    }
                case .commonGroups:
                    string = strings().sharedMediaCommonGroupsCountOther(count)
                case .saved:
                    string = strings().sharedMediaSavedCountOther(count)
                case .savedMessages:
                    string = strings().sharedMediaSavedMessagesCountOther(count)
                case .similarChannels:
                    string = strings().sharedMediaSimilarCountOther(count)
                case .similarBots:
                    string = strings().sharedMediaSimilarBotsCountOther(count)
                case .members:
                    string = nil
                case .polls:
                    string = strings().peerMediaPolls
                case .gifts:
                    string = strings().sharedMediaStarGiftsOther(count)
                }
                if let string {
                    self?.centerBarView.status = .initialize(string: string, color: theme.colors.grayText, font: .normal(.text))
                }
            } else {
                let peerView = self?.peerView
                self?.peerView = peerView
            }
        }))
        
    }
     
     public override func viewDidResized(_ size: NSSize) {
         super.viewDidResized(size)
     }
    
    
    private var currentTable: TableView? {
        if self.mode == .photoOrVideo || self.mode == .members {
            return nil
        } else {
            return self.listControllers[currentTagListIndex].genericView
        }
    }
    
    private func applyReadyController(mode:PeerMediaCollectionMode, animated:Bool) {
        let oldMode = self.mode
        self.mode = mode
        let previous = self.currentController
        
        let controller = self.controller(for: mode)
        
        self.currentController = controller
        controller.viewWillAppear(animated)
        previous?.viewWillDisappear(animated)
        let isInteractive = self.interactiveSwitchMode == mode
        self.interactiveSwitchMode = nil
        if isInteractive {
            controller.view.setFrameSize(self.genericView.view.contentBounds.size)
        } else {
            controller.view.frame = self.genericView.view.contentBounds
        }
        let animation: PeerMediaAnimationDirection?
        
        if isInteractive {
            animation = .interactive
        } else if animated, let oldMode = oldMode {
            let prevIndex = self.genericView.tabsView.index(of: Int64(oldMode.rawValue)) ?? 0
            let newIndex = self.genericView.tabsView.index(of: Int64(mode.rawValue)) ?? 0

            if prevIndex > newIndex {
                animation = .rightToLeft
            } else {
                animation = .leftToRight
            }
        } else {
            animation = nil
        }
        
        genericView.updateMainView(with: controller.view, animated: animation)
        prepareNeighborTabs()
        controller.viewDidAppear(animated)
        previous?.viewDidDisappear(animated)
        searchValueDisposable.set(nil)
        
        
        updateSearchBarVisibility(self.hasSearch)
        
        
        if let controller = controller as? PeerMediaSearchable {
            
            if let externalSearchData = self.externalSearchData {
                controller.setExternalSearch(externalSearchData.searchResult, externalSearchData.loadMore)
            } else {
                searchValueDisposable.set(controller.mediaSearchValue.start(next: { [weak self, weak controller] state in
                    self?.genericView.updateSearchState(state, updateSearchState: { searchState in
                        controller?.setSearchValue(.single(searchState))
                    }, toggle: {
                        controller?.toggleSearch()
                    })
                }))
            }
        }
        
        self.currentMainTableView?(genericView.mainTable, animated, previous != controller && genericView.tabsView.contains(Int64(oldMode?.rawValue ?? -3)))
    }
    
    private func prepareController(for mode: PeerMediaCollectionMode) -> ViewController? {
        let bounds = self.genericView.view.bounds
        switch mode {
        case .members:
            if !self.members.isLoaded() {
                self.members.loadViewIfNeeded(bounds)
            }
            return self.members
        case .commonGroups:
            if !self.commonGroups.isLoaded() {
                self.commonGroups.loadViewIfNeeded(bounds)
            }
            return self.commonGroups
        case .similarChannels:
            if !self.similarChannels.isLoaded() {
                self.similarChannels.loadViewIfNeeded(bounds)
            }
            return self.similarChannels
        case .similarBots:
            if !self.similarBots.isLoaded() {
                self.similarBots.loadViewIfNeeded(bounds)
            }
            return self.similarBots
        case .photoOrVideo:
            if !self.mediaGrid.isLoaded() {
                if let externalSearchData = self.externalSearchData {
                    self.mediaGrid.setExternalSearch(externalSearchData.searchResult, externalSearchData.loadMore)
                }
                self.mediaGrid.loadViewIfNeeded(bounds)
            }
            return self.mediaGrid
        case .gifs:
            if !self.gifs.isLoaded() {
                if let externalSearchData = self.externalSearchData {
                    self.gifs.setExternalSearch(externalSearchData.searchResult, externalSearchData.loadMore)
                }
                self.gifs.loadViewIfNeeded(bounds)
            }
            return self.gifs
        case .stories:
            if !self.stories.isLoaded() {
                self.stories.loadViewIfNeeded(bounds)
            }
            return self.stories
        case .archiveStories:
            if let archiveStories = self.archiveStories {
                if !archiveStories.isLoaded() {
                    archiveStories.loadViewIfNeeded(bounds)
                }
                return archiveStories
            }
            return nil
        case .savedMessages:
            if let savedMessages = self.savedMessages {
                if !savedMessages.isLoaded() {
                    savedMessages.loadViewIfNeeded(bounds)
                }
                return savedMessages
            }
            return nil
        case .saved:
            if !self.saved.isLoaded() {
                self.saved.loadViewIfNeeded(bounds)
            }
            return self.saved
        case .gifts:
            if let gifts = self.gifts {
                if !gifts.isLoaded() {
                    gifts.loadViewIfNeeded(bounds)
                }
                return gifts
            }
            return nil
        case .polls:
            if self.pollsController == nil {
                self.pollsController = PeerMediaPollsController(context: self.context, peerId: self.peerId)
            }
            if let controller = self.pollsController {
                if !controller.isLoaded() {
                    controller.loadViewIfNeeded(bounds)
                }
                return controller
            }
            return nil
        default:
            let controller = self.listControllers[Int(mode.rawValue)]
            if !controller.isLoaded() {
                if let externalSearchData = self.externalSearchData {
                    controller.setExternalSearch(externalSearchData.searchResult, externalSearchData.loadMore)
                }
                controller.loadViewIfNeeded(bounds)
                controller.load(with: mode.tagsValue)
            }
            return controller
        }
    }
    
    private func tabSwipeFingerDelta(_ event: NSEvent) -> CGFloat {
        return System.isScrollInverted ? event.scrollingDeltaX : -event.scrollingDeltaX
    }
    
    private func isOverTabSwipeArea() -> Bool {
        guard self.externalSearchData == nil, self.state == .Normal, self.genericView.searchPanelView == nil, self.interactions.presentation.state != .selecting, (self.currentTabs?.tabs.count ?? 0) > 1 else {
            return false
        }
        guard let window = self.genericView.window, let contentView = window.contentView else {
            return false
        }
        let point = window.mouseLocationOutsideOfEventStream
        guard let hit = contentView.hitTest(contentView.convert(point, from: nil)), hit.isDescendant(of: self.genericView.view) else {
            return false
        }
        if hit.enclosingHorizontalScrollConsumer(atWindowPoint: point) != nil {
            return false
        }
        var view: NSView? = hit
        while let current = view, current !== self.genericView.view {
            if current is HorizontalTableView || current is HorizontalScrollView {
                return false
            }
            view = current.superview
        }
        return true
    }
    
    private func handleTabSwipe(_ event: NSEvent) -> KeyHandlerResult {
        if !event.momentumPhase.isEmpty {
            guard self.swallowsTabSwipeMomentum else {
                return .rejected
            }
            if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) {
                self.swallowsTabSwipeMomentum = false
            }
            return .invoked
        }
        
        let phase = event.phase
        if phase.isEmpty {
            return .rejected
        }
        if phase.contains(.mayBegin) || phase.contains(.began) {
            self.swallowsTabSwipeMomentum = false
            self.tabSwipe = TabSwipeGesture()
        }
        guard var current = self.tabSwipe else {
            return .rejected
        }
        let isEnd = phase.contains(.ended) || phase.contains(.cancelled)
        
        switch current.axis {
        case .undecided:
            if isEnd {
                self.tabSwipe = nil
                return .rejected
            }
            let deltaX = event.scrollingDeltaX
            let deltaY = event.scrollingDeltaY
            if deltaX == 0 && deltaY == 0 {
                if phase.contains(.began) {
                    current.beganPassedThrough = true
                }
                self.tabSwipe = current
                return .rejected
            }
            if abs(deltaX) > abs(deltaY), self.isOverTabSwipeArea() {
                if self.interactiveSwitchMode != nil {
                    current.axis = .blocked
                } else {
                    self.genericView.view.finishTransition()
                    current.axis = .horizontal
                    self.tabSwipeOffset = 0
                    self.trackTabSwipe(event, gesture: &current)
                }
                self.tabSwipe = current
                return .invoked
            }
            current.axis = .vertical
            self.tabSwipe = current
            return .rejected
        case .vertical:
            if isEnd {
                self.tabSwipe = nil
            }
            return .rejected
        case .blocked:
            if isEnd {
                self.tabSwipe = nil
                self.swallowsTabSwipeMomentum = true
            }
            return .invoked
        case .horizontal:
            if isEnd {
                self.tabSwipe = nil
                self.swallowsTabSwipeMomentum = true
                self.releaseTabSwipe(at: event.timestamp, samples: current.samples)
                return current.beganPassedThrough ? .rejected : .invoked
            }
            self.trackTabSwipe(event, gesture: &current)
            self.tabSwipe = current
            return .invoked
        }
    }
    
    private func trackTabSwipe(_ event: NSEvent, gesture: inout TabSwipeGesture) {
        let width = self.genericView.view.contentBounds.width
        guard width > 0, let tabs = self.currentTabs?.tabs, let mode = self.mode, let index = tabs.firstIndex(of: mode) else {
            return
        }
        let delta = self.tabSwipeFingerDelta(event)
        gesture.samples.append((timestamp: event.timestamp, delta: delta))
        let minOffset: CGFloat = self.genericView.view.hasNextPage ? -width : 0
        let maxOffset: CGFloat = self.genericView.view.hasPreviousPage ? width : 0
        let offset = min(max(self.tabSwipeOffset + delta, minOffset), maxOffset)
        self.tabSwipeOffset = offset
        self.genericView.view.updateSwipeOffset(offset)
        self.genericView.tabsView.setSelection(position: CGFloat(index) - offset / width, animated: false)
    }
    
    private func releaseTabSwipe(at timestamp: TimeInterval, samples: [(timestamp: TimeInterval, delta: CGFloat)]) {
        let width = self.genericView.view.contentBounds.width
        let recent = samples.filter { timestamp - $0.timestamp <= tabSwipeVelocityWindow }
        var velocity: CGFloat = 0
        if let first = recent.first {
            let span = max(CGFloat(timestamp - first.timestamp), 1.0 / 60.0)
            velocity = recent.reduce(CGFloat(0), { $0 + $1.delta }) / span
        }
        
        var target: PeerMediaCollectionMode?
        if self.tabSwipeOffset != 0, let tabs = self.currentTabs?.tabs, let mode = self.mode, let index = tabs.firstIndex(of: mode), tabs.indices.contains(self.tabSwipeOffset > 0 ? index - 1 : index + 1) {
            let neighbor = tabs[self.tabSwipeOffset > 0 ? index - 1 : index + 1]
            if abs(velocity) > tabSwipeSwitchVelocity {
                if (velocity > 0) == (self.tabSwipeOffset > 0) {
                    target = neighbor
                }
            } else if abs(self.tabSwipeOffset) > width * tabSwipeSwitchFraction {
                target = neighbor
            }
        }
        self.tabSwipeOffset = 0
        
        if let target = target, let index = self.currentTabs?.tabs.firstIndex(of: target) {
            self.interactiveSwitchMode = target
            self.genericView.tabsView.setSelection(position: CGFloat(index), animated: true)
            self.modeValue.set(target)
        } else {
            self.genericView.view.cancelSwipe(animated: true)
            if let mode = self.mode, let index = self.currentTabs?.tabs.firstIndex(of: mode) {
                self.genericView.tabsView.setSelection(position: CGFloat(index), animated: true)
            }
        }
    }
    
    private func prepareNeighborTabs() {
        var previous: NSView?
        var next: NSView?
        if self.externalSearchData == nil, let tabs = self.currentTabs?.tabs, let mode = self.mode, let index = tabs.firstIndex(of: mode) {
            if index > 0 {
                previous = self.prepareController(for: tabs[index - 1])?.view
            }
            if index < tabs.count - 1 {
                next = self.prepareController(for: tabs[index + 1])?.view
            }
        }
        self.genericView.view.setNeighborPages(previous: previous, next: next)
    }
    
    private func updateTabsView(animated: Bool) {
        guard let currentTabs = self.currentTabs else {
            return
        }
        let tabs = currentTabs.tabs.map { tab in
            PeerMediaTabsView.Tab(id: Int64(tab.rawValue), title: tab.title(self.peer), gifts: tab == .gifts ? self.giftIcons : [])
        }
        genericView.updateTabs(tabs, selected: currentTabs.selected.flatMap { Int64($0.rawValue) }, account: context.account, animated: animated)
    }
    
    func controller(for mode: PeerMediaCollectionMode) -> ViewController {
        switch mode {
        case .photoOrVideo:
            return self.mediaGrid
        case .members:
            return self.members
        case .commonGroups:
            return self.commonGroups
        case .similarChannels:
            return self.similarChannels
        case .similarBots:
            return self.similarBots
        case .gifs:
            return self.gifs
        case .stories:
            return stories
        case .archiveStories:
            if let archiveStories = self.archiveStories {
                return archiveStories
            } else {
                return ViewController()
            }
        case .savedMessages:
            if let savedMessages = self.savedMessages {
                return savedMessages
            } else {
                return ViewController()
            }
        case .saved:
            return saved
        case .polls:
            if let controller = self.pollsController {
                return controller
            } else {
                return ViewController()
            }
        case .gifts:
            if let gifts = self.gifts {
                return gifts
            } else {
                return ViewController()
            }
        default:
            return self.listControllers[Int(mode.rawValue)]
        }
    }
    
    private func toggle(with mode:PeerMediaCollectionMode, animated:Bool = false) {
        let isUpdated = self.mode != mode
        if isUpdated {
            let controller: ViewController = self.controller(for: mode)

            let ready = controller.ready.get() |> take(1)
            
            toggleDisposable.set(ready.start(next: { [weak self] _ in
                self?.applyReadyController(mode: mode, animated: animated)
            }))
        } else {
            toggleDisposable.set(nil)
            self.currentMainTableView?(genericView.mainTable, animated, false)
        }
        self.modeValue.set(mode)
    }
    
    deinit {
        removeCaptureExclusion()
        messagesActionDisposable.dispose()
        loadFwdMessagesDisposable.dispose()
        loadSelectionMessagesDisposable.dispose()
        tabsDisposable.dispose()
        giftIconsDisposable.dispose()
        toggleDisposable.dispose()
        onlineMemberCountDisposable.dispose()
        externalDisposable.dispose()
        statusDisposable.dispose()
        searchValueDisposable.dispose()
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        
        for controller in self.listControllers {
            if controller.isLoaded() {
                controller.updateLocalizationAndTheme(theme: theme)
            }
        }
    }
    
    override public func update(with state:ViewControllerState) -> Void {
        super.update(with:state)
        interactions.update({state == .Normal ? $0.withoutSelectionState() : $0.withSelectionState()})
    }
    
    public override func escapeKeyAction() -> KeyHandlerResult {
        if genericView.searchPanelView != nil {
            if let mode = self.mode {
                (self.controller(for: mode) as? PeerMediaSearchable)?.toggleSearch()
                return .invoked
            } else {
                return super.escapeKeyAction()
            }
        } else if interactions.presentation.state == .selecting {
            interactions.update { $0.withoutSelectionState() }
            return .invoked
        } else {
            return super.escapeKeyAction()
        }
    }
     
     var onTheTop: Bool {
         switch self.mode {
         case .photoOrVideo:
             return self.mediaGrid.onTheTop
         default:
             return true
         }
     }
    
    private weak var searchBarButton: ImageButton?

    private func updateSearchBarVisibility(_ visible: Bool, animated: Bool = true) {
        if let searchBtn = searchBarButton {
            stackedBar.change(opacity: visible ? 1 : 0, for: searchBtn, animated: animated)
        }
    }
    
    private func searchGroupUsers() {
        _ = (selectModalPeers(window: context.window, context: context, title: strings().selectPeersTitleSearchMembers, behavior: peerId.namespace == Namespaces.Peer.CloudGroup ? SelectGroupMembersBehavior(peerId: peerId, limit: 1, settings: []) : SelectChannelMembersBehavior(peerId: peerId, peerChannelMemberContextsManager: context.peerChannelMemberCategoriesContextsManager, limit: 1, settings: [])) |> deliverOnMainQueue |> map {$0.first}).start(next: { [weak self] peerId in
            if let peerId = peerId, let context = self?.context {
                PeerInfoController<Context>.push(navigation: context.bindings.rootNavigation(), context: context, peerId: peerId)
            }
        })
    }
    
    public override func becomeFirstResponder() -> Bool? {
        return true
    }
    
    public override func firstResponder() -> NSResponder? {
        return genericView.searchPanelView?.searchView.input
    }
    
    public override var defaultBarTitle: String {
        if peerId == context.peerId, !isProfileIntended {
            return strings().peerSavedMessages
        } else {
            return localizedString("Telegram.PeerMediaController")
        }
    }
     
     public override func setCenterTitle(_ text: String) {
         
     }
     public override func setCenterStatus(_ text: String?) {
         
     }
     
     public override var defaultBarStatus: String? {
         return nil
     }
    
    
    public override func didRemovedFromStack() {
        super.didRemovedFromStack()
    }
    
    
    
    public override func initializer() -> PeerMediaContainerView {
        return PeerMediaContainerView(frame: initializationRect, isSegmentHidden: self.externalSearchData != nil)
    }
    
 }
 
 
 

