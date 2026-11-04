import AppKit
import ColorPalette
import SwiftSignalKit

public func systemThemeColorsSignal() -> Signal<ColorPalette, NoError> {
    return systemThemeColorsSignal(notificationCenter: .default, application: NSApplication.shared, palette: {
        systemPalette.withUpdatedName(systemPalette.name)
    })
}

func systemThemeColorsSignal(notificationCenter: NotificationCenter, application: NSApplication?, palette: @escaping () -> ColorPalette) -> Signal<ColorPalette, NoError> {
    return Signal { subscriber in
        assert(Thread.isMainThread)
        let disposed = Atomic<Bool>(value: false)
        let scheduled = Atomic<Bool>(value: false)
        let update: () -> Void = {
            if scheduled.swap(true) {
                return
            }
            DispatchQueue.main.async {
                _ = scheduled.swap(false)
                if !disposed.with({ $0 }) {
                    subscriber.putNext(palette())
                }
            }
        }
        let observer = notificationCenter.addObserver(forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { _ in
            update()
        }
        var appearanceObservation: NSKeyValueObservation?
        if #available(macOS 10.14, *), let application = application {
            appearanceObservation = application.observe(\.effectiveAppearance, options: []) { _, _ in
                update()
            }
        }
        subscriber.putNext(palette())
        return ActionDisposable {
            _ = disposed.swap(true)
            notificationCenter.removeObserver(observer)
            appearanceObservation?.invalidate()
        }
    } |> distinctUntilChanged
}
