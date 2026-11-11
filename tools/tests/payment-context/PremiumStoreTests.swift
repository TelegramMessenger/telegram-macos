import Foundation
import XCTest
import SwiftSignalKit

public struct InAppPurchaseProduct {}
public enum AppStoreTransactionPurpose { case subscription }
__STORE_TYPES__
public final class StoreAccount { var refreshes = 0 }
public final class StoreManager: InAppPurchaseManagerProtocol {
    public var canMakePayments = true
    public var availableProducts: Signal<[InAppPurchaseProduct], NoError> { .complete() }
    var purchase: Signal<InAppPurchaseState, InAppPurchaseError> = .complete()
    var purchases = 0
    var finishes = 0
    var restores = 0
    var onBuy: (() -> Void)?
    var onRestore: (() -> Void)?
    var restoreCallback: ((InAppPurchaseRestoreState) -> Void)?
    public func restorePurchases(completion: @escaping (InAppPurchaseRestoreState) -> Void) { restores += 1; onRestore?(); restoreCallback = completion }
    func failRestore() { let callback = restoreCallback; callback?(.failed); restoreCallback = nil }
    public func finishAllTransactions() { finishes += 1 }
    public func buyProduct(_ product: InAppPurchaseProduct, quantity: Int32, purpose: AppStoreTransactionPurpose) -> Signal<InAppPurchaseState, InAppPurchaseError> { purchases += 1; onBuy?(); return purchase }
}
final class PremiumLockModalController: ModalViewController {
    var closes = 0
    override init(frame: NSRect = .zero) { super.init(frame: frame); StoreUI.onLockConstruction?(); StoreUI.locks.append(self) }
    func close() { closes += 1; PremiumUI.modals.removeAll { $0 === self } }
}
enum StoreUI {
    static var delayed: [() -> Void] = []
    static var locks: [PremiumLockModalController] = []
    static var onLockConstruction: (() -> Void)?
    static func runDelayed() { while !delayed.isEmpty { delayed.removeFirst()() } }
}
func delay(_ delay: Double, closure: @escaping () -> Void) { StoreUI.delayed.append(closure) }
func updatePremiumPromoConfigurationOnce(account: StoreAccount) -> Signal<Never, NoError> {
    Signal { subscriber in account.refreshes += 1; subscriber.putCompletion(); return EmptyDisposable }
}
__STORE_OPERATIONS__

