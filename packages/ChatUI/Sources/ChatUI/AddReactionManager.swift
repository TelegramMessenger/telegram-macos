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

public final class ContextAddReactionsListView : View, StickerFramesCollector  {
    
    
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
        
        private var selectionView : View?
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
                let view = View()
                self.selectionView = view
                view.frame = NSMakeRect(0, 0, 34, 34)
                view.layer?.cornerRadius = view.frame.height / 2
                view.backgroundColor = theme.colors.vibrant.mixedWith(NSColor(0x000000), alpha: 0.1)
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
        public required init(frame frameRect: NSRect, theme: TelegramPresentationTheme) {
            super.init(frame: frameRect)
            self.backgroundColor = theme.colors.vibrant.mixedWith(NSColor(0x000000), alpha: 0.1)
            self.scaleOnClick = true
            self.layer?.cornerRadius = frameRect.height / 2
            addSubview(self.imageView)
            self.imageView.isAccessibilityDecorative = true
            self.setAccessibilityLabel(strings().voiceOverCommonMore)
            self.imageView.image = theme.icons.reactions_show_more
            self.imageView.sizeToFit()
        }
        
        public override func layout() {
            super.layout()
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
    private let radiusLayer: CGFloat?
    
    private var aboveTextView: TextView?
    
    private let showMore: ShowMore
    private let revealReactions:((ContextAddReactionsListView & StickerFramesCollector)->Void)?
    
    private let maskLayer = SimpleShapeLayer()
    private let backgroundColorView = View()
    private let shadowLayer = SimpleShapeLayer()
    private let presentation: TelegramPresentationTheme
    private var hasBubble: Bool
    private let aboveText: TextViewLayout?
    public required init(frame frameRect: NSRect, context: any AccountContextProtocol, list: [ContextReaction], add:@escaping(MessageReaction.Reaction, Bool, NSRect?)->Void, addLarge: ((MessageReaction.Reaction, NSRect?)->Void)? = nil, radiusLayer: CGFloat? = 15, revealReactions:((ContextAddReactionsListView & StickerFramesCollector)->Void)? = nil, presentation: TelegramPresentationTheme = theme, hasBubble: Bool = true, aboveText: TextViewLayout? = nil, message: Message? = nil, parentWindow: Window? = nil) {
        self.list = list
        self.showMore = ShowMore(frame: NSMakeRect(0, 0, 34, 34), theme: presentation)
        self.revealReactions = revealReactions
        self.radiusLayer = radiusLayer
        self.presentation = presentation
        self.hasBubble = hasBubble
        self.aboveText = aboveText
        super.init(frame: frameRect)
        
        
        let theme = presentation
        
        backgroundView.layer?.mask = maskLayer
        if !TelegramUtilsHooks.shared.isLite(.blur) {
            self.visualEffect.state = .active
            self.visualEffect.wantsLayer = true
            self.visualEffect.blendingMode = hasBubble ? .behindWindow : .withinWindow
        }
        
        
        
        showMore.isHidden = revealReactions == nil
        
        showMore.set(handler: { [weak self] control in
            if let view = self {
                view.hasBubble = false
                view.updateLayout(size: view.frame.size, transition: .immediate)
                view.showMore.startLoading()
                revealReactions?(view)
            }
        }, for: .Click)
        
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOffset = CGSize(width: 0.0, height: 0)
        shadowLayer.shadowRadius = 2
        shadowLayer.shadowOpacity = 0.2
        shadowLayer.fillColor = NSColor.clear.cgColor
        self.layer?.addSublayer(shadowLayer)

        bottomGradient.shadowBackground = theme.colors.background.withAlphaComponent(1)
        bottomGradient.direction = .horizontal(true)
        topGradient.shadowBackground = theme.colors.background.withAlphaComponent(1)
        topGradient.direction = .horizontal(false)
        
        if !TelegramUtilsHooks.shared.isLite(.blur) {
            visualEffect.material = theme.colors.isDark ? .dark : .mediumLight
        }
        
        if #available(macOS 11.0, *), !TelegramUtilsHooks.shared.isLite(.blur) {
            backgroundColorView.backgroundColor = theme.colors.background.withAlphaComponent(0.7)
        } else {
            backgroundColorView.backgroundColor = theme.colors.background
        }
        if #available(macOS 11.0, *), !TelegramUtilsHooks.shared.isLite(.blur) {
            backgroundView.addSubview(visualEffect)
        }
        backgroundView.addSubview(backgroundColorView)

        
        
        addSubview(backgroundView)
        backgroundView.addSubview(scrollView)
        addSubview(showMore)
        
        backgroundView.addSubview(topGradient)
        backgroundView.addSubview(bottomGradient)

        
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
        if let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
        }
    }
    
    public func update(list: [AvailableReactions.Reaction]) {
        
    }
    
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        
        var rect = size.bounds.insetBy(dx: 10, dy: 10)
        rect.origin.y -= 5
        
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
        transition.updateFrame(view: backgroundColorView, frame: size.bounds)
        
        if let aboveText = aboveText {
            transition.updateFrame(view: showMore, frame: NSMakeRect(rect.maxX - showMore.frame.width - 3, rect.minY + 3 + aboveText.layoutSize.height + 2, showMore.frame.width, showMore.frame.height))
        } else {
            transition.updateFrame(view: showMore, frame: NSMakeRect(rect.maxX - showMore.frame.width - 3, rect.minY + 3, showMore.frame.width, showMore.frame.height))
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
    
    private func getMaskPath(rect: CGRect, hasBubble: Bool = true) -> CGPath {
        
        let mutablePath = CGMutablePath()
        mutablePath.addRoundedRect(in: rect, cornerWidth: 20, cornerHeight: 20)
        
        if hasBubble {
            let bubbleRect = NSMakeRect(rect.width - 40, rect.maxY - 10, 20, 20)
            mutablePath.addRoundedRect(in: bubbleRect, cornerWidth: bubbleRect.width / 2, cornerHeight: bubbleRect.width / 2)
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
                        
