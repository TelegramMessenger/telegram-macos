import AppKit
import XCTest
import TGUIKit
import WidgetSandbox
@testable import TwidgetRenderer
@testable import HTMLBubbles

final class WidgetResizePresentationTests: XCTestCase {
    private final class VisibleWindow: NSWindow {
        override var isVisible: Bool { true }
        override var occlusionState: NSWindow.OcclusionState { .visible }
    }

    private final class Space: WidgetFeedSpace {
        var slots: [WidgetFeedSlot] = []
        var onScreen = true
        var feedViewport: CGRect { CGRect(x: 0, y: 0, width: 420, height: 600) }
        var feedOnScreen: Bool { onScreen }
        func feedSlots(in rect: CGRect) -> [WidgetFeedSlot] { slots }
    }

    private func pump(until done: () -> Bool) {
        let end = Date().addingTimeInterval(5)
        while !done() && Date() < end {
            RunLoop.main.run(until: Date().addingTimeInterval(0.005))
        }
        XCTAssertTrue(done())
    }

    func testHotelWidgetRetainsRenderedContentAcrossAnimatedResizes() throws {
        _ = NSApplication.shared
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../third-party/widget-sandbox/corpus/resize/3-grows-down/03-show-more.html").standardized
        let html = try String(contentsOf: url, encoding: .utf8)
        let appearance = HTMLBubbleAppearance(key: "resize-test", css: "", dark: false, incoming: true)
        let state = HTMLBubbleState(html: html, outgoing: false, engine: .twidget, selfContained: true)
        state.isWidgetMessage = true
        state.showsStats = false
        let window = VisibleWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let space = Space()
        let slot = try XCTUnwrap(state.twidgetSlot(appearance: appearance, width: 420, locate: { CGRect(x: 0, y: 0, width: 420, height: 600) }))
        slot.space = space
        space.slots = [slot]
        WidgetFeed.shared.attach(space)
        defer { WidgetFeed.shared.detach(space) }
        let view = HTMLBubbleView(frame: CGRect(x: 0, y: 0, width: 420, height: 300))
        window.contentView?.addSubview(view)
        view.update(state: state, appearance: appearance, maxWidth: 420, rendering: nil)
        let bubble = state.twidgetBubble(appearance: appearance, width: 420)
        let host = try XCTUnwrap(bubble.ensureHost())
        var targetHeight: CGFloat = 300
        view.onContentChanged = { [weak view] size, _ in
            guard let view = view, abs(size.height - targetHeight) > 0.5 else { return }
            targetHeight = size.height
            view.update(state: state, appearance: appearance, maxWidth: 420, rendering: nil)
            ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeOut).updateFrame(view: view, frame: CGRect(origin: .zero, size: size))
        }
        WidgetFeed.shared.update()
        pump { host.diagnostics.loaded && host.diagnostics.rendered && targetHeight > 300 }
        let renderer = try XCTUnwrap(host.rendererObject as? LiteHTMLWidgetRenderer)
        for _ in 0..<9 {
            let previous = host.diagnostics.height
            let message = renderer.onMessage
            let event = "{\"type\":\"event\",\"trusted\":true,\"ev\":{\"type\":\"click\",\"targetId\":0,\"bubbles\":true}}"
            host.executor.async {
                let node = renderer.dom.nodes.values.first { $0.attribute("id") == "more" }!
                message?(event.replacingOccurrences(of: "\"targetId\":0", with: "\"targetId\":\(renderer.dom.publicId(node))"))
            }
            pump { abs(host.diagnostics.height - previous) > 0.5 }
            pump { abs(view.frame.height - host.diagnostics.height) < 0.5 }
            pump { abs(renderer.view.frame.height - view.frame.height) < 0.5 }
            XCTAssertTrue(renderer.view.isDescendant(of: view))
            XCTAssertFalse(renderer.view.isHiddenOrHasHiddenAncestor)
            XCTAssertEqual(renderer.view.frame.height, view.frame.height, accuracy: 0.5)
            XCTAssertGreaterThan(renderer.tileLayerCount, 0)
            XCTAssertNil(host.diagnostics.dead)
        }
    }

    func testRevenueTableKeepsItsActiveViewAfterReturningToChat() throws {
        _ = NSApplication.shared
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../../third-party/widget-sandbox/corpus/htmlbubbles-ported/03-stress-test/06-fuzz.html").standardized
        let state = HTMLBubbleState(html: try String(contentsOf: url), outgoing: false, engine: .twidget, selfContained: true)
        state.isWidgetMessage = true
        state.showsStats = false
        let appearance = HTMLBubbleAppearance(key: "table-lifecycle", css: "", dark: false, incoming: true)
        let window = VisibleWindow(contentRect: CGRect(x: 0, y: 0, width: 420, height: 900), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let space = Space()
        let slot = try XCTUnwrap(state.twidgetSlot(appearance: appearance, width: 420, locate: { CGRect(x: 0, y: 0, width: 420, height: 500) }))
        slot.space = space
        space.slots = [slot]
        WidgetFeed.shared.attach(space)
        defer { WidgetFeed.shared.detach(space) }
        func makeView() -> HTMLBubbleView {
            let view = HTMLBubbleView(frame: CGRect(x: 0, y: 0, width: 420, height: 300))
            var targetHeight: CGFloat = 300
            window.contentView?.addSubview(view)
            view.onContentChanged = { [weak view] size, _ in
                guard let view, abs(targetHeight - size.height) > 0.5 else { return }
                targetHeight = size.height
                view.update(state: state, appearance: appearance, maxWidth: 420, rendering: nil)
                ContainedViewLayoutTransition.animated(duration: 0.2, curve: .easeOut).updateFrame(view: view, frame: CGRect(origin: .zero, size: size))
            }
            view.update(state: state, appearance: appearance, maxWidth: 420, rendering: nil)
            return view
        }
        var active = makeView()
        var cached: [HTMLBubbleView] = []
        let bubble = state.twidgetBubble(appearance: appearance, width: 420)
        let host = try XCTUnwrap(bubble.ensureHost())
        WidgetFeed.shared.update()
        pump { host.diagnostics.loaded && host.diagnostics.rendered && host.diagnostics.height > 0 }
        let renderer = try XCTUnwrap(host.rendererObject as? LiteHTMLWidgetRenderer)
        for cycle in 0..<5 {
            if cycle > 0 {
                space.onScreen = false
                active.removeFromSuperview()
                cached.append(active)
                WidgetFeed.shared.update()
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                active = makeView()
                space.onScreen = true
                WidgetFeed.shared.update()
                pump { renderer.view.isDescendant(of: active) }
            }
            let previous = host.diagnostics.height
            host.executor.async {
                let node = renderer.dom.nodes.values.first { $0.attribute("data-action") == "expand" && $0.attribute("data-value") == "0" }!
                let id = renderer.dom.publicId(node)
                renderer.noteUserInput()
                renderer.onMessage?("{\"type\":\"event\",\"trusted\":true,\"ev\":{\"type\":\"click\",\"targetId\":\(id),\"bubbles\":true}}")
            }
            pump { abs(host.diagnostics.height - previous) > 0.5 }
            RunLoop.main.run(until: Date().addingTimeInterval(0.6))
            XCTAssertTrue(renderer.view.isDescendant(of: active), "cycle \(cycle): the live renderer moved into a cached chat view")
            XCTAssertTrue(state.twidgetHostChangedOwner === active)
            XCTAssertNil(host.diagnostics.dead)
            let context = try XCTUnwrap(CGContext(data: nil, width: 420, height: 900, bitsPerComponent: 8, bytesPerRow: 420 * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 420, height: 900))
            context.clip(to: active.bounds)
            try XCTUnwrap(active.layer).render(in: context)
            let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
            var headerPixels = 0
            for index in stride(from: 0, to: 420 * 900 * 4, by: 4) {
                if Int(pixels[index + 2]) > Int(pixels[index]) + 30 { headerPixels += 1 }
            }
            XCTAssertGreaterThan(headerPixels, 1500, "cycle \(cycle): the visible table became blank")
        }
        active.removeFromSuperview()
        let returning = cached.removeFirst()
        window.contentView?.addSubview(returning)
        returning.update(state: state, appearance: appearance, maxWidth: 420, rendering: nil)
        XCTAssertTrue(state.visibility === returning)
        XCTAssertTrue(state.twidgetHostChangedOwner === returning)
        XCTAssertTrue(renderer.view.isDescendant(of: returning))
        withExtendedLifetime(cached) {}
    }
}
