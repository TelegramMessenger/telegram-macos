import SwiftSignalKit
import TelegramCore
import NumberPluralization
import Strings
import Foundation

extension Int {
    func description() -> String {
        return "\(self)"
    }
    
}
extension Int32 {
    var description:String {
        return "\(self)"
    }
}
extension Float {
    var description:String {
        return "\(self)"
    }
}
extension Double {
    var description:String {
        return "\(self)"
    }
}


 func tr(_ string: String) -> String {
    return string
}

private func dictFromLocalization(_ value: Localization) -> [String: String] {
    var dict: [String: String] = [:]
    for entry in value.entries {
        switch entry {
        case let .string(key, value):
            dict[key] = value
        case let .pluralizedString(key, zero, one, two, few, many, other):
            if let zero = zero {
                dict["\(key)_zero"] = zero
            }
            if let one = one {
                dict["\(key)_one"] = one
            }
            if let two = two {
                dict["\(key)_two"] = two
            }
            if let few = few {
                dict["\(key)_few"] = few
            }
            if let many = many {
                dict["\(key)_many"] = many
            }
            dict["\(key)_other"] = other
        }
    }
    return dict
}

public func applyUILocalization(_ settings: LocalizationSettings) {
    let primaryLanguage = Language(languageCode: settings.primaryComponent.languageCode, customPluralizationCode: settings.primaryComponent.customPluralizationCode, strings: dictFromLocalization(settings.primaryComponent.localization))
    let secondaryLanguage = settings.secondaryComponent != nil ? Language.init(languageCode: settings.secondaryComponent!.languageCode, customPluralizationCode: settings.secondaryComponent!.customPluralizationCode, strings: dictFromLocalization(settings.secondaryComponent!.localization)) : nil
    
    let language = TelegramLocalization(primaryLanguage: primaryLanguage, secondaryLanguage: secondaryLanguage, localizedName: settings.primaryComponent.localizedName)
    _ = _appCurrentLanguage.swap(language)
    languagePromise.set(.single(language))
}

public class Language : Equatable {
    public let languageCode:String
    public let customPluralizationCode: String?
    public let strings:[String: String]
    fileprivate let bundledFallbacks: [Bundle]
    public init (languageCode:String, customPluralizationCode: String?, strings:[String: String]) {
        self.languageCode = languageCode
        self.customPluralizationCode = customPluralizationCode
        self.strings = strings
        self.bundledFallbacks = bundledLocalizationFallbacks(for: languageCode)
    }
}

public func ==(lhs:Language, rhs:Language) -> Bool {
    return lhs === rhs
}
private let ZeroValueHolder = "_ZeroValueHolder"
private let _otherSuffix = "_other"

public func translate(key: String, _ args: [CVarArg]) -> String {
    var args = args

    // Snapshot the language ONCE per call. Each `appCurrentLanguage` access
    // takes the Atomic lock — looking up `_NSLocalizedString` four times
    // would otherwise lock four times. Local snapshot is also safe because a
    // mid-call language switch would race with the result anyway.
    let language = appCurrentLanguage
    let primary = language.primaryLanguage
    let secondary = language.secondaryLanguage

    let format: String = resolveFormat(
        key: key,
        args: args,
        primary: primary,
        secondary: secondary,
        pluralizationCode: language.pluralizationCode
    ) ?? "UndefinedKey"

    if format == "UndefinedKey" {
        return format
    }

    let ranges = extractArgumentRanges(format)
    var formatted = format
    while ranges.count != args.count, !args.isEmpty {
        args.removeFirst()
    }
    let argIndexes = ranges.sorted(by: { lhs, rhs -> Bool in
        return lhs.2 < rhs.2
    })

    var argValues: [String] = args.map { "\($0)" }

    for index in argIndexes.map({ $0.0 }) {
        if !args.isEmpty {
            argValues[index] = "\(args.removeFirst())"
        }
    }

    for range in ranges.reversed() {
        if !argValues.isEmpty {
            let value = argValues.removeLast()
            formatted = formatted.nsstring.replacingCharacters(in: range.1, with: value)
        } else {
            formatted = formatted.nsstring.replacingCharacters(in: range.1, with: "")
        }
    }
    return formatted
}

@inline(__always)
private func resolveFormat(key: String, args: [CVarArg], primary: Language, secondary: Language?, pluralizationCode: String) -> String? {
    if !key.hasSuffix(_otherSuffix) {
        return _LocalizedStringFor(key, primary: primary, secondary: secondary)
    }

    // `_other`-suffixed key: locate the first numeric arg, derive the
    // language's plural form, and try the more specific key first. The
    // previous implementation walked `args` with a flagged loop just to grab
    // the first Int — same here but kept tight.
    var resolvedCount: Int?
    for arg in args {
        if let count = arg as? Int {
            resolvedCount = count
            break
        }
    }
    guard let count = resolvedCount else {
        return _LocalizedStringFor(key, primary: primary, secondary: secondary)
    }

    // `_other` is the known suffix (we early-exited otherwise). Avoid
    // `range(of:)`/substring slicing — `dropLast` is a plain index op.
    let baseKey = String(key.dropLast(_otherSuffix.count))
    let count32 = Int32(min(count, Int(Int32.max)))

    if count32 == 0 {
        if let value = _LocalizedStringFor(baseKey + ZeroValueHolder, primary: primary, secondary: secondary, returnNilIfMissing: true) {
            return value
        }
    }

    let code = languageCodehash(pluralizationCode)
    let pluralForm = "_\(presentationStringsPluralizationForm(code, count32).name)"
    let pluralKey = baseKey + pluralForm
    if let value = _LocalizedStringFor(pluralKey, primary: primary, secondary: secondary, returnNilIfMissing: true) {
        return value
    }
    return _LocalizedStringFor(key, primary: primary, secondary: secondary)
}

