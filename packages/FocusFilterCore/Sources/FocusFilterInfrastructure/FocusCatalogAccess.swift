import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum FocusCatalogAccessError: Error {
    case invalidInstallation
    case unavailable
    case duplicateSession
}

public enum FocusCatalogAccessState: Equatable {
    case accessible
    case locked
    case unavailable
}

private struct FocusCatalogBundleIdentity {
    let bundleURL: URL
    let value: String

    init(bundleURL: URL) throws {
        guard let value = Self.identity(at: bundleURL) else {
            throw FocusCatalogAccessError.invalidInstallation
        }
        self.bundleURL = bundleURL
        self.value = value
    }

    var matchesLoadedExecutable: Bool {
        #if canImport(Darwin)
        guard let executable = FocusApplicationLocation.executableURL(in: bundleURL),
              let loaded = FocusExtensionInstallation.loadedExecutableUUID(),
              let installed = FocusExtensionInstallation.executableUUIDs(at: executable) else { return false }
        return installed.contains(loaded)
        #else
        return true
        #endif
    }

    var isCurrent: Bool {
        Self.identity(at: bundleURL) == value
    }

    private static func identity(at bundleURL: URL) -> String? {
        guard let executableURL = FocusApplicationLocation.executableURL(in: bundleURL) else { return nil }
        var directory = stat()
        var executable = stat()
        guard stat(bundleURL.path, &directory) == 0, directory.st_mode & S_IFMT == S_IFDIR,
              stat(executableURL.path, &executable) == 0, executable.st_mode & S_IFMT == S_IFREG else { return nil }
        #if canImport(Darwin)
        let modified = executable.st_mtimespec
        let changed = executable.st_ctimespec
        #else
        let modified = executable.st_mtim
        let changed = executable.st_ctim
        #endif
        return "\(directory.st_dev)-\(directory.st_ino)-\(executable.st_dev)-\(executable.st_ino)-\(executable.st_size)-\(modified.tv_sec)-\(modified.tv_nsec)-\(changed.tv_sec)-\(changed.tv_nsec)"
    }
}

private struct FocusCatalogAccessLocation {
    let extensionIdentity: FocusCatalogBundleIdentity
    let fileURL: URL

    init(storageDirectory: URL, applicationBundleURL: URL) throws {
        guard let extensionURL = FocusApplicationLocation.focusExtensionURL(containing: applicationBundleURL) else {
            throw FocusCatalogAccessError.invalidInstallation
        }
        extensionIdentity = try FocusCatalogBundleIdentity(bundleURL: extensionURL)
        fileURL = storageDirectory.standardizedFileURL.resolvingSymlinksInPath()
            .appendingPathComponent("CatalogAccess", isDirectory: true)
            .appendingPathComponent("extension-\(extensionIdentity.value)")
    }

    var isCurrent: Bool { extensionIdentity.isCurrent }
}

private enum FocusCatalogAccessFileError: Error {
    case missing
}

private enum FocusCatalogAccessSlot: Int64 {
    case presence = 0
    case denial = 1
    case initialization = 2
    case emergencyDenial = 3
}

private enum FocusCatalogAccessFiles {
    static let lock = NSLock()
    static var ownedPaths = Set<String>()

    static func openFile(_ url: URL, create: Bool) throws -> Int32 {
        let flags = (create ? O_RDWR | O_CREAT : O_RDONLY) | O_CLOEXEC | O_NOFOLLOW
        let descriptor = open(url.path, flags, mode_t(0o600))
        guard descriptor >= 0 else {
            if !create && errno == ENOENT { throw FocusCatalogAccessFileError.missing }
            throw FocusCatalogAccessError.unavailable
        }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
              metadata.st_uid == geteuid(), metadata.st_nlink == 1 else {
            close(descriptor)
            throw FocusCatalogAccessError.unavailable
        }
        return descriptor
    }

    static func isHealthy(_ descriptor: Int32) -> Bool {
        var value: UInt8 = 1
        return pread(descriptor, &value, 1, 0) == 1 && value == 0
    }

    static func resetFailure(_ descriptor: Int32) throws {
        var value: UInt8 = 0
        guard pwrite(descriptor, &value, 1, 0) == 1 else { throw FocusCatalogAccessError.unavailable }
    }

