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

    private func makeSegment(capsule: Bool) -> ScrollableSegmentView {
        let segment = ScrollableSegmentView(frame: NSMakeRect(10, 10, 300, 40))
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 320, 60), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = View(frame: NSMakeRect(0, 0, 320, 60))
        window.contentView?.addSubview(segment)
        windows.append(window)
        segment.capsule = capsule
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
        for capsule in [false, true] {
            let segment = makeSegment(capsule: capsule)
            var titles: [Control] = []
            segment.updateItems(items(selected: 0, titles: &titles), animated: false)
            segment.layoutSubtreeIfNeeded()
            let title = titles[1]
            let control = try XCTUnwrap(title.superview)
            for point in [NSMakePoint(37, 20), NSMakePoint(37, 37), NSMakePoint(5, 20)] {
                let hit = segment.hitTest(control.convert(point, to: segment.superview))
                XCTAssertTrue(hit === control, "capsule: \(capsule), point: \(point), hit: \(String(describing: hit))")
            }
            control.isHidden = true
            XCTAssertFalse(segment.hitTest(control.convert(NSMakePoint(37, 20), to: segment.superview)) === control)
        }
    }

    func testReplacementTitlesAreLaidOutBeforeTheCapsuleRendersThem() throws {
        guard #available(macOS 26.0, *), LiquidGlassLensView.make() != nil else {
            throw XCTSkip("Native glass requires macOS 26")
        }
        let segment = makeSegment(capsule: true)
        var titles: [Control] = []
        segment.updateItems(items(selected: 0, titles: &titles), animated: false)
        segment.layoutSubtreeIfNeeded()
        segment.updateItems(items(selected: 1, titles: &titles), animated: true)
        for title in titles {
            XCTAssertEqual(title.frame.origin, NSMakePoint(10, 12))
        }
    }

    func testReturningToWindowRestoresTheSelectedFolderPill() throws {
        guard #available(macOS 26.0, *), LiquidGlassLensView.make() != nil else {
            throw XCTSkip("Native glass requires macOS 26")
        }
        let segment = makeSegment(capsule: true)
        var titles: [Control] = []
        segment.updateItems(items(selected: 1, titles: &titles), animated: false)
        segment.layoutSubtreeIfNeeded()
        let host = try XCTUnwrap(segment.superview)
        let lens = try XCTUnwrap(titles[1].superview?.superview?.superview?.superview as? LiquidGlassLensView)
        let selectedFrame = try XCTUnwrap(lens.subviews.first?.layer?.sublayers?.first { $0.name == "lensRestingBackground" }).frame
        for _ in 0..<3 {
            segment.removeFromSuperview()
            XCTAssertNil(lens.subviews.first?.layer?.sublayers?.first { $0.name == "lensRestingBackground" })
            segment.needsLayout = false
            host.addSubview(segment)
            host.layoutSubtreeIfNeeded()
            let pill = try XCTUnwrap(lens.subviews.first?.layer?.sublayers?.first { $0.name == "lensRestingBackground" })
            XCTAssertEqual(pill.frame, selectedFrame)
            XCTAssertEqual(pill.opacity, 1)
        }
    }
}
