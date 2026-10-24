import Foundation

public enum Configuration : String {
    enum Error: Swift.Error {
        case missingKey, invalidValue
    }
    case source = "SOURCE"
    case apiId = "TELEGRAM_API_ID"
    case apiHash = "TELEGRAM_API_HASH"
    case bundleId = "TELEGRAM_BUNDLE_ID"
    case teamId = "TELEGRAM_TEAM_ID"
    
    public static func value(for key: Configuration) -> String? {
        guard let value = Bundle.main.infoDictionary?[key.rawValue] as? String else {
            return nil
        }
        return value
    }
}
