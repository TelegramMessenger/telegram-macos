extension ForwardObjectTests {
    func testComposerPreparationMutationCancelsLookupWithoutSendingClearingOrScrolling() {
        for scheduled in [false, true] {
            let controller = ChatController(account, .peer(3))
            let origin = origin()
            let task = ComposerSubmission(origin)
            let group = ComposerGroup(task)
            var source: Subscriber<[Message], NoError>?
            var disposed = 0, texts = 0, clears = 0, scrolls = 0
            account.account.postbox.composerMessages = Signal { observer in
                source = observer
                return ActionDisposable { disposed += 1 }
            }
            let completed = expectation(description: "invalidated lookup")
            let disposable = composerForwardPipeline(controller: controller, origin: origin, requested: [sourceId], task: task, group: group, scheduledAt: scheduled ? Date() : nil, afterSentTransition: { clears += 1 }, scrollAfterSend: { scrolls += 1 }, makeTextSignal: { _ in texts += 1; return .complete() }).start(completed: { completed.fulfill() })
            XCTAssertTrue(controller.chatInteraction.isPreparingForwardSend)
            XCTAssertEqual(controller.nextTransaction.armed, 0)
            XCTAssertEqual(clears, 0)
            controller.chatInteraction.invalidateDeferredSendActions()
            source?.putNext([Message(id: sourceId)])
            wait(for: [completed], timeout: 2)
            XCTAssertFalse(controller.chatInteraction.isPreparingForwardSend)
            XCTAssertEqual(disposed, 1)
            XCTAssertEqual(texts, 0)
            XCTAssertEqual(clears, 0)
            XCTAssertEqual(scrolls, 0)
            XCTAssertEqual(controller.nextTransaction.armed, 0)
            XCTAssertTrue(task.discarded)
            XCTAssertTrue(UI.forwarded.isEmpty)
            XCTAssertEqual(group.recorded, 0)
            disposable.dispose()
            source = nil
        }
    }
    func testComposerPreparationArmsTransitionOnlyWhenCurrentLookupCanSend() {
        for scheduled in [false, true] {
            UI.reset()
            let controller = ChatController(account, .peer(3))
            let origin = origin()
            var source: Subscriber<[Message], NoError>?
            account.account.postbox.composerMessages = Signal { observer in source = observer; return EmptyDisposable }
            var texts = 0, clears = 0, scrolls = 0
            let completed = expectation(description: "current lookup sent")
            let disposable = composerForwardPipeline(controller: controller, origin: origin, requested: [sourceId], task: nil, group: nil, scheduledAt: scheduled ? Date() : nil, afterSentTransition: {
                clears += 1
                controller.chatInteraction.invalidateDeferredSendActions()
            }, scrollAfterSend: { scrolls += 1 }, makeTextSignal: { _ in texts += 1; return .complete() }).start(completed: { completed.fulfill() })
            XCTAssertEqual(texts, 0)
            XCTAssertEqual(clears, 0)
            XCTAssertEqual(controller.nextTransaction.armed, 0)
            source?.putNext([Message(id: sourceId)])
            wait(for: [completed], timeout: 2)
            XCTAssertEqual(texts, 1)
            XCTAssertEqual(UI.forwarded, [[sourceId]])
            XCTAssertEqual(scrolls, 1)
            XCTAssertFalse(controller.chatInteraction.isPreparingForwardSend)
            if !scheduled { controller.nextTransaction.execute() }
            XCTAssertEqual(clears, 1)
            XCTAssertEqual(controller.nextTransaction.armed, scheduled ? 0 : 1)
            disposable.dispose()
            source = nil
        }
    }
    func testComposerPreparationRejectsDuplicateWithoutReplacingOriginal() {
        let owner = ChatForwardSendPreparation()
        var source: Subscriber<Int, NoError>?
        var builds = 0, firstInvalidations = 0, secondInvalidations = 0
        var values: [Int] = []
        let first = owner.prepare(isCurrent: { true }, invalidated: { firstInvalidations += 1 }, request: {
            builds += 1
            return Signal { observer in source = observer; return EmptyDisposable }
        }).start(next: { values.append($0) })
        let second = owner.prepare(isCurrent: { true }, invalidated: { secondInvalidations += 1 }, request: { builds += 1; return .single(2) }).start(next: { values.append($0) })
        XCTAssertEqual(builds, 1)
        XCTAssertEqual(secondInvalidations, 1)
        XCTAssertTrue(owner.isPending)
        source?.putNext(1)
        XCTAssertEqual(values, [1])
        XCTAssertEqual(firstInvalidations, 0)
        XCTAssertFalse(owner.isPending)
        first.dispose()
        second.dispose()
        source = nil
    }
    func testComposerPreparationRejectsChangedGuardAtDeliveryWithoutExplicitReset() {
        let owner = ChatForwardSendPreparation()
        var current = true, invalidations = 0
        var source: Subscriber<Int, NoError>?
        let disposable = owner.prepare(isCurrent: { current }, invalidated: { invalidations += 1 }, request: {
            Signal { observer in source = observer; return EmptyDisposable }
        }).start(next: { _ in XCTFail("stale delivery") })
        current = false
        source?.putNext(1)
        XCTAssertEqual(invalidations, 1)
        XCTAssertFalse(owner.isPending)
        disposable.dispose()
        XCTAssertEqual(invalidations, 1)
        source = nil
    }
    func testComposerPreparationResetDuringConstructionNeverSubscribesOldSource() {
        let owner = ChatForwardSendPreparation()
        var invalidations = 0, subscriptions = 0
        let disposable = owner.prepare(isCurrent: { true }, invalidated: { invalidations += 1 }, request: {
            owner.reset()
            return Signal<Int, NoError> { _ in subscriptions += 1; return EmptyDisposable }
        }).start(next: { _ in XCTFail("invalid construction") })
        XCTAssertEqual(invalidations, 1)
        XCTAssertEqual(subscriptions, 0)
        XCTAssertFalse(owner.isPending)
        disposable.dispose()
    }
    func testComposerPreparationDisposalCanStartReplacementWithoutOldCleanupCancellingIt() {
        let owner = ChatForwardSendPreparation()
        var firstInvalidations = 0, replacementInvalidations = 0
        var replacement: Disposable?
        var replacementSource: Subscriber<Int, NoError>?
        var values: [Int] = []
        let first = owner.prepare(isCurrent: { true }, invalidated: { firstInvalidations += 1 }, request: {
            Signal<Int, NoError> { _ in ActionDisposable {
                replacement = owner.prepare(isCurrent: { true }, invalidated: { replacementInvalidations += 1 }, request: {
                    Signal { observer in replacementSource = observer; return EmptyDisposable }
                }).start(next: { values.append($0) })
            } }
        }).start()
        owner.reset()
        first.dispose()
        XCTAssertEqual(firstInvalidations, 1)
        XCTAssertTrue(owner.isPending)
        replacementSource?.putNext(2)
        XCTAssertEqual(values, [2])
        XCTAssertEqual(replacementInvalidations, 0)
        replacement?.dispose()
        replacement = nil
        replacementSource = nil
    }
    func testComposerPreparationOwnerReleaseCancelsPendingSource() {
        var owner: ChatForwardSendPreparation? = ChatForwardSendPreparation()
        var invalidations = 0, disposals = 0, completions = 0
        let disposable = owner!.prepare(isCurrent: { true }, invalidated: { invalidations += 1 }, request: {
            Signal<Int, NoError> { _ in ActionDisposable { disposals += 1 } }
        }).start(completed: { completions += 1 })
        weak var released = owner
        owner = nil
        XCTAssertNil(released)
        XCTAssertEqual(disposals, 1)
        XCTAssertEqual(invalidations, 1)
        XCTAssertEqual(completions, 1)
        disposable.dispose()
    }
    func testComposerPreparationEmptyCompletionDiscardsTaskAndLeavesDraftAlone() {
        let controller = ChatController(account, .peer(3))
        let origin = origin()
        let task = ComposerSubmission(origin)
        account.account.postbox.composerMessages = .complete()
        var texts = 0, clears = 0, scrolls = 0
        let completed = expectation(description: "empty lookup completion")
        let disposable = composerForwardPipeline(controller: controller, origin: origin, requested: [sourceId], task: task, group: nil, afterSentTransition: { clears += 1 }, scrollAfterSend: { scrolls += 1 }, makeTextSignal: { _ in texts += 1; return .complete() }).start(completed: { completed.fulfill() })
        wait(for: [completed], timeout: 2)
        XCTAssertTrue(task.discarded)
        XCTAssertEqual(texts, 0)
        XCTAssertEqual(clears, 0)
        XCTAssertEqual(scrolls, 0)
        XCTAssertEqual(controller.nextTransaction.armed, 0)
        disposable.dispose()
    }
}

