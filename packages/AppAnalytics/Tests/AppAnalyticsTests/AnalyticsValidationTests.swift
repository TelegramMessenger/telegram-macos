import XCTest
import TelegramCore
import TGUIKit
@testable import AppAnalytics

private enum ForgedFlow: AnalyticsFlowSpec {
    static let id = "peer_info.visibility"
    enum Step: String {
        case selectPublic = "select_public"
        case unregistered
    }
    enum Param: String, Hashable {
        case entry
        case content
    }
}

private enum UnknownFlow: AnalyticsFlowSpec {
    static let id = "unknown"
    typealias Step = ForgedFlow.Step
    typealias Param = ForgedFlow.Param
}

final class AnalyticsValidationTests: XCTestCase {
    private let owner = NSObject()
    private var sent: [[String: JSON]] = []
    private var logs: [String] = []

    private func hub(clock: @escaping () -> TimeInterval = { 0 }) -> (Analytics, AnalyticsScope?) {
        let hub = Analytics(clock: clock)
        hub.setSink({ [unowned self] _, data in
            if case let .dictionary(params) = data { self.sent.append(params) }
        }, owner: owner)
        hub.log = { [unowned self] in self.logs.append($0) }
        hub.isEnabled = true
        return (hub, hub.policy.makeScope(owner: owner, privacy: .ordinary))
    }

    private var validFlow: [String: JSON] {
        return ["flow": .string("peer_info.visibility"), "outcome": .string("success"), "entry": .string("edit"), "steps": .array([.array([.string("select_public"), .number(5)])]), "step_count": .number(1), "duration_ms": .number(10)]
    }

    private func assertRejected(_ type: String, _ params: [String: JSON], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(Analytics.validate(type: type, params: params).isEmpty, file: file, line: line)
        let (analytics, scope) = hub()
        analytics.sendRaw(type: type, data: .dictionary(params), scope: scope)
        XCTAssertTrue(sent.isEmpty, file: file, line: line)
        XCTAssertTrue(logs.isEmpty, file: file, line: line)
    }

    func testInvalidScalarTypesAndValuesNeverReachLogOrSink() {
        for value in [JSON.string("unregistered"), .number(1), .bool(true), .null, .array([]), .dictionary([:])] {
            assertRejected("chat.message.send", ["kind": value])
        }
        for value in [JSON.string("true"), .number(1), .null] {
            assertRejected("call.start", ["video": value])
        }
        for value in [Double(-1), 0.5, .nan, .infinity, -.infinity, Double(AnalyticsValidation.maximumInteger) + 1] {
            assertRejected("app.background", ["duration_ms": .number(value)])
        }
        assertRejected("chat.message.forward", ["count": .number(2)])
        assertRejected("chat.message.forward", ["count": .string("2")])
        assertRejected("screen.show", ["screen": .string("unregistered")])
        assertRejected("screen.show", ["screen": .string("ios.widget")])
    }

    func testMenuAndSettingValuesBelongToTheirParent() {
        assertRejected("menu.select", ["menu": .string("chat.header"), "item": .string("reply")])
        assertRejected("menu.select", ["menu": .string("unknown"), "item": .string("reply")])
        assertRejected("settings.change", ["setting": .string("privacy.last_seen"), "value": .string("enabled")])
        assertRejected("settings.change", ["setting": .string("unknown"), "value": .string("enabled")])
        XCTAssertTrue(Analytics.validate(type: "menu.select", params: ["menu": .string("chat.message"), "item": .string("reply")]).isEmpty)
        XCTAssertTrue(Analytics.validate(type: "settings.change", params: ["setting": .string("privacy.last_seen"), "value": .string("contacts")]).isEmpty)
    }

    func testFlowParamsAreRestrictedToTheSelectedFlow() {
        for patch in [
            ["flow": .string("unknown")], ["entry": .string("clipboard contents")],
            ["text": .string("message contents")], ["rule": .string("last_seen")],
            ["peer_type": .string("user")], ["outcome": .string("unknown")],
            ["outcome": .string("abandoned"), "result": .string("public")]
        ] as [[String: JSON]] {
            assertRejected("flow.end", validFlow.merging(patch) { _, new in new })
        }
        var empty = validFlow
        empty["flow"] = .string("peer_info.manage")
        empty["steps"] = .array([])
        empty["step_count"] = .number(0)
        assertRejected("flow.end", empty)
        empty.removeValue(forKey: "entry")
        XCTAssertTrue(Analytics.validate(type: "flow.end", params: empty).isEmpty)
        XCTAssertTrue(Analytics.validate(type: "flow.end", params: validFlow.merging(["result": .string("public")]) { _, new in new }).isEmpty)
    }

    func testFlowStepsRequireValidShapeOrderDurationAndCounts() {
        for steps in [
            JSON.string("select_public"), .array([.string("select_public")]),
            .array([.array([.string("select_public"), .number(0), .number(1)])]),
            .array([.array([.string("change_title"), .number(0)])]),
            .array([.array([.string("select_public"), .number(-1)])]),
            .array([.array([.string("select_public"), .number(0.5)])]),
            .array([.array([.string("select_public"), .number(.infinity)])]),
            .array([.array([.string("select_public"), .number(11)])]),
            .array([.array([.string("select_public"), .number(5)]), .array([.string("select_private"), .number(4)])]),
            .array([.array([.string("select_public"), .number(1)]), .array([.string("select_public"), .number(2)])]),
            .array(Array(repeating: .array([.string("select_public"), .number(0)]), count: 51))
        ] {
            var params = validFlow
            params["steps"] = steps
            if case let .array(values) = steps { params["step_count"] = .number(Double(values.count)) }
            assertRejected("flow.end", params)
        }
        for count in [Double(0), 2, 51] {
            assertRejected("flow.end", validFlow.merging(["step_count": .number(count)]) { _, new in new })
        }
        for key in ["steps", "step_count", "duration_ms", "flow", "outcome"] {
            var params = validFlow
            params.removeValue(forKey: key)
            assertRejected("flow.end", params)
        }
    }

