#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasPullQuotePlainClipboardTests: XCTestCase {
    private final class FakePasteboard: TextPasteboard {
        var string: String? { didSet { richFragment = nil } }
        var richFragment: Data?
        var hasStrings: Bool { !(string ?? "").isEmpty }
    }

    private func canvas(_ blocks: [Block]) -> (DocumentCanvasView, FakePasteboard) {
        let canvas = DocumentCanvasView()
        let pasteboard = FakePasteboard()
        canvas.pasteboard = pasteboard
        canvas.setBlocks(blocks, width: 400)
        return (canvas, pasteboard)
    }

    private func quote(_ body: String = "Quoted words", author: String = "Ada Lovelace", id: String = "q") -> Block {
        .pullQuote(PullQuote(id: BlockID(id), runs: [TextRun(text: body)], author: [TextRun(text: author)]))
    }

    private func region(_ canvas: DocumentCanvasView, _ ref: TextNodeRef) throws -> LeafTextRegion {
        try XCTUnwrap(canvas.allLeafRegions().first { $0.ref == ref })
    }

    func testBodyAndAuthorHaveNewlineInEitherSelectionDirection() throws {
        let (canvas, pasteboard) = canvas([quote()])
        let body = try region(canvas, .pullQuote(BlockID("q")))
        let author = try region(canvas, .quoteAuthor(BlockID("q")))
        let before = canvas.currentBlocks()
        for range in [(body.globalStart, author.globalStart + author.length),
                      (author.globalStart + author.length, body.globalStart)] {
            canvas.selectedGlobalRange = range
            canvas.copy(nil)
            XCTAssertEqual(pasteboard.string, "Quoted words\nAda Lovelace")
            XCTAssertEqual(canvas.text(inGlobalRange: range.0, range.1), "Quoted wordsAda Lovelace")
            XCTAssertEqual(canvas.selectedGlobalRange.0, range.0)
            XCTAssertEqual(canvas.selectedGlobalRange.1, range.1)
            XCTAssertEqual(canvas.currentBlocks(), before)
            XCTAssertNotNil(pasteboard.richFragment)
        }
    }

    func testPartialSelectionSlicesBothSidesUsingUTF16() throws {
        let (canvas, pasteboard) = canvas([quote("A𝄞BC", author: "D𝄞EF")])
        let body = try region(canvas, .pullQuote(BlockID("q")))
        let author = try region(canvas, .quoteAuthor(BlockID("q")))
        canvas.selectedGlobalRange = (body.globalStart + 1, author.globalStart + 3)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "𝄞BC\nD𝄞")
    }

    func testBodyOnlyAndSelectionEndingAtAuthorStartDoNotAddSeparator() throws {
        let (canvas, pasteboard) = canvas([quote()])
        let body = try region(canvas, .pullQuote(BlockID("q")))
        let author = try region(canvas, .quoteAuthor(BlockID("q")))
        for end in [body.globalStart + body.length, author.globalStart] {
            canvas.selectedGlobalRange = (body.globalStart + 7, end)
            canvas.copy(nil)
            XCTAssertEqual(pasteboard.string, "words")
        }
    }

    func testAuthorOnlyCopyClearsRichFragmentAndAddsNoSeparator() throws {
        let (canvas, pasteboard) = canvas([quote()])
        let author = try region(canvas, .quoteAuthor(BlockID("q")))
        canvas.selectAllText()
        canvas.copy(nil)
        XCTAssertNotNil(pasteboard.richFragment)
        canvas.selectedGlobalRange = (author.globalStart + 4, author.globalStart + 7)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "Lov")
        XCTAssertNil(pasteboard.richFragment)
    }

    func testSelectionStartingAtBodyEndAddsNoLeadingSeparator() throws {
        let (canvas, pasteboard) = canvas([quote()])
        let body = try region(canvas, .pullQuote(BlockID("q")))
        let author = try region(canvas, .quoteAuthor(BlockID("q")))
        canvas.selectedGlobalRange = (body.globalStart + body.length, author.globalStart + 3)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "Ada")
    }

    func testEmptyBodyOrAuthorAddsNoSeparator() {
        for (body, author, expected) in [("", "Ada", "Ada"), ("Quote", "", "Quote")] {
            let (canvas, pasteboard) = canvas([quote(body, author: author)])
            canvas.selectAllText()
            canvas.copy(nil)
            XCTAssertEqual(pasteboard.string, expected)
        }
    }

    func testRawNewlinesAndTabsArePreservedBesidesStructuralBoundary() {
        let (canvas, pasteboard) = canvas([quote("one\r\ntwo\n", author: "\nAda\tLovelace")])
        canvas.selectAllText()
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "one\r\ntwo\n\n\nAda\tLovelace")
    }

    func testNestedQuoteUsesMatchingBodyAndAuthor() throws {
        let (canvas, pasteboard) = canvas([
            .blockQuote(BlockQuote(id: BlockID("outer"), children: [quote()], collapsed: false)),
            quote("Other", author: "Grace", id: "other")
        ])
        let body = try region(canvas, .pullQuote(BlockID("q")))
        let author = try region(canvas, .quoteAuthor(BlockID("q")))
        canvas.selectedGlobalRange = (body.globalStart + 7, author.globalStart + 3)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "words\nAda")
        let data = try XCTUnwrap(pasteboard.richFragment)
        let document = try DocumentCodec.decode(data)
        guard case let .blockQuote(outer) = document.blocks.first,
              case let .pullQuote(copied) = outer.children.first else { return XCTFail("Expected nested quote") }
        XCTAssertEqual(copied.text, "words")
    }

    func testInlineFormattingIsUnchangedByPlainCopy() throws {
        let (canvas, pasteboard) = canvas([
            .pullQuote(PullQuote(id: BlockID("q"),
                                 runs: [TextRun(text: "ab"), TextRun(text: "CD", attributes: CharacterAttributes(bold: true))],
                                 author: [TextRun(text: "Ada", attributes: CharacterAttributes(underline: true))]))
        ])
        let body = try region(canvas, .pullQuote(BlockID("q")))
        let author = try region(canvas, .quoteAuthor(BlockID("q")))
        let before = canvas.currentBlocks()
        canvas.selectedGlobalRange = (body.globalStart + 1, author.globalStart + 2)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "bCD\nAd")
        let document = try DocumentCodec.decode(XCTUnwrap(pasteboard.richFragment))
        guard case let .pullQuote(copied) = document.blocks.first else { return XCTFail("Expected quote") }
        XCTAssertEqual(copied.runs.filter { $0.attributes.bold }.map(\.text).joined(), "CD")
        XCTAssertEqual(canvas.currentBlocks(), before)
    }

    func testOrdinaryParagraphCopyAndTextInputRemainUnchanged() {
        let (canvas, pasteboard) = canvas([
            .paragraph(ParagraphBlock(id: BlockID("a"), runs: [TextRun(text: "first\r\nline")])),
            .paragraph(ParagraphBlock(id: BlockID("b"), runs: [TextRun(text: "second")]))
        ])
        canvas.selectAllText()
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "first\r\nlinesecond")
        XCTAssertEqual(canvas.text(inGlobalRange: canvas.selFrom, canvas.selTo), pasteboard.string)
    }

    func testCollapsedSelectionDoesNotWritePasteboard() {
        let (canvas, pasteboard) = canvas([quote()])
        pasteboard.string = "keep"
        canvas.setCaret(global: canvas.boxes[0].textStart)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "keep")
    }
}
#endif
