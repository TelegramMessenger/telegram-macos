import Foundation
import XCTest
import SwiftSignalKit

typealias PeerId = Int64
struct MessageId: Equatable { let peerId: PeerId; let id: Int }
class Peer {
    let id: PeerId
    init(_ id: PeerId) { self.id = id }
    var isSupergroup: Bool { true }
    var compactDisplayTitle: String { "name" }
}
typealias EnginePeer = Peer
final class TelegramChannel: Peer {
    var linkedCommunityId: PeerId?
    var linkedMonoforumId: PeerId?
    var isMonoForum = false
    var defaultBannedRights: TelegramChatBannedRights?
}
struct Message {
    let id: MessageId
    var containsSecretMedia = false
    var author: Peer?
    var peers: [PeerId: Peer] = [:]
}
struct TelegramChatBannedRightsFlags: OptionSet {
    let rawValue: Int
    static let banReadMessages = Self(rawValue: 1)
    static let banSendText = Self(rawValue: 2)
    static let banSendMedia = Self(rawValue: 4)
}
struct TelegramChatBannedRights { let flags: TelegramChatBannedRightsFlags; let untilDate: Int32 }
func banSendMediaSubList() -> [(TelegramChatBannedRightsFlags, Int)] { [(.banSendMedia, 0)] }
func allGroupPermissionList(peer: TelegramChannel) -> [(TelegramChatBannedRightsFlags, Int)] { [(.banSendText, 0)] }
__POLICY__
__CONTEXT__
extension AnalyticsPrivacy {
    init(peerId: PeerId) { self = peerId < 0 ? .excluded : peerId == 0 ? .unresolved : .ordinary }
}
final class Analytics {
    static var shared = Analytics()
    let policy = AnalyticsCollectionPolicy()
    func unresolvedContext() -> AnalyticsContext { AnalyticsContext(analytics: self, privacy: .unresolved, scope: nil) }
    func captureContext(engine: Engine, peerId: PeerId, inherited: AnalyticsContext? = nil) -> AnalyticsContext { captureContext(owner: engine.account, privacy: AnalyticsPrivacy(peerId: peerId), inherited: inherited) }
__CAPTURE__
    func send(_ event: @autoclosure () -> Int) { Probe.legacyEvents += 1 }
}
enum AnalyticsValues { struct Count { init(bucketing: Int) {} } }
enum AnalyticsEvents { static func chatMessageDelete(count: AnalyticsValues.Count, forEveryone: Bool) -> Int { 0 } }
final class Account {}
protocol AccountContextProtocol {
    var engine: Engine { get }
    var peerId: PeerId { get }
    var window: Int { get }
    var peerChannelMemberCategoriesContextsManager: Manager { get }
}
final class Context: AccountContextProtocol {
    let engine = Engine()
    let peerId: PeerId = 1
    let window = 0
    let peerChannelMemberCategoriesContextsManager = Manager()
}
final class Engine {
    let account = Account()
    let messages = Messages()
    let peers = Peers()
}
final class Messages {
    enum DeleteType { case forEveryone }
    func deleteReaction(messageId: MessageId, authorId: PeerId) -> Signal<Void, NoError> { Probe.operation("reaction", ids: [messageId.peerId, authorId]) }
    func deleteMessagesInteractively(messageIds: [MessageId], type: DeleteType) -> Signal<Void, NoError> { Probe.operation("messages", ids: messageIds.map(\.peerId)) }
    func clearAuthorHistory(peerId: PeerId, memberId: PeerId) -> Signal<Void, NoError> { Probe.operation("history", ids: [peerId, memberId]) }
    func deleteAllReactionsWithAuthor(peerId: PeerId, authorId: PeerId) -> Signal<Void, NoError> { Probe.operation("reactions", ids: [peerId, authorId]) }
}
final class Peers {
    enum Reason { case spam }
    func reportPeerMessages(messageIds: [MessageId], reason: Reason, message: String) -> Signal<Void, NoError> { Probe.operation("report", ids: messageIds.map(\.peerId)) }
    func toggleCommunityParticipantBanned(communityId: PeerId, participantId: PeerId, banned: Bool) -> Signal<Void, NoError> { Probe.operation("community", ids: [communityId, participantId]) }
}
struct ChannelParticipant {}
struct AdminListState {
    enum Loading { case ready, loading }
    struct Item { let participant: ChannelParticipant }
    let loadingState: Loading
    let list: [Item]
}
final class Manager {
    func admins(peerId: PeerId, updated: @escaping (AdminListState) -> Void) -> (Disposable, Int) {
        Probe.check?(); Probe.adminUpdate = updated
        return (ActionDisposable { Probe.check?(); Probe.adminDisposals += 1 }, 0)
    }
    func updateMemberBannedRights(peerId: PeerId, memberId: PeerId, bannedRights: TelegramChatBannedRights) -> Signal<Void, NoError> {
        Probe.rights.append(bannedRights); return Probe.operation("ban", ids: [peerId, memberId])
    }
}
__STATE__
extension DeleteState: Equatable { static func == (lhs: DeleteState, rhs: DeleteState) -> Bool { false } }
struct JoinedChats { let creatorChatIds: [PeerId]; let joinedChatIds: [PeerId]; let peers: [PeerId: EnginePeer] }
struct Strings {
    var deleteGroupMessagesWarningTitle: String { "Warning" }
    var deleteGroupMessagesBan: String { "Ban" }
    func deleteGroupMessagesCommunityBanWarningOther(_ count: Int, _ name: String) -> String { "Warning" }
}
func strings() -> Strings { Strings() }
struct InputDataSignalValue { let entries: [Int] }
func entries(_ state: DeleteState) -> [Int] { Probe.check?(); Probe.renders += 1; return [] }
func deliverOnPrepareQueue<T>(_ signal: Signal<T, NoError>) -> Signal<T, NoError> {
    signal |> mapToSignal { value in Probe.gate.get() |> filter { $0 } |> take(1) |> map { _ in value } }
}
enum Validation { case none }
final class Content {
    var analyticsContext: AnalyticsContext?
    var validateData: (Int) -> Validation = { _ in .none }
    let subscription = MetaDisposable()
    init(_ signal: Signal<InputDataSignalValue, NoError>) { Probe.check?(); subscription.set(signal.start()) }
    deinit { subscription.dispose() }
}
final class Modal {
    let content: Content
    var analyticsContext: AnalyticsContext?
    var modal: Modal? { self }
    var update: ((DeleteState) -> DeleteState) -> Void = { _ in }
    init(_ content: Content) { self.content = content; Probe.check?() }
    func close() { Probe.check?(); Probe.closes += 1 }
}
struct ModalAlertData {
    struct Header {
        let make: (Int, Int, Int) -> CommunityBanWarningItem
        init(id: String, make: @escaping (Int, Int, Int) -> CommunityBanWarningItem) { self.make = make }
    }
}
struct CommunityBanWarningItem {
    init(_ size: Int, stableId: Int, context: any AccountContextProtocol, chats: [(peer: EnginePeer, members: Int32?)]) { Probe.check?() }
}
func verifyAlert(for window: Int, header: String, information: String, ok: String, successHandler: @escaping (Int) -> Void, onDeinit: @escaping () -> Void, headerItem: ModalAlertData.Header) {
    Probe.check?(); Probe.confirm = successHandler; Probe.dismiss = onDeinit; Probe.header = headerItem
}
func DeleteGroupMessagesController(context: any AccountContextProtocol, channel: TelegramChannel, messages: [Message], allPeers: Set<PeerId>, reactionAuthor: PeerId? = nil, analyticsContext: AnalyticsContext? = nil, onComplete: @escaping () -> Void) -> Modal {
__ADMISSION__
    let state = DeleteState(channel: channel, messages: messages, allPeers: allPeers, reactionAuthor: reactionAuthor)
    let stateValue = Atomic(value: state)
    let statePromise = ValuePromise(state)
__UPDATE__
    var close: (() -> Void)?
__RENDER__
    let controller = Content(signal)
__CONTROLLER_CONTEXT__
    let messageIds = messages.map { $0.id }
    let peerId = channel.id
    let messagesPeerId = channel.isMonoForum ? channel.linkedMonoforumId ?? channel.id : channel.id
__SUBMIT__
    let modalController = Modal(controller)
__MODALCONTROLLER_CONTEXT__
    modalController.update = updateState
__CLOSE__
    return modalController
}
final class DeleteMenuItem {
    let context: any AccountContextProtocol
    let message: Message?
    let peer: Peer
    let analyticsContext: AnalyticsContext
    init(context: any AccountContextProtocol, message: Message?, peer: Peer, analyticsContext: AnalyticsContext?) {
__ITEM_ADMISSION__
        self.context = context; self.message = message; self.peer = peer
    }
    func action() -> () -> Void {
        let context = self.context
        return { [weak self] in
__ITEM_DELETE__
        }
    }
}
func showModal(with modal: Modal, for window: Int) { Probe.check?(); Probe.modal = modal }
func item(context: Context, message: Message, peer: Peer, peerOrigin: AnalyticsContext) -> DeleteMenuItem {
    DeleteMenuItem(context: context, message: message, peer: peer, analyticsContext: __ITEM_HANDOFF__)
}
func resolveCommunity(_ analyticsOrigin: AnalyticsContext, communityPeer: Peer?, joinedChats: JoinedChats) -> AnalyticsContext {
__COMMUNITY_ADMISSION__
    Probe.check?(); return resolvedOrigin
}
func deliverMessages(_ messages: [Message], analyticsOrigin: AnalyticsContext) -> AnalyticsContext {
__CHAT_DELIVERY__
    Probe.check?(); return deliveredOrigin
}
func deletionLookups(context: Context, peer: Peer, messageIds: [MessageId], analyticsOrigin: AnalyticsContext) -> Signal<([Message], [ChannelParticipant]?), NoError> {
    let lifetime = analyticsOrigin.beginPresentation()
    defer { lifetime.end() }
__ADMIN_LOOKUP__
    return __ADMIN_SIGNAL__
}
enum Probe {
    static var check: (() -> Void)?
    static var adminUpdate: ((AdminListState) -> Void)?
    static var adminDisposals = 0
    static var messageSink: Subscriber<[Message], NoError>?
    static var messageDisposals = 0
    static func messagesAtIds(_ ids: [MessageId]) -> Signal<[Message], NoError> {
        check?()
        return Signal { sink in
            check?(); messageSink = sink
            return ActionDisposable { check?(); messageDisposals += 1 }
        }
    }
    static var gate = ValuePromise<Bool>(true)
    static var renders = 0
    static var closes = 0
    static var completions = 0
    static var legacyEvents = 0
    static var calls: [(String, [PeerId])] = []
    static var sinks: [Subscriber<Void, NoError>] = []
    static var disposals = 0
    static var rights: [TelegramChatBannedRights] = []
    static var confirm: ((Int) -> Void)?
    static var dismiss: (() -> Void)?
    static var header: ModalAlertData.Header?
    static var modal: Modal?
    static func operation(_ name: String, ids: [PeerId]) -> Signal<Void, NoError> {
        check?(); calls.append((name, ids))
        return Signal { sink in check?(); sinks.append(sink); return ActionDisposable { check?(); disposals += 1 } }
    }
    static func reset() {
        check = nil; adminUpdate = nil; adminDisposals = 0; messageSink = nil; messageDisposals = 0; confirm = nil; dismiss?(); dismiss = nil; header = nil; modal = nil
        for sink in sinks { sink.putCompletion() }
        sinks = []; calls = []; rights = []; disposals = 0; renders = 0; closes = 0; completions = 0; legacyEvents = 0; gate = ValuePromise(true)
    }
}
final class DeleteActionsTests: XCTestCase {
    var context: Context!
    var hub: Analytics { Analytics.shared }
    override func setUp() { Probe.reset(); Analytics.shared = Analytics(); context = Context(); hub.policy.setOwner(context.engine.account); hub.policy.isEnabled = true }
    override func tearDown() { Probe.reset(); context = nil }
    func origin(_ privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsContext { hub.captureContext(owner: context.engine.account, privacy: privacy) }
    func message(_ peerId: PeerId = 2, secret: Bool = false) -> Message { Message(id: MessageId(peerId: peerId, id: 7), containsSecretMedia: secret, peers: [peerId: TelegramChannel(peerId)]) }
    func expectExcluded() { Probe.check = { XCTAssertTrue(self.hub.policy.hasExclusions) } }
    func open(_ source: AnalyticsContext?, messages: [Message]? = nil, channel: TelegramChannel = TelegramChannel(2), peers: Set<PeerId> = [3], reactionAuthor: PeerId? = 3) -> Modal {
        DeleteGroupMessagesController(context: context, channel: channel, messages: messages ?? [message()], allPeers: peers, reactionAuthor: reactionAuthor, analyticsContext: source, onComplete: { Probe.check?(); Probe.completions += 1 })
    }
    func finish() { for sink in Probe.sinks { sink.putNext(()); sink.putCompletion() } }
    func testOrdinaryMenuHandoffKeepsScopeAndExactReactionTarget() {
        let source = origin(); let menu = item(context: context, message: message(), peer: Peer(3), peerOrigin: source)
        menu.action()(); XCTAssertTrue(Probe.modal?.analyticsContext?.scope === source.scope); XCTAssertTrue(Probe.modal?.content.analyticsContext?.scope === source.scope)
        _ = Probe.modal?.content.validateData(0)
        XCTAssertEqual(Probe.calls.map(\.0), ["reaction"]); XCTAssertEqual(Probe.calls.first?.1, [2, 3]); XCTAssertEqual(Probe.legacyEvents, 0)
        XCTAssertEqual(Probe.completions, 0); finish()
    }
    func testSecretMediaPrivateParentAndUnknownSourcesRemainExcluded() {
        for (source, messages) in [(origin(), [message(secret: true)]), (origin(.excluded), [message()]), (origin(), [message(0)]), (origin(), [message(-1)])] {
            expectExcluded(); let modal = open(source, messages: messages); _ = modal.content.validateData(0); finish()
            XCTAssertTrue(modal.analyticsContext?.isExcluded == true)
        }
    }
    func testPrivateAuthorsTargetsAndLinkedPeersCannotGainGrant() {
        var authored = message(); authored.author = Peer(-2)
        let linked = TelegramChannel(2); linked.linkedCommunityId = -4
        for (messages, channel, peers, author) in [([authored], TelegramChannel(2), Set([Int64(3)]), Int64(3)), ([message()], linked, Set([Int64(3)]), Int64(3)), ([message()], TelegramChannel(2), Set([Int64(-5)]), Int64(3)), ([message()], TelegramChannel(2), Set([Int64(3)]), Int64(-6))] {
            expectExcluded(); let modal = open(origin(), messages: messages, channel: channel, peers: peers, reactionAuthor: author)
            XCTAssertTrue(modal.analyticsContext?.isExcluded == true)
        }
    }
    func testPrivateSubmitPreservesEverySelectedOperationAfterDialogRelease() {
        var modal: Modal? = open(origin(.excluded), reactionAuthor: nil); expectExcluded()
        modal?.update { value in var value = value; value.banSelected = true; value.banPeerSelected = [3]; value.spamSelected = true; value.deleteSelected = true; value.deletePeerSelected = [3]; value.deleteReactionsSelected = true; value.deleteReactionsPeerSelected = [3]; return value }
        _ = modal?.content.validateData(0); modal = nil
        XCTAssertEqual(Set(Probe.calls.map(\.0)), ["messages", "ban", "report", "history", "reactions"])
        XCTAssertTrue(hub.policy.hasExclusions); finish(); XCTAssertFalse(hub.policy.hasExclusions)
        XCTAssertEqual(Probe.disposals, 5); XCTAssertEqual(Probe.completions, 1)
        XCTAssertEqual(Probe.rights.first?.flags, .banReadMessages)
    }
    func testCommunityConfirmationKeepsOriginAfterDialogReleaseAndOnLateSuccess() {
        var modal: Modal? = open(origin(.excluded)); expectExcluded()
        modal?.update { value in var value = value; value.deleteListSelected = false; value.banFromCommunity = true; value.communityId = 4; value.communityCreatorChatIds = [5]; value.communityChatPeers = [5: Peer(5)]; return value }
        _ = modal?.content.validateData(0); modal = nil
        XCTAssertTrue(hub.policy.hasExclusions); _ = Probe.header?.make(0, 0, 0)
        Probe.confirm?(0); Probe.dismiss?(); Probe.dismiss = nil
        XCTAssertEqual(Probe.calls.map(\.0), ["community"]); XCTAssertEqual(Probe.completions, 1)
        finish(); Probe.confirm = nil; Probe.header = nil; XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testCancelledCommunityConfirmationDoesNotCommit() {
        var modal: Modal? = open(origin(.excluded)); expectExcluded()
        modal?.update { value in var value = value; value.deleteListSelected = false; value.banFromCommunity = true; value.communityId = 4; value.communityCreatorChatIds = [5]; return value }
        _ = modal?.content.validateData(0); modal = nil; Probe.dismiss?(); Probe.dismiss = nil; Probe.confirm = nil; Probe.header = nil
        XCTAssertTrue(Probe.calls.isEmpty); XCTAssertEqual(Probe.completions, 0); XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testPrivateCommunityResolutionRevokesPreviouslyCapturedSource() {
        let source = origin(); let modal = open(source)
        expectExcluded(); let resolved = resolveCommunity(source, communityPeer: Peer(4), joinedChats: JoinedChats(creatorChatIds: [5], joinedChatIds: [], peers: [5: Peer(-6)]))
        XCTAssertTrue(resolved.isExcluded); XCTAssertTrue(source.scope?.isExcluded == true)
        _ = modal.content.validateData(0); finish()
    }
    func testFetchedSecretMessageRevokesEarlierSelectionOrigin() {
        let source = origin(); expectExcluded(); let delivered = deliverMessages([message(secret: true)], analyticsOrigin: source)
        XCTAssertTrue(source.scope?.isExcluded == true); XCTAssertTrue(delivered.isExcluded)
    }
    func testDelayedRowsAndStateUpdatesRetainPrivateOrigin() {
        Probe.gate.set(false); let modal = open(origin(.excluded)); XCTAssertEqual(Probe.renders, 0)
        expectExcluded(); modal.update { value in var value = value; value.spamSelected = true; return value }
        Probe.gate.set(true); XCTAssertGreaterThan(Probe.renders, 0)
    }
    func testAccountChangeAndDisabledOriginCannotRenewAtMenuInvocation() {
        let menu = item(context: context, message: message(), peer: Peer(3), peerOrigin: origin())
        let other = Context(); hub.policy.setOwner(other.engine.account); expectExcluded(); menu.action()()
        XCTAssertNil(Probe.modal?.analyticsContext?.scope)
        hub.policy.isEnabled = false; let modal = open(nil); _ = modal.content.validateData(0); finish()
        XCTAssertNil(modal.analyticsContext?.scope)
    }
    func testReleasedMenuAndMissingChannelPreserveNoOpenBehavior() {
        var menu: DeleteMenuItem? = item(context: context, message: message(), peer: Peer(3), peerOrigin: origin())
        let action = menu!.action(); menu = nil; action(); XCTAssertNil(Probe.modal)
        let missing = Message(id: MessageId(peerId: 2, id: 7))
        item(context: context, message: missing, peer: Peer(3), peerOrigin: origin()).action()()
        XCTAssertNil(Probe.modal)
    }
    func testCancelledMessageLookupDisposesPendingAdministratorRequest() {
        expectExcluded()
        let disposable = deletionLookups(context: context, peer: Peer(2), messageIds: [message().id], analyticsOrigin: origin(.excluded)).start()
        XCTAssertTrue(hub.policy.hasExclusions); disposable.dispose()
        XCTAssertEqual(Probe.adminDisposals, 1); XCTAssertEqual(Probe.messageDisposals, 1)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testReadyAdministratorLookupDisposesExactlyOnceAndKeepsDeliveryPrivate() {
        expectExcluded(); var deliveries = 0
        let disposable = deletionLookups(context: context, peer: Peer(2), messageIds: [message().id], analyticsOrigin: origin(.excluded)).start(next: { _, _ in
            XCTAssertTrue(self.hub.policy.hasExclusions); deliveries += 1
        })
        Probe.adminUpdate?(.init(loadingState: .ready, list: []))
        Probe.messageSink?.putNext([message()]); Probe.messageSink?.putCompletion()
        XCTAssertEqual(deliveries, 1); disposable.dispose(); XCTAssertEqual(Probe.adminDisposals, 1)
        XCTAssertFalse(hub.policy.hasExclusions)
    }
    func testRevokedConfirmationDoesNotRestoreEligibilityAtCommit() {
        let source = origin(); var modal: Modal? = open(source)
        modal?.update { value in var value = value; value.deleteListSelected = false; value.banFromCommunity = true; value.communityId = 4; value.communityCreatorChatIds = [5]; return value }
        _ = modal?.content.validateData(0); modal = nil; source.scope?.exclude(); expectExcluded()
        Probe.confirm?(0); Probe.dismiss?(); Probe.dismiss = nil; finish(); Probe.confirm = nil; Probe.header = nil
        XCTAssertEqual(Probe.calls.map(\.0), ["community"]); XCTAssertFalse(source.scope?.isValid == true)
    }
    func testMonoforumTargetsAndRestrictionFlagsRemainUnchanged() {
        let channel = TelegramChannel(2); channel.isMonoForum = true; channel.linkedMonoforumId = 9
        channel.defaultBannedRights = TelegramChatBannedRights(flags: [.banSendText], untilDate: 0)
        let modal = open(origin(), channel: channel); modal.update { value in
            var value = value; value.deleteListSelected = false; value.banSelected = true; value.banFully = false; value.updatedFlags = [.banSendMedia]; value.banPeerSelected = [3]; value.deleteReactionsSelected = true; value.deleteReactionsPeerSelected = [3]; return value
        }
        _ = modal.content.validateData(0); finish()
        XCTAssertEqual(Probe.calls.map(\.1), [[9, 3], [9, 3]])
        XCTAssertEqual(Probe.rights.first?.flags, .banSendText); XCTAssertEqual(Probe.rights.first?.untilDate, Int32.max)
    }

    func testNewlyPrivateSelectedTargetRevokesOriginBeforeOperationConstruction() {
        let source = origin(); let modal = open(source)
        modal.update { value in var value = value; value.deleteListSelected = false; value.deleteReactionsSelected = true; value.deleteReactionsPeerSelected = [-7]; return value }
        expectExcluded(); _ = modal.content.validateData(0); finish()
        XCTAssertTrue(source.scope?.isExcluded == true); XCTAssertEqual(Probe.calls.map(\.1), [[2, -7]])
    }

    func testCommunityWarningCancellationDoesNotUndoEarlierReactionRequests() {
        var modal: Modal? = open(origin(.excluded)); expectExcluded()
        modal?.update { value in
            var value = value; value.deleteReactionsSelected = true; value.deleteReactionsPeerSelected = [3]; value.banFromCommunity = true; value.communityId = 4; value.communityCreatorChatIds = [5]; return value
        }
        _ = modal?.content.validateData(0)
        XCTAssertEqual(Probe.calls.map(\.0), ["reaction", "reactions"])
        modal = nil; Probe.dismiss?(); Probe.dismiss = nil; Probe.confirm = nil; Probe.header = nil
        XCTAssertEqual(Probe.completions, 0); XCTAssertTrue(hub.policy.hasExclusions)
        finish(); XCTAssertFalse(hub.policy.hasExclusions)
        XCTAssertEqual(Probe.calls.map(\.0), ["reaction", "reactions"])
    }

}
