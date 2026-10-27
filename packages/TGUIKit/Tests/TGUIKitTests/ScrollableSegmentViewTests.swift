import AppKit
import ColorPalette
import XCTest
@testable import TGUIKit

final class ScrollableSegmentViewTests: XCTestCase {
    private var windows: [NSWindow] = []

    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    override func tearDown() {
        windows.forEach { $0.close() }
        windows.removeAll()
        super.tearDown()
    }

    private func makeSegment(bubbles: Bool) -> ScrollableSegmentView {
        let segment = ScrollableSegmentView(frame: NSMakeRect(10, 10, 300, 40))
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 320, 60), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = View(frame: NSMakeRect(0, 0, 320, 60))
        window.contentView?.addSubview(segment)
        windows.append(window)
        segment.bubbles = bubbles
        return segment
    }

    private func items(selected: Int, titles: inout [Control]) -> [ScrollableSegmentItem] {
        let theme = ScrollableSegmentTheme.standard(PresentationTheme.current.colors)
        let views = (0..<2).map { _ -> Control in
            let title = Control(frame: NSMakeRect(0, 0, 54, 16))
            title.userInteractionEnabled = false
            let text = TextView(frame: title.bounds)
            text.userInteractionEnabled = false
            text.isSelectable = false
            title.addSubview(text)
            return title
        }
        titles = views
        return views.enumerated().map { index, title in
            ScrollableSegmentItem(title: "Folder \(index)", index: index, uniqueId: Int64(index), selected: index == selected, insets: NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10), icon: nil, theme: theme, equatable: nil, customTextView: { title })
        }
    }

    func testTitleAndPaddingHitTheSameFolderControl() throws {
        for bubbles in [false, true] {
            let segment = makeSegment(bubbles: bubbles)
            var titles: [Control] = []
            segment.updateItems(items(selected: 0, titles: &titles), animated: false)
            segment.layoutSubtreeIfNeeded()
            let title = titles[1]
            let control = try XCTUnwrap(title.superview)
            for point in [NSMakePoint(37, 20), NSMakePoint(37, 37), NSMakePoint(5, 20)] {
                let hit = segment.hitTest(control.convert(point, to: segment.superview))
                XCTAssertTrue(hit === control, "bubbles: \(bubbles), point: \(point), hit: \(String(describing: hit))")
            }
            control.isHidden = true
            XCTAssertFalse(segment.hitTest(control.convert(NSMakePoint(37, 20), to: segment.superview)) === control)
        }
    }

    func testReplacementTitlesAreLaidOutBeforeThePillsAnimate() throws {
        let segment = makeSegment(bubbles: true)
        var titles: [Control] = []
        segment.updateItems(items(selected: 0, titles: &titles), animated: false)
        segment.layoutSubtreeIfNeeded()
        segment.updateItems(items(selected: 1, titles: &titles), animated: true)
        for title in titles {
            XCTAssertEqual(title.frame.origin, NSMakePoint(10, 12))
        }
    }

    func testFolderPillsDoNotCreateALensWhenSelectionChanges() throws {
        let segment = makeSegment(bubbles: true)
        var titles: [Control] = []
        for selection in [0, 1, 0] {
            segment.updateItems(items(selected: selection, titles: &titles), animated: true)
            segment.layoutSubtreeIfNeeded()
            var views: [NSView] = [segment]
            while let view = views.popLast() {
                XCTAssertFalse(view is LiquidGlassLensView)
                views.append(contentsOf: view.subviews)
            }
            for title in titles {
                XCTAssertEqual(title.frame.origin, NSMakePoint(10, 12))
            }
            XCTAssertNil(segment.scrollView.layer?.mask)
            XCTAssertEqual(segment.scrollView.frame, segment.bounds)
        }
    }
}
