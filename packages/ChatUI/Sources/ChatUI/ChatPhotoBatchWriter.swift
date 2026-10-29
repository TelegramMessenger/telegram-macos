import Foundation

struct ChatPhotoBatchWriter {
    struct File {
        let source: URL
        let name: String
    }

    static func copy(_ files: [File], to directory: URL, cancelled: () -> Bool = { false }) throws -> [URL] {
        guard !files.isEmpty else { return [] }
        let manager = FileManager.default
        let staging = directory.appendingPathComponent(".telegram-photos-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? manager.removeItem(at: staging) }

        for (index, file) in files.enumerated() {
            if cancelled() { throw CocoaError(.userCancelled) }
            guard !file.name.isEmpty, file.name == (file.name as NSString).lastPathComponent, file.name != ".", file.name != ".." else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            try manager.copyItem(at: file.source, to: staging.appendingPathComponent("\(index)"))
        }

        var saved: [URL] = []
        do {
            for (index, file) in files.enumerated() {
                if cancelled() { throw CocoaError(.userCancelled) }
                let name = file.name as NSString
                var suffix = 0
                while true {
                    let candidate: String
                    if suffix == 0 {
                        candidate = file.name
                    } else {
                        let ext = name.pathExtension
                        candidate = "\(name.deletingPathExtension) (\(suffix))" + (ext.isEmpty ? "" : ".\(ext)")
                    }
                    let destination = directory.appendingPathComponent(candidate)
                    do {
                        try manager.moveItem(at: staging.appendingPathComponent("\(index)"), to: destination)
                        saved.append(destination)
                        break
                    } catch {
                        let error = error as NSError
                        guard error.domain == NSCocoaErrorDomain, error.code == NSFileWriteFileExistsError else { throw error }
                        suffix += 1
                    }
                }
            }
            return saved
        } catch {
            for destination in saved { try? manager.removeItem(at: destination) }
            throw error
        }
    }
}
