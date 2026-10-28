import Cocoa
import TGUIKit
#if SHARE
import TelegramThemeShare
import TelegramContextShare
#else
import TelegramTheme
import TelegramContext
#endif


open class GeneralInteractedRowView: GeneralContainableRowView, ViewDisplayDelegate {

    public private(set) var switchView:SwitchView?
    public private(set) var selectLeftControl: SelectingControl?
    public private(set) var progressView: ProgressIndicator?
    public private(set) var textView:TextView?
    public private(set) var secondaryTextView:TextView?
    public private(set) var descriptionView: TextView?
    let nextView = SimpleLayer()
    private var nextImage: CGImage? {
        didSet {
            nextView.contents = nextImage
        }
    }
    private var imageContext:ImageView?

    let nameView = InlineTextView()

    private var badgeView: View?

    private var rightIconView: ImageView?
    
    open override func set(item:TableRowItem, animated:Bool = false) {
        
        
        
        if let item = item as? GeneralInteractedRowItem {
            
            
            nameView.set(text: item.isSelected ? item.nameLayoutSelected : item.nameLayout, context: item.context)
                        
            if let descLayout = item.descLayout {
                if descriptionView == nil {
                    descriptionView = TextView()
                    descriptionView?.userInteractionEnabled = false
                    descriptionView?.isSelectable = false
                    descriptionView?.isEventLess = true
                    containerView.addSubview(descriptionView!)
                }
                descriptionView?.update(descLayout)
            } else {
                descriptionView?.removeFromSuperview()
                descriptionView = nil
            }
            
            nextView.isHidden = true
            if case let .switchable(stateback) = item.type {
                if switchView == nil {
                    switchView = SwitchView()
                    containerView.addSubview(switchView!)
                }
                switchView?.autoswitch = item.autoswitch
                switchView?.presentation = item.switchAppearance
                switchView?.setIsOn(stateback,animated:animated)
                
                switchView?.stateChanged = { [weak self, weak item] in
                    guard let self, let item, self.item === item else { return }
                    if item.autoswitch, item.switchAction == nil, let switchView = self.switchView {
                        item.type = .switchable(switchView.isOn)
                    }
                    (item.switchAction ?? item.action)()
                }
                switchView?.userInteractionEnabled = item.enabled
                switchView?.isEnabled = item.enabled
            } else {
                switchView?.removeFromSuperview()
                switchView = nil
            }
            if case let .selectableLeft(value) = item.type {
                
                let unselected: CGImage = item.customTheme?.unselectedImage ?? theme.icons.chatToggleUnselected
                let selected: CGImage = item.customTheme?.selectedImage ?? theme.icons.chatToggleSelected

                let current: SelectingControl
                if let view = self.selectLeftControl {
                    current = view
                } else {
                    
                    current = SelectingControl(unselectedImage: unselected, selectedImage: selected)
                    current.scaleOnClick = true
                    containerView.addSubview(current)
                    self.selectLeftControl = current
                    
                    current.set(handler: { [weak self] _ in
                        if let item = self?.item as? GeneralInteractedRowItem {
                            item.switchAction?()
                        }
                    }, for: .Click)
                }
                current.update(unselectedImage: unselected, selectedImage: selected, selected: value, animated: animated)
                
                current.userInteractionEnabled = item.switchAction != nil
                
                
                current.layer?.opacity = item.enabled ? 1 : 0.7
            } else if let view = self.selectLeftControl {
                performSubviewRemoval(view, animated: animated)
                self.selectLeftControl = nil
            }
                        
            if let badgeNode = item.badgeNode {
                if badgeView == nil {
                    badgeView = View()
                    containerView.addSubview(badgeView!)
                }
                badgeView?.setFrameSize(badgeNode.size)
                badgeNode.view = badgeView
                badgeNode.setNeedDisplay()
            } else {
                self.badgeView?.removeFromSuperview()
                self.badgeView = nil
            }
            
            if case let .image(stateback) = item.type {
                nextImage = stateback
                nextView.frame.size = nextImage?.backingSize ?? nextView.frame.size
                nextView.isHidden = item.isSelected
            }
            
            switch item.type {
            case let .context(value), let .contextColored(value, _), let .nextContext(value), let .contextSelector(value, _), let .imageContext(_, value):
                if textView == nil {
                    textView = TextView()
                    textView?.animates = false
                    textView?.userInteractionEnabled = false
                    textView?.isEventLess = true
                    containerView.addSubview(textView!)
                }
                let textColor: NSColor
                if case let .contextColored(_, color) = item.type {
                    textColor = color
                } else {
                    textColor = item.customTheme?.grayTextColor ?? theme.colors.grayText
                }
                let underselect = item.customTheme?.underSelectedColor ?? theme.colors.underSelectedColor

                let layout = item.isSelected ? nil : TextViewLayout(.initialize(string: value, color: isSelect ? underselect : textColor, font: .normal(.title)), maximumNumberOfLines: 1)

                textView?.set(layout: layout)
                secondaryTextView?.removeFromSuperview()
                secondaryTextView = nil
                var nextVisible: Bool = true
                if case let .contextSelector(value, items) = item.type {
                    nextVisible = !items.isEmpty && !value.isEmpty
                } else if case .imageContext = item.type {
                    nextVisible = true
                } else if case .context = item.type {
                    nextVisible = false
                } else if case .contextColored = item.type {
                    nextVisible = false
                }
                nextView.isHidden = !nextVisible
            case let .twoLinesContext(primary, secondary):
                if textView == nil {
                    textView = TextView()
                    textView?.animates = false
                    textView?.userInteractionEnabled = false
                    textView?.isEventLess = true
                    containerView.addSubview(textView!)
                }
                if secondaryTextView == nil {
                    secondaryTextView = TextView()
                    secondaryTextView?.animates = false
                    secondaryTextView?.userInteractionEnabled = false
                    secondaryTextView?.isEventLess = true
                    containerView.addSubview(secondaryTextView!)
                }
                let textColor = item.customTheme?.textColor ?? theme.colors.text
                let grayText = item.customTheme?.grayTextColor ?? theme.colors.grayText
                let underselect = item.customTheme?.underSelectedColor ?? theme.colors.underSelectedColor

                let primaryLayout = item.isSelected ? nil : TextViewLayout(.initialize(string: primary, color: isSelect ? underselect : textColor, font: .normal(.title)), maximumNumberOfLines: 1, alignment: .right)
                let secondaryLayout = item.isSelected ? nil : TextViewLayout(.initialize(string: secondary, color: isSelect ? underselect : grayText, font: .normal(.text)), maximumNumberOfLines: 1, alignment: .right)

                textView?.set(layout: primaryLayout)
                secondaryTextView?.set(layout: secondaryLayout)
                nextView.isHidden = true
            default:
                textView?.removeFromSuperview()
                textView = nil
                secondaryTextView?.removeFromSuperview()
                secondaryTextView = nil
            }
            if case let .nextImage(image) = item.type {
                let current:ImageView
                if let view = self.imageContext {
                    current = view
                } else {
                    current = ImageView()
                    current.isAccessibilityDecorative = true
                    containerView.addSubview(current)
                    self.imageContext = current
                }
                current.image = image 
                current.sizeToFit()
            } else if let view = self.imageContext {
                performSubviewRemoval(view, animated: animated)
                self.imageContext = nil
            }
            textView?.backgroundColor = backdorColor
            
            if case let .selectable(value) = item.type {
                nextView.isHidden = !value
                
                nextImage = GeneralRowsHooks.shared.checkSelectedImage(item.customTheme?.accentColor ?? theme.colors.accent, item.customTheme?.underSelectedColor ?? theme.colors.underSelectedColor)
                
                nextView.frame.size = nextImage?.backingSize ?? nextView.frame.size
                
            }
            if case let .imageContext(image, _) = item.type {
                nextView.isHidden = false
                nextImage = image
                nextView.frame.size = nextImage?.backingSize ?? nextView.frame.size
            }
            
            var needNextImage: Bool = false
            if case .colorSelector = item.type {
                needNextImage = true
            }
            if case .next = item.type {
                needNextImage = true
            }
            if case .nextContext = item.type {
                needNextImage = true
            }
            if case .nextImage = item.type {
                needNextImage = true
            }
            if case let .contextSelector(value, items) = item.type {
                needNextImage = !items.isEmpty && !value.isEmpty
            }
            if needNextImage {
                nextView.isHidden = false
                                
                let color = (item.customTheme?.grayTextColor ?? theme.colors.grayText).withAlphaComponent(0.5)
                nextImage = item.isSelected ? nil : TelegramThemeHooks.shared.image(.iconGeneralNext).precomposed(color)
                nextView.frame.size = nextImage?.backingSize ?? nextView.frame.size
            }
            
            nextView.opacity = item.enabled ? 1.0 : 0.7
            
            switch item.viewType {
            case .legacy:
                containerView.setCorners([], animated: false)
            case .modern:
                containerView.setCorners(self.isResorting ? GeneralViewItemCorners.all : item.viewType.corners, animated: animated)
            }
            
            switch item.type {
            case .loading:
                if progressView == nil {
                    self.progressView = ProgressIndicator(frame: NSMakeRect(0, 0, 20, 20))
                    containerView.addSubview(self.progressView!)
                }
            default:
                self.progressView?.removeFromSuperview()
                self.progressView = nil
            }

            if let rightIcon = item.rightIcon {
                let current: ImageView
                if let view = rightIconView {
                    current = view
                } else {
                    current = ImageView()
                    current.isAccessibilityDecorative = true
                    self.rightIconView = current
                    containerView.addSubview(current)
                }
                current.image = rightIcon
                current.sizeToFit()
            } else if let view = rightIconView {
                performSubviewRemoval(view, animated: animated)
                self.rightIconView = nil
            }
        }
        super.set(item: item, animated: animated)
        
        needsLayout = true
        containerView.needsDisplay = true
        
    }
    
