import Foundation
import CoreGraphics

enum StorageUsageCapacity {
    static var totalDeviceBytes: UInt64? {
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: "/")
        return attributes?[.systemSize] as? UInt64
    }

    static func fraction(usedBytes: Int64, totalBytes: UInt64?) -> CGFloat? {
        guard usedBytes >= 0, let totalBytes, totalBytes > 0 else {
            return nil
        }
        return min(1, CGFloat(usedBytes) / CGFloat(totalBytes))
    }
}
