import Foundation
import XCTest
import SwiftSignalKit

public typealias PeerId = Int64
struct MessageId: Hashable { let peerId: PeerId; let id: Int }
struct Message: Equatable { let id: MessageId; var containsSecretMedia = false }
__POLICY__
__FORWARD_PICKER_SPEC__
enum AnalyticsFlowOutcome: String { case success, fail, cancelled }
struct LookupSummary { let steps: [String]; let result: String?; let sourceLookup: Bool?; let sourceCoverage: String?; let outcome: String }
enum LookupObservations { static var starts = 0; static var summaries: [LookupSummary] = [] }
final class AnalyticsFlow<Spec> {
    private let scope: AnalyticsScope?
    private var steps: [String] = [], result: String?, sourceLookup: Bool?
    private var sourceCoverage: String?
    var storedStepCount: Int { steps.count }
    init(analytics: Analytics, scope: AnalyticsScope?) { self.scope = scope; LookupObservations.starts += 1 }
    func set(entryPoint: AnalyticsFlows.ChatForwardPicker.EntryPoint) {}
    func set(retryCount: AnalyticsFlows.ChatForwardPicker.RetryCount) {}
    func set(lastBlocker: AnalyticsFlows.ChatForwardPicker.LastBlocker) {}
    func set(searchUsed: Bool) {}
    func set(sourceLookup: Bool) { self.sourceLookup = sourceLookup }
    func set(sourceCoverage: AnalyticsFlows.ChatForwardPicker.SourceCoverage?) { self.sourceCoverage = sourceCoverage?.rawValue }
    func set(activation: AnalyticsFlows.ChatForwardPicker.Activation?) {}
    func set(destination: AnalyticsFlows.ChatForwardPicker.Destination) {}
    func set(result: AnalyticsFlows.ChatForwardPicker.Result) { self.result = result.rawValue }
    func step(_ step: AnalyticsFlows.ChatForwardPicker.Step) { scope?.perform { steps.append(step.rawValue) } }
    func finish(_ outcome: AnalyticsFlowOutcome) {
        scope?.perform { LookupObservations.summaries.append(LookupSummary(steps: steps, result: result, sourceLookup: sourceLookup, sourceCoverage: sourceCoverage, outcome: outcome.rawValue)) }
        discard()
    }
    func discard() { steps = []; result = nil; sourceLookup = nil; sourceCoverage = nil }
}
__JOURNEY__
__CONTEXT__
extension AnalyticsContext {
    func beginPresentation() -> AnalyticsPresentation { AnalyticsPresentation(context: self) }
__PRESERVING__
}
__PRESENTATION__
extension AnalyticsPrivacy {
    init(peerId: PeerId) { self = peerId < 0 ? .excluded : peerId == 0 ? .unresolved : .ordinary }
}
final class Analytics {
    static var shared = Analytics()
    let policy = AnalyticsCollectionPolicy()
    func unresolvedContext() -> AnalyticsContext { AnalyticsContext(analytics: self, privacy: .unresolved, scope: nil) }
    func captureContext(engine: Engine, peerId: PeerId, inherited: AnalyticsContext? = nil) -> AnalyticsContext {
        captureContext(owner: engine.account, privacy: AnalyticsPrivacy(peerId: peerId), inherited: inherited)
    }
__CAPTURE__
}
final class Account { let postbox = Postbox() }
final class Engine { let account = Account() }
protocol AccountContextProtocol { var engine: Engine { get }; var peerId: PeerId { get } }
final class AccountContext: AccountContextProtocol {
    let engine = Engine()
    let peerId: PeerId = 1
    var account: Account { engine.account }
}
final class Postbox {
    var requests: [[MessageId]] = []
    var onSetup: (() -> Void)?
    var result: Signal<[Message], NoError> = .complete()
    func messagesAtIds(_ ids: [MessageId]) -> Signal<[Message], NoError> { requests.append(ids); onSetup?(); return result }
}
struct Selection { var selectedIds: Set<MessageId> }
struct Presentation {
    var selectionState: Selection?
    var chatLocation = 2
    var chatMode = 0
    var reportMode: Int?
}
__SELECTION__
final class ChatInteraction {
    let context: AccountContext
    var peerId: PeerId = 2
    var inherited: AnalyticsContext?
    var presentation = Presentation()
    let forwardSelection = ChatForwardSelection()
    init(_ context: AccountContext) { self.context = context }
    func captureAnalyticsContext() -> AnalyticsContext {
        Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: inherited)
    }
