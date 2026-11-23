import XCTest

__TRIM__

// The composer-state split around the caret.
//
// A paste at the caret must not eat the whitespace around it: with the caret in
// "hello | world", the text before the caret is "hello " and the text after it is
// " world" — trimming them would silently turn the message into "helloworld".
//
// `ChatTextInputState.subInputState(from:trimWhitespace:)` decides this, and the decision
// lives in the production source, so run.py extracts the trimming steps from it and the tests
// below drive the extracted code.
final class ComposerWhitespaceTests: XCTestCase {

    /// The old single-argument API trimmed the range's whitespace; the default must keep doing
    /// exactly that, so every existing caller is unaffected.
    func testDefaultTrimBehaviourIsUnchanged() {
        XCTAssertEqual(trimmedText("  hi  ", trimWhitespace: true), "hi")
        XCTAssertEqual(trimmedText("\n\na\n\n", trimWhitespace: true), "a")
    }

    /// The untrimmed overload keeps the whitespace around the caret.
    func testUntrimmedKeepsTheWhitespaceAroundTheCaret() {
        XCTAssertEqual(trimmedText("hello ", trimWhitespace: false), "hello ")
        XCTAssertEqual(trimmedText(" world", trimWhitespace: false), " world")
        XCTAssertEqual(trimmedText("a\n\n", trimWhitespace: false), "a\n\n")
        XCTAssertEqual(trimmedText("\n\nb", trimWhitespace: false), "\n\nb")
    }

    /// The case that motivated the overload: the caret sits between "hello " and " world".
    func testCaretSurroundingsSurviveTheSplit() {
        let full = "hello  world"
        let caret = 6 // after "hello "
        let head = String(full[full.startIndex..<full.index(full.startIndex, offsetBy: caret)])
        let tail = String(full[full.index(full.startIndex, offsetBy: caret)...])
        XCTAssertEqual(trimmedText(head, trimWhitespace: false), "hello ")
        XCTAssertEqual(trimmedText(tail, trimWhitespace: false), " world")
        XCTAssertEqual(
            trimmedText(head, trimWhitespace: false) + trimmedText(tail, trimWhitespace: false),
            "hello  world",
            "splitting the composer text at the caret must not lose any of it")
    }
}
