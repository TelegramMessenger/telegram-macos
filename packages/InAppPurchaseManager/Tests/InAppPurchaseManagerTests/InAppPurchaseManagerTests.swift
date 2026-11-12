import XCTest
import StoreKit
import SwiftSignalKit
import TelegramCore
import TelegramContext
@testable import InAppPurchaseManager

private let annual = "org.telegram.telegramPremium.annual"
private let starsTopup = "org.telegram.telegramStars.topup.x100"
private let accountPeerId = "1000"

private final class Locked<Value> {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func with<Result>(_ f: (inout Value) -> Result) -> Result {
        self.lock.lock()
        defer {
            self.lock.unlock()
        }
        return f(&self.value)
    }

    var current: Value {
        return self.with { $0 }
    }
}

private final class FakeTransaction: SKPaymentTransaction, @unchecked Sendable {
    private let identifier: String?
    private let state: SKPaymentTransactionState
    private let fakePayment: SKPayment

    init(_ identifier: String?, _ state: SKPaymentTransactionState, product: String, user: String? = accountPeerId) {
        self.identifier = identifier
        self.state = state
        let payment = SKMutablePayment()
        payment.productIdentifier = product
        payment.applicationUsername = user
        self.fakePayment = payment
        super.init()
    }

    override var transactionIdentifier: String? {
        return self.identifier
    }

    override var transactionState: SKPaymentTransactionState {
        return self.state
    }

    override var payment: SKPayment {
        return self.fakePayment
    }

    override var original: SKPaymentTransaction? {
        return nil
    }

    override var error: Error? {
        return nil
    }
}

private final class FakePaymentQueue: SKPaymentQueue, @unchecked Sendable {
    let finished = Locked<[String]>([])
    let addedPayments = Locked<[String]>([])
    let restoreRequests = Locked<Int>(0)
    let queuedTransactions = Locked<[SKPaymentTransaction]>([])

    override func add(_ observer: SKPaymentTransactionObserver) {
    }

    override func remove(_ observer: SKPaymentTransactionObserver) {
    }

    override func add(_ payment: SKPayment) {
        self.addedPayments.with { $0.append(payment.productIdentifier) }
    }

    override func restoreCompletedTransactions() {
        self.restoreRequests.with { $0 += 1 }
    }

    override var transactions: [SKPaymentTransaction] {
        return self.queuedTransactions.current
    }

    override func finishTransaction(_ transaction: SKPaymentTransaction) {
        self.finished.with { $0.append(transaction.transactionIdentifier ?? "") }
    }
}

private final class FakeProduct: SKProduct, @unchecked Sendable {
    private let identifier: String

    init(_ identifier: String) {
        self.identifier = identifier
        super.init()
    }

    override var productIdentifier: String {
        return self.identifier
    }

    override var price: NSDecimalNumber {
        return NSDecimalNumber(string: "9.99")
    }

    override var priceLocale: Locale {
        return Locale(identifier: "en_US")
    }
}

private final class FakeProductsResponse: SKProductsResponse, @unchecked Sendable {
    private let fakeProducts: [SKProduct]

    init(_ products: [SKProduct]) {
        self.fakeProducts = products
        super.init()
    }

    override var products: [SKProduct] {
        return self.fakeProducts
    }
}

private final class FakeProductsRequest: SKProductsRequest {
    override func start() {
    }

    override func cancel() {
    }
}

private final class FakeServer {
    final class Request {
        let purpose: AppStoreTransactionPurpose
        fileprivate var subscriber: Subscriber<Never, AssignAppStoreTransactionError>?
        fileprivate var replied = false
        fileprivate var cancelled = false

        init(purpose: AppStoreTransactionPurpose) {
            self.purpose = purpose
        }
    }

    private let state = Locked<[Request]>([])

    var requests: [Request] {
        return self.state.current
    }

    func isCancelled(_ index: Int) -> Bool {
        return self.state.with { $0[index].cancelled }
    }

    func send(_ receipt: Data, _ purpose: AppStoreTransactionPurpose) -> Signal<Never, AssignAppStoreTransactionError> {
        return Signal { subscriber in
            let request = Request(purpose: purpose)
            request.subscriber = subscriber
            self.state.with { $0.append(request) }
            return ActionDisposable {
                self.state.with { _ in
                    if !request.replied {
                        request.cancelled = true
                    }
                }
            }
        }
    }

    func succeed(_ index: Int) {
        self.reply(index, error: nil)
    }

    func fail(_ index: Int) {
        self.reply(index, error: .generic)
    }

