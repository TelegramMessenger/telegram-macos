import XCTest
import Cocoa
import WidgetSandbox
import TwidgetRenderer
@testable import HTMLBubbles

final class WidgetTextSelectionWindowTests: XCTestCase {
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

    private static let html = #"<style>body{margin:0;background:#000}#t{margin:0;font:22px/32px sans-serif;color:#fff;user-select:text}</style><p id="t">Selectable words here one two three four five six seven eight nine ten eleven twelve thirteen fourteen</p>"#

    private final class Harness {
        let window: NSWindow
        let state: HTMLBubbleState
        let space = Space()
        let slot: WidgetFeedSlot
        let bubble: HTMLBubbleView
        let renderer: LiteHTMLWidgetRenderer

        init(_ test: WidgetTextSelectionWindowTests) throws {
            _ = NSApplication.shared
            window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 440, height: 700), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua)
            window.orderFrontRegardless()
            state = HTMLBubbleState(html: WidgetTextSelectionWindowTests.html, outgoing: false, engine: .twidget, selfContained: true)
            state.isWidgetMessage = true
            let appearance = HTMLBubbleAppearance(key: "selection-test", css: "", dark: true, incoming: true, textSelectionColor: NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
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

        func firstLine(x: CGFloat) -> CGPoint {
            let view = renderer.view
            let y: CGFloat = view.isFlipped ? 16 : view.bounds.height - 16
            return view.convert(CGPoint(x: x, y: y), to: nil)
        }

        func send(_ type: NSEvent.EventType, _ location: CGPoint, clicks: Int = 1) {
            let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: type == .leftMouseUp ? 0 : 1)!
            window.sendEvent(event)
        }

        func redPixels() -> Int? {
            guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution]), image.width > 0 else {
                return nil
            }
            let rep = NSBitmapImageRep(cgImage: image)
            var count = 0
            var y = 0
            while y < rep.pixelsHigh {
                var x = 0
                while x < rep.pixelsWide {
                    if let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), color.redComponent > 0.7, color.greenComponent < 0.3, color.blueComponent < 0.3 {
                        count += 1
                    }
                    x += 4
                }
                y += 4
            }
            return count
        }
    }

    func testDragThroughTheWindowSelectsAndHighlightsOnScreen() throws {
        let h = try Harness(self)
        defer { h.close() }
        let hitView = h.window.contentView?.hitTest(h.window.contentView!.convert(h.firstLine(x: 4), from: nil))
        let hitName = hitView.map { String(describing: type(of: $0)) } ?? "nil"
        let start = h.firstLine(x: 4)
        let end = h.firstLine(x: 300)
        h.send(.leftMouseDown, start)
        h.send(.leftMouseDragged, CGPoint(x: (start.x + end.x) / 2, y: start.y))
        h.send(.leftMouseDragged, end)
        h.send(.leftMouseUp, end)
        pump(0.4)
        let text = h.state.twidgetSelectedText
        XCTAssertNotNil(text, "no selection after a window drag; hit view \(hitName)")
        XCTAssertEqual(h.bubble.selectedText, text)
        XCTAssertTrue(h.window.firstResponder === h.bubble, "first responder \(String(describing: h.window.firstResponder))")
        guard let red = h.redPixels() else {
            throw XCTSkip("no window capture (screen recording permission or locked screen)")
        }
        XCTAssertGreaterThan(red, 50, "selection highlight not on screen; hit view \(hitName), text \(text ?? "nil")")
    }
}
