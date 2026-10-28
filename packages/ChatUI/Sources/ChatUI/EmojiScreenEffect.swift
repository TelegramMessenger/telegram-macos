import Foundation
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import AppKit
import TelegramMedia
import TelegramMediaResources
import FoundationUtils
import LocalAnimations
import SceneEffects
import TelegramContext
import Strings
import TelegramMediaUtils
import TelegramTheme

public final class EmojiScreenEffect {
    fileprivate let context: any AccountContextProtocol
    fileprivate let takeTableItem:(MessageId)->ChatRowItem?
    public fileprivate(set) var scrollUpdater: TableScrollListener!
    private var dataDisposable: DisposableDict<MessageId> = DisposableDict()
    private var reactionDataDisposable: DisposableDict<MessageId> = DisposableDict()
    private var largeReactionCenterDisposable: DisposableDict<MessageId> = DisposableDict()
    
    private let limit: Int = 5
    
    struct Key : Hashable {
        enum Mode : Equatable, Hashable {
            case effect(Bool)
            case reaction(MessageReaction.Reaction)
            case largeReaction(MessageReaction.Reaction, mirror: Bool, centered: Bool)
            case largeReactionCenter(MessageReaction.Reaction)
        }
        let messageId: MessageId
        let timestamp: TimeInterval
        let isIncoming: Bool
        let mode: Mode
        
        var screenMode: ChatRowView.ScreenEffectMode {
            switch self.mode {
            case let .reaction(value), let .largeReaction(value, _, _), let .largeReactionCenter(value):
                return .reaction(value)
            case .effect:
                return .effect
            }
        }
    }
    
    struct Value {
        let view: WeakReference<EmojiAnimationEffectView>
        let index: Int
        let messageId: MessageId
        let emoji: String?
        let reaction: MessageReaction.Reaction?
        let mirror: Bool
        let key: Key
        var onRemove: (() -> Void)? = nil
        var collapse: (() -> Void)? = nil
    }
    
    private var animations:[Key: Value] = [:]
    
    private var enqueuedToServer:[Value] = []
    private var enqueuedToEnjoy:[Value] = []
    
    private var enjoyTimer: SwiftSignalKit.Timer?

    private var timers:[MessageId : SwiftSignalKit.Timer] = [:]
    
    
    
    public init(context: any AccountContextProtocol, takeTableItem:@escaping(MessageId)->ChatRowItem?) {
        self.context = context
        self.takeTableItem = takeTableItem
        
        self.scrollUpdater = .init(dispatchWhenVisibleRangeUpdated: false, { [weak self] position in
            self?.updateScroll(transition: .immediate)
        })
    }
    
    private func checkItem(_ item: TableRowItem, _ messageId: MessageId, with emoji: String) -> Bool {
        if let item = item as? ChatRowItem, item.message?.text.withoutColorizer == emoji.withoutColorizer {
            if messageId.peerId.namespace == Namespaces.Peer.CloudUser {
                return context.sharedContext.baseSettings.bigEmoji
            }
        }
        return false
    }
    
    private func updateScroll(transition: ContainedViewLayoutTransition) {
        var outOfBounds: Set<Key> = Set()
        for (key, animation) in animations {
            var success: Bool = false
            if let animationView = animation.view.value {
                if let item = takeTableItem(key.messageId), let view = item.view as? ChatRowView {
                    if let contentView = view.getScreenEffectView(key.screenMode) {
                        var point = contentView.convert(CGPoint.zero, to: animationView)
                        let subSize = animationView.animationSize - contentView.frame.size
                        
                        switch key.mode {
                        case let .effect(isPremium):
                            if !animation.mirror {
                                point.x-=subSize.width
                            }
                            point.y-=subSize.height/2
                                       
                            
                            if isPremium {
                                if !animation.mirror {
                                    point.x += 18
                                } else {
                                    point.x -= 18
                                }
                                point.y -= 10
                            } else {
                                point.x -= 10
                                point.y -= 5
                            }
                        case .reaction, .largeReactionCenter:
                            point.x-=subSize.width/2
                            point.y-=subSize.height/2
                        case let .largeReaction(_, mirror, centered):
                            point.x-=subSize.width/2
                            point.y-=subSize.height/2
                            if !centered {
                                point.x += (mirror ? 1 : -1) * animationView.animationSize.width * 0.3
                            }
                        }
                       

                        
                        animationView.updatePoint(point, transition: transition)
                        
                        if contentView.visibleRect != .zero {
                            success = true
                        } 
                    }
                }
            }
            if !success {
                outOfBounds.insert(key)
            }
        }
        for key in outOfBounds {
            self.deinitAnimation(key: key, animated: true)
        }
    }
    
