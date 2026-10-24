import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import InAppSettings
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import StoriesUI
import InlineStickerLayer

public class ChatListRevealItem: TableStickItem {
    fileprivate let action:((ChatListFilter)->Void)?
    fileprivate let context: (any AccountContextProtocol)?
    fileprivate let tabs: [ChatListFilter]
    fileprivate let selected: ChatListFilter
    fileprivate let openSettings: (()->Void)?
    fileprivate let counters: ChatListFilterBadges
    fileprivate let presentation: TelegramPresentationTheme
    fileprivate let _menuItems: ((ChatListFilter, Int?, Bool?)->[ContextMenuItem])?
    fileprivate let getCurrentStoriesState:()->(StoryListChatListRowItem.InterfaceState, NSView)?
    fileprivate let customBackgroundColor: NSColor?
    public init(_ initialSize: NSSize, context: any AccountContextProtocol, tabs: [ChatListFilter], selected: ChatListFilter, counters: ChatListFilterBadges, action: ((ChatListFilter)->Void)? = nil, openSettings: (()->Void)? = nil, menuItems: ((ChatListFilter, Int?, Bool?)->[ContextMenuItem])? = nil, presentation: TelegramPresentationTheme = theme, customBackgroundColor: NSColor? = nil, getCurrentStoriesState:@escaping()->(StoryListChatListRowItem.InterfaceState, NSView)? = { return nil }) {
        self.action = action
        self.context = context
        self.tabs = tabs
        self.presentation = presentation
        self.selected = selected
        self.openSettings = openSettings
        self.counters = counters
        self._menuItems = menuItems
        self.customBackgroundColor = customBackgroundColor
        self.getCurrentStoriesState = getCurrentStoriesState
        super.init(initialSize)
    }

    public required init(_ initialSize: NSSize) {
        self.action = nil
        self.context = nil
        self.tabs = []
        self.presentation = theme
        self.selected = .allChats
        self.openSettings = nil
        self._menuItems = nil
        self.customBackgroundColor = nil
        self.getCurrentStoriesState = { return nil }
        self.counters = ChatListFilterBadges(total: 0, filters: [])
        super.init(initialSize)
    }


    public override var backdorColor: NSColor {
        return customBackgroundColor ?? .clear
    }

    public override var borderColor: NSColor {
        return .clear
    }

    public override var singletonItem: Bool {
        return false
    }
    
    public func menuItems(for item: ChatListFilter, unreadCount: Int?) -> Signal<[ContextMenuItem], NoError> {
        
        let id = ChatListUIHooks.shared.chatListFilterId(item)
        _ = self.context
        
        guard let context = self.context else {
            return .complete()
        }
        
        let filterPeersAreMuted: Signal<Bool, NoError> = context.engine.peers.currentChatListFilters()
        |> take(1)
        |> mapToSignal { filters -> Signal<Bool, NoError> in
            guard let filter = filters.first(where: { ChatListUIHooks.shared.chatListFilterId($0) == id }) else {
                return .single(false)
            }
            guard case let .filter(_, _, _, data) = filter else {
                return .single(false)
            }
            return context.engine.data.get(
                EngineDataList(data.includePeers.peers.map(TelegramEngine.EngineData.Item.Peer.NotificationSettings.init(id:)))
            )
            |> map { list -> Bool in
                for item in list {
                    switch item.muteState {
                    case .default, .unmuted:
                        return false
                    default:
                        break
                    }
                }
                return true
            }
        } |> deliverOnMainQueue
        
        return filterPeersAreMuted |> map { [weak self] allMuted in
            return self?._menuItems?(item, unreadCount, allMuted) ?? []
        }
    }
    
    public override var stableId: AnyHashable {
        return UIChatListEntryId.reveal
    }
    
    public override func viewClass() -> AnyClass {
        return ChatListRevealView.self
    }
    
    public override var identifier: String {
        return "ChatListRevealView"
    }
    
    public override var height: CGFloat {
        return 30
    }
    
    static func accessibilityTabTitle(_ title: String, unreadCount: Int?) -> String {
        if let count = unreadCount, count > 0 {
            return title + ", " + strings().voiceOverChatUnreadMessagesOther(count)
        }
        return title
    }

