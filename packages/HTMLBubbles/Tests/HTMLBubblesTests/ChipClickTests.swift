import XCTest
import Cocoa
import WidgetSandbox
import TwidgetRenderer
@testable import HTMLBubbles

final class ChipClickTests: XCTestCase {
    final class Space: WidgetFeedSpace {
        var slots: [WidgetFeedSlot] = []
        var viewport = CGRect(x: 0, y: 0, width: 440, height: 600)
        var feedViewport: CGRect { return viewport }
        var feedOnScreen: Bool { return true }
        func feedSlots(in rect: CGRect) -> [WidgetFeedSlot] { return slots }
    }

    static let chipHTML = """
    <style>body{margin:0}.chip{display:inline-block;padding:30px 80px;background:#eef;border-radius:14px;color:#2481cc;text-decoration:none}</style>
    <div style="padding:10px"><a class="chip" href="https://example.com/chicken">/chicken</a></div>
    <script>setTimeout(function () { document.querySelector('a').click(); }, 200);</script>
    """

    static let sendChipHTML = """
    <style>body{margin:0}.chip{display:inline-block;padding:30px 80px;background:#eef;border-radius:14px;color:#2481cc;text-decoration:none}</style>
    <div style="padding:10px"><a class="chip" href="chat:send?text=/chicken">/chicken</a></div>
    <script>document.querySelector('a').addEventListener('click', function () { try { TelegramWidget.sendMessage('/chicken'); } catch (e) {} });</script>
    """

