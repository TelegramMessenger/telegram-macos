import XCTest
import AppKit
import ColorPalette
@testable import TGUIKit

private final class TestBadgeNode: Node {
    init() {
        let view = View(frame: NSMakeRect(0, 0, 10, 10))
        view.backgroundColor = .systemRed
        super.init(view)
    }

    override func update() {
        if let view, let superview = view.superview {
            view.setFrameOrigin(NSMakePoint(floor(superview.frame.width / 2) + 4, 4))
        }
    }
}

private final class TabSelectionDelegate: TabViewDelegate {
    var changes: [Int] = []
    var scrollCount = 0

    func didChange(selected item: TabItem, index: Int) {
        changes.append(index)
    }

    func scrollup() {
        scrollCount += 1
    }
}

private final class CustomTabIcon: View {
    var selected = false
}

private final class CustomTabItem: TabItem {
    var animatedSelections = 0

    override func makeView() -> NSView {
        return CustomTabIcon(frame: NSMakeRect(0, 0, 30, 30))
    }

    override func setSelected(_ selected: Bool, for view: NSView, animated: Bool) {
        (view as? CustomTabIcon)?.selected = selected
        if selected && animated {
            animatedSelections += 1
        }
    }
}

private final class TabSelectionTestLayer: CALayer {
    var displayedLayer: TabSelectionTestLayer?

    override func presentation() -> Self? {
        return displayedLayer as? Self
    }
}

