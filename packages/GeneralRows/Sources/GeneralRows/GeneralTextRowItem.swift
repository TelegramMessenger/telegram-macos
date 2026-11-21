import Cocoa
import TGUIKit
import SwiftSignalKit
#if SHARE
import TelegramThemeShare
import TelegramContextShare
#else
import TelegramTheme
import TelegramContext
import ColorPalette
#endif

public enum GeneralRowTextType : Equatable {
    case plain(String)
    case attributed(NSAttributedString)
    case markdown(String, linkHandler: (String)->Void)
    case customMarkdown(String, linkColor: NSColor, linkFont: NSFont, linkHandler: (String)->Void)

    public static func ==(lhs: GeneralRowTextType, rhs: GeneralRowTextType) -> Bool {
        switch lhs {
        case let .plain(text):
            if case .plain(text) = rhs {
                return true
            } else {
                return false
            }
        case let .attributed(text):
            if case .attributed(text) = rhs {
                return true
            } else {
                return false
            }
        case let .markdown(text, _):
            if case .markdown(text, _) = rhs {
                return true
            } else {
                return false
            }
        case let .customMarkdown(text, color, font, _):
            if case .customMarkdown(text, color, font, _) = rhs {
                return true
            } else {
                return false
            }
        }
    }
}



open class GeneralTextRowItem: GeneralRowItem {
    fileprivate let textColor: NSColor
    fileprivate var layout:TextViewLayout
    private let text:NSAttributedString
    private let alignment:NSTextAlignment
    fileprivate let centerViewAlignment: Bool
    fileprivate let additionLoading: Bool
    fileprivate let isTextSelectable: Bool
    fileprivate let rightItem: InputDataGeneralTextRightData
    fileprivate let contextMenu: (()->[ContextMenuItem])?
    fileprivate let clickable: Bool
    fileprivate let clickableCornerRadius: CGFloat
    fileprivate let context: (any AccountContextProtocol)?
    public init(_ initialSize: NSSize, stableId: AnyHashable = arc4random(), height: CGFloat = 0, text:NSAttributedString, alignment:NSTextAlignment = .left, drawCustomSeparator:Bool = false, border:BorderType = [], inset:NSEdgeInsets = NSEdgeInsets(left: 20, right: 20, top:4, bottom:2), action: @escaping ()->Void = {}, centerViewAlignment: Bool = false, additionLoading: Bool = false, additionRightText: String? = nil, linkExecutor: TextViewInteractions = GeneralRowsHooks.shared.linkExecutor(), isTextSelectable: Bool = false, detectLinks: Bool = true, viewType: GeneralViewType = .legacy, rightItem: InputDataGeneralTextRightData = InputDataGeneralTextRightData(isLoading: false, text: nil), contextMenu: (()->[ContextMenuItem])? = nil, clickable: Bool = false, clickableCornerRadius: CGFloat = .cornerRadius, context: (any AccountContextProtocol)? = nil) {
        self.textColor = theme.colors.listGrayText
        self.isTextSelectable = isTextSelectable
        self.contextMenu = contextMenu
        self.context = context
        self.clickable = clickable
        self.clickableCornerRadius = clickableCornerRadius
        let mutable = text.mutableCopy() as! NSMutableAttributedString
        if detectLinks {
            GeneralRowsHooks.shared.detectLinks(mutable)
        }
        self.rightItem = rightItem
        self.text = mutable
        self.additionLoading = additionLoading
        self.alignment = alignment
        self.centerViewAlignment = centerViewAlignment
        layout = TextViewLayout(mutable, truncationType: .end, alignment: alignment)
        layout.interactions = linkExecutor
        super.init(initialSize, height: height, stableId: stableId, type: .none, viewType: viewType, action: action, drawCustomSeparator: drawCustomSeparator, border: border, inset: inset)
    }
    
