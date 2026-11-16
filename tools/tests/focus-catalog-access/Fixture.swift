import Foundation
#if canImport(Darwin)
import MachO
#endif

private enum FixtureError: Error {
    case injectedCheckerMissing
}

@main
private enum Fixture {
    static func main() throws {
        let arguments = CommandLine.arguments
        let directory = URL(fileURLWithPath: arguments[2])
        let application = URL(fileURLWithPath: arguments[3])
        if arguments[1].hasPrefix("injected-") {
            try verifyInjectedChecker()
        }
        if arguments[1] == "state" {
            let reader = try? FocusCatalogAccessReader(storageDirectory: directory, applicationBundleURL: application)
            print(String(describing: reader?.state ?? .unavailable))
            return
        }
        if arguments[1] == "read" {
            let reader = try? FocusCatalogAccessReader(storageDirectory: directory, applicationBundleURL: application)
            print(reader?.isAccessible ?? false)
            return
        }
        if arguments[1] == "reader" || arguments[1] == "injected-reader" {
            let reader: FocusCatalogAccessReader
            #if canImport(Darwin)
            if arguments[1] == "injected-reader" {
                reader = try FocusCatalogAccessReader(storageDirectory: directory, extensionBundle: .main)
            } else {
                reader = try FocusCatalogAccessReader(storageDirectory: directory, applicationBundleURL: application)
            }
            #else
            reader = try FocusCatalogAccessReader(storageDirectory: directory, applicationBundleURL: application)
            #endif
            print("ready")
            fflush(stdout)
            while readLine() != nil {
                print(reader.isAccessible)
                fflush(stdout)
            }
            return
        }
        let session = try FocusCatalogAccessSession(storageDirectory: directory, applicationBundleURL: application)
        print("ready")
        fflush(stdout)
        while let command = readLine() {
            switch command {
            case "unlock": try session.update(isUnlocked: true)
            case "lock": try session.update(isUnlocked: false)
            case "attempt-unlock":
                do {
                    try session.update(isUnlocked: true)
                    print("updated")
                } catch {
                    print("unavailable")
                }
            case "own-read":
                let reader = try FocusCatalogAccessReader(storageDirectory: directory, applicationBundleURL: application)
                print(reader.isAccessible)
            case "duplicate":
                do {
                    _ = try FocusCatalogAccessSession(storageDirectory: directory, applicationBundleURL: application)
                    print("unexpected")
                } catch FocusCatalogAccessError.duplicateSession {
                    print("duplicate denied")
                }
            default: return
            }
            print("done")
            fflush(stdout)
        }
    }

    private static func verifyInjectedChecker() throws {
        #if canImport(Darwin)
        guard let header = _dyld_get_image_header(0), header.pointee.filetype == MH_DYLIB,
              let name = _dyld_get_image_name(0),
              URL(fileURLWithPath: String(cString: name)).lastPathComponent == "libMainThreadChecker.dylib" else {
            throw FixtureError.injectedCheckerMissing
        }
        #else
        throw FixtureError.injectedCheckerMissing
        #endif
    }
}
