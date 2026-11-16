import ColorPalette
import GeneralRows
import TelegramContext
import TelegramTheme
import TelegramUtils
import Localization
import Cocoa
import TGUIKit
import TGModernGrowingTextView
import Postbox

public protocol InputDataRowDataValue {
    var value: InputDataValue { get }
}

public enum InputDataRightItemAction : Equatable {
    public static func == (lhs: InputDataRightItemAction, rhs: InputDataRightItemAction) -> Bool {
        switch lhs {
        case .clearText:
            if case .clearText = rhs {
                return true
            } else {
                return false
            }
        case .resort:
            if case .resort = rhs {
                return true
            } else {
                return false
            }
        case .none:
            if case .none = rhs {
                return true
            } else {
                return false
            }
        case .custom:
            if case .custom = rhs {
                return true
            } else {
                return false
            }
        }
    }
    
    case clearText
    case resort
    case custom((TableRowItem, Control)->Void)
    case none
}

public enum InputDataRightItem : Equatable {
    case action(CGImage, InputDataRightItemAction)
    case loading
    case actionWithLoading(CGImage, InputDataRightItemAction)
    case media(Media, any AccountContextProtocol, Bool, Float, InputDataRightItemAction)

    public static func == (lhs: InputDataRightItem, rhs: InputDataRightItem) -> Bool {
        switch lhs {
        case let .action(lhsImage, lhsAction):
            if case let .action(rhsImage, rhsAction) = rhs {
                return lhsImage === rhsImage && lhsAction == rhsAction
            }
            return false
        case .loading:
            if case .loading = rhs { return true }
            return false
        case let .actionWithLoading(lhsImage, lhsAction):
            if case let .actionWithLoading(rhsImage, rhsAction) = rhs {
                return lhsImage === rhsImage && lhsAction == rhsAction
            }
            return false
        case let .media(lhsMedia, _, lhsLoading, lhsProgress, lhsAction):
            if case let .media(rhsMedia, _, rhsLoading, rhsProgress, rhsAction) = rhs {
                return lhsMedia.isEqual(to: rhsMedia) && lhsLoading == rhsLoading && lhsProgress == rhsProgress && lhsAction == rhsAction
            }
            return false
        }
    }
}

open class InputDataRowItem: GeneralRowItem, InputDataRowDataValue {

    fileprivate let placeholderLayout: TextViewLayout?
    fileprivate let placeholder: InputDataInputPlaceholder?
    
    
    fileprivate let inputPlaceholder: NSAttributedString
    fileprivate let filter:(String)->String
    fileprivate let allowsReplacementText: ((String) -> Bool)?
    fileprivate let shouldShakeOnFilterCorrection: ((String) -> Bool)?
    public let limit:Int32
    private let updated:(String)->Void
    private var updatedText: String?
    private var _currentText: NSAttributedString = NSAttributedString() {
        didSet {
            let newValue = currentText.string
            if updatedText != newValue {
                updated(newValue)
                updatedText = newValue
            }
        }
    }
    public fileprivate(set) var currentText: NSAttributedString {
        set {
            let copy = newValue.mutableCopy() as! NSMutableAttributedString
            if let defaultText = self.defaultText {
                copy.replaceCharacters(in: NSMakeRange(0, min(defaultText.length, copy.length)), with: "")
            }
             _currentText = copy
            
            if copy != newValue {
                self.noteHeightOfRow()
            }
        }
        get {
            return _currentText
        }
    }
    

    
    open var currentAttributed: NSAttributedString {
        let attr = NSMutableAttributedString()
        
        if let defaultText = self.defaultText {
            attr.append(.initialize(string: defaultText, color: theme.colors.text, font: .normal(.text)))
        }
        attr.append(currentText)
        return attr
    }
    
    open var value: InputDataValue {
        if canMakeTransformations {
            return .attributedString(currentText)
        } else {
            return .string(currentText.string)
        }
    }
    
    fileprivate var inputHeight: CGFloat = 21
    fileprivate var realInputHeight: CGFloat = 21
    
    open override var inset: NSEdgeInsets {
        var inset = super.inset
        switch viewType {
        case .legacy:
            break
        case .modern:
            if let errorLayout = errorLayout {
                inset.bottom += errorLayout.layoutSize.height + 4
            }
        }
        return inset
    }

