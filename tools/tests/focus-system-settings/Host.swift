import AppKit
import Darwin
import MachO
import FocusFilterCore
import FocusFilterInfrastructure

@main
private enum FixtureApplication {
    static func main() {
        InstallationDiagnostics.record()
        if CommandLine.arguments.contains("--verify-installation") {
            do {
                try verifyInstallation()
                print("PASS: installed host initialized the production catalog session")
            } catch {
                NSLog("Focus CI installation verification failed: %@", String(describing: error))
                exit(EXIT_FAILURE)
            }
            return
        }
        let application = NSApplication.shared
        let delegate = FixtureDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
        withExtendedLifetime(delegate) {}
    }

    private static func verifyInstallation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("focus-ci-installation-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = try FocusCatalogAccessSession(storageDirectory: directory, applicationBundleURL: Bundle.main.bundleURL)
        try session.update(isUnlocked: false)
    }
}

private enum InstallationDiagnostics {
    static func record() {
        NSLog("Focus CI main bundle: %@", Bundle.main.bundleURL.path)
        NSLog("Focus CI main executable: %@", Bundle.main.executableURL?.path ?? "missing")
        NSLog("Focus CI image zero: %@", _dyld_get_image_name(0).map { String(cString: $0) } ?? "missing")
        recordBundle(Bundle.main.bundleURL, label: "host")
        recordBundle(Bundle.main.bundleURL.appendingPathComponent("Contents/Extensions/FocusIntents.appex"), label: "extension")
    }

    private static func recordBundle(_ bundle: URL, label: String) {
        let info = bundle.appendingPathComponent("Contents/Info.plist")
        NSLog("Focus CI %@ Info.plist: %@ exists=%d", label, info.path, FileManager.default.fileExists(atPath: info.path))
        do {
            let data = try Data(contentsOf: info)
            let dictionary = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
            guard let executable = dictionary?["CFBundleExecutable"] as? String else {
                NSLog("Focus CI %@ has no CFBundleExecutable", label)
                return
            }
            let path = bundle.appendingPathComponent("Contents/MacOS").appendingPathComponent(executable)
            NSLog("Focus CI %@ executable: %@ exists=%d", label, path.path, FileManager.default.fileExists(atPath: path.path))
            let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
            NSLog("Focus CI %@ executable attributes: %@", label, String(describing: attributes))
        } catch {
            NSLog("Focus CI %@ inspection failed: %@", label, String(describing: error))
        }
    }
}

private final class FixtureDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var session: FocusCatalogAccessSession?
    private var store: FocusFilterStore?
    private let status = NSTextField(labelWithString: "Starting")

    func applicationDidFinishLaunching(_ notification: Notification) {
        showWindow()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(lockFromNotification(_:)), name: Notification.Name("org.telegram.FocusSettingsCI.lock"), object: nil)
        do {
            try prepareCatalog()
            try setUnlocked(false)
        } catch {
            report(error)
        }
    }

    private func prepareCatalog() throws {
        guard let group = Bundle.main.object(forInfoDictionaryKey: "FocusAppGroup") as? String else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let location = try FocusFilterStorageLocation.resolve(appGroupIdentifier: group, buildSource: "DEBUG")
        let store = FocusFilterStore(location: location, onReadFailure: { error in
            NSLog("Focus CI storage error: %@", error.localizedDescription)
        })
        try store.updateCatalog(FocusFilterCatalog(
            accounts: [FocusCatalogAccount(id: 1042, title: "Focus CI Account", telegramUserId: 1042)],
            chats: [FocusCatalogChat(id: FocusChatIdentifier(accountId: 1042, peerId: 1043), title: "Focus CI Chat", telegramChatId: 1043)],
            folders: [FocusCatalogFolder(id: FocusFolderIdentifier(accountId: 1042, folderId: 1044), title: "Focus CI Folder", peerIds: [1043])]
        ))
        self.store = store
        session = try FocusCatalogAccessSession(storageDirectory: location.directory, applicationBundleURL: Bundle.main.bundleURL)
    }

    private func showWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 180), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Telegram Focus CI"
        let unlock = NSButton(title: "Unlock", target: self, action: #selector(unlockCatalog))
        unlock.setAccessibilityIdentifier("unlock")
        let lock = NSButton(title: "Lock", target: self, action: #selector(lockCatalog))
        lock.setAccessibilityIdentifier("lock")
        status.setAccessibilityIdentifier("status")
        let stack = NSStackView(views: [status, unlock, lock])
        stack.orientation = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                stack.centerYAnchor.constraint(equalTo: content.centerYAnchor)
            ])
        }
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    @objc private func unlockCatalog() {
        updateAccess(isUnlocked: true)
    }

    @objc private func lockCatalog() {
        updateAccess(isUnlocked: false)
    }

    @objc private func lockFromNotification(_ notification: Notification) {
        updateAccess(isUnlocked: false)
    }

    private func updateAccess(isUnlocked: Bool) {
        do {
            try setUnlocked(isUnlocked)
        } catch {
            report(error)
        }
    }

    private func setUnlocked(_ isUnlocked: Bool) throws {
        guard let session else { throw CocoaError(.fileReadUnknown) }
        try session.update(isUnlocked: isUnlocked)
        status.stringValue = isUnlocked ? "Unlocked" : "Locked"
    }

    private func report(_ error: Error) {
        status.stringValue = "Setup failed: \(String(describing: error))"
        NSLog("Focus CI host failed: %@", String(describing: error))
    }
}
