import Foundation
import XCTest
import SwiftSignalKit

public protocol AccountContextProtocol { var engine: PremiumEngine { get }; var window: Window { get }; var premiumIsBlocked: Bool { get }; var inAppPurchaseManager: any InAppPurchaseManagerProtocol { get }; var account: StoreAccount { get } }
struct AccountContext: AccountContextProtocol { let engine = PremiumEngine(); let window = Window(); var premiumIsBlocked = false; let manager = StoreManager(); var inAppPurchaseManager: any InAppPurchaseManagerProtocol { manager }; let account = StoreAccount(); let bindings = PremiumBindings() }
public struct MessageId { let peerId: Int }
public enum BotPaymentInvoiceSource {
    case message(MessageId)
    case other
    case slug(String)
}
public struct TelegramMediaInvoice {}
public enum PaymentCheckoutResult { case paid, cancelled, failed }
typealias PaymentCheckoutCompletionStatus = PaymentCheckoutResult
public class ViewController {
    var analyticsScreen: AnalyticsScreen?
    public init(frame: NSRect = .zero) {}
    var analyticsContext: AnalyticsContext?
    var onDeinit: (() -> Void)?
    deinit { onDeinit?() }
}
public class ModalViewController: ViewController {}
public final class InputDataModalController: ModalViewController {
    let current = ViewController()
}
public final class AnalyticsContext {
__SIGNAL_CONTEXT__
    let excluded: Bool
    var depth = 0
    init(excluded: Bool) { self.excluded = excluded }
    func beginPresentation() -> AnalyticsPresentation { AnalyticsPresentation(self) }
    func restricting(peerId: PeerId) -> AnalyticsContext { self }
    func restricting(peerId: Int) -> AnalyticsContext {
        if peerId < 0 && !excluded { return AnalyticsContext(excluded: true) }
        return self
    }
}
final class AnalyticsPresentation {
    let context: AnalyticsContext
    var active = true
    init(_ context: AnalyticsContext) {
        self.context = context
        context.depth += 1
    }
    func end() {
        if active {
            active = false
            context.depth -= 1
        }
    }
    deinit { end() }
}
struct Hooks {
    static var shared = Hooks()
__PREMIUM_HOOK__
__HOOK__
}
__CHILD__

private func makeCompletion(analyticsContext: AnalyticsContext, completion: ((PaymentCheckoutCompletionStatus) -> Void)?) -> (PaymentCheckoutCompletionStatus) -> Void {
__COMPLETION__
    return invokeCompletion
}

final class PaymentContextTests: XCTestCase {
    func testChildConstructionBindsModalAndInnerControllerAndPreservesCleanup() {
        let origin = AnalyticsContext(excluded: true)
        var cleanups = 0
        var child: ModalViewController? = paymentChildController(analyticsContext: origin, create: {
            XCTAssertEqual(origin.depth, 1)
            let child = InputDataModalController()
            child.onDeinit = {
                XCTAssertEqual(origin.depth, 1)
                cleanups += 1
            }
            return child
        })
        XCTAssertTrue(child?.analyticsContext === origin)
        XCTAssertTrue((child as? InputDataModalController)?.current.analyticsContext === origin)
        child = nil
        XCTAssertEqual(cleanups, 1)
        XCTAssertEqual(origin.depth, 0)
    }

    func testChildKeepsContextAfterParentEnds() {
        let origin = AnalyticsContext(excluded: true)
        let parent = origin.beginPresentation()
        var child: ModalViewController? = paymentChildController(analyticsContext: origin, create: { ModalViewController() })
        XCTAssertNotNil(child)
        XCTAssertEqual(origin.depth, 2)
        parent.end()
        XCTAssertEqual(origin.depth, 1)
        child = nil
        XCTAssertEqual(origin.depth, 0)
    }