    open override var height: CGFloat {
        switch viewType {
        case .legacy:
            var height = inputHeight + 8
            if let errorLayout = errorLayout  {
                height += (height == 42 ? errorLayout.layoutSize.height : errorLayout.layoutSize.height / 2)
            }
            return height
        case let .modern(_, insets):
            var inputHeight = realInputHeight
            switch self.mode {
            case .plain:
                break
            case .secure:
                inputHeight -= 6
            }
            let height = inputHeight + insets.top + insets.bottom + inset.top + inset.bottom
//            if let errorLayout = errorLayout  {
//                height += errorLayout.layoutSize.height + 4
//            }
            return height
        }
       
    }
    fileprivate let defaultText: String?
    fileprivate let mode: InputDataInputMode
    fileprivate let rightItem: InputDataRightItem?
    fileprivate let canMakeTransformations: Bool
    fileprivate let pasteFilter:((String)->(Bool, String))?
    private let maxBlockWidth: CGFloat?
    public init(_ initialSize: NSSize, stableId: AnyHashable, mode: InputDataInputMode, error: InputDataValueError?, viewType: GeneralViewType = .legacy, currentText: String, currentAttributedText: NSAttributedString? = nil, placeholder: InputDataInputPlaceholder?, inputPlaceholder: String, defaultText: String? = nil, rightItem: InputDataRightItem? = nil, canMakeTransformations: Bool = false, insets: NSEdgeInsets = NSEdgeInsets(left: 20, right: 20), maxBlockWidth: CGFloat? = nil, filter:@escaping(String)->String, updated:@escaping(String)->Void, pasteFilter:((String)->(Bool, String))? = nil, limit: Int32, allowsReplacementText: ((String) -> Bool)? = nil, shouldShakeOnFilterCorrection: ((String) -> Bool)? = nil, customTheme: GeneralRowItem.Theme? = nil) {
        self.filter = filter
        self.allowsReplacementText = allowsReplacementText
        self.shouldShakeOnFilterCorrection = shouldShakeOnFilterCorrection
        self.limit = limit
        self.updated = updated
        self.placeholder = placeholder
        self.pasteFilter = pasteFilter
        self.defaultText = defaultText
        self.maxBlockWidth = maxBlockWidth
        self.canMakeTransformations = canMakeTransformations
        self.rightItem = rightItem
        let holder = NSMutableAttributedString()
        switch mode {
        case .secure:
            holder.append(.initialize(string: inputPlaceholder, color: customTheme?.grayTextColor ?? theme.colors.grayText, font: .light(.text)))
        case .plain:
            holder.append(.initialize(string: inputPlaceholder, color: customTheme?.grayTextColor ?? theme.colors.grayText, font: .normal(.text)))
        }
        self.inputPlaceholder = holder
        placeholderLayout = placeholder?.placeholder != nil ? TextViewLayout(.initialize(string: placeholder!.placeholder!, color: customTheme?.grayTextColor ?? theme.colors.text, font: .normal(.text)), maximumNumberOfLines: 1) : nil
    
        _currentText = currentAttributedText ?? NSAttributedString.initialize(string: currentText, color: theme.colors.text, font: .normal(.text))
        self.mode = mode
    
        super.init(initialSize, stableId: stableId, viewType: viewType, inset: insets, error: error, customTheme: customTheme)
        
       
        _ = makeSize(initialSize.width, oldWidth: oldWidth)
    }
    
    open override var blockWidth: CGFloat {
        if let maxBlockWidth = maxBlockWidth {
            return min(maxBlockWidth, super.blockWidth)
        } else {
            return super.blockWidth
        }
    }
    
    open var textFieldLeftInset: CGFloat {
        if let placeholder = placeholder {
            if let placeholder = placeholder.placeholder {
                if placeholder.trimmingCharacters(in: CharacterSet(charactersIn: "0987654321")).isEmpty {
                    return 30
                } else {
                    return 102
                }
            } else {
                if let icon = placeholder.icon {
                    return icon.backingSize.width + 6 + placeholder.insets.left
                } else {
                    return -2
                }
            }
        } else {
            return -2
        }
    }
    
    open override var instantlyResize: Bool {
        return true
    }
    
    open func calculateHeight() {
        _ = self.makeSize(self.width, oldWidth: self.width)
    }
    
    open var hasTextLimitation: Bool {
        if let placeholder = placeholder {
            return placeholder.hasLimitationText
        } else {
            return limit > 30 && defaultText == nil
        }
    }
    
    private(set) fileprivate var additionRightInset: CGFloat = 0
    
    open override func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool {
        let currentAttributed: NSMutableAttributedString = NSMutableAttributedString()
        _ = currentAttributed.append(string: (defaultText ?? ""), font: .normal(.text))
        currentAttributed.append(currentText)
                
        if mode == .secure {
            currentAttributed.setAttributedString(.init(string: String(currentText.string.map { _ in return "•" })))
            currentAttributed.addAttribute(.font, value: NSFont.normal(15.0 + 3.22), range: currentAttributed.range)
        }
                
        if let rightItem = self.rightItem {
            switch rightItem {
            case .loading:
                self.additionRightInset = 20
            case let .action(icon, _):
                self.additionRightInset = icon.backingSize.width + 2
            case let .actionWithLoading(icon, _):
                self.additionRightInset = icon.backingSize.width + 2
            case .media:
                self.additionRightInset = 26
            }
        } else {
            self.additionRightInset = 0
        }
        
        if hasTextLimitation {
            self.additionRightInset += 20
        }
        
        switch viewType {
        case .legacy:
            let height = currentAttributed.sizeFittingWidth(initialSize.width - inset.left - inset.right - textFieldLeftInset - additionRightInset).height
            self.realInputHeight = max(34, height + 6)
            inputHeight = max(34, height + 6)
        case let .modern(_, insets):
            let height = currentAttributed.sizeFittingWidth(self.blockWidth - insets.left - insets.right - textFieldLeftInset - additionRightInset).height
            
            switch self.mode {
            case .plain:
                self.realInputHeight = max(16, height)
            case .secure:
                self.realInputHeight = max(22, height)
            }
            inputHeight = max(34, height + 1)
        }
        
        let success = super.makeSize(width, oldWidth: oldWidth)
        placeholderLayout?.measure(width: 100)
        return success
    }
    
