import Cocoa
import XCTest
import WidgetSandbox
@testable import HTMLBubbles

final class WebKitBubbleTests: XCTestCase {
    @MainActor
    func testWebKitBubbleMeasuresInteractsAndCapturesPreview() async throws {
        let state = HTMLBubbleState(html: "<style>body{margin:0}button{height:120px;width:100%}</style><button id='count'>0</button><script>var n=0; document.getElementById('count').onclick=function(){this.textContent=String(++n)}</script>", outgoing: false, engine: .webKit, selfContained: true)
        let appearance = HTMLBubbleAppearance(key: "web-test", css: "", dark: false, incoming: true)
        XCTAssertFalse(state.prepareTwidget(appearance: appearance, width: 360, wait: 0))
        XCTAssertNil(state.startTwidgetPrepare(appearance: appearance, width: 360))
        let bubble = state.twidgetBubble(appearance: appearance, width: 360)
        let host = try XCTUnwrap(bubble.ensureHost())
        XCTAssertTrue(host.rendererObject is RendererWebView)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 360, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView?.addSubview(host.view)
        window.orderFront(nil)
        defer { host.destroy(); window.close() }
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline, !bubble.hostHasContent || state.twidgetSize(width: 360).height != 120 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(bubble.hostHasContent)
        XCTAssertEqual(state.twidgetSize(width: 360).height, 120)
        let clicked: String = await withCheckedContinuation { c in
            host.evaluateInRenderer("document.getElementById('count').click(); 'clicked'") { c.resume(returning: $0) }
        }
        XCTAssertEqual(clicked, "clicked")
        try await Task.sleep(nanoseconds: 200_000_000)
        let text: String = await withCheckedContinuation { c in
            host.evaluateInRenderer("document.getElementById('count').textContent") { c.resume(returning: $0) }
        }
        XCTAssertEqual(text, "1")
        bubble.takeSnapshot()
        let snapshotDeadline = Date().addingTimeInterval(5)
        while Date() < snapshotDeadline, state.twidgetSnapshot == nil {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertNotNil(state.twidgetSnapshot)
    }
}
