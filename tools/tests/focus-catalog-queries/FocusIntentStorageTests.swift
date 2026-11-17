import FocusFilterCore
import FocusFilterInfrastructure
import Foundation

extension String {
    init(localized value: String) {
        self = value
    }
}

struct FocusFilterStorageLocation {
    var directory: URL { URL(fileURLWithPath: "/unavailable") }

    static func resolve(appGroupIdentifier: String, buildSource: String?) throws -> Self {
        throw FocusCatalogAccessError.unavailable
    }
}

struct FocusExtensionLifecycle {
    struct Request {
        func invalidate() {}
    }

    static func start() -> Self? { nil }
    func beginRequest() -> Request? { nil }
}

extension FocusCatalogAccessReader {
    convenience init(storageDirectory: URL, extensionBundle: Bundle) throws {
        throw FocusCatalogAccessError.unavailable
    }
}

final class FocusFilterStore: FocusFilterRepository {
    var policy = FocusFilterPolicy()

    init(location: FocusFilterStorageLocation, onReadFailure: @escaping (Error) -> Void) {}
    func reload() {}
    func updateConfiguration(_ configuration: FocusFilterConfiguration) throws {}
    func updateCatalog(_ catalog: FocusFilterCatalog) throws {}
    func observe(_ observer: @escaping (FocusFilterPolicy) -> Void) -> any FocusFilterObservation {
        fatalError("Unexpected repository observation")
    }
}

private final class Probe: @unchecked Sendable {
    private let lock = NSLock()
    private var attempts = 0
    private var reads = 0
    private var failures = 2
    private var result = FocusCatalogAccessState.accessible

    func makeReader() throws -> () -> FocusCatalogAccessState {
        lock.lock()
        defer { lock.unlock() }
        attempts += 1
        if failures > 0 {
            failures -= 1
            throw FocusCatalogAccessError.unavailable
        }
        return { self.read() }
    }

    func setState(_ state: FocusCatalogAccessState) {
        lock.lock()
        defer { lock.unlock() }
        result = state
    }

    func read() -> FocusCatalogAccessState {
        lock.lock()
        defer { lock.unlock() }
        reads += 1
        return result
    }

    var counts: (attempts: Int, reads: Int) {
        lock.lock()
        defer { lock.unlock() }
        return (attempts, reads)
    }
}

@main
private enum FocusIntentStorageTests {
    static func main() {
        let probe = Probe()
        let access = FocusIntentCatalogAccess(makeReader: probe.makeReader)
        precondition(access.state == .unavailable)
        precondition(access.state == .unavailable)
        precondition(probe.counts.reads == 0)
        precondition(access.state == .accessible)
        precondition(probe.counts.attempts == 3)
        for state in [FocusCatalogAccessState.locked, .unavailable, .accessible] {
            probe.setState(state)
            DispatchQueue.concurrentPerform(iterations: 100) { _ in
                precondition(access.state == state)
            }
        }
        precondition(probe.counts.attempts == 3)
        precondition(probe.counts.reads == 301)
        let concurrentProbe = Probe()
        let concurrentAccess = FocusIntentCatalogAccess(makeReader: concurrentProbe.makeReader)
        let resultLock = NSLock()
        var unavailable = 0
        var accessible = 0
        DispatchQueue.concurrentPerform(iterations: 100) { _ in
            let state = concurrentAccess.state
            resultLock.lock()
            defer { resultLock.unlock() }
            switch state {
            case .unavailable: unavailable += 1
            case .accessible: accessible += 1
            case .locked: preconditionFailure("Initialization failure must not report locked")
            }
        }
        precondition(unavailable == 2 && accessible == 98)
        precondition(concurrentProbe.counts.attempts == 3)
        precondition(concurrentProbe.counts.reads == 98)
        print("PASS: production admission cache retries failed initialization, serializes concurrent requests and observes live lock/error recovery")
    }
}
