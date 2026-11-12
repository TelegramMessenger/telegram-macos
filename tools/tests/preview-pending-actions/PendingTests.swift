import Foundation
import XCTest

__ACTIONS__
__ATTACHMENT_EDITS__
__DEFERRED__
__CHILD__

final class AnalyticsPresentation {
    private var finish: (() -> Void)?
    init(_ finish: @escaping () -> Void) { self.finish = finish }
    func end() { let callback = finish; finish = nil; callback?() }
    deinit { end() }
}
final class Context {
    let window = Window()
    var depth = 0
    var onPriceConstruction: (() -> Void)?
    func beginPresentation() -> AnalyticsPresentation {
        depth += 1
        return AnalyticsPresentation { self.depth -= 1 }
    }
}
typealias AnalyticsContext = Context
final class Window {}
final class Analytics {
    static let shared = Analytics()
    func unresolvedContext() -> Context { Context() }
}
struct ChatState {
    var alwaysPaid = false
    func withUpdatedAlwaysPaidMessage(_ value: Bool) -> ChatState { ChatState(alwaysPaid: value) }
}
final class ChatInteraction {
    struct Schedule { let date: Int32; let repeatPeriod: Int32? }
    var revision = 0
    var preferenceWrites = 0
    var state = ChatState()
    var onUpdate: (() -> Void)?
    func captureDeferredSendAction() -> ChatDeferredSendAction {
        let revision = self.revision
        return ChatDeferredSendAction { [weak self] in self?.revision == revision }
    }
    func update(_ transform: (ChatState) -> ChatState) { state = transform(state); preferenceWrites += 1; onUpdate?() }
}
final class Journey {
    enum Step { case cancelSchedule, openPrice, applyPrice, cancelPrice, removePrice, openEffectPremium }
    var steps: [Step] = []
    var cancelled = 0
    var discarded = 0
    var scheduleCancelled = 0
    func cancel() { cancelled += 1 }
    func discard() { discarded += 1 }
    func step(_ step: Step) { steps.append(step); if step == .cancelSchedule { scheduleCancelled += 1 } }
}
enum ModalAnimationCloseBehaviour { case common, noMorph }
class Base {
    var closes: [ModalAnimationCloseBehaviour] = []
    func close(animationType: ModalAnimationCloseBehaviour) { closes.append(animationType) }
    func viewWillDisappear(_ animated: Bool) {}
}
struct Peer { let id = 1 }
enum Mode { case schedule(Int) }
enum Via { case sendControl }
struct DateCallbacks {
    let selected: (Int32, Int32?) -> Void
    let cancelled: () -> Void
    let dismissed: () -> Void
}
enum PremiumSource { case savedTags, messageEffects }
final class FeatureNavigationHooks {
    var premiumOrigins: [Context] = []
    var premiumRoutes: [(PremiumSource?, Bool)] = []
    func showPremiumBoardingObserved(_ context: Context, _ window: Window, _ source: PremiumSource?, _ features: Bool, _ theme: Int?, analyticsContext: Context) { premiumOrigins.append(analyticsContext); premiumRoutes.append((source, features)) }
    static let shared = FeatureNavigationHooks()
    var dates: [DateCallbacks] = []
    func selectDateObserved(_ context: Context, _ window: Window, _ date: Int?, _ period: Int?, _ mode: Mode, analyticsContext: Context, selectedAt: @escaping (Int32, Int32?) -> Void, cancelled: @escaping () -> Void, dismissed: @escaping () -> Void) {
        dates.append(DateCallbacks(selected: selectedAt, cancelled: cancelled, dismissed: dismissed))
    }
}
final class PasteSubscriptionFixture { func dispose() {} }
final class Controller: Base {
    let context = Context()
    let genericView = PricePreviewView()
    let pasteActions = PreviewSenderPendingActions()
    let attachmentEdits = PreviewSenderAttachmentEdits()
    let editorDisposable = PasteSubscriptionFixture()
    let pasteDisposable = PasteSubscriptionFixture()
    let pendingActions = PreviewSenderPendingActions()
    let chatInteraction = ChatInteraction()
    var analyticsMediaJourney: Journey? = Journey()
    var analyticsContext: Context? = Context()
    var sent = false
    var window: Window? = Window()
    var sendCurrentMedia: ((Bool, ChatInteraction.Schedule?, Bool?, Via) -> Void)?
    var onSend: (() -> Void)?
__EFFECT_PREMIUM__
__PRICE__
__CAPTURE__
__CLOSE__
__DISAPPEAR__
    func sendBatches(_ count: Int, onBatch: (Int) -> Void) {
        let submission = analyticsMediaJourney
        sent = true
        for index in 0..<count {
__BATCH_GUARD__
            onBatch(index)
        }
    }
    var sendEntries = 0
    func sendEntry() {
__SEND_ENTRY__
        sendEntries += 1
    }
    func currentEntry() -> () -> Void {
        return { [weak self] in
__CURRENT_ENTRY__
            self.sendEntries += 1
        }
    }
    func appFileEntry() -> () -> Void {
        return { [weak self] in
__APP_FILE_ENTRY__
            self.sendEntries += 1
        }
    }
    func makeSubmission() -> (Bool?) -> Void {
__SUBMIT_PREFIX__
            self.onSend?()
        }
        return invoke
    }
    func schedule() {
        let context = Context()
        let peer = Peer()
        let analyticsContext = self.analyticsContext!
        let scheduleAction = capturePendingAction()
        let silent = false
        let asSpoiler: Bool? = nil
        let via = Via.sendControl
__SCHEDULE__
    }
}

