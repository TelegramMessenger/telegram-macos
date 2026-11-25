import Foundation
import Postbox
import TelegramCore

import SwiftSignalKit

public enum PeerChannelMemberContextKey: Equatable, Hashable {
    case recent
    case recentSearch(String)
    case mentions(threadId: MessageId?, query: String?)
    case admins(String?)
    case contacts(String?)
    case bots(String?)
    case restrictedAndBanned(String?)
    case restricted(String?)
    case banned(String?)
    
}


private final class PeerChannelMembersOnlineContext {
    public let subscribers = Bag<(Int32) -> Void>()
    public let disposable: Disposable
    public var value: Int32?
    public var emptyTimer: SwiftSignalKit.Timer?
    
    public init(disposable: Disposable) {
        self.disposable = disposable
    }
}


private struct PeerParticipantKey: Hashable {
    public let peerId: PeerId
    public let participantId: PeerId
}

private final class PeerChannelMemberCategoriesContextsManagerImpl {
    fileprivate var contexts: [PeerId: PeerChannelMemberCategoriesContext] = [:]
    fileprivate var onlineContexts: [PeerId: PeerChannelMembersOnlineContext] = [:]
    fileprivate var cachedParticipants: [PeerParticipantKey: RenderedChannelParticipant] = [:]

    fileprivate let engine: TelegramEngine
    fileprivate let account: Account
    public init(_ engine: TelegramEngine, account: Account) {
        self.engine = engine
        self.account = account
    }

    public func getContext(peerId: PeerId, key: PeerChannelMemberContextKey, requestUpdate: Bool, updated: @escaping (ChannelMemberListState) -> Void) -> (Disposable, PeerChannelMemberCategoryControl) {
        if let current = self.contexts[peerId] {
            return current.getContext(key: key, requestUpdate: requestUpdate, updated: updated)
        } else {
            var becameEmptyImpl: ((Bool) -> Void)?
            let context = PeerChannelMemberCategoriesContext(engine: engine, account: account, peerId: peerId, becameEmpty: { value in
                becameEmptyImpl?(value)
            })
            becameEmptyImpl = { [weak self, weak context] value in
                assert(Queue.mainQueue().isCurrent())
                if let strongSelf = self {
                    if let current = strongSelf.contexts[peerId], current === context {
                        strongSelf.contexts.removeValue(forKey: peerId)
                    }
                }
            }
            self.contexts[peerId] = context
            return context.getContext(key: key, requestUpdate: requestUpdate, updated: updated)
        }
    }
    
    public func recentOnline(peerId: PeerId, updated: @escaping (Int32) -> Void) -> Disposable {
        let context: PeerChannelMembersOnlineContext
        if let current = self.onlineContexts[peerId] {
            context = current
        } else {
            let disposable = MetaDisposable()
            context = PeerChannelMembersOnlineContext(disposable: disposable)
            self.onlineContexts[peerId] = context
            
            let signal = (
                engine.peers.chatOnlineMembers(peerId: peerId)
                    |> then(
                        .complete()
                            |> delay(30.0, queue: .mainQueue())
                )
                ) |> restart
            
            disposable.set(signal.start(next: { [weak context] value in
                guard let context = context else {
                    return
                }
                context.value = value
                for f in context.subscribers.copyItems() {
                    f(value)
                }
            }))
        }
        
        if let emptyTimer = context.emptyTimer {
            emptyTimer.invalidate()
            context.emptyTimer = nil
        }
        
        let index = context.subscribers.add({ next in
            updated(next)
        })
        updated(context.value ?? 0)
        
        return ActionDisposable { [weak self, weak context] in
            Queue.mainQueue().async {
                guard let strongSelf = self else {
                    return
                }
                if let current = strongSelf.onlineContexts[peerId], let context = context, current === context {
                    current.subscribers.remove(index)
                    if current.subscribers.isEmpty {
                        if current.emptyTimer == nil {
                            let timer = SwiftSignalKit.Timer(timeout: 60.0, repeat: false, completion: { [weak context] in
                                if let current = strongSelf.onlineContexts[peerId], let context = context, current === context {
                                    if current.subscribers.isEmpty {
                                        strongSelf.onlineContexts.removeValue(forKey: peerId)
                                        current.disposable.dispose()
                                    }
                                }
                                }, queue: Queue.mainQueue())
                            current.emptyTimer = timer
                            timer.start()
                        }
                    }
                }
            }
        }
    }
    

    
    public func loadMore(peerId: PeerId, control: PeerChannelMemberCategoryControl) {
        if let context = self.contexts[peerId] {
            context.loadMore(control)
        }
    }
}

