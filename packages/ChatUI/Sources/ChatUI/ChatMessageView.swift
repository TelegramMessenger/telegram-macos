import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import InputTextView
import MessageUtils
import TelegramMediaUtils
import TelegramTheme
import Localization


public class ChatMessageView: ChatRowView, ModalPreviewRowViewProtocol {
    
    public class ActionButton: TextButton {
        
        public var urlView: ImageView?
        
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public func set(isExternalUrl: Bool, color: NSColor) {
            if isExternalUrl {
                let current: ImageView
                if let view = self.urlView {
                    current = view
                } else {
                    current = ImageView()
                    current.isAccessibilityDecorative = true
                    addSubview(current)
                    self.urlView = current
                }
                current.image = NSImage.init(named: "Icon_InlineBotUrl")?.precomposed(color)
                current.sizeToFit()
            } else if let view = self.urlView {
                view.removeFromSuperview()
                self.urlView = nil
            }
            needsLayout = true
        }
        
        public override func layout() {
            super.layout()
            if let view = urlView {
                view.setFrameOrigin(NSMakePoint(frame.width - view.frame.width - 5, 5))
            }
        }
    }
    
    public class AdSettingsView : View {
        private let close: ImageButton = ImageButton()
        private var more: ImageButton?
        private let separator = View()
        
        private weak var item: ChatMessageItem?
        
        public required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            
            addSubview(close)
            addSubview(separator)
            
            close.scaleOnClick = true
            close.setAccessibilityLabel(strings().voiceOverCommonClose)
            close.autohighlight = false
            
            close.set(handler: { [weak self] _ in
                if let item = self?.item {
                    item.webpageLayout?.premiumBoarding()
                }
            }, for: .Click)

        }
        
        public required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public override func layout() {
            super.layout()
            close.setFrameOrigin(.zero)
            separator.frame = NSMakeRect(6, close.frame.maxY + 3, frame.width - 12, .borderSize)
            more?.setFrameOrigin(NSMakePoint(0, close.frame.maxY + 6))

        }
        
