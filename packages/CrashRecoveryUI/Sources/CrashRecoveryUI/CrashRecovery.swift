import Cocoa
import TGUIKit
import SwiftSignalKit
import ColorPalette
import KeyboardKey
import Localization

public enum CrashRecoveryUpdateState: Equatable {
    case checking
    case downloading(version: String, current: Int, total: Int)
    case preparing(version: String)
    case readyToInstall(version: String)
    case installing
    case upToDate
    case failed
}

public struct CrashRecoveryUpdater {
    public let state: Signal<CrashRecoveryUpdateState, NoError>
    public let check: () -> Void
    public let install: () -> Void

    public init(state: Signal<CrashRecoveryUpdateState, NoError>, check: @escaping () -> Void, install: @escaping () -> Void) {
        self.state = state
        self.check = check
        self.install = install
    }
}

public enum CrashRecoveryUpdate {
    case disabled
    case updater(CrashRecoveryUpdater)
    case appStore
    case website
}

public enum CrashRecoveryResult {
    case continueLaunch
    case resetLocalData
}

public func runCrashRecovery(update: CrashRecoveryUpdate) -> CrashRecoveryResult {
    let previousTheme = presentation
    let palette = systemPalette()
    updateTheme(PresentationTheme(colors: palette, search: previousTheme.search, inputTheme: previousTheme.inputTheme))
    defer {
        updateTheme(previousTheme)
    }
    return CrashRecoveryWindowController(update: update, palette: palette).run()
}

private func systemPalette() -> ColorPalette {
    if #available(macOS 10.14, *), NSApp.effectiveAppearance.glassAppearance == .forceDark {
        return darkPalette
    }
    return whitePalette
}

private let appStoreURL = URL(string: "macappstore://apps.apple.com/app/id747648890")!
private let websiteURL = URL(string: "https://macos.telegram.org")!

private enum Text {
    static let title = strings().crashRecoveryTitle
    static let message = strings().crashRecoveryDescription
    static let checking = strings().crashRecoveryChecking
    static let checkingDetail = strings().crashRecoveryCheckingDetail
    static func downloading(_ version: String) -> String {
        return version.isEmpty ? strings().crashRecoveryDownloadingUpdate : strings().crashRecoveryDownloadingVersion(version)
    }
    static func downloaded(_ current: String, _ total: String) -> String {
        return strings().crashRecoveryDownloadProgress(current, total)
    }
    static let downloadStarting = strings().crashRecoveryDownloadStarting
    static func preparing(_ version: String) -> String {
        return version.isEmpty ? strings().crashRecoveryPreparingUpdate : strings().crashRecoveryPreparingVersion(version)
    }
    static let preparingDetail = strings().crashRecoveryPreparingDetail
    static func ready(_ version: String) -> String {
        return version.isEmpty ? strings().crashRecoveryReadyUpdate : strings().crashRecoveryReadyVersion(version)
    }
    static let readyDetail = strings().crashRecoveryReadyDetail
    static let installing = strings().crashRecoveryInstalling
    static let installingDetail = strings().crashRecoveryInstallingDetail
    static let upToDate = strings().crashRecoveryUpToDate
    static let upToDateDetail = strings().crashRecoveryUpToDateDetail
    static let failed = strings().crashRecoveryFailed
    static let failedDetail = strings().crashRecoveryFailedDetail
    static let appStore = strings().crashRecoveryAppStore
    static let appStoreDetail = strings().crashRecoveryAppStoreDetail
    static let website = strings().crashRecoveryWebsite
    static let websiteDetail = strings().crashRecoveryWebsiteDetail
    static let update = strings().crashRecoveryUpdate
    static let downloadingButton = strings().crashRecoveryDownloadingButton
    static let preparingButton = strings().crashRecoveryPreparingButton
    static let install = strings().crashRecoveryInstall
    static let installingButton = strings().crashRecoveryInstallingButton
    static let checkAgain = strings().crashRecoveryCheckAgain
    static let tryAgain = strings().crashRecoveryTryAgain
    static let openAppStore = strings().crashRecoveryOpenAppStore
    static let openWebsite = strings().crashRecoveryOpenWebsite
    static let continueAnyway = strings().crashRecoveryContinueAnyway
    static let quit = strings().crashRecoveryQuit
    static let websiteLink = strings().crashRecoveryWebsiteLink
    static let reset = strings().crashRecoveryReset
    static let resetTitle = strings().crashRecoveryResetTitle
    static let resetText = strings().crashRecoveryResetInfo
    static let resetConfirm = strings().crashRecoveryResetConfirm
    static let cancel = strings().crashRecoveryCancel
}

