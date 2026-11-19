#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasTablePlainClipboardTests: XCTestCase {
    private final class FakePasteboard: TextPasteboard {
        var string: String? { didSet { richFragment = nil } }
        var richFragment: Data?
        var hasStrings: Bool { !(string ?? "").isEmpty }
    }

    private func paragraph(_ id: String, _ text: String) -> Block {
        .paragraph(ParagraphBlock(id: BlockID(id), runs: [TextRun(text: text)]))
    }

    private func table(_ contents: [[[String]]] = [[["111"], ["333"]], [["222"], ["444"]]]) -> Block {
        .table(TableBlock(id: BlockID("table"), columns: (0..<(contents.first?.count ?? 0)).map { _ in ColumnSpec(width: 120) },
                          rows: contents.enumerated().map { row, cells in
            Row(id: BlockID("r\(row)"), cells: cells.enumerated().map { column, texts in
                let id = "r\(row)c\(column)"
                return Cell(id: BlockID(id), blocks: texts.enumerated().map { paragraph(id + "p\($0.offset)", $0.element) })
            })
        }))
    }

    private func canvas(_ blocks: [Block]) -> (DocumentCanvasView, FakePasteboard) {
        let canvas = DocumentCanvasView()
        let pasteboard = FakePasteboard()
        canvas.pasteboard = pasteboard
        canvas.setBlocks(blocks, width: 400)
        return (canvas, pasteboard)
    }

    private func region(_ canvas: DocumentCanvasView, _ id: String) throws -> LeafTextRegion {
        try XCTUnwrap(canvas.allLeafRegions().first { $0.ref == .paragraph(BlockID(id)) })
    }

    func testSelectedTableUsesTabsAndNewlinesInEitherDirection() throws {
        let (canvas, pasteboard) = canvas([table()])
        let first = try region(canvas, "r0c0p0"), last = try region(canvas, "r1c1p0")
        let before = canvas.currentBlocks()
        for range in [(first.globalStart, last.globalStart + last.length),
                      (last.globalStart + last.length, first.globalStart)] {
            canvas.selectedGlobalRange = range
            canvas.copy(nil)
            XCTAssertEqual(pasteboard.string, "111\t333\n222\t444")
            XCTAssertEqual(canvas.text(inGlobalRange: range.0, range.1), "111333222444")
            XCTAssertEqual(canvas.currentBlocks(), before)
            XCTAssertEqual(canvas.selectedGlobalRange.0, range.0)
            XCTAssertEqual(canvas.selectedGlobalRange.1, range.1)
            let document = try DocumentCodec.decode(XCTUnwrap(pasteboard.richFragment))
            XCTAssertEqual(document.blocks, before)
        }
    }

    func testPartialSelectionDoesNotCopyUnselectedCellEdges() throws {
        let (canvas, pasteboard) = canvas([table()])
        let first = try region(canvas, "r0c0p0"), last = try region(canvas, "r1c1p0")
        canvas.selectedGlobalRange = (first.globalStart + 1, last.globalStart + 2)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "11\t333\n222\t44")
        let document = try DocumentCodec.decode(XCTUnwrap(pasteboard.richFragment))
        XCTAssertEqual(document.blocks, canvas.currentBlocks())
    }

    func testPartialRowAndRowBoundaryHaveOnlySelectedCells() throws {
        let (canvas, pasteboard) = canvas([table()])
        let a = try region(canvas, "r0c0p0"), b = try region(canvas, "r0c1p0"), c = try region(canvas, "r1c0p0")
        canvas.selectedGlobalRange = (a.globalStart + 1, b.globalStart + 2)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "11\t33")
        canvas.selectedGlobalRange = (b.globalStart + 1, c.globalStart + 2)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "33\n22")
    }

    func testNonemptyCellEndpointAddsNoUnselectedSeparator() throws {
        let (canvas, pasteboard) = canvas([table()])
        let a = try region(canvas, "r0c0p0"), b = try region(canvas, "r0c1p0")
        canvas.selectedGlobalRange = (a.globalStart, b.globalStart)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "111")
        canvas.selectedGlobalRange = (a.globalStart + a.length, b.globalStart + b.length)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "333")
    }

    func testWithinCellSelectionKeepsUTF16OffsetsAndRawWhitespace() throws {
        let (canvas, pasteboard) = canvas([table([[["A𝄞B\r\nC\tD"], ["other"]]])])
        let cell = try region(canvas, "r0c0p0")
        canvas.selectedGlobalRange = (cell.globalStart + 1, cell.globalStart + cell.length - 1)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "𝄞B\r\nC\t")
    }

    func testEmptyCellsAndEmptyRowsRetainTheirBoundaries() {
        let (canvas, pasteboard) = canvas([table([
            [[""], ["A"], []],
            [[], [""], []],
            [["B"], [], [""]]
        ])])
        canvas.selectAllText()
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "\tA\t\n\t\t\nB\t\t")
    }

    func testSelectionBetweenEmptyCellsKeepsEmptyColumns() throws {
        let (canvas, pasteboard) = canvas([table([[[""], ["A"], [""]]])])
        let a = try region(canvas, "r0c0p0"), c = try region(canvas, "r0c2p0")
        canvas.selectedGlobalRange = (a.globalStart, c.globalStart)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "\tA\t")
    }

    func testMultipleParagraphsAndBlankLinesStayInsideCell() throws {
        let (canvas, pasteboard) = canvas([table([[["first", "", "last"], ["right"]]])])
        canvas.selectAllText()
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "first\n\nlast\tright")
        let first = try region(canvas, "r0c0p0"), last = try region(canvas, "r0c0p2")
        canvas.selectedGlobalRange = (first.globalStart + 2, last.globalStart + 2)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "rst\n\nla")
    }

    func testNestedTableUsesItsLeafSpans() throws {
        let (canvas, pasteboard) = canvas([
            paragraph("before", "before"),
            .blockQuote(BlockQuote(id: BlockID("outer"), children: [table()], collapsed: false)),
            paragraph("after", "after")
        ])
        let first = try region(canvas, "r0c0p0"), last = try region(canvas, "r1c1p0")
        canvas.selectedGlobalRange = (first.globalStart + 1, last.globalStart + 2)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "11\t333\n222\t44")
        let document = try DocumentCodec.decode(XCTUnwrap(pasteboard.richFragment))
        guard case let .blockQuote(outer) = document.blocks.first,
              case let .table(copied) = outer.children.first else { return XCTFail("Expected nested table") }
        XCTAssertEqual(copied.rowCount, 2)
        XCTAssertEqual(copied.columnCount, 2)
    }

    func testStructuralRowsAndColumnsKeepOnlySelectedCoordinates() throws {
        let (canvas, pasteboard) = canvas([table()])
        let first = try region(canvas, "r0c0p0")
        canvas.setCaret(global: first.globalStart)
        canvas.selectTableRow(1)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "222\t444")
        canvas.selectTableColumn(1)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "333\n444")
        canvas.selectTableRows(0...1)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "111\t333\n222\t444")
        canvas.selectTableColumns(0...1)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "111\t333\n222\t444")
    }

    func testStructuralSelectionPreservesMultipleParagraphsAndEmptyCells() throws {
        let (canvas, pasteboard) = canvas([table([[["first", "", "last"], [""]], [["next"], ["right"]]])])
        let first = try region(canvas, "r0c0p0")
        canvas.setCaret(global: first.globalStart)
        canvas.selectTableRow(0)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "first\n\nlast\t")
        canvas.selectTableColumn(0)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "first\n\nlast\nnext")
    }

    func testAllEmptyTextSelectionStillCopiesGrid() {
        let (canvas, pasteboard) = canvas([table([[[""], [""]], [[""], [""]]])])
        canvas.selectAllText()
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "\t\n\t")
    }

    func testTableBetweenParagraphsDoesNotChangeTheirSerialization() {
        let (canvas, pasteboard) = canvas([paragraph("before", "before"), table(), paragraph("after", "after")])
        canvas.selectAllText()
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "before111\t333\n222\t444after")
    }

    func testAllEmptyStructuralSelectionStillCopiesGrid() throws {
        let (canvas, pasteboard) = canvas([table([[[""], [""]], [[""], [""]]])])
        let first = try region(canvas, "r0c0p0")
        canvas.setCaret(global: first.globalStart)
        canvas.selectTableRows(0...1)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "\t\n\t")
    }

    func testInlineFormattingSurvivesRichCopy() throws {
        let (canvas, pasteboard) = canvas([.table(TableBlock(id: BlockID("t"), columns: [ColumnSpec(width: 120)], rows: [
            Row(id: BlockID("r"), cells: [Cell(id: BlockID("c"), blocks: [
                .paragraph(ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: "a"), TextRun(text: "BC", attributes: CharacterAttributes(underline: true))]))
            ])])
        ]))])
        let region = try region(canvas, "p")
        canvas.selectedGlobalRange = (region.globalStart + 1, region.globalStart + 2)
        let before = canvas.currentBlocks()
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "B")
        let document = try DocumentCodec.decode(XCTUnwrap(pasteboard.richFragment))
        XCTAssertEqual(document.blocks, before)
        guard case let .table(table) = document.blocks.first,
              case let .paragraph(paragraph) = table.rows[0].cells[0].blocks.first else { return XCTFail("Expected table paragraph") }
        XCTAssertEqual(paragraph.runs.filter { $0.attributes.underline }.map(\.text).joined(), "BC")
    }

    func testOrdinaryParagraphsAndAuthorOnlyCopyRemainUnchanged() throws {
        let (canvas, pasteboard) = canvas([paragraph("a", "one\r\ntwo"), paragraph("b", "three")])
        canvas.selectAllText()
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "one\r\ntwothree")
        XCTAssertEqual(canvas.text(inGlobalRange: canvas.selFrom, canvas.selTo), pasteboard.string)
        canvas.setBlocks([.pullQuote(PullQuote(id: BlockID("q"), runs: [TextRun(text: "Quote")], author: [TextRun(text: "Ada")]))], width: 400)
        let author = try XCTUnwrap(canvas.allLeafRegions().first { $0.ref == .quoteAuthor(BlockID("q")) })
        canvas.selectedGlobalRange = (author.globalStart, author.globalStart + author.length)
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "Ada")
        XCTAssertNil(pasteboard.richFragment)
    }

    func testTableAndPullQuoteBoundariesCoexistInExpandedQuote() {
        let quote = Block.pullQuote(PullQuote(id: BlockID("q"), runs: [TextRun(text: "Quote")], author: [TextRun(text: "Ada")]))
        let (canvas, pasteboard) = canvas([
            .blockQuote(BlockQuote(id: BlockID("outer"), children: [quote, table()], collapsed: false)),
            .pullQuote(PullQuote(id: BlockID("after"), runs: [TextRun(text: "Other")], author: [TextRun(text: "Grace")]))
        ])
        let before = canvas.currentBlocks()
        canvas.selectAllText()
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "Quote\nAda111\t333\n222\t444Other\nGrace")
        XCTAssertEqual(canvas.currentBlocks(), before)
    }

    func testPartialSelectionAcrossTableAndPullQuotePreservesBothBoundaries() throws {
        let (canvas, pasteboard) = canvas([
            table(),
            .pullQuote(PullQuote(id: BlockID("q"), runs: [TextRun(text: "Quote")], author: [TextRun(text: "Ada")]))
        ])
        let cell = try region(canvas, "r1c0p0")
        let author = try XCTUnwrap(canvas.allLeafRegions().first { $0.ref == .quoteAuthor(BlockID("q")) })
        for range in [(cell.globalStart + 1, author.globalStart + 2), (author.globalStart + 2, cell.globalStart + 1)] {
            canvas.selectedGlobalRange = range
            canvas.copy(nil)
            XCTAssertEqual(pasteboard.string, "22\t444Quote\nAd")
        }
    }

    func testCollapsedSelectionDoesNotWritePasteboard() throws {
        let (canvas, pasteboard) = canvas([table()])
        let first = try region(canvas, "r0c0p0")
        canvas.setCaret(global: first.globalStart)
        pasteboard.string = "keep"
        canvas.copy(nil)
        XCTAssertEqual(pasteboard.string, "keep")
    }
}
#endif