        public func update(_ item: ChatMessageItem, animated: Bool) {
            self.item = item
            backgroundColor = theme.colors.background
            
            separator.backgroundColor = theme.colors.grayIcon.withAlphaComponent(0.4)

            close.set(image: TelegramThemeHooks.shared.image(.iconAdHide).precomposed(theme.colors.grayIcon), for: .Normal)
            close.sizeToFit(.zero, NSMakeSize(30, 30), thatFit: true)
            separator.isHidden = !item.isFragmentAd
            
            
            if item.isFragmentAd {
                let current: ImageButton
                if let view = self.more {
                    current = view
                } else {
                    current = ImageButton(frame: NSMakeRect(0, 30, 30, 30))
                    current.scaleOnClick = true
                    current.autohighlight = false
                    current.setAccessibilityLabel(strings().voiceOverCommonMore)

                    self.more = current
                    addSubview(current)
                    
                   
                    
                }
                current.removeAllHandlers()
                current.set(handler: { [weak item] control in
                    if let item = item, let event = NSApp.currentEvent {
                        _ = item.menuItems(in: .zero).startStandalone(next: { [weak control] items in
                            if let control = control {
                                let menu = ContextMenu()
                                menu.items = items
                                AppMenu.show(menu: menu, event: event, for: control)
                            }
                        })
                    }
                }, for: .Down)
                current.set(image: TelegramThemeHooks.shared.image(.iconAdMore).precomposed(theme.colors.grayIcon), for: .Normal)
                current.sizeToFit(.zero, NSMakeSize(30, 30), thatFit: true)
            } else if let view = self.more {
                performSubviewRemoval(view, animated: animated)
                self.more = nil
            }
        }
    }
    
    
    public func fileAtPoint(_ point: NSPoint) -> (QuickPreviewMedia, NSView?)? {
        if let webpageContent = webpageContent {
            return webpageContent.fileAtPoint(convert(point, from: self))
        }
        
        return nil
    }
    
    public override func forceClick(in location: NSPoint) {
        if previewMediaIfPossible() {
            
        } else {
            super.forceClick(in: location)
        }
    }
    
    public override func previewMediaIfPossible() -> Bool {
        return webpageContent?.previewMediaIfPossible() ?? false
    }
    
    private(set) var text:FoldingTextView?
    private var layerText: ChatLayerMessageTextView?
    private var textBindingVersion: UInt64 = 0

    var textContentView: NSView? { layerText ?? text }

    func firstTextBaseline(in view: NSView) -> NSPoint? {
        if let layerText { return layerText.firstTextBaseline(in: view) }
        guard let textView = text?.textViews.first, let line = textView.textLayout?.lines.first else { return nil }
        return textView.convert(NSPoint(x: line.frame.minX, y: line.frame.minY), to: view)
    }

    public private(set) var webpageContent:WPContentView?
    private var actionButton: ActionButton?
    private var papercutView: ChatUnsupportedPapercutView?
    
    
    private var adSettingView: AdSettingsView?
    

    public required init(frame frameRect: NSRect) {
        
        super.init(frame: frameRect)
       // self.layerContentsRedrawPolicy = .never
    }
    
    
    public override func layout() {
        super.layout()
       
    }
    
    public func webpageFrame(_ item: ChatMessageItem) -> NSRect {
        guard let item = self.item as? ChatMessageItem else {
            return .zero
        }
        let maxY: CGFloat

        if item.webpageAboveContent {
            maxY = 1
        } else {
            maxY = textFrame(item).maxY + item.defaultContentInnerInset
        }
        if let webpageLayout = item.webpageLayout {
            let size = webpageLayout.size
            return CGRect(origin: NSMakePoint(0, maxY), size: size)
        }
        return .zero
    }
    
    public func textFrame(_ item: ChatMessageItem) -> NSRect {
        guard let item = self.item as? ChatMessageItem else {
            return .zero
        }
        let maxY: CGFloat

        if item.webpageAboveContent, item.webpageLayout != nil {
            maxY = webpageFrame(item).maxY + item.defaultContentInnerInset - 2
        } else {
            maxY = 0
        }
        return CGRect(origin: NSMakePoint(0, maxY), size: item.textLayout.size)

    }
    
    /// The card *is* the frosted panel — the message carries no bubble — so it is exactly the content
    /// rect, and `frostedPanels` derives the blurred surfaces from this same rect.
    public func papercutFrame(_ item: ChatMessageItem) -> NSRect {
        guard let papercutLayout = item.papercutLayout else {
            return .zero
        }
        var rect = self.contentFrame(item)
        rect.size.height = papercutLayout.size.height
        return rect
    }

    public override func frostedPanels(_ item: ChatRowItem) -> [ChatRowView.FrostedPanel] {
        guard let item = item as? ChatMessageItem, item.isBubbled, let layout = item.papercutLayout else {
            return []
        }
        let origin = self.bubbleFrame(item).origin
        return layout.frostedPanels(in: self.papercutFrame(item), offsetBy: CGPoint(x: -origin.x, y: -origin.y))
    }

    public func adSettingFrame(_ item: ChatMessageItem) -> NSRect {
        let webpage = webpageFrame(item)
        var rect = NSMakeRect(webpage.maxX + contentFrame(item).minX + 10, contentFrame(item).minY + webpage.minY, 30, item.isFragmentAd ? 69 : 30)
        if item.isBubbled {
            rect.origin.x += 10
            rect.origin.y = bubbleFrame(item).minY
        }
        return rect
    }
    
    public override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        guard let item = self.item as? ChatMessageItem else {
            return
        }
        if let webpageContent = webpageContent {
            transition.updateFrame(view: webpageContent, frame: webpageFrame(item))
        }
        
        if let text = textContentView {
            transition.updateFrame(view: text, frame: textFrame(item))
        }
        
        if let actionButton = actionButton {
            var add = item.additionalLineForDateInBubbleState ?? 0
            if !item.isBubbled {
                add = 0
            }
            let contentRect = self.contentFrame(item)
            transition.updateFrame(view: actionButton, frame: CGRect(origin: NSMakePoint(contentRect.minX, contentRect.maxY - actionButton.frame.height + add), size: actionButton.frame.size))
        }
        
        if let papercutView = self.papercutView {
            transition.updateFrame(view: papercutView, frame: papercutFrame(item))
            papercutView.needsDisplay = true
        }

        if let adSettingView {
            transition.updateFrame(view: adSettingView, frame: adSettingFrame(item))
        }
    }

    public override func canStartTextSelecting(_ event: NSEvent) -> Bool {
        if let superTextView = textContentView?.superview {
            if let webpageContent = webpageContent {
                return !NSPointInRect(superTextView.convert(event.locationInWindow, from: nil), webpageContent.frame)
            }
            return true
        }
        return false
    }
    
    override var textSelectionSources: ChatTextSelectionSources {
        let hasLayerCaptions = captionViews.contains(where: { $0.layerView != nil })
        guard layerText != nil || hasLayerCaptions else { return .views(selectableTextViews) }
        var sources: [ChatTextSelectionSource]
        if hasLayerCaptions, case let .mixed(values) = super.textSelectionSources {
            sources = values
        } else {
            sources = super.selectableTextViews.map(ChatTextSelectionSource.view)
        }
        if let layerText {
            sources.append(contentsOf: layerText.body.textNodes.map { .layer($0, layerText) })
        } else if let text {
            sources.append(contentsOf: text.textViews.map(ChatTextSelectionSource.view))
        }
        if let webpageContent { sources.append(contentsOf: webpageContent.selectableTextViews.map(ChatTextSelectionSource.view)) }
        return .mixed(sources)
    }

    public override var selectableTextViews: [TextView] {
        var views:[TextView] = super.selectableTextViews + (text?.textViews ?? [])
        if let webpage = webpageContent {
            views += webpage.selectableTextViews
        }
        return views
    }
    
    public override func updateMouse(animated: Bool) {
        super.updateMouse(animated: animated)
        webpageContent?.updateMouse()
    }
    
    public override func canMultiselectTextIn(_ location: NSPoint) -> Bool {
        _ = self.contentView.convert(location, from: nil)
        return true
    }
    
    public override func focusAnimation(_ innerId: AnyHashable?, text: String?) {
        focusAnimation(innerId, text: text, range: nil)
    }

    public override func focusAnimation(_ innerId: AnyHashable?, text: String?, range: NSRange?) {
        super.focusAnimation(innerId, text: text)
        
        guard let item = item as? ChatMessageItem else {
            return
        }
        if let text = text, !text.isEmpty {
            let layoutString = item.textLayout.attributedString
            let layoutRange = chatQuoteTextRange(in: layoutString, text: text, offset: range?.location)
            let layoutText = layoutRange.map { (layoutString.string as NSString).substring(with: $0) } ?? text
            if let layerText {
                layerText.body.highlight(text: layoutText, color: item.presentation.colors.focusAnimationColor, range: layoutRange, in: item.textLayout)
            } else {
                self.text?.highlight(text: layoutText, color: item.presentation.colors.focusAnimationColor, range: layoutRange)
            }
        }
    }


    private func updateText(for item: ChatMessageItem, previous: ChatMessageItem?, animated: Bool) {
        let version = textBindingVersion
        let presentation = item.papercutLayout == nil ? ChatLayerMessageTextPresentation.simpleText(item.textLayout) : nil
        var useLayers = presentation != nil
        if useLayers, let text {
            if animated || text.hasSelectedText {
                useLayers = false
            } else {
                useLayers = text.updateForReusedContent(layout: item.textLayout)
                guard textBindingVersion == version else { return }
            }
        }
        if useLayers, let presentation {
            let current = layerText ?? ChatLayerMessageTextView(frame: textFrame(item))
            if presentation.requiresRevealAction, current.body.revealBlockAtIndex == nil {
                current.body.revealBlockAtIndex = { [weak self] index in
                    (self?.item as? ChatMessageItem)?.revealBlockAtIndex(index)
                }
            }
            let identity = ChatLayerMessageTextView.Identity(messageId: item.stableId, accountId: ObjectIdentifier(item.textLayout.context))
            guard current.update(presentation, identity: identity, context: item.textLayout.context, animated: animated), textBindingVersion == version else {
                if layerText !== current { _ = current.prepareForRemoval() }
                return
            }
            let isNew = layerText !== current
            if let text {
                self.text = nil
                text.removeFromSuperview()
                guard textBindingVersion == version else { return }
            }
            layerText = current
            if isNew || !animated {
                let frame = textFrame(item)
                if current.frame != frame { current.frame = frame }
            }
            if isNew {
                addSubview(current)
                if animated { current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2) }
            }
        } else {
            if let layerText {
                let sameMessage = previous?.stableId == item.stableId && previous?.textLayout.context === item.textLayout.context
                let selections = sameMessage ? layerText.body.textNodes.compactMap { node in
                    node.textLayout.map { ($0.attributedString.string, $0.selectedRange) }
                } : []
                guard layerText.prepareForRemoval(), textBindingVersion == version else { return }
                for (old, block) in zip(selections, item.textLayout.blocks)
                where old.0 == block.text.attributedString.string && block.text.mayItems && block.text.selectedRange.range.location == NSNotFound {
                    block.text.selectedRange = old.1
                }
                self.layerText = nil
                performSubviewRemoval(layerText, animated: animated)
                guard textBindingVersion == version else { return }
            }
            updateNativeText(for: item, previous: previous, animated: animated)
        }
    }

    private func updateNativeText(for item: ChatMessageItem, previous: ChatMessageItem?, animated: Bool) {
        let isEqual = previous?.stableId == item.stableId
            && previous?.textLayout.context === item.textLayout.context
            && previous?.textLayout.string == item.textLayout.string
        if item.papercutLayout != nil {
            if let view = self.text {
                performSubviewRemoval(view, animated: animated)
                self.text = nil
            }
        } else if isEqual, let view = self.text {
            view.update(layout: item.textLayout, animated: animated)
        } else if !animated, let view = self.text, view.updateForReusedContent(layout: item.textLayout) {
            let frame = textFrame(item)
            if view.frame != frame { view.frame = frame }
        } else {

            let appendingAnimationView = self.text?.appendingAnimationView

            if let view = self.text {
                performSubviewRemoval(view, animated: animated)
            }
            let current: FoldingTextView = FoldingTextView(frame: textFrame(item))
            current.update(layout: item.textLayout, animated: false, appendingAnimationView: appendingAnimationView)

            current.revealBlockAtIndex = { [weak self] index in
                if let item = self?.item as? ChatMessageItem {
                    item.revealBlockAtIndex(index)
                }
            }
            current.streamingVisibleHeightChanged = { [weak self] in
                guard let self, let item = self.item as? ChatMessageItem, let table = item.table else {
                    return
                }
                let oldHeight = item.height
                item.previousBlockWidth = 0
                _ = item.makeSize(item.width, oldWidth: 0)
                let newHeight = item.height
                if oldHeight != newHeight {
                    table.noteHeightOfRow(item.index, true)
                }
            }

            self.text = current
            addSubview(current)

            if animated, !item.textLayout.appendingAnimation {
                current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
            }
        }
    }


    public override func set(item:TableRowItem, animated:Bool = false) {
        textBindingVersion &+= 1
        let version = textBindingVersion
        let previous = self.item as? ChatMessageItem
        super.set(item: item, animated: animated)
        guard textBindingVersion == version else { return }

        if let item = item as? ChatMessageItem {

            bindStep("messageText") { updateText(for: item, previous: previous, animated: animated) }
            guard textBindingVersion == version else { return }

            if let webpageLayout = item.webpageLayout {
                let updated = webpageContent == nil || !webpageContent!.isKind(of: webpageLayout.viewClass())
                let current: WPContentView
                if !updated, let view = self.webpageContent {
                    current = view
                } else {
                    if let view = self.webpageContent {
                        performSubviewRemoval(view, animated: animated)
                    }
                    let vz = webpageLayout.viewClass() as! WPContentView.Type
                    current = vz.init()
                    current.frame = webpageFrame(item)
                    self.webpageContent = current
                    addSubview(current)
                    if animated {
                        current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    }
                }
                
                bindStep("webpage") { current.update(with: webpageLayout, animated: animated) }
            } else if let view = webpageContent {
                performSubviewRemoval(view, animated: animated)
                webpageContent = nil
            }
            if let text = item.actionButtonText {
                var isNew = false
                if actionButton == nil {
                    actionButton = ActionButton(frame: .zero)
                    actionButton?.layer?.cornerRadius = .cornerRadius
                    actionButton?.disableActions()
                    actionButton?.set(font: .normal(.text), for: .Normal)
                    self.rowView.addSubview(actionButton!)
                    isNew = true
                }
                actionButton?.set(isExternalUrl: item.hasExternalLink, color: item.wpPresentation.activity.main)
                actionButton?.scaleOnClick = true
                actionButton?.removeAllHandlers()
                actionButton?.set(handler: { [weak item, weak self] _ in
                    item?.invokeAction(morphSource: { [weak self] in self?.actionButton })
                }, for: .Click)
                actionButton?.set(text: text, for: .Normal)
                actionButton?.set(color: item.wpPresentation.activity.main, for: .Normal)
                actionButton?.set(background: item.wpPresentation.activity.main.withAlphaComponent(0.1), for: .Normal)
                _ = actionButton?.sizeToFit(NSZeroSize, NSMakeSize(item.actionButtonWidth, 36), thatFit: true)
                if animated, isNew {
                    actionButton?.layer?.animateScaleCenter(from: 0.1, to: 1, duration: 0.2, timingFunction: .easeOut)
                    actionButton?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                }
            } else {
                if let view = actionButton {
                    performSubviewRemoval(view, animated: animated)
                    actionButton = nil
                }
            }

            if let papercutLayout = item.papercutLayout {
                let current: ChatUnsupportedPapercutView
                if let view = self.papercutView {
                    current = view
                } else {
                    // Added to `rowView`, not `contentView`: the card can be wider than `contentSize`,
                    // and AppKit clips hit-testing to the superview's frame. Same reason `actionButton`
                    // and `adSettingView` do it.
                    current = ChatUnsupportedPapercutView(frame: papercutFrame(item))
                    self.papercutView = current
                    self.rowView.addSubview(current)
                    if animated {
                        current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    }
                }
                current.update(layout: papercutLayout)
                current.removeAllHandlers()
                current.set(handler: { [weak item] _ in
                    item?.invokeAction()
                }, for: .Click)
            } else if let view = self.papercutView {
                performSubviewRemoval(view, animated: animated)
                self.papercutView = nil
            }


            if item.message?.adAttribute != nil {
                let current: AdSettingsView
                if let view = self.adSettingView {
                    current = view
                } else {
                    current = AdSettingsView(frame: adSettingFrame(item))
                    self.adSettingView = current
                    self.rowView.addSubview(current)
                }
                current.update(item, animated: animated)
                current.layer?.cornerRadius = current.frame.width / 2
            } else if let view = self.adSettingView {
                performSubviewRemoval(view, animated: animated)
                self.adSettingView = nil
            }

        }

    }
    
    public override func updateAnimatableContent() {
        super.updateAnimatableContent()
        layerText?.updateInlineEmojiVisibility()
    }
    
    public override func clickInContent(point: NSPoint) -> Bool {
        guard let item = item as? ChatMessageItem else {return true}
        let _ = item
        // `point` is in this row view's coordinates (see TableRowView.doubleClick); the text view tests
        // against its own local geometry, so convert — otherwise clicks left of the bubble land "inside".
        if let layerText {
            return layerText.clickInContent(point: layerText.convert(point, from: self))
        } else if let text = self.text {
            return text.clickInContent(point: text.convert(point, from: self))
        } else {
            return false
        }
    }
    
    public override func interactionContentView(for innerId: AnyHashable, animateIn: Bool ) -> NSView {
        if let webpageContent = webpageContent {
            return webpageContent.interactionContentView(for: innerId, animateIn: animateIn)
        }
        return self
    }
    

    public override func convertWindowPointToContent(_ point: NSPoint) -> NSPoint {
        let main = super.convertWindowPointToContent(point)
        
        if let webpageContent = webpageContent, NSPointInRect(main, webpageContent.frame) {
            return webpageContent.convertWindowPointToContent(point)
        } else {
            return main
        }
    }
    
    public override func storyControl(_ storyId: StoryId) -> NSView? {
        if let item = item as? ChatRowItem {
            if item.message?.storyAttribute?.storyId == storyId {
                return super.storyControl(storyId)
            } else {
                return self.webpageContent?.mediaContentView ?? super.storyControl(storyId)
            }
        }
        return nil
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
