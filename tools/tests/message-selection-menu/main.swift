import AppKit
import TGUIKit
import ColorPalette

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)
System.legacyMenu = false
let images: [NSImage] = __IMAGE_PATHS__.map { name, path in
    let image = NSImage(contentsOfFile: path)!
    image.setName(name)
    return image
}
let snapshots: String? = __SNAPSHOTS__
let expectBug = CommandLine.arguments.contains("--expect-bug")
var checks = 0
func check(_ value: @autoclosure () -> Bool, _ message: String) {
    precondition(value(), message)
    checks += 1
}
let initial = PresentationTheme.current
func caption(_ text: String, y: CGFloat, color: NSColor) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.frame = NSMakeRect(20, y, 600, 24)
    field.font = .systemFont(ofSize: 14, weight: .medium)
    field.textColor = color
    return field
}
for (paletteName, palette) in [("dark", nightAccentPalette), ("light", whitePalette)] {
    updateTheme(PresentationTheme(colors: palette, search: initial.search, inputTheme: initial.inputTheme))
    let window = Window(contentRect: NSMakeRect(150, 150, 640, 350), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.level = .floating
    window.isOpaque = true
    window.backgroundColor = palette.background
    window.hasShadow = false
    window.title = "Message selection — component check"
    let root = View(frame: NSMakeRect(0, 0, 640, 350))
    root.backgroundColor = palette.background
    window.contentView = root
    root.addSubview(caption("1. Select “Apply style”", y: 10, color: palette.grayText))
    let contextStep = caption("2. Right-click the message", y: 136, color: palette.grayText)
    root.addSubview(contextStep)
    let result = caption("", y: 300, color: palette.text)
    root.addSubview(result)
    let bubble = View(frame: NSMakeRect(12, 168, 616, 100))
    bubble.backgroundColor = palette.grayBackground
    bubble.layer?.cornerRadius = 18
    root.addSubview(bubble)
    let scene = ChatLayerSceneView(frame: NSMakeRect(16, 24, 560, 40))
    bubble.addSubview(scene)
    let selectionColor = palette.accent.withAlphaComponent(0.4)
    let message = NSAttributedString.initialize(string: "Choose “Apply style” to update the message.", color: palette.text, font: .normal(18))
    let layout = TextViewLayout(message, selectText: selectionColor)
    layout.measure(width: 560)
    let selected = (layout.attributedString.string as NSString).range(of: "Apply style")
    let reference = View(frame: NSMakeRect(12, 42, 616, 80))
    reference.backgroundColor = palette.grayBackground
    reference.layer?.cornerRadius = 18
    root.addSubview(reference)
    let referenceScene = ChatLayerSceneView(frame: NSMakeRect(16, 24, 560, 40))
    reference.addSubview(referenceScene)
    let referenceLayout = TextViewLayout(message, selectText: selectionColor)
    referenceLayout.measure(width: 560)
    referenceLayout.selectedRange = TextSelectedRange(range: selected, color: selectionColor, def: true)
    let referenceNode = ChatLayerTextNode(id: "selected-reference", layout: referenceLayout)
    referenceNode.frame = NSRect(origin: .zero, size: referenceLayout.layoutSize)
    try! referenceScene.root.setChildren([referenceNode])
    referenceScene.layoutSubtreeIfNeeded()
    let node = ChatLayerTextNode(id: "message", layout: layout)
    node.frame = NSRect(origin: .zero, size: layout.layoutSize)
    try! scene.root.setChildren([node])
    scene.layoutSubtreeIfNeeded()
    let owner = SelectionFixture(node)
    var shown: ContextMenu?
    var quoteItem: ContextMenuItem?
    var quoted = ""
    node.onPointer = { event in
        guard event.kind == .down else { return true }
        if event.button == 1 || event.modifiers.contains(.control) {
            let range = layout.selectedRange.range
            let text = range.location == NSNotFound ? "" : layout.attributedString.attributedSubstring(from: range).string
            let menu = ContextMenu()
            let item = ContextMenuItem("Quote", handler: { quoted = text }, overrideWidth: 180)
            menu.addItem(item)
            menu.addItem(ContextMenuItem("Copy", handler: {}))
            quoteItem = item
            shown = menu
            AppMenu.show(menu: menu, event: event.nativeEvent!, for: scene)
        }
        return true
    }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    for (name, button, flags, opensMenu) in [
        ("right-click", 1, NSEvent.ModifierFlags(), true),
        ("control-click", 0, NSEvent.ModifierFlags.control, true),
        ("control-shift-click", 0, [.control, .shift], true),
        ("primary-click", 0, [], false),
        ("middle-click", 2, [], false)
    ] {
        AppMenu.closeAll()
        scene.cancelInput()
        scene.focus(nil)
        window.makeKeyAndOrderFront(nil)
        check(window.makeFirstResponder(owner), "selection owner did not become first responder")
        layout.selectedRange = TextSelectedRange(range: selected, color: selectionColor, def: true)
        node.drawingLayer.setNeedsDisplay()
        let previousClears = owner.clears
        let point = NSMakePoint(node.frame.width - 5, 12)
        let native = NSEvent.mouseEvent(with: button == 1 ? .rightMouseDown : .leftMouseDown, location: scene.convert(point, to: nil), modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        check(scene.handlePointer(.down, at: point, button: button, native: native), "pointer was not handled")
        let shouldFocus = expectBug || (button == 0 && !flags.contains(.control))
        check((window.firstResponder === scene) == shouldFocus, "context click moved keyboard focus")
        check((owner.clears > previousClears) == shouldFocus, "selection owner was unexpectedly resigned")
        check((layout.selectedRange.range == selected) == !shouldFocus, "visible text selection disagrees with focus ownership")
        if opensMenu {
            check(shown?.isShown == true, "context menu did not open")
            quoteItem?.handler?()
            check(quoted == "Apply style", "quote did not use the selected text")
            print("\(paletteName) \(name): menu open, owner retained \(window.firstResponder === owner), visible selection \(layout.selectedRange.range == selected), quote correct")
            if let snapshots, name == "right-click" || name == "control-click" {
                contextStep.stringValue = name == "control-click" ? "2. Control-click the message" : "2. Right-click the message"
                result.stringValue = layout.selectedRange.range == selected
                    ? "Highlight stays visible. Quote receives “\(quoted)”."
                    : "Highlight disappears. Quote still receives “\(quoted)”."
                window.display()
                CATransaction.flush()
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                let rect = window.convertToScreen(root.convert(root.bounds, to: nil))
                let top = NSScreen.screens.first!.frame.maxY
                let region = "\(Int(rect.minX)),\(Int(top - rect.maxY)),\(Int(rect.width)),\(Int(rect.height))"
                let capture = Process()
                capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                capture.arguments = ["-x", "-R", region, snapshots + "/" + paletteName + "-" + name + ".png"]
                try! capture.run()
                capture.waitUntilExit()
                precondition(capture.terminationStatus == 0, "Component and menu capture failed")
            }
        }
    }
    AppMenu.closeAll()
    _ = window.makeFirstResponder(nil)
    window.orderOut(nil)
}
print("PASS: \(checks) native scene dispatch, context-menu, focus, selection and quote checks\(expectBug ? " (baseline bug reproduced)" : "")")
