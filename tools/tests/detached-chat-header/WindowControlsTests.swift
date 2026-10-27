import AppKit

class View: NSView {
    override var isFlipped: Bool { true }
}

__WINDOW_CONTROLS__

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
    let controls = DetachedChatWindowControlsView(frame: NSRect(x: 12, y: 12, width: 80, height: 40))
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
            if index > 0 {
                check(button.frame.minX - fixture.buttons[index - 1].frame.maxX == 6, "native controls separated")
            }
            let themeFrame = fixture.window.contentView!.superview!
            for inset: CGFloat in [3, 7, 11] {
                let point = controls.convert(NSPoint(x: button.frame.midX, y: button.frame.minY + inset), to: themeFrame.superview)
                check(themeFrame.hitTest(point) === button, "native button receives hit tests")
            }
        }
        for width: CGFloat in [380, 700, 500] {
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
    let controls = DetachedChatWindowControlsView(frame: NSRect(x: 12, y: 12, width: 80, height: 40))
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
    let controls = DetachedChatWindowControlsView(frame: NSRect(x: 12, y: 12, width: 80, height: 40))
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
        let controls = DetachedChatWindowControlsView(frame: NSRect(x: 12, y: 12, width: 80, height: 40))
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

let app = NSApplication.shared
private let tests: [() -> Void] = [testRepeatedAttachmentAndResize, testAppKitRepositioningAndFullScreenNotifications, testWindowSwitchAndExistingChrome, testDeinitializationRestoresChrome]
for test in tests {
    test()
}
print("All 4 detached-chat native window-control checks passed")
