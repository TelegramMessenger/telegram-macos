import AppKit
import XCTest
@testable import TGUIKit

private final class SizedItem: TableRowItem {
    private let rowHeight: CGFloat
    private let anchor: ((TableRowItem) -> TableRowResizeAnchor?)?

    init(id: Int, height: CGFloat, anchor: ((TableRowItem) -> TableRowResizeAnchor?)? = nil) {
        self.rowHeight = height
        self.anchor = anchor
        super.init(.zero, stableId: id)
    }

    override var height: CGFloat {
        return rowHeight
    }

    override func resizeAnchor(previous: TableRowItem) -> TableRowResizeAnchor? {
        return anchor?(previous)
    }
}

final class TableRowResizeAnchorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    private let viewport: CGFloat = 400

    private func withChat(count: Int = 40, rowHeight: CGFloat = 60, _ body: (TableView, NSWindow) throws -> Void) rethrows {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: viewport), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let table = TableView(frame: window.contentView!.bounds, isFlipped: false)
        window.contentView!.addSubview(table)
        for id in 0 ..< count {
            _ = table.addItem(item: SizedItem(id: id, height: rowHeight))
        }
        table.layoutSubtreeIfNeeded()
        try body(table, window)
        table.clipView.updateBounds(to: table.clipView.bounds.origin, cancel: true)
    }

    private func offset(_ table: TableView) -> CGFloat {
        return table.clipView.destination?.y ?? table.clipView.bounds.minY
    }

    private func screenTop(_ table: TableView, _ id: Int) -> CGFloat {
        let rect = table.rectOf(item: table.item(stableId: AnyHashable(id))!)
        return rect.maxY - offset(table)
    }

    private func screenBottom(_ table: TableView, _ id: Int) -> CGFloat {
        let rect = table.rectOf(item: table.item(stableId: AnyHashable(id))!)
        return rect.minY - offset(table)
    }

    private func resize(_ table: TableView, id: Int, to height: CGFloat, animated: Bool = false, inserted: [(Int, TableRowItem)] = [], anchor: @escaping (TableRowItem) -> TableRowResizeAnchor?) {
        let index = table.item(stableId: AnyHashable(id))!.index + inserted.count
        let item = SizedItem(id: id, height: height, anchor: anchor)
        table.merge(with: TableUpdateTransition(deleted: [], inserted: inserted, updated: [(index, item)], animated: animated))
    }

    private func scroll(_ table: TableView, to y: CGFloat) {
        table.clipView.updateBounds(to: NSMakePoint(0, y))
        table.layoutSubtreeIfNeeded()
    }

    func testChatBottomUsesDocumentOrientation() {
        withChat { table, _ in
            scroll(table, to: 0)
            XCTAssertTrue(table.isFlipped)
            XCTAssertFalse(table.documentView!.isFlipped)
            XCTAssertTrue(table.isAtBottom)
            scroll(table, to: 60)
            XCTAssertFalse(table.isAtBottom)
        }
    }

    func testReactionAtBottomKeepsLatestMessageInPlace() {
        withChat { table, _ in
            scroll(table, to: 0)
            let latestBottom = screenBottom(table, 0)
            for height: CGFloat in [100, 60, 120, 60] {
                let sticksToBottom = table.isAtBottom
                resize(table, id: 1, to: height, animated: true) { previous in
                    sticksToBottom ? .bottom(oldHeight: previous.height, newHeight: height) : .top
                }
                XCTAssertEqual(offset(table), 0, accuracy: 0.5)
                XCTAssertEqual(screenBottom(table, 0), latestBottom, accuracy: 0.5)
            }
        }
    }

    func testReactionWhileReadingOlderMessagesKeepsMessageTop() {
        withChat { table, _ in
            scroll(table, to: 600)
            let top = screenTop(table, 12)
            let sticksToBottom = table.isAtBottom
            resize(table, id: 12, to: 100, animated: true) { previous in
                sticksToBottom ? .bottom(oldHeight: previous.height, newHeight: 100) : .top
            }
            XCTAssertEqual(screenTop(table, 12), top, accuracy: 0.5)
            XCTAssertFalse(table.isAtBottom)
        }
    }

    func testFlippedDocumentBottomIsItsMaximumOffset() {
        withChat { table, _ in
            table.setIsFlipped(true)
            scroll(table, to: 0)
            XCTAssertFalse(table.isAtBottom)
            scroll(table, to: table.documentSize.height - table.clipView.bounds.height)
            XCTAssertTrue(table.isAtBottom)
        }
    }

    func testBottomCheckFollowsAnimatedScrollDestination() {
        withChat { table, _ in
            scroll(table, to: 0)
            table.clipView.scroll(to: NSMakePoint(0, 300), animated: true)
            XCTAssertFalse(table.isAtBottom)
            table.clipView.updateBounds(to: NSMakePoint(0, 300), cancel: true)
            table.clipView.scroll(to: .zero, animated: true)
            XCTAssertTrue(table.isAtBottom)
        }
    }

    func testShortHistoryIsAlreadyAtBottomInEitherOrientation() {
        withChat(count: 2) { table, _ in
            scroll(table, to: 0)
            XCTAssertTrue(table.isAtBottom)
            table.setIsFlipped(true)
            scroll(table, to: 0)
            XCTAssertTrue(table.isAtBottom)
        }
    }

    func testTopAnchorKeepsRowTopWhenGrowing() {
        withChat { table, _ in
            scroll(table, to: 600)
            let top = screenTop(table, 12)
            resize(table, id: 12, to: 260) { _ in .top }
            XCTAssertEqual(screenTop(table, 12), top, accuracy: 0.5)
            XCTAssertEqual(screenBottom(table, 12), top - 260, accuracy: 0.5)
        }
    }

    func testTopAnchorKeepsRowTopWhenShrinking() {
        withChat { table, _ in
            _ = table.merge(with: TableUpdateTransition(deleted: [], inserted: [], updated: [(12, SizedItem(id: 12, height: 260))]))
            scroll(table, to: 700)
            let top = screenTop(table, 12)
            resize(table, id: 12, to: 60) { _ in .top }
            XCTAssertEqual(screenTop(table, 12), top, accuracy: 0.5)
        }
    }

    func testBottomAnchorKeepsRowBottom() {
        withChat { table, _ in
            scroll(table, to: 600)
            let bottom = screenBottom(table, 12)
            resize(table, id: 12, to: 260) { previous in .bottom(oldHeight: previous.height, newHeight: 260) }
            XCTAssertEqual(screenBottom(table, 12), bottom, accuracy: 0.5)
        }
    }

    func testPointAnchorKeepsClickedPoint() {
        withChat { table, _ in
            scroll(table, to: 600)
            let top = screenTop(table, 12)
            resize(table, id: 12, to: 260) { _ in TableRowResizeAnchor(from: 40, to: 140) }
            XCTAssertEqual(screenTop(table, 12) - 140, top - 40, accuracy: 0.5)
        }
    }

    func testRowBelowViewportKeepsVisibleRowsStill() {
        withChat { table, _ in
            scroll(table, to: 900)
            let reference = screenTop(table, 20)
            resize(table, id: 3, to: 300) { _ in .bottom(oldHeight: 60, newHeight: 300) }
            XCTAssertEqual(screenTop(table, 20), reference, accuracy: 0.5)
        }
    }

    func testRowAboveViewportKeepsVisibleRowsStill() {
        withChat { table, _ in
            scroll(table, to: 300)
            let reference = screenTop(table, 7)
            resize(table, id: 30, to: 300) { _ in .top }
            XCTAssertEqual(screenTop(table, 7), reference, accuracy: 0.5)
        }
    }

    func testTopAnchorClampsAtChatBottom() {
        withChat { table, _ in
            _ = table.merge(with: TableUpdateTransition(deleted: [], inserted: [], updated: [(0, SizedItem(id: 0, height: 260))]))
            scroll(table, to: 0)
            resize(table, id: 0, to: 60) { _ in .top }
            XCTAssertEqual(offset(table), 0, accuracy: 0.5)
            XCTAssertEqual(screenBottom(table, 0), 0, accuracy: 0.5)
        }
    }

    func testTopAnchorAtChatBottomScrollsToKeepTop() {
        withChat { table, _ in
            scroll(table, to: 0)
            let top = screenTop(table, 1)
            resize(table, id: 1, to: 300) { _ in .top }
            XCTAssertEqual(screenTop(table, 1), top, accuracy: 0.5)
        }
    }

    func testAnchorSurvivesInsertedRowsInSameMerge() {
        withChat { table, _ in
            scroll(table, to: 600)
            let top = screenTop(table, 12)
            resize(table, id: 12, to: 260, inserted: [(0, SizedItem(id: 100, height: 80))]) { _ in .top }
            XCTAssertEqual(screenTop(table, 12), top, accuracy: 0.5)
        }
    }

    func testAnimatedResizeTargetsAnchoredOffset() {
        withChat { table, window in
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            scroll(table, to: 600)
            let top = screenTop(table, 12)
            resize(table, id: 12, to: 260, animated: true) { _ in .top }
            XCTAssertEqual(screenTop(table, 12), top, accuracy: 0.5)
        }
    }

    func testRowWithoutAnchorKeepsExistingBehaviour() {
        withChat { table, _ in
            scroll(table, to: 600)
            let before = offset(table)
            _ = table.merge(with: TableUpdateTransition(deleted: [], inserted: [], updated: [(12, SizedItem(id: 12, height: 260))], animated: true))
            XCTAssertEqual(offset(table), before, accuracy: 0.5)
        }
    }

    func testLiveScrollResizeKeepsTheRowStillWithoutAnimatingIt() {
        withChat { table, window in
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            scroll(table, to: 600)
            table.scrollWillStartLiveScrolling()
            defer { table.scrollDidEndLiveScrolling() }
            let top = screenTop(table, 12)
            resize(table, id: 12, to: 260, animated: true) { _ in .top }
            XCTAssertEqual(screenTop(table, 12), top, accuracy: 0.5)
            let view = table.item(stableId: AnyHashable(12))?.view
            XCTAssertNotNil(view?.layer)
            XCTAssertNil(view?.layer?.animation(forKey: "tableRowResize.bounds"))
            XCTAssertNil(view?.layer?.animation(forKey: "tableRowResize.position"))
            scroll(table, to: offset(table) + 40)
            XCTAssertEqual(screenTop(table, 12), top - 40, accuracy: 0.5)
        }
    }

    func testSaveVisibleResizeKeepsTheMessageStillDuringLiveScroll() {
        withChat { table, window in
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            scroll(table, to: 600)
            table.scrollWillStartLiveScrolling()
            defer { table.scrollDidEndLiveScrolling() }
            let top = screenTop(table, 12)
            let item = SizedItem(id: 12, height: 260, anchor: { _ in .top })
            table.merge(with: TableUpdateTransition(deleted: [], inserted: [], updated: [(12, item)], animated: false, state: .saveVisible(.upper, false)))
            XCTAssertEqual(screenTop(table, 12), top, accuracy: 0.5)
        }
    }

    func testOffsetMath() {
        let old = CGRect(x: 0, y: 100, width: 10, height: 50)
        let grown = CGRect(x: 0, y: 100, width: 10, height: 150)
        XCTAssertEqual(TableRowResizeAnchor.offset(anchor: .top, oldRect: old, newRect: grown, offset: 0, viewport: 400, flipped: false, range: 0 ... 1000), 100)
        XCTAssertEqual(TableRowResizeAnchor.offset(anchor: .bottom(oldHeight: 50, newHeight: 150), oldRect: old, newRect: grown, offset: 0, viewport: 400, flipped: false, range: 0 ... 1000), 0)
        XCTAssertEqual(TableRowResizeAnchor.offset(anchor: .top, oldRect: old, newRect: grown, offset: 0, viewport: 400, flipped: false, range: 0 ... 40), 40)
        let flippedGrown = CGRect(x: 0, y: 100, width: 10, height: 150)
        XCTAssertEqual(TableRowResizeAnchor.offset(anchor: .bottom(oldHeight: 50, newHeight: 150), oldRect: old, newRect: flippedGrown, offset: 0, viewport: 400, flipped: true, range: 0 ... 1000), 100)
    }

    func testResolveClickInUpperHalfKeepsClickPoint() {
        let anchor = TableRowResizeAnchor.resolve(oldHeight: 200, newHeight: 380, click: 50, sticksToBottom: true)
        XCTAssertEqual(anchor, TableRowResizeAnchor(from: 50, to: 50))
    }

    func testResolveClickInLowerHalfKeepsBottomDistance() {
        let anchor = TableRowResizeAnchor.resolve(oldHeight: 200, newHeight: 120, click: 170, sticksToBottom: false)
        XCTAssertEqual(anchor, TableRowResizeAnchor(from: 170, to: 90))
    }

    func testResolveUnchangedRegionsOverrideHalfRule() {
        XCTAssertEqual(TableRowResizeAnchor.resolve(oldHeight: 200, newHeight: 400, click: 170, unchangedTop: 180, sticksToBottom: false), TableRowResizeAnchor(from: 170, to: 170))
        XCTAssertEqual(TableRowResizeAnchor.resolve(oldHeight: 200, newHeight: 400, click: 30, unchangedBottom: 180, sticksToBottom: false), TableRowResizeAnchor(from: 30, to: 230))
    }

    func testResolveWithoutClickFollowsChatPosition() {
        XCTAssertEqual(TableRowResizeAnchor.resolve(oldHeight: 200, newHeight: 300, click: nil, sticksToBottom: true), .bottom(oldHeight: 200, newHeight: 300))
        XCTAssertEqual(TableRowResizeAnchor.resolve(oldHeight: 200, newHeight: 300, click: nil, sticksToBottom: false), .top)
    }

    func testResolveWithoutClickKeepsLargerUnchangedSide() {
        XCTAssertEqual(TableRowResizeAnchor.resolve(oldHeight: 200, newHeight: 300, click: nil, unchangedTop: 20, unchangedBottom: 150, sticksToBottom: false), .bottom(oldHeight: 200, newHeight: 300))
        XCTAssertEqual(TableRowResizeAnchor.resolve(oldHeight: 200, newHeight: 300, click: nil, unchangedTop: 150, unchangedBottom: 20, sticksToBottom: false), .top)
    }

    func testResolveClampsClickIntoRow() {
        let anchor = TableRowResizeAnchor.resolve(oldHeight: 200, newHeight: 100, click: -20, sticksToBottom: false)
        XCTAssertEqual(anchor, TableRowResizeAnchor(from: 0, to: 0))
        let below = TableRowResizeAnchor.resolve(oldHeight: 200, newHeight: 50, click: 260, sticksToBottom: false)
        XCTAssertEqual(below, TableRowResizeAnchor(from: 200, to: 50))
    }

    func testPartiallyVisibleRowAtTopEdgeKeepsAnchor() {
        withChat { table, _ in
            scroll(table, to: 600)
            let rect = table.rectOf(item: table.item(stableId: AnyHashable(16))!)
            let visibleTop = offset(table) + viewport
            XCTAssertTrue(rect.minY < visibleTop && rect.maxY > visibleTop)
            let bottom = screenBottom(table, 16)
            resize(table, id: 16, to: 300) { _ in .bottom(oldHeight: 60, newHeight: 300) }
            XCTAssertEqual(screenBottom(table, 16), bottom, accuracy: 0.5)
        }
    }

    func testRepeatedResizeUsesLatestAnchor() {
        withChat { table, window in
            window.orderFront(nil)
            defer { window.orderOut(nil) }
            scroll(table, to: 600)
            let top = screenTop(table, 12)
            resize(table, id: 12, to: 260, animated: true) { _ in .top }
            resize(table, id: 12, to: 120, animated: true) { _ in .top }
            XCTAssertEqual(screenTop(table, 12), top, accuracy: 0.5)
        }
    }

    func testInterfaceMergeWithInsertsLeavesScrollToInterface() {
        withChat { table, _ in
            scroll(table, to: 600)
            var asked = false
            let item = SizedItem(id: 12, height: 260, anchor: { _ in
                asked = true
                return .top
            })
            let index = table.item(stableId: AnyHashable(12))!.index + 1
            table.merge(with: TableUpdateTransition(deleted: [], inserted: [(0, SizedItem(id: 100, height: 80))], updated: [(index, item)], animated: true, state: .none(TableAnimationInterface(true, true, { _ in }))))
            XCTAssertFalse(asked)
        }
    }

    func testPacingAnimatesSingleJumps() {
        var pacing = TableRowResizePacing()
        XCTAssertTrue(pacing.animates(delta: 200, allowed: true, now: 10))
        XCTAssertTrue(pacing.animates(delta: 200, allowed: true, now: 20))
    }

    func testPacingFollowsContinuousStepsImmediately() {
        var pacing = TableRowResizePacing()
        XCTAssertFalse(pacing.animates(delta: 5, allowed: true, now: 10))
        XCTAssertFalse(pacing.animates(delta: 40, allowed: true, now: 10.008))
        XCTAssertFalse(pacing.animates(delta: 6, allowed: true, now: 10.016))
    }

    func testPacingKeepsAnimatingWhileResizeIsInFlight() {
        var pacing = TableRowResizePacing()
        XCTAssertTrue(pacing.animates(delta: 200, allowed: true, now: 10))
        XCTAssertTrue(pacing.animates(delta: 3, allowed: true, now: 10.15))
        XCTAssertFalse(pacing.animates(delta: 3, allowed: true, now: 10.2))
        XCTAssertFalse(pacing.animates(delta: 3, allowed: true, now: 10.6))
        XCTAssertFalse(pacing.animates(delta: 300, allowed: false, now: 20))
    }

    func testPointerSnapsToExactEdgesWithinRounding() {
        XCTAssertEqual(TableRowResizeAnchor.pointer(from: 90, to: 95.6, oldHeight: 120, newHeight: 126), TableRowResizeAnchor(from: 90, to: 96))
        XCTAssertEqual(TableRowResizeAnchor.pointer(from: 90, to: 90.4, oldHeight: 120, newHeight: 126), TableRowResizeAnchor(from: 90, to: 90))
        XCTAssertEqual(TableRowResizeAnchor.pointer(from: 90, to: 150, oldHeight: 120, newHeight: 320), TableRowResizeAnchor(from: 90, to: 150))
    }
}