    func accessibilityTabTitle(_ tab: ChatListFilter) -> String {
        return ChatListRevealItem.accessibilityTabTitle(tab.title, unreadCount: counters.count(for: tab)?.count)
    }
    
    public override var accessibilityLabel: String? {
        return strings().chatListFilterListTitle
    }
    
    public override var accessibilityValue: String? {
        guard !tabs.isEmpty else {
            return nil
        }
        return accessibilityTabTitle(selected) + ", " + strings().voiceOverCommonSelected
    }
    
    public override var accessibilityRole: NSAccessibility.Role? {
        return .tabGroup
    }
    
    public override func accessibilityPerformPress() -> Bool {
        return false
    }
}


public final class ChatListRevealView : TableStickView {
    private let containerView = View()
    private var animated: Bool = false
    public let segmentView: ScrollableSegmentView = ScrollableSegmentView(frame: NSZeroRect)
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(containerView)
        containerView.backgroundColor = .clear
        containerView.layer?.masksToBounds = false
        containerView.addSubview(segmentView)
        segmentView.layer?.masksToBounds = true

        self.layer?.masksToBounds = false

        segmentView.scrollView.applyExternalScroll = { [weak self] event in
            if let item = self?.item as? ChatListRevealItem {
                if let (state, view) = item.getCurrentStoriesState() {
                    switch state {
                    case .progress:
                        view.scrollWheel(with: event)
                        return true
                    default:
                        return false
                    }
                }
            }
            return false
        }
    }

    public override func mouseUp(with event: NSEvent) {
       
    }
    public override func mouseDown(with event: NSEvent) {
        if mouseInside() {
        }
    }
    
    
    public override func updateIsVisible(_ visible: Bool, animated: Bool) {
        super.updateIsVisible(visible, animated: animated)
    }

    public override var backdorColor: NSColor {
        return (item as? ChatListRevealItem)?.customBackgroundColor ?? .clear
    }

    public override func updateColors() {
        super.updateColors()
        needsDisplay = true
    }
    
    private var splitViewState: SplitViewState?
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? ChatListRevealItem else {
            return
        }

        var animated = (self.animated || animated)
        self.animated = true


        guard let context = item.context else {
            return
        }
        
        let generateIcon:(ChatListFilter?)->CGImage? = { tab in
            let unreadCount:ChatListFilterBadge? = item.counters.count(for: tab)
            let icon: CGImage?
            if let unreadCount = unreadCount, unreadCount.count > 0 {
                let selectedBubble = System.edgeToEdgeSidebar && item.selected == tab
                let attributedString = NSAttributedString.initialize(string: "\(unreadCount.count.prettyNumber)", color: selectedBubble ? item.presentation.colors.accent : item.presentation.colors.background, font: .medium(.short))
                let textLayout = TextNode.layoutText(maybeNode: nil,  attributedString, nil, 1, .start, NSMakeSize(CGFloat.greatestFiniteMagnitude, CGFloat.greatestFiniteMagnitude), nil, false, .center)
                var size = NSMakeSize(textLayout.0.size.width + 8, textLayout.0.size.height + 5)
                size = NSMakeSize(max(size.height,size.width), size.height)
                
                icon = generateImage(size, rotatedContext: { size, ctx in
                    let rect = NSMakeRect(0, 0, size.width, size.height)
                    ctx.clear(rect)
                    if selectedBubble {
                        ctx.setFillColor(item.presentation.colors.underSelectedColor.cgColor)
                    } else if item.selected == tab || unreadCount.hasUnmutedUnread {
                        ctx.setFillColor(item.presentation.colors.accent.cgColor)
                    } else {
                        ctx.setFillColor(item.presentation.colors.badgeMuted.cgColor)
                    }
                    
                    
                    ctx.round(size, size.height/2.0)
                    ctx.fill(rect)
                    
                    let focus = rect.focus(textLayout.0.size)
                    textLayout.1.draw(focus.offsetBy(dx: 0, dy: -1), in: ctx, backingScaleFactor: 2.0, backgroundColor: .white)
                    
                })!
            } else if let _ = tab {
                icon = nil
            } else {
                icon = nil
            }
            return icon
        }
        
        animated = animated && splitViewState == context.layout
        self.splitViewState = context.layout
        
        let segmentTheme = ScrollableSegmentTheme(background: .clear, border: System.edgeToEdgeSidebar ? .clear : item.presentation.colors.border, selector: item.presentation.colors.accent, inactiveText: System.edgeToEdgeSidebar ? item.presentation.colors.text : item.presentation.colors.grayText, activeText: System.edgeToEdgeSidebar ? item.presentation.colors.underSelectedColor : item.presentation.colors.text, textFont: .normal(.text))

        segmentView.bubbles = System.edgeToEdgeSidebar
        segmentView.theme = segmentTheme

        var index: Int = 0
        let insets = System.edgeToEdgeSidebar ? NSEdgeInsets(left: 14, right: 14) : NSEdgeInsets(left: 10, right: 10)
        var items:[ScrollableSegmentItem] = []
        for tab in item.tabs {
            let unreadCount = item.counters.count(for: tab)
            let icon: CGImage? = generateIcon(tab)
            let title: String = tab.title
            let selected = item.selected == tab

            let segmentItem = ScrollableSegmentItem(title: title, index: index, uniqueId: Int64(ChatListUIHooks.shared.chatListFilterId(tab)), selected: selected, insets: insets, icon: icon, theme: segmentTheme, equatable: UIEquatable(unreadCount), customTextView: {
                
                let attr = NSMutableAttributedString()
                attr.append(string: title, color: selected ? segmentTheme.activeText : segmentTheme.inactiveText, font: selected && System.edgeToEdgeSidebar ? .semibold(.text) : segmentTheme.textFont)
                InlineStickerItem.apply(to: attr, associatedMedia: [:], entities: tab.entities, isPremium: context.isPremium, playPolicy: tab.enableAnimations ? nil : .framesCount(1))

                let layout = TextViewLayout(attr)
                layout.measure(width: .greatestFiniteMagnitude)

                let textView = InteractiveTextView()
                textView.userInteractionEnabled = false
                textView.textView.isSelectable = false
                textView.set(text: layout, context: context)
                
                return textView
            })
            let accessibilityUnreadCount = unreadCount?.count
            segmentItem.accessibilityLabel = {
                return ChatListRevealItem.accessibilityTabTitle(title, unreadCount: accessibilityUnreadCount)
            }
            items.append(segmentItem)
            index += 1
        }
        
        segmentView.updateItems(items, animated: animated)
        let range: NSRange
        if context.isPremium {
            range = NSMakeRange(0, items.count)
        } else {
            range = NSMakeRange(1, items.count - 1)
        }
        segmentView.resortRange = range
        segmentView.resortHandler = { from, to in
            _ = context.engine.peers.updateChatListFiltersInteractively({ state in
                var state = state
                if context.isPremium {
                    state.move(at: from, to: to)
                } else {
                    state.move(at: from - 1, to: to - 1)
                }
                return state
            }).start()
        }
        segmentView.didChangeSelectedItem = { [weak item] selected in
            if let item = item {
                if selected.uniqueId == -1 {
                    item.action?(.allChats)
                } else if selected.uniqueId == -2 {
                    item.openSettings?()
                } else {
                    item.action?(item.tabs[selected.index])
                }
            }
        }
        segmentView.menuItems = { [weak item] selected in
            if let item = item, selected.uniqueId != -1 && selected.uniqueId != -2 {
                return item.menuItems(for: item.tabs[selected.index], unreadCount: item.counters.count(for: item.tabs[selected.index])?.count)
            } else if let item = item, selected.uniqueId == -1 {
                return item.menuItems(for: .allChats, unreadCount: nil)
            } else {
                return .single([])
            }
        }
      
    }
    
    
    public override var isHidden: Bool {
        didSet {
            if isHidden {
                var bp:Int = 0
                bp += 1
            }
        }
    }
    
    public override var isAlwaysUp: Bool {
        return true
    }
    
    public override func removeFromSuperview() {
        super.removeFromSuperview()
    }
    
    public override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    public override func layout() {
        super.layout()

        containerView.frame = bounds
        segmentView.frame = NSMakeRect(0, -10, containerView.bounds.width, containerView.bounds.height
         + 10)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
