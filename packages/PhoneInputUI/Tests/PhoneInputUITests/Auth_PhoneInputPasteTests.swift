import AppKit
import XCTest
import TGUIKit
import TelegramCore
import TelegramTheme
import ColorPalette
import ThemeSettings
@testable import PhoneInputUI

final class Auth_PhoneInputPasteTests: XCTestCase {
    private static var images: [NSImage] = []
    
    private static let installed: Void = {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        System.updateScaleFactor(2)
        System.liquidGlass = false
        let image = NSImage(size: NSMakeSize(16, 16), flipped: false) { rect in
            NSColor.black.setFill()
            rect.insetBy(dx: 4, dy: 4).fill()
            return true
        }
        for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"] {
            let named = image.copy() as! NSImage
            _ = named.setName(name)
            images.append(named)
        }
        TelegramThemeHooks.install(.init(image: { _ in image }, icons: { generateIcons(from: $0, bubbled: $1) }, sendingFrame: { generateSendingFrame($0) }, clockMinImage: { generateClockMinImage($0) }, chatGroupToggleSelected: { generateChatGroupToggleSelected(foregroundColor: $0, backgroundColor: $1) }, chatGroupToggleUnselected: { generateChatGroupToggleUnselected(foregroundColor: $0, backgroundColor: $1) }, setDefaultTheme: { _ in }, liteMode: { .standart }, darkAppearance: { theme }, liveStreamBadgeColor: { .systemRed }))
        telegramUpdateTheme(generateTheme(palette: dayClassicPalette, cloudTheme: nil, bubbled: false, fontSize: 13, wallpaper: ThemeWallpaper(), liquidGlass: false), window: nil, animated: false)
    }()
    
    private func makeInput() -> Auth_PhoneInput {
        _ = Auth_PhoneInputPasteTests.installed
        let input = Auth_PhoneInput(frame: NSMakeRect(0, 0, 300, 100))
        input.manager = Auth_CountryManager([
            Country(id: "CA", name: "Canada", localizedName: nil, countryCodes: [.init(code: "1", prefixes: ["403", "416"], patterns: ["XXX XXX XXXX"])], hidden: false),
            Country(id: "GB", name: "United Kingdom", localizedName: nil, countryCodes: [.init(code: "44", prefixes: [], patterns: ["XXXX XXXXXX"])], hidden: false),
            Country(id: "US", name: "USA", localizedName: nil, countryCodes: [.init(code: "1", prefixes: [], patterns: ["XXX XXX XXXX"])], hidden: false),
        ])
        return input
    }
    
    private func type(_ text: String, into field: NSTextField, of input: Auth_PhoneInput) {
        field.stringValue = text
        input.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    }
    
    private func digits(_ value: String) -> String {
        return value.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
    }
    
    private func enterUSNumber(_ input: Auth_PhoneInput) {
        type("+1", into: input.codeText, of: input)
        type("2025550123", into: input.numberText, of: input)
        XCTAssertEqual(input.selected?.id, "US")
        XCTAssertEqual(digits(input.readyValue), "12025550123")
    }
    
    func testFullNumberPastedIntoNumberFieldReplacesBothFields() {
        let input = makeInput()
        enterUSNumber(input)
        
        type("+44 7700 900123", into: input.numberText, of: input)
        
        XCTAssertEqual(input.codeText.stringValue, "+44")
        XCTAssertEqual(input.numberText.stringValue, "7700 900123")
        XCTAssertEqual(input.selected?.id, "GB")
        XCTAssertEqual(digits(input.readyValue), "447700900123")
    }
    
    func testFullNumberPastedIntoCodeFieldReplacesNumberField() {
        let input = makeInput()
        enterUSNumber(input)
        
        type("+44 7700 900123", into: input.codeText, of: input)
        
        XCTAssertEqual(input.codeText.stringValue, "+44")
        XCTAssertEqual(input.numberText.stringValue, "7700 900123")
        XCTAssertEqual(input.selected?.id, "GB")
        XCTAssertEqual(digits(input.readyValue), "447700900123")
    }
    
    func testDigitTypedPastCodeMovesToNumberField() {
        let input = makeInput()
        type("+1", into: input.codeText, of: input)
        type("555 0123", into: input.numberText, of: input)
        
        type("+1202", into: input.codeText, of: input)
        type("+12025", into: input.codeText, of: input)
        
        XCTAssertEqual(input.codeText.stringValue, "+1")
        XCTAssertEqual(digits(input.readyValue), "120255550123")
    }
}
