import Foundation
import AppKit
import TGUIKit
import TelegramCore
import SwiftSignalKit
import PhoneNumberUtils
import TelegramTheme
import Localization

private func formatNumber(_ number: String, country: Country) -> String {
    var formatted: String = ""
    
    var pattern: String?
    if number.isEmpty {
        pattern = country.countryCodes.first?.patterns.first(where: { value in
            return value.trimmingCharacters(in: CharacterSet(charactersIn: "0987654321")).count == value.count
        })
    } else {
        pattern = country.countryCodes.first?.patterns.first(where: { value in
            return value.first == number.first
        })
    }
    if pattern == nil {
        pattern = country.countryCodes.first?.patterns.last
    }
    guard let pattern = pattern else {
        return number
    }
    
    let numberChars = Array(number)
    let patternChars = Array(pattern)
    
    var patternIndex: Int = 0
    for char in numberChars {
        if patternIndex < patternChars.count {
            let pattern = patternChars[patternIndex]
            if pattern == "X" {
                formatted.append(char)
            } else {
                formatted.append("\(pattern)")
                if pattern == " " {
                    formatted.append(char)
                    patternIndex += 1
                }
            }
            patternIndex += 1
        } else {
            formatted.append(char)
        }
    }
    if patternIndex < patternChars.count, patternChars[patternIndex] == " " {
        formatted.append(" ")
    }
    return formatted
}

public final class Auth_CountryManager {
    public let list: [Country]
    private let byPrefix: [String: (Country, Country.CountryCode)]
    public init(_ countries:[Country]) {
        self.list = (countries).sorted(by: { lhs, rhs in
            return lhs.name < rhs.name
        })
        var byPrefix: [String: (Country, Country.CountryCode)] = [:]
        for country in countries {
            for code in country.countryCodes {
                if !code.prefixes.isEmpty {
                    for prefix in code.prefixes {
                        byPrefix[code.code + prefix] = (country, code)
                    }
                } else {
                    byPrefix[code.code] = (country, code)
                }
            }
        }
        if let code = Auth_CountryManager.globalCountry.countryCodes.first {
            byPrefix[code.code] = (Auth_CountryManager.globalCountry, code)
        }
        self.byPrefix = byPrefix
    }
    
    private static let globalCountry: Country = .init(id: "TG", name: "Test", localizedName: "Test", countryCodes: [.init(code: "999", prefixes: [], patterns: ["XXXX X XX"])], hidden: false)
    private var global: Country {
        return Auth_CountryManager.globalCountry
    }
    
    public func item(byNumber number: String, code: String? = nil, preferred: [String: String] = [:]) -> (Country, Country.CountryCode)? {
        var results: [(String, Country, Country.CountryCode)] = []
        for i in 0 ..< number.count {
            let prefix = String(number.prefix(number.count - i))
            if let (country, countryCode) = byPrefix[prefix], code == nil || countryCode.code == code {
                if let first = results.first, first.2.code.count > countryCode.code.count {
                    break
                }
                results.append((prefix, country, countryCode))
            }
        }
        guard let (key, country, countryCode) = results.first else {
            return nil
        }
        if key == countryCode.code, let preferredId = preferred[countryCode.code], let preferredCountry = self.list.first(where: { $0.id == preferredId }), let preferredCode = preferredCountry.countryCodes.first(where: { $0.code == countryCode.code }) {
            return (preferredCountry, preferredCode)
        }
        return (country, countryCode)
    }
    

    
    public func items(byCodeNumber codeNumber: String, checkAll: Bool = false) -> [Country] {
        
        var list = self.list
        list.append(global)

        
        return list.filter( { value in
            for code in value.countryCodes {
                if code.code == codeNumber {
                    return true
                } else if checkAll {
                    return code.code.hasPrefix(codeNumber)
                }
            }
            return false
        })
    }
    
