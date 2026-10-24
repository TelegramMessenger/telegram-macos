import XCTest
@testable import Translate

final class TranslateLanguageCodeTests: XCTestCase {
    private func isTranslationTarget(_ code: String) -> Bool {
        return Translate.codes.contains(where: { $0.code.contains(code) })
    }

    func testRegionalInterfaceLanguageIsNotATranslationTarget() {
        XCTAssertFalse(isTranslationTarget("pt-br"))
    }

    func testRegionalInterfaceLanguageNormalizesToBaseLanguage() {
        XCTAssertEqual(Translate.normalizeLanguageCode("pt-br"), "pt")
        XCTAssertEqual(Translate.normalizeLanguageCode("zh-hans"), "zh")
    }

    func testNorwegianBokmalNormalizesToNorwegian() {
        XCTAssertEqual(Translate.normalizeLanguageCode("nb"), "no")
    }

    func testSupportedCodesAreKept() {
        for value in Translate.codes {
            for code in value.code {
                XCTAssertEqual(Translate.normalizeLanguageCode(code), code)
            }
        }
    }

    func testOfficialInterfaceLanguagesNormalizeToTranslationTargets() {
        let interfaceLanguages = ["en", "ar", "be", "ca", "hr", "cs", "nl", "fi", "fr", "de", "he", "hu", "id", "it", "kk", "ko", "ms", "nb", "fa", "pl", "pt-br", "ru", "sr", "sk", "es", "sv", "tr", "uk", "uz"]
        for language in interfaceLanguages {
            XCTAssertTrue(isTranslationTarget(Translate.normalizeLanguageCode(language)), language)
        }
    }

    func testFindUsesNormalizedCode() {
        XCTAssertEqual(Translate.find("pt-br")?.code, ["pt"])
        XCTAssertEqual(Translate.find("nb")?.code, ["no"])
        XCTAssertEqual(Translate.find("zh-TW")?.code, ["zh-TW"])
    }
}
