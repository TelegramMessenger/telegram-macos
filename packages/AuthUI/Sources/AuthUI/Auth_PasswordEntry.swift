import Foundation
import TGUIKit
import AppKit
import TelegramCore
import TelegramMedia
import FilePanels
import PhoneNumberUtils
import LocalAnimations
import TelegramContext
import TelegramTheme
import Localization
import TelegramUtils

private final class Auth_PasswordEntryHeaderView : View {
    private let playerView:LottiePlayerView = LottiePlayerView()
    private let header: TextView = TextView()
    private let desc: TextView = TextView()
    private var descAttr: NSAttributedString?
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(playerView)
        addSubview(header)
        addSubview(desc)
        header.userInteractionEnabled = false
        header.isSelectable = false
        
        desc.userInteractionEnabled = false
        desc.isSelectable = false
        
        updateLocalizationAndTheme(theme: theme)
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = theme as! TelegramPresentationTheme
        if let data = LocalAnimatedSticker.keychain.data {
            self.playerView.set(LottieAnimation(compressed: data, key: .init(key: .bundle("keychain"), size: Auth_Insets.logoSize, backingScale: Int(System.backingScale), fitzModifier: nil, colors: []), playPolicy: .onceEnd))
        }
        
        let layout = TextViewLayout(.initialize(string: strings().loginNewPasswordLabel, color: theme.colors.text, font: Auth_Insets.headerFont))
        layout.measure(width: frame.width)
        self.header.update(layout)
        
        let descAttr: NSAttributedString = .initialize(string: strings().loginNewPasswordInfo, color: theme.colors.grayText, font: Auth_Insets.infoFont)
        
        let descLayout = TextViewLayout(descAttr, alignment: .center)
        descLayout.measure(width: frame.width)
        self.desc.update(descLayout)
        
        self.layout()
    }
    
    public override func layout() {
        super.layout()
        self.playerView.setFrameSize(Auth_Insets.logoSize)
        self.playerView.centerX(y: 0)
        self.header.centerX(y: self.playerView.frame.maxY + 20)
        self.desc.centerX(y: self.header.frame.maxY + 10)

    }
    
    public var height: CGFloat {
        return self.desc.frame.maxY
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func playAnimation() {
        playerView.playAgain()
    }
}

private final class Auth_PasswordEntryInputView : View, NSTextFieldDelegate {
    private let secureField: NSSecureTextField = NSSecureTextField()
    private let plainField: NSTextField = NSTextField()
    private let revealButton: ImageButton = ImageButton()
    private var isRevealed: Bool = false
    private var hint: String?
    private var takeError: (()->Void)?
    private var invoke:(()->Void)?
    private let revealButtonSize: CGFloat = 28
    
    private var activeField: NSTextField {
        return isRevealed ? plainField : secureField
    }
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(secureField)
        addSubview(plainField)
        addSubview(revealButton)
        plainField.isHidden = true
        revealButton.autohighlight = false
        revealButton.scaleOnClick = true
        revealButton.set(handler: { [weak self] _ in
            self?.toggleReveal()
        }, for: .Click)
        updateLocalizationAndTheme(theme: theme)
    }
    
    private func configure(_ field: NSTextField, theme: PresentationTheme) {
        field.font = .normal(.title)
        field.textColor = theme.colors.text
        field.drawsBackground = false
        field.backgroundColor = .clear
        field.focusRingType = .none
        field.isBordered = false
        field.usesSingleLineMode = true
        field.isBezeled = false
        field.delegate = self
        if #available(macOS 11.0, *) {
            field.contentType = .password
        }
        let hint = self.hint ?? ""
        field.placeholderAttributedString = .initialize(string: hint.isEmpty ? strings().loginNewPasswordPlaceholder : hint, color: theme.colors.grayText, font: .normal(.text))
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        background = theme.colors.grayBackground
        layer?.cornerRadius = 10
        
        configure(secureField, theme: theme)
        configure(plainField, theme: theme)
        
        let icon = NSImage(named: isRevealed ? "Icon_Eye_On" : "Icon_Eye_Off")?.precomposed(theme.colors.grayIcon)
        if let icon = icon {
            revealButton.set(image: icon, for: .Normal)
        }
        revealButton.setFrameSize(NSMakeSize(revealButtonSize, revealButtonSize))
        revealButton.setAccessibilityLabel(isRevealed ? strings().voiceOverCommonHide : strings().voiceOverCommonShow)
    }
    
    private func toggleReveal() {
        let previous = activeField
        let editor = previous.currentEditor()
        let hadFocus = editor != nil
        let selection = editor?.selectedRange ?? NSMakeRange(previous.stringValue.length, 0)
        
        isRevealed.toggle()
        
        let next = activeField
        next.stringValue = previous.stringValue
        previous.stringValue = ""
        previous.isHidden = true
        next.isHidden = false
        updateLocalizationAndTheme(theme: theme)
        
        if hadFocus {
            window?.makeFirstResponder(next)
            next.setSelectionRange(selection)
        }
        needsLayout = true
    }
    
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            self.invoke?()
            return true
        }
        return false
    }
    
    public func controlTextDidChange(_ obj: Notification) {
        self.takeError?()
    }
    
    public func update(locked: Bool, hint: String?, invoke: @escaping()->Void, takeError:@escaping()->Void) {
        self.hint = hint
        self.invoke = invoke
        self.takeError = takeError
        updateLocalizationAndTheme(theme: theme)
    }
    
    public override func layout() {
        super.layout()
        let fieldWidth = frame.width - 20 - revealButtonSize
        secureField.frame = NSMakeRect(10, 10, fieldWidth, 18)
        plainField.frame = secureField.frame
        revealButton.setFrameOrigin(NSMakePoint(frame.width - revealButtonSize - 6, floorToScreenPixels((frame.height - revealButtonSize) / 2)))
    }
    
    public func updateLocked(_ locked: Bool) {
        self.secureField.textView?.isEditable = !locked
        self.plainField.textView?.isEditable = !locked
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    public func firstResponder() -> NSResponder? {
        let field = activeField
        if window?.firstResponder == field.textView {
            return field.textView
        }
        return field
    }
    public var value: String {
        return self.activeField.stringValue
    }
}

