import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import Reactions
import SwiftSignalKit
import InAppSettings
import FetchManager
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import LocalAnimations
import InputDataUI
import AlertsUI
import AvatarUI
import SceneEffects
import PremiumStatusUI
import ProxyUtils
import WebAppUI
import StoriesUI
import ChatHistoryModel
import ChatUI
import ChatModeTypes
import InlineStickerLayer

public struct PeerListHiddenItems : Equatable {
    public var archive: ItemHideStatus
    public var generalTopic: ItemHideStatus?
    public var promo: Set<PeerId>
    
    public static var `default`: PeerListHiddenItems {
        return PeerListHiddenItems(archive: FastSettings.archiveStatus, generalTopic: nil, promo: Set())
    }
}


private final class Arguments {
    let context: any AccountContextProtocol
    let joinGroupCall:(ChatActiveGroupCallInfo)->Void
    let joinGroup:(PeerId)->Void
    let openPendingRequests:()->Void
    let dismissPendingRequests:([PeerId])->Void
    let openStory:(StoryInitialIndex?, Bool, Bool)->Void
    let getStoryInterfaceState:()->StoryListChatListRowItem.InterfaceState
    let revealStoriesState:()->Void
    let setupFilter: (ChatListFilter)->Void
    let openFilterSettings: (ChatListFilter)->Void
    let tabsMenuItems: (ChatListFilter, Int?, Bool?)->[ContextMenuItem]
    let getController:()->ViewController?
    let navigationBarLeftPosition:()->CGFloat
    let contextMenu:()->ContextMenu
    let selectSearchTag:(PeerListState.SelectedSearchTag)->Void
    let setPeerAsTag:(Peer?)->Void
    let toggleContactsSort:(PeerListState.ContactsSort)->Void
    init(context: any AccountContextProtocol, joinGroupCall:@escaping(ChatActiveGroupCallInfo)->Void, joinGroup:@escaping(PeerId)->Void, openPendingRequests:@escaping()->Void, dismissPendingRequests: @escaping([PeerId])->Void, openStory:@escaping(StoryInitialIndex?, Bool, Bool)->Void, getStoryInterfaceState:@escaping()->StoryListChatListRowItem.InterfaceState, revealStoriesState:@escaping()->Void, setupFilter: @escaping(ChatListFilter)->Void, openFilterSettings: @escaping(ChatListFilter)->Void, tabsMenuItems: @escaping(ChatListFilter, Int?, Bool?)->[ContextMenuItem], getController:@escaping()->ViewController?, navigationBarLeftPosition:@escaping()->CGFloat, contextMenu: @escaping()->ContextMenu, selectSearchTag:@escaping(PeerListState.SelectedSearchTag)->Void, setPeerAsTag:@escaping(Peer?)->Void, toggleContactsSort:@escaping(PeerListState.ContactsSort)->Void) {
        self.context = context
        self.joinGroupCall = joinGroupCall
        self.joinGroup = joinGroup
        self.openPendingRequests = openPendingRequests
        self.dismissPendingRequests = dismissPendingRequests
        self.openStory = openStory
        self.getStoryInterfaceState = getStoryInterfaceState
        self.revealStoriesState = revealStoriesState
        self.setupFilter = setupFilter
        self.openFilterSettings = openFilterSettings
        self.tabsMenuItems = tabsMenuItems
        self.getController = getController
        self.navigationBarLeftPosition = navigationBarLeftPosition
        self.contextMenu = contextMenu
        self.selectSearchTag = selectSearchTag
        self.setPeerAsTag = setPeerAsTag
        self.toggleContactsSort = toggleContactsSort
    }
}


public struct PeerListState : Equatable {
    
    public enum SelectedSearchTag : Int32 {
        case hashtagThisChat = -7
        case hashtagMyMessages = -6
        case hashtagPublicPosts = -5
        case chats = -4
        case downloads = -3
        case channels = -2
        case apps = -1
        case globalPosts = 0
        case photos = 256
        case videos = 512
        case links = 8
        case music = 4
        case voice = 16
        case gif = 128
        case files = 2
   
        
        public func searchTags(_ peerTag: PeerId?, hashtag: Hashtag?) -> SearchTags {
            switch self {
            case .chats:
                return SearchTags(messageTags: nil, peerTag: peerTag)
            case .downloads:
                return SearchTags(messageTags: nil, peerTag: nil)
            case .channels:
                return SearchTags(messageTags: nil, peerTag: nil, listType: .channels)
            case .apps:
                return SearchTags(messageTags: nil, peerTag: nil, listType: .bots)
            case .globalPosts:
                return SearchTags(messageTags: nil, peerTag: nil, listType: .globalPosts)
            case .hashtagThisChat:
                return SearchTags(messageTags: nil, peerTag: hashtag?.peer?.id, text: hashtag?.text, publicPosts: false, myMessages: false)
            case .hashtagMyMessages:
                return SearchTags(messageTags: nil, peerTag: nil, text: hashtag?.text, publicPosts: false, myMessages: true)
            case .hashtagPublicPosts:
                return SearchTags(messageTags: nil, peerTag: nil, text: hashtag?.text, publicPosts: true, myMessages: false)
            default:
                return SearchTags(messageTags: self.messageTags, peerTag: peerTag)
            }
        }
        
        public var searchOptions: AppSearchOptions {
            switch self {
            case .chats:
                return [.chats, .messages]
            case .downloads:
                return []
            case .channels:
                return [.chats]
            case .apps:
                return [.chats]
            default:
                return [.messages]
            }
        }
        
        
        public var title: String {
            switch self {
            case .chats:
                return strings().chatListChatsTag
            case .downloads:
                return strings().chatListDownloadsTag
            case .channels:
                return strings().chatListChannelsTag
            case .apps:
                return strings().chatListAppsTag
            case .globalPosts:
                //TODO
                return "Posts"
            case .photos:
                return strings().searchFilterPhotos
            case .videos:
                return strings().searchFilterVideos
            case .links:
                return strings().searchFilterLinks
            case .music:
                return strings().searchFilterMusic
            case .voice:
                return strings().searchFilterVoice
            case .gif:
                return strings().searchFilterGIFs
            case .files:
                return strings().searchFilterFiles
            case .hashtagThisChat:
                return strings().chatHashtagThisChat
            case .hashtagMyMessages:
                return strings().chatHashtagMyMessages
            case .hashtagPublicPosts:
                return strings().chatHashtagPublicPosts
            }
        }
        
        public var messageTags: MessageTags? {
            switch self {
            case .chats:
                return nil
            case .downloads:
                return nil
            case .channels:
                return nil
            case .apps:
                return nil
            case .globalPosts:
                return nil
            case .photos:
                return .photo
            case .videos:
                return .video
            case .links:
                return .webPage
            case .music:
                return .music
            case .voice:
                return .voiceOrInstantVideo
            case .gif:
                return .gif
            case .files:
                return .file
            case .hashtagThisChat:
                return nil
            case .hashtagMyMessages:
                return nil
            case .hashtagPublicPosts:
                return nil
            }
        }
        
        public static func list(_ state: PeerListState) -> [SelectedSearchTag] {
            var list: [SelectedSearchTag] = []
            if state.searchState == .Focus {
                if state.peerTag == nil, state.forumPeer == nil, !state.mode.isForumLike, !state.mode.isCommunity {
                    if state.hasDownloads {
                        list.append(.downloads)
                    }
                    list.append(.channels)
                    list.append(.apps)
                    list.append(.globalPosts)
                }
                list.append(.photos)
                list.append(.videos)
                list.append(.links)
                list.append(.music)
                list.append(.voice)
                list.append(.gif)
                list.append(.files)
                
                list.append(.hashtagThisChat)
                list.append(.hashtagMyMessages)
                list.append(.hashtagPublicPosts)
                
                return list

            } else {
                return []
            }
        }
        
    }
    
    public typealias ContactsSort = InAppSettings.ContactsSort
    
    public enum AppearMode : Equatable {
        case normal
        case short
    }
    
    public struct InputActivities : Equatable {
        public struct Activity : Equatable {
            public let peer: PeerEquatable
            public let activity: PeerInputActivity
            public init(_ peer: Peer, _ activity: PeerInputActivity) {
                self.peer = PeerEquatable(peer)
                self.activity = activity
            }
        }
        public var activities: [PeerActivitySpace: [Activity]]
    }
    public struct ForumData : Equatable {
        public static func == (lhs: PeerListState.ForumData, rhs: PeerListState.ForumData) -> Bool {
            if lhs.peer != rhs.peer {
                return false
            }
            if let lhsCached = lhs.peerView.cachedData, let rhsCached = rhs.peerView.cachedData {
                if !lhsCached.isEqual(to: rhsCached) {
                    return false
                }
            } else if (lhs.peerView.cachedData != nil) != (rhs.peerView.cachedData != nil) {
                return false
            }
            if lhs.online != rhs.online {
                return false
            }
            return true
        }
        
        public var peer: TelegramChannel
        public var peerView: PeerView
        public var online: Int32
        
    }
    
    public var proxySettings: ProxySettings
    public var connectionStatus: ConnectionStatus
    public var splitState: SplitViewState
    public var searchState: SearchFieldState = .None
    public var searchQuery: String = ""
    public var peer: PeerEquatable?
    public var forumPeer: ForumData?
    public var mode: PeerListMode
    public var activities: InputActivities
    
    public var appear: AppearMode
    public var controllerAppear: AppearMode
    public var hiddenItems: PeerListHiddenItems
    public var selectedForum: PeerId?
    public var stories: EngineStorySubscriptions?
    public var isContacts: Bool
    public var filterData: FilterData
    public var presentation: TelegramPresentationTheme
    public var privacy: GlobalPrivacySettings?
    public var displaySavedAsTopics: Bool
    public var webapps: BrowserStateContext.FullState? = nil
    
    public var contactsSort: ContactsSort = FastSettings.contactsSort
    
    public var selectedTag: SelectedSearchTag = .chats
    public var peerTag: EnginePeer? = nil
    
    public var hasDownloads = false
    
    public struct Hashtag : Equatable {
        public var mode: SelectedSearchTag
        public var peer: EnginePeer?
        public var text: String
    }
    
    public var hashtag: Hashtag?
    
    public var hasStories: Bool {
        if let stories = self.stories, !isContacts, !mode.isForumLike {
            if self.splitState == .minimisize {
                return false
            }
            if let accountItem = stories.accountItem, accountItem.storyCount > 0, mode.groupId != .archive {
                return true
            }
            if !stories.items.isEmpty {
                return true
            }
        }
        return false
    }
    
    public static func initialize(_ isContacts: Bool) -> PeerListState {
        return .init(proxySettings: .defaultSettings, connectionStatus: .waitingForNetwork, splitState: .dual, searchState: .None, peer: nil, forumPeer: nil, mode: .plain, activities: .init(activities: [:]), appear: .normal, controllerAppear: .normal, hiddenItems: .default, selectedForum: nil, stories: nil, isContacts: isContacts, filterData: FilterData(), presentation: theme, privacy: nil, displaySavedAsTopics: false)

    }
}


private final class ProxyView : Control {
    fileprivate let button:ImageButton = ImageButton()
    private var connecting: ProgressIndicator?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(button)
        button.userInteractionEnabled = false
        button.isEventLess = true
        button.isAccessibilityDecorative = true
        self.setAccessibilityLabel(strings().voiceOverNavigationProxySettings)
        self.scaleOnClick = true
    }

    private func proxyImage(_ image: CGImage) -> CGImage {
        return image
    }

    func update(_ pref: ProxySettings, connection: ConnectionStatus, animated: Bool) {
        switch connection {
        case .connecting, .waitingForNetwork:
            if pref.enabled {
                let current: ProgressIndicator
                if let view = self.connecting {
                    current = view
                } else {
                    current = ProgressIndicator(frame: focus(NSMakeSize(11, 11)))
                    self.connecting = current
                    addSubview(current)
                }
                current.userInteractionEnabled = false
                current.isEventLess = true
                current.progressColor = theme.colors.accentIcon
            } else if let view = connecting {
                performSubviewRemoval(view, animated: animated)
                self.connecting = nil
            }

            button.set(image: proxyImage(pref.enabled ? theme.icons.proxyState : theme.icons.proxyEnable), for: .Normal)
        case .online, .updating:
            if let view = connecting {
                performSubviewRemoval(view, animated: animated)
                self.connecting = nil
            }
            if pref.enabled  {
                button.set(image: proxyImage(theme.icons.proxyEnabled), for: .Normal)
            } else {
                button.set(image: proxyImage(theme.icons.proxyEnable), for: .Normal)
            }
        }
        button.sizeToFit()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        button.center()
        if let connecting = connecting {
            var rect = connecting.centerFrame()
            if backingScaleFactor == 2.0 {
                rect.origin.x -= 0.5
                rect.origin.y -= 0.5
            }
            connecting.frame = rect
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        connecting?.progressColor = theme.colors.accentIcon
    }
}

private final class StatusView : Control {
    fileprivate var button:PremiumStatusControl?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false
    }
    
    private var peer: Peer?
    private weak var effectPanel: Window?
    
    func update(_ peer: Peer, context: any AccountContextProtocol, animated: Bool) {
        
        
        var interactiveStatus: Reactions.InteractiveStatus? = nil
        if visibleRect != .zero, window != nil, let interactive = context.reactions.interactiveStatus, !context.isLite(.emoji_effects) {
            interactiveStatus = interactive
        }
        if let view = self.button, interactiveStatus != nil, interactiveStatus?.fileId != nil {
            performSubviewRemoval(view, animated: animated, duration: 0.3)
            self.button = nil
        }
        
        let control = PremiumStatusControl.control(peer, account: context.account, inlinePacksContext: context.inlinePacksContext, left: false, isSelected: false, isBig: true, playTwice: true, cached: self.button, animated: animated)
        if let control = control {
            self.button = control
            addSubview(control)
            control.center()
            
        } else {
            self.button?.removeFromSuperview()
            self.button = nil
        }
        self.peer = peer
        
        if let interactive = interactiveStatus {
            self.playAnimation(interactive, context: context)
        }
    }
    
    private func playAnimation(_  status: Reactions.InteractiveStatus, context: any AccountContextProtocol) {
        guard let control = self.button, let window = self.window else {
            return
        }
        
        guard let fileId = status.fileId else {
            return
        }
        
        control.isHidden = true
        
        let play:(StatusView)->Void = { [weak control] superview in
            
            guard let control = control else {
                return
            }
            control.isHidden = false
            
            let panel = Window(contentRect: NSMakeRect(0, 0, 160, 120), styleMask: [.fullSizeContentView], backing: .buffered, defer: false)
            panel._canBecomeMain = false
            panel._canBecomeKey = false
            panel.ignoresMouseEvents = true
            panel.level = .popUpMenu
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false

            let player = CustomReactionEffectView(frame: NSMakeSize(160, 120).bounds, context: context, fileId: fileId)
            
            player.isEventLess = true
            
            player.triggerOnFinish = { [weak panel] in
                if let panel = panel  {
                    panel.parent?.removeChildWindow(panel)
                    panel.orderOut(nil)
                }
            }
            superview.effectPanel = panel
                    
            let controlRect = superview.convert(control.frame, to: nil)
            
            var rect = CGRect(origin: CGPoint(x: controlRect.midX - player.frame.width / 2, y: controlRect.midY - player.frame.height / 2), size: player.frame.size)
            
            
            rect = window.convertToScreen(rect)
            
            panel.setFrame(rect, display: true)
            
            panel.contentView?.addSubview(player)
            
            window.addChildWindow(panel, ordered: .above)
        }
        if let fromRect = status.rect {
            let layer = InlineStickerItemLayer(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: .init(fileId: fileId, file: nil, emoji: ""), size: control.frame.size)
            
            let toRect = control.convert(control.frame.size.bounds, to: nil)
            
            let from = fromRect.origin.offsetBy(dx: fromRect.width / 2, dy: fromRect.height / 2)
            let to = toRect.origin.offsetBy(dx: toRect.width / 2, dy: toRect.height / 2)
            
            let completed: (Bool)->Void = { [weak self] _ in
                DispatchQueue.main.async {
                    if let container = self {
                        play(container)
                        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                    }
                }
            }
            parabollicReactionAnimation(layer, fromPoint: from, toPoint: to, window: context.window, completion: completed)
        } else {
            play(self)
        }
    }
    
  
    override func layout() {
        super.layout()
        button?.center()
    }
    
    deinit {
        if let panel = effectPanel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
    }
}