final class PendingTests: XCTestCase {
    override func setUp() { FeatureNavigationHooks.shared.dates = [] }
    func testTokenInspectionDoesNotConsumeAndTakingIsOnceOnly() {
        let state = PreviewSenderPendingActions()
        let token = state.captureToken()
        XCTAssertTrue(token.isCurrent)
        XCTAssertTrue(token.isCurrent)
        XCTAssertTrue(token.take())
        XCTAssertFalse(token.isCurrent)
        XCTAssertFalse(token.take())
    }
    func testTokenInspectionRejectsReplacementClosureAndOwnerLoss() {
        var state: PreviewSenderPendingActions? = PreviewSenderPendingActions()
        let old = state!.captureToken()
        let current = state!.captureToken()
        XCTAssertFalse(old.isCurrent)
        XCTAssertFalse(old.take())
        state!.close()
        XCTAssertFalse(current.isCurrent)
        XCTAssertFalse(current.take())
        state = PreviewSenderPendingActions()
        let released = state!.captureToken()
        state = nil
        XCTAssertFalse(released.isCurrent)
        XCTAssertFalse(released.take())
    }
    func testChatActionInspectionDoesNotConsumeOrReviveConsumedAction() {
        var valid = true
        let action = ChatDeferredSendAction(isCurrent: { valid })
        XCTAssertTrue(action.isAvailable)
        XCTAssertTrue(action.isAvailable)
        valid = false
        XCTAssertFalse(action.isAvailable)
        XCTAssertFalse(action.takeIfCurrent())
        valid = true
        XCTAssertFalse(action.isAvailable)
        XCTAssertFalse(action.takeIfCurrent())
        let current = ChatDeferredSendAction(isCurrent: { true })
        XCTAssertTrue(current.isAvailable)
        XCTAssertTrue(current.takeIfCurrent())
        XCTAssertFalse(current.isAvailable)
    }
    func testActionIsConsumedOnceAndNewAttemptSupersedesOld() {
        let state = PreviewSenderPendingActions()
        let old = state.capture()
        let current = state.capture()
        XCTAssertFalse(old())
        XCTAssertTrue(current())
        XCTAssertFalse(current())
    }
    func testInvalidationCannotReviveOldActionAndCloseIsPermanent() {
        let state = PreviewSenderPendingActions()
        let action = state.capture()
        state.invalidate()
        XCTAssertFalse(action())
        let next = state.capture()
        state.close()
        XCTAssertFalse(next())
        XCTAssertFalse(state.capture()())
        XCTAssertTrue(state.isClosed)
    }
    func testActionDoesNotRetainItsOwner() {
        var state: PreviewSenderPendingActions? = PreviewSenderPendingActions()
        let action = state!.capture()
        state = nil
        XCTAssertFalse(action())
    }
    func testPreviewActionAlsoValidatesOriginalChatRevision() {
        let controller = Controller()
        let action = controller.capturePendingAction()
        controller.chatInteraction.revision += 1
        XCTAssertFalse(action())
        XCTAssertFalse(action())
    }
    func testExplicitCloseEndsTaskOnceAndInvalidatesDelayedAction() {
        let controller = Controller()
        let action = controller.capturePendingAction()
        controller.closeModal(); controller.closeModal()
        XCTAssertEqual(controller.closes.count, 1)
        XCTAssertEqual(controller.analyticsMediaJourney?.cancelled, 1)
        XCTAssertFalse(action())
    }
    func testGenericDisappearanceDiscardsWithoutInventingCancel() {
        let controller = Controller()
        let action = controller.capturePendingAction()
        controller.viewWillDisappear(true)
        XCTAssertEqual(controller.analyticsMediaJourney?.discarded, 1)
        XCTAssertEqual(controller.analyticsMediaJourney?.cancelled, 0)
        XCTAssertFalse(action())
    }
    func testCommittedSubmissionIsNotDiscardedOrCancelledByClose() {
        let controller = Controller()
        var sends = 0
        controller.onSend = { sends += 1 }
        let send = controller.makeSubmission()
        send(nil); send(nil)
        controller.closeModal()
        controller.viewWillDisappear(true)
        XCTAssertEqual(sends, 1)
        XCTAssertEqual(controller.analyticsMediaJourney?.cancelled, 0)
        XCTAssertEqual(controller.analyticsMediaJourney?.discarded, 0)
    }
    func testInvalidSubmissionCannotChangePreferenceOrSend() {
        for close in [false, true] {
            let controller = Controller()
            var sends = 0
            controller.onSend = { sends += 1 }
            let send = controller.makeSubmission()
            if close { controller.pendingActions.close() } else { controller.chatInteraction.revision += 1 }
            send(true)
            XCTAssertEqual(sends, 0)
            XCTAssertEqual(controller.chatInteraction.preferenceWrites, 0)
            XCTAssertFalse(controller.sent)
        }
    }
    func testSubmissionCommitsBeforeReentrantPreferenceAndSendCallbacks() {
        let controller = Controller()
        var sends = 0
        var submit: ((Bool?) -> Void)!
        submit = controller.makeSubmission()
        controller.chatInteraction.onUpdate = { XCTAssertTrue(controller.sent); submit(true) }
        controller.onSend = { sends += 1; submit(nil) }
        submit(true)
        XCTAssertEqual(sends, 1)
        XCTAssertEqual(controller.chatInteraction.preferenceWrites, 1)
        XCTAssertTrue(controller.chatInteraction.state.alwaysPaid)
    }
    func testScheduleSelectionCancelAndDismissalAreMutuallyExclusive() {
        let controller = Controller()
        var dates: [Int32] = []
        controller.sendCurrentMedia = { _, schedule, _, _ in dates.append(schedule!.date) }
        controller.schedule()
        let callbacks = FeatureNavigationHooks.shared.dates[0]
        callbacks.selected(10, nil); callbacks.selected(20, nil); callbacks.cancelled(); callbacks.dismissed()
        XCTAssertEqual(dates, [10])
        XCTAssertEqual(controller.analyticsMediaJourney?.scheduleCancelled, 0)
        XCTAssertEqual(controller.analyticsMediaJourney?.discarded, 0)
    }
    func testOldScheduleCannotAffectNewAttemptOrClosedPreview() {
        let controller = Controller()
        var sends = 0
        controller.sendCurrentMedia = { _, _, _, _ in sends += 1 }
        controller.schedule()
        let old = FeatureNavigationHooks.shared.dates[0]
        controller.schedule()
        let current = FeatureNavigationHooks.shared.dates[1]
        old.selected(1, nil); old.cancelled(); old.dismissed()
        XCTAssertEqual(sends, 0)
        XCTAssertEqual(controller.analyticsMediaJourney?.discarded, 0)
        controller.pendingActions.close()
        current.selected(2, nil)
        XCTAssertEqual(sends, 0)
    }
    func testScheduleCancelKeepsParentAndUnknownDismissalDiscards() {
        let controller = Controller()
        controller.schedule()
        FeatureNavigationHooks.shared.dates[0].cancelled()
        XCTAssertEqual(controller.analyticsMediaJourney?.scheduleCancelled, 1)
        XCTAssertEqual(controller.analyticsMediaJourney?.cancelled, 0)
        controller.schedule()
        FeatureNavigationHooks.shared.dates[1].dismissed()
        XCTAssertEqual(controller.analyticsMediaJourney?.discarded, 1)
    }
}


