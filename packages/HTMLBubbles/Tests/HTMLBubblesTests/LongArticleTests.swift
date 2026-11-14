import Cocoa
import XCTest
import WidgetSandbox
import LiteHTML
@testable import HTMLBubbles

final class LongArticleTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        DemoFixtures.install()
    }

    private final class DocumentView: NSView {
        override var isFlipped: Bool { true }
    }

    private struct Rect: Codable {
        let x: CGFloat
        let y: CGFloat
        let width: CGFloat
        let height: CGFloat
        var bottom: CGFloat { y + height }
    }

    private struct Measurement: Codable {
        let width: CGFloat
        let dark: Bool
        let card: Rect
        let tags: Rect
        let pre: Rect
        let rule: Rect
        let preClientWidth: CGFloat
        let preScrollWidth: CGFloat
        let headings: [Rect]
        let listItems: Int
    }

    private static let probe = """
    <script>
    var previousArticleMeasurement = '';
    setInterval(function () {
      var card = document.querySelector('.card'), tags = document.querySelector('.tags'), pre = document.querySelector('pre');
      function rect(element) { var r = element.getBoundingClientRect(); return {x:r.x,y:r.y,width:r.width,height:r.height}; }
      var data = JSON.stringify({width:innerWidth,dark:matchMedia('(prefers-color-scheme: dark)').matches,
        card:rect(card),tags:rect(tags),pre:rect(pre),rule:rect(document.querySelector('hr')),preClientWidth:pre.clientWidth,preScrollWidth:pre.scrollWidth,
        headings:Array.from(document.querySelectorAll('h1,h2,h3')).map(rect),listItems:document.querySelectorAll('li').length});
      if (data !== previousArticleMeasurement) { console.log('article-measurement:' + data); previousArticleMeasurement = data; }
    }, 100);
    </script>
    """

    private func measurement(_ host: WidgetHost) -> Measurement? {
        let prefix = "article-measurement:"
        guard let text = host.diagnostics.logs.last(where: { $0.text.hasPrefix(prefix) })?.text,
              let data = String(text.dropFirst(prefix.count)).data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Measurement.self, from: data)
    }

    @MainActor
    func testLongArticleFitsBothRenderersAcrossWidthsAndThemes() async throws {
        let article = try XCTUnwrap(HTMLDemoCatalog.widgetFiles(.allWidgets).first { $0.name.hasSuffix("04-long-article.html") })
        let corpusURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../third-party/widget-sandbox/corpus/common/heavy/04-long-article.html").standardized
        XCTAssertEqual(article.html, try String(contentsOf: corpusURL, encoding: .utf8))
        var measurements: [[Measurement]] = []
        for engine in [HTMLRenderEngine.webKit, .twidget] {
            let state = HTMLBubbleState(html: article.html + Self.probe, outgoing: false, engine: engine, selfContained: true)
            let appearance = HTMLBubbleAppearance(key: "article", css: "", dark: false, incoming: true)
            let bubble = state.twidgetBubble(appearance: appearance, width: 400)
            let host = try XCTUnwrap(bubble.ensureHost())
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let scroll = NSScrollView(frame: window.contentView!.bounds)
            scroll.autoresizingMask = [.width, .height]
            let document = DocumentView(frame: scroll.bounds)
            scroll.documentView = document
            document.addSubview(host.view)
            window.contentView?.addSubview(scroll)
            window.orderFront(nil)
            defer { host.destroy(); window.close() }
            var results: [Measurement] = []
            for (index, configuration) in [(400.0, false), (280.0, true), (320.0, false), (640.0, true), (400.0, false)].enumerated() {
                let width = CGFloat(configuration.0)
                let dark = configuration.1
                window.setContentSize(NSSize(width: width, height: 600))
                bubble.setWidth(width)
                bubble.setTheme(dark ? "dark" : "light")
                host.view.frame.size.width = width
                let deadline = Date().addingTimeInterval(15)
                while Date() < deadline {
                    let height = host.diagnostics.height
                    document.frame.size = NSSize(width: width, height: height)
                    host.view.frame = document.bounds
                    if let value = measurement(host), value.width == width, value.dark == dark,
                       value.card.height > 2000, abs(height - value.card.bottom) < 2, bubble.hostHasContent { break }
                    try await Task.sleep(nanoseconds: 20_000_000)
                }
                let value = try XCTUnwrap(measurement(host), "\(engine): \(host.diagnostics.logs)")
                XCTAssertEqual(value.width, width)
                XCTAssertEqual(value.dark, dark)
                XCTAssertGreaterThan(value.card.height, 2000)
                XCTAssertEqual(bubble.height, value.card.bottom, accuracy: 2)
                XCTAssertGreaterThanOrEqual(bubble.height, value.tags.bottom)
                XCTAssertLessThanOrEqual(value.card.width, width)
                XCTAssertEqual(value.listItems, 10)
                XCTAssertEqual(value.headings.count, 6)
                if engine == .webKit {
                    XCTAssertLessThanOrEqual(value.preScrollWidth, value.preClientWidth + 1)
                } else {
                    let document = LHDocument(html: article.html.replacingOccurrences(of: "<pre>", with: "<pre id='article-code'>"), css: nil)
                    document.layout(maxWidth: width, preferredWidth: width)
                    let codeBounds = try XCTUnwrap(document.bounds(byAttribute: "id")["article-code"]).rectValue
                    let text = document.textFragments(maxWidth: width).filter {
                        codeBounds.contains(NSPoint(x: $0.frame.minX, y: $0.frame.midY)) && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    }
                    XCTAssertFalse(text.isEmpty)
                    for fragment in text {
                        XCTAssertLessThanOrEqual(fragment.frame.maxX, codeBounds.maxX, "clipped code: \(fragment.text)")
                    }
                    XCTAssertEqual(text.map { $0.text }.joined().filter { !$0.isWhitespace }, "rendererfirstpainttextupdaterebuildwebview121msn/an/ablitz82ms??litehtml107ms??")
                }
                XCTAssertGreaterThan(value.pre.height, 88)
                XCTAssertEqual(value.rule.height, 1)
                XCTAssertNil(host.diagnostics.dead)
                XCTAssertNil(host.diagnostics.lastError)
                scroll.contentView.scroll(to: NSPoint(x: 0, y: document.bounds.height - scroll.contentSize.height))
                scroll.reflectScrolledClipView(scroll.contentView)
                let lastTags = NSRect(x: value.tags.x, y: value.tags.y, width: value.tags.width, height: value.tags.height)
                XCTAssertTrue(document.visibleRect.contains(lastTags), "final tags are unreachable: \(document.visibleRect), \(lastTags)")
                if let directory = ProcessInfo.processInfo.environment["ARTICLE_WIDGET_ARTIFACTS"] {
                    let image: NSImage? = await withCheckedContinuation { continuation in
                        host.snapshot { continuation.resume(returning: $0) }
                    }
                    let snapshot = try XCTUnwrap(image)
                    XCTAssertEqual(snapshot.size.height, bubble.height, accuracy: 1)
                    let bitmap = try XCTUnwrap(snapshot.cgImage(forProposedRect: nil, context: nil, hints: nil))
                    let png = try XCTUnwrap(NSBitmapImageRep(cgImage: bitmap).representation(using: .png, properties: [:]))
                    let url = URL(fileURLWithPath: directory).appendingPathComponent("\(index)-\(Int(width))-\(dark ? "dark" : "light")\(engine == .twidget ? ".lite" : "").png")
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try png.write(to: url)
                    try JSONEncoder().encode(value).write(to: url.deletingPathExtension().appendingPathExtension("json"))
                }
                results.append(value)
            }
            measurements.append(results)
        }
        let drift: (CGFloat) -> CGFloat = { max(4, $0 * 0.025) }
        for (web, native) in zip(measurements[0], measurements[1]) {
            XCTAssertEqual(native.card.height, web.card.height, accuracy: drift(web.card.height))
            XCTAssertEqual(native.tags.bottom, web.tags.bottom, accuracy: drift(web.tags.bottom))
            XCTAssertEqual(native.pre.height, web.pre.height, accuracy: max(2, web.pre.height * 0.025))
            for (webHeading, nativeHeading) in zip(web.headings, native.headings) {
                XCTAssertEqual(nativeHeading.y, webHeading.y, accuracy: drift(webHeading.y))
                XCTAssertEqual(nativeHeading.height, webHeading.height, accuracy: 2)
            }
        }
    }

    @MainActor
    func testBackgroundPreparedArticleKeepsItsFullHeight() async throws {
        let article = try XCTUnwrap(HTMLDemoCatalog.widgetFiles(.allWidgets).first { $0.name.hasSuffix("04-long-article.html") })
        let state = HTMLBubbleState(html: article.html, outgoing: false, engine: .twidget, selfContained: true)
        let appearance = HTMLBubbleAppearance(key: "prepared-article", css: "", dark: false, incoming: true)
        let oldWindow = TwidgetPrepareBudget.window
        let oldBudget = TwidgetPrepareBudget.perWindow
        TwidgetPrepareBudget.window = 0
        TwidgetPrepareBudget.perWindow = 5
        defer {
            TwidgetPrepareBudget.window = oldWindow
            TwidgetPrepareBudget.perWindow = oldBudget
        }
        _ = state.startTwidgetPrepare(appearance: appearance, width: 400)
        WidgetShellPool.shared.prewarm(width: 400)
        let shellDeadline = Date().addingTimeInterval(5)
        while Date() < shellDeadline, !WidgetShellPool.shared.available(width: 400) {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(WidgetShellPool.shared.available(width: 400))
        let prepared: Bool = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: state.prepareTwidget(appearance: appearance, width: 400, wait: 5))
            }
        }
        XCTAssertTrue(prepared)
        XCTAssertGreaterThan(state.twidgetSize(width: 400).height, 2300)
        let bubble = state.twidgetBubble(appearance: appearance, width: 400)
        let host = try XCTUnwrap(bubble.ensureHost())
        defer { host.destroy() }
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !bubble.hostHasContent {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(bubble.hostHasContent)
        XCTAssertGreaterThan(bubble.height, 2300)
        XCTAssertEqual(bubble.height, state.twidgetSize(width: 400).height)
    }
}
