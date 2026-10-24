import XCTest
import AppKit
@testable import TGUIKit

final class TextButtonBarViewTreeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    private func makeBar(_ text: String = "Done") -> TextButtonBarView {
        let bar = TextButtonBarView(controller: ViewController(), text: text)
        bar.frame = NSMakeRect(0, 0, 120, 50)
        _ = bar.fit(to: 120)
        bar.layout()
        return bar
    }

    private func spinners(_ bar: TextButtonBarView) -> [ProgressIndicator] {
        return bar.button.subviews.compactMap { $0 as? ProgressIndicator }
    }

    func testIdleBarHasNoSpinner() {
        let bar = makeBar()
        XCTAssertTrue(spinners(bar).isEmpty)
        XCTAssertEqual(viewClassNames(bar.button.subviews), ["LiquidGlassView", "ImageView", "TextView"])
    }

    func testLoadingAddsTheSpinnerWhereItUsedToBe() {
        let bar = makeBar()
        bar.isLoading = true
        bar.layout()
        let spinner = spinners(bar)
        XCTAssertEqual(spinner.count, 1)
        XCTAssertEqual(viewClassNames(bar.button.subviews), ["LiquidGlassView", "ImageView", "TextView", "ProgressIndicator"])
        XCTAssertFalse(spinner[0].isHidden)
        XCTAssertEqual(spinner[0].frame.size, NSMakeSize(18, 18))
        XCTAssertEqual(spinner[0].frame, bar.button.focus(NSMakeSize(18, 18)))
        XCTAssertFalse(bar.button.userInteractionEnabled)

        let legacy = makeBar()
        let old = ProgressIndicator(frame: NSMakeRect(0, 0, 18, 18))
        old.isHidden = true
        legacy.button.addSubview(old)
        legacy.isLoading = true
        old.isHidden = false
        legacy.layout()
        old.center()
        XCTAssertEqual(legacy.button.frame, bar.button.frame)
        XCTAssertEqual(old.frame, spinner[0].frame)
    }

    func testSpinnerStaysBelowLaterButtonContent() {
        let bar = makeBar()
        bar.button.set(subtext: "sub", for: .Normal)
        bar.button.apply(state: .Normal)
        XCTAssertEqual(viewClassNames(bar.button.subviews), ["LiquidGlassView", "ImageView", "TextView", "TextView"])
        bar.isLoading = true
        let names = viewClassNames(bar.button.subviews)
        XCTAssertEqual(names, ["LiquidGlassView", "ImageView", "TextView", "ProgressIndicator", "TextView"])
    }

    func testFinishingLoadingRemovesTheSpinnerAndRestoresTheTitle() {
        let bar = makeBar()
        bar.isLoading = true
        bar.isLoading = true
        XCTAssertEqual(spinners(bar).count, 1)
        bar.isLoading = false
        XCTAssertTrue(spinners(bar).isEmpty)
        XCTAssertTrue(bar.button.userInteractionEnabled)
        bar.isLoading = true
        XCTAssertEqual(spinners(bar).count, 1)
    }

    func testDoneRemainsInsideNavigationBarAfterLoadingWithoutResize() {
        let controller = ViewController()
        let bar = TextButtonBarView(controller: controller, text: "Done")
        bar.isLoading = true
        let navigationBar = NavigationBarView(frame: NSMakeRect(0, 0, 420, 64))
        navigationBar.switchViews(left: BarView(controller: controller), center: BarView(controller: controller), right: bar, controller: controller, style: .push, animationStyle: .init(duration: 0, function: .linear), liveSwiping: false)
        XCTAssertTrue(bar.bounds.contains(bar.button.frame))

        navigationBar.layoutSubtreeIfNeeded()
        navigationBar.needsLayout = false

        bar.isLoading = false
        bar.isEnabled = true
        bar.set(text: "Done", for: .Normal)
        XCTAssertTrue(navigationBar.needsLayout)
        navigationBar.layoutSubtreeIfNeeded()

        XCTAssertEqual(navigationBar.frame.size, NSMakeSize(420, 64))
        XCTAssertEqual(bar.frame.maxX, navigationBar.bounds.maxX - 12)
        XCTAssertTrue(bar.bounds.contains(bar.button.frame))
        XCTAssertTrue(navigationBar.bounds.contains(bar.convert(bar.button.frame, to: navigationBar)))
        let center = bar.button.convert(NSMakePoint(bar.button.bounds.midX, bar.button.bounds.midY), to: navigationBar)
        let hit = navigationBar.hitTest(center)
        XCTAssertTrue(hit === bar.button || hit?.isDescendant(of: bar.button) == true)
        XCTAssertTrue(bar.button.userInteractionEnabled)
    }
}
