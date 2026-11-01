import Foundation
import TGUIKit
import AppKit
import SwiftSignalKit
import TelegramCore
import Postbox
import ObjcUtils
import TelegramMedia
import TelegramMediaResources
import LocalAnimations
import Localization
import StarsUI
import TelegramContext
import TelegramMediaUtils
import TelegramTheme
import TelegramUtils
import InlineStickerLayer



private let largeReactionHoldDuration: Double = 0.8

public final class ContextAddReactionsListView : View, StickerFramesCollector, AppMenuCursorAppearance  {
    
    
    private final class ReactionView : Control {
                
        let player: LottiePlayerView
        private var imageView: InlineStickerView?
        private let disposable = MetaDisposable()
        private let appearDisposable = MetaDisposable()
        private let fetchDisposables = DisposableSet()
        let reaction: ContextReaction
        let context: any AccountContextProtocol
        private let stateDisposable = MetaDisposable()
        private var selectAnimationData: Data?
        private var currentKey: String?
        
        private var selectionView : NSView?
        private let presentation: TelegramPresentationTheme
        
        private var starEffect: StarsButtonEffectLayer?
        
        private var starBackground: SimpleGradientLayer?
        
        private let parentWindow: Window?
        
        required init(frame frameRect: NSRect, context: any AccountContextProtocol, reaction: ContextReaction, add: @escaping(MessageReaction.Reaction, Bool, NSRect?)->Void, addLarge: ((MessageReaction.Reaction, NSRect?)->Void)?, theme: TelegramPresentationTheme, message: Message?, parentWindow: Window? = nil) {
            
            let size: NSSize = reaction.isSelected ? NSMakeSize(25, 24) : NSMakeSize(frameRect.width, 30)
            let rect = CGRect(origin: .zero, size: size)
            
            let isLite = context.isLite(.emoji)
            
            self.presentation = theme
            self.player = LottiePlayerView(frame: rect)
            self.reaction = reaction
            self.context = context
            self.parentWindow = parentWindow
           
            super.init(frame: frameRect)
            
            self.layer?.masksToBounds = false
            
            if case .stars = reaction.value {
                
                if !reaction.isSelected {
                    starBackground = .init(frame: frameRect.size.bounds.insetBy(dx: -4, dy: -4))
                    self.layer?.addSublayer(starBackground!)
                    
                    starBackground?.type = .radial
                    starBackground?.colors =  [NSColor(0xFFAC04).withAlphaComponent(0.28),
                                               NSColor(0xFFCA35).withAlphaComponent(0.14),
                                               NSColor(0xFFCA35).withAlphaComponent(0.0)].map { $0.cgColor }
                    
                    starBackground?.startPoint = NSMakePoint(0.5, 0.5)
                    starBackground?.endPoint = NSMakePoint(1, 1)
                }
                
                

                
                starEffect = .init()
                starEffect?.frame = rect
                starEffect?.update(size: rect.size)
                self.layer?.addSublayer(starEffect!)
            }

            
            let imageView: InlineStickerView
            if let file = reaction.selectedAnimation {
                imageView = InlineStickerView(account: context.account, file: file, size: size, isPlayable: false)
            } else {
                imageView = InlineStickerView(account: context.account, inlinePacksContext: context.inlinePacksContext, emoji: .init(fileId: reaction.fileId, file: nil, emoji: clown), size: size, isPlayable: false)
            }
            self.imageView = imageView
            addSubview(imageView)

            addSubview(player)
            self.player.isHidden = false
            
          
           
            switch reaction {
            case .builtin:
                self.layer?.cornerRadius = 0
            case .custom:
                self.layer?.cornerRadius = 4
            case .stars:
                self.layer?.cornerRadius = 0
            }
            
            stateDisposable.set(player.state.start(next: { [weak self] state in
                switch state {
                case .playing:
                    delay(0.016, closure: {
                        self?.imageView?.removeFromSuperview()
                    })
                case .stoped:
                    delay(0.016, closure: {
                        self?.imageView?.removeFromSuperview()
                    })
                default:
                    break
                }
            }))
                                    

            let signal = reaction.selectAnimation(context) |> mapToSignal { file in
                if let resource = file.resource as? LocalBundleResource, let path = resource.path {
                    return .single(MediaResourceData(path: path, offset: 0, size: 0, complete: true))
                } else {
                    return context.account.postbox.mediaBox.resourceData(file.resource, attemptSynchronously: true)
                }
            }
            |> filter {
                $0.complete
            }
            |> deliverOnMainQueue
            
            disposable.set(signal.start(next: { [weak self] resourceData in
                if let data = try? Data(contentsOf: URL.init(fileURLWithPath: resourceData.path)) {
                    self?.selectAnimationData = data
                    if !isLite {
                        let apply:()->Void = {
                            self?.apply(data, key: "select", policy: .framesCount(1))
                        }
                        apply()
                    }
                }
            }))
            
            let getWindow:()->Window = { [weak self] in
                return self?.parentWindow ?? context.window
            }
            
            set(handler: { control in
                if let window = control.window, (control as? ReactionView)?.largeInvoked != true {
                    let wrect = control.convert(control.frame.size.bounds, to: nil)
                    let srect = window.convertToScreen(wrect)
                    add(reaction.value, true, getWindow().convertFromScreen(srect))
                }
            }, for: .Click)
            
            if let addLarge, !reaction.isSelected, reaction.value != .stars {
                self.handleLongEvent = false
                self.largeHoldEnabled = true
                set(handler: { control in
                    (control as? ReactionView)?.startLargeHold(completion: { control in
                        if let window = control.window {
                            let wrect = control.convert(control.frame.size.bounds, to: nil)
                            let srect = window.convertToScreen(wrect)
                            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                            addLarge(reaction.value, getWindow().convertFromScreen(srect))
                            AppMenu.closeAll()
                        }
                    })
                }, for: .Down)
                set(handler: { control in
                    (control as? ReactionView)?.cancelLargeHold()
                }, for: .Up)
            }

            if case .stars = reaction.value, let message {
                self.set(handler: { _ in
                    showModal(with: Star_ReactionsController(context: context, source: .message(.init(message))), for: getWindow())
                    AppMenu.closeAll()
                }, for: .RightDown)
                
                self.set(handler: { _ in
                    showModal(with: Star_ReactionsController(context: context, source: .message(.init(message))), for: getWindow())
                    AppMenu.closeAll()
                }, for: .LongMouseDown)
            } else {
                
                contextMenu = {
                    let menu = ContextMenu()
                    menu.addItem(ContextMenuItem(strings().chatContextReactionQuick, handler: {
                        context.reactions.updateQuick(reaction.value)
                    }, itemImage: MenuAnimation.menu_add_to_favorites.value))
                    return menu
                }
            }
            
            
            
            
            if reaction.isSelected {
                let size = ContextAddReactionsListView.showMoreSize
                let view: NSView
                if TelegramUtilsHooks.shared.isLite(.blur) {
                    let solid = View()
                    solid.backgroundColor = theme.colors.vibrant.mixedWith(NSColor(0x000000), alpha: 0.1)
                    view = solid
                } else {
                    let frost = NSVisualEffectView()
                    frost.wantsLayer = true
                    frost.material = .selection
                    frost.blendingMode = .withinWindow
                    frost.state = .active
                    frost.appearance = NSAppearance(named: theme.colors.isDark ? .darkAqua : .aqua)
                    frost.layer?.masksToBounds = true
                    view = frost
                }
                self.selectionView = view
                view.frame = NSMakeRect(0, 0, size, size)
                view.layer?.cornerRadius = size / 2
                self.addSubview(view, positioned: .below, relativeTo: self.subviews.first)
                
                if case .custom = reaction.value {
                    self.player.layer?.cornerRadius = 4
                    self.imageView?.layer?.cornerRadius = 4
                }
            }

            if let file = reaction.selectedAnimation {
                fetchDisposables.add(fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .other, userContentType: .sticker, reference: .standalone(resource: file.resource)).start())
            }
            if let file = reaction.appearAnimation {
                fetchDisposables.add(fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: .other, userContentType: .sticker, reference: .standalone(resource: file.resource)).start())
            }
            
        }
        
        var isLite: Bool {
            return context.isLite(.emoji)
        }
        
        private var largeHoldTimer: SwiftSignalKit.Timer?
        private var largeHoldEnabled: Bool = false
        fileprivate private(set) var largeInvoked: Bool = false

        fileprivate func startLargeHold(completion: @escaping(ReactionView)->Void) {
            largeHoldTimer?.invalidate()
            self.layer?.zPosition = 1
            self.layer?.animateScaleCenter(from: 1, to: 1.5, duration: largeReactionHoldDuration, removeOnCompletion: false)
            largeHoldTimer = SwiftSignalKit.Timer(timeout: largeReactionHoldDuration, repeat: false, completion: { [weak self] in
                guard let self else {
                    return
                }
                self.largeHoldTimer = nil
                if self.mouseInside() {
                    self.largeInvoked = true
                    completion(self)
                } else {
                    self.cancelLargeHold()
                }
            }, queue: .mainQueue())
            largeHoldTimer?.start()
        }

        fileprivate func cancelLargeHold() {
            guard !largeInvoked else {
                return
            }
            largeHoldTimer?.invalidate()
            largeHoldTimer = nil
            let current = self.layer?.presentation()?.value(forKeyPath: "transform.scale") as? CGFloat ?? 1
            self.layer?.animateScaleCenter(from: current, to: 1, duration: 0.2, removeOnCompletion: true)
            self.layer?.zPosition = 0
        }

        private func apply(_ data: Data, key: String, policy: LottiePlayPolicy) {
            let animation = LottieAnimation(compressed: data, key: LottieAnimationEntryKey(key: .bundle("reaction_\(reaction.value)_\(key)"), size: player.frame.size), type: .lottie, cachePurpose: .none, playPolicy: policy, maximumFps: 60, runOnQueue: Queue(), metalSupport: false)
            player.set(animation, reset: true, saveContext: true, animated: false)
            self.currentKey = key
        }
        
        deinit {
            disposable.dispose()
            stateDisposable.dispose()
            appearDisposable.dispose()
            fetchDisposables.dispose()
        }
        
        override func layout() {
            super.layout()
            updateLayout(size: self.frame.size, transition: .immediate)
        }
        
        func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            transition.updateFrame(view: player, frame: self.focus(player.frame.size))
            if let imageView = imageView {
                transition.updateFrame(view: imageView, frame: self.focus(imageView.frame.size))
            }
            if let selectionView = self.selectionView {
                selectionView.center()
            }
        }
        private var previous: ControlState = .Normal
        override func stateDidUpdate(_ state: ControlState) {
            super.stateDidUpdate(state)
            let isLite = context.isLite(.emoji)
            switch state {
            case .Hover:
                if self.player.currentState != .playing, !isLite {
                    if self.player.animation?.playPolicy == .framesCount(1) {
                        self.player.set(self.player.animation?.withUpdatedPolicy(.once), reset: false)
                    } else {
                        if let data = selectAnimationData, self.currentKey != "select" {
                            self.apply(data, key: "select", policy: .framesCount(1))
                        } else {
                            self.player.playAgain()
                        }
                    }
                }
            default:
                break
            }
            
            if !largeHoldEnabled, previous == .Hover, state == .Highlight {
                self.layer?.animateScaleCenter(from: 1, to: 0.8, duration: 0.2, removeOnCompletion: false)
            } else if !largeHoldEnabled, state == .Hover, previous == .Highlight {
                self.layer?.animateScaleCenter(from: 0.8, to: 1, duration: 0.2, removeOnCompletion: true)
            }
            previous = state
        }
        
        private var timestamp: TimeInterval? = Date().timeIntervalSince1970
        
        func playAppearAnimation() {
            guard self.visibleRect != .zero && !self.isLite else {
                return
            }
          
            
            
            if let appearAnimation = reaction.selectedAnimation {
                let signal = context.account.postbox.mediaBox.resourceData(appearAnimation.resource, attemptSynchronously: true)
                |> filter {
                    $0.complete
                } |> take(1)
                |> deliverOnMainQueue
                
//                self.imageView?.removeFromSuperview()
                            
                appearDisposable.set(signal.start(next: { [weak self] resourceData in
                    if let data = try? Data(contentsOf: URL.init(fileURLWithPath: resourceData.path)) {
                        if let timestamp = self?.timestamp, Date().timeIntervalSince1970 - timestamp > 0.1 {
                            return
                        }
                        self?.apply(data, key: "appear", policy: .toEnd(from: 0))
                    }
                }))
            } else {
                imageView?.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.35, bounce: true)
            }
            
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        required init(frame frameRect: NSRect) {
            fatalError("init(frame:) has not been implemented")
        }
    }
    
    public class ShowMore : Control {
        private let imageView = ImageView()
        private var loadingViews: [ImageView] = []
        private let frost = NSVisualEffectView()
        var onEnter: (() -> Void)?
        public override func mouseEntered(with event: NSEvent) {
            super.mouseEntered(with: event)
            onEnter?()
        }
        public required init(frame frameRect: NSRect, theme: TelegramPresentationTheme) {
            super.init(frame: frameRect)
            self.scaleOnClick = true
            self.layer?.cornerRadius = frameRect.height / 2
            if TelegramUtilsHooks.shared.isLite(.blur) {
                self.backgroundColor = theme.colors.vibrant.mixedWith(NSColor(0x000000), alpha: 0.1)
            } else {
                frost.wantsLayer = true
                frost.material = .selection
                frost.blendingMode = .withinWindow
                frost.state = .active
                frost.appearance = NSAppearance(named: theme.colors.isDark ? .darkAqua : .aqua)
                frost.layer?.masksToBounds = true
                addSubview(frost)
            }
            addSubview(self.imageView)
            self.imageView.isAccessibilityDecorative = true
            self.setAccessibilityLabel(strings().voiceOverCommonMore)
            self.imageView.image = theme.icons.reactions_show_more
            self.imageView.sizeToFit()
        }
        
        public override func layout() {
            super.layout()
            frost.frame = bounds
            frost.layer?.cornerRadius = bounds.height / 2
            layer?.cornerRadius = bounds.height / 2
            imageView.center()
            for view in loadingViews {
                view.frame = imageView.frame
            }
        }
        
        func startLoading() {
            guard loadingViews.isEmpty else {
                return
            }
            self.userInteractionEnabled = false
            for _ in 0 ..< 2 {
                let view = ImageView()
                view.isAccessibilityDecorative = true
                view.image = imageView.image
                view.frame = imageView.frame
                addSubview(view, positioned: .below, relativeTo: imageView)
                loadingViews.append(view)
            }
            let views = loadingViews + [imageView]
            let step: CGFloat = 4
            let now = CACurrentMediaTime()
            for (i, view) in views.enumerated() {
                guard let layer = view.layer else {
                    continue
                }
                let offset = (CGFloat(i) - 1) * step
                layer.opacity = 0.4 + 0.3 * Float(i)
                layer.transform = CATransform3DMakeTranslation(0, offset, 0)
                layer.animate(from: NSNumber(value: Float(-offset)), to: NSNumber(value: 0), keyPath: "transform.translation.y", timingFunction: .spring, duration: 0.25, additive: true)
                
                let bounce = CAKeyframeAnimation(keyPath: "transform.translation.y")
                bounce.values = [0, 3, 0]
                bounce.keyTimes = [0, 0.5, 1]
                bounce.timingFunctions = [CAMediaTimingFunction(name: .easeInEaseOut), CAMediaTimingFunction(name: .easeInEaseOut)]
                bounce.duration = 0.7
                bounce.repeatCount = .infinity
                bounce.isAdditive = true
                bounce.beginTime = now + 0.25 + Double(i) * 0.08
                bounce.fillMode = .backwards
                layer.add(bounce, forKey: "loading")
            }
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public required init(frame frameRect: NSRect) {
            fatalError("init(frame:) has not been implemented")
        }
    }
    
    private let scrollView = HorizontalScrollView()
    private let documentView = View()
    private let list: [ContextReaction]
    private var boundsObserver: NSObjectProtocol?
    
    private let topGradient = ShadowView()
    private let bottomGradient = ShadowView()

    private let backgroundView = View()
    private let visualEffect = NSVisualEffectView(frame: .zero)
    private var glassContainer: NSView?
    private var glassShapes: [NSView] = []
    private let radiusLayer: CGFloat?
    
    private var aboveTextView: TextView?
    
    private let showMore: ShowMore
    private let revealReactions:((ContextAddReactionsListView & StickerFramesCollector)->Void)?
    public var prepareReveal: (() -> Void)?
    
    private let maskLayer = SimpleShapeLayer()
    private let backgroundColorView = View()
    private let shadowLayer = SimpleShapeLayer()
    private let presentation: TelegramPresentationTheme
    private var hasBubble: Bool
    private let aboveText: TextViewLayout?
    public required init(frame frameRect: NSRect, context: any AccountContextProtocol, list: [ContextReaction], add:@escaping(MessageReaction.Reaction, Bool, NSRect?)->Void, addLarge: ((MessageReaction.Reaction, NSRect?)->Void)? = nil, radiusLayer: CGFloat? = 15, revealReactions:((ContextAddReactionsListView & StickerFramesCollector)->Void)? = nil, presentation: TelegramPresentationTheme = theme, hasBubble: Bool = true, aboveText: TextViewLayout? = nil, message: Message? = nil, parentWindow: Window? = nil) {
        self.list = list
        self.showMore = ShowMore(frame: NSMakeRect(0, 0, ContextAddReactionsListView.showMoreSize, ContextAddReactionsListView.showMoreSize), theme: presentation)
        self.revealReactions = revealReactions
        self.radiusLayer = radiusLayer
        self.presentation = presentation
        self.hasBubble = hasBubble
        self.aboveText = aboveText
        super.init(frame: frameRect)
        
        
        let theme = presentation
        
        if #available(macOS 26.0, *), System.liquidGlass, System.liquidGlassAvailable, !TelegramUtilsHooks.shared.isLite(.blur) {
            let container = FlippedGlassEffectContainerView(frame: frameRect.size.bounds, flipped: true)
            container.spacing = 8
            let content = GlassContentView(frame: frameRect.size.bounds)
            container.contentView = content
            let appearance = NSAppearance(named: presentation.colors.isDark ? .darkAqua : .aqua)
            for _ in 0 ..< (hasBubble ? 2 : 1) {
                let glass = NSGlassEffectView(frame: .zero)
                glass.style = .regular
                glass.tintColor = presentation.colors.background.withAlphaComponent(0.3)
                glass.appearance = appearance
                content.addSubview(glass)
                glassShapes.append(glass)
            }
            self.glassContainer = container
            addSubview(container)
        }
        backgroundView.layer?.mask = maskLayer
        if !TelegramUtilsHooks.shared.isLite(.blur) {
            self.visualEffect.state = .active
            self.visualEffect.wantsLayer = true
            self.visualEffect.blendingMode = hasBubble ? .behindWindow : .withinWindow
        }
        
        
        
        showMore.isHidden = revealReactions == nil
        
        showMore.onEnter = { [weak self] in
            self?.prepareReveal?()
        }

        showMore.set(handler: { [weak self] _ in
            AppMenu.keepsOpenOnNextMouseUp = true
            self?.prepareReveal?()
        }, for: .Down)

        showMore.set(handler: { [weak self] control in
            if let view = self {
                if view.glassContainer != nil, view.hasBubble {
                    view.collapseTail()
                } else {
                    view.hasBubble = false
                    view.updateLayout(size: view.frame.size, transition: .immediate)
                }
                view.showMore.startLoading()
                revealReactions?(view)
            }
        }, for: .Click)
        
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOffset = CGSize(width: 0.0, height: 0)
        shadowLayer.shadowRadius = 2
        shadowLayer.shadowOpacity = 0.2
        shadowLayer.fillColor = NSColor.clear.cgColor
        if glassContainer == nil {
            self.layer?.addSublayer(shadowLayer)
        }

        bottomGradient.shadowBackground = theme.colors.background.withAlphaComponent(1)
        bottomGradient.direction = .horizontal(true)
        topGradient.shadowBackground = theme.colors.background.withAlphaComponent(1)
        topGradient.direction = .horizontal(false)
        
        let usesMaterial: Bool
        if #available(macOS 11.0, *), !TelegramUtilsHooks.shared.isLite(.blur) {
            usesMaterial = true
            visualEffect.material = .menu
            visualEffect.appearance = NSAppearance(named: theme.colors.isDark ? .darkAqua : .aqua)
            backgroundColorView.backgroundColor = glassContainer == nil ? .menuFallbackVeil(isDark: theme.colors.isDark) : .clear
        } else {
            usesMaterial = false
            backgroundColorView.backgroundColor = theme.colors.background
        }
        if #available(macOS 11.0, *), !TelegramUtilsHooks.shared.isLite(.blur), glassContainer == nil {
            backgroundView.addSubview(visualEffect)
        }
        backgroundView.addSubview(backgroundColorView)

        
        
        addSubview(backgroundView)
        backgroundView.addSubview(scrollView)
        addSubview(showMore)
        
        if !usesMaterial {
            backgroundView.addSubview(topGradient)
            backgroundView.addSubview(bottomGradient)
        }

        
        if revealReactions == nil {
            boundsObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.clipView, queue: OperationQueue.main, using: { [weak self] notification  in
                self?.updateScroll()
            })
        } else {
            var calc:CGFloat = 0
            var clicked: Bool = false
            scrollView.applyExternalScroll = { [weak self] event in
                calc += abs(event.deltaY)
                calc += abs(event.deltaX)
                
                if calc > 30, !clicked {
                    self?.showMore.send(event: .Click)
                    AppMenu.closeAll()
                    clicked = true
                    return false
                }
                return true
            }
        }
        
                
        scrollView.background = .clear
        scrollView.documentView = documentView
        let size = ContextAddReactionsListView.size
        var x: CGFloat = 1
        
       
        
        
        var y: CGFloat = 3
        if let aboveText = aboveText {
            y += aboveText.layoutSize.height + 2
        }
        
        for reaction in list {
            let add:(ContextReaction)->Void = { reaction in
                let itemSize = size.bounds
                let reaction = ReactionView(frame: NSMakeRect(x, y, itemSize.width, itemSize.height), context: context, reaction: reaction, add: add, addLarge: addLarge, theme: presentation, message: message, parentWindow: parentWindow)
                
                self.documentView.addSubview(reaction)
                x += size.width + 3
            }
            if x < frame.width {
                add(reaction)
            } else {
                DispatchQueue.main.async {
                    add(reaction)
                }
            }
        }
        
        if let aboveText = aboveText {
            let aboveTextView = TextView()
            aboveTextView.userInteractionEnabled = true
            aboveTextView.isSelectable = false
            addSubview(aboveTextView)
            self.aboveTextView = aboveTextView
            aboveTextView.update(aboveText)
        }
        
        updateLayout(size: frame.size, transition: .immediate)
        
       

        for view in self.documentView.subviews {
            let view = view as? ReactionView
            view?.playAppearAnimation()
        }
        updateScroll()
    }
    
    public func revealDidStart() {
        guard let superview = self.superview else {
            return
        }
        let button = self.showMore
        let frame = button.convert(button.bounds, to: superview)
        button.removeFromSuperview()
        button.frame = frame
        superview.addSubview(button)
        button.layer?.animateScaleCenter(from: 1, to: 0.1, duration: 0.2, removeOnCompletion: false)
        button.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak button] _ in
            button?.removeFromSuperview()
        })
    }
    
    public func collect() -> [Int : LottiePlayerView] {
        var frames:[Int : LottiePlayerView] = [:]
        for (i, view) in self.documentView.subviews.enumerated() {
            if let view = view as? ReactionView {
                frames[i] = view.player
            }
        }
        return frames
    }
    
    public func invokeFirst() {
        for view in self.documentView.subviews {
            if let view = view as? ReactionView {
                view.send(event: .Click)
                return
            }
        }
    }
    
    public static var size: CGSize {
        return .init(width: 37, height: 34)
    }
    
    public func rect(for reaction: ContextReaction) -> NSRect {
        let view = documentView.subviews.compactMap {
            $0 as? ReactionView
        }.first(where: {
            $0.reaction == reaction
        })
        if let view = view {
            return view.frame
        } else {
            return .zero
        }
    }
    
    private var previousRange: [Int] = []
    private func updateScroll() {
        
        self.topGradient.isHidden = self.scrollView.documentOffset.x == 0
        self.bottomGradient.isHidden = self.scrollView.documentOffset.x == self.scrollView.documentSize.width - self.scrollView.frame.width

        let range = visibleRange(self.scrollView.documentOffset)
        if previousRange != range, !previousRange.isEmpty {
            let new = range.filter({
                !previousRange.contains($0)
            })
            for i in new {
                let view = self.documentView.subviews[i] as? ReactionView
                view?.playAppearAnimation()
            }
        }
        self.previousRange = range
        
        if self.radiusLayer != nil {
            for view in documentView.subviews {
                var fr = CATransform3DIdentity
                if view.visibleRect.size != view.frame.size {
                    let value = max(0.5, view.visibleRect.width / view.frame.width)
                    fr = CATransform3DTranslate(fr, view.frame.width / 2, view.frame.height / 2, 0)
                    fr = CATransform3DScale(fr, value, value, 1)
                    fr = CATransform3DTranslate(fr, -(view.frame.width / 2), -(view.frame.height / 2), 0)
                    view.layer?.transform = fr
                } else {
                    view.layer?.transform = fr
                }
            }
        }
       
    }
    
    private func visibleRange(_ documentOffset: NSPoint) -> [Int] {
        var range: [Int] = []
        for (i, view) in documentView.subviews.enumerated() {
            if view.visibleRect != .zero {
                range.append(i)
            }
        }
        return range
    }
    
    
    public override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }
    
    public static func width(for count: Int, maxCount: Int = .max, allowToAll: Bool = true) -> CGFloat {
        var width = CGFloat(min(count, maxCount)) * self.size.width
        width += CGFloat(min(count, maxCount)) * 3
        if maxCount != .max, allowToAll {
            width += self.size.width
        }
        return width
    }
    
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    deinit {
        appearTimer?.invalidate()
        tailTimer?.invalidate()
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }

    private var appearTimer: Foundation.Timer?
    private var tailTimer: Foundation.Timer?
    private var isAppearing: Bool = false

    private func collapseTail() {
        guard glassShapes.count == 2 else {
            return
        }
        let tail = glassShapes[1]
        let bar = barRect(size: frame.size)
        let from = tail.frame
        var start: CFTimeInterval?
        isAppearing = true
        tailTimer?.invalidate()
        let timer = Foundation.Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] timer in
            let now = CACurrentMediaTime()
            let begin = start ?? now
            start = begin
            let progress = min(1, (now - begin) / 0.04)
            let suck = CGFloat(progress * progress)
            let size = from.width - (from.width - 8) * suck
            let centerY = from.midY + (bar.midY - from.midY) * suck
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            tail.frame = NSMakeRect(from.midX - size / 2, centerY - size / 2, size, size)
            if #available(macOS 26.0, *) {
                (tail as? NSGlassEffectView)?.cornerRadius = size / 2
            }
            CATransaction.commit()
            if progress >= 1 {
                timer.invalidate()
                tail.isHidden = true
                guard let self else {
                    return
                }
                self.tailTimer = nil
                self.isAppearing = false
                self.hasBubble = false
                self.updateLayout(size: self.frame.size, transition: .immediate)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        tailTimer = timer
    }

    public var canAppearFromCursor: Bool {
        return glassContainer != nil && hasBubble && !TelegramUtilsHooks.shared.isLite(.animations)
    }

    public func appearFromCursor(_ point: NSPoint) {
        guard let glassContainer, glassShapes.count == 2 else {
            return
        }
        let bar = barRect(size: frame.size)
        let tailFinal = glassShapeRects(rect: bar)[1]
        let pill = glassShapes[0]
        let tail = glassShapes[1]
        let radius = bar.height / 2
        let startX = min(max(point.x, bar.minX + radius), bar.maxX - radius)
        let dot = NSMakeRect(startX - 5, min(point.y, frame.height + AppMenuCursorAppearanceExtraHeight - 10) - 9, 10, 10)
        let circle = NSMakeRect(startX - radius, bar.minY, radius * 2, radius * 2)

        isAppearing = true
        layer?.masksToBounds = false
        glassContainer.frame = NSMakeRect(0, 0, frame.width, frame.height + AppMenuCursorAppearanceExtraHeight)
        let savedMask = backgroundView.layer?.mask
        backgroundView.layer?.mask = nil
        backgroundView.layer?.masksToBounds = false
        scrollView.layer?.masksToBounds = false
        scrollView.contentView.layer?.masksToBounds = false

        var revealed: [(NSView, CGFloat)] = documentView.subviews.map { ($0, documentView.convert($0.frame, to: self).midX) }
        revealed.append((showMore, showMore.frame.midX))
        let textMask = CAGradientLayer()
        let hint = aboveTextView
        if let aboveTextView {
            textMask.startPoint = CGPoint(x: 0, y: 0.5)
            textMask.endPoint = CGPoint(x: 1, y: 0.5)
            textMask.colors = [NSColor.clear.cgColor, NSColor.black.cgColor, NSColor.black.cgColor, NSColor.clear.cgColor]
            textMask.frame = .zero
            aboveTextView.layer?.mask = textMask
            aboveTextView.layer?.opacity = 0
        }
        for (view, _) in revealed {
            view.layer?.opacity = 0
        }
        pill.frame = dot
        tail.frame = NSMakeRect(tailFinal.midX, tailFinal.midY, 0, 0)
        if #available(macOS 26.0, *) {
            (pill as? NSGlassEffectView)?.cornerRadius = dot.height / 2
            (tail as? NSGlassEffectView)?.cornerRadius = 0
        }

        let duration: Double = 1.1
        let start = CACurrentMediaTime()
        var revealStarts: [Int: Double] = [:]
        var tailStart: Double?

        let finish: () -> Void = { [weak self] in
            guard let self else {
                return
            }
            self.appearTimer?.invalidate()
            self.appearTimer = nil
            self.isAppearing = false
            for (view, _) in revealed {
                view.layer?.opacity = 1
                view.layer?.transform = CATransform3DIdentity
            }
            self.aboveTextView?.layer?.mask = nil
            self.aboveTextView?.layer?.opacity = 1
            self.backgroundView.layer?.mask = savedMask
            self.backgroundView.layer?.masksToBounds = true
            self.scrollView.layer?.masksToBounds = true
            self.scrollView.contentView.layer?.masksToBounds = true
            self.updateLayout(size: self.frame.size, transition: .immediate)
            self.updateScroll()
        }

        let timer = Foundation.Timer(timeInterval: 1.0 / 120.0, repeats: true) { timer in
            let seconds = CACurrentMediaTime() - start
            if seconds >= duration {
                timer.invalidate()
                finish()
                return
            }
            let rise = bubbleSpring(seconds, omega: 17, damping: 0.55)
            let grow = bubbleSpring(seconds, omega: 22, damping: 0.8)
            let size = dot.height + (circle.height - dot.height) * grow
            let centerY = dot.midY + (circle.midY - dot.midY) * rise
            let base = NSMakeRect(startX - size / 2, centerY - size / 2, size, size)
            let stretch = seconds < 0.1 ? 0 : bubbleSpring(seconds - 0.1, omega: 15, damping: 0.72)
            let left = base.minX + (bar.minX - circle.minX) * stretch
            let right = base.maxX + (bar.maxX - circle.maxX) * stretch
            let current = NSMakeRect(left, base.minY, right - left, base.height)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            pill.frame = current
            if #available(macOS 26.0, *) {
                (pill as? NSGlassEffectView)?.cornerRadius = min(20, current.height / 2)
            }

            if tailStart == nil, current.maxX >= tailFinal.midX + 14 {
                tailStart = seconds
            }
            if let tailStart {
                let pull = bubbleSpring(seconds - tailStart, omega: 16, damping: 0.6)
                let tailSize = 12 + (tailFinal.width - 12) * min(1, pull)
                let tailY = current.midY + (tailFinal.midY - current.midY) * pull
                tail.frame = NSMakeRect(tailFinal.midX - tailSize / 2, tailY - tailSize / 2, tailSize, tailSize)
                if #available(macOS 26.0, *) {
                    (tail as? NSGlassEffectView)?.cornerRadius = tailSize / 2
                }
            }

            if let aboveTextView = hint {
                let text = aboveTextView.frame
                let feather: CGFloat = 24
                let span = NSMakeRect(current.minX - text.minX - feather / 2, 0, current.width + feather, text.height)
                textMask.frame = span
                let edge = NSNumber(value: Double(min(0.5, feather / max(1, span.width))))
                textMask.locations = [0, edge, NSNumber(value: 1 - edge.doubleValue), 1]
                let coverage = min(1, max(0, (text.maxY - current.minY) / max(1, text.height)))
                aboveTextView.layer?.opacity = Float(coverage)
            }

            let offsetY = current.midY - bar.midY
            for (index, (view, centerX)) in revealed.enumerated() {
                if revealStarts[index] == nil, seconds > 0.08, current.minX <= centerX - 8, current.maxX >= centerX + 8 {
                    revealStarts[index] = seconds
                }
                guard let revealStart = revealStarts[index] else {
                    continue
                }
                let progress = 1 - pow(1 - min(1, (seconds - revealStart) / 0.18), 3)
                let scale = 0.6 + 0.4 * progress
                let w = view.frame.width / 2, h = view.frame.height / 2
                var transform = CATransform3DMakeTranslation(w, h + offsetY, 0)
                transform = CATransform3DScale(transform, scale, scale, 1)
                transform = CATransform3DTranslate(transform, -w, -h, 0)
                view.layer?.transform = transform
                view.layer?.opacity = Float(progress)
            }
            CATransaction.commit()
        }
        RunLoop.main.add(timer, forMode: .common)
        appearTimer = timer
    }

    private func barRect(size: NSSize) -> NSRect {
        var rect = size.bounds.insetBy(dx: 10, dy: 10)
        rect.origin.y -= 5
        return rect
    }
    
    public func update(list: [AvailableReactions.Reaction]) {
        
    }
    
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        
        let rect = barRect(size: size)
        
        for subview in documentView.subviews {
            let point: NSPoint
            if let aboveText = aboveText {
                point = NSMakePoint(subview.frame.minX, aboveText.layoutSize.height + 2 + 3)
            } else {
                point = NSMakePoint(subview.frame.minX, 3)
            }
            transition.updateFrame(view: subview, frame: CGRect(origin: point, size: subview.frame.size))
        }
        
        if let aboveTextView = aboveTextView {
            aboveTextView.centerX(y: 8)
        }
        
        
        let documentRect = NSMakeSize(ContextAddReactionsListView.width(for: self.list.count), rect.height).bounds
        var scrollRect = rect
        if documentRect.width < scrollRect.width, self.list.count < 6 {
            scrollRect.size.width = documentRect.width
            scrollRect.origin.x = rect.minX + (rect.width - documentRect.width) / 2
        }
        transition.updateFrame(view: self.documentView, frame: documentRect)
        transition.updateFrame(view: self.scrollView, frame: scrollRect)

        transition.updateFrame(view: self.topGradient, frame: NSMakeRect(10, 0, 10, size.height))
        transition.updateFrame(view: self.bottomGradient, frame: NSMakeRect(rect.width, 0, 10, size.height))
        
        transition.updateFrame(view: visualEffect, frame: size.bounds)
        transition.updateFrame(view: backgroundView, frame: size.bounds)
        if let glassContainer, !isAppearing {
            transition.updateFrame(view: glassContainer, frame: size.bounds)
            let shapes = hasBubble ? glassShapeRects(rect: rect) : [rect]
            for (index, glass) in glassShapes.enumerated() {
                glass.isHidden = index >= shapes.count
            }
            for (glass, shape) in zip(glassShapes, shapes) {
                transition.updateFrame(view: glass, frame: shape)
                if #available(macOS 26.0, *), let glass = glass as? NSGlassEffectView {
                    glass.cornerRadius = min(20, shape.height / 2)
                }
            }
        }
        transition.updateFrame(view: backgroundColorView, frame: size.bounds)
        
        let showMoreInset = ContextAddReactionsListView.showMoreInset
        if let aboveText = aboveText {
            transition.updateFrame(view: showMore, frame: NSMakeRect(rect.maxX - showMore.frame.width - showMoreInset, rect.minY + showMoreInset + aboveText.layoutSize.height + 2, showMore.frame.width, showMore.frame.height))
        } else {
            transition.updateFrame(view: showMore, frame: NSMakeRect(rect.maxX - showMore.frame.width - showMoreInset, rect.minY + showMoreInset, showMore.frame.width, showMore.frame.height))
        }
        
