import Cocoa
import TGUIKit

private final class DetachedWindowCapsuleView: View {
    override var mouseDownCanMoveWindow: Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

public final class DetachedWindowControls {
    private static let registry = NSMapTable<NSWindow, DetachedWindowControls>.weakToStrongObjects()

    @discardableResult
    public static func install(on window: Window) -> DetachedWindowControls {
        if let existing = registry.object(forKey: window) {
            return existing
        }
        let controls = DetachedWindowControls(window: window)
        registry.setObject(controls, forKey: window)
        return controls
    }

    public static func reservedWidth(in window: NSWindow?) -> CGFloat {
        guard let window, let controls = registry.object(forKey: window) else {
            return 0
        }
        return controls.reservedWidth
    }

    private weak var window: Window?
    private let host = DetachedWindowCapsuleView(frame: .zero)
    private let glass = GlassContainerView(frame: .zero, flipped: true, spacing: 5)
    private let capsule = LiquidGlassView(frame: .zero, cornerRadius: DetachedWindowHeaderLayout.height / 2, hasShadow: true, hasBorder: true, tintAlpha: 0.4)
    private var layout: DetachedWindowHeaderLayout?
    private var observers: [NSObjectProtocol] = []
    private var fullScreenTransition = false

    private init(window: Window) {
        self.window = window
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        let toolbar = NSToolbar(identifier: "detached-window")
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        if #available(macOS 11.0, *) {
            window.toolbarStyle = .unified
        }
        glass.addGhost(capsule)
        host.addSubview(glass)
        place()

        let notifications = NotificationCenter.default
        observers.append(notifications.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
            self?.fullScreenTransition = true
            self?.host.isHidden = true
        })
        observers.append(notifications.addObserver(forName: NSWindow.didExitFullScreenNotification, object: window, queue: .main) { [weak self] _ in
            self?.fullScreenTransition = false
            self?.host.isHidden = false
            self?.window?.contentView?.needsLayout = true
        })
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
        host.removeFromSuperview()
    }

    public var reservedWidth: CGFloat {
        guard let window, let layout, !window.isFullScreen, !fullScreenTransition else {
            return 0
        }
        return layout.reservedWidth
    }

    public func bringToFront() {
        guard let contentView = window?.contentView else {
            return
        }
        contentView.addSubview(host, positioned: .above, relativeTo: nil)
    }

    public func updateTheme(_ theme: PresentationTheme) {
        capsule.updateLocalizationAndTheme(theme: theme)
    }

    private func place() {
        guard let window, let contentView = window.contentView else {
            return
        }
        contentView.superview?.layoutSubtreeIfNeeded()
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
        guard let titlebar = buttons.first?.superview else {
            return
        }
        let height = window.frame.height
        let topLeft: (NSRect) -> NSRect = { rect in
            return NSRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
        }
        let buttonsFrame = buttons.map { $0.convert($0.bounds, to: nil) }.reduce(NSRect.null) { $0.union($1) }
        let layout = DetachedWindowHeaderLayout(buttonsFrame: topLeft(buttonsFrame), titlebarFrame: topLeft(titlebar.convert(titlebar.bounds, to: nil)))
        self.layout = layout
        window.setTrafficLightsInset(layout.buttonsOffset)

        let capsuleFrame = layout.capsuleFrame
        if contentView.isFlipped {
            host.frame = capsuleFrame
            host.autoresizingMask = [.maxXMargin, .maxYMargin]
        } else {
            host.frame = NSRect(x: capsuleFrame.minX, y: contentView.bounds.height - capsuleFrame.maxY, width: capsuleFrame.width, height: capsuleFrame.height)
            host.autoresizingMask = [.maxXMargin, .minYMargin]
        }
        glass.frame = host.bounds
        glass.updateLayout(size: host.bounds.size, transition: .immediate)
        glass.setGhostFrame(capsule, frame: host.bounds, transition: .immediate)
        bringToFront()
    }
}
