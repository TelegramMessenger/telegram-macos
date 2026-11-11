import Foundation
import TelegramCore

enum AnalyticsParameterRule {
    case values(Set<String>)
    case boolean
    case integer
    case metadata
    case screen
    case menu
    case menuItem
    case setting
    case settingValue
    case flow
    case outcome
    case steps
}

enum AnalyticsValidation {
    static let maximumInteger = 9_007_199_254_740_991
    static let maximumPayloadBytes = 15 * 1024
    static let maximumSteps = 50

    static func validate(type: String, params: [String: JSON]) -> [String] {
        guard let name = AnalyticsEventName(rawValue: type), let eventRules = AnalyticsValidationSpec.events[name] else {
            return ["unknown event \(type)"]
        }
        var rules = eventRules.merging(AnalyticsValidationSpec.common) { current, _ in current }
        var required = AnalyticsEventSpec.required[name] ?? []
        if name == .flowEnd, let flow = string(params["flow"]) {
            rules.merge(AnalyticsValidationSpec.flowParams[flow] ?? [:]) { current, _ in current }
            required.formUnion(AnalyticsValidationSpec.flowRequired[flow] ?? [])
        }
        var problems: [String] = []
        for key in params.keys.sorted() {
            guard let rule = rules[key] else {
                problems.append("\(type) has unknown param \(key)")
                continue
            }
            if let value = params[key], !accepts(value, rule: rule, params: params) {
                problems.append("\(type) has invalid param \(key)")
            }
        }
        for key in required.sorted() where params[key] == nil {
            problems.append("\(type) is missing \(key)")
        }
        if let flow = string(params["flow"]), let conditions = AnalyticsValidationSpec.flowParamOutcomes[flow] {
            for key in conditions.keys.sorted() where params[key] != nil {
                if let outcome = string(params["outcome"]), conditions[key]?.contains(outcome) == true {
                    continue
                }
                problems.append("\(type) has incompatible param \(key)")
            }
        }
        if let session = params["session_id"], string(session).flatMap(UUID.init(uuidString:)) == nil {
            problems.append("\(type) has invalid session_id")
        }
        if let version = params["schema_version"], version != .number(Double(AnalyticsSchema.version)) {
            problems.append("\(type) has invalid schema_version")
        }
        if let platform = params["platform"], platform != .string(AnalyticsValues.Platform.macos.rawValue) {
            problems.append("\(type) has invalid platform")
        }
        if problems.isEmpty {
            guard let bytes = try? JSONEncoder().encode(JSON.dictionary(params)), bytes.count <= maximumPayloadBytes else {
                return ["\(type) exceeds payload limit"]
            }
        }
        return problems
    }

    static func acceptsFlowValue(flow: String, key: String, value: JSON?) -> Bool {
        guard let rule = AnalyticsValidationSpec.flowParams[flow]?[key] else { return false }
        guard let value = value else { return true }
        return accepts(value, rule: rule, params: [:])
    }

    static func elapsedMilliseconds(since start: TimeInterval, now: TimeInterval) -> Int? {
        guard start.isFinite, now.isFinite else { return nil }
        let elapsed = (now - start) * 1000
        guard elapsed.isFinite else { return nil }
        return Int(min(Double(maximumInteger), max(0, elapsed.rounded())))
    }

    private static func string(_ value: JSON?) -> String? {
        guard case let .string(value)? = value else { return nil }
        return value
    }

    private static func integer(_ value: JSON?) -> Int? {
        guard case let .number(value)? = value, value.isFinite, value >= 0, value <= Double(maximumInteger), value.rounded(.towardZero) == value else { return nil }
        return Int(value)
    }

    private static func accepts(_ value: JSON, rule: AnalyticsParameterRule, params: [String: JSON]) -> Bool {
        switch rule {
        case let .values(values):
            return string(value).map { values.contains($0) } ?? false
        case .boolean:
            if case .bool = value { return true }
            return false
        case .integer:
            return integer(value) != nil
        case .metadata:
            guard let value = string(value), value.utf8.count <= 64 else { return false }
            return value.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || ".+-_".unicodeScalars.contains($0) }
        case .screen:
            return string(value).map { AnalyticsValidationSpec.screens.contains($0) } ?? false
        case .menu:
            return string(value).map { AnalyticsValidationSpec.menuItems[$0] != nil } ?? false
        case .menuItem:
            guard let menu = string(params["menu"]), let item = string(value) else { return false }
            return AnalyticsValidationSpec.menuItems[menu]?.contains(item) ?? false
        case .setting:
            return string(value).map { AnalyticsValidationSpec.settingValues[$0] != nil } ?? false
        case .settingValue:
            guard let setting = string(params["setting"]), let value = string(value) else { return false }
            return AnalyticsValidationSpec.settingValues[setting]?.contains(value) ?? false
        case .flow:
            return string(value).map { AnalyticsValidationSpec.flowSteps[$0] != nil } ?? false
        case .outcome:
            return string(value).map { AnalyticsValidationSpec.outcomes.contains($0) } ?? false
        case .steps:
            return acceptsSteps(value, params: params)
        }
    }

    private static func acceptsSteps(_ value: JSON, params: [String: JSON]) -> Bool {
        guard case let .array(steps) = value, steps.count <= maximumSteps,
              let flow = string(params["flow"]), let allowed = AnalyticsValidationSpec.flowSteps[flow],
              let count = integer(params["step_count"]), let duration = integer(params["duration_ms"]),
              count >= steps.count, count == steps.count || steps.count == maximumSteps else { return false }
        var previousTime = 0
        var previousStep: String?
        let resolution = AnalyticsValidationSpec.flowTimingResolution[flow] ?? 1
        guard duration % resolution == 0 else { return false }
        for entry in steps {
            guard case let .array(pair) = entry, pair.count == 2,
                  let step = string(pair[0]), allowed.contains(step), step != previousStep,
                  let time = integer(pair[1]), time >= previousTime, time <= duration, time % resolution == 0 else { return false }
            previousTime = time
            previousStep = step
        }
        return true
    }
}