fileprivate final class WebappsControl : Control {
    
    
    struct WebAppItem : Identifiable, Comparable {
        static func < (lhs: WebAppItem, rhs: WebAppItem) -> Bool {
            return lhs.index < rhs.index
        }
        let data: BrowserTabData
        let index: Int
        var stableId: AnyHashable {
            return data.unique
        }
    }
    
    class Control : View {
        private var avatarView: AvatarControl?
        private var iconView: ImageView?
        
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            self.layer?.cornerRadius = 4
            self.layer?.borderWidth = 2
            self.layer?.borderColor = theme.colors.background.cgColor
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func updateLocalizationAndTheme(theme: PresentationTheme) {
            super.updateLocalizationAndTheme(theme: theme)
            self.layer?.borderColor = theme.colors.background.cgColor
        }
        
        func update(item: WebAppItem, context: any AccountContextProtocol) {
            if let enginePeer = item.data.peer {
                let current: AvatarControl
                if let view = self.avatarView {
                    current = view
                } else {
                    current = AvatarControl(font: .avatar(8))
                    current.setFrameSize(24, 24)
                    current.userInteractionEnabled = false
                    self.avatarView = current
                    addSubview(current)
                    current.center()
                }
                current.setPeer(account: context.account, peer: enginePeer._asPeer())
            } else if let avatarView {
                performSubviewRemoval(avatarView, animated: false)
                self.avatarView = nil
            }
            
            if item.data.external?.isSite == true {
                let current: ImageView
                if let view = self.iconView {
                    current = view
                } else {
                    current = ImageView()
                    current.setFrameSize(24, 24)
                    current.isEventLess = true
                    current.isAccessibilityDecorative = true
                    current.layer?.cornerRadius = 4
                    self.iconView = current
                    addSubview(current)
                    current.animates = true
                    current.center()
                }
                
                let color: NSColor = theme.colors.listBackground

                if case .instantView = item.data.unique {
                    current.nsImage = generateContextMenuInstantView(color: color, size: NSMakeSize(24, 24))
                } else  if let favicon = item.data.external?.favicon {
                    current.nsImage = favicon
                } else {
                    current.nsImage = generateContextMenuUrl(color: color, state: item.data.external, size: NSMakeSize(24, 24))
                }
            } else if let iconView {
                performSubviewRemoval(iconView, animated: false)
                self.iconView = nil
            }
        }
        
        override func layout() {
            super.layout()
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }
        
        func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            if let avatarView {
                transition.updateFrame(view: avatarView, frame: size.bounds)
            }
            if let iconView {
                transition.updateFrame(view: iconView, frame: size.bounds)
            }
        }
    }
    
    private var views: [Control] = []
    private var items: [WebAppItem] = []
    
    private var imageView: ImageView?
    private var _glassView: NSView?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.layer?.masksToBounds = false
        scaleOnClick = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(webapps: [BrowserTabData], context: any AccountContextProtocol, animated: Bool) {
        var items: [WebAppItem] = []
        var index: Int = .max
        for webapp in webapps.prefix(4).reversed() {
            items.append(.init(data: webapp, index: index))
            index -= 1
        }
        
        let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: self.items, rightList: items)
        
        for rdx in deleteIndices.reversed() {
            performSubviewRemoval(views.remove(at: rdx), animated: animated, scale: true)
        }
        
        let rects = getRects(items)
        
        for (idx, item, _) in indicesAndItems {
            let view = Control(frame: rects[idx])
            view.setAccessibilityLabel(item.data.peer?._asPeer().displayTitle)
            view.update(item: item, context: context)
            
            views.insert(view, at: idx)
            self.addSubview(view)
            if animated {
                view.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                view.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.5, bounce: true)
            }
           
        }
        for (idx, item, _) in updateIndices {
            let item = item
            views[idx].update(item: item, context: context)
        }
        
        self.items = items
        
        if items.isEmpty {
            let current: ImageView
            let isNew: Bool
            if let view = self.imageView {
                current = view
                isNew = false
            } else {
                current = ImageView()
                current.isAccessibilityDecorative = true
                addSubview(current)
                self.imageView = current
                isNew = true
            }
            current.image = theme.icons.chatlist_apps
            current.sizeToFit()
            
            
            if animated, isNew {
                current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                current.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.5, bounce: true)
            }
        } else if let view = self.imageView {
            performSubviewRemoval(view, animated: animated, scale: true)
            self.imageView = nil
        }
        
        
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.35, curve: .spring) : .immediate
        
        self.updateLayout(size: self.frame.size, transition: transition)
        
        for (_, view) in views.enumerated() {
            view.layer?.borderWidth = items.count < 4 ? 2 : 0
            view.layer?.cornerRadius = items.count < 4 ? 6 : 2
            if animated {
                view.layer?.animateBorder()
                view.layer?.animateCornerRadius()
            }
        }
        
        let size: NSSize
        if items.count == 4 || items.count == 0 {
            size = NSMakeSize(28, 24)
        } else {
            let last = getRects(items).last!
            size = NSMakeSize(last.maxX, 24)
        }
        transition.updateFrame(view: self, frame: CGRect(origin: self.frame.origin, size: size))
    }
    
    private func getRects(_ items: [WebAppItem]) -> [NSRect] {
        var rects: [NSRect] = []
        
        if items.count < 4 {
            let size = NSMakeSize(24, 24)
            if items.count == 1 {
                rects.append(.init(origin: NSPoint(x: 2, y: 0), size: size))
            } else {
                rects.append(.init(origin: NSPoint(x: 0, y: 0), size: size))
            }
            if items.count < 3 {
                rects.append(.init(origin: NSPoint(x: size.width / 2, y: 0), size: size))
            } else {
                rects.append(.init(origin: NSPoint(x: floorToScreenPixels(size.width / 3), y: 0), size: size))
                rects.append(.init(origin: NSPoint(x: floorToScreenPixels(size.width / 3 * 2), y: 0), size: size))
            }
        } else {
            let size = NSMakeSize(11, 11)
            rects.append(.init(origin: NSPoint(x: 2, y: 2), size: size))
            rects.append(.init(origin: NSPoint(x: size.width + 4, y: 2), size: size))
            rects.append(.init(origin: NSPoint(x: 2, y: size.height + 4), size: size))
            rects.append(.init(origin: NSPoint(x: size.width + 4, y: size.height + 4), size: size))
            rects = rects.reversed()
        }
        
        return Array(rects.prefix(items.count))
    }
    
    override func layout() {
        super.layout()
        self.imageView?.center()
        _glassView?.frame = bounds.insetBy(dx: -4, dy: -4).offsetBy(dx: 0, dy: 0)
        _glassView?.layer?.cornerRadius = min(bounds.width, bounds.height) / 2 + 4
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }

    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        let rects = self.getRects(self.items)
        for (i, view) in views.enumerated() {
            transition.updateFrame(view: view, frame: rects[i])
            view.updateLayout(size: view.frame.size, transition: transition)
        }
        if let glassView = _glassView {
            let glassFrame = size.bounds.insetBy(dx: -4, dy: -4)
            transition.updateFrame(view: glassView, frame: glassFrame)
            (glassView as? LiquidGlassView)?.updateLayout(size: glassFrame.size, transition: transition)
        }
    }
}

