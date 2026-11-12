import XCTest
import AppKit
import TGUIKit
import GeneralRows
import TelegramTheme
import TelegramUtils
@testable import PeerInfoUI

final class TextAndLabelRowTests: XCTestCase {
    private struct Config {
        let name: String
        var viewType: GeneralViewType = .singleItem
        var text: String = "Plan like an adult, believe like a child"
        var copy: Bool = false
        var hideText: Bool? = nil
        var gift: Bool = false
        var description: String? = nil
    }

    private static let longText = Array(repeating: "Plan like an adult, believe like a child, and keep every promise.", count: 6).joined(separator: " ")

    private let configs: [Config] = [
        Config(name: "plain", viewType: .firstItem),
        Config(name: "copy", viewType: .innerItem, copy: true),
        Config(name: "more", viewType: .lastItem, text: longText),
        Config(name: "hidden", hideText: true),
        Config(name: "shown", hideText: false),
        Config(name: "gift", gift: true),
        Config(name: "description", copy: true, description: "28 years old"),
        Config(name: "legacy", viewType: .legacy, copy: true),
        Config(name: "everything", viewType: .firstItem, text: longText, copy: true, hideText: false, description: "28 years old"),
    ]

    private let width: CGFloat = 420

    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
        LinkHooks.install(LinkHooks(callbackLink: { link, _ in link }, globalLinkExecutor: { TextViewInteractions() }, openExternalLink: { _, _ in }, markdownLink: { $0 }, externalLink: { link, _ in link }, linkPayload: { $0 as? String }, openAnyLink: { _ in }, detectLinks: { _, _ in }))
    }

    private func makeItem(_ config: Config, copied: (() -> Void)? = nil, toggled: (() -> Void)? = nil) -> TextAndLabelItem {
        let item = TextAndLabelItem(NSMakeSize(width, 50), stableId: 0, label: "bio", copyMenuText: "Copy", text: config.text, context: nil, viewType: config.viewType, _copyToClipboard: config.copy ? (copied ?? {}) : nil, hideText: config.hideText, toggleHide: config.hideText != nil ? (toggled ?? {}) : nil, linkInteractions: TextViewInteractions(), gift: config.gift ? {} : nil, description: config.description)
        _ = item.makeSize(width, oldWidth: 0)
        return item
    }

    private func show<T: TableRowView>(_ row: T, _ item: TextAndLabelItem) {
        row.setFrameSize(NSMakeSize(width, item.height))
        row.set(item: item, animated: false)
        row.updateColors()
        row.layout()
    }

    private func container(_ row: NSView) -> NSView {
        return row.subviews.first(where: { $0 is GeneralRowContainerView })!
    }

    private func shownChildren(_ row: NSView) -> [String] {
        return container(row).subviews.filter { !$0.isHidden }.map { String(describing: type(of: $0)) }
    }

    func testRowsRenderLikeTheOldRow() {
        for config in configs {
            let item = makeItem(config)
            let current = TextAndLabelRowView(frame: NSMakeRect(0, 0, width, item.height))
            let legacy = LegacyTextAndLabelRowView(frame: NSMakeRect(0, 0, width, item.height))
            show(current, item)
            show(legacy, item)
            XCTAssertEqual(shownChildren(current), shownChildren(legacy), config.name)
            for (new, old) in zip(container(current).subviews, container(legacy).subviews.filter { !$0.isHidden }) {
                XCTAssertEqual(new.frame, old.frame, config.name)
            }
            XCTAssertEqual(ViewSnapshot.render(current).differingPixels(from: ViewSnapshot.render(legacy), tolerance: 0), 0, config.name)
        }
    }

    func testExtrasAreVisibleInTheRender() {
        let plain = makeItem(Config(name: "plain"))
        let base = TextAndLabelRowView(frame: NSMakeRect(0, 0, width, plain.height))
        show(base, plain)
        let reference = ViewSnapshot.render(base)
        for config in [Config(name: "copy", copy: true), Config(name: "hidden", hideText: false), Config(name: "gift", gift: true)] {
            let item = makeItem(config)
            let row = TextAndLabelRowView(frame: NSMakeRect(0, 0, width, item.height))
            show(row, item)
            XCTAssertGreaterThan(ViewSnapshot.render(row).differingPixels(from: reference, tolerance: 0), 100, config.name)
        }
        let more = makeItem(Config(name: "more", text: TextAndLabelRowTests.longText))
        XCTAssertEqual(more.hasMore, true)
    }

    func testPlainRowHoldsOnlyItsText() {
        let row = TextAndLabelRowView(frame: NSMakeRect(0, 0, width, 50))
        show(row, makeItem(Config(name: "plain")))
        XCTAssertEqual(container(row).subviews.count, 1)
        XCTAssertTrue(container(row).subviews.first is InteractiveTextView)
    }

    func testReusedRowMatchesAFreshOldRow() {
        let everything = configs.last!
        let row = TextAndLabelRowView(frame: NSMakeRect(0, 0, width, 50))
        show(row, makeItem(everything))
        show(row, makeItem(Config(name: "plain")))
        XCTAssertEqual(container(row).subviews.count, 1)
        show(row, makeItem(Config(name: "description", copy: true, description: "28 years old")))
        let item = makeItem(everything)
        show(row, item)
        let legacy = LegacyTextAndLabelRowView(frame: NSMakeRect(0, 0, width, item.height))
        show(legacy, item)
        XCTAssertEqual(shownChildren(row), shownChildren(legacy))
        XCTAssertEqual(ViewSnapshot.render(row).differingPixels(from: ViewSnapshot.render(legacy), tolerance: 0), 0)
    }

    func testShareLinkDoesNotActivateInOuterMargins() throws {
        for width: CGFloat in [420, 900] {
            for viewType: GeneralViewType in [.singleItem, .firstItem, .innerItem, .lastItem] {
                var shared = 0
                let fixture = ShareLinkClickFixture(width: width, viewType: viewType, share: { shared += 1 })
                defer { fixture.window.close() }
                let block = container(fixture.row).frame
                let points = [
                    NSPoint(x: block.minX / 2, y: block.midY),
                    NSPoint(x: (block.maxX + width) / 2, y: block.midY)
                ]
                for point in points {
                    XCTAssertTrue(fixture.row.bounds.contains(point))
                    XCTAssertFalse(block.contains(point))
                    try fixture.click(point)
                    XCTAssertEqual(shared, 0, "width: \(width), viewType: \(viewType), point: \(point)")
                }
                try fixture.click(NSPoint(x: block.midX, y: block.midY))
                XCTAssertEqual(shared, 1)
            }
        }
    }

    func testShareLinkActionsStillWorkInsideTheBlock() throws {
        for viewType: GeneralViewType in [.singleItem, .legacy] {
            var shared = 0
            var copied = 0
            var qrOpened = 0
            let fixture = ShareLinkClickFixture(width: width, viewType: viewType, share: { shared += 1 }, copy: { copied += 1 }, qr: { qrOpened += 1 })
            defer { fixture.window.close() }
            let block = container(fixture.row)
            try fixture.click(NSPoint(x: block.frame.midX, y: block.frame.midY))
            XCTAssertEqual(shared, 1)
            let buttons = block.subviews.compactMap { $0 as? ImageButton }
            XCTAssertEqual(buttons.count, 2)
            for button in buttons {
                let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: fixture.row)
                try fixture.click(point)
            }
            XCTAssertEqual(shared, 1)
            XCTAssertEqual(copied, 1)
            XCTAssertEqual(qrOpened, 1)
        }
    }

    func testButtonsReachTheirActions() {
        var copied = 0
        var toggled = 0
        let row = TextAndLabelRowView(frame: NSMakeRect(0, 0, width, 50))
        show(row, makeItem(Config(name: "both", copy: true, hideText: true), copied: { copied += 1 }, toggled: { toggled += 1 }))
        let buttons = container(row).subviews.compactMap { $0 as? ImageButton }
        XCTAssertEqual(buttons.count, 2)
        buttons.forEach { $0.send(event: .Click) }
        XCTAssertEqual(copied, 1)
        XCTAssertEqual(toggled, 1)
        XCTAssertTrue(buttons.allSatisfy { $0.scaleOnClick && !$0.autohighlight })
    }
}

