import Cocoa
import Foundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import AlertsUI
import SystemPermissions
import BuildConfig
import LocalAuthentication
import InputDataUI
import GeneralRows
import AppAnalytics


public enum PasscodeMode : Equatable {
    case install
    case change
    case disable
    case walletProtection(enabled: Bool)
    case walletBiometrics(enabled: Bool)
}

private struct PasscodeState : Equatable {
    public let mode: PasscodeMode
    public let data: [InputDataIdentifier : InputDataValue]
    public let errors: [InputDataIdentifier : InputDataValueError]
    public let walletProtectionEnabled: Bool
    public init(mode: PasscodeMode, data: [InputDataIdentifier : InputDataValue], errors: [InputDataIdentifier : InputDataValueError], walletProtectionEnabled: Bool) {
        self.mode = mode
        self.data = data
        self.errors = errors
        self.walletProtectionEnabled = walletProtectionEnabled
    }
    
    public func withUpdatedError(_ error: InputDataValueError?, for key: InputDataIdentifier) -> PasscodeState {
        var errors = self.errors
        if let error = error {
            errors[key] = error
        } else {
            errors.removeValue(forKey: key)
        }
        return PasscodeState(mode: self.mode, data: self.data, errors: errors, walletProtectionEnabled: self.walletProtectionEnabled)
    }
    
    public func withUpdatedValue(_ value: InputDataValue, for key: InputDataIdentifier) -> PasscodeState {
        var data = self.data
        data[key] = value
        return PasscodeState(mode: self.mode, data: data, errors: self.errors, walletProtectionEnabled: self.walletProtectionEnabled)
    }

    public func withUpdatedWalletProtectionEnabled(_ walletProtectionEnabled: Bool) -> PasscodeState {
        return PasscodeState(mode: self.mode, data: self.data, errors: self.errors, walletProtectionEnabled: walletProtectionEnabled)
    }
}

private let _id_input_new_passcode = InputDataIdentifier("_id_input_new_passcode")
private let _id_input_re_new_passcode = InputDataIdentifier("_id_input_re_new_passcode")

private let _id_input_current = InputDataIdentifier("_id_input_current")

private let passcodeWalletDisableWarning = strings().passcodeControllerWalletDisableWarning
private let passcodeWalletProtectionInfo = strings().passcodeControllerWalletProtectionInfo
private let passcodeSyncFailedText = strings().passcodeControllerSyncFailed
private let passcodeWalletProtectionFailedText = strings().passcodeControllerWalletProtectionFailed

private func passcodeCooldownText(_ seconds: Int) -> String {
    return strings().passcodeControllerCooldownOther(seconds)
}