fileprivate final class TitleView : Control {
    
    enum Source {
        case contacts
        case forum
        case chats
        case archivedChats
        case savedMessages
        var text: String {
            switch self {
            case .contacts:
                return strings().peerListTitleContacts
            case .chats:
                return strings().peerListTitleChats
            case .archivedChats:
                return strings().peerListTitleArchive
            case .forum:
                return strings().peerListTitleForum
            case .savedMessages:
                return strings().peerListTitleSavedMessages
            }
        }
    }
    
    var openStatus:((Control)->Void)? = nil
    
    private let textView = TextView()
    private var premiumStatus: StatusView?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        textView.isAccessibilityDecorative = true
        self.layer?.masksToBounds = false
    }
    
    
    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
    }
        
    private struct TitleKey: Equatable {
        var text: String
        var maxWidth: CGFloat
        var theme: ObjectIdentifier
    }

    private var titleKey: TitleKey?

    fileprivate func updateState(_ state: PeerListState, arguments: Arguments, communityTitle: String?, maxWidth: CGFloat, animated: Bool) {

        let source: Source
        if state.mode.isSavedMessages {
            source = .savedMessages
        } else if state.isContacts {
            source = .contacts
        } else if state.mode.groupId == .archive {
            source = .archivedChats
        } else if state.mode.isForum {
            source = .forum
        } else {
            source = .chats
        }
        let text: String
        if state.mode.isForum {
            text = state.forumPeer?.peer.title ?? source.text
        } else if state.mode.isCommunity, let communityTitle = communityTitle, !communityTitle.isEmpty {
            text = communityTitle
        } else {
            text = source.text
        }
        let titleKey = TitleKey(text: text, maxWidth: maxWidth, theme: ObjectIdentifier(theme))
        if titleKey != self.titleKey {
            self.titleKey = titleKey
            let layout = TextViewLayout(.initialize(string: text, color: theme.colors.text, font: .medium(.title)), maximumNumberOfLines: 1)
            layout.measure(width: maxWidth)
            textView.update(layout)
            setAccessibilityLabel(text)
        }
        
        let hasStatus = state.peer?.peer.isPremium ?? false && state.mode == .plain && source != .contacts

        if hasStatus, let peer = state.peer?.peer {
            
            let current: StatusView
            if let view = self.premiumStatus {
                current = view
            } else {
                current = StatusView(frame: CGRect(origin: NSMakePoint(textView.frame.width + 4, (frame.height - 20) / 2), size: NSMakeSize(20, 20)))
                self.premiumStatus = current
                self.addSubview(current)
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
                current.set(handler: { [weak self] control in
                    self?.openStatus?(control)
                }, for: .Click)
                current.scaleOnClick = true
            }
            current.update(peer, context: arguments.context, animated: animated)
            
        } else if let view = self.premiumStatus {
            performSubviewRemoval(view, animated: animated)
            self.premiumStatus = nil
        }
    }
    
    var hasPremium: Bool {
        return premiumStatus != nil
    }
    
    var displaysStatus: Bool = true
    
    var size: NSSize {
        return size(displayingStatus: displaysStatus)
    }
    
    func size(displayingStatus: Bool) -> NSSize {
        var width: CGFloat = textView.frame.width
        if displayingStatus, let premiumStatus = self.premiumStatus {
            width += premiumStatus.frame.width + 4
        }
        return NSMakeSize(width, 20)
    }
    
    override func layout() {
        super.layout()
        self.updateLayout(size: frame.size, transition: .immediate)
    }
    
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: textView, frame: textView.centerFrameY(x: 0))
        if let premiumStatus = self.premiumStatus {
            premiumStatus.isHidden = !displaysStatus
            transition.updateFrame(view: premiumStatus, frame: premiumStatus.centerFrameY(x: textView.frame.width + 4, addition: 1))
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class TitleForumView : Control {
    private let title = TextView()
    private let status = TextView()
    private let settings = ImageButton()
    private var state: PeerListState?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(title)
        addSubview(status)
        addSubview(settings)
        
        title.userInteractionEnabled = false
        status.userInteractionEnabled = false
        title.isSelectable = false
        status.isSelectable = false
        title.isAccessibilityDecorative = true
        
        settings.setAccessibilityLabel(strings().voiceOverCommonMore)
        settings.autohighlight = false
        settings.scaleOnClick = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(_ state: PeerListState, forumData: PeerListState.ForumData, arguments: Arguments) {
        self.state = state
        let size = self.frame.size
        _ = state.filterData.sidebar && !state.filterData.isEmpty
        let text_w = size.width - 80 - 10 - 30

        
        let t_layout = TextViewLayout(.initialize(string: forumData.peer.displayTitle, color: theme.colors.text, font: .medium(.text)), maximumNumberOfLines: 1)
        t_layout.measure(width: text_w)
        
        let s_layout = TextViewLayout(.initialize(string: stringStatus(for: forumData.peerView, context: arguments.context).status.string, color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1)
        s_layout.measure(width: text_w)

        
        self.title.update(t_layout)
        self.status.update(s_layout)
        setAccessibilityLabel(forumData.peer.displayTitle)
        
        settings.set(image: theme.icons.chatActions.highlight(color: theme.colors.accent), for: .Normal)
        settings.sizeToFit(.zero, NSMakeSize(30, 30), thatFit: true)
        settings.scaleOnClick = true
        
        settings.contextMenu = { [weak arguments] in
            return arguments?.contextMenu()
        }
        needsLayout = true
    }
    
    override func layout() {
        super.layout()
        guard self.state != nil else {
            return
        }
        let text_w = frame.size.width - 80 - 10 - 40

        title.resize(text_w)
        status.resize(text_w)

        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        
        guard let state = self.state else {
            return
        }
        let hasSidebar = state.filterData.sidebar && !state.filterData.isEmpty

        let minX = !hasSidebar ? Window.controlsInset + 15 : 0
        
        var title_r = title.centerFrameX(y: 10)
        title_r.origin.x = max(title_r.minX, minX)
        
        var status_r = status.centerFrameX(y: title_r.maxY + 1)
        status_r.origin.x = max(status_r.minX, minX)

        transition.updateFrame(view: title, frame: title_r)
        transition.updateFrame(view: status, frame: status_r)
        
        transition.updateFrame(view: settings, frame: settings.centerFrameY(x: size.width - 10 - settings.frame.width))
    }
}

extension StoryRevealModel {
    var interfaceState: StoryListChatListRowItem.InterfaceState {
        switch self.presentation {
        case .revealed:
            return .revealed
        case .concealed:
            return .concealed
        case let .moving(fraction, opening, tracking):
            return .progress(fraction, opening ? .concealed : .revealed, tracking)
        }
    }
}

public class PeerListContainerView : Control {
    
    public override func removeFromSuperview() {
        super.removeFromSuperview()
    }
    
    
    public var layoutBottomOverlay: ((CGFloat, ContainedViewLayoutTransition) -> NSRect?)?

    public var contentBottomInset: CGFloat = 0 {
        didSet {
            guard contentBottomInset != oldValue else {
                return
            }
            tableView.contentInsets.bottom = contentBottomInset
            updateScrollerInset(animated: false)
            updateBottomControls(size: frame.size, transition: .immediate)
        }
    }

    private var downloads: DownloadsControl?
    private var removalUndo: ChatRemovalUndoView?
    private var proxy: ProxyView?
    private var compose:ImageButton?
    private var backButton: ImageButton?
    private var glassContainer: NSView?

    private var contactsSort: TextButton?

    
    private var forumTitle: TitleForumView?
    
    private var scrollerView: ChatNavigationScroller?
    
    public let backgroundView = View(frame: NSZeroRect)
    
    public let tableView = TableView(frame:NSZeroRect, drawBorder: true)
    
    
    private let containerView = Control()
    private let statusContainer = Control()
    
    public let searchView:SearchView = SearchView(frame:NSMakeRect(10, 0, 0, 0))
    
    
    fileprivate let titleView = TitleView(frame: .zero)
    
    private var webapps: WebappsControl?
        
    
    public var searchViewRect: NSRect {
        var stories: CGFloat = 0
        if let state = self.state, let storiesItem = self.storiesItem, state.splitState != .minimisize, state.mode.isPlain || state.mode.isCommunity {
            stories = storiesItem.navigationHeight
        }
        let y = navigationHeight - stories

        return NSMakeRect(0, max(0, y), frame.width, frame.height - y)
    }

    public var mode: PeerListMode = .plain

    public var communityTitle: String? = nil {
        didSet {
            if communityTitle != oldValue {
                needsLayout = true
            }
        }
    }
    private let borderView = View()
    private let forumSeparatorView = View()
    private let tableMaskLayer = CALayer()
    private var layoutSize: NSSize?

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
    }


    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizesSubviews = false

        backgroundView.layer?.opacity = 0

        containerView.layer?.masksToBounds = false

        tableView.wantsLayer = true
        tableView.layer?.masksToBounds = true
        tableMaskLayer.backgroundColor = NSColor.black.cgColor
        tableMaskLayer.disableActions()
        tableView.layer?.mask = tableMaskLayer

        addSubview(backgroundView)
        addSubview(tableView)
        addSubview(containerView)
        addSubview(borderView)
        addSubview(forumSeparatorView)
        forumSeparatorView.isHidden = true


        statusContainer.handleScrollEventOnInteractionEnabled = true
        statusContainer.userInteractionEnabled = false
        statusContainer.isEventLess = true
        statusContainer.isAccessibilityDecorative = true
        containerView.isAccessibilityDecorative = true
        
        searchView.externalScroll = { [weak self] event in
            self?.tableView.scrollWheel(with: event)
        }
        
        statusContainer.addSubview(titleView)
        
        containerView.addSubview(statusContainer)
        
        containerView.addSubview(searchView)
        
        
        tableView.getBackgroundColor = {
            .clear
        }
        
        titleView.scaleOnClick = true
        
       
        
        updateLocalizationAndTheme(theme: theme)
        
        
    }
    
    private var state: PeerListState?
    private var arguments: Arguments?
    
    private var storiesItem: StoryListChatListRowItem?
    private var storiesView: StoryListChatListRowView?
    
    private var foldersItem: ChatListRevealItem?
    private var foldersView: ChatListRevealView?
    

    
    public var openProxy:((Control)->Void)? = nil
    public var openCurrentProfile:((PeerId)->Void)? = nil
    public var openStatus:((Control)->Void)? = nil {
        didSet {
            titleView.openStatus = { [weak self] control in
                self?.openStatus?(control)
            }
        }
    }

    fileprivate func updateState(_ state: PeerListState, arguments: Arguments, animated: Bool) {
        
        let previous = self.state
        
        let animated = animated && self.state?.splitState == state.splitState && self.state != nil
        let prevSearchState = self.state?.searchState
        let prevSplitState = self.state?.splitState
        let prevAppear = self.state?.appear
        self.state = state
        self.arguments = arguments

        if prevSearchState != state.searchState || prevSplitState != state.splitState || prevAppear != state.appear {
            applyDownloadsVisibility(animated: animated)
        }
        if prevSplitState != state.splitState || prevAppear != state.appear {
            applyRemovalUndoVisibility(animated: animated)
        }

        self.mode = state.mode
        let displaysFullForumHeader = state.splitState != .minimisize && state.mode.isFullForum

        let hideHeader = state.splitState == .minimisize && state.filterData.sidebar

        if !hideHeader, let stories = state.stories, state.hasStories {
            self.storiesItem = .init(frame.size, stableId: 0, context: arguments.context, isArchive: state.mode.groupId == .archive, state: stories, open: arguments.openStory, getInterfaceState: arguments.getStoryInterfaceState, reveal: arguments.revealStoriesState)
            storiesItem?.table = self.tableView
        } else {
            self.storiesItem = nil
        }
        
        if !state.filterData.isEmpty && !state.filterData.sidebar, state.splitState != .minimisize, state.mode == .plain, state.searchState == .None {
            self.foldersItem = .init(frame.size, context: arguments.context, tabs: state.filterData.tabs, selected: state.filterData.filter, counters: state.filterData.badges, action: arguments.setupFilter, openSettings: {
                arguments.openFilterSettings(.allChats)
            }, menuItems: arguments.tabsMenuItems, getCurrentStoriesState: { [weak self] in
                if let state = self?.arguments?.getStoryInterfaceState(), let tableView = self?.tableView {
                    return (state, tableView)
                }
                return nil
            })
            foldersItem?.table = self.tableView
        } else {
            self.foldersItem = nil
        }

        
        let hasCompose = state.splitState != .minimisize && (state.isContacts || state.mode.isSavedMessages || state.mode == .plain || state.mode.groupId == .archive || state.mode.isCommunity)
        
        if hasCompose {
            let current: ImageButton
            if let view = self.compose {
                current = view
            } else {
                current = ImageButton(frame: NSMakeRect(frame.width - 10 - 30, (statusHeight - 30)/2.0, 30, 30))
                current.layer?.cornerRadius = .cornerRadius
                self.compose = current
                current.autohighlight = false
                current.animates = false
                current.scaleOnClick = true
                statusContainer.addSubview(current)
            }
            if state.isContacts {
                current.set(image: theme.icons.contactsNewContact, for: .Normal)
                current.set(image: theme.icons.contactsNewContact, for: .Hover)
                current.setAccessibilityLabel(strings().voiceOverContactsAddContact)
            } else if state.mode.groupId == .archive || state.mode.isSavedMessages || state.mode.isCommunity {
                current.set(image: theme.icons.chatActions.highlight(color: theme.colors.accent), for: .Normal)
                current.set(image: theme.icons.chatActions.highlight(color: theme.colors.accent), for: .Hover)
                current.setAccessibilityLabel(strings().voiceOverCommonMore)
            } else {
                current.set(image: theme.icons.composeNewChat, for: .Normal)
                current.set(image: theme.icons.composeNewChat, for: .Hover)
                current.setAccessibilityLabel(strings().voiceOverNavigationCompose)
            }
            current.contextMenu = { [weak arguments] in
                return arguments?.contextMenu()
            }
        } else if let view = self.compose {
            performSubviewRemoval(view, animated: animated)
            self.compose = nil
        }
        
        let hasForumTitle = state.splitState != .minimisize && (delta != nil || state.appear == .short || displaysFullForumHeader)
        
        if hasForumTitle, let forumData = state.forumPeer {
            let current: TitleForumView
            if let view = self.forumTitle {
                 current = view
            } else {
                current = TitleForumView(frame: NSMakeRect(0, 0, frame.width, 50))
                self.forumTitle = current
                statusContainer.addSubview(current)
                
                current.set(handler: { [weak self] _ in
                    self?.openCurrentProfile?(forumData.peer.id)
                }, for: .Click)
            }
            current.update(state, forumData: forumData, arguments: arguments)
            
        } else if let view = self.forumTitle {
            performSubviewRemoval(view, animated: animated)
            self.forumTitle = nil
        }
        
        self.titleView.isHidden = (state.splitState == .minimisize) || (!mode.isPlain && !mode.isCommunity) || mode.isForumLike
        
        let componentSize = NSMakeSize(30, 30)
        
        var controlPoint = NSMakePoint(frame.width - 10, floorToScreenPixels(backingScaleFactor, (containerView.frame.height - componentSize.height)/2.0))
        
        if let compose = self.compose {
            controlPoint.x -= compose.frame.width
        }
        
        let hasControls = state.splitState != .minimisize && mode.isPlain && mode == .plain
        
        let hasProxy = (!state.proxySettings.servers.isEmpty || state.proxySettings.effectiveActiveServer != nil) && hasControls && !state.isContacts
        
        
        if hasProxy {
            controlPoint.x -= componentSize.width
            
            let current: ProxyView
            if let view = self.proxy {
                current = view
            } else {
                current = ProxyView(frame: CGRect(origin: controlPoint, size: componentSize))
                self.proxy = current
                self.statusContainer.addSubview(current, positioned: .below, relativeTo: nil)
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
                current.set(handler: { [weak self] control in
                    self?.openProxy?(control)
                }, for: .Click)
            }
            current.update(state.proxySettings, connection: state.connectionStatus, animated: animated)
            
        } else if let view = self.proxy {
            performSubviewRemoval(view, animated: animated)
            self.proxy = nil
        }

        glassContainer?.removeFromSuperview()
        glassContainer = nil

        if let item = self.storiesItem {
            let current: StoryListChatListRowView
            if let view = self.storiesView {
                current = view
            } else {
                current = StoryListChatListRowView(frame: NSMakeRect(0, 50, frame.width, item.height))
                containerView.addSubview(current, positioned: .below, relativeTo: statusContainer)
                self.storiesView = current
                current.forwardVerticalScroll = { [weak self] event in
                    self?.tableView.scrollWheel(with: event)
                }
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            current.set(item: item, animated: animated)
        } else if let view = self.storiesView {
            performSubviewRemoval(view, animated: animated)
            self.storiesView = nil
        }
        
        if let item = self.foldersItem {
            let current: ChatListRevealView
            if let view = self.foldersView {
                current = view
            } else {
                current = ChatListRevealView(frame: NSMakeRect(0, navigationHeight - item.height, frame.width, item.height))
                containerView.addSubview(current, positioned: .below, relativeTo: statusContainer)
                self.foldersView = current
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            current.set(item: item, animated: animated)
        } else if let view = self.foldersView {
            performSubviewRemoval(view, animated: animated)
            self.foldersView = nil
        }
        
       
        var _: [SearchView.TagInfo] = []
//        if let peerTag = state.peerTag {
//            tags.append(.init(text: peerTag._asPeer().compactDisplayTitle.prefixWithDots(10)))
//        }
//        if let hashtag = state.hashtag {
//            tags.append(.init(text: hashtag.text, isVisible: false))
//        }
//        self.searchView.updateTags(tags, theme.search.searchImage)
        
        let hasSidebar = state.filterData.sidebar && !state.filterData.isEmpty
        if !hideHeader, hasSidebar || state.mode.groupId == .archive || state.mode.isCommunity || displaysFullForumHeader || state.appear == .short, (state.searchState != .Focus || hasSidebar) {
            let current: ImageButton
            var isNew = false
            if let view = self.backButton {
                current = view
            } else {
                current = ImageButton(frame: .zero)
                current.setAccessibilityLabel(strings().voiceOverCommonBack)
                self.backButton = current
                current.animates = false
                current.scaleOnClick = true
                current.set(handler: { [weak arguments, weak self] _ in
                    arguments?.getController()?.navigationController?.back()
                    self?.searchView.cancel(true)
                }, for: .Click)
                containerView.addSubview(current, positioned: .below, relativeTo: searchView)
                isNew = true
            }

            if state.splitState == .minimisize {
                current.set(image: theme.icons.instantViewBack, for: .Normal)
            } else {
                current.set(image: theme.icons.chatNavigationBack, for: .Normal)
            }
            current.sizeToFit(.zero, NSMakeSize(30, 30), thatFit: true)
            if isNew {
                current.frame = backRect(size: frame.size)
            }
            
        } else if let view = self.backButton {
            performSubviewRemoval(view, animated: animated)
            self.backButton = nil
        }
        
        
                
//                        default:
//                        default:
        
        if let view = self.contactsSort {
            performSubviewRemoval(view, animated: animated)
            self.contactsSort = nil
        }
        
        if previous?.appear != state.appear {
            self.delta = nil
        } else if previous?.splitState != state.splitState {
            self.delta = nil
        }
        
        self.updateScroller(animated: animated)

        
        let transition: ContainedViewLayoutTransition
        if animated, previous?.splitState == state.splitState {
            if previous?.appear != state.appear {
                transition = .animated(duration: 0.4, curve: .spring)
            } else {
                transition = .animated(duration: 0.2, curve: .easeOut)
            }
        } else {
            transition = .immediate
        }
        self.updateLayout(self.frame.size, transition: transition)
    }
    
    public func updateScroller(animated: Bool) {
        guard let state else {
            return
        }
        
        let isShown: Bool = !state.filterData.isTop || tableView.documentOffset.y > tableView.frame.height
        
        if !state.isContacts, isShown {
            let current: ChatNavigationScroller
            if let view = self.scrollerView {
                current = view
            } else {
                current = ChatNavigationScroller(.scrollerUp)
                addSubview(current)
                self.scrollerView = current
                updateBottomControls(size: frame.size, transition: .immediate)
                
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            }
            current.setSingle(handler: { [weak self] _ in
                self?.arguments?.getController()?.scrollup()
            }, for: .Click)
            
        } else if let view = self.scrollerView {
            performSubviewRemoval(view, animated: animated)
            self.scrollerView = nil
        }
    }
    
    
    
    private func updateTags(_ state: PeerListState,updateSearchTags: @escaping(PeerListState.SelectedSearchTag)->Void) {
        if searchView.customSearchControl == nil {
            searchView.customSearchControl = CustomSearchController(clickHandler: { _, _ in
                
            }, deleteTag: { index in
                updateSearchTags(.chats)
            }, icon: theme.search.searchImage)
        }
    }
    
    fileprivate func searchStateChanged(_ state: PeerListState, arguments: Arguments, animated: Bool, updateSearchTags: @escaping(PeerListState.SelectedSearchTag)->Void) {
        self.updateTags(state, updateSearchTags: updateSearchTags)
        self.updateState(state, arguments: arguments, animated: animated)
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        let theme = (theme as! TelegramPresentationTheme)


        borderView.backgroundColor = theme.colors.border
        forumSeparatorView.backgroundColor = theme.colors.border

        self.backgroundColor = .clear
        self.backgroundView.backgroundColor = .clear

        searchView.searchTheme = .init(theme.colors.background, theme.search.searchImage, theme.search.clearImage, {
            return strings().chatListSearchPlaceholder
        }, theme.search.textColor, theme.search.placeholderColor)
        searchView.layer?.borderWidth = 1
        searchView.layer?.borderColor = theme.colors.border.withAlphaComponent(0.75).cgColor

        self.containerView.backgroundColor = .clear


        super.updateLocalizationAndTheme(theme: theme)

        updateLayout(self.frame.size, transition: .immediate)
    }
    
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layout() {
        super.layout()
        self.updateLayout(frame.size, transition: .immediate)
    }
    
    public private(set) var delta: CGFloat? = nil
    
    public func updateSwipingState(_ state: SwipeState, controller: ViewController) -> Void {
        let transition: ContainedViewLayoutTransition
        switch state {
        case let .swiping(delta, _):
            if controller.stake.keepLeft > 0 {
                self.delta = max(0, min(delta, frame.width - controller.stake.keepLeft))
            } else {
                self.delta = nil
            }
            transition = .immediate
        case .success:
            if controller.stake.keepLeft > 0 {
                self.delta = frame.width - controller.stake.keepLeft
            } else {
                self.delta = nil
            }
            transition = .animated(duration: 0.2, curve: .easeOut)
        case .failed:
            if controller.stake.keepLeft > 0 {
                self.delta = 0
            } else {
                self.delta = nil
            }
            transition = .animated(duration: 0.2, curve: .easeOut)
        case .start:
            if controller.stake.keepLeft > 0 {
                self.delta = 0
            } else {
                self.delta = nil
            }
            transition = .immediate
        }
        if let arguments = arguments, let state = self.state {
            self.updateState(state, arguments: arguments, animated: transition.isAnimated)
        }

        self.updateLayout(frame.size, transition: transition)
    }
    
    private func backRect(size: NSSize) -> NSRect {
        guard let state = self.state else {
            return NSMakeRect(10, 10, 30, 30)
        }
        let hasLeftSidebar = state.filterData.sidebar && !state.filterData.isEmpty
        let inlineBackButton = !hasLeftSidebar && state.splitState != .minimisize && state.splitState != .single
        let edge: CGFloat = 10
        let componentHeight: CGFloat = 30

        if state.splitState == .minimisize {
            // Single-column: button is horizontally centered, 30pt from the top.
            return NSMakeRect(floorToScreenPixels(backingScaleFactor, (size.width - componentHeight) / 2), 30, componentHeight, componentHeight)
        }

        if state.mode.isCommunity || state.mode.isFullForum {
            return NSMakeRect(edge, 10, 30, componentHeight)
        }

        var searchY: CGFloat = self.statusHeight
        if let storiesItem = self.storiesItem {
            searchY += (StoryListChatListRowItem.InterfaceState.revealed.height * storiesItem.progress) + 9 * storiesItem.progress
        }

        if inlineBackButton {
            let buttonSize: CGFloat = 30
            let buttonY = searchY + floorToScreenPixels(backingScaleFactor, (componentHeight - buttonSize) / 2)
            return NSMakeRect(edge, buttonY, buttonSize, buttonSize)
        } else {
            return NSMakeRect(edge, 10, 30, componentHeight)
        }
    }

    public func updateLayout(_ size: NSSize, transition: ContainedViewLayoutTransition) {


        guard let state = self.state, let arguments = self.arguments else {
            return
        }
        let transition: ContainedViewLayoutTransition = layoutSize == size ? transition : .immediate
        layoutSize = size
        let displaysFullForumHeader = state.splitState != .minimisize && state.mode.isFullForum
        
        var maxTitleWidth: CGFloat = max(size.width, 300) - 60
        if let compose = self.compose {
            maxTitleWidth -= compose.frame.width
        }
        if let proxy = self.proxy {
            maxTitleWidth -= proxy.frame.width
        }
        
        self.titleView.updateState(state, arguments: arguments, communityTitle: self.communityTitle, maxWidth: maxTitleWidth, animated: transition.isAnimated)
        
        let offset: CGFloat = navigationHeight
        
        let progress: CGFloat = displaysFullForumHeader ? 0.0 : (getDeltaProgress() ?? (state.appear == .short ? 0.0 : 1.0))
        
        var inset: CGFloat = 0
        
        let containerSize = NSMakeSize(state.splitState == .minimisize ? 90 : size.width, offset)
                
        transition.updateFrame(view: self.containerView, frame: NSMakeRect(0, inset, containerSize.width, offset))
        
        
        transition.updateFrame(view: self.statusContainer, frame: NSMakeRect(0, 0, containerSize.width, statusHeight))
        
        inset = self.statusContainer.frame.maxY


        transition.updateFrame(view: self.backgroundView, frame: size.bounds)
        
        let navigationHeight_ = self.navigationHeight

        transition.updateFrame(view: self.borderView, frame: CGRect(origin: CGPoint(x: 0, y: navigationHeight_ - .borderSize), size: CGSize(width: size.width, height: .borderSize)))
        transition.updateAlpha(view: borderView, alpha: state.searchState == .Focus ? 0 : 1)

        forumSeparatorView.isHidden = !mode.isForumLike || displaysFullForumHeader
        transition.updateFrame(view: forumSeparatorView, frame: NSMakeRect(0, 0, .borderSize, size.height))

        let statusHeight: CGFloat = self.statusHeight


        let componentSize = NSMakeSize(30, 30)
                        
        
        var searchY: CGFloat = statusHeight
        
        if let storiesItem = storiesItem {
            searchY += (StoryListChatListRowItem.InterfaceState.revealed.height * storiesItem.progress) + 9 * storiesItem.progress
        }


        let edge: CGFloat = 10
        let hasLeftSidebar = state.filterData.sidebar && !state.filterData.isEmpty
        let inlineBackButton = self.backButton != nil && !hasLeftSidebar && state.splitState != .minimisize && state.splitState != .single && !state.mode.isCommunity && !displaysFullForumHeader
        let inlineBackButtonGap: CGFloat = 10
        let searchLeading: CGFloat = inlineBackButton ? backRect(size: size).maxX + inlineBackButtonGap : edge
        let searchRect = NSMakeRect(searchLeading, searchY, size.width - searchLeading - edge, componentSize.height)


        let bottomInset: CGFloat = 0

        transition.updateFrame(view: searchView, frame: searchRect)
        searchView.updateLayout(size: searchRect.size, transition: transition)
        searchView.isHidden = state.splitState == .minimisize || (mode.isForumLike && !displaysFullForumHeader)
        


        ContainedViewLayoutTransition.immediate.updateFrame(view: tableView, frame: NSMakeRect(0, 0, size.width, size.height - bottomInset))
        updateTableMask(spaceHeight: navigationHeight)

        updateBottomControls(size: size, transition: transition)
        
        var controlPoint = NSMakePoint(containerSize.width - 14, floorToScreenPixels(backingScaleFactor, (statusHeight - componentSize.height)/2.0))

        controlPoint.x -= componentSize.width
        
        if let compose = compose {
            transition.updateFrame(view: compose, frame: CGRect(origin: controlPoint, size: componentSize))
            if state.splitState == .minimisize {
                transition.updateAlpha(view: compose, alpha: 1)
            } else {
                transition.updateAlpha(view: compose, alpha: progress)
            }
        }
        
        if let view = forumTitle {
            transition.updateFrame(view: view, frame: CGRect(origin: .zero, size: NSMakeSize(size.width, 50)))
            transition.updateAlpha(view: view, alpha: 1 - progress)
        }
        
        if let view = proxy {
            controlPoint.x -= componentSize.width
            transition.updateFrame(view: view, frame: CGRect(origin: controlPoint, size: componentSize))
            transition.updateAlpha(view: view, alpha: progress)
        }

        if let glassContainer = glassContainer {
            var glassFrame: NSRect = .zero
            if let compose = compose, let proxy = proxy {
                glassFrame = compose.frame.union(proxy.frame)
            } else if let compose = compose {
                glassFrame = compose.frame
            }
            transition.updateFrame(view: glassContainer, frame: glassFrame)
            (glassContainer as? LiquidGlassView)?.updateLayout(size: glassFrame.size, transition: transition)
            transition.updateAlpha(view: glassContainer, alpha: progress)
        }

        if let view = self.backButton {
            transition.updateFrame(view: view, frame: backRect(size: size))
            if state.splitState == .minimisize || inlineBackButton || state.mode.groupId == .archive || state.mode.isSavedMessages || state.mode.isCommunity || displaysFullForumHeader {
                transition.updateAlpha(view: view, alpha: 1)
            } else {
                transition.updateAlpha(view: view, alpha: 1 - progress)
            }
        }

        if let view = self.webapps {
            transition.updateFrame(view: view, frame: CGRect(origin: NSMakePoint(10, floorToScreenPixels((50 - view.frame.height) / 2)), size: view.frame.size))
        }

        let storiesShift: CGFloat
        if let storiesItem = storiesItem, storiesItem.itemsCount < 3 {
            storiesShift = StoryListChatListRowItem.smallSize.width / 2 * CGFloat(3 - storiesItem.itemsCount)
        } else {
            storiesShift = 0
        }
        let titlePlusStoryMinX = arguments.navigationBarLeftPosition() + 8 - storiesShift
        let titlePlusStoryMaxX = controlPoint.x - 4
        titleView.displaysStatus = storiesItem == nil || titlePlusStoryMinX + 59 + titleView.size(displayingStatus: true).width <= titlePlusStoryMaxX

        let titlePlusStorySize = titleView.size.width + (59)
        var titlePlusStoryStartX = (size.width - titlePlusStorySize) / 2
        titlePlusStoryStartX = max(titlePlusStoryMinX, titlePlusStoryStartX)
        titlePlusStoryStartX = min(titlePlusStoryMaxX - titlePlusStorySize, titlePlusStoryStartX)

        let storyXStart = titlePlusStoryStartX - 10
        let titleXStart = titlePlusStoryStartX + (59)

        let storyXEnd: CGFloat = 0
        let titleXEnd = (size.width - titleView.size.width) / 2



        var titleX: CGFloat = titleXEnd
        var storyX: CGFloat = storyXEnd

        if let stories = self.storiesItem {
            titleX = titleXEnd - (titleXEnd - titleXStart) * (1 - stories.progress)
            storyX = storyXEnd + (storyXStart - storyXEnd) * (1 - stories.progress)
        }


        transition.updateFrame(view: titleView, frame: CGRect(origin: CGPoint(x: titleX, y: floorToScreenPixels(bsc, (statusHeight - titleView.size.height) / 2) - 2), size: titleView.size))
        titleView.updateLayout(size: titleView.size, transition: transition)
        transition.updateAlpha(view: titleView, alpha: progress)

        if let storiesItem = storiesItem, let view = storiesView {
            let size = NSMakeSize(size.width, storiesItem.height)
                        
            var rect = CGRect(origin: NSMakePoint(storyX, 10 + storiesItem.getInterfaceState().progress * 40), size: size)
                        
            rect.origin.x += (1 - storiesItem.getInterfaceState().progress) * storiesShift
            transition.updateFrame(view: view, frame: rect)
            view.set(item: storiesItem, animated: transition.isAnimated)
            view.updateLayout(size: size, transition: transition)
            transition.updateAlpha(view: view, alpha: progress)
        }
        
        if let foldersItem = foldersItem, let view = foldersView {
            let controlSize = NSMakeSize(size.width, foldersItem.height)
            
            let rect = CGRect(origin: NSMakePoint(0, navigationHeight - controlSize.height), size: controlSize)
                        
            transition.updateFrame(view: view, frame: rect)
            view.set(item: foldersItem, animated: transition.isAnimated)
            
            view.updateLayout(size: size, transition: transition)
        }
        transition.updateAlpha(view: self.backgroundView, alpha: 1 - progress)

        self.updateScrollerInset(animated: transition.isAnimated)

    }
    
    public func getDeltaProgress() -> CGFloat? {
        let progress: CGFloat?
        if let delta = self.delta {
            progress = delta / (frame.width - 70)
        } else {
            if let state = self.state, state.appear == .short {
                progress = 0.0
            } else {
                progress = nil
            }
        }
        return progress
    }
    
    public var navigationHeight: CGFloat {
        guard let state = self.state else {
            return 50
        }

        if case .forum = state.mode, state.splitState != .minimisize, !state.mode.isFullForum {
            return 0
        }
        if state.splitState == .minimisize, state.filterData.sidebar {
            return 0
        }
        var offset: CGFloat = 50



        if state.splitState != .minimisize, state.mode.isPlain || state.mode.isCommunity {

            offset += 40

            if let storiesItem = self.storiesItem {
                offset += storiesItem.navigationHeight
            }
            if let foldersItem = self.foldersItem {
                offset += foldersItem.height
            }
        } else if state.splitState == .minimisize {
            if state.mode.groupId == .archive {
                offset += 16
            } else if state.mode.groupId == .root {
                offset = 36
            }
        }
        return offset
    }
    public var statusHeight: CGFloat {
        guard let state = self.state else {
            return 0
        }
        if !state.mode.isPlain && !state.mode.isCommunity {
            return 10
        }
        let height: CGFloat = 50
        
//        if state.splitState == .minimisize {
//            if !state.filterData.sidebar {
//                height += 40
//            }
//        }
        return height
    }
    
    public func updateScrollerInset(animated: Bool) {
        var top: CGFloat = 0
        self.tableView.enumerateItems(with: { item in
            if let item = item as? ChatListSpaceItem {
                top += item.height
                item.redraw(animated: animated)
            }
            return true
        })
        tableView.scrollerInsets = .init(left: 0, right: 0, top: top, bottom: contentBottomInset)
        updateTableMask(spaceHeight: top)
    }

    public func updateTableMask(spaceHeight: CGFloat) {
        let tableHeight = tableView.frame.height
        guard tableHeight > 0 else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tableMaskLayer.frame = NSMakeRect(0, spaceHeight, tableView.bounds.width, max(0, tableHeight - spaceHeight))
        CATransaction.commit()
    }
    
    public func updateBottomControls(size: NSSize, transition: ContainedViewLayoutTransition) {
        var bottomControlsY = size.height - contentBottomInset
        for view in [downloads as NSView?, removalUndo as NSView?].compactMap({ $0 }) {
            let edge: CGFloat = 12
            let y = bottomControlsY - view.frame.height - edge
            let rect = view is DownloadsControl ? downloadsFrame(in: size, y: y) : NSMakeRect(edge, y, size.width - edge * 2, view.frame.height)
            transition.updateFrame(view: view, frame: rect)
            bottomControlsY = rect.minY
        }
        let overlay = layoutBottomOverlay?(bottomControlsY, transition)
        if let view = self.scrollerView {
            let gap: CGFloat = 12
            let visualInset = (view.frame.height - (view.glassSize?.height ?? view.frame.height)) / 2
            let bottomOffset: CGFloat = downloads != nil || removalUndo != nil ? gap - visualInset : 10
            var rect = NSMakeRect(size.width - view.frame.width - 10, bottomControlsY - view.frame.height - bottomOffset, view.frame.width, view.frame.height)
            if let overlay, overlay.intersects(NSRect(origin: .zero, size: size)) {
                rect.origin.y = min(overlay.midY - rect.height / 2, bottomControlsY - rect.height - gap + visualInset)
                if rect.insetBy(dx: -6, dy: 0).intersects(overlay) {
                    rect.origin.y = overlay.minY - rect.height - gap + visualInset
                }
            }
            transition.updateFrame(view: view, frame: rect)
        }
    }

    private func downloadsFrame(in size: NSSize, y: CGFloat) -> NSRect {
        let width = min(500, max(0, size.width - 40))
        return NSMakeRect(floorToScreenPixels((size.width - width) / 2), y, width, 30)
    }

    private var pendingRemovalUndo: (toast: PendingChatRemovalToast, undo: () -> Void)?

    public func updateRemovalUndo(_ toast: PendingChatRemovalToast?, undo: @escaping () -> Void, animated: Bool) {
        if let toast = toast {
            self.pendingRemovalUndo = (toast: toast, undo: undo)
        } else {
            self.pendingRemovalUndo = nil
        }
        applyRemovalUndoVisibility(animated: animated)
    }

    fileprivate func applyRemovalUndoVisibility(animated: Bool) {
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeInOut) : .immediate
        let edge: CGFloat = 12
        let allowed: Bool
        if let st = self.state {
            allowed = st.splitState != .minimisize && st.appear != .short
        } else {
            allowed = true
        }
        if let pending = self.pendingRemovalUndo, allowed {
            let current: ChatRemovalUndoView
            if let view = self.removalUndo {
                current = view
            } else {
                current = ChatRemovalUndoView(frame: NSMakeRect(edge, frame.height, frame.width - edge * 2, ChatRemovalUndoView.height))
                self.removalUndo = current
                addSubview(current, positioned: .above, relativeTo: self.tableView)
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2, timingFunction: .easeInEaseOut)
                }
            }
            current.update(toast: pending.toast, undo: pending.undo)
        } else if let view = self.removalUndo {
            self.removalUndo = nil
            transition.updateFrame(view: view, frame: NSRect(origin: NSMakePoint(edge, frame.height), size: view.frame.size), completion: { _ in
                view.removeFromSuperview()
            })
        }
        updateBottomControls(size: frame.size, transition: transition)
    }

    private var pendingDownloads: (state: DownloadsSummary.State, context: any AccountContextProtocol, arguments: DownloadsControlArguments)?

    public func updateDownloads(_ state: DownloadsSummary.State, context: any AccountContextProtocol, arguments: DownloadsControlArguments, animated: Bool) {
        self.pendingDownloads = (state, context, arguments)
        applyDownloadsVisibility(animated: animated)
    }

    fileprivate func applyDownloadsVisibility(animated: Bool) {
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeInOut) : .immediate
        let allowed: Bool
        if let st = self.state {
            let hideContent = st.splitState == .minimisize || st.appear == .short
            allowed = !hideContent && st.searchState == .None
        } else {
            allowed = true
        }
        if let pending = self.pendingDownloads, !pending.state.isEmpty, allowed {
            let current: DownloadsControl
            if let view = self.downloads {
                current = view
            } else {
                current = DownloadsControl(frame: downloadsFrame(in: frame.size, y: frame.height))
                self.downloads = current
                addSubview(current, positioned: .above, relativeTo: self.tableView)
                if animated {
                    current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2, timingFunction: .easeInEaseOut)
                }
            }
            current.update(pending.state, context: pending.context, arguments: pending.arguments, animated: animated)
            current.setSingle(handler: { _ in
                pending.arguments.open()
            }, for: .Click)
        } else if let view = self.downloads {
            self.downloads = nil
            transition.updateFrame(view: view, frame: downloadsFrame(in: frame.size, y: frame.height), completion: { _ in
                view.removeFromSuperview()
            })
        }
        updateBottomControls(size: frame.size, transition: transition)
    }
    
}