public final class PeerChannelMemberCategoriesContextsManager {
    private let impl: QueueLocalObject<PeerChannelMemberCategoriesContextsManagerImpl>
    
    private let engine: TelegramEngine
    private let account: Account
    public init(_ engine: TelegramEngine, account: Account) {
        self.engine = engine
        self.account = account
        self.impl = QueueLocalObject(queue: Queue.mainQueue(), generate: {
            return PeerChannelMemberCategoriesContextsManagerImpl(engine, account: account)
        })
    }

    public func loadMore(peerId: PeerId, control: PeerChannelMemberCategoryControl?) {
        if let control = control {
            self.impl.with { impl in
                impl.loadMore(peerId: peerId, control: control)
            }
        }
    }
    
    private func getContext(peerId: PeerId, key: PeerChannelMemberContextKey, requestUpdate: Bool, updated: @escaping (ChannelMemberListState) -> Void) -> (Disposable, PeerChannelMemberCategoryControl?) {
        assert(Queue.mainQueue().isCurrent())
        
        return self.impl.syncWith({ impl in
            return impl.getContext(peerId: peerId, key: key, requestUpdate: requestUpdate, updated: updated)
        })

    }
    
    public func transferOwnership(peerId: PeerId, memberId: PeerId, password: String) -> Signal<Void, ChatOwnershipTransferError> {
        return engine.peers.updateChatOwnership(peerId: peerId, memberId: memberId, password: password)
            |> map(Optional.init)
            |> deliverOnMainQueue
            |> beforeNext { [weak self] results in
                if let strongSelf = self, let results = results {
                    strongSelf.impl.with { impl in
                        for (contextPeerId, context) in impl.contexts {
                            if peerId == contextPeerId {
                                context.replayUpdates(results.map { ($0.0, $0.1, nil) })
                            }
                        }
                    }
                }
            }
            |> mapToSignal { _ -> Signal<Void, ChatOwnershipTransferError> in
                return .complete()
        }
    }

    
    public func fetchParticipant(peerId: PeerId, participantId: PeerId) -> Signal<RenderedChannelParticipant?, NoError> {
        let cached: RenderedChannelParticipant? = self.impl.syncWith { impl in
            return impl.cachedParticipants[PeerParticipantKey(peerId: peerId, participantId: participantId)]
        }
        if let cached = cached {
            return .single(cached)
        }
        let engine = self.engine
        let account = self.account
        return engine.peers.fetchChannelParticipant(peerId: peerId, participantId: participantId)
            |> mapToSignal { participant -> Signal<RenderedChannelParticipant?, NoError> in
                guard let participant = participant else { return .single(nil) }
                return account.postbox.loadedPeerWithId(participantId) |> map { peer in
                    return RenderedChannelParticipant(participant: participant, peer: .init(peer))
                }
            }
            |> take(1)
            |> deliverOnMainQueue
            |> beforeNext { [weak self] rendered in
                if let rendered = rendered {
                    self?.impl.with { impl in
                        impl.cachedParticipants[PeerParticipantKey(peerId: peerId, participantId: participantId)] = rendered
                    }
                }
            }
    }

    public func externallyAdded(peerId: PeerId, participant: RenderedChannelParticipant) {
        self.impl.with { impl in
            for (contextPeerId, context) in impl.contexts {
                if contextPeerId == peerId {
                    context.replayUpdates([(nil, participant, nil)])
                }
            }
        }
    }
    
    public func mentions(peerId: PeerId, threadMessageId: MessageId?, searchQuery: String? = nil, requestUpdate: Bool = true, updated: @escaping (ChannelMemberListState) -> Void) -> (Disposable, PeerChannelMemberCategoryControl?) {
        let key: PeerChannelMemberContextKey = .mentions(threadId: threadMessageId, query: searchQuery)
        return self.getContext(peerId: peerId, key: key, requestUpdate: requestUpdate, updated: updated)
    }
    
    public func recent(peerId: PeerId, searchQuery: String? = nil, requestUpdate: Bool = true, updated: @escaping (ChannelMemberListState) -> Void) -> (Disposable, PeerChannelMemberCategoryControl?) {
        let key: PeerChannelMemberContextKey
        if let searchQuery = searchQuery {
            key = .recentSearch(searchQuery)
        } else {
            key = .recent
        }
        return self.getContext(peerId: peerId, key: key, requestUpdate: requestUpdate, updated: updated)
    }
    
