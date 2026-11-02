import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import TelegramMediaUtils
import SecureIdUtils
import TelegramLinks
import PhoneNumberUtils
import KeyboardKey
import TGPassportMRZ
import OCR
import FilePanels
import ObjcUtils

private final class PassportInsertPasswordField : NSSecureTextField {
    
    override func resignFirstResponder() -> Bool {
        (self.delegate as? PassportInsertPasswordRowView)?.controlTextDidBeginEditing(Notification(name: NSControl.textDidChangeNotification))
        return super.resignFirstResponder()
    }
    
    override func becomeFirstResponder() -> Bool {
        (self.delegate as? PassportInsertPasswordRowView)?.controlTextDidEndEditing(Notification(name: NSControl.textDidChangeNotification))
        return super.becomeFirstResponder()
    }
    
    override func mouseDown(with event: NSEvent) {
        superview?.mouseDown(with: event)
    }
}

class PassportInsertPasswordItem: GeneralRowItem {
    static let margin: CGFloat = 30
    static let textInset: CGFloat = 20
    static let topPadding: CGFloat = 12
    static let fieldHeight: CGFloat = 40
    private let _stableId: AnyHashable
    fileprivate let descLayout: TextViewLayout
    fileprivate let checkPasswordAction:((String, ()->Void))->Void
    fileprivate let forgotPassword: ()->Void
    fileprivate let hasRecoveryEmail: Bool
    init(_ initialSize: NSSize, stableId: AnyHashable, checkPasswordAction: @escaping((String, ()->Void))->Void, forgotPassword: @escaping()->Void, hasRecoveryEmail: Bool, isSettings: Bool, error: String?) {
        self._stableId = stableId
        self.checkPasswordAction = checkPasswordAction
        self.forgotPassword = forgotPassword
        self.hasRecoveryEmail = hasRecoveryEmail
        descLayout = TextViewLayout(.initialize(string: error != nil ? error! : (isSettings ? strings().secureIdInsertPasswordSettingsDescription : strings().secureIdInsertPasswordDescription), color: error != nil ? theme.colors.redUI : theme.colors.grayText, font: .normal(.text)), alignment: .center)
        super.init(initialSize)
        _ = makeSize(initialSize.width, oldWidth: 0)
    }
    
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        descLayout.measure(width: width - PassportInsertPasswordItem.margin * 2 - PassportInsertPasswordItem.textInset * 2)
        
        return success
    }
    
    override var stableId: AnyHashable {
        return _stableId
    }
    
    override var instantlyResize: Bool {
        return true
    }
    
    override func viewClass() -> AnyClass {
        return PassportInsertPasswordRowView.self
    }
    
    override var height: CGFloat {
        return PassportInsertPasswordItem.topPadding + PassportInsertPasswordItem.fieldHeight + 12 + descLayout.layoutSize.height + 10 + 18 + 24 + PassportInsertPasswordItem.fieldHeight + 24
    }

    override var backdorColor: NSColor {
        return theme.colors.listBackground
    }

    override var accessibilityLabel: String? {
        return descLayout.attributedString.string
    }
}


