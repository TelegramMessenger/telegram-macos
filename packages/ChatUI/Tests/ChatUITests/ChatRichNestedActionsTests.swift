import AppKit
import XCTest
import Postbox
import TelegramCore
import InAppSettings
import TelegramTheme
@testable import InstantPageUI
@testable import ChatUI

final class ChatRichNestedActionsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    private func layout(_ blocks: [InstantPageBlock]) -> InstantPageV2Layout {
        let page = InstantPage(blocks: blocks, media: [:], isComplete: true, rtl: false, url: "", views: nil)
        let content = TelegramMediaWebpageLoadedContent(url: "", displayUrl: "", hash: 0, type: nil, websiteName: nil, title: nil, text: nil, embedUrl: nil, embedType: nil, embedSize: nil, duration: nil, author: nil, isMediaLargeByDefault: nil, imageIsVideoCover: false, image: nil, file: nil, story: nil, attributes: [], instantPage: page)
        return layoutInstantPageV2(webpage: TelegramMediaWebpage(webpageId: MediaId(namespace: 0, id: 0), content: .Loaded(content)), instantPage: page, boundingWidth: 320, horizontalInset: 0, theme: instantPageThemeForType(.light, settings: InstantViewAppearance.defaultSettings), unsupportedStyle: ChatUnsupportedPapercutStyle.make(presentation: theme, isBubbled: false, tornEdges: false))
    }

    private func table(_ body: InstantPageV2Layout) -> InstantPageV2Layout {
        let frame = CGRect(x: 0, y: 0, width: 320, height: body.contentSize.height + 20)
        let cell = InstantPageV2TableCell(frame: frame, isHeader: false, horizontalAlignment: .left, verticalAlignment: .top, backgroundColor: nil, subLayout: body)
        let table = InstantPageV2TableItem(frame: frame, titleSubLayout: nil, titleFrame: nil, contentSize: frame.size, cells: [cell], horizontalLines: [], verticalLines: [], outerFrame: frame, outerCornerRadius: 0, bordered: false, striped: false, borderColor: .clear)
        return InstantPageV2Layout(contentSize: frame.size, items: [.table(table)], detailsIndices: [])
    }

    private func host(_ layout: InstantPageV2Layout) -> (InstantPageV2View, NSWindow) {
        let view = InstantPageV2View(frame: CGRect(x: 0, y: 0, width: 320, height: max(200, layout.contentSize.height)))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.update(layout: layout, theme: instantPageThemeForType(.light, settings: InstantViewAppearance.defaultSettings))
        return (view, window)
    }

    private func click(_ view: InstantPageV2View, point: CGPoint, window: NSWindow) throws {
        let location = view.convert(point, to: nil)
        let down = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let up = try XCTUnwrap(NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [], timestamp: 0.1, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0))
        view.mouseDown(with: down)
        view.mouseUp(with: up)
    }

    private func unsupportedPoint(_ layout: InstantPageV2Layout) throws -> CGPoint {
        let item = try XCTUnwrap(layout.items.compactMap { if case let .unsupported(item) = $0 { return item }; return nil }.first)
        let rect = item.layout.pillRect(in: item.frame)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    private func buttonPoint(_ layout: InstantPageV2Layout) throws -> CGPoint {
        let row = try XCTUnwrap(layout.items.compactMap { if case let .buttonRow(row) = $0 { return row }; return nil }.first)
        let rect = try XCTUnwrap(row.buttons.first).frame.offsetBy(dx: row.frame.minX, dy: row.frame.minY)
        return CGPoint(x: rect.midX, y: rect.midY)
    }

    func testButtonInTableUsesCallbackAssignedAfterLayout() throws {
        let button = InstantPageButton(text: .plain("Open"), action: .url("https://telegram.org"), color: nil)
        let inner = layout([.buttonRow(alignment: .left, buttons: [button])])
        let (view, window) = host(table(inner))
        defer { window.close() }
        var tapped: [InstantPageButton] = []
        view.buttonTapped = { tapped.append($0) }
        try click(view, point: buttonPoint(inner), window: window)
        XCTAssertEqual(tapped, [button])
    }

    func testButtonInDetailsUsesCallbackAssignedAfterLayout() throws {
        let button = InstantPageButton(text: .plain("Open"), action: .url("https://telegram.org"), color: nil)
        let content = layout([.details(title: .plain("More"), blocks: [.buttonRow(alignment: .left, buttons: [button])], expanded: true)])
        let (view, window) = host(content)
        defer { window.close() }
        let body = try XCTUnwrap(view.subviews.compactMap { $0 as? InstantPageV2View }.first)
        let inner = try XCTUnwrap(content.items.compactMap { if case let .details(item) = $0 { return item.innerLayout }; return nil }.first)
        var tapped: [InstantPageButton] = []
        view.buttonTapped = { tapped.append($0) }
        try click(body, point: buttonPoint(inner), window: window)
        XCTAssertEqual(tapped, [button])
    }

    func testUpdateInDetailsUsesCurrentRootCallback() throws {
        let content = layout([.details(title: .plain("More"), blocks: [.unsupported], expanded: true)])
        let (view, window) = host(content)
        defer { window.close() }
        let body = try XCTUnwrap(view.subviews.compactMap { $0 as? InstantPageV2View }.first)
        let inner = try XCTUnwrap(content.items.compactMap { if case let .details(item) = $0 { return item.innerLayout }; return nil }.first)
        var calls = 0
        view.unsupportedTapped = { calls += 1 }
        try click(body, point: unsupportedPoint(inner), window: window)
        view.unsupportedTapped = { calls += 10 }
        try click(body, point: unsupportedPoint(inner), window: window)
        XCTAssertEqual(calls, 11)
    }

    func testUpdateInTableReachesRoot() throws {
        let inner = layout([.unsupported])
        let (view, window) = host(table(inner))
        defer { window.close() }
        var calls = 0
        view.unsupportedTapped = { calls += 1 }
        try click(view, point: unsupportedPoint(inner), window: window)
        XCTAssertEqual(calls, 1)
    }

    func testTopLevelUpdateStillWorks() throws {
        let content = layout([.unsupported])
        let (view, window) = host(content)
        defer { window.close() }
        var calls = 0
        view.unsupportedTapped = { calls += 1 }
        try click(view, point: unsupportedPoint(content), window: window)
        XCTAssertEqual(calls, 1)
    }
}
