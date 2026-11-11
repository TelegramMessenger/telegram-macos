import XCTest
import AppKit
@testable import TGUIKit

private final class CountingTarget: NSObject {
    var calls = 0
    @objc func update() {
        calls += 1
    }
}

final class AnimatableContentObserverTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    func testViewOutsideAScrollViewIgnoresOtherViewsGeometry() {
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 300, 300), styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        let root = NSView(frame: NSMakeRect(0, 0, 300, 300))
        window.contentView = root
        let observed = NSView(frame: NSMakeRect(0, 0, 20, 20))
        root.addSubview(observed)
        let unrelated = NSView(frame: NSMakeRect(50, 50, 20, 20))
        unrelated.postsFrameChangedNotifications = true
        unrelated.postsBoundsChangedNotifications = true
        root.addSubview(unrelated)

        let target = CountingTarget()
        let observer = AnimatableContentObserver()
        observer.update(for: observed, target: target, selector: #selector(CountingTarget.update), options: [.contentBounds, .documentFrame, .ownFrame])

        for i in 0 ..< 100 {
            unrelated.frame = NSMakeRect(50, 50, 20 + CGFloat(i % 7), 20)
            unrelated.bounds = NSMakeRect(CGFloat(i % 3), 0, 20, 20)
        }
        XCTAssertEqual(target.calls, 0)

        window.setContentSize(NSMakeSize(320, 300))
        XCTAssertGreaterThan(target.calls, 0)

        let before = target.calls
        observed.frame = NSMakeRect(0, 0, 30, 30)
        XCTAssertGreaterThan(target.calls, before)

        observed.removeFromSuperview()
        observer.update(for: observed, target: target, selector: #selector(CountingTarget.update), options: [.contentBounds, .documentFrame, .ownFrame])
        let detached = target.calls
        window.setContentSize(NSMakeSize(360, 300))
        XCTAssertEqual(target.calls, detached)
    }

    func testViewInsideAScrollViewStillFollowsScrolling() {
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 300, 300), styleMask: [.titled], backing: .buffered, defer: true)
        let scroll = NSScrollView(frame: NSMakeRect(0, 0, 300, 300))
        let document = NSView(frame: NSMakeRect(0, 0, 300, 1000))
        scroll.documentView = document
        scroll.contentView.postsBoundsChangedNotifications = true
        window.contentView = scroll
        let observed = NSView(frame: NSMakeRect(0, 500, 20, 20))
        document.addSubview(observed)

        let target = CountingTarget()
        let observer = AnimatableContentObserver()
        observer.update(for: observed, target: target, selector: #selector(CountingTarget.update))
        scroll.contentView.scroll(to: NSMakePoint(0, 200))
        XCTAssertGreaterThan(target.calls, 0)
    }

    func testReattachedViewFollowsOnlyItsCurrentScrollView() {
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 300, 300), styleMask: [.titled], backing: .buffered, defer: true)
        let root = NSView(frame: NSMakeRect(0, 0, 300, 300))
        window.contentView = root
        func makeScroll() -> NSScrollView {
            let scroll = NSScrollView(frame: NSMakeRect(0, 0, 300, 300))
            scroll.documentView = NSView(frame: NSMakeRect(0, 0, 300, 1000))
            scroll.contentView.postsBoundsChangedNotifications = true
            root.addSubview(scroll)
            return scroll
        }
        let first = makeScroll()
        let second = makeScroll()
        let observed = NSView(frame: NSMakeRect(0, 500, 20, 20))

        let target = CountingTarget()
        let observer = AnimatableContentObserver()
        for _ in 0 ..< 3 {
            first.documentView?.addSubview(observed)
            observer.update(for: observed, target: target, selector: #selector(CountingTarget.update))
            observed.removeFromSuperview()
            observer.update(for: observed, target: target, selector: #selector(CountingTarget.update))
        }
        first.contentView.scroll(to: NSMakePoint(0, 100))
        XCTAssertEqual(target.calls, 0)

        first.documentView?.addSubview(observed)
        observer.update(for: observed, target: target, selector: #selector(CountingTarget.update))
        first.contentView.scroll(to: NSMakePoint(0, 200))
        XCTAssertEqual(target.calls, 1)

        observed.removeFromSuperview()
        second.documentView?.addSubview(observed)
        observer.update(for: observed, target: target, selector: #selector(CountingTarget.update))
        first.contentView.scroll(to: NSMakePoint(0, 300))
        XCTAssertEqual(target.calls, 1)
        second.contentView.scroll(to: NSMakePoint(0, 100))
        XCTAssertEqual(target.calls, 2)
    }
}
