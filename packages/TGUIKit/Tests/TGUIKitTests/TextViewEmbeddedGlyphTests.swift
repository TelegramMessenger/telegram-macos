import AppKit
import XCTest
@testable import TGUIKit

final class TextViewEmbeddedGlyphTests: XCTestCase {
    override func setUp() {
        TGUIKitTestBootstrap.install()
    }

    func testEmbeddedEmojiTouchingOppositeDirectionUsesOnlyItsGlyph() throws {
        for text in ["abc😀مرحبا", "123😀مرحبا", "abc😀שלום", "مرحبا😀abc", "😀مرحبا", "مرحبا😀"] {
            let value = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.black])
            let range = (text as NSString).range(of: "😀")
            value.addAttribute(TextInputAttributes.embedded, value: "emoji", range: range)
            let layout = TextViewLayout(value)
            layout.measure(width: 300)
            let item = try XCTUnwrap(layout.embeddedItems.first, text)
            XCTAssertEqual(item.range, range, text)
            XCTAssertLessThan(item.rect.width, 34, text)
            XCTAssertGreaterThan(item.rect.width, 20, text)
        }
    }

    func testEmbeddedEmojiRetainsGeometryWhenTruncatedAfterIt() throws {
        let value = NSMutableAttributedString(string: "abc😀مرحبا followed by a long line", attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.black])
        let range = (value.string as NSString).range(of: "😀")
        value.addAttribute(TextInputAttributes.embedded, value: "emoji", range: range)
        let layout = TextViewLayout(value, maximumNumberOfLines: 1)
        layout.measure(width: 110)
        let item = try XCTUnwrap(layout.embeddedItems.first)
        XCTAssertEqual(item.range, range)
        XCTAssertLessThan(item.rect.width, 34)
        XCTAssertGreaterThan(item.rect.width, 20)
    }

    func testCaptureBidirectionalEmbeddedGlyph() throws {
        guard let directory = ProcessInfo.processInfo.environment["EMBEDDED_GLYPH_CAPTURE_DIRECTORY"] else {
            throw XCTSkip("Opt-in glyph geometry capture")
        }
        let value = NSMutableAttributedString(string: "abc😀مرحبا", attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.black])
        value.addAttribute(TextInputAttributes.embedded, value: "emoji", range: NSRange(location: 3, length: 2))
        let layout = TextViewLayout(value)
        layout.measure(width: 300)
        let item = try XCTUnwrap(layout.embeddedItems.first)
        let view = TextView()
        view.update(layout)
        let marker = CALayer()
        marker.frame = item.rect
        marker.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.25).cgColor
        marker.borderColor = NSColor.systemBlue.cgColor
        marker.borderWidth = 1
        view.addEmbeddedLayer(marker)
        let pixels = ViewSnapshot.render(view, scale: 3)
        let root = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        pixels.write(to: root.appendingPathComponent("bidi-embedded.png").path)
    }

    func testEmbeddedLTRGlyphKeepsItsExistingPadding() throws {
        let value = NSMutableAttributedString(string: "abc★", attributes: [.font: NSFont.systemFont(ofSize: 16), .foregroundColor: NSColor.black])
        value.addAttribute(TextInputAttributes.embedded, value: "icon", range: NSRange(location: 3, length: 1))
        let layout = TextViewLayout(value)
        layout.measure(width: 300)
        let item = try XCTUnwrap(layout.embeddedItems.first)
        XCTAssertEqual(item.rect.minX, 25)
        XCTAssertEqual(item.rect.width, 22)
    }
}
