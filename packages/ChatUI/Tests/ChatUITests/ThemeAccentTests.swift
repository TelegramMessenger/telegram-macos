import XCTest
import AppKit
import ColorPalette
import ThemeSettings
import TelegramTheme
import TGUIKit
import TelegramCore
import Postbox

final class ThemeAccentTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
        purgeImageCachesForMemoryPressure()
    }

    private func settings(_ palette: ColorPalette) -> ThemePaletteSettings {
        return ThemePaletteSettings.defaultTheme.withUpdatedPalette(palette).installDefaultWallpaper()
    }

    func testBuiltInAccentsUpdateOutgoingMessages() {
        for palette in [nightAccentPalette, whitePalette, dayClassicPalette] {
            for accent in palette.accentList.dropFirst() {
                let updated = settings(palette).withUpdatedAccentColor(accent)
                XCTAssertEqual(updated.palette.accent.argb, accent.accent.argb)
                XCTAssertNotEqual(updated.palette.bubbleBackground_outgoing, palette.bubbleBackground_outgoing)
                if let messages = accent.messages {
                    XCTAssertEqual(updated.palette.bubbleBackground_outgoing, messages)
                } else if palette.parent != .dayClassic {
                    XCTAssertEqual(updated.palette.bubbleBackground_outgoing, [accent.accent])
                }
            }
        }
    }

    func testEmptyMessageColoursUseTheDerivedColour() {
        for palette in [nightAccentPalette, whitePalette, dayClassicPalette] {
            let accent = NSColor(rgb: 0xc4528f)
            let unspecified = palette.withAccentColor(PaletteAccentColor(accent))
            let empty = palette.withAccentColor(PaletteAccentColor(accent, []))
            XCTAssertEqual(unspecified, empty)
            XCTAssertNotEqual(empty.bubbleBackground_outgoing, palette.bubbleBackground_outgoing)
        }
    }

    func testBasicAccentRestoresTheDefaultPalette() {
        for palette in [nightAccentPalette, whitePalette, dayClassicPalette] {
            let changed = settings(palette).withUpdatedAccentColor(PaletteAccentColor(NSColor(rgb: 0xc4528f)))
            for messages: [NSColor]? in [nil, []] {
                let restored = changed.withUpdatedAccentColor(PaletteAccentColor(palette.basicAccent, messages))
                XCTAssertEqual(restored.palette, palette)
                XCTAssertEqual(restored.installDefaultAccent().palette, palette)
            }
        }
    }

    func testExplicitMessageColoursSurviveBasicAccentAndThemeGeneration() {
        let messages = [NSColor(rgb: 0xffcc88), NSColor(rgb: 0xff99aa)]
        for palette in [nightAccentPalette, whitePalette, dayClassicPalette] {
            let updated = settings(palette).withUpdatedAccentColor(PaletteAccentColor(palette.basicAccent, messages))
            XCTAssertEqual(updated.palette.bubbleBackground_outgoing, messages)
            XCTAssertEqual(updated.installDefaultAccent().palette.bubbleBackground_outgoing, messages)
            let presentation = updateTheme(with: updated)
            XCTAssertEqual(presentation.colors.bubbleBackground_outgoing, messages)
            XCTAssertEqual(presentation.withUpdatedBackgroundSize(NSSize(width: 80, height: 55)).colors.bubbleBackground_outgoing, messages)
        }
    }

    func testNightAccentTintsBackgroundsAndDayThemesKeepTheirBackgrounds() {
        let accent = PaletteAccentColor(NSColor(rgb: 0xc4528f))
        let night = settings(nightAccentPalette).withUpdatedAccentColor(accent)
        XCTAssertNotEqual(night.palette.chatBackground, nightAccentPalette.chatBackground)
        XCTAssertNotEqual(night.palette.listBackground, nightAccentPalette.listBackground)
        for palette in [whitePalette, dayClassicPalette] {
            let updated = settings(palette).withUpdatedAccentColor(accent)
            XCTAssertEqual(updated.palette.chatBackground, palette.chatBackground)
            XCTAssertEqual(updated.wallpaper.wallpaper, palette.wallpaper.wallpaper)
        }
    }

    func testCustomWallpapersSurviveAccentChangesAndRestoration() {
        let image = TelegramMediaImageRepresentation(dimensions: PixelDimensions(width: 640, height: 480), resource: LocalFileMediaResource(fileId: 847261), progressiveSizes: [], immediateThumbnailData: nil)
        let wallpapers: [Wallpaper] = [.color(0x5588aa), .gradient(nil, [0x5588aa, 0xaa8855], 45), .image([image], settings: WallpaperSettings()), .custom(image, blurred: true)]
        for palette in [nightAccentPalette, whitePalette, dayClassicPalette] {
            for wallpaper in wallpapers {
                let initial = settings(palette).updateWallpaper { _ in ThemeWallpaper(wallpaper: wallpaper, associated: nil) }.saveDefaultWallpaper()
                let updated = initial.withUpdatedAccentColor(PaletteAccentColor(NSColor(rgb: 0xc4528f)))
                XCTAssertEqual(updated.wallpaper.wallpaper, wallpaper)
                XCTAssertEqual(updated.installDefaultWallpaper().wallpaper.wallpaper, wallpaper)
                XCTAssertEqual(updated.withUpdatedAccentColor(PaletteAccentColor(palette.basicAccent)).wallpaper.wallpaper, wallpaper)
            }
        }
    }

    func testWallpaperCacheSeparatesAccents() {
        let size = NSSize(width: 100, height: 200)
        let red = nightAccentPalette.withAccentColor(PaletteAccentColor(.red))
        let green = nightAccentPalette.withAccentColor(PaletteAccentColor(.green))
        cacheBackground(.none, palette: red, size: size, background: .color(color: red.listBackground))
        XCTAssertNil(cachedBackground(.none, palette: green, size: size))
        XCTAssertEqual(cachedBackground(.none, palette: red, size: size), .color(color: red.listBackground))
        cacheBackground(.none, palette: green, size: size, background: .color(color: green.listBackground))
        XCTAssertEqual(cachedBackground(.none, palette: green, size: size), .color(color: green.listBackground))
        XCTAssertEqual(cachedBackground(.none, palette: red, size: size), .color(color: red.listBackground))
    }

    func testWallpaperCacheUsesPixelResolution() {
        let size = NSSize(width: 100, height: 200)
        cacheBackground(.none, palette: nightAccentPalette, size: size, background: .color(color: .red), scaleFactor: 1)
        XCTAssertNil(cachedBackground(.none, palette: nightAccentPalette, size: size, scaleFactor: 2))
        XCTAssertNil(cachedBackground(.none, palette: nightAccentPalette, size: NSSize(width: 80, height: 55), scaleFactor: 1))
        XCTAssertEqual(cachedBackground(.none, palette: nightAccentPalette, size: NSSize(width: 50, height: 100), scaleFactor: 2), .color(color: .red))
    }

    func testPerChatWallpaperOverridesDoNotChangeTheGlobalTheme() {
        let global = updateTheme(with: settings(nightAccentPalette).withUpdatedAccentColor(PaletteAccentColor(.red)))
        let wallpaper = ThemeWallpaper(wallpaper: .color(0x5588aa), associated: nil)
        let chat = global.withUpdatedWallpaper(wallpaper)
        XCTAssertEqual(chat.backgroundMode, .color(color: NSColor(rgb: 0x5588aa)))
        XCTAssertEqual(chat.colors, global.colors)
        XCTAssertEqual(global.wallpaper.wallpaper, .none)
    }
}
