import Foundation
import OpusBinding

public final class DataItem : TGDataItem {
    let path: String
    public init(path: String) {
        self.path = path
        super.init()
    }
    init(path: String, initialData: Data) {
        self.path = path
        super.init()
        super.appendData(initialData)
    }
    public override func replaceData(_ data: Data!) -> Bool {
        guard let data else { return false }
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            return false
        }
        return super.replaceData(data)
    }
    public override func appendData(_ data: Data!) {
        if !FileManager.default.fileExists(atPath: self.path) {
            FileManager.default.createFile(atPath: self.path, contents: self.data(), attributes: nil)
        }
        let fd = Darwin.open(self.path, O_WRONLY | O_APPEND)
        if fd >= 0 {
            data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) -> Void in
                guard let baseAddress = bytes.baseAddress else {
                    return
                }
                var offset = 0
                while offset < bytes.count {
                    let written = Darwin.write(fd, baseAddress.advanced(by: offset), bytes.count - offset)
                    if written > 0 {
                        offset += written
                    } else if written < 0 && errno == EINTR {
                        continue
                    } else {
                        break
                    }
                }
            }
            Darwin.fsync(fd)
            Darwin.close(fd)
        }
        super.appendData(data)
    }
}
