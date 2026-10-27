import Cocoa
import TGUIKit
import TelegramCore
import TGModernGrowingTextView
import Postbox
import SwiftSignalKit
import InputView
import MetalEngine
import DustLayer
import AvatarUI
import ChatHistoryModel
import GeneralRows
import InAppSettings
import InputTextView
import LocalAnimations
import Localization
import MessageUtils
import PremiumStatusUI
import TelegramContext
import TelegramTheme
import TelegramUtils

public final class ChatSwipeToReplyView : View {

    public static let controlSize = NSMakeSize(33, 33)

    private static let bleed: CGFloat = 22
    private static let progressLineWidth: CGFloat = 2
    private static let successRingRadius: CGFloat = 35
    private static let successFillLineWidth: CGFloat = 18

    private let contentLayer = SimpleLayer()
    private let semiFillLayer = SimpleShapeLayer()
    private let progressLayer = SimpleShapeLayer()
    private let fillLayer = SimpleShapeLayer()
    private let iconLayer = SimpleLayer()

    private var playedSuccessAnimation = false
    private var currentScale: CGFloat = 1

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer?.masksToBounds = false
        backgroundColor = .clear

        let bleed = ChatSwipeToReplyView.bleed
        let size = ChatSwipeToReplyView.controlSize
        let contentSize = NSMakeSize(size.width + bleed * 2, size.height + bleed * 2)
        let discRect = CGRect(origin: NSMakePoint(bleed, bleed), size: size)

        contentLayer.frame = CGRect(origin: NSMakePoint(-bleed, -bleed), size: contentSize)
        contentLayer.masksToBounds = false

        semiFillLayer.frame = discRect
        semiFillLayer.path = CGPath(ellipseIn: semiFillLayer.bounds, transform: nil)
        semiFillLayer.strokeColor = NSColor.clear.cgColor
        semiFillLayer.opacity = 0

        progressLayer.frame = CGRect(origin: NSMakePoint(bleed - 20, bleed - 20), size: NSMakeSize(size.width + 40, size.height + 40))
        progressLayer.fillColor = NSColor.clear.cgColor
        progressLayer.lineCap = .round
        progressLayer.lineWidth = ChatSwipeToReplyView.progressLineWidth

        fillLayer.frame = discRect
        fillLayer.fillColor = NSColor.clear.cgColor
        fillLayer.isHidden = true

        iconLayer.frame = discRect
        iconLayer.opacity = 0

        contentLayer.addSublayer(semiFillLayer)
        contentLayer.addSublayer(progressLayer)
        contentLayer.addSublayer(fillLayer)
        contentLayer.addSublayer(iconLayer)
        layer?.addSublayer(contentLayer)

        progressLayer.path = ringPath(progress: 0)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func update(fillColor: NSColor, icon: CGImage) {
        semiFillLayer.fillColor = fillColor.withAlphaComponent(0.6).cgColor
        progressLayer.strokeColor = fillColor.cgColor
        fillLayer.strokeColor = fillColor.cgColor

        let bleed = ChatSwipeToReplyView.bleed
        let size = ChatSwipeToReplyView.controlSize
        let iconSize = icon.backingSize

        iconLayer.contents = icon
        iconLayer.contentsScale = System.backingScale
        iconLayer.frame = CGRect(origin: NSMakePoint(bleed + (size.width - iconSize.width) / 2, bleed + (size.height - iconSize.height) / 2), size: iconSize)
    }

    public func update(item: ChatRowItem) {
        if item.isBubbled, item.presentation.chatBackground != item.presentation.chatServiceItemColor {
            update(fillColor: item.presentation.chatServiceItemColor, icon: item.presentation.chat.chat_reply_swipe_bubble(theme: item.presentation))
        } else {
            update(fillColor: item.presentation.colors.grayBackground, icon: item.presentation.icons.chat_swipe_reply)
        }
    }

    public func animateOut(completion: @escaping()->Void) {
        layer?.animateAlpha(from: 1.0, to: 0.0, duration: 0.3, removeOnCompletion: false, completion: { _ in
            completion()
        })
        let from = currentScale
        currentScale = 0.2
        contentLayer.transform = CATransform3DMakeScale(0.2, 0.2, 1)
        contentLayer.animateScale(from: from, to: 0.2, duration: 0.3, timingFunction: .spring, removeOnCompletion: false)
    }

    private func ringPath(progress: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let center = NSMakePoint(progressLayer.bounds.midX, progressLayer.bounds.midY)
        path.addArc(center: center, radius: ChatSwipeToReplyView.controlSize.width / 2, startAngle: -.pi / 2, endAngle: -.pi / 2 + progress * 2 * .pi, clockwise: false)
        return path
    }

    public func updateProgress(_ value: CGFloat) {
        let progress = max(0, min(1, value))

        var foregroundProgress = min(1, progress * 1.2)
        var scaleProgress = 0.65 + foregroundProgress * 0.35

        if !playedSuccessAnimation {
            progressLayer.path = ringPath(progress: progress)
        } else {
            foregroundProgress = progress
            scaleProgress = progress
            contentLayer.opacity = Float(progress)
        }

        semiFillLayer.opacity = Float(progress)

        currentScale = scaleProgress
        contentLayer.transform = CATransform3DMakeScale(scaleProgress, scaleProgress, 1)

        iconLayer.opacity = Float(foregroundProgress)
        iconLayer.transform = CATransform3DMakeScale(foregroundProgress, foregroundProgress, 1)

        if progress == 1 {
            playSuccessAnimation()
        }
    }

    private func playSuccessAnimation() {
        guard !playedSuccessAnimation else {
            return
        }
        playedSuccessAnimation = true

        currentScale = 1.1
        contentLayer.transform = CATransform3DMakeScale(1.1, 1.1, 1)
        contentLayer.animateScale(from: 1.0, to: 1.1, duration: 0.2, completion: { [weak self] _ in
            guard let self else { return }
            self.currentScale = 1
            self.contentLayer.transform = CATransform3DIdentity
            self.contentLayer.animateScale(from: 1.1, to: 1.0, duration: 0.15)
        })

        let progressLineWidth = progressLayer.lineWidth
        progressLayer.lineWidth = 0
        progressLayer.animate(from: NSNumber(value: Double(progressLineWidth)), to: NSNumber(value: 0.0), keyPath: "lineWidth", timingFunction: .linear, duration: 0.3)

        if let currentRing = progressLayer.path {
            let expandedRing = CGMutablePath()
            expandedRing.addArc(center: NSMakePoint(progressLayer.bounds.midX, progressLayer.bounds.midY), radius: ChatSwipeToReplyView.successRingRadius, startAngle: -.pi / 2, endAngle: -.pi / 2 + 2 * .pi, clockwise: false)
            progressLayer.path = expandedRing
            progressLayer.animate(from: currentRing, to: expandedRing, keyPath: "path", timingFunction: .spring, duration: 0.3)
        }
        progressLayer.animateAlpha(from: 1.0, to: 0.0, duration: 0.3)
        progressLayer.opacity = 0

        fillLayer.isHidden = false
        let outerFill = CGPath(ellipseIn: fillLayer.bounds, transform: nil)
        fillLayer.path = outerFill
        fillLayer.lineWidth = ChatSwipeToReplyView.successFillLineWidth
        fillLayer.animate(from: NSNumber(value: Double(ChatSwipeToReplyView.progressLineWidth)), to: NSNumber(value: Double(ChatSwipeToReplyView.successFillLineWidth)), keyPath: "lineWidth", timingFunction: .linear, duration: 0.3)

        let innerFill = CGPath(ellipseIn: fillLayer.bounds.insetBy(dx: 9, dy: 9), transform: nil)
        fillLayer.path = innerFill
        fillLayer.animate(from: outerFill, to: innerFill, keyPath: "path", timingFunction: .linear, duration: 0.3)
    }
}

public class ChatRowView: TableRowView, Notifable, MultipleSelectable, ChatTextSelectionProvider, RevealTableView {

    public class CaptionView {
        public private(set) var id: UInt32
        public private(set) var shim: Bool
        public let view: View
        fileprivate var messageId: MessageId?
        fileprivate weak var context: (any AccountContextProtocol)?
        fileprivate var layout: FoldingTextLayout?
        var nativeView: FoldingTextView? { view as? FoldingTextView }
        var layerView: ChatLayerMessageTextView? { view as? ChatLayerMessageTextView }

        public init(id: UInt32, shim: Bool, view: View) {
            self.id = id
            self.shim = shim
            self.view = view
        }

        public func isSame(to other: ChatRowItem.RowCaption) -> Bool {
            return id == other.id && messageId == other.message.id
                && context === other.layout.context && layout?.string == other.layout.string
        }

        fileprivate func canKeepRenderer(for caption: ChatRowItem.RowCaption, presentation: ChatLayerMessageTextPresentation?, animated: Bool) -> Bool {
            if layerView != nil { return presentation != nil }
            guard presentation != nil, let nativeView else { return true }
            return animated || nativeView.hasSelectedText || !nativeView.updateForReusedContent(layout: caption.layout)
        }

        fileprivate func reuse(_ caption: ChatRowItem.RowCaption, presentation: ChatLayerMessageTextPresentation?) -> Bool {
            guard context === caption.layout.context else { return false }
            if let nativeView {
                guard presentation == nil, nativeView.updateForReusedContent(layout: caption.layout) else { return false }
            } else if let layerView, let presentation {
                guard !layerView.hasActiveInput, !contextMenuOnScreen(), layerView.layer?.animationKeys()?.isEmpty != false,
                      !layerView.body.textNodes.contains(where: { $0.hasExternalTextSelection }),
                      layerView.update(presentation, identity: .init(messageId: caption.message.id, accountId: ObjectIdentifier(caption.layout.context)), context: caption.layout.context) else { return false }
            } else {
                return false
            }
            updateIdentity(caption)
            return true
        }

        fileprivate func updateIdentity(_ caption: ChatRowItem.RowCaption) {
            id = caption.id
            shim = caption.isLoading
            messageId = caption.message.id
            context = caption.layout.context
            layout = caption.layout
        }

        fileprivate func update(_ caption: ChatRowItem.RowCaption, presentation: ChatLayerMessageTextPresentation?, animated: Bool) {
            updateIdentity(caption)
            if let nativeView {
                nativeView.update(layout: caption.layout, animated: animated)
            } else if let layerView, let presentation {
                layerView.update(presentation, identity: .init(messageId: caption.message.id, accountId: ObjectIdentifier(caption.layout.context)), context: caption.layout.context, animated: animated)
            }
        }

        fileprivate func prepareForRemoval() {
            layerView?.prepareForRemoval()
            view.isEventLess = true
        }

        public func clickInContent(point: NSPoint) -> Bool {
            return nativeView?.clickInContent(point: point) ?? layerView?.clickInContent(point: point) ?? false
        }

        public func highlight(text: String, color: NSColor, range: NSRange?) {
            if let nativeView {
                nativeView.highlight(text: text, color: color, range: range)
            } else if let layerView, let layout {
                layerView.body.highlight(text: text, color: color, range: range, in: layout)
            }
        }
    }

    private final class CaptionBindingState {
        var pending: (ChatRowItem, Bool)?
        var isUpdating = false
    }
    private var captionBindingState: CaptionBindingState?
    public struct CaptionShimmerView {
        public let id: UInt32
        public let view: ShimmerView
        public let mask: SimpleLayer
        
    }
   
    
    public var header: String? {
        if let item = item as? ChatRowItem, let message = item.message {
            var header = copiedMessageHeader(message, timeDifference: item.context.timeDifference) + ":"
            if let replyLine = copiedMessageReplyLine(message, threadId: item.chatInteraction.chatLocation.threadId) {
                header += "\n" + replyLine
            }
            return header
        }
        return nil
    }


    static var usesLegacyRowChrome = false
    #if DEBUG
    static var parityMutation: CGFloat = 0
    static var parityEmojiMutation: CGFloat = 0
    static var parityAvatarMutation: CGFloat = 0
    static var parityStatusMutation: CGFloat = 0
    static var parityChipMutation: CGFloat = 0
    static var parityBadgeMutation: CGFloat = 0
    static var parityReplyMutation: CGFloat = 0
    var debugHasLegacyAdminBadge: Bool { adminBadge != nil }
    #endif

    private final class RightToolTip: NSObject, NSViewToolTipOwner {
        weak var item: ChatRowItem?
        private weak var view: NSView?
        private var tag: NSView.ToolTipTag?
        private var rect: NSRect = .zero

        func update(_ view: NSView, rect: NSRect, force: Bool) {
            if !force, self.view === view, self.rect == rect, tag != nil { return }
            remove()
            guard !rect.isEmpty else { return }
            self.view = view
            self.rect = rect
            tag = view.addToolTip(rect, owner: self, userData: nil)
        }

        func remove() {
            if let tag, let view { view.removeToolTip(tag) }
            tag = nil
            view = nil
            rect = .zero
        }