    deinit {
        dataDisposable.dispose()
        reactionDataDisposable.dispose()
        largeReactionCenterDisposable.dispose()
        let animations = self.animations
        for animation in animations {
            deinitAnimation(key: animation.key, animated: false)
        }
    }
    private func isLimitExceed(_ messageId: MessageId) -> Bool {
        let onair = animations.filter { $0.key.messageId == messageId }
        let last = onair.max(by: { $0.key.timestamp < $1.key.timestamp })
        if let last = last {
            if Date().timeIntervalSince1970 - last.key.timestamp < 0.2 {
                return true
            }
        }
        return onair.count >= limit
    }
    
    
    func addAnimation(_ emoji: String, index: Int?, mirror: Bool, isIncoming: Bool, messageId: MessageId, animationSize: NSSize, viewFrame: NSRect, for parentView: NSView) {
        
        if context.isLite(.emoji_effects) {
            return
        }
        
        if !isLimitExceed(messageId), let item = takeTableItem(messageId), checkItem(item, messageId, with: emoji) {
            let signal: Signal<LottieAnimation?, NoError> = context.diceCache.animationEffect(for: emoji.emojiUnmodified)
            |> map { value -> LottieAnimation? in
                if let random = value.randomElement(), let data = random.1 {
                    return LottieAnimation(compressed: data, key: .init(key: .bundle("_effect_\(emoji)_\(random.2.fileId)"), size: animationSize, backingScale: Int(System.backingScale), mirror: mirror), cachePurpose: .temporaryLZ4(.effect), playPolicy: .onceEnd)
                } else {
                    return nil
                }
            }
            |> deliverOnMainQueue
            
            dataDisposable.set(signal.start(next: { [weak self, weak parentView] animation in
                if let animation = animation, let parentView = parentView {
                    self?.initAnimation(.builtin(animation), mode: .effect(false), emoji: emoji, reaction: nil, mirror: mirror, isIncoming: isIncoming, messageId: messageId, animationSize: animationSize, viewFrame: viewFrame, parentView: parentView)
                }
            }), forKey: messageId)
        } else {
            dataDisposable.set(nil, forKey: messageId)
        }
    }
    
    func addPremiumEffect(mirror: Bool, isIncoming: Bool, messageId: MessageId, viewFrame: NSRect, for parentView: NSView) {
        
        let context = self.context
        let onair = animations.filter { $0.key.messageId == messageId }

        if context.isLite(.emoji_effects) {
            return
        }
        
        if onair.isEmpty, let item = takeTableItem(messageId) {
            let signal: Signal<(LottieAnimation, String)?, NoError>
            var animationSize = NSMakeSize(item.contentSize.width * 1.5, item.contentSize.height * 1.5)
            if let messageEffect = item.messageEffect {
                let file = messageEffect.effectSticker._parse()
                animationSize = NSMakeSize(200, 200)
                
                if let animation = messageEffect.effectAnimation?._parse() {
                    signal = context.account.postbox.mediaBox.resourceData(animation.resource) |> filter { $0.complete } |> take(1) |> map { data in
                        if data.complete, let data = try? Data(contentsOf: URL(fileURLWithPath: data.path)) {
                            return (LottieAnimation(compressed: data, key: .init(key: .bundle("_prem_effect_\(animation.fileId.id)"), size: animationSize, backingScale: Int(System.backingScale), mirror: mirror), cachePurpose: .temporaryLZ4(.effect), playPolicy: .onceEnd), animation.stickerText ?? "")
                        } else {
                            return nil
                        }
                    }
                    let _ = fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .other, userContentType: .file, reference: MediaResourceReference.standalone(resource: animation.resource)).start()
                } else {
                    if let effect = messageEffect.effectSticker._parse().premiumEffect {
                        signal = context.account.postbox.mediaBox.resourceData(effect.resource) |> filter { $0.complete } |> take(1) |> map { data in
                            if data.complete, let data = try? Data(contentsOf: URL(fileURLWithPath: data.path)) {
                                return (LottieAnimation(compressed: data, key: .init(key: .bundle("_prem_effect_\(file.fileId.id)"), size: animationSize, backingScale: Int(System.backingScale), mirror: mirror), cachePurpose: .temporaryLZ4(.effect), playPolicy: .onceEnd), file.stickerText ?? "")
                            } else {
                                return nil
                            }
                        }
                        let _ = fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .other, userContentType: .file, reference: MediaResourceReference.standalone(resource: effect.resource)).start()
                    } else {
                        signal = .single(nil)
                    }
                }
                

            } else {
                signal = context.account.postbox.messageAtId(messageId)
                 |> mapToSignal { message in
                     if let message = message, let file = message.anyMedia as? TelegramMediaFile {
                         if let effect = file.premiumEffect {
                             return context.account.postbox.mediaBox.resourceData(effect.resource) |> filter { $0.complete } |> take(1) |> map { data in
                                 if data.complete, let data = try? Data(contentsOf: URL(fileURLWithPath: data.path)) {
                                     return (LottieAnimation(compressed: data, key: .init(key: .bundle("_prem_effect_\(file.fileId.id)"), size: animationSize, backingScale: Int(System.backingScale), mirror: mirror), cachePurpose: .temporaryLZ4(.effect), playPolicy: .onceEnd), file.stickerText ?? "")
                                 } else {
                                     return nil
                                 }
                             }
                         }
                     }
                     return .single(nil)
                 }
                
            }
           