private final class ShareLinkClickWindow: NSWindow {
    var pointerLocation = NSPoint.zero

    override var mouseLocationOutsideOfEventStream: NSPoint {
        return pointerLocation
    }
}

private final class ShareLinkClickFixture {
    let row: TextAndLabelRowView
    let window: ShareLinkClickWindow

    init(width: CGFloat, viewType: GeneralViewType, share: @escaping () -> Void, copy: @escaping () -> Void = {}, qr: @escaping () -> Void = {}) {
        let item = TextAndLabelItem(NSSize(width: width, height: 50), stableId: 0, label: "share link", copyMenuText: "Copy", text: "@bloodysx", context: nil, viewType: viewType, isTextSelectable: false, callback: share, _copyToClipboard: copy, linkInteractions: TextViewInteractions(), qrCode: { _ in qr() })
        _ = item.makeSize(width, oldWidth: 0)
        row = TextAndLabelRowView(frame: NSRect(x: 30, y: 20, width: width, height: item.height))
        window = ShareLinkClickWindow(contentRect: NSRect(x: 0, y: 0, width: width + 60, height: item.height + 40), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSView(frame: NSRect(origin: .zero, size: window.frame.size))
        window.contentView?.addSubview(row)
        row.set(item: item, animated: false)
        row.layoutSubtreeIfNeeded()
        row.layout()
    }

    func click(_ point: NSPoint) throws {
        let location = row.convert(point, to: nil)
        window.pointerLocation = location
        let target = try XCTUnwrap(window.contentView?.hitTest(location))
        for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0))
            if type == .leftMouseDown {
                target.mouseDown(with: event)
            } else {
                target.mouseUp(with: event)
            }
        }
    }
}