__FORWARD__
__LOAD__
    func update(_ f: (inout Presentation) -> Void) {
        let oldValue = presentation
        f(&presentation)
__INVALIDATE__
    }
}
final class ModalViewController { var analyticsContext: AnalyticsContext?; var journey: AnalyticsForwardPickerJourney? }
struct ChatUIHooks {
__HOOK__
}
final class ForwardSelectionTests: XCTestCase {
    var account: AccountContext!
    var interaction: ChatInteraction!
    let ordinaryId = MessageId(peerId: 2, id: 1)
    let secretId = MessageId(peerId: -1, id: 2)
    var hub: Analytics { Analytics.shared }
    override func setUp() {
        LookupObservations.starts = 0; LookupObservations.summaries = []
        Analytics.shared = Analytics(); account = AccountContext(); interaction = ChatInteraction(account)
        hub.policy.setOwner(account.engine.account); hub.policy.isEnabled = true
        interaction.presentation.selectionState = Selection(selectedIds: [ordinaryId])
    }
    override func tearDown() { interaction = nil; account = nil; Analytics.shared = Analytics() }
    func origin(_ privacy: AnalyticsPrivacy = .ordinary) -> AnalyticsContext { hub.captureContext(owner: account.engine.account, privacy: privacy) }
    func testSelectedSourceIsCapturedBeforeLookupAndDoesNotFollowLaterContext() {
        let original = origin(); interaction.inherited = original
        var subscriber: Subscriber<[Message], NoError>?, received: AnalyticsContext?
        account.account.postbox.result = Signal { subscriber = $0; return EmptyDisposable }
        interaction.forwardMessagesWithContext = { _, context in received = context }
        interaction.forwardSelectedMessages(); interaction.inherited = origin(.excluded)
        subscriber?.putNext([Message(id: ordinaryId)]); subscriber = nil
        XCTAssertTrue(received?.scope === original.scope); XCTAssertFalse(received?.isExcluded ?? true)
    }
    func testSecretSelectedIdProtectsSetupSubscriptionDeliveryAndDisposal() {
        interaction.presentation.selectionState = Selection(selectedIds: [ordinaryId, secretId])
        var subscriber: Subscriber<[Message], NoError>?, disposed = false
        account.account.postbox.onSetup = { XCTAssertTrue(self.hub.policy.hasExclusions) }
        account.account.postbox.result = Signal {
            subscriber = $0; XCTAssertTrue(self.hub.policy.hasExclusions)
            return ActionDisposable { disposed = true; XCTAssertTrue(self.hub.policy.hasExclusions) }
        }
        interaction.forwardMessagesWithContext = { _, context in XCTAssertTrue(context.isExcluded); XCTAssertTrue(self.hub.policy.hasExclusions) }
        interaction.forwardSelectedMessages(); subscriber?.putNext([Message(id: ordinaryId)]); subscriber = nil
        XCTAssertTrue(disposed)
    }
    func testDuplicatePendingActivationAndDuplicateResultsOpenOnePicker() {
        var subscriber: Subscriber<[Message], NoError>?, calls = 0
        account.account.postbox.result = Signal { subscriber = $0; return EmptyDisposable }
        interaction.forwardMessagesWithContext = { _, _ in calls += 1 }
        interaction.forwardSelectedMessages(); interaction.forwardSelectedMessages()
        subscriber?.putNext([Message(id: ordinaryId)]); subscriber?.putNext([Message(id: ordinaryId)]); subscriber = nil
        XCTAssertEqual(account.account.postbox.requests.count, 1); XCTAssertEqual(calls, 1)
    }
    func testSelectionChangeAndReturnCannotReviveOldLookup() {
        var subscriber: Subscriber<[Message], NoError>?, disposed = false, calls = 0
        account.account.postbox.result = Signal { subscriber = $0; return ActionDisposable { disposed = true } }
        interaction.forwardMessagesWithContext = { _, _ in calls += 1 }
        interaction.forwardSelectedMessages()
        interaction.update { $0.selectionState = nil }
        interaction.update { $0.selectionState = Selection(selectedIds: [self.ordinaryId]) }
        subscriber?.putNext([Message(id: ordinaryId)]); subscriber = nil
        XCTAssertTrue(disposed); XCTAssertEqual(calls, 0)
    }
    func testLocationModeAndReportChangeCancelPendingLookup() {
        let changes: [(inout Presentation) -> Void] = [{ $0.chatLocation = 3 }, { $0.chatMode = 1 }, { $0.reportMode = 1 }]
        for change in changes {
            var disposed = false, calls = 0
            account.account.postbox.result = Signal { _ in ActionDisposable { disposed = true } }
            interaction.forwardMessagesWithContext = { _, _ in calls += 1 }
            interaction.forwardSelectedMessages(); interaction.update(change)
            XCTAssertTrue(disposed); XCTAssertEqual(calls, 0)
        }
    }
    func testOwnerReleaseCancelsLookup() {
        var subscriber: Subscriber<[Message], NoError>?, disposed = false
        account.account.postbox.result = Signal { subscriber = $0; return ActionDisposable { disposed = true } }
        interaction.forwardSelectedMessages(); interaction = nil
        XCTAssertTrue(disposed); subscriber?.putNext([Message(id: ordinaryId)]); subscriber = nil
    }
    func testEmptySelectionAndEmptyResultDoNotOpenPickerAndAllowRetry() {
        var calls = 0; interaction.forwardMessagesWithContext = { _, _ in calls += 1 }
        interaction.presentation.selectionState = Selection(selectedIds: [])
        interaction.forwardSelectedMessages(); XCTAssertTrue(account.account.postbox.requests.isEmpty)
        interaction.presentation.selectionState = Selection(selectedIds: [ordinaryId])
        account.account.postbox.result = .single([]); interaction.forwardSelectedMessages()
        account.account.postbox.result = .complete(); interaction.forwardSelectedMessages()
        account.account.postbox.result = .single([Message(id: ordinaryId)]); interaction.forwardSelectedMessages()
        XCTAssertEqual(calls, 1)
    }
    func testReturnedSecretSourceTightensOriginBeforeLegacyCallback() {
        account.account.postbox.result = .single([Message(id: secretId)])
        var calls = 0
        interaction.forwardMessages = { _ in calls += 1; XCTAssertTrue(self.hub.policy.hasExclusions) }
        interaction.forwardSelectedMessages(); XCTAssertEqual(calls, 1)
    }
    func testRevokedAndForeignOriginsCannotAcquireReplacementGrant() {
        let original = origin(); hub.policy.isEnabled = false; hub.policy.isEnabled = true
        for source in [original, Analytics.shared.captureContext(owner: NSObject(), privacy: .ordinary)] {
            var captured: AnalyticsContext?
            interaction.forwardMessagesWithContext = { _, context in captured = context; XCTAssertTrue(self.hub.policy.hasExclusions) }
            interaction.forwardMessagesObserved([Message(id: ordinaryId)], analyticsContext: source)
            XCTAssertNil(captured?.scope)
        }
    }
    func testReentrantSetupResetDoesNotStartRequest() {
        var subscribed = false
        account.account.postbox.result = Signal { _ in subscribed = true; return EmptyDisposable }
        account.account.postbox.onSetup = { self.interaction.update { $0.selectionState = nil } }
        interaction.forwardSelectedMessages(); XCTAssertFalse(subscribed)
    }
    func testReentrantNewSelectionIsNotConsumedByOldCompletion() {
        let second = MessageId(peerId: 2, id: 2)
        var subscribers: [Subscriber<[Message], NoError>] = [], calls = 0
        account.account.postbox.result = Signal { subscribers.append($0); return EmptyDisposable }
        interaction.forwardMessagesWithContext = { _, _ in
            calls += 1
            if calls == 1 {
                self.interaction.update { $0.selectionState = Selection(selectedIds: [second]) }
                self.interaction.forwardSelectedMessages()
            }
        }
        interaction.forwardSelectedMessages(); subscribers[0].putNext([Message(id: ordinaryId)])
        subscribers[1].putNext([Message(id: second)]); subscribers = []
        XCTAssertEqual(calls, 2)
    }
    func testObservedHookBindsPickerAndPreservesDelayedAlbumLookup() {
        var lookup: (([MessageId], Bool) -> Signal<[Message], NoError>)?
        let hooks = ChatUIHooks(makeForwardMessagesShareModal: { _, _, getMessages in
            XCTAssertTrue(self.hub.policy.hasExclusions); lookup = getMessages; return ModalViewController()
        })
        var subscriber: Subscriber<[Message], NoError>?, disposed = false
        var controller: ModalViewController? = hooks.makeForwardMessagesShareModalObserved(account, [Message(id: secretId)], { _, _ in
            XCTAssertTrue(self.hub.policy.hasExclusions)
            return Signal {
                subscriber = $0; XCTAssertTrue(self.hub.policy.hasExclusions)
                return ActionDisposable { disposed = true; XCTAssertTrue(self.hub.policy.hasExclusions) }
            }
        }, analyticsContext: origin())
        XCTAssertTrue(controller?.analyticsContext?.isExcluded == true); controller = nil
        let disposable = lookup?([ordinaryId], true).start(next: { _ in XCTAssertTrue(self.hub.policy.hasExclusions) })
        subscriber?.putNext([Message(id: ordinaryId)]); subscriber?.putCompletion(); subscriber = nil
        XCTAssertTrue(disposed); disposable?.dispose(); lookup = nil
    }
    func testObservedHookPreservesOrdinaryGrantAndTightensRequestedAlbumPeer() {
        var lookup: (([MessageId], Bool) -> Signal<[Message], NoError>)?
        let hooks = ChatUIHooks(makeForwardMessagesShareModal: { _, _, getMessages in lookup = getMessages; return ModalViewController() })
        let source = origin()
        let controller = hooks.makeForwardMessagesShareModalObserved(account, [Message(id: ordinaryId)], { _, _ in
            XCTAssertTrue(self.hub.policy.hasExclusions); return .single([])
        }, analyticsContext: source)
        XCTAssertTrue(controller.analyticsContext?.scope === source.scope)
        let disposable = lookup?([secretId], true).start(); disposable?.dispose(); lookup = nil
    }
}


