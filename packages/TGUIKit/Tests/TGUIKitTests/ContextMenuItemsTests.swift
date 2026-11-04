import Cocoa
import XCTest
import SwiftSignalKit
@testable import TGUIKit

final class ContextMenuItemsTests: XCTestCase {
    private var previousLegacyMenu = true

    override func setUp() {
        TGUIKitTestBootstrap.install()
        previousLegacyMenu = System.legacyMenu
        System.legacyMenu = false
    }

    override func tearDown() {
        System.legacyMenu = previousLegacyMenu
    }

    private func menuView(_ window: NSWindow?) -> MenuView? {
        window?.contentView?.subviews.first as? MenuView
    }

    private func makeItems(_ count: Int) -> [ContextMenuItem] {
        (0..<count).map { ContextMenuItem("Item \($0)") }
    }

    private func assertNativeItems(_ menu: ContextMenu, are expected: [NSMenuItem], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(menu.numberOfItems, expected.count, file: file, line: line)
        XCTAssertEqual(menu.items.count, expected.count, file: file, line: line)
        for (index, item) in expected.enumerated() where index < menu.numberOfItems {
            XCTAssertTrue(menu.item(at: index) === item, "native item \(index)", file: file, line: line)
            XCTAssertTrue(menu.items[index] === item, "stored item \(index)", file: file, line: line)
        }
    }

    func testAddItemKeepsNativeItemsInOrder() {
        let menu = ContextMenu()
        let items = makeItems(5)
        items.forEach(menu.addItem)
        assertNativeItems(menu, are: items)
    }

    func testAddItemInsertsEachItemOnce() {
        let menu = ContextMenu()
        var insertions = 0
        let observer = NotificationCenter.default.addObserver(forName: NSMenu.didAddItemNotification, object: menu, queue: nil) { _ in
            insertions += 1
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        makeItems(100).forEach(menu.addItem)

        XCTAssertEqual(insertions, 100)
    }

    func testAddItemNotifiesItemsObservers() {
        let menu = ContextMenu()
        var observedCounts: [Int] = []
        let observation = menu.observe(\._items, options: [.new]) { _, change in
            observedCounts.append(change.newValue?.count ?? 0)
        }
        defer { observation.invalidate() }

        makeItems(3).forEach(menu.addItem)

        XCTAssertEqual(observedCounts, [1, 2, 3])
    }

    func testItemsSetterReplacesNativeItems() {
        let menu = ContextMenu()
        makeItems(3).forEach(menu.addItem)
        let replacement = makeItems(2)

        menu.items = replacement

        assertNativeItems(menu, are: replacement)
    }

    func testAddItemAfterItemsSetterAppends() {
        let menu = ContextMenu()
        let initial = makeItems(2)
        menu.items = initial
        let appended = ContextMenuItem("Appended")

        menu.addItem(appended)

        assertNativeItems(menu, are: initial + [appended])
    }

    func testAsyncItemsProviderStartsOnceAndFillsMenuWhenLoaded() {
        let menu = ContextMenu()
        let items = makeItems(3)
        var calls = 0
        var complete: (([NSMenuItem]) -> Void)?
        menu.asyncItemsProvider = { completion in
            calls += 1
            complete = completion
            return EmptyDisposable
        }

        XCTAssertEqual(calls, 0)

        menu.loadAsyncItems()
        menu.loadAsyncItems()

        XCTAssertEqual(calls, 1)
        XCTAssertNil(menu.asyncItemsProvider)
        XCTAssertTrue(menu.isLoadingAsyncItems)
        XCTAssertEqual(menu.numberOfItems, 0)

        var loadedCalls = 0
        menu.asyncItemsLoaded = {
            loadedCalls += 1
        }
        complete?(items)

        XCTAssertFalse(menu.isLoadingAsyncItems)
        XCTAssertEqual(loadedCalls, 1)
        XCTAssertNil(menu.asyncItemsLoaded)
        assertNativeItems(menu, are: items)
    }

    func testAsyncItemsProviderCompletingSynchronouslyIsNotLoading() {
        let menu = ContextMenu()
        let items = makeItems(2)
        menu.asyncItemsProvider = { completion in
            completion(items)
            return EmptyDisposable
        }

        menu.loadAsyncItems()

        XCTAssertFalse(menu.isLoadingAsyncItems)
        assertNativeItems(menu, are: items)
    }

    func testAsyncItemsProviderLoadsImmediatelyForNativeMenus() {
        System.legacyMenu = true
        let menu = ContextMenu()
        var calls = 0

        menu.asyncItemsProvider = { _ in
            calls += 1
            return EmptyDisposable
        }

        XCTAssertEqual(calls, 1)
        XCTAssertNil(menu.asyncItemsProvider)
    }

    func testPressingLoadingSubmenuRowWhileSiblingSubmenuIsOpenPresentsItWhenLoaded() throws {
        let window = Window(contentRect: NSMakeRect(0, 0, 200, 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let anchor = NSView(frame: NSMakeRect(0, 0, 100, 100))
        window.contentView?.addSubview(anchor)

        let open = ContextMenuItem("Open")
        let openSubmenu = ContextMenu()
        openSubmenu.addItem(ContextMenuItem("Nested"))
        open.submenu = openSubmenu
        let loading = ContextMenuItem("Loading")
        let loadingSubmenu = ContextMenu()
        var complete: (([NSMenuItem]) -> Void)?
        loadingSubmenu.asyncItemsProvider = { completion in
            complete = completion
            return EmptyDisposable
        }
        loading.submenu = loadingSubmenu
        let menu = ContextMenu()
        [open, loading].forEach(menu.addItem)

        let controller = AppMenuController(menu, presentation: .current(PresentationTheme.current.colors), holder: AppMenu(menu: menu), betterInside: false, appearMode: .click, parentView: anchor)
        defer { controller.close() }
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: NSMakePoint(5, 5), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 0))
        controller.present(event: event, view: anchor)

        let root = try XCTUnwrap(NSApp.windows.compactMap(menuView).first { $0.controller === controller })
        root.layoutSubtreeIfNeeded()
        let openRow = try XCTUnwrap(root.item(for: open.id))
        let loadingRow = try XCTUnwrap(root.item(for: loading.id))

        XCTAssertTrue(openRow.accessibilityPerformPress())
        XCTAssertEqual(menuView(root.childView)?.submenuId, open.id)

        XCTAssertTrue(loadingRow.accessibilityPerformPress())
        XCTAssertNil(root.childView)
        XCTAssertTrue(loadingRow.isSelected)

        complete?([ContextMenuItem("Topic")])
        XCTAssertEqual(menuView(root.childView)?.submenuId, loading.id)
    }

    func testAsyncItemsLoadingIsDisposedWithMenu() {
        var disposed = false
        autoreleasepool {
            let menu = ContextMenu()
            menu.asyncItemsProvider = { _ in
                ActionDisposable {
                    disposed = true
                }
            }
            menu.loadAsyncItems()
            XCTAssertFalse(disposed)
        }
        XCTAssertTrue(disposed)
    }
}
