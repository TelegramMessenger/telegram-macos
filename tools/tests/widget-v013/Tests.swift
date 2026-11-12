import Cocoa
import QuartzCore
import zlib

__RESIZE_ANCHOR__

__ANCHOR__

struct WidgetPrepared {
    struct Host {
        struct Diagnostics {
            let resizeAnchor: WidgetResizeAnchor
        }
        let diagnostics: Diagnostics
    }
    let height: CGFloat
    let host: Host
}

final class LayoutState {
    enum Engine {
        case twidget, webKit
    }
    let lock = NSLock()
    var engine = Engine.twidget
    var isWidgetMessage = true
    var heightHint: CGFloat = 0
    var fixedHeight: CGFloat?
    var twidgetLayout = TwidgetLayout(height: 0, resizeAnchor: .top)
    var twidgetLayouts: [String: TwidgetLayout] = [:]
    var twidgetLiveKey: String?
    var notifications = 0

    func notify() {
        notifications += 1
    }

    __LAYOUT__
}

let fixtures = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String: Any]
func bytes(_ name: String) -> Data {
    return Data((fixtures[name] as! [NSNumber]).map { $0.uint8Value })
}
let html = fixtures["html"] as! String
if let index = CommandLine.arguments.firstIndex(of: "--check-mode") {
    let previous = CommandLine.arguments[index + 1] == "old"
    precondition(HTMLWidgetTestMode.usesPreviousBehavior == previous)
    precondition(HTMLWidgetPayload.decode(bytes("gzip")) == html)
    precondition(HTMLWidgetPayload.decode(bytes("zlib")) == (previous ? nil : html))
    let state = LayoutState()
    state.twidgetChanged(height: 200, resizeAnchor: .bottom)
    precondition(state.twidgetMessageResizeAnchor(width: 300, oldHeight: 100, newHeight: 200) == (previous ? nil : .bottom(oldHeight: 100, newHeight: 200)))
    print("PASS: \(previous ? "OLD gzip-only and guessed resize" : "NEW decoding and explicit anchors")")
    exit(0)
}
for format in ["zlib", "gzip"] {
    let payload = bytes(format)
    precondition(HTMLWidgetPayload.decode(payload) == html, format)
    precondition(HTMLWidgetPayload.decode(payload.dropLast()) == nil, "truncated \(format)")
    precondition(HTMLWidgetPayload.decode(payload + Data([0])) == nil, "trailing \(format)")
    var corrupt = payload
    corrupt[corrupt.count - 1] ^= 0xff
    precondition(HTMLWidgetPayload.decode(corrupt) == nil, "checksum \(format)")
}
for payload in [Data(), Data("<p>uncompressed</p>".utf8), bytes("raw"), bytes("invalidUTF8"), bytes("oversized")] {
    precondition(HTMLWidgetPayload.decode(payload) == nil)
}
precondition(HTMLWidgetPayload.decode(bytes("limit"))?.utf8.count == HTMLWidgetPayload.maximumHTMLSize)
precondition(HTMLWidgetPayload.compressedSize(Array(html.utf8)) == bytes("zlib").count)
print("PASS: zlib and gzip, UTF-8, checksums, framing, output limits, level-9 size")