    public func recentOnline(peerId: PeerId) -> Signal<Int32, NoError> {
        return Signal { [weak self] subscriber in
            guard let strongSelf = self else {
                subscriber.putNext(0)
                subscriber.putCompletion()
                return EmptyDisposable
            }
            let disposable = strongSelf.impl.syncWith({ impl -> Disposable in
                return impl.recentOnline(peerId: peerId, updated: { value in
                    subscriber.putNext(value)
                })
            })
            return disposable
            }
            |> runOn(Queue.mainQueue())
    }

    
    public func recentOnlineSmall(peerId: PeerId) -> Signal<Int32, NoError> {
        return recentOnlineSmallCounts(peerId: peerId) |> map { $0.recent } |> distinctUntilChanged
    }

    public func recentOnlineSmallCounts(peerId: PeerId) -> Signal<(total: Int32, recent: Int32), NoError> {
        let account = self.account
        return Signal { [weak self] subscriber in
            guard let strongSelf = self else {
                return EmptyDisposable
            }
            var previousIds: Set<PeerId>?
            let statusesDisposable = MetaDisposable()
            let disposableAndControl = self?.recent(peerId: peerId, updated: { state in
                var idList: [PeerId] = []
                for item in state.list {
                    idList.append(item.peer.id)
                    if idList.count >= 200 {
                        break
                    }
                }
                let updatedIds = Set(idList)
                if previousIds != updatedIds {
                    previousIds = updatedIds
                    let key: PostboxViewKey = .peerPresences(peerIds: updatedIds)
                    statusesDisposable.set((strongSelf.account.postbox.combinedView(keys: [key])
                        |> map { view -> Int32 in
                            var count: Int32 = 0
                            let timestamp = CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970
                            if let presences = (view.views[key] as? PeerPresencesView)?.presences {
                                for (_, presence) in presences {
                                    if let presence = presence as? TelegramUserPresence {
                                        let networkTime = account.network.globalTime > 0 ? account.network.globalTime - timestamp : 0
                                        
                                        let relativeStatus = relativeUserPresenceStatus(presence, timeDifference: networkTime, relativeTo: Int32(timestamp))
                                        sw: switch relativeStatus {
                                        case let .online(at: until):
                                            if until > Int32(timestamp) {
                                                count += 1
                                            }
                                        default:
                                            break sw
                                        }
                                    }
                                }
                            }
                            return count
                        }
                        |> distinctUntilChanged
                        |> deliverOnMainQueue).start(next: { count in
                            subscriber.putNext((Int32(updatedIds.count), count))
                        }))
                }
            })
            return ActionDisposable {
                disposableAndControl?.0.dispose()
                statusesDisposable.dispose()
            }
            }
            |> runOn(Queue.mainQueue())
        
    }
    
    public func admins(peerId: PeerId, searchQuery: String? = nil, updated: @escaping (ChannelMemberListState) -> Void) -> (Disposable, PeerChannelMemberCategoryControl?) {
        return self.getContext(peerId: peerId, key: .admins(searchQuery), requestUpdate: true, updated: updated)
    }
    
    public func restricted(peerId: PeerId, searchQuery: String? = nil, updated: @escaping (ChannelMemberListState) -> Void) -> (Disposable, PeerChannelMemberCategoryControl?) {
        return self.getContext(peerId: peerId, key: .restricted(searchQuery), requestUpdate: true, updated: updated)
    }
    
    public func contacts(peerId: PeerId, searchQuery: String? = nil, updated: @escaping (ChannelMemberListState) -> Void) -> (Disposable, PeerChannelMemberCategoryControl?) {
        return self.getContext(peerId: peerId, key: .contacts(searchQuery), requestUpdate: true, updated: updated)
    }
    
    public func banned(peerId: PeerId, searchQuery: String? = nil, updated: @escaping (ChannelMemberListState) -> Void) -> (Disposable, PeerChannelMemberCategoryControl?) {
        return self.getContext(peerId: peerId, key: .banned(searchQuery), requestUpdate: true, updated: updated)
    }
    
    public func restrictedAndBanned(peerId: PeerId, searchQuery: String? = nil, updated: @escaping (ChannelMemberListState) -> Void) -> (Disposable, PeerChannelMemberCategoryControl?) {
        return self.getContext(peerId: peerId, key: .restrictedAndBanned(searchQuery), requestUpdate: true, updated: updated)
    }
    
