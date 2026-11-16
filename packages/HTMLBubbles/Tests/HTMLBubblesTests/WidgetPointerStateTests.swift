import XCTest
import Cocoa
import WidgetSandbox
import TwidgetRenderer
@testable import HTMLBubbles

final class WidgetPointerStateTests: XCTestCase {
    final class Space: WidgetFeedSpace {
        var slots: [WidgetFeedSlot] = []
        var feedViewport: CGRect { return CGRect(x: 0, y: 0, width: 440, height: 700) }
        var feedOnScreen: Bool { return true }
        func feedSlots(in rect: CGRect) -> [WidgetFeedSlot] { return slots }
    }

    private func pump(_ seconds: TimeInterval, until: (() -> Bool)? = nil) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline && !(until?() ?? false) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private func interactionHTML() throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../third-party/widget-sandbox/packages/conformance/visual/11-interaction.html").standardized
        return try String(contentsOf: url, encoding: .utf8)
    }

    private final class Harness {
        let window: NSWindow
        let state: HTMLBubbleState
        let space = Space()
        let slot: WidgetFeedSlot
        let bubble: HTMLBubbleView
        let renderer: LiteHTMLWidgetRenderer

        init(_ test: WidgetPointerStateTests, html: String) throws {
            window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 440, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.orderFrontRegardless()
            state = HTMLBubbleState(html: html, outgoing: false, engine: .twidget, selfContained: true)
            state.isWidgetMessage = true
            let appearance = HTMLBubbleAppearance(key: "dark-test", css: "", dark: true, incoming: true)
            slot = try XCTUnwrap(state.twidgetSlot(appearance: appearance, width: 412, locate: { CGRect(x: 0, y: 0, width: 412, height: 600) }))
            slot.space = space
            space.slots = [slot]
            WidgetFeed.shared.attach(space)
            WidgetFeed.shared.update()
            let state = self.state
            test.pump(10, until: { state.twidgetHost?.diagnostics.loaded == true && state.twidgetHost?.diagnostics.rendered == true })
            bubble = HTMLBubbleView(frame: NSRect(x: 14, y: 10, width: 412, height: 600))
            window.contentView?.addSubview(bubble)
            bubble.update(state: state, appearance: appearance, maxWidth: 412, rendering: nil)
            WidgetFeed.shared.update()
            test.pump(0.8)
            renderer = try XCTUnwrap(state.twidgetHost?.rendererObject as? LiteHTMLWidgetRenderer)
        }

        func close() {
            WidgetFeed.shared.detach(space)
            window.close()
        }

        func center(_ id: String) throws -> CGPoint {
            switch id {
            case "press":
                return CGPoint(x: 16, y: 116)
            case "hov":
                return CGPoint(x: 16, y: 248)
            default:
                throw XCTSkip("unknown target \(id)")
            }
        }

        func presented(_ point: CGPoint) -> [Int]? {
            let inWindow = renderer.view.convert(point, to: nil)
            guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]), image.width > 0 else {
                return nil
            }
            let rep = NSBitmapImageRep(cgImage: image)
            let scale = CGFloat(image.width) / window.frame.width
            guard let color = rep.colorAt(x: Int(inWindow.x * scale), y: Int((window.frame.height - inWindow.y) * scale))?.usingColorSpace(.sRGB) else {
                return nil
            }
            return [color.redComponent, color.greenComponent, color.blueComponent].map { Int(($0 * 255).rounded()) }
        }
    }

    func testHoverPaintsInsideABubbleWhenTheViewGetsTheMove() throws {
        let h = try Harness(self, html: try interactionHTML())
        defer { h.close() }
        let hov = try h.center("hov")
        guard let idle = h.presented(hov), idle != [0, 0, 0] else {
            throw XCTSkip("no window capture (screen recording permission or locked screen)")
        }
        let location = h.renderer.view.convert(hov, to: nil)
        let event = NSEvent.mouseEvent(with: .mouseMoved, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: h.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)!
        h.renderer.view.mouseMoved(with: event)
        pump(0.4)
        let hovered = try XCTUnwrap(h.presented(hov))
        XCTAssertGreaterThan(hovered[1], hovered[0] + 40, "\(hovered) is not green on screen (idle \(idle))")
    }
}