    open override func updateIsResorting() {
        if let item = self.item {
            self.set(item: item, animated: true)
        }
    }
    
    open override var backdorColor: NSColor {
        guard let item = item as? GeneralInteractedRowItem else {
            return super.backdorColor
        }
        if let theme = item.customTheme {
            return isSelect ? theme.accentColor : theme.backgroundColor
        }
        return isSelect ? theme.colors.accentSelect : theme.colors.background
    }
    
    open var highlightColor: NSColor {
        guard let item = item as? GeneralInteractedRowItem else {
            return super.backdorColor
        }
        if let theme = item.customTheme {
            return theme.highlightColor
        }
        return theme.colors.grayHighlight
    }
    
    open override var borderColor: NSColor {
        guard let item = item as? GeneralInteractedRowItem else {
            return theme.colors.border
        }
        if item.disableBorder {
            return .clear
        }
        if let theme = item.customTheme {
            return theme.borderColor
        }
        return theme.colors.border
    }
    
    open override func updateColors() {
        if let item = item as? GeneralInteractedRowItem {
            self.background = item.viewType.rowBackground
            if item.viewType == .legacy, item.customTheme != nil {
                self.background = .clear
            }
            let highlighted = isSelect ? self.backdorColor : highlightColor
            descriptionView?.backgroundColor = containerView.controlState == .Highlight && !isSelect ? .clear : self.backdorColor
            textView?.backgroundColor = containerView.controlState == .Highlight && !isSelect ? .clear : self.backdorColor
            containerView.set(background: self.backdorColor, for: .Normal)
            containerView.set(background: highlighted, for: .Highlight)
            progressView?.progressColor = item.customTheme?.secondaryColor ?? theme.colors.grayIcon
        }
        containerView.needsDisplay = true
    }
    
