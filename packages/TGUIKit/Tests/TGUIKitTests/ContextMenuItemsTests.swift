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

    func testItemsProviderRunsOnceWhenLoaded() {
        let menu = ContextMenu()
        let items = makeItems(2)
        var calls = 0
        menu.itemsProvider = {
            calls += 1
            return items
        }

        XCTAssertEqual(calls, 0)
        XCTAssertEqual(menu.numberOfItems, 0)

        menu.loadProvidedItems()
        menu.loadProvidedItems()

        XCTAssertEqual(calls, 1)
        XCTAssertNil(menu.itemsProvider)
        assertNativeItems(menu, are: items)
    }

    func testItemsProviderLoadsImmediatelyForNativeMenus() {
        System.legacyMenu = true
        let menu = ContextMenu()
        let items = makeItems(2)

        menu.itemsProvider = { items }

        XCTAssertNil(menu.itemsProvider)
        assertNativeItems(menu, are: items)
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
