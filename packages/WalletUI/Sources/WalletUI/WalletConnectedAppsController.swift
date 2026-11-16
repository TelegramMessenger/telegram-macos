import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import InputDataUI
import Localization
import Cocoa
import TGUIKit
import SwiftSignalKit
import WalletContext
import AppAnalytics

@available(macOS 10.15, *)
func walletConnectedAppSessions(_ sessions: [WalletContext.TonConnectSession]) -> [WalletContext.TonConnectSession] {
    return sessions.filter { $0.manifest != nil && $0.status == .connected }
}

@available(macOS 10.15, *)
private struct WalletConnectedAppsState: Equatable {
    var sessions: [WalletContext.TonConnectSession] = []
    var icons: [String: Data] = [:]
    var isDisconnecting = false

    var apps: [WalletContext.TonConnectSession] {
        return walletConnectedAppSessions(sessions)
    }
}

private final class WalletConnectedAppsArguments {
    let openApp: (Int64) -> Void
    let disconnectAll: () -> Void

    init(openApp: @escaping (Int64) -> Void, disconnectAll: @escaping () -> Void) {
        self.openApp = openApp
        self.disconnectAll = disconnectAll
    }
}

private let _id_disconnect_all = InputDataIdentifier("_id_disconnect_all")
private func _id_app(_ id: Int64) -> InputDataIdentifier {
    return InputDataIdentifier("_id_app_\(id)")
}

@available(macOS 10.15, *)
private func walletConnectedAppsEntries(_ state: WalletConnectedAppsState, arguments: WalletConnectedAppsArguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    let apps = state.apps
    let header = strings().walletConnectedAppsControllerActiveConnections
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(header), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    let hasDisconnectAll = apps.count > 1
    if hasDisconnectAll {
        let disconnectAllTitle = strings().walletConnectedAppsControllerDisconnectAllApps
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_disconnect_all, equatable: nil, comparable: nil, item: { initialSize, stableId in
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: disconnectAllTitle, nameStyle: ControlStyle(font: .normal(.title), foregroundColor: theme.colors.redUI), type: .none, viewType: .firstItem, action: {
                arguments.disconnectAll()
            }, thumb: NSImage(named: "Wallet_DisconnectAll").map { GeneralThumbAdditional(thumb: $0.precomposed(theme.colors.redUI, flipVertical: true), textInset: 40, thumbInset: 0) })
        }))
        index += 1
    }

    struct AppTuple: Equatable {
        let id: Int64
        let name: String
        let domain: String
        let icon: Data?
        let viewType: GeneralViewType
    }
    for (position, session) in apps.enumerated() {
        guard let manifest = session.manifest else {
            continue
        }
        let isFirst = position == 0 && !hasDisconnectAll
        let isLast = position == apps.count - 1
        let viewType: GeneralViewType
        if isFirst && isLast {
            viewType = .singleItem
        } else if isFirst {
            viewType = .firstItem
        } else if isLast {
            viewType = .lastItem
        } else {
            viewType = .innerItem
        }
        let tuple = AppTuple(id: session.id, name: manifest.name, domain: manifest.domain, icon: manifest.icon.flatMap { state.icons[$0.url] }, viewType: viewType)
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_app(session.id), equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
            let icon = walletAppIconImage(data: tuple.icon, applicationName: tuple.name, size: 30, cornerRadius: 9).map { NSImage(cgImage: $0, size: $0.backingSize).precomposed(flipVertical: true) }
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: tuple.name, nameStyle: ControlStyle(font: .medium(.title), foregroundColor: theme.colors.text), description: tuple.domain, type: .next, viewType: tuple.viewType, action: {
                arguments.openApp(tuple.id)
            }, thumb: icon.map { GeneralThumbAdditional(thumb: $0, textInset: 40, thumbInset: 0) })
        }))
        index += 1
    }

    let footer = strings().walletConnectedAppsControllerFooter
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(footer), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