    open override func shakeView() {
        self.shake()
    }
    
    private var textXAdditional: CGFloat {
        var textXAdditional:CGFloat = 0
        guard let item = item as? GeneralInteractedRowItem else {return 0}
        let t = item.isSelected ? item.activeThumb : item.thumb
        if let thumb = t {
            if let textInset = thumb.textInset {
                textXAdditional = textInset
            } else {
                textXAdditional = thumb.thumb.systemSize.width + 10
            }
        }
        if let _ = self.selectLeftControl {
            textXAdditional += 24 + 14
        }
        return textXAdditional
    }
    
    open override func draw(_ layer: CALayer, in ctx: CGContext) {
                
        if let item = item as? GeneralInteractedRowItem, layer == containerView.layer {
            
            switch item.viewType {
            case .legacy:
                super.draw(layer, in: ctx)
                let t = item.isSelected ? item.activeThumb : item.thumb
                if let thumb = t {
                    var f = focus(thumb.thumb.systemSize)
                    if item.descLayout != nil {
                        f.origin.y = 11
                    }
                    let x: CGFloat = item.inset.left + (thumb.thumbInset ?? 0)
                    let icon = thumb.thumb
                    ctx.draw(icon, in: NSMakeRect(x, f.minY, f.width, f.height))
                }
                
                if item.drawCustomSeparator, !isSelect && !self.isResorting && containerView.controlState != .Highlight {
                    ctx.setFillColor(borderColor.cgColor)
                    ctx.fill(NSMakeRect(textXAdditional + item.inset.left, frame.height - .borderSize, containerView.frame.width - (item.inset.left + item.inset.right), .borderSize))
                }
                
                
                if case let .colorSelector(stateback) = item.type {
                    ctx.setFillColor(stateback.cgColor)
                    ctx.fillEllipse(in: NSMakeRect(containerView.frame.width - 14 - item.inset.right - 16, floorToScreenPixels(backingScaleFactor, (frame.height - 14) / 2), 14, 14))
                }
            case let .modern(position, insets):
                let t = item.isSelected ? item.activeThumb : item.thumb
                if let thumb = t {
                    let f = focus(thumb.thumb.systemSize)
                    
                    let icon = thumb.thumb
                    var x: CGFloat = insets.left + (thumb.thumbInset ?? 0)
                    if case .selectableLeft = item.type {
                        x += 35
                    } else {
                        if item.descLayout != nil {
                        }
                    }
                    ctx.draw(icon, in: NSMakeRect(x, f.minY, f.width, f.height))
                }
                
                if position.border, !isSelect && !self.isResorting  {
                    ctx.setFillColor(borderColor.cgColor)
                    ctx.fill(NSMakeRect(textXAdditional + insets.left, containerView.frame.height - .borderSize, containerView.frame.width - (insets.left + insets.right + textXAdditional), .borderSize))
                }
                
                let nameLayout = (item.isSelected ? item.nameLayoutSelected : item.nameLayout)
                
                var textRect = focus(NSMakeSize(nameLayout.layoutSize.width,nameLayout.layoutSize.height))
                textRect.origin.x = insets.left + textXAdditional
                if item.descLayout == nil {
                    textRect.origin.y = insets.top - 1
                } else {
                    textRect.origin.y = 5
                }
                                
                if let afterNameImage = item.afterNameImage {
                    ctx.draw(afterNameImage, in: CGRect(x: textRect.maxX + 8, y: textRect.minY, width: afterNameImage.systemSize.width, height: afterNameImage.systemSize.height))
                }
                
               
                
                if case let .colorSelector(stateback) = item.type {
                    ctx.setFillColor(stateback.cgColor)
                    ctx.fillEllipse(in: NSMakeRect(containerView.frame.width - 14 - insets.right, floorToScreenPixels(backingScaleFactor, (containerView.frame.height - 14) / 2), 14, 14))
                }
            }
        }
    }
    
   
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        containerView.layerContentsRedrawPolicy = .duringViewResize
        
