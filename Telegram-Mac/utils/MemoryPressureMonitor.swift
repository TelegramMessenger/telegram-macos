import Cocoa
import SwiftSignalKit
import TelegramCore
import Postbox
#if SHARE
import TelegramThemeShare
#else
import TelegramTheme
import UniqueGiftBackground
#endif

public final class MemoryPressureMonitor {
    private let source: DispatchSourceMemoryPressure
    private var trimTimer: SwiftSignalKit.Timer?
    private var observers: [NSObjectProtocol] = []

    public init() {
        self.source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        self.source.setEventHandler { [weak self] in
            self?.handlePressure()
        }
        self.source.resume()

        let center = NotificationCenter.default
        self.observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleInactiveTrim()
        })
        self.observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.trimTimer?.invalidate()
            self?.trimTimer = nil
        })
    }

    deinit {
        self.source.cancel()
        self.trimTimer?.invalidate()
        for observer in self.observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func handlePressure() {
        let event = self.source.data
        purgeImageCachesForMemoryPressure()
        #if !SHARE
        UniqueGiftBackgroundCache.shared.removeAll()
        UniqueGiftPatternGlyphs.shared.removeAll()
        #endif
        URLCache.shared.removeAllCachedResponses()
        let released = self.trimAllocator()
        Logger.shared.log("Memory", "pressure \(event.contains(.critical) ? "critical" : "warning"): image caches purged, allocator released \(released / 1024) KB")
    }

    private func scheduleInactiveTrim() {
        self.trimTimer?.invalidate()
        let timer = SwiftSignalKit.Timer(timeout: 20, repeat: false, completion: { [weak self] in
            guard let self, !NSApp.isActive else {
                return
            }
            let released = self.trimAllocator()
            Logger.shared.log("Memory", "inactive trim released \(released / 1024) KB")
        }, queue: .mainQueue())
        self.trimTimer = timer
        timer.start()
    }

    @discardableResult
    private func trimAllocator() -> Int {
        return malloc_zone_pressure_relief(nil, 0)
    }
}
