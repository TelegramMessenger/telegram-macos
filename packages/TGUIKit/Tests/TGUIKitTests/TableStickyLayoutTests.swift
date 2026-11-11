import AppKit
import XCTest
@testable import TGUIKit

private final class LayoutStickView: TableStickView {
    var pillVisible = true
    var layoutSize: NSSize = .zero

    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        layoutSize = size
    }

    override func updateIsVisible(_ visible: Bool, animated: Bool) {
        pillVisible = visible
    }
}

private final class LayoutAnimationLayer: CALayer {
    var positionAnimations = 0

    override func add(_ animation: CAAnimation, forKey key: String?) {
        if key == "position" {
            positionAnimations += 1
        }
        super.add(animation, forKey: key)
    }
}

private final class LayoutPrimaryHeader: TableStickItem {
    override func viewClass() -> AnyClass {
        return LayoutStickView.self
    }
}

private final class LayoutSecondaryHeader: TableStickItem {
    override func viewClass() -> AnyClass {
        return LayoutStickView.self
    }
}

private final class LayoutScanCounts {
    var primary = 0
    var secondary = 0
}

private final class LayoutCountedItem: TableRowItem {
    let counts: LayoutScanCounts
    init(id: Int, counts: LayoutScanCounts) {
        self.counts = counts
        super.init(.zero, stableId: id)
    }
    override func isKind(of aClass: AnyClass) -> Bool {
        if ObjectIdentifier(aClass) == ObjectIdentifier(LayoutPrimaryHeader.self) { counts.primary += 1 }
        if ObjectIdentifier(aClass) == ObjectIdentifier(LayoutSecondaryHeader.self) { counts.secondary += 1 }
        return super.isKind(of: aClass)
    }
}