    open override var accessibilityLabel: String? {
        if let title = placeholderLayout?.attributedString.string, !title.isEmpty {
            return title
        }
        return inputPlaceholder.string.isEmpty ? nil : inputPlaceholder.string
    }

    open override func viewClass() -> AnyClass {
        return InputDataRowView.self
    }
    
}

private final class InputDataSecureField : NSSecureTextField {
    override func becomeFirstResponder() -> Bool {
        
        let success = super.becomeFirstResponder()
        if success {
            let tetView = self.currentEditor() as? NSTextView
            tetView?.insertionPointColor = theme.colors.indicatorColor
        }
        //NSTextView* textField = (NSTextView*) [self currentEditor];
        
        return success
    }
}


open class InputDataRowView : GeneralRowView, TGModernGrowingDelegate, NSTextFieldDelegate, InputDataTextFormatting {
    public let containerView = GeneralRowContainerView(frame: NSZeroRect)
    private let placeholderTextView = TextView()
    private let rightActionView: ImageButton = ImageButton()
    private var loadingView: ProgressIndicator? = nil
    private var placeholderAction: ImageButton?
    public let textView: TGModernGrowingTextView = TGModernGrowingTextView(frame: NSZeroRect, unscrollable: true)
    private let secureField: InputDataSecureField = InputDataSecureField(frame: NSMakeRect(0, 0, 100, 16))
    private let textLimitation: TextViewLabel = TextViewLabel(frame: NSMakeRect(0, 0, 16, 14))
    let separator = SimpleLayer()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        containerView.addSubview(placeholderTextView)
        containerView.addSubview(textView)
        containerView.addSubview(secureField)
        separator.anchorPoint = .zero
        separator.zPosition = 1
        containerView.layer?.addSublayer(separator)
        containerView.addSubview(textLimitation)
        containerView.addSubview(rightActionView)
        addSubview(containerView)
        rightActionView.autohighlight = false
        
        containerView.userInteractionEnabled = false
        
        textLimitation.alignment = .right
        
        
        
    //    textView.max_height = 34
      // .isSingleLine = true
        placeholderTextView.userInteractionEnabled = false
        placeholderTextView.isSelectable = false
        
        secureField.isBordered = false
        secureField.isBezeled = false
        secureField.focusRingType = .none
        secureField.drawsBackground = true
        secureField.isEditable = true
        secureField.isSelectable = true
        
        textView.max_height = 10000
        
