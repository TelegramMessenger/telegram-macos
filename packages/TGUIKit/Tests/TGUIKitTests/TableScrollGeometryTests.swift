import AppKit
import XCTest
@testable import TGUIKit

private final class ScrollGeometryTableSpy: TGFlipableTableView {
    var rangeQueries = 0
    override func rows(in rect: NSRect) -> NSRange {
        rangeQueries += 1
        return NSRange(location: 0, length: 0)
    }
}

private final class ScrollGeometryHeader: TableStickItem {}
private final class ScrollGeometrySecondaryHeader: TableStickItem {}

private final class BottomInsetGeometryRow: TableRowItem {
    override var height: CGFloat {
        return 60
    }
}

final class TableScrollGeometryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    func testAbsentStickyHeadersDoNotQueryRows() {
        let table = TableView(frame: NSRect(x: 0, y: 0, width: 320, height: 400))
        let spy = ScrollGeometryTableSpy(frame: table.bounds)
        table.tableView = spy
        for _ in 0..<20 { table.updateStickAfterScroll(false) }
        XCTAssertEqual(spy.rangeQueries, 0)
        table.set(stickClass: ScrollGeometryHeader.self, handler: { _ in })
        spy.rangeQueries = 0
        table.updateStickAfterScroll(false)
        XCTAssertEqual(spy.rangeQueries, 1)
        table.setSecondary(stickClass: ScrollGeometrySecondaryHeader.self, handler: { _ in })
        spy.rangeQueries = 0
        table.updateStickAfterScroll(false)
        XCTAssertEqual(spy.rangeQueries, 2)
        table.set(stickClass: nil, handler: { _ in })
        spy.rangeQueries = 0
        table.updateStickAfterScroll(false)
        XCTAssertEqual(spy.rangeQueries, 1)
        table.setSecondary(stickClass: nil, handler: { _ in })
        spy.rangeQueries = 0
        table.updateStickAfterScroll(false)
        XCTAssertEqual(spy.rangeQueries, 0)
    }

    func testBottomAlignedRowsClearTheContentInsetWithoutShrinkingTheViewport() {
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 320, 400), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let table = TableView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(table)
        for index in 0 ..< 20 {
            _ = table.addItem(item: BottomInsetGeometryRow(table.bounds.size, stableId: index))
        }
        for inset in [CGFloat(0), 56, 0] {
            table.contentInsets.bottom = inset
            table.layoutSubtreeIfNeeded()
            let states: [TableScrollState] = [.bottom(id: 19, innerId: nil, animated: false, focus: .init(focus: false), inset: 0), .down(false)]
            for state in states {
                table.contentView.scroll(to: NSMakePoint(0, table.documentSize.height - table.frame.height))
                table.layoutSubtreeIfNeeded()
                table.scroll(to: state, toVisible: true)
                table.layoutSubtreeIfNeeded()
                let row = table.rectOf(item: table.item(at: 19))
                let frame = table.convert(row, from: table.view)
                XCTAssertEqual(table.frame.height, 400)
                XCTAssertEqual(frame.maxY, 400 - inset, accuracy: 0.5)
            }
        }
    }

    func testVisibleRangesMatchOriginalFormulaAcrossInsetsResizeAndRemoval() {
        for flipped in [false, true] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let table = TableView(frame: window.contentView!.bounds, isFlipped: flipped)
            window.contentView!.addSubview(table)
            for index in 0..<60 { _ = table.addItem(item: TableRowItem(.zero, stableId: index)) }
            for height in [CGFloat(400), 200] {
                table.setFrameSize(NSSize(width: 320, height: height))
                for top in [CGFloat(0), 30] {
                    table.contentInsets.top = top
                    for offset in [CGFloat(0), 1, 59, 500, 3000] {
                        table.contentView.scroll(to: NSPoint(x: 0, y: offset))
                        table.layoutSubtreeIfNeeded()
                        for inset in [CGFloat(0), 20, -10] {
                            var rect = NSRect(x: 0, y: table.documentOffset.y, width: table.tableView.realVisibleRect.width, height: table.tableView.realVisibleRect.height).insetBy(dx: 0, dy: -inset)
                            if inset == 0, top > 0 { rect.size.height -= top }
                            XCTAssertEqual(table.visibleRows(inset), table.tableView.rows(in: rect))
                        }
                    }
                }
            }
            table.removeAll()
            XCTAssertEqual(table.visibleRows().length, 0)
            window.close()
        }
    }

    func testCoalescedScrollDeliversFinalPositionAndCallbacksCanChangeRows() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 400), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let table = TableView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(table)
        for index in 0..<60 { _ = table.addItem(item: TableRowItem(.zero, stableId: index)) }
        table.layoutSubtreeIfNeeded()
        var seen: [NSRange] = []
        table.addScroll(listener: TableScrollListener(dispatchWhenVisibleRangeUpdated: false) { position in
            seen.append(position.visibleRows)
        })
        table.needUpdateVisibleAfterScroll = true
        for offset in [100, 200, 900] { table.contentView.scroll(to: NSPoint(x: 0, y: offset)) }
        let delivered = expectation(description: "Final scroll delivery")
        DispatchQueue.main.async { delivered.fulfill() }
        wait(for: [delivered], timeout: 2)
        XCTAssertFalse(seen.isEmpty)
        XCTAssertEqual(seen.last, table.visibleRows())
        table.addScroll(listener: TableScrollListener { _ in table.removeAll() })
        table.contentView.scroll(to: NSPoint(x: 0, y: 1200))
        let removed = expectation(description: "Mutation during delivery")
        DispatchQueue.main.async { removed.fulfill() }
        wait(for: [removed], timeout: 2)
        XCTAssertEqual(table.count, 0)
    }
}
