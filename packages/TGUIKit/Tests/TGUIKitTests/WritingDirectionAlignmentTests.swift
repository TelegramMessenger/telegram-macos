import XCTest
import Cocoa
@testable import TGUIKit

final class WritingDirectionAlignmentTests: XCTestCase {
    private let alignmentDelegate = WritingDirectionAlignmentDelegate()

    private func makeStorage(_ text: String = "", baseWritingDirection: NSWritingDirection = .natural) -> NSTextStorage {
        let style = NSMutableParagraphStyle()
        style.baseWritingDirection = baseWritingDirection
        let storage = NSTextStorage()
        storage.delegate = alignmentDelegate
        storage.setAttributedString(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13), .paragraphStyle: style]))
        return storage
    }

    private func alignment(_ storage: NSTextStorage, at index: Int) -> NSTextAlignment {
        let style = storage.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle ?? NSParagraphStyle.default
        return style.alignment
    }

    private func append(_ text: String, to storage: NSTextStorage) {
        let attributes = storage.length > 0 ? storage.attributes(at: storage.length - 1, effectiveRange: nil) : [.font: NSFont.systemFont(ofSize: 13)]
        storage.append(NSAttributedString(string: text, attributes: attributes))
    }

    private func caretX(afterTyping text: String, alignsByWritingDirection: Bool) -> [CGFloat] {
        let storage = NSTextStorage()
        if alignsByWritingDirection {
            storage.delegate = alignmentDelegate
        }
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 300, height: 1000))
        layoutManager.addTextContainer(container)
        let style = NSMutableParagraphStyle()
        style.baseWritingDirection = .natural
        var result: [CGFloat] = []
        for character in text {
            storage.append(NSAttributedString(string: String(character), attributes: [.font: NSFont.systemFont(ofSize: 13), .paragraphStyle: style]))
            layoutManager.ensureLayout(for: container)
            let end = NSRange(location: storage.length, length: 0)
            var count = 0
            let rects = layoutManager.rectArray(forCharacterRange: end, withinSelectedCharacterRange: end, in: container, rectCount: &count)
            result.append(count > 0 ? rects![0].minX : -1)
        }
        return result
    }

    func testRightToLeftParagraphIsRightAligned() {
        let storage = makeStorage("سلام دنیا")
        XCTAssertEqual(alignment(storage, at: 0), .right)
    }

    func testLeftToRightParagraphKeepsNaturalAlignment() {
        let storage = makeStorage("hello world")
        XCTAssertEqual(alignment(storage, at: 0), .natural)
    }

    func testFirstStrongCharacterDecidesDirection() {
        XCTAssertEqual(alignment(makeStorage("123 سلام hello"), at: 0), .right)
        XCTAssertEqual(alignment(makeStorage("123 hello سلام"), at: 0), .natural)
        XCTAssertEqual(alignment(makeStorage("שלום"), at: 0), .right)
    }

    func testArabicIndicDigitsAloneAreNotRightToLeft() {
        XCTAssertEqual(alignment(makeStorage("۱۲۳ ٤٥٦"), at: 0), .natural)
    }

    func testArabicPunctuationAndSignsAreNeutral() {
        XCTAssertEqual(alignment(makeStorage("،Hello"), at: 0), .natural)
        XCTAssertEqual(alignment(makeStorage("٪Hello"), at: 0), .natural)
        XCTAssertEqual(alignment(makeStorage("\u{0600}Hello"), at: 0), .natural)
        XCTAssertEqual(alignment(makeStorage("،سلام"), at: 0), .right)
    }

    func testCombiningMarksAreNeutral() {
        XCTAssertEqual(alignment(makeStorage("\u{064B}Hello"), at: 0), .natural)
        XCTAssertEqual(alignment(makeStorage("\u{05B0}Hello"), at: 0), .natural)
        XCTAssertEqual(alignment(makeStorage("\u{0301}سلام"), at: 0), .right)
    }

    func testDirectionMarksDecideDirection() {
        XCTAssertEqual(alignment(makeStorage("\u{200F}hello"), at: 0), .right)
        XCTAssertEqual(alignment(makeStorage("\u{200E}سلام"), at: 0), .natural)
    }

    func testIsolatedTextDoesNotDecideDirection() {
        XCTAssertEqual(alignment(makeStorage("\u{2067}سلام\u{2069} hello"), at: 0), .natural)
        XCTAssertEqual(alignment(makeStorage("\u{2066}hello\u{2069} سلام"), at: 0), .right)
    }

    func testLongParagraphsResolveDirection() {
        let neutralRun = String(repeating: "1. ", count: 100)
        XCTAssertEqual(alignment(makeStorage(neutralRun + "سلام"), at: 0), .right)
        XCTAssertEqual(alignment(makeStorage(neutralRun + "hello سلام"), at: 0), .natural)
        XCTAssertEqual(alignment(makeStorage(String(repeating: "سلام دنیا ", count: 400)), at: 0), .right)
        XCTAssertEqual(alignment(makeStorage(String(repeating: "hello world ", count: 400)), at: 0), .natural)
        XCTAssertEqual(alignment(makeStorage(neutralRun + "\u{2067}hello\u{2069} سلام"), at: 0), .right)
    }

    func testExplicitBaseWritingDirectionWins() {
        XCTAssertEqual(alignment(makeStorage("hello", baseWritingDirection: .rightToLeft), at: 0), .right)
        XCTAssertEqual(alignment(makeStorage("سلام", baseWritingDirection: .leftToRight), at: 0), .natural)
    }

    func testEachParagraphIsAlignedOnItsOwn() {
        let storage = makeStorage("سلام\nhello\nدنیا")
        XCTAssertEqual(alignment(storage, at: 0), .right)
        XCTAssertEqual(alignment(storage, at: 5), .natural)
        XCTAssertEqual(alignment(storage, at: 11), .right)
    }

    func testAlignmentFollowsEditedText() {
        let storage = makeStorage()
        append("hi", to: storage)
        XCTAssertEqual(alignment(storage, at: 0), .natural)
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: "سلام")
        XCTAssertEqual(alignment(storage, at: 0), .right)
        storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: "hi")
        XCTAssertEqual(alignment(storage, at: 0), .natural)
    }

    func testTrailingSpaceMovesCaretInRightToLeftText() {
        let before = caretX(afterTyping: "سلام ", alignsByWritingDirection: false)
        XCTAssertEqual(before[3], before[4], "left-aligned right-to-left text hides the trailing space")

        let after = caretX(afterTyping: "سلام ", alignsByWritingDirection: true)
        XCTAssertLessThan(after[4], after[3])
    }

    func testRightToLeftScriptsAreRightAlignedAndShowTrailingSpace() {
        let samples: [(language: String, text: String)] = [
            ("Persian", "سلام"),
            ("Arabic", "مرحبا"),
            ("Urdu", "سلام"),
            ("Kurdish", "سڵاو"),
            ("Pashto", "ښه"),
            ("Uyghur", "ياخشى"),
            ("Hebrew", "שלום"),
            ("Yiddish", "שלום"),
            ("Syriac", "ܫܠܡܐ"),
            ("Dhivehi", "ސަލާމް"),
            ("N'Ko", "ߊߟߎ"),
        ]
        for sample in samples {
            XCTAssertEqual(alignment(makeStorage(sample.text), at: 0), .right, sample.language)
            let caret = caretX(afterTyping: sample.text + " ", alignsByWritingDirection: true)
            XCTAssertLessThan(caret[caret.count - 1], caret[caret.count - 2], sample.language)
        }
    }

    func testLeftToRightScriptsKeepNaturalAlignmentAndShowTrailingSpace() {
        let samples: [(language: String, text: String)] = [
            ("English", "hello"),
            ("Russian", "привет"),
            ("Greek", "γεια"),
            ("Turkish", "merhaba"),
            ("Armenian", "բարեւ"),
            ("Georgian", "გამარჯობა"),
            ("Hindi", "नमस्ते"),
            ("Thai", "สวัสดี"),
            ("Chinese", "你好"),
            ("Japanese", "こんにちは"),
            ("Korean", "안녕"),
        ]
        for sample in samples {
            XCTAssertEqual(alignment(makeStorage(sample.text), at: 0), .natural, sample.language)
            let caret = caretX(afterTyping: sample.text + " ", alignsByWritingDirection: true)
            XCTAssertGreaterThan(caret[caret.count - 1], caret[caret.count - 2], sample.language)
        }
    }

    func testLeadingEmojiAndPunctuationDoNotDecideDirection() {
        XCTAssertEqual(alignment(makeStorage("😀 «سلام»"), at: 0), .right)
        XCTAssertEqual(alignment(makeStorage("😀 \"hello\""), at: 0), .natural)
    }

    private func makeTextKit1View(width: CGFloat) -> (NSTextView, WritingDirectionSelection) {
        let container = NSTextContainer(size: CGSize(width: width, height: 1000))
        container.widthTracksTextView = false
        let layoutManager = NSLayoutManager()
        let storage = NSTextStorage()
        storage.delegate = alignmentDelegate
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100), textContainer: container)
        textView.textContainerInset = .zero
        textView.typingAttributes = [.font: NSFont.systemFont(ofSize: 13)]
        let selection = WritingDirectionSelection()
        selection.attach(to: textView)
        return (textView, selection)
    }

    private func clickedOffsets(in textView: NSTextView, atX xs: [CGFloat], y: CGFloat) throws -> [Int] {
        #if compiler(>=6.4)
        if #available(macOS 27.0, *) {
            let dataSource = try XCTUnwrap(textView.textSelectionManager?.textSelectionDataSource)
            XCTAssertTrue(dataSource is WritingDirectionResolvingSelectionDataSource)
            textView.layoutManager?.ensureLayout(for: textView.textContainer!)
            let navigation = NSTextSelectionNavigation(dataSource: dataSource)
            let start = dataSource.documentRange.location
            return xs.map { x in
                let selections = navigation.textSelections(interactingAt: CGPoint(x: x, y: y), inContainerAt: start, anchors: [], modifiers: [], selecting: false, bounds: .zero)
                return selections.first?.textRanges.first.map { dataSource.offset(from: start, to: $0.location) } ?? -1
            }
        }
        #endif
        throw XCTSkip("Text selection manager requires macOS 27")
    }

    func testClickBesideRightToLeftLinePlacesCaretByLineDirection() throws {
        let (textView, selection) = makeTextKit1View(width: 300)
        textView.insertText("سلام دنیا", replacementRange: NSRange(location: 0, length: 0))
        let offsets = try clickedOffsets(in: textView, atX: [5, 295], y: 5)
        XCTAssertEqual(offsets, [9, 0])
        withExtendedLifetime(selection) {}
    }

    func testClickBesideLeftToRightLineIsUnchanged() throws {
        let (textView, selection) = makeTextKit1View(width: 300)
        textView.insertText("hello world", replacementRange: NSRange(location: 0, length: 0))
        let offsets = try clickedOffsets(in: textView, atX: [0, 295], y: 5)
        XCTAssertEqual(offsets, [0, 11])
        withExtendedLifetime(selection) {}
    }

    func testClickFollowsEachParagraphDirection() throws {
        let (textView, selection) = makeTextKit1View(width: 300)
        textView.insertText("سلام\nhello\nدنیا", replacementRange: NSRange(location: 0, length: 0))
        let lineHeight = textView.layoutManager!.defaultLineHeight(for: NSFont.systemFont(ofSize: 13))
        let leftClicks = try [0.5, 1.5, 2.5].map { try clickedOffsets(in: textView, atX: [5], y: lineHeight * $0)[0] }
        XCTAssertEqual(leftClicks, [4, 5, 15])
        withExtendedLifetime(selection) {}
    }

    func testSearchTextFieldClickBesideRightToLeftQuery() throws {
        let field = SearchTextField()
        field.frame = NSRect(x: 0, y: 0, width: 200, height: 22)
        field.insertText("سلام", replacementRange: NSRange(location: 0, length: 0))
        let offsets = try clickedOffsets(in: field, atX: [5], y: 5)
        XCTAssertEqual(offsets, [4])
    }

    func testSearchTextFieldAlignsRightToLeftQuery() {
        let field = SearchTextField()
        field.frame = NSRect(x: 0, y: 0, width: 200, height: 22)
        field.insertText("سلام ", replacementRange: NSRange(location: 0, length: 0))
        let storage = field.textStorage!
        XCTAssertEqual(alignment(storage, at: 0), .right)
    }
}
