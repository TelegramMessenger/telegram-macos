import AppKit

public class View: NSView {
    public override var isFlipped: Bool { true }
}

__WINDOW_CONTROLS__

__HEADER_LAYOUT__

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

final class WindowFixture {
    let window: NSWindow
    let root: View
    let buttons: [NSButton]
    let parents: [NSView]
    let frames: [NSRect]
    let masks: [NSView.AutoresizingMask]
    let actions: [Selector?]
    let targets: [AnyObject?]

    init(fullSize: Bool = false) {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        if fullSize {
            style.insert(.fullSizeContentView)
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 600), styleMask: style, backing: .buffered, defer: false)
        self.window = window
        window.isReleasedWhenClosed = false
        root = View(frame: window.contentView!.bounds)
        root.autoresizingMask = [.width, .height]
        window.contentView!.addSubview(root)
        window.layoutIfNeeded()
        buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].map { window.standardWindowButton($0)! }
        parents = buttons.map { $0.superview! }
        frames = buttons.map { $0.frame }
        masks = buttons.map { $0.autoresizingMask }
        actions = buttons.map { $0.action }
        targets = buttons.map { $0.target }
    }

    func checkRestored() {
        for (index, button) in buttons.enumerated() {
            check(button.superview === parents[index], "native button parent restored")
            check(button.frame == frames[index], "native button frame restored")
            check(button.autoresizingMask == masks[index], "native button autoresizing restored")
            check(button.action == actions[index], "native button action preserved")
            check(button.target === targets[index], "native button target preserved")
        }
    }
}

private func testRepeatedAttachmentAndResize() {
    let fixture = WindowFixture()
    let controls = DetachedWindowControlsView(frame: NSRect(x: 12, y: 14, width: 83, height: 36))
    fixture.root.addSubview(controls)
    for _ in 0..<3 {
        controls.attach(to: fixture.window)
        controls.attach(to: fixture.window)
        controls.layout()
        check(controls.showsControls, "traffic lights installed")
        check(controls.subviews.count == 3, "reattaching does not duplicate controls")
        check(fixture.window.titleVisibility == .hidden, "native title hidden while attached")
        check(fixture.window.titlebarAppearsTransparent, "titlebar transparent while attached")
        check(fixture.window.styleMask.contains(.fullSizeContentView), "full-size content enabled")
        for (index, button) in fixture.buttons.enumerated() {
            check(button.superview === controls, "original native button reused")
            check(button.frame.size == fixture.frames[index].size, "native button dimensions preserved")
            check(controls.bounds.contains(button.frame), "button fits inside pill")
            check(button.frame.minX == 11 + CGFloat(index) * 23, "traffic lights start 11 points in with 23-point centers")
            check(button.frame.minY == 11, "traffic lights keep 11-point vertical insets")
            if index > 0 {
                check(button.frame.minX - fixture.buttons[index - 1].frame.maxX == 9, "native controls separated by 9 points")
            }
            let themeFrame = fixture.window.contentView!.superview!
            for inset: CGFloat in [3, 7, 11] {
                let point = controls.convert(NSPoint(x: button.frame.midX, y: button.frame.minY + inset), to: themeFrame.superview)
                check(themeFrame.hitTest(point) === button, "native button receives hit tests")
            }
        }
        for width: CGFloat in [380, 600, 500] {
            fixture.window.setContentSize(NSSize(width: width, height: 600))
            fixture.window.layoutIfNeeded()
            NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: fixture.window)
            controls.layout()
            check(fixture.buttons.allSatisfy { controls.bounds.contains($0.frame) }, "controls stay inside pill after resizing")
        }
        controls.detach()
        check(!controls.showsControls, "detach clears controls")
        check(!fixture.window.styleMask.contains(.fullSizeContentView), "original content style restored")
        check(!fixture.window.titlebarAppearsTransparent, "original titlebar restored")
        check(fixture.window.titleVisibility == .visible, "original title visibility restored")
        fixture.checkRestored()
    }
    print("PASS: repeated attachment, native size/actions, hit testing, resize and restoration")
}

