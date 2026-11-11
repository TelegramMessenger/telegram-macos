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

@available(macOS 10.15, *)
private final class Arguments {
    let showRecoveryPhrase: () -> Void
    let enableBackup: () -> Void
    let disableBackup: () -> Void
    let deleteWallet: () -> Void
    let showPreviousWallet: (WalletContext.PreviousWallet) -> Void

    let enterRecoveryPhrase: () -> Void
    init(enterRecoveryPhrase: @escaping () -> Void, showRecoveryPhrase: @escaping () -> Void, enableBackup: @escaping () -> Void, disableBackup: @escaping () -> Void, showPreviousWallet: @escaping (WalletContext.PreviousWallet) -> Void, deleteWallet: @escaping () -> Void) {
        self.enterRecoveryPhrase = enterRecoveryPhrase
        self.showRecoveryPhrase = showRecoveryPhrase
        self.enableBackup = enableBackup
        self.disableBackup = disableBackup
        self.showPreviousWallet = showPreviousWallet
        self.deleteWallet = deleteWallet
    }
}

@available(macOS 10.15, *)
private struct State: Equatable {
    var walletState: WalletContext.State
    var previousWallets: [WalletContext.PreviousWallet] = []
}

@available(macOS 10.15, *)
private func walletPreviousWalletSubtitle(_ wallet: WalletContext.PreviousWallet) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(wallet.lastUsedAt))
    let lastUsed: String
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
        lastUsed = strings().walletSettingsControllerLastUsedToday
    } else if calendar.isDateInYesterday(date) {
        lastUsed = strings().walletSettingsControllerLastUsedYesterday
    } else {
        let formatter = DateFormatter()
        formatter.locale = appAppearance.locale
        formatter.setLocalizedDateFormatFromTemplate("d MMM yyyy")
        lastUsed = formatter.string(from: date)
    }
    let balanceText = wallet.balance.map { formatGramsText($0, maxDecimalPositions: 2) } ?? walletGramsUnitText("—")
    return strings().walletSettingsControllerPreviousWalletSubtitle(balanceText, lastUsed)
}

@available(macOS 10.15, *)
private enum WalletBackupAction {
    case enable
    case disable

    func isAvailable(for info: WalletContext.WalletInfo) -> Bool {
        switch self {
        case .enable:
            return info.canEnableBackup
        case .disable:
            return info.backupEnabled
        }
    }
}

private let _id_show_recovery = InputDataIdentifier("_id_show_recovery")
private let _id_enter_recovery = InputDataIdentifier("_id_enter_recovery")
private let _id_enable_backup = InputDataIdentifier("_id_enable_backup")
private let _id_disable_backup = InputDataIdentifier("_id_disable_backup")
private let _id_delete_wallet = InputDataIdentifier("_id_delete_wallet")
private func _id_previous_wallet(_ id: String) -> InputDataIdentifier {
    InputDataIdentifier("_id_previous_wallet_\(id)")
}

