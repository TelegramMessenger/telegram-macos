import Foundation
import XCTest
import Postbox
import TelegramCore
@testable import ChatUI

final class ChatRichTextProfileButtonTests: XCTestCase {
    func testProfileActionPreservesPeerThroughDocumentEncoding() throws {
        let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(0x123456789))
        let action = buttonAction(from: .openUserProfile(peerId: peerId))
        let saved = try JSONEncoder().encode(action)
        let restored = try JSONDecoder().decode(type(of: action), from: saved)
        guard case let .openUserProfile(restoredPeerId) = replyMarkupButtonAction(from: restored) else {
            return XCTFail("Profile action was lost after document encoding")
        }
        XCTAssertEqual(restoredPeerId, peerId)
        XCTAssertEqual(buttonAction(from: .openUserProfile(peerId: restoredPeerId)), action)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "userProfile")
    }

    func testProfileActionForNonUserPeerIsDisabled() throws {
        let peerId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(12345))
        let saved = try JSONSerialization.data(withJSONObject: [
            "type": "userProfile", "value": peerId.toInt64()
        ])
        let restored = try JSONDecoder().decode(type(of: buttonAction(from: .disabled)), from: saved)
        XCTAssertEqual(replyMarkupButtonAction(from: restored), .disabled)
    }

    func testPreviouslySavedOpaqueProfileActionStillOpensOriginalPeer() throws {
        let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(0x123456789))
        let encoder = PostboxEncoder()
        ReplyMarkupButtonAction.openUserProfile(peerId: peerId).encode(encoder)
        let saved = try JSONSerialization.data(withJSONObject: [
            "type": "unsupported",
            "kind": "replyMarkupButtonAction",
            "value": encoder.makeData().base64EncodedString()
        ])
        let restored = try JSONDecoder().decode(type(of: buttonAction(from: .disabled)), from: saved)
        guard case let .openUserProfile(restoredPeerId) = replyMarkupButtonAction(from: restored) else {
            return XCTFail("Legacy profile action was lost")
        }
        XCTAssertEqual(restoredPeerId, peerId)
    }
}
