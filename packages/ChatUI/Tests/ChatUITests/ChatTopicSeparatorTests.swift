import AppKit
import XCTest
import TGUIKit
import ChatHistoryModel
import InAppSettings
import TelegramTheme
import TelegramUtils
import ThemeSettings
import ColorPalette
@testable import ChatUI

final class ChatTopicSeparatorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
        TelegramUtilsHooks.install(.init(animationsAreLite: { false }, isLite: { _ in false }, peerTitle: { _ in "" }, peerLetters: { _ in [] }, peerIsForum: { _ in false }, peerCompactTitle: { _ in "" }, repliesPeerId: { .init(0) }))
    }

    func testSourceChatHeaderDoesNotInsertAnExtraFortyPointGap() {
        for state in [MonoforumUIState.horizontal, .vertical, .sidebar] {
            let entries = messageEntries([], monoforumState: state)
            XCTAssertFalse(entries.contains { entry in
                if case .topThreadInset = entry { return true }
                return false
            }, "Unexpected history spacer for \(state)")
        }
    }

    func testExplicitThreadInsetIsPreservedWithoutAnExtraHeaderGap() {
        let entries = messageEntries([], addTopThreadInset: 24, monoforumState: .horizontal)
        let insets = entries.compactMap { entry -> CGFloat? in
            if case let .topThreadInset(height, _, _) = entry { return height }
            return nil
        }
        XCTAssertEqual(insets, [24])
    }

    private func makeSeparator(presentation: TelegramPresentationTheme = theme) -> TableStickView {
        let item = ChatTopicSeparatorItem(NSSize(width: 400, height: 28), entry: .topicSeparator(.absoluteLowerBound(), .topic(1, .init(title: "Separator Test", icon: nil, iconColor: 0, isClosed: false)), .bubble, .init(nil, .init(monoforumState: .horizontal))), theme: presentation)
        _ = item.makeSize(400, oldWidth: 0)
        let view = (item.viewClass() as! TableStickView.Type).init(frame: NSRect(x: 0, y: 0, width: 400, height: 28))
        view.set(item: item, animated: false)
        view.updateLayout(size: view.frame.size, transition: .immediate)
        return view
    }

    private func servicePill(in view: TableStickView) throws -> (container: NSView, service: NSView) {
        let containers = view.subviews.filter { candidate in
            candidate.subviews.contains { $0 is LiquidGlassView }
        }
        XCTAssertEqual(containers.count, 1)
        let container = try XCTUnwrap(containers.first)
        let services = container.subviews.filter { $0 is View && !($0 is LiquidGlassView) }
        XCTAssertEqual(services.count, 1)
        return (container, try XCTUnwrap(services.first))
    }

    func testHiddenInlinePillLeavesCompleteDashedSeparator() {
        let view = makeSeparator()
        view.updateIsVisible(false, animated: false)
        XCTAssertTrue(view.subviews[1].isHidden)
        XCTAssertTrue(view.subviews[2].isHidden)
        let line = view.subviews[0]
        let image = ViewSnapshot.render(line)
        let center = image.height / 2
        func alpha(in range: Range<Int>) -> Int {
            var result = 0
            for y in max(0, center - 2) ..< min(image.height, center + 3) {
                for x in range {
                    result += Int(image.bytes[(y * image.width + x) * 4 + 3])
                }
            }
            return result
        }
        XCTAssertGreaterThan(alpha(in: 0 ..< 60), 0)
        XCTAssertGreaterThan(alpha(in: image.width / 2 - 30 ..< image.width / 2 + 30), 0)
        XCTAssertGreaterThan(alpha(in: image.width - 60 ..< image.width), 0)
    }

    func testPillUsesStandardServiceColorAndRoundedBackground() throws {
        let view = makeSeparator()
        let layers = try servicePill(in: view)
        let background = layers.service
        XCTAssertEqual(background.layer?.backgroundColor, theme.chatServiceItemColor.cgColor)
        XCTAssertEqual(background.layer?.masksToBounds, true)
        XCTAssertGreaterThan(background.layer?.cornerRadius ?? 0, 0)
        view.header = true
        view.updateIsVisible(true, animated: false)
        XCTAssertEqual(layers.container.layer?.opacity, 1)
        XCTAssertEqual(view.subviews[0].layer?.opacity, 0)
    }

    func testWallpaperPillBlursUnderneathUsingUnmodifiedServiceTint() throws {
        let presentation = generateTheme(palette: dayClassicPalette, cloudTheme: nil, bubbled: true, fontSize: 13, wallpaper: .init(wallpaper: .gradient(nil, [0xff99bf80, 0xff99bf80], nil), associated: nil), liquidGlass: false)
        let view = makeSeparator(presentation: presentation)
        let layers = try servicePill(in: view)
        let background = layers.service
        let effect = background.subviews.first(where: { $0 is VisualEffect }) as? VisualEffect
        XCTAssertNotNil(effect)
        XCTAssertEqual(effect?.bgColor, presentation.chatServiceItemColor)
        XCTAssertEqual(effect?.blendingMode, .withinWindow)
        XCTAssertEqual(effect?.state, .active)
        XCTAssertEqual(background.layer?.masksToBounds, true)
        XCTAssertEqual(background.layer?.backgroundColor?.alpha, 0)
    }
}
