import Cocoa
import XCTest
import SwiftSignalKit
import Darwin
@testable import TGUIKit

private final class LifecycleMenuItem: TableRowItem {
    var starts = 0
    var cancelled: [Int] = []
    var additionStarts = 0
    var additionCancellations = 0
    var onItems: (() -> Void)?
    var onStart: (() -> Void)?
    var onDispose: (() -> Void)?
    var onAddition: (() -> Void)?

    override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        onItems?()
        return Signal { [weak self] _ in
            guard let self else { return EmptyDisposable }
            self.starts += 1
            let request = self.starts
            self.onStart?()
            return ActionDisposable { [weak self] in
                self?.cancelled.append(request)
                self?.onDispose?()
            }
        }
    }

    override var menuAdditionView: Signal<Window?, NoError> {
        onAddition?()
        return Signal { [weak self] _ in
            self?.additionStarts += 1
            return ActionDisposable { [weak self] in self?.additionCancellations += 1 }
        }
    }
}

private final class StreamingMenuItem: TableRowItem {
    let additions = ValuePipe<Window?>()
    var cancellations = 0
    var onPresentation: (() -> Void)?

    override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> { .single([]) }

    override var menuAdditionView: Signal<Window?, NoError> {
        additions.signal() |> afterDisposed { [weak self] in self?.cancellations += 1 }
    }

    override var menuPresentation: AppMenu.Presentation {
        onPresentation?()
        return super.menuPresentation
    }
}

private final class MenuCallbackRow: TableRowView {
    var shown = 0
    var closed = 0
    override func onShowContextMenu() { shown += 1 }
    override func onCloseContextMenu() { closed += 1 }
}

private final class RightClickMenuRow: TableRowView {
    override func mouseInside() -> Bool { true }
}

final class TableRowMenuLifecycleTests: XCTestCase {
    private var previousLegacyMenu = true

    override func setUp() {
        TGUIKitTestBootstrap.install()
        previousLegacyMenu = System.legacyMenu
        System.legacyMenu = false
    }

    override func tearDown() { System.legacyMenu = previousLegacyMenu }

    private func close(_ menu: AppMenu) throws {
        let controller = try XCTUnwrap(Mirror(reflecting: menu).children.first { $0.label == "controller" }?.value as? AppMenuController)
        controller.close()
    }

    private func showCallback(_ menu: AppMenu) throws {
        let context = try XCTUnwrap(Mirror(reflecting: menu).children.first { $0.label == "menu" }?.value as? ContextMenu)
        context.onShow(context)
    }

    func testOldMenuCallbacksDoNotChangeNewMenu() throws {
        let view = MenuCallbackRow(frame: .zero)
        let item = StreamingMenuItem(.zero, stableId: 1)
        view.set(item: item)
        view.showContextMenu(event())
        item.additions.putNext(nil)
        let first = try XCTUnwrap(view.contextMenu)
        defer { try? close(first) }
        try showCallback(first)
        XCTAssertEqual(view.shown, 1)
        view.showContextMenu(event())
        item.additions.putNext(nil)
        let second = try XCTUnwrap(view.contextMenu)
        defer { try? close(second) }
        XCTAssertFalse(first === second)
        try showCallback(first)
        XCTAssertEqual(view.shown, 1)
        try close(first)
        XCTAssertTrue(view.contextMenu === second)
        XCTAssertEqual(view.closed, 0)
        try showCallback(second)
        XCTAssertEqual(view.shown, 2)
        try close(second)
        XCTAssertNil(view.contextMenu)
        XCTAssertEqual(view.closed, 1)
    }

    func testClosingMenuStopsAdditionWorkAndPreventsReopening() throws {
        let view = MenuCallbackRow(frame: .zero)
        let item = StreamingMenuItem(.zero, stableId: 1)
        view.set(item: item)
        view.showContextMenu(event())
        item.additions.putNext(nil)
        let menu = try XCTUnwrap(view.contextMenu)
        defer { try? close(menu) }
        XCTAssertEqual(item.cancellations, 0)
        try close(menu)
        XCTAssertEqual(item.cancellations, 1)
        item.additions.putNext(nil)
        XCTAssertNil(view.contextMenu)
        XCTAssertEqual(view.closed, 1)
    }

