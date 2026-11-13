import Darwin
import Foundation
import MachO

final class FocusExtensionInstallation {
    struct Snapshot: Equatable {
        fileprivate let files: [FileIdentity?]
        fileprivate let executableUUIDs: Set<UUID>
    }

    fileprivate struct FileIdentity: Equatable {
        let path: String
        let device: dev_t
        let inode: ino_t
        let size: off_t
        let modifiedSeconds: Int
        let modifiedNanoseconds: Int
        let changedSeconds: Int
        let changedNanoseconds: Int

        init?(url: URL, directory: Bool = false) {
            var value = stat()
            guard stat(url.path, &value) == 0,
                  value.st_mode & S_IFMT == (directory ? S_IFDIR : S_IFREG) else { return nil }
            path = url.path
            device = value.st_dev
            inode = value.st_ino
            size = value.st_size
            modifiedSeconds = value.st_mtimespec.tv_sec
            modifiedNanoseconds = value.st_mtimespec.tv_nsec
            changedSeconds = value.st_ctimespec.tv_sec
            changedNanoseconds = value.st_ctimespec.tv_nsec
        }
    }

    private let bundleURL: URL
    private let executableURL: URL
    private let applicationURL: URL
    private let loadedUUID: UUID
    private(set) var initial: Snapshot?

    convenience init?(bundle: Bundle) {
        guard let executableURL = bundle.executableURL, let uuid = Self.loadedExecutableUUID() else { return nil }
        self.init(bundleURL: bundle.bundleURL, executableURL: executableURL, loadedUUID: uuid)
    }

    init?(bundleURL: URL, executableURL: URL, loadedUUID: UUID) {
        let bundleURL = bundleURL.standardizedFileURL
        let executableURL = executableURL.standardizedFileURL
        guard bundleURL.pathExtension == "appex", executableURL.path.hasPrefix(bundleURL.path + "/") else { return nil }
        guard let applicationURL = FocusApplicationLocation.applicationURL(containing: bundleURL) else { return nil }
        self.bundleURL = bundleURL
        self.executableURL = executableURL
        self.applicationURL = applicationURL
        self.loadedUUID = loadedUUID
        initial = snapshot()
    }

    func snapshot() -> Snapshot? {
        let applicationInfo = applicationURL.appendingPathComponent("Contents/Info.plist")
        guard let applicationInfoIdentity = FileIdentity(url: applicationInfo),
              let applicationExecutable = FocusApplicationLocation.executableURL(in: applicationURL) else { return nil }
        let required = [
            FileIdentity(url: bundleURL, directory: true),
            FileIdentity(url: applicationURL, directory: true),
            FileIdentity(url: executableURL),
            FileIdentity(url: bundleURL.appendingPathComponent("Contents/Info.plist")),
            applicationInfoIdentity,
            FileIdentity(url: applicationExecutable)
        ]
        guard required.allSatisfy({ $0 != nil }), let uuids = Self.executableUUIDs(at: executableURL) else { return nil }
        let optional = [bundleURL, applicationURL].map { FileIdentity(url: $0.appendingPathComponent("Contents/_CodeSignature/CodeResources")) }
        return Snapshot(files: required + optional, executableUUIDs: uuids)
    }

    func isCurrent(_ snapshot: Snapshot) -> Bool {
        guard snapshot.executableUUIDs.contains(loadedUUID) else { return false }
        if let initial { return snapshot == initial }
        initial = snapshot
        return true
    }

