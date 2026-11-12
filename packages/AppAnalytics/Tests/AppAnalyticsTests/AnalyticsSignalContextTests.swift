import XCTest
import SwiftSignalKit
@testable import AppAnalytics

final class AnalyticsSignalContextTests: XCTestCase {
    func testRevokedOrdinaryDeliveryAndCleanupCannotFreshenDescendantScopes() {
        let analytics = hub()
        let context = analytics.captureContext(owner: owner, privacy: .ordinary)
        var emit: (() -> Void)?
        var values = 0
        var cleanups = 0
        let source = Signal<Int, NoError> { subscriber in
            emit = { subscriber.putNext(1) }
            return ActionDisposable {
                cleanups += 1
                XCTAssertNil(analytics.captureContext(owner: self.owner, privacy: .ordinary).scope)
            }
        }
        let disposable = context.preservingPresentation(source).start(next: { _ in
            values += 1
            let fresh = analytics.captureContext(owner: self.owner, privacy: .ordinary)
            XCTAssertNil(fresh.scope)
            analytics.send(AnalyticsEvents.appForeground(), scope: fresh.scope)
        })
        let secret = analytics.excludedContext().beginPresentation()
        secret.end()
        XCTAssertFalse(context.scope?.isValid ?? true)
        XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        emit?()
        XCTAssertEqual(values, 1)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        disposable.dispose()
        XCTAssertEqual(cleanups, 1)
        XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
    }

    private enum Failure: Error {
        case expected
    }

    private let owner = NSObject()
    private var sent: [String] = []

    private func hub() -> Analytics {
        let analytics = Analytics(clock: { 0 })
        analytics.setSink({ [unowned self] name, _ in self.sent.append(name) }, owner: owner)
        analytics.isEnabled = true
        return analytics
    }

    func testPrivateSignalExcludesProducerAndCallbacksOnlyWhenSubscribed() {
        let analytics = hub()
        let original = analytics.captureContext(owner: owner, privacy: .ordinary)
        var values: [Int] = []
        var completed = false
        let source = Signal<Int, NoError> { subscriber in
            XCTAssertNil(analytics.captureContext(owner: self.owner, privacy: .ordinary).scope)
            subscriber.putNext(42)
            subscriber.putCompletion()
            return EmptyDisposable
        }
        let protected = analytics.excludedContext().preservingPresentation(source)
        XCTAssertTrue(original.scope?.isValid == true)
        let disposable = protected.start(next: { value in
            values.append(value)
            analytics.send(AnalyticsEvents.appForeground(), scope: original.scope)
            XCTAssertNil(analytics.captureContext(owner: self.owner, privacy: .ordinary).scope)
        }, completed: {
            completed = true
            XCTAssertNil(analytics.captureContext(owner: self.owner, privacy: .ordinary).scope)
        })
        XCTAssertEqual(values, [42])
        XCTAssertTrue(completed)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertFalse(original.scope?.isValid ?? true)
        XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        disposable.dispose()
    }

    func testOrdinarySignalPreservesFunctionalValuesAndExistingScope() {
        let analytics = hub()
        let context = analytics.captureContext(owner: owner, privacy: .ordinary)
        var values: [Int] = []
        let disposable = context.preservingPresentation(Signal<Int, NoError>.single(7)).start(next: { value in
            values.append(value)
            XCTAssertTrue(context.scope?.isValid == true)
            analytics.send(AnalyticsEvents.appForeground(), scope: context.scope)
        })
        XCTAssertEqual(values, [7])
        XCTAssertEqual(sent, ["app.foreground"])
        XCTAssertTrue(context.scope?.isValid == true)
        disposable.dispose()
    }

    func testSignalFailureReleasesExclusionAfterErrorCallback() {
        let analytics = hub()
        var failed = false
        let disposable = analytics.excludedContext().preservingPresentation(Signal<Int, Failure>.fail(.expected)).start(error: { error in
            XCTAssertEqual(error, .expected)
            failed = true
            XCTAssertNil(analytics.captureContext(owner: self.owner, privacy: .ordinary).scope)
        })
        XCTAssertTrue(failed)
        XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        disposable.dispose()
    }

    func testExplicitDisposalKeepsExclusionThroughSourceCleanupAndRunsOnce() {
        let analytics = hub()
        var cleanupCount = 0
        let source = Signal<Int, NoError> { _ in
            return ActionDisposable {
                cleanupCount += 1
                XCTAssertNil(analytics.captureContext(owner: self.owner, privacy: .ordinary).scope)
            }
        }
        let disposable = analytics.excludedContext().preservingPresentation(source).start()
        XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        disposable.dispose()
        disposable.dispose()
        XCTAssertEqual(cleanupCount, 1)
        XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
    }

    func testOverlappingSubscriptionsKeepIndependentExclusionLifetimes() {
        let analytics = hub()
        let protected = analytics.excludedContext().preservingPresentation(Signal<Int, NoError>.never())
        let first = protected.start()
        let second = protected.start()
        first.dispose()
        XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        second.dispose()
        XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
    }

    func testDeferredPrivateResultStaysExcludedAfterParentEnds() {
        let analytics = hub()
        let context = analytics.excludedContext()
        let parent = context.beginPresentation()
        var deliver: ((Int) -> Void)?
        var values: [Int] = []
        let source = Signal<Int, NoError> { subscriber in
            deliver = { value in subscriber.putNext(value) }
            return EmptyDisposable
        }
        let disposable = context.preservingPresentation(source).start(next: { value in
            values.append(value)
            XCTAssertNil(analytics.captureContext(owner: self.owner, privacy: .ordinary).scope)
        })
        parent.end()
        deliver?(3)
        XCTAssertEqual(values, [3])
        XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        disposable.dispose()
        deliver?(4)
        XCTAssertEqual(values, [3])
        XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
    }

