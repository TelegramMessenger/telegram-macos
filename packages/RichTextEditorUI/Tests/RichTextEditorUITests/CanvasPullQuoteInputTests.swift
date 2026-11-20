#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasPullQuoteInputTests: AppKitTestCase {
    private func canvas(body: String = "Quote", author: String = "") -> (DocumentCanvasView, PullQuoteBox) {
        let canvas = DocumentCanvasView()
        canvas.setBlocks([.pullQuote(PullQuote(id: BlockID("q"), runs: [TextRun(text: body)],
                                              author: author.isEmpty ? [] : [TextRun(text: author)]))], width: 400)
        canvas.frame = CGRect(x: 0, y: 0, width: 400, height: 600)
        canvas.layoutSubtreeIfNeeded()
        return (canvas, canvas.boxes[0] as! PullQuoteBox)
    }

    private func pressReturn(_ canvas: DocumentCanvasView, keyCode: UInt16 = 36, shift: Bool = false) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [],
                                    timestamp: 0, windowNumber: 0, context: nil, characters: "\r",
                                    charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: keyCode)!
        canvas.keyDown(with: event)
    }

    func test_emptyAuthorCaret_isCenteredAtPlaceholder() {
        let (canvas, quote) = canvas()
        canvas.setCaret(global: quote.authorRegionStart)
        let caret = canvas.caretRect(forGlobal: canvas.head)
        XCTAssertEqual(caret.minX, quote.frame.midX, accuracy: 0.5)
        XCTAssertEqual(caret.minY, quote.authorOrigin.y, accuracy: 0.5)
        XCTAssertGreaterThan(caret.height, 0)
        XCTAssertNil(canvas.activeStack(at: canvas.head))
    }

    func test_nonemptyAuthorCaret_keepsTextKitPosition() {
        let (canvas, quote) = canvas(author: "Ada")
        canvas.setCaret(global: quote.authorRegionStart + 1)
        let expected = quote.authorLayout.caretRect(atOffset: 1).offsetBy(dx: quote.authorOrigin.x, dy: quote.authorOrigin.y)
        XCTAssertEqual(canvas.caretRect(forGlobal: canvas.head), expected)
    }

    func test_rawReturnInQuoteBody_insertsNewlineAndKeepsAuthor() {
        for keyCode: UInt16 in [36, 76] {
            for (offset, expected) in [(0, "\nQuote"), (2, "Qu\note"), (5, "Quote\n")] {
                let (canvas, quote) = canvas(author: "Ada")
                canvas.setCaret(global: quote.textStart + offset)
                pressReturn(canvas, keyCode: keyCode)
                XCTAssertEqual(quote.layout.attributedString.string, expected)
                XCTAssertEqual(quote.authorLayout.attributedString.string, "Ada")
                XCTAssertEqual(canvas.head, quote.textStart + offset + 1)
                XCTAssertEqual(canvas.boxes.count, 1)
            }
        }
    }

    func test_selectorReturnInQuoteBody_insertsNewlineAndKeepsAuthor() {
        let (canvas, quote) = canvas(author: "Ada")
        canvas.setCaret(global: quote.textStart + 2)
        canvas.insertNewline(nil)
        XCTAssertEqual(quote.layout.attributedString.string, "Qu\note")
        XCTAssertEqual(quote.authorLayout.attributedString.string, "Ada")
        XCTAssertEqual(canvas.head, quote.textStart + 3)
        XCTAssertEqual(canvas.boxes.count, 1)
    }

    func test_rawReturnAtQuoteEnd_movesCaretToNextLine() {
        let (canvas, quote) = canvas(author: "Ada")
        canvas.setCaret(global: quote.textStart + quote.textLength)
        let before = canvas.caretRect(forGlobal: canvas.head)
        pressReturn(canvas)
        canvas.layoutSubtreeIfNeeded()
        XCTAssertEqual(quote.layout.attributedString.string, "Quote\n")
        let after = canvas.caretRect(forGlobal: canvas.head)
        XCTAssertGreaterThan(after.minY, before.minY + 1)
        XCTAssertLessThan(after.minY, quote.authorOrigin.y)
        XCTAssertEqual(after.minX, quote.frame.midX, accuracy: 0.5)
    }

    func test_selectorReturnReplacingBodySelection_insertsNewline() {
        let (canvas, quote) = canvas(author: "Ada")
        canvas.selectedGlobalRange = (quote.textStart + 1, quote.textStart + 4)
        canvas.insertNewline(nil)
        XCTAssertEqual(quote.layout.attributedString.string, "Q\ne")
        XCTAssertEqual(quote.authorLayout.attributedString.string, "Ada")
        XCTAssertEqual(canvas.head, quote.textStart + 2)
    }

    func test_hostCanConsumeSelectorReturn_withoutEditingQuote() {
        let (canvas, quote) = canvas(author: "Ada")
        canvas.setCaret(global: quote.textStart + 2)
        var invocations = 0
        canvas.onReturnKey = { invocations += 1; return true }
        canvas.insertNewline(nil)
        XCTAssertEqual(invocations, 1)
        XCTAssertEqual(quote.layout.attributedString.string, "Quote")
        XCTAssertEqual(canvas.head, quote.textStart + 2)
    }

    func test_emptyAuthorCaret_staysCenteredAfterResizeAndRetyping() {
        let (canvas, quote) = canvas(author: "Ada")
        canvas.selectedGlobalRange = (quote.authorRegionStart, quote.authorRegionStart + quote.authorLength)
        canvas.commitText("")
        for width: CGFloat in [280, 700] {
            canvas.frame.size.width = width
            canvas.setParagraphsWidthIfNeeded(width)
            canvas.layoutSubtreeIfNeeded()
            XCTAssertEqual(canvas.caretRect(forGlobal: canvas.head).minX, quote.frame.midX, accuracy: 0.5)
        }
        canvas.commitText("A")
        XCTAssertEqual(quote.authorLayout.attributedString.string, "A")
        XCTAssertEqual(quote.layout.attributedString.string, "Quote")
        XCTAssertEqual(canvas.head, quote.authorRegionStart + 1)
    }

    func test_nestedEmptyAuthorCaret_usesItsOwnCenteredLeaf() throws {
        let (canvas, original) = canvas()
        canvas.setBlocks([.blockQuote(BlockQuote(id: BlockID("outer"), children: [original.currentBlock()], collapsed: false))], width: 400)
        canvas.layoutSubtreeIfNeeded()
        let container = try XCTUnwrap(canvas.boxes.first as? BlockQuoteBox)
        let quote = try XCTUnwrap(container.children.boxes.first as? PullQuoteBox)
        canvas.setCaret(global: quote.authorRegionStart)
        XCTAssertEqual(canvas.caretRect(forGlobal: canvas.head).minX, quote.frame.midX, accuracy: 0.5)
        XCTAssertNil(canvas.activeStack(at: canvas.head))
    }

    func test_selectorReturnAtQuoteEnd_matchesRawReturnAndUndoes() {
        for viaSelector in [false, true] {
            let (canvas, quote) = canvas(author: "Ada")
            canvas.setCaret(global: quote.textStart + quote.textLength)
            let before = canvas.currentModelBlocks()
            let beforeHead = canvas.head
            let undo = UndoManager(); undo.groupsByEvent = false; canvas.undoManagerOverride = undo
            undo.beginUndoGrouping()
            if viaSelector { canvas.insertNewline(nil) } else { pressReturn(canvas) }
            undo.endUndoGrouping()
            XCTAssertEqual(quote.layout.attributedString.string, "Quote\n")
            XCTAssertEqual(quote.authorLayout.attributedString.string, "Ada")
            XCTAssertEqual(canvas.head, quote.textStart + quote.textLength)
            let after = canvas.currentModelBlocks()
            undo.undo()
            XCTAssertEqual(canvas.currentModelBlocks(), before)
            XCTAssertEqual(canvas.head, beforeHead)
            undo.redo()
            XCTAssertEqual(canvas.currentModelBlocks(), after)
            undo.beginUndoGrouping(); canvas.commitText("Next"); undo.endUndoGrouping()
            XCTAssertEqual(canvas.boxes.first?.textLayout.attributedString.string, "Quote\nNext")
        }
    }

    func test_selectorDoubleReturn_exitsQuoteAndPreservesAuthor() {
        let (canvas, quote) = canvas(author: "Ada")
        canvas.setCaret(global: quote.textStart + quote.textLength)
        canvas.insertNewline(nil)
        canvas.insertNewline(nil)
        XCTAssertEqual(quote.layout.attributedString.string, "Quote")
        XCTAssertEqual(quote.authorLayout.attributedString.string, "Ada")
        XCTAssertEqual(canvas.boxes.count, 2)
        XCTAssertTrue(canvas.boxes.last is BlockBox)
        XCTAssertEqual(canvas.head, canvas.boxes.last?.textStart)
    }

    func test_selectorReturnInEmptyQuote_matchesRawReturn() {
        for viaSelector in [false, true] {
            let (canvas, quote) = canvas(body: "")
            canvas.setCaret(global: quote.textStart)
            if viaSelector { canvas.insertNewline(nil) } else { pressReturn(canvas) }
            XCTAssertEqual(canvas.boxes.count, 1)
            XCTAssertTrue(canvas.boxes.first is BlockBox)
            XCTAssertEqual(canvas.boxes.first?.textLength, 0)
        }
    }

    func test_commandReturnInQuoteBody_routesThroughSelector() {
        let (canvas, quote) = canvas(author: "Ada")
        canvas.setCaret(global: quote.textStart + 2)
        canvas.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        XCTAssertEqual(quote.layout.attributedString.string, "Qu\note")
        XCTAssertEqual(quote.authorLayout.attributedString.string, "Ada")
    }

    func test_selectorReturnInNestedQuoteBody_insertsInsideQuote() throws {
        let (canvas, original) = canvas(author: "Ada")
        canvas.setBlocks([.blockQuote(BlockQuote(id: BlockID("outer"), children: [original.currentBlock()], collapsed: false))], width: 400)
        let container = try XCTUnwrap(canvas.boxes.first as? BlockQuoteBox)
        let quote = try XCTUnwrap(container.children.boxes.first as? PullQuoteBox)
        canvas.setCaret(global: quote.textStart + 2)
        canvas.insertNewline(nil)
        XCTAssertEqual(quote.layout.attributedString.string, "Qu\note")
        XCTAssertEqual(quote.authorLayout.attributedString.string, "Ada")
        XCTAssertEqual(canvas.boxes.count, 1)
        XCTAssertEqual(container.children.boxes.count, 1)
    }

    func test_unconsumedHostReturn_insertsNewlineInQuote() {
        let (canvas, quote) = canvas(author: "Ada")
        canvas.setCaret(global: quote.textStart + 2)
        var invocations = 0
        canvas.onReturnKey = { invocations += 1; return false }
        canvas.insertNewline(nil)
        XCTAssertEqual(invocations, 1)
        XCTAssertEqual(quote.layout.attributedString.string, "Qu\note")
    }

    func test_rawReturnReplacingBodySelection_insertsNewline() {
        for keyCode: UInt16 in [36, 76] {
            let (canvas, quote) = canvas(author: "Ada")
            canvas.selectedGlobalRange = (quote.textStart + 4, quote.textStart + 1)
            pressReturn(canvas, keyCode: keyCode)
            XCTAssertEqual(quote.layout.attributedString.string, "Q\ne")
            XCTAssertEqual(quote.authorLayout.attributedString.string, "Ada")
            XCTAssertEqual(canvas.anchor, quote.textStart + 2)
            XCTAssertEqual(canvas.head, quote.textStart + 2)
        }
    }

    func test_rawDoubleReturn_exitsQuoteAndPreservesAuthor() {
        for keyCode: UInt16 in [36, 76] {
            let (canvas, quote) = canvas(author: "Ada")
            canvas.setCaret(global: quote.textStart + quote.textLength)
            pressReturn(canvas, keyCode: keyCode)
            pressReturn(canvas, keyCode: keyCode)
            XCTAssertEqual(quote.layout.attributedString.string, "Quote")
            XCTAssertEqual(quote.authorLayout.attributedString.string, "Ada")
            XCTAssertEqual(canvas.boxes.count, 2)
            XCTAssertTrue(canvas.boxes.last is BlockBox)
            XCTAssertEqual(canvas.head, canvas.boxes.last?.textStart)
        }
    }

    func test_authorReturn_routingIsUnchanged() {
        for keyCode: UInt16 in [36, 76] {
            let (canvas, quote) = canvas(author: "Ada")
            canvas.setCaret(global: quote.authorRegionStart + 1)
            pressReturn(canvas, keyCode: keyCode)
            XCTAssertEqual(quote.authorLayout.attributedString.string, "A\nda")
            XCTAssertEqual(quote.layout.attributedString.string, "Quote")
        }
        let (canvas, quote) = canvas(author: "Ada")
        canvas.setCaret(global: quote.authorRegionStart + 1)
        canvas.insertNewline(nil)
        XCTAssertEqual(quote.authorLayout.attributedString.string, "Ada")
        XCTAssertEqual(quote.layout.attributedString.string, "Quote")
    }

    func test_paragraphReturn_routingIsUnchanged() {
        for viaSelector in [false, true] {
            let (canvas, _) = canvas()
            canvas.setBlocks([.paragraph(ParagraphBlock(id: BlockID("p"), runs: [TextRun(text: "Body")]))], width: 400)
            canvas.setCaret(global: canvas.boxes[0].textStart + 2)
            if viaSelector { canvas.insertNewline(nil) } else { pressReturn(canvas) }
            XCTAssertEqual(canvas.currentParagraphs().map(\.text), viaSelector ? ["Bo", "dy"] : ["Bo\ndy"])
        }
    }

    func test_codeReturn_routingIsUnchanged() {
        for viaSelector in [false, true] {
            let (canvas, _) = canvas()
            canvas.setBlocks([.code(CodeBlock(id: BlockID("c"), language: "swift", runs: [TextRun(text: "code")]))], width: 400)
            let code = canvas.boxes[0]
            canvas.setCaret(global: code.textStart + 2)
            if viaSelector { canvas.insertNewline(nil) } else { pressReturn(canvas) }
            XCTAssertEqual(code.textLayout.attributedString.string, viaSelector ? "code" : "co\nde")
        }
    }

    func test_shiftReturn_leavesQuoteWithoutChangingAuthor() {
        let (canvas, quote) = canvas(author: "Ada")
        canvas.setCaret(global: quote.textStart + 2)
        pressReturn(canvas, shift: true)
        XCTAssertEqual(quote.layout.attributedString.string, "Quote")
        XCTAssertEqual(quote.authorLayout.attributedString.string, "Ada")
        XCTAssertEqual(canvas.boxes.count, 2)
        XCTAssertTrue(canvas.boxes.last is BlockBox)
        XCTAssertEqual(canvas.head, canvas.boxes.last?.textStart)
    }
}
#endif