    func testQueuedBackgroundAdditionCannotPresentAfterReuse() {
        let view = MenuCallbackRow(frame: .zero)
        let item = StreamingMenuItem(.zero, stableId: 1)
        view.set(item: item)
        view.showContextMenu(event())
        let enqueued = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            item.additions.putNext(nil)
            enqueued.signal()
        }
        XCTAssertEqual(enqueued.wait(timeout: .now() + 2), .success)
        view.set(item: TableRowItem(.zero, stableId: 2))
        let drained = expectation(description: "Main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertNil(view.contextMenu)
        XCTAssertEqual(item.cancellations, 1)
        if let menu = view.contextMenu { try? close(menu) }
    }

    func testSynchronousCompletedRequestKeepsItsMenuCallbacks() throws {
        let view = MenuCallbackRow(frame: .zero)
        view.set(item: TableRowItem(.zero, stableId: 1))
        view.showContextMenu(event())
        let menu = try XCTUnwrap(view.contextMenu)
        defer { try? close(menu) }
        try showCallback(menu)
        XCTAssertEqual(view.shown, 1)
        try close(menu)
        XCTAssertEqual(view.closed, 1)
        XCTAssertNil(view.contextMenu)
    }

    func testReuseDuringPresentationDoesNotInstallStaleMenu() {
        let view = MenuCallbackRow(frame: .zero)
        let item = StreamingMenuItem(.zero, stableId: 1)
        item.onPresentation = { [weak view] in view?.set(item: TableRowItem(.zero, stableId: 2)) }
        view.set(item: item)
        view.showContextMenu(event())
        item.additions.putNext(nil)
        XCTAssertNil(view.contextMenu)
        XCTAssertEqual(item.cancellations, 1)
        if let menu = view.contextMenu { try? close(menu) }
    }

