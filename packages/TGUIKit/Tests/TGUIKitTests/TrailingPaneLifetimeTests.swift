import AppKit
import XCTest
@testable import TGUIKit

private final class PaneLifetimeController: ViewController {
    override func viewDidLoad() { super.viewDidLoad(); readyOnce() }
}

final class TrailingPaneLifetimeTests: XCTestCase {
    override func setUp() { TGUIKitTestBootstrap.install() }

    private func settle(_ split: SplitView) {
        for _ in 0..<30 {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.016))
            split.layoutSubtreeIfNeeded()
        }
    }

    func testPaneSurvivesOwnerReleaseUntilItsViewIsRemoved() {
        for width: CGFloat in [500, 1100] {
            let window = Window(contentRect: NSRect(x: 0, y: 0, width: width, height: 650), styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let split = SplitView(frame: window.contentView!.bounds)
            split.canChangeState = false
            let chat = PaneLifetimeController()
            let navigation = NavigationViewController(chat, window)
            split.addController(controller: navigation, proportion: SplitProportion(min: width, max: .greatestFiniteMagnitude))
            window.contentView = split
            var pane: PaneLifetimeController? = PaneLifetimeController()
            weak var retainedPane = pane
            let paneView = pane!.view
            split.setTrailing(controller: pane, width: 358, minimumLeadingWidth: 380, overlayWhenNarrow: true, navigationOwner: chat)
            split.layoutSubtreeIfNeeded()
            pane = nil
            XCTAssertNotNil(retainedPane, "The host must retain its currently attached pane")
            split.setTrailing(controller: nil, width: 0, minimumLeadingWidth: 0, animated: true, navigationOwner: chat)
            settle(split)
            XCTAssertNil(paneView.superview, "Clearing a released pane must remove the actual view")
            XCTAssertNil(retainedPane, "The host must release the pane after removal")
            window.close()
            withExtendedLifetime(navigation) {}
        }
    }

    func testRemovedSidebarIsCleanedUpAfterReturningFromSettings() {
        let window = Window(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 650), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let split = SplitView(frame: window.contentView!.bounds)
        split.canChangeState = false
        let chat = PaneLifetimeController()
        let navigation = NavigationViewController(chat, window)
        split.addController(controller: navigation, proportion: SplitProportion(min: 1100, max: .greatestFiniteMagnitude))
        window.contentView = split
        var pane: PaneLifetimeController? = PaneLifetimeController()
        weak var retainedPane = pane
        let paneView = pane!.view
        split.setTrailing(controller: pane, width: 358, minimumLeadingWidth: 380, overlayWhenNarrow: true, navigationOwner: chat)
        split.layoutSubtreeIfNeeded()
        let settings = PaneLifetimeController()
        navigation.push(settings, false)
        split.setTrailing(controller: nil, width: 0, minimumLeadingWidth: 0, navigationOwner: chat)
        pane = nil
        XCTAssertNotNil(retainedPane, "A suspended pane needs its controller until cleanup")
        navigation.back(animated: false)
        split.setTrailing(controller: nil, width: 0, minimumLeadingWidth: 0, navigationOwner: chat)
        settle(split)
        XCTAssertNil(paneView.superview)
        XCTAssertNil(retainedPane)
        XCTAssertEqual(chat.view.frame.width, 1100, accuracy: 0.1)
        window.close()
        withExtendedLifetime(navigation) {}
    }
}