final class PassportInsertPasswordRowView : GeneralRowView, NSTextFieldDelegate {
    let input:NSSecureTextField
    private let backdrop: View = View()
    private let inputContainer: View = View()
    private let descTextView: TextView = TextView()
    private let nextButton: TextButton = TextButton()
    private let forgotPassword: TextButton = TextButton()
    required init(frame frameRect: NSRect) {
        input = PassportInsertPasswordField(frame: NSZeroRect)
        super.init(frame: frameRect)
        input.stringValue = ""
        
        
        descTextView.userInteractionEnabled = false
        descTextView.isSelectable = false
        
        addSubview(backdrop)
        addSubview(inputContainer)

        input.wantsLayer = true
        input.isBordered = false
        input.isBezeled = false
        input.focusRingType = .none
        input.delegate = self
        input.drawsBackground = false
        input.isEditable = true
        input.isSelectable = true
        input.font = .normal(.text)
        inputContainer.backgroundColor = theme.colors.grayBackground
        inputContainer.layer?.cornerRadius = PassportInsertPasswordItem.fieldHeight / 2
        
        inputContainer.addSubview(input)
        
        
        input.target = self
        input.action = #selector(checkPasscode)
        
        addSubview(descTextView)
        addSubview(nextButton)
        addSubview(forgotPassword)
        forgotPassword.autohighlight = false
        forgotPassword.scaleOnClick = true
        
        nextButton.set(handler: { [weak self] _ in
            self?.checkPasscode()
        }, for: .Click)
        
        forgotPassword.set(handler: { [weak self] _ in
            if let item = self?.item as? PassportInsertPasswordItem {
                if item.hasRecoveryEmail {
                    item.forgotPassword()
                } else {
                    alert(for: mainWindow, info: strings().secureIdForgotPasswordNoEmail)
                }
            }
        }, for: .Click)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func mouseDown(with event: NSEvent) {
        if inputContainer.mouseInside() || input._mouseInside() {
            (window as? Window)?.applyResponderIfNeeded()
        } else {
            super.mouseDown(with: event)
        }
    }
    
    func controlTextDidChange(_ obj: Notification) {
  
    }
    
    private func clearEditorBackground() {
        if let editor = input.textView {
            editor.drawsBackground = false
            editor.backgroundColor = .clear
            editor.insertionPointColor = theme.colors.text
        }
    }
    
    func controlTextDidBeginEditing(_ obj: Notification) {
        clearEditorBackground()
    }
    
    func controlTextDidEndEditing(_ obj: Notification) {
        clearEditorBackground()
    }
    
    override func layout() {
        super.layout()
        backdrop.frame = bounds
        let margin = PassportInsertPasswordItem.margin
        let fieldHeight = PassportInsertPasswordItem.fieldHeight
        inputContainer.frame = NSMakeRect(margin, PassportInsertPasswordItem.topPadding, frame.width - margin * 2, fieldHeight)
        input.setFrameSize(NSMakeSize(inputContainer.frame.width - PassportInsertPasswordItem.textInset * 2, input.frame.height))
        input.centerY(x: PassportInsertPasswordItem.textInset)
        descTextView.centerX(y: inputContainer.frame.maxY + 12)
        forgotPassword.centerX(y: descTextView.frame.maxY + 10)
        nextButton.frame = NSMakeRect(margin, forgotPassword.frame.maxY + 24, frame.width - margin * 2, fieldHeight)
    }
    
    @objc func checkPasscode() {
        guard let item = item as? PassportInsertPasswordItem else {return}

        item.checkPasswordAction((input.stringValue, { [weak self] in
            assertOnMainThread()
            (self?.window as? Window)?.applyResponderIfNeeded()
            self?.input.shake()
            self?.input.textView?.selectAllText()
            self?.clearEditorBackground()
        }))
    }
    
    
    
    override func updateColors() {
        super.updateColors()
        backdrop.backgroundColor = theme.colors.listBackground
        input.textColor = theme.colors.text
        input.backgroundColor = .clear
        descTextView.backgroundColor = theme.colors.listBackground
        inputContainer.backgroundColor = theme.colors.grayBackground
        
        let attr = NSMutableAttributedString()
        _ = attr.append(string: strings().secureIdInsertPasswordPassword, color: theme.colors.grayText, font: .normal(.title))
        input.placeholderAttributedString = attr
        input.font = .normal(.title)
        input.sizeToFit()
        nextButton.set(font: .medium(.title), for: .Normal)
        nextButton.set(color: .white, for: .Normal)
        nextButton.set(background: theme.colors.accent, for: .Normal)
        nextButton.set(text: strings().secureIdInsertPasswordNext, for: .Normal)
        nextButton.layer?.cornerRadius = PassportInsertPasswordItem.fieldHeight / 2
        
        forgotPassword.set(font: .normal(.text), for: .Normal)
        forgotPassword.set(color: theme.colors.accent, for: .Normal)
        forgotPassword.set(background: theme.colors.listBackground, for: .Normal)
        forgotPassword.set(text: strings().loginPasswordForgot, for: .Normal)
        forgotPassword.setAccessibilityLabel(strings().loginPasswordForgot)
        _ = forgotPassword.sizeToFit()
        needsLayout = true
    }
    
    override func viewDidMoveToWindow() {
        if let window = window as? Window {
            window.applyResponderIfNeeded()
        }
        clearEditorBackground()
    }
    
    override var firstResponder: NSResponder? {
        return input
    }
    
    override var mouseInsideField: Bool {
        return input._mouseInside()
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        switch true {
        case NSPointInRect(point, inputContainer.frame):
            return input
        default:
            return super.hitTest(point)
        }
    }
    
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? PassportInsertPasswordItem else {return}
        descTextView.update(item.descLayout)
        needsLayout = true
    }
    
}
