import XCTest

// The production merge helper is extracted from the real source by run.py, so these tests
// exercise the shipped code rather than a copy of it.
//
// Minimal stand-ins for the editor's block model: the merge helper only needs to know which
// blocks are paragraphs and how to read/join their runs.
struct ParagraphBlock: Equatable {
    var runs: [String]
    init(runs: [String] = []) { self.runs = runs }
}

enum Block {
    case paragraph(ParagraphBlock)
    case structural(String)
}

enum RichTextOutgoingBlock {
    case paragraph(ParagraphBlock)
    case structural(String)
}

__MERGE__
/// Test-side convenience wrapper over the production helper, instantiated for the concrete
/// `Block` type the way the production call sites do.
func mergeBlocks(fragment: [Block], before: [Block], after: [Block]) -> [Block] {
    RichTextComposerPasteMerge.merge(
        fragment: fragment,
        before: before,
        after: after,
        paragraph: { if case let .paragraph(paragraph) = $0 { return paragraph }; return nil },
        makeParagraph: { .paragraph($0) })
}


/// The plain text of a block list, with blocks separated by a newline — the editor's
/// paragraph-separated plain-text conversion.
func plainText(_ blocks: [Block]) -> String {
    blocks.compactMap { block -> String? in
        switch block {
        case let .paragraph(paragraph): return paragraph.runs.joined()
        case let .structural(value): return value
        }
    }.joined(separator: "\n")
}

func para(_ text: String) -> Block { .paragraph(ParagraphBlock(runs: [text])) }

final class RichPasteMergeTests: XCTestCase {

    // MARK: - The composer's text must survive the paste

    /// The reviewer's canonical case: the caret sits in "hello | world" and the pasted fragment is
    /// "X". The result is ONE paragraph reading "hello X world" — the typed text is kept and no
    /// line break is introduced at the seam.
    func testSingleParagraphFragmentMergesInlineWithSurroundingText() {
        let merged = mergeBlocks(
            fragment: [para("X")],
            before: [para("hello ")],
            after: [para(" world")])
        XCTAssertEqual(merged.count, 1, "expected a single merged paragraph, got \(merged)")
        XCTAssertEqual(plainText(merged), "hello X world")
    }

    /// No line break may appear at the seam: "hello \nX\n world" would read as three paragraphs.
    func testNoSpuriousLineBreaksAtTheSeams() {
        let merged = mergeBlocks(
            fragment: [para("X")],
            before: [para("hello ")],
            after: [para(" world")])
        XCTAssertFalse(plainText(merged).contains("\n"), "unexpected line break in \(plainText(merged))")
    }

    /// The text before the caret joins the fragment's first block when that block is a paragraph —
    /// the same rule the editor's own fragment insertion applies (`DocumentCanvasView.insertFragment`).
    func testTextBeforeTheCaretJoinsTheFirstParagraphBlock() {
        let merged = mergeBlocks(
            fragment: [para("b"), .structural("table")],
            before: [para("a")],
            after: [para("c")])
        XCTAssertEqual(plainText(merged), "ab\ntable\nc",
                       "the typed text before the caret joins the fragment's first paragraph")
    }

    /// A fragment that starts with a structural block (a table) keeps the typed text before it in
    /// its own paragraph — the text is never swallowed into the fragment.
    func testTextBeforeTheCaretIsKeptSeparateFromALeadingTable() {
        let merged = mergeBlocks(
            fragment: [.structural("table"), para("b")],
            before: [para("a")],
            after: [])
        XCTAssertEqual(plainText(merged), "a\ntable\nb",
                       "a leading table must not swallow the typed text before the caret")
    }

    // MARK: - Structural fragments

    /// A table is not a paragraph: it keeps its own block and the surrounding text stays around it.
    func testStructuralFragmentKeepsItsOwnBlock() {
        let merged = mergeBlocks(
            fragment: [.structural("table")],
            before: [para("before")],
            after: [para("after")])
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(plainText(merged), "before\ntable\nafter")
    }

    // MARK: - Degenerate inputs

    func testEmptyComposerKeepsTheFragmentAsIs() {
        let merged = mergeBlocks(fragment: [para("X")], before: [], after: [])
        XCTAssertEqual(plainText(merged), "X")
    }

    func testEmptyFragmentKeepsTheSurroundingText() {
        let merged = mergeBlocks(fragment: [], before: [para("a")], after: [para("b")])
        XCTAssertEqual(plainText(merged), "a\nb")
    }

    /// Text only after the caret: the fragment merges with it.
    func testFragmentMergesWithTextAfterTheCaretOnly() {
        let merged = mergeBlocks(fragment: [para("X")], before: [], after: [para(" tail")])
        XCTAssertEqual(plainText(merged), "X tail")
    }

    /// Text only before the caret: the fragment merges with it.
    func testFragmentMergesWithTextBeforeTheCaretOnly() {
        let merged = mergeBlocks(fragment: [para("X")], before: [para("head ")], after: [])
        XCTAssertEqual(plainText(merged), "head X")
    }
}