    open override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        if let contextMenu = contextMenu {
            return .single(contextMenu())
        } else {
            return super.menuItems(in: location)
        }
    }
    
    public init(_ initialSize: NSSize, stableId: AnyHashable = arc4random(), height: CGFloat = 0, text: GeneralRowTextType, detectBold: Bool = true, textColor: NSColor = theme.colors.listGrayText, linkColor: NSColor = theme.colors.link, alignment:NSTextAlignment = .left, drawCustomSeparator:Bool = false, border:BorderType = [], inset:NSEdgeInsets = NSEdgeInsets(left: 20, right: 20, top:4, bottom:2), action: @escaping ()->Void = {}, centerViewAlignment: Bool = false, additionLoading: Bool = false, isTextSelectable: Bool = false, viewType: GeneralViewType = .legacy, rightItem: InputDataGeneralTextRightData = InputDataGeneralTextRightData(isLoading: false, text: nil), fontSize: CGFloat? = nil, contextMenu: (()->[ContextMenuItem])? = nil, clickable: Bool = false, clickableCornerRadius: CGFloat = .cornerRadius, context: (any AccountContextProtocol)? = nil, linkExecutor: TextViewInteractions = GeneralRowsHooks.shared.linkExecutor()) {

        let attributedText: NSMutableAttributedString
        self.textColor = textColor
        self.contextMenu = contextMenu
        self.clickable = clickable
        self.clickableCornerRadius = clickableCornerRadius
        self.context = context
        switch text {
        case let .attributed(attr):
            attributedText = attr.mutableCopy() as! NSMutableAttributedString
        case let .plain(text):
            attributedText = NSAttributedString.initialize(string: text, color: textColor, font: .normal(fontSize ?? 11.5)).mutableCopy() as! NSMutableAttributedString
        case let .markdown(text, handler):
            attributedText = parseMarkdownIntoAttributedString(text, attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .normal(fontSize ?? 11.5), textColor: textColor), bold: MarkdownAttributeSet(font: .bold(fontSize ?? 11.5), textColor: textColor), link: MarkdownAttributeSet(font: .normal(fontSize ?? 11.5), textColor: linkColor), linkAttribute: { contents in
                return GeneralRowsHooks.shared.linkAttribute(contents, handler)
            })).mutableCopy() as! NSMutableAttributedString
        case let .customMarkdown(text, linkColor, linkFont, handler):
            attributedText = parseMarkdownIntoAttributedString(text, attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .normal(fontSize ?? 11.5), textColor: textColor), bold: MarkdownAttributeSet(font: .bold(fontSize ?? 11.5), textColor: textColor), link: MarkdownAttributeSet(font: linkFont, textColor: linkColor), linkAttribute: { contents in
                return GeneralRowsHooks.shared.linkAttribute(contents, handler)
            })).mutableCopy() as! NSMutableAttributedString
        }
        if detectBold {
            attributedText.detectBoldColorInString(with: .bold(fontSize ?? 11.5))
        }
        self.rightItem = rightItem
        self.text = attributedText
        self.alignment = alignment
        self.isTextSelectable = isTextSelectable
        self.additionLoading = additionLoading
        self.centerViewAlignment = centerViewAlignment
        layout = TextViewLayout(attributedText, truncationType: .end, alignment: alignment)
        layout.interactions = linkExecutor
        super.init(initialSize, height: height, stableId: stableId, type: .none, viewType: viewType, action: action, drawCustomSeparator: drawCustomSeparator, border: border, inset: inset)
    }
    
    public init(_ initialSize: NSSize, stableId: AnyHashable = arc4random(), height: CGFloat = 0, text:String, detectBold: Bool = true, textColor: NSColor = theme.colors.listGrayText, alignment:NSTextAlignment = .left, drawCustomSeparator:Bool = false, border:BorderType = [], inset:NSEdgeInsets = NSEdgeInsets(left: 20, right: 20), action: @escaping ()->Void = {}, centerViewAlignment: Bool = false, additionLoading: Bool = false, fontSize: CGFloat = 11.5, isTextSelectable: Bool = false, viewType: GeneralViewType = .legacy, rightItem: InputDataGeneralTextRightData = InputDataGeneralTextRightData(isLoading: false, text: nil), contextMenu: (()->[ContextMenuItem])? = nil, clickable: Bool = false, clickableCornerRadius: CGFloat = .cornerRadius, context: (any AccountContextProtocol)? = nil, linkExecutor: TextViewInteractions = GeneralRowsHooks.shared.linkExecutor()) {
        let attr = NSAttributedString.initialize(string: text, color: textColor, font: .normal(fontSize)).mutableCopy() as! NSMutableAttributedString
        if detectBold {
            attr.detectBoldColorInString(with: .medium(fontSize))
        }
        self.clickable = clickable
        self.clickableCornerRadius = clickableCornerRadius
        self.textColor = textColor
        self.context = context
        self.text = attr
        self.contextMenu = contextMenu
        self.alignment = alignment
        self.isTextSelectable = isTextSelectable
        self.additionLoading = additionLoading
        self.centerViewAlignment = centerViewAlignment
        layout = TextViewLayout(self.text, truncationType: .end, alignment: alignment)
        layout.interactions = linkExecutor
        self.rightItem = rightItem
        super.init(initialSize, height: height, stableId: stableId, type: .none, viewType: viewType, action: action, drawCustomSeparator: drawCustomSeparator, border: border, inset: inset)
    }
    
    
    
    open override var inset: NSEdgeInsets {
        if settingsPresentation != nil {
            return NSEdgeInsets(left: super.inset.left, right: super.inset.right)
        }
        return super.inset
    }

    @discardableResult
    open override func withSettingsLayout(_ presentation: SettingsRowPresentation = .content) -> Self {
        let isHeader = viewType.innerInset.top == 0 && viewType.innerInset.bottom > 0
        super.withSettingsLayout(presentation)
        guard settingsPresentation != nil else { return self }
        setSettingsInsets(NSEdgeInsets(top: isHeader ? 0 : 6, left: SettingsRowMetrics.contentInset, bottom: isHeader ? 6 : 0, right: SettingsRowMetrics.contentInset))
        let text = NSMutableAttributedString(attributedString: layout.attributedString)
        if isHeader {
            let string = text.string
            if string.rangeOfCharacter(from: .lowercaseLetters) == nil {
                text.replaceCharacters(in: text.range, with: string.settingsTitleCase)
            }
            text.addAttribute(.foregroundColor, value: theme.colors.text, range: text.range)
        }
        text.enumerateAttribute(.font, in: text.range) { value, range, _ in
            let font = value as? NSFont ?? .normal(SettingsRowMetrics.subtitleSize)
            text.addAttribute(.font, value: isHeader ? NSFont.bold(SettingsRowMetrics.titleSize) : NSFontManager.shared.convert(font, toSize: SettingsRowMetrics.subtitleSize), range: range)
        }
        let interactions = layout.interactions
        layout = TextViewLayout(text, alignment: alignment)
        layout.interactions = interactions
        _ = makeSize(width, oldWidth: 0)
        return self
    }

    open override var height: CGFloat {
        if _height > 0 {
            return _height
        }
        switch viewType {
        case .legacy:
            return layout.layoutSize.height + inset.top + inset.bottom + (additionLoading ? 30 : 0)
        case let .modern(_, insets):
            return layout.layoutSize.height + inset.top + inset.bottom + insets.top + insets.bottom + (additionLoading ? 30 : 0)
        }
    }
    
    open override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        switch viewType {
        case .legacy:
            layout.measure(width: width - inset.left - inset.right)
        case let .modern(_, insets):
            var addition: CGFloat = 0
            if let text = rightItem.text {
                let layout = TextViewLayout(text)
                layout.measure(width: .greatestFiniteMagnitude)
                addition += layout.layoutSize.width + 20
            }
            layout.measure(width: self.blockWidth - insets.left - insets.right - addition)
        }

        return success
    }
    
    open override func viewClass() -> AnyClass {
        return GeneralTextRowView.self
    }

    open override var accessibilityLabel: String? {
        let string = layout.attributedString.string
        return string.isEmpty ? nil : string
    }

    open override var accessibilityValue: String? {
        guard let right = rightItem.text?.string, !right.isEmpty else {
            return nil
        }
        return right
    }

    open override var accessibilityRole: NSAccessibility.Role? {
        return accessibilityIncludesChildren ? nil : .staticText
    }

    open override var accessibilityIncludesChildren: Bool {
        if clickable || rightItem.action != nil || rightItem.contextMenu != nil {
            return true
        }
        var hasLink = false
        let attributed = layout.attributedString
        attributed.enumerateAttribute(.link, in: attributed.range, options: [.longestEffectiveRangeNotRequired]) { value, _, stop in
            if value != nil {
                hasLink = true
                stop.pointee = true
            }
        }
        return hasLink
    }
    
}