public enum PeerListMode : Equatable {
    case plain
    case folder(EngineChatList.Group)
    case filter(Int32)
    case forum(PeerId, Bool, Bool)
    case savedMessagesChats(peerId: PeerId)
    case community(PeerId)

    public var isCommunity: Bool {
        switch self {
        case .community:
            return true
        default:
            return false
        }
    }
    public var communityId: PeerId? {
        switch self {
        case let .community(peerId):
            return peerId
        default:
            return nil
        }
    }

    public var isForumLike: Bool {
        switch self {
        case .forum, .savedMessagesChats:
            return true
        default:
            return false
        }
    }
    
    public var isPlain:Bool {
        switch self {
        case .plain:
            return true
        case .forum:
            return true
        case .savedMessagesChats:
            return true
        default:
            if self.groupId == .archive {
                return true
            } else {
                return false
            }
        }
    }
    public var groupId: EngineChatList.Group {
        switch self {
        case let .folder(groupId):
            return groupId
        default:
            return .root
        }
    }
    public var filterId: Int32? {
        switch self {
        case let .filter(id):
            return id
        default:
            return nil
        }
    }
    public var isSavedMessages: Bool {
        switch self {
        case .savedMessagesChats:
            return true
        default:
            return false
        }
    }
    public var isForum: Bool {
        switch self {
        case .forum:
            return true
        default:
            return false
        }
    }
    public var isFullForum: Bool {
        switch self {
        case let .forum(_, isFull, _):
            return isFull
        default:
            return false
        }
    }
    public var location: ChatListControllerLocation {
        switch self {
        case .plain:
            return .chatList(groupId: .root)
        case let .folder(group):
            return .chatList(groupId: group._asGroup())
        case let .forum(peerId, _, _):
            return .forum(peerId: peerId)
        case let .filter(filterId):
            return .chatList(groupId: .group(filterId))
        case let .savedMessagesChats(peerId):
            return .savedMessagesChats(peerId: peerId)
        case .community:
            return .chatList(groupId: .root)
        }
    }
}

private class SearchContainer : Control {
    let tagsView: ScrollableSegmentView
    let searchView: NSView
    
    init(frame frameRect: NSRect, searchView: NSView) {
        self.searchView = searchView
        self.tagsView = .init(frame:NSMakeRect(0, -10, frameRect.width, 40))
        super.init(frame: frameRect)
        addSubview(tagsView)
        addSubview(searchView)
    }
    
    override var sendRightMouseAnyway: Bool {
        return false
    }
    
    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private var state: PeerListState?
    
