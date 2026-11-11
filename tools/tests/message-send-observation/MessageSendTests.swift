import Foundation
import XCTest
import SwiftSignalKit

public typealias PeerId = Int64
struct MessageId: ExpressibleByIntegerLiteral {
    let peerId: PeerId
    init(peerId: PeerId) { self.peerId = peerId }
    init(integerLiteral value: Int64) { self.peerId = 2 }
}
__POLICY__
__CONTEXT__
extension AnalyticsContext {
    func beginPresentation() -> AnalyticsPresentation { AnalyticsPresentation(context: self) }
__PRESERVING__
}
__PRESENTATION__
extension AnalyticsPrivacy {
    init(peerId: PeerId) { self = peerId < 0 ? .excluded : peerId == 0 ? .unresolved : .ordinary }
}
public enum AnalyticsValues {
    public enum MessageKind: Equatable { case text, contact, photo, album, sticker }
    public enum PeerType: Equatable { case user, group, secretChat }
}
final class PayloadLifetime {}
public struct AnalyticsEvent: Equatable {
    let kind: AnalyticsValues.MessageKind
    let peerType: AnalyticsValues.PeerType?
    let hasReply: Bool
    let scheduled: Bool
    let silent: Bool
    var lifetime: PayloadLifetime? = nil
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.kind == rhs.kind && lhs.peerType == rhs.peerType && lhs.hasReply == rhs.hasReply && lhs.scheduled == rhs.scheduled && lhs.silent == rhs.silent
    }
}
enum AnalyticsEvents {
    static var constructed = 0
    static weak var lastPayload: PayloadLifetime?
    static func chatMessageSend(kind: AnalyticsValues.MessageKind, peerType: AnalyticsValues.PeerType?, hasReply: Bool, scheduled: Bool, silent: Bool) -> AnalyticsEvent {
        constructed += 1
        let lifetime = PayloadLifetime()
        lastPayload = lifetime
        return AnalyticsEvent(kind: kind, peerType: peerType, hasReply: hasReply, scheduled: scheduled, silent: silent, lifetime: lifetime)
    }
}
final class Engine { let account = NSObject(); let messages = InlineMessages() }
final class AccountContext { let engine = Engine(); var account: NSObject { engine.account } }
final class Analytics {
    static var shared = Analytics()
    let policy = AnalyticsCollectionPolicy()
    var events: [AnalyticsEvent] = []
    func send(_ event: @autoclosure () -> AnalyticsEvent, scope: AnalyticsScope? = nil) {
        policy.sync {
            guard policy.accepts(scope) else { return }
            events.append(event())
        }
    }
    func captureContext(engine: Engine, peerId: PeerId, inherited: AnalyticsContext? = nil) -> AnalyticsContext {
        captureContext(owner: engine.account, privacy: AnalyticsPrivacy(peerId: peerId), inherited: inherited)
    }
__CAPTURE__
}
__OBSERVATION__
enum Mode: Equatable { case history, thread, scheduled, preview, custom, pinned }
struct ReplySubject: ExpressibleByIntegerLiteral {
    let messageId: MessageId
    init(messageId: MessageId) { self.messageId = messageId }
    init(integerLiteral value: Int64) { messageId = MessageId(integerLiteral: value) }
}
struct InterfaceState { var replyMessageId: ReplySubject? }
struct Presentation { var interfaceState = InterfaceState() }
final class ChatInteraction { var peerId: PeerId = 2; var presentation = Presentation() }
final class ChatController {
    let context: AccountContext
    let chatInteraction = ChatInteraction()
    var mode = Mode.history
    var analyticsPeerValue: AnalyticsValues.PeerType? = .user
    let nextTransaction = NextTransaction()
    init(_ context: AccountContext) { self.context = context }
__SNAPSHOT__
}
func observedEnqueue(_ signal: Signal<[MessageId?], NoError>, expected: Int, sendObservation: AnalyticsMessageSend?) -> Signal<[MessageId?], NoError> {
    let mapped = Array(repeating: 0, count: expected)
    let observedResult: ((Int, [MessageId?]) -> Void)? = { expectedCount, ids in
__RESULT__
    }
__SENDER_OBSERVE__
    return observe(signal)
}
final class MessageSendTests: XCTestCase {
    var account: AccountContext!
    var controller: ChatController!
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        Analytics.shared = Analytics(); AnalyticsEvents.constructed = 0; InlineUI.reset()
        account = AccountContext(); controller = ChatController(account)
        hub.policy.setOwner(account.engine.account); hub.policy.isEnabled = true
    }
    override func tearDown() { controller = nil; account = nil; Analytics.shared = Analytics() }
    func origin(_ privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsContext {
        hub.captureContext(owner: account.engine.account, privacy: privacy)
    }
    func observation(_ context: AnalyticsContext? = nil) -> AnalyticsMessageSend? {
        controller.makeMessageSendObservation(.text, analyticsContext: context ?? origin(), scheduled: false, silent: false)
    }
    func testMatchingContextEmitsOnceOnlyAfterCompleteAcceptedBatch() {
        let pending = observation(); XCTAssertNotNil(pending); XCTAssertTrue(hub.events.isEmpty)
        pending?.complete(expectedCount: 2, resultCount: 2, acceptedCount: 2)
        pending?.complete(expectedCount: 2, resultCount: 2, acceptedCount: 2)
        XCTAssertEqual(hub.events.count, 1)
    }
    func testEmptyPartialRejectedAndMalformedResultsCannotBecomeSuccessOnDuplicate() {
        for counts in [(0, 0, 0), (2, 2, 1), (2, 2, 0), (1, 2, 1), (2, 1, 1), (-1, -1, -1)] {
            let pending = observation()
            pending?.complete(expectedCount: counts.0, resultCount: counts.1, acceptedCount: counts.2)
            pending?.complete(expectedCount: 1, resultCount: 1, acceptedCount: 1)
        }
        XCTAssertTrue(hub.events.isEmpty)
    }
    func testDeniedOriginsDoNotConstructPayloadOrObservation() {
        for privacy in [AnalyticsPrivacy.excluded, .unresolved] {
            XCTAssertNil(observation(origin(privacy)))
        }
        let foreign = hub.captureContext(owner: NSObject(), privacy: .ordinary)
        XCTAssertNil(observation(foreign))
        hub.policy.isEnabled = false
        XCTAssertNil(observation()); XCTAssertEqual(AnalyticsEvents.constructed, 0)
    }
    func testSecretAndUnknownDestinationsTightenOrdinaryGrant() {
        let context = origin()
        for peerId: PeerId in [-1, 0] {
            controller.chatInteraction.peerId = peerId
            XCTAssertNil(observation(context))
        }
        XCTAssertEqual(AnalyticsEvents.constructed, 0)
    }
    func testSecretPeerMetadataCannotConstructPayloadWithOrdinaryGrant() {
        controller.analyticsPeerValue = .secretChat
        XCTAssertNil(observation())
        XCTAssertEqual(AnalyticsEvents.constructed, 0)
    }
    func testSecretReplySourceExcludesOrdinaryDestinationBeforeSnapshot() {
        controller.chatInteraction.presentation.interfaceState.replyMessageId = ReplySubject(messageId: MessageId(peerId: -1))
        XCTAssertNil(observation())
        XCTAssertEqual(AnalyticsEvents.constructed, 0)
    }
    func testAccountSwitchCannotRedirectOrRefreshCapturedGrant() {
        let context = origin(), pending = observation(context)
        let next = AccountContext(); hub.policy.setOwner(next.engine.account)
        pending?.complete(expectedCount: 1, resultCount: 1, acceptedCount: 1)
        controller = ChatController(next)
        XCTAssertNil(observation(context)); XCTAssertTrue(hub.events.isEmpty)
    }
    func testDisableOrPrivatePresentationRevokesAndReenableCannotRecoverAttempt() {
        for secret in [false, true] {
            let pending = observation()
            let privateSurface = NSObject()
            if secret {
                hub.policy.setExcluded(true, owner: ObjectIdentifier(privateSurface))
                hub.policy.setExcluded(false, owner: ObjectIdentifier(privateSurface))
            } else {
                hub.policy.isEnabled = false; hub.policy.isEnabled = true
            }
            pending?.complete(expectedCount: 1, resultCount: 1, acceptedCount: 1)
        }
        XCTAssertTrue(hub.events.isEmpty)
    }
    func testRevocationReleasesPendingPayloadBeforeObservationOwner() {
        let pending = observation()
        XCTAssertNotNil(AnalyticsEvents.lastPayload)
        hub.policy.isEnabled = false
        XCTAssertNil(AnalyticsEvents.lastPayload)
        withExtendedLifetime(pending) {}
        XCTAssertTrue(hub.events.isEmpty)
    }
    func testScheduledSilentReplyAndPeerSnapshotDoNotFollowComposerMutation() {
        controller.mode = .scheduled
        controller.analyticsPeerValue = .group
        controller.chatInteraction.presentation.interfaceState.replyMessageId = 4
        let pending = controller.makeMessageSendObservation(.text, analyticsContext: origin(), scheduled: false, silent: true)
        controller.mode = .history; controller.analyticsPeerValue = .user
        controller.chatInteraction.presentation.interfaceState.replyMessageId = nil
        pending?.complete(expectedCount: 1, resultCount: 1, acceptedCount: 1)
        XCTAssertEqual(hub.events, [AnalyticsEvent(kind: .text, peerType: .group, hasReply: true, scheduled: true, silent: true)])
    }
    func testExplicitReplyAndScheduledArgumentsOverrideComposerState() {
        controller.chatInteraction.presentation.interfaceState.replyMessageId = 1
        let pending = controller.makeMessageSendObservation(.contact, analyticsContext: origin(), scheduled: true, silent: false, hasReply: false)
        pending?.complete(expectedCount: 1, resultCount: 1, acceptedCount: 1)
        XCTAssertEqual(hub.events, [AnalyticsEvent(kind: .contact, peerType: .user, hasReply: false, scheduled: true, silent: false)])
    }
    func testCustomPreviewAndPinnedModesNeverConstructOrdinarySend() {
        for mode in [Mode.custom, .preview, .pinned] { controller.mode = mode; XCTAssertNil(observation()) }
        XCTAssertEqual(AnalyticsEvents.constructed, 0)
    }
    func testDiscardAndDestructionEmitNothing() {
        var pending = observation(); pending?.discard()
        pending?.complete(expectedCount: 1, resultCount: 1, acceptedCount: 1)
        pending = observation(); pending = nil
        XCTAssertTrue(hub.events.isEmpty)
    }
    func testSenderResultCallbackUsesActualBatchCountAndWaitsForSignal() {
        var subscriber: Subscriber<[MessageId?], NoError>?
        let pending = observation()
        let signal = Signal<[MessageId?], NoError> { subscriber = $0; return EmptyDisposable }
        let disposable = observedEnqueue(signal, expected: 2, sendObservation: pending).start()
        XCTAssertTrue(hub.events.isEmpty)
        subscriber?.putNext([1, 2]); subscriber?.putNext([1, 2]); subscriber?.putCompletion(); subscriber = nil
        XCTAssertEqual(hub.events.count, 1); disposable.dispose()
    }
    func testSenderEmptyCompletionAndDisposalDoNotInventAcceptedResult() {
        let empty = observedEnqueue(.complete(), expected: 1, sendObservation: observation()).start()
        var subscriber: Subscriber<[MessageId?], NoError>?
        let signal = Signal<[MessageId?], NoError> { subscriber = $0; return EmptyDisposable }
        let disposable = observedEnqueue(signal, expected: 1, sendObservation: observation()).start()
        disposable.dispose(); subscriber?.putNext([1]); subscriber = nil; empty.dispose()
        XCTAssertTrue(hub.events.isEmpty)
    }
    func testConcurrentResultsEmitAtMostOnce() {
        let pending = observation()
        DispatchQueue.concurrentPerform(iterations: 100) { _ in pending?.complete(expectedCount: 1, resultCount: 1, acceptedCount: 1) }
        XCTAssertEqual(hub.events.count, 1)
    }
}

