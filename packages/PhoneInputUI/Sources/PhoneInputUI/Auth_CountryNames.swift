import Foundation
import TelegramCore
import PhoneNumberUtils
import TelegramTheme
import Localization

func localizedCountryName(_ country: Country) -> String {
    if country.countryCodes.first?.code == "999" {
        return country.name
    }
    if country.id == "FT" {
        return strings().loginAnonymousNumbers
    }
    return appAppearance.locale.localizedString(forRegionCode: country.id) ?? country.name
}

func countryTitle(_ country: Country) -> String {
    let name = localizedCountryName(country)
    let flag = emojiFlagForISOCountryCode(country.id)
    return flag.isEmpty ? name : flag + " " + name
}

extension Auth_CountryManager {
    public var displayList: [Country] {
        let locale = appAppearance.locale
        return self.list.map { country in
            return Country(id: country.id, name: localizedCountryName(country), localizedName: country.localizedName, countryCodes: country.countryCodes, hidden: country.hidden)
        }.sorted(by: { lhs, rhs in
            return lhs.name.compare(rhs.name, options: [.caseInsensitive, .diacriticInsensitive], locale: locale) == .orderedAscending
        })
    }
}