    fileprivate func update(_ state: PeerListState, animated: Bool, arguments: Arguments?) {

        self.backgroundColor = .clear
        
        let previous = self.state
        if state.searchState == .Focus {
            let current: ScrollableSegmentView = self.tagsView
            
            let presentation = ScrollableSegmentTheme(background: .clear, border: theme.colors.border, selector: theme.colors.accent, inactiveText: theme.colors.grayText, activeText: theme.colors.text, textFont: .normal(.text))
            
            var items: [ScrollableSegmentItem] = []
            let insets = NSEdgeInsets(left: 10, right: 10)
            var index: Int = 0
            
            if let peer = state.hashtag?.peer {
                let tags: [PeerListState.SelectedSearchTag] = [.hashtagThisChat, .hashtagMyMessages, .hashtagPublicPosts]
                for tag in tags {
                    let title: String
                    if tag == .hashtagThisChat {
                        title = peer._asPeer().compactDisplayTitle
                    } else {
                        title = tag.title
                    }
                    items.append(.init(title: title, index: index, uniqueId: Int64(tag.rawValue), selected: state.selectedTag == tag, insets: insets, icon: nil, theme: presentation, equatable: UIEquatable(state)))
                    index += 1
                }
            } else {
                
                let isForum = state.forumPeer != nil
                
                items.append(.init(title: isForum ? strings().chatListTopicsTag : state.peerTag == nil ? strings().chatListChatsTag : strings().chatListMessagesTag, index: index, uniqueId: -4, selected: state.selectedTag == .chats, insets: insets, icon: nil, theme: presentation, equatable: UIEquatable(state)))
                index += 1
                
                if state.hashtag != nil {
                    let tag = PeerListState.SelectedSearchTag.hashtagPublicPosts
                    items.append(.init(title: tag.title, index: index, uniqueId: Int64(tag.rawValue), selected: state.selectedTag == tag, insets: insets, icon: nil, theme: presentation, equatable: UIEquatable(state)))
                    index += 1
                }
                
                if state.peerTag == nil, state.forumPeer == nil, !state.mode.isForumLike, !state.mode.isCommunity {
                    if state.hasDownloads {
                        items.append(.init(title: strings().chatListDownloadsTag, index: index, uniqueId: -3, selected: state.selectedTag == .downloads, insets: insets, icon: nil, theme: presentation, equatable: UIEquatable(state)))
                        index += 1
                    }
                    items.append(.init(title: strings().chatListChannelsTag, index: index, uniqueId: -2, selected: state.selectedTag == .channels, insets: insets, icon: nil, theme: presentation, equatable: UIEquatable(state)))
                    index += 1
                    items.append(.init(title: strings().chatListAppsTag, index: index, uniqueId: -1, selected: state.selectedTag == .apps, insets: insets, icon: nil, theme: presentation, equatable: UIEquatable(state)))
                    index += 1
                    items.append(.init(title: strings().chatListPostsTag, index: index, uniqueId: 0, selected: state.selectedTag == .globalPosts, insets: insets, icon: nil, theme: presentation, equatable: UIEquatable(state)))
                    index += 1

                }
                
                
                let tags:[(MessageTags, String)] = [(.photo, strings().searchFilterPhotos),
                                                    (.video, strings().searchFilterVideos),
                                                    (.webPage, strings().searchFilterLinks),
                                                    (.music, strings().searchFilterMusic),
                                                    (.voiceOrInstantVideo, strings().searchFilterVoice),
                                                    (.gif, strings().searchFilterGIFs),
                                                    (.file, strings().searchFilterFiles)]
                
                for tag in tags {
                    items.append(.init(title: tag.1, index: index, uniqueId: Int64(tag.0.rawValue), selected: state.selectedTag.rawValue == tag.0.rawValue, insets: insets, icon: nil, theme: presentation, equatable: UIEquatable(state)))
                    index += 1
                }
            }
                        
            current.updateItems(items, animated: animated, autoscroll: previous?.selectedTag != state.selectedTag)
            current.theme = presentation
            
            current.didChangeSelectedItem = { [weak arguments] item in
                if let tag = PeerListState.SelectedSearchTag(rawValue: Int32(item.uniqueId)) {
                    arguments?.selectSearchTag(tag)
                }
            }
                        
        }
        self.state = state
        needsLayout = true
    }
    
    override func layout() {
        super.layout()
        tagsView.frame = NSMakeRect(0, -10, frame.width, 40)
        self.searchView.frame = NSMakeRect(0, tagsView.frame.maxY, frame.width, frame.height - tagsView.frame.maxY)
    }
}

open class PeersListController<Context: AccountContextProtocol>: TelegramGenericViewController<PeerListContainerView, Context>, TableViewDelegate {
    
    
    open func findGroupStableId(for stableId: AnyHashable) -> AnyHashable? {
        return nil
    }
    
    public let stateValue: Atomic<PeerListState>
    private let stateSignal: ValuePromise<PeerListState>
    open var stateUpdater: Signal<PeerListState, NoError> {
        return stateSignal.get()
    }
    

    open var filterSignal : Signal<FilterData, NoError> {
        return self.stateSignal.get() |> map { $0.filterData }
    }
    open var filterValue: FilterData {
        return self.stateValue.with { $0.filterData }
    }

    private let forumPeerData: Promise<PeerListState.ForumData?> = Promise(nil)
    public let storyList: Signal<EngineStorySubscriptions, NoError>?

    
    private let progressDisposable = MetaDisposable()
    private let createSecretChatDisposable = MetaDisposable()
    private let actionsDisposable = DisposableSet()
    private let followGlobal:Bool
    private let searchOptions: AppSearchOptions
    
    
    
    private var tempImportersContext: PeerInvitationImportersContext? = nil
    
    public private(set) var searchSection: SectionViewController? = nil
    private var searchContainer: SearchContainer?

    private let appearMode: ValuePromise<PeerListState.AppearMode> = ValuePromise(.normal, ignoreRepeated: true)
    private let controllerAppear: ValuePromise<PeerListState.AppearMode> = ValuePromise(.normal, ignoreRepeated: true)
    
    public let mode:PeerListMode
    
    open func updateState(_ f:(PeerListState)->PeerListState) -> Void {
        self.stateSignal.set(self.stateValue.modify(f))
    }
        
    open func updateHiddenItemsState(_ f:(PeerListHiddenItems)->PeerListHiddenItems) {
        
    
        updateState { current in
            var current = current
            current.hiddenItems = f(current.hiddenItems)
            return current
        }
        
        let value = self.stateValue.with { $0.hiddenItems.archive }
        FastSettings.archiveStatus = value

    }
    
    public let topics: ForumChannelTopics?
    public let isContacts: Bool
    open var revealListener: TableScrollListener!

    
    public init(_ context: Context, isContacts: Bool = false, followGlobal:Bool = true, mode: PeerListMode = .plain, searchOptions: AppSearchOptions = [.chats, .messages]) {
        self.followGlobal = followGlobal
        self.mode = mode
        self.stateValue = Atomic(value: .initialize(isContacts))
        self.stateSignal = ValuePromise(.initialize(isContacts), ignoreRepeated: true)

        self.isContacts = isContacts
        self.searchOptions = searchOptions
        switch mode {
        case let .forum(peerId, _, _):
            self.topics = ForumChannelTopics(account: context.account, peerId: peerId)
        default:
            self.topics = nil
        }
        if mode.isPlain && !isContacts {
            self.storyList = context.engine.messages.storySubscriptions(isHidden: mode.groupId == .archive)
        } else {
            self.storyList = nil
        }
        super.init(context)

        if case let .forum(peerId, _, _) = mode, mode.isFullForum {
            self.forumPeerData.set(context.account.postbox.peerView(id: peerId) |> map { view -> PeerListState.ForumData? in
                if let peer = peerViewMainPeer(view) as? TelegramChannel, TelegramUtilsHooks.shared.peerIsForum(peer) {
                    return .init(peer: peer, peerView: view, online: 0)
                } else {
                    return nil
                }
            })
        }

        self.bar = .init(height: 0)
        self.insets = NSEdgeInsets()

    }
    
    open override var containerCornerRadius: CGFloat {
        return 0
    }
    
    open override var redirectUserInterfaceCalls: Bool {
        return true
    }

    open override var wantsContainerGlass: Bool {
        return false
    }

    open override var responderPriority: HandlerPriority {
        return .low
    }
    
    deinit {
        progressDisposable.dispose()
        createSecretChatDisposable.dispose()
        actionsDisposable.dispose()
    }
    
    open override func viewDidResized(_ size: NSSize) {
        super.viewDidResized(size)
    }
    
    open func makeDownloadSearch() {
        showDownloads(animated: true)
    }
    
    open func showDownloads(animated: Bool) {
        
        self.genericView.searchView.change(state: .Focus,  true)
        if let controller = self.searchSection {
            let ready = controller.ready.get()
            |> filter { $0 }
            |> take(1)
            
            _ = ready.startStandalone(next: { [weak self] _ in
                guard let `self` = self, let searchSection = self.searchSection else {
                    return
                }
                
                let index = searchSection.sections.firstIndex(where: { $0.title() == "\(PeerListState.SelectedSearchTag.downloads.rawValue)"})
                
                if let index {
                    searchSection.select(index, false)
                }
            })
        }
    }
    
    open func updateHighlightEvents(_ hasChat: Bool) {
        if let searchSection {
            for section in searchSection.sections {
                if let controller = section.controller as? SearchController<Context>, controller.isLoaded() {
                    controller.updateHighlightEvents(hasChat)
                }
            }
        }
    }
    
    open func makeHashtag(_ hashtag: PeerListState.Hashtag, cached: CachedSearchMessages? = nil) {
        self.updateState { current in
            var current = current
            current.hashtag = hashtag
            current.selectedTag = hashtag.mode
            current.searchQuery = hashtag.text
            return current
        }

        self.genericView.searchView.setString(hashtag.text)

        if hashtag.peer == nil {
                        
            if let cached {
                let section = self.searchSection?.sections.first(where:  {
                    $0.title() == "\(PeerListState.SelectedSearchTag.hashtagPublicPosts.rawValue)"
                })?.controller as? SearchController<Context>
                
                section?.setCachedMessages(cached)
            }
            
            self.takeArguments()?.selectSearchTag(.hashtagPublicPosts)

        }
    }

    open func globalSearch(_ query: String, peer: EnginePeer?, cached: CachedSearchMessages?, isSuperTag: Bool) {
        let context = self.context

        if query.isEmpty {
            self.genericView.searchView.change(state: .Focus, true)
        } else {
            let invoke = { [weak self] in
                if let peer {
                    let mode: PeerListState.SelectedSearchTag
                    if isSuperTag {
                        mode = .hashtagThisChat
                    } else if case let .channel(channel) = peer, case .broadcast = channel.info, !(channel.addressName ?? "").isEmpty {
                        mode = .hashtagPublicPosts
                    } else {
                        mode = .hashtagThisChat
                    }
                    self?.makeHashtag(.init(mode: mode, peer: peer, text: query), cached: cached)
                } else {
                    self?.makeHashtag(.init(mode: .hashtagPublicPosts, peer: nil, text: query), cached: cached)
                }
                self?.genericView.searchView.change(state: .Focus, false)
            }

            switch context.layout {
            case .single:
                context.bindings.rootNavigation().back()
                Queue.mainQueue().justDispatch(invoke)
            case .minimisize:
                context.bindings.needFullsize()
                Queue.mainQueue().justDispatch(invoke)
            default:
                invoke()
            }
        }
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        updateContainerContentInsets(containerContentInsets, transition: .immediate)
        let context = self.context
        let mode = self.mode
        let isContacts = self.isContacts
        #if DEBUG
        if mode == .plain, !isContacts {
            StoryRevealLabRegistry.target = self
        }
        #endif
        
        
        genericView.customHandler.size = { [weak self] size in
            let frame = self?.genericView.searchViewRect ?? size.bounds
            self?.searchContainer?.frame = frame
        }
        
        
        switch mode {
        case .savedMessagesChats:
            let signal = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.DisplaySavedChatsAsTopics()) |> deliverOnMainQueue
            actionsDisposable.add(signal.startStrict(next: { [weak self] value in
                self?.updateState { current in
                    var current = current
                    current.displaySavedAsTopics = value
                    return current
                }
            }))
        default:
            break
        }
        
        actionsDisposable.add(context.engine.peers.requestGlobalRecommendedChannelsIfNeeded().startStrict())
                
        genericView.tableView._scrollDidEndLiveScrolling = { [weak self] in
            self?.storyRevealDriver.finishIfPartial()
        }
        
        revealListener = .init(dispatchWhenVisibleRangeUpdated: false, { [weak self] _ in
            self?.processScroll()
        })
        
        genericView.tableView.applyExternalScroll = { [weak self] event in
            return self?.processScroll(event) ?? false
        }

        genericView.tableView.addScroll(listener: revealListener)
        
        genericView.tableView.addScroll(listener: .init(dispatchWhenVisibleRangeUpdated: false, { [weak self] position in
            self?.genericView.updateScroller(animated: true)
        }))
        

        genericView.titleView.set(handler: { [weak self] _ in
            self?.toggleStoriesState()
        }, for: .Click)
        
        
        let actionsDisposable = self.actionsDisposable
        
        actionsDisposable.add((context.cancelGlobalSearch.get() |> deliverOnMainQueue).start(next: { [weak self] animated in
            self?.genericView.searchView.cancel(animated)
        }))
        
        genericView.mode = mode
        
        if followGlobal {
            let combined = combineLatest(queue: .mainQueue(), context.globalPeerHandler.get(), context.globalForumId.get())
            
            actionsDisposable.add(combined.start(next: { [weak self] location, forumId in
                guard let `self` = self else {return}
                self.changeSelection(location, globalForumId: forumId)
                if location == nil {
                    if !self.genericView.searchView.isEmpty {
                        _ = self.window?.makeFirstResponder(self.genericView.searchView.input)
                    }
                }
            }))
        }
        
        if self.navigationController?.modalAction is ChatListForwardAction {
            self.setCenterTitle(strings().chatForwardActionHeader)
        }
        
        if self.navigationController?.modalAction is ChatInterfaceInlineResultAction {
            self.setCenterTitle(strings().chatShareInlineResultActionHeader)
        }
        
        genericView.tableView.delegate = self
        
        let state = self.stateSignal
        let stateValue = self.stateValue
       
        let updateState:((PeerListState)->PeerListState) -> Void = { f in
            state.set(stateValue.modify(f))
        }
        

        let layoutSignal = context.layoutValue
        
        let proxy = proxySettings(accountManager: context.sharedContext.accountManager) |> mapToSignal { ps -> Signal<(ProxySettings, ConnectionStatus), NoError> in
            return context.account.network.connectionStatus |> map { status -> (ProxySettings, ConnectionStatus) in
                return (ps, status)
            }
        }
        
        let peer: Signal<PeerEquatable?, NoError> = getPeerView(peerId: context.peerId, postbox: context.account.postbox) |> map { peer in
            if let peer = peer {
                return PeerEquatable(peer)
            } else {
                return nil
            }
        }
        let forumPeer: Signal<PeerListState.ForumData?, NoError> = self.forumPeerData.get()
        
        
        let postbox = context.account.postbox
        let previousPeerCache = Atomic<[PeerId: Peer]>(value: [:])
        let previousActivities = Atomic<PeerListState.InputActivities?>(value: nil)
        let peerInputActivities = context.account.allPeerInputActivities()
                                           |> mapToSignal { activitiesByPeerId -> Signal<[PeerActivitySpace: [PeerListState.InputActivities.Activity]], NoError> in
                var foundAllPeers = true
                var cachedResult: [PeerActivitySpace: [PeerListState.InputActivities.Activity]] = [:]
                previousPeerCache.with { dict -> Void in
                    for (chatPeerId, activities) in activitiesByPeerId {
                        
                        var cachedChatResult: [PeerListState.InputActivities.Activity] = []
                        for (peerId, activity) in activities {
                            if let peer = dict[peerId] {
                                cachedChatResult.append(PeerListState.InputActivities.Activity(peer, activity))
                            } else {
                                foundAllPeers = false
                                break
                            }
                            cachedResult[chatPeerId] = cachedChatResult
                        }
                    }
                }
                if foundAllPeers {
                    return .single(cachedResult)
                } else {
                    return postbox.transaction { transaction -> [PeerActivitySpace: [PeerListState.InputActivities.Activity]] in
                        var result: [PeerActivitySpace: [PeerListState.InputActivities.Activity]] = [:]
                        var peerCache: [PeerId: Peer] = [:]
                        for (chatPeerId, activities) in activitiesByPeerId {
                            
                            var chatResult: [PeerListState.InputActivities.Activity] = []
                            for (peerId, activity) in activities {
                                if let peer = transaction.getPeer(peerId) {
                                    chatResult.append(PeerListState.InputActivities.Activity(peer, activity))
                                    peerCache[peerId] = peer
                                }
                            }
                            result[chatPeerId] = chatResult
                        }
                        let _ = previousPeerCache.swap(peerCache)
                        return result
                    }
                }
            }
            |> map { activities -> PeerListState.InputActivities in
                return previousActivities.modify { current in
                    var updated = false
                    let currentList: [PeerActivitySpace: [PeerListState.InputActivities.Activity]] = current?.activities ?? [:]
                    if currentList.count != activities.count {
                        updated = true
                    } else {
                        outer: for (space, currentValue) in currentList {
                            if let value = activities[space] {
                                if currentValue.count != value.count {
                                    updated = true
                                    break outer
                                } else {
                                    for i in 0 ..< currentValue.count {
                                        if currentValue[i] != value[i] {
                                            updated = true
                                            break outer
                                        }
                                    }
                                }
                            } else {
                                updated = true
                                break outer
                            }
                        }
                    }
                    if updated {
                        if activities.isEmpty {
                            return .init(activities: [:])
                        } else {
                            return .init(activities: activities)
                        }
                    } else {
                        return current
                    }
                } ?? .init(activities: [:])
            }
        let inputActivities: Signal<PeerListState.InputActivities, NoError> = isContacts ? .single(.init(activities: [:])) : peerInputActivities
        