    public func item(byCodeNumber codeNumber: String, prefix: String?) -> Country? {
        if codeNumber == "999" {
            return global
        }
//        if codeNumber == "888" {
//            return fragment
//        }
        let firstTrip = self.list.first(where: { value in
            for code in value.countryCodes {
                if code.code == codeNumber {
                    if let prefix = prefix {
                        return code.prefixes.contains(prefix)
                    }
                    return true
                }
            }
            return false
        })
        if firstTrip == nil {
            return self.list.first(where: { value in
                for code in value.countryCodes {
                    if code.code == codeNumber, code.prefixes.isEmpty {
                        return true
                    }
                }
                return false
            })
        }
        return firstTrip
    }
    public func item(bySmallCountryName name: String) -> Country? {
        return self.list.first(where: { value in
            return value.id == name
        })
    }
}

private final class TextField : NSTextField {
    public var didUpdateResponder: (()->Void)? = nil
    
    public var isFirstResponder: Bool = false
    public override func becomeFirstResponder() -> Bool {
        isFirstResponder = true
        self.didUpdateResponder?()
        return super.becomeFirstResponder()
    }
    public override func resignFirstResponder() -> Bool {
        isFirstResponder = false
        self.didUpdateResponder?()
        return super.resignFirstResponder()
    }
}

public final class Auth_PhoneInput: View, NSTextFieldDelegate {
    private let separator = View()
    private let country: TextButton = TextButton()
    
    private let country_overlay: Control = Control()
    private var preferredCountryIdForCode: [String: String] = [:]
    private let nextView = ImageView()
    
    private let codeText:TextField = TextField()
    private let numberText:TextField = TextField()

    
    public var manager: Auth_CountryManager = .init([]) {
        didSet {
            if !manager.list.isEmpty, selected == nil {
                let code = NSLocale.current.regionCode ?? "US"
                update(selected: manager.item(bySmallCountryName: code), update: true)
            }
        }
    }

    
    public func updateLocked(_ locked: Bool) {
        self.codeText.textView?.isEditable = !locked
        self.numberText.textView?.isEditable = !locked
    }
    
    public var selected:Country? {
        didSet {
            updatePlaceholder()
        }
    }

    
    public var next:((String)->Void)?
    public var updatePhoneNumber:((String)->Void)?
    
    private let placeholder: TextView = TextView()
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(separator)
        layer?.cornerRadius = 10
        
        country.set(text: "-----", for: .Normal)
        country.disableActions()
        _ = country.sizeToFit()
        addSubview(country)
        addSubview(nextView)
        addSubview(country_overlay)
        nextView.isAccessibilityDecorative = true
        country_overlay.setAccessibilityLabel(strings().loginCountryLabel)
        
        codeText.stringValue = "+"
        codeText.font = .code(.title)
        numberText.font = .code(.title)
        
        numberText.isBordered = false
        numberText.isBezeled = false
        numberText.focusRingType = .none
        numberText.drawsBackground = false
        
        codeText.isBordered = false
        codeText.isBezeled = false
        codeText.focusRingType = .none
        codeText.drawsBackground = false
        
        self.numberText.didUpdateResponder = { [weak self] in
            self?.needsLayout = true
        }
        self.codeText.didUpdateResponder = { [weak self] in
            self?.needsLayout = true
        }
        
        codeText.delegate = self
        codeText.nextResponder = numberText
        codeText.nextKeyView = numberText
        
        numberText.delegate = self
        numberText.nextResponder = codeText
        numberText.nextKeyView = codeText
        
        addSubview(placeholder)
        addSubview(codeText)
        addSubview(numberText)
        
        updateLocalizationAndTheme(theme: theme)
        