extension ForwardSelectionTests {
    func testSelectedSecretMediaIsExcludedBeforeContextOrLegacyCallback() {
        for legacy in [false, true] {
            account.account.postbox.result = .single([Message(id: ordinaryId, containsSecretMedia: true)])
            var calls = 0
            interaction.forwardMessagesWithContext = legacy ? nil : { _, context in
                calls += 1; XCTAssertTrue(context.isExcluded); XCTAssertTrue(self.hub.policy.hasExclusions)
            }
            interaction.forwardMessages = { _ in calls += 1; XCTAssertTrue(self.hub.policy.hasExclusions) }
            interaction.forwardSelectedMessages()
            XCTAssertEqual(calls, 1)
        }
    }
    func testHookSecretMediaExcludesLegacyAndCompanionFactoryBeforeChildren() {
        for companion in [false, true] {
            var calls = 0
            var hooks = ChatUIHooks(makeForwardMessagesShareModal: { _, _, _ in
                calls += 1; XCTAssertTrue(self.hub.policy.hasExclusions); return ModalViewController()
            })
            if companion {
                hooks.makeForwardMessagesShareModalWithContext = { _, _, _, context in
                    calls += 1; XCTAssertTrue(context.isExcluded); XCTAssertTrue(self.hub.policy.hasExclusions); return ModalViewController()
                }
            }
            let controller = hooks.makeForwardMessagesShareModalObserved(account, [Message(id: ordinaryId), Message(id: MessageId(peerId: 2, id: 3), containsSecretMedia: true)], { _, _ in .complete() }, analyticsContext: origin())
            XCTAssertEqual(calls, 1); XCTAssertTrue(controller.analyticsContext?.isExcluded == true)
        }
    }
    func testHookCannotRelaxExcludedUnresolvedRevokedOrForeignChildContext() {
        let revoked = origin(); hub.policy.isEnabled = false; hub.policy.isEnabled = true
        let foreignHub = Analytics(), foreignOwner = NSObject()
        foreignHub.policy.setOwner(foreignOwner); foreignHub.policy.isEnabled = true
        let foreign = foreignHub.captureContext(owner: foreignOwner, privacy: .ordinary)
        XCTAssertNotNil(foreign.scope)
        for childContext in [origin(.excluded), hub.unresolvedContext(), revoked, foreign] {
            let child = ModalViewController(); child.analyticsContext = childContext
            let hooks = ChatUIHooks(makeForwardMessagesShareModal: { _, _, _ in child })
            let controller = hooks.makeForwardMessagesShareModalObserved(account, [Message(id: ordinaryId)], { _, _ in .complete() }, analyticsContext: origin())
            XCTAssertNil(controller.analyticsContext?.scope)
        }
    }
    func testLookupReturnedPrivateMessagesProtectLegacyConsumer() {
        for message in [Message(id: secretId), Message(id: ordinaryId, containsSecretMedia: true)] {
            var lookup: (([MessageId], Bool) -> Signal<[Message], NoError>)?
            let hooks = ChatUIHooks(makeForwardMessagesShareModal: { _, _, getMessages in lookup = getMessages; return ModalViewController() })
            _ = hooks.makeForwardMessagesShareModalObserved(account, [Message(id: ordinaryId)], { _, _ in .single([message]) }, analyticsContext: origin())
            var calls = 0
            let subscription = lookup?([ordinaryId], true).start(next: { messages in
                calls += 1; XCTAssertEqual(messages, [message]); XCTAssertTrue(self.hub.policy.hasExclusions)
            })
            XCTAssertEqual(calls, 1); subscription?.dispose(); lookup = nil
        }
    }
}