        let isFull: Bool
        switch mode {
        case let .forum(_, value, _):
            isFull = value
        default:
            isFull = true
        }
                
        let storyList = self.storyList
        let storyState: Signal<EngineStorySubscriptions?, NoError>
        if let storyList = storyList {
            storyState = storyList |> map(Optional.init)
        } else {
            storyState = .single(nil)
        }
        
        let privacy: Promise<GlobalPrivacySettings?> = Promise(nil)
       
        
        let hasRecentDownload = recentDownloadItems(postbox: context.account.postbox) |> map { $0.count > 0 }
        let hasDownloading = (context.fetchManager as! FetchManagerImpl).entriesSummary |> map { $0.count > 0 }
        
        let hasDownloads = combineLatest(hasRecentDownload, hasDownloading) |> map { $0 || $1 }
        
        actionsDisposable.add(combineLatest(queue: .mainQueue(), proxy, layoutSignal, peer, forumPeer, inputActivities, storyState, appearMode.get(), privacy.get(), appearanceSignal, BrowserStateContext.get(context).fullState(), hasDownloads).start(next: { pref, layout, peer, forumPeer, inputActivities, storyState, appearMode, privacy, appearance, webappsState, hasDownloads in
            updateState { value in
                var current: PeerListState = value
                current.proxySettings = pref.0
                current.connectionStatus = pref.1
                current.splitState = layout
                current.controllerAppear = isFull ? .normal : .short
                current.peer = peer
                current.forumPeer = forumPeer
                current.mode = mode
                current.activities = inputActivities
                current.stories = storyState
                current.appear = layout == .minimisize ? .normal : appearMode
                current.isContacts = isContacts
                current.presentation = appearance.presentation
                current.privacy = privacy
                current.webapps = webappsState
                current.hasDownloads = hasDownloads
                return current
            }
        }))
        
        if self.mode.groupId == .archive {
            privacy.set(context.engine.privacy.requestAccountPrivacySettings() |> map { $0.globalSettings } |> map(Optional.init))
        }
        
        let pushController:(ViewController)->Void = { [weak self] c in
            guard let navigation = self?.context.bindings.rootNavigation() else {
                return
            }
            let animated = navigation.stackCount > 1
            navigation.push(c, animated)
        }
                
        let openProxySettings:()->Void = { [weak self] in
            if let controller = self?.context.bindings.rootNavigation().controller as? InputDataController {
                if controller.identifier == "proxy" {
                    return
                }
            }
            if let controller = FeatureNavigationHooks.shared.makeProxyListController(context, { servers in
                var message: String = ""
                for server in servers {
                    message += server.link + "\n\n"
                }
                message = message.trimmed

                showModal(with: ChatListUIHooks.shared.makeShareLinkModal(context, message), for: context.window)
            }, { controller in
                 pushController(controller)
            }) {
                pushController(controller)
            }
        }
        
        
        genericView.openProxy = { _ in
            openProxySettings()
        }
        
        genericView.openCurrentProfile = { peerId in
            ChatListUIHooks.shared.pushPeerInfo(context.bindings.rootNavigation(), context, peerId)

        }
        
        genericView.openStatus = { control in
            let peer = stateValue.with { $0.peer?.peer }
            if let peer = peer as? TelegramUser {
                let callback:(TelegramMediaFile, StarGift.UniqueGift?, Int32?, CGRect?)->Void = { file, starGift, timeout, fromRect in
                    context.reactions.setStatus(file, peer: peer, timestamp: context.timestamp, timeout: timeout, fromRect: fromRect, starGift: starGift)
                }
                if control.popover == nil {
                    showPopover(for: control, with: ChatListUIHooks.shared.makePremiumStatusController(context, callback, peer), edge: .maxY, inset: NSMakePoint(-80, -35), static: true, animationMode: .reveal)
                }
            }
        }
        
        let updateSearch:(SearchState)->Void = { [weak self] state in
            updateState { current in
                var current = current
                current.searchState = state.state
                current.searchQuery = state.request
                if !current.searchQuery.hasPrefix("#") && !current.searchQuery.hasPrefix("$"), current.hashtag != nil {
                    current.hashtag = nil
                    current.peerTag = nil
                    current.selectedTag = .chats
                }
                return current
            }
            let selected = self?.state?.selectedTag ?? .chats
            let sectionIndex = self?.searchSection?.sections.firstIndex(where: { $0.title() == "\(selected.rawValue)" })
            
            if let sectionIndex {
                self?.searchSection?.select(sectionIndex, true)
            }
        }

        genericView.searchView.searchInteractions = SearchInteractions({ [weak self] state, animated in
            updateSearch(state)
            switch state.state {
            case .Focus:
                self?.showSearchController(animated: animated)
                
            case .None:
                self?.hideSearchController(animated: animated)
            }
        }, updateSearch, responderModified: { [weak self] state in
            self?.context.isInGlobalSearch = state.responder
        })
        
        let stateSignal = state.get() |> distinctUntilChanged(isEqual: { lhs, rhs in
            var lhs = lhs
            lhs.activities = rhs.activities
            return lhs == rhs
        })
        
        let previousState: Atomic<PeerListState?> = Atomic(value: nil)
        
        
        let arguments = Arguments(context: context, joinGroupCall: { info in
            if case let .forum(peerId, _, _) = mode {
                let join:(PeerId, Date?, Bool)->Void = { joinAs, _, _ in
                    _ = ChatUIHooks.shared.requestOrJoinGroupCall(context, peerId, joinAs, info.activeCall, info.data?.info, nil, nil).start(next: { result in
                        switch result {
                        case let .samePeer(callContext), let .success(callContext):
                            FeatureNavigationHooks.shared.applyGroupCallResult(context.sharedContext, callContext as AnyObject)
                        default:
                            alert(for: context.window, info: strings().errorAnError)
                        }
                    })
                }
                if let callJoinPeerId = info.callJoinPeerId {
                    join(callJoinPeerId, nil, false)
                } else {
                    FeatureNavigationHooks.shared.selectGroupCallJoiner(context, peerId, join)
                }
            }
        }, joinGroup: { peerId in
            ChatUIHooks.shared.joinChannel(context, peerId)
        }, openPendingRequests: { [weak self] in
            if let importersContext = self?.tempImportersContext, case let .forum(peerId, _, _) = mode {
                let navigation = context.bindings.rootNavigation()
                if let controller = FeatureNavigationHooks.shared.makeRequestJoinMembersController(context, peerId, importersContext, { [weak navigation] in
                    if let links = FeatureNavigationHooks.shared.makeInviteLinksController(context, peerId, false) {
                        navigation?.push(links)
                    }
                }) {
                    navigation.push(controller)
                }
            }
        }, dismissPendingRequests: { peerIds in
            if case let .forum(peerId, _, _) = mode {
                FastSettings.dismissPendingRequests(peerIds, for: peerId)
            }
        }, openStory: { initialId, singlePeer, isHidden in
            ChatUIHooks.shared.showStories(context, isHidden, initialId, singlePeer)
        }, getStoryInterfaceState: { [weak self] in
            guard let `self` = self else {
                return .empty
            }
            if self.state?.splitState == .minimisize {
                return .empty
            }
            if self.state?.hasStories == true {
                return self.storyInterfaceState
            }
            return .empty
        }, revealStoriesState: { [weak self] in
            self?.revealStoriesState()
        }, setupFilter: { [weak self] filter in
            if self?.stateValue.with({ $0.filterData.filter }) != filter {
            }
            self?.navigationController?.back()
            self?.updateState { current in
                var current = current
                current.filterData = current.filterData.withUpdatedFilter(filter)
                return current
            }
            self?.scrollup(force: true)
        }, openFilterSettings: { filter in
            if case .filter = filter {
                context.bindings.rootNavigation().push(ChatListUIHooks.shared.makeChatListFilterController(context, filter))
            } else {
                context.bindings.rootNavigation().push(ChatListUIHooks.shared.makeChatListFiltersListController(context))
            }
        }, tabsMenuItems: { filter, unreadCount, allMuted in
            return ChatListUIHooks.shared.filterContextMenuItems(filter, unreadCount, allMuted, context)
        }, getController: { [weak self] in
            return self
        }, navigationBarLeftPosition: { [weak self] in
            guard let state = self?.state else {
                return 0
            }
            if state.filterData.sidebar && !state.filterData.isEmpty {
                return 0
            } else {
                if case .forum = state.mode {
                    return 0
                } else {
                    if state.splitState != .minimisize {
                        return Window.controlsInset
                    } else {
                        return 0
                    }
                }
            }
        }, contextMenu: { [weak self] in
            let menu = ContextMenu()
            if let custom = self?.customContextMenu() {
                return custom
            }
            if let peer = self?.state?.forumPeer {
                var items: [ContextMenuItem] = []

                let chatController = context.bindings.rootNavigation().controller as? ChatController<Context>
                let infoController = context.bindings.rootNavigation().controller as? ChatListPeerInfoController
                let topicController = context.bindings.rootNavigation().controller as? InputDataController

                if infoController == nil || (infoController?.peerId != peer.peer.id || infoController?.threadInfo != nil) {
                    items.append(ContextMenuItem(strings().forumTopicContextInfo, handler: {
                        ForumUI.openInfo(peer.peer.id, context: context)
                    }, itemImage: MenuAnimation.menu_show_info.value))
                }

                if chatController == nil || (chatController?.chatInteraction.chatLocation != .peer(peer.peer.id)) {
                    items.append(ContextMenuItem(strings().forumTopicContextShowAsMessages, handler: { [weak self] in
                        self?.open(with: .chatId(.chatList(peer.peer.id), peer.peer.id, -1), forceAnimated: true)
                        _ = context.engine.peers.updateForumViewAsMessages(peerId: peer.peer.id, value: true).start()
                    }, itemImage: MenuAnimation.menu_read.value))
                }
               

                if peer.peer.hasPermission(.manageTopics) || peer.peer.hasPermission(.createTopics) {
                    if topicController?.identifier != "ForumTopic" {
                        if !items.isEmpty {
                            items.append(ContextSeparatorItem())
                        }
                        items.append(ContextMenuItem(strings().forumTopicContextNew, handler: {
                            ForumUI.createTopic(peer.peer.id, context: context)
                        }, itemImage: MenuAnimation.menu_edit.value))
                    }
                }

                for item in items {
                    menu.addItem(item)
                }
            } else if isContacts {
                menu.addItem(ContextMenuItem(strings().newContactTitle, handler: {
                    showModal(with: ChatListUIHooks.shared.makeAddContactModal(context), for: context.window)
                }, itemImage: MenuAnimation.menu_add_member.value))
            } else if case .savedMessagesChats = self?.state?.mode {
                
                let displayAsTopics = self?.state?.displaySavedAsTopics ?? false
                
                menu.addItem(ContextMenuItem(strings().chatSavedMessagesViewAsMessages, handler: {
                    context.engine.peers.updateSavedMessagesViewAsTopics(value: false)
                    self?.navigationController?.back()
                    ChatUIHooks.shared.navigateToChat(context.bindings.rootNavigation(), context, .peer(context.peerId))
                }, itemImage: !displayAsTopics ? MenuAnimation.menu_check_selected.value : nil))
                
                menu.addItem(ContextMenuItem(strings().chatSavedMessagesViewAsChats, handler: {
                    context.engine.peers.updateSavedMessagesViewAsTopics(value: true)
                    ForumUI.open(context.peerId, addition: false, context: context)
                }, itemImage: displayAsTopics ? MenuAnimation.menu_check_selected.value : nil))
            } else if self?.state?.mode.groupId == .archive {
                menu.addItem(ContextMenuItem(strings().peerListArchiveSettings, handler: {
                    if let controller = FeatureNavigationHooks.shared.makeArchiveSettingsController(context, self?.state?.privacy, { updated in
                        updateState { current in
                            var current = current
                            current.privacy = updated
                            return current
                        }
                    }) {
                        pushController(controller)
                    }
                }, itemImage: MenuAnimation.menu_gear.value))
            } else {
                let items = [ContextMenuItem(strings().composePopoverNewGroup, handler: { [weak self] in
                    ChatListUIHooks.shared.composeCreateGroup(self?.context)
                }, itemImage: MenuAnimation.menu_create_group.value),
                ContextMenuItem(strings().composePopoverNewSecretChat, handler: { [weak self] in
                    ChatListUIHooks.shared.composeCreateSecretChat(self?.context)
                }, itemImage: MenuAnimation.menu_lock.value),
                ContextMenuItem(strings().composePopoverNewChannel, handler: { [weak self] in
                    ChatListUIHooks.shared.composeCreateChannel(self?.context)
                }, itemImage: MenuAnimation.menu_channel.value)];

                for item in items {
                    menu.addItem(item)
                }
            }
            return menu
        }, selectSearchTag: { [weak self] selected in
            let previous = self?.state
            self?.updateState { current in
                var current = current
                current.selectedTag = selected
                if selected == previous?.selectedTag, selected == .chats {
                    current.peerTag = nil
                    current.hashtag = nil
                }
                return current
            }
            
            let sectionIndex = self?.searchSection?.sections.firstIndex(where: { $0.title() == "\(selected.rawValue)" })
            
            if let sectionIndex {
                self?.searchSection?.select(sectionIndex, true)
            }
        }, setPeerAsTag: { [weak self] peer in
            self?.updateState { current in
                var current = current
                current.peerTag = peer.flatMap { .init($0) }
                return current
            }
        }, toggleContactsSort: { [weak self] sort in
            self?.updateState { current in
                var current = current
                current.contactsSort = sort
                return current
            }
            FastSettings.contactsSort = sort
        })
        
        self.takeArguments = { [weak arguments] in
            return arguments
        }
        
        actionsDisposable.add(stateSignal.start(next: { [weak self] state in
            CATransaction.begin()
            self?.updateState(state, previous: previousState.swap(state), arguments: arguments)
            CATransaction.commit()
        }))
        
