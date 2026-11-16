import Foundation
import zlib

public enum HTMLWidgetTestMode {
    public static let usesPreviousBehavior: Bool = {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ name: String) -> String? {
            guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else {
                return nil
            }
            return arguments[index + 1]
        }
        return value("-PerfLab") == "chat-navigation" && value("-PerfLabScenarios") == "manual" && value("-PerfLabSyntheticWidgets") != nil && value("-PerfLabWidgetBehavior") == "old"
        #else
        return false
        #endif
    }()
}

public enum HTMLWidgetPayload {
    public static let maximumHTMLSize = 4 * 1024 * 1024
    public static let minimumWidth: CGFloat = 200
    public static let minimumHeight: CGFloat = 50
    public static let maximumHeight: CGFloat = 600

    public static func clampedHeight(_ height: CGFloat) -> CGFloat {
        return min(max(height, minimumHeight), maximumHeight)
    }

    static func compressedSize(_ bytes: [UInt8]) -> Int {
        guard !bytes.isEmpty else {
            return 0
        }
        var capacity = compressBound(uLong(bytes.count))
        var output = [UInt8](repeating: 0, count: Int(capacity))
        let status = bytes.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                compress2(destination.baseAddress, &capacity, source.baseAddress, uLong(source.count), Z_BEST_COMPRESSION)
            }
        }
        return status == Z_OK ? Int(capacity) : bytes.count
    }

    public static func decode(_ payload: Data) -> String? {
        guard !payload.isEmpty else {
            return nil
        }
        var stream = z_stream()
        let windowBits = MAX_WBITS + (HTMLWidgetTestMode.usesPreviousBehavior ? 16 : 32)
        guard inflateInit2_(&stream, windowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer { inflateEnd(&stream) }
        return payload.withUnsafeBytes { input -> String? in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
            stream.avail_in = uInt(input.count)
            let chunkSize = 8192
            var chunk = [UInt8](repeating: 0, count: chunkSize)
            var output = Data()
            while true {
                let status = chunk.withUnsafeMutableBytes { buffer -> Int32 in
                    stream.next_out = buffer.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(chunkSize)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let count = chunkSize - Int(stream.avail_out)
                guard output.count + count <= maximumHTMLSize else {
                    return nil
                }
                output.append(contentsOf: chunk.prefix(count))
                if status == Z_STREAM_END {
                    guard stream.avail_in == 0, !output.isEmpty else {
                        return nil
                    }
                    return String(data: output, encoding: .utf8)
                }
                guard status == Z_OK, count > 0 else {
                    return nil
                }
            }
        }
    }
}
