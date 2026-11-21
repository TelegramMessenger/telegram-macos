import FocusFilterCore
import FocusFilterInfrastructure
import Foundation

enum FocusIntentStorage {
    static let lifecycle = FocusExtensionLifecycle.start()

    static func withRequest<Result>(_ work: () throws -> Result) rethrows -> Result {
        let request = lifecycle?.beginRequest()
        defer { request?.invalidate() }
        return try work()
    }

    private static func resolveLocation() throws -> FocusFilterStorageLocation {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "FocusAppGroup") as? String else {
            throw FocusStorageError.unavailable
        }
        let source = Bundle.main.object(forInfoDictionaryKey: "SOURCE") as? String
        return try FocusFilterStorageLocation.resolve(appGroupIdentifier: group, buildSource: source)
    }

    private static let catalogAccess = FocusIntentCatalogAccess {
        let location = try resolveLocation()
        let reader = try FocusCatalogAccessReader(storageDirectory: location.directory, extensionBundle: .main)
        return { reader.state }
    }

    static var catalogAccessState: FocusCatalogAccessState {
        catalogAccess.state
    }

    static var isCatalogAccessible: Bool {
        catalogAccessState == .accessible
    }

    private static let repository: Result<any FocusFilterRepository, Error> = Result {
        FocusFilterStore(location: try resolveLocation(), onReadFailure: logReadFailure)
    }

    static func store() throws -> any FocusFilterRepository {
        try repository.get()
    }

    static func loadCatalog() -> FocusFilterCatalog {
        guard isCatalogAccessible else { return FocusFilterCatalog() }
        do {
            let repository = try store()
            repository.reload()
            let catalog = repository.policy.catalog
            return isCatalogAccessible ? catalog : FocusFilterCatalog()
        } catch {
            logReadFailure(error)
            return FocusFilterCatalog()
        }
    }

    private static func logReadFailure(_ error: Error) {
        NSLog("Telegram Focus catalog unavailable: %@", error.localizedDescription)
    }
}

enum FocusStorageError: LocalizedError {
    case unavailable
    case locked
    case verificationUnavailable

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return String(localized: "Open Telegram once to prepare its Focus filters. The app and extension must share the same App Group.")
        case .verificationUnavailable:
            return String(localized: "Telegram could not verify access to its Focus catalog. Try again while Telegram is open. Saved Focus rules keep working.")
        case .locked:
            return String(localized: "Open and unlock Telegram to choose accounts, folders, and chats. Saved Focus rules keep working.")
        }
    }
}

final class FocusIntentCatalogAccess {
    private let lock = NSLock()
    private let makeReader: () throws -> () -> FocusCatalogAccessState
    private var readState: (() -> FocusCatalogAccessState)?

    init(makeReader: @escaping () throws -> () -> FocusCatalogAccessState) {
        self.makeReader = makeReader
    }

    var state: FocusCatalogAccessState {
        lock.lock()
        defer { lock.unlock() }
        if readState == nil {
            do {
                readState = try makeReader()
            } catch {
                return .unavailable
            }
        }
        return readState?() ?? .unavailable
    }
}