private func testAppKitRepositioningAndFullScreenNotifications() {
    let fixture = WindowFixture()
    let otherWindow = WindowFixture()
    let controls = DetachedWindowControlsView(frame: NSRect(x: 12, y: 14, width: 83, height: 36))
    fixture.root.addSubview(controls)
    controls.attach(to: fixture.window)
    for name in [NSWindow.didUpdateNotification, NSWindow.didBecomeKeyNotification, NSWindow.didDeminiaturizeNotification] {
        for (index, button) in fixture.buttons.enumerated() {
            fixture.parents[index].addSubview(button)
            button.frame.origin = NSPoint(x: 9 + CGFloat(index) * 23, y: 9)
        }
        NotificationCenter.default.post(name: name, object: fixture.window)
        check(fixture.buttons.allSatisfy { $0.superview === controls && controls.bounds.contains($0.frame) }, "AppKit repositioning repaired")
    }
    NotificationCenter.default.post(name: NSWindow.willEnterFullScreenNotification, object: otherWindow.window)
    check(controls.showsControls, "unrelated window notification ignored")
    NotificationCenter.default.post(name: NSWindow.willEnterFullScreenNotification, object: fixture.window)
    check(!controls.showsControls, "native controls returned before full screen")
    fixture.checkRestored()
    NotificationCenter.default.post(name: NSWindow.didUpdateNotification, object: fixture.window)
    check(!controls.showsControls, "controls remain native during full-screen transition")
    NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: fixture.window)
    check(controls.showsControls, "controls reinstalled after full screen")
    controls.detach()
    NotificationCenter.default.post(name: NSWindow.didExitFullScreenNotification, object: fixture.window)
    check(!controls.showsControls, "detach removes notification observers")
    fixture.checkRestored()
    print("PASS: AppKit repositioning, window-scoped notifications and simulated full-screen lifecycle")
}

private func testWindowSwitchAndExistingChrome() {
    let first = WindowFixture()
    let second = WindowFixture(fullSize: true)
    second.window.titleVisibility = .hidden
    second.window.titlebarAppearsTransparent = true
    let controls = DetachedWindowControlsView(frame: NSRect(x: 12, y: 14, width: 83, height: 36))
    controls.attach(to: first.window)
    controls.attach(to: second.window)
    first.checkRestored()
    check(!first.window.styleMask.contains(.fullSizeContentView), "switching windows restores old chrome")
    controls.detach()
    second.checkRestored()
    check(second.window.styleMask.contains(.fullSizeContentView), "existing full-size content preserved")
    check(second.window.titleVisibility == .hidden, "existing hidden title preserved")
    check(second.window.titlebarAppearsTransparent, "existing transparent titlebar preserved")
    print("PASS: moving between windows and preserving existing chrome")
}

private func testDeinitializationRestoresChrome() {
    let fixture = WindowFixture()
    weak var releasedControls: NSView?
    autoreleasepool {
        let controls = DetachedWindowControlsView(frame: NSRect(x: 12, y: 14, width: 83, height: 36))
        releasedControls = controls
        controls.attach(to: fixture.window)
    }
    check(releasedControls == nil, "window controls released")
    fixture.checkRestored()
    check(!fixture.window.styleMask.contains(.fullSizeContentView), "deinit restores original content style")
    check(!fixture.window.titlebarAppearsTransparent, "deinit restores original titlebar")
    check(fixture.window.titleVisibility == .visible, "deinit restores original title visibility")
    print("PASS: deinitialization restores native buttons and window chrome")
}

