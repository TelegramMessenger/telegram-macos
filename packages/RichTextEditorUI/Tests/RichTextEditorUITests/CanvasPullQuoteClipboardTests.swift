#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasPullQuoteClipboardTests: AppKitTestCase {
    private final class FakePasteboard: TextPasteboard {
        var string: String? { didSet { richFragment = nil } }
        var richFragment: Data?
        var hasStrings: Bool { !(string ?? "").isEmpty }
    }

    private func canvas(_ blocks: [Block], pasteboard: FakePasteboard = FakePasteboard()) -> DocumentCanvasView {
        let canvas = DocumentCanvasView()
        canvas.setBlocks(blocks, width: 400)
        canvas.pasteboard = pasteboard
        return canvas
    }

    private func quoteCanvas() -> (DocumentCanvasView, FakePasteboard) {
        let pasteboard = FakePasteboard()
        let quote = PullQuote(id: BlockID("q"),
                              runs: [TextRun(text: "Quoted "), TextRun(text: "words", attributes: CharacterAttributes(bold: true))],
                              author: [TextRun(text: "Ada "), TextRun(text: "Lovelace", attributes: CharacterAttributes(underline: true))])
        return (canvas([.pullQuote(quote)], pasteboard: pasteboard), pasteboard)
    }

    private func regions(_ canvas: DocumentCanvasView) throws -> (body: LeafTextRegion, author: LeafTextRegion) {
        let body = try XCTUnwrap(canvas.allLeafRegions().first { if case .pullQuote = $0.ref { return true }; return false })
        let author = try XCTUnwrap(canvas.allLeafRegions().first { if case .quoteAuthor = $0.ref { return true }; return false })
        return (body, author)
    }

    private func copiedQuote(_ canvas: DocumentCanvasView, _ pasteboard: FakePasteboard) throws -> PullQuote {
        canvas.copy(nil)
        let data = try XCTUnwrap(pasteboard.richFragment)
        let document = try DocumentCodec.decode(data)
        XCTAssertEqual(document.blocks.count, 1)
        return try XCTUnwrap(document.blocks.compactMap { if case let .pullQuote(quote) = $0 { return quote }; return nil }.first)
    }

    func test_selectAllAuthoredQuote_roundTripsAuthorAndAttributes() throws {
        let (source, pasteboard) = quoteCanvas()
        let spans = try regions(source)
        source.selectAllText()
        XCTAssertEqual(source.selTo, spans.author.globalStart + spans.author.length)
        let quote = try copiedQuote(source, pasteboard)
        XCTAssertEqual(quote.text, "Quoted words")
        XCTAssertEqual(quote.author.map(\.text).joined(), "Ada Lovelace")
        XCTAssertEqual(quote.runs.filter { $0.attributes.bold }.map(\.text).joined(), "words")
        XCTAssertEqual(quote.author.filter { $0.attributes.underline }.map(\.text).joined(), "Lovelace")
        XCTAssertTrue(quote.author.allSatisfy { !$0.attributes.bold && !$0.attributes.italic && $0.attributes.foreground == nil })
        XCTAssertNotEqual(quote.id, BlockID("q"))
        XCTAssertEqual(pasteboard.string, "Quoted words\nAda Lovelace")

        let destination = canvas([.paragraph(ParagraphBlock(id: BlockID("p")))], pasteboard: pasteboard)
        let before = destination.currentBlocks()
        let undo = UndoManager(); undo.groupsByEvent = false; destination.undoManagerOverride = undo
        destination.setCaret(global: destination.boxes[0].textStart)
        undo.beginUndoGrouping(); destination.paste(nil); undo.endUndoGrouping()
        guard case let .pullQuote(pasted) = destination.currentBlocks().first else { return XCTFail("Expected pasted quote") }
        XCTAssertEqual(pasted.runs, quote.runs)
        XCTAssertEqual(pasted.author, quote.author)
        XCTAssertNotEqual(pasted.id, quote.id)
        undo.undo()
        XCTAssertEqual(destination.currentBlocks(), before)
        undo.redo()
        guard case let .pullQuote(redone) = destination.currentBlocks().first else { return XCTFail("Expected redone quote") }
        XCTAssertEqual(redone.author, quote.author)
    }

    func test_reverseSelectionThroughAuthorEnd_preservesAuthor() throws {
        let (canvas, pasteboard) = quoteCanvas()
        let spans = try regions(canvas)
        canvas.selectedGlobalRange = (spans.author.globalStart + spans.author.length, spans.body.globalStart)
        let quote = try copiedQuote(canvas, pasteboard)
        XCTAssertEqual(quote.text, "Quoted words")
        XCTAssertEqual(quote.author.map(\.text).joined(), "Ada Lovelace")
    }

    func test_bodyOnlySelection_doesNotCopyUnselectedAuthor() throws {
        let (canvas, pasteboard) = quoteCanvas()
        let spans = try regions(canvas)
        canvas.selectedGlobalRange = (spans.body.globalStart, spans.body.globalStart + spans.body.length)
        let quote = try copiedQuote(canvas, pasteboard)
        XCTAssertEqual(quote.text, "Quoted words")
        XCTAssertTrue(quote.author.isEmpty)
        XCTAssertEqual(pasteboard.string, "Quoted words")
    }

    func test_partialBodySelection_doesNotCopyUnselectedAuthor() throws {
        let (canvas, pasteboard) = quoteCanvas()
        let spans = try regions(canvas)
        canvas.selectedGlobalRange = (spans.body.globalStart + 7, spans.body.globalStart + 10)
        let quote = try copiedQuote(canvas, pasteboard)
        XCTAssertEqual(quote.text, "wor")
        XCTAssertTrue(quote.author.isEmpty)
        XCTAssertTrue(quote.runs.allSatisfy { $0.attributes.bold })
    }

    func test_bodyThroughPartialAuthor_copiesOnlySelectedAuthorRuns() throws {
        let (canvas, pasteboard) = quoteCanvas()
        let spans = try regions(canvas)
        canvas.selectedGlobalRange = (spans.body.globalStart + 7, spans.author.globalStart + 7)
        let quote = try copiedQuote(canvas, pasteboard)
        XCTAssertEqual(quote.text, "words")
        XCTAssertEqual(quote.author.map(\.text).joined(), "Ada Lov")
        XCTAssertEqual(quote.author.filter { $0.attributes.underline }.map(\.text).joined(), "Lov")
        XCTAssertEqual(pasteboard.string, "words\nAda Lov")
    }

    func test_selectionEndingAtAuthorStart_doesNotIncludeAuthor() throws {
        let (canvas, pasteboard) = quoteCanvas()
        let spans = try regions(canvas)
        canvas.selectedGlobalRange = (spans.body.globalStart, spans.author.globalStart)
        let quote = try copiedQuote(canvas, pasteboard)
        XCTAssertEqual(quote.text, "Quoted words")
        XCTAssertTrue(quote.author.isEmpty)
    }

    func test_authorOnlyCopy_remainsPlainTextAndClearsStaleRichFragment() throws {
        for range in [0..<12, 4..<7] {
            let (source, pasteboard) = quoteCanvas()
            source.selectAllText()
            source.copy(nil)
            XCTAssertNotNil(pasteboard.richFragment)
            let spans = try regions(source)
            source.selectedGlobalRange = (spans.author.globalStart + range.lowerBound, spans.author.globalStart + range.upperBound)
            let expected = ("Ada Lovelace" as NSString).substring(with: NSRange(location: range.lowerBound, length: range.count))
            source.copy(nil)
            XCTAssertEqual(pasteboard.string, expected)
            XCTAssertNil(pasteboard.richFragment)
            let destination = canvas([.paragraph(ParagraphBlock(id: BlockID("p")))], pasteboard: pasteboard)
            destination.setCaret(global: destination.boxes[0].textStart)
            destination.paste(nil)
            XCTAssertEqual(destination.currentParagraphs().map(\.text), [expected])
        }
    }

    func test_authorOnlyCutAndPaste_restoresAuthorWithoutChangingBody() throws {
        let (canvas, pasteboard) = quoteCanvas()
        let spans = try regions(canvas)
        canvas.selectedGlobalRange = (spans.author.globalStart, spans.author.globalStart + spans.author.length)
        canvas.cut(nil)
        XCTAssertEqual(pasteboard.string, "Ada Lovelace")
        XCTAssertNil(pasteboard.richFragment)
        let quote = try XCTUnwrap(canvas.boxes.first as? PullQuoteBox)
        XCTAssertEqual(quote.authorLength, 0)
        XCTAssertEqual(quote.textLayout.attributedString.string, "Quoted words")
        canvas.setCaret(global: quote.authorRegionStart)
        canvas.paste(nil)
        XCTAssertEqual(quote.authorLayout.attributedString.string, "Ada Lovelace")
        XCTAssertEqual(quote.textLayout.attributedString.string, "Quoted words")
    }

    func test_authoredQuoteWithEmptyBody_selectAllPreservesQuote() throws {
        let pasteboard = FakePasteboard()
        let canvas = canvas([.pullQuote(PullQuote(id: BlockID("q"), runs: [], author: [TextRun(text: "Ada")]))], pasteboard: pasteboard)
        canvas.selectAllText()
        let quote = try copiedQuote(canvas, pasteboard)
        XCTAssertTrue(quote.runs.isEmpty)
        XCTAssertEqual(quote.author.map(\.text).joined(), "Ada")
    }

    func test_quoteWithEmptyAuthor_copiesWithoutAddingAuthor() throws {
        let pasteboard = FakePasteboard()
        let canvas = canvas([.pullQuote(PullQuote(id: BlockID("q"), runs: [TextRun(text: "Quote")]))], pasteboard: pasteboard)
        canvas.selectAllText()
        let quote = try copiedQuote(canvas, pasteboard)
        XCTAssertEqual(quote.text, "Quote")
        XCTAssertTrue(quote.author.isEmpty)
    }

    func test_nestedPullQuote_selectionUsesItsLeafSpans() throws {
        let (original, pasteboard) = quoteCanvas()
        let source = canvas([
            .paragraph(ParagraphBlock(id: BlockID("before"), runs: [TextRun(text: "Before") ])),
            .blockQuote(BlockQuote(id: BlockID("outer"), children: original.currentBlocks(), collapsed: false)),
            .paragraph(ParagraphBlock(id: BlockID("after"), runs: [TextRun(text: "After") ])),
        ], pasteboard: pasteboard)
        let spans = try regions(source)
        source.selectedGlobalRange = (spans.body.globalStart, spans.author.globalStart + spans.author.length)
        source.copy(nil)
        let data = try XCTUnwrap(pasteboard.richFragment)
        let document = try DocumentCodec.decode(data)
        XCTAssertEqual(document.blocks.count, 1)
        guard case let .blockQuote(outer) = document.blocks.first,
              case let .pullQuote(quote) = outer.children.first else { return XCTFail("Expected nested pull quote") }
        XCTAssertEqual(quote.text, "Quoted words")
        XCTAssertEqual(quote.author.map(\.text).joined(), "Ada Lovelace")
    }

    func test_authorThroughFollowingParagraph_copiesSelectedAuthorAsText() throws {
        let (original, pasteboard) = quoteCanvas()
        let source = canvas(original.currentBlocks() + [
            .paragraph(ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: "After")]))
        ], pasteboard: pasteboard)
        let spans = try regions(source)
        source.selectedGlobalRange = (spans.author.globalStart + 4, source.boxes[1].textStart + 2)
        source.copy(nil)
        let data = try XCTUnwrap(pasteboard.richFragment)
        let document = try DocumentCodec.decode(data)
        let paragraphs = document.blocks.compactMap { if case let .paragraph(p) = $0 { return p }; return nil }
        XCTAssertEqual(paragraphs.map(\.text), ["Lovelace", "Af"])
        XCTAssertEqual(paragraphs.first?.runs.filter { $0.attributes.underline }.map(\.text).joined(), "Lovelace")
        let destination = canvas([.paragraph(ParagraphBlock(id: BlockID("destination")))], pasteboard: pasteboard)
        destination.setCaret(global: destination.boxes[0].textStart)
        destination.paste(nil)
        XCTAssertEqual(destination.currentParagraphs().map(\.text), ["Lovelace", "Af"])
    }

    func test_emptyQuoteSelection_doesNotCreateRichContent() {
        let pasteboard = FakePasteboard()
        let canvas = canvas([.pullQuote(PullQuote(id: BlockID("q"), runs: []))], pasteboard: pasteboard)
        canvas.selectAllText()
        canvas.copy(nil)
        XCTAssertNil(pasteboard.richFragment)
    }

    func test_authorSliceUsesUTF16Offsets() throws {
        let pasteboard = FakePasteboard()
        let canvas = canvas([.pullQuote(PullQuote(id: BlockID("q"), runs: [TextRun(text: "Q\u{1D11E}")],
                                                 author: [TextRun(text: "A\u{1D11E}B")]))], pasteboard: pasteboard)
        let spans = try regions(canvas)
        canvas.selectedGlobalRange = (spans.body.globalStart, spans.author.globalStart + 3)
        let quote = try copiedQuote(canvas, pasteboard)
        XCTAssertEqual(quote.text, "Q\u{1D11E}")
        XCTAssertEqual(quote.author.map(\.text).joined(), "A\u{1D11E}")
    }
}
#endif