private func formattedSize(_ bytes: Int) -> String {
    return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
}

private func recoveryContent(update: CrashRecoveryUpdate, state: CrashRecoveryUpdateState, openedExternal: Bool) -> CrashRecoveryContent {
    switch update {
    case .disabled:
        return CrashRecoveryContent(symbol: .warning, title: Text.title, detail: Text.upToDateDetail, progress: nil, primaryTitle: Text.quit, primaryEnabled: true, secondaryEnabled: true, showsWebsite: false, showsReset: true)
    case .appStore:
        return CrashRecoveryContent(symbol: .appStore, title: Text.appStore, detail: Text.appStoreDetail, progress: nil, primaryTitle: openedExternal ? Text.quit : Text.openAppStore, primaryEnabled: true, secondaryEnabled: true, showsWebsite: false, showsReset: true)
    case .website:
        return CrashRecoveryContent(symbol: .website, title: Text.website, detail: Text.websiteDetail, progress: nil, primaryTitle: openedExternal ? Text.quit : Text.openWebsite, primaryEnabled: true, secondaryEnabled: true, showsWebsite: false, showsReset: true)
    case .updater:
        switch state {
        case .checking:
            return CrashRecoveryContent(symbol: .activity, title: Text.checking, detail: Text.checkingDetail, progress: nil, primaryTitle: Text.update, primaryEnabled: false, secondaryEnabled: true, showsWebsite: true, showsReset: true)
        case let .downloading(version, current, total):
            let detail = total > 0 ? Text.downloaded(formattedSize(current), formattedSize(total)) : Text.downloadStarting
            let progress = total > 0 ? min(1, CGFloat(current) / CGFloat(total)) : 0
            return CrashRecoveryContent(symbol: .download, title: Text.downloading(version), detail: detail, progress: progress, primaryTitle: Text.downloadingButton, primaryEnabled: false, secondaryEnabled: true, showsWebsite: true, showsReset: true)
        case let .preparing(version):
            return CrashRecoveryContent(symbol: .activity, title: Text.preparing(version), detail: Text.preparingDetail, progress: nil, primaryTitle: Text.preparingButton, primaryEnabled: false, secondaryEnabled: true, showsWebsite: true, showsReset: true)
        case let .readyToInstall(version):
            return CrashRecoveryContent(symbol: .ready, title: Text.ready(version), detail: Text.readyDetail, progress: nil, primaryTitle: Text.install, primaryEnabled: true, secondaryEnabled: true, showsWebsite: true, showsReset: true)
        case .installing:
            return CrashRecoveryContent(symbol: .activity, title: Text.installing, detail: Text.installingDetail, progress: nil, primaryTitle: Text.installingButton, primaryEnabled: false, secondaryEnabled: true, showsWebsite: false, showsReset: false)
        case .upToDate:
            return CrashRecoveryContent(symbol: .upToDate, title: Text.upToDate, detail: Text.upToDateDetail, progress: nil, primaryTitle: Text.checkAgain, primaryEnabled: true, secondaryEnabled: true, showsWebsite: true, showsReset: true)
        case .failed:
            return CrashRecoveryContent(symbol: .warning, title: Text.failed, detail: Text.failedDetail, progress: nil, primaryTitle: Text.tryAgain, primaryEnabled: true, secondaryEnabled: true, showsWebsite: true, showsReset: true)
        }
    }
}

private final class CrashRecoveryWindowController: NSObject, NSWindowDelegate {
    private let update: CrashRecoveryUpdate
    private let window: Window
    private let view: CrashRecoveryView
    private let disposable = MetaDisposable()
    private var state: CrashRecoveryUpdateState = .checking
    private var pendingState: CrashRecoveryUpdateState?
    private var renderedContent: CrashRecoveryContent?
    private var openedExternal = false
    private var result: CrashRecoveryResult = .continueLaunch