private func testLeadingHeaderLayout() {
    let origin = NSPoint(x: 12, y: 12)
    let full = DetachedWindowHeaderLayout(origin: origin, showsControls: true, hasBackButton: true)
    let capsule = full.leadingPillFrame
    check(capsule == NSRect(x: 12, y: 14, width: 120, height: 36), "capsule is 120 x 36 and centered on the 40-point header row")
    check(full.controlsFrame.minX == capsule.minX && full.controlsFrame.width == 83, "native controls span the capsule up to the divider")
    if let divider = full.dividerFrame {
        check(divider.minX - capsule.minX == 83 && divider.minY - capsule.minY == 8, "divider origin is (83, 8) in the capsule")
        check(divider.width == 1 && divider.height == 20, "divider is 1 x 20")
        let greenMaxX = DetachedWindowHeaderLayout.controlsLeadingInset + DetachedWindowHeaderLayout.buttonSize * 3 + DetachedWindowHeaderLayout.buttonSpacing * 2
        check(divider.minX - capsule.minX - greenMaxX == 12, "green edge to divider is 12 points")
        check(full.backButtonFrame.minX - divider.maxX == 3, "back highlight starts 3 points after the divider")
    } else {
        check(false, "divider separates traffic lights from a back button")
    }
    check(full.backButtonFrame.minX - capsule.minX == 87 && full.backButtonFrame.minY - capsule.minY == 3, "back highlight origin is (87, 3) in the capsule")
    check(full.backButtonFrame.size == NSSize(width: 30, height: 30), "back highlight is 30 x 30")
    check(capsule.maxX - full.backButtonFrame.maxX == 3 && capsule.maxY - full.backButtonFrame.maxY == 3, "back highlight keeps 3-point gaps to the capsule edge")
    check(full.contentMinX == capsule.maxX + 6, "six-point gap after the capsule")

    let controlsOnly = DetachedWindowHeaderLayout(origin: origin, showsControls: true, hasBackButton: false)
    check(controlsOnly.dividerFrame == nil, "no divider without a back button")
    check(controlsOnly.leadingPillFrame.width == 82, "controls-only capsule keeps 11-point insets on both sides")

    let backOnly = DetachedWindowHeaderLayout(origin: origin, showsControls: false, hasBackButton: true)
    check(backOnly.leadingPillFrame == NSRect(x: 12, y: 12, width: 40, height: 40), "standard back bubble keeps its 40-point size")
    check(backOnly.dividerFrame == nil, "no divider without traffic lights")

    let empty = DetachedWindowHeaderLayout(origin: origin, showsControls: false, hasBackButton: false)
    check(empty.leadingPillFrame.width == 0 && empty.contentMinX == 12, "no leading capsule without controls or back button")
    print("PASS: shared profile/chat leading-pill geometry and back-button spacing")
}

private func testChatToProfileHandoff() {
    let fixture = WindowFixture()
    let chatControls = DetachedWindowControlsView(frame: .zero)
    let profileControls = DetachedWindowControlsView(frame: .zero)
    let layout = DetachedWindowHeaderLayout(origin: NSPoint(x: 12, y: 12), showsControls: true, hasBackButton: true)
    for _ in 0..<3 {
        for controls in [chatControls, profileControls] {
            fixture.root.addSubview(controls)
            controls.frame = layout.controlsFrame
            controls.attach(to: fixture.window)
            controls.layout()
            check(fixture.buttons.allSatisfy { $0.superview === controls && controls.bounds.contains($0.frame) }, "native controls move between chat and profile hosts")
            controls.detach()
            controls.removeFromSuperview()
            fixture.checkRestored()
            check(!fixture.window.styleMask.contains(.fullSizeContentView), "handoff restores window chrome before next host attaches")
        }
    }
    print("PASS: repeated chat/profile native-control handoff")
}

