import XCTest
import TelegramCore
import Postbox
import RichTextEditorCore
import RichTextEditorUI
@testable import ChatUI

final class ChatRichTextMarkerTests: XCTestCase {
    private func blocks(_ link: String) -> [RichTextOutgoingBlock] {
        var attributes = CharacterAttributes.plain
        attributes.bold = true
        attributes.link = link
        return [.paragraph(ParagraphBlock(id: .generate(), runs: [TextRun(text: "Alice", attributes: attributes)]))]
    }

    private func rich(_ link: String) throws -> RichText {
        let page = try XCTUnwrap(richTextInstantPage(from: blocks(link), media: [:]))
        guard case let .paragraph(text) = page.blocks.first else { throw NSError(domain: "block", code: 1) }
        return text
    }

    func testMentionUsesRawLargeUserIdInRichMessage() throws {
        XCTAssertEqual(try rich("tg://user?id=5000000000"), .textMentionName(text: .bold(.plain("Alice")), peerId: 5_000_000_000))
    }

    func testDateUsesFormattedRichText() throws {
        XCTAssertEqual(try rich("tg://timestamp?t=1800000000"), .textDate(text: .bold(.plain("Alice")), date: 1_800_000_000, format: nil))
    }

    func testInvalidMarkerRemainsLink() throws {
        for link in ["tg://user?id=0", "tg://user?id=-1", "tg://user?id=4503599627370496", "tg://timestamp?t=2147483648", "https://telegram.org"] {
            XCTAssertEqual(try rich(link), .url(text: .bold(.plain("Alice")), url: link, webpageId: nil))
        }
    }

    func testPlainSendPreservesMentionAndDateEntities() throws {
        let mention = richTextPlain(from: blocks("tg://user?id=5000000000"))
        let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(5_000_000_000))
        XCTAssertTrue(mention.entities.contains { $0.type == .TextMention(peerId: peerId) })
        let date = richTextPlain(from: blocks("tg://timestamp?t=1800000000"))
        XCTAssertTrue(date.entities.contains { if case let .FormattedDate(_, value) = $0.type { return value == 1_800_000_000 }; return false })
    }

    func testRichDateSurvivesEditorRoundTrip() throws {
        let page = InstantPage(blocks: [.paragraph(.textDate(text: .plain("Tomorrow"), date: 1_800_000_000, format: nil))], media: [:], isComplete: true, rtl: false, url: "", views: nil)
        let output = richTextOutgoing(from: page)
        let restored = try XCTUnwrap(richTextInstantPage(from: output.blocks, media: output.media))
        XCTAssertEqual(restored.blocks, page.blocks)
    }

    func testPlainFormattedDateSurvivesEditorRoundTrip() throws {
        let document = richTextDocument(text: "Tomorrow", entities: [.init(range: 0..<8, type: .FormattedDate(format: .full(timeFormat: .short, dateFormat: .short, dayOfWeek: false), date: 1_800_000_000))])
        let output = outgoingBlocks(fromSelection: document.blocks)
        let message = richTextPlain(from: output)
        XCTAssertTrue(message.entities.contains { if case let .FormattedDate(_, date) = $0.type { return date == 1_800_000_000 }; return false })
    }
}