    func testCappedFlowPreservesTotalCount() {
        var params = validFlow
        params["steps"] = .array((0..<50).map { .array([.string($0 % 2 == 0 ? "select_public" : "select_private"), .number(Double($0))]) })
        params["step_count"] = .number(73)
        params["duration_ms"] = .number(100)
        XCTAssertTrue(Analytics.validate(type: "flow.end", params: params).isEmpty)
    }

    func testOversizedAndMalformedMetadataIsRejected() {
        assertRejected("app.foreground", ["app_version": .string(String(repeating: "x", count: 16 * 1024))])
        assertRejected("app.foreground", ["build": .string("private text\n")])
        assertRejected("app.foreground", ["session_id": .string("stable-user-id")])
        assertRejected("app.foreground", ["schema_version": .number(0)])
        assertRejected("app.foreground", ["platform": .string("ios")])
        assertRejected("app.foreground", ["seq": .number(-1)])
    }

    func testRejectedEventsDoNotConsumeSequenceAndCommonParamsCannotBeOverridden() {
        let (analytics, scope) = hub()
        analytics.sendRaw(type: "call.start", data: .dictionary(["video": .string("true")]), scope: scope)
        let injected = UUID().uuidString
        analytics.sendRaw(type: "app.foreground", data: .dictionary(["seq": .number(999), "session_id": .string(injected), "layout": .string("wide")]), scope: scope)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent.first?["seq"], .number(0))
        XCTAssertEqual(sent.first?["layout"], .string("regular"))
        XCTAssertNotEqual(sent.first?["session_id"], .string(injected))
        #if DEBUG
        XCTAssertEqual(logs.count, 1)
        #else
        XCTAssertTrue(logs.isEmpty)
        #endif
    }

    func testInvalidFlowValuesEraseRecorderBeforeFinish() {
        let (analytics, scope) = hub()
        let flow = AnalyticsFlow<AnalyticsFlows.PeerInfoVisibility>(analytics: analytics, scope: scope)
        flow.step(.selectPublic)
        flow.setValue(.entry, .string("clipboard contents"))
        XCTAssertEqual(flow.recordedStepCount, 0)
        flow.set(entry: .edit)
        flow.finish(.success)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logs.isEmpty)
    }

    func testCustomFlowSpecsCannotRecordUnknownFieldsOrSteps() {
        let (analytics, scope) = hub()
        let invalidParam = AnalyticsFlow<ForgedFlow>(analytics: analytics, scope: scope)
        invalidParam.step(.selectPublic)
        invalidParam.setValue(.content, .string("clipboard contents"))
        XCTAssertEqual(invalidParam.recordedStepCount, 0)
        invalidParam.finish(.success)
        let invalidStep = AnalyticsFlow<ForgedFlow>(analytics: analytics, scope: scope)
        invalidStep.step(.unregistered)
        XCTAssertEqual(invalidStep.recordedStepCount, 0)
        invalidStep.finish(.success)
        var clockCalls = 0
        let unknown = AnalyticsFlow<UnknownFlow>(sink: { _, _ in XCTFail() }, clock: { clockCalls += 1; return 0 })
        unknown.step(.selectPublic)
        unknown.finish(.success)
        XCTAssertEqual(clockCalls, 0)
        XCTAssertTrue(sent.isEmpty)
    }

    func testSetIfAbsentDoesNotEvaluateUnusedValue() {
        let (analytics, scope) = hub()
        let flow = AnalyticsFlow<AnalyticsFlows.PeerInfoVisibility>(analytics: analytics, scope: scope)
        flow.set(entry: .edit)
        func unused() -> JSON { XCTFail(); return .string("private contents") }
        flow.setValueIfAbsent(.entry, unused())
        flow.finish(.success)
        XCTAssertEqual(sent.first?["entry"], .string("edit"))
    }

    func testNonFiniteAndBackwardsClocksDiscardFlows() {
        for invalid in [TimeInterval.nan, .infinity, -.infinity, -1] {
            var now: TimeInterval = 0
            let (analytics, scope) = hub(clock: { now })
            let flow = AnalyticsFlow<AnalyticsFlows.PeerInfoVisibility>(analytics: analytics, scope: scope)
            now = 2
            flow.step(.selectPublic)
            now = invalid
            flow.step(.selectPrivate)
            XCTAssertEqual(flow.recordedStepCount, 0)
            flow.finish(.success)
            XCTAssertTrue(sent.isEmpty)
        }
    }

    func testInvalidClockAtStartDoesNotRecordVisibilityOrFlow() {
        let (analytics, scope) = hub(clock: { .nan })
        let flow = AnalyticsFlow<AnalyticsFlows.PeerInfoVisibility>(analytics: analytics, scope: scope)
        flow.step(.selectPublic)
        flow.finish(.success)
        analytics.screens.show(ObjectIdentifier(owner), screen: .chat, scope: scope)
        XCTAssertNil(analytics.screens.current)
        XCTAssertTrue(sent.isEmpty)
    }
}
