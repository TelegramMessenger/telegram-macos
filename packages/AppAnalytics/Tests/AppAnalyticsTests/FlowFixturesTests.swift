import XCTest
import TelegramCore
@testable import AppAnalytics

final class FlowFixturesTests: XCTestCase {
    private typealias Spec = AnalyticsFlows.PeerInfoVisibility

    private func loadFixtures() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("../../../../docs/analytics/fixtures/flows.json")
            .standardizedFileURL
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testFixtures() throws {
        let fixtures = try loadFixtures()
        XCTAssertEqual(fixtures["flow"] as? String, Spec.id)
        let cases = try XCTUnwrap(fixtures["cases"] as? [[String: Any]])
        XCTAssertFalse(cases.isEmpty)
        let commonKeys = Set(AnalyticsCommon.params().keys)

        for testCase in cases {
            let name = testCase["name"] as? String ?? "?"
            var now: TimeInterval = 0
            var sent: [(String, JSON)] = []
            var flow: AnalyticsFlow<Spec>?

            for op in try XCTUnwrap(testCase["ops"] as? [[String: Any]]) {
                now = Double(op["at_ms"] as? Int ?? 0) / 1000
                switch op["op"] as? String {
                case "start":
                    flow = AnalyticsFlow<Spec>(sink: { sent.append(($0, $1)) }, clock: { now })
                case "set":
                    let key = try XCTUnwrap(Spec.Param(rawValue: op["key"] as? String ?? ""), name)
                    flow?.setValue(key, (op["value"] as? String).map { .string($0) })
                case "set_if_absent":
                    let key = try XCTUnwrap(Spec.Param(rawValue: op["key"] as? String ?? ""), name)
                    let value = try XCTUnwrap(op["value"] as? String)
                    flow?.setValueIfAbsent(key, .string(value))
                case "step":
                    flow?.step(try XCTUnwrap(Spec.Step(rawValue: op["step"] as? String ?? ""), name))
                case "finish":
                    flow?.finish(try XCTUnwrap(AnalyticsFlowOutcome(rawValue: op["outcome"] as? String ?? ""), name))
                case "dispose":
                    flow = nil
                default:
                    XCTFail("\(name): unknown op \(op)")
                }
            }
            flow = nil

            let expected = try XCTUnwrap(testCase["expect"] as? [[String: Any]])
            XCTAssertEqual(sent.count, expected.count, name)
            for (event, expectedEvent) in zip(sent, expected) {
                XCTAssertEqual(event.0, expectedEvent["type"] as? String, name)
                guard case var .dictionary(data) = event.1 else {
                    XCTFail("\(name): data is not a dictionary")
                    continue
                }
                for key in commonKeys {
                    XCTAssertNotNil(data.removeValue(forKey: key), "\(name): missing common param \(key)")
                }
                let expectedData = try JSONSerialization.data(withJSONObject: try XCTUnwrap(expectedEvent["data"]))
                XCTAssertEqual(JSON.dictionary(data), JSON(data: expectedData), name)
            }
        }
    }
}
