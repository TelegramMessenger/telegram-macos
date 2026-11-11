import Cocoa
import TGUIKit
import ComponentsUI
import TelegramCore
import TelegramUtils
import InlineStickerLayer
import SwiftSignalKit





final class ChatRightIconLayer: SimpleLayer {
    var image: CGImage? {
        didSet {
            contents = image
        }
    }

    func sizeToFit() {
        if let image = image {
            bounds = CGRect(origin: .zero, size: image.backingSize)
        }
    }
}

final class ChatRightTextLayer: SimpleLayer {
    private let drawLayer = TextViewLayer()

    var textLayout: TextViewLayout? {
        return drawLayer.textLayout
    }

    override init() {
        super.init()
        anchorPoint = .zero
        zPosition = 1
        masksToBounds = false
        addSublayer(drawLayer)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ layout: TextViewLayout) {
        bounds = CGRect(origin: .zero, size: layout.layoutSize)
        drawLayer.update(layout, size: bounds.size)
        updateDrawLayer()
        drawLayer.setNeedsDisplay()
    }

    func updateDrawLayer() {
        if drawLayer.textSize != bounds.size {
            drawLayer.textSize = bounds.size
            drawLayer.setNeedsDisplay()
        }
        let drawingBounds = bounds.insetBy(dx: -2, dy: -3)
        let drawingPosition = CGPoint(x: bounds.midX, y: bounds.midY)
        if drawLayer.bounds != drawingBounds {
            drawLayer.bounds = drawingBounds
        }
        if drawLayer.position != drawingPosition {
            drawLayer.position = drawingPosition
        }
    }

    func updateScale(_ scale: CGFloat) {
        drawLayer.contentsScale = scale
        drawLayer.setNeedsDisplay()
    }
}

public class ChatRightView: View, ViewDisplayDelegate {

    public let contentLayer = SimpleLayer()
    public private(set) var isContentHosted = false

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        contentLayer.anchorPoint = .zero
        contentLayer.zPosition = 1
        contentLayer.frame = bounds
        layer?.addSublayer(contentLayer)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public var flightLayer: CALayer? {
        return isContentHosted ? contentLayer : layer
    }

    public var canHostContent: Bool {
        return blurBackground == nil && subviews.allSatisfy { $0 === visualEffect }
    }

    public func hostContent(in parent: CALayer) {
        if !isContentHosted {
            isContentHosted = true
            contentLayer.masksToBounds = true
            contentLayer.isOpaque = true
            contentLayer.edgeAntialiasingMask = []
            if #available(macOS 10.15, *) { contentLayer.cornerCurve = .continuous }
            syncHostedAppearance()
        }
        if contentLayer.superlayer !== parent {
            parent.addSublayer(contentLayer)
        }
    }

    public func restoreContent() {
        guard isContentHosted else { return }
        isContentHosted = false
        contentLayer.removeAllAnimations()
        contentLayer.masksToBounds = false
        contentLayer.isOpaque = false
        contentLayer.edgeAntialiasingMask = [.layerLeftEdge, .layerRightEdge, .layerBottomEdge, .layerTopEdge]
        contentLayer.backgroundColor = nil
        contentLayer.cornerRadius = 0
        contentLayer.opacity = 1
        contentLayer.isHidden = false
        contentLayer.frame = bounds
        layer?.addSublayer(contentLayer)
    }

    public func setLayerCornerRadius(_ radius: CGFloat) {
        layer?.cornerRadius = radius
        if isContentHosted, contentLayer.cornerRadius != radius {
            contentLayer.cornerRadius = radius
        }
    }

    public func updateHostedFrame(_ frame: NSRect, transition: ContainedViewLayoutTransition) {
        guard isContentHosted else { return }
        if self.frame != frame {
            self.frame = frame
        }
        #if DEBUG
        transition.updateFrame(layer: contentLayer, frame: frame.offsetBy(dx: ChatRowView.parityMutation, dy: 0))
        #else
        transition.updateFrame(layer: contentLayer, frame: frame)
        #endif
    }

