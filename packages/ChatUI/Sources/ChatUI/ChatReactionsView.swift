import Foundation
import TGUIKit
import TelegramCore
import Postbox
import Reactions
import AppKit
import SwiftSignalKit
import TelegramMedia
import TelegramMediaResources
import AvatarUI
import LocalAnimations
import Localization
import MessageUtils
import SceneEffects
import StarsUI
import Strings
import TelegramContext
import TelegramTheme
import TelegramUtils
import InlineStickerLayer

private func tagImage(_ color: NSColor)->NSImage? {
    let image = TelegramThemeHooks.shared.image(.iconReactionTagBackground)
    return NSImage(cgImage: generateTintedImage(image: image._cgImage, color: color)!, size: image.size)
}






extension MessageReaction {
    public static func <(lhs: MessageReaction, rhs: MessageReaction) -> Bool {
        
        if rhs.value == .stars {
            return false
        }
        var lhsCount = lhs.count
        if lhs.chosenOrder != nil {
            lhsCount -= 1
        }
        var rhsCount = rhs.count
        if rhs.chosenOrder != nil {
            rhsCount -= 1
        }
        if lhsCount != rhsCount {
            return lhsCount > rhsCount
        }
        
        if (lhs.chosenOrder != nil) != (rhs.chosenOrder != nil) {
            if lhs.chosenOrder != nil {
                return true
            } else {
                return false
            }
        } else if let lhsIndex = lhs.chosenOrder, let rhsIndex = rhs.chosenOrder {
            return lhsIndex < rhsIndex
        }
        return false
    }
}

public final class ChatReactionsLayout {
    
    public struct Theme : Equatable {
        public let bgColor: NSColor
        public let textColor: NSColor
        public let borderColor: NSColor
        public let selectedColor: NSColor
        public let textSelectedColor: NSColor
        public let reactionSize: NSSize
        public let avatarSize: NSSize
        public let insetOuter: CGFloat
        public let insetInner: CGFloat

        public let renderType: ChatItemRenderType
        public let isIncoming: Bool
        public let isOutOfBounds: Bool
        public let hasWallpaper: Bool
        public let tagBackground: NSImage?
        
        public static func Current(theme: TelegramPresentationTheme, renderType: ChatItemRenderType, isIncoming: Bool, isOutOfBounds: Bool, hasWallpaper: Bool, stateOverlayTextColor: NSColor, mode: ChatReactionsLayout.Mode, isStars: Bool) -> Theme {
            let bgColor: NSColor
            let textColor: NSColor
            let textSelectedColor: NSColor
            let borderColor: NSColor
            let selectedColor: NSColor
            
            let gold_alpha = GOLD.withAlphaComponent(0.2)
            
            switch mode {
            case .full, .tag:
                switch renderType {
                case .bubble:
                    if isOutOfBounds {
                        if !hasWallpaper {
                            bgColor = isStars ? gold_alpha : theme.colors.grayIcon.withAlphaComponent(0.3)
                            textColor = isStars ? GOLD : theme.colors.accent
                            borderColor = .clear
                            selectedColor = isStars ? GOLD : theme.colors.accent
                            textSelectedColor = isStars ? NSColor(0xffffff) : theme.colors.underSelectedColor
                        } else {
                            bgColor = theme.blurServiceColor
                            textColor = theme.chatServiceItemTextColor
                            borderColor = .clear
                            selectedColor = isStars ? GOLD : theme.colors.accent
                            textSelectedColor = isStars ? NSColor(0xffffff) : selectedColor.underTextColor
                        }
                    } else {
                        if isIncoming {
                            bgColor = isStars ? gold_alpha : theme.colors.accent.withAlphaComponent(0.15)
                            textColor = isStars ? GOLD : theme.colors.accent
                            borderColor = .clear
                            selectedColor = isStars ? GOLD : theme.colors.accent
                            textSelectedColor = selectedColor.underTextColor
                        } else {
                            bgColor = theme.chat.grayText(false, true).withAlphaComponent(0.15)
                            textColor = theme.chat.grayText(false, true)
                            borderColor = .clear
                            selectedColor = isStars ? GOLD : theme.chat.grayText(false, true)
                            textSelectedColor = isStars ? NSColor(0xffffff) : theme.colors.blendedOutgoingColors
                        }
                    }
                case .list:
                    bgColor = isStars ? gold_alpha : theme.colors.accent.withAlphaComponent(0.15)
                    textColor = isStars ? GOLD : theme.colors.accent
                    borderColor = .clear
                    selectedColor = isStars ? GOLD : theme.colors.accent
                    textSelectedColor = selectedColor.underTextColor
                }
            }
           
            let size: NSSize
            switch mode {
            case .full, .tag:
                size = NSMakeSize(16, 16)
            }
            
            return .init(bgColor: bgColor, textColor: textColor, borderColor: borderColor, selectedColor: selectedColor, textSelectedColor: textSelectedColor, reactionSize: size, avatarSize: NSMakeSize(20, 20), insetOuter: 10, insetInner: 5, renderType: renderType, isIncoming: isIncoming, isOutOfBounds: isOutOfBounds, hasWallpaper: hasWallpaper, tagBackground: mode == .tag ? tagImage(selectedColor) : nil)

        }
    }
    
    public final class Reaction : Equatable, Comparable, Identifiable {
        
        public enum Source : Equatable {
            case builtin(AvailableReactions.Reaction)
            case custom(Int64, TelegramMediaFile?, TelegramMediaFile?)
            case stars(TelegramMediaFile, TelegramMediaFile?)
            public var file: TelegramMediaFile? {
                switch self {
                case .builtin:
                    return nil
                case let .custom(_, file, _):
                    return file
                case let .stars(file, _):
                    return file
                }
            }
        }

        private var _cachedBuiltinAnimationFile: TelegramMediaFile?
        private var _cachedBuiltinEffectFile: TelegramMediaFile?

        private func builtinAnimationFile(_ reaction: AvailableReactions.Reaction) -> TelegramMediaFile {
            if let cached = _cachedBuiltinAnimationFile {
                return cached
            }
            let file = sharedParsedReactionFile(reaction.centerAnimation ?? reaction.selectAnimation)
            _cachedBuiltinAnimationFile = file
            return file
        }

        private func builtinEffectFile(_ reaction: AvailableReactions.Reaction) -> TelegramMediaFile? {
            if let cached = _cachedBuiltinEffectFile {
                return cached
            }
            let file = reaction.centerAnimation.flatMap(sharedParsedReactionFile)
            _cachedBuiltinEffectFile = file
            return file
        }

        public var effectFile: TelegramMediaFile? {
            switch source {
            case let .builtin(reaction):
                return builtinEffectFile(reaction)
            case let .custom(_, _, effect):
                return effect
            case let .stars(file, _):
                return file
            }
        }

        public func getInlineLayer(_ mode: ChatReactionsLayout.Mode) -> InlineStickerItemLayer {
            switch source {
            case let .builtin(reaction):
                return .init(account: context.account, file: builtinAnimationFile(reaction), size: NSMakeSize(presentation.reactionSize.width * 2, presentation.reactionSize.height * 2), playPolicy: .framesCount(1), shimmerColor: .init(color: presentation.bgColor.darker(), circle: true))
            case let .custom(fileId, file, _):
                var reactionSize: NSSize = presentation.reactionSize
                reactionSize.width += 3
                reactionSize.height += 3
                let textColor = value.isSelected ? presentation.textSelectedColor : presentation.textColor
                return .init(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: .init(fileId: fileId, file: file, emoji: ""), size: reactionSize, getColors: { file in
                    var colors: [LottieColor] = []
                    if file.paintToText {
                        colors.append(.init(keyPath: "", color: textColor))
                    }
                    return colors
                }, shimmerColor: .init(color: presentation.bgColor.darker(), circle: true))
            case .stars:
                return .init(account: context.account, file: LocalAnimatedSticker.premium_reaction_6.file, size: NSMakeSize(presentation.reactionSize.width + 4, presentation.reactionSize.height + 4), playPolicy: .framesCount(1), shimmerColor: .init(color: presentation.bgColor.darker(), circle: true))
            }
        }
        

        
        public let value: MessageReaction
        public let text: TextViewLayout?
        public let presentation: Theme
        public let index: Int
        public let minimumSize: NSSize
        
        public let source: Source
        
        public let mode: ChatReactionsLayout.Mode
        public let currentTag: MessageReaction.Reaction?
        public let disposable: MetaDisposable = MetaDisposable()
        public let delayDisposable = MetaDisposable()
        public let action:(MessageReaction.Reaction, Bool)->Void
        public let context: any AccountContextProtocol
        public let message: Message
        public let openInfo: (PeerId)->Void
        public let runEffect:(MessageReaction.Reaction, Bool)->Void
        public let canViewList: Bool
        public let avatars:[Avatar]
        public var rect: CGRect = .zero
        public let starReact:()->Void
        
        public static func ==(lhs: Reaction, rhs: Reaction) -> Bool {
            return lhs.value == rhs.value &&
            lhs.presentation == rhs.presentation &&
            lhs.index == rhs.index &&
            lhs.minimumSize == rhs.minimumSize &&
            lhs.source == rhs.source &&
            lhs.mode == rhs.mode &&
            lhs.rect == rhs.rect &&
            lhs.message.id == rhs.message.id &&
            lhs.message.containsSecretMedia == rhs.message.containsSecretMedia &&
            lhs.canViewList == rhs.canViewList &&
            lhs.message.effectiveReactions(isTags: lhs.context.peerId == lhs.message.id.peerId) == rhs.message.effectiveReactions(isTags: rhs.context.peerId == rhs.message.id.peerId)
        }
        public static func <(lhs: Reaction, rhs: Reaction) -> Bool {
            return lhs.index < rhs.index
        }
        public var stableId: MessageReaction.Reaction {
            return self.value.value
        }
        