//        transition.updateFrame(layer: maskLayer, frame: rect.size.bounds)
        transition.updateFrame(layer: shadowLayer, frame: size.bounds)

        maskLayer.path = getMaskPath(rect: rect, hasBubble: self.hasBubble)
        
        shadowLayer.path = getMaskPath(rect: rect, hasBubble: self.hasBubble)
        shadowLayer.shadowPath = getMaskPath(rect: rect, hasBubble: self.hasBubble)

        
        if transition.isAnimated {
            maskLayer.animatePath()
        }
    }
    
    private static let showMoreInset: CGFloat = 5
    private static var showMoreSize: CGFloat {
        return size.height + 6 - showMoreInset * 2
    }
    
    private func glassShapeRects(rect: CGRect) -> [CGRect] {
        let bubbleRect = NSMakeRect(rect.width - 40, rect.maxY - 10, 20, 20)
        return [rect, bubbleRect]
    }
    
    private func getMaskPath(rect: CGRect, hasBubble: Bool = true) -> CGPath {
        
        let mutablePath = CGMutablePath()
        mutablePath.addRoundedRect(in: rect, cornerWidth: 20, cornerHeight: 20)
        
        if hasBubble {
            for shape in glassShapeRects(rect: rect).dropFirst() {
                mutablePath.addRoundedRect(in: shape, cornerWidth: shape.width / 2, cornerHeight: shape.width / 2)
            }
        }

        return mutablePath
    }
}
//





//
//                        let viewRect = view.convert(rect, from: itemView)
//                        let dst = 50 - min(max(0, inside.distance(p2: NSMakePoint(viewRect.midX, viewRect.midY))), 50)
//
//
//                        let multiplier = log2(mappingRange(dst, 0, 50, 1, 100))
//
//                        NSLog("\(log2(mappingRange(dst, 0, 50, 1, 100)))")
                        
//                        let updated = base.insetBy(dx: -3 * (multiplier / 7), dy: -3 * (multiplier / 7))

private func bubbleSpring(_ seconds: Double, omega: Double, damping: Double) -> CGFloat {
    let dampedOmega = omega * (1 - damping * damping).squareRoot()
    return CGFloat(1 - exp(-damping * omega * seconds) * (cos(dampedOmega * seconds) + damping * omega / dampedOmega * sin(dampedOmega * seconds)))
}
