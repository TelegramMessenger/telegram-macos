import Foundation

public struct FocusFilterStorageLocation: Equatable {
    public let directory: URL
    public let notificationName: String

    public init(container: URL, appGroupIdentifier: String, buildChannel: String) {
        directory = container.appendingPathComponent(buildChannel, isDirectory: true).appendingPathComponent("FocusFilters", isDirectory: true)
        notificationName = "\(appGroupIdentifier).FocusFilters.\(buildChannel)"
    }

    public static func resolve(appGroupIdentifier: String, buildSource: String?) throws -> Self {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            throw FocusFilterStorageError.unavailableAppGroup
        }
        return Self(container: container, appGroupIdentifier: appGroupIdentifier, buildChannel: channel(for: buildSource))
    }

    public static func channel(for buildSource: String?) -> String {
        switch buildSource {
        case "DEBUG": return "debug"
        case "STABLE": return "stable"
        case "APP_STORE": return "appstore"
        default: return "beta"
        }
    }
}

public enum FocusFilterStorageError: Error {
    case unavailableAppGroup
}
