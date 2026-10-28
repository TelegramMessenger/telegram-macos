import Foundation
import XCTest
import Postbox
import SwiftSignalKit
import TelegramCore
import AccountResetSupport
import BuildConfig
@testable import SettingsUI

final class DeveloperAppResetBackupTests: XCTestCase {
    private func value<T>(_ signal: Signal<T, NoError>) throws -> T {
        var result: T?
        let completed = expectation(description: "Transaction committed")
        let disposable = signal.start(next: { value in
            result = value
            completed.fulfill()
        })
        defer { disposable.dispose() }
        wait(for: [completed], timeout: 5)
        return try XCTUnwrap(result)
    }

    private func withManager(_ body: (AccountManager<TelegramAccountManagerTypes>, URL, String) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DeveloperAppResetBackupTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("accounts-metadata").path
        let manager = AccountManager<TelegramAccountManagerTypes>(basePath: path, isTemporary: false, isReadOnly: false, useCaches: false, removeDatabaseOnError: true, accessChallenge: .init(prepare: { _ in }, resolve: { current, _ in current }, finishInitialization: {}))
        try body(manager, root, path)
    }

    private func backup(peerId: Int64) -> AccountBackupData {
        return AccountBackupData(masterDatacenterId: 2, peerId: peerId, masterDatacenterKey: Data(repeating: 0x31, count: 256), masterDatacenterKeyId: 42, notificationEncryptionKeyId: Data(repeating: 0x52, count: 8), notificationEncryptionKey: Data(repeating: 0x63, count: 256), additionalDatacenterKeys: [4: .init(id: 4, keyId: 84, key: Data(repeating: 0x74, count: 256))])
    }

    private func makeStore(root: URL, id: AccountRecordId, keyByte: UInt8 = 0x25) -> DeveloperAppResetBackupStore {
        return DeveloperAppResetBackupStore(accountBasePath: root.path, accountId: id, encryptionParameters: ValueBoxEncryptionParameters(forceEncryptionIfNoSet: true, key: .init(data: Data(repeating: keyByte, count: 32))!, salt: .init(data: Data(repeating: 0x36, count: 16))!))
    }

