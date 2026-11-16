import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import AlertsUI
import InAppSettings
import ColorPalette
import FoundationUtils
import LocalAnimations
import Translate
import Postbox
import AppAnalytics

private final class Arguments {
    public let context: any AccountContextProtocol
    public let openPlatform: () -> Void
    public init(context: any AccountContextProtocol, openPlatform: @escaping () -> Void) {
        self.context = context
        self.openPlatform = openPlatform
    }
}

private struct State: Equatable {
    public var info: LocalizationInfo
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    let info = state.info
    let text: String
    if info.isOfficial {
        text = strings().applyLanguageChangeLanguageOfficialText(info.title)
    } else {
        let percent = Int(Float(info.translatedStringCount) / Float(info.totalStringCount) * 100.0)
        text = strings().applyLanguageChangeLanguageUnofficialText1(info.title, "\(percent)")
    }

    entries.append(.desc(
        sectionId: sectionId,
        index: index,
        text: .markdown(text, linkHandler: { _ in
            arguments.openPlatform()
        }),
        data: InputDataGeneralTextData(
            color: theme.colors.text,
            viewType: .textTopItem,
            centerViewAlignment: true,
            alignment: .center
        )
    ))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

public func LocalizationPreviewModalController(_ context: any AccountContextProtocol, info: LocalizationInfo) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let initialState = State(info: info)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)

    var close: (() -> Void)? = nil

    let arguments = Arguments(context: context, openPlatform: {
        LinkHooks.shared.openExternalLink(info.platformUrl, false)
    })

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().applyLanguageChangeLanguageTitle, hasDone: false)
    controller.analyticsScreen = .settingsLanguagePreview

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().applyLanguageApplyLanguageAction, accept: {
        close?()
        _ = showModalProgress(signal: context.engine.localization.downloadAndApplyLocalization(accountManager: context.sharedContext.accountManager, languageCode: info.languageCode), for: context.window).start()
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })

    close = { [weak modalController] in
        modalController?.modal?.close()
    }

    return modalController
}