        secureField.font = .normal(.text)
        secureField.textView?.insertionPointColor = theme.colors.text
        secureField.sizeToFit()
        
                
    }
    
    deinit {
    }
    
    open override func shakeView() {
        if !secureField.isHidden {
            secureField.shake()
            secureField.setSelectionRange(NSMakeRange(0, secureField.stringValue.length))
        }
        if !textView.isHidden {
            textView.shake()
            textView.setSelectedRange(NSMakeRange(0, textView.string().length))
        }
        let shakeOffset: CGFloat = 3
        self.separator.shake(0.04, from: NSMakePoint(self.separator.position.x - shakeOffset, self.separator.position.y), to: NSMakePoint(self.separator.position.x + shakeOffset, self.separator.position.y))
        NSSound.beep()
    }
    
    open override func hasFirstResponder() -> Bool {
        return true
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    open override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }
    
    open func canTransformInputText() -> Bool {
        guard let item = item as? InputDataRowItem else { return false }
        return item.canMakeTransformations
    }
    
    open func makeBold() {
        self.textView.boldWord()
    }
    open func makeUrl() {
        self.makeUrl(of: textView.selectedRange())
    }
    open func makeItalic() {
        self.textView.italicWord()
    }
    open func makeMonospace() {
        self.textView.codeWord()
    }

    open func makeUrl(of range: NSRange) {
        guard range.min != range.max, let window = window as? Window else {
            return
        }
        var effectiveRange:NSRange = NSMakeRange(NSNotFound, 0)
        let defaultTag: TGInputTextTag? = self.textView.attributedString().attribute(NSAttributedString.Key(rawValue: TGCustomLinkAttributeName), at: range.location, effectiveRange: &effectiveRange) as? TGInputTextTag
        
        
        let defaultUrl = defaultTag?.attachment as? String
        
        if effectiveRange.location == NSNotFound || defaultTag == nil {
            effectiveRange = range
        }
        
        showModal(with: InputURLFormatterModalController(string: self.textView.string().nsstring.substring(with: effectiveRange), defaultUrl: defaultUrl, completion: { [weak self] text, url in
            self?.textView.addLink(url, text: text, range: effectiveRange)
        }), for: window)
        
    }
    
    
    func changeSeparator(frame rect: NSRect, animated: Bool) {
        if rect.size != separator.frame.size {
            if animated {
                var from = separator.bounds
                if let presentation = separator.presentation(), separator.animation(forKey: "bounds") != nil {
                    from.size = presentation.bounds.size
                }
                separator.animateBounds(from: from, to: rect.size.bounds, duration: 0.2, timingFunction: .easeOut)
            } else {
                separator.removeAnimation(forKey: "bounds")
            }
            separator.frame.size = rect.size
        }
        if rect.origin != separator.frame.origin {
            if animated {
                var from = separator.frame.origin
                if let presentation = separator.presentation(), separator.animation(forKey: "position") != nil {
                    from = presentation.frame.origin
                }
                separator.animatePosition(from: from, to: rect.origin, duration: 0.2, timingFunction: .easeOut)
            } else {
                separator.removeAnimation(forKey: "position")
            }
            separator.frame.origin = rect.origin
        }
    }

    private var separatorFrame: NSRect {
        
        guard let item = item as? InputDataRowItem else { return NSZeroRect }
        
        switch item.viewType {
        case .legacy:
            if let placeholder = item.placeholder {
                if placeholder.drawBorderAfterPlaceholder {
                    return NSMakeRect(item.inset.left + item.textFieldLeftInset + 4, self.containerView.frame.height - .borderSize, self.containerView.frame.width - item.inset.left - item.inset.right - item.textFieldLeftInset - 4, .borderSize)
                } else {
                    return NSMakeRect(item.inset.left, self.containerView.frame.height - .borderSize, self.containerView.frame.width - item.inset.left - item.inset.right, .borderSize)
                }
            } else {
                return NSMakeRect(item.inset.left, self.containerView.frame.height - .borderSize, self.containerView.frame.width - item.inset.left - item.inset.right, .borderSize)
            }
        case let .modern(_, innerInsets):
            if let placeholder = item.placeholder {
                if placeholder.drawBorderAfterPlaceholder {
                    return NSMakeRect(innerInsets.left + item.textFieldLeftInset + 4, self.containerView.frame.height - .borderSize, self.containerView.frame.width - innerInsets.left - innerInsets.right - item.textFieldLeftInset - 4, .borderSize)
                } else {
                    return NSMakeRect(innerInsets.left, self.containerView.frame.height - .borderSize, self.containerView.frame.width - innerInsets.left - innerInsets.right, .borderSize)
                }
            } else {
                return NSMakeRect(innerInsets.left, self.containerView.frame.height - .borderSize, self.containerView.frame.width - innerInsets.left - innerInsets.right, .borderSize)
            }
        }
    }
    
    open override func layout() {
        super.layout()
        guard let item = item as? InputDataRowItem else {return}
        
        switch item.viewType {
        case .legacy:
            self.containerView.frame = bounds
            placeholderTextView.setFrameOrigin(item.inset.left, 14)
            placeholderAction?.setFrameOrigin(item.inset.left, 9)
            
            separator.frame = separatorFrame

            if let rightItem = item.rightItem {
                switch rightItem {
                case .action, .actionWithLoading:
                    rightActionView.setFrameOrigin(NSMakePoint(self.containerView.frame.width - rightActionView.frame.width - item.inset.right + 4, 14))
                case .loading, .media:
                    break
                }
            }
            
            secureField.setFrameSize(NSMakeSize(self.containerView.frame.width - item.inset.left - item.inset.right - item.textFieldLeftInset - item.additionRightInset, item.inputHeight))
            secureField.setFrameOrigin(item.inset.left + item.textFieldLeftInset, 14)
            
            textView.setFrameSize(NSMakeSize(self.containerView.frame.width - item.inset.left - item.inset.right - item.textFieldLeftInset - item.additionRightInset, item.inputHeight))
            textView.setFrameOrigin(item.inset.left + item.textFieldLeftInset - 3, 6)
            
            textLimitation.setFrameOrigin(NSMakePoint(self.containerView.frame.width - item.inset.right - textLimitation.frame.width + 4, self.containerView.frame.height - textLimitation.frame.height - 4))
        case let .modern(position, innerInsets):
            self.containerView.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - item.blockWidth) / 2), item.inset.top, item.blockWidth, frame.height - item.inset.bottom - item.inset.top)
         
            self.separator.isHidden = !position.border
            
            let textX = innerInsets.left + item.textFieldLeftInset - 3
            
            placeholderTextView.setFrameOrigin(NSMakePoint(innerInsets.left, innerInsets.top))
            if item.placeholder?.centersIconVertically == true {
                placeholderAction?.centerY(x: innerInsets.left)
            } else {
                placeholderAction?.setFrameOrigin(NSMakePoint(innerInsets.left, innerInsets.top - 5))
            }
            
            separator.frame = separatorFrame
        
            
            if let rightItem = item.rightItem {
                switch rightItem {
                case .action:
                    if item.realInputHeight <= 22 {
                        rightActionView.centerY(x: self.containerView.frame.width - rightActionView.frame.width - innerInsets.right)
                    } else {
                        rightActionView.setFrameOrigin(NSMakePoint(self.containerView.frame.width - rightActionView.frame.width - innerInsets.right, innerInsets.top))
                    }
                case .loading:
                    if let loadingView = loadingView  {
                        if item.realInputHeight <= 16 {
                            loadingView.centerY(x: self.containerView.frame.width - loadingView.frame.width - innerInsets.right)
                        } else {
                            loadingView.setFrameOrigin(NSMakePoint(self.containerView.frame.width - loadingView.frame.width - innerInsets.right, innerInsets.top))
                        }
                    }
                case .actionWithLoading:
                    if item.realInputHeight <= 22 {
                        rightActionView.centerY(x: self.containerView.frame.width - rightActionView.frame.width - innerInsets.right)
                    } else {
                        rightActionView.setFrameOrigin(NSMakePoint(self.containerView.frame.width - rightActionView.frame.width - innerInsets.right, innerInsets.top))
                    }
                    if let loadingView = loadingView {
                        loadingView.setFrameOrigin(NSMakePoint(rightActionView.frame.midX - loadingView.frame.width / 2, rightActionView.frame.midY - loadingView.frame.height / 2))
                    }
                case .media:
                    break
                }
            }
            
            
            secureField.setFrameSize(NSMakeSize(item.blockWidth - innerInsets.left - innerInsets.right - item.textFieldLeftInset - item.additionRightInset, item.inputHeight))
            secureField.setFrameOrigin(innerInsets.left + item.textFieldLeftInset + 1, innerInsets.top)
            
            textView.setFrameSize(NSMakeSize(item.blockWidth - innerInsets.left - innerInsets.right - item.textFieldLeftInset - item.additionRightInset, item.inputHeight))
            
            if item.realInputHeight <= 16 {
                textView.setFrameOrigin(textX, innerInsets.top - 8)
            } else {
                textView.setFrameOrigin(textX, innerInsets.top )
            }
            
            textLimitation.setFrameOrigin(NSMakePoint(item.blockWidth - innerInsets.right - textLimitation.frame.width, self.containerView.frame.height - innerInsets.bottom - textLimitation.frame.height))

            
        }
    }
    
    public func maxCharactersLimit(_ textView: TGModernGrowingTextView!) -> Int32 {
        if let item = item as? InputDataRowItem {
            if item.hasTextLimitation {
                return 10000
            } else {
                return item.limit
            }
        }
        return 100000
    }
    
    open func textViewDidReachedLimit(_ textView: Any) {
        if let item = item as? InputDataRowItem {
            switch item.mode {
            case .plain:
                if self.textView.selectedRange().max == self.textView.string().length {
                    self.textView.shake()
                }
            case .secure:
                self.secureField.shake()
            }
        }
        
    }
    
    open override func draw(_ layer: CALayer, in ctx: CGContext) {
        
    }
    
    open func textViewDidPaste(_ pasteboard: NSPasteboard) -> Bool {
        if let item = item as? InputDataRowItem, let pasteFilter = item.pasteFilter {
            if let string = pasteboard.string(forType: .string)?.trimmed {
                let value = pasteFilter(string)
                let updatedText = item.filter(value.1)
                if value.0 {
                    switch item.mode {
                    case .plain:
                        textView.setString(updatedText)
                    case .secure:
                        secureField.stringValue = updatedText
                    }
                } else {
                    switch item.mode {
                    case .plain:
                        textView.appendText(updatedText)
                    case .secure:
                        secureField.stringValue = secureField.stringValue + updatedText
                    }
                }
                return true
            }
            
        }
        return false
    }
    
    open func textViewHeightChanged(_ height: CGFloat, animated: Bool) {
        
        if let item = item as? InputDataRowItem, let table = item.table {
            item.inputHeight = height
            
            
            item.calculateHeight()
            
            table.reloadData(row: item.index, animated: animated)
        }
        
    }
    
    open func textViewSize(_ textView: TGModernGrowingTextView!) -> NSSize {
        return textView.frame.size
    }
    
    open func textViewEnterPressed(_ event:NSEvent) -> Bool {
        if InputDataUIHooks.shared.checkSendingAbility(event) {
            return true
        }
        return false
    }
    
    open func textViewIsTypingEnabled() -> Bool {
        return true
    }
    
    open func textViewNeedClose(_ textView: Any) {
        
    }
    
    public func textViewAllowsReplacementText(_ replacementText: String) -> Bool {
        return (item as? InputDataRowItem)?.allowsReplacementText?(replacementText) ?? true
    }

    open func textViewTextDidChange(_ string: String) {
        if let item = item as? InputDataRowItem {
            let updated = item.filter(string)
            if updated != string {
                textView.setString(updated, animated: true)
                if let shouldShake = item.shouldShakeOnFilterCorrection {
                    textView.setSelectedRange(NSRange(location: updated.utf16.count, length: 0))
                    item.currentText = textView.attributedString()
                    if shouldShake(string) {
                        textView.shake(beep: false)
                    }
                }
            } else {
                item.currentText = textView.attributedString()
            }
            let prevInputHeight = item.realInputHeight
            let prevHeight = item.inputHeight
            item.calculateHeight()
            if prevInputHeight != item.realInputHeight && prevHeight == item.inputHeight {
                textViewHeightChanged(item.inputHeight, animated: true)
            }
            containerView.needsDisplay = true
        }
    }
    
    
    open func controlTextDidChange(_ obj: Notification) {
        if let item = item as? InputDataRowItem {
            let string = secureField.stringValue
            let updated = item.filter(string)
            if updated != string {
                secureField.stringValue = updated
            } else {
                item.currentText = .initialize(string: updated, color: theme.colors.text, font: .normal(.text))
            }
            let prevInputHeight = item.realInputHeight
            item.calculateHeight()
            if prevInputHeight != item.realInputHeight {
                textViewHeightChanged(item.inputHeight, animated: true)
            }
            containerView.needsDisplay = true
        }
    }
    
    open func textViewTextDidChangeSelectedRange(_ range: NSRange) {
        if let item = item as? InputDataRowItem {
            if let defaultText = item.defaultText {
                if range.min < defaultText.length {
                    self.textView.setSelectedRange(NSMakeRange(textView.attributedString().range.max, 0))
                }
            }
            if item.currentText != textView.attributedString(), !textView.inputView.hasMarkedText() {
                item.currentText = textView.attributedString()
            }
        }
    }
    
