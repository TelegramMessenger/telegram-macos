import Darwin
import FocusFilterCore
import FocusFilterInfrastructure
import Foundation

private func emit(_ marker: String) {
    let line = "\(marker) \(ProcessInfo.processInfo.systemUptime)\n"
    FileHandle.standardOutput.write(Data(line.utf8))
}

@main
struct LifecycleFixture {
    private static var lifecycle: FocusExtensionLifecycle?
    private static var request: (any FocusFilterObservation)?

    static func main() {
        let expectedName = "Telegram Focus Filters"
        guard ProcessInfo.processInfo.processName == expectedName,
              Bundle.main.executableURL?.lastPathComponent == expectedName,
              Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String == expectedName else {
            emit("INVALID_PROCESS_NAME \(ProcessInfo.processInfo.processName)")
            exit(78)
        }
        guard Bundle.main.bundleURL.pathExtension == "appex",
              Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String == "1",
              let group = Bundle.main.object(forInfoDictionaryKey: "FocusAppGroup") as? String,
              let lifecycle = FocusExtensionLifecycle.start() else {
            emit("INVALID_BUNDLE")
            exit(78)
        }
        self.lifecycle = lifecycle
        atexit { emit("EXIT") }

        #if BUILD_A
        request = lifecycle.beginRequest()
        DispatchQueue.global().asyncAfter(deadline: .now() + 35) {
            request?.invalidate()
            request = nil
            emit("WORK_FINISHED")
        }
        emit("READY A")
        #else
        for delay in [1, 3, 30] {
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(delay)) {
                FocusExtensionLifecycle.applicationDidLaunch(appGroupIdentifier: group, buildSource: "STABLE")
                emit("NOTIFIED B")
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 45) {
            emit("NORMAL B")
            exit(EXIT_SUCCESS)
        }
        emit("READY B")
        #endif

        DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
            emit("DEADLINE")
            exit(70)
        }
        dispatchMain()
    }
}
