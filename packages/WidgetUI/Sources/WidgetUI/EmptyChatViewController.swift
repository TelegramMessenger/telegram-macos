import Cocoa
import TGUIKit
import TelegramCore

import SwiftSignalKit
import InAppSettings
import Localization
import TelegramTheme
import TelegramIconsTheme
import TelegramContext
import TelegramUtils



public class EmptyChatView : View {
    private let containerView: View = View()
    private let label:TextView = TextView()
    private let imageView:ImageView = ImageView()
    
    public let toggleTips: ImageButton = ImageButton()

    private var navigationOverflow: CGFloat = 0
    
    private var cards: NSView?
    
    public func toggleTips(_ isEnabled: Bool, animated: Bool, view: NSView) {
        if isEnabled {
            addSubview(view)
            self.cards = view
            view.frame = NSMakeRect(0, 0, frame.width, 370)
            view.center()
            if animated {
                view.layer?.animateAlpha(from: 0, to: 1, duration: 0.3, timingFunction: .spring)
                view.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.3)
            }
        } else {
            performSubviewRemoval(view, animated: animated, duration: 0.3, timingFunction: .spring, checkCompletion: true)
            if animated {
                view.layer?.animateScaleSpring(from: 1, to: 0.1, duration: 0.3, bounce: false)
            }

            self.cards = nil
        }
        containerView.change(opacity: isEnabled ? 0 : 1, animated: animated)
        toggleTips.set(image: self.cards == nil ? TelegramThemeHooks.shared.image(.iconEmptyShowTips).precomposed(theme.colors.text) : theme.icons.glass_close, for: .Normal)
        updateToggleTipsAccessibility()

        
    }
    
    private func updateToggleTipsAccessibility() {
        if cards == nil {
            toggleTips.setAccessibilityLabel(strings().voiceOverCommonShowTips)
        } else {
            toggleTips.setAccessibilityLabel(strings().voiceOverCommonClose)
        }
    }
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.layer = CAGradientLayer()
        self.layer?.disableActions()
        
        toggleTips.set(image: theme.icons.glass_close, for: .Normal)
        toggleTips.setGlassEffect(size: NSMakeSize(40, 40))
        toggleTips.sizeToFit(.zero, NSMakeSize(40, 40), thatFit: true)

        toggleTips.autohighlight = false
        toggleTips.scaleOnClick = true

        addSubview(containerView)
        containerView.addSubview(imageView)
        containerView.addSubview(label)
        imageView.isAccessibilityDecorative = true
        addSubview(toggleTips)
        label.userInteractionEnabled = false
        label.isSelectable = false
        updateLocalizationAndTheme(theme: theme)
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)
        imageView.image = theme.icons.chatEmpty
        switch theme.controllerBackgroundMode {
        case .plain:
            imageView.isHidden = false
        default:
            imageView.isHidden = true
        }
        
        toggleTips.set(image: cards == nil ? TelegramThemeHooks.shared.image(.iconEmptyShowTips).precomposed(theme.colors.text) : theme.icons.glass_close, for: .Normal)
        updateToggleTipsAccessibility()


        imageView.sizeToFit()
        label.disableBackgroundDrawing = true
        if imageView.isHidden && theme.bubbled {
            label.blurBackground = theme.chatServiceItemColor
        } else {
            label.blurBackground = nil
            label.backgroundColor = theme.chatBackground
        }

        label.update(TextViewLayout(.initialize(string: strings().emptyPeerDescription, color: imageView.isHidden ? theme.chatServiceItemTextColor : theme.colors.grayText, font: .medium(imageView.isHidden ? .text : .header)), maximumNumberOfLines: 1, alignment: .center))
        needsLayout = true
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        label.textLayout?.measure(width: frame.size.width - 20)
        label.update(label.textLayout)
        
        cards?.frame = NSMakeRect(0, 0, frame.width, 370)
        cards?.center()
        
        
        
        if imageView.isHidden {
            
            label.setFrameSize(label.frame.width + 16, label.frame.height + 6)
            
            containerView.setFrameSize(label.frame.width + 20, 24)
            containerView.center()
            label.center()
            label.layer?.cornerRadius = label.frame.height / 2
            containerView.layer?.cornerRadius = containerView.frame.height / 2
        } else {
            containerView.setFrameSize(max(imageView.frame.width, label.frame.width) + 40, imageView.frame.size.height + label.frame.size.height + 70)
            imageView.centerX(y: 20)
            containerView.center()
            label.centerX(y: imageView.frame.maxY + 30)
            containerView.layer?.cornerRadius = 0
        }
        
        let edge = EmptyChatView.edgeInset
        toggleTips.setFrameOrigin(NSMakePoint(frame.width - toggleTips.frame.width - edge, edge + navigationOverflow))
    }

    private static let edgeInset: CGFloat = System.windowEdgeInset

    public func updateNavigationOverflow(_ overflow: CGFloat, transition: ContainedViewLayoutTransition) {
        guard navigationOverflow != overflow else {
            return
        }
        navigationOverflow = overflow
        let edge = EmptyChatView.edgeInset
        let origin = NSMakePoint(frame.width - toggleTips.frame.width - edge, edge + overflow)
        transition.updateFrame(view: toggleTips, frame: CGRect(origin: origin, size: toggleTips.frame.size))
    }
}

