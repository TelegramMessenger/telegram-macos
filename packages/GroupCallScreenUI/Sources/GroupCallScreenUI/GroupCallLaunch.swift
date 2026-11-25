import Cocoa
import Postbox
import TelegramCore
import InAppSettings
import SwiftSignalKit
import AVFoundation
import TGUIKit
import TelegramMedia
import TgVoipWebrtc
import TelegramCallsCore
import TelegramContext
import TelegramTheme
import Localization
import AlertsUI
import CallsUI

public func getGroupCallPanelData(context: any AccountContextProtocol, peerId: PeerId) -> Signal<GroupCallPanelData?, NoError> {
    let account = context.account
    let availableGroupCall: Signal<GroupCallPanelData?, NoError>
    if peerId.namespace == Namespaces.Peer.CloudChannel || peerId.namespace == Namespaces.Peer.CloudGroup {
        availableGroupCall = context.account.viewTracker.peerView(peerId)
                        |> map { peerView -> (CachedChannelData.ActiveCall?, Bool) in
                            if let cachedData = peerView.cachedData as? CachedChannelData {
                                return (cachedData.activeCall, peerViewMainPeer(peerView)?.isChannel == true)
                            }
                            if let cachedData = peerView.cachedData as? CachedGroupData {
                                return (cachedData.activeCall, false)
                            }
                            return (nil, false)
                        } |> mapToSignal { (activeCall, isChannel) -> Signal<GroupCallPanelData?, NoError> in
                               guard let activeCall = activeCall else {
                                   return .single(nil)
                               }
                                return GroupCallScreenUIHooks.shared.groupCallContext(context.sharedContext) |> mapToSignal { groupCall in
                                    if let context = groupCall, context.call.peerId == peerId && context.call.account.id == account.id {
                                        return context.call.summaryState
                                            |> map { summary -> GroupCallPanelData in
                                                if let summary = summary {
                                                    return GroupCallPanelData(
                                                        peerId: peerId,
                                                        isChannel: isChannel,
                                                        info: summary.info,
                                                        topParticipants: summary.topParticipants,
                                                        participantCount: summary.participantCount,
                                                        activeSpeakers: summary.activeSpeakers,
                                                        groupCall: context
                                                    )
                                                } else {
                                                    return GroupCallPanelData(peerId: peerId, isChannel: isChannel, info: nil, topParticipants: [], participantCount: 0, activeSpeakers: [], groupCall: context)
                                                }
                                            }
                                    } else {
                                        return Signal { subscriber in
                                            let disposable = MetaDisposable()
                                            let callContext = GroupCallScreenUIHooks.shared.cachedGroupCallContexts(context)
                                            callContext.impl.syncWith { impl in
                                                let callContext = impl.get(account: context.account, engine: context.engine, peerId: peerId, isChannel: isChannel, call: .init(activeCall), isMuted: true, e2eContext: nil)
                                                disposable.set((callContext.context.panelData
                                                |> deliverOnMainQueue).start(next: { panelData in
                                                    callContext.keep()
                                                    subscriber.putNext(panelData)
                                                }))
                                            }
                                            return disposable
                                        }
                                    }
                                }
                           }

    } else {
        availableGroupCall = .single(nil)
    }
    return availableGroupCall
}