        public init(value: MessageReaction, recentPeers:[Peer], canViewList: Bool, message: Message, savedMessageTags: SavedMessageTags?, currentTag: MessageReaction.Reaction?, context: any AccountContextProtocol, mode: ChatReactionsLayout.Mode, index: Int, source: Source, presentation: Theme, action:@escaping(MessageReaction.Reaction, Bool)->Void, openInfo: @escaping (PeerId)->Void, runEffect:@escaping(MessageReaction.Reaction, Bool)->Void, starReact: @escaping()->Void) {
            self.value = value
            self.index = index
            self.message = message
            self.canViewList = canViewList
            self.action = action
            self.source = source
            self.context = context
            self.currentTag = currentTag
            self.presentation = presentation
            self.mode = mode
            self.openInfo = openInfo
            self.runEffect = runEffect
            self.starReact = starReact
            switch mode {
            case .full, .tag:
                let height = presentation.reactionSize.height + presentation.insetInner * 2
                if self.value.value.isEmpty {
                    self.minimumSize = NSMakeSize(34, height)
                    self.avatars = []
                    self.text = nil
                } else {
                    if let title = savedMessageTags?.tags.first(where: { $0.reaction == value.value })?.title {
                        self.text = .init(.initialize(string: title, color: value.isSelected ? presentation.textSelectedColor : presentation.textColor, font: .normal(.text)))
                        self.text?.measure(width: .greatestFiniteMagnitude)

                    } else {
                        if recentPeers.isEmpty, mode != .tag {
                            self.text = .init(.initialize(string: Int(value.count).prettyNumber, color: value.isSelected ? presentation.textSelectedColor : presentation.textColor, font: .normal(.text)))
                            self.text?.measure(width: .greatestFiniteMagnitude)
                        } else {
                            self.text = nil
                        }
                    }
                    
                    
                    var width: CGFloat = presentation.insetOuter
                    width += presentation.reactionSize.width
                    if let text = text {
                        width += presentation.insetInner
                        width += text.layoutSize.width
                        width += presentation.insetOuter
                    } else if !recentPeers.isEmpty {
                        width += presentation.insetInner
                        if recentPeers.count == 1 {
                            width += presentation.reactionSize.width
                            if case .builtin = value.value {
                                width -= 2
                            } else {
                                width += 1
                            }
                        } else if !recentPeers.isEmpty {
                            width += 12 * CGFloat(recentPeers.count)
                            width += 4
                        }
                        width += presentation.insetOuter
                    }
                    if mode == .tag {
                        if text == nil {
                            width += 22
                        } else {
                            width += 16
                        }
                    }
                    
                    var index: Int = 0
                    self.avatars = recentPeers.map { peer in
                        let avatar = Avatar(peer: peer, index: index)
                        index += 1
                        return avatar
                    }
                    self.minimumSize = NSMakeSize(width, height)
                }
            }
        }
        
        public func measure(for width: CGFloat, recommendedSize: NSSize) {
           
        }
        
        private var menu: ContextMenu?
        
        private var reactions: EngineMessageReactionListContext?
        private let avatarDisposable = MetaDisposable()
        
        public func cancelMenu() {
            delayDisposable.set(nil)
            disposable.set(nil)
        }
        
        public func loadMenu() -> ContextMenu? {
            
            let context = self.context
            let tag = self.value.value
            let label = self.text?.attributedString.string
            if message.id.peerId == context.peerId {
                if let menu = menu {
                    return menu
                } else {
                    let menu = ContextMenu()
                    self.menu = menu
                    
                    if context.isPremium {
                        if self.value.value != self.currentTag {
                            menu.addItem(ContextMenuItem(strings().chatReactionContextFilterByTag, handler: { [weak self] in
                                if let `self` = self {
                                    _ = self.action(self.value.value, false)
                                }
                            }, itemImage: MenuAnimation.menu_tag_filter.value))
                        }
                        
                        menu.addItem(ContextMenuItem(label != nil ? strings().chatReactionContextEditTag : strings().chatReactionContextAddLabel, handler: {
                            ChatNavigationHooks.shared.showEditTagLabelObserved(context, tag, label, context.window)
                        }, itemImage: MenuAnimation.menu_tag_rename.value))
                        
                        menu.addItem(ContextSeparatorItem())
                    }
                    
                    menu.addItem(ContextMenuItem(strings().chatReactionContextRemoveTag, handler: { [weak self] in
                        if let `self` = self {
                            self.action(self.value.value, true)
                        }
                    }, itemMode: .destruct, itemImage: MenuAnimation.menu_tag_remove.value))
                    
                    return menu
                }
            }
            
            if let peer = self.message.peers[message.id.peerId] {
                guard peer.isGroup || peer.isSupergroup else {
                    return nil
                }
            }
            

            if !self.canViewList {
                return nil
            }
            if let menu = menu {
                return menu
            } else {
                let menu = ContextMenu()
                self.menu = menu
                let current: EngineMessageReactionListContext
                if let reactions = reactions {
                    current = reactions
                } else {
                    current = context.engine.messages.messageReactionList(message: .init(self.message), readStats: nil, reaction: self.value.value)
                    self.reactions = current
                }
                let signal = current.state |> deliverOnMainQueue
                self.disposable.set((signal).start(next: { [weak self] state in
                    self?.applyState(state)
                }))
                
                return menu
            }
        }
        private var state: EngineMessageReactionListContext.State?
        public func applyState(_ state: EngineMessageReactionListContext.State) {
            self.state = state
            let account = self.context.account
            let context = self.context
            let source: ReactionPeerMenu.Source
            switch self.source {
            case let .builtin(reaction):
                source = .builtin(reaction.staticIcon._parse())
            case let .custom(fileId, file, _):
                source = .custom(fileId, file)
            case let .stars(file, effect):
                source = .stars(file, effect)
            }
            weak let weakSelf = self
            let message = self.message
            let canDeleteReactions = canDeleteReactionsInChat(message: self.message)
            let avatarDisposables = DisposableSet()
            self.avatarDisposable.set(avatarDisposables)
            let makeItem:(_ peer: Peer, _ readTimestamp: Int32?) -> ContextMenuItem = { peer, readTimestamp in
                let title = peer.displayTitle.prefixWithDots(25)
                let item = ReactionPeerMenu(title: title, handler: {
                    weakSelf?.openInfo(peer.id)
                }, peer: peer, context: context, reaction: source, readTimestamp: readTimestamp, message: message, canDelete: canDeleteReactions)
                
                let signal:Signal<(CGImage?, Bool), NoError>
                signal = peerAvatarImage(account: account, photo: .peer(peer, peer.smallProfileImage, peer.namePeerColor, TelegramUtilsHooks.shared.peerLetters(peer), nil, nil), displayDimensions: NSMakeSize(18 * System.backingScale, 18 * System.backingScale), font: .avatar(13), genCap: true, synchronousLoad: false) |> deliverOnMainQueue
                avatarDisposables.add((signal).start(next: { [weak item] image, _ in
                    if let image = image {
                        item?.image = NSImage(cgImage: image, size: NSMakeSize(18, 18))
                    }
                }))
                return item
            }
            menu?.loadMore = { [weak self] in
                guard let self, self.state?.canLoadMore == true else { return }
                self.reactions?.loadMore()
            }
            
            var items = state.items.map {
                return makeItem($0.peer._asPeer(), $0.timestamp)
            }
            
            switch source {
            case let .custom(_, file):
                if let reference = file?.emojiReference {
                    items.append(ContextSeparatorItem())
                    
                    let sources:[ChatMediaStickerPackPreviewSource] = [.emoji(reference)]
                    let text = strings().chatContextMessageContainsEmojiOther(1)
                    
                    let item = MessageContainsPacksMenuItem(title: text, handler: {
                        showModal(with: ChatMediaUIHooks.shared.makeStickerPackPreviewObserved(context, message.id.peerId, sources), for: context.window)
                    }, packs: [reference], context: context)
                    
                    items.append(item)
                }
            default:
                break
            }
            menu?.items = items
        }

        deinit {
            delayDisposable.dispose()
            disposable.dispose()
            avatarDisposable.dispose()
        }
    }
    fileprivate let context: any AccountContextProtocol
    fileprivate let message: Message
    fileprivate let renderType: ChatItemRenderType
    fileprivate let available: AvailableReactions?
    fileprivate let engine: Reactions
    fileprivate let openInfo:(PeerId)->Void
    public let presentation: Theme
    
    public private(set) var size: NSSize = .zero
    fileprivate let reactions: [Reaction]
    private var lines:[[Reaction]] = []
    
    public enum Mode {
        case full
        case tag
    }
    
    public let mode: Mode
    
    
    public init(context: any AccountContextProtocol, message: Message, available: AvailableReactions?, peerAllowed: PeerAllowedReactions?, savedMessageTags: SavedMessageTags?, engine:Reactions, theme: TelegramPresentationTheme, renderType: ChatItemRenderType, currentTag: MessageReaction.Reaction?, isIncoming: Bool, isOutOfBounds: Bool, hasWallpaper: Bool, stateOverlayTextColor: NSColor, reactionPeer: @escaping () -> Peer?, openInfo:@escaping(PeerId)->Void, runEffect: @escaping(MessageReaction.Reaction, Bool)->Void, tagAction:@escaping(MessageReaction.Reaction)->Void, starReact:@escaping()->Void) {
        
        var mode: Mode = .full
        if message.id.peerId == context.peerId {
            mode = .tag
        }
        self.message = message
        self.context = context
        self.renderType = renderType
        self.available = available
        self.engine = engine
        self.mode = mode
        self.openInfo = openInfo
        let presentation: Theme = .Current(theme: theme, renderType: renderType, isIncoming: isIncoming, isOutOfBounds: isOutOfBounds, hasWallpaper: hasWallpaper, stateOverlayTextColor: stateOverlayTextColor, mode: mode, isStars: false)
        self.presentation = presentation
        
        var index: Int = 0
        let getIndex:()->Int = {
            index += 1
            return index
        }
        
        let reactions = message.effectiveReactions(context.peerId, isTags: context.peerId == message.id.peerId)!
        
        var indexes:[MessageReaction.Reaction: Int] = [:]
        if let available = available {
            var index: Int = 0
            for value in available.reactions {
                indexes[value.value] = index
                index += 1
            }
        }
        
        let sorted = reactions.reactions.sorted(by: <)
        
        
        self.reactions = sorted.compactMap { reaction in
            let source: Reaction.Source?
            switch reaction.value {
            case let .custom(fileId):
                let mediaId = MediaId(namespace: Namespaces.Media.CloudFile, id: fileId)
                source = .custom(fileId, message.associatedMedia[mediaId] as? TelegramMediaFile, nil)
            case .builtin:
                if let current = available?.reactions.first(where: { $0.value == reaction.value || reaction.value.isEmpty }) {
                    source = .builtin(current)
                } else {
                    source = nil
                }
            case .stars:
                source = .stars(LocalAnimatedSticker.premium_reaction_6.file, nil)
            }
            
            if let source = source {
                var recentPeers:[Peer] = reactions.recentPeers.filter { recent in
                    return recent.value == reaction.value
                }.compactMap {
                    message.peers[$0.peerId]
                }
                if recentPeers.count < reaction.count {
                    recentPeers = []
                }
                if let peer = message.peers[message.id.peerId], peer.isChannel {
                    recentPeers = []
                }
                if reactions.reactions.reduce(0, { $0 + $1.count }) > 3 {
                    recentPeers = []
                }
                if mode == .tag {
                    recentPeers = []
                }
                
                if message.id.peerId.namespace == Namespaces.Peer.CloudUser {
                    if mode == .full {
                        recentPeers = []
                        if reaction.isSelected {
                            if let peer = context.myPeer {
                                recentPeers.append(peer)
                            }
                            if reaction.count > 1 {
                                if let peer = message.peers[message.id.peerId] {
                                    recentPeers.append(peer)
                                }
                            }
                        } else {
                            if let peer = message.peers[message.id.peerId] {
                                recentPeers.append(peer)
                            }
                        }
                    }
                }
                
                let presentation: Theme = .Current(theme: theme, renderType: renderType, isIncoming: isIncoming, isOutOfBounds: isOutOfBounds, hasWallpaper: hasWallpaper, stateOverlayTextColor: stateOverlayTextColor, mode: mode, isStars: reaction.value == .stars)
                
                return .init(value: reaction, recentPeers: recentPeers, canViewList: reactions.canViewList, message: message, savedMessageTags: savedMessageTags, currentTag: currentTag, context: context, mode: mode, index: getIndex(), source: source, presentation: presentation, action: { value, isFilterTag in
                    if message.id.peerId == context.peerId, !isFilterTag, mode == .tag {
                       tagAction(value)
                    } else {
                        guard let peer = reactionPeer(), canSendReactionsToPeer(EnginePeer(peer)) else {
                            return
                        }
                        if value == .stars {
                            engine.sendStarsReaction(message.id, count: 1)
                        } else {
                            engine.react(message.id, values: ChatHistoryUIHooks.shared.messageNewReactions(message, value.toUpdate(source.file), context.peerId == message.id.peerId))
                        }
                    }
                }, openInfo: openInfo, runEffect: runEffect, starReact: starReact)
            } else {
                return nil
            }
        }
    }
    