        country_overlay.contextMenu = { [weak self] in
            guard let manager = self?.manager else {
                return nil
            }
            var items:[ContextMenuItem] = []
            for country in manager.list where !country.hidden {
                let item = ContextMenuItem(country.fullName, handler: { [weak self] in
                    if let code = country.countryCodes.first?.code {
                        self?.preferredCountryIdForCode[code] = country.id
                    }
                    self?.update(selected: country, update: true)
                })
                items.append(item)
            }
            let menu = ContextMenu()
            for item in items {
                menu.addItem(item)
            }
            return menu
        }
    }
    
    private func updatePlaceholder() {
        let number = numberText.stringValue
        var text: String = number.isEmpty ? strings().loginPhoneFieldPlaceholder : ""
        if let item = selected {
            var pattern: String?
            if number.isEmpty {
                pattern = item.countryCodes.first?.patterns.first(where: { value in
                    return value.trimmingCharacters(in: CharacterSet(charactersIn: "0987654321")).count == value.count
                })
            } else {
                pattern = item.countryCodes.first?.patterns.first(where: { value in
                    return value.first == number.first
                })
            }
            if pattern == nil {
                pattern = item.countryCodes.first?.patterns.last
            }
            if let pattern = pattern {
                text = String(pattern.replacingOccurrences(of: "X", with: "-"))
            }
        }
        let attr = NSMutableAttributedString()
        _ = attr.append(string: text, color: theme.colors.grayText, font: .code(.title))
        if !number.isEmpty {
            attr.addAttribute(.foregroundColor, value: NSColor.clear, range: NSMakeRange(0, min(number.length, text.length)))
        }
        let layout = TextViewLayout(attr)
        layout.measure(width: .greatestFiniteMagnitude)
        placeholder.update(layout)
        needsLayout = true
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        self.backgroundColor = theme.colors.grayBackground
        self.separator.background = theme.colors.border
        
        numberText.textColor = theme.colors.text
        codeText.textColor = theme.colors.text

        codeText.backgroundColor = .clear
        numberText.backgroundColor = .clear
        country.style = ControlStyle(font: .medium(.title), foregroundColor: theme.colors.text, backgroundColor: theme.colors.grayBackground)
        country.set(font: .normal(.header), for: .Normal)
        
        codeText.placeholderAttributedString = .initialize(string: strings().loginCodePlaceholder, color: theme.colors.grayText, font: .normal(.header))
        nextView.image = TelegramThemeHooks.shared.image(.iconGeneralNext).precomposed(theme.colors.border)
        
        self.updatePlaceholder()
        
        nextView.sizeToFit()
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()
        codeText.sizeToFit()
        codeText.setFrameSize(codeText.frame.width, 18)
        numberText.setFrameSize(frame.width - (10 + codeText.frame.width + 10) - 10, 18)
        self.separator.frame = focus(NSMakeSize(frame.width - 20, .borderSize))
        
        let yCode:CGFloat = codeText.currentEditor() != nil ? 0 : 0
        let yNumber:CGFloat = numberText.currentEditor() != nil ? 0 : 0
        
        codeText.setFrameOrigin(10, frame.height - floor(frame.height / 2 - codeText.frame.height/2) + yCode)
        numberText.setFrameOrigin(10 + codeText.frame.width + 10, frame.height - floor(frame.height / 2 - numberText.frame.height/2) + yNumber)
        placeholder.setFrameOrigin(NSMakePoint(10 + codeText.frame.width + 10 + 2, frame.height - floor(frame.height / 2 - placeholder.frame.height/2) + 2))

        country.setFrameOrigin(NSMakePoint(10, 12))
        country_overlay.frame = NSMakeRect(0, 0, frame.width, frame.height / 2)
        nextView.setFrameOrigin(NSMakePoint(frame.width - 10 - nextView.frame.width, floor((frame.height / 2 - nextView.frame.height)/2)))
    }
    
    
    public func update(selected:Country?, update:Bool, updateCode:Bool = true) -> Void {
        self.selected = selected
        if let selected = selected {
            country.set(text: selected.emojiName , for: .Normal)
        } else {
            country.set(text: strings().loginInvalidCountryCode, for: .Normal)
        }
        country_overlay.setAccessibilityValue(selected?.emojiName ?? strings().loginInvalidCountryCode)
        country.sizeToFit()
        if updateCode {
            codeText.stringValue = selected != nil ? "+\(selected!.countryCodes[0].code)" : "+"
        }
        needsLayout = true
    }
    
    public func update(countryCode: Int32, number: String) {
        if !hasChanges {
            self.codeText.stringValue = "\(countryCode)"
            self.numberText.stringValue = formatPhoneNumber(number)
        }
        needsLayout = true
    }
    
    private var hasChanges: Bool = false
    
    public func controlTextDidChange(_ obj: Notification) {
        if let field = obj.object as? NSTextField {
            hasChanges = true
            let code = codeText.stringValue.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
            let dec = code.prefix(4)
            if field == codeText {
                if code.length > 4 {
                    if let (item, itemCode) = manager.item(byNumber: code, preferred: preferredCountryIdForCode) {
                        let rest = String(code.dropFirst(itemCode.code.count))
                        codeText.stringValue = "+" + itemCode.code
                        update(selected: item, update: true, updateCode: false)
                        
                        let text = rest + numberText.stringValue.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                        let formated = formatNumber(text, country: item).prefix(17)
                        numberText.stringValue = formated
                        window?.makeFirstResponder(numberText)
                        numberText.setCursorToEnd()
                        self.updatePhoneNumber?(formated)
                    } else {
                        update(selected: nil, update: true, updateCode: false)
                    }
                } else {
                    codeText.stringValue = "+" + dec
                    let item:Country? = manager.item(byNumber: String(dec), code: String(dec), preferred: preferredCountryIdForCode)?.0 ?? manager.item(byCodeNumber: String(dec), prefix: nil)
                    
                    let shouldSwitch = manager.items(byCodeNumber: dec, checkAll: true).count == 1
                    update(selected: item, update: true, updateCode:false)
                                             
                    if shouldSwitch {
                        window?.makeFirstResponder(numberText)
                    }
                }
                
            } else if field == numberText, let item = self.selected {
                let current = numberText.stringValue.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()

                let updated:Country? = manager.item(byNumber: String(dec) + current, preferred: preferredCountryIdForCode)?.0 ?? manager.item(byCodeNumber: String(dec), prefix: nil)
                if item != updated {
                    self.update(selected: updated, update: true, updateCode: false)
                }
                let formatCountry: Country? = updated.flatMap { value in value.countryCodes.contains(where: { $0.code == String(dec) }) ? value : nil } ?? manager.item(byNumber: String(dec), code: String(dec))?.0
                let formated = formatNumber(current, country: formatCountry ?? updated ?? item).prefix(17)
                numberText.stringValue = formated
                self.updatePhoneNumber?(formated)
            } else if field == numberText {
                let current = "+" + numberText.stringValue.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                self.numberText.stringValue = ""
                self.codeText.stringValue = current
                window?.makeFirstResponder(codeText)
                codeText.setCursorToEnd()
                self.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: self.codeText, userInfo: nil))
                self.updatePhoneNumber?(formatPhoneNumber(current))
            }
            
        }
        updatePlaceholder()
        needsLayout = true
    }
    
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            if control == codeText {
                self.window?.makeFirstResponder(self.numberText)
                self.numberText.selectText(nil)
            } else if !numberText.stringValue.isEmpty {
                self.next?(codeText.stringValue + numberText.stringValue)
            }
            (control as? NSTextField)?.setCursorToEnd()
            return true
        } else if commandSelector == #selector(deleteBackward(_:)) {
            if control == numberText {
                if numberText.stringValue.isEmpty {
                    DispatchQueue.main.async {
                        self.window?.makeFirstResponder(self.codeText)
                        self.codeText.setCursorToEnd()
                    }
                } else {
                    if numberText.stringValue.last == " " {
                        numberText.stringValue = String(numberText.stringValue.prefix(max(0, numberText.stringValue.length - 1)))
                        return true
                    }
                }
            }
            return false
            
        }
        return false
    }

    
    public var readyValue: String {
        return self.codeText.stringValue + numberText.stringValue
    }
    
    public var firstResponder: NSResponder? {
        if window?.firstResponder != numberText.textView || window?.firstResponder != codeText.textView {
            if self.codeText.stringValue.isEmpty {
                return self.codeText
            }
            return self.numberText
        }
        return window?.firstResponder
    }
    
    public func set(_ number: String) {
        if !hasChanges {
            self.codeText.stringValue = number
            self.numberText.stringValue = ""
            self.controlTextDidChange(Notification.init(name: NSControl.textDidChangeNotification, object: self.codeText, userInfo: nil))
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
