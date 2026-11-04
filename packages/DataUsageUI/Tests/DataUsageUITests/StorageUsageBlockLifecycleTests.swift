import AppKit
import XCTest
import TGUIKit
import GeneralRows
import TelegramTheme
import ColorPalette
import InAppSettings
import ThemeSettings
@testable import DataUsageUI

private final class MediaView: View {
    let table = TableView(frame: .zero)
    let header = View()

    required init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(header)
        addSubview(table)
        for id in 0 ..< 100 {
            _ = table.addItem(item: TableRowItem(.zero, stableId: id))
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        header.frame = NSMakeRect(30, 30, max(0, frame.width - 60), 56)
        table.frame = NSMakeRect(30, 86, max(0, frame.width - 60), max(0, frame.height - 86))
    }
}

private final class MediaController: ViewController, StorageUsageBlockControlling {
    var mediaView: View { view as! MediaView }
    var mainTable: TableView? { (mediaView as! MediaView).table }
    var unableToHide: Bool { false }
    var currentMainTableView: ((TableView?, Bool, Bool) -> Void)? {
        didSet { currentMainTableView?(mainTable, false, false) }
    }
    private(set) var detachedOnDisappear = false

    override func viewClass() -> AnyClass { MediaView.self }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        detachedOnDisappear = mediaView.superview == nil
    }
}

