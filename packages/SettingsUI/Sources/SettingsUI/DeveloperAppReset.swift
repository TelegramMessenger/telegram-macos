import Foundation

enum DeveloperAppReset {
    case database
    case databaseAndCache

    var title: String {
        switch self {
        case .database:
            return "Clear Database"
        case .databaseAndCache:
            return "Clear Database and Cache"
        }
    }

    func performAndRelaunch(accountBasePath: String, process: Process) throws {
        try process.run()
        perform(accountBasePath: accountBasePath)
    }

    func perform(accountBasePath: String, terminate: () -> Void = { exit(0) }) {
        let path: String
        switch self {
        case .database:
            path = accountBasePath + "/postbox/db"
        case .databaseAndCache:
            path = accountBasePath + "/postbox"
        }
        let _ = try? FileManager.default.removeItem(atPath: path)
        terminate()
    }
}
