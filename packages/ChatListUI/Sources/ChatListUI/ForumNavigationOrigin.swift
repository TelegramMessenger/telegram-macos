import AppAnalytics
import ObjectiveC
import Postbox
import SwiftSignalKit
import TelegramContext
import TGUIKit

private var forumControllerOriginKey: UInt8 = 0

private final class ForumControllerOrigin {
    let context: AnalyticsContext
    let presentation: AnalyticsPresentation

    init(_ context: AnalyticsContext) {
        self.context = context
        self.presentation = context.beginPresentation()
    }
}

final class ForumNavigationOrigin {
    let context: AnalyticsContext?

    init(context: any AccountContextProtocol, peerId: PeerId, inherited: AnalyticsContext?) {
        self.context = inherited.map {
            Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: $0)
        }
    }

    func perform<T>(_ action: () -> T) -> T {
        let presentation = context?.beginPresentation()
        defer { presentation?.end() }
        return action()
    }

    func preserving<Value, Failure>(_ signal: Signal<Value, Failure>) -> Signal<Value, Failure> {
        return context?.preservingPresentation(signal) ?? signal
    }

    func bind(_ controller: ViewController) {
        guard let context else { return }
        if let chat = controller as? ChatListChatController {
            chat.inheritAnalyticsContext(context)
        } else {
            let previous = objc_getAssociatedObject(controller, &forumControllerOriginKey) as? ForumControllerOrigin
            let binding: ForumControllerOrigin
            if let previous, previous.context.isExcluded || !context.isExcluded {
                binding = ForumControllerOrigin(previous.context)
            } else {
                binding = ForumControllerOrigin(context)
            }
            objc_setAssociatedObject(controller, &forumControllerOriginKey, binding, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            controller.analyticsContext = binding.context
        }
    }
}