    init(update: CrashRecoveryUpdate, palette: ColorPalette) {
        self.update = update
        self.view = CrashRecoveryView(frame: NSMakeRect(0, 0, CrashRecoveryView.width, 400), palette: palette, title: Text.title, message: Text.message, continueTitle: Text.continueAnyway, websiteTitle: Text.websiteLink, resetTitle: Text.reset)
        self.window = Window(contentRect: NSMakeRect(0, 0, CrashRecoveryView.width, 400), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.title = Text.title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        if #available(macOS 10.14, *) {
            window.appearance = NSAppearance(named: palette.isDark ? .darkAqua : .aqua)
        }
        window.backgroundColor = palette.background
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.delegate = self
        window.contentView = view
    }

    func run() -> CrashRecoveryResult {
        view.primary = { [weak self] in
            self?.performPrimary()
        }
        view.secondary = { [weak self] in
            self?.finish(.continueLaunch)
        }
        view.website = {
            NSWorkspace.shared.open(websiteURL)
        }
        view.reset = { [weak self] in
            self?.confirmReset()
        }
        render(animated: false)
        if case let .updater(updater) = update {
            disposable.set(updater.state.start(next: { [weak self] state in
                CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) {
                    self?.enqueue(state)
                }
                CFRunLoopWakeUp(CFRunLoopGetMain())
            }))
            updater.check()
        }
        window.set(handler: { [weak self] _ in
            if let self = self, !self.primaryQuits {
                self.performPrimary()
            }
            return .invoked
        }, with: self, for: .Return, priority: .high)
        window.set(handler: { [weak self] _ in
            self?.performSecondary()
            return .invoked
        }, with: self, for: .Escape, priority: .high)
        window.setContentSize(NSMakeSize(CrashRecoveryView.width, view.requiredHeight))
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        let quitMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "q" {
                NSApp.terminate(nil)
                return nil
            }
            return event
        }
        NSApp.runModal(for: window)
        if let quitMonitor = quitMonitor {
            NSEvent.removeMonitor(quitMonitor)
        }
        disposable.dispose()
        window.removeAllHandlers(for: self)
        window.orderOut(nil)
        return result
    }

    private var primaryQuits: Bool {
        switch update {
        case .disabled:
            return true
        case .appStore, .website:
            return openedExternal
        case .updater:
            return false
        }
    }

    private var content: CrashRecoveryContent {
        return recoveryContent(update: update, state: state, openedExternal: openedExternal)
    }

    private func enqueue(_ state: CrashRecoveryUpdateState) {
        let scheduled = pendingState != nil
        pendingState = state
        guard !scheduled else {
            return
        }
        CFRunLoopPerformBlock(CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue) { [weak self] in
            guard let self = self, let pendingState = self.pendingState else {
                return
            }
            self.pendingState = nil
            self.state = pendingState
            self.render(animated: true)
        }
        CFRunLoopWakeUp(CFRunLoopGetMain())
    }

    private func render(animated: Bool) {
        let content = self.content
        guard content != renderedContent else {
            return
        }
        renderedContent = content
        view.update(content: content, animated: animated)
    }

    private func performPrimary() {
        guard content.primaryEnabled else {
            return
        }
        switch update {
        case .disabled:
            NSApp.terminate(nil)
        case let .updater(updater):
            switch state {
            case .readyToInstall:
                updater.install()
            case .upToDate, .failed:
                updater.check()
            default:
                break
            }
        case .appStore, .website:
            if openedExternal {
                NSApp.terminate(nil)
            } else {
                if case .appStore = update {
                    NSWorkspace.shared.open(appStoreURL)
                } else {
                    NSWorkspace.shared.open(websiteURL)
                }
                openedExternal = true
                render(animated: true)
            }
        }
    }

    private func performSecondary() {
        guard content.secondaryEnabled else {
            return
        }
        finish(.continueLaunch)
    }

    private func confirmReset() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = Text.resetTitle
        alert.informativeText = Text.resetText
        alert.addButton(withTitle: Text.cancel)
        let reset = alert.addButton(withTitle: Text.resetConfirm)
        if #available(macOS 11.0, *) {
            reset.hasDestructiveAction = true
        }
        alert.beginSheetModal(for: window, completionHandler: { [weak self] response in
            if response == .alertSecondButtonReturn {
                self?.finish(.resetLocalData)
            }
        })
    }

    private func finish(_ result: CrashRecoveryResult) {
        self.result = result
        NSApp.stopModal()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        performSecondary()
        return false
    }
}
