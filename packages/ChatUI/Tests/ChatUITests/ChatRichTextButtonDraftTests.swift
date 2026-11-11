import XCTest
import Postbox
import TelegramCore
import RichTextEditorCore
@testable import ChatUI

final class ChatRichTextButtonDraftTests: XCTestCase {
    func testCopyTextCanBeAuthoredAndEncodedWithoutChangingWhitespace() throws {
        var draft = ChatRichTextButtonDraft(action: .url("https://example.com"))
        draft.select(.copyText)
        draft.updateText("  two lines\nsecond 😀  ")
        let action = try XCTUnwrap(draft.validatedAction { _ in nil })
        XCTAssertEqual(action, .copyText("  two lines\nsecond 😀  "))
        XCTAssertEqual(try JSONDecoder().decode(ButtonAction.self, from: JSONEncoder().encode(action)), action)
        XCTAssertEqual(replyMarkupButtonAction(from: action), .copyText(payload: "  two lines\nsecond 😀  "))
    }

    func testUserProfileRequiresChoosingAUser() throws {
        var draft = ChatRichTextButtonDraft(action: .url("https://example.com"))
        draft.select(.userProfile)
        XCTAssertNil(draft.validatedAction { $0 })
        let id = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(5_000_000_000))
        draft.selectUser(id: id, name: "Test User")
        XCTAssertEqual(draft.profileId, id)
        XCTAssertEqual(draft.profileName, "Test User")
        XCTAssertEqual(draft.validatedAction { $0 }, .userProfile(peerId: id.toInt64()))
        XCTAssertEqual(replyMarkupButtonAction(from: draft.action), .openUserProfile(peerId: id))
    }

    func testChannelsAndGroupsCannotReplaceAChosenUser() {
        let user = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(42))
        var draft = ChatRichTextButtonDraft(action: .userProfile(peerId: user.toInt64()), profileName: "User")
        for namespace in [Namespaces.Peer.CloudChannel, Namespaces.Peer.CloudGroup, Namespaces.Peer.SecretChat] {
            draft.selectUser(id: PeerId(namespace: namespace, id: ._internalFromInt64Value(99)), name: "Invalid")
            XCTAssertEqual(draft.profileId, user)
            XCTAssertEqual(draft.profileName, "User")
        }
    }

    func testMalformedProfileIdsCannotBeSaved() {
        for raw: Int64 in [0, -1, Int64.min, Int64.max, 1 << 55, 1 << 32] {
            let draft = ChatRichTextButtonDraft(action: .userProfile(peerId: raw))
            XCTAssertNil(draft.profileId)
            XCTAssertNil(draft.validatedAction { $0 })
        }
    }

    func testChangingActionDropsIncompatiblePayloadAndSameChoicePreservesIt() {
        var draft = ChatRichTextButtonDraft(action: .copyText("keep"))
        draft.select(.copyText)
        XCTAssertEqual(draft.action, .copyText("keep"))
        draft.select(.url)
        XCTAssertEqual(draft.action, .url(""))
        draft.updateText("https://example.com")
        draft.select(.userProfile)
        XCTAssertNil(draft.profileId)
        draft.select(.copyText)
        XCTAssertEqual(draft.action, .copyText(""))
    }

    func testStaleUserSelectionCannotReplaceANewerAction() {
        var draft = ChatRichTextButtonDraft(action: .userProfile(peerId: 42))
        draft.select(.copyText)
        draft.updateText("new text")
        draft.selectUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(99)), name: "Late result")
        XCTAssertEqual(draft.action, .copyText("new text"))
        XCTAssertNil(draft.profileName)
    }

    func testOpaqueAndDisabledActionsRoundTripUntilExplicitlyReplaced() {
        for action: ButtonAction in [.disabled, .unsupported(kind: "unknown", payload: "opaque")] {
            var draft = ChatRichTextButtonDraft(action: action)
            XCTAssertNil(draft.choice)
            draft.updateText("ignored")
            XCTAssertEqual(draft.validatedAction { _ in nil }, action)
            draft.select(.copyText)
            XCTAssertEqual(draft.action, .copyText(""))
        }
    }

    func testURLValidationUsesNormalizedWholeValue() {
        let draft = ChatRichTextButtonDraft(action: .url("  EXAMPLE.COM  "))
        XCTAssertEqual(draft.validatedAction { value in
            XCTAssertEqual(value, "EXAMPLE.COM")
            return "https://example.com"
        }, .url("https://example.com"))
        XCTAssertNil(draft.validatedAction { _ in nil })
    }
}
