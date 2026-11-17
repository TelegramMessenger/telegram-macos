import Cocoa
import XCTest
@testable import InstantPageUI

final class InstantPageTextFinderTests: XCTestCase {
    private func text(_ string: String, excludedRanges: [NSRange] = [], lineRanges: [NSRange]? = nil, origin: CGPoint = .zero, view: NSView? = nil, scrollToVisible: @escaping (CGRect) -> Void = { _ in }) -> InstantPageFindText {
        let attributedString = NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: 16)])
        let typesetter = CTTypesetterCreateWithAttributedString(attributedString)
        let ranges = lineRanges ?? [NSRange(location: 0, length: attributedString.length)]
        let lines = ranges.enumerated().map { index, range -> InstantPageFindLine in
            let line = CTTypesetterCreateLine(typesetter, CFRange(location: range.location, length: range.length))
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            let width = CTLineGetTypographicBounds(line, &ascent, &descent, nil)
            return InstantPageFindLine(line: line, range: range, frame: CGRect(x: 0, y: CGFloat(index) * 24, width: width, height: ascent))
        }
        return InstantPageFindText(attributedString: attributedString, lines: lines, excludedRanges: excludedRanges, location: {
            return view.map { ($0, origin) }
        }, scrollToVisible: scrollToVisible)
    }

    private func finder() -> (InstantPageTextFinder, NSScrollView, NSView) {
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 160))
        let document = NSView(frame: CGRect(x: 0, y: 0, width: 300, height: 1000))
        scroll.documentView = document
        let client = InstantPageTextFinder(scrollView: scroll, indicatorColor: { NSColor() })
        return (client, scroll, document)
    }

    private func strings(_ client: InstantPageTextFinder) -> [(String, NSRange, Bool)] {
        var result: [(String, NSRange, Bool)] = []
        var index = 0
        while index < client.stringLength() {
            var range = NSRange()
            var boundary = ObjCBool(false)
            let string = client.string(at: index, effectiveRange: &range, endsWithSearchBoundary: &boundary)
            result.append((string, range, boundary.boolValue))
            XCTAssertGreaterThan(range.length, 0)
            guard range.length > 0 else { break }
            index = NSMaxRange(range)
        }
        return result
    }

    func testUTF16SegmentsHaveSearchBoundaries() {
        let (client, scroll, document) = finder()
        client.update([text("A😀café", view: document), text("CAFÉ", view: document)])
        XCTAssertTrue(client.finder.findBarContainer === scroll)
        XCTAssertTrue(client.finder.client === client)
        XCTAssertTrue(client.finder.isIncrementalSearchingEnabled)
        XCTAssertEqual(client.stringLength(), 11)
        let segments = strings(client)
        XCTAssertEqual(segments.map { $0.0 }, ["A😀café", "CAFÉ"])
        XCTAssertEqual(segments.map { $0.1 }, [NSRange(location: 0, length: 7), NSRange(location: 7, length: 4)])
        XCTAssertTrue(segments.allSatisfy { $0.2 })
        for selector in ["stringAtIndex:effectiveRange:endsWithSearchBoundary:", "stringLength", "firstSelectedRange", "selectedRanges", "setSelectedRanges:", "rectsForCharacterRange:", "contentViewAtIndex:effectiveCharacterRange:", "drawCharactersInRange:forContentView:"] {
            XCTAssertTrue(client.responds(to: NSSelectorFromString(selector)), selector)
        }
        XCTAssertTrue(client.finder.validateAction(.showFindInterface))
        XCTAssertFalse(client.isEditable)
        XCTAssertFalse(client.allowsMultipleSelection)
        XCTAssertFalse(client.finder.validateAction(.replace))
    }

    func testHiddenTextAndAttachmentsCannotJoinIntoFauxMatches() {
        let (client, _, document) = finder()
        let string = "abSECRETcd\u{fffc}ef"
        let source = text(string, excludedRanges: [NSRange(location: 2, length: 6), NSRange(location: 10, length: 1)], view: document)
        client.update([source])
        XCTAssertEqual(strings(client).map { $0.0 }, ["ab", "cd", "ef"])
        XCTAssertTrue(strings(client).allSatisfy { $0.2 })
        XCTAssertEqual(client.stringLength(), 6)
        var range = NSRange()
        var boundary = ObjCBool(false)
        XCTAssertEqual(client.string(at: 2, effectiveRange: &range, endsWithSearchBoundary: &boundary), "cd")
        XCTAssertEqual(range, NSRange(location: 2, length: 2))
        let rects = client.rects(forCharacterRange: range)?.map { $0.rectValue } ?? []
        XCTAssertEqual(rects, source.rects(for: NSRange(location: 8, length: 2)))
    }

    func testOnlyRenderedLineRangesAreSearchable() {
        let (client, _, document) = finder()
        client.update([text("visible truncated", lineRanges: [NSRange(location: 0, length: 7)], view: document)])
        XCTAssertEqual(strings(client).map { $0.0 }, ["visible"])
        XCTAssertEqual(client.stringLength(), 7)
    }

    func testMultilineMatchesUseOriginalUTF16OffsetsAndOrigins() {
        let (client, _, document) = finder()
        let string = "😀first\nsecond"
        let source = text(string, lineRanges: [NSRange(location: 0, length: 8), NSRange(location: 8, length: 6)], origin: CGPoint(x: 37, y: 120), view: document)
        client.update([source])
        let range = NSRange(location: 4, length: 7)
        let local = source.rects(for: range)
        XCTAssertEqual(local.count, 2)
        XCTAssertEqual(client.rects(forCharacterRange: range)?.map { $0.rectValue }, local.map { $0.offsetBy(dx: 37, dy: 120) })
        var effectiveRange = NSRange()
        XCTAssertTrue(client.contentView(at: 9, effectiveCharacterRange: &effectiveRange) === document)
        XCTAssertEqual(effectiveRange, NSRange(location: 0, length: 14))
    }

    func testBidirectionalMatchesDoNotCoverUnmatchedRuns() {
        let source = text("abc אבג def")
        let latin = source.rects(for: NSRange(location: 0, length: 3))
        let hebrew = source.rects(for: NSRange(location: 4, length: 3))
        let trailing = source.rects(for: NSRange(location: 8, length: 3))
        XCTAssertEqual(latin.count, 1)
        XCTAssertEqual(hebrew.count, 1)
        XCTAssertEqual(trailing.count, 1)
        XCTAssertLessThanOrEqual(latin[0].maxX, hebrew[0].minX)
        XCTAssertLessThanOrEqual(hebrew[0].maxX, trailing[0].minX)
        XCTAssertGreaterThan(source.rects(for: NSRange(location: 3, length: 2)).count, 1)
    }

    func testLigaturesAndCombiningMarksHaveNonemptyGlyphGeometry() {
        let source = text("office e\u{301} 😀")
        for range in [NSRange(location: 2, length: 1), NSRange(location: 7, length: 2), NSRange(location: 10, length: 2)] {
            let rects = source.rects(for: range)
            XCTAssertFalse(rects.isEmpty)
            XCTAssertTrue(rects.allSatisfy { $0.width > 0 && $0.height > 0 })
        }
    }

    func testFindSelectionAndScrollDoNotModifyArticleText() {
        let (client, _, document) = finder()
        var scrolled: CGRect?
        let source = text("first target last", view: document, scrollToVisible: { scrolled = $0 })
        client.update([source])
        let range = NSRange(location: 6, length: 6)
        client.selectedRanges = [NSValue(range: range)]
        XCTAssertEqual(client.firstSelectedRange, range)
        XCTAssertEqual(source.attributedString.string, "first target last")
        client.scrollRangeToVisible(range)
        XCTAssertEqual(scrolled, source.rects(for: range).first)
        client.selectedRanges = [NSValue(range: NSRange(location: NSNotFound, length: 1))]
        XCTAssertEqual(client.firstSelectedRange, range)
        client.selectedRanges = [NSValue(range: NSRange(location: 15, length: 3))]
        XCTAssertEqual(client.firstSelectedRange, range)
    }

    func testInvalidationRemovesOldArticleAndSelection() {
        let (client, _, document) = finder()
        client.update([text("old article", view: document)])
        client.selectedRanges = [NSValue(range: NSRange(location: 4, length: 7))]
        client.invalidate()
        XCTAssertEqual(client.stringLength(), 0)
        XCTAssertEqual(client.firstSelectedRange, NSRange(location: 0, length: 0))
        XCTAssertEqual(client.visibleCharacterRanges, [])
        XCTAssertEqual(client.rects(forCharacterRange: NSRange(location: 4, length: 7)), [])
        client.update([text("new", view: document)])
        XCTAssertEqual(strings(client).map { $0.0 }, ["new"])
        XCTAssertEqual(client.stringLength(), 3)
    }

    func testTruncatedRunsDoNotExposeTheRestOfTheLine() {
        let string = NSAttributedString(string: "visible hidden suffix", attributes: [.font: NSFont.systemFont(ofSize: 16)])
        let line = CTLineCreateWithAttributedString(string)
        let token = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: [.font: NSFont.systemFont(ofSize: 16)]))
        let truncated = CTLineCreateTruncatedLine(line, 70, .end, token)!
        let text = InstantPageFindText(attributedString: string, lines: [InstantPageFindLine(line: truncated, range: NSRange(location: 0, length: string.length), frame: CGRect(x: 0, y: 0, width: 70, height: 16))], excludedRanges: [], location: { nil }, scrollToVisible: { _ in })
        let (client, _, _) = finder()
        client.update([text])
        XCTAssertLessThan(client.stringLength(), string.length)
        XCTAssertFalse(strings(client).contains(where: { $0.0.contains("hidden") || $0.0.contains("suffix") }))
    }

    func testHiddenRangesCanBecomeSearchableWithoutStaleSelection() {
        let (client, _, document) = finder()
        client.update([text("before secret after", excludedRanges: [NSRange(location: 7, length: 6)], view: document)])
        XCTAssertEqual(strings(client).map { $0.0 }, ["before ", " after"])
        client.selectedRanges = [NSValue(range: NSRange(location: 7, length: 6))]
        client.update([text("before secret after", view: document)])
        XCTAssertEqual(strings(client).map { $0.0 }, ["before secret after"])
        XCTAssertEqual(client.firstSelectedRange, NSRange(location: 0, length: 0))
    }

    func testLiveLocationTracksRelayoutAndScrollCallback() {
        let (client, _, document) = finder()
        let template = text("table cell")
        var origin = CGPoint(x: 24, y: 64)
        let text = InstantPageFindText(attributedString: template.attributedString, lines: template.lines, excludedRanges: [], location: { (document, origin) }, scrollToVisible: { rect in
            document.scrollToVisible(rect.offsetBy(dx: origin.x, dy: origin.y))
        })
        client.update([text])
        let range = NSRange(location: 6, length: 4)
        let before = client.rects(forCharacterRange: range)!.map { $0.rectValue }
        origin = CGPoint(x: 88, y: 180)
        let after = client.rects(forCharacterRange: range)!.map { $0.rectValue }
        XCTAssertEqual(after, before.map { $0.offsetBy(dx: 64, dy: 116) })
        XCTAssertEqual(strings(client).map { $0.0 }, ["table cell"])
    }

    func testTelegramSearchFindsCaseInsensitiveMatchesWithoutCrossingBoundaries() {
        let (client, _, document) = finder()
        client.update([text("abSECRETcd CAFÉ café", excludedRanges: [NSRange(location: 2, length: 6)], view: document)])
        client.search("abcd")
        XCTAssertTrue(client.matches.isEmpty)
        client.search("CAFÉ")
        XCTAssertEqual(client.matches.count, 2)
        XCTAssertEqual(client.matchIndex, 0)
        XCTAssertEqual(client.firstSelectedRange, client.matches[0])
        client.search("SECRET")
        XCTAssertTrue(client.matches.isEmpty)
        client.search("")
        XCTAssertTrue(client.matches.isEmpty)
        XCTAssertNil(client.matchIndex)
    }

    func testTelegramSearchNavigatesAndWrapsWithoutChangingText() {
        let (client, _, document) = finder()
        var scrolls: [CGRect] = []
        let source = text("cat cat cat", view: document, scrollToVisible: { scrolls.append($0) })
        client.update([source])
        client.search("cat")
        XCTAssertEqual(client.matches, [NSRange(location: 0, length: 3), NSRange(location: 4, length: 3), NSRange(location: 8, length: 3)])
        client.navigate(backwards: true)
        XCTAssertEqual(client.matchIndex, 2)
        client.navigate(backwards: false)
        XCTAssertEqual(client.matchIndex, 0)
        client.navigate(backwards: false)
        XCTAssertEqual(client.matchIndex, 1)
        XCTAssertEqual(client.firstSelectedRange, NSRange(location: 4, length: 3))
        XCTAssertEqual(scrolls.count, 4)
        XCTAssertEqual(source.attributedString.string, "cat cat cat")
    }

    func testTelegramSearchRetainsVisibilityBoundariesAfterUpdates() {
        let (client, _, document) = finder()
        client.update([text("secret secret", excludedRanges: [NSRange(location: 0, length: 6)], view: document)])
        client.search("secret")
        XCTAssertEqual(client.matches.count, 1)
        client.update([text("secret secret", view: document)])
        XCTAssertEqual(client.matches.count, 2)
        client.invalidate()
        XCTAssertTrue(client.matches.isEmpty)
        XCTAssertNil(client.matchIndex)
        client.update([text("other", view: document)])
        XCTAssertTrue(client.matches.isEmpty)
    }

    func testTelegramSearchUsesUTF16AndLiteralQueries() {
        let (client, _, document) = finder()
        client.update([text("😀 .*[x] 😀", view: document)])
        client.search("😀")
        XCTAssertEqual(client.matches, [NSRange(location: 0, length: 2), NSRange(location: 9, length: 2)])
        client.search(".*[x]")
        XCTAssertEqual(client.matches, [NSRange(location: 3, length: 5)])
        client.search("x" + String(repeating: "y", count: 100))
        XCTAssertTrue(client.matches.isEmpty)
    }

    func testTelegramHighlightsTrackSelectedMatchAndVisibleGeometry() {
        let (client, _, document) = finder()
        let source = text("cat cat", view: document)
        client.update([source, text("cat", origin: CGPoint(x: 0, y: 2000), view: document)])
        client.search("cat")
        XCTAssertEqual(client.matches.count, 3)
        var highlights = client.highlights()
        XCTAssertEqual(highlights.count, 1)
        XCTAssertEqual(highlights[0].selected, source.rects(for: NSRange(location: 0, length: 3)))
        XCTAssertEqual(highlights[0].rects, source.rects(for: NSRange(location: 4, length: 3)))
        client.navigate(backwards: false)
        highlights = client.highlights()
        XCTAssertEqual(highlights[0].selected, source.rects(for: NSRange(location: 4, length: 3)))
        client.search("")
        XCTAssertTrue(client.highlights().isEmpty)
    }

    func testMissingVirtualizedViewsDoNotProduceVisibleMatches() {
        let (client, _, _) = finder()
        client.update([text("offscreen")])
        XCTAssertEqual(client.visibleCharacterRanges, [])
        XCTAssertEqual(client.rects(forCharacterRange: NSRange(location: 0, length: 9)), [])
    }
}