    func pump(_ seconds: TimeInterval, until: (() -> Bool)? = nil) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline && !(until?() ?? false) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    final class Harness {
        let window: NSWindow
        let state: HTMLBubbleState
        let space = Space()
        let slot: WidgetFeedSlot
        let view: NSView
        final class Links {
            var urls: [String] = []
        }
        let recorded = Links()
        var links: [String] {
            get { return recorded.urls }
            set { recorded.urls = newValue }
        }

        init(_ test: ChipClickTests, html: String) throws {
            window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.ignoresMouseEvents = true
            window.orderFrontRegardless()
            state = HTMLBubbleState(html: html, outgoing: false, engine: .twidget, selfContained: true)
            let recorded = self.recorded
            state.linkHandler = { _, url in recorded.urls.append(url) }
            state.widgetActionHandler = { _, action in
                switch action {
                case let .openLink(url):
                    recorded.urls.append("openLink " + url.absoluteString)
                case let .openTelegramLink(url):
                    recorded.urls.append("openTelegramLink " + url.absoluteString)
                }
            }
            let appearance = HTMLBubbleAppearance(key: "test", css: "", dark: false, incoming: true)
            slot = try XCTUnwrap(state.twidgetSlot(appearance: appearance, width: 420, locate: { CGRect(x: 0, y: 0, width: 420, height: 200) }))
            slot.space = space
            space.slots = [slot]
            WidgetFeed.shared.attach(space)
            WidgetFeed.shared.update()
            let state = self.state
            test.pump(10, until: { state.twidgetHost?.diagnostics.rendered == true && state.twidgetHost?.diagnostics.loaded == true })
            let host = try XCTUnwrap(state.twidgetHost)
            host.view.frame = NSRect(x: 0, y: 0, width: 420, height: 200)
            window.contentView?.addSubview(host.view)
            WidgetFeed.shared.update()
            view = try XCTUnwrap((host.rendererObject as? LiteHTMLWidgetRenderer)?.view)
        }

        func close() {
            WidgetFeed.shared.detach(space)
            window.close()
        }

        func send(_ type: NSEvent.EventType, _ point: NSPoint) {
            let location = view.convert(point, to: nil)
            if type == .scrollWheel {
                guard let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -40, wheel2: 0, wheel3: 0) else { return }
                cg.location = window.convertPoint(toScreen: location)
                if let event = NSEvent(cgEvent: cg) { view.scrollWheel(with: event) }
                return
            }
            let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0)!
            switch type {
            case .leftMouseDown: view.mouseDown(with: event)
            case .leftMouseUp: view.mouseUp(with: event)
            default: view.mouseMoved(with: event)
            }
        }

        var point: NSPoint {
            return NSPoint(x: 60, y: view.isFlipped ? 40 : view.bounds.height - 40)
        }
    }

    func testOneRealClickOnAVisibleChipOpensExactlyOneLink() throws {
        HTMLBubbleUserAction.reset()
        let savedInputAge = HTMLBubbleUserAction.inputAge
        defer { HTMLBubbleUserAction.inputAge = savedInputAge }
        var inputAge: CFTimeInterval = 30
        HTMLBubbleUserAction.inputAge = { inputAge }

        let h = try Harness(self, html: ChipClickTests.chipHTML)
        defer { h.close() }
        XCTAssertTrue(h.slot.isVisible)
        let point = h.point

        inputAge = 0.05
        for k in 0..<30 {
            h.send(.mouseMoved, NSPoint(x: point.x + CGFloat(k), y: point.y))
            pump(0.03)
        }
        pump(0.5)
        XCTAssertEqual(h.links, [], "a link opened without a click")

        h.send(.leftMouseDown, point)
        h.send(.leftMouseUp, point)
        pump(3, until: { !h.links.isEmpty })
        pump(0.5)
        XCTAssertEqual(h.links, ["openLink https://example.com/chicken"])

        h.links.removeAll()
        inputAge = 30
        pump(0.8)
        h.send(.leftMouseDown, point)
        h.send(.leftMouseUp, point)
        pump(1.5)
        XCTAssertEqual(h.links, [], "a click without real input opened a link")
    }

    func testARealClickOnAChatSendChipSendsNothing() throws {
        HTMLBubbleUserAction.reset()
        let savedInputAge = HTMLBubbleUserAction.inputAge
        defer { HTMLBubbleUserAction.inputAge = savedInputAge }
        HTMLBubbleUserAction.inputAge = { 0.05 }

        let h = try Harness(self, html: ChipClickTests.sendChipHTML)
        defer { h.close() }
        XCTAssertTrue(h.slot.isVisible)
        h.send(.leftMouseDown, h.point)
        h.send(.leftMouseUp, h.point)
        pump(1.5)
        XCTAssertEqual(h.links, [])
        let blocked = h.state.twidgetHost?.diagnostics.diags["navigation-blocked"]?.count ?? 0
        XCTAssertGreaterThan(blocked, 0, "the click never reached the chip")
    }

    func testScrollingPastWidgetsWithoutAClickOpensNothing() throws {
        HTMLBubbleUserAction.reset()
        let savedInputAge = HTMLBubbleUserAction.inputAge
        defer { HTMLBubbleUserAction.inputAge = savedInputAge }
        HTMLBubbleUserAction.inputAge = { 0.05 }
        let corpus = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Corpus/attacks").standardized
        for name in ["activation-scroll-hover.html", "activation-timers.html", "activation-animation-events.html", "activation-synthetic-input.html"] {
            let html = try String(contentsOf: corpus.appendingPathComponent(name), encoding: .utf8)
            let h = try Harness(self, html: html)
            for step in 0..<60 {
                h.send(.scrollWheel, NSPoint(x: 40 + CGFloat(step * 5 % 300), y: 30 + CGFloat(step * 3 % 150)))
                h.send(.mouseMoved, NSPoint(x: 40 + CGFloat(step * 7 % 300), y: 20 + CGFloat(step * 2 % 160)))
                if step % 10 == 5 {
                    h.space.viewport.origin.y = h.space.viewport.origin.y == 0 ? 2000 : 0
                    WidgetFeed.shared.update()
                }
                pump(0.03)
            }
            h.space.viewport.origin.y = 0
            WidgetFeed.shared.update()
            pump(1.5)
            XCTAssertEqual(h.links, [], name)
            let blocked = h.state.twidgetHost?.diagnostics.diags["activation-blocked"]?.count ?? 0
            if name == "activation-scroll-hover.html" {
                XCTAssertGreaterThan(blocked, 0, "the scroll and hover events never reached the widget")
            }
            h.close()
            pump(0.2)
        }
    }
}
