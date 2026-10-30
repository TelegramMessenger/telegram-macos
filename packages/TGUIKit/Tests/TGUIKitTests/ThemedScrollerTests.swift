import XCTest
import AppKit
import ColorPalette
@testable import TGUIKit

final class ThemedScrollerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TGUIKitTestBootstrap.install()
    }

    func testVerticalOptInPreservesNativeScrollerIdentity() throws {
        let view = ScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 400))
        XCTAssertFalse(view.hasVerticalScroller)
        view.hasVerticalScroller = true
        let scroller = try XCTUnwrap(view.verticalScroller)
        XCTAssertTrue(scroller is ThemedScroller)
        XCTAssertEqual(scroller.scrollerStyle, .overlay)
        view.applyThemedVerticalScroller()
        XCTAssertTrue(view.verticalScroller === scroller)
        view.hasVerticalScroller = false
        view.hasVerticalScroller = true
        XCTAssertTrue(view.verticalScroller === scroller)
    }

    func testHorizontalOnlyViewDoesNotGainVerticalScroller() {
        let view = HorizontalScrollView(frame: NSRect(x: 0, y: 0, width: 320, height: 400))
        XCTAssertFalse(view.hasVerticalScroller)
    }
    func testHighContrastFollowsTelegramPaletteWithOppositeSystemAppearance() throws {
        guard #available(macOS 11.0, *) else { throw XCTSkip("Drawing appearance scopes require macOS 11") }
        let original = PresentationTheme.current
        defer { updateTheme(original) }
        let scroller = ThemedScroller(frame: NSRect(x: 0, y: 0, width: 16, height: 200))
        for palette in [nightAccentPalette, whitePalette] {
            updateTheme(PresentationTheme(colors: palette, search: original.search, inputTheme: original.inputTheme))
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                scroller.appearance = NSAppearance(named: appearance)
                scroller.effectiveAppearance.performAsCurrentDrawingAppearance {
                    for expanded in [false, true] {
                        let color = scroller.knobColor(expanded: expanded, highContrast: true)
                        XCTAssertEqual(color, palette.text.withAlphaComponent(1))
                        XCTAssertEqual(color.alphaComponent, 1)
                    }
                }
            }
        }
    }

    func testHighContrastUsesLightInkOnAlwaysDarkSurfacesInLightTheme() throws {
        let original = PresentationTheme.current
        defer { updateTheme(original) }
        updateTheme(PresentationTheme(colors: whitePalette, search: original.search, inputTheme: original.inputTheme))
        for background in [NSColor.black, NSColor.black.withAlphaComponent(0.6)] {
            let panel = View(frame: NSRect(x: 0, y: 0, width: 320, height: 400))
            panel.backgroundColor = background
            let scroll = ScrollView(frame: panel.bounds)
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            panel.addSubview(scroll)
            let scroller = try XCTUnwrap(scroll.verticalScroller as? ThemedScroller)
            let color = try XCTUnwrap(scroller.knobColor(expanded: false, highContrast: true).usingColorSpace(.sRGB))
            XCTAssertEqual(color.redComponent, 1, accuracy: 0.001)
            XCTAssertEqual(color.alphaComponent, 1)
        }
    }

    func testHighContrastUsesDarkInkOnLightSurfacesInDarkTheme() throws {
        let original = PresentationTheme.current
        defer { updateTheme(original) }
        updateTheme(PresentationTheme(colors: nightAccentPalette, search: original.search, inputTheme: original.inputTheme))
        let panel = View(frame: NSRect(x: 0, y: 0, width: 320, height: 400))
        panel.backgroundColor = .white
        let scroll = ScrollView(frame: panel.bounds)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        panel.addSubview(scroll)
        let scroller = try XCTUnwrap(scroll.verticalScroller as? ThemedScroller)
        let color = try XCTUnwrap(scroller.knobColor(expanded: true, highContrast: true).usingColorSpace(.sRGB))
        XCTAssertEqual(color.redComponent, 0, accuracy: 0.001)
        XCTAssertEqual(color.alphaComponent, 1)
    }

}
