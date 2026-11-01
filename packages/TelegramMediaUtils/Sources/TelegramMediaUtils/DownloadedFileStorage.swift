import Foundation

enum DownloadedFileStorage {
    static func temporaryDirectory(mediaBoxPath: String) -> String {
        return URL(fileURLWithPath: mediaBoxPath, isDirectory: true)
            .deletingLastPathComponent()
            .appendingPathComponent("temp-downloads", isDirectory: true).path
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

    static func copy(from source: String, to destination: String) throws -> String {
        let url = URL(fileURLWithPath: destination)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: nil)
        let base = url.deletingPathExtension().path
        let suffix = url.pathExtension.isEmpty ? "" : "." + url.pathExtension
        var path = destination
        var index = 1
        while true {
            do {
                try FileManager.default.copyItem(atPath: source, toPath: path)
                return path
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                path = "\(base) (\(index))\(suffix)"
                index += 1
            }
        }
    }
}