@available(macOS 10.15, *)
public func WalletConnectedAppsController(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext) -> InputDataModalController {
    let actionsDisposable = DisposableSet()
    let operationDisposable = MetaDisposable()
    actionsDisposable.add(operationDisposable)
    let iconDisposables = DisposableDict<String>()
    actionsDisposable.add(iconDisposables)

    let initialState = WalletConnectedAppsState(sessions: [])
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((WalletConnectedAppsState) -> WalletConnectedAppsState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var getController: (() -> ViewController?)?
    var close: (() -> Void)?
    var isFinishing = false
    var hasReceivedSessions = false
    var pendingToast: String?
    var operationSessionIds = Set<Int64>()
    var operationToast: String?
    var operationCompletion: ((Bool) -> Void)?
    weak var infoController: InputDataModalController?
    var infoSessionId: Int64?
    var closeInfo: (() -> Void)?

    var window: Window {
        walletUIWindow(context, getController?())
    }

    let requestIcons: ([WalletContext.TonConnectSession]) -> Void = { sessions in
        for session in walletConnectedAppSessions(sessions) {
            guard let icon = session.manifest?.icon, stateValue.with({ $0.icons[icon.url] == nil }) else {
                continue
            }
            iconDisposables.set((walletFetchAppIcon(context: context, icon: icon) |> deliverOnMainQueue).start(next: { data in
                guard let data else {
                    return
                }
                updateState { current in
                    var current = current
                    current.icons[icon.url] = data
                    return current
                }
            }), forKey: icon.url)
        }
    }

    let finish: (String?) -> Void = { toast in
        guard !isFinishing else {
            return
        }
        isFinishing = true
        let targetWindow = context.window
        closeInfo?()
        close?()
        if let toast {
            delay(0.3, closure: {
                environment.showModalText(for: targetWindow, text: toast)
            })
        }
    }

    let reconcile: () -> Void = {
        guard !stateValue.with({ $0.isDisconnecting }), hasReceivedSessions, !isFinishing else {
            return
        }
        let apps = stateValue.with { $0.apps }
        if let infoSessionId, infoController != nil {
            if !apps.contains(where: { $0.id == infoSessionId }) {
                closeInfo?()
            }
            return
        }
        if apps.isEmpty {
            let toast = pendingToast
            pendingToast = nil
            finish(toast)
        } else if let toast = pendingToast {
            pendingToast = nil
            environment.showModalText(for: window, text: toast)
        }
    }

    let completeDisconnect: (Bool) -> Void = { succeeded in
        let completion = operationCompletion
        operationCompletion = nil
        operationSessionIds.removeAll()
        if succeeded {
            pendingToast = operationToast
        }
        operationToast = nil
        updateState { current in
            var current = current
            current.isDisconnecting = false
            return current
        }
        completion?(succeeded)
        Queue.mainQueue().justDispatch {
            reconcile()
        }
    }

    let completeAcceptedDisconnect: ([WalletContext.TonConnectSession]) -> Bool = { sessions in
        guard stateValue.with({ $0.isDisconnecting }) else {
            return false
        }
        let accepted = operationSessionIds.allSatisfy { id in
            !sessions.contains(where: { $0.id == id })
        }
        if accepted {
            completeDisconnect(true)
        }
        return accepted
    }

    let presentDisconnectError: (Bool) -> Void = { all in
        let text = all ? strings().walletConnectedAppsControllerDisconnectAllFailed : strings().walletConnectedAppsControllerDisconnectFailed
        environment.alert(for: window, info: text)
    }

    let disconnect: (Set<Int64>, Bool, String, @escaping (Bool) -> Void) -> Void = { ids, all, toast, completion in
        guard !stateValue.with({ $0.isDisconnecting }), !ids.isEmpty, !isFinishing else {
            completion(false)
            return
        }
        operationSessionIds = ids
        operationToast = toast
        operationCompletion = completion
        updateState { current in
            var current = current
            current.isDisconnecting = true
            return current
        }
        let operation: Signal<Void, NoError>
        if all {
            operation = walletContext.disconnectAllTonConnectSessions()
        } else if let id = ids.first {
            operation = walletContext.disconnectTonConnectSession(id: id)
        } else {
            completeDisconnect(false)
            return
        }
        operationDisposable.set((operation
        |> mapToSignal { walletContext.tonConnectState |> take(1) }
        |> deliverOnMainQueue).start(next: { tonConnectState in
            guard stateValue.with({ $0.isDisconnecting }) else {
                return
            }
            updateState { current in
                var current = current
                current.sessions = tonConnectState.sessions
                return current
            }
            guard stateValue.with({ $0.isDisconnecting }) else {
                return
            }
            if !completeAcceptedDisconnect(tonConnectState.sessions) {
                completeDisconnect(false)
                presentDisconnectError(all)
            }
        }))
    }

    let openApp: (Int64) -> Void = { sessionId in
        guard !stateValue.with({ $0.isDisconnecting }), infoController == nil, !isFinishing,
              let session = stateValue.with({ $0.apps }).first(where: { $0.id == sessionId }),
              let manifest = session.manifest else {
            return
        }
        let iconData = manifest.icon.flatMap { icon in stateValue.with { $0.icons[icon.url] } }
        let controller = WalletConnectedAppInfoController(context: context, environment: environment, manifest: manifest, iconData: iconData, disconnect: { completion in
            disconnect([session.id], false, strings().walletConnectedAppsControllerAppDisconnected(manifest.name), completion)
        }, closed: {
            infoController = nil
            infoSessionId = nil
            Queue.mainQueue().justDispatch {
                reconcile()
            }
        })
        infoController = controller
        infoSessionId = session.id
        closeInfo = { [weak controller] in
            controller?.close()
        }
        showModal(with: controller, for: window)
    }

    let disconnectAll: () -> Void = {
        guard !stateValue.with({ $0.isDisconnecting }), infoController == nil, !isFinishing, stateValue.with({ $0.apps.count > 1 }) else {
            return
        }
        let targetWindow = window
        environment.verifyAlert(for: targetWindow, header: strings().walletConnectedAppsControllerDisconnectAllConfirmTitle, information: strings().walletConnectedAppsControllerDisconnectAllConfirmInfo, ok: strings().walletConnectedAppsControllerDisconnectAll, cancel: strings().walletConnectedAppsControllerCancel, successHandler: { _ in
            let ids = Set(stateValue.with { $0.apps }.map(\.id))
            disconnect(ids, true, strings().walletConnectedAppsControllerAllAppsDisconnected, { _ in })
        })
    }

    let arguments = WalletConnectedAppsArguments(openApp: openApp, disconnectAll: disconnectAll)

    let signal = statePromise.get()
    |> deliverOnPrepareQueue
    |> map { state in
        InputDataSignalValue(entries: walletConnectedAppsEntries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().walletConnectedAppsControllerTitle, hasDone: false)
    controller.analyticsScreen = .walletConnectedApps
    getController = { [weak controller] in
        controller
    }
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    actionsDisposable.add((walletContext.tonConnectState
    |> deliverOnMainQueue).start(next: { tonConnectState in
        hasReceivedSessions = true
        updateState { current in
            var current = current
            current.sessions = tonConnectState.sessions
            return current
        }
        requestIcons(tonConnectState.sessions)
        _ = completeAcceptedDisconnect(tonConnectState.sessions)
        Queue.mainQueue().justDispatch {
            reconcile()
        }
    }))

    let modalController = WalletModalController(controller, closeHandler: { close in
        guard !stateValue.with({ $0.isDisconnecting }) else {
            return
        }
        close()
    }, size: NSMakeSize(360, 0))
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    close = { [weak modalController] in
        modalController?.close()
    }
    return modalController
}

private let _id_app_header = InputDataIdentifier("_id_app_header")
private let _id_app_domain = InputDataIdentifier("_id_app_domain")

@available(macOS 10.15, *)
private func walletConnectedAppInfoEntries(manifest: TonConnectManifestInfo, iconData: Data?, environment: WalletUIEnvironment) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    let description = strings().walletConnectedAppsControllerAppInfoDescription
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_app_header, equatable: .init(iconData), comparable: nil, item: { initialSize, stableId in
        let title = NSMutableAttributedString()
        title.append(string: manifest.name, color: theme.colors.text, font: .medium(18))
        let info = NSMutableAttributedString()
        info.append(string: description, color: theme.colors.text, font: .normal(.text))
        return environment.makeAnimatedHeader(initialSize, stableId: stableId, sticker: nil, text: title, infoText: info, stickerSize: NSMakeSize(88, 88), image: walletAppIconImage(data: iconData, applicationName: manifest.name, size: 88, cornerRadius: 44), viewType: .singleItem)
    }))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1

    let domainText = "[\(manifest.domain)](\(manifest.url))"
    entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(domainText, linkHandler: { _ in
        environment.openExternalURL(manifest.url)
    }), data: .init(color: walletClassicAccent, detectBold: false, viewType: .textBottomItem, fontSize: .title, inset: .init(left: 20, right: 20), centerViewAlignment: true, alignment: .center, linkColor: walletClassicAccent)))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1

    return entries
}