    private func syncHostedAppearance() {
        guard isContentHosted, let layer else { return }
        contentLayer.backgroundColor = layer.backgroundColor
        contentLayer.cornerRadius = layer.cornerRadius
        contentLayer.opacity = layer.opacity
        contentLayer.isHidden = isHidden
    }

    public override var backgroundColor: NSColor {
        didSet {
            if isContentHosted {
                contentLayer.backgroundColor = layer?.backgroundColor
            }
        }
    }

    public override var isHidden: Bool {
        didSet {
            if isContentHosted, contentLayer.isHidden != isHidden {
                contentLayer.isHidden = isHidden
            }
        }
    }

    public override func change(opacity to: CGFloat, animated: Bool = true, _ save: Bool = true, removeOnCompletion: Bool = true, duration: Double = 0.2, timingFunction: CAMediaTimingFunctionName = .easeOut, completion: ((Bool) -> Void)? = nil) {
        super.change(opacity: to, animated: animated, save, removeOnCompletion: removeOnCompletion, duration: duration, timingFunction: timingFunction, completion: completion)
        guard isContentHosted, Float(to) != contentLayer.opacity else { return }
        if animated {
            var from = CGFloat(contentLayer.opacity)
            if let presentation = contentLayer.presentation(), contentLayer.animation(forKey: "opacity") != nil {
                from = CGFloat(presentation.opacity)
            }
            contentLayer.animateAlpha(from: from, to: to, duration: duration, timingFunction: timingFunction, removeOnCompletion: removeOnCompletion)
        } else {
            contentLayer.removeAnimation(forKey: "opacity")
        }
        if save {
            contentLayer.opacity = Float(to)
        }
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if !isContentHosted, contentLayer.frame.size != newSize {
            contentLayer.frame = bounds
        }
    }

    static func makeTextLayer(_ frame: NSRect) -> ChatRightTextLayer {
        let layer = ChatRightTextLayer()
        layer.frame = frame
        return layer
    }

    static func makeIconLayer(_ frame: NSRect) -> ChatRightIconLayer {
        let layer = ChatRightIconLayer()
        layer.anchorPoint = .zero
        layer.zPosition = 1
        layer.masksToBounds = true
        layer.frame = frame
        return layer
    }

    static func removeIcon(_ layer: CALayer, animated: Bool) {
        if animated {
            let from = layer.presentation()?.opacity ?? layer.opacity
            layer.animateAlpha(from: CGFloat(from), to: 0, duration: 0.2, timingFunction: .easeOut, removeOnCompletion: false, completion: { [weak layer] _ in
                layer?.removeFromSuperlayer()
            })
            layer.animateScaleCenter(from: 1, to: 0.01, duration: 0.2, removeOnCompletion: false, timingFunction: .easeOut)
        } else {
            layer.removeFromSuperlayer()
        }
    }

    
    