    public func updateMemberBannedRights(peerId: PeerId, memberId: PeerId, bannedRights: TelegramChatBannedRights?) -> Signal<Void, NoError> {
        return engine.peers.updateChannelMemberBannedRights(peerId: peerId, memberId: memberId, rights: bannedRights)
            |> deliverOnMainQueue
            |> beforeNext { [weak self] (previous, updated, isMember) in
                if let strongSelf = self {
                    strongSelf.impl.with { impl in
                        for (contextPeerId, context) in impl.contexts {
                            if peerId == contextPeerId {
                                context.replayUpdates([(previous, updated, isMember)])
                            }
                        }
                    }
                }
            }
            |> mapToSignal { _ -> Signal<Void, NoError> in
                return .complete()
        }
    }
    
    public func updateMemberAdminRights(peerId: PeerId, memberId: PeerId, adminRights: TelegramChatAdminRights?, rank: String?, guardBotId: PeerId? = nil) -> Signal<PeerId, UpdateChannelAdminRightsError> {
        let engine = self.engine
        return engine.peers.updateChannelAdminRights(peerId: peerId, adminId: memberId, rights: adminRights, rank: rank)
            |> deliverOnMainQueue
            |> beforeNext { [weak self] result in
                if let strongSelf = self {
                    let (previous, updated) = result
                    strongSelf.impl.with { impl in
                        for (contextPeerId, context) in impl.contexts {
                            if peerId == contextPeerId {
                                context.replayUpdates([(previous, updated, nil)])
                            }
                        }
                    }
                }
            }
            |> mapToSignal { _ -> Signal<PeerId, UpdateChannelAdminRightsError> in
                if let guardBotId {
                    return engine.peers.toggleChannelJoinRequest(peerId: peerId, enabled: true, guardBotId: guardBotId)
                        |> `catch` { _ -> Signal<Never, NoError> in .complete() }
                        |> castError(UpdateChannelAdminRightsError.self)
                        |> map { _ -> PeerId in return memberId }
                        |> then(.single(memberId))
                }
                return .single(memberId)
        }
    }
    
    public func updateChatRank(peerId: PeerId, memberId: PeerId, rank: String?, participant: RenderedChannelParticipant) -> Signal<Void, UpdateChatRankError> {
        let account = self.account
        return Signal { [weak self] subscriber in
            guard let strongSelf = self else {
                subscriber.putCompletion()
                return EmptyDisposable
            }
            return strongSelf.engine.peers.updateChatRank(peerId: peerId, userId: memberId, rank: rank).start(error: { error in
                subscriber.putError(error)
            }, completed: { [weak self] in
                Queue.mainQueue().async {
                    let updatedParticipant: ChannelParticipant
                    switch participant.participant {
                    case let .creator(id, adminInfo, _):
                        updatedParticipant = .creator(id: id, adminInfo: adminInfo, rank: rank)
                    case let .member(id, invitedAt, adminInfo, banInfo, _, subscriptionUntilDate):
                        updatedParticipant = .member(id: id, invitedAt: invitedAt, adminInfo: adminInfo, banInfo: banInfo, rank: rank, subscriptionUntilDate: subscriptionUntilDate)
                    }
                    let updated = RenderedChannelParticipant(participant: updatedParticipant, peer: participant.peer, peers: participant.peers, presences: participant.presences)
                    if let strongSelf = self {
                        strongSelf.impl.with { impl in
                            for (contextPeerId, context) in impl.contexts {
                                if peerId == contextPeerId {
                                    context.replayUpdates([(participant.participant, updated, nil)])
                                }
                            }
                            impl.cachedParticipants[PeerParticipantKey(peerId: peerId, participantId: memberId)] = updated
                        }
                    }
                    let _ = (account.postbox.transaction { transaction in
                        let entryId = cachedChannelAdminRanksEntryId(peerId: peerId)
                        var ranks: [PeerId: CachedChannelAdminRank] = [:]
                        if let data = transaction.retrieveItemCacheEntry(id: entryId)?.get(CachedChannelAdminRanks.self) {
                            ranks = data.ranks
                        }
                        if let existingRank = ranks[memberId] {
                            switch existingRank {
                            case .owner:
                                ranks[memberId] = .owner(rank)
                            case .admin:
                                ranks[memberId] = .admin(rank)
                            case .member:
                                ranks[memberId] = .member(rank)
                            }
                        } else {
                            switch updatedParticipant {
                            case .creator:
                                ranks[memberId] = .owner(rank)
                            case let .member(_, _, adminInfo, _, _, _):
                                if adminInfo != nil {
                                    ranks[memberId] = .admin(rank)
                                } else {
                                    ranks[memberId] = .member(rank)
                                }
                            }
                        }
                        if let entry = CodableEntry(CachedChannelAdminRanks(ranks: ranks)) {
                            transaction.putItemCacheEntry(id: entryId, entry: entry)
                        }
                    }).start()
                    subscriber.putCompletion()
                }
            })
        }
    }

