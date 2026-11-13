import Foundation
import Localization

func chatListFocusEmptyText(language: TelegramLocalization = appCurrentLanguage, bundle: Bundle = .main) -> String {
    focusFilterText("ChatList.Filter.EmptyFocus", fallback: "All chats in this folder are hidden by Focus settings.", language: language, bundle: bundle)
}

public func focusFilterConfigurationWarning(language: TelegramLocalization = appCurrentLanguage, bundle: Bundle = .main) -> (title: String, message: String) {
    let title = focusFilterText("FocusFilter.Unavailable.Title", fallback: "Focus filter unavailable", language: language, bundle: bundle)
    let message = focusFilterText("FocusFilter.Unavailable.Message", fallback: "Telegram couldn’t load the Focus filter. Chat notifications for all accounts will follow your usual Telegram and macOS settings until the filter loads. To reapply it, open System Settings → Focus, select your Focus and save the Telegram filter again.", language: language, bundle: bundle)
    return (title, message)
}

private func focusFilterText(_ key: String, fallback: String, language: TelegramLocalization, bundle: Bundle) -> String {
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
    return fallback
}
