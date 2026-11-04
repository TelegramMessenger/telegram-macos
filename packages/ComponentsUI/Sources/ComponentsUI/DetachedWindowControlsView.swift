import Cocoa
import TGUIKit

public final class DetachedWindowControlsView: View {
    private var buttons: [(button: NSButton, parent: NSView, frame: NSRect, autoresizingMask: NSView.AutoresizingMask)] = []
    private weak var attachedWindow: NSWindow?
    private var originalChrome: (fullSize: Bool, transparent: Bool, visibility: NSWindow.TitleVisibility)?
    private var observers: [NSObjectProtocol] = []
    private var enteringFullScreen = false
    private var compactChromeApplied = false
    private var updatingPresentation = false
    private var trackedGroupRect: NSRect?
    public var visibilityChanged: (() -> Void)?
    public var restoresTitlebarWhenWide = true {
        didSet {
            updatePresentation()
        }
    }

    public var showsControls: Bool {
        return !buttons.isEmpty
    }

    public func attach(to window: NSWindow) {
        guard attachedWindow !== window else { return }
        detach()
        attachedWindow = window
        originalChrome = (window.styleMask.contains(.fullSizeContentView), window.titlebarAppearsTransparent, window.titleVisibility)
        let notifications = NotificationCenter.default
        observers.append(notifications.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
            self?.enteringFullScreen = true
            self?.updatePresentation()
        })
        observers.append(notifications.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
            self?.enteringFullScreen = false
            self?.updatePresentation()
        })
        for name in [NSWindow.didUpdateNotification, NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification, NSWindow.didDeminiaturizeNotification] {
            observers.append(notifications.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.updatePresentation()
            })
        }
        updatePresentation()
    }

    public func detach() {
        guard attachedWindow != nil || !observers.isEmpty || !buttons.isEmpty else { return }
        let window = attachedWindow
        let chrome = originalChrome
        let restoreChrome = compactChromeApplied
        attachedWindow = nil
        originalChrome = nil
        compactChromeApplied = false
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        observers.removeAll()
        restoreButtons()
        if restoreChrome, let window, let chrome {
            applyOriginalChrome(chrome, to: window)
        }
        if let window {
            updateNativeHoverTracking(in: window)
        }
        enteringFullScreen = false
        visibilityChanged?()
    }

    private func applyOriginalChrome(_ chrome: (fullSize: Bool, transparent: Bool, visibility: NSWindow.TitleVisibility), to window: NSWindow) {
        if !chrome.fullSize {
            window.styleMask.remove(.fullSizeContentView)
        }
        window.titlebarAppearsTransparent = chrome.transparent
        window.titleVisibility = chrome.visibility
    }

    private func updatePresentation() {
        guard let window = attachedWindow, !updatingPresentation else { return }
        updatingPresentation = true
        defer { updatingPresentation = false }
        let hadControls = showsControls
        if window.styleMask.contains(.fullScreen) || enteringFullScreen {
            restoreButtons()
        } else if !restoresTitlebarWhenWide || DetachedWindowHeaderLayout.usesCompactLayout(width: window.frame.width) {
            if !compactChromeApplied {
                compactChromeApplied = true
                window.styleMask.insert(.fullSizeContentView)
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
            }
            installButtons()
            positionButtons()
        } else {
            restoreButtons()
            if compactChromeApplied, let chrome = originalChrome {
                compactChromeApplied = false
                applyOriginalChrome(chrome, to: window)
            }
        }
        if !showsControls {
            updateNativeHoverTracking(in: window)
        }
        if hadControls != showsControls {
            visibilityChanged?()
        }
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
    }

    private func restoreButtons() {
        let previousButtons = buttons
        buttons.removeAll()
        for entry in previousButtons {
            entry.parent.addSubview(entry.button)
            entry.button.frame = entry.frame
            entry.button.autoresizingMask = entry.autoresizingMask
        }
    }

    public override func layout() {
        super.layout()
        positionButtons()
    }

    public override func willRemoveSubview(_ subview: NSView) {
        super.willRemoveSubview(subview)
        if buttons.contains(where: { $0.button === subview }) {
            DispatchQueue.main.async { [weak self] in
                self?.positionButtons()
            }
        }
    }

    private func updateNativeHoverTracking(in window: NSWindow) {
        let rect = buttons.isEmpty ? nil : convert(bounds, to: nil)
        guard rect != trackedGroupRect else { return }
        trackedGroupRect = rect
        let selector = NSSelectorFromString("_updateMouseTracking")
        if let themeFrame = window.contentView?.superview, themeFrame.responds(to: selector) {
            themeFrame.perform(selector)
        }
    }

    private func positionButtons() {
        guard let window = attachedWindow, !window.styleMask.contains(.fullScreen), !enteringFullScreen, !buttons.isEmpty else { return }
        let spacing = DetachedWindowHeaderLayout.buttonSpacing
        var x = DetachedWindowHeaderLayout.controlsLeadingInset
        for entry in buttons {
            let size = entry.frame.size
            if entry.button.superview !== self {
                addSubview(entry.button)
                trackedGroupRect = nil
            }
            let frame = NSRect(x: x, y: floor((bounds.height - size.height) / 2), width: size.width, height: size.height)
            if entry.button.frame != frame {
                entry.button.frame = frame
                trackedGroupRect = nil
            }
            x += size.width + spacing
        }
        updateNativeHoverTracking(in: window)
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