public final class Auth_PasswordEntryView: View {
    private let container: View = View()
    private let header:Auth_PasswordEntryHeaderView
    private let input:Auth_PasswordEntryInputView
    private let nextView = Auth_NextView()
    private let error: LoginErrorStateView = LoginErrorStateView()
    private let forgot: TextView = TextView()
    private var locked: Bool = false
    private var takeReset: Bool = false {
        didSet {
            updateLocalizationAndTheme(theme: theme)
        }
    }
    
    private var takeNext:((String)->Void)?
    private var takeForgot:((Bool, @escaping()->Void)->Void)?
    public required init(frame frameRect: NSRect) {
        header = Auth_PasswordEntryHeaderView(frame: frameRect.size.bounds)
        input = Auth_PasswordEntryInputView(frame: NSMakeRect(0, 0, 280, 40))
        super.init(frame: frameRect)
        container.addSubview(header)
        container.addSubview(input)
        container.addSubview(nextView)
        container.addSubview(error)
        container.addSubview(forgot)

        forgot.isSelectable = false
        addSubview(container)
        nextView.set(handler: { [weak self] _ in
            self?.invoke()
        }, for: .Click)
        
        updateLocalizationAndTheme(theme: theme)
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        nextView.updateLocalizationAndTheme(theme: theme)
        
        let attr = NSMutableAttributedString()
        _ = attr.append(string: takeReset ? strings().loginResetAccountText : strings().loginPasswordForgot, color: takeReset ? theme.colors.redUI : theme.colors.accent, font: .normal(.title))
        attr.addAttribute(.link, value: LinkHooks.shared.callbackLink("", { [weak self] _ in
            guard let takeReset = self?.takeReset else {
                return
            }
            self?.takeForgot?(takeReset, { [weak self] in
                self?.takeReset = true
            })
        }), range: attr.range)
        let layout = TextViewLayout(attr)
        layout.measure(width: .greatestFiniteMagnitude)
        layout.interactions = LinkHooks.shared.globalLinkExecutor()
        forgot.update(layout)
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        container.setFrameSize(NSMakeSize(frame.width, header.height + Auth_Insets.betweenHeader + input.frame.height + Auth_Insets.betweenNextView + Auth_Insets.nextHeight + Auth_Insets.betweenHeader + forgot.frame.height))
        
        header.setFrameSize(NSMakeSize(frame.width, header.height))
        header.centerX(y: 0)
        input.centerX(y: header.frame.maxY + Auth_Insets.betweenHeader)
        error.centerX(y: input.frame.maxY + Auth_Insets.betweenError)
        nextView.centerX(y: input.frame.maxY + Auth_Insets.betweenNextView)
        forgot.centerX(y: nextView.frame.maxY + Auth_Insets.betweenHeader)
        container.center()
        
    }
    
    public func invoke() {
        if !self.input.value.isEmpty, !locked {
            self.takeNext?(self.input.value)
        }
    }
    
    public func firstResponder() -> NSResponder? {
        return input.firstResponder()
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    public func update(locked: Bool, error: AuthorizationPasswordVerificationError?, hint: String?, takeNext: @escaping(String)->Void, takeError:@escaping()->Void, takeForgot:@escaping(Bool, @escaping()->Void)->Void) {
        self.input.update(locked: locked, hint: hint, invoke: { [weak self] in
            self?.invoke()
        }, takeError: takeError)
        self.takeNext = takeNext
        self.takeForgot = takeForgot
        self.locked = locked
        nextView.updateLocked(locked)
        self.input.updateLocked(locked)
        if let error = error {
            let text:String
            switch error {
            case .invalidPassword:
                text = strings().passwordHashInvalid
            case .limitExceeded:
                text = strings().loginFloodWait
            case .generic:
                text = "undefined error"
            }
            self.error.state.set(.error(text))
            self.input.shake(beep: true)
        } else {
            self.error.state.set(.normal)
        }
        needsLayout = true
    }
    
    public func playAnimation() {
        header.playAnimation()
    }
}

public final class Auth_PasswordEntryController : GenericViewController<Auth_PasswordEntryView> {
    
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        readyOnce()
    }
    
    public func update(locked: Bool, error: AuthorizationPasswordVerificationError?, hint: String?, takeNext: @escaping(String)->Void, takeError:@escaping()->Void, takeForgot:@escaping(Bool, @escaping()->Void)->Void) {
        self.genericView.update(locked: locked, error: error, hint: hint, takeNext: takeNext, takeError: takeError, takeForgot: takeForgot)
    }
    
    public override func firstResponder() -> NSResponder? {
        return genericView.firstResponder()
    }
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if animated {
            genericView.playAnimation()
        }
    }
}
