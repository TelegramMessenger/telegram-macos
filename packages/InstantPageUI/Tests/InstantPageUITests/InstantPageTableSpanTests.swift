import XCTest
import Postbox
import TelegramCore
import InAppSettings
@testable import InstantPageUI

private func cell(colspan: Int32, rowspan: Int32, text: RichText? = nil) -> InstantPageTableCell {
    return InstantPageTableCell(text: text, header: false, alignment: .left, verticalAlignment: .top, colspan: colspan, rowspan: rowspan)
}

private func row(_ cells: InstantPageTableCell...) -> InstantPageTableRow {
    return InstantPageTableRow(cells: cells)
}

final class InstantPageTableSpanTests: XCTestCase {
    func testClampLeavesOrdinarySpansUntouched() {
        XCTAssertEqual(clampedTableSpan(1, max: 4), 1)
        XCTAssertEqual(clampedTableSpan(2, max: 4), 2)
        XCTAssertEqual(clampedTableSpan(4, max: 4), 4)
    }

    func testClampTreatsUnsetOrNegativeAsOne() {
        XCTAssertEqual(clampedTableSpan(0, max: 4), 1)
        XCTAssertEqual(clampedTableSpan(-1, max: 4), 1)
        XCTAssertEqual(clampedTableSpan(Int32.min, max: 4), 1)
    }

    func testClampCapsAtTheUpperBound() {
        XCTAssertEqual(clampedTableSpan(5, max: 4), 4)
        XCTAssertEqual(clampedTableSpan(2_000_000_000, max: 3), 3)
        XCTAssertEqual(clampedTableSpan(Int32.max, max: 2), 2)
    }

    func testClampNeverReturnsLessThanOneEvenWithEmptyBound() {
        XCTAssertEqual(clampedTableSpan(Int32.max, max: 0), 1)
        XCTAssertEqual(clampedTableSpan(5, max: -3), 1)
    }

    func testColumnCountIsTheWidestRow() {
        let rows = [row(cell(colspan: 1, rowspan: 1)),
                    row(cell(colspan: 1, rowspan: 1), cell(colspan: 1, rowspan: 1), cell(colspan: 1, rowspan: 1))]
        XCTAssertEqual(maxTableColumnCount(rows), 3)
        XCTAssertEqual(maxTableColumnCount([]), 0)
    }

    func testNormalizationBoundsEveryMaliciousSpanToTheTableSize() {
        let rows = [row(cell(colspan: Int32.max, rowspan: Int32.max),
                        cell(colspan: 2_000_000_000, rowspan: 1)),
                    row(cell(colspan: 1, rowspan: 1),
                        cell(colspan: 1, rowspan: 1))]
        let normalized = tableRowsWithClampedSpans(rows)
        let columnBound = maxTableColumnCount(rows)
        let rowBound = rows.count
        for row in normalized {
            for cell in row.cells {
                XCTAssertGreaterThanOrEqual(cell.colspan, 1)
                XCTAssertGreaterThanOrEqual(cell.rowspan, 1)
                XCTAssertLessThanOrEqual(Int(cell.colspan), columnBound)
                XCTAssertLessThanOrEqual(Int(cell.rowspan), rowBound)
            }
        }
        XCTAssertEqual(normalized[0].cells[0].colspan, 2)
        XCTAssertEqual(normalized[0].cells[0].rowspan, 2)
    }

    func testNormalizationKeepsValidTablesIdentical() {
        let rows = [row(cell(colspan: 2, rowspan: 1), cell(colspan: 1, rowspan: 2)),
                    row(cell(colspan: 1, rowspan: 1), cell(colspan: 1, rowspan: 1), cell(colspan: 1, rowspan: 1))]
        let normalized = tableRowsWithClampedSpans(rows)
        XCTAssertEqual(normalized, rows)
    }

    func testLayoutOfAMaliciousTableReturnsPromptlyInsteadOfHanging() {
        let rows = [row(cell(colspan: Int32.max, rowspan: 1), cell(colspan: Int32.max, rowspan: Int32.max)),
                    row(cell(colspan: 2_000_000_000, rowspan: 1), cell(colspan: 2_000_000_000, rowspan: 1))]
        let theme = instantPageThemeForType(.light, settings: InstantViewAppearance.defaultSettings)
        let webpage = TelegramMediaWebpage(webpageId: MediaId(namespace: 0, id: 0), content: .Pending(0, nil))

        let started = Date()
        let item = layoutTableItem(rtl: false, rows: rows, styleStack: InstantPageTextStyleStack(), theme: theme, bordered: true, striped: false, boundingWidth: 320.0, horizontalInset: 17.0, media: [:], webpage: webpage)
        let elapsed = Date().timeIntervalSince(started)

        XCTAssertLessThan(elapsed, 5.0, "laying out a clamped 2x2 table must be near-instant")
        XCTAssertGreaterThan(item.frame.width, 0.0)
    }
    
    private func richMessageLayout(_ rows: [InstantPageTableRow]) -> InstantPageV2Layout {
        let page = InstantPage(blocks: [.table(title: .empty, rows: rows, bordered: true, striped: false, compact: false)], media: [:], isComplete: true, rtl: false, url: "", views: nil)
        let content = TelegramMediaWebpageLoadedContent(url: "", displayUrl: "", hash: 0, type: nil, websiteName: nil, title: nil, text: nil, embedUrl: nil, embedType: nil, embedSize: nil, duration: nil, author: nil, isMediaLargeByDefault: nil, imageIsVideoCover: false, image: nil, file: nil, story: nil, attributes: [], instantPage: page)
        let webpage = TelegramMediaWebpage(webpageId: MediaId(namespace: 0, id: 0), content: .Loaded(content))
        let theme = instantPageThemeForType(.light, settings: InstantViewAppearance.defaultSettings)
        return layoutInstantPageV2(webpage: webpage, instantPage: page, boundingWidth: 320.0, horizontalInset: 17.0, theme: theme)
    }
    