        nextView.anchorPoint = .zero
        nextView.masksToBounds = true
        containerView.layer?.insertSublayer(nextView, above: borderView)

        containerView.displayDelegate = self
        
        containerView.addSubview(nameView)
        
        
        
        containerView.set(handler: { [weak self] _ in
            self?.updateColors()
        }, for: .Highlight)
        containerView.set(handler: { [weak self] _ in
            self?.updateColors()
        }, for: .Normal)
        containerView.set(handler: { [weak self] _ in
            self?.updateColors()
        }, for: .Hover)
        
        containerView.set(handler: { [weak self] _ in
            self?.invokeIfNeededDown()
        }, for: .Down)
        
        containerView.set(handler: { [weak self] _ in
            if let event = NSApp.currentEvent {
                self?.mouseDragged(with: event)
            }
        }, for: .MouseDragging)
        
        containerView.set(handler: { [weak self] _ in
            self?.invokeIfNeededUp()
        }, for: .Up)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    #if !SHARE
    func showAccessibilityContextSelector(_ items: [ContextMenuItem]) -> Bool {
        let anchor: NSView = textView ?? containerView
        guard let window = window else {
            return false
        }
        if items.contains(where: { ($0.menu as? ContextMenu)?.isShown == true }) {
            return false
        }
        let point = anchor.convert(NSMakePoint(anchor.bounds.midX, anchor.bounds.midY), to: nil)
        guard let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else {
            return false
        }
        let menu = ContextMenu()
        for item in items {
            menu.addItem(item)
        }
        AppMenu.show(menu: menu, event: event, for: anchor)
        return true
    }
    #endif