        func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint, userData data: UnsafeMutableRawPointer?) -> String {
            guard let item else { return "" }
            return item.tooltipCountdownText() ?? item.fullDate ?? ""
        }
    }
    private var rightToolTip: RightToolTip?

    private var avatar:ChatAvatarView?
    public private(set) var contentView:View = View()
    private var replyView:ChatAccessoryView?
    private var replyNode: ChatLayerControlNode?
    private var replyHost: ChatAccessoryView?
    private var spareReply: (node: ChatLayerControlNode, host: ChatAccessoryView)?
    private weak var replyNodeRejected: ChatAccessoryModel?
    private var replyMarkupView:View?
    
    public private(set) var forwardPhoto: AvatarControl?
    public private(set) var forwardLine:SimpleLayer?

    
    public private(set) var captionViews: [CaptionView] = []
    public private(set) var captionShimmerViews: [CaptionShimmerView] = []
    
    private var shareView:ImageButton?
    private var shareVisibleForCurrentItem: Bool = false
    private var reactionsView:ChatReactionsView?
    private var channelCommentsBubbleControl: ChannelCommentsBubbleControl?
    private var channelCommentsBubbleSmallControl: ChannelCommentsSmallControl?

    private var topicLinkView:TopicReplyItemView?

    
    
    private var adminBadge: TextView?
    private var adminBadgeBg: View?
    private var boostBadge: InteractiveTextView?
    private var ephemeralBadgeView: InteractiveTextView?
    public let rightView:ChatRightView = ChatRightView(frame:NSZeroRect)
    public private(set) var selectingView:SelectingControl?
    private var mouseDragged: Bool = false
    private var animatedView:RowAnimateView?
    
    private var forwardAccessory: ChatBubbleAccessoryForward? = nil
    private var viaAccessory: ChatBubbleViaAccessory? = nil
    
    
    public let bubbleView = ChatMessageBubbleBackdrop()

    private var cutBandViews: [NSView] = []
    
    private var statusControl: PremiumStatusControl? = nil
    private var forwardStatusControl: PremiumStatusControl? = nil
    
    private var psaButton: ImageButton? = nil
    
    private var hasBeenLayout: Bool = false
    private weak var observedInteraction: ChatInteraction?
    private var isPreparingItem: Bool = false

    private var _cachedBubbleFrame: NSRect?
    private var _cachedContentFrame: NSRect?
    private var _cachedRightFrame: NSRect?

    public func invalidateFrameCache() {
        _cachedBubbleFrame = nil
        _cachedContentFrame = nil
        _cachedRightFrame = nil
    }

    public func cachedContentFrame(_ item: ChatRowItem) -> NSRect {
        if let cached = _cachedContentFrame { return cached }
        let result = contentFrame(item)
        _cachedContentFrame = result
        return result
    }

    private var factCheckView: FactCheckMessageView?

    public let rowView: View
    
    public var photoView: NSView? {
        return self.avatar
    }

    public required init(frame frameRect: NSRect) {
        rowView = ChatLayerRowView(frame: NSMakeRect(0, 0, frameRect.width, frameRect.height))
        super.init(frame: frameRect)
        
        super.addSubview(rowView)
        
        
        contentView.layer?.masksToBounds = false
        
        rowView.addSubview(bubbleView)
        (rowView as? ChatLayerRowView)?.layerHitBackground = bubbleView
        rowView.addSubview(contentView)
        rowView.addSubview(rightView)
    }
    
    public override func setFrameSize(_ newSize: NSSize) {
        if !inLiveResize || !NSIsEmptyRect(visibleRect) {
            super.setFrameSize(newSize)
            rowView.setFrameSize(newSize)
        }
        
    }
    
    public override func setFrameOrigin(_ newOrigin: NSPoint) {
        let oldOrigin = self.frame.origin
        super.setFrameOrigin(newOrigin)
        
        if oldOrigin != newOrigin, oldOrigin == .zero {
            updateBackground(animated: false, item: self.item)
        }
    }
    
    private var shouldHostRight: Bool {
        return !ChatRowView.usesLegacyRowChrome && rightView.canHostContent
    }

    private func updateRightHosting(_ item: ChatRowItem) {
        guard let rowLayer = rowView.layer else { return }
        if shouldHostRight, rightView.superview == rowView || rightView.isContentHosted {
            let wasHosted = rightView.isContentHosted
            if rightView.superview != nil {
                rightView.removeFromSuperview()
            }
            rightView.hostContent(in: rowLayer)
            let toolTip = rightToolTip ?? RightToolTip()
            rightToolTip = toolTip
            toolTip.item = item
            if !wasHosted {
                let frame = rightFrame(item)
                rightView.updateHostedFrame(frame, transition: .immediate)
                rightView.updateLayout(size: frame.size, transition: .immediate)
                toolTip.update(rowView, rect: frame, force: false)
            }
        } else if rightView.isContentHosted {
            rightToolTip?.remove()
            rightView.restoreContent()
            rowView.addSubview(rightView, positioned: .above, relativeTo: contentView)
            rightView.frame = rightFrame(item)
            rightView.updateLayout(size: rightView.frame.size, transition: .immediate)
        }
    }

    private func moveHostedRightForShake() -> (() -> Void)? {
        guard rightView.isContentHosted, let bubbleLayer = bubbleView.layer, let rowLayer = rowView.layer else { return nil }
        let content = rightView.contentLayer
        content.frame = bubbleView.convert(rightView.frame, from: rowView)
        bubbleLayer.addSublayer(content)
        return { [weak self] in
            guard let self, self.rightView.isContentHosted, content.superlayer === bubbleLayer else { return }
            rowLayer.addSublayer(content)
            content.frame = self.rightView.frame
        }
    }

    public func updateBackground(animated: Bool, item: TableRowItem?, rotated: Bool = false, clean: Bool = false) -> Void {

        guard let item = item as? ChatRowItem else {
            return
        }

        let gradientRect = item.chatInteraction.getGradientOffsetRect()
        let size = NSMakeSize(gradientRect.width, gradientRect.height + 60)
        updateBackground(animated: animated, gradientRect: gradientRect, size: size, rotated: rotated, clean: clean)
    }

    public func updateBackground(animated: Bool, gradientRect: NSRect, size: NSSize, rotated: Bool = false, clean: Bool = false) -> Void {
        let inset = size.height - gradientRect.minY + (frame.height - self.bubbleView.frame.maxY) - 30
        let animated = animated && visibleRect.height > 0 && !clean && self.layer?.animation(forKey: "position") == nil
        let rect = self.frame

        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate

        bubbleView.update(rect: rect.offsetBy(dx: self.bubbleView.frame.minX, dy: inset), within: size, transition: transition, rotated: rotated)
    }
      
    var textSelectionSources: ChatTextSelectionSources {
        guard captionViews.contains(where: { $0.layerView != nil }) else { return .views(selectableTextViews) }
        var sources: [ChatTextSelectionSource] = []
        for caption in captionViews {
            if let layer = caption.layerView {
                sources.append(contentsOf: layer.body.textNodes.map { .layer($0, layer) })
            } else if let native = caption.nativeView {
                sources.append(contentsOf: native.textViews.map(ChatTextSelectionSource.view))
            }
        }
        if let text = factCheckView?.textView.textView { sources.append(.view(text)) }
        return .mixed(sources)
    }

    public var selectableTextViews: [TextView] {
        var views = captionViews.flatMap { $0.nativeView?.textViews ?? [] }
        if let text = factCheckView?.textView.textView { views.append(text) }
        return views
    }
    
    public func clickInContent(point: NSPoint) -> Bool {
        guard let item = item as? ChatRowItem, let _ = item.captionLayouts.first?.layout, let captionView = captionViews.first else {return false}
        return captionView.clickInContent(point: captionView.view.convert(point, from: self))
    }
    
    public func isEqual(to other: Notifable) -> Bool {
        if let other = other as? ChatRowView {
            return self == other
        }
        return false
    }
    
    public func notify(with value: Any, oldValue: Any, animated:Bool) {
        guard !isPreparingItem else { return }
        
        let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate
        
        if let value = value as? ChatPresentationInterfaceState, let oldValue = oldValue as? ChatPresentationInterfaceState {
            if (value.selectionState != oldValue.selectionState) {
                updateSelectingState(!NSIsEmptyRect(visibleRect), selectingMode:value.selectionState != nil, item: self.item as? ChatRowItem, needUpdateColors: true)
                
                updateLayout(size: frame.size, transition: transition)
            } else if let item = item as? ChatRowItem, let message = item.message {
                if value.selectionState?.selectedIds.contains(message.id) != oldValue.selectionState?.selectedIds.contains(message.id) {
                    if let selectionState = value.selectionState {
                        selectingView?.set(selected: selectionState.selectedIds.contains(message.id), animated: !NSIsEmptyRect(visibleRect))
                        updateColors()
                        updateLayout(size: frame.size, transition: transition)
                    }
                }
            }
        }

    }
    
    
    public func updateSelectingState(_ animated:Bool = false, selectingMode:Bool, item: ChatRowItem?, needUpdateColors: Bool) {
        
        let selectingMode = selectingMode && item?.chatInteraction.chatLocation.threadMsgId != item?.message?.id
        if let item = item {
            if selectingMode {
                if selectingView == nil {
                    selectingView = SelectingControl(unselectedImage: item.presentation.chat_toggle_unselected, selectedImage: item.presentation.chat_toggle_selected, selected: item.isSelectedMessage)
                    selectingView?.setFrameOrigin(NSMakePoint(frame.width, selectingPoint(item).y))
                    super.addSubview(selectingView!)
                    
                    if animated {
                        selectingView?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    }
                }
            } else {
                if let view = self.selectingView {
                    performSubviewRemoval(view, animated: animated, scale: true)
                    view.layer?.animatePosition(from: view.frame.origin, to: view.frame.origin.offsetBy(dx: 20, dy: 0), removeOnCompletion: false)
                    self.selectingView = nil
                }
            }
            updateSelectionViewAfterUpdateState(item: item, animated: animated)
            if needUpdateColors {
                renderLayoutType(item, animated: animated)
                updateColors()
            }
            if item.chatInteraction.presentation.state == .selecting || item.disableInteractions {
                disableHierarchyInteraction()
            } else {
               restoreHierarchyInteraction()
            }
            self.channelCommentsBubbleSmallControl?.isEnabled = !item.isFailed && !item.isUnsent && item.chatInteraction.presentation.state != .selecting
            self.channelCommentsBubbleControl?.isEnabled = !item.isFailed && !item.isUnsent && item.chatInteraction.presentation.state != .selecting
        }
    }
    
    public func updateSelectionViewAfterUpdateState(item: ChatRowItem, animated: Bool) {
        
        if let selectionState = item.chatInteraction.presentation.selectionState, let message = item.message {
            selectingView?.set(selected: selectionState.selectedIds.contains(message.id), animated: animated)
        }
    }
    
    public func canStartTextSelecting(_ event:NSEvent) -> Bool {
        return false
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var isSelect: Bool {
        if let item = item as? ChatRowItem {
            return isSelectedItem(item)
        }
        return false
    }
    
    private func isSelectedItem(_ item: ChatRowItem) -> Bool {
        if let message = item.message, let selectionState = item.chatInteraction.presentation.selectionState {
            return selectionState.selectedIds.contains(message.id)
        }
        return false
    }
    
    public func isSelectInGroup(_ location: NSPoint) -> Bool {
        return isSelect
    }
    
    public override var backdorColor: NSColor {
        guard let item = item as? ChatRowItem else { return super.backdorColor }
        if let forceBackgroundColor = item.forceBackgroundColor {
            return forceBackgroundColor
        }
        return item.renderType == .bubble ? .clear : contextMenu != nil || isSelect ? item.presentation.colors.selectMessage : item.presentation.chatBackground
    }
    
    public var contentColor: NSColor {
        guard let item = item as? ChatRowItem else {return backdorColor}
        if item.hasBubble {
            return item.presentation.chat.backgroundColor(item.isIncoming, item.renderType == .bubble)
        } else {
            return .clear//backdorColor
        }
    }

    
    public override func updateColors() -> Void {
        super.updateColors()
        
        guard let item = item as? ChatRowItem else {return}

        rowView.backgroundColor = backdorColor
        
        if item.shouldBlurService {
            rightView.blurBackground = item.presentation.blurServiceColor
            rightView.setLayerCornerRadius(item.rightSize.height / 2)
        } else {
            rightView.blurBackground = nil
            rightView.setLayerCornerRadius(item.rightSize.height / 2)
            rightView.backgroundColor = item.isStateOverlayLayout ? item.presentation.chatServiceItemColor : contentColor
        }
        if !isPreparingItem, rightView.isContentHosted != shouldHostRight {
            updateRightHosting(item)
        }

        contentView.backgroundColor = .clear
        if let replyModel = item.replyModel {
            replyModel.backgroundColor = item.hasBubble ? contentColor : item.isBubbled ? item.presentation.colors.bubbleBackground_incoming : contentColor
        }
        (rowView as? ChatLayerRowView)?.senderName?.layer.backgroundColor = contentColor.cgColor
        (rowView as? ChatLayerRowView)?.forwardName?.layer.backgroundColor = contentColor.cgColor
        for captionView in captionViews {
            captionView.view.backgroundColor = contentColor
        }
        replyMarkupView?.backgroundColor = backdorColor
        bubbleView.background = item.presentation.chat.bubbleBackgroundColor(item.isIncoming, item.hasBubble)

        if let control = channelCommentsBubbleControl {
            control.set(background: .clear, for: .Normal)
            if control.bubbleMode {
                control.set(background: item.presentation.colors.accent.withAlphaComponent(0.08), for: .Hover)
                control.set(background: item.presentation.colors.accent.withAlphaComponent(0.16), for: .Highlight)
            } else {
                control.set(background: .clear, for: .Hover)
                control.set(background: .clear, for: .Highlight)
            }
        }

        if let control = channelCommentsBubbleSmallControl {
            control.set(background: item.presentation.chatServiceItemColor, for: .Normal)
            if item.shouldBlurService {
                control.set(background: .clear, for: .Normal)
                control.blurBackground = item.presentation.blurServiceColor
            } else {
                control.set(background: item.presentation.chatServiceItemColor, for: .Normal)
                control.blurBackground = nil
            }
        }

        
        for view in contentView.subviews {
            if let view = view as? View, !view.isDynamicColorUpdateLocked {
                view.backgroundColor = contentColor
            }
        }
    }
    
    private var mouseDownPoint: NSPoint = .zero
    public override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        
        let current = convert(event.locationInWindow, from: nil)
        mouseDragged = mouseDragged || abs(mouseDownPoint.x - current.x) > 5 || abs(mouseDownPoint.y - current.y) > 5
        
    }
    
    
    public override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        mouseDownPoint = convert(event.locationInWindow, from: nil)
        mouseDragged = false
    }
    
    public override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        
        if let item = item as? ChatRowItem, !item.chatInteraction.isLogInteraction && !item.chatInteraction.disableSelectAbility, !item.sending {
            if item.chatInteraction.presentation.state != .selecting {
                let location = self.convert(event.locationInWindow, from: nil)
                if NSPointInRect(location, rightView.frame) {
                    if item.isFailed,  let messageId = item.message?.id {
                        item.resendFailed(messageId)
                    } else {
                        if item.message?.pendingProcessingAttribute != nil {
                            if rightView.isContentHosted {
                                tooltip(for: rowView, text: strings().chatVideoProccessingTooltip, rect: rightView.frame)
                            } else {
                                tooltip(for: rightView, text: strings().chatVideoProccessingTooltip)
                            }
                        } else {
                            forceSelectItem(item, onRightClick: true)
                        }
                    }
                }
            }
        }
    }
    
    public func forceSelectItem(_ item: ChatRowItem, onRightClick: Bool) {
        if let message = item.message, item.isSelectable {
            item.chatInteraction.withToggledSelectedMessage({$0.withToggledSelectedMessage(message.id)})
        }
    }
    
    public override func onShowContextMenu() {
        guard let item = item as? ChatRowItem else {return}
        renderLayoutType(item, animated: true)
        updateColors()
        updateMouse(animated: false)
        super.onShowContextMenu()
    }
    
    public override func onCloseContextMenu() {
        guard let item = item as? ChatRowItem else {return}
        renderLayoutType(item, animated: true)
        updateColors()
        updateMouse(animated: false)
        item.chatInteraction.focusInputField()
        super.onCloseContextMenu()
    }
    
    public func mouseInsideRow() -> Bool {
        guard let window else {
            return false
        }
        let rect = rowView.convert(rowView.bounds, to: nil)
        return NSPointInRect(window.mouseLocationOutsideOfEventStream, rect)
    }
    
    public override func updateMouse(animated: Bool) {
        if let item = item as? ChatRowItem {
            let shouldBeVisible = shareVisibleForCurrentItem
                && mouseInsideRow()
                && contextMenu == nil
                && item.chatInteraction.presentation.state != .selecting
            if shouldBeVisible {
                if shareView == nil {
                    let view = ImageButton(frame: CGRect(origin: shareViewPoint(item), size: NSMakeSize(26, 26)))
                    view.setAccessibilityLabel(item.hasSource ? strings().voiceOverChatGoToOriginalMessage : strings().voiceOverCommonShare)
                    view.disableActions()
                    view.scaleOnClick = true
                    view.layer?.opacity = 0
                    rowView.addSubview(view)
                    self.shareView = view
                    configureShareView(item)
                }
                shareView?.change(opacity: 1, animated: animated)
            } else {
                if let view = shareView {
                    self.shareView = nil
                    performSubviewRemoval(view, animated: animated, scale: false)
                }
            }
        }
        if let commentsView = self.channelCommentsBubbleSmallControl, let item = item as? ChatRowItem {
            commentsView.change(opacity: mouseInsideRow() && contextMenu == nil && item.chatInteraction.presentation.state != .selecting ? 1.0 : 0.0, animated: animated)
        }
    }
    
    
    
    public override func addSubview(_ view: NSView) {
        self.contentView.addSubview(view)
    }
    
    func reattachRowView() {
        guard rowView.superview !== self else {
            return
        }
        super.addSubview(rowView)
        sortSubviews({ lhs, rhs, context in
            guard let context else {
                return .orderedSame
            }
            let rowView = Unmanaged<NSView>.fromOpaque(context).takeUnretainedValue()
            if lhs === rowView {
                return .orderedAscending
            } else if rhs === rowView {
                return .orderedDescending
            } else {
                return .orderedSame
            }
        }, context: Unmanaged.passUnretained(rowView).toOpaque())
    }

    public func fillTopicLink(_ item: ChatRowItem, animated: Bool) -> Void {
        if let value = item.topicLinkLayout {
            if topicLinkView == nil {
                topicLinkView = TopicReplyItemView(frame: topicLinkFrame(item))
                rowView.addSubview(topicLinkView!)
            }
            topicLinkView?.removeAllHandlers()
            topicLinkView?.set(handler: { [weak item] _ in
                item?.openTopic()
            }, for: .Click)
            
            topicLinkView?.update(item: value, animated: animated)
        } else {
            if let view = topicLinkView {
                performSubviewRemoval(view, animated: animated, scale: true)
                topicLinkView = nil
            }
        }
    }
    
    func usesReplyNode(_ item: ChatRowItem, _ reply: ChatAccessoryModel) -> Bool {
        return !ChatRowView.usesLegacyRowChrome && item.hasBubble && rowView is ChatLayerRowView && reply !== replyNodeRejected && ChatAccessoryView.canHostInLayer(reply)
    }

    static func performReplyAction(_ item: ChatRowItem?, _ reply: ChatAccessoryModel?) {
        if let summarize = reply as? SummarizeReplyModel {
            summarize.dismiss()
        } else if reply is ExpiredStoryReplyModel {
            item?.showExpiredStoryError()
        } else if reply is StoryReplyModel {
            item?.openStory()
        } else {
            item?.chatInteraction.focusInputField()
            item?.openReplyMessage()
        }
    }

    private func fillReplyNode(_ item: ChatRowItem, reply: ChatAccessoryModel, scene: ChatLayerRowView, animated: Bool) {
        let node: ChatLayerControlNode
        let host: ChatAccessoryView
        if let replyNode, let replyHost {
            node = replyNode
            host = replyHost
        } else if let spare = spareReply {
            spareReply = nil
            node = spare.node
            host = spare.host
            let frame = replyFrame(item)
            node.frame = frame
            host.frame = frame
            host.visibilityView = scene
            scene.addChromeNode(node)
            replyNode = node
            replyHost = host
        } else {
            let frame = replyFrame(item)
            let layer = SimpleLayer()
            layer.anchorPoint = .zero
            layer.masksToBounds = true
            layer.isOpaque = true
            layer.edgeAntialiasingMask = []
            if #available(macOS 10.15, *) {
                layer.cornerCurve = .continuous
            }
            node = ChatLayerControlNode(id: "reply", layer: layer)
            node.frame = frame
            node.accessibilityRole = .button
            host = ChatAccessoryView(layerHost: layer)
            host.frame = frame
            host.visibilityView = scene
            scene.addChromeNode(node)
            replyNode = node
            replyHost = host
        }
        host.layerHostScaleDidChange(scene.backingScaleFactor)
        host.layerHostFallback = { [weak self, weak item, weak reply] in
            DispatchQueue.main.async {
                guard let self, let item, let reply, self.item === item, item.replyModel === reply else { return }
                self.replyNodeRejected = reply
                self.fillReply(item, animated: false)
                self.needsLayout = true
            }
        }
        host.layerHostSizeDidChange = { [weak node, weak host] size in
            guard let node, let host else { return }
            node.frame = NSRect(origin: node.frame.origin, size: size)
            host.updateLayout(size, transition: .immediate)
        }
        node.removeAllHandlers()
        node.set(handler: { [weak item, weak reply] _ in
            ChatRowView.performReplyAction(item, reply)
        }, for: .Click)
        reply.animates = animated
        reply.view = host
        node.accessibilityLabel = host.accessibilityDefaultLabel
    }

    private func removeReplyNode(animated: Bool) {
        guard let node = replyNode else { return }
        let host = replyHost
        host?.layerHostFallback = nil
        host?.layerHostSizeDidChange = nil
        replyNode = nil
        replyHost = nil
        (rowView as? ChatLayerRowView)?.removeChromeNode(node, animated: animated)
        if !animated, let host {
            node.layer.removeAllAnimations()
            spareReply = (node, host)
        }
    }

    #if DEBUG
    var debugHasReplyNode: Bool { replyNode != nil }
    var debugHasReplyView: Bool { replyView != nil }
    var debugReplyThumbnail: Bool { replyHost?.imageLayer != nil || replyView?.imageView != nil }
    var debugReplyHit: Bool? {
        guard let node = replyNode, let scene = rowView as? ChatLayerRowView, let window = scene.window else { return nil }
        let center = NSPoint(x: node.frame.midX, y: node.frame.midY)
        guard window.contentView?.hitTest(scene.convert(center, to: nil)) === scene else { return false }
        return scene.hitNode(at: center) === node
    }
    #endif

    public func fillReply(_ item:ChatRowItem, animated: Bool) -> Void {
        if let reply = item.replyModel, usesReplyNode(item, reply), let scene = rowView as? ChatLayerRowView {
            if let view = replyView {
                performSubviewRemoval(view, animated: animated, scale: true)
                replyView = nil
            }
            fillReplyNode(item, reply: reply, scene: scene, animated: animated)
            return
        }
        removeReplyNode(animated: animated && item.replyModel == nil)
        
        if let reply = item.replyModel {
            if replyView == nil {
                replyView = ChatAccessoryView(frame: replyFrame(item))
                rowView.addSubview(replyView!)
            }
            
            replyView?.removeAllHandlers()
            replyView?.set(handler: { [weak item, weak reply] _ in
                if let summarize = reply as? SummarizeReplyModel {
                    summarize.dismiss()
                } else if reply is ExpiredStoryReplyModel {
                    item?.showExpiredStoryError()
                } else if reply is StoryReplyModel {
                    item?.openStory()
                } else {
                    item?.chatInteraction.focusInputField()
                    item?.openReplyMessage()
                }
            }, for: .Click)
            
            reply.animates = animated
            reply.view = replyView
        } else {
            if let view = replyView {
                performSubviewRemoval(view, animated: animated, scale: true)
                replyView = nil
            }
        }
        
    }
    
    public func bubbleFrame(_ item: ChatRowItem) -> NSRect {
        if let cached = _cachedBubbleFrame { return cached }
        let result = ChatRowGeometry.bubbleFrame(.init(item: item, rowWidth: frame.width))
        _cachedBubbleFrame = result
        return result
    }
    
    public func rightFrame(_ item: ChatRowItem) -> NSRect {
        if let cached = _cachedRightFrame { return cached }
        let result = ChatRowGeometry.timestampFrame(.init(item: item, rowWidth: frame.width, bubbleFrame: bubbleFrame(item), contentFrame: cachedContentFrame(item)))
        _cachedRightFrame = result
        return result
    }

    public func factCheckFrame(_ item: ChatRowItem) -> NSRect {
        if let layout = item.factCheckLayout {
            let cachedContent = cachedContentFrame(item)
            var rect = cachedContent
            rect.size = layout.size
            rect.origin.x += item.elementsContentInset

            rect.origin.y = cachedContent.maxY + item.defaultContentInnerInset
            
            if let captionLayout = item.captionLayouts.first?.layout, !item.invertMedia {
                var ignore: Bool = false
                if let item = item as? ChatGroupedItem, !item.isBubbled {
                    if item.layoutType == .files {
                        ignore = true
                    }
                }
                if !ignore {
                    rect.origin.y += captionLayout.size.height + item.defaultContentInnerInset
                }
            }
            
            return rect
        } else {
            return .zero
        }
    }
    
    public func avatarFrame(_ item: ChatRowItem) -> NSRect {
        let isBubbled = item.isBubbled
        return ChatRowGeometry.avatarFrame(leftInset: item.leftInset, rowHeight: isBubbled ? item.height : 0, isBubbled: isBubbled)
    }
    
    public func captionFrame(_ item: ChatRowItem, caption: ChatRowItem.RowCaption) -> NSRect {
        let content = cachedContentFrame(item)
        let invertMedia = item.invertMedia
        return ChatRowGeometry.captionFrame(contentFrame: content, size: caption.layout.size, offset: caption.offset.y, invertedOffset: invertMedia ? caption.invertedOffset : 0, contentInset: caption.contentInset, innerInset: invertMedia ? 0 : item.defaultContentInnerInset, elementsInset: item.elementsContentInset, invertMedia: invertMedia, isBubbled: item.isBubbled)
    }
    
    public func replyMarkupFrame(_ item: ChatRowItem) -> NSRect {
        guard let replyMarkup = item.replyMarkupModel else {return NSZeroRect}

        let contentFrame = self.cachedContentFrame(item)
        
        var frame = NSMakeRect(contentFrame.minX + item.elementsContentInset, contentFrame.maxY + item.defaultReplyMarkupInset, replyMarkup.size.width, replyMarkup.size.height)
        
        if let captionLayout = item.captionLayouts.first?.layout {
            frame.origin.y += captionLayout.size.height + item.defaultContentInnerInset
        }
        
        let bubbleFrame = self.bubbleFrame(item)
        
        if item.hasBubble {
            frame.origin.y = bubbleFrame.maxY + item.defaultReplyMarkupInset
            frame.origin.x = bubbleFrame.minX + (item.isIncoming ? item.additionBubbleInset : 0)
        } else if item.isBubbled {
            frame.origin.y = bubbleFrame.maxY
        }
        
        if let reactions = item.reactionsLayout, reactions.presentation.isOutOfBounds {
          //  frame.origin.y += reactions.size.height + item.defaultReactionsInset + item.defaultContentInnerInset
        }
        
        return frame
    }
    
    public func replyFrame(_ item: ChatRowItem) -> NSRect {
        guard let reply = item.replyModel else { return .zero }
        return ChatRowGeometry.sideAccessoryFrame(.init(item: item, size: reply.size, offset: item.replyOffset, contentFrame: cachedContentFrame(item)))
    }
    
    public func topicLinkFrame(_ item: ChatRowItem) -> NSRect {
        guard let topic = item.topicLinkLayout else { return .zero }
        return ChatRowGeometry.sideAccessoryFrame(.init(item: item, size: topic.size, offset: item.topicLinkOffset, contentFrame: cachedContentFrame(item)))
    }
    
    public func viaAccesoryPoint(_ item: ChatRowItem) -> NSPoint {
        guard let viaAccessory = viaAccessory else {return NSZeroPoint}
        
        if viaAccessory.superview == replyView {
            return NSMakePoint(5, 0)
        }
        
        let contentFrame = self.cachedContentFrame(item)

        var point: NSPoint = NSMakePoint(contentFrame.minX + item.elementsContentInset, item.defaultContentTopOffset)
        if item.isBubbled, !item.hasBubble {
            if item.isIncoming {
                point.x = contentFrame.maxX + 10
            } else {
                point.x = contentFrame.minX - viaAccessory.frame.width - 10
            }
        }
        return point
    }
    
    public func namePoint(_ item: ChatRowItem) -> NSPoint {
        return ChatRowGeometry.authorPoint(.init(item: item, contentFrame: cachedContentFrame(item)))
    }

    public func ephemeralBadgePoint(_ item: ChatRowItem) -> NSPoint {
        let namePoint = self.namePoint(item)
        let authorHeight = item.authorText?.layoutSize.height ?? 0
        return NSMakePoint(namePoint.x, namePoint.y + authorHeight + ChatRowItem.defaultContentInnerInset)
    }
    
    public func statusPoint(_ item: ChatRowItem) -> NSPoint {
        guard let authorText = item.authorText else {return NSZeroPoint}
        
        var point = self.namePoint(item)
        point.x += authorText.layoutSize.width + 1
//        point.y += 1
        return point
    }
    
    public func psaPoint(_ item: ChatRowItem) -> NSPoint {
        var point: NSPoint = .zero
        if item.isBubbled, let _ = item.forwardNameLayout {
            point.x = item.bubbleFrame.width - 20
            point.y = self.forwardNamePoint(item).y
        } else if item.entry.renderType == .list, let name = item.authorText {
            point = self.namePoint(item)
            point.x += name.layoutSize.width
            point.y -= 6
        }
       
       // point.y -= 7
        return point
    }
    
    public func statusForwardPoint(_ item: ChatRowItem) -> NSPoint {
        guard let forwardName = item.forwardNameLayout else {return NSZeroPoint}
        
        var point = self.forwardNamePoint(item)
        point.x += forwardName.layoutSize.width + 3
        //point.y += 1
        return point
    }
    
    public func adminBadgePoint(_ item: ChatRowItem) -> NSPoint {
        guard let adminBadge = item.adminBadge, let authorText = item.authorText else {return NSZeroPoint}
        let bubbleFrame = self.bubbleFrame(item)
        let namePoint = self.namePoint(item)
        
        var offset: CGFloat = adminBadge.layoutSize.width
        if let boostBadge = item.boostBadge {
            offset += boostBadge.layoutSize.width
        }
        
        var point = NSMakePoint( item.isBubbled ? bubbleFrame.maxX - item.bubbleContentInset - offset : namePoint.x + 6 + authorText.layoutSize.width, item.defaultContentTopOffset + 1)
        
        if !item.isBubbled {
            point.x += max(0, item.statusSize - 2)
        }
        if !item.isBubbled, let boostBadge = item.boostBadge {
            point.x += boostBadge.layoutSize.width
        }

        if item.isBubbled {
            point.y -= item.topInset
        }
        return point
    }
    func usesAdminBadgeNode(_ item: ChatRowItem) -> Bool {
        return !ChatRowView.usesLegacyRowChrome && !item.adminBadgeCanEdit && rowView is ChatLayerRowView
    }

    public func adminBadgeBgRect(_ item: ChatRowItem) -> NSRect {
        guard let badgeLayout = item.adminBadge else { return .zero }
        let badgeOrigin = adminBadgePoint(item)
        let padding = NSEdgeInsets(top: 1, left: 1, bottom: 1, right: 4)
        return NSMakeRect(badgeOrigin.x - padding.left, badgeOrigin.y - padding.top, badgeLayout.layoutSize.width + padding.left + padding.right, badgeLayout.layoutSize.height + padding.top + padding.bottom)
    }
    public func boostBadgePoint(_ item: ChatRowItem) -> NSPoint {
        guard let boostBadge = item.boostBadge, let authorText = item.authorText else {return NSZeroPoint}
        let bubbleFrame = self.bubbleFrame(item)
        let namePoint = self.namePoint(item)
        var point = NSMakePoint( item.isBubbled ? bubbleFrame.maxX - item.bubbleContentInset - boostBadge.layoutSize.width : namePoint.x + authorText.layoutSize.width, item.defaultContentTopOffset + 1)
        
        if !item.isBubbled {
            point.x += max(0, item.statusSize - 2)
        }

        if item.isBubbled {
            point.y -= item.topInset
        }
        return point
    }
    
    public func selectingPoint(_ item: ChatRowItem) -> NSPoint {
        
        var point = NSZeroPoint
        
        
        let rightFrame = self.rightFrame(item)
        
        if let selectingView = selectingView {
            if item.isBubbled {
                let f = focus(selectingView.frame.size)
                point.y = f.minY
                point.x = frame.width - selectingView.frame.width - 15
            } else {
                point = NSMakePoint(rightFrame.maxX + 4, item.defaultContentTopOffset - 3)
            }
        }
        return point
    }
    
    public func contentFrame(_ item: ChatRowItem) -> NSRect {
        return ChatRowGeometry.contentFrame(.init(item: item, bubbleFrame: item.isBubbled ? bubbleFrame(item) : .zero))
    }
    
    public func contentFrameModifier(_ item: ChatRowItem) -> NSRect {
        return self.cachedContentFrame(item)
    }
    
    public func bubbleFilledContentFrame(_ item: ChatRowItem, base: NSRect) -> NSRect {
        if item.isBubbled {
            var frame = bubbleFrame(item)
            frame.size.height = self.cachedContentFrame(item).height
            frame.size.width -= item.additionBubbleInset
            frame.origin.y = base.minY
            if item.isIncoming {
                frame.origin.x += item.additionBubbleInset
            }
            return frame
        } else {
            var frame = base
            frame.origin.x -= item.bubbleContentInset
            return frame
        }
    }
    
    public func bubbleCenteredContentFrame(_ item: ChatRowItem, base: NSRect) -> NSRect {
        var rect = base
        if item.renderType == .bubble {
            let addition = floorToScreenPixels(backingScaleFactor, (bubbleFrame(item).width - item.bubbleContentInset * 2 - item.additionBubbleInset - rect.width) / 2)
            rect.origin.x += addition
        }
        return rect
    }
    
    public func rowPoint(_ item: ChatRowItem) -> NSPoint {
        
        if let swipeDelta = swipeDelta {
            return NSMakePoint(swipeDelta, 0)
        } else if item.isBubbled {
            return NSMakePoint((self.selectingView != nil && !item.isIncoming ? -32 : 0), 0)
        } else {
            return NSMakePoint(0, 0)
        }
    }
    
    public func forwardLineRect(_ item: ChatRowItem) -> CGRect {
        return ChatRowGeometry.forwardLineFrame(item: item, rowHeight: frame.height)
    }
    
    public func forwardHeaderRect(_ item: ChatRowItem) -> CGRect {
        guard let header = item.forwardHeader else { return .zero }
        return ChatRowGeometry.forwardHeaderFrame(leftInset: item.defLeftInset, top: item.forwardHeaderInset.y, size: header.layoutSize)
    }
    
    public func forwardNamePoint(_ item: ChatRowItem) -> NSPoint {
        let accessoryWidth = item.isBubbled && !item.hasBubble ? forwardAccessory?.frame.width : nil
        let bubble = item.isBubbled && item.hasBubble ? bubbleFrame(item) : .zero
        let content = accessoryWidth != nil ? cachedContentFrame(item) : .zero
        return ChatRowGeometry.forwardNamePoint(.init(item: item, bubbleFrame: bubble, contentFrame: content, accessoryWidth: accessoryWidth))
    }
    
    public func forwardPhotoPoint(_ item: ChatRowItem) -> NSPoint {
        var point = self.forwardNamePoint(item)
        if let layout = item.forwardNameLayout, let range = item.forwardPhotoPlaceRange {
            if let rect = layout.rects(range).last {
                point.x += rect.0.minX + 2
                point.y += rect.0.minY
            }
        }
        return point.toScreenPixel
    }
    
    public override func layout() {
        self.updateLayout(size: self.frame.size, transition: .immediate)
    }
    
    public func shareViewPoint(_ item: ChatRowItem) -> NSPoint {
        let size = NSMakeSize((29 + 4) * 1.05, (29 + 4) * 1.05)
        var point: NSPoint
        if item.isBubbled {
            let bubbleFrame = self.bubbleFrame(item)
            let rightFrame = self.rightFrame(item)
            point = NSMakePoint(item.isIncoming ? max(bubbleFrame.maxX + 10, rightFrame.maxX + 10) : bubbleFrame.minX - size.width - 10, bubbleFrame.maxY - (size.height) + 3)
        } else {
            let rightFrame = self.rightFrame(item)
            point = NSMakePoint(frame.width - 20.0 - size.width, rightFrame.maxY)
        }
        return point
    }
    

    
    
    
    public func fillForward(_ item:ChatRowItem, animated: Bool) -> Void {
        if let forwardNameLayout = item.forwardNameLayout {
            if item.isBubbled && !item.hasBubble {
                guard (rowView as? ChatLayerRowView)?.updateForwardName(nil, frame: .zero, animated: animated) != false else { return }
                
                if let view = self.forwardPhoto {
                    performSubviewRemoval(view, animated: animated)
                    self.forwardPhoto = nil
                }
                
                if forwardAccessory == nil {
                    forwardAccessory = ChatBubbleAccessoryForward(frame: CGRect(origin: forwardNamePoint(item), size: forwardNameLayout.layoutSize))
                    rowView.addSubview(forwardAccessory!)
                }
                forwardAccessory?.updateText(layout: forwardNameLayout, replyView: self.replyView)
                
            } else {
                if let view = forwardAccessory {
                    performSubviewRemoval(view, animated: animated, scale: true)
                    forwardAccessory = nil
                }
                
                if item.forwardPhotoPlaceRange != nil {
                    let current: AvatarControl
                    if let view = self.forwardPhoto {
                        current = view
                    } else {
                        current = AvatarControl(font: .avatar(6))
                        current.layer?.zPosition = 2
                        current.setFrameSize(NSMakeSize(14, 14))
                        current.setFrameOrigin(forwardPhotoPoint(item))
                        rowView.addSubview(current)
                        self.forwardPhoto = current
                    }
                    current.setPeer(account: item.context.account, peer: item.message?.forwardInfo?.author, message: item.message)
                    
                    current.removeAllHandlers()
                    current.set(handler: { [weak item] _ in
                        item?.openForwardInfo()
                    }, for: .Click)
                } else if let view = self.forwardPhoto {
                    performSubviewRemoval(view, animated: animated)
                    self.forwardPhoto = nil
                }
                
                (rowView as? ChatLayerRowView)?.updateForwardName(forwardNameLayout, frame: CGRect(origin: forwardNamePoint(item), size: forwardNameLayout.layoutSize), animated: animated)
            }
            
        } else {
            guard (rowView as? ChatLayerRowView)?.updateForwardName(nil, frame: .zero, animated: animated) != false else { return }
            if let view = forwardAccessory {
                performSubviewRemoval(view, animated: animated, scale: true)
                forwardAccessory = nil
            }
            if let view = self.forwardPhoto {
                performSubviewRemoval(view, animated: animated)
                self.forwardPhoto = nil
            }
        }
    }
    
    
    
    public func showHiddenForwardTooltip() {
        guard let host = rowView as? ChatLayerRowView, let rect = host.forwardNameFrame else { return }
        tooltip(for: host, text: strings().chatTooltipHiddenForwardName, autoCorner: false, rect: rect)
    }

    public func fillForwardLine(_ item: ChatRowItem, animated: Bool) -> Void {
        if let fwdType = item.forwardType, !item.isBubbled {
            let current: SimpleLayer
            if let view = self.forwardLine {
                current = view
            } else {
                current = SimpleLayer()
                current.frame = forwardLineRect(item)
                rowView.layer?.addSublayer(current)
                self.forwardLine = current
            }
            let color: NSColor
            if item.isPsa {
                color = item.presentation.colors.greenUI
            } else {
                color = item.presentation.chat.linkColor(item.isIncoming, false)
            }
            current.cornerRadius = current.frame.width / 2
            switch fwdType {
            case .FullHeader:
                current.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner]
            case .ShortHeader:
                current.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
            case .Inside:
                current.maskedCorners = []
            case .Bottom:
                current.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
            }
            current.backgroundColor = color.cgColor
        } else if let forwardLine {
            performSublayerRemoval(forwardLine, animated: animated)
            self.forwardLine = nil
        }
        
        
    }
    
    public func fillForwardHeader(_ item: ChatRowItem, animated: Bool) {
        (rowView as? ChatLayerRowView)?.updateForwardHeader(item.forwardHeader, frame: forwardHeaderRect(item), animated: animated)
    }

    
    public static func makePhotoView(_ item: ChatRowItem) -> ChatAvatarView {
        let avatar = ChatAvatarView(frame: NSMakeSize(36, 36).bounds)
        avatar.setFrameSize(36,36)
        
        if let peer = item.peer {
            avatar.setPeer(item: item, peer: peer, storyStats: item.entry.additionalData.authorStoryStats, message: item.message)
            if peer.id.id._internalGetInt64Value() != 0 {
                avatar.contextMenu = photoContextMenu(item, peer: peer, setOpenProgress: { [weak avatar] signal in
                    avatar?.setOpenProgress(signal)
                })
            }
        }
        return avatar
    }

    static func photoContextMenu(_ item: ChatRowItem, peer: Peer, setOpenProgress: @escaping (Signal<Never, NoError>) -> Void) -> () -> ContextMenu? {
        let chatInteraction = item.chatInteraction
        let authorStoryStats = item.entry.additionalData.authorStoryStats
        return { [weak chatInteraction] in
                    
                    let menu = ContextMenu()
                    
                    if let _ = authorStoryStats, let messageId = item.message?.id {
                        menu.addItem(ContextMenuItem(strings().chatContextPeerOpenStory, handler: { 
                            chatInteraction?.openChatPeerStories(messageId, peer.id, { signal in
                                setOpenProgress(signal)
                            })
                        }, itemImage: MenuAnimation.menu_stories.value))
                    }
                    
                    menu.addItem(ContextMenuItem(strings().chatContextPeerOpenInfo, handler: {
                        chatInteraction?.openInfoFromMessage(peer.id, false, nil, nil, message: item.message)
                    }, itemImage: MenuAnimation.menu_open_profile.value))
                    
                    menu.addItem(ContextMenuItem(strings().chatContextPeerSendMessage, handler: {
                        chatInteraction?.openInfoFromMessage(peer.id, true, nil, nil, message: item.message)
                    }, itemImage: MenuAnimation.menu_read.value))

                    menu.addItem(ContextMenuItem(strings().chatContextPeerMention, handler: {
                        let attr: NSMutableAttributedString = NSMutableAttributedString()

                        if let addressName = peer.addressName {
                            attr.append(string: "@\(addressName) ", font: .normal(theme.fontSize))
                        } else {
                            attr.append(string: peer.compactDisplayTitle + " ", font: .normal(theme.fontSize))
                            attr.addAttribute(TextInputAttributes.textMention, value: ChatTextInputTextMentionAttribute(peerId: peer.id), range: attr.range)
                        }
                        _ = chatInteraction?.appendText(attr)
                    }, itemImage: MenuAnimation.menu_atsign.value))

                    if let chatPeer = chatInteraction?.peer, (chatPeer.isGroup || chatPeer.isSupergroup), !chatPeer.isMonoForum, chatInteraction?.isLogInteraction == false, let mode = chatInteraction?.mode, mode == .history || mode.isThreadMode || mode.isTopicMode {
                        menu.addItem(ContextMenuItem(strings().shortcutsControllerChatSearchMessages, handler: {
                            chatInteraction?.searchPeerMessages(peer)
                        }, itemImage: MenuAnimation.menu_search.value))
                    }

                    if let channel = chatInteraction?.peer as? TelegramChannel, let context = chatInteraction?.interactionContext, peer.id != context.peerId {
                        
                        menu.addItem(ContextSeparatorItem())
                        
                        let canEditTag = !channel.isChannel && ((peer.id == context.peerId && channel.hasPermission(.editRank)) || channel.hasPermission(.manageRanks))
                        let authorId = peer.id
                        let peerId = channel.id

                        let fetchParticipant = context.engine.peers.fetchChannelParticipant(peerId: peerId, participantId: authorId)
                            |> mapToSignal { participant -> Signal<RenderedChannelParticipant?, NoError> in
                                guard let participant = participant else { return .single(nil) }
                                return context.account.postbox.loadedPeerWithId(authorId) |> map { peer in
                                    return RenderedChannelParticipant(participant: participant, peer: .init(peer))
                                }
                            }
                            |> take(1)
                            |> deliverOnMainQueue

                        if canEditTag {
                            menu.addItem(ContextMenuItem(strings().channelMemberEditTag, handler: {
                                _ = fetchParticipant.start(next: { rendered in
                                    if let rendered = rendered {
                                        showModal(with: ChatHistoryUIHooks.shared.makeChannelParticipantController(context, peerId, rendered), for: context.window)
                                    }
                                })
                            }, itemImage: MenuAnimation.menu_tag_rename.value))
                        }

                        if channel.hasPermission(.banMembers) {
                            menu.addItem(ContextMenuItem(strings().channelMemberRestrict, handler: {
                                _ = fetchParticipant.start(next: { rendered in
                                    if let rendered = rendered {
                                        showModal(with: ChatHistoryUIHooks.shared.makeRestrictedModalController(context, peerId, authorId, rendered.participant, { updatedRights in
                                            _ = context.peerChannelMemberCategoriesContextsManager.updateMemberBannedRights(peerId: peerId, memberId: authorId, bannedRights: updatedRights).start()
                                        }), for: context.window)
                                    }
                                })
                            }, itemImage: MenuAnimation.menu_restrict.value))
                        }

                        if channel.hasPermission(.addAdmins) {
                            menu.addItem(ContextMenuItem(strings().channelMemberPromote, handler: {
                                _ = fetchParticipant.start(next: { rendered in
                                    if let rendered = rendered {
                                        showModal(with: ChatHistoryUIHooks.shared.makeChannelAdminModalController(context, peerId, authorId, rendered.participant, { _ in }, { _, _ in }), for: context.window)
                                    }
                                })
                            }, itemImage: MenuAnimation.menu_promote.value))
                        }
                    }
                    return menu
        }
    }
    
    public func fillPhoto(_ item:ChatRowItem, animated: Bool) -> Void {
        if item.hasPhoto, let peer = item.peer, item.fillPhoto {
            if avatar == nil {
                avatar = ChatRowView.makePhotoView(item)
                rowView.addSubview(avatar!)
            }
            avatar?.setPeer(item: item, peer: peer, storyStats: item.entry.additionalData.authorStoryStats, message: item.message)
            
        } else {
            if let view = avatar {
                performSubviewRemoval(view, animated: animated, scale: true)
                self.avatar = nil
            }
        }
    }
    
    public func fillPsaButton(_ item: ChatRowItem, animated: Bool) -> Void {
        if let text = item.psaButton, item.forwardNameLayout != nil || !item.isBubbled {
            
            let icon = item.presentation.chat.channelInfoPromo(item.isIncoming, item.isBubbled, icons: theme.icons)
            
            if psaButton == nil {
                psaButton = ImageButton(frame: CGRect(origin: psaPoint(item), size: icon.backingSize))
                psaButton?.autohighlight = false
                psaButton?.setAccessibilityLabel(strings().voiceOverCommonInfo)
                rowView.addSubview(psaButton!)
                psaButton?.set(handler: { control in
                    tooltip(for: control, text: "", attributedText: text, interactions: LinkHooks.shared.globalLinkExecutor())
                }, for: .Click)
            }
            psaButton?.set(image: icon, for: .Normal)
            
        } else {
            if let view = psaButton {
                performSubviewRemoval(view, animated: animated, scale: true)
                psaButton = nil
            }
        }
    }
    
    public func fillStatus(_ item: ChatRowItem, animated: Bool) -> Void {
        if !ChatRowView.usesLegacyRowChrome, let scene = rowView as? ChatLayerRowView {
            if let view = statusControl {
                view.removeFromSuperview()
                statusControl = nil
            }
            let layer = item.statusLayer(scene.statusNode?.layer as? PremiumStatusLayer, animated: animated)
            scene.updateStatus(layer, origin: statusPoint(item), animated: animated, action: { [weak item] in
                item?.openInfo()
            })
            return
        }
        (rowView as? ChatLayerRowView)?.updateStatus(nil, origin: .zero, animated: false, action: {})
        
        if let status = item.status(self.statusControl, animated: animated) {
            rowView.addSubview(status)
            if self.statusControl == nil {
                status.setFrameOrigin(statusPoint(item))
            }
            self.statusControl = status
            
            status.userInteractionEnabled = true
            status.removeAllHandlers()
            status.set(handler: { [weak item] _ in
                item?.openInfo()
            }, for: .Click)
            
        } else if let view = statusControl {
            performSubviewRemoval(view, animated: animated)
            self.statusControl = nil
        }
    }
    
    public func fillFactCheck(_ item: ChatRowItem, animated: Bool) -> Void {
        if let layout = item.factCheckLayout {
            let current: FactCheckMessageView
            let isNew: Bool
            if let view = self.factCheckView {
                current = view
                isNew = false
            } else {
                current = FactCheckMessageView(frame: factCheckFrame(item))
                rowView.addSubview(current)
                isNew = true
                self.factCheckView = current
            }
            current.update(layout: layout, animated: animated && !isNew)
        } else if let view = factCheckView {
            performSubviewRemoval(view, animated: animated)
            self.factCheckView = nil
        }
    }
    
    
    public func fillCaption(_ item: ChatRowItem, animated: Bool) {
        if let state = captionBindingState, state.isUpdating {
            state.pending = (item, animated)
            return
        }
        guard !captionViews.isEmpty || !item.captionLayouts.isEmpty else { return }
        let state = captionBindingState ?? CaptionBindingState()
        captionBindingState = state
        state.isUpdating = true
        var nextItem = item
        var nextAnimated = animated
        while true {
            state.pending = nil
            updateCaptions(nextItem, animated: nextAnimated)
            guard let pending = state.pending else { break }
            nextItem = pending.0
            nextAnimated = pending.1
        }
        state.isUpdating = false
        if captionViews.isEmpty { captionBindingState = nil }
    }

    private func updateCaptions(_ item: ChatRowItem, animated: Bool) {
        let previous = captionViews
        let presentations = item.captionLayouts.map { ChatLayerMessageTextPresentation.simpleText($0.layout) }
        if previous.count == item.captionLayouts.count, previous.indices.allSatisfy({
            previous[$0].isSame(to: item.captionLayouts[$0]) && (previous[$0].layerView != nil) == (presentations[$0] != nil)
        }) {
            for index in previous.indices {
                previous[index].update(item.captionLayouts[index], presentation: presentations[index], animated: animated)
            }
            return
        }
        if !animated, previous.count == 1, item.captionLayouts.count == 1,
           previous[0].reuse(item.captionLayouts[0], presentation: presentations[0]) {
            let frame = captionFrame(item, caption: item.captionLayouts[0])
            if previous[0].view.frame != frame { previous[0].view.frame = frame }
            return
        }
        var used = Array(repeating: false, count: previous.count)
        var next = Array<CaptionView?>(repeating: nil, count: item.captionLayouts.count)

        for (index, caption) in item.captionLayouts.enumerated() {
            if let match = previous.indices.first(where: { !used[$0] && previous[$0].isSame(to: caption) }) {
                if previous[match].canKeepRenderer(for: caption, presentation: presentations[index], animated: animated) {
                    next[index] = previous[match]
                    used[match] = true
                } else if let layout = previous[match].layout {
                    let selections = layout.blocks.map { ($0.text.attributedString.string, $0.text.selectedRange) }
                    used[match] = true
                    previous[match].prepareForRemoval()
                    performSubviewRemoval(previous[match].view, animated: animated)
                    for (old, new) in zip(selections, caption.layout.blocks)
                    where old.0 == new.text.attributedString.string && new.text.mayItems && new.text.selectedRange.range.location == NSNotFound {
                        new.text.selectedRange = old.1
                    }
                }
            }
        }

        for (index, caption) in item.captionLayouts.enumerated() {
            let presentation = presentations[index]
            var current = next[index]
            var didReuseContent = false
            if current == nil, !animated {
                let matchingId = previous.indices.first(where: { !used[$0] && previous[$0].id == caption.id })
                if let match = matchingId, previous[match].reuse(caption, presentation: presentation) {
                    current = previous[match]
                    used[match] = true
                    didReuseContent = true
                } else if let match = previous.indices.first(where: {
                    !used[$0] && $0 != matchingId && previous[$0].reuse(caption, presentation: presentation)
                }) {
                    current = previous[match]
                    used[match] = true
                    didReuseContent = true
                }
            }

            let isNewView = current == nil
            if current == nil {
                let view: View = presentation == nil ? FoldingTextView(frame: .zero) : ChatLayerMessageTextView(frame: .zero)
                current = CaptionView(id: caption.id, shim: caption.isLoading, view: view)
                let revealBlockAtIndex: (Int) -> Void = { [weak self, weak current] blockIndex in
                    if let item = self?.item as? ChatRowItem, let messageId = current?.messageId {
                        item.revealBlockAtIndex(blockIndex, messageId: messageId)
                    }
                }
                current?.nativeView?.revealBlockAtIndex = revealBlockAtIndex
                current?.layerView?.body.revealBlockAtIndex = revealBlockAtIndex
            }
            guard let current else { continue }
            if isNewView {
                rowView.addSubview(current.view, positioned: .below, relativeTo: contentView)
                current.view.frame = captionFrame(item, caption: caption)
                if animated { current.view.layer?.animateAlpha(from: 0, to: 1, duration: 0.2) }
            } else if didReuseContent {
                let frame = captionFrame(item, caption: caption)
                if current.view.frame != frame { current.view.frame = frame }
            }
            if !didReuseContent { current.update(caption, presentation: presentation, animated: animated) }
            next[index] = current
        }
        captionViews = next.compactMap { $0 }
        for index in previous.indices where !used[index] {
            previous[index].prepareForRemoval()
            performSubviewRemoval(previous[index].view, animated: animated)
        }
    }

    public override func updateAnimatableContent() -> Void {
        topicLinkView?.updateAnimatableContent()
        captionViews.forEach { $0.layerView?.updateInlineEmojiVisibility() }
    }
    
    public override var isEmojiLite: Bool {
        if let item = item as? ChatRowItem {
            return item.context.isLite(.emoji)
        }
        return super.isEmojiLite
    }
    
    
    public func reactionsRect(_ item: ChatRowItem) -> CGRect {
        guard let reactionsLayout = item.reactionsLayout else {
            return .zero
        }
        let contentFrame = self.cachedContentFrame(item)
        
        var frame = NSMakeRect(contentFrame.minX + item.elementsContentInset, contentFrame.maxY + item.defaultReplyMarkupInset, reactionsLayout.size.width, reactionsLayout.size.height)
        
        if let captionLayout = item.captionLayouts.first?.layout, !item.invertMedia {
            var ignore: Bool = false
            if let item = item as? ChatGroupedItem, !item.isBubbled {
                if item.layoutType == .files {
                    ignore = true
                }
            }
            if !ignore {
                frame.origin.y += captionLayout.size.height + item.defaultContentInnerInset
            }
        }
        
        if self is LiveLocationRowView, !reactionsLayout.presentation.isOutOfBounds {
            frame.origin.y += 40
        }
        
        
        let bubbleFrame = self.bubbleFrame(item)
        
        if item.hasBubble {
            if item.isBubbleFullFilled, item.captionLayouts.isEmpty {
                frame.origin.y = bubbleFrame.maxY + item.defaultReactionsInset
                frame.origin.x = bubbleFrame.minX + (item.isIncoming ? item.additionBubbleInset : 0)
            } else {
                if item.captionLayouts.isEmpty {
                    frame.origin.y = contentFrame.maxY + item.defaultReactionsInset
                } else if let last = item.captionLayouts.last {
                    frame.origin.y = max(contentFrame.maxY, captionFrame(item, caption: last).maxY) + item.defaultReactionsInset
                }
                if !item.isBubbleFullFilled {
                    frame.origin.x = contentFrame.minX
                } else {
                    frame.origin.x = contentFrame.minX + item.defaultReactionsInset + item.additionBubbleInset
                }
                
            }
           
        } else if item.isBubbled {
            if item.isBigEmoji {
                frame.origin.y = bubbleFrame.maxY + item.defaultReactionsInset
            }
//            if let item = item as? ChatMessageItem {
//                if item.containsBigEmoji {
//                    frame.origin.y += rightFrame(item).height
//                }
//            }
        } else if let replyMarkup = item.replyMarkupModel {
            frame.origin.y += replyMarkup.size.height + item.defaultContentInnerInset
        }
        if reactionsLayout.presentation.isOutOfBounds, !item.isIncoming {
            frame.origin.x = contentFrame.maxX - reactionsLayout.size.width
        } else if reactionsLayout.presentation.isOutOfBounds {
            if let replyMarkupModel = item.replyMarkupModel {
                frame.origin.y += replyMarkupModel.size.height + item.defaultContentInnerInset
            }
        }
        if let factCheckLayout = item.factCheckLayout {
            frame.origin.y += factCheckLayout.size.height + item.defaultContentInnerInset
        }
        return frame
    }
    
    public func channelCommentsBubbleFrame(_ item: ChatRowItem) -> CGRect {
        guard let comments = item.commentsBubbleData else {
            return .zero
        }
        var x: CGFloat = 0
        if !item.isBubbled, let _ = forwardLine {
            x += 10
        }
        return NSMakeRect(x, 0, item.isBubbled ? item.bubbleFrame.width : max(item.contentSize.width - x, comments.size(true).width + 10), ChatRowItem.channelCommentsBubbleHeight)
    }
    public func channelCommentsOverlayFrame(_ item: ChatRowItem) -> CGRect {
        guard let commentsData = item.commentsBubbleDataOverlay else {
            return .zero
        }
        let size = commentsData.size(false, true)
        let rightFrame = self.rightFrame(item)
        var rect = NSMakeRect(rightFrame.maxX + 19, rightFrame.minY - size.height - 15, size.width, size.height)
        if item.isInstantVideo {
            rect = NSMakeRect(rightFrame.maxX + 12, rightFrame.minY - size.height - 23, size.width, size.height)
        } else if let item = item as? ChatMessageItem, item.containsBigEmoji {
            rect.origin.x -= 8
            rect.origin.y -= 8
        }
        return rect
    }
    
    public func fillChannelComments(_ item: ChatRowItem, animated: Bool) {
        if let commentsBubbleData = item.commentsBubbleData {
            let current: ChannelCommentsBubbleControl
            if let channelCommentsBubbleControl = self.channelCommentsBubbleControl {
                current = channelCommentsBubbleControl
            } else {
                current = ChannelCommentsBubbleControl(frame: NSMakeRect(0, 0, item.bubbleFrame.width, ChatRowItem.channelCommentsBubbleHeight))
                                
                self.channelCommentsBubbleControl = current
                bubbleView.addSubview(current)
            }
            current.update(data: commentsBubbleData, size: channelCommentsBubbleFrame(item).size, animated: animated)
        } else {
            if let channelCommentsBubbleControl = self.channelCommentsBubbleControl {
                performSubviewRemoval(channelCommentsBubbleControl, animated: animated)
                self.channelCommentsBubbleControl = nil
            }
        }
        if let data = item.commentsBubbleDataOverlay {
            let current: ChannelCommentsSmallControl
            if let channelCommentsBubbleSmallControl = self.channelCommentsBubbleSmallControl {
                current = channelCommentsBubbleSmallControl
            } else {
                current = ChannelCommentsSmallControl(frame: CGRect(origin: .zero, size: data.size(false, true)))
                current.set(background: item.presentation.chatServiceItemColor, for: .Normal)
                
                current.change(opacity: 0, animated: animated)
                self.channelCommentsBubbleSmallControl = current
                rowView.addSubview(current)
            }
            if item.shouldBlurService {
                current.set(background: .clear, for: .Normal)
                current.blurBackground = item.presentation.blurServiceColor
            } else {
                current.set(background: contentColor, for: .Normal)
                current.blurBackground = nil
            }
            current.scaleOnClick = true
            current.update(data: data, size: channelCommentsOverlayFrame(item).size, animated: animated)
            current.change(pos: channelCommentsOverlayFrame(item).origin, animated: animated)
        } else {
            if let channelCommentsBubbleSmallControl = self.channelCommentsBubbleSmallControl {
                self.channelCommentsBubbleSmallControl = nil
                if animated {
                    channelCommentsBubbleSmallControl.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak channelCommentsBubbleSmallControl] _ in
                        channelCommentsBubbleSmallControl?.removeFromSuperview()
                    })
                } else {
                    channelCommentsBubbleSmallControl.removeFromSuperview()
                }
            }
        }
        self.channelCommentsBubbleControl?.isEnabled = !item.isFailed && !item.isUnsent
        self.channelCommentsBubbleSmallControl?.isEnabled = !item.isFailed && !item.isUnsent

    }
    
    public func fillShareView(_ item:ChatRowItem, animated: Bool) -> Void {
        let shouldShow = item.shareVisible || item.hasSource
        shareVisibleForCurrentItem = shouldShow

        if !shouldShow {
            if let view = shareView {
                self.shareView = nil
                performSubviewRemoval(view, animated: animated, scale: true)
            }
        } else if shareView != nil {
            configureShareView(item)
        }
        updateMouse(animated: animated)
    }

    private func configureShareView(_ item: ChatRowItem) {
        guard let control = shareView else { return }
        control.autohighlight = false
        control.setAccessibilityLabel(item.hasSource ? strings().voiceOverChatGoToOriginalMessage : strings().voiceOverCommonShare)

        if item.isBubbled, item.presentation.backgroundMode.hasWallpaper {
            control.set(image: item.hasSource ? item.presentation.chat.chat_goto_message_bubble(theme: item.presentation) : item.presentation.chat.chat_share_bubble(theme: item.presentation), for: .Normal)
            control.set(cornerRadius: .half, for: .Normal)
            control.blurBackground = item.presentation.blurServiceColor
            control.background = .clear
        } else if item.presentation.backgroundMode.hasWallpaper {
            control.set(image: item.hasSource ? item.presentation.chat.chat_goto_message_bubble(theme: item.presentation) : item.presentation.chat.chat_share_bubble(theme: item.presentation), for: .Normal)
            control.backgroundColor = item.presentation.chatServiceItemColor
            control.blurBackground = nil
        } else {
            control.set(image: item.hasSource ? item.presentation.icons.chat_goto_message : item.presentation.icons.chat_share_message, for: .Normal)
            control.backgroundColor = .clear
            control.blurBackground = nil
        }
        let size = NSMakeSize(26, 26)
        control.setFrameSize(NSMakeSize(floorToScreenPixels(backingScaleFactor, (size.width + 4) * 1.05), floorToScreenPixels(backingScaleFactor, (size.height + 4) * 1.05)))
        control.set(cornerRadius: .half, for: .Normal)

        control.removeAllHandlers()
        control.set(handler: { [weak item] _ in
            if let item = item {
                if item.hasSource {
                    item.gotoSourceMessage()
                } else {
                    item.share()
                }
            }
        }, for: .Click)
    }
    
    public func fillReactions(_ item: ChatRowItem, animated: Bool) {
        if let reactionsLayout = item.reactionsLayout  {
            if reactionsView == nil {
                reactionsView = ChatReactionsView(frame: reactionsRect(item))
                rowView.addSubview(reactionsView!)
            }
            guard let reactionsView = reactionsView else {return}
            reactionsView.update(with: reactionsLayout, animated: animated)
        } else {
            if let view = self.reactionsView {
                self.reactionsView = nil
                performSubviewRemoval(view, animated: animated, scale: true)
            }
        }
    }
    
    public func fillReplyMarkup(_ item:ChatRowItem, animated: Bool) -> Void {
        if let replyMarkup = item.replyMarkupModel {
            if replyMarkupView == nil {
                replyMarkupView = ReplyMarkupContainerView(frame: replyMarkupFrame(item))
                rowView.addSubview(replyMarkupView!)
            }
            replyMarkup.view = replyMarkupView
            replyMarkup.redraw()
        } else {
            if let replyMarkupView = self.replyMarkupView, animated {
                self.replyMarkupView = nil
                replyMarkupView.layer?.animateScaleCenter(from: 1, to: 0.1, duration: 0.2, removeOnCompletion: false)
                replyMarkupView.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak replyMarkupView] _ in
                    replyMarkupView?.removeFromSuperview()
                })
            } else {
                replyMarkupView?.removeFromSuperview()
                replyMarkupView = nil
            }
        }
    }
    
    
    
    public func fillName(_ item:ChatRowItem, animated: Bool) -> Void {
        if let author = item.authorText {
            if item.isBubbled && !item.hasBubble {
                (rowView as? ChatLayerRowView)?.updateSenderName(nil, toolTip: nil, frame: .zero, animated: animated)
                (rowView as? ChatLayerRowView)?.updateAdminBadge(nil, origin: .zero, background: nil, backgroundFrame: .zero, interactive: false, animated: animated, action: {})
                if let view = adminBadge {
                    performSubviewRemoval(view, animated: animated, scale: true)
                    self.adminBadge = nil
                }
                if let view = adminBadgeBg {
                    performSubviewRemoval(view, animated: animated, scale: true)
                    self.adminBadgeBg = nil
                }
                if let view = boostBadge {
                    performSubviewRemoval(view, animated: animated, scale: true)
                    self.boostBadge = nil
                }

                if viaAccessory == nil {
                    viaAccessory = ChatBubbleViaAccessory(frame: NSZeroRect)
                }
                guard let viaAccessory = viaAccessory else {return}
                viaAccessory.removeFromSuperview()
                if replyView != nil {
                    replyView?.addSubview(viaAccessory)
                } else {
                    rowView.addSubview(viaAccessory)
                }
                viaAccessory.updateText(layout: author)
            } else {
                if let view = viaAccessory {
                    performSubviewRemoval(view, animated: animated, scale: true)
                    self.viaAccessory = nil
                }
                
                (rowView as? ChatLayerRowView)?.updateSenderName(author, toolTip: item.nameHide, frame: CGRect(origin: namePoint(item), size: author.layoutSize), animated: animated)
                if let boostBadge = item.boostBadge {
                    if self.boostBadge == nil {
                        self.boostBadge = InteractiveTextView(frame: CGRect(origin: boostBadgePoint(item), size: boostBadge.layoutSize))
                        self.boostBadge?.scaleOnClick = true
                        rowView.addSubview(self.boostBadge!)
                    }
                    self.boostBadge?.removeAllHandlers()
                    self.boostBadge?.set(handler: { [weak item, weak self] _ in
                        item?.boost(morphSource: { [weak self] in self?.boostBadge })
                    }, for: .Click)
                    self.boostBadge?.set(text: boostBadge, context: item.context)
                } else {
                    if let view = boostBadge {
                        performSubviewRemoval(view, animated: animated, scale: true)
                        self.boostBadge = nil
                    }
                }
                if let adminBadge = item.adminBadge, !usesAdminBadgeNode(item) {
                    if self.adminBadge == nil {
                        self.adminBadge = TextView(frame: CGRect(origin: adminBadgePoint(item), size: adminBadge.layoutSize))
                        self.adminBadge?.isSelectable = false
                        rowView.addSubview(self.adminBadge!)
                    }
                    self.adminBadge?.update(adminBadge)
                    self.adminBadge?.removeAllHandlers()
                    if item.adminBadgeAuthorId == nil { self.adminBadge?.controlState = .Normal }
                    self.adminBadge?.scaleOnClick = item.adminBadgeAuthorId != nil
                    self.adminBadge?.userInteractionEnabled = item.adminBadgeAuthorId != nil
                    if item.adminBadgeAuthorId != nil {
                        self.adminBadge?.set(handler: { [weak item] control in
                            item?.adminBadgeInteraction(control)
                        }, for: .Click)
                    }
                    if item.adminBadgeIsRank, let color = item.adminBadgeColor {
                        if self.adminBadgeBg == nil {
                            self.adminBadgeBg = View()
                            rowView.addSubview(self.adminBadgeBg!, positioned: .below, relativeTo: self.adminBadge)
                        }
                        self.adminBadgeBg?.background = color.withAlphaComponent(0.2)
                        let bgFrame = adminBadgeBgRect(item)
                        self.adminBadgeBg?.frame = bgFrame
                        self.adminBadgeBg?.layer?.cornerRadius = bgFrame.height / 2
                    } else {
                        if let view = adminBadgeBg {
                            performSubviewRemoval(view, animated: animated, scale: true)
                            self.adminBadgeBg = nil
                        }
                    }
                } else {
                    if let view = adminBadge {
                        performSubviewRemoval(view, animated: animated, scale: true)
                        self.adminBadge = nil
                    }
                    if let view = adminBadgeBg {
                        performSubviewRemoval(view, animated: animated, scale: true)
                        self.adminBadgeBg = nil
                    }
                }
                if usesAdminBadgeNode(item) {
                    (rowView as? ChatLayerRowView)?.updateAdminBadge(item.adminBadge, origin: adminBadgePoint(item), background: item.adminBadgeIsRank ? item.adminBadgeColor : nil, backgroundFrame: adminBadgeBgRect(item), interactive: item.adminBadgeAuthorId != nil, animated: animated, action: { [weak item, weak self] in
                        guard let self else { return }
                        item?.adminBadgeInteraction(self.rowView)
                    })
                } else {
                    (rowView as? ChatLayerRowView)?.updateAdminBadge(nil, origin: .zero, background: nil, backgroundFrame: .zero, interactive: false, animated: false, action: {})
                }
            }

        } else {
            if let view = viaAccessory {
                performSubviewRemoval(view, animated: animated, scale: true)
                self.viaAccessory = nil
            }
            (rowView as? ChatLayerRowView)?.updateSenderName(nil, toolTip: nil, frame: .zero, animated: animated)
            (rowView as? ChatLayerRowView)?.updateAdminBadge(nil, origin: .zero, background: nil, backgroundFrame: .zero, interactive: false, animated: animated, action: {})
            if let view = adminBadge {
                performSubviewRemoval(view, animated: animated, scale: true)
                self.adminBadge = nil
            }
            if let view = adminBadgeBg {
                performSubviewRemoval(view, animated: animated, scale: true)
                self.adminBadgeBg = nil
            }
            if let view = boostBadge {
                performSubviewRemoval(view, animated: animated, scale: true)
                self.boostBadge = nil
            }
        }

        if let badge = item.guestChatBadge {
            if self.ephemeralBadgeView == nil {
                self.ephemeralBadgeView = InteractiveTextView(frame: .zero)
                self.ephemeralBadgeView?.userInteractionEnabled = false
                self.ephemeralBadgeView?.textView.isSelectable = false
                rowView.addSubview(self.ephemeralBadgeView!)
            }
            self.ephemeralBadgeView?.set(text: badge, context: item.context, emojiOffset: NSMakePoint(2, 1))
            self.ephemeralBadgeView?.setFrameSize(badge.layoutSize)
            self.ephemeralBadgeView?.setFrameOrigin(ephemeralBadgePoint(item))
        } else if let view = ephemeralBadgeView {
            performSubviewRemoval(view, animated: animated, scale: true)
            self.ephemeralBadgeView = nil
        }
    }
    
    
    
    public override func focusAnimation(_ innerId: AnyHashable?, text: String?) {
        
        guard let item = item as? ChatRowItem else {
            return
        }
        
        if let text = text, !text.isEmpty, !item.isBubbled {
            return
        }
        
        if animatedView == nil {
            self.animatedView = RowAnimateView(frame:bounds)
            self.animatedView?.isEventLess = true
            if text == nil {
                rowView.addSubview(animatedView!)
            } else {
                rowView.addSubview(animatedView!, positioned: .below, relativeTo: bubbleView)
            }
            animatedView?.backgroundColor = theme.colors.focusAnimationColor
            animatedView?.layer?.opacity = 0
            
        }
        animatedView?.stableId = item.stableId
        
        
        let animation: CABasicAnimation = makeSpringAnimation("opacity")
        
        animation.fromValue = animatedView?.layer?.presentation()?.opacity ?? 0
        animation.toValue = 0.5
        animation.autoreverses = true
        animation.isRemovedOnCompletion = true
        animation.fillMode = CAMediaTimingFillMode.forwards
        
        animation.delegate = CALayerAnimationDelegate(completion: { [weak self] completed in
            if completed {
                self?.animatedView?.removeFromSuperview()
                self?.animatedView = nil
            }
        })
        animation.isAdditive = false
        
        animatedView?.layer?.add(animation, forKey: "opacity")
    }
    
    
    public enum ScreenEffectMode {
        case effect
        case reaction(MessageReaction.Reaction)
    }
    public func getReactionChip(_ value: MessageReaction.Reaction) -> ReactionViewImpl? {
        return reactionsView?.getView(value)
    }

    public func getScreenEffectView(_ mode: ScreenEffectMode) -> NSView? {
        switch mode {
        case .effect:
            if let effectView = rightView.effectView {
                return effectView
            } else if let effectView = rightView.effectTextView {
                return effectView
            } else  if let media = self as? ChatMediaView {
                return media.contentNode
            }
        case let .reaction(value):
            if let reactionsView = reactionsView {
                return reactionsView.getReactionView(value)
            }
        }
        return nil
    }
    
    public func playSeenReactionEffect(_ checkUnseen: Bool) {
        if let reactionsView = reactionsView {
            reactionsView.playSeenReactionEffect(checkUnseen)
        }
    }
    
    public func canDropSelection(in location: NSPoint) -> Bool {
        return true
    }

    public override func rightMouseDown(with event: NSEvent) {
        if let item = self.item as? ChatRowItem {
            if item.chatInteraction.presentation.state == .selecting {
                let selectedIds = item.chatInteraction.presentation.selectionState?.selectedIds ?? []
                guard selectedIds.count > 1, item.messages.contains(where: { message in
                    selectedIds.contains(message.id) && message.media.contains(where: { $0 is TelegramMediaImage })
                }) else {
                    return
                }
            }
        }
        super.rightMouseDown(with: event)
    }
    
  
    
    private func renderLayoutType(_ item: ChatRowItem, animated: Bool) {
        if item.isBubbled, item.hasBubble {
            bubbleView.setType(image: item.bubbleImage, border: nil, background: item.isIncoming ? item.presentation.icons.chatGradientBubble_incoming : item.presentation.icons.chatGradientBubble_outgoing)
        } else {
            bubbleView.setType(image: nil, border: nil, background: item.isIncoming ? item.presentation.icons.chatGradientBubble_incoming : item.presentation.icons.chatGradientBubble_outgoing)
        }
        applyCutBands(item)
    }

    /// Bands of the bubble that must be erased so the wallpaper shows through, in bubble-local
    /// coordinates. The base row never cuts its bubble — this is also what resets a reused view, so a
    /// hole can't survive onto an unrelated message.
    public func cutBands(_ item: ChatRowItem) -> [CGRect] {
        return []
    }

    /// A frosted surface sitting in a cut band, in bubble-local coordinates. Rendered below
    /// `bubbleView`, so the wallpaper reads through it blurred while the sharp content is drawn on top.
    public struct FrostedPanel {
        public let rect: CGRect
        public let cornerRadius: CGFloat
        /// `VisualEffect.bgColor`.
        public let blurTint: NSColor
        /// The flat fill standing in for the blur under `isLite(.blur)`.
        public let flatColor: NSColor
        /// An alpha mask shaping a non-rectangular frosted surface — a silhouette rather than a rounded
        /// rect. The corner radius still applies, and is simply irrelevant once a mask is set.
        public let mask: CGImage?

        public init(rect: CGRect, cornerRadius: CGFloat, blurTint: NSColor, flatColor: NSColor, mask: CGImage? = nil) {
            self.rect = rect
            self.cornerRadius = cornerRadius
            self.blurTint = blurTint
            self.flatColor = flatColor
            self.mask = mask
        }
    }

    /// The frosted surfaces to render in this row's cut bands. The base row has none — which is also
    /// what strips them off a reused view, so a panel can't survive onto an unrelated message.
    public func frostedPanels(_ item: ChatRowItem) -> [FrostedPanel] {
        return []
    }

    /// Cuts the bands out of the bubble and renders the row's frosted surfaces below `bubbleView`, so
    /// the bubble's own mask clips them to the torn edges.
    private func applyCutBands(_ item: ChatRowItem) {
        bubbleView.setCutBands(self.cutBands(item), incoming: item.isIncoming)

        let panels = self.frostedPanels(item)

        let isBlurred = !item.context.isLite(.blur)

        if let first = cutBandViews.first, (first is VisualEffect) != isBlurred {
            for view in cutBandViews {
                view.removeFromSuperview()
            }
            cutBandViews = []
        }

        while cutBandViews.count > panels.count {
            cutBandViews.removeLast().removeFromSuperview()
        }
        while cutBandViews.count < panels.count {
            let view: NSView = isBlurred ? VisualEffect(frame: .zero) : View(frame: .zero)
            rowView.addSubview(view, positioned: .below, relativeTo: bubbleView)
            cutBandViews.append(view)
        }

        guard !panels.isEmpty else {
            return
        }

        let origin = bubbleFrame(item).origin

        for (i, panel) in panels.enumerated() {
            let view = cutBandViews[i]
            view.frame = panel.rect.offsetBy(dx: origin.x, dy: origin.y)
            // `VisualEffect` tints through a sublayer, so a bare corner radius would leave the tint square.
            view.layer?.cornerRadius = panel.cornerRadius
            view.layer?.masksToBounds = true
            // The mask is always assigned, `nil` included: these views are recycled across rows, and a
            // silhouette left on a reused panel would eat most of it.
            if let view = view as? VisualEffect {
                view.bgColor = panel.blurTint
                // `maskContents` and not `maskImage`: the latter shapes only the material, leaving the
                // tint a full rectangle around the silhouette.
                view.maskContents = panel.mask
            } else if let view = view as? View {
                view.backgroundColor = panel.flatColor
                if let mask = panel.mask {
                    let maskLayer = view.layer?.mask ?? CALayer()
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    maskLayer.contents = mask
                    maskLayer.frame = view.bounds
                    view.layer?.mask = maskLayer
                    CATransaction.commit()
                } else {
                    view.layer?.mask = nil
                }
            }
        }
    }
    
    public func shakeContentView() {
        
        guard let item = item as? ChatRowItem else { return }
        
        if bubbleView.layer?.animation(forKey: "shake") != nil {
            return
        }
        
        let translation = CAKeyframeAnimation(keyPath: "transform.translation.x");
        translation.timingFunction = CAMediaTimingFunction(name: .linear)
        translation.values = [-2, 2, -2, 2, -2, 2, -2, 2, 0]
        
        let rotation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        rotation.values = [-0.5, -0.5, -0.5, 0.5, -0.5, 0.5, -0.5, -0.5, 0].map {
            ( degrees: Double) -> Double in
            let radians: Double = (.pi * degrees) / 180.0
            return radians
        }
        
        let shakeGroup: CAAnimationGroup = CAAnimationGroup()
        shakeGroup.isRemovedOnCompletion = true
        shakeGroup.animations = [rotation]
        shakeGroup.timingFunction = .init(name: .easeInEaseOut)
        shakeGroup.duration = 0.5
        
        
        
        let frame = bubbleFrame(item)
        let contentFrame = self.contentFrameModifier(item)
        
        
        contentView.layer?.position = NSMakePoint(contentFrame.minX + contentFrame.width / 2, contentFrame.minY + contentFrame.height / 2)
        contentView.layer?.anchorPoint = NSMakePoint(0.5, 0.5);
        
        if item.hasBubble {
            let restoreSenderName = (rowView as? ChatLayerRowView)?.moveSenderNameForShake(into: bubbleView)
            let restoreForwardName = (rowView as? ChatLayerRowView)?.moveForwardNameForShake(into: bubbleView)
            let restoreStatus = (rowView as? ChatLayerRowView)?.moveStatusForShake(into: bubbleView)
            let restoreAdminBadge = (rowView as? ChatLayerRowView)?.moveAdminBadgeForShake(into: bubbleView)
            let restoreReply = replyNode.flatMap { (rowView as? ChatLayerRowView)?.moveChromeNodeForShake($0, into: bubbleView) }
            struct ShakeItem {
                let view: NSView
                let rect: NSRect
                let tempRect: NSRect
            }
            let restoreRight = moveHostedRightForShake()
            var views:[NSView] = [self.rightView.isContentHosted ? nil : self.rightView, self.statusControl, self.forwardStatusControl, self.replyView, self.adminBadge, self.adminBadgeBg, self.boostBadge, self.forwardPhoto, self.viaAccessory].compactMap { $0 }
            views.append(contentsOf: self.captionViews.map { $0.view })
            let shakeItems = views.map { view -> ShakeItem in
                return ShakeItem(view: view, rect: view.frame, tempRect: self.bubbleView.convert(view.frame, from: view.superview))
            }
            
            for item in shakeItems {
                item.view.removeFromSuperview()
                item.view.frame = item.tempRect
                bubbleView.addSubview(item.view)
            }
            
            
            shakeGroup.delegate = CALayerAnimationDelegate(completion: { [weak self] _ in
                restoreSenderName?()
                restoreForwardName?()
                restoreStatus?()
                restoreAdminBadge?()
                restoreReply?()
                restoreRight?()
                guard let `self` = self else {
                    return
                }
                for item in shakeItems {
                    item.view.removeFromSuperview()
                    item.view.frame = item.rect
                    self.rowView.addSubview(item.view)
                }
            })
        }
        
        bubbleView.layer?.position = NSMakePoint(frame.minX + frame.width / 2, frame.minY + frame.height / 2)
        bubbleView.layer?.anchorPoint = NSMakePoint(0.5, 0.5);

        
        bubbleView.layer?.add(shakeGroup, forKey: "shake")
        contentView.layer?.add(shakeGroup, forKey: "shake")

        
    }
    
    public override func set(item:TableRowItem, animated:Bool = false) {
        #if DEBUG
        ChatMergeProbe.noteBind(previous: self.item, next: item)
        #endif
        invalidateFrameCache()
        let previousItem = self.item as? ChatRowItem

        super.set(item: item, animated: animated)

       
        if observedInteraction !== (item as? ChatRowItem)?.chatInteraction {
            updateInteractionObserver(nil)
        }
        guard let item = item as? ChatRowItem else {
            return
        }
        isPreparingItem = true
        
        if self.animatedView != nil && self.animatedView?.stableId != item.stableId {
            self.animatedView?.removeFromSuperview()
            self.animatedView = nil
        }
        
        let animated = animated && item.presentation.bubbled == previousItem?.presentation.bubbled
        
        
        if previousItem?.message?.id != item.message?.id {
            updateBackground(animated: false, item: item, clean: true)
        }
        
        renderLayoutType(item, animated: animated)

        updateInteractionObserver(item.chatInteraction)
        
        updateSelectingState(selectingMode:item.chatInteraction.presentation.selectionState != nil, item: item, needUpdateColors: false)
        
        rightView.set(item:item, animated:animated)
        updateRightHosting(item)
        fillTopicLink(item, animated: animated)
        fillReply(item, animated: animated)
        fillName(item, animated: animated)
        fillForward(item, animated: animated)
        fillForwardHeader(item, animated: animated)
        fillForwardLine(item, animated: animated)
        fillPhoto(item, animated: animated)
        fillStatus(item, animated: animated)
        fillPsaButton(item, animated: animated)
        fillShareView(item, animated: animated)
        fillReactions(item, animated: animated)
        fillReplyMarkup(item, animated: animated)
        fillCaption(item, animated: animated)
        fillFactCheck(item, animated: animated)
        fillChannelComments(item, animated: animated)
        
        //self.needsLayout = true

    }

    open override func interactionContentView(for innerId: AnyHashable, animateIn: Bool ) -> NSView {
        return self.contentView
    }
    
    public func isAllowedToDoubleAction(_ location: NSPoint) -> Bool {
        if let item = self.item as? ChatRowItem, item.chatInteraction.presentation.canReplyInRestrictedMode {
            let hitView = self.hitTest(location)
            if !clickInContent(point: location), hitView == nil || hitView == self || hitView == rowView || hitView == bubbleView || hitView == replyView {
                if let avatar = avatar {
                    if NSPointInRect(location, avatar.frame) {
                        return false
                    }
                }
                if let message = item.message, canReplyMessage(message, peerId: item.chatInteraction.peerId, chatLocation: item.chatInteraction.chatLocation, mode: item.chatInteraction.mode) {
                    return true
                }
            }
        }
        return false
    }
    
    public override func doubleClick(in location: NSPoint) {
        if let item = self.item as? ChatRowItem, isAllowedToDoubleAction(location), let message = item.message {
            item.chatInteraction.setupReplyMessage(message, .init(messageId: message.id, quote: nil, innerSubject: nil))
        }
    }
    
    public override func canAnimateUpdate(_ item: TableRowItem) -> Bool {
        guard let item = item as? ChatRowItem else {
            return false
        }
        
        let previous = self.item as? ChatRowItem
        
        if item.presentation.bubbled != previous?.presentation.bubbled {
            return false
        }
        
        return super.canAnimateUpdate(item)
    }
    
    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        invalidateFrameCache()
        guard let item = item as? ChatRowItem else {
            return
        }

        hasBeenLayout = true
                
        transition.updateFrame(view: bubbleView, frame: bubbleFrame(item))
        applyCutBands(item)
        bubbleView.updateLayout(size: bubbleView.frame.size, transition: transition)
        transition.updateFrame(view: contentView, frame: contentFrameModifier(item))
        
        
        transition.updateFrame(view: rowView, frame: CGRect(origin: rowPoint(item), size: size))
        
        updateBackground(animated: transition.isAnimated, item: item)
        
        (rowView as? ChatLayerRowView)?.layoutForwardName(origin: forwardNamePoint(item), transition: transition)
        if let view = forwardPhoto {
            transition.updateFrame(view: view, frame: CGRect(origin: forwardPhotoPoint(item), size: view.frame.size))
        }
        (rowView as? ChatLayerRowView)?.layoutForwardHeader(frame: forwardHeaderRect(item), transition: transition)
        if let layer = forwardLine {
            transition.updateFrame(layer: layer, frame: forwardLineRect(item))
        }
        
        if let view = forwardAccessory {
            transition.updateFrame(view: view, frame: CGRect(origin: forwardNamePoint(item), size: view.frame.size))
        }

        if rightView.superview == rowView {
            transition.updateFrame(view: rightView, frame: rightFrame(item))
            rightView.updateLayout(size: rightView.frame.size, transition: transition)
        } else if rightView.isContentHosted {
            let frame = rightFrame(item)
            rightView.updateHostedFrame(frame, transition: transition)
            rightView.updateLayout(size: frame.size, transition: transition)
            rightToolTip?.update(rowView, rect: frame, force: false)
        }

        (rowView as? ChatLayerRowView)?.layoutSenderName(origin: namePoint(item), transition: transition)
        if let view = ephemeralBadgeView, let badge = item.guestChatBadge {
            transition.updateFrame(view: view, frame: CGRect(origin: ephemeralBadgePoint(item), size: badge.layoutSize))
        }

        if let view = adminBadge {
            transition.updateFrame(view: view, frame: CGRect(origin: adminBadgePoint(item), size: view.frame.size))
        }
        if let view = adminBadgeBg, let _ = item.adminBadge {
            let bgFrame = adminBadgeBgRect(item)
            transition.updateFrame(view: view, frame: bgFrame)
            view.layer?.cornerRadius = bgFrame.height / 2
        }
        if let scene = rowView as? ChatLayerRowView, scene.hasAdminBadgeNode {
            #if DEBUG
            let badgeShift = ChatRowView.parityBadgeMutation
            #else
            let badgeShift: CGFloat = 0
            #endif
            scene.layoutAdminBadge(origin: adminBadgePoint(item).offsetBy(dx: badgeShift, dy: 0), backgroundFrame: adminBadgeBgRect(item).offsetBy(dx: badgeShift, dy: 0), transition: transition)
        }
        if let view = boostBadge {
            transition.updateFrame(view: view, frame: CGRect(origin: boostBadgePoint(item), size: view.frame.size))
        }
        if let view = viaAccessory {
            transition.updateFrame(view: view, frame: CGRect(origin: viaAccesoryPoint(item), size: view.frame.size))
        }
        if let view = topicLinkView, view.superview == rowView {
            let frame = topicLinkFrame(item)
            transition.updateFrame(view: view, frame: frame)
            view.updateLayout(size: frame.size, transition: transition)
        }
        if let view = item.replyModel?.view, view.superview == rowView {
            transition.updateFrame(view: view, frame: replyFrame(item))
        }
        if let node = replyNode, let host = replyHost, let scene = rowView as? ChatLayerRowView {
            #if DEBUG
            let replyShift = ChatRowView.parityReplyMutation
            #else
            let replyShift: CGFloat = 0
            #endif
            let frame = replyFrame(item).offsetBy(dx: replyShift, dy: 0)
            if host.frame.size != frame.size {
                let sizeDidChange = host.layerHostSizeDidChange
                host.layerHostSizeDidChange = nil
                host.setFrameSize(frame.size)
                host.layerHostSizeDidChange = sizeDidChange
                host.updateLayout(frame.size, transition: .immediate)
            }
            scene.layoutChromeNode(node, frame: frame, transition: transition)
        }
        if let view = statusControl {
            transition.updateFrame(view: view, frame: CGRect(origin: statusPoint(item), size: view.frame.size))
        }
        #if DEBUG
        (rowView as? ChatLayerRowView)?.layoutStatus(origin: statusPoint(item).offsetBy(dx: ChatRowView.parityStatusMutation, dy: 0), transition: transition)
        #else
        (rowView as? ChatLayerRowView)?.layoutStatus(origin: statusPoint(item), transition: transition)
        #endif
        if let view = forwardStatusControl {
            transition.updateFrame(view: view, frame: CGRect(origin: statusForwardPoint(item), size: view.frame.size))
        }
        
        if let view = psaButton {
            transition.updateFrame(view: view, frame: CGRect(origin: psaPoint(item), size: view.frame.size))
        }
        
        if let view = avatar {
            transition.updateFrame(view: view, frame: avatarFrame(item))
        }
        
        if !captionViews.isEmpty {
            var captionById: [UInt32: ChatRowItem.RowCaption] = [:]
            for caption in item.captionLayouts {
                captionById[caption.id] = caption
            }
            for captionView in captionViews {
                if let caption = captionById[captionView.id] {
                    transition.updateFrame(view: captionView.view, frame: captionFrame(item, caption: caption))
                }
            }
        }
        
        
        if let view = replyMarkupView {
            transition.updateFrame(view: view, frame: replyMarkupFrame(item))
            item.replyMarkupModel?.layout()
        }
        
        if let view = selectingView {
            transition.updateFrame(view: view, frame: CGRect(origin: selectingPoint(item), size: view.frame.size))
        }
        
        
        if let view = animatedView {
            transition.updateFrame(view: view, frame: size.bounds)
        }
        if let view = channelCommentsBubbleControl {
            transition.updateFrame(view: view, frame: channelCommentsBubbleFrame(item))
        }
        if let view = channelCommentsBubbleSmallControl {
            transition.updateFrame(view: view, frame: channelCommentsOverlayFrame(item))
        }

        updateSwipeLayout(transition)

        if let view = shareView {
            transition.updateFrame(view: view, frame: CGRect(origin: shareViewPoint(item), size: view.frame.size))
        }
        
        if let view = reactionsView {
            transition.updateFrame(view: view, frame: reactionsRect(item))
            view.updateLayout(size: view.frame.size, transition: transition)
        }
        
        if let view = factCheckView {
            transition.updateFrame(view: view, frame: factCheckFrame(item))
            view.updateLayout(size: view.frame.size, transition: transition)
        }

    }
    
    
    public func toggleSelected(_ select: Bool, in point: NSPoint) {
        guard let item = item as? ChatRowItem else { return }
        
        if item.isSelectable {
            item.chatInteraction.withToggledSelectedMessage({ current in
                if let message = item.message {
                    if (select && !current.isSelectedMessageId(message.id)) || (!select && current.isSelectedMessageId(message.id)) {
                        return current.withToggledSelectedMessage(message.id)
                    }
                }
                return current
            })
        }        
    }
    
    public override func forceClick(in location: NSPoint) {
            
       
        
        if let item = self.item as? ChatRowItem, item.chatInteraction.presentation.state != .editing {
            
//            let table = item.table!
//            let rect = item.context.window.contentView!.bounds
//            let metalLayer = DustLayer()
//            let view = View(frame: rect)
//            view.layer?.addSublayer(metalLayer)
//            item.context.window.contentView?.addSubview(view)
//            metalLayer.frame = rect
//            metalLayer.isInHierarchy = true
//
//            
//            metalLayer.addItem(frame: CGRect(origin: view.focus(rowView.frame.size).origin, size: rowView.frame.size), image: self.rowView.snapshot)
//            metalLayer.becameEmpty = { [weak view] in
//                view?.removeFromSuperview()
//            }
//            
//            return
            
            let result: Bool
            switch FastSettings.forceTouchAction {
            case .edit:
                result = item.editAction()
            case .reply:
                result = item.replyAction()
            case .forward:
                result = item.forwardAction()
            case .previewMedia:
                result = false
            case .react:
                let hitView = self.reactionsView?.hitTest(location)
                if hitView == self.reactionsView || hitView == nil {
                    result = item.reactAction()
                } else {
                    result = false
                }
            }
            if result {
                focusAnimation(nil, text: nil)
            } else {
             //   NSSound.beep()
            }
        }
        
    }
    
    public func previewMediaIfPossible() -> Bool {
        return false
    }
    
    deinit {
        contentView.removeAllSubviews()
        observedInteraction?.remove(observer: self)
    }

    private func updateInteractionObserver(_ interaction: ChatInteraction?) {
        if interaction != nil {
            isPreparingItem = false
        }
        guard observedInteraction !== interaction else { return }
        observedInteraction?.remove(observer: self)
        observedInteraction = interaction
        interaction?.add(observer: self)
    }
    
    public override func convertWindowPointToContent(_ point: NSPoint) -> NSPoint {
        return contentView.convert(point, from: nil)
    }
    
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateInteractionObserver(window == nil ? nil : (item as? ChatRowItem)?.chatInteraction)
        if window != nil {
            replyHost?.imageLayer?.hostDidMoveToWindow()
        }

    }
    
    
    // swiping methods
    
    private var swipingRightView: View?
    private var playedSwipeToReplyHaptic: Bool = false
    private var swipeDelta: CGFloat?

    public var additionalRevealDelta: CGFloat { 0 }
    public var containerX: CGFloat { rowView.frame.minX }
    public var width: CGFloat { rowView.frame.width }
    public static let revealActionInset: CGFloat = 4
    public static let replyRevealThreshold: CGFloat = 100
    public var rightRevealWidth: CGFloat { 40 }
    public var leftRevealWidth: CGFloat { 0 }
    public var endRevealState: SwipeDirection?

    private func updateSwipeLayout(_ transition: ContainedViewLayoutTransition) {
        guard let swipingRightView else { return }
        let delta = swipeDelta ?? 0
        transition.updateFrame(view: swipingRightView, frame: NSMakeRect(frame.width + delta, 0, max(rightRevealWidth, -delta), frame.height))
    }

    public func initRevealState() {
        let previous = swipingRightView
        swipingRightView = nil
        swipeDelta = nil
        playedSwipeToReplyHaptic = false
        rowView.layer?.removeAnimation(forKey: "position")
        rowView.setFrameOrigin(NSMakePoint(0, rowView.frame.minY))
        previous?.removeFromSuperview()
        previous?.removeAllSubviews()

        guard let item = item as? ChatRowItem else { return }
        let container = View(frame: NSMakeRect(frame.width, 0, rightRevealWidth, frame.height))
        container.layer?.masksToBounds = false
        swipingRightView = container
        swipeDelta = 0

        let control = ChatSwipeToReplyView(frame: CGRect(origin: .zero, size: ChatSwipeToReplyView.controlSize))
        control.update(item: item)
        control.updateProgress(0)
        container.addSubview(control)
        control.centerY(x: ChatRowView.revealActionInset)
        super.addSubview(container)
    }

    public var hasRevealState: Bool {
        return swipingRightView?.subviews.isEmpty == false
    }

    public func moveReveal(delta: CGFloat) {
        if swipeDelta == nil || !hasRevealState {
            initRevealState()
        }
        guard let swipingRightView, let control = swipingRightView.subviews.first as? ChatSwipeToReplyView else { return }

        let delta = delta - additionalRevealDelta
        self.swipeDelta = delta
        rowView.setFrameOrigin(NSMakePoint(delta, rowView.frame.minY))
        swipingRightView.change(pos: NSMakePoint(frame.width + delta, swipingRightView.frame.minY), animated: false)
        swipingRightView.change(size: NSMakeSize(max(rightRevealWidth, -delta), swipingRightView.frame.height), animated: false)
        control.centerY(x: ChatRowView.revealActionInset)

        let progress = min(1, max(0, -delta / ChatRowView.replyRevealThreshold))
        control.updateProgress(progress)
        if progress == 1 {
            if !playedSwipeToReplyHaptic {
                playedSwipeToReplyHaptic = true
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted)
            }
        } else {
            playedSwipeToReplyHaptic = false
        }
    }

    public func completeReveal(direction: SwipeDirection) {
        guard let delta = swipeDelta, let container = swipingRightView,
              let control = container.subviews.first as? ChatSwipeToReplyView else { return }
        swipeDelta = nil
        playedSwipeToReplyHaptic = false
        endRevealState = nil

        if case .right = direction, -delta >= ChatRowView.replyRevealThreshold {
            _ = (item as? ChatRowItem)?.replyAction()
        }
        guard swipingRightView === container, container.subviews.first === control, swipeDelta == nil else { return }

        rowView.change(pos: NSMakePoint(0, rowView.frame.minY), animated: true)
        container.change(pos: NSMakePoint(frame.width, container.frame.minY), animated: true)
        control.animateOut(completion: { [weak self, weak container, weak control] in
            guard let self, let container, let control, self.swipingRightView === container,
                  container.subviews.first === control else { return }
            self.swipingRightView = nil
            container.removeFromSuperview()
            container.removeAllSubviews()
        })
    }

    public override var interactableView: NSView {
        return self
    }
    
    public override func removeFromSuperview() {
        super.removeFromSuperview()
    }
    
    public override func onInsert(_ animation: NSTableView.AnimationOptions, appearAnimated: Bool) {
        if let item = item as? ChatRowItem, visibleRect != .zero, !TelegramUtilsHooks.shared.isLite(.animations) {
            if item.isBubbled, appearAnimated {
                if item.isIncoming {
                    self.rowView.layer?.animateScaleSpringFrom(anchor: NSMakePoint(bubbleView.frame.minX, rowView.frame.height / 2), from: 0.1, to: 1, duration: 0.35, bounce: false)
                } else {
                    self.rowView.layer?.animateScaleSpringFrom(anchor: NSMakePoint(rowView.frame.width - 20, rowView.frame.height / 2), from: 0.1, to: 1, duration: 0.35, bounce: false)
                }
                self.rowView.layer?.animateAlpha(from: 0, to: 1, duration: 0.35)
            }
        }
    }
    
    public var storyAvatarControl: NSView? {
        return self.avatar
    }
    
    public func storyControl(_ storyId: StoryId) -> NSView? {
        return replyView?.imageView
    }
    
    public var storyMediaControl: NSView? {
        return nil
    }
}

extension PremiumStatusLayer: ChatLayerHostedVisibility {}