final class PremiumStoreTests: XCTestCase {
    private func drain() {
        let done = expectation(description: "main callbacks")
        DispatchQueue.main.async { done.fulfill() }
        wait(for: [done], timeout: 2)
    }
    override func setUp() {
        PremiumUI.modals = []
        PremiumUI.feedback = []
        PremiumUI.confetti = 0
        PremiumUI.onFeedback = nil
        StoreUI.delayed = []
        StoreUI.locks = []
        StoreUI.onLockConstruction = nil
    }
    override func tearDown() { StoreUI.runDelayed(); drain(); PremiumUI.modals = []; StoreUI.locks = []; PremiumUI.onFeedback = nil; StoreUI.onLockConstruction = nil }
    func testFastErrorsNeverPresentDelayedLockAndFinishOnlyOnce() {
        let errors: [(InAppPurchaseError, String)] = [(.generic, "unknown store error"), (.assignFailed, "unknown store error"), (.network, "network error"), (.notAllowed, "not allowed"), (.cantMakePayments, "cannot pay"), (.cancelled, "cancelled")]
        for (error, message) in errors {
            let context = AccountContext()
            let origin = AnalyticsContext(excluded: true)
            context.manager.purchase = .fail(error)
            PremiumUI.onFeedback = { XCTAssertGreaterThan(origin.depth, 0); XCTAssertEqual(context.manager.finishes, 1) }
            premiumStorePurchase(context: context, product: InAppPurchaseProduct(), analyticsContext: origin, paid: { XCTFail("Not purchased") })
            XCTAssertEqual(PremiumUI.feedback.last, message)
            XCTAssertEqual(context.manager.finishes, 1)
            XCTAssertEqual(StoreUI.locks.last?.closes, 1)
            StoreUI.runDelayed()
            XCTAssertTrue(PremiumUI.modals.isEmpty)
            XCTAssertEqual(origin.depth, 0)
        }
    }
    func testDelayedPurchaseAfterParentEndsPreservesConstructionDeliveryAndFeedback() {
        let context = AccountContext()
        let origin = AnalyticsContext(excluded: true)
        let parent = origin.beginPresentation()
        var purchased: (() -> Void)?
        var disposed = 0
        context.manager.purchase = Signal { subscriber in
            XCTAssertGreaterThan(origin.depth, 0)
            purchased = { subscriber.putNext(.purchased(transactionId: "synthetic")) }
            return ActionDisposable { disposed += 1 }
        }
        context.manager.onBuy = { XCTAssertGreaterThan(origin.depth, 0) }
        StoreUI.onLockConstruction = { XCTAssertGreaterThan(origin.depth, 0) }
        PremiumUI.onFeedback = { XCTAssertGreaterThan(origin.depth, 0) }
        var paid = 0
        premiumStorePurchase(context: context, product: InAppPurchaseProduct(), analyticsContext: origin) { paid += 1; XCTAssertGreaterThan(origin.depth, 0) }
        parent.end()
        StoreUI.runDelayed()
        XCTAssertEqual(PremiumUI.modals.count, 1)
        XCTAssertTrue(PremiumUI.modals[0].analyticsContext === origin)
        purchased?(); purchased?()
        XCTAssertEqual(paid, 1)
        XCTAssertEqual(context.manager.finishes, 1)
        XCTAssertEqual(disposed, 1)
        XCTAssertTrue(PremiumUI.modals.isEmpty)
        XCTAssertGreaterThan(origin.depth, 0)
        StoreUI.runDelayed()
        XCTAssertEqual(PremiumUI.feedback, ["store success"])
        XCTAssertEqual(PremiumUI.confetti, 1)
        XCTAssertEqual(context.account.refreshes, 1)
        XCTAssertEqual(origin.depth, 0)
    }
    func testPurchaseCleanupPrecedesReentrantRestoreAndOldCompletionKeepsNewOwner() {
        let context = AccountContext()
        let origin = AnalyticsContext(excluded: true)
        context.manager.purchase = .single(.purchased(transactionId: "synthetic"))
        premiumStorePurchase(context: context, product: InAppPurchaseProduct(), analyticsContext: origin) {
            XCTAssertEqual(context.manager.finishes, 1)
            premiumStoreRestore(context: context, analyticsContext: origin)
        }
        XCTAssertEqual(context.manager.restores, 1)
        StoreUI.runDelayed()
        XCTAssertEqual(origin.depth, 1)
        context.manager.restoreCallback?(.succeed(false))
        drain()
        XCTAssertEqual(origin.depth, 0)
        context.manager.restoreCallback = nil
    }
    func testRejectedOrEmptyEligibilityDoesNotBuyAndCannotLeaveLock() {
        for empty in [false, true] {
            let context = AccountContext()
            let origin = AnalyticsContext(excluded: true)
            context.engine.payments.eligibility = empty ? .complete() : .single(false)
            premiumStorePurchase(context: context, product: InAppPurchaseProduct(), analyticsContext: origin, paid: { XCTFail("No eligibility") })
            StoreUI.runDelayed()
            XCTAssertEqual(context.manager.purchases, 0)
            XCTAssertTrue(PremiumUI.modals.isEmpty)
            XCTAssertTrue(PremiumUI.feedback.isEmpty)
            XCTAssertEqual(origin.depth, 0)
        }
    }
    func testEmptyPurchaseIsUnknownAndReleasesAdmissionForRetry() {
        let context = AccountContext()
        let origin = AnalyticsContext(excluded: true)
        for _ in 0..<2 {
            premiumStorePurchase(context: context, product: InAppPurchaseProduct(), analyticsContext: origin, paid: { XCTFail("Empty result") })
            StoreUI.runDelayed()
            XCTAssertEqual(origin.depth, 0)
        }
        XCTAssertEqual(context.manager.purchases, 2)
        XCTAssertEqual(context.manager.finishes, 0)
        XCTAssertTrue(PremiumUI.feedback.isEmpty)
        XCTAssertTrue(PremiumUI.modals.isEmpty)
    }
    func testPendingEligibilityBlocksDuplicatePurchaseAndRestoreForSameManager() {
        let context = AccountContext()
        let origin = AnalyticsContext(excluded: true)
        var eligibility: ((Bool) -> Void)?
        context.engine.payments.eligibility = Signal { subscriber in
            eligibility = { subscriber.putNext($0) }
            return EmptyDisposable
        }
        premiumStorePurchase(context: context, product: InAppPurchaseProduct(), analyticsContext: origin, paid: {})
        premiumStorePurchase(context: context, product: InAppPurchaseProduct(), analyticsContext: AnalyticsContext(excluded: false), paid: {})
        premiumStoreRestore(context: context, analyticsContext: AnalyticsContext(excluded: false))
        XCTAssertEqual(context.engine.payments.eligibilityChecks, 1)
        XCTAssertEqual(context.manager.restores, 0)
        eligibility?(false)
        StoreUI.runDelayed()
        premiumStoreRestore(context: context, analyticsContext: origin)
        XCTAssertEqual(context.manager.restores, 1)
        context.manager.restoreCallback?(.failed)
        drain()
        context.manager.restoreCallback = nil
        XCTAssertEqual(origin.depth, 0)
    }
    func testRepeatedEligibilityCanOnlyStartOnePurchase() {
        let context = AccountContext()
        let origin = AnalyticsContext(excluded: true)
        context.engine.payments.eligibility = Signal { subscriber in
            subscriber.putNext(true); subscriber.putNext(true); subscriber.putCompletion()
            return EmptyDisposable
        }
        context.manager.purchase = .single(.purchased(transactionId: "synthetic"))
        var paid = 0
        premiumStorePurchase(context: context, product: InAppPurchaseProduct(), analyticsContext: origin) { paid += 1 }
        StoreUI.runDelayed()
        XCTAssertEqual(context.manager.purchases, 1)
        XCTAssertEqual(paid, 1)
        XCTAssertEqual(origin.depth, 0)
    }
    func testRestoreKeepsOriginalContextAfterParentEndsAndConsumesBackgroundResultOnce() {
        let context = AccountContext()
        let origin = AnalyticsContext(excluded: true)
        let parent = origin.beginPresentation()
        context.manager.onRestore = { XCTAssertGreaterThan(origin.depth, 0) }
        PremiumUI.onFeedback = { XCTAssertTrue(Thread.isMainThread); XCTAssertGreaterThan(origin.depth, 0) }
        premiumStoreRestore(context: context, analyticsContext: origin)
        parent.end()
        XCTAssertEqual(origin.depth, 1)
        let callback = context.manager.restoreCallback!
        let delivered = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            XCTAssertFalse(Thread.isMainThread)
            callback(.succeed(true)); callback(.failed)
            delivered.signal()
        }
        XCTAssertEqual(delivered.wait(timeout: .now() + 2), .success)
        drain()
        XCTAssertEqual(PremiumUI.feedback, ["restore success"])
        XCTAssertEqual(origin.depth, 0)
        context.manager.restoreCallback = nil
    }
    func testOverlappingRestoreCannotReplaceOriginOrStartPurchase() {
        let context = AccountContext()
        let origin = AnalyticsContext(excluded: true)
        let other = AnalyticsContext(excluded: false)
        premiumStoreRestore(context: context, analyticsContext: origin)
        let original = context.manager.restoreCallback!
        premiumStoreRestore(context: context, analyticsContext: other)
        premiumStorePurchase(context: context, product: InAppPurchaseProduct(), analyticsContext: other, paid: {})
        XCTAssertEqual(context.manager.restores, 1)
        XCTAssertEqual(context.manager.purchases, 0)
        XCTAssertEqual(other.depth, 0)
        original(.succeed(false))
        drain()
        XCTAssertTrue(PremiumUI.feedback.isEmpty)
        premiumStoreRestore(context: context, analyticsContext: other)
        XCTAssertEqual(context.manager.restores, 2)
        original(.failed)
        drain()
        XCTAssertEqual(other.depth, 1)
        XCTAssertTrue(PremiumUI.feedback.isEmpty)
        context.manager.restoreCallback?(.failed)
        drain()
        XCTAssertEqual(PremiumUI.feedback, ["restore failed"])
        XCTAssertEqual(other.depth, 0)
        context.manager.restoreCallback = nil
    }
    func testDifferentManagersRetainIndependentOrigins() {
        let first = AccountContext()
        let second = AccountContext()
        let privateOrigin = AnalyticsContext(excluded: true)
        let ordinary = AnalyticsContext(excluded: false)
        premiumStoreRestore(context: first, analyticsContext: privateOrigin)
        premiumStoreRestore(context: second, analyticsContext: ordinary)
        XCTAssertEqual(first.manager.restores, 1)
        XCTAssertEqual(second.manager.restores, 1)
        first.manager.restoreCallback?(.succeed(false))
        drain()
        XCTAssertEqual(privateOrigin.depth, 0)
        XCTAssertEqual(ordinary.depth, 1)
        second.manager.restoreCallback?(.failed)
        drain()
        XCTAssertEqual(ordinary.depth, 0)
        first.manager.restoreCallback = nil
        second.manager.restoreCallback = nil
    }
    func testDroppedRestoreCallbackReleasesAdmissionWithoutInventingResult() {
        let context = AccountContext()
        let origin = AnalyticsContext(excluded: true)
        premiumStoreRestore(context: context, analyticsContext: origin)
        let released = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            XCTAssertFalse(Thread.isMainThread)
            context.manager.restoreCallback = nil
            released.signal()
        }
        XCTAssertEqual(released.wait(timeout: .now() + 2), .success)
        XCTAssertEqual(origin.depth, 0)
        premiumStoreRestore(context: context, analyticsContext: origin)
        XCTAssertEqual(context.manager.restores, 2)
        context.manager.restoreCallback = nil
        XCTAssertEqual(origin.depth, 0)
        XCTAssertTrue(PremiumUI.feedback.isEmpty)
    }
    func testTerminalFeedbackAllowsReentrantRetryWithoutOldCompletionTakingOwnership() {
        let context = AccountContext()
        let origin = AnalyticsContext(excluded: true)
        premiumStoreRestore(context: context, analyticsContext: origin)
        let old = context.manager.restoreCallback!
        var retried = false
        PremiumUI.onFeedback = {
            guard !retried else { return }
            retried = true
            premiumStoreRestore(context: context, analyticsContext: origin)
        }
        context.manager.failRestore()
        drain()
        XCTAssertEqual(context.manager.restores, 2)
        XCTAssertNotNil(context.manager.restoreCallback)
        XCTAssertEqual(origin.depth, 1)
        old(.succeed(true))
        drain()
        XCTAssertEqual(origin.depth, 1)
        context.manager.restoreCallback?(.succeed(false))
        drain()
        XCTAssertEqual(origin.depth, 0)
        XCTAssertEqual(PremiumUI.feedback, ["restore failed"])
        context.manager.restoreCallback = nil
    }
}
