import AppKit
import TGUIKit
import ColorPalette
import ImageIO
import UniformTypeIdentifiers

_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)
System.updateScaleFactor(2)
System.liquidGlass = false
let snapshotPath: String? = __SNAPSHOTS__
let expectBug = CommandLine.arguments.contains("--expect-bug")
var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    checks += 1
}
func drain(_ seconds: Double = 0.08) {
    RunLoop.main.run(until: Date(timeIntervalSinceNow: seconds))
}
let images = ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand"].map { name in
    let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
        NSColor.gray.setFill()
        rect.insetBy(dx: 4, dy: 4).fill()
        return true
    }
    image.setName(name)
    return image
}
let initialTheme = PresentationTheme.current
func label(_ text: String, size: CGFloat = 16) -> NSTextField {
    let field = NSTextField(labelWithString: text)
    field.font = NSFont.systemFont(ofSize: size)
    field.textColor = presentation.colors.text
    return field
}
final class FixtureController: ViewController {
    let title: String
    let realBar: Bool
    let slide: Bool
    let list = View()
    init(_ title: String, barHeight: CGFloat = 64, realBar: Bool = false, slide: Bool = false) {
        self.title = title
        self.realBar = realBar
        self.slide = slide
        super.init()
        bar = .init(height: barHeight)
        animationStyle = .init(duration: 0.03, function: .spring)
    }
    override var defaultBarTitle: String { title }
    override var barIsReal: Bool { realBar }
    override var fullSlideAnimation: Bool { slide }
    override func viewDidLoad() {
        super.viewDidLoad()
        (view as? View)?.backgroundColor = presentation.colors.listBackground
        list.backgroundColor = presentation.colors.background
        list.layer?.cornerRadius = 18
        view.addSubview(list)
        let names = title == "Subscribers" ? ["＋  Add Subscribers", "Alex", "Jamie", "Morgan", "Taylor"] : ["Subscriber profile", "Message", "Call"]
        for (index, name) in names.enumerated() {
            let field = label(name)
            field.frame = NSMakeRect(18, CGFloat(index) * 52 + 16, 220, 24)
            if index == 0 { field.textColor = presentation.colors.accent }
            list.addSubview(field)
        }
        viewDidResized(view.frame.size)
        readyOnce()
    }
    override func viewDidResized(_ size: NSSize) {
        super.viewDidResized(size)
        if isLoaded() {
            let width = min(560, max(0, size.width - 44))
            list.frame = NSMakeRect((size.width - width) / 2, realBar ? 12 : 76, width, 278)
        }
    }
}
let window = Window(contentRect: NSMakeRect(150, 150, 820, 510), styleMask: [.borderless], backing: .buffered, defer: false)
window.isReleasedWhenClosed = false
window.isOpaque = true
window.hasShadow = false
window.level = .floating
let root = View(frame: NSMakeRect(0, 0, 820, 510))
root.backgroundColor = presentation.colors.listBackground
window.contentView = root
let caption = label("", size: 16)
caption.frame = NSMakeRect(18, 10, 784, 26)
root.addSubview(caption)
let footer = label("", size: 14)
footer.textColor = presentation.colors.grayText
footer.frame = NSMakeRect(18, 476, 784, 25)
root.addSubview(footer)
var retained: [NavigationViewController] = []
func navigation(width: CGFloat, height: CGFloat = 420, barHeight: CGFloat = 64, insets: NSEdgeInsets = .init(), realBar: Bool = false, slide: Bool = false, headerHeight: CGFloat = 0, headerOverflow: CGFloat = 0) -> (NavigationViewController, FixtureController, FixtureController) {
    let subscriber = FixtureController("Subscribers", barHeight: barHeight, realBar: realBar)
    subscriber.insets = insets
    let profile = FixtureController("Profile", barHeight: 0, slide: slide)
    let nav = NavigationViewController(subscriber, window)
    nav.loadViewIfNeeded(NSMakeRect(0, 42, width, height))
    root.addSubview(nav.view)
    nav.viewWillAppear(false)
    nav.viewDidAppear(false)
    if headerHeight > 0 {
        let header = NavigationHeader(headerHeight) { header, _, _ in
            let view = NavigationHeaderView(header)
            view.backgroundColor = presentation.colors.background
            view.ready.set(.single(true))
            return (view, headerHeight + headerOverflow)
        }
        nav.set(header: header)
        header.show(false, contextObject: 0)
    }
    nav.viewDidResized(NSMakeSize(width, height))
    retained.append(nav)
    return (nav, subscriber, profile)
}
func begin(_ nav: NavigationViewController, _ subscriber: ViewController) {
    if case let .success(previous) = window.fixtureSwipe(nav, .left(.start(controller: subscriber))) {
        check(previous === subscriber, "Swipe revealed a different controller")
    } else {
        preconditionFailure("Back swipe did not start")
    }
}
func verify(_ nav: NavigationViewController, _ subscriber: ViewController, expected: NSRect, context: String) {
    let frame = nav.fixtureFrame(subscriber)
    if expectBug && subscriber.barHeight != 0 {
        check(frame.minY != expected.minY || frame.height != expected.height, "Baseline no longer reproduces the jump: \(context)")
    } else {
        check(frame.minY == expected.minY, "Vertical jump: \(context): \(frame) != \(expected)")
        check(frame.height == expected.height, "Height changed: \(context)")
        check(frame.width == expected.width, "Width changed: \(context)")
    }
}
for width: CGFloat in [360, 820] {
    for height: CGFloat in [0, 44, 64, 88] {
        for realBar in [false, true] {
            let insets = NSEdgeInsets(top: 7, left: 11, bottom: 13, right: 17)
            let (nav, subscriber, profile) = navigation(width: width, barHeight: height, insets: insets, realBar: realBar, slide: width == 360)
            let expected = nav.fixtureFrame(subscriber)
            nav.push(profile, false)
            drain(0.01)
            begin(nav, subscriber)
            verify(nav, subscriber, expected: expected, context: "start")
            for progress: CGFloat in [0.01, 0.25, 0.5, 0.75, 0.99] {
                _ = window.fixtureSwipe(nav, .left(.swiping(delta: width * progress, controller: subscriber)))
                verify(nav, subscriber, expected: expected, context: "progress \(progress)")
            }
            _ = window.fixtureSwipe(nav, .left(.failed(delta: width * 0.99, controller: subscriber)), animated: false)
            check(nav.controller === profile, "Cancelled swipe popped the profile")
            begin(nav, subscriber)
            verify(nav, subscriber, expected: expected, context: "repeated start")
            _ = window.fixtureSwipe(nav, .left(.swiping(delta: width * 0.8, controller: subscriber)))
            _ = window.fixtureSwipe(nav, .left(.success(delta: width * 0.8, controller: subscriber)))
            drain(0.12)
            check(nav.controller === subscriber, "Completed swipe did not restore subscribers")
            check(nav.fixtureFrame(subscriber) == expected, "Settled layout changed")
            nav.viewWillDisappear(false)
            nav.view.removeFromSuperview()
        }
    }
}
for overflow: CGFloat in [0, 20] {
    let (nav, subscriber, profile) = navigation(width: 820, headerHeight: 30, headerOverflow: overflow)
    let expected = nav.fixtureFrame(subscriber)
    nav.push(profile, false)
    begin(nav, subscriber)
    verify(nav, subscriber, expected: expected, context: "navigation header \(overflow)")
    _ = window.fixtureSwipe(nav, .left(.failed(delta: 0, controller: subscriber)), animated: false)
    nav.viewWillDisappear(false)
    nav.view.removeFromSuperview()
}
func capture(_ path: String) {
    root.layoutSubtreeIfNeeded()
    drain(0.1)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-o", "-l", String(window.windowNumber), path]
    try! process.run()
    process.waitUntilExit()
    check(process.terminationStatus == 0, "Screenshot failed")
}
if let snapshotPath {
    window.makeKeyAndOrderFront(nil)
    for (name, palette) in [("dark", nightAccentPalette), ("light", dayClassicPalette)] {
        updateTheme(PresentationTheme(colors: palette, search: initialTheme.search, inputTheme: initialTheme.inputTheme))
        root.backgroundColor = palette.listBackground
        window.backgroundColor = palette.listBackground
        caption.textColor = palette.text
        footer.textColor = palette.grayText
        let (nav, subscriber, profile) = navigation(width: 820)
        nav.push(profile, false)
        begin(nav, subscriber)
        _ = window.fixtureSwipe(nav, .left(.swiping(delta: 820 * 0.78, controller: subscriber)))
        caption.stringValue = "Swipe back from a subscriber’s profile — 78% complete"
        footer.stringValue = "Subscribers top edge: \(Int(nav.fixtureFrame(subscriber).minY)) pt"
        capture(snapshotPath + "/\(name)-during.png")
        _ = window.fixtureSwipe(nav, .left(.success(delta: 820 * 0.78, controller: subscriber)))
        drain(0.2)
        caption.stringValue = "Swipe back complete"
        footer.stringValue = "Subscribers top edge: \(Int(nav.fixtureFrame(subscriber).minY)) pt"
        capture(snapshotPath + "/\(name)-settled.png")
        let url = URL(fileURLWithPath: snapshotPath + "/\(name)-swipe.gif")
        let gif = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString, 2, nil)!
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for phase in ["during", "settled"] {
            let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: snapshotPath + "/\(name)-\(phase).png") as CFURL, nil)!
            CGImageDestinationAddImageFromSource(gif, source, 0, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.3]] as CFDictionary)
        }
        check(CGImageDestinationFinalize(gif), "GIF export failed")
        nav.viewWillDisappear(false)
        nav.view.removeFromSuperview()
    }
}
window.orderOut(nil)
print("Navigation swipe: \(checks) assertions passed (\(expectBug ? "baseline reproduces jump" : "fixed"))")