    private func reply(_ index: Int, error: AssignAppStoreTransactionError?) {
        let subscriber = self.state.with { requests -> Subscriber<Never, AssignAppStoreTransactionError>? in
            requests[index].replied = true
            return requests[index].subscriber
        }
        if let error {
            subscriber?.putError(error)
        } else {
            subscriber?.putCompletion()
        }
    }
}

private final class FakePendingStore {
    private let states = Locked<[String: PendingInAppPurchaseState]>([:])

    func state(_ productId: String) -> PendingInAppPurchaseState? {
        return self.states.current[productId]
    }

    func set(_ productId: String, _ state: PendingInAppPurchaseState?) {
        self.states.with { $0[productId] = state }
    }

    func get(_ productId: String) -> Signal<PendingInAppPurchaseState?, NoError> {
        return Signal { subscriber in
            subscriber.putNext(self.state(productId))
            subscriber.putCompletion()
            return EmptyDisposable
        }
    }

    func update(_ productId: String, _ state: PendingInAppPurchaseState?) -> Signal<Never, NoError> {
        return Signal { subscriber in
            self.set(productId, state)
            subscriber.putCompletion()
            return EmptyDisposable
        }
    }
}

private final class Harness {
    let queue: FakePaymentQueue
    let server: FakeServer
    let pending: FakePendingStore
    let productRequests: Locked<[SKProductsRequest]>
    let manager: InAppPurchaseManager

    init(canMakePayments: Bool = true) {
        let queue = FakePaymentQueue()
        let server = FakeServer()
        let pending = FakePendingStore()
        let productRequests = Locked<[SKProductsRequest]>([])
        self.queue = queue
        self.server = server
        self.pending = pending
        self.productRequests = productRequests
        self.manager = InAppPurchaseManager(environment: InAppPurchaseEnvironment(
            accountPeerId: accountPeerId,
            paymentQueue: queue,
            canMakePayments: {
                return canMakePayments
            },
            makeProductsRequest: { productIdentifiers in
                let request = FakeProductsRequest(productIdentifiers: productIdentifiers)
                productRequests.with { $0.append(request) }
                return request
            },
            receiptData: {
                return Data("receipt".utf8)
            },
            saveDebugReceipt: { _ in
            },
            sendReceipt: { receipt, purpose in
                return server.send(receipt, purpose)
            },
            pendingState: { productId in
                return pending.get(productId)
            },
            updatePendingState: { productId, state in
                return pending.update(productId, state)
            }
        ))
    }

    func settle() {
        for _ in 0 ..< 4 {
            self.manager.stateQueue.sync {
            }
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.005))
        }
    }

    func loadProducts(_ productIds: [String]) {
        self.settle()
        guard let request = self.productRequests.current.last else {
            XCTFail("No products request")
            return
        }
        self.manager.productsRequest(request, didReceive: FakeProductsResponse(productIds.map { FakeProduct($0) }))
        self.settle()
    }

    func setPendingPurchase(_ productId: String, _ purpose: PendingInAppPurchaseState.Purpose) {
        self.pending.set(productId, PendingInAppPurchaseState(productId: productId, purpose: purpose))
    }

    func deliver(_ transactions: [SKPaymentTransaction]) {
        self.manager.paymentQueue(self.queue, updatedTransactions: transactions)
        self.settle()
    }
}

private func isSubscription(_ purpose: AppStoreTransactionPurpose) -> Bool {
    if case .subscription = purpose {
        return true
    }
    return false
}

private func isRestore(_ purpose: AppStoreTransactionPurpose) -> Bool {
    if case .restore = purpose {
        return true
    }
    return false
}

