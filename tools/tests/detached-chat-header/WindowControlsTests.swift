import AppKit

__HEADER_LAYOUT__

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

let kinds: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

func makeWindow(width: CGFloat) -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 600), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.titlebarAppearsTransparent = true
    window.titleVisibility = .hidden
    let toolbar = NSToolbar(identifier: "detached-window")
    window.toolbar = toolbar
    window.toolbarStyle = .unified
    window.contentView?.superview?.layoutSubtreeIfNeeded()
    return window
}

func topLeft(_ rect: NSRect, in window: NSWindow) -> NSRect {
    return NSRect(x: rect.minX, y: window.frame.height - rect.maxY, width: rect.width, height: rect.height)
}

func buttonsFrame(_ window: NSWindow) -> NSRect {
    let buttons = kinds.compactMap { window.standardWindowButton($0) }
    return buttons.map { topLeft($0.convert($0.bounds, to: nil), in: window) }.reduce(NSRect.null) { $0.union($1) }
}

func place(_ window: NSWindow) -> DetachedWindowHeaderLayout {
    let titlebar = window.standardWindowButton(.closeButton)!.superview!
    let layout = DetachedWindowHeaderLayout(buttonsFrame: buttonsFrame(window), titlebarFrame: topLeft(titlebar.convert(titlebar.bounds, to: nil), in: window))
    for kind in kinds {
        let button = window.standardWindowButton(kind)!
        button.setFrameOrigin(NSPoint(x: button.frame.minX + layout.buttonsOffset.x, y: button.frame.minY - layout.buttonsOffset.y))
    }
    return layout
}

func testCapsuleMatchesHeaderRow() {
    let window = makeWindow(width: 500)
    let layout = place(window)
    let capsule = layout.capsuleFrame
    check(capsule.minX == DetachedWindowHeaderLayout.sideInset, "capsule starts at the header side inset")
    check(capsule.minY == DetachedWindowHeaderLayout.topInset, "capsule is on the header bubble row (got \(capsule.minY))")
    check(capsule.height == DetachedWindowHeaderLayout.height, "capsule matches the header bubble height")
    let buttons = buttonsFrame(window)
    check(abs(buttons.midY - capsule.midY) < 0.5, "traffic lights are vertically centred in the capsule")
    check(abs((buttons.minX - capsule.minX) - (capsule.maxX - buttons.maxX)) < 0.5, "traffic lights are horizontally centred in the capsule")
    check(layout.reservedWidth == capsule.maxX + DetachedWindowHeaderLayout.spacing, "screens reserve the capsule plus bubble spacing")
}

func testButtonsStayInsideTitlebarAndClickable() {
    let window = makeWindow(width: 500)
    _ = place(window)
    let titlebar = window.standardWindowButton(.closeButton)!.superview!
    let theme = window.contentView!.superview!
    for kind in kinds {
        let button = window.standardWindowButton(kind)!
        check(titlebar.bounds.contains(button.frame), "\(kind) stays inside the titlebar view")
        let center = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        let hit = theme.hitTest(theme.convert(center, from: nil))
        check(hit === button || hit?.isDescendant(of: button) == true, "\(kind) receives clicks at its new position")
        check(button.superview === titlebar, "\(kind) keeps its native parent")
    }
}

func testGeometryIsWidthIndependent() {
    let narrow = place(makeWindow(width: 420))
    let wide = place(makeWindow(width: 1200))
    check(narrow == wide, "capsule geometry is the same in narrow and wide windows")
}

func testClampsToShortTitlebar() {
    let layout = DetachedWindowHeaderLayout(buttonsFrame: NSRect(x: 7, y: 7, width: 54, height: 14), titlebarFrame: NSRect(x: 0, y: 0, width: 500, height: 28))
    check(NSRect(x: 7, y: 7, width: 54, height: 14).offsetBy(dx: layout.buttonsOffset.x, dy: layout.buttonsOffset.y).maxY <= 28, "buttons never leave a short titlebar")
    check(layout.capsuleFrame.height == DetachedWindowHeaderLayout.height, "capsule keeps its height when clamped")
}

testCapsuleMatchesHeaderRow()
testButtonsStayInsideTitlebarAndClickable()
testGeometryIsWidthIndependent()
testClampsToShortTitlebar()
print("PASS: detached window header checks")