        centerBarView.set(handler: { _ in
            switch mode {
            case let .forum(peerId, _, _):
                ForumUI.openInfo(peerId, context: context)
            default:
                break
            }
        }, for: .Click)
    }
    
    open var state: PeerListState? {
        return self.stateValue.with { $0 }
    }
    
    private func updateState(_ state: PeerListState, previous: PeerListState?, arguments: Arguments) {
        
       
        
        if previous?.forumPeer != state.forumPeer {
            if state.forumPeer == nil {
                switch self.mode {
                case .forum:
                    self.navigationController?.back()
                default:
                    break
                }
                return
            } else if let peer = state.forumPeer?.peer, peer.displayForumAsTabs(splitState: state.splitState), TelegramUtilsHooks.shared.peerIsForum(peer) {
                switch self.mode {
                case .forum:
                    self.navigationController?.back()
                default:
                    break
                }
            }
        }
        if previous?.splitState != state.splitState {
            if  case .minimisize = state.splitState {
                if self.genericView.searchView.state == .Focus {
                    self.genericView.searchView.change(state: .None,  false)
                }
            }
            self.genericView.tableView.alwaysOpenRowsOnMouseUp = state.splitState == .single
                        

            genericView.updateLayout(frame.size, transition: .immediate)
        }
                      
        let animated = genericView.window != nil && state.splitState == previous?.splitState && !context.window.inLiveResize
        
        self.genericView.searchStateChanged(state, arguments: arguments, animated: animated, updateSearchTags: { [weak self] value in
            self?.takeArguments()?.selectSearchTag(value)
        })
        
        if let forum = state.forumPeer {
            if forum.peer.participationStatus == .left && previous?.forumPeer?.peer.participationStatus == .member {
                self.navigationController?.back()
            }
        }
        
        if previous?.splitState != state.splitState {
            DispatchQueue.main.async {
                self.genericView.tableView.reloadData()
            }
        }
        
        if let searchSection {
            for section in searchSection.sections {
                if let controller = section.controller as? SearchController<Context> {
                    if let tagRawValue = Int32(section.title()), let tag = PeerListState.SelectedSearchTag(rawValue: tagRawValue) {
                        controller.updateSearchTags(tag.searchTags(state.peerTag?.id, hashtag: state.hashtag))
                        if tag == state.selectedTag {
                            controller.request(with: state.searchQuery)
                        }
                    }
                }
            }
        }
        
        self.searchContainer?.update(state, animated: animated, arguments: arguments)
        
    }
    

        
    private var takeArguments:()->Arguments? = {
        return nil
    }
    
    
    
    
    private var previousLocation: (ChatLocation?, PeerId?) = (nil, nil)
    open func changeSelection(_ location: ChatLocation?, globalForumId: PeerId?) {
        if previousLocation.0 != location {
            if let location = location {
                var id: UIChatListEntryId
                switch location {
                case .peer:
                    switch self.mode {
                    case .savedMessagesChats:
                        id = .empty
                    default:
                        id = .chatId(.chatList(location.peerId), location.peerId, -1)
                    }
                case let .thread(data):
                    let threadId = data.threadId
                    
                    switch self.mode {
                    case .plain, .filter, .folder:
                        if data.isMonoforumPost {
                            id = .chatId(.chatList(location.peerId), location.peerId, -1)
                        } else {
                            id = .forum(location.peerId)
                        }
                    case .forum:
                        id = .chatId(.forum(threadId), location.peerId, -1)
                    case .savedMessagesChats:
                        id = .chatId(.chatList(PeerId(data.threadId)), PeerId(data.threadId), -1)
                    case .community:
                        id = .chatId(.chatList(location.peerId), location.peerId, -1)
                    }
                }
                if self.genericView.tableView.item(stableId: id) == nil {
                    let fId = UIChatListEntryId.forum(location.peerId)
                    if self.genericView.tableView.item(stableId: fId) != nil {
                        id = fId
                    }
                }
                self.genericView.tableView.changeSelection(stableId: id)
            } else {
                self.genericView.tableView.changeSelection(stableId: nil)
            }
        }
        self.previousLocation = (location, globalForumId)
        if globalForumId != nil || location?.threadId != nil {
            self.updateHighlight(globalForumId ?? location?.peerId)
        } else {
            self.updateHighlight(nil)
        }
    }
    
    private func searchSiblingController() -> ViewController? {
        guard let nav = self.navigationController else { return nil }
        let isVisibleSibling: (ViewController) -> Bool = { other in
            if other.stake.keepLeft > 0 { return true }
            if let peers = other as? PeersListController<Context>, peers.mode.isForumLike || peers.mode.isCommunity { return true }
            return false
        }
        if nav.controller === self {
            if let prev = nav.previousController, prev !== self, isVisibleSibling(prev) {
                return prev
            }
        } else if nav.previousController === self {
            if nav.controller !== self, isVisibleSibling(nav.controller) {
                return nav.controller
            }
        }
        return nil
    }

    private func showSearchController(animated: Bool) {
            
        
        if searchSection == nil, let state = self.state {
            
            self.completeUndefiedStates(animated: true)
            let rect = self.genericView.searchViewRect
            let isCommunityHashtag = state.hashtag != nil && mode.isCommunity
            let searchesForum = state.appear == .short || (state.splitState != .minimisize && state.mode.isFullForum)

            let target: SearchController.Target
            if isCommunityHashtag {
                target = .common(.root)
            } else if let peerId = state.forumPeer?.peer.id, searchesForum {
                target = .forum(peerId)
            } else if case let .savedMessagesChats(peerId) = mode {
                target = .savedMessages(peerId)
            } else if case let .community(communityId) = mode {
                target = .community(communityId)
            } else {
                target = .common(.root)
            }
            let searchCommunityId = isCommunityHashtag ? nil : self.mode.communityId
            
            var items: [SectionControllerItem] = []
            
            do {
                let initialTags: SearchTags
                if state.forumPeer != nil, searchesForum {
                    initialTags = .init(messageTags: nil, peerTag: nil)
                } else if case .savedMessagesChats = mode {
                    initialTags = .init(messageTags: nil, peerTag: nil)
                } else {
                    initialTags = .init(messageTags: nil, peerTag: nil)
                }

                let rect = self.genericView.searchViewRect
                let searchController = SearchController<Context>(context: self.context, open: { [weak self] (id, messageId, close) in
                    if let id = id {
                        self?.open(with: id, messageId: messageId, close: close)
                    } else {
                        self?.genericView.searchView.cancel(true)
                    }
                }, options: self.searchOptions, frame: rect, target: target, communityId: searchCommunityId, tags: initialTags)
//                searchController.defaultQuery = self.genericView.searchView.query
                    
                searchController.setPeerAsTag = { [weak self] peer in
                    self?.genericView.searchView.setString("")
                    self?.takeArguments()?.setPeerAsTag(peer)
                }
    
                searchController.navigationController = self.navigationController
                
                items.append(.init(title: { "\(PeerListState.SelectedSearchTag.chats.rawValue)" }, controller: searchController))
            }
            
            
            for tag in PeerListState.SelectedSearchTag.list(state) {
                if tag == .downloads {
                    let controller = DownloadsController(context: context, searchValue: self.genericView.searchView.searchValue |> map { $0.request })
                    controller._frameRect = rect
                    items.append(.init(title: { "\(tag.rawValue)" }, controller: controller))
                } else {
                    let searchController = SearchController<Context>(context: self.context, open: { [weak self] (id, messageId, close) in
                        if let id = id {
                            self?.open(with: id, messageId: messageId, close: close)
                        } else {
                            self?.genericView.searchView.cancel(true)
                        }
                    }, options: tag.searchOptions, frame: rect, target: target, communityId: searchCommunityId, tags: tag.searchTags(state.peerTag?.id, hashtag: state.hashtag))
//                    searchController.defaultQuery = self.genericView.searchView.query

                    searchController.navigationController = self.navigationController
                    
                    
                    items.append(.init(title: { "\(tag.rawValue)" }, controller: searchController))
                }
            }
            

            if searchSection == nil {
                let index = items.firstIndex(where: { $0.title() == "\(state.selectedTag.rawValue)" }) ?? 0
                let searchSection = SectionViewController(sections: items, selected: index, hasBar: false)
                let rect = self.genericView.searchViewRect
                
                searchSection._frameRect = rect
                searchSection.navigationController = self.navigationController
                searchSection.loadViewIfNeeded()
                searchSection.updateContainerContentInsets(containerContentInsets, transition: .immediate)
                searchSection.genericView._backgroundColor = .clear
                searchSection.selectionUpdateHandler = { [weak self] idx in
                    if let searchSection = self?.searchSection {
                        if let sectionTagRaw = Int32(searchSection.sections[idx].title()) {
                            if let tag = PeerListState.SelectedSearchTag(rawValue: sectionTagRaw) {
                                self?.takeArguments()?.selectSearchTag(tag)
                            }
                        }
                        if let controller = searchSection.sections[idx].controller as? SearchController<Context> {
                            self?.progressDisposable.set((controller.isLoading.get() |> deliverOnMainQueue).start(next: { [weak self] isLoading in
                                self?.genericView.searchView.isLoading = isLoading
                            }))
                        } else {
                            self?.progressDisposable.set(nil)
                            self?.genericView.searchView.isLoading = false
                        }
                        
                    }
                }
                
                self.searchSection = searchSection
                
                let signal = searchSection.ready.get() |> take(1)
                _ = signal.start(next: { [weak searchSection, weak self] _ in
                    if let searchSection = searchSection, let self {
                        let container = SearchContainer(frame: rect, searchView: searchSection.view)
                        container.update(state, animated: false, arguments: self.takeArguments())
                        if animated {
                            container.layer?.animateAlpha(from: 0.0, to: 1.0, duration: 0.25, completion:{ [weak self] complete in
                                if complete {
                                    self?.searchSection?.viewDidAppear(animated)
                                }
                            })
                            container.layer?.animateScaleSpring(from: 1.05, to: 1.0, duration: 0.4, bounce: false)
                            container.layer?.animatePosition(from: NSMakePoint(rect.minX, rect.minY + 15), to: rect.origin, duration: 0.4, timingFunction: .spring)
                        } else {
                            self.completeUndefiedStates(animated: false)
                            searchSection.viewDidAppear(animated)
                        }
                        self.navigationController?.addSubview(container)
                        self.searchContainer = container
                        self.genericView.tableView.change(opacity: 0, animated: animated)
                        if let sibling = self.searchSiblingController() {
                            sibling.view._change(opacity: 0, animated: animated)
                        }
                        searchSection.didSetReady = true
                    }
                })
            }
            
        }
    }
    
    private func hideSearchController(animated: Bool) {
        
                
        if let searchSection = self.searchSection, let container = searchContainer {
            
            let animated = animated && searchSection.didSetReady && !searchSection.view.isHidden
            
            searchSection.viewWillDisappear(animated)
            container.layer?.opacity = animated ? 1.0 : 0.0
        
            searchSection.viewDidDisappear(true)
            self.searchSection = nil
            self.searchContainer = nil
            self.genericView.tableView.isHidden = false
            self.genericView.tableView.change(opacity: 1, animated: animated)
            if let sibling = self.searchSiblingController() {
                sibling.view._change(opacity: 1, animated: animated)
            }
        
            container._change(opacity: 0, animated: animated, duration: 0.25, timingFunction: .spring, completion: { [weak container] completed in
                container?.removeFromSuperview()
            })
            if animated {
                container.layer?.animateScaleSpring(from: 1.0, to: 1.05, duration: 0.4, removeOnCompletion: false, bounce: false)
            }

        }
        
        self.takeArguments()?.selectSearchTag(.chats)
        
        self.progressDisposable.set(nil)
        self.genericView.searchView.isLoading = false

    }
    
    open override func focusSearch(animated: Bool, text: String? = nil) {
        genericView.searchView.change(state: .Focus, animated)
        if let text = text {
            genericView.searchView.setString(text)
        }
    }
   
    

    
    open override func escapeKeyAction() -> KeyHandlerResult {
        guard context.layout != .minimisize else {
            return .invoked
        }
        if genericView.tableView.highlightedItem() != nil {
            genericView.tableView.cancelHighlight()
            return .invoked
        }
        if genericView.searchView.state == .None {
            return genericView.searchView.changeResponder() ? .invoked : .rejected
        } else if genericView.searchView.state == .Focus && genericView.searchView.query.length > 0 {
            genericView.searchView.change(state: .None, true)
            return .invoked
        } else if let state = self.state {
            if state.peerTag != nil || state.hashtag != nil {
                self.takeArguments()?.selectSearchTag(.chats)
                return .invoked
            }
        }
        return .rejected
    }
    
    open override func returnKeyAction() -> KeyHandlerResult {
        if let highlighted = genericView.tableView.highlightedItem() {
            _ = genericView.tableView.select(item: highlighted)
            return .invoked
        }
        return .rejected
    }
    
    open var currentSearchTags: SearchTags? {
        if let searchSection, let state {
            if let rawValue = Int32(searchSection.sections[searchSection.selectedIndex].title()), let tag = PeerListState.SelectedSearchTag(rawValue: rawValue) {
                return tag.searchTags(state.peerTag?.id, hashtag: state.hashtag)
            } else {
                return nil
            }
        } else {
            return nil
        }
    }
    
    open func open(with entryId: UIChatListEntryId, messageId:MessageId? = nil, initialAction: ChatInitialAction? = nil, close:Bool = true, addition: Bool = false, forceAnimated: Bool = false, threadId: Int64? = nil, openAsTopics: Bool = false, fullWidthTopics: Bool = false) ->Void {
        
        let navigation = context.bindings.rootNavigation()

        var addition = addition
        var close = close
        if let searchTags = self.currentSearchTags {
            if searchTags.peerTag != nil && searchTags.messageTags != nil {
                addition = true
            }
            if !searchTags.isEmpty {
                close = false
            }
        }
        
        switch entryId {
        case let .chatId(type, peerId, _):
            switch type {
            case let .chatList(peerId):
                
                if openAsTopics {
                    ForumUI.open(peerId, addition: false, context: context, threadId: threadId, fullWidth: fullWidthTopics)
                } else {
                    if let modalAction = navigation.modalAction as? ChatListForwardAction, peerId == context.peerId {
                        _ = Sender.forwardMessages(messageIds: modalAction.messages.map{$0.id}, context: context, peerId: context.peerId, replyId: nil, threadId: nil).start()
                        _ = showModalSuccess(for: context.window, icon: theme.icons.successModalProgress, delay: 1.0).start()
                        modalAction.afterInvoke()
                        navigation.removeModalAction()
                    } else {
                        if mode.isSavedMessages {
                            _ = (ForumUI.openSavedMessages(peerId.toInt64(), context: context, messageId: messageId, initialAction: initialAction) |> take(1)).start()
                        } else {
                            if let current = navigation.controller as? ChatController<Context>, peerId == current.chatInteraction.peerId, let messageId = messageId, current.mode == .history {
                                current.chatInteraction.focusMessageId(nil, .init(messageId: messageId, string: nil), .center(id: 0, innerId: nil, animated: false, focus: .init(focus: true), inset: 0))
                            } else {
                                let chatLocation: ChatLocation = .peer(peerId)
                                
                                let animated = context.layout == .single || forceAnimated

                                ChatListUIHooks.shared.navigateToChat(navigation, self.context, chatLocation, .init(messageId: messageId), initialAction, addition, animated, animated ? .push : ViewControllerStyle.none)
                                
                            }
                        }
                    }
                }
                
                if self.navigationController?.controller !== self {
                    switch entryId {
                    case .chatId(_, _, _):
                        self.navigationController?.back()
                    default:
                        break
                    }
                }
                
            case let .forum(threadId):
                _ = (ForumUI.openTopic(threadId, peerId: peerId, context: context, messageId: messageId) |> take(1)).start()
            }
        case let .groupId(groupId):
            self.navigationController?.push(ChatListController(context, modal: false, mode: .folder(groupId)))
        case let .forum(peerId):
            let current = navigationController?.controller as? ChatListController<Context>
            if case .forum(peerId, _, _) = current?.mode {
                navigationController?.back()
            } else {
                if current?.mode.isForum == true {
                    navigationController?.back()
                }
                self.updateState { current in
                    var current = current
                    current.selectedTag = .chats
                    current.peerTag = nil
                    current.hashtag = nil
                    return current
                }
                self.genericView.searchView.cancelSearch()
                self.genericView.searchView.change(state: .None, true)
                ForumUI.open(peerId, addition: false, context: context, threadId: threadId)
            }
        case .systemDeprecated, .sharedFolderUpdated, .reveal, .empty, .loading, .space, .suspicious, .savedMessageIndex, .custom, .auction, .birthdays, .grace:
            break
        }
        if close {
            self.genericView.searchView.cancel(true)
        }
    }
    
    open func longSelect(row: Int, item: TableRowItem) {
        
    }
    
    open func selectionWillChange(row:Int, item:TableRowItem, byClick: Bool) -> Bool {
        return true
    }
    
    open func selectionDidChange(row:Int, item:TableRowItem, byClick:Bool, isNew:Bool) -> Void {
       
    }
    
    open func isSelectable(row:Int, item:TableRowItem) -> Bool {
        return true
    }
    
    open override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
    }
    
    open func updateScrollerInset(animated: Bool) {
        self.genericView.updateScrollerInset(animated: animated)
    }
    
    
    open func afterTransaction(_ transition: TableUpdateTransition) {
        self.updateScrollerInset(animated: transition.animated)
    }

    open func customContextMenu() -> ContextMenu? {
        return nil
    }
    

    private var effectiveTableView: TableView {
        switch genericView.searchView.state {
        case .Focus:
            if let searchSection {
                let controller = searchSection.sections[searchSection.selectedIndex].controller
                if let controller = controller as? SearchController<Context> {
                    return controller.genericView
                } else if let controller = controller as? InputDataController {
                    return controller.tableView
                } else {
                    return genericView.tableView
                }
            } else {
                return genericView.tableView
            }
        case .None:
            return genericView.tableView
        }
    }

    open override func updateContainerContentInsets(_ insets: NSEdgeInsets, transition: ContainedViewLayoutTransition) {
        super.updateContainerContentInsets(insets, transition: transition)
        guard isLoaded() else {
            return
        }
        genericView.contentBottomInset = insets.bottom
        searchSection?.updateContainerContentInsets(insets, transition: transition)
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        
        if context.layout == .single && animated {
            context.globalPeerHandler.set(.single(nil))
        }
        
        context.window.set(handler: { [weak self] event in
            if let strongSelf = self, let window = strongSelf.window {
                let navigation = strongSelf.context.bindings.rootNavigation()
                if FeatureNavigationHooks.shared.emptyChatControllerType().map({ navigation.controller.isKind(of: $0) }) == true, strongSelf.searchSection == nil, !event.modifierFlags.contains(.command), !event.modifierFlags.contains(.shift), !event.modifierFlags.contains(.control) {
                    switch strongSelf.mode {
                    case .plain:
                        let isAlphanumeric = event.charactersIgnoringModifiers?.unicodeScalars.first.map {
                              CharacterSet.alphanumerics.contains($0)
                          } ?? false
                        if isAlphanumeric, !hasModals(window), !contextMenuOnScreen() {
                            strongSelf.genericView.searchView.change(state: .Focus, true)
                            return .invokeNext
                        }
                    default:
                        break
                    }
                }
            }
            return .rejected
        }, with: self, for: .All, priority: .supreme)
        
        context.window.set(handler: { [weak self] _ in
            if let strongSelf = self {
                return strongSelf.escapeKeyAction()
            }
            return .invokeNext
        }, with: self, for: .Escape, priority:.low)
        
        context.window.set(handler: { [weak self] _ in
            if let strongSelf = self {
                return strongSelf.returnKeyAction()
            }
            return .invokeNext
        }, with: self, for: .Return, priority:.low)
        
        context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            if let item = self?.effectiveTableView.selectedItem(), item.index > 0 {
                self?.effectiveTableView.selectPrev()
            }
            return .invoked
        }, with: self, for: .UpArrow, priority: .medium, modifierFlags: [.option])
        
        context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.effectiveTableView.selectNext()
            return .invoked
        }, with: self, for: .DownArrow, priority:.medium, modifierFlags: [.option])
        
        context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.effectiveTableView.selectNext(turnDirection: false)
            return .invoked
        }, with: self, for: .Tab, priority: .modal, modifierFlags: [.control])
        
        context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.effectiveTableView.selectPrev(turnDirection: false)
            return .invoked
        }, with: self, for: .Tab, priority: .modal, modifierFlags: [.control, .shift])
        
    }
    
    open override var fullSlideAnimation: Bool {
        return !self.mode.isForumLike || self.mode.isFullForum
    }
    
    open override func setToNextController(_ controller: ViewController, style: ViewControllerStyle) {
        switch style {
        case .push:
            swipeState = nil
            self.completeUndefiedStates(animated: style != .none)
            if controller.stake.isCustom {
                appearMode.set(.short)
            } else {
                appearMode.set(.normal)
            }
            
            if let controller = controller as? PeersListController<Context> {
                if case let .forum(peerId, _, _) = controller.mode {
                    self.updateHighlight(peerId)
                } else {
                    self.updateHighlight(context.globalLocationId?.peerId)
                }
            } else {
                self.updateHighlight(context.globalLocationId?.peerId)
            }
        default:
            break
        }
    }
    
    
    open override func setToPreviousController(_ controller: ViewController, style: ViewControllerStyle) {
        switch style {
        case .pop:
            self.swipeState = nil
            self.appearMode.set(.normal)
            self.updateHighlight(context.globalLocationId?.peerId)
            genericView.backgroundView.change(opacity: 0, animated: true)
        default:
            break
        }
    }
    
    private func updateHighlight(_ peerId: PeerId?) -> Void {
        switch self.mode {
        case .forum, .savedMessagesChats:
            break
        default:
            self.updateState { current in
                var current = current
                current.selectedForum = peerId
                if peerId == nil {
                    current.forumPeer = nil
                }
                return current
            }
            let context = self.context
            let forumPeer: Signal<PeerListState.ForumData?, NoError>
            if let peerId = peerId {
                forumPeer = context.account.postbox.peerView(id: peerId) |> mapToSignal { view in
                    if let peer = peerViewMainPeer(view) as? TelegramChannel, TelegramUtilsHooks.shared.peerIsForum(peer) {
                        return .single(.init(peer: peer, peerView: view, online: 0))
                    } else {
                        return .single(nil)
                    }
                }
            } else {
                forumPeer = .single(nil)
            }
            self.forumPeerData.set(forumPeer)
        }
    }
    
    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        context.window.removeAllHandlers(for: self)
        switch mode {
        case .forum:
            context.globalForumId.set(nil)
        case .savedMessagesChats:
            context.globalForumId.set(nil)
        default:
            break
        }
        self.searchSection?.view._change(opacity: 0, animated: true, completion: { [weak self] completed in
            if completed {
                self?.searchSection?.view.isHidden = true
            }
        })
    }
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        switch mode {
        case let .forum(peerId, _, _):
            context.globalForumId.set(peerId)
        case .savedMessagesChats:
            context.globalForumId.set(context.peerId)
        default:
            break
        }
        self.searchSection?.view.isHidden = false
        self.searchSection?.view._change(opacity: 1, animated: true)
    }
    
    open override var stake: StakeSettings {
        switch mode {
        case let .forum(_, isFull, parentIsArchive):
            if !isFull {
                return .init(keepLeft: 70, keepTop: { [weak self] in
                    guard let state = self?.state else {
                        return 0
                    }
                    var height: CGFloat = 90
                    if !state.filterData.isEmpty, state.splitState != .minimisize {
                        if !state.filterData.sidebar {
                            if !parentIsArchive {
                                height += 36
                            }
                        }
                    }
                    return height
                }, straightMove: true, keepIn: false)
            }
        case .plain:
            return .init(keepLeft: 0, keepTop: { 0}, straightMove: false, keepIn: false)
        default:
            break
        }
        return super.stake
    }
    
    public private(set) var swipeState: SwipeState?
    
    open func getSwipeProgress() -> CGFloat? {
        if let swipeState = swipeState {
            switch swipeState {
            case .swiping, .success, .start:
                return swipeState.delta / (frame.width - 70)
            default:
                return nil
            }
        }
        return nil
    }
    
    open override func updateSwipingState(_ state: SwipeState, controller: ViewController, isPrevious: Bool) -> Void {
        
        if isPrevious, controller.stake.keepLeft > 0 {
            self.genericView.updateSwipingState(state, controller: controller)
            self.swipeState = state
            
            genericView.tableView.enumerateExistingItemViews(with: { _, view in
                if let view = view as? ChatListRowView {
                    let animated: Bool
                    switch swipeState {
                    case .swiping, .success, .start:
                        animated = false
                    default:
                        animated = true
                    }
                    view.updateHideProgress(animated: animated)
                }
            })

            if let progress = getSwipeProgress() {
                genericView.backgroundView.layer?.opacity = Float(1 - progress)
            }
        }
    }
    
    private var storyInterfaceState: StoryListChatListRowItem.InterfaceState {
        if self.state?.hasStories == false {
            return .empty
        }
        return self.storyReveal.interfaceState
    }

    private let storyReveal = StoryRevealModel()
    private lazy var storyRevealDriver: StoryRevealDriver = {
        let driver = StoryRevealDriver(table: self.genericView.tableView, model: self.storyReveal)
        driver.didChange = { [weak self] previous, tracking in
            self?.storyRevealDidChange(from: previous, tracking: tracking)
        }
        return driver
    }()

    private var storyRevealAllowed: Bool {
        return self.state?.hasStories == true && self.canStoryOverscroll && self.searchSection == nil
    }

    private func storyRevealDidChange(from previous: CGFloat, tracking: Bool) {
        if tracking, self.storyReveal.fraction >= 1, previous < 1 {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .drawCompleted)
        }
        #if DEBUG
        let started = CACurrentMediaTime()
        #endif
        self.relayoutStoryReveal()
        #if DEBUG
        if StoryRevealLabRegistry.isRecording {
            StoryRevealLabRegistry.layoutMs.append((CACurrentMediaTime() - started) * 1000)
        }
        #endif
    }

    private func relayoutStoryReveal() {
        guard let item = self.genericView.tableView.item(stableId: UIChatListEntryId.space) as? ChatListSpaceItem else {
            return
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        self.genericView.tableView.noteHeightOfRow(item.index, false)
        self.genericView.updateLayout(frame.size, transition: .immediate)
        CATransaction.commit()
    }

    private func setStoriesRevealed(_ revealed: Bool, animated: Bool) {
        self.storyRevealDriver.setRevealed(revealed, animated: animated)
    }
    
    open var canStoryOverscroll: Bool {
        if self.state?.splitState == .minimisize {
            return false
        }
        if state?.forumPeer != nil {
            return false
        }
        if state?.appear == .short {
            return false
        }
        return true
    }
    
    open func getStoryInterfaceState() -> StoryListChatListRowItem.InterfaceState {
        return self.takeArguments()?.getStoryInterfaceState() ?? .empty
    }
    
    open func getDeltaProgress() -> CGFloat? {
        genericView.getDeltaProgress()
    }

    private func processScroll() {
        guard self.storyRevealAllowed else {
            return
        }
        self.storyRevealDriver.tableDidScroll()
    }

    open func processScroll(_ event: NSEvent) -> Bool {
        #if DEBUG
        let started = CACurrentMediaTime()
        defer {
            if StoryRevealLabRegistry.isRecording {
                StoryRevealLabRegistry.eventMs.append((CACurrentMediaTime() - started) * 1000)
            }
        }
        #endif
        let allowed = self.storyRevealAllowed
        self.storyRevealDriver.setEnabled(allowed)
        guard allowed else {
            return false
        }
        let input = StoryRevealModel.input(event, time: StoryRevealDriver.eventTime(event, now: CACurrentMediaTime()))
        let consumed = self.storyRevealDriver.handle(input)
        #if DEBUG
        StoryRevealLabRegistry.record(input, consumed: consumed)
        #endif
        return consumed
    }
    
    open func toggleStoriesState() {
        
        if case let .forum(peerId, _, _) = self.mode {
            ChatListUIHooks.shared.pushPeerInfo(context.bindings.rootNavigation(), context, peerId)
            return
        }
        
        if searchSection != nil {
            return
        }
        
        guard self.genericView.tableView.item(stableId: UIChatListEntryId.space) is ChatListSpaceItem, storyInterfaceState != .empty else {
            return
        }
        let target = self.storyReveal.spring?.target ?? (self.storyReveal.glide != nil ? 0 : nil)
        let opening = target.map { $0 < 1 } ?? (self.storyReveal.fraction < 1)
        self.genericView.tableView.scroll(to: .up(false), ignoreLayerAnimation: true)
        self.setStoriesRevealed(opening, animated: true)
    }
    
    @discardableResult open func revealStoriesState() -> Bool {
        guard self.genericView.tableView.item(stableId: UIChatListEntryId.space) is ChatListSpaceItem, storyInterfaceState != .empty else {
            return false
        }
        if self.storyInterfaceState != .revealed {
            self.genericView.searchView.cancel(true)
            self.genericView.tableView.scroll(to: .up(false), ignoreLayerAnimation: true)
            self.setStoriesRevealed(true, animated: true)
            return true
        }
        return false
    }
    
    open func completeUndefiedStates(animated: Bool) {
        guard self.genericView.tableView.item(stableId: UIChatListEntryId.space) is ChatListSpaceItem, storyInterfaceState != .empty else {
            return
        }
        if self.storyReveal.fraction > 0 || self.storyReveal.isAnimating {
            if self.genericView.tableView.documentOffset.y <= StoryRevealModel.topTolerance {
                self.genericView.tableView.scroll(to: .up(false), ignoreLayerAnimation: true)
            }
            self.setStoriesRevealed(false, animated: animated)
        }
    }

    open override var backdorColor: NSColor {
        return .clear
    }
        
}

