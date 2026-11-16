import Darwin
import Foundation

private enum FixtureError: Error {
    case invalidArguments
    case unexpectedBundle
    case hostFileReadable
    case unexpectedCommand
}

@main
private enum Fixture {
    static func main() throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 4 else { throw FixtureError.invalidArguments }
        let storage = URL(fileURLWithPath: arguments[2])
        let application = URL(fileURLWithPath: arguments[3])
        switch arguments[1] {
        case "owner":
            try ownPermit(storage: storage, application: application)
        case "reader":
            try readPermit(storage: storage, application: application)
        default:
            throw FixtureError.invalidArguments
        }
    }

    private static func emit(_ value: String) {
        print(value)
        fflush(stdout)
    }

    private static func ownPermit(storage: URL, application: URL) throws {
        let session = try FocusCatalogAccessSession(storageDirectory: storage, applicationBundleURL: application)
        emit("ready")
        while let command = readLine() {
            switch command {
            case "unlock": try session.update(isUnlocked: true)
            case "lock": try session.update(isUnlocked: false)
            default: throw FixtureError.unexpectedCommand
            }
            emit("done")
        }
    }

    private static func readPermit(storage: URL, application: URL) throws {
        let expectedBundle = application.appendingPathComponent("Contents/Extensions/FocusIntents.appex")
        guard Bundle.main.bundleURL.resolvingSymlinksInPath() == expectedBundle.resolvingSymlinksInPath() else {
            throw FixtureError.unexpectedBundle
        }
        for path in ["Contents/Info.plist", "Contents/MacOS/FocusFixture"] {
            guard (try? Data(contentsOf: application.appendingPathComponent(path))) == nil else {
                throw FixtureError.hostFileReadable
            }
        }
        let reader = try FocusCatalogAccessReader(storageDirectory: storage, extensionBundle: .main)
        emit("host-files-denied")
        while let command = readLine() {
            guard command == "state" else { throw FixtureError.unexpectedCommand }
            emit(String(describing: reader.state))
        }
    }
}