private func passcodeEntries(_ state: PasscodeState) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    
    var sectionId: Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    switch state.mode {
    case .install:

        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().passcodeControllerHeaderNew), data: InputDataGeneralTextData(viewType: .textTopItem)))
        index += 1
        
        
        entries.append(InputDataEntry.input(sectionId: sectionId, index: index, value: .string(state.data[_id_input_new_passcode]?.stringValue), error: state.errors[_id_input_new_passcode], identifier: _id_input_new_passcode, mode: .secure, data: InputDataRowData(viewType: .firstItem), placeholder: nil, inputPlaceholder: strings().passcodeControllerEnterPasscodePlaceholder, filter: { $0 }, limit: 255))
        index += 1
        
        entries.append(InputDataEntry.input(sectionId: sectionId, index: index, value: .string(state.data[_id_input_re_new_passcode]?.stringValue), error: state.errors[_id_input_re_new_passcode], identifier: _id_input_re_new_passcode, mode: .secure, data: InputDataRowData(viewType: .lastItem), placeholder: nil, inputPlaceholder: strings().passcodeControllerReEnterPasscodePlaceholder, filter: { $0 }, limit: 255))
        index += 1
        
        
    case .change:
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().passcodeControllerHeaderCurrent), data: InputDataGeneralTextData(viewType: .textTopItem)))
        index += 1
        
        entries.append(InputDataEntry.input(sectionId: sectionId, index: index, value: .string(state.data[_id_input_current]?.stringValue), error: state.errors[_id_input_current], identifier: _id_input_current, mode: .secure, data: InputDataRowData(viewType: .singleItem), placeholder: nil, inputPlaceholder: strings().passcodeControllerCurrentPlaceholder, filter: { $0 }, limit: 255))
        index += 1
        
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1

        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().passcodeControllerHeaderNew), data: InputDataGeneralTextData(viewType: .textTopItem)))
        index += 1
        
        entries.append(InputDataEntry.input(sectionId: sectionId, index: index, value: .string(state.data[_id_input_new_passcode]?.stringValue), error: state.errors[_id_input_new_passcode], identifier: _id_input_new_passcode, mode: .secure, data: InputDataRowData(viewType: .firstItem), placeholder: nil, inputPlaceholder: strings().passcodeControllerEnterPasscodePlaceholder, filter: { $0 }, limit: 255))
        index += 1
        
        entries.append(InputDataEntry.input(sectionId: sectionId, index: index, value: .string(state.data[_id_input_re_new_passcode]?.stringValue), error: state.errors[_id_input_re_new_passcode], identifier: _id_input_re_new_passcode, mode: .secure, data: InputDataRowData(viewType: .lastItem), placeholder: nil, inputPlaceholder: strings().passcodeControllerReEnterPasscodePlaceholder, filter: { $0 }, limit: 255))
        index += 1
        
        
        
    case .disable, .walletProtection, .walletBiometrics:
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().passcodeControllerHeaderCurrent), data: InputDataGeneralTextData(viewType: .textTopItem)))
        index += 1
        
        entries.append(InputDataEntry.input(sectionId: sectionId, index: index, value: .string(state.data[_id_input_current]?.stringValue), error: state.errors[_id_input_current], identifier: _id_input_current, mode: .secure, data: InputDataRowData(viewType: .singleItem), placeholder: nil, inputPlaceholder: strings().passcodeControllerCurrentPlaceholder, filter: { $0 }, limit: 255))
        index += 1
    }
    
    switch state.mode {
    case .walletProtection, .walletBiometrics:
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(passcodeWalletProtectionInfo), data: InputDataGeneralTextData(detectBold: false, viewType: .textBottomItem)))
        index += 1
    case .disable where state.walletProtectionEnabled:
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(passcodeWalletDisableWarning), data: InputDataGeneralTextData(detectBold: false, viewType: .textBottomItem)))
        index += 1
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().passcodeControllerText), data: InputDataGeneralTextData(detectBold: false, viewType: .textBottomItem)))
        index += 1
    default:
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().passcodeControllerText), data: InputDataGeneralTextData(detectBold: false, viewType: .textBottomItem)))
        index += 1
    }
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

private func passcodeCredentialSyncCompletion(_ completion: @escaping PasscodeCredentialSyncCompletion) -> PasscodeCredentialSyncCompletion {
    return { result in
        Queue.mainQueue().async {
            completion(result)
        }
    }
}