final class InAppPurchaseManagerTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        let logger = Logger(rootPath: NSTemporaryDirectory(), basePath: NSTemporaryDirectory())
        logger.logToFile = false
        logger.logToConsole = false
        Logger.setSharedLogger(logger)
    }

    func testRedeliveriesWhileTheReceiptIsBeingAssignedNeitherResendNorCancelIt() {
        let harness = Harness()
        harness.loadProducts([annual])
        harness.setPendingPurchase(annual, .subscription)
        let transaction = FakeTransaction("T1", .purchased, product: annual)

        harness.deliver([transaction])
        XCTAssertEqual(harness.server.requests.count, 1)

        for _ in 0 ..< 500 {
            harness.manager.paymentQueue(harness.queue, updatedTransactions: [transaction])
        }
        harness.settle()

        XCTAssertEqual(harness.server.requests.count, 1)
        XCTAssertFalse(harness.server.isCancelled(0))
        XCTAssertEqual(harness.queue.finished.current, [])

        harness.server.succeed(0)
        harness.settle()

        XCTAssertEqual(harness.queue.finished.current, ["T1"])
        XCTAssertNil(harness.pending.state(annual))
    }

    func testRedeliveryAfterSuccessfulAssignmentFinishesTheTransactionWithoutSendingAgain() {
        let harness = Harness()
        harness.loadProducts([annual])
        harness.setPendingPurchase(annual, .subscription)
        let transaction = FakeTransaction("T1", .purchased, product: annual)

        harness.deliver([transaction])
        harness.server.succeed(0)
        harness.settle()

        harness.deliver([transaction])
        harness.deliver([transaction])

        XCTAssertEqual(harness.server.requests.count, 1)
        XCTAssertEqual(harness.queue.finished.current, ["T1", "T1", "T1"])
    }

    func testTerminalErrorFinishesTheTransactionClearsThePendingPurchaseAndStopsResending() {
        let harness = Harness()
        harness.loadProducts([annual])
        harness.setPendingPurchase(annual, .subscription)
        let transaction = FakeTransaction("T1", .purchased, product: annual)

        harness.deliver([transaction])
        harness.server.fail(0)
        harness.settle()

        XCTAssertEqual(harness.queue.finished.current, ["T1"])
        XCTAssertNil(harness.pending.state(annual))

        harness.deliver([transaction])

        XCTAssertEqual(harness.server.requests.count, 1)
        XCTAssertEqual(harness.queue.finished.current, ["T1", "T1"])
    }

    func testOnlyTheSentTransactionsAreFinished() {
        let harness = Harness()
        harness.loadProducts([annual, starsTopup])
        harness.setPendingPurchase(annual, .subscription)

        harness.deliver([
            FakeTransaction("T1", .purchased, product: annual),
            FakeTransaction("T2", .purchased, product: annual, user: "2000"),
            FakeTransaction(nil, .purchasing, product: starsTopup),
            FakeTransaction("T4", .restored, product: annual)
        ])
        XCTAssertEqual(harness.server.requests.count, 1)

        harness.server.fail(0)
        harness.settle()

        XCTAssertEqual(harness.queue.finished.current, ["T1"])
    }

    func testPurchasedTransactionWithoutAPendingPurchaseIsFinishedWithoutSendingTheReceipt() {
        let harness = Harness()
        harness.loadProducts([annual])

        harness.deliver([FakeTransaction("T1", .purchased, product: annual)])

        XCTAssertEqual(harness.server.requests.count, 0)
        XCTAssertEqual(harness.queue.finished.current, ["T1"])
    }

    func testReceiptIsSentOnceWhenProductsArriveAndRedeliveriesBeforeThatAreIgnored() {
        let harness = Harness()
        harness.settle()
        harness.setPendingPurchase(annual, .subscription)
        let transaction = FakeTransaction("T1", .purchased, product: annual)

        for _ in 0 ..< 20 {
            harness.deliver([transaction])
        }
        XCTAssertEqual(harness.server.requests.count, 0)
        XCTAssertEqual(harness.productRequests.current.count, 1)

        harness.loadProducts([annual])

        XCTAssertEqual(harness.server.requests.count, 1)
        XCTAssertTrue(isSubscription(harness.server.requests[0].purpose))
    }

    func testProductsAreRequestedOnlyOnceAfterTheyArrive() {
        let harness = Harness()
        harness.loadProducts([annual])
        harness.setPendingPurchase(annual, .subscription)

        for _ in 0 ..< 50 {
            let _ = harness.manager.availableProducts
        }
        for index in 0 ..< 10 {
            harness.deliver([FakeTransaction("T\(index)", .purchased, product: annual)])
        }

        XCTAssertEqual(harness.productRequests.current.count, 1)
        XCTAssertEqual(harness.server.requests.count, 10)
    }

    func testFailedProductsRequestIsRetriedOnTheNextAccess() {
        let harness = Harness()
        harness.settle()
        XCTAssertEqual(harness.productRequests.current.count, 1)

        let _ = harness.manager.availableProducts
        harness.settle()
        XCTAssertEqual(harness.productRequests.current.count, 1)

        harness.manager.request(harness.productRequests.current[0], didFailWithError: NSError(domain: "test", code: 1))
        harness.settle()
        let _ = harness.manager.availableProducts
        harness.settle()

        XCTAssertEqual(harness.productRequests.current.count, 2)
    }

    func testPurchaseSendsTheReceiptWithItsPurposeAndClearsThePendingPurchase() {
        let harness = Harness()
        harness.loadProducts([annual])
        var purchasedIds: [String] = []
        var errors: [InAppPurchaseError] = []

        let disposable = harness.manager.buyProduct(InAppPurchaseProduct(skProduct: FakeProduct(annual)), quantity: 1, purpose: .subscription).start(next: { state in
            if case let .purchased(transactionId) = state {
                purchasedIds.append(transactionId)
            }
        }, error: { error in
            errors.append(error)
        })
        harness.settle()
        XCTAssertEqual(harness.queue.addedPayments.current, [annual])

        harness.deliver([FakeTransaction(nil, .purchasing, product: annual)])
        guard let pendingPurchase = harness.pending.state(annual), case .subscription = pendingPurchase.purpose else {
            XCTFail("The purchase purpose was not stored")
            return
        }

        harness.deliver([FakeTransaction("T1", .purchased, product: annual)])
        XCTAssertEqual(purchasedIds, ["T1"])
        XCTAssertEqual(harness.server.requests.count, 1)
        XCTAssertTrue(isSubscription(harness.server.requests[0].purpose))

        harness.server.succeed(0)
        harness.settle()

        XCTAssertEqual(harness.queue.finished.current, ["T1"])
        XCTAssertNil(harness.pending.state(annual))
        XCTAssertEqual(errors, [])
        disposable.dispose()
    }

    func testFailedAssignmentOfAnOlderTransactionKeepsThePendingPurchaseOfANewerOne() {
        let harness = Harness()
        harness.loadProducts([annual])
        harness.setPendingPurchase(annual, .upgrade)

        harness.deliver([FakeTransaction("T1", .purchased, product: annual)])
        XCTAssertEqual(harness.server.requests.count, 1)

        var errors: [InAppPurchaseError] = []
        let disposable = harness.manager.buyProduct(InAppPurchaseProduct(skProduct: FakeProduct(annual)), quantity: 1, purpose: .subscription).start(error: { error in
            errors.append(error)
        })
        harness.settle()
        harness.deliver([FakeTransaction(nil, .purchasing, product: annual)])

        harness.server.fail(0)
        harness.settle()

        XCTAssertEqual(harness.queue.finished.current, ["T1"])
        XCTAssertEqual(errors, [])
        guard let pendingPurchase = harness.pending.state(annual), case .subscription = pendingPurchase.purpose else {
            XCTFail("The newer purchase lost its purpose")
            return
        }

        harness.deliver([FakeTransaction("T1", .purchased, product: annual)])

        XCTAssertEqual(harness.server.requests.count, 1)
        XCTAssertEqual(harness.queue.finished.current, ["T1", "T1"])
        disposable.dispose()
    }

    func testRestoreSendsTheReceiptWithTheRestorePurpose() {
        let harness = Harness()
        var results: [InAppPurchaseRestoreState] = []

        harness.manager.restorePurchases(completion: { result in
            results.append(result)
        })
        XCTAssertEqual(harness.queue.restoreRequests.current, 1)

        harness.manager.paymentQueueRestoreCompletedTransactionsFinished(harness.queue)
        harness.settle()
        XCTAssertEqual(harness.server.requests.count, 1)
        XCTAssertTrue(isRestore(harness.server.requests[0].purpose))

        harness.server.succeed(0)
        harness.settle()

        XCTAssertEqual(results.count, 1)
        guard let result = results.first, case .succeed(false) = result else {
            XCTFail("Unexpected restore result")
            return
        }
    }

    func testBuyingFailsWhenPaymentsAreNotAllowed() {
        let harness = Harness(canMakePayments: false)
        var errors: [InAppPurchaseError] = []

        let _ = harness.manager.buyProduct(InAppPurchaseProduct(skProduct: FakeProduct(annual)), quantity: 1, purpose: .subscription).start(error: { error in
            errors.append(error)
        })
        harness.settle()

        XCTAssertEqual(errors, [.cantMakePayments])
        XCTAssertEqual(harness.queue.addedPayments.current, [])
    }

    func testFinishAllTransactionsFinishesEveryQueuedTransaction() {
        let harness = Harness()
        harness.queue.queuedTransactions.with {
            $0 = [
                FakeTransaction("T1", .purchased, product: annual),
                FakeTransaction("T2", .failed, product: starsTopup)
            ]
        }

        harness.manager.finishAllTransactions()

        XCTAssertEqual(harness.queue.finished.current, ["T1", "T2"])
    }
}
