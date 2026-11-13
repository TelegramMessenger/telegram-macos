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

    private static let location: Result<FocusFilterStorageLocation, Error> = Result {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "FocusAppGroup") as? String else {
            throw FocusStorageError.unavailable
        }
        let source = Bundle.main.object(forInfoDictionaryKey: "SOURCE") as? String
        return try FocusFilterStorageLocation.resolve(appGroupIdentifier: group, buildSource: source)
    }

    private static let catalogAccess: FocusCatalogAccessReader? = {
        guard let location = try? location.get() else { return nil }
        return try? FocusCatalogAccessReader(storageDirectory: location.directory, extensionBundle: .main)
    }()

    static var isCatalogAccessible: Bool {
        catalogAccess?.isAccessible ?? false
    }

    private static let repository: Result<any FocusFilterRepository, Error> = Result {
        FocusFilterStore(location: try location.get(), onReadFailure: logReadFailure)
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

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return String(localized: "Open Telegram once to prepare its Focus filters. The app and extension must share the same App Group.")
        case .locked:
            return String(localized: "Open and unlock Telegram to choose accounts, folders, and chats. Saved Focus rules keep working.")
        }
    }
}