extension ForwardSelectionTests {
    func testSelectedMessageRouteReachesExplicitCompanionAfterLookup() {
        account.account.postbox.result = .single([Message(id: ordinaryId)])
        var entries: [AnalyticsFlows.ChatForwardPicker.EntryPoint] = []
        interaction.forwardMessagesWithSource = { _, _, entry in entries.append(entry) }
        interaction.forwardSelectedMessages()
        XCTAssertEqual(entries, [.messageSelection])
    }
    func testLookupKnownEmptyResultIsUnavailableBeforeAnyPicker() {
        account.account.postbox.result = .single([])
        var calls = 0
        interaction.forwardMessagesWithJourney = { _, _, _, _ in calls += 1 }
        interaction.forwardSelectedMessages(); interaction.forwardSelectedMessages()
        XCTAssertEqual(calls, 0); XCTAssertEqual(LookupObservations.summaries.count, 2)
        XCTAssertEqual(LookupObservations.summaries.first?.steps, ["lookup_source", "source_unavailable"])
        XCTAssertEqual(LookupObservations.summaries.first?.result, "source_unavailable")
        XCTAssertEqual(LookupObservations.summaries.first?.sourceLookup, true)
        XCTAssertEqual(LookupObservations.summaries.first?.outcome, "fail")
    }
    func testLookupCarriesOneJourneyThroughValidatedFactoryAndPicker() {
        account.account.postbox.result = .single([Message(id: ordinaryId)])
        var controller: ModalViewController?
        var hooks = ChatUIHooks(makeForwardMessagesShareModal: { _, _, _ in ModalViewController() })
        hooks.makeForwardMessagesShareModalWithSource = { _, _, _, _, _ in XCTFail("Must not create a replacement journey"); return ModalViewController() }
        hooks.attachForwardJourney = { modal, journey in modal.journey = journey; journey.pickerOpened() }
        interaction.forwardMessagesWithJourney = { messages, origin, entry, journey in
            controller = hooks.makeForwardMessagesShareModalObserved(self.account, messages, { _, _ in .single(messages) }, analyticsContext: origin, entry: entry, journey: journey)
        }
        interaction.forwardSelectedMessages(); controller?.journey?.cancel()
        XCTAssertEqual(LookupObservations.starts, 1)
        XCTAssertEqual(LookupObservations.summaries.first?.steps, ["lookup_source", "source_ready", "open_picker", "cancel"])
    }
    func testLookupEmptyCompletionResetAndReleaseDiscardWithoutOutcome() {
        account.account.postbox.result = .complete(); interaction.forwardSelectedMessages()
        account.account.postbox.result = .never(); interaction.forwardSelectedMessages()
        interaction.update { $0.selectionState = nil }
        interaction.presentation.selectionState = Selection(selectedIds: [ordinaryId]); interaction.forwardSelectedMessages(); interaction = nil
        XCTAssertTrue(LookupObservations.summaries.isEmpty)
    }
    func testLookupPrivateReturnedMediaRevokesBeforeSourceReadyOrHandoff() {
        for message in [Message(id: ordinaryId, containsSecretMedia: true), Message(id: secretId)] {
            account.account.postbox.result = .single([message])
            interaction.forwardMessagesWithJourney = { _, origin, _, journey in
                XCTAssertTrue(origin.isExcluded); XCTAssertEqual(journey.retainedStateCount, 0)
                journey.pickerOpened(); journey.cancel()
            }
            interaction.forwardSelectedMessages()
        }
        XCTAssertTrue(LookupObservations.summaries.isEmpty)
    }
    func testLookupPrivateOriginAndReportModeDoNotStartObservation() {
        account.account.postbox.result = .single([])
        interaction.presentation.selectionState = Selection(selectedIds: [secretId]); interaction.forwardSelectedMessages()
        interaction.presentation.selectionState = Selection(selectedIds: [ordinaryId]); interaction.presentation.reportMode = 1
        interaction.forwardSelectedMessages()
        XCTAssertEqual(LookupObservations.starts, 0); XCTAssertTrue(LookupObservations.summaries.isEmpty)
    }
    func testLookupLegacyHandoffDiscardsPartialJourney() {
        account.account.postbox.result = .single([Message(id: ordinaryId)])
        var calls = 0
        interaction.forwardMessagesWithSource = { _, _, _ in calls += 1 }
        interaction.forwardSelectedMessages()
        XCTAssertEqual(calls, 1); XCTAssertEqual(LookupObservations.starts, 1); XCTAssertTrue(LookupObservations.summaries.isEmpty)
    }
    func testLookupStricterConstructedChildErasesTransferredJourney() {
        account.account.postbox.result = .single([Message(id: ordinaryId)])
        var hooks = ChatUIHooks(makeForwardMessagesShareModal: { _, _, _ in
            let modal = ModalViewController(); modal.analyticsContext = self.origin(.excluded); return modal
        })
        hooks.attachForwardJourney = { _, journey in
            XCTAssertEqual(journey.retainedStateCount, 0); journey.pickerOpened(); journey.cancel()
        }
        interaction.forwardMessagesWithJourney = { messages, origin, entry, journey in
            _ = hooks.makeForwardMessagesShareModalObserved(self.account, messages, { _, _ in .single(messages) }, analyticsContext: origin, entry: entry, journey: journey)
        }
        interaction.forwardSelectedMessages(); XCTAssertTrue(LookupObservations.summaries.isEmpty)
    }
    func testLookupReentrantDisposalCannotReplaceANewerSelection() {
        let second = MessageId(peerId: 2, id: 2), newest = MessageId(peerId: 2, id: 3)
        var subscribers: [Subscriber<[Message], NoError>] = []
        account.account.postbox.result = Signal { subscriber in
            subscribers.append(subscriber)
            let first = subscribers.count == 1
            return ActionDisposable {
                if first {
                    self.interaction.presentation.selectionState = Selection(selectedIds: [newest])
                    self.interaction.forwardSelectedMessages()
                }
            }
        }
        interaction.forwardMessagesWithJourney = { messages, _, _, journey in
            XCTAssertEqual(messages.map { $0.id }, [newest]); journey.pickerOpened(); journey.cancel()
        }
        interaction.forwardSelectedMessages()
        interaction.presentation.selectionState = Selection(selectedIds: [second])
        interaction.forwardSelectedMessages()
        XCTAssertEqual(account.account.postbox.requests, [[ordinaryId], [newest]])
        XCTAssertEqual(LookupObservations.starts, 2)
        subscribers.dropFirst().first?.putNext([Message(id: newest)])
        subscribers = []
        XCTAssertEqual(LookupObservations.summaries.count, 1)
        XCTAssertEqual(LookupObservations.summaries.first?.steps, ["lookup_source", "source_ready", "open_picker", "cancel"])
    }
    func testLookupDuplicateActivationTransfersOnlyOneJourney() {
        var subscriber: Subscriber<[Message], NoError>?
        account.account.postbox.result = Signal { subscriber = $0; return EmptyDisposable }
        interaction.forwardMessagesWithJourney = { _, _, _, journey in journey.pickerOpened(); journey.cancel() }
        interaction.forwardSelectedMessages(); interaction.forwardSelectedMessages()
        subscriber?.putNext([Message(id: ordinaryId)]); subscriber?.putNext([Message(id: ordinaryId)]); subscriber = nil
        XCTAssertEqual(LookupObservations.starts, 1); XCTAssertEqual(LookupObservations.summaries.count, 1)
    }
    func testLookupOwnerReceivesPrivateResultOnlyAfterJourneyRevocation() {
        let loader = ChatForwardSelection()
        var calls = 0
        loader.load(ids: [ordinaryId], analyticsContext: origin(), trackForwarding: true, request: {
            .single([Message(id: self.ordinaryId, containsSecretMedia: true)])
        }, completion: { _, journey in
            calls += 1
            XCTAssertTrue(self.hub.policy.hasExclusions)
            XCTAssertEqual(journey?.retainedStateCount, 0)
            journey?.pickerOpened(); journey?.cancel()
        })
        XCTAssertEqual(calls, 1); XCTAssertTrue(LookupObservations.summaries.isEmpty)
    }
    func testSourceCoverageDistinguishesReorderedPartialUnexpectedAndDuplicateResults() {
        let second = MessageId(peerId: 2, id: 2), unrelated = MessageId(peerId: 3, id: 3)
        interaction.presentation.selectionState = Selection(selectedIds: [ordinaryId, second])
        let cases: [([MessageId], String)] = [([second, ordinaryId], "complete"), ([ordinaryId], "partial"), ([unrelated], "unexpected"), ([ordinaryId, unrelated], "unexpected"), ([ordinaryId, ordinaryId], "unexpected"), ([ordinaryId, second, second], "unexpected")]
        for (ids, expected) in cases {
            let messages = ids.map { Message(id: $0) }
            account.account.postbox.result = .single(messages)
            var received: [Message] = []
            interaction.forwardMessagesWithJourney = { values, _, _, journey in
                received = values; journey.pickerOpened(); journey.cancel()
            }
            interaction.forwardSelectedMessages()
            XCTAssertEqual(received, messages)
            XCTAssertEqual(LookupObservations.summaries.last?.sourceCoverage, expected)
            XCTAssertEqual(LookupObservations.summaries.last?.steps, ["lookup_source", "source_ready", "open_picker", "cancel"])
        }
        XCTAssertEqual(LookupObservations.summaries.count, cases.count)
    }
    func testSourceCoverageIsAbsentWhenNoSourceIsReturned() {
        account.account.postbox.result = .single([]); interaction.forwardSelectedMessages()
        XCTAssertEqual(LookupObservations.summaries.first?.result, "source_unavailable")
        XCTAssertNil(LookupObservations.summaries.first?.sourceCoverage)
    }
    func testSourceCoverageNeverSurvivesPrivateMismatchOrReenable() {
        for privateMessage in [Message(id: secretId), Message(id: ordinaryId, containsSecretMedia: true)] {
            account.account.postbox.result = .single([privateMessage])
            var delivered = 0
            interaction.forwardMessagesWithJourney = { _, _, _, journey in
                delivered += 1; self.hub.policy.isEnabled = false; self.hub.policy.isEnabled = true
                journey.pickerOpened(); journey.cancel()
            }
            interaction.forwardSelectedMessages(); XCTAssertEqual(delivered, 1)
        }
        XCTAssertTrue(LookupObservations.summaries.isEmpty)
    }
}
