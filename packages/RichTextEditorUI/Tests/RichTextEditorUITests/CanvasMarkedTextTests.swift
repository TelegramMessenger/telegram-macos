#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasMarkedTextTests: AppKitTestCase {
    private let unspecifiedRange = NSRange(location: NSNotFound, length: 0)

    private func canvas(_ text: String = "") -> DocumentCanvasView {
        let view = DocumentCanvasView()
        view.setParagraphs([ParagraphBlock(id: BlockID("body"), runs: [TextRun(text: text)])], width: 400)
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        view.layoutSubtreeIfNeeded()
        view.moveCaretToEnd()
        return view
    }

    private func text(_ view: DocumentCanvasView) -> String {
        view.text(inGlobalRange: 0, view.documentSizeValue)
    }

    private func mark(_ string: String, in view: DocumentCanvasView, selection: NSRange? = nil, replacement: NSRange? = nil) {
        view.setMarkedText(string, selectedRange: selection ?? NSRange(location: (string as NSString).length, length: 0), replacementRange: replacement ?? unspecifiedRange)
    }

    func testDeadKeyCommitReplacesAccent() {
        for (accent, letter) in [("˜", "ñ"), ("¨", "ö"), ("´", "é"), ("ˆ", "ê"), ("`", "è")] {
            let view = canvas()
            let start = view.head
            mark(accent, in: view)
            XCTAssertEqual(text(view), accent)
            XCTAssertTrue(view.hasMarkedText())
            XCTAssertEqual(view.markedRange(), NSRange(location: start, length: 1))
            view.insertText(letter, replacementRange: unspecifiedRange)
            XCTAssertEqual(text(view), letter)
            XCTAssertEqual(view.selectedRange(), NSRange(location: start + 1, length: 0))
            XCTAssertFalse(view.hasMarkedText())
            XCTAssertEqual(view.markedRange(), unspecifiedRange)
        }
    }

    func testMarkedUpdatesReplaceTheWholeComposition() {
        let view = canvas("before after")
        let start = view.firstRenderableGlobal() + 7
        view.setCaret(global: start)
        mark("n", in: view)
        mark("ni", in: view, selection: NSRange(location: 1, length: 1))
        XCTAssertEqual(text(view), "before niafter")
        XCTAssertEqual(view.selectedRange(), NSRange(location: start + 1, length: 1))
        mark("你", in: view)
        XCTAssertEqual(text(view), "before 你after")
        view.insertText("你好", replacementRange: unspecifiedRange)
        XCTAssertEqual(text(view), "before 你好after")
        XCTAssertFalse(view.hasMarkedText())
    }

    func testDeleteCommandEndsComposition() throws {
        let view = canvas("prefix")
        let window = hostInWindow(view)
        defer { window.orderOut(nil) }
        mark("˜", in: view)
        let delete = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "\u{7f}", charactersIgnoringModifiers: "\u{7f}", isARepeat: false, keyCode: 51))
        view.keyDown(with: delete)
        XCTAssertEqual(text(view), "prefix")
        XCTAssertFalse(view.hasMarkedText())
    }

    func testCompositionReplacesSelectedTextAndPreservesSuffix() {
        let view = canvas("hello world")
        let start = view.firstRenderableGlobal()
        view.selectedGlobalRange = (start + 4, start + 1)
        mark("¨", in: view)
        XCTAssertEqual(text(view), "h¨o world")
        view.insertText("ö", replacementRange: unspecifiedRange)
        XCTAssertEqual(text(view), "höo world")
        XCTAssertEqual(view.head, start + 2)
    }

    func testExplicitReplacementRangeTakesPriority() {
        let view = canvas("teh word")
        let start = view.firstRenderableGlobal()
        view.insertText("the", replacementRange: NSRange(location: start, length: 3))
        XCTAssertEqual(text(view), "the word")
        view.moveCaretToEnd()
        mark("¨", in: view, replacement: NSRange(location: start + 5, length: 1))
        XCTAssertEqual(text(view), "the w¨rd")
        view.insertText("ö", replacementRange: view.markedRange())
        XCTAssertEqual(text(view), "the wörd")
    }

    func testEmptyMarkedTextCancelsWithoutDeletingNeighbors() {
        let view = canvas("ab")
        let start = view.firstRenderableGlobal() + 1
        view.setCaret(global: start)
        mark("˜", in: view)
        mark("", in: view)
        XCTAssertEqual(text(view), "ab")
        XCTAssertEqual(view.head, start)
        XCTAssertFalse(view.hasMarkedText())
        view.insertText("x", replacementRange: unspecifiedRange)
        XCTAssertEqual(text(view), "axb")
    }

    func testEmptyCommitRemovesMarkedText() {
        let view = canvas("prefix")
        mark("¨", in: view)
        view.insertText("", replacementRange: unspecifiedRange)
        XCTAssertEqual(text(view), "prefix")
        XCTAssertFalse(view.hasMarkedText())
    }

    func testUnmarkKeepsTextAndEndsReplacement() {
        let view = canvas()
        mark("˜", in: view)
        view.unmarkText()
        XCTAssertEqual(text(view), "˜")
        XCTAssertFalse(view.hasMarkedText())
        view.insertText("n", replacementRange: unspecifiedRange)
        XCTAssertEqual(text(view), "˜n")
    }

    func testUTF16MarkedRangeAndRelativeSelection() {
        let view = canvas("😀")
        let start = view.head
        view.setMarkedText(NSAttributedString(string: "😀ab"), selectedRange: NSRange(location: 2, length: 1), replacementRange: unspecifiedRange)
        XCTAssertEqual(view.markedRange(), NSRange(location: start, length: 4))
        XCTAssertEqual(view.selectedRange(), NSRange(location: start + 2, length: 1))
        view.insertText(NSAttributedString(string: "ö"), replacementRange: unspecifiedRange)
        XCTAssertEqual(text(view), "😀ö")
        XCTAssertEqual(view.head, start + 1)
    }

    func testMarkedSelectionIsClampedToComposition() {
        let view = canvas()
        mark("ni", in: view, selection: NSRange(location: 20, length: Int.max))
        XCTAssertEqual(view.selectedRange(), NSRange(location: NSMaxRange(view.markedRange()), length: 0))
        mark("ni", in: view, selection: NSRange(location: 0, length: Int.max))
        XCTAssertEqual(view.selectedRange(), view.markedRange())
    }

    func testUndoRedoDoesNotRestoreIntermediateAccents() {
        let view = canvas("prefix ")
        let manager = UndoManager()
        manager.groupsByEvent = false
        view.undoManagerOverride = manager
        manager.beginUndoGrouping()
        mark("˜", in: view)
        manager.endUndoGrouping()
        mark("n", in: view)
        view.insertText("ñ", replacementRange: unspecifiedRange)
        XCTAssertEqual(text(view), "prefix ñ")
        manager.undo()
        XCTAssertEqual(text(view), "prefix ")
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertFalse(manager.canUndo)
        manager.redo()
        XCTAssertEqual(text(view), "prefix ñ")
        XCTAssertFalse(view.hasMarkedText())
    }

    func testUndoDuringCompositionClearsMarkedState() {
        let view = canvas()
        let manager = UndoManager()
        manager.groupsByEvent = false
        view.undoManagerOverride = manager
        manager.beginUndoGrouping()
        mark("¨", in: view)
        manager.endUndoGrouping()
        manager.undo()
        XCTAssertEqual(text(view), "")
        XCTAssertFalse(view.hasMarkedText())
        manager.beginUndoGrouping()
        view.insertText("a", replacementRange: unspecifiedRange)
        manager.endUndoGrouping()
        XCTAssertEqual(text(view), "a")
    }

    func testCaretMoveAndDocumentReplacementEndComposition() {
        let view = canvas("ab")
        mark("˜", in: view)
        view.setCaret(global: view.firstRenderableGlobal())
        XCTAssertFalse(view.hasMarkedText())
        view.insertText("x", replacementRange: unspecifiedRange)
        XCTAssertEqual(text(view), "xab˜")
        mark("¨", in: view)
        view.setParagraphs([ParagraphBlock(id: BlockID("replacement"), runs: [TextRun(text: "new")])], width: 400)
        view.moveCaretToEnd()
        XCTAssertFalse(view.hasMarkedText())
        view.insertText("!", replacementRange: unspecifiedRange)
        XCTAssertEqual(text(view), "new!")
    }

    func testLosingFocusEndsComposition() {
        let view = canvas()
        let window = hostInWindow(view)
        defer { window.orderOut(nil) }
        mark("¨", in: view)
        XCTAssertTrue(window.makeFirstResponder(nil))
        XCTAssertFalse(view.hasMarkedText())
        XCTAssertEqual(text(view), "¨")
    }

    func testCompositionPreservesPendingFormatting() {
        let view = canvas()
        view.toggleBold()
        mark("˜", in: view)
        mark("n", in: view)
        view.insertText("ñ", replacementRange: unspecifiedRange)
        let paragraph = (view.boxes[0] as! BlockBox).currentParagraph()
        XCTAssertEqual(paragraph.runs.map(\.text).joined(), "ñ")
        XCTAssertTrue(paragraph.runs.allSatisfy { $0.attributes.bold })
    }

    func testCompositionAfterFormattedTextKeepsAttributes() {
        let view = canvas()
        view.setParagraphs([ParagraphBlock(id: BlockID("bold"), runs: [TextRun(text: "bold ", attributes: CharacterAttributes(bold: true))])], width: 400)
        view.moveCaretToEnd()
        mark("¨", in: view)
        view.insertText("ö", replacementRange: unspecifiedRange)
        let paragraph = (view.boxes[0] as! BlockBox).currentParagraph()
        XCTAssertEqual(paragraph.runs.map(\.text).joined(), "bold ö")
        XCTAssertTrue(paragraph.runs.allSatisfy { $0.attributes.bold })
    }

    func testCompositionInsertsAtMediaGap() {
        let view = canvas()
        view.insertImage(NSImage(size: NSSize(width: 100, height: 100)), naturalSize: NSSize(width: 100, height: 100), assetID: "image")
        let image = view.boxes.first { $0 is MediaBlockBox }!
        view.setCaret(global: image.nodeStart)
        mark("˜", in: view)
        let range = view.markedRange()
        XCTAssertEqual(view.text(inGlobalRange: range.location, NSMaxRange(range)), "˜")
        view.insertText("ñ", replacementRange: unspecifiedRange)
        XCTAssertEqual(text(view), "ñ")
        XCTAssertNotNil(view.boxes.first { $0 is MediaBlockBox })
    }

    func testCompositionInsideTableCellKeepsOtherCell() {
        let view = canvas()
        view.setBlocks([.table(TableBlock(id: BlockID("table"), columns: [ColumnSpec(width: 120), ColumnSpec(width: 120)], rows: [Row(id: BlockID("row"), cells: [
            Cell(id: BlockID("left"), blocks: [.paragraph(ParagraphBlock(id: BlockID("left-text"), runs: [TextRun(text: "ab")]))]),
            Cell(id: BlockID("right"), blocks: [.paragraph(ParagraphBlock(id: BlockID("right-text"), runs: [TextRun(text: "keep")]))])
        ])]))], width: 400)
        let region = view.allLeafRegions().first { $0.ref == .paragraph(BlockID("left-text")) }!
        view.setCaret(global: region.globalStart + 1)
        mark("¨", in: view)
        view.insertText("ö", replacementRange: unspecifiedRange)
        XCTAssertEqual(view.allLeafRegions().first { $0.ref == .paragraph(BlockID("left-text")) }?.layout.attributedString.string, "aöb")
        XCTAssertEqual(view.allLeafRegions().first { $0.ref == .paragraph(BlockID("right-text")) }?.layout.attributedString.string, "keep")
    }
}
#endif
