import Foundation

enum VideoRenderUploadChunk {
    case data(offset: Int64, data: Data)
    case header(Data)
    case complete(size: Int64)
    case completeFile(path: String)
}

enum VideoRenderUploadError: Error {
    case failed
    case invalidRange
    case truncated
}

struct VideoRenderUploadState {
    private(set) var offset: Int64 = 0
    private(set) var headerSize: Int64 = 32 * 1024
    private(set) var isComplete = false
    private var sourcePath: String?
    let minimumSize: Int64
    static let chunkSize: Int64 = 512 * 1024

    init(minimumSize: Int64 = PendingVideoRenderEvent.minimumStreamingSize) {
        self.minimumSize = minimumSize
    }

    mutating func update(_ event: PendingVideoRenderEvent, finalPath: String, emit: (VideoRenderUploadChunk) -> Void) throws {
        guard !isComplete else { return }
        switch event {
        case let .progress(path, size, headerSize):
            guard size >= headerSize, headerSize > 0, headerSize <= Int64(Int32.max) else { throw VideoRenderUploadError.invalidRange }
            guard size >= offset else { throw VideoRenderUploadError.truncated }
            if offset > 0, headerSize > self.headerSize || sourcePath != path { throw VideoRenderUploadError.invalidRange }
            sourcePath = path
            self.headerSize = max(self.headerSize, headerSize)
            guard size > minimumSize, size - offset >= Self.chunkSize else { return }
            do {
                try append(path: path, size: size, emit: emit)
            } catch {
                if FileManager.default.fileExists(atPath: path) { throw error }
            }
        case let .completed(success):
            guard success else { throw VideoRenderUploadError.failed }
            let attributes = try FileManager.default.attributesOfItem(atPath: finalPath)
            guard let size = (attributes[.size] as? NSNumber)?.int64Value, size >= offset else { throw VideoRenderUploadError.truncated }
            if offset == 0 {
                isComplete = true
                emit(.completeFile(path: finalPath))
                return
            }
            try append(path: finalPath, size: size, emit: emit)
            let headerLength = min(size, self.headerSize)
            let header = try read(path: finalPath, offset: 0, length: headerLength)
            emit(.header(header))
            isComplete = true
            emit(.complete(size: size))
        }
    }

    private mutating func append(path: String, size: Int64, emit: (VideoRenderUploadChunk) -> Void) throws {
        guard size >= offset else { throw VideoRenderUploadError.truncated }
        while offset < size {
            let limit = offset == 0 ? max(Self.chunkSize, minimumSize + 1) : Self.chunkSize
            let count = min(limit, size - offset)
            let data = try read(path: path, offset: offset, length: count)
            emit(.data(offset: offset, data: data))
            offset += count
        }
    }

    private func read(path: String, offset: Int64, length: Int64) throws -> Data {
        guard offset >= 0, length >= 0, length <= Int64(Int.max), let handle = FileHandle(forReadingAtPath: path) else { throw VideoRenderUploadError.invalidRange }
        defer { handle.closeFile() }
        handle.seek(toFileOffset: UInt64(offset))
        let data = handle.readData(ofLength: Int(length))
        guard data.count == Int(length) else { throw VideoRenderUploadError.truncated }
        return data
    }
}
