#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

@available(macOS 12, *)
final class CanvasPullQuoteAuthorReturnTests: AppKitTestCase {
    private func canvas(body: String = "", author: String = "Ada Lovelace") -> DocumentCanvasView {
        let canvas = DocumentCanvasView()
        let quote = PullQuote(id: BlockID("quote"), runs: body.isEmpty ? [] : [TextRun(text: body)],
                              author: author.isEmpty ? [] : [TextRun(text: author, attributes: CharacterAttributes(underline: true))])
        canvas.setBlocks([.pullQuote(quote)], width: 400)
        canvas.setCaret(global: canvas.boxes[0].textStart)
        return canvas
    }

    private func quote(_ canvas: DocumentCanvasView, file: StaticString = #filePath, line: UInt = #line) throws -> PullQuote {
        try XCTUnwrap(canvas.currentBlocks().compactMap { if case let .pullQuote(quote) = $0 { return quote }; return nil }.first,
                      file: file, line: line)
    }

    private func pressReturn(_ canvas: DocumentCanvasView, keyCode: UInt16 = 36, shift: Bool = false) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: shift ? [.shift] : [],
                                    timestamp: 0, windowNumber: 0, context: nil, characters: "\r",
                                    charactersIgnoringModifiers: "\r", isARepeat: false, keyCode: keyCode)!
        canvas.keyDown(with: event)
    }

    func test_selectorReturnOnAuthorOnlyQuote_preservesAuthor() throws {
        let canvas = canvas()
        let before = try quote(canvas)
        canvas.insertNewline(nil)
        let after = try quote(canvas)
        XCTAssertEqual(after, before)
    }

    func test_commandReturnOnAuthorOnlyQuote_preservesAuthor() throws {
        let canvas = canvas()
        let before = try quote(canvas)
        canvas.doCommand(by: #selector(NSResponder.insertNewline(_:)))
        let after = try quote(canvas)
        XCTAssertEqual(after, before)
    }

    func test_repeatedSelectorReturnOnAuthorOnlyQuote_preservesAuthor() throws {
        let canvas = canvas()
        let before = try quote(canvas)
        canvas.insertNewline(nil)
        canvas.insertNewline(nil)
        let after = try quote(canvas)
        XCTAssertEqual(after, before)
    }

    func test_rawReturnOnAuthorOnlyQuote_preservesAuthor() throws {
        for keyCode: UInt16 in [36, 76] {
            let canvas = canvas()
            let before = try quote(canvas)
            pressReturn(canvas, keyCode: keyCode)
            let after = try quote(canvas)
            XCTAssertEqual(after, before)
        }
    }

    func test_returnOnAuthorOnlyQuote_exitsBelowAndUndoes() throws {
        for viaSelector in [false, true] {
            let canvas = canvas()
            let before = canvas.currentModelBlocks()
            let beforeHead = canvas.head
            let undo = UndoManager(); undo.groupsByEvent = false; canvas.undoManagerOverride = undo
            undo.beginUndoGrouping()
            if viaSelector { canvas.insertNewline(nil) } else { pressReturn(canvas) }
            undo.endUndoGrouping()
            XCTAssertEqual(canvas.boxes.count, 2)
            XCTAssertTrue(canvas.boxes.first is PullQuoteBox)
            let paragraph = try XCTUnwrap(canvas.boxes.last as? BlockBox)
            XCTAssertEqual(paragraph.style, .body)
            XCTAssertEqual(paragraph.textLength, 0)
            XCTAssertEqual(canvas.anchor, paragraph.textStart)
            XCTAssertEqual(canvas.head, paragraph.textStart)
            let after = canvas.currentModelBlocks()
            undo.undo()
            XCTAssertEqual(canvas.currentModelBlocks(), before)
            XCTAssertEqual(canvas.head, beforeHead)
            undo.redo()
            XCTAssertEqual(canvas.currentModelBlocks(), after)
            XCTAssertEqual(canvas.head, canvas.boxes.last?.textStart)
        }
    }

    func test_shiftReturnOnAuthorOnlyQuote_preservesAuthor() throws {
        let canvas = canvas()
        let before = try quote(canvas)
        pressReturn(canvas, shift: true)
        let after = try quote(canvas)
        XCTAssertEqual(after, before)
        XCTAssertEqual(canvas.boxes.count, 2)
        XCTAssertEqual(canvas.head, canvas.boxes.last?.textStart)
    }

    func test_returnAfterBlankBodyLine_preservesAuthor() throws {
        let canvas = canvas(body: "\n")
        let before = try quote(canvas)
        canvas.setCaret(global: canvas.boxes[0].textStart + 1)
        canvas.insertNewline(nil)
        let after = try quote(canvas)
        XCTAssertEqual(after.id, before.id)
        XCTAssertEqual(after.author, before.author)
        XCTAssertTrue(after.text.isEmpty)
        XCTAssertEqual(canvas.boxes.count, 2)
        XCTAssertEqual(canvas.head, canvas.boxes.last?.textStart)
    }

    func test_returnAfterDeletingBody_preservesRemainingAuthor() throws {
        let canvas = canvas(body: "Quote")
        let before = try quote(canvas)
        let body = canvas.boxes[0]
        canvas.selectedGlobalRange = (body.textStart, body.textStart + body.textLength)
        canvas.commitText("")
        canvas.insertNewline(nil)
        let after = try quote(canvas)
        XCTAssertEqual(after.id, before.id)
        XCTAssertEqual(after.author, before.author)
        XCTAssertTrue(after.text.isEmpty)
    }

    func test_whitespaceAuthor_isNotDiscarded() throws {
        let canvas = canvas(author: " ")
        let before = try quote(canvas)
        canvas.insertNewline(nil)
        let after = try quote(canvas)
        XCTAssertEqual(after, before)
    }

    func test_trulyEmptyQuote_stillBecomesBodyParagraph() {
        for viaSelector in [false, true] {
            let canvas = canvas(author: "")
            if viaSelector { canvas.insertNewline(nil) } else { pressReturn(canvas) }
            XCTAssertEqual(canvas.boxes.count, 1)
            XCTAssertTrue(canvas.boxes.first is BlockBox)
            XCTAssertEqual(canvas.boxes.first?.textLength, 0)
            XCTAssertEqual(canvas.head, canvas.boxes.first?.textStart)
        }
    }

    func test_hostConsumedReturn_keepsAuthorOnlyQuoteUntouched() {
        let canvas = canvas()
        let before = canvas.currentModelBlocks()
        let beforeHead = canvas.head
        canvas.onReturnKey = { true }
        canvas.insertNewline(nil)
        XCTAssertEqual(canvas.currentModelBlocks(), before)
        XCTAssertEqual(canvas.head, beforeHead)
    }
}
#endif
