import Foundation
import MachO
import XCTest
@testable import FocusFilterInfrastructure

final class FocusExtensionInstallationTests: XCTestCase {
    private var directory: URL!
    private let firstUUID = UUID(uuidString: "01234567-89AB-CDEF-0123-456789ABCDEF")!
    private let secondUUID = UUID(uuidString: "FEDCBA98-7654-3210-FEDC-BA9876543210")!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("FocusInstallationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    func testThinExecutablesSupportBothWidthsAndByteOrders() throws {
        for wide in [false, true] {
            for littleEndian in [false, true] {
                XCTAssertEqual(try parse(thin(firstUUID, wide: wide, littleEndian: littleEndian)), [firstUUID])
            }
        }
    }

    func testUniversalExecutablesCollectEachSliceUUID() throws {
        for wide in [false, true] {
            for littleEndian in [false, true] {
                XCTAssertEqual(try parse(fat([thin(firstUUID), thin(secondUUID)], wide: wide, littleEndian: littleEndian)), [firstUUID, secondUUID])
            }
        }
    }

    func testRejectsTruncationMalformedCommandsAndUnboundedHeaders() throws {
        let valid = thin(firstUUID)
        for length in [0, 7, 27, 31, valid.count - 1] {
            XCTAssertNil(try parse(Data(valid.prefix(length))))
        }
        for (offset, value) in [(16, UInt32.max), (20, UInt32.max), (36, 0), (36, 7), (36, UInt32.max)] {
            var malformed = valid
            malformed.replaceSubrange(offset..<(offset + 4), with: bytes(UInt64(value), count: 4))
            XCTAssertNil(try parse(malformed))
        }
        var missingUUID = valid
        missingUUID.replaceSubrange(32..<36, with: bytes(UInt64(LC_SEGMENT_64), count: 4))
        XCTAssertNil(try parse(missingUUID))
        var hugeFatCount = fat([valid])
        hugeFatCount.replaceSubrange(4..<8, with: bytes(UInt64(UInt32.max), count: 4, littleEndian: false))
        XCTAssertNil(try parse(hugeFatCount))
    }

    func testRejectsUniversalOffsetsOutsideTheFileAndTruncatedSlices() throws {
        let valid = fat([thin(firstUUID)], wide: true)
        for (offset, value) in [(16, UInt64.max), (16, 0), (24, UInt64.max), (24, 31)] {
            var malformed = valid
            malformed.replaceSubrange(offset..<(offset + 8), with: bytes(value, count: 8, littleEndian: false))
            XCTAssertNil(try parse(malformed))
        }
    }

    func testUnchangedInstallationRemainsCurrentAndSameVersionReplacementDoesNot() throws {
        let fixture = try makeInstallation()
        let installation = try XCTUnwrap(FocusExtensionInstallation(bundleURL: fixture.bundle, executableURL: fixture.executable, loadedUUID: firstUUID))
        let original = try XCTUnwrap(installation.snapshot())
        XCTAssertEqual(installation.initial, original)
        XCTAssertTrue(installation.isCurrent(original))
        try thin(secondUUID).write(to: fixture.executable, options: .atomic)
        XCTAssertFalse(installation.isCurrent(try XCTUnwrap(installation.snapshot())))
    }

    func testAlreadyReplacedExecutableDoesNotBecomeTheCurrentLoadedBinary() throws {
        let fixture = try makeInstallation()
        let installation = try XCTUnwrap(FocusExtensionInstallation(bundleURL: fixture.bundle, executableURL: fixture.executable, loadedUUID: secondUUID))
        XCTAssertFalse(installation.isCurrent(try XCTUnwrap(installation.snapshot())))
    }

    func testBundleInitializerCapturesTheActualLoadedExecutableIdentity() throws {
        let fixture = try makeInstallation()
        let bundle = try XCTUnwrap(Bundle(url: fixture.bundle))
        let installation = try XCTUnwrap(FocusExtensionInstallation(bundle: bundle))
        XCTAssertFalse(installation.isCurrent(try XCTUnwrap(installation.snapshot())))
    }

    func testContainingAppReplacementDetectedEvenWithIdenticalExtensionAndVersions() throws {
        let fixture = try makeInstallation()
        let installation = try XCTUnwrap(FocusExtensionInstallation(bundleURL: fixture.bundle, executableURL: fixture.executable, loadedUUID: firstUUID))
        let info = fixture.app.appendingPathComponent("Contents/Info.plist")
        let original = try Data(contentsOf: info)
        try original.write(to: info, options: .atomic)
        XCTAssertFalse(installation.isCurrent(try XCTUnwrap(installation.snapshot())))
    }