    public func addMember(peerId: PeerId, memberId: PeerId) -> Signal<Void, NoError> {
        return engine.peers.addChannelMember(peerId: peerId, memberId: memberId)
            |> map(Optional.init)
            |> `catch` { _ -> Signal<(ChannelParticipant?, RenderedChannelParticipant)?, NoError> in
                return .single(nil)
            }
            |> deliverOnMainQueue
            |> beforeNext { [weak self] result in
                if let strongSelf = self, let (previous, updated) = result {
                    strongSelf.impl.with { impl in
                        for (contextPeerId, context) in impl.contexts {
                            if peerId == contextPeerId {
                                context.replayUpdates([(previous, updated, nil)])
                            }
                        }
                    }
                }
            }
            |> mapToSignal { _ -> Signal<Void, NoError> in
                return .complete()
        }
    }
    
    public func addMembersAllowPartial(peerId: PeerId, memberIds: [PeerId]) -> Signal<[(PeerId, AddChannelMemberError)], NoError> {
        let signals: [Signal<((ChannelParticipant?, RenderedChannelParticipant)?, PeerId, AddChannelMemberError?), NoError>] = memberIds.map({ memberId in
            return engine.peers.addChannelMember(peerId: peerId, memberId: memberId)
            |> map { result -> ((ChannelParticipant?, RenderedChannelParticipant)?, PeerId, AddChannelMemberError?) in
                return (result, memberId, nil)
            }
            |> `catch` { error -> Signal<((ChannelParticipant?, RenderedChannelParticipant)?, PeerId, AddChannelMemberError?), NoError> in
                return .single((nil, memberId, error))
            }
        })
        return combineLatest(signals)
        |> deliverOnMainQueue
        |> beforeNext { [weak self] results in
            if let strongSelf = self {
                strongSelf.impl.with { impl in
                    for (result, _, _) in results {
                        if let (previous, updated) = result {
                            for (contextPeerId, context) in impl.contexts {
                                if peerId == contextPeerId {
                                    context.replayUpdates([(previous, updated, nil)])
                                }
                            }
                        }
                    }
                }
            }
        }
        |> map { results -> [(PeerId, AddChannelMemberError)] in
            var failedIds: [(PeerId, AddChannelMemberError)] = []
            
            for (_, memberId, error) in results {
                if let error = error {
                    failedIds.append((memberId, error))
                }
            }
            
            return failedIds
        }
    }

    
    public func addMembers(peerId: PeerId, memberIds: [PeerId]) -> Signal<[PeerId], AddChannelMemberError> {
        let signals: [Signal<(ChannelParticipant?, RenderedChannelParticipant)?, AddChannelMemberError>] = memberIds.map({ memberId in
            return engine.peers.addChannelMember(peerId: peerId, memberId: memberId)
                |> map(Optional.init)
                |> `catch` { error -> Signal<(ChannelParticipant?, RenderedChannelParticipant)?, AddChannelMemberError> in
                    if memberIds.count == 1 {
                        return .fail(error)
                    } else {
                        return .single(nil)
                    }
            }
        })
        return combineLatest(signals)
            |> deliverOnMainQueue
            |> beforeNext { [weak self] results in
                if let strongSelf = self {
                    strongSelf.impl.with { impl in
                        for result in results {
                            if let (previous, updated) = result {
                                for (contextPeerId, context) in impl.contexts {
                                    if peerId == contextPeerId {
                                        context.replayUpdates([(previous, updated, nil)])
                                    }
                                }
                            }
                        }
                    }
                }
            }
            |> mapToSignal { values -> Signal<[PeerId], AddChannelMemberError> in
                return .single(values.compactMap { $0?.1.peer.id })
            }
    }
    
    public func replyThread(account: Account, messageId: MessageId) -> Signal<MessageHistoryViewExternalInput, NoError> {
        return .complete()
    }


}
