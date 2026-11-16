import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import InputDataUI
import Localization
import Postbox
import TelegramCore
import Cocoa
import TGUIKit
import SwiftSignalKit
import WalletContext
import PasscodeCore
import AppAnalytics

private final class Arguments {
    let createWallet: () -> Void
    let importWallet: () -> Void

    init(createWallet: @escaping () -> Void, importWallet: @escaping () -> Void) {
        self.createWallet = createWallet
        self.importWallet = importWallet
    }
}

private struct State: Equatable {
    var isCreating: Bool = false
}

private let _id_create = InputDataIdentifier("_id_create")
private let _id_import = InputDataIdentifier("_id_import")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().walletReplaceControllerHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_create, data: .init(name: strings().walletReplaceControllerCreateNew, color: walletClassicAccent, type: state.isCreating ? .loading : .none, viewType: .firstItem, enabled: !state.isCreating, action: arguments.createWallet)))
    index += 1
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_import, data: .init(name: strings().walletReplaceControllerImportExisting, color: walletClassicAccent, type: .none, viewType: .lastItem, enabled: !state.isCreating, action: arguments.importWallet)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

@available(macOS 10.15, *)
public func WalletReplaceController(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext) -> InputDataModalController {
    let actionsDisposable = DisposableSet()
    let replaceDisposable = MetaDisposable()
    actionsDisposable.add(replaceDisposable)
    let creationWatchDisposable = MetaDisposable()
    actionsDisposable.add(creationWatchDisposable)
    let createFlow = WalletFlowAuthorization(walletContext: walletContext, reason: walletConfirmAccessFlowReason)

    let initialState = State()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var getController: (() -> ViewController?)?
    var close: (() -> Void)?

    var window: Window {
        walletUIWindow(context, getController?())
    }

    let completeReplacement: (String, String, Window) -> Void = { toastTitle, toastText, targetWindow in
        _ = (ApplicationSpecificNotice.resetWalletGramTooltip(accountManager: context.sharedContext.accountManager)
        |> deliverOnMainQueue).startStandalone(next: {
            closeAllModals(window: targetWindow)
            environment.showModalText(for: targetWindow, text: toastText, title: toastTitle)
            showWallet(context: context, environment: environment, walletContext: walletContext, for: targetWindow)
        })
    }

    let arguments = Arguments(createWallet: {
        guard !stateValue.with({ $0.isCreating }), walletContext.stateValue.activeOperation == nil else {
            return
        }
        let targetWindow = window
        updateState { current in
            var current = current
            current.isCreating = true
            return current
        }
        let createdWallet = Atomic<WalletContext.WalletInfo?>(value: nil)
        let finishOnce = Atomic<Bool>(value: false)
        let finishCreation: () -> Void = {
            guard !finishOnce.swap(true) else { return }
            createFlow.end()
            completeReplacement(strings().walletReplaceControllerCreatedTitle, strings().walletReplaceControllerCreatedInfo, targetWindow)
        }
        creationWatchDisposable.set((walletContext.state
        |> filter { state in
            guard let created = createdWallet.with({ $0 }), state.activeOperation == nil else { return false }
            guard case let .wallet(info) = state.phase else { return false }
            return info.address == created.address && info.publicKey == created.publicKey && info.canSign
        }
        |> take(1)
        |> deliverOnMainQueue).start(next: { _ in
            finishCreation()
        }))
        replaceDisposable.set(performWalletAuthorizedOperation(context: context, environment: environment, window: targetWindow, showsProgress: false, operation: { password in
            let creation: Signal<WalletContext.WalletInfo, WalletContext.WalletError>
            if let created = createdWallet.with({ $0 }) {
                creation = .single(created)
            } else {
                creation = createFlow.authorize()
                |> mapToSignal { session in
                    walletContext.createWallet(password: password, session: session)
                }
            }
            return creation
            |> deliverOnMainQueue
            |> mapToSignal { created -> Signal<WalletContext.WalletInfo, WalletContext.WalletError> in
                _ = createdWallet.swap(created)
                return createFlow.authorize()
                |> mapToSignal { session in
                    walletContext.completeWalletCreation(created, password: password, session: session)
                }
            }
        }, next: { _ in
            finishCreation()
        }, failed: { error in
            guard !finishOnce.with({ $0 }) else { return }
            creationWatchDisposable.set(nil)
            if error == .authorizationCancelled {
                createFlow.end()
            }
            updateState { current in
                var current = current
                current.isCreating = false
                return current
            }
            presentWalletAuthorizationError(environment: environment, error, window: targetWindow, fallbackTitle: strings().walletReplaceControllerReplaceFailedTitle, fallbackText: strings().walletReplaceControllerCheckConnection)
        }))
    }, importWallet: {
        guard !stateValue.with({ $0.isCreating }) else {
            return
        }
        let targetWindow = window
        close?()
        showModal(with: WalletImportController(context: context, environment: environment, walletContext: walletContext, onImported: {
            completeReplacement(strings().walletReplaceControllerImportedTitle, strings().walletReplaceControllerImportedInfo, targetWindow)
        }), for: targetWindow)
    })

    let signal = statePromise.get()
    |> deliverOnPrepareQueue
    |> map { state in
        InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().walletReplaceControllerTitle, hasDone: false)
    controller.analyticsScreen = .walletReplace
    getController = { [weak controller] in
        controller
    }
    controller.onDeinit = {
        createFlow.end()
        actionsDisposable.dispose()
    }

    let modalController = WalletModalController(controller, size: NSMakeSize(360, 0))
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    close = { [weak modalController] in
        modalController?.close()
    }
    return modalController
}