    private func event() -> NSEvent {
        NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: 5, y: 5), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 0)!
    }

    func testRightClickRequestsOnlyTheTelegramMenu() {
        let view = RightClickMenuRow(frame: .zero)
        let item = LifecycleMenuItem(.zero, stableId: 1)
        view.set(item: item)

        let click = event()
        let nativeMenu = view.menu(for: click)
        XCTAssertNil(nativeMenu)
        guard nativeMenu == nil else { return }

        view.rightMouseDown(with: click)
        XCTAssertEqual(item.starts, 1)
    }

    func testReuseCancelsBothPendingSources() {
        let view = TableRowView(frame: .zero)
        let old = LifecycleMenuItem(.zero, stableId: 1)
        view.set(item: old)
        view.showContextMenu(event())
        XCTAssertEqual(old.starts, 1)
        XCTAssertEqual(old.additionStarts, 1)
        view.set(item: TableRowItem(.zero, stableId: 2))
        XCTAssertEqual(old.cancelled, [1])
        XCTAssertEqual(old.additionCancellations, 1)
    }

    func testSameIdentityRefreshPreservesRequest() {
        let view = TableRowView(frame: .zero)
        let old = LifecycleMenuItem(.zero, stableId: 1)
        view.set(item: old)
        view.showContextMenu(event())
        view.set(item: TableRowItem(.zero, stableId: 1))
        XCTAssertTrue(old.cancelled.isEmpty)
        XCTAssertEqual(old.additionCancellations, 0)
        view.set(item: TableRowItem(.zero, stableId: 2))
        XCTAssertEqual(old.cancelled, [1])
    }

    func testReuseDuringSourceStartDisposesReturnedSubscription() {
        let view = TableRowView(frame: .zero)
        let old = LifecycleMenuItem(.zero, stableId: 1)
        let replacement = TableRowItem(.zero, stableId: 2)
        old.onStart = { [weak view] in view?.set(item: replacement) }
        view.set(item: old)
        view.showContextMenu(event())
        XCTAssertTrue(view.item === replacement)
        XCTAssertEqual(old.cancelled, [1])
        XCTAssertEqual(old.additionCancellations, old.additionStarts)
    }

    func testNewRequestDuringSourceStartKeepsNewestSubscription() {
        let view = TableRowView(frame: .zero)
        let item = LifecycleMenuItem(.zero, stableId: 1)
        let event = event()
        item.onStart = { [weak view, weak item] in
            item?.onStart = nil
            view?.showContextMenu(event)
        }
        view.set(item: item)
        view.showContextMenu(event)
        XCTAssertEqual(item.starts, 2)
        XCTAssertEqual(item.cancelled, [1])
        view.set(item: TableRowItem(.zero, stableId: 2))
        XCTAssertEqual(item.cancelled, [1, 2])
    }

    func testNewRequestDuringDisposalSupersedesOuterRequest() {
        let view = TableRowView(frame: .zero)
        let item = LifecycleMenuItem(.zero, stableId: 1)
        let event = event()
        view.set(item: item)
        view.showContextMenu(event)
        item.onDispose = { [weak view, weak item] in
            item?.onDispose = nil
            view?.showContextMenu(event)
        }
        view.showContextMenu(event)
        XCTAssertEqual(item.starts, 2)
        XCTAssertEqual(item.cancelled, [1])
        view.set(item: TableRowItem(.zero, stableId: 2))
        XCTAssertEqual(item.cancelled, [1, 2])
    }

    func testReuseDuringItemsFactoryDoesNotStartStaleSources() {
        let view = TableRowView(frame: .zero)
        let item = LifecycleMenuItem(.zero, stableId: 1)
        item.onItems = { [weak view] in view?.set(item: TableRowItem(.zero, stableId: 2)) }
        view.set(item: item)
        view.showContextMenu(event())
        XCTAssertEqual(item.starts, 0)
        XCTAssertEqual(item.additionStarts, 0)
    }

    func testReuseDuringAdditionFactoryDoesNotStartStaleSources() {
        let view = TableRowView(frame: .zero)
        let item = LifecycleMenuItem(.zero, stableId: 1)
        item.onAddition = { [weak view] in view?.set(item: TableRowItem(.zero, stableId: 2)) }
        view.set(item: item)
        view.showContextMenu(event())
        XCTAssertEqual(item.starts, 0)
        XCTAssertEqual(item.additionStarts, 0)
    }

    func testReuseDisposalCanBindAndStartNewItem() {
        let view = TableRowView(frame: .zero)
        let item = LifecycleMenuItem(.zero, stableId: 1)
        let replacement = LifecycleMenuItem(.zero, stableId: 3)
        let event = event()
        view.set(item: item)
        view.showContextMenu(event)
        item.onDispose = { [weak view] in
            view?.set(item: replacement)
            view?.showContextMenu(event)
        }
        view.set(item: TableRowItem(.zero, stableId: 2))
        XCTAssertTrue(view.item === replacement)
        XCTAssertEqual(item.cancelled, [1])
        XCTAssertEqual(replacement.starts, 1)
        XCTAssertTrue(replacement.cancelled.isEmpty)
    }

    func testWindowDetachCancelsPendingSources() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        let view = TableRowView(frame: .zero)
        window.contentView?.addSubview(view)
        let item = LifecycleMenuItem(.zero, stableId: 1)
        view.set(item: item)
        view.showContextMenu(event())
        view.removeFromSuperview()
        XCTAssertNil(view.window)
        XCTAssertEqual(item.cancelled, [1])
        XCTAssertEqual(item.additionCancellations, 1)
    }

    func testPendingMenuDoesNotRetainRow() {
        let item = LifecycleMenuItem(.zero, stableId: 1)
        weak var released: TableRowView?
        autoreleasepool {
            let view = TableRowView(frame: .zero)
            released = view
            view.set(item: item)
            view.showContextMenu(event())
        }
        XCTAssertNil(released)
        XCTAssertEqual(item.cancelled, [1])
        XCTAssertEqual(item.additionCancellations, 1)
    }

    func testBindingCost() throws {
        guard let variant = ProcessInfo.processInfo.environment["ROW_MENU_BENCHMARK"] else { throw XCTSkip("Opt-in row binding benchmark") }
        let view = TableRowView(frame: .zero)
        let first = TableRowItem(.zero, stableId: 1), second = TableRowItem(.zero, stableId: 2)
        var results: [String: [Double]] = [:]
        for scenario in ["unused", "previously_used"] {
            if scenario == "previously_used" {
                view.set(item: LifecycleMenuItem(.zero, stableId: 3))
                view.showContextMenu(event())
            }
            for _ in 0..<1000 { view.set(item: first); view.set(item: second) }
            var samples: [Double] = []
            for _ in 0..<9 {
                let start = CACurrentMediaTime()
                for _ in 0..<10000 { view.set(item: first); view.set(item: second) }
                samples.append((CACurrentMediaTime() - start) * 1e6 / 20000)
            }
            results[scenario] = samples
        }
        let bytes = malloc_size(Unmanaged.passUnretained(view).toOpaque())
        try JSONSerialization.data(withJSONObject: ["unit": "microseconds_per_binding", "samples": results, "row_bytes": bytes], options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "/tmp/row-menu-\(variant).json"))
    }
}