    public struct Frames {
        public private(set) var state:NSRect?
        public private(set) var read:NSRect?
        public private(set) var sending:NSRect?
        public private(set) var reactions: NSRect?
        public private(set) var replyCount: NSRect?
        public private(set) var replyImage: NSRect?
        public private(set) var viewsCount: NSRect?
        public private(set) var viewsImage: NSRect?
        public private(set) var postAuthor: NSRect?
        public private(set) var pin: NSRect?
        public private(set) var edit: NSRect?
        public private(set) var paidMessageCount: NSRect?
        public private(set) var paidMessageImage: NSRect?
        public private(set) var diceStakeCount: NSRect?
        public private(set) var diceStakeImage: NSRect?
        public private(set) var date: NSRect?
        public private(set) var failed: NSRect?
        public private(set) var effect: NSRect?
        private let isStateOverlay: Bool
        public private(set) var width: CGFloat = 0
        public init(_ item: ChatRowItem, size: NSSize) {
            
            self.isStateOverlay = item.isStateOverlayLayout
            let stateIsEnd = item.isBubbled && !item.isIncoming
                        
            var x: CGFloat = item.isStateOverlayLayout ? 4 : 0

            if let _ = item.messageEffect {
                var rect = size.bounds.focus(NSMakeSize(14, 14))
                rect.origin.x = x + 2
                rect.origin.y += 1
                self.effect = rect
                x = rect.maxX
            }

            if let views = item.replyCount {
                var rect_i = size.bounds.focus(item.presentation.chat.repliesCountIcon(item).backingSize)
                rect_i.origin.x = x + 2
                if item.isBubbled {
                    rect_i.origin.y -= 1
                }
                x = rect_i.maxX
                var rect_t = size.bounds.focus(views.layoutSize)
                rect_t.origin.x = x + 2
                x = rect_t.maxX
                
                self.replyImage = rect_i
                self.replyCount = rect_t
            }
            
            if item.isPinned {
                var rect = size.bounds.focus(item.presentation.chat.messagePinnedIcon(item).backingSize)
                rect.origin.x = x + 2
                self.pin = rect
                x = rect.maxX
            }
            
            if let views = item.channelViews {
                var rect_i = size.bounds.focus(item.presentation.chat.channelViewsIcon(item).backingSize)
                rect_i.origin.x = x + 2
                x = rect_i.maxX
                var rect_t = size.bounds.focus(views.layoutSize)
                rect_t.origin.x = x + 2
                x = rect_t.maxX
                
                self.viewsImage = rect_i
                self.viewsCount = rect_t
            }
            
            if let postAuthor = item.postAuthor {
                var rect = size.bounds.focus(postAuthor.layoutSize)
                rect.origin.x = x + 2
                self.postAuthor = rect
                x = rect.maxX
            }
            
            if let editLabel = item.editedLabel {
                var rect = size.bounds.focus(editLabel.layoutSize)
                rect.origin.x = x + 2
                self.edit = rect
                x = rect.maxX
            }
            
            if let paidMessage = item.paidMessage {
                var rect_i = size.bounds.focus(item.presentation.chat.paidMessageIcon(item).backingSize)
                rect_i.origin.x = x + 2
                rect_i.origin.y -= 1
                x = rect_i.maxX
                var rect_t = size.bounds.focus(paidMessage.layoutSize)
                rect_t.origin.x = x + 2
                x = rect_t.maxX
                
                self.paidMessageImage = rect_i
                self.paidMessageCount = rect_t
            }
            
            if item.isFailed {
                var rect = size.bounds.focus(item.presentation.icons.sentFailed.backingSize)
                rect.origin.x = x + 2
                self.failed = rect
                x = rect.maxX
            }
            
            if stateIsEnd {
                self.date = makeDate(item, size, &x)
            }
            
            self.state = makeState(item, size, &x)
            self.read = makeRead(item, size, &x)
            self.sending = makeSending(item, size, &x)

            if !stateIsEnd {
                if self.read == nil && (self.state != nil || self.sending != nil)  {
                    x += 4
                }
                self.date = makeDate(item, size, &x)
            }

            if let diceStake = item.diceStake {
                var rect_i = size.bounds.focus(item.presentation.chat.diceStakeIcon(item).backingSize)
                rect_i.origin.x = x + 2
                rect_i.origin.y -= 1
                x = rect_i.maxX
                var rect_t = size.bounds.focus(diceStake.layoutSize)
                rect_t.origin.x = x
                x = rect_t.maxX

                self.diceStakeImage = rect_i
                self.diceStakeCount = rect_t
            }
            self.width = measureWidth()
        }
        
        private func makeDate(_ item: ChatRowItem, _ size: NSSize, _ x: inout CGFloat) -> NSRect? {
            if let date = item.date {
                var rect = size.bounds.focus(date.layoutSize)
                rect.origin.x = x + 2
                x = rect.maxX
                return rect
            }
            return nil
        }
        
