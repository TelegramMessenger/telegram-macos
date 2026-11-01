import Foundation
import XCTest
import SwiftSignalKit

typealias MessageId = Int
struct Message: Equatable { let id: Int }
__SOURCES__

final class LifecycleTests: XCTestCase {
    let key = ChatRichTextDraftKey(accountId: 1, peerId: 2, threadId: nil, isWelcome: false)

    func testDraftChangesInvalidatePendingSendEvenAfterUndo() {
        let store = ChatRichTextDraftStore<String>()
        store.set("first", for: key)
        let revision = store.captureRevision(for: key)
        store.set("second", for: key)
        store.set("first", for: key)
        XCTAssertFalse(revision.isValid)
        XCTAssertEqual(store.value(for: key), "first")
    }

    func testUnchangedDraftKeepsRevision() {
        let store = ChatRichTextDraftStore<String>()
        store.set("first", for: key)
        let revision = store.captureRevision(for: key)
        XCTAssertFalse(store.set("first", for: key))
        XCTAssertTrue(revision.isValid)
    }

    func testDraftKeysAreIsolatedAndClearingInvalidates() {
        let store = ChatRichTextDraftStore<String>()
        store.set("first", for: key)
        let revision = store.captureRevision(for: key)
        for other in [ChatRichTextDraftKey(accountId: 3, peerId: 2, threadId: nil, isWelcome: false), ChatRichTextDraftKey(accountId: 1, peerId: 3, threadId: nil, isWelcome: false), ChatRichTextDraftKey(accountId: 1, peerId: 2, threadId: 0, isWelcome: false), ChatRichTextDraftKey(accountId: 1, peerId: 2, threadId: nil, isWelcome: true), ChatRichTextDraftKey(accountId: 1, peerId: 2, threadId: nil, isWelcome: false, isCustomEditor: true)] {
            store.set("other", for: other)
            XCTAssertTrue(revision.isValid)
        }
        store.set(nil, for: key)
        XCTAssertFalse(revision.isValid)
        XCTAssertNil(store.value(for: key))
    }

    func testDeferredSendIsConsumedOnce() {
        let action = ChatDeferredSendAction { true }
        XCTAssertTrue(action.isAvailable)
        XCTAssertTrue(action.takeIfCurrent())
        XCTAssertFalse(action.takeIfCurrent())
        XCTAssertFalse(action.isAvailable)
    }

    func testInvalidDeferredSendCannotBeRevived() {
        var current = false
        var invalidations = 0
        let action = ChatDeferredSendAction { current }
        XCTAssertFalse(action.takeIfCurrent { invalidations += 1 })
        current = true
        XCTAssertFalse(action.takeIfCurrent { invalidations += 1 })
        XCTAssertEqual(invalidations, 1)
    }

    func testPreviewNewActionInvalidatesOldAndCloseInvalidatesAll() {
        let actions = PreviewSenderPendingActions()
        let first = actions.captureToken()
        let second = actions.captureToken()
        XCTAssertFalse(first.take())
        XCTAssertTrue(second.take())
        XCTAssertFalse(second.take())
        let third = actions.captureToken()
        actions.close()
        XCTAssertFalse(third.take())
        XCTAssertFalse(actions.captureToken().take())
    }

    func testPreviewTokenDoesNotRetainOwner() {
        var actions: PreviewSenderPendingActions? = PreviewSenderPendingActions()
        weak var owner = actions
        let token = actions!.captureToken()
        actions = nil
        XCTAssertNil(owner)
        XCTAssertFalse(token.take())
    }

    func testChildActionRevalidatesAndDoesNotRepeat() {
        var current = false
        var calls = 0
        let invalid = PreviewSenderChildAction { current }
        invalid.resolve { calls += 1 }
        current = true
        invalid.resolve { calls += 1 }
        let valid = PreviewSenderChildAction { current }
        valid.resolve { calls += 1 }
        valid.resolve { calls += 1 }
        XCTAssertEqual(calls, 1)
    }

    func testDismissalAllowsSameTurnResultButRejectsLateResult() {
        let child = PreviewSenderChildAction { true }
        let browser = BrowserDecision()
        var calls = 0
        child.dismissed()
        browser.dismissed()
        browser.resolve { calls += 1 }
        let done = expectation(description: "dismissal settled")
        DispatchQueue.main.async {
            child.resolve { calls += 1 }
            browser.resolve { calls += 1 }
            XCTAssertEqual(calls, 1)
            done.fulfill()
        }
        wait(for: [done], timeout: 2)
    }

    func testForwardSelectionResetDiscardsLateLookup() {
        let selection = ChatForwardSelection()
        var subscriber: Subscriber<[Message], NoError>?
        var disposed = 0
        var delivered: [[Message]] = []
        selection.load(ids: [1], request: {
            Signal { observer in
                subscriber = observer
                return ActionDisposable { disposed += 1 }
            }
        }, completion: { delivered.append($0) })
        selection.reset()
        subscriber?.putNext([Message(id: 1)])
        XCTAssertEqual(disposed, 1)
        XCTAssertTrue(delivered.isEmpty)
    }

    func testForwardSelectionRejectsDuplicateAndDeliversOnce() {
        let selection = ChatForwardSelection()
        var subscriber: Subscriber<[Message], NoError>?
        var builds = 0
        var delivered: [[Message]] = []
        let request: () -> Signal<[Message], NoError> = {
            builds += 1
            return Signal { observer in subscriber = observer; return EmptyDisposable }
        }
        selection.load(ids: [1], request: request, completion: { delivered.append($0) })
        selection.load(ids: [1], request: request, completion: { delivered.append($0) })
        subscriber?.putNext([Message(id: 1)])
        subscriber?.putNext([Message(id: 2)])
        XCTAssertEqual(builds, 1)
        XCTAssertEqual(delivered, [[Message(id: 1)]])
    }

    func testForwardPreparationChecksValidityAgainAtDelivery() {
        let owner = ChatForwardSendPreparation()
        var current = true
        var subscriber: Subscriber<Int, NoError>?
        var invalidations = 0
        var values: [Int] = []
        let disposable = owner.prepare(isCurrent: { current }, invalidated: { invalidations += 1 }, request: {
            Signal { observer in subscriber = observer; return EmptyDisposable }
        }).start(next: { values.append($0) })
        current = false
        subscriber?.putNext(1)
        XCTAssertFalse(owner.isPending)
        XCTAssertEqual(invalidations, 1)
        XCTAssertTrue(values.isEmpty)
        disposable.dispose()
    }

    func testForwardPreparationKeepsOriginalOnDuplicate() {
        let owner = ChatForwardSendPreparation()
        var subscriber: Subscriber<Int, NoError>?
        var invalidations = 0
        var values: [Int] = []
        let first = owner.prepare(isCurrent: { true }, invalidated: { XCTFail("Original request invalidated") }, request: {
            Signal { observer in subscriber = observer; return EmptyDisposable }
        }).start(next: { values.append($0) })
        let second = owner.prepare(isCurrent: { true }, invalidated: { invalidations += 1 }, request: { .single(2) }).start(next: { values.append($0) })
        subscriber?.putNext(1)
        XCTAssertEqual(values, [1])
        XCTAssertEqual(invalidations, 1)
        XCTAssertFalse(owner.isPending)
        first.dispose()
        second.dispose()
    }
}
