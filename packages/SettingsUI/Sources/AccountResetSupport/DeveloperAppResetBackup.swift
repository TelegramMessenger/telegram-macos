import Foundation
import Darwin
import Postbox
import SwiftSignalKit
import TelegramCore

public enum DeveloperAppResetBackupError: Error {
    case unavailable
    case invalidData
}

public struct DeveloperAppResetBackup {
    public let data: AccountBackupData
    fileprivate let generation: String
    fileprivate let canCompleteRestoration: Bool
}

private struct StoredResetBackup: Codable {
    let data: AccountBackupData
    let generation: String
    let resetProcessIdentifier: Int32
}

public struct DeveloperAppResetBackupStore {
    fileprivate static let queue = Queue(name: "DeveloperAppResetBackup")
    private static let table = ValueBoxTable(id: 0, keyType: .int64, compactValuesOnCreation: false)
    public let accountId: AccountRecordId
    private let path: String
    private let accountBasePath: String
    private let encryptionParameters: ValueBoxEncryptionParameters

    public init(accountBasePath: String, accountId: AccountRecordId, encryptionParameters: ValueBoxEncryptionParameters) {
        self.path = accountBasePath + "/developer-reset-backup"
        self.accountBasePath = accountBasePath
        self.accountId = accountId
        self.encryptionParameters = ValueBoxEncryptionParameters(forceEncryptionIfNoSet: true, key: encryptionParameters.key, salt: encryptionParameters.salt)
    }

    private var key: ValueBoxKey {
        let key = ValueBoxKey(length: 8)
        key.setInt64(0, value: accountId.int64)
        return key
    }

    private func isStagingDirectory(_ name: String) -> Bool {
        let prefix = "developer-reset-backup.preparing-"
        return name.hasPrefix(prefix) && UUID(uuidString: String(name.dropFirst(prefix.count))) != nil
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        var result: Result<T, Error>!
        Self.queue.sync {
            result = Result {
                let descriptor = open(accountBasePath, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                guard descriptor >= 0 else { throw DeveloperAppResetBackupError.unavailable }
                defer { close(descriptor) }
                while flock(descriptor, LOCK_EX) != 0 {
                    if errno != EINTR { throw DeveloperAppResetBackupError.unavailable }
                }
                defer { flock(descriptor, LOCK_UN) }
                for name in try FileManager.default.contentsOfDirectory(atPath: accountBasePath) where isStagingDirectory(name) {
                    try FileManager.default.removeItem(atPath: accountBasePath + "/" + name)
                }
                return try body()
            }
        }
        return try result.get()
    }

    private func access<T>(path: String, readOnly: Bool, _ body: (SqliteValueBox) throws -> T) throws -> T {
        var result: Result<T, Error>!
        Self.queue.sync {
            result = Result {
                let isNewDatabase = !FileManager.default.fileExists(atPath: path + "/db_sqlite")
                guard let box = SqliteValueBox(basePath: path, queue: Self.queue, isTemporary: false, isReadOnly: readOnly, useCaches: false, removeDatabaseOnError: !readOnly && isNewDatabase, encryptionParameters: encryptionParameters, upgradeProgress: { _ in }) else {
                    throw DeveloperAppResetBackupError.unavailable
                }
                return try body(box)
            }
        }
        return try result.get()
    }

    public func save(_ backup: AccountBackupData, resetProcessIdentifier: Int32 = getpid()) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try withLock {
            let data = try JSONEncoder().encode(StoredResetBackup(data: backup, generation: UUID().uuidString, resetProcessIdentifier: resetProcessIdentifier))
            let stagingPath = path + ".preparing-" + UUID().uuidString
            try FileManager.default.createDirectory(atPath: stagingPath, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(atPath: stagingPath) }
            try access(path: stagingPath, readOnly: false) { box in
                box.begin()
                box.set(Self.table, key: key, value: MemoryBuffer(data: data))
                box.commit()
                box.checkpoint()
                guard box.get(Self.table, key: key)?.makeData() == data else {
                    throw DeveloperAppResetBackupError.invalidData
                }
            }
            try removeUnlocked()
            try FileManager.default.moveItem(atPath: stagingPath, toPath: path)
        }
    }

    public func load() throws -> AccountBackupData? {
        return try loadForRestoration()?.data
    }

    private func loadUnlocked() throws -> DeveloperAppResetBackup? {
        do {
            _ = try FileManager.default.attributesOfItem(atPath: path)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) {
            return nil
        }
        return try access(path: path, readOnly: true) { box in
            guard let data = box.get(Self.table, key: key)?.makeData(), let backup = try? JSONDecoder().decode(StoredResetBackup.self, from: data) else {
                throw DeveloperAppResetBackupError.invalidData
            }
            let canCompleteRestoration = kill(backup.resetProcessIdentifier, 0) != 0 && errno == ESRCH
            return DeveloperAppResetBackup(data: backup.data, generation: backup.generation, canCompleteRestoration: canCompleteRestoration)
        }
    }

    public func loadForRestoration() throws -> DeveloperAppResetBackup? {
        let names: [String]
        do {
            names = try FileManager.default.contentsOfDirectory(atPath: accountBasePath)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) {
            return nil
        }
        guard names.contains("developer-reset-backup") || names.contains(where: isStagingDirectory) else {
            return nil
        }
        return try withLock { try loadUnlocked() }
    }

    public func completeRestoration(_ backup: DeveloperAppResetBackup?) throws {
        guard let backup, backup.canCompleteRestoration else { return }
        try withLock {
            if try loadUnlocked()?.generation == backup.generation {
                try removeUnlocked()
            }
        }
    }

    private func removeUnlocked() throws {
        if FileManager.default.fileExists(atPath: path) {
            try FileManager.default.removeItem(atPath: path)
        }
    }

    public func remove() throws {
        try withLock { try removeUnlocked() }
    }

}

public func saveDeveloperAppResetBackup(_ backup: AccountBackupData?, store: DeveloperAppResetBackupStore, accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<Bool, NoError> {
    guard let backup else {
        return .single(false)
    }
    do {
        try store.save(backup)
    } catch {
        try? store.remove()
        return .single(false)
    }
    return accountManager.transaction { transaction in
        let saved = transaction.getRecords().contains { $0.id == store.accountId }
        if !saved {
            try? store.remove()
        }
        return saved
    }
}

public func loadDeveloperAppResetBackup(store: DeveloperAppResetBackupStore) -> Signal<DeveloperAppResetBackup?, DeveloperAppResetBackupError> {
    return deferred {
        do {
            return .single(try store.loadForRestoration())
        } catch {
            return .fail(.unavailable)
        }
    }
    |> runOn(DeveloperAppResetBackupStore.queue)
}
