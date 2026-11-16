import XCTest
import WidgetSandbox
import WalletEngineFFI
@testable import WalletContext
@testable import WalletUI

@available(macOS 10.15, *)
private struct InvalidWidgetPayload: Error {}

@available(macOS 10.15, *)
final class WidgetWalletTests: XCTestCase {
    private let address = "EQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAM9c"
    private var wallet: WalletContext.WalletInfo {
        .init(address: "0:" + String(repeating: "0", count: 64), publicKey: String(repeating: "1", count: 64), canSign: true)
    }

    private func transaction(_ object: [String: Any]) throws -> WidgetTransactionIntent {
        guard let checked = SdkPolicy.checkWalletTransaction(object) else { throw InvalidWidgetPayload() }
        let data = try JSONSerialization.data(withJSONObject: checked.json)
        return try widgetTransactionIntent(json: String(decoding: data, as: UTF8.self), now: 1000, walletAddress: wallet.address)
    }

    private func signature(_ object: [String: Any]) throws -> TonConnectSignDataRequest {
        guard let checked = SdkPolicy.checkSignDataPayload(object) else { throw InvalidWidgetPayload() }
        let data = try JSONSerialization.data(withJSONObject: checked.json)
        return try widgetSignDataRequest(json: String(decoding: data, as: UTF8.self), walletAddress: wallet.address)
    }

    func testTransactionPreservesBatchPayloadStateInitAndExpiry() throws {
        let payload = try transaction(["network": "-239", "from": wallet.address, "valid_until": 2000, "messages": [["address": address, "amount": "1000000000", "payload": "te6ccgEBAQEAAgAAAA==", "stateInit": "AQID"]]])
        XCTAssertEqual(payload.intent.expiration, .exact(unixTimestamp: 2000))
        let message = try XCTUnwrap(payload.intent.messages.first)
        XCTAssertEqual(message.destination, address)
        XCTAssertEqual(message.stateInit, "AQID")
        if case let .exact(amount) = message.amount { XCTAssertEqual(amount, "1000000000") } else { XCTFail() }
        if case let .rawPayload(value) = message.body { XCTAssertEqual(value, "te6ccgEBAQEAAgAAAA==") } else { XCTFail() }
        XCTAssertTrue(message.bounce)
    }

    func test255MessagesAndLimit() throws {
        let message = ["address": address, "amount": "0"]
        XCTAssertEqual(try transaction(["messages": Array(repeating: message, count: 255)]).intent.messages.count, 255)
        XCTAssertThrowsError(try transaction(["messages": Array(repeating: message, count: 256)]))
        XCTAssertThrowsError(try transaction(["messages": []]))
    }

    func testWrongNetworkSenderRawDestinationAndInvalidAmountAreRejected() {
        let messages = [["address": address, "amount": "1"]]
        XCTAssertThrowsError(try transaction(["network": "-3", "messages": messages]))
        XCTAssertThrowsError(try transaction(["from": "0:" + String(repeating: "1", count: 64), "messages": messages]))
        XCTAssertThrowsError(try transaction(["messages": [["address": wallet.address, "amount": "1"]]]))
        for amount in ["-1", "1.5", "", "1e3"] {
            XCTAssertThrowsError(try transaction(["messages": [["address": address, "amount": amount]]]))
        }
    }

    func testExpiredFractionalAndBooleanTimestampsAreRejected() {
        for expiry: Any in [1000, 999, 1000.5, true] {
            XCTAssertThrowsError(try transaction(["valid_until": expiry, "messages": [["address": address, "amount": "1"]]]))
        }
    }

    func testSigningTextBytesAndCellKeepTheirContent() throws {
        let text = try signature(["type": "text", "text": "Confirm order"])
        XCTAssertEqual(text.payload, .text(text: "Confirm order"))
        let binary = try signature(["type": "binary", "bytes": "AQID"])
        XCTAssertEqual(binary.payload, .binary(bytes: "AQID"))
        let cell = try signature(["type": "cell", "schema": "foo$_ x:uint8 = Foo;", "cell": "AQID"])
        XCTAssertEqual(cell.payload, .cell(schema: "foo$_ x:uint8 = Foo;", cell: "AQID"))
    }

    func testSigningRefusesWrongNetworkSenderAndMalformedBase64() {
        XCTAssertThrowsError(try signature(["type": "text", "text": "test", "network": "-3"]))
        XCTAssertThrowsError(try signature(["type": "text", "text": "test", "from": "0:" + String(repeating: "2", count: 64)]))
        XCTAssertThrowsError(try signature(["type": "binary", "bytes": "!"]))
        XCTAssertThrowsError(try signature(["type": "unsupported"]))
    }
    func testDoubleClickCannotApproveBeforeWindowDelayAndReopeningResetsIt() {
        var gate = WalletTonConnectInputGate()
        gate.appear(now: 100, delay: 0.75)
        XCTAssertFalse(gate.allowsInput(now: 100))
        XCTAssertFalse(gate.allowsInput(now: 100.25))
        XCTAssertFalse(gate.allowsInput(now: 100.749))
        XCTAssertTrue(gate.allowsInput(now: 100.75))
        gate.appear(now: 200, delay: 0.75)
        XCTAssertFalse(gate.allowsInput(now: 200.5))
        XCTAssertTrue(gate.allowsInput(now: 200.75))
    }

}