open class GeneralTextRowView : GeneralRowView {
    public let textView:InteractiveTextView = InteractiveTextView(frame: .zero)
    private var progressView: ProgressIndicator?
    private var rightTextView: InteractiveTextView?
    private var afterRightIcon: ImageView?
    private var animatedView: GeneralRowsAnimatedItemView?
    private var clickable: Control?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        textView.textView.userInteractionEnabled = true
    }
    
    open override var firstResponder: NSResponder? {
        return nil
    }
    
    open override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        if let item = item as? GeneralTextRowItem {
            switch item.viewType {
            case .legacy:
                if item.drawCustomSeparator {
                    ctx.setFillColor(theme.colors.border.cgColor)
                    ctx.fill(NSMakeRect(item.inset.left, frame.height - .borderSize, frame.width - item.inset.left - item.inset.right, .borderSize))
                }
            case .modern:
                break
            }
        }
    }
    
    open override var backdorColor: NSColor {
        if let item = item as? GeneralTextRowItem {
            return item.viewType.rowBackground
        }
        return theme.colors.background
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        textView.backgroundColor = self.backdorColor
        
        guard let item = item as? GeneralTextRowItem else {return}
        textView.textView.isSelectable = item.isTextSelectable
        textView.userInteractionEnabled = !item.clickable
        textView.textView.userInteractionEnabled = !item.clickable
        textView.set(text: item.layout, context: item.context)
        
        if item.additionLoading || item.rightItem.isLoading {
            let size = item.rightItem.isLoading ? NSMakeSize(15, 15) : NSMakeSize(20, 20)
            if progressView == nil {
                progressView = ProgressIndicator(frame: NSMakeRect(0, 0, size.width, size.height))
            }
            if progressView!.superview == nil {
                addSubview(progressView!)
            }
        } else {
            progressView?.removeFromSuperview()
            progressView = nil
        }
        
        if let text = item.rightItem.text {
            if self.rightTextView == nil {
                self.rightTextView = InteractiveTextView()
                addSubview(self.rightTextView!)
            }
            rightTextView?.layer?.cornerRadius = item.rightItem.cornerRadius
            
            if let iconAfter = item.rightItem.afterImage {
                if afterRightIcon == nil {
                    afterRightIcon = ImageView()
                    afterRightIcon?.isAccessibilityDecorative = true
                    afterRightIcon?.image = iconAfter
                    afterRightIcon?.sizeToFit()
                    addSubview(afterRightIcon!)
                }
            } else {
                afterRightIcon?.removeFromSuperview()
                afterRightIcon = nil
            }
            
            if let wrap = item.rightItem.wrap {
                rightTextView?.backgroundColor = wrap
            }
            
            let textLayout = TextViewLayout(text, alignment: .center)
            
            textLayout.measure(width: .greatestFiniteMagnitude)
            
            var animatedData:InputDataTextInsertAnimatedViewData?
            text.enumerateAttributes(in: text.range, options: [], using: { data, range, stop in
                
                if let attr = data[InputDataTextInsertAnimatedViewData.attributeKey] {
                    animatedData = attr as? InputDataTextInsertAnimatedViewData
                }
            })
            
            if let attr = animatedData {
                if self.animatedView == nil {
                    self.animatedView = GeneralRowsHooks.shared.makeAnimatedItemView()
                    self.addSubview(self.animatedView!)
                }
                self.animatedView?.updateAnimatedItem(context: attr.context, file: attr.file, size: NSMakeSize(16, 16), animated: animated)

            } else {
                self.animatedView?.removeFromSuperview()
                self.animatedView = nil
            }
            
            if let rightTextView = rightTextView {
                rightTextView.set(text: textLayout, context: item.context)
                
                if item.rightItem.alignToText {
                    rightTextView.setFrameSize(rightTextView.frame.width + 6, rightTextView.frame.height + 4)
                }
                
                rightTextView.textView.isSelectable = false
                rightTextView.userInteractionEnabled = item.rightItem.action != nil || item.rightItem.contextMenu?() != nil
                
                if let action = item.rightItem.action {
                    rightTextView.setSingle(handler: { _ in
                        action()
                    }, for: .Click)
                } else if let contextMenuItems = item.rightItem.contextMenu?() {
                    rightTextView.setSingle(handler: { control in
                        if let event = NSApp.currentEvent {
                            let menu = ContextMenu()
                            menu.items = contextMenuItems
                            AppMenu.show(menu: menu, event: event, for: control)
                        }
                    }, for: .Click)
                }
            }
           
        } else {
            self.rightTextView?.removeFromSuperview()
            self.rightTextView = nil
            self.animatedView?.removeFromSuperview()
            self.animatedView = nil
            
            afterRightIcon?.removeFromSuperview()
            afterRightIcon = nil
        }

        if item.clickable {
            let current: Control
            if let view = self.clickable {
                current = view
            } else {
                current = Control()
                self.clickable = current
                addSubview(current, positioned: .below, relativeTo: self.textView)
            }
            current.set(background: item.customTheme?.backgroundColor ?? theme.colors.background, for: .Normal)
            current.layer?.cornerRadius = item.clickableCornerRadius
            current.setAccessibilityLabel(item.layout.attributedString.string)
            
            current.contextMenu = { [weak item] in
                if let items = item?.contextMenu?() {
                    let menu = ContextMenu()
                    for item in items {
                        menu.addItem(item)
                    }
                    return menu
                }
                return nil
            }
            
        }
        
        needsDisplay = true
        needsLayout = true
    }
    
    open override func mouseUp(with event: NSEvent) {
        if let item = item as? GeneralTextRowItem, mouseInside() {
           item.action()
        } else {
            super.mouseUp(with: event)
        }
    }
    
    open override func shakeView() {
        textView.shake()
    }
    
    open override func layout() {
        super.layout()
        if let item = item as? GeneralTextRowItem {
            if item.additionLoading, let progressView = progressView {
                progressView.centerX(y: 0)
                textView.centerX(y: progressView.frame.maxY + 10)
            } else {
                switch item.viewType {
                case .legacy:
                    textView.setFrameOrigin(NSMakePoint(item.inset.left, item.inset.top))
                case let .modern(_, insets):
                    let mid = max(0, floorToScreenPixels(backingScaleFactor, (frame.width - item.blockWidth) / 2))
                    textView.setFrameOrigin(NSMakePoint(mid + insets.left, item.inset.top + insets.top))
                    
                    if item.rightItem.isLoading, let progressView = self.progressView {
                        if item.rightItem.text == nil {
                            progressView.setFrameOrigin(NSMakePoint(mid + insets.left, item.inset.top + insets.top))
                            textView.setFrameOrigin(NSMakePoint(mid + insets.left + progressView.frame.width + 5, item.inset.top + insets.top))
                        } else {
                            progressView.setFrameOrigin(NSMakePoint(frame.width - progressView.frame.width - mid - insets.left - insets.right, item.inset.top + insets.top))
                        }
                        progressView.progressColor = item.textColor
                    }
                    if let rightTextView = self.rightTextView {
                        
                        var inset: CGFloat = 0
                        if let afterRightIcon {
                            inset += afterRightIcon.frame.width - 2
                        }
                        
                        if item.rightItem.alignToText {
                            rightTextView.setFrameOrigin(NSMakePoint(textView.frame.maxX + 3, textView.frame.minY - 1))
                        } else {
                            rightTextView.setFrameOrigin(NSMakePoint(frame.width - rightTextView.frame.width - mid - insets.left - insets.right - inset, frame.height - insets.bottom - rightTextView.frame.height))
                        }
                        
                        if let layout = rightTextView.textView.textLayout {
                            var animatedRange: NSRange? = nil
                            layout.attributedString.enumerateAttributes(in: layout.attributedString.range, options: [], using: { data, range, stop in
                                if let _ = data[InputDataTextInsertAnimatedViewData.attributeKey] {
                                    animatedRange = range
                                }
                            })
                            if let range = animatedRange, let view = self.animatedView, let offset = layout.offset(for: range.location) {
                                view.setFrameOrigin(NSMakePoint(rightTextView.frame.minX + offset, rightTextView.frame.minY - 1))
                            }
                        }
                        
                        if let afterRightIcon {
                            afterRightIcon.setFrameOrigin(NSMakePoint(rightTextView.frame.maxX + 2, rightTextView.frame.minY))
                        }
                    }
                    if let current = clickable {
                        current.frame = textView.frame.insetBy(dx: -3, dy: -2)
                        if let rightTextView = self.rightTextView, item.rightItem.alignToText {
                            rightTextView.setFrameOrigin(NSMakePoint(current.frame.maxX + 6, current.frame.minY))
                        }
                    }
                }
               
                
            }
            if item.centerViewAlignment {
                textView.center()                
            }
        }
    }
}
