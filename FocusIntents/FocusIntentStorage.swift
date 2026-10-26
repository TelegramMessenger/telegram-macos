import FocusFilterCore
import FocusFilterInfrastructure
import Foundation

enum FocusIntentStorage {
    private static let repository: Result<any FocusFilterRepository, Error> = Result {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "FocusAppGroup") as? String else {
            throw FocusStorageError.unavailable
        }
        let source = Bundle.main.object(forInfoDictionaryKey: "SOURCE") as? String
        let location: FocusFilterStorageLocation
        do {
            location = try FocusFilterStorageLocation.resolve(appGroupIdentifier: group, buildSource: source)
        } catch {
            throw FocusStorageError.unavailable
        }
        return FocusFilterStore(location: location, onReadFailure: logReadFailure)
    }

    static func store() throws -> any FocusFilterRepository {
        try repository.get()
    }

    static func loadCatalog() -> FocusFilterCatalog {
        do {
            let repository = try store()
            repository.reload()
            return repository.policy.catalog
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

    var errorDescription: String? {
        String(localized: "Open Telegram once to prepare its Focus filters. The app and extension must share the same App Group.")
    }
}
