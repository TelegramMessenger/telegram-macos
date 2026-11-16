import AppKit

public struct AnimatableContentObserverOptions: OptionSet {
    public let rawValue: Int
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    public static let contentBounds = AnimatableContentObserverOptions(rawValue: 1 << 0)
    public static let documentFrame = AnimatableContentObserverOptions(rawValue: 1 << 1)
    public static let ownFrame = AnimatableContentObserverOptions(rawValue: 1 << 2)
    public static let ownBounds = AnimatableContentObserverOptions(rawValue: 1 << 3)
}

private struct AnimatableContentRegistration {
    let name: Notification.Name
    weak var object: AnyObject?
}

private final class AnimatableContentNotificationTarget: NSObject {
    weak var target: AnyObject?
    var selector: Selector?

    @objc func forwardNotification(_ notification: NSNotification) {
        guard let target, let selector else {
            return
        }
        _ = target.perform(selector, with: notification)
    }
}

public final class AnimatableContentObserver {
    private weak var observedWindow: NSWindow?
    private weak var observedContentView: NSView?
    private weak var observedDocumentView: NSView?
    private weak var observedView: NSView?
    private lazy var notificationTarget = AnimatableContentNotificationTarget()
    private var observedOptions: AnimatableContentObserverOptions = []
    private var registrations: [AnimatableContentRegistration] = []
    private var registered = false

    public init() {
    }

    public func update(for view: NSView, target: AnyObject, selector: Selector, options: AnimatableContentObserverOptions = [.contentBounds, .documentFrame]) {
        guard view.window != nil else {
            unregister()
            return
        }
        let scrollView = view.enclosingScrollView
        self.update(for: view, target: target, selector: selector, contentView: scrollView?.contentView, documentView: scrollView?.documentView, options: options)
    }

    public func update(for view: NSView, target: AnyObject, selector: Selector, contentView: NSView?, documentView: NSView?, options: AnimatableContentObserverOptions) {
        guard let window = view.window else {
            unregister()
            return
        }
        if registered
            && observedWindow === window
            && observedContentView === contentView
            && observedDocumentView === documentView
            && observedView === view
            && notificationTarget.target === target
            && notificationTarget.selector == selector
            && observedOptions == options {
            return
        }
        unregister()
        notificationTarget.target = target
        notificationTarget.selector = selector

        let center = NotificationCenter.default
        func add(_ name: Notification.Name, _ object: AnyObject) {
            center.addObserver(notificationTarget, selector: #selector(AnimatableContentNotificationTarget.forwardNotification(_:)), name: name, object: object)
            registrations.append(AnimatableContentRegistration(name: name, object: object))
        }
        add(NSWindow.didBecomeKeyNotification, window)
        add(NSWindow.didResignKeyNotification, window)
        if options.contains(.contentBounds), let contentView {
            add(NSView.boundsDidChangeNotification, contentView)
        }
        if options.contains(.ownBounds) {
            add(NSView.boundsDidChangeNotification, view)
        }
        if options.contains(.documentFrame), let documentView {
            add(NSView.frameDidChangeNotification, documentView)
        }
        if options.contains(.ownFrame) {
            add(NSView.frameDidChangeNotification, view)
        }
        if (options.contains(.contentBounds) && contentView == nil) || (options.contains(.documentFrame) && documentView == nil) {
            add(NSWindow.didResizeNotification, window)
        }
        observedWindow = window
        observedContentView = contentView
        observedDocumentView = documentView
        observedView = view
        observedOptions = options
        registered = true
    }

    private func unregister() {
        guard registered else {
            return
        }
        let center = NotificationCenter.default
        if registrations.contains(where: { $0.object == nil }) {
            center.removeObserver(notificationTarget)
        } else {
            for registration in registrations {
                center.removeObserver(notificationTarget, name: registration.name, object: registration.object)
            }
        }
        registrations.removeAll()
        notificationTarget.target = nil
        notificationTarget.selector = nil
        observedWindow = nil
        observedContentView = nil
        observedDocumentView = nil
        observedView = nil
        observedOptions = []
        registered = false
    }

    deinit {
        unregister()
    }
}

public final class AnimatableContentTokenObserver {
    private weak var observedWindow: NSWindow?
    private weak var observedContentView: NSView?
    private weak var observedDocumentView: NSView?
    private var tokens: [NSObjectProtocol] = []
    private var handler: ((Notification) -> Void)?
    private var generation = 0

    public init() {
    }

    public func update(for view: NSView, handler: @escaping (Notification) -> Void) {
        guard let window = view.window else {
            removeObservers()
            return
        }
        let scrollView = view.enclosingScrollView
        let contentView = scrollView?.contentView
        let documentView = scrollView?.documentView
        if !tokens.isEmpty
            && observedWindow === window
            && observedContentView === contentView
            && observedDocumentView === documentView {
            self.handler = handler
            return
        }
        removeObservers()
        self.handler = handler
        let generation = self.generation
        let callback: (Notification) -> Void = { [weak self] notification in
            guard let self, self.generation == generation else {
                return
            }
            self.handler?(notification)
        }
        let center = NotificationCenter.default
        tokens.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main, using: callback))
        tokens.append(center.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main, using: callback))
        if let contentView {
            tokens.append(center.addObserver(forName: NSView.boundsDidChangeNotification, object: contentView, queue: .main, using: callback))
        }
        if let documentView {
            tokens.append(center.addObserver(forName: NSView.frameDidChangeNotification, object: documentView, queue: .main, using: callback))
        }
        if contentView == nil || documentView == nil {
            tokens.append(center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main, using: callback))
        }
        observedWindow = window
        observedContentView = contentView
        observedDocumentView = documentView
    }

    public func removeObservers() {
        generation &+= 1
        let center = NotificationCenter.default
        for token in tokens {
            center.removeObserver(token)
        }
        tokens.removeAll()
        handler = nil
        observedWindow = nil
        observedContentView = nil
        observedDocumentView = nil
    }

    deinit {
        removeObservers()
    }
}
