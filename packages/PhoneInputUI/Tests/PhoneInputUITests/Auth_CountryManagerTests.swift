import XCTest
import TelegramCore
@testable import PhoneInputUI

final class Auth_CountryManagerTests: XCTestCase {
    private let saintHelena = Country(id: "SH", name: "Saint Helena", localizedName: nil, countryCodes: [
        .init(code: "247", prefixes: [], patterns: []),
        .init(code: "290", prefixes: [], patterns: ["XX XXX"]),
    ], hidden: false)
    
    private lazy var manager = Auth_CountryManager([
        Country(id: "BS", name: "Bahamas", localizedName: nil, countryCodes: [.init(code: "1242", prefixes: [], patterns: ["XXX XXXX"])], hidden: false),
        Country(id: "CA", name: "Canada", localizedName: nil, countryCodes: [.init(code: "1", prefixes: ["403", "416", "604"], patterns: ["XXX XXX XXXX"])], hidden: false),
        Country(id: "CP", name: "CanadaVoIP", localizedName: nil, countryCodes: [.init(code: "1", prefixes: [], patterns: [])], hidden: false),
        Country(id: "KZ", name: "Kazakhstan", localizedName: nil, countryCodes: [.init(code: "7", prefixes: ["6", "7"], patterns: ["XXX XXX XXXX"])], hidden: false),
        Country(id: "RU", name: "Russian Federation", localizedName: nil, countryCodes: [.init(code: "7", prefixes: [], patterns: ["XXX XXX XXXX"])], hidden: false),
        saintHelena,
        Country(id: "US", name: "USA", localizedName: nil, countryCodes: [.init(code: "1", prefixes: [], patterns: ["XXX XXX XXXX"])], hidden: false),
    ])
    
    func testMatchesLongestPrefix() {
        XCTAssertEqual(manager.item(byNumber: "12025550123")?.0.id, "US")
        XCTAssertEqual(manager.item(byNumber: "14165550123")?.0.id, "CA")
        XCTAssertEqual(manager.item(byNumber: "12425551234")?.0.id, "BS")
        XCTAssertEqual(manager.item(byNumber: "79161234567")?.0.id, "RU")
        XCTAssertEqual(manager.item(byNumber: "77011234567")?.0.id, "KZ")
        XCTAssertEqual(manager.item(byNumber: "1", code: "1")?.0.id, "US")
        XCTAssertEqual(manager.item(byNumber: "9991234")?.1.code, "999")
    }
    
    func testKeepsPreferredCountryWithoutAreaCodeMatch() {
        XCTAssertEqual(manager.item(byNumber: "12025550123", preferred: ["1": "CP"])?.0.id, "CP")
        XCTAssertEqual(manager.item(byNumber: "14165550123", preferred: ["1": "CP"])?.0.id, "CA")
    }
    
    func testReturnsMatchedCodeOfCountryWithSeveralCodes() {
        let other = manager.item(byNumber: "29012345")
        XCTAssertEqual(other?.0.id, "SH")
        XCTAssertEqual(other?.1.code, "290")
        XCTAssertEqual(manager.item(byNumber: "290", code: "290")?.1.code, "290")
        
        let first = manager.item(byNumber: "2471234")
        XCTAssertEqual(first?.0.id, "SH")
        XCTAssertEqual(first?.1.code, "247")
    }
    
    func testFormatsWithMatchedCode() throws {
        let code = try XCTUnwrap(manager.item(byNumber: "29012345")?.1)
        XCTAssertEqual(formatNationalNumber("12345", code: code), "12 345")
        XCTAssertEqual(phoneNumberPattern("", code: code), "XX XXX")
        
        XCTAssertEqual(formatNationalNumber("12345", code: saintHelena.countryCodes[0]), "12345")
        XCTAssertNil(phoneNumberPattern("", code: saintHelena.countryCodes[0]))
    }
}