@available(macOS 10.15, *)
func WalletConnectedAppInfoController(context: any AccountContextProtocol, environment: WalletUIEnvironment, manifest: TonConnectManifestInfo, iconData: Data?, disconnect: @escaping (@escaping (Bool) -> Void) -> Void, closed: @escaping () -> Void) -> InputDataModalController {
    let iconPromise = ValuePromise<Data?>(iconData, ignoreRepeated: true)
    let iconDisposable = MetaDisposable()
    var isDisconnecting = false
    var isFinishing = false
    var close: (() -> Void)?

    if iconData == nil {
        iconDisposable.set((walletFetchAppIcon(context: context, icon: manifest.icon) |> deliverOnMainQueue).start(next: { data in
            iconPromise.set(data)
        }))
    }

    let signal = iconPromise.get()
    |> deliverOnPrepareQueue
    |> map { iconData in
        InputDataSignalValue(entries: walletConnectedAppInfoEntries(manifest: manifest, iconData: iconData, environment: environment))
    }

    let controller = InputDataController(dataSignal: signal, title: "", hasDone: false, getBackgroundColor: {
        theme.colors.background
    })
    controller.analyticsScreen = .walletConnectedApp
    controller.onDeinit = {
        iconDisposable.dispose()
        closed()
    }

    var updateButton: (() -> Void)?

    let performDisconnect: () -> Void = {
        guard !isDisconnecting, !isFinishing else {
            return
        }
        isDisconnecting = true
        updateButton?()
        disconnect { succeeded in
            isDisconnecting = false
            updateButton?()
            if succeeded {
                isFinishing = true
                close?()
            }
        }
    }

    controller.validateData = { _ in
        performDisconnect()
        return .none
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().walletConnectedAppsControllerDisconnect, accept: {
        performDisconnect()
    }, singleButton: true, customTheme: { walletModalTheme })

    let modalController = WalletModalController(controller, modalInteractions: modalInteractions, closeHandler: { close in
        guard !isDisconnecting else {
            return
        }
        close()
    }, size: NSMakeSize(360, 0))

    updateButton = { [weak modalInteractions] in
        modalInteractions?.updateDone { button in
            button.isEnabled = !isDisconnecting
            button.set(text: isDisconnecting ? strings().walletConnectedAppsControllerDisconnecting : strings().walletConnectedAppsControllerDisconnect, for: .Normal)
            button.set(background: theme.colors.redUI, for: .Normal)
        }
    }
    controller.afterTransaction = { _ in
        updateButton?()
    }

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    close = { [weak modalController] in
        modalController?.close()
    }
    return modalController
}
