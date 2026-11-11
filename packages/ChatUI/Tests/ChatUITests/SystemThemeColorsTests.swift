import XCTest
import AppKit
import ColorPalette
import SwiftSignalKit
import ThemeSettings
@testable import TelegramTheme

final class SystemThemeColorsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
    }

    func testNotificationsAreCoalescedAndSnapshotsStayImmutable() {
        let center = NotificationCenter()
        let red = systemPalette.withAccentColor(PaletteAccentColor(.red))
        let green = systemPalette.withAccentColor(PaletteAccentColor(.green))
        var current = red
        var reads = 0
        var values: [ColorPalette] = []
        let changed = expectation(description: "Updated system colours")
        let disposable = systemThemeColorsSignal(notificationCenter: center, application: nil, palette: {
            XCTAssertTrue(Thread.isMainThread)
            reads += 1
            return current.withUpdatedName(current.name)
        }).start(next: { value in
            values.append(value)
            if values.count == 2 {
                changed.fulfill()
            }
        })
        XCTAssertEqual(values.count, 1)
        current = green
        for _ in 0..<10 {
            center.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
        }
        wait(for: [changed], timeout: 2)
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(values[0].accent.argb, NSColor.red.argb)
        XCTAssertEqual(values[1].accent.argb, NSColor.green.argb)
        XCTAssertNotEqual(values[0].colorSignature, values[1].colorSignature)
        disposable.dispose()
    }

    func testUnchangedColoursAreNotPublishedAgain() {
        let center = NotificationCenter()
        var reads = 0
        var values = 0
        let processed = expectation(description: "Notification processed")
        let disposable = systemThemeColorsSignal(notificationCenter: center, application: nil, palette: {
            reads += 1
            if reads == 2 {
                processed.fulfill()
            }
            return systemPalette.withUpdatedName(systemPalette.name)
        }).start(next: { _ in values += 1 })
        center.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
        wait(for: [processed], timeout: 2)
        XCTAssertEqual(values, 1)
        disposable.dispose()
    }

    func testOnlyLatestColoursFromRapidChangesArePublished() {
        let center = NotificationCenter()
        var current = systemPalette.withAccentColor(PaletteAccentColor(.red))
        var values: [ColorPalette] = []
        let changed = expectation(description: "Latest colours")
        let disposable = systemThemeColorsSignal(notificationCenter: center, application: nil, palette: { current }).start(next: { value in
            values.append(value)
            if values.count == 2 {
                changed.fulfill()
            }
        })
        current = systemPalette.withAccentColor(PaletteAccentColor(.green))
        center.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
        current = systemPalette.withAccentColor(PaletteAccentColor(.blue))
        center.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
        wait(for: [changed], timeout: 2)
        XCTAssertEqual(values.count, 2)
        XCTAssertEqual(values.last?.accent.argb, NSColor.blue.argb)
        disposable.dispose()
    }

    func testDisposalCancelsQueuedUpdates() {
        let center = NotificationCenter()
        var reads = 0
        let disposable = systemThemeColorsSignal(notificationCenter: center, application: nil, palette: {
            reads += 1
            return systemPalette.withUpdatedName(systemPalette.name)
        }).start()
        center.post(name: NSColor.systemColorsDidChangeNotification, object: nil)
        disposable.dispose()
        let drained = expectation(description: "Main queue drained")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertEqual(reads, 1)
    }

    func testApplicationAppearanceChangesAreObserved() {
        guard #available(macOS 10.14, *) else { return }
        let previous = NSApp.appearance
        defer { NSApp.appearance = previous }
        NSApp.appearance = NSAppearance(named: .aqua)
        let changed = expectation(description: "Application appearance observed")
        var reads = 0
        let disposable = systemThemeColorsSignal(notificationCenter: NotificationCenter(), application: NSApp, palette: {
            reads += 1
            if reads == 2 { changed.fulfill() }
            return systemPalette.withUpdatedName(systemPalette.name)
        }).start()
        NSApp.appearance = NSAppearance(named: .darkAqua)
        wait(for: [changed], timeout: 2)
        disposable.dispose()
    }

    func testThemeGenerationKeepsResolvedSystemColours() {
        let settings = ThemePaletteSettings.defaultTheme.withUpdatedPalette(systemPalette)
        let red = systemPalette.withAccentColor(PaletteAccentColor(.red))
        let green = systemPalette.withAccentColor(PaletteAccentColor(.green))
        let first = updateTheme(with: settings, resolvedSystemPalette: red)
        let second = updateTheme(with: settings, resolvedSystemPalette: green)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.colors.accent.argb, NSColor.red.argb)
        XCTAssertEqual(second.colors.accent.argb, NSColor.green.argb)
        XCTAssertEqual(first.inputTheme.accentColor.argb, NSColor.red.argb)
        XCTAssertEqual(second.inputTheme.accentColor.argb, NSColor.green.argb)
    }

    func testResolvedSystemColoursDoNotOverrideOtherThemes() {
        let settings = ThemePaletteSettings.defaultTheme.withUpdatedPalette(nightAccentPalette)
        let red = systemPalette.withAccentColor(PaletteAccentColor(.red))
        let green = systemPalette.withAccentColor(PaletteAccentColor(.green))
        XCTAssertEqual(updateTheme(with: settings, resolvedSystemPalette: red), updateTheme(with: settings, resolvedSystemPalette: green))
    }

    func testDefaultSystemThemeGenerationUsesAColourSnapshot() {
        let settings = ThemePaletteSettings.defaultTheme.withUpdatedPalette(systemPalette)
        let presentation = updateTheme(with: settings)
        XCTAssertFalse(presentation.colors === systemPalette)
        XCTAssertEqual(presentation.colors.accent.argb, systemPalette.accent.argb)
        XCTAssertNotEqual(presentation.colors.colorSignature, systemPalette.colorSignature)
    }
}