#if DEBUG
struct StoryRevealLabSnapshot {
    var progress: CGFloat
    var interface: String
    var animating: Bool
    var tracking: Bool
    var tableOffset: CGFloat
    var tableOffsetVisual: CGFloat
    var navigationHeight: CGFloat
    var spaceRowHeight: CGFloat
    var searchBottomVisual: CGFloat
    var firstRowTopVisual: CGFloat?
    var stripOffsetVisual: CGFloat?
    var stripRect: CGRect?
    var driver: String = ""
    var tableOffsetX: CGFloat = 0
}

protocol StoryRevealLabProbing: AnyObject {
    var storyLabWindow: Window? { get }
    var storyLabHasStories: Bool { get }
    func storyLabSnapshot() -> StoryRevealLabSnapshot
    func storyLabListPoint() -> NSPoint
    func storyLabStripPoint() -> NSPoint?
    func storyLabReset(revealed: Bool)
    func storyLabScrollList(to offset: CGFloat)
}

final class StoryRevealLabRegistry {
    static weak var target: StoryRevealLabProbing?
    static var routing: [String: Int] = [:]
    static var layoutMs: [Double] = []
    static var eventMs: [Double] = []
    static var isRecording: Bool = false

    static func record(_ input: StoryRevealInput, consumed: Bool) {
        let kind = input.momentum != .none ? "momentum.\(input.momentum)" : "\(input.phase)"
        self.routing["\(kind).\(consumed ? "consumed" : "passThrough")", default: 0] += 1
    }
}

extension PeerListContainerView {
    var storyLabStoriesView: StoryListChatListRowView? {
        return self.storiesView
    }
}

extension PeersListController: StoryRevealLabProbing {
    var storyLabWindow: Window? {
        return self.window
    }

    var storyLabHasStories: Bool {
        return self.state?.hasStories == true && self.storyInterfaceState != .empty
    }

    func storyLabSnapshot() -> StoryRevealLabSnapshot {
        let table = self.genericView.tableView
        let interface = self.storyInterfaceState
        let clipVisual = table.clipView.layer?.presentation()?.bounds.origin.y ?? table.documentOffset.y
        let space = table.item(stableId: UIChatListEntryId.space)
        let spaceHeight = space?.view?.frame.height ?? 0
        let search = self.genericView.searchView
        let searchLayer = search.layer?.presentation() ?? search.layer
        let searchBottom = (searchLayer?.frame.maxY ?? search.frame.maxY)
        var firstRowTop: CGFloat?
        table.enumerateVisibleItems(with: { item in
            if item is ChatListRowItem, let view = item.view {
                let y = view.layer?.presentation()?.frame.minY ?? view.frame.minY
                firstRowTop = y - clipVisual
                return false
            }
            return true
        })
        let strip = self.genericView.storyLabStoriesView
        let stripRect = strip.map { $0.convert($0.bounds, to: nil) }
        let state: String
        switch interface {
        case .revealed:
            state = "revealed"
        case .concealed:
            state = "concealed"
        case .empty:
            state = "empty"
        case .progress:
            state = "progress"
        }
        var snapshot = StoryRevealLabSnapshot(progress: interface.progress, interface: state, animating: self.storyReveal.isAnimating, tracking: self.storyReveal.isTracking, tableOffset: table.documentOffset.y, tableOffsetVisual: clipVisual, navigationHeight: self.genericView.navigationHeight, spaceRowHeight: spaceHeight, searchBottomVisual: searchBottom, firstRowTopVisual: firstRowTop, stripOffsetVisual: strip?.debugHorizontalOffset, stripRect: stripRect)
        snapshot.tableOffsetX = table.clipView.bounds.origin.x
        snapshot.driver = "ticking=\(self.storyRevealDriver.isTicking) ticks=\(self.storyRevealDriver.ticks) spring=\(String(describing: self.storyReveal.spring)) glide=\(self.storyReveal.glide != nil)"
        return snapshot
    }

    func storyLabListPoint() -> NSPoint {
        let table = self.genericView.tableView
        let rect = table.convert(table.bounds, to: nil)
        return NSMakePoint(rect.midX, rect.minY + rect.height * 0.3)
    }

    func storyLabStripPoint() -> NSPoint? {
        guard let strip = self.genericView.storyLabStoriesView, strip.window != nil, strip.frame.height > 0 else {
            return nil
        }
        let rect = strip.convert(strip.bounds, to: nil)
        return NSMakePoint(rect.midX, rect.midY)
    }

    func storyLabReset(revealed: Bool) {
        self.genericView.tableView.scroll(to: .up(false), ignoreLayerAnimation: true)
        self.genericView.storyLabStoriesView?.debugResetHorizontalOffset()
        self.setStoriesRevealed(revealed, animated: false)
        self.relayoutStoryReveal()
    }

    func storyLabScrollList(to offset: CGFloat) {
        self.genericView.tableView.clipView.scroll(to: NSMakePoint(0, offset), animated: false)
    }
}
#endif

