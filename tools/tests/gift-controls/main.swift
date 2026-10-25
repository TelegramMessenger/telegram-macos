import AppKit
import TGUIKit
import ColorPalette

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)
let images: [NSImage] = __IMAGE_PATHS__.map { name, path in
    let image = NSImage(contentsOfFile: path)!
    image.setName(name)
    return image
}
enum ImageName { case iconChatActions }
struct HookFixture {
    func image(_ name: ImageName) -> NSImage { NSImage(named: "Icon_ChatActions")! }
}
enum TelegramThemeHooks { static let shared = HookFixture() }
let initial = PresentationTheme.current
for (name, palette) in [("light", whitePalette), ("dark", darkPalette)] {
    updateTheme(PresentationTheme(colors: palette, search: initial.search, inputTheme: initial.inputTheme))
    let window = NSWindow(contentRect: NSMakeRect(150, 150, 350, 70), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let root = View(frame: NSMakeRect(0, 0, 350, 70))
    root.backgroundColor = NSColor(calibratedRed: 0.40, green: 0.64, blue: 0.28, alpha: 1)
    window.contentView = root
    let dismiss = ImageButton()
    dismiss.set(image: NSImage(named: "Icon_Pip_Close")!.precomposed(.white), for: .Normal)
    dismiss.setGlassEffect(size: NSMakeSize(36, 36))
    dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
    dismiss.setFrameOrigin(NSMakePoint(10, 10))
    root.addSubview(dismiss)
    let current = ImageButton()
    __MORE_STYLE__
    current.setFrameOrigin(NSMakePoint(304, 10))
    root.addSubview(current)
    root.layoutSubtreeIfNeeded()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    window.display()
    CATransaction.flush()
    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
    print("\(name): close \(dismiss.frame.size), glass \(String(describing: dismiss.interactiveGlassView?.frame.size)); more \(current.frame.size), glass \(String(describing: current.interactiveGlassView?.frame.size))")
    let capture = Process()
    capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    capture.arguments = ["-x", "-o", "-l", String(window.windowNumber), __SNAPSHOTS__ + "/" + name + ".png"]
    try! capture.run()
    capture.waitUntilExit()
    precondition(capture.terminationStatus == 0, "Window capture failed")
    window.orderOut(nil)
}
