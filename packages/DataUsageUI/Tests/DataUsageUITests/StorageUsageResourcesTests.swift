import AppKit
import XCTest
import TGUIKit
@testable import DataUsageUI

final class StorageUsageResourcesTests: XCTestCase {
    func testParticleArtworkKeepsItsOriginalVerticalOrientation() throws {
        System.updateScaleFactor(2)
        for (category, name) in [(StorageUsageCategory.avatars, "StorageParticleAvatars"), (.stickers, "StorageParticleStickers")] {
            let source = try XCTUnwrap(Bundle.module.image(forResource: NSImage.Name(name)))
            let particle = StorageUsageResources.particle(for: category)
            let upright = source.precomposed()
            let upsideDown = source.precomposed(flipVertical: true)
            XCTAssertEqual(particle.width, upright.width)
            XCTAssertEqual(particle.height, upright.height)
            let pixels = try XCTUnwrap(particle.dataProvider?.data) as Data
            XCTAssertEqual(pixels, try XCTUnwrap(upright.dataProvider?.data) as Data)
            XCTAssertNotEqual(pixels, try XCTUnwrap(upsideDown.dataProvider?.data) as Data)
        }
    }
}
