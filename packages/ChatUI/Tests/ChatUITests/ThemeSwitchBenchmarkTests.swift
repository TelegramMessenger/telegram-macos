import XCTest
import AppKit
import QuartzCore
import Darwin
import TelegramCore
import ThemeSettings
import SwiftSignalKit
@testable import TelegramTheme

@available(macOS 14.0, *)
private final class ThemeSwitchFrameProbe: NSObject {
    let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 16, height: 16), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var link: CADisplayLink?
    private var lastTick: Double?
    var gaps: [Double] = []

    func start() {
        window.level = .floating
        window.orderFront(nil)
        let link = window.contentView!.displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        window.orderOut(nil)
    }

    @objc private func tick() {
        let now = CACurrentMediaTime()
        if let lastTick = lastTick { gaps.append(now - lastTick) }
        lastTick = now
    }
}

final class ThemeSwitchBenchmarkTests: XCTestCase {
    private func threadCPUTime() -> Double {
        var value = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &value)
        return Double(value.tv_sec) + Double(value.tv_nsec) / 1_000_000_000
    }

    private func baseline(presentation: Signal<TelegramPresentationTheme, NoError>, themes: [TelegramTheme]) -> Signal<[(ChatTheme, TelegramPresentationTheme)], NoError> {
        return presentation |> mapToSignal { presentation in
            var signals: [Signal<(ChatTheme, TelegramPresentationTheme), NoError>] = []
            for theme in themes {
                if let settings = theme.effectiveSettings(isDark: presentation.dark), let emoji = theme.emoticon {
                    let newTheme = presentation.withUpdatedColors(settings.palette)
                    if let wallpaper = settings.wallpaper?.uiWallpaper(nil) {
                        signals.append(Signal<Wallpaper, NoError>.single(wallpaper) |> map { wallpaper in
                            (.emoticon(emoji), newTheme.withUpdatedWallpaper(ThemeWallpaper(wallpaper: wallpaper, associated: nil)))
                        })
                    } else {
                        signals.append(.single((.emoticon(emoji), newTheme)))
                    }
                }
            }
            return .single([]) |> then(combineLatest(signals))
        }
    }

    @available(macOS 14.0, *)
    private func runScenario(prepared: Bool, fixtures: [TelegramTheme], presentations: [TelegramPresentationTheme]) -> [String: Any] {
        let input = ValuePromise<TelegramPresentationTheme>(PreparedChatThemesTests.presentation(), ignoreRepeated: false)
        let signal = prepared ? preparedChatThemes(presentation: input.get(), themes: .single(fixtures), cacheWallpaper: { .single($0) }) : baseline(presentation: input.get(), themes: fixtures)
        let probe = ThemeSwitchFrameProbe()
        var ready: XCTestExpectation? = expectation(description: "Initial themes")
        var submittedAt: Double?
        var latencies: [Double] = []
        var submissionTimes: [Double] = []
        var emptyUpdates = 0
        let disposable = signal.start(next: { themes in
            if themes.isEmpty {
                emptyUpdates += 1
                return
            }
            if let submittedAt = submittedAt { latencies.append(CACurrentMediaTime() - submittedAt) }
            ready?.fulfill()
        })
        wait(for: [ready!], timeout: 5)
        probe.start()
        let warm = expectation(description: "Display link warmup")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { warm.fulfill() }
        wait(for: [warm], timeout: 2)
        probe.gaps.removeAll()
        let cpuStart = threadCPUTime()
        for presentation in presentations {
            ready = expectation(description: "Theme switched")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.025) {
                submittedAt = CACurrentMediaTime()
                input.set(presentation)
                submissionTimes.append(CACurrentMediaTime() - submittedAt!)
            }
            wait(for: [ready!], timeout: 5)
        }
        let drained = expectation(description: "Final display frame")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        let cpu = threadCPUTime() - cpuStart
        probe.stop()
        disposable.dispose()
        XCTAssertEqual(latencies.count, presentations.count)
        XCTAssertFalse(probe.gaps.isEmpty)
        let sorted = latencies.sorted()
        return [
            "switches": presentations.count,
            "downloadedThemes": fixtures.count,
            "completionMedianMs": sorted[sorted.count / 2] * 1000,
            "completionP95Ms": sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))] * 1000,
            "mainSubmissionMeanMs": submissionTimes.reduce(0, +) / Double(submissionTimes.count) * 1000,
            "mainThreadCpuMs": cpu * 1000,
            "displayCallbacks": probe.gaps.count,
            "gapsOver33Ms": probe.gaps.filter { $0 > 0.0334 }.count,
            "worstCallbackGapMs": (probe.gaps.max() ?? 0) * 1000,
            "emptyThemeUpdates": emptyUpdates,
            "wallpaperImageDecodes": 0,
            "wallpaperFixture": "solid colours"
        ]
    }

    func testPreparationComparison() throws {
        guard #available(macOS 14.0, *) else { throw XCTSkip("Display-link benchmark requires macOS 14") }
        UITestBootstrap.install()
        let fixtures = (1...32).map { PreparedChatThemesTests.cloudTheme(id: Int64($0), colour: UInt32(0x558800 + $0)) }
        let presentations = (0..<20).map { PreparedChatThemesTests.presentation(fontSize: CGFloat(14 + $0 % 2)) }
        let results: [String: Any] = [
            "baselineAlgorithmCommit": "8a8791c1",
            "scope": "Downloaded chat-theme preparation; global UI redraw and crossfade are excluded",
            "baseline": runScenario(prepared: false, fixtures: fixtures, presentations: presentations),
            "prepared": runScenario(prepared: true, fixtures: fixtures, presentations: presentations)
        ]
        let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
        print("THEME_SWITCH_BENCHMARK " + String(decoding: data, as: UTF8.self))
    }
}