    func testMissingFilesYieldNoDecisionAndInitialIncompleteInstallRecovers() throws {
        let fixture = try makeInstallation()
        let info = fixture.app.appendingPathComponent("Contents/Info.plist")
        let original = try Data(contentsOf: info)
        try FileManager.default.removeItem(at: info)
        let installation = try XCTUnwrap(FocusExtensionInstallation(bundleURL: fixture.bundle, executableURL: fixture.executable, loadedUUID: firstUUID))
        XCTAssertNil(installation.initial)
        XCTAssertNil(installation.snapshot())
        try original.write(to: info)
        let restored = try XCTUnwrap(installation.snapshot())
        XCTAssertTrue(installation.isCurrent(restored))
        XCTAssertEqual(installation.initial, restored)
        try FileManager.default.removeItem(at: fixture.executable)
        XCTAssertNil(installation.snapshot())
    }

    func testSignatureResourceChangesAreDetected() throws {
        let fixture = try makeInstallation()
        let signature = fixture.bundle.appendingPathComponent("Contents/_CodeSignature/CodeResources")
        try FileManager.default.createDirectory(at: signature.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("first".utf8).write(to: signature)
        let installation = try XCTUnwrap(FocusExtensionInstallation(bundleURL: fixture.bundle, executableURL: fixture.executable, loadedUUID: firstUUID))
        try Data("other".utf8).write(to: signature)
        XCTAssertFalse(installation.isCurrent(try XCTUnwrap(installation.snapshot())))
    }

    func testRejectsBundlesOutsideContainingApplicationAndEscapingExecutables() {
        let bundle = directory.appendingPathComponent("FocusIntents.appex")
        XCTAssertNil(FocusExtensionInstallation(bundleURL: bundle, executableURL: bundle.appendingPathComponent("Contents/MacOS/FocusIntents"), loadedUUID: firstUUID))
        XCTAssertNil(FocusExtensionInstallation(bundleURL: directory.appendingPathComponent("Telegram.app/Contents/Extensions/FocusIntents.appex"), executableURL: directory.appendingPathComponent("other"), loadedUUID: firstUUID))
    }

    private func makeInstallation() throws -> (app: URL, bundle: URL, executable: URL) {
        let app = directory.appendingPathComponent("Telegram.app")
        let bundle = app.appendingPathComponent("Contents/Extensions/FocusIntents.appex")
        let executable = bundle.appendingPathComponent("Contents/MacOS/FocusIntents")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        for (root, name) in [(app, "Telegram"), (bundle, "FocusIntents")] {
            let info = try PropertyListSerialization.data(fromPropertyList: ["CFBundleExecutable": name, "CFBundleVersion": "1"], format: .xml, options: 0)
            try info.write(to: root.appendingPathComponent("Contents/Info.plist"))
        }
        try Data("app".utf8).write(to: app.appendingPathComponent("Contents/MacOS/Telegram"))
        try thin(firstUUID).write(to: executable)
        return (app, bundle, executable)
    }

    private func parse(_ data: Data) throws -> Set<UUID>? {
        let file = directory.appendingPathComponent("executable")
        try data.write(to: file)
        return FocusExtensionInstallation.executableUUIDs(at: file)
    }

    private func thin(_ uuid: UUID, wide: Bool = true, littleEndian: Bool = true) -> Data {
        let fields: [UInt32] = [wide ? UInt32(MH_MAGIC_64) : UInt32(MH_MAGIC), 0, 0, UInt32(MH_EXECUTE), 1, 24, 0] + (wide ? [0] : [])
        var data = Data(fields.flatMap { bytes(UInt64($0), count: 4, littleEndian: littleEndian) })
        data.append(contentsOf: bytes(UInt64(LC_UUID), count: 4, littleEndian: littleEndian))
        data.append(contentsOf: bytes(24, count: 4, littleEndian: littleEndian))
        var value = uuid.uuid
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
        return data
    }

    private func fat(_ slices: [Data], wide: Bool = false, littleEndian: Bool = false) -> Data {
        let entrySize = wide ? 32 : 20
        var data = Data(bytes(UInt64(wide ? FAT_MAGIC_64 : FAT_MAGIC), count: 4, littleEndian: littleEndian))
        data.append(contentsOf: bytes(UInt64(slices.count), count: 4, littleEndian: littleEndian))
        var offset = 8 + slices.count * entrySize
        for slice in slices {
            data.append(contentsOf: bytes(0, count: 8))
            data.append(contentsOf: bytes(UInt64(offset), count: wide ? 8 : 4, littleEndian: littleEndian))
            data.append(contentsOf: bytes(UInt64(slice.count), count: wide ? 8 : 4, littleEndian: littleEndian))
            data.append(contentsOf: bytes(0, count: wide ? 8 : 4))
            offset += slice.count
        }
        for slice in slices { data.append(slice) }
        return data
    }

    private func bytes(_ value: UInt64, count: Int, littleEndian: Bool = true) -> [UInt8] {
        (0..<count).map { UInt8(truncatingIfNeeded: value >> ((littleEndian ? $0 : count - 1 - $0) * 8)) }
    }
}
