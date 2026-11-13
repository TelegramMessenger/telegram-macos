import Foundation

@main
private enum Fixture {
    static func main() throws {
        let arguments = CommandLine.arguments
        let directory = URL(fileURLWithPath: arguments[2])
        let application = URL(fileURLWithPath: arguments[3])
        if arguments[1] == "read" {
            let reader = try? FocusCatalogAccessReader(storageDirectory: directory, applicationBundleURL: application)
            print(reader?.isAccessible ?? false)
            return
        }
        if arguments[1] == "reader" {
            let reader = try FocusCatalogAccessReader(storageDirectory: directory, applicationBundleURL: application)
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
}