final class TabBarViewTreeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    private func makeTab(badge: Bool = false, controller: ViewController = ViewController()) -> TabItem {
        controller.bar = .init(height: 0)
        return TabItem(image: testImage(CGSize(width: 24, height: 24)), selectedImage: testImage(CGSize(width: 24, height: 24)), controller: controller, subNode: badge ? TestBadgeNode() : nil)
    }

    private func makeBar(width: CGFloat = 333, selected: Int = 0) -> TabBarView {
        let bar = TabBarView(frame: NSMakeRect(0, 0, width, 48))
        bar.reduceMotion = { false }
        for index in 0 ..< 4 {
            bar.addTab(makeTab(badge: index == 2))
        }
        bar.setSelectedIndex(selected, respondToDelegate: false, animated: false)
        return bar
    }

    private func center(_ bar: TabBarView, _ index: Int) -> NSPoint {
        let frame = bar.control(for: index).frame
        return NSMakePoint(frame.midX, frame.midY)
    }

    private func portals(in layer: CALayer, source: CALayer) -> [CALayer] {
        var result: [CALayer] = []
        if layer.responds(to: NSSelectorFromString("sourceLayer")), layer.value(forKey: "sourceLayer") as? CALayer === source {
            result.append(layer)
        }
        for child in layer.sublayers ?? [] {
            result += portals(in: child, source: source)
        }
        return result
    }

    private func assertTint(_ portal: CALayer, matches color: NSColor, file: StaticString = #filePath, line: UInt = #line) throws {
        let filter = try XCTUnwrap(portal.filters?.first as? NSObject, file: file, line: line)
        let value = try XCTUnwrap(filter.value(forKey: "inputColorMatrix") as? NSValue, file: file, line: line)
        let color = try XCTUnwrap(color.usingColorSpace(.sRGB), file: file, line: line)
        var matrix = [Float](repeating: 0, count: 20)
        matrix.withUnsafeMutableBytes { value.getValue($0.baseAddress!, size: $0.count) }
        for (index, component) in [(3, color.redComponent), (8, color.greenComponent), (13, color.blueComponent), (18, color.alphaComponent)] {
            XCTAssertEqual(CGFloat(matrix[index]), component, accuracy: 0.0001, file: file, line: line)
        }
    }

    private func makePlaybackBar(selected: Int = 0) -> (TabBarView, [CustomTabItem]) {
        let bar = TabBarView(frame: NSMakeRect(0, 0, 333, 48))
        bar.reduceMotion = { false }
        let items = (0 ..< 4).map { _ -> CustomTabItem in
            let original = makeTab()
            return CustomTabItem(image: original.image, selectedImage: original.selectedImage, controller: original.controller)
        }
        for item in items {
            bar.addTab(item)
        }
        bar.setSelectedIndex(selected, respondToDelegate: false, animated: false)
        return (bar, items)
    }

    private func enableNativeLens(_ bar: TabBarView) throws {
        guard System.liquidGlassAvailable else {
            throw XCTSkip("Native glass is unavailable")
        }
        bar.reduceTransparency = { false }
        System.liquidGlass = true
        bar.updateLocalizationAndTheme(theme: presentation)
        XCTAssertNotNil(bar.nativeLens)
    }

    func testDisabledGlassKeepsTheExistingInteractionWithoutConstructingALens() {
        let bar = makeBar()
        var attempts = 0
        bar.lensFactory = {
            attempts += 1
            return nil
        }
        bar.beginSelection(at: center(bar, 0))
        XCTAssertNil(bar.nativeLens)
        XCTAssertEqual(attempts, 0)
        XCTAssertEqual(bar.selectionFrame.width, bar.control(for: 0).frame.width + 16)
        XCTAssertEqual(bar.control(for: 0).layer!.transform.m11, 1.15, accuracy: 0.001)
        bar.cancelSelection(animated: false)
    }

    func testNativeLensKeepsTheSameControlsIconsBadgesAndHitTargets() throws {
        defer { System.liquidGlass = false }
        let bar = makeBar(selected: 2)
        let control = bar.control(for: 2)
        let icon = control.subviews[0]
        let badge = control.subviews[1]
        try enableNativeLens(bar)
        let lens = try XCTUnwrap(bar.nativeLens)
        XCTAssertTrue(control.superview === lens.contentView)
        bar.beginSelection(at: center(bar, 2))
        XCTAssertEqual(bar.selectionFrame.width, control.frame.width + 20)
        XCTAssertEqual(bar.selectionFrame.height, 56)
        XCTAssertEqual(control.layer!.transform.m11, 1, accuracy: 0.001)
        XCTAssertTrue(control.subviews[0] === icon)
        XCTAssertTrue(control.subviews[1] === badge)
        XCTAssertTrue(bar.hitTest(center(bar, 2)) === control)
        bar.cancelSelection(animated: false)
    }

    func testNativeRestingIndicatorUsesABlurThatDisappearsDuringDragging() throws {
        defer { System.liquidGlass = false }
        let bar = makeBar(selected: 2)
        try enableNativeLens(bar)
        let lens = try XCTUnwrap(bar.nativeLens)
        let background = try XCTUnwrap(lens.subviews.first?.layer?.sublayers?.first)
        XCTAssertEqual(background.name, "lensRestingBackground")
        XCTAssertEqual(background.frame, bar.selectionFrame)
        XCTAssertEqual(background.opacity, 1)
        XCTAssertEqual(background.sublayers?.first?.value(forKeyPath: "filters.lensRestingBlur.inputRadius") as? CGFloat, 16)
        XCTAssertEqual(bar.subviews[1].alphaValue, 0)
        bar.beginSelection(at: center(bar, 2))
        bar.updateSelection(at: center(bar, 3))
        XCTAssertEqual(background.opacity, 0)
        bar.cancelSelection(animated: false)
        XCTAssertEqual(background.opacity, 1)
        XCTAssertEqual(background.frame, bar.control(for: 2).frame)
        bar.reduceMotion = { true }
        bar.beginSelection(at: center(bar, 2))
        XCTAssertEqual(background.opacity, 1)
        XCTAssertEqual(background.frame.height, 40)
        bar.cancelSelection(animated: false)
    }

    func testNativeLensTintsOverlappingIconsWhileKeepingTheBadgeUntinted() throws {
        defer { System.liquidGlass = false }
        let bar = makeBar()
        let window = NSWindow(contentRect: bar.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = bar
        defer { window.close() }
        try enableNativeLens(bar)
        bar.beginSelection(at: center(bar, 1))
        bar.updateSelection(at: NSPoint(x: (center(bar, 1).x + center(bar, 2).x) / 2, y: center(bar, 1).y))
        bar.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let root = try XCTUnwrap(bar.nativeLens?.layer)
        for index in [1, 2] {
            let icon = bar.control(for: index).subviews[0]
            let copies = portals(in: root, source: try XCTUnwrap(icon.layer))
            XCTAssertEqual(copies.count, 2)
            XCTAssertTrue(copies.allSatisfy { $0.filters?.count == 1 })
            XCTAssertNil(icon.layer?.filters)
        }
        let badge = bar.control(for: 2).subviews[1]
        let copies = portals(in: root, source: try XCTUnwrap(badge.layer))
        XCTAssertEqual(copies.count, 2)
        XCTAssertTrue(copies.allSatisfy { $0.filters?.isEmpty ?? true })
        bar.cancelSelection(animated: false)
        XCTAssertTrue(portals(in: root, source: try XCTUnwrap(badge.layer)).isEmpty)
    }

    func testNativeLensPreservesCustomIconsWithoutTemplateTinting() throws {
        defer { System.liquidGlass = false }
        let (bar, _) = makePlaybackBar()
        let window = NSWindow(contentRect: bar.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = bar
        defer { window.close() }
        try enableNativeLens(bar)
        bar.beginSelection(at: center(bar, 1))
        bar.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let icon = bar.control(for: 1).subviews[0]
        let copies = portals(in: try XCTUnwrap(bar.nativeLens?.layer), source: try XCTUnwrap(icon.layer))
        XCTAssertEqual(copies.count, 2)
        XCTAssertTrue(copies.allSatisfy { $0.filters?.isEmpty ?? true })
        bar.cancelSelection(animated: false)
    }

    func testNativeLensOutsideTintMatchesDarkAndLightThemes() throws {
        let previousTheme = presentation
        defer {
            System.liquidGlass = false
            updateTheme(previousTheme)
        }
        for palette in [darkPalette, nightAccentPalette, whitePalette] {
            updateTheme(PresentationTheme(colors: palette, search: previousTheme.search, inputTheme: previousTheme.inputTheme))
            let bar = makeBar()
            let window = NSWindow(contentRect: bar.bounds, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = bar
            defer { window.close() }
            try enableNativeLens(bar)
            bar.beginSelection(at: center(bar, 1))
            bar.updateSelection(at: NSPoint(x: (center(bar, 1).x + center(bar, 2).x) / 2, y: center(bar, 1).y))
            bar.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let root = try XCTUnwrap(bar.nativeLens?.layer)
            for index in 0 ..< bar.count {
                let icon = bar.control(for: index).subviews[0]
                let copies = portals(in: root, source: try XCTUnwrap(icon.layer))
                XCTAssertEqual(copies.count, 2)
                for copy in copies {
                    let color = copy.superlayer?.name == "lensUnlensedContent" ? (palette.isDark ? NSColor.white : palette.grayIcon) : palette.accentIcon
                    try assertTint(copy, matches: color)
                }
                XCTAssertNil(icon.layer?.filters)
            }
            bar.cancelSelection(animated: false)
            XCTAssertTrue(portals(in: root, source: try XCTUnwrap(bar.control(for: 1).subviews[0].layer)).isEmpty)
        }
    }

    func testDisablingGlassDuringADragCancelsAndRestoresTheOriginalControls() throws {
        defer { System.liquidGlass = false }
        let bar = makeBar(selected: 1)
        let delegate = TabSelectionDelegate()
        bar.delegate = delegate
        let controls = (0 ..< bar.count).map { bar.control(for: $0) }
        try enableNativeLens(bar)
        bar.beginSelection(at: center(bar, 1))
        bar.updateSelection(at: center(bar, 3))
        System.liquidGlass = false
        XCTAssertFalse(bar.isTrackingSelection)
        XCTAssertNil(bar.nativeLens)
        XCTAssertEqual(bar.selectedIndex, 1)
        XCTAssertTrue(delegate.changes.isEmpty)
        XCTAssertTrue(controls.allSatisfy { $0.superview === bar })
        XCTAssertTrue(bar.control(for: 1).isAccessibilitySelected())
        XCTAssertEqual(bar.selectionFrame, bar.control(for: 1).frame)
    }

    func testUnsupportedNativeEffectsKeepTheExistingGlassAndAreNotRetriedEveryLayout() throws {
        guard System.liquidGlassAvailable else {
            throw XCTSkip("Native glass is unavailable")
        }
        defer { System.liquidGlass = false }
        let bar = makeBar()
        var attempts = 0
        bar.reduceTransparency = { false }
        bar.lensFactory = {
            attempts += 1
            return nil
        }
        System.liquidGlass = true
        bar.beginSelection(at: center(bar, 0))
        bar.layout()
        bar.updateSelection(at: center(bar, 1))
        XCTAssertEqual(attempts, 1)
        XCTAssertNil(bar.nativeLens)
        XCTAssertEqual(bar.selectionFrame.width, bar.control(for: 1).frame.width + 16)
        bar.cancelSelection(animated: false)
    }

    func testReducingTransparencyDuringAPressRemovesTheNativeLens() throws {
        defer { System.liquidGlass = false }
        let bar = makeBar()
        try enableNativeLens(bar)
        bar.beginSelection(at: center(bar, 2))
        bar.reduceTransparency = { true }
        bar.updateLocalizationAndTheme(theme: presentation)
        XCTAssertNil(bar.nativeLens)
        XCTAssertFalse(bar.isTrackingSelection)
        XCTAssertEqual(bar.selectedIndex, 0)
        bar.reduceTransparency = { false }
        bar.updateLocalizationAndTheme(theme: presentation)
        XCTAssertNotNil(bar.nativeLens)
    }

    func testNativeDragCommitStillPlaysOnlyTheDestinationOnce() throws {
        defer { System.liquidGlass = false }
        let (bar, items) = makePlaybackBar()
        let delegate = TabSelectionDelegate()
        bar.delegate = delegate
        try enableNativeLens(bar)
        bar.beginSelection(at: center(bar, 0))
        bar.updateSelection(at: center(bar, 2))
        bar.updateSelection(at: center(bar, 3))
        bar.endSelection(at: center(bar, 3))
        XCTAssertEqual(items.map { $0.animatedSelections }, [0, 0, 0, 1])
        XCTAssertEqual(delegate.changes, [3])
    }

    func testNativeLensRespectsReduceMotionWithoutScalingTheOriginalContent() throws {
        defer { System.liquidGlass = false }
        let bar = makeBar()
        try enableNativeLens(bar)
        bar.reduceMotion = { true }
        let point = center(bar, 2)
        bar.beginSelection(at: point)
        XCTAssertEqual(bar.selectionFrame, bar.control(for: 2).frame)
        XCTAssertEqual(bar.selectionFrame.height, 40)
        XCTAssertEqual(bar.control(for: 2).layer!.transform.m11, 1, accuracy: 0.001)
        XCTAssertNil(bar.control(for: 2).layer?.animation(forKey: "transform"))
        bar.endSelection(at: point)
        XCTAssertEqual(bar.selectedIndex, 2)
    }

    func testDragCommitPlaysOnlyTheDestinationOnceOnRelease() {
        for (source, destinations) in [(0, [1, 2, 3]), (3, [2, 1, 0])] {
            let (bar, items) = makePlaybackBar(selected: source)
            let delegate = TabSelectionDelegate()
            bar.delegate = delegate
            bar.beginSelection(at: center(bar, source))
            for index in destinations {
                bar.updateSelection(at: center(bar, index))
                XCTAssertTrue(items.allSatisfy { $0.animatedSelections == 0 })
            }
            let target = destinations.last!
            bar.endSelection(at: center(bar, target))
            XCTAssertEqual(items[target].animatedSelections, 1)
            XCTAssertEqual(items.map { $0.animatedSelections }.reduce(0, +), 1)
            XCTAssertEqual(delegate.changes, [target])
            bar.endSelection(at: center(bar, target))
            XCTAssertEqual(items[target].animatedSelections, 1)
        }
    }

    func testFractionalDragReleasePlaysTheNearestTab() {
        let (bar, items) = makePlaybackBar()
        bar.beginSelection(at: center(bar, 0))
        bar.updateSelection(at: center(bar, 1))
        let first = center(bar, 1)
        let second = center(bar, 2)
        bar.endSelection(at: NSMakePoint(first.x + (second.x - first.x) * 0.6, first.y))
        XCTAssertEqual(bar.selectedIndex, 2)
        XCTAssertEqual(items[2].animatedSelections, 1)
        XCTAssertEqual(items[1].animatedSelections, 0)
    }

    func testClickPlaybackDoesNotRestartOnRelease() {
        let (bar, items) = makePlaybackBar()
        let point = center(bar, 3)
        bar.beginSelection(at: point)
        XCTAssertEqual(items[3].animatedSelections, 1)
        bar.endSelection(at: point)
        XCTAssertEqual(items[3].animatedSelections, 1)
    }

    func testCancelledDragDoesNotPlayItsPreviewedDestination() {
        let (bar, items) = makePlaybackBar()
        bar.beginSelection(at: center(bar, 0))
        bar.updateSelection(at: center(bar, 3))
        bar.cancelSelection()
        bar.endSelection(at: center(bar, 3))
        XCTAssertEqual(bar.selectedIndex, 0)
        XCTAssertEqual(items[3].animatedSelections, 0)
    }

    func testDraggingBackToTheOriginalTabDoesNotPlayItAgain() {
        let (bar, items) = makePlaybackBar()
        let delegate = TabSelectionDelegate()
        bar.delegate = delegate
        let start = center(bar, 0)
        bar.beginSelection(at: start)
        bar.updateSelection(at: center(bar, 2))
        bar.updateSelection(at: start)
        bar.endSelection(at: start)
        XCTAssertTrue(items.allSatisfy { $0.animatedSelections == 0 })
        XCTAssertTrue(delegate.changes.isEmpty)
        XCTAssertEqual(delegate.scrollCount, 1)
    }

    func testReduceMotionDisablesDragCommitPlayback() {
        let (bar, items) = makePlaybackBar()
        bar.reduceMotion = { true }
        bar.beginSelection(at: center(bar, 0))
        bar.updateSelection(at: center(bar, 3))
        bar.endSelection(at: center(bar, 3))
        XCTAssertEqual(bar.selectedIndex, 3)
        XCTAssertTrue(items.allSatisfy { $0.animatedSelections == 0 })
    }

    private func selectionLayer(_ bar: TabBarView) throws -> TabSelectionTestLayer {
        let view = bar.subviews[1]
        let layer = TabSelectionTestLayer()
        layer.anchorPoint = try XCTUnwrap(view.layer).anchorPoint
        view.layer = layer
        return layer
    }

    private func positionAnimation(_ layer: CALayer) throws -> CABasicAnimation {
        return try XCTUnwrap(layer.animation(forKey: "position") as? CABasicAnimation)
    }

    func testImmediateClickReleaseKeepsTheFullTabTransition() throws {
        for (source, target) in [(3, 0), (0, 3)] {
            let bar = makeBar(selected: source)
            let delegate = TabSelectionDelegate()
            bar.delegate = delegate
            let layer = try selectionLayer(bar)
            let initialPosition = layer.position
            let initialBounds = layer.bounds
            let point = center(bar, target)
            bar.beginSelection(at: point)
            bar.endSelection(at: point)
            let animation = try positionAnimation(layer)
            XCTAssertEqual((animation.fromValue as? NSValue)?.pointValue, initialPosition)
            XCTAssertEqual((animation.toValue as? NSValue)?.pointValue, layer.position)
            XCTAssertEqual(animation.duration / Double(animation.speed), 0.4, accuracy: 0.001)
            let bounds = try XCTUnwrap(layer.animation(forKey: "bounds") as? CABasicAnimation)
            XCTAssertEqual((bounds.fromValue as? NSValue)?.rectValue, initialBounds)
            XCTAssertEqual((bounds.toValue as? NSValue)?.rectValue, layer.bounds)
            XCTAssertEqual(bar.selectionFrame, bar.control(for: target).frame)
            XCTAssertEqual(bar.selectedIndex, target)
            XCTAssertEqual(delegate.changes, [target])
            XCTAssertFalse(bar.isTrackingSelection)
        }
    }

    func testClickJitterAndRedundantLayoutsPreserveThePressAnimation() throws {
        let bar = makeBar(selected: 3)
        let layer = try selectionLayer(bar)
        let point = center(bar, 0)
        bar.beginSelection(at: point)
        let animation = try positionAnimation(layer)
        let frame = bar.selectionFrame
        for offset in [CGFloat(0), 2, -2] {
            bar.updateSelection(at: NSMakePoint(point.x + offset, point.y + 10))
            bar.layout()
            bar.setFrameSize(bar.frame.size)
            XCTAssertEqual(bar.selectionFrame, frame)
            XCTAssertTrue(try positionAnimation(layer).isEqual(animation))
        }
        bar.endSelection(at: NSMakePoint(point.x + 2, point.y))
        XCTAssertEqual((try positionAnimation(layer).fromValue as? NSValue)?.pointValue, (animation.fromValue as? NSValue)?.pointValue)
        XCTAssertEqual(bar.selectedIndex, 0)
    }

    func testReleaseRetargetsFromThePresentedPositionAndBounds() throws {
        for (source, target) in [(3, 0), (0, 3)] {
            let bar = makeBar(selected: source)
            let layer = try selectionLayer(bar)
            let point = center(bar, target)
            bar.beginSelection(at: point)
            let displayed = TabSelectionTestLayer()
            displayed.position = NSMakePoint(150, 1)
            displayed.bounds = NSMakeRect(0, 0, 90, 46)
            layer.displayedLayer = displayed
            bar.endSelection(at: point)
            XCTAssertEqual((try positionAnimation(layer).fromValue as? NSValue)?.pointValue, displayed.position)
            let bounds = try XCTUnwrap(layer.animation(forKey: "bounds") as? CABasicAnimation)
            XCTAssertEqual((bounds.fromValue as? NSValue)?.rectValue, displayed.bounds)
            XCTAssertEqual((bounds.toValue as? NSValue)?.rectValue, layer.bounds)
        }
    }

    func testRapidClicksKeepTheirUnrenderedStartingPosition() throws {
        let bar = makeBar(selected: 3)
        let layer = try selectionLayer(bar)
        let initialPosition = layer.position
        for index in [0, 2, 1, 0] {
            let point = center(bar, index)
            bar.beginSelection(at: point)
            bar.endSelection(at: point)
            XCTAssertEqual((try positionAnimation(layer).fromValue as? NSValue)?.pointValue, initialPosition)
            XCTAssertEqual(bar.selectedIndex, index)
        }
    }

    func testHorizontalDraggingStartsAtThreePointsAndTracksUntilRelease() throws {
        let bar = makeBar(selected: 3)
        let layer = try selectionLayer(bar)
        let delegate = TabSelectionDelegate()
        bar.delegate = delegate
        let start = center(bar, 0)
        bar.beginSelection(at: start)
        bar.updateSelection(at: NSMakePoint(start.x + 3, start.y))
        XCTAssertNil(layer.animation(forKey: "position"))
        XCTAssertNil(layer.animation(forKey: "bounds"))
        XCTAssertEqual(bar.selectionFrame.midX, start.x + 3, accuracy: 0.001)
        let end = center(bar, 1)
        bar.updateSelection(at: NSMakePoint(end.x - 5, end.y))
        bar.endSelection(at: end)
        XCTAssertEqual(bar.selectedIndex, 1)
        XCTAssertEqual(bar.selectionFrame.midX, end.x, accuracy: 0.001)
        XCTAssertEqual(delegate.changes, [1])
        XCTAssertNotNil(layer.animation(forKey: "bounds"))
    }

    func testCancellationAnimatesBackFromThePresentedFrame() throws {
        let bar = makeBar(selected: 3)
        let delegate = TabSelectionDelegate()
        bar.delegate = delegate
        let layer = try selectionLayer(bar)
        let initialFrame = bar.selectionFrame
        bar.beginSelection(at: center(bar, 0))
        let displayed = TabSelectionTestLayer()
        displayed.position = NSMakePoint(150, 1)
        displayed.bounds = NSMakeRect(0, 0, 90, 46)
        layer.displayedLayer = displayed
        bar.cancelSelection()
        XCTAssertEqual((try positionAnimation(layer).fromValue as? NSValue)?.pointValue, displayed.position)
        XCTAssertEqual(bar.selectionFrame, initialFrame)
        XCTAssertEqual(bar.selectedIndex, 3)
        XCTAssertTrue(delegate.changes.isEmpty)
        XCTAssertEqual(delegate.scrollCount, 0)
    }

    func testNewSelectionsRetargetAnActivePressWithoutSnappingBack() throws {
        for programmatic in [false, true] {
            let bar = makeBar(selected: 3)
            let layer = try selectionLayer(bar)
            let initialPosition = layer.position
            bar.beginSelection(at: center(bar, 0))
            if programmatic {
                bar.setSelectedIndex(1, respondToDelegate: false, animated: true)
            } else {
                let point = center(bar, 1)
                bar.beginSelection(at: point)
                bar.endSelection(at: point)
            }
            XCTAssertEqual((try positionAnimation(layer).fromValue as? NSValue)?.pointValue, initialPosition)
            XCTAssertEqual(bar.selectedIndex, 1)
        }
    }

    func testReduceMotionKeepsClicksAndDraggingImmediate() throws {
        let bar = makeBar(selected: 3)
        bar.reduceMotion = { true }
        let layer = try selectionLayer(bar)
        let point = center(bar, 0)
        bar.beginSelection(at: point)
        XCTAssertEqual(bar.selectionFrame.height, 40)
        XCTAssertEqual(bar.selectionFrame.midX, point.x)
        bar.endSelection(at: point)
        XCTAssertNil(layer.animation(forKey: "position"))
        XCTAssertNil(layer.animation(forKey: "bounds"))
        bar.beginSelection(at: point)
        bar.updateSelection(at: center(bar, 2))
        bar.endSelection(at: center(bar, 2))
        XCTAssertEqual(bar.selectedIndex, 2)
        XCTAssertEqual(bar.selectionFrame.height, 40)
        XCTAssertNil(layer.animation(forKey: "position"))
        XCTAssertNil(layer.animation(forKey: "bounds"))
        for control in bar.itemControls {
            XCTAssertNil(control.layer?.animation(forKey: "transform"))
        }
    }

    func testCapsuleFloatsInsideItsPaneAndCapsItsWidth() {
        XCTAssertEqual(FloatingTabBarLayout.frame(in: NSMakeSize(380, 700)), NSMakeRect(20, 636, 340, 48))
        XCTAssertEqual(FloatingTabBarLayout.frame(in: NSMakeSize(800, 700)), NSMakeRect(150, 636, 500, 48))
        XCTAssertEqual(FloatingTabBarLayout.frame(in: .zero).width, 0)
    }

    func testThreeAndFourTabsFillTheCapsuleWithoutPixelGaps() {
        for width in [CGFloat(280), 333, 401] {
            let bar = makeBar(width: width)
            for count in [4, 3] {
                if count == 3 {
                    bar.removeTab(at: 1)
                }
                XCTAssertEqual(bar.itemControls.count, count)
                XCTAssertEqual(bar.itemControls.first?.frame.minX, 4)
                XCTAssertEqual(bar.itemControls.last?.frame.maxX, width - 4)
                for (index, control) in bar.itemControls.enumerated() {
                    XCTAssertEqual(control.frame.height, 40)
                    XCTAssertEqual(control.subviews.first!.frame.midX, control.bounds.midX, accuracy: 0.5)
                    XCTAssertEqual(control.subviews.first!.frame.midY, control.bounds.midY, accuracy: 0.5)
                    if index > 0 {
                        XCTAssertEqual(bar.itemControls[index - 1].frame.maxX, control.frame.minX)
                    }
                }
            }
        }
    }

    func testIconsAndBadgesStayAttachedWhenResizing() {
        let bar = makeBar(selected: 2)
        let icon = bar.control(for: 2).subviews[0]
        let badge = bar.control(for: 2).subviews[1]
        bar.setFrameSize(NSMakeSize(401, 48))
        XCTAssertTrue(bar.control(for: 2).subviews[0] === icon)
        XCTAssertTrue(bar.control(for: 2).subviews[1] === badge)
        XCTAssertEqual(bar.selectionFrame.midX, bar.control(for: 2).frame.midX)
        XCTAssertEqual(badge.frame.minX, floor(bar.control(for: 2).frame.width / 2) + 4)
    }

    func testDragPreviewsWithoutSwitchingAndCommitsOnceOnRelease() {
        let bar = makeBar()
        let delegate = TabSelectionDelegate()
        bar.delegate = delegate
        bar.beginSelection(at: center(bar, 0))
        bar.updateSelection(at: center(bar, 3))
        XCTAssertEqual(bar.selectedIndex, 0)
        XCTAssertTrue(bar.control(for: 3).isSelected)
        XCTAssertTrue(delegate.changes.isEmpty)
        bar.endSelection(at: center(bar, 3))
        XCTAssertEqual(bar.selectedIndex, 3)
        XCTAssertEqual(delegate.changes, [3])
        XCTAssertFalse(bar.isTrackingSelection)
        XCTAssertEqual(bar.selectionFrame.height, 40)
    }

    func testLensFollowsFractionalDragAndClampsAtTheEnds() {
        let bar = makeBar()
        let start = center(bar, 0)
        let next = center(bar, 1)
        bar.beginSelection(at: start)
        bar.updateSelection(at: NSMakePoint((start.x + next.x) / 2, start.y))
        XCTAssertEqual(bar.selectionFrame.midX, (start.x + next.x) / 2, accuracy: 0.001)
        bar.updateSelection(at: NSMakePoint(-500, start.y))
        XCTAssertEqual(bar.selectionFrame.midX, start.x)
        bar.updateSelection(at: NSMakePoint(1000, start.y))
        XCTAssertEqual(bar.selectionFrame.midX, center(bar, 3).x)
        bar.cancelSelection(animated: false)
    }

    func testReselectingScrollsUpAndCancellationDoesNot() {
        let bar = makeBar(selected: 2)
        let delegate = TabSelectionDelegate()
        bar.delegate = delegate
        bar.beginSelection(at: center(bar, 2))
        bar.endSelection(at: center(bar, 2))
        XCTAssertEqual(delegate.scrollCount, 1)
        bar.beginSelection(at: center(bar, 0))
        bar.cancelSelection(animated: false)
        bar.endSelection(at: center(bar, 0))
        XCTAssertEqual(bar.selectedIndex, 2)
        XCTAssertEqual(delegate.scrollCount, 1)
        XCTAssertTrue(delegate.changes.isEmpty)
        XCTAssertTrue(bar.control(for: 2).isSelected)
    }

    func testHidingResizingAndChangingItemsCancelTheGesture() {
        let bar = makeBar(selected: 2)
        bar.beginSelection(at: center(bar, 0))
        bar.isHidden = true
        XCTAssertFalse(bar.isTrackingSelection)
        bar.isHidden = false
        bar.beginSelection(at: center(bar, 0))
        bar.setFrameSize(NSMakeSize(401, 48))
        XCTAssertFalse(bar.isTrackingSelection)
        bar.beginSelection(at: center(bar, 0))
        bar.removeTab(at: 1)
        XCTAssertFalse(bar.isTrackingSelection)
        XCTAssertEqual(bar.selectedIndex, 1)
    }

    func testCallsInsertionAndRemovalPreserveTheSelectedController() {
        let bar = makeBar(selected: 3)
        let settings = bar.tab(at: 3).controller
        let settingsControl = bar.control(for: 3)
        bar.removeTab(at: 1)
        XCTAssertEqual(bar.selectedIndex, 2)
        XCTAssertTrue(bar.tab(at: 2).controller === settings)
        XCTAssertTrue(bar.control(for: 2) === settingsControl)
        bar.insertTab(makeTab(), at: 1)
        XCTAssertEqual(bar.selectedIndex, 3)
        XCTAssertTrue(bar.tab(at: 3).controller === settings)
    }

    func testRemovingSelectedCallsSelectsChatsAndNotifiesTheDelegate() {
        let bar = makeBar(selected: 1)
        let chats = bar.tab(at: 2).controller
        let delegate = TabSelectionDelegate()
        bar.delegate = delegate
        bar.removeTab(at: 1)
        XCTAssertTrue(bar.tab(at: bar.selectedIndex).controller === chats)
        XCTAssertEqual(delegate.changes, [1])
    }

    func testInvalidSelectionAndEmptyBarsAreSafe() {
        let bar = makeBar(selected: 2)
        for index in [-1, 4, 50] {
            bar.setSelectedIndex(index, respondToDelegate: true, animated: false)
        }
        XCTAssertEqual(bar.selectedIndex, 2)
        for _ in 0 ..< 4 {
            bar.removeTab(at: 0)
        }
        bar.setSelectedIndex(0, respondToDelegate: true, animated: false)
        bar.beginSelection(at: .zero)
        XCTAssertTrue(bar.isEmpty)
        XCTAssertFalse(bar.isTrackingSelection)
        XCTAssertNil(bar.hitTest(.zero))
    }

    func testCapsuleMarginsPassThroughAndIconsHitTheirControls() {
        let parent = View(frame: NSMakeRect(0, 0, 380, 700))
        let bar = makeBar(width: 340)
        bar.frame = FloatingTabBarLayout.frame(in: parent.frame.size)
        parent.addSubview(bar)
        XCTAssertNil(bar.hitTest(NSMakePoint(10, 670)))
        XCTAssertNil(bar.hitTest(NSMakePoint(20, 636)))
        for index in 0 ..< bar.count {
            XCTAssertTrue(bar.hitTest(parent.convert(center(bar, index), from: bar)) === bar.control(for: index))
        }
    }

    func testReplacementUsesTheCustomIconAndPreservesTheBadgeAndTitle() {
        let bar = TabBarView(frame: NSMakeRect(0, 0, 340, 48))
        let original = makeTab(badge: true)
        let item = CustomTabItem(image: original.image, selectedImage: original.selectedImage, controller: original.controller, subNode: original.subNode)
        item.accessibilityTitle = "Settings"
        bar.addTab(item)
        let icon = bar.control(for: 0).subviews[0] as! CustomTabIcon
        let badge = bar.control(for: 0).subviews[1]
        let replacement = CustomTabItem(image: original.image, selectedImage: original.selectedImage, controller: original.controller, subNode: original.subNode)
        replacement.accessibilityTitle = "Updated Settings"
        bar.replaceTab(replacement, at: 0)
        XCTAssertTrue(bar.control(for: 0).subviews[0] === icon)
        XCTAssertTrue(bar.control(for: 0).subviews[1] === badge)
        XCTAssertTrue(icon.selected)
        XCTAssertEqual(bar.control(for: 0).accessibilityLabel(), "Updated Settings")
        XCTAssertEqual(bar.control(for: 0).toolTip, "Updated Settings")
    }

    func testReplacementRemovesAnObsoleteBadge() {
        let bar = makeBar(selected: 2)
        let badge = bar.control(for: 2).subviews[1]
        bar.replaceTab(makeTab(), at: 2)
        XCTAssertNil(badge.superview)
        XCTAssertEqual(bar.control(for: 2).subviews.count, 1)
    }

    func testControllerContentFillsThePaneAndReceivesComposableInsets() {
        let controller = TabBarController()
        controller.bar = .init(height: 0)
        controller._frameRect = NSMakeRect(0, 0, 380, 700)
        controller.loadViewIfNeeded()
        let child = ViewController()
        child.bar = .init(height: 0)
        controller.add(tab: makeTab(controller: child))
        controller.select(index: 0)
        XCTAssertEqual(child.view.frame, controller.bounds)
        XCTAssertEqual(child.containerContentInsets.bottom, 64)
        controller.updateContainerContentInsets(NSEdgeInsets(top: 0, left: 0, bottom: 12, right: 0), transition: .immediate)
        XCTAssertEqual(child.containerContentInsets.bottom, 76)
        controller.hideTabView(true)
        XCTAssertEqual(child.view.frame, controller.bounds)
        XCTAssertEqual(child.containerContentInsets.bottom, 12)
        controller.hideTabView(false)
        XCTAssertEqual(child.containerContentInsets.bottom, 76)
    }

    func testAccessibilityPressSelectsOnceAndReportsSelection() {
        let bar = makeBar()
        let delegate = TabSelectionDelegate()
        bar.delegate = delegate
        XCTAssertEqual(bar.accessibilityRole(), .tabGroup)
        XCTAssertEqual(bar.control(for: 2).accessibilityRole(), .radioButton)
        XCTAssertTrue(bar.control(for: 2).accessibilityPerformPress())
        XCTAssertEqual(delegate.changes, [2])
        XCTAssertTrue(bar.control(for: 2).isAccessibilitySelected())
        XCTAssertFalse(bar.control(for: 0).isAccessibilitySelected())
    }

    func testQuickMenuHighlightDoesNotChangeTabSelectionOrLeaveAnAccentedIcon() {
        let bar = makeBar(selected: 3)
        bar.control(for: 3).isSelected = false
        bar.setSelectedIndex(2, respondToDelegate: false, animated: false)
        let previousIcon = bar.control(for: 3).subviews[0] as! ImageView
        XCTAssertTrue(previousIcon.image === bar.tab(at: 3).image)
        bar.control(for: 1).isSelected = true
        XCTAssertFalse(bar.control(for: 1).isAccessibilitySelected())
        XCTAssertTrue(bar.control(for: 2).isAccessibilitySelected())
        XCTAssertEqual(bar.selectedIndex, 2)
    }

    func testWindowResignationCancelsAPendingSelection() {
        let bar = makeBar(selected: 2)
        let window = NSWindow(contentRect: bar.bounds, styleMask: .borderless, backing: .buffered, defer: true)
        window.contentView = bar
        bar.beginSelection(at: center(bar, 0))
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        XCTAssertFalse(bar.isTrackingSelection)
        XCTAssertEqual(bar.selectedIndex, 2)
    }

    func testContextActionKeepsItsItemAfterInsertion() {
        let bar = makeBar()
        var calls = 0
        let original = makeTab()
        let item = TabItem(image: original.image, selectedImage: original.selectedImage, controller: original.controller, longHoverHandler: { _ in calls += 1 })
        bar.addTab(item)
        bar.insertTab(makeTab(), at: 1)
        bar.control(for: 5).send(event: .RightDown)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(bar.selectedIndex, 0)
    }

    func testControlClickDoesNotSelectWhenTheModifierIsReleasedFirst() throws {
        let bar = makeBar()
        let original = makeTab()
        var contextActions = 0
        bar.addTab(TabItem(image: original.image, selectedImage: original.selectedImage, controller: original.controller, longHoverHandler: { _ in contextActions += 1 }))
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: .control, timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 0.1, windowNumber: 0, context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
        bar.control(for: 4).mouseDown(with: down)
        bar.control(for: 4).mouseUp(with: up)
        XCTAssertEqual(contextActions, 1)
        XCTAssertEqual(bar.selectedIndex, 0)
        XCTAssertFalse(bar.isTrackingSelection)
    }

    func testNavigationAndSearchSectionsForwardInsetsBeforeLoading() {
        let first = ViewController()
        let second = ViewController()
        let sections = SectionViewController(sections: [SectionControllerItem(title: { "First" }, controller: first), SectionControllerItem(title: { "Second" }, controller: second)])
        let window = Window(contentRect: NSMakeRect(0, 0, 380, 700), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let navigation = NavigationViewController(sections, window)
        navigation.cleanupAfterDeinit = false
        let insets = NSEdgeInsets(top: 0, left: 0, bottom: 56, right: 0)
        navigation.updateContainerContentInsets(insets, transition: .immediate)
        XCTAssertEqual(first.containerContentInsets.bottom, 56)
        XCTAssertEqual(second.containerContentInsets.bottom, 56)
        XCTAssertFalse(first.isLoaded())
        XCTAssertFalse(second.isLoaded())
        navigation.updateContainerContentInsets(NSEdgeInsets(), transition: .immediate)
        XCTAssertEqual(first.containerContentInsets.bottom, 0)
        XCTAssertEqual(second.containerContentInsets.bottom, 0)
    }
}