            dataDisposable.set((signal |> deliverOnMainQueue).start(next: { [weak self, weak parentView] values in
                if let animation = values?.0, let emoji = values?.1, let parentView = parentView {
                    self?.initAnimation(.builtin(animation), mode: .effect(true), emoji: emoji, reaction: nil, mirror: mirror, isIncoming: isIncoming, messageId: messageId, animationSize: animationSize, viewFrame: viewFrame, parentView: parentView)
                }
            }), forKey: messageId)
        } else {
            dataDisposable.set(nil, forKey: messageId)
        }
    }
    
    public func addReactionAnimation(_ value: MessageReaction.Reaction, index: Int?, messageId: MessageId, animationSize initialAnimationSize: NSSize, isLarge: Bool = false, viewFrame: NSRect, for parentView: NSView) {
        
        let context = self.context
        
        if context.isLite(.emoji_effects) {
            return
        }
        
        let mode: Key.Mode
        let mirror: Bool
        let animationSize: NSSize
        if isLarge, value != .stars {
            let reactionView = (takeTableItem(messageId)?.view as? ChatRowView)?.getScreenEffectView(.reaction(value))
            let reactionFrame = reactionView.flatMap { $0.convert($0.bounds, to: parentView) }
            mirror = (reactionFrame?.midX ?? 0) < parentView.bounds.width / 2
            mode = .largeReaction(value, mirror: mirror, centered: false)
            animationSize = NSMakeSize(initialAnimationSize.width * 4, initialAnimationSize.height * 4)
            addLargeReactionCenter(value, messageId: messageId, animationSize: NSMakeSize(initialAnimationSize.width * 1.5, initialAnimationSize.height * 1.5), viewFrame: viewFrame, for: parentView)
        } else {
            mirror = false
            mode = .reaction(value)
            animationSize = initialAnimationSize
        }

        switch value {
        case let .custom(fileId):
            
            let signal: Signal<LottieAnimation?, NoError> = combineLatest(context.reactions.stateValue |> take(1), context.inlinePacksContext.load(fileId: fileId)) |> map { state, file in
                return state?.reactions.first(where: {
                    $0.value.string == file?.customEmojiText
                })
            }
             |> mapToSignal { reaction -> Signal<MediaResourceData?, NoError> in
                 if let file = isLarge ? reaction?.effectAnimation._parse() : reaction?.aroundAnimation?._parse() {
                    return context.account.postbox.mediaBox.resourceData(file.resource)
                    |> map { $0.complete ? $0 : nil }
                    |> take(1)
                } else {
                    return .single(nil)
                }
            } |> map { resource in
                if let resource = resource, let data = try? Data(contentsOf: URL(fileURLWithPath: resource.path)) {
                    return LottieAnimation(compressed: data, key: .init(key: .bundle("_reaction_\(isLarge ? "l" : "e")_\(value)"), size: animationSize, backingScale: Int(System.backingScale), mirror: mirror), cachePurpose: .temporaryLZ4(.effect), playPolicy: .onceEnd)
                } else {
                    return nil
                }
            } |> deliverOnMainQueue
            
            reactionDataDisposable.set(signal.start(next: { [weak self, weak parentView] animation in
                if let parentView = parentView {
                    if let animation = animation {
                        self?.initAnimation(.builtin(animation), mode: mode, emoji: nil, reaction: value, mirror: false, isIncoming: false, messageId: messageId, animationSize: animationSize, viewFrame: viewFrame, parentView: parentView)
                    } else {
                        let animationSize = isLarge ? animationSize : NSMakeSize(animationSize.width * 2, animationSize.height * 2)
                        let rect = NSMakeSize(animationSize.width, animationSize.height).bounds
                        let view = CustomReactionEffectView(frame: rect, context: context, fileId: fileId, style: .inlinePattern(mirrored: viewFrame.midX < parentView.bounds.width / 2))
                        let patternMode: Key.Mode = isLarge ? .largeReaction(value, mirror: mirror, centered: true) : mode
                        self?.initAnimation(.custom(view), mode: patternMode, emoji: nil, reaction: value, mirror: false, isIncoming: false, messageId: messageId, animationSize: animationSize, viewFrame: viewFrame, parentView: parentView)
                    }
                }
            }), forKey: messageId)
            
            
        case .builtin:
            let signal: Signal<LottieAnimation?, NoError> = context.reactions.stateValue |> take(1) |> map {
                return $0?.reactions.first(where: {
                    $0.value == value
                })
            }
            |> filter { $0 != nil}
            |> map {
                $0!
            } |> mapToSignal { reaction -> Signal<MediaResourceData, NoError> in
                if let file = isLarge ? reaction.effectAnimation._parse() : reaction.aroundAnimation?._parse() {
                    return context.account.postbox.mediaBox.resourceData(file.resource)
                    |> filter { $0.complete }
                    |> take(1)
                } else {
                    return .complete()
                }
            } |> map { data in
                if let data = try? Data(contentsOf: URL(fileURLWithPath: data.path)) {
                    return LottieAnimation(compressed: data, key: .init(key: .bundle("_reaction_\(isLarge ? "l" : "e")_\(value)"), size: animationSize, backingScale: Int(System.backingScale), mirror: mirror), cachePurpose: .temporaryLZ4(.effect), playPolicy: .onceEnd)
                } else {
                    return nil
                }
            } |> deliverOnMainQueue
            
            reactionDataDisposable.set(signal.start(next: { [weak self, weak parentView] animation in
                if let animation = animation, let parentView = parentView {
                    self?.initAnimation(.builtin(animation), mode: mode, emoji: nil, reaction: value, mirror: false, isIncoming: false, messageId: messageId, animationSize: animationSize, viewFrame: viewFrame, parentView: parentView)
                }
            }), forKey: messageId)
        case .stars:
            
            let files = [LocalAnimatedSticker.premium_reaction_effect_1.file,
                         LocalAnimatedSticker.premium_reaction_effect_2.file,
                         LocalAnimatedSticker.premium_reaction_effect_3.file,
                         LocalAnimatedSticker.premium_reaction_effect_4.file,
                         LocalAnimatedSticker.premium_reaction_effect_5.file]
            
            let signal: Signal<LottieAnimation?, NoError> = .single(files.randomElement()!) |> map { file -> MediaResourceData? in
                if let path = (file.resource as? LocalBundleResource)?.path {
                    return MediaResourceData(path: path, offset: 0, size: 0, complete: true)
                } else {
                    return nil
                }
            } |> map { resource in
                if let resource, let data = try? Data(contentsOf: URL(fileURLWithPath: resource.path)) {
                    return LottieAnimation(compressed: data, key: .init(key: .bundle("_reaction_e_\(resource.path.hashValue)"), size: animationSize, backingScale: Int(System.backingScale), mirror: false), cachePurpose: .temporaryLZ4(.effect), playPolicy: .onceEnd)
                } else {
                    return nil
                }
            } |> deliverOnMainQueue
            
            reactionDataDisposable.set(signal.start(next: { [weak self, weak parentView] animation in
                if let animation = animation, let parentView = parentView {
                    self?.initAnimation(.builtin(animation), mode: mode, emoji: nil, reaction: value, mirror: false, isIncoming: false, messageId: messageId, animationSize: animationSize, viewFrame: viewFrame, parentView: parentView)
                }
            }), forKey: messageId)
        }
        
        
       
    }

    
    
    private func addLargeReactionCenter(_ value: MessageReaction.Reaction, messageId: MessageId, animationSize: NSSize, viewFrame: NSRect, for parentView: NSView) {
        let context = self.context
        let file: Signal<TelegramMediaFile?, NoError>
        switch value {
        case .builtin:
            file = context.reactions.stateValue |> take(1) |> map {
                return $0?.reactions.first(where: { $0.value == value })?.activateAnimation._parse()
            }
        case let .custom(fileId):
            file = context.inlinePacksContext.load(fileId: fileId) |> take(1) |> map { file in
                return file?.isAnimatedSticker == true ? file : nil
            }
        case .stars:
            return
        }
        let signal: Signal<LottieAnimation?, NoError> = file
        |> mapToSignal { file -> Signal<MediaResourceData?, NoError> in
            if let file {
                return context.account.postbox.mediaBox.resourceData(file.resource)
                |> filter { $0.complete }
                |> take(1)
                |> map(Optional.init)
            } else {
                return .single(nil)
            }
        } |> map { data in
            if let data, let content = try? Data(contentsOf: URL(fileURLWithPath: data.path)) {
                return LottieAnimation(compressed: content, key: .init(key: .bundle("_reaction_c_\(value)"), size: animationSize, backingScale: Int(System.backingScale), mirror: false), cachePurpose: .temporaryLZ4(.effect), playPolicy: .onceEnd)
            } else {
                return nil
            }
        } |> deliverOnMainQueue

        largeReactionCenterDisposable.set(signal.start(next: { [weak self, weak parentView] animation in
            if let animation, let parentView {
                self?.initAnimation(.builtin(animation), mode: .largeReactionCenter(value), emoji: nil, reaction: value, mirror: false, isIncoming: false, messageId: messageId, animationSize: animationSize, viewFrame: viewFrame, parentView: parentView)
            }
        }), forKey: messageId)
    }

    private func collapseLargeReactionCenter(_ key: Key) {
        guard var value = animations[key], let collapse = value.collapse else {
            return
        }
        value.collapse = nil
        animations[key] = value
        collapse()
    }
    
    private func deinitAnimation(key: Key, animated: Bool) {
        let value = animations.removeValue(forKey: key)
        value?.onRemove?()
        let view = value?.view.value
        if let view = view {
            performSubviewRemoval(view, animated: animated)
        }
        if case let .largeReaction(reaction, _, _) = key.mode, case .custom = reaction {
            let centers = animations.keys.filter {
                $0.messageId == key.messageId && $0.mode == .largeReactionCenter(reaction)
            }
            for center in centers {
                collapseLargeReactionCenter(center)
            }
        }
        enqueuedToServer.removeAll(where: { $0.key == key })
        enqueuedToEnjoy.removeAll(where: { $0.key == key })
    }
    
    func removeAll() {
        dataDisposable.dispose()
        dataDisposable = DisposableDict()
        reactionDataDisposable.dispose()
        reactionDataDisposable = DisposableDict()
        largeReactionCenterDisposable.dispose()
        largeReactionCenterDisposable = DisposableDict()
        enjoyTimer?.invalidate()
        enjoyTimer = nil
        for timer in timers.values {
            timer.invalidate()
        }
        timers.removeAll()
        enqueuedToServer.removeAll()
        enqueuedToEnjoy.removeAll()
        let animations = self.animations
        for animation in animations {
            deinitAnimation(key: animation.key, animated: false)
        }
    }
    
    private func initAnimation(_ animation: EmojiAnimationEffectView.Source, mode: EmojiScreenEffect.Key.Mode, emoji: String?, reaction: MessageReaction.Reaction?, mirror: Bool, isIncoming: Bool, messageId: MessageId, animationSize: NSSize, viewFrame: NSRect, parentView: NSView) {
        
        
        let mediaView = (takeTableItem(messageId)?.view as? ChatMediaView)?.contentNode as? MediaAnimatedStickerView
        mediaView?.playAgain()
        
        let key: Key = .init(messageId: messageId, timestamp: Date().timeIntervalSince1970, isIncoming: isIncoming, mode: mode)
        
        switch animation {
        case let .builtin(animation):
            animation.triggerOn = (LottiePlayerTriggerFrame.last, { [weak self] in
                self?.deinitAnimation(key: key, animated: true)
            }, {})
        case let .custom(animation):
            animation.triggerOnFinish = { [weak self] in
                self?.deinitAnimation(key: key, animated: true)
            }
        }
       
        
        let view = EmojiAnimationEffectView(animation: animation, animationSize: animationSize, animationPoint: .zero, frameRect: viewFrame)

        parentView.addSubview(view)
        
        var value: Value = .init(view: .init(value: view), index: 1, messageId: messageId, emoji: emoji, reaction: reaction, mirror: mirror, key: key)

        if case let .largeReactionCenter(reactionValue) = mode, case let .builtin(lottie) = animation, let chip = (takeTableItem(messageId)?.view as? ChatRowView)?.getReactionChip(reactionValue) {
            let iconScale = max(chip.getView().frame.width, 1) / animationSize.width
            chip.lockVisibility()
            value.onRemove = { [weak chip] in
                chip?.unlockVisibility()
            }
            view.animateContentScale(from: iconScale, to: 1, duration: 0.35, spring: true)
            value.collapse = { [weak self, weak view] in
                view?.animateContentScale(from: 1, to: iconScale, duration: 0.25, completion: { _ in
                    self?.deinitAnimation(key: key, animated: false)
                })
            }
            lottie.triggerOn = (LottiePlayerTriggerFrame.last, { [weak self] in
                self?.collapseLargeReactionCenter(key)
            }, {})
        }
        animations[key] = value
        
        updateScroll(transition: .immediate)
        if !isIncoming {
            self.enqueuedToServer.append(value)
        } else {
            self.enqueuedToEnjoy.append(value)
        }
        self.enqueueToServer()
        self.enqueueToEnjoy()
    }
    
    private func enqueueToEnjoy() {
        if enjoyTimer == nil, !enqueuedToEnjoy.isEmpty {
            enjoyTimer = .init(timeout: 1.0, repeat: false, completion: { [weak self] in
                self?.performEnjoyAction()
            }, queue: .mainQueue())
            enjoyTimer?.start()
        }
    }
    
    private func performEnjoyAction() {
        self.enjoyTimer = nil
        
        var exists:Set<MessageId> = Set()
        for value in enqueuedToEnjoy {
            if !exists.contains(value.key.messageId), let emoji = value.emoji {
                context.account.updateLocalInputActivity(peerId: PeerActivitySpace(peerId: value.key.messageId.peerId, category: .global), activity: .seeingEmojiInteraction(emoticon: emoji), isPresent: true)
                exists.insert(value.key.messageId)
            }
        }
        self.enqueuedToEnjoy.removeAll()
    }
    
    private func enqueueToServer() {
        let outgoing = self.enqueuedToServer
        let msgIds:[MessageId] = outgoing.map { $0.key.messageId }.uniqueElements
 
        for msgId in msgIds {
            if self.timers[msgId] == nil {
                self.timers[msgId] = .init(timeout: 1, repeat: false, completion: { [weak self] in
                    self?.performServerActions(for: msgId)
                }, queue: .mainQueue())
                self.timers[msgId]?.start()
            }
        }
    }
    
    private func performServerActions(for msgId: MessageId) {
        let values = self.enqueuedToServer.filter { $0.key.messageId == msgId }
        self.enqueuedToServer.removeAll(where: { $0.key.messageId == msgId })
        self.timers.removeValue(forKey: msgId)
        if !values.isEmpty {
            let value = values.min(by: { $0.key.timestamp < $1.key.timestamp })!
            let animations:[EmojiInteraction.Animation] = values.map { current -> EmojiInteraction.Animation in
                .init(index: current.index, timeOffset: Float((current.key.timestamp - value.key.timestamp)))
            }.sorted(by: { $0.timeOffset < $1.timeOffset })
            
            if let emoji = value.emoji {
                context.account.updateLocalInputActivity(peerId: PeerActivitySpace(peerId: msgId.peerId, category: .global), activity: .interactingWithEmoji(emoticon: emoji, messageId: msgId, interaction: EmojiInteraction(animations: animations)), isPresent: true)
            }
        }
    }
    
    
    func updateLayout(rect: CGRect, transition: ContainedViewLayoutTransition) {
        for (_ , animation) in animations {
            if let value = animation.view.value {
                transition.updateFrame(view: value, frame: rect)
                value.updateLayout(size: rect.size, transition: transition)
            }
        }
    }
}


