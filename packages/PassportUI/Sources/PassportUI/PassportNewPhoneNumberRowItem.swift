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
import PhoneInputUI

class PassportNewPhoneNumberRowItem: GeneralRowItem, InputDataRowDataValue {
    fileprivate let countries: Signal<[Country], NoError>
    fileprivate var readValue: (() -> String)?
    
    var value: InputDataValue {
        return .string(readValue?() ?? "")
    }
    
    init(_ initialSize: NSSize, stableId: AnyHashable, countries: Signal<[Country], NoError>, action: @escaping()->Void) {
        self.countries = countries
        super.init(initialSize, height: 100, stableId: stableId, viewType: .singleItem, action: action)
    }
    
    override func viewClass() -> AnyClass {
        return PassportNewPhoneNumberRowView.self
    }

    override var backdorColor: NSColor {
        return theme.colors.listBackground
    }

    override var accessibilityLabel: String? {
        return strings().secureIdPhoneNumber
    }
}


private final class PassportNewPhoneNumberRowView : TableRowView {
    private let input: Auth_PhoneInput = Auth_PhoneInput(frame: NSMakeRect(0, 0, 300, 80))
    private let countriesDisposable = MetaDisposable()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        input.layer?.cornerRadius = 20
        addSubview(input)
    }
    
    deinit {
        countriesDisposable.dispose()
    }
    
    override var mouseInsideField: Bool {
        return input._mouseInside()
    }
    
    override func hasFirstResponder() -> Bool {
        return true
    }
    
    override var firstResponder: NSResponder? {
        return input.firstResponder
    }
    
    override func layout() {
        super.layout()
        guard let item = item as? PassportNewPhoneNumberRowItem else {
            return
        }
        let width = item.blockWidth
        input.frame = NSMakeRect(floor((frame.width - width) / 2), 10, width, 80)
    }
    
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? PassportNewPhoneNumberRowItem else {
            return
        }
        item.readValue = { [weak self] in
            return self?.input.readyValue ?? ""
        }
        countriesDisposable.set((item.countries |> deliverOnMainQueue).start(next: { [weak self] countries in
            self?.input.manager = Auth_CountryManager(countries)
        }))
    }
    
    override func updateColors() {
        super.updateColors()
        backgroundColor = theme.colors.listBackground
        input.updateLocalizationAndTheme(theme: theme)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
