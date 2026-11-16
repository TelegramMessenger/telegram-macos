import Foundation
import Cocoa
import TGUIKit
import TelegramCore
import ObjcUtils
import Postbox
import SwiftSignalKit
import TelegramVoip
import ColorPalette
import PrivateCallScreen
import Emoji
import TelegramCallsCore
import Localization
import TelegramTheme
import AlertsUI
import SystemPermissions
import AvatarUI
import TelegramContext
import TelegramUtils
import CallVideoLayer
import AppAnalytics

private func insertSpacesBetweenEmojis(in text: String) -> String {
    var newString = ""
    var previousCharacterWasEmoji = false

    for character in text {
        if character.isEmoji {
            if previousCharacterWasEmoji {
                newString += " "
            }
            previousCharacterWasEmoji = true
        } else {
            previousCharacterWasEmoji = false
        }
        newString += String(character)
    }

    return newString
}



private func mapCallState(_ state: CallState, canBeRemoved: Bool, supportsConference: Bool) -> ExternalPeerCallState {
    
    
    let externalState: ExternalPeerCallState.State
    switch state.state {
    case .waiting:
        externalState = .waiting
    case .ringing:
        externalState = .ringing
    case .requesting(let bool):
        externalState = .requesting(ringing: bool)
    case .connecting:
        externalState = .connecting
    case .active(let startTime, let reception, let data):
        externalState = .active(startTime: startTime, reception: reception, emoji: insertSpacesBetweenEmojis(in: ObjcUtils.callEmojies(data)))
    case .reconnecting(let startTime, let reception, let data):
        externalState = .reconnecting(startTime: startTime, reception: reception, emoji: insertSpacesBetweenEmojis(in: ObjcUtils.callEmojies(data)))
    case let .terminating(callSessionTerminationReason):
        let reason: PeerCallSessionTerminationReason?
        if let callSessionTerminationReason {
            switch callSessionTerminationReason {
            case .ended(let callSessionEndedType):
                switch callSessionEndedType {
                case .hungUp:
                    reason = .ended(.hungUp)
                case .busy:
                    reason = .ended(.busy)
                case .missed:
                    reason = .ended(.missed)
                case .switchedToConference:
                    reason = .ended(.switchedToConference)
                }
            case .error(let callSessionError):
                switch callSessionError {
                case .generic:
                    reason = .error(.generic)
                case .privacyRestricted:
                    reason = .error(.privacyRestricted)
                case .notSupportedByPeer(let isVideo):
                    reason = .error(.notSupportedByPeer(isVideo: isVideo))
                case .serverProvided(let text):
                    reason = .error(.serverProvided(text: text))
                case .disconnected:
                    reason = .error(.disconnected)
                }
            }
        } else {
            reason = nil
        }
        externalState = .terminating(reason)
    case .terminated(_, let callSessionTerminationReason, _):
        let reason: PeerCallSessionTerminationReason?
        if let callSessionTerminationReason {
            switch callSessionTerminationReason {
            case .ended(let callSessionEndedType):
                switch callSessionEndedType {
                case .hungUp:
                    reason = .ended(.hungUp)
                case .busy:
                    reason = .ended(.busy)
                case .missed:
                    reason = .ended(.missed)
                case .switchedToConference:
                    reason = .ended(.switchedToConference)
                }
            case .error(let callSessionError):
                switch callSessionError {
                case .generic:
                    reason = .error(.generic)
                case .privacyRestricted:
                    reason = .error(.privacyRestricted)
                case .notSupportedByPeer(let isVideo):
                    reason = .error(.notSupportedByPeer(isVideo: isVideo))
                case .serverProvided(let text):
                    reason = .error(.serverProvided(text: text))
                case .disconnected:
                    reason = .error(.disconnected)
                }
            }
        } else {
            reason = nil
        }
        externalState = .terminated(reason)
    }
    
    let videoState: ExternalPeerCallState.VideoState
    switch state.videoState {
    case .notAvailable:
        videoState = .notAvailable
    case .inactive(let bool):
        videoState = .inactive(bool)
    case .active(let bool):
        videoState = .active(bool)
    case .paused(let bool):
        videoState = .paused(bool)
    }
    let remoteVideoState: ExternalPeerCallState.RemoteVideoState
    switch state.remoteVideoState {
    case .active:
        remoteVideoState = .active
    case .inactive:
        remoteVideoState = .inactive
    case .paused:
        remoteVideoState = .paused
    }
    
    let remoteAudioState: ExternalPeerCallState.RemoteAudioState
    switch state.remoteAudioState {
    case .active:
        remoteAudioState = .active
    case .muted:
        remoteAudioState = .muted
    }
    
    let remoteBatteryLevel: ExternalPeerCallState.RemoteBatteryLevel
    switch state.remoteBatteryLevel {
    case .normal:
        remoteBatteryLevel = .normal
    case .low:
        remoteBatteryLevel = .low
    }
    
    return .init(state: externalState, videoState: videoState, remoteVideoState: remoteVideoState, isMuted: state.isMuted, isOutgoingVideoPaused: state.isOutgoingVideoPaused, remoteAspectRatio: state.remoteAspectRatio, remoteAudioState: remoteAudioState, remoteBatteryLevel: remoteBatteryLevel, isScreenCapture: state.isScreenCapture, canBeRemoved: canBeRemoved, participants: state.participants, conferenceReference: state.conferenceReference, supportsConferenceCalls: state.supportsConferenceCalls && supportsConference)
}


