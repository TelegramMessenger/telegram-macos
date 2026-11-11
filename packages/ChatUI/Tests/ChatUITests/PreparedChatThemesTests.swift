import XCTest
import AppKit
import ColorPalette
import SwiftSignalKit
import TelegramCore
import ThemeSettings
import TGUIKit
import Postbox
@testable import TelegramTheme

final class PreparedChatThemesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
        purgeImageCachesForMemoryPressure()
    }

    static func presentation(fontSize: CGFloat = 13) -> TelegramPresentationTheme {
        return generateTheme(palette: nightAccentPalette, cloudTheme: nil, bubbled: true, fontSize: fontSize, wallpaper: ThemeWallpaper(), liquidGlass: false)
    }

    static func cloudTheme(id: Int64 = 1, colour: UInt32 = 0x5588aa) -> TelegramTheme {
        let settings = TelegramThemeSettings(baseTheme: .tinted, accentColor: colour, outgoingAccentColor: nil, messageColors: [], animateMessageColors: false, wallpaper: .color(colour))
        return TelegramTheme(id: id, accessHash: 0, slug: "test-\(id)", emoticon: "🎨\(id)", title: "Test", file: nil, settings: [settings], isCreator: false, isDefault: false, installCount: nil)
    }

    func testPreparationRunsInBackgroundAndPublishesOnMain() {
        let prepared = expectation(description: "Prepared chat themes")
        let disposable = preparedChatThemes(presentation: .single(Self.presentation()), themes: .single([Self.cloudTheme()]), cacheWallpaper: { wallpaper in
            XCTAssertFalse(Thread.isMainThread)
            return .single(wallpaper)
        }).start(next: { themes in
            XCTAssertTrue(Thread.isMainThread)
            XCTAssertEqual(themes.count, 1)
            XCTAssertEqual(themes.first?.1.wallpaper.wallpaper, .color(0x5588aa))
            XCTAssertEqual(themes.first?.1.backgroundMode, .color(color: NSColor(rgb: 0x5588aa)))
            prepared.fulfill()
        })
        wait(for: [prepared], timeout: 3)
        disposable.dispose()
    }

    func testEquivalentPresentationInputsDoNotRebuildThemes() {
        let queue = Queue(name: "PreparedChatThemesTests")
        let presentation = Self.presentation()
        let input = ValuePromise<TelegramPresentationTheme>(presentation, ignoreRepeated: false)
        let reads = Atomic<Int>(value: 0)
        var emissions = 0
        let prepared = expectation(description: "Initial preparation")
        let disposable = preparedChatThemes(presentation: input.get(), themes: .single([Self.cloudTheme()]), cacheWallpaper: { wallpaper in
            _ = reads.modify { $0 + 1 }
            return .single(wallpaper)
        }, queue: queue).start(next: { _ in
            emissions += 1
            prepared.fulfill()
        })
        wait(for: [prepared], timeout: 3)
        for _ in 0..<10 { input.set(presentation.withUpdatedWallpaper(presentation.wallpaper)) }
        let drained = expectation(description: "Preparation queue drained")
        queue.justDispatch { DispatchQueue.main.async { drained.fulfill() } }
        wait(for: [drained], timeout: 3)
        XCTAssertEqual(reads.with { $0 }, 1)
        XCTAssertEqual(emissions, 1)
        disposable.dispose()
    }

    func testNewerSelectionCancelsQueuedPreparation() {
        let queue = Queue(name: "PreparedChatThemesCancellationTests")
        let gate = DispatchSemaphore(value: 0)
        queue.justDispatch { gate.wait() }
        let input = ValuePromise<TelegramPresentationTheme>(Self.presentation(), ignoreRepeated: false)
        let prepared = expectation(description: "Latest selection prepared")
        var values: [CGFloat] = []
        let disposable = preparedChatThemes(presentation: input.get(), themes: .single([Self.cloudTheme()]), cacheWallpaper: { .single($0) }, queue: queue).start(next: { themes in
            values.append(themes[0].1.fontSize)
            prepared.fulfill()
        })
        input.set(Self.presentation(fontSize: 17))
        gate.signal()
        wait(for: [prepared], timeout: 3)
        XCTAssertEqual(values, [17])
        disposable.dispose()
    }

    func testCurrentThemesStayPublishedWhileReplacementWallpaperLoads() {
        let input = ValuePromise<[TelegramTheme]>([Self.cloudTheme()], ignoreRepeated: false)
        let pending = Promise<Wallpaper>()
        let initial = expectation(description: "Initial themes")
        let loading = expectation(description: "Replacement loading")
        let replacement = expectation(description: "Replacement themes")
        var values: [[Wallpaper]] = []
        let disposable = preparedChatThemes(presentation: .single(Self.presentation()), themes: input.get(), cacheWallpaper: { wallpaper in
            if wallpaper == .color(0xaa8855) {
                loading.fulfill()
                return pending.get()
            }
            return .single(wallpaper)
        }).start(next: { themes in
            values.append(themes.map { $0.1.wallpaper.wallpaper })
            if values.count == 1 { initial.fulfill() } else { replacement.fulfill() }
        })
        wait(for: [initial], timeout: 3)
        input.set([Self.cloudTheme(colour: 0xaa8855)])
        wait(for: [loading], timeout: 3)
        XCTAssertEqual(values, [[.color(0x5588aa)]])
        pending.set(.single(.color(0xaa8855)))
        wait(for: [replacement], timeout: 3)
        XCTAssertEqual(values, [[.color(0x5588aa)], [.color(0xaa8855)]])
        disposable.dispose()
    }

    func testEmptyServerListClearsPreparedThemes() {
        let input = ValuePromise<[TelegramTheme]>([Self.cloudTheme()], ignoreRepeated: false)
        let initial = expectation(description: "Initial themes")
        let cleared = expectation(description: "Themes cleared")
        var counts: [Int] = []
        let disposable = preparedChatThemes(presentation: .single(Self.presentation()), themes: input.get(), cacheWallpaper: { .single($0) }).start(next: { themes in
            counts.append(themes.count)
            if themes.isEmpty { cleared.fulfill() } else { initial.fulfill() }
        })
        wait(for: [initial], timeout: 3)
        input.set([])
        wait(for: [cleared], timeout: 3)
        XCTAssertEqual(counts, [1, 0])
        disposable.dispose()
    }

    func testObsoleteWallpaperCompletionCannotReplaceNewerThemes() {
        let input = ValuePromise<[TelegramTheme]>([Self.cloudTheme()], ignoreRepeated: false)
        let pending = Promise<Wallpaper>()
        let loading = expectation(description: "Old wallpaper loading")
        let prepared = expectation(description: "New themes ready")
        var values: [Wallpaper] = []
        let disposable = preparedChatThemes(presentation: .single(Self.presentation()), themes: input.get(), cacheWallpaper: { wallpaper in
            if wallpaper == .color(0x5588aa) {
                loading.fulfill()
                return pending.get()
            }
            return .single(wallpaper)
        }).start(next: { themes in
            values.append(themes[0].1.wallpaper.wallpaper)
            prepared.fulfill()
        })
        wait(for: [loading], timeout: 3)
        input.set([Self.cloudTheme(colour: 0xaa8855)])
        wait(for: [prepared], timeout: 3)
        pending.set(.single(.color(0x5588aa)))
        let drained = expectation(description: "Main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 3)
        XCTAssertEqual(values, [.color(0xaa8855)])
        disposable.dispose()
    }

    func testEagerPreparationReusesTheCachedBackground() {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        let mode = TableBackgroundMode.background(image: image, intensity: nil, colors: nil, rotation: nil, metadata: nil)
        let size = NSSize(width: 1040, height: 1580)
        cacheBackground(.none, palette: nightAccentPalette, size: size, background: mode)
        let prepared = expectation(description: "Eager background prepared")
        DispatchQueue.global().async {
            for fontSize: CGFloat in [13, 17] {
                let presentation = Self.presentation(fontSize: fontSize)
                if case let .background(cached, _, _, _, _) = presentation.backgroundMode {
                    XCTAssertTrue(cached === image)
                } else {
                    XCTFail("Generated themes must use the background cache")
                }
            }
            prepared.fulfill()
        }
        wait(for: [prepared], timeout: 3)
    }

    func testCustomWallpaperImagesAreReusedAcrossAccentChanges() {
        let image = NSImage(size: NSSize(width: 10, height: 10))
        let mode = TableBackgroundMode.background(image: image, intensity: nil, colors: nil, rotation: nil, metadata: nil)
        let representation = TelegramMediaImageRepresentation(dimensions: PixelDimensions(width: 640, height: 480), resource: LocalFileMediaResource(fileId: 372918), progressiveSizes: [], immediateThumbnailData: nil)
        let wallpaper = ThemeWallpaper(wallpaper: .custom(representation, blurred: false), associated: nil)
        let red = nightAccentPalette.withAccentColor(PaletteAccentColor(.red))
        let green = nightAccentPalette.withAccentColor(PaletteAccentColor(.green))
        cacheBackground(wallpaper.wallpaper, palette: red, size: NSSize(width: 1040, height: 1580), background: mode)
        let prepared = expectation(description: "Cached custom wallpaper")
        DispatchQueue.global().async {
            for palette in [red, green] {
                let presentation = generateTheme(palette: palette, cloudTheme: nil, bubbled: true, fontSize: 13, wallpaper: wallpaper, liquidGlass: false)
                if case let .background(cached, _, _, _, _) = presentation.backgroundMode {
                    XCTAssertTrue(cached === image)
                } else {
                    XCTFail("Accent changes must reuse the decoded custom image")
                }
            }
            prepared.fulfill()
        }
        wait(for: [prepared], timeout: 3)
        XCTAssertNil(cachedBackground(wallpaper.wallpaper, palette: whitePalette, size: NSSize(width: 1040, height: 1580)))
    }

    func testEmoticonBackgroundUsesItsCurrentThemeList() {
        let base = Self.presentation()
        let wallpaper = ThemeWallpaper(wallpaper: .emoticon("🎨"), associated: nil)
        let red = base.withUpdatedWallpaper(ThemeWallpaper(wallpaper: .color(0xff0000), associated: nil))
        let green = base.withUpdatedWallpaper(ThemeWallpaper(wallpaper: .color(0x00ff00), associated: nil))
        let first = base.withUpdatedWallpaper(wallpaper).withUpdatedEmoticonThemes([(.emoticon("🎨"), red)])
        let second = base.withUpdatedWallpaper(wallpaper).withUpdatedEmoticonThemes([(.emoticon("🎨"), green)])
        XCTAssertEqual(first.backgroundMode, .color(color: NSColor(rgb: 0xff0000)))
        XCTAssertEqual(second.backgroundMode, .color(color: NSColor(rgb: 0x00ff00)))
    }

    func testDerivedThemesPreserveTheirCapturedDisplaySettings() {
        let base = generateTheme(palette: nightAccentPalette, cloudTheme: nil, bubbled: true, fontSize: 13, wallpaper: ThemeWallpaper(), liquidGlass: false, scaleFactor: 1)
        let derived = [base.withUpdatedColors(whitePalette), base.withUpdatedWallpaper(ThemeWallpaper()), base.withUpdatedBackgroundSize(NSSize(width: 80, height: 55)), base.withUpdatedChatMode(false), base.withUpdatedEmoticonThemes([])]
        for theme in derived {
            XCTAssertEqual(theme.scaleFactor, 1)
            XCTAssertFalse(theme.liquidGlass)
            XCTAssertEqual(theme.liteMode, base.liteMode)
        }
    }

    func testChatThemesSelectTheMatchingLightAndDarkSettings() {
        let dark = TelegramThemeSettings(baseTheme: .tinted, accentColor: 0xff0000, outgoingAccentColor: nil, messageColors: [], animateMessageColors: false, wallpaper: .color(0xff0000))
        let light = TelegramThemeSettings(baseTheme: .day, accentColor: 0x00ff00, outgoingAccentColor: nil, messageColors: [], animateMessageColors: false, wallpaper: .color(0x00ff00))
        let theme = TelegramTheme(id: 1, accessHash: 0, slug: "test", emoticon: "🎨", title: "Test", file: nil, settings: [dark, light], isCreator: false, isDefault: false, installCount: nil)
        let input = ValuePromise<TelegramPresentationTheme>(Self.presentation(), ignoreRepeated: false)
        let darkReady = expectation(description: "Dark theme ready")
        let lightReady = expectation(description: "Light theme ready")
        let disposable = preparedChatThemes(presentation: input.get(), themes: .single([theme]), cacheWallpaper: { .single($0) }).start(next: { themes in
            let theme = themes[0].1
            if theme.dark {
                XCTAssertEqual(theme.wallpaper.wallpaper, .color(0xff0000))
                darkReady.fulfill()
            } else {
                XCTAssertEqual(theme.wallpaper.wallpaper, .color(0x00ff00))
                lightReady.fulfill()
            }
        })
        wait(for: [darkReady], timeout: 3)
        input.set(generateTheme(palette: whitePalette, cloudTheme: nil, bubbled: true, fontSize: 13, wallpaper: ThemeWallpaper(), liquidGlass: false))
        wait(for: [lightReady], timeout: 3)
        disposable.dispose()
    }
}