    static func executableUUIDs(at url: URL) -> Set<UUID>? {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var metadata = stat()
        guard fstat(descriptor, &metadata) == 0, metadata.st_size >= 8 else { return nil }
        let size = UInt64(metadata.st_size)
        func read(_ offset: UInt64, _ count: Int) -> Data? {
            guard count >= 0, count <= 1_048_576, offset <= size, UInt64(count) <= size - offset else { return nil }
            var data = Data(count: count)
            let readCount = data.withUnsafeMutableBytes { pread(descriptor, $0.baseAddress, count, off_t(offset)) }
            return readCount == count ? data : nil
        }
        guard let header = read(0, 8) else { return nil }
        let magic = integer(header, 0, littleEndian: true)
        if [UInt32(MH_MAGIC), UInt32(MH_MAGIC_64), UInt32(MH_CIGAM), UInt32(MH_CIGAM_64)].contains(magic) {
            return thinUUID(offset: 0, size: size, read: read).map { [$0] }
        }
        let littleEndian: Bool
        let wide: Bool
        switch magic {
        case UInt32(FAT_CIGAM): littleEndian = false; wide = false
        case UInt32(FAT_CIGAM_64): littleEndian = false; wide = true
        case UInt32(FAT_MAGIC): littleEndian = true; wide = false
        case UInt32(FAT_MAGIC_64): littleEndian = true; wide = true
        default: return nil
        }
        let count = Int(integer(header, 4, littleEndian: littleEndian))
        let entrySize = wide ? 32 : 20
        guard count > 0, count <= 32, let entries = read(8, count * entrySize) else { return nil }
        var result = Set<UUID>()
        for index in 0..<count {
            let start = index * entrySize
            let offset = wide ? integer64(entries, start + 8, littleEndian: littleEndian) : UInt64(integer(entries, start + 8, littleEndian: littleEndian))
            let length = wide ? integer64(entries, start + 16, littleEndian: littleEndian) : UInt64(integer(entries, start + 12, littleEndian: littleEndian))
            guard offset >= UInt64(8 + count * entrySize), offset <= size, length <= size - offset,
                  let uuid = thinUUID(offset: offset, size: length, read: read) else { return nil }
            result.insert(uuid)
        }
        return result
    }

    private static func thinUUID(offset: UInt64, size: UInt64, read: (UInt64, Int) -> Data?) -> UUID? {
        guard size >= 28, let header = read(offset, 28) else { return nil }
        let magic = integer(header, 0, littleEndian: true)
        let littleEndian: Bool
        let headerSize: UInt64
        switch magic {
        case UInt32(MH_MAGIC): littleEndian = true; headerSize = 28
        case UInt32(MH_MAGIC_64): littleEndian = true; headerSize = 32
        case UInt32(MH_CIGAM): littleEndian = false; headerSize = 28
        case UInt32(MH_CIGAM_64): littleEndian = false; headerSize = 32
        default: return nil
        }
        let count = Int(integer(header, 16, littleEndian: littleEndian))
        let length = Int(integer(header, 20, littleEndian: littleEndian))
        guard size >= headerSize, UInt64(length) <= size - headerSize,
              length <= 1_048_576, let commands = read(offset + headerSize, length) else { return nil }
        return commandUUID(commands, count: count, littleEndian: littleEndian)
    }

    private static func commandUUID(_ commands: Data, count: Int, littleEndian: Bool) -> UUID? {
        guard count > 0, count <= 32_768 else { return nil }
        var offset = 0
        var result: UUID?
        for _ in 0..<count {
            guard commands.count - offset >= 8 else { return nil }
            let command = integer(commands, offset, littleEndian: littleEndian)
            let size = Int(integer(commands, offset + 4, littleEndian: littleEndian))
            guard size >= 8, size <= commands.count - offset else { return nil }
            if command == LC_UUID {
                guard size == 24, result == nil else { return nil }
                let b = Array(commands[(offset + 8)..<(offset + 24)])
                result = UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
            }
            offset += size
        }
        return offset == commands.count ? result : nil
    }

    static func loadedExecutableUUID() -> UUID? {
        guard let header = _dyld_get_image_header(0) else { return nil }
        let value = header.pointee
        guard value.magic == MH_MAGIC || value.magic == MH_MAGIC_64, value.sizeofcmds <= 1_048_576 else { return nil }
        let headerSize = value.magic == MH_MAGIC_64 ? MemoryLayout<mach_header_64>.size : MemoryLayout<mach_header>.size
        let commands = Data(bytes: UnsafeRawPointer(header).advanced(by: headerSize), count: Int(value.sizeofcmds))
        return commandUUID(commands, count: Int(value.ncmds), littleEndian: true)
    }

    private static func integer(_ data: Data, _ offset: Int, littleEndian: Bool) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(data[offset + $1]) << UInt32((littleEndian ? $1 : 3 - $1) * 8) }
    }

    private static func integer64(_ data: Data, _ offset: Int, littleEndian: Bool) -> UInt64 {
        (0..<8).reduce(0) { $0 | UInt64(data[offset + $1]) << UInt64((littleEndian ? $1 : 7 - $1) * 8) }
    }
}
