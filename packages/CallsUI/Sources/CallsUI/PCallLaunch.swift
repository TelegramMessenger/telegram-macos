import Cocoa
import SwiftSignalKit
import TelegramCore
import InAppSettings
import Postbox
import TGUIKit
import CoreGraphics
import TelegramVoip
import TelegramCallsCore
import AlertsUI
import SystemPermissions
import TelegramUtils
import Localization
import TelegramContext
import AppAnalytics

public enum PCallResult {
    case success(PCallSession)
    case fail
    case samePeer(PCallSession)
}

public func phoneCall(context: any AccountContextProtocol, peerId:PeerId, ignoreSame:Bool = false, isVideo: Bool = false) -> Signal<PCallResult, NoError> {
    return phoneCall(account: context.account, sharedContext: context.sharedContext, window: context.window, peerId: peerId, ignoreSame: ignoreSame, isVideo: isVideo)
}

public func phoneCall(account: Account, sharedContext: any SharedAccountContextProtocol, window: Window?, peerId:PeerId, ignoreSame:Bool = false, isVideo: Bool = false) -> Signal<PCallResult, NoError> {
    
    let alertWindow = window ?? CallsCoreHooks.shared.activeWindow()
    
    let signal: Signal<(Bool, Bool?), NoError>
    if isVideo {
        signal = combineLatest(queue: .mainQueue(), requestMicrophonePermission(), requestCameraPermission() |> map(Optional.init))
    } else {
        signal = combineLatest(queue: .mainQueue(), requestMicrophonePermission(), .single(nil))
    }
    
    
    var isVideoPossible = account.postbox.transaction { transaction -> VideoCallsConfiguration in
        let appConfiguration: AppConfiguration = transaction.getPreferencesEntry(key: PreferencesKeys.appConfiguration)?.get(AppConfiguration.self) ?? AppConfiguration.defaultValue
        return VideoCallsConfiguration(appConfiguration: appConfiguration)
    }
    |> map { callsConfiguration -> Bool in
        let isVideoPossible: Bool
        switch callsConfiguration.videoCallsSupport {
        case .disabled:
            isVideoPossible = isVideo
        case .full:
            isVideoPossible = true
        case .onlyVideo:
            isVideoPossible = isVideo
        }
        return isVideoPossible
    }
    
    isVideoPossible = combineLatest(isVideoPossible, account.postbox.transaction {
        ($0.getPeerCachedData(peerId: peerId) as? CachedUserData)?.videoCallsAvailable ?? true
    }) |> map {
        $0.0 && $0.1
    }
    
    let accounts = sharedContext.activeAccounts |> take(1)
    
    
    return combineLatest(queue: .mainQueue(), signal, isVideoPossible, accounts) |> mapToSignal { values -> Signal<PCallResult, NoError> in
        
        let (microAccess, _) = values.0
        let isVideoPossible = values.1
        let activeAccounts = values.2
        
        for activeAccount in activeAccounts.accounts {
            if activeAccount.1.peerId == peerId {
                if let alertWindow {
                    alert(for: alertWindow, info: strings().callSameDeviceError)
                }
                return .complete()
            }
        }
        if microAccess {
            return makeNewCallConfirmation(sharedContext: sharedContext, account: account, window: alertWindow, newPeerId: peerId, newCallType: .call, ignoreSame: ignoreSame) |> mapToSignal { value -> Signal<Bool, NoError> in
                if ignoreSame {
                    return .single(value)
                } else {
                    return sharedContext.endCurrentCall()
                }
            } |> mapToSignal { _ in
                return account.callSessionManager.request(peerId: peerId, isVideo: isVideo, enableVideo: isVideoPossible)
            }
            |> mapToSignal { id in
                return getPrivateCallSessionData(account, accountManager: sharedContext.accountManager, peerId: peerId) |> map {
                    (id, $0)
                }
            }
            |> deliverOnMainQueue
            |> map { id, data in
                Analytics.shared.send(AnalyticsEvents.callStart(video: isVideo))
                return .success(PCallSession(sharedContext: sharedContext, account: account, isOutgoing: true, incomingConferenceSource: nil, incomingParticipants: [], peerId: peerId, id: id, initialState: nil, startWithVideo: isVideo, isVideoPossible: isVideoPossible, data: data))
            }
        } else {
            if let alertWindow {
                verifyAlert_button(for: alertWindow, information: strings().requestAccesErrorHaveNotAccessCall, ok: strings().modalOK, cancel: "", option: strings().requestAccesErrorConirmSettings, successHandler: { result in
                    switch result {
                    case .thrid:
                        openSystemSettings(.microphone)
                    default:
                        break
                    }
                })
            }
            return .complete()
        }
    }
}