    func testSecretInvoiceRestrictsOrdinaryContextBeforeFactoryAndBinding() throws {
        let ordinary = AnalyticsContext(excluded: false)
        var received: AnalyticsContext?
        var hooks = Hooks()
        hooks.makePaymentsCheckoutControllerWithContext = { _, _, _, context, _ in
            XCTAssertTrue(context.excluded)
            XCTAssertEqual(context.depth, 1)
            received = context
            return InputDataModalController()
        }
        var controller = hooks.makePaymentsCheckoutObserved(AccountContext(), .message(MessageId(peerId: -1)), TelegramMediaInvoice(), analyticsContext: ordinary, completion: nil)
        let restricted = try XCTUnwrap(received)
        XCTAssertTrue(controller?.analyticsContext === restricted)
        XCTAssertTrue((controller as? InputDataModalController)?.current.analyticsContext === restricted)
        XCTAssertEqual(ordinary.depth, 0)
        controller = nil
        XCTAssertEqual(restricted.depth, 0)
    }

    func testLegacyFallbackRetainsContextThroughConstructionAndDelayedCompletion() {
        let origin = AnalyticsContext(excluded: true)
        var callback: ((PaymentCheckoutResult) -> Void)?
        var hooks = Hooks()
        hooks.makePaymentsCheckoutController = { _, _, _, completion in
            XCTAssertEqual(origin.depth, 1)
            callback = completion
            return ModalViewController()
        }
        var values = 0
        var controller = hooks.makePaymentsCheckoutObserved(AccountContext(), .other, TelegramMediaInvoice(), analyticsContext: origin, completion: { _ in
            XCTAssertEqual(origin.depth, 1)
            values += 1
        })
        XCTAssertTrue(controller?.analyticsContext === origin)
        controller = nil
        XCTAssertEqual(origin.depth, 0)
        callback?(.paid)
        XCTAssertEqual(values, 1)
        XCTAssertEqual(origin.depth, 0)
    }

    func testContextFactoryIsPreferredAndSynchronousNilResultReleasesLease() {
        let origin = AnalyticsContext(excluded: true)
        var hooks = Hooks()
        hooks.makePaymentsCheckoutController = { _, _, _, _ in
            XCTFail("Legacy factory unexpectedly used")
            return nil
        }
        hooks.makePaymentsCheckoutControllerWithContext = { _, _, _, context, completion in
            XCTAssertTrue(context === origin)
            XCTAssertEqual(origin.depth, 1)
            completion?(.failed)
            return nil
        }
        var results = 0
        let controller = hooks.makePaymentsCheckoutObserved(AccountContext(), .other, TelegramMediaInvoice(), analyticsContext: origin, completion: { _ in
            XCTAssertEqual(origin.depth, 2)
            results += 1
        })
        XCTAssertNil(controller)
        XCTAssertEqual(results, 1)
        XCTAssertEqual(origin.depth, 0)
    }

    func testHookCompletionSurvivesReentrantControllerDestruction() {
        let origin = AnalyticsContext(excluded: true)
        var callback: ((PaymentCheckoutResult) -> Void)?
        var controller: ModalViewController?
        var hooks = Hooks()
        hooks.makePaymentsCheckoutControllerWithContext = { _, _, _, _, completion in
            callback = completion
            return ModalViewController()
        }
        controller = hooks.makePaymentsCheckoutObserved(AccountContext(), .other, TelegramMediaInvoice(), analyticsContext: origin, completion: { _ in
            XCTAssertEqual(origin.depth, 2)
            controller = nil
            XCTAssertEqual(origin.depth, 1)
        })
        XCTAssertNotNil(controller)
        callback?(.paid)
        XCTAssertEqual(origin.depth, 0)
    }

    func testCheckoutCompletionClearsBeforeReentrantCancellation() {
        let origin = AnalyticsContext(excluded: true)
        var completion: ((PaymentCheckoutCompletionStatus) -> Void)!
        var values = 0
        completion = makeCompletion(analyticsContext: origin, completion: { _ in
            XCTAssertEqual(origin.depth, 1)
            values += 1
            if values == 1 { completion(.cancelled) }
            XCTAssertEqual(origin.depth, 1)
        })
        completion(.paid)
        completion(.failed)
        XCTAssertEqual(values, 1)
        XCTAssertEqual(origin.depth, 0)
    }

    func testCheckoutDeliveryRetainsContextWhenParentCloses() {
        let origin = AnalyticsContext(excluded: true)
        let parent = origin.beginPresentation()
        let completion = makeCompletion(analyticsContext: origin, completion: { _ in
            XCTAssertEqual(origin.depth, 2)
            parent.end()
            XCTAssertEqual(origin.depth, 1)
        })
        completion(.paid)
        XCTAssertEqual(origin.depth, 0)
    }
}
