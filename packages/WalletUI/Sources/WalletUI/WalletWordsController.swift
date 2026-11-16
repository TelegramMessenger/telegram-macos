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
import IOKit.pwr_mgt
import AppAnalytics

private final class Arguments {
    let context: any AccountContextProtocol
    let environment: WalletUIEnvironment
    let isReplacementPhrase: Bool

    init(context: any AccountContextProtocol, environment: WalletUIEnvironment, isReplacementPhrase: Bool) {
        self.context = context
        self.environment = environment
        self.isReplacementPhrase = isReplacementPhrase
    }
}

private struct State: Equatable {
    var words: [String]
}

private let _id_header = InputDataIdentifier("_id_header")
private let _id_words_grid = InputDataIdentifier("_id_words_grid")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        let title = NSMutableAttributedString()
        let titleText: String
        let bodyText: String
        if arguments.isReplacementPhrase {
            titleText = strings().walletWordsControllerNewPhraseTitle
            bodyText = strings().walletWordsControllerNewPhraseInfo
        } else {
            titleText = strings().walletWordsControllerPhraseTitle
            bodyText = strings().walletWordsControllerPhraseInfo
        }
        title.append(string: titleText, color: theme.colors.text, font: .medium(18))
        return arguments.environment.makeAnimatedHeader(
            initialSize,
            stableId: stableId,
            sticker: WalletUIAnimation.wallet_word_list,
            text: title,
            infoText: .initialize(string: bodyText, color: theme.colors.text, font: .normal(.text)),
            stickerSize: NSMakeSize(108, 108), image: nil, viewType: .singleItem)
    }))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(30)))
    sectionId += 1

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_words_grid, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return WalletWordsGridRowItem(initialSize, stableId: stableId, words: state.words, viewType: .legacy)
    }))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1

    return entries
}

private func makeWordsController(context: any AccountContextProtocol, environment: WalletUIEnvironment, words: [String], isReplacementPhrase: Bool = false, dismissed: (() -> Void)? = nil) -> InputDataController {
    let actionsDisposable = DisposableSet()

    let initialState = State(words: words)

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)

    let arguments = Arguments(context: context, environment: environment, isReplacementPhrase: isReplacementPhrase)

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: strings().walletWordsControllerTitle, hasDone: false, getBackgroundColor: {
        theme.colors.background
    })
    controller.analyticsScreen = .walletRecoveryPhrase

    var displaySleepAssertionID: IOPMAssertionID = 0
    var holdsDisplaySleepAssertion = false

    controller.didLoad = { _, _ in
        guard !holdsDisplaySleepAssertion else {
            return
        }
        let status = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString,
                                                 IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "Wallet Secret Phrase" as CFString,
                                                 &displaySleepAssertionID)
        holdsDisplaySleepAssertion = status == kIOReturnSuccess
    }

    controller.onDeinit = {
        if holdsDisplaySleepAssertion {
            _ = IOPMAssertionRelease(displaySleepAssertionID)
            holdsDisplaySleepAssertion = false
        }
        actionsDisposable.dispose()
        dismissed?()
    }

    return controller
}

private func walletWordsBackgroundOrLock() -> Signal<Void, NoError> {
    return Signal { subscriber in
        let token = NotificationCenter.default.addObserver(forName: NSApplication.didHideNotification, object: nil, queue: .main, using: { _ in
            subscriber.putNext(Void())
        })
        let lockDisposable = (walletUIPasscodeLocked()
        |> filter { $0 }).start(next: { _ in
            subscriber.putNext(Void())
        })
        return ActionDisposable {
            NotificationCenter.default.removeObserver(token)
            lockDisposable.dispose()
        }
    } |> take(1)
}