    open func invokeAction(_ item: GeneralInteractedRowItem) {
        if item.enabled {
            if let textView = self.textView {
                switch item.type {
                case let .contextSelector(_, items):
                    if let event = NSApp.currentEvent {
                        if items.contains(where: { ($0.menu as? ContextMenu)?.isShown == true }) {
                            return
                        }
                        let menu = ContextMenu()

                        for item in items {
                            menu.addItem(item)
                        }
                        AppMenu.show(menu: menu, event: event, for: textView)
                    }
                    
                    return
                default:
                    break
                }
            }
            
            switch item.type {
            case .switchable:
                if item.switchAction == nil, let switchView {
                    switchView.performToggle()
                    return
                }
            default:
                break
            }
            item.action()
        } else {
            if let action = item.disabledAction {
                action()
            }
        }
    }
    private func invokeIfNeededUp() {
        if let event = NSApp.currentEvent {
            guard let item = item as? GeneralInteractedRowItem else {
                return
            }
            if case .contextSelector = item.type {
                
            } else if let table = item.table, table.alwaysOpenRowsOnMouseUp, containerView.mouseInside() {
                invokeAction(item)
            } else {
                super.mouseUp(with: event)
            }
        }
        
    }
    private func invokeIfNeededDown() {
        if let event = NSApp.currentEvent {
            guard let item = item as? GeneralInteractedRowItem else {
                return
            }
            if case .contextSelector = item.type {
                invokeAction(item)
            } else if let table = item.table, !table.alwaysOpenRowsOnMouseUp, containerView.mouseInside() {
                invokeAction(item)
            } else {
                super.mouseDown(with: event)
            }
        }
    }
    
    
    open override func layout() {
        super.layout()
        
        
        if let item = item as? GeneralInteractedRowItem {
            let insets = item.inset
                        
            switch item.viewType {
            case .legacy:
                if let descriptionView = descriptionView {
                    descriptionView.setFrameOrigin(insets.left + textXAdditional, floorToScreenPixels(backingScaleFactor, frame.height - descriptionView.frame.height - 6))
                }
                let nextInset = nextView.isHidden ? 0 : nextView.frame.width + 6 + (insets.right == 0 ? 10 : 0)
                
                if let switchView = switchView {
                    switchView.centerY(x:containerView.frame.width - insets.right - switchView.frame.width - nextInset, addition: -1)
                }
                
                if let badgeView = badgeView {
                    badgeView.centerY(x:containerView.frame.width - insets.right - badgeView.frame.width - nextInset, addition: -1)
                }
                
                let nameLayout = (item.isSelected ? item.nameLayoutSelected : item.nameLayout)
                
                var textRect = focus(NSMakeSize(nameLayout.layoutSize.width, nameLayout.layoutSize.height))
                textRect.origin.x = item.inset.left + textXAdditional
                textRect.origin.y -= 2
                if item.descLayout != nil {
                    textRect.origin.y = 10
                }
                nameView.setFrameOrigin(textRect.origin)
                
                if let textView = textView {
                    let width:CGFloat = containerView.frame.width - item.nameLayout.layoutSize.width - nextInset - insets.right - insets.left - 10
                    textView.textLayout?.measure(width: width)
                    textView.update(textView.textLayout)
                    textView.centerY(x: containerView.frame.width - insets.right - textView.frame.width - nextInset, addition: -1)
                    if !nextView.isHidden {
                        textView.setFrameOrigin(textView.frame.minX,textView.frame.minY - 1)
                    }
                }
                if let current = self.imageContext {
                    current.centerY(x: containerView.frame.width - insets.right - current.frame.width - nextInset)
                    if !nextView.isHidden {
                        current.setFrameOrigin(current.frame.minX, current.frame.minY - 2)
                    }
                }
                
                nextView.frame.origin = NSMakePoint(containerView.frame.width - (insets.right == 0 ? 10 : insets.right) - nextView.frame.width, round((containerView.frame.height - nextView.frame.height) / 2.0))
                if let progressView = progressView {
                    progressView.centerY(x: containerView.frame.width - (insets.right == 0 ? 10 : insets.right) - progressView.frame.width, addition: -1)
                }
            case let .modern(_, innerInsets):
                                
                if let current = self.selectLeftControl {
                    current.centerY(x: innerInsets.left)
                }
                
                let balancedOffset: CGFloat = item.balancedDescriptionLayout ? 2 : 0
                if let descriptionView = self.descriptionView {
                    descriptionView.setFrameOrigin(innerInsets.left + textXAdditional, containerView.frame.height - descriptionView.frame.height - 5 - balancedOffset)
                }
                var nextInset = nextView.isHidden ? 0 : nextView.frame.width + 6
                
                if let switchView = switchView {
                    switchView.centerY(x: containerView.frame.width - innerInsets.right - switchView.frame.width - nextInset, addition: -1)
                }
                
                let nameLayout = (item.isSelected ? item.nameLayoutSelected : item.nameLayout)
                
                var textRect = focus(NSMakeSize(nameLayout.layoutSize.width, nameLayout.layoutSize.height))
                textRect.origin.x = innerInsets.left + textXAdditional
                if item.descLayout == nil {
                    textRect.origin.y = innerInsets.top - 1
                } else {
                    textRect.origin.y = 5 - balancedOffset
                }
                
                nameView.setFrameOrigin(textRect.origin)

                
                if let textView = textView {
                    let width:CGFloat = containerView.frame.width - item.nameLayout.layoutSize.width - innerInsets.right - insets.left - 10
                    textView.textLayout?.measure(width: width)
                    textView.update(textView.textLayout)
                    if let secondaryTextView = secondaryTextView {
                        secondaryTextView.textLayout?.measure(width: width)
                        secondaryTextView.update(secondaryTextView.textLayout)
                        let totalHeight = textView.frame.height + secondaryTextView.frame.height + 2
                        let startY = (containerView.frame.height - totalHeight) / 2
                        textView.setFrameOrigin(NSMakePoint(containerView.frame.width - innerInsets.right - textView.frame.width - nextInset, startY))
                        secondaryTextView.setFrameOrigin(NSMakePoint(containerView.frame.width - innerInsets.right - secondaryTextView.frame.width - nextInset, startY + textView.frame.height + 2))
                    } else {
                        textView.centerY(x: containerView.frame.width - innerInsets.right - textView.frame.width - nextInset)
                        if !nextView.isHidden {
                            textView.setFrameOrigin(textView.frame.minX, textView.frame.minY - 1)
                        }
                    }
                }
                if let current = self.imageContext {
                    current.centerY(x: containerView.frame.width - innerInsets.right - current.frame.width - nextInset)
                    if !nextView.isHidden {
                        current.setFrameOrigin(current.frame.minX, current.frame.minY - 2)
                    }
                }
                
                if let textView = textView {
                    nextInset += textView.frame.width + 10
                }
                nextView.frame.origin = NSMakePoint(containerView.frame.width - innerInsets.right - nextView.frame.width, round((containerView.frame.height - nextView.frame.height) / 2.0) - 1)
                if let progressView = progressView {
                    progressView.centerY(x: containerView.frame.width - innerInsets.right - progressView.frame.width, addition: -1)
                }
                
                if let badgeView = badgeView {
                    badgeView.centerY(x: containerView.frame.width - innerInsets.right - badgeView.frame.width - nextInset, addition: -1)
                }
                
                if let imageView = self.rightIconView {
                    imageView.centerY(x: containerView.frame.width - imageView.frame.width - nextInset - 10)
                }
            }
        }
    }
    
}
