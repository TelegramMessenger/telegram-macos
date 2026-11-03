import Darwin
import FocusFilterCore
import Foundation

public final class FocusExtensionLifecycle {
    private let installation: FocusExtensionInstallation
    private let retirement = FocusExtensionRetirement<FocusExtensionInstallation.Snapshot>()
    private let queue = DispatchQueue(label: "Telegram.FocusExtensionLifecycle", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var observation: (any FocusFilterObservation)?
    private var confirmation: DispatchWorkItem?

    private init(installation: FocusExtensionInstallation, bundle: Bundle) {
        self.installation = installation
        if let group = bundle.object(forInfoDictionaryKey: "FocusAppGroup") as? String {
            let changes = DistributedFocusFilterChanges(name: Self.notificationName(
                appGroupIdentifier: group,
                buildSource: bundle.object(forInfoDictionaryKey: "SOURCE") as? String
            ))
            observation = changes.observe { [weak self] in
                self?.queue.async { [weak self] in self?.checkInstallation() }
            }
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .seconds(30), leeway: .seconds(5))
        timer.setEventHandler { [weak self] in self?.checkInstallation() }
        self.timer = timer
        timer.resume()
    }

    public static func start(bundle: Bundle = .main) -> FocusExtensionLifecycle? {
        guard let installation = FocusExtensionInstallation(bundle: bundle) else {
            return nil
        }
        return FocusExtensionLifecycle(installation: installation, bundle: bundle)
    }

    public static func applicationDidLaunch(appGroupIdentifier: String, buildSource: String?) {
        DistributedFocusFilterChanges(name: notificationName(
            appGroupIdentifier: appGroupIdentifier,
            buildSource: buildSource
        )).postChange()
    }

    public func beginRequest() -> any FocusFilterObservation {
        retirement.beginRequest()
    }

    static func notificationName(appGroupIdentifier: String, buildSource: String?) -> String {
        "\(appGroupIdentifier).FocusFilters.\(FocusFilterStorageLocation.channel(for: buildSource)).Installation"
    }

    private func checkInstallation() {
        confirmation?.cancel()
        confirmation = nil
        let snapshot = installation.snapshot()
        let needsConfirmation = retirement.check(snapshot: snapshot, isCurrent: snapshot.map(installation.isCurrent) ?? false) {
            NSLog("Telegram Focus extension is retiring after an application update")
            exit(EXIT_SUCCESS)
        }
        if needsConfirmation {
            let work = DispatchWorkItem { [weak self] in self?.checkInstallation() }
            confirmation = work
            queue.asyncAfter(deadline: .now() + 2, execute: work)
        }
    }

    deinit {
        timer?.cancel()
        confirmation?.cancel()
        observation?.invalidate()
    }
}

final class FocusExtensionRetirement<Snapshot: Equatable> {
    private let lock = NSLock()
    private let now: () -> TimeInterval
    private let gracePeriod: TimeInterval
    private var candidate: Snapshot?
    private var candidateSince: TimeInterval = 0
    private var lastActivity: TimeInterval = 0
    private var activeRequests = 0
    private var retired = false

    init(gracePeriod: TimeInterval = 2, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.gracePeriod = gracePeriod
        self.now = now
    }

    func beginRequest() -> any FocusFilterObservation {
        lock.lock()
        activeRequests += 1
        lastActivity = now()
        lock.unlock()
        return FocusFilterObservationToken { [self] in
            lock.lock()
            activeRequests -= 1
            lastActivity = now()
            lock.unlock()
        }
    }

    func check(snapshot: Snapshot?, isCurrent: Bool, retire: () -> Void) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !retired else { return false }
        guard let snapshot, !isCurrent else {
            candidate = nil
            return false
        }
        let time = now()
        if candidate != snapshot {
            candidate = snapshot
            candidateSince = time
        }
        guard activeRequests == 0, time - candidateSince >= gracePeriod, time - lastActivity >= gracePeriod else {
            return true
        }
        retired = true
        retire()
        return false
    }
}