final class ChildActionTests: XCTestCase {
    private func drainMainQueue() {
        let drained = expectation(description: "dismissal finalized")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
    }
    func testOriginLeaseCoversConstructionAndResolutionUntilDismissal() {
        let context = Context()
        let child = PreviewSenderChildAction(context: context, isCurrent: { true })
        XCTAssertEqual(context.depth, 1)
        child.resolve { XCTAssertEqual(context.depth, 2) }
        XCTAssertEqual(context.depth, 1)
        child.dismissed()
        drainMainQueue()
        XCTAssertEqual(context.depth, 0)
    }
    func testCloseBeforeCallbackAllowsSameTurnResultUnderOriginalLease() {
        let context = Context()
        let child = PreviewSenderChildAction(context: context, isCurrent: { true })
        var calls = 0
        child.dismissed()
        child.resolve { calls += 1; XCTAssertEqual(context.depth, 2) }
        drainMainQueue()
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(context.depth, 0)
    }
    func testUnknownDismissalRejectsLaterResultsAndIsIdempotent() {
        let context = Context()
        let child = PreviewSenderChildAction(context: context, isCurrent: { true })
        var calls = 0
        child.dismissed(); child.dismissed()
        drainMainQueue()
        child.resolve { calls += 1 }
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(context.depth, 0)
    }
    func testResolutionConsumesBeforeReentrantAction() {
        let context = Context()
        let child = PreviewSenderChildAction(context: context, isCurrent: { true })
        var calls = 0
        child.resolve {
            calls += 1
            child.resolve { calls += 1 }
            child.dismissed()
            drainMainQueue()
            XCTAssertEqual(context.depth, 1)
        }
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(context.depth, 0)
    }
    func testCurrentPredicateRunsUnderOriginAndCannotBeRetried() {
        let context = Context()
        var valid = false
        var checks = 0
        let child = PreviewSenderChildAction(context: context, isCurrent: {
            checks += 1
            XCTAssertEqual(context.depth, 2)
            return valid
        })
        var calls = 0
        child.resolve { calls += 1 }
        valid = true
        child.resolve { calls += 1 }
        XCTAssertEqual(checks, 1)
        XCTAssertEqual(calls, 0)
        child.dismissed()
        drainMainQueue()
        XCTAssertEqual(context.depth, 0)
    }
    func testClosedPreviewSuppressesActionWhileChildKeepsItsOrigin() {
        let controller = Controller()
        let context = controller.analyticsContext!
        let child = PreviewSenderChildAction(context: context, isCurrent: controller.capturePendingAction())
        controller.viewWillDisappear(true)
        XCTAssertEqual(context.depth, 1)
        var calls = 0
        child.resolve { calls += 1 }
        XCTAssertEqual(calls, 0)
        child.dismissed()
        drainMainQueue()
        XCTAssertEqual(context.depth, 0)
    }
    func testNewPreviewAttemptSupersedesOlderRecovery() {
        let controller = Controller()
        let context = controller.analyticsContext!
        let old = PreviewSenderChildAction(context: context, isCurrent: controller.capturePendingAction())
        let current = PreviewSenderChildAction(context: context, isCurrent: controller.capturePendingAction())
        var calls = 0
        old.resolve { calls += 10 }
        current.resolve { calls += 1 }
        XCTAssertEqual(calls, 1)
        old.dismissed(); current.dismissed()
        drainMainQueue()
        XCTAssertEqual(context.depth, 0)
    }
    func testDestroyingUnusedChildReleasesLease() {
        let context = Context()
        var child: PreviewSenderChildAction? = PreviewSenderChildAction(context: context, isCurrent: { true })
        XCTAssertNotNil(child)
        XCTAssertEqual(context.depth, 1)
        child = nil
        XCTAssertEqual(context.depth, 0)
    }
}

