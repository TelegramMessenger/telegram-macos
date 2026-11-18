import AppKit
import XCTest
@testable import TGUIKit

private final class ContinuousDragWindow: NSWindow {
    var pointer = NSPoint.zero

    override var mouseLocationOutsideOfEventStream: NSPoint {
        return pointer
    }
}

private final class ContinuousDragDelegate: SplitViewDelegate {
    weak var split: SplitView?
    let leading = ViewController(frame: NSRect(x: 0, y: 0, width: 300, height: 300))
    let trailing = ViewController(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    var fullWidth: CGFloat = 300
    var compact = false
    var resizePoints: [CGFloat] = []
    var states: [SplitViewState] = []

    func splitViewDidNeedSwapToLayout(state: SplitViewState) {
        guard let split else { return }
        states.append(state)
        if split.contains(controller: leading) {
            split.removeController(controller: leading)
        }
        if split.contains(controller: trailing) {
            split.removeController(controller: trailing)
        }
        compact = state == .minimisize
        split.mustMinimisize = compact
        if state == .dual || state == .minimisize {
            let width = compact ? 90 : fullWidth
            split.insertController(controller: leading, proportion: SplitProportion(min: width, max: width), at: split.fixedControllerCount)
            split.insertController(controller: trailing, proportion: SplitProportion(min: 380, max: .greatestFiniteMagnitude), at: split.fixedControllerCount + 1)
        } else if state == .single {
            split.insertController(controller: trailing, proportion: SplitProportion(min: 380, max: .greatestFiniteMagnitude), at: split.fixedControllerCount)
        }
    }

    func splitViewDidNeedMinimisize(controller: ViewController) {}
    func splitViewDidNeedFullsize(controller: ViewController) {}
    func splitViewIsCanMinimisize() -> Bool { true }
    func splitViewDrawBorder() -> Bool { false }

    func splitViewShouldResize(at point: NSPoint) {
        guard let split else { return }
        resizePoints.append(point.x)
        if !compact {
            let width = round(min(max(point.x - split.fixedLeadingWidth, 300), split.frame.width - 380 - split.fixedLeadingWidth))
            fullWidth = width
            split.updateStartSize(size: NSSize(width: width, height: width), controller: leading)
        }
    }

    func splitResizeCursor(at point: NSPoint) -> NSCursor? {
        return compact ? .resizeRight : .resizeLeftRight
    }
}

private final class ContinuousDragFixture {
    let window: ContinuousDragWindow
    let split: SplitView
    let delegate = ContinuousDragDelegate()
    let overlay: Control
    private let sidebar: ViewController?
    private var eventNumber = 0

