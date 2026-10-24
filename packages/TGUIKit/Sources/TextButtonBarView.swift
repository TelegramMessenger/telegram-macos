import Cocoa

open class TextButtonBarView: BarView {

    public static let pillHeight: CGFloat = 40
    private static let horizontalPad: CGFloat = 20

    public let button: TextButton = TextButton()
    private var progressIndicator: ProgressIndicator?
    private weak var progressAnchor: NSView?
    private var _isFitted: Bool
    private var currentTexts: [ControlState: String] = [:]

    public init(controller: ViewController, text: String, style: ControlStyle = navigationButtonStyle, glassForceAppearance: LiquidGlassAppearance? = nil) {

        var pillStyle = style
        pillStyle.foregroundColor = presentation.colors.text
        button.autoSizeToFit = false
        button.set(font: pillStyle.font, for: .Normal)
        button.set(color: pillStyle.foregroundColor, for: .Normal)
        button.set(text: text, for: .Normal)
        button.set(background: .clear, for: .Normal)
        button.disableActions()

        _isFitted = false
        currentTexts[.Normal] = text
        super.init(controller: controller)

        self.style = pillStyle
        button.style = pillStyle

        self.addSubview(button)
        progressAnchor = button.subviews.last

        button.disableActions()
        button.animates = false
        button.scaleOnClick = true

        button.layer?.cornerRadius = TextButtonBarView.pillHeight / 2
        button.layer?.masksToBounds = true
        self.layer?.masksToBounds = false
        button.setGlassEffect(forceAppearance: glassForceAppearance)
        self.stretchReferenceView = button
        self.stretchTransformView = button
    }

    public var direction: TextButtonImageDirection = .left {
        didSet {
            button.direction = direction
        }
    }

    public func set(image: CGImage, for state: ControlState) -> Void {
        button.set(image: image, for: state)
        _isFitted = false
        (superview as? NavigationBarView)?.viewFrameChanged(Notification(name: NSView.frameDidChangeNotification))
    }

    public func set(color: NSColor, for state: ControlState) -> Void {
        _isFitted = false
        button.set(color: color, for: state)
    }

    public func set(font: NSFont, for state: ControlState) -> Void {
        button.set(font: font, for: state)
        _isFitted = false
        (superview as? NavigationBarView)?.viewFrameChanged(Notification(name: NSView.frameDidChangeNotification))
    }

    public func set(text: String, for state: ControlState) -> Void {
        if currentTexts[state] == text {
            return
        }
        currentTexts[state] = text
        if !isLoading {
            button.set(text: text, for: state)
        }
        _isFitted = false
        (superview as? NavigationBarView)?.viewFrameChanged(Notification(name: NSView.frameDidChangeNotification))
    }

    public func removeImage(for state: ControlState) {
        button.removeImage(for: state)
    }

    @discardableResult open override func set(handler: @escaping (Control) -> Void, for event: ControlEvent) -> UInt32 {
        return button.set(handler: handler, for: event)
    }

    @discardableResult open override func set(handler: @escaping (Control) -> Void, for state: ControlState) -> UInt32 {
        return button.set(handler: handler, for: state)
    }

    open override func removeAllHandlers() {
        button.removeAllHandlers()
    }

    open override func removeAllStateHandlers() {
        button.removeAllStateHandlers()
    }

    override var isFitted: Bool {
        return _isFitted
    }

    open override func fit(to maxWidth: CGFloat, transition: ContainedViewLayoutTransition = .immediate) -> CGFloat {
        let pad = TextButtonBarView.horizontalPad
        let pillHeight = TextButtonBarView.pillHeight
        let addition = NSMakeSize(pad, 0)
        _isFitted = button.sizeToFit(addition, NSMakeSize(maxWidth, pillHeight), thatFit: false, transition: transition)
        return max(button.frame.width, isLoading ? pillHeight : 0)
    }

    public override var style: ControlStyle {
        didSet {
            button.set(font: style.font, for: .Normal)
            set(color: style.foregroundColor, for: .Normal)
            button.style = style
        }
    }

    open override var isEnabled: Bool {
        didSet {
            button.isEnabled = isEnabled
        }
    }

    open var isLoading: Bool = false {
        didSet {
            guard isLoading != oldValue else {
                return
            }
            if isLoading {
                button.set(text: "", for: .Normal)
            } else {
                button.set(text: currentTexts[.Normal] ?? "", for: .Normal)
            }
            if isLoading {
                if progressIndicator == nil {
                    let indicator = ProgressIndicator(frame: NSMakeRect(0, 0, 18, 18))
                    if let anchor = progressAnchor, anchor.superview === button {
                        button.addSubview(indicator, positioned: .above, relativeTo: anchor)
                    } else {
                        button.addSubview(indicator)
                    }
                    progressIndicator = indicator
                }
            } else if let indicator = progressIndicator {
                indicator.removeFromSuperview()
                progressIndicator = nil
            }
            button.userInteractionEnabled = !isLoading
            _isFitted = false
            needsLayout = true
            superview?.needsLayout = true
        }
    }

    override open func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        button.set(color: presentation.colors.text, for: .Normal)
        button.set(background: .clear, for: .Normal)
        button.updateLocalizationAndTheme(theme: theme)
    }

    open override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }

    open override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        let pillHeight = TextButtonBarView.pillHeight
        let w = max(button.frame.width, isLoading ? pillHeight : 0)
        let btnSize = NSMakeSize(w, pillHeight)
        let x = floorToScreenPixels(backingScaleFactor, (size.width - w) / 2)
        let y = floorToScreenPixels(backingScaleFactor, (size.height - pillHeight) / 2)
        transition.updateFrame(view: button, frame: NSMakeRect(x, y, btnSize.width, btnSize.height))
        button.updateLayout(size: btnSize, transition: transition)
        progressIndicator?.center()
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required public init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

}