public func requestOrJoinGroupCall(context: any AccountContextProtocol, peerId: PeerId?, joinAs: PeerId, initialCall: CachedChannelData.ActiveCall?, initialInfo: GroupCallInfo? = nil, joinHash: String? = nil, conferenceFromCallId: CallId? = nil, isConference: Bool = false, reference: InternalGroupCallReference?) -> Signal<RequestOrJoinGroupCallResult, NoError> {
    let sharedContext = context.sharedContext
    let accounts = context.sharedContext.activeAccounts |> take(1)
    let account = context.account

    if let peerId {
        return combineLatest(queue: .mainQueue(), accounts, account.postbox.loadedPeerWithId(peerId)) |> mapToSignal { accounts, peer in
            if let context = GroupCallScreenUIHooks.shared.getCrossAccountGroupCall(context.sharedContext), context.call.peerId == peerId, context.call.account.id == account.id {
                return .single(.samePeer(context))
            } else {
                return makeNewCallConfirmation(accountContext: context, newPeerId: peerId, newCallType: .voiceChat)
                |> mapToSignal { _ in
                    return sharedContext.endCurrentCall()
                } |> map { _ in
                    let call: CachedChannelData.ActiveCall?
                    if let info = initialInfo {
                        call = .init(id: info.id, accessHash: info.accessHash, title: info.title, scheduleTimestamp: info.scheduleTimestamp, subscribedToScheduled: info.subscribedToScheduled, isStream: info.isStream)
                    } else {
                        call = initialCall
                    }
                    return .success(startGroupCall(context: context, peerId: peerId, joinAs: joinAs, initialCall: call, initialInfo: initialInfo, joinHash: joinHash, peer: peer, conferenceFromCallId: conferenceFromCallId, isConference: isConference, isChannel: peer.isChannel, reference: reference))
                }
            }
        }
    } else {
        return .complete()
    }
}

public func requestOrJoinConferenceCall(context: any AccountContextProtocol, initialInfo: GroupCallInfo, reference: InternalGroupCallReference) -> Signal<RequestOrJoinGroupCallResult, NoError> {
    let sharedContext = context.sharedContext
    let accounts = context.sharedContext.activeAccounts |> take(1)
    let account = context.account

    let joinAs = context.peerId
    
    let conferenceFromCallId: CallId = .init(id: initialInfo.id, accessHash: initialInfo.accessHash)

    return accounts |> mapToSignal { accounts in
        if let context = GroupCallScreenUIHooks.shared.getCrossAccountGroupCall(context.sharedContext), context.call.callId == conferenceFromCallId.id, context.call.account.id == account.id {
            return .single(.samePeer(context))
        } else {
            return makeNewCallConfirmation(accountContext: context, newPeerId: nil, newCallType: .voiceChat)
            |> mapToSignal { _ in
                return sharedContext.endCurrentCall()
            } |> map { _ in
                let call: CachedChannelData.ActiveCall?
                call = .init(id: initialInfo.id, accessHash: initialInfo.accessHash, title: initialInfo.title, scheduleTimestamp: initialInfo.scheduleTimestamp, subscribedToScheduled: initialInfo.subscribedToScheduled, isStream: initialInfo.isStream)

                return .success(startGroupCall(context: context, peerId: nil, joinAs: joinAs, initialCall: call, initialInfo: initialInfo, peer: nil, conferenceFromCallId: conferenceFromCallId, isConference: true, isChannel: false, reference: reference))
            }
        }
    }

}


private func startGroupCall(context: any AccountContextProtocol, peerId: PeerId?, joinAs: PeerId, initialCall: CachedChannelData.ActiveCall?, initialInfo: GroupCallInfo? = nil, internalId: CallSessionInternalId = CallSessionInternalId(), joinHash: String? = nil, peer: Peer? = nil, conferenceFromCallId: CallId?, isConference: Bool, isChannel: Bool, reference: InternalGroupCallReference?) -> GroupCallContext {
    
    let keyPair: TelegramKeyPair? = isConference ? TelegramE2EEncryptionProviderImpl.shared.generateKeyPair() : nil
    
    var initial: (description: EngineGroupCallDescription, reference: InternalGroupCallReference)?
    
    if let initialCall, let reference {
        initial = (EngineGroupCallDescription(
            id: initialCall.id,
            accessHash: initialCall.accessHash,
            title: initialCall.title,
            scheduleTimestamp: initialCall.scheduleTimestamp,
            subscribedToScheduled: initialCall.subscribedToScheduled,
            isStream: initialCall.isStream
        ), reference)
    } else if let initialInfo {
        initial = (EngineGroupCallDescription(
            id: initialInfo.id,
            accessHash: initialInfo.accessHash,
            title: initialInfo.title,
            scheduleTimestamp: initialInfo.scheduleTimestamp,
            subscribedToScheduled: initialInfo.subscribedToScheduled,
            isStream: initialInfo.isStream
        ), .id(id: initialInfo.id, accessHash: initialInfo.accessHash))
    } else if let initialCall {
        initial = (EngineGroupCallDescription(
            id: initialCall.id,
            accessHash: initialCall.accessHash,
            title: initialCall.title,
            scheduleTimestamp: initialCall.scheduleTimestamp,
            subscribedToScheduled: initialCall.subscribedToScheduled,
            isStream: initialCall.isStream
        ), .id(id: initialCall.id, accessHash: initialCall.accessHash))
    }
    
    
    return GroupCallContext(call: PresentationGroupCallImpl(accountContext: context, initialCall: initial, internalId: internalId, peerId: peerId, isChannel: isChannel, invite: joinHash, joinAsPeerId: joinAs, initialInfo: initialInfo, isStream: initialInfo?.isStream ?? initialCall?.isStream ?? false, streamPeerId: peerId, keyPair: keyPair, conferenceSourceId: nil, isConference: isConference, initialOutput: .init(isMuted: true), isLiveStream: false), peerMemberContextsManager: context.peerChannelMemberCategoriesContextsManager, window: makeGroupWindow(isStream: false))
}

