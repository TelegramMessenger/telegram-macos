import Cocoa
import Metal
import Postbox
import TelegramCore
import InAppSettings
import SwiftSignalKit
import AVFoundation
import TelegramVoip
import TGUIKit
import CallVideoLayer
import TgVoipWebrtc
import TdBinding
import Localization
import ColorPalette
import TelegramContext
import TelegramUtils
import TelegramMediaUtils
import SystemPermissions
import ProxyUtils



private enum CurrentImpl {
    case call(OngoingGroupCallContext)
    case stream(GroupCallStreamPlayer)
}

private extension CurrentImpl {
    var joinPayload: Signal<(String, UInt32), NoError> {
        switch self {
        case let .call(callContext):
            return callContext.joinPayload
        case .stream:
            let ssrcId = UInt32.random(in: 1 ..< UInt32(Int32.max - 1))
            let dict: [String: Any] = [
                "fingerprints": [] as [Any],
                "ufrag": "",
                "pwd": "",
                "ssrc": Int32(bitPattern: ssrcId),
                "ssrc-groups": [] as [Any]
            ]
            guard let jsonString = (try? JSONSerialization.data(withJSONObject: dict, options: [])).flatMap({ String(data: $0, encoding: .utf8) }) else {
                return .never()
            }
            return .single((jsonString, ssrcId))
        }
    }
    
    var networkState: Signal<OngoingGroupCallContext.NetworkState, NoError> {
        switch self {
        case let .call(callContext):
            return callContext.networkState
        case let .stream(player):
            return player.networkState
        }
    }
    
    var audioLevels: Signal<[(OngoingGroupCallContext.AudioLevelKey, Float, Bool)], NoError> {
        switch self {
        case let .call(callContext):
            return callContext.audioLevels
        case .stream:
            return .single([])
        }
    }
    
}

private final class ConferenceCallE2EContextStateImpl: ConferenceCallE2EContextState {
    private let call: TdCall

    public init(call: TdCall) {
        self.call = call
    }

    public func getEmojiState() -> Data? {
        return self.call.emojiState()
    }
    
    public func getParticipantLatencies() -> [Int64: Double] {
        let dict = self.call.participantLatencies()
        var result: [Int64: Double] = [:]
        for (k, v) in dict {
            result[k.int64Value] = v.doubleValue
        }
        return result
    }
    
    public func getParticipants() -> [ConferenceCallE2EContext.BlockchainParticipant] {
        return self.call.participants().map { ConferenceCallE2EContext.BlockchainParticipant(userId: $0.userId, internalId: $0.internalId) }
    }

    public func getParticipantIds() -> [Int64] {
        return self.call.participants().map { $0.userId }
    }

    public func applyBlock(block: Data) -> Bool {
        return self.call.applyBlock(block)
    }

    public func applyBroadcastBlock(block: Data) {
        self.call.applyBroadcastBlock(block)
    }

    public func generateRemoveParticipantsBlock(participantIds: [Int64]) -> Data? {
        return self.call.generateRemoveParticipantsBlock(participantIds.map { $0 as NSNumber })
    }

    public func takeOutgoingBroadcastBlocks() -> [Data] {
        return self.call.takeOutgoingBroadcastBlocks()
    }

    public func encrypt(message: Data, channelId: Int32, plaintextPrefixLength: Int) -> Data? {
        return self.call.encrypt(message, channelId: channelId, plaintextPrefixLength: plaintextPrefixLength)
    }


    public func decrypt(message: Data, userId: Int64) -> Data? {
        return self.call.decrypt(message, userId: userId)
    }
}

public class OngoingGroupCallEncryptionContextImpl: OngoingGroupCallEncryptionContext {
    private let e2eCall: Atomic<ConferenceCallE2EContext.ContextStateHolder>
    private let channelId: Int32
    
    public init(e2eCall: Atomic<ConferenceCallE2EContext.ContextStateHolder>, channelId: Int32) {
        self.e2eCall = e2eCall
        self.channelId = channelId
    }
    
    public func encrypt(message: Data, plaintextPrefixLength: Int) -> Data? {
        let channelId = self.channelId
        return self.e2eCall.with({ $0.state?.encrypt(message: message, channelId: channelId, plaintextPrefixLength: plaintextPrefixLength) })
    }

    
    public func decrypt(message: Data, userId: Int64) -> Data? {
        return self.e2eCall.with({ $0.state?.decrypt(message: message, userId: userId) })
    }
}




public final class TelegramE2EEncryptionProviderImpl: TelegramE2EEncryptionProvider {
    public static let shared = TelegramE2EEncryptionProviderImpl()
    
    public func generateKeyPair() -> TelegramKeyPair? {
        guard let keyPair = TdKeyPair.generate() else {
            return nil
        }
        guard let publicKey = TelegramPublicKey(data: keyPair.publicKey) else {
            return nil
        }
        return TelegramKeyPair(id: keyPair.keyId, publicKey: publicKey)
    }
    
    public func generateCallZeroBlock(keyPair: TelegramKeyPair, userId: Int64) -> Data? {
        guard let keyPair = TdKeyPair(keyId: keyPair.id, publicKey: keyPair.publicKey.data) else {
            return nil
        }
        return tdGenerateZeroBlock(keyPair, userId)
    }
}



public func groupCallLogsPath(account: Account) -> String {
    return account.basePath + "/group-calls"
}

public func allocateCallLogPath(account: Account) -> String {
    let path = groupCallLogsPath(account: account)
    
    let _ = try? FileManager.default.createDirectory(at: URL(fileURLWithPath: path), withIntermediateDirectories: true, attributes: nil)
    
    let name = "log-\(Date())".replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
    
    return "\(path)/\(name).log"
}


private final class PendingConferenceInvitationContext {
    public enum State {
        case ringing
    }
    
    private let engine: TelegramEngine
    private var requestDisposable: Disposable?
    private var stateDisposable: Disposable?
    public private(set) var messageId: EngineMessage.Id?
    
    private var hadMessage: Bool = false
    private var didNotifyEnded: Bool = false
    
    public init(engine: TelegramEngine, reference: InternalGroupCallReference, peerId: PeerId, isVideo: Bool, onStateUpdated: @escaping (State) -> Void, onEnded: @escaping (Bool) -> Void, onError: @escaping (InviteConferenceCallParticipantError) -> Void) {
        self.engine = engine
        self.requestDisposable = (engine.calls.inviteConferenceCallParticipant(reference: reference, peerId: peerId, isVideo: isVideo) |> deliverOnMainQueue).startStrict(next: { [weak self] messageId in
            guard let self else {
                return
            }

            self.messageId = messageId
            
            onStateUpdated(.ringing)
            
            let timeout: Double = 30.0
            let timerSignal = Signal<Void, NoError>.single(Void()) |> then(
                Signal<Void, NoError>.single(Void())
                |> delay(1.0, queue: .mainQueue())
            ) |> restart
            
            let startTime = CFAbsoluteTimeGetCurrent()
            self.stateDisposable = (combineLatest(queue: .mainQueue(),
                engine.data.subscribe(
                    TelegramEngine.EngineData.Item.Messages.Message(id: messageId)
                ),
                timerSignal
            )
            |> deliverOnMainQueue).startStrict(next: { [weak self] message, _ in
                guard let self else {
                    return
                }
                if let message {
                    self.hadMessage = true
                    if message.timestamp + Int32(timeout) <= Int32(Date().timeIntervalSince1970) {
                        if !self.didNotifyEnded {
                            self.didNotifyEnded = true
                            onEnded(false)
                        }
                    } else {
                        var isActive = false
                        var isAccepted = false
                        var foundAction: TelegramMediaAction?
                        for media in message.media {
                            if let action = media as? TelegramMediaAction {
                                foundAction = action
                                break
                            }
                        }
                        
                        if let action = foundAction, case let .conferenceCall(conferenceCall) = action.action {
                            if conferenceCall.flags.contains(.isMissed) || conferenceCall.duration != nil {
                            } else {
                                if conferenceCall.flags.contains(.isActive) {
                                    isAccepted = true
                                } else {
                                    isActive = true
                                }
                            }
                        }
                        if !isActive {
                            if !self.didNotifyEnded {
                                self.didNotifyEnded = true
                                onEnded(isAccepted)
                            }
                        }
                    }
                } else {
                    if self.hadMessage || CFAbsoluteTimeGetCurrent() > startTime + 1.0 {
                        if !self.didNotifyEnded {
                            self.didNotifyEnded = true
                            onEnded(false)
                        }
                    }
                }
            })
        }, error: { [weak self] error in
            guard let self, !self.didNotifyEnded else {
                return
            }
            self.didNotifyEnded = true
            onError(error)
            onEnded(false)
        })
    }
    
    deinit {
        self.requestDisposable?.dispose()
        self.stateDisposable?.dispose()
    }
}




public protocol AccountGroupCallContext {
}

public protocol AccountGroupCallContextCache {
}



public final class AccountGroupCallContextImpl: AccountGroupCallContext {
    public final class Proxy {
        public let context: AccountGroupCallContextImpl
        public let removed: () -> Void
        
        public init(context: AccountGroupCallContextImpl, removed: @escaping () -> Void) {
            self.context = context
            self.removed = removed
        }
        
        deinit {
            self.removed()
        }
        
        public func keep() {
        }
    }
    
    public var disposable: Disposable?
    public var participantsContext: GroupCallParticipantsContext?
    
    private let panelDataPromise = Promise<GroupCallPanelData?>()
    public var panelData: Signal<GroupCallPanelData?, NoError> {
        return self.panelDataPromise.get()
    }
    
    public init(account: Account, engine: TelegramEngine, peerId: PeerId?, isChannel: Bool, call: EngineGroupCallDescription, isMuted: Bool, e2eContext: ConferenceCallE2EContext?) {
        self.panelDataPromise.set(.single(nil))
        let state = engine.calls.getGroupCallParticipants(reference: .id(id: call.id, accessHash: call.accessHash), offset: "", ssrcs: [], limit: 100, sortAscending: nil)
        |> map(Optional.init)
        |> `catch` { _ -> Signal<GroupCallParticipantsContext.State?, NoError> in
            return .single(nil)
        }
        
        let peer: Signal<EnginePeer?, NoError>
        if let peerId {
            peer = engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        } else {
            peer = .single(nil)
        }
        self.disposable = (combineLatest(queue: .mainQueue(),
            state,
            peer
        )
        |> deliverOnMainQueue).start(next: { [weak self] state, peer in
            guard let self, let state = state else {
                return
            }
            let context = engine.calls.groupCall(
                peerId: peerId,
                myPeerId: account.peerId,
                id: call.id,
                reference: .id(id: call.id, accessHash: call.accessHash),
                state: state,
                previousServiceState: nil,
                e2eContext: e2eContext
            )
            
            self.participantsContext = context
            
            if !isMuted {
                self.participantsContext?.updateMuteState(peerId: account.peerId, muteState: nil, volume: nil, raiseHand: nil)
            }
            
            
            if let peerId {
                self.panelDataPromise.set(combineLatest(queue: .mainQueue(),
                    context.state,
                    context.activeSpeakers
                )
                |> map { state, activeSpeakers -> GroupCallPanelData in
                    var topParticipants: [GroupCallParticipantsContext.Participant] = []
                    for participant in state.participants {
                        if topParticipants.count >= 3 {
                            break
                        }
                        topParticipants.append(participant)
                    }
                    
                    var isChannel = false
                    if let peer = peer, case let .channel(channel) = peer, case .broadcast = channel.info {
                        isChannel = true
                    }
                    
                    return GroupCallPanelData(
                        peerId: peerId,
                        isChannel: isChannel,
                        info: GroupCallInfo(
                            id: call.id,
                            accessHash: call.accessHash,
                            participantCount: state.totalCount,
                            streamDcId: nil,
                            title: state.title,
                            scheduleTimestamp: state.scheduleTimestamp,
                            subscribedToScheduled: state.subscribedToScheduled,
                            recordingStartTimestamp: nil,
                            sortAscending: state.sortAscending,
                            defaultParticipantsAreMuted: state.defaultParticipantsAreMuted,
                            messagesAreEnabled: state.messagesAreEnabled,
                            isVideoEnabled: state.isVideoEnabled,
                            unmutedVideoLimit: state.unmutedVideoLimit,
                            isStream: state.isStream,
                            isCreator: state.isCreator,
                            defaultSendAs: state.defaultSendAs
                        ),
                        topParticipants: topParticipants,
                        participantCount: state.totalCount,
                        activeSpeakers: activeSpeakers,
                        groupCall: nil
                    )
                })
            }
        })
    }
    
    deinit {
        self.disposable?.dispose()
    }
}


public final class AccountGroupCallContextCacheImpl: AccountGroupCallContextCache {
    public class Impl {
        private class Record {
            public let context: AccountGroupCallContextImpl
            public let subscribers = Bag<Void>()
            public var removeTimer: SwiftSignalKit.Timer?
            
            public init(context: AccountGroupCallContextImpl) {
                self.context = context
            }
        }
        
        private let queue: Queue
        private var contexts: [Int64: Record] = [:]

        private let leaveDisposables = DisposableSet()
        
        public init(queue: Queue) {
            self.queue = queue
        }
        
        public func get(account: Account, engine: TelegramEngine, peerId: PeerId, isChannel: Bool, call: EngineGroupCallDescription, isMuted: Bool, e2eContext: ConferenceCallE2EContext?) -> AccountGroupCallContextImpl.Proxy {
            let result: Record
            if let current = self.contexts[call.id] {
                result = current
            } else {
                let context = AccountGroupCallContextImpl(account: account, engine: engine, peerId: peerId, isChannel: isChannel, call: call, isMuted: isMuted, e2eContext: e2eContext)
                result = Record(context: context)
                self.contexts[call.id] = result
            }
            
            let index = result.subscribers.add(Void())
            result.removeTimer?.invalidate()
            result.removeTimer = nil
            return AccountGroupCallContextImpl.Proxy(context: result.context, removed: { [weak self, weak result] in
                Queue.mainQueue().async {
                    if let strongResult = result, let self, self.contexts[call.id] === strongResult {
                        strongResult.subscribers.remove(index)
                        if strongResult.subscribers.isEmpty {
                            let removeTimer = SwiftSignalKit.Timer(timeout: 30, repeat: false, completion: { [weak self] in
                                if let result = result, let self, self.contexts[call.id] === result, result.subscribers.isEmpty {
                                    self.contexts.removeValue(forKey: call.id)
                                }
                            }, queue: .mainQueue())
                            strongResult.removeTimer = removeTimer
                            removeTimer.start()
                        }
                    }
                }
            })
        }

        public func leaveInBackground(engine: TelegramEngine, id: Int64, accessHash: Int64, source: UInt32) {
            let disposable = engine.calls.leaveGroupCall(callId: id, accessHash: accessHash, source: source).start(completed: { [weak self] in
                guard let self else {
                    return
                }
                if let context = self.contexts[id] {
                    context.context.participantsContext?.removeLocalPeerId()
                }
            })
            self.leaveDisposables.add(disposable)
        }
    }
    
    public let queue: Queue = .mainQueue()
    public let impl: QueueLocalObject<Impl>
    
    public init() {
        let queue = self.queue
        self.impl = QueueLocalObject(queue: queue, generate: {
            return Impl(queue: queue)
        })
    }
}



private extension PresentationGroupCallState {
    static func initialValue(myPeerId: PeerId, title: String?, scheduledTimestamp: Int32?, subscribedToScheduled: Bool, isStream: Bool, isChannel: Bool, isConference: Bool, isMuted: Bool, messagesEnabled: GroupCallParticipantsContext.State.MessagesAreEnabled?) -> PresentationGroupCallState {
        return PresentationGroupCallState(
            myPeerId: myPeerId,
            networkState: .connecting,
            canManageCall: false,
            adminIds: Set(),
            muteState: isMuted ? GroupCallParticipantsContext.Participant.MuteState(canUnmute: true, mutedByYou: false) : nil,
            defaultParticipantMuteState: nil,
            messagesEnabled: messagesEnabled,
            recordingStartTimestamp: nil,
            title: title,
            raisedHand: false,
            scheduleTimestamp: scheduledTimestamp,
            subscribedToScheduled: subscribedToScheduled,
            isVideoEnabled: false,
            isStream: isStream,
            isChannel: isChannel,
            isConference: isConference,
            sendAs: [],
            defaultSendAs: nil,
            sendPaidMessageStars: nil
        )
    }
}

public struct GroupCallInitialOutput {
    public struct Video {
        public var capturer: OngoingCallVideoCapturer
        public var source: VideoSourceMac
        public init(capturer: OngoingCallVideoCapturer, source: VideoSourceMac) {
            self.capturer = capturer
            self.source = source
        }
    }
    public var isMuted: Bool
    public var video: Video?
    public var screencast: Video?
    public init(isMuted: Bool, video: Video? = nil, screencast: Video? = nil) {
        self.isMuted = isMuted
        self.video = video
        self.screencast = screencast
    }
}

public final class PresentationGroupCallImpl: PresentationGroupCall {

    public var isStream = false
    private let streamPeerId: EnginePeer.Id?
    
