import XCTest
import InputView
import InlineStickerLayer
import TelegramCore
import TGUIKit
@testable import ChatUI

final class ChatQuoteTextRangeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private func layout(_ text: String, emoji: [String]) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text)
        var searchLocation = 0
        var fileId: Int64 = 0
        while searchLocation < result.length {
            let nearest = emoji.compactMap { value -> (NSRange, String)? in
                let range = (result.string as NSString).range(of: value, range: NSRange(location: searchLocation, length: result.length - searchLocation))
                return range.location == NSNotFound ? nil : (range, value)
            }.min { $0.0.location < $1.0.location }
            guard let (range, value) = nearest else { break }
            fileId += 1
            let item = InlineStickerItem(source: .attribute(.init(fileId: fileId, file: nil, emoji: value)))
            result.replaceCharacters(in: range, with: NSAttributedString(string: "&", attributes: [TextInputAttributes.embedded: item]))
            searchLocation = range.location + 1
        }
        return result
    }

    func testProductionEmojiReplacementRetainsQuoteGeometry() {
        let text = "Intro 💬 first.\n\nSecond 👍🏽 quote."
        let attributed = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let originalQuote = "Second 👍🏽 quote"
        let originalRange = (text as NSString).range(of: originalQuote)
        let emoji = ["💬", "👍🏽"]
        let entities = emoji.enumerated().map { index, value in
            let range = (text as NSString).range(of: value)
            return MessageTextEntity(range: range.location ..< NSMaxRange(range), type: .CustomEmoji(stickerPack: nil, fileId: Int64(index + 1)))
        }
        InlineStickerItem.apply(to: attributed, associatedMedia: [:], entities: entities, isPremium: true)
        let mapped = chatQuoteTextRange(in: attributed, text: originalQuote, offset: originalRange.location)
        XCTAssertNotNil(mapped)
        let quote = mapped.map { (attributed.string as NSString).substring(with: $0) }
        XCTAssertNotEqual(quote, originalQuote)
        XCTAssertEqual(mapped?.location, (attributed.string as NSString).range(of: "Second").location)
        if let mapped, let quote {
            let layout = TextViewLayout(attributed)
            layout.measure(width: 300)
            XCTAssertFalse(layout.rects(mapped).isEmpty)
            XCTAssertEqual((attributed.string as NSString).substring(with: mapped), quote)
            XCTAssertEqual((attributed.string as NSString).range(of: originalQuote).location, NSNotFound)
        }
    }

    func testQuoteContainingCustomEmojiMapsToLayout() {
        let text = "Intro. 💬Можно было бы подумать💬, — отметил."
        let layout = layout(text, emoji: ["💬"])
        let quote = "Можно было бы подумать💬, — отметил"
        let range = chatQuoteTextRange(in: layout, text: quote, offset: (text as NSString).range(of: quote).location)
        XCTAssertEqual(range.map { (layout.string as NSString).substring(with: $0) }, "Можно было бы подумать&, — отметил")
    }

    func testOriginalOffsetPicksNearestDuplicateAfterEmoji() {
        let layout = layout("💬💬💬💬ab 💬ab", emoji: ["💬"])
        XCTAssertEqual(chatQuoteTextRange(in: layout, text: "ab", offset: 10), NSRange(location: 4, length: 2))
        XCTAssertEqual(chatQuoteTextRange(in: layout, text: "ab", offset: 15), NSRange(location: 8, length: 2))
    }

    func testExactOffsetPreservesOverlappingQuoteOccurrence() {
        let layout = NSAttributedString(string: "aaaa")
        XCTAssertEqual(chatQuoteTextRange(in: layout, text: "aa", offset: 1), NSRange(location: 1, length: 2))
    }

    func testExactOverlappingOffsetUsesOriginalUTF16PositionsAfterCustomEmoji() {
        let text = "👍🏽aaaa"
        let originalOffset = ("👍🏽" as NSString).length + 1
        let layout = layout(text, emoji: ["👍🏽"])
        XCTAssertEqual(chatQuoteTextRange(in: layout, text: "aa", offset: originalOffset), NSRange(location: 2, length: 2))
        XCTAssertEqual(chatQuoteTextRange(in: NSAttributedString(string: "😀aaaa"), text: "aa", offset: 3), NSRange(location: 3, length: 2))
    }

    func testNearestOffsetFallbackIncludesOverlappingOccurrences() {
        let layout = NSAttributedString(string: "aaaa")
        XCTAssertEqual(chatQuoteTextRange(in: layout, text: "aaa", offset: 2), NSRange(location: 1, length: 3))
    }

    func testOverlappingFallbackSearchCrossesUTF16SurrogateBoundaries() {
        let layout = NSAttributedString(string: "😀😀😀")
        XCTAssertEqual(chatQuoteTextRange(in: layout, text: "😀😀", offset: 3), NSRange(location: 2, length: 4))
    }

    func testQuoteBoundariesInsideEmojiIncludeWholePlaceholder() {
        let layout = layout("a 👍👍 b", emoji: ["👍👍"])
        XCTAssertEqual(chatQuoteTextRange(in: layout, text: "a 👍", offset: 0), NSRange(location: 0, length: 3))
        XCTAssertEqual(chatQuoteTextRange(in: layout, text: "👍 b", offset: 4), NSRange(location: 2, length: 3))
    }

    func testQuoteEndingWithEmojiMapsItsUpperBoundary() {
        let layout = layout("💬 one x 💬", emoji: ["💬"])
        XCTAssertEqual(chatQuoteTextRange(in: layout, text: "x 💬", offset: nil), NSRange(location: 6, length: 3))
    }

    func testNoOffsetUsesFirstOccurrence() {
        let layout = layout("💬 ab 💬 ab", emoji: ["💬"])
        XCTAssertEqual(chatQuoteTextRange(in: layout, text: "ab", offset: nil), NSRange(location: 2, length: 2))
    }

    func testPlainTextUsesNearestOffsetAndDeterministicTie() {
        let layout = NSAttributedString(string: "one two one two")
        XCTAssertEqual(chatQuoteTextRange(in: layout, text: "one", offset: 7), NSRange(location: 8, length: 3))
        XCTAssertEqual(chatQuoteTextRange(in: layout, text: "one", offset: 4), NSRange(location: 8, length: 3))
        XCTAssertEqual(chatQuoteTextRange(in: layout, text: "one", offset: nil), NSRange(location: 0, length: 3))
    }

    func testMissingOrEmptyQuoteHasNoHighlight() {
        let layout = layout("edited 💬 text", emoji: ["💬"])
        XCTAssertNil(chatQuoteTextRange(in: layout, text: "original 💬 text", offset: 0))
        XCTAssertNil(chatQuoteTextRange(in: layout, text: "", offset: 0))
        XCTAssertNil(chatQuoteTextRange(in: NSAttributedString(string: ""), text: "x", offset: nil))
    }

    func testDifferentEmojiLengthsAndUnrelatedEmbeddedValues() {
        let layout = NSMutableAttributedString(attributedString: layout("👍🏽ab👨‍👩‍👧‍👦 cd", emoji: ["👍🏽", "👨‍👩‍👧‍👦"]))
        layout.addAttribute(TextInputAttributes.embedded, value: "unrelated", range: NSRange(location: 6, length: 1))
        XCTAssertEqual(chatQuoteTextRange(in: layout, text: "ab👨‍👩‍👧‍👦 cd", offset: 4), NSRange(location: 1, length: 6))
    }
}
