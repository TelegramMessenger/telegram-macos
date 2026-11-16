import Cocoa
import XCTest
import WidgetSandbox
@testable import HTMLBubbles

final class CanvasGradientLifetimeTests: XCTestCase {
    private final class Space: WidgetFeedSpace {
        var slots: [WidgetFeedSlot] = []
        var feedViewport: CGRect { CGRect(x: 0, y: 0, width: 120, height: 80) }
        var feedOnScreen: Bool { true }
        func feedSlots(in rect: CGRect) -> [WidgetFeedSlot] { slots }
    }

    private func pump(_ seconds: TimeInterval, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline, !condition() {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    @MainActor
    func testGradientChurnKeepsWaveformAndSavedPaintsVisibleInBothRenderers() throws {
        let html = """
        <style>body{margin:0;background:white}canvas{display:block}</style><canvas id=c width=80 height=60></canvas>
        <script>
        const x = document.getElementById('c').getContext('2d');
        function gradient(color) {
          const g = x.createLinearGradient(0, 60, 0, 0);
          g.addColorStop(0, color); g.addColorStop(1, color);
          return g;
        }
        x.fillStyle = gradient('red'); x.save();
        x.fillStyle = gradient('blue'); x.save();
        let frames = 0;
        function draw() {
          x.clearRect(0, 0, 80, 60);
          for (let i = 0; i < 128; i++) {
            x.fillStyle = gradient('#00ff00');
            x.fillRect(0, 20, 80, 40);
          }
          if (++frames < 80) setTimeout(draw, 0);
          else {
            x.restore(); x.fillRect(0, 0, 20, 20);
            x.restore(); x.fillRect(20, 0, 20, 20);
            console.log('gradient-churn-complete');
          }
        }
        setTimeout(draw, 0);
        </script>
        """
        for engine in [HTMLRenderEngine.twidget, .webKit] {
            let state = HTMLBubbleState(html: html, outgoing: false, engine: engine, selfContained: true)
            let appearance = HTMLBubbleAppearance(key: "gradient-churn", css: "", dark: false, incoming: true)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 120, height: 80), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.level = .floating
            window.orderFrontRegardless()
            defer { window.close() }
            let space = Space()
            let slot = try XCTUnwrap(state.twidgetSlot(appearance: appearance, width: 120, locate: { space.feedViewport }))
            slot.space = space
            space.slots = [slot]
            let feed = HTMLTwidgetTableSpace.feed(for: engine)
            feed.attach(space)
            defer { feed.detach(space) }
            feed.update()
            pump(10) { state.twidgetHost?.diagnostics.loaded == true }
            let host = try XCTUnwrap(state.twidgetHost)
            host.view.frame = window.contentView!.bounds
            window.contentView?.addSubview(host.view)
            feed.update()
            defer { host.destroy() }
            pump(20) { host.diagnostics.logs.contains { $0.text == "gradient-churn-complete" } }
            XCTAssertTrue(host.diagnostics.logs.contains { $0.text == "gradient-churn-complete" }, "\(engine): \(host.diagnostics.logs)")
            XCTAssertNil(host.diagnostics.dead)
            XCTAssertNil(host.diagnostics.lastError)
            pump(0.1) { false }
            var snapshot: NSImage?
            var captured = false
            host.snapshot { snapshot = $0; captured = true }
            pump(5) { captured }
            let image = try XCTUnwrap(snapshot)
            let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            func color(_ x: CGFloat, _ y: CGFloat) throws -> NSColor {
                try XCTUnwrap(bitmap.colorAt(x: Int(x * CGFloat(bitmap.pixelsWide) / image.size.width), y: Int(y * CGFloat(bitmap.pixelsHigh) / image.size.height))?.usingColorSpace(.sRGB))
            }
            let blue = try color(10, 10), red = try color(30, 10), green = try color(10, 40)
            XCTAssertGreaterThan(blue.blueComponent, 0.85, "\(engine)")
            XCTAssertLessThan(blue.redComponent, 0.15, "\(engine)")
            XCTAssertGreaterThan(red.redComponent, 0.85, "\(engine)")
            XCTAssertLessThan(red.blueComponent, 0.15, "\(engine)")
            XCTAssertGreaterThan(green.greenComponent, 0.85, "\(engine)")
            XCTAssertLessThan(green.redComponent, 0.15, "\(engine)")
            XCTAssertLessThan(green.blueComponent, 0.15, "\(engine)")
        }
    }
}
