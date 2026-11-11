import AppKit
import XCTest
import Postbox
import TelegramCore
import InstantPageUI
@testable import ChatUI

final class ChatRichMentionRoutingTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    func testLargeUserIdIsNotInterpretedAsPackedPeerId() {
        let marker = "tg://user?id=5000000000"
        let peer = chatRichMessageMentionPeerId(marker)
        XCTAssertEqual(peer?.namespace, Namespaces.Peer.CloudUser)
        XCTAssertEqual(peer?.id._internalGetInt64Value(), 5_000_000_000)
    }

    func testMalformedAndImpossibleMentionsCannotRoute() {
        for value in ["0", "-1", "-9223372036854775808", "4503599627370496", "9223372036854775807", "garbage"] {
            XCTAssertNil(chatRichMessageMentionPeerId("tg://user?id=" + value))
        }
        XCTAssertNil(chatRichMessageMentionPeerId("https://telegram.org"))
    }

    func testInvalidRichMentionRemainsPlainText() {
        for value: Int64 in [0, -1, Int64.min, 1 << 52, Int64.max] {
            let text = attributedStringForRichText(.textMentionName(text: .plain("Alice"), peerId: value), styleStack: InstantPageTextStyleStack())
            XCTAssertEqual(text.string, "Alice")
            var routed = false
            text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, _, _ in
                if attributes.values.contains(where: { $0 is InstantPageUrlItem }) { routed = true }
            }
            XCTAssertFalse(routed, "Impossible user ID must not create an active profile link")
        }
    }
}