        private func makeState(_ item: ChatRowItem, _ size: NSSize, _ x: inout CGFloat) -> CGRect? {
            let hasState = !item.isIncoming && !item.isUnsent && !item.isFailed && !item.chatInteraction.isLogInteraction
            if hasState {
                var rect = size.bounds.focus(item.presentation.chat.stateStateIcon(item).backingSize)
                rect.origin.x = x + 2
                x = rect.maxX
                return rect
            }
            return nil
        }
        private func makeRead(_ item: ChatRowItem, _ size: NSSize, _ x: inout CGFloat) -> CGRect? {
            let hasState = !item.isIncoming && !item.isUnsent && !item.isFailed && !item.chatInteraction.isLogInteraction
            let hasRead = hasState && item.isRead && !item.hasSource
            if hasRead {
                var rect = size.bounds.focus(item.presentation.chat.readStateIcon(item).backingSize)
                rect.origin.x = x - 8
                x = rect.maxX
                return rect
            }
            return nil
        }
        private func makeSending(_ item: ChatRowItem, _ size: NSSize, _ x: inout CGFloat) -> CGRect? {
            let isSending = item.isUnsent && !item.isFailed
            if isSending {
                var rect = size.bounds.focus(NSMakeSize(12, 12))
                rect.origin.x = x + 2
                if isStateOverlay {
                    if System.backingScale > 1 {
                        rect.origin.y -= 0.5
                    }
                    rect.origin.x += 1
                }
                x = rect.maxX
                return rect
            }
            return nil
        }
        
        private func measureWidth() -> CGFloat {
            var rightmost: NSRect?
            func include(_ rect: NSRect?) {
                guard let rect = rect else {
                    return
                }
                if let current = rightmost {
                    if current.maxX < rect.maxX {
                        rightmost = rect
                    }
                } else {
                    rightmost = rect
                }
            }
            include(self.state)
            include(self.read)
            include(self.sending)
            include(self.effect)
            include(self.diceStakeCount)
            include(self.diceStakeImage)
            include(self.paidMessageCount)
            include(self.paidMessageImage)
            include(self.replyCount)
            include(self.viewsCount)
            include(self.viewsImage)
            include(self.postAuthor)
            include(self.pin)
            include(self.edit)
            include(self.date)

            var max = rightmost ?? .zero
            if max == self.state || max == self.sending {
                max.origin.x += 4
            }
            if isStateOverlay {
                return max.maxX + 4
            } else {
                return max.maxX + 1
            }
                
        }
    }
    
    private var visualEffect: VisualEffect? = nil
    public var blurBackground: NSColor? = nil {
        didSet {
            if blurBackground != oldValue {
                updateBackgroundBlur()
            }
            if blurBackground != nil {
                self.backgroundColor = .clear
            }
        }
    }
    
    private func updateBackgroundBlur() {
        if let blurBackground, let visualEffect {
            visualEffect.isHidden = false
            visualEffect.bgColor = blurBackground
        } else if blurBackground == nil, let visualEffect {
            visualEffect.isHidden = true
        } else {
            updateVisualEffectBackground(for: self, visualEffect: &visualEffect, blurBackground: blurBackground)
        }
        needsLayout = true
    }
    
    private var stateView: ChatRightIconLayer?
    private var readImageView: ChatRightIconLayer?
    private var sendingView:SendingClockProgress?
    public private(set) var effectView: InlineStickerView?
    public private(set) var effectTextView: TextView?
    private var replyCountView: ChatRightTextLayer?
    private var replyCountImage: ChatRightIconLayer?
    private var paidMessageCountView: ChatRightTextLayer?
    private var paidMessageImage: ChatRightIconLayer?
    private var diceStakeCountView: ChatRightTextLayer?
    private var diceStakeImageView: ChatRightIconLayer?
    private var viewsCountView: ChatRightTextLayer?
    private var viewsImageView: ChatRightIconLayer?
    private var postAuthorView: ChatRightTextLayer?
    private var pinView: ChatRightIconLayer?
    private var editView: ChatRightTextLayer?
    private var dateView: ChatRightTextLayer?
    private var failedView: ChatRightIconLayer?
    private weak var item:ChatRowItem?
    private var tooltipTimer: SwiftSignalKit.Timer?
    
    public var isReversed: Bool {
        guard let item = item else {return false}
        return item.isBubbled && !item.isIncoming
    }
    
    private var stacked: [Frames] = []
    
