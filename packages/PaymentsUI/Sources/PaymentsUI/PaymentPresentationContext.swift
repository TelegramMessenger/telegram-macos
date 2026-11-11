import AppAnalytics
import InputDataUI
import TGUIKit

func paymentChildController(analyticsContext: AnalyticsContext, create: () -> ModalViewController) -> ModalViewController {
    let lifetime = analyticsContext.beginPresentation()
    let controller = create()
    controller.analyticsContext = analyticsContext
    (controller as? InputDataModalController)?.current.analyticsContext = analyticsContext
    let onDeinit = controller.onDeinit
    controller.onDeinit = {
        onDeinit?()
        lifetime.end()
    }
    return controller
}
