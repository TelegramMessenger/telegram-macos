import AppKit
import XCTest
@testable import TGUIKit

private final class BubbleItem: TableRowItem {
    var fixedHeight: CGFloat?
    private var measuredHeight: CGFloat = 60
    override var height: CGFloat { fixedHeight ?? measuredHeight }
    override func makeSize(_ width: CGFloat = .greatestFiniteMagnitude, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        measuredHeight = ceil(1800 / max(40, width - 100)) * 22 + 24
        return true
    }
    override func viewClass() -> AnyClass { BubbleRow.self }
}

private final class ReplySpacer: TableRowItem {
    var value: CGFloat = 52
    override var height: CGFloat { value }
}

private final class BubbleRow: TableRowView {
    static var animatedLayouts = 0
    let bubble = View(frame: .zero)
    required init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(bubble)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        if transition.isAnimated { Self.animatedLayouts += 1 }
        bubble.frame = NSRect(x: max(20, size.width - 320), y: 4, width: min(300, size.width - 40), height: size.height - 8)
    }
}

private final class ChatView: View {
    let table = TableView(frame: .zero, isFlipped: false)
    let input = View(frame: .zero)
    var inputHeight: CGFloat = 50
    required init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(table)
        addSubview(input)
        for id in 0..<40 { _ = table.addItem(item: BubbleItem(frame.size, stableId: id)) }
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        table.frame = bounds
        input.frame = NSRect(x: 0, y: bounds.height - inputHeight, width: bounds.width, height: inputHeight)
    }
}

private final class Chat: ViewController {
    override func viewClass() -> AnyClass { ChatView.self }
    override func viewDidLoad() { super.viewDidLoad(); readyOnce() }
}

final class TrailingChatLayoutTests: XCTestCase {
    override func setUp() {
        TGUIKitTestBootstrap.install()
    }

