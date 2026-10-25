import AppKit
import TGUIKit
import ColorPalette

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)
let images = ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand"].map { name in
    let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in true }
    image.setName(name)
    return image
}
let initial = PresentationTheme.current
System.updateScaleFactor(2)
System.liquidGlass = true
let window = Window(contentRect: NSMakeRect(150, 150, 620, 220), styleMask: [.borderless], backing: .buffered, defer: false)
window.level = .floating
window.isReleasedWhenClosed = false
window.isOpaque = true
window.hasShadow = false
window.makeKeyAndOrderFront(nil)
for (name, palette) in [("dark", nightAccentPalette), ("light", whitePalette)] {
    let theme = PresentationTheme(colors: palette, search: initial.search, inputTheme: initial.inputTheme)
    updateTheme(theme)
    for (phase, title) in [("before", __BEFORE__), ("after", __AFTER__)] {
        let root = View(frame: NSMakeRect(0, 0, 620, 220))
        root.backgroundColor = palette.listBackground
        window.backgroundColor = palette.listBackground
        window.contentView = root
        for (text, y, size) in [("Recent Actions", CGFloat(20), CGFloat(17)), ("Alex joined the channel", CGFloat(84), CGFloat(14))] {
            let label = NSTextField(labelWithString: text)
            label.font = .systemFont(ofSize: size)
            label.textColor = size == 17 ? palette.text : palette.grayText
            label.frame = NSMakeRect(20, y, 580, 24)
            label.alignment = .center
            root.addSubview(label)
        }
        let settings = TextButton()
        __SETUP__
        __STYLE__
        settings.setFrameOrigin(NSMakePoint((root.frame.width - settings.frame.width) / 2, root.frame.height - settings.frame.height - 12))
        root.addSubview(settings)
        root.layoutSubtreeIfNeeded()
        precondition(settings.frame.width >= settings.textSize.width + 30)
        precondition(root.bounds.contains(settings.frame))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.25))
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), __SNAPSHOTS__ + "/\(phase)-\(name).png"]
        try! capture.run()
        capture.waitUntilExit()
        precondition(capture.terminationStatus == 0)
    }
}
window.orderOut(nil)
print("Native Recent Actions label captures saved; button fits and stays centered in both appearances.")