    static func recordFailure(_ descriptor: Int32) {
        var value: UInt8 = 1
        if pwrite(descriptor, &value, 1, 0) != 1 {
            _ = ftruncate(descriptor, 0)
        }
    }

    @discardableResult
    static func changeLock(_ descriptor: Int32, type: Int16, at slot: FocusCatalogAccessSlot, allowContention: Bool = false) throws -> Bool {
        var record = flock()
        record.l_type = type
        record.l_whence = Int16(SEEK_SET)
        record.l_start = off_t(slot.rawValue)
        record.l_len = 1
        if fcntl(descriptor, F_SETLK, &record) == 0 { return true }
        if allowContention && (errno == EACCES || errno == EAGAIN) { return false }
        throw FocusCatalogAccessError.unavailable
    }

    static func lockOwner(_ descriptor: Int32, at slot: FocusCatalogAccessSlot) throws -> pid_t? {
        var record = flock()
        record.l_type = Int16(F_WRLCK)
        record.l_whence = Int16(SEEK_SET)
        record.l_start = off_t(slot.rawValue)
        record.l_len = 1
        guard fcntl(descriptor, F_GETLK, &record) == 0 else { throw FocusCatalogAccessError.unavailable }
        if record.l_type == Int16(F_UNLCK) { return nil }
        guard (record.l_type == Int16(F_RDLCK) || (slot == .initialization && record.l_type == Int16(F_WRLCK))), record.l_pid > 0 else { throw FocusCatalogAccessError.unavailable }
        return record.l_pid
    }
}

public final class FocusCatalogAccessSession {
    private enum Initialization {
        case pending
        case ready
        case failed
    }

    private let location: FocusCatalogAccessLocation
    private let applicationIdentity: FocusCatalogBundleIdentity
    private var descriptor: Int32 = -1
    private var registered = false
    private var initialization = Initialization.pending

    public init(storageDirectory: URL, applicationBundleURL: URL) throws {
        location = try FocusCatalogAccessLocation(storageDirectory: storageDirectory, applicationBundleURL: applicationBundleURL)
        guard let applicationURL = FocusApplicationLocation.applicationURL(containing: applicationBundleURL) else {
            throw FocusCatalogAccessError.invalidInstallation
        }
        applicationIdentity = try FocusCatalogBundleIdentity(bundleURL: applicationURL)
        guard applicationIdentity.matchesLoadedExecutable else { throw FocusCatalogAccessError.invalidInstallation }
        FocusCatalogAccessFiles.lock.lock()
        defer { FocusCatalogAccessFiles.lock.unlock() }
        guard !FocusCatalogAccessFiles.ownedPaths.contains(location.fileURL.path) else {
            throw FocusCatalogAccessError.duplicateSession
        }
        try FileManager.default.createDirectory(at: location.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let descriptor = try FocusCatalogAccessFiles.openFile(location.fileURL, create: true)
        do {
            try FocusCatalogAccessFiles.changeLock(descriptor, type: Int16(F_RDLCK), at: .denial)
        } catch {
            do {
                try FocusCatalogAccessFiles.changeLock(descriptor, type: Int16(F_RDLCK), at: .presence)
                try FocusCatalogAccessFiles.changeLock(descriptor, type: Int16(F_RDLCK), at: .emergencyDenial)
            } catch {
                FocusCatalogAccessFiles.recordFailure(descriptor)
                close(descriptor)
                throw error
            }
            initialization = .failed
            FocusCatalogAccessFiles.recordFailure(descriptor)
        }
        self.descriptor = descriptor
        FocusCatalogAccessFiles.ownedPaths.insert(location.fileURL.path)
        registered = true
        do {
            try initializeIfPossible()
        } catch {
            initialization = .failed
            FocusCatalogAccessFiles.recordFailure(descriptor)
        }
    }

    private func initializeIfPossible() throws {
        guard initialization == .pending else { return }
        guard try FocusCatalogAccessFiles.changeLock(descriptor, type: Int16(F_WRLCK), at: .initialization, allowContention: true) else { return }
        do {
            if try FocusCatalogAccessFiles.lockOwner(descriptor, at: .presence) == nil {
                try FocusCatalogAccessFiles.resetFailure(descriptor)
            }
            try FocusCatalogAccessFiles.changeLock(descriptor, type: Int16(F_RDLCK), at: .presence)
            try FocusCatalogAccessFiles.changeLock(descriptor, type: Int16(F_UNLCK), at: .initialization)
            initialization = .ready
        } catch {
            _ = try? FocusCatalogAccessFiles.changeLock(descriptor, type: Int16(F_UNLCK), at: .initialization)
            throw error
        }
    }

    public func update(isUnlocked: Bool) throws {
        FocusCatalogAccessFiles.lock.lock()
        defer { FocusCatalogAccessFiles.lock.unlock() }
        guard descriptor >= 0, initialization != .failed else { throw FocusCatalogAccessError.unavailable }
        do {
            try initializeIfPossible()
            let permitted = initialization == .ready && isUnlocked && location.isCurrent && applicationIdentity.isCurrent && applicationIdentity.matchesLoadedExecutable && FocusCatalogAccessFiles.isHealthy(descriptor)
            try FocusCatalogAccessFiles.changeLock(descriptor, type: Int16(permitted ? F_UNLCK : F_RDLCK), at: .denial)
        } catch {
            initialization = .failed
            FocusCatalogAccessFiles.recordFailure(descriptor)
            throw error
        }
    }

    deinit {
        FocusCatalogAccessFiles.lock.lock()
        defer { FocusCatalogAccessFiles.lock.unlock() }
        if descriptor >= 0 { close(descriptor) }
        if registered { FocusCatalogAccessFiles.ownedPaths.remove(location.fileURL.path) }
    }
}

public final class FocusCatalogAccessReader {
    private let location: FocusCatalogAccessLocation
    private var isCurrentExtension: () -> Bool = { true }