let state = LayoutState()
precondition(state.twidgetMessageResizeAnchor(width: 300, oldHeight: 50, newHeight: 120) == .top)
state.recordPrepared(WidgetPrepared(height: 120, host: .init(diagnostics: .init(resizeAnchor: .bottom))), key: "300|light")
precondition(state.twidgetSize(width: 300).height == 120)
precondition(state.twidgetMessageResizeAnchor(width: 300, oldHeight: 50, newHeight: 120) == .bottom(oldHeight: 50, newHeight: 120))
state.twidgetLiveKey = "300|light"
state.twidgetChanged(height: 240, resizeAnchor: .bottom)
state.twidgetLiveKey = nil
precondition(state.twidgetSize(width: 300).height == 240)
precondition(state.twidgetMessageResizeAnchor(width: 300, oldHeight: 120, newHeight: 240) == .bottom(oldHeight: 120, newHeight: 240))
state.twidgetLiveKey = "300|dark"
state.twidgetChanged(height: 180, resizeAnchor: .top)
precondition(state.twidgetSize(width: 300).height == 180)
precondition(state.twidgetMessageResizeAnchor(width: 300, oldHeight: 240, newHeight: 180) == .top)
state.twidgetChanged(height: 180, resizeAnchor: .bottom)
precondition(state.twidgetMessageResizeAnchor(width: 300, oldHeight: 180, newHeight: 220) == .bottom(oldHeight: 180, newHeight: 220))
state.twidgetLiveKey = "220|dark"
state.twidgetChanged(height: 900, resizeAnchor: .top)
precondition(state.twidgetSize(width: 220).height == HTMLWidgetPayload.maximumHeight)
precondition(state.twidgetSize(width: 300).height == 180 || state.twidgetSize(width: 300).height == 240)
state.fixedHeight = HTMLWidgetPayload.clampedHeight(120)
precondition(state.twidgetSize(width: 300).height == 120 && state.twidgetSize(width: 220).height == 120)
state.fixedHeight = nil
state.isWidgetMessage = false
precondition(state.twidgetMessageResizeAnchor(width: 300, oldHeight: 180, newHeight: 220) == nil)
print("PASS: prepared, live and cached heights retain their resize anchor across host and theme changes; a bot's fixed height wins over them")

for flipped in [true, false] {
    for edge in [WidgetResizeAnchor.top, .bottom] {
        for newHeight: CGFloat in [120, 320] {
            let oldRect = CGRect(x: 0, y: 600, width: 300, height: 200)
            let newRect = CGRect(x: 0, y: flipped ? 600 : 800 - newHeight, width: 300, height: newHeight)
            let anchor = edge == .top ? TableRowResizeAnchor.top : .bottom(oldHeight: 200, newHeight: newHeight)
            let offset = TableRowResizeAnchor.offset(anchor: anchor, oldRect: oldRect, newRect: newRect, offset: 400, viewport: 600, flipped: flipped, range: 0 ... 2000)
            let before = (flipped ? oldRect.minY + anchor.from : oldRect.maxY - anchor.from) - 400
            let after = (flipped ? newRect.minY + anchor.to : newRect.maxY - anchor.to) - offset
            precondition(before == after, "\(edge) \(flipped) \(newHeight)")
        }
    }
}
print("PASS: top and bottom stay fixed while growing and shrinking in normal and inverted lists")

final class LHDocument {
    let size: CGSize
    let boxes: [Int: CGRect]

    init(height: CGFloat, boxes: [Int: CGRect]) {
        size = CGSize(width: 300, height: height)
        self.boxes = boxes
    }

    func idBounds() -> [Int: CGRect] {
        return boxes
    }
}

final class AlignmentView {
    var shift: CGFloat = 0

    func noteAnchorShift(_ shift: CGFloat, height: CGFloat) {
        self.shift = shift
    }
}

final class LiteHTMLWidgetRenderer {
    static let resizePointerAge: CFTimeInterval = 1.5
    static let resizeBurstGap: CFTimeInterval = 0.15
    var lastClick: (time: CFTimeInterval, point: CGPoint) = (0, .zero)
    let resizeDiffLock = NSLock()
    var resizeDiffAt: CFTimeInterval = 0
    var resizeDiff: WidgetResizeDiff?
    var resizePrefersBottom = false
    var resizeAnchorOverride: WidgetResizeAnchor?
    var resizeClickY: CGFloat = 0
    var resizePressId = 10
    var nextBounds: (LHDocument, [Int: CGRect])?
    let documentView = AlignmentView()

    __RENDERER_RESIZE__
}