    init(width: CGFloat = 1000, fixedLeadingWidth: CGFloat = 0) throws {
        window = ContinuousDragWindow(contentRect: NSRect(x: -10000, y: -10000, width: width, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        split = SplitView(frame: NSRect(x: 0, y: 0, width: width, height: 300))
        split.collapseToSingle = true
        split.setProportion(proportion: SplitProportion(min: 650, max: 1250), state: .dual)
        window.contentView = split
        delegate.split = split
        split.delegate = delegate
        if fixedLeadingWidth > 0 {
            let controller = ViewController(frame: NSRect(x: 0, y: 0, width: fixedLeadingWidth, height: 300))
            sidebar = controller
            split.addController(controller: controller, proportion: SplitProportion(min: fixedLeadingWidth, max: fixedLeadingWidth))
            split.setFixed(controller: controller, fixed: true)
        } else {
            sidebar = nil
        }
        split.state = .dual
        split.layoutSubtreeIfNeeded()
        split.layout()
        overlay = try XCTUnwrap(split.subviews.compactMap { $0 as? Control }.first)
        window.pointer = NSPoint(x: overlay.frame.midX, y: 150)
        window.orderBack(nil)
        XCTAssertTrue(overlay.mouseInside())
    }

    var width: CGFloat { delegate.leading.view.frame.width }

    func send(_ type: NSEvent.EventType, x: CGFloat) throws {
        window.pointer = NSPoint(x: x, y: 150)
        eventNumber += 1
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: window.pointer, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: eventNumber, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
        window.sendEvent(event)
        split.layoutSubtreeIfNeeded()
        split.layout()
    }

    func begin() throws {
        let x = overlay.frame.midX
        try send(.leftMouseDown, x: x)
        try send(.leftMouseDragged, x: x - 10)
    }

    func expandAfterCollapse() throws {
        try begin()
        try send(.leftMouseDragged, x: 80)
        XCTAssertEqual(split.state, .minimisize)
        XCTAssertEqual(width, 90)
        try send(.leftMouseDragged, x: 220)
        XCTAssertEqual(split.state, .dual)
        XCTAssertTrue(overlay.window === window)
    }

    deinit {
        window.close()
    }
}

final class SplitViewContinuousDragTests: XCTestCase {
    private var previousCursor: NSCursor!

    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
        previousCursor = NSCursor.current
    }

    override func tearDown() {
        previousCursor.set()
        super.tearDown()
    }

    func testExpansionKeepsReceivingDraggedEventsWithoutAnotherMouseDown() throws {
        let fixture = try ContinuousDragFixture()
        try fixture.expandAfterCollapse()
        let delivered = fixture.delegate.resizePoints.count
        try fixture.send(.leftMouseDragged, x: 500)
        XCTAssertEqual(fixture.delegate.resizePoints.count, delivered + 1)
        XCTAssertEqual(fixture.width, 500)
        try fixture.send(.leftMouseDragged, x: 350)
        XCTAssertEqual(fixture.width, 350)
        try fixture.send(.leftMouseUp, x: 350)
    }

    func testMultipleCollapseExpansionCyclesWorkInOneGesture() throws {
        let fixture = try ContinuousDragFixture()
        try fixture.begin()
        for _ in 0 ..< 3 {
            try fixture.send(.leftMouseDragged, x: 80)
            XCTAssertEqual(fixture.split.state, .minimisize)
            try fixture.send(.leftMouseDragged, x: 220)
            XCTAssertEqual(fixture.split.state, .dual)
            try fixture.send(.leftMouseDragged, x: 480)
            XCTAssertEqual(fixture.width, 480)
        }
        try fixture.send(.leftMouseUp, x: 480)
    }

    func testExpandedGestureCanReverseAfterHittingMaximumWidth() throws {
        let fixture = try ContinuousDragFixture()
        try fixture.expandAfterCollapse()
        try fixture.send(.leftMouseDragged, x: 900)
        XCTAssertEqual(fixture.width, 620)
        try fixture.send(.leftMouseDragged, x: 450)
        XCTAssertEqual(fixture.width, 450)
        try fixture.send(.leftMouseDragged, x: 320)
        XCTAssertEqual(fixture.width, 320)
        try fixture.send(.leftMouseUp, x: 320)
    }

    func testFixedFolderSidebarDoesNotInterruptExpandedGesture() throws {
        let fixture = try ContinuousDragFixture(fixedLeadingWidth: 70)
        try fixture.expandAfterCollapse()
        try fixture.send(.leftMouseDragged, x: 570)
        XCTAssertEqual(fixture.width, 500)
        try fixture.send(.leftMouseDragged, x: 430)
        XCTAssertEqual(fixture.width, 360)
        XCTAssertEqual(fixture.split.fixedLeadingWidth, 70)
        try fixture.send(.leftMouseUp, x: 430)
    }

    func testNormalResizeKeepsMinimumAndMaximumLimits() throws {
        let fixture = try ContinuousDragFixture()
        try fixture.begin()
        try fixture.send(.leftMouseDragged, x: 450)
        XCTAssertEqual(fixture.width, 450)
        try fixture.send(.leftMouseDragged, x: 150)
        XCTAssertEqual(fixture.width, 300)
        try fixture.send(.leftMouseDragged, x: 950)
        XCTAssertEqual(fixture.width, 620)
        try fixture.send(.leftMouseDragged, x: 380)
        XCTAssertEqual(fixture.width, 380)
        try fixture.send(.leftMouseUp, x: 380)
    }

    func testExpansionDoesNotEmitIntermediateNoneLayout() throws {
        let fixture = try ContinuousDragFixture()
        fixture.split.needMinimisize()
        fixture.split.layout()
        fixture.delegate.states.removeAll()
        fixture.split.needFullsize()
        fixture.split.layout()
        XCTAssertFalse(fixture.delegate.states.contains(.none))
        XCTAssertEqual(fixture.split.state, .dual)
        XCTAssertTrue(fixture.overlay.window === fixture.window)
    }

    func testFullsizeRefreshKeepsOngoingDrag() throws {
        let fixture = try ContinuousDragFixture()
        try fixture.begin()
        try fixture.send(.leftMouseDragged, x: 420)
        XCTAssertEqual(fixture.width, 420)
        fixture.split.needFullsize()
        fixture.split.layout()
        try fixture.send(.leftMouseDragged, x: 510)
        XCTAssertEqual(fixture.width, 510)
        try fixture.send(.leftMouseUp, x: 510)
    }

    func testExpansionInNarrowWindowStillChoosesSingleLayout() throws {
        let fixture = try ContinuousDragFixture()
        fixture.split.needMinimisize()
        fixture.split.layout()
        fixture.split.setFrameSize(NSSize(width: 600, height: 300))
        fixture.split.needFullsize()
        fixture.split.layout()
        XCTAssertEqual(fixture.split.state, .single)
        XCTAssertNil(fixture.overlay.superview)
    }

    func testTripleLayoutStillRemovesDivider() throws {
        let fixture = try ContinuousDragFixture()
        fixture.split.needMinimisize()
        fixture.split.layout()
        fixture.split.setProportion(proportion: SplitProportion(min: 650, max: 800), state: .dual)
        fixture.split.setProportion(proportion: SplitProportion(min: 800, max: .greatestFiniteMagnitude), state: .triple)
        fixture.split.needFullsize()
        fixture.split.layout()
        XCTAssertEqual(fixture.split.state, .triple)
        XCTAssertNil(fixture.overlay.superview)
    }
}