extension ForwardObjectTests {
    func testComposerPreparationControllerReleaseCancelsLookupWithoutRetainCycle() {
        var controller: ChatController? = ChatController(account, .peer(3))
        let origin = origin()
        let task = ComposerSubmission(origin)
        var disposed = false
        account.account.postbox.composerMessages = Signal { _ in ActionDisposable { disposed = true } }
        let completed = expectation(description: "released controller")
        let disposable = composerForwardPipeline(controller: controller!, origin: origin, requested: [sourceId], task: task, group: nil, makeTextSignal: { _ in XCTFail("released text sender"); return .complete() }).start(completed: { completed.fulfill() })
        weak var released = controller
        controller = nil
        XCTAssertNil(released)
        wait(for: [completed], timeout: 2)
        XCTAssertTrue(disposed)
        XCTAssertTrue(task.discarded)
        XCTAssertTrue(UI.forwarded.isEmpty)
        disposable.dispose()
    }
    func testComposerPreparationReplacementDuringConstructionSurvivesOldAdmissionCheck() {
        let owner = ChatForwardSendPreparation()
        var replacement: Disposable?
        var source: Subscriber<Int, NoError>?
        var oldSubscriptions = 0, oldInvalidations = 0, newInvalidations = 0
        var values: [Int] = []
        let first = owner.prepare(isCurrent: { true }, invalidated: { oldInvalidations += 1 }, request: {
            owner.reset()
            replacement = owner.prepare(isCurrent: { true }, invalidated: { newInvalidations += 1 }, request: {
                Signal { observer in source = observer; return EmptyDisposable }
            }).start(next: { values.append($0) })
            return Signal<Int, NoError> { _ in oldSubscriptions += 1; return EmptyDisposable }
        }).start()
        XCTAssertTrue(owner.isPending)
        XCTAssertEqual(oldInvalidations, 1)
        XCTAssertEqual(oldSubscriptions, 0)
        source?.putNext(2)
        XCTAssertEqual(values, [2])
        XCTAssertEqual(newInvalidations, 0)
        first.dispose()
        replacement?.dispose()
        replacement = nil
        source = nil
    }
}
