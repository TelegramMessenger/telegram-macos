import XCTest
import Cocoa
import WidgetSandbox
import TwidgetRenderer
@testable import HTMLBubbles

final class BotDocumentAnimationTests: XCTestCase {
    final class Space: WidgetFeedSpace {
        var slots: [WidgetFeedSlot] = []
        var feedViewport: CGRect { return CGRect(x: 0, y: 0, width: 440, height: 600) }
        var feedOnScreen: Bool { return true }
        func feedSlots(in rect: CGRect) -> [WidgetFeedSlot] { return slots }
    }

    static let probe = """
    <script>
    var __frames = 0;
    (function tick() { __frames++; if (__frames < 1000) requestAnimationFrame(tick); })();
    setTimeout(function () {
      var cl = document.getElementById('cl'), price = document.getElementById('price');
      console.log('probe frames=' + __frames + ' price=' + (price ? price.textContent.replace(/\\s/g, '') : 'none') + ' line=' + (cl ? (cl.getAttribute('d') || '').length : -1));
    }, 1500);
    </script>
    """

    private func pump(_ seconds: TimeInterval, until: (() -> Bool)? = nil) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline && !(until?() ?? false) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private func chartHTML(_ name: String = "chart.html") throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Corpus/bot/\(name)").standardized
        return try String(contentsOf: url, encoding: .utf8) + BotDocumentAnimationTests.probe
    }

    private struct Probe {
        let frames: Int
        let price: String
        let line: Int
    }

    private func probe(_ state: HTMLBubbleState) -> Probe? {
        guard let text = state.twidgetHost?.diagnostics.logs.map({ $0.text }).last(where: { $0.hasPrefix("probe ") }) else {
            return nil
        }
        var values: [String: String] = [:]
        for part in text.dropFirst(6).split(separator: " ") {
            let pair = part.split(separator: "=", maxSplits: 1)
            values[String(pair[0])] = pair.count > 1 ? String(pair[1]) : ""
        }
        return Probe(frames: Int(values["frames"] ?? "") ?? 0, price: values["price"] ?? "", line: Int(values["line"] ?? "") ?? -1)
    }

    private func run(prepare: Bool, name: String = "chart.html") throws -> Probe {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.orderFrontRegardless()
        defer { window.close() }

        let state = HTMLDocumentBubbles.makeState(html: try chartHTML(name))
        let appearance = HTMLBubbleAppearance(key: "test", css: "", dark: false, incoming: true)
        if prepare {
            let done = expectation(description: "prepare")
            DispatchQueue.global().async {
                _ = state.prepareTwidget(appearance: appearance, width: 412, wait: 2)
                done.fulfill()
            }
            wait(for: [done], timeout: 5)
        }
        let space = Space()
        let slot = try XCTUnwrap(state.twidgetSlot(appearance: appearance, width: 412, locate: { CGRect(x: 0, y: 0, width: 412, height: 321) }))
        slot.space = space
        space.slots = [slot]
        WidgetFeed.shared.attach(space)
        defer { WidgetFeed.shared.detach(space) }
        WidgetFeed.shared.update()
        pump(10, until: { state.twidgetHost?.diagnostics.loaded == true })
        let host = try XCTUnwrap(state.twidgetHost)
        host.view.frame = NSRect(x: 0, y: 0, width: 412, height: 321)
        window.contentView?.addSubview(host.view)
        WidgetFeed.shared.update()
        pump(6, until: { self.probe(state) != nil })
        let result = try XCTUnwrap(probe(state), "no probe log: \(state.twidgetHost?.diagnostics.logs.map { $0.text } ?? [])")
        return result
    }

    func testChartAnimatesWhenBootedLive() throws {
        let result = try run(prepare: false)
        XCTAssertGreaterThan(result.frames, 10)
        XCTAssertFalse(result.price.isEmpty)
        XCTAssertGreaterThan(result.line, 100)
    }

    func testChartAnimatesAfterBackgroundPrepare() throws {
        let result = try run(prepare: true)
        XCTAssertGreaterThan(result.frames, 10)
        XCTAssertFalse(result.price.isEmpty)
        XCTAssertGreaterThan(result.line, 100)
    }

    func testRealGramChartAnimatesAfterBackgroundPrepare() throws {
        for _ in 0 ..< 3 {
            let result = try run(prepare: true, name: "gram-real.html")
            XCTAssertGreaterThan(result.frames, 10)
        }
    }

    func testChartAnimatesAfterBackgroundPrepareRepeatedly() throws {
        for _ in 0 ..< 3 {
            let result = try run(prepare: true)
            XCTAssertGreaterThan(result.frames, 10)
            XCTAssertGreaterThan(result.line, 100)
        }
    }
}
