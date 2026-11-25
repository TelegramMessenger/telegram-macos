import XCTest
import Cocoa
import WidgetSandbox
import TwidgetRenderer
@testable import HTMLBubbles

final class BotDocumentMorphTests: XCTestCase {
    final class Space: WidgetFeedSpace {
        var slots: [WidgetFeedSlot] = []
        var feedViewport: CGRect { return CGRect(x: 0, y: 0, width: 440, height: 600) }
        var feedOnScreen: Bool { return true }
        func feedSlots(in rect: CGRect) -> [WidgetFeedSlot] { return slots }
    }

    static let tracker = """
    <script>
    window.__bar = document.getElementById('bar');
    document.addEventListener('widgetupdate', function () {
      console.log('morphed same=' + (window.__bar === document.getElementById('bar')) + ' bar=' + document.getElementById('bar').getAttribute('style').replace(/\\s/g, '') + ' st1=' + document.getElementById('st1').className);
    });
    </script>
    """

    private func pump(_ seconds: TimeInterval, until: (() -> Bool)? = nil) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline && !(until?() ?? false) {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    private func fixture(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Corpus/bot/\(name)").standardized
        return try String(contentsOf: url, encoding: .utf8)
    }

    func testDetectsMorphableDocuments() throws {
        XCTAssertTrue(HTMLDocumentBubbles.isMorphable(try fixture("preparing-1.html")))
        XCTAssertTrue(HTMLDocumentBubbles.isMorphable("<div class=\"widget\" data-morph=\"1\">x</div>"))
        XCTAssertFalse(HTMLDocumentBubbles.isMorphable(try fixture("chart.html")))
        XCTAssertFalse(HTMLDocumentBubbles.isMorphable("<div class=\"widget\"><p data-morph>x</p></div>"))
    }

    func testEditedDocumentMorphsTheLiveWidget() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.orderFrontRegardless()
        defer { window.close() }

        let state = HTMLDocumentBubbles.makeState(html: try fixture("preparing-1.html") + BotDocumentMorphTests.tracker)
        let appearance = HTMLBubbleAppearance(key: "test", css: "", dark: false, incoming: true)
        let space = Space()
        let slot = try XCTUnwrap(state.twidgetSlot(appearance: appearance, width: 412, locate: { CGRect(x: 0, y: 0, width: 412, height: 322) }))
        slot.space = space
        space.slots = [slot]
        WidgetFeed.shared.attach(space)
        defer { WidgetFeed.shared.detach(space) }
        WidgetFeed.shared.update()
        pump(10, until: { state.twidgetHost?.diagnostics.loaded == true })
        let host = try XCTUnwrap(state.twidgetHost)
        host.view.frame = NSRect(x: 0, y: 0, width: 412, height: 322)
        window.contentView?.addSubview(host.view)
        WidgetFeed.shared.update()
        pump(0.5)

        XCTAssertTrue(state.canMorph)
        var applied: Bool?
        let next = try fixture("preparing-2.html") + BotDocumentMorphTests.tracker
        state.morph(html: next) { applied = $0 }
        pump(5, until: { applied != nil && state.twidgetHost?.diagnostics.logs.contains { $0.text.hasPrefix("morphed ") } == true })
        XCTAssertEqual(applied, true)
        XCTAssertTrue(state.twidgetHost === host)
        XCTAssertEqual(state.source, next)
        let log = state.twidgetHost?.diagnostics.logs.last { $0.text.hasPrefix("morphed ") }?.text
        XCTAssertEqual(log, "morphed same=true bar=width:50% st1=st done")
    }
}
