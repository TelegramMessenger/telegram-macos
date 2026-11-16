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
    
    private var window: NSWindow?
    
    override func tearDown() {
        window?.orderOut(nil)
        window = nil
        super.tearDown()
    }
    
    private func makeInput() -> Auth_PhoneInput {
        _ = Auth_PhoneInputPasteTests.installed
        let input = Auth_PhoneInput(frame: NSMakeRect(0, 0, 300, 100))
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 300, 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView?.addSubview(input)
        self.window = window
        input.manager = Auth_CountryManager([
            Country(id: "CA", name: "Canada", localizedName: nil, countryCodes: [.init(code: "1", prefixes: ["403", "416"], patterns: ["XXX XXX XXXX"])], hidden: false),
            Country(id: "EG", name: "Egypt", localizedName: nil, countryCodes: [.init(code: "20", prefixes: [], patterns: ["XX XXXX XXXX"])], hidden: false),
            Country(id: "GB", name: "United Kingdom", localizedName: nil, countryCodes: [.init(code: "44", prefixes: [], patterns: ["XXXX XXXXXX"])], hidden: false),
            Country(id: "US", name: "USA", localizedName: nil, countryCodes: [.init(code: "1", prefixes: [], patterns: ["XXX XXX XXXX"])], hidden: false),
        ])
        return input
    }
    
    private func set(_ text: String, into field: NSTextField, of input: Auth_PhoneInput) {
        field.stringValue = text
        input.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    }
    
    private func editor(for field: NSTextField) throws -> NSTextView {
        XCTAssertTrue(try XCTUnwrap(window).makeFirstResponder(field))
        return try XCTUnwrap(field.currentEditor() as? NSTextView)
    }
    
    private func insert(_ text: String, into field: NSTextField, range: NSRange? = nil) throws {
        let editor = try editor(for: field)
        editor.setSelectedRange(range ?? NSMakeRange((editor.string as NSString).length, 0))
        editor.insertText(text, replacementRange: editor.selectedRange())
    }
    
    private func digits(_ value: String) -> String {
        return value.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
    }
    
    private func enterUSNumber(_ input: Auth_PhoneInput) {
        set("+1", into: input.codeText, of: input)
        set("202 555 0123", into: input.numberText, of: input)
        XCTAssertEqual(input.selected?.id, "US")
        XCTAssertEqual(digits(input.readyValue), "12025550123")
    }
    
    private func assertUKNumber(_ input: Auth_PhoneInput, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(input.codeText.stringValue, "+44", file: file, line: line)
        XCTAssertEqual(input.numberText.stringValue, "7700 900123", file: file, line: line)
        XCTAssertEqual(input.selected?.id, "GB", file: file, line: line)
        XCTAssertEqual(digits(input.readyValue), "447700900123", file: file, line: line)
    }
    
    func testPasteAtEndOfNumberFieldReplacesBothFields() throws {
        let input = makeInput()
        enterUSNumber(input)
        try insert("+44 7700 900123", into: input.numberText)
        assertUKNumber(input)
    }
    
    func testPasteOverPartOfNumberFieldReplacesBothFields() throws {
        let input = makeInput()
        enterUSNumber(input)
        try insert("+44 7700 900123", into: input.numberText, range: NSMakeRange(4, 3))
        assertUKNumber(input)
    }
    
    func testPasteAtEndOfCodeFieldReplacesBothFields() throws {
        let input = makeInput()
        enterUSNumber(input)
        try insert("+44 7700 900123", into: input.codeText)
        assertUKNumber(input)
    }
    
    func testPastedCallingCodeKeepsNumber() throws {
        let input = makeInput()
        enterUSNumber(input)
        try insert("+44", into: input.codeText)
        XCTAssertEqual(input.codeText.stringValue, "+44")
        XCTAssertEqual(input.selected?.id, "GB")
        XCTAssertEqual(digits(input.numberText.stringValue), "2025550123")
    }
    
    func testTypedPlusInNumberFieldKeepsNumber() throws {
        let input = makeInput()
        enterUSNumber(input)
        try insert("+", into: input.numberText)
        XCTAssertEqual(input.codeText.stringValue, "+1")
        XCTAssertEqual(input.numberText.stringValue, "202 555 0123")
        XCTAssertEqual(input.selected?.id, "US")
        XCTAssertEqual(digits(input.readyValue), "12025550123")
    }
    
    func testTypedDigitsInNumberFieldAreFormatted() throws {
        let input = makeInput()
        set("+1", into: input.codeText, of: input)
        for digit in "2025550123" {
            try insert(String(digit), into: input.numberText)
        }
        XCTAssertEqual(input.numberText.stringValue, "202 555 0123")
        XCTAssertEqual(input.selected?.id, "US")
    }
    
    func testDigitTypedPastCodeMovesToNumberField() throws {
        let input = makeInput()
        set("+1", into: input.codeText, of: input)
        set("555 0123", into: input.numberText, of: input)
        set("+1202", into: input.codeText, of: input)
        try insert("5", into: input.codeText)
        XCTAssertEqual(input.codeText.stringValue, "+1")
        XCTAssertEqual(digits(input.readyValue), "120255550123")
    }
}