public func PasscodeController(sharedContext: (any SharedAccountContextProtocol), mode: PasscodeMode, installsForWallet: Bool = false) -> ViewController {
    
    
    let initialState = PasscodeState(mode: mode, data: [:], errors: [:], walletProtectionEnabled: false)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: false)
    let stateValue = Atomic(value: initialState)
    let updateState: ((PasscodeState) -> PasscodeState) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    let dataSignal = statePromise.get() |> map {
        return passcodeEntries($0)
    }
    
    let title: String
    switch mode {
    case .install:
        title = strings().passcodeControllerInstallTitle
    case .change:
        title = strings().passcodeControllerChangeTitle
    case .disable:
        title = strings().passcodeControllerDisableTitle
    case .walletProtection:
        title = strings().passcodeControllerWalletProtectionTitle
    case .walletBiometrics:
        title = strings().passcodeControllerWalletBiometricsTitle
    }
    
    var shouldMakeNextResponderAfterTransition: InputDataIdentifier? = nil

    let actionsDisposable = DisposableSet()

    weak var weakController: InputDataController?

    let alertSyncFailure: (String) -> Void = { text in
        if let window = weakController?.window {
            alert(for: window, info: text)
        }
    }

    let rootPath = sharedContext.accountManager.basePath.nsstring.deletingLastPathComponent
    let verifyCurrent: (String) -> Bool = { current in
        let appEncryption = AppEncryptionParameters(path: rootPath)
        appEncryption.applyPasscode(current)
        return appEncryption.decrypt() != nil
    }

    let commitPasscode: (PostboxAccessChallengeData, @escaping () -> Void, Result<Void, PasscodeCredentialSyncError>, @escaping (InputDataValidation) -> Void) -> Void = { challenge, applyEncryption, result, f in
        applyEncryption()
        actionsDisposable.add((sharedContext.accountManager.transaction { transaction in
            transaction.setAccessChallengeData(challenge)
        } |> deliverOnMainQueue).start(completed: {
            switch mode {
            case .install:
                Analytics.shared.send(AnalyticsEvents.settingsChange(.privacyPasscode(.enabled)))
            case .disable:
                Analytics.shared.send(AnalyticsEvents.settingsChange(.privacyPasscode(.disabled)))
            default:
                break
            }
            f(.success(.navigationBackWithPushAnimation))
            if case .failure = result {
                alertSyncFailure(passcodeSyncFailedText)
            }
        }))
    }

    if case .disable = mode {
        actionsDisposable.add((PasscodeCredentialHooks.shared.walletProtection() |> take(1) |> deliverOnMainQueue).start(next: { protection in
            updateState {
                $0.withUpdatedWalletProtectionEnabled(protection?.enabled ?? false)
            }
        }))
    }
    
    let controller = InputDataController(dataSignal: dataSignal |> map { InputDataSignalValue(entries: $0) }, title: title, validateData: { data in
        
        
        return .fail(.doSomething { f in
            let state = stateValue.with { $0 }
            
            switch state.mode {
            case .install:
                let passcode = state.data[_id_input_new_passcode]?.stringValue ?? ""
                let confirm = state.data[_id_input_re_new_passcode]?.stringValue ?? ""
                
                var fields:[InputDataIdentifier : InputDataValidationFailAction] = [:]
                
                if !passcode.isEmpty, !confirm.isEmpty, passcode != confirm {
                    fields[_id_input_new_passcode] = .shake
                    fields[_id_input_re_new_passcode] = .shake
                    
                    updateState {
                        $0.withUpdatedError(InputDataValueError(description: strings().passcodeControllerErrorDifferent, target: .data), for: _id_input_re_new_passcode)
                    }
                }
                if passcode.isEmpty {
                    fields[_id_input_new_passcode] = .shake
                    shouldMakeNextResponderAfterTransition = _id_input_new_passcode
                }
                if confirm.isEmpty {
                    fields[_id_input_re_new_passcode] = .shake
                    if shouldMakeNextResponderAfterTransition == nil {
                        shouldMakeNextResponderAfterTransition = _id_input_re_new_passcode
                    }
                }
                if !fields.isEmpty {
                    f(.fail(.fields(fields)))
                } else {
                    PasscodeCredentialHooks.shared.passcodeInstalled(passcode, passcodeCredentialSyncCompletion({ result in
                        let commit: () -> Void = {
                            commitPasscode(.plaintextPassword(value: ""), {
                                sharedContext.appEncryptionValue.change(passcode)
                            }, result, f)
                        }
                        guard installsForWallet else {
                            commit()
                            return
                        }
                        guard case .success = result else {
                            commit()
                            return
                        }
                        PasscodeCredentialHooks.shared.setWalletProtection(true, passcode, passcodeCredentialSyncCompletion({ protectionResult in
                            commit()
                            if case .failure = protectionResult {
                                alertSyncFailure(passcodeWalletProtectionFailedText)
                            }
                        }))
                    }))
                }
                
            case .change:
                let current = state.data[_id_input_current]?.stringValue ?? ""
                
                let passcode = state.data[_id_input_new_passcode]?.stringValue ?? ""
                let confirm = state.data[_id_input_re_new_passcode]?.stringValue ?? ""
                
                var fields:[InputDataIdentifier : InputDataValidationFailAction] = [:]
                
                if !verifyCurrent(current) {
                    fields[_id_input_current] = .shake
                    if shouldMakeNextResponderAfterTransition == nil {
                        shouldMakeNextResponderAfterTransition = _id_input_current
                    }
                    updateState {
                        $0.withUpdatedError(InputDataValueError(description: strings().passcodeControllerErrorCurrent, target: .data), for: _id_input_current)
                    }
                    f(.fail(.fields(fields)))
                    return
                }
                
                if !passcode.isEmpty, !confirm.isEmpty, passcode != confirm {
                    fields[_id_input_new_passcode] = .shake
                    fields[_id_input_re_new_passcode] = .shake
                    
                    updateState {
                        $0.withUpdatedError(InputDataValueError(description: strings().passcodeControllerErrorDifferent, target: .data), for: _id_input_re_new_passcode)
                    }
                }
                if passcode.isEmpty {
                    fields[_id_input_new_passcode] = .shake
                    if shouldMakeNextResponderAfterTransition == nil {
                        shouldMakeNextResponderAfterTransition = _id_input_new_passcode
                    }
                }
                if confirm.isEmpty {
                    fields[_id_input_re_new_passcode] = .shake
                    if shouldMakeNextResponderAfterTransition == nil {
                        shouldMakeNextResponderAfterTransition = _id_input_re_new_passcode
                    }
                }
                if !fields.isEmpty {
                    f(.fail(.fields(fields)))
                } else {
                    PasscodeCredentialHooks.shared.passcodeChanged(current, passcode, passcodeCredentialSyncCompletion({ result in
                        if case let .failure(.cooldown(seconds)) = result {
                            updateState {
                                $0.withUpdatedError(InputDataValueError(description: passcodeCooldownText(seconds), target: .data), for: _id_input_current)
                            }
                            f(.fail(.fields([_id_input_current : .shake])))
                            return
                        }
                        commitPasscode(.plaintextPassword(value: ""), {
                            sharedContext.appEncryptionValue.change(passcode)
                        }, result, f)
                    }))
                }
            case .disable:
                let current = state.data[_id_input_current]?.stringValue ?? ""
                
                if !verifyCurrent(current) {
                    updateState {
                        $0.withUpdatedError(InputDataValueError(description: strings().passcodeControllerErrorCurrent, target: .data), for: _id_input_current)
                    }
                    f(.fail(.fields([_id_input_current : .shake])))
                    
                } else {
                    PasscodeCredentialHooks.shared.passcodeDisabled(current, passcodeCredentialSyncCompletion({ result in
                        if case let .failure(.cooldown(seconds)) = result {
                            updateState {
                                $0.withUpdatedError(InputDataValueError(description: passcodeCooldownText(seconds), target: .data), for: _id_input_current)
                            }
                            f(.fail(.fields([_id_input_current : .shake])))
                            return
                        }
                        commitPasscode(.none, {
                            sharedContext.appEncryptionValue.remove()
                        }, result, f)
                    }))
                }
            case let .walletProtection(enabled), let .walletBiometrics(enabled):
                let current = state.data[_id_input_current]?.stringValue ?? ""

                if !verifyCurrent(current) {
                    updateState {
                        $0.withUpdatedError(InputDataValueError(description: strings().passcodeControllerErrorCurrent, target: .data), for: _id_input_current)
                    }
                    f(.fail(.fields([_id_input_current : .shake])))
                    return
                }
                let update: (Bool, String, @escaping PasscodeCredentialSyncCompletion) -> Void
                if case .walletBiometrics = state.mode {
                    update = PasscodeCredentialHooks.shared.setWalletBiometrics
                } else {
                    update = PasscodeCredentialHooks.shared.setWalletProtection
                }
                update(enabled, current, passcodeCredentialSyncCompletion({ result in
                    switch result {
                    case .success:
                        f(.success(.navigationBackWithPushAnimation))
                    case let .failure(error):
                        switch error {
                        case .invalidCode:
                            updateState {
                                $0.withUpdatedError(InputDataValueError(description: strings().passcodeControllerErrorCurrent, target: .data), for: _id_input_current)
                            }
                            f(.fail(.fields([_id_input_current : .shake])))
                        case let .cooldown(seconds):
                            updateState {
                                $0.withUpdatedError(InputDataValueError(description: passcodeCooldownText(seconds), target: .data), for: _id_input_current)
                            }
                            f(.fail(.fields([_id_input_current : .shake])))
                        case .failed:
                            f(.fail(.alert(passcodeWalletProtectionFailedText)))
                        }
                    }
                }))
            }
            
            updateState {
                $0
            }
        })
    }, updateDatas: { data in
        updateState { state in
            var state = state
            if let value = data[_id_input_new_passcode] {
                state = state.withUpdatedValue(value, for: _id_input_new_passcode).withUpdatedError(nil, for: _id_input_new_passcode)
            }
            if let value = data[_id_input_re_new_passcode] {
                state = state.withUpdatedValue(value, for: _id_input_re_new_passcode).withUpdatedError(nil, for: _id_input_re_new_passcode)
            }
            if let value = data[_id_input_current] {
                state = state.withUpdatedValue(value, for: _id_input_current).withUpdatedError(nil, for: _id_input_current)
            }
            return state
        }
       
        
        return .none
    }, afterDisappear: {
        actionsDisposable.dispose()
    }, afterTransaction: { controller in
        if let identifier = shouldMakeNextResponderAfterTransition {
            controller.makeFirstResponderIfPossible(for: identifier)
        }
        shouldMakeNextResponderAfterTransition = nil
    })

    weakController = controller

    switch mode {
    case .walletProtection, .walletBiometrics:
        controller.analyticsScreen = .walletProtection
    default:
        controller.analyticsScreen = .settingsPrivacyPasscodeSetup
    }

    return controller
    
}