    public var peer: Peer? = nil
    private let loadPeerDisposable = MetaDisposable()
//    var activeCall: CachedChannelData.ActiveCall?

    private let startDisposable = MetaDisposable()
    private let subscribeDisposable = MetaDisposable()
    private let updateGroupCallJoinAsDisposable = MetaDisposable()
    private let sendAsDisposable = MetaDisposable()
    
    private let devicesContext: DevicesContext
    private let devicesDisposable = MetaDisposable()
    
    private let displayAsPeersValue: Promise<[FoundPeer]?> = Promise(nil)
    public var displayAsPeers: Signal<[FoundPeer]?, NoError> {
        return displayAsPeersValue.get()
    }
    
    
    
    public var permissions: (PresentationGroupCallMuteAction, @escaping(Bool)->Void)->Void = { _, f in f(true) }

    public var sharedContext: (any SharedAccountContextProtocol) {
        return accountContext.sharedContext
    }
    
    private enum InternalState {
        case requesting
        case active(GroupCallInfo)
        case established(info: GroupCallInfo, connectionMode: JoinGroupCallResult.ConnectionMode, clientParams: String, localSsrc: UInt32, initialState: GroupCallParticipantsContext.State)
        
        public var callInfo: GroupCallInfo? {
            switch self {
            case .requesting:
                return nil
            case let .active(info):
                return info
            case let .established(info, _, _, _, _):
                return info
            }
        }
    }
    
    private struct SummaryInfoState: Equatable {
        public var info: GroupCallInfo
        
        public init(
            info: GroupCallInfo
        ) {
            self.info = info
        }
    }
    
    private struct SummaryParticipantsState: Equatable {
        public var participantCount: Int
        public var topParticipants: [GroupCallParticipantsContext.Participant]
        public var activeSpeakers: Set<PeerId>
    
        public init(
            participantCount: Int,
            topParticipants: [GroupCallParticipantsContext.Participant],
            activeSpeakers: Set<PeerId>
        ) {
            self.participantCount = participantCount
            self.topParticipants = topParticipants
            self.activeSpeakers = activeSpeakers
        }
    }
    
    private class SpeakingParticipantsContext {
        private let speakingLevelThreshold: Float = 0.1
        private let cutoffTimeout: Int32 = 3
        private let silentTimeout: Int32 = 2
        
        public struct Participant {
            public let ssrc: UInt32
            public let timestamp: Int32
            public let level: Float
            public init(ssrc: UInt32, timestamp: Int32, level: Float) {
                self.ssrc = ssrc
                self.timestamp = timestamp
                self.level = level
            }
        }
        
        private var participants: [PeerId: Participant] = [:]
        private let speakingParticipantsPromise = ValuePromise<[PeerId: UInt32]>(ignoreRepeated: true)
        private var speakingParticipants = [PeerId: UInt32]() {
            didSet {
                self.speakingParticipantsPromise.set(self.speakingParticipants)
            }
        }
        
        private let audioLevelsPromise = Promise<[(PeerId, UInt32, Float, Bool)]>()
        
        public init() {
        }
        
        public func update(levels: [(PeerId, UInt32, Float, Bool)]) {
            let timestamp = Int32(CFAbsoluteTimeGetCurrent())
            let currentParticipants: [PeerId: Participant] = self.participants
            
            var validSpeakers: [PeerId: Participant] = [:]
            var silentParticipants = Set<PeerId>()
            var speakingParticipants = [PeerId: UInt32]()
            for (peerId, ssrc, level, hasVoice) in levels {
                if level > speakingLevelThreshold && hasVoice {
                    validSpeakers[peerId] = Participant(ssrc: ssrc, timestamp: timestamp, level: level)
                    speakingParticipants[peerId] = ssrc
                } else {
                    silentParticipants.insert(peerId)
                }
            }
            
            for (peerId, participant) in currentParticipants {
                if let _ = validSpeakers[peerId] {
                } else {
                    let delta = timestamp - participant.timestamp
                    if silentParticipants.contains(peerId) {
                        if delta < silentTimeout {
                            validSpeakers[peerId] = participant
                            speakingParticipants[peerId] = participant.ssrc
                        }
                    } else if delta < cutoffTimeout {
                        validSpeakers[peerId] = participant
                        speakingParticipants[peerId] = participant.ssrc
                    }
                }
            }
            
            var audioLevels: [(PeerId, UInt32, Float, Bool)] = []
            for (peerId, source, level, hasVoice) in levels {
                if level > 0.001 {
                    audioLevels.append((peerId, source, level, hasVoice))
                }
            }
            
            self.participants = validSpeakers
            self.speakingParticipants = speakingParticipants
            self.audioLevelsPromise.set(.single(audioLevels))
        }
        
        public func get() -> Signal<[PeerId: UInt32], NoError> {
            return self.speakingParticipantsPromise.get()
        }
        
        public func getAudioLevels() -> Signal<[(PeerId, UInt32, Float, Bool)], NoError> {
            return self.audioLevelsPromise.get() |> distinctUntilChanged(isEqual: { lhs, rhs in
                if lhs.count != rhs.count {
                    return false
                } else {
                    for (i, lhsValue) in lhs.enumerated() {
                        let rhsValue = rhs[i]
                        if lhsValue != rhsValue {
                            return false
                        }
                    }
                }
                return true
            })
        }
    }
    
    public let account: Account
    public let accountContext: (any AccountContextProtocol)
    
    public var engine: TelegramEngine {
        return accountContext.engine
    }
    
    private var initialCall: (description: EngineGroupCallDescription, reference: InternalGroupCallReference)?
    public let internalId: CallSessionInternalId
    public let peerId: PeerId?
    private var invite: String?
    private var joinAsPeerIdSignal:ValuePromise<PeerId> = ValuePromise(ignoreRepeated: true)
    public var joinAsPeerIdValue:Signal<PeerId, NoError> {
        return joinAsPeerIdSignal.get()
    }
    public private(set) var joinAsPeerId: PeerId {
        didSet {
            joinAsPeerIdSignal.set(joinAsPeerId)
        }
    }
    private var ignorePreviousJoinAsPeerId: (PeerId, UInt32)?
    private var reconnectingAsPeer: Peer?
    
    public private(set) var callId: Int64?
    
    public private(set) var hasVideo: Bool
    public private(set) var hasScreencast: Bool

    public var e2eEncryptionKeyHash: Signal<Data?, NoError> {
        return self.e2eContext?.e2eEncryptionKeyHash ?? .single(nil)
    }
        
    private let updateTitleDisposable = MetaDisposable()
    
    private var temporaryJoinTimestamp: Int32
    private var temporaryActivityTimestamp: Double?
    private var temporaryActivityRank: Int?
    private var temporaryRaiseHandRating: Int64?
    private var temporaryHasRaiseHand: Bool = false
    private var temporaryVideoJoined: Bool = true
    private var temporaryMuteState: GroupCallParticipantsContext.Participant.MuteState?
    
    private var internalState: InternalState = .requesting
    private let internalStatePromise = Promise<InternalState>(.requesting)
    private var currentLocalSsrc: UInt32?
    
    private var genericCallContext: OngoingGroupCallContext?
    private var streamPlayer: GroupCallStreamPlayer?
    private let supportsBroadcastListener = MTLCreateSystemDefaultDevice() != nil
    private var currentConnectionMode: OngoingGroupCallContext.ConnectionMode = .none
    private var screencastCallContext: OngoingGroupCallContext?
    
    private struct SsrcMapping {
            public var peerId: PeerId
            public var isPresentation: Bool
        }
        private var ssrcMapping: [UInt32: SsrcMapping] = [:]

    private var summaryInfoState = Promise<SummaryInfoState?>(nil)
    
    public var callInfo: Signal<GroupCallInfo?, NoError> {
        return summaryInfoState.get() |> map { $0?.info }
    }
    
    private var summaryParticipantsState = Promise<SummaryParticipantsState?>(nil)
    
    private let summaryStatePromise = Promise<PresentationGroupCallSummaryState?>(nil)
    public var summaryState: Signal<PresentationGroupCallSummaryState?, NoError> {
        return self.summaryStatePromise.get() |> distinctUntilChanged
    }
    private var summaryStateDisposable: Disposable?
    
    private var isMutedValue: PresentationGroupCallMuteAction = .muted(isPushToTalkActive: false)
    private var muteActionVersion = 0
    private let isMutedPromise = ValuePromise<PresentationGroupCallMuteAction>(.muted(isPushToTalkActive: false))
    public var isMuted: Signal<Bool, NoError> {
        return self.isMutedPromise.get()
        |> map { value -> Bool in
            switch value {
            case let .muted(isPushToTalkActive):
                return !isPushToTalkActive
            case .unmuted:
                return false
            }
        }
    }
    
    private var settingsDisposable: Disposable?
        
    private var audioLevelsDisposable = MetaDisposable()
    
    private let speakingParticipantsContext = SpeakingParticipantsContext()
    private var speakingParticipantsReportTimestamp: [PeerId: Double] = [:]
    public var audioLevels: Signal<[(PeerId, UInt32, Float, Bool)], NoError> {
        return self.speakingParticipantsContext.getAudioLevels()
    }
    
    private var participantsContextStateDisposable = MetaDisposable()
    private var temporaryParticipantsContext: GroupCallParticipantsContext?
    private var participantsContext: GroupCallParticipantsContext?
    
    private let myAudioLevelPipe = ValuePipe<Float>()
    public var myAudioLevel: Signal<Float, NoError> {
        return self.myAudioLevelPipe.signal()
    }
    private var myAudioLevelDisposable = MetaDisposable()
        
    private let typingDisposable = MetaDisposable()
    
    private let _canBeRemoved = Promise<Bool>(false)
    public var canBeRemoved: Signal<Bool, NoError> {
        return self._canBeRemoved.get()
    }
    private var markedAsCanBeRemoved = false
    
    private var leaving = false
    
    private var stateValue: PresentationGroupCallState {
        didSet {
            if self.stateValue != oldValue {
                self.statePromise.set(self.stateValue)
            }
        }
    }
    private let statePromise: ValuePromise<PresentationGroupCallState>
    public var state: Signal<PresentationGroupCallState, NoError> {
        return self.statePromise.get()
    }
    
    private var checkIndex = 0
    
    private var stateVersionValue: Int = 0 {
        didSet {
            if self.stateVersionValue != oldValue {
                self.stateVersionPromise.set(self.stateVersionValue)
            }
        }
    }
    private let stateVersionPromise = ValuePromise<Int>(0)
    public var stateVersion: Signal<Int, NoError> {
        return self.stateVersionPromise.get()
    }

    
    private var membersValue: PresentationGroupCallMembers? {
        didSet {
            if self.membersValue != oldValue {
                self.membersPromise.set(self.membersValue)
            }
        }
    }
    private let membersPromise = ValuePromise<PresentationGroupCallMembers?>(nil)
    public var members: Signal<PresentationGroupCallMembers?, NoError> {
        return self.membersPromise.get()
    }
    
    private var invitedPeersValue: [PresentationGroupCallInvitedPeer] = [] {
        didSet {
            if self.invitedPeersValue != oldValue {
                self.inivitedPeersPromise.set(self.invitedPeersValue)
            }
        }
    }
    private let inivitedPeersPromise = ValuePromise<[PresentationGroupCallInvitedPeer]>([])
    public var invitedPeers: Signal<[PresentationGroupCallInvitedPeer], NoError> {
        return self.inivitedPeersPromise.get()
    }
    
    private let invitationErrorsPipe = ValuePipe<InviteConferenceCallParticipantError>()
    public var invitationErrors: Signal<InviteConferenceCallParticipantError, NoError> {
        return self.invitationErrorsPipe.signal()
    }

    private let memberEventsPipe = ValuePipe<PresentationGroupCallMemberEvent>()
    public var memberEvents: Signal<PresentationGroupCallMemberEvent, NoError> {
        return self.memberEventsPipe.signal()
    }
    private let memberEventsPipeDisposable = MetaDisposable()

    private let reconnectedAsEventsPipe = ValuePipe<Peer>()
    public var reconnectedAsEvents: Signal<Peer, NoError> {
        return self.reconnectedAsEventsPipe.signal()
    }
    
    private let joinDisposable = MetaDisposable()
    private let screencastJoinDisposable = MetaDisposable()
    private let screencastRequestDisposable = MetaDisposable()
    private let requestDisposable = MetaDisposable()
    private var groupCallParticipantUpdatesDisposable: Disposable?
    
    private let networkStateDisposable = MetaDisposable()
    private let isMutedDisposable = MetaDisposable()
    private let memberStatesDisposable = MetaDisposable()
    private let leaveDisposable = MetaDisposable()

    private var isReconnectingAsSpeaker = false {
        didSet {
            if self.isReconnectingAsSpeaker != oldValue {
                self.isReconnectingAsSpeakerPromise.set(self.isReconnectingAsSpeaker)
            }
        }
    }
    private let isReconnectingAsSpeakerPromise = ValuePromise<Bool>(false)
    
    private var checkCallDisposable: Disposable?
    private var isCurrentlyConnecting: Bool?

    private var myAudioLevelTimer: SwiftSignalKit.Timer?
        
    private var removedChannelMembersDisposable: Disposable?
    
    private var didStartConnectingOnce: Bool = false
    private var didConnectOnce: Bool = false
    
    private var videoCapturer: OngoingCallVideoCapturer?
    
    private var initialOutput: GroupCallInitialOutput
    private var didApplyInitialOutput = false
    
    private var screenCapturer: OngoingCallVideoCapturer?
    
    public private(set) var schedulePending = false
    private var isScheduledStarted = false
    


    private let isSpeakingPromise = ValuePromise<Bool>(false, ignoreRepeated: true)
        public var isSpeaking: Signal<Bool, NoError> {
            return self.isSpeakingPromise.get()
        }


    private var peerUpdatesSubscription: Disposable?
    
    private let keyPair: TelegramKeyPair?
    public let isConference: Bool
    
    private let conferenceSourceId: CallSessionInternalId?
    public var conferenceSource: CallSessionInternalId? {
        return self.conferenceSourceId
    }
    
    public var upgradedConferenceCall: PCallSession?
    public var pendingDisconnedUpgradedConferenceCall: PCallSession?
    private var conferenceInvitationContexts: [PeerId: PendingConferenceInvitationContext] = [:]

    private let e2eContext: ConferenceCallE2EContext?