    public var lastLineSize: NSSize {
        if let line = lines.last {
            if let lastItem = line.last {
                return NSMakeSize(lastItem.rect.maxX, lastItem.rect.height)
            }
        }
        return .zero
    }
    public var oneLine: Bool {
        return lines.count == 1
    }
    
   
    public func measure(for width: CGFloat) {
                
        var lines:[[Reaction]] = []
        
        var line:[Reaction] = []
        var current: CGFloat = 0
        for reaction in reactions {
            current += reaction.minimumSize.width
            let force: Bool
            if let lastCount = lines.last?.count {
                force = lastCount == line.count
            } else {
                force = false
            }
            if (current - presentation.insetInner > width && !line.isEmpty) || force {
                lines.append(line)
                line.removeAll()
                line.append(reaction)
                current = reaction.minimumSize.width
            } else {
                line.append(reaction)
            }
            current += presentation.insetInner
        }
        if !line.isEmpty {
            lines.append(line)
            line.removeAll()
        }
            
        
        let count = lines.reduce(0, {
            $0 + $1.count
        })
        
        
        
        assert(count == reactions.count)
        
        self.lines = lines
        
        if !lines.isEmpty {
            var point: CGPoint = .zero
            for line in lines {
                for reaction in line {
                    var rect = NSZeroRect
                    rect.origin = point
                    rect.size = reaction.minimumSize
                    point.x += reaction.minimumSize.width + presentation.insetInner
                    reaction.rect = rect
                }
                point.x = 0
                point.y += line.map { $0.minimumSize.height }.max()! + presentation.insetInner
            }
            let max_w = lines.max(by: { lhs, rhs in
                return lhs.last!.rect.maxX < rhs.last!.rect.maxX
            })!.last!.rect.maxX
            self.size = NSMakeSize(max_w, point.y - presentation.insetInner)
        } else {
            self.size = .zero
        }
        
    }
}

private let parsedReactionFiles: Atomic<[MediaId: (TelegramMediaFile.Accessor, TelegramMediaFile)]> = Atomic(value: [:])

private func sharedParsedReactionFile(_ accessor: TelegramMediaFile.Accessor) -> TelegramMediaFile {
    let fileId = accessor.fileId
    if let cached = parsedReactionFiles.with({ $0[fileId] }), cached.0 == accessor {
        return cached.1
    }
    let file = accessor._parse()
    _ = parsedReactionFiles.modify { current in
        var current = current
        if current.count >= 512 {
            current.removeAll()
        }
        current[fileId] = (accessor, file)
        return current
    }
    return file
}

public protocol ReactionViewImpl : AnyObject {
    func update(with reaction: ChatReactionsLayout.Reaction, account: Account, animated: Bool)
    func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition)
    func playEffect()
    
    func getView()-> NSView
    
    func lockVisibility()
    func unlockVisibility()
}

public class AnimationLayerContainer : View {
    fileprivate var imageLayer: InlineStickerItemLayer?
    fileprivate private(set) var isContentPlayable: Bool = false
    fileprivate var contentPlayableUpdated: ((Bool) -> Void)?
    private var isLite: Bool = false
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEventLess = true
    }
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func updateLayer(_ imageLayer: InlineStickerItemLayer, isLite: Bool, animated: Bool) {
        if let layer = self.imageLayer {
            performSublayerRemoval(layer, animated: animated)
        }
        self.isLite = isLite
        imageLayer.superview = superview
        self.layer?.addSublayer(imageLayer)
        if animated && self.imageLayer != nil {
            imageLayer.animateAlpha(from: 0, to: 1, duration: 0.2)
        }
        self.imageLayer = imageLayer
        updateAnimatableContent()
        updateListeners()
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        if let imageLayer = self.imageLayer {
            imageLayer.frame = focus(imageLayer.frame.size)
        }
    }
    
    
    private var animatableContentUpdatePending: Bool = false
    
    @objc public func updateAnimatableContent() -> Void {
        if self.animatableContentUpdatePending {
            return
        }
        if let value = self.imageLayer, value.superview != nil {
            self.animatableContentUpdatePending = true
            DispatchQueue.main.async {
                self.animatableContentUpdatePending = false
                let isLite = self.isLite
                guard let value = self.imageLayer, let superview = value.superview else {
                    return
                }
                var isKeyWindow: Bool = false
                if let window = self.window {
                    if !window.canBecomeKey {
                        isKeyWindow = true
                    } else {
                        isKeyWindow = window.isKeyWindow
                    }
                }
                let isPlayable = !superview.visibleRect.isEmpty && isKeyWindow && !isLite
                value.isPlayable = isPlayable
                if self.isContentPlayable != isPlayable {
                    self.isContentPlayable = isPlayable
                    self.contentPlayableUpdated?(isPlayable)
                }
            }
        }
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.updateListeners()
        self.updateAnimatableContent()
    }
    public override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        self.updateListeners()
        self.updateAnimatableContent()
    }
    
    private let animatableContentObserver = AnimatableContentObserver()

    private func updateListeners() {
        animatableContentObserver.update(for: self, target: self, selector: #selector(updateAnimatableContent), options: [.contentBounds, .documentFrame, .ownFrame])
    }
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

protocol ChatReactionEmojiHost: AnyObject {
    var frame: CGRect { get }
    var isHidden: Bool { get set }
    var isContentPlayable: Bool { get }
    var contentPlayableUpdated: ((Bool) -> Void)? { get set }
    func install(in chip: NSView)
    func setFrame(_ frame: CGRect, transition: ContainedViewLayoutTransition)
    func setOpacityImmediately(_ value: Float)
    func setCornerRadius(_ value: CGFloat)
    func animateAppear()
    func updateLayer(_ layer: InlineStickerItemLayer, isLite: Bool, animated: Bool, host: NSView)
    func updateAnimatableContent()
    var observesOwnVisibility: Bool { get }
}

extension ChatReactionEmojiLayer: ChatReactionEmojiHost {
    func install(in chip: NSView) {
        chip.layer?.addSublayer(self)
    }
    func setFrame(_ frame: CGRect, transition: ContainedViewLayoutTransition) {
        #if DEBUG
        transition.updateFrame(layer: self, frame: frame.offsetBy(dx: ChatRowView.parityEmojiMutation, dy: 0))
        #else
        transition.updateFrame(layer: self, frame: frame)
        #endif
        layoutImage()
        updateAnimatableContent()
    }
    func setOpacityImmediately(_ value: Float) {
        removeAnimation(forKey: "opacity")
        opacity = value
    }
    func setCornerRadius(_ value: CGFloat) {
        cornerRadius = value
    }
    func animateAppear() {
        animateScaleCenter(from: 0.1, to: 1, duration: 0.2)
    }
    var observesOwnVisibility: Bool { false }
}

protocol ChatReactionAvatarHost: AnyObject {
    var hostLayer: CALayer? { get }
    var origin: NSPoint { get }
    func setOrigin(_ origin: NSPoint)
    func updateLayout(size: CGSize, isClipped: Bool, animated: Bool)
    func removeFromContainer()
}

extension AvatarContentView: ChatReactionAvatarHost {
    var hostLayer: CALayer? { layer }
    var origin: NSPoint { frame.origin }
    func setOrigin(_ origin: NSPoint) { setFrameOrigin(origin) }
    func removeFromContainer() { removeFromSuperview() }
}

extension AvatarContentLayer: ChatReactionAvatarHost {
    var hostLayer: CALayer? { self }
    var origin: NSPoint { frame.origin }
    func setOrigin(_ origin: NSPoint) { frame.origin = origin }
    func removeFromContainer() { removeFromSuperlayer() }
}

enum ChatReactionAvatarsContainer {
    case view(View)
    case layer(SimpleLayer)

    static func make(in chip: NSView) -> ChatReactionAvatarsContainer {
        let frame = NSMakeRect(0, 0, 24 * 3, 24)
        if ChatRowView.usesLegacyRowChrome {
            let container = View(frame: frame)
            container.isEventLess = true
            chip.addSubview(container)
            return .view(container)
        }
        let container = SimpleLayer()
        ChatReactionAvatarsContainer.mirrorViewLayer(container)
        container.frame = frame
        chip.layer?.addSublayer(container)
        return .layer(container)
    }

    static func make(inLayer parent: CALayer) -> ChatReactionAvatarsContainer {
        let container = SimpleLayer()
        ChatReactionAvatarsContainer.mirrorViewLayer(container)
        container.frame = NSMakeRect(0, 0, 24 * 3, 24)
        parent.addSublayer(container)
        return .layer(container)
    }

    static func mirrorViewLayer(_ layer: CALayer) {
        layer.anchorPoint = .zero
        layer.masksToBounds = true
        layer.isOpaque = true
        layer.edgeAntialiasingMask = []
        if #available(macOS 10.15, *) {
            layer.cornerCurve = .continuous
        }
    }

    var frame: CGRect {
        switch self {
        case let .view(view): return view.frame
        case let .layer(layer): return layer.frame
        }
    }

    func makeAvatar(context: any AccountContextProtocol, peer: Peer, message: Message?, size: NSSize) -> ChatReactionAvatarHost {
        switch self {
        case .view:
            let control = AvatarContentView(context: context, peer: peer, message: message, synchronousLoad: false, size: size, inset: 6)
            control.userInteractionEnabled = false
            return control
        case .layer:
            let control = AvatarContentLayer(context: context, peer: peer, message: message, synchronousLoad: false, size: size, inset: 6)
            control.animatesClipChanges = true
            ChatReactionAvatarsContainer.mirrorViewLayer(control)
            return control
        }
    }

    func insert(_ avatar: ChatReactionAvatarHost, at index: Int, size: NSSize, origin: NSPoint) {
        switch self {
        case let .view(view):
            guard let control = avatar as? AvatarContentView else { return }
            control.setFrameSize(size)
            control.setFrameOrigin(origin)
            view.subviews.insert(control, at: index)
        case let .layer(layer):
            guard let control = avatar as? AvatarContentLayer else { return }
            control.frame = CGRect(origin: origin, size: size)
            layer.insertSublayer(control, at: UInt32(index))
        }
    }

    var ordered: [ChatReactionAvatarHost] {
        switch self {
        case let .view(view): return view.subviews.compactMap { $0 as? AvatarContentView }
        case let .layer(layer): return layer.sublayers?.compactMap { $0 as? AvatarContentLayer } ?? []
        }
    }

    func updateFrame(_ frame: CGRect, transition: ContainedViewLayoutTransition) {
        switch self {
        case let .view(view): transition.updateFrame(view: view, frame: frame)
        case let .layer(layer):
            #if DEBUG
            transition.updateFrame(layer: layer, frame: frame.offsetBy(dx: ChatRowView.parityAvatarMutation, dy: 0))
            #else
            transition.updateFrame(layer: layer, frame: frame)
            #endif
        }
    }
}

