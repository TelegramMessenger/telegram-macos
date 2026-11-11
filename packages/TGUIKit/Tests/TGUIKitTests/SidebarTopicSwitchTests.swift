import AppKit
import XCTest
@testable import TGUIKit

private final class TopicSwitchChat: ViewController {
    override func viewDidLoad() { super.viewDidLoad(); readyOnce() }
}

final class SidebarTopicSwitchTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }
    private func settle(_ split: SplitView) {
        for _ in 0..<4 { RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01)); split.layoutSubtreeIfNeeded() }
    }

    func testTopicSwitchKeepsChatBesideSidebarWithoutWindowResize() {
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 650), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let split = SplitView(frame: window.contentView!.bounds)
        split.canChangeState = false
        let first = TopicSwitchChat()
        let navigation = NavigationViewController(first, window)
        window.contentView = split
        split.addController(controller: navigation, proportion: SplitProportion(min: 1100, max: .greatestFiniteMagnitude))
        let originalFrame = window.frame
        var panes: [TopicSwitchChat] = []
        for index in 0..<4 {
            let chat = index == 0 ? first : TopicSwitchChat()
            if index != 0 { navigation.push(chat, false, style: .none) }
            let pane = TopicSwitchChat()
            panes.append(pane)
            split.setTrailing(controller: pane, width: 358, minimumLeadingWidth: 380, overlayWhenNarrow: true, navigationOwner: chat)
            settle(split)
            XCTAssertEqual(chat.view.frame.width, 742, accuracy: 0.01, "New topic must inherit the existing reserved width")
            let chatRect = chat.view.convert(chat.view.bounds, to: split)
            let paneRect = pane.view.convert(pane.view.bounds, to: split)
            XCTAssertLessThanOrEqual(chatRect.maxX, paneRect.minX + 0.01, "Docked sidebar must not cover the new chat")
            XCTAssertEqual(window.frame, originalFrame)
        }
        split.setTrailing(controller: nil, width: 0, minimumLeadingWidth: 0)
        settle(split)
        XCTAssertEqual(navigation.controller.view.frame.width, 1100, accuracy: 0.01)
        XCTAssertTrue(panes.allSatisfy { $0.view.superview == nil })
        window.close()
        withExtendedLifetime(navigation) {}
    }

    func testOnlySmallOpenWindowsOverlayRegardlessOfListLayoutState() {
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 650), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let split = SplitView(frame: window.contentView!.bounds)
        split.canChangeState = false
        let chat = TopicSwitchChat()
        let navigation = NavigationViewController(chat, window)
        window.contentView = split
        split.addController(controller: navigation, proportion: SplitProportion(min: 1100, max: .greatestFiniteMagnitude))
        let pane = TopicSwitchChat()
        for state in [SplitViewState.none, .single, .minimisize] {
            split.state = state
            split.frame.size.width = 1100
            split.setTrailing(controller: pane, width: 358, minimumLeadingWidth: 380, overlayWhenNarrow: true, navigationOwner: chat)
            settle(split)
            XCTAssertEqual(chat.view.frame.width, 742, accuracy: 0.01, "Wide windows must dock regardless of chat-list state")
            split.frame.size.width = 500
            settle(split)
            XCTAssertEqual(chat.view.frame.width, 500, accuracy: 0.01, "Small windows overlay rather than shrink chat")
            let paneRect = pane.view.convert(pane.view.bounds, to: split)
            XCTAssertGreaterThan(paneRect.minX, 0)
            split.setTrailing(controller: nil, width: 0, minimumLeadingWidth: 0)
            settle(split)
            XCTAssertNil(pane.view.superview)
            XCTAssertEqual(chat.view.frame.width, 500, accuracy: 0.01)
        }
        window.close()
        withExtendedLifetime(navigation) {}
    }
}