    private var messagesContext: GroupCallMessagesContext? {
        didSet {
            if let messagesContext = self.messagesContext {
                self.messagesStatePromise.set(messagesContext.state)
            }
        }
    }
    private let messagesStatePromise = Promise<GroupCallMessagesContext.State>(GroupCallMessagesContext.State(messages: [], pinnedMessages: [], topStars: [], totalStars: 0, pendingMyStars: 0))
    public var messagesState: Signal<GroupCallMessagesContext.State, NoError> {
        return self.messagesStatePromise.get()
    }

    
    public init(
        accountContext: (any AccountContextProtocol),
        initialCall: (description: EngineGroupCallDescription, reference: InternalGroupCallReference)?,
        internalId: CallSessionInternalId,
        peerId: PeerId?,
        isChannel: Bool,
        invite: String?,
        joinAsPeerId: PeerId?,
        initialInfo: GroupCallInfo?,
        isStream: Bool,
        streamPeerId: PeerId?,
        keyPair: TelegramKeyPair?,
        conferenceSourceId: CallSessionInternalId?,
        isConference: Bool,
        initialOutput: GroupCallInitialOutput,
        isLiveStream: Bool
    ) {
        self.account = accountContext.account
        self.accountContext = accountContext
        
        self.initialOutput = initialOutput
        self.initialCall = initialCall
        self.internalId = internalId
        self.streamPeerId = streamPeerId
        self.peerId = peerId
        self.invite = invite
        self.conferenceSourceId = conferenceSourceId
        self.isStream = isStream
        self.joinAsPeerId = joinAsPeerId ?? accountContext.account.peerId
        self.joinAsPeerIdSignal.set(self.joinAsPeerId)
        self.isConference = isConference
        self.keyPair = keyPair
        
        if let keyPair, let initialCall {
            self.e2eContext = ConferenceCallE2EContext(
                engine: accountContext.engine,
                callId: initialCall.description.id,
                accessHash: initialCall.description.accessHash,
                userId: accountContext.account.peerId.id._internalGetInt64Value(),
                reference: initialCall.reference,
                keyPair: keyPair,
                initializeState: { keyPair, userId, block in
                    guard let keyPair = TdKeyPair(keyId: keyPair.id, publicKey: keyPair.publicKey.data) else {
                        return nil
                    }
                    guard let call = TdCall.make(with: keyPair, userId: userId, latestBlock: block) else {
                        return nil
                    }
                    return ConferenceCallE2EContextStateImpl(call: call)
                }

            )
        } else {
            self.e2eContext = nil
        }
        
        

        //        self.stateValue = PresentationGroupCallState.initialValue(myPeerId: self.joinAsPeerId, title: initialCall?.description.title, scheduleTimestamp: initialCall?.description.scheduleTimestamp, subscribedToScheduled: initialCall?.description.subscribedToScheduled ?? false)
        


        self.stateValue = PresentationGroupCallState.initialValue(myPeerId: self.joinAsPeerId, title: initialCall?.description.title, scheduledTimestamp: initialCall?.description.scheduleTimestamp, subscribedToScheduled: initialCall?.description.subscribedToScheduled ?? false, isStream: self.isStream, isChannel: isChannel, isConference: isConference, isMuted: self.initialOutput.isMuted, messagesEnabled: isChannel ? nil : .init(isEnabled: true, canChange: false, sendPaidMessagesStars: nil))
        self.statePromise = ValuePromise(self.stateValue)
        
        self.temporaryJoinTimestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
        
        self.hasVideo = false
        self.hasScreencast = false

        self.devicesContext = CallsCoreHooks.shared.devicesContext(accountContext.sharedContext)
        
        
        if let initialCall {
            let messageLifetime = accountContext.appConfiguration.getGeneralValue("group_call_message_ttl", orElse: 10)
            let messagesContext = accountContext.engine.messages.groupCallMessages(
                appConfig: accountContext.appConfiguration, callId: initialCall.description.id,
                reference: .id(id: initialCall.description.id, accessHash: initialCall.description.accessHash),
                e2eContext: self.e2eContext, messageLifetime: messageLifetime,
                isLiveStream: isLiveStream
            )
            self.messagesContext = messagesContext
            self.messagesStatePromise.set(messagesContext.state)
        }

        
        var devicesConnected = false
        var pendingInputDeviceId: String?
        var pendingOutputDeviceId: String?
        let applyPendingDevices: () -> Void = { [weak self] in
            guard let `self` = self, devicesConnected else {
                return
            }
            if let id = pendingInputDeviceId {
                pendingInputDeviceId = nil
                self.genericCallContext?.switchAudioInput(id)
            }
            if let id = pendingOutputDeviceId {
                pendingOutputDeviceId = nil
                self.genericCallContext?.switchAudioOutput(id)
            }
        }
        let devicesUpdates = DisposableSet()
        devicesUpdates.add((devicesContext.updater() |> deliverOnMainQueue).start(next: { devices in
            if let id = devices.input {
                pendingInputDeviceId = id
            }
            if let id = devices.output {
                pendingOutputDeviceId = id
            }
            applyPendingDevices()
        }))
        devicesUpdates.add((state |> map { $0.networkState == .connected } |> distinctUntilChanged |> deliverOnMainQueue).start(next: { connected in
            devicesConnected = connected
            applyPendingDevices()
        }))
        devicesDisposable.set(devicesUpdates)
        
        if let peerId {
            let peerSignal = account.postbox.peerView(id: peerId)
                |> map { peerViewMainPeer($0) }
            |> deliverOnMainQueue
            
            self.loadPeerDisposable.set(peerSignal.start(next: { [weak self] peer in
                self?.peer = peer
            }))
        }
        
        self.groupCallParticipantUpdatesDisposable = (self.account.stateManager.groupCallParticipantUpdates
        |> deliverOnMainQueue).start(next: { [weak self] updates in
            guard let strongSelf = self else {
                return
            }
            if case let .established(callInfo, _, _, _, _) = strongSelf.internalState {
                var _: [(UInt32, String?, String?)] = []
                var removedSsrc: [UInt32] = []
                for (callId, update) in updates {
                    if callId == callInfo.id {
                        switch update {
                        case let .state(update):
                            for participantUpdate in update.participantUpdates {
                                if case .left = participantUpdate.participationStatusChange {
                                    if let ssrc = participantUpdate.ssrc {
                                        removedSsrc.append(ssrc)
                                    }
                                    
                                    if participantUpdate.peerId == strongSelf.joinAsPeerId {
                                        if case let .established(_, _, _, ssrc, _) = strongSelf.internalState, ssrc == participantUpdate.ssrc {
                                            strongSelf.markAsCanBeRemoved()
                                        }
                                    } else {
                                        strongSelf.e2eContext?.synchronizeRemovedParticipants()
                                    }

                                    
                                } else if participantUpdate.peerId == strongSelf.joinAsPeerId {
                                    if case let .established(_, connectionMode, _, ssrc, _) = strongSelf.internalState {
                                        if ssrc != participantUpdate.ssrc {
                                            strongSelf.markAsCanBeRemoved()
                                        } else if case .broadcast = connectionMode {
                                            let canUnmute: Bool
                                            if let muteState = participantUpdate.muteState {
                                                canUnmute = muteState.canUnmute
                                            } else {
                                                canUnmute = true
                                            }
                                            
                                            if canUnmute {
                                                strongSelf.requestCall(movingFromBroadcastToRtc: true)
                                            }
                                        }
                                    }
                                } else if case .joined = participantUpdate.participationStatusChange {
                                } else if let ssrc = participantUpdate.ssrc, strongSelf.ssrcMapping[ssrc] == nil {
                                }
                            }
                        case let .call(isTerminated, _, _, _, _, _, _, _, _):
                            if isTerminated {
                                strongSelf.markAsCanBeRemoved()
                            }
                        case let .conferenceChainBlocks(subChainId, blocks, nextOffset):
                            if let e2eContext = strongSelf.e2eContext {
                                e2eContext.addChainBlocksUpdate(subChainId: subChainId, blocks: blocks, nextOffset: nextOffset)
                            }
                        }
                    }
                }
                if !removedSsrc.isEmpty {
                    strongSelf.genericCallContext?.removeSsrcs(ssrcs: removedSsrc)
                }
                //strongSelf.callContext?.addParticipants(participants: addedParticipants)
            }
        })
        
        
        if let peerId {
            self.displayAsPeersValue.set(accountContext.engine.calls.cachedGroupCallDisplayAsAvailablePeers(peerId: peerId) |> map(Optional.init))
            
            if isLiveStream {
                let signal = accountContext.engine.peers.liveStorySendAsAvailablePeers(peerId: peerId) |> deliverOnMainQueue
                self.sendAsDisposable.set(signal.startStrict(next: { [weak self] value in
                    self?.stateValue.sendAs = value
                }))
            }
        }
       
        
        self.summaryStatePromise.set(combineLatest(queue: .mainQueue(),
            self.summaryInfoState.get(),
            self.summaryParticipantsState.get(),
            self.statePromise.get()
        )
        |> map { infoState, participantsState, callState -> PresentationGroupCallSummaryState? in
            guard let participantsState = participantsState else {
                return nil
            }
            return PresentationGroupCallSummaryState(
                info: infoState?.info,
                participantCount: participantsState.participantCount,
                callState: callState,
                topParticipants: participantsState.topParticipants,
                activeSpeakers: participantsState.activeSpeakers
            )
        })
        
        if let initialCall = initialCall, let peerId {
            let temporaryParticipantsContext = CallsCoreHooks.shared.cachedGroupCallContexts(self.accountContext).impl.syncWith({ impl in
                impl.get(account: accountContext.account, engine: accountContext.engine, peerId: peerId, isChannel: isChannel, call: EngineGroupCallDescription(id: initialCall.description.id, accessHash: initialCall.description.accessHash, title: initialCall.description.title, scheduleTimestamp: initialCall.description.scheduleTimestamp, subscribedToScheduled: initialCall.description.subscribedToScheduled, isStream: initialCall.description.isStream), isMuted: initialOutput.isMuted, e2eContext: self.e2eContext)
            })
            self.switchToTemporaryParticipantsContext(sourceContext: temporaryParticipantsContext.context.participantsContext, oldMyPeerId: self.joinAsPeerId)
        } else {
            self.switchToTemporaryParticipantsContext(sourceContext: nil, oldMyPeerId: self.joinAsPeerId)
        }
        
        if let peerId {
            let _ = (self.account.postbox.loadedPeerWithId(peerId)
            |> deliverOnMainQueue).start(next: { [weak self] peer in
                guard let strongSelf = self else {
                    return
                }
                var canManageCall = false
                if let peer = peer as? TelegramGroup {
                    if case .creator = peer.role {
                        canManageCall = true
                    } else if case let .admin(rights, _) = peer.role, rights.rights.contains(.canManageCalls) {
                        canManageCall = true
                    }
                } else if let peer = peer as? TelegramChannel {
                    if peer.flags.contains(.isCreator) {
                        canManageCall = true
                    } else if (peer.adminRights?.rights.contains(.canManageCalls) == true) {
                        canManageCall = true
                    }
                    strongSelf.peerUpdatesSubscription = strongSelf.accountContext.account.viewTracker.polledChannel(peerId: peer.id).start()
                }
                var updatedValue = strongSelf.stateValue
                updatedValue.canManageCall = canManageCall
                strongSelf.stateValue = updatedValue
            })
        }
       
        
      //  if initialCall?.scheduleTimestamp == nil {
            self.requestCall(movingFromBroadcastToRtc: false)
      //  }
        if let initialInfo = initialInfo {
            summaryInfoState.set(.single(.init(info: initialInfo)))
        }
    }
    
    deinit {
        self.summaryStateDisposable?.dispose()
        self.joinDisposable.dispose()
        self.requestDisposable.dispose()
        self.groupCallParticipantUpdatesDisposable?.dispose()
        self.leaveDisposable.dispose()
        self.isMutedDisposable.dispose()
        self.memberStatesDisposable.dispose()
        self.networkStateDisposable.dispose()
        self.checkCallDisposable?.dispose()
        self.audioLevelsDisposable.dispose()
        self.participantsContextStateDisposable.dispose()
        self.myAudioLevelDisposable.dispose()
        self.memberEventsPipeDisposable.dispose()
        self.screencastJoinDisposable.dispose()
        self.screencastRequestDisposable.dispose()
        self.myAudioLevelTimer?.invalidate()
        self.typingDisposable.dispose()
        self.updateTitleDisposable.dispose()
        self.removedChannelMembersDisposable?.dispose()
        self.sendAsDisposable.dispose()
        self.peerUpdatesSubscription?.dispose()
        self.devicesDisposable.dispose()
        self.loadPeerDisposable.dispose()
        self.startDisposable.dispose()
        self.subscribeDisposable.dispose()
        self.updateGroupCallJoinAsDisposable.dispose()
        self.settingsDisposable?.dispose()
    }
    
