import Foundation

public enum DownloadedFileStorage {
    public static func temporaryDirectory(mediaBoxPath: String) -> String {
        return URL(fileURLWithPath: mediaBoxPath, isDirectory: true)
            .deletingLastPathComponent()
            .appendingPathComponent("temp-downloads", isDirectory: true).path
    }

    private static let lock = NSLock()
    private static var closedDirectories = Set<String>()

    public static func removeTemporaryDirectory(mediaBoxPath: String) {
        let directory = URL(fileURLWithPath: temporaryDirectory(mediaBoxPath: mediaBoxPath), isDirectory: true).standardizedFileURL.path
        lock.lock()
        closedDirectories.insert(directory)
        try? FileManager.default.removeItem(atPath: directory)
        lock.unlock()
    }

    static func existingPath(_ path: String, size: Int64, lastModified: Int32, in directory: String) -> String? {
        let url = URL(fileURLWithPath: path)
        guard url.deletingLastPathComponent().standardizedFileURL == URL(fileURLWithPath: directory, isDirectory: true).standardizedFileURL,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let actualSize = attributes[.size] as? NSNumber,
              actualSize.int64Value == size,
              let modificationDate = attributes[.modificationDate] as? Date,
              Int32(modificationDate.timeIntervalSince1970) == lastModified else {
            return nil
        }
        return path
    }

    private static func ensureOpen(_ directory: String, afterCopy: Bool = false) throws {
        lock.lock()
        defer { lock.unlock() }
        if closedDirectories.contains(directory) {
            if afterCopy {
                try? FileManager.default.removeItem(atPath: directory)
            }
            throw CocoaError(.fileWriteNoPermission)
        }
    }

    static func copy(from source: String, to destination: String) throws -> String {
        let url = URL(fileURLWithPath: destination)
        let directory = url.deletingLastPathComponent().standardizedFileURL.path
        try ensureOpen(directory)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        let base = url.deletingPathExtension().path
        let suffix = url.pathExtension.isEmpty ? "" : "." + url.pathExtension
        var path = destination
        var index = 1
        while true {
            do {
                try FileManager.default.copyItem(atPath: source, toPath: path)
                try ensureOpen(directory, afterCopy: true)
                return path
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                path = "\(base) (\(index))\(suffix)"
                index += 1
            }
        }
    }
}
