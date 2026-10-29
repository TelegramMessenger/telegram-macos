import Cocoa
import TGUIKit
import TelegramCore
import CalendarUtils
import Postbox
import SwiftSignalKit
import InAppSettings
import ObjcUtils
import ThemeSettings
import DustLayer
import TelegramMedia
import FoundationUtils
import AlertsUI
import BoostUI
import CaptureExclusion
import ChatHistoryModel
import ChatModeTypes
import FilePanels
import InputDataUI
import InputTextView
import InstantPageUI
import LocalAnimations
import Localization
import MediaRecorderUI
import MessageTextUtils
import MessageUtils
import PremiumUI
import ShortPeerRow
import StarsUI
import SystemPermissions
import TelegramCallsCore
import TelegramContext
import TelegramLinks
import TelegramMediaUtils
import TelegramTheme
import TelegramUtils
import Strings
import InputView


private func calculateAdjustedPoint(for point: CGPoint,
                            floatingPhotosView: NSView,
                            tableView: TableView) -> CGPoint? {
    guard let tableViewDocumentView = tableView.documentView else {
        return nil
    }
    
    let floatingPhotosFrameInSuperview = floatingPhotosView.frame
    let tableViewDocumentFrameInSuperview = tableViewDocumentView.frame

    let contentOffset = tableView.contentView.bounds.origin
    let offsetX = floatingPhotosFrameInSuperview.origin.x - tableViewDocumentFrameInSuperview.origin.x + contentOffset.x
    let offsetY = floatingPhotosFrameInSuperview.origin.y - tableViewDocumentFrameInSuperview.origin.y + contentOffset.y
    let adjustedPoint = CGPoint(x: point.x + offsetX, y: point.y + offsetY)
    
    return adjustedPoint
}

private func chatHistoryKeepsReadState(peer: Peer?, chatLocation: ChatLocation) -> Bool {
    if case .thread = chatLocation {
        return true
    }
    guard let channel = peer as? TelegramChannel else {
        return true
    }
    return channel.flags.contains(.isMonoforum) || channel.participationStatus == .member
}

private func canBypassChatRestrictions(_ cachedData: CachedChannelData) -> Bool {
    guard let required = cachedData.boostsToUnrestrict, required > 0, let applied = cachedData.appliedBoosts else {
        return false
    }
    return applied >= required
}

private var nextClientId: Int32 = 1








extension ChatHistoryLocation {
    public var isAtUpperBound: Bool {
        switch self {
        case .Navigation(index: .upperBound, anchorIndex: .upperBound, count: _, side: _):
            return true
        case .Scroll(index: .upperBound, anchorIndex: .upperBound, sourceIndex: _, scrollPosition: _, count: _, animated: _):
            return true
        default:
            return false
        }
    }

}



public final class ChatWrappedEntry : Comparable, Identifiable {
    public let appearance: AppearanceWrapperEntry<ChatHistoryEntry>
    public let tag: HistoryViewInputTag?
    public init(appearance: AppearanceWrapperEntry<ChatHistoryEntry>, tag: HistoryViewInputTag?) {
        self.appearance = appearance
        self.tag = tag
    }
    public var stableId: ChatHistoryEntryId {
        return appearance.entry.stableId
    }
    
    public var entry: ChatHistoryEntry {
        return appearance.entry
    }
}

public func ==(lhs:ChatWrappedEntry, rhs: ChatWrappedEntry) -> Bool {
    return lhs.appearance == rhs.appearance && lhs.tag == rhs.tag
}
public func <(lhs:ChatWrappedEntry, rhs: ChatWrappedEntry) -> Bool {
    return lhs.appearance.entry < rhs.appearance.entry
}


final class ChatHistoryView {
    let originalView: MessageHistoryView?
    let filteredEntries: [ChatWrappedEntry]
    let theme: TelegramPresentationTheme
    init(originalView:MessageHistoryView?, filteredEntries: [ChatWrappedEntry], theme: TelegramPresentationTheme) {
        self.originalView = originalView
        self.filteredEntries = filteredEntries
        self.theme = theme
    }
    
    deinit {
        
    }
}

enum ChatControllerViewState {
    case visible
    case progress
    //case IsNotAccessible
}

final class ChatHistoryState : Equatable {
    let isDownOfHistory:Bool
    fileprivate let replyStack:[MessageId]
    init (isDownOfHistory:Bool = true, replyStack:[MessageId] = []) {
        self.isDownOfHistory = isDownOfHistory
        self.replyStack = replyStack
    }
    
    func withUpdatedStateOfHistory(_ isDownOfHistory:Bool) -> ChatHistoryState {
        return ChatHistoryState(isDownOfHistory: isDownOfHistory, replyStack: self.replyStack)
    }
    
    func withAddingReply(_ messageId:MessageId) -> ChatHistoryState {
        var stack = replyStack
        stack.append(messageId)
        return ChatHistoryState(isDownOfHistory: isDownOfHistory, replyStack: stack)
    }
    
    func withClearReplies() -> ChatHistoryState {
        return ChatHistoryState(isDownOfHistory: isDownOfHistory, replyStack: [])
    }
    
    func reply() -> MessageId? {
        return replyStack.last
    }
    
    func withRemovingReplies(max: MessageId) -> ChatHistoryState {
        var copy = replyStack
        for i in stride(from: replyStack.count - 1, to: -1, by: -1) {
            if replyStack[i] <= max {
                copy.remove(at: i)
            }
        }
        return ChatHistoryState(isDownOfHistory: isDownOfHistory, replyStack: copy)
    }
}

func ==(lhs:ChatHistoryState, rhs:ChatHistoryState) -> Bool {
    return lhs.isDownOfHistory == rhs.isDownOfHistory && lhs.replyStack == rhs.replyStack
}

private final class ChatPresentationCacheEntry {
    private let base: TelegramPresentationTheme
    private weak var global: TelegramPresentationTheme?
    private let result: TelegramPresentationTheme
    private let emoticonThemes: [(ChatTheme, TelegramPresentationTheme)]
    private let wallpaper: ThemeWallpaper?
    private let liteMode: LiteMode
    private let scaleFactor: CGFloat

    init(base: TelegramPresentationTheme, global: TelegramPresentationTheme, emoticonThemes: [(ChatTheme, TelegramPresentationTheme)], wallpaper: ThemeWallpaper?, liteMode: LiteMode, scaleFactor: CGFloat, result: TelegramPresentationTheme) {
        self.base = base
        self.global = global
        self.result = result
        self.emoticonThemes = emoticonThemes
        self.wallpaper = wallpaper
        self.liteMode = liteMode
        self.scaleFactor = scaleFactor
    }

    func result(base: TelegramPresentationTheme, global: TelegramPresentationTheme, emoticonThemes: [(ChatTheme, TelegramPresentationTheme)]?, wallpaper: ThemeWallpaper?, liteMode: LiteMode, scaleFactor: CGFloat) -> TelegramPresentationTheme? {
        guard self.base === base, self.global === global, self.liteMode == liteMode, self.scaleFactor == scaleFactor, self.result.backgroundSize == base.backgroundSize, self.wallpaper == wallpaper else {
            return nil
        }
        if let emoticonThemes {
            if emoticonThemes.count != self.emoticonThemes.count {
                return nil
            }
            for (l, r) in zip(emoticonThemes, self.emoticonThemes) where l.1 !== r.1 || l.0 != r.0 {
                return nil
            }
        }
        return self.result
    }
}

private func chatPresentation(_ base: TelegramPresentationTheme, withEmoticonThemes emoticonThemes: [(ChatTheme, TelegramPresentationTheme)], cache: inout ChatPresentationCacheEntry?) -> TelegramPresentationTheme {
    let global = theme
    let liteMode = TelegramPresentationTheme.currentLiteMode()
    let scaleFactor = System.backingScale
    if let cached = cache?.result(base: base, global: global, emoticonThemes: emoticonThemes, wallpaper: nil, liteMode: liteMode, scaleFactor: scaleFactor) {
        return cached
    }
    let result = base.withUpdatedEmoticonThemes(emoticonThemes)
    cache = ChatPresentationCacheEntry(base: base, global: global, emoticonThemes: emoticonThemes, wallpaper: nil, liteMode: liteMode, scaleFactor: scaleFactor, result: result)
    return result
}

private func chatPresentation(_ base: TelegramPresentationTheme, withWallpaper wallpaper: ThemeWallpaper, cache: inout ChatPresentationCacheEntry?) -> TelegramPresentationTheme {
    let global = theme
    let liteMode = TelegramPresentationTheme.currentLiteMode()
    let scaleFactor = System.backingScale
    if let cached = cache?.result(base: base, global: global, emoticonThemes: nil, wallpaper: wallpaper, liteMode: liteMode, scaleFactor: scaleFactor) {
        return cached
    }
    let result = base.withUpdatedWallpaper(wallpaper)
    cache = ChatPresentationCacheEntry(base: base, global: global, emoticonThemes: [], wallpaper: wallpaper, liteMode: liteMode, scaleFactor: scaleFactor, result: result)
    return result
}


public class ChatControllerView : View, ChatInputDelegate {

    
    public let tableView:TableView
    
    
    private var textInputSuggestionsView: InputSwapSuggestionsPanel?
    
    
    private var starUndoView: ChatStarReactionUndoView?
    
    private var videoProccesing: ChatVideoProcessingTooltip?

    
    var scroll: ScrollPosition {
        return self.tableView.scrollPosition().current
    }
    
    private weak var navigationView: NSView?
    
    public let inputView:ChatInputView
    let showsInput: Bool

    static func showsInput(in mode: ChatMode) -> Bool {
        return mode != .preview
    }

    func bottomInset(forInputHeight inputHeight: CGFloat) -> CGFloat {
        return ChatHistoryBottomRowItem.bottomInset(showsInput: showsInput, inputOverlayHeight: max(0, inputHeight - ChatInputView.inputBottomInset) + transcriptionInset)
    }

    var floatingPhotosBottomGap: CGFloat {
        var gap = ChatHistoryBottomRowItem.bottomInset(showsInput: showsInput, inputOverlayHeight: 0)
        if showsInput, inputView.attachView.isAIVisible {
            gap += ChatInputAttachButton.expandedHeight - ChatInputAttachButton.collapsedHeight
        }
        return gap
    }
    let inputContextHelper:InputContextHelper
    let bubblesView: ChatHeaderBubblesView
    private(set) var state:ChatControllerViewState = .visible
    private var searchInteractions:ChatSearchInteractions!
    private let scroller:ChatNavigationScroller
    private(set) var mentions:ChatNavigationScroller?
    private(set) var reactions:ChatNavigationScroller?
    private(set) var pollVotes:ChatNavigationScroller?
    private var progressView:ProgressIndicator?
    private let header:ChatHeaderController
    private var historyState:ChatHistoryState?
    private var scrollerTargetIsHidden: Bool?
    private let chatInteraction: ChatInteraction
    
    
    private var monoforum_VerticalView: MonoforumVerticalView?
    private var monoforumHorizontalData: ChatHeaderState.MonoforumData?

    fileprivate var updateFloatingPhotos:((ScrollPosition, Bool)->Void)? = nil
    fileprivate var inputHeightChanged: ((CGFloat) -> Void)? = nil
    private var transcriptionView: ChatVoiceTranscriptionView?
    private static let transcriptionGap: CGFloat = 10

    var transcriptionInset: CGFloat {
        guard let transcriptionView else {
            return 0
        }
        return transcriptionView.contentHeight + ChatControllerView.transcriptionGap
    }
    
    
    var chatTheme: TelegramPresentationTheme? {
        didSet {
            if chatTheme != oldValue {
                updateLocalizationAndTheme(theme: chatTheme ?? theme)
            }
        }
    }
    
    private var themeSelectorView: NSView?
    
    let floatingPhotosView: FlippableView = FlippableView()
    
    private let gradientMaskView = BackgroundGradientView(frame: NSZeroRect)
    private let inputShadowView = EdgeEffectView()
    private let bubbleShadowView = EdgeEffectView()

    struct EdgeBlur: OptionSet {
        let rawValue: Int
        static let top = EdgeBlur(rawValue: 1 << 0)
        static let bottom = EdgeBlur(rawValue: 1 << 1)
    }

    static let edgeBlur: EdgeBlur = []

    private var toasterView: ChatToasterView?

    var headerState: ChatHeaderState {
        return header.state
    }
    
    
    deinit {
        var bp:Int = 0
        bp += 1
    }
    
    private var backgroundMode: TableBackgroundMode?
    private(set) var backgroundView: BackgroundView?
    private var cachedEdgeColor: NSColor?
    private var cachedEdgeColorMode: TableBackgroundMode?

    private func edgeEffectColor() -> NSColor {
        let mode = self.backgroundMode ?? self.chatTheme?.controllerBackgroundMode ?? theme.controllerBackgroundMode
        if let cached = cachedEdgeColor, let cachedMode = cachedEdgeColorMode, cachedMode == mode {
            return cached
        }
        let color = ChatControllerView.computeEdgeColor(for: mode, theme: self.chatTheme ?? theme)
        cachedEdgeColor = color
        cachedEdgeColorMode = mode
        return color
    }

    private static func computeEdgeColor(for mode: TableBackgroundMode, theme: TelegramPresentationTheme) -> NSColor {
        
       
        
        switch mode {
        case .plain:
            return theme.colors.chatBackground
        case let .color(color):
            return color
        case let .gradient(colors, _):
            if colors.isEmpty {
                return theme.colors.chatBackground
            }
            return averageColor(colors)
        case let .background(image, _, colors, _, _):
            if let colors, !colors.isEmpty {
                if theme.colors.isDark {
                    return NSColor(0x000000)
                }
                return averageColor(colors.map { $0.withAlphaComponent(1.0) })
            }
            if let sampled = sampleAverageColor(from: image) {
                return sampled
            }
            return theme.colors.chatBackground
        case let .tiled(image):
            if let sampled = sampleAverageColor(from: image) {
                return sampled
            }
            return theme.colors.chatBackground
        }
    }

    private static func averageColor(_ colors: [NSColor]) -> NSColor {
        guard !colors.isEmpty else { return .clear }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        for c in colors {
            var cr: CGFloat = 0, cg: CGFloat = 0, cb: CGFloat = 0, ca: CGFloat = 0
            (c.usingColorSpace(.deviceRGB) ?? c).getRed(&cr, green: &cg, blue: &cb, alpha: &ca)
            r += cr; g += cg; b += cb; a += ca
        }
        let n = CGFloat(colors.count)
        return NSColor(deviceRed: r / n, green: g / n, blue: b / n, alpha: a / n)
    }

    private static func sampleAverageColor(from image: NSImage) -> NSColor? {
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace, bitmapInfo: bitmapInfo) else {
            return nil
        }
        context.interpolationQuality = .medium
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let r = CGFloat(pixel[0]) / 255.0
        let g = CGFloat(pixel[1]) / 255.0
        let b = CGFloat(pixel[2]) / 255.0
        let a = CGFloat(pixel[3]) / 255.0
        return NSColor(deviceRed: r, green: g, blue: b, alpha: max(a, 1.0))
    }

    func updateBackground(_ mode: TableBackgroundMode, navigationView: NSView?, isStandalone: Bool) {
        self.navigationView = navigationView
        if self.backgroundMode != mode {
            self.cachedEdgeColor = nil
            self.cachedEdgeColorMode = nil
        }
        self.backgroundMode = mode

        if backgroundView == nil {
            let bgView = BackgroundView(frame: bounds)
            bgView.useSharedAnimationPhase = false
            addSubview(bgView, positioned: .below, relativeTo: self.subviews.first)
            self.backgroundView = bgView
        }
        backgroundView?.backgroundMode = mode
    }
    
    
    
    func findItem(by messageId: MessageId) -> TableRowItem? {
        var found: TableRowItem? = nil
        self.tableView.enumerateVisibleItems(with: { item in
            if let item = item as? ChatRowItem, item.message?.id == messageId {
                found = item
                return false
            } else {
                return true
            }
        })
        return found
    }
    
    public required init(frame frameRect: NSRect, chatInteraction:ChatInteraction) {
        self.chatInteraction = chatInteraction
        header = ChatHeaderController(chatInteraction)


        scroller = ChatNavigationScroller(.scroller)
        inputContextHelper = InputContextHelper(chatInteraction: chatInteraction)
        tableView = TableView(frame:NSMakeRect(0,0,frameRect.width,frameRect.height - 50), isFlipped:false)

        bubblesView = ChatHeaderBubblesView(frame: NSMakeRect(0, 0, frameRect.width, ChatHeaderBubblesView.totalHeight), chatInteraction: chatInteraction)

        inputView = ChatInputView(frame: NSMakeRect(0,tableView.frame.maxY, frameRect.width,50), chatInteraction: chatInteraction)
        showsInput = ChatControllerView.showsInput(in: chatInteraction.mode)
        //inputView.autoresizingMask = [.width]
        super.init(frame: frameRect)
        
        
        tableView.getBackgroundColor = {
            .clear
        }
        tableView.clipView.skipsDisplayOnScroll = true
        tableView.mergesSaveVisibleInOneGroup = true
        
//        self.layer = CAGradientLayer()
//        self.layer?.disableActions()
        
        addSubview(tableView)
        addSubview(floatingPhotosView)
        
        floatingPhotosView.flip = false
        floatingPhotosView.isEventLess = true
        
//        floatingPhotosView.backgroundColor = .random
        
        inputShadowView.isEventLess = true
        bubbleShadowView.isEventLess = true
        addSubview(inputShadowView)
        addSubview(bubbleShadowView)

        addSubview(inputView)
        addSubview(bubblesView)
        inputView.isHidden = !showsInput
        inputShadowView.isHidden = !showsInput
        header.sharedGlassWrapper = bubblesView.sharedGlassWrapper
        inputView.delegate = self
        self.autoresizesSubviews = false
        tableView.autoresizingMask = []
        scroller.set(handler:{ [weak chatInteraction] control in
            chatInteraction?.scrollToLatest(false)
        }, for: .Click)
        scroller.forceHide()
        
        tableView.automaticallyAdjustsContentInsets = false
        
        addSubview(scroller, positioned: .below, relativeTo: inputView)
        
        let context = chatInteraction.interactionContext
        

        searchInteractions = ChatSearchInteractions(jump: { [weak chatInteraction] message in
            chatInteraction?.focusMessageId(nil, .init(messageId: message.id, string: nil), .center(id: 0, innerId: nil, animated: false, focus: .init(focus: true), inset: 0))
        }, results: { [weak chatInteraction] query in
            chatInteraction?.modalSearch(query)
        }, calendarAction: { [weak chatInteraction] date in
            chatInteraction?.jumpToDate(date)
        }, cancel: { [weak chatInteraction] in
            chatInteraction?.update({$0.updatedSearchMode(.init(inSearch: false))})
        }, searchRequest: { [weak chatInteraction] query, fromId, state, tags in
            guard let chatInteraction = chatInteraction else {
                return .never()
            }
            let location: SearchMessagesLocation
            switch chatInteraction.chatLocation {
            case let .peer(peerId):
                location = .peer(peerId: peerId, fromId: fromId, tags: chatInteraction.mode.tagMask, reactions: tags.map { $0.tag.reaction }, threadId: chatInteraction.chatLocation.threadId, minDate: nil, maxDate: nil)
            case let .thread(data):
                location = .peer(peerId: data.peerId, fromId: fromId, tags: nil, reactions: tags.map { $0.tag.reaction }, threadId: data.threadId, minDate: nil, maxDate: nil)
            }
            return context.engine.messages.searchMessages(location: location, query: query, state: state) |> map {($0.0.messages.filter({ !($0.extendedMedia is TelegramMediaAction) }), $0.1, $0.0.totalCount)}
        })
        
        
        tableView.backgroundColor = .clear
        tableView.layer?.backgroundColor = .clear

        self.layer?.masksToBounds = false

        tableView.documentSubviewKeptAboveRows = { $0 is ChatAvatarView || $0 is ChatFloatingAvatarScene }
        
        tableView.set(stickClass: ChatDateStickItem.self, handler: { stick in

        })

        tableView.setSecondary(stickClass: ChatTopicSeparatorItem.self, handler: { stick in

        })

        tableView.addScroll(listener: TableScrollListener(dispatchWhenVisibleRangeUpdated: false, { [weak self] _ in
            guard let self = self else { return }
            if let state = self.historyState {
                self.updateScroller(state, onlyIfVisibilityChanged: true)
            }
            let gradientRect = self.chatInteraction.getGradientOffsetRect()
            let size = NSMakeSize(gradientRect.width, gradientRect.height + 60)
            self.tableView.enumerateVisibleViews(with: { view in
                if let view = view as? ChatRowView {
                    view.updateBackground(animated: false, gradientRect: gradientRect, size: size)
                }
            })
        }))

    }
        
    private var anchoredAvatarScene: ChatFloatingAvatarScene?
    private var documentAvatarScene: ChatFloatingAvatarScene?

    private func avatarScene(anchored: Bool, documentView: NSView) -> ChatFloatingAvatarScene {
        let container: NSView = anchored ? floatingPhotosView : documentView
        let existing = anchored ? anchoredAvatarScene : documentAvatarScene
        if let existing, existing.superview === container, existing.isFlipped == container.isFlipped {
            if existing.frame != container.bounds {
                existing.frame = container.bounds
            }
            return existing
        }
        existing?.removeFromSuperview()
        let scene = ChatFloatingAvatarScene(frame: container.bounds, flipped: container.isFlipped)
        scene.autoresizingMask = [.width, .height]
        container.addSubview(scene)
        if anchored {
            anchoredAvatarScene = scene
        } else {
            documentAvatarScene = scene
        }
        return scene
    }

    private func moveFloatingAvatar(_ node: ChatLayerNode, to origin: NSPoint, animated: Bool) {
        if origin == node.frame.origin {
            return
        }
        let layer = node.layer
        if animated {
            var present = node.frame.origin
            if let presentation = layer.presentation(), layer.animation(forKey: "position") != nil {
                present = presentation.frame.origin
            }
            layer.animatePosition(from: present, to: origin, duration: 0.2, timingFunction: .easeOut)
        } else {
            layer.removeAnimation(forKey: "position")
        }
        node.frame = NSRect(origin: origin, size: node.frame.size)
    }

    #if DEBUG
    var debugFloatingAvatarCounts: (nodes: Int, views: Int, hitOK: Int, hitTotal: Int, viewHitOK: Int, viewHitTotal: Int, misses: String) {
        let documentView = self.tableView.documentView
        let avatarViews = (floatingPhotosView.subviews + (documentView?.subviews ?? [])).filter { $0 is ChatAvatarView }
        let views = avatarViews.count
        var viewOK = 0, viewTotal = 0
        if let window = self.window {
            for view in avatarViews where view.layer?.animation(forKey: "opacity") == nil {
                viewTotal += 1
                let center = view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.midY), to: nil)
                if let hit = window.contentView?.hitTest(center), hit === view || hit.isDescendant(of: view) {
                    viewOK += 1
                }
            }
        }
        var misses: [String] = []
        if let window = self.window {
            for scene in [anchoredAvatarScene, documentAvatarScene].compactMap({ $0 }) {
                for node in scene.avatars where node.control.layer.animation(forKey: "opacity") == nil {
                    let frame = node.control.frame
                    let center = scene.convert(NSPoint(x: frame.midX, y: frame.midY), to: nil)
                    if window.contentView?.hitTest(center) !== scene {
                        let hit = window.contentView?.hitTest(center)
                        misses.append("\(scene === anchoredAvatarScene ? "a" : "d")@\(Int(center.y)):\(hit.map { String(describing: type(of: $0)) } ?? "nil")")
                    }
                }
            }
        }
        var nodes = 0, ok = 0, total = 0
        for scene in [anchoredAvatarScene, documentAvatarScene].compactMap({ $0 }) {
            nodes += scene.avatars.count
            let hits = scene.debugAvatarHitChecks()
            ok += hits.ok
            total += hits.total
        }
        return (nodes, views, ok, total, viewOK, viewTotal, misses.joined(separator: ","))
    }
    #endif

    func updateFloating(_ values:[ChatFloatingPhoto], animated: Bool, currentAnimationRows: [TableAnimationInterface.AnimateItem] = []) {
        let animated = animated && !inLiveResize && !tableView.clipView.isAnimateScrolling
        let documentView = self.tableView.documentView!
        var anchoredNodes: [ChatFloatingAvatarNode] = []
        var documentNodes: [ChatFloatingAvatarNode] = []
        var placedIds = Set<ObjectIdentifier>()
        var newNodes: [(ChatFloatingAvatarNode, ChatFloatingPhoto, ChatFloatingAvatarScene)] = []
        for value in values {
            guard value.photoView == nil, let node = value.node else { continue }
            let scene = avatarScene(anchored: value.isAnchor, documentView: documentView)
            let container: NSView = value.isAnchor ? floatingPhotosView : documentView
            #if DEBUG
            let shift = ChatFloatingAvatar.parityMutation
            #else
            let shift: CGFloat = 0
            #endif
            let target = scene.convert(NSRect(origin: value.point, size: node.frame.size), from: container).origin.offsetBy(dx: shift, dy: 0)
            node.layer.removeAnimation(forKey: "opacity")
            let isNew = !scene.contains(node)
            let checker = self.tableView.documentOffset == .zero || target.x != node.frame.minX
            if isNew {
                #if DEBUG
                if node.scene == nil {
                    ChatFloatingDebug.attaches += 1
                } else {
                    ChatFloatingDebug.transitions += 1
                }
                #endif
                (node.scene as? ChatFloatingAvatarScene)?.detach(node)
            }
            moveFloatingAvatar(node.control, to: target, animated: animated && !isNew && checker)
            if !placedIds.insert(ObjectIdentifier(node)).inserted {
                anchoredNodes.removeAll(where: { $0 === node })
                documentNodes.removeAll(where: { $0 === node })
                newNodes.removeAll(where: { $0.0 === node })
            }
            if value.isAnchor {
                anchoredNodes.append(node)
            } else {
                documentNodes.append(node)
            }
            if isNew {
                newNodes.append((node, value, scene))
            }
        }
        anchoredAvatarScene?.place(anchoredNodes)
        documentAvatarScene?.place(documentNodes)
        for (node, value, scene) in newNodes where scene.contains(node) {
            if let moveAsNew = currentAnimationRows.first(where: { $0.index == value.items.first?.index }) {
                let container: NSView = value.isAnchor ? floatingPhotosView : documentView
                let from = scene.convert(NSRect(origin: value.point - (moveAsNew.to - moveAsNew.from), size: node.frame.size), from: container).origin
                node.layer.animateAlpha(from: 0, to: 1, duration: 0.2, timingFunction: .easeOut)
                node.layer.animatePosition(from: from, to: node.frame.origin, duration: 0.2, timingFunction: .easeOut)
            }
        }
        var removedNodes = 0
        for (scene, placed) in [(anchoredAvatarScene, anchoredNodes.count), (documentAvatarScene, documentNodes.count)] {
            guard let scene, scene.avatarCount > placed else { continue }
            for node in scene.avatars where !placedIds.contains(ObjectIdentifier(node)) {
                scene.remove(node, animated: animated)
                removedNodes += 1
            }
        }
        if let scene = documentAvatarScene, scene.avatarCount > 0 {
            let subviews = documentView.subviews
            if let last = subviews.last, last !== scene, !(last is ChatAvatarView), let index = subviews.lastIndex(where: { $0 === scene }), subviews[(index + 1)...].contains(where: { !($0 is ChatAvatarView) }) {
                documentView.addSubview(scene, positioned: .above, relativeTo: nil)
                #if DEBUG
                ChatFloatingDebug.readds += 1
                #endif
            }
        }
        #if DEBUG
        ChatFloatingDebug.removes += removedNodes
        #endif
        let photoViews = values.compactMap { $0.photoView }
        let hasDuplicates = Set(photoViews.map { ObjectIdentifier($0) }).count != photoViews.count
        let animateNew: (NSView, ChatFloatingPhoto) -> Void = { view, value in
            let moveAsNew = currentAnimationRows.first(where: {
                $0.index == value.items.first?.index
            })
            if let moveAsNew = moveAsNew {
                view.layer?.animateAlpha(from: 0, to: 1, duration: 0.2, timingFunction: .easeOut)
                view.layer?.animatePosition(from: value.point - (moveAsNew.to - moveAsNew.from), to: value.point, duration: 0.2, timingFunction: .easeOut)
            }
        }
        var added:[NSView] = []
        var newViews: [(NSView, ChatFloatingPhoto)] = []
        for value in values {
            if let view = value.photoView {
                let superview = value.isAnchor ? floatingPhotosView : documentView

                let checker = self.tableView.documentOffset == .zero || value.point.x != view.frame.minX
                
                view.layer?.removeAnimation(forKey: "opacity")
                view._change(pos: value.point, animated: animated && view.superview == superview && checker, duration: 0.2, timingFunction: .easeOut)
                             
                let isNew = view.superview != superview
                #if DEBUG
                if isNew {
                    if view.superview == nil {
                        ChatFloatingDebug.attaches += 1
                    } else {
                        ChatFloatingDebug.transitions += 1
                    }
                }
                #endif
                if hasDuplicates {
                    superview.addSubview(view)
                    if isNew {
                        animateNew(view, value)
                    }
                } else if isNew {
                    newViews.append((view, value))
                }
                added.append(view)
            }
        }
        if !hasDuplicates {
            self.placeFloatingPhotosOnTop(values.compactMap { $0.isAnchor ? $0.photoView : nil }, in: floatingPhotosView)
            self.placeFloatingPhotosOnTop(values.compactMap { $0.isAnchor ? nil : $0.photoView }, in: documentView)
            for (view, value) in newViews {
                animateNew(view, value)
            }
        }
        let toRemove = (floatingPhotosView.subviews + self.tableView.documentView!.subviews).filter {
            $0 is ChatAvatarView && !added.contains($0)
        }
        for view in toRemove {
            performSubviewRemoval(view, animated: animated, timingFunction: .easeOut, checkCompletion: true)
        }
        #if DEBUG
        ChatFloatingDebug.removes += toRemove.count
        #endif
    }
    
    private func placeFloatingPhotosOnTop(_ views: [NSView], in superview: NSView) {
        guard !views.isEmpty else {
            return
        }
        let subviews = superview.subviews
        if subviews.count >= views.count, zip(subviews.suffix(views.count), views).allSatisfy({ $0 === $1 }) {
            return
        }
        let wanted = Set(views.map { ObjectIdentifier($0) })
        var positions: [ObjectIdentifier: Int] = [:]
        for (index, view) in subviews.enumerated() {
            positions[ObjectIdentifier(view)] = index
        }
        let present = views.enumerated().compactMap { index, view -> (target: Int, position: Int)? in
            return positions[ObjectIdentifier(view)].map { (target: index, position: $0) }
        }
        if let lowest = present.map({ $0.position }).min(), subviews[lowest...].contains(where: { !wanted.contains(ObjectIdentifier($0)) && !($0 is ChatAvatarView) && !($0 is ChatFloatingAvatarScene) }) {
            for view in views {
                superview.addSubview(view)
            }
            #if DEBUG
            ChatFloatingDebug.readds += views.count
            #endif
            return
        }
        let sequence = present.sorted(by: { $0.position < $1.position }).map { $0.target }
        var length = Array(repeating: 1, count: sequence.count)
        var previous = Array(repeating: -1, count: sequence.count)
        for i in sequence.indices {
            for j in 0 ..< i where sequence[j] < sequence[i] && length[j] + 1 > length[i] {
                length[i] = length[j] + 1
                previous[i] = j
            }
        }
        var kept = Set<Int>()
        if var index = length.indices.max(by: { length[$0] < length[$1] }) {
            while index >= 0 {
                kept.insert(sequence[index])
                index = previous[index]
            }
        }
        let firstKept = kept.min().map { views[$0] }
        for index in views.indices where !kept.contains(index) {
            if index > 0 {
                superview.addSubview(views[index], positioned: .above, relativeTo: views[index - 1])
            } else if let firstKept = firstKept {
                superview.addSubview(views[index], positioned: .below, relativeTo: firstKept)
            } else {
                superview.addSubview(views[index])
            }
            #if DEBUG
            ChatFloatingDebug.moves += 1
            #endif
        }
        #if DEBUG
        let ordered = superview.subviews.filter { wanted.contains(ObjectIdentifier($0)) }
        let lowestPlaced = superview.subviews.firstIndex(where: { wanted.contains(ObjectIdentifier($0)) }) ?? 0
        if ordered.count != views.count || !zip(ordered, views).allSatisfy({ $0 === $1 }) || superview.subviews[lowestPlaced...].contains(where: { !wanted.contains(ObjectIdentifier($0)) && !($0 is ChatAvatarView) && !($0 is ChatFloatingAvatarScene) }) {
            ChatFloatingDebug.violations += 1
        }
        #endif
    }
    
    
    func showChatThemeSelector(_ view: NSView, animated: Bool) {
        self.themeSelectorView?.removeFromSuperview()
        self.themeSelectorView = view
        addSubview(view)
        updateFrame(self.frame, transition: animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate)
        self.inputHeightChanged?(view.frame.height)
    }

    func hideChatThemeSelector(animated: Bool) {
        if let view = self.themeSelectorView {
            self.themeSelectorView = nil
            let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate
            self.updateFrame(self.frame, transition: transition)
            self.inputHeightChanged?(inputView.height(for: frame.width))
            if animated {
                transition.updateFrame(view: view, frame: CGRect(origin: CGPoint(x: 0, y: frame.maxY), size: view.frame.size), completion: { [weak view] _ in
                    view?.removeFromSuperview()
                })
            } else {
                view.removeFromSuperview()
            }
        }
    }
    
    func updateScroller(_ historyState: ChatHistoryState, onlyIfVisibilityChanged: Bool = false) {
        let prev = self.historyState
        self.historyState = historyState
        let isHidden = (tableView.documentOffset.y < 80 && historyState.isDownOfHistory) || tableView.isEmpty

        let visibilityChanged = scrollerTargetIsHidden != isHidden
        scrollerTargetIsHidden = isHidden
        if onlyIfVisibilityChanged && !visibilityChanged {
            return
        }

        if !isHidden {
            scroller.isHidden = false
        }
        
        let transition: ContainedViewLayoutTransition
        if prev == nil || (NSEvent.pressedMouseButtons & (1 << 0)) != 0 {
            transition = .immediate
        } else {
            transition = .animated(duration: 0.2, curve: .easeOut)
        }
        
        if visibilityChanged {
            scroller.change(opacity: isHidden ? 0 : 1, animated: transition.isAnimated) { [weak self] completed in
                if completed, let self = self, self.scrollerTargetIsHidden == isHidden {
                    self.scroller.isHidden = isHidden
                }
            }
        }
        

        transition.updateFrame(view: scroller, frame: scrollerRect)
        
        if let mentions = mentions {
            transition.updateFrame(view: mentions, frame: mentionsRect)
        }
        if let reactions = reactions {
            transition.updateFrame(view: reactions, frame: reactionsRect)
        }
        if let pollVotes = pollVotes {
            transition.updateFrame(view: pollVotes, frame: pollVotesRect)
        }
        inputView.updateFloatingColumnAnchor(floatingColumnAnchor, transition: transition)
    }


    public func inputChanged(height: CGFloat, animated: Bool) {
        if superview != nil {
            let transition: ContainedViewLayoutTransition = animated && window != nil ? .animated(duration: 0.2, curve: .easeOut) : .immediate
            self.updateFrame(self.frame, transition: transition)
        }
        self.updateFloatingPhotos?(self.scroll, animated)
        self.inputHeightChanged?(height)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)

        if self.inLiveResize {
            return
        }

        let gradientRect = self.chatInteraction.getGradientOffsetRect()
        let size = NSMakeSize(gradientRect.width, gradientRect.height + 60)
        self.tableView.enumerateVisibleViews(with: { view in
            if let view = view as? ChatRowView {
                view.updateBackground(animated: false, gradientRect: gradientRect, size: size)
            }
        })
    }

    public override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        let gradientRect = self.chatInteraction.getGradientOffsetRect()
        let size = NSMakeSize(gradientRect.width, gradientRect.height + 60)
        self.tableView.enumerateVisibleViews(with: { view in
            if let view = view as? ChatRowView {
                view.updateBackground(animated: false, gradientRect: gradientRect, size: size)
            }
        })
    }

    
    public override func layout() {
        super.layout()
        updateFrame(frame, inset: currentHeaderInset, transition: .immediate)
    }

    var tableRect: NSRect {
        let tableHeight = frame.height - header.state.toleranceHeight
        let tableRect = NSMakeRect(0, header.state.toleranceHeight, frame.width, tableHeight)

        return tableRect
    }

    private var headerHeight: CGFloat {
        return inlineHeaderFrame(for: frame.width) == nil ? header.state.height : 0
    }

    private func inlineHeaderFrame(for width: CGFloat) -> NSRect? {
        guard header.state.canDisplayInline, let frame = bubblesView.inlineHeaderFrame(for: width) else {
            return nil
        }
        if case .search = header.state.main, frame.width < ChatHeaderInlineLayout.minimumSearchAccessoryWidth {
            return nil
        }
        return frame
    }

    private var previousHeaderInsets: (stick: CGFloat, content: CGFloat)?

    private func updateHeaderInsets(width: CGFloat, animated: Bool) {
        let height = inlineHeaderFrame(for: width) == nil ? header.state.height : 0
        let bubbleHeight = ChatHeaderBubblesView.totalHeight
        let stick = bubbleHeight + height - header.state.toleranceHeight + 10
        let content = bubbleHeight + ((chatInteraction.presentation.historyCount ?? 0) > 0 ? height : 0)
        guard previousHeaderInsets?.stick != stick || previousHeaderInsets?.content != content else {
            return
        }
        previousHeaderInsets = (stick, content)
        tableView.updateStickInset(stick, animated: animated)
        tableView.contentInsets = .init(top: content)
    }

    private var currentHeaderInset: CGFloat = 0
    private var navigationOverflow: CGFloat = 0
    private var hasLayout: Bool = false

    func updateNavigationOverflow(_ overflow: CGFloat, transition: ContainedViewLayoutTransition) {
        guard navigationOverflow != overflow else {
            return
        }
        navigationOverflow = overflow
        updateFrame(frame, inset: currentHeaderInset, transition: transition)
    }

    func updateFrame(_ frame: NSRect, transition: ContainedViewLayoutTransition) {
        updateFrame(frame, inset: currentHeaderInset, transition: transition)
    }

    func updateFrame(_ frame: NSRect, inset: CGFloat, transition: ContainedViewLayoutTransition) {
        let transition: ContainedViewLayoutTransition = hasLayout ? transition : .immediate
        hasLayout = true
        currentHeaderInset = inset

        
        let wFrame = window?.frame.size.bounds ?? frame.size.bounds

        let headerInset: NSPoint = NSMakePoint(0, 0)
        

        let bubbleBarHeight: CGFloat = ChatHeaderBubblesView.totalHeight

        let inlineFrame = inlineHeaderFrame(for: frame.width)
        let headerHeight = inlineFrame == nil ? header.state.height : 0
        bubblesView.displaysInlineHeader = inlineFrame != nil
        bubblesView.extendedContentHeight = headerHeight
        updateHeaderInsets(width: frame.width, animated: transition.isAnimated)
        let bubblesFrame = NSMakeRect(headerInset.x, navigationOverflow, frame.width - headerInset.x, bubbleBarHeight)
        transition.updateFrame(view: bubblesView, frame: bubblesFrame)
        bubblesView.updateLayout(size: bubblesFrame.size, transition: transition)

        let edgeBg = edgeEffectColor()
        let bubbleShadowExtra: CGFloat = 24
        let bubbleShadowTopExtend: CGFloat = max(100, inset)
        let bubbleShadowBottom = navigationOverflow + bubbleBarHeight + headerHeight + bubbleShadowExtra
        let shadowX: CGFloat = -self.frame.minX
        let shadowWidth: CGFloat = (superview?.frame.width).map { max($0, self.frame.width) } ?? self.frame.width
        let bubbleShadowRect = NSMakeRect(shadowX, -bubbleShadowTopExtend, shadowWidth, bubbleShadowBottom + bubbleShadowTopExtend)
        let listTopInset = navigationOverflow + bubbleBarHeight + headerHeight
        let bubbleBlur = EdgeEffectView.Blur(rect: NSMakeRect(shadowX, bubbleShadowRect.minY, shadowWidth, listTopInset + 10 - bubbleShadowRect.minY), edgeSize: 80)
        transition.updateFrame(view: bubbleShadowView, frame: bubbleShadowRect)
        bubbleShadowView.update(color: edgeBg, blur: ChatControllerView.edgeBlur.contains(.top) ? bubbleBlur : nil, alpha: 0.6, edge: .bottom, edgeSize: min(60, bubbleShadowRect.height), rect: bubbleShadowRect, transition: transition)


        if let view = inputContextHelper.accessoryView {
            let gap: CGFloat = 10
            let textContainer = inputView.textFieldContainer.convert(inputView.textFieldContainer.bounds, to: self)
            transition.updateFrame(view: view, frame: NSMakeRect(textContainer.minX, textContainer.minY - view.frame.height - gap, textContainer.width, view.frame.height))
        }
        if let currentView = header.currentView {
            let headerEdge: CGFloat = 12
            var inset: CGFloat = 0
            if let monoforum_VerticalView {
                inset += 12 + monoforum_VerticalView.frame.width
            }
            
            let headerFrame = inlineFrame?.offsetBy(dx: headerInset.x, dy: navigationOverflow)
                ?? NSMakeRect(inset + headerEdge, bubblesView.frame.maxY, frame.width - inset - headerEdge * 2, headerHeight)
            header.measure(headerFrame.width)

            let headerTransition: ContainedViewLayoutTransition = header.hasLayout ? transition : .immediate
            headerTransition.updateFrame(view: currentView, frame: headerFrame)
            header.updateLayout(size: currentView.frame.size, transition: headerTransition)
        }
        
        let inputHeight = inputView.height(for: frame.width)
        
        if tableRect != tableView.frame {
            transition.updateFrame(view: tableView, frame: tableRect)
        }

        let inputY: CGFloat = themeSelectorView != nil ? frame.height : tableView.frame.maxY - inputHeight

        let inputRect = NSMakeRect(0, inputY, frame.width, max(50, inputHeight))
        transition.updateFrame(view: inputView, frame: inputRect)
        inputView.updateLayout(size: NSMakeSize(frame.width, inputRect.height), transition: transition)


        let scrollInset = inputHeight - 24
        tableView.scrollerInsets = NSEdgeInsets(bottom: scrollInset)

        if let view = transcriptionView {
            let height = view.contentHeight
            let rect = NSMakeRect(0, inputRect.minY - height - ChatControllerView.transcriptionGap, frame.width, height)
            transition.updateFrame(view: view, frame: rect)
            view.updateLayout(size: rect.size, transition: transition)
        }

        
        let inputShadowExtra: CGFloat = 24
        let inputShadowMinY = max(0, inputView.frame.minY - inputShadowExtra)
        let inputShadowHeight: CGFloat = max(frame.height + 200, 600)
        let inputShadowRect = NSMakeRect(shadowX, inputShadowMinY, shadowWidth, inputShadowHeight)

        transition.updateFrame(view: inputShadowView, frame: inputShadowRect)
        let inputShadowHorizontalFade: CGFloat = inputShadowRect.width > 0 ? min(0.5, 60 / inputShadowRect.width) : 0
        let inputPillTop = inputRect.maxY - inputHeight
        let inputBlurBottom = max(frame.height, inputPillTop)
        let inputBlurHeight = max(60, inputBlurBottom - (inputPillTop + 4))
        let inputBlur = EdgeEffectView.Blur(rect: NSMakeRect(shadowX, inputBlurBottom - inputBlurHeight, shadowWidth, inputBlurHeight), edgeSize: 60)
        inputShadowView.update(color: edgeBg, blur: ChatControllerView.edgeBlur.contains(.bottom) ? inputBlur : nil, alpha: 0.6, edge: .top, edgeSize: 60, rect: inputShadowRect, transition: transition, horizontalFade: inputShadowHorizontalFade)
        

        if let backgroundView = backgroundView {
            transition.updateFrame(view: backgroundView, frame: NSMakeRect(shadowX, -(wFrame.height - frame.height), shadowWidth, wFrame.height))
        }
        transition.updateFrame(view: gradientMaskView, frame: tableView.frame)
        
        if let progressView = progressView {
            transition.updateFrame(view: progressView, frame: progressView.centerFrame().offsetBy(dx: headerInset.x != 0 ? headerInset.x / 2 : 0, dy: -inputView.frame.height/2))
        }
        transition.updateFrame(view: scroller, frame: scrollerRect)
        
        if let mentions = mentions {
            transition.updateFrame(view: mentions, frame: mentionsRect)
        }
        if let reactions = reactions {
            transition.updateFrame(view: reactions, frame: reactionsRect)
        }
        if let pollVotes = pollVotes {
            transition.updateFrame(view: pollVotes, frame: pollVotesRect)
        }
        inputView.updateFloatingColumnAnchor(floatingColumnAnchor, transition: transition)
        transition.updateFrame(view: floatingPhotosView, frame: tableView.frame)

        if let toasterView = self.toasterView {
            transition.updateFrame(view: toasterView, frame: toasterRect)
        }

        DispatchQueue.main.async { [weak self] in
            guard let `self` = self else {
                return
            }
            let visibleRows = self.tableView.visibleRows(frame.height)
            for i in visibleRows.lowerBound ..< visibleRows.upperBound {
                let item = self.tableView.item(at: i)
                if let view = item.view as? ChatRowView {
                    view.updateBackground(animated: transition.isAnimated, item: view.item)
                }
            }
        }
        

        if let themeSelectorView = self.themeSelectorView {
            transition.updateFrame(view: themeSelectorView, frame: NSMakeRect(0, frame.height - themeSelectorView.frame.height, frame.width, themeSelectorView.frame.height))
        }
        
        if let starUndoView {
            transition.updateFrame(view: starUndoView, frame: starUndoView.centerFrameX(y: navigationOverflow + bubbleBarHeight + headerHeight + 10))
        }

        if let videoProccesing {
            transition.updateFrame(view: videoProccesing, frame: videoProccesing.centerFrameX(y: navigationOverflow + bubbleBarHeight + headerHeight + 10))
        }
        
        if let monoforum_VerticalView {
            let vTop = bubblesView.frame.maxY
            let vBottom = inputView.frame.minY - 10
            let vHeight = max(0, vBottom - vTop)
            transition.updateFrame(view: monoforum_VerticalView, frame: NSMakeRect(12, vTop, monoforum_VerticalView.frame.width, vHeight))
            monoforum_VerticalView.updateLayout(size: monoforum_VerticalView.frame.size, transition: transition)
        }
        
        
        self.textInputSuggestionsView?.updateRect(transition: transition)
      //  self.updateFloatingPhotos?(self.scroll, transition.isAnimated)
        //self.chatInteraction.updateFrame(frame, transition)
    }

    public override var responder: NSResponder? {
        return inputView.responder
    }
    
    func change(state:ChatControllerViewState, animated:Bool) {
        let state = chatInteraction.presentation.isNotAccessible ? .visible : state
        if state != self.state {
            self.state = state
            
            switch state {
            case .progress:
                if progressView == nil {
                    self.progressView = ProgressIndicator(frame: NSMakeRect(0,0,30,30))
                    self.progressView?.innerInset = 6
                    progressView!.animates = true
                    addSubview(progressView!)
                    
                    var leftInset: CGFloat = 0
                    if let monoforum_VerticalView {
                        leftInset += monoforum_VerticalView.frame.width / 2
                    }
                    progressView!.frame = progressView!.centerFrame().offsetBy(dx: leftInset, dy: -inputView.frame.height/2)
                }
                let currentTheme = self.chatTheme ?? theme
                if currentTheme.shouldBlurService, !TelegramUtilsHooks.shared.isLite(.blur) {
                    progressView?.blurBackground = currentTheme.blurServiceColor
                    progressView?.backgroundColor = .clear
                } else {
                    progressView?.backgroundColor = currentTheme.chatServiceItemColor
                    progressView?.blurBackground = nil
                }
                progressView?.progressColor = currentTheme.chatServiceItemTextColor
                progressView?.layer?.cornerRadius = 15
            case .visible:
                if let view = progressView {
                    performSubviewRemoval(view, animated: animated)
                    progressView = nil
                }
            }
        }
        if chatInteraction.presentation.isNotAccessible {
            tableView.updateEmpties()
        }
    }
    
    func updateHeader(_ interfaceState:ChatPresentationInterfaceState, _ animated:Bool, _ animateOnlyHeader: Bool = false) {

    
        var voiceChat: ChatActiveGroupCallInfo?
        if interfaceState.groupCall?.data?.groupCall == nil, interfaceState.threadInfo == nil, interfaceState.chatMode != .preview {
            if let data = interfaceState.groupCall?.data {
                if data.participantCount == 0 && interfaceState.groupCall?.activeCall.scheduleTimestamp == nil {
                    voiceChat = nil
                } else {
                    voiceChat = interfaceState.groupCall
                }
            } else {
                voiceChat = nil
            }
        } else {
            voiceChat = nil
        }

        var value:ChatHeaderState.Value
        if let settings = interfaceState.peerStatus?.peerStatusSettings, let stars = settings.paidMessageStars, let peer = interfaceState.peer {
            value = .removePaidMessages(peer, stars)
        } else if let removePaidMessageFeeData = interfaceState.removePaidMessageFeeData, let peer = interfaceState.peer {
            value = .removePaidMessages(peer, removePaidMessageFeeData.amount)
        } else if interfaceState.peer?.restrictionText(interfaceState.contentSettings) != nil {
            value = .none
        } else if interfaceState.searchMode.inSearch {
            var tags: [EmojiTag]? = nil
            
            if let savedMessageTags = interfaceState.savedMessageTags {
                if interfaceState.accountPeer?.isPremium == false || !savedMessageTags.tags.isEmpty, chatInteraction.peerId == chatInteraction.interactionContext.peerId {
                    tags = []
                }
                for tag in savedMessageTags.tags {
                    switch tag.reaction {
                    case .builtin:
                        if let file = chatInteraction.interactionContext.reactions.available?.enabled.first(where: { $0.value == tag.reaction })?.activateAnimation._parse() {
                            tags?.append(.init(emoji: tag.reaction.string, tag: tag, file: file))
                        }
                    case let .custom(fileId):
                        if let file = savedMessageTags.files[fileId] {
                            tags?.append(.init(emoji: tag.reaction.string, tag: tag, file: file))
                        }
                    case .stars:
                        break
                    }
                }
            }
            
            let selected: EmojiTag?
            if let tag = interfaceState.searchMode.tag, case let .customTag(memoryBuffer, _) = tag {
                let tag = ReactionsMessageAttribute.reactionFromMessageTag(tag: memoryBuffer)
                selected = tags?.first(where: { $0.tag.reaction == tag })
            } else {
                selected = nil
            }
            
            value = .search(searchInteractions, interfaceState.searchMode.peer?._asPeer(), interfaceState.searchMode.query, tags, selected, interfaceState.chatLocation)
        } else if interfaceState.chatMode != .preview, let threadData = interfaceState.threadInfo, threadData.isClosed, let peer = interfaceState.peer as? TelegramChannel, peer.adminRights != nil || peer.flags.contains(.isCreator) || threadData.isOwnedByMe {
            value = .restartTopic
        } else if interfaceState.managedBotNeedsPhoto {
            value = .setBotPhoto
        } else if let count = interfaceState.inviteRequestsPending, let inviteRequestsPendingPeers = interfaceState.inviteRequestsPendingPeers, !inviteRequestsPendingPeers.isEmpty, interfaceState.threadInfo == nil {
            value = .pendingRequests(Int(count), inviteRequestsPendingPeers)
        } else if interfaceState.reportMode != nil {
            value = .none
        } else if let initialAction = interfaceState.initialAction, case let .ad(kind) = initialAction {
            value = .promo(kind)
        } else if let peerStatus = interfaceState.peerStatus, let settings = peerStatus.peerStatusSettings, !settings.flags.isEmpty {
            
            if let requestChatTitle = settings.requestChatTitle, let date = settings.requestChatDate, let mainPeer = interfaceState.mainPeer {
                let text: String
                if settings.requestChatIsChannel == true {
                    text = strings().chatInviteRequestAdminChannel(mainPeer.displayTitle, requestChatTitle)
                } else {
                    text = strings().chatInviteRequestAdminGroup(mainPeer.displayTitle, requestChatTitle)
                }
                
                let formatter = DateSelectorUtil.chatFullDateFormatter
                
                let alertText = strings().chatInviteRequestInfo(requestChatTitle, formatter.string(from: Date(timeIntervalSince1970: TimeInterval(date))))
                value = .requestChat(text, alertText)
            } else if peerStatus.canAddContact && settings.contains(.canAddContact) {
                value = .addContact(block: settings.contains(.canReport) || settings.contains(.canBlock), autoArchived: settings.contains(.autoArchived))
            } else if settings.contains(.canReport) {
                let isUser = interfaceState.peer?.isUser == true
                value = .report(autoArchived: settings.contains(.autoArchived), status: isUser ? interfaceState.peer?.emojiStatus : nil)
            } else if settings.contains(.canShareContact) {
                value = .shareInfo
            } else if let pinnedMessageId = interfaceState.pinnedMessageId, !interfaceState.interfaceState.dismissedPinnedMessageId.contains(pinnedMessageId.messageId), !interfaceState.hidePinnedMessage, interfaceState.chatMode != .pinned {
                
                let translation: ChatLiveTranslateContext.State.Result?
                if let translate = interfaceState.translateState {
                    translation = translate.result[.Key(id: pinnedMessageId.messageId, toLang: translate.to)]
                } else {
                    translation = nil
                }
                
                if pinnedMessageId.message?.restrictedText(chatInteraction.interactionContext.contentSettings) == nil {
                    value = .pinned(pinnedMessageId, translation, doNotChangeTable: interfaceState.chatLocation.threadId != nil)
                } else {
                    value = .none
                }
            } else {
                value = .none
            }
        } else if let pinnedMessageId = interfaceState.pinnedMessageId, !interfaceState.interfaceState.dismissedPinnedMessageId.contains(pinnedMessageId.messageId), !interfaceState.hidePinnedMessage, interfaceState.chatMode != .pinned {
            if pinnedMessageId.message?.restrictedText(chatInteraction.interactionContext.contentSettings) == nil {
                
                let translation: ChatLiveTranslateContext.State.Result?
                if let translate = interfaceState.translateState {
                    translation = translate.result[.Key(id: pinnedMessageId.messageId, toLang: translate.to)]
                } else {
                    translation = nil
                }
                
                value = .pinned(pinnedMessageId, translation, doNotChangeTable: interfaceState.chatLocation.threadId != nil)
            } else {
                value = .none
            }
        } else if let canAdd = interfaceState.canAddContact, canAdd {
            value = .none
        } else {
            value = .none
        }
        var translate: ChatPresentationInterfaceState.TranslateState?
        if interfaceState.peer?.restrictionText(interfaceState.contentSettings) == nil {
            if let translateState = interfaceState.translateState, translateState.canTranslate {
                if case .search = value {
                    translate = nil
                } else {
                    translate = translateState
                }
            } else {
                translate = nil
            }
        } else {
            translate = nil
        }

        let botAd: Message? = (interfaceState.historyCount ?? 0) >= 2 ? interfaceState.adMessage : nil
        
             
        let state: ChatHeaderState = .init(main: value, voiceChat: voiceChat, translate: translate, botManager: interfaceState.chatMode == .preview ? nil : interfaceState.connectedBot, botAd: botAd.flatMap { .init(message: $0, chatInteraction: chatInteraction) }, monoforumHorizontal: interfaceState.monoforumState == .horizontal ? monoforumHorizontalData : nil)

        state.measure(frame.width - (interfaceState.monoforumState == .vertical ? 92 : 0) - 24)

        header.updateState(state, animated: animated, for: self, inset: interfaceState.monoforumState == .vertical ? 92 : 0, relativeView: header.monoforumView, mergeGlassOnRemoval: bubblesView.displaysInlineHeader)

        updateHeaderInsets(width: frame.width, animated: animated)

        if superview != nil {
            updateFrame(frame, transition: animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate)
        }
    }
    
    

    func updateMonoforumState(state: MonoforumUIState?, items: [MonoforumItem], threadId: Int64?, animated: Bool) {
        if let state {
            switch state {
            case .horizontal:
                if let view = monoforum_VerticalView {
                    performSubviewPosRemoval(view, pos: NSMakePoint(-view.frame.width, view.frame.minY), animated: animated)
                    self.monoforum_VerticalView = nil
                }
                self.monoforumHorizontalData = .init(items: items, selected: threadId)

            case .vertical:
                self.monoforumHorizontalData = nil

                let current: MonoforumVerticalView
                if let view = self.monoforum_VerticalView {
                    current = view
                } else {
                    let y = bubblesView.frame.maxY
                    current = MonoforumVerticalView(frame: NSMakeRect(0, y, 80, tableRect.height - y))
                    addSubview(current, positioned: .below, relativeTo: inputView)
                    self.monoforum_VerticalView = current

                    if animated {
                        current.layer?.animateAlpha(from: 0.5, to: 1, duration: 0.2)
                        current.layer?.animatePosition(from: NSMakePoint(-current.frame.width, 0), to: .zero)
                    }
                }

                current.set(items: items, selected: threadId, chatInteraction: chatInteraction, animated: animated)
            }
        } else {
            if let view = monoforum_VerticalView {
                performSubviewPosRemoval(view, pos: NSMakePoint(-view.frame.width, 0), animated: animated)
                self.monoforum_VerticalView = nil
            }
            self.monoforumHorizontalData = nil
        }
        
        updateFrame(self.frame, transition: animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate)
    }
    
    private let floatingColumnBadgeOverhang: CGFloat = 6

    private var floatingColumnAnchor: NSPoint? {
        let entries: [(ChatNavigationScroller?, NSRect)] = [(scroller, scrollerRect), (mentions, mentionsRect), (reactions, reactionsRect), (pollVotes, pollVotesRect)]
        var top: CGFloat?
        for (button, rect) in entries {
            guard let button, !button.controlIsHidden else {
                continue
            }
            let diameter = button.glassSize?.height ?? rect.height
            let value = rect.minY + (rect.height - diameter) / 2 - (button.hasBadge ? floatingColumnBadgeOverhang : 0)
            top = min(top ?? value, value)
        }
        guard let top else {
            return nil
        }
        return self.convert(NSMakePoint(0, top), to: nil)
    }

    private var scrollerRect: NSRect {
        return NSMakeRect(frame.width - scroller.frame.width,  frame.height - inputView.frame.height - 6 - scroller.frame.height, scroller.frame.width, scroller.frame.height)
    }
    private var mentionsRect: NSRect {
        if let _ = mentions {
            if scroller.controlIsHidden {
                return scrollerRect.offsetBy(dx: 0, dy: 0)
            } else {
                return scrollerRect.offsetBy(dx: 0, dy: scroller.hasBadge ? -56 : -50)
            }
        }
        return .zero
    }
    private var reactionsRect: NSRect {
        if let _ = reactions {
            if let mentions = mentions {
                if scroller.controlIsHidden {
                    return mentionsRect.offsetBy(dx: 0, dy: 0)
                } else {
                    return mentionsRect.offsetBy(dx: 0, dy: mentions.hasBadge ? -56 : -50)
                }
            } else {
                if scroller.controlIsHidden {
                    return scrollerRect.offsetBy(dx: 0, dy: 0)
                } else {
                    return scrollerRect.offsetBy(dx: 0, dy: scroller.hasBadge ? -56 : -50)
                }
            }
        }
        return .zero
    }
    private var pollVotesRect: NSRect {
        if let _ = pollVotes {
            if let reactions = reactions {
                return reactionsRect.offsetBy(dx: 0, dy: reactions.hasBadge ? -56 : -50)
            } else if let mentions = mentions {
                return mentionsRect.offsetBy(dx: 0, dy: mentions.hasBadge ? -56 : -50)
            } else {
                if scroller.controlIsHidden {
                    return scrollerRect.offsetBy(dx: 0, dy: 0)
                } else {
                    return scrollerRect.offsetBy(dx: 0, dy: scroller.hasBadge ? -56 : -50)
                }
            }
        }
        return .zero
    }

    var hasEmojiSwap: Bool {
        return self.textInputSuggestionsView != nil
    }
    
    func updateTextInputSuggestions(_ files: [TelegramMediaFile], range: NSRange, animated: Bool) {
        if !files.isEmpty {
            let current: InputSwapSuggestionsPanel
            let isNew: Bool
            if let view = self.textInputSuggestionsView {
                current = view
                isNew = false
            } else {
                current = InputSwapSuggestionsPanel(inputView: self.inputView.textView, textContent: self.inputView.textView.scrollView.contentView, relativeView: self, window: chatInteraction.interactionContext.window, context: chatInteraction.interactionContext, highlightRect: { [weak self] range, whole in
                    return self?.inputView.textView.highlight(for: range, whole: whole) ?? .zero
                })
                self.textInputSuggestionsView = current
                isNew = true
            }
            current.apply(files, range: range, animated: animated, isNew: isNew)
        } else if let view = self.textInputSuggestionsView {
            view.close(animated: animated)
            self.textInputSuggestionsView = nil
        }
    }
    
    func updateMentionsCount(mentionsCount: Int32, reactionsCount: Int32, pollVotesCount: Int32, scrollerCount: Int32, animated: Bool) {
        if mentionsCount > 0 {
            if self.mentions == nil {
                self.mentions = ChatNavigationScroller(.mentions)
                self.mentions?.set(handler: { [weak self] _ in
                    self?.chatInteraction.mentionPressed()
                }, for: .Click)
                
                self.mentions?.set(handler: { [weak self] _ in
                    self?.chatInteraction.clearMentions()
                }, for: .LongMouseDown)
                
                if let mentions = self.mentions {
                    mentions.frame = mentionsRect
                    mentions.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    addSubview(mentions, positioned: .below, relativeTo: inputView)
                }             
            }
            self.mentions?.updateCount(mentionsCount)
        } else {
            if let mentions = self.mentions {
                self.mentions = nil
                performSubviewRemoval(mentions, animated: true, scale: true)
            }
        }
        if reactionsCount > 0 {
            if self.reactions == nil {
                self.reactions = ChatNavigationScroller(.reactions)
                self.reactions?.set(handler: { [weak self] _ in
                    self?.chatInteraction.reactionPressed()
                }, for: .Click)
                
                self.reactions?.set(handler: { [weak self] _ in
                    self?.chatInteraction.clearReactions()
                }, for: .LongMouseDown)
                
                if let reactions = self.reactions {
                    reactions.frame = reactionsRect
                    reactions.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    addSubview(reactions, positioned: .below, relativeTo: inputView)
                }
            }
            self.reactions?.updateCount(reactionsCount)
        } else {
            if let reactions = self.reactions {
                self.reactions = nil
                performSubviewRemoval(reactions, animated: true, scale: true)
            }
        }
        if pollVotesCount > 0 {
            if self.pollVotes == nil {
                self.pollVotes = ChatNavigationScroller(.pollVotes)
                self.pollVotes?.set(handler: { [weak self] _ in
                    self?.chatInteraction.reactionPressed()
                }, for: .Click)

                self.pollVotes?.set(handler: { [weak self] _ in
                    self?.chatInteraction.clearReactions()
                }, for: .LongMouseDown)

                if let pollVotes = self.pollVotes {
                    pollVotes.frame = reactionsRect
                    pollVotes.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    addSubview(pollVotes, positioned: .below, relativeTo: inputView)
                }
            }
            self.pollVotes?.updateCount(pollVotesCount)
        } else {
            if let pollVotes = self.pollVotes {
                self.pollVotes = nil
                performSubviewRemoval(pollVotes, animated: true, scale: true)
            }
        }
        scroller.updateCount(scrollerCount)
        needsLayout = true
    }
    
    func applySearchResponder() {
        header.applySearchResponder()
    }

    
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {

        super.updateLocalizationAndTheme(theme: theme)
        
        let chatTheme = self.chatTheme ?? theme as! TelegramPresentationTheme
        
        if chatTheme.shouldBlurService, !TelegramUtilsHooks.shared.isLite(.blur) {
            progressView?.blurBackground = chatTheme.blurServiceColor
            progressView?.backgroundColor = .clear
        } else {
            progressView?.backgroundColor = chatTheme.chatServiceItemColor
            progressView?.blurBackground = nil
        }
        progressView?.progressColor = chatTheme.chatServiceItemTextColor
        scroller.updateLocalizationAndTheme(theme: chatTheme)
        header.updateLocalizationAndTheme(theme: chatTheme)

        bubblesView.updateLocalizationAndTheme(theme: chatTheme)
        bubblesView.updatePresentation(chatInteraction.presentation, force: true)
    }



    func forceCancelPendingStars() {
        if let starUndoView = self.starUndoView {
            performSubviewRemoval(starUndoView, animated: true)
            self.starUndoView = nil
        }
    }
    
    func updateStars(context: any AccountContextProtocol, count: Int32, messageId: MessageId) {
        let current: ChatStarReactionUndoView
        let animated: Bool
        if let view = self.starUndoView {
            current = view
            animated = true
        } else {
            current = ChatStarReactionUndoView(frame: .zero)
            addSubview(current)
            self.starUndoView = current
            animated = false
            
        }
        let size = current.update(context: context, messageId: messageId, count: count, animated: animated, complete: { [weak self] in
            if let starUndoView = self?.starUndoView {
                performSubviewRemoval(starUndoView, animated: true)
                self?.starUndoView = nil
            }
        }, undo: {
            context.engine.messages.cancelPendingSendStarsReaction(id: messageId)
        })
        
        let rect = self.frame.focusX(size, y: ChatHeaderBubblesView.totalHeight + headerHeight + 10)
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate
        transition.updateFrame(view: current, frame: rect)

        if !animated {
            current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            current.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.2)
        }

        self.updateFrame(self.frame, transition: transition)
    }

    func showVideoProccessingTooltip(context: any AccountContextProtocol, source: ChatVideoProcessingTooltip.Source, animated: Bool) {
        let current: ChatVideoProcessingTooltip
        let animated: Bool
        if let view = self.videoProccesing {
            current = view
            animated = true
        } else {
            current = ChatVideoProcessingTooltip(frame: .zero)
            addSubview(current)
            self.videoProccesing = current
            animated = false
            
        }
        let size = current.update(context: context, source: source, animated: animated, complete: { [weak self] in
            if let videoProccesing = self?.videoProccesing {
                performSubviewRemoval(videoProccesing, animated: true)
                self?.videoProccesing = nil
            }
        })
        
        let rect = self.frame.focusX(size, y: ChatHeaderBubblesView.totalHeight + headerHeight + 10)
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate
        transition.updateFrame(view: current, frame: rect)
        
        if !animated {
            current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            current.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.2)
        }
        
        self.updateFrame(self.frame, transition: transition)

    }

    private var toasterRect: NSRect {
        guard let view = toasterView else { return .zero }
        let maxWidth = max(80, frame.width - 24)
        let size = view.contentSize(maxWidth: maxWidth)
        let y = ChatHeaderBubblesView.totalHeight + headerHeight
        return frame.focusX(size, y: y)
    }

    var presentationTextColor: NSColor {
        return presentation.colors.text
    }

    func showToaster(text: NSAttributedString, animation: LocalAnimatedSticker? = nil, context: (any AccountContextProtocol)? = nil, action: (() -> Void)? = nil, timeout: Double, animated: Bool) {
        // Tear down any in-flight toaster before installing the new one —
        // `dismissImmediately` only kills the timer, so we also have to
        // remove the view from the hierarchy or it sticks around forever.
        if let existing = self.toasterView {
            self.toasterView = nil
            existing.dismissImmediately()
            performSubviewRemoval(existing, animated: true)
        }

        let view = ChatToasterView(frame: .zero)
        let maxWidth = max(80, frame.width - 24)
        view.update(text: text, animation: animation, context: context, maxWidth: maxWidth)
        let size = view.contentSize(maxWidth: maxWidth)
        let y = ChatHeaderBubblesView.totalHeight + headerHeight + 8
        view.frame = frame.focusX(size, y: y)
        self.toasterView = view

        if let action {
            view.set(handler: { [weak self] _ in
                action()
                self?.removeToaster(animated: true)
            }, for: .Click)
        }

        addSubview(view, positioned: .above, relativeTo: bubblesView)

        if animated {
            view.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            view.layer?.animateScaleSpring(from: 0.5, to: 1, duration: 0.3)
            view.layer?.animatePosition(from: NSMakePoint(view.frame.minX, view.frame.minY - 12), to: view.frame.origin, duration: 0.25, timingFunction: .spring)
        }

        view.scheduleAutoDismiss(after: timeout) { [weak self] in
            self?.removeToaster(animated: true)
        }
    }

    func showToaster(text: String, action: (() -> Void)? = nil, timeout: Double, animated: Bool) {
        let attributed = NSAttributedString.initialize(string: text, color: presentation.colors.text, font: .normal(.text))
        showToaster(text: attributed, action: action, timeout: timeout, animated: animated)
    }

    func removeToaster(animated: Bool) {
        guard let view = self.toasterView else { return }
        self.toasterView = nil
        view.dismissImmediately()
        performSubviewRemoval(view, animated: animated)
        if animated {
            view.layer?.animatePosition(from: view.frame.origin, to: NSMakePoint(view.frame.minX, view.frame.minY - 12), duration: 0.2, removeOnCompletion: false)
        }
    }

}

final class ChatToasterView: Control {
    private let glass: LiquidGlassView
    private let textView = TextView()
    private let animationView: MediaAnimatedStickerView = MediaAnimatedStickerView(frame: NSMakeRect(0, 0, 26, 26))
    private var hasAnimation: Bool = false
    private let animationSize: CGFloat = 26
    private let animationSpacing: CGFloat = 8
    /// Auto-dismiss timer owned by the view itself, so the view manages its
    /// own lifecycle. Previously a separate `ChatToaster` model held both a
    /// strong reference to the view AND the disposable, which made the
    /// ownership graph harder to reason about and risked retain cycles.
    private let dismissDisposable = MetaDisposable()

    private let horizontalPadding: CGFloat = 18
    private let verticalPadding: CGFloat = 8
    private let minHeight: CGFloat = 36

    required init(frame frameRect: NSRect) {
        self.glass = LiquidGlassView(frame: frameRect.size.bounds, cornerRadius: max(36, frameRect.height) / 2, hasShadow: true, hasBorder: true, tintAlpha: 0.0)
        super.init(frame: frameRect)
        addSubview(glass)
        addSubview(textView)
        addSubview(animationView)
        animationView.userInteractionEnabled = false
        animationView.isHidden = true
        textView.isSelectable = false
        textView.userInteractionEnabled = false
        textView.disableBackgroundDrawing = true
        self.layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        dismissDisposable.dispose()
    }

    func update(text: NSAttributedString, animation: LocalAnimatedSticker? = nil, context: (any AccountContextProtocol)? = nil, maxWidth: CGFloat) {
        let iconWidth: CGFloat
        if let animation, let context {
            hasAnimation = true
            animationView.isHidden = false
            let color = (text.length > 0 ? text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor : nil) ?? NSColor.white
            let parameters = ChatAnimatedStickerMediaLayoutParameters(playPolicy: .once, alwaysAccept: true, cache: .temporaryLZ4(.thumb), hidePlayer: false, media: animation.file, colors: [.init(keyPath: "", color: color)], shimmer: false)
            animationView.update(with: animation.file, size: NSMakeSize(animationSize, animationSize), context: context, table: nil, parameters: parameters, animated: false)
            iconWidth = animationSize + animationSpacing
        } else {
            hasAnimation = false
            animationView.isHidden = true
            iconWidth = 0
        }
        let layout = TextViewLayout(text, maximumNumberOfLines: 3, truncationType: .end, alignment: .center)
        layout.measure(width: max(40, maxWidth - horizontalPadding * 2 - iconWidth))
        textView.update(layout)
    }

    func scheduleAutoDismiss(after timeout: Double, _ handler: @escaping () -> Void) {
        let signal: Signal<Void, NoError> = .single(Void()) |> delay(timeout, queue: .mainQueue())
        dismissDisposable.set(signal.start(next: handler))
    }

    /// Cancels the auto-dismiss timer without removing the view. Use this
    /// when the parent is replacing the toaster — the view itself is removed
    /// via `performSubviewRemoval` separately.
    func dismissImmediately() {
        dismissDisposable.dispose()
    }

    func contentSize(maxWidth: CGFloat) -> NSSize {
        guard let layout = textView.textLayout else {
            return NSMakeSize(120, minHeight)
        }
        let iconWidth: CGFloat = hasAnimation ? animationSize + animationSpacing : 0
        let width = min(maxWidth, layout.layoutSize.width + iconWidth + horizontalPadding * 2)
        let height = max(minHeight, layout.layoutSize.height + verticalPadding * 2)
        return NSMakeSize(width, height)
    }

    override func layout() {
        super.layout()
        glass.frame = bounds
        glass.cornerRadius = bounds.height / 2
        if hasAnimation {
            let iconWidth = animationSize + animationSpacing
            let contentWidth = iconWidth + textView.frame.width
            let startX = floor((bounds.width - contentWidth) / 2)
            animationView.setFrameOrigin(NSMakePoint(startX, floor((bounds.height - animationSize) / 2)))
            textView.setFrameOrigin(NSMakePoint(startX + iconWidth, floor((bounds.height - textView.frame.height) / 2)))
        } else {
            textView.center()
        }
    }
}




fileprivate func prepareEntries(from fromView:ChatHistoryView?, to toView:ChatHistoryView, timeDifference: TimeInterval, initialSize:NSSize, interaction:ChatInteraction, animated:Bool, scrollPosition:ChatHistoryViewScrollPosition?, reason:ChatHistoryViewUpdateType, animationInterface:TableAnimationInterface?, side: TableSavingSide?, messagesViewQueue: Queue) -> Signal<TableUpdateTransition, NoError> {
    return Signal { subscriber in
    
        
//        subscriber.putNext(TableUpdateTransition(deleted: [], inserted: [], updated: [], animated: animated, state: .none(nil), grouping: true))
//        subscriber.putCompletion()
        
        let initialSize = initialSize
        
        var scrollToItem:TableScrollState? = nil
        let offset:CGFloat = 0
        if let scrollPosition = scrollPosition {
            switch scrollPosition {
            case let .keepInPlace(messageId):
                if let entry = fromView?.filteredEntries.first(where: { $0.entry.messages.contains(where: { $0.id == messageId }) }) {
                    scrollToItem = .saveVisible(.aroundIndex(entry.stableId), false)
                } else {
                    scrollToItem = .saveVisible(.upper, false)
                }
            case .unread(_):
                var index = toView.filteredEntries.count - 1
                for entry in toView.filteredEntries {
                    if case .UnreadEntry = entry.appearance.entry {
                        scrollToItem = .top(id: entry.stableId, innerId: nil, animated: false, focus: .init(focus: false), inset: offset)
                        break
                    }
                    index -= 1
                }
                
                if scrollToItem == nil {
                    scrollToItem = .saveVisible(.upper, true)
                }
            case let .positionRestoration(scrollIndex, relativeOffset):
                
                let timestamp = Int32(min(TimeInterval(scrollIndex.timestamp) - timeDifference, TimeInterval(Int32.max)))

                
                let scrollIndex = scrollIndex.withUpdatedTimestamp(timestamp)
                var index = toView.filteredEntries.count - 1
                for entry in toView.filteredEntries {
                    if entry.appearance.entry.index >= scrollIndex {
                        scrollToItem = .top(id: entry.stableId, innerId: nil, animated: false, focus: .init(focus: false), inset: relativeOffset)
                        break
                    }
                    index -= 1
                }
                
                if scrollToItem == nil {
                    var index = 0
                    for entry in toView.filteredEntries.reversed() {
                        if entry.appearance.entry.index < scrollIndex {
                            scrollToItem = .top(id: entry.stableId, innerId: nil, animated: false, focus: .init(focus: false), inset: relativeOffset)
                            break
                        }
                        index += 1
                    }
                }
            case let .index(scrollIndex, position, _, _):
                let scrollIndex = scrollIndex.withSubstractedTimestamp(Int32(timeDifference))

                for entry in toView.filteredEntries {
                    if scrollIndex.isLessOrEqual(to: entry.appearance.entry.index) {
                        if case let .groupedPhotos(entries, _) = entry.appearance.entry {
                            for inner in entries {
                                if case let .MessageEntry(message, _, _, _, _, _, _) = inner {
                                    let timestamp = Int32(min(TimeInterval(message.timestamp) - timeDifference, TimeInterval(Int32.max)))

                                    let messageIndex = MessageIndex(message.withUpdatedTimestamp(timestamp))
                                    
                                    if !scrollIndex.isLess(than: messageIndex) && scrollIndex.isLessOrEqual(to: messageIndex) {
                                        scrollToItem = position.swap(to: entry.appearance.entry.stableId, innerId: inner.stableId)
                                    }
                                }
                            }
                        } else {
                            scrollToItem = position.swap(to: entry.appearance.entry.stableId)
                        }
                        break
                    }
                }
                
                if scrollToItem == nil {
                    var index = 0
                    for entry in toView.filteredEntries.reversed() {
                        if MessageHistoryAnchorIndex.message(entry.appearance.entry.index) < scrollIndex {
                            scrollToItem = position.swap(to: entry.appearance.entry.stableId)
                            break
                        }
                        index += 1
                    }
                }
            case let .scroll(state):
                scrollToItem = state
            }
        }
        
        if scrollToItem == nil {
            scrollToItem = .saveVisible(side ?? .upper, false)
            
            switch reason {
            case let .Generic(type):
                switch type {
                case .Generic:
                    scrollToItem = .none(animationInterface)
                default:
                    break
                }
            case let .Initial(fadeIn):
                if !fadeIn {
                    scrollToItem = .saveVisible(side ?? .upper, true)
                }
            }
        }
        
        
        func makeItem(_ entry: ChatWrappedEntry) -> TableRowItem {
            
            let presentation: TelegramPresentationTheme = entry.entry.additionalData.chatTheme ?? theme
            
            let item:TableRowItem = ChatRowItem.item(initialSize, from: entry.appearance.entry, interaction: interaction, theme: presentation)
            _ = item.makeSize(initialSize.width)
            item.premeasuredWidth = initialSize.width
            return item;
        }
        
        let firstTransition = Queue.mainQueue().isCurrent()
        let cancelled = Atomic(value: false)
        
        let prevIsLoading = fromView?.originalView == nil || fromView?.originalView?.isLoading == true 
        
        if firstTransition, let state = scrollToItem, prevIsLoading, fromView?.filteredEntries.isEmpty != false {
                        
            var initialIndex:Int = 0
            var height:CGFloat = 0
            var firstInsertion:[(Int, TableRowItem)] = []
            let entries = Array(toView.filteredEntries.reversed())
            
            switch state {
            case let .top(stableId, _, _, _, relativeOffset):
                var index:Int? = nil
                height = relativeOffset
                for k in 0 ..< entries.count {
                    if AnyHashable(entries[k].stableId) == stableId {
                        let x:Int = Int(ceil(abs(offset) / 28))
                        index = min(entries.count - 1, k + x)
                        break
                    }
                }
                
                if let index = index {
                    var success:Bool = false
                    var j:Int = index
                    for i in stride(from: index, to: -1, by: -1) {
                        let item = makeItem(entries[i])
                        if !item.ignoreAtInitialization {
                            height += item.height
                        }
                        firstInsertion.append((index - j, item))
                        j -= 1
                        if initialSize.height + offset < height {
                            success = true
                            break
                        }
                    }
                    
                    if !success {
                        for i in (index + 1) ..< entries.count {
                            let item = makeItem(entries[i])
                            if !item.ignoreAtInitialization {
                                height += item.height
                            }
                            firstInsertion.insert((0, item), at: 0)
                            if initialSize.height + offset < height {
                                success = true
                                break
                            }
                        }
                    }
                    
                    var reversed:[(Int, TableRowItem)] = []
                    var k:Int = 0
                    
                    for f in firstInsertion.reversed() {
                        reversed.append((k, f.1))
                        k += 1
                    }
                
                    firstInsertion = reversed
                    

                    
                    if success {
                        initialIndex = (j + 1)
                    } else {
                        let alreadyInserted = firstInsertion.count
                        for i in alreadyInserted ..< entries.count {
                            let item = makeItem(entries[i])
                            height += item.height
                            firstInsertion.append((i, item))
                            if initialSize.height + offset < height {
                                break
                            }
                        }
                    }
                    
                    
                }
            case let .center(stableId, innerId, _, focus, relativeOffset):
                if let index = entries.firstIndex(where: { AnyHashable($0.stableId) == stableId }) {
                    let selection = chatInitialCenteredRows(count: entries.count, anchor: index, viewportHeight: initialSize.height, accountForAnchorHeight: innerId == nil && focus.isWholeRow && relativeOffset == 0, makeItem: { index in
                        makeItem(entries[index])
                    }, height: { item in
                        item.ignoreAtInitialization ? 0 : item.height
                    })
                    initialIndex = selection.range.lowerBound
                    firstInsertion = selection.items.enumerated().map { ($0.offset, $0.element) }
                }
            default:
                for i in 0 ..< entries.count {
                    let item = makeItem(entries[i])
                    firstInsertion.append((i, item))
                    if !item.ignoreAtInitialization {
                        height += item.height
                    }
                    if initialSize.height < height {
                        break
                    }
                }
            }
            var scrollState = state
            var ignoreHeight: CGFloat = 0
            for (_, item) in firstInsertion.reversed() {
                if item.ignoreAtInitialization {
                    ignoreHeight += item.height
                } else {
                    if ignoreHeight > 0 {
                        scrollState = .bottom(id: item.stableId, innerId: nil, animated: false, focus: .init(focus: false), inset: ignoreHeight)
                    }
                }
            }
            subscriber.putNext(TableUpdateTransition(deleted: [], inserted: firstInsertion, updated: [], state: scrollState, isPartOfTransition: true))
             
            
            messagesViewQueue.async {
                if !cancelled.with({ $0 }) {
                    
                    var firstInsertedRange:NSRange = NSMakeRange(0, 0)
                    
                    if !firstInsertion.isEmpty {
                        firstInsertedRange = NSMakeRange(initialIndex, firstInsertion.count)
                    }
                    
                    var insertions:[(Int, TableRowItem)] = []
                    let updates:[(Int, TableRowItem)] = []
                    
                    let finish:()->Void = {
                        subscriber.putNext(TableUpdateTransition(deleted: [], inserted: insertions, updated: updates, state: .saveVisible(.upper, false)))
                        subscriber.putCompletion()
                    }
                    
                    var mustBreak = false
                    for i in 0 ..< entries.count {
                        let item:TableRowItem
                        if cancelled.with({ $0 }) || mustBreak {
                            mustBreak = true
                            subscriber.putCompletion()
                            return
                        }
                        if firstInsertedRange.indexIn(i) {
                            //item = firstInsertion[i - initialIndex].1
                            //updates.append((i, item))
                        } else {
                            item = makeItem(entries[i])
                            insertions.append((i, item))
                        }
                    }
                    finish()
                }
            }
            
        } else if let state = scrollToItem {
            let (removed,inserted,updated) = proccessEntries(fromView?.filteredEntries, right: toView.filteredEntries, { entry -> TableRowItem in
                if !cancelled.with({ $0 }) {
                    return makeItem(entry)
                } else {
                    return TableRowItem(initialSize)
                }
            })
            var grouping: Bool = true
            
            var scrollState = state
            if removed.isEmpty, !inserted.isEmpty {
                var addAdded: Bool = true
                for inserted in inserted {
                    if !inserted.1.ignoreAtInitialization {
                        addAdded = false
                        break
                    }
                }
                if addAdded {
                    scrollState = .saveVisible(.lower, false)
                }
            } else if !updated.isEmpty, removed.isEmpty, inserted.isEmpty {
                if let fromEntries = fromView?.filteredEntries {
                    var fromByStableId: [ChatHistoryEntryId: ChatWrappedEntry] = [:]
                    fromByStableId.reserveCapacity(fromEntries.count)
                    for entry in fromEntries {
                        fromByStableId[entry.stableId] = entry
                    }
                    for toEntry in toView.filteredEntries {
                        if let fromEntry = fromByStableId[toEntry.stableId] {
                            if fromEntry.entry.additionalData.summarize != toEntry.entry.additionalData.summarize {
                                scrollState = .saveVisible(.aroundIndex(toEntry.stableId), true)
                                grouping = false
                                break
                            }
                        }
                    }
                }
            }
           
            subscriber.putNext(TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: scrollState.animated, state: scrollState, grouping: grouping, animateVisibleOnly: true))
            subscriber.putCompletion()
        }
        return ActionDisposable {
            _ = cancelled.swap(true)
        }
    }
}



enum ChatHistoryViewTransitionReason {
    case Initial(fadeIn: Bool)
    case InteractiveChanges
    case HoleReload    
    case Reload
}

private struct ChatTopVisibleMessageRange: Equatable {
    var lowerBound: MessageId
    var upperBound: MessageId
    var isLast: Bool
}

private struct ChatDismissedPins : Equatable {
    let ids: [MessageId]
    let tempMaxId: MessageId?
}

private final class ChatAdData {
    var preloadAdPeerId: PeerId?
    let preloadAdPeerDisposable = MetaDisposable()
    var pendingDynamicAdMessages: [Message] = []
    var pendingDynamicAdMessageInterval: Int?
    var remainingDynamicAdMessageInterval: Int?
    var remainingDynamicAdMessageDistance: CGFloat?
    var nextPendingDynamicMessageId: Int32 = 1
    private var seenMessageIds = Set<MessageId>()
    private var height: CGFloat = 0


    private let disposable = MetaDisposable()
    let context: AdMessagesHistoryContext
    
    private var allAdMessages: (fixed: Message?, opportunistic: [Message], version: Int) = (nil, [], 0) {
            didSet {
                self.allAdMessagesPromise.set(.single(self.allAdMessages))
            }
        }
    private let allAdMessagesPromise = Promise<(fixed: Message?, opportunistic: [Message], version: Int)>((nil, [], 0))
    
    var allMessages: Signal<(fixed: Message?, opportunistic: [Message], version: Int), NoError> {
        return allAdMessagesPromise.get()
    }


    init(context: any AccountContextProtocol, height: Signal<CGFloat, NoError>, peerId: PeerId) {
        self.context = context.engine.messages.adMessages(peerId: peerId)
        let signal = (combineLatest(self.context.state, height)
                      |> deliverOnMainQueue)
        
        disposable.set(signal.start(next: { [weak self] values in
            guard let `self` = self else {
                return
            }
            let (interPostInterval, messages, _, _) = values.0
            let height = values.1
            self.height = height
            
            if let interPostInterval = interPostInterval {
                self.pendingDynamicAdMessages = messages
                self.pendingDynamicAdMessageInterval = Int(interPostInterval)
                
                if self.remainingDynamicAdMessageInterval == nil {
                    self.remainingDynamicAdMessageInterval = Int(interPostInterval)
                }
                if self.remainingDynamicAdMessageDistance == nil {
                    self.remainingDynamicAdMessageDistance = height
                }
                
                self.resetAllAdMessages(messages.first)
            } else {
                var adPeerId: PeerId?
                adPeerId = messages.first?.author?.id
                
                if self.preloadAdPeerId != adPeerId {
                    self.preloadAdPeerId = adPeerId
                    if let adPeerId = adPeerId {
                        let combinedDisposable = DisposableSet()
                        self.preloadAdPeerDisposable.set(combinedDisposable)
                        combinedDisposable.add(context.account.viewTracker.polledChannel(peerId: adPeerId).start())
                        combinedDisposable.add(context.account.addAdditionalPreloadHistoryPeerId(peerId: adPeerId))
                    } else {
                        self.preloadAdPeerDisposable.set(nil)
                    }
                }
                
                self.resetAllAdMessages(messages.first)
            }
        }))

    }
    
    
    private func resetAllAdMessages(_ fixed: Message?) {
        if self.allAdMessages.fixed === fixed && self.allAdMessages.opportunistic.isEmpty && self.allAdMessages.version == 0 {
            return
        }
        self.allAdMessages = (fixed, [], 0)
    }
    
    private func maybeInsertPendingAdMessage(tableView: TableView, position: ScrollPosition, toLaterRange: (Int, Int), toEarlierRange: (Int, Int)) {
        if self.pendingDynamicAdMessages.isEmpty {
            return
        }
        
        let currentPrefetchDirectionIsToLater = position.direction == .top

        let selectedRange: (Int, Int)
        let range:[Int]
        let reverse: Bool
        if currentPrefetchDirectionIsToLater {
            selectedRange = (toLaterRange.0, toLaterRange.1)
            reverse = true
        } else {
            selectedRange = (toEarlierRange.0, toEarlierRange.1)
            reverse = false
        }
        if selectedRange.0 <= selectedRange.1 {
            if reverse {
                range = (selectedRange.0 ... selectedRange.1).reversed()
            } else {
                range = Array((selectedRange.0 ... selectedRange.1))
            }
        } else {
            range = []
        }
        
        if !range.isEmpty {
            var insertionTimestamp: Int32?
            for i in range {
                let item = tableView.item(at: i) as? ChatRowItem
                if let message = item?.message, message.id.namespace == Namespaces.Message.Cloud, message.adAttribute == nil {
                    
                    insertionTimestamp = message.timestamp
                    break
                }
            }

            if let insertionTimestamp = insertionTimestamp {
                let initialMessage = self.pendingDynamicAdMessages.removeFirst()
                let message = Message(
                    stableId: UInt32.max - 1 - UInt32(self.nextPendingDynamicMessageId),
                    stableVersion: initialMessage.stableVersion,
                    id: MessageId(peerId: initialMessage.id.peerId, namespace: initialMessage.id.namespace, id: self.nextPendingDynamicMessageId),
                    globallyUniqueId: nil,
                    groupingKey: nil,
                    groupInfo: nil,
                    threadId: nil,
                    timestamp: insertionTimestamp,
                    flags: initialMessage.flags,
                    tags: initialMessage.tags,
                    globalTags: initialMessage.globalTags,
                    localTags: initialMessage.localTags, 
                    customTags: initialMessage.customTags,
                    forwardInfo: initialMessage.forwardInfo,
                    author: initialMessage.author,
                    text: initialMessage.text,
                    attributes: initialMessage.attributes,
                    media: initialMessage.media,
                    peers: initialMessage.peers,
                    associatedMessages: initialMessage.associatedMessages,
                    associatedMessageIds: initialMessage.associatedMessageIds,
                    associatedMedia: initialMessage.associatedMedia,
                    associatedThreadInfo: initialMessage.associatedThreadInfo,
                    associatedStories: initialMessage.associatedStories
                )
                self.nextPendingDynamicMessageId += 1

                var allAdMessages = self.allAdMessages
                if allAdMessages.fixed?.adAttribute?.opaqueId == message.adAttribute?.opaqueId {
                    allAdMessages.fixed = self.pendingDynamicAdMessages.first?.withUpdatedStableVersion(stableVersion: UInt32(self.nextPendingDynamicMessageId))
                }
                allAdMessages.opportunistic.append(message)
                allAdMessages.version += 1
                self.allAdMessages = allAdMessages
            }
        }
    }
    
    func update(items allVisibleAnchorMessageIds: [(MessageId, Int)], tableView: TableView, position: ScrollPosition) {
        let visible = tableView.visibleRows()
        
        let toEarlierRange = (visible.upperBound + 1, tableView.count - 1)
        let toLaterRange = (0, visible.lowerBound)

        for (messageId, index) in allVisibleAnchorMessageIds {
            let itemHeight = tableView.item(at: index).height
            
            if self.seenMessageIds.insert(messageId).inserted, let remainingDynamicAdMessageIntervalValue = self.remainingDynamicAdMessageInterval, let remainingDynamicAdMessageDistanceValue = self.remainingDynamicAdMessageDistance {
                
                let remainingDynamicAdMessageInterval = remainingDynamicAdMessageIntervalValue - 1
                let remainingDynamicAdMessageDistance = remainingDynamicAdMessageDistanceValue - itemHeight
                if remainingDynamicAdMessageInterval <= 0 && remainingDynamicAdMessageDistance <= 0.0 {
                    self.remainingDynamicAdMessageInterval = self.pendingDynamicAdMessageInterval
                    self.remainingDynamicAdMessageDistance = self.height
                    self.maybeInsertPendingAdMessage(tableView: tableView, position: position, toLaterRange: toLaterRange, toEarlierRange: toEarlierRange)
                } else {
                    self.remainingDynamicAdMessageInterval = remainingDynamicAdMessageInterval
                    self.remainingDynamicAdMessageDistance = remainingDynamicAdMessageDistance
                }
            }
        }
    }
    
    func markAsSeen(opaqueId: Data) {
        for i in 0 ..< self.pendingDynamicAdMessages.count {
            if let pendingAttribute = self.pendingDynamicAdMessages[i].adAttribute, pendingAttribute.opaqueId == opaqueId {
                self.pendingDynamicAdMessages.remove(at: i)
                break
            }
        }
        self.context.markAsSeen(opaqueId: opaqueId)
    }

    func markAction(opaqueId: Data, media: Bool) {
        self.context.markAction(opaqueId: opaqueId, media: media, fullscreen: false)
    }
    
    func remove(opaqueId: Data) {
        self.context.remove(opaqueId: opaqueId)
    }
    
    deinit {
        disposable.dispose()
        preloadAdPeerDisposable.dispose()
    }
}

private struct FindSearchMessage {
    let message:Message?
    let loaded:Bool
}

private enum ChatPlayEffectTarget {
    case premiumSticker
    case animatedEmoji
    case effect
}

open class ChatController<Context: AccountContextProtocol>: TelegramGenericViewController<ChatControllerView, Context>, Notifable, TableViewDelegate, ChatControllerKind, ChatInterfaceController {
    private enum WallpaperResult : Equatable {
        case result(Wallpaper?)
        case loading 
    }
    private struct WallpaperTuple : Equatable {
        var wallpaper: Wallpaper?
        var appearance: Appearance
        init(_ wallpaper: Wallpaper? = nil, _ appearance: Appearance) {
            self.wallpaper = wallpaper
            self.appearance = appearance
        }
    }
    private struct ThemeTuple : Equatable {
        let theme: TelegramPresentationTheme
        let emoticon: ChatTheme?
        let genuie: TelegramPresentationTheme
        let temp: Bool
    }
    private struct FindSearchMessage {
        let message:Message?
        let loaded:Bool
    }
    private struct PeerViewTuple : Equatable {
        var peer: Peer
        var monoforumPeer: Peer?
        var cachedData: CachedPeerData?
        static func ==(lhs: PeerViewTuple, rhs: PeerViewTuple) -> Bool {
            if let lhsCachedData = lhs.cachedData, let rhsCachedData = rhs.cachedData {
                if !lhsCachedData.isEqual(to: rhsCachedData) {
                    return false
                }
            } else if (lhs.cachedData != nil) != (rhs.cachedData != nil) {
                return false
            }
            return lhs.peer.isEqual(rhs.peer)
        }
    }

    open override var defaultBarTitle: String {
        return localizedString("Telegram.ChatController")
    }

    var state: ViewControllerState = .Normal 

    func changeState() {
        state = state == .Normal ? .Edit : .Normal
        update(with: state)
    }

    public override var enableBack: Bool {
        return true
    }

    
    public var chatLocation: ChatLocation {
        return chatInteraction.chatLocation
    }
    private let peerView = Promise<PostboxView?>()
    
    private let emojiEffects: EmojiScreenEffect
//    private var reactionManager:AddReactionManager?
    
    private let queue: Queue = .init(name: "messagesViewQueue", qos: .userInitiated)

    private var heavyScrollWorkItem: DispatchWorkItem?

    private let historyDisposable:MetaDisposable = MetaDisposable()
    private let peerDisposable:MetaDisposable = MetaDisposable()
    private let titleUpdateDisposable:MetaDisposable = MetaDisposable()

    private let updatedChannelParticipants:MetaDisposable = MetaDisposable()
    private let sentMessageEventsDisposable = MetaDisposable()
    private let proccessingMessageEventsDisposable = MetaDisposable()
    private let messageActionCallbackDisposable:MetaDisposable = MetaDisposable()
    private let shareContactDisposable:MetaDisposable = MetaDisposable()
    private let peerInputActivitiesDisposable:MetaDisposable = MetaDisposable()
    private let connectionStatusDisposable:MetaDisposable = MetaDisposable()
    private let messagesActionDisposable:MetaDisposable = MetaDisposable()
    private let unblockDisposable:MetaDisposable = MetaDisposable()
    private let updatePinnedDisposable:MetaDisposable = MetaDisposable()
    private let tonAddressMenuDisposable = MetaDisposable()
    private let reportPeerDisposable:MetaDisposable = MetaDisposable()
    private let focusMessageDisposable:MetaDisposable = MetaDisposable()
    private var messageFocusRequestId = 0
    private let updateFontSizeDisposable:MetaDisposable = MetaDisposable()
    private let loadFwdMessagesDisposable:MetaDisposable = MetaDisposable()
    private let chatUnreadMentionCountDisposable:MetaDisposable = MetaDisposable()
    private let navigationActionDisposable:MetaDisposable = MetaDisposable()
    private let messageIndexDisposable: MetaDisposable = MetaDisposable()
    private let dateDisposable:MetaDisposable = MetaDisposable()
    private let interactiveReadingDisposable: MetaDisposable = MetaDisposable()
    private let interactiveReadReactionsDisposable: MetaDisposable = MetaDisposable()
    private let interactiveReadStateDisposable = MetaDisposable()
    private var interactiveReadEnabled = false
    private let replyMessageDisposable = MetaDisposable()
    private let deleteChatDisposable: MetaDisposable = MetaDisposable()
    private let loadSelectionMessagesDisposable: MetaDisposable = MetaDisposable()
    private var currentRanks: CachedChannelAdminRanks?
    private let updateMediaDisposable = MetaDisposable()
    private let editCurrentMessagePhotoDisposable = MetaDisposable()
    private var editingSessionId: Int = 0
    private let failedMessageEventsDisposable = MetaDisposable()
    private let monoforumTopicsDisposable = MetaDisposable()
    private let newTopicEventsDisposable = MetaDisposable()
    private let selectMessagePollOptionDisposables: DisposableDict<MessageId> = DisposableDict()
    private let codeSyntaxHighlightDisposables: DisposableDict<CodeSyntaxKey> = DisposableDict()
    private var captureExclusionToken: CaptureExclusionManager.Token?
    private weak var captureExclusionWindow: NSWindow?
    private var isCaptureProtected: Bool = false

    private let hasScheduledMessagesDisposable = MetaDisposable()
    private let discussionDataLoadDisposable = MetaDisposable()
    private let slowModeDisposable = MetaDisposable()
    private let slowModeInProgressDisposable = MetaDisposable()
    private let forwardMessagesDisposable = MetaDisposable()
    private let shiftSelectedDisposable = MetaDisposable()
    private let updateUrlDisposable = MetaDisposable()
    private let pollChannelDiscussionDisposable = MetaDisposable()
    private let peekDisposable = MetaDisposable()
    private let loadThreadDisposable = MetaDisposable()
    private let updateChatLocationThreadDisposable = MetaDisposable()
    private let recordActivityDisposable = MetaDisposable()
    private let suggestionsDisposable = MetaDisposable()
    private let sendAsPeersDisposable = MetaDisposable()
    private let startSecretChatDisposable = MetaDisposable()
    private let inputSwapDisposable = MetaDisposable()
    private let liveTranslateDisposable = MetaDisposable()
    private let presentationDisposable = DisposableSet()
    private let storiesDisposable = MetaDisposable()
    private let keepShortcutDisposable = MetaDisposable()
    
    private let preloadPersonalChannel = MetaDisposable()
    private let premiumOrStarsRequiredDisposable = MetaDisposable()
    
    private var keepMessageCountersSyncrhonizedDisposable: Disposable?
    private var keepSavedMessagesSyncrhonizedDisposable: Disposable?
    private var networkSpeedEventsDisposable: Disposable?


    private let searchState: ValuePromise<SearchMessagesResultState> = ValuePromise(SearchMessagesResultState("", []), ignoreRepeated: true)

    
    private let topVisibleMessageRange = ValuePromise<ChatTopVisibleMessageRange?>(nil, ignoreRepeated: true)
    private let dismissedPinnedIds = ValuePromise<ChatDismissedPins>(ChatDismissedPins(ids: [], tempMaxId: nil), ignoreRepeated: true)

    private let visibleMessageRange: Atomic<VisibleMessageRange> = Atomic(value: .init(lowerBound: .absoluteLowerBound(), upperBound: nil))

    private var grouppedFloatingPhotos: [([ChatRowItem], ChatFloatingAvatar)] = []
    private var lastFloatingCollectKey: (lower: Int, upper: Int, firstId: MessageId?, lastId: MessageId?)?
    
    private let chatThemeValue: Promise<(ChatTheme?, TelegramPresentationTheme)> = Promise((nil, theme))
    private var presentationEmoticonCache: ChatPresentationCacheEntry?
    private var presentationWallpaperCache: ChatPresentationCacheEntry?
    private let chatThemeTempValue: Promise<(ChatTheme?, TelegramPresentationTheme)?> = Promise(nil)

   
    public var chatInteraction:ChatInteraction
    
    
    var nextTransaction:TransactionHandler = TransactionHandler()
    
    private let _historyReady = Promise<Bool>()
    private var didSetHistoryReady = false

    
    private let _monoforumReady = Promise<Bool>()

    
    private var currentPeerView: PeerView? {
        didSet {
          //  self.reactionManager?.updatePeerView(currentPeerView)
        }
    }

    private func canJoinInaccessibleCommunityChat() -> Bool {
        guard chatInteraction.presentation.isNotAccessible,
              let channel = chatInteraction.peer as? TelegramChannel,
              case .group = channel.info,
              channel.participationStatus == .left,
              let linkedCommunityId = channel.linkedCommunityId,
              let community = currentPeerView?.peers[linkedCommunityId] as? TelegramCommunity,
              community.participationStatus == .member else {
            return false
        }
        return true
    }

    private let location:Promise<ChatHistoryLocationInput> = Promise()
    private let _locationValue:Atomic<ChatHistoryLocationInput?> = Atomic(value: nil)
    private var locationValue:ChatHistoryLocationInput? {
        return _locationValue.with { $0 }
    }

    private func setLocation(_ location: ChatHistoryLocationInput) {
        if let current = self.locationValue, current.chatLocation != location.chatLocation || current.tag != location.tag {
            self.cancelMessageFocus()
        }
        _ = _locationValue.swap(location)
        self.location.set(.single(location))
    }
    
    private func setLocation(_ location: ChatHistoryLocation, chatLocation: ChatLocation? = nil) {
        let chatLocation = chatLocation ?? self.locationValue?.chatLocation
        if let chatLocation {
            let input = ChatHistoryLocationInput(content: location, chatLocation: chatLocation, tag: self.locationValue?.tag, id: self.takeNextHistoryLocationId())
            self.setLocation(input)
        }
    }
    
    //    var content: ChatHistoryLocation

    
    private var chatLocationValue: Signal<ChatLocation, NoError> {
        return self.location.get() |> map { $0.chatLocation }
    }
    

    private var nextHistoryLocationId: Int32 = 1
    private func takeNextHistoryLocationId() -> Int32 {
        let id = self.nextHistoryLocationId
        self.nextHistoryLocationId += 5
        return id
    }

    
    private let maxVisibleIncomingMessageIndex = ValuePromise<MessageIndex>(ignoreRepeated: true)
    private let readHistoryDisposable = MetaDisposable()
    
    private let chatLocationContextHolder: Atomic<ChatLocationContextHolder?>

    
    private let initialDataHandler:Promise<ChatHistoryCombinedInitialData> = Promise()

    let previousView = Atomic<ChatHistoryView?>(value: nil)

    /// Stored on the controller (not a `viewDidLoad` local) so we can null
    /// its contents from `cleanup()` and release the held `Appearance`
    /// immediately. The big `combineLatest → mapToQueue` closure captures
    /// this Atomic; even after `historyDisposable.dispose()`, that closure
    /// can linger briefly on its dispatch queue and keep the Appearance
    /// alive. Setting the Atomic to `nil` in cleanup breaks the chain
    /// independent of when the closure finally deallocates.
    fileprivate let previousAppearance: Atomic<Appearance?> = Atomic(value: nil)
    
    
    private let botCallbackAlertMessage = Promise<(String?, Bool)>((nil, false))
    private var botCallbackAlertMessageDisposable: Disposable?
    
    private var selectTextController:ChatSelectText!
    
    private let visibility = ValuePromise(true, ignoreRepeated: true)
    
    private var contextQueryState: (ChatPresentationInputQuery?, Disposable)?
    private var urlPreviewQueryState: (String?, Disposable)?

    
    let layoutDisposable:MetaDisposable = MetaDisposable()
    
    private var afterNextTransaction:(()->Void)?
    
    private var currentAnimationRows:[TableAnimationInterface.AnimateItem] = []
    
    private var textSendFlight: ChatTextSendFlight?
    private weak var videoRecorderModal: VideoRecorderModalController?

    private let adMessages: ChatAdData?
    
    
    private var liveTranslate: ChatLiveTranslateContext?
    private var stories: PeerExpiringStoryListContext?
    private var themeSelector: ChatThemeSelectorController<Context>? = nil
    
    private let uiState: Atomic<State> = Atomic(value: State())
    private let stateValue: ValuePromise<State> = ValuePromise(ignoreRepeated: true)
        
    
    private var groupsInCommon: GroupsInCommonContext?
    
    private struct State : Equatable {



        var transribe: [MessageId: TranscribeAudioState] = [:]
        var topicCreatorId: PeerId?
        var threadLoading: MessageId?
        var pollAnswers: [MessageId : ChatPollStateData] = [:]
        var mediaRevealed: Set<MessageId> = Set()
        var translate: ChatLiveTranslateContext.State?
        var storyState: PeerExpiringStoryListContext.State?
        var presentation:TelegramPresentationTheme = theme
        var presentation_genuie:TelegramPresentationTheme = theme
        var bespoke_wallpaper: ThemeWallpaper?
        var presentation_emoticon: ChatTheme? = nil
        var factCheck: Set<MessageId> = Set()
        var solutionRevealed: Set<MessageId> = Set()
        
        var quoteRevealed: Set<QuoteMessageIndex> = Set()
        var detailsExpanded: Set<DetailsMessageIndex> = Set()

        var answersAndOnline: ChatTitleCounters = .init()
        
        var codeSyntaxes: [CodeSyntaxKey : CodeSyntaxResult] = [:]
        
        var peerStatus: PeerStatusSettings? = nil
        
        var commonGroups: GroupsInCommonState?
        
        var monoforumState: MonoforumUIState?

        var walletFiatRate: WalletFiatRateProjection?
    }
    private func updateState(_ f:(State)->State) -> Void {
        stateValue.set(uiState.modify(f))
    }

    private func cachedPresentation(_ base: TelegramPresentationTheme, withEmoticonThemes emoticonThemes: [(ChatTheme, TelegramPresentationTheme)]) -> TelegramPresentationTheme {
        return chatPresentation(base, withEmoticonThemes: emoticonThemes, cache: &presentationEmoticonCache)
    }

    private func cachedPresentation(_ base: TelegramPresentationTheme, withWallpaper wallpaper: ThemeWallpaper) -> TelegramPresentationTheme {
        return chatPresentation(base, withWallpaper: wallpaper, cache: &presentationWallpaperCache)
    }

    private let transcribeDisposable = DisposableDict<MessageId>()
    
    private let messageProcessingManager = ChatMessageThrottledProcessingManager()
    private let unsupportedMessageProcessingManager = ChatMessageThrottledProcessingManager()
    private let reactionsMessageProcessingManager = ChatMessageThrottledProcessingManager(submitInterval: 4.0)
    private let messageMentionProcessingManager = ChatMessageThrottledProcessingManager(delay: 0.2, submitInterval: 0.0)
    private let messageReactionsMentionProcessingManager = ChatMessageThrottledProcessingManager(delay: 0.2, submitInterval: 0.0)
    private let refreshStoriesProcessingManager = ChatMessageThrottledProcessingManager()
    private let extendedMediaProcessingManager = ChatMessageVisibleThrottledProcessingManager()
    private let seenLiveLocationProcessingManager = ChatMessageThrottledProcessingManager()
    private let refreshMediaProcessingManager = ChatMessageThrottledProcessingManager()
    private let factCheckProcessingManager = ChatMessageThrottledProcessingManager(submitInterval: 1.0)
    private var readMetricsManager: MessageReadMetricsManager?



    var historyState:ChatHistoryState = ChatHistoryState() {
        didSet {
            assertOnMainThread()
            //if historyState != oldValue {
                genericView.updateScroller(historyState) // updateScroller()
            //}
        }
    }
    
    private func cancelMessageFocus() {
        messageFocusRequestId &+= 1
        focusMessageDisposable.set(nil)
        messageIndexDisposable.set(nil)
        navigationActionDisposable.set(nil)
        dateDisposable.set(nil)
        chatInteraction.loadingMessage.set(.single(false))
    }

    public func clearReplyStack() {
        self.historyState = historyState.withClearReplies()
    }

    public override var navigationController: NavigationViewController? {
        didSet {
            updateSidebar()
        }
    }

    public func scrollUpOrToUnread() {
        self.scrollup()
    }
    
    public override func scrollup(force: Bool = false) -> Void {
        
        assertOnMainThread()
        
        chatInteraction.update({ $0.withUpdatedTempPinnedMaxId(nil) })
        
        self.cancelMessageFocus()
        
        if let reply = historyState.reply() {
            
            chatInteraction.focusMessageId(nil, .init(messageId: reply, string: nil), .CenterEmpty)
            historyState = historyState.withRemovingReplies(max: reply)
        } else {
            let laterId = previousView.with { $0?.originalView?.laterId }
            if laterId != nil {
                
                let history: ChatHistoryLocation = .Scroll(index: MessageHistoryAnchorIndex.upperBound, anchorIndex: MessageHistoryAnchorIndex.upperBound, sourceIndex: MessageHistoryAnchorIndex.upperBound, scrollPosition: .down(!force), count: requestCount, animated: true)
                
                let historyView = preloadedChatHistoryViewForLocation(history, context: context, chatLocation: chatLocation, chatLocationContextHolder: chatLocationContextHolder, tag: locationValue?.tag, additionalData: [])
                

                let signal = historyView
                    |> mapToSignal { historyView -> Signal<Bool, NoError> in
                        switch historyView {
                        case .Loading:
                            return .single(true)
                        case let .HistoryView(view, _, _, _):
                            if !view.holeEarlier, view.laterId == nil, !view.isLoading {
                                return .single(false)
                            }
                            return .single(true)
                        }
                    } |> take(until: { index in
                        return SignalTakeAction(passthrough: !index, complete: !index)
                    })

                messageIndexDisposable.set(showModalProgress(signal: signal, for: context.window).start(next: { [weak self] _ in
                    self?.setLocation(history)
                }, completed: {

                }))
            } else {
                genericView.tableView.scroll(to: .down(!force))
            }

        }
        
    }
    
    private var requestCount: Int {
        return 30
    }
    
    func readyHistory() {
        if !didSetHistoryReady {
            didSetHistoryReady = true
            _historyReady.set(.single(true))
        }
    }
    
    func updateSidebar() {
    }
    
    private func updateFloatingPhotos(_ position: ScrollPosition, animated: Bool, currentAnimationRows: [TableAnimationInterface.AnimateItem] = []) {
        
        let offset = genericView.tableView.clipView.bounds.origin
        
        var floating: [ChatFloatingPhoto] = []
        for groupped in grouppedFloatingPhotos {
            let photoHeight = groupped.1.view?.frame.height ?? ChatFloatingAvatarNode.size.height
            
            let items = groupped.0
            
            
            guard !items.isEmpty else {
                continue
            }
            
            var point: NSPoint = .init(x: groupped.0[0].leftInset, y: 0)


            let ph: CGFloat = 36
            let gap = genericView.floatingPhotosBottomGap
            let inset: CGFloat = 3
            
            var isAnchor: Bool = false
            
            let lastMax: CGFloat = items[items.count - 1].frame.maxY - inset
            let firstMin: CGFloat = items[0].frame.minY + inset
            

            
            if offset.y >= lastMax - ph - gap {
                point.y = lastMax - offset.y - ph
            } else if offset.y + gap > firstMin {
                point.y = gap
                isAnchor = true
            } else {
                point.y = firstMin - offset.y
            }
            
            let revealView = items.lazy.compactMap {
                $0.view as? ChatRowView
            }.first(where: {
                $0.hasRevealState
            })
            
            if let revealView = revealView {
                
                let maxOffset = revealView.frame.maxY - offset.y
                let minOffset = revealView.frame.minY - offset.y

                let rect = NSMakeRect(0, minOffset, revealView.frame.width, maxOffset - minOffset)
                if NSPointInRect(point, rect) {
                    point.x += revealView.containerX
                } else if NSPointInRect(NSMakePoint(point.x, point.y + photoHeight - 1), rect) {
                    point.x += revealView.containerX
                }

            }
            if !isAnchor {
                point = calculateAdjustedPoint(for: point, floatingPhotosView: self.genericView.floatingPhotosView, tableView: self.genericView.tableView)!
            }
            

            var value: ChatFloatingPhoto = .init(point: point, items: groupped.0, photoView: groupped.1.view, isAnchor: isAnchor)
            value.node = groupped.1.node
            floating.append(value)
        }
        
        
        genericView.updateFloating(floating, animated: animated, currentAnimationRows: currentAnimationRows)
    }
    
    private var hasPhotos: Bool = false
    private func updateHasPhotos(_ theme: TelegramPresentationTheme) {
        if let peer = self.chatInteraction.peer {
            let peerAccept = peer.isGroup || peer.isChannel || peer.isSupergroup || peer.id == context.peerId || peer.id == repliesPeerId || mode.isSavedMessagesThread || peer.id == verifyCodePeerId
            self.hasPhotos = peerAccept && theme.bubbled
        } else {
            self.hasPhotos = false
        }
    }
    
    
    #if DEBUG
    func debugRebuildFloatingAvatars() {
        grouppedFloatingPhotos = []
        lastFloatingCollectKey = nil
        genericView.updateFloating([], animated: false)
        collectFloatingPhotos(animated: false, currentAnimationRows: [])
    }
    #endif

    private func collectFloatingPhotos(animated: Bool, currentAnimationRows: [TableAnimationInterface.AnimateItem]) {

        if !hasPhotos {
            self.grouppedFloatingPhotos = []
            self.lastFloatingCollectKey = nil
            return
        }

        let visibleRange = self.genericView.tableView.visibleRows(50)
        let firstItem = visibleRange.length > 0 ? (self.genericView.tableView.item(at: visibleRange.lowerBound) as? ChatRowItem) : nil
        let lastItem = visibleRange.length > 0 ? (self.genericView.tableView.item(at: visibleRange.upperBound - 1) as? ChatRowItem) : nil
        let key: (lower: Int, upper: Int, firstId: MessageId?, lastId: MessageId?) = (visibleRange.lowerBound, visibleRange.upperBound, firstItem?.message?.id, lastItem?.message?.id)
        if let last = lastFloatingCollectKey, last.lower == key.lower, last.upper == key.upper, last.firstId == key.firstId, last.lastId == key.lastId {
            self.updateFloatingPhotos(self.genericView.scroll, animated: animated, currentAnimationRows: currentAnimationRows)
            return
        }
        self.lastFloatingCollectKey = key

        let cached:[MessageId : ChatFloatingAvatar] = self.grouppedFloatingPhotos.reduce(into: [:], { current, value in
            for item in value.0 {
                current[item.message!.id] = value.1
            }
        })
        let previousLastItems: [ObjectIdentifier: ChatRowItem] = self.grouppedFloatingPhotos.reduce(into: [:], { current, value in
            current[ObjectIdentifier(value.1)] = value.0.last
        })
        
        var groupped:[[ChatRowItem]] = []
        var current:[ChatRowItem] = []
        let visibleItems = self.genericView.tableView.visibleRows(50)
        for i in visibleItems.lowerBound ..< visibleItems.upperBound {
            let item = self.genericView.tableView.item(at: i)
            var skipOrFill = true
            if let item = item as? ChatRowItem {
                if item.canHasFloatingPhoto {
                    let prev = current.last
                    let sameAuthor = prev?.lastMessage?.author?.id == item.lastMessage?.author?.id
                    var canGroup = false
                    if sameAuthor {
                        if case .Short = item.itemType {
                            canGroup = true
                        }
                    }
                    if prev == nil || canGroup {
                        skipOrFill = false
                        current.append(item)
                    }
                }
                if skipOrFill {
                    if !current.isEmpty {
                        groupped.append(current)
                    }
                    current = []
                    
                    if item.canHasFloatingPhoto {
                        current.append(item)
                    }
                }
            }
            
        }
        
        if !current.isEmpty {
            groupped.append(current)
        }
        self.grouppedFloatingPhotos = groupped.compactMap { value in
            let item = value[value.count - 1]
            var view: ChatFloatingAvatar?
            for item in value {
                if let v = cached[item.message!.id] {
                    view = v
                    break
                }
            }
            if let current = view, !current.canPresent(item) {
                view = nil
            }
            if view == nil {
                view = ChatFloatingAvatar(item)
                #if DEBUG
                ChatFloatingDebug.creates += 1
                #endif
            } else if let current = view, previousLastItems[ObjectIdentifier(current)] !== item, let peer = item.peer {
                current.setPeer(item: item, peer: peer)
            }
           
            //??
            let control = view
            
            if let control = control {
                return (value, control)
            } else {
                return nil
            }
        }
        
        self.updateFloatingPhotos(self.genericView.scroll, animated: animated, currentAnimationRows: currentAnimationRows)
        
    }
    
    private func updateVisibleRange(_ range: NSRange) -> Void {
        var lowerBound: MessageIndex?
        var upperBound: MessageIndex?
        for i in range.lowerBound ..< range.upperBound {
            let item = genericView.tableView.item(at: i) as? ChatRowItem
            if lowerBound == nil {
                if let message = item?.firstMessage {
                    lowerBound = MessageIndex(message)
                }
            }
            if let message = item?.firstMessage {
                upperBound = MessageIndex(message)
            }
        }
        if let upperBound = upperBound {
            _ = self.visibleMessageRange.swap(.init(lowerBound: upperBound, upperBound: lowerBound))
        }
    }

    public override func viewDidResized(_ size: NSSize) {
        super.viewDidResized(size)
        sizeValue.set(size)
        self.updateFloatingPhotos(genericView.scroll, animated: false)
    }
        
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        self.ableToNextController = { [weak self] controller, f in
            let proceed = { f(controller, true) }
            guard let self else {
                proceed()
                return
            }
            if self.confirmDiscardRecordingIfNeeded(confirmed: proceed) {
                proceed()
            }
        }

        if let contents = mode.customChatContents as? HashtagSearchGlobalChatContents, let hashtag = contents.kind.hashtag {
            contents.hashtagSearchResultsUpdate = { [weak self] result in
                self?.searchState.set(.init(hashtag, result.0.messages))
            }
        }
        
        
        
        genericView.updateFloatingPhotos = { [weak self] scroll, animated in
            self?.updateFloatingPhotos(scroll, animated: animated)
        }

        genericView.inputHeightChanged = { [weak self] rawInputHeight in
            guard let self else { return }
            let bottomInset = self.genericView.bottomInset(forInputHeight: rawInputHeight)
            let previous = self.chatInteraction.bottomInset.swap(bottomInset)
            if previous == bottomInset {
                return
            }
            let table = self.genericView.tableView
            guard let item = table.item(stableId: ChatHistoryEntryId.bottom) as? ChatHistoryBottomRowItem,
                  let index = table.index(of: item) else {
                return
            }

            if let _ = item.view {
                table.noteHeightOfRow(index, true)
                self.collectFloatingPhotos(animated: true, currentAnimationRows: self.currentAnimationRows)
            } else {
                CATransaction.begin()
                let visibleItems = table.visibleItems()
                table.noteHeightOfRow(index, false)
                table.saveScrollState(visibleItems)
                self.collectFloatingPhotos(animated: false, currentAnimationRows: self.currentAnimationRows)
                CATransaction.commit()
            }

        }

        genericView.bubblesView.backHandler = { [weak self] in
            if self?.mode == .preview, (self?.navigationController?.stackCount ?? 0) <= 1 {
                self?.navigationController?.modal?.close()
            } else {
                self?.navigationController?.back()
            }
        }
        genericView.bubblesView.avatarHandler = { [weak self] in
            self?.openPhotoFromHeader()
        }
        genericView.bubblesView.avatarAccessibilityActionName = { [weak self] in
            return self?.headerPhotoAccessibilityActionName
        }
        genericView.bubblesView.titleHandler = { [weak self] in
            self?.openPeerInfoFromHeader()
        }
        genericView.bubblesView.searchHandler = { [weak self] in
            self?.chatInteraction.update { current in
                current.updatedSearchMode(.init(inSearch: !current.searchMode.inSearch))
            }
        }
        genericView.bubblesView.callHandler = { [weak self] in
            guard let self else { return }
            if let groupCall = self.chatInteraction.presentation.groupCall {
                self.chatInteraction.joinGroupCall(groupCall.activeCall, groupCall.joinHash)
            } else {
                self.chatInteraction.call()
            }
        }
        genericView.bubblesView.doneHandler = { [weak self] in
            self?.changeState()
        }
        genericView.bubblesView.menuContextMenu = { [weak self] in
            return self?.buildChatActionsMenu()
        }
        
        keepShortcutDisposable.set(context.engine.accountData.keepShortcutMessageListUpdated().start())
        
        
        sizeValue.set(frame.size)
        self.chatInteraction.add(observer: self)
        
        genericView.inputContextHelper.didScroll = { [weak self] in
            self?.genericView.updateTextInputSuggestions([], range: NSMakeRange(0, 0), animated: true)
        }
        
        genericView.tableView.addScroll(listener: emojiEffects.scrollUpdater)
        

        
        self.genericView.tableView.addScroll(listener: .init(dispatchWhenVisibleRangeUpdated: true, { [weak self] position in
            guard let `self` = self else {
                return
            }
            self.collectFloatingPhotos(animated: false, currentAnimationRows: self.currentAnimationRows)
            
            self.updateVisibleRange(position.visibleRows)
            
        }))
        
        
        self.genericView.tableView.scrollDidUpdate = { [weak self] position in
            self?.updateFloatingPhotos(position, animated: false)
        }
        
        let previousView = self.previousView
        let context = self.context
        let atomicSize = self.atomicSize
        let chatInteraction = self.chatInteraction
        let nextTransaction = self.nextTransaction
        let mode = self.mode
                
        let peerId: PeerId = self.chatInteraction.peerId
        
        let chatLocation:()->ChatLocation = { [weak self] in
            guard let self else {
                return .peer(peerId)
            }
            return self.chatLocation
        }
        
        let makeThreadId64: (Bool)->Int64? = { [weak chatInteraction] forward in
            guard let chatInteraction else {
                return nil
            }
            let chatLocationValue = chatInteraction.chatLocation
            var threadId = chatLocationValue.threadId
            if forward, threadId == nil {
                threadId = chatInteraction.presentation.interfaceState.replyMessage?.threadId
            }
            if threadId == nil, chatInteraction.presentation.threadedBot {
                threadId = Message.newTopicThreadId
            }
            return threadId
        }
        
        let makePeerId:()->PeerId = { [weak self] in
            guard let self else {
                return peerId
            }
            return self.chatInteraction.peerId
        }
        
        let threadId64: ()->Int64? = {
            return makeThreadId64(false)
        }
        let isThread = chatInteraction.mode.isThreadMode
        let customChatContents = chatInteraction.mode.customChatContents

        let takeReplyId:()->EngineMessageReplySubject? = { [weak self] in
            guard let self else {
                return nil
            }
            let presentation = self.chatInteraction.presentation
            var reply = presentation.interfaceState.replyMessageId
            
            if let suggest = presentation.interfaceState.suggestPost {
                switch suggest.mode {
                case let .edit(id), let .suggest(id):
                    reply = .init(messageId: id, quote: nil, innerSubject: nil)
                default:
                    break
                }
            }
            
            if reply == nil, let threadId64 = threadId64(), !presentation.isMonoforum, threadId64 != Message.newTopicThreadId {
                reply = .init(messageId: MessageId(peerId: makePeerId(), namespace: Namespaces.Message.Cloud, id: Int32(clamping: threadId64)), quote: nil, innerSubject: nil)
            }
            return reply
        }
        let takePaidMessageStars:()->StarsAmount? = { [weak self] in
            return self?.chatInteraction.presentation.sendPaidMessageStars
        }
        if case let .thread(message) = self.chatLocation, message.isForumPost {
            if self.keepMessageCountersSyncrhonizedDisposable == nil {
                self.keepMessageCountersSyncrhonizedDisposable = self.context.engine.messages.keepMessageCountersSyncrhonized(peerId: message.peerId, threadId: message.threadId).startStrict()
            }
        } else if self.chatLocation.peerId == self.context.account.peerId {
            if self.keepMessageCountersSyncrhonizedDisposable == nil {
                if let threadId = self.chatLocation.threadId {
                    self.keepMessageCountersSyncrhonizedDisposable = self.context.engine.messages.keepMessageCountersSyncrhonized(peerId: self.context.account.peerId, threadId: threadId).startStrict()
                } else {
                    self.keepMessageCountersSyncrhonizedDisposable = self.context.engine.messages.keepMessageCountersSyncrhonized(peerId: self.context.account.peerId).startStrict()
                }
            }
            if self.keepSavedMessagesSyncrhonizedDisposable == nil {
                self.keepSavedMessagesSyncrhonizedDisposable = self.context.engine.stickers.refreshSavedMessageTags(subPeerId: self.chatLocation.threadId.flatMap(PeerId.init)).startStrict()
            }
        }



        var lastEventTimestamp: Double = 0.0
        self.networkSpeedEventsDisposable = (self.context.account.network.networkSpeedLimitedEvents
        |> deliverOnMainQueue).start(next: { event in

            let timestamp = CFAbsoluteTimeGetCurrent()
            if lastEventTimestamp + 10.0 < timestamp {
                lastEventTimestamp = timestamp
            } else {
                return
            }
            
            let title: String
            let text: String
            switch event {
            case .download:
                let speedIncreaseFactor = context.appConfiguration.getGeneralValue("upload_premium_speedup_download", orElse: 10)
                title = strings().chatDownloadLimitTitle
                text = strings().chatDownloadLimitTextOther(Int(speedIncreaseFactor))
            case .upload:
                let speedIncreaseFactor = context.appConfiguration.getGeneralValue("upload_premium_speedup_upload", orElse: 10)
                title = strings().chatUploadLimitTitle
                text = strings().chatUploadLimitTextOther(Int(speedIncreaseFactor))
            }
            
            showModalText(for: context.window, text: text, title: title, callback: { _ in
                prem(with: PremiumBoardingController(context: context, source: .upload_limit, openFeatures: true), for: context.window)
            })
            
        })


        
        if chatInteraction.peerId.namespace == Namespaces.Peer.CloudChannel {
            slowModeInProgressDisposable.set((context.account.postbox.unsentMessageIdsView() |> mapToSignal { view -> Signal<[MessageId], NoError> in
                return context.account.postbox.messagesAtIds(Array(view.ids)) |> map { messages in
                    return messages.filter { $0.flags.contains(.Unsent) }.map { $0.id }
                }
            } |> deliverOnMainQueue).start(next: { [weak self] ids in
                self?.chatInteraction.update({ $0.updateSlowMode {
                    $0?.withUpdatedSendingIds(ids)
                }})
            }))
        }
        
        
        genericView.tableView.emptyChecker = { [weak self] items in
            
            let hasContent = items.contains(where: { item in
                if let item = item as? ChatRowItem, let message = item.message {
                    if let action = message.extendedMedia as? TelegramMediaAction {
                        switch action.action {
                        case .groupCreated:
                            return coreMessageMainPeer(message)?.groupAccess.isCreator == false
                        case .groupMigratedToChannel:
                            return false
                        case .channelMigratedFromGroup:
                            return false
                        case .photoUpdated:
                            return true
                        default:
                            return true
                        }
                    }
                    return true
                }
                return false
            })
            
            return !hasContent && self?.genericView.state != .progress
        }

        
        genericView.tableView.delegate = self
        
        
        switch chatLocation() {
        case let .peer(peerId):
            self.peerView.set(context.account.viewTracker.peerView(peerId, updateData: true) |> map {Optional($0)})
            let _ = context.engine.peers.checkPeerChatServiceActions(peerId: peerId).start()
        case let .thread(data):
            var peerId: PeerId = data.peerId
            if let threadMode = mode.threadMode {
                switch threadMode {
                case .savedMessages:
                    peerId = PeerId(data.threadId)
                default:
                    break
                }
            }
            self.peerView.set(context.account.viewTracker.peerView(peerId) |> map {Optional($0)})
        }
        
        
        let currentAccountPeer = self.context.account.postbox.loadedPeerWithId(self.context.account.peerId)
        |> map { peer in
            return [SendAsPeer(peer: .init(peer), subscribers: nil, isPremiumRequired: false)]
        }
        
        let supportsSendAs = self.mode.customChatContents == nil

        let signal: Signal<[SendAsPeer]?, NoError> = peerView.get()
        |> map { $0 as? PeerView }
        |> filter { $0?.cachedData != nil }
        |> map { $0! }
        |> map { peerView -> TelegramChannel? in
            if !supportsSendAs {
                return nil
            }
            if let channel = peerViewMainPeer(peerView) as? TelegramChannel {
                if channel.isSupergroup || channel.isGigagroup {
                    if channel.addressName != nil {
                        return channel
                    } else if let cachedData = peerView.cachedData as? CachedChannelData, cachedData.linkedDiscussionPeerId.peerId != nil {
                        return channel
                    }
                } else if case let .broadcast(info) = channel.info {
                    if info.flags.contains(.messagesShouldHaveProfiles), channel.isAdmin {
                        return channel
                    }
                }
            }
            return nil
        } |> distinctUntilChanged |> mapToSignal { channel in
            if let channel = channel {
                return combineLatest(currentAccountPeer, context.engine.peers.sendAsAvailablePeers(peerId: peerId)) |> map { current, peers in
                    var items:[SendAsPeer] = []
                    if !channel.hasPermission(.canBeAnonymous) {
                        items = current
                    }
                    items.append(contentsOf: peers)
                    if items.count == 1, items[0].peer.id == context.peerId {
                        items.removeAll()
                    }
                    return items
                }
            } else {
                return .single(nil)
            }
            
        } |> deliverOnMainQueue

        
        sendAsPeersDisposable.set(signal.start(next: { [weak self] peers in
            guard let strongSelf = self else {
                return
            }
            strongSelf.chatInteraction.update({
                $0.withUpdatedSendAsPeers(peers)
            })
        }))

        

        let layout:Atomic<SplitViewState> = Atomic(value:context.layout)
        layoutDisposable.set(context.layoutValue.start(next: {[weak self] (state) in
            let previous = layout.swap(state)
            if previous != state, let navigation = self?.navigationController {
                if let modalAction = navigation.modalAction {
                    navigation.set(modalAction: modalAction, state != .single)
                }
                DispatchQueue.main.async {
                    self?.genericView.tableView.reloadData()
                    self?.updateBubblesBackButton()
                }
            }
        }))
        
        selectTextController = ChatSelectText(genericView.tableView)
        
        let maxReadIndex:ValuePromise<MessageIndex?> = ValuePromise()
        var didSetReadIndex: Bool = false
        let queue = self.queue
        
        
        let chatLocationContextHolder = self.chatLocationContextHolder
        
        
        
        
        let peerAndData:Signal<(Peer, CachedPeerData?)?, NoError> = peerView.get()
        |> map { value in
            if let value = value as? PeerView, let peer = peerViewMainPeer(value) {
                return (peer, value.cachedData)
            } else {
                return nil
            }
        }
        |> take(until: { value in
            return .init(passthrough: true, complete: value?.1 != nil)
        })

        let historyViewUpdate1 = combineLatest(location.get(), peerAndData |> take(1)) |> deliverOn(queue)
        |> mapToSignal { inputLocation, peerAndData -> Signal<(ChatHistoryViewUpdate, TableSavingSide?, ChatHistoryLocationInput, ChatLocation), NoError> in
            
                let chatLocation = inputLocation.chatLocation
            
                let isNewThread = false
            
//                if let peerAndData, peerAndData.0.botInfo?.flags.contains(.hasForum) == true {
//                    if case .peer = chatLocation {
//                        return .single((.Loading(initialData: .init(), type: .Generic(type: .Generic)), nil, inputLocation, chatLocation))
//                        isNewThread = true
//                    }
//                }
            
            
            
                let location = inputLocation.content

                var additionalData: [AdditionalMessageHistoryViewData] = []
                additionalData.append(.cachedPeerData(peerId))
                additionalData.append(.peerNotificationSettings(peerId))
                additionalData.append(.preferencesEntry(PreferencesKeys.limitsConfiguration))
                additionalData.append(.preferencesEntry(ApplicationSpecificPreferencesKeys.autoplayMedia))
                additionalData.append(.preferencesEntry(ApplicationSpecificPreferencesKeys.automaticMediaDownloadSettings))
                if peerId.namespace == Namespaces.Peer.CloudChannel {
                    additionalData.append(.cacheEntry(cachedChannelAdminRanksEntryId(peerId: peerId)))
                    additionalData.append(.peer(peerId))
                }
                if peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.SecretChat {
                    additionalData.append(.peerIsContact(peerId))
                }
                switch chatLocation {
                case let .thread(data):
                    if mode.isThreadMode {
                        additionalData.append(.message(data.effectiveTopId))
                    }
                case .peer:
                    additionalData.append(.cachedPeerDataMessages(peerId))
                }
            
                let stopHistoryViewUpdates: Signal<Bool, NoError>
                if isNewThread {
                    stopHistoryViewUpdates = Signal<Bool, NoError>.single(false)
                    |> then(
                        context.account.pendingMessageManager.newTopicEvents(peerId: chatLocation.peerId)
                        |> mapToSignal { event -> Signal<Bool, NoError> in
                            if case .willMove(EngineMessage.newTopicThreadId, _) = event {
                                return .single(true)
                            } else {
                                return .never()
                            }
                        }
                        |> take(1)
                    )
                } else {
                    stopHistoryViewUpdates = .single(false)
                }
            
                return stopHistoryViewUpdates |> mapToSignal { value in
                    if !value {
                        return chatHistoryViewForLocation(location, context: context, chatLocation: chatLocation, fixedCombinedReadStates: { nil }, tag: inputLocation.tag, mode: mode, additionalData: additionalData, chatLocationContextHolder: chatLocationContextHolder) |> beforeNext { viewUpdate in
                            switch viewUpdate {
                            case let .HistoryView(view, _, _, _):
                                if !didSetReadIndex {
                                    if let index = view.maxReadIndex {
                                        if let last = view.entries.last {
                                            if index.id >= last.index.id {
                                                maxReadIndex.set(nil)
                                            } else {
                                                maxReadIndex.set(index)
                                            }
                                        } else {
                                            maxReadIndex.set(index)
                                        }
                                    } else {
                                        maxReadIndex.set(view.maxReadIndex)
                                    }
                                    didSetReadIndex = true
                                }
                            default:
                                maxReadIndex.set(nil)
                            }
                        } |> mapToSignal { view in
                            return .single((view, location.side, inputLocation, chatLocation))
                        }
                    } else {
                        return .never()
                    }
                }
                 
        }
        
        
        
        let historyViewUpdateId = Atomic<Int>(value: 0)
        let historyViewUpdate = historyViewUpdate1 |> map { update in
            let id = historyViewUpdateId.modify { $0 &+ 1 }
            return (update.0, update.1, update.2, update.3, id)
        }


        
        let animatedEmojiStickers: Signal<[String: StickerPackItem], NoError> = context.diceCache.animatedEmojies
        // Use the process-wide cache on `context.reactions` instead of
        // re-running the postbox transaction + Codable+FlatBuffer decode
        // (~15-20ms in release, ~85ms in debug) on every chat-open. The
        // cache emits `.single(nil)` until the catalogue first decodes,
        // then the cached value for every subsequent open.
        let cachedMessageEffects: AvailableMessageEffects? = context.reactions.availableMessageEffects
        let messageEffects: Signal<AvailableMessageEffects?, NoError> = .single(cachedMessageEffects) |> then(context.reactions.messageEffectsValue)

        
        let savedMessageTags: Signal<SavedMessageTags?, NoError>
        if peerId == self.context.account.peerId {
            savedMessageTags = context.engine.stickers.savedMessageTagData()
        } else {
            savedMessageTags = .single(nil)
        }

        
        let reactions = context.reactions.stateValue

        
        let customChannelDiscussionReadState: Signal<MessageId?, NoError>
        if case let .peer(peerId) = chatLocation(), peerId.namespace == Namespaces.Peer.CloudChannel {
            let cachedDataKey = PostboxViewKey.cachedPeerData(peerId: peerId)
            let peerKey = PostboxViewKey.basicPeer(peerId)
            customChannelDiscussionReadState = context.account.postbox.combinedView(keys: [cachedDataKey, peerKey])
                |> mapToSignal { views -> Signal<PeerId?, NoError> in
                    guard let view = views.views[cachedDataKey] as? CachedPeerDataView else {
                        return .single(nil)
                    }
                    guard let peer = (views.views[peerKey] as? BasicPeerView)?.peer as? TelegramChannel, case .broadcast = peer.info else {
                        return .single(nil)
                    }
                    guard let cachedData = view.cachedPeerData as? CachedChannelData else {
                        return .single(nil)
                    }
                    guard case let .known(value) = cachedData.linkedDiscussionPeerId else {
                        return .single(nil)
                    }
                    return .single(value)
                }
                |> distinctUntilChanged
                |> mapToSignal { discussionPeerId -> Signal<MessageId?, NoError> in
                    guard let discussionPeerId = discussionPeerId else {
                        return .single(nil)
                    }
                    let key = PostboxViewKey.combinedReadState(peerId: discussionPeerId, handleThreads: false)
                    return context.account.postbox.combinedView(keys: [key])
                        |> map { views -> MessageId? in
                            guard let view = views.views[key] as? CombinedReadStateView else {
                                return nil
                            }
                            guard let state = view.state else {
                                return nil
                            }
                            for (namespace, namespaceState) in state.states {
                                if namespace == Namespaces.Message.Cloud {
                                    switch namespaceState {
                                    case let .idBased(maxIncomingReadId, _, _, _, _):
                                        return MessageId(peerId: discussionPeerId, namespace: Namespaces.Message.Cloud, id: maxIncomingReadId)
                                    default:
                                        break
                                    }
                                }
                            }
                            return nil
                        }
                        |> distinctUntilChanged
            }
        } else {
            customChannelDiscussionReadState = .single(nil)
        }
        
        
        
        let customThreadOutgoingReadState: Signal<MessageId?, NoError> = chatLocationValue |> distinctUntilChanged |> mapToSignal { location in
            switch location {
            case .thread:
                return context.chatLocationOutgoingReadState(for: location, contextHolder: chatLocationContextHolder)
            case .peer:
                return .single(nil)
            }
        }
//        if case .thread = chatLocation {
//            customThreadOutgoingReadState =
//        } else {
//            customThreadOutgoingReadState = .single(nil)
//        }

        let animatedRows:([TableAnimationInterface.AnimateItem])->Void = { [weak self] items in
            self?.currentAnimationRows = items
        }
        
        // Use the stored `self.previousAppearance` instead of a fresh local
        // Atomic. Seed it with the current appearance.
        let previousAppearance = self.previousAppearance
        _ = previousAppearance.swap(appAppearance)
        let firstInitialUpdate:Atomic<Bool> = Atomic(value: true)
                
        let applyHole:(ChatHistoryLocationInput) -> Void = { [weak self] current in
            guard let `self` = self else { return }
            let locationValue = self.locationValue
            if current != locationValue {
                return
            }
            let visibleRows = self.genericView.tableView.visibleRows()
            var messageIndex: MessageIndex?
            for i in stride(from: visibleRows.max - 1, to: -1, by: -1) {
                if let item = self.genericView.tableView.item(at: i) as? ChatRowItem, !item.ignoreAtInitialization, let message = item.message, message.adAttribute == nil {
                    messageIndex = MessageIndex(message)
                    break
                }
            }
            if let messageIndex = messageIndex {
                self.setLocation(.Navigation(index: MessageHistoryAnchorIndex.message(messageIndex), anchorIndex: MessageHistoryAnchorIndex.message(messageIndex), count: self.requestCount, side: .upper))
            } else if let location = self.locationValue {
                self.setLocation(location.content)
            }
        }
        
        let _searchState: Atomic<SearchMessagesResultState> = Atomic(value: SearchMessagesResultState("", []))
        
        let updatingMedia = context.account.pendingUpdateMessageManager.updatingMessageMedia
            |> map { value -> [MessageId: ChatUpdatingMessageMedia] in
                var result = value
                for id in value.keys {
                    if id.peerId != peerId {
                        result.removeValue(forKey: id)
                    }
                }
                return result
            }
            |> distinctUntilChanged
        
        let previousUpdatingMedia = Atomic<[MessageId: ChatUpdatingMessageMedia]?>(value: nil)
        
        
        let adMessages:Signal<(fixed: Message?, opportunistic: [Message], version: Int), NoError>
        if let ad = self.adMessages {
            adMessages = ad.allMessages
        } else {
            adMessages = .single((nil, [], 0))
        }
        
        
        
        
        let themeEmoticon: Signal<ChatTheme?, NoError> = self.peerView.get() |> map {
            ($0 as? PeerView)?.cachedData
        } |> map { cachedData in
            var chatTheme: ChatTheme? = nil
            if let cachedData = cachedData as? CachedUserData {
                chatTheme = cachedData.chatTheme
            } else if let cachedData = cachedData as? CachedGroupData {
                chatTheme = cachedData.chatTheme
            } else if let cachedData = cachedData as? CachedChannelData {
                chatTheme = cachedData.chatTheme
            }
            return chatTheme
        } |> distinctUntilChanged
        
        
        
        var uploadingPeerMedia = context.account.pendingPeerMediaUploadManager.uploadingPeerMedia
        uploadingPeerMedia = .single([:]) |> then(uploadingPeerMedia)
        
        
        let wallpaper: Signal<WallpaperTuple, NoError> = combineLatest(uploadingPeerMedia, self.peerView.get(), appearanceSignal) |> map { uploading, peerView, appearance in
            if let content = uploading[peerId]?.content {
                switch content {
                case let .wallpaper(wallpaper, _):
                    return WallpaperTuple(wallpaper.uiWallpaper(), appearance)
                }
            }
            if let peerView = peerView as? PeerView {
                
                var wallpaper: TelegramWallpaper?
                var chatTheme: ChatTheme?
                
                if let data = peerView.cachedData as? CachedUserData {
                    wallpaper = data.wallpaper
                    chatTheme = data.chatTheme
                } else if let data = peerView.cachedData as? CachedChannelData {
                    wallpaper = data.wallpaper
                    chatTheme = data.chatTheme
                }
                if let wallpaper {
                    return WallpaperTuple(wallpaper.uiWallpaper(), appearance)
                } else if let chatTheme {
                    switch chatTheme {
                    case let .gift(gift, settings):
                        let setting = settings.first(where: { $0.baseTheme.palette.isDark == appearance.presentation.colors.isDark })
                        switch gift {
                        case let .unique(unique):
                            return WallpaperTuple(setting?.wallpaper?.uiWallpaper(unique), appearance)
                        default:
                            break
                        }
                    default:
                        break
                    }
                }
            }
            return WallpaperTuple(nil, appearance)
        } |> distinctUntilChanged
        
        
        let chatTheme:Signal<(ChatTheme?, TelegramPresentationTheme), NoError> = combineLatest(context.chatThemes, themeEmoticon, appearanceSignal) |> map { chatThemes, chatTheme, appearance -> (ChatTheme?, TelegramPresentationTheme) in
            
            var theme: TelegramPresentationTheme = appearance.presentation
            if let chatTheme = chatTheme {
                switch chatTheme {
                case .emoticon:
                    let chatThemeData = chatThemes.first(where: { $0.0 == chatTheme})?.1
                    theme = chatThemeData ?? appearance.presentation
                case let .gift(gift, settings):
                    let setting = settings.first(where: { $0.baseTheme.palette.isDark == appearance.presentation.colors.isDark })
                    if let unique = gift.unique, let setting, let wallpaper = setting.wallpaper {
                        theme = theme.withUpdatedWallpaper(ThemeWallpaper(wallpaper: wallpaper.uiWallpaper(unique), associated: nil)).withUpdatedColors(setting.palette)
                    }
                }
            }
            return (chatTheme, theme)
        }

        
        let themeWallpaper: Signal<WallpaperResult, NoError> = wallpaper |> mapToSignal { value in
            let wallpaper = value.wallpaper
            let appearance = value.appearance
            
            if let wallpaper = wallpaper {
                if backgroundExists(wallpaper, palette: appearance.presentation.colors) {
                    return .single(.result(wallpaper))
                } else {
                    return .single(.loading) |> then(moveWallpaperToCache(postbox: context.account.postbox, wallpaper: wallpaper) |> map {
                        .result($0)
                    })
                }
            }
            return .single(.result(nil))
        }
        |> distinctUntilChanged
        |> deliverOnMainQueue
        
                
        
        
        let effectiveTheme: Signal<ThemeTuple, NoError> = combineLatest(chatTheme, chatThemeTempValue.get()) |> map { genuie, temp in
            if let temp = temp {
                return .init(theme: temp.1, emoticon: temp.0, genuie: genuie.1, temp: true)
            } else {
                return .init(theme: genuie.1, emoticon: genuie.0, genuie: genuie.1, temp: false)
            }
        }
        |> distinctUntilChanged
        |> deliverOnMainQueue
        
        let appearanceReady: ValuePromise<Bool> = ValuePromise(ignoreRepeated: true)
        
        if chatLocation().peerId.namespace != Namespaces.Peer.SecretChat, chatLocation().peerId != context.peerId, mode != .pinned, mode != .scheduled {
            self.liveTranslate = .init(peerId: chatLocation().peerId, context: context)
        } else {
            self.liveTranslate = nil
        }
        

        
        let translateSignal: Signal<ChatLiveTranslateContext.State?, NoError>
        if let liveTranslate = self.liveTranslate {
            translateSignal = liveTranslate.state
            |> map(Optional.init)

            liveTranslateDisposable.set((liveTranslate.summarizeCompleted |> deliverOnMainQueue).start(next: { [weak self] messageId in
                self?.chatInteraction.focusMessageId(nil, .init(messageId: messageId, string: nil), .top(id: 0, innerId: nil, animated: true, focus: .init(focus: false), inset: self?.genericView.headerState.height ?? 10))
            }))
        } else {
            translateSignal = .single(nil)
        }
        
                
        if chatLocation().peerId.namespace == Namespaces.Peer.CloudUser || chatLocation().peerId.namespace == Namespaces.Peer.CloudChannel, chatLocation().peerId != context.peerId, mode == .history {
            self.stories = PeerExpiringStoryListContext(account: context.account, peerId: peerId)
        } else {
            self.stories = nil
        }
        
        let storiesSignal: Signal<PeerExpiringStoryListContext.State?, NoError>
        if let stories = self.stories {
            storiesSignal = .single(nil) |> then(stories.state |> map(Optional.init))
        } else {
            storiesSignal = .single(nil)
        }
        
        let recommendedChannels: Signal<RecommendedChannels?, NoError>
        if peerId.namespace == Namespaces.Peer.CloudChannel {
            recommendedChannels = context.engine.peers.recommendedChannels(peerId: peerId)
        } else {
            recommendedChannels = .single(nil)
        }
        
        
        let onlineCounterMode: Signal<Int, NoError> = peerView.get() |> map { view -> Int in
            guard let peerView = view as? PeerView, let peer = peerViewMainPeer(peerView), peer.isSupergroup || peer.isGigagroup, let cachedData = peerView.cachedData as? CachedChannelData else {
                return 0
            }
            return (cachedData.participantsSummary.memberCount ?? 0) > 200 ? 2 : 1
        } |> distinctUntilChanged
        
        let counters: Signal<ChatTitleCounters, NoError> = combineLatest(onlineCounterMode, self.chatLocationValue) |> mapToSignal { onlineCounterMode, chatLocation in
            let threadId = chatLocation.threadId
            
            let answersCount: Signal<Int32?, NoError>
            let onlineMemberCount:Signal<Int32?, NoError>

            
            if let threadId {
                switch chatLocation {
                case let .thread(data):
                    if mode.isSavedMessagesThread || data.isMonoforumPost {
                        let savedMessagesPeerId: PeerId = PeerId(data.threadId)
                        
                        let threadPeerId = savedMessagesPeerId
                        let basicPeerKey: PostboxViewKey = .basicPeer(threadPeerId)
                        let countViewKey: PostboxViewKey = .historyTagSummaryView(tag: MessageTags(), peerId: peerId, threadId: savedMessagesPeerId.toInt64(), namespace: Namespaces.Message.Cloud, customTag: nil)
                        answersCount = context.account.postbox.combinedView(keys: [basicPeerKey, countViewKey])
                        |> map { views -> Int32? in
                            
                            var messageCount = 0
                            if let summaryView = views.views[countViewKey] as? MessageHistoryTagSummaryView, let count = summaryView.count {
                                messageCount += Int(count)
                            }
                            
                            return Int32(messageCount)
                        }

                    } else if isThread {
                        answersCount = context.account.postbox.messageView(data.effectiveTopId)
                            |> map {
                                $0.message?.attributes.compactMap { $0 as? ReplyThreadMessageAttribute }.first
                            }
                            |> map {
                                $0?.count
                            }
                            |> deliverOnMainQueue
                    } else {
                        let countViewKey: PostboxViewKey = .historyTagSummaryView(tag: MessageTags(), peerId: peerId, threadId: threadId, namespace: Namespaces.Message.Cloud, customTag: nil)
                        let localCountViewKey: PostboxViewKey = .historyTagSummaryView(tag: MessageTags(), peerId: peerId, threadId: threadId, namespace: Namespaces.Message.Local, customTag: nil)
                        
                        answersCount = context.account.postbox.combinedView(keys: [countViewKey, localCountViewKey])
                        |> map { views -> Int32 in
                            var messageCount = 0
                            if let summaryView = views.views[countViewKey] as? MessageHistoryTagSummaryView, let count = summaryView.count {
                                if threadId == 1 {
                                    messageCount += Int(count)
                                } else {
                                    messageCount += max(Int(count) - 1, 0)
                                }
                            }
                            if let summaryView = views.views[localCountViewKey] as? MessageHistoryTagSummaryView, let count = summaryView.count {
                                messageCount += Int(count)
                            }
                            return Int32(messageCount)
                        } |> map(Optional.init) |> deliverOnMainQueue
                    }
                default:
                    answersCount = .single(nil)
                }
            } else {
                answersCount = .single(nil)
            }
            
            
            switch onlineCounterMode {
            case 2:
                onlineMemberCount = context.peerChannelMemberCategoriesContextsManager.recentOnline(peerId: peerId)  |> map(Optional.init) |> deliverOnMainQueue
            case 1:
                onlineMemberCount = context.peerChannelMemberCategoriesContextsManager.recentOnlineSmall(peerId: peerId)  |> map(Optional.init) |> deliverOnMainQueue
            default:
                onlineMemberCount = .single(nil)
            }
            
            return combineLatest(answersCount, onlineMemberCount) |> map {
                return .init(replies: $0, online: $1)
            }
        } |> deliverOnMainQueue
        
        
        
        let groupsInCommon = GroupsInCommonContext(account: context.account, peerId: peerId)
        self.groupsInCommon = groupsInCommon
        
        let monoforumTopics: Promise<[EngineChatList.Item]?> = Promise()

      
        presentationDisposable.add(combineLatest(queue:.mainQueue(), effectiveTheme, themeWallpaper, translateSignal, storiesSignal, context.chatThemes, counters, context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.PeerSettings(id: peerId)), Signal<GroupsInCommonState?, NoError>.single(nil) |> then(groupsInCommon.state |> map(Optional.init)), monoforumTopics.get() |> take(1)).start(next: { [weak self] presentation, wallpaper, translate, storyState, emoticonThemes, counters, peerStatus, groupsInCommon, monoforumTopics in
            let emoticon = presentation.emoticon
            let theme = presentation.theme
            let genuie = presentation.genuie
            self?.updateState { current in
                var current = current
                current.presentation_emoticon = emoticon
                current.presentation_genuie = genuie
                current.translate = translate
                current.storyState = storyState
                current.answersAndOnline = counters
                current.peerStatus = peerStatus
                current.commonGroups = groupsInCommon
                current.monoforumState = monoforumTopics != nil ? FastSettings.monoforumState(peerId) : nil
                switch wallpaper {
                case let .result(result):
                    current.presentation = self?.cachedPresentation(theme, withEmoticonThemes: emoticonThemes) ?? theme.withUpdatedEmoticonThemes(emoticonThemes)
                    if let wallpaper = result, !presentation.temp {
                        current.bespoke_wallpaper = .init(wallpaper: wallpaper, associated: nil)
                    } else {
                        current.bespoke_wallpaper = current.presentation.wallpaper
                    }
                    if current.presentation.wallpaper != current.bespoke_wallpaper {
                        if let wallpaper = current.bespoke_wallpaper {
                            current.presentation = self?.cachedPresentation(current.presentation, withWallpaper: wallpaper) ?? current.presentation.withUpdatedWallpaper(wallpaper)
                        } else {
                            current.presentation = self?.cachedPresentation(current.presentation, withWallpaper: theme.wallpaper) ?? current.presentation.withUpdatedWallpaper(theme.wallpaper)
                        }
                    }
                case .loading:
                    break
                }
                return current
            }
            
            let presentation = self?.uiState.with { ($0.presentation_emoticon, $0.presentation )}
            if let presentation = presentation {
                self?.chatThemeValue.set(.single(presentation))
            }
            appearanceReady.set(true)
            if let state = translate {
                self?.chatInteraction.update({ current in
                    return current.withUpdatedTranslateState(.init(canTranslate: state.canTranslate, translate: state.translate, from: state.from, to: state.to, paywall: state.paywall, tone: state.tone, result: state.result))
                })
                self?.genericView.tableView.notifyScrollHandlers()
            }
        }))
        
        
        
       
        if #available(macOS 10.15, *), let walletContext = ChatHistoryUIHooks.shared.walletHooks.walletContext(context) {
            presentationDisposable.add((walletContext.chatFiatRateState
            |> deliverOnMainQueue).start(next: { [weak self] rate in
                self?.updateState { current in
                    var current = current
                    current.walletFiatRate = rate.map { WalletFiatRateProjection(unitsPerGram: $0.unitsPerGram, currencySymbol: $0.currencySymbol) }
                    return current
                }
            }))
        }

        let historyUiState: Signal<State, NoError> = stateValue.get() |> distinctUntilChanged(isEqual: { lhs, rhs in
            return lhs.transribe == rhs.transribe &&
                lhs.topicCreatorId == rhs.topicCreatorId &&
                lhs.threadLoading == rhs.threadLoading &&
                lhs.pollAnswers == rhs.pollAnswers &&
                lhs.mediaRevealed == rhs.mediaRevealed &&
                lhs.translate?.canTranslate == rhs.translate?.canTranslate &&
                lhs.translate?.translate == rhs.translate?.translate &&
                lhs.translate?.to == rhs.translate?.to &&
                lhs.translate?.result == rhs.translate?.result &&
                lhs.translate?.transcriptionResult == rhs.translate?.transcriptionResult &&
                lhs.translate?.summarizeResult == rhs.translate?.summarizeResult &&
                lhs.storyState?.maxReadId == rhs.storyState?.maxReadId &&
                lhs.presentation == rhs.presentation &&
                lhs.factCheck == rhs.factCheck &&
                lhs.solutionRevealed == rhs.solutionRevealed &&
                lhs.quoteRevealed == rhs.quoteRevealed &&
                lhs.detailsExpanded == rhs.detailsExpanded &&
                lhs.codeSyntaxes == rhs.codeSyntaxes &&
                lhs.peerStatus == rhs.peerStatus &&
                (lhs.commonGroups == rhs.commonGroups || lhs.peerStatus?.phoneCountry == nil) &&
                lhs.monoforumState == rhs.monoforumState &&
                lhs.walletFiatRate == rhs.walletFiatRate
        })
        
        let historyPeerView: Signal<PostboxView?, NoError> = peerView.get() |> distinctUntilChanged(isEqual: { lhs, rhs in
            let lhsView = lhs as? PeerView
            let rhsView = rhs as? PeerView
            guard let lhsView, let rhsView else {
                return lhsView == nil && rhsView == nil
            }
            let lhsPeer = peerViewMainPeer(lhsView)
            let rhsPeer = peerViewMainPeer(rhsView)
            if let lhsPeer, let rhsPeer {
                if !lhsPeer.isEqual(rhsPeer) {
                    return false
                }
            } else if (lhsPeer == nil) != (rhsPeer == nil) {
                return false
            }
            if let lhsData = lhsView.cachedData, let rhsData = rhsView.cachedData {
                return lhsData.isEqual(to: rhsData)
            }
            return (lhsView.cachedData == nil) == (rhsView.cachedData == nil)
        })

        let previousHistoryViewUpdateId = Atomic<Int?>(value: nil)
        let historyViewTransition = combineLatest(queue: queue,
                                                  historyViewUpdate,
                                                  appearanceSignal,
                                                  maxReadIndex.get(),
                                                  searchState.get(),
                                                  animatedEmojiStickers,
                                                  messageEffects,
                                                  savedMessageTags,
                                                  customChannelDiscussionReadState,
                                                  customThreadOutgoingReadState,
                                                  updatingMedia,
                                                  adMessages,
                                                  reactions,
                                                  historyUiState,
                                                  historyPeerView,
                                                  recommendedChannels
    ) |> mapToQueue { update, appearance, maxReadIndex, searchState, animatedEmojiStickers, messageEffects, savedMessageTags, customChannelDiscussionReadState, customThreadOutgoingReadState, updatingMedia, adMessages, reactions, uiState, peerView, recommendedChannels -> Signal<(TableUpdateTransition, MessageHistoryView?, ChatHistoryCombinedInitialData, Bool, ChatHistoryView), NoError> in
                                    
            let pollAnswersLoading = uiState.pollAnswers
            let threadLoading = uiState.threadLoading
            let chatLocation = update.3
            let chatTheme = uiState.presentation
            let searchStateUpdated = _searchState.swap(searchState) != searchState
            
            let isNewHistoryViewUpdate = previousHistoryViewUpdateId.swap(update.4) != update.4
            let isLoading: Bool
            let view: MessageHistoryView?
            let initialData: ChatHistoryCombinedInitialData
            var updateType: ChatHistoryViewUpdateType
            let scrollPosition: ChatHistoryViewScrollPosition?
            switch update.0 {
            case let .Loading(data, ut):
                view = nil
                initialData = data
                isLoading = true
                updateType = isNewHistoryViewUpdate ? ut : .Generic(type: .Generic)
                scrollPosition = nil
            case let .HistoryView(_view, _type, _scrollPosition, _initialData):
                initialData = _initialData
                view = _view
                isLoading = _view.isLoading
                updateType = isNewHistoryViewUpdate ? _type : .Generic(type: .Generic)
                scrollPosition = searchStateUpdated || !isNewHistoryViewUpdate ? nil : _scrollPosition

            }
    
            if let updatedValue = previousUpdatingMedia.swap(updatingMedia), updatingMedia != updatedValue {
                updateType = .Generic(type: .Generic)
            }
            
            switch updateType {
            case let .Generic(type: type):
                switch type {
                case .FillHole:
                    DispatchQueue.main.async {
                        applyHole(update.2)
                    }
                    return .complete()
                default:
                    break
                }
            default:
                break
            }
            
            
            // The stored Atomic is `Appearance?`; the only time it's nil is
            // after `cleanup()` nulled it (controller is being torn down).
            // Fall back to `appearance` itself in that case — comparing
            // against the just-emitted value yields no theme change, which
            // is the correct behaviour during shutdown.
            let pAppearance = previousAppearance.swap(appearance) ?? appearance
            var prepareOnMainQueue = pAppearance.presentation != appearance.presentation
            switch updateType {
            case .Initial:
                prepareOnMainQueue = firstInitialUpdate.swap(isLoading) || prepareOnMainQueue
            default:
                break
            }
            
            let animationInterface: TableAnimationInterface = TableAnimationInterface(nextTransaction.isExutable && view?.laterId == nil, true, animatedRows)
            let timeDifference = context.timeDifference
            let bigEmojiEnabled = context.sharedContext.baseSettings.bigEmoji

            
            var ranks: CachedChannelAdminRanks?
            if let view = view {
                for additionalEntry in view.additionalData {
                    if case let .cacheEntry(id, data) = additionalEntry {
                        if id == cachedChannelAdminRanksEntryId(peerId: peerId), let data = data?.get(CachedChannelAdminRanks.self)  {
                            ranks = data
                            self.currentRanks = data
                        }
                        break
                    }
                }
            }
           
            
            let proccesedView:ChatHistoryView
            if let view = view {
                if let peerView = peerView as? PeerView, let peer = peerView.peers[peerView.peerId], peer.isRestrictedChannel(context.contentSettings) {
                    proccesedView = ChatHistoryView(originalView: view, filteredEntries: [], theme: chatTheme)
                } else {
                    let msgEntries = view.entries
                    
                    let topMessages: [Message]?
                    switch chatLocation {
                    case let .thread(data):
                        if mode.isThreadMode {
                            if view.earlierId == nil, !view.isLoading, !view.holeEarlier {
                                topMessages = initialData.cachedDataMessages?[data.effectiveTopId]
                            } else {
                                topMessages = nil
                            }
                        } else {
                            topMessages = nil
                        }
                    case .peer:
                        topMessages = nil
                    }
                    
                    var ads:(fixed: Message?, opportunistic: [Message]) = (fixed: nil, opportunistic: [])
                   
                    
                    let peerView = (peerView as? PeerView)
                    let peer = peerView != nil ? peerViewMainPeer(peerView!) : nil
                    
                    //,
                    if !view.isLoading && view.laterId == nil, peer?.isChannel == true {
                        ads = (fixed: adMessages.fixed, opportunistic: adMessages.opportunistic)
                    }
                    
                    let includeJoin: Bool
                    switch mode {
                    case .history:
                        includeJoin = true
                    default:
                        includeJoin = false
                    }
                    
                    let entries = messageEntries(msgEntries, location: chatLocation, maxReadIndex: view.isAnchorOnlyWhileLoading ? nil : maxReadIndex, dayGrouping: customChatContents == nil, renderType: chatTheme.bubbled ? .bubble : .list, includeBottom: true, timeDifference: timeDifference, ranks: ranks, pollAnswersLoading: pollAnswersLoading, threadLoading: threadLoading, groupingPhotos: true, autoplayMedia: initialData.autoplayMedia, searchState: searchState, animatedEmojiStickers: bigEmojiEnabled ? animatedEmojiStickers : [:], topFixedMessages: topMessages, customChannelDiscussionReadState: customChannelDiscussionReadState, customThreadOutgoingReadState: customThreadOutgoingReadState, addRepliesHeader: peerId == repliesPeerId && view.earlierId == nil, addWelcomeMessagesHeader: customChatContents?.kind == .welcomeMessages, updatingMedia: updatingMedia, adMessage: ads.fixed, dynamicAdMessages: ads.opportunistic, chatTheme: chatTheme, reactions: reactions, transribeState: uiState.transribe, topicCreatorId: uiState.topicCreatorId, mediaRevealed: uiState.mediaRevealed, translate: uiState.translate, storyState: uiState.storyState, peerStoryStats: view.peerStoryStats, cachedData: peerView?.cachedData, peer: peer, holeLater: view.holeLater, holeEarlier: view.holeEarlier, recommendedChannels: recommendedChannels, includeJoin: includeJoin, earlierId: view.earlierId, laterId: view.laterId, automaticDownload: initialData.autodownloadSettings, savedMessageTags: savedMessageTags, contentSettings: context.contentSettings, codeSyntaxData: uiState.codeSyntaxes, messageEffects: messageEffects, factCheckRevealed: uiState.factCheck, solutionRevealed: uiState.solutionRevealed, quoteRevealed: uiState.quoteRevealed, detailsExpanded: uiState.detailsExpanded, peerStatus: uiState.peerStatus, commonGroups: uiState.commonGroups, monoforumState: uiState.monoforumState, accountPeerId: context.peerId, contentConfig: context.contentConfig, walletFiatRate: uiState.walletFiatRate).map { ChatWrappedEntry(appearance: AppearanceWrapperEntry(entry: $0, appearance: appearance), tag: view.tag) }
                    proccesedView = ChatHistoryView(originalView: view, filteredEntries: entries, theme: chatTheme)
                }
            } else {
                proccesedView = ChatHistoryView(originalView: nil, filteredEntries: [], theme: chatTheme)
            }

            return prepareEntries(from: previousView.swap(proccesedView), to: proccesedView, timeDifference: timeDifference, initialSize: atomicSize.with { $0 }, interaction: chatInteraction, animated: false, scrollPosition:scrollPosition, reason: updateType, animationInterface: animationInterface, side: update.1, messagesViewQueue: queue) |> map { transition in
                return (transition, view, initialData, isLoading, proccesedView)
            } |> runOn(prepareOnMainQueue ? Queue.mainQueue(): queue)
            
        } |> deliverOnMainQueue
        
        
        let appliedTransition = historyViewTransition |> map { [weak self] transition, view, initialData, isLoading, proccesedView in
            self?.applyTransition(transition, initialData: initialData, isLoading: isLoading, processedView: proccesedView)
        }
        
        
        self.historyDisposable.set(appliedTransition.start())
        
        var canRead: Signal<Bool, NoError>
        if let isLocked = ChatUIHooks.shared.appIsLocked() {
            canRead = isLocked
            |> map { !$0 }
        } else {
            canRead = .single(true)
        }
        canRead = combineLatest(canRead, self.isKeyWindow.get()) |> map { $0 && $1 }

        self.interactiveReadStateDisposable.set((canRead |> distinctUntilChanged |> deliverOnMainQueue).start(next: { [weak self] canRead in
            guard let self else { return }
            self.interactiveReadEnabled = canRead
            self.updateInteractiveReading()
            if canRead {
                self.genericView.tableView.notifyScrollHandlers()
            }
        }))
        
        
        let previousMaxIncomingMessageIdByNamespace = Atomic<[MessageId.Namespace: MessageIndex]>(value: [:])
        
        let readHistory = combineLatest(self.maxVisibleIncomingMessageIndex.get(), canRead, self.chatLocationValue |> distinctUntilChanged, self.peerView.get())
            |> deliverOnMainQueue
            |> map { messageIndex, canRead, chatLocation, view in
                let peer = (view as? PeerView)?.peers[chatLocation.peerId]
                guard chatHistoryKeepsReadState(peer: peer, chatLocation: chatLocation) else {
                    let _ = previousMaxIncomingMessageIdByNamespace.swap([:])
                    return
                }
                if canRead && !hasModals(context.window) {
                    var apply = false
                    let _ = previousMaxIncomingMessageIdByNamespace.modify { dict in
                        let previousIndex = dict[messageIndex.id.namespace]
                        if previousIndex == nil || previousIndex! < messageIndex {
                            apply = true
                            var dict = dict
                            dict[messageIndex.id.namespace] = messageIndex
                            return dict
                        }
                        return dict
                    }
                    if apply {
                        ChatUIHooks.shared.clearNotifies(chatLocation.peerId, messageIndex.id)
                        context.applyMaxReadIndex(for: chatLocation, contextHolder: chatLocationContextHolder, messageIndex: messageIndex)
                    }
                }
        }
        
        self.readHistoryDisposable.set(readHistory.start())
        
        
        chatInteraction.updateFrame = { [weak self] frame, transition in
//            self?.reactionManager?.updateLayout(size: frame.size, transition: transition)
            if let tableView = self?.genericView.tableView {
                self?.updateFloatingPhotos(tableView.scrollPosition().current, animated: transition.isAnimated)
            }
        }
        
        chatInteraction.setupReplyMessage = { [weak self] message, subject in
            guard let `self` = self else { return }
            
            switch self.mode {
            case .scheduled, .pinned:
                return
            default:
                break
            }
            
            if let peer = self.chatInteraction.presentation.mainPeer {
                let threadInfo = self.chatInteraction.presentation.threadInfo
                if let subject = subject, !peer.canSendMessage(self.mode.isThreadMode, threadData: threadInfo, cachedData: self.chatInteraction.presentation.cachedData) {
                    self.chatInteraction.replyToAnother(subject, false)
                    return
                }
            }
            
            
            self.chatInteraction.focusInputField()
            self.replyMessageDisposable.set(nil)
            let replyMessage = message.flatMap { $0.id == subject?.messageId ? $0 : nil }
            self.chatInteraction.update({ current in
                var current = current.updatedInterfaceState({ $0.withUpdatedReplyMessageId(subject).withUpdatedReplyMessage(replyMessage) })
                if subject?.messageId == current.keyboardButtonsMessage?.replyAttribute?.messageId {
                    current = current.updatedInterfaceState({ $0.withUpdatedDismissedForceReplyId(subject?.messageId) })
                }
                return current
            })
            guard let subject, replyMessage == nil else { return }
            self.replyMessageDisposable.set((self.chatInteraction.interactionContext.account.postbox.messageAtId(subject.messageId) |> deliverOnMainQueue).start(next: { [weak self] message in
                self?.chatInteraction.update({ current in
                    guard current.interfaceState.replyMessageId == subject else { return current }
                    return current.updatedInterfaceState({ $0.withUpdatedReplyMessage(message) })
                })
            }))
            
            
        }
        
        chatInteraction.removeAd = { [weak self] opaqueId in
            self?.adMessages?.remove(opaqueId: opaqueId)
        }
        
        chatInteraction.startRecording = { [weak self] hold, view in
            guard let chatInteraction = self?.chatInteraction else {return}
            let recordingMode = FastSettings.recordingState
            if hasModals(context.window) || hasPopover(context.window) {
                return
            }
            if let slowMode = chatInteraction.presentation.slowMode, slowMode.hasLocked {
                if let last = slowMode.sendingIds.last {
                    chatInteraction.focusMessageId(nil, .init(messageId: last, string: nil), .CenterEmpty)
                }
                if let view = self?.genericView.inputView.currentActionView {
                    showSlowModeTimeoutTooltip(slowMode, for: view)
                    return
                }
            }
            
            if let cachedData = chatInteraction.presentation.cachedData as? CachedUserData, let peer = chatInteraction.presentation.mainPeer {
                if !cachedData.voiceMessagesAvailable {
                    if let view = self?.genericView.inputView.currentActionView {
                        tooltip(for: view, text: strings().chatSendVoicePrivacyError(peer.compactDisplayTitle))
                    }
                    return
                }
            }
            
            if chatInteraction.presentation.recordingState != nil || chatInteraction.presentation.state != .normal {
                NSSound.beep()
                return
            }
            if let peer = chatInteraction.presentation.peer {
                let flags: TelegramChatBannedRightsFlags
                switch recordingMode {
                case .video:
                    flags = .banSendInstantVideos
                case .voice:
                    flags = .banSendVoice
                }
                if let permissionText = permissionText(from: peer, for: flags, cachedData: chatInteraction.presentation.cachedData) {
                    showModalText(for: context.window, text: permissionText)
                    return
                }
                
                let invoke:()->Void = { [weak chatInteraction] in
                    guard let chatInteraction else {
                        return
                    }
                    switch recordingMode {
                    case .voice:
                        let state = ChatRecordingAudioState(context: chatInteraction.interactionContext, liveUpload: chatInteraction.peerId.namespace != Namespaces.Peer.SecretChat, autohold: hold)
                        state.start()
                        delay(0.1, closure: { [weak chatInteraction] in
                            chatInteraction?.update({$0.withRecordingState(state)})
                        })
                    case .video:
                        let state = ChatRecordingVideoState(context: chatInteraction.interactionContext, liveUpload: chatInteraction.peerId.namespace != Namespaces.Peer.SecretChat, autohold: hold)
                        let recorder = VideoRecorderModalController(state: state, pipeline: state.pipeline, sendMedia: { [weak chatInteraction] medias in
                            chatInteraction?.sendMedia(medias)
                        }, resetState: { [weak chatInteraction] in
                            chatInteraction?.update { $0.withoutRecordingState() }
                        })
                        self?.videoRecorderModal = recorder
                        showModal(with: recorder, for: context.window)

                        chatInteraction.update({$0.withRecordingState(state)})
                    }
                }
                
                let checkStars:()->Void = { [weak chatInteraction] in
                    guard let chatInteraction else {
                        return
                    }
                    
                    let presentation = chatInteraction.presentation
                    let messagesCount = 1
                    
                    if let payStars = presentation.sendPaidMessageStars, let peer = presentation.peer, let starsState = presentation.starsState {
                        let starsPrice = Int(payStars.value * Int64(messagesCount))
                        let amount = strings().starListItemCountOther(starsPrice)
                        
                        if !presentation.alwaysPaidMessage {
                            
                            let messageCountText = strings().chatPayStarsConfirmMessagesOther(messagesCount)
                            
                            verifyAlert(for: chatInteraction.interactionContext.window, header: strings().chatPayStarsConfirmTitle, information: strings().chatPayStarsConfirmText(peer.displayTitle, amount, amount, messageCountText), ok: strings().chatPayStarsConfirmPayOther(messagesCount), option: strings().chatPayStarsConfirmCheckbox, optionIsSelected: false, successHandler: { [weak chatInteraction] result in
                                guard let chatInteraction = chatInteraction else { return }
                                guard chatPaidMessagePriceIsCurrent(chatInteraction, payStars) else { return }
                                if starsState.balance.value > starsPrice {
                                    chatInteraction.update({ current in
                                        return current
                                            .withUpdatedAlwaysPaidMessage(result == .thrid)
                                    })
                                    invoke()
                                    if result == .thrid {
                                        FastSettings.toggleCofirmPaid(peer.id, price: Int(payStars.value))
                                    }
                                } else {
                                    FeatureNavigationHooks.shared.showStarsPurchaseWithContext(context, context.window, .stars, nil, Int64(starsPrice))
                                }
                            }, cancelHandler: {
                            })
                            
                        } else {
                            if starsState.balance.value > starsPrice {
                                invoke()
                            } else {
                                FeatureNavigationHooks.shared.showStarsPurchaseWithContext(context, context.window, .stars, nil, Int64(starsPrice))
                            }
                        }
                    } else {
                        invoke()
                    }

                }
                
                /*
                 

                 */
                
                if chatInteraction.presentation.effectiveInput.inputText.isEmpty {
                    switch recordingMode {
                    case .voice:
                        let permission: Signal<Bool, NoError> = (requestMediaPermission(.audio) |> deliverOnMainQueue)
                       _ = permission.start(next: { access in
                            if access {
                                checkStars()
                            } else {
                                verifyAlert_button(for: context.window, information: strings().requestAccesErrorHaveNotAccessVoiceMessages, ok: strings().modalOK, cancel: "", option: strings().requestAccesErrorConirmSettings, successHandler: { result in
                                   switch result {
                                   case .thrid:
                                       openSystemSettings(.none)
                                   default:
                                       break
                                   }
                               })
                            }
                        })
                    case .video:
                        let permission: Signal<Bool, NoError> = (combineLatest(requestMediaPermission(.video), requestMediaPermission(.audio)) |> map { $0 && $1 } |> deliverOnMainQueue)
                        _ = permission.start(next: { access in
                            if access {
                                checkStars()
                            } else {
                                verifyAlert_button(for: context.window, information: strings().requestAccesErrorHaveNotAccessVideoMessages, ok: strings().modalOK, cancel: "", option: strings().requestAccesErrorConirmSettings, successHandler: { result in
                                    switch result {
                                    case .thrid:
                                        openSystemSettings(.none)
                                    default:
                                        break
                                    }
                                })
                            }
                           
                        })
                    }
                }
            }
        }
        
        let scrollAfterSend:()->Void = { [weak self] in
            guard let `self` = self else { return }
            self.chatInteraction.scrollToLatest(true)
            ChatUIHooks.shared.closeEntertainmentPopover(self.context)
            self.context.cancelGlobalSearch.set(true)
//            self.reactionManager?.clearAndTempLock()
        }
        
        
        let _afterSentTransition:(Bool)->Void = { [weak self] flushInput in
            self?.chatInteraction.update({ presentation in
                return presentation.updatedInputQueryResult {_ in
                    return nil
                }.updatedInterfaceState { current in
                
                    var value: ChatInterfaceState = current
                    if flushInput {
                        value = value
                            .withUpdatedInputState(ChatTextInputState())
                    }
                    value = value.withUpdatedReplyMessageId(nil)
                        .withUpdatedInputState(ChatTextInputState())
                        .withUpdatedForwardMessageIds([])
                        .withUpdatedComposeDisableUrlPreview(nil)
                        .withUpdatedMessageEffect(nil)
                        .withUpdatedSuggestPost(nil)
                        .withoutEditMessage()
                
                    if let message = presentation.keyboardButtonsMessage, let replyMarkup = message.replyMarkup {
                        if replyMarkup.flags.contains(.setupReply) {
                            value = value.withUpdatedDismissedForceReplyId(message.id)
                        }
                    }
                    return value
                }.updatedUrlPreview(nil).updateBotMenu({ current in
                    var current = current
                    current?.revealed = false
                    return current
                }).withUpdatedAcknowledgedPaidMessage(false)
            
            })
            self?.chatInteraction.saveState(scrollState: self?.immediateScrollState())
            if !context.isLite(.animations) {
                self?.context.bindings.doGlobalBackgroundAction()
            }
        }
        
        let afterSentTransition:()->Void = {
            _afterSentTransition(true)
        }
        
        chatInteraction.jumpToDate = { [weak self] date in
            if let strongSelf = self, let window = self?.window, let peerId = self?.chatInteraction.peerId {
                strongSelf.cancelMessageFocus()
                let requestId = strongSelf.messageFocusRequestId
                let chatLocation = strongSelf.chatLocation
                let locationTag = strongSelf.locationValue?.tag
                
                
                switch strongSelf.mode {
                case .history, .thread, .preview:
                    let signal = context.engine.messages.searchMessageIdByTimestamp(peerId: peerId, threadId: chatLocation.threadId, timestamp: Int32(date.timeIntervalSince1970))
                    
                    strongSelf.dateDisposable.set(showModalProgress(signal: signal |> deliverOnMainQueue, for: window).start(next: { [weak strongSelf] messageId in
                        guard let strongSelf, strongSelf.messageFocusRequestId == requestId,
                              strongSelf.chatLocation == chatLocation, strongSelf.locationValue?.tag == locationTag else { return }
                        if let messageId = messageId {
                            strongSelf.chatInteraction.focusMessageId(nil, .init(messageId: messageId, string: nil), .top(id: 0, innerId: nil, animated: true, focus: .init(focus: false), inset: 30))
                        }
                    }))
                case .scheduled:
                    let targetDay = chatDateId(for: Int32(date.timeIntervalSince1970))
                    var previousItem: ChatRowItem?
                    var targetItem: ChatRowItem?
                    strongSelf.genericView.tableView.enumerateItems(with: { item -> Bool in
                        if let item = item as? ChatDateStickItem {
                            if Int64(item.timestamp) == targetDay {
                                targetItem = previousItem
                                return false
                            }
                            previousItem = nil
                        } else if let item = item as? ChatRowItem {
                            previousItem = item
                        }
                        return true
                    })
                    if let targetItem {
                        strongSelf.genericView.tableView.scroll(to: .top(id: targetItem.stableId, innerId: nil, animated: true, focus: .init(focus: false), inset: 30))
                    }
                case .pinned:
                    break
                case .customChatContents:
                    break
                case .customLink:
                    break
                }
                
                
            }
        }
       
        let editMessage:(ChatEditState, Date?)->Void = { [weak self] state, atDate in
            guard let `self` = self else {return}
            let chatInteraction = self.chatInteraction
            let presentation = chatInteraction.presentation

            let inputState = state.inputState.subInputState(from: NSMakeRange(0, state.inputState.inputText.length))

            let text = inputState.inputText.trimmed
            if text.length > chatInteraction.maxInputCharacters {
                if context.isPremium || context.premiumIsBlocked {
                    alert(for: context.window, info: strings().chatInputErrorMessageTooLongOther(text.length - Int(chatInteraction.maxInputCharacters)))
                } else if !context.premiumIsBlocked {
                    verifyAlert_button(for: context.window, information: strings().chatInputErrorMessageTooLongOther(text.length - Int(chatInteraction.maxInputCharacters)), ok: strings().alertOK, cancel: "", option: strings().premiumGetPremiumDouble, successHandler: { result in
                        switch result {
                        case .thrid:
                            showPremiumLimit(context: context, type: .caption(text.length))
                        default:
                            break
                        }

                    })
                }
                return
            }

            let urlPreview = urlPreviewMatchesInput(presentation, context: context) ? presentation.urlPreview : nil
            let disableUrlPreview = presentation.interfaceState.composeDisableUrlPreview != nil && (urlPreview == nil || urlPreview?.0 == presentation.interfaceState.composeDisableUrlPreview)

            self.urlPreviewQueryState?.1.dispose()
            
            
            let webpagePreviewAttribute: WebpagePreviewMessageAttribute?
            
            let media: RequestEditMessageMedia
            if let webpreview = urlPreview?.1 {
                webpagePreviewAttribute = .init(leadingPreview: !presentation.interfaceState.linkBelowMessage, forceLargeMedia: presentation.interfaceState.largeMedia, isManuallyAdded: false, isSafe: true)
                if urlPreview?.0 == presentation.interfaceState.composeDisableUrlPreview {
                    media = .keep
                } else {
                    media = .update(.webPage(webPage: WebpageReference(webpreview), media: webpreview))
                }
            } else {
                webpagePreviewAttribute = nil
                media = state.editMedia
            }
            
            let invertMediaAttribute = state.invertMedia ? InvertMediaMessageAttribute() : nil
            
            
            let editSubmissionId = chatInteraction.beginMediaEditSubmission()
            if atDate == nil {
                self.context.account.pendingUpdateMessageManager.add(messageId: state.message.id, text: inputState.inputText, media: media, entities: TextEntitiesMessageAttribute(entities: inputState.messageTextEntities(extractDates: state.message.id.peerId.namespace == Namespaces.Peer.CloudUser)), richText: nil, inlineStickers: inputState.inlineMedia, webpagePreviewAttribute: webpagePreviewAttribute, invertMediaAttribute: invertMediaAttribute, disableUrlPreview: disableUrlPreview)
                
                self.chatInteraction.beginEditingMessage(nil)
                self.chatInteraction.update({
                    $0.updatedInterfaceState({
                        $0.withUpdatedComposeDisableUrlPreview(nil).updatedEditState({
                            $0?.withUpdatedLoadingState(.none)
                        })
                    })
                })
                
            } else {
                let scheduleTime:Int32? = atDate != nil ? Int32(atDate!.timeIntervalSince1970) : nil
                
               
                self.chatInteraction.update({$0.updatedUrlPreview(nil).updatedInterfaceState({$0.updatedEditState({$0?.withUpdatedLoadingState(state.editMedia == .keep ? .loading : .progress(0.2))})})})
                        
                let scheduleAttr = scheduleTime.flatMap {
                    OutgoingScheduleInfoMessageAttribute(scheduleTime: $0, repeatPeriod: nil)
                }
                
                
                self.chatInteraction.editDisposable.set((context.engine.messages.requestEditMessage(messageId: state.message.id, text: inputState.inputText, media: media, entities: TextEntitiesMessageAttribute(entities: inputState.messageTextEntities()), richText: nil, inlineStickers: inputState.inlineMedia, webpagePreviewAttribute: webpagePreviewAttribute, invertMediaAttribute: invertMediaAttribute, disableUrlPreview: disableUrlPreview, scheduleInfoAttribute: scheduleAttr) |> deliverOnMainQueue).start(next: { [weak self] progress in
                    guard let self, self.chatInteraction.isCurrentMediaEditSubmission(editSubmissionId), self.chatInteraction.presentation.interfaceState.editState?.message.id == state.message.id else { return }
                    switch progress {
                    case let .progress(progress):
                        if state.editMedia != .keep {
                            self.chatInteraction.update({$0.updatedInterfaceState({$0.updatedEditState({$0?.withUpdatedLoadingState(.progress(max(progress, 0.2)))})})})
                        }
                    default:
                        break
                    }
                    
                    }, error: { [weak self] error in
                        guard let self, self.chatInteraction.isCurrentMediaEditSubmission(editSubmissionId), self.chatInteraction.presentation.interfaceState.editState?.message.id == state.message.id else { return }
                        self.chatInteraction.update({ $0.updatedInterfaceState({ $0.updatedEditState({ $0?.withUpdatedLoadingState(.none) }) }) })
                        alert(for: context.window, info: strings().unknownError)
                    }, completed: { [weak self] in
                        guard let self, self.chatInteraction.isCurrentMediaEditSubmission(editSubmissionId), self.chatInteraction.presentation.interfaceState.editState?.message.id == state.message.id else { return }
                        self.chatInteraction.beginEditingMessage(nil)
                        self.chatInteraction.update({
                            $0.updatedInterfaceState({
                                $0.withUpdatedComposeDisableUrlPreview(nil).updatedEditState({
                                    $0?.withUpdatedLoadingState(.none)
                                })
                            })
                        })
                }))
            }
            
        }
        
        chatInteraction.sendMessage = { [weak self] silent, atDate, messageEffect in
            if customChatContents != nil {
            }
            #if DEBUG
            if let strongSelf = self,
               isChatSyntheticButtonsCommand(strongSelf.chatInteraction.presentation.effectiveInput.inputText) {
                insertSyntheticButtonsMessages(
                    context: strongSelf.context,
                    peerId: strongSelf.chatInteraction.peerId,
                    threadId: strongSelf.chatInteraction.chatLocation.threadId
                )
                strongSelf.chatInteraction.updateInput(with: "")
                return
            }
            if let strongSelf = self,
               isChatUnsupportedMessageCommand(strongSelf.chatInteraction.presentation.effectiveInput.inputText) {
                insertUnsupportedMockMessages(
                    context: strongSelf.context,
                    peerId: strongSelf.chatInteraction.peerId,
                    threadId: strongSelf.chatInteraction.chatLocation.threadId
                )
                strongSelf.chatInteraction.updateInput(with: "")
                return
            }
            if let strongSelf = self,
               isChatUnsupportedMessage2Command(strongSelf.chatInteraction.presentation.effectiveInput.inputText) {
                insertSupportedFileMockMessage(
                    context: strongSelf.context,
                    peerId: strongSelf.chatInteraction.peerId,
                    threadId: strongSelf.chatInteraction.chatLocation.threadId
                )
                strongSelf.chatInteraction.updateInput(with: "")
                return
            }
            if let strongSelf = self,
               isChatGramsModalCommand(strongSelf.chatInteraction.presentation.effectiveInput.inputText) {
                strongSelf.chatInteraction.updateInput(with: "")
                ChatNavigationHooks.shared.showFirstGramsModal(strongSelf.context, strongSelf.context.window)
                return
            }
            #endif
            // Flush the live inline editor (if any) into the stored draft / composer text first, so this send
            // posts the current edited content (we don't continuously sync — that loops).
            self?.chatInteraction.flushRichTextDraft?()
            let deferredSendAction = self?.chatInteraction.captureDeferredSendAction()
            // A structural rich-text draft (composed in the rich editor, shown as the composer preview) sends
            // as a RichTextMessageAttribute, bypassing the plain text/forward send below — the text input is
            // empty while a draft is present (so `abilityToSend`, which requires non-empty text, can't be used;
            // gate on the permission conditions only: normal state, not slow-locked, not an unpriced suggest).
            let canSendRichDraft: Bool = {
                guard let strongSelf = self else { return false }
                let p = strongSelf.chatInteraction.presentation
                guard p.state == .normal else { return false }
                if let suggestPost = p.interfaceState.suggestPost, suggestPost.amount == nil { return false }
                if let slowMode = p.slowMode, slowMode.hasLocked || p.slowModeMultipleLocked { return false }
                return true
            }()
            if let strongSelf = self, let draft = strongSelf.chatInteraction.richTextDraft, canSendRichDraft {
                let ci = strongSelf.chatInteraction
                // Don't send a structurally-present but empty draft (e.g. an empty table) — keep it and warn.
                if !richTextOutgoingHasContent(richTextOutgoing(from: draft).blocks) {
                    showModalText(for: context.window, text: strings().chatEmptyMessageError)
                    return
                }
                func applyRichDraft(_ date: Date?, _ repeatPeriod: Int32?) {
                    ci.setRichTextDraft(nil)
                    var attributes: [MessageAttribute] = [RichTextMessageAttribute(instantPage: draft, fullInstantPage: nil)]
                    if let date {
                        attributes.append(OutgoingScheduleInfoMessageAttribute(scheduleTime: Int32(min(date.timeIntervalSince1970, Double(scheduleWhenOnlineTimestamp))), repeatPeriod: repeatPeriod))
                    }
                    richTextEnqueue(chatInteraction: ci, text: "", attributes: attributes)
                }
                if let atDate {
                    applyRichDraft(atDate.date, atDate.repeatPeriod)
                } else if strongSelf.mode == .scheduled, let peer = ci.peer {
                    DispatchQueue.main.async {
                        showModal(with: chatDateSelector(context: context, mode: .schedule(peer.id), selectedAt: { date, repeatPeriod in
                            guard deferredSendAction?.takeIfCurrent(onInvalidated: {}) == true else { return }
                            applyRichDraft(date, repeatPeriod)
                        }), for: context.window)
                    }
                } else {
                    applyRichDraft(nil, nil)
                }
                return
            }
            if let strongSelf = self, !strongSelf.nextTransaction.isExutable, !strongSelf.chatInteraction.isPreparingForwardSend {
                let chatInteraction = strongSelf.chatInteraction
                let presentation = chatInteraction.presentation
                let peerId = strongSelf.chatInteraction.peerId
                let currentSendAsPeerId = presentation.currentSendAsPeerId
                if presentation.abilityToSend {
                    func apply(_ controller: ChatController, atDate: Date?, repeatPeriod: Int32?) {
                        let confirmationAction = chatInteraction.captureDeferredSendAction()
                        let destinationPeerId = makePeerId()
                        let destinationReply = takeReplyId()
                        let destinationThreadId = makeThreadId64(true)
                        var makeTextSignal: () -> Signal<Never, NoError> = { .complete() }
                        
                        let suggest = presentation.interfaceState.suggestPost
                        
                        var isSuggestEditing: Bool = false
                        if let suggest {
                            switch suggest.mode {
                            case .edit, .suggest:
                                isSuggestEditing = true
                            default:
                                break
                            }
                        }
                        
                        var setNextToTransaction = false
                        if let state = presentation.interfaceState.editState, !isSuggestEditing {
                            editMessage(state, atDate)
                            return
                        } else {
                            let hasText = !presentation.effectiveInput.inputText.trimmed.isEmpty
                            let hasForwards = !presentation.interfaceState.forwardMessageIds.isEmpty
                            var messagesCount: Int = presentation.interfaceState.forwardMessageIds.count
                            if !presentation.effectiveInput.inputText.trimmed.isEmpty {
                                setNextToTransaction = true
                                let paidMessageStars = takePaidMessageStars()
                                makeTextSignal = { [weak controller] in
                                    guard let controller else { return .complete() }
                                    return Sender.enqueue(input: presentation.effectiveInput, context: context, peerId: destinationPeerId, replyId: destinationReply, threadId: destinationThreadId, disablePreview: presentation.interfaceState.composeDisableUrlPreview != nil, linkBelowMessage: presentation.interfaceState.linkBelowMessage, largeMedia: presentation.interfaceState.largeMedia, silent: silent, atDate: atDate, repeatPeriod: repeatPeriod, sendAsPeerId: currentSendAsPeerId, mediaPreview: presentation.urlPreview?.1, emptyHandler: { [weak controller] in
                                        _ = controller?.nextTransaction.execute()
                                    }, customChatContents: customChatContents, messageEffect: messageEffect, sendPaidMessageStars: paidMessageStars, suggestPost: presentation.interfaceState.suggestPost) |> deliverOnMainQueue |> afterNext { ids in
                                    } |> ignoreValues
                                }
                                messagesCount += 1
                            }
                            
                            let invoke:()->Void = {
                                guard confirmationAction.takeIfCurrent(onInvalidated: {}) else { return }
                                let fwdIds: [MessageId] = presentation.interfaceState.forwardMessageIds
                                let hideNames = presentation.interfaceState.hideSendersName
                                let hideCaptions = presentation.interfaceState.hideCaptions
                                let cachedData = presentation.cachedData
                                var startedSending = false
                                let startSending: () -> Void = { [weak controller] in
                                    guard !startedSending, let controller else { return }
                                    startedSending = true
                                    if setNextToTransaction {
                                        if atDate != nil {
                                            afterSentTransition()
                                        } else {
                                            controller.nextTransaction.set(handler: afterSentTransition)
                                        }
                                    }
                                }
                                let invokeSignal: Signal<Never, NoError>
                                if !fwdIds.isEmpty {
                                    setNextToTransaction = true
                                    
                                    
                                    invokeSignal = controller.chatInteraction.prepareForwardSend(onInvalidated: {}, request: {
                                        combineLatest(queue: .mainQueue(), context.account.postbox.messagesAtIds(fwdIds), context.account.postbox.loadedPeerWithId(peerId))
                                    }) |> mapToSignal { [weak controller] messages, peer -> Signal<Never, NoError> in
                                        guard let controller else { return .complete() }
                                        startSending()
                                        return (makeTextSignal() |> then(deferred {
                                            if messages.count != fwdIds.count {
                                            }
                                            let errors:[String] = messages.compactMap { message in

                                                for attr in message.attributes {
                                                    if let _ = attr as? InlineBotMessageAttribute, peer.hasBannedRights(.banSendInline) {
                                                        return permissionText(from: peer, for: .banSendInline, cachedData: cachedData)
                                                    }
                                                }

                                                if let media = message.anyMedia {
                                                    return checkMediaPermission(media, for: peer)
                                                }

                                                return nil
                                            }

                                            if !errors.isEmpty {
                                                alert(for: context.window, info: errors.joined(separator: "\n\n"))
                                                return .complete()
                                            }

                                            return Sender.forwardMessages(messageIds: messages.map { $0.id }, context: context, peerId: destinationPeerId, replyId: destinationReply, threadId: destinationThreadId, hideNames: hideNames, hideCaptions: hideCaptions, silent: silent, atDate: atDate, sendAsPeerId: currentSendAsPeerId) |> afterNext { ids in
                                            } |> ignoreValues
                                        }))
                                    }

                                } else {
                                    startSending()
                                    invokeSignal = makeTextSignal()
                                }

                                if fwdIds.isEmpty, atDate == nil, !presentation.effectiveInput.inputText.trimmed.isEmpty, presentation.botMenu?.revealed != true, controller.historyState.isDownOfHistory {
                                    controller.textSendFlight?.launch()
                                }

                                _ = (invokeSignal |> deliverOnMainQueue).start(completed: {
                                    if startedSending { scrollAfterSend() }
                                })
                                
                            }
                            
                            if messagesCount > 0, let payStars = presentation.sendPaidMessageStars, let peer = presentation.peer, let starsState = presentation.starsState {
                                let starsPrice = Int(payStars.value * Int64(messagesCount))
                                let amount = strings().starListItemCountOther(starsPrice)
                                
                                if !presentation.alwaysPaidMessage {
                                    
                                    let messageCountText = strings().chatPayStarsConfirmMessagesOther(messagesCount)
                                    
                                    verifyChatSendPayment(for: chatInteraction.interactionContext.window, header: strings().chatPayStarsConfirmTitle, information: strings().chatPayStarsConfirmText(peer.displayTitle, amount, amount, messageCountText), ok: strings().chatPayStarsConfirmPayOther(messagesCount), option: strings().chatPayStarsConfirmCheckbox, successHandler: { result in
                                        guard chatPaidMessagePriceIsCurrent(chatInteraction, payStars) else { return }
                                        if starsState.balance.value > starsPrice {
                                            chatInteraction.update({ current in
                                                return current
                                                    .withUpdatedAlwaysPaidMessage(result == .thrid)
                                            })
                                            if result == .thrid {
                                                FastSettings.toggleCofirmPaid(peer.id, price: Int(payStars.value))
                                            }
                                            invoke()
                                        } else {
                                            FeatureNavigationHooks.shared.showStarsPurchaseWithContext(context, context.window, .stars, nil, Int64(starsPrice))
                                        }
                                    }, cancelHandler: {
                                    }, dismissed: {
                                    })
                                } else {
                                    if starsState.balance.value > starsPrice {
                                        invoke()
                                    } else {
                                        FeatureNavigationHooks.shared.showStarsPurchaseWithContext(context, context.window, .stars, nil, Int64(starsPrice))
                                    }
                                }
                            } else {
                                invoke()
                            }
                        }
                    }
                    
                    switch strongSelf.mode {
                    case .scheduled:
                        if let atDate = atDate {
                            apply(strongSelf, atDate: atDate.date, repeatPeriod: atDate.repeatPeriod)
                        } else if presentation.state != .editing, let peer = chatInteraction.peer {
                            DispatchQueue.main.async { [strongSelf] in
                                showModal(with: chatDateSelector(context: context, mode: .schedule(peer.id), selectedAt: { [weak strongSelf] date, repeatPeriod in
                                    guard deferredSendAction?.takeIfCurrent(onInvalidated: {}) == true else { return }
                                    if let strongSelf = strongSelf {
                                        apply(strongSelf, atDate: date, repeatPeriod: repeatPeriod)
                                    }
                                }), for: context.window)
                            }
                        } else {
                            apply(strongSelf, atDate: nil, repeatPeriod: nil)
                        }
                    case .history, .thread, .pinned, .customChatContents:
                        delay(0.1, closure: {
                            if atDate != nil {
                                strongSelf.openScheduledChat()
                            }
                        })
                        apply(strongSelf, atDate: atDate?.date, repeatPeriod: atDate?.repeatPeriod)
                    case let .customLink(contents):
                        contents.saveText?(presentation.effectiveInput)
                        strongSelf.navigationController?.invokeBack(checkLock: false)
                    case .preview:
                        break
                    }
                    
                } else {
                    if presentation.effectiveInput.inputText.trimmed.isEmpty, presentation.interfaceState.forwardMessageIds.isEmpty, chatInteraction.richTextDraft == nil, presentation.interfaceState.editState == nil {
                    } else {
                    }
                    if let suggest = presentation.interfaceState.suggestPost, suggest.amount == nil {
                        strongSelf.chatInteraction.editPostSuggestion(suggest)
                        return
                    }
                    if let editState = presentation.interfaceState.editState, editState.inputState.inputText.isEmpty {
                        if editState.message.media.isEmpty || editState.message.anyMedia is TelegramMediaWebpage {
                            strongSelf.chatInteraction.deleteMessages([editState.message.id], nil)
                            return
                        }
                    }
                    let actionView = strongSelf.genericView.inputView.currentActionView
                    if let slowMode = presentation.slowMode {
                        if let errorText = presentation.slowModeErrorText {
                            if let slowMode = presentation.slowMode, slowMode.timeout != nil {
                                showSlowModeTimeoutTooltip(slowMode, for: actionView)
                            } else {
                                tooltip(for: actionView, text: errorText)
                            }
                            if let last = slowMode.sendingIds.last {
                                strongSelf.chatInteraction.focusMessageId(nil, .init(messageId: last, string: nil), .CenterEmpty)
                            } else {
                                strongSelf.genericView.inputView.textView.shake()
                            }
                        } else {
                            strongSelf.genericView.inputView.textView.shake()
                        }
                       
                    }
                }
            }
        }
        
        chatInteraction.sendMessageMenu = { [weak self] fromEffect in
            guard let self else {
                return .single(nil)
            }
            let presentation = self.chatInteraction.presentation
            let chatInteraction = self.chatInteraction
            
            guard let peer = presentation.peer else {
                return .single(nil)
            }
            
            let context = context
            if let slowMode = presentation.slowMode, slowMode.hasLocked {
                return .single(nil)
            }
            if presentation.state != .normal {
                return .single(nil)
            }
            var items:[ContextMenuItem] = []

            if fromEffect {
                switch chatInteraction.mode {
                case .history, .thread:
                    items.append(ContextMenuItem(strings().modalRemove, handler: { [weak self] in
                        self?.chatInteraction.update {
                            $0.updatedInterfaceState {
                                $0.withUpdatedMessageEffect(nil)
                            }
                        }
                    }, itemMode: .destruct, itemImage: MenuAnimation.menu_clear_history.value))
                default:
                    break
                }
            } else {
                items = sendMessageMenuItems(chatInteraction: chatInteraction, send: { [weak chatInteraction] silent, schedule in
                    chatInteraction?.sendMessage(silent, schedule, chatInteraction?.presentation.messageEffect)
                }) ?? []
            }

            let reactions:Signal<[AvailableMessageEffects.MessageEffect], NoError> = context.diceCache.availableMessageEffects |> map { view in
                return view?.messageEffects ?? []
            } |> deliverOnMainQueue |> take(1)
                        
            return (reactions) |> map { [weak self] reactions in
                
                let width = ContextAddReactionsListView.width(for: reactions.count, maxCount: 7, allowToAll: true)
                let aboveText: String = strings().chatContextMessageEffectAdd
                
                let w_width = width + 20
                let color = theme.colors.darkGrayText.withAlphaComponent(0.8)
                let link = theme.colors.link.withAlphaComponent(0.8)
                let attributed = parseMarkdownIntoAttributedString(aboveText, attributes: .init(body: .init(font: .normal(.text), textColor: color), bold: .init(font: .medium(.text), textColor: color), link: .init(font: .normal(.text), textColor: link), linkAttribute: { link in
                    return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink("", { _ in
                        prem(with: PremiumBoardingController(context: context, source: .message_effects, openFeatures: true), for: context.window)
                    }))
                })).detectBold(with: .medium(.text))
                let aboveLayout = TextViewLayout(attributed, maximumNumberOfLines: 2, alignment: .center)
                aboveLayout.measure(width: w_width - 24)
                aboveLayout.interactions = LinkHooks.shared.globalLinkExecutor()
                
                let rect = NSMakeRect(0, 0, w_width, 40 + 20 + aboveLayout.layoutSize.height + 4)
                
                let panel = Window(contentRect: rect, styleMask: [.fullSizeContentView], backing: .buffered, defer: false)
                panel._canBecomeMain = false
                panel._canBecomeKey = false
                panel.level = .popUpMenu
                panel.backgroundColor = .clear
                panel.isOpaque = false
                panel.hasShadow = false
                

                let reveal:((ContextAddReactionsListView & StickerFramesCollector)->Void)?
                
                
                var selectedItems: [ChatUIEmojiSelectedItem] = []
                
                if let effect = presentation.interfaceState.messageEffect {
                    selectedItems.append(.init(source: .custom(effect.effect.effectSticker.fileId.id), type: .transparent))
                }
                
                let update:(Int64, NSRect?)->Void = { fileId, fromRect in
                    let effect = reactions.first(where: {
                        $0.effectSticker.fileId.id == fileId
                    })
                    let current = self?.chatInteraction.presentation.interfaceState.messageEffect
                    let value: ChatInterfaceMessageEffect?
                    if let effect, current?.effect != effect {
                        value = ChatInterfaceMessageEffect(effect: effect, fromRect: fromRect)
                    } else {
                        value = nil
                    }
                    self?.chatInteraction.update {
                        $0.updatedInterfaceState {
                            $0.withUpdatedMessageEffect(value)
                        }
                    }
                }
                
                reveal = { view in
                    ChatUIHooks.shared.showMessageEffectsWindow(context, peerId, selectedItems, { sticker, fromRect in
                        update(sticker.file.fileId.id, fromRect)
                    }, view)
                }
                
                let available: [ContextReaction] = Array(reactions.map { value in
                    return .custom(value: .custom(value.effectSticker.fileId.id), fileId: value.effectSticker.fileId.id, value.effectSticker._parse(), isSelected: presentation.interfaceState.messageEffect?.effect.effectSticker.fileId.id == value.effectSticker.fileId.id)
                }.prefix(7))
                
                let view = ContextAddReactionsListView(frame: rect, context: context, list: available, add: { value, checkPrem, fromRect in
                    switch value {
                    case let .custom(fileId):
                        update(fileId, fromRect)
                    default:
                        break
                    }
                }, radiusLayer: nil, revealReactions: reveal, aboveText: aboveLayout)
                
                
                panel.contentView?.addSubview(view)
                panel.contentView?.wantsLayer = true
                view.autoresizingMask = [.width, .height]
                
                let menu = ContextMenu(bottomAnchor: true)
                if peer.isUser, peer.id != context.peerId {
                    menu.topWindow = panel
                }
                
                for item in items {
                    menu.addItem(item)
                }
                return menu
            }
        }
        
        chatInteraction.updateEditingMessageMedia = { [weak self] exts, asMedia in
            guard let self, let messageId = self.chatInteraction.presentation.interfaceState.editState?.message.id else { return }
            let replacement = self.chatInteraction.beginMediaReplacement()
            let editingSessionId = self.editingSessionId
            self.editCurrentMessagePhotoDisposable.set(nil)
            self.updateMediaDisposable.set(nil)

            filePanel(with: exts, allowMultiple: false, for: context.window, cancelled: { [weak self] in
                self?.chatInteraction.cancelMediaReplacement(replacement)
            }, completion: { [weak self] files in
                guard let self, self.editingSessionId == editingSessionId, self.chatInteraction.presentation.interfaceState.editState?.message.id == messageId else { return }
                if let file = files?.first {
                    self.updateMediaDisposable.set((Sender.generateMedia(for: MediaSenderContainer(path: file, isFile: !asMedia), account: context.account, isSecretRelated: peerId.namespace == Namespaces.Peer.SecretChat) |> deliverOnMainQueue).start(next: { [weak self] media, _ in
                        guard let self, self.chatInteraction.presentation.interfaceState.editState?.message.id == messageId else { return }
                        self.chatInteraction.applyMediaReplacement(media, request: replacement)
                    }))
                } else if files != nil {
                    self.chatInteraction.failMediaReplacement(replacement)
                } else {
                    self.chatInteraction.discardMediaReplacement(replacement)
                }
            })
        }
        
        
        chatInteraction.addContact = { [weak self] in
            if let peerId = self?.chatInteraction.presentation.mainPeer?.id {
                showModal(with: NewContactController(context: context, peerId: peerId), for: context.window)
            }
        }
        chatInteraction.blockContact = { [weak self] in
            if let chatInteraction = self?.chatInteraction, let peer = chatInteraction.presentation.mainPeer {
                if peer.isUser || peer.isBot {
                    let options: [ModalOptionSet] = [ModalOptionSet(title: strings().blockContactOptionsReport, selected: true, editable: true), ModalOptionSet(title: strings().blockContactOptionsDeleteChat, selected: true, editable: true)]
                    
                    showModal(with: ModalOptionSetController(context: chatInteraction.interactionContext, options: options, actionText: (strings().blockContactOptionsAction(peer.compactDisplayTitle), theme.colors.redUI), desc: strings().blockContactTitle(peer.compactDisplayTitle), title: strings().blockContactOptionsTitle, result: { result in
                        
                        var signals:[Signal<Never, NoError>] = []
                        
                        
                        signals.append(context.blockedPeersContext.add(peerId: peer.id) |> `catch` { _ in return .complete() })
                        
                        if result[1] == .selected {
                            signals.append(context.engine.peers.removePeerChat(peerId: chatInteraction.peerId, reportChatSpam: result[0] == .selected) |> ignoreValues)
                        } else if result[0] == .selected {
                            
                            signals.append(context.engine.peers.reportPeer(peerId: peer.id) |> ignoreValues)
                        }
                        let closeChat = result[1] == .selected
                        
                        _ = showModalProgress(signal: combineLatest(signals), for: context.window).start(completed: {
                            if closeChat {
                                context.bindings.rootNavigation().back()
                            }
                        })
                        
                    }), for: context.window)
                } else {
                    chatInteraction.reportSpamAndClose()
                }
               
            }
            
        }
        
        chatInteraction.unarchive = { [weak self] in
            _ = context.engine.peers.updatePeersGroupIdInteractively(peerIds: [peerId], groupId: .root).start()
            let removeFlagsSignal = context.account.postbox.transaction { transaction in
                transaction.updatePeerCachedData(peerIds: [peerId], update: { peerId, cachedData in
                    if let cachedData = cachedData as? CachedUserData {
                        let current = cachedData.peerStatusSettings
                        var flags = current?.flags ?? []
                        flags.remove(.autoArchived)
                        flags.remove(.canBlock)
                        flags.remove(.canReport)
                        return cachedData.withUpdatedPeerStatusSettings(PeerStatusSettings(flags: flags, managingBot: nil))
                    }
                    if let cachedData = cachedData as? CachedChannelData {
                        let current = cachedData.peerStatusSettings
                        var flags = current?.flags ?? []
                        flags.remove(.autoArchived)
                        flags.remove(.canBlock)
                        flags.remove(.canReport)
                        return cachedData.withUpdatedPeerStatusSettings(PeerStatusSettings(flags: flags, managingBot: nil))
                    }
                    if let cachedData = cachedData as? CachedGroupData {
                        let current = cachedData.peerStatusSettings
                        var flags = current?.flags ?? []
                        flags.remove(.autoArchived)
                        flags.remove(.canBlock)
                        flags.remove(.canReport)
                        return cachedData.withUpdatedPeerStatusSettings(PeerStatusSettings(flags: flags, managingBot: nil))
                    }
                    return cachedData
                })
            }
            let unmuteSignal = context.engine.peers.updatePeerMuteSetting(peerId: peerId, threadId: self?.chatLocation.threadId, muteInterval: nil)
            
            _ = combineLatest(unmuteSignal, removeFlagsSignal).start()
        }
        
        chatInteraction.appendAttributedText = { [weak self] attr in
            _ = self?.chatInteraction.appendText(attr)
        }
        
        chatInteraction.sendPlainText = { [weak self] text in
            guard let strongSelf = self, let peer = strongSelf.chatInteraction.presentation.peer else {
                return
            }
            let destination = makePeerId()
            guard peer.canSendMessage(strongSelf.mode.isThreadMode, threadData: strongSelf.chatInteraction.presentation.threadInfo, cachedData: strongSelf.chatInteraction.presentation.cachedData) else {
                return
            }
            let presentation = strongSelf.chatInteraction.presentation
            let signal = Sender.enqueue(input: ChatTextInputState(inputText: text), context: context, peerId: destination, replyId: takeReplyId(), threadId: threadId64(), sendAsPeerId: presentation.currentSendAsPeerId, customChatContents: customChatContents, sendPaidMessageStars: takePaidMessageStars())
            _ = (signal |> deliverOnMainQueue).start(completed: {
                scrollAfterSend()
            })
        }

        chatInteraction.hashtag = { hashtag in
            context.bindings.globalSearch(hashtag, peerId, nil)
        }
        
        chatInteraction.sendLocation = { [weak self] coordinate, venue in
            let media = TelegramMediaMap(latitude: coordinate.latitude, longitude: coordinate.longitude, heading: nil, accuracyRadius: nil, venue: venue, liveBroadcastingTimeout: nil, liveProximityNotificationRadius: nil)
            self?.chatInteraction.sendMedias([media], ChatTextInputState(), false, nil, false, nil, false, nil, false)
        }
        
        chatInteraction.scrollToLatest = { [weak self] removeStack in
            if let strongSelf = self {
                if removeStack {
                    strongSelf.historyState = strongSelf.historyState.withClearReplies()
                }
                strongSelf.scrollup(force: removeStack)
            }
        }

        if #available(macOS 10.15, *) {
            chatInteraction.walletTransferAnimation = ChatWalletTransferAnimation(chatInteraction: chatInteraction, tableView: genericView.tableView)
        }
        chatInteraction.voiceSendFlight = ChatVoiceSendFlight(tableView: genericView.tableView)
        chatInteraction.voiceTranscription = ChatVoiceTranscription(chatInteraction: chatInteraction, host: genericView)
        self.textSendFlight = ChatTextSendFlight(view: genericView)
        chatInteraction.mediaSendFlight = ChatMediaSendFlight(view: genericView, canLaunch: { [weak self] in
            guard let self else {
                return false
            }
            switch self.mode {
            case .history, .thread:
                return self.historyState.isDownOfHistory
            default:
                return false
            }
        })

        chatInteraction.reportMessages = { [weak self] value, ids in
            ChatNavigationHooks.shared.showReportDetails(context, value, { [weak self] value in
                _ = showModalProgress(signal: context.engine.peers.reportPeerMessages(messageIds: ids, reason: value.reason, message: value.comment), for: context.window).start(completed: { [weak self] in
                    showModalText(for: context.window, text: strings().peerInfoChannelReported)
                    self?.changeState()
                })
            }, context.window)

        }
        
        chatInteraction.translateTo = { [weak self] toLang in
            self?.liveTranslate?.translate(toLang: toLang)
        }
        chatInteraction.setTranslateTone = { [weak self] tone in
            self?.liveTranslate?.setTone(tone)
        }
        chatInteraction.enableTranslatePaywall = { [weak self] in
            self?.liveTranslate?.enablePaywall()
        }
        chatInteraction.summarize = { [weak self] message in
            self?.liveTranslate?.summarize(message)
        }
        chatInteraction.clearSummarize = { [weak self] messageId in
            self?.liveTranslate?.clearSummarize(messageId)
        }

        chatInteraction.boostToUnrestrict = { source in
            let signal: Signal<(Peer, ChannelBoostStatus?, MyBoostStatus?)?, NoError> = context.account.postbox.loadedPeerWithId(peerId) |> mapToSignal { value in
                return combineLatest(context.engine.peers.getChannelBoostStatus(peerId: value.id), context.engine.peers.getMyBoostStatus()) |> map {
                    (value, $0, $1)
                }
            }
            _ = showModalProgress(signal: signal, for: context.window).start(next: { value in
                if let value = value, let boosts = value.1 {
                    showModal(with: BoostChannelModalController(context: context, peer: value.0, boosts: boosts, myStatus: value.2, source: source), for: context.window)
                } else {
                    alert(for: context.window, info: strings().unknownError)
                }
            })
        }
        
        chatInteraction.forwardMessages = { [weak self] messages in
            guard let strongSelf = self else {
                return
            }
            if let report = strongSelf.chatInteraction.presentation.reportMode {
                strongSelf.chatInteraction.reportMessages(report, messages.map { $0.id })
                return
            }
            let messages = messages.map(messageForForwarding)
            showModal(with: ChatUIHooks.shared.makeForwardMessagesShareModalObserved(context, messages, strongSelf.chatInteraction.getMessages), for: context.window)
        }
        

        chatInteraction.deleteMessages = { [weak self] messageIds, morphSource in
            if let strongSelf = self, let peer = strongSelf.chatInteraction.peer {

                
                if let customChatContents {
                    customChatContents.deleteMessages(ids: messageIds)
                    strongSelf.chatInteraction.update({$0.withoutSelectionState()})
                    return
                }
                
                if strongSelf.chatInteraction.presentation.reportMode != nil {
                    strongSelf.changeState()
                    return
                }

                let channelAdmin:Promise<[ChannelParticipant]?> = Promise()
                let channelAdminDisposable = MetaDisposable()
                    
                if peer.isSupergroup {
                    let disposable = channelAdminDisposable
                    let result = context.peerChannelMemberCategoriesContextsManager.admins(peerId: peer.id, updated: { state in
                        switch state.loadingState {
                        case .ready:
                            channelAdmin.set(.single(state.list.map({$0.participant})))
                            disposable.dispose()
                        default:
                            break
                        }
                    })
                    disposable.set(ActionDisposable {
                        result.0.dispose()
                    })
                } else {
                    channelAdmin.set(.single(nil))
                }
            
                
                self?.messagesActionDisposable.set((combineLatest(context.account.postbox.messagesAtIds(messageIds) |> deliverOnMainQueue, channelAdmin.get() |> deliverOnMainQueue) |> afterDisposed {
                    channelAdminDisposable.dispose()
                }).start( next:{ [weak strongSelf] messages, admins in
                    if let strongSelf = strongSelf, let peer = strongSelf.chatInteraction.peer {
                        var canDelete:Bool = true
                        var canDeleteForEveryone = true
                        var allPeers:Set<PeerId> = Set()
                        _ = peer.id
                        var _mustDeleteForEveryoneMessage: Bool = true
                        for message in messages {
                            if !canDeleteMessage(message, account: context.account, chatLocation: chatLocation(), mode: mode, ranks: strongSelf.currentRanks) {
                                canDelete = false
                            }
                            if !mustDeleteForEveryoneMessage(message) {
                                _mustDeleteForEveryoneMessage = false
                            }
                            if !canDeleteForEveryoneMessage(message, context: context) {
                                canDeleteForEveryone = false
                                if let author = message.effectiveAuthor {
                                    if !allPeers.contains(author.id) {
                                        allPeers.insert(author.id)
                                    }
                                }
                            } else {
                                if message.effectiveAuthor?.id != context.peerId && !(context.limitConfiguration.canRemoveIncomingMessagesInPrivateChats && message.peers[message.id.peerId] is TelegramUser)  {
                                    if let peer = message.peers[message.id.peerId] as? TelegramGroup {
                                        inner: switch peer.role {
                                        case .member:
                                            if let author = message.effectiveAuthor {
                                                if !allPeers.contains(author.id) {
                                                    allPeers.insert(author.id)
                                                }
                                            }
                                        default:
                                            break inner
                                        }
                                    } else {
                                        if let author = message.effectiveAuthor {
                                            if !allPeers.contains(author.id) {
                                                allPeers.insert(author.id)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        
                        if peer.id == context.peerId {
                            canDeleteForEveryone = false
                        }
                        if messages.isEmpty {
                            strongSelf.chatInteraction.update({$0.withoutSelectionState()})
                            return
                        }
                        
                        if canDelete {
                            if mustManageDeleteMessages(messages, for: peer, account: context.account) {
                                if let channel = peer as? TelegramChannel {
                                    showModal(with: DeleteGroupMessagesController(context: context, channel: channel, messages: messages, allPeers: allPeers, onComplete: { [weak strongSelf] in
                                        strongSelf?.chatInteraction.update({$0.withoutSelectionState()})
                                    }), for: context.window, morphSource: morphSource)
                                }
                            } else {
                                
                                let successHandler: (ConfirmResult)->Void = { [weak strongSelf] result in
                                    
                                    guard let strongSelf = strongSelf else {return}
                                    
                                    let type:InteractiveMessagesDeletionType
                                    switch result {
                                    case .basic:
                                        type = .forLocalPeer
                                    case .thrid:
                                        type = .forEveryone
                                    }
                                    if let editingState = strongSelf.chatInteraction.presentation.interfaceState.editState {
                                        if messageIds.contains(editingState.message.id) {
                                            strongSelf.chatInteraction.cancelEditing()
                                        }
                                    }
                                    _ = context.engine.messages.deleteMessagesInteractively(messageIds: messageIds, type: type).start()
                                    strongSelf.chatInteraction.update({$0.withoutSelectionState()})
                                }
                                
                                if messages.count == 1, let giveaway = messages[0].media.first as? TelegramMediaGiveaway {
                                    let title = strings().chatGiveawayDeleteConfirmationTitle
                                    let info = strings().chatGiveawayDeleteConfirmationText(stringForFullDate(timestamp: giveaway.untilDate))
                                    verifyAlert(for: context.window, header: title, information: info, ok: strings().confirmDelete, cancel: strings().modalCancel, successHandler: successHandler)
                                } else {
                                    
                                    if messages.count == 1, messages[0].timestamp > context.timestamp + .secondsInDay, let attr = messages[0].publishedSuggestedPostMessageAttribute {
                                        let header: String
                                        let info: String

                                        switch attr.currency {
                                        case .ton:
                                            header = strings().chatDeleteMessageSuggestedPostHeaderTon
                                            info = strings().chatDeleteMessageSuggestedPostInfoTon
                                        case .stars:
                                            header = strings().chatDeleteMessageSuggestedPostHeaderStars
                                            info = strings().chatDeleteMessageSuggestedPostInfoStars
                                        }

                                        verifyAlert(for: context.window, header: header, information: info, ok: strings().chatDeleteMessageSuggestedPostActionDeleteAnyway, successHandler: successHandler)
                                    } else {
                                        let thrid:String? = strongSelf.mode == .scheduled ? nil : (canDeleteForEveryone ? peer.isUser ? strings().chatMessageDeleteForMeAndPerson(peer.compactDisplayTitle) : strings().chatConfirmDeleteMessagesForEveryone : nil)
                                        
                                        verifyAlert(for: context.window, header: thrid == nil ? strings().chatConfirmActionUndonable : strings().chatConfirmDeleteMessages1Other(messages.count), information: thrid == nil ? _mustDeleteForEveryoneMessage ? strings().chatConfirmDeleteForEveryoneOther(messages.count) : strings().chatConfirmDeleteMessages1Other(messages.count) : nil, ok: strings().confirmDelete, option: thrid, successHandler: successHandler)
                                    }
                                    
                                }
                            }
                        }
                    }
                }))
            }
        }
        
        let openInfo: (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void = { [weak self] peerId, toChat, postId, action in
            if let strongSelf = self {
                
                var album: Int32?
                var mediaMode: PeerMediaCollectionMode? = nil
                if case let .album(id, collection) = action {
                    album = id
                    mediaMode = collection
                } else {
                    album = nil
                }
                
                if toChat || action != nil, album == nil {
                    
                    if peerId == strongSelf.chatInteraction.peerId {
                        if let postId = postId {
                            var fromId: MessageId? = nil
                            var pollOptionId: Data? = nil
                            if let action = action {
                                switch action {
                                case let .source(id, _):
                                    fromId = id
                                case let .pollOption(optionData):
                                    pollOptionId = optionData
                                default:
                                    break
                                }
                            }
                            strongSelf.chatInteraction.focusMessageId(fromId, .init(messageId: postId, string: nil, pollOptionId: pollOptionId), TableScrollState.CenterEmpty)
                        }
                        if let action = action {
                            strongSelf.chatInteraction.update({ $0.updatedInitialAction(action) })
                            strongSelf.chatInteraction.invokeInitialAction()
                        }
                    } else {
                        if mode.isSavedMessagesThread {
                            ChatUIHooks.shared.navigateToChatObserved(strongSelf.navigationController, context, .peer(peerId), .init(messageId: postId), action, false)
                        } else {
                            ChatUIHooks.shared.navigateToChatObserved(strongSelf.navigationController, context, .peer(peerId), .init(messageId: postId), action, true)
                        }
                    }
                } else {
                    
                    let threadInfo: ThreadInfo? = strongSelf.chatInteraction.threadInfo(peerId, holder: strongSelf.chatLocationContextHolder)
                    
                    let stories: PeerExpiringStoryListContext?
                    if peerId == strongSelf.chatInteraction.peerId {
                        stories = strongSelf.stories
                    } else {
                        stories = nil
                    }
                    if let navigation = strongSelf.navigationController {
                        if mode.isSavedMessagesThread {
                            let controller = ChatUIHooks.shared.makePeerMediaControllerObserved(context, peerId, threadInfo: threadInfo, isBot: false)
                            navigation.push(controller)
                        } else {
                            ChatUIHooks.shared.pushPeerInfoObserved(navigation, context, peerId, threadInfo, stories, mediaMode, album)
                        }
                    }
                }
            }
        }
        
        chatInteraction.openInfo = { peerId, toChat, postId, action in
            openInfo(peerId, toChat, postId, action)
        }

        chatInteraction.showNextPost = { [weak self] in
            guard let `self` = self else {return}
            if let bottomVisibleRow = self.genericView.tableView.bottomVisibleRow {
                if bottomVisibleRow > 0 {
                    var item = self.genericView.tableView.item(at: bottomVisibleRow - 1)
                    if item.view?.visibleRect.height != item.view?.frame.height {
                        item = self.genericView.tableView.item(at: bottomVisibleRow)
                    }
                    self.genericView.tableView.scroll(to: .center(id: item.stableId, innerId: nil, animated: true, focus: .init(focus: true), inset: 0), inset: NSEdgeInsets(), toVisible: true)
                }
                
            }
        }
        
        self.chatInteraction.openPendingRequests = { [weak self] in
            if let importersContext = self?.tempImportersContext {
                self?.navigationController?.push(ChatNavigationHooks.shared.makeRequestJoinMemberListController(context, peerId, importersContext, { [weak self] in
                    self?.navigationController?.push(ChatNavigationHooks.shared.makeInviteLinksController(context, peerId, false))
                }))
            }
        }
        self.chatInteraction.dismissPendingRequests = { [weak self] peerIds in
            guard let `self` = self else {
                return
            }
            FastSettings.dismissPendingRequests(peerIds, for: self.chatInteraction.peerId)
            self.chatInteraction.update {
                $0.withUpdatedInviteRequestsPending(nil)
                    .withUpdatedInviteRequestsPendingPeers(nil)
            }
        }
        
        
        self.chatInteraction.setupChatThemes = { [weak self] in
            self?.showChatThemeSelector()
        }
        self.chatInteraction.closeChatThemes = { [weak self] in
            self?.closeChatThemesSelector()
        }
        
        chatInteraction.openStory = { [weak self] messageId, storyId in
            ChatUIHooks.shared.showSingleStoryObserved(context, storyId, .init(peerId: peerId, id: nil, messageId: messageId, takeControl: { peerId, messageId, storyId in
                return self?.findStoryControl(messageId, storyId, peerId)
            }), {
                showModalText(for: context.window, text: strings().storyErrorNotExist)
            })
        }
        
        chatInteraction.openChatPeerStories = { [weak self] messageId, peerId, setProgress in
            ChatUIHooks.shared.showStoriesObserved(context, false, .init(peerId: peerId, id: nil, messageId: messageId, takeControl: { peerId, messageId, storyId in
                return self?.findStoryControl(messageId, storyId, peerId, useAvatar: true)
            }, setProgress: setProgress), true)
        }
        
        chatInteraction.sendMessageShortcut = { item in
            if let shortcutId = item.id {
                context.engine.accountData.sendMessageShortcut(peerId: peerId, id: shortcutId)
            }
        }
        
        chatInteraction.openProxySettings = { [weak self] in
            let controller = ChatNavigationHooks.shared.makeProxyListController(context.sharedContext.accountManager, context.account.network, { [weak self] controller in
                 self?.navigationController?.push(controller)
            })
            self?.navigationController?.push(controller)
        }
        
        chatInteraction.inlineAudioPlayer = { [weak self] controller in
            ChatUIHooks.shared.showInlineAudioPlayer(controller, context, self?.genericView.tableView)
        }
        
        chatInteraction.searchPeerMessages = { [weak self] peer in
            guard let `self` = self else { return }
            self.chatInteraction.update({ current in
                return current.updatedSearchMode(.init(inSearch: true, peer: .init(peer), query: nil, tag: nil))
            })
        }
        chatInteraction.movePeerToInput = { [weak self] (peer) in
            if let strongSelf = self {
                let textInputState = strongSelf.chatInteraction.presentation.effectiveInput
                if let (range, _, _) = textInputStateContextQueryRangeAndType(textInputState, includeContext: false) {
                    let inputText = textInputState.inputText
                    
                    let name:String = peer.addressName ?? peer.compactDisplayTitle
                    
                    let distance = inputText.distance(from: range.lowerBound, to: range.upperBound)
                    let replacementText = name + " "
                    
                    let atLength = peer.addressName != nil ? 0 : 1
                    
                    let range = strongSelf.chatInteraction.appendText(replacementText, selectedRange: textInputState.selectionRange.lowerBound - distance - atLength ..< textInputState.selectionRange.upperBound)
                    
                    if peer.addressName == nil {
                        let state = strongSelf.chatInteraction.presentation.effectiveInput
                        var attributes = state.attributes
                        attributes.append(.uid(range.lowerBound ..< range.upperBound - 1, peer.id.id._internalGetInt64Value()))
                        let updatedState = ChatTextInputState(inputText: state.inputText, selectionRange: state.selectionRange, attributes: attributes)
                        strongSelf.chatInteraction.update({$0.withUpdatedEffectiveInputState(updatedState)})
                    }
                }
            }
        }
        
        
        chatInteraction.afterSentTransition = afterSentTransition
        
        chatInteraction.sendInlineResult = { [weak self] (results,result) in
            let deferredSendAction = self?.chatInteraction.captureDeferredSendAction()
            let confirmationAction = self?.chatInteraction.captureDeferredSendAction()
            if let strongSelf = self {
                let invoke:()->Void = { [weak strongSelf] in
                    guard confirmationAction?.takeIfCurrent() == true else { return }
                    guard let strongSelf = strongSelf else {
                        return
                    }
                    func apply(_ controller: ChatController, atDate: Int32?) {
                        let destinationPeerId = makePeerId()
                        guard let message = context.engine.messages.outgoingMessageWithChatContextResult(to: destinationPeerId, threadId: threadId64(), botId: results.botId, result: result, replyToMessageId: takeReplyId(), replyToStoryId: nil, hideVia: false, silentPosting: false, scheduleTime: atDate, sendPaidMessageStars: takePaidMessageStars(), postpone: false, correlationId: nil) else { return }
                        _ = (enqueueMessages(account: context.account, peerId: destinationPeerId, messages: [message])).start(next: { ids in
                        })
                        controller.nextTransaction.set(handler: afterSentTransition)
                    }
                    switch strongSelf.mode {
                    case .history, .thread, .customChatContents:
                        apply(strongSelf, atDate: nil)
                    case .scheduled:
                        if let peer = strongSelf.chatInteraction.peer {
                            showModal(with: chatDateSelector(context: context, mode: .schedule(peer.id), selectedAt: { [weak strongSelf] date, _ in
                                guard deferredSendAction?.takeIfCurrent() == true else { return }
                                if let strongSelf = strongSelf {
                                    apply(strongSelf, atDate: Int32(date.timeIntervalSince1970))
                                }
                            }), for: context.window)
                        }
                    case .pinned:
                        break
                    case .customLink:
                        break
                    case  .preview:
                        break
                    }
                }
                
                let chatInteraction = strongSelf.chatInteraction
                let presentation = chatInteraction.presentation
                let messagesCount = 1
                
                if let payStars = presentation.sendPaidMessageStars, let peer = presentation.peer, let starsState = presentation.starsState {
                    let starsPrice = Int(payStars.value * Int64(messagesCount))
                    let amount = strings().starListItemCountOther(starsPrice)
                    
                    if !presentation.alwaysPaidMessage {
                        
                        let messageCountText = strings().chatPayStarsConfirmMessagesOther(messagesCount)
                        
                        verifyChatSendPayment(for: chatInteraction.interactionContext.window, header: strings().chatPayStarsConfirmTitle, information: strings().chatPayStarsConfirmText(peer.displayTitle, amount, amount, messageCountText), ok: strings().chatPayStarsConfirmPayOther(messagesCount), option: strings().chatPayStarsConfirmCheckbox, successHandler: { result in
                            guard chatPaidMessagePriceIsCurrent(chatInteraction, payStars) else { return }
                            if starsState.balance.value > starsPrice {
                                chatInteraction.update({ current in
                                    return current
                                        .withUpdatedAlwaysPaidMessage(result == .thrid)
                                })
                                if result == .thrid {
                                    FastSettings.toggleCofirmPaid(peer.id, price: Int(payStars.value))
                                }
                                invoke()
                            } else {
                                FeatureNavigationHooks.shared.showStarsPurchaseWithContext(context, context.window, .stars, nil, Int64(starsPrice))
                            }
                        })
                        
                    } else {
                        if starsState.balance.value > starsPrice {
                            invoke()
                        } else {
                            FeatureNavigationHooks.shared.showStarsPurchaseWithContext(context, context.window, .stars, nil, Int64(starsPrice))
                        }
                    }
                } else {
                    invoke()
                }
                
            }
            
        }
        
        chatInteraction.beginEditingMessage = { [weak self] message in

            // Rich messages (composed in the rich-text editor) can't be edited in the inline input — open
            // them back in the editor, pre-seeded with their content.
            if #available(macOS 12, *), let self = self, let message = message, message.attributes.contains(where: { $0 is RichTextMessageAttribute }) {
                showRichTextEditor(chatInteraction: self.chatInteraction, editing: message)
                return
            }

            let process:()->Void = { [weak self] in
                if let message = message {
                    self?.chatInteraction.update({ state in
                        var state = state
                        state = state.withEditMessage(message)
                        
                        if let suggestAttr = message.suggestPostAttribute {
                            state = state.updatedInterfaceState({
                                return $0.withUpdatedSuggestPost(.init(amount: suggestAttr.amount, date: suggestAttr.timestamp, mode: message.effectivelyIncoming(context.peerId) ? .suggest(message.id) : .edit(message.id)))
                            })
                        }
                        
                        if let attribute = message.webpagePreviewAttribute {
                            state = state.updatedInterfaceState { current in
                                var current = current
                                current = current.withUpdatedLinkBelowMessage(!attribute.leadingPreview)
                                if let forceLargeMedia = attribute.forceLargeMedia {
                                    current = current.withUpdatedLargeMedia(forceLargeMedia)
                                }
                                return current
                            }
                        }
                        if !context.isPremium && context.peerId != peerId {
                            state = state.updatedInterfaceState { interfaceState in
                                var interfaceState = interfaceState
                                interfaceState = interfaceState.updatedEditState { editState in
                                    if let editState = editState {
                                        return editState.withUpdated(state: editState.inputState.withoutAnimatedEmoji)
                                    }
                                    return editState
                                }
                                return interfaceState
                            }
                        }
                        return state
                    })
                } else {
                    self?.chatInteraction.cancelEditing(true)
                }
                self?.chatInteraction.focusInputField()
            }
            
            if let message, message.media.first is TelegramMediaTodo, let self {
                ChatNavigationHooks.shared.showNewTodo(self.chatInteraction, .edit(message, taskId: nil), context.window, nil)
                return
            }
            
            if let editState = self?.chatInteraction.presentation.interfaceState.editState, let window = self?.window, let _ = message  {
                if editState.inputState.inputText != editState.message.text {
                    verifyAlert_button(for: window, information: strings().chatEditCancelText, ok: strings().alertDiscard, successHandler: { _ in
                        process()
                    })
                } else {
                    process()
                }
            } else {
                process()
            }
        }
        
        chatInteraction.appendTask = { [weak self] message in
            guard let self else {
                return
            }
            if !context.isPremium {
                showModalText(for: context.window, text: strings().chatServiceTodoCompletePremium, callback: { _ in
                    prem(with: PremiumBoardingController(context: context, source: .todo, openFeatures: true), for: context.window)
                })
            } else {
                ChatNavigationHooks.shared.showNewTodo(self.chatInteraction, .addOption(message), context.window, nil)
            }
        }
        
        chatInteraction.mentionPressed = { [weak self] in
            guard let self else { return }
            self.cancelMessageFocus()
            let requestId = self.messageFocusRequestId
            let chatLocation = self.chatLocation
            let locationTag = self.locationValue?.tag
            let signal = context.engine.messages.earliestUnseenPersonalMentionMessage(peerId: peerId, threadId: chatLocation.threadId)
            self.navigationActionDisposable.set((signal |> deliverOnMainQueue).start(next: { [weak self] result in
                guard let self, self.messageFocusRequestId == requestId,
                      self.chatLocation == chatLocation, self.locationValue?.tag == locationTag else { return }
                switch result {
                case .loading:
                    break
                case .result(let messageId):
                    if let messageId {
                        self.chatInteraction.focusMessageId(nil, .init(messageId: messageId, string: nil), .CenterEmpty)
                    }
                }
            }))
        }
        
        chatInteraction.clearMentions = { [weak self] in
            guard let `self` = self else {return}
            self.cancelMessageFocus()
            _ = clearPeerUnseenPersonalMessagesInteractively(account: context.account, peerId: self.chatInteraction.peerId, threadId: chatLocation().threadId).start()
        }
        
        chatInteraction.clearReactions = { [weak self] in
            guard let `self` = self else {return}
            self.cancelMessageFocus()
            _ = clearPeerUnseenReactionsAndPollVotesInteractively(account: context.account, peerId: self.chatInteraction.peerId, threadId: chatLocation().threadId).start()
        }
        
        chatInteraction.reactionPressed = { [weak self] in
            guard let self else { return }
            self.cancelMessageFocus()
            let requestId = self.messageFocusRequestId
            let chatLocation = self.chatLocation
            let locationTag = self.locationValue?.tag
            let signal = context.engine.messages.earliestUnseenPersonalReactionMessage(peerId: self.chatInteraction.peerId, threadId: chatLocation.threadId)
            self.navigationActionDisposable.set((signal |> deliverOnMainQueue).start(next: { [weak self] result in
                guard let self, self.messageFocusRequestId == requestId,
                      self.chatLocation == chatLocation, self.locationValue?.tag == locationTag else { return }
                switch result {
                case .loading:
                    break
                case .result(let messageId):
                    if let messageId {
                        self.chatInteraction.focusMessageId(nil, .init(messageId: messageId, string: nil), .CenterEmpty)
                    }
                }
            }))
        }
        
        chatInteraction.editEditingMessagePhoto = { [weak self] media in
            guard let self, let editState = self.chatInteraction.presentation.interfaceState.editState else { return }
            let messageId = editState.message.id
            let replacement = self.chatInteraction.beginMediaReplacement()
            if let resource = media.representationForDisplayAtSize(PixelDimensions(1280, 1280))?.resource {
                let disposables = DisposableSet()
                self.editCurrentMessagePhotoDisposable.set(disposables)
                self.updateMediaDisposable.set(nil)
                disposables.add(fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .peer(peerId), userContentType: .image, reference: .media(media: .message(message: MessageReference(editState.message), media: media), resource: resource)).start())
                disposables.add((context.account.postbox.mediaBox.resourceData(resource) |> filter { $0.complete } |> take(1) |> deliverOnMainQueue).start(next: { [weak self] resource in
                    guard let self, self.chatInteraction.isCurrentMediaReplacement(replacement) else { return }
                    guard let path = link(path: resource.path, ext: kMediaImageExt) else {
                        self.chatInteraction.failMediaReplacement(replacement)
                        return
                    }
                    let url = URL(fileURLWithPath: path)
                    let editResult = ChatNavigationHooks.shared.editImageObserved(context, url, editState.editedData, cancelled: { [weak self] in
                        self?.chatInteraction.cancelMediaReplacement(replacement)
                    }, dismissed: { [weak self] in
                        self?.chatInteraction.discardMediaReplacement(replacement)
                    })
                    disposables.add((editResult |> deliverOnMainQueue).start(next: { [weak self] (new, data) in
                        guard let self, self.chatInteraction.isCurrentMediaReplacement(replacement) else { return }
                        self.chatInteraction.update({$0.updatedInterfaceState({$0.updatedEditState({$0?.withUpdatedEditedData(data)})})})
                        if new != url {
                            self.updateMediaDisposable.set((Sender.generateMedia(for: MediaSenderContainer(path: new.path, isFile: false), account: context.account, isSecretRelated: peerId.namespace == Namespaces.Peer.SecretChat) |> deliverOnMainQueue).start(next: { [weak self] media, _ in
                                guard let self, self.chatInteraction.isCurrentMediaReplacement(replacement) else { return }
                                self.chatInteraction.applyMediaReplacement(media, request: replacement)
                            }))
                        } else {
                            self.chatInteraction.applyMediaReplacement(media, request: replacement)
                        }
                        
                    }))
                }))
            } else {
                self.chatInteraction.failMediaReplacement(replacement)
            }
        }
        
        
        chatInteraction.requestMessageActionCallback = { [weak self] messageId, isGame, data in
            if let strongSelf = self {
                switch strongSelf.mode {
                case .history, .thread, .customChatContents:
                    let applyResult:(MessageActionCallbackResult) -> Void = { [weak strongSelf] result in
                        if let strongSelf = strongSelf {
                            switch result {
                            case .none:
                                strongSelf.botCallbackAlertMessage.set(.single(("", false)))
                            case let .toast(text):
                                strongSelf.botCallbackAlertMessage.set(.single((text, false)))
                            case let .alert(text):
                                strongSelf.botCallbackAlertMessage.set(.single((text, true)))
                            case let .url(url):
                                if isGame {
                                    ChatNavigationHooks.shared.openBrowserTab(context, .game(url: url, peerId: strongSelf.chatInteraction.peerId, messageId: messageId))
                                } else {
                                    LinkHooks.shared.openExternalLink(url, !(strongSelf.chatInteraction.peer?.isVerified ?? false))
                                }
                            }
                        }
                    }
                    strongSelf.botCallbackAlertMessage.set(.single((strings().chatInlineRequestLoading, false)))
                    strongSelf.messageActionCallbackDisposable.set((context.engine.messages.requestMessageActionCallback(messageId: messageId, isGame:isGame, password: nil, data: data?.data) |> deliverOnMainQueue).start(next: applyResult, error: { [weak strongSelf] error in
                        
                        strongSelf?.botCallbackAlertMessage.set(.single(("", false)))
                        if let data = data, data.requiresPassword {
                            var errorText: String? = nil
                            var install2Fa = false
                            switch error {
                            case .invalidPassword:
                                showModal(with: InputPasswordController(context: context, title: strings().botTransferOwnershipPasswordTitle, desc: strings().botTransferOwnershipPasswordDesc, checker: { pwd in
                                    return context.engine.messages.requestMessageActionCallback(messageId: messageId, isGame: isGame, password: pwd, data: data.data)
                                        |> deliverOnMainQueue
                                        |> beforeNext { result in
                                            applyResult(result)
                                        }
                                        |> ignoreValues
                                        |> `catch` { error -> Signal<Never, InputPasswordValueError> in
                                            switch error {
                                            case .generic:
                                                return .fail(.generic)
                                            case .invalidPassword:
                                                return .fail(.wrong)
                                            default:
                                                return .fail(.generic)
                                            }
                                    } 
                                }), for: context.window)
                            case .authSessionTooFresh:
                                errorText = strings().botTransferOwnerErrorText
                            case .twoStepAuthMissing:
                                errorText = strings().botTransferOwnerErrorText
                                install2Fa = true
                            case .twoStepAuthTooFresh:
                                errorText = strings().botTransferOwnerErrorText
                            default:
                                break
                            }
                            if let errorText = errorText {
                                verifyAlert_button(for: context.window, header: strings().botTransferOwnerErrorTitle, information: errorText, ok: strings().modalOK, cancel: strings().modalCancel, option: install2Fa ? strings().botTransferOwnerErrorEnable2FA : nil, successHandler: { result in
                                    switch result {
                                    case .basic:
                                        break
                                    case .thrid:
                                        ChatNavigationHooks.shared.pushTwoStepVerificationUnlock(context, { (controller, isRoot, animated) in
                                            let navigation = context.bindings.rootNavigation()
                                            if isRoot {
                                                navigation.removeUntil(ChatController.self)
                                            }
                                            if !animated {
                                                navigation.stackInsert(controller, at: navigation.stackCount)
                                            } else {
                                                navigation.push(controller)
                                            }
                                        })
                                    }
                                })
                            }
                        }
                        
                    }))
                case .scheduled:
                    break
                case .pinned:
                    break
                case .customLink:
                    break
                case .preview:
                    break
                }
                
            }
        }
        
        chatInteraction.updateSearchRequest = { [weak self] state in
            self?.searchState.set(state)
        }
        
        chatInteraction.setLocation = { [weak self] location in
            self?.setLocation(location)
        }
        
        chatInteraction.setLocationTag = { [weak self] tag in
            guard let `self` = self else {
                return
            }
            self.chatInteraction.update { current in
                return current.updatedSearchMode(.init(inSearch: true, peer: current.searchMode.peer, query: current.searchMode.query, tag: tag == current.searchMode.tag ? nil : tag))
            }
            
        }
        
        chatInteraction.revealFactCheck = { [weak self] messageId in
            self?.updateState { current in
                var current = current
                if current.factCheck.contains(messageId) {
                    current.factCheck.remove(messageId)
                } else {
                    current.factCheck.insert(messageId)
                }
                return current
            }
        }

        chatInteraction.togglePollSolution = { [weak self] messageId in
            self?.updateState { current in
                var current = current
                if current.solutionRevealed.contains(messageId) {
                    current.solutionRevealed.remove(messageId)
                } else {
                    current.solutionRevealed.insert(messageId)
                }
                return current
            }
        }
        
        
        chatInteraction.scrollToTheFirst = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.cancelMessageFocus()
            let requestId = strongSelf.messageFocusRequestId
            let chatLocation = strongSelf.chatLocation
            let locationTag = strongSelf.locationValue?.tag
            
            let scroll: ChatHistoryLocation = .Scroll(index: .lowerBound, anchorIndex: .lowerBound, sourceIndex: .lowerBound, scrollPosition: .up(true), count: 50, animated: true)
            
            let historyView = preloadedChatHistoryViewForLocation(scroll, context: context, chatLocation: chatLocation, chatLocationContextHolder: strongSelf.chatLocationContextHolder, tag: locationTag, additionalData: [])
            
            
            let signal = historyView
            |> mapToSignal { historyView -> Signal<(MessageIndex?, Bool), NoError> in
                switch historyView {
                case .Loading:
                    return .single((nil, true))
                case .HistoryView:
                    return .single((nil, false))
                }
            }
            |> take(until: { index in
                return SignalTakeAction(passthrough: !index.1, complete: !index.1)
            })

            
            strongSelf.chatInteraction.loadingMessage.set(.single(true) |> delay(0.2, queue: Queue.mainQueue()))
            strongSelf.messageIndexDisposable.set(showModalProgress(signal: signal, for: context.window).start(next: { [weak strongSelf] _ in
                guard let strongSelf, strongSelf.messageFocusRequestId == requestId,
                      strongSelf.chatLocation == chatLocation, strongSelf.locationValue?.tag == locationTag else { return }
                strongSelf.setLocation(scroll)
            }, completed: { [weak strongSelf] in
                guard let strongSelf, strongSelf.messageFocusRequestId == requestId else { return }
                strongSelf.chatInteraction.loadingMessage.set(.single(false))
            }))
        }
        
        chatInteraction.openFocusedMedia = { [weak self] timemark in
            if let focusTarget = self?.focusTarget {
                self?.genericView.tableView.enumerateItems(with: { item in
                    if let item = item as? ChatMediaItem, item.message?.id == focusTarget.messageId {
                        item.openMedia(timemark)
                        return false
                    }
                    return true
                })
            }
        }
        
        chatInteraction.focusPinnedMessageId = { [weak self] messageId in
            self?.chatInteraction.focusMessageId(nil, .init(messageId: messageId, string: nil), .CenterActionEmpty { [weak self] _ in
                self?.chatInteraction.update({$0.withUpdatedTempPinnedMaxId(messageId)})
            })
        }
        
        chatInteraction.toggleUnderMouseMessage = { [weak self] in
            if let event = NSApp.currentEvent, let `self` = self {
                let point = self.genericView.tableView.contentView.convert(event.locationInWindow, from: nil)
                let row = self.genericView.tableView.row(at: point)
                if row != -1 {
                    let item = self.genericView.tableView.item(at: row)
                    (item as? ChatRowItem)?.toggleSelect()
                }
            }
        }
        
        chatInteraction.runPremiumScreenEffect = { [weak self] message, mirror, isIncoming in
            guard let strongSelf = self else {
                return
            }
            let messageId = message.id
            if strongSelf.isOnScreen {
                strongSelf.emojiEffects.addPremiumEffect(mirror: mirror, isIncoming: isIncoming, messageId: messageId, viewFrame: context.window.bounds, for: context.window.contentView!)
            }
        }
        chatInteraction.runEmojiScreenEffect = { [weak self] emoji, message, mirror, isIncoming in
            guard let strongSelf = self else {
                return
            }
            let messageId = message.id
            if strongSelf.isOnScreen {
                strongSelf.emojiEffects.addAnimation(emoji.fixed, index: nil, mirror: mirror, isIncoming: isIncoming, messageId: messageId, animationSize: NSMakeSize(350, 350), viewFrame: context.window.bounds, for: context.window.contentView!)
            }
        }
        
        chatInteraction.runReactionEffect = { [weak self] value, messageId, isLarge in
            guard let strongSelf = self else {
                return
            }
            if strongSelf.isOnScreen {
                strongSelf.emojiEffects.addReactionAnimation(value, index: nil, messageId: messageId, animationSize: NSMakeSize(80, 80), isLarge: isLarge, viewFrame: context.window.bounds, for: context.window.contentView!)
            }
        }
        
        chatInteraction.toggleSendAs = { updatedPeerId in
            _ = context.engine.peers.updatePeerSendAsPeer(peerId: peerId, sendAs: updatedPeerId).start()
        }
        
        chatInteraction.focusMessageId = { [weak self] fromId, focusTarget, state in

            if let strongSelf = self {
                strongSelf.cancelMessageFocus()
                let requestId = strongSelf.messageFocusRequestId
                let chatLocation = strongSelf.chatLocation
                let locationTag = strongSelf.locationValue?.tag

                if focusTarget.messageId.peerId != strongSelf.chatInteraction.peerId {
                    let peer = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: focusTarget.messageId.peerId)) |> deliverOnMainQueue
                    strongSelf.focusMessageDisposable.set(peer.start(next: { [weak strongSelf] value in
                        guard let strongSelf, strongSelf.messageFocusRequestId == requestId else {
                            return
                        }
                        let accept: Bool
                        if let value = value {
                            switch value {
                            case let .channel(channel):
                                accept = channel.participationStatus == .member || value.addressName != nil
                            case let .legacyGroup(group):
                                accept = group.membership == .Member || value.addressName != nil
                            default:
                                accept = false
                            }

                        } else {
                            accept = false
                        }
                        if accept {
                            strongSelf.navigationController?.push(ChatAdditionController(context: context, chatLocation: .peer(focusTarget.messageId.peerId), focusTarget: focusTarget))
                        } else {
                            let text: String
                            if let peer = value {
                                if peer._asPeer().isChannel {
                                    text = strings().chatToastQuoteChatUnavailbalePrivateChannel
                                } else if peer._asPeer().isGroup || peer._asPeer().isSupergroup {
                                    text = strings().chatToastQuoteChatUnavailbalePrivateGroup
                                } else {
                                    text = strings().chatToastQuoteChatUnavailbalePrivateChat
                                }
                            } else {
                                text = strings().chatToastQuoteChatUnavailbalePrivateChat
                            }
                            showModalText(for: context.window, text: text)
                        }
                    }))
                    return
                }

                switch strongSelf.mode {
                case .history, .thread, .customChatContents:
                    var fromIndex: MessageIndex?
                    let innerId: AnyHashable?

                    if let fromId = fromId, let message = strongSelf.messageInCurrentHistoryView(fromId) {
                        fromIndex = MessageIndex(message)
                    } else {
                        if let message = strongSelf.anchorMessageInCurrentHistoryView() {
                            fromIndex = MessageIndex(message)
                        }
                    }
                    if let pollOptionData = focusTarget.pollOptionId {
                        innerId = pollOptionData
                    } else if let fromId = fromId, let message = strongSelf.messageInCurrentHistoryView(fromId) {
                        switch message.replyAttribute?.innerSubject {
                        case let .todoItem(id):
                            innerId = id
                        case let .pollOption(data):
                            innerId = data
                        case nil:
                            innerId = nil
                        }
                    } else {
                        innerId = nil
                    }
                    let historyView = preloadedChatHistoryViewForLocation(.InitialSearch(location: .id(focusTarget.messageId, focusTarget.string, focusTarget.range), count: strongSelf.requestCount), context: context, chatLocation: chatLocation, chatLocationContextHolder: strongSelf.chatLocationContextHolder, tag: locationTag, additionalData: [])


                    let signal = historyView
                        |> mapToSignal { historyView -> Signal<(Message?, Bool), NoError> in
                            switch historyView {
                            case .Loading:
                                return .single((nil, true))
                            case let .HistoryView(view, _, _, _):
                                for entry in view.entries {
                                    if entry.message.id == focusTarget.messageId {
                                        return .single((entry.message, false))
                                    }
                                }
                                return .single((nil, false))
                            }
                        } |> take(until: { index in
                            return SignalTakeAction(passthrough: index.0 != nil, complete: !index.1)
                        }) |> map { $0.0 }

                    strongSelf.chatInteraction.loadingMessage.set(.single(true) |> delay(0.2, queue: Queue.mainQueue()))
                    strongSelf.messageIndexDisposable.set(showModalProgress(signal: signal, for: context.window).start(next: { [weak strongSelf] message in
                        guard let strongSelf, strongSelf.messageFocusRequestId == requestId,
                              strongSelf.chatLocation == chatLocation, strongSelf.locationValue?.tag == locationTag else {
                            return
                        }
                        strongSelf.chatInteraction.loadingMessage.set(.single(false))
                        if let message {
                            if let fromId {
                                strongSelf.historyState = strongSelf.historyState.withAddingReply(fromId)
                            }
                            let toIndex = MessageIndex(message)
                            let fromIndex = fromIndex ?? toIndex
                            let locationId = strongSelf.takeNextHistoryLocationId()
                            let requestCount = strongSelf.requestCount
                            let scroll = state
                                .swap(to: ChatHistoryEntryId.message(message)).text(string: focusTarget.string, range: focusTarget.range, innerId: innerId)
                                .focus(action: { [weak strongSelf] view in
                                    guard let strongSelf, strongSelf.messageFocusRequestId == requestId,
                                          strongSelf.chatLocation == chatLocation, strongSelf.locationValue?.tag == locationTag else {
                                        return
                                    }
                                    if strongSelf.locationValue?.id == locationId {
                                        let content: ChatHistoryLocation = .Scroll(index: .message(toIndex), anchorIndex: .message(toIndex), sourceIndex: .message(fromIndex), scrollPosition: .none(nil), count: requestCount, animated: state.animated)
                                        strongSelf.setLocation(content)
                                    }
                                    state.action?(view)
                                })
                            let content: ChatHistoryLocation = .Scroll(index: .message(toIndex), anchorIndex: .message(toIndex), sourceIndex: .message(fromIndex), scrollPosition: scroll, count: requestCount, animated: state.animated)
                            strongSelf.setLocation(.init(content: content, chatLocation: chatLocation, tag: locationTag, id: locationId))
                        }
                    }, completed: { [weak strongSelf] in
                        guard let strongSelf, strongSelf.messageFocusRequestId == requestId else {
                            return
                        }
                        strongSelf.chatInteraction.loadingMessage.set(.single(false))
                    }))
                case .scheduled:
                    strongSelf.navigationController?.back()
                    (strongSelf.navigationController?.controller as? ChatController)?.chatInteraction.focusMessageId(fromId, focusTarget, state)
                case .pinned:
                    break
                case .customLink:
                    break
                case .preview:
                    break
                }
            }

        }

        chatInteraction.vote = { [weak self] messageId, opaqueIdentifiers, submit in
            guard let `self` = self else {return}
            
            self.updateState { state in
                var state = state
                var data = state.pollAnswers
                data[messageId] = ChatPollStateData(identifiers: opaqueIdentifiers, isLoading: submit && !opaqueIdentifiers.isEmpty)
                state.pollAnswers = data
                return state
            }
            
            let signal:Signal<TelegramMediaPoll?, RequestMessageSelectPollOptionError>

            if submit {
                if opaqueIdentifiers.isEmpty {
                    signal = showModalProgress(signal: (context.engine.messages.requestMessageSelectPollOption(messageId: messageId, opaqueIdentifiers: []) |> deliverOnMainQueue), for: context.window)
                } else {
                    signal = (context.engine.messages.requestMessageSelectPollOption(messageId: messageId, opaqueIdentifiers: opaqueIdentifiers) |> deliverOnMainQueue)
                }
                
                self.selectMessagePollOptionDisposables.set(signal.start(next: { [weak self] poll in
                    if let poll = poll {
                        self?.updateState { state in
                            var state = state
                            var data = state.pollAnswers
                            data.removeValue(forKey: messageId)
                            state.pollAnswers = data
                            return state
                        }
                        var once: Bool = true
                        self?.afterNextTransaction = { [weak self] in
                            if let tableView = self?.genericView.tableView, once {
                                tableView.enumerateItems(with: { item -> Bool in
                                    if let item = item as? ChatRowItem, let message = item.message, message.id == messageId, let `self` = self {
                                        
                                        let entry = item.entry.withUpdatedMessageMedia(poll)
                                        let size = self.atomicSize.with { $0 }
                                        let updatedItem = ChatRowItem.item(size, from: entry, interaction: self.chatInteraction, theme: theme)

                                        _ = updatedItem.makeSize(size.width, oldWidth: 0)

                                        tableView.merge(with: .init(deleted: [], inserted: [], updated: [(item.index, updatedItem)], animated: true))
                                        
                                        delay(0.25, closure: { [weak self] in
                                            if let location = self?._locationValue.with({$0}) {
                                                self?.setLocation(location)
                                            }
                                        })
                                        
                                        let view = item.view as? ChatPollItemView
                                        if let view = view, view.window != nil, view.visibleRect != .zero {
                                            view.doAfterAnswer()
                                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted)
                                        }
                                        return false
                                    }
                                    return true
                                })
                                once = false
                            }
                        }
                        
                        if opaqueIdentifiers.isEmpty {
                            self?.afterNextTransaction?()
                        }
                    }

                }, error: { [weak self] error in
                    switch error {
                    case .generic:
                        let restrictionSignal = context.account.postbox.transaction { transaction -> String? in
                            guard let message = transaction.getMessage(messageId) else {
                                return nil
                            }
                            guard let poll = message.anyMedia as? TelegramMediaPoll else {
                                return nil
                            }
                            return pollVoteRestrictionText(poll: poll, chatPeer: message.peers[message.id.peerId])
                        } |> deliverOnMainQueue
                        _ = restrictionSignal.start(next: { text in
                            if let text {
                                showModalText(for: context.window, text: text)
                            } else {
                                alert(for: context.window, info: strings().unknownError)
                            }
                        })
                    case .restrictedToSubscribers:
                        let restrictionSignal = context.account.postbox.transaction { transaction -> String? in
                            guard let message = transaction.getMessage(messageId) else {
                                return nil
                            }
                            guard let poll = message.anyMedia as? TelegramMediaPoll else {
                                return nil
                            }
                            return pollVoteRestrictionText(poll: poll, chatPeer: message.peers[message.id.peerId])
                        } |> deliverOnMainQueue
                        _ = restrictionSignal.start(next: { text in
                            if let text {
                                showModalText(for: context.window, text: text)
                            } else {
                                alert(for: context.window, info: strings().unknownError)
                            }
                        })
                    }
                    self?.updateState { state in
                        var state = state
                        var data = state.pollAnswers
                        data.removeValue(forKey: messageId)
                        state.pollAnswers = data
                        return state
                    }

                }), forKey: messageId)
            }
            
        }
        chatInteraction.closePoll = { [weak self] messageId in
            guard let `self` = self else {return}
            self.selectMessagePollOptionDisposables.set(context.engine.messages.requestClosePoll(messageId: messageId).start(), forKey: messageId)
        }

        chatInteraction.addPollOption = { [weak self] messageId, pollOption in
            guard let `self` = self else { return }
            self.selectMessagePollOptionDisposables.set(context.engine.messages.addPollOption(messageId: messageId, text: pollOption.text, entities: pollOption.entities, mediaReference: pollOption.media.flatMap( { AnyMediaReference.standalone(media:$0) })).start(), forKey: messageId)
        }

        chatInteraction.deletePollOption = { [weak self] messageId, opaqueIdentifier in
            guard let `self` = self else { return }
            self.selectMessagePollOptionDisposables.set(context.engine.messages.deletePollOption(messageId: messageId, opaqueIdentifier: opaqueIdentifier).start(), forKey: messageId)
        }

        chatInteraction.revealMedia = { [weak self] message in
            
            if message.isSensitiveContent(platform: "ios") {
                
                if !context.contentConfig.sensitiveContentEnabled, context.contentConfig.canAdjustSensitiveContent {
                    let need_verification = context.appConfiguration.getBoolValue("need_age_video_verification", orElse: false)
                    
                    if need_verification {
                        ChatNavigationHooks.shared.showVerifyAgeAlert(context, context.window)
                        return
                    }
                }
                if context.contentConfig.sensitiveContentEnabled {
                    self?.updateState { current in
                        var current = current
                        current.mediaRevealed.insert(message.id)
                        return current
                    }
                } else {
                    verifyAlert(for: context.window, header: strings().chatSensitiveContent, information: strings().chatSensitiveContentConfirm, ok: strings().chatSensitiveContentConfirmOk, option: context.contentConfig.canAdjustSensitiveContent ? strings().chatSensitiveContentConfirmThird : nil, optionIsSelected: false, successHandler: { result in
                        self?.updateState { current in
                            var current = current
                            current.mediaRevealed.insert(message.id)
                            return current
                        }
                        if result == .thrid {
                            let _ = updateRemoteContentSettingsConfiguration(postbox: context.account.postbox, network: context.account.network, sensitiveContentEnabled: true).start()
                            let messages = self?.historyView?.originalView?.entries.compactMap { $0.message } ?? []
                            self?.updateState { current in
                                var current = current
                                for message in messages {
                                    current.mediaRevealed.insert(message.id)
                                }
                                return current
                            }
                        }
                    })
                }
            } else {
                self?.updateState { current in
                    var current = current
                    current.mediaRevealed.insert(message.id)
                    return current
                }
            }
            
        }
        chatInteraction.openStories = { [weak self] f, setProgress in
            let state = self?.uiState.with ({ $0.storyState })
            if let _ = state {
                ChatUIHooks.shared.showStoriesObserved(context, false, .init(peerId: peerId, id: nil, messageId: nil, takeControl: f, setProgress: setProgress), true)
            }
        }
        
        chatInteraction.toggleTranslate = { [weak self] in
            let enabled = self?.uiState.with { $0.translate?.translate } == true
            if !context.isPremium && !enabled {
                prem(with: PremiumBoardingController(context: context, source: .translations, openFeatures: true), for: context.window)
            } else {
                if !enabled {
                }
                self?.liveTranslate?.toggleTranslate()
            }
            self?.genericView.tableView.notifyScrollHandlers()
        }
        chatInteraction.hideTranslation = { [weak self] in
            if !context.isPremium {
                self?.liveTranslate?.disablePaywall()
                showModalText(for: context.window, text: strings().chatTranslateMenuHidePaywallTooltip)
            } else {
                self?.liveTranslate?.hideTranslation()
                if let peer = self?.chatInteraction.peer {
                    let text: String
                    if peer.isUser {
                        text = strings().chatTranslateMenuHideUserTooltip
                    } else if peer.isChannel {
                        text = strings().chatTranslateMenuHideChannelTooltip
                    } else if peer.isBot {
                        text = strings().chatTranslateMenuHideBotTooltip
                    } else {
                        text = strings().chatTranslateMenuHideGroupTooltip
                    }
                    showModalText(for: context.window, text: text)
                }
            }
        }
        chatInteraction.doNotTranslate = { code in
            _ = updateBaseAppSettingsInteractively(accountManager: context.sharedContext.accountManager, { settings in
                var current = settings.doNotTranslate
                if !current.contains(code) {
                    current.insert(code)
                }
                return settings.withUpdatedDoNotTranslate(current)
            }).start()
        }
        
        chatInteraction.sendMedia = { [weak self] media in
            if customChatContents != nil {
            }
            if media.isEmpty {
                self?.chatInteraction.voiceSendFlight?.cancel()
                return
            }
            if let strongSelf = self, let peer = strongSelf.chatInteraction.peer {
                let currentSendAsPeerId = strongSelf.chatInteraction.presentation.currentSendAsPeerId
                switch strongSelf.mode {
                case .scheduled:
                    strongSelf.chatInteraction.voiceSendFlight?.cancel()
                    FeatureNavigationHooks.shared.selectDateObserved(strongSelf.context, strongSelf.context.window, nil, nil, .schedule(peer.id), selectedAt: { [weak strongSelf] date, repeatPeriod in
                        if let strongSelf = strongSelf {
                            let destination = makePeerId()
                            let _ = (Sender.enqueue(media: media, context: context, peerId: destination, replyId: takeReplyId(), threadId: threadId64(), atDate: date, repeatPeriod: repeatPeriod, sendAsPeerId: currentSendAsPeerId, customChatContents: customChatContents, sendPaidMessageStars: takePaidMessageStars()) |> deliverOnMainQueue).start(next: { ids in
                            }, completed: {
                                scrollAfterSend()
                            })
                            strongSelf.nextTransaction.set(handler: afterSentTransition)
                        } else {
                        }
                    }, cancelled: { [weak strongSelf] in
                    }, dismissed: {
                    })
                case .history, .thread, .customChatContents:
                    let _ = (Sender.enqueue(media: media, context: context, peerId: peerId, replyId: takeReplyId(), threadId: threadId64(), sendAsPeerId: currentSendAsPeerId, customChatContents: customChatContents, sendPaidMessageStars: takePaidMessageStars()) |> deliverOnMainQueue).start(next: { ids in
                    }, completed: {
                        scrollAfterSend()
                    })
                    strongSelf.nextTransaction.set(handler: afterSentTransition)
                case .pinned, .customLink, .preview:
                    break
                }
            } else {
            }
        }
        
        chatInteraction.attachFile = { [weak self] asMedia in
            if let `self` = self, let window = self.window {
                let selectionAction = self.chatInteraction.captureDeferredSendAction()
                if let slowMode = self.chatInteraction.presentation.slowMode, let errorText = slowMode.errorText {
                    tooltip(for: self.genericView.inputView.attachView, text: errorText)
                    if let last = slowMode.sendingIds.last {
                        self.chatInteraction.focusMessageId(nil, .init(messageId: last, string: nil), .CenterEmpty)
                    }
                } else if let peer = self.chatInteraction.peer {
                    
                    let canSend = peer.canSendMessage(self.mode.isThreadMode, threadData: self.chatInteraction.presentation.threadInfo, cachedData: self.chatInteraction.presentation.cachedData)

                    
                    if canSend {
                        filePanel(allowMultiple: true, canChooseDirectories: true, for: window, cancelled: {
                            guard selectionAction.takeIfCurrent(onInvalidated: {}) else { return }
                        }, completion: { [weak self] result in
                            guard let self else {
                                return
                            }
                            guard selectionAction.takeIfCurrent(onInvalidated: {}) else { return }
                            if let result = result {
                                guard !result.isEmpty else {
                                    return
                                }
                                
                                let previous = result.count
                                var exceedSize: Int64?
                                var rejectedForSize = false
                                let result = result.filter { path -> Bool in
                                    if let size = fileSize(path) {
                                        let exceed = fileSizeLimitExceed(context: context, fileSize: size)
                                        if !exceed { rejectedForSize = true }
                                        if exceed {
                                            exceedSize = size
                                        }
                                        return exceed
                                    }
                                    return false
                                }
                                
                                let afterSizeCheck = result.count
                                if afterSizeCheck > 0 && afterSizeCheck < previous {
                                }
                                
                                if afterSizeCheck == 0 && previous != afterSizeCheck {
                                    showFileLimit(context: context, fileSize: exceedSize)
                                } else {
                                    self.chatInteraction.showPreviewSender(result.map{URL(fileURLWithPath: $0)}, asMedia, nil)
                                }
                                
                            } else {
                            }
                        })
                    } else {
                    }
                }
            }
            
        }
        chatInteraction.attachPhotoOrVideo = { [weak self] type in
            if let `self` = self, let window = self.window {
                let selectionAction = self.chatInteraction.captureDeferredSendAction()
                if let slowMode = self.chatInteraction.presentation.slowMode, let errorText = slowMode.errorText {
                    tooltip(for: self.genericView.inputView.attachView, text: errorText)
                    if let last = slowMode.sendingIds.last {
                        self.chatInteraction.focusMessageId(nil, .init(messageId: last, string: nil), .CenterEmpty)
                    }
                } else {
                    var exts:[String]? = nil
                    if let type = type {
                        switch type {
                        case .photo:
                            exts = photoExts
                        case .video:
                            exts = videoExts
                        }
                    }
                                        
                    filePanel(with: exts, allowMultiple: true, canChooseDirectories: true, for: window, cancelled: {
                        guard selectionAction.takeIfCurrent(onInvalidated: {}) else { return }
                    }, completion: { [weak self] result in
                        guard let self else {
                            return
                        }
                        guard selectionAction.takeIfCurrent(onInvalidated: {}) else { return }
                        if let result = result {
                            guard !result.isEmpty else {
                                return
                            }
                            let previous = result.count
                            
                            var exceedSize: Int64?
                            var rejectedForSize = false
                            let result = result.filter { path -> Bool in
                                if let size = fileSize(path) {
                                    let exceed = fileSizeLimitExceed(context: context, fileSize: size)
                                    if !exceed { rejectedForSize = true }
                                    if exceed {
                                        exceedSize = size
                                    }
                                    return exceed
                                }
                                return false
                            }
                            
                            let afterSizeCheck = result.count
                            if afterSizeCheck > 0 && afterSizeCheck < previous {
                            }
                            
                            if afterSizeCheck == 0 && previous != afterSizeCheck {
                                showFileLimit(context: context, fileSize: exceedSize)
                            } else {
                                self.chatInteraction.showPreviewSender(result.map{URL(fileURLWithPath: $0)}, true, nil)
                            }
                        } else {
                        }
                    })
                }
            }
        }
        chatInteraction.attachPicture = { [weak self] in
            guard let `self` = self else {return}
            if let window = self.window {
                let selectionAction = self.chatInteraction.captureDeferredSendAction()
                pickImage(for: window, completion: { [weak self] image in
                    guard let self else {
                        return
                    }
                    guard selectionAction.takeIfCurrent(onInvalidated: {}) else { return }
                    if let image = image {
                        let preparedAction = self.chatInteraction.captureDeferredSendAction()
                        let signal = putToTemp(image: image) |> deliverOnMainQueue
                        _ = (signal).start(next: { [weak self] path in
                            guard let self else {
                                return
                            }
                            guard preparedAction.takeIfCurrent(onInvalidated: {}) else { return }
                            self.chatInteraction.showPreviewSender([URL(fileURLWithPath: path)], true, nil)
                        })
                    } else {
                    }
                })
            }
        }
        chatInteraction.attachLocation = { [weak self] morphSource in
            guard let `self` = self else {return}
            ChatNavigationHooks.shared.showLocationPicker(self.chatInteraction, context.window, morphSource)
        }
        chatInteraction.attachAudio = { [weak self] morphSource in
            guard let `self` = self else { return }
            showModal(with: ChatUIHooks.shared.makeSendAudioModal(context, self.chatInteraction), for: context.window, morphSource: morphSource)
        }
        
        chatInteraction.sendAppFile = { [weak self] file, silent, query, schedule, collectionId, caption, preSchedule in
            guard let strongSelf = self, let peer = strongSelf.chatInteraction.peer else {
                return
            }
            if peer.canSendMessage(strongSelf.mode.isThreadMode, media: file, threadData: strongSelf.chatInteraction.presentation.threadInfo, cachedData: strongSelf.chatInteraction.presentation.cachedData) {

                let invoke:()->Void = { [strongSelf] in
                    let hasFwd = !strongSelf.chatInteraction.presentation.interfaceState.forwardMessageIds.isEmpty
                    func apply(_ controller: ChatController, atDate: Date?, repeatPeriod: Int32?) {
                        let completed: () -> Void = {
                            scrollAfterSend()
                        }
                        if let caption = caption {
                            let _ = (Sender.enqueue(media: [file], caption: caption, context: context, peerId: makePeerId(), replyId: takeReplyId(), threadId: threadId64(), silent: silent, atDate: atDate, repeatPeriod: repeatPeriod, query: query, collectionId: collectionId, customChatContents: customChatContents, sendPaidMessageStars: takePaidMessageStars()) |> deliverOnMainQueue).start(completed: completed)
                        } else {
                            let _ = (Sender.enqueue(media: file, context: context, peerId: makePeerId(), replyId: takeReplyId(), threadId: threadId64(), silent: silent, atDate: atDate, repeatPeriod: repeatPeriod, query: query, collectionId: collectionId, customChatContents: customChatContents, sendPaidMessageStars: takePaidMessageStars()) |> deliverOnMainQueue).start(next: { ids in
                            }, completed: completed)
                        }
                        controller.nextTransaction.set(handler: {
                            if hasFwd {
                                DispatchQueue.main.async {
                                    self?.chatInteraction.sendMessage(false, nil, self?.chatInteraction.presentation.messageEffect)
                                }
                            } else {
                                _afterSentTransition(false)
                            }
                        })
                    }

                    if let preSchedule = preSchedule {
                        apply(strongSelf, atDate: preSchedule.date, repeatPeriod: preSchedule.repeatPeriod)
                        return
                    }

                    let shouldSchedule: Bool
                    switch strongSelf.mode {
                    case .scheduled:
                        shouldSchedule = true
                    default:
                        shouldSchedule = schedule
                    }

                    if shouldSchedule {
                        FeatureNavigationHooks.shared.selectDateObserved(context, context.window, nil, nil, .schedule(peer.id), selectedAt: { [weak strongSelf] date, repeatPeriod in
                            if let controller = strongSelf {
                                apply(controller, atDate: date, repeatPeriod: repeatPeriod)
                            } else {
                            }
                        }, cancelled: {
                        }, dismissed: {
                        })
                    } else {
                        apply(strongSelf, atDate: nil, repeatPeriod: nil)
                    }
                }
                
                let chatInteraction = strongSelf.chatInteraction
                let presentation = chatInteraction.presentation
                let messagesCount = 1
                
                if let payStars = presentation.sendPaidMessageStars, let peer = presentation.peer, let starsState = presentation.starsState {
                    let starsPrice = Int(payStars.value * Int64(messagesCount))
                    let amount = strings().starListItemCountOther(starsPrice)
                    let showPurchase: () -> Void = {
                        FeatureNavigationHooks.shared.showStarsPurchaseWithContext(context, context.window, .stars, nil, Int64(starsPrice))
                    }
                    
                    if !presentation.alwaysPaidMessage {
                        
                        let messageCountText = strings().chatPayStarsConfirmMessagesOther(messagesCount)
                        
                        var confirmationResolved = false
                        verifyAlert(for: chatInteraction.interactionContext.window, header: strings().chatPayStarsConfirmTitle, information: strings().chatPayStarsConfirmText(peer.displayTitle, amount, amount, messageCountText), ok: strings().chatPayStarsConfirmPayOther(messagesCount), option: strings().chatPayStarsConfirmCheckbox, optionIsSelected: false, successHandler: { result in
                            confirmationResolved = true
                            guard chatPaidMessagePriceIsCurrent(chatInteraction, payStars) else { return }
                            if starsState.balance.value > starsPrice {
                                chatInteraction.update({ current in
                                    return current
                                        .withUpdatedAlwaysPaidMessage(result == .thrid)
                                })
                                if result == .thrid {
                                    FastSettings.toggleCofirmPaid(peer.id, price: Int(payStars.value))
                                }
                                invoke()
                            } else {
                                showPurchase()
                            }
                        }, cancelHandler: {
                            confirmationResolved = true
                        }, onDeinit: {
                            DispatchQueue.main.async {
                            }
                        })
                        
                    } else {
                        if starsState.balance.value > starsPrice {
                            invoke()
                        } else {
                            showPurchase()
                        }
                    }
                } else {
                    invoke()
                }
            } else {
            }
        }

        chatInteraction.sendMedias = { [weak self] medias, caption, isCollage, additionText, silent, atDate, isSpoiler, messageEffect, leadingText in
            let deferredSendAction = self?.chatInteraction.captureDeferredSendAction()
            if customChatContents != nil {
            }
            if let strongSelf = self, let peer = strongSelf.chatInteraction.peer {
                
                let presentation = strongSelf.chatInteraction.presentation
                
                let canSend = medias.map {
                    return peer.canSendMessage(strongSelf.mode.isThreadMode, media: $0, threadData: strongSelf.chatInteraction.presentation.threadInfo, cachedData: strongSelf.chatInteraction.presentation.cachedData)
                }.allSatisfy { $0 }
                
                if canSend {
                    
                    let invoke:()->Void = { [strongSelf] in
                        func apply(_ controller: ChatController, atDate: Date?, repeatPeriod: Int32?) {
                            let destinationPeerId = makePeerId()
                            let _ = (Sender.enqueue(media: medias, caption: caption, context: context, peerId: destinationPeerId, replyId: takeReplyId(), threadId: threadId64(), isCollage: isCollage, additionText: additionText, silent: silent, atDate: atDate, repeatPeriod: repeatPeriod, isSpoiler: isSpoiler, customChatContents: customChatContents, messageEffect: messageEffect, leadingText: leadingText, sendPaidMessageStars: takePaidMessageStars(), suggestPost: presentation.interfaceState.suggestPost) |> deliverOnMainQueue).start(next: { ids in
                            }, completed: {
                                scrollAfterSend()
                            })
                            controller.nextTransaction.set(handler: afterSentTransition)
                        }
                        switch strongSelf.mode {
                        case .history, .thread, .customChatContents:
                            DispatchQueue.main.async { [weak strongSelf] in
                                if let _ = atDate {
                                    strongSelf?.openScheduledChat()
                                }
                            }
                            apply(strongSelf, atDate: atDate?.date, repeatPeriod: atDate?.repeatPeriod)
                        case .scheduled:
                            if let atDate = atDate {
                                apply(strongSelf, atDate: atDate.date, repeatPeriod: atDate.repeatPeriod)
                            } else {
                                showModal(with: chatDateSelector(context: context, mode: .schedule(peer.id), selectedAt: { [weak strongSelf] date, repeatPeriod in
                                    guard deferredSendAction?.takeIfCurrent(onInvalidated: {}) == true else { return }
                                    if let strongSelf = strongSelf {
                                        apply(strongSelf, atDate: date, repeatPeriod: repeatPeriod)
                                    }
                                }), for: context.window)
                            }
                        case .pinned:
                            break
                        case .customLink:
                            break
                        case .preview:
                            break
                        }
                    }
                    invoke()
                } else {
                }
            } else {
            }
        }
        
        chatInteraction.shareSelfContact = { [weak self] replyId in
            if let strongSelf = self, let peer = strongSelf.chatInteraction.peer {
                if let myPeer = context.myPeer as? TelegramUser {
                    let media = TelegramMediaContact(firstName: myPeer.firstName ?? "", lastName: myPeer.lastName ?? "", phoneNumber: myPeer.phone ?? "", peerId: myPeer.id, vCardData: nil)
                    let canSend = peer.canSendMessage(strongSelf.mode.isThreadMode, media: media, threadData: strongSelf.chatInteraction.presentation.threadInfo, cachedData: strongSelf.chatInteraction.presentation.cachedData)
                    if canSend {
                        _ = Sender.enqueue(message: EnqueueMessage.message(text: "", attributes: [], inlineStickers: [:], mediaReference: AnyMediaReference.standalone(media: media), threadId: threadId64(), replyToMessageId: replyId.flatMap { .init(messageId: $0, quote: nil, innerSubject: nil) }, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: []), context: context, peerId: peerId).start(next: { ids in
                        }, completed: scrollAfterSend)
                        strongSelf.nextTransaction.set(handler: afterSentTransition)
                    }
                }
            }
        }
        
        chatInteraction.restartTopic = {
            switch chatLocation() {
            case let .thread(data):
                _ = context.engine.peers.setForumChannelTopicClosed(id: peerId, threadId: data.threadId, isClosed: false).start()
            default:
                break
            }
        }

        chatInteraction.openSetPeerAvatar = {
            ChatNavigationHooks.shared.setPeerPhoto(context, peerId)
        }
        
        chatInteraction.sendCommand = { [weak self] command in
            let deferredSendAction = self?.chatInteraction.captureDeferredSendAction()
            if let strongSelf = self, let peer = strongSelf.chatInteraction.peer, peer.canSendMessage(strongSelf.mode.isThreadMode, threadData: strongSelf.chatInteraction.presentation.threadInfo, cachedData: strongSelf.chatInteraction.presentation.cachedData) {
                func apply(_ controller: ChatController, atDate: Date?, repeatPeriod: Int32?) {
                    var commandText = "/" + command.command.text
                    if controller.chatInteraction.peerId.namespace != Namespaces.Peer.CloudUser, let addressName = command.peer.addressName, !addressName.isEmpty {
                        commandText += "@" + addressName
                    }
                    let destinationPeerId = makePeerId()
                    let ephemeralBotPeerId = command.command.isEphemeral ? command.peer.id : nil
                    _ = Sender.enqueue(input: ChatTextInputState(inputText: commandText), context: context, peerId: destinationPeerId, replyId: takeReplyId(), threadId: threadId64(), atDate: atDate, repeatPeriod: repeatPeriod, customChatContents: customChatContents, sendPaidMessageStars: takePaidMessageStars(), ephemeralBotPeerId: ephemeralBotPeerId).start(completed: scrollAfterSend)
                    controller.chatInteraction.updateInput(with: "")
                    controller.nextTransaction.set(handler: afterSentTransition)
                }
                switch strongSelf.mode {
                case .scheduled:
                    DispatchQueue.main.async { [strongSelf] in
                        showModal(with: chatDateSelector(context: context, mode: .schedule(peer.id), selectedAt: { [weak strongSelf] date, repeatPeriod in
                            guard deferredSendAction?.takeIfCurrent() == true else {
                                return
                            }
                            if let strongSelf = strongSelf {
                                apply(strongSelf, atDate: date, repeatPeriod: repeatPeriod)
                            }
                        }), for: context.window)
                    }
                case .history, .thread, .customChatContents:
                    apply(strongSelf, atDate: nil, repeatPeriod: nil)
                case .pinned:
                    break
                case .customLink:
                    break
                case .preview:
                    break
                }
            }
        }
        
        chatInteraction.switchInlinePeer = { [weak self] switchId, initialAction in
            if let strongSelf = self {
                strongSelf.navigationController?.push(ChatSwitchInlineController(context: context, peerId: switchId, fallbackId:strongSelf.chatInteraction.peerId, fallbackMode: strongSelf.mode, initialAction: initialAction))
            }
        }
        
        chatInteraction.setNavigationAction = { [weak self] action in
            self?.navigationController?.set(modalAction: action)
        }
        
        chatInteraction.presentPreviewSender = { [weak self] urls, asMedia, attributedString in
            if let `self` = self {
                if let slowMode = self.chatInteraction.presentation.slowMode, let errorText = slowMode.errorText {
                    tooltip(for: self.genericView.inputView.attachView, text: errorText)
                    if !slowMode.sendingIds.isEmpty {
                        self.chatInteraction.focusMessageId(nil, .init(messageId: slowMode.sendingIds.last!, string: nil), .CenterEmpty)
                    }
                } else {
                                        
                    var updated:[URL] = []
                    for url in urls {
                        if url.path.contains("/T/TemporaryItems/") {
                            let newUrl = URL(fileURLWithPath: NSTemporaryDirectory() + url.path.nsstring.lastPathComponent)
                            try? FileManager.default.moveItem(at: url, to: newUrl)
                            if FileManager.default.fileExists(atPath: newUrl.path) {
                                updated.append(newUrl)
                            }
                        } else {
                            if FileManager.default.fileExists(atPath: url.path) {
                                updated.append(url)
                            }
                        }
                    }
                    
                    if !updated.isEmpty {
                        if let editState = self.chatInteraction.presentation.interfaceState.editState {
                            if editState.message.media.isEmpty, updated.count == 1 {
                                if let media = updated.first {
                                    let replacement = self.chatInteraction.beginMediaReplacement()
                                    self.updateMediaDisposable.set((Sender.generateMedia(for: MediaSenderContainer(path: media.path, isFile: false), account: context.account, isSecretRelated: peerId.namespace == Namespaces.Peer.SecretChat) |> deliverOnMainQueue).start(next: { [weak self] media, _ in
                                        self?.chatInteraction.applyMediaReplacement(media, request: replacement)
                                    }))
                                }

                            } else {
                                alert(for: context.window, info: strings().chatEditAttachError)
                            }
                        } else {
                            if updated.count < urls.count {
                            }
                            let preview = ChatUIHooks.shared.makePreviewSender(updated, self.chatInteraction, asMedia, attributedString)
                            _ = ChatUIHooks.shared.bindPreviewSendValidation(preview, { [weak self] in
                                guard let self else { return false }
                                guard let navigation = self.navigationController else { return true }
                                return navigation.controller === self
                            })
                            showModal(with: preview, for: context.window, morphSource: { [weak self] in self?.genericView.inputView.attachView })
                        }
                    } else {
                    }
                }
            } else {
            }
        }
        
        chatInteraction.setChatMessageAutoremoveTimeout = { [weak self] seconds in
            guard let strongSelf = self else {
                return
            }
            if let peer = strongSelf.chatInteraction.peer, peer.canSendMessage(strongSelf.mode.isThreadMode, threadData: strongSelf.chatInteraction.presentation.threadInfo, cachedData: strongSelf.chatInteraction.presentation.cachedData) {
                _ = (context.engine.peers.setChatMessageAutoremoveTimeoutInteractively(peerId: peer.id, timeout: seconds) |> deliverOnMainQueue).start(completed: scrollAfterSend)
                strongSelf.nextTransaction.set(handler: afterSentTransition)
            }
            scrollAfterSend()
        }
        
        chatInteraction.showEmojiUseTooltip = { [weak self] in
            if let view = self?.genericView.inputView.emojiView {
                tooltip(for: view, text: strings().emojiPackMoreEmoji)
            }
        }

        chatInteraction.showDeleterSetup = { [weak self] control in
            guard let strongSelf = self else {
                return
            }
            if let peer = strongSelf.chatInteraction.peer {
                if !peer.canManageDestructTimer {
                    if let timeout = strongSelf.chatInteraction.presentation.messageSecretTimeout?.timeout?.effectiveValue {
                        switch timeout {
                        case .secondsInDay:
                            tooltip(for: control, text: strings().chatInputAutoDelete1Day)
                        case .secondsInWeek:
                            tooltip(for: control, text: strings().chatInputAutoDelete7Days)
                        default:
                            break
                        }
                    }
                } else {
                    
                    ChatNavigationHooks.shared.showAutoremoveMessages(context, peer, context.window)
                }
            }
        }
        
        chatInteraction.toggleNotifications = { [weak self] isMuted in
            guard let self else {
                return
            }
            let peerId = self.chatInteraction.presentation.peer?.associatedPeerId ?? self.chatLocation.peerId
            if isMuted == nil || isMuted == true {
                _ = context.engine.peers.togglePeerMuted(peerId: peerId, threadId: self.chatLocation.threadId).start()
            } else {
                var options:[ModalOptionSet] = []
                
                options.append(ModalOptionSet(title: strings().chatListMute1Hour, selected: false, editable: true))
                options.append(ModalOptionSet(title: strings().chatListMute4Hours, selected: false, editable: true))
                options.append(ModalOptionSet(title: strings().chatListMute8Hours, selected: false, editable: true))
                options.append(ModalOptionSet(title: strings().chatListMute1Day, selected: false, editable: true))
                options.append(ModalOptionSet(title: strings().chatListMute3Days, selected: false, editable: true))
                options.append(ModalOptionSet(title: strings().chatListMuteForever, selected: true, editable: true))
                
                let intervals:[Int32] = [60 * 60, 60 * 60 * 4, 60 * 60 * 8, 60 * 60 * 24, 60 * 60 * 24 * 3, Int32.max]
                
                showModal(with: ModalOptionSetController(context: context, options: options, selectOne: true, actionText: (strings().chatInputMute, theme.colors.accent), title: strings().peerInfoNotifications, result: { [weak self] result in
                    
                    for (i, option) in result.enumerated() {
                        inner: switch option {
                        case .selected:
                            _ = context.engine.peers.updatePeerMuteSetting(peerId: peerId, threadId: self?.chatLocation.threadId, muteInterval: intervals[i]).start()
                            break
                        default:
                            break inner
                        }
                    }
                    
                }), for: context.window)
            }
        }
        
        chatInteraction.openDiscussion = { [weak self] in
            guard let `self` = self else { return }
            let signal = showModalProgress(signal: context.account.viewTracker.peerView(self.chatLocation.peerId) |> filter { $0.cachedData is CachedChannelData } |> map { $0.cachedData as! CachedChannelData } |> take(1) |> deliverOnMainQueue, for: context.window)
            self.discussionDataLoadDisposable.set(signal.start(next: { [weak self] cachedData in
                if let linkedDiscussionPeerId = cachedData.linkedDiscussionPeerId.peerId {
                    self?.chatInteraction.openInfo(linkedDiscussionPeerId, true, nil, nil)
                }
            }))
        }
        
        chatInteraction.removeAndCloseChat = { [weak self] in
            if let strongSelf = self, let window = strongSelf.window {
                _ = showModalProgress(signal: context.engine.peers.removePeerChat(peerId: strongSelf.chatInteraction.peerId, reportChatSpam: false), for: window).start(next: { [weak strongSelf] in
                    strongSelf?.navigationController?.close()
                })
            }
        }
        
        chatInteraction.removeChatInteractively = { [weak self] in
            if let strongSelf = self {
                let signal = ChatUIHooks.shared.removeChatInteractively(context, strongSelf.chatInteraction.peerId, strongSelf.chatInteraction.peer?.id) |> filter {$0} |> mapToSignal { _ -> Signal<ChatLocation?, NoError> in
                    return context.globalPeerHandler.get() |> take(1)
                   } |> deliverOnMainQueue
                
                strongSelf.deleteChatDisposable.set(signal.start(next: { [weak strongSelf] location in
                    if location == strongSelf?.chatInteraction.chatLocation {
                        strongSelf?.context.bindings.rootNavigation().close()
                    }
                }))
            }
        }
        
        chatInteraction.joinChannel = { [weak self] in
            guard let self else { return }
            joinChannel(context: context, peerId: peerId)
        }
        
        chatInteraction.joinGroupCall = { [weak self] activeCall, joinHash in
            let groupCall = self?.chatInteraction.presentation.groupCall
            var currentActiveCall = groupCall?.activeCall
            var activeCall: CachedChannelData.ActiveCall? = activeCall
            if currentActiveCall == nil {
                activeCall = nil
            }
            if activeCall != currentActiveCall {
                currentActiveCall = activeCall
            } 
            if let activeCall = currentActiveCall {
                let join:(PeerId, Date?, Bool)->Void = { joinAs, _, _ in
                    _ = ChatUIHooks.shared.requestOrJoinGroupCall(context, peerId, joinAs, activeCall, groupCall?.data?.info, joinHash, nil).start(next: { result in
                        switch result {
                        case let .samePeer(callContext):
                            ChatNavigationHooks.shared.applyGroupCallResult(context.sharedContext, callContext)
                            if let joinHash = joinHash {
                                callContext.call.joinAsSpeakerIfNeeded(joinHash)
                            }
                        case let .success(callContext):
                            ChatNavigationHooks.shared.applyGroupCallResult(context.sharedContext, callContext)
                        default:
                            alert(for: context.window, info: strings().errorAnError)
                        }
                    })
                }
                if groupCall?.data?.info?.isStream == true {
                    join(context.account.peerId, nil, false)
                } else if let callJoinPeerId = groupCall?.callJoinPeerId {
                    join(callJoinPeerId, nil, false)
                } else {
                    ChatNavigationHooks.shared.selectGroupCallJoiner(context, peerId, join)
                }
            } else if let peer = self?.chatInteraction.peer {
                if peer.groupAccess.canMakeVoiceChat {
                    verifyAlert_button(for: context.window, information: strings().voiceChatChatStartNew, ok: strings().voiceChatChatStartNewOK, successHandler: { _ in
                        ChatUIHooks.shared.createVoiceChat(context, peerId)
                    })
                }
            }
        }
        
        chatInteraction.returnGroup = { [weak self] in
            if let strongSelf = self, let _ = strongSelf.window {
            }
        }
        
        chatInteraction.transcribeAudio = { [weak self] message in
            
            let messageId = message.id
            
            guard let strongSelf = self else {
                return
            }
            
         
                        
            let value: [MessageId : TranscribeAudioState] = strongSelf.uiState.with { $0.transribe }
           
            if let value = value[messageId] {
                strongSelf.updateState { state in
                    var state = state
                    switch value {
                    case let .revealed(success):
                        state.transribe[messageId] = .collapsed(success)
                    case let .collapsed(success):
                        state.transribe[messageId] = .revealed(success)
                    case .loading:
                        break
                    }
                    return state
                }
            } else {
                
                let currentTime = Int32(Date().timeIntervalSince1970)
                if !context.isPremium, message.audioTranscription == nil {
                    if let cooldownUntilTime = context.audioTranscriptionTrial.cooldownUntilTime, cooldownUntilTime > currentTime {
                        let time = stringForMediumDate(timestamp: Int32(cooldownUntilTime))
                        let trialCount = context.appConfiguration.getGeneralValue("transcribe_audio_trial_weekly_number", orElse: 0)
                        let usedString = strings().conversationFreeTranscriptionCooldownTooltipOther(Int(trialCount))
                        let waitString = strings().conversationFreeTranscriptionWaitOrSubscribe(time)
                        let fullString = "\(usedString) \(waitString)"
                        showModalText(for: context.window, text: fullString, callback: { _ in
                            prem(with: PremiumBoardingController(context: context, source: .translations), for: context.window)
                        })
                        return
                    } else {
                        let remainingCount = context.audioTranscriptionTrial.remainingCount
                        let text = strings().conversationFreeTranscriptionLimitTooltipOther(Int(remainingCount))
                        showModalText(for: context.window, text: text)
                    }
                }
                
                strongSelf.updateState { state in
                    var state = state
                    state.transribe[messageId] = .loading
                    return state
                }
                
                let signal = context.engine.messages.transcribeAudio(messageId: messageId)
                |> deliverOnMainQueue

                strongSelf.transcribeDisposable.set(signal.start(next: { [weak strongSelf] result in
                    guard let strongSelf = strongSelf else { return }
                    strongSelf.updateState { state in
                        var state = state
                        switch result {
                        case .success:
                            state.transribe[messageId] = .revealed(true)
                        case .error:
                            state.transribe[messageId] = .revealed(false)
                        }
                        return state
                    }
                    
                }), forKey: messageId)
            }

        }
        
        chatInteraction.openScheduledMessages = { [weak self] in
            self?.openScheduledChat()
        }
        
        chatInteraction.openBank = { card in
            _ = showModalProgress(signal: context.engine.payments.getBankCardInfo(cardNumber: card), for: context.window).start(next: { info in
                if let info = info {
                    
                    let values: [ValuesSelectorValue<String>] = info.urls.map {
                        return ValuesSelectorValue(localized: $0.title, value: $0.url)
                    }
                    
                    showModal(with: ValuesSelectorModalController(values: values, selected: nil, title: info.title, onComplete: { selected in
                        LinkHooks.shared.openExternalLink(selected.value, false)
                    }), for: context.window)
                 
                }
            })
        }
        
        chatInteraction.shareContact = { [weak self] peer in
            if let strongSelf = self, let main = strongSelf.chatInteraction.peer {
                if let permissionText = permissionText(from: main, for: .banSendText, cachedData: strongSelf.chatInteraction.presentation.cachedData) {
                    showModalText(for: context.window, text: permissionText)
                    return
                }
                let media = TelegramMediaContact(firstName: peer.firstName ?? "", lastName: peer.lastName ?? "", phoneNumber: peer.phone ?? "", peerId: peer.id, vCardData: nil)
                let canSend = main.canSendMessage(strongSelf.mode.isThreadMode, media: media, threadData: strongSelf.chatInteraction.presentation.threadInfo, cachedData: strongSelf.chatInteraction.presentation.cachedData)
                if canSend {
                    _ = Sender.shareContact(context: context, peerId: makePeerId(), media: media, replyId: takeReplyId(), threadId: threadId64(), sendPaidMessageStars: takePaidMessageStars()).start(completed: scrollAfterSend)
                    strongSelf.nextTransaction.set(handler: afterSentTransition)
                }
            }
        }
        
        chatInteraction.unblock = { [weak self] in
            if let strongSelf = self {
                let presentation = strongSelf.chatInteraction.presentation
                if let peer = presentation.mainPeer {
                    strongSelf.unblockDisposable.set(context.blockedPeersContext.remove(peerId: peer.id).start())
                }
            }
        }
        
        chatInteraction.replyToAnother = { [weak self] subject, reset in
            
            if reset {
                self?.chatInteraction.update({
                    $0.updatedInterfaceState({
                        $0.withUpdatedReplyMessageId(nil)
                    })
                })
            }
            
            let message = context.engine.data.get(TelegramEngine.EngineData.Item.Messages.Message(id: subject.messageId)) |> deliverOnMainQueue
            
            _ = message.start(next: { message in
                if let message = message?._asMessage() {
                    showModal(with: ChatUIHooks.shared.makeReplyForwardShareModal(context, message, subject), for: context.window)
                }
                
            })
        }
        
        chatInteraction.toggleQuote = { [weak self] index in
            self?.updateState { current in
                var current = current
                if current.quoteRevealed.contains(index) {
                    current.quoteRevealed.remove(index)
                } else {
                    current.quoteRevealed.insert(index)
                }
                return current
            }
        }

        chatInteraction.toggleDetails = { [weak self] index in
            self?.updateState { current in
                var current = current
                if current.detailsExpanded.contains(index) {
                    current.detailsExpanded.remove(index)
                } else {
                    current.detailsExpanded.insert(index)
                }
                return current
            }
        }
        
        chatInteraction.interactionEnqueueCodeSyntax = { [weak self] messageId, range, code, language, theme in
            assertOnMainThread()
            
            let codeSyntaxes = self?.uiState.with { $0.codeSyntaxes }
            
            let key = ChatUIHooks.shared.makeCodeSyntaxKey(messageId, range, language, theme)
            if codeSyntaxes?[key] == nil {
                
                self?.updateState({ current in
                    var current = current
                    current.codeSyntaxes[key] = .init(resut: nil)
                    return current
                })
                
                let signal: Signal<CodeSyntaxResult, NoError> = Signal { subscriber in
                    subscriber.putNext(.init(resut: ChatUIHooks.shared.highlightCodeSyntax(code, language, theme)))
                    subscriber.putCompletion()
                    return EmptyDisposable
                }
                |> runOn(.concurrentBackgroundQueue())
                |> deliverOnMainQueue
                
                self?.codeSyntaxHighlightDisposables.set(signal.startStrict(next: { result in
                    self?.updateState({ current in
                        var current = current
                        current.codeSyntaxes[key] = result
                        return current
                    })
                }), forKey: key)
            }
        }
        
        chatInteraction.openPhoneNumberContextMenu = { [weak self] phoneNumber in
            let point = context.window.mouseLocationOutsideOfEventStream
            let view = context.window.contentView?.hitTest(point)
            
            if let view, let event = NSApp.currentEvent {
                
                let signal = context.engine.peers.resolvePeerByPhone(phone: phoneNumber) |> deliverOnMainQueue
                
                _ = signal.startStandalone(next: { [weak view] peer in
                    
                    if let view = view {
                        let menu = ContextMenu()
                        
                        menu.addItem(ContextMenuItem(strings().contextCopyToClipboard, handler: {
                            copyToClipboard(phoneNumber)
                            showModalText(for: context.window, text: strings().shareLinkCopied)
                        }, itemImage: MenuAnimation.menu_copy.value))
                        
                        menu.addItem(ContextSeparatorItem())

                        let item: ContextMenuItem
                        if let peer {
                            item = ReactionPeerMenu(title: peer._asPeer().displayTitle, handler: { [weak self] in
                                self?.chatInteraction.openInfo(peer.id, true, nil, nil)
                            }, peer: peer._asPeer(), context: context, reaction: nil, message: nil)
                        } else {
                            item = ContextMenuItem(strings().chatContextPhoneNotTelegram)
                            item.isEnabled = false
                        }
                        menu.addItem(item)
                        
                        AppMenu.show(menu: menu, event: event, for: view)
                    }
                })
                
                
            }
        }
        
        chatInteraction.openTonAddressContextMenu = { [weak self] address in
            guard #available(macOS 10.15, *), let walletContext = ChatHistoryUIHooks.shared.walletHooks.walletContext(context) else {
                return
            }
            guard let event = NSApp.currentEvent, let window = event.window, let view = window.contentView?.hitTest(window.mouseLocationOutsideOfEventStream) else {
                return
            }
            self?.tonAddressMenuDisposable.set((ChatHistoryUIHooks.shared.walletHooks.resolveTonAddress(context, walletContext, address)
            |> take(1)
            |> deliverOnMainQueue).start(next: { [weak self, weak view] resolved in
                guard let view, let resolved else {
                    return
                }
                let menu = ContextMenu()
                if context.appConfiguration.getBoolValue("wallet_available", orElse: false) {
                    menu.addItem(ContextMenuItem(strings().chatControllerSendMoney, handler: resolved.send, itemImage: MenuAnimation.menu_gram.value))
                }
                menu.addItem(ContextMenuItem(strings().chatControllerCopyAddress, handler: {
                    copyToClipboard(address)
                    showModalText(for: context.window, text: strings().chatControllerAddressCopied)
                }, itemImage: MenuAnimation.menu_copy.value))
                menu.addItem(ContextMenuItem(strings().chatControllerViewInExplorer, handler: resolved.openExplorer, itemImage: MenuAnimation.menu_search.value))
                if let owner = resolved.owner {
                    menu.addItem(ContextSeparatorItem())
                    menu.addItem(ReactionPeerMenu(title: owner._asPeer().displayTitle, handler: { [weak self] in
                        self?.chatInteraction.openInfo(owner.id, false, nil, nil)
                    }, peer: owner._asPeer(), context: context, reaction: nil, message: nil))
                }
                AppMenu.show(menu: menu, event: event, for: view)
            }))
        }
        
        chatInteraction.updatePinned = { [weak self] pinnedId, dismiss, silent, forThisPeerOnlyIfPossible in
            if let `self` = self {
                
                let pinnedUpdate: PinnedMessageUpdate = dismiss ? .clear(id: pinnedId) : .pin(id: pinnedId, silent: silent, forThisPeerOnlyIfPossible: forThisPeerOnlyIfPossible)
                let peerId = self.chatInteraction.peerId
                if let peer = self.chatInteraction.peer as? TelegramChannel {
                    if peer.hasPermission(.pinMessages) || (peer.isChannel && peer.hasPermission(.editAllMessages)) {
                        
                        let verify = dismiss ? verifyAlertSignal(for: context.window, header: strings().chatConfirmUnpinHeader, information: strings().chatConfirmUnpin, ok: strings().chatConfirmUnpinOK) |> map { $0 == .basic } |> filter { $0 } : .single(true)
                        
                        self.updatePinnedDisposable.set((verify |> mapToSignal { _ in return
                            showModalProgress(signal: context.engine.messages.requestUpdatePinnedMessage(peerId: peerId, update: pinnedUpdate) |> `catch` { _ in .complete() }, for: context.window)}).start())
                    } else {
                        self.chatInteraction.update({$0.updatedInterfaceState({$0.withAddedDismissedPinnedIds([pinnedId])})})
                    }
                } else if self.chatInteraction.peerId.namespace == Namespaces.Peer.CloudUser {
                    if dismiss {
                        verifyAlert_button(for: context.window, header: strings().chatConfirmUnpinHeader, information: strings().chatConfirmUnpin, ok: strings().chatConfirmUnpinOK, successHandler: { [weak self] _ in
                            self?.updatePinnedDisposable.set(showModalProgress(signal: context.engine.messages.requestUpdatePinnedMessage(peerId: peerId, update: pinnedUpdate), for: context.window).start())
                        })
                    } else {
                        self.updatePinnedDisposable.set(showModalProgress(signal: context.engine.messages.requestUpdatePinnedMessage(peerId: peerId, update: pinnedUpdate), for: context.window).start())
                    }
                } else if let peer = self.chatInteraction.peer as? TelegramGroup, peer.canPinMessage {
                    if dismiss {
                        verifyAlert_button(for: context.window, header: strings().chatConfirmUnpinHeader, information: strings().chatConfirmUnpin, ok: strings().chatConfirmUnpinOK, successHandler: {  [weak self]_ in
                            self?.updatePinnedDisposable.set(showModalProgress(signal: context.engine.messages.requestUpdatePinnedMessage(peerId: peerId, update: pinnedUpdate), for: context.window).start())
                        })
                    } else {
                        self.updatePinnedDisposable.set(showModalProgress(signal: context.engine.messages.requestUpdatePinnedMessage(peerId: peerId, update: pinnedUpdate), for: context.window).start())
                    }
                }
            }
        }
        
        chatInteraction.openPinnedMessages = { [weak self, unowned context] messageId in
            guard let `self` = self else {
                return
            }
            self.navigationController?.push(ChatAdditionController(context: context, chatLocation: chatLocation(), mode: .pinned, focusTarget: .init(messageId: messageId)))
        }
        
        chatInteraction.unpinAllMessages = { [weak self, unowned context] in
            guard let `self` = self else {
                return
            }
            
            guard let peer = self.chatInteraction.presentation.peer else {
                return
            }
            
            var canManagePin = false
            if let channel = peer as? TelegramChannel {
                canManagePin = channel.hasPermission(.pinMessages)
            } else if let group = peer as? TelegramGroup {
                switch group.role {
                case .creator, .admin:
                    canManagePin = true
                default:
                    if let defaultBannedRights = group.defaultBannedRights {
                        canManagePin = !defaultBannedRights.flags.contains(.banPinMessages)
                    } else {
                        canManagePin = true
                    }
                }
            } else if let _ = peer as? TelegramUser, self.chatInteraction.presentation.canPinMessage {
                canManagePin = true
            }

            if canManagePin {
                let count = self.chatInteraction.presentation.pinnedMessageId?.totalCount ?? 1
                
                verifyAlert_button(for: context.window, information: strings().chatUnpinAllMessagesConfirmationOther(count), ok: strings().chatConfirmUnpinOK, cancel: strings().modalCancel, successHandler: { [weak self] _ in
                    let _ = (context.engine.messages.requestUnpinAllMessages(peerId: peerId, threadId: self?.chatLocation.threadId)
                        |> deliverOnMainQueue).start(error: { _ in
                            
                        }, completed: { [weak self] in
                            self?.navigationController?.back()
                        })
                })
            } else {
                self.chatInteraction.update({ state in
                    return state.updatedInterfaceState { $0.withAddedDismissedPinnedIds(state.pinnedMessageId?.others.map { $0 } ?? [] )}
                })
                self.navigationController?.back()
            }

            
            
        }
        
        chatInteraction.openMonoforum = { [weak self] peerId in
            guard let self else {
                return
            }
            
            let peer = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId)) |> deliverOnMainQueue
            
            _ = peer.startStandalone(next: { [weak self] peer in
                
                guard let peer, let self else {
                    return
                }
                self.chatInteraction.saveState(scrollState: self.immediateScrollState())
                
                if peer._asPeer().groupAccess.canManageDirect {
                    let location: ChatLocation = .makeSaved(peerId, peerId: context.peerId, isMonoforum: true)
                    
                    self.navigationController?.push(ChatAdditionController(context: context, chatLocation: location, mode: .history))

                } else {
                    self.navigationController?.push(ChatAdditionController(context: context, chatLocation: .peer(peerId), mode: .history))
                }

            })
        }
        
        chatInteraction.sendGift = { morphSource in
            showModal(with: GiftingController(context: context, peerId: peerId, isBirthday: false), for: context.window, morphSource: morphSource)
        }

        chatInteraction.diceRoll = { [weak self] in
            if let chatInteraction = self?.chatInteraction {
                showModal(with: ChatUIHooks.shared.makeDiceRollController(context, chatInteraction), for: context.window)
            }
        }

        chatInteraction.sendDiceWithStake = { [weak self] stake in
            _ = (context.tonContext.state |> deliverOnMainQueue |> take(1)).startStandalone(next: { tonState in
                if let balance = tonState?.balance.value, balance >= stake {
                    self?.chatInteraction.sendMedias([TelegramMediaDice(emoji: "🎲", tonAmount: stake)], ChatTextInputState(), false, nil, false, nil, false, nil, false)
                } else {
                    let needed = stake - (tonState?.balance.value ?? 0)
                    ChatNavigationHooks.shared.showAddTonBalance(context, needed, context.window)
                }
            })
        }

        chatInteraction.editPostSuggestion = { [weak self] data in
            if let chatInteraction = self?.chatInteraction {
                showModal(with: EditPostSuggestionController(chatInteraction: chatInteraction, data: data), for: context.window)
            }
        }
        
        
        
        chatInteraction.toggleMonoforumState = { [weak self] in
            guard let self else {
                return
            }
            self.updateState { current in
                var current = current
                current.monoforumState = current.monoforumState == .vertical ? .horizontal : .vertical
                return current
            }
            FastSettings.setMonoforumState(peerId, state: self.uiState.with { $0.monoforumState ?? .vertical })
        }
        
        chatInteraction.monoforumMenuItems = { [weak self] item in
            var items: [ContextMenuItem] = []

            let threadId = item.uniqueId

            guard let peer = self?.chatInteraction.peer, peer.isForumOrMonoForum else {
                return .single([])
            }

            if let user = peer as? TelegramUser, let botInfo = user.botInfo, botInfo.flags.contains(.hasForum), botInfo.flags.contains(.forumManagedByUser) {
                items.append(ContextMenuItem(strings().chatMonoforumNewChat, handler: { [weak self] in
                    self?.chatInteraction.updateChatLocationThread(Message.newTopicThreadId)
                }, itemImage: MenuAnimation.menu_create_group.value))
                if item.item != nil {
                    items.append(ContextSeparatorItem())
                }
            }

            if let item = item.item, let threadData = item.threadData {
                
                if threadData.isOwnedByMe || peer.isAdmin {
                    items.append(ContextMenuItem(strings().navigationEdit, handler: {
                        ChatUIHooks.shared.editForumTopic(peer.id, threadData, threadId, context)
                    }, itemImage: MenuAnimation.menu_edit.value))
                }
                
                if let readCounters = item.readCounters, readCounters.isUnread {
                    items.append(ContextMenuItem(strings().chatListContextMaskAsRead, handler: {
                        _ = context.engine.messages.markForumThreadAsRead(peerId: peerId, threadId: threadId).start()
                    }, itemImage: MenuAnimation.menu_read.value))
                }
                
                let isPinned = item.chatListIndex.pinningIndex != nil
                let isMuted = item.isMuted
                let isClosedTopic = threadData.isClosed
                
                let canPin = (peer as? TelegramChannel)?.hasPermission(.pinMessages) ?? peer.isBot
                
                if canPin {
                    items.append(ContextMenuItem(!isPinned ? strings().chatListContextPin : strings().chatListContextUnpin, handler: {
                        let signal = context.engine.peers.toggleForumChannelTopicPinned(id: peerId, threadId: threadId) |> deliverOnMainQueue
                        
                        _ = signal.startStandalone(error: { error in
                            switch error {
                            case let .limitReached(count):
                                alert(for: context.window, info: strings().chatListContextPinErrorTopicsOther(count))
                            default:
                                alert(for: context.window, info: strings().unknownError)
                            }
                        })
                    }, itemImage: !isPinned ? MenuAnimation.menu_pin.value : MenuAnimation.menu_unpin.value))
                }
                
                items.append(ContextMenuItem(isMuted ? strings().chatListContextUnmute : strings().chatListContextMute, handler: {
                    _ = context.engine.peers.togglePeerMuted(peerId: peerId, threadId: threadId).startStandalone()
                }, itemImage: isMuted ? MenuAnimation.menu_unmuted.value : MenuAnimation.menu_mute.value))
        
                
                if threadData.isOwnedByMe || peer.isAdmin {
                    items.append(ContextMenuItem(!isClosedTopic ? strings().chatListContextPause : strings().chatListContextStart, handler: {
                        _ = context.engine.peers.setForumChannelTopicClosed(id: peerId, threadId: threadId, isClosed: !isClosedTopic).startStandalone()
                    }, itemImage: !isClosedTopic ? MenuAnimation.menu_pause.value : MenuAnimation.menu_play.value))
                    
                    items.append(ContextSeparatorItem())
                    items.append(ContextMenuItem(strings().chatListContextDelete, handler: {
                        _ = ChatUIHooks.shared.removeThreadInteractively(context, peerId, threadId, nil).startStandalone()
                    }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                }
            } else if let item = item.item, let user = item.renderedPeer.chatOrMonoforumMainPeer {
                if let readCounters = item.readCounters, readCounters.isUnread {
                    items.append(ContextMenuItem(strings().chatListContextMaskAsRead, handler: {
                        _ = context.engine.messages.togglePeerUnreadMarkInteractively(peerId: peerId, threadId: threadId, setToValue: true).startStandalone()
                    }, itemImage: MenuAnimation.menu_read.value))
                }
                
                let isPinned = item.chatListIndex.pinningIndex != nil
                let isMuted = item.isMuted
                
                if let _ = peer.sendPaidMessageStars, self?.chatInteraction.presentation.removePaidMessageFeeData == nil, user.id.toInt64() == self?.chatInteraction.chatLocation.threadId {
                    items.append(ContextMenuItem(strings().chatContextReturnMessageFee, handler: {
                        _ = context.engine.peers.reinstateNoPaidMessagesException(scopePeerId: peer.id, peerId: user.id).startStandalone()
                    }, itemImage: MenuAnimation.menu_plus.value))
                }
                
                items.append(ContextMenuItem(!isPinned ? strings().chatListContextPin : strings().chatListContextUnpin, handler: {
                    let signal = context.engine.peers.toggleForumChannelTopicPinned(id: peerId, threadId: threadId) |> deliverOnMainQueue
                    
                    _ = signal.startStandalone(error: { error in
                        switch error {
                        case let .limitReached(count):
                            alert(for: context.window, info: strings().chatListContextPinErrorTopicsOther(count))
                        default:
                            break
//                            alert(for: context.window, info: strings().unknownError)
                        }
                    })
                }, itemImage: !isPinned ? MenuAnimation.menu_pin.value : MenuAnimation.menu_unpin.value))
                
               
                
                items.append(ContextMenuItem(isMuted ? strings().chatListContextUnmute : strings().chatListContextMute, handler: {
                    _ = context.engine.peers.togglePeerMuted(peerId: peerId, threadId: threadId).startStandalone()
                }, itemImage: isMuted ? MenuAnimation.menu_unmuted.value : MenuAnimation.menu_mute.value))
        
                items.append(ContextSeparatorItem())
                items.append(ContextMenuItem(strings().chatListContextDelete, handler: {
                    _ = ChatUIHooks.shared.removeThreadInteractively(context, peerId, threadId, nil).startStandalone()
                }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))

            }
                        
            return .single(items)
        }
        
        chatInteraction.updateChatLocationThread = { [weak self] threadId in
            guard let self else {
                return
            }
            self.updateChatLocationThreadDisposable.set(nil)
            self.cancelMessageFocus()
            
            if self.chatLocation.threadId == threadId {
                self.scrollup()
                return
            }
            
            let isMonoforum = self.chatInteraction.isMonoforum
            
            didSetReadIndex = false
            self.updateMaxVisibleReadIncomingMessageIndex(MessageIndex.absoluteLowerBound())
            _ = previousMaxIncomingMessageIdByNamespace.swap([:])
            _ = chatLocationContextHolder.swap(nil)
            
            if isMonoforum {
                let location: ChatLocation
                if let threadId {
                    location = .makeSaved(peerId, threadId: threadId, isMonoforum: isMonoforum)
                } else {
                    location = .peer(peerId)
                }
                self.chatInteraction.update({
                    $0.withUpdatedChatLocation(location)
                })
                
            } else {
                if let threadId {
                    
                    let _peerId: PeerId
                    
                    _peerId = peerId
                    
                    if threadId == Message.newTopicThreadId {
                        let message = ChatReplyThreadMessage.init(peerId: _peerId, threadId: threadId, channelMessageId: nil, isChannelPost: false, isForumPost: false, isMonoforumPost: false, maxMessage: nil, maxReadIncomingMessageId: nil, maxReadOutgoingMessageId: nil, unreadCount: 0, initialFilledHoles: .init(), initialAnchor: .automatic, isNotAvailable: false)
                        
                        self.chatInteraction.update({
                            $0.withUpdatedChatLocation(.thread(message))
                        })
                        
                    } else {
                        let message: Signal<ChatReplyThreadMessage, FetchChannelReplyThreadMessageError>
                        message = context.engine.messages.fetchChannelReplyThreadMessage(messageId: MessageId(peerId: _peerId, namespace: Namespaces.Message.Cloud, id: Int32(clamping: threadId)), atMessageId: nil) |> deliverOnMainQueue
                        
                        self.updateChatLocationThreadDisposable.set(message.start(next: { [weak self] message in
                            self?.chatInteraction.update({
                                $0.withUpdatedChatLocation(.thread(message))
                            })
                        }))

                    }
                } else {
                    self.chatInteraction.update({
                        $0.withUpdatedChatLocation(.peer(peerId))
                    })
                }
            }
        }
        
        chatInteraction.reportSpamAndClose = { [weak self] in
            let title: String
            if let peer = self?.chatInteraction.peer {
                if peer.isUser {
                    title = strings().chatConfirmReportSpamUser
                } else if peer.isChannel {
                    title = strings().chatConfirmReportSpamChannel
                } else if peer.isGroup || peer.isSupergroup {
                    title = strings().chatConfirmReportSpamGroup
                } else {
                    title = strings().chatConfirmReportSpam
                }
            } else {
                title = strings().chatConfirmReportSpam
            }
            
            self?.reportPeerDisposable.set((verifyAlertSignal(for: context.window, header: strings().chatConfirmReportSpamHeader, information: title, ok: strings().messageContextReport, cancel: strings().modalCancel) |> filter { $0 == .basic } |> mapToSignal { [weak self] _ in
                return context.engine.peers.reportPeer(peerId: peerId) |> deliverOnMainQueue |> mapToSignal { [weak self] _ -> Signal<Void, NoError> in
                    if let peer = self?.chatInteraction.peer {
                        if peer.id.namespace == Namespaces.Peer.CloudUser {
                            return context.engine.peers.removePeerChat(peerId: peerId, reportChatSpam: true) |> deliverOnMainQueue
                                |> mapToSignal { _ in
                                    return context.blockedPeersContext.add(peerId: peer.id) |> `catch` { _ in return .complete() } |> mapToSignal { _ in
                                        return .single(Void())
                                    }
                            }
                        } else {
                            return context.engine.peers.removePeerChat(peerId: peerId, reportChatSpam: true)
                        }
                    }
                    return .complete()
                    }
                    |> deliverOnMainQueue
                }).start(next: { [weak self] in
                    self?.navigationController?.back()
                }))
        }
        
        chatInteraction.dismissPeerStatusOptions = { [weak self] in
            if let strongSelf = self {
                let peerId = strongSelf.chatInteraction.peerId
                _ = context.engine.peers.dismissPeerStatusOptions(peerId: peerId).start()
            }
        }
        
        chatInteraction.markAdAction = { [weak self] opaqueId, media in
            self?.adMessages?.markAction(opaqueId: opaqueId, media: media)
        }
        
        chatInteraction.freezeAccountAlert = {
            ChatNavigationHooks.shared.showFrozenAccount(context, context.window)
        }
        
        chatInteraction.markAdAsSeen = { [weak self] opaqueId in
            self?.adMessages?.markAsSeen(opaqueId: opaqueId)
        }
        
        chatInteraction.toggleSidebar = { [weak self] in
            guard let self else { return }
            FastSettings.toggleSidebar(true)
            FastSettings.toggleSidebarShown(!ChatInputUIHooks.shared.isEntertainmentSidebarVisible(self.context.window))
            self.chatInteraction.update({ $0.withToggledSidebarEnabled(true).withToggledSidebarShown(FastSettings.sidebarShown) })
            ChatInputUIHooks.shared.updateEntertainmentSidebar(true)
        }

        chatInteraction.focusInputField = { [weak self] in
            _ = self?.context.window.makeFirstResponder(self?.firstResponder())
        }

        chatInteraction.showToaster = { [weak self] text in
            self?.genericView.showToaster(text: text, timeout: 3.0, animated: true)
        }
        chatInteraction.previewTopic = { [weak self] threadId in
            guard let self else { return }
            let peerId = self.chatInteraction.peerId
            let threadMessageId = makeThreadIdMessageId(peerId: peerId, threadId: threadId)
            _ = (fetchAndPreloadReplyThreadInfo(context: context, subject: .groupMessage(threadMessageId), preload: false) |> take(1) |> deliverOnMainQueue).start(next: { [weak self] result in
                self?.navigationController?.push(ChatController(context: context, chatLocation: .thread(result.message), mode: .preview, chatLocationContextHolder: result.contextHolder))
            })
        }
        chatInteraction.showAnimatedToaster = { [weak self] animation, text in
            guard let self else { return }
            let attributed = NSAttributedString.initialize(string: text, color: self.genericView.presentationTextColor, font: .normal(.text))
            self.genericView.showToaster(text: attributed, animation: animation, context: self.context, timeout: 3.0, animated: true)
        }
        chatInteraction.removeToaster = { [weak self] in
            self?.genericView.removeToaster(animated: true)
        }
        

        chatInteraction.withToggledSelectedMessage = { [weak self] f in
            guard let `self` = self else {
                return
            }
            let previous = self.chatInteraction.presentation.selectionState?.selectedIds
            self.chatInteraction.update(f)
            
            if let event = NSApp.currentEvent, event.modifierFlags.contains(.shift) {
                if let selectionState = self.chatInteraction.presentation.selectionState, let lastMessageId = selectionState.lastSelectedId, let previous = previous {
                    if let messageId = selectionState.selectedIds.subtracting(previous).first {
                        let minId = min(lastMessageId.id, messageId.id)
                        let maxId = max(lastMessageId.id, messageId.id)
                        let cloudNamespace = self.mode == .scheduled ? Namespaces.Message.ScheduledCloud : Namespaces.Message.Cloud
                        let localNamespace = self.mode == .scheduled ? Namespaces.Message.ScheduledLocal : Namespaces.Message.Local
                        let selectMessages = context.account.postbox.transaction { transaction -> [Message] in
                            var messages:[Message] = []
                            for id in minId ..< maxId {
                                let cloudId = MessageId(peerId: lastMessageId.peerId, namespace: cloudNamespace, id: id)
                                let localId = MessageId(peerId: lastMessageId.peerId, namespace: localNamespace, id: id)
                                let message = transaction.getMessage(cloudId) ?? transaction.getMessage(localId)
                                if let message = message {
                                    if minId > maxId {
                                        messages.append(message)
                                    } else {
                                        messages.insert(message, at: 0)
                                    }
                                }
                            }
                            return messages
                        } |> deliverOnMainQueue
                        
                        self.shiftSelectedDisposable.set(selectMessages.start(next: { [weak self] messages in
                            guard let `self` = self else {
                                return
                            }
                            self.chatInteraction.update({ current in
                                var current = current
                                if let selectionState = current.selectionState, selectionState.selectedIds.count >= 100 {
                                    return current
                                }
                                for message in messages {
                                    current = current.withUpdatedSelectedMessage(message.id)
                                }
                                
                                return current
                            })
                        }))
                    }
                }
            }
        }
        
        chatInteraction.getGradientOffsetRect = { [weak self] in
            guard let `self` = self else {
                return .zero
            }
            let point = self.genericView.scroll.rect.origin
            return CGRect(origin: point, size: self.frame.size)
        }
        
        var currentThreadId: MessageId?
        
        chatInteraction.openReplyThread = { [weak self] messageId, isChannelPost, modalProgress, mode in
            let signal:Signal<ThreadInfo, FetchChannelReplyThreadMessageError>
                
            if modalProgress {
                signal = showModalProgress(signal: fetchAndPreloadReplyThreadInfo(context: context, subject: isChannelPost ? .channelPost(messageId) : .groupMessage(messageId)) |> take(1) |> deliverOnMainQueue, for: context.window)
            } else {
                signal = fetchAndPreloadReplyThreadInfo(context: context, subject: isChannelPost ? .channelPost(messageId) : .groupMessage(messageId)) |> take(1) |> deliverOnMainQueue
            }
            
            currentThreadId = mode.originId
            
            delay(0.2, closure: {
                if currentThreadId == mode.originId {
                    self?.updateState { state in
                        var state = state
                        state.threadLoading = mode.originId
                        return state
                    }
                }
            })
            
            
            self?.loadThreadDisposable.set(signal.start(next: { [weak self] result in
                let chatLocation: ChatLocation = .thread(result.message)
                self?.updateState { state in
                    var state = state
                    state.threadLoading = nil
                    return state
                }
                currentThreadId = nil
                let updatedMode: ReplyThreadMode
                if result.isChannelPost {
                    updatedMode = .comments(origin: mode.originId)
                } else {
                    updatedMode = .replies(origin: mode.originId)
                }
                self?.navigationController?.push(ChatAdditionController(context: context, chatLocation: chatLocation, mode: .thread(mode: updatedMode), focusTarget: isChannelPost ? nil : .init(messageId: mode.originId), initialAction: nil, chatLocationContextHolder: result.contextHolder))
            }, error: { error in
                self?.updateState { state in
                    var state = state
                    state.threadLoading = nil
                    return state
                }
                currentThreadId = nil
                
                switch error {
                case .generic:
                    alert(for: context.window, info: strings().chatDiscussionMessageDeleted)
                }
            }))
        }
        
        
        
        
        chatInteraction.closeAfterPeek = { [weak self] peek in
            
            let showConfirm:()->Void = {
                verifyAlert_button(for: context.window, header: strings().privateChannelPeekHeader, information: strings().privateChannelPeekText, ok: strings().privateChannelPeekOK, cancel: strings().privateChannelPeekCancel, successHandler: { _ in
                    self?.chatInteraction.joinChannel()
                }, cancelHandler: {
                    self?.navigationController?.back()
                })
            }
            
            let timeout = TimeInterval(peek) - Date().timeIntervalSince1970
            if timeout > 0 {
                let signal = Signal<NoValue, NoError>.complete() |> delay(timeout, queue: .mainQueue())
                self?.peekDisposable.set(signal.start(completed: showConfirm))
            } else {
                showConfirm()
            }
        }
        
        
        let chatLocationValue = self.chatLocationValue |> distinctUntilChanged
        let topVisibleMessageRange = self.topVisibleMessageRange.get()
        let dismissedPinnedIds = self.dismissedPinnedIds.get()
        let ready = self.ready.get()
        
        let getPinned:()-> Signal<ChatPinnedMessage?, NoError> = {
           
            let replyHistoryFirst: Signal<(ChatHistoryViewUpdate, ChatLocation), NoError> = chatLocationValue |> mapToSignal { chatLocation in
                return preloadedChatHistoryViewForLocation(.Initial(count: 6, scrollPosition: nil), context: context, chatLocation: chatLocation, chatLocationContextHolder: chatLocationContextHolder, tag: .tag(.pinned), additionalData: []) |> map { ($0, chatLocation) }
            }

            let ready = ready |> filter { $0 } |> take(1)
            
            let replyHistory: Signal<(ChatHistoryViewUpdate, ChatLocation), NoError> = chatLocationValue |> mapToSignal { chatLocation in
                return preloadedChatHistoryViewForLocation(.Initial(count: 100, scrollPosition: nil), context: context, chatLocation: chatLocation, chatLocationContextHolder: chatLocationContextHolder, tag: .tag(.pinned), additionalData: []) |> map { ($0, chatLocation) }
            }
            
            return combineLatest(queue: prepareQueue, replyHistoryFirst |> then(ready |> mapToSignal { _ in
                return  replyHistory
            }), topVisibleMessageRange, dismissedPinnedIds)
                |> map { update, topVisibleMessageRange, dismissed -> ChatPinnedMessage? in
                    let chatLocation = update.1
                    var message: ChatPinnedMessage?
                    switch update.0 {
                    case .Loading:
                        break
                    case let .HistoryView(view, _, _, _):
                        let isInLocation: (Message) -> Bool = { message in
                            return chatLocation.threadId == message.threadId || chatLocation.threadId == nil && message.threadId == 1 || message.threadId == context.peerId.toInt64()
                        }
                        let lastIndexInLocation = view.entries.lastIndex(where: { isInLocation($0.message) })
                        for i in 0 ..< view.entries.count {
                            let entry = view.entries[i]
                            var matches = false
                            if let topVisibleMessageRange = topVisibleMessageRange {
                                if entry.message.id <= topVisibleMessageRange.lowerBound {
                                    matches = !dismissed.ids.contains(entry.message.id)
                                }
                            }
                            if let tempMaxId = dismissed.tempMaxId {
                                var effectiveMatches = matches && entry.message.id < tempMaxId
                                
                                if matches, message == nil, i == lastIndexInLocation {
                                    effectiveMatches = true
                                }
                                matches = effectiveMatches
                            }
                            if i == lastIndexInLocation, message == nil {
                                matches = true
                            }
                            if matches, isInLocation(entry.message) {
                                message = ChatPinnedMessage(messageId: entry.message.id, message: entry.message, others: view.entries.map { $0.message.id }, isLatest: i == view.entries.count - 1, index: view.entries.count - 1 - i, totalCount: view.entries.count)
                            }
                        }
                        break
                    }
                    return message
                }
                |> distinctUntilChanged
        }
        
        let topPinnedMessage: Signal<ChatPinnedMessage?, NoError>
        switch mode {
        case .history:
            topPinnedMessage = getPinned()
        case .pinned:
            let replyHistory: Signal<ChatHistoryViewUpdate, NoError> = (chatHistoryViewForLocation(.Initial(count: 90, scrollPosition: nil), context: self.context, chatLocation: .peer(peerId), fixedCombinedReadStates: nil, tag: .tag(.pinned), additionalData: [])
                |> castError(Bool.self)
                |> mapToSignal { update -> Signal<ChatHistoryViewUpdate, Bool> in
                    switch update {
                    case let .Loading(_, type):
                        if case .Generic(.FillHole) = type {
                            return .fail(true)
                        }
                    case let .HistoryView(_, type, _, _):
                        if case .Generic(.FillHole) = type {
                            return .fail(true)
                        }
                    }
                    return .single(update)
                })
                |> restartIfError
            
            topPinnedMessage = replyHistory
                |> map { update -> ChatPinnedMessage? in
                    switch update {
                    case .Loading:
                        break
                    case let .HistoryView(view, _, _, _):
                        if let first = view.entries.first {
                            return ChatPinnedMessage(messageId: first.message.id, message: first.message, others: view.entries.map { $0.message.id }, isLatest: true, index: 0, totalCount: view.entries.count)
                        }
                    }
                    return nil
                }
                |> distinctUntilChanged
        case .thread:
            if mode.isThreadMode, case let .thread(data) = chatLocation() {
                topPinnedMessage = context.account.postbox.messageView(data.effectiveTopId) |> map { view in
                    if let message = view.message {
                        return ChatPinnedMessage(messageId: message.id, message: message, others: [message.id], isLatest: true, index: 0, totalCount: 1)
                    } else {
                        return nil
                    }
                }
            } else {
                topPinnedMessage = getPinned()
            }
            
        default:
            topPinnedMessage = .single(nil)
        }
        
        
        let initialData = initialDataHandler.get() |> take(1) |> beforeNext { [weak self] (combinedInitialData) in
            
            guard let `self` = self else {
                return
            }
            guard let initialData = combinedInitialData.initialData else {
                self.genericView.inputView.updateInterface(with: self.chatInteraction)
                return
            }
                        
            let opaqueState = initialData.storedInterfaceState.flatMap(_internal_decodeStoredChatInterfaceState)
            
            let interfaceState = ChatInterfaceState.parse(opaqueState, peerId: self.chatLocation.peerId, context: context)
            
            self.chatInteraction.update(animated:false, { present in
                var present = present
                present = present.updatedInterfaceState({ value in
                    return interfaceState ?? value
                }).withUpdatedContentSettings(context.contentSettings)
                
                switch mode {
                case .history, .thread, .preview:
                    let isLiveCall: Bool
                    if let peer = present.peer {
                        isLiveCall = peer.isGigagroup || peer.isChannel
                    } else {
                        isLiveCall = false
                    }
                    if peerId.namespace == Namespaces.Peer.SecretChat {
                        
                    } else if let cachedData = combinedInitialData.cachedData as? CachedChannelData {
                        present = present.withUpdatedMessageSecretTimeout(cachedData.autoremoveTimeout)
                            .withUpdatedAllowedReactions(cachedData.reactionSettings.knownValue?.allowedReactions)
                    } else if let cachedData = combinedInitialData.cachedData as? CachedGroupData {
                        present = present.withUpdatedMessageSecretTimeout(cachedData.autoremoveTimeout)
                            .withUpdatedAllowedReactions(cachedData.reactionSettings.knownValue?.allowedReactions)
                    } else if let cachedData = combinedInitialData.cachedData as? CachedUserData {
                        present = present.withUpdatedMessageSecretTimeout(cachedData.autoremoveTimeout)
                    }
                    
                    if let cachedData = combinedInitialData.cachedData as? CachedGroupData {
                        present = present.updatedGroupCall({ currentValue in
                            if let call = cachedData.activeCall {
                                return ChatActiveGroupCallInfo(activeCall: call, data: currentValue?.data, callJoinPeerId: cachedData.callJoinPeerId, joinHash: currentValue?.joinHash, isLive: isLiveCall)
                            } else {
                                return nil
                            }
                        }).withUpdatedInviteRequestsPending(cachedData.inviteRequestsPending)
                    }
                    if let cachedData = combinedInitialData.cachedData as? CachedUserData {
                        present = present
                            .withUpdatedBlocked(cachedData.isBlocked)
                            .withUpdatedCanPinMessage(cachedData.canPinMessages || context.peerId == peerId)
                            .updateBotMenu { current in
                                if let botInfo = cachedData.botInfo {
                                    var current = current ?? .init(commands: [], revealed: false, menuButton: botInfo.menuButton)
                                    current.commands = botInfo.commands
                                    current.menuButton = botInfo.menuButton
                                    return current
                                }
                                return nil
                            }
                    } else if let cachedData = combinedInitialData.cachedData as? CachedChannelData {
                        present = present
                            .withUpdatedIsNotAccessible(cachedData.isNotAccessible)
                            .withUpdatedInviteRequestsPending(cachedData.inviteRequestsPending)
                            .withUpdatedCurrentSendAsPeerId(cachedData.sendAsPeerId)
                            .updatedGroupCall({ currentValue in
                                if let call = cachedData.activeCall {
                                    return ChatActiveGroupCallInfo(activeCall: call, data: currentValue?.data, callJoinPeerId: cachedData.callJoinPeerId, joinHash: currentValue?.joinHash, isLive: isLiveCall)
                                } else {
                                    return nil
                                }
                            })
                        if let peer = present.peer as? TelegramChannel {
                            switch peer.info {
                            case let .group(info):
                                if info.flags.contains(.slowModeEnabled), peer.adminRights == nil && !peer.flags.contains(.isCreator), !canBypassChatRestrictions(cachedData) {
                                    present = present.updateSlowMode({ value in
                                        var value = value ?? SlowMode()
                                        value = value.withUpdatedValidUntil(cachedData.slowModeValidUntilTimestamp)
                                        if let timeout = cachedData.slowModeValidUntilTimestamp {
                                            if timeout > context.timestamp {
                                                value = value.withUpdatedTimeout(timeout - context.timestamp)
                                            } else {
                                                value = value.withUpdatedTimeout(nil)
                                            }
                                        }
                                        return value
                                    })
                                } else {
                                    present = present.updateSlowMode { _ in return nil }
                                }
                            default:
                                present = present.updateSlowMode { _ in return nil }
                            }
                        }
                    }
                    
                    present = present.withUpdatedLimitConfiguration(combinedInitialData.limitsConfiguration).withUpdatedCachedData(combinedInitialData.cachedData)
                    
                    let price = present.sendPaidMessageStars.flatMap({ Int($0.value) })
                    
                    let freezeAccount = context.appConfiguration.getGeneralValue("freeze_since_date", orElse: 0)
                    let freezeAccountAppealAddressName = context.appConfiguration.getStringValue("freeze_appeal_url", orElse: "https://t.me/spambot")
                    
                    
                    
                    func extractUsername(from url: String) -> String? {
                        let pattern = "(?:https?://)?t\\.me/([a-zA-Z0-9_]+)"
                        
                        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                            let range = NSRange(location: 0, length: url.utf16.count)
                            if let match = regex.firstMatch(in: url, options: [], range: range) {
                                if let usernameRange = Range(match.range(at: 1), in: url) {
                                    return String(url[usernameRange])
                                }
                            }
                        }
                        return nil
                    }
                    
                    
                    present = present.withUpdatedAlwaysPaidMessage(FastSettings.needConfirmPaid(peerId, price: price ?? 0)).withUpdatedFreezeAccount(freezeAccount).withUpdatedFreezeAccountAddressName(extractUsername(from: freezeAccountAppealAddressName)?.lowercased())
                case .scheduled:
                    if let cachedData = combinedInitialData.cachedData as? CachedChannelData {
                        present = present.withUpdatedCurrentSendAsPeerId(cachedData.sendAsPeerId)
                            .withUpdatedCachedData(cachedData)
                    }
                case .pinned:
                    break
                case .customChatContents:
                    break
                case .customLink:
                    break
                }
                return present
            })
            
            
            
            if let modalAction = self.navigationController?.modalAction {
                self.invokeNavigation(action: modalAction)
            }
            
            
            self.state = self.chatInteraction.presentation.state == .selecting ? .Edit : .Normal
            
            
        } |> map {_ in}
        
        
        
        
        let first:Atomic<Bool> = Atomic(value: true)
        
        
        let availableGroupCall: Signal<GroupCallPanelData?, NoError>
        switch self.mode {
        case .history:
            availableGroupCall = ChatUIHooks.shared.getGroupCallPanelData(context, peerId)
        case .thread:
            availableGroupCall = ChatUIHooks.shared.getGroupCallPanelData(context, peerId)
        default:
            availableGroupCall = .single(nil)
        }
        
        let attach = context.engine.messages.attachMenuBotsUpdates()
        
        let threadInfo: Signal<MessageHistoryThreadData?, NoError> = chatLocationValue |> mapToSignal { [weak self] chatLocation in
            switch chatLocation {
            case .peer:
                return .single(nil) |> beforeNext { [weak self] value in
                    let _ = self?.uiState.modify { state in
                        var state = state
                        state.topicCreatorId = nil
                        return state
                    }
                }
            case .thread(let data):
                let key: PostboxViewKey = .messageHistoryThreadInfo(peerId: peerId, threadId: data.threadId)
                return context.account.postbox.combinedView(keys: [key]) |> map { views in
                    let view = views.views[key] as? MessageHistoryThreadInfoView
                    let data = view?.info?.data.get(MessageHistoryThreadData.self)
                    return data
                }
                |> deliverOnMainQueue
                |> beforeNext { [weak self] value in
                    let _ = self?.uiState.modify { state in
                        var state = state
                        state.topicCreatorId = value?.author
                        return state
                    }
                }
            }
        }
        
        let isFirst = Atomic(value: true)
        
        let tagsAndFiles: Signal<([SavedMessageTags.Tag], [Int64 : TelegramMediaFile]), NoError>
        if peerId == context.peerId {
            tagsAndFiles = combineLatest(context.engine.data.subscribe(
                TelegramEngine.EngineData.Item.Messages.SavedMessageTagStats(peerId: context.account.peerId, threadId: threadId64())
            )
            |> distinctUntilChanged
            |> mapToSignal { tags -> Signal<([MessageReaction.Reaction: Int], [Int64: TelegramMediaFile]), NoError> in
                var customFileIds: [Int64] = []
                for (reaction, _) in tags {
                    switch reaction {
                    case .builtin:
                        break
                    case let .custom(fileId):
                        customFileIds.append(fileId)
                    case .stars:
                        break
                    }
                }
                
                return context.engine.stickers.resolveInlineStickers(fileIds: customFileIds)
                |> map { files in
                    return (tags, files)
                }
            }, context.engine.stickers.savedMessageTagData()) |> map { tagsAndFiles, savedMessageTags in
                var result: [SavedMessageTags.Tag] = []
                let tags = tagsAndFiles.0
                let files = tagsAndFiles.1
                for (reaction, count) in tags {
                    let title = savedMessageTags?.tags.first(where: { $0.reaction == reaction })?.title
                    result.append(.init(reaction: reaction, title: title, count: count))
                }
                result = result.sorted(by: { lhs, rhs in
                    if lhs.count != rhs.count {
                        return lhs.count > rhs.count
                    }
                    return lhs.reaction < rhs.reaction

                })
                return (result, files)
            }
        } else {
            tagsAndFiles = .single(([], [:]))
        }

        
        let shortcuts: Signal<ShortcutMessageList?, NoError>
        if peerId.namespace == Namespaces.Peer.CloudUser {
            shortcuts = context.engine.accountData.shortcutMessageList(onlyRemote: true) |> map(Optional.init)
        } else {
            shortcuts = .single(nil)
        }
        
        
        
        let savedChatsAsTopics = context.engine.data.get(TelegramEngine.EngineData.Item.Peer.DisplaySavedChatsAsTopics())
       
        let managingBot = peerView.get() |> map { (($0 as? PeerView)?.cachedData as? CachedUserData)?.peerStatusSettings?.managingBot }
        
        let connectedBot: Signal<ChatBotManagerData?, NoError>
        switch mode {
        case .history:
            connectedBot = combineLatest(context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.BusinessConnectedBot(id: context.peerId)), managingBot) |> mapToSignal { value, managingBot in
               if let value, let managingBot {
                   return context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: value.id)) |> map { peer in
                       return peer.flatMap {
                           .init(bot: value, peer: $0, settings: managingBot)
                       }
                   }
               } else {
                   return .single(nil)
               }
           }
        default:
            connectedBot = .single(nil)
        }
        
        titleUpdateDisposable.set((peerView.get() |> take(1) |> deliverOnMainQueue).start(next: { [weak self] postboxView in
            self?.genericView.bubblesView.update(postboxView as? PeerView, story: nil, counters: .init(), animated: false)
        }))
        
        let updaterPromise: Promise<Any> = Promise(Void())
        
        switch mode {
        case let .customLink(contents):
            contents.interfaceUpdate = {
                updaterPromise.set(.single(Void()))
            }
        default:
            break
        }
        
        
        
        

        monoforumTopics.set(self.peerView.get() |> map { peerView -> PeerViewTuple? in
            if let peerView = peerView as? PeerView, let peer = peerViewMainPeer(peerView) {
                return PeerViewTuple(peer: peer, monoforumPeer: peerViewMonoforumMainPeer(peerView), cachedData: peerView.cachedData)
            } else {
                return nil
            }
        } |> distinctUntilChanged |> mapToQueue { tuple in
            if let channel = tuple?.peer as? TelegramChannel {
                if channel.flags.contains(.isMonoforum), (tuple?.monoforumPeer ?? channel).groupAccess.canManageDirect {
                    return ChatUIHooks.shared.savedMessagesChatListItems(peerId, context.account)
                } else if channel.isForum, channel.displayForumAsTabs(splitState: context.layout) {
                    return ChatUIHooks.shared.forumChatListItems(channel.id, context.account)
                }
            } else if let user = tuple?.peer as? TelegramUser, let botInfo = user.botInfo, botInfo.flags.contains(.hasForum) {
                return ChatUIHooks.shared.botForumChatListItems(peerId, context.account)
            }
            return .single(nil)
        })
        
                
        monoforumTopicsDisposable.set(monoforumTopics.get().startStrict())
        
        
        
        
        let titlePeerView: Signal<PeerView, NoError> = self.chatLocationValue |> mapToSignal { location in
            switch location {
            case let .peer(peerId):
                return context.account.viewTracker.peerView(peerId, updateData: false)
            case let .thread(data):
                if data.isMonoforumPost {
                    return context.account.viewTracker.peerView(PeerId(data.threadId), updateData: false)
                } else {
                    var peerId = peerId
                    if let threadMode = mode.threadMode {
                        switch threadMode {
                        case .savedMessages:
                            peerId = PeerId(data.threadId)
                        default:
                            break
                        }
                    }
                    return context.account.viewTracker.peerView(peerId, updateData: false)
                }
            }
        }

        var botStartCheckedOnPeer = false
        peerDisposable.set(combineLatest(queue: .mainQueue(), topPinnedMessage, peerView.get(), titlePeerView, availableGroupCall, attach, threadInfo, stateValue.get(), tagsAndFiles, getPeerView(peerId: context.peerId, postbox: context.account.postbox), savedChatsAsTopics, shortcuts, connectedBot, updaterPromise.get(), ApplicationSpecificNotice.playedMessageEffects(accountManager: context.sharedContext.accountManager), adMessages, context.starsContext.state, monoforumTopics.get()).start(next: { [weak self] pinnedMsg, postboxView, titlePeerView, groupCallData, attachItems, threadInfo, uiState, savedMessageTags, accountPeer, displaySavedChatsAsTopics, shortcuts, connectedBot, _, playedMessageEffects, adMessages, starsState, monoforumTopics in
            
            
            let firstTime = isFirst.swap(false)
            let animated = !firstTime
                        
            guard let `self` = self else {return}
            self.genericView.bubblesView.update(titlePeerView, story: uiState.storyState, counters: uiState.answersAndOnline, animated: animated)
            let peerView = postboxView as? PeerView
            self.currentPeerView = peerView
            if firstTime, let peerView, let cachedData = peerView.cachedData as? CachedChannelData, cachedData.isNotAccessible {
                context.account.viewTracker.forceUpdateCachedPeerData(peerId: peerView.peerId)
            }
            switch self.chatInteraction.mode {
            case .history, .thread, .customChatContents, .customLink, .preview:
                
                var wasGroupChannel: Bool?
                if let peer = self.chatInteraction.presentation.mainPeer as? TelegramChannel  {
                    if case .group = peer.info {
                        wasGroupChannel = true
                    } else {
                        wasGroupChannel = false
                    }
                }
                var isGroupChannel: Bool?
                if let peerView = peerView, let info = (peerView.peers[peerView.peerId] as? TelegramChannel)?.info {
                    if case .group = info {
                        isGroupChannel = true
                    } else {
                        isGroupChannel = false
                    }
                }
                
                if wasGroupChannel != isGroupChannel {
                    if let isGroupChannel = isGroupChannel, isGroupChannel {
                        let (recentDisposable, _) = context.peerChannelMemberCategoriesContextsManager.recent(peerId: chatInteraction.peerId, updated: { _ in })
                        let (adminsDisposable, _) = context.peerChannelMemberCategoriesContextsManager.admins(peerId: chatInteraction.peerId, updated: { _ in })
                        let disposable = DisposableSet()
                        disposable.add(recentDisposable)
                        disposable.add(adminsDisposable)
                        
                        self.updatedChannelParticipants.set(disposable)
                    } else {
                        self.updatedChannelParticipants.set(nil)
                    }
                    
                }
                
                self.chatInteraction.update(animated: !first.swap(false), { [weak peerView] presentation in
                    if let peerView = peerView, let peer = peerView.peers[peerView.peerId], let mainPeer = peerViewMainPeer(peerView) {
                        var present = presentation.updatedPeer { _ in
                            return peer
                        }.updatedMainPeer(mainPeer)
                            .withUpdatedAccountPeer(accountPeer)
                            .withUpdatedStarsState(starsState)
                        
                        var discussionGroupId:CachedChannelData.LinkedDiscussionPeerId = .unknown
                        if let cachedData = peerView.cachedData as? CachedChannelData {
                            if let peer = mainPeer as? TelegramChannel {
                                switch peer.info {
                                case let .broadcast(info):
                                    if info.flags.contains(.hasDiscussionGroup) {
                                        discussionGroupId = cachedData.linkedDiscussionPeerId
                                    }
                                case .group:
                                    discussionGroupId = cachedData.linkedDiscussionPeerId
                                }
                            }
                        }

                        if let peer = peer as? TelegramSecretChat {
                            if let value = peer.messageAutoremoveTimeout {
                                present = present.withUpdatedMessageSecretTimeout(.known(.init(peerValue: value)))
                            } else {
                                present = present.withUpdatedMessageSecretTimeout(.known(nil))
                            }
                        } else if let cachedData = peerView.cachedData as? CachedUserData {
                            present = present.withUpdatedMessageSecretTimeout(cachedData.autoremoveTimeout)
                        } else if let cachedData = peerView.cachedData as? CachedChannelData {
                            present = present.withUpdatedMessageSecretTimeout(cachedData.autoremoveTimeout)
                                .withUpdatedAllowedReactions(cachedData.reactionSettings.knownValue?.allowedReactions)
                        } else if let cachedData = peerView.cachedData as? CachedGroupData {
                            present = present.withUpdatedMessageSecretTimeout(cachedData.autoremoveTimeout)
                                .withUpdatedAllowedReactions(cachedData.reactionSettings.knownValue?.allowedReactions)
                        }
                        
                        var removePaidMessageFeeData: ChatPresentationInterfaceState.RemovePaidMessageFeeData?
                        
                        
                        
                        if let peer = peerViewMainPeer(titlePeerView) {
                            if let threadInfo, !threadInfo.isMessageFeeRemoved, let channel = peerView.peers[peerView.peerId] as? TelegramChannel, let sendPaidMessageStars = channel.sendPaidMessageStars, channel.isMonoForum {
                                if let linkedMonoforumId = channel.linkedMonoforumId, let mainChannel = peerView.peers[linkedMonoforumId] as? TelegramChannel, mainChannel.hasPermission(.sendSomething) {
                                    removePaidMessageFeeData = ChatPresentationInterfaceState.RemovePaidMessageFeeData(
                                        peer: .init(peer),
                                        amount: sendPaidMessageStars
                                    )
                                }
                            }
                        }
                        
                        

                        
                        present = present.withUpdatedDiscussionGroupId(discussionGroupId)
                        present = present.withUpdatedPinnedMessageId(pinnedMsg)
                        present = present.withUpdatedAttachItems(attachItems)
                        present = present.withUpdatedShortcuts(shortcuts)
                        present = present.withUpdatedConnectedBot(connectedBot)
                        present = present.withUpdatedPlayedMessageEffects(playedMessageEffects ?? [])
                        present = present.withUpdatedMonoforumState(uiState.monoforumState)
                        present = present.withUpdatedRemovePaidMessageFeeData(removePaidMessageFeeData)

                        if let monoforumTopics {
                            let topics = monoforumTopics.map {
                                MonoforumItem(mode: .normal($0))
                            }
                            present = present.withUpdatedMonoforumTopics(topics)
                        }
                        
                        
                        if peer.isBot {
                            present = present.withUpdatedAdMessage(adMessages.fixed)
                        }

                        var contactStatus: ChatPeerStatus?
                        if let cachedData = peerView.cachedData as? CachedUserData {
                            contactStatus = ChatPeerStatus(canAddContact: !peerView.peerIsContact, peerStatusSettings: cachedData.peerStatusSettings)
                        } else if let cachedData = peerView.cachedData as? CachedGroupData {
                            contactStatus = ChatPeerStatus(canAddContact: false, peerStatusSettings: cachedData.peerStatusSettings)
                        } else if let cachedData = peerView.cachedData as? CachedChannelData {
                            contactStatus = ChatPeerStatus(canAddContact: false, peerStatusSettings: cachedData.peerStatusSettings)
                        } else if let cachedData = peerView.cachedData as? CachedSecretChatData {
                            contactStatus = ChatPeerStatus(canAddContact: !peerView.peerIsContact, peerStatusSettings: cachedData.peerStatusSettings)
                        }
                        
                        var activeCall: CachedChannelData.ActiveCall? = nil
                        var callJoinPeerId: PeerId? = nil
                        var inviteRequestsPending: Int32? = nil
                        var sendAsPeerId: PeerId? = nil
                        var isNotAccessible: Bool = false
                        switch mode {
                        case .history, .thread, .customChatContents:
                            if let cachedData = peerView.cachedData as? CachedChannelData {
                                if !mode.isThreadMode {
                                    activeCall = cachedData.activeCall
                                }
                                callJoinPeerId = cachedData.callJoinPeerId
                                inviteRequestsPending = cachedData.inviteRequestsPending
                                sendAsPeerId = cachedData.sendAsPeerId
                                isNotAccessible = cachedData.isNotAccessible
                            } else if let cachedData = peerView.cachedData as? CachedGroupData {
                                activeCall = cachedData.activeCall
                                callJoinPeerId = cachedData.callJoinPeerId
                                inviteRequestsPending = cachedData.inviteRequestsPending
                            }
                        default:
                            break
                        }
                        
                        if let cachedData = peerView.cachedData as? CachedUserData {
                            present = present
                                .withUpdatedBlocked(cachedData.isBlocked)
                                .withUpdatedCanPinMessage(cachedData.canPinMessages || context.peerId == peerId)
                                .updateBotMenu { current in
                                    if let botInfo = cachedData.botInfo {
                                        var current = current ?? .init(commands: [], revealed: false, menuButton: botInfo.menuButton)
                                        current.commands = botInfo.commands
                                        current.menuButton = botInfo.menuButton
                                        return current
                                    }
                                    return nil
                                }
                        } else if let cachedData = peerView.cachedData as? CachedChannelData {
                            if let peer = mainPeer as? TelegramChannel {
                                switch peer.info {
                                case let .group(info):
                                    if info.flags.contains(.slowModeEnabled), peer.adminRights == nil && !peer.flags.contains(.isCreator), !canBypassChatRestrictions(cachedData) {
                                        present = present.updateSlowMode({ value in
                                            var value = value ?? SlowMode()
                                            value = value.withUpdatedValidUntil(cachedData.slowModeValidUntilTimestamp)
                                            if let timeout = cachedData.slowModeValidUntilTimestamp {
                                                if timeout > context.timestamp {
                                                    value = value.withUpdatedTimeout(timeout - context.timestamp)
                                                } else {
                                                    value = value.withUpdatedTimeout(nil)
                                                }
                                            }
                                            return value
                                        })
                                    } else {
                                        present = present.updateSlowMode { _ in return nil }
                                    }
                                default:
                                    present = present.updateSlowMode { _ in return nil }
                                }
                            }
                        }
                        
                        if let notificationSettings = peerView.notificationSettings as? TelegramPeerNotificationSettings {
                            present = present.updatedNotificationSettings(notificationSettings)
                        }
                        present = present.withUpdatedPeerStatusSettings(contactStatus)
                        present = present.withUpdatedInviteRequestsPending(inviteRequestsPending)
                        present = present.withUpdatedCurrentSendAsPeerId(sendAsPeerId)
                        present = present.withUpdatedIsNotAccessible(isNotAccessible)
                        present = present.withUpdatedSavedMessageTags(.init(tags: savedMessageTags.0, files: savedMessageTags.1))
                        present = present.withUpdatedDisplaySavedChatsAsTopics(displaySavedChatsAsTopics)
                        
                        present = present.updatedGroupCall { current in
                            if let call = activeCall {
                                return ChatActiveGroupCallInfo(activeCall: call, data: groupCallData, callJoinPeerId: callJoinPeerId, joinHash: current?.joinHash, isLive: peer.isGigagroup || peer.isChannel)
                            } else {
                                return nil
                            }
                        }
                        
                        
                        present = present.withUpdatedCachedData(peerView.cachedData)
                        return present.withUpdatedThreadInfo(threadInfo)
                            .withUpdatedPresence(peerView.peerPresences[peerView.peerId] as? TelegramUserPresence)
                    }
                    return presentation
                })
            case .scheduled:
                self.chatInteraction.update(animated: !first.swap(false), {  presentation in
                    var presentation = presentation.withUpdatedCanPinMessage(context.peerId == peerId).updatedPeer { _ in
                        if let peerView = peerView {
                            return peerView.peers[peerView.peerId]
                        }
                        return nil
                    }.updatedMainPeer(peerView != nil ? peerViewMainPeer(peerView!) : nil)
                    if let cachedData = peerView?.cachedData as? CachedChannelData {
                        presentation = presentation.withUpdatedCurrentSendAsPeerId(cachedData.sendAsPeerId)
                    }
                    return presentation.withUpdatedCachedData(peerView?.cachedData).withUpdatedThreadInfo(threadInfo)
                })
            case .pinned:
                self.chatInteraction.update(animated: !first.swap(false), { presentation in
                    let pinnedMessage: ChatPinnedMessage? = pinnedMsg
                    return presentation.withUpdatedPinnedMessageId(pinnedMessage).withUpdatedCanPinMessage((peerView?.cachedData as? CachedUserData)?.canPinMessages ?? true || context.peerId == peerId).updatedPeer { _ in
                        if let peerView = peerView {
                            return peerView.peers[peerView.peerId]
                        }
                        return nil
                    }.updatedMainPeer(peerView != nil ? peerViewMainPeer(peerView!) : nil).withUpdatedCachedData(peerView?.cachedData).withUpdatedThreadInfo(threadInfo)
                })
            }
            self.genericView.inputView.isHidden = !self.genericView.showsInput || (self.chatInteraction.presentation.isNotAccessible && !self.canJoinInaccessibleCommunityChat())
            if !animated {
                self.notify(with: self.chatInteraction.presentation, oldValue: ChatPresentationInterfaceState(chatLocation: self.chatLocation, chatMode: self.mode), animated: animated)
            }
            
            if !botStartCheckedOnPeer, self.chatInteraction.peer != nil {
                botStartCheckedOnPeer = true
                if self.historyTransitionApplied {
                    self.updateEmptyBotStartAction()
                }
            }
            
            self._monoforumReady.set(.single(true))

        }))
        
        
    
        
        let updating: Signal<Bool, NoError> = context.account.stateManager.isUpdating |> mapToSignal { isUpdating in
            return isUpdating ? .single(isUpdating) |> delay(1.0, queue: .mainQueue()) : .single(isUpdating)
        }
        
        let connecting: Signal<ConnectionStatus, NoError> = context.account.network.connectionStatus |> mapToSignal { status in
            switch status {
            case .online:
                return .single(status)
            default:
                return .single(status) |> delay(1.0, queue: .mainQueue())
            }
        }
        
        
        let connectionStatus = combineLatest(queue: .mainQueue(), connecting, updating) |> deliverOnMainQueue |> beforeNext { [weak self] status, isUpdating -> Void in
            var status = status
            switch status {
            case let .online(proxyAddress):
                if isUpdating {
                    status = .updating(proxyAddress: proxyAddress)
                }
            default:
                break
            }
            
            self?.genericView.bubblesView.connectionStatus = status
        }
        
        let combine = combineLatest(queue: .mainQueue(), _historyReady.get() |> take(1), appearanceReady.get(), peerView.get() |> take(1) |> map { _ in } |> then(initialData), genericView.inputView.ready.get() |> take(1), _monoforumReady.get() |> take(1))
        
        
        //self.ready.set(.single(true))
        
        self.ready.set(combine |> map { (hReady, appearanceReady, _, iReady, monoforumReady) in
            return hReady && iReady && appearanceReady && monoforumReady
        })
        
        
        connectionStatusDisposable.set((connectionStatus).start())
        
        
       
        
        botCallbackAlertMessageDisposable = (self.botCallbackAlertMessage.get()
            |> deliverOnMainQueue).start(next: { [weak self] (message, isAlert) in
               
                if let strongSelf = self, let message = message {
                    if !message.isEmpty {
                        if isAlert {
                            alert(for: context.window, info: message)
                        } else {
                            strongSelf.chatInteraction.showToaster(.initialize(string: message.fixed, color: theme.colors.text, font: .normal(.text)))
                        }
                    } else {
                        strongSelf.chatInteraction.removeToaster()
                    }
                }
                
            })
        
        switch mode {
        case .history, .thread:
            
            let unreadCount = chatLocationValue |> mapToSignal { location in
                return context.chatLocationUnreadCount(for: location, contextHolder: chatLocationContextHolder)
            } |> deliverOnMainQueue
            
            let unseenPersonalMessages = chatLocationValue |> mapToSignal { location in
                return context.account.viewTracker.unseenPersonalMessagesAndReactionCount(peerId: peerId, threadId: location.threadId)
            } |> deliverOnMainQueue
    
            var previousCounts: (mentions: Int32, reactions: Int32, pollVotes: Int32, scroller: Int32)?
            weak var previousCountsTheme: TelegramPresentationTheme?
            self.chatUnreadMentionCountDisposable.set(combineLatest(queue: .mainQueue(), unseenPersonalMessages, unreadCount).start(next: { [weak self] count, unreadCount in
                let counts = (mentions: count.mentionCount, reactions: count.reactionCount, pollVotes: count.pollVoteCount, scroller: Int32(unreadCount))
                if let previous = previousCounts, previous == counts, previousCountsTheme === theme {
                    return
                }
                previousCounts = counts
                previousCountsTheme = theme
                self?.genericView.updateMentionsCount(mentionsCount: counts.mentions, reactionsCount: counts.reactions, pollVotesCount: counts.pollVotes, scrollerCount: counts.scroller, animated: true)
            }))
        default:
            self.chatUnreadMentionCountDisposable.set(nil)
        }
       
        
        let previousPeerCache = Atomic<[PeerId: Peer]>(value: [:])
        
        
        let peerInputActivities = chatLocationValue |> mapToSignal { location in
            return context.account.peerInputActivities(peerId: .init(peerId: peerId, category: mode.activityCategory(location.threadId)))
        }
        
        self.peerInputActivitiesDisposable.set((peerInputActivities
            |> mapToSignal { activities -> Signal<[(Peer, PeerInputActivity)], NoError> in
                var foundAllPeers = true
                var cachedResult: [(Peer, PeerInputActivity)] = []
                previousPeerCache.with { dict -> Void in
                    for (peerId, activity) in activities {
                        if let peer = dict[peerId] {
                            cachedResult.append((peer, activity))
                        } else {
                            foundAllPeers = false
                            break
                        }
                    }
                }
                if foundAllPeers {
                    return .single(cachedResult)
                } else {
                    return context.account.postbox.transaction { transaction -> [(Peer, PeerInputActivity)] in
                        var result: [(Peer, PeerInputActivity)] = []
                        var peerCache: [PeerId: Peer] = [:]
                        for (peerId, activity) in activities {
                            if let peer = transaction.getPeer(peerId) {
                                result.append((peer, activity))
                                peerCache[peerId] = peer
                            }
                        }
                        _ = previousPeerCache.swap(peerCache)
                        return result
                    }
                }
            }
            |> deliverOnMainQueue).start(next: { [weak self] activities in
                if let strongSelf = self, strongSelf.chatInteraction.peerId != strongSelf.context.peerId {
                    (strongSelf.centerBarView as? ChatTitleBarView)?.inputActivities = (strongSelf.chatInteraction.peerId, activities)
                    strongSelf.genericView.bubblesView.inputActivities = (strongSelf.chatInteraction.peerId, activities)
                    
                    for activity in activities {
                        switch activity.1 {
                        case let .interactingWithEmoji(emoticon, messageId, interaction: interaction):
                            
                            let animations = interaction?.animations ?? []
                            
                            let item = strongSelf.genericView.findItem(by: messageId) as? ChatRowItem
                            
                            if let item = item {
                                let mirror = item.isIncoming && item.renderType == .bubble
                                for animation in animations {
                                    delay(Double(animation.timeOffset), closure: { [weak strongSelf] in
                                        guard let strongSelf = strongSelf else {
                                            return
                                        }
                                        strongSelf.emojiEffects.addAnimation(emoticon.fixed, index: animation.index, mirror: mirror, isIncoming: true, messageId: messageId, animationSize: NSMakeSize(350, 350), viewFrame: context.window.bounds, for: context.window.contentView!)
                                    })
                                }
                            }
                            
                            break
                        default:
                            break
                        }
                    }
                }
            }))
        
        
        
        
        
       // var beginHistoryTime:CFAbsoluteTime?

        genericView.tableView.setScrollHandler({ [weak self] scroll in
            guard let `self` = self else {return}
            
            let view = self.previousView.with { $0?.originalView }
            if let view = view {
                var messageIndex:MessageIndex?

                let visible = self.genericView.tableView.visibleRows()
                
                switch scroll.direction {
                case .top:
                    if view.laterId != nil {
                        for i in visible.min ..< visible.max {
                            if let item = self.genericView.tableView.item(at: i) as? ChatRowItem, !item.ignoreAtInitialization {
                                messageIndex = item.entry.index
                                break
                            }
                        }
                    } else if view.laterId == nil, !view.holeLater, let locationValue = self.locationValue, !locationValue.content.isAtUpperBound, view.anchorIndex != .upperBound {
                        messageIndex = .upperBound(peerId: self.chatInteraction.peerId)
                    }
                case .bottom:
                    if let contents = self.mode.customChatContents {
                        contents.loadMore()
                    } else {
                        if view.earlierId != nil {
                            for i in stride(from: visible.max - 1, to: -1, by: -1) {
                                if let item = self.genericView.tableView.item(at: i) as? ChatRowItem, !item.ignoreAtInitialization {
                                    messageIndex = item.entry.index
                                    break
                                }
                            }
                        }
                    }
                case .none:
                    break
                }
                if let messageIndex = messageIndex {
                    let location: ChatHistoryLocation = .Navigation(index: MessageHistoryAnchorIndex.message(messageIndex), anchorIndex: MessageHistoryAnchorIndex.message(messageIndex), count: 90, side: scroll.direction == .bottom ? .upper : .lower)
                    guard location != self.locationValue?.content else {
                        return
                    }
                    self.setLocation(location)
                }
            }
            if let tempPinnedMaxId = self.chatInteraction.presentation.tempPinnedMaxId {
                let tableView = self.genericView.tableView
                let visibleRows = tableView.visibleRows()
                var isTempPinnedVisible = false
                if visibleRows.length > 0 {
                    for i in visibleRows.min ..< visibleRows.max {
                        if let item = tableView.item(at: i) as? ChatRowItem, item.messages.contains(where: { $0.id == tempPinnedMaxId }) {
                            isTempPinnedVisible = true
                            break
                        }
                    }
                }
                if !isTempPinnedVisible {
                    self.chatInteraction.update({$0.withUpdatedTempPinnedMaxId(nil)})
                }
            }
        })
        
        genericView.tableView.addScroll(listener: TableScrollListener(dispatchWhenVisibleRangeUpdated: false, { [weak self] position in
            guard let `self` = self else {return}
            self.updateInteractiveReading()
        }))
        
        genericView.tableView.addScroll(listener: TableScrollListener(dispatchWhenVisibleRangeUpdated: true, { [weak self] position in
            guard let `self` = self else {return}
            let tableView = self.genericView.tableView
            let chatInteraction = self.chatInteraction
            if self.mode.isThreadMode || self.mode.isTopicMode {
                if let pinnedMessageId = chatInteraction.presentation.pinnedMessageId, position.visibleRows.location != NSNotFound {
                    var hidden: Bool = false
                    for row in position.visibleRows.min ..< position.visibleRows.max {
                        if let item = tableView.item(at: row) as? ChatRowItem {
                            if item.message?.id == pinnedMessageId.others.first {
                                hidden = true
                                break
                            }
                        }
                    }
                    chatInteraction.update({$0.withUpdatedHidePinnedMessage(hidden)})
                }
            }
        }))
        
        genericView.tableView.addScroll(listener: TableScrollListener { [weak self] position in
            self?.heavyScrollWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self] in
                let tableView = self?.genericView.tableView

                if let strongSelf = self, let tableView = tableView {
            
                if let row = tableView.topVisibleRow, let item = tableView.item(at: row) as? ChatRowItem, let id = item.message?.id {
                    strongSelf.historyState = strongSelf.historyState.withRemovingReplies(max: id)
                }
                if !strongSelf.context.window.isKeyWindow {
                    return
                }
                
                var message:Message? = nil
                
                var messageIdsWithViewCount: [MessageId] = []
                var messageIdsWithUnseenPersonalMention: [MessageId] = []
                var messageIdsWithUnseenReactionsOrVotes: [MessageId] = []

                var messageIdsWithReactions:[MessageId] = []
                var unsupportedMessagesIds: [MessageId] = []
                var topVisibleMessageRange: ChatTopVisibleMessageRange?
 
                var messageIdsWithUnsupportedMedia: [MessageId] = []
                var messageIdsWithRefreshMedia: [MessageId] = []
                var messageIdsWithRefreshStories: [MessageId] = []
                var messageIdsWithLiveLocation: [MessageId] = []
                var messageIdsWithInactiveExtendedMedia = Set<MessageId>()
                var messageIdsToFactCheck: [MessageId] = []


                var messagesToTranslate: [Message] = []
                var messagesToTranslateTranscribe: [Message] = []

                
                var allVisibleAnchorMessageIds: [(MessageId, Int)] = []

                var visibleMessageInfos: [MessageReadMetricsManager.VisibleMessageInfo] = []

                var readAds:[Data] = []
                
                tableView.enumerateVisibleItems(with: { item in
                    if let item = item as? ChatRowItem {
                        let height = item.view?.visibleRect.height ?? 0
                        if message == nil, height >= (item.height - 10) {
                            message = item.lastMessage
                        }

                        if let view = item.view {
                            for msg in item.messages {
                                if msg.id.namespace == Namespaces.Message.Cloud {
                                    visibleMessageInfos.append(.init(
                                        messageId: msg.id,
                                        itemHeight: item.height,
                                        visibleRect: view.visibleRect,
                                        viewportHeight: tableView.frame.height
                                    ))
                                }
                            }
                        }

                        for message in item.messages {
                            var hasUncocumedMention: Bool = false
                            var hasUncosumedContent: Bool = false
                            
                            var contentRequiredValidation = false
                            var mediaRequiredValidation = false
                            var storiesRequiredValidation = false
                            var factCheckRequired = false
                            
                            for attribute in message.attributes {
                                if let _ = attribute as? ContentRequiresValidationMessageAttribute {
                                    contentRequiredValidation = true
                                }  else if let _ = attribute as? ReplyStoryAttribute {
                                    storiesRequiredValidation = true
                                } else if let attribute = attribute as? FactCheckMessageAttribute, case .Pending = attribute.content {
                                    factCheckRequired = true
                                }
                            }
                            
                            for media in message.media {
                                if let _ = media as? TelegramMediaUnsupported {
                                    contentRequiredValidation = true
                                } else if message.flags.contains(.Incoming), let media = media as? TelegramMediaMap, let liveBroadcastingTimeout = media.liveBroadcastingTimeout {
                                    let timestamp = Int32(CFAbsoluteTimeGetCurrent() + kCFAbsoluteTimeIntervalSince1970)
                                    if Int(message.timestamp) + Int(liveBroadcastingTimeout) > Int(timestamp) {
                                        messageIdsWithLiveLocation.append(message.id)
                                    }
                                } else if let telegramFile = media as? TelegramMediaFile {
                                    if telegramFile.isAnimatedSticker, (message.id.peerId.namespace == Namespaces.Peer.SecretChat || !telegramFile.previewRepresentations.isEmpty), let size = telegramFile.size, size > 0 && size <= 128 * 1024 {
                                        if message.id.peerId.namespace == Namespaces.Peer.SecretChat {
                                            if telegramFile.fileId.namespace == Namespaces.Media.CloudFile {
                                                var isValidated = false
                                                attributes: for attribute in telegramFile.attributes {
                                                    if case .hintIsValidated = attribute {
                                                        isValidated = true
                                                        break attributes
                                                    }
                                                }
                                                
                                                if !isValidated {
                                                    mediaRequiredValidation = true
                                                }
                                            }
                                        }
                                    }
                                } else if let invoice = media as? TelegramMediaInvoice, let extendedMedia = invoice.extendedMedia, case .preview = extendedMedia {
                                    messageIdsWithInactiveExtendedMedia.insert(message.id)
                                    if invoice.version != TelegramMediaInvoice.lastVersion {
                                        contentRequiredValidation = true
                                    }
                                } else if let paidContent = media as? TelegramMediaPaidContent, let extendedMedia = paidContent.extendedMedia.first, case .preview = extendedMedia {
                                    messageIdsWithInactiveExtendedMedia.insert(message.id)
                                } else if let _ = media as? TelegramMediaStory {
                                    storiesRequiredValidation = true
                                } else if let webpage = media as? TelegramMediaWebpage, case let .Loaded(content) = webpage.content, let _ = content.story {
                                    storiesRequiredValidation = true
                                }
                            }

                            if contentRequiredValidation {
                                messageIdsWithUnsupportedMedia.append(message.id)
                            }
                            if mediaRequiredValidation {
                                messageIdsWithRefreshMedia.append(message.id)
                            }
                            if storiesRequiredValidation {
                                messageIdsWithRefreshStories.append(message.id)
                            }
                            if factCheckRequired {
                                messageIdsToFactCheck.append(message.id)
                            }
                            
                            if message.tags.contains(.unseenPersonalMessage) {
                                for attribute in message.attributes {
                                    if let attribute = attribute as? ConsumableContentMessageAttribute, !attribute.consumed {
                                        hasUncosumedContent = true
                                    }
                                    if let attribute = attribute as? ConsumablePersonalMentionMessageAttribute, !attribute.pending {
                                        hasUncocumedMention = true
                                    }
                                }
                                if hasUncocumedMention && !hasUncosumedContent {
                                    messageIdsWithUnseenPersonalMention.append(message.id)
                                }
                            }
                            if message.tags.contains(.unseenReaction) {
                                messageIdsWithUnseenReactionsOrVotes.append(message.id)
                            }
                            if let poll = message.media.first as? TelegramMediaPoll, poll.results.hasUnseenVotes == true {
                                messageIdsWithUnseenReactionsOrVotes.append(message.id)
                            }
                            
                            if let topVisibleMessageRangeValue = topVisibleMessageRange {
                                topVisibleMessageRange = ChatTopVisibleMessageRange(lowerBound: topVisibleMessageRangeValue.lowerBound, upperBound: message.id, isLast: item.index == tableView.count - 1)
                            } else {
                                topVisibleMessageRange = ChatTopVisibleMessageRange(lowerBound: message.id, upperBound: message.id, isLast: item.index == tableView.count - 1)
                            }
                            
                            if message.id.namespace == Namespaces.Message.Cloud, self?.adMessages?.remainingDynamicAdMessageInterval != nil {
                                allVisibleAnchorMessageIds.append((message.id, item.index))
                            }
                            
                            if let id = message.adAttribute?.opaqueId {
                                if item.height == item.view?.visibleRect.height {
                                    readAds.append(id)
                                }
                            }
                            
                        }
                        
                        if let msg = message, let currentMsg = item.messages.last {
                            if msg.id.namespace == Namespaces.Message.Local && currentMsg.id.namespace == Namespaces.Message.Local {
                                if msg.id < currentMsg.id {
                                    message = currentMsg
                                }
                            }
                        }
                    }
                    return true
                })
                
                
                let state = strongSelf.uiState.with { $0 }
                
                tableView.enumerateVisibleItems(inset: tableView.frame.height, with: { item in
                    if let item = item as? ChatRowItem {
                        
                        if message == nil {
                            message = item.lastMessage
                        }
                        for message in item.messages {
                            inner: for attribute in message.attributes {
                                if attribute is ViewCountMessageAttribute {
                                    messageIdsWithViewCount.append(message.id)
                                    break inner
                                }
                            }
                            if message.anyMedia is TelegramMediaUnsupported {
                                unsupportedMessagesIds.append(message.id)
                            }
                            if message.id.peerId.namespace == Namespaces.Peer.CloudChannel || message.id.peerId.namespace == Namespaces.Peer.CloudGroup {
                                messageIdsWithReactions.append(message.id)
                            }
                            if message.id.namespace == Namespaces.Message.Cloud {
                                if message.author?.id != strongSelf.context.peerId, message.effectivelyIncoming(strongSelf.context.peerId) {
                                    if !message.text.isEmpty {
                                        messagesToTranslate.append(message)
                                    } else if let _ = message.media.first as? TelegramMediaPoll {
                                        messagesToTranslate.append(message)
                                    } else if message.attributes.contains(where: { $0 is RichTextMessageAttribute }) {
                                        messagesToTranslate.append(message)
                                    }
                                    if let media = message.media.first as? TelegramMediaFile, media.isVoice || media.isInstantVideo {
                                        if case .revealed(true) = state.transribe[message.id] {
                                            messagesToTranslateTranscribe.append(message)
                                        }
                                    }
                                }
                                if let reply = message.replyAttribute, let replyMessage = message.associatedMessages[reply.messageId] {
                                    if !replyMessage.text.isEmpty {
                                        messagesToTranslate.append(replyMessage)
                                    }
                                }
                            }
                        }
                    }
                    return true
                })

                
                if topVisibleMessageRange != nil {
                    strongSelf.topVisibleMessageRange.set(topVisibleMessageRange)
                }

                if !readAds.isEmpty {
                    for data in readAds {
                        strongSelf.adMessages?.markAsSeen(opaqueId: data)
                    }
                }
                                
                if !messageIdsWithViewCount.isEmpty {
                    strongSelf.messageProcessingManager.add(messageIdsWithViewCount)
                }
                if !messageIdsWithLiveLocation.isEmpty {
                    strongSelf.seenLiveLocationProcessingManager.add(messageIdsWithLiveLocation)
                }
                if !messageIdsWithUnsupportedMedia.isEmpty {
                    strongSelf.unsupportedMessageProcessingManager.add(messageIdsWithUnsupportedMedia)
                }
                if !messageIdsWithRefreshMedia.isEmpty {
                    strongSelf.refreshMediaProcessingManager.add(messageIdsWithRefreshMedia)
                }
                if !messageIdsWithRefreshStories.isEmpty {
                    strongSelf.refreshStoriesProcessingManager.add(messageIdsWithRefreshStories)
                }
                if !messageIdsToFactCheck.isEmpty {
                    strongSelf.factCheckProcessingManager.add(messageIdsToFactCheck)
                }
                if !messageIdsWithInactiveExtendedMedia.isEmpty {
                    strongSelf.extendedMediaProcessingManager.update(messageIdsWithInactiveExtendedMedia)
                }

                if !messageIdsWithUnseenPersonalMention.isEmpty {
                    strongSelf.messageMentionProcessingManager.add(messageIdsWithUnseenPersonalMention)
                }
                if !messageIdsWithUnseenReactionsOrVotes.isEmpty {
                    strongSelf.messageReactionsMentionProcessingManager.add(messageIdsWithUnseenReactionsOrVotes)
                }
                if !unsupportedMessagesIds.isEmpty {
                    strongSelf.unsupportedMessageProcessingManager.add(unsupportedMessagesIds)
                }
                
                if !messageIdsWithReactions.isEmpty {
                    strongSelf.reactionsMessageProcessingManager.add(messageIdsWithReactions)
                }
                
                if let message = message {
                    strongSelf.updateMaxVisibleReadIncomingMessageIndex(MessageIndex(message))
                }
                
                if let pinned = strongSelf.chatInteraction.presentation.pinnedMessageId, let message = pinned.message, !message.text.isEmpty, message.author?.id != strongSelf.context.peerId {
                    messagesToTranslate.append(message)
                }
                
                if !messagesToTranslate.isEmpty {
                    strongSelf.liveTranslate?.translate(messagesToTranslate.sorted(by: { $0.id < $1.id}))
                }
                if !messagesToTranslateTranscribe.isEmpty {
                    strongSelf.liveTranslate?.translateTranscription(messagesToTranslateTranscribe.sorted(by: { $0.id < $1.id}))
                }
                
                if !allVisibleAnchorMessageIds.isEmpty {
                    self?.adMessages?.update(items: allVisibleAnchorMessageIds, tableView: tableView, position: position)
                }

                strongSelf.readMetricsManager?.updateVisibleMessages(visibleMessageInfos)
                strongSelf.readMetricsManager?.recordUserActivity()

                }
            }
            self?.heavyScrollWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
        })

        switch self.mode {
        case .history, .thread:
            let hasScheduledMessages = combineLatest(peerView.get(), chatLocationValue)
            |> take(1)
            |> mapToSignal { view, chatLocation -> Signal<Bool, NoError> in
                if let view = view as? PeerView, let peer = peerViewMainPeer(view) as? TelegramChannel, !peer.hasPermission(.sendSomething) {
                    return .single(false)
                } else {
                    return context.account.viewTracker.scheduledMessagesViewForLocation(.peer(peerId: peerId, threadId: chatLocation.threadId))
                        |> map { view, _, _ in
                            return !view.entries.isEmpty
                    }
                }
            } |> deliverOnMainQueue
            
            hasScheduledMessagesDisposable.set(hasScheduledMessages.start(next: { [weak self] hasScheduledMessages in
                self?.chatInteraction.update({
                    $0.withUpdatedHasScheduled(hasScheduledMessages)
                })
            }))
            
        default:
            break
        }
        
    
        
        let discussion: Signal<Void, NoError> = peerView.get()
            |> deliverOnMainQueue
            |> map { view -> PeerId? in
                if let threadId = threadId64() {
                    return PeerId(threadId)
                }
                if let value = (view as? PeerView)?.cachedData as? CachedChannelData, case let .known(peerId) = value.linkedDiscussionPeerId {
                    return peerId
                }
                return nil
        } |> distinctUntilChanged |> mapToSignal { peerId in
            if let peerId = peerId {
                return context.account.viewTracker.polledChannel(peerId: peerId)
            }
            return .single(Void())
        }
        
       
        
        
        pollChannelDiscussionDisposable.set(discussion.start())
        
        
        let personalChannelSignal: Signal<Void, NoError>
        if peerId.namespace == Namespaces.Peer.CloudUser {
            personalChannelSignal = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.PersonalChannel(id: peerId)) |> mapToSignal { value in
                switch value {
                case let .known(channel):
                    if let channel = channel {
                        return context.account.viewTracker.aroundMessageHistoryViewForLocation(.peer(peerId: channel.peerId, threadId: nil), index: .upperBound, anchorIndex: .upperBound, count: 10, fixedCombinedReadStates: nil) |> map { _ in }
                    } else {
                        return .single(Void())
                    }
                case .unknown:
                    return .single(Void())
                }
            }
        } else {
            personalChannelSignal = .single(Void())
        }
        
        preloadPersonalChannel.set(personalChannelSignal.start())
        
        self.premiumOrStarsRequiredDisposable.set(((self.context.engine.peers.isPremiumRequiredToContact([peerId]) |> then(.complete() |> suspendAwareDelay(60.0, queue: Queue.concurrentDefaultQueue()))) |> restart).startStandalone())
        
        
        let count = 50
        let location:ChatHistoryLocation
        
        switch chatLocation() {
        case let .thread(data):
            switch data.initialAnchor {
            case .automatic:
                if let messageId = self.focusTarget?.messageId {
                    location = .InitialSearch(location: .id(messageId, self.focusTarget?.string, self.focusTarget?.range), count: count, cachedAnchor: self.focusTarget?.cachedAnchor == true)
                } else {
                    location = .Initial(count: count, scrollPosition: nil)
                }
            case let .lowerBoundMessage(index):
                location = .Scroll(index: .message(index), anchorIndex: .message(index), sourceIndex: .message(index), scrollPosition: .up(false), count: count, animated: false)
            }
        default:
            if let messageId = self.focusTarget?.messageId {
                location = .InitialSearch(location: .id(messageId, self.focusTarget?.string, self.focusTarget?.range), count: count, cachedAnchor: self.focusTarget?.cachedAnchor == true)
            } else {
                location = .Initial(count: count, scrollPosition: nil)
            }
        }
        let id = self.takeNextHistoryLocationId()
        
        do {
            let chatLocation: ChatLocation
            if case let .openTopic(thread) = self.chatInteraction.presentation.initialAction {
                chatLocation = .thread(thread)
            } else {
                chatLocation = self.chatLocation
            }
            
            
            let update:(ChatLocation)->Void = { [weak self] chatLocation in
                guard let self else {
                    return
                }
                self.setLocation(.init(content: location, chatLocation: chatLocation, tag: self.mode.tagMask.flatMap { .tag($0) }, id: id))
                
                self.chatInteraction.update({
                    $0.withUpdatedChatLocation(chatLocation)
                })
            }
            
            update(chatLocation)
            
        }
        
     
    }
    
    private var subscribedToPeerId: PeerId?
    private func subscribeForNewTopicEvents(peerId: PeerId?) {
        if subscribedToPeerId != peerId {
            if let peerId {
                self.newTopicEventsDisposable.set((self.context.account.pendingMessageManager.newTopicEvents(peerId: peerId)
                |> mapToSignal { event -> Signal<Int64, NoError> in
                    if case let .didMove(fromThreadId, toThreadId) = event {
                        if fromThreadId == EngineMessage.newTopicThreadId {
                            return .single(toThreadId)
                        }
                    }
                    return .never()
                }
                |> deliverOnMainQueue).startStrict(next: { [weak self] threadId in
                    guard let self else {
                        return
                    }
                    self.chatInteraction.updateChatLocationThread(threadId)
                }))
            } else {
                self.newTopicEventsDisposable.set(nil)
            }
        }
        self.subscribedToPeerId = peerId
    }

    public override func updateFrame(_ frame: NSRect, inset: CGFloat, transition: ContainedViewLayoutTransition) {
        super.updateFrame(frame, inset: inset, transition: transition)
        self.genericView.updateFrame(frame, inset: inset, transition: transition)
    }

    public override func updateNavigationHeaderOverflow(_ overflow: CGFloat, transition: ContainedViewLayoutTransition) {
        super.updateNavigationHeaderOverflow(overflow, transition: transition)
        if isLoaded() {
            self.genericView.updateNavigationOverflow(overflow, transition: transition)
        }
    }
    
    private func openScheduledChat() {
        self.chatInteraction.saveState(scrollState: self.immediateScrollState())
        self.navigationController?.push(ChatScheduleController(context: context, chatLocation: self.chatLocation))
    }

    public override func windowDidBecomeKey() {
        super.windowDidBecomeKey()
        updateInteractiveReading()
        chatInteraction.saveState(scrollState: immediateScrollState())
        self.genericView.tableView.notifyScrollHandlers()
        readMetricsManager?.resume()
        setVisibleRefreshActive(true)
    }
    public override func windowDidResignKey() {
        super.windowDidResignKey()
        updateInteractiveReading()
        chatInteraction.saveState(scrollState:immediateScrollState())
      // self.genericView.tableView.notifyScrollHandlers()
        readMetricsManager?.pause()
        setVisibleRefreshActive(false)
    }
    
    private func setVisibleRefreshActive(_ isActive: Bool) {
        reactionsMessageProcessingManager.setActive(isActive)
        factCheckProcessingManager.setActive(isActive)
    }
    
    private func anchorMessageInCurrentHistoryView() -> Message? {
        
        let historyView = self.previousView.with { $0 }
        if let historyView = historyView {
            let visibleRange = self.genericView.tableView.visibleRows()
            var index = 0
            for entry in historyView.filteredEntries.reversed() {
                if index >= visibleRange.min && index <= visibleRange.max {
                    if case let .MessageEntry(message, _, _, _, _, _, _) = entry.entry {
                        return message
                    }
                }
                index += 1
            }
            
            for entry in historyView.filteredEntries {
                if let message = entry.appearance.entry.message {
                    return message
                }
            }
        }
        return nil
    }
    
    private func visibleMessageIdsForReading(_ messageIds: Set<MessageId>) -> Set<MessageId> {
        guard self.interactiveReadEnabled, self.context.window.isKeyWindow,
              ChatUIHooks.shared.appIsLockedValue() != true,
              !self.genericView.tableView.clipView.isAnimateScrolling else {
            return []
        }
        var visibleIds = Set<MessageId>()
        self.genericView.tableView.enumerateVisibleItems(with: { item in
            if let item = item as? ChatRowItem, let view = item.view, view.visibleRect.height > 0 {
                for message in item.messages where message.id.namespace == Namespaces.Message.Cloud && messageIds.contains(message.id) {
                    visibleIds.insert(message.id)
                }
            }
            return true
        })
        return visibleIds
    }

    private func canInteractiveRead() -> Bool {
        guard self.interactiveReadEnabled, !self.genericView.tableView.clipView.isAnimateScrolling else { return false }
        let scroll = genericView.scroll
        let hasEntries = self.previousView.with { $0?.filteredEntries.count ?? 0 } > 1
        let checkScroll = self.historyState.isDownOfHistory && scroll.rect.minY == genericView.tableView.frame.height && hasEntries
        let screenIsLocked = ChatUIHooks.shared.appIsLockedValue() ?? false
        if checkScroll, !screenIsLocked, context.window.isKeyWindow {
            return true
        } else {
            return false
        }
    }
    
    private struct InteractiveReadingKey: Equatable {
        let peerId: PeerId
        let threadId: Int64?
    }
    private var installedInteractiveReadingKey: InteractiveReadingKey?
    
    private func updateInteractiveReading() {
        switch mode {
        case .history:
            if self.canInteractiveRead() {
                let key = InteractiveReadingKey(peerId: chatInteraction.peerId, threadId: self.chatLocation.threadId)
                if self.installedInteractiveReadingKey == key {
                    return
                }
                self.installedInteractiveReadingKey = key
                self.interactiveReadingDisposable.set(context.engine.messages.installInteractiveReadMessagesAction(peerId: chatInteraction.peerId, threadId: self.chatLocation.threadId))

                let visibleMessageRange = self.visibleMessageRange
                self.interactiveReadReactionsDisposable.set(context.engine.messages.installInteractiveReadReactionsAction(peerId: chatInteraction.peerId, getVisibleRange: {

                    return visibleMessageRange.with { $0 }
                }, didReadReactionsInMessages: { [weak self] idsAndReactions in
                    Queue.mainQueue().after(0.1, {
                        self?.playUnseenReactions(Set(idsAndReactions.keys))
                    })
                }))


            } else {
                self.installedInteractiveReadingKey = nil
                self.interactiveReadingDisposable.set(nil)
                self.interactiveReadReactionsDisposable.set(nil)
            }

        default:
            self.installedInteractiveReadingKey = nil
            self.interactiveReadingDisposable.set(nil)
            self.interactiveReadReactionsDisposable.set(nil)
        }
        
    }
    
    
    
    private func messageInCurrentHistoryView(_ id: MessageId) -> Message? {
        return self.previousView.with { view in
            if let historyView = view {
                for entry in historyView.filteredEntries {
                    if let message = entry.appearance.entry.message, message.id == id {
                        return message
                    }
                }
            }
            return nil
        }
    }
    
    func isSearchAvailable(_ presentation: ChatPresentationInterfaceState) -> Bool {
        if presentation.reportMode != nil {
            return false
        }
        if chatInteraction.mode == .preview {
            return false
        }
        if presentation.chatMode.customChatContents != nil {
            return false
        }
        var isEmpty: Bool = genericView.tableView.isEmpty
        if chatInteraction.mode.isThreadMode {
            isEmpty = genericView.tableView.count == (theme.bubbled ? 4 : 3)
        }
        if chatInteraction.mode == .scheduled || isEmpty {
            return false
        } else {
            return true
        }
    }
    
    var searchAvailable: Bool {
        isSearchAvailable(chatInteraction.presentation)
    }
    
    private var checkMessageExists: Bool = true
    public override func updateBackgroundColor(_ backgroundMode: TableBackgroundMode) {
        super.updateBackgroundColor(backgroundMode)
        genericView.updateBackground(backgroundMode, navigationView: self.navigationController?.view, isStandalone: self.navigationController?.modal != nil || self.context.isExternal)
        
    }

    private var isPushedGlobalBackground: Bool = false
    
    private var currentDeleteAnimationCorrelationIds = Set<ChatHistoryEntryId>()
    func setCurrentDeleteAnimationCorrelationIds(_ value: Set<ChatHistoryEntryId>) {
        self.currentDeleteAnimationCorrelationIds = value
    }

    private weak var dustLayerView: DustLayerView? = nil
    
    private func checkMessageDeletions(_ previous: ChatHistoryView?, _ currentView: ChatHistoryView) {
        
        if TelegramUtilsHooks.shared.isLite(.animations) {
            return
        }
        if hasModals(context.window) || !context.window.isKeyWindow {
            return
        }
        
        CATransaction.begin()
        

        var expiredMessageStableIds = Set<ChatHistoryEntryId>()
        if let previousHistoryView = self.historyView {
            var existingStableIds = Set<ChatHistoryEntryId>()
            for entry in currentView.filteredEntries {
                switch entry.entry {
                case .MessageEntry:
                    existingStableIds.insert(entry.entry.stableId)
                case .groupedPhotos:
                    existingStableIds.insert(entry.entry.stableId)
                default:
                    break
                }
            }
            let currentTimestamp = Int32(context.timestamp)
            var maybeRemovedInteractivelyMessageIds: [(ChatHistoryEntryId, EngineMessage.Id)] = []
            for entry in previousHistoryView.filteredEntries {
                let entryStableId = entry.entry.stableId
                switch entry.entry {
                case let .MessageEntry(message, _, _, _, _, _, _):
                    if !existingStableIds.contains(entryStableId) {
                        if let autoremoveAttribute = message.autoremoveAttribute, let countdownBeginTime = autoremoveAttribute.countdownBeginTime {
                            let exipiresAt = countdownBeginTime + autoremoveAttribute.timeout
                            if exipiresAt <= currentTimestamp - 1 {
                                expiredMessageStableIds.insert(entryStableId)
                            } else {
                                maybeRemovedInteractivelyMessageIds.append((entryStableId, message.id))
                            }
                        } else {
                            maybeRemovedInteractivelyMessageIds.append((entryStableId, message.id))
                        }
                    }
                case let .groupedPhotos(entries, _):
                    let isRemoved = !existingStableIds.contains(entryStableId)
                    if isRemoved, let message = entries.first?.message {
                        if let autoremoveAttribute = message.autoremoveAttribute, let countdownBeginTime = autoremoveAttribute.countdownBeginTime {
                            let exipiresAt = countdownBeginTime + autoremoveAttribute.timeout
                            if exipiresAt <= currentTimestamp - 1 {
                                expiredMessageStableIds.insert(entryStableId)
                            } else {
                                maybeRemovedInteractivelyMessageIds.append((entryStableId, message.id))
                            }
                        } else {
                            maybeRemovedInteractivelyMessageIds.append((entryStableId, message.id))
                        }
                    }
                default:
                    break
                }
            }
            
            var testIds: [MessageId] = []
            if !maybeRemovedInteractivelyMessageIds.isEmpty {
                for (_, id) in maybeRemovedInteractivelyMessageIds {
                    testIds.append(id)
                }
            }
            for id in self.context.engine.messages.synchronouslyIsMessageDeletedInteractively(ids: testIds) {
                inner: for (stableId, listId) in maybeRemovedInteractivelyMessageIds {
                    if listId == id {
                        expiredMessageStableIds.insert(stableId)
                        break inner
                    }
                }
            }
        }
        self.currentDeleteAnimationCorrelationIds.formUnion(expiredMessageStableIds)
        var appliedDeleteAnimationCorrelationIds = Set<ChatHistoryEntryId>()

        if !self.currentDeleteAnimationCorrelationIds.isEmpty {
            var foundItemViews: [NSView] = []
            self.genericView.tableView.enumerateViews(with: { view in
                if let view = view as? ChatRowView, let item = view.item as? ChatRowItem, item.height < 300 {
                    let entryId = item.entry.stableId
                    if self.currentDeleteAnimationCorrelationIds.contains(entryId) {
                        appliedDeleteAnimationCorrelationIds.insert(entryId)
                        self.currentDeleteAnimationCorrelationIds.remove(entryId)
                        foundItemViews.append(view.rowView)
                    }
                } else if #available(macOS 10.15, *), let view = view as? ChatServiceRowView, let item = view.item as? ChatServiceItem, item.height < 300, let transferView = view.walletTransferView {
                    let entryId = item.entry.stableId
                    if self.currentDeleteAnimationCorrelationIds.contains(entryId) {
                        appliedDeleteAnimationCorrelationIds.insert(entryId)
                        self.currentDeleteAnimationCorrelationIds.remove(entryId)
                        foundItemViews.append(transferView)
                    }
                }
                return true
            })
            if dustLayerView == nil {
                self.dustLayerView = ApplyDustAnimations(for: foundItemViews, superview: self.dustLayerView)
            }
        }
        CATransaction.commit()
    }

    private var historyView: ChatHistoryView?
    
    private var historyTransitionApplied: Bool = false
    
    private func updateEmptyBotStartAction() {
        if genericView.tableView.isEmpty, let peer = chatInteraction.peer, peer.isBot {
            if chatInteraction.presentation.initialAction == nil && self.genericView.state == .visible, chatInteraction.presentation.monoforumState == nil {
                chatInteraction.update(animated: false, {$0.updatedInitialAction(.start(parameter: "", behavior: .none))})
            }
        }
    }
    
    func applyTransition(_ transition:TableUpdateTransition, initialData:ChatHistoryCombinedInitialData, isLoading: Bool, processedView: ChatHistoryView) {
        
                
        let wasEmpty = genericView.tableView.isEmpty
        genericView.chatTheme = processedView.theme
        self.updateBackgroundColor(processedView.theme.controllerBackgroundMode)

        initialDataHandler.set(.single(initialData))
        
        historyState = historyState.withUpdatedStateOfHistory(processedView.originalView?.laterId == nil)
        
        let oldState = genericView.state
        
        
        
        
        let animated: Bool
        switch transition.state {
        case let .none(interface):
            animated = interface != nil
        default:
            animated = transition.animated
        }
        
        var appearAnimated: Bool = false
        if !nextTransaction.isExutable, !transition.isPartOfTransition, !transition.inserted.isEmpty, transition.inserted.allSatisfy({ $0.1.ignoreAtInitialization }) {
            switch transition.state {
            case .none, .saveVisible:
                appearAnimated = genericView.tableView.documentOffset == .zero
            default:
                break
            }
        }
        
        if case .none = transition.state {
            checkMessageDeletions(self.historyView, processedView)
        }

        self.currentAnimationRows = []
        
        self.updateHasPhotos(processedView.theme)
        
        let _ = nextTransaction.execute()

        if #available(macOS 10.15, *) {
            chatInteraction.walletTransferAnimation?.updateOpenReadStates(processedView.originalView?.fixedReadStates)
        }
        #if DEBUG
        let mergeProbe = ChatMergeProbe.begin(table: genericView.tableView, transition: transition)
        #endif
        genericView.tableView.merge(with: transition, appearAnimated: appearAnimated)
        #if DEBUG
        ChatMergeProbe.end(mergeProbe, transition: transition, visible: genericView.tableView.visibleRows(), table: genericView.tableView)
        #endif
        chatInteraction.voiceSendFlight?.tableDidUpdate()
        self.textSendFlight?.tableDidUpdate()
        chatInteraction.mediaSendFlight?.tableDidUpdate()
        self.lastFloatingCollectKey = nil
        collectFloatingPhotos(animated: animated && transition.state.isNone, currentAnimationRows: currentAnimationRows)

        
        self.genericView.tableView.notifyScrollHandlers()
        
                   
        let showsCachedAnchor = processedView.originalView?.isAnchorOnlyWhileLoading == true
        genericView.change(state: isLoading && !showsCachedAnchor ? .progress : .visible, animated: processedView.originalView != nil)
        if !isLoading {
            self.historyTransitionApplied = true
        }
        

        
        if oldState != genericView.state {
            genericView.tableView.updateEmpties(animated: previousView.with { $0?.originalView != nil })
        }
        
       
        
       // genericView.tableView.notifyScrollHandlers()
        
        if !transition.isEmpty, let afterNextTransaction = self.afterNextTransaction {
            delay(0.1, closure: afterNextTransaction)
            self.afterNextTransaction = nil
        }
        
        
        self.genericView.bubblesView.updateSearchButton(hidden: !searchAvailable, animated: transition.animated)
        
        self.updateEmptyBotStartAction()
        chatInteraction.update(animated: !wasEmpty, { current in
            let messagesCount = processedView.originalView?.entries.count ?? 0
            var current = current.updatedHistoryCount(messagesCount).updatedKeyboardButtonsMessage(initialData.buttonKeyboardMessage)
            
            if let message = initialData.buttonKeyboardMessage {
                if message.requestsSetupReply {
                    if message.id != current.interfaceState.dismissedForceReplyId {
                        current = current.updatedInterfaceState({
                            $0.withUpdatedReplyMessageId(.init(messageId: message.id, quote: nil, innerSubject: nil))
                        })
                    }
                }
            }
            
            return current
        })
        
        readyHistory()
        
        updateInteractiveReading()
        
        
        self.centerBarView.animates = true
        
        self.chatInteraction.invokeInitialAction(includeAuto: true, animated: false)
        
        
        genericView.tableView.enumerateVisibleViews(with: { view in
            if let view = view as? ChatRowView {
                view.updateBackground(animated: transition.animated, item: view.item)
            }
        })
        
        
        
        switch self.mode {
        case .pinned:
            if genericView.tableView.isEmpty {
                navigationController?.back()
            }
        default:
            break
        }
        if !isLoading && checkMessageExists {
            switch self.locationValue?.content {
            case let .InitialSearch(location, _, _):
                switch location {
                case let .id(messageId, _, _):
                    checkMessageExists = false

                    delay(1.5, closure: { [weak self] in
                        guard let `self` = self else {
                            return
                        }
                        var found: Bool = false
                        self.genericView.tableView.enumerateItems(with: { item in
                            if let item = item as? ChatRowItem {
                                found = item.messages.contains(where: { $0.id == messageId })
                            }
                            return !found
                        })
                        if !found, !self.genericView.tableView.isEmpty {
                            showModalText(for: context.window, text: strings().chatOpenMessageNotExist, title: nil)
                        }
                    })
                default:
                    break
                }
            default:
                break
            }
        }
        
        if !isLoading {
            var items:[ChatRowItem] = []
            var animatedEmojiItems:[ChatRowItem] = []
            var effectItems:[ChatRowItem] = []
            
            var played: Set<MessageId>?

            self.genericView.tableView.enumerateVisibleItems(with: { item in
                if let item = item as? ChatRowItem, let view = item.view, let message = item.message {
                    var target: ChatPlayEffectTarget?
                    if let file = message.anyMedia as? TelegramMediaFile {
                        if !file.noPremium, !context.premiumIsBlocked, file.isPremiumSticker {
                            target = .premiumSticker
                        } else if file.isEmojiAnimatedSticker || file.isCustomEmoji, file.isPremiumEmoji {
                            if message.globallyUniqueId != nil || message.flags.contains(.Incoming) {
                                target = .animatedEmoji
                            }
                        }
                    } else if let _ = item.entry.additionalData.messageEffect {
                        if message.globallyUniqueId != nil || message.flags.contains(.Incoming) {
                            target = .effect
                        }
                    }
                    if let target {
                        let playedSet = played ?? Set(chatInteraction.presentation.playedMessageEffects)
                        played = playedSet
                        if !playedSet.contains(message.id), view.visibleRect == view.bounds {
                            switch target {
                            case .premiumSticker:
                                items.append(item)
                            case .animatedEmoji:
                                animatedEmojiItems.append(item)
                            case .effect:
                                effectItems.append(item)
                            }
                        }
                    }
                }
                return true
            })
            
            let playedIds = (items + animatedEmojiItems + effectItems).compactMap { $0.message?.id }
            
            for item in items {
                if let message = item.message {
                    let mirror = item.renderType == .list || message.isIncoming(item.itemContext.account, item.renderType == .bubble)
                    chatInteraction.runPremiumScreenEffect(message, mirror, false)
                }
            }
            for item in effectItems {
                if let message = item.message {
                    let mirror = item.renderType == .list ? false : message.isIncoming(item.itemContext.account, item.renderType == .bubble)
                    chatInteraction.runPremiumScreenEffect(message, mirror, false)
                }
            }
            for item in animatedEmojiItems {
                if let message = item.message {
                    let mirror = item.renderType == .list || message.isIncoming(item.itemContext.account, item.renderType == .bubble)
                    if let emoji = message.file?.stickerText {
                        chatInteraction.runEmojiScreenEffect(emoji, message, mirror, false)
                    }
                }
            }
            if !playedIds.isEmpty {
                _ = ApplicationSpecificNotice.addPlayedMessageEffects(accountManager: context.sharedContext.accountManager, values: playedIds).startStandalone()
            }
        }
        
        if !didSetReady {
            self.genericView.inputView.updateInterface(with: self.chatInteraction)
        }
        self.didSetReady = true
        
        
        

        
        self.historyView = processedView
                
    }
    
    
    fileprivate func buildChatActionsMenu() -> ContextMenu? {
        let context = self.context
        let chatLocation = self.chatLocation

        guard let peerView = self.currentPeerView, peerViewMainPeer(peerView)?.restrictionText(context.contentSettings) == nil else {
            return nil
        }

        guard !context.isFrozen else {
            return nil
        }

        let chatInteraction = self.chatInteraction
        let menu = ContextMenu(betterInside: true)
        let mode = self.mode
        var items: [ContextMenuItem] = []
        let peerId = chatLocation.peerId

        switch mode {
        case .history, .thread:
            if peerId == context.peerId {
                let displaySavedChatsAsTopics = chatInteraction.presentation.displaySavedChatsAsTopics

                items.append(ContextMenuItem(strings().chatSavedMessagesViewAsMessages, handler: { [weak self] in
                    context.engine.peers.updateSavedMessagesViewAsTopics(value: false)
                    ChatUIHooks.shared.navigateToChat(self?.navigationController, context, .peer(context.peerId))
                }, itemImage: !displaySavedChatsAsTopics ? MenuAnimation.menu_check_selected.value : nil))

                items.append(ContextMenuItem(strings().chatSavedMessagesViewAsChats, handler: { [weak self] in
                    context.engine.peers.updateSavedMessagesViewAsTopics(value: true)
                    self?.navigationController?.back()
                    ChatUIHooks.shared.openForum(context.peerId, true, context)
                }, itemImage: displaySavedChatsAsTopics ? MenuAnimation.menu_check_selected.value : nil))

                items.append(ContextSeparatorItem())
            }
        default:
            break
        }

        switch self.mode {
        case .scheduled:
            items.append(ContextMenuItem(strings().chatContextClearScheduled, handler: {
                verifyAlert_button(for: context.window, header: strings().chatContextClearScheduledConfirmHeader, information: strings().chatContextClearScheduledConfirmInfo, ok: strings().chatContextClearScheduledConfirmOK, successHandler: { _ in
                    _ = context.engine.messages.clearHistoryInteractively(peerId: peerId, threadId: nil, type: .scheduledMessages).start()
                })
            }, itemImage: MenuAnimation.menu_schedule_message.value))
        case .history:

            if let peer = peerViewMainPeer(peerView), TelegramUtilsHooks.shared.peerIsForum(peer) && peer.displayForumAsTabs(splitState: context.layout) {
                items.append(ContextMenuItem(strings().forumTopicContextNew, handler: {
                    ChatUIHooks.shared.createForumTopic(peer.id, context)
                }, itemImage: MenuAnimation.menu_plus.value))

                items.append(ContextSeparatorItem())
            }

            switch chatLocation {
            case let .peer(peerId):

                items.append(ContextMenuItem(strings().chatContextEdit1, handler: { [weak self] in
                    self?.changeState()
                }, itemImage: MenuAnimation.menu_edit.value))

                if peerId != repliesPeerId {
                    items.append(ContextMenuItem(strings().chatContextInfo, handler: { [weak self] in
                        self?.chatInteraction.openInfo(peerId, false, nil, nil)
                    }, itemImage: MenuAnimation.menu_show_info.value))
                }


                if let notificationSettings = peerView.notificationSettings as? TelegramPeerNotificationSettings, !self.isAdChat {
                    if chatInteraction.peerId != context.peerId {
                        items.append(ContextMenuItem(!notificationSettings.isMuted ? strings().chatContextEnableNotifications : strings().chatContextDisableNotifications, handler: { [weak self] in
                            self?.chatInteraction.toggleNotifications(notificationSettings.isMuted)
                        }, itemImage: notificationSettings.isMuted ? MenuAnimation.menu_unmuted.value : MenuAnimation.menu_mute.value))
                    }
                }

                if let peer = peerView.peers[peerView.peerId], let mainPeer = peerViewMainPeer(peerView), !mainPeer.isMonoForum {

                    var activeCall = (peerView.cachedData as? CachedGroupData)?.activeCall
                    activeCall = activeCall ?? (peerView.cachedData as? CachedChannelData)?.activeCall

                    let canDeleteForAll: Bool? = (peerView.cachedData as? CachedChannelData)?.flags.contains(.canDeleteHistory)

                    if peer.groupAccess.canMakeVoiceChat {
                        var isLiveStream: Bool = false
                        if let peer = peer as? TelegramChannel {
                            isLiveStream = peer.isChannel || peer.flags.contains(.isGigagroup)
                        }
                        items.append(ContextMenuItem(isLiveStream ? strings().peerInfoActionLiveStream : strings().peerInfoActionVoiceChat, handler: { [weak self] in
                            self?.makeVoiceChat(activeCall, callJoinPeerId: nil)
                        }, itemImage: MenuAnimation.menu_video_chat.value))
                    }
                    if peer.isUser, peer.id != context.peerId {
                        if !peer.isBot, !isServicePeer(peer) {
                            items.append(ContextMenuItem(strings().peerInfoActionVideoCall, handler: { [weak self] in
                                self?.chatInteraction.call(isVideo: true)
                            }, itemImage: MenuAnimation.menu_video_call.value))
                        }

                        if !isServicePeer(peer) {
                            items.append(ContextMenuItem(strings().chatContextCreateGroup, handler: { [weak self] in
                                self?.createGroup()
                            }, itemImage: MenuAnimation.menu_create_group.value))
                        }
                        if !isServicePeer(peer), chatInteraction.presentation.sendPaidMessageStars == nil {
                            items.append(ContextMenuItem(strings().peerInfoChatBackground, handler: { [weak self] in
                                self?.showChatThemeSelector()
                            }, itemImage: MenuAnimation.menu_change_colors.value))
                        }
                    }
                    let deleteChat = { [weak self] in
                        guard let `self` = self else { return }
                        let signal = ChatUIHooks.shared.removeChatInteractively(context, self.chatInteraction.peerId, self.chatInteraction.peer?.id) |> filter { $0 } |> mapToSignal { _ -> Signal<ChatLocation?, NoError> in
                            return context.globalPeerHandler.get() |> take(1)
                        } |> deliverOnMainQueue

                        self.deleteChatDisposable.set(signal.start(next: { [weak self] location in
                            if location == self?.chatInteraction.chatLocation {
                                self?.context.bindings.rootNavigation().close()
                            }
                        }))
                    }

                    let animation: LocalAnimatedSticker
                    let text: String
                    if peer.isGroup {
                        text = strings().chatListContextDeleteAndExit
                        animation = .menu_delete
                    } else if peer.isChannel {
                        text = strings().chatListContextLeaveChannel
                        animation = .menu_leave
                    } else if peer.isSupergroup {
                        text = strings().chatListContextLeaveGroup
                        animation = .menu_leave
                    } else {
                        text = strings().chatListContextDeleteChat
                        animation = .menu_delete
                    }

                    items.append(ContextMenuItem(ChatNavigationHooks.shared.chatExportMenuTitle(), handler: {
                        ChatNavigationHooks.shared.showChatExport(context, mainPeer)
                    }, itemImage: MenuAnimation.menu_file.value))

                    if !items.isEmpty {
                        items.append(ContextSeparatorItem())
                    }

                    if peer.canManageDestructTimer && context.peerId != peer.id, !isServicePeer(peer) && !peer.isSecretChat, chatInteraction.presentation.sendPaidMessageStars == nil {

                        let best: (Int32) -> MenuAnimation = { value in
                            if value == Int32.secondsInDay {
                                return MenuAnimation.menu_autodelete_1d
                            }
                            if value == Int32.secondsInWeek {
                                return MenuAnimation.menu_autodelete_1w
                            }
                            if value == Int32.secondsInMonth {
                                return MenuAnimation.menu_autodelete_1m
                            }
                            if value == 0 {
                                return MenuAnimation.menu_autodelete_never
                            }
                            return MenuAnimation.menu_autodelete_customize
                        }

                        var selected: Int32 = 0
                        var values: [Int32] = [0, .secondsInDay, .secondsInWeek, .secondsInMonth]

                        if let timeout = chatInteraction.presentation.messageSecretTimeout?.timeout {
                            if !values.contains(timeout.effectiveValue) {
                                values.append(timeout.effectiveValue)
                            }
                            selected = timeout.effectiveValue
                        }
                        let item = ContextMenuItem(strings().chatContextAutoDelete, handler: {
                            clearHistory(context: context, peer: peer, mainPeer: mainPeer, canDeleteForAll: canDeleteForAll)
                        }, itemImage: selected == 0 ? MenuAnimation.menu_secret_chat.value : best(selected).value)

                        let submenu = ContextMenu()

                        let updateTimer: (Int32) -> Void = { value in
                            _ = showModalProgress(signal: context.engine.peers.setChatMessageAutoremoveTimeoutInteractively(peerId: peerId, timeout: value == 0 ? nil : value), for: context.window).start()
                        }

                        for value in values {
                            if value == 0 {
                                submenu.addItem(ContextMenuItem(strings().autoremoveMessagesNever, handler: {
                                    updateTimer(value)
                                }, state: selected == value ? .on : nil, itemImage: best(value).value))
                            } else {
                                submenu.addItem(ContextMenuItem(autoremoveLocalized(Int(value)), handler: {
                                    updateTimer(value)
                                }, state: selected == value ? .on : nil, itemImage: best(value).value))
                            }
                        }

                        item.submenu = submenu
                        items.append(item)
                    }
                    if peer.canClearHistory || (peer.canManageDestructTimer && context.peerId != peer.id) {
                        items.append(ContextMenuItem(strings().chatContextClearHistory, handler: {
                            clearHistory(context: context, peer: peer, mainPeer: mainPeer, canDeleteForAll: canDeleteForAll)
                        }, itemImage: MenuAnimation.menu_clear_history.value))
                    }


                    items.append(ContextMenuItem(text, handler: deleteChat, itemMode: .destruct, itemImage: animation.value))

                }
            case .thread:
                break
            }
        case .pinned:
            items.append(ContextMenuItem(strings().chatContextEdit1, handler: { [weak self] in
                self?.changeState()
            }, itemImage: MenuAnimation.menu_edit.value))
        case .thread:
            items.append(ContextMenuItem(strings().chatContextEdit1, handler: { [weak self] in
                self?.changeState()
            }, itemImage: MenuAnimation.menu_edit.value))
            let threadId = self.chatLocation.threadId
            if let threadId = threadId, let threadData = chatInteraction.presentation.threadInfo, let peer = chatInteraction.peer {
                if threadData.isOwnedByMe || peer.isAdmin {
                    if !mode.isSavedMessagesThread {
                        items.append(ContextMenuItem(!threadData.isClosed ? strings().chatListContextPause : strings().chatListContextStart, handler: {
                            _ = context.engine.peers.setForumChannelTopicClosed(id: peerId, threadId: threadId, isClosed: !threadData.isClosed).start()
                        }, itemImage: !threadData.isClosed ? MenuAnimation.menu_pause.value : MenuAnimation.menu_play.value))

                        items.append(ContextSeparatorItem())
                    }
                    if threadId != 1 {
                        items.append(ContextMenuItem(strings().chatListContextDelete, handler: {
                            _ = ChatUIHooks.shared.removeThreadInteractively(context, peerId, threadId, nil).start()
                        }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
                    }
                }
            }
        case .customChatContents:
            items.append(ContextMenuItem(strings().chatContextEdit1, handler: { [weak self] in
                self?.changeState()
            }, itemImage: MenuAnimation.menu_edit.value))
        case let .customLink(contents):
            items.append(ContextMenuItem(strings().chatContextBusinessLinkEditName, handler: {
                contents.editName?()
            }, itemImage: MenuAnimation.menu_edit.value))
        case .preview:
            break
        }

        if let translation = chatTranslationMenuItem(chatInteraction: chatInteraction) {
            if !items.isEmpty {
                items.insert(ContextSeparatorItem(), at: 0)
            }
            items.insert(translation, at: 0)
        }

        guard !items.isEmpty else {
            return nil
        }

        for item in items {
            menu.addItem(item)
        }
        return menu
    }

    fileprivate var headerPhotoAccessibilityActionName: String? {
        if genericView.bubblesView.hasStories {
            return strings().voiceOverCommonStories
        }
        if chatInteraction.mode == .history, chatInteraction.peerId != chatInteraction.interactionContext.peerId, chatInteraction.presentation.mainPeer?.largeProfileImage != nil {
            return strings().voiceOverCommonProfilePhoto
        }
        return nil
    }

    fileprivate func openPhotoFromHeader() {
        let bubbles = genericView.bubblesView
        if bubbles.hasStories {
            chatInteraction.openStories({ [weak self] peerId, _, _ in
                if self?.chatInteraction.peerId == peerId {
                    return self?.genericView.bubblesView.avatarStoryControl
                } else {
                    return nil
                }
            }, { [weak self] signal in
                guard let self = self else { return }
                SetOpenStoryDisposable(self.genericView.bubblesView.avatarStoryControl.pushLoadingStatus(signal: signal))
            })
        } else {
            if chatInteraction.mode == .history, chatInteraction.peerId != chatInteraction.interactionContext.peerId {
                if let peer = chatInteraction.presentation.mainPeer, let large = peer.largeProfileImage {
                    showPhotosGallery(context: chatInteraction.interactionContext, peerId: peer.id, firstStableId: AnyHashable(large.resource.id.stringRepresentation), bubbles, nil)
                    return
                }
            }
        }
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }

    fileprivate func updateBubblesBackButton() {
        guard isLoaded() else { return }
        guard let nav = navigationController else {
            genericView.bubblesView.hasBackButton = false
            genericView.bubblesView.isCloseButton = false
            return
        }
        let prev = nav.previousController
        let previousIsEmpty = prev?.isKind(of: ChatHistoryUIHooks.shared.emptyChatControllerType()) ?? false
        let stackHas = nav.stackCount > 1 && !previousIsEmpty
        let isClose = mode == .preview && nav.stackCount <= 1
        genericView.bubblesView.hasBackButton = stackHas || isClose
        genericView.bubblesView.isCloseButton = isClose
    }

    fileprivate func openPeerInfoFromHeader() {
        let chatInteraction = self.chatInteraction
        if chatInteraction.mode == .history {
            if chatInteraction.presentation.reportMode != nil {

            } else if chatInteraction.peerId == repliesPeerId {

            } else if chatInteraction.peerId == chatInteraction.interactionContext.peerId {
                chatInteraction.interactionContext.bindings.rootNavigation().push(ChatUIHooks.shared.makePeerMediaControllerObserved(chatInteraction.interactionContext, chatInteraction.peerId, isBot: false))
            } else {
                switch chatInteraction.chatLocation {
                case let .peer(peerId):
                    chatInteraction.openInfoObserved(peerId, false, nil, nil)
                case let .thread(data):
                    if data.isMonoforumPost {
                        chatInteraction.openInfoObserved(PeerId(data.threadId), false, nil, nil)
                    } else {
                        chatInteraction.openInfoObserved(data.peerId, false, nil, nil)
                    }
                }
            }
        } else if chatInteraction.mode == .preview {
            let peerId = chatInteraction.peerId
            var threadInfo: ThreadInfo?
            if case let .thread(data) = chatInteraction.chatLocation, data.threadId != Message.newTopicThreadId {
                threadInfo = ThreadInfo(message: data, isChannelPost: false, isMonoforumPost: data.isMonoforumPost, isEmpty: false, contextHolder: chatLocationContextHolder)
            }
            navigationController?.modal?.close()
            ChatUIHooks.shared.pushPeerInfoObserved(context.bindings.rootNavigation(), context, peerId, threadInfo, nil, nil, nil)
        } else if chatInteraction.presentation.isTopicMode {
            chatInteraction.openInfoObserved(chatInteraction.peerId, false, nil, nil)
        } else if chatInteraction.mode.isSavedMessagesThread, let threadId = chatInteraction.chatLocation.threadId {
            chatInteraction.openInfoObserved(PeerId(threadId), false, nil, nil)
        }
    }

    

    private func createGroup() {
        ChatUIHooks.shared.createGroupDirectly(context, [self.chatLocation.peerId])
    }
    
    
    private func makeVoiceChat(_ current: CachedChannelData.ActiveCall?, callJoinPeerId: PeerId?) {
        let context = self.context
        let peerId = self.chatLocation.peerId
        if let activeCall = current {
            let join:(PeerId, Date?, Bool)->Void = { joinAs, _, _ in
                _ = ChatUIHooks.shared.requestOrJoinGroupCall(context, peerId, joinAs, activeCall, nil, nil, nil).start(next: { result in
                    switch result {
                    case let .samePeer(callContext), let .success(callContext):
                        ChatNavigationHooks.shared.applyGroupCallResult(context.sharedContext, callContext)
                    default:
                        alert(for: context.window, info: strings().errorAnError)
                    }
                })
            }
            
            if let callJoinPeerId = callJoinPeerId {
                join(callJoinPeerId, nil, false)
            } else {
                ChatNavigationHooks.shared.selectGroupCallJoiner(context, peerId, join)
            }
        } else {
            ChatUIHooks.shared.createVoiceChatCanBeScheduled(context, peerId, true)
        }
    }

    
//    override func invokeNavigationBack() -> Bool {
//        return !context.closeFolderFirst
//    }
    
    public override func escapeKeyAction() -> KeyHandlerResult {
        
//
//        if context.closeFolderFirst {
//            return .rejected
//        }
        
        if genericView.inputView.textView.inputView.hasMarkedText() {
            return .invokeNext
        }
        
        if chatInteraction.presentation.interfaceState.themeEditing {
            self.themeSelector?.close(true)
            return .invoked
        }
        
        var result:KeyHandlerResult = .rejected
        if chatInteraction.presentation.botMenu?.revealed == true {
            self.chatInteraction.update({
                $0.updateBotMenu({ current in
                    var current = current
                    current?.revealed = false
                    return current
                })
            })
            result = .invoked
        } else if chatInteraction.presentation.reportMode != nil {
            self.changeState()
            result = .invoked
        } else if chatInteraction.presentation.state == .selecting {
            self.changeState()
            result = .invoked
        } else if chatInteraction.presentation.state == .editing {
            chatInteraction.cancelEditing()
            result = .invoked
        } else if case let .contextRequest(_, request) = chatInteraction.presentation.inputContext {
            if request.isEmpty {
                chatInteraction.clearInput()
            } else {
                chatInteraction.clearContextQuery()
            }
            result = .invoked
        } else if chatInteraction.presentation.searchMode.inSearch {
            chatInteraction.update({$0.updatedSearchMode(.init(inSearch: false))})
            result = .invoked
        } else if let recordingState = chatInteraction.presentation.recordingState {
            recordingState.discard(from: chatInteraction)
            return .invoked
        } else if chatInteraction.presentation.interfaceState.replyMessageId != nil {
            if chatInteraction.presentation.interfaceState.inputState.inputText.isEmpty {
                chatInteraction.update({$0.updatedInterfaceState({$0.withUpdatedReplyMessageId(nil)})})
                return .invoked
            }
        }
        
        return result
    }
    
    public override func invokeNavigationBack() -> Bool {
        let presentation = self.chatInteraction.presentation
        let context = self.context
        
        if presentation.recordingState != nil {
            return false
        }
        
        switch mode {
        case .customLink(let contents):
            let current = presentation.effectiveInput
            if contents.text.attributes != current.attributes || contents.text.inputText != current.inputText {
                verifyAlert(for: context.window, information: strings().chatAlertUnsaved, ok: strings().chatAlertUnsavedReset, successHandler: { [weak self] _ in
                    self?.navigationController?.invokeBack(checkLock: false)
                })
                return false
            }
        case let .customChatContents(contents):
            if presentation.historyCount == 0 {
                let title: String
                let info: String
                switch contents.kind {
                case .greetingMessageInput:
                    title = strings().quickReplyChatRemoveGreetingMessageTitle
                    info = strings().quickReplyChatRemoveGreetingMessageTitle
                case .awayMessageInput:
                    title = strings().quickReplyChatRemoveAwayMessageTitle
                    info = strings().quickReplyChatRemoveAwayMessageText
                case .quickReplyMessageInput:
                    title = strings().quickReplyChatRemoveGenericTitle
                    info = strings().quickReplyChatRemoveGenericText
                case .welcomeMessages:
                    return true
                case .searchHashtag:
                    return true
                }
                verifyAlert(for: context.window, header: title, information: info, ok: strings().quickReplyChatRemoveGenericDeleteAction, successHandler: { [weak self] _ in
                    self?.navigationController?.invokeBack(checkLock: false)
                })
                return false
            }
        default:
            break
        }
        return true
    }
    
    private var isConfirmingDiscardRecording: Bool = false

    public func confirmDiscardRecordingIfNeeded(confirmed: @escaping () -> Void) -> Bool {
        guard chatInteraction.presentation.recordingState != nil else {
            return true
        }
        guard !isConfirmingDiscardRecording else {
            return false
        }
        isConfirmingDiscardRecording = true
        verifyAlert_button(for: context.window, information: strings().chatRecordingCancel, ok: strings().alertDiscard, cancel: strings().alertNO, successHandler: { [weak self] _ in
            self?.isConfirmingDiscardRecording = false
            guard let self, let recordingState = self.chatInteraction.presentation.recordingState else {
                return
            }
            recordingState.discard(from: self.chatInteraction, closingOtherModals: true)
            confirmed()
        }, cancelHandler: { [weak self] in
            self?.isConfirmingDiscardRecording = false
        }, onDeinit: { [weak self] in
            self?.isConfirmingDiscardRecording = false
        })
        return false
    }

    public override func backKeyAction() -> KeyHandlerResult {
        
        if let window = window, hasModals(window) {
            return .invokeNext
        }
        if let event = NSApp.currentEvent, event.modifierFlags.contains(.shift), window?.firstResponder === selectManager {
            if !selectManager.isEmpty {
                let result = selectManager.selectPrevChar()
                if result {
                    return .invoked
                }
            }
        }
        
        return !self.chatInteraction.presentation.searchMode.inSearch && self.chatInteraction.presentation.effectiveInput.inputText.isEmpty ? .rejected : .invokeNext
    }
    
    public override func returnKeyAction() -> KeyHandlerResult {
        if let recordingState = chatInteraction.presentation.recordingState {
            recordingState.send(from: chatInteraction, closingOtherModals: true)
            return .invoked
        }
        return super.returnKeyAction()
    }
    
    public override func nextKeyAction() -> KeyHandlerResult {
        
        if let window = window, hasModals(window) {
            return .invokeNext
        }
        
        if let event = NSApp.currentEvent, event.modifierFlags.contains(.shift), window?.firstResponder === selectManager {
            if !selectManager.isEmpty {
                let result = selectManager.selectNextChar()
                if result {
                    return .invoked
                }
            }
        }
        
        if !self.chatInteraction.presentation.searchMode.inSearch && chatInteraction.presentation.effectiveInput.inputText.isEmpty {
            chatInteraction.openInfo(chatInteraction.peerId, false, nil, nil)
            return .invoked
        }
        return .rejected
    }
    
    
    private var didCleanup: Bool = false

    private func cleanup() {
        if didCleanup {
            return
        }
        didCleanup = true
        chatInteraction.invalidateDeferredSendActions()

        heavyScrollWorkItem?.cancel()
        heavyScrollWorkItem = nil
        readMetricsManager?.finalizeAll()
        failedMessageEventsDisposable.dispose()
        historyDisposable.dispose()
        peerDisposable.dispose()
        updatedChannelParticipants.dispose()
        readHistoryDisposable.dispose()
        messageActionCallbackDisposable.dispose()
        sentMessageEventsDisposable.dispose()
        proccessingMessageEventsDisposable.dispose()
        chatInteraction.remove(observer: self)
        contextQueryState?.1.dispose()
        self.urlPreviewQueryState?.1.dispose()
        botCallbackAlertMessageDisposable?.dispose()
        layoutDisposable.dispose()
        shareContactDisposable.dispose()
        peerInputActivitiesDisposable.dispose()
        connectionStatusDisposable.dispose()
        messagesActionDisposable.dispose()
        unblockDisposable.dispose()
        updatePinnedDisposable.dispose()
        tonAddressMenuDisposable.dispose()
        reportPeerDisposable.dispose()
        focusMessageDisposable.dispose()
        updateFontSizeDisposable.dispose()
        context.addRecentlyUsedPeer(peerId: chatInteraction.peerId)
        loadFwdMessagesDisposable.dispose()
        chatUnreadMentionCountDisposable.dispose()
        navigationActionDisposable.dispose()
        messageIndexDisposable.dispose()
        dateDisposable.dispose()
        interactiveReadingDisposable.dispose()
        interactiveReadReactionsDisposable.dispose()
        interactiveReadStateDisposable.dispose()
        replyMessageDisposable.dispose()
        deleteChatDisposable.dispose()
        loadSelectionMessagesDisposable.dispose()
        updateMediaDisposable.dispose()
        editCurrentMessagePhotoDisposable.dispose()
        selectMessagePollOptionDisposables.dispose()
        monoforumTopicsDisposable.dispose()
        chatInteraction.presentation.recordingState?.cancel()
        discussionDataLoadDisposable.dispose()
        slowModeDisposable.dispose()
        slowModeInProgressDisposable.dispose()
        forwardMessagesDisposable.dispose()
        shiftSelectedDisposable.dispose()
        hasScheduledMessagesDisposable.dispose()
        updateUrlDisposable.dispose()
        pollChannelDiscussionDisposable.dispose()
        loadThreadDisposable.dispose()
        updateChatLocationThreadDisposable.dispose()
        recordActivityDisposable.dispose()
        suggestionsDisposable.dispose()
        tempImportersContextDisposable.dispose()
        sendAsPeersDisposable.dispose()
        peekDisposable.dispose()
        transcribeDisposable.dispose()
        startSecretChatDisposable.dispose()
        inputSwapDisposable.dispose()
        keepMessageCountersSyncrhonizedDisposable?.dispose()
        liveTranslateDisposable.dispose()
        presentationDisposable.dispose()
        storiesDisposable.dispose()
        keepSavedMessagesSyncrhonizedDisposable?.dispose()
        keepShortcutDisposable.dispose()
        networkSpeedEventsDisposable?.dispose()
        titleUpdateDisposable.dispose()
        preloadPersonalChannel.dispose()
        codeSyntaxHighlightDisposables.dispose()
        premiumOrStarsRequiredDisposable.dispose()
        newTopicEventsDisposable.dispose()
        _ = previousView.swap(nil)
        // Release the held Appearance immediately. The big history-transition
        // combineLatest closure captures this Atomic; even after disposing
        // `historyDisposable`, the closure can briefly outlive cleanup() on
        // its dispatch queue and would otherwise keep the Appearance alive.
        _ = previousAppearance.swap(nil)

        removeCaptureExclusion()
        context.closeFolderFirst = false
    }

    public override func readyToDetach() {
        chatInteraction.invalidateDeferredSendActions()
        super.readyToDetach()
    }

    deinit {
        cleanup()
    }


    public override func viewWillDisappear(_ animated: Bool) {
        chatInteraction.invalidateDeferredSendActions()
        super.viewWillDisappear(animated)
        self.cancelMessageFocus()
        chatInteraction.dateHeaderActions.reset()
        chatInteraction.voiceTranscription?.dismiss(animated: false)

        // Note: do NOT clear the global background here. The window-level
        // background is driven by `globalPeerHandler` in AuthorizedApplicationContext;
        // we leave it alone so that pushing PeerInfo (or any other controller) on
        // top of the chat keeps the chat's wallpaper visible behind it.
        isPushedGlobalBackground = false

        readMetricsManager?.pause()
        setVisibleRefreshActive(false)

        self.emojiEffects.removeAll()

        suggestionsDisposable.set(nil)

        sentMessageEventsDisposable.set(nil)
        proccessingMessageEventsDisposable.set(nil)
        peekDisposable.set(nil)
        
        genericView.inputContextHelper.viewWillRemove()
        chatInteraction.saveState(scrollState: immediateScrollState())
        
        context.window.removeAllHandlers(for: self)
        
        if let window = window {
            selectTextController.removeHandlers(for: window)
        }
        self.visibility.set(false)
        
        context.reactions.sentStarReactions = nil
        context.reactions.forceSendStarReactions = nil
    }
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        DispatchQueue.main.async { [weak self] in
            self?.removeCaptureExclusion()
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

    public override func didRemovedFromStack() {
        super.didRemovedFromStack()
        chatInteraction.remove(observer: self)
    }
    
    
    

    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        isPushedGlobalBackground = true
        updateBubblesBackButton()
        

        if let initialAction = self.chatInteraction.presentation.initialAction {
            switch initialAction {
            case let .closeAfter(peek):
                 self.chatInteraction.closeAfterPeek(peek)
            default:
                break
            }
        }
        

        let context = self.context
        context.closeFolderFirst = false

        ChatUIHooks.shared.updateEntertainment(self.context, self.chatInteraction)
        chatInteraction.update(animated: false, { $0.withToggledSidebarEnabled(FastSettings.sidebarEnabled).withToggledSidebarShown(FastSettings.sidebarShown) })
        ChatInputUIHooks.shared.updateEntertainmentSidebar(false)
        
        self.failedMessageEventsDisposable.set((context.account.pendingMessageManager.failedMessageEvents(peerId: chatInteraction.peerId, isScheduled: self.mode == .scheduled)
         |> deliverOnMainQueue).start(next: { [weak self] reason in
            if let strongSelf = self {
                let text: String
                switch reason {
                case .flood:
                    text = strings().chatSendMessageErrorFlood
                case .publicBan:
                    text = strings().chatSendMessageErrorGroupRestricted
                case .mediaRestricted:
                    text = strings().chatSendMessageErrorGroupRestricted
                case .slowmodeActive:
                    text = strings().chatSendMessageSlowmodeError
                case .tooMuchScheduled:
                    text = strings().chatSendMessageErrorTooMuchScheduled
                case .voiceMessagesForbidden:
                    let peer = strongSelf.chatInteraction.presentation.mainPeer
                    text = strings().chatSendVoicePrivacyError(peer?.compactDisplayTitle ?? "")
                case .sendingTooFast:
                    text = strings().chatSendMessageErrorTooFast
                case .nonPremiumMessagesForbidden:
                    let peer = strongSelf.chatInteraction.presentation.mainPeer
                    text = strings().chatSendMessageErrorNonPremiumForbidden(peer?.compactDisplayTitle ?? "")
                }
                verifyAlert_button(for: context.window, information: text, cancel: "", option: strings().genericErrorMoreInfo, successHandler: { [weak strongSelf] confirm in
                    guard let strongSelf = strongSelf else {return}
                    
                    switch confirm {
                    case .thrid:
                        ChatUIHooks.shared.openSpamBot(context, { [weak strongSelf] peerId, openChat, postid, initialAction in
                            strongSelf?.chatInteraction.openInfo(peerId, openChat, postid, initialAction)
                        })
                    default:
                        break
                    }
                })
            }
         }))
 
        
        if let peer = chatInteraction.peer {
            if peer.isRestrictedChannel(context.contentSettings), let reason = peer.restrictionText(context.contentSettings) {
                alert(for: context.window, info: reason, completion: { }, onDeinit: { [weak self] in
                    self?.dismiss()
                })
            }
        }
        
       
        
        self.context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            if let strongSelf = self, let window = strongSelf.window, !hasModals(window) {
                let result:KeyHandlerResult = strongSelf.chatInteraction.presentation.effectiveInput.inputText.isEmpty && strongSelf.chatInteraction.presentation.state == .normal ? .invoked : .rejected

                if result == .invoked {
                    let setup = strongSelf.findAndSetEditableMessage()
                    if !setup {
                        strongSelf.genericView.tableView.scrollUp()
                        return .invoked
                    }
                } else {
                    if strongSelf.chatInteraction.presentation.effectiveInput.inputText.isEmpty {
                        strongSelf.genericView.tableView.scrollUp()
                        return .invoked
                    }
                }

                return result
            }
            return .rejected
        }, with: self, for: .UpArrow, priority: .low)


        
        
        self.context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            if let strongSelf = self, let window = strongSelf.window, !hasModals(window) {
                let result:KeyHandlerResult = strongSelf.chatInteraction.presentation.effectiveInput.inputText.isEmpty ? .invoked : .invokeNext
                
                
                if result == .invoked {
                    strongSelf.genericView.tableView.scrollDown()
                }
                
                return result
            }
            return .rejected
        }, with: self, for: .DownArrow, priority: .low)
        
        self.context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            if let `self` = self, let window = self.window, !hasModals(window), self.chatInteraction.presentation.interfaceState.editState == nil, self.chatInteraction.presentation.interfaceState.inputState.inputText.isEmpty {
                var currentReplyId = self.chatInteraction.presentation.interfaceState.replyMessage
                self.genericView.tableView.enumerateItems(with: { item in
                    if let item = item as? ChatRowItem, let message = item.message {
                        if canReplyMessage(message, peerId: self.chatInteraction.peerId, chatLocation: self.chatLocation, mode: self.chatInteraction.mode), currentReplyId == nil || (message.id < currentReplyId!.id) {
                            currentReplyId = message
                            self.genericView.tableView.scroll(to: .center(id: item.stableId, innerId: nil, animated: true, focus: .init(focus: true), inset: 0), inset: NSEdgeInsetsZero, timingFunction: .linear)
                            return false
                        }
                    }
                    return true
                })
                
                let result:KeyHandlerResult = currentReplyId != nil ? .invoked : .rejected
                let subject: EngineMessageReplySubject?
                if let currentReplyId = currentReplyId {
                    subject = .init(messageId: currentReplyId.id, quote: nil, innerSubject: nil)
                } else {
                    subject = nil
                }
                self.chatInteraction.setupReplyMessage(currentReplyId, subject)
                
                return result
            }
            return .rejected
        }, with: self, for: .UpArrow, priority: .low, modifierFlags: [.command])
        
        self.context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            if let `self` = self, let window = self.window, !hasModals(window), self.chatInteraction.presentation.interfaceState.editState == nil, self.chatInteraction.presentation.interfaceState.inputState.inputText.isEmpty {
                var currentReplyId = self.chatInteraction.presentation.interfaceState.replyMessage
                self.genericView.tableView.enumerateItems(reversed: true, with: { item in
                    if let item = item as? ChatRowItem, let message = item.message {
                        if canReplyMessage(message, peerId: self.chatInteraction.peerId, chatLocation: self.chatLocation, mode: self.chatInteraction.mode), currentReplyId != nil && (message.id > currentReplyId!.id) {
                            currentReplyId = message
                            self.genericView.tableView.scroll(to: .center(id: item.stableId, innerId: nil, animated: true, focus: .init(focus: true), inset: 0), inset: NSEdgeInsetsZero, timingFunction: .linear)
                            return false
                        }
                    }
                    return true
                })
                
                let result:KeyHandlerResult = currentReplyId != nil ? .invoked : .rejected
                let subject: EngineMessageReplySubject?
                if let currentReplyId = currentReplyId {
                    subject = .init(messageId: currentReplyId.id, quote: nil, innerSubject: nil)
                } else {
                    subject = nil
                }
                self.chatInteraction.setupReplyMessage(currentReplyId, subject)
                
                return result
            }
            return .rejected
        }, with: self, for: .DownArrow, priority: .low, modifierFlags: [.command])
        
        
        self.context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            guard let `self` = self, let window = self.window, !hasModals(window) else {return .rejected}
            
            if let selectionState = self.chatInteraction.presentation.selectionState, !selectionState.selectedIds.isEmpty {
                self.chatInteraction.deleteSelectedMessages()
                return .invoked
            }
            
            return .rejected
        }, with: self, for: .Delete, priority: .low)
        
        self.context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            guard let `self` = self else {return .rejected}
            
            if let selectionState = self.chatInteraction.presentation.selectionState, !selectionState.selectedIds.isEmpty {
                self.chatInteraction.deleteSelectedMessages()
                return .invoked
            }
            
            return .rejected
        }, with: self, for: .ForwardDelete, priority: .low)
        
        

        
        self.context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            guard let strongSelf = self else {
                return .rejected
            }
            if hasModals() {
                return .rejected
            }
            let inputView = strongSelf.genericView.inputView.textView.inputView
            if strongSelf.context.window.firstResponder != inputView {
                _ = strongSelf.context.window.makeFirstResponder(inputView)
                return .invoked
            }
            return .rejected
        }, with: self, for: .Tab, priority: .high)
        
      
        
        self.context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            guard let `self` = self, self.mode != .scheduled, self.searchAvailable else {return .rejected}
            if !self.chatInteraction.presentation.searchMode.inSearch {
                self.chatInteraction.update({$0.updatedSearchMode(.init(inSearch: true))})
            } else {
                self.genericView.applySearchResponder()
            }
            return .invoked
        }, with: self, for: .F, priority: .medium, modifierFlags: [.command])
        
        
        self.context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.chatInteraction.attachFile(true)
            return .invoked
        }, with: self, for: .O, priority: .medium, modifierFlags: [.command])
      
        self.context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.inputView.makeBold()
            return .invoked
        }, with: self, for: .B, priority: .medium, modifierFlags: [.command])
        
        self.context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.inputView.makeUnderline()
            return .invoked
        }, with: self, for: .U, priority: .high, modifierFlags: [.shift, .command])
        
        self.context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.inputView.makeQuote()
            return .invoked
        }, with: self, for: .I, priority: .high, modifierFlags: [.shift, .command])
        
        self.context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.inputView.makeSpoiler()
            return .invoked
        }, with: self, for: .P, priority: .medium, modifierFlags: [.shift, .command])
        
        self.context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.inputView.makeStrikethrough()
            return .invoked
        }, with: self, for: .X, priority: .medium, modifierFlags: [.shift, .command])
        
        self.context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.inputView.removeAllAttributes()
            return .invoked
        }, with: self, for: .Backslash, priority: .medium, modifierFlags: [.command])
        
        self.context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.inputView.makeUrl()
            return .invoked
        }, with: self, for: .U, priority: .medium, modifierFlags: [.command])
        
        self.context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.inputView.makeItalic()
            return .invoked
        }, with: self, for: .I, priority: .medium, modifierFlags: [.command])
                
        self.context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            guard let `self` = self else { return .rejected }
            self.chatInteraction.startRecording(true, nil)
            return .invoked
        }, with: self, for: .R, priority: .medium, modifierFlags: [.command])
        
        
        self.context.window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.genericView.inputView.makeMonospace()
            return .invoked
        }, with: self, for: .K, priority: .medium, modifierFlags: [.command, .shift])

        self.context.window.set(mouseHandler: { [weak self] _ in
            self?.readMetricsManager?.recordUserActivity()
            return .rejected
        }, with: self, for: .mouseMoved, priority: .low)

        self.context.window.add(swipe: { [weak self] direction, _ -> SwipeHandlerResult in
            guard let `self` = self, let window = self.window, self.chatInteraction.presentation.canReplyInRestrictedMode else {return .failed}
            let swipeState: SwipeState?
            switch direction {
            case .left:
               return .failed
            case let .right(_state):
                swipeState = _state
            case .none:
                swipeState = nil
            }
            
            guard let state = swipeState else {return .failed}
            

            
            switch state {
            case .start:
                let mouseInWindow = window.mouseLocationOutsideOfEventStream
                if let hit = window.contentView?.hitTest(window.contentView!.convert(mouseInWindow, from: nil)),
                   hit.enclosingHorizontalScrollConsumer(atWindowPoint: mouseInWindow) != nil {
                    return .failed
                }
                let row = self.genericView.tableView.row(at: self.genericView.tableView.clipView.convert(mouseInWindow, from: nil))
                if row != -1 {
                    guard let item = self.genericView.tableView.item(at: row) as? ChatRowItem else {
                        return .failed
                    }
                    if let item = item as? ChatServiceItem, item.walletTransferData == nil {
                        return .failed
                    }
                    if !item.isSharable {
                        if let message = item.message, !canReplyMessage(message, peerId: self.chatInteraction.peerId, chatLocation: self.chatInteraction.chatLocation, mode: self.chatInteraction.mode) {
                            return .failed
                        }
                    }
                    (item.view as? RevealTableView)?.initRevealState()
                    return .success(RevealTableItemController(item: item))
                } else {
                    return .failed
                }
                
            case let .swiping(_delta, controller):
                let controller = controller as! RevealTableItemController
                
                guard let view = controller.item.view as? RevealTableView else {return .nothing}
                
                var delta:CGFloat
                switch direction {
                case .left:
                    delta = _delta//max(0, _delta)
                case .right:
                    delta = -_delta//min(-_delta, 0)
                default:
                    delta = _delta
                }
                
                let newDelta = min(min(300, view.width) * log2(abs(delta) + 1) * log2(min(300, view.width)) / 100.0, abs(delta))
                
                if delta < 0 {
                    delta = -newDelta
                } else {
                    delta = newDelta
                }

                
                view.moveReveal(delta: delta)
                self.updateFloatingPhotos(self.genericView.scroll, animated: false)
//                self.reactionManager?.clearAndTempLock()
//                self.reactionManager?.update()
            case let .success(_, controller), let .failed(_, controller):
                let controller = controller as! RevealTableItemController
                guard let view = (controller.item.view as? RevealTableView) else { return .nothing }
                
                view.completeReveal(direction: direction)
                self.updateFloatingPhotos(self.genericView.scroll, animated: true)

             //   self.reactionManager?.update(transition: .animated(duration: 0.2, curve: .easeOut))

            }
            
            
            //  return .success()
            
            return .nothing
        }, with: self.genericView.tableView, identifier: "chat-reply-swipe")
        
                
        let peerId = self.chatLocation.peerId
        
      
        
        if !(context.window.firstResponder is NSTextView) {
            self.genericView.inputView.makeFirstResponder()
        }

        if let window = window {
            selectTextController.initializeHandlers(for: window, chatInteraction:chatInteraction)
        }
       // if !context.isInGlobalSearch {
            _ = context.window.makeFirstResponder(genericView.inputView.textView.inputView)
       // }
    
        
        var beginPendingTime:CFAbsoluteTime?
        
       self.sentMessageEventsDisposable.set((context.account.pendingMessageManager.deliveredMessageEvents(peerId: self.chatLocation.peerId) |> deliverOn(Queue.concurrentDefaultQueue())).start(next: { pending in
           
           for result in pending {
               if FastSettings.inAppSounds, !result.isSilent, !result.isPendingProcessing {
                   if let beginPendingTime = beginPendingTime {
                       if CFAbsoluteTimeGetCurrent() - beginPendingTime < 0.5 {
                           return
                       }
                   }
                   beginPendingTime = CFAbsoluteTimeGetCurrent()
                   playSoundEffect(.sent)
               }
               
           }
          
       }))
        
        let proccessingEvents = context.account.pendingMessageManager.deliveredMessageEvents(peerId: self.chatLocation.peerId)
        |> deliverOnMainQueue
        |> map { $0.filter(\.isPendingProcessing) }
        
        let chatLocation = self.chatLocation
        
        
        proccessingMessageEventsDisposable.set(proccessingEvents.start(next: { [weak self] proccessing in
            if let first = proccessing.first {
                self?.navigationController?.push(ChatScheduleController(context: context, chatLocation: chatLocation, focusTarget: .init(messageId: first.id)))
            }
        }))
         

        
        let suggestions = context.engine.notices.getPeerSpecificServerProvidedSuggestions(peerId: self.chatLocation.peerId) |> deliverOnMainQueue

        suggestionsDisposable.set(suggestions.start(next: { suggestions in
            for suggestion in suggestions {
                switch suggestion {
                case .convertToGigagroup:
                    verifyAlert_button(for: context.window, header: strings().broadcastGroupsLimitAlertTitle, information: strings().broadcastGroupsLimitAlertText(Formatter.withSeparator.string(from: NSNumber(value: context.limitConfiguration.maxSupergroupMemberCount))!), ok: strings().broadcastGroupsLimitAlertLearnMore, successHandler: { _ in
                        ChatNavigationHooks.shared.showGigagroupLanding(context, peerId, context.window)
                    }, cancelHandler: {
                        showModalText(for: context.window, text: strings().broadcastGroupsLimitAlertSettingsTip)
                    })
                    _ = context.engine.notices.dismissPeerSpecificServerProvidedSuggestion(peerId: peerId, suggestion: suggestion).startStandalone()
                }
            }
        }))

        
    }
    
    
    func findAndSetEditableMessage() -> Bool {
        if self.previousView.with({ $0?.originalView?.laterId == nil }) {
            
            var edited: Bool = false
            genericView.tableView.enumerateVisibleItems(with: { item in
                guard let item = item as? ChatRowItem else {
                    return true
                }
                if item.messages.count > 1 {
                    var effectiveMessage: Message?
                    for message in item.messages {
                        if !message.text.isEmpty {
                            effectiveMessage = message
                            break
                        }
                    }
                    effectiveMessage = effectiveMessage ?? item.messages.first
                    
                    if let message = effectiveMessage {
                        if canEditMessage(message, chatInteraction: chatInteraction, context: context)  {
                            chatInteraction.beginEditingMessage(message)
                            edited = true
                            return false
                        }
                    }
                } else if let message = item.message {
                    if canEditMessage(message, chatInteraction: chatInteraction, context: context)  {
                        chatInteraction.beginEditingMessage(message)
                        edited = true
                        return false
                    }
                }
                
                
                return true
            })
            return edited
        }
        return false
    }
    
    public override func firstResponder() -> NSResponder? {
        if mode == .preview {
            return self.genericView
        }
        return self.genericView.responder
    }
    
    public override var responderPriority: HandlerPriority {
        return .medium
    }

    public override var wantsContainerGlass: Bool {
        return false
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        

        readMetricsManager?.resume()
        setVisibleRefreshActive(true)

        updateBubblesBackButton()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.applyCaptureExclusionIfNeeded()
            if self.genericView.window === self.context.window, self.navigationController?.controller === self, !hasModals(self.context.window) {
                _ = self.context.window.makeFirstResponder(self.firstResponder())
            }
        }

        let context = self.context
        
        switch self.mode {
        case .history, .thread:
            self.context.globalPeerHandler.set(.single(chatLocation))
        default:
            break
        }

        self.genericView.tableView.notifyScrollHandlers()
//        self.genericView.updateHeader(chatInteraction.presentation, false, false)
        if let controller = ChatUIHooks.shared.getAudioPlayer(context), let header = self.navigationController?.header, header.needShown {
            let object = ChatUIHooks.shared.makeInlineAudioPlayerContextObject(controller, context, genericView.tableView)
            header.view.update(with: object)
        }
        self.visibility.set(true)
        
        context.reactions.sentStarReactions = { [weak self] messageId, count in
            if let self {
                self.genericView.updateStars(context: self.context, count: Int32(count), messageId: messageId)
            }
        }
        context.reactions.forceSendStarReactions = { [weak self] in
            self?.genericView.forceCancelPendingStars()
        }
    }
    
    private func updateMaxVisibleReadIncomingMessageIndex(_ index: MessageIndex) {
        self.maxVisibleIncomingMessageIndex.set(index)
    }
    
    
    public override func invokeNavigation(action:NavigationModalAction) {
        super.invokeNavigation(action: action)
        chatInteraction.applyAction(action: action)
    }
    
    private let isAdChat: Bool
    private let focusTarget: ChatFocusTarget?
    public let mode: ChatMode
    
    private let sizeValue = ValuePromise<NSSize>(ignoreRepeated: true)
    
    public init(context: Context, chatLocation:ChatLocation, mode: ChatMode = .history, focusTarget:ChatFocusTarget? = nil, initialAction: ChatInitialAction? = nil, chatLocationContextHolder: Atomic<ChatLocationContextHolder?>? = nil) {
        self.focusTarget = focusTarget
        self.chatLocationContextHolder = chatLocationContextHolder ?? Atomic<ChatLocationContextHolder?>(value: nil)
        self.mode = mode
        self.chatInteraction = ChatInteraction(chatLocation: chatLocation, context: context, mode: mode)
        if let action = initialAction {
            switch action {
            case .ad:
                isAdChat = true
            default:
                isAdChat = false
            }
        } else {
            isAdChat = false
        }
        
        _ = chatInteraction.bottomInset.swap(ChatHistoryBottomRowItem.bottomInset(showsInput: ChatControllerView.showsInput(in: mode), inputOverlayHeight: 0))
                
        if chatLocation.peerId.namespace == Namespaces.Peer.CloudChannel || chatLocation.peerId.namespace == Namespaces.Peer.CloudUser, mode == .history {
            self.adMessages = .init(context: context, height: sizeValue.get() |> map { $0 .height}, peerId: chatLocation.peerId)
        } else {
            self.adMessages = nil
        }
        
        
       
        var takeTableItem:((MessageId)->ChatRowItem?)? = nil
        
        self.emojiEffects = EmojiScreenEffect(context: chatInteraction.interactionContext, takeTableItem: { msgId in
            return takeTableItem?(msgId)
        })
        super.init(context)

        self.bar = .init(height: 0)
        self.insets = NSEdgeInsets()

        self.chatInteraction.update(animated: false, {$0.updatedInitialAction(initialAction)})

        context.checkFirstRecentlyForDuplicate(peerId: chatInteraction.peerId)
        
        let clientId = nextClientId
        nextClientId += 1

        
        self.messageProcessingManager.process = { messageIds in
            context.account.viewTracker.updateViewCountForMessageIds(messageIds: messageIds.filter({$0.namespace == Namespaces.Message.Cloud}), clientId: clientId)
        }
        self.factCheckProcessingManager.process = { messageIds in
            _ = context.engine.messages.getMessagesFactCheck(messageIds: Array(messageIds)).startStandalone()
        }
        
        self.extendedMediaProcessingManager.process = { messageIds in
            context.account.viewTracker.updatedExtendedMediaForMessageIds(messageIds: messageIds)
        }

        self.unsupportedMessageProcessingManager.process = { [weak self] messageIds in
            let msgIds = messageIds.filter { $0.namespace == Namespaces.Message.Cloud }.map { MessageAndThreadId(messageId: $0, threadId: self?.chatLocation.threadId) }
            context.account.viewTracker.updateUnsupportedMediaForMessageIds(messageIds: Set(msgIds) )
        }
        self.messageMentionProcessingManager.process = { [weak self] messageIds in
            guard let self else { return }
            let messageIds = self.visibleMessageIdsForReading(messageIds)
            if !messageIds.isEmpty {
                context.account.viewTracker.updateMarkMentionsSeenForMessageIds(messageIds: messageIds)
            }
        }
        self.messageReactionsMentionProcessingManager.process = { [weak self] messageIds in
            guard let self else { return }
            let messageIds = self.visibleMessageIdsForReading(messageIds)
            if !messageIds.isEmpty {
                self.playUnseenReactions(messageIds, checkUnseen: true)
                context.account.viewTracker.updateMarkReactionsAndVotesSeenForMessageIds(messageIds: messageIds)
            }
        }
        self.refreshStoriesProcessingManager.process = { [weak self] messageIds in
            self?.context.account.viewTracker.refreshStoriesForMessageIds(messageIds: messageIds)
        }
        self.refreshMediaProcessingManager.process = { [weak self] messageIds in
            self?.context.account.viewTracker.refreshSecretMediaMediaForMessageIds(messageIds: messageIds)
        }
        self.seenLiveLocationProcessingManager.process = { [weak self] messageIds in
            self?.context.account.viewTracker.updateSeenLiveLocationForMessageIds(messageIds: messageIds)
        }


        self.reactionsMessageProcessingManager.process = { messageIds in
            context.account.viewTracker.updateReactionsForMessageIds(messageIds: messageIds.filter({$0.namespace == Namespaces.Message.Cloud}))
        }

        self.readMetricsManager = MessageReadMetricsManager(context: context, peerId: chatInteraction.peerId)

        chatInteraction.contextHolder = { [weak self] in
            return self?.chatLocationContextHolder ?? Atomic(value: nil)
        }
        
        takeTableItem = { [weak self] msgId in
            if self?.isLoaded() == false {
                return nil
            }
            var found: ChatRowItem? = nil
            self?.genericView.tableView.enumerateVisibleItems(with: { item in
                if let item = item as? ChatRowItem, item.message?.id == msgId {
                    found = item
                    return false
                } else {
                    return true
                }
            })
            return found
        }
        
    }
    


    
    
    
    

    public func notify(with value: Any, oldValue: Any, animated:Bool) {
        self.notify(with: value, oldValue: oldValue, animated: animated && self.didSetReady, force: false)
//        DispatchQueue.main.async { [weak self] in
//            if let self {
//                self.updateFloatingPhotos(self.genericView.scroll, animated: animated)
//            }
//        }
    }
    
    private var isPausedGlobalPlayer: Bool = false
    private var tempImportersContext: PeerInvitationImportersContext? = nil
    private let tempImportersContextDisposable = MetaDisposable()
    
    public func notify(with value: Any, oldValue: Any, animated:Bool, force:Bool) {
        if let value = value as? ChatPresentationInterfaceState, let oldValue = oldValue as? ChatPresentationInterfaceState {

            if value.interfaceState.editState?.message.id != oldValue.interfaceState.editState?.message.id {
                self.editingSessionId += 1
                self.editCurrentMessagePhotoDisposable.set(nil)
                self.updateMediaDisposable.set(nil)
                self.chatInteraction.editDisposable.set(nil)
            }
            
            let context = self.context
            let mode = self.chatInteraction.mode
            
            if value.selectionState != oldValue.selectionState {
                loadSelectionMessagesDisposable.set(nil)
                if let selectionState = value.selectionState {
                    let ids = Array(selectionState.selectedIds)
                    let messages: Signal<[Message], NoError>
                    
                    switch mode {
                    case let .customChatContents(contents):
                        messages = contents.messagesAtIds(ids, album: false) |> deliverOnMainQueue
                    default:
                        messages = context.account.postbox.messagesAtIds(ids) |> deliverOnMainQueue
                    }
                    loadSelectionMessagesDisposable.set(messages.start( next:{ [weak self] messages in
                        guard self?.chatInteraction.presentation.selectionState == selectionState else { return }
                        var canDelete:Bool = !messages.isEmpty && !context.isFrozen
                        var canForward:Bool = !messages.isEmpty && !context.isFrozen
                        if let chatInteraction = self?.chatInteraction {
                            for message in messages {
                                if !canDeleteMessage(message, account: context.account, chatLocation: value.chatLocation, mode: mode, ranks: self?.currentRanks) {
                                    canDelete = false
                                }
                                if !canForwardMessage(message, chatInteraction: chatInteraction) {
                                    canForward = false
                                }
                            }
                            chatInteraction.update({$0.withUpdatedBasicActions((canDelete, canForward))})
                        }
                        
                    }))
                    
                } else {
                    DispatchQueue.main.async { [weak self] in
                        guard self?.chatInteraction.presentation.selectionState == nil else { return }
                        self?.chatInteraction.update({$0.withUpdatedBasicActions((false, false))})
                    }
                }
                if value.selectionState != nil {
                    _ = window?.makeFirstResponder(selectManager)
                } else {
                    _ = window?.makeFirstResponder(self.firstResponder())
                }
                
                updateFloatingPhotos(self.genericView.scroll, animated: animated)
            }

            
            if oldValue.recordingState == nil && value.recordingState != nil {
                if let pause = ChatUIHooks.shared.getAudioPlayer(context)?.pause() {
                    isPausedGlobalPlayer = pause
                }
            } else if value.recordingState == nil && oldValue.recordingState != nil {
                if isPausedGlobalPlayer {
                    _ = ChatUIHooks.shared.getAudioPlayer(context)?.play()
                }
            }
            if let until = value.slowMode?.validUntil, until > self.context.timestamp {
                let signal = Signal<Void, NoError>.single(Void()) |> then(.single(Void()) |> delay(0.2, queue: .mainQueue()) |> restart)
                slowModeDisposable.set(signal.start(next: { [weak self] in
                    if let `self` = self {
                        if until < self.context.timestamp {
                            self.chatInteraction.update({$0.updateSlowMode({ $0?.withUpdatedTimeout(nil) })})
                        } else {
                            self.chatInteraction.update({$0.updateSlowMode({ $0?.withUpdatedTimeout(until - self.context.timestamp) })})
                        }
                    }
                }))
                
            } else {
                self.slowModeDisposable.set(nil)
                if let slowMode = value.slowMode, slowMode.timeout != nil {
                    DispatchQueue.main.async { [weak self] in
                        self?.chatInteraction.update({$0.updateSlowMode({ $0?.withUpdatedTimeout(nil) })})
                    }
                }
            }
            
            if value.inputQueryResult != oldValue.inputQueryResult || value.state != oldValue.state {
                genericView.inputContextHelper.context(with: value.inputQueryResult, for: genericView, relativeView: genericView.inputView.textFieldContainer, animated: true)
            }
            if value.interfaceState.inputState != oldValue.interfaceState.inputState {
                if didSetReady {
                    chatInteraction.saveState(false, scrollState: immediateScrollState())
                }
            }
            if value.searchMode.tag != oldValue.searchMode.tag || value.searchMode.showAll != oldValue.searchMode.showAll {
                let content: ChatHistoryLocation = .Scroll(index: MessageHistoryAnchorIndex.upperBound, anchorIndex: MessageHistoryAnchorIndex.upperBound, sourceIndex: MessageHistoryAnchorIndex.upperBound, scrollPosition: .down(true), count: self.requestCount, animated: true)
                if let tag = value.searchMode.tag, !value.searchMode.showAll {
                    self.setLocation(.init(content: content, chatLocation: self.chatLocation, tag: tag, id: self.takeNextHistoryLocationId()))
                } else {
                    self.setLocation(.init(content: content, chatLocation: self.chatLocation, tag: nil, id: self.takeNextHistoryLocationId()))
                }
            }
            
            if value.interfaceState.forwardMessageIds != oldValue.interfaceState.forwardMessageIds {
                let signal = (context.account.postbox.messagesAtIds(value.interfaceState.forwardMessageIds)) |> deliverOnMainQueue
                forwardMessagesDisposable.set(signal.start(next: { [weak self] messages in
                    self?.chatInteraction.update(animated: animated, {
                        $0.updatedInterfaceState {
                            $0.withUpdatedForwardMessages(messages)
                        }
                    })
                }))
            }
            
            if value.selectionState != oldValue.selectionState || value.reportMode != oldValue.reportMode {
                genericView.bubblesView.setMenuMode(value.selectionState != nil ? .done : .menu)
            }
            let input = value.effectiveInput
            if input != oldValue.effectiveInput || value.botMenu != oldValue.botMenu || force {
                
                let textInputContextState = textInputStateContextQueryRangeAndType(input, includeContext: false)
                
                var cleanup = true
                
                if let textInputContextState = textInputContextState {
                    if textInputContextState.1.contains(.swapEmoji) {
                        let stringRange = textInputContextState.0
                        let range = NSRange(string: input.inputText, range: stringRange)
                        if !input.isAnimatedEmoji(at: range) {
                            let query = String(input.inputText[stringRange])
                            let signal = InputSwapSuggestionsPanelItems(query, peerId: chatInteraction.peerId, context: chatInteraction.interactionContext)
                            |> deliverOnMainQueue
                            self.inputSwapDisposable.set(signal.start(next: { [weak self] files in
                                self?.genericView.updateTextInputSuggestions(files, range: range, animated: animated)
                            }))
                            cleanup = false
                        }
                    }
                }
                if cleanup {
                    self.genericView.updateTextInputSuggestions([], range: NSMakeRange(0, 0), animated: animated)
                    self.inputSwapDisposable.set(nil)
                }
                
                if let (updatedContextQueryState, updatedContextQuerySignal) = contextQueryResultStateForChatInterfacePresentationState(value, context: self.context, currentQuery: self.contextQueryState?.0) {
                    self.contextQueryState?.1.dispose()
                    var inScope = true
                    var inScopeResult: ((ChatPresentationInputQueryResult?) -> ChatPresentationInputQueryResult?)?
                    self.contextQueryState = (updatedContextQueryState, (updatedContextQuerySignal |> deliverOnMainQueue).start(next: { [weak self] result in
                        if let strongSelf = self {
                            if Thread.isMainThread && inScope {
                                inScope = false
                                inScopeResult = result
                            } else {
                                strongSelf.chatInteraction.update(animated: animated, {
                                    $0.updatedInputQueryResult { previousResult in
                                        return result(previousResult)
                                    }
                                })
                                
                            }
                        }
                    }))
                    inScope = false
                    if let inScopeResult = inScopeResult {
                        
                        chatInteraction.update(animated: animated, {
                            $0.updatedInputQueryResult { previousResult in
                                return inScopeResult(previousResult)
                            }
                        })
                        
                    }
                    
                    var disableEditingPreview:((String)->Void)? = nil
                    if oldValue.interfaceState.editState == nil, value.interfaceState.editState != nil {
                        disableEditingPreview = { [weak self] value in
                            self?.chatInteraction.update({ $0.updatedInterfaceState{
                                $0.withUpdatedComposeDisableUrlPreview(value)
                            }})
                        }
                    }
                    
                    let updateUrl = urlPreviewStateForChatInterfacePresentationState(chatInteraction.presentation, context: context, currentQuery: self.urlPreviewQueryState?.0, disableEditingPreview: disableEditingPreview) |> delay(value.effectiveInput.inputText.isEmpty ? 0.0 : 0.1, queue: .mainQueue()) |> deliverOnMainQueue
                    
                    updateUrlDisposable.set(updateUrl.start(next: { [weak self] result in
                        if let `self` = self, let (updatedUrlPreviewUrl, updatedUrlPreviewSignal) = result {
                            self.urlPreviewQueryState?.1.dispose()
                            var inScope = true
                            var inScopeResult: ((TelegramMediaWebpage?) -> TelegramMediaWebpage?)?
                            self.urlPreviewQueryState = (updatedUrlPreviewUrl, (updatedUrlPreviewSignal |> deliverOnMainQueue).start(next: { [weak self] result in
                                if let strongSelf = self {
                                    if Thread.isMainThread && inScope {
                                        inScope = false
                                        inScopeResult = result
                                    } else {
                                        strongSelf.chatInteraction.update(animated: true, {
                                            if let updatedUrlPreviewUrl = updatedUrlPreviewUrl, let webpage = result($0.urlPreview?.1) {
                                                return $0.updatedUrlPreview((updatedUrlPreviewUrl, webpage))
                                            } else {
                                                return $0.updatedUrlPreview(nil)
                                            }
                                        })
                                    }
                                }
                            }))
                            inScope = false
                            if let inScopeResult = inScopeResult {
                                self.chatInteraction.update(animated: true, {
                                    if let updatedUrlPreviewUrl = updatedUrlPreviewUrl, let webpage = inScopeResult($0.urlPreview?.1) {
                                        return $0.updatedUrlPreview((updatedUrlPreviewUrl, webpage))
                                    } else {
                                        return $0.updatedUrlPreview(nil)
                                    }
                                })
                            }
                        }
                    }))
                }
            }
            
            
            if value.monoforumState != oldValue.monoforumState || value.monoforumTopics != oldValue.monoforumTopics || value.chatLocation != oldValue.chatLocation {
                genericView.updateMonoforumState(state: value.monoforumState, items: value.monoforumTopics, threadId: value.chatLocation.threadId, animated: animated)
            }
            
            
            if value.searchMode != oldValue.searchMode || value.pinnedMessageId != oldValue.pinnedMessageId || value.peerStatus != oldValue.peerStatus || value.interfaceState.dismissedPinnedMessageId != oldValue.interfaceState.dismissedPinnedMessageId || value.initialAction != oldValue.initialAction || value.restrictionInfo != oldValue.restrictionInfo || value.hidePinnedMessage != oldValue.hidePinnedMessage || value.groupCall != oldValue.groupCall || value.reportMode != oldValue.reportMode || value.inviteRequestsPendingPeers != oldValue.inviteRequestsPendingPeers || value.threadInfo?.isClosed != oldValue.threadInfo?.isClosed || value.translateState != oldValue.translateState || value.savedMessageTags != oldValue.savedMessageTags || value.connectedBot != oldValue.connectedBot || value.adMessage != oldValue.adMessage || value.historyCount != oldValue.historyCount || value.monoforumState != oldValue.monoforumState || value.removePaidMessageFeeData != oldValue.removePaidMessageFeeData || value.chatLocation.threadId != oldValue.chatLocation.threadId || value.managedBotNeedsPhoto != oldValue.managedBotNeedsPhoto {
                genericView.bubblesView.updatePresentation(value, force: true)
                genericView.updateHeader(value, animated, value.hidePinnedMessage != oldValue.hidePinnedMessage)
            }
            
            if value.chatLocation != oldValue.chatLocation {
                self.setLocation(.Initial(count: self.requestCount, scrollPosition: .down(true)), chatLocation: value.chatLocation)
            }
                     
            if value.chatLocation.threadId == nil {
                self.subscribeForNewTopicEvents(peerId: value.chatLocation.peerId)
            }
            
            if value.reportMode != oldValue.reportMode {
                self.genericView.bubblesView.updateSearchButton(hidden: !isSearchAvailable(value), animated: animated)
            }

            if (value.peer != nil && oldValue.peer == nil) || value.isNotAccessible != oldValue.isNotAccessible {
                genericView.tableView.emptyItem = ChatEmptyPeerItem(genericView.tableView.frame.size, chatInteraction: chatInteraction, theme: previousView.with { $0?.theme ?? theme })
            }

            if let peer = value.peer {
                self.updateCaptureExclusion(peer.id.isSecretChat)
            }

            var upgradedToPeerId: PeerId?
            if let previous = oldValue.peer, let group = previous as? TelegramGroup, group.migrationReference == nil, let updatedGroup = value.peer as? TelegramGroup, let migrationReference = updatedGroup.migrationReference {
                upgradedToPeerId = migrationReference.peerId
            }


            self.state = value.selectionState != nil ? .Edit : .Normal
            
            if let upgradedToPeerId = upgradedToPeerId, navigationController?.controller == self {
                let controller = ChatController(context: context, chatLocation: .peer(upgradedToPeerId))
                navigationController?.removeAll()
                navigationController?.push(controller, false, style: ViewControllerStyle.none)
            }
            
            if value.recordingState != oldValue.recordingState {
                if let state = value.recordingState {
                    let activity: PeerInputActivity = state is ChatRecordingAudioState ? .recordingVoice : .recordingInstantVideo
                    
                    let recursive = (Signal<Void, NoError>.single(Void()) |> then(.single(Void()) |> suspendAwareDelay(4, queue: .mainQueue()))) |> restart
                    
                    recordActivityDisposable.set(recursive.start(next: { [weak self] in
                        guard let `self` = self else {
                            return
                        }
                        if self.chatInteraction.peerIsAccountPeer {
                            self.context.account.updateLocalInputActivity(peerId: .init(peerId: self.chatLocation.peerId, category: mode.activityCategory(value.chatLocation.threadId)), activity: activity, isPresent: true)
                        }
                    }))
                    
                } else if let state = oldValue.recordingState {
                    let activity: PeerInputActivity = state is ChatRecordingAudioState ? .recordingVoice : .recordingInstantVideo
                    if self.chatInteraction.peerIsAccountPeer {
                        self.context.account.updateLocalInputActivity(peerId: .init(peerId: self.chatLocation.peerId, category: mode.activityCategory(value.chatLocation.threadId)), activity: activity, isPresent: false)
                    }
                    recordActivityDisposable.set(nil)
                    if let state = state as? ChatRecordingVideoState, !state.isCancelled, let previewView = self.videoRecorderModal?.previewView, previewView.window != nil {
                        let snapshot = state.pipeline.thumbnail.flatMap { thumbnail -> CGImage? in
                            let side = min(thumbnail.width, thumbnail.height)
                            return thumbnail.cropping(to: CGRect(x: (thumbnail.width - side) / 2, y: (thumbnail.height - side) / 2, width: side, height: side))
                        }
                        self.chatInteraction.mediaSendFlight?.launch(ChatMediaSendFlightSource(rect: previewView.convert(previewView.bounds, to: nil), snapshot: snapshot, cornerRadius: previewView.bounds.width / 2, sourceLayer: previewView.layer))
                    }
                }
            }
            
            dismissedPinnedIds.set(ChatDismissedPins(ids: value.interfaceState.dismissedPinnedMessageId, tempMaxId: value.tempPinnedMaxId))
           
            
            if value.inviteRequestsPending != oldValue.inviteRequestsPending, let count = value.inviteRequestsPending, count > 0, !self.chatInteraction.presentation.isTopicMode, let peer = value.peer as? TelegramChannel, peer.groupAccess.canCreateInviteLink {
        
                let peerId = self.chatLocation.peerId
                let current:PeerInvitationImportersContext
                if let value = self.tempImportersContext {
                    current = value
                } else {
                    let importersContext = context.engine.peers.peerInvitationImporters(peerId: peerId, subject: .requests(query: nil))
                    importersContext.loadMore()
                    current = importersContext
                }
                self.tempImportersContext = current
                let state = current.state
                |> filter { !$0.isLoadingMore }
                |> deliverOnMainQueue
                tempImportersContextDisposable.set(state.start(next: { [weak self] state in
                    let check = FastSettings.canBeShownPendingRequests(state.importers.compactMap { $0.peer.peer?.id }, for: peerId)
                    if check || state.importers.isEmpty  {
                        self?.chatInteraction.update {
                            $0.withUpdatedInviteRequestsPendingPeers(state.importers)
                        }
                    }
                }))
            } else {
                if value.inviteRequestsPending == nil || value.inviteRequestsPending == 0 {
                    tempImportersContext = nil
                    tempImportersContextDisposable.set(nil)
                }
            }
            
            if let peer = value.mainPeer, let oldPeer = oldValue.mainPeer {
                if TelegramUtilsHooks.shared.peerIsForum(peer) && !TelegramUtilsHooks.shared.peerIsForum(oldPeer) || (oldValue.threadInfo != nil && value.threadInfo == nil && !peer.displayForumAsTabs(splitState: context.layout)), !peer.isMonoForum {
                    if (self.navigationController?.stackCount ?? 0) > 1 {
                        self.navigationController?.removeImmediately(self)
                    } else if self.mode == .preview {
                        self.navigationController?.modal?.close()
                    }
                }
            }

        }
        
    }
    
    
    func immediateScrollState() -> ChatInterfaceHistoryScrollState? {
        
        var message:Message?
        var index:Int?
        self.genericView.tableView.enumerateVisibleItems(reversed: true, with: { item -> Bool in
            
            if let item = item as? ChatRowItem {
                message = item.message
                index = item.index
            }
            return message == nil
        })
        
        if let visibleIndex = index, let message = message {
            let rect = genericView.tableView.rectOf(index: visibleIndex)
            let top = genericView.tableView.documentOffset.y + genericView.tableView.frame.height
            if genericView.tableView.frame.height >= genericView.tableView.documentOffset.y && historyState.isDownOfHistory {
                return nil
            } else {
                let relativeOffset: CGFloat = top - rect.maxY
                return ChatInterfaceHistoryScrollState(messageIndex: MessageIndex(message), relativeOffset: Double(relativeOffset))
            }
        }
        
        return nil
    }
  

    public func isEqual(to other: Notifable) -> Bool {
        if let other = other as? ChatController {
            return other == self
        }
        return false
    }
    
    private func playUnseenReactions(_ messageIds: Set<MessageId>, checkUnseen: Bool = false) {
        
        self.genericView.tableView.enumerateVisibleItems(with: { item in
            guard let item = item as? ChatRowItem else {
                return true
            }
            for id in messageIds {
                if item.firstMessage?.id == id, let view = item.view as? ChatRowView {
                    if view.visibleRect.height == view.frame.height {
                        view.playSeenReactionEffect(checkUnseen)
                    }
                }
            }
            return true
        })
    }
    
    public override func draggingExited() {
        super.draggingExited()
        genericView.inputView.isHidden = false
    }
    public override func draggingEntered() {
        super.draggingEntered()
        genericView.inputView.isHidden = true
    }
    
    public override func draggingItems(for pasteboard:NSPasteboard) -> [DragItem] {
        
        if let window = self.window, hasModals(window) {
            return []
        }
        
        if case .block = chatInteraction.presentation.state {
            return []
        }

        let peerId = self.chatInteraction.peerId
        let dropAction = self.chatInteraction.captureDeferredSendAction()
        
        if let types = pasteboard.types, types.contains(.kFilenames) {
            let list = pasteboard.propertyList(forType: .kFilenames) as? [String]
            
            if let list = list, list.count > 0 {
                
                var items:[DragItem] = []
                
                let list = list.filter { path -> Bool in
                    if let size = fileSize(path) {
                        let exceed = fileSizeLimitExceed(context: context, fileSize: size)
                        return exceed
                    }
                    return false
                }
                
                if list.count == 1, let editState = chatInteraction.presentation.interfaceState.editState, editState.canEditMedia {
                    let editingSessionId = self.editingSessionId
                    let messageId = editState.message.id
                    return [DragItem(title: strings().chatDropEditTitle, desc: strings().chatDropEditDesc, handler: { [weak self] in
                        guard let self, self.editingSessionId == editingSessionId,
                              self.chatInteraction.presentation.interfaceState.editState?.message.id == messageId,
                              dropAction.takeIfCurrent() else { return }
                        let replacement = self.chatInteraction.beginMediaReplacement()
                        NSApp.activate(ignoringOtherApps: true)
                        self.editCurrentMessagePhotoDisposable.set(nil)
                        self.updateMediaDisposable.set((Sender.generateMedia(for: MediaSenderContainer(path: list[0], isFile: false), account: self.chatInteraction.interactionContext.account, isSecretRelated: peerId.namespace == Namespaces.Peer.SecretChat) |> deliverOnMainQueue).start(next: { [weak self] media, _ in
                            guard let self, self.editingSessionId == editingSessionId,
                                  self.chatInteraction.presentation.interfaceState.editState?.message.id == messageId else { return }
                            self.chatInteraction.applyMediaReplacement(media, request: replacement)
                        }))
                    })]
                }

                if !list.isEmpty {
                    
                    
                    let asMediaItem = DragItem(title: strings().chatDropTitle, desc: strings().chatDropQuickDesc, handler:{ [weak self] in
                        guard let self, dropAction.takeIfCurrent() else { return }
                        NSApp.activate(ignoringOtherApps: true)
                        self.chatInteraction.showPreviewSender(list.map { URL(fileURLWithPath: $0) }, true, nil)
                    })
                    let fileTitle: String
                    let fileDesc: String
                    
                    if list.count == 1, list[0].isDirectory {
                        fileTitle = strings().chatDropFolderTitle
                        fileDesc = strings().chatDropFolderDesc
                    } else {
                        fileTitle = strings().chatDropTitle
                        fileDesc = strings().chatDropAsFilesDesc
                    }
                    let asFileItem = DragItem(title: fileTitle, desc: fileDesc, handler: { [weak self] in
                        guard let self, dropAction.takeIfCurrent() else { return }
                        NSApp.activate(ignoringOtherApps: true)
                        let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
                        if shift {
                            self.chatInteraction.sendMedia(list.map{MediaSenderContainer(path: $0, caption: "", isFile: true)})
                        } else {
                            self.chatInteraction.showPreviewSender(list.map { URL(fileURLWithPath: $0) }, false, nil)
                        }
                    })
                    
                    items.append(asFileItem)
                    
                    
                    var asMedia:Bool = false
                    for path in list {
                        if mediaExts.contains(path.nsstring.pathExtension.lowercased()) {
                            asMedia = true
                            break
                        }
                    }
                    
                    if asMedia {
                        items.append(asMediaItem)
                    } 
    
                }

                return items
            }
            //NSTIFFPboardType
        } else if let types = pasteboard.types, types.contains(.tiff) {
            let data = pasteboard.data(forType: .tiff)
            if let data = data, let image = NSImage(data: data) {
                
                if let editState = chatInteraction.presentation.interfaceState.editState, editState.canEditMedia {
                    let editingSessionId = self.editingSessionId
                    let messageId = editState.message.id
                    return [DragItem(title: strings().chatDropEditTitle, desc: strings().chatDropEditDesc, handler: { [weak self] in
                        guard let self, self.editingSessionId == editingSessionId,
                              self.chatInteraction.presentation.interfaceState.editState?.message.id == messageId,
                              dropAction.takeIfCurrent() else { return }
                        let replacement = self.chatInteraction.beginMediaReplacement()
                        NSApp.activate(ignoringOtherApps: true)
                        self.editCurrentMessagePhotoDisposable.set(nil)
                        let account = self.chatInteraction.interactionContext.account
                        self.updateMediaDisposable.set((putToTemp(image: image) |> mapToSignal {
                            Sender.generateMedia(for: MediaSenderContainer(path: $0, isFile: false), account: account, isSecretRelated: peerId.namespace == Namespaces.Peer.SecretChat)
                        } |> deliverOnMainQueue).start(next: { [weak self] media, _ in
                            guard let self, self.editingSessionId == editingSessionId,
                                  self.chatInteraction.presentation.interfaceState.editState?.message.id == messageId else { return }
                            self.chatInteraction.applyMediaReplacement(media, request: replacement)
                        }))
                    })]
                }

                var items:[DragItem] = []

                let asMediaItem = DragItem(title: strings().chatDropTitle, desc: strings().chatDropQuickDesc, handler:{ [weak self] in
                    guard let self, dropAction.takeIfCurrent() else { return }
                    NSApp.activate(ignoringOtherApps: true)
                    let preparedAction = self.chatInteraction.captureDeferredSendAction()
                    _ = (putToTemp(image: image) |> deliverOnMainQueue).start(next: { [weak self] path in
                        guard let self else {
                            return
                        }
                        guard preparedAction.takeIfCurrent(onInvalidated: {}) else { return }
                        self.chatInteraction.showPreviewSender([URL(fileURLWithPath: path)], true, nil)
                    })

                })
                
                let asFileItem = DragItem(title: strings().chatDropTitle, desc: strings().chatDropAsFilesDesc, handler:{ [weak self] in
                    guard let self, dropAction.takeIfCurrent() else { return }
                    NSApp.activate(ignoringOtherApps: true)
                    let preparedAction = self.chatInteraction.captureDeferredSendAction()
                    _ = (putToTemp(image: image) |> deliverOnMainQueue).start(next: { [weak self] path in
                        guard let self else {
                            return
                        }
                        guard preparedAction.takeIfCurrent(onInvalidated: {}) else { return }
                        self.chatInteraction.showPreviewSender([URL(fileURLWithPath: path)], false, nil)
                    })
                })
                
                items.append(asFileItem)
                items.append(asMediaItem)
                
                return items
            }
        }
        
        return []
    }
    
    override public var isOpaque: Bool {
        return false
    }
    
    public override func updateController() {
        genericView.tableView.enumerateVisibleViews(with: { view in
            if let view = view as? ChatRowView {
                view.updateBackground(animated: false, item: view.item)
            }
        }, force: true)
    }

    override open func backSettings() -> (String,CGImage?) {
        if context.layout == .single {
            return super.backSettings()
        }
        return (strings().navigationClose,nil)
    }

    public func update(with state:ViewControllerState) -> Void {
        chatInteraction.update({state == .Normal ? $0.withoutSelectionState().withUpdatedRepotMode(nil) : $0.withSelectionState()})
        context.window.applyResponderIfNeeded()
    }
    
    public override func initializer() -> ChatControllerView {
        return ChatControllerView(frame: NSMakeRect(_frameRect.minX, _frameRect.minY, _frameRect.width, _frameRect.height - self.bar.height), chatInteraction:chatInteraction);
    }
    
    public override func requestUpdateCenterBar() {
       
    }
    func closeChatThemesSelector() {
        self.themeSelector?.close(true)
    }
    
    func findStoryControl(_ messageId: MessageId?, _ storyId: Int32?, _ peerId: PeerId, useAvatar: Bool = false) -> NSView? {
        var control: NSView? = nil
        
        if useAvatar, !self.grouppedFloatingPhotos.isEmpty {
            for value in grouppedFloatingPhotos {
                if value.0.contains(where: { $0.messages.contains(where: { $0.id == messageId })}), let control = value.1.storyControl {
                    return control
                }
            }
        }
        
        genericView.tableView.enumerateVisibleItems(with: { item in
            guard let id = storyId else {
                return false
            }
            let storyId: StoryId = .init(peerId: peerId, id: id)
            if let item = item as? ChatRowItem, messageId == item.message?.id || messageId == nil {
                if useAvatar, let view = item.view as? ChatRowView {
                    control = view.storyAvatarControl
                    return false
                }
                if let attr = item.message?.storyAttribute {
                    if attr.storyId == storyId {
                        if let view = item.view as? ChatRowView {
                            control = view.storyControl(storyId)
                        }
                    }
                } else if let media = item.message?.media.first as? TelegramMediaStory, media.storyId == storyId {
                    control = (item.view as? ChatRowView)?.storyMediaControl ?? (item.view as? ChatServiceRowView)?.storyMediaControl
                } else if let media = item.message?.media.first as? TelegramMediaWebpage {
                    switch media.content {
                    case let .Loaded(content):
                        if content.story?.storyId == storyId {
                            control = (item.view as? ChatRowView)?.storyMediaControl
                        }
                    default:
                        break
                    }
                }
            }
            return control == nil
        })
        return control
    }
    
    func showChatThemeSelector() {
        
        guard themeSelector == nil else {
            return
        }
        
        let context = self.context
        
        if let peer = chatInteraction.peer as? TelegramChannel {
            if peer.hasPermission(.changeInfo) {
                navigationController?.push(ChatNavigationHooks.shared.makeSelectColorController(context, peer))
            }
            return
        }
        
        self.themeSelector = ChatThemeSelectorController(context, installedTheme: self.uiState.with { $0.presentation_emoticon }, chatTheme: chatThemeValue.get(), chatInteraction: self.chatInteraction)
        self.themeSelector?.onReady = { [weak self] controller in
            self?.genericView.showChatThemeSelector(controller.view, animated: true)
        }
        self.themeSelector?.close = { [weak self] drop in
            if drop {
                self?.chatThemeTempValue.set(.single(nil))
            }
            self?.genericView.hideChatThemeSelector(animated: true)
            self?.themeSelector = nil
            self?.chatInteraction.update({ $0.updatedInterfaceState({ $0.withUpdatedThemeEditing(false) })})
        }
        
        self.themeSelector?.previewCurrent = { [weak self] theme in
            if let value = theme.1 {
                self?.chatThemeTempValue.set(.single((theme.0, value)))
            } else {
                self?.chatThemeTempValue.set(.single(nil))
            }
        }
        
        self.themeSelector?._frameRect = NSMakeRect(0, self.frame.maxY, frame.width, 230)
        self.themeSelector?.loadViewIfNeeded()
        
        self.chatInteraction.update({ $0.updatedInterfaceState({ $0.withUpdatedThemeEditing(true) })})
    }
    
    public func focusExistingMessage(_ message: Message) -> Void {
        let scroll: TableScrollState = .center(id: ChatHistoryEntryId.message(message), innerId: nil, animated: true, focus: .init(focus: true, string: nil), inset: 0)
        genericView.tableView.scroll(to: scroll)
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: genericView.chatTheme ?? theme)
    }
    
    
    public func selectionDidChange(row:Int, item:TableRowItem, byClick:Bool, isNew:Bool) -> Void {
        
    }
    public func selectionWillChange(row:Int, item:TableRowItem, byClick: Bool) -> Bool {
        return false
    }
    public func isSelectable(row:Int, item:TableRowItem) -> Bool {
        return false
    }
    public func findGroupStableId(for stableId: AnyHashable) -> AnyHashable? {
        return previousView.with { view in
            if let view = view, let stableId = stableId.base as? ChatHistoryEntryId {
                switch stableId {
                case let .message(message):
                    for entry in view.filteredEntries {
                        s: switch entry.entry {
                        case let .groupedPhotos(entries, _):
                            for groupedEntry in entries {
                                if message.id == groupedEntry.message?.id {
                                    return entry.stableId
                                }
                            }
                        default:
                            break s
                        }
                    }
                case let .mediaId(_, message):
                    return ChatHistoryEntryId.message(message)
                default:
                    break
                }
            }
            return nil
        }
    }
    
    public override var containerCornerRadius: CGFloat {
        return 0
    }

    
}





extension ChatControllerView: ChatVoiceTranscriptionHost {
    func setTranscriptionView(_ view: ChatVoiceTranscriptionView?, animated: Bool) {
        let animated = animated && window != nil
        if let previous = transcriptionView, previous !== view {
            if animated {
                previous.animateOut(completion: { [weak previous] in
                    previous?.removeFromSuperview()
                })
            } else {
                previous.removeFromSuperview()
            }
        }
        transcriptionView = view
        if let view {
            addSubview(view, positioned: .below, relativeTo: inputView)
            let height = view.contentHeight
            view.frame = NSMakeRect(0, inputView.frame.minY - height - 10, frame.width, height)
            view.updateLayout(size: view.frame.size, transition: .immediate)
            if animated {
                view.animateIn()
            }
        }
        transcriptionLayoutDidChange(animated: animated)
    }

    func transcriptionLayoutDidChange(animated: Bool) {
        inputChanged(height: inputView.height(for: frame.width), animated: animated)
    }

    var transcriptionWidth: CGFloat {
        return frame.width
    }

    func transcriptionGradient() -> (rect: NSRect, size: NSSize) {
        let rect = chatInteraction.getGradientOffsetRect()
        return (rect, NSMakeSize(rect.width, rect.height + 60))
    }
}