let card = LHDocument(height: 100, boxes: [10: CGRect(x: 0, y: 0, width: 100, height: 100)])
let grown = LHDocument(height: 200, boxes: [10: CGRect(x: 0, y: 0, width: 100, height: 100), 11: CGRect(x: 0, y: 100, width: 100, height: 100)])
for edge in [WidgetResizeAnchor.top, .bottom] {
    for (from, to) in [(card, grown), (grown, card)] {
        let renderer = LiteHTMLWidgetRenderer()
        renderer.resizePrefersBottom = edge == .bottom
        renderer.noteResize(from: from, oldBounds: { from.idBounds() }, to: to)
        precondition(renderer.resizeDiff?.keepsBottom == (edge == .bottom), "\(edge) \(from.size.height)")
        precondition(renderer.documentView.shift == (edge == .bottom ? to.size.height - from.size.height : 0), "\(edge) \(from.size.height)")
    }
}
print("PASS: without a recent press the renderer keeps the old pixels on the widget's anchored edge")

for edge in [WidgetResizeAnchor.top, .bottom] {
    for delta: CGFloat in [1, 100] {
        let buttonBefore = LHDocument(height: 100, boxes: [10: CGRect(x: 0, y: 60, width: 100, height: 40)])
        let buttonAfter = LHDocument(height: 100 + delta, boxes: [10: CGRect(x: 0, y: edge == .top ? 60 + delta : 60, width: 100, height: 40)])
        for (from, to) in [(buttonBefore, buttonAfter), (buttonAfter, buttonBefore)] {
            let renderer = LiteHTMLWidgetRenderer()
            renderer.resizeAnchorOverride = edge
            renderer.resizePrefersBottom = edge != .bottom
            renderer.resizeClickY = from.boxes[10]!.midY
            renderer.lastClick = (CACurrentMediaTime(), CGPoint(x: 10, y: renderer.resizeClickY))
            renderer.resizeDiffAt = CACurrentMediaTime()
            renderer.resizeDiff = WidgetResizeDiff(oldHeight: from.size.height, newHeight: to.size.height, unchangedTop: 0, unchangedBottom: 0, keepsBottom: edge != .bottom)
            renderer.noteResize(from: from, oldBounds: { from.idBounds() }, to: to)
            precondition(renderer.resizeDiff?.keepsBottom == (edge == .bottom))
            precondition(renderer.documentView.shift == (edge == .bottom ? to.size.height - from.size.height : 0))
        }
    }
}
print("PASS: explicit widget anchors override a moving clicked button and the previous resize direction")

struct TelegramMediaWidget {
    let width: Int32
    let height: Int32
    let payload: Data
}

enum FixtureLoader {
    __FIXTURE_LOADER__
}

let fixtureDirectory = URL(fileURLWithPath: CommandLine.arguments[1]).deletingLastPathComponent().appendingPathComponent("manual-fixtures")
try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)
try bytes("zlib").write(to: fixtureDirectory.appendingPathComponent("01.zlib"))
try bytes("gzip").write(to: fixtureDirectory.appendingPathComponent("02.gzip"))
try Data(html.utf8).write(to: fixtureDirectory.appendingPathComponent("03.html"))
try Data("ignore".utf8).write(to: fixtureDirectory.appendingPathComponent("04.txt"))
try bytes("gzip").write(to: fixtureDirectory.appendingPathComponent("05.tgw"))
let widgets = FixtureLoader.syntheticWidgets(directory: fixtureDirectory.path, width: 0, height: 0)
precondition(widgets.count == 4)
precondition(widgets[0].payload == bytes("zlib"))
precondition(widgets[1].payload == bytes("gzip"))
precondition(widgets[2].payload == bytes("zlib"))
precondition(widgets[3].payload == bytes("gzip"))
for widget in widgets {
    precondition(widget.width == 0 && widget.height == 0)
    precondition(HTMLWidgetPayload.decode(widget.payload) == html)
}
print("PASS: manual chat feeds untouched zlib, gzip and .tgw bytes and level-9 zlib of HTML through the actual payload decoder")