@available(macOS 10.15, *)
private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    if case let .wallet(info) = state.walletState.phase {
        if info.canRevealPhrase {
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().walletSettingsControllerSecretPhraseHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
            index += 1
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_show_recovery, data: .init(name: strings().walletSettingsControllerShowSecretPhrase, color: walletClassicAccent, type: .none, viewType: .singleItem, action: arguments.showRecoveryPhrase)))
            index += 1
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().walletSettingsControllerShowSecretPhraseInfo), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
            index += 1
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
        } else if !info.canSign, !info.canExportPhrase {
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().walletSettingsControllerSecretPhraseHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
            index += 1
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_enter_recovery, data: .init(name: strings().walletSettingsControllerEnterSecretPhrase, color: walletClassicAccent, type: .none, viewType: .singleItem, action: arguments.enterRecoveryPhrase)))
            index += 1
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().walletSettingsControllerEnterSecretPhraseInfo), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
            index += 1
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
        }

        let showEnableBackup = info.canEnableBackup
        let showDisableBackup = info.backupEnabled
        if showEnableBackup || showDisableBackup {
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().walletSettingsControllerEncryptedBackupHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
            index += 1
            if showEnableBackup {
                entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_enable_backup, data: .init(name: strings().walletSettingsControllerEnableBackup, color: walletClassicAccent, type: .none, viewType: showDisableBackup ? .firstItem : .singleItem, action: arguments.enableBackup)))
                index += 1
            }
            if showDisableBackup {
                entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_disable_backup, data: .init(name: strings().walletSettingsControllerDisableBackup, color: theme.colors.redUI, type: .none, viewType: showEnableBackup ? .lastItem : .singleItem, action: arguments.disableBackup)))
                index += 1
            }
            let footerText: String
            if info.backupEnabled {
                footerText = strings().walletSettingsControllerBackupEnabledInfo
            } else {
                footerText = strings().walletSettingsControllerBackupDisabledInfo
            }
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(footerText), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
            index += 1
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
        }
    } else {
        let phaseText: String
        switch state.walletState.phase {
        case .restoring, .creating, .empty:
            phaseText = strings().walletSettingsControllerSettingUp
        case .failed:
            phaseText = strings().walletSettingsControllerDataUnreadable
        case .wallet:
            phaseText = ""
        }
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(phaseText), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    }

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_delete_wallet, data: .init(name: strings().walletSettingsControllerDeleteWallet, color: theme.colors.redUI, type: .none, viewType: .singleItem, action: arguments.deleteWallet)))
    index += 1

    if !state.previousWallets.isEmpty {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1

        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().walletSettingsControllerPreviousWalletsHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1

        for wallet in state.previousWallets {
            let viewType = bestGeneralViewType(state.previousWallets, for: wallet)
            let subtitle = walletPreviousWalletSubtitle(wallet)
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_previous_wallet(wallet.id), equatable: .init(wallet), comparable: nil, item: { initialSize, stableId in
                return WalletPreviousWalletRowItem(initialSize, stableId: stableId, address: wallet.address, subtitle: subtitle, viewType: viewType, action: {
                    arguments.showPreviousWallet(wallet)
                })
            }))
            index += 1
        }

        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().walletSettingsControllerPreviousWalletsInfo), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal))

    return entries
}

func walletDisableBackupConfirmationText(updateSecretPhrase: Bool) -> String {
    return updateSecretPhrase
        ? strings().walletSettingsControllerDisableBackupConfirmUpdatePhrase
        : strings().walletSettingsControllerDisableBackupConfirm
}

