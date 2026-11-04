#if canImport(AppKit)
import AppKit
import XCTest
@testable import RichTextEditorUI
import RichTextEditorCore

/// The canvas (the NSTextInputClient that handles keyDown) must end up as the window's first responder
/// when the host focuses the editor — otherwise typing-on-launch is dead (the façade has no keyDown).
@available(macOS 12, *)
final class FacadeFocusTests: AppKitTestCase {
    func test_focusingFacade_makesCanvasFirstResponder() {
        let editor = RichTextEditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        editor.document = Document(blocks: [.paragraph(ParagraphBlock(id: BlockID.generate()))])
        let win = hostInWindow(editor)
        editor.makeEditorFirstResponder()
        XCTAssertTrue(win.firstResponder === editor.canvas,
                      "the canvas must be first responder so keyDown reaches the editor")
    }

    private func hostedEditor(_ text: String) -> (RichTextEditorView, NSWindow) {
        let editor = RichTextEditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        editor.document = Document(blocks: [.paragraph(ParagraphBlock(id: BlockID.generate(), runs: [TextRun(text: text)]))])
        let win = hostInWindow(editor)
        editor.makeEditorFirstResponder()
        editor.canvas.moveCaretToEnd()
        return (editor, win)
    }

    private func keyEvent(_ characters: String, keyCode: UInt16, window: NSWindow) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
    }

    func test_keyOutsideCompositionIsLeftToTheHost() throws {
        let (editor, win) = hostedEditor("prefix")
        defer { win.orderOut(nil) }
        let escape = try keyEvent("\u{1b}", keyCode: 53, window: win)
        XCTAssertFalse(editor.handleKeyDuringComposition(escape),
                       "without marked text Escape belongs to the host, which closes the modal")
        XCTAssertEqual(editor.canvas.text(inGlobalRange: 0, editor.canvas.documentSizeValue), "prefix")
    }

    func test_keyDuringCompositionReachesTheInputContext() throws {
        let (editor, win) = hostedEditor("prefix")
        defer { win.orderOut(nil) }
        editor.canvas.setMarkedText("˜", selectedRange: NSRange(location: 1, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        let delete = try keyEvent("\u{7f}", keyCode: 51, window: win)
        XCTAssertTrue(editor.handleKeyDuringComposition(delete),
                      "while composing, the key must be consumed by the editor instead of the host")
        XCTAssertEqual(editor.canvas.text(inGlobalRange: 0, editor.canvas.documentSizeValue), "prefix")
        XCTAssertFalse(editor.canvas.hasMarkedText())
    }

    func test_canvasDoesNotInheritATableAccessibilityParent() {
        let editor = RichTextEditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))

        XCTAssertNil(editor.canvas.accessibilityParent(),
                     "the focused canvas must not ask AppKit to synthesize a table-cell accessibility parent")
    }

    func test_nonScrollingModeHostsCanvasDirectly() {
        let editor = RichTextEditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))

        editor.isScrollEnabled = false
        editor.layoutSubtreeIfNeeded()

        XCTAssertTrue(editor.canvas.superview === editor,
                      "a non-scrolling editor must not retain an NSScrollView between its canvas and host")
        XCTAssertFalse(editor.subviews.contains { $0 is NSScrollView },
                       "the internal scroll view must be detached from a table-backed editor")
        XCTAssertTrue(editor.inputResponder === editor.canvas,
                      "hosts must receive the actual text-input responder rather than the façade")
    }

    func test_reenablingScrollingReparentsTheExistingCanvas() {
        let editor = RichTextEditorView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let canvas = editor.canvas
        editor.isScrollEnabled = false

        editor.isScrollEnabled = true
        editor.layoutSubtreeIfNeeded()

        XCTAssertTrue(editor.canvas === canvas)
        XCTAssertTrue(editor.canvas.superview is NSClipView,
                      "re-enabling scrolling must restore the canvas as the scroll view document")
        XCTAssertTrue(editor.subviews.contains { $0 is NSScrollView })
    }
}
#endif