final class NextTransaction {
    var count = 0
    func set(handler: @escaping () -> Void) { count += 1 }
}
struct InlineResult { var kind = AnalyticsValues.MessageKind.photo }
struct InlineResults { var botId: PeerId = 3 }
struct InlineMessage {}
func chatAnalyticsMessageKind(_ result: InlineResult) -> AnalyticsValues.MessageKind { result.kind }
final class InlineMessages {
    func outgoingMessageWithChatContextResult(to: PeerId, threadId: Int64?, botId: PeerId, result: InlineResult, replyToMessageId: ReplySubject?, replyToStoryId: Int?, hideVia: Bool, silentPosting: Bool, scheduleTime: Int32?, sendPaidMessageStars: Int?, postpone: Bool, correlationId: Int64?) -> InlineMessage? {
        InlineUI.factoryCalls += 1
        InlineUI.onFactory?()
        InlineUI.arguments = (to, threadId, botId, scheduleTime, sendPaidMessageStars)
        XCTAssertNil(replyToStoryId); XCTAssertFalse(hideVia); XCTAssertFalse(silentPosting)
        XCTAssertFalse(postpone); XCTAssertNil(correlationId)
        return InlineUI.canConstruct ? InlineMessage() : nil
    }
}
enum InlineUI {
    static var canConstruct = true, factoryCalls = 0, enqueues = 0
    static var destination: PeerId = 2
    static var arguments: (PeerId, Int64?, PeerId, Int32?, Int?)?
    static var onFactory: (() -> Void)?
    static var result: Signal<[MessageId?], NoError> = .complete()
    static func reset() { canConstruct = true; factoryCalls = 0; enqueues = 0; destination = 2; arguments = nil; onFactory = nil; result = .complete() }
}
func enqueueMessages(account: NSObject, peerId: PeerId, messages: [InlineMessage]) -> Signal<[MessageId?], NoError> {
    InlineUI.enqueues += 1
    XCTAssertEqual(messages.count, 1); XCTAssertEqual(peerId, InlineUI.destination)
    return InlineUI.result
}
func inlineApply(_ controller: ChatController, schedulingAnalyticsContext: AnalyticsContext, result: InlineResult = .init(), results: InlineResults = .init(), atDate: Int32? = nil) {
    let context = controller.context
    let makePeerId = { InlineUI.destination }
    let threadId64: () -> Int64? = { 12 }
    let takeReplyId: () -> ReplySubject? = { controller.chatInteraction.presentation.interfaceState.replyMessageId }
    let takePaidMessageStars: () -> Int? = { 5 }
    let afterSentTransition: () -> Void = {}
__INLINE__
}
extension MessageSendTests {
    func testInlineConstructionSuccessWaitsForActualEnqueueResult() {
        var subscriber: Subscriber<[MessageId?], NoError>?
        InlineUI.result = Signal { subscriber = $0; return EmptyDisposable }
        inlineApply(controller, schedulingAnalyticsContext: origin(), atDate: 100)
        XCTAssertEqual(InlineUI.enqueues, 1); XCTAssertEqual(controller.nextTransaction.count, 1)
        XCTAssertTrue(hub.events.isEmpty)
        XCTAssertEqual(InlineUI.arguments?.0, 2); XCTAssertEqual(InlineUI.arguments?.1, 12)
        XCTAssertEqual(InlineUI.arguments?.2, 3); XCTAssertEqual(InlineUI.arguments?.3, 100)
        XCTAssertEqual(InlineUI.arguments?.4, 5)
        subscriber?.putNext([1]); subscriber?.putNext([2]); subscriber?.putCompletion(); subscriber = nil
        XCTAssertEqual(hub.events.count, 1); XCTAssertEqual(hub.events.first?.kind, .photo)
        XCTAssertEqual(hub.events.first?.scheduled, true)
    }
    func testInlineUnconstructibleResultDoesNotEnqueueOrSetTransition() {
        InlineUI.canConstruct = false
        inlineApply(controller, schedulingAnalyticsContext: origin())
        XCTAssertEqual(InlineUI.enqueues, 0); XCTAssertEqual(controller.nextTransaction.count, 0)
        XCTAssertEqual(AnalyticsEvents.constructed, 0); XCTAssertTrue(hub.events.isEmpty)
    }
    func testInlineRejectedEmptyAndMalformedResultsAreNotSuccess() {
        for ids: [MessageId?] in [[], [nil], [1, 2]] {
            InlineUI.result = .single(ids)
            inlineApply(controller, schedulingAnalyticsContext: origin())
        }
        InlineUI.result = .complete()
        inlineApply(controller, schedulingAnalyticsContext: origin())
        XCTAssertTrue(hub.events.isEmpty)
    }
    func testInlineExcludedSourceRetainsPrivacyThroughRequestAndLateDisposal() {
        var subscriber: Subscriber<[MessageId?], NoError>?, disposed = false
        InlineUI.onFactory = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        InlineUI.result = Signal {
            subscriber = $0
            XCTAssertTrue(self.hub.policy.hasExclusions)
            return ActionDisposable { disposed = true; XCTAssertTrue(self.hub.policy.hasExclusions) }
        }
        inlineApply(controller, schedulingAnalyticsContext: origin(.excluded))
        XCTAssertTrue(hub.policy.hasExclusions)
        subscriber?.putNext([1]); subscriber?.putCompletion(); subscriber = nil
        XCTAssertTrue(disposed); XCTAssertTrue(hub.events.isEmpty); XCTAssertEqual(AnalyticsEvents.constructed, 0)
    }
    func testInlineOrdinaryGrantRevokedWhileEnqueuePendingCannotEmit() {
        var subscriber: Subscriber<[MessageId?], NoError>?
        InlineUI.result = Signal { subscriber = $0; return EmptyDisposable }
        inlineApply(controller, schedulingAnalyticsContext: origin())
        hub.policy.isEnabled = false; hub.policy.isEnabled = true
        subscriber?.putNext([1]); subscriber?.putCompletion(); subscriber = nil
        XCTAssertTrue(hub.events.isEmpty)
    }
    func testInlineSecretDestinationAndForeignSourceStayExcluded() {
        InlineUI.result = .single([1])
        let source = origin(); InlineUI.destination = -1
        inlineApply(controller, schedulingAnalyticsContext: source)
        InlineUI.destination = 2
        let other = AccountContext()
        let foreign = hub.captureContext(owner: other.engine.account, privacy: .ordinary)
        inlineApply(controller, schedulingAnalyticsContext: foreign)
        XCTAssertEqual(AnalyticsEvents.constructed, 0); XCTAssertTrue(hub.events.isEmpty)
    }
}