    private func switchToTemporaryParticipantsContext(sourceContext: GroupCallParticipantsContext?, oldMyPeerId: PeerId) {
        let myPeerId = self.joinAsPeerId
        let accountContext = self.accountContext
        let myPeer = self.accountContext.account.postbox.transaction { transaction -> (Peer, CachedPeerData?)? in
            if let peer = transaction.getPeer(myPeerId) {
                return (peer, transaction.getPeerCachedData(peerId: myPeerId))
            } else {
                return nil
            }
        }
        
        let rawAdminIds: Signal<Set<PeerId>, NoError>
        if let peerId {
            if peerId.namespace == Namespaces.Peer.CloudChannel {
                rawAdminIds = Signal { subscriber in
                    let (disposable, _) = accountContext.peerChannelMemberCategoriesContextsManager.admins(peerId: peerId, updated: { list in
                        var peerIds = Set<PeerId>()
                        for item in list.list {
                            if let adminInfo = item.participant.adminInfo, adminInfo.rights.rights.contains(.canManageCalls) {
                                peerIds.insert(item.peer.id)
                            }
                        }
                        subscriber.putNext(peerIds)
                    })
                    return disposable
                }
                |> distinctUntilChanged
                |> runOn(.mainQueue())
            } else {
                rawAdminIds = accountContext.engine.data.subscribe(
                    TelegramEngine.EngineData.Item.Peer.LegacyGroupParticipants(id: peerId)
                )
                |> map { participants -> Set<PeerId> in
                    guard case let .known(participants) = participants else {
                        return Set()
                    }
                    return Set(participants.compactMap { item -> PeerId? in
                        switch item {
                        case .creator, .admin:
                            return item.peerId
                        default:
                            return nil
                        }
                    })
                }
                |> distinctUntilChanged
            }
        } else {
            rawAdminIds = .single(Set())
        }
        
        let peer: Signal<EnginePeer?, NoError>
        if let peerId = (self.peerId ?? self.streamPeerId) {
            peer = accountContext.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: peerId))
        } else {
            peer = .single(nil)
        }
        let adminIds = combineLatest(queue: .mainQueue(),
            rawAdminIds,
            peer
        )
        |> map { rawAdminIds, peer -> Set<PeerId> in
            var rawAdminIds = rawAdminIds
            if let peer, case let .channel(peer) = peer {
                if peer.hasPermission(.manageCalls) {
                    rawAdminIds.insert(accountContext.account.peerId)
                } else {
                    rawAdminIds.remove(accountContext.account.peerId)
                }
            }
            return rawAdminIds
        }
        |> distinctUntilChanged


        
        if let sourceContext = sourceContext, let initialState = sourceContext.immediateState {
            let temporaryParticipantsContext = self.accountContext.engine.calls.groupCall(peerId: self.peerId, myPeerId: myPeerId, id: sourceContext.id, reference: sourceContext.reference, state: initialState, previousServiceState: sourceContext.serviceState, e2eContext: self.e2eContext)
            self.temporaryParticipantsContext = temporaryParticipantsContext
            self.participantsContextStateDisposable.set((combineLatest(queue: .mainQueue(),
                myPeer,
                temporaryParticipantsContext.state,
                temporaryParticipantsContext.activeSpeakers, adminIds
            )
            |> take(1)).start(next: { [weak self] myPeerAndCachedData, state, activeSpeakers, adminIds in
                guard let strongSelf = self else {
                    return
                }

                var topParticipants: [GroupCallParticipantsContext.Participant] = []

                var members = PresentationGroupCallMembers(
                    participants: [],
                    speakingParticipants: [],
                    totalCount: 0,
                    loadMoreToken: nil
                )

                var updatedInvitedPeers = strongSelf.invitedPeersValue
                var didUpdateInvitedPeers = false

                var participants = state.participants

                if oldMyPeerId != myPeerId {
                    for i in 0 ..< participants.count {
                        if participants[i].id == .peer(oldMyPeerId) {
                            participants.remove(at: i)
                            break
                        }
                    }
                }

                if !participants.contains(where: { $0.id == .peer(myPeerId) }) {
                    if let (myPeer, cachedData) = myPeerAndCachedData {
                        let about: String?
                        if let cachedData = cachedData as? CachedUserData {
                            about = cachedData.about
                        } else if let cachedData = cachedData as? CachedChannelData {
                            about = cachedData.about
                        } else {
                            about = nil
                        }
                        participants.append(GroupCallParticipantsContext.Participant(
                            id: .peer(myPeerId),
                            peer: .init(myPeer),
                            ssrc: nil,
                            videoDescription: nil,
                            presentationDescription: nil,
                            joinTimestamp: strongSelf.temporaryJoinTimestamp,
                            raiseHandRating: strongSelf.temporaryRaiseHandRating,
                            hasRaiseHand: strongSelf.temporaryHasRaiseHand,
                            activityTimestamp: strongSelf.temporaryActivityTimestamp,
                            activityRank: strongSelf.temporaryActivityRank,
                            muteState: strongSelf.temporaryMuteState ?? (strongSelf.initialOutput.isMuted ? GroupCallParticipantsContext.Participant.MuteState(canUnmute: true, mutedByYou: false) : nil),
                            volume: nil,
                            about: about,
                            joinedVideo: strongSelf.temporaryVideoJoined,
                            paidStarsTotal: nil
                        ))
                        participants.sort(by: { GroupCallParticipantsContext.Participant.compare(lhs: $0, rhs: $1, sortAscending: state.sortAscending) })
                    }
                }

                for participant in participants {
                    members.participants.append(participant)

                    if topParticipants.count < 3 {
                        topParticipants.append(participant)
                    }

                    if let index = updatedInvitedPeers.firstIndex(where: { .peer($0.id) == participant.id}) {
                        updatedInvitedPeers.remove(at: index)
                        didUpdateInvitedPeers = true
                    }
                }

                members.totalCount = state.totalCount
                members.loadMoreToken = state.nextParticipantsFetchOffset

                strongSelf.membersValue = members

                var stateValue = strongSelf.stateValue
                stateValue.myPeerId = strongSelf.joinAsPeerId
                stateValue.adminIds = adminIds
                
                let canManageCall = state.isCreator || stateValue.adminIds.contains(accountContext.account.peerId)
                
                stateValue.canManageCall = canManageCall
                stateValue.defaultParticipantMuteState = state.defaultParticipantsAreMuted.isMuted ? .muted : .unmuted
                
                stateValue.sendPaidMessageStars = state.messagesAreEnabled.sendPaidMessagesStars
                stateValue.recordingStartTimestamp = state.recordingStartTimestamp
                stateValue.title = state.title
                stateValue.muteState = GroupCallParticipantsContext.Participant.MuteState(canUnmute: canManageCall || !state.defaultParticipantsAreMuted.isMuted, mutedByYou: false)

                
                stateValue.scheduleTimestamp = state.scheduleTimestamp
                strongSelf.stateValue = stateValue

                strongSelf.summaryParticipantsState.set(.single(SummaryParticipantsState(
                    participantCount: state.totalCount,
                    topParticipants: topParticipants,
                    activeSpeakers: activeSpeakers
                )))

                if didUpdateInvitedPeers {
                    strongSelf.invitedPeersValue = updatedInvitedPeers
                }
            }))
        } else {
            self.temporaryParticipantsContext = nil
            self.participantsContextStateDisposable.set((myPeer
            |> deliverOnMainQueue
            |> take(1)).start(next: { [weak self] myPeerAndCachedData in
                guard let strongSelf = self else {
                    return
                }

                var topParticipants: [GroupCallParticipantsContext.Participant] = []

                var members = PresentationGroupCallMembers(
                    participants: [],
                    speakingParticipants: [],
                    totalCount: 0,
                    loadMoreToken: nil
                )

                var participants: [GroupCallParticipantsContext.Participant] = []

                if let (myPeer, cachedData) = myPeerAndCachedData {
                    let about: String?
                    if let cachedData = cachedData as? CachedUserData {
                        about = cachedData.about
                    } else if let cachedData = cachedData as? CachedChannelData {
                        about = cachedData.about
                    } else {
                        about = nil
                    }
                    participants.append(GroupCallParticipantsContext.Participant(
                        id: .peer(myPeerId),
                        peer: .init(myPeer),
                        ssrc: nil,
                        videoDescription: nil,
                        presentationDescription: nil,
                        joinTimestamp: strongSelf.temporaryJoinTimestamp,
                        raiseHandRating: strongSelf.temporaryRaiseHandRating,
                        hasRaiseHand: strongSelf.temporaryHasRaiseHand,
                        activityTimestamp: strongSelf.temporaryActivityTimestamp,
                        activityRank: strongSelf.temporaryActivityRank,
                        muteState: strongSelf.temporaryMuteState ?? (strongSelf.initialOutput.isMuted ? GroupCallParticipantsContext.Participant.MuteState(canUnmute: true, mutedByYou: false) : nil),
                        volume: nil,
                        about: about,
                        joinedVideo: strongSelf.temporaryVideoJoined,
                        paidStarsTotal: nil
                    ))
                }

                for participant in participants {
                    members.participants.append(participant)

                    if topParticipants.count < 3 {
                        topParticipants.append(participant)
                    }
                }

                strongSelf.membersValue = members

                var stateValue = strongSelf.stateValue
                stateValue.myPeerId = strongSelf.joinAsPeerId

                strongSelf.stateValue = stateValue
            }))
        }
    }
    
    private func updateSessionState(internalState: InternalState) {
        guard !self.leaving && !self.markedAsCanBeRemoved else {
            return
        }
        
        let previousInternalState = self.internalState
        self.internalState = internalState
        self.internalStatePromise.set(.single(internalState))
        
        var shouldJoin = false
        let activeCallInfo: GroupCallInfo?
        switch previousInternalState {
            case let .active(previousCallInfo):
                if case let .active(callInfo) = internalState {
                    shouldJoin = previousCallInfo.scheduleTimestamp != nil && callInfo.scheduleTimestamp == nil
                    activeCallInfo = callInfo
                } else {
                    activeCallInfo = nil
                }
            default:
                if case let .active(callInfo) = internalState {
                    shouldJoin = callInfo.scheduleTimestamp == nil
                    activeCallInfo = callInfo
                } else {
                    activeCallInfo = nil
                }
        }

        
        switch previousInternalState {
        case .requesting:
            break
        default:
            if case .requesting = internalState {
                self.isCurrentlyConnecting = nil
            }
        }
        
        
  


        
        var encryptionContext: OngoingGroupCallEncryptionContext?
        if let e2eContext = self.e2eContext {
            encryptionContext = OngoingGroupCallEncryptionContextImpl(e2eCall: e2eContext.state, channelId: 0)
        } else if self.isConference {
            // Prevent non-encrypted conference calls
            encryptionContext = OngoingGroupCallEncryptionContextImpl(e2eCall: Atomic(value: ConferenceCallE2EContext.ContextStateHolder()), channelId: 0)
        }
                                   
        let prioritizeVP8 = self.accountContext.appConfiguration.getBoolValue("macos_calls_prioritize_vp8", orElse: false)
        
        if shouldJoin, let callInfo = activeCallInfo {
            let media: CurrentImpl
            if callInfo.isStream && !self.isConference {
                let player = self.streamPlayer ?? GroupCallStreamPlayer(account: self.account, rejoin: { [weak self] in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, case .established = self.internalState else { return }
                        self.requestCall(movingFromBroadcastToRtc: false)
                    }
                })
                self.streamPlayer = player
                media = .stream(player)
            } else if let context = self.genericCallContext {
                media = .call(context)
            } else {
                let genericCallContext = OngoingGroupCallContext(inputDeviceId: devicesContext.currentMicroId ?? "", outputDeviceId: devicesContext.currentOutputId ?? "", audioSessionActive: .single(true), video: self.videoCapturer, requestMediaChannelDescriptions: { [weak self] ssrcs, completion in
                    let disposable = MetaDisposable()
                    Queue.mainQueue().async {
                        guard let strongSelf = self else {
                            return
                        }
                        disposable.set(strongSelf.requestMediaChannelDescriptions(ssrcs: ssrcs, completion: completion))
                    }
                    return disposable
                }, rejoinNeeded: { [weak self] in
                    Queue.mainQueue().async {
                        guard let strongSelf = self else {
                            return
                        }
                        if case .established = strongSelf.internalState {
                            strongSelf.requestCall(movingFromBroadcastToRtc: false)
                        }
                    }
                }, outgoingAudioBitrateKbit: nil, videoContentType: .generic, enableNoiseSuppression: false, disableAudioInput: self.isStream, enableSystemMute: false, useReferenceImpl: true, prioritizeVP8: prioritizeVP8, logPath: allocateCallLogPath(account: self.account), onMutedSpeechActivityDetected: { _ in }, isConference: isConference, audioIsActiveByDefault: !self.initialOutput.isMuted, isStream: false, sharedAudioDevice: nil, encryptionContext: encryptionContext, broadcastPlayer: self.supportsBroadcastListener)
                
                
                
                self.genericCallContext = genericCallContext
                media = .call(genericCallContext)
                genericCallContext.setRequestedVideoChannels(self.suspendVideoChannelRequests ? [] : self.requestedVideoChannels)
                self.settingsDisposable = (voiceCallSettings(self.sharedContext.accountManager) |> deliverOnMainQueue).start(next: { [weak self] settings in
                    self?.genericCallContext?.setIsNoiseSuppressionEnabled(settings.noiseSuppression)
                })
                
                self.stateVersionValue += 1
                
               
            }
            self.joinDisposable.set((media.joinPayload
            |> distinctUntilChanged(isEqual: { lhs, rhs in
                if lhs.0 != rhs.0 {
                    return false
                }
                if lhs.1 != rhs.1 {
                    return false
                }
                return true
            })
            |> deliverOnMainQueue).start(next: { [weak self] joinPayload, ssrc in
                guard let strongSelf = self else {
                    return
                }

                let peerAdminIds: Signal<[PeerId], NoError>
                let peerId = strongSelf.peerId
                if let peerId {
                    if peerId.namespace == Namespaces.Peer.CloudChannel {
                        peerAdminIds = Signal { subscriber in
                            let (disposable, _) = strongSelf.accountContext.peerChannelMemberCategoriesContextsManager.admins(peerId: peerId, updated: { list in
                                var peerIds = Set<PeerId>()
                                for item in list.list {
                                    if let adminInfo = item.participant.adminInfo, adminInfo.rights.rights.contains(.canManageCalls) {
                                        peerIds.insert(item.peer.id)
                                    }
                                }
                                subscriber.putNext(Array(peerIds))
                            })
                            return disposable
                        }
                        |> distinctUntilChanged
                        |> runOn(.mainQueue())
                    } else {
                        peerAdminIds = strongSelf.account.postbox.transaction { transaction -> [PeerId] in
                            var result: [PeerId] = []
                            if let cachedData = transaction.getPeerCachedData(peerId: peerId) as? CachedGroupData {
                                if let participants = cachedData.participants {
                                    for participant in participants.participants {
                                        if case .creator = participant {
                                            result.append(participant.peerId)
                                        } else if case .admin = participant {
                                            result.append(participant.peerId)
                                        }
                                    }
                                }
                            }
                            return result
                        }
                    }
                } else {
                    peerAdminIds = .single([])
                }
                var generateE2EData: ((Data?) -> JoinGroupCallE2E?)?
                if let keyPair = strongSelf.keyPair {
                    if let mappedKeyPair = TdKeyPair(keyId: keyPair.id, publicKey: keyPair.publicKey.data) {
                        let userId = strongSelf.joinAsPeerId.id._internalGetInt64Value()
                        var checkIndex = 0
                        generateE2EData = { block -> JoinGroupCallE2E? in
                            
                            checkIndex += 1
                            
                            if checkIndex > 1 {
                                var bp = 0
                                bp += 1
                            }
                            
                            if let block {
                                guard let resultBlock = tdGenerateSelfAddBlock(mappedKeyPair, userId, block) else {
                                    return nil
                                }
                                return JoinGroupCallE2E(
                                    publicKey: keyPair.publicKey,
                                    block: resultBlock
                                )
                            } else {
                                guard let resultBlock = tdGenerateZeroBlock(mappedKeyPair, userId) else {
                                    return nil
                                }
                                return JoinGroupCallE2E(
                                    publicKey: keyPair.publicKey,
                                    block: resultBlock
                                )
                            }
                        }
                    }
                }
                
                let reference: InternalGroupCallReference
                if let initialCall = strongSelf.initialCall {
                    reference = initialCall.reference
                } else {
                    reference = .id(id: callInfo.id, accessHash: callInfo.accessHash)
                }
                

                strongSelf.currentLocalSsrc = ssrc
                strongSelf.checkIndex += 1
                
                if strongSelf.checkIndex > 1 {
                    var bp = 0
                    bp += 1
                }
                strongSelf.requestDisposable.set((strongSelf.accountContext.engine.calls.joinGroupCall(
                    peerId: strongSelf.peerId,
                    joinAs: strongSelf.joinAsPeerId,
                    callId: callInfo.id,
                    reference: reference,
                    isStream: strongSelf.isStream,
                    streamPeerId: strongSelf.streamPeerId,
                    preferMuted: true,
                    joinPayload: joinPayload,
                    peerAdminIds: peerAdminIds,
                    inviteHash: strongSelf.invite,
                    generateE2E: generateE2EData
                ) |> deliverOnMainQueue).start(next: { joinCallResult in
                    guard let strongSelf = self else {
                        return
                    }
                    let clientParams = joinCallResult.jsonParams

                    strongSelf.ssrcMapping.removeAll()
                    for participant in joinCallResult.state.participants {
                        if let ssrc = participant.ssrc {
                            if let participantPeer = participant.peer {
                                strongSelf.ssrcMapping[ssrc] = SsrcMapping(peerId: participantPeer.id, isPresentation: false)
                            }
                        }
                        if let presentationSsrc = participant.presentationDescription?.audioSsrc {
                            if let participantPeer = participant.peer {
                                strongSelf.ssrcMapping[presentationSsrc] = SsrcMapping(peerId: participantPeer.id, isPresentation: true)
                            }
                        }
                    }

                    switch joinCallResult.connectionMode {
                    case .rtc:
                        guard strongSelf.streamPlayer == nil else {
                            strongSelf.markAsCanBeRemoved()
                            return
                        }
                        strongSelf.currentConnectionMode = .rtc
                        strongSelf.genericCallContext?.setConnectionMode(.rtc, keepBroadcastConnectedIfWasEnabled: false, isUnifiedBroadcast: false)
                        strongSelf.genericCallContext?.setJoinResponse(payload: clientParams)
                    case let .broadcast(isExternalStream):
                        strongSelf.currentConnectionMode = .broadcast
                        let data = OngoingGroupCallContext.AudioStreamData(engine: strongSelf.accountContext.engine, callId: callInfo.id, accessHash: callInfo.accessHash, isExternalStream: isExternalStream)
                        if let player = strongSelf.streamPlayer {
                            guard isExternalStream else {
                                strongSelf.markAsCanBeRemoved()
                                return
                            }
                            player.joined(data)
                        } else {
                            strongSelf.genericCallContext?.setAudioStreamData(audioStreamData: data)
                            strongSelf.genericCallContext?.setConnectionMode(.broadcast, keepBroadcastConnectedIfWasEnabled: false, isUnifiedBroadcast: isExternalStream)
                        }
                    }

                    strongSelf.updateSessionState(internalState: .established(info: joinCallResult.callInfo, connectionMode: joinCallResult.connectionMode, clientParams: clientParams, localSsrc: ssrc, initialState: joinCallResult.state))
                    strongSelf.e2eContext?.begin(initialState: joinCallResult.e2eState)

                }, error: { error in
                    guard let strongSelf = self else {
                        return
                    }
                    
                    if case .anonymousNotAllowed = error {
                        CallsCoreHooks.shared.alert(strongSelf.accountContext.window, strings().voiceChatAnonymousDisabledAlertText)
                    } else if case .tooManyParticipants = error {
                        CallsCoreHooks.shared.alert(strongSelf.accountContext.window, strings().voiceChatJoinErrorTooMany)
                    }
                    strongSelf.markAsCanBeRemoved()
                }))
            }))
            self.networkStateDisposable.set((media.networkState
            |> deliverOnMainQueue).start(next: { [weak self] state in
                guard let strongSelf = self else {
                    return
                }
                let mappedState: PresentationGroupCallState.NetworkState
                if state.isConnected {
                    mappedState = .connected
                } else {
                    mappedState = .connecting
                }

                _ = strongSelf.stateValue.networkState == .connecting
                if strongSelf.stateValue.networkState != mappedState {
                    strongSelf.stateValue.networkState = mappedState
                }
                let isConnecting = mappedState == .connecting
                
                if strongSelf.isCurrentlyConnecting != isConnecting {
                    strongSelf.isCurrentlyConnecting = isConnecting
                    if isConnecting {
                        strongSelf.startCheckingCallIfNeeded()
                    } else {
                        strongSelf.checkCallDisposable?.dispose()
                        strongSelf.checkCallDisposable = nil
                    }
                }

                strongSelf.isReconnectingAsSpeaker = state.isTransitioningFromBroadcastToRtc
                
                if isConnecting {
                    strongSelf.didStartConnectingOnce = true
                }
                
                if state.isConnected {
                    if !strongSelf.didConnectOnce {
                        strongSelf.didConnectOnce = true
                    }

                    if let peer = strongSelf.reconnectingAsPeer {
                        strongSelf.reconnectingAsPeer = nil
                        strongSelf.reconnectedAsEventsPipe.putNext(peer)
                    }
                }
            }))
            
            self.audioLevelsDisposable.set((media.audioLevels
            |> deliverOnMainQueue).start(next: { [weak self] levels in
                guard let strongSelf = self else {
                    return
                }
                var result: [(PeerId, UInt32, Float, Bool)] = []
                var myLevel: Float = 0.0
                var myLevelHasVoice: Bool = false
                var orignalMyLevelHasVoice: Bool = false
                var missingSsrcs = Set<UInt32>()
                for (ssrcKey, level, hasVoice) in levels {
                    var peerId: PeerId?
                    let ssrcValue: UInt32
                    switch ssrcKey {
                    case .local:
                        peerId = strongSelf.joinAsPeerId
                        ssrcValue = 0
                    case let .source(ssrc):
                        if let mapping = strongSelf.ssrcMapping[ssrc] {
                            if mapping.isPresentation {
                                peerId = nil
                                ssrcValue = 0
                            } else {
                                peerId = mapping.peerId
                                ssrcValue = ssrc
                            }
                        } else {
                            ssrcValue = ssrc
                        }
                    }
                    if let peerId = peerId {
                        if case .local = ssrcKey {
                            orignalMyLevelHasVoice = hasVoice
                            myLevel = level
                            myLevelHasVoice = hasVoice
                        }
                        result.append((peerId, ssrcValue, level, hasVoice))
                    } else if ssrcValue != 0 {
                        missingSsrcs.insert(ssrcValue)
                    }

                }
                            
                strongSelf.speakingParticipantsContext.update(levels: result)
                
                if strongSelf.stateValue.muteState == nil {
                    let mappedLevel = myLevel * 1.5
                    strongSelf.myAudioLevelPipe.putNext(mappedLevel)
                    strongSelf.processMyAudioLevel(level: mappedLevel, hasVoice: myLevelHasVoice && orignalMyLevelHasVoice)
                } else {
                    strongSelf.myAudioLevelPipe.putNext(0)
                    strongSelf.processMyAudioLevel(level: 0, hasVoice: false)
                }
                
                strongSelf.isSpeakingPromise.set(orignalMyLevelHasVoice)
                if !missingSsrcs.isEmpty && !strongSelf.isStream {
                    strongSelf.participantsContext?.ensureHaveParticipants(ssrcs: missingSsrcs)
                }
            }))
        }
        
        switch previousInternalState {
        case .established:
            break
        default:
            if case let .established(callInfo, _, _, _, initialState) = internalState {
                self.summaryInfoState.set(.single(SummaryInfoState(info: callInfo)))
                
                var stateValue = self.stateValue
                
                
                stateValue.canManageCall = initialState.isCreator || initialState.adminIds.contains(self.accountContext.account.peerId)
                if stateValue.canManageCall && initialState.defaultParticipantsAreMuted.canChange {
                    stateValue.defaultParticipantMuteState = initialState.defaultParticipantsAreMuted.isMuted ? .muted : .unmuted
                }
                stateValue.messagesEnabled = initialState.messagesAreEnabled
                stateValue.defaultSendAs = initialState.defaultSendAs
                stateValue.sendPaidMessageStars = initialState.messagesAreEnabled.sendPaidMessagesStars
                stateValue.recordingStartTimestamp = initialState.recordingStartTimestamp
                stateValue.title = initialState.title

                stateValue.scheduleTimestamp = initialState.scheduleTimestamp
                stateValue.subscribedToScheduled = initialState.subscribedToScheduled
                self.stateValue = stateValue
                
                let accountContext = self.accountContext
                let peerId = self.peerId ?? self.streamPeerId
                let rawAdminIds: Signal<Set<PeerId>, NoError>
                let adminIds: Signal<Set<PeerId>, NoError>
                if let peerId {
                    if peerId.namespace == Namespaces.Peer.CloudChannel {
                        rawAdminIds = Signal { subscriber in
                            let (disposable, _) = accountContext.peerChannelMemberCategoriesContextsManager.admins(peerId: peerId, updated: { list in
                                var peerIds = Set<PeerId>()
                                for item in list.list {
                                    if let adminInfo = item.participant.adminInfo, adminInfo.rights.rights.contains(.canManageCalls) {
                                        peerIds.insert(item.peer.id)
                                    }
                                }
                                subscriber.putNext(peerIds)
                            })
                            return disposable
                        }
                        |> distinctUntilChanged
                        |> runOn(.mainQueue())
                    } else {
                        rawAdminIds = accountContext.account.postbox.combinedView(keys: [.cachedPeerData(peerId: peerId)])
                        |> map { views -> Set<PeerId> in
                            guard let view = views.views[.cachedPeerData(peerId: peerId)] as? CachedPeerDataView else {
                                return Set()
                            }
                            guard let cachedData = view.cachedPeerData as? CachedGroupData, let participants = cachedData.participants else {
                                return Set()
                            }
                            return Set(participants.participants.compactMap { item -> PeerId? in
                                switch item {
                                case .creator, .admin:
                                    return item.peerId
                                default:
                                    return nil
                                }
                            })
                        }
                        |> distinctUntilChanged
                    }
                    
                    adminIds = combineLatest(queue: .mainQueue(),
                        rawAdminIds,
                        accountContext.account.postbox.combinedView(keys: [.basicPeer(peerId)])
                    )
                    |> map { rawAdminIds, view -> Set<PeerId> in
                        var rawAdminIds = rawAdminIds
                        if let peerView = view.views[.basicPeer(peerId)] as? BasicPeerView, let peer = peerView.peer as? TelegramChannel {
                            if peer.hasPermission(.manageCalls) {
                                rawAdminIds.insert(accountContext.account.peerId)
                            } else {
                                rawAdminIds.remove(accountContext.account.peerId)
                            }
                        }
                        return rawAdminIds
                    }
                    |> distinctUntilChanged
                    
                } else {
                    adminIds = .single(Set())
                }
                

                let myPeerId = self.joinAsPeerId
                
                var initialState = initialState
                var serviceState: GroupCallParticipantsContext.ServiceState?
                if let participantsContext = self.participantsContext, let immediateState = participantsContext.immediateState {
                    initialState.mergeActivity(from: immediateState, myPeerId: myPeerId, previousMyPeerId: self.ignorePreviousJoinAsPeerId?.0, mergeActivityTimestamps: true)
                    serviceState = participantsContext.serviceState
                }
                
                let participantsContext = accountContext.engine.calls.groupCall(
                    peerId: self.peerId,
                    myPeerId: self.joinAsPeerId,
                    id: callInfo.id,
                    reference: self.initialCall?.reference ?? .id(id: callInfo.id, accessHash: callInfo.accessHash),
                    state: initialState,
                    previousServiceState: serviceState,
                    e2eContext: self.e2eContext
                )
                self.temporaryParticipantsContext = nil
                self.participantsContext = participantsContext
                
                if !self.didApplyInitialOutput {
                    self.didApplyInitialOutput = true
                    if !self.initialOutput.isMuted {
                        self.setIsMuted(action: .unmuted)
                    }
                    if let video = self.initialOutput.video {
                        self.requestVideo(deviceId: video.capturer, source: video.source)
                    }
                    if let video = self.initialOutput.screencast {
                        self.requestScreencast(deviceId: video.capturer, source: video.source)
                    }
                    self.initialOutput.video = nil
                    self.initialOutput.screencast = nil
                } else if self.hasVideo {
                    participantsContext.updateVideoState(peerId: self.joinAsPeerId, isVideoMuted: false, isVideoPaused: false, isPresentationPaused: nil)
                }
                
                let myPeer = self.accountContext.account.postbox.peerView(id: myPeerId)
                |> map { view -> (Peer, CachedPeerData?)? in
                    if let peer = peerViewMainPeer(view) {
                        return (peer, view.cachedData)
                    } else {
                        return nil
                    }
                }
                |> beforeNext { view in
                    if let view = view, view.1 == nil {
                        let _ = accountContext.engine.peers.fetchAndUpdateCachedPeerData(peerId: myPeerId).start()
                    }
                }
                
                let chatPeer: Signal<Peer?, NoError>
                
                if let peerId {
                    chatPeer = self.accountContext.account.postbox.peerView(id: peerId)
                    |> map { view -> Peer? in
                        if let peer = peerViewMainPeer(view), callInfo.isStream {
                            return peer
                        } else {
                            return nil
                        }
                    }
                } else {
                    chatPeer = .single(nil)
                }
                
                self.participantsContextStateDisposable.set(combineLatest(queue: .mainQueue(),
                    participantsContext.state,
                    participantsContext.activeSpeakers,
                    self.speakingParticipantsContext.get(),
                    adminIds,
                    myPeer,
                    chatPeer,
                    self.isReconnectingAsSpeakerPromise.get()
                ).start(next: { [weak self] state, activeSpeakers, speakingParticipants, adminIds, myPeerAndCachedData, chatPeer, isReconnectingAsSpeaker in
                    guard let strongSelf = self else {
                        return
                    }

                    strongSelf.participantsContext?.updateAdminIds(adminIds)
                    
                    var topParticipants: [GroupCallParticipantsContext.Participant] = []
                    
                    var reportSpeakingParticipants: [PeerId: UInt32] = [:]
                    let timestamp = CACurrentMediaTime()
                    for (peerId, ssrc) in speakingParticipants {
                        let shouldReport: Bool
                        if let previousTimestamp = strongSelf.speakingParticipantsReportTimestamp[peerId] {
                            shouldReport = previousTimestamp + 1.0 < timestamp
                        } else {
                            shouldReport = true
                        }
                        if shouldReport {
                            strongSelf.speakingParticipantsReportTimestamp[peerId] = timestamp
                            reportSpeakingParticipants[peerId] = ssrc
                        }
                    }
                    
                    if !reportSpeakingParticipants.isEmpty {
                        Queue.mainQueue().justDispatch {
                            self?.participantsContext?.reportSpeakingParticipants(ids: reportSpeakingParticipants)
                        }
                    }
                    
                    var members = PresentationGroupCallMembers(
                        participants: [],
                        speakingParticipants: Set(speakingParticipants.keys),
                        totalCount: 0,
                        loadMoreToken: nil
                    )
                    
                    var updatedInvitedPeers = strongSelf.invitedPeersValue
                    var didUpdateInvitedPeers = false

                    var participants = state.participants

                    if let (ignorePeerId, ignoreSsrc) = strongSelf.ignorePreviousJoinAsPeerId {
                        for i in 0 ..< participants.count {
                            if participants[i].id == .peer(ignorePeerId) && participants[i].ssrc == ignoreSsrc {
                                participants.remove(at: i)
                                break
                            }
                        }
                    }

                    if !participants.contains(where: { $0.id == .peer(myPeerId) }) && !strongSelf.leaving {
                        if let (myPeer, cachedData) = myPeerAndCachedData {
                            let about: String?
                            if let cachedData = cachedData as? CachedUserData {
                                about = cachedData.about
                            } else if let cachedData = cachedData as? CachedChannelData {
                                about = cachedData.about
                            } else {
                                about = nil
                            }

                            participants.append(GroupCallParticipantsContext.Participant(
                                id: .peer(myPeerId),
                                peer: .init(myPeer),
                                ssrc: nil,
                                videoDescription: nil,
                                presentationDescription: nil,
                                joinTimestamp: strongSelf.temporaryJoinTimestamp,
                                raiseHandRating: strongSelf.temporaryRaiseHandRating,
                                hasRaiseHand: strongSelf.temporaryHasRaiseHand,
                                activityTimestamp: strongSelf.temporaryActivityTimestamp,
                                activityRank: strongSelf.temporaryActivityRank,
                                muteState: strongSelf.temporaryMuteState ?? GroupCallParticipantsContext.Participant.MuteState(canUnmute: true, mutedByYou: false),
                                volume: nil,
                                about: about,
                                joinedVideo: strongSelf.temporaryVideoJoined,
                                paidStarsTotal: nil
                            ))
                            participants.sort(by: { GroupCallParticipantsContext.Participant.compare(lhs: $0, rhs: $1, sortAscending: state.sortAscending) })
                        }
                    }
                    
                    if let chatPeer = chatPeer {
                        participants.removeAll(where: { $0.id == .peer(chatPeer.id) })
                        participants.append(GroupCallParticipantsContext.Participant(
                            id: .peer(chatPeer.id),
                            peer: .init(chatPeer),
                            ssrc: 100,
                            videoDescription: GroupCallParticipantsContext.Participant.VideoDescription(
                                endpointId: "unified",
                                ssrcGroups: [],
                                audioSsrc: 100,
                                isPaused: false
                            ),
                            presentationDescription: nil,
                            joinTimestamp: strongSelf.temporaryJoinTimestamp,
                            raiseHandRating: nil,
                            hasRaiseHand: false,
                            activityTimestamp: nil,
                            activityRank: nil,
                            muteState: GroupCallParticipantsContext.Participant.MuteState(canUnmute: false, mutedByYou: false),
                            volume: nil,
                            about: nil,
                            joinedVideo: false,
                            paidStarsTotal: nil
                        ))
                        participants.sort(by: { GroupCallParticipantsContext.Participant.compare(lhs: $0, rhs: $1, sortAscending: state.sortAscending) })
                    }


                    
                    var otherParticipantsWithVideo = 0
                                        
                    for participant in participants {
                        var participant = participant
                        
                        if topParticipants.count < 3 {
                            topParticipants.append(participant)
                        }
                        
                        if let ssrc = participant.ssrc {
                            if let participantPeer = participant.peer {
                                strongSelf.ssrcMapping[ssrc] = SsrcMapping(peerId: participantPeer.id, isPresentation: false)
                            }
                        }
                        if let presentationSsrc = participant.presentationDescription?.audioSsrc {
                            if let participantPeer = participant.peer {
                                strongSelf.ssrcMapping[presentationSsrc] = SsrcMapping(peerId: participantPeer.id, isPresentation: true)
                            }
                        }

                        
                        if participant.id == .peer(strongSelf.joinAsPeerId) {
                            var filteredMuteState = participant.muteState
                            if isReconnectingAsSpeaker || strongSelf.currentConnectionMode != .rtc {
                                filteredMuteState = GroupCallParticipantsContext.Participant.MuteState(canUnmute: false, mutedByYou: false)
                                participant.muteState = filteredMuteState
                            }

                            if !(strongSelf.stateValue.muteState?.canUnmute ?? false) {
                                strongSelf.stateValue.raisedHand = participant.hasRaiseHand
                            }
                            strongSelf.applyParticipantMuteState(filteredMuteState)
                        } else {
                            if let ssrc = participant.ssrc {
                                if let volume = participant.volume {
                                    strongSelf.genericCallContext?.setVolume(ssrc: ssrc, volume: Double(volume) / 10000.0)
                                } else if participant.muteState?.mutedByYou == true {
                                    strongSelf.genericCallContext?.setVolume(ssrc: ssrc, volume: 0.0)
                                }
                            }
                            if let presentationSsrc = participant.presentationDescription?.audioSsrc {
                                if let volume = participant.volume {
                                    strongSelf.genericCallContext?.setVolume(ssrc: presentationSsrc, volume: Double(volume) / 10000.0)
                                } else if participant.muteState?.mutedByYou == true {
                                    strongSelf.genericCallContext?.setVolume(ssrc: presentationSsrc, volume: 0.0)
                                }
                            }

                            if participant.videoDescription != nil || participant.presentationDescription != nil {
                                otherParticipantsWithVideo += 1
                            }

                        }
                        
                        if let index = updatedInvitedPeers.firstIndex(where: { $0.id == participant.peer?.id }) {
                            updatedInvitedPeers.remove(at: index)
                            didUpdateInvitedPeers = true
                        }

                        members.participants.append(participant)
                    }
                    
                    members.totalCount = state.totalCount
                    members.loadMoreToken = state.nextParticipantsFetchOffset
                    
                    strongSelf.membersValue = members
                    
                    var stateValue = strongSelf.stateValue
                    
                    stateValue.adminIds = adminIds
                    
                    stateValue.canManageCall = state.isCreator || adminIds.contains(strongSelf.accountContext.account.peerId)
                    if (state.isCreator || stateValue.adminIds.contains(strongSelf.accountContext.account.peerId)) && state.defaultParticipantsAreMuted.canChange {
                        stateValue.defaultParticipantMuteState = state.defaultParticipantsAreMuted.isMuted ? .muted : .unmuted
                    }
                    
                    stateValue.messagesEnabled = state.messagesAreEnabled
                    stateValue.defaultSendAs = state.defaultSendAs
                    stateValue.sendPaidMessageStars = state.messagesAreEnabled.sendPaidMessagesStars
                    stateValue.recordingStartTimestamp = state.recordingStartTimestamp
                    stateValue.title = state.title
                    stateValue.scheduleTimestamp = state.scheduleTimestamp
                    stateValue.subscribedToScheduled = state.subscribedToScheduled
                    stateValue.isVideoEnabled = state.isVideoEnabled && otherParticipantsWithVideo < state.unmutedVideoLimit


                    strongSelf.stateValue = stateValue
                    
                    strongSelf.summaryInfoState.set(.single(SummaryInfoState(info: GroupCallInfo(
                        id: callInfo.id,
                        accessHash: callInfo.accessHash,
                        participantCount: state.totalCount,
                        streamDcId: nil,
                        title: state.title,
                        scheduleTimestamp: state.scheduleTimestamp,
                        subscribedToScheduled: state.subscribedToScheduled,
                        recordingStartTimestamp: state.recordingStartTimestamp,
                        sortAscending: state.sortAscending,
                        defaultParticipantsAreMuted: state.defaultParticipantsAreMuted,
                        messagesAreEnabled: state.messagesAreEnabled,
                        isVideoEnabled: state.isVideoEnabled,
                        unmutedVideoLimit: state.unmutedVideoLimit,
                        isStream: callInfo.isStream,
                        isCreator: callInfo.isCreator,
                        defaultSendAs: callInfo.defaultSendAs
                    ))))
                    
                    strongSelf.summaryParticipantsState.set(.single(SummaryParticipantsState(
                        participantCount: state.totalCount,
                        topParticipants: topParticipants,
                        activeSpeakers: activeSpeakers
                    )))
                    
                    if didUpdateInvitedPeers {
                        strongSelf.invitedPeersValue = updatedInvitedPeers
                    }
                }))
                
                let postbox = self.accountContext.account.postbox
                self.memberEventsPipeDisposable.set((participantsContext.memberEvents
                |> mapToSignal { event -> Signal<PresentationGroupCallMemberEvent, NoError> in
                    return postbox.transaction { transaction -> Signal<PresentationGroupCallMemberEvent, NoError> in
                        if let peer = transaction.getPeer(event.peerId) {
                            return .single(PresentationGroupCallMemberEvent(peer: peer, joined: event.joined))
                        } else {
                            return .complete()
                        }
                    }
                    |> switchToLatest
                }
                |> deliverOnMainQueue).start(next: { [weak self] event in
                    guard let strongSelf = self else {
                        return
                    }
                    if event.peer.id == strongSelf.stateValue.myPeerId {
                        return
                    }
                    strongSelf.memberEventsPipe.putNext(event)
                }))
                
                if let isCurrentlyConnecting = self.isCurrentlyConnecting, isCurrentlyConnecting {
                    self.startCheckingCallIfNeeded()
                }
            } else if case let .active(callInfo) = internalState, callInfo.scheduleTimestamp != nil {
                let accountContext = self.accountContext
                let peerId = self.peerId
                let rawAdminIds: Signal<Set<PeerId>, NoError>
                let adminIds: Signal<Set<PeerId>, NoError>
                if let peerId {
                    if peerId.namespace == Namespaces.Peer.CloudChannel {
                        rawAdminIds = Signal { subscriber in
                            let (disposable, _) = accountContext.peerChannelMemberCategoriesContextsManager.admins(peerId: peerId, updated: { list in
                                var peerIds = Set<PeerId>()
                                for item in list.list {
                                    if let adminInfo = item.participant.adminInfo, adminInfo.rights.rights.contains(.canManageCalls) {
                                        peerIds.insert(item.peer.id)
                                    }
                                }
                                subscriber.putNext(peerIds)
                            })
                            return disposable
                        }
                        |> distinctUntilChanged
                        |> runOn(.mainQueue())
                    } else {
                        rawAdminIds = accountContext.account.postbox.combinedView(keys: [.cachedPeerData(peerId: peerId)])
                        |> map { views -> Set<PeerId> in
                            guard let view = views.views[.cachedPeerData(peerId: peerId)] as? CachedPeerDataView else {
                                return Set()
                            }
                            guard let cachedData = view.cachedPeerData as? CachedGroupData, let participants = cachedData.participants else {
                                return Set()
                            }
                            return Set(participants.participants.compactMap { item -> PeerId? in
                                switch item {
                                case .creator, .admin:
                                    return item.peerId
                                default:
                                    return nil
                                }
                            })
                        }
                        |> distinctUntilChanged
                    }
                    adminIds = combineLatest(queue: .mainQueue(),
                        rawAdminIds,
                        accountContext.account.postbox.combinedView(keys: [.basicPeer(peerId)])
                    )
                    |> map { rawAdminIds, view -> Set<PeerId> in
                        var rawAdminIds = rawAdminIds
                        if let peerView = view.views[.basicPeer(peerId)] as? BasicPeerView, let peer = peerView.peer as? TelegramChannel {
                            if peer.hasPermission(.manageCalls) {
                                rawAdminIds.insert(accountContext.account.peerId)
                            } else {
                                rawAdminIds.remove(accountContext.account.peerId)
                            }
                        }
                        return rawAdminIds
                    }
                    |> distinctUntilChanged
                } else {
                    adminIds = .single(Set())
                }
                
                let participantsContext = self.accountContext.engine.calls.groupCall(
                    peerId: self.peerId,
                    myPeerId: self.joinAsPeerId,
                    id: callInfo.id,
                    reference: .id(id: callInfo.id, accessHash: callInfo.accessHash),
                    state: GroupCallParticipantsContext.State(
                        participants: [],
                        nextParticipantsFetchOffset: nil,
                        adminIds: Set(),
                        isCreator: false,
                        defaultParticipantsAreMuted: callInfo.defaultParticipantsAreMuted ?? GroupCallParticipantsContext.State.DefaultParticipantsAreMuted(isMuted: self.stateValue.defaultParticipantMuteState == .muted, canChange: true),
                        messagesAreEnabled: callInfo.messagesAreEnabled ?? .init(isEnabled: false, canChange: false, sendPaidMessagesStars: nil),
                        sortAscending: true,
                        recordingStartTimestamp: nil,
                        title: self.stateValue.title,
                        scheduleTimestamp: self.stateValue.scheduleTimestamp,
                        subscribedToScheduled: self.stateValue.subscribedToScheduled,
                        totalCount: 0,
                        isVideoEnabled: callInfo.isVideoEnabled,
                        unmutedVideoLimit: callInfo.unmutedVideoLimit,
                        isStream: callInfo.isStream,
                        sendPaidMessagesStars: self.stateValue.sendPaidMessageStars,
                        defaultSendAs: self.stateValue.defaultSendAs,
                        version: 0
                    ),
                    previousServiceState: nil,
                    e2eContext: self.e2eContext
                )
                self.temporaryParticipantsContext = nil
                self.participantsContext = participantsContext
                
                let myPeerId = self.joinAsPeerId
                let myPeer = self.accountContext.account.postbox.peerView(id: myPeerId)
                |> map { view -> (Peer, CachedPeerData?)? in
                    if let peer = peerViewMainPeer(view) {
                        return (peer, view.cachedData)
                    } else {
                        return nil
                    }
                }
                |> beforeNext { view in
                    if let view = view, view.1 == nil {
                        let _ = accountContext.engine.peers.fetchAndUpdateCachedPeerData(peerId: myPeerId).start()
                    }
                }
                               

                let chatPeer: Signal<Peer?, NoError>
                
                if let peerId {
                    chatPeer = self.accountContext.account.postbox.peerView(id: peerId)
                    |> map { view -> Peer? in
                        if let peer = peerViewMainPeer(view), callInfo.isStream {
                            return peer
                        } else {
                            return nil
                        }
                    }
                } else {
                    chatPeer = .single(nil)
                }
                
                let peerView: Signal<PeerView?, NoError>
                if let peerId {
                    peerView = accountContext.account.postbox.peerView(id: peerId) |> map(Optional.init)
                } else {
                    peerView = .single(nil)
                }


                
                self.participantsContextStateDisposable.set(combineLatest(queue: .mainQueue(),
                    participantsContext.state,
                    adminIds,
                    myPeer,
                    chatPeer,
                    peerView
                ).start(next: { [weak self] state, adminIds, myPeerAndCachedData, chatPeer, view in
                    guard let strongSelf = self else {
                        return
                    }
                    
                    var members = PresentationGroupCallMembers(
                        participants: [],
                        speakingParticipants: Set(),
                        totalCount: state.totalCount,
                        loadMoreToken: state.nextParticipantsFetchOffset
                    )
                    
                    var participants: [GroupCallParticipantsContext.Participant] = []
                    var topParticipants: [GroupCallParticipantsContext.Participant] = []
                    if let (myPeer, cachedData) = myPeerAndCachedData {
                        let about: String?
                        if let cachedData = cachedData as? CachedUserData {
                            about = cachedData.about
                        } else if let cachedData = cachedData as? CachedChannelData {
                            about = cachedData.about
                        } else {
                            about = nil
                        }
                        participants.append(GroupCallParticipantsContext.Participant(
                            id: .peer(myPeerId),
                            peer: .init(myPeer),
                            ssrc: nil,
                            videoDescription: nil,
                            presentationDescription: nil,
                            joinTimestamp: strongSelf.temporaryJoinTimestamp,
                            raiseHandRating: strongSelf.temporaryRaiseHandRating,
                            hasRaiseHand: strongSelf.temporaryHasRaiseHand,
                            activityTimestamp: strongSelf.temporaryActivityTimestamp,
                            activityRank: strongSelf.temporaryActivityRank,
                            muteState: strongSelf.temporaryMuteState ?? GroupCallParticipantsContext.Participant.MuteState(canUnmute: true, mutedByYou: false),
                            volume: nil,
                            about: about,
                            joinedVideo: strongSelf.temporaryVideoJoined,
                            paidStarsTotal: nil
                        ))
                    }
                    
                    if let chatPeer = chatPeer {
                        participants.removeAll(where: { $0.id == .peer(chatPeer.id) })
                        participants.append(GroupCallParticipantsContext.Participant(
                            id: .peer(chatPeer.id),
                            peer: .init(chatPeer),
                            ssrc: 100,
                            videoDescription: GroupCallParticipantsContext.Participant.VideoDescription(
                                endpointId: "unified",
                                ssrcGroups: [],
                                audioSsrc: 100,
                                isPaused: false
                            ),
                            presentationDescription: nil,
                            joinTimestamp: strongSelf.temporaryJoinTimestamp,
                            raiseHandRating: nil,
                            hasRaiseHand: false,
                            activityTimestamp: nil,
                            activityRank: nil,
                            muteState: GroupCallParticipantsContext.Participant.MuteState(canUnmute: false, mutedByYou: false),
                            volume: nil,
                            about: nil,
                            joinedVideo: false,
                            paidStarsTotal: nil
                        ))
                        participants.sort(by: { GroupCallParticipantsContext.Participant.compare(lhs: $0, rhs: $1, sortAscending: state.sortAscending) })
                    }


                    for participant in participants {
                        members.participants.append(participant)

                        if topParticipants.count < 3 {
                            topParticipants.append(participant)
                        }
                    }
                    
                    strongSelf.membersValue = members
                    
                    var stateValue = strongSelf.stateValue
                    
                    stateValue.adminIds = adminIds
                    stateValue.canManageCall = state.isCreator || adminIds.contains(strongSelf.accountContext.account.peerId)
                    if (state.isCreator || stateValue.adminIds.contains(strongSelf.accountContext.account.peerId)) && state.defaultParticipantsAreMuted.canChange {
                        stateValue.defaultParticipantMuteState = state.defaultParticipantsAreMuted.isMuted ? .muted : .unmuted
                    }
                    stateValue.messagesEnabled = state.messagesAreEnabled
                    stateValue.defaultSendAs = state.defaultSendAs
                    stateValue.recordingStartTimestamp = state.recordingStartTimestamp
                    stateValue.sendPaidMessageStars = state.messagesAreEnabled.sendPaidMessagesStars
                    stateValue.muteState = GroupCallParticipantsContext.Participant.MuteState(canUnmute: stateValue.canManageCall || !state.defaultParticipantsAreMuted.isMuted, mutedByYou: false)

                    
                    if let activeCall = (view?.cachedData as? CachedGroupData)?.activeCall {
                        stateValue.title = activeCall.title
                    } else if let activeCall = (view?.cachedData as? CachedChannelData)?.activeCall {
                        stateValue.title = activeCall.title
                    } else {
                        stateValue.title = state.title
                    }
                    
                    
                    stateValue.scheduleTimestamp = strongSelf.isScheduledStarted ? nil : state.scheduleTimestamp

                    strongSelf.stateValue = stateValue
                    
                    if state.scheduleTimestamp == nil && !strongSelf.isScheduledStarted {
                        strongSelf.updateSessionState(internalState: .active(GroupCallInfo(id: callInfo.id, accessHash: callInfo.accessHash, participantCount: state.totalCount, streamDcId: callInfo.streamDcId, title: state.title, scheduleTimestamp: nil, subscribedToScheduled: false, recordingStartTimestamp: nil, sortAscending: true, defaultParticipantsAreMuted: callInfo.defaultParticipantsAreMuted ?? state.defaultParticipantsAreMuted, messagesAreEnabled: state.messagesAreEnabled, isVideoEnabled: callInfo.isVideoEnabled, unmutedVideoLimit: callInfo.unmutedVideoLimit, isStream: callInfo.isStream, isCreator: state.isCreator, defaultSendAs: callInfo.defaultSendAs)))
                    } else if !strongSelf.isScheduledStarted {
                        strongSelf.summaryInfoState.set(.single(SummaryInfoState(info: GroupCallInfo(
                            id: callInfo.id,
                            accessHash: callInfo.accessHash,
                            participantCount: state.totalCount,
                            streamDcId: nil,
                            title: state.title,
                            scheduleTimestamp: state.scheduleTimestamp,
                            subscribedToScheduled: state.subscribedToScheduled,
                            recordingStartTimestamp: state.recordingStartTimestamp,
                            sortAscending: state.sortAscending,
                            defaultParticipantsAreMuted: state.defaultParticipantsAreMuted,
                            messagesAreEnabled: state.messagesAreEnabled,
                            isVideoEnabled: state.isVideoEnabled,
                            unmutedVideoLimit: state.unmutedVideoLimit,
                            isStream: callInfo.isStream,
                            isCreator: callInfo.isCreator,
                            defaultSendAs: callInfo.defaultSendAs
                        ))))
                        
                        strongSelf.summaryParticipantsState.set(.single(SummaryParticipantsState(
                            participantCount: state.totalCount,
                            topParticipants: topParticipants,
                            activeSpeakers: Set()
                        )))
                    }
                }))
            }

        }
    }
        

    private func requestMediaChannelDescriptions(ssrcs: Set<UInt32>, completion: @escaping ([OngoingGroupCallContext.MediaChannelDescription]) -> Void) -> Disposable {
        func extractMediaChannelDescriptions(remainingSsrcs: inout Set<UInt32>, participants: [GroupCallParticipantsContext.Participant], into result: inout [OngoingGroupCallContext.MediaChannelDescription]) {
            for participant in participants {
                guard let audioSsrc = participant.ssrc else {
                    continue
                }

                if remainingSsrcs.contains(audioSsrc) {
                    remainingSsrcs.remove(audioSsrc)
                    if let participantPeer = participant.peer {
                        result.append(OngoingGroupCallContext.MediaChannelDescription(
                            kind: .audio,
                            peerId: participantPeer.id.id._internalGetInt64Value(),
                            audioSsrc: audioSsrc,
                            videoDescription: nil
                        ))
                    }
                }

                if let screencastSsrc = participant.presentationDescription?.audioSsrc {
                    if remainingSsrcs.contains(screencastSsrc) {
                        remainingSsrcs.remove(screencastSsrc)
                        if let participantPeer = participant.peer {
                            result.append(OngoingGroupCallContext.MediaChannelDescription(
                                kind: .audio,
                                peerId: participantPeer.id.id._internalGetInt64Value(),
                                audioSsrc: screencastSsrc,
                                videoDescription: nil
                            ))
                        }
                    }
                }
            }
        }

        var remainingSsrcs = ssrcs
        var result: [OngoingGroupCallContext.MediaChannelDescription] = []

        if let membersValue = self.membersValue {
            extractMediaChannelDescriptions(remainingSsrcs: &remainingSsrcs, participants: membersValue.participants, into: &result)
        }

        if !remainingSsrcs.isEmpty, let callInfo = self.internalState.callInfo {
            return (accountContext.engine.calls.getGroupCallParticipants(reference: .id(id: callInfo.id, accessHash: callInfo.accessHash), offset: "", ssrcs: Array(remainingSsrcs), limit: 100, sortAscending: callInfo.sortAscending)
            |> deliverOnMainQueue).start(next: { state in
                extractMediaChannelDescriptions(remainingSsrcs: &remainingSsrcs, participants: state.participants, into: &result)

                completion(result)
            })
        } else {
            completion(result)
            return EmptyDisposable
        }
    }

    
    private func startCheckingCallIfNeeded() {
        if self.checkCallDisposable != nil {
            return
        }
        if case let .established(callInfo, connectionMode, _, ssrc, _) = self.internalState, case .rtc = connectionMode {
            let checkSignal = accountContext.engine.calls.checkGroupCall(callId: callInfo.id, accessHash: callInfo.accessHash, ssrcs: [ssrc])
            
            self.checkCallDisposable = ((
                checkSignal
                |> castError(Bool.self)
                |> delay(4.0, queue: .mainQueue())
                |> mapToSignal { result -> Signal<Bool, Bool> in
                    var foundAll = true
                    for value in [ssrc] {
                        if !result.contains(value) {
                            foundAll = false
                            break
                        }
                    }
                    if foundAll {
                        return .fail(true)
                    } else {
                        return .single(true)
                    }
                }
            )
            |> restartIfError
            |> take(1)
            |> deliverOnMainQueue).start(completed: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.checkCallDisposable = nil
                strongSelf.requestCall(movingFromBroadcastToRtc: false)
            })
        }
    }

    private func markAsCanBeRemoved() {
        if self.markedAsCanBeRemoved {
            return
        }
        self.markedAsCanBeRemoved = true
        self.leaving = true
        self.joinDisposable.dispose()
        self.requestDisposable.dispose()
        self.screencastJoinDisposable.dispose()
        self.screencastRequestDisposable.dispose()
        self.networkStateDisposable.dispose()
        self.audioLevelsDisposable.dispose()
        self.participantsContextStateDisposable.dispose()
        self.checkCallDisposable?.dispose()
        self.checkCallDisposable = nil
        self.myAudioLevelTimer?.invalidate()
        self.myAudioLevelTimer = nil
        self.typingDisposable.dispose()
        self.streamPlayer?.stop()
        self.streamPlayer = nil
        self.genericCallContext?.stop(account: account, reportCallId: nil, debugLog: .init(nil))
        self.screencastCallContext?.stop(account: account, reportCallId: nil, debugLog: .init(nil))
        self._canBeRemoved.set(.single(true))
    }
    
    public func joinAsSpeakerIfNeeded(_ joinHash: String) {
        self.invite = joinHash
        if let muteState = self.stateValue.muteState, !muteState.canUnmute {
            requestCall(movingFromBroadcastToRtc: true)
        }
    }
    public func resetListenerLink() {
        self.participantsContext?.resetInviteLinks()
    }
    
    public func reconnect(as peerId: PeerId) {
        if peerId == self.joinAsPeerId {
            return
        }
        
        if self.stateValue.scheduleTimestamp != nil, let callPeerId = self.peerId {
            updateGroupCallJoinAsDisposable.set(accountContext.engine.calls.updateGroupCallJoinAsPeer(peerId: callPeerId, joinAs: peerId).start())
        }
        
        let _ = (self.accountContext.account.postbox.transaction { transaction -> Peer? in
            return transaction.getPeer(peerId)
        }
        |> deliverOnMainQueue).start(next: { [weak self] myPeer in
            guard let strongSelf = self, let _ = myPeer else {
                return
            }

            strongSelf.reconnectingAsPeer = myPeer
            
            let previousPeerId = strongSelf.joinAsPeerId
            if let localSsrc = strongSelf.currentLocalSsrc {
                strongSelf.ignorePreviousJoinAsPeerId = (previousPeerId, localSsrc)
            }
            strongSelf.joinAsPeerId = peerId
            
            if let participantsContext = strongSelf.participantsContext, let immediateState = participantsContext.immediateState {
                for participant in immediateState.participants {
                    if participant.id == .peer(previousPeerId) {
                        strongSelf.temporaryJoinTimestamp = participant.joinTimestamp
                        strongSelf.temporaryActivityTimestamp = participant.activityTimestamp
                        strongSelf.temporaryVideoJoined = participant.joinedVideo
                        strongSelf.temporaryActivityRank = participant.activityRank
                        strongSelf.temporaryRaiseHandRating = participant.raiseHandRating
                        strongSelf.temporaryHasRaiseHand = participant.hasRaiseHand
                        strongSelf.temporaryMuteState = participant.muteState
                    }
                }
                strongSelf.switchToTemporaryParticipantsContext(sourceContext: participantsContext, oldMyPeerId: previousPeerId)
            } else {
                strongSelf.stateValue.myPeerId = peerId
            }
            
            strongSelf.requestCall(movingFromBroadcastToRtc: false)
        })
    }
    
    public func leave(terminateIfPossible: Bool) -> Signal<Bool, NoError> {
        self.leaving = true
        if let callInfo = self.internalState.callInfo, let localSsrc = self.currentLocalSsrc {
            if terminateIfPossible {
                self.leaveDisposable.set((accountContext.engine.calls.stopGroupCall(peerId: self.peerId, callId: callInfo.id, accessHash: callInfo.accessHash)
                |> deliverOnMainQueue).start(error: { [weak self] _ in
                    self?.markAsCanBeRemoved()
                }, completed: { [weak self] in
                    guard let strongSelf = self else {
                        return
                    }
                    strongSelf.markAsCanBeRemoved()
                }))
            } else {
                let contexts = CallsCoreHooks.shared.cachedGroupCallContexts(self.accountContext)
                let accountContext = self.accountContext
                let id = callInfo.id
                let accessHash = callInfo.accessHash
                let source = localSsrc
                contexts.impl.with { impl in
                    impl.leaveInBackground(engine: accountContext.engine, id: id, accessHash: accessHash, source: source)
                }
                self.markAsCanBeRemoved()
            }
        } else if let callInfo = self.internalState.callInfo, terminateIfPossible {
            self.leaveDisposable.set((accountContext.engine.calls.stopGroupCall(peerId: self.peerId, callId: callInfo.id, accessHash: callInfo.accessHash)
            |> deliverOnMainQueue).start(error: { [weak self] _ in
                self?.markAsCanBeRemoved()
            }, completed: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                strongSelf.markAsCanBeRemoved()
            }))
        } else {
            self.markAsCanBeRemoved()
        }
        return self._canBeRemoved.get()
    }
    
    public func toggleIsMuted() {
        
        if stateValue.networkState == .connecting || stateValue.scheduleTimestamp != nil {
            return
        }
        
        
        
        switch self.isMutedValue {
        case .muted:
            self.setIsMuted(action: .unmuted)
        case .unmuted:
            self.setIsMuted(action: .muted(isPushToTalkActive: false))
        }
    }
    
    private func applyParticipantMuteState(_ muteState: GroupCallParticipantsContext.Participant.MuteState?) {
        if muteState?.canUnmute == false || self.stateValue.muteState?.canUnmute == false {
            self.muteActionVersion += 1
            self.isMutedValue = .muted(isPushToTalkActive: false)
            self.isMutedPromise.set(self.isMutedValue)
            self.genericCallContext?.setIsMuted(true)
            self.stateValue.muteState = muteState ?? GroupCallParticipantsContext.Participant.MuteState(canUnmute: true, mutedByYou: false)
        } else if muteState != nil, self.isMutedValue == .unmuted {
            let _ = self.updateMuteState(peerId: self.joinAsPeerId, isMuted: false)
        }
    }

    public func setIsMuted(action: PresentationGroupCallMuteAction) {
        self.muteActionVersion += 1
        let muteActionVersion = self.muteActionVersion
        self.permissions(action, { [weak self] permission in
            guard let `self` = self, !self.leaving, !self.markedAsCanBeRemoved, self.muteActionVersion == muteActionVersion else {
                return
            }
            if !permission {
                return
            }
            if self.isMutedValue == action {
                return
            }
            if let muteState = self.stateValue.muteState, !muteState.canUnmute {
                return
            }
            self.isMutedValue = action
            self.isMutedPromise.set(self.isMutedValue)
            let isEffectivelyMuted: Bool
            let isVisuallyMuted: Bool
            
            
            
            
            switch self.isMutedValue {
            case let .muted(isPushToTalkActive):
                isEffectivelyMuted = !isPushToTalkActive
                isVisuallyMuted = true
                let _ = self.updateMuteState(peerId: self.joinAsPeerId, isMuted: true)
            case .unmuted:
                isEffectivelyMuted = false
                isVisuallyMuted = false
                let _ = self.updateMuteState(peerId: self.joinAsPeerId, isMuted: false)
            }
            self.genericCallContext?.setIsMuted(isEffectivelyMuted)
            

            if isVisuallyMuted {
                self.stateValue.muteState = GroupCallParticipantsContext.Participant.MuteState(canUnmute: true, mutedByYou: false)
            } else {
                self.stateValue.muteState = nil
            }
            
            if !isEffectivelyMuted {
                if let id = self.devicesContext.currentMicroId {
                    self.genericCallContext?.switchAudioInput(id)
                }
                if let id = self.devicesContext.currentOutputId {
                    self.genericCallContext?.switchAudioOutput(id)
                }
            }
        })
    }
    
    public func raiseHand() {
        guard let membersValue = self.membersValue else {
            return
        }
        for participant in membersValue.participants {
            if participant.id == .peer(self.joinAsPeerId) {
                if participant.hasRaiseHand {
                    return
                }
                break
            }
        }
        
        self.participantsContext?.raiseHand()
    }
    
    public func lowerHand() {
        guard let membersValue = self.membersValue else {
            return
        }
        for participant in membersValue.participants {
            if participant.id == .peer(self.joinAsPeerId) {
                if !participant.hasRaiseHand {
                    return
                }
                break
            }
        }
        
        self.participantsContext?.lowerHand()
    }
    
    public var mustStopSharing:(()->Void)?
    public var mustStopVideo:(()->Void)?
    
    public func requestScreencast(deviceId: OngoingCallVideoCapturer, source: VideoSourceMac) {
        guard !self.leaving, !self.markedAsCanBeRemoved, self.screencastCallContext == nil, let callInfo = self.internalState.callInfo else {
            return
        }
        self.screencastRequestDisposable.set(nil)
        self.screenCapturer = deviceId
        
        self.stateValue.sources.screencast = source
        
        self.screenCapturer?.setOnFatalError({ [weak self] in
            self?.mustStopSharing?()
        })
        
        self.screenCapturer?.setOnPause({ [weak self] paused in
            guard let strongSelf = self else {
                return
            }
            strongSelf.participantsContext?.updateVideoState(peerId: strongSelf.joinAsPeerId, isVideoMuted: nil, isVideoPaused: false, isPresentationPaused: paused)
        })
        
        var encryptionContext: OngoingGroupCallEncryptionContext?
        if let e2eContext = self.e2eContext {
            encryptionContext = OngoingGroupCallEncryptionContextImpl(e2eCall: e2eContext.state, channelId: 1)
        } else if self.isConference {
            encryptionContext = OngoingGroupCallEncryptionContextImpl(e2eCall: Atomic(value: ConferenceCallE2EContext.ContextStateHolder()), channelId: 1)
        }

        let screencastCallContext = OngoingGroupCallContext(audioSessionActive: .single(true), video: self.screenCapturer, requestMediaChannelDescriptions: { _, completion in
            completion([])
            return EmptyDisposable
        },
            rejoinNeeded: {},
            outgoingAudioBitrateKbit: nil,
            videoContentType: .screencast,
            enableNoiseSuppression: false,
            disableAudioInput: true,
            enableSystemMute: false,
            useReferenceImpl: true,
            prioritizeVP8: false,
            logPath: "",
            onMutedSpeechActivityDetected: { _ in },
            isConference: false,
            audioIsActiveByDefault: false,
            isStream: false,
            sharedAudioDevice: nil,
            encryptionContext: encryptionContext
        )

        self.screencastCallContext = screencastCallContext
        self.hasScreencast = true
        

        self.screencastJoinDisposable.set((screencastCallContext.joinPayload
        |> distinctUntilChanged(isEqual: { lhs, rhs in
            if lhs.0 != rhs.0 {
                return false
            }
            if lhs.1 != rhs.1 {
                return false
            }
            return true
        })
        |> deliverOnMainQueue).start(next: { [weak self, weak screencastCallContext] joinPayload, _ in
            guard let strongSelf = self, let screencastCallContext, strongSelf.screencastCallContext === screencastCallContext else {
                return
            }

            strongSelf.screencastRequestDisposable.set((strongSelf.accountContext.engine.calls.joinGroupCallAsScreencast(
                callId: callInfo.id,
                accessHash: callInfo.accessHash,
                joinPayload: joinPayload
            )
            |> deliverOnMainQueue).start(next: { [weak self, weak screencastCallContext] joinCallResult in
                guard let strongSelf = self, let screencastCallContext, strongSelf.screencastCallContext === screencastCallContext else {
                    return
                }
                let clientParams = joinCallResult.jsonParams

                screencastCallContext.setConnectionMode(.rtc, keepBroadcastConnectedIfWasEnabled: false, isUnifiedBroadcast: false)
                screencastCallContext.setJoinResponse(payload: clientParams)
                                
                strongSelf.stateValue.presentationEndpointId = joinCallResult.endpointId

            }, error: { [weak self, weak screencastCallContext] _ in
                guard let strongSelf = self, let screencastCallContext, strongSelf.screencastCallContext === screencastCallContext else {
                    return
                }
                strongSelf.disableScreencast()
                strongSelf.mustStopSharing?()
            }))
        }))
        
    }

    
    public func requestScreencast(deviceId: String, source: VideoSourceMac) {
        if self.screencastCallContext != nil {
            return
        }

        let screenCapturer = OngoingCallVideoCapturer(deviceId)
        requestScreencast(deviceId: screenCapturer, source: source)
    }
    
    public func disableScreencast() {
        self.screencastRequestDisposable.set(nil)
        self.hasScreencast = false
        
        self.stateValue.presentationEndpointId = nil
        if let screencastCallContext = self.screencastCallContext {
            self.screencastJoinDisposable.set(nil)
            self.screencastCallContext = nil
            screencastCallContext.disableVideo()
            screencastCallContext.stop(account: account, reportCallId: nil, debugLog: .init(nil))

            let maybeCallInfo: GroupCallInfo? = self.internalState.callInfo

            if let callInfo = maybeCallInfo {
                self.screencastJoinDisposable.set(accountContext.engine.calls.leaveGroupCallAsScreencast(
                    callId: callInfo.id,
                    accessHash: callInfo.accessHash
                ).start())
            }
        }
        self.screenCapturer = nil
        
        self.stateValue.sources.screencast = nil
    }
    
    public func toggleVideoFailed(failed: Bool) {
        self.stateValue.sources.failed = failed

    }


    public func requestVideo(deviceId: OngoingCallVideoCapturer, source: VideoSourceMac) {
        guard !self.leaving && !self.markedAsCanBeRemoved else {
            return
        }
        self.videoCapturer = deviceId

        self.videoCapturer?.setOnFatalError({ [weak self] in
            self?.mustStopVideo?()
        })
        self.hasVideo = true
        self.genericCallContext?.requestVideo(deviceId)
        self.participantsContext?.updateVideoState(peerId: self.joinAsPeerId, isVideoMuted: false, isVideoPaused: false, isPresentationPaused: nil)

        self.stateValue.sources.video = source
    }

    
    public func requestVideo(deviceId: String, source: VideoSourceMac) {
        if self.videoCapturer != nil {
            return
        }

        let videoCapturer = OngoingCallVideoCapturer(deviceId)
        self.requestVideo(deviceId: videoCapturer, source: source)
    }
    
    public func disableVideo() {
        self.hasVideo = false
        if let _ = self.videoCapturer {
            self.videoCapturer = nil
            self.genericCallContext?.disableVideo()
            self.participantsContext?.updateVideoState(peerId: self.joinAsPeerId, isVideoMuted: true, isVideoPaused: false, isPresentationPaused: nil)
        }
        self.stateValue.sources.video = nil
    }


    
    public func setVolume(peerId: PeerId, volume: Int32, sync: Bool) {
        var found = false
        for (ssrc, mapping) in self.ssrcMapping {
            if mapping.peerId == peerId {
                self.genericCallContext?.setVolume(ssrc: ssrc, volume: Double(volume) / 10000.0)
                found = true
            }
        }
        if found && sync {
            self.participantsContext?.updateMuteState(peerId: peerId, muteState: nil, volume: volume, raiseHand: nil)
        }
        
    }

    private var requestedVideoChannels: [OngoingGroupCallContext.VideoChannel] = []
    private var suspendVideoChannelRequests: Bool = false
    
    public func setSuspendVideoChannelRequests(_ value: Bool) {
        if CallVideoTuning.isOptimized, self.suspendVideoChannelRequests != value {
            self.suspendVideoChannelRequests = value
            self.genericCallContext?.setRequestedVideoChannels(value ? [] : self.requestedVideoChannels)
        }
    }
    
    public func setRequestedVideoList(items: [PresentationGroupCallRequestedVideo]) {
        let requestedVideoChannels = items.map { item -> OngoingGroupCallContext.VideoChannel in
            let mappedMinQuality: OngoingGroupCallContext.VideoChannel.Quality
            let mappedMaxQuality: OngoingGroupCallContext.VideoChannel.Quality
            switch item.minQuality {
            case .thumbnail:
                mappedMinQuality = .thumbnail
            case .medium:
                mappedMinQuality = .medium
            case .full:
                mappedMinQuality = .full
            }
            switch item.maxQuality {
            case .thumbnail:
                mappedMaxQuality = .thumbnail
            case .medium:
                mappedMaxQuality = .medium
            case .full:
                mappedMaxQuality = .full
            }
            return OngoingGroupCallContext.VideoChannel(
                audioSsrc: item.audioSsrc,
                peerId: item.peerId,
                endpointId: item.endpointId,
                ssrcGroups: item.ssrcGroups.map { group in
                    return OngoingGroupCallContext.VideoChannel.SsrcGroup(semantics: group.semantics, ssrcs: group.ssrcs)
                },
                minQuality: mappedMinQuality,
                maxQuality: mappedMaxQuality
            )
        }
        guard self.requestedVideoChannels != requestedVideoChannels else {
            return
        }
        self.requestedVideoChannels = requestedVideoChannels
        if !self.suspendVideoChannelRequests {
            self.genericCallContext?.setRequestedVideoChannels(self.requestedVideoChannels)
        }
    }


    
    public func updateMuteState(peerId: PeerId, isMuted: Bool) -> GroupCallParticipantsContext.Participant.MuteState? {
        let canThenUnmute: Bool
        if isMuted {
            var mutedByYou = false
            if peerId == self.joinAsPeerId {
                canThenUnmute = true
            } else if self.stateValue.canManageCall {
                if self.stateValue.adminIds.contains(peerId) {
                    canThenUnmute = true
                } else {
                    canThenUnmute = false
                }
            } else if self.stateValue.adminIds.contains(self.accountContext.account.peerId) {
                canThenUnmute = true
            } else {
                self.setVolume(peerId: peerId, volume: 0, sync: false)
                mutedByYou = true
                canThenUnmute = true
            }
            let muteState = isMuted ? GroupCallParticipantsContext.Participant.MuteState(canUnmute: canThenUnmute, mutedByYou: mutedByYou) : nil
            self.participantsContext?.updateMuteState(peerId: peerId, muteState: muteState, volume: nil, raiseHand: nil)
            return muteState
        } else {
            if peerId == self.joinAsPeerId {
                self.participantsContext?.updateMuteState(peerId: peerId, muteState: nil, volume: nil, raiseHand: nil)
                return nil
            } else if self.stateValue.canManageCall || self.stateValue.adminIds.contains(self.accountContext.account.peerId) {
                let muteState = GroupCallParticipantsContext.Participant.MuteState(canUnmute: true, mutedByYou: false)
                self.participantsContext?.updateMuteState(peerId: peerId, muteState: muteState, volume: nil, raiseHand: nil)
                return muteState
            } else {
                self.setVolume(peerId: peerId, volume: 10000, sync: true)
                self.participantsContext?.updateMuteState(peerId: peerId, muteState: nil, volume: nil, raiseHand: nil)
                return nil
            }
        }
    }

    public func setShouldBeRecording(_ shouldBeRecording: Bool, title: String?, videoOrientation: Bool?) {
        if !self.stateValue.canManageCall {
            return
        }
        if (self.stateValue.recordingStartTimestamp != nil) == shouldBeRecording {
            return
        }
        self.participantsContext?.updateShouldBeRecording(shouldBeRecording, title: title, videoOrientation: videoOrientation)
    }
    
    private func requestCall(movingFromBroadcastToRtc: Bool) {
        guard !self.leaving && !self.markedAsCanBeRemoved else {
            return
        }
        self.currentConnectionMode = .none
        self.genericCallContext?.setConnectionMode(.none, keepBroadcastConnectedIfWasEnabled: movingFromBroadcastToRtc, isUnifiedBroadcast: false)
                
        self.internalState = .requesting
        self.internalStatePromise.set(.single(.requesting))
        self.isCurrentlyConnecting = nil
        
        enum CallError {
            case generic
        }
        
        let currentCall: Signal<GroupCallInfo?, CallError>
        if let initialCall = self.initialCall {
            currentCall = accountContext.engine.calls.getCurrentGroupCall(reference: initialCall.reference)
            |> mapError { _ -> CallError in
                return .generic
            }
            |> map { summary -> GroupCallInfo? in
                return summary?.info
            }
        } else {
            currentCall = .single(nil)
        }
        
        self.networkStateDisposable.set(nil)
        self.joinDisposable.set(nil)
        
        self.checkCallDisposable?.dispose()
        self.checkCallDisposable = nil
        
        if movingFromBroadcastToRtc {
            self.stateValue.networkState = .connected
        } else {
            self.stateValue.networkState = .connecting
        }
        
        self.requestDisposable.set((currentCall
        |> deliverOnMainQueue).start(next: { [weak self] value in
            guard let strongSelf = self else {
                return
            }
            
            if let value = value {
                var reference: InternalGroupCallReference = .id(id: value.id, accessHash: value.accessHash)
                if let current = strongSelf.initialCall {
                    switch current.reference {
                    case .message, .link:
                        reference = current.reference
                    default:
                        break
                    }
                }
                strongSelf.initialCall = (EngineGroupCallDescription(id: value.id, accessHash: value.accessHash, title: value.title, scheduleTimestamp: nil, subscribedToScheduled: false, isStream: value.isStream), reference)
                strongSelf.callId = value.id
                strongSelf.isStream = value.isStream
                strongSelf.stateValue.isStream = value.isStream
                strongSelf.updateSessionState(internalState: .active(value))
            } else {
                strongSelf.markAsCanBeRemoved()
            }
        }, error: { [weak self] _ in
            self?.markAsCanBeRemoved()
        }))
    }
    
    
    public func invitePeer(_ peerId: PeerId, isVideo: Bool = false) -> Bool {
        if self.isConference {
            
            guard let initialCall = self.initialCall else {
                return false
            }
            
            if self.conferenceInvitationContexts[peerId] != nil {
                return false
            }
            var onStateUpdated: ((PendingConferenceInvitationContext.State) -> Void)?
            var onEnded: ((Bool) -> Void)?
            var didEndAlready = false
            let invitationContext = PendingConferenceInvitationContext(
                engine: self.accountContext.engine,
                reference: initialCall.reference,
                peerId: peerId,
                isVideo: isVideo,
                onStateUpdated: { state in
                    onStateUpdated?(state)
                },
                onEnded: { success in
                    didEndAlready = true
                    onEnded?(success)
                },
                onError: { [weak self] error in
                    self?.invitationErrorsPipe.putNext(error)
                }
            )
            if !didEndAlready {
                conferenceInvitationContexts[peerId] = invitationContext
                if !self.invitedPeersValue.contains(where: { $0.id == peerId }) {
                    self.invitedPeersValue.append(PresentationGroupCallInvitedPeer(id: peerId, state: .requesting))
                }
                onStateUpdated = { [weak self] state in
                    guard let self else {
                        return
                    }
                    if let index = self.invitedPeersValue.firstIndex(where: { $0.id == peerId }) {
                        var invitedPeer = self.invitedPeersValue[index]
                        switch state {
                        case .ringing:
                            invitedPeer.state = .ringing
                        }
                        self.invitedPeersValue[index] = invitedPeer
                    }
                }
                onEnded = { [weak self, weak invitationContext] success in
                    guard let self, let invitationContext else {
                        return
                    }
                    if self.conferenceInvitationContexts[peerId] === invitationContext {
                        self.conferenceInvitationContexts.removeValue(forKey: peerId)
                        
                        if success {
                            if let index = self.invitedPeersValue.firstIndex(where: { $0.id == peerId }) {
                                var invitedPeer = self.invitedPeersValue[index]
                                invitedPeer.state = .connecting
                                self.invitedPeersValue[index] = invitedPeer
                            }
                        } else {
                            self.invitedPeersValue.removeAll(where: { $0.id == peerId })
                        }
                    }
                }
            }
            
            return true

        } else {
            guard let callInfo = self.internalState.callInfo, !self.invitedPeersValue.contains(where: { $0.id == peerId }) else {
                return false
            }
            
            var updatedInvitedPeers = self.invitedPeersValue
            updatedInvitedPeers.insert(PresentationGroupCallInvitedPeer(id: peerId, state: nil), at: 0)
            self.invitedPeersValue = updatedInvitedPeers
            
            let _ = self.accountContext.engine.calls.inviteToGroupCall(callId: callInfo.id, accessHash: callInfo.accessHash, peerId: peerId).start()
            
            return true
        }
    }
    
    public func kickPeer(id: EnginePeer.Id) {
        if self.isConference {
            self.removedPeer(id)
            self.e2eContext?.kickPeer(id: id)
        }
    }

    
    public func removedPeer(_ peerId: PeerId) {
        var updatedInvitedPeers = self.invitedPeersValue
        updatedInvitedPeers.removeAll(where: { $0.id == peerId})
        self.invitedPeersValue = updatedInvitedPeers
        
        if let conferenceInvitationContext = self.conferenceInvitationContexts[peerId] {
            self.conferenceInvitationContexts.removeValue(forKey: peerId)
            if let messageId = conferenceInvitationContext.messageId {
                self.accountContext.engine.account.callSessionManager.dropOutgoingConferenceRequest(messageId: messageId)
            }
        }

    }
    
    public func updateTitle(_ title: String, force: Bool) {
        guard let callInfo = self.internalState.callInfo else {
            return
        }
        self.stateValue.title = title.isEmpty ? nil : title
        
        var signal = accountContext.engine.calls.editGroupCallTitle(callId: callInfo.id, accessHash: callInfo.accessHash, title: title)
        if !force {
            signal = signal |> delay(0.2, queue: .mainQueue())
        }
        updateTitleDisposable.set(signal.start())
    }
    
    public var inviteLinks: Signal<GroupCallInviteLinks?, NoError> {
        let engine = self.accountContext.engine
        let initialCall = self.initialCall
        let isConference = self.isConference

        return self.state
        |> map { state -> PeerId in
            return state.myPeerId
        }
        |> distinctUntilChanged
        |> mapToSignal { [weak self] _ -> Signal<GroupCallInviteLinks?, NoError> in
            guard let self = self else {
                return .complete()
            }
            return self.internalStatePromise.get()
            |> filter { state -> Bool in
                if case .requesting = state {
                    return false
                } else {
                    return true
                }
            }
            |> mapToSignal { state in
                if let callInfo = state.callInfo {
                    let reference: InternalGroupCallReference
                    if let initialCall = initialCall {
                        reference = initialCall.reference
                    } else {
                        reference = .id(id: callInfo.id, accessHash: callInfo.accessHash)
                    }
                    
                    return engine.calls.groupCallInviteLinks(reference: reference, isConference: isConference)
                } else {
                    return .complete()
                }
            }
        }
    }
    
    private var currentMyAudioLevel: Float = 0.0
    private var currentMyAudioLevelTimestamp: Double = 0.0
    private var isSendingTyping: Bool = false
    
    
    private func restartMyAudioLevelTimer() {
        self.myAudioLevelTimer?.invalidate()
        
        guard let peerId = self.peerId else {
            return
        }

        let myAudioLevelTimer = SwiftSignalKit.Timer(timeout: 0.1, repeat: false, completion: { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.myAudioLevelTimer = nil
            
            let timestamp = CACurrentMediaTime()
            
            var shouldBeSendingTyping = false
            if strongSelf.currentMyAudioLevel > 0.01 && timestamp < strongSelf.currentMyAudioLevelTimestamp + 1.0 {
                strongSelf.restartMyAudioLevelTimer()
                shouldBeSendingTyping = true
            } else {
                if timestamp < strongSelf.currentMyAudioLevelTimestamp + 1.0 {
                    strongSelf.restartMyAudioLevelTimer()
                    shouldBeSendingTyping = true
                }
            }
            if shouldBeSendingTyping != strongSelf.isSendingTyping {
                strongSelf.isSendingTyping = shouldBeSendingTyping
                if shouldBeSendingTyping {
                    strongSelf.typingDisposable.set(strongSelf.accountContext.account.acquireLocalInputActivity(peerId: PeerActivitySpace(peerId: peerId, category: .voiceChat), activity: .speakingInGroupCall(timestamp: 0)))
                    strongSelf.restartMyAudioLevelTimer()
                } else {
                    strongSelf.typingDisposable.set(nil)
                }
            }
        }, queue: .mainQueue())
        self.myAudioLevelTimer = myAudioLevelTimer
        myAudioLevelTimer.start()
    }
    
    private func processMyAudioLevel(level: Float, hasVoice: Bool) {
        self.currentMyAudioLevel = level
        
        if level > 0.01 && hasVoice {
            self.currentMyAudioLevelTimestamp = CACurrentMediaTime()
            
            if self.myAudioLevelTimer == nil {
                self.restartMyAudioLevelTimer()
            }
        }
    }
    
    public func updateDefaultParticipantsAreMuted(isMuted: Bool) {
        self.participantsContext?.updateDefaultParticipantsAreMuted(isMuted: isMuted)
    }
    
    public func switchVideoInput(_ deviceId: String) {
        videoCapturer?.switchVideoInput(deviceId)
    }
    
   
    private final class SharedVideoSource {
        weak var value: VideoSource?
        weak var context: OngoingGroupCallContext?
        init(_ value: VideoSource, context: OngoingGroupCallContext) {
            self.value = value
            self.context = context
        }
    }
    private var sharedVideoSources: [String: SharedVideoSource] = [:]
    
    private func sharedVideoSource(context: OngoingGroupCallContext, endpointId: String, videoMode: GroupCallVideoMode) -> VideoSource {
        self.sharedVideoSources = self.sharedVideoSources.filter { $0.value.value != nil && $0.value.context != nil }
        let key = "\(videoMode)-\(endpointId)"
        if CallVideoTuning.isOptimized, let current = self.sharedVideoSources[key], current.context === context, let value = current.value {
            return value
        }
        let source = MetalVideoMakeSource(videoStreamSignal: context.video(endpointId: endpointId))
        self.sharedVideoSources[key] = SharedVideoSource(source, context: context)
        return source
    }
    
    public func makeVideoView(endpointId: String, videoMode: GroupCallVideoMode, completion: @escaping (PresentationCallVideoView?) -> Void) {
        if endpointId == "unified", let streamPlayer = self.streamPlayer {
            completion(streamPlayer.makeVideoView())
            return
        }
        let context: OngoingGroupCallContext?
        switch videoMode {
        case .video:
            context = self.genericCallContext
        case .screencast:
            context = self.screencastCallContext
        }
        
        guard let context = context else {
            completion(nil)
            return
        }
        
#if arch(arm64)
        let useMetal = true
#else
        let useMetal = self.supportsBroadcastListener && !self.isConference && context === self.genericCallContext
#endif
        if useMetal {
            let videoView = MetalVideoMakeView(videoSource: self.sharedVideoSource(context: context, endpointId: endpointId, videoMode: videoMode))

            completion(PresentationCallVideoView(holder: videoView, view: videoView, setOnFirstFrameReceived: { [weak videoView] f in
                videoView?.firstFrameRendered = {
                    f?(0)
                }
            }, getOrientation: {
                .rotation0
            }, getAspect: {
                return 0
            }, setVideoContentMode: { [weak videoView] gravity in
                videoView?.setGravity(gravity)
            }, setOnOrientationUpdated: { _ in
            }, setOnIsMirroredUpdated: { _ in
            }, setIsPaused: { [weak videoView] paused in
                videoView?.isPaused = paused
            }, renderToSize: { [weak videoView] size, animated in
                videoView?.updateLayout(size: size, transition: animated ? .animated(duration: 0.3, curve: .easeOut) : .immediate)
            }))
            return
        }
        context.makeIncomingVideoView(endpointId: endpointId, requestClone: false, completion: { view, _ in
            if let view = view {
                let setOnFirstFrameReceived = view.setOnFirstFrameReceived
                let setOnOrientationUpdated = view.setOnOrientationUpdated
                let setOnIsMirroredUpdated = view.setOnIsMirroredUpdated
                completion(PresentationCallVideoView(
                    holder: view,
                    view: view.view,
                    setOnFirstFrameReceived: { f in
                        setOnFirstFrameReceived(f)

                    },
                    getOrientation: { [weak view] in
                        if let view = view {
                            let mappedValue: PresentationCallVideoView.Orientation
                            switch view.getOrientation() {
                            case .rotation0:
                                mappedValue = .rotation0
                            case .rotation90:
                                mappedValue = .rotation90
                            case .rotation180:
                                mappedValue = .rotation180
                            case .rotation270:
                                mappedValue = .rotation270
                            }
                            return mappedValue
                        } else {
                            return .rotation0
                        }
                    },
                    getAspect: { [weak view] in
                        if let view = view {
                            return view.getAspect()
                        } else {
                            return 0.0
                        }
                    }, setVideoContentMode: { [weak view] mode in
                        view?.setVideoContentMode(mode)
                    },
                    setOnOrientationUpdated: { f in
                        setOnOrientationUpdated { value, aspect in
                            let mappedValue: PresentationCallVideoView.Orientation
                            switch value {
                            case .rotation0:
                                mappedValue = .rotation0
                            case .rotation90:
                                mappedValue = .rotation90
                            case .rotation180:
                                mappedValue = .rotation180
                            case .rotation270:
                                mappedValue = .rotation270
                            }
                            f?(mappedValue, aspect)
                        }
                    },
                    setOnIsMirroredUpdated: { f in
                        setOnIsMirroredUpdated { value in
                            f?(value)
                        }
                    }, setIsPaused: { [weak view] paused in
                        view?.setIsPaused(paused)
                    }, renderToSize: { [weak view] size, animated in
                        view?.renderToSize(size, animated)
                    }
                ))
            } else {
                completion(nil)
            }
        })
    }

    public func loadMore() {
        if let token = self.membersValue?.loadMoreToken {
            self.participantsContext?.loadMore(token: token)
        }
    }
    public func startScheduled() {
        guard case let .active(callInfo) = self.internalState else {
            return
        }
        
        guard let peerId = self.peerId else {
            return
        }

        
        self.isScheduledStarted = true
        self.stateValue.scheduleTimestamp = nil
        
        self.startDisposable.set((accountContext.engine.calls.startScheduledGroupCall(peerId: peerId, callId: callInfo.id, accessHash: callInfo.accessHash)
        |> deliverOnMainQueue).start(next: { [weak self] callInfo in
            guard let strongSelf = self else {
                return
            }
            strongSelf.updateSessionState(internalState: .active(callInfo))
        }))
    }
        
    public func toggleScheduledSubscription(_ subscribe: Bool) {
        guard case let .active(callInfo) = self.internalState, callInfo.scheduleTimestamp != nil, self.peerId != nil else {
            return
        }
        
        guard let peerId = self.peerId else {
            return
        }
        
        self.stateValue.subscribedToScheduled = subscribe
        
        self.subscribeDisposable.set((accountContext.engine.calls.toggleScheduledGroupCallSubscription(peerId: peerId, reference: .id(id: callInfo.id, accessHash: callInfo.accessHash), subscribe: subscribe)
        |> deliverOnMainQueue).start())
    }
    
    public func sendMessage(text: String, entities: [MessageTextEntity], paidStars: Int64?) {
        if let messagesContext = self.messagesContext {
            messagesContext.send(fromId: stateValue.defaultSendAs ?? stateValue.myPeerId, isAdmin: self.stateValue.adminIds.contains(stateValue.myPeerId), randomId: nil, text: text, entities: entities, paidStars: paidStars)
        }
    }
    
    public func sendStars(amount: Int64) {
        if let messagesContext = self.messagesContext {
            messagesContext.sendStars(fromId: stateValue.defaultSendAs ?? stateValue.myPeerId, isAdmin: self.stateValue.adminIds.contains(stateValue.myPeerId), amount: amount, delay: true)
        }
    }
    
    public func deleteMessage(id: GroupCallMessagesContext.Message.Id, authorId: EnginePeer.Id, reportSpam: Bool, deleteAll: Bool) {
        if let messagesContext = self.messagesContext {
            if deleteAll {
                messagesContext.deleteAllMessages(authorId: authorId, reportSpam: reportSpam)
            } else {
                messagesContext.deleteMessage(id: id, reportSpam: reportSpam)
            }
        }
    }

    
    public func setDefaultSendAs(_ peerId: PeerId?) {
        self.stateValue.defaultSendAs = peerId
    }

    public func updateMessagesEnabled(isEnabled: Bool) {
        self.participantsContext?.updateMessagesEnabled(isEnabled: isEnabled, sendPaidMessageStars: nil)
    }
    
}

