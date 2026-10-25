import AppKit
import XCTest
@testable import TGUIKit
import TelegramMedia
import TLottie
import LocalAnimations
import ColorPalette
import TelegramTheme
@testable import ChatListUI

private final class FloatingTabBarTestRow: TableRowItem {
    override var height: CGFloat {
        return 60
    }
}

private final class TabAnimationTestRenderer: TLottieBridge, R_LottieBridge {
}

private final class LensTestAnimatedItem: TabAnimatedItem {
    let icon: TabAnimatedIconView

    init(sticker: LocalAnimatedSticker, data: Data, image: CGImage) {
        icon = TabAnimatedIconView(sticker: sticker, animationData: data)
        super.init(sticker, image: image, selectedImage: image, controller: ViewController())
    }

    override func makeView() -> NSView {
        return icon
    }
}

private final class LensTestAvatarItem: TabAnimatedItem {
    let icon = AvatarTabContainer(frame: NSRect(x: 0, y: 0, width: 30, height: 30))

    override func makeView() -> NSView {
        return icon
    }

    override func setSelected(_ selected: Bool, for view: NSView, animated: Bool) {
        icon.setSelected(selected, animated: animated)
        super.setSelected(selected, for: view, animated: animated)
    }
}

final class FloatingTabBarIntegrationTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    func testPeerListsComposeBottomPaddingWithTheirHeaderInsets() {
        let view = PeerListContainerView(frame: NSMakeRect(0, 0, 380, 700))
        view.tableView.contentInsets.top = 30
        view.contentBottomInset = 64
        XCTAssertEqual(view.tableView.contentInsets.top, 30)
        XCTAssertEqual(view.tableView.contentInsets.bottom, 64)
        XCTAssertEqual(view.tableView.scrollerInsets.bottom, 64)
        view.contentBottomInset = 64
        XCTAssertEqual(view.tableView.contentInsets.bottom, 64)
        view.contentBottomInset = 0
        XCTAssertEqual(view.tableView.contentInsets.top, 30)
        XCTAssertEqual(view.tableView.contentInsets.bottom, 0)
        XCTAssertEqual(view.tableView.scrollerInsets.bottom, 0)
    }

    func testBottomControlsUseTheAreaAboveTheFloatingBar() {
        let view = PeerListContainerView(frame: NSMakeRect(0, 0, 380, 700))
        var bottomY: CGFloat?
        view.layoutBottomOverlay = { y, _ in
            bottomY = y
            return nil
        }
        view.contentBottomInset = 64
        XCTAssertEqual(bottomY, 636)
        view.contentBottomInset = 0
        XCTAssertEqual(bottomY, 700)
    }

    func testAnimatedTabReplacementKeepsItsBadgeControllerAndTitle() throws {
        let controller = ViewController()
        let badge = Node(View(frame: NSMakeRect(0, 0, 18, 18)))
        let first = TestImages.named("Icon_SearchField").precomposed()
        let second = TestImages.named("Icon_SearchClear").precomposed()
        let item = TabAnimatedItem(.tab_chats, image: first, selectedImage: first, controller: controller, subNode: badge)
        item.accessibilityTitle = "Chats"
        let replacement = try XCTUnwrap(item.withUpdatedImages(second, second) as? TabAnimatedItem)
        XCTAssertEqual(replacement.sticker, .tab_chats)
        XCTAssertTrue(replacement.controller === controller)
        XCTAssertTrue(replacement.subNode === badge)
        XCTAssertEqual(replacement.accessibilityTitle, "Chats")
    }

    private func waitUntil(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.004))
        }
        return condition()
    }

    func testSelectedTabPreviewStartsPlayingWithoutChangingColors() throws {
        let resource = TestImages.catalog.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/tgs/tab_chats.tgs")
        let data = try Data(contentsOf: resource)
        let previousRenderer = makeRLottie
        makeRLottie = { json, _ in TabAnimationTestRenderer(json: json) }
        let icon = TabAnimatedIconView(sticker: .tab_chats, animationData: data)
        let player: LottiePlayerView = icon
        defer {
            player.set(nil)
            makeRLottie = previousRenderer
        }
        icon.setSelected(true, animated: false)
        XCTAssertTrue(waitUntil { player.currentState == .finished })
        let finalFrame = try XCTUnwrap(player.currentFrame)
        XCTAssertGreaterThan(finalFrame, 0)
        let colors = try XCTUnwrap(player.animation).colors
        icon.setSelected(true, animated: true)
        XCTAssertEqual(player.animation?.colors, colors)
        guard waitUntil({ player.currentFrame.map { $0 < finalFrame } ?? false }) else {
            XCTFail("The selected icon must restart playback after its static preview")
            return
        }
        let firstFrame = try XCTUnwrap(player.currentFrame)
        XCTAssertTrue(waitUntil { player.currentFrame.map { $0 > firstFrame } ?? false })
    }

    func testLottieKeepsPlayingThroughBothTintedLensPortals() throws {
        guard System.liquidGlassAvailable else {
            throw XCTSkip("Native glass is unavailable")
        }
        let previousTheme = theme
        defer { telegramUpdateTheme(previousTheme, window: nil, animated: false) }
        for palette in [dayClassicPalette, darkPalette] {
            let currentTheme = generateTheme(palette: palette, cloudTheme: nil, bubbled: false, fontSize: 13, wallpaper: previousTheme.wallpaper, liquidGlass: true)
            telegramUpdateTheme(currentTheme, window: nil, animated: false)
            try assertLottieKeepsPlayingThroughTintedPortals(outsideColor: palette.isDark ? .white : palette.grayIcon, accentColor: palette.accentIcon)
        }
    }

    private func assertLottieKeepsPlayingThroughTintedPortals(outsideColor: NSColor, accentColor: NSColor) throws {
        let resource = TestImages.catalog.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources/tgs/tab_chats.tgs")
        let data = try Data(contentsOf: resource)
        let previousRenderer = makeRLottie
        makeRLottie = { json, _ in TabAnimationTestRenderer(json: json) }
        System.liquidGlass = true
        let bar = TabBarView(frame: NSRect(x: 0, y: 0, width: 333, height: 48))
        bar.reduceMotion = { false }
        bar.reduceTransparency = { false }
        let window = NSWindow(contentRect: bar.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = bar
        defer { window.close() }
        let image = TestImages.named("Icon_SearchField").precomposed()
        let items = [LocalAnimatedSticker.tab_contacts, .tab_chats, .tab_settings].map {
            LensTestAnimatedItem(sticker: $0, data: data, image: image)
        }
        defer {
            bar.cancelSelection(animated: false)
            for item in items {
                item.icon.set(nil)
            }
            System.liquidGlass = false
            makeRLottie = previousRenderer
        }
        for item in items {
            bar.addTab(item)
        }
        bar.setSelectedIndex(0, respondToDelegate: false, animated: false)
        let player = items[1].icon
        XCTAssertTrue(waitUntil { player.currentState == .finished })
        let finalFrame = try XCTUnwrap(player.currentFrame)
        let frame = bar.control(for: 1).frame
        let point = NSPoint(x: frame.midX, y: frame.midY)
        bar.beginSelection(at: point)
        bar.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let root = try XCTUnwrap(bar.nativeLens?.layer)
        let source = try XCTUnwrap(player.layer)
        func portals(_ layer: CALayer) -> [CALayer] {
            var result: [CALayer] = []
            if layer.responds(to: NSSelectorFromString("sourceLayer")), layer.value(forKey: "sourceLayer") as? CALayer === source {
                result.append(layer)
            }
            for child in layer.sublayers ?? [] {
                result += portals(child)
            }
            return result
        }
        let copies = portals(root)
        XCTAssertEqual(copies.count, 2)
        XCTAssertTrue(copies.allSatisfy { $0.filters?.count == 1 })
        for copy in copies {
            let color = try XCTUnwrap((copy.superlayer?.name == "lensUnlensedContent" ? outsideColor : accentColor).usingColorSpace(.sRGB))
            let filter = try XCTUnwrap(copy.filters?.first as? NSObject)
            let value = try XCTUnwrap(filter.value(forKey: "inputColorMatrix") as? NSValue)
            var matrix = [Float](repeating: 0, count: 20)
            matrix.withUnsafeMutableBytes { value.getValue($0.baseAddress!, size: $0.count) }
            for (index, component) in [(3, color.redComponent), (8, color.greenComponent), (13, color.blueComponent), (18, color.alphaComponent)] {
                XCTAssertEqual(CGFloat(matrix[index]), component, accuracy: 0.0001)
            }
        }
        XCTAssertTrue(waitUntil { player.currentFrame.map { $0 < finalFrame } ?? false })
        let firstFrame = try XCTUnwrap(player.currentFrame)
        let animation = player.animation
        bar.updateSelection(at: NSPoint(x: point.x + 10, y: point.y))
        bar.layout()
        XCTAssertTrue(waitUntil { player.currentFrame.map { $0 > firstFrame } ?? false })
        XCTAssertTrue(player.animation === animation)
        XCTAssertTrue(portals(root).elementsEqual(copies, by: { $0 === $1 }))
        XCTAssertNil(player.layer?.filters)
    }

    func testLensTintSupportsAnimatedIconsAndPreservesAvatars() {
        let image = TestImages.named("Icon_SearchField").precomposed()
        let item = TabAnimatedItem(.tab_settings, image: image, selectedImage: image, controller: ViewController())
        XCTAssertTrue(item.supportsLensTint(for: TabAnimatedIconView(sticker: .tab_settings)))
        XCTAssertFalse(item.supportsLensTint(for: AvatarTabContainer(frame: NSRect(x: 0, y: 0, width: 30, height: 30))))
    }

    func testAvatarOutlineIsRevealedSpatiallyAcrossTheSelectionMidpoint() throws {
        guard System.liquidGlassAvailable else {
            throw XCTSkip("Native glass is unavailable")
        }
        System.liquidGlass = true
        defer { System.liquidGlass = false }
        let bar = TabBarView(frame: NSRect(x: 0, y: 0, width: 333, height: 48))
        bar.reduceMotion = { false }
        bar.reduceTransparency = { false }
        let window = NSWindow(contentRect: bar.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = bar
        defer { window.close() }
        let image = TestImages.named("Icon_SearchField").precomposed()
        for _ in 0 ..< 2 {
            bar.addTab(TabItem(image: image, selectedImage: image, controller: ViewController()))
        }
        let badge = View(frame: NSRect(x: 18, y: 2, width: 12, height: 12))
        badge.backgroundColor = .systemRed
        let item = LensTestAvatarItem(.tab_settings, image: image, selectedImage: image, controller: ViewController(), subNode: Node(badge))
        bar.addTab(item)
        let ring = try XCTUnwrap(item.icon.subviews.first?.layer)
        let avatar = try XCTUnwrap(item.icon.subviews.last?.layer)
        let badgeLayer = try XCTUnwrap(badge.layer)
        func center(_ index: Int) -> NSPoint {
            let frame = bar.control(for: index).frame
            return NSPoint(x: frame.midX, y: frame.midY)
        }
        func portals(_ layer: CALayer, source: CALayer) -> [CALayer] {
            var result: [CALayer] = []
            if layer.responds(to: NSSelectorFromString("sourceLayer")), layer.value(forKey: "sourceLayer") as? CALayer === source {
                result.append(layer)
            }
            return result + (layer.sublayers ?? []).flatMap { portals($0, source: source) }
        }
        for origin in [1, 2] {
            bar.setSelectedIndex(origin, respondToDelegate: false, animated: false)
            bar.beginSelection(at: center(origin))
            bar.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            let root = try XCTUnwrap(bar.nativeLens?.layer)
            let copies = portals(root, source: ring)
            let inside = try XCTUnwrap(copies.first { $0.superlayer?.name != "lensUnlensedContent" })
            let outside = try XCTUnwrap(copies.first { $0.superlayer?.name == "lensUnlensedContent" })
            let mask = try XCTUnwrap(inside.superlayer?.mask as? CAShapeLayer)
            let positions: [CGFloat] = origin == 1 ? [1.4, 1.49, 1.51, 1.6] : [1.6, 1.51, 1.49, 1.4]
            for position in positions {
                let first = center(1)
                let point = NSPoint(x: first.x + (center(2).x - first.x) * (position - 1), y: first.y)
                bar.updateSelection(at: point)
                bar.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                XCTAssertTrue(portals(root, source: ring).elementsEqual(copies, by: { $0 === $1 }))
                XCTAssertEqual(ring.opacity, position < 1.5 ? 0 : 1)
                XCTAssertEqual(inside.opacity, 1)
                XCTAssertEqual(inside.transform.m11, 1.1, accuracy: 0.0001)
                let filter = try XCTUnwrap(outside.filters?.first as? NSObject)
                let value = try XCTUnwrap(filter.value(forKey: "inputColorMatrix") as? NSValue)
                var matrix = [Float](repeating: 1, count: 20)
                matrix.withUnsafeMutableBytes { value.getValue($0.baseAddress!, size: $0.count) }
                XCTAssertTrue(matrix.allSatisfy { $0 == 0 })
                let left = inside.convert(CGPoint(x: 1, y: 15), to: inside.superlayer)
                let right = inside.convert(CGPoint(x: 29, y: 15), to: inside.superlayer)
                XCTAssertTrue(try XCTUnwrap(mask.path).contains(left))
                XCTAssertEqual(try XCTUnwrap(mask.path).contains(right), position == 1.6)
                let avatarCopies = portals(root, source: avatar)
                XCTAssertEqual(avatarCopies.count, 2)
                XCTAssertTrue(avatarCopies.allSatisfy { $0.filters?.isEmpty ?? true })
                XCTAssertEqual(avatarCopies.first { $0.superlayer?.name != "lensUnlensedContent" }?.transform.m11 ?? 0, 0.88, accuracy: 0.0001)
                XCTAssertTrue(portals(root, source: badgeLayer).allSatisfy { $0.filters?.isEmpty ?? true })
            }
            bar.cancelSelection(animated: false)
            XCTAssertEqual(ring.opacity, origin == 2 ? 1 : 0)
            XCTAssertTrue(copies.allSatisfy { $0.value(forKey: "sourceLayer") == nil })
        }
        bar.setSelectedIndex(1, respondToDelegate: false, animated: false)
        bar.beginSelection(at: center(1))
        bar.updateSelection(at: center(2))
        bar.endSelection(at: center(2))
        XCTAssertEqual(bar.selectedIndex, 2)
        XCTAssertEqual(ring.opacity, 1)
        XCTAssertEqual(avatar.frame.width, 24, accuracy: 0.0001)
    }

    func testLastRowCanScrollAboveTheFloatingBar() {
        let window = NSWindow(contentRect: NSMakeRect(0, 0, 380, 700), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = PeerListContainerView(frame: window.contentView!.bounds)
        window.contentView!.addSubview(view)
        view.tableView.frame = view.bounds
        view.contentBottomInset = 64
        for index in 0 ..< 20 {
            _ = view.tableView.addItem(item: FloatingTabBarTestRow(view.bounds.size, stableId: index))
        }
        view.layoutSubtreeIfNeeded()
        view.tableView.scroll(to: .bottom(id: 19, innerId: nil, animated: false, focus: .init(focus: false), inset: 0))
        view.layoutSubtreeIfNeeded()
        let row = view.tableView.rectOf(item: view.tableView.item(at: 19))
        let visibleRow = view.convert(row, from: view.tableView.view)
        XCTAssertLessThanOrEqual(visibleRow.maxY, view.bounds.height - 64)
    }
}
