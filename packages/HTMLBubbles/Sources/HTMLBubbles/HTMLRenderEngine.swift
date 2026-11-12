import Foundation
import Localization

public enum HTMLRenderEngine: CaseIterable {
    case litehtmlBefore
    case litehtml
    case litehtmlGPU
    case twidget
    case webKit

    public var usesWidgetSandbox: Bool {
        return self == .twidget || self == .webKit
    }

    var title: String {
        switch self {
        case .litehtmlBefore:
            return strings().htmlRenderEngineLitehtml
        case .litehtml:
            return strings().htmlRenderEngineLitehtmlOptimized
        case .litehtmlGPU:
            return strings().htmlRenderEngineLitehtmlGPU
        case .twidget:
            return strings().htmlRenderEngineTwidget
        case .webKit:
            return strings().htmlRenderEngineWebKit
        }
    }

    var chatId: String {
        switch self {
        case .litehtmlBefore:
            return "html-bot-litehtml"
        case .litehtml:
            return HTMLDemoCatalog.botChatId
        case .litehtmlGPU:
            return "html-bot-litehtml-gpu"
        case .twidget:
            return "html-bot-twidget"
        case .webKit:
            return "html-bot-webkit"
        }
    }
}