final class ChatReactionEmojiViewHost: ChatReactionEmojiHost {
    let view = AnimationLayerContainer(frame: NSMakeRect(0, 0, 16, 16))
    var frame: CGRect { view.frame }
    var isHidden: Bool {
        get { view.isHidden }
        set { view.isHidden = newValue }
    }
    var isContentPlayable: Bool { view.isContentPlayable }
    var contentPlayableUpdated: ((Bool) -> Void)? {
        get { view.contentPlayableUpdated }
        set { view.contentPlayableUpdated = newValue }
    }
    func install(in chip: NSView) {
        chip.addSubview(view)
    }
    func setFrame(_ frame: CGRect, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: view, frame: frame)
    }
    func setOpacityImmediately(_ value: Float) {
        view._change(opacity: CGFloat(value), animated: false)
    }
    func setCornerRadius(_ value: CGFloat) {
        view.layer?.cornerRadius = value
    }
    func animateAppear() {
        view.layer?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2)
    }
    func updateLayer(_ layer: InlineStickerItemLayer, isLite: Bool, animated: Bool, host: NSView) {
        view.updateLayer(layer, isLite: isLite, animated: animated)
    }
    func updateAnimatableContent() {
        view.updateAnimatableContent()
    }
    var observesOwnVisibility: Bool { true }
}

fileprivate protocol ReactionChipElement: ReactionViewImpl {
    var chipFrame: NSRect { get set }
    var chipLayer: CALayer? { get }
    func chipReaction(in mode: ChatReactionsLayout.Mode) -> ChatReactionsLayout.Reaction?
    func chipIsReusable(in mode: ChatReactionsLayout.Mode) -> Bool
    func chipCancelPendingEffect()
    func install(in container: ChatReactionsView)
    func removeFromContainer(_ container: ChatReactionsView, animated: Bool)
    func updateChipFrame(_ frame: NSRect, transition: ContainedViewLayoutTransition)
}

final class ChatReactionsView : ChatLayerSceneView {
    
    
    public final class ReactionView: Control, ReactionViewImpl {
        fileprivate private(set) var reaction: ChatReactionsLayout.Reaction?
        fileprivate var isReusable: Bool {
            return self.effetView == nil && !self.imageView.isHidden
        }
        fileprivate func cancelPendingEffect() {
            self.effectDisposable.set(nil)
        }
        fileprivate let imageView: ChatReactionEmojiHost = {
            if ChatRowView.usesLegacyRowChrome {
                return ChatReactionEmojiViewHost()
            }
            let layer = ChatReactionEmojiLayer()
            layer.frame = NSMakeRect(0, 0, 16, 16)
            return layer
        }()
        private var emojiAnchor: View?
        private let emojiObserver = AnimatableContentObserver()
        private var textLayer: ChatReactionTextLayer?
        private var avatarsContainer: ChatReactionAvatarsContainer?
        private var avatars:[ChatReactionAvatarHost] = []
        private var peers:[Avatar] = []
        private var first: Bool = true
        private var backgroundLayer: SimpleLayer?
        
        private var effetView: LottiePlayerView?
        private let effectDisposable = MetaDisposable()
        
        private var starButtonEffect: StarsButtonEffectLayer?
        
        
        private var starKeyHandler: UInt32?
        
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            
            imageView.install(in: self)
            scaleOnClick = true
            imageView.contentPlayableUpdated = { [weak self] isPlayable in
                self?.starButtonEffect?.isPlaying = isPlayable
            }
            
            self.layer?.masksToBounds = false
            
            self.set(handler: { [weak self] _ in
                if let reaction = self?.reaction {
                    reaction.action(reaction.value.value, false)
                }
            }, for: .Click)
            
            
            self.contextMenu = { [weak self] in
                if let reaction = self?.reaction {
                    return reaction.loadMenu()
                }
                return nil
            }
            
            self.set(handler: { [weak self] _ in
                if let reaction = self?.reaction, reaction.value.value == .stars {
                    reaction.starReact()
                }
            }, for: .LongMouseDown)
            
            
            self.set(handler: { [weak self] _ in
                self?.reaction?.cancelMenu()
            }, for: .Normal)
                        
        }
        