final class TableStickyLayoutTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    private func makeTable() -> (TableView, LayoutScanCounts) {
        let table = TableView(frame: NSRect(x: 0, y: 0, width: 320, height: 240))
        let counts = LayoutScanCounts()
        for id in 0..<40 {
            if id % 10 == 0 { _ = table.addItem(item: LayoutPrimaryHeader(.zero)) }
            else if id % 10 == 5 { _ = table.addItem(item: LayoutSecondaryHeader(.zero)) }
            else { _ = table.addItem(item: LayoutCountedItem(id: id, counts: counts)) }
        }
        table.set(stickClass: LayoutPrimaryHeader.self, handler: { _ in })
        table.setSecondary(stickClass: LayoutSecondaryHeader.self, handler: { _ in })
        table.updateStickAfterScroll(false)
        XCTAssertGreaterThan(counts.primary, 0)
        XCTAssertGreaterThan(counts.secondary, 0)
        counts.primary = 0
        counts.secondary = 0
        return (table, counts)
    }

    func testRepeatedLayoutDoesNotRescanUnchangedHeaderIndexes() {
        let (table, counts) = makeTable()
        for _ in 0..<20 {
            table.layout()
            table.updateStickAfterScroll(false)
        }
        XCTAssertEqual(table.count, 40)
        XCTAssertEqual(counts.primary, 0)
        XCTAssertEqual(counts.secondary, 0)
    }

    func testResizingRelayoutsBothStickyOverlaysWithoutScrolling() {
        let (table, _) = makeTable()
        for size in [NSSize(width: 900, height: 600), NSSize(width: 1200, height: 800), NSSize(width: 480, height: 500)] {
            table.setFrameSize(size)
            table.layout()
            let overlays = table.subviews.compactMap { $0 as? LayoutStickView }
            XCTAssertFalse(overlays.isEmpty)
            XCTAssertTrue(overlays.contains { $0.item is LayoutPrimaryHeader })
            XCTAssertTrue(overlays.contains { $0.item is LayoutSecondaryHeader })
            for overlay in overlays {
                XCTAssertEqual(overlay.frame.width, size.width)
                XCTAssertEqual(overlay.layoutSize, overlay.frame.size)
            }
        }
    }

    func testRealInsertionAndRemovalStillInvalidateBothIndexes() {
        let (table, counts) = makeTable()
        _ = table.insert(item: LayoutPrimaryHeader(.zero), at: 0)
        table.layout()
        table.updateStickAfterScroll(false)
        XCTAssertGreaterThan(counts.primary, 0)
        XCTAssertGreaterThan(counts.secondary, 0)
        counts.primary = 0
        counts.secondary = 0
        table.remove(at: 0)
        table.layout()
        table.updateStickAfterScroll(false)
        XCTAssertGreaterThan(counts.primary, 0)
        XCTAssertGreaterThan(counts.secondary, 0)
        counts.primary = 0
        counts.secondary = 0
        table.layout()
        table.updateStickAfterScroll(false)
        XCTAssertEqual(counts.primary, 0)
        XCTAssertEqual(counts.secondary, 0)
    }

    func testHeaderClassChangesStillRefreshTheMatchingIndex() {
        let (table, counts) = makeTable()
        table.set(stickClass: LayoutSecondaryHeader.self, handler: { _ in })
        table.updateStickAfterScroll(false)
        XCTAssertGreaterThan(counts.secondary, 0)
        counts.primary = 0
        counts.secondary = 0
        table.setSecondary(stickClass: LayoutPrimaryHeader.self, handler: { _ in })
        table.updateStickAfterScroll(false)
        XCTAssertGreaterThan(counts.primary, 0)
        counts.primary = 0
        counts.secondary = 0
        table.layout()
        table.updateStickAfterScroll(false)
        XCTAssertEqual(counts.primary, 0)
        XCTAssertEqual(counts.secondary, 0)
    }

    func testPinnedOrderAndInlineOwnershipInBothCoordinateDirections() {
        for flipped in [false, true] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let table = TableView(frame: window.contentView!.bounds, isFlipped: flipped)
            window.contentView!.addSubview(table)
            let date = LayoutPrimaryHeader(.zero)
            let topic = LayoutSecondaryHeader(.zero)
            let chronological: [TableRowItem] = [date, topic] + (0 ..< 40).map { TableRowItem(.zero, stableId: $0) }
            for item in flipped ? chronological : chronological.reversed() {
                _ = table.addItem(item: item)
            }
            table.set(stickClass: LayoutPrimaryHeader.self, handler: { _ in })
            table.setSecondary(stickClass: LayoutSecondaryHeader.self, handler: { _ in })
            table.updateStickInset(10, animated: false)
            table.layoutSubtreeIfNeeded()
            var inlineChecks = 0
            for offset in [CGFloat(0), 0.25, 1, 29.75, 30, 200, 200.25, 201, 200.25, 200] {
                let documentY = flipped ? offset : table.documentSize.height - table.frame.height - offset
                table.contentView.scroll(to: NSPoint(x: 0, y: documentY))
                table.updateStickAfterScroll(false)
                let overlays = table.subviews.compactMap { $0 as? LayoutStickView }
                XCTAssertEqual(overlays.count, 2)
                let dateView = overlays.first(where: { $0.item === date })
                let topicView = overlays.first(where: { $0.item === topic })
                XCTAssertEqual(dateView?.frame.minY, 10)
                XCTAssertEqual(topicView?.frame.minY, 10 + date.heightValue)
                XCTAssertNil(dateView?.layer?.animation(forKey: "position"))
                XCTAssertNil(topicView?.layer?.animation(forKey: "position"))
                for item in [date, topic] {
                    let rect = table.convert(table.rectOf(item: item), from: table.tableView)
                    if rect.intersects(table.bounds) {
                        let inline = table.viewNecessary(at: item.index, makeIfNecessary: true) as? LayoutStickView
                        XCTAssertNotNil(inline)
                        XCTAssertEqual(inline?.pillVisible, false)
                        inlineChecks += 1
                    }
                }
                table.enumerateExistingItemViews { item, view in
                    if item === date || item === topic {
                        XCTAssertFalse((view as! LayoutStickView).pillVisible)
                    }
                }
            }
            XCTAssertGreaterThan(inlineChecks, 0)
            table.removeAll()
            table.updateStickAfterScroll(false)
            XCTAssertTrue(table.subviews.compactMap { $0 as? LayoutStickView }.isEmpty)
        }
    }

    func testDateHandoffStartsOneSpringAndSubsequentScrollKeepsIt() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let table = TableView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(table)
        let firstDate = LayoutPrimaryHeader(.zero)
        let topic = LayoutSecondaryHeader(.zero)
        let nextDate = LayoutPrimaryHeader(.zero)
        _ = table.addItem(item: firstDate)
        _ = table.addItem(item: topic)
        for id in 0 ..< 20 {
            _ = table.addItem(item: TableRowItem(.zero, stableId: id))
        }
        _ = table.addItem(item: nextDate)
        for id in 20 ..< 40 {
            _ = table.addItem(item: TableRowItem(.zero, stableId: id))
        }
        table.set(stickClass: LayoutPrimaryHeader.self, handler: { _ in })
        table.setSecondary(stickClass: LayoutSecondaryHeader.self, handler: { _ in })
        table.updateStickInset(10, animated: false)
        table.layoutSubtreeIfNeeded()
        let nextDateY = table.rectOf(item: nextDate).minY
        table.contentView.scroll(to: NSPoint(x: 0, y: nextDateY - 71))
        table.updateStickAfterScroll(false)
        let topicView = table.subviews.compactMap { $0 as? LayoutStickView }.first(where: { $0.item === topic })
        XCTAssertNotNil(topicView)
        let layer = LayoutAnimationLayer()
        topicView?.layer = layer
        XCTAssertNil(topicView?.layer?.animation(forKey: "position"))
        table.contentView.scroll(to: NSPoint(x: 0, y: nextDateY - 69))
        table.updateStickAfterScroll(false)
        let handoff = topicView?.layer?.animation(forKey: "position")
        XCTAssertNotNil(handoff)
        if let handoff {
            XCTAssertEqual(handoff.duration / Double(handoff.speed), 0.35, accuracy: 0.0001)
        }
        XCTAssertEqual(layer.positionAnimations, 1)
        table.contentView.scroll(to: NSPoint(x: 0, y: nextDateY - 68.5))
        table.updateStickAfterScroll(false)
        XCTAssertEqual(layer.positionAnimations, 1)
        XCTAssertEqual(topicView?.frame.minY, 98.5)
    }

    func testPushedDateRemainsWholeAbovePinningInsetUntilItLeavesViewport() {
        for flipped in [false, true] {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let table = TableView(frame: window.contentView!.bounds, isFlipped: flipped)
            window.contentView!.addSubview(table)
            let outgoing = LayoutPrimaryHeader(.zero)
            let incoming = LayoutPrimaryHeader(.zero)
            let topic = LayoutSecondaryHeader(.zero)
            let chronological: [TableRowItem] = [outgoing, topic] + (0 ..< 20).map { TableRowItem(.zero, stableId: $0) } + [incoming] + (20 ..< 40).map { TableRowItem(.zero, stableId: $0) }
            for item in flipped ? chronological : chronological.reversed() {
                _ = table.addItem(item: item)
            }
            table.set(stickClass: LayoutPrimaryHeader.self, handler: { _ in })
            table.setSecondary(stickClass: LayoutSecondaryHeader.self, handler: { _ in })
            table.updateStickInset(90, animated: false)
            table.layoutSubtreeIfNeeded()
            let incomingRect = table.rectOf(item: incoming)
            for boundary in stride(from: CGFloat(110), through: 5, by: -0.25) {
                let offset = flipped ? incomingRect.minY - boundary : incomingRect.maxY - table.frame.height + boundary
                table.contentView.scroll(to: NSPoint(x: 0, y: offset))
                table.updateStickAfterScroll(false)
                let overlays = table.subviews.compactMap { $0 as? LayoutStickView }
                let outgoingView = overlays.first(where: { $0.item === outgoing })
                XCTAssertNotNil(outgoingView)
                XCTAssertEqual(outgoingView?.frame.minY, boundary - outgoing.heightValue)
                XCTAssertEqual(outgoingView?.frame.height, outgoing.heightValue)
                for overlay in overlays {
                    XCTAssertNil(overlay.layer?.mask)
                }
            }
        }
    }

    func testOneHeaderViewSurvivesNaturalToPinnedHandoffAndReverse() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 240), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let table = TableView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(table)
        for id in 0 ..< 2 {
            _ = table.addItem(item: TableRowItem(.zero, stableId: id))
        }
        let date = LayoutPrimaryHeader(.zero)
        let topic = LayoutSecondaryHeader(.zero)
        _ = table.addItem(item: date)
        _ = table.addItem(item: topic)
        for id in 2 ..< 40 {
            _ = table.addItem(item: TableRowItem(.zero, stableId: id))
        }
        table.set(stickClass: LayoutPrimaryHeader.self, handler: { _ in })
        table.setSecondary(stickClass: LayoutSecondaryHeader.self, handler: { _ in })
        table.updateStickInset(10, animated: false)
        table.layoutSubtreeIfNeeded()
        var retained: [AnyHashable: LayoutStickView] = [:]
        for offset in [CGFloat(0), 60, 100, 120, 140, 200, 140, 120, 100, 60, 0] {
            table.contentView.scroll(to: NSPoint(x: 0, y: offset))
            table.updateStickAfterScroll(false)
            for item in [date, topic] {
                let overlays = table.subviews.compactMap { $0 as? LayoutStickView }.filter { $0.item === item }
                XCTAssertEqual(overlays.count, 1)
                if let previous = retained[item.stableId] {
                    XCTAssertTrue(previous === overlays.first)
                } else {
                    retained[item.stableId] = overlays.first
                }
                let inline = table.viewNecessary(at: item.index, makeIfNecessary: true) as? LayoutStickView
                XCTAssertEqual(inline?.pillVisible, false)
            }
        }
    }
}