@available(macOS 10.15, *)
public func WalletWordsController(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, words: [String], dismissOnBackgroundOrLock: Bool = false) -> InputDataModalController {
    let controller = makeWordsController(context: context, environment: environment, words: words)

    var close: (() -> Void)? = nil

    if dismissOnBackgroundOrLock {
        let dismissalDisposable = MetaDisposable()
        dismissalDisposable.set((walletWordsBackgroundOrLock()
        |> deliverOnMainQueue).start(next: { _ in
            close?()
        }))
        controller.onDeinit = { [previous = controller.onDeinit] in
            dismissalDisposable.dispose()
            previous?()
        }
    }

    controller.validateData = { _ in
        close?()
        return .none
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().walletWordsControllerDone, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true, customTheme: { walletModalTheme })

    let modalController = WalletModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(360, 0))

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })

    close = { [weak modalController] in
        modalController?.close()
    }

    return modalController
}

@available(macOS 10.15, *)
public func WalletBackupDisableWordsController(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, words: [String], updateSecretPhrase: Bool, onVerified: @escaping (Window, @escaping () -> Void) -> Void, dismissed: (() -> Void)? = nil) -> (controller: InputDataModalController, dismiss: () -> Void) {
    let controller = makeWordsController(context: context, environment: environment, words: words, isReplacementPhrase: updateSecretPhrase, dismissed: dismissed)
    let displayedAt = Date()
    var verificationStep: WalletOnboardingStep?
    var getModalController: (() -> InputDataModalController?)?
    var updateButton: (() -> Void)?
    var dismiss: (() -> Void)?

    let continueAction: () -> Void = { [weak controller] in
        guard verificationStep == nil, let modalController = getModalController?() else {
            verificationStep?.accept()
            return
        }
        guard Date().timeIntervalSince(displayedAt) >= 10.0 else {
            environment.alert(for: walletUIWindow(context, controller), header: strings().walletWordsControllerAllDoneTitle, info: strings().walletWordsControllerAllDoneInfo, ok: strings().walletWordsControllerOkSorry)
            return
        }
        let step = WalletImportPage(
            context: context, environment: environment,
            walletContext: walletContext,
            mode: .verify(words, keyRotation: updateSecretPhrase, allowsRepeatedCompletion: true),
            frameRect: modalController.frame.size.bounds,
            updateButton: {
                updateButton?()
            },
            onBack: { [weak modalController] in
                modalController?.pop(animated: true)
            },
            onVerified: {
                onVerified(walletUIWindow(context, verificationStep?.controller)) {
                    dismiss?()
                }
            }
        )
        verificationStep = step
        modalController.push(step.controller, animated: true)
        updateButton?()
    }

    controller.validateData = { _ in
        continueAction()
        return .none
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().walletWordsControllerContinue, accept: {
        continueAction()
    }, singleButton: true, customTheme: { walletModalTheme })
    var isDismissingProgrammatically = false
    let modalController = WalletModalController(controller, modalInteractions: modalInteractions, closeHandler: { [weak controller] close in
        guard !isDismissingProgrammatically else {
            close()
            return
        }
        environment.verifyAlert(for: walletUIWindow(context, controller), header: strings().walletWordsControllerCancelDisablingTitle, information: strings().walletWordsControllerCancelDisablingInfo, ok: strings().walletWordsControllerCancelDisabling, cancel: strings().walletWordsControllerContinue, successHandler: { _ in
            close()
        })
    }, size: NSMakeSize(360, 0))
    dismiss = { [weak modalController] in
        isDismissingProgrammatically = true
        modalController?.close()
        isDismissingProgrammatically = false
    }

    modalController.didPopController = { _ in
        verificationStep = nil
        updateButton?()
    }

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        if verificationStep == nil {
            modalController?.close()
        } else {
            modalController?.pop(animated: true)
        }
    })

    getModalController = { [weak modalController] in
        modalController
    }
    controller.onDeinit = { [previous = controller.onDeinit] in
        previous?()
        verificationStep = nil
        updateButton = nil
    }
    updateButton = { [weak modalInteractions] in
        modalInteractions?.updateDone { button in
            if let verificationStep {
                button.set(text: verificationStep.acceptTitle, for: .Normal)
                button.isEnabled = verificationStep.isAcceptEnabled()
            } else {
                button.set(text: strings().walletWordsControllerContinue, for: .Normal)
                button.isEnabled = true
            }
        }
    }

    return (modalController, { dismiss?() })
}
