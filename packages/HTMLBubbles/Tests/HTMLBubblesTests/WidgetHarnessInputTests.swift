import XCTest
@testable import WidgetSandbox
@testable import HTMLBubbles

final class WidgetHarnessInputTests: XCTestCase {
    func testHarnessClicksCountAsPointerActivation() throws {
        let message = #"{"type":"event","trusted":true,"ev":{"type":"click","targetId":5,"button":0}}"#
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(message.utf8)) as? [String: Any])
        XCTAssertFalse(WidgetHost.isUserActivation(try XCTUnwrap(original["ev"])))
        let converted = HTMLBubbleState.debugPointerClickMessage(message)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(converted.utf8)) as? [String: Any])
        let event = try XCTUnwrap(object["ev"] as? [String: Any])
        XCTAssertTrue(WidgetHost.isUserActivation(event))
        XCTAssertEqual(event["targetId"] as? Int, 5)
        XCTAssertEqual(object["trusted"] as? Bool, true)
    }

    func testHarnessDoesNotPromoteUntrustedOrNonClickEvents() {
        for message in [#"{"type":"event","trusted":false,"ev":{"type":"click","targetId":5}}"#, #"{"type":"event","trusted":true,"ev":{"type":"pointermove","targetId":5}}"#, "invalid"] {
            XCTAssertEqual(HTMLBubbleState.debugPointerClickMessage(message), message)
        }
    }
}
