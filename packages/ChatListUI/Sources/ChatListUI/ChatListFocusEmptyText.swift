import Foundation
import Localization

func chatListFocusEmptyText(language: TelegramLocalization = appCurrentLanguage, bundle: Bundle = .main) -> String {
    let key = "ChatList.Filter.EmptyFocus"
    for translation in [language.primaryLanguage.strings[key], language.secondaryLanguage?.strings[key]] {
        if let translation, !translation.isEmpty {
            return translation
        }
    }
    let fallbackLanguage = [language.primaryLanguage.languageCode, language.secondaryLanguage?.languageCode].compactMap { code -> String? in
        guard let code else {
            return nil
        }
        let languageCode = code.lowercased().replacingOccurrences(of: "_", with: "-").split(separator: "-").first.map(String.init)
        return languageCode == "ru" || languageCode == "en" ? languageCode : nil
    }.first ?? "en"
    if let path = bundle.path(forResource: fallbackLanguage, ofType: "lproj"), let localizedBundle = Bundle(path: path) {
        let value = localizedBundle.localizedString(forKey: key, value: nil, table: nil)
        if value != key {
            return value
        }
    }
    return "All chats in this folder are hidden by Focus settings."
}
