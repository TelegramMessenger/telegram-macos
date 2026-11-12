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
import AppAnalytics

@available(macOS 10.15, *)
public func walletAuthorizationErrorMessage(_ error: WalletContext.WalletError) -> (title: String, text: String)? {
    switch error {
    case .recoveryPhraseOutdated:
        return (strings().walletAuthorizedOperationPhraseChangedTitle, strings().walletAuthorizedOperationPhraseChangedInfo)
    case .twoStepAuthMissing:
        return (strings().walletAuthorizedOperationTwoStepRequiredTitle, strings().walletAuthorizedOperationTwoStepRequiredInfo)
    case let .passwordTooFresh(timeout):
        return (strings().walletAuthorizedOperationPasswordTooNewTitle, strings().walletAuthorizedOperationPasswordTooNewInfo(timeIntervalString(Int(timeout))))
    case let .sessionTooFresh(timeout):
        return (strings().walletAuthorizedOperationSessionTooNewTitle, strings().walletAuthorizedOperationSessionTooNewInfo(timeIntervalString(Int(timeout))))
    case .backupDisabled:
        return (strings().walletAuthorizedOperationBackupDisabledTitle, strings().walletAuthorizedOperationBackupDisabledInfo)
    case .backupNotAvailable:
        return (strings().walletAuthorizedOperationBackupUnavailableTitle, strings().walletAuthorizedOperationBackupUnavailableInfo)
    case .keyRotationFailed:
        return (strings().walletAuthorizedOperationKeyRotationFailedTitle, strings().walletAuthorizedOperationKeyRotationFailedInfo)
    case .proofInvalid:
        return (strings().walletAuthorizedOperationProofInvalidTitle, strings().walletAuthorizedOperationProofInvalidInfo)
    case .proofExpired:
        return (strings().walletAuthorizedOperationProofExpiredTitle, strings().walletAuthorizedOperationProofExpiredInfo)
    case .rotationNotFound:
        return (strings().walletAuthorizedOperationRotationPendingTitle, strings().walletAuthorizedOperationRotationPendingInfo)
    case .commentTooLong:
        return (strings().walletAuthorizedOperationCommentTooLongTitle, strings().walletAuthorizedOperationCommentTooLongInfo)
    case .commentEncryptionRecipientUnavailable:
        return (strings().walletAuthorizedOperationEncryptFailedTitle, strings().walletAuthorizedOperationEncryptRecipientUnavailableInfo)
    case .commentEncryptionFailed:
        return (strings().walletAuthorizedOperationEncryptFailedTitle, strings().walletAuthorizedOperationEncryptFailedInfo)
    case .commentDecryptionFailed:
        return (strings().walletAuthorizedOperationDecryptFailedTitle, strings().walletAuthorizedOperationDecryptFailedInfo)
    case .walletKeyMismatch:
        return (strings().walletAuthorizedOperationWalletKeyChangedTitle, strings().walletAuthorizedOperationWalletKeyChangedInfo)
    default:
        return nil
    }
}

@available(macOS 10.15, *)
public func presentWalletAuthorizationError(environment: WalletUIEnvironment, _ error: WalletContext.WalletError, window: Window, fallbackTitle: String, fallbackText: String) {
    guard error != .authorizationCancelled else {
        return
    }
    let message = walletAuthorizationErrorMessage(error) ?? (title: fallbackTitle, text: fallbackText)
    environment.alert(for: window, header: message.title, info: message.text)
}

@available(macOS 10.15, *)
func walletBackupEnableErrorMessage(_ error: WalletContext.WalletError) -> (title: String, text: String) {
    switch error {
    case .walletKeyMismatch, .recoveryPhraseOutdated, .storage(.identityMismatch), .proofInvalid:
        return (strings().walletAuthorizedOperationBackupVerifyFailedTitle, strings().walletAuthorizedOperationBackupVerifyFailedInfo)
    case .rotationNotFound:
        return (strings().walletAuthorizedOperationRotationPendingTitle, strings().walletAuthorizedOperationBackupRotationPendingInfo)
    case .proofExpired:
        return (strings().walletAuthorizedOperationProofExpiredTitle, strings().walletAuthorizedOperationBackupProofExpiredInfo)
    case .invalidMnemonic:
        return (strings().walletAuthorizedOperationInvalidPhraseTitle, strings().walletAuthorizedOperationInvalidPhraseInfo)
    case .unavailable:
        return (strings().walletAuthorizedOperationWalletChangedTitle, strings().walletAuthorizedOperationWalletChangedInfo)
    default:
        return walletAuthorizationErrorMessage(error) ?? (strings().walletAuthorizedOperationEnableBackupFailedTitle, strings().walletAuthorizedOperationCheckNetworkInfo)
    }
}

