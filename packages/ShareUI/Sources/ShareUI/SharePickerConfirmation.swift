import AppAnalytics
import AlertsUI
import Dispatch
import SwiftSignalKit
import TGUIKit

func sharePickerConfirmation(context: AnalyticsContext, window: Window, header: String, information: String, ok: String) -> Signal<Bool, NoError> {
    return Signal { subscriber in
        let lifetime = context.beginPresentation()
        verifyAlert(for: window, header: header, information: information, ok: ok, successHandler: { _ in
            let delivery = context.beginPresentation()
            defer { delivery.end() }
            subscriber.putNext(true)
            subscriber.putCompletion()
        }, cancelHandler: {
            let delivery = context.beginPresentation()
            defer { delivery.end() }
            subscriber.putNext(false)
            subscriber.putCompletion()
        }, onDeinit: {
            DispatchQueue.main.async {
                withExtendedLifetime(lifetime) {
                    let delivery = context.beginPresentation()
                    defer { delivery.end() }
                    subscriber.putCompletion()
                }
            }
        })
        return EmptyDisposable
    } |> take(1)
}