    func testOrdinarySubscriptionCannotRenewRevokedCapturedScope() {
        let analytics = hub()
        let context = analytics.captureContext(owner: owner, privacy: .ordinary)
        let source = context.preservingPresentation(Signal<Int, NoError>.single(1))
        let privatePresentation = analytics.excludedContext().beginPresentation()
        privatePresentation.end()
        let disposable = source.start(next: { _ in
            analytics.send(AnalyticsEvents.appForeground(), scope: context.scope)
        })
        XCTAssertTrue(sent.isEmpty)
        XCTAssertFalse(context.scope?.isValid ?? true)
        XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        disposable.dispose()
    }

    func testPrivateResultTransfersExclusionToChildBeforeSourceCleanup() {
        let analytics = hub()
        let original = analytics.captureContext(owner: owner, privacy: .ordinary)
        let context = analytics.excludedContext()
        let editor = context.beginPresentation()
        var child: AnalyticsPresentation?
        var sourceCleaned = false
        let source = Signal<Int, NoError> { subscriber in
            subscriber.putNext(1)
            subscriber.putCompletion()
            return ActionDisposable {
                sourceCleaned = true
                XCTAssertNil(analytics.captureContext(owner: self.owner, privacy: .ordinary).scope)
            }
        }
        let disposable = context.preservingPresentation(source).start(next: { _ in
            editor.end()
            XCTAssertNil(analytics.captureContext(owner: self.owner, privacy: .ordinary).scope)
            child = context.beginPresentation()
        })
        XCTAssertTrue(sourceCleaned)
        disposable.dispose()
        XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        analytics.send(AnalyticsEvents.appForeground(), scope: original.scope)
        XCTAssertTrue(sent.isEmpty)
        child?.end()
        child = nil
        XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        XCTAssertFalse(original.scope?.isValid ?? true)
    }

    func testDeferredFailureKeepsPrivateOriginThroughPasswordAndSuccessHandoffs() {
        let analytics = hub()
        for context in [analytics.excludedContext(), analytics.unresolvedContext()] {
            let parent = context.beginPresentation()
            var failTransfer: (() -> Void)?
            var finishAuthorization: (() -> Void)?
            var password: AnalyticsPresentation?
            var feedback: AnalyticsPresentation?
            var wallet: AnalyticsPresentation?
            var authorization: Disposable?
            var transferCleanup = 0
            var authorizationCleanup = 0
            var successCallbacks = 0
            let transferSource = Signal<Never, Failure> { subscriber in
                failTransfer = { subscriber.putError(.expected) }
                return ActionDisposable {
                    transferCleanup += 1
                    XCTAssertNil(analytics.captureContext(owner: self.owner, privacy: .ordinary).scope)
                }
            }
            let transfer = context.preservingPresentation(transferSource).start(error: { error in
                XCTAssertEqual(error, .expected)
                XCTAssertNil(analytics.captureContext(owner: self.owner, privacy: .ordinary).scope)
                password = context.beginPresentation()
                let authorizationSource = Signal<Never, NoError> { subscriber in
                    finishAuthorization = { subscriber.putCompletion() }
                    return ActionDisposable {
                        authorizationCleanup += 1
                        XCTAssertNil(analytics.captureContext(owner: self.owner, privacy: .ordinary).scope)
                    }
                }
                authorization = context.preservingPresentation(authorizationSource |> afterCompleted {
                    feedback = context.beginPresentation()
                    successCallbacks += 1
                    password?.end()
                    password = nil
                    XCTAssertNil(analytics.captureContext(owner: self.owner, privacy: .ordinary).scope)
                }).start()
            })
            parent.end()
            failTransfer?()
            transfer.dispose()
            XCTAssertEqual(transferCleanup, 1)
            XCTAssertNotNil(password)
            XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
            finishAuthorization?()
            authorization?.dispose()
            authorization = nil
            XCTAssertEqual(successCallbacks, 1)
            XCTAssertEqual(authorizationCleanup, 1)
            XCTAssertNil(password)
            XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
            wallet = context.beginPresentation()
            feedback?.end()
            feedback = nil
            XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
            wallet?.end()
            wallet = nil
            XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
            failTransfer?()
            finishAuthorization?()
            XCTAssertEqual(successCallbacks, 1)
            XCTAssertTrue(sent.isEmpty)
        }
    }

    func testReentrantDisposalDoesNotLiftExclusionInsideDeliveryCallback() {
        let analytics = hub()
        for delivery in 0..<3 {
            var emit: (() -> Void)?
            var disposable: Disposable?
            var cleaned = 0
            var callbacks = 0
            let source = Signal<Int, Failure> { subscriber in
                emit = {
                    switch delivery {
                    case 0: subscriber.putNext(1)
                    case 1: subscriber.putError(.expected)
                    default: subscriber.putCompletion()
                    }
                }
                return ActionDisposable {
                    cleaned += 1
                    XCTAssertNil(analytics.captureContext(owner: self.owner, privacy: .ordinary).scope)
                }
            }
            let delivered = {
                callbacks += 1
                disposable?.dispose()
                XCTAssertNil(analytics.captureContext(owner: self.owner, privacy: .ordinary).scope)
            }
            disposable = analytics.excludedContext().preservingPresentation(source).start(next: { _ in delivered() }, error: { _ in delivered() }, completed: delivered)
            emit?()
            XCTAssertEqual(callbacks, 1)
            XCTAssertEqual(cleaned, 1)
            XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
            emit?()
            XCTAssertEqual(callbacks, 1)
            disposable = nil
        }
        XCTAssertTrue(sent.isEmpty)
    }

}
