import XCTest
import RichTextEditorCore
@testable import ChatUI

/// The merge of a pasted rich fragment into the text around the caret.
///
/// When a rich fragment is pasted into the composer, the editor takes over the whole composer
/// content, so the text around the caret has to be spliced around the fragment. The rules mirror the
/// editor's own fragment insertion (`DocumentCanvasView.insertFragment`).
final class ChatRichPasteComposerMergeTests: XCTestCase {

    private func paragraph(_ text: String) -> Block {
        return .paragraph(ParagraphBlock(id: BlockID.generate(), style: .body, runs: [TextRun(text: text)]))
    }

    private func merge(fragment: [Block], before: [Block], after: [Block]) -> [Block] {
        return RichTextComposerPasteMerge.merge(
            fragment: fragment,
            before: before,
            after: after,
            paragraph: { block in
                if case let .paragraph(paragraph) = block {
                    return paragraph
                }
                return nil
            },
            makeParagraph: { .paragraph($0) })
    }

    private func plainText(_ blocks: [Block]) -> String {
        return blocks.compactMap { block -> String? in
            if case let .paragraph(paragraph) = block {
                return paragraph.runs.map(\.text).joined()
            }
            return nil
        }.joined(separator: "\n")
    }

    /// The caret sits in "hello | world" and the pasted fragment is "X": the result is ONE paragraph
    /// reading "hello X world" — the typed text is kept and no line break is introduced.
    func testSingleParagraphFragmentMergesInlineWithSurroundingText() {
        let merged = merge(
            fragment: [paragraph("X")],
            before: [paragraph("hello ")],
            after: [paragraph(" world")])
        XCTAssertEqual(merged.count, 1, "expected a single merged paragraph, got \(merged)")
        XCTAssertEqual(plainText(merged), "hello X world")
    }

    /// No line break may appear at the seam: "hello \nX\n world" would read as three paragraphs.
    func testNoSpuriousLineBreaksAtTheSeams() {
        let merged = merge(
            fragment: [paragraph("X")],
            before: [paragraph("hello ")],
            after: [paragraph(" world")])
        XCTAssertFalse(plainText(merged).contains("\n"), "unexpected line break in \(plainText(merged))")
    }

    /// The text before the caret joins the fragment's first paragraph block — the same rule the
    /// editor's own fragment insertion applies.
    func testTextBeforeTheCaretJoinsTheFirstParagraphBlock() {
        let merged = merge(
            fragment: [paragraph("b"), .table(TableBlock(id: BlockID.generate(), rows: []))],
            before: [paragraph("a")],
            after: [paragraph("c")])
        XCTAssertEqual(plainText(merged), "ab\nc", "the text before the caret joins the fragment's first paragraph")
    }

    /// A fragment that starts with a structural block (a table) keeps the typed text before it in
    /// its own paragraph — the text is never swallowed into the fragment.
    func testTextBeforeTheCaretIsKeptSeparateFromALeadingTable() {
        let merged = merge(
            fragment: [.table(TableBlock(id: BlockID.generate(), rows: [])), paragraph("b")],
            before: [paragraph("a")],
            after: [])
        XCTAssertEqual(plainText(merged), "a\nb", "a leading table must not swallow the typed text")
    }

    /// A table is not a paragraph: it keeps its own block and the surrounding text stays around it.
    func testStructuralFragmentKeepsItsOwnBlock() {
        let merged = merge(
            fragment: [.table(TableBlock(id: BlockID.generate(), rows: []))],
            before: [paragraph("before")],
            after: [paragraph("after")])
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(plainText(merged), "before\nafter")
    }

    // MARK: - Degenerate inputs

    func testEmptyComposerKeepsTheFragmentAsIs() {
        let merged = merge(fragment: [paragraph("X")], before: [], after: [])
        XCTAssertEqual(plainText(merged), "X")
    }

    func testEmptyFragmentKeepsTheSurroundingText() {
        let merged = merge(fragment: [], before: [paragraph("a")], after: [paragraph("b")])
        XCTAssertEqual(plainText(merged), "a\nb")
    }

    /// Text only after the caret: the fragment merges with it.
    func testFragmentMergesWithTextAfterTheCaretOnly() {
        let merged = merge(fragment: [paragraph("X")], before: [], after: [paragraph(" tail")])
        XCTAssertEqual(plainText(merged), "X tail")
    }

    /// Text only before the caret: the fragment merges with it.
    func testFragmentMergesWithTextBeforeTheCaretOnly() {
        let merged = merge(fragment: [paragraph("X")], before: [paragraph("head ")], after: [])
        XCTAssertEqual(plainText(merged), "head X")
    }

    // MARK: - Editing an existing message

    /// While editing a message the composer text belongs to that message, so the surrounding text is
    /// still handed to the editor — the pasted fragment lands INSIDE the edited message instead of
    /// replacing it.
    func testSurroundingTextOfTheEditedMessageIsPreserved() {
        let merged = merge(
            fragment: [paragraph("X")],
            before: [paragraph("hello ")],
            after: [paragraph(" world")])
        XCTAssertEqual(plainText(merged), "hello X world")
    }

    // MARK: - Whitespace around the caret

    /// The spaces around the caret belong to the user's text — trimming them would turn
    /// "hello | world" into "helloworld".
    func testSpacesAroundTheCaretArePreserved() {
        let merged = merge(
            fragment: [paragraph("X")],
            before: [paragraph("hello ")],
            after: [paragraph(" world")])
        XCTAssertEqual(plainText(merged), "hello X world")
    }

    /// A blank line the user typed before the caret is a paragraph break, not something to trim.
    func testBlankLineBeforeTheCaretIsPreserved() {
        let merged = merge(
            fragment: [paragraph("X")],
            before: [paragraph("first\n\n")],
            after: [])
        XCTAssertEqual(plainText(merged), "first\n\nX")
    }
}
