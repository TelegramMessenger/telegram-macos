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
    let resetProcessIdentifier: Int32?
}

public struct DeveloperAppResetBackupStore {
    private static let queue = Queue(name: "DeveloperAppResetBackup")
    private static let table = ValueBoxTable(id: 0, keyType: .int64, compactValuesOnCreation: false)
    public let accountId: AccountRecordId
    private let path: String
    private let lockPath: String
    private let encryptionParameters: ValueBoxEncryptionParameters

    public init(accountBasePath: String, accountId: AccountRecordId, encryptionParameters: ValueBoxEncryptionParameters) {
        self.path = accountBasePath + "/developer-reset-backup"
        self.lockPath = accountBasePath + "/.developer-reset-backup.lock"
        self.accountId = accountId
        self.encryptionParameters = ValueBoxEncryptionParameters(forceEncryptionIfNoSet: true, key: encryptionParameters.key, salt: encryptionParameters.salt)
    }

    private var key: ValueBoxKey {
        let key = ValueBoxKey(length: 8)
        key.setInt64(0, value: accountId.int64)
        return key
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        var result: Result<T, Error>!
        Self.queue.sync {
            result = Result {
                let descriptor = open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
                guard descriptor >= 0 else { throw DeveloperAppResetBackupError.unavailable }
                defer { close(descriptor) }
                while flock(descriptor, LOCK_EX) != 0 {
                    if errno != EINTR { throw DeveloperAppResetBackupError.unavailable }
                }
                defer { flock(descriptor, LOCK_UN) }
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

    public func save(_ backup: AccountBackupData, resetProcessIdentifier: Int32? = getpid()) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try withLock {
            if resetProcessIdentifier == nil, (try? loadUnlocked()) != nil {
                return
            }
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
            let canCompleteRestoration: Bool
            if let pid = backup.resetProcessIdentifier {
                canCompleteRestoration = kill(pid, 0) != 0 && errno == ESRCH
            } else {
                canCompleteRestoration = true
            }
            return DeveloperAppResetBackup(data: backup.data, generation: backup.generation, canCompleteRestoration: canCompleteRestoration)
        }
    }

    public func loadForRestoration() throws -> DeveloperAppResetBackup? {
        if !FileManager.default.fileExists(atPath: (path as NSString).deletingLastPathComponent) {
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

public func saveDeveloperAppResetBackup(_ backup: AccountBackupData?, store: DeveloperAppResetBackupStore, accountManager: AccountManager<TelegramAccountManagerTypes>, forPendingReset: Bool = true) -> Signal<Bool, NoError> {
    guard let backup else {
        return .single(false)
    }
    do {
        try store.save(backup, resetProcessIdentifier: forPendingReset ? getpid() : nil)
    } catch {
        try? store.remove()
        return .single(false)
    }
    return accountManager.transaction { transaction in
        var saved = false
        transaction.updateRecord(store.accountId) { record in
            guard let record else {
                return nil
            }
            let attributes = record.attributes.filter { attribute in
                if case .backupData = attribute {
                    return false
                }
                return true
            }
            saved = true
            return AccountRecord(id: record.id, attributes: attributes, temporarySessionId: record.temporarySessionId)
        }
        if !saved {
            try? store.remove()
        }
        return saved
    }
}

public func loadDeveloperAppResetBackup(legacyBackup: AccountBackupData?, store: DeveloperAppResetBackupStore, accountManager: AccountManager<TelegramAccountManagerTypes>) -> Signal<DeveloperAppResetBackup?, DeveloperAppResetBackupError> {
    if let legacyBackup {
        return saveDeveloperAppResetBackup(legacyBackup, store: store, accountManager: accountManager, forPendingReset: false)
        |> castError(DeveloperAppResetBackupError.self)
        |> mapToSignal { saved in
            if saved {
                return loadDeveloperAppResetBackup(legacyBackup: nil, store: store, accountManager: accountManager)
            }
            return .fail(.unavailable)
        }
    }
    do {
        return .single(try store.loadForRestoration())
    } catch {
        return .fail(.unavailable)
    }
}
