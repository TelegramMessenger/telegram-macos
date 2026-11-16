import Foundation
import TGUIKit
import SwiftSignalKit
import TelegramContext
import WalletContext
import PasscodeCore
import Localization

let walletRestoreFlowReason = strings().walletFlowAuthorizationRestoreReason
let walletConfirmAccessFlowReason = strings().walletFlowAuthorizationConfirmAccessReason

@available(macOS 10.15, *)
final class WalletFlowAuthorization {
    private let walletContext: WalletContext
    private let reason: String
    private var session: PasscodeSession?
    private(set) var generation: UInt64 = 0

    init(walletContext: WalletContext, reason: String) {
        self.walletContext = walletContext
        self.reason = reason
    }

    deinit {
        session?.invalidate()
    }

    var currentSession: PasscodeSession? {
        guard let session, session.isValid else {
            return nil
        }
        return session
    }

    func isCurrent(_ generation: UInt64) -> Bool {
        return self.generation == generation
    }

    func authorize() -> Signal<PasscodeSession, WalletContext.WalletError> {
        if let session = currentSession {
            return .single(session)
        }
        let generation = self.generation
        return walletContext.beginWalletFlow(reason: reason)
        |> deliverOnMainQueue
        |> mapToSignal { [weak self] session -> Signal<PasscodeSession, WalletContext.WalletError> in
            guard let self, self.generation == generation else {
                session.invalidate()
                return .fail(.authorizationCancelled)
            }
            self.session?.invalidate()
            self.session = session
            return .single(session)
        }
    }

    func end() {
        generation &+= 1
        session?.invalidate()
        session = nil
    }
}

@available(macOS 10.15, *)
func presentWalletRestoreError(environment: WalletUIEnvironment, _ error: WalletContext.WalletError, window: Window, retry: @escaping () -> Void, cancel: @escaping () -> Void) {
    guard error != .authorizationCancelled else {
        cancel()
        return
    }
    let message = walletAuthorizationErrorMessage(error) ?? (title: strings().walletFlowAuthorizationRestoreFailedTitle, text: strings().walletFlowAuthorizationCheckConnection)
    environment.verifyAlert(for: window, header: message.title, information: message.text, ok: strings().walletFlowAuthorizationRetry, cancel: strings().walletFlowAuthorizationCancel, successHandler: { _ in
        retry()
    }, cancelHandler: cancel)
}

@available(macOS 10.15, *)
func walletRestoreSigningAccess(
    context: any AccountContextProtocol,
    environment: WalletUIEnvironment,
    window: Window,
    walletContext: WalletContext,
    authorization: WalletFlowAuthorization,
    retry: @escaping () -> Void,
    next: @escaping () -> Void,
    failed: @escaping () -> Void
) -> Disposable {
    let generation = authorization.generation
    return performWalletAuthorizedOperation(context: context, environment: environment, window: window, operation: { password -> Signal<[String], WalletContext.WalletError> in
        guard authorization.isCurrent(generation) else {
            return .fail(.authorizationCancelled)
        }
        return authorization.authorize()
        |> mapToSignal { session in
            walletContext.recoveryPhrase(password: password, session: session)
        }
    }, next: { _ in
        guard authorization.isCurrent(generation) else {
            return
        }
        authorization.end()
        next()
    }, failed: { error in
        guard authorization.isCurrent(generation) else {
            return
        }
        presentWalletRestoreError(environment: environment, error, window: window, retry: {
            guard authorization.isCurrent(generation) else {
                return
            }
            retry()
        }, cancel: {
            guard authorization.isCurrent(generation) else {
                return
            }
            authorization.end()
            failed()
        })
    })
}

@available(macOS 10.15, *)
public func walletEnsureSigningAccess(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, window: Window, next: @escaping () -> Void) {
    guard case let .wallet(info) = walletContext.stateValue.phase, !info.canSign else {
        next()
        return
    }
    if info.canExportPhrase {
        let authorization = WalletFlowAuthorization(walletContext: walletContext, reason: walletRestoreFlowReason)
        let disposable = MetaDisposable()
        var restore: (() -> Void)?
        restore = {
            disposable.set(walletRestoreSigningAccess(context: context, environment: environment, window: window, walletContext: walletContext, authorization: authorization, retry: {
                restore?()
            }, next: {
                restore = nil
                next()
            }, failed: {
                restore = nil
            }))
        }
        restore?()
    } else {
        environment.verifyAlert(for: window, header: strings().walletTransactionControllerSecretPhraseRequiredTitle, information: strings().walletTonConnectSecretPhraseRequiredInfo, ok: strings().walletTransactionControllerProceed, cancel: strings().walletTransactionControllerCancel, successHandler: { _ in
            showModal(with: WalletImportController(context: context, environment: environment, walletContext: walletContext, mode: .enterRecoveryPhrase, onImported: next), for: window)
        })
    }
}