@available(macOS 10.15, *)
public func WalletSettingsController(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext) -> InputDataModalController {
    let actionsDisposable = DisposableSet()
    let recoveryDisposable = MetaDisposable()
    let backupDisposable = MetaDisposable()
    let backupAccessDisposable = MetaDisposable()
    let replaceDisposable = MetaDisposable()
    let previousWalletsDisposable = MetaDisposable()
    let previousPhraseDisposable = MetaDisposable()
    actionsDisposable.add(previousWalletsDisposable)
    actionsDisposable.add(previousPhraseDisposable)
    actionsDisposable.add(recoveryDisposable)
    actionsDisposable.add(backupDisposable)
    actionsDisposable.add(backupAccessDisposable)
    actionsDisposable.add(replaceDisposable)

    let settingsFlow = WalletFlowAuthorization(walletContext: walletContext, reason: walletConfirmAccessFlowReason)
    let restoreAuthorization = WalletFlowAuthorization(walletContext: walletContext, reason: walletRestoreFlowReason)

    let initialState = State(walletState: walletContext.stateValue)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    let reloadPreviousWallets: () -> Void = {
        previousWalletsDisposable.set((walletContext.previousWallets()
        |> deliverOnMainQueue).start(next: { wallets in
            let deduplicated = walletUniquePreviousWallets(wallets)
            updateState { current in
                var current = current
                current.previousWallets = deduplicated
                return current
            }
        }))
    }

    var getController: (() -> ViewController?)?

    var window: Window {
        walletUIWindow(context, getController?())
    }

    var preparedBackupDisable: WalletContext.PreparedBackupDisable? = nil
    var isPreparingBackupDisable = false
    var isDisablingBackup = false
    var backupWordsClose: (() -> Void)? = nil
    var backupWordsWindow: (() -> Window?)? = nil
    var disableBackupWalletIdentity: (address: String, publicKey: String)? = nil
    var disableBackupGeneration: UInt64 = 0

    let setPreparedBackupDisable: (WalletContext.PreparedBackupDisable?) -> Void = { prepared in
        if let previous = preparedBackupDisable, previous.id != prepared?.id {
            walletContext.discardPreparedBackupDisable(previous)
        }
        preparedBackupDisable = prepared
    }

    let abandonBackupAccess: () -> Void = {
        backupAccessDisposable.set(nil)
        restoreAuthorization.end()
    }

    var isOpeningPreviousWalletPhrase = false

    let abandonWalletFlow: () -> Void = {
        abandonBackupAccess()
        previousPhraseDisposable.set(nil)
        isOpeningPreviousWalletPhrase = false
        disableBackupGeneration &+= 1
        disableBackupWalletIdentity = nil
        backupDisposable.set(nil)
        isPreparingBackupDisable = false
        isDisablingBackup = false
        setPreparedBackupDisable(nil)
        settingsFlow.end()
    }

    let dismissBackupWordsFlow: () -> Void = {
        let close = backupWordsClose
        backupWordsClose = nil
        backupWordsWindow = nil
        abandonWalletFlow()
        close?()
    }

    let disableBackupFeeText: (Int64) -> String = { fee in
        var text = formatGramsText(fee, maxDecimalPositions: 5)
        let fiat = walletContext.stateValue.fiat
        if let rate = fiat.selectedRate, rate.unitsPerGram.isFinite, rate.unitsPerGram > 0 {
            if Double(fee) / 1_000_000_000 * rate.unitsPerGram < 0.005 {
                text += " (<\(formatFiatValue(0.01, currencySymbol: fiat.selectedCurrency.symbol)))"
            } else {
                text += " (~\(formatTonFiatValue(fee, rate: rate.unitsPerGram, currencySymbol: fiat.selectedCurrency.symbol)))"
            }
        }
        return text
    }

    let disableBackupErrorMessage: (WalletContext.WalletError?) -> (title: String, text: String) = { error in
        switch error {
        case .proofInvalid?:
            return (strings().walletSettingsControllerErrorProofInvalidTitle, strings().walletSettingsControllerErrorProofInvalid)
        case .proofExpired?:
            return (strings().walletSettingsControllerErrorProofExpiredTitle, strings().walletSettingsControllerErrorProofExpired)
        case .rotationNotFound?:
            return (strings().walletSettingsControllerErrorRotationPendingTitle, strings().walletSettingsControllerErrorRotationPending)
        case .keyRotationFailed?:
            return (strings().walletSettingsControllerErrorKeyRotationFailedTitle, strings().walletSettingsControllerErrorKeyRotationFailed)
        case let .insufficientBalance(required)?:
            return (strings().walletSettingsControllerErrorInsufficientBalanceTitle, strings().walletSettingsControllerErrorInsufficientBalance(disableBackupFeeText(required)))
        default:
            return error.flatMap(walletAuthorizationErrorMessage)
                ?? (strings().walletSettingsControllerErrorDisableBackupTitle, strings().walletSettingsControllerErrorDisableBackup)
        }
    }

    let presentDisableBackupError: (WalletContext.WalletError, Window) -> Void = { error, targetWindow in
        if error == .authorizationCancelled {
            settingsFlow.end()
            return
        }
        let message = disableBackupErrorMessage(error)
        environment.alert(for: targetWindow, header: message.title, info: message.text)
    }

    var presentDisableBackupAlert: ((Bool) -> Void)?
    var continueWithPreparedBackupDisable: ((WalletContext.PreparedBackupDisable, Window) -> Void)?
    var presentFinalDisableBackupConfirmation: ((WalletContext.PreparedBackupDisable, Window, @escaping () -> Void) -> Void)?

    presentFinalDisableBackupConfirmation = { prepared, phraseWindow, dismiss in
        let information = walletDisableBackupConfirmationText(updateSecretPhrase: prepared.updateSecretPhrase)
        let generation = disableBackupGeneration
        environment.verifyAlert(for: phraseWindow, header: strings().walletSettingsControllerDisableBackupConfirmTitle, information: information, ok: strings().walletSettingsControllerDisable, cancel: strings().walletSettingsControllerCancel, successHandler: { _ in
            guard !isDisablingBackup, disableBackupGeneration == generation, preparedBackupDisable?.id == prepared.id else {
                return
            }
            isDisablingBackup = true
            backupDisposable.set(performWalletAuthorizedOperation(context: context, environment: environment, window: phraseWindow, operation: { password in
                settingsFlow.authorize()
                |> mapToSignal { session in
                    walletContext.disableBackup(prepared, password: password, session: session)
                }
            }, next: { _ in
                guard disableBackupGeneration == generation, preparedBackupDisable?.id == prepared.id else {
                    return
                }
                isDisablingBackup = false
                disableBackupWalletIdentity = nil
                settingsFlow.end()
                preparedBackupDisable = nil
                backupWordsClose = nil
                backupWordsWindow = nil
                dismiss()
                environment.showModalText(for: window, text: strings().walletSettingsControllerBackupDisabledNotice, title: strings().walletSettingsControllerBackupDisabled)
            }, failed: { error in
                guard disableBackupGeneration == generation, preparedBackupDisable?.id == prepared.id else {
                    return
                }
                isDisablingBackup = false
                if error == .preparedBackupDisableExpired {
                    presentDisableBackupAlert?(true)
                    return
                }
                if case let .backupDisableNeedsConfirmation(updated) = error {
                    setPreparedBackupDisable(updated)
                    presentFinalDisableBackupConfirmation?(updated, phraseWindow, dismiss)
                    return
                }
                presentDisableBackupError(error, phraseWindow)
            }))
        }, cancelHandler: {
            dismissBackupWordsFlow()
        })
    }

    let presentFinalDisableBackup: (WalletContext.PreparedBackupDisable, Window, @escaping () -> Void) -> Void = { prepared, phraseWindow, dismiss in
        guard !isDisablingBackup, preparedBackupDisable?.id == prepared.id else {
            return
        }
        let generation = disableBackupGeneration
        isDisablingBackup = true
        backupDisposable.set((walletModalProgress(signal: settingsFlow.authorize()
        |> mapToSignal { session in
            walletContext.refreshPreparedBackupDisable(prepared, session: session)
        }, for: phraseWindow)
        |> deliverOnMainQueue).start(next: { updated in
            guard disableBackupGeneration == generation, preparedBackupDisable?.id == prepared.id else {
                return
            }
            isDisablingBackup = false
            setPreparedBackupDisable(updated)
            presentFinalDisableBackupConfirmation?(updated, phraseWindow, dismiss)
        }, error: { error in
            guard disableBackupGeneration == generation, preparedBackupDisable?.id == prepared.id else {
                return
            }
            isDisablingBackup = false
            if error == .preparedBackupDisableExpired {
                presentDisableBackupAlert?(true)
                return
            }
            presentDisableBackupError(error, phraseWindow)
        }))
    }

    continueWithPreparedBackupDisable = { prepared, targetWindow in
        if let fee = prepared.networkFeeNanograms {
            guard let balance = walletContext.stateValue.balance.currentValue else {
                abandonWalletFlow()
                presentDisableBackupError(.network, targetWindow)
                return
            }
            if balance < fee {
                abandonWalletFlow()
                let message = disableBackupErrorMessage(.insufficientBalance(required: fee))
                environment.verifyAlert(for: targetWindow, header: message.title, information: message.text, ok: strings().walletSettingsControllerTopUp, cancel: strings().walletSettingsControllerNotNow, successHandler: { _ in
                    guard case let .wallet(info) = walletContext.stateValue.phase else {
                        return
                    }
                    showModal(with: WalletReceiveController(context: context, environment: environment, walletContext: walletContext, address: info.address), for: targetWindow)
                })
                return
            }
        }
        let (wordsController, dismissWords) = WalletBackupDisableWordsController(context: context, environment: environment, walletContext: walletContext, words: prepared.words, updateSecretPhrase: prepared.updateSecretPhrase, onVerified: { phraseWindow, dismiss in
            presentFinalDisableBackup(prepared, phraseWindow, dismiss)
        }, dismissed: {
            guard preparedBackupDisable?.id == prepared.id else {
                return
            }
            backupWordsClose = nil
            backupWordsWindow = nil
            abandonWalletFlow()
        })
        backupWordsClose = dismissWords
        backupWordsWindow = { [weak wordsController] in
            wordsController?.window
        }
        showModal(with: wordsController, for: targetWindow)
    }

    let prepareDisableBackup: (Bool, Bool, Window) -> Void = { updateSecretPhrase, replacingWords, targetWindow in
        guard !isPreparingBackupDisable else {
            return
        }
        let generation = disableBackupGeneration
        isPreparingBackupDisable = true
        backupDisposable.set((walletModalProgress(signal: settingsFlow.authorize()
        |> mapToSignal { session in
            walletContext.prepareDisableBackup(updateSecretPhrase: updateSecretPhrase, session: session)
        }, for: targetWindow)
        |> deliverOnMainQueue).start(next: { prepared in
            guard disableBackupGeneration == generation else {
                walletContext.discardPreparedBackupDisable(prepared)
                return
            }
            isPreparingBackupDisable = false
            setPreparedBackupDisable(prepared)
            if replacingWords {
                let close = backupWordsClose
                backupWordsClose = nil
                backupWordsWindow = nil
                close?()
                continueWithPreparedBackupDisable?(prepared, window)
            } else {
                continueWithPreparedBackupDisable?(prepared, targetWindow)
            }
        }, error: { error in
            guard disableBackupGeneration == generation else {
                return
            }
            isPreparingBackupDisable = false
            presentDisableBackupError(error, targetWindow)
        }))
    }

    let presentDisableBackupTopUp: (Bool) -> Void = { restarting in
        if restarting {
            dismissBackupWordsFlow()
        } else {
            abandonWalletFlow()
        }
        environment.verifyAlert(for: window, header: strings().walletSettingsControllerDisableBackupConfirmTitle, information: strings().walletSettingsControllerDisableBackupZeroBalance, ok: strings().walletSettingsControllerTopUp, cancel: strings().walletSettingsControllerCancel, successHandler: { _ in
            guard case let .wallet(info) = walletContext.stateValue.phase else {
                return
            }
            showModal(with: WalletReceiveController(context: context, environment: environment, walletContext: walletContext, address: info.address), for: window)
        })
    }

    presentDisableBackupAlert = { restarting in
        if restarting, preparedBackupDisable == nil || backupWordsClose == nil {
            return
        }
        guard walletContext.stateValue.activeOperation == nil,
              case let .wallet(info) = walletContext.stateValue.phase,
              info.backupEnabled else {
            return
        }
        let targetWindow = restarting ? (backupWordsWindow?() ?? window) : window
        let updateSecretPhrase = restarting && preparedBackupDisable?.updateSecretPhrase == true
        disableBackupWalletIdentity = (info.address, info.publicKey)
        environment.verifyAlert(for: targetWindow, header: strings().walletSettingsControllerDisableBackupConfirmTitle, information: strings().walletSettingsControllerDisableBackupManualRecovery, ok: strings().walletSettingsControllerDisable, cancel: strings().walletSettingsControllerCancel, option: strings().walletSettingsControllerUpdateSecretPhrase, optionIsSelected: updateSecretPhrase, successHandler: { updateSecretPhrase in
            if updateSecretPhrase, walletDisableBackupRequiresTopUp(walletContext.stateValue) {
                presentDisableBackupTopUp(restarting)
                return
            }
            prepareDisableBackup(updateSecretPhrase, restarting, targetWindow)
        }, cancelHandler: {
            if restarting {
                dismissBackupWordsFlow()
            } else {
                abandonWalletFlow()
            }
        })
    }

    let reconcileBackupDisableWalletState: (WalletContext.State) -> Void = { walletState in
        guard let identity = disableBackupWalletIdentity else {
            return
        }
        switch walletState.phase {
        case .restoring, .creating:
            return
        case let .wallet(info):
            if info.address == identity.address {
                if info.publicKey == identity.publicKey {
                    if !info.backupEnabled, !isDisablingBackup {
                        dismissBackupWordsFlow()
                    }
                    return
                }
                if let newPublicKey = preparedBackupDisable?.rotation?.newPublicKey,
                   info.publicKey == newPublicKey.map({ String(format: "%02x", $0) }).joined() {
                    return
                }
            }
        case .empty, .failed:
            break
        }
        let targetWindow = backupWordsWindow?() ?? window
        dismissBackupWordsFlow()
        environment.alert(for: targetWindow, header: strings().walletSettingsControllerWalletChanged, info: strings().walletSettingsControllerWalletChangedInfo)
    }

    let openBackupPhraseInput: (String) -> Void = { expectedAddress in
        guard case let .wallet(info) = walletContext.stateValue.phase, info.address == expectedAddress, info.canEnableBackup else {
            return
        }
        abandonWalletFlow()
        let targetWindow = window
        showModal(with: WalletImportController(context: context, environment: environment, walletContext: walletContext, mode: .enableBackup(expectedAddress: expectedAddress), onImported: {
            environment.showModalText(for: targetWindow, text: strings().walletSettingsControllerBackupEnabledNotice, title: strings().walletSettingsControllerBackupEnabled)
        }), for: targetWindow)
    }

    var enableBackup: (() -> Void)?
    enableBackup = {
        guard walletContext.stateValue.activeOperation == nil,
              case let .wallet(info) = walletContext.stateValue.phase,
              info.canEnableBackup else {
            return
        }
        guard info.canSign else {
            openBackupPhraseInput(info.address)
            return
        }
        let targetWindow = window
        backupDisposable.set((walletModalProgress(signal: settingsFlow.authorize()
        |> mapToSignal { session in
            walletContext.enableBackup(expectedAddress: info.address, session: session)
        }, for: targetWindow)
        |> deliverOnMainQueue).start(next: { _ in
            settingsFlow.end()
            environment.showModalText(for: targetWindow, text: strings().walletSettingsControllerBackupEnabledNotice, title: strings().walletSettingsControllerBackupEnabled)
        }, error: { error in
            if error == .authorizationCancelled {
                settingsFlow.end()
            }
            presentWalletBackupEnableError(environment: environment, error, window: targetWindow, retry: {
                enableBackup?()
            }, enterSecretPhrase: {
                openBackupPhraseInput(info.address)
            })
        }))
    }

    let performBackupAction: (WalletBackupAction) -> Void = { action in
        switch action {
        case .enable:
            enableBackup?()
        case .disable:
            presentDisableBackupAlert?(false)
        }
    }

    var beginBackupAction: ((WalletBackupAction) -> Void)?
    beginBackupAction = { action in
        guard walletContext.stateValue.activeOperation == nil,
              case let .wallet(info) = walletContext.stateValue.phase,
              action.isAvailable(for: info) else {
            return
        }
        abandonWalletFlow()
        if case .enable = action {
            enableBackup?()
            return
        }
        if info.canSign {
            performBackupAction(action)
            return
        }
        let targetWindow = window
        let resumeIfReady: () -> Void = {
            guard walletContext.stateValue.activeOperation == nil,
                  case let .wallet(current) = walletContext.stateValue.phase,
                  current.address == info.address, current.publicKey == info.publicKey,
                  current.canSign, action.isAvailable(for: current) else {
                return
            }
            performBackupAction(action)
        }
        if info.canExportPhrase {
            backupAccessDisposable.set(walletRestoreSigningAccess(context: context, environment: environment, window: targetWindow, walletContext: walletContext, authorization: restoreAuthorization, retry: {
                beginBackupAction?(action)
            }, next: {
                resumeIfReady()
            }, failed: {}))
        } else {
            environment.verifyAlert(for: targetWindow, header: strings().walletSettingsControllerSecretPhraseRequired, information: strings().walletSettingsControllerSecretPhraseRequiredForBackup, ok: strings().walletSettingsControllerProceed, cancel: strings().walletSettingsControllerCancel, successHandler: { _ in
                showModal(with: WalletImportController(context: context, environment: environment, walletContext: walletContext, mode: .enterRecoveryPhrase, onImported: {
                    environment.showModalText(for: targetWindow, text: strings().walletSettingsControllerWalletImportedInfo, title: strings().walletSettingsControllerWalletImported)
                    delay(0.4, closure: {
                        resumeIfReady()
                    })
                }), for: targetWindow)
            })
        }
    }

    let arguments = Arguments(enterRecoveryPhrase: {
        guard walletContext.stateValue.activeOperation == nil else {
            return
        }
        abandonWalletFlow()
        showModal(with: WalletImportController(context: context, environment: environment, walletContext: walletContext, mode: .enterRecoveryPhrase, onImported: {
            environment.showModalText(for: context.window, text: strings().walletSettingsControllerWalletImportedInfo, title: strings().walletSettingsControllerWalletImported)
        }), for: context.window)
    }, showRecoveryPhrase: {
        guard case let .wallet(info) = walletContext.stateValue.phase, info.canRevealPhrase else {
            return
        }
        abandonWalletFlow()
        let targetWindow = window
        showModal(with: WalletInfoController(context: context, environment: environment, walletContext: walletContext, mode: .recovery, completion: {
            recoveryDisposable.set(performWalletAuthorizedOperation(context: context, environment: environment, window: targetWindow, operation: { password in
                walletContext.recoveryPhrase(password: password)
            }, next: { words in
                showModal(with: WalletWordsController(context: context, environment: environment, walletContext: walletContext, words: words, dismissOnBackgroundOrLock: true), for: targetWindow)
            }, failed: { error in
                presentWalletAuthorizationError(environment: environment, error, window: targetWindow, fallbackTitle: strings().walletSettingsControllerShowSecretPhraseFailed, fallbackText: strings().walletSettingsControllerCheckNetwork)
            }))
        }), for: targetWindow)
    }, enableBackup: {
        beginBackupAction?(.enable)
    }, disableBackup: {
        beginBackupAction?(.disable)
    }, showPreviousWallet: { wallet in
        guard !isOpeningPreviousWalletPhrase,
              walletContext.stateValue.activeOperation == nil,
              stateValue.with({ $0.previousWallets.contains(where: { $0.id == wallet.id }) }) else {
            return
        }
        abandonWalletFlow()
        isOpeningPreviousWalletPhrase = true
        let targetWindow = window
        previousPhraseDisposable.set((walletModalProgress(signal: walletContext.previousWalletRecoveryPhrase(id: wallet.id), for: targetWindow)
        |> deliverOnMainQueue).start(next: { words in
            isOpeningPreviousWalletPhrase = false
            showModal(with: WalletWordsController(context: context, environment: environment, walletContext: walletContext, words: words, dismissOnBackgroundOrLock: true), for: targetWindow)
        }, error: { error in
            isOpeningPreviousWalletPhrase = false
            presentWalletAuthorizationError(environment: environment, error, window: targetWindow, fallbackTitle: strings().walletSettingsControllerShowSecretPhraseFailed, fallbackText: strings().walletSettingsControllerCheckNetwork)
        }, completed: {
            isOpeningPreviousWalletPhrase = false
        }))
    }, deleteWallet: {
        abandonWalletFlow()
        let targetWindow = window
        environment.verifyAlert(for: targetWindow, header: strings().walletSettingsControllerDeleteWalletConfirmTitle, information: strings().walletSettingsControllerDeleteWalletConfirm, ok: strings().walletSettingsControllerDeleteAnyway, cancel: strings().walletSettingsControllerCancel, successHandler: { _ in
            delay(0.25, closure: {
                showModal(with: WalletReplaceController(context: context, environment: environment, walletContext: walletContext), for: targetWindow)
            })
        })
    })

    let signal = statePromise.get()
    |> deliverOnPrepareQueue
    |> map { state in
        InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    let controller = InputDataController(dataSignal: signal, title: strings().walletSettingsControllerKeysAndBackup, hasDone: false)
    controller.analyticsScreen = .walletSettings
    getController = { [weak controller] in
        controller
    }
    controller.onDeinit = {
        if let prepared = preparedBackupDisable {
            walletContext.discardPreparedBackupDisable(prepared)
        }
        preparedBackupDisable = nil
        settingsFlow.end()
        restoreAuthorization.end()
        actionsDisposable.dispose()
        presentDisableBackupAlert = nil
        continueWithPreparedBackupDisable = nil
        presentFinalDisableBackupConfirmation = nil
        enableBackup = nil
        beginBackupAction = nil
    }

    actionsDisposable.add((walletContext.state |> deliverOnMainQueue).start(next: { walletState in
        let previousWalletState = stateValue.with { $0.walletState }
        if case let .wallet(previousInfo) = previousWalletState.phase {
            switch walletState.phase {
            case let .wallet(info) where previousInfo.address == info.address && previousInfo.publicKey == info.publicKey:
                break
            default:
                abandonBackupAccess()
            }
        }
        if previousWalletState.phase != walletState.phase || previousWalletState.walletAddress != walletState.walletAddress {
            reloadPreviousWallets()
        }
        updateState { current in
            var current = current
            current.walletState = walletState
            return current
        }
        reconcileBackupDisableWalletState(walletState)
    }))

    reloadPreviousWallets()

    let modalController = WalletModalController(controller, size: NSMakeSize(360, 0))
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    return modalController
}