private func testResponsiveCompactAndStandardChrome() {
    let fixture = WindowFixture()
    let controls = DetachedWindowControlsView(frame: NSRect(x: 12, y: 14, width: 83, height: 36))
    fixture.root.addSubview(controls)
    controls.attach(to: fixture.window)
    for _ in 0..<3 {
        for width: CGFloat in [500, 649, 650, 900, 480] {
            fixture.window.setContentSize(NSSize(width: width, height: 600))
            fixture.window.layoutIfNeeded()
            NotificationCenter.default.post(name: NSWindow.didResizeNotification, object: fixture.window)
            controls.layout()
            let compact = width < 650
            check(controls.showsControls == compact, "responsive native-control visibility matches 650-point cutoff")
            check(fixture.window.styleMask.contains(.fullSizeContentView) == compact, "window content style switches with width")
            check(fixture.window.titleVisibility == (compact ? .hidden : .visible), "native title restored for standard layout")
            for (index, button) in fixture.buttons.enumerated() {
                check(button.superview === (compact ? controls : fixture.parents[index]), "native buttons return to the correct parent on resize")
                check(button.frame.size == fixture.frames[index].size, "responsive layout preserves native button size")
                check(button.action == fixture.actions[index], "responsive layout preserves native actions")
            }
        }
    }
    fixture.window.setContentSize(NSSize(width: 900, height: 600))
    controls.restoresTitlebarWhenWide = false
    controls.layout()
    check(controls.showsControls, "views that keep the capsule show it in wide windows")
    check(fixture.buttons.allSatisfy { $0.superview === controls }, "wide capsule hosts the native buttons")
    controls.restoresTitlebarWhenWide = true
    check(!controls.showsControls, "wide window returns to the standard titlebar when allowed")
    check(fixture.window.titleVisibility == .visible, "native title restored after leaving the wide capsule")
    controls.detach()
    fixture.checkRestored()
    check(!DetachedWindowHeaderLayout.usesCompactLayout(width: 650), "cutoff uses standard layout")
    check(DetachedWindowHeaderLayout.usesCompactLayout(width: 649), "narrow window uses compact layout")
    print("PASS: repeated compact/standard width changes restore native controls and window chrome at 650 points")
}

private func testTrafficLightHoverGroup() {
    let fixture = WindowFixture()
    let controls = DetachedWindowControlsView(frame: NSRect(x: 12, y: 14, width: 83, height: 36))
    fixture.root.addSubview(controls)
    controls.attach(to: fixture.window)
    let themeFrame = fixture.window.contentView!.superview!
    let closeCenter: () -> NSPoint = {
        let button = fixture.buttons[0]
        return themeFrame.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), from: button)
    }
    let groupTracked: (NSPoint) -> Bool = { point in
        themeFrame.trackingAreas.contains { ($0.userInfo ?? [:]).isEmpty && $0.rect.contains(point) }
    }
    let originalCenter = themeFrame.convert(NSPoint(x: fixture.frames[0].midX, y: fixture.frames[0].midY), from: fixture.parents[0])
    check(groupTracked(closeCenter()), "native hover group tracks the moved traffic lights")
    check(!groupTracked(originalCenter), "native hover group leaves the original titlebar position")
    controls.frame.origin = NSPoint(x: 120, y: 80)
    controls.layout()
    check(groupTracked(closeCenter()), "native hover group follows the pill when it moves")
    fixture.parents[0].addSubview(fixture.buttons[0])
    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
    check(fixture.buttons[0].superview === controls, "traffic lights return after AppKit moves them back")
    check(groupTracked(closeCenter()), "native hover group tracks the returned traffic lights")
    controls.detach()
    fixture.checkRestored()
    check(groupTracked(closeCenter()), "native hover group returns to the titlebar")
    print("PASS: traffic-light hover group")
}

let app = NSApplication.shared
private let tests: [() -> Void] = [testRepeatedAttachmentAndResize, testAppKitRepositioningAndFullScreenNotifications, testWindowSwitchAndExistingChrome, testDeinitializationRestoresChrome, testLeadingHeaderLayout, testChatToProfileHandoff, testResponsiveCompactAndStandardChrome, testTrafficLightHoverGroup]
for test in tests {
    test()
}
print("All 8 detached-window header checks passed")
