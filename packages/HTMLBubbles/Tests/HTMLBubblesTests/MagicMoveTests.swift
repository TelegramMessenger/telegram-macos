import XCTest
import AppKit
@testable import HTMLBubbles

private final class OnScreenWindow: NSWindow {
    override var occlusionState: NSWindow.OcclusionState {
        return .visible
    }
}

final class MagicMoveTests: XCTestCase {
    private static let html = """
    <style>.c { display: inline-block; width: 70px; height: 34px; margin: 4px; padding: 6px; border-radius: 8px; color: #ffffff; font-weight: 700; }</style>
    <div>fallback</div>
    <script>
    const colors = ['#ff3b30', '#ff9500', '#34c759', '#007aff', '#af52de'];
    let order = [0, 1, 2, 3];
    let step = 0;
    function render() {
      return '<div>' + order.map(n => `<div class="c" data-key="k${n}" style="background-color: ${colors[n]}">Item ${n}<br>${step}</div>`).join('') + '</div>';
    }
    setTimeout(() => { transition('move'); step = 1; order = [4, 3, 1, 0]; }, 600);
    </script>
    """

    private func run(_ seconds: TimeInterval, every interval: TimeInterval = 0.01, _ body: () -> Void = {}) {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(interval))
            body()
        }
    }

    private func layers(_ root: CALayer, where predicate: (CALayer) -> Bool) -> [CALayer] {
        var found: [CALayer] = []
        func visit(_ layer: CALayer) {
            if predicate(layer) {
                found.append(layer)
            }
            layer.sublayers?.forEach(visit)
        }
        visit(root)
        return found
    }

    static let flightKeys: Set<String> = ["move", "enter", "leave", "position.x", "position.y", "bounds.size.width", "bounds.size.height"]

    func testMoveTransitionFliesKeyedElements() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["HTMLBUBBLES_UI_TESTS"] != nil, "Needs an unlocked screen; set HTMLBUBBLES_UI_TESTS=1")
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        let state = HTMLBubbleState(html: MagicMoveTests.html, outgoing: false, engine: .litehtml)
        let appearance = HTMLBubbleAppearance(key: "magic-test", css: "body { font-family: -apple-system; font-size: 13px; line-height: 1.3; color: #000000; }", dark: false, incoming: true)
        let window = OnScreenWindow(contentRect: NSRect(x: 80, y: 80, width: 380, height: 160), styleMask: [.borderless], backing: .buffered, defer: false)
        window.backgroundColor = .white
        window.level = .floating
        window.orderFrontRegardless()
        let view = HTMLBubbleView(frame: NSRect(x: 10, y: 10, width: 360, height: 100))
        view.onContentChanged = { size, _ in
            view.frame.size = NSSize(width: 360, height: size.height)
        }
        run(0.3)
        window.contentView?.addSubview(view)
        run(0.1)
        state.start()
        view.update(state: state, appearance: appearance, maxWidth: 360, rendering: nil)
        run(0.4)
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("html-bubble-magic")
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var flying = 0
        var frames = 0
        run(1.3, every: 0.04) {
            guard let root = view.layer else {
                return
            }
            let moving = layers(root) { ($0.animationKeys() ?? []).contains { MagicMoveTests.flightKeys.contains($0) } }
            flying = max(flying, moving.count)
            if !moving.isEmpty, let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) {
                let rep = NSBitmapImageRep(cgImage: image)
                try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("frame\(frames).png"))
                frames += 1
            }
        }
        XCTAssertGreaterThanOrEqual(flying, 4, "keyed elements should fly: 3 moves, 1 enter and 1 leave")
        let leftover = layers(view.layer!) { $0.animationKeys() != nil && !($0.animationKeys() ?? []).isEmpty && $0.contents != nil && $0.superlayer?.superlayer != nil && $0.zPosition >= 1 && $0.zPosition <= 2 && !Set($0.animationKeys()!).isDisjoint(with: MagicMoveTests.flightKeys) }
        XCTAssertTrue(leftover.isEmpty, "magic layers should be gone after the flight")
        if let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]) {
            try NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("final.png"))
        }
        print("magic frames: \(frames) in \(directory.path), most layers in flight \(flying)")
        window.orderOut(nil)
    }
}