private let argumentRegex = try! NSRegularExpression(pattern: "(%(((\\d+)\\$)?)([0-9])%(((\\d+)\\$)?)([@df]))|(%(((\\d+)\\$)?)([@df]))", options: [])
internal func extractArgumentRanges(_ value: String) -> [(Int, NSRange, Int)] {
    var result: [(Int, NSRange, Int)] = []
    let string = value as NSString
    let matches = argumentRegex.matches(in: string as String, options: [], range: NSRange(location: 0, length: string.length))
    var index = 0
    for match in matches {
        let range = match.range(at: 0)
        var valueIndex = index
        if range.length >= 4, let index = Int(string.substring(with: NSMakeRange(range.location + 1, range.length - 3))) {
            valueIndex = index
        }
        result.append((index, range, valueIndex))
        index += 1
    }
    result.sort(by: { $0.1.location < $1.1.location })
    return result
}

public final class TelegramLocalization : Equatable {
    
    
    public let primaryLanguage: Language
    public let secondaryLanguage: Language?
    public let baseLanguageCode: String
    public let localizedName: String
    public init(primaryLanguage: Language, secondaryLanguage: Language?, localizedName: String) {
        self.primaryLanguage = primaryLanguage
        self.secondaryLanguage = secondaryLanguage
        self.localizedName = localizedName
        self.baseLanguageCode = secondaryLanguage?.languageCode ?? primaryLanguage.languageCode
    }
    
    public var languageCode: String {
        return baseLanguageCode
    }
    
    public static func == (lhs: TelegramLocalization, rhs: TelegramLocalization) -> Bool {
        return lhs.primaryLanguage == rhs.primaryLanguage && lhs.secondaryLanguage == rhs.secondaryLanguage && lhs.baseLanguageCode == rhs.baseLanguageCode
    }
    
    public var pluralizationCode: String {
        return primaryLanguage.customPluralizationCode ?? secondaryLanguage?.customPluralizationCode ?? secondaryLanguage?.languageCode ?? primaryLanguage.languageCode
    }
    
}

private let _appCurrentLanguage:Atomic<TelegramLocalization> = Atomic(value: TelegramLocalization(primaryLanguage: Language(languageCode: "en", customPluralizationCode: nil, strings: [:]), secondaryLanguage: nil, localizedName: "English"))
public var appCurrentLanguage:TelegramLocalization {
    return _appCurrentLanguage.modify {$0}
}
private let languagePromise:Promise<TelegramLocalization> = Promise(appCurrentLanguage)

public var languageSignal:Signal<TelegramLocalization, NoError> {
    return languagePromise.get() |> distinctUntilChanged |> deliverOnMainQueue
}

private let _englishFallbackBundle: Bundle? = {
    guard let path = Bundle.main.path(forResource: "en", ofType: "lproj") else {
        return nil
    }
    return Bundle(path: path)
}()

private let _localizedFallbackBundles: [String: Bundle] = {
    var bundles: [String: Bundle] = [:]
    for code in Bundle.main.localizations where code != "en" {
        if let path = Bundle.main.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) {
            bundles[code.lowercased().replacingOccurrences(of: "_", with: "-")] = bundle
        }
    }
    return bundles
}()

private func bundledLocalizationFallbacks(for languageCode: String) -> [Bundle] {
    var components = languageCode.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
    var bundles: [Bundle] = []
    while !components.isEmpty {
        if let bundle = _localizedFallbackBundles[components.joined(separator: "-")] {
            bundles.append(bundle)
        }
        components.removeLast()
    }
    return bundles
}

private func bundledLocalizedString(_ key: String, in bundles: [Bundle]) -> String? {
    for bundle in bundles {
        let value = NSLocalizedString(key, bundle: bundle, comment: "")
        if value != key && !value.isEmpty {
            return value
        }
    }
    return nil
}

/// Single combined lookup used by `translate`. Returning `String?` lets the
/// caller skip a second exist+fetch round-trip when a key is missing.
/// When `returnNilIfMissing` is false, mirrors `_NSLocalizedString` and
/// returns the raw key as a last resort (matches `NSLocalizedString` default
/// behavior when the key is absent from the bundle).
internal func _LocalizedStringFor(_ key: String, primary: Language, secondary: Language?, returnNilIfMissing: Bool = false) -> String? {
    if let value = primary.strings[key], !value.isEmpty {
        return value
    }
    if let value = secondary?.strings[key], !value.isEmpty {
        return value
    }
    if let value = bundledLocalizedString(key, in: primary.bundledFallbacks) {
        return value
    }
    if let secondary, let value = bundledLocalizedString(key, in: secondary.bundledFallbacks) {
        return value
    }
    if let bundle = _englishFallbackBundle {
        let resolved = NSLocalizedString(key, bundle: bundle, comment: "")
        if returnNilIfMissing && resolved == key {
            return nil
        }
        return resolved
    }
    let resolved = NSLocalizedString(key, comment: "")
    if returnNilIfMissing && resolved == key {
        return nil
    }
    return resolved
}

public func _NSLocalizedString(_ key: String) -> String {
    let language = appCurrentLanguage
    return _LocalizedStringFor(key, primary: language.primaryLanguage, secondary: language.secondaryLanguage) ?? key
}

public func NativeLocalization(_ key: String) -> String {
    if let bundle = _englishFallbackBundle {
        return NSLocalizedString(key, bundle: bundle, comment: "")
    }
    return NSLocalizedString(key, comment: "")
}


public func strings() -> L10n.Type {
    return L10n.self
}