open class EmptyChatViewController<Context: AccountContextProtocol>: TelegramGenericViewController<EmptyChatView, Context> {
    
    open override var defaultBarTitle: String {
        return localizedString("Telegram.EmptyChatViewController")
    }
    
    private let cards: WidgetController<Context>
    public override var wantsContainerGlass: Bool {
        return false
    }

    public override init(_ context: Context) {
        cards = WidgetController(context)
        super.init(context)
        self.bar = NavigationBarStyle(height:0)
        self.insets = NSEdgeInsets()
    }

    
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }
    
    public override func escapeKeyAction() -> KeyHandlerResult {
        return .rejected
    }

    public override func updateNavigationHeaderOverflow(_ overflow: CGFloat, transition: ContainedViewLayoutTransition) {
        super.updateNavigationHeaderOverflow(overflow, transition: transition)
        if isLoaded() {
            genericView.updateNavigationOverflow(overflow, transition: transition)
        }
    }
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)
        self.backgroundColor = .clear
        self.cards.updateLocalizationAndTheme(theme: theme)
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public override func updateBackgroundColor(_ backgroundMode: TableBackgroundMode) {
        super.updateBackgroundColor(backgroundMode)
        
    }
    
    override public var isOpaque: Bool {
        return false
    }
    
    public override var responderPriority: HandlerPriority {
        return .medium
    }
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let context = self.context
        context.globalPeerHandler.set(.single(nil))
        
        window?.set(handler: { _ in
            context.bindings.globalSearch("", nil, nil)
            return .invoked
        }, with: self, for: .F, priority: .modal, modifierFlags: [.command])
    }
    
    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        window?.removeAllHandlers(for: self)
    }
    
    public override func backKeyAction() -> KeyHandlerResult {
        return cards.backKeyAction()
    }
    public override func nextKeyAction() -> KeyHandlerResult {
        return cards.nextKeyAction()
    }
    
    private let disposable = MetaDisposable()
    
    deinit {
        disposable.dispose()
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        self.ready.set(cards.ready.get())
        
        
        self.genericView.toggleTips(FastSettings.emptyTips, animated: false, view: cards.view)
        
        self.genericView.toggleTips.set(handler: { [weak self] _ in
            guard let cards = self?.cards.view else {
                return
            }
            FastSettings.updateEmptyTips(!FastSettings.emptyTips)
            self?.genericView.toggleTips(FastSettings.emptyTips, animated: true, view: cards)
        }, for: .Click)
    }
    
    
    
    public override var window: Window? {
        return context.window
    }
}
