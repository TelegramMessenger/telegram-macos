import XCTest
import InputView
import RichTextEditorCore
@testable import ChatUI

/// The composer text split around the caret when a rich fragment is pasted.
///
/// A paste at the caret must not eat the whitespace around it: with the caret in "hello | world"
/// the text before the caret is "hello " and the text after it is " world" — trimming them would
/// silently turn the message into "helloworld".
final class ChatComposerWhitespaceSplitTests: XCTestCase {

    private func state(_ text: String, selection: Range<Int>) -> ChatTextInputState {
        return ChatTextInputState(inputText: text, selectionRange: selection, attributes: [])
    }

    /// The old single-argument API trimmed the range's whitespace; the default must keep doing
    /// exactly that, so every existing caller is unaffected.
    func testDefaultTrimBehaviourIsUnchanged() {
        XCTAssertEqual(state("  hi  ", selection: 0 ..< 7).subInputState(from: NSMakeRange(0, 7)).inputText, "hi")
        XCTAssertEqual(state("\n\na\n\n", selection: 0 ..< 5).subInputState(from: NSMakeRange(0, 5)).inputText, "a")
    }

    /// The untrimmed overload keeps the whitespace around the caret.
    func testUntrimmedKeepsTheWhitespaceAroundTheCaret() {
        XCTAssertEqual(state("hello ", selection: 0 ..< 6).subInputState(from: NSMakeRange(0, 6), trimWhitespace: false).inputText, "hello ")
        XCTAssertEqual(state(" world", selection: 0 ..< 6).subInputState(from: NSMakeRange(0, 6), trimWhitespace: false).inputText, " world")
        XCTAssertEqual(state("a\n\n", selection: 0 ..< 3).subInputState(from: NSMakeRange(0, 3), trimWhitespace: false).inputText, "a\n\n")
        XCTAssertEqual(state("\n\nb", selection: 0 ..< 3).subInputState(from: NSMakeRange(0, 3), trimWhitespace: false).inputText, "\n\nb")
    }

    /// The case that motivated the overload: the caret sits between "hello " and " world".
    func testCaretSurroundingsSurviveTheSplit() {
        let full = "hello  world"
        let caret = 6 // after "hello "
        let head = state(full, selection: caret ..< caret).subInputState(from: NSMakeRange(0, caret), trimWhitespace: false)
        let tail = state(full, selection: caret ..< caret).subInputState(from: NSMakeRange(caret, full.utf16.count - caret), trimWhitespace: false)
        XCTAssertEqual(head.inputText, "hello ")
        XCTAssertEqual(tail.inputText, " world")
        XCTAssertEqual(head.inputText + tail.inputText, "hello  world", "splitting the composer text at the caret must not lose any of it")
    }

    // MARK: - The rich-paste split

    /// The split the rich paste uses: the text around the caret, with its whitespace intact.
    func testSurroundingBlocksKeepTheWhitespaceAroundTheCaret() {
        let full = "hello  world"
        let caret = 6 // after "hello "
        let surrounding = RichTextComposerPasteMerge.surroundingBlocks(state(full, selection: caret ..< caret))
        XCTAssertEqual(text(surrounding.before), "hello ")
        XCTAssertEqual(text(surrounding.after), " world")
    }

    /// A selection is replaced by the paste, exactly like a normal paste: only the text outside the
    /// selected range is kept.
    func testSurroundingBlocksReplaceTheSelectedRange() {
        let full = "hello world"
        let surrounding = RichTextComposerPasteMerge.surroundingBlocks(state(full, selection: 6 ..< 11))
        XCTAssertEqual(text(surrounding.before), "hello ")
        XCTAssertEqual(text(surrounding.after), "", "the selected range is replaced, not kept")
    }

    /// An empty composer contributes nothing around the fragment.
    func testSurroundingBlocksOfAnEmptyComposerAreEmpty() {
        let surrounding = RichTextComposerPasteMerge.surroundingBlocks(state("", selection: 0 ..< 0))
        XCTAssertTrue(surrounding.before.isEmpty)
        XCTAssertTrue(surrounding.after.isEmpty)
    }

    private func text(_ blocks: [Block]) -> String {
        return blocks.compactMap { block -> String? in
            if case let .paragraph(paragraph) = block {
                return paragraph.runs.map(\.text).joined()
            }
            return nil
        }.joined(separator: "\n")
    }
}
