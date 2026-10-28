import Foundation
import XCTest
import Postbox
import SwiftSignalKit
import TelegramCore
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
                        let neighborBackup = backup(peerId: 100)
                        let ids = try value(manager.transaction { transaction in
                            let ids = (0 ..< count).map { index in
                                return transaction.createRecord([
                                    .environment(AccountEnvironmentAttribute(environment: .test)),
                                    .sortOrder(AccountSortOrderAttribute(order: Int32(index))),
                                    .backupData(AccountBackupDataAttribute(data: neighborBackup)),
                                ])
                            }
                            transaction.setCurrentId(ids[selectedIndex])
                            return ids
                        })
                        let selectedId = ids[selectedIndex]
                        let initial = AccountManager<TelegramAccountManagerTypes>.getCurrentRecords(basePath: metadataPath)
                        let selectedBackup = backup(peerId: 200)
                        XCTAssertTrue(try value(saveDeveloperAppResetBackup(selectedBackup, accountId: selectedId, accountManager: manager)))

                        let accountPath = root.appendingPathComponent("account-current")
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
                        XCTAssertEqual(recordBackup(record), [selectedBackup])
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
        try withManager { manager, _, metadataPath in
            let existingBackup = backup(peerId: 100)
            let id = try value(manager.transaction { transaction in
                return transaction.createRecord([.backupData(AccountBackupDataAttribute(data: existingBackup))])
            })
            XCTAssertFalse(try value(saveDeveloperAppResetBackup(nil, accountId: id, accountManager: manager)))
            let records = AccountManager<TelegramAccountManagerTypes>.getCurrentRecords(basePath: metadataPath).records
            XCTAssertEqual(recordBackup(try XCTUnwrap(records.first)), [existingBackup])
        }
    }

    func testMissingAccountDoesNotCreateAnAccountOrReportSuccess() throws {
        try withManager { manager, _, metadataPath in
            _ = try value(manager.transaction { _ in true })
            XCTAssertFalse(try value(saveDeveloperAppResetBackup(backup(peerId: 200), accountId: AccountRecordId(rawValue: 999), accountManager: manager)))
            XCTAssertTrue(AccountManager<TelegramAccountManagerTypes>.getCurrentRecords(basePath: metadataPath).records.isEmpty)
        }
    }
}
