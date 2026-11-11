import Foundation
import XCTest

final class Window {}
enum ConfirmResult: Equatable {
    case basic
    case thrid
}
private final class AlertFixture {
    static var shared = AlertFixture()
    var success: ((ConfirmResult) -> Void)?
    var cancel: (() -> Void)?
    var deinitCallback: (() -> Void)?
    var constructed: (() -> Void)?
    var labels: [String] = []
    var optionSelected: Bool?
}
func verifyAlert(for window: Window, header: String, information: String, ok: String, option: String, optionIsSelected: Bool, successHandler: @escaping (ConfirmResult) -> Void, cancelHandler: @escaping () -> Void, onDeinit: @escaping () -> Void) {
    let fixture = AlertFixture.shared
    fixture.labels = [header, information, ok, option]
    fixture.optionSelected = optionIsSelected
    fixture.success = successHandler
    fixture.cancel = cancelHandler
    fixture.deinitCallback = onDeinit
    fixture.constructed?()
}

__PAYMENT_CONFIRMATION__

final class PaymentConfirmationTests: XCTestCase {
    private func drainMainQueue() {
        let completed = expectation(description: "main queue drained")
        DispatchQueue.main.async { completed.fulfill() }
        wait(for: [completed], timeout: 1)
    }

    override func tearDown() {
        AlertFixture.shared.deinitCallback?()
        drainMainQueue()
        AlertFixture.shared = AlertFixture()
        super.tearDown()
    }

    private func present(_ origin: AnalyticsContext, success: @escaping (ConfirmResult) -> Void = { _ in }, cancel: @escaping () -> Void = {}, dismissed: @escaping () -> Void = {}) {
        verifyChatSendPayment(for: Window(), header: "Pay", information: "Message", ok: "Send", option: "Remember", analyticsContext: origin, successHandler: success, cancelHandler: cancel, dismissed: dismissed)
    }

    func testConstructionAndSelectionPreserveContextAndArguments() {
        let origin = AnalyticsContext(excluded: true)
        AlertFixture.shared.constructed = { XCTAssertEqual(origin.depth, 1) }
        var results: [ConfirmResult] = []
        present(origin, success: { result in
            XCTAssertEqual(origin.depth, 2)
            results.append(result)
        })
        XCTAssertEqual(AlertFixture.shared.labels, ["Pay", "Message", "Send", "Remember"])
        XCTAssertEqual(AlertFixture.shared.optionSelected, false)
        XCTAssertEqual(origin.depth, 1)
        AlertFixture.shared.success?(.thrid)
        XCTAssertEqual(results, [.thrid])
        XCTAssertEqual(origin.depth, 1)
        AlertFixture.shared.deinitCallback?()
        drainMainQueue()
        XCTAssertEqual(origin.depth, 0)
    }

    func testExplicitCancelCannotBecomeSuccessOrUnknownDismissal() {
        let origin = AnalyticsContext(excluded: true)
        var cancellations = 0
        var confirmations = 0
        var dismissals = 0
        present(origin, success: { _ in confirmations += 1 }, cancel: {
            XCTAssertEqual(origin.depth, 2)
            cancellations += 1
        }, dismissed: { dismissals += 1 })
        AlertFixture.shared.cancel?()
        AlertFixture.shared.cancel?()
        AlertFixture.shared.success?(.basic)
        AlertFixture.shared.deinitCallback?()
        drainMainQueue()
        XCTAssertEqual(cancellations, 1)
        XCTAssertEqual(confirmations, 0)
        XCTAssertEqual(dismissals, 0)
        XCTAssertEqual(origin.depth, 0)
    }

    func testCloseBeforeCompletionStillDeliversConfirmation() {
        let origin = AnalyticsContext(excluded: true)
        var confirmations = 0
        var dismissals = 0
        present(origin, success: { _ in
            XCTAssertEqual(origin.depth, 2)
            confirmations += 1
        }, dismissed: { dismissals += 1 })
        AlertFixture.shared.deinitCallback?()
        AlertFixture.shared.success?(.basic)
        drainMainQueue()
        XCTAssertEqual(confirmations, 1)
        XCTAssertEqual(dismissals, 0)
        XCTAssertEqual(origin.depth, 0)
    }

    func testUnknownDestructionResolvesOnceUnderOriginAndRejectsLateResults() {
        let origin = AnalyticsContext(excluded: true)
        var confirmations = 0
        var dismissals = 0
        present(origin, success: { _ in confirmations += 1 }, dismissed: {
            XCTAssertEqual(origin.depth, 2)
            dismissals += 1
        })
        AlertFixture.shared.deinitCallback?()
        AlertFixture.shared.deinitCallback?()
        XCTAssertEqual(dismissals, 0)
        XCTAssertEqual(origin.depth, 1)
        drainMainQueue()
        AlertFixture.shared.success?(.basic)
        AlertFixture.shared.cancel?()
        XCTAssertEqual(confirmations, 0)
        XCTAssertEqual(dismissals, 1)
        XCTAssertEqual(origin.depth, 0)
    }

    func testReentrantDestructionDoesNotLiftContextInsideSuccess() {
        let origin = AnalyticsContext(excluded: true)
        var confirmations = 0
        var dismissals = 0
        present(origin, success: { _ in
            XCTAssertEqual(origin.depth, 2)
            AlertFixture.shared.deinitCallback?()
            self.drainMainQueue()
            XCTAssertEqual(origin.depth, 1)
            confirmations += 1
        }, dismissed: { dismissals += 1 })
        AlertFixture.shared.success?(.basic)
        XCTAssertEqual(confirmations, 1)
        XCTAssertEqual(dismissals, 0)
        XCTAssertEqual(origin.depth, 0)
    }

    func testReentrantSuccessCannotDeliverSecondOutcome() {
        let origin = AnalyticsContext(excluded: false)
        var confirmations = 0
        var cancellations = 0
        present(origin, success: { _ in
            confirmations += 1
            AlertFixture.shared.success?(.thrid)
            AlertFixture.shared.cancel?()
        }, cancel: { cancellations += 1 })
        AlertFixture.shared.success?(.basic)
        XCTAssertEqual(confirmations, 1)
        XCTAssertEqual(cancellations, 0)
    }

    func testSynchronousFactoryCompletionUsesSameLifetimeRules() {
        let origin = AnalyticsContext(excluded: true)
        var confirmations = 0
        AlertFixture.shared.constructed = {
            AlertFixture.shared.deinitCallback?()
            AlertFixture.shared.success?(.basic)
        }
        present(origin, success: { _ in
            XCTAssertEqual(origin.depth, 2)
            confirmations += 1
        })
        drainMainQueue()
        XCTAssertEqual(confirmations, 1)
        XCTAssertEqual(origin.depth, 0)
    }
}