public func createVoiceChat(context: any AccountContextProtocol, peerId: PeerId, displayAsList: [FoundPeer]? = nil, canBeScheduled: Bool = false) {
    let confirmation = combineLatest(queue: .mainQueue(), makeNewCallConfirmation(accountContext: context, newPeerId: peerId, newCallType: .voiceChat), context.account.postbox.loadedPeerWithId(peerId)) |> mapToSignalPromotingError { _, peer in
        return Signal<(GroupCallInfo?, PeerId), CreateGroupCallError> { subscriber in

            let disposable = MetaDisposable()

            let create:(PeerId, Date?, Bool)->Void = { joinAs, schedule, isStream in
                let scheduleDate: Int32?
                if let timeInterval = schedule?.timeIntervalSince1970 {
                    scheduleDate = Int32(timeInterval)
                } else {
                    scheduleDate = nil
                }
                disposable.set(context.engine.calls.createGroupCall(peerId: peerId, title: nil, scheduleDate: scheduleDate, isExternalStream: isStream).start(next: { info in
                    subscriber.putNext((info, joinAs))
                    subscriber.putCompletion()
                }, error: { error in
                    subscriber.putError(error)
                }))
            }
            if let displayAsList = displayAsList {
                if displayAsList.count > 1 || canBeScheduled {
                    showModal(with: GroupCallDisplayAsController(context: context, mode: .create, peerId: peerId, list: displayAsList, completion: create, canBeScheduled: canBeScheduled, isCreator: peer.groupAccess.isCreator), for: context.window)
                } else {
                    create(context.peerId, nil, false)
                }
            } else {
                selectGroupCallJoiner(context: context, peerId: peerId, completion: create, canBeScheduled: canBeScheduled)
            }

            return ActionDisposable {
                disposable.dispose()
            }
        } |> runOn(.mainQueue())
    }

    let requestCall: Signal<RequestOrJoinGroupCallResult, CreateGroupCallError> = confirmation |> mapToSignal { call, joinAs in
        
        let initialCall: CachedChannelData.ActiveCall?
        if let call = call {
            initialCall = .init(id: call.id, accessHash: call.accessHash, title: call.title, scheduleTimestamp: call.scheduleTimestamp, subscribedToScheduled: call.subscribedToScheduled, isStream: call.isStream)
        } else {
            initialCall = nil
        }
        
        return requestOrJoinGroupCall(context: context, peerId: peerId, joinAs: joinAs, initialCall: initialCall, reference: nil)
        |> castError(CreateGroupCallError.self)
    } |> deliverOnMainQueue
    
    _ = requestCall.start(next: { result in
        switch result {
        case let .success(callContext), let .samePeer(callContext):
            applyGroupCallResult(context.sharedContext, callContext)
        default:
            alert(for: context.window, info: strings().errorAnError)
        }
    }, error: { error in
        if case .anonymousNotAllowed = error {
            alert(for: context.window, info: strings().voiceChatAnonymousDisabledAlertText)
        } else {
            alert(for: context.window, info: strings().errorAnError)
        }
    })
}