    private func assertNoPlaintextCredentials(root: URL, backup: AccountBackupData) throws {
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]))
        let keys = [backup.masterDatacenterKey, backup.notificationEncryptionKey!] + backup.additionalDatacenterKeys.values.map { $0.key }
        for case let file as URL in files {
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let data = try Data(contentsOf: file)
            for key in keys {
                XCTAssertNil(data.range(of: key), file.lastPathComponent)
                XCTAssertNil(data.range(of: Data(key.base64EncodedString().utf8)), file.lastPathComponent)
            }
        }
    }

    private func recordBackup(_ record: AccountRecord<TelegramAccountManagerTypes.Attribute>) -> [AccountBackupData?] {
        return record.attributes.compactMap { attribute -> AccountBackupDataAttribute? in
            if case let .backupData(value) = attribute {
                return value
            }
            return nil
        }.map { $0.data }
    }

    func testBothResetsKeepSelectedAccountCredentialsWithOneOrTwoAccounts() throws {
        for count in [1, 2] {
            for action in [DeveloperAppReset.database, .databaseAndCache] {
                for selectedIndex in 0 ..< count {
                    try withManager { manager, root, metadataPath in
                        let ids = try value(manager.transaction { transaction in
                            let ids = (0 ..< count).map { index in
                                return transaction.createRecord([
                                    .environment(AccountEnvironmentAttribute(environment: .test)),
                                    .sortOrder(AccountSortOrderAttribute(order: Int32(index))),
                                ])
                            }
                            transaction.setCurrentId(ids[selectedIndex])
                            return ids
                        })
                        let selectedId = ids[selectedIndex]
                        let initial = AccountManager<TelegramAccountManagerTypes>.getCurrentRecords(basePath: metadataPath)
                        let selectedBackup = backup(peerId: 200)
                        let accountPath = root.appendingPathComponent("account-current")
                        let store = makeStore(root: accountPath, id: selectedId)
                        XCTAssertTrue(try value(saveDeveloperAppResetBackup(selectedBackup, store: store, accountManager: manager)))
                        try assertNoPlaintextCredentials(root: root, backup: selectedBackup)
                        for relativePath in ["postbox/db", "postbox/media"] {
                            let directory = accountPath.appendingPathComponent(relativePath)
                            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                            try Data("disposable".utf8).write(to: directory.appendingPathComponent("data"))
                        }
                        var terminated = false
                        action.perform(accountBasePath: accountPath.path) { terminated = true }
                        XCTAssertTrue(terminated)

                        let restored = AccountManager<TelegramAccountManagerTypes>.getCurrentRecords(basePath: metadataPath)
                        XCTAssertEqual(restored.currentId, selectedId)
                        XCTAssertEqual(restored.records.count, count)
                        let record = try XCTUnwrap(restored.records.first(where: { $0.id == selectedId }))
                        XCTAssertEqual(recordBackup(record), [])
                        XCTAssertEqual(try store.load(), selectedBackup)
                        XCTAssertEqual(record.temporarySessionId, initial.records.first(where: { $0.id == selectedId })?.temporarySessionId)
                        XCTAssertTrue(record.attributes.contains(.environment(AccountEnvironmentAttribute(environment: .test))))
                        XCTAssertTrue(record.attributes.contains(.sortOrder(AccountSortOrderAttribute(order: Int32(selectedIndex)))))
                        if count == 2 {
                            let neighborId = ids[1 - selectedIndex]
                            XCTAssertEqual(restored.records.first(where: { $0.id == neighborId }), initial.records.first(where: { $0.id == neighborId }))
                        }
                        XCTAssertFalse(FileManager.default.fileExists(atPath: accountPath.appendingPathComponent("postbox/db").path))
                        switch action {
                        case .database:
                            XCTAssertTrue(FileManager.default.fileExists(atPath: accountPath.appendingPathComponent("postbox/media/data").path))
                        case .databaseAndCache:
                            XCTAssertFalse(FileManager.default.fileExists(atPath: accountPath.appendingPathComponent("postbox").path))
                        }
                    }
                }
            }
        }
    }

    func testMissingCredentialsLeaveExistingBackupIntact() throws {
        try withManager { manager, root, metadataPath in
            let existingBackup = backup(peerId: 100)
            let id = try value(manager.transaction { transaction in
                return transaction.createRecord([.backupData(AccountBackupDataAttribute(data: existingBackup))])
            })
            XCTAssertFalse(try value(saveDeveloperAppResetBackup(nil, store: makeStore(root: root, id: id), accountManager: manager)))
            let records = AccountManager<TelegramAccountManagerTypes>.getCurrentRecords(basePath: metadataPath).records
            XCTAssertEqual(recordBackup(try XCTUnwrap(records.first)), [existingBackup])
        }
    }

    func testMissingAccountDoesNotCreateAnAccountOrReportSuccess() throws {
        try withManager { manager, root, metadataPath in
            _ = try value(manager.transaction { _ in true })
            XCTAssertFalse(try value(saveDeveloperAppResetBackup(backup(peerId: 200), store: makeStore(root: root, id: AccountRecordId(rawValue: 999)), accountManager: manager)))
            XCTAssertTrue(AccountManager<TelegramAccountManagerTypes>.getCurrentRecords(basePath: metadataPath).records.isEmpty)
        }
    }

    func testWrongKeyOrAccountCannotReadBackupAndDoesNotDestroyIt() throws {
        try withManager { manager, root, _ in
            let id = try value(manager.transaction { $0.createRecord([]) })
            let store = makeStore(root: root, id: id)
            let credentials = backup(peerId: 200)
            XCTAssertTrue(try value(saveDeveloperAppResetBackup(credentials, store: store, accountManager: manager)))
            XCTAssertThrowsError(try makeStore(root: root, id: id, keyByte: 0x99).load())
            XCTAssertThrowsError(try makeStore(root: root, id: AccountRecordId(rawValue: 999)).load())
            XCTAssertEqual(try store.load(), credentials)
            try assertNoPlaintextCredentials(root: root, backup: credentials)
        }
    }

    func testFailedRelaunchRemovesEncryptedBackupAndKeepsDatabase() throws {
        try withManager { manager, root, metadataPath in
            let id = try value(manager.transaction { $0.createRecord([]) })
            let store = makeStore(root: root, id: id)
            let credentials = backup(peerId: 200)
            let database = root.appendingPathComponent("postbox/db")
            try FileManager.default.createDirectory(at: database, withIntermediateDirectories: true)
            for action in [DeveloperAppReset.database, .databaseAndCache] {
                XCTAssertTrue(try value(saveDeveloperAppResetBackup(credentials, store: store, accountManager: manager)))
                let process = Process()
                process.executableURL = root.appendingPathComponent("missing-relaunch-helper")
                XCTAssertThrowsError(try action.performAndRelaunch(accountBasePath: root.path, backupStore: store, process: process))
                XCTAssertNil(try store.load())
                XCTAssertTrue(FileManager.default.fileExists(atPath: database.path))
                let record = try XCTUnwrap(AccountManager<TelegramAccountManagerTypes>.getCurrentRecords(basePath: metadataPath).records.first)
                XCTAssertTrue(recordBackup(record).isEmpty)
                try assertNoPlaintextCredentials(root: root, backup: credentials)
            }
        }
    }

    func testLegacyBackupMigratesOutOfPlaintextMetadataBeforeRestoration() throws {
        try withManager { manager, root, metadataPath in
            let credentials = backup(peerId: 200)
            let id = try value(manager.transaction { transaction in
                let id = transaction.createRecord([.backupData(AccountBackupDataAttribute(data: credentials))])
                transaction.setCurrentId(id)
                return id
            })
            let store = makeStore(root: root, id: id)
            let loaded = try value(loadDeveloperAppResetBackup(legacyBackup: credentials, store: store, accountManager: manager) |> map { $0 } |> `catch` { _ in .single(nil) })
            XCTAssertEqual(loaded?.data, credentials)
            XCTAssertEqual(try store.load(), credentials)
            let record = try XCTUnwrap(AccountManager<TelegramAccountManagerTypes>.getCurrentRecords(basePath: metadataPath).records.first)
            XCTAssertTrue(recordBackup(record).isEmpty)
            try assertNoPlaintextCredentials(root: root, backup: credentials)
            try store.completeRestoration(loaded)
            XCTAssertNil(try store.load())
        }
    }

    func testBackupStaysEncryptedUntilPasscodeUnlockAndSurvivesPasscodeChanges() throws {
        try withManager { manager, root, _ in
            let id = try value(manager.transaction { $0.createRecord([]) })
            let encryption = AppEncryptionParameters(path: root.path)
            encryption.change("1234")
            let parameters = try XCTUnwrap(encryption.decrypt())
            func store(_ parameters: DeviceSpecificEncryptionParameters) throws -> DeveloperAppResetBackupStore {
                return DeveloperAppResetBackupStore(accountBasePath: root.path, accountId: id, encryptionParameters: ValueBoxEncryptionParameters(forceEncryptionIfNoSet: true, key: try XCTUnwrap(.init(data: parameters.key)), salt: try XCTUnwrap(.init(data: parameters.salt))))
            }
            let credentials = backup(peerId: 200)
            let originalStore = try store(parameters)
            XCTAssertTrue(try value(saveDeveloperAppResetBackup(credentials, store: originalStore, accountManager: manager)))
            let locked = AppEncryptionParameters(path: root.path)
            XCTAssertNil(locked.decrypt())
            try assertNoPlaintextCredentials(root: root, backup: credentials)
            locked.applyPasscode("1234")
            XCTAssertEqual(try store(XCTUnwrap(locked.decrypt())).load(), credentials)
            locked.change("5678")
            let changed = AppEncryptionParameters(path: root.path)
            XCTAssertNil(changed.decrypt())
            changed.applyPasscode("5678")
            XCTAssertEqual(try store(XCTUnwrap(changed.decrypt())).load(), credentials)
            try originalStore.remove()
        }
    }

    func testUnreadableBackupIsRetainedAndRestorationFailsSafely() throws {
        try withManager { manager, root, metadataPath in
            let id = try value(manager.transaction { $0.createRecord([]) })
            let directory = root.appendingPathComponent("developer-reset-backup")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent("db_sqlite")
            let invalid = Data("invalid database".utf8)
            try invalid.write(to: file)
            let store = makeStore(root: root, id: id)
            XCTAssertThrowsError(try store.load())
            let failed = expectation(description: "Invalid backup is not treated as absent")
            let disposable = loadDeveloperAppResetBackup(legacyBackup: nil, store: store, accountManager: manager).start(next: { _ in XCTFail("Invalid backup must fail") }, error: { _ in failed.fulfill() })
            defer { disposable.dispose() }
            wait(for: [failed], timeout: 5)
            XCTAssertEqual(try Data(contentsOf: file), invalid)
            XCTAssertEqual(AccountManager<TelegramAccountManagerTypes>.getCurrentRecords(basePath: metadataPath).records.map { $0.id }, [id])
        }
    }

    func testOtherProcessCannotConsumeBackupWhileResetProcessIsAlive() throws {
        try withManager { _, root, _ in
            let store = makeStore(root: root, id: AccountRecordId(rawValue: 1))
            let writer = Process()
            writer.executableURL = URL(fileURLWithPath: "/bin/sleep")
            writer.arguments = ["30"]
            try writer.run()
            defer {
                if writer.isRunning {
                    writer.terminate()
                    writer.waitUntilExit()
                }
            }
            let credentials = backup(peerId: 200)
            try store.save(credentials, resetProcessIdentifier: writer.processIdentifier)
            let earlyReader = try XCTUnwrap(store.loadForRestoration())
            try store.completeRestoration(earlyReader)
            XCTAssertEqual(try store.load(), credentials)
            writer.terminate()
            writer.waitUntilExit()
            try store.completeRestoration(earlyReader)
            XCTAssertEqual(try store.load(), credentials)
            let relaunchReader = try XCTUnwrap(store.loadForRestoration())
            try store.completeRestoration(relaunchReader)
            XCTAssertNil(try store.load())
        }
    }

    func testStaleRestorationCannotRemoveANewerResetBackup() throws {
        try withManager { _, root, _ in
            let store = makeStore(root: root, id: AccountRecordId(rawValue: 1))
            try store.save(backup(peerId: 100), resetProcessIdentifier: nil)
            let staleReader = try XCTUnwrap(store.loadForRestoration())
            let current = backup(peerId: 200)
            try store.save(current)
            try store.completeRestoration(staleReader)
            XCTAssertEqual(try store.load(), current)
        }
    }

    func testInterruptedPreparationIsNotPublishedForRestoration() throws {
        try withManager { _, root, _ in
            let staging = root.appendingPathComponent("developer-reset-backup.preparing-interrupted")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try Data("partial database".utf8).write(to: staging.appendingPathComponent("db_sqlite"))
            let store = makeStore(root: root, id: AccountRecordId(rawValue: 1))
            XCTAssertNil(try store.load())
            let credentials = backup(peerId: 200)
            try store.save(credentials)
            XCTAssertEqual(try store.load(), credentials)
        }
    }

    func testLegacyMigrationCannotReplaceAPendingReset() throws {
        try withManager { manager, root, _ in
            let legacy = backup(peerId: 100)
            let current = backup(peerId: 200)
            let id = try value(manager.transaction { $0.createRecord([.backupData(AccountBackupDataAttribute(data: legacy))]) })
            let store = makeStore(root: root, id: id)
            try store.save(current)
            let loaded = try value(loadDeveloperAppResetBackup(legacyBackup: legacy, store: store, accountManager: manager) |> `catch` { _ in .single(nil) })
            XCTAssertEqual(loaded?.data, current)
            try store.completeRestoration(loaded)
            XCTAssertEqual(try store.load(), current)
        }
    }

}