final class StorageUsageBlockLifecycleTests: XCTestCase {
    private static var images: [NSImage] = []

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        System.updateScaleFactor(2)
        System.liquidGlass = false
        let image = NSImage(size: NSMakeSize(16, 16), flipped: false) { rect in
            NSColor.black.setFill()
            rect.insetBy(dx: 4, dy: 4).fill()
            return true
        }
        for name in ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand", "Icon_CopyCode"] {
            let named = image.copy() as! NSImage
            _ = named.setName(name)
            Self.images.append(named)
        }
        GeneralRowsHooks.install(.placeholder)
        TelegramThemeHooks.install(.init(image: { _ in image }, icons: { generateIcons(from: $0, bubbled: $1) }, sendingFrame: { generateSendingFrame($0) }, clockMinImage: { generateClockMinImage($0) }, chatGroupToggleSelected: { generateChatGroupToggleSelected(foregroundColor: $0, backgroundColor: $1) }, chatGroupToggleUnselected: { generateChatGroupToggleUnselected(foregroundColor: $0, backgroundColor: $1) }, setDefaultTheme: { _ in }, liteMode: { .standart }, darkAppearance: { theme }, liveStreamBadgeColor: { .systemRed }))
        telegramUpdateTheme(generateTheme(palette: dayClassicPalette, cloudTheme: nil, bubbled: false, fontSize: 13, wallpaper: .init(), liquidGlass: false), window: nil, animated: false)
    }

    private func pump(_ table: TableView) {
        table.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        table.layoutSubtreeIfNeeded()
    }

    private func withBlock(_ body: (StorageUsageTableView, MediaController, StorageUsageBlockItem, TableRowView) throws -> Void) throws {
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 500, 600), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let table = StorageUsageTableView(frame: window.contentView!.bounds)
        table.contentInsets.top = 50
        table.verticalScrollElasticity = .none
        window.contentView!.addSubview(table)
        for id in 0 ..< 30 {
            _ = table.addItem(item: TableRowItem(.zero, stableId: id))
        }
        let controller = MediaController()
        controller._frameRect = table.bounds
        let block = StorageUsageBlockItem(table.bounds.size, stableId: 500, controller: controller, isVisible: true, viewType: .singleItem)
        _ = table.addItem(item: block)
        pump(table)
        table.clipView.scroll(to: NSMakePoint(0, table.rectOf(item: block).minY - 64))
        pump(table)
        let row = try XCTUnwrap(table.viewNecessary(at: block.index))
        try body(table, controller, block, row)
        table.clipView.updateBounds(to: .zero, cancel: true)
    }

    func testClearingDetachesMediaEvenWhenAppKitKeepsTheRowAlive() throws {
        for inset in [CGFloat(64), 200, 800] {
            try withBlock { table, controller, block, row in
                table.clipView.scroll(to: NSMakePoint(0, table.rectOf(item: block).minY - inset))
                pump(table)
                controller.mainTable?.removeAll()
                _ = table.merge(with: .init(deleted: [block.index], inserted: [], updated: [], animated: false))
                XCTAssertNil(controller.mediaView.superview)
                XCTAssertTrue(controller.detachedOnDisappear)
                XCTAssertNil(table.prepareForResize)
                XCTAssertNil(table._scrollWillStartLiveScrolling)
                XCTAssertNil(controller.currentMainTableView)
                XCTAssertNil(controller.mainTable?.applyExternalScroll)
                let recycled = (block.viewClass() as! TableRowView.Type).init(frame: row.frame)
                recycled.set(item: block, animated: false)
                XCTAssertNil(controller.mediaView.superview)
                table.scroll(to: .up(false))
                for size in [NSMakeSize(900, 600), NSMakeSize(400, 800), NSMakeSize(700, 450)] {
                    table.setFrameSize(size)
                    row.setFrameOrigin(.zero)
                    row.viewDidMoveToSuperview()
                    pump(table)
                    XCTAssertNil(controller.mediaView.superview)
                }
                withExtendedLifetime((block, row)) {}
            }
        }
    }

    func testStaleTabAndResizeCallbacksCannotMoveTheClearedScreen() throws {
        try withBlock { table, controller, block, row in
            table.scroll(to: .up(false))
            pump(table)
            let oldMediaCallback = controller.currentMainTableView
            let oldResizeCallback = table.prepareForResize
            oldMediaCallback?(controller.mainTable, true, true)
            _ = table.merge(with: .init(deleted: [block.index], inserted: [], updated: [], animated: false))
            let offset = table.liveDocumentOffset
            oldMediaCallback?(controller.mainTable, true, true)
            let restore = oldResizeCallback?()
            restore?()
            pump(table)
            XCTAssertEqual(table.liveDocumentOffset, offset)
            XCTAssertNil(controller.mediaView.superview)
            XCTAssertNil(controller.mainTable?.applyExternalScroll)
            withExtendedLifetime((block, row)) {}
        }
    }

    func testMediaCanBeAttachedAgainWithoutOldRowsChangingItsFrame() throws {
        try withBlock { table, controller, block, row in
            _ = table.merge(with: .init(deleted: [block.index], inserted: [], updated: [], animated: false))
            let replacement = StorageUsageBlockItem(table.bounds.size, stableId: 500, controller: controller, isVisible: true, viewType: .singleItem)
            _ = table.merge(with: .init(deleted: [], inserted: [(table.count, replacement)], updated: [], animated: false))
            table.clipView.scroll(to: NSMakePoint(0, table.rectOf(item: replacement).minY - 64))
            pump(table)
            XCTAssertTrue(controller.mediaView.superview === table.documentView)
            XCTAssertNotNil(controller.currentMainTableView)
            XCTAssertNotNil(controller.mainTable?.applyExternalScroll)
            let frame = controller.mediaView.frame
            row.set(item: block, animated: false)
            row.setFrameOrigin(.zero)
            pump(table)
            XCTAssertEqual(controller.mediaView.frame, frame)
            withExtendedLifetime((block, row)) {}
        }
    }

    func testPinnedMediaStillKeepsItsPositionAfterResizing() throws {
        try withBlock { table, controller, _, _ in
            let inner = try XCTUnwrap(controller.mainTable)
            inner.clipView.scroll(to: NSMakePoint(0, 250))
            pump(table)
            for size in [NSMakeSize(500, 450), NSMakeSize(500, 750), NSMakeSize(700, 500), NSMakeSize(400, 600)] {
                table.setFrameSize(size)
                pump(table)
                let media = controller.mediaView as! MediaView
                XCTAssertEqual(table.convert(media.header.bounds, from: media.header).minY, 94, accuracy: 0.5)
                XCTAssertEqual(table.convert(inner.bounds, from: inner).maxY, size.height, accuracy: 0.5)
                XCTAssertEqual(inner.liveDocumentOffset.y, 250, accuracy: 0.5)
            }
        }
    }

    func testOverflowingTabsCanScrollWithAVerticalMouseWheel() throws {
        let tabs = SegmentContainerView(frame: NSMakeRect(0, 0, 120, 56))
        tabs.update(collections: [.peers, .media, .files, .music, .voice], selected: .peers, animated: false)
        tabs.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(tabs.subviews.first as? HorizontalScrollView)
        let document = try XCTUnwrap(scroll.documentView)
        XCTAssertGreaterThan(document.frame.width, scroll.frame.width)
        scroll.clipView.scroll(to: NSMakePoint((document.frame.width - scroll.frame.width) / 2, 0))
        let before = scroll.clipView.bounds.origin
        scroll.scrollWheel(with: VerticalWheelEvent())
        XCTAssertNotEqual(scroll.clipView.bounds.origin.x, before.x)
        XCTAssertEqual(scroll.clipView.bounds.origin.y, 0)
    }
}

private final class VerticalWheelEvent: NSEvent {
    override var scrollingDeltaY: CGFloat { 40 }
    override var scrollingDeltaX: CGFloat { 0 }
}