public func callScreen(_ result:PCallResult, source: CallWindowSource? = nil) {
    
    switch result {
    case let .samePeer(session), let .success(session):
        
        let account = session.account
        guard let sharedContext = PhoneCallUIHooks.shared.callScreenHost(session.sharedContext) else {
            return
        }
        let ownContext:()->(any AccountContextProtocol)? = { [weak session] in
            return session?.accountContext
        }
        
        var getScreen:(()->Window?)? = nil
        
        let arguments: PeerCallArguments = PeerCallArguments(engine: session.engine, peerId: session.peerId, makeAvatar: { view, peer in
            let control = view as? AvatarControl ?? AvatarControl(font: .avatar(17))
            control.setFrameSize(NSMakeSize(120, 120))
            control.userInteractionEnabled = false
            control.setPeer(account: account, peer: peer)
            return control
        }, makeParticipants: { previous, participants in
            let view = (previous as? CallParticipantsView) ?? CallParticipantsView(frame: .zero)
            view.update(participants: participants, account: account, animated: false)
            return view
        }, toggleMute: { [weak session] in
            session?.toggleMute()
        }, toggleCamera: { [weak session] callState in
            
            guard let screen = getScreen?() else {
                return
            }
            
            switch callState.videoState {
            case let .active(available), let .paused(available), let .inactive(available):
                if available {
                    if callState.isOutgoingVideoPaused || callState.isScreenCapture || callState.videoState == .inactive(available) {
                        session?.requestVideo()
                    } else {
                        session?.disableVideo()
                    }
                } else {
                    verifyAlert_button(for: screen, information: strings().callCameraError, ok: strings().modalOK, cancel: "", option: strings().requestAccesErrorConirmSettings, successHandler: { result in
                        switch result {
                        case .thrid:
                            openSystemSettings(.camera)
                        default:
                            break
                        }
                    }, presentation: TelegramThemeHooks.shared.darkAppearance())
                }
            default:
                break
            }
            
        }, toggleScreencast: { [weak session] callState in
            
            guard let screen = getScreen?() else {
                return
            }
            let result = session?.toggleScreenCapture()
            
            if let result = result {
                switch result {
                case .permission:
                    verifyAlert_button(for: screen, information: strings().callScreenError, ok: strings().modalOK, cancel: "", option: strings().requestAccesErrorConirmSettings, successHandler: { result in
                        switch result {
                        case .thrid:
                            openSystemSettings(.sharing)
                        default:
                            break
                        }
                    }, presentation: TelegramThemeHooks.shared.darkAppearance())
                }
            }
        }, endcall: { [weak session] state in
            
            if case .ringing = state.state {
                Analytics.shared.send(AnalyticsEvents.callDecline())
            }
            
            switch state.state {
            case let .terminated(reason):
                if let reason = reason, reason.recall {
                    session?.setToRemovableState()
                }
            default:
                session?.setToRemovableState()
                _ = session?.hangUpCurrentCall().start()
            }
            
        }, recall: { [weak session] in
            guard let session = session else {
                return
            }
            let redial = phoneCall(account: session.account, sharedContext: sharedContext, window: session.window, peerId: session.peerId, ignoreSame: true) |> deliverOnMainQueue
            
            _ = redial.startStandalone(next: { result in
                callScreen(result)
            })
        }, acceptcall: { [weak session] in
            if let session {
                Analytics.shared.send(AnalyticsEvents.callAccept(video: session.isVideo))
            }
            session?.acceptCallSession()
        }, video: { [weak session] isIncoming in
            return session?.makeVideo(isIncoming: isIncoming).map { MetalVideoMakeSource(videoStreamSignal: $0) }
        }, nativeVideo: { [weak session] isIncoming, completion in
            guard let session, isNativeCallVideoRenderingAvailable else {
                completion(nil)
                return
            }
            let deliver: (OngoingCallContextPresentationCallVideoView?) -> Void = { video in
                Queue.mainQueue().async {
                    completion(video.flatMap { NativeCallVideoView(video: $0) })
                }
            }
            if isIncoming {
                session.makeIncomingVideoView(completion: deliver)
            } else {
                session.makeOutgoingVideoView(completion: deliver)
            }
        }, audioLevel: { [weak session] in
            return session?.audioLevel ?? .single(0)
        }, openSettings: { window in
            showModal(with: CallSettingsModalController(sharedContext, presentation: TelegramThemeHooks.shared.darkAppearance()), for: window)
        }, upgradeToConference: { [weak session] window in
            if let session, let context = ownContext() {
                let peerIds = [session.peerId]
                _ = PhoneCallUIHooks.shared.selectModalPeers(window, context, strings().voiceChatInviteChannelsTitle, Set(peerIds)).start(next: { [weak session, weak window] peerIds in
                    if let session, let window {
                        _ = session.upgradeToConference(invitePeerIds: peerIds, completion: { groupCall in
                            window.minSize = PhoneCallUIHooks.shared.groupCallMinFullScreenSize()
                        })
                    }
                })
            }
        })
        
        let screen: PeerCallScreen
        if let shared = sharedContext.peerCall, shared.onCompletion != nil {
            screen = shared
        } else {
            screen = PeerCallScreen(external: arguments, isConference: session.isIncomingConference)
        }
        
        
        
        screen.update(arguments: arguments)
        screen.show(source: source, animated: true)
        
        session.window = screen.window
        
        screen.contextObject = session
        
        screen.setState(combineLatest(session.state, session.canBeRemoved) |> deliverOnMainQueue |> map { state, canBeRemoved in
            return mapCallState(state, canBeRemoved: canBeRemoved, supportsConference: ownContext() != nil)
        })
        
        screen.onCompletion = {
            sharedContext.peerCall = nil
        }
        sharedContext.peerCall = screen
        
        getScreen = { [weak screen] in
            return screen?.window
        }
        
        observeCallTermination(session)
        
    default:
        break
    }
    
}