    func testNativeReplyTableUpdatesDoNotRestoreOldDocumentWidth() throws {
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 650), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let table = TableView(frame: NSRect(x: 0, y: 0, width: 1100, height: 650), isFlipped: false)
        window.contentView = table
        let spacer = ReplySpacer(table.frame.size, stableId: -1)
        _ = table.addItem(item: spacer)
        for id in 0..<6 {
            let item = BubbleItem(table.frame.size, stableId: id)
            item.fixedHeight = 82
            _ = table.addItem(item: item)
        }
        window.orderBack(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        var rows: [TableRowView] = []
        table.enumerateVisibleViews(with: { if $0.item is BubbleItem { rows.append($0) } }, force: true)
        XCTAssertFalse(rows.isEmpty)
        spacer.value = 100
        table.noteHeightOfRowWithVerticalAnimation(0)
        XCTAssertTrue(rows.contains(where: { $0.layer?.animation(forKey: "inputHeight.position.y") != nil }), "Reply must retain smooth vertical movement")
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        for width: CGFloat in [1050, 971, 850, 742] {
            table.frame = NSRect(origin: .zero, size: NSSize(width: width, height: 650))
            XCTAssertEqual(table.documentView!.frame.width, width, accuracy: 0.5)
            for row in rows { XCTAssertEqual(row.frame.width, width, accuracy: 0.5) }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.015))
            for row in rows { XCTAssertEqual(row.frame.width, width, accuracy: 0.5) }
        }
    }

    func testReplyHeightAnimationDoesNotPinInputWidth() throws {
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 650), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let root = View(frame: NSRect(x: 0, y: 0, width: 1100, height: 650))
        let input = View(frame: NSRect(x: 0, y: 598, width: 1100, height: 52))
        root.addSubview(input)
        window.contentView = root
        window.orderBack(nil)
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        ContainedViewLayoutTransition.animated(duration: 1, curve: .easeOut).updateFrame(view: input, frame: NSRect(x: 0, y: 550, width: 1100, height: 100))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        ContainedViewLayoutTransition.immediate.updateFrame(view: input, frame: NSRect(x: 0, y: 550, width: 742, height: 100))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.03))
        let presented = try XCTUnwrap(input.layer?.presentation())
        XCTAssertEqual(presented.bounds.width, 742, accuracy: 0.5)
        XCTAssertGreaterThan(presented.bounds.height, 52)
        XCTAssertLessThan(presented.bounds.height, 100)
    }

    func testConstantHeightRowsFollowWidthDuringReply() throws {
        let (window, split, navigation, chat, _) = fixture(width: 1100)
        defer { withExtendedLifetime(navigation) { window.close() } }
        let table = (chat.view as! ChatView).table
        table.enumerateItems { item in
            (item as! BubbleItem).fixedHeight = 82
            return true
        }
        table.layoutItems()
        split.layoutSubtreeIfNeeded()
        var rows: [TableRowView] = []
        table.enumerateVisibleViews(with: { rows.append($0) }, force: true)
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            row._change(size: NSSize(width: row.frame.width, height: row.frame.height + 8), animated: true, duration: 1)
            let animation = CABasicAnimation(keyPath: "position")
            animation.fromValue = NSValue(point: row.frame.origin.offsetBy(dx: 0, dy: 48))
            animation.toValue = NSValue(point: row.frame.origin)
            animation.duration = 1
            row.layer?.add(animation, forKey: "position")
        }
        for width: CGFloat in [1050, 971, 742, 1000, 1100] {
            ContainedViewLayoutTransition.immediate.updateFrame(view: table, frame: NSRect(origin: table.frame.origin, size: NSSize(width: width, height: table.frame.height)))
            table.layoutSubtreeIfNeeded()
            for row in rows {
                XCTAssertEqual(row.frame.width, width, accuracy: 0.5)
                XCTAssertEqual((row as! BubbleRow).bubble.frame.maxX, width - 20, accuracy: 0.5)
            }
        }
    }

    func testWidthRelayoutDoesNotRestartReplyRowAnimations() throws {
        let (window, split, navigation, chat, _) = fixture(width: 1100)
        defer { withExtendedLifetime(navigation) { window.close() } }
        split.layoutSubtreeIfNeeded()
        let table = (chat.view as! ChatView).table
        var rows: [TableRowView] = []
        table.enumerateVisibleViews(with: { rows.append($0) }, force: true)
        XCTAssertFalse(rows.isEmpty)
        for row in rows {
            let motion = CABasicAnimation(keyPath: "position")
            motion.fromValue = NSValue(point: row.frame.origin.offsetBy(dx: 0, dy: 40))
            motion.toValue = NSValue(point: row.frame.origin)
            motion.duration = 1
            row.layer?.add(motion, forKey: "position")
        }
        BubbleRow.animatedLayouts = 0
        table.reloadData(row: rows[0].item!.index, animated: false)
        XCTAssertGreaterThan(BubbleRow.animatedLayouts, 0, "Ordinary reloads should still continue an existing animation")
        BubbleRow.animatedLayouts = 0
        for width: CGFloat in [400, 742, 1100, 650] {
            table.setFrameSize(NSSize(width: width, height: table.frame.height))
            XCTAssertEqual(BubbleRow.animatedLayouts, 0, "Width updates must not start a fresh bubble animation on each sidebar tick")
        }
        XCTAssertNotNil(rows.first?.layer?.animation(forKey: "position"), "Reply's existing vertical animation should survive")
    }

    private func fixture(width: CGFloat) -> (Window, SplitView, NavigationViewController, Chat, ViewController) {
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: width, height: 650), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let split = SplitView(frame: window.contentView!.bounds)
        split.canChangeState = false
        split.state = .dual
        let chat = Chat()
        let navigation = NavigationViewController(chat, window)
        split.addController(controller: navigation, proportion: SplitProportion(min: width, max: .greatestFiniteMagnitude))
        window.contentView = split
        let sidebar = ViewController()
        split.needsLayout = true
        split.layoutSubtreeIfNeeded()
        return (window, split, navigation, chat, sidebar)
    }

    private func verify(_ split: SplitView, _ chat: Chat, _ pane: ViewController, docked: Bool) throws {
        split.layoutSubtreeIfNeeded()
        guard pane.isLoaded(), let host = pane.view.superview else { return }
        if docked {
            XCTAssertTrue(host.isDescendant(of: chat.navigationController!.containerOf(chat)))
            let chatRect = chat.view.convert(chat.view.bounds, to: split)
            let sidebarRect = host.convert(host.bounds, to: split)
            XCTAssertEqual(chatRect.maxX, sidebarRect.minX, accuracy: 0.01)
        }
        let content = try XCTUnwrap(chat.view as? ChatView)
        XCTAssertEqual(content.table.frame.width, content.bounds.width, accuracy: 0.01)
        XCTAssertEqual(content.input.frame.width, content.bounds.width, accuracy: 0.01)
        var rowCount = 0
        content.table.enumerateVisibleViews(with: { row in
            rowCount += 1
            row.layoutSubtreeIfNeeded()
            XCTAssertEqual(row.frame.width, content.table.frame.width, accuracy: 1)
            XCTAssertEqual(row.frame.height, row.item!.height, accuracy: 1)
            if let row = row as? BubbleRow {
                XCTAssertLessThanOrEqual(row.bubble.frame.maxX, row.bounds.maxX)
            }
        }, force: true)
        XCTAssertGreaterThan(rowCount, 0)
    }

    func testDockedPaneAndRowsShareEverySlideFrameAndReverseWithoutJump() throws {
        let (window, split, navigation, chat, pane) = fixture(width: 1100)
        defer { withExtendedLifetime(navigation) { window.close() } }
        var intermediateWidths: [CGFloat] = []
        for visible in [true, false, true, false] {
            split.setTrailing(controller: visible ? pane : nil, width: 358, minimumLeadingWidth: 380, animated: true, overlayWhenNarrow: true, navigationOwner: chat)
            for sample in 0..<8 {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.012))
                try verify(split, chat, pane, docked: true)
                intermediateWidths.append(chat.view.frame.width)
                if sample == 3 {
                    let content = chat.view as! ChatView
                    content.inputHeight = visible ? 100 : 50
                    content.needsLayout = true
                }
            }
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))
        split.layoutSubtreeIfNeeded()
        XCTAssertTrue(intermediateWidths.contains(where: { $0 > 742 && $0 < 1100 }))
        XCTAssertEqual(chat.view.frame.width, 1100, accuracy: 0.01)
        XCTAssertNil(pane.view.superview)
    }

    func testCompactDrawerDoesNotResizeChat() throws {
        let (window, split, navigation, chat, pane) = fixture(width: 600)
        defer { withExtendedLifetime(navigation) { window.close() } }
        split.state = .minimisize
        split.setTrailing(controller: pane, width: 358, minimumLeadingWidth: 380, animated: true, overlayWhenNarrow: true, navigationOwner: chat)
        for _ in 0..<20 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.015))
            try verify(split, chat, pane, docked: false)
            XCTAssertEqual(chat.view.frame.width, 600, accuracy: 0.01)
        }
        let host = try XCTUnwrap(pane.view.superview)
        XCTAssertEqual(host.frame.width, 358)
        XCTAssertGreaterThan(host.frame.minX, 0)
    }

    func testPushingScreenKeepsDockedPaneInsideOutgoingChat() throws {
        let (window, split, navigation, chat, pane) = fixture(width: 1100)
        defer { window.close() }
        split.setTrailing(controller: pane, width: 358, minimumLeadingWidth: 380, overlayWhenNarrow: true, navigationOwner: chat)
        split.layoutSubtreeIfNeeded()
        try verify(split, chat, pane, docked: true)
        let host = try XCTUnwrap(pane.view.superview)
        let parent = try XCTUnwrap(host.superview)
        let info = Chat()
        navigation.push(info)
        split.setTrailing(controller: nil, width: 0, minimumLeadingWidth: 0, animated: true, navigationOwner: info)
        for _ in 0..<8 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.025))
            split.layoutSubtreeIfNeeded()
            XCTAssertTrue(host.superview === parent)
            XCTAssertTrue(chat.view.isDescendant(of: navigation.containerOf(chat)))
            XCTAssertTrue(host.isDescendant(of: navigation.containerOf(chat)))
            XCTAssertEqual(chat.view.frame.width, 742, accuracy: 0.01)
            XCTAssertEqual(info.view.frame.width, 1100, accuracy: 0.01)
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.4))
    }

    func testCompactDrawerSlidesOutWhileNextScreenPushes() throws {
        let (window, split, navigation, chat, pane) = fixture(width: 600)
        defer { withExtendedLifetime(navigation) { window.close() } }
        split.state = .minimisize
        split.setTrailing(controller: pane, width: 358, minimumLeadingWidth: 380, overlayWhenNarrow: true, navigationOwner: chat)
        split.layoutSubtreeIfNeeded()
        let host = try XCTUnwrap(pane.view.superview)
        let initialX = host.frame.minX
        let next = Chat()
        navigation.controllerDidChange = {
            split.setTrailing(controller: nil, width: 0, minimumLeadingWidth: 0, animated: true)
        }
        split.setTrailing(controller: nil, width: 0, minimumLeadingWidth: 0, animated: true, navigationOwner: chat)
        navigation.push(next)
        XCTAssertTrue(navigation.controller === next)
        XCTAssertTrue(pane.view.superview === host)
        var positions: [CGFloat] = []
        for _ in 0..<10 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.012))
            split.layoutSubtreeIfNeeded()
            if pane.view.superview != nil { positions.append(host.frame.minX) }
        }
        XCTAssertTrue(positions.contains { $0 > initialX + 1 && $0 < split.bounds.maxX - 1 })
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.5))
        split.layoutSubtreeIfNeeded()
        XCTAssertNil(pane.view.superview)
        XCTAssertTrue(navigation.controller === next)
    }

}
