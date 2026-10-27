import AppKit
import XCTest
import TGUIKit
@testable import ChatListUI

private final class AvatarSelectionTestLayer: CALayer {
    var displayedLayer: AvatarSelectionTestLayer?

    override func presentation() -> Self? {
        return displayedLayer as? Self
    }
}

final class AvatarTabContainerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    override func tearDown() {
        System.updateScaleFactor(2)
        super.tearDown()
    }

    private func makeContainer() -> AvatarTabContainer {
        let container = AvatarTabContainer(frame: NSMakeRect(0, 0, 30, 30))
        container.setSelected(false, animated: false)
        return container
    }

    private func layers(_ container: AvatarTabContainer) throws -> [CALayer] {
        return try container.subviews.map { try XCTUnwrap($0.layer) }
    }

    private func assertCentered(_ layer: CALayer, in container: AvatarTabContainer, transform: CATransform3D? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let sample = CALayer()
        sample.bounds = layer.bounds
        sample.anchorPoint = layer.anchorPoint
        sample.position = layer.position
        sample.transform = transform ?? layer.transform
        XCTAssertEqual(sample.frame.midX, container.bounds.midX, accuracy: 0.0001, file: file, line: line)
        XCTAssertEqual(sample.frame.midY, container.bounds.midY, accuracy: 0.0001, file: file, line: line)
    }

    private func assertAnimationCentered(_ layer: CALayer, in container: AvatarTabContainer, file: StaticString = #filePath, line: UInt = #line) throws {
        let animation = try XCTUnwrap(layer.animation(forKey: "transform") as? CABasicAnimation, file: file, line: line)
        let start = try XCTUnwrap(animation.fromValue as? NSValue, file: file, line: line).caTransform3DValue
        let end = try XCTUnwrap(animation.toValue as? NSValue, file: file, line: line).caTransform3DValue
        assertCentered(layer, in: container, transform: start, file: file, line: line)
        assertCentered(layer, in: container, transform: end, file: file, line: line)
        XCTAssertTrue(animation.isRemovedOnCompletion, file: file, line: line)
        XCTAssertEqual(animation.duration / Double(animation.speed), 0.3, accuracy: 0.001, file: file, line: line)
    }

    private func installTestLayers(_ container: AvatarTabContainer) throws -> [AvatarSelectionTestLayer] {
        for view in container.subviews {
            let layer = AvatarSelectionTestLayer()
            layer.anchorPoint = try XCTUnwrap(view.layer).anchorPoint
            view.layer = layer
        }
        container.setSelected(false, animated: false)
        return try container.subviews.map { try XCTUnwrap($0.layer as? AvatarSelectionTestLayer) }
    }

    private func transform(scale: CGFloat) -> CATransform3D {
        var value = CATransform3DMakeTranslation(15, 15, 0)
        value = CATransform3DScale(value, scale, scale, 1)
        return CATransform3DTranslate(value, -15, -15, 0)
    }

    func testScaleAnimationUsesTheBoundsCenterAfterImmediateSelection() throws {
        let container = makeContainer()
        container.setSelected(true, animated: false)
        container.setSelected(false, animated: true)
        for layer in try layers(container) {
            try assertAnimationCentered(layer, in: container)
        }
    }

    func testSelectionTransformsRemainCorrectAfterAnimationsAreRemoved() throws {
        let container = makeContainer()
        let layers = try layers(container)
        let ring = try XCTUnwrap(layers.first)
        let avatar = try XCTUnwrap(layers.last)
        for selected in [true, false, true] {
            container.setSelected(selected, animated: true)
            for layer in layers {
                assertCentered(layer, in: container)
                layer.removeAllAnimations()
                assertCentered(layer, in: container)
            }
            XCTAssertEqual(avatar.frame.width, selected ? 24 : 30, accuracy: 0.0001)
            XCTAssertEqual(ring.frame.width, selected ? 30 : 15, accuracy: 0.0001)
            XCTAssertEqual(ring.opacity, selected ? 1 : 0)
        }
    }

    func testRepeatedAnimatedAndImmediateUpdatesKeepBothCentersStable() throws {
        for scale in [CGFloat(1), 2] {
            System.updateScaleFactor(scale)
            let container = makeContainer()
            let layers = try layers(container)
            for index in 0 ..< 24 {
                let selected = index % 2 == 0
                let animated = index % 3 != 0
                container.setSelected(selected, animated: animated)
                container.layout()
                for layer in layers {
                    assertCentered(layer, in: container)
                    if let animation = layer.animation(forKey: "transform") as? CABasicAnimation {
                        let end = try XCTUnwrap(animation.toValue as? NSValue).caTransform3DValue
                        assertCentered(layer, in: container, transform: end)
                    }
                    if !animated {
                        XCTAssertNil(layer.animation(forKey: "transform"))
                    }
                }
                XCTAssertEqual(layers.last!.frame.width, selected ? 24 : 30, accuracy: 0.0001)
            }
        }
    }

    func testInterruptedSelectionUsesThePresentedTransforms() throws {
        let container = makeContainer()
        let layers = try installTestLayers(container)
        container.setSelected(true, animated: true)
        for (index, layer) in layers.enumerated() {
            let displayed = AvatarSelectionTestLayer()
            displayed.transform = transform(scale: index == 0 ? 0.75 : 0.9)
            layer.displayedLayer = displayed
        }
        container.setSelected(false, animated: true)
        for layer in layers {
            let animation = try XCTUnwrap(layer.animation(forKey: "transform") as? CABasicAnimation)
            let start = try XCTUnwrap(animation.fromValue as? NSValue).caTransform3DValue
            XCTAssertTrue(CATransform3DEqualToTransform(start, layer.displayedLayer!.transform))
            try assertAnimationCentered(layer, in: container)
        }
    }

    func testRapidReversalBeforeRenderingKeepsTheOriginalStart() throws {
        let container = makeContainer()
        let layers = try installTestLayers(container)
        let initial = layers.map { $0.transform }
        container.setSelected(true, animated: true)
        container.setSelected(false, animated: true)
        for (index, layer) in layers.enumerated() {
            XCTAssertTrue(CATransform3DEqualToTransform(layer.transform, initial[index]))
            if let animation = layer.animation(forKey: "transform") as? CABasicAnimation {
                let start = try XCTUnwrap(animation.fromValue as? NSValue).caTransform3DValue
                XCTAssertTrue(CATransform3DEqualToTransform(start, initial[index]))
            }
        }
    }

    func testRedundantLayoutAndThemeRefreshPreserveSelectionAnimations() throws {
        let container = makeContainer()
        container.setSelected(true, animated: true)
        let layers = try layers(container)
        let animations = try layers.map { try XCTUnwrap($0.animation(forKey: "transform")) }
        for _ in 0 ..< 4 {
            container.layout()
            container.updateLocalizationAndTheme(theme: presentation)
            for (index, layer) in layers.enumerated() {
                XCTAssertTrue(try XCTUnwrap(layer.animation(forKey: "transform")).isEqual(animations[index]))
                assertCentered(layer, in: container)
            }
        }
    }

    func testResizeRebuildsCenteredGeometryForTheCurrentSelection() throws {
        let container = makeContainer()
        container.setSelected(true, animated: true)
        container.setFrameSize(NSMakeSize(40, 40))
        container.bounds = NSMakeRect(2, 3, 40, 40)
        container.layout()
        let layers = try layers(container)
        for view in container.subviews {
            XCTAssertEqual(view.frame, container.bounds)
        }
        for layer in layers {
            assertCentered(layer, in: container)
            XCTAssertNil(layer.animation(forKey: "transform"))
        }
        XCTAssertEqual(layers.first?.cornerRadius, 20)
        XCTAssertEqual(layers.last!.frame.width, 24, accuracy: 0.0001)
    }

    func testLensSourcesRevealOnlyTheOutlineAndPreserveAvatarColors() throws {
        let container = makeContainer()
        let item = TabAnimatedItem(.tab_settings, image: TestImages.named("Icon_SearchField").precomposed(), selectedImage: TestImages.named("Icon_SearchField").precomposed(), controller: ViewController())
        for selected in [false, true] {
            container.setSelected(selected, animated: true)
            let layers = try layers(container)
            let animations = layers.map { $0.animation(forKey: "transform") }
            let sources = item.lensContentSources(for: container, lensedTintColor: .systemPurple, unlensedTintColor: .white)
            XCTAssertEqual(sources.count, 2)
            XCTAssertTrue(sources[0].view === container.subviews[0])
            XCTAssertEqual(sources[0].lensedTintColor, .systemPurple)
            XCTAssertEqual(sources[0].unlensedTintColor, .clear)
            XCTAssertEqual(sources[0].lensedScale, 1)
            XCTAssertTrue(sources[1].view === container.subviews[1])
            XCTAssertNil(sources[1].lensedTintColor)
            XCTAssertNil(sources[1].unlensedTintColor)
            XCTAssertEqual(sources[1].lensedScale, 0.8, accuracy: 0.0001)
            XCTAssertEqual(layers[0].opacity, selected ? 1 : 0)
            for (index, layer) in layers.enumerated() {
                if let animation = animations[index] {
                    XCTAssertTrue(layer.animation(forKey: "transform")?.isEqual(animation) == true)
                } else {
                    XCTAssertNil(layer.animation(forKey: "transform"))
                }
                XCTAssertNil(layer.filters)
            }
        }
        container.setFrameSize(NSSize(width: 40, height: 40))
        let resized = container.lensContentSources(tintColor: .systemBlue)
        XCTAssertEqual(resized[1].lensedScale, 0.6, accuracy: 0.0001)
    }
}