    public func set(item:ChatRowItem, animated:Bool) {
                
        bindTooltip(item)
        
        guard let frames = item.rightFrames else {
            return
        }
        
        let findState:([Frames])->NSRect? = { stake in
            for value in stake.reversed() {
                if value.state != nil {
                    return value.state
                }
            }
            return nil
        }
        let findSending:([Frames])->NSRect? = { stake in
            for value in stake.reversed() {
                if value.sending != nil {
                    return value.sending
                }
            }
            return nil
        }
        
        if let effect = item.messageEffect {
            let found = item.context.reactions.available?.enabled.first(where: { $0.value.string == effect.emoticon })?.staticIcon
            if effect.effectAnimation != nil || (found != nil && effect.effectAnimation == nil) {
                if let effectTextView {
                    performSubviewRemoval(effectTextView, animated: animated)
                    self.effectTextView = nil
                }
                
                let newFileId = found?.fileId.id ?? effect.effectSticker.fileId.id

                if self.effectView?.animateLayer.fileId != newFileId {
                    let file = found?._parse() ?? effect.effectSticker._parse()
                    if let view = self.effectView {
                        performSubviewRemoval(view, animated: animated)
                    }
                    let current = InlineStickerView(account: item.context.account, file: file, size: NSMakeSize(12, 12), playPolicy: .framesCount(1))
                    current.userInteractionEnabled = true
                    current.set(handler: { [weak self] _ in
                        self?.item?.invokeMessageEffect()
                    }, for: .SingleClick)
                    self.effectView = current
                    addSubview(current)
                }
            } else {
                if let effectView {
                    performSubviewRemoval(effectView, animated: animated)
                    self.effectView = nil
                }
                let current: TextView
                if let view = self.effectTextView {
                    current = view
                } else {
                    current = TextView()
                    current.userInteractionEnabled = true
                    current.isSelectable = false
                    self.effectTextView = current
                    
                    current.set(handler: { [weak self] _ in
                        self?.item?.invokeMessageEffect()
                    }, for: .SingleClick)
                    
                    addSubview(current)
                }
                let layout = TextViewLayout(.initialize(string: effect.emoticon, font: .normal(10)))
                layout.measure(width: .greatestFiniteMagnitude)
                current.update(layout)
            }
            
        } else {
            if let view = self.effectView {
                self.effectView = nil
                performSubviewRemoval(view, animated: animated, scale: true)
            }
            if let view = self.effectTextView {
                self.effectTextView = nil
                performSubviewRemoval(view, animated: animated, scale: true)
            }
        }
        if let sendingRect = frames.sending {
            if self.sendingView == nil {
                self.sendingView = SendingClockProgress(frame: findState(stacked) ?? sendingRect)
                addSubview(sendingView!)
                if animated {
                    self.sendingView?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    self.sendingView?.layer?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2)
                }
            }
            let f = item.presentation.chat.sendingFrameIcon(item)
            let h = item.presentation.chat.sendingHourIcon(item)
            let m = item.presentation.chat.sendingMinIcon(item)

            self.sendingView?.set(frame: f, hour: h, minute: m)
        } else {
            if let view = self.sendingView {
                self.sendingView = nil
                performSubviewRemoval(view, animated: animated, scale: true)
            }
        }
        
                
        if let stateRect = frames.state {
            if self.stateView == nil {
                stateView = ChatRightView.makeIconLayer(findSending(stacked) ?? stateRect)
                self.contentLayer.addSublayer(self.stateView!)
                if animated {
                    self.stateView?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    self.stateView?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2)
                }
            }
            let stateImage = item.presentation.chat.stateStateIcon(item)
            stateView?.image = stateImage
            stateView?.sizeToFit()
        } else {
            if let view = self.stateView {
                self.stateView = nil
                ChatRightView.removeIcon(view, animated: animated)
            }
        }
        if let readRect = frames.read {
            if readImageView == nil {
                readImageView = ChatRightView.makeIconLayer(readRect)
                self.contentLayer.addSublayer(self.readImageView!)
                if animated {
                    self.readImageView?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    self.readImageView?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2)
                }
            }
            self.readImageView?.image = item.presentation.chat.readStateIcon(item)
            self.readImageView?.sizeToFit()
        } else {
            if let view = self.readImageView {
                self.readImageView = nil
                ChatRightView.removeIcon(view, animated: animated)
            }
        }
        
        if let replyCount = item.replyCount, let replyImageRect = frames.replyImage, let replyCountRect = frames.replyCount {
            if self.replyCountView == nil {
                self.replyCountView = ChatRightView.makeTextLayer(replyCountRect)
                self.contentLayer.addSublayer(self.replyCountView!)
                if animated {
                    self.replyCountView?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    self.replyCountView?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2)
                }
            }
            self.replyCountView?.update(replyCount)
            
            if self.replyCountImage == nil {
                self.replyCountImage = ChatRightView.makeIconLayer(replyImageRect)
                self.contentLayer.addSublayer(self.replyCountImage!)
                if animated {
                    self.replyCountImage?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    self.replyCountImage?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2)
                }
            }
            self.replyCountImage?.image = item.presentation.chat.repliesCountIcon(item)
            self.replyCountImage?.sizeToFit()
            
        } else {
            if let view = self.replyCountView {
                self.replyCountView = nil
                ChatRightView.removeIcon(view, animated: animated)
            }
            if let view = self.replyCountImage {
                self.replyCountImage = nil
                ChatRightView.removeIcon(view, animated: animated)
            }
        }
        
        if let paidMessage = item.paidMessage, let paidMessageImage = frames.paidMessageImage, let paidMessageCount = frames.paidMessageCount {
            if self.paidMessageCountView == nil {
                self.paidMessageCountView = ChatRightView.makeTextLayer(paidMessageCount)
                self.contentLayer.addSublayer(self.paidMessageCountView!)
                if animated {
                    self.paidMessageCountView?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    self.paidMessageCountView?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2)
                }
            }
            self.paidMessageCountView?.update(paidMessage)
            
            if self.paidMessageImage == nil {
                self.paidMessageImage = ChatRightView.makeIconLayer(paidMessageImage)
                self.contentLayer.addSublayer(self.paidMessageImage!)
                if animated {
                    self.paidMessageImage?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    self.paidMessageImage?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2)
                }
            }
            self.paidMessageImage?.image = item.presentation.chat.paidMessageIcon(item)
            self.paidMessageImage?.sizeToFit()
            
        } else {
            if let view = self.paidMessageCountView {
                self.paidMessageCountView = nil
                ChatRightView.removeIcon(view, animated: animated)
            }
            if let view = self.paidMessageImage {
                self.paidMessageImage = nil
                ChatRightView.removeIcon(view, animated: animated)
            }
        }

        if let diceStake = item.diceStake, let diceStakeImage = frames.diceStakeImage, let diceStakeCount = frames.diceStakeCount {
            if self.diceStakeCountView == nil {
                self.diceStakeCountView = ChatRightView.makeTextLayer(diceStakeCount)
                self.contentLayer.addSublayer(self.diceStakeCountView!)
                if animated {
                    self.diceStakeCountView?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    self.diceStakeCountView?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2)
                }
            }
            self.diceStakeCountView?.update(diceStake)

            if self.diceStakeImageView == nil {
                self.diceStakeImageView = ChatRightView.makeIconLayer(diceStakeImage)
                self.contentLayer.addSublayer(self.diceStakeImageView!)
                if animated {
                    self.diceStakeImageView?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    self.diceStakeImageView?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2)
                }
            }
            self.diceStakeImageView?.image = item.presentation.chat.diceStakeIcon(item)
            self.diceStakeImageView?.sizeToFit()

        } else {
            if let view = self.diceStakeCountView {
                self.diceStakeCountView = nil
                ChatRightView.removeIcon(view, animated: animated)
            }
            if let view = self.diceStakeImageView {
                self.diceStakeImageView = nil
                ChatRightView.removeIcon(view, animated: animated)
            }
        }

        if let pinRect = frames.pin {
            if self.pinView == nil {
                self.pinView = ChatRightView.makeIconLayer(pinRect)
                self.contentLayer.addSublayer(self.pinView!)
                if animated {
                    self.pinView?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    self.pinView?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2)
                }
            }
            self.pinView?.image = item.presentation.chat.messagePinnedIcon(item)
            self.pinView?.sizeToFit()
        } else {
            if let view = self.pinView {
                self.pinView = nil
                ChatRightView.removeIcon(view, animated: animated)
            }
        }
        
        
        
        if let date = item.date, let dateRect = frames.date {
            if self.dateView == nil {
                self.dateView = ChatRightView.makeTextLayer(dateRect)
                self.contentLayer.addSublayer(self.dateView!)
                if animated {
                    self.dateView?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    self.dateView?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2)
                }
            }
            self.dateView?.update(date)
        } else {
            if let view = self.dateView {
                self.dateView = nil
                ChatRightView.removeIcon(view, animated: animated)
            }
        }
        
        if let failedRect = frames.failed {
            if self.failedView == nil {
                self.failedView = ChatRightView.makeIconLayer(failedRect)
                self.contentLayer.addSublayer(self.failedView!)
                if animated {
                    self.failedView?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    self.failedView?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2)
                }
            }
            self.failedView?.image = item.presentation.icons.sentFailed
            self.failedView?.sizeToFit()
        } else {
            if let view = self.failedView {
                self.failedView = nil
                ChatRightView.removeIcon(view, animated: animated)
            }
        }
        
        if let editedLabel = item.editedLabel, let editRect = frames.edit {
            if self.editView == nil {
                self.editView = ChatRightView.makeTextLayer(editRect)
                self.contentLayer.addSublayer(self.editView!)
                if animated {
                    self.editView?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    self.editView?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2)
                }
            }
            self.editView?.update(editedLabel)
        } else {
            if let view = self.editView {
                self.editView = nil
                ChatRightView.removeIcon(view, animated: animated)
            }
        }
        if let channelViews = item.channelViews, let viewsImageRect = frames.viewsImage, let viewsCountRect = frames.viewsCount {
            if self.viewsCountView == nil {
                self.viewsCountView = ChatRightView.makeTextLayer(viewsCountRect)
                self.contentLayer.addSublayer(self.viewsCountView!)
                if animated {
                    self.viewsCountView?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    self.viewsCountView?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2)
                }
            }
            self.viewsCountView?.update(channelViews)
            
            if self.viewsImageView == nil {
                self.viewsImageView = ChatRightView.makeIconLayer(viewsImageRect)
                self.contentLayer.addSublayer(self.viewsImageView!)
                if animated {
                    self.viewsImageView?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    self.viewsImageView?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2)
                }
            }
            self.viewsImageView?.image = item.presentation.chat.channelViewsIcon(item)
            self.viewsImageView?.sizeToFit()
            
        } else {
            if let view = self.viewsCountView {
                self.viewsCountView = nil
                ChatRightView.removeIcon(view, animated: animated)
            }
            if let view = self.viewsImageView {
                self.viewsImageView = nil
                ChatRightView.removeIcon(view, animated: animated)
            }
        }
        
        if let postAuthor = item.postAuthor, let postAuthorRect = frames.postAuthor {
            if self.postAuthorView == nil {
                self.postAuthorView = ChatRightView.makeTextLayer(postAuthorRect)
                self.contentLayer.addSublayer(self.postAuthorView!)
                if animated {
                    self.postAuthorView?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    self.postAuthorView?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2)
                }
            }
            self.postAuthorView?.update(postAuthor)
        } else {
            if let view = self.postAuthorView {
                self.postAuthorView = nil
                ChatRightView.removeIcon(view, animated: animated)
            }
        }
        
        stacked.append(frames)
        
    }
    
    
    public func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        if let visualEffect = visualEffect {
            transition.updateFrame(view: visualEffect, frame: size.bounds)
        }
        if let visualEffect = visualEffect {
            transition.updateFrame(view: visualEffect, frame: size.bounds)
        }
        
        guard let item = self.item else {
            return
        }
        
        guard let frames = item.rightFrames else {
            return
        }
        
        
        if let frame = frames.effect, let view = effectView {
            transition.updateFrame(view: view, frame: frame)
        }
        if let frame = frames.effect, let view = effectTextView {
            transition.updateFrame(view: view, frame: frame.offsetBy(dx: -1, dy: 0))
        }
        if let frame = frames.pin, let view = pinView {
            transition.updateFrame(layer: view, frame: frame)
        }
        if let frame = frames.failed, let view = failedView {
            transition.updateFrame(layer: view, frame: frame)
        }
        if let frame = frames.edit, let view = editView {
            transition.updateFrame(layer: view, frame: frame)
            view.updateDrawLayer()
        }
        if let frame = frames.state, let view = stateView {
            transition.updateFrame(layer: view, frame: frame)
        }
        if let frame = frames.read, let view = readImageView {
            transition.updateFrame(layer: view, frame: frame)
        }
        if let frame = frames.date, let view = dateView {
            transition.updateFrame(layer: view, frame: frame)
            view.updateDrawLayer()
        }
        if let frame = frames.postAuthor, let view = postAuthorView {
            transition.updateFrame(layer: view, frame: frame)
            view.updateDrawLayer()
        }
        if let frame = frames.sending, let view = sendingView {
            transition.updateFrame(view: view, frame: frame)
        }
        if let frame = frames.viewsImage, let view = viewsImageView {
            transition.updateFrame(layer: view, frame: frame)
        }
        if let frame = frames.viewsCount, let view = viewsCountView {
            transition.updateFrame(layer: view, frame: frame)
            view.updateDrawLayer()
        }
        if let frame = frames.replyCount, let view = replyCountView {
            transition.updateFrame(layer: view, frame: frame)
            view.updateDrawLayer()
        }
        if let frame = frames.replyImage, let view = replyCountImage {
            transition.updateFrame(layer: view, frame: frame)
        }
        if let frame = frames.paidMessageImage, let view = paidMessageImage {
            transition.updateFrame(layer: view, frame: frame)
        }
        if let frame = frames.paidMessageCount, let view = paidMessageCountView {
            transition.updateFrame(layer: view, frame: frame)
            view.updateDrawLayer()
        }
        if let frame = frames.diceStakeImage, let view = diceStakeImageView {
            transition.updateFrame(layer: view, frame: frame)
        }
        if let frame = frames.diceStakeCount, let view = diceStakeCountView {
            transition.updateFrame(layer: view, frame: frame)
            view.updateDrawLayer()
        }
    }

    public override func layout() {
        super.layout()
        
        updateLayout(size: self.frame.size, transition: .immediate)
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        for layer in [replyCountView, paidMessageCountView, diceStakeCountView, dateView, editView, viewsCountView, postAuthorView] {
            layer?.updateScale(backingScaleFactor)
        }
    }
    
    private func bindTooltip(_ item: ChatRowItem) {
        if self.item !== item {
            let wasRunning = tooltipTimer != nil
            cancelTooltipTimer()
            self.item = item
            updateTooltipText(item.fullDate)
            if wasRunning {
                startTooltipTimerIfNeeded()
            }
        } else if tooltipTimer == nil {
            updateTooltipText(item.fullDate)
        }
    }

    private var canUpdateTooltip: Bool {
        return window != nil && !isHiddenOrHasHiddenAncestor && !visibleRect.isEmpty && mouseInside()
    }

    private func updateTooltipText(_ value: String?) {
        if toolTip != value {
            toolTip = value
        }
    }

    private func refreshTooltipCountdown() -> Bool {
        guard let value = item?.tooltipCountdownText() else {
            updateTooltipText(item?.fullDate)
            return false
        }
        updateTooltipText(value)
        return true
    }

    private func startTooltipTimerIfNeeded() {
        guard tooltipTimer == nil, canUpdateTooltip, refreshTooltipCountdown() else {
            return
        }
        tooltipTimer = SwiftSignalKit.Timer(timeout: 1.0, repeat: true, completion: { [weak self] in
            guard let self else {
                return
            }
            if !self.canUpdateTooltip || !self.refreshTooltipCountdown() {
                self.cancelTooltipTimer()
            }
        }, queue: .mainQueue())
        tooltipTimer?.start()
    }

    private func cancelTooltipTimer() {
        tooltipTimer?.invalidate()
        tooltipTimer = nil
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        cancelTooltipTimer()
    }

    deinit {
        tooltipTimer?.invalidate()
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        startTooltipTimerIfNeeded()
    }
    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        cancelTooltipTimer()
    }
    
    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        startTooltipTimerIfNeeded()
    }
    
    
    public override func mouseUp(with event: NSEvent) {
        superview?.mouseUp(with: event)
    }
    
}