    public init(storageDirectory: URL, applicationBundleURL: URL) throws {
        location = try FocusCatalogAccessLocation(storageDirectory: storageDirectory, applicationBundleURL: applicationBundleURL)
    }

    #if canImport(Darwin)
    public convenience init(storageDirectory: URL, extensionBundle: Bundle) throws {
        guard let installation = FocusExtensionInstallation(bundle: extensionBundle, includesApplication: false) else {
            throw FocusCatalogAccessError.invalidInstallation
        }
        try self.init(storageDirectory: storageDirectory, applicationBundleURL: extensionBundle.bundleURL)
        isCurrentExtension = {
            guard let snapshot = installation.snapshot() else { return false }
            return installation.isCurrent(snapshot)
        }
    }
    #endif

    public var isAccessible: Bool { state == .accessible }

    public var state: FocusCatalogAccessState {
        FocusCatalogAccessFiles.lock.lock()
        defer { FocusCatalogAccessFiles.lock.unlock() }
        guard !FocusCatalogAccessFiles.ownedPaths.contains(location.fileURL.path),
              location.isCurrent, isCurrentExtension() else { return .unavailable }
        do {
            let descriptor = try FocusCatalogAccessFiles.openFile(location.fileURL, create: false)
            defer { close(descriptor) }
            guard FocusCatalogAccessFiles.isHealthy(descriptor),
                  try FocusCatalogAccessFiles.lockOwner(descriptor, at: .emergencyDenial) == nil else { return .unavailable }
            guard try FocusCatalogAccessFiles.lockOwner(descriptor, at: .initialization) == nil,
                  try FocusCatalogAccessFiles.lockOwner(descriptor, at: .denial) == nil,
                  try FocusCatalogAccessFiles.lockOwner(descriptor, at: .presence) != nil,
                  try FocusCatalogAccessFiles.lockOwner(descriptor, at: .denial) == nil,
                  try FocusCatalogAccessFiles.lockOwner(descriptor, at: .initialization) == nil else { return .locked }
            guard try FocusCatalogAccessFiles.lockOwner(descriptor, at: .emergencyDenial) == nil,
                  FocusCatalogAccessFiles.isHealthy(descriptor), location.isCurrent, isCurrentExtension() else { return .unavailable }
            return .accessible
        } catch FocusCatalogAccessFileError.missing {
            return .locked
        } catch {
            return .unavailable
        }
    }
}