private let callTerminationDisposable = MetaDisposable()
private var observedTerminationInternalId: CallSessionInternalId?

private func observeCallTermination(_ session: PCallSession) {
    assertOnMainThread()
    if session.isIncomingConference || observedTerminationInternalId == session.internalId {
        return
    }
    observedTerminationInternalId = session.internalId
    let accountId = session.account.id
    let peerId = session.peerId
    let isVideo = session.isVideo
    let outcome = session.account.callSessionManager.callState(internalId: session.internalId)
    |> mapToSignal { callSession -> Signal<(CallTerminationOutcome, AnalyticsEvents.CallEndReason?), NoError> in
        if let outcome = callTerminationOutcome(callSession.state) {
            return .single((outcome, analyticsCallEndReason(callSession.state)))
        }
        return .complete()
    }
    |> take(1)
    let activeStart: Signal<Double?, NoError> = .single(nil) |> then(session.state |> mapToSignal { state -> Signal<Double?, NoError> in
        switch state.state {
        case let .active(startTime, _, _), let .reconnecting(startTime, _, _):
            return .single(startTime)
        default:
            return .complete()
        }
    } |> take(1))
    let terminated = combineLatest(outcome, activeStart)
    |> take(1)
    |> deliverOnMainQueue
    callTerminationDisposable.set(terminated.startStandalone(next: { [weak session] values, activeStart in
        let (outcome, reason) = values
        let duration = activeStart.flatMap { AnalyticsValues.CallDuration(bucketing: Int(CFAbsoluteTimeGetCurrent() - $0)) }
        Analytics.shared.send(AnalyticsEvents.callEnd(duration: duration, video: session?.isVideo ?? isVideo, reason: reason))
        guard let accountContext = CallsCoreHooks.shared.accountContext(accountId) else {
            return
        }
        if let error = outcome.error {
            _ = (accountContext.account.postbox.loadedPeerWithId(peerId) |> deliverOnMainQueue).startStandalone(next: { peer in
                if let text = callErrorText(error, peer: peer) {
                    alert(for: accountContext.window, info: text)
                }
            })
        }
        if let callId = outcome.ratingCallId {
            showModal(with: CallRatingModalViewController(accountContext, callId: callId, userInitiated: false, isVideo: isVideo), for: accountContext.window)
        }
    }))
}

private func analyticsCallEndReason(_ state: CallSessionState) -> AnalyticsEvents.CallEndReason? {
    guard case let .terminated(_, reason, _) = state else {
        return nil
    }
    switch reason {
    case let .ended(type):
        switch type {
        case .hungUp:
            return .hangup
        case .busy:
            return .busy
        case .missed:
            return .missed
        case .switchedToConference:
            return nil
        }
    case let .error(error):
        switch error {
        case .disconnected:
            return .disconnected
        default:
            return .failed
        }
    }
}

func callErrorText(_ error: CallSessionError, peer: Peer) -> String? {
    switch error {
    case .privacyRestricted:
        return strings().callPrivacyErrorMessage(peer.compactDisplayTitle)
    case .notSupportedByPeer:
        return strings().callParticipantVersionOutdatedError(peer.compactDisplayTitle)
    case let .serverProvided(text):
        return text
    case .generic:
        return strings().callUndefinedError
    case .disconnected:
        return nil
    }
}

public func showCallWindow(_ session: PCallSession) {
    callScreen(.success(session))
}

public func applyUIPCallResult(_ context: any AccountContextProtocol, _ result: PCallResult) {
    assertOnMainThread()
    callScreen(result, source: CallWindowSource.underCursor())
}
