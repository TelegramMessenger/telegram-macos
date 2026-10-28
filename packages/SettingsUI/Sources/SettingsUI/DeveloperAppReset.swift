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

    func performAndRelaunch(accountBasePath: String) throws {
        let process = Self.relaunchProcess(bundleURL: Bundle.main.bundleURL, parentProcessIdentifier: ProcessInfo.processInfo.processIdentifier)
        try process.run()
        perform(accountBasePath: accountBasePath)
    }

    static func relaunchProcess(bundleURL: URL, parentProcessIdentifier: Int32, openerURL: URL = URL(fileURLWithPath: "/usr/bin/open")) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            """
            while /bin/kill -0 "$1" 2>/dev/null; do
                /bin/sleep 0.1
            done
            exec "$2" -n "$3"
            """,
            "telegram-reset-relaunch",
            String(parentProcessIdentifier),
            openerURL.path,
            bundleURL.path
        ]
        return process
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
