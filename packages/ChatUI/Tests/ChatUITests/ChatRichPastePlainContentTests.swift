import XCTest
import RichTextEditorCore
import TelegramCore
@testable import ChatUI

/// The plain-text downgrade used when the rich editor is not opened on paste.
///
/// A pasted rich fragment is inserted into the composer as text instead of taking the composer over
/// with the editor. The inline formatting the fragment can be expressed with (bold, italic, code,
/// quotes, links) is kept; a structural fragment (a table, a heading, a formula) is flattened to its
/// text rendering — the same one the rich editor's plain preview shows.
final class ChatRichPastePlainContentTests: XCTestCase {

    private func boldRun(_ text: String) -> TextRun {
        var attributes = CharacterAttributes.plain
        attributes.bold = true
        return TextRun(text: text, attributes: attributes)
    }

    /// A fragment that is entity-expressible keeps its inline formatting.
    func testEntityExpressibleFragmentKeepsItsInlineFormatting() {
        let document = Document(blocks: [
            .paragraph(ParagraphBlock(id: BlockID.generate(), style: .body, runs: [
                boldRun("bold "),
                TextRun(text: "plain"),
            ]))
        ])
        let content = richTextPastePlainContent(document)
        XCTAssertEqual(content.text, "bold plain")
        XCTAssertEqual(content.entities.count, 1)
        if case let .Bold(range) = content.entities[0].type {
            XCTAssertEqual(range, 0 ..< 5)
        } else {
            XCTFail("the bold entity should survive the downgrade, got \(content.entities[0].type)")
        }
    }

    /// A structural fragment (a table) is flattened to its text rendering — a table row becomes
    /// tab-separated cells, so no content is silently dropped.
    func testStructuralFragmentIsFlattenedToText() {
        let cell = Cell(id: BlockID.generate(), blocks: [
            .paragraph(ParagraphBlock(id: BlockID.generate(), style: .body, runs: [TextRun(text: "cell a")]))
        ])
        let table = TableBlock(id: BlockID.generate(), columns: [ColumnSpec(width: 1), ColumnSpec(width: 1)], rows: [
            Row(id: BlockID.generate(), cells: [cell, Cell(id: BlockID.generate(), blocks: [
                .paragraph(ParagraphBlock(id: BlockID.generate(), style: .body, runs: [TextRun(text: "cell b")]))
            ])])
        ])
        let document = Document(blocks: [.table(table)])
        let content = richTextPastePlainContent(document)
        XCTAssertTrue(content.text.contains("\t"), "a table row should keep its cell separator")
        XCTAssertTrue(content.text.contains("cell a"))
        XCTAssertTrue(content.text.contains("cell b"))
    }

    /// The downgrade never produces an empty result for content that has text.
    func testDowngradeNeverEmptiesNonEmptyContent() {
        let document = Document(blocks: [
            .paragraph(ParagraphBlock(id: BlockID.generate(), style: .body, runs: [TextRun(text: "text")]))
        ])
        XCTAssertFalse(richTextPastePlainContent(document).text.isEmpty)
    }
}
