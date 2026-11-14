import Cocoa

public struct DeveloperHooks {
    public let updateGraphicContext: () -> Void

    public init(updateGraphicContext: @escaping () -> Void) {
        self.updateGraphicContext = updateGraphicContext
    }

    private static var _shared: DeveloperHooks?

    public static var isInstalled: Bool {
        return _shared != nil
    }

    public static var shared: DeveloperHooks {
        if let value = _shared {
            return value
        }
        assertionFailure("DeveloperHooks.install must be called before the developer screen is used")
        return .placeholder
    }

    public static func install(_ hooks: DeveloperHooks) {
        assert(Thread.isMainThread, "DeveloperHooks.install must be called on the main thread")
        _shared = hooks
    }

    public static let placeholder = DeveloperHooks(
        updateGraphicContext: { }
    )
}