@available(macOS 10.15, *)
func presentWalletBackupEnableError(environment: WalletUIEnvironment, _ error: WalletContext.WalletError, window: Window, retry: @escaping () -> Void, enterSecretPhrase: @escaping () -> Void) {
    guard error != .authorizationCancelled else {
        return
    }
    let message = walletBackupEnableErrorMessage(error)
    switch error {
    case .walletKeyMismatch, .storage(.identityMismatch), .proofInvalid, .invalidMnemonic, .rotationNotFound:
        environment.verifyAlert(for: window, header: message.title, information: message.text, ok: strings().walletAuthorizedOperationEnterCurrentPhrase, cancel: strings().walletAuthorizedOperationCancel, successHandler: { _ in
            enterSecretPhrase()
        })
    case .proofExpired, .network:
        environment.verifyAlert(for: window, header: message.title, information: message.text, ok: strings().walletAuthorizedOperationRetry, cancel: strings().walletAuthorizedOperationCancel, successHandler: { _ in
            retry()
        })
    default:
        environment.alert(for: window, header: message.title, info: message.text)
    }
}

private let _id_wallet_password = InputDataIdentifier("_id_wallet_password")

private struct WalletPasswordPromptState: Equatable {
    let value: InputDataValue
    let error: InputDataValueError?
    let isLoading: Bool

    init(value: InputDataValue, error: InputDataValueError?, isLoading: Bool) {
        self.value = value
        self.error = error
        self.isLoading = isLoading
    }

    func withUpdatedValue(_ value: InputDataValue) -> WalletPasswordPromptState {
        return WalletPasswordPromptState(value: value, error: self.error, isLoading: self.isLoading)
    }
    func withUpdatedError(_ error: InputDataValueError?) -> WalletPasswordPromptState {
        return WalletPasswordPromptState(value: self.value, error: error, isLoading: self.isLoading)
    }
    func withUpdatedLoading(_ isLoading: Bool) -> WalletPasswordPromptState {
        return WalletPasswordPromptState(value: self.value, error: self.error, isLoading: isLoading)
    }
}

private func walletPasswordPromptEntries(state: WalletPasswordPromptState) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    entries.append(.input(sectionId: sectionId, index: index, value: state.value, error: state.error, identifier: _id_wallet_password, mode: .secure, data: InputDataRowData(viewType: .singleItem), placeholder: nil, inputPlaceholder: strings().walletAuthorizedOperationPasswordPlaceholder, filter: { $0 }, limit: 255))
    index += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().walletAuthorizedOperationPasswordInfo), data: InputDataGeneralTextData(detectBold: false, viewType: .textBottomItem)))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1

    return entries
}

final class WalletAuthorizedOperationHandle {
    let operationDisposable = MetaDisposable()
    var finished: Bool = false
    var dismissPrompt: (() -> Void)?

    func dispose(enqueue: (@escaping () -> Void) -> Void) {
        operationDisposable.dispose()
        enqueue {
            self.finished = true
            self.dismissPrompt?()
            self.dismissPrompt = nil
        }
    }
}