        public override var sendRightMouseAnyway: Bool {
            if let _ = reaction, reaction?.value.value == .stars {
                return false
            } else {
                return true
            }
        }
        
        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            textLayer?.updateScale(backingScaleFactor)
            updateEmojiListeners()
            imageView.updateAnimatableContent()
        }

        @objc private func updateEmojiVisibility() {
            imageView.updateAnimatableContent()
        }

        private func updateEmojiListeners() {
            guard !imageView.observesOwnVisibility else { return }
            emojiObserver.update(for: self, target: self, selector: #selector(updateEmojiVisibility), options: [.contentBounds, .documentFrame, .ownFrame])
        }

        public override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            textLayer?.updateScale(backingScaleFactor)
        }

        public override func accessibilityChildren() -> [Any]? {
            let children = super.accessibilityChildren() ?? []
            guard let child = textLayer?.accessibleChild() else { return children }
            return children + [child]
        }

        public override func accessibilityHitTest(_ point: NSPoint) -> Any? {
            return textLayer?.accessibilityHit(at: point) ?? super.accessibilityHitTest(point)
        }
        public override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            updateEmojiListeners()
            imageView.updateAnimatableContent()
        }
        
        public func playEffect() {
            let size: NSSize
            
            guard let reaction = reaction, let file = reaction.effectFile, self.effetView == nil else {
                return
            }
            
            switch reaction.value.value {
            case .stars:
                size = NSMakeSize(imageView.frame.width + 4, imageView.frame.height + 4)
            default:
                size = NSMakeSize(imageView.frame.width * 2, imageView.frame.height * 2)
            }
            
            if TelegramUtilsHooks.shared.isLite(.emoji_effects) {
                return
            }

            let fileSignal: Signal<MediaResourceData, NoError>
            if let resource = file.resource as? LocalBundleResource, let path = resource.path {
                fileSignal = .single(MediaResourceData(path: path, offset: 0, size: 0, complete: true))
            } else {
                fileSignal = reaction.context.account.postbox.mediaBox.resourceData(file.resource, attemptSynchronously: true)
            }
            let signal: Signal<LottieAnimation?, NoError> = fileSignal
            |> filter { $0.complete }
            |> map { value -> Data? in
                return try? Data(contentsOf: URL(fileURLWithPath: value.path))
            }
            |> filter {
                $0 != nil
            }
            |> map {
                $0!
            }
            |> take(1)
            |> map { data in
                return LottieAnimation(compressed: data, key: .init(key: .bundle("_effect_\(reaction.value.value)"), size: size), cachePurpose: .none, playPolicy: .once, metalSupport: false)
            } |> deliverOnMainQueue

            self.effectDisposable.set(signal.start(next: { [weak self] animation in
                if let animation = animation {
                    self?.runAnimationEffect(animation)
                }
            }))
            
        }
        
        private func runAnimationEffect(_ animation: LottieAnimation) {
            
            guard let reaction = self.reaction else {
                return
            }
            
            let point: NSPoint
            switch reaction.value.value {
            case .stars:
                point = self.imageView.frame.origin.offsetBy(dx: -2, dy: -2)
            default:
                point = NSMakePoint(2, -3)
            }
            
            let player = LottiePlayerView(frame: CGRect(origin: point, size: animation.size))

            
            
            player.set(animation, reset: true)
            
            self.effetView = player
            
            addSubview(player)
            
            
            self.imageView.setOpacityImmediately(0)
            
            animation.triggerOn = (LottiePlayerTriggerFrame.last, { [weak self, weak player] in
                self?.imageView.setOpacityImmediately(1)
                if let player = player {
                    performSubviewRemoval(player, animated: false)
                    if self?.effetView == player {
                        self?.effetView = nil
                    }
                }
            }, {})
        }
        
        public func update(with reaction: ChatReactionsLayout.Reaction, account: Account, animated: Bool) {
            let layerUpdated = reaction.source != self.reaction?.source
            let selectedUpdated = self.reaction?.value.isSelected != reaction.value.isSelected
            let reactionUpdated = self.reaction?.value.value != reaction.value.value
            self.reaction = reaction
            self.layer?.cornerRadius = reaction.rect.height / 2
            
            let tooltip = reaction.avatars.map { $0.peer.displayTitle }.joined(separator: ", ")
            
            if tooltip.isEmpty {
                self.toolTip = "\(reaction.value.count.formattedWithSeparator)"
            } else {
                self.toolTip = tooltip
            }
            
            self.imageView.setCornerRadius(reaction.value.value.string == "" ? 4 : 0)
            
            let presentation = reaction.presentation
            
            if let text = reaction.text {
                let current: ChatReactionTextLayer
                if let layer = self.textLayer {
                    current = layer
                } else {
                    current = ChatReactionTextLayer()
                    current.frame = CGRect(origin: NSMakePoint(presentation.insetOuter + presentation.reactionSize.width + presentation.insetInner, (frame.height - text.layoutSize.height) / 2), size: text.layoutSize)
                    self.textLayer = current
                }
                current.update(text, in: self)
            } else if let layer = self.textLayer {
                layer.remove(animated: animated)
                self.textLayer = nil
            }
            
            
            let (removed, inserted, updated) = mergeListsStableWithUpdates(leftList: self.peers, rightList: reaction.avatars)
            
            let size = reaction.presentation.reactionSize
            
            for removed in removed.reversed() {
                let control = avatars.remove(at: removed)
                let peer = self.peers[removed]
                let haveNext = reaction.avatars.contains(where: { $0.stableId == peer.stableId })
                control.updateLayout(size: size, isClipped: false, animated: animated)
                if animated && !haveNext {
                    control.hostLayer?.animateAlpha(from: 1, to: 0, duration: 0.2, timingFunction: .easeOut, removeOnCompletion: false, completion: { [weak control] _ in
                        control?.removeFromContainer()
                    })
                    control.hostLayer?.animateScaleSpring(from: 1.0, to: 0.2, duration: 0.2)
                } else {
                    control.removeFromContainer()
                }
            }
            let avatarSize = reaction.presentation.avatarSize
            if !inserted.isEmpty, avatarsContainer == nil {
                avatarsContainer = ChatReactionAvatarsContainer.make(in: self)
            }
            if let avatarsContainer {
                for inserted in inserted {
                    let control = avatarsContainer.makeAvatar(context: reaction.context, peer: inserted.1.peer, message: reaction.message, size: avatarSize)
                    control.updateLayout(size: avatarSize, isClipped: inserted.0 != 0, animated: animated)
                    let origin = NSMakePoint(CGFloat(inserted.0) * 12, 0)
                    avatars.insert(control, at: inserted.0)
                    avatarsContainer.insert(control, at: inserted.0, size: avatarSize, origin: origin)
                    if animated {
                        if let index = inserted.2 {
                            control.hostLayer?.animatePosition(from: NSMakePoint(CGFloat(index) * 12, 0), to: origin, duration: 0.2, timingFunction: .easeOut)
                        } else {
                            control.hostLayer?.animateAlpha(from: 0, to: 1, duration: 0.2, timingFunction: .easeOut)
                            control.hostLayer?.animateScaleSpring(from: 0.2, to: 1.0, duration: 0.2)
                        }
                    }
                }
            }
            for updated in updated {
                let control = avatars[updated.0]
                control.updateLayout(size: avatarSize, isClipped: updated.0 != 0, animated: animated)
                let updatedPoint = NSMakePoint(CGFloat(updated.0) * 12, 0)
                if animated {
                    control.hostLayer?.animatePosition(from: control.origin - updatedPoint, to: .zero, duration: 0.2, timingFunction: .easeOut, additive: true)
                }
                control.setOrigin(updatedPoint)
            }
            var index: CGFloat = 10
            for control in avatarsContainer?.ordered ?? [] {
                control.hostLayer?.zPosition = index
                index -= 1
            }
            
            self.peers = reaction.avatars
            
            self.backgroundColor = reaction.presentation.bgColor
            
 

            
            if selectedUpdated {
                if reaction.value.isSelected {
                    let background = SimpleLayer()
                    background.anchorPoint = layer?.anchorPoint ?? .zero
                    background.isGeometryFlipped = layer?.isGeometryFlipped ?? false
                    background.frame = bounds
                    background.cornerRadius = background.frame.height / 2
                    background.isOpaque = true
                    background.edgeAntialiasingMask = []
                    if #available(macOS 10.15, *) { background.cornerCurve = .continuous }
                    self.backgroundLayer = background
                    layer?.insertSublayer(background, at: 0)
                    
                    if animated {
                        background.animateScaleSpring(from: 0.1, to: 1, duration: 0.3)
                        background.animateAlpha(from: 0, to: 1, duration: 0.2)
                    }
                } else {
                    if let layer = backgroundLayer {
                        if animated {
                            let opacity = layer.presentation()?.opacity ?? layer.opacity
                            layer.animateAlpha(from: CGFloat(opacity), to: 0, duration: 0.2, timingFunction: .easeOut, removeOnCompletion: false, completion: { [weak layer] _ in
                                layer?.removeFromSuperlayer()
                            })
                            layer.animateScaleCenter(from: 1, to: 0.01, duration: 0.2, removeOnCompletion: false, timingFunction: .easeOut)
                        } else {
                            layer.removeFromSuperlayer()
                        }
                        self.backgroundLayer = nil
                    }
                }
            }

            self.backgroundLayer?.backgroundColor = reaction.presentation.selectedColor.cgColor

            
            if case .stars = reaction.value.value {
                let current: StarsButtonEffectLayer
                if let layer = self.starButtonEffect {
                    current = layer
                } else {
                    current = StarsButtonEffectLayer()
                    current.isPlaying = self.imageView.isContentPlayable
                    self.starButtonEffect = current
                }
                let rect = reaction.rect.size.bounds.insetBy(dx: -5, dy: -5)
                current.frame = rect
                current.update(size: rect.size)
                
                if let backgroundLayer {
                    backgroundLayer.addSublayer(current)
                } else {
                    self.layer?.addSublayer(current)
                }
            } else if let starButtonEffect {
                performSublayerRemoval(starButtonEffect, animated: animated)
                self.starButtonEffect = nil
            }
            
            
            if case .stars = reaction.value.value {
                if self.starKeyHandler == nil {
                    self.starKeyHandler = self.set(handler: { [weak self] _ in
                        self?.reaction?.starReact()
                    }, for: .RightDown)
                }
            } else if let starKeyHandler {
                self.starKeyHandler = nil
                self.removeHandler(starKeyHandler)
            }
            
            if animated {
                self.layer?.animateBorder()
                self.layer?.animateBackground()
            }
            
            if !first, reactionUpdated, animated {
                self.imageView.animateAppear()
            }

            if first {
                updateLayout(size: reaction.rect.size, transition: .immediate)
                first = false
            }

            if layerUpdated {
                self.imageView.updateLayer(reaction.getInlineLayer(reaction.mode), isLite: TelegramUtilsHooks.shared.isLite(.emoji), animated: animated, host: self)
            }
        }
        
        deinit {
            effectDisposable.dispose()
        }
        
        public func isOwner(of reaction: ChatReactionsLayout.Reaction) -> Bool {
            return self.reaction?.value.value == reaction.value.value
        }
        
        public func getView() -> NSView {
            if let legacy = imageView as? ChatReactionEmojiViewHost {
                return legacy.view
            }
            let anchor: View
            if let emojiAnchor {
                anchor = emojiAnchor
            } else {
                anchor = View(frame: imageView.frame)
                anchor.isEventLess = true
                anchor.backgroundColor = .clear
                emojiAnchor = anchor
                addSubview(anchor)
            }
            if anchor.frame != imageView.frame {
                anchor.frame = imageView.frame
            }
            return anchor
        }
        
        public func lockVisibility() {
            self.imageView.isHidden = true
        }
        public func unlockVisibility() {
            self.imageView.isHidden = false
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
            guard let reaction = reaction else {
                return
            }
            
            if let backgroundLayer {
                transition.updateFrame(layer: backgroundLayer, frame: size.bounds)
            }
            
            
            let presentation = reaction.presentation
            
            var reactionSize = presentation.reactionSize
            
            if case .custom = reaction.value.value {
                reactionSize.width += 3
                reactionSize.height += 3
            }
            
            let emojiFrame = CGRect(origin: NSMakePoint(presentation.insetOuter, (size.height - reactionSize.height) / 2), size: reactionSize)
            self.imageView.setFrame(emojiFrame, transition: transition)
            if let emojiAnchor, emojiAnchor.frame != emojiFrame {
                emojiAnchor.frame = emojiFrame
            }
            
            
            if let textLayer = textLayer, let text = reaction.text {
                let center = focus(text.layoutSize)
                textLayer.updateFrame(CGRect(origin: NSMakePoint(self.imageView.frame.maxX + presentation.insetInner, center.minY), size: text.layoutSize), transition: transition)
            }
            
            if let avatarsContainer {
                let center = focus(presentation.avatarSize)
                avatarsContainer.updateFrame(CGRect(origin: NSMakePoint(self.imageView.frame.maxX + presentation.insetInner, center.minY), size: avatarsContainer.frame.size), transition: transition)
            }
            
        }
        public override func layout() {
            super.layout()
            updateLayout(size: frame.size, transition: .immediate)
        }
    }
    
    final class ReactionChip: NSObject, ReactionViewImpl {
        let node: ChatLayerControlNode
        fileprivate private(set) var reaction: ChatReactionsLayout.Reaction?
        fileprivate weak var container: ChatReactionsView?
        fileprivate var isReusable: Bool {
            return self.effetView == nil && !self.emoji.isHidden
        }
        fileprivate func cancelPendingEffect() {
            self.effectDisposable.set(nil)
        }
        private let emoji: ChatReactionEmojiLayer = {
            let layer = ChatReactionEmojiLayer()
            layer.frame = NSMakeRect(0, 0, 16, 16)
            return layer
        }()
        private var emojiAnchor: View?
        private let emojiObserver = AnimatableContentObserver()
        private var textLayer: ChatReactionTextLayer?
        private var avatarsContainer: ChatReactionAvatarsContainer?
        private var avatars:[ChatReactionAvatarHost] = []
        private var peers:[Avatar] = []
        private var first: Bool = true
        private var backgroundLayer: SimpleLayer?

        private var effetView: LottiePlayerView?
        private let effectDisposable = MetaDisposable()

        private var starButtonEffect: StarsButtonEffectLayer?

        private var starKeyHandler: UInt32?

        init(id: AnyHashable, frame: NSRect) {
            self.node = ChatLayerControlNode(id: id)
            super.init()
            let layer = node.layer
            layer.masksToBounds = false
            layer.isOpaque = true
            if #available(macOS 10.15, *) {
                layer.cornerCurve = .continuous
            }
            node.frame = frame
            layer.addSublayer(emoji)
            node.scaleOnClick = true
            node.accessibilityRole = .button
            emoji.contentPlayableUpdated = { [weak self] isPlayable in
                self?.starButtonEffect?.isPlaying = isPlayable
            }

            node.set(handler: { [weak self] _ in
                if let reaction = self?.reaction {
                    reaction.action(reaction.value.value, false)
                }
            }, for: .Click)

            node.contextMenu = { [weak self] in
                if let reaction = self?.reaction {
                    return reaction.loadMenu()
                }
                return nil
            }

            node.set(handler: { [weak self] _ in
                if let reaction = self?.reaction, reaction.value.value == .stars {
                    reaction.starReact()
                }
            }, for: .LongMouseDown)

            node.set(handler: { [weak self] _ in
                self?.reaction?.cancelMenu()
            }, for: .Normal)

            node.onAccessibilityPress = { [weak self] in
                guard let reaction = self?.reaction else { return false }
                reaction.action(reaction.value.value, false)
                return true
            }
        }

        private var frame: NSRect { node.frame }
        private var hostScale: CGFloat { container?.backingScaleFactor ?? System.backingScale }

        fileprivate func hostDidMoveToWindow() {
            textLayer?.updateScale(hostScale)
            updateEmojiListeners()
            emoji.updateAnimatableContent()
        }

        fileprivate func hostDidChangeBackingProperties() {
            textLayer?.updateScale(hostScale)
        }

        @objc private func updateEmojiVisibility() {
            emoji.updateAnimatableContent()
        }

        private func updateEmojiListeners() {
            guard let container else { return }
            emojiObserver.update(for: container, target: self, selector: #selector(updateEmojiVisibility), options: [.contentBounds, .documentFrame, .ownFrame])
        }

        public func playEffect() {
            let size: NSSize

            guard let reaction = reaction, let file = reaction.effectFile, self.effetView == nil else {
                return
            }

            switch reaction.value.value {
            case .stars:
                size = NSMakeSize(emoji.frame.width + 4, emoji.frame.height + 4)
            default:
                size = NSMakeSize(emoji.frame.width * 2, emoji.frame.height * 2)
            }

            if TelegramUtilsHooks.shared.isLite(.emoji_effects) {
                return
            }

            let fileSignal: Signal<MediaResourceData, NoError>
            if let resource = file.resource as? LocalBundleResource, let path = resource.path {
                fileSignal = .single(MediaResourceData(path: path, offset: 0, size: 0, complete: true))
            } else {
                fileSignal = reaction.context.account.postbox.mediaBox.resourceData(file.resource, attemptSynchronously: true)
            }
            let signal: Signal<LottieAnimation?, NoError> = fileSignal
            |> filter { $0.complete }
            |> map { value -> Data? in
                return try? Data(contentsOf: URL(fileURLWithPath: value.path))
            }
            |> filter {
                $0 != nil
            }
            |> map {
                $0!
            }
            |> take(1)
            |> map { data in
                return LottieAnimation(compressed: data, key: .init(key: .bundle("_effect_\(reaction.value.value)"), size: size), cachePurpose: .none, playPolicy: .once, metalSupport: false)
            } |> deliverOnMainQueue

            self.effectDisposable.set(signal.start(next: { [weak self] animation in
                if let animation = animation {
                    self?.runAnimationEffect(animation)
                }
            }))
        }

        private func runAnimationEffect(_ animation: LottieAnimation) {
            guard let reaction = self.reaction, let container else {
                return
            }

            let point: NSPoint
            switch reaction.value.value {
            case .stars:
                point = self.emoji.frame.origin.offsetBy(dx: -2, dy: -2)
            default:
                point = NSMakePoint(2, -3)
            }

            let player = LottiePlayerView(frame: CGRect(origin: point.offsetBy(dx: frame.minX, dy: frame.minY), size: animation.size))

            player.set(animation, reset: true)

            self.effetView = player

            player.isEventLess = true
            container.addSubview(player)
            player.layer?.zPosition = 10

            self.emoji.setOpacityImmediately(0)

            animation.triggerOn = (LottiePlayerTriggerFrame.last, { [weak self, weak player] in
                self?.emoji.setOpacityImmediately(1)
                if let player = player {
                    performSubviewRemoval(player, animated: false)
                    if self?.effetView == player {
                        self?.effetView = nil
                    }
                }
            }, {})
        }

        public func update(with reaction: ChatReactionsLayout.Reaction, account: Account, animated: Bool) {
            let layerUpdated = reaction.source != self.reaction?.source
            let selectedUpdated = self.reaction?.value.isSelected != reaction.value.isSelected
            let reactionUpdated = self.reaction?.value.value != reaction.value.value
            self.reaction = reaction
            let layer = node.layer
            layer.cornerRadius = reaction.rect.height / 2
            node.sendRightMouseAnyway = reaction.value.value != .stars

            let tooltip = reaction.avatars.map { $0.peer.displayTitle }.joined(separator: ", ")

            if tooltip.isEmpty {
                node.toolTip = "\(reaction.value.count.formattedWithSeparator)"
            } else {
                node.toolTip = tooltip
            }
            node.accessibilityLabel = node.toolTip

            self.emoji.setCornerRadius(reaction.value.value.string == "" ? 4 : 0)

            let presentation = reaction.presentation

            if let text = reaction.text, let container {
                let current: ChatReactionTextLayer
                if let layer = self.textLayer {
                    current = layer
                } else {
                    current = ChatReactionTextLayer()
                    current.frame = CGRect(origin: NSMakePoint(presentation.insetOuter + presentation.reactionSize.width + presentation.insetInner, (frame.height - text.layoutSize.height) / 2), size: text.layoutSize)
                    self.textLayer = current
                }
                current.update(text, in: container, parent: layer)
            } else if let layer = self.textLayer {
                layer.remove(animated: animated)
                self.textLayer = nil
            }

            let (removed, inserted, updated) = mergeListsStableWithUpdates(leftList: self.peers, rightList: reaction.avatars)

            let size = reaction.presentation.reactionSize

            for removed in removed.reversed() {
                let control = avatars.remove(at: removed)
                let peer = self.peers[removed]
                let haveNext = reaction.avatars.contains(where: { $0.stableId == peer.stableId })
                control.updateLayout(size: size, isClipped: false, animated: animated)
                if animated && !haveNext {
                    control.hostLayer?.animateAlpha(from: 1, to: 0, duration: 0.2, timingFunction: .easeOut, removeOnCompletion: false, completion: { [weak control] _ in
                        control?.removeFromContainer()
                    })
                    control.hostLayer?.animateScaleSpring(from: 1.0, to: 0.2, duration: 0.2)
                } else {
                    control.removeFromContainer()
                }
            }
            let avatarSize = reaction.presentation.avatarSize
            if !inserted.isEmpty, avatarsContainer == nil {
                avatarsContainer = ChatReactionAvatarsContainer.make(inLayer: layer)
            }
            if let avatarsContainer {
                for inserted in inserted {
                    let control = avatarsContainer.makeAvatar(context: reaction.context, peer: inserted.1.peer, message: reaction.message, size: avatarSize)
                    control.updateLayout(size: avatarSize, isClipped: inserted.0 != 0, animated: animated)
                    let origin = NSMakePoint(CGFloat(inserted.0) * 12, 0)
                    avatars.insert(control, at: inserted.0)
                    avatarsContainer.insert(control, at: inserted.0, size: avatarSize, origin: origin)
                    if animated {
                        if let index = inserted.2 {
                            control.hostLayer?.animatePosition(from: NSMakePoint(CGFloat(index) * 12, 0), to: origin, duration: 0.2, timingFunction: .easeOut)
                        } else {
                            control.hostLayer?.animateAlpha(from: 0, to: 1, duration: 0.2, timingFunction: .easeOut)
                            control.hostLayer?.animateScaleSpring(from: 0.2, to: 1.0, duration: 0.2)
                        }
                    }
                }
            }
            for updated in updated {
                let control = avatars[updated.0]
                control.updateLayout(size: avatarSize, isClipped: updated.0 != 0, animated: animated)
                let updatedPoint = NSMakePoint(CGFloat(updated.0) * 12, 0)
                if animated {
                    control.hostLayer?.animatePosition(from: control.origin - updatedPoint, to: .zero, duration: 0.2, timingFunction: .easeOut, additive: true)
                }
                control.setOrigin(updatedPoint)
            }
            var index: CGFloat = 10
            for control in avatarsContainer?.ordered ?? [] {
                control.hostLayer?.zPosition = index
                index -= 1
            }

            self.peers = reaction.avatars

            let bgColor = reaction.presentation.bgColor.cgColor
            if layer.backgroundColor != bgColor {
                layer.backgroundColor = bgColor
            }

            if selectedUpdated {
                if reaction.value.isSelected {
                    let background = SimpleLayer()
                    background.anchorPoint = layer.anchorPoint
                    background.isGeometryFlipped = layer.isGeometryFlipped
                    background.frame = layer.bounds
                    background.cornerRadius = background.frame.height / 2
                    background.isOpaque = true
                    background.edgeAntialiasingMask = []
                    if #available(macOS 10.15, *) { background.cornerCurve = .continuous }
                    self.backgroundLayer = background
                    layer.insertSublayer(background, at: 0)

                    if animated {
                        background.animateScaleSpring(from: 0.1, to: 1, duration: 0.3)
                        background.animateAlpha(from: 0, to: 1, duration: 0.2)
                    }
                } else {
                    if let layer = backgroundLayer {
                        if animated {
                            let opacity = layer.presentation()?.opacity ?? layer.opacity
                            layer.animateAlpha(from: CGFloat(opacity), to: 0, duration: 0.2, timingFunction: .easeOut, removeOnCompletion: false, completion: { [weak layer] _ in
                                layer?.removeFromSuperlayer()
                            })
                            layer.animateScaleCenter(from: 1, to: 0.01, duration: 0.2, removeOnCompletion: false, timingFunction: .easeOut)
                        } else {
                            layer.removeFromSuperlayer()
                        }
                        self.backgroundLayer = nil
                    }
                }
            }

            self.backgroundLayer?.backgroundColor = reaction.presentation.selectedColor.cgColor

            if case .stars = reaction.value.value {
                let current: StarsButtonEffectLayer
                if let layer = self.starButtonEffect {
                    current = layer
                } else {
                    current = StarsButtonEffectLayer()
                    current.isPlaying = self.emoji.isContentPlayable
                    self.starButtonEffect = current
                }
                let rect = reaction.rect.size.bounds.insetBy(dx: -5, dy: -5)
                current.frame = rect
                current.update(size: rect.size)

                if let backgroundLayer {
                    backgroundLayer.addSublayer(current)
                } else {
                    layer.addSublayer(current)
                }
            } else if let starButtonEffect {
                performSublayerRemoval(starButtonEffect, animated: animated)
                self.starButtonEffect = nil
            }

            if case .stars = reaction.value.value {
                if self.starKeyHandler == nil {
                    self.starKeyHandler = node.set(handler: { [weak self] _ in
                        self?.reaction?.starReact()
                    }, for: .RightDown)
                }
            } else if let starKeyHandler {
                self.starKeyHandler = nil
                node.removeHandler(starKeyHandler)
            }

            if animated {
                layer.animateBorder()
                layer.animateBackground()
            }

            if !first, reactionUpdated, animated {
                self.emoji.animateAppear()
            }

            if first {
                updateLayout(size: reaction.rect.size, transition: .immediate)
                first = false
            }

            if layerUpdated, let container {
                self.emoji.updateLayer(reaction.getInlineLayer(reaction.mode), isLite: TelegramUtilsHooks.shared.isLite(.emoji), animated: animated, host: container)
            }
        }

        deinit {
            effectDisposable.dispose()
        }

        public func getView() -> NSView {
            let anchor: View
            if let emojiAnchor {
                anchor = emojiAnchor
            } else {
                anchor = View(frame: anchorFrame)
                anchor.isEventLess = true
                anchor.backgroundColor = .clear
                emojiAnchor = anchor
                container?.addSubview(anchor)
            }
            if anchor.frame != anchorFrame {
                anchor.frame = anchorFrame
            }
            return anchor
        }

        private var anchorFrame: NSRect {
            return emoji.frame.offsetBy(dx: frame.minX, dy: frame.minY)
        }

        public func lockVisibility() {
            self.emoji.isHidden = true
        }
        public func unlockVisibility() {
            self.emoji.isHidden = false
        }

        public func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
            guard let reaction = reaction else {
                return
            }

            if let backgroundLayer {
                transition.updateFrame(layer: backgroundLayer, frame: size.bounds)
            }

            let presentation = reaction.presentation

            var reactionSize = presentation.reactionSize

            if case .custom = reaction.value.value {
                reactionSize.width += 3
                reactionSize.height += 3
            }

            let emojiFrame = CGRect(origin: NSMakePoint(presentation.insetOuter, (size.height - reactionSize.height) / 2), size: reactionSize)
            self.emoji.setFrame(emojiFrame, transition: transition)
            if let emojiAnchor, emojiAnchor.frame != anchorFrame {
                emojiAnchor.frame = anchorFrame
            }

            let bounds = NSRect(origin: .zero, size: size)
            if let textLayer = textLayer, let text = reaction.text {
                let center = bounds.focus(text.layoutSize)
                textLayer.updateFrame(CGRect(origin: NSMakePoint(self.emoji.frame.maxX + presentation.insetInner, center.minY), size: text.layoutSize), transition: transition)
            }

            if let avatarsContainer {
                let center = bounds.focus(presentation.avatarSize)
                avatarsContainer.updateFrame(CGRect(origin: NSMakePoint(self.emoji.frame.maxX + presentation.insetInner, center.minY), size: avatarsContainer.frame.size), transition: transition)
            }
        }

        fileprivate func removeAnchors() {
            emojiAnchor?.removeFromSuperview()
            emojiAnchor = nil
            if let effetView {
                effetView.removeFromSuperview()
                self.effetView = nil
            }
        }
    }

    public final class TagReactionView: Control, ReactionViewImpl {
        fileprivate private(set) var reaction: ChatReactionsLayout.Reaction?
        fileprivate var isReusable: Bool {
            return self.effetView == nil && !self.imageView.isHidden
        }
        fileprivate func cancelPendingEffect() {
            self.effectDisposable.set(nil)
        }
        fileprivate let imageView: ChatReactionEmojiHost = {
            if ChatRowView.usesLegacyRowChrome {
                return ChatReactionEmojiViewHost()
            }
            let layer = ChatReactionEmojiLayer()
            layer.frame = NSMakeRect(0, 0, 16, 16)
            return layer
        }()
        private var emojiAnchor: View?
        private let emojiObserver = AnimatableContentObserver()
        private var first: Bool = true
        private var backgroundLayer: ChatReactionTagBackgroundLayer?
        private var textLayer: ChatReactionTextLayer?

        private var effetView: LottiePlayerView?
        private let effectDisposable = MetaDisposable()
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            
            imageView.install(in: self)
            scaleOnClick = true
            
            self.set(handler: { control in
                control.showContextMenu()
            }, for: .Click)
            
            
            self.contextMenu = { [weak self] in
                if let reaction = self?.reaction {
                    return reaction.loadMenu()
                }
                return nil
            }
            
            
            self.set(handler: { [weak self] _ in
                self?.reaction?.cancelMenu()
            }, for: .Normal)
            
        }
        
        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            textLayer?.updateScale(backingScaleFactor)
            backgroundLayer?.updateScale(backingScaleFactor)
            updateEmojiListeners()
            imageView.updateAnimatableContent()
        }

        @objc private func updateEmojiVisibility() {
            imageView.updateAnimatableContent()
        }

        private func updateEmojiListeners() {
            guard !imageView.observesOwnVisibility else { return }
            emojiObserver.update(for: self, target: self, selector: #selector(updateEmojiVisibility), options: [.contentBounds, .documentFrame, .ownFrame])
        }

        public override func viewDidChangeBackingProperties() {
            super.viewDidChangeBackingProperties()
            textLayer?.updateScale(backingScaleFactor)
            backgroundLayer?.updateScale(backingScaleFactor)
        }

        public override func accessibilityChildren() -> [Any]? {
            let children = super.accessibilityChildren() ?? []
            guard let child = textLayer?.accessibleChild() else { return children }
            return children + [child]
        }

        public override func accessibilityHitTest(_ point: NSPoint) -> Any? {
            return textLayer?.accessibilityHit(at: point) ?? super.accessibilityHitTest(point)
        }
        public override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            updateEmojiListeners()
            imageView.updateAnimatableContent()
        }
        
        public func playEffect() {
            let size = NSMakeSize(imageView.frame.width * 2, imageView.frame.height * 2)
            
            guard let reaction = reaction, let file = reaction.effectFile else {
                return
            }
            if TelegramUtilsHooks.shared.isLite(.emoji_effects) {
                return
            }

            let signal: Signal<LottieAnimation?, NoError> = reaction.context.account.postbox.mediaBox.resourceData(file.resource)
            |> filter { $0.complete }
            |> map { value -> Data? in
                return try? Data(contentsOf: URL(fileURLWithPath: value.path))
            }
            |> filter {
                $0 != nil
            }
            |> map {
                $0!
            }
            |> take(1)
            |> map { data in
                return LottieAnimation(compressed: data, key: .init(key: .bundle("_effect_\(reaction.value.value)"), size: size), cachePurpose: .none, playPolicy: .once, metalSupport: false)
            } |> deliverOnMainQueue

            self.effectDisposable.set(signal.start(next: { [weak self] animation in
                if let animation = animation {
                    self?.runAnimationEffect(animation)
                }
            }))
            
        }
        
        private func runAnimationEffect(_ animation: LottieAnimation) {
            let player = LottiePlayerView(frame: NSMakeRect(2, -3, animation.size.width, animation.size.height))

            player.set(animation, reset: true)
            
            self.effetView = player
            
            addSubview(player)
            
            self.imageView.setOpacityImmediately(0)
            
            animation.triggerOn = (LottiePlayerTriggerFrame.last, { [weak self, weak player] in
                self?.imageView.setOpacityImmediately(1)
                if let player = player {
                    performSubviewRemoval(player, animated: false)
                    if self?.effetView == player {
                        self?.effetView = nil
                    }
                }
            }, {})
        }
        
        public func update(with reaction: ChatReactionsLayout.Reaction, account: Account, animated: Bool) {
            let layerUpdated = reaction.source != self.reaction?.source
            let selectedUpdated = self.reaction?.value.isSelected != reaction.value.isSelected
            let reactionUpdated = self.reaction?.value.value != reaction.value.value
            self.reaction = reaction
            
            self.imageView.setCornerRadius(reaction.value.value.string == "" ? 4 : 0)
                        
            self.backgroundColor = .clear

            if selectedUpdated {
                if reaction.value.isSelected {
                    if backgroundLayer == nil {
                        let background = ChatReactionTagBackgroundLayer()
                        background.frame = bounds
                        background.capInsets = NSEdgeInsets(top: 3, left: 5, bottom: 3, right: 15)
                        background.isGeometryFlipped = isFlipped
                        background.contentsScale = backingScaleFactor
                        self.backgroundLayer = background
                        layer?.insertSublayer(background, at: 0)
                        
                        if animated {
                            background.animateScaleSpring(from: 0.1, to: 1, duration: 0.3)
                            background.animateAlpha(from: 0, to: 1, duration: 0.2)
                        }
                    }
                } else {
                    if let layer = backgroundLayer {
                        if animated {
                            let opacity = layer.presentation()?.opacity ?? layer.opacity
                            layer.animateAlpha(from: CGFloat(opacity), to: 0, duration: 0.2, timingFunction: .easeOut, removeOnCompletion: false, completion: { [weak layer] _ in
                                layer?.removeFromSuperlayer()
                            })
                            layer.animateScaleCenter(from: 1, to: 0.01, duration: 0.2, removeOnCompletion: false, timingFunction: .easeOut)
                        } else {
                            layer.removeFromSuperlayer()
                        }
                        self.backgroundLayer = nil
                    }
                }
            }
            
            let presentation = reaction.presentation
            
            if let text = reaction.text {
                let current: ChatReactionTextLayer
                if let layer = self.textLayer {
                    current = layer
                } else {
                    current = ChatReactionTextLayer()
                    current.frame = CGRect(origin: NSMakePoint(presentation.insetOuter + presentation.reactionSize.width + presentation.insetInner, (frame.height - text.layoutSize.height) / 2), size: text.layoutSize)
                    self.textLayer = current
                }
                current.update(text, in: self)
            } else if let layer = self.textLayer {
                layer.remove(animated: animated)
                self.textLayer = nil
            }
            
            
            
            self.backgroundLayer?.image = reaction.presentation.tagBackground
            
            if animated {
                self.layer?.animateBorder()
                self.layer?.animateBackground()
            }
            
            if !first, reactionUpdated, animated {
                self.imageView.animateAppear()
            }

            if first {
                updateLayout(size: reaction.rect.size, transition: .immediate)
                first = false
            }

            if layerUpdated {
                self.imageView.updateLayer(reaction.getInlineLayer(reaction.mode), isLite: TelegramUtilsHooks.shared.isLite(.emoji), animated: animated, host: self)
            }
        }
        
        deinit {
            effectDisposable.dispose()
        }
        
        public func isOwner(of reaction: ChatReactionsLayout.Reaction) -> Bool {
            return self.reaction?.value.value == reaction.value.value
        }
        
        public func getView() -> NSView {
            if let legacy = imageView as? ChatReactionEmojiViewHost {
                return legacy.view
            }
            let anchor: View
            if let emojiAnchor {
                anchor = emojiAnchor
            } else {
                anchor = View(frame: imageView.frame)
                anchor.isEventLess = true
                anchor.backgroundColor = .clear
                emojiAnchor = anchor
                addSubview(anchor)
            }
            if anchor.frame != imageView.frame {
                anchor.frame = imageView.frame
            }
            return anchor
        }
        
        public func lockVisibility() {
            self.imageView.isHidden = true
        }
        public func unlockVisibility() {
            self.imageView.isHidden = false
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
            guard let reaction = reaction else {
                return
            }
            
            if let backgroundLayer {
                transition.updateFrame(layer: backgroundLayer, frame: size.bounds)
            }
            
            let presentation = reaction.presentation
            
            var reactionSize = presentation.reactionSize
            
            if case .custom = reaction.value.value {
                reactionSize.width += 3
                reactionSize.height += 3
            }
            
            let emojiFrame = CGRect(origin: NSMakePoint(presentation.insetOuter, (size.height - reactionSize.height) / 2), size: reactionSize)
            self.imageView.setFrame(emojiFrame, transition: transition)
            if let emojiAnchor, emojiAnchor.frame != emojiFrame {
                emojiAnchor.frame = emojiFrame
            }
            
            if let textLayer = textLayer, let text = reaction.text {
                let center = focus(text.layoutSize)
                textLayer.updateFrame(CGRect(origin: NSMakePoint(self.imageView.frame.maxX + presentation.insetInner, center.minY), size: text.layoutSize), transition: transition)
            }
        }
        public override func layout() {
            super.layout()
            updateLayout(size: frame.size, transition: .immediate)
        }
    }
    
    private var currentLayout: ChatReactionsLayout?
    private var reactions:[ChatReactionsLayout.Reaction] = []
    private var views:[ReactionChipElement] = []
    private let usesNodes: Bool = !ChatRowView.usesLegacyRowChrome
    #if DEBUG
    var debugChipNodeCount: Int { views.filter { $0 is ReactionChip }.count }
    func debugChipHitChecks() -> (ok: Int, total: Int) {
        var ok = 0, total = 0
        for case let chip as ReactionChip in views {
            total += 1
            let center = NSPoint(x: chip.node.frame.midX, y: chip.node.frame.midY)
            guard let window else { continue }
            let windowPoint = convert(center, to: nil)
            if window.contentView?.hitTest(windowPoint) === self, hitNode(at: center) === chip.node {
                ok += 1
            }
        }
        return (ok, total)
    }
    #endif
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect, deferred: true)
        self.layer?.masksToBounds = false
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for case let chip as ReactionChip in views {
            chip.hostDidMoveToWindow()
        }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        for case let chip as ReactionChip in views {
            chip.hostDidChangeBackingProperties()
        }
    }

    fileprivate func attach(_ chip: ReactionChip) {
        guard chip.node.scene !== self else { return }
        chip.container = self
        do { try root.setChildren(root.children + [chip.node]) }
        catch { assertionFailure("Invalid reactions tree") }
        chip.hostDidMoveToWindow()
    }

    fileprivate func detach(_ chip: ReactionChip, animated: Bool) {
        guard chip.node.scene === self else { return }
        do { try root.setChildren(root.children.filter { $0 !== chip.node }) }
        catch { assertionFailure("Invalid reactions tree") }
        chip.removeAnchors()
        let layer = chip.node.layer
        if animated {
            root.layer.addSublayer(layer)
            let from = layer.presentation()?.opacity ?? layer.opacity
            layer.animateAlpha(from: CGFloat(from), to: 0, duration: 0.2, timingFunction: .easeOut, removeOnCompletion: false, completion: { [weak self, weak layer] finish in
                if finish {
                    layer?.removeFromSuperlayer()
                    self?.releaseEmptyLayerContent()
                }
            })
            layer.animateScaleCenter(from: 1, to: 0.01, duration: 0.2, removeOnCompletion: false, timingFunction: .easeOut)
        } else {
            releaseEmptyLayerContent()
        }
    }
    
    public func getView(_ value: MessageReaction.Reaction) -> ReactionViewImpl? {
        guard let currentLayout = currentLayout else {
            return nil
        }
        return self.views.first(where: { $0.chipReaction(in: currentLayout.mode)?.value.value == value })
    }
    
    public func getReactionView(_ value: MessageReaction.Reaction) -> NSView? {
        return getView(value)?.getView()
    }
    
    public func update(with layout: ChatReactionsLayout, animated: Bool) {
                
        
        let previous = self.reactions
        
        let (removed, inserted, updated) = mergeListsStableWithUpdates(leftList: self.reactions, rightList: layout.reactions)
        

        var deletedViews:[Int: ReactionChipElement] = [:]
        var reused:Set<Int> = Set()
        
        for idx in removed.reversed() {
            self.reactions.remove(at: idx)
            let view = self.views.remove(at: idx)
            deletedViews[idx] = view
        }
        let claimedByIdentity = Set(inserted.compactMap { $0.2 })
        for (idx, item, pix) in inserted {
            var prevFrame: NSRect? = nil
            var prevView: ReactionChipElement? = nil
            var reusedPix: Int?
            if let pix = pix {
                prevFrame = previous[pix].rect
                prevView = deletedViews[pix]
                if prevView != nil {
                    reused.insert(pix)
                    reusedPix = pix
                }
            }
            if prevView == nil, !animated {
                var candidate: (Int, ReactionChipElement)?
                for (key, view) in deletedViews where !reused.contains(key) && !claimedByIdentity.contains(key) {
                    let reusable = view.chipIsReusable(in: layout.mode)
                    let value = view.chipReaction(in: layout.mode)?.value.value
                    if !reusable {
                        continue
                    }
                    if value == item.value.value {
                        candidate = (key, view)
                        break
                    } else if candidate == nil || key < candidate!.0 {
                        candidate = (key, view)
                    }
                }
                if let (key, view) = candidate {
                    prevView = view
                    reused.insert(key)
                    reusedPix = key
                    view.chipCancelPendingEffect()
                }
            }
            let usesNodes = self.usesNodes
            let getView: (ReactionChipElement?)->ReactionChipElement = { prev in
                switch layout.mode {
                case .full:
                    if usesNodes {
                        if let prev = prev as? ReactionChip {
                            return prev
                        } else {
                            return ReactionChip(id: AnyHashable(UUID()), frame: item.rect)
                        }
                    }
                    if let prev = prev as? ReactionView {
                        return prev
                    } else {
                        return ReactionView(frame: item.rect)
                    }
                case .tag:
                    if let prev = prev as? TagReactionView {
                        return prev
                    } else {
                        return TagReactionView(frame: item.rect)
                    }
                }
            }
            
            let view = getView(prevView)
            
            if view !== prevView, let pix = reusedPix {
                _ = reused.remove(pix)
            }
            view.chipFrame = prevFrame ?? item.rect
            self.views.insert(view, at: idx)
            self.reactions.insert(item, at: idx)
            if let chip = view as? ReactionChip {
                chip.container = self
            }
            view.update(with: item, account: layout.context.account, animated: animated)
            if animated, prevView == nil {
                view.chipLayer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.3)
                view.chipLayer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            }
            view.install(in: self)
        }
        
        for (idx, item, prev) in updated {
            if prev != idx {
                self.views[idx].chipFrame = previous[prev].rect
            }
            self.views[idx].update(with: item, account: layout.context.account, animated: animated)
            self.reactions[idx] = item
        }
        
        for (i, view) in views.enumerated() {
            view.chipLayer?.masksToBounds = false
            view.chipLayer?.zPosition = CGFloat(i)
        }
        
        for (index, view) in deletedViews {
            if !reused.contains(index) {
                view.removeFromContainer(self, animated: animated)
            }
        }

        self.currentLayout = layout
        
        let transition: ContainedViewLayoutTransition
        if animated {
            transition = .animated(duration: 0.2, curve: .easeOut)
        } else {
            transition = .immediate
        }
        
        self.updateLayout(size: layout.size, transition: transition)
        
                
        let new = reactions.filter { $0.value.isSelected }.filter { value in
            var prev = previous.first(where: { $0.value.value == value.value.value && $0.value.isSelected })
            if value.value.value == .stars {
                prev = previous.first(where: { $0.value.value == value.value.value && $0.value.count == value.value.count })
            }
            return prev == nil
        }
        
        DispatchQueue.main.async { [self] in
            if let selected = new.first {
                let interactive = layout.context.reactions.interactive
                if let interactive = interactive {
                    let stars = selected.value.value == .stars
                    if interactive.messageId == layout.message.id, !stars || interactive.reaction == .stars  {
                        let view = self.getView(selected.value.value)
                        if let view = view {
                            if let fromRect = interactive.rect {
                                let current = view.getView()
                                
                                let layer = selected.getInlineLayer(selected.mode)

                                let toRect = current.convert(current.bounds, to: nil)
                                
                                let from = fromRect.origin.offsetBy(dx: fromRect.width / 2, dy: fromRect.height / 2)
                                let to = toRect.origin.offsetBy(dx: toRect.width / 2, dy: toRect.height / 2)
                                if selected.value.count == 1 {
                                    view.lockVisibility()
                                }
                                
                                let completed: (Bool)->Void = { [weak view, weak self] _ in
                                    view?.unlockVisibility()
                                    DispatchQueue.main.async {
                                        if !interactive.isLarge {
                                            view?.playEffect()
                                        }
                                        selected.runEffect(selected.value.value, interactive.isLarge)
                                        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                                        if selected.value.value == .stars, let window = self?.window as? Window {
                                            PlayConfetti(for: window, stars: true)
                                        }
                                    }
                                }
                                parabollicReactionAnimation(layer, fromPoint: from, toPoint: to, window: layout.context.window, completion: completed, duration: interactive.isLarge ? 0.5 : 0.2)
                            } else {
                                if !interactive.isLarge {
                                    view.playEffect()
                                }
                                selected.runEffect(selected.value.value, interactive.isLarge)
                            }
                        }
                    }
                }
            }
        }
    }
    
    public func playSeenReactionEffect(_ checkUnseen: Bool) {
        guard let currentLayout = currentLayout else {
            return
        }
        let layout = currentLayout.message.effectiveReactions(currentLayout.context.peerId, isTags: currentLayout.context.peerId == currentLayout.message.id.peerId)
        let peer = layout?.recentPeers.first(where: { $0.isUnseen || !checkUnseen })
        if let peer = peer, let reaction = reactions.first(where: { $0.value.value == peer.value }) {
            reaction.runEffect(reaction.value.value, peer.isLarge)
            if !peer.isLarge {
                getView(reaction.value.value)?.playEffect()
            }
        }
    }
    
    public override func layout() {
        super.layout()
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    public func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
        for (i, view) in views.enumerated() {
            let rect = self.reactions[i].rect
            view.updateChipFrame(rect, transition: transition)
            view.updateLayout(size: rect.size, transition: transition)
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

extension ChatReactionsView.ReactionView: ReactionChipElement {
    var chipFrame: NSRect {
        get { frame }
        set { frame = newValue }
    }
    var chipLayer: CALayer? { layer }
    func chipReaction(in mode: ChatReactionsLayout.Mode) -> ChatReactionsLayout.Reaction? {
        if case .full = mode { return reaction }
        return nil
    }
    func chipIsReusable(in mode: ChatReactionsLayout.Mode) -> Bool {
        if case .full = mode { return isReusable }
        return false
    }
    func chipCancelPendingEffect() { cancelPendingEffect() }
    func install(in container: ChatReactionsView) {
        if superview !== container { container.addSubview(self) }
    }
    func removeFromContainer(_ container: ChatReactionsView, animated: Bool) {
        performSubviewRemoval(self, animated: animated, checkCompletion: true, scale: true)
    }
    func updateChipFrame(_ frame: NSRect, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: self, frame: frame)
    }
}

extension ChatReactionsView.TagReactionView: ReactionChipElement {
    var chipFrame: NSRect {
        get { frame }
        set { frame = newValue }
    }
    var chipLayer: CALayer? { layer }
    func chipReaction(in mode: ChatReactionsLayout.Mode) -> ChatReactionsLayout.Reaction? {
        if case .tag = mode { return reaction }
        return nil
    }
    func chipIsReusable(in mode: ChatReactionsLayout.Mode) -> Bool {
        if case .tag = mode { return isReusable }
        return false
    }
    func chipCancelPendingEffect() { cancelPendingEffect() }
    func install(in container: ChatReactionsView) {
        if superview !== container { container.addSubview(self) }
    }
    func removeFromContainer(_ container: ChatReactionsView, animated: Bool) {
        performSubviewRemoval(self, animated: animated, checkCompletion: true, scale: true)
    }
    func updateChipFrame(_ frame: NSRect, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(view: self, frame: frame)
    }
}

extension ChatReactionsView.ReactionChip: ReactionChipElement {
    var chipFrame: NSRect {
        get { node.frame }
        set { node.frame = newValue }
    }
    var chipLayer: CALayer? { node.layer }
    func chipReaction(in mode: ChatReactionsLayout.Mode) -> ChatReactionsLayout.Reaction? {
        if case .full = mode { return reaction }
        return nil
    }
    func chipIsReusable(in mode: ChatReactionsLayout.Mode) -> Bool {
        if case .full = mode { return isReusable }
        return false
    }
    func chipCancelPendingEffect() { cancelPendingEffect() }
    func install(in container: ChatReactionsView) {
        container.attach(self)
    }
    func removeFromContainer(_ container: ChatReactionsView, animated: Bool) {
        container.detach(self, animated: animated)
    }
    func updateChipFrame(_ frame: NSRect, transition: ContainedViewLayoutTransition) {
        #if DEBUG
        node.updateFrame(frame.offsetBy(dx: ChatRowView.parityChipMutation, dy: 0), transition: transition)
        #else
        node.updateFrame(frame, transition: transition)
        #endif
    }
}
