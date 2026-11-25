import Foundation
import WidgetEngineXPC

func installWidgetEngineService() {
    let serviceName = WidgetEngineXPC.embeddedServiceName() ?? "ru.keepcoder.Telegram.WidgetEngineService"
    WidgetEngineXPC.install(serviceName: serviceName)
}
