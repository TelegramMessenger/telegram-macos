import XCTest
import TelegramCore
import RichTextEditorCore
import RichTextEditorUI
@testable import ChatUI

final class ChatRichTextSpoilerTests: XCTestCase {
    func testRichSpoilerWrapsStylesAndLinks() throws {
        for link in [nil, "https://telegram.org"] as [String?] {
            var attributes = CharacterAttributes.plain
            attributes.bold = true
            attributes.spoiler = true
            attributes.link = link
            let blocks: [RichTextOutgoingBlock] = [.paragraph(ParagraphBlock(id: .generate(), runs: [TextRun(text: "Secret", attributes: attributes)]))]
            let page = try XCTUnwrap(richTextInstantPage(from: blocks, media: [:]))
            let inner: RichText = .bold(.plain("Secret"))
            let expected: RichText = link.map { .url(text: inner, url: $0, webpageId: nil) } ?? inner
            XCTAssertEqual(page.blocks, [.paragraph(.textSpoiler(text: expected))])
        }
    }

    func testOrdinaryTextStaysVisible() throws {
        let blocks: [RichTextOutgoingBlock] = [.paragraph(ParagraphBlock(id: .generate(), runs: [TextRun(text: "Visible")]))]
        let page = try XCTUnwrap(richTextInstantPage(from: blocks, media: [:]))
        XCTAssertEqual(page.blocks, [.paragraph(.plain("Visible"))])
    }
}
