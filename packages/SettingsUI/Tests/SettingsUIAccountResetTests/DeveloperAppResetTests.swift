import Foundation
import XCTest
import FoundationUtils
@testable import SettingsUI

final class DeveloperAppResetTests: XCTestCase {
    private var root: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        root = fileManager.temporaryDirectory.appendingPathComponent("DeveloperAppResetTests-" + UUID().uuidString)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try fileManager.removeItem(at: root)
        root = nil
    }

    func testResetsPreserveCacheAndNeighboringAccountsAsAppropriate() throws {
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

            XCTAssertTrue(terminations == 1, "Reset must terminate exactly once")
            XCTAssertTrue(databaseWasRemovedBeforeTermination, "Database must be removed before termination")
            switch action {
            case .database:
                XCTAssertTrue(fileManager.fileExists(atPath: cache.appendingPathComponent("data").path), "Database reset must preserve cached media")
            case .databaseAndCache:
                XCTAssertTrue(!fileManager.fileExists(atPath: account.appendingPathComponent("postbox").path), "Full reset must remove the entire postbox")
            }
            XCTAssertTrue(try Data(contentsOf: otherAccount.appendingPathComponent("data")) == Data("fixture".utf8), "Reset must preserve other accounts")
            XCTAssertTrue(try Data(contentsOf: accountManager) == Data("accounts".utf8), "Reset must preserve account-manager metadata")
            XCTAssertTrue(try Data(contentsOf: accountMetadata) == Data("account".utf8), "Reset must preserve files outside postbox")
        }
    }

    func testMissingAndInvalidTargetsStillTerminateWithoutDeletingParents() throws {
        for action in [DeveloperAppReset.database, .databaseAndCache] {
            var terminations = 0
            action.perform(accountBasePath: root.appendingPathComponent("missing-account").path) {
                terminations += 1
            }
            XCTAssertTrue(terminations == 1, "A missing reset target must still terminate, matching iOS")

            let invalidAccount = root.appendingPathComponent(UUID().uuidString)
            try Data("preserve".utf8).write(to: invalidAccount)
            action.perform(accountBasePath: invalidAccount.path) {
                terminations += 1
            }
            XCTAssertTrue(terminations == 2, "A removal error must still terminate, matching iOS")
            XCTAssertTrue(try Data(contentsOf: invalidAccount) == Data("preserve".utf8), "An invalid target must not delete its parent")
        }
    }

    func testRelaunchWaitsForExitAndPreservesBundlePath() throws {
        let opener = root.appendingPathComponent("fixture opener.sh")
        let record = root.appendingPathComponent("relaunch-arguments")
        let bundle = root.appendingPathComponent("Telegram's $HOME \"fixture\".app")
        let script = """
        #!/bin/sh
        printf '%s\n' "$@" >> "$DEVELOPER_RELAUNCH_RECORD"
        if /bin/kill -0 "$DEVELOPER_RELAUNCH_PARENT" 2>/dev/null; then
            printf 'alive\n' >> "$DEVELOPER_RELAUNCH_RECORD"
        else
            printf 'exited\n' >> "$DEVELOPER_RELAUNCH_RECORD"
        fi
        """
        try Data(script.utf8).write(to: opener)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: opener.path)

        let parent = Process()
        parent.executableURL = URL(fileURLWithPath: "/bin/sleep")
        parent.arguments = ["30"]
        try parent.run()
        defer {
            if parent.isRunning {
                parent.terminate()
                parent.waitUntilExit()
            }
        }

        let relaunch = appRelaunchProcess(bundleURL: bundle, parentProcessIdentifier: parent.processIdentifier, openerURL: opener)
        relaunch.environment = ["DEVELOPER_RELAUNCH_RECORD": record.path, "DEVELOPER_RELAUNCH_PARENT": String(parent.processIdentifier)]
        try relaunch.run()
        defer {
            if relaunch.isRunning {
                relaunch.terminate()
                relaunch.waitUntilExit()
            }
        }
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertTrue(!fileManager.fileExists(atPath: record.path), "Relaunch must wait until the old process exits")
        parent.terminate()
        parent.waitUntilExit()

        let deadline = Date(timeIntervalSinceNow: 5)
        while relaunch.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        guard !relaunch.isRunning else {
            XCTFail("Relaunch must open the app after the old process exits")
            return
        }
        relaunch.waitUntilExit()
        XCTAssertTrue(relaunch.terminationStatus == 0, "Relaunch helper must finish successfully")
        let arguments = try String(contentsOf: record, encoding: .utf8)
        XCTAssertTrue(arguments == "-n\n" + bundle.path + "\nexited\n", "Relaunch must preserve the bundle path and open exactly once after exit")
    }
}
