import Foundation
import FocusFilterCore

public protocol FocusFilterPersistence {
    func loadConfiguration() throws -> FocusFilterConfiguration
    func loadCatalog() throws -> FocusFilterCatalog
    func saveConfiguration(_ configuration: FocusFilterConfiguration) throws
    func saveCatalog(_ catalog: FocusFilterCatalog) throws
}

public final class FocusFilterFilePersistence: FocusFilterPersistence {
    private let directory: URL
    private let fileManager: FileManager

    public init(directory: URL, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    public func loadConfiguration() throws -> FocusFilterConfiguration {
        try read("configuration.json", defaultValue: .init())
    }

    public func loadCatalog() throws -> FocusFilterCatalog {
        try read("catalog.json", defaultValue: .init())
    }

    public func saveConfiguration(_ configuration: FocusFilterConfiguration) throws {
        try write(configuration, name: "configuration.json")
    }

    public func saveCatalog(_ catalog: FocusFilterCatalog) throws {
        try write(catalog, name: "catalog.json")
    }

    private func read<Value: Decodable>(_ name: String, defaultValue: Value) throws -> Value {
        let url = directory.appendingPathComponent(name)
        do {
            return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return defaultValue
        }
    }

    private func write<Value: Encodable>(_ value: Value, name: String) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let url = directory.appendingPathComponent(name)
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