@available(macOS 10.15, *)
private func walletPasswordPromptController<Value>(
    environment: WalletUIEnvironment,
    window: Window,
    handle: WalletAuthorizedOperationHandle,
    operation: @escaping (String?) -> Signal<Value, WalletContext.WalletError>,
    next: @escaping (Value) -> Void,
    failed: @escaping (WalletContext.WalletError) -> Void,
    passwordRemoved: @escaping () -> Void
) -> InputDataModalController {
    let initialState = WalletPasswordPromptState(value: .string(nil), error: nil, isLoading: false)
    let stateValue = Atomic(value: initialState)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let updateState: ((WalletPasswordPromptState) -> WalletPasswordPromptState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    let dataSignal = statePromise.get() |> map { state in
        return InputDataSignalValue(entries: walletPasswordPromptEntries(state: state))
    }

    var dismiss: (() -> Void)?

    let controller = InputDataController(dataSignal: dataSignal, title: strings().walletAuthorizedOperationPasswordTitle, validateData: { data in
        return .fail(.doSomething { f in
            guard !stateValue.with({ $0.isLoading }) else {
                return
            }
            guard let password = data[_id_wallet_password]?.stringValue, !password.isEmpty else {
                f(.fail(.fields([_id_wallet_password : .shake])))
                return
            }
            updateState {
                $0.withUpdatedLoading(true).withUpdatedError(nil)
            }
            handle.operationDisposable.set((walletModalProgress(signal: operation(password), for: window)
            |> deliverOnMainQueue).start(next: { value in
                updateState {
                    $0.withUpdatedLoading(false)
                }
                handle.finished = true
                dismiss?()
                next(value)
            }, error: { error in
                switch error {
                case .requestPassword, .invalidPassword:
                    updateState {
                        $0.withUpdatedLoading(false).withUpdatedError(InputDataValueError(description: strings().walletAuthorizedOperationInvalidPassword, target: .data))
                    }
                    f(.fail(.fields([_id_wallet_password : .shake])))
                case .twoStepAuthMissing:
                    updateState {
                        $0.withUpdatedLoading(false)
                    }
                    handle.finished = true
                    dismiss?()
                    passwordRemoved()
                default:
                    updateState {
                        $0.withUpdatedLoading(false)
                    }
                    handle.finished = true
                    dismiss?()
                    failed(error)
                }
            }))
        })
    }, updateDatas: { data in
        updateState {
            $0.withUpdatedValue(data[_id_wallet_password] ?? .string(nil)).withUpdatedError(nil)
        }
        return .fail(.none)
    }, afterDisappear: {
        if !handle.finished {
            handle.finished = true
            failed(.authorizationCancelled)
        }
    }, hasDone: true)
    controller.analyticsScreen = .walletPassword

    controller.autoInputAction = true

    let interactions = ModalInteractions(acceptTitle: strings().walletAuthorizedOperationContinue, accept: { [weak controller] in
        controller?.validateInputValues()
    }, singleButton: true, customTheme: { walletModalTheme })

    let modalController = WalletModalController(controller, modalInteractions: interactions, size: NSMakeSize(300, 300))
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    dismiss = { [weak modalController] in
        modalController?.close()
    }
    return modalController
}

@discardableResult
@available(macOS 10.15, *)
public func performWalletAuthorizedOperation<Value>(
    context: any AccountContextProtocol, environment: WalletUIEnvironment,
    window: Window,
    showsProgress: Bool = true,
    operation: @escaping (String?) -> Signal<Value, WalletContext.WalletError>,
    next: @escaping (Value) -> Void,
    failed: @escaping (WalletContext.WalletError) -> Void
) -> Disposable {
    let handle = WalletAuthorizedOperationHandle()
    var retryState = WalletPasswordRetryState()
    var runWithoutPassword: (() -> Void)?

    let presentPrompt: () -> Void = {
        let modalController = walletPasswordPromptController(environment: environment, window: window, handle: handle, operation: operation, next: next, failed: failed, passwordRemoved: {
            guard retryState.consumeRemovedPasswordRetry() else {
                failed(.twoStepAuthMissing)
                return
            }
            handle.finished = false
            runWithoutPassword?()
        })
        handle.dismissPrompt = { [weak modalController] in
            modalController?.close()
        }
        showModal(with: modalController, for: window)
    }

    runWithoutPassword = {
        let running = showsProgress ? walletModalProgress(signal: operation(nil), for: window) : operation(nil)
        handle.operationDisposable.set((running
        |> deliverOnMainQueue).start(next: { value in
            handle.finished = true
            next(value)
        }, error: { error in
            if error == .requestPassword {
                presentPrompt()
            } else {
                handle.finished = true
                failed(error)
            }
        }))
    }

    runWithoutPassword?()

    return ActionDisposable {
        handle.dispose(enqueue: { Queue.mainQueue().async($0) })
        Queue.mainQueue().async {
            runWithoutPassword = nil
        }
    }
}
