import Foundation

private final class StreamingVideoHeaderSizes {
    static let shared = StreamingVideoHeaderSizes()
    private let lock = NSLock()
    private var sizes: [String: Int32] = [:]

    func update(_ size: Int64?, path: String) {
        lock.lock()
        if let size {
            sizes[path] = Int32(clamping: max(32 * 1024, size))
        } else {
            sizes.removeValue(forKey: path)
        }
        lock.unlock()
    }

    func size(path: String) -> Int32 {
        lock.lock()
        defer { lock.unlock() }
        return sizes[path] ?? 32 * 1024
    }
}

public func updateStreamingVideoHeaderSize(_ size: Int64?, path: String) {
    StreamingVideoHeaderSizes.shared.update(size, path: path)
}

public func streamingVideoHeaderSize(path: String) -> Int32 {
    return StreamingVideoHeaderSizes.shared.size(path: path)
}