final class EffectPremiumTests: XCTestCase {
    override func setUp() { FeatureNavigationHooks.shared.premiumOrigins = []; FeatureNavigationHooks.shared.premiumRoutes = [] }
    func testActionUsesCapturedOriginOnce() {
        let owner = Controller()
        let origin = owner.analyticsContext!
        let open = owner.makeEffectPremiumAction()
        owner.analyticsContext = Context()
        XCTAssertTrue(owner.analyticsMediaJourney!.steps.isEmpty)
        open(); open()
        XCTAssertEqual(owner.analyticsMediaJourney?.steps, [.openEffectPremium])
        XCTAssertEqual(FeatureNavigationHooks.shared.premiumRoutes.first?.0, .messageEffects)
        XCTAssertEqual(FeatureNavigationHooks.shared.premiumRoutes.first?.1, false)
        XCTAssertEqual(FeatureNavigationHooks.shared.premiumOrigins.count, 1)
        XCTAssertTrue(FeatureNavigationHooks.shared.premiumOrigins.first === origin)
    }
    func testChangedChatPreviewNewActionClosureAndCommitRejectOldMenu() {
        for change in 0..<5 {
            let owner = Controller()
            let open = owner.makeEffectPremiumAction()
            switch change {
            case 0: owner.chatInteraction.revision += 1
            case 1: owner.pendingActions.invalidate()
            case 2: _ = owner.makeEffectPremiumAction()
            case 3: owner.pendingActions.close()
            default: owner.sent = true
            }
            open()
            XCTAssertTrue(owner.analyticsMediaJourney!.steps.isEmpty)
        }
        XCTAssertTrue(FeatureNavigationHooks.shared.premiumOrigins.isEmpty)
    }
    func testMenuKeepsOriginalJourneyAndNavigationWorksWithoutObservation() {
        let owner = Controller()
        let originalJourney = owner.analyticsMediaJourney!
        let open = owner.makeEffectPremiumAction()
        owner.analyticsMediaJourney = Journey()
        open()
        XCTAssertEqual(originalJourney.steps, [.openEffectPremium])
        XCTAssertTrue(owner.analyticsMediaJourney!.steps.isEmpty)
        owner.analyticsMediaJourney = nil
        owner.makeEffectPremiumAction()()
        XCTAssertEqual(FeatureNavigationHooks.shared.premiumOrigins.count, 2)
    }
    func testMenuActionDoesNotRetainPreview() {
        var owner: Controller? = Controller()
        weak var weakOwner = owner
        let open = owner!.makeEffectPremiumAction()
        owner = nil
        XCTAssertNil(weakOwner)
        open()
        XCTAssertTrue(FeatureNavigationHooks.shared.premiumOrigins.isEmpty)
    }
}