public enum CallConfirmationType {
    case call
    case voiceChat
}

public func makeNewCallConfirmation(accountContext: any AccountContextProtocol, newPeerId: PeerId?, newCallType: CallConfirmationType, ignoreSame: Bool = false) -> Signal<Bool, NoError> {
    return makeNewCallConfirmation(sharedContext: accountContext.sharedContext, account: accountContext.account, window: accountContext.window, newPeerId: newPeerId, newCallType: newCallType, ignoreSame: ignoreSame)
}

public func makeNewCallConfirmation(sharedContext: any SharedAccountContextProtocol, account: Account, window: Window?, newPeerId: PeerId?, newCallType: CallConfirmationType, ignoreSame: Bool = false) -> Signal<Bool, NoError> {
    if sharedContext.hasActiveCall {
        let currentCallType: CallConfirmationType
        let currentPeerId: PeerId?
        let currentAccount: Account
        if let session = PhoneCallUIHooks.shared.getCrossAccountCallSession(sharedContext) {
            currentPeerId = session.peerId
            currentAccount = session.account
            currentCallType = .call
        } else if let groupCall = PhoneCallUIHooks.shared.getCrossAccountGroupCall(sharedContext) {
            currentPeerId = groupCall.call.peerId
            currentAccount = groupCall.call.account
            currentCallType = .voiceChat
        } else {
            fatalError("wtf")
        }
        if ignoreSame, newPeerId == currentPeerId {
            return .single(true)
        }
        let from = currentAccount.postbox.transaction { transaction in
            if let currentPeerId {
                return transaction.getPeer(currentPeerId)
            } else {
                return nil
            }
        }
        let to: Signal<Peer?, NoError>
        if let newPeerId {
            to = account.postbox.transaction {
                return $0.getPeer(newPeerId)
            }
        } else {
            to = .single(nil)
        }
        
        return combineLatest(from, to) |> map { (from: $0, to: $1) }
        |> deliverOnMainQueue
        |> mapToSignal { values in
            let header: String
            let text: String
            switch currentCallType {
            case .call:
                header = strings().callConfirmDiscardCallHeader
            case .voiceChat:
                header = strings().callConfirmDiscardVoiceHeader
            }
            switch newCallType {
            case .call:
                switch currentCallType {
                case .call:
                    text = strings().callConfirmDiscardCallToCallText(values.from?.displayTitle ?? "", values.to?.displayTitle ?? "")
                case .voiceChat:
                    text = strings().callConfirmDiscardVoiceToCallText(values.from?.displayTitle ?? "", values.to?.displayTitle ?? "")
                }
            case .voiceChat:
                switch currentCallType {
                case .call:
                    text = strings().callConfirmDiscardCallToVoiceText(values.from?.displayTitle ?? "", values.to?.displayTitle ?? "")
                case .voiceChat:
                    text = strings().callConfirmDiscardVoiceToVoiceText(values.from?.displayTitle ?? "", values.to?.displayTitle ?? "")
                }
            }
            guard let window = window ?? CallsCoreHooks.shared.activeWindow() else {
                return .single(false)
            }
            return verifyAlertSignal(for: window, header: header, information: text, ok: strings().modalYes, cancel: strings().modalCancel)
            |> filter { $0 == .basic }
            |> map { _ in true }
        }
    } else {
        return .single(true)
    }
}
