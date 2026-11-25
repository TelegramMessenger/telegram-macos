import Foundation
import XCTest
import SwiftSignalKit

__REQUEST_STATE__

private enum RequestError: Error { case failed }
private final class Owner {}

private func startValidation(_ validation: Signal<Int, RequestError>, analyticsContext: AnalyticsContext, requestState: PaymentFormRequestState, requestDisposable: MetaDisposable, getController: (() -> Owner?)?, accepted: @escaping (Int) -> Void, failed: @escaping () -> Void = {}) {
    guard let requestId = requestState.begin() else { return }
__REQUEST_BINDING__
    operation.set(analyticsContext.preservingPresentation(validation).start(next: { result in
        __RESULT_GUARD__
        accepted(result)
    }, error: { _ in
        __RESULT_GUARD__
        failed()
    }, completed: {
        _ = requestState.take(requestId)
    }))
}

private struct CardState {
    var card = "synthetic card input"
    var holderName = "synthetic holder"
    var billingAddress = "synthetic billing"
    var saveInfo = false
    var error = false
    var peerStatus = 0
}
private struct ShippingState {
    var formInfo = "synthetic shipping input"
    var saveInfo = false
    var errors = false
}
private func updateCard(_ current: CardState, _ updated: CardState, _ requestState: PaymentFormRequestState) {
__CARD_INVALIDATION__
}
private func updateShipping(_ current: ShippingState, _ updated: ShippingState, _ requestState: PaymentFormRequestState) {
__SHIPPING_INVALIDATION__
}

final class FormRequestTests: XCTestCase {
    func testNewestRequestWinsAndOldCompletionCannotConsumeIt() throws {
        let state = PaymentFormRequestState()
        let old = try XCTUnwrap(state.begin())
        let current = try XCTUnwrap(state.begin())
        XCTAssertFalse(state.take(old))
        XCTAssertTrue(state.take(current))
        XCTAssertFalse(state.take(current))
    }

    func testInvalidationDoesNotPreventFreshAttempt() throws {
        let state = PaymentFormRequestState()
        let old = try XCTUnwrap(state.begin())
        state.invalidate()
        XCTAssertFalse(state.take(old))
        let current = try XCTUnwrap(state.begin())
        XCTAssertTrue(state.take(current))
    }

    func testReopeningDoesNotReviveOldRequest() throws {
        let state = PaymentFormRequestState()
        let old = try XCTUnwrap(state.begin())
        state.suspend()
        XCTAssertNil(state.begin())
        state.resume()
        XCTAssertFalse(state.take(old))
        let current = try XCTUnwrap(state.begin())
        state.resume()
        XCTAssertTrue(state.take(current))
    }

    func testConcurrentResultDeliveryAcceptsOnlyOneResult() throws {
        let state = PaymentFormRequestState()
        let request = try XCTUnwrap(state.begin())
        let count = Atomic<Int>(value: 0)
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            if state.take(request) { _ = count.modify { $0 + 1 } }
        }
        XCTAssertEqual(count.with { $0 }, 1)
    }

    func testCardInputChangesInvalidateWhilePresentationChangesDoNot() throws {
        let changes: [(inout CardState) -> Void] = [
            { $0.card = "changed" }, { $0.holderName = "changed" },
            { $0.billingAddress = "changed" }, { $0.saveInfo = true }
        ]
        for change in changes {
            let state = PaymentFormRequestState()
            let request = try XCTUnwrap(state.begin())
            let original = CardState()
            var updated = original
            change(&updated)
            updateCard(original, updated, state)
            updateCard(updated, original, state)
            XCTAssertFalse(state.take(request))
        }
        let state = PaymentFormRequestState()
        let request = try XCTUnwrap(state.begin())
        let original = CardState()
        var updated = original
        updated.error = true
        updated.peerStatus = 1
        updateCard(original, updated, state)
        XCTAssertTrue(state.take(request))
    }

    func testShippingInputAndSaveChoiceInvalidateButErrorsDoNot() throws {
        for saveChoice in [false, true] {
            let state = PaymentFormRequestState()
            let request = try XCTUnwrap(state.begin())
            let original = ShippingState()
            var updated = original
            if saveChoice { updated.saveInfo = true } else { updated.formInfo = "changed" }
            updateShipping(original, updated, state)
            XCTAssertFalse(state.take(request))
        }
        let state = PaymentFormRequestState()
        let request = try XCTUnwrap(state.begin())
        let original = ShippingState()
        var updated = original
        updated.errors = true
        updateShipping(original, updated, state)
        XCTAssertTrue(state.take(request))
    }

    func testDisappearanceDisposesOperationAndDropsLateResult() {
        let origin = AnalyticsContext(excluded: true)
        let state = PaymentFormRequestState()
        let slot = MetaDisposable()
        let owner = Owner()
        var subscriber: Subscriber<Int, RequestError>?
        var cleanups = 0
        var accepted = 0
        let source = Signal<Int, RequestError> { value in
            subscriber = value
            return ActionDisposable { cleanups += 1 }
        }
        startValidation(source, analyticsContext: origin, requestState: state, requestDisposable: slot, getController: { owner }, accepted: { _ in accepted += 1 })
        XCTAssertEqual(origin.depth, 1)
        state.suspend()
        slot.set(nil)
        subscriber?.putNext(1)
        XCTAssertEqual(accepted, 0)
        XCTAssertEqual(cleanups, 1)
        XCTAssertEqual(origin.depth, 0)
    }

    func testReentrantNewRequestSurvivesSynchronousOldCompletion() {
        let origin = AnalyticsContext(excluded: true)
        let state = PaymentFormRequestState()
        let slot = MetaDisposable()
        let owner = Owner()
        var newSubscriber: Subscriber<Int, RequestError>?
        var newCleanups = 0
        var values: [Int] = []
        let next = Signal<Int, RequestError> { value in
            newSubscriber = value
            return ActionDisposable { newCleanups += 1 }
        }
        startValidation(.single(1), analyticsContext: origin, requestState: state, requestDisposable: slot, getController: { owner }, accepted: { value in
            values.append(value)
            startValidation(next, analyticsContext: origin, requestState: state, requestDisposable: slot, getController: { owner }, accepted: { values.append($0) })
        })
        XCTAssertEqual(newCleanups, 0)
        XCTAssertEqual(origin.depth, 1)
        newSubscriber?.putNext(2)
        newSubscriber?.putCompletion()
        XCTAssertEqual(values, [1, 2])
        XCTAssertEqual(newCleanups, 1)
        XCTAssertEqual(origin.depth, 0)
        slot.dispose()
    }

    func testEditedFormIgnoresOldErrorAndReleasesContext() {
        let origin = AnalyticsContext(excluded: true)
        let state = PaymentFormRequestState()
        let slot = MetaDisposable()
        let owner = Owner()
        var subscriber: Subscriber<Int, RequestError>?
        var errors = 0
        let source = Signal<Int, RequestError> { value in subscriber = value; return EmptyDisposable }
        startValidation(source, analyticsContext: origin, requestState: state, requestDisposable: slot, getController: { owner }, accepted: { _ in XCTFail("Unexpected result") }, failed: { errors += 1 })
        state.invalidate()
        subscriber?.putError(.failed)
        XCTAssertEqual(errors, 0)
        XCTAssertEqual(origin.depth, 0)
        slot.dispose()
    }
}
