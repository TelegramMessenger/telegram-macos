import XCTest
import AppKit
import ObjectiveC
import TGUIKit
import TelegramTheme
import GeneralRows
@testable import StarsUI

final class StarTransactionTabsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private func items(_ titles: [String], selected: Int?, ids: [Int64]? = nil) -> [ScrollableSegmentItem] {
        return titles.enumerated().map { index, title in
            ScrollableSegmentItem(title: title, index: index, uniqueId: ids?[index] ?? Int64(index), selected: index == selected, insets: NSEdgeInsets(left: 10, right: 10), icon: nil, theme: .standard(theme.colors), equatable: nil)
        }
    }

    private func item(_ titles: [String], selected: Int?, ids: [Int64]? = nil, callback: @escaping (Int64) -> Void = { _ in }) -> StarTransactionTabsRowItem {
        return StarTransactionTabsRowItem(NSSize(width: 360, height: 72), stableId: 1, items: items(titles, selected: selected, ids: ids), viewType: .firstItem, callback: callback)
    }

    private func row(_ item: StarTransactionTabsRowItem, width: CGFloat) -> GeneralContainableRowView {
        let type = item.viewClass() as! GeneralContainableRowView.Type
        let row = type.init(frame: NSMakeRect(0, 0, width, item.height))
        row.set(item: item, animated: false)
        row.updateLayout(size: row.frame.size, transition: .immediate)
        row.layoutSubtreeIfNeeded()
        return row
    }

    private func descendants<T: NSView>(_ view: NSView, as type: T.Type) -> [T] {
        return view.subviews.flatMap { ($0 as? T).map { [$0] } ?? [] } + view.subviews.flatMap { descendants($0, as: type) }
    }

    private func controls(_ view: NSView) throws -> (GlassSegmentView, HorizontalScrollView) {
        return (try XCTUnwrap(descendants(view, as: GlassSegmentView.self).first), try XCTUnwrap(descendants(view, as: HorizontalScrollView.self).first))
    }

    private func assertSelectedVisible(_ view: NSView, file: StaticString = #filePath, line: UInt = #line) throws {
        let (segments, scroll) = try controls(view)
        let selected = try XCTUnwrap(segments.selectedIndex, file: file, line: line)
        let document = try XCTUnwrap(scroll.documentView, file: file, line: line)
        let frame = segments.convert(segments.itemFrames[selected], to: document)
        let viewport = scroll.clipView.bounds
        XCTAssertLessThanOrEqual(frame.width, viewport.width, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minX, viewport.minX - 0.5, file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, viewport.maxX + 0.5, file: file, line: line)
        let expected = min(max(0, frame.midX - viewport.width / 2), max(0, document.frame.width - viewport.width))
        XCTAssertEqual(viewport.minX, expected, accuracy: 0.5, file: file, line: line)
    }

    private func withReduceMotion(_ value: Bool, _ body: () throws -> Void) throws {
        let method = try XCTUnwrap(class_getInstanceMethod(NSWorkspace.self, #selector(getter: NSWorkspace.accessibilityDisplayShouldReduceMotion)))
        let replacement = imp_implementationWithBlock({ (_: AnyObject) -> Bool in value } as @convention(block) (AnyObject) -> Bool)
        let original = method_setImplementation(method, replacement)
        defer {
            method_setImplementation(method, original)
            imp_removeBlock(replacement)
        }
        try body()
    }

    func testUnevenLocalizedTitlesCenterTheActualSelectedSegment() throws {
        let sets = [
            [String(repeating: "Ausführliche Transaktionsübersicht ", count: 4), "Eingänge", "Ausgänge"],
            ["Все", "Зачисления", String(repeating: "Подробные исходящие переводы ", count: 4)],
            ["All", String(repeating: "Incoming payments ", count: 5), "Outgoing"]
        ]
        for titles in sets {
            for selected in titles.indices where titles[selected].count < 20 {
                let view = row(item(titles, selected: selected), width: 300)
                try assertSelectedVisible(view)
                XCTAssertNil(view.window)
            }
        }
    }

    func testResizeAndTitleChangesKeepTheSelectionVisible() throws {
        let titles = [String(repeating: "Long localized heading ", count: 4), "Incoming", "Outgoing"]
        let view = row(item(titles, selected: 1), width: 700)
        for width: CGFloat in [300, 460, 280, 700, 320] {
            view.setFrameSize(NSSize(width: width, height: view.frame.height))
            view.updateLayout(size: view.frame.size, transition: .immediate)
            try assertSelectedVisible(view)
        }
        view.set(item: item(["All", "Incoming", "Outgoing"], selected: 1), animated: false)
        view.setFrameSize(NSSize(width: 700, height: view.frame.height))
        view.updateLayout(size: view.frame.size, transition: .immediate)
        try assertSelectedVisible(view)
        let (_, scroll) = try controls(view)
        XCTAssertEqual(scroll.clipView.bounds.origin, .zero)
        view.set(item: item(titles, selected: 1), animated: false)
        view.updateLayout(size: view.frame.size, transition: .immediate)
        try assertSelectedVisible(view)
    }

    func testFallbackShadowHasSpaceInsideTheClipAndRow() throws {
        let original = System.liquidGlass
        System.liquidGlass = false
        defer { System.liquidGlass = original }
        let view = row(item(["All", "Incoming", "Outgoing"], selected: 0), width: 600)
        let (segments, scroll) = try controls(view)
        let glass = try XCTUnwrap(descendants(segments, as: LiquidGlassView.self).first)
        let shadow = try XCTUnwrap(glass.shadow)
        let document = try XCTUnwrap(scroll.documentView)
        let frame = glass.convert(glass.bounds, to: document)
        let extent = frame.insetBy(dx: -shadow.shadowBlurRadius, dy: -shadow.shadowBlurRadius)
        XCTAssertTrue(document.bounds.contains(extent))
        XCTAssertTrue(scroll.clipView.bounds.contains(extent))
        XCTAssertTrue(view.containerView.bounds.contains(scroll.frame))
        XCTAssertEqual(view.frame.height, GlassSegmentView.height + 32)
        XCTAssertTrue(view.borderView.isHidden)
        for selected in [0, 2] {
            view.set(item: item(["All", "Incoming", "Outgoing"], selected: selected), animated: false)
            view.setFrameSize(NSSize(width: 240, height: view.frame.height))
            view.updateLayout(size: view.frame.size, transition: .immediate)
            XCTAssertGreaterThanOrEqual(frame.minY - scroll.clipView.bounds.minY, shadow.shadowBlurRadius)
            XCTAssertGreaterThanOrEqual(scroll.clipView.bounds.maxY - frame.maxY, shadow.shadowBlurRadius)
            if selected == 0 {
                XCTAssertGreaterThanOrEqual(frame.minX - scroll.clipView.bounds.minX, shadow.shadowBlurRadius)
            } else {
                XCTAssertGreaterThanOrEqual(scroll.clipView.bounds.maxX - frame.maxX, shadow.shadowBlurRadius)
            }
        }
    }

    func testLiquidGlassChangesKeepExistingRowAndShadowInsideBounds() throws {
        let original = System.liquidGlass
        defer { System.liquidGlass = original }
        for initial in [true, false] {
            System.liquidGlass = initial
            let model = item(["All", "Incoming", "Outgoing"], selected: 1)
            let view = row(model, width: 600)
            let height = model.height
            let (segments, scroll) = try controls(view)
            for enabled in [!initial, initial, !initial] {
                System.liquidGlass = enabled
                view.updateColors()
                view.updateLayout(size: view.frame.size, transition: .immediate)
                view.layoutSubtreeIfNeeded()
                XCTAssertEqual(model.height, height)
                XCTAssertEqual(view.frame.height, height)
                XCTAssertTrue(view.containerView.bounds.contains(scroll.frame))
                try assertSelectedVisible(view)
                if !enabled {
                    let glass = try XCTUnwrap(descendants(segments, as: LiquidGlassView.self).first)
                    let shadow = try XCTUnwrap(glass.shadow)
                    let document = try XCTUnwrap(scroll.documentView)
                    let bounds = glass.convert(glass.bounds, to: document).insetBy(dx: -shadow.shadowBlurRadius, dy: -shadow.shadowBlurRadius)
                    XCTAssertTrue(document.bounds.contains(bounds))
                    XCTAssertTrue(scroll.clipView.bounds.contains(bounds))
                }
            }
        }
    }

    func testAccessibilityExposesRadioChoicesAndUsesCurrentStableIds() throws {
        var chosen: [Int64] = []
        let tabs = items(["All", "Outgoing"], selected: 0, ids: [0, 2])
        tabs[1].accessibilityLabel = { "Outgoing transactions" }
        let model = StarTransactionTabsRowItem(NSSize(width: 360, height: 72), stableId: 1, items: tabs, viewType: .firstItem, callback: { chosen.append($0) })
        let view = row(model, width: 360)
        var children = try XCTUnwrap(view.accessibilityChildren() as? [NSAccessibilityElement])
        XCTAssertEqual(view.accessibilityRole(), .radioGroup)
        XCTAssertTrue(view.isAccessibilityElement())
        XCTAssertTrue(model.accessibilityIncludesChildren)
        XCTAssertNil(model.accessibilityCustomActions)
        XCTAssertEqual(children.count, 2)
        guard children.count == 2 else { return }
        for (index, child) in children.enumerated() {
            XCTAssertTrue(child.isAccessibilityElement())
            XCTAssertEqual(child.accessibilityRole(), .radioButton)
            XCTAssertEqual(child.accessibilityValue() as? NSNumber, NSNumber(value: index == 0))
            XCTAssertEqual(child.isAccessibilitySelected(), index == 0)
            XCTAssertTrue(child.accessibilityParent() as? NSView === view)
        }
        XCTAssertEqual(children[1].accessibilityLabel(), "Outgoing transactions")
        XCTAssertTrue(children[1].accessibilityPerformPress())
        XCTAssertEqual(chosen, [2])
        let retained = children[1]
        view.set(item: item(["Outgoing", "All", "Incoming"], selected: 0, ids: [2, 0, 1], callback: { chosen.append($0 + 10) }), animated: false)
        view.updateLayout(size: view.frame.size, transition: .immediate)
        children = try XCTUnwrap(view.accessibilityChildren() as? [NSAccessibilityElement])
        XCTAssertTrue(children[0] === retained)
        XCTAssertEqual(retained.accessibilityLabel(), "Outgoing")
        XCTAssertEqual(retained.accessibilityValue() as? NSNumber, NSNumber(value: true))
        XCTAssertTrue(retained.isAccessibilitySelected())
        XCTAssertTrue(retained.accessibilityPerformPress())
        let (segments, _) = try controls(view)
        segments.didSelect?(2)
        segments.didSelect?(-1)
        segments.didSelect?(99)
        XCTAssertEqual(chosen, [2, 12, 11])
        view.set(item: item(["All"], selected: 0), animated: false)
        XCTAssertFalse(retained.accessibilityPerformPress())
    }

    func testAccessibilityFocusRevealsOffscreenChoices() throws {
        let view = row(item([String(repeating: "Long localized heading ", count: 4), "Incoming", "Outgoing"], selected: 0), width: 300)
        let children = try XCTUnwrap(view.accessibilityChildren() as? [NSAccessibilityElement])
        XCTAssertEqual(children.count, 3)
        guard children.count == 3 else { return }
        children[2].setAccessibilityFocused(true)
        let (segments, scroll) = try controls(view)
        let document = try XCTUnwrap(scroll.documentView)
        let frame = segments.convert(segments.itemFrames[2], to: document)
        XCTAssertTrue(scroll.clipView.bounds.contains(frame))
        XCTAssertFalse(scroll.clipView.isAnimateScrolling)
        XCTAssertEqual(segments.selectedIndex, 0)
    }

    func testSelectionScrollAnimatesAndResizeCancelsIt() throws {
        try withReduceMotion(false) {
            let titles = [String(repeating: "Long localized heading ", count: 4), "Incoming", "Outgoing"]
            let view = row(item(titles, selected: 0), width: 300)
            view.set(item: item(titles, selected: 1), animated: true)
            view.updateLayout(size: view.frame.size, transition: .immediate)
            let (segments, scroll) = try controls(view)
            XCTAssertTrue(scroll.clipView.isAnimateScrolling)
            XCTAssertNotNil(scroll.clipView.layer?.animation(forKey: "bounds"))
            XCTAssertTrue(segments.subviews.contains { !($0.layer?.animationKeys()?.isEmpty ?? true) })
            try assertSelectedVisible(view)
            view.updateLayout(size: view.frame.size, transition: .immediate)
            XCTAssertTrue(scroll.clipView.isAnimateScrolling)
            view.setFrameSize(NSSize(width: 420, height: view.frame.height))
            view.updateLayout(size: view.frame.size, transition: .immediate)
            XCTAssertFalse(scroll.clipView.isAnimateScrolling)
            XCTAssertNil(scroll.clipView.layer?.animation(forKey: "bounds"))
            try assertSelectedVisible(view)
        }
    }

    func testAppearanceRefreshPreservesAnInFlightSelectionSpring() throws {
        try withReduceMotion(false) {
            let segments = GlassSegmentView(frame: NSMakeRect(0, 0, 360, 40))
            let titles = ["Emoji", "Stickers", "GIFs"]
            segments.set(titles: titles, selected: 0, animated: false)
            segments.set(titles: titles, selected: 2, animated: true)
            let selection = try XCTUnwrap(segments.subviews.first { !($0.layer?.animationKeys()?.isEmpty ?? true) })
            let keys = try XCTUnwrap(selection.layer?.animationKeys())
            XCTAssertFalse(keys.isEmpty)
            segments.updateLocalizationAndTheme(theme: theme)
            segments.set(titles: titles, selected: 2, animated: false)
            XCTAssertEqual(selection.layer?.animationKeys(), keys)
            try withReduceMotion(true) {
                segments.set(titles: titles, selected: 2, animated: false)
                XCTAssertTrue(selection.layer?.animationKeys()?.isEmpty ?? true)
            }
        }
    }

    func testReduceMotionStopsScrollAndSelectionAnimations() throws {
        let titles = [String(repeating: "Long localized heading ", count: 4), "Incoming", "Outgoing"]
        let view = row(item(titles, selected: 0), width: 300)
        let (segments, scroll) = try controls(view)
        try withReduceMotion(false) {
            view.set(item: item(titles, selected: 1), animated: true)
            view.updateLayout(size: view.frame.size, transition: .immediate)
            XCTAssertTrue(scroll.clipView.isAnimateScrolling)
        }
        try withReduceMotion(true) {
            view.set(item: item(titles, selected: 2), animated: true)
            view.updateLayout(size: view.frame.size, transition: .immediate)
            XCTAssertFalse(scroll.clipView.isAnimateScrolling)
            XCTAssertNil(scroll.clipView.layer?.animation(forKey: "bounds"))
            XCTAssertTrue(segments.subviews.allSatisfy { $0.layer?.animationKeys()?.isEmpty ?? true })
            try assertSelectedVisible(view)
            segments.setSelection(position: 1, animated: true)
            XCTAssertTrue(segments.subviews.allSatisfy { $0.layer?.animationKeys()?.isEmpty ?? true })
            segments.set(titles: titles, selected: 0, animated: true)
            XCTAssertTrue(segments.subviews.allSatisfy { $0.layer?.animationKeys()?.isEmpty ?? true })
        }
    }

    func testEmptySelectionAndOversizedSegmentStayClamped() throws {
        let view = row(item([], selected: nil), width: 300)
        let (segments, scroll) = try controls(view)
        XCTAssertTrue(try XCTUnwrap(view.accessibilityChildren()).isEmpty)
        XCTAssertNil(segments.selectedIndex)
        XCTAssertEqual(scroll.clipView.bounds.origin, .zero)
        view.set(item: item(["All", String(repeating: "Oversized localized title ", count: 8), "Outgoing"], selected: 1), animated: false)
        view.updateLayout(size: view.frame.size, transition: .immediate)
        let document = try XCTUnwrap(scroll.documentView)
        let frame = segments.convert(segments.itemFrames[1], to: document)
        XCTAssertGreaterThan(frame.width, scroll.clipView.bounds.width)
        XCTAssertEqual(scroll.clipView.bounds.midX, frame.midX, accuracy: 0.5)
        XCTAssertGreaterThanOrEqual(scroll.clipView.bounds.minX, 0)
        XCTAssertLessThanOrEqual(scroll.clipView.bounds.maxX, document.bounds.maxX)
    }
}