    func testRichMessageTableWithMaliciousSpansReturnsPromptly() {
        let rows = [row(cell(colspan: Int32.max, rowspan: 1, text: .plain("a")), cell(colspan: Int32.max, rowspan: Int32.max, text: .plain("b"))),
                    row(cell(colspan: 2_000_000_000, rowspan: 1, text: .plain("c")), cell(colspan: 1, rowspan: 2_000_000_000, text: .plain("d")))]
        
        let started = Date()
        let layout = richMessageLayout(rows)
        let elapsed = Date().timeIntervalSince(started)
        
        XCTAssertLessThan(elapsed, 5.0, "a clamped 2x2 rich message table must lay out near-instantly")
        let tables = layout.items.compactMap { item -> InstantPageV2TableItem? in
            if case let .table(table) = item {
                return table
            }
            return nil
        }
        XCTAssertEqual(tables.count, 1)
        XCTAssertFalse(tables.first?.cells.isEmpty ?? true)
        XCTAssertLessThan(tables.first?.contentSize.width ?? .infinity, 5_000)
    }
    
    func testRichMessageTableWithValidSpansIsUnchanged() {
        let rows = [row(cell(colspan: 2, rowspan: 1, text: .plain("wide header"))),
                    row(cell(colspan: 1, rowspan: 2, text: .plain("tall")), cell(colspan: 1, rowspan: 1, text: .plain("x"))),
                    row(cell(colspan: 1, rowspan: 1, text: .plain("y")))]
        XCTAssertEqual(tableRowsWithClampedSpans(rows), rows)
        XCTAssertGreaterThan(richMessageLayout(rows).contentSize.height, 0.0)
    }

    private func listMessageLayout(_ items: [InstantPageListItem], ordered: Bool, rtl: Bool) -> InstantPageV2Layout {
        let page = InstantPage(blocks: [.list(items: items, ordered: ordered)], media: [:], isComplete: true, rtl: rtl, url: "", views: nil)
        let content = TelegramMediaWebpageLoadedContent(url: "", displayUrl: "", hash: 0, type: nil, websiteName: nil, title: nil, text: nil, embedUrl: nil, embedType: nil, embedSize: nil, duration: nil, author: nil, isMediaLargeByDefault: nil, imageIsVideoCover: false, image: nil, file: nil, story: nil, attributes: [], instantPage: page)
        let webpage = TelegramMediaWebpage(webpageId: MediaId(namespace: 0, id: 0), content: .Loaded(content))
        let theme = instantPageThemeForType(.light, settings: InstantViewAppearance.defaultSettings)
        return layoutInstantPageV2(webpage: webpage, instantPage: page, boundingWidth: 320.0, horizontalInset: 17.0, theme: theme)
    }

    private func listMarkers(in layout: InstantPageV2Layout) -> [InstantPageV2ListMarkerItem] {
        return layout.items.compactMap { item -> InstantPageV2ListMarkerItem? in
            if case let .listMarker(marker) = item {
                return marker
            }
            return nil
        }
    }

    func testRTLBlockListItemMirrorsMarkersToTheRight() {
        let items: [InstantPageListItem] = [.blocks([.paragraph(.plain("פריט ראשון"))], nil, nil)]
        let markers = listMarkers(in: listMessageLayout(items, ordered: false, rtl: false))

        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers[0].frame.maxX, 303.0, accuracy: 0.5)
    }

    func testRTLTextListItemMirrorsMarkersAndRightAlignsText() {
        let items: [InstantPageListItem] = [.text(.plain("פריט"), nil, nil)]
        let layout = listMessageLayout(items, ordered: false, rtl: false)

        let markers = listMarkers(in: layout)
        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers[0].frame.maxX, 303.0, accuracy: 0.5)

        let textItems = layout.items.compactMap { item -> InstantPageV2TextItem? in
            if case let .text(text) = item {
                return text
            }
            return nil
        }
        XCTAssertEqual(textItems.count, 1)
        XCTAssertGreaterThanOrEqual(textItems[0].frame.maxX, 260.0)
    }

    func testMessageLevelRTLMirrorsListMarkersForLTRText() {
        let items: [InstantPageListItem] = [.text(.plain("First"), nil, nil)]
        let markers = listMarkers(in: listMessageLayout(items, ordered: false, rtl: true))

        XCTAssertEqual(markers.count, 1)
        XCTAssertEqual(markers[0].frame.maxX, 303.0, accuracy: 0.5)
    }

    func testLTRListKeepsMarkersOnTheLeft() {
        let items: [InstantPageListItem] = [.blocks([.paragraph(.plain("First item"))], nil, nil)]
        let layout = listMessageLayout(items, ordered: false, rtl: false)

        let markers = listMarkers(in: layout)
        XCTAssertEqual(markers.count, 1)
        XCTAssertGreaterThanOrEqual(markers[0].frame.minX, 17.0)
        XCTAssertLessThanOrEqual(markers[0].frame.minX, 39.0)

        let textItems = layout.items.compactMap { item -> InstantPageV2TextItem? in
            if case let .text(text) = item {
                return text
            }
            return nil
        }
        XCTAssertEqual(textItems.count, 1)
        XCTAssertEqual(textItems[0].frame.minX, 47.0, accuracy: 0.5)
    }
}