extension PendingTests {
    func testPreviewSourceBindingIsOptionalAndCannotBeReplaced() {
        let controller = Controller()
        XCTAssertTrue(controller.validateSendSource())
        XCTAssertTrue(controller.bindSendSourceValidation { false })
        XCTAssertFalse(controller.bindSendSourceValidation { true })
        XCTAssertFalse(controller.validateSendSource())
        XCTAssertEqual(controller.analyticsMediaJourney?.discarded, 1)
        let closed = Controller()
        closed.closeModal()
        XCTAssertFalse(closed.bindSendSourceValidation { true })
        let sent = Controller()
        sent.sent = true
        XCTAssertFalse(sent.bindSendSourceValidation { true })
    }
    func testInvalidSourceBlocksInitialAndDelayedSendEntriesWithoutClosingPreview() {
        let controller = Controller()
        var valid = true
        XCTAssertTrue(controller.bindSendSourceValidation { valid })
        controller.sendEntry()
        let delayed = controller.currentEntry()
        let appFile = controller.appFileEntry()
        valid = false
        controller.sendEntry()
        delayed()
        appFile()
        XCTAssertEqual(controller.sendEntries, 1)
        XCTAssertEqual(controller.genericView.sendButton.shakes, 1)
        XCTAssertTrue(controller.closes.isEmpty)
        XCTAssertFalse(controller.sent)
        XCTAssertGreaterThan(controller.analyticsMediaJourney?.discarded ?? 0, 0)
    }
    func testSourceChangeDuringPaymentCannotSendOrChangePreferences() {
        let controller = Controller()
        var valid = true
        XCTAssertTrue(controller.bindSendSourceValidation { valid })
        var sends = 0
        controller.onSend = { sends += 1 }
        let send = controller.makeSubmission()
        valid = false
        send(true)
        XCTAssertEqual(sends, 0)
        XCTAssertEqual(controller.chatInteraction.preferenceWrites, 0)
        XCTAssertFalse(controller.sent)
        XCTAssertEqual(controller.analyticsMediaJourney?.discarded, 1)
        valid = true
        send(true)
        XCTAssertEqual(sends, 0)
        XCTAssertEqual(controller.chatInteraction.preferenceWrites, 0)
        XCTAssertFalse(controller.validateSendSource())
    }
    func testSourceChangeBetweenBatchesStopsRemainingSendsWithoutClaimingCancellation() {
        let controller = Controller()
        var valid = true
        XCTAssertTrue(controller.bindSendSourceValidation { valid })
        var batches: [Int] = []
        controller.sendBatches(3) { index in
            batches.append(index)
            valid = false
        }
        XCTAssertEqual(batches, [0])
        XCTAssertEqual(controller.closes, [.noMorph])
        XCTAssertEqual(controller.analyticsMediaJourney?.cancelled, 0)
        XCTAssertGreaterThan(controller.analyticsMediaJourney?.discarded ?? 0, 0)
    }
    func testStaleSourceDoesNotBlockExplicitCloseConfirmation() {
        let controller = Controller()
        XCTAssertTrue(controller.bindSendSourceValidation { false })
        let close = controller.capturePendingAction()
        XCTAssertTrue(close())
        controller.closeModal()
        XCTAssertEqual(controller.closes, [.common])
    }
}
