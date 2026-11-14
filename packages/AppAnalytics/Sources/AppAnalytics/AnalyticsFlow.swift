import Foundation
import TelegramCore

public enum AnalyticsCommon {
    public static func params() -> [String: JSON] {
        let info = Bundle.main.infoDictionary ?? [:]
        return [
            "platform": .string(AnalyticsValues.Platform.macos.rawValue),
            "schema_version": .number(Double(AnalyticsSchema.version)),
            "app_version": .string(info["CFBundleShortVersionString"] as? String ?? ""),
            "build": .string(info["CFBundleVersion"] as? String ?? ""),
        ]
    }
}

public final class AnalyticsFlow<Spec: AnalyticsFlowSpec>: AnalyticsRevocable {
    public typealias Sink = (_ type: String, _ data: JSON) -> Void
    public static var maxSteps: Int { 50 }

    private var sink: Sink?
    private let scope: AnalyticsScope?
    private let clock: () -> TimeInterval
    private var startTime: TimeInterval
    private var lastElapsedMs = 0
    private var params: [Spec.Param: JSON] = [:]
    private var steps: [(Spec.Step, Int)] = []
    private var stepCount = 0
    private var lastStep: String?
    private var isFinished = false
    private var source: String?

    private init(scope: AnalyticsScope?, sink: @escaping Sink, clock: @escaping () -> TimeInterval, source: String?) {
        let scope = AnalyticsValidationSpec.flowSteps[Spec.id] == nil ? nil : scope
        self.scope = scope
        self.sink = scope == nil ? nil : sink
        self.clock = clock
        self.startTime = scope?.perform { clock() } ?? 0
        self.source = scope == nil ? nil : source
        if let scope = scope {
            if startTime.isFinite {
                scope.observe(self)
            } else {
                revokeAnalytics()
            }
        } else {
            revokeAnalytics()
        }
    }

    convenience init(sink: @escaping Sink, clock: @escaping () -> TimeInterval, source: String? = nil) {
        let policy = AnalyticsCollectionPolicy()
        let owner = NSObject()
        policy.setOwner(owner)
        policy.isEnabled = true
        self.init(scope: policy.makeScope(owner: owner, privacy: .ordinary), sink: sink, clock: clock, source: source)
    }

    public convenience init(engine: TelegramEngine, scope: AnalyticsScope? = nil) {
        let analytics = Analytics.shared
        let eligibleScope = analytics.policy.sync {
            analytics.policy.accepts(scope, owner: engine.account) ? scope : nil
        }
        self.init(analytics: analytics, scope: eligibleScope)
    }

    public convenience init(analytics: Analytics, scope: AnalyticsScope? = nil, source: AnalyticsScreen? = nil) {
        let eligibleScope = analytics.policy.sync {
            analytics.policy.accepts(scope) && source?.isAnalyticsExcluded != true ? scope : nil
        }
        self.init(scope: eligibleScope, sink: { [weak analytics] type, data in
            analytics?.sendRaw(type: type, data: data, scope: eligibleScope)
        }, clock: { [weak analytics] in
            analytics?.now ?? ProcessInfo.processInfo.systemUptime
        }, source: source?.rawValue)
    }

    public func setValue(_ key: Spec.Param, _ value: @autoclosure () -> JSON?) {
        scope?.perform {
            guard !isFinished else { return }
            let value = value()
            guard !isFinished, scope?.isValid == true else { return }
            guard !isExcludedValue(key, value), AnalyticsValidation.acceptsFlowValue(flow: Spec.id, key: key.rawValue, value: value) else {
                revokeAnalytics()
                scope?.removeObserver(self)
                return
            }
            params[key] = value
        }
    }

    public func setValueIfAbsent(_ key: Spec.Param, _ value: @autoclosure () -> JSON) {
        scope?.perform {
            guard !isFinished, params[key] == nil else { return }
            let value = value()
            guard !isFinished, scope?.isValid == true else { return }
            guard !isExcludedValue(key, value), AnalyticsValidation.acceptsFlowValue(flow: Spec.id, key: key.rawValue, value: value) else {
                revokeAnalytics()
                scope?.removeObserver(self)
                return
            }
            if params[key] == nil {
                params[key] = value
            }
        }
    }

    public func step(_ step: Spec.Step) {
        scope?.perform {
            guard !isFinished, step.rawValue != lastStep else { return }
            guard AnalyticsValidationSpec.flowSteps[Spec.id]?.contains(step.rawValue) == true, let elapsed = elapsedMs() else {
                revokeAnalytics()
                scope?.removeObserver(self)
                return
            }
            guard !isFinished, scope?.isValid == true else { return }
            lastStep = step.rawValue
            stepCount = min(AnalyticsValidation.maximumInteger, stepCount + 1)
            if steps.count < Self.maxSteps {
                steps.append((step, elapsed))
            }
        }
    }

    public func finish(_ outcome: AnalyticsFlowOutcome) {
        scope?.perform {
            guard !isFinished, let sink = sink else { return }
            isFinished = true
            guard let elapsed = elapsedMs() else {
                revokeAnalytics()
                scope?.removeObserver(self)
                return
            }
            var data = AnalyticsCommon.params()
            for (key, value) in params {
                data[key.rawValue] = value
            }
            data["flow"] = .string(Spec.id)
            data["outcome"] = .string(outcome.rawValue)
            data["steps"] = .array(steps.map { .array([.string($0.0.rawValue), .number(Double($0.1))]) })
            data["step_count"] = .number(Double(stepCount))
            data["duration_ms"] = .number(Double(elapsed))
            guard scope?.isValid == true else { return }
            if let source = source {
                data["source"] = .string(source)
            }
            revokeAnalytics()
            scope?.removeObserver(self)
            guard AnalyticsValidation.validate(type: AnalyticsEventName.flowEnd.rawValue, params: data).isEmpty else { return }
            sink(AnalyticsEventName.flowEnd.rawValue, .dictionary(data))
        }
    }

    func revokeAnalytics() {
        isFinished = true
        sink = nil
        params.removeAll()
        steps.removeAll()
        stepCount = 0
        lastStep = nil
        startTime = 0
        lastElapsedMs = 0
        source = nil
    }

    public func discard() {
        scope?.policy.sync {
            revokeAnalytics()
            scope?.removeObserver(self)
        }
    }

    var recordedStepCount: Int {
        return scope?.policy.sync { stepCount } ?? 0
    }

    var storedStepCount: Int {
        return scope?.policy.sync { steps.count } ?? 0
    }

    private func isExcludedValue(_ key: Spec.Param, _ value: JSON?) -> Bool {
        return key.rawValue == "peer_type" && value == .string(AnalyticsValues.PeerType.secretChat.rawValue)
    }

    private func elapsedMs() -> Int? {
        guard let elapsed = AnalyticsValidation.elapsedMilliseconds(since: startTime, now: clock()), scope?.isValid == true, sink != nil, elapsed >= lastElapsedMs else { return nil }
        lastElapsedMs = elapsed
        let resolution = AnalyticsValidationSpec.flowTimingResolution[Spec.id] ?? 1
        return elapsed / resolution * resolution
    }

    deinit {
        finish(.abandoned)
    }
}
