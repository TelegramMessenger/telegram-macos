import Cocoa
import TGUIKit

public final class DetachedWindowControlsView: View {
    private var buttons: [(button: NSButton, parent: NSView, frame: NSRect, autoresizingMask: NSView.AutoresizingMask)] = []
    private weak var attachedWindow: NSWindow?
    private var originalChrome: (fullSize: Bool, transparent: Bool, visibility: NSWindow.TitleVisibility)?
    private var observers: [NSObjectProtocol] = []
    private var enteringFullScreen = false
    public var visibilityChanged: (() -> Void)?

    public var showsControls: Bool {
        return !buttons.isEmpty
    }

    public func attach(to window: NSWindow) {
        guard attachedWindow !== window else { return }
        detach()
        attachedWindow = window
        originalChrome = (window.styleMask.contains(.fullSizeContentView), window.titlebarAppearsTransparent, window.titleVisibility)
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        let notifications = NotificationCenter.default
        observers.append(notifications.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
            self?.enteringFullScreen = true
            self?.restoreButtons()
            self?.visibilityChanged?()
        })
        observers.append(notifications.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
            self?.enteringFullScreen = false
            self?.installButtons()
        })
        for name in [NSWindow.didUpdateNotification, NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification, NSWindow.didDeminiaturizeNotification] {
            observers.append(notifications.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.positionButtons()
            })
        }
        installButtons()
    }

    public func detach() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        restoreButtons()
        if let window = attachedWindow, let chrome = originalChrome {
            if !chrome.fullSize {
                window.styleMask.remove(.fullSizeContentView)
            }
            window.titlebarAppearsTransparent = chrome.transparent
            window.titleVisibility = chrome.visibility
        }
        attachedWindow = nil
        originalChrome = nil
        enteringFullScreen = false
        visibilityChanged?()
    }

    private func installButtons() {
        guard let window = attachedWindow, !window.styleMask.contains(.fullScreen), !enteringFullScreen, buttons.isEmpty else { return }
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            if let button = window.standardWindowButton(kind), let parent = button.superview {
                buttons.append((button, parent, button.frame, button.autoresizingMask))
                button.autoresizingMask = []
                addSubview(button)
            }
        }
        positionButtons()
        visibilityChanged?()
    }

    private func restoreButtons() {
        for entry in buttons {
            entry.parent.addSubview(entry.button)
            entry.button.frame = entry.frame
            entry.button.autoresizingMask = entry.autoresizingMask
        }
        buttons.removeAll()
    }

    public override func layout() {
        super.layout()
        positionButtons()
    }

    private func positionButtons() {
        guard let window = attachedWindow, !window.styleMask.contains(.fullScreen), !enteringFullScreen else { return }
        let spacing: CGFloat = 6
        let width = buttons.reduce(CGFloat(0)) { $0 + $1.frame.width } + CGFloat(max(0, buttons.count - 1)) * spacing
        var x = floor((bounds.width - width) / 2)
        for entry in buttons {
            let size = entry.frame.size
            if entry.button.superview !== self {
                addSubview(entry.button)
            }
            let frame = NSRect(x: x, y: floor((bounds.height - size.height) / 2), width: size.width, height: size.height)
            if entry.button.frame != frame {
                entry.button.frame = frame
            }
            x += size.width + spacing
        }
    }

    public override var mouseDownCanMoveWindow: Bool {
        return true
    }

    public override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }

    deinit {
        detach()
    }
}
