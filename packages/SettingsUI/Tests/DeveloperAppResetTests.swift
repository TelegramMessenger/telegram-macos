import Foundation

private struct TestFailure: Error {
    let message: String
}

@main
private enum DeveloperAppResetTests {
    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        let result = try condition()
        if !result {
            throw TestFailure(message: message)
        }
    }

    static func main() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("DeveloperAppResetTests-" + UUID().uuidString)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        for (index, action) in [DeveloperAppReset.database, .databaseAndCache].enumerated() {
            let fixture = root.appendingPathComponent("fixture-\(index)")
            let account = fixture.appendingPathComponent("account-current")
            let database = account.appendingPathComponent("postbox/db")
            let cache = account.appendingPathComponent("postbox/media")
            let otherAccount = fixture.appendingPathComponent("account-other/postbox/db")
            let accountManager = fixture.appendingPathComponent("accounts-metadata")
            let accountMetadata = account.appendingPathComponent("network-metadata")
            for directory in [database, cache, otherAccount] {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
                try Data("fixture".utf8).write(to: directory.appendingPathComponent("data"))
            }
            try Data("accounts".utf8).write(to: accountManager)
            try Data("account".utf8).write(to: accountMetadata)

            var terminations = 0
            var databaseWasRemovedBeforeTermination = false
            action.perform(accountBasePath: account.path) {
                terminations += 1
                databaseWasRemovedBeforeTermination = !fileManager.fileExists(atPath: database.path)
            }

            try require(terminations == 1, "Reset must terminate exactly once")
            try require(databaseWasRemovedBeforeTermination, "Database must be removed before termination")
            switch action {
            case .database:
                try require(fileManager.fileExists(atPath: cache.appendingPathComponent("data").path), "Database reset must preserve cached media")
            case .databaseAndCache:
                try require(!fileManager.fileExists(atPath: account.appendingPathComponent("postbox").path), "Full reset must remove the entire postbox")
            }
            try require(try Data(contentsOf: otherAccount.appendingPathComponent("data")) == Data("fixture".utf8), "Reset must preserve other accounts")
            try require(try Data(contentsOf: accountManager) == Data("accounts".utf8), "Reset must preserve account-manager metadata")
            try require(try Data(contentsOf: accountMetadata) == Data("account".utf8), "Reset must preserve files outside postbox")
            print("Passed: \(action.title)")
        }

        for action in [DeveloperAppReset.database, .databaseAndCache] {
            var terminations = 0
            action.perform(accountBasePath: root.appendingPathComponent("missing-account").path) {
                terminations += 1
            }
            try require(terminations == 1, "A missing reset target must still terminate, matching iOS")

            let invalidAccount = root.appendingPathComponent(UUID().uuidString)
            try Data("preserve".utf8).write(to: invalidAccount)
            action.perform(accountBasePath: invalidAccount.path) {
                terminations += 1
            }
            try require(terminations == 2, "A removal error must still terminate, matching iOS")
            try require(try Data(contentsOf: invalidAccount) == Data("preserve".utf8), "An invalid target must not delete its parent")
            print("Passed: \(action.title) with missing or inaccessible postbox")
        }
    }
}
