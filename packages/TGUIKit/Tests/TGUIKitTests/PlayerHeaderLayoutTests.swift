import AppKit
import XCTest
@testable import TGUIKit

private final class PlayerHeaderRow: TableRowItem {
    override var height: CGFloat { 80 }
}

private final class PlayerHeaderChatView: View {
    let table = TableView(frame: .zero, isFlipped: false)

    required init(frame: NSRect) {
        super.init(frame: frame)
        autoresizesSubviews = false
        addSubview(table)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        ContainedViewLayoutTransition.immediate.updateFrame(view: table, frame: bounds)
    }
}

private final class PlayerHeaderChat: ViewController {
    override func viewClass() -> AnyClass { PlayerHeaderChatView.self }
    override func viewDidLoad() { super.viewDidLoad(); readyOnce() }
    override func updateFrame(_ frame: NSRect, inset: CGFloat, transition: ContainedViewLayoutTransition) {
        super.updateFrame(frame, inset: inset, transition: transition)
        transition.updateFrame(view: (view as! PlayerHeaderChatView).table, frame: frame.size.bounds)
    }
}

final class PlayerHeaderLayoutTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    func testBottomUpFrameResizeKeepsBoundsOriginStable() throws {
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 600, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = View(frame: window.contentView!.bounds)
        let table = TableView(frame: root.bounds, isFlipped: false)
        root.addSubview(table)
        window.contentView = root
        for id in 0..<30 { _ = table.addItem(item: PlayerHeaderRow(table.frame.size, stableId: id)) }
        window.orderBack(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        for height: CGFloat in [648, 700] {
            ContainedViewLayoutTransition.animated(duration: 1, curve: .easeOut).updateFrame(view: table, frame: NSRect(x: 0, y: 0, width: 600, height: height))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            let layer = try XCTUnwrap(table.layer?.presentation())
            XCTAssertEqual(layer.bounds.minY, 0, accuracy: 0.5)
            XCTAssertNotEqual(layer.bounds.height, height, "The resize must remain animated")
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.05))
        }
    }

    func testPlayerHeaderShowHideKeepsMessagesInPlace() throws {
        for count in [3, 30] {
            for offset: CGFloat in count == 3 ? [0] : [0, 700] {
                let window = Window(contentRect: NSRect(x: 0, y: 0, width: 600, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                let chat = PlayerHeaderChat()
                let navigation = NavigationViewController(chat, window)
                navigation.loadViewIfNeeded(NSRect(x: 0, y: 0, width: 600, height: 700))
                window.contentView = navigation.view
                let table = (chat.view as! PlayerHeaderChatView).table
                for id in 0..<count { _ = table.addItem(item: PlayerHeaderRow(NSSize(width: 600, height: 80), stableId: id)) }
                let header = NavigationHeader(52) { header, _, _ in
                    let view = NavigationHeaderView(header)
                    view.ready.set(.single(true))
                    return (view, 52)
                }
                navigation.set(header: header)
                window.orderBack(nil)
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
                table.contentView.scroll(to: NSPoint(x: 0, y: offset))
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
                let index = offset == 0 ? 0 : 12
                let row = table.rectOf(item: table.item(at: index))
                func presentedY() throws -> CGFloat {
                    let document = try XCTUnwrap(table.view.layer?.presentation())
                    let root = try XCTUnwrap(navigation.view.layer?.presentation())
                    return document.convert(row, to: root).minY
                }
                let initial = try presentedY()
                for visible in [true, false, true, false] {
                    if visible { header.show(true, contextObject: ()) } else { header.hide(true) }
                    for _ in 0..<12 {
                        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
                        XCTAssertEqual(try presentedY(), initial, accuracy: 1, "count=\(count), offset=\(offset), visible=\(visible)")
                    }
                }
                withExtendedLifetime(navigation) { window.close() }
            }
        }
    }

    func testHeaderResizeDoesNotPinTableWidthAndCanReverse() throws {
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 600, height: 700), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let table = TableView(frame: window.contentView!.bounds, isFlipped: false)
        window.contentView = table
        for id in 0..<30 { _ = table.addItem(item: PlayerHeaderRow(table.frame.size, stableId: id)) }
        window.orderBack(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        for height: CGFloat in [648, 700, 648, 700] {
            ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeOut).updateFrame(view: table, frame: NSRect(x: 0, y: 0, width: table.frame.width, height: height))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            let width: CGFloat = table.frame.width == 600 ? 400 : 600
            ContainedViewLayoutTransition.immediate.updateFrame(view: table, frame: NSRect(x: 0, y: 0, width: width, height: height))
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            let layer = try XCTUnwrap(table.layer?.presentation())
            XCTAssertEqual(layer.bounds.minY, 0, accuracy: 0.5)
            XCTAssertEqual(layer.bounds.width, width, accuracy: 0.5)
        }
    }

    func testDirectBottomUpResizeRetainsItsOriginCompensation() {
        let table = TableView(frame: NSRect(x: 0, y: 0, width: 600, height: 700), isFlipped: false)
        table.change(size: NSSize(width: 600, height: 648), animated: true)
        XCTAssertNotNil(table.layer?.animation(forKey: "boundsOriginYAdditive"))
    }
}
