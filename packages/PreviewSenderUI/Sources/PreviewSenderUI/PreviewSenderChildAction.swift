import AppAnalytics
import Dispatch

final class PreviewSenderChildAction {
    private let context: AnalyticsContext
    private let lifetime: AnalyticsPresentation
    private let isCurrent: () -> Bool
    private var resolved = false
    private var dismissalScheduled = false

    init(context: AnalyticsContext, isCurrent: @escaping () -> Bool) {
        self.context = context
        self.isCurrent = isCurrent
        self.lifetime = context.beginPresentation()
    }

    func resolve(_ action: () -> Void) {
        guard !resolved else { return }
        resolved = true
        let delivery = context.beginPresentation()
        defer { delivery.end() }
        guard isCurrent() else { return }
        action()
    }

    func dismissed() {
        guard !dismissalScheduled else { return }
        dismissalScheduled = true
        DispatchQueue.main.async {
            self.resolved = true
            self.lifetime.end()
        }
    }
}