//    func textViewDidPaste(_ pasteboard: NSPasteboard) -> Bool {
//        if let item = item as? InputDataRowItem, let string = pasteboard.string(forType: .string) {
//            let updated = item.filter(string)
//            if updated == string {
//                return false
//            } else {
//                NSSound.beep()
//                shakeView()
//            }
//        }
//        return true
//    }
    
    open override var backdorColor: NSColor {
        if let item = item as? GeneralRowItem, let customTheme = item.customTheme {
            return customTheme.backgroundColor
        }
        return theme.colors.background
    }
    
    open var textColor: NSColor {
        if let item = item as? GeneralRowItem, let customTheme = item.customTheme {
            return customTheme.textColor
        }
        return theme.colors.text
    }
    open var linkColor: NSColor {
        if let item = item as? GeneralRowItem, let customTheme = item.customTheme {
            return customTheme.accentColor
        }
        return theme.colors.accent
    }
    open var grayText: NSColor {
        if let item = item as? GeneralRowItem, let customTheme = item.customTheme {
            return customTheme.grayTextColor
        }
        return theme.colors.grayText
    }
    open var redColor: NSColor {
        if let item = item as? GeneralRowItem, let customTheme = item.customTheme {
            return customTheme.redColor
        }
        return theme.colors.redUI
    }
    open override var borderColor: NSColor {
        if let item = item as? GeneralRowItem, let customTheme = item.customTheme {
            return customTheme.borderColor
        }
        return theme.colors.border
    }
    
    open var indicatorColor: NSColor {
        if let item = item as? GeneralRowItem, let customTheme = item.customTheme {
            return customTheme.indicatorColor
        }
        return theme.colors.indicatorColor
    }
    
    open override func updateColors() {
        placeholderTextView.backgroundColor = backdorColor
        textView.cursorColor = theme.colors.indicatorColor
        textView.textFont = .normal(.text)
        textView.textColor = textColor
        textView.linkColor = linkColor

        textView.setBackgroundColor(backdorColor)
        secureField.font = .normal(13)
        secureField.backgroundColor = backdorColor
        secureField.textColor = textColor
        separator.backgroundColor = borderColor.cgColor
        containerView.backgroundColor = backdorColor
        loadingView?.progressColor = grayText
        guard let item = item as? InputDataRowItem else {
            return
        }
        self.background = item.viewType.rowBackground
    }
    
 
    open override var mouseInsideField: Bool {
        return secureField._mouseInside() || textView._mouseInside()
    }
    
    open override func hitTest(_ point: NSPoint) -> NSView? {
//        switch true {
//        case NSPointInRect(convert(point, from: superview), secureField.frame):
//            return secureField
//        case NSPointInRect(convert(point, from: superview), textView.frame):
//            return textView
//        default:
            return super.hitTest(point)
        //}
    }
    
    open override var firstResponder: NSResponder? {
        if let item = item as? InputDataRowItem {
            switch item.mode {
            case .plain:
                return textView.inputView
            case .secure:
                return secureField
            }
        }
        return super.firstResponder
    }
    
    open func showPlaceholderActionTooltip(_ text: String) -> Void {
        if let placeholderAction = placeholderAction {
            tooltip(for: placeholderAction, text: text)
        }
    }
    
    open override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            self.secureField.delegate = self
            self.textView.delegate = self
        } else {
            self.secureField.delegate = self
            self.textView.delegate = self
        }
    }
    
    open override func set(item: TableRowItem, animated: Bool) {
        
        guard let item = item as? InputDataRowItem else {return}
        
        self.textView.animates = false
        super.set(item: item, animated: animated)
        self.textView.animates = true

        
        placeholderTextView.isHidden = item.placeholderLayout == nil
        placeholderTextView.update(item.placeholderLayout)
        
        let containerRect: NSRect
        switch item.viewType {
        case .legacy:
            containerRect = self.bounds
        case .modern:
            containerRect = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - item.blockWidth) / 2), item.inset.top, item.blockWidth, item.height - item.inset.bottom - item.inset.top)
        }
        containerView.change(size: containerRect.size, animated: animated, corners: item.viewType.corners)
        containerView.change(pos: containerRect.origin, animated: animated)

        if let rightItem = item.rightItem {
            switch rightItem {
            case let .action(image, action):
                rightActionView.set(image: image, for: .Normal)
                rightActionView.setAccessibilityLabel(rightActionAccessibilityLabel(action))
                _ = rightActionView.sizeToFit()
                rightActionView.isHidden = false
                loadingView?.removeFromSuperview()
                loadingView = nil
                rightActionView.removeAllHandlers()
                switch action {
                case .none:
                    rightActionView.userInteractionEnabled = false
                    rightActionView.autohighlight = false
                case .resort:
                    rightActionView.userInteractionEnabled = false
                    rightActionView.autohighlight = false
                case .clearText:
                    rightActionView.userInteractionEnabled = true
                    rightActionView.autohighlight = true
                    rightActionView.set(handler: { [weak self] _ in
                        self?.secureField.stringValue = ""
                        self?.textView.setString("")
                    }, for: .Click)
                case let .custom(action):
                    rightActionView.userInteractionEnabled = true
                    rightActionView.autohighlight = true
                    rightActionView.set(handler: { control in
                        action(item, control)
                    }, for: .Click)
                }
            case .loading:
                if loadingView == nil {
                    var origin = NSPoint.zero
                    if case let .modern(_, innerInsets) = item.viewType {
                        if item.realInputHeight <= 16 {
                            origin = NSMakePoint(self.containerView.frame.width - 18 - innerInsets.right, (self.containerView.frame.height - 18) / 2)
                        } else {
                            origin = NSMakePoint(self.containerView.frame.width - 18 - innerInsets.right, innerInsets.top)
                        }
                    } else {
                        origin = NSMakePoint(self.containerView.frame.width - 18 - item.inset.right, 14)
                    }
                    loadingView = ProgressIndicator(frame: NSMakeRect(origin.x, origin.y, 18, 18))
                    loadingView?.progressColor = self.grayText
                    containerView.addSubview(loadingView!)
                }
                rightActionView.isHidden = true
            case let .actionWithLoading(image, action):
                rightActionView.set(image: image, for: .Normal)
                rightActionView.setAccessibilityLabel(rightActionAccessibilityLabel(action))
                _ = rightActionView.sizeToFit()
                rightActionView.isHidden = false
                if loadingView == nil {
                    let origin = NSMakePoint(rightActionView.frame.midX - 9, rightActionView.frame.midY - 9)
                    loadingView = ProgressIndicator(frame: NSMakeRect(origin.x, origin.y, 18, 18))
                    loadingView?.progressColor = self.grayText
                    containerView.addSubview(loadingView!)
                }
                rightActionView.removeAllHandlers()
                switch action {
                case .none:
                    rightActionView.userInteractionEnabled = false
                    rightActionView.autohighlight = false
                case .resort:
                    rightActionView.userInteractionEnabled = false
                    rightActionView.autohighlight = false
                case .clearText:
                    rightActionView.userInteractionEnabled = true
                    rightActionView.autohighlight = true
                    rightActionView.set(handler: { [weak self] _ in
                        self?.secureField.stringValue = ""
                        self?.textView.setString("")
                    }, for: .Click)
                case let .custom(action):
                    rightActionView.userInteractionEnabled = true
                    rightActionView.autohighlight = true
                    rightActionView.set(handler: { control in
                        action(item, control)
                    }, for: .Click)
                }
            case .media:
                rightActionView.isHidden = true
                loadingView?.removeFromSuperview()
                loadingView = nil
            }
        } else {
            rightActionView.isHidden = true
            loadingView?.removeFromSuperview()
            loadingView = nil
        }
        
        if let placeholder = item.placeholder {
            if let icon = placeholder.icon {
                if placeholderAction == nil {
                    self.placeholderAction = ImageButton()
                    containerView.addSubview(self.placeholderAction!)
                    if animated {
                        placeholderAction!.layer?.animateAlpha(from: 0, to: 2, duration: 0.2)
                        changeSeparator(frame: separatorFrame, animated: animated)
                    }
                    
                    switch item.viewType {
                    case .legacy:
                        textView._change(pos: NSMakePoint(item.inset.left + item.textFieldLeftInset - 3, 6), animated: animated)
                    case let .modern(_, innerInsets):
                        let textX = innerInsets.left + item.textFieldLeftInset - 3
                        if item.realInputHeight <= 16 {
                            textView._change(pos: NSMakePoint(textX, textView.frame.minY), animated: animated)
                        } else {
                            textView._change(pos: NSMakePoint(textX, textView.frame.minY), animated: animated)
                        }
                    }
                    
                }
                guard let placeholderAction = self.placeholderAction else {
                    return
                }
                placeholderAction.set(image: icon, for: .Normal)
                placeholderAction.setAccessibilityLabel(placeholder.placeholder)
                placeholderAction.set(image: icon, for: .Highlight)
                placeholderAction.set(image: icon, for: .Hover)
                _ = placeholderAction.sizeToFit()
                placeholderAction.removeAllHandlers()
                placeholderAction.set(handler: { _ in
                    placeholder.action?()
                }, for: .SingleClick)
            } else {
                if animated {
                    if let placeholderAction = placeholderAction {
                        self.placeholderAction = nil
                        placeholderAction.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak placeholderAction] _ in
                            placeholderAction?.removeFromSuperview()
                        })
                        changeSeparator(frame: separatorFrame, animated: animated)
                    }
                } else {
                    placeholderAction?.removeFromSuperview()
                    placeholderAction = nil
                }
                
                switch item.viewType {
                case .legacy:
                    textView._change(pos: NSMakePoint(item.inset.left + item.textFieldLeftInset - 3, 6), animated: animated)
                case let .modern(_, innerInsets):
                    let textX = innerInsets.left + item.textFieldLeftInset - 3
                    if item.realInputHeight <= 16 {
                        textView._change(pos: NSMakePoint(textX, textView.frame.minY), animated: animated)
                    } else {
                        textView._change(pos: NSMakePoint(textX, textView.frame.minY), animated: animated)
                    }
                }
            }
            
            
        } else {
            if animated {
                if let placeholderAction = placeholderAction {
                    self.placeholderAction = nil
                    placeholderAction.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak placeholderAction] _ in
                        placeholderAction?.removeFromSuperview()
                    })
                    changeSeparator(frame: separatorFrame, animated: animated)
                }
            } else {
                placeholderAction?.removeFromSuperview()
                placeholderAction = nil
            }
            
           
            
            switch item.viewType {
            case .legacy:
                textView._change(pos: NSMakePoint(item.inset.left + item.textFieldLeftInset - 3, 6), animated: animated)
            case let .modern(_, innerInsets):
                let textX = innerInsets.left + item.textFieldLeftInset - 3
                if item.realInputHeight <= 16 {
                    textView._change(pos: NSMakePoint(textX, textView.frame.minY), animated: animated)
                } else {
                    textView._change(pos: NSMakePoint(textX, textView.frame.minY), animated: animated)
                }
            }
        }
        
        if item.hasTextLimitation {
            textLimitation.isHidden = item.currentText.length < item.limit / 3 * 2 || item.currentText.length == item.limit
            let color: NSColor = item.currentText.length > item.limit ? self.redColor : self.grayText
            textLimitation.attributedString = .initialize(string: "\(item.limit - Int32(item.currentText.length))", color: color, font: .normal(.small))
            textLimitation.sizeToFit()
        } else {
            textLimitation.isHidden = true
        }
        
        switch item.mode {
        case .plain:
            secureField.isHidden = true
            textView.isHidden = false
            textView.animates = false
            textView.setPlaceholderAttributedString(item.inputPlaceholder, update: false)
            if item.currentAttributed != textView.attributedString() {
                textView.setAttributedString(item.currentAttributed, animated: false)
            }
            textView.update(false)
            textView.needsDisplay = true
            textView.animates = true
        case .secure:
            secureField.placeholderAttributedString = item.inputPlaceholder
            secureField.isHidden = false
            
            textView.isHidden = true
            if item.currentText.string != secureField.stringValue {
                secureField.stringValue = item.currentText.string
            }
        }
        
        containerView.needsDisplay = true
        self.needsLayout = true

    }
    
    open override func selectAll(_ sender: Any?) {
        self.textView.setSelectedRange(NSMakeRange(0, self.textView.string().length))
    }
}

private func rightActionAccessibilityLabel(_ action: InputDataRightItemAction) -> String? {
    switch action {
    case .clearText:
        return strings().voiceOverCommonClear
    case .resort:
        return strings().voiceOverCommonReorder
    default:
        return nil
    }
}
