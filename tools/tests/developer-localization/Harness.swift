import AppKit
import Foundation

var checks = 0
var failures = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    checks += 1
    if !condition() {
        failures += 1
        if failures <= 20 { print("FAIL: \(name)") }
    }
}
func language(_ code: String, _ values: [String: String] = [:]) -> Language {
    Language(languageCode: code, customPluralizationCode: nil, strings: values)
}
func select(_ primary: Language, _ secondary: Language? = nil) {
    appCurrentLanguage = TelegramLocalization(primaryLanguage: primary, secondaryLanguage: secondary, localizedName: primary.languageCode)
}
let ru = language("ru")
let en = language("en")
let unknown = language("zz")
check(Bundle.main.bundlePath.hasSuffix(".app"), "native application bundle")
check(Bundle.main.localizations.contains("ru"), "Russian bundle is present")
check(_LocalizedStringFor("Developer.Title", primary: ru, secondary: nil) == "Для разработчиков", "bundled Russian without downloaded keys")
check(_LocalizedStringFor("Developer.Title", primary: en, secondary: nil) == "Developer", "English fallback")
check(_LocalizedStringFor("Developer.Title", primary: unknown, secondary: nil) == "Developer", "unknown locale uses English")
check(_LocalizedStringFor("Developer.Title", primary: language("uk"), secondary: nil) == "Developer", "empty Ukrainian bundle does not select Russian")
check(_LocalizedStringFor("Developer.Title", primary: language("RU_ru"), secondary: nil) == "Для разработчиков", "region and case fallback")
check(_LocalizedStringFor("Developer.Title", primary: language("ru-RU"), secondary: nil) == "Для разработчиков", "hyphenated region fallback")
check(_LocalizedStringFor("Developer.Title", primary: unknown, secondary: ru) == "Для разработчиков", "custom language uses Russian base")
check(_LocalizedStringFor("Developer.Title", primary: language("ru", ["Developer.Title": "Облачный перевод"]), secondary: nil) == "Облачный перевод", "downloaded primary wins")
check(_LocalizedStringFor("Developer.Title", primary: ru, secondary: language("en", ["Developer.Title": "Cloud secondary"])) == "Cloud secondary", "downloaded secondary priority is preserved")
check(_LocalizedStringFor("Developer.Title", primary: language("ru", ["Developer.Title": ""]), secondary: nil) == "Для разработчиков", "empty downloaded string falls through")
check(_LocalizedStringFor("Missing.Developer.Key", primary: ru, secondary: nil) == "Missing.Developer.Key", "unknown key remains the key")
check(_LocalizedStringFor("Missing.Developer.Key", primary: ru, secondary: nil, returnNilIfMissing: true) == nil, "unknown key can return nil")
select(ru)
check(strings().developerTitle == "Для разработчиков", "generated title accessor")
check(strings().developerNetworkEngineActive("Rust", "MtProtoKit") == "Rust (активен: MtProtoKit)", "ordered engine arguments")
check(strings().developerNetworkEngineRustDisabled.contains("mtproto_engine_rust_disabled"), "diagnostic code remains literal")
check(strings().developerNativeContextMenu.contains("возможны сбои"), "glitch warning survives translation")
check(strings().developerCrash == "Вызвать аварийное завершение", "crash action is explicit")
let windows = [0: "окнах", 1: "окне", 2: "окнах", 5: "окнах", 11: "окнах", 21: "окне", 22: "окнах", 25: "окнах"]
let issueWords = [0: "проблем", 1: "проблема", 2: "проблемы", 5: "проблем", 11: "проблем", 21: "проблема", 22: "проблемы", 25: "проблем"]
for count in [0, 1, 2, 5, 11, 21, 22, 25] {
    check(strings().developerAccessibilityAuditNoIssuesOther(count) == "В \(count) \(windows[count]!) проблем доступности не обнаружено.", "Russian window plural \(count)")
    let value = strings().developerAccessibilityAuditCopiedOther(count)
    check(value.contains("\(count) \(issueWords[count]!)"), "Russian issue plural \(count)")
    check(value.contains("буфер обмена"), "clipboard message \(count)")
}
check(NativeLocalization("Developer.Title") == "Developer", "native English lookup stays English")
let russianBundle = Bundle(path: Bundle.main.path(forResource: "ru", ofType: "lproj")!)!
let englishBundle = Bundle(path: Bundle.main.path(forResource: "en", ofType: "lproj")!)!
let englishPath = englishBundle.path(forResource: "Localizable", ofType: "strings")!
let englishValues = NSDictionary(contentsOfFile: englishPath) as! [String: String]
for (key, value) in englishValues {
    let local = NSLocalizedString(key, bundle: russianBundle, comment: "")
    if local == key {
        check(_LocalizedStringFor(key, primary: ru, secondary: nil) == value, "unchanged English fallback \(key)")
    }
}
let lock = NSLock()
var concurrentFailures = 0
DispatchQueue.concurrentPerform(iterations: 1000) { _ in
    if _LocalizedStringFor("Developer.Title", primary: ru, secondary: nil) != "Для разработчиков" {
        lock.lock(); concurrentFailures += 1; lock.unlock()
    }
}
check(concurrentFailures == 0, "concurrent bundle lookups")
select(en)
check(strings().developerTitle == "Developer", "switch to English")
check(strings().developerAccessibilityAuditNoIssuesOther(1) == "No accessibility issues in 1 window.", "English singular")
check(strings().developerAccessibilityAuditNoIssuesOther(2) == "No accessibility issues in 2 windows.", "English plural")
select(ru)
check(strings().developerTitle == "Для разработчиков", "switch back to Russian")
check(previewRows().count == beforeRows().count, "same menu row count")

func render(_ rows: [(String, Bool)], title: String, to url: URL) throws {
    let width: CGFloat = 850
    let height = CGFloat(110 + rows.reduce(0) { $0 + ($1.1 ? 48 : 58) })
    let image = NSImage(size: NSSize(width: width, height: height))
    image.lockFocus()
    NSColor(calibratedRed: 0.055, green: 0.084, blue: 0.108, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 23, weight: .medium), .foregroundColor: NSColor.white]
    (title as NSString).draw(in: NSRect(x: 40, y: height - 65, width: width - 80, height: 40), withAttributes: attributes)
    var y = height - 105
    for (text, header) in rows {
        let rowHeight: CGFloat = header ? 48 : 58
        let rowAttributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: header ? 15 : 20), .foregroundColor: header ? NSColor.lightGray : NSColor.white]
        if !header {
            NSColor(calibratedRed: 0.09, green: 0.135, blue: 0.17, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 24, y: y - rowHeight + 5, width: width - 48, height: rowHeight - 3), xRadius: 12, yRadius: 12).fill()
        }
        (text as NSString).draw(in: NSRect(x: 45, y: y - rowHeight + 16, width: width - 90, height: rowHeight - 16), withAttributes: rowAttributes)
        y -= rowHeight
    }
    image.unlockFocus()
    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}
if let index = CommandLine.arguments.firstIndex(of: "--output"), index + 1 < CommandLine.arguments.count {
    let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
    _ = NSApplication.shared
    try render(beforeRows(), title: "Developer", to: directory.appendingPathComponent("before.png"))
    try render(previewRows(), title: strings().developerTitle, to: directory.appendingPathComponent("after.png"))
}
print("\(checks) native localization checks; \(failures) failures")
exit(failures == 0 ? 0 : 1)
