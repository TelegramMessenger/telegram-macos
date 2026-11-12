import Cocoa
import AppAnalytics
import InputView
import TGUIKit
import TelegramContext
import TelegramCore

public protocol InputInlineAvatarLayer: SimpleLayer {
}

public struct InputTextViewHooks {
    public let checkSendingAbility: (NSEvent) -> Bool
    public let showDateSelector: (any AccountContextProtocol, Window, Date, @escaping (Date) -> Void) -> Void
    public let showPremiumBoarding: (any AccountContextProtocol, Window) -> Void
    public let showTranslate: (any AccountContextProtocol, Window, String?, ChatTextInputState, @escaping (NSAttributedString) -> Void) -> Void
    public let showURLFormatter: (Window, String, String?, [String], @escaping (String, String?) -> Void) -> Void
    public let makeInlineAvatarLayer: (any AccountContextProtocol, NSRect, EnginePeer) -> any InputInlineAvatarLayer

    public var showTranslateWithContext: ((any AccountContextProtocol, Window, String?, ChatTextInputState, AnalyticsContext, @escaping (NSAttributedString) -> Void) -> Void)?
    public var showPremiumBoardingWithContext: ((any AccountContextProtocol, Window, AnalyticsContext) -> Void)?

    public func showTranslateObserved(_ context: any AccountContextProtocol, _ window: Window, _ from: String?, _ draft: ChatTextInputState, analyticsContext: AnalyticsContext, onUse: @escaping (NSAttributedString) -> Void) {
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        let completion: (NSAttributedString) -> Void = { translated in
            let currentOrigin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: origin)
            let presentation = currentOrigin.beginPresentation()
            defer { presentation.end() }
            onUse(currentOrigin.isExcluded || currentOrigin.scope?.isValid != true ? chatInputTextExcludingAnalytics(translated) : translated)
        }
        if let showTranslateWithContext {
            showTranslateWithContext(context, window, from, draft, origin, completion)
        } else {
            showTranslate(context, window, from, draft, completion)
        }
    }

    public func showPremiumBoardingObserved(_ context: any AccountContextProtocol, _ window: Window, analyticsContext: AnalyticsContext) {
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        if let showPremiumBoardingWithContext {
            showPremiumBoardingWithContext(context, window, origin)
        } else {
            showPremiumBoarding(context, window)
        }
    }

    public init(checkSendingAbility: @escaping (NSEvent) -> Bool,
                showDateSelector: @escaping (any AccountContextProtocol, Window, Date, @escaping (Date) -> Void) -> Void,
                showPremiumBoarding: @escaping (any AccountContextProtocol, Window) -> Void,
                showTranslate: @escaping (any AccountContextProtocol, Window, String?, ChatTextInputState, @escaping (NSAttributedString) -> Void) -> Void,
                showURLFormatter: @escaping (Window, String, String?, [String], @escaping (String, String?) -> Void) -> Void,
                makeInlineAvatarLayer: @escaping (any AccountContextProtocol, NSRect, EnginePeer) -> any InputInlineAvatarLayer) {
        self.checkSendingAbility = checkSendingAbility
        self.showDateSelector = showDateSelector
        self.showPremiumBoarding = showPremiumBoarding
        self.showTranslate = showTranslate
        self.showURLFormatter = showURLFormatter
        self.makeInlineAvatarLayer = makeInlineAvatarLayer
    }

    private static var installed: InputTextViewHooks?

    public static var shared: InputTextViewHooks {
        guard let hooks = installed else {
            fatalError("InputTextViewHooks.install must be called before the input view is used")
        }
        return hooks
    }

    public static func install(_ hooks: InputTextViewHooks) {
        installed = hooks
    }
}
